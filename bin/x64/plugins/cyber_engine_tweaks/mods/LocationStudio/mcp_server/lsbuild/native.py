from __future__ import annotations

import copy
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .build import inspect_export, _read_json

TEMPLATE_SCHEMA = "cp77wb-wkit-templates/1"
NATIVE_JSON_SCHEMA = "cp77wb-native-json/1"
DEFAULT_WKIT_VERSION = "9.0.1"
DEFAULT_WKIT_JSON_VERSION = "0.0.8"

BASE_TYPES = (
    "worldStreamingSector",
    "gameDeviceResource",
    "gamePersistentStateDataResource",
    "worldStreamingBlock",
    "worldStreamingSectorDescriptor",
    "worldStreamingSectorVariant",
)


def required_template_types(export_file: str | Path) -> list[str]:
    data = _read_json(export_file)
    types = set(BASE_TYPES)
    for sector in data.get("sectors", []):
        if not isinstance(sector, dict):
            continue
        for node in sector.get("nodes", []):
            if isinstance(node, dict) and isinstance(node.get("type"), str) and node["type"]:
                types.add(node["type"])
    return sorted(types)


def make_template_capture_script(export_file: str | Path, output: str | Path, *, resource_name: str | None = None) -> dict[str, Any]:
    export_file = Path(export_file)
    types = required_template_types(export_file)
    data = _read_json(export_file)
    resource_name = resource_name or f"cp77wb_templates_{data.get('name', export_file.stem)}.json"
    js_types = json.dumps(types, ensure_ascii=False)
    script = f'''// cp77wb v0.9 RED type template capture\n// Run once in WolvenKit Script Manager. The output is written to the project's resources folder.\n\nconst schema = "{TEMPLATE_SCHEMA}";\nconst outputFile = {json.dumps(resource_name)};\nconst types = {js_types};\n\nexport function RunCp77wbTemplateCapture() {{\n  const result = {{ schema, generatedBy: "WolvenKit CreateInstanceAsJSON", types: {{}} }};\n  for (const type of types) {{\n    try {{\n      result.types[type] = JSON.parse(wkit.CreateInstanceAsJSON(type));\n    }} catch (e) {{\n      result.types[type] = {{ "__cp77wb_error": String(e) }};\n    }}\n  }}\n  wkit.SaveToResources(outputFile, JSON.stringify(result));\n}}\n\nRunCp77wbTemplateCapture();\n'''
    out = Path(output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(script, encoding="utf-8")
    return {"script": str(out), "resource": resource_name, "requiredTypes": types, "count": len(types)}


def load_template_bundle(path: str | Path) -> dict[str, Any]:
    p = Path(path)
    data = json.loads(p.read_text(encoding="utf-8-sig"))
    if not isinstance(data, dict) or data.get("schema") != TEMPLATE_SCHEMA:
        raise ValueError(f"Unsupported template bundle schema in {p}; expected {TEMPLATE_SCHEMA}")
    types = data.get("types")
    if not isinstance(types, dict):
        raise ValueError("Template bundle requires an object named 'types'")
    return data


def verify_template_bundle(export_file: str | Path, bundle_file: str | Path) -> dict[str, Any]:
    bundle = load_template_bundle(bundle_file)
    required = required_template_types(export_file)
    types = bundle["types"]
    missing = [t for t in required if t not in types]
    failed = [t for t in required if isinstance(types.get(t), dict) and "__cp77wb_error" in types[t]]
    usable = [t for t in required if t in types and t not in failed]
    return {
        "schema": TEMPLATE_SCHEMA,
        "export": str(export_file),
        "bundle": str(bundle_file),
        "required": required,
        "requiredCount": len(required),
        "usableCount": len(usable),
        "missing": missing,
        "failed": failed,
        "valid": not missing and not failed,
    }


def _template(bundle: dict[str, Any], type_name: str) -> dict[str, Any]:
    value = bundle["types"].get(type_name)
    if not isinstance(value, dict) or "__cp77wb_error" in value:
        raise ValueError(f"Template bundle has no usable RED type {type_name!r}")
    return copy.deepcopy(value)


def _header(bundle: dict[str, Any], root_chunk: dict[str, Any]) -> dict[str, Any]:
    return {
        "Header": {
            "WolvenKitVersion": str(bundle.get("wolvenKitVersion") or DEFAULT_WKIT_VERSION),
            "WKitJsonVersion": str(bundle.get("wkitJsonVersion") or DEFAULT_WKIT_JSON_VERSION),
            "DataType": "CR2W",
        },
        "Data": {"Version": 195, "BuildVersion": 0, "RootChunk": root_chunk, "EmbeddedFiles": []},
    }


def _deep_copy(origin: Any, target: Any) -> Any:
    if isinstance(origin, dict) and isinstance(target, dict):
        for key, value in origin.items():
            if isinstance(value, dict):
                child = target.get(key)
                if not isinstance(child, dict):
                    child = {}
                    target[key] = child
                _deep_copy(value, child)
            elif isinstance(value, list):
                child = target.get(key)
                if not isinstance(child, list):
                    target[key] = copy.deepcopy(value)
                else:
                    target[key] = copy.deepcopy(value)
            else:
                target[key] = value
        return target
    return copy.deepcopy(origin)


def _reorder_json_by_type(data: Any) -> Any:
    if isinstance(data, list):
        return [_reorder_json_by_type(x) for x in data]
    if isinstance(data, dict):
        out: dict[str, Any] = {}
        priority = ("$type", "ShapeType", "BufferId", "Flags", "Type")
        for key in priority:
            if key in data:
                out[key] = _reorder_json_by_type(data[key])
        for key, value in data.items():
            if key not in priority:
                out[key] = _reorder_json_by_type(value)
        return out
    return data


def _sort_instance_data(data: dict[str, Any]) -> None:
    try:
        buf = data["instanceData"]["Data"]["buffer"]["Data"]
        chunks = buf["Chunks"]
        cruids = buf["CruidDict"]
        if not isinstance(chunks, list) or not isinstance(cruids, dict):
            return
        result = [x for x in chunks if isinstance(x, dict) and x.get("id") is None]
        for _, cruid in cruids.items():
            result.extend(x for x in chunks if isinstance(x, dict) and x.get("id") == cruid)
        buf["Chunks"] = result
    except (KeyError, TypeError):
        return


def _fnv1a(data: bytes, bits: int) -> int:
    if bits == 64:
        h, prime, mask = 0xCBF29CE484222325, 0x100000001B3, 0xFFFFFFFFFFFFFFFF
    elif bits == 32:
        h, prime, mask = 0x811C9DC5, 0x01000193, 0xFFFFFFFF
    else:
        raise ValueError(bits)
    for b in data:
        h ^= b
        h = (h * prime) & mask
    return h


def _json_stringify(value: Any) -> str:
    # Match JSON.stringify's compact separators and preserve insertion order.
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), allow_nan=False)


def _new_world_node_data() -> dict[str, Any]:
    return {
        "Id": "0", "NodeIndex": 0,
        "Position": {"$type": "Vector4", "W": 0, "X": 0, "Y": 0, "Z": 0},
        "Orientation": {"$type": "Quaternion", "i": 0, "j": 0, "k": 0, "r": 1},
        "Scale": {"$type": "Vector3", "X": 0, "Y": 0, "Z": 0},
        "Pivot": {"$type": "Vector3", "X": 0, "Y": 0, "Z": 0},
        "Bounds": {
            "$type": "Box",
            "Max": {"$type": "Vector4", "W": 0, "X": 0, "Y": 0, "Z": 0},
            "Min": {"$type": "Vector4", "W": 0, "X": 0, "Y": 0, "Z": 0},
        },
        "QuestPrefabRefHash": {"$type": "NodeRef", "$storage": "uint64", "$value": "0"},
        "UkHash1": {"$type": "NodeRef", "$storage": "uint64", "$value": "0"},
        "CookedPrefabData": {"DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"}, "Flags": "Default"},
        "MaxStreamingDistance": 0, "UkFloat1": 0, "Uk10": 0, "Uk11": 0, "Uk12": 0, "Uk13": "0", "Uk14": "0",
    }


def _insert_node(sector: dict[str, Any], node: dict[str, Any], bundle: dict[str, Any]) -> None:
    root = sector["Data"]["RootChunk"]
    node_data = _new_world_node_data()
    pos = node["position"]
    ref = node.get("streamingRefPoint") or pos
    node_data["NodeIndex"] = len(root["nodes"])
    node_data["Position"].update({"X": pos["x"], "Y": pos["y"], "Z": pos["z"]})
    node_data["MaxStreamingDistance"] = node.get("secondaryRange", 0)
    node_data["UkFloat1"] = node.get("primaryRange", 0)
    node_data["Uk10"] = node.get("uk10", 0)
    node_data["Uk11"] = node.get("uk11", 0)
    node_data["Pivot"].update({"X": ref["x"], "Y": ref["y"], "Z": ref["z"]})
    node_data["Bounds"]["Max"].update({"X": pos["x"], "Y": pos["y"], "Z": pos["z"]})
    node_data["Bounds"]["Min"].update({"X": ref["x"], "Y": ref["y"], "Z": ref["z"]})
    scale = node["scale"]
    node_data["Scale"].update({"X": scale["x"], "Y": scale["y"], "Z": scale["z"]})
    rot = node["rotation"]
    node_data["Orientation"].update({"i": rot["i"], "j": rot["j"], "k": rot["k"], "r": rot["r"]})
    node_ref = node.get("nodeRef")
    if isinstance(node_ref, str) and node_ref:
        node_data["QuestPrefabRefHash"].update({"$storage": "string", "$value": node_ref})
        root["nodeRefs"].append({"$type": "NodeRef", "$storage": "string", "$value": node_ref})
    else:
        node_data["QuestPrefabRefHash"]["$value"] = str(_fnv1a(_json_stringify(node_data).encode("utf-8"), 64))
    root["nodeData"]["Data"].append(node_data)

    world_node = _template(bundle, str(node["type"]))
    node_payload = _reorder_json_by_type(copy.deepcopy(node.get("data") or {}))
    _sort_instance_data(node_payload)
    _deep_copy(node_payload, world_node)
    debug_name = world_node.get("debugName")
    if isinstance(debug_name, dict):
        debug_name["$value"] = node.get("name") or ""
    else:
        world_node["debugName"] = {"$type": "CName", "$storage": "string", "$value": node.get("name") or ""}
    root["nodes"].append({"HandleId": str(len(root["nodes"])), "Data": world_node})


def _create_sector(bundle: dict[str, Any], info: dict[str, Any]) -> dict[str, Any]:
    root_chunk = _template(bundle, "worldStreamingSector")
    sector = _header(bundle, root_chunk)
    root = sector["Data"]["RootChunk"]
    root["nodeData"] = root.get("nodeData") or {}
    root["nodeData"]["Type"] = "WolvenKit.RED4.Archive.Buffer.worldNodeDataBuffer, WolvenKit.RED4, Version=8.13.0.0, Culture=neutral, PublicKeyToken=null"
    root["nodeData"]["Data"] = []
    root.setdefault("nodes", [])
    root.setdefault("nodeRefs", [])
    root["category"] = info.get("category")
    root["level"] = info.get("level")
    root["variantIndices"] = copy.deepcopy(info.get("variantIndices") or [0])
    root["version"] = 62
    return sector


def _js_abs_i32(value: int) -> int:
    value &= 0xFFFFFFFF
    if value >= 0x80000000:
        value -= 0x100000000
    return abs(value)


def _add_sector_to_block(block: dict[str, Any], info: dict[str, Any], root_name: str, bundle: dict[str, Any]) -> None:
    desc = _template(bundle, "worldStreamingSectorDescriptor")
    desc["category"] = info.get("category")
    desc["level"] = info.get("level")
    variants_value = info.get("variants")
    variants = variants_value if isinstance(variants_value, list) else []
    desc["numNodeRanges"] = 1 + len(variants)
    desc["streamingBox"]["Max"].update({"X": info["max"]["x"], "Y": info["max"]["y"], "Z": info["max"]["z"]})
    desc["streamingBox"]["Min"].update({"X": info["min"]["x"], "Y": info["min"]["y"], "Z": info["min"]["z"]})
    desc["data"]["DepotPath"].update({"$storage": "string", "$value": f"{root_name}/sectors/{info['name']}.streamingsector"})
    prefab_ref = info.get("prefabRef")
    if isinstance(prefab_ref, str) and prefab_ref:
        desc["questPrefabNodeRef"].update({"$storage": "string", "$value": prefab_ref})
    desc.setdefault("variants", [])
    for variant in variants:
        v = _template(bundle, "worldStreamingSectorVariant")
        v["enabledByDefault"] = bool(variant.get("defaultOn"))
        v["name"]["$value"] = variant.get("name", "")
        v["nodeRef"].update({"$storage": "string", "$value": variant.get("ref", "")})
        v["rangeIndex"] = variant.get("index", 0)
        h = _fnv1a((str(variant.get("ref", "")) + str(variant.get("name", ""))).encode("utf-8"), 32)
        v["variantId"] = _js_abs_i32(h)
        desc["variants"].append(v)
    block["Data"]["RootChunk"].setdefault("descriptors", []).append(desc)


def _devices_file(bundle: dict[str, Any], devices: dict[str, Any]) -> dict[str, Any]:
    doc = _header(bundle, _template(bundle, "gameDeviceResource"))
    doc["Data"]["RootChunk"]["data"] = {"Data": {"$type": "gameDeviceResourceData", "unk1": [], "version": 2}}
    out = doc["Data"]["RootChunk"]["data"]["Data"]["unk1"]
    for _, device in devices.items():
        out.append({
            "$type": "gameDeviceResourceData_Cls1",
            "children": copy.deepcopy(device.get("children", [])),
            "className": {"$type": "CName", "$storage": "string", "$value": device.get("className", "")},
            "hash": device.get("hash"),
            "nodePosition": {"$type": "Vector3", "X": device["nodePosition"]["x"], "Y": device["nodePosition"]["y"], "Z": device["nodePosition"]["z"]},
            "parents": copy.deepcopy(device.get("parents", [])),
        })
    return doc


def _ps_file(bundle: dict[str, Any], entries: dict[str, Any]) -> dict[str, Any]:
    doc = _header(bundle, _template(bundle, "gamePersistentStateDataResource"))
    doc["Data"]["RootChunk"]["buffer"] = {
        "BufferId": "0", "Flags": 4063232,
        "Type": "WolvenKit.RED4.Archive.Buffer.RedPackage, WolvenKit.RED4, Version=8.13.0.0, Culture=neutral, PublicKeyToken=null",
        "Data": {"Version": 4, "Sections": 6, "CruidIndex": 0, "CruidDict": {}, "Chunks": []},
    }
    buf = doc["Data"]["RootChunk"]["buffer"]["Data"]
    for index, entry in enumerate(entries.values()):
        buf["Chunks"].append(copy.deepcopy(entry["instanceData"]))
        buf["CruidDict"][str(index)] = entry["PSID"]
    return doc


def prepare_native_json(export_file: str | Path, bundle_file: str | Path, output: str | Path) -> dict[str, Any]:
    report = inspect_export(export_file)
    if not report["valid"]:
        raise ValueError(f"World Builder export has {report['errors']} error(s)")
    coverage = verify_template_bundle(export_file, bundle_file)
    if not coverage["valid"]:
        raise ValueError(f"Template bundle incomplete: missing={coverage['missing']} failed={coverage['failed']}")
    data = _reorder_json_by_type(_read_json(export_file))
    bundle = load_template_bundle(bundle_file)
    out_root = Path(output)
    if out_root.exists():
        shutil.rmtree(out_root)
    out_root.mkdir(parents=True, exist_ok=True)

    files: list[dict[str, str]] = []
    block = _header(bundle, _template(bundle, "worldStreamingBlock"))
    block["Data"]["RootChunk"].setdefault("descriptors", [])
    for info in data.get("sectors", []):
        _add_sector_to_block(block, info, str(data["name"]), bundle)
        sector = _create_sector(bundle, info)
        for node in info.get("nodes", []):
            _insert_node(sector, node, bundle)
        rel = Path(str(data["name"])) / "sectors" / f"{info['name']}.streamingsector.json"
        p = out_root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(sector, ensure_ascii=False, separators=(",", ":"))+"\n", encoding="utf-8")
        files.append({"json": str(p), "target": str(rel)[:-5]})

    if isinstance(data.get("devices"), dict) and data["devices"]:
        rel = Path(str(data["name"])) / "custom_devices.devices.json"
        p = out_root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(_devices_file(bundle, data["devices"]), ensure_ascii=False, separators=(",", ":"))+"\n", encoding="utf-8")
        files.append({"json": str(p), "target": str(rel)[:-5]})
    if isinstance(data.get("psEntries"), dict) and data["psEntries"]:
        rel = Path(str(data["name"])) / "custom_devices.psrep.json"
        p = out_root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(_ps_file(bundle, data["psEntries"]), ensure_ascii=False, separators=(",", ":"))+"\n", encoding="utf-8")
        files.append({"json": str(p), "target": str(rel)[:-5]})

    rel = Path(str(data["name"])) / "all.streamingblock.json"
    p = out_root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(block, ensure_ascii=False, separators=(",", ":"))+"\n", encoding="utf-8")
    files.append({"json": str(p), "target": str(rel)[:-5]})

    manifest = {
        "schema": NATIVE_JSON_SCHEMA,
        "export": str(Path(export_file).resolve()),
        "exportSha256": hashlib.sha256(Path(export_file).read_bytes()).hexdigest(),
        "templateBundle": str(Path(bundle_file).resolve()),
        "templateSha256": hashlib.sha256(Path(bundle_file).read_bytes()).hexdigest(),
        "name": data["name"], "files": files,
    }
    (out_root / ".cp77wb-native-json.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    return {"output": str(out_root), "manifest": str(out_root/".cp77wb-native-json.json"), "files": files, "count": len(files), "coverage": coverage}


def _resolve_cli(cli: str | Path | None) -> str | None:
    if cli:
        p = Path(str(cli))
        if p.exists():
            return str(p.resolve())
        return shutil.which(str(cli))
    return shutil.which("cp77tools") or shutil.which("WolvenKit.CLI") or shutil.which("WolvenKit.CLI.exe")


def native_preflight(*, cli: str | Path | None = None, timeout: int = 30) -> dict[str, Any]:
    path = _resolve_cli(cli)
    result: dict[str, Any] = {
        "cli": path, "found": bool(path), "platform": os.name,
        "convertDeserialize": False, "versionOutput": None, "helpOutput": None,
        "ready": False,
    }
    if not path:
        result["reason"] = "WolvenKit CLI/cp77tools not found"
        return result
    try:
        ver = subprocess.run([path, "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout, check=False)
        result["versionOutput"] = ver.stdout.strip()[-2000:]
    except Exception as exc:
        result["versionError"] = str(exc)
    try:
        help_p = subprocess.run([path, "convert", "deserialize", "--help"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout, check=False)
        text = help_p.stdout or ""
        result["helpOutput"] = text.strip()[-4000:]
        result["convertDeserialize"] = help_p.returncode == 0 and ("deserialize" in text.lower() or "cr2w" in text.lower() or "json" in text.lower())
    except Exception as exc:
        result["helpError"] = str(exc)
    result["ready"] = bool(result["found"] and result["convertDeserialize"])
    if not result["ready"] and "reason" not in result:
        result["reason"] = "CLI found, but convert deserialize could not be verified"
    return result


def _load_native_manifest(native_json: str | Path) -> tuple[Path, dict[str, Any]]:
    root = Path(native_json).resolve()
    p = root / ".cp77wb-native-json.json"
    data = json.loads(p.read_text(encoding="utf-8"))
    if data.get("schema") != NATIVE_JSON_SCHEMA:
        raise ValueError(f"Unsupported native JSON manifest schema {data.get('schema')!r}")
    return root, data


def native_convert(native_json: str | Path, output: str | Path, *, cli: str | Path | None = None, run: bool = False, timeout: int = 300) -> dict[str, Any]:
    root, manifest = _load_native_manifest(native_json)
    preflight = native_preflight(cli=cli)
    if not preflight["ready"]:
        raise FileNotFoundError(preflight.get("reason") or "WolvenKit JSON deserializer unavailable")
    cli_path = str(preflight["cli"])
    out_root = Path(output).resolve()
    actions: list[dict[str, Any]] = []
    for item in manifest["files"]:
        src = Path(item["json"])
        rel_target = Path(item["target"])
        target_dir = out_root / rel_target.parent
        target = out_root / rel_target
        cmd = [cli_path, "convert", "deserialize", str(src), "--outpath", str(target_dir)]
        action = {"json": str(src), "target": str(target), "command": cmd, "ran": False}
        actions.append(action)
        if not run:
            continue
        target_dir.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout, check=False)
        action.update({"ran": True, "exitCode": proc.returncode, "log": proc.stdout[-6000:]})
        if proc.returncode != 0:
            raise RuntimeError(f"WolvenKit JSON->CR2W conversion failed for {src} ({proc.returncode}):\n{proc.stdout[-6000:]}")
        # Most WKit versions strip .json. If a backend emitted elsewhere in target_dir, normalize cautiously.
        if not target.is_file():
            candidates = [p for p in target_dir.glob(src.stem) if p.is_file()]
            if not candidates:
                candidates = [p for p in target_dir.iterdir() if p.is_file() and p.name == rel_target.name]
            if candidates and candidates[0] != target:
                target.parent.mkdir(parents=True, exist_ok=True)
                candidates[0].replace(target)
    verification = verify_native_outputs(out_root, [x["target"] for x in manifest["files"]]) if run else None
    return {"nativeJson": str(root), "output": str(out_root), "run": run, "preflight": preflight, "actions": actions, "verification": verification}


def verify_native_outputs(output: str | Path, targets: list[str] | None = None, *, strict_magic: bool = True) -> dict[str, Any]:
    root = Path(output).resolve()
    if targets is None:
        targets = [str(p.relative_to(root)) for p in root.rglob("*") if p.is_file() and p.suffix in {".streamingsector", ".streamingblock", ".devices", ".psrep"}]
    files: list[dict[str, Any]] = []
    issues: list[dict[str, str]] = []
    for rel in targets:
        p = root / rel
        exists = p.is_file()
        magic = p.read_bytes()[:4] if exists else b""
        cr2w = exists and magic == b"CR2W"
        files.append({"path": str(rel), "exists": exists, "size": p.stat().st_size if exists else 0, "magic": magic.decode("ascii", "replace"), "cr2w": cr2w})
        if not exists:
            issues.append({"severity": "error", "code": "missing", "message": f"Missing converted output {rel}"})
        elif strict_magic and not cr2w:
            issues.append({"severity": "error", "code": "bad-magic", "message": f"{rel} does not begin with CR2W magic"})
    return {"output": str(root), "files": files, "issues": issues, "valid": not issues}


def native_import(export_file: str | Path, bundle_file: str | Path, output: str | Path, *, cli: str | Path | None = None,
                  run: bool = False, keep_json: bool = True, timeout: int = 300) -> dict[str, Any]:
    output = Path(output).resolve()
    json_root = output.parent / (output.name + ".cp77wb-json")
    prep = prepare_native_json(export_file, bundle_file, json_root)
    conv = native_convert(json_root, output, cli=cli, run=run, timeout=timeout)
    if run and not keep_json and conv.get("verification", {}).get("valid"):
        shutil.rmtree(json_root, ignore_errors=True)
    return {"prepared": prep, "conversion": conv, "run": run, "native": bool(run and conv.get("verification", {}).get("valid"))}
