"""Streaming/performance estimate for World Builder native exports.

Per sector: node counts by category (static meshes, lights, audio, decals,
VFX, dynamic entities, collision, meta), a weighted relative cost, known
expensive resources, nodes that stay streamed from very far away, budget
overruns, and unusually dense clusters. Costs compare areas; they are not
measured frame time.
"""
from __future__ import annotations

import math
import statistics
from typing import Any

# Node type -> (category, relative cost, expensive reason or None).
NODE_CLASSES: dict[str, tuple[str, float, str | None]] = {
    "worldStaticMeshNode": ("static", 1.0, None),
    "worldInstancedMeshNode": ("static", 1.0, None),
    "worldRotatingMeshNode": ("dynamic", 3.0, "animated rotating mesh"),
    "worldClothMeshNode": ("dynamic", 6.0, "cloth simulation"),
    "worldDynamicMeshNode": ("dynamic", 5.0, "physics-simulated mesh"),
    "worldEntityNode": ("dynamic", 3.0, None),
    "worldDeviceNode": ("dynamic", 3.0, None),
    "worldPopulationSpawnerNode": ("dynamic", 6.0, "NPC population spawner"),
    "worldStaticLightNode": ("lights", 4.0, None),
    "worldReflectionProbeNode": ("lights", 6.0, "reflection probe"),
    "worldStaticSoundEmitterNode": ("audio", 2.0, None),
    "worldAmbientAreaNode": ("audio", 1.0, None),
    "worldStaticDecalNode": ("decals", 1.5, None),
    "worldStaticParticleNode": ("vfx", 4.0, None),
    "worldEffectNode": ("vfx", 4.0, None),
    "worldStaticFogVolumeNode": ("vfx", 5.0, "volumetric fog volume"),
    "worldWaterPatchNode": ("vfx", 6.0, "water patch"),
    "worldCollisionNode": ("collision", 0.5, None),
}
CATEGORIES = ("static", "lights", "audio", "decals", "vfx", "dynamic", "collision", "meta")
SECTOR_BUDGET = {"nodes": 1500, "lights": 60, "audio": 40, "decals": 300, "vfx": 50, "dynamic": 150, "cost": 2500}
LONG_STREAMING_RANGE = 1000.0
CELL_SIZE = 5.0
CLUSTER_MIN_COST = 40.0
CLUSTER_SIGMA = 3.0


def classify(node: dict[str, Any]) -> dict[str, Any]:
    category, cost, expensive = NODE_CLASSES.get(str(node.get("type")), ("meta", 0.2, None))
    data = node.get("data") if isinstance(node.get("data"), dict) else {}
    if category == "lights":
        radius = data.get("radius")
        if isinstance(radius, (int, float)) and radius > 15:
            cost += radius / 5
            expensive = expensive or f"light radius {radius:g} m"
    if category == "vfx":
        rate = data.get("emissionRate")
        if isinstance(rate, (int, float)) and rate > 5:
            cost += rate / 5
            expensive = expensive or f"particle emission rate {rate:g}"
    return {"category": category, "cost": cost, "expensive": expensive}


def _blank() -> dict[str, float]:
    counts: dict[str, float] = {"nodes": 0, "cost": 0.0, "expensive": 0}
    counts.update({c: 0 for c in CATEGORIES})
    return counts


def _add(counts: dict[str, float], info: dict[str, Any]) -> None:
    counts["nodes"] += 1
    counts[info["category"]] += 1
    counts["cost"] += info["cost"]
    if info["expensive"]:
        counts["expensive"] += 1


def _over(counts: dict[str, float], budget: dict[str, float]) -> list[dict[str, Any]]:
    return [{"metric": k, "value": round(counts[k], 1), "limit": v} for k, v in sorted(budget.items()) if counts.get(k, 0) > v]


def clusters(rows: list[dict[str, Any]], cell_size: float = CELL_SIZE, min_cost: float = CLUSTER_MIN_COST,
             sigma: float = CLUSTER_SIGMA) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Dense XY grid cells (cost >= max(min_cost, median + sigma * MAD * 1.4826)), merged when touching.

    Median/MAD keep a single very dense cell from hiding itself by inflating the mean and stddev.
    """
    cells: dict[tuple[int, int], dict[str, Any]] = {}
    for row in rows:
        p = row["position"]
        key = (math.floor(p["x"] / cell_size), math.floor(p["y"] / cell_size))
        cell = cells.setdefault(key, {"cost": 0.0, "rows": []})
        cell["cost"] += row["info"]["cost"]
        cell["rows"].append(row)
    if not cells:
        return [], {"cells": 0, "median": 0, "robust_spread": 0, "threshold": 0, "cell_size": cell_size}
    costs = [c["cost"] for c in cells.values()]
    med = statistics.median(costs)
    spread = statistics.median(abs(c - med) for c in costs) * 1.4826
    threshold = max(min_cost, med + sigma * spread)
    dense = {k for k, c in cells.items() if c["cost"] >= threshold}
    seen: set[tuple[int, int]] = set()
    out = []
    for start in sorted(dense):
        if start in seen:
            continue
        stack, members = [start], []
        seen.add(start)
        while stack:
            k = stack.pop()
            members.append(k)
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    n = (k[0] + di, k[1] + dj)
                    if n in dense and n not in seen:
                        seen.add(n)
                        stack.append(n)
        rows_in = [r for k in members for r in cells[k]["rows"]]
        counts = _blank()
        for r in rows_in:
            _add(counts, r["info"])
        center = {a: sum(r["position"][a] for r in rows_in) / len(rows_in) for a in "xyz"}
        radius = max(math.hypot(r["position"]["x"] - center["x"], r["position"]["y"] - center["y"]) for r in rows_in)
        top = sorted(rows_in, key=lambda r: -r["info"]["cost"])[:8]
        counts["cost"] = round(counts["cost"], 1)
        out.append({"center": center, "radius": round(radius, 1), "cells": len(members), "counts": counts,
                    "sectors": sorted({r.get("sector") for r in rows_in if r.get("sector")}),
                    "top_contributors": [{"name": r.get("name"), "type": r.get("type"), "sector": r.get("sector"),
                                          "cost": round(r["info"]["cost"], 1), "expensive": r["info"]["expensive"]} for r in top]})
    out.sort(key=lambda c: -c["counts"]["cost"])
    return out, {"cells": len(cells), "median": round(med, 1), "robust_spread": round(spread, 1),
                 "threshold": round(threshold, 1), "cell_size": cell_size}


def analyze_export(export: dict[str, Any], *, budget: dict[str, float] | None = None,
                   player: dict[str, float] | None = None) -> dict[str, Any]:
    budget = budget or SECTOR_BUDGET
    rows: list[dict[str, Any]] = []
    sectors = []
    for si, sector in enumerate(export.get("sectors") or []):
        if not isinstance(sector, dict):
            continue
        name = str(sector.get("name") or f"sector_{si}")
        counts = _blank()
        expensive, far = [], []
        for node in sector.get("nodes") or []:
            if not isinstance(node, dict):
                continue
            info = classify(node)
            _add(counts, info)
            pos = node.get("position") if isinstance(node.get("position"), dict) else None
            if info["expensive"]:
                expensive.append({"name": node.get("name"), "type": node.get("type"), "reason": info["expensive"]})
            rng = node.get("secondaryRange")
            if isinstance(rng, (int, float)) and rng > LONG_STREAMING_RANGE:
                far.append({"name": node.get("name"), "type": node.get("type"), "secondary_range": rng})
            if pos and all(isinstance(pos.get(a), (int, float)) for a in "xyz"):
                rows.append({"sector": name, "name": node.get("name"), "type": node.get("type"),
                             "position": {a: float(pos[a]) for a in "xyz"}, "info": info})
        counts["cost"] = round(counts["cost"], 1)
        lo, hi = sector.get("min"), sector.get("max")
        center = None
        if isinstance(lo, dict) and isinstance(hi, dict):
            try:
                center = {a: (float(lo[a]) + float(hi[a])) / 2 for a in "xyz"}
            except (KeyError, TypeError, ValueError):
                center = None
        entry = {"name": name, "counts": counts, "over_budget": _over(counts, budget), "expensive": expensive[:25],
                 "expensive_total": len(expensive), "long_streaming_range": far[:25], "long_streaming_total": len(far)}
        if player and center:
            entry["distance_from_player"] = round(math.dist([player[a] for a in "xyz"], [center[a] for a in "xyz"]), 1)
        sectors.append(entry)
    found, stats = clusters(rows)
    if player:
        for c in found:
            c["distance_from_player"] = round(math.dist([player[a] for a in "xyz"], [c["center"][a] for a in "xyz"]), 1)
    totals = _blank()
    for r in rows:
        _add(totals, r["info"])
    totals["cost"] = round(totals["cost"], 1)
    sectors.sort(key=lambda s: -s["counts"]["cost"])
    warnings = [{"sector": s["name"], **o} for s in sectors for o in s["over_budget"]]
    warnings += [{"sector": s["name"], "metric": "long_streaming_range", "value": s["long_streaming_total"],
                  "limit": 0} for s in sectors if s["long_streaming_total"]]
    return {"totals": totals, "sectors": sectors, "clusters": found, "cluster_stats": stats, "warnings": warnings,
            "budget": budget, "long_streaming_range_m": LONG_STREAMING_RANGE,
            "note": "Relative cost estimate from node types and data, not measured frame time."}
