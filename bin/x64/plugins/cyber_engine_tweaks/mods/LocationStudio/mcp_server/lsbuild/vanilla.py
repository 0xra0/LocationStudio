"""Read vanilla nodes from a WolvenKit-exported .streamingsector JSON.

The sector's nodeData buffer holds each node instance's exact transform
(Position, Orientation quaternion, Scale) and the node definition holds its
real resource references. This produces candidates for the in-game
vanilla-clone importer (snake_case, Euler rotation in degrees) so clones get
the exact placement that RedHotTools cannot report live.

Rotation convention: REDengine EulerAngles are roll about Y, pitch about X and
yaw about Z, composed as q = qz(yaw) * qx(pitch) * qy(roll).
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

CLONEABLE = {
    "worldMeshNode", "worldBendedMeshNode", "worldPhysicalDestructionNode", "worldStaticDecalNode",
    "worldEffectNode", "worldStaticParticleNode", "worldEntityNode", "worldDeviceNode", "worldPopulationSpawnerNode",
}
# Per-instance transforms of these live inside the node's own buffer, not in nodeData.
INSTANCE_BUFFER = {"worldInstancedMeshNode", "worldFoliageNode", "worldInstancedDestructibleMeshNode"}


def quat_to_euler(i: float, j: float, k: float, r: float) -> dict[str, float]:
    n = math.sqrt(i * i + j * j + k * k + r * r) or 1.0
    x, y, z, w = i / n, j / n, k / n, r / n
    m01 = 2 * (x * y - w * z)
    m11 = 1 - 2 * (x * x + z * z)
    m20 = 2 * (x * z - w * y)
    m21 = 2 * (y * z + w * x)
    m22 = 1 - 2 * (x * x + y * y)
    pitch = math.degrees(math.asin(max(-1.0, min(1.0, m21))))
    roll = math.degrees(math.atan2(-m20, m22))
    yaw = math.degrees(math.atan2(-m01, m11))
    return {"roll": round(roll, 4), "pitch": round(pitch, 4), "yaw": round(yaw, 4)}


def euler_to_quat(roll: float, pitch: float, yaw: float) -> dict[str, float]:
    p, y, r = (math.radians(v) * 0.5 for v in (pitch, yaw, roll))
    sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    return {"i": cy * sp * cr - sy * cp * sr, "j": cy * cp * sr + sy * sp * cr,
            "k": sy * cp * cr + cy * sp * sr, "r": cy * cp * cr - sy * sp * sr}


def _value(v: Any) -> str | None:
    if isinstance(v, dict):
        if "DepotPath" in v:
            return _value(v["DepotPath"])
        if "$value" in v:
            val = v["$value"]
            return str(val) if val not in (None, "", "0", 0, "None") else None
    if isinstance(v, str) and v:
        return v
    return None


def _num(v: Any, default: float = 0.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


def _root(data: dict[str, Any]) -> dict[str, Any]:
    if isinstance(data.get("Data"), dict) and isinstance(data["Data"].get("RootChunk"), dict):
        return data["Data"]["RootChunk"]
    if isinstance(data.get("RootChunk"), dict):
        return data["RootChunk"]
    return data


def read_sector(path: str | Path, *, center: dict[str, float] | None = None, radius: float | None = None,
                term: str = "", node_indices: list[int] | None = None, match: list[dict[str, Any]] | None = None,
                cloneable_only: bool = False, limit: int = 500,
                box: dict[str, dict[str, float]] | None = None) -> dict[str, Any]:
    """List node instances with exact transforms and resources.

    match: [{node_index, instance_index?}] from staged live picks of this sector.
    box: {min: {x,y,z}, max: {x,y,z}} keeps node instances inside an axis-aligned box.
    """
    file = Path(path)
    root = _root(json.loads(file.read_text(encoding="utf-8")))
    if root.get("$type") not in (None, "worldStreamingSector"):
        raise ValueError(f"not a streaming sector: {root.get('$type')}")
    nodes = root.get("nodes") or []
    node_data = root.get("nodeData") or {}
    buffer = node_data.get("Data") if isinstance(node_data, dict) else node_data
    if not isinstance(buffer, list) or not isinstance(nodes, list):
        raise ValueError("sector JSON has no nodes/nodeData buffer; export it with WolvenKit (Convert to JSON)")
    sector_name = file.name
    for suffix in (".json", ".streamingsector"):
        if sector_name.endswith(suffix):
            sector_name = sector_name[: -len(suffix)]
    wanted_idx = set(int(i) for i in node_indices or [])
    wanted_pairs = {(int(m["node_index"]), m.get("instance_index")) for m in match or [] if m.get("node_index") is not None}
    term = (term or "").lower()
    instance_seen: dict[int, int] = {}
    items: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    total = 0
    for nd in buffer:
        if not isinstance(nd, dict):
            continue
        idx = int(_num(nd.get("NodeIndex"), -1))
        inst = instance_seen.get(idx, 0)
        instance_seen[idx] = inst + 1
        if idx < 0 or idx >= len(nodes):
            continue
        node = (nodes[idx] or {}).get("Data") or {}
        ntype = str(node.get("$type") or "")
        counts[ntype] = counts.get(ntype, 0) + 1
        pos_raw = nd.get("Position") or {}
        pos = {"x": _num(pos_raw.get("X")), "y": _num(pos_raw.get("Y")), "z": _num(pos_raw.get("Z"))}
        if wanted_idx and idx not in wanted_idx:
            continue
        if wanted_pairs and (idx, inst) not in wanted_pairs and (idx, None) not in wanted_pairs:
            continue
        if center is not None and radius is not None:
            if math.dist((pos["x"], pos["y"], pos["z"]), (float(center["x"]), float(center["y"]), float(center["z"]))) > radius:
                continue
        if box is not None and not all(float(box["min"][a]) <= pos[a] <= float(box["max"][a]) for a in "xyz"):
            continue
        q_raw = nd.get("Orientation") or {}
        quat = {k: _num(q_raw.get(k), 1.0 if k == "r" else 0.0) for k in ("i", "j", "k", "r")}
        s_raw = nd.get("Scale") or {}
        scale = {"x": _num(s_raw.get("X"), 1.0), "y": _num(s_raw.get("Y"), 1.0), "z": _num(s_raw.get("Z"), 1.0)}
        ref = nd.get("QuestPrefabRefHash") or {}
        item: dict[str, Any] = {
            "node_type": ntype, "sector_path": sector_name, "node_index": idx, "instance_index": inst,
            "node_id": str(nd.get("Id")) if nd.get("Id") not in (None, "0", 0) else None,
            "node_ref": ref.get("$value") if isinstance(ref, dict) and ref.get("$storage") == "string" else None,
            "debug_name": _value(node.get("debugName")),
            "position": pos, "rotation": quat_to_euler(**quat), "quaternion": quat, "scale": scale,
            "mesh_path": _value(node.get("mesh")), "mesh_appearance": _value(node.get("meshAppearance")),
            "material_path": _value(node.get("material")), "effect_path": _value(node.get("effect")),
            "particle_path": _value(node.get("particleSystem")), "template_path": _value(node.get("entityTemplate")),
            "appearance": _value(node.get("appearanceName")), "record_id": _value(node.get("objectRecordId")),
            "cloneable": ntype in CLONEABLE, "source_kind": "sector_json",
        }
        if ntype in INSTANCE_BUFFER:
            item["cloneable"] = False
            item["reason"] = "per-instance transforms of this node type are inside its own buffer; pick the instance in game instead"
        if term and not any(term in str(item.get(f) or "").lower() for f in
                            ("node_type", "debug_name", "mesh_path", "material_path", "effect_path", "particle_path", "template_path", "record_id", "node_ref")):
            continue
        if cloneable_only and not item["cloneable"]:
            continue
        total += 1
        if len(items) < limit:
            items.append({k: v for k, v in item.items() if v is not None})
    return {"sector": sector_name, "file": str(file), "node_count": len(nodes), "instance_count": len(buffer),
            "type_counts": counts, "matched": total, "items": items, "truncated": total > len(items)}
