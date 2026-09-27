from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import time
import zipfile
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape as xml_escape

EXPORT_IMPORT_VERSION = "1.0.4"
MANIFEST_SCHEMA = "cp77wb-build/1"


@dataclass
class ExportIssue:
    severity: str
    code: str
    message: str
    path: str = ""

    def to_dict(self) -> dict[str, str]:
        return asdict(self)


def _read_json(path: str | Path) -> dict[str, Any]:
    p = Path(path)
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"Expected JSON object in {p}")
    return data


def _ver_tuple(v: Any) -> tuple[int, ...]:
    parts = re.findall(r"\d+", str(v or "0"))
    return tuple(int(x) for x in parts) or (0,)


def inspect_export(path: str | Path, *, importer_version: str = EXPORT_IMPORT_VERSION) -> dict[str, Any]:
    p = Path(path)
    data = _read_json(p)
    issues: list[ExportIssue] = []
    name = data.get("name")
    if not isinstance(name, str) or not name.strip():
        issues.append(ExportIssue("error", "missing-name", "Export requires a non-empty name", "$.name"))
        name = p.stem.removesuffix("_exported")
    elif not re.fullmatch(r"[a-z0-9_\-.]+", name):
        issues.append(ExportIssue("warning", "unusual-name", "Export name contains characters outside the usual WB normalized set", "$.name"))

    version = str(data.get("version", "0"))
    if _ver_tuple(version) > _ver_tuple(importer_version):
        issues.append(ExportIssue("error", "importer-too-old", f"Export requires import script {version}+ but configured importer is {importer_version}", "$.version"))

    sectors = data.get("sectors")
    if not isinstance(sectors, list) or not sectors:
        issues.append(ExportIssue("error", "missing-sectors", "Export contains no sectors", "$.sectors"))
        sectors = []

    total_nodes = 0
    node_refs: dict[str, str] = {}
    sector_names: set[str] = set()
    node_types: dict[str, int] = {}
    for si, sector in enumerate(sectors):
        spath = f"$.sectors[{si}]"
        if not isinstance(sector, dict):
            issues.append(ExportIssue("error", "invalid-sector", "Sector must be an object", spath))
            continue
        sname = sector.get("name")
        if not isinstance(sname, str) or not sname:
            issues.append(ExportIssue("error", "missing-sector-name", "Sector requires name", spath+".name"))
        elif sname in sector_names:
            issues.append(ExportIssue("error", "duplicate-sector", f"Duplicate sector name {sname!r}", spath+".name"))
        else:
            sector_names.add(sname)
        nodes = sector.get("nodes")
        if not isinstance(nodes, list):
            issues.append(ExportIssue("error", "invalid-nodes", "Sector nodes must be an array", spath+".nodes"))
            continue
        total_nodes += len(nodes)
        variants = sector.get("variantIndices", [0])
        if not isinstance(variants, list) or not variants or variants[0] != 0:
            issues.append(ExportIssue("error", "variant-indices", "variantIndices must be a non-empty array starting with 0", spath+".variantIndices"))
        elif any(not isinstance(x, int) or x < 0 or x > len(nodes) for x in variants):
            issues.append(ExportIssue("error", "variant-range", "variantIndices entries must address node ranges inside the sector", spath+".variantIndices"))
        elif variants != sorted(variants):
            issues.append(ExportIssue("error", "variant-order", "variantIndices must be sorted", spath+".variantIndices"))
        for ni, node in enumerate(nodes):
            npath = f"{spath}.nodes[{ni}]"
            if not isinstance(node, dict):
                issues.append(ExportIssue("error", "invalid-node", "Node must be an object", npath))
                continue
            for key in ("type", "position", "rotation", "scale", "data"):
                if key not in node:
                    issues.append(ExportIssue("error", f"missing-node-{key}", f"Node missing required field {key}", npath+"."+key))
            ntype = str(node.get("type", "<missing>"))
            node_types[ntype] = node_types.get(ntype, 0) + 1
            nr = node.get("nodeRef")
            if isinstance(nr, str) and nr:
                if nr in node_refs:
                    issues.append(ExportIssue("error", "duplicate-noderef", f"NodeRef {nr!r} also used by {node_refs[nr]}", npath+".nodeRef"))
                else:
                    node_refs[nr] = npath

    devices = data.get("devices", {})
    ps_entries = data.get("psEntries", {})
    if not isinstance(devices, dict):
        issues.append(ExportIssue("error", "invalid-devices", "devices must be an object", "$.devices"))
        devices = {}
    if not isinstance(ps_entries, dict):
        issues.append(ExportIssue("error", "invalid-psentries", "psEntries must be an object", "$.psEntries"))
        ps_entries = {}
    errors = sum(i.severity == "error" for i in issues)
    warnings = sum(i.severity == "warning" for i in issues)
    return {
        "file": str(p), "name": name, "version": version, "importerVersion": importer_version,
        "xlFormat": int(data.get("xlFormat", 0) or 0), "sectors": len(sectors), "nodes": total_nodes,
        "devices": len(devices), "psEntries": len(ps_entries), "nodeTypes": dict(sorted(node_types.items())),
        "issues": [i.to_dict() for i in issues], "errors": errors, "warnings": warnings, "valid": errors == 0,
    }


def archive_xl_config(export: dict[str, Any]) -> dict[str, Any]:
    name = str(export["name"])
    xl: dict[str, Any] = {"streaming": {"blocks": [f"{name}/all.streamingblock"]}}
    has_devices = isinstance(export.get("devices"), dict) and bool(export.get("devices"))
    has_ps = isinstance(export.get("psEntries"), dict) and bool(export.get("psEntries"))
    if has_devices or has_ps:
        xl["resource"] = {"patch": {}}
        patch = xl["resource"]["patch"]
        if has_devices:
            patch[f"{name}/custom_devices.devices"] = [r"base\worlds\03_night_city\_compiled\default\03_night_city.devices"]
        if has_ps:
            patch[f"{name}/custom_devices.psrep"] = [r"base\worlds\03_night_city\_compiled\default\03_night_city.psrep"]
    return xl


def _yaml_scalar(v: Any) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "null"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v)
    if re.fullmatch(r"[A-Za-z0-9_./\\-]+", s):
        return s
    return json.dumps(s, ensure_ascii=False)


def _yaml_dump(value: Any, indent: int = 0) -> str:
    pad = " " * indent
    if isinstance(value, dict):
        lines: list[str] = []
        for k, v in value.items():
            key = str(k)
            if isinstance(v, (dict, list)):
                lines.append(f"{pad}{key}:")
                lines.append(_yaml_dump(v, indent + 2))
            else:
                lines.append(f"{pad}{key}: {_yaml_scalar(v)}")
        return "\n".join(lines)
    if isinstance(value, list):
        lines=[]
        for item in value:
            if isinstance(item, (dict, list)):
                lines.append(f"{pad}-")
                lines.append(_yaml_dump(item, indent+2))
            else:
                lines.append(f"{pad}- {_yaml_scalar(item)}")
        return "\n".join(lines)
    return pad + _yaml_scalar(value)


def write_archive_xl(export_file: str | Path, output: str | Path, *, format: str | None = None) -> dict[str, Any]:
    data = _read_json(export_file)
    config = archive_xl_config(data)
    fmt = format or ("yaml" if int(data.get("xlFormat", 0) or 0) == 1 else "json")
    out = Path(output)
    out.parent.mkdir(parents=True, exist_ok=True)
    if fmt == "yaml":
        out.write_text(_yaml_dump(config)+"\n", encoding="utf-8")
    elif fmt == "json":
        out.write_text(json.dumps(config, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    else:
        raise ValueError("ArchiveXL format must be json or yaml")
    return {"output": str(out), "format": fmt, "config": config}


def _project_xml(name: str, author: str, version: str, description: str) -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<CP77Mod xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n'
        f'  <Name>{xml_escape(name)}</Name>\n  <Author>{xml_escape(author)}</Author>\n'
        f'  <Version>{xml_escape(version)}</Version>\n  <Description>{xml_escape(description)}</Description>\n'
        '</CP77Mod>\n'
    )


def _patch_importer(text: str, exported_filename: str) -> str:
    pattern = r'const\s+inputFilePathInRawFolder\s*=\s*"[^"]*"'
    replacement = f'const inputFilePathInRawFolder = "{exported_filename}"'
    patched, count = re.subn(pattern, replacement, text, count=1)
    if count != 1:
        raise ValueError("Could not locate inputFilePathInRawFolder in World Builder importer")
    return patched


def _find_importer(world_builder_root: str | Path | None) -> Path | None:
    if not world_builder_root:
        return None
    root = Path(world_builder_root)
    candidates = [root/"script"/"import_object_spawner.wscript", root/"scripts"/"import_object_spawner.wscript"]
    return next((p for p in candidates if p.is_file()), None)


def prepare_build_workspace(export_file: str | Path, workspace: str | Path, *, world_builder_root: str | Path | None = None,
                            project_name: str | None = None, author: str = "", version: str = "1.0.0",
                            description: str = "World Builder project prepared by cp77wb", force: bool = False,
                            scaffold_tweak: bool = False) -> dict[str, Any]:
    export_file = Path(export_file)
    report = inspect_export(export_file)
    if not report["valid"]:
        raise ValueError(f"World Builder export has {report['errors']} error(s); run export-inspect first")
    data = _read_json(export_file)
    name = project_name or str(data["name"])
    root = Path(workspace) / name
    if root.exists() and any(root.iterdir()) and not force:
        raise FileExistsError(f"Workspace {root} is not empty; use --force to update generated files")
    (root/"source"/"archive").mkdir(parents=True, exist_ok=True)
    (root/"source"/"raw").mkdir(parents=True, exist_ok=True)
    (root/"source"/"resources").mkdir(parents=True, exist_ok=True)
    (root/"source"/"customSounds").mkdir(parents=True, exist_ok=True)
    (root/"automation").mkdir(parents=True, exist_ok=True)
    (root/"packed").mkdir(parents=True, exist_ok=True)

    raw_export = root/"source"/"raw"/export_file.name
    shutil.copy2(export_file, raw_export)
    cpmodproj = root/f"{name}.cpmodproj"
    cpmodproj.write_text(_project_xml(name, author, version, description), encoding="utf-8")
    xl = root/"source"/"resources"/f"{data['name']}.xl"
    xl_info = write_archive_xl(export_file, xl)
    if scaffold_tweak:
        tweak = root/"source"/"resources"/"r6"/"tweaks"/f"{name}.yaml"
        tweak.parent.mkdir(parents=True, exist_ok=True)
        if not tweak.exists() or force:
            tweak.write_text("# cp77wb v0.9 TweakXL scaffold. Remove this file if your world edit needs no TweakXL records.\n", encoding="utf-8")

    importer = _find_importer(world_builder_root)
    importer_out = None
    importer_version = None
    if importer:
        text = importer.read_text(encoding="utf-8-sig")
        m = re.search(r'const\s+version\s*=\s*"([^"]+)"', text)
        importer_version = m.group(1) if m else None
        importer_out = root/"automation"/f"import_object_spawner_{data['name']}.wscript"
        importer_out.write_text(_patch_importer(text, export_file.name), encoding="utf-8")

    from .native import make_template_capture_script
    capture_out = root/"automation"/f"capture_cp77wb_templates_{data['name']}.wscript"
    capture_info = make_template_capture_script(export_file, capture_out, resource_name=f"cp77wb_templates_{data['name']}.json")

    expected = [
        f"source/archive/{data['name']}/all.streamingblock",
        *[f"source/archive/{data['name']}/sectors/{s.get('name','<unnamed>')}.streamingsector" for s in data.get("sectors", []) if isinstance(s, dict)],
    ]
    if data.get("devices"):
        expected.append(f"source/archive/{data['name']}/custom_devices.devices")
    if data.get("psEntries"):
        expected.append(f"source/archive/{data['name']}/custom_devices.psrep")

    manifest = {
        "schema": MANIFEST_SCHEMA, "cp77wbVersion": "1.0.1", "projectName": name, "exportName": data["name"],
        "exportFile": str(raw_export.relative_to(root)), "exportSha256": hashlib.sha256(export_file.read_bytes()).hexdigest(),
        "exportVersion": str(data.get("version", "")), "worldBuilderImporter": str(importer_out.relative_to(root)) if importer_out else None,
        "nativeTemplateCapture": str(capture_out.relative_to(root)), "nativeTemplateResource": capture_info["resource"], "nativeRequiredTypes": capture_info["requiredTypes"],
        "importerVersion": importer_version, "archiveXL": str(xl.relative_to(root)), "archiveXLFormat": xl_info["format"],
        "expectedArchiveFiles": expected, "createdAt": int(time.time()),
        "backend": {"objectSpawnerImport": "wolvenkit-script-api-or-template-json-or-dotnet-worker", "pack": "wolvenkit-cli-or-cp77tools", "linuxNativeObjectSpawner": "dotnet-worker-preferred-template-bundle-fallback"},
    }
    manifest_path = root/".cp77wb-build.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    readme = root/"BUILD-CP77WB.md"
    script_note = (f"Run `automation/{importer_out.name}` in WolvenKit Script Manager.\n" if importer_out else
                   "Run World Builder's `import_object_spawner.wscript` in WolvenKit Script Manager with the raw export as input.\n")
    readme.write_text(
        f"# {name} — cp77wb build workspace\n\n"
        f"1. Open `{cpmodproj.name}` in WolvenKit.\n2. {script_note}"
        "3. Run `cp77wb build-status .` and require `importComplete: true`.\n"
        "4. Pack with `cp77wb build-pack . --cli /path/to/cp77tools --run` (or WolvenKit Build Project).\n"
        "5. Create a game-layout package with `cp77wb build-package . --archive /path/to/mod.archive --output dist`.\n\n"
        "For Linux-native conversion, prefer `cp77wb worker-preflight` / `cp77wb build-worker-import`; v0.9 template capture + `native-import` remains the fallback.\n",
        encoding="utf-8")
    return {"workspace": str(root), "project": str(cpmodproj), "manifest": str(manifest_path), "rawExport": str(raw_export),
            "archiveXL": str(xl), "importScript": str(importer_out) if importer_out else None, "nativeTemplateCapture": str(capture_out),
            "nativeRequiredTypes": capture_info["requiredTypes"], "expected": expected, "export": report}


def load_manifest(workspace: str | Path) -> tuple[Path, dict[str, Any]]:
    root = Path(workspace).resolve()
    p = root/".cp77wb-build.json"
    data = _read_json(p)
    if data.get("schema") != MANIFEST_SCHEMA:
        raise ValueError(f"Unsupported build manifest schema {data.get('schema')!r}")
    return root, data


def build_status(workspace: str | Path) -> dict[str, Any]:
    root, manifest = load_manifest(workspace)
    expected = list(manifest.get("expectedArchiveFiles", []))
    files = [{"path": rel, "exists": (root/rel).is_file(), "size": (root/rel).stat().st_size if (root/rel).is_file() else 0} for rel in expected]
    missing = [x["path"] for x in files if not x["exists"]]
    raw = root/str(manifest["exportFile"])
    sha = hashlib.sha256(raw.read_bytes()).hexdigest() if raw.is_file() else None
    export_unchanged = sha == manifest.get("exportSha256")
    return {"workspace": str(root), "projectName": manifest.get("projectName"), "exportUnchanged": export_unchanged,
            "importComplete": not missing and bool(expected), "expected": files, "missing": missing,
            "archiveXL": str(root/str(manifest.get("archiveXL"))) if manifest.get("archiveXL") else None}


def backend_scan(*, cli: str | Path | None = None, world_builder_root: str | Path | None = None) -> dict[str, Any]:
    cli_path = None
    if cli:
        c = Path(cli)
        cli_path = str(c) if c.exists() else shutil.which(str(cli))
    else:
        cli_path = shutil.which("cp77tools") or shutil.which("WolvenKit.CLI") or shutil.which("WolvenKit.CLI.exe")
    importer = _find_importer(world_builder_root)
    importer_calls: list[str] = []
    if importer:
        text = importer.read_text(encoding="utf-8-sig")
        for call in ("CreateInstanceAsJSON", "HashString", "JsonToCR2W", "SaveToProject", "SaveToResources"):
            if f"wkit.{call}" in text:
                importer_calls.append(call)
    from .native import native_preflight
    from .worker import worker_preflight
    native = native_preflight(cli=cli_path) if cli_path else {"ready": False, "found": False, "reason": "WolvenKit CLI/cp77tools not found"}
    worker = worker_preflight()
    return {
        "platform": os.name, "wolvenkitCli": cli_path, "cliFound": bool(cli_path), "worldBuilderImporter": str(importer) if importer else None,
        "scriptApiCalls": importer_calls, "nativePreflight": native, "workerPreflight": worker,
        "capabilities": {
            "prepareWorkspace": True, "generateArchiveXL": True, "validateImportOutputs": True,
            "packViaCli": bool(cli_path), "packageZip": True, "deployLegacyMod": True,
            "wkitJsonToCr2w": bool(native.get("ready")),
            "dotnetWorker": bool(worker.get("ready")),
            "linuxNativeObjectSpawnerConversion": bool(worker.get("ready") or native.get("ready")),
            "authoritativeNativeWorker": bool(worker.get("authoritativeNative")),
            "nativeRequiresTemplateBundle": not bool(worker.get("ready")),
        },
        "nativeBlocker": None if (worker.get("ready") or native.get("ready")) else "Build/run cp77wb-wkit-worker (.NET 10 + WolvenKit 9.x), or use the v0.9 template bundle + WolvenKit CLI fallback.",
    }



def build_native_import(workspace: str | Path, bundle: str | Path, *, cli: str | Path | None = None, run: bool = False,
                        keep_json: bool = True, timeout: int = 300) -> dict[str, Any]:
    root, manifest = load_manifest(workspace)
    export_file = root / str(manifest["exportFile"])
    output = root / "source" / "archive"
    from .native import native_import, native_preflight, verify_template_bundle
    coverage = verify_template_bundle(export_file, bundle)
    preflight = native_preflight(cli=cli)
    plan = {
        "workspace": str(root), "export": str(export_file), "bundle": str(Path(bundle)),
        "output": str(output), "run": run, "coverage": coverage, "preflight": preflight,
    }
    if not run:
        plan["ready"] = bool(coverage["valid"] and preflight["ready"])
        return plan
    if not coverage["valid"]:
        raise ValueError(f"Template bundle incomplete: missing={coverage['missing']} failed={coverage['failed']}")
    if not preflight["ready"]:
        raise FileNotFoundError(preflight.get("reason") or "WolvenKit JSON deserializer unavailable")
    result = native_import(export_file, bundle, output, cli=cli, run=True, keep_json=keep_json, timeout=timeout)
    status = build_status(root)
    if result.get("native") and status.get("importComplete"):
        manifest["lastImportBackend"] = "template-json+wkit-convert-deserialize"
        manifest["lastImportAt"] = int(time.time())
        (root/".cp77wb-build.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    plan.update({"result": result, "status": status, "ready": bool(result.get("native") and status.get("importComplete"))})
    return plan

def build_worker_import(workspace: str | Path, *, worker: str | Path | None = None, run: bool = False,
                        keep_json: bool = True, timeout: int = 300) -> dict[str, Any]:
    root, manifest = load_manifest(workspace)
    export_file = root / str(manifest["exportFile"])
    output = root / "source" / "archive"
    from .worker import worker_import, worker_preflight
    preflight = worker_preflight(worker=worker, timeout=min(timeout, 30))
    plan = {"workspace": str(root), "export": str(export_file), "output": str(output), "run": run, "preflight": preflight,
            "ready": bool(preflight.get("ready"))}
    if not run:
        return plan
    if not preflight.get("ready"):
        raise FileNotFoundError(preflight.get("reason") or "cp77wb WolvenKit worker unavailable")
    result = worker_import(export_file, output, worker=worker, run=True, keep_json=keep_json, timeout=timeout)
    status = build_status(root)
    if result.get("native") and status.get("importComplete"):
        manifest["lastImportBackend"] = "dotnet-wolvenkit-worker"
        manifest["lastImportAt"] = int(time.time())
        (root/".cp77wb-build.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    plan.update({"result": result, "status": status, "ready": bool(result.get("native") and status.get("importComplete"))})
    return plan


def _command_for_pack(cli: str, archive_dir: Path, out_dir: Path) -> list[str]:
    # cp77tools and WolvenKit.CLI both expose the WolvenKit CLI command family.
    return [cli, "pack", "-p", str(archive_dir), "-o", str(out_dir)]


def build_pack(workspace: str | Path, *, cli: str | Path | None = None, output: str | Path | None = None, run: bool = False,
               timeout: int = 300) -> dict[str, Any]:
    root, manifest = load_manifest(workspace)
    status = build_status(root)
    if not status["importComplete"]:
        raise ValueError("Object Spawner import outputs are incomplete; run build-status")
    cli_path = str(cli) if cli else (shutil.which("cp77tools") or shutil.which("WolvenKit.CLI") or shutil.which("WolvenKit.CLI.exe"))
    if not cli_path:
        raise FileNotFoundError("WolvenKit CLI/cp77tools not found; pass --cli PATH")
    out = Path(output) if output else root/"packed"/"archive"/"pc"/"mod"
    out.mkdir(parents=True, exist_ok=True)
    cmd = _command_for_pack(cli_path, root/"source"/"archive", out)
    result: dict[str, Any] = {"command": cmd, "ran": False, "output": str(out)}
    if not run:
        return result
    before = set(out.glob("*.archive"))
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=timeout, check=False)
    after = set(out.glob("*.archive"))
    new = sorted(after-before, key=lambda p: p.stat().st_mtime)
    if proc.returncode != 0:
        raise RuntimeError(f"WolvenKit pack failed ({proc.returncode}):\n{proc.stdout[-6000:]}")
    archive = new[-1] if new else (max(after, key=lambda p: p.stat().st_mtime) if after else None)
    desired = out/f"{manifest['projectName']}.archive"
    if archive and archive != desired:
        if desired.exists():
            desired.unlink()
        archive.rename(desired)
        archive = desired
    result.update({"ran": True, "exitCode": proc.returncode, "log": proc.stdout, "archive": str(archive) if archive else None})
    return result


def _copy_resource_tree(resources: Path, layout: Path) -> list[str]:
    produced: list[str] = []
    if not resources.is_dir():
        return produced
    for src in resources.rglob("*"):
        if not src.is_file():
            continue
        rel = src.relative_to(resources)
        # WKit's resource root has special handling for root ArchiveXL files.
        if len(rel.parts) == 1 and src.suffix.lower() in {".xl"}:
            dest = layout/"archive"/"pc"/"mod"/src.name
        elif rel.parts and rel.parts[0] in {"r6", "bin", "red4ext", "engine", "mods"}:
            dest = layout/rel
        else:
            # Keep unrecognized resources visible instead of silently installing to a guessed location.
            dest = layout/"cp77wb-unmapped-resources"/rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
        produced.append(str(dest.relative_to(layout)))
    return produced


def build_package(workspace: str | Path, *, archive: str | Path, output: str | Path, zip_output: str | Path | None = None,
                  clean: bool = True) -> dict[str, Any]:
    root, manifest = load_manifest(workspace)
    archive = Path(archive)
    if not archive.is_file():
        raise FileNotFoundError(archive)
    layout = Path(output)
    if clean and layout.exists():
        shutil.rmtree(layout)
    mod_dir = layout/"archive"/"pc"/"mod"
    mod_dir.mkdir(parents=True, exist_ok=True)
    dest_archive = mod_dir/f"{manifest['projectName']}.archive"
    shutil.copy2(archive, dest_archive)
    produced = [str(dest_archive.relative_to(layout))]
    produced += _copy_resource_tree(root/"source"/"resources", layout)
    unmapped = [x for x in produced if x.startswith("cp77wb-unmapped-resources/")]
    zip_path = None
    if zip_output:
        zip_path = Path(zip_output)
        zip_path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for f in sorted(layout.rglob("*")):
                if f.is_file() and not str(f.relative_to(layout)).startswith("cp77wb-unmapped-resources/"):
                    zf.write(f, f.relative_to(layout).as_posix())
    return {"layout": str(layout), "archive": str(dest_archive), "files": produced, "unmappedResources": unmapped,
            "zip": str(zip_path) if zip_path else None, "ready": not unmapped}


def deploy_layout(layout: str | Path, game_root: str | Path, *, apply: bool = False, overwrite: bool = False) -> dict[str, Any]:
    layout = Path(layout).resolve()
    game = Path(game_root).resolve()
    if not layout.is_dir():
        raise FileNotFoundError(layout)
    files = [p for p in layout.rglob("*") if p.is_file() and "cp77wb-unmapped-resources" not in p.parts]
    actions=[]
    conflicts=[]
    for src in files:
        rel=src.relative_to(layout)
        dest=game/rel
        exists=dest.exists()
        same=False
        if exists:
            try:
                same=hashlib.sha256(src.read_bytes()).digest()==hashlib.sha256(dest.read_bytes()).digest()
            except OSError:
                same=False
        action={"source":str(src),"relative":rel.as_posix(),"destination":str(dest),"exists":exists,"same":same}
        actions.append(action)
        if exists and not same:
            conflicts.append(rel.as_posix())
    if conflicts and apply and not overwrite:
        raise FileExistsError("Deployment would overwrite existing files: "+", ".join(conflicts[:10]))
    backup_root=None
    if apply:
        if conflicts:
            backup_root=game/".cp77wb-deploy-backups"/time.strftime("%Y%m%d-%H%M%S")
        for a in actions:
            src=Path(a["source"])
            dest=Path(a["destination"])
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists() and not a["same"] and backup_root:
                b=backup_root/a["relative"]
                b.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dest,b)
            if not a["same"]:
                shutil.copy2(src,dest)
    return {"apply":apply,"files":len(actions),"conflicts":conflicts,"backup":str(backup_root) if backup_root else None,"actions":actions}


def verify_package(layout: str | Path, *, game_root: str | Path | None = None) -> dict[str, Any]:
    root=Path(layout)
    issues: list[dict[str,str]]=[]
    archives=list((root/"archive"/"pc"/"mod").glob("*.archive")) if (root/"archive"/"pc"/"mod").is_dir() else []
    xls=list((root/"archive"/"pc"/"mod").glob("*.xl")) if (root/"archive"/"pc"/"mod").is_dir() else []
    if not archives:
        issues.append({"severity":"error","code":"no-archive","message":"No .archive under archive/pc/mod"})
    if (root/"cp77wb-unmapped-resources").exists():
        issues.append({"severity":"warning","code":"unmapped-resources","message":"Package contains resources whose install location cp77wb would not guess"})
    conflicts=[]
    if game_root:
        game=Path(game_root)
        for f in root.rglob("*"):
            if f.is_file() and "cp77wb-unmapped-resources" not in f.parts:
                dest=game/f.relative_to(root)
                if dest.is_file() and hashlib.sha256(dest.read_bytes()).digest()!=hashlib.sha256(f.read_bytes()).digest():
                    conflicts.append(f.relative_to(root).as_posix())
    errors=sum(x["severity"]=="error" for x in issues)
    return {"layout":str(root),"archives":[str(x) for x in archives],"archiveXL":[str(x) for x in xls],"conflicts":conflicts,"issues":issues,"valid":errors==0}


def build_doctor(layout: str | Path, *, game_root: str | Path | None = None, tail: int = 200) -> dict[str, Any]:
    package = verify_package(layout, game_root=game_root)
    log_report = None
    issue_lines = 0
    if game_root:
        from .logs import read_logs
        log_report = read_logs(game_root, tail=tail, issues_only=True)
        issue_lines = sum(len(entry.get("lines", [])) for entry in log_report.get("logs", []))
    status = "ok" if package["valid"] and issue_lines == 0 else ("review" if package["valid"] else "error")
    return {"status": status, "package": package, "logs": log_report, "logIssueLines": issue_lines}
