"""Automatic bounds for generated resources (Build Mod side).

The in-game module (modules/bounds_gen.lua) keeps bounds records on generated
objects for editing, overlap and visibility tools. At build time the exact
geometry is known: this module derives the same records from the built mesh,
which is exact for CSG as well. Build Mod uses them for:

* node streaming: ``primaryRange`` is the visibility distance (the range at
  which the bounding sphere subtends ``min_screen_angle``) plus
  ``stream_margin``, clamped to [min_range, max_range]. ``secondaryRange`` is
  ``secondary_factor`` times that. A manual ``stream_range`` on the object wins;
* sector choice: the sector that holds the centre of the world bounds, not the pivot;
* sector growth: by the rotated world AABB of the mesh.

The settings come from ``settings.bounds`` in the project, the same as in game.
"""
from __future__ import annotations

import math
from typing import Any

DEFAULTS = {"min_screen_angle": 1.0, "stream_margin": 10.0, "min_range": 30.0, "max_range": 800.0, "secondary_factor": 1.2,
            "cell_size": 128.0, "padding": 0.0}
AXES = ("x", "y", "z")


def settings(project: dict[str, Any] | None) -> dict[str, float]:
    saved = (((project or {}).get("settings") or {}).get("bounds")) or {}
    out = dict(DEFAULTS)
    for k in DEFAULTS:
        try:
            if saved.get(k) is not None:
                out[k] = float(saved[k])
        except (TypeError, ValueError):
            pass
    return out


def _box(lo, hi) -> dict[str, Any]:
    lo = {k: float(lo[i] if isinstance(lo, (list, tuple)) else lo[k]) for i, k in enumerate(AXES)}
    hi = {k: float(hi[i] if isinstance(hi, (list, tuple)) else hi[k]) for i, k in enumerate(AXES)}
    return {"min": lo, "max": hi, "center": {k: (lo[k] + hi[k]) / 2 for k in AXES}, "extents": {k: (hi[k] - lo[k]) / 2 for k in AXES}}


def world_of(local: dict[str, Any], transform: dict[str, Any] | None) -> dict[str, Any]:
    """World AABB of an object-frame box under the procedural rotation convention."""
    from .procedural import rot_matrix

    t = transform or {}
    p = t.get("position") or {}
    m = rot_matrix(t.get("rotation"))
    pos = [float(p.get(k, 0) or 0) for k in AXES]
    pts = []
    for x in (local["min"]["x"], local["max"]["x"]):
        for y in (local["min"]["y"], local["max"]["y"]):
            for z in (local["min"]["z"], local["max"]["z"]):
                pts.append([pos[i] + m[i][0] * x + m[i][1] * y + m[i][2] * z for i in range(3)])
    return _box([min(q[i] for q in pts) for i in range(3)], [max(q[i] for q in pts) for i in range(3)])


def distances(radius: float, s: dict[str, float], manual: float | None = None) -> tuple[float, float, float]:
    vis = radius / math.tan(math.radians(s["min_screen_angle"]) / 2)
    vis = max(s["min_range"], min(s["max_range"], vis))
    rng = float(manual) if manual else max(s["min_range"], min(s["max_range"], vis + s["stream_margin"]))
    return vis, rng, rng * s["secondary_factor"]


def cells(world: dict[str, Any], size: float) -> list[str]:
    lo = {k: math.floor(world["min"][k] / size) for k in AXES}
    hi = {k: math.floor(world["max"][k] / size) for k in AXES}
    return [f"{x},{y},{z}" for x in range(lo["x"], hi["x"] + 1) for y in range(lo["y"], hi["y"] + 1) for z in range(lo["z"], hi["z"] + 1)]


def record(obj: dict[str, Any], s: dict[str, float], mesh=None) -> dict[str, Any]:
    """Bounds record of a procedural object from its (exact) mesh."""
    from .procedural import object_mesh

    mesh = mesh if mesh is not None else object_mesh(obj)
    mb = mesh.bounds()
    pad = s["padding"]
    local = _box([v - pad for v in mb["min"]], [v + pad for v in mb["max"]])
    world = world_of(local, obj.get("transform"))
    e = local["extents"]
    radius = math.sqrt(e["x"] ** 2 + e["y"] ** 2 + e["z"] ** 2)
    cfg = obj["metadata"]["procedural"]
    manual = cfg.get("stream_range")
    vis, rng, secondary = distances(radius, s, float(manual) if manual else None)
    return {"local": local, "world": world, "sphere": {"center": world["center"], "radius": radius},
            "visibility": {"distance": vis, "min": world["min"], "max": world["max"]},
            "streaming": {"range": rng, "secondary_range": secondary, "source": "manual" if manual else "auto",
                          "cells": cells(world, s["cell_size"]), "cell_size": s["cell_size"]},
            "exact": True}


def compare(saved: dict[str, Any] | None, exact: dict[str, Any], tolerance: float = 0.05) -> float | None:
    """Largest difference (m) between saved local bounds and the exact ones, or None when nothing is saved."""
    if not saved or not saved.get("min") or not saved.get("max"):
        return None
    return max(max(abs(float(saved["min"][k]) - exact["min"][k]), abs(float(saved["max"][k]) - exact["max"][k])) for k in AXES)


def report(project: dict[str, Any], premise_id: str | None = None, tolerance: float = 0.05) -> dict[str, Any]:
    """Exact bounds of every generated object in scope, with differences from the saved in-game records."""
    from .materials import definitions, resolve_object
    from .procedural import procedural_objects

    s = settings(project)
    defs = definitions(project)
    rows, issues = [], []
    for o in procedural_objects(project, premise_id):
        try:
            rec = record(resolve_object(o, defs), s)
        except (ValueError, KeyError, TypeError) as exc:
            issues.append({"object_id": o.get("id"), "name": o.get("name"), "error": str(exc)})
            continue
        saved = ((o.get("metadata") or {}).get("generated_bounds") or {}).get("local") or (o.get("metadata") or {}).get("asset_bounds")
        diff = compare(saved, rec["local"], tolerance)
        row = {"object_id": o.get("id"), "name": o.get("name"), **rec, "saved_difference": diff}
        if diff is not None and diff > tolerance:
            issues.append({"object_id": o.get("id"), "name": o.get("name"),
                           "warning": f"saved local bounds differ from the built mesh by {diff:.3f} m; refresh bounds in game (bounds_refresh)"})
        if len(rec["streaming"]["cells"]) > 1:
            issues.append({"object_id": o.get("id"), "name": o.get("name"),
                           "info": f"spans {len(rec['streaming']['cells'])} streaming cells of {s['cell_size']:g} m"})
        rows.append(row)
    colliders = []
    for o in project.get("objects") or []:
        md = (o or {}).get("metadata") or {}
        if md.get("collision_gen") and (not premise_id or o.get("premise_id") == premise_id):
            rec = md.get("generated_bounds") or {}
            colliders.append({"object_id": o.get("id"), "owner": md["collision_gen"].get("owner"), "room_id": o.get("room_id"),
                              "world": rec.get("world")})
    return {"settings": s, "objects": rows, "colliders": colliders, "issues": issues, "count": len(rows)}
