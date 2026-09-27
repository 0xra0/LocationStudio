"""Exact constructive solid geometry for procedural objects (Build Mod).

The in-game module (modules/csg.lua) saves every CSG object's tree, expanded
to primitive leaves, as ``metadata.procedural.csg.tree``. Its preview and
collision are grid boxes. This module meshes the same tree exactly:

* each leaf (box, wedge, cylinder, sphere, prism) is triangulated with
  ``procedural.mesh_from_parts`` into a closed solid;
* ``union`` / ``subtract`` / ``intersect`` use BSP-tree clipping, the
  algorithm of Evan Wallace's csg.js, implemented iteratively here;
* faces keep their material slot. Faces cut by a subtraction take the node's
  ``cut_material`` (default ``main``), so a glass cutter does not glaze the hole;
* the result becomes a ``procedural.Mesh`` with interpolated normals and the
  usual world-projected UVs, so the glb/native mesh backends and material UV
  scaling apply unchanged.

Curved leaves keep their facet counts (``sides``). The result is exact for the
faceted solids.
"""
from __future__ import annotations

import math
from typing import Any

EPS = 1e-5
COPLANAR, FRONT, BACK, SPANNING = 0, 1, 2, 3


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def _unit(a):
    n = math.sqrt(_dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n) if n > 1e-12 else (0.0, 0.0, 1.0)


class Plane:
    __slots__ = ("n", "w")

    def __init__(self, n, w):
        self.n, self.w = n, w

    @classmethod
    def from_points(cls, a, b, c) -> "Plane | None":
        n = _cross(_sub(b, a), _sub(c, a))
        length = math.sqrt(_dot(n, n))
        if length < 1e-12:
            return None
        n = (n[0] / length, n[1] / length, n[2] / length)
        return cls(n, _dot(n, a))

    def flipped(self) -> "Plane":
        return Plane((-self.n[0], -self.n[1], -self.n[2]), -self.w)

    def split(self, poly: "Polygon", coplanar_front, coplanar_back, front, back) -> None:
        types = []
        kind = 0
        for v in poly.verts:
            t = _dot(self.n, v[0]) - self.w
            ty = BACK if t < -EPS else FRONT if t > EPS else COPLANAR
            kind |= ty
            types.append(ty)
        if kind == COPLANAR:
            (coplanar_front if _dot(self.n, poly.plane.n) > 0 else coplanar_back).append(poly)
        elif kind == FRONT:
            front.append(poly)
        elif kind == BACK:
            back.append(poly)
        else:
            f, b = [], []
            n = len(poly.verts)
            for i in range(n):
                j = (i + 1) % n
                ti, tj = types[i], types[j]
                vi, vj = poly.verts[i], poly.verts[j]
                if ti != BACK:
                    f.append(vi)
                if ti != FRONT:
                    b.append(vi)
                if (ti | tj) == SPANNING:
                    t = (self.w - _dot(self.n, vi[0])) / _dot(self.n, _sub(vj[0], vi[0]))
                    v = (_lerp(vi[0], vj[0], t), _lerp(vi[1], vj[1], t))
                    f.append(v)
                    b.append(v)
            if len(f) >= 3:
                front.append(Polygon(f, poly.material, poly.plane))
            if len(b) >= 3:
                back.append(Polygon(b, poly.material, poly.plane))


class Polygon:
    """Convex planar polygon: verts are (position, normal) tuples."""
    __slots__ = ("verts", "material", "plane")

    def __init__(self, verts, material: str, plane: Plane | None = None):
        self.verts = verts
        self.material = material
        self.plane = plane or Plane.from_points(verts[0][0], verts[1][0], verts[2][0])

    def flipped(self) -> "Polygon":
        return Polygon([(p, (-n[0], -n[1], -n[2])) for p, n in reversed(self.verts)], self.material, self.plane.flipped())


class Node:
    __slots__ = ("plane", "front", "back", "polygons")

    def __init__(self, polygons: list[Polygon] | None = None):
        self.plane: Plane | None = None
        self.front: Node | None = None
        self.back: Node | None = None
        self.polygons: list[Polygon] = []
        if polygons:
            self.build(polygons)

    def _nodes(self):
        stack, out = [self], []
        while stack:
            n = stack.pop()
            out.append(n)
            if n.front:
                stack.append(n.front)
            if n.back:
                stack.append(n.back)
        return out

    def invert(self) -> None:
        for n in self._nodes():
            n.polygons = [p.flipped() for p in n.polygons]
            if n.plane:
                n.plane = n.plane.flipped()
            n.front, n.back = n.back, n.front

    def clip_polygons(self, polygons: list[Polygon]) -> list[Polygon]:
        """Remove the parts of `polygons` inside this BSP tree's solid."""
        out: list[Polygon] = []
        stack = [(self, polygons)]
        while stack:
            node, polys = stack.pop()
            if node.plane is None:
                out.extend(polys)
                continue
            front: list[Polygon] = []
            back: list[Polygon] = []
            for p in polys:
                node.plane.split(p, front, back, front, back)
            if node.front:
                stack.append((node.front, front))
            else:
                out.extend(front)
            if node.back:
                stack.append((node.back, back))
            # polygons behind a leaf are inside: dropped
        return out

    def clip_to(self, other: "Node") -> None:
        for n in self._nodes():
            n.polygons = other.clip_polygons(n.polygons)

    def all_polygons(self) -> list[Polygon]:
        out: list[Polygon] = []
        for n in self._nodes():
            out.extend(n.polygons)
        return out

    def build(self, polygons: list[Polygon]) -> None:
        stack = [(self, [p for p in polygons if p.plane is not None])]
        while stack:
            node, polys = stack.pop()
            if not polys:
                continue
            if node.plane is None:
                node.plane = polys[0].plane
            front: list[Polygon] = []
            back: list[Polygon] = []
            for p in polys:
                node.plane.split(p, node.polygons, node.polygons, front, back)
            if front:
                node.front = node.front or Node()
                stack.append((node.front, front))
            if back:
                node.back = node.back or Node()
                stack.append((node.back, back))


def union(a: list[Polygon], b: list[Polygon]) -> list[Polygon]:
    na, nb = Node(a), Node(b)
    na.clip_to(nb)
    nb.clip_to(na)
    nb.invert()
    nb.clip_to(na)
    nb.invert()
    na.build(nb.all_polygons())
    return na.all_polygons()


def subtract(a: list[Polygon], b: list[Polygon]) -> list[Polygon]:
    na, nb = Node(a), Node(b)
    na.invert()
    na.clip_to(nb)
    nb.clip_to(na)
    nb.invert()
    nb.clip_to(na)
    nb.invert()
    na.build(nb.all_polygons())
    na.invert()
    return na.all_polygons()


def intersect(a: list[Polygon], b: list[Polygon]) -> list[Polygon]:
    na, nb = Node(a), Node(b)
    na.invert()
    nb.clip_to(na)
    nb.invert()
    na.clip_to(nb)
    nb.clip_to(na)
    na.build(nb.all_polygons())
    na.invert()
    return na.all_polygons()


# --------------------------------------------------------------------------- trees

def _vec(v: Any) -> dict[str, float]:
    if isinstance(v, dict):
        return {"x": float(v.get("x", 0)), "y": float(v.get("y", 0)), "z": float(v.get("z", 0))}
    v = list(v) + [0, 0, 0]
    return {"x": float(v[0]), "y": float(v[1]), "z": float(v[2])}


def _leaf_part(leaf: dict[str, Any]) -> dict[str, Any]:
    part = dict(leaf)
    if part.get("shape") == "prism":
        part["points"] = [p if isinstance(p, dict) else {"x": p[0], "y": p[1]} for p in part["points"]]
    else:
        part["center"] = _vec(part["center"])
        if "size" in part:
            part["size"] = _vec(part["size"])
    part["material"] = "glass" if part.get("material") == "glass" else "main"
    return part


def leaf_polygons(leaf: dict[str, Any]) -> list[Polygon]:
    """Closed solid of one primitive, as triangles."""
    from .procedural import mesh_from_parts

    mesh = mesh_from_parts([_leaf_part(leaf)])
    out: list[Polygon] = []
    for material, prim in mesh.prims.items():
        pos, nrm, idx = prim["pos"], prim["nrm"], prim["idx"]
        for t in range(0, len(idx), 3):
            verts = [(tuple(pos[i]), tuple(nrm[i])) for i in idx[t:t + 3]]
            plane = Plane.from_points(verts[0][0], verts[1][0], verts[2][0])
            if plane is not None:
                out.append(Polygon(verts, material, plane))
    return out


def _translate(node: dict[str, Any], d: tuple[float, float, float]) -> dict[str, Any]:
    if node.get("shape"):
        leaf = _leaf_part(node)
        if leaf["shape"] == "prism":
            leaf["points"] = [{"x": p["x"] + d[0], "y": p["y"] + d[1]} for p in leaf["points"]]
            leaf["z0"], leaf["z1"] = float(leaf["z0"]) + d[2], float(leaf["z1"]) + d[2]
        else:
            c = leaf["center"]
            leaf["center"] = {"x": c["x"] + d[0], "y": c["y"] + d[1], "z": c["z"] + d[2]}
        return leaf
    return {**node, "children": [_translate(c, d) for c in node.get("children") or []]}


def expand(raw: dict[str, Any], _depth: int = 0) -> dict[str, Any]:
    """Expand ``repeat`` in a raw tree (primitive leaves only; generator leaves are expanded in game)."""
    if _depth > 16:
        raise ValueError("CSG tree is deeper than 16 levels")
    if not isinstance(raw, dict):
        raise ValueError("CSG nodes must be objects")
    if raw.get("generator") is not None:
        raise ValueError("generator leaves are expanded by LocationStudio in game; mesh a saved CSG object by object_id instead")
    if raw.get("op") is not None:
        node = {"op": raw["op"], "children": [expand(c, _depth + 1) for c in raw.get("children") or []]}
        if raw.get("cut_material"):
            node["cut_material"] = raw["cut_material"]
    elif raw.get("shape"):
        node = {k: v for k, v in raw.items() if k != "repeat"}
    else:
        raise ValueError("a CSG node needs op or shape")
    rep = raw.get("repeat")
    if rep:
        count, step = int(rep.get("count", 1)), _vec(rep.get("step") or [0, 0, 0])
        if not 1 <= count <= 100:
            raise ValueError("repeat count must be 1-100")
        node = {"op": "union", "children": [_translate(node, (step["x"] * i, step["y"] * i, step["z"] * i)) for i in range(count)]}
    return node


def evaluate(node: dict[str, Any], _depth: int = 0) -> list[Polygon]:
    """Polygons of the solid a tree describes."""
    if _depth > 64:
        raise ValueError("CSG tree is too deep")
    if node.get("shape"):
        return leaf_polygons(node)
    op = node.get("op")
    children = node.get("children") or []
    if op not in ("union", "subtract", "intersect") or not children:
        raise ValueError(f"invalid CSG node (op {op!r})")
    result = evaluate(children[0], _depth + 1)
    for child in children[1:]:
        other = evaluate(child, _depth + 1)
        if op == "union":
            result = union(result, other)
        elif op == "subtract":
            cut = node.get("cut_material") or "main"
            result = subtract(result, [Polygon(p.verts, cut, p.plane) for p in other])
        else:
            result = intersect(result, other)
    return result


WELD = 1e-4  # 0.1 mm: BSP intersections computed through near-parallel planes differ by a few micrometres


def weld(polygons: list[Polygon], tol: float = WELD) -> list[Polygon]:
    """Snap vertices closer than `tol` to one position; drop repeated vertices and degenerate polygons."""
    cells: dict[tuple[int, int, int], list[tuple[float, float, float]]] = {}

    def snap(p):
        key = (math.floor(p[0] / tol), math.floor(p[1] / tol), math.floor(p[2] / tol))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    for q in cells.get((key[0] + dx, key[1] + dy, key[2] + dz), ()):
                        if _dot(_sub(p, q), _sub(p, q)) <= tol * tol:
                            return q
        cells.setdefault(key, []).append(p)
        return p

    out = []
    for poly in polygons:
        verts = []
        for p, n in poly.verts:
            q = snap(p)
            if not verts or verts[-1][0] != q:
                verts.append((q, n))
        while len(verts) > 1 and verts[0][0] == verts[-1][0]:
            verts.pop()
        if len(verts) >= 3:
            out.append(Polygon(verts, poly.material, poly.plane))
    return out


def fix_t_junctions(polygons: list[Polygon], eps: float = WELD / 2) -> list[Polygon]:
    """Insert every vertex that lies on another polygon's edge into that edge.

    BSP splitting leaves T-junctions (a vertex of one face in the middle of a
    neighbour's edge), which render as hairline cracks. Adding those vertices
    makes the triangulated surface watertight.
    """
    import bisect

    points = sorted({p for poly in polygons for p, _n in poly.verts})
    xs = [p[0] for p in points]
    out = []
    for poly in polygons:
        verts = []
        n = len(poly.verts)
        for i in range(n):
            (a, na), (b, nb) = poly.verts[i], poly.verts[(i + 1) % n]
            verts.append((a, na))
            d = _sub(b, a)
            length2 = _dot(d, d)
            if length2 < 1e-14:
                continue
            lo, hi = min(a[0], b[0]) - eps, max(a[0], b[0]) + eps
            extra = []
            for p in points[bisect.bisect_left(xs, lo):bisect.bisect_right(xs, hi)]:
                t = _dot(_sub(p, a), d) / length2
                if _dot(_sub(p, a), _sub(p, a)) <= eps * eps or _dot(_sub(p, b), _sub(p, b)) <= eps * eps or t <= 0 or t >= 1:
                    continue
                q = _lerp(a, b, t)
                if _dot(_sub(p, q), _sub(p, q)) <= eps * eps:
                    extra.append((t, p))
            for t, p in sorted(extra):
                verts.append((p, _lerp(na, nb, t)))
        out.append(Polygon(verts, poly.material, poly.plane) if len(verts) != n else poly)
    return out


def to_mesh(polygons: list[Polygon], *, uv_scale: float = 1.0, slot_uv: dict[str, Any] | None = None):
    """A procedural.Mesh (per-slot primitives, UVs) from CSG polygons, with T-junctions repaired."""
    from .procedural import Mesh

    mesh = Mesh(uv_scale, slot_uv)
    for poly in fix_t_junctions(weld(polygons)):
        verts = []
        for p, n in poly.verts:
            if not verts or math.dist(verts[-1][0], p) > 1e-9:
                verts.append((p, n))
        if len(verts) > 1 and math.dist(verts[0][0], verts[-1][0]) <= 1e-9:
            verts.pop()
        if len(verts) < 3:
            continue
        pn = poly.plane.n
        area = 0.0
        for i in range(1, len(verts) - 1):
            c = _cross(_sub(verts[i][0], verts[0][0]), _sub(verts[i + 1][0], verts[0][0]))
            area += math.sqrt(_dot(c, c)) / 2
        if area < 1e-9:
            continue
        prim = mesh._prim(poly.material)
        pts = [v[0] for v in verts]
        collinear = any(abs(_dot(_cross(_sub(pts[i], pts[i - 1]), _sub(pts[(i + 1) % len(pts)], pts[i])), pn)) < 1e-12 for i in range(len(pts)))
        if collinear:
            # T-junction vertices sit on straight edges: fan from the centroid so no triangle is degenerate.
            c = tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))
            nc = tuple(sum(v[1][k] for v in verts) for k in range(3))
            verts = verts + [(c, nc)]
        base = len(prim["pos"])
        for p, n in verts:
            prim["pos"].append(p)
            prim["nrm"].append(_unit(n) if _dot(n, pn) > 0 else pn)
            prim["uv"].append(mesh._uv(p, pn, poly.material))
        m = len(pts)
        if collinear:
            for i in range(m):
                prim["idx"].extend((base + m, base + i, base + (i + 1) % m))
        else:
            for i in range(1, m - 1):
                prim["idx"].extend((base, base + i, base + i + 1))
    return mesh


def mesh_from_tree(tree: dict[str, Any], *, uv_scale: float = 1.0, slot_uv: dict[str, Any] | None = None):
    polygons = evaluate(tree)
    if not polygons:
        raise ValueError("the CSG tree produces an empty solid")
    return to_mesh(polygons, uv_scale=uv_scale, slot_uv=slot_uv)


def volume(mesh) -> float:
    """Enclosed volume of a closed mesh (divergence theorem)."""
    total = 0.0
    for prim in mesh.prims.values():
        p, idx = prim["pos"], prim["idx"]
        for t in range(0, len(idx), 3):
            a, b, c = p[idx[t]], p[idx[t + 1]], p[idx[t + 2]]
            total += _dot(a, _cross(b, c)) / 6
    return total


def open_edges(mesh) -> int:
    """Boundary edges of the welded mesh (0 for a closed solid).

    Vertices are welded by position. T-junctions from BSP splitting show up as
    boundary edges, so this counts, it does not prove, watertightness.
    """
    key = lambda v: (round(v[0], 5), round(v[1], 5), round(v[2], 5))  # noqa: E731
    count: dict[tuple, int] = {}
    for prim in mesh.prims.values():
        p, idx = prim["pos"], prim["idx"]
        for t in range(0, len(idx), 3):
            tri = [key(p[i]) for i in idx[t:t + 3]]
            for i in range(3):
                e = tuple(sorted((tri[i], tri[(i + 1) % 3])))
                count[e] = count.get(e, 0) + 1
    return sum(1 for c in count.values() if c == 1)
