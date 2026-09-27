"""Material instance resources from LocationStudio material definitions.

The in-game material library (modules/materials.lua) stores definitions in
``material_defs``: a base material (preset or any .mt/.remt/.mi), textures,
semantic parameters (roughness, metallic, emissive, tint, tiling, UV scale),
raw parameter overrides and named variants. This module is the build half:

* ``build_material`` turns a definition into WolvenKit CR2W-JSON
  ``CMaterialInstance`` documents: one for the definition and one per variant.
  A variant's base material is the parent ``.mi``, and it only stores the values
  that differ from the parent.
* Textures are depot ``.xbm`` references, local images (``file``), or generated
  solid-colour PNGs (``solid``). Build Mod imports the images to ``.xbm`` with
  the WolvenKit CLI.
* ``uv_scale`` (metres per texture repeat) and ``tiling`` (repeats) are baked
  into the UVs of generated meshes, so they work with every base material.
* Parameter names come from built-in profiles for the presets, which are
  unverified. When a WolvenKit JSON export of the base material (``.mt.json`` /
  ``.remt.json``) is available, every parameter name and type is checked
  against its ``parameterName`` list (``profile_source: base-json``).
  Otherwise names that a reference ``.mi`` export uses count as verified.
  Anything else is reported as unverified.
* ``resolve_project`` rewrites ``@key`` / ``@key:variant`` references on
  procedural objects into depot paths and lists one mesh appearance per variant.
* ``apply_to_workspace`` is the Build Mod ``materials`` stage. It writes the
  ``.mi`` documents, turns them into CR2W with the WolvenKit worker, and
  imports the textures.
"""
from __future__ import annotations

import copy
import json
import os
import struct
import subprocess
import zlib
from pathlib import Path
from typing import Any, Callable

from .meshres import WKIT_JSON_VERSION, WKIT_VERSION, cname, depot

DEFAULT_TEXTURE_IMPORT_COMMAND = ["{cli}", "import", "-p", "{image}"]

# preset -> base, semantic parameter -> (parameter name, value type), texture -> (parameter name, value type)
PROFILES: dict[str, dict[str, Any]] = {
    "metal_base": {
        "base": "base\\materials\\metal_base.remt",
        "params": {"tint": ("BaseColorScale", "Vector4"), "roughness": ("RoughnessBias", "Float"), "roughness_scale": ("RoughnessScale", "Float"),
                   "metallic": ("MetalnessBias", "Float"), "metallic_scale": ("MetalnessScale", "Float"),
                   "normal_strength": ("NormalStrength", "Float"), "emissive_color": ("EmissiveColor", "Color"),
                   "emissive_ev": ("EmissiveEV", "Float"), "alpha_threshold": ("AlphaThreshold", "Float")},
        "textures": {"base_color": ("BaseColor", "texture"), "normal": ("Normal", "texture"), "roughness": ("Roughness", "texture"),
                     "metalness": ("Metalness", "texture"), "emissive": ("Emissive", "texture"), "mask": ("AlphaMask", "texture")},
        # A scalar without its texture: zero the texture scale so the bias is the value.
        "constant": {"roughness": ("roughness", "roughness_scale"), "metallic": ("metalness", "metallic_scale")},
    },
    "glass": {
        "base": "base\\materials\\glass.mt",
        "params": {"tint": ("TintColor", "Color"), "roughness": ("Roughness", "Float"), "ior": ("IOR", "Float"),
                   "opacity": ("Opacity", "Float"), "normal_strength": ("NormalStrength", "Float")},
        "textures": {"normal": ("Normal", "texture"), "mask": ("Mask", "texture")},
    },
    "multilayered": {
        "base": "engine\\materials\\multilayered.mt",
        "params": {},
        "textures": {"mlsetup": ("MultilayerSetup", "mlsetup"), "mlmask": ("MultilayerMask", "mlmask"), "normal": ("GlobalNormal", "texture")},
    },
    "custom": {"base": None, "params": {}, "textures": {}},
}

REF_TYPES = {"texture": "rRef:ITexture", "mlsetup": "rRef:Multilayer_Setup", "mlmask": "rRef:Multilayer_Mask"}
# CMaterialTemplate parameter classes -> value types
TEMPLATE_TYPES = {"Scalar": "Float", "Texture": "texture", "Color": "Color", "Vector": "Vector4", "MultilayerSetup": "mlsetup",
                  "MultilayerMask": "mlmask", "Bool": "Bool", "Int": "Int32", "CName": "CName", "TextureArray": "texture"}


def _norm(path: str) -> str:
    return str(path or "").replace("/", "\\").strip("\\").lower()


# --------------------------------------------------------------------------- values

def _color8(c: list[float]) -> dict[str, Any]:
    r, g, b, a = (list(c) + [1.0])[:4]
    clamp = lambda x: max(0, min(255, int(round(float(x) * 255))))  # noqa: E731
    return {"$type": "Color", "Alpha": clamp(a), "Blue": clamp(b), "Green": clamp(g), "Red": clamp(r)}


def value_json(vtype: str, value: Any, template: dict[str, Any] | None = None) -> dict[str, Any]:
    """CVariant JSON for one parameter value. A reference value of the same type supplies the exact shape."""
    if vtype in REF_TYPES:
        out = {"$type": REF_TYPES[vtype], **depot(str(value))}
    elif vtype == "Color":
        out = _color8(value)
    elif vtype == "Vector4":
        x, y, z, w = (list(value) + [1.0])[:4]
        out = {"$type": "Vector4", "W": float(w), "X": float(x), "Y": float(y), "Z": float(z)}
    elif vtype == "CName":
        out = cname(str(value))
    elif vtype == "Bool":
        out = {"$type": "Bool", "$value": 1 if value else 0}
    elif vtype == "Int32":
        out = {"$type": "Int32", "$value": int(value)}
    else:
        out = {"$type": "Float", "$value": float(value)}
    if template and template.get("$type") == out["$type"]:
        shaped = copy.deepcopy(template)
        for k, v in out.items():
            if k in shaped or k == "$value":
                shaped[k] = v
        if "$value" in out and "$value" not in template:
            # e.g. {"$type": "Float", "Value": 0.5}
            for k in template:
                if k != "$type" and isinstance(template[k], (int, float)):
                    shaped.pop("$value", None)
                    shaped[k] = out["$value"]
                    break
        return shaped
    return out


def _pair(name: str, value: dict[str, Any]) -> dict[str, Any]:
    return {"$type": "CKeyValuePair", "key": cname(name), "value": value}


# --------------------------------------------------------------------------- base material knowledge

def template_parameters(doc: dict[str, Any]) -> dict[str, str]:
    """Parameter name -> value type from a WolvenKit JSON export of a .mt/.remt (CMaterialTemplate)."""
    out: dict[str, str] = {}

    def walk(v: Any) -> None:
        if isinstance(v, dict):
            name = v.get("parameterName")
            if name is not None:
                n = name.get("$value") if isinstance(name, dict) else name
                cls = str(v.get("$type") or "")
                kind = cls.replace("CMaterialParameter", "")
                if n:
                    out[str(n)] = TEMPLATE_TYPES.get(kind, kind or "unknown")
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)

    walk(doc)
    return out


def instance_values(doc: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Parameter name -> raw value JSON from a CMaterialInstance document."""
    root = ((doc or {}).get("Data") or {}).get("RootChunk") or doc or {}
    out = {}
    for pair in root.get("values") or []:
        key = pair.get("key")
        name = key.get("$value") if isinstance(key, dict) else key
        if name:
            out[str(name)] = pair.get("value") or {}
    return out


def decode_instance(doc: dict[str, Any]) -> dict[str, Any]:
    """Readable summary of a CMaterialInstance JSON document (ours or a WolvenKit export)."""
    root = ((doc or {}).get("Data") or {}).get("RootChunk") or {}
    if root.get("$type") != "CMaterialInstance":
        raise ValueError(f"not a CMaterialInstance document ({root.get('$type')!r})")
    base = ((root.get("baseMaterial") or {}).get("DepotPath") or {}).get("$value")
    values = []
    for name, v in instance_values(doc).items():
        t = v.get("$type")
        if t in REF_TYPES.values():
            value = ((v.get("DepotPath") or {}).get("$value"))
        elif t == "Color":
            value = [v.get("Red"), v.get("Green"), v.get("Blue"), v.get("Alpha")]
        elif t == "Vector4":
            value = [v.get("X"), v.get("Y"), v.get("Z"), v.get("W")]
        else:
            value = v.get("$value", next((x for k, x in v.items() if k != "$type"), None))
        values.append({"name": name, "type": t, "value": value})
    return {"base_material": base, "values": values, "generated_by": ((doc.get("Header") or {}).get("GeneratedBy"))}


# --------------------------------------------------------------------------- definitions

def texture_path(defn: dict[str, Any], semantic: str, tex: Any, variant: str | None = None) -> str:
    if isinstance(tex, str):
        return tex
    if tex.get("path"):
        return str(tex["path"])
    stem = str(defn["path"])[: -len(".mi")]
    folder, _, name = stem.rpartition("\\")
    suffix = f"_{variant}" if variant else ""
    return f"{folder}\\textures\\{name}{suffix}_{semantic}.xbm" if folder else f"textures\\{name}{suffix}_{semantic}.xbm"


def _resolved(defn: dict[str, Any], block: dict[str, Any], variant: str | None, own: set[str] | None = None) -> tuple[dict[str, tuple[str, Any]], list[dict[str, Any]], list[str]]:
    """name -> (type, value) for one parameter set, plus texture jobs and unmapped semantic keys."""
    profile = PROFILES.get(defn.get("preset") or "custom", PROFILES["custom"])
    values: dict[str, tuple[str, Any]] = {}
    jobs: list[dict[str, Any]] = []
    for semantic, tex in (block.get("textures") or {}).items():
        name, vtype = profile["textures"][semantic]
        path = texture_path(defn, semantic, tex, variant if own is None or semantic in own else None)
        values[name] = (vtype, path)
        if isinstance(tex, dict) and (tex.get("file") or tex.get("solid")):
            jobs.append({"semantic": semantic, "path": path, **{k: tex[k] for k in ("file", "solid", "size", "srgb", "compression") if k in tex}})
    params = block.get("params") or {}
    for semantic, value in params.items():
        if semantic in ("uv_scale", "tiling"):
            continue
        name, vtype = profile["params"][semantic]
        values[name] = (vtype, value)
    for semantic, (texture_key, scale_key) in (profile.get("constant") or {}).items():
        if semantic in params and texture_key not in (block.get("textures") or {}) and scale_key not in params:
            values[profile["params"][scale_key][0]] = ("Float", 0.0)
    for name, o in (block.get("overrides") or {}).items():
        vtype, value = o["type"], o["value"]
        if isinstance(value, dict):  # generated texture override
            path = texture_path(defn, name.lower(), value, variant if own is None or name in own else None)
            jobs.append({"semantic": name.lower(), "path": path, **{k: value[k] for k in ("file", "solid", "size", "srgb", "compression") if k in value}})
            value = path
        values[name] = (vtype, value)
    return values, jobs, []


def _instance_doc(base: str, values: dict[str, tuple[str, Any]], *, reference: dict[str, Any] | None, label: str) -> dict[str, Any]:
    ref_root = copy.deepcopy(((reference or {}).get("Data") or {}).get("RootChunk") or {}) if reference else {}
    templates: dict[str, dict[str, Any]] = {}
    for v in instance_values(reference or {}).values():
        templates.setdefault(str(v.get("$type")), v)
    root = ref_root if ref_root.get("$type") == "CMaterialInstance" else {}
    root.update({"$type": "CMaterialInstance", "cookingPlatform": root.get("cookingPlatform", "PLATFORM_PC"),
                 "enableMask": root.get("enableMask", 0), "resourceVersion": root.get("resourceVersion", 4),
                 "audioTag": root.get("audioTag", cname("None")),
                 "baseMaterial": depot(base),
                 "values": [_pair(name, value_json(vtype, value, templates.get(value_json(vtype, value)["$type"])))
                            for name, (vtype, value) in sorted(values.items())]})
    return {"Header": {"WolvenKitVersion": WKIT_VERSION, "WKitJsonVersion": WKIT_JSON_VERSION, "DataType": "CR2W",
                       "GeneratedBy": f"LocationStudio material library ({label})"},
            "Data": {"Version": 195, "BuildVersion": 0, "RootChunk": root, "EmbeddedFiles": []}}


def build_material(defn: dict[str, Any], *, base_parameters: dict[str, str] | None = None,
                   reference: dict[str, Any] | None = None) -> dict[str, Any]:
    """CMaterialInstance documents for a definition and its variants, texture jobs and verification.

    base_parameters: name -> type from ``template_parameters`` of the base material's JSON export.
    reference: a WolvenKit JSON export of a vanilla .mi (value shapes; names it uses count as seen).
    """
    for field in ("key", "path", "base"):
        if not defn.get(field):
            raise ValueError(f"material definition needs {field}")
    base = str(defn["base"])
    values, jobs, _ = _resolved(defn, defn, None)
    variant_types: dict[str, str] = {}
    docs = [{"path": defn["path"], "variant": None, "base": base, "document": _instance_doc(base, values, reference=reference, label=defn["key"]),
             "values": {k: v[1] for k, v in values.items()}}]
    for variant in defn.get("variants") or []:
        merged = {"textures": {**(defn.get("textures") or {}), **(variant.get("textures") or {})},
                  "params": {**(defn.get("params") or {}), **(variant.get("params") or {})},
                  "overrides": {**(defn.get("overrides") or {}), **(variant.get("overrides") or {})}}
        own_tex = set((variant.get("textures") or {}).keys()) | set((variant.get("overrides") or {}).keys())
        full, vjobs, _ = _resolved(defn, merged, variant["name"], own_tex)
        diff = {k: v for k, v in full.items() if values.get(k) != v}
        variant_types.update({k: v[0] for k, v in diff.items()})
        jobs += [j for j in vjobs if j["path"] not in {x["path"] for x in jobs}]
        docs.append({"path": variant["path"], "variant": variant["name"], "base": defn["path"],
                     "document": _instance_doc(defn["path"], diff, reference=reference, label=f"{defn['key']}:{variant['name']}"),
                     "values": {k: v[1] for k, v in diff.items()}})
    written = {name: vt for name, (vt, _v) in values.items()}
    written.update(variant_types)
    ref_names = set(instance_values(reference or {}).keys())
    ref_base = _norm(((((reference or {}).get("Data") or {}).get("RootChunk") or {}).get("baseMaterial") or {}).get("DepotPath", {}).get("$value", ""))
    errors, warnings = [], []
    if base_parameters:
        source = "base-json"
        for name, vtype in written.items():
            known = base_parameters.get(name)
            if known is None:
                errors.append(f"{base} has no parameter {name}")
            elif known != vtype and not (known == "texture" and vtype in REF_TYPES) and not (known == "Color" and vtype == "Vector4") and not (known == "Vector4" and vtype == "Color"):
                errors.append(f"parameter {name} of {base} is {known}, not {vtype}")
    else:
        unseen = sorted(n for n in written if not (ref_base == _norm(base) and n in ref_names))
        source = "reference-mi" if not unseen and written else "builtin-unverified"
        if unseen:
            warnings.append(f"parameter names not verified against {base}: {', '.join(unseen)}; export the base material to JSON with WolvenKit "
                            "(mod_sources/<depot path>.json) so they are checked, and verify the material in game")
    return {"key": defn["key"], "documents": docs, "textures": jobs, "profile_source": source, "errors": errors, "warnings": warnings,
            "uv": uv_transform(defn)}


def uv_transform(defn: dict[str, Any] | None) -> tuple[float, float]:
    """Divisor applied to world-projected UVs: uv_scale (metres per repeat) / tiling (repeats)."""
    params = (defn or {}).get("params") or {}
    su, sv = params.get("uv_scale") or (1.0, 1.0)
    tu, tv = params.get("tiling") or (1.0, 1.0)
    return (float(su) / float(tu), float(sv) / float(tv))


# --------------------------------------------------------------------------- textures

def solid_png(rgba: list[float], size: int = 4) -> bytes:
    """A small RGBA PNG of one colour."""
    px = bytes(max(0, min(255, int(round(float(c) * 255)))) for c in (list(rgba) + [1.0])[:4])
    raw = b"".join(b"\x00" + px * size for _ in range(size))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def _texture_command(cli: str, image: Path, xbm: Path) -> list[str]:
    template = DEFAULT_TEXTURE_IMPORT_COMMAND
    env = os.environ.get("LOCATION_STUDIO_TEXTURE_IMPORT_CMD")
    if env:
        template = json.loads(env)
    return [str(p).format(cli=cli, image=str(image), xbm=str(xbm), raw_dir=str(image.parent)) for p in template]


# --------------------------------------------------------------------------- project

def definitions(project: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {d["key"]: d for d in project.get("material_defs") or [] if isinstance(d, dict) and d.get("key")}


def parse_ref(ref: Any) -> tuple[str, str | None] | None:
    if not isinstance(ref, str) or not ref.startswith("@"):
        return None
    key, _, variant = ref[1:].partition(":")
    return key, (variant or None)


def ref_path(defs: dict[str, dict[str, Any]], ref: str) -> str:
    parsed = parse_ref(ref)
    if parsed is None:
        return ref
    key, variant = parsed
    d = defs.get(key)
    if d is None:
        raise ValueError(f"unknown material @{key}")
    if variant is None:
        return str(d["path"])
    for v in d.get("variants") or []:
        if v.get("name") == variant:
            return str(v["path"])
    raise ValueError(f"material @{key} has no variant {variant}")


def resolve_object(obj: dict[str, Any], defs: dict[str, dict[str, Any]]) -> dict[str, Any]:
    """Copy of a procedural object with library references replaced by depot paths.

    Adds ``material.appearances`` (name -> slot -> path): the default appearance
    plus one per variant name found in the referenced definitions. It also adds
    ``material.slot_uv``, the UV divisor for each slot.
    """
    obj = copy.deepcopy(obj)
    cfg = obj["metadata"]["procedural"]
    mat = cfg.setdefault("material", {})
    slots = dict(mat.get("materials") or {})
    resolved, slot_uv, variants = {}, {}, []
    for slot, ref in slots.items():
        resolved[slot] = ref_path(defs, ref)
        parsed = parse_ref(ref)
        if parsed:
            d = defs[parsed[0]]
            slot_uv[slot] = uv_transform(d)
            if parsed[1] is None:
                variants += [v["name"] for v in d.get("variants") or [] if v["name"] not in variants]
    appearances = {"default": dict(resolved)}
    for name in variants:
        look = {}
        for slot, ref in slots.items():
            parsed = parse_ref(ref)
            d = defs.get(parsed[0]) if parsed else None
            has = parsed and parsed[1] is None and any(v["name"] == name for v in (d or {}).get("variants") or [])
            look[slot] = ref_path(defs, f"@{parsed[0]}:{name}") if has else resolved[slot]
        appearances[name] = look
    mat["materials"] = resolved
    mat["appearances"] = appearances
    mat["slot_uv"] = slot_uv
    return obj


def referenced_keys(project: dict[str, Any], objects: list[dict[str, Any]] | None = None) -> set[str]:
    keys = set()
    for o in objects if objects is not None else project.get("objects") or []:
        proc = ((o.get("metadata") or {}).get("procedural") or {})
        for ref in ((proc.get("material") or {}).get("materials") or {}).values():
            parsed = parse_ref(ref)
            if parsed:
                keys.add(parsed[0])
    return keys


def in_scope(project: dict[str, Any], objects: list[dict[str, Any]], premise_id: str | None) -> list[dict[str, Any]]:
    """Definitions a build ships: referenced by the objects in scope, or owned by the premise."""
    defs = definitions(project)
    keys = referenced_keys(project, objects)
    for d in defs.values():
        if premise_id and d.get("premise_id") == premise_id:
            keys.add(d["key"])
    return [defs[k] for k in sorted(keys) if k in defs]


def generated_paths(project: dict[str, Any]) -> dict[str, list[str]]:
    """Depot paths a build generates (.mi and imported textures) -> the paths they reference (for the dependency resolver)."""
    out: dict[str, list[str]] = {}
    for d in definitions(project).values():
        try:
            built = build_material(d)
        except (ValueError, KeyError, TypeError):
            continue
        for doc in built["documents"]:
            children = [doc["base"]] + [str(v) for v in doc["values"].values() if isinstance(v, str) and "\\" in v]
            out[_norm(doc["path"])] = sorted({_norm(c) for c in children})
        for job in built["textures"]:
            out.setdefault(_norm(job["path"]), [])
    return out


def base_parameters_for(base: str, lookup: Callable[[str], Path | None] | None,
                        cache: dict[str, dict[str, str] | None]) -> dict[str, str] | None:
    """Parameter table from ``<base>.json`` in the mod sources, if present."""
    key = _norm(base)
    if key in cache:
        return cache[key]
    found = None
    hit = lookup(key) if lookup else None
    if hit and Path(hit).is_file():
        try:
            found = template_parameters(json.loads(Path(hit).read_text(encoding="utf-8"))) or None
        except (OSError, ValueError):
            found = None
    cache[key] = found
    return found


def _run_worker(worker: str, source: Path, target: Path, timeout: int) -> tuple[bool, str]:
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        proc = subprocess.run([worker, "deserialize", "--input", str(source), "--output", str(target), "--json"],
                              capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)
    ok = proc.returncode == 0 and target.is_file() and target.read_bytes()[:4] == b"CR2W"
    return ok, (proc.stdout + proc.stderr)[-2000:]


def write_texture_source(job: dict[str, Any], raw_root: Path) -> Path:
    """Put the job's image in the raw tree next to its .xbm depot path and return it."""
    rel = Path(*_norm(job["path"]).split("\\"))
    if job.get("solid") is not None:
        image = raw_root / rel.with_suffix(".png")
        image.parent.mkdir(parents=True, exist_ok=True)
        image.write_bytes(solid_png(job["solid"], int(job.get("size") or 4)))
        return image
    src = Path(str(job["file"])).expanduser()
    if not src.is_file():
        raise FileNotFoundError(f"texture image {src} does not exist")
    image = raw_root / rel.with_suffix(src.suffix.lower())
    image.parent.mkdir(parents=True, exist_ok=True)
    image.write_bytes(src.read_bytes())
    return image


def import_texture(cli: str, image: Path, archive_root: Path, raw_root: Path, timeout: int) -> tuple[Path | None, str]:
    """Run the WolvenKit CLI import on an image; returns the CR2W .xbm placed in the archive tree."""
    rel = image.relative_to(raw_root).with_suffix(".xbm")
    target = archive_root / rel
    cmd = _texture_command(cli, image, target)
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"{exc} ({' '.join(cmd)})"
    out = (proc.stdout + proc.stderr)[-2000:]
    for candidate in (target, image.with_suffix(".xbm")):
        if candidate.is_file() and candidate.read_bytes()[:4] == b"CR2W":
            if candidate != target:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(candidate.read_bytes())
                candidate.unlink()
            return target, out
    return None, f"WolvenKit did not write {rel} (exit {proc.returncode}): {out}"


def apply_to_workspace(project_file: str | Path, workspace: str | Path, *, premise_id: str | None = None, worker: str | None = None,
                       cli: str | None = None, base_json: Callable[[str], Path | None] | None = None,
                       reference: dict[str, Any] | None = None, output: str | Path | None = None, timeout: int = 300) -> dict[str, Any]:
    """Build Mod stage: every material the build uses becomes CR2W .mi files and imported .xbm textures."""
    from .procedural import procedural_objects

    project = json.loads(Path(project_file).read_text(encoding="utf-8")) if Path(project_file).is_file() else {"objects": []}
    objects = procedural_objects(project, premise_id)
    defs = definitions(project)
    report: dict[str, Any] = {"materials": [], "textures": [], "issues": [], "warnings": [], "ready": True}
    for o in objects:
        for slot, ref in (((o["metadata"]["procedural"].get("material") or {}).get("materials")) or {}).items():
            try:
                ref_path(defs, ref)
            except ValueError as exc:
                report["issues"].append({"object_id": o.get("id"), "error": f"{o.get('name')}: materials.{slot}: {exc}"})
    scope = in_scope(project, objects, premise_id)
    root = Path(workspace)
    raw_root, archive_root = root / "source" / "raw", root / "source" / "archive"
    cache: dict[str, dict[str, str] | None] = {}
    for d in scope:
        try:
            built = build_material(d, base_parameters=base_parameters_for(d["base"], base_json, cache), reference=reference)
        except (ValueError, KeyError, TypeError) as exc:
            report["issues"].append({"material": d.get("key"), "error": f"@{d.get('key')}: {exc}"})
            continue
        for e in built["errors"]:
            report["issues"].append({"material": d["key"], "error": f"@{d['key']}: {e}"})
        report["warnings"] += [f"@{d['key']}: {w}" for w in built["warnings"]]
        entry = {"key": d["key"], "profile_source": built["profile_source"], "files": []}
        report["materials"].append(entry)
        if built["errors"]:
            continue
        for doc in built["documents"]:
            rel = Path(*_norm(doc["path"]).split("\\"))
            doc_path = raw_root / Path(str(rel) + ".json")
            doc_path.parent.mkdir(parents=True, exist_ok=True)
            doc_path.write_text(json.dumps(doc["document"], ensure_ascii=False), encoding="utf-8")
            row = {"path": doc["path"], "variant": doc["variant"], "json": str(doc_path), "converted": False}
            entry["files"].append(row)
            if not worker:
                report["issues"].append({"material": d["key"], "error": f"@{d['key']}: the WolvenKit worker is not ready (build_worker_preflight); it writes the .mi"})
                continue
            target = archive_root / rel
            ok, out = _run_worker(worker, doc_path, target, timeout)
            if not ok:
                report["issues"].append({"material": d["key"], "error": f"@{d['key']}: the worker did not write a CR2W {doc['path']}", "output": out})
                continue
            row.update(converted=True, file=str(target))
        for job in built["textures"]:
            trow = {"material": d["key"], "path": job["path"], "source": "solid" if job.get("solid") is not None else job.get("file"), "converted": False}
            report["textures"].append(trow)
            try:
                image = write_texture_source(job, raw_root)
            except (OSError, FileNotFoundError) as exc:
                report["issues"].append({"material": d["key"], "error": f"@{d['key']}: {exc}"})
                continue
            trow["image"] = str(image)
            if not cli:
                report["issues"].append({"material": d["key"], "error": f"@{d['key']}: WolvenKit CLI not found; it imports {job['path']}"})
                continue
            xbm, out = import_texture(cli, image, archive_root, raw_root, timeout)
            if xbm is None:
                report["issues"].append({"material": d["key"], "error": f"@{d['key']}: texture {job['path']}: {out}"})
                continue
            trow.update(converted=True, file=str(xbm))
    report["ready"] = not report["issues"]
    if output is not None:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        Path(output).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report
