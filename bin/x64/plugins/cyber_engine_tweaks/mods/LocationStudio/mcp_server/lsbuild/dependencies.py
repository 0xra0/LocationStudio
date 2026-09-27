"""Asset dependency resolver for LocationStudio builds.

Starting from what the project's objects reference (depot paths of meshes,
entity templates, materials, textures, particles/effects..., TweakDB records
and audio events), recursively find everything that has to ship with the mod
and flag what is missing before the build.

How a reference is classified:

* **project**: the file exists in a mod source folder (a WolvenKit project's
  ``source/archive`` tree, WolvenKit raw JSON under ``source/raw``, or any
  folder laid out by depot path). It must ship and its own references are
  followed: JSON through every ``DepotPath``, binary CR2W files through the
  depot-path strings of their import table.
* **project_archive**: the path hash is inside a prebuilt ``.archive`` given as
  a source; the archive ships next to the mod and its dependency table (path
  hashes) is followed.
* **vanilla**: the FNV-1a64 path hash is in the game's content archives
  (``archive/pc/content`` and ``archive/pc/ep1``), read from their RDAR index.
* **other_mod**: provided by an installed mod archive in ``archive/pc/mod``;
  that mod becomes an external requirement.
* **missing**: none of the above. Blocks the build.
* **unknown**: not found locally and no vanilla index is available.
* **dynamic**: ArchiveXL substitution paths (``*`` or ``{...}``); resolved at runtime.

TweakDB records are ``project`` when a TweakXL YAML in the sources defines
them, ``other_mod`` when an installed mod's YAML does, and ``unverified``
otherwise (the vanilla TweakDB is not indexed). Audio events are ``project``
when a custom-sound ``info.json`` in the sources defines them, else
``unverified`` (vanilla Wwise events are not indexed).
"""
from __future__ import annotations

import json
import re
import shutil
import struct
from array import array
from collections import deque
from pathlib import Path
from typing import Any, Iterable

REPORT_SCHEMA = "locationstudio-dependencies/1"
INDEX_SCHEMA = "locationstudio-archive-index/1"

EXTENSIONS = (
    "mesh", "mi", "mt", "remt", "mlsetup", "mlmask", "mltemplate", "xbm", "ent", "app", "anims", "animgraph", "rig",
    "physicalscene", "particle", "effect", "workspot", "scene", "inkatlas", "inkwidget", "inkstyle", "morphtarget",
    "cfoliage", "streamingsector", "streamingblock", "opusinfo", "wem", "gradient", "hp", "fx", "sampler", "texarray",
    "envprobe", "cubemap", "bk2", "csv", "json", "cooked_mlsetup", "terrainsetup", "dtex", "fnt", "journal",
    "questphase", "quest", "garmentlayerparams", "facialsetup", "animgraph", "ragdoll", "bnk", "phys",
)
_EXT = "|".join(sorted(set(EXTENSIONS), key=len, reverse=True))
# Depot path: at least one folder, segments of safe characters (ArchiveXL * { } allowed), a known extension.
DEPOT_RE = re.compile(r"(?<![A-Za-z0-9_\-.])((?:[A-Za-z0-9_\-.@*{}]+[\\/])+[A-Za-z0-9_\-.@*{}]+\.(?:" + _EXT + r"))(?![A-Za-z0-9_])", re.I)
DEPOT_BYTES_RE = re.compile(rb"((?:[A-Za-z0-9_\-.@*{}]+\\)+[A-Za-z0-9_\-.@*{}]+\.(?:" + _EXT.encode() + rb"))(?![A-Za-z0-9_])", re.I)
RECORD_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$")
YAML_TOP_KEY = re.compile(r"^([A-Za-z_][A-Za-z0-9_.]*)\s*:", re.M)


# --------------------------------------------------------------------------- paths and hashes

def normalize(path: str) -> str:
    return str(path).strip().replace("/", "\\").strip("\\").lower()


def fnv1a64(data: bytes) -> int:
    h = 0xCBF29CE484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def path_hash(path: str) -> int:
    return fnv1a64(normalize(path).encode("utf-8"))


def is_dynamic(path: str) -> bool:
    return any(c in path for c in "*{}")


def extension(path: str) -> str:
    name = normalize(path).rsplit("\\", 1)[-1]
    return name.split(".", 1)[1] if "." in name else ""


# --------------------------------------------------------------------------- RDAR archives

def read_archive(path: str | Path, *, dependencies: bool = False) -> dict[str, Any]:
    """Read an RDAR archive index: file path hashes and, optionally, each file's dependency hashes."""
    with open(path, "rb") as f:
        header = f.read(40)
        if len(header) < 40 or header[:4] != b"RDAR":
            raise ValueError(f"{path}: not a REDengine archive")
        _magic, _version, index_pos, _index_size = struct.unpack_from("<4sIQI", header, 0)
        f.seek(index_pos)
        head = f.read(28)
        if len(head) < 28:
            raise ValueError(f"{path}: truncated archive index")
        _tab_off, _tab_size, _crc, n_files, n_segments, n_deps = struct.unpack("<IIQIII", head)
        entries = f.read(56 * n_files)
        if len(entries) < 56 * n_files:
            raise ValueError(f"{path}: truncated file table")
        hashes = array("Q")
        ranges = []
        for i in range(n_files):
            h, _ts, _inline, _s0, _s1, d0, d1 = struct.unpack_from("<QqIIIII", entries, i * 56)
            hashes.append(h)
            ranges.append((d0, d1))
        deps: dict[int, list[int]] = {}
        if dependencies and n_deps:
            f.seek(16 * n_segments, 1)
            raw = f.read(8 * n_deps)
            table = array("Q")
            table.frombytes(raw[: 8 * (len(raw) // 8)])
            for h, (d0, d1) in zip(hashes, ranges):
                if d1 > d0:
                    deps[h] = list(table[d0:d1])
    return {"hashes": hashes, "dependencies": deps}


def build_index(game_root: str | Path, cache: str | Path) -> dict[str, Any]:
    """Index every vanilla content archive's path hashes into a compact cache file."""
    root = Path(game_root)
    folders = [root / "archive" / "pc" / "content", root / "archive" / "pc" / "ep1"]
    archives = sorted(p for d in folders if d.is_dir() for p in d.glob("*.archive"))
    if not archives:
        raise FileNotFoundError(f"no content archives under {root / 'archive' / 'pc'}; pass the game root")
    all_hashes = array("Q")
    sources, errors = [], []
    for a in archives:
        try:
            info = read_archive(a)
        except (OSError, ValueError, struct.error) as exc:
            errors.append({"archive": str(a), "error": str(exc)})
            continue
        all_hashes.extend(info["hashes"])
        sources.append({"archive": a.name, "files": len(info["hashes"]), "mtime": int(a.stat().st_mtime)})
    unique = array("Q", sorted(set(all_hashes)))
    cache = Path(cache)
    cache.parent.mkdir(parents=True, exist_ok=True)
    with open(cache, "wb") as f:
        unique.tofile(f)
    meta = {"schema": INDEX_SCHEMA, "game_root": str(root), "archives": sources, "hashes": len(unique), "errors": errors}
    cache.with_suffix(".json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return meta


class HashSet:
    """Sorted uint64 array with binary search; small memory for ~2M hashes."""

    def __init__(self, values: Iterable[int] = ()):
        self.values = array("Q", sorted(set(values)))

    @classmethod
    def load(cls, cache: str | Path) -> "HashSet":
        out = cls()
        data = array("Q")
        with open(cache, "rb") as f:
            data.frombytes(f.read())
        out.values = data
        return out

    def __contains__(self, h: int) -> bool:
        v, lo, hi = self.values, 0, len(self.values)
        while lo < hi:
            mid = (lo + hi) // 2
            if v[mid] < h:
                lo = mid + 1
            else:
                hi = mid
        return lo < len(v) and v[lo] == h

    def __len__(self) -> int:
        return len(self.values)


def index_info(cache: str | Path) -> dict[str, Any]:
    cache = Path(cache)
    meta_file = cache.with_suffix(".json")
    if not cache.is_file() or not meta_file.is_file():
        return {"available": False, "cache": str(cache)}
    meta = json.loads(meta_file.read_text(encoding="utf-8"))
    meta.update({"available": True, "cache": str(cache)})
    return meta


def mod_archives(game_root: str | Path | None) -> dict[int, str]:
    """Installed mod archives: path hash -> archive file name."""
    out: dict[int, str] = {}
    if not game_root:
        return out
    folder = Path(game_root) / "archive" / "pc" / "mod"
    if not folder.is_dir():
        return out
    for a in sorted(folder.glob("*.archive")):
        try:
            for h in read_archive(a)["hashes"]:
                out.setdefault(h, a.name)
        except (OSError, ValueError, struct.error):
            continue
    return out


def tweak_records(folders: Iterable[str | Path]) -> dict[str, Path]:
    """Top-level TweakXL record names defined by YAML files under the folders."""
    out: dict[str, Path] = {}
    for folder in folders:
        folder = Path(folder)
        if not folder.is_dir():
            continue
        for y in sorted(list(folder.rglob("*.yaml")) + list(folder.rglob("*.yml"))):
            try:
                text = y.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for m in YAML_TOP_KEY.finditer(text):
                if "." in m.group(1):
                    out.setdefault(m.group(1), y)
    return out


def _record_block(file: Path, record: str) -> str:
    text = file.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^" + re.escape(record) + r"\s*:.*?(?=^\S|\Z)", text, re.M | re.S)
    return m.group(0) if m else ""


def custom_sounds(folders: Iterable[str | Path]) -> dict[str, Path]:
    """Custom sound event names from REDmod customSounds info.json files."""
    out: dict[str, Path] = {}
    for folder in folders:
        folder = Path(folder)
        if not folder.is_dir():
            continue
        for info in folder.rglob("info.json"):
            try:
                data = json.loads(info.read_text(encoding="utf-8"))
            except (OSError, ValueError):
                continue
            for s in data.get("customSounds", []) if isinstance(data, dict) else []:
                if isinstance(s, dict) and s.get("name"):
                    out.setdefault(str(s["name"]), info)
    return out


# --------------------------------------------------------------------------- reference extraction

def refs_from_json(value: Any) -> tuple[set[str], set[int]]:
    paths: set[str] = set()
    hashes: set[int] = set()

    def walk(v: Any) -> None:
        if isinstance(v, dict):
            dp = v.get("DepotPath")
            if isinstance(dp, dict):
                val = dp.get("$value")
                if dp.get("$storage") == "uint64":
                    try:
                        if int(val):
                            hashes.add(int(val))
                    except (TypeError, ValueError):
                        pass
                elif isinstance(val, str) and val:
                    paths.add(val)
            for k, x in v.items():
                if k != "DepotPath":
                    walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)
        elif isinstance(v, str) and DEPOT_RE.fullmatch(v.strip()):
            paths.add(v.strip())

    walk(value)
    return paths, hashes


def refs_from_binary(data: bytes) -> set[str]:
    return {m.group(1).decode("ascii", "replace") for m in DEPOT_BYTES_RE.finditer(data)}


def _depot_relative(rel: str) -> str | None:
    """Depot path of a file under a source root; WolvenKit project folders are unwrapped."""
    padded = "\\" + rel
    if "\\source\\resources\\" in padded:
        return None
    for marker in ("\\source\\archive\\", "\\source\\raw\\"):
        i = padded.find(marker)
        if i >= 0:
            return padded[i + len(marker):]
    return rel


class Sources:
    """Mod source folders and prebuilt archives, indexed by normalized depot path and hash.

    A root may be a folder laid out by depot path, a WolvenKit project (its source/archive and source/raw trees
    are unwrapped, source/resources is skipped), or a prebuilt .archive file.
    """

    def __init__(self, roots: Iterable[str | Path]):
        self.files: dict[str, tuple[Path, str]] = {}  # depot -> (file, 'binary'|'json')
        self.by_hash: dict[int, str] = {}
        self.archives: dict[int, Path] = {}
        self.archive_deps: dict[int, list[int]] = {}
        self.roots: list[str] = []
        self.errors: list[dict[str, str]] = []
        for root in roots:
            root = Path(root)
            if root.is_file() and root.suffix == ".archive":
                self._add_archive(root)
                continue
            if not root.is_dir():
                continue
            self.roots.append(str(root))
            for f in root.rglob("*"):
                if not f.is_file():
                    continue
                if f.suffix == ".archive":
                    self._add_archive(f)
                    continue
                rel = _depot_relative(normalize(str(f.relative_to(root))))
                if rel is None:
                    continue
                if rel.endswith(".json") and extension(rel[:-5]) in EXTENSIONS and extension(rel[:-5]) != "json":
                    depot, kind = rel[:-5], "json"
                elif extension(rel) in EXTENSIONS:
                    depot, kind = rel, "binary" if extension(rel) != "json" else "json"
                else:
                    continue
                # A cooked binary wins over its raw JSON twin.
                if depot not in self.files or kind == "binary":
                    self.files[depot] = (f, kind)
                    self.by_hash[path_hash(depot)] = depot

    def _add_archive(self, path: Path) -> None:
        try:
            info = read_archive(path, dependencies=True)
        except (OSError, ValueError, struct.error) as exc:
            self.errors.append({"file": str(path), "error": str(exc)})
            return
        for h in info["hashes"]:
            self.archives.setdefault(h, path)
        self.archive_deps.update(info["dependencies"])


# --------------------------------------------------------------------------- project roots

_SKIP_KEYS = {"vanilla_source", "runtime", "reference_area_id", "procedural"}


def project_roots(project: dict[str, Any], *, premise_id: str | None = None) -> list[dict[str, Any]]:
    """Per exported object: the resources it references."""
    layers = {l.get("id"): l for l in project.get("layers", []) if isinstance(l, dict)}
    roots = []
    for o in project.get("objects", []) or []:
        if not isinstance(o, dict):
            continue
        md = o.get("metadata") or {}
        if md.get("reference_area_id"):
            continue
        layer = layers.get(o.get("layer"))
        if layer and layer.get("export") is False:
            continue
        if premise_id and o.get("premise_id") != premise_id:
            continue
        refs: dict[tuple[str, str], str] = {}

        def add(kind: str, value: Any, field: str) -> None:
            if isinstance(value, str) and value.strip():
                refs.setdefault((kind, value.strip()), field)

        wb = md.get("world_builder") or {}
        key = wb.get("definition_key")
        if key == "entity_record":
            add("record", wb.get("resource_path"), "world_builder.resource_path")
        elif key == "audio":
            add("audio", wb.get("resource_path"), "world_builder.resource_path")
        # Procedural geometry: its mesh is generated at build time; the template's materials are real dependencies.
        proc = md.get("procedural") if isinstance(md.get("procedural"), dict) else None
        if proc:
            material = proc.get("material") or {}
            add("path", material.get("template"), "procedural.material.template")
            add("path", material.get("glass_template"), "procedural.material.glass_template")
            for slot, mi in (material.get("materials") or {}).items() if isinstance(material.get("materials"), dict) else []:
                if isinstance(mi, str) and mi.startswith("@"):
                    # Material library reference: the generated .mi (and every variant) ships with the build.
                    from .materials import definitions, ref_path
                    defs = definitions(project)
                    try:
                        add("path", ref_path(defs, mi), f"procedural.material.materials.{slot}")
                        key = mi[1:].partition(":")[0]
                        if ":" not in mi:
                            for v in defs[key].get("variants") or []:
                                add("path", v.get("path"), f"procedural.material.materials.{slot} (variant {v.get('name')})")
                    except (ValueError, KeyError):
                        add("path", mi, f"procedural.material.materials.{slot}")
                else:
                    add("path", mi, f"procedural.material.materials.{slot}")
        if (md.get("npc_population") or {}).get("record"):
            add("record", md["npc_population"]["record"], "npc_population.record")
        for fld in ("event", "sound_event"):
            for block in ("ambient_audio", "ambient_zone"):
                add("audio", (md.get(block) or {}).get(fld), f"{block}.{fld}")

        def scan(v: Any, where: str) -> None:
            if isinstance(v, dict):
                for k, x in v.items():
                    if k not in _SKIP_KEYS:
                        scan(x, f"{where}.{k}" if where else str(k))
            elif isinstance(v, list):
                for i, x in enumerate(v):
                    scan(x, f"{where}[{i}]")
            elif isinstance(v, str):
                s = v.strip()
                if DEPOT_RE.fullmatch(s):
                    add("path", s, where)

        scan({k: v for k, v in o.items() if k in ("template", "metadata")}, "")
        if refs:
            roots.append({"object_id": o.get("id"), "name": o.get("name"), "premise_id": o.get("premise_id"),
                          "refs": [{"kind": k, "value": v, "field": f} for (k, v), f in sorted(refs.items())]})
    return roots


# --------------------------------------------------------------------------- resolver

def resolve(roots: list[dict[str, Any]], *, sources: Sources, vanilla: HashSet | None = None,
            mods: dict[int, str] | None = None, project_tweaks: dict[str, Path] | None = None,
            mod_tweaks: dict[str, Path] | None = None, sounds: dict[str, Path] | None = None,
            max_depth: int = 32, generated: dict[str, list[str]] | None = None) -> dict[str, Any]:
    """`generated`: depot paths the build itself writes (material library .mi and textures) -> their references."""
    mods = mods or {}
    generated = generated or {}
    project_tweaks = project_tweaks or {}
    mod_tweaks = mod_tweaks or {}
    sounds = sounds or {}
    nodes: dict[str, dict[str, Any]] = {}
    parent: dict[str, str | None] = {}
    queue: deque[tuple[str, int]] = deque()
    errors: list[dict[str, str]] = list(sources.errors)

    def node_key_for_hash(h: int) -> str:
        return sources.by_hash.get(h) or f"#{h:016x}"

    def enqueue(key: str, via: str, depth: int, kind: str = "path") -> None:
        n = nodes.get(key)
        if n is None:
            n = nodes[key] = {"path": key, "kind": kind, "referenced_by": [], "depth": depth}
            parent[key] = via
            queue.append((key, depth))
        if via not in n["referenced_by"]:
            n["referenced_by"].append(via)

    for root in roots:
        via = f"object:{root.get('object_id')}"
        for ref in root.get("refs", []):
            if ref["kind"] == "path":
                enqueue(normalize(ref["value"]), via, 0)
            else:
                enqueue(f"{ref['kind']}:{ref['value']}", via, 0, ref["kind"])

    while queue:
        key, depth = queue.popleft()
        n = nodes[key]
        kind = n["kind"]
        children: list[str] = []
        if kind == "record":
            name = key.split(":", 1)[1]
            if name in project_tweaks:
                n.update(status="project", ship=True, found_at=str(project_tweaks[name]), format="tweakxl")
                block = _record_block(project_tweaks[name], name)
                for p in {m.group(1) for m in DEPOT_RE.finditer(block)}:
                    children.append(normalize(p))
                base = re.search(r"^\s+\$base\s*:\s*([A-Za-z_][\w.]*)", block, re.M)
                if base:
                    enqueue(f"record:{base.group(1)}", key, depth + 1, "record")
            elif name in mod_tweaks:
                n.update(status="other_mod", ship=False, provided_by=str(mod_tweaks[name]))
            elif not RECORD_RE.match(name):
                n.update(status="missing", ship=False, reason="not a TweakDB record id")
            else:
                n.update(status="unverified", ship=False, reason="not defined by the sources or installed TweakXL mods; assumed vanilla (the vanilla TweakDB is not indexed)")
        elif kind == "audio":
            name = key.split(":", 1)[1]
            if name in sounds:
                n.update(status="project", ship=True, found_at=str(sounds[name]), format="custom_sound")
            else:
                n.update(status="unverified", ship=False, reason="not a custom sound in the sources; assumed a vanilla Wwise event")
        elif key.startswith("#"):
            h = int(key[1:], 16)
            if h in sources.archives:
                n.update(status="project_archive", ship=True, found_at=str(sources.archives[h]))
                children.extend(node_key_for_hash(d) for d in sources.archive_deps.get(h, []))
            elif vanilla is not None and h in vanilla:
                n.update(status="vanilla", ship=False)
            elif h in mods:
                n.update(status="other_mod", ship=False, provided_by=mods[h])
            else:
                n.update(status="missing" if vanilla is not None else "unknown", ship=False,
                         reason="unnamed path hash from a dependency table")
        else:
            n["extension"] = extension(key)
            h = path_hash(key)
            if is_dynamic(key):
                n.update(status="dynamic", ship=False, reason="ArchiveXL dynamic path; resolved at runtime")
            elif key in generated and key not in sources.files:
                n.update(status="generated", ship=True, reason="written by the Build Mod materials stage")
                children.extend(generated[key])
            elif key in sources.files:
                file, fmt = sources.files[key]
                n.update(status="project", ship=True, found_at=str(file), format=fmt)
                try:
                    if fmt == "json":
                        paths, hashes = refs_from_json(json.loads(file.read_text(encoding="utf-8")))
                        children.extend(normalize(p) for p in paths)
                        children.extend(node_key_for_hash(x) for x in hashes)
                    else:
                        children.extend(normalize(p) for p in refs_from_binary(file.read_bytes()))
                except (OSError, ValueError) as exc:
                    errors.append({"file": str(file), "error": f"could not read references: {exc}"})
            elif h in sources.archives:
                n.update(status="project_archive", ship=True, found_at=str(sources.archives[h]))
                children.extend(node_key_for_hash(d) for d in sources.archive_deps.get(h, []))
            elif vanilla is not None and h in vanilla:
                n.update(status="vanilla", ship=False)
            elif h in mods:
                n.update(status="other_mod", ship=False, provided_by=mods[h])
            else:
                n.update(status="missing" if vanilla is not None else "unknown", ship=False,
                         reason="not in the mod sources, the game's content archives or installed mods" if vanilla is not None
                         else "not in the mod sources; build the vanilla archive index to tell vanilla from missing")
        if depth + 1 > max_depth and children:
            errors.append({"file": key, "error": f"dependency depth limit {max_depth} reached"})
            children = []
        for c in children:
            if c and c != key:
                enqueue(c, key, depth + 1)
        n["children"] = sorted(set(c for c in children if c and c != key))

    def chain(key: str) -> list[str]:
        out, seen = [key], {key}
        while parent.get(out[-1]) and parent[out[-1]] not in seen and not str(parent[out[-1]]).startswith("object:"):
            out.append(parent[out[-1]])
            seen.add(out[-1])
        if parent.get(out[-1]):
            out.append(parent[out[-1]])
        return list(reversed(out))

    counts: dict[str, int] = {}
    for n in nodes.values():
        counts[n["status"]] = counts.get(n["status"], 0) + 1
        if n["status"] in ("missing", "unknown"):
            n["chain"] = chain(n["path"])

    # Per object: everything reachable from its references, and what of that is missing.
    missing_keys = {k for k, n in nodes.items() if n["status"] == "missing"}
    objects = []
    for root in roots:
        direct = [normalize(r["value"]) if r["kind"] == "path" else f"{r['kind']}:{r['value']}" for r in root["refs"]]
        seen: set[str] = set()
        stack = [d for d in direct if d in nodes]
        while stack:
            k = stack.pop()
            if k not in seen:
                seen.add(k)
                stack.extend(nodes[k].get("children", []))
        statuses = {k: nodes[k]["status"] for k in direct if k in nodes}
        objects.append({"object_id": root.get("object_id"), "name": root.get("name"), "references": statuses,
                        "dependencies": len(seen), "missing": sorted(seen & missing_keys),
                        "unknown": sum(1 for k in seen if nodes[k]["status"] == "unknown"),
                        "ship": sum(1 for k in seen if nodes[k].get("ship"))})

    ship = [{"path": k, "found_at": n.get("found_at"), "format": n.get("format"), "status": n["status"]}
            for k, n in sorted(nodes.items()) if n.get("ship")]
    external: dict[str, list[str]] = {}
    for k, n in sorted(nodes.items()):
        if n["status"] == "other_mod":
            external.setdefault(str(n.get("provided_by")), []).append(k)
    blocking = counts.get("missing", 0)
    raw_only = [s["path"] for s in ship if s.get("format") == "json"]
    return {
        "schema": REPORT_SCHEMA, "ready": blocking == 0, "counts": counts, "objects_scanned": len(roots),
        "missing": [nodes[k] for k in sorted(missing_keys)],
        "unknown": [n for k, n in sorted(nodes.items()) if n["status"] == "unknown"],
        "unverified": [{"reference": k, "reason": n.get("reason")} for k, n in sorted(nodes.items()) if n["status"] == "unverified"],
        "ship": ship, "raw_json_only": raw_only, "external_requirements": external,
        "objects": objects, "nodes": nodes, "errors": errors, "vanilla_index": vanilla is not None,
    }


def stage(report: dict[str, Any], workspace: str | Path) -> dict[str, Any]:
    """Copy shippable dependencies into a build workspace so pack/package include them."""
    ws = Path(workspace)
    archive_dir = ws / "source" / "archive"
    raw_dir = ws / "source" / "raw"
    tweak_dir = ws / "source" / "resources" / "r6" / "tweaks"
    mod_dir = ws / "source" / "resources" / "archive" / "pc" / "mod"
    copied, skipped = [], []
    archives_done: set[str] = set()
    for item in report.get("ship", []):
        if item.get("status") == "generated":
            skipped.append({"path": item["path"], "reason": "written by the Build Mod materials stage"})
            continue
        src = Path(item["found_at"]) if item.get("found_at") else None
        if not src or not src.is_file():
            skipped.append({"path": item["path"], "reason": "source file not found"})
            continue
        fmt = item.get("format")
        if item["status"] == "project_archive":
            if str(src) in archives_done:
                continue
            archives_done.add(str(src))
            target = mod_dir / src.name
        elif fmt == "tweakxl":
            target = tweak_dir / src.name
        elif fmt == "custom_sound":
            target = ws / "source" / "customSounds" / src.parent.name
            if not target.exists():
                shutil.copytree(src.parent, target)
            copied.append({"path": item["path"], "to": str(target)})
            continue
        elif fmt == "json":
            target = raw_dir / (item["path"].replace("\\", "/") + ".json")
        else:
            target = archive_dir / item["path"].replace("\\", "/")
        try:
            if target.resolve() == src.resolve():
                skipped.append({"path": item["path"], "reason": "already in the workspace"})
                continue
        except OSError:
            pass
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, target)
        copied.append({"path": item["path"], "to": str(target)})
    return {"copied": copied, "skipped": skipped,
            "needs_conversion": report.get("raw_json_only", []),
            "note": "Raw JSON dependencies were staged under source/raw; convert them to CR2W (WolvenKit import) before packing." if report.get("raw_json_only") else None}


def slim(report: dict[str, Any]) -> dict[str, Any]:
    """Report without the full node graph, for MCP replies."""
    out = {k: v for k, v in report.items() if k != "nodes"}
    out["missing"] = [{k: n.get(k) for k in ("path", "kind", "reason", "chain", "referenced_by")} for n in report.get("missing", [])]
    out["unknown"] = [{k: n.get(k) for k in ("path", "reason", "chain")} for n in report.get("unknown", [])][:200]
    return out
