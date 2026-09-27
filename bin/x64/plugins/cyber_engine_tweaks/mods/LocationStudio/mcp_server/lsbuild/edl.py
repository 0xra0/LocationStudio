"""LocationStudio Environment Definition Language (EDL).

An EDL document describes a whole location declaratively: floors and rooms
with walls, doors and windows; room-kit materials; props; lights; collision;
devices and their logic; NPCs with routes and workspots; audio emitters and
reverb; VFX; quest triggers; cameras; occluders; splines; navigation; and
streaming settings. Documents are JSON or YAML (``edl: 1``).

The compiler validates a document, expands parameters, templates and repeats,
resolves every element into the location's local frame, and emits one version-2
LocationStudio authoring plan. Executed in game, that plan is a single undoable
transaction that creates real World Builder resources through the same
backends as the editor, and replaces the previous build of the same document
id. Build Mod then turns the result into game archives (``edl_build``).

Coordinates are metres in the location frame (the plan origin: V, the camera
or an explicit transform). Elements inside a room use that room's frame:
``at`` is relative to the room centre at floor level and ``yaw`` adds to the
room's yaw.
"""
from __future__ import annotations

import ast
import copy
import hashlib
import json
import math
import operator
import re
from pathlib import Path
from typing import Any

SCHEMA_VERSION = 1
PLAN_FORMAT = "locationstudio-authoring-plan"
ID_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")
FACT_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
RECORD_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z0-9_.-]+$")
PARAM_RE = re.compile(r"\$\{([^}]+)\}")
WALLS = {"north", "south", "east", "west"}
EXTENSION_TYPES = {"mesh": "mesh_static", "ent": "entity_template", "mi": "decal", "particle": "particle", "effect": "effect"}
RESOURCE_TYPES = {"mesh_static", "mesh_rotating", "mesh_cloth", "mesh_dynamic", "mesh_proxy", "entity_template", "entity_amm",
                  "entity_record", "device", "decal", "particle", "effect"}
ROOM_KITS = {"common_interior", "kitsch_apartment"}
KIT_ROLES = {"floor", "ceiling", "wall", "door", "window"}
COLLISION_SHAPES = {"box", "capsule", "sphere"}
VOLUME_SHAPES = {"box", "sphere", "cylinder"}
OCCLUDER_MESHES = {"box", "plane", "plane_two_sided"}
DEVICE_KINDS = {"door", "loot_container", "shard", "item"}
LOGIC_KINDS = {"terminal", "door", "elevator", "switch", "camera", "security_system", "fact", "action"}
NAV_EDGES = {"walk", "door", "stairs", "elevator", "jump", "off_mesh", "custom"}
ELEMENT_LISTS = ("objects", "geometry", "lights", "collisions", "devices", "npcs", "workspots", "vfx", "triggers", "cameras", "occluders")
GEOMETRY = {"box", "wall", "floor", "ceiling", "column", "stairs", "ramp", "door_frame", "window", "railing", "pipe", "duct"}
TOP_KEYS = {"edl", "id", "name", "description", "origin", "parameters", "templates", "materials", "premise", "defaults", "streaming",
            "floors", "audio", "splines", "navigation", "logic", "scene", *ELEMENT_LISTS}
_OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul, ast.Div: operator.truediv,
        ast.Mod: operator.mod, ast.Pow: operator.pow, ast.USub: operator.neg, ast.UAdd: operator.pos}


class EdlError(ValueError):
    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors[:10]) + (f" (+{len(errors) - 10} more)" if len(errors) > 10 else ""))
        self.errors = errors


# --------------------------------------------------------------------------- loading and expansion

def load(source: str | Path | dict[str, Any], *, fmt: str | None = None) -> tuple[dict[str, Any], str | None]:
    """Parse a document from a dict, a file path, or JSON/YAML text. Returns (document, source path)."""
    if isinstance(source, dict):
        return copy.deepcopy(source), None
    text, path = str(source), None
    candidate = Path(text).expanduser()
    if "\n" not in text and len(text) < 1024 and candidate.suffix.lower() in {".json", ".yaml", ".yml"}:
        if not candidate.is_file():
            raise EdlError([f"EDL file not found: {candidate}"])
        text, path = candidate.read_text(encoding="utf-8"), str(candidate)
        fmt = fmt or ("json" if candidate.suffix.lower() == ".json" else "yaml")
    if fmt == "json" or (fmt is None and text.lstrip().startswith("{")):
        try:
            doc = json.loads(text)
        except ValueError as exc:
            raise EdlError([f"invalid JSON: {exc}"]) from exc
    else:
        try:
            import yaml  # type: ignore
        except ImportError as exc:  # pragma: no cover - depends on the install
            raise EdlError(["YAML documents need PyYAML (pip install -r mcp_server/requirements.txt); JSON works without it"]) from exc
        try:
            doc = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            raise EdlError([f"invalid YAML: {exc}"]) from exc
    if not isinstance(doc, dict):
        raise EdlError(["an EDL document must be a mapping"])
    return doc, path


def _eval(expr: str, params: dict[str, Any], where: str) -> Any:
    expr = expr.strip()
    if expr in params:
        return params[expr]
    try:
        tree = ast.parse(expr, mode="eval")
    except SyntaxError as exc:
        raise EdlError([f"{where}: cannot parse expression ${{{expr}}}"]) from exc

    def ev(node: ast.AST) -> Any:
        if isinstance(node, ast.Expression):
            return ev(node.body)
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return node.value
        if isinstance(node, ast.Name):
            if node.id not in params:
                raise EdlError([f"{where}: unknown parameter {node.id}"])
            return params[node.id]
        if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
            return _OPS[type(node.op)](ev(node.left), ev(node.right))
        if isinstance(node, ast.UnaryOp) and type(node.op) in _OPS:
            return _OPS[type(node.op)](ev(node.operand))
        raise EdlError([f"{where}: only numbers, parameters and + - * / % ** are allowed in ${{{expr}}}"])

    return ev(tree)


def substitute(value: Any, params: dict[str, Any], where: str = "$") -> Any:
    """Replace ${name} / ${expression}. A string that is only one expression keeps the value's type."""
    if isinstance(value, dict):
        return {k: substitute(v, params, f"{where}.{k}") for k, v in value.items()}
    if isinstance(value, list):
        return [substitute(v, params, f"{where}[{i}]") for i, v in enumerate(value)]
    if isinstance(value, str) and "${" in value:
        whole = PARAM_RE.fullmatch(value.strip())
        if whole:
            return _eval(whole.group(1), params, where)
        return PARAM_RE.sub(lambda m: str(_eval(m.group(1), params, where)), value)
    return value


def _merge(base: Any, over: Any) -> Any:
    if isinstance(base, dict) and isinstance(over, dict):
        out = copy.deepcopy(base)
        for k, v in over.items():
            out[k] = _merge(out.get(k), v) if k in out else copy.deepcopy(v)
        return out
    return copy.deepcopy(over)


def _expand_list(items: Any, templates: dict[str, Any], where: str, errors: list[str]) -> list[dict[str, Any]]:
    """Apply `use:` templates and `repeat:` to one element list."""
    out: list[dict[str, Any]] = []
    if items is None:
        return out
    if not isinstance(items, list):
        errors.append(f"{where}: must be a list")
        return out
    for i, raw in enumerate(items):
        path = f"{where}[{i}]"
        if not isinstance(raw, dict):
            errors.append(f"{path}: must be a mapping")
            continue
        item = raw
        if "use" in item:
            name = item["use"]
            if name not in templates:
                errors.append(f"{path}.use: unknown template {name!r}")
                continue
            item = _merge(templates[name], {k: v for k, v in item.items() if k != "use"})
        rep = item.pop("repeat", None) if isinstance(item, dict) else None
        if rep is None:
            item["_path"] = path
            out.append(item)
            continue
        count = rep.get("count") if isinstance(rep, dict) else None
        if not isinstance(count, int) or not 1 <= count <= 500:
            errors.append(f"{path}.repeat.count: must be an integer from 1 to 500")
            continue
        step = _vec(rep.get("step", [0, 0, 0]), f"{path}.repeat.step", errors)
        yaw_step = float(rep.get("yaw_step", 0) or 0)
        base_at = _vec(item.get("at", [0, 0, 0]), f"{path}.at", errors)
        if step is None or base_at is None:
            continue
        for n in range(count):
            copy_ = copy.deepcopy(item)
            copy_["id"] = f"{item.get('id')}_{n + 1}"
            if item.get("name"):
                copy_["name"] = f"{item['name']} {n + 1}"
            copy_["at"] = [base_at[k] + step[k] * n for k in range(3)]
            copy_["yaw"] = float(item.get("yaw", 0) or 0) + yaw_step * n
            copy_["_path"] = f"{path}#{n + 1}"
            out.append(copy_)
    return out


def _vec(value: Any, where: str, errors: list[str], *, size: int = 3, default_z: float = 0.0) -> list[float] | None:
    if isinstance(value, dict):
        value = [value.get("x"), value.get("y"), value.get("z", default_z)]
    if isinstance(value, (list, tuple)) and len(value) == 2 and size == 3:
        value = [value[0], value[1], default_z]
    if not isinstance(value, (list, tuple)) or len(value) != size:
        errors.append(f"{where}: must be [{', '.join('xyz'[:size])}]")
        return None
    try:
        out = [float(v) for v in value]
    except (TypeError, ValueError):
        errors.append(f"{where}: must contain numbers")
        return None
    if any(math.isnan(v) or math.isinf(v) for v in out):
        errors.append(f"{where}: must be finite")
        return None
    return out


# --------------------------------------------------------------------------- compiler

def _clean(value: Any) -> Any:
    """Drop None values at every depth (JSON null has no Lua equivalent)."""
    if isinstance(value, dict):
        return {k: _clean(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [_clean(v) for v in value if v is not None]
    return value


class _Frame:
    """A room (or the location) frame: origin-local offset, yaw and floor elevation."""

    def __init__(self, x: float = 0.0, y: float = 0.0, z: float = 0.0, yaw: float = 0.0, room: str | None = None):
        self.x, self.y, self.z, self.yaw, self.room = x, y, z, yaw, room

    def place(self, at: list[float], yaw: float = 0.0) -> tuple[dict[str, float], float]:
        r = math.radians(self.yaw)
        dx = at[0] * math.cos(r) - at[1] * math.sin(r)
        dy = at[0] * math.sin(r) + at[1] * math.cos(r)
        return {"x": round(self.x + dx, 5), "y": round(self.y + dy, 5), "z": round(self.z + at[2], 5)}, round(self.yaw + yaw, 5)


class Compiler:
    def __init__(self, doc: dict[str, Any], source: str | None = None, overrides: dict[str, Any] | None = None):
        self.raw = doc
        self.source = source
        self.overrides = overrides or {}
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.steps: list[dict[str, Any]] = []
        self.ids: dict[str, str] = {}  # element id -> kind
        self.resources: dict[tuple[str, str], str] = {}
        self.rooms: dict[str, dict[str, Any]] = {}
        self.floors: dict[str, dict[str, Any]] = {}
        self.counts: dict[str, int] = {}
        self.deferred: list[tuple[str, dict[str, Any], _Frame]] = []

    # -- helpers
    def err(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def alias(self, element_id: str) -> str:
        return "e_" + element_id

    def register(self, element: dict[str, Any], kind: str, where: str) -> str | None:
        eid = element.get("id")
        if not isinstance(eid, str) or not ID_RE.match(eid):
            self.err(where, "id is required ([A-Za-z_][A-Za-z0-9_-]*)")
            return None
        if eid in self.ids:
            self.err(where, f"duplicate id {eid!r} (already a {self.ids[eid]})")
            return None
        self.ids[eid] = kind
        self.counts[kind] = self.counts.get(kind, 0) + 1
        return eid

    def emit(self, step: dict[str, Any], element: str | None = None) -> dict[str, Any]:
        if element:
            step["edl_element"] = element
        self.steps.append(_clean(step))
        return step

    def resource(self, spec: Any, where: str, *, allowed: set[str] | None = None) -> str | None:
        """Import step for a resource (deduplicated); returns the plan alias."""
        kind, path = None, None
        if isinstance(spec, str):
            path = spec.strip()
            if RECORD_RE.match(path) and "\\" not in path and "/" not in path:
                kind = "entity_record"
            else:
                ext = path.rsplit(".", 1)[-1].lower() if "." in path else ""
                kind = EXTENSION_TYPES.get(ext)
                if kind is None:
                    self.err(where, f"cannot infer the resource type of {path!r}; use {{type: ..., path: ...}}")
                    return None
        elif isinstance(spec, dict):
            kind, path = spec.get("type"), str(spec.get("path") or "").strip()
            if kind not in RESOURCE_TYPES:
                self.err(where + ".type", f"must be one of {', '.join(sorted(RESOURCE_TYPES))}")
                return None
        else:
            self.err(where, "resource must be a depot path, a TweakDB record or {type, path}")
            return None
        if not path:
            self.err(where, "resource path is empty")
            return None
        if allowed and kind not in allowed:
            self.err(where, f"a {kind} resource is not valid here (expected {', '.join(sorted(allowed))})")
            return None
        key = (kind, path.lower())
        if key not in self.resources:
            alias = f"r{len(self.resources) + 1}"
            self.resources[key] = alias
            backend_cet = isinstance(spec, dict) and spec.get("backend") == "cet"
            self.steps.insert(self._import_at, _clean({"op": "import_resource", "as": alias, "definition_key": kind, "path": path,
                                                       "allow_cet": True if backend_cet else None}))
            self._import_at += 1
        return "$" + self.resources[key]

    def pose(self, element: dict[str, Any], frame: _Frame, where: str) -> tuple[dict[str, float], dict[str, float]] | None:
        at = _vec(element.get("at", [0, 0, 0]), where + ".at", self.errors)
        if at is None:
            return None
        rot = element.get("rotation") or {}
        if not isinstance(rot, dict):
            self.err(where + ".rotation", "must be {roll, pitch, yaw}")
            return None
        yaw = float(element.get("yaw", rot.get("yaw", 0)) or 0)
        pos, world_yaw = frame.place(at, yaw)
        angles = {"yaw": world_yaw}
        if rot.get("roll") is not None or rot.get("pitch") is not None:
            angles.update(roll=float(rot.get("roll") or 0), pitch=float(rot.get("pitch") or 0))
        return pos, angles

    def frame_for(self, element: dict[str, Any], default: _Frame, where: str) -> _Frame:
        room = element.get("room")
        if room is not None:
            if room not in self.rooms:
                self.err(where + ".room", f"unknown room {room!r}")
                return default
            return self.rooms[room]["frame"]
        floor = element.get("floor")
        if floor is not None:
            if floor not in self.floors:
                self.err(where + ".floor", f"unknown floor {floor!r}")
                return default
            return _Frame(z=self.floors[floor]["elevation"])
        return default

    def common(self, element: dict[str, Any], frame: _Frame, where: str) -> dict[str, Any] | None:
        p = self.pose(element, frame, where)
        if p is None:
            return None
        pos, angles = p
        step: dict[str, Any] = {"premise_id": "$premise", "offset": pos, "yaw": angles["yaw"], "name": element.get("name") or element.get("id")}
        if "roll" in angles:
            step["roll"], step["pitch"] = angles["roll"], angles["pitch"]
        if frame.room:
            step["room_id"] = "$" + self.alias(frame.room)
        if element.get("spawn") is not None:
            step["spawn"] = bool(element["spawn"])
        elif self.defaults.get("spawn") is not None:
            step["spawn"] = bool(self.defaults["spawn"])
        return step

    # -- top level
    def compile(self) -> dict[str, Any]:
        doc = self.raw
        params = dict(doc.get("parameters") or {}) if isinstance(doc.get("parameters"), dict) else {}
        params.update(self.overrides)
        for k, v in params.items():
            if not ID_RE.match(str(k)) or not isinstance(v, (int, float, str, bool)):
                self.err(f"parameters.{k}", "parameters must be simple named numbers, strings or booleans")
        try:
            doc = substitute({k: v for k, v in doc.items() if k != "parameters"}, params)
        except EdlError as exc:
            self.errors.extend(exc.errors)
            return self.result(None)
        self.doc = doc
        if doc.get("edl") != SCHEMA_VERSION:
            self.err("edl", f"must be {SCHEMA_VERSION} (the EDL version this compiler reads)")
        for key in doc:
            if key not in TOP_KEYS:
                self.err(key, "unknown top-level key")
        doc_id = doc.get("id")
        if not isinstance(doc_id, str) or not ID_RE.match(doc_id):
            self.err("id", "a stable document id is required ([A-Za-z_][A-Za-z0-9_-]*); applying the same id replaces the previous build")
            doc_id = "invalid"
        self.doc_id = doc_id
        self.defaults = doc.get("defaults") or {}
        templates = doc.get("templates") or {}
        if not isinstance(templates, dict):
            self.err("templates", "must be a mapping of name -> element fields")
            templates = {}
        self.templates = templates
        origin = self.origin(doc.get("origin", "player"))
        streaming = self.streaming(doc.get("streaming"))
        canonical = json.dumps(doc, sort_keys=True, ensure_ascii=False, default=str)
        self.hash = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]
        self.emit({"op": "edl_begin", "doc": doc_id, "name": doc.get("name") or doc_id, "hash": self.hash,
                   "source": self.source, "streaming": streaming})
        self._import_at = len(self.steps)
        self.materials(doc.get("materials"))
        premise = doc.get("premise") or {}
        if not isinstance(premise, dict):
            self.err("premise", "must be a mapping")
            premise = {}
        floors = doc.get("floors") or []
        first_height = float((floors[0] or {}).get("height", 3.0)) if isinstance(floors, list) and floors and isinstance(floors[0], dict) else 3.0
        self.floor_height = first_height
        self.emit({"op": "create_premise", "as": "premise", "name": doc.get("name") or doc_id, "kind": premise.get("kind", "interior"),
                   "levels": max(1, len(floors) if isinstance(floors, list) else 1), "floor_height": first_height,
                   "tags": ["edl", doc_id] + list(premise.get("tags") or []), "notes": premise.get("notes") or doc.get("description")})
        self.compile_floors(floors)
        root = _Frame()
        for kind in ELEMENT_LISTS:
            for element in _expand_list(doc.get(kind), templates, kind, self.errors):
                self.element(kind, element, self.frame_for(element, root, element["_path"]))
        self.audio(doc.get("audio"), root)
        for kind, element, frame in self.deferred:
            self.element_late(kind, element, frame)
        self.splines(doc.get("splines"), root)
        self.navigation(doc.get("navigation"), root)
        self.logic(doc.get("logic"))
        scene = doc.get("scene")
        if scene:
            name = scene.get("name") if isinstance(scene, dict) else None
            self.emit({"op": "capture_scene", "as": "scene", "name": name or f"{doc.get('name') or doc_id} scene", "premise_id": "$premise",
                       "activate": bool(scene.get("activate")) if isinstance(scene, dict) else False})
        return self.result(origin, streaming)

    def origin(self, value: Any) -> Any:
        if value in ("player", "camera"):
            return value
        if isinstance(value, dict):
            pos = _vec(value.get("position"), "origin.position", self.errors)
            if pos is None:
                return "player"
            rot = value.get("rotation") or {}
            return {"position": {"x": pos[0], "y": pos[1], "z": pos[2], "w": 1},
                    "rotation": {"roll": float(rot.get("roll", 0) or 0), "pitch": float(rot.get("pitch", 0) or 0),
                                 "yaw": float(value.get("yaw", rot.get("yaw", 0)) or 0)}}
        self.err("origin", "must be player, camera or {position: [x,y,z], yaw}")
        return "player"

    def streaming(self, value: Any) -> dict[str, Any]:
        if value is None:
            return {}
        if not isinstance(value, dict):
            self.err("streaming", "must be a mapping")
            return {}
        out: dict[str, Any] = {}
        if value.get("category") is not None:
            cats = {"exterior": 0, "interior": 1, "quest": 2, "navigation": 3, "alwaysloaded": 4}
            cat = value["category"]
            if isinstance(cat, str) and cat.lower() in cats:
                out["category"] = cats[cat.lower()]
            elif isinstance(cat, int) and 0 <= cat <= 4:
                out["category"] = cat
            else:
                self.err("streaming.category", f"must be one of {', '.join(cats)} or 0-4")
        if value.get("level") is not None:
            if isinstance(value["level"], int) and 0 <= value["level"] <= 10:
                out["level"] = value["level"]
            else:
                self.err("streaming.level", "must be an integer 0-10")
        if value.get("cell") is not None:
            cell = _vec(value["cell"], "streaming.cell", self.errors)
            if cell is not None:
                if any(v <= 0 for v in cell):
                    self.err("streaming.cell", "sizes must be positive")
                out["cell"] = {"x": cell[0], "y": cell[1], "z": cell[2]}
        if value.get("range") is not None:
            try:
                rng = float(value["range"])
                if rng <= 0:
                    raise ValueError
                self.defaults.setdefault("stream_range", rng)
                out["range"] = rng
            except (TypeError, ValueError):
                self.err("streaming.range", "must be a positive number of metres")
        return out

    def materials(self, value: Any) -> None:
        if not value:
            return
        if not isinstance(value, dict):
            self.err("materials", "must be a mapping")
            return
        step: dict[str, Any] = {"op": "set_room_kit"}
        kit = value.get("room_kit")
        if kit is not None:
            if kit not in ROOM_KITS:
                self.err("materials.room_kit", f"must be one of {', '.join(sorted(ROOM_KITS))}")
            step["preset"] = kit
        roles = {}
        for role, spec in (value.get("roles") or {}).items():
            if role not in KIT_ROLES:
                self.err(f"materials.roles.{role}", f"must be one of {', '.join(sorted(KIT_ROLES))}")
                continue
            alias = self.resource(spec, f"materials.roles.{role}", allowed={"mesh_static"})
            if alias:
                roles[role] = alias
        if roles:
            step["roles"] = roles
            self.warnings.append("materials.roles changes the project's room kit, so it affects every room built afterwards, not only this document")
        if len(step) > 1:
            self.emit(step)

    def compile_floors(self, floors: Any) -> None:
        if not isinstance(floors, list):
            self.err("floors", "must be a list")
            return
        elevation = 0.0
        for fi, floor in enumerate(floors):
            where = f"floors[{fi}]"
            if not isinstance(floor, dict):
                self.err(where, "must be a mapping")
                continue
            fid = self.register(floor, "floor", where)
            height = float(floor.get("height", self.floor_height) or self.floor_height)
            level = int(floor.get("level", fi))
            elev = float(floor["elevation"]) if floor.get("elevation") is not None else elevation
            elevation = elev + height
            if fid:
                self.floors[fid] = {"elevation": elev, "height": height, "level": level}
            for ri, room in enumerate(_expand_list(floor.get("rooms"), self.templates, f"{where}.rooms", self.errors)):
                self.room(room, room["_path"], elev, height, level)

    def room(self, room: dict[str, Any], where: str, elevation: float, floor_height: float, level: int) -> None:
        rid = self.register(room, "room", where)
        at = _vec(room.get("at", [0, 0, 0]), where + ".at", self.errors)
        size = room.get("size")
        if isinstance(size, dict):
            size = [size.get("width"), size.get("depth"), size.get("height", floor_height)]
        if isinstance(size, list) and len(size) == 2:
            size = [size[0], size[1], room.get("height", floor_height)]
        size = _vec(size, where + ".size", self.errors) if size is not None else None
        if size is None:
            if room.get("size") is None:
                self.err(where + ".size", "is required ([width, depth] or [width, depth, height])")
            return
        if at is None or rid is None:
            return
        if not (0.5 <= size[0] <= 200 and 0.5 <= size[1] <= 200 and 1.5 <= size[2] <= 50):
            self.err(where + ".size", "width/depth must be 0.5-200 m and height 1.5-50 m")
        yaw = float(room.get("yaw", 0) or 0)
        z_room = elevation + at[2]
        self.rooms[rid] = {"frame": _Frame(at[0], at[1], z_room, yaw, rid), "size": size}
        wall = room.get("walls") or {}
        self.emit({"op": "create_room", "as": self.alias(rid), "premise_id": "$premise", "name": room.get("name") or rid,
                   "width": size[0], "depth": size[1], "height": size[2], "x": at[0], "y": at[1],
                   "z": round(z_room - level * self.floor_height, 5), "level": level, "yaw": yaw,
                   "wall_thickness": wall.get("thickness") if isinstance(wall, dict) else None, "spawn": False}, rid)
        for kind, default_h, sill in (("doors", 2.2, 0.0), ("windows", 1.2, 1.0)):
            for oi, op in enumerate(room.get(kind) or []):
                ow = f"{where}.{kind}[{oi}]"
                if not isinstance(op, dict) or op.get("wall") not in WALLS:
                    self.err(ow + ".wall", "must be north, south, east or west")
                    continue
                width = float(op.get("width", 1.0 if kind == "doors" else 1.5))
                height = float(op.get("height", default_h))
                wall_len = size[0] if op["wall"] in ("north", "south") else size[1]
                offset = float(op.get("offset", 0))
                if width >= wall_len or abs(offset) + width / 2 > wall_len / 2:
                    self.err(ow, f"does not fit on the {op['wall']} wall ({wall_len} m)")
                osill = float(op.get("sill", sill))
                if osill + height > size[2]:
                    self.err(ow, "is taller than the room")
                self.counts[kind] = self.counts.get(kind, 0) + 1
                self.emit({"op": "add_opening", "room_id": "$" + self.alias(rid), "kind": "door" if kind == "doors" else "window",
                           "wall": op["wall"], "offset": offset, "width": width, "height": height, "sill": osill, "spawn": False})
        spawn = room.get("spawn", self.defaults.get("spawn", True))
        if spawn:
            self.emit({"op": "spawn", "kind": "room", "id": "$" + self.alias(rid)})
        frame = self.rooms[rid]["frame"]
        for kind in ELEMENT_LISTS:
            for element in _expand_list(room.get(kind), self.templates, f"{where}.{kind}", self.errors):
                self.element(kind, element, frame)
        reverb = room.get("reverb")
        if reverb:
            self.reverb(dict(reverb, room=rid) if isinstance(reverb, dict) else {"room": rid}, f"{where}.reverb")
        audio = room.get("audio")
        if audio:
            self.audio(audio, frame, f"{where}.audio")

    # -- elements
    def element(self, kind: str, e: dict[str, Any], frame: _Frame) -> None:
        where = e["_path"]
        # NPCs are placed after workspots so their routes can reference any workspot.
        if kind == "npcs":
            eid = self.register(e, "npc", where)
            if eid:
                self.deferred.append((kind, e, frame))
            return
        handler = getattr(self, "el_" + kind)
        handler(e, frame, where)

    def element_late(self, kind: str, e: dict[str, Any], frame: _Frame) -> None:
        getattr(self, "el_" + kind)(e, frame, e["_path"])

    def el_objects(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "object", where)
        if not eid:
            return
        if e.get("asset"):
            asset = str(e["asset"])
        else:
            asset = self.resource(e.get("resource"), where + ".resource",
                                  allowed=RESOURCE_TYPES - {"entity_record"}) if e.get("resource") is not None else None
            if asset is None:
                if e.get("resource") is None:
                    self.err(where, "needs resource or asset")
                return
        step = self.common(e, frame, where)
        if step is None:
            return
        scale = e.get("scale")
        if scale is not None:
            s = [float(scale)] * 3 if isinstance(scale, (int, float)) else _vec(scale, where + ".scale", self.errors)
            if s is not None:
                if any(v <= 0 for v in s):
                    self.err(where + ".scale", "must be positive")
                step["scale"] = {"x": s[0], "y": s[1], "z": s[2]}
        rng = e.get("stream_range", self.defaults.get("stream_range"))
        self.emit({"op": "place_resource", "as": self.alias(eid), "asset_id": asset, **step, "appearance": e.get("appearance"),
                   "layer": e.get("layer") or self.defaults.get("layer"), "stream_range": rng}, eid)

    def el_geometry(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "geometry", where)
        step = self.common(e, frame, where) if eid else None
        if step is None:
            return
        gen = e.get("generator")
        if gen not in GEOMETRY:
            self.err(where + ".generator", f"must be one of {', '.join(sorted(GEOMETRY))}")
            return
        params = e.get("params") or {}
        if not isinstance(params, dict):
            self.err(where + ".params", "must be a mapping")
            return
        material = e.get("material") or {}
        if isinstance(material, str):
            material = {"template": material}
        template = str(material.get("template") or "")
        slots = material.get("materials") or {}
        if not isinstance(slots, dict):
            self.err(where + ".material.materials", "must map slots (main, glass) to .mi paths")
            slots = {}
        for slot, mi in slots.items():
            if slot not in ("main", "glass") or not str(mi).lower().endswith((".mi", ".mt", ".remt")):
                self.err(f"{where}.material.materials.{slot}", "slots are main/glass and values .mi/.mt depot paths")
        if template and not template.lower().endswith(".mesh"):
            self.err(where + ".material.template", "must be a .mesh depot path")
        if not template and not slots.get("main"):
            self.warnings.append(f"{where}: no material.materials.main or material.template; the geometry previews but Build Mod needs one to create the .mesh")
        mat_out = {"template": template, "appearance": material.get("appearance", "default"), "uv_scale": material.get("uv_scale", 1)}
        if slots:
            mat_out["materials"] = slots
        self.emit({"op": "create_procedural", "as": self.alias(eid), **step, "generator": gen, "params": params,
                   "material": mat_out,
                   "collision": e.get("collision", True), "collision_preset": e.get("collision_preset"), "layer": e.get("layer"),
                   "stream_range": e.get("stream_range", self.defaults.get("stream_range"))}, eid)

    def el_lights(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "light", where)
        step = self.common(e, frame, where) if eid else None
        if step is None:
            return
        color = e.get("color", [1, 1, 1])
        if not (isinstance(color, list) and len(color) == 3 and all(isinstance(c, (int, float)) and 0 <= c <= 1 for c in color)):
            self.err(where + ".color", "must be [r, g, b] from 0 to 1")
            return
        flicker = e.get("flicker") or {}
        config = {"color": color, "intensity": float(e.get("intensity", 100)), "radius": float(e.get("radius", 10)),
                  "flickerStrength": float(flicker.get("strength", 0)), "flickerPeriod": float(flicker.get("period", 0.2)),
                  "flickerOffset": float(flicker.get("offset", 0))}
        if not 0 <= config["intensity"] <= 9999 or not 0.05 <= config["radius"] <= 9999 or not 0 <= config["flickerStrength"] <= 1:
            self.err(where, "intensity 0-9999, radius 0.05-9999 m, flicker.strength 0-1")
        self.emit({"op": "create_light", "as": self.alias(eid), **step, "config": config, "preset_id": e.get("preset")}, eid)

    def el_collisions(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "collision", where)
        step = self.common(e, frame, where) if eid else None
        if step is None:
            return
        shape = e.get("shape", "box")
        if shape not in COLLISION_SHAPES:
            self.err(where + ".shape", "must be box, capsule or sphere")
            return
        out = {"op": "create_collision", "as": self.alias(eid), **step, "shape": shape, "preset": e.get("preset"), "material": e.get("material"),
               "visualize": e.get("visualize")}
        if shape == "box":
            size = _vec(e.get("size", [1, 1, 1]), where + ".size", self.errors)
            if size is None:
                return
            out["size"] = {"x": size[0], "y": size[1], "z": size[2]}
        else:
            out["radius"] = float(e.get("radius", 0.5))
            if shape == "capsule":
                out["height"] = float(e.get("height", 1.8))
        self.emit(out, eid)

    def el_devices(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "device", where)
        if not eid:
            return
        kind = e.get("kind")
        if kind not in DEVICE_KINDS:
            self.err(where + ".kind", f"must be one of {', '.join(sorted(DEVICE_KINDS))}")
            return
        asset = str(e["asset"]) if e.get("asset") else self.resource(e.get("resource"), where + ".resource",
                                                                     allowed={"entity_template", "entity_amm", "entity_record", "device"})
        step = self.common(e, frame, where)
        if asset is None or step is None:
            return
        fact = e.get("fact") or {}
        if fact and not FACT_RE.match(str(fact.get("name", ""))):
            self.err(where + ".fact.name", "must use letters, numbers, underscore, dot or hyphen")
        loot = []
        for li, row in enumerate(e.get("loot") or []):
            if not isinstance(row, dict) or not str(row.get("item", "")).startswith("Items."):
                self.err(f"{where}.loot[{li}].item", "must be an Items.* record")
                continue
            loot.append({"item_record": row["item"], "count_min": int(row.get("min", 1)), "count_max": int(row.get("max", row.get("min", 1))),
                         "drop_chance": float(row.get("chance", 1))})
        if kind == "loot_container" and not str(e.get("loot_table", "")).startswith("LootTables."):
            self.err(where + ".loot_table", "a loot_container needs a LootTables.* record")
        if kind in ("shard", "item") and not str(e.get("item", "")).startswith("Items."):
            self.err(where + ".item", f"a {kind} needs an Items.* record")
        lock = None
        if kind in ("door", "loot_container"):
            lock = "locked" if e.get("locked") else "unlocked"
        self.emit({"op": "create_interactable", "as": self.alias(eid), "asset_id": asset, **step, "kind": kind, "loot_table": e.get("loot_table"),
                   "loot_items": loot or None, "item_record": e.get("item"), "fact_name": fact.get("name"), "fact_value": fact.get("value"),
                   "lock_state": lock}, eid)

    def el_workspots(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "workspot", where)
        p = self.pose(e, frame, where) if eid else None
        if p is None:
            return
        anim = e.get("animation") or {}
        if anim and not all(anim.get(k) for k in ("name", "comp", "ent")):
            self.err(where + ".animation", "needs name, comp and ent (AMM workspot data)")
        self.emit({"op": "create_workspot", "as": self.alias(eid), "name": e.get("name") or eid, "offset": p[0], "yaw": p[1]["yaw"],
                   "workspot_kind": e.get("kind", "sit"), "animation": anim or None, "record": e.get("record"), "appearance": e.get("appearance")}, eid)

    def el_npcs(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = e["id"]
        record = str(e.get("record", ""))
        if not record.startswith("Character."):
            self.err(where + ".record", "must be a Character.* TweakDB record")
            return
        asset = self.resource({"type": "entity_record", "path": record}, where + ".record")
        step = self.common(e, frame, where)
        if asset is None or step is None:
            return
        conditions = []
        for ci, c in enumerate(e.get("conditions") or []):
            if not isinstance(c, dict) or not FACT_RE.match(str(c.get("fact", ""))):
                self.err(f"{where}.conditions[{ci}]", "needs a valid fact")
                continue
            conditions.append({"fact_name": c["fact"], "operator": c.get("op", "=="), "value": c.get("value", 1)})
        self.emit({"op": "create_npc", "as": self.alias(eid), "asset_id": asset, "record": record, **step, "appearance": e.get("appearance"),
                   "spawn_on_start": e.get("spawn_on_start"), "always_spawned": e.get("always_spawned"), "attitude": e.get("attitude"),
                   "faction": e.get("faction"), "level": e.get("level"), "archetype": e.get("archetype"), "idle_behavior": e.get("idle"),
                   "conditions": conditions or None}, eid)
        route = e.get("route")
        if not route:
            return
        if not isinstance(route, dict) or not isinstance(route.get("waypoints"), list) or not route["waypoints"]:
            self.err(where + ".route", "needs waypoints")
            return
        route_alias = self.alias(eid) + "_route"
        self.counts["npc_routes"] = self.counts.get("npc_routes", 0) + 1
        self.emit({"op": "create_npc_route", "as": route_alias, "npc_id": "$" + self.alias(eid), "name": route.get("name") or f"{e.get('name') or eid} route",
                   "loop": route.get("loop", True), "route_kind": route.get("kind")})
        for wi, wp in enumerate(route["waypoints"]):
            ww = f"{where}.route.waypoints[{wi}]"
            if not isinstance(wp, dict):
                self.err(ww, "must be a mapping")
                continue
            workspot = wp.get("workspot")
            step_wp: dict[str, Any] = {"op": "add_route_waypoint", "route_id": "$" + route_alias, "variant": wp.get("variant"),
                                       "wait_seconds": wp.get("wait", 0), "speed": wp.get("speed"), "facing_yaw": wp.get("facing"), "name": wp.get("name")}
            if workspot is not None:
                if self.ids.get(workspot) != "workspot":
                    self.err(ww + ".workspot", f"unknown workspot {workspot!r}")
                    continue
                step_wp.update(transition="workspot", workspot_location_id="$" + self.alias(workspot))
            p = self.pose(wp, frame, ww)
            if p is None:
                continue
            step_wp.update(offset=p[0], yaw=p[1]["yaw"])
            self.emit(step_wp)

    def el_vfx(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "vfx", where)
        step = self.common(e, frame, where) if eid else None
        if step is None:
            return
        path = str(e.get("resource", ""))
        if not path.lower().endswith((".particle", ".effect")):
            self.err(where + ".resource", "must be a .particle or .effect depot path")
            return
        scale = e.get("scale")
        s = None
        if scale is not None:
            s = [float(scale)] * 3 if isinstance(scale, (int, float)) else _vec(scale, where + ".scale", self.errors)
        self.emit({"op": "create_vfx", "as": self.alias(eid), **step, "resource_path": path,
                   "scale": {"x": s[0], "y": s[1], "z": s[2]} if s else None, "emission_rate": e.get("emission_rate")}, eid)

    def el_triggers(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "trigger", where)
        step = self.common(e, frame, where) if eid else None
        if step is None:
            return
        shape = e.get("shape", "box")
        if shape not in VOLUME_SHAPES:
            self.err(where + ".shape", "must be box, sphere or cylinder")
            return
        out = {"op": "create_volume", "as": self.alias(eid), **step, "shape": shape, "purpose": e.get("purpose", "trigger")}
        out.pop("spawn", None)
        if shape == "box":
            size = _vec(e.get("size", [2, 2, 2]), where + ".size", self.errors)
            if size is None:
                return
            out.update(size_x=size[0], size_y=size[1], size_z=size[2])
        else:
            out["radius"] = float(e.get("radius", 1))
            out["height"] = float(e.get("height", 2))
        self.emit(out, eid)
        fact = e.get("fact")
        if fact:
            if not isinstance(fact, dict) or not FACT_RE.match(str(fact.get("name", ""))):
                self.err(where + ".fact", "needs a valid name")
                return
            self.emit({"op": "link_fact", "volume_id": "$" + self.alias(eid), "fact_name": fact["name"], "value": fact.get("value", 1)})

    def el_cameras(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "camera", where)
        step = self.common(e, frame, where) if eid else None
        if step is None:
            return
        step.pop("spawn", None)
        look = e.get("look_at")
        if isinstance(look, str):
            self.err(where + ".look_at", "must be a point [x, y, z] in the same frame as at")
            return
        look_v = _vec(look if look is not None else [0, 2, 1.4], where + ".look_at", self.errors)
        if look_v is None:
            return
        target, _ = frame.place(look_v)
        self.emit({"op": "create_camera", "as": self.alias(eid), **step, "look_at_offset": target, "fov": e.get("fov"),
                   "kind": e.get("kind")}, eid)

    def el_occluders(self, e: dict[str, Any], frame: _Frame, where: str) -> None:
        eid = self.register(e, "occluder", where)
        step = self.common(e, frame, where) if eid else None
        if step is None:
            return
        mesh = e.get("mesh", "plane_two_sided")
        if mesh not in OCCLUDER_MESHES:
            self.err(where + ".mesh", "must be box, plane or plane_two_sided")
            return
        size = _vec(e.get("size", [4, 1, 3]), where + ".size", self.errors)
        if size is None:
            return
        self.emit({"op": "create_occluder", "as": self.alias(eid), **step, "mesh": mesh, "size": {"x": size[0], "y": size[1], "z": size[2]}}, eid)

    def audio(self, value: Any, frame: _Frame, where: str = "audio") -> None:
        if not value:
            return
        if not isinstance(value, dict):
            self.err(where, "must be {emitters: [...], reverb: [...]}")
            return
        for e in _expand_list(value.get("emitters"), self.templates, where + ".emitters", self.errors):
            ew = e["_path"]
            eid = self.register(e, "audio_emitter", ew)
            step = self.common(e, self.frame_for(e, frame, ew), ew) if eid else None
            if step is None:
                continue
            if not e.get("resource") and not e.get("query"):
                self.err(ew, "needs resource (audio event path) or query")
                continue
            self.emit({"op": "create_audio_emitter", "as": self.alias(eid), **step, "resource_path": e.get("resource"), "query": e.get("query"),
                       "radius": e.get("radius")}, eid)
        for i, r in enumerate(value.get("reverb") or []):
            self.reverb(r, f"{where}.reverb[{i}]")

    def reverb(self, r: Any, where: str) -> None:
        if not isinstance(r, dict) or r.get("room") not in self.rooms:
            self.err(where + ".room", "reverb needs an existing room")
            return
        rid = r["room"]
        eid = r.get("id") or f"{rid}_reverb"
        if not self.register({"id": eid}, "reverb", where):
            return
        self.emit({"op": "create_reverb_zone", "as": self.alias(eid), "premise_id": "$premise", "room_id": "$" + self.alias(rid),
                   "name": r.get("name"), "preset_name": r.get("preset"), "sound_event": r.get("sound_event"), "reverb": r.get("reverb"),
                   "priority": r.get("priority")}, eid)

    def splines(self, value: Any, frame: _Frame) -> None:
        for s in _expand_list(value, self.templates, "splines", self.errors):
            where = s["_path"]
            eid = self.register(s, "spline", where)
            pts = s.get("points")
            if not eid or not isinstance(pts, list) or len(pts) < 2:
                if eid:
                    self.err(where + ".points", "needs at least two points")
                continue
            f = self.frame_for(s, frame, where)
            points = []
            for pi, p in enumerate(pts):
                v = _vec(p, f"{where}.points[{pi}]", self.errors)
                if v is not None:
                    points.append({"offset": f.place(v)[0]})
            if s.get("closed") and len(points) < 3:
                self.err(where, "a closed spline needs at least three points")
            self.emit({"op": "create_spline", "as": self.alias(eid), "premise_id": "$premise", "name": s.get("name") or eid, "points": points,
                       "closed": bool(s.get("closed")), "tension": s.get("tension")}, eid)

    def navigation(self, value: Any, frame: _Frame) -> None:
        if not value:
            return
        if not isinstance(value, dict) or not isinstance(value.get("nodes"), list):
            self.err("navigation", "must be {nodes: [...], edges: [...]}")
            return
        node_ids, nodes = set(), []
        for i, n in enumerate(value["nodes"]):
            where = f"navigation.nodes[{i}]"
            if not isinstance(n, dict) or not isinstance(n.get("id"), str) or n["id"] in node_ids:
                self.err(where + ".id", "needs a unique id")
                continue
            v = _vec(n.get("at"), where + ".at", self.errors)
            if v is None:
                continue
            node_ids.add(n["id"])
            nodes.append({"id": n["id"], "name": n.get("name"), "surface": n.get("surface"), "offset": self.frame_for(n, frame, where).place(v)[0]})
        edges = []
        for i, e in enumerate(value.get("edges") or []):
            where = f"navigation.edges[{i}]"
            if not isinstance(e, dict) or e.get("from") not in node_ids or e.get("to") not in node_ids or e.get("from") == e.get("to"):
                self.err(where, "from/to must name two different nodes")
                continue
            kind = e.get("kind", "walk")
            if kind not in NAV_EDGES:
                self.err(where + ".kind", f"must be one of {', '.join(sorted(NAV_EDGES))}")
                continue
            edges.append({"from": e["from"], "to": e["to"], "kind": kind, "one_way": bool(e.get("one_way")), "cost": e.get("cost", 1)})
        if nodes:
            self.counts["navigation_nodes"] = len(nodes)
            self.emit({"op": "import_navigation", "as": "navigation", "name": value.get("name") or f"{self.doc_id} navigation", "nodes": nodes, "edges": edges})

    def logic(self, value: Any) -> None:
        if not value:
            return
        if not isinstance(value, list):
            self.err("logic", "must be a list of graphs")
            return
        for gi, g in enumerate(value):
            where = f"logic[{gi}]"
            if not isinstance(g, dict):
                self.err(where, "must be a mapping")
                continue
            gid = self.register(g, "logic_graph", where)
            if not gid:
                continue
            galias = self.alias(gid)
            self.emit({"op": "create_device_graph", "as": galias, "name": g.get("name") or gid, "premise_id": "$premise"}, gid)
            local: set[str] = set()
            for ni, n in enumerate(g.get("nodes") or []):
                nw = f"{where}.nodes[{ni}]"
                if not isinstance(n, dict) or not isinstance(n.get("id"), str) or not ID_RE.match(n["id"]) or n["id"] in local:
                    self.err(nw + ".id", "needs a unique id within the graph")
                    continue
                if n.get("kind") not in LOGIC_KINDS:
                    self.err(nw + ".kind", f"must be one of {', '.join(sorted(LOGIC_KINDS))}")
                    continue
                local.add(n["id"])
                element = n.get("element")
                if element is not None and self.ids.get(element) not in ("object", "geometry", "device", "light", "vfx", "collision", "occluder", "npc", "audio_emitter"):
                    self.err(nw + ".element", f"{element!r} is not a placed element of this document")
                    continue
                self.emit({"op": "add_device_node", "as": f"{galias}__{n['id']}", "graph_id": "$" + galias, "kind": n["kind"],
                           "name": n.get("name") or n["id"], "object_id": "$" + self.alias(element) if element else None,
                           "config": n.get("config")})
            for li, link in enumerate(g.get("links") or []):
                lw = f"{where}.links[{li}]"
                if not isinstance(link, dict) or link.get("from") not in local or link.get("to") not in local:
                    self.err(lw, "from/to must name nodes of this graph")
                    continue
                when = link.get("when") or {}
                self.emit({"op": "add_device_link", "graph_id": "$" + galias, "from_id": f"${galias}__{link['from']}",
                           "to_id": f"${galias}__{link['to']}", "trigger": link.get("trigger"), "condition_fact": when.get("fact"),
                           "condition_value": when.get("value")})

    def result(self, origin: Any, streaming: dict[str, Any] | None = None) -> dict[str, Any]:
        ok = not self.errors
        plan = None
        if ok:
            plan = {"format": PLAN_FORMAT, "version": 2, "name": f"EDL {self.doc.get('name') or self.doc_id}", "origin": origin,
                    "steps": self.steps}
            if len(self.steps) > 2000:
                self.errors.append(f"the compiled plan has {len(self.steps)} steps; the limit is 2000 (split the location into several documents)")
                ok, plan = False, None
        return {"valid": ok, "errors": self.errors, "warnings": self.warnings, "doc": getattr(self, "doc_id", None),
                "name": (getattr(self, "doc", None) or {}).get("name"), "hash": getattr(self, "hash", None), "counts": self.counts,
                "resources": [{"type": k[0], "path": k[1], "alias": v} for k, v in self.resources.items()],
                "streaming": streaming or {}, "step_count": len(self.steps), "plan": plan}


def compile_document(source: str | Path | dict[str, Any], *, parameters: dict[str, Any] | None = None,
                     fmt: str | None = None) -> dict[str, Any]:
    try:
        doc, path = load(source, fmt=fmt)
    except EdlError as exc:
        return {"valid": False, "errors": exc.errors, "warnings": [], "plan": None}
    return Compiler(doc, path, parameters).compile()


def schema() -> dict[str, Any]:
    """Loaded JSON Schema (for editors) plus a compact field reference."""
    path = Path(__file__).resolve().parents[2] / "edl" / "locationstudio-edl-1.schema.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
