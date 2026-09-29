"""Procedural geometry: parts -> triangle mesh -> glTF -> .mesh -> native node.

LocationStudio's in-game generators (modules/procedural.lua) save a list of
solid parts on every procedural object. This module is the build half:

* ``mesh_from_parts`` triangulates the parts (box, wedge, cylinder, sphere,
  prism) with outward normals and world-scale box-projected UVs, one
  primitive per material slot (``main``, ``glass``).
* ``write_glb`` writes a glTF 2.0 binary. REDengine is Z-up and glTF is Y-up,
  so positions and normals are written as (x, z, -y).
* ``apply_to_workspace`` (the Build Mod ``procedural`` stage) writes a glb per
  object and a CR2W ``.mesh`` for it, then adds a native ``worldMeshNode`` to
  the workspace copy of the World Builder export. The mesh comes from one of
  two backends:
  - ``native`` (objects with ``material.materials`` slot -> .mi/.mt): a complete
    CMesh document with vertex/index buffers, chunks, bounds, LOD metadata and
    material references (``meshres``), written to CR2W by the WolvenKit worker;
  - ``import`` (objects with only ``material.template``): the glb imported over
    a local copy of the template mesh with the WolvenKit CLI.

Rotation convention (shared with the Lua generators): R = Rz(yaw) Rx(pitch) Ry(roll).
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
from pathlib import Path
from typing import Any, Callable

from .vanilla import euler_to_quat

DEFAULT_IMPORT_COMMAND = ["{cli}", "import", "-p", "{glb}", "-k"]


# --------------------------------------------------------------------------- math

def rot_matrix(rot: dict[str, Any] | None) -> list[list[float]]:
    rot = rot or {}
    y, p, r = (math.radians(float(rot.get(k) or 0)) for k in ("yaw", "pitch", "roll"))
    cy, sy, cp, sp, cr, sr = math.cos(y), math.sin(y), math.cos(p), math.sin(p), math.cos(r), math.sin(r)
    rz = [[cy, -sy, 0], [sy, cy, 0], [0, 0, 1]]
    rx = [[1, 0, 0], [0, cp, -sp], [0, sp, cp]]
    ry = [[cr, 0, sr], [0, 1, 0], [-sr, 0, cr]]

    def mul(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]

    return mul(mul(rz, rx), ry)


def _apply(m: list[list[float]], v: tuple[float, float, float]) -> tuple[float, float, float]:
    return (m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
            m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
            m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _norm(a):
    n = math.sqrt(_dot(a, a)) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


# --------------------------------------------------------------------------- mesh building

class Mesh:
    def __init__(self, uv_scale: float = 1.0, slot_uv: dict[str, Any] | None = None):
        self.uv_scale = uv_scale if uv_scale > 0 else 1.0
        # Per-slot extra UV divisor (u, v) from library materials: uv_scale / tiling.
        self.slot_uv = {k: (float(v[0]), float(v[1])) for k, v in (slot_uv or {}).items() if v and float(v[0]) > 0 and float(v[1]) > 0}
        self.prims: dict[str, dict[str, list]] = {}

    def _prim(self, material: str) -> dict[str, list]:
        return self.prims.setdefault(material, {"pos": [], "nrm": [], "uv": [], "idx": []})

    def _uv(self, p, n, material: str = "main"):
        ax = max(range(3), key=lambda i: abs(n[i]))
        u, v = [(1, 2), (0, 2), (0, 1)][ax]
        du, dv = self.slot_uv.get(material, (1.0, 1.0))
        return (p[u] / (self.uv_scale * du), p[v] / (self.uv_scale * dv))

    def polygon(self, material: str, verts: list[tuple[float, float, float]], outward: tuple[float, float, float] | None = None,
                normal: tuple[float, float, float] | None = None) -> None:
        """A convex planar polygon; winding is fixed so its normal faces `outward` (or equals `normal`)."""
        if len(verts) < 3:
            return
        n = _norm(_cross(_sub(verts[1], verts[0]), _sub(verts[2], verts[0])))
        want = normal or outward
        if want is not None and _dot(n, want) < 0:
            verts = list(reversed(verts))
            n = (-n[0], -n[1], -n[2])
        if normal is not None:
            n = _norm(normal)
        prim = self._prim(material)
        base = len(prim["pos"])
        for v in verts:
            prim["pos"].append(v)
            prim["nrm"].append(n)
            prim["uv"].append(self._uv(v, n, material))
        for i in range(1, len(verts) - 1):
            prim["idx"].extend((base, base + i, base + i + 1))

    def smooth_quad(self, material: str, verts, normals) -> None:
        """A quad with per-vertex normals (cylinder/sphere sides), counter-clockwise as seen from outside."""
        prim = self._prim(material)
        base = len(prim["pos"])
        face_n = _norm(_cross(_sub(verts[1], verts[0]), _sub(verts[2], verts[0]))) if len(set(verts[:3])) == 3 else normals[0]
        for v, n in zip(verts, normals):
            prim["pos"].append(v)
            prim["nrm"].append(_norm(n))
            prim["uv"].append(self._uv(v, face_n, material))
        prim["idx"].extend((base, base + 1, base + 2, base, base + 2, base + 3))

    @property
    def triangle_count(self) -> int:
        return sum(len(p["idx"]) // 3 for p in self.prims.values())

    def bounds(self) -> dict[str, list[float]]:
        pts = [p for prim in self.prims.values() for p in prim["pos"]]
        if not pts:
            return {"min": [0, 0, 0], "max": [0, 0, 0]}
        return {"min": [min(p[i] for p in pts) for i in range(3)], "max": [max(p[i] for p in pts) for i in range(3)]}


def _place(part: dict[str, Any]):
    m = rot_matrix(part.get("rotation"))
    c = part.get("center") or {}
    center = (float(c.get("x", 0)), float(c.get("y", 0)), float(c.get("z", 0)))

    def world(v):
        r = _apply(m, v)
        return (center[0] + r[0], center[1] + r[1], center[2] + r[2])

    return m, center, world


def _box(mesh: Mesh, part: dict[str, Any]) -> None:
    s = part["size"]
    hx, hy, hz = float(s["x"]) / 2, float(s["y"]) / 2, float(s["z"]) / 2
    _m, center, world = _place(part)
    c = {(i, j, k): world((i * hx, j * hy, k * hz)) for i in (-1, 1) for j in (-1, 1) for k in (-1, 1)}
    faces = [
        [c[(1, -1, -1)], c[(1, 1, -1)], c[(1, 1, 1)], c[(1, -1, 1)]], [c[(-1, -1, -1)], c[(-1, -1, 1)], c[(-1, 1, 1)], c[(-1, 1, -1)]],
        [c[(-1, 1, -1)], c[(-1, 1, 1)], c[(1, 1, 1)], c[(1, 1, -1)]], [c[(-1, -1, -1)], c[(1, -1, -1)], c[(1, -1, 1)], c[(-1, -1, 1)]],
        [c[(-1, -1, 1)], c[(1, -1, 1)], c[(1, 1, 1)], c[(-1, 1, 1)]], [c[(-1, -1, -1)], c[(-1, 1, -1)], c[(1, 1, -1)], c[(1, -1, -1)]],
    ]
    for f in faces:
        centroid = tuple(sum(v[i] for v in f) / 4 for i in range(3))
        mesh.polygon(part.get("material", "main"), f, outward=_sub(centroid, center))


def _wedge(mesh: Mesh, part: dict[str, Any]) -> None:
    s = part["size"]
    hx, hy, hz = float(s["x"]) / 2, float(s["y"]) / 2, float(s["z"]) / 2
    _m, center, world = _place(part)
    a, b, cc, d = world((-hx, -hy, -hz)), world((hx, -hy, -hz)), world((hx, hy, -hz)), world((-hx, hy, -hz))
    e, f = world((-hx, hy, hz)), world((hx, hy, hz))
    solid_center = tuple((a[i] + b[i] + cc[i] + d[i] + e[i] + f[i]) / 6 for i in range(3))
    for face in ([a, b, cc, d], [d, cc, f, e], [a, b, f, e], [a, d, e], [b, cc, f]):
        centroid = tuple(sum(v[i] for v in face) / len(face) for i in range(3))
        mesh.polygon(part.get("material", "main"), face, outward=_sub(centroid, solid_center))


def _cylinder(mesh: Mesh, part: dict[str, Any]) -> None:
    r, half = float(part["radius"]), float(part["length"]) / 2
    n = max(3, min(64, int(part.get("sides") or 12)))
    m, center, world = _place(part)
    ring = [(math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n)) for i in range(n)]
    material = part.get("material", "main")
    for i in range(n):
        (x0, z0), (x1, z1) = ring[i], ring[(i + 1) % n]
        # Around local +Y: counter-clockwise seen from outside.
        verts = [world((r * x0, -half, r * z0)), world((r * x0, half, r * z0)), world((r * x1, half, r * z1)), world((r * x1, -half, r * z1))]
        normals = [_apply(m, (x0, 0, z0)), _apply(m, (x0, 0, z0)), _apply(m, (x1, 0, z1)), _apply(m, (x1, 0, z1))]
        out = _apply(m, ((x0 + x1) / 2, 0, (z0 + z1) / 2))
        if _dot(_cross(_sub(verts[1], verts[0]), _sub(verts[2], verts[0])), out) < 0:
            verts, normals = list(reversed(verts)), list(reversed(normals))
        mesh.smooth_quad(material, verts, normals)
    for sign in (-1, 1):
        cap = [world((r * x, sign * half, r * z)) for x, z in ring]
        mesh.polygon(material, cap, normal=_apply(m, (0, sign, 0)))


def _sphere(mesh: Mesh, part: dict[str, Any]) -> None:
    r = float(part["radius"])
    n = max(6, min(32, int(part.get("sides") or 12)))
    stacks = max(3, n // 2)
    _m, center, _world = _place(part)
    material = part.get("material", "main")

    def pt(i, j):
        th, ph = math.pi * i / stacks, 2 * math.pi * j / n
        d = (math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th))
        return (center[0] + r * d[0], center[1] + r * d[1], center[2] + r * d[2]), d

    for i in range(stacks):
        for j in range(n):
            (p0, n0), (p1, n1), (p2, n2), (p3, n3) = pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1)
            verts, normals = [p0, p1, p2, p3], [n0, n1, n2, n3]
            mid = _norm(tuple(n0[k] + n1[k] + n2[k] + n3[k] for k in range(3)))
            if _dot(_cross(_sub(p1, p0), _sub(p2, p0)), mid) < 0:
                verts, normals = list(reversed(verts)), list(reversed(normals))
            mesh.smooth_quad(material, verts, normals)


def _triangulate(poly: list[tuple[float, float]]) -> list[tuple[int, int, int]]:
    """Ear clipping for a simple counter-clockwise polygon."""
    idx = list(range(len(poly)))
    tris: list[tuple[int, int, int]] = []

    def area2(a, b, c):
        return (poly[b][0] - poly[a][0]) * (poly[c][1] - poly[a][1]) - (poly[b][1] - poly[a][1]) * (poly[c][0] - poly[a][0])

    def inside(p, a, b, c):
        return area2(a, b, p) >= 0 and area2(b, c, p) >= 0 and area2(c, a, p) >= 0

    guard = 0
    while len(idx) > 3 and guard < 10000:
        guard += 1
        for k in range(len(idx)):
            a, b, c = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
            if area2(a, b, c) <= 1e-12:
                continue
            if any(inside(p, a, b, c) for p in idx if p not in (a, b, c)):
                continue
            tris.append((a, b, c))
            idx.pop(k)
            break
        else:
            raise ValueError("prism polygon is not simple (self-intersecting or degenerate)")
    tris.append((idx[0], idx[1], idx[2]))
    return tris


def _prism(mesh: Mesh, part: dict[str, Any]) -> None:
    pts = [(float(p["x"]), float(p["y"])) for p in part["points"]]
    if sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) < 0:
        pts.reverse()
    z0, z1 = float(part["z0"]), float(part["z1"])
    material = part.get("material", "main")
    for a, b, c in _triangulate(pts):
        mesh.polygon(material, [(pts[a][0], pts[a][1], z1), (pts[b][0], pts[b][1], z1), (pts[c][0], pts[c][1], z1)], normal=(0, 0, 1))
        mesh.polygon(material, [(pts[a][0], pts[a][1], z0), (pts[c][0], pts[c][1], z0), (pts[b][0], pts[b][1], z0)], normal=(0, 0, -1))
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
        mesh.polygon(material, [(ax, ay, z0), (bx, by, z0), (bx, by, z1), (ax, ay, z1)], normal=(by - ay, -(bx - ax), 0))


SHAPES: dict[str, Callable[[Mesh, dict[str, Any]], None]] = {"box": _box, "wedge": _wedge, "cylinder": _cylinder, "sphere": _sphere, "prism": _prism}


def mesh_from_parts(parts: list[dict[str, Any]], *, uv_scale: float = 1.0, slot_uv: dict[str, Any] | None = None) -> Mesh:
    mesh = Mesh(uv_scale, slot_uv)
    for i, part in enumerate(parts):
        fn = SHAPES.get(part.get("shape"))
        if fn is None:
            raise ValueError(f"part {i + 1} has unknown shape {part.get('shape')!r}")
        fn(mesh, part)
    return mesh


# --------------------------------------------------------------------------- glTF

def write_glb(mesh: Mesh, path: str | Path | None = None, *, name: str = "procedural") -> bytes:
    buffer = bytearray()
    views: list[dict[str, Any]] = []
    accessors: list[dict[str, Any]] = []
    primitives: list[dict[str, Any]] = []
    materials: list[dict[str, Any]] = []

    def add(data: bytes, target: int) -> int:
        while len(buffer) % 4:
            buffer.append(0)
        views.append({"buffer": 0, "byteOffset": len(buffer), "byteLength": len(data), "target": target})
        buffer.extend(data)
        return len(views) - 1

    for material, prim in sorted(mesh.prims.items()):
        if not prim["idx"]:
            continue
        pos = [(p[0], p[2], -p[1]) for p in prim["pos"]]
        nrm = [(n[0], n[2], -n[1]) for n in prim["nrm"]]
        pv = add(b"".join(struct.pack("<3f", *p) for p in pos), 34962)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": len(pos), "type": "VEC3",
                          "min": [min(p[i] for p in pos) for i in range(3)], "max": [max(p[i] for p in pos) for i in range(3)]})
        nv = add(b"".join(struct.pack("<3f", *n) for n in nrm), 34962)
        accessors.append({"bufferView": nv, "componentType": 5126, "count": len(nrm), "type": "VEC3"})
        uv = add(b"".join(struct.pack("<2f", u, 1.0 - v) for u, v in prim["uv"]), 34962)
        accessors.append({"bufferView": uv, "componentType": 5126, "count": len(prim["uv"]), "type": "VEC2"})
        iv = add(struct.pack(f"<{len(prim['idx'])}I", *prim["idx"]), 34963)
        accessors.append({"bufferView": iv, "componentType": 5125, "count": len(prim["idx"]), "type": "SCALAR"})
        materials.append({"name": material, "doubleSided": material == "glass"})
        a = len(accessors)
        primitives.append({"attributes": {"POSITION": a - 4, "NORMAL": a - 3, "TEXCOORD_0": a - 2}, "indices": a - 1,
                           "material": len(materials) - 1, "mode": 4})
    while len(buffer) % 4:
        buffer.append(0)
    doc = {"asset": {"version": "2.0", "generator": "LocationStudio procedural geometry"}, "scene": 0,
           "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": name}], "meshes": [{"name": name, "primitives": primitives}],
           "materials": materials, "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": len(buffer)}]}
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(buffer))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(buffer), 0x004E4942) + bytes(buffer)
    if path is not None:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_bytes(out)
    return out


def read_glb(data: bytes) -> dict[str, Any]:
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError("not a glTF 2.0 binary")
    jlen, _ = struct.unpack_from("<II", data, 12)
    return json.loads(data[20:20 + jlen])


# --------------------------------------------------------------------------- project and build stage

def procedural_objects(project: dict[str, Any], premise_id: str | None = None) -> list[dict[str, Any]]:
    layers = {l.get("id"): l for l in project.get("layers", []) if isinstance(l, dict)}
    out = []
    for o in project.get("objects", []) or []:
        md = (o or {}).get("metadata") or {}
        cfg = md.get("procedural")
        if not isinstance(cfg, dict) or o.get("enabled") is False or md.get("reference_area_id"):
            continue
        if (layers.get(o.get("layer")) or {}).get("export") is False:
            continue
        if premise_id and o.get("premise_id") != premise_id:
            continue
        out.append(o)
    return out


def object_mesh(obj: dict[str, Any]) -> Mesh:
    cfg = obj["metadata"]["procedural"]
    material = cfg.get("material") or {}
    uv_scale = float(material.get("uv_scale") or 1.0)
    if cfg.get("generator") == "csg":
        # The saved parts are grid boxes for the preview; mesh the exact tree instead.
        from .csg import mesh_from_tree

        tree = (cfg.get("csg") or {}).get("tree")
        if not isinstance(tree, dict):
            raise ValueError("CSG object has no saved tree; regenerate it in LocationStudio")
        return mesh_from_tree(tree, uv_scale=uv_scale, slot_uv=material.get("slot_uv"))
    return mesh_from_parts(cfg.get("parts") or [], uv_scale=uv_scale, slot_uv=material.get("slot_uv"))


def _node(obj: dict[str, Any], rec: dict[str, Any] | None = None) -> dict[str, Any]:
    cfg = obj["metadata"]["procedural"]
    t = obj.get("transform") or {}
    p, r = t.get("position") or {}, t.get("rotation") or {}
    q = euler_to_quat(float(r.get("roll") or 0), float(r.get("pitch") or 0), float(r.get("yaw") or 0))
    # Streaming ranges from the automatic bounds (lsbuild/bounds.py); a manual stream_range wins inside `record`.
    rng = float(rec["streaming"]["range"]) if rec else float(cfg.get("stream_range") or 150)
    secondary = float(rec["streaming"]["secondary_range"]) if rec else rng * 1.2
    appearance = (cfg.get("material") or {}).get("appearance") or "default"
    return {"name": f"[Procedural] {obj.get('name')}", "type": "worldMeshNode",
            "position": {"x": float(p.get("x", 0)), "y": float(p.get("y", 0)), "z": float(p.get("z", 0)), "w": 0},
            "rotation": q, "scale": {"x": 1, "y": 1, "z": 1}, "primaryRange": rng, "secondaryRange": secondary,
            "data": {"mesh": {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": cfg["mesh_path"]}, "Flags": "Default"},
                     "meshAppearance": {"$type": "CName", "$storage": "string", "$value": appearance}},
            "locationstudio": {"object_id": obj.get("id"), "procedural": True}}


def _sector_for(export: dict[str, Any], pos: dict[str, float]) -> dict[str, Any] | None:
    sectors = [s for s in export.get("sectors", []) if isinstance(s, dict)]
    if not sectors:
        return None

    def inside(s):
        lo, hi = s.get("min") or {}, s.get("max") or {}
        return all(float(lo.get(k, -1e9)) <= pos[k] <= float(hi.get(k, 1e9)) for k in "xyz")

    for s in sectors:
        if inside(s):
            return s

    def dist(s):
        lo, hi = s.get("min") or {}, s.get("max") or {}
        c = {k: (float(lo.get(k, 0)) + float(hi.get(k, 0))) / 2 for k in "xyz"}
        return math.dist((pos["x"], pos["y"], pos["z"]), (c["x"], c["y"], c["z"]))

    return min(sectors, key=dist)


def inject_nodes(export: dict[str, Any], objects: list[dict[str, Any]], bounds_by_id: dict[str, Any] | None = None,
                 project: dict[str, Any] | None = None) -> list[dict[str, Any]]:
    """Add one worldMeshNode per object to the sector holding its world-bounds centre (before any variant range) and
    grow the sector by its rotated world AABB."""
    from . import bounds as _bounds

    placed = []
    bounds_by_id = dict(bounds_by_id or {})
    bounds_settings = _bounds.settings(project)
    for s in export.get("sectors", []):
        if isinstance(s, dict):
            s["nodes"] = [n for n in s.get("nodes", []) if not (isinstance(n, dict) and (n.get("locationstudio") or {}).get("procedural"))]
    for obj in objects:
        rec = bounds_by_id.get(obj.get("id"))
        if rec is None:
            try:
                rec = _bounds.record(obj, bounds_settings)
            except (ValueError, KeyError, TypeError):
                rec = None
        node = _node(obj, rec)
        sector = _sector_for(export, rec["world"]["center"] if rec else node["position"])
        if sector is None:
            raise ValueError("the export has no sectors to receive procedural geometry")
        nodes = sector.setdefault("nodes", [])
        variants = sector.get("variantIndices") or [0]
        at = int(variants[1]) if len(variants) > 1 else len(nodes)
        nodes.insert(at, node)
        if len(variants) > 1:
            sector["variantIndices"] = [v if i == 0 or v < at else v + 1 for i, v in enumerate(variants)]
        lo, hi = sector.setdefault("min", {}), sector.setdefault("max", {})
        for k in "xyz":
            p = node["position"][k]
            ext_lo = rec["world"]["min"][k] - 1 if rec else p
            ext_hi = rec["world"]["max"][k] + 1 if rec else p
            lo[k] = min(float(lo.get(k, ext_lo)), ext_lo)
            hi[k] = max(float(hi.get(k, ext_hi)), ext_hi)
        placed.append({"object_id": obj.get("id"), "sector": sector.get("name"), "node_index": at, "mesh_path": obj["metadata"]["procedural"]["mesh_path"],
                       "primary_range": node["primaryRange"], "secondary_range": node["secondaryRange"]})
    return placed


def _import_command(cli: str, glb: Path, mesh: Path) -> list[str]:
    template = DEFAULT_IMPORT_COMMAND
    env = os.environ.get("LOCATION_STUDIO_MESH_IMPORT_CMD")
    if env:
        template = json.loads(env)
    return [str(part).format(cli=cli, glb=str(glb), mesh=str(mesh), raw_dir=str(glb.parent)) for part in template]


def backend_for(cfg: dict[str, Any]) -> str:
    material = cfg.get("material") or {}
    materials = material.get("materials") if isinstance(material.get("materials"), dict) else {}
    return "native" if materials.get("main") else "import"


def native_mesh(obj: dict[str, Any], *, reference: dict[str, Any] | None = None) -> dict[str, Any]:
    """CMesh document and stats for one procedural object (native backend)."""
    from .meshres import build_mesh_resource

    cfg = obj["metadata"]["procedural"]
    material = cfg.get("material") or {}
    looks = material.get("appearances") if isinstance(material.get("appearances"), dict) else {}
    if len(looks) > 1:
        # Library variants: the default look plus one appearance per variant; the node picks material.appearance.
        return build_mesh_resource(object_mesh(obj), dict(material.get("materials") or {}), reference=reference, appearance="default",
                                   lod_distances=cfg.get("lod_distances"), appearances=looks)
    return build_mesh_resource(object_mesh(obj), dict(material.get("materials") or {}), reference=reference,
                               appearance=str(material.get("appearance") or "default"), lod_distances=cfg.get("lod_distances"))


def _run_worker(worker: str, source: Path, target: Path, timeout: int) -> tuple[bool, str]:
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        proc = subprocess.run([worker, "deserialize", "--input", str(source), "--output", str(target), "--json"],
                              capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return False, str(exc)
    ok = proc.returncode == 0 and target.is_file() and target.read_bytes()[:4] == b"CR2W"
    return ok, (proc.stdout + proc.stderr)[-2000:]


def apply_to_workspace(project_file: str | Path, workspace: str | Path, *, premise_id: str | None = None, cli: str | None = None,
                       template_file: Callable[[str], Path | None] | None = None, output: str | Path | None = None,
                       timeout: int = 300, worker: str | None = None, reference: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build Mod stage: generate, convert and place every procedural mesh in scope."""
    from .build import load_manifest
    from .dependencies import normalize

    project = json.loads(Path(project_file).read_text(encoding="utf-8")) if Path(project_file).is_file() else {"objects": []}
    objects = procedural_objects(project, premise_id)
    report: dict[str, Any] = {"objects": len(objects), "generated": [], "issues": [], "nodes": [], "ready": True}
    if not objects:
        return report
    from . import bounds as _bounds
    from .materials import definitions, resolve_object

    defs = definitions(project)
    bounds_settings = _bounds.settings(project)
    bounds_by_id: dict[str, Any] = {}
    root, manifest = load_manifest(workspace)
    raw_export = root / str(manifest["exportFile"])
    for obj in objects:
        label = f"{obj.get('name')} ({obj.get('id')})"
        try:
            obj = resolve_object(obj, defs)  # material library references -> depot paths, variant appearances
        except ValueError as exc:
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: {exc}"})
            continue
        cfg = obj["metadata"]["procedural"]
        path = normalize(cfg.get("mesh_path") or "")
        looks = (cfg.get("material") or {}).get("appearances") or {}
        wanted = str((cfg.get("material") or {}).get("appearance") or "default")
        if len(looks) > 1 and wanted not in looks:
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: appearance {wanted!r} is not one of the material variants ({', '.join(looks)})"})
            continue
        if not path.endswith(".mesh"):
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: mesh_path is not a .mesh depot path"})
            continue
        try:
            mesh = object_mesh(obj)
        except (ValueError, KeyError, TypeError) as exc:
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: {exc}"})
            continue
        rel = Path(*path.split("\\"))
        glb = root / "source" / "raw" / rel.with_suffix(".glb")
        write_glb(mesh, glb, name=rel.stem)
        entry = {"object_id": obj.get("id"), "mesh_path": path, "glb": str(glb), "triangles": mesh.triangle_count, "converted": False,
                 "backend": backend_for(cfg)}
        rec = _bounds.record(obj, bounds_settings, mesh)
        bounds_by_id[obj.get("id")] = rec
        entry["bounds"] = {"local": rec["local"], "world": rec["world"], "primary_range": rec["streaming"]["range"],
                           "secondary_range": rec["streaming"]["secondary_range"], "visibility_distance": rec["visibility"]["distance"],
                           "cells": rec["streaming"]["cells"]}
        saved = ((obj.get("metadata") or {}).get("generated_bounds") or {}).get("local")
        diff = _bounds.compare(saved, rec["local"])
        if diff is not None and diff > 0.05:
            report.setdefault("warnings", []).append(f"{label}: saved bounds differ from the built mesh by {diff:.3f} m (the mesh bounds are used)")
        report["generated"].append(entry)
        if entry["backend"] == "native":
            try:
                built = native_mesh(obj, reference=reference)
            except (ValueError, KeyError, TypeError) as exc:
                report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: {exc}"})
                continue
            doc_path = root / "source" / "raw" / Path(str(rel) + ".json")
            doc_path.parent.mkdir(parents=True, exist_ok=True)
            doc_path.write_text(json.dumps(built["document"], ensure_ascii=False), encoding="utf-8")
            entry.update(mesh_json=str(doc_path), stats=built["stats"])
            if built["stats"].get("warning"):
                report.setdefault("warnings", []).append(f"{label}: {built['stats']['warning']}")
            if not worker:
                report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: the WolvenKit worker is not ready (build_worker_preflight); it writes the native .mesh"})
                continue
            target = root / "source" / "archive" / rel
            ok, out = _run_worker(worker, doc_path, target, timeout)
            if not ok:
                report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: the worker did not write a CR2W .mesh", "output": out})
                continue
            entry.update(converted=True, mesh_file=str(target))
            continue
        template = str((cfg.get("material") or {}).get("template") or "")
        local = template_file(template) if (template and template_file) else None
        if not template:
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: no materials; set material.materials (slot -> .mi, native mesh) or material.template (a .mesh to import over)"})
            continue
        if local is None or not Path(local).is_file():
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: template {template} is not available locally; extract it with WolvenKit into mod_sources (or a source folder)"})
            continue
        if not cli:
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: WolvenKit CLI not found; pass cli or put cp77tools / WolvenKit.CLI on PATH"})
            continue
        work_mesh = glb.with_suffix(".mesh")
        shutil.copy2(local, work_mesh)
        before = hashlib.sha256(work_mesh.read_bytes()).hexdigest()
        cmd = _import_command(cli, glb, work_mesh)
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        except (OSError, subprocess.SubprocessError) as exc:
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: mesh import failed to run: {exc}", "command": cmd})
            continue
        if proc.returncode != 0 or hashlib.sha256(work_mesh.read_bytes()).hexdigest() == before:
            report["issues"].append({"object_id": obj.get("id"), "error": f"{label}: WolvenKit did not import the geometry (exit {proc.returncode})",
                                     "command": cmd, "output": (proc.stdout + proc.stderr)[-2000:]})
            continue
        target = root / "source" / "archive" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(work_mesh, target)
        entry.update(converted=True, mesh_file=str(target))
    report["ready"] = not report["issues"]
    if report["ready"]:
        export = json.loads(raw_export.read_text(encoding="utf-8"))
        report["nodes"] = inject_nodes(export, objects, bounds_by_id, project)
        raw_export.write_text(json.dumps(export, ensure_ascii=False), encoding="utf-8")
        manifest["sourceExportSha256"] = manifest.get("sourceExportSha256") or manifest.get("exportSha256")
        manifest["exportSha256"] = hashlib.sha256(raw_export.read_bytes()).hexdigest()
        required = list(manifest.get("nativeRequiredTypes") or [])
        if "worldMeshNode" not in required:
            required.append("worldMeshNode")
        manifest["nativeRequiredTypes"] = required
        manifest["proceduralMeshes"] = [e["mesh_path"] for e in report["generated"]]
        (root / ".cp77wb-build.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if output is not None:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        Path(output).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report
