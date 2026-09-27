"""Streaming-sector inspector for World Builder native exports.

Reports, for every exported node: its sector, variant range, NodeRef,
position/streaming reference point, linked device and persistent-state
IDs, NodeRefs it references, and the LocationStudio object it came from.
Flags nodes whose placement suggests the wrong sector. Read-only: the
export is never modified.
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

SCHEMA = "locationstudio-sector-inspection/1"
BOUNDS_TOLERANCE = 0.5          # metres outside a sector box before it counts as outside
DEVICE_MATCH_DISTANCE = 0.05    # device.nodePosition -> node.position
OBJECT_MATCH_DISTANCE = 0.1     # project object -> node.position
OUTLIER_MIN_DISTANCE = 50.0     # never call a node an outlier closer than this to its sector centroid
OUTLIER_FACTOR = 3.0            # ... or than this multiple of the sector's 90th-percentile spread


def _vec(value: Any) -> dict[str, float] | None:
    if not isinstance(value, dict):
        return None
    try:
        out = {axis: float(value[axis]) for axis in ("x", "y", "z")}
    except (KeyError, TypeError, ValueError):
        return None
    return out if all(math.isfinite(v) for v in out.values()) else None


def _dist(a: dict[str, float], b: dict[str, float]) -> float:
    return math.sqrt(sum((a[k] - b[k]) ** 2 for k in "xyz"))


def _inside(p: dict[str, float], lo: dict[str, float] | None, hi: dict[str, float] | None, tol: float) -> bool | None:
    if lo is None or hi is None:
        return None
    return all(lo[k] - tol <= p[k] <= hi[k] + tol for k in "xyz")


def _outside_by(p: dict[str, float], lo: dict[str, float], hi: dict[str, float]) -> float:
    return math.sqrt(sum(max(lo[k] - p[k], 0.0, p[k] - hi[k]) ** 2 for k in "xyz"))


def _referenced_refs(value: Any, own: str | None, out: set[str]) -> None:
    """Collect NodeRef strings used inside node data (typed NodeRef values or '$/...' paths)."""
    if isinstance(value, dict):
        if value.get("$type") == "NodeRef" and isinstance(value.get("$value"), str):
            ref = value["$value"]
            if ref.startswith("$/") and ref != own:
                out.add(ref)
        for item in value.values():
            _referenced_refs(item, own, out)
    elif isinstance(value, list):
        for item in value:
            _referenced_refs(item, own, out)
    elif isinstance(value, str) and value.startswith("$/") and value != own and "#" in value:
        out.add(value)


def _variant_for(index: int, sector: dict[str, Any]) -> dict[str, Any] | None:
    indices = sector.get("variantIndices") if isinstance(sector.get("variantIndices"), list) else [0]
    variants = sector.get("variants") if isinstance(sector.get("variants"), list) else []
    rng = None
    for i, start in enumerate(indices):
        end = indices[i + 1] if i + 1 < len(indices) else None
        if isinstance(start, int) and index >= start and (end is None or index < end):
            rng = i
    if not rng:
        return {"range": rng or 0, "name": "default"}
    variant = next((v for v in variants if isinstance(v, dict) and v.get("rangeIndex", v.get("index")) == rng), None)
    name = variant.get("name") if isinstance(variant, dict) else None
    if isinstance(name, dict):
        name = name.get("$value")
    return {"range": rng, "name": name or f"range {rng}"}


def _project_objects(project_file: str | Path | None) -> list[dict[str, Any]]:
    if not project_file or not Path(project_file).is_file():
        return []
    project = json.loads(Path(project_file).read_text(encoding="utf-8"))
    out = []
    for obj in project.get("objects", []):
        if not isinstance(obj, dict):
            continue
        pos = _vec(((obj.get("transform") or {}).get("position")))
        if pos is not None and isinstance((obj.get("metadata") or {}).get("world_builder"), dict):
            out.append({"id": obj.get("id"), "name": obj.get("name") or "", "premise_id": obj.get("premise_id"),
                        "room_id": obj.get("room_id"), "position": pos})
    return out


def inspect(export_file: str | Path, project_file: str | Path | None = None, *, sector: str | None = None,
            include_nodes: bool = True, output: str | Path | None = None) -> dict[str, Any]:
    export_path = Path(export_file)
    data = json.loads(export_path.read_text(encoding="utf-8"))
    raw_sectors = data.get("sectors") if isinstance(data.get("sectors"), list) else []
    devices = data.get("devices") if isinstance(data.get("devices"), dict) else {}
    ps_entries = data.get("psEntries") if isinstance(data.get("psEntries"), dict) else {}
    objects = _project_objects(project_file)

    sectors: list[dict[str, Any]] = []
    nodes: list[dict[str, Any]] = []
    ref_owner: dict[str, str] = {}
    for si, raw in enumerate(raw_sectors):
        if not isinstance(raw, dict):
            continue
        name = str(raw.get("name") or f"sector_{si}")
        lo, hi = _vec(raw.get("min")), _vec(raw.get("max"))
        entry = {"name": name, "index": si, "category": raw.get("category"), "level": raw.get("level"),
                 "bounds": {"min": lo, "max": hi} if lo and hi else None, "node_count": 0, "node_types": {},
                 "variants": len(raw.get("variants") or []), "node_refs": 0, "devices": 0, "ps_entries": 0}
        sectors.append(entry)
        for ni, node in enumerate(raw.get("nodes") or []):
            if not isinstance(node, dict):
                continue
            pos = _vec(node.get("position"))
            ref = node.get("nodeRef") if isinstance(node.get("nodeRef"), str) and node.get("nodeRef") else None
            ntype = str(node.get("type") or "<missing>")
            entry["node_count"] += 1
            entry["node_types"][ntype] = entry["node_types"].get(ntype, 0) + 1
            if ref:
                entry["node_refs"] += 1
                ref_owner.setdefault(ref, name)
            refs: set[str] = set()
            _referenced_refs(node.get("data"), ref, refs)
            nodes.append({"sector": name, "index": ni, "name": node.get("name"), "type": ntype, "node_ref": ref,
                          "position": pos, "streaming_ref_point": _vec(node.get("streamingRefPoint")),
                          "primary_range": node.get("primaryRange"), "secondary_range": node.get("secondaryRange"),
                          "variant": _variant_for(ni, raw), "references": sorted(refs), "flags": []})
    by_sector = {s["name"]: s for s in sectors}

    # Devices and persistent IDs are keyed by hash; place them on nodes by position.
    device_rows = []
    for key, device in devices.items():
        if not isinstance(device, dict):
            continue
        point = _vec(device.get("nodePosition"))
        node = None
        if point is not None:
            near = [n for n in nodes if n["position"] and _dist(n["position"], point) <= DEVICE_MATCH_DISTANCE]
            node = near[0] if len(near) == 1 else None
        ps = ps_entries.get(str(key)) if isinstance(ps_entries.get(str(key)), dict) else None
        row = {"hash": str(key), "class": device.get("className"), "sector": node["sector"] if node else None,
               "node_ref": node["node_ref"] if node else None, "psid": ps.get("PSID") if ps else None,
               "children": [str(c) for c in device.get("children") or []], "parents": [str(p) for p in device.get("parents") or []]}
        device_rows.append(row)
        if node:
            node["device_hash"] = str(key)
            node["psid"] = row["psid"]
            by_sector[node["sector"]]["devices"] += 1
            if ps:
                by_sector[node["sector"]]["ps_entries"] += 1
    devices_by_hash = {d["hash"]: d for d in device_rows}
    psid_seen: dict[str, list[str]] = {}
    for key, ps in ps_entries.items():
        if isinstance(ps, dict) and ps.get("PSID") is not None:
            psid_seen.setdefault(str(ps.get("PSID")), []).append(str(key))

    # Sector centroids and spread for outlier detection.
    centroids: dict[str, dict[str, float]] = {}
    spread: dict[str, float] = {}
    for s in sectors:
        points = [n["position"] for n in nodes if n["sector"] == s["name"] and n["position"]]
        if points:
            c = {k: sum(p[k] for p in points) / len(points) for k in "xyz"}
            centroids[s["name"]] = c
            dists = sorted(_dist(p, c) for p in points)
            spread[s["name"]] = dists[min(len(dists) - 1, int(0.9 * (len(dists) - 1)))] if len(dists) > 1 else 0.0

    flags: list[dict[str, Any]] = []

    def flag(node: dict[str, Any], code: str, severity: str, message: str, **extra: Any) -> None:
        item = {"code": code, "severity": severity, "message": message, "sector": node["sector"], "node_index": node["index"],
                "node_name": node["name"], "node_ref": node["node_ref"], "node_type": node["type"], **extra}
        node["flags"].append(code)
        flags.append(item)

    for node in nodes:
        own = by_sector[node["sector"]]
        pos = node["position"]
        if pos is None:
            flag(node, "missing_position", "error", "Node has no valid position; its sector cannot be checked.")
            continue
        b = own["bounds"]
        inside_own = _inside(pos, b["min"], b["max"], BOUNDS_TOLERANCE) if b else None
        containing = [s["name"] for s in sectors if s["name"] != own["name"] and s["bounds"]
                      and _inside(pos, s["bounds"]["min"], s["bounds"]["max"], 0.0)]
        if inside_own is False:
            by = _outside_by(pos, b["min"], b["max"])
            if containing:
                flag(node, "outside_sector_inside_other", "error",
                     f"Node lies {by:.1f} m outside its sector bounds and inside {', '.join(containing)}; it is likely in the wrong sector.",
                     suggested_sector=containing[0], outside_by=round(by, 2))
            else:
                flag(node, "outside_sector_bounds", "warning",
                     f"Node lies {by:.1f} m outside its sector bounds; the sector may not stream it where expected.",
                     outside_by=round(by, 2))
        ref_point = node["streaming_ref_point"]
        if ref_point and b and _inside(ref_point, b["min"], b["max"], BOUNDS_TOLERANCE) is False:
            flag(node, "streaming_ref_outside_sector", "warning", "The node's streaming reference point lies outside its sector bounds.")
        c = centroids.get(own["name"])
        if c and own["node_count"] >= 4:
            d = _dist(pos, c)
            limit = max(OUTLIER_MIN_DISTANCE, OUTLIER_FACTOR * spread.get(own["name"], 0.0))
            if d > limit:
                nearest = min(centroids, key=lambda name: _dist(pos, centroids[name]))
                extra = {"distance_from_centroid": round(d, 1), "outlier_limit": round(limit, 1)}
                if nearest != own["name"]:
                    extra["suggested_sector"] = nearest
                if "outside_sector_inside_other" not in node["flags"]:
                    flag(node, "sector_outlier", "warning",
                         f"Node is {d:.0f} m from the rest of its sector (limit {limit:.0f} m)"
                         + (f"; nearest sector by content is {nearest}." if nearest != own["name"] else "."), **extra)
        rng = node["secondary_range"]
        if isinstance(rng, (int, float)) and rng > 0 and c and _dist(pos, c) > rng and "sector_outlier" not in node["flags"]:
            flag(node, "beyond_streaming_range", "info",
                 f"Node is {_dist(pos, c):.0f} m from its sector centroid, beyond its {rng:.0f} m streaming range.")

    # Cross-sector references: NodeRefs in node data and device links.
    cross_refs: list[dict[str, Any]] = []
    for node in nodes:
        for ref in node["references"]:
            target = ref_owner.get(ref)
            if target is None:
                cross_refs.append({"kind": "node_ref", "from_sector": node["sector"], "from_node_ref": node["node_ref"],
                                   "from_node": node["name"], "target_ref": ref, "target_sector": None, "status": "external_or_missing"})
            elif target != node["sector"]:
                cross_refs.append({"kind": "node_ref", "from_sector": node["sector"], "from_node_ref": node["node_ref"],
                                   "from_node": node["name"], "target_ref": ref, "target_sector": target, "status": "cross_sector"})
    for dev in device_rows:
        for child in dev["children"]:
            other = devices_by_hash.get(child)
            if other is None:
                cross_refs.append({"kind": "device_link", "from_device": dev["hash"], "to_device": child, "from_sector": dev["sector"],
                                   "target_sector": None, "status": "missing_device"})
            elif dev["sector"] and other["sector"] and dev["sector"] != other["sector"]:
                cross_refs.append({"kind": "device_link", "from_device": dev["hash"], "to_device": child, "from_sector": dev["sector"],
                                   "target_sector": other["sector"], "status": "cross_sector"})
        if dev["sector"] is None:
            flags.append({"code": "device_without_node", "severity": "warning", "sector": None, "device_hash": dev["hash"],
                          "message": "Device record matches no single exported node position; its sector cannot be determined."})

    for psid, keys in psid_seen.items():
        if len(keys) > 1:
            flags.append({"code": "duplicate_psid", "severity": "error", "sector": None, "psid": psid, "ps_entries": keys,
                          "message": f"PSID {psid} is used by {len(keys)} persistent-state entries."})

    # Map nodes back to LocationStudio objects (position + name).
    for node in nodes:
        if not node["position"] or not objects:
            continue
        near = [o for o in objects if _dist(o["position"], node["position"]) <= OBJECT_MATCH_DISTANCE]
        named = [o for o in near if o["name"] and node["name"] and o["name"] in str(node["name"])]
        match = named[0] if len(named) == 1 else near[0] if len(near) == 1 else None
        if match:
            node["object_id"] = match["id"]
            node["premise_id"] = match["premise_id"]
    for item in flags:
        if "node_index" in item:
            node = next(n for n in nodes if n["sector"] == item["sector"] and n["index"] == item["node_index"])
            if node.get("object_id"):
                item["object_id"] = node["object_id"]
    premises: dict[str, set[str]] = {}
    for node in nodes:
        if node.get("premise_id"):
            premises.setdefault(node["premise_id"], set()).add(node["sector"])
    split = [{"premise_id": pid, "sectors": sorted(names)} for pid, names in premises.items() if len(names) > 1]

    order = {"error": 0, "warning": 1, "info": 2}
    flags.sort(key=lambda f: (order.get(f["severity"], 3), str(f.get("sector")), f.get("node_index", -1)))
    counts = {level: sum(1 for f in flags if f["severity"] == level) for level in ("error", "warning", "info")}
    report: dict[str, Any] = {
        "schema": SCHEMA, "export": str(export_path), "export_name": data.get("name"),
        "sector_count": len(sectors), "node_count": len(nodes), "device_count": len(device_rows), "ps_entry_count": len(ps_entries),
        "sectors": sectors, "flags": flags, "flag_counts": counts,
        "likely_wrong_sector": [f for f in flags if f["code"] in {"outside_sector_inside_other", "sector_outlier"}],
        "cross_sector_references": cross_refs, "devices": device_rows, "premises_split_across_sectors": split,
        "matched_objects": sum(1 for n in nodes if n.get("object_id")),
        "thresholds": {"bounds_tolerance_m": BOUNDS_TOLERANCE, "outlier_min_distance_m": OUTLIER_MIN_DISTANCE,
                       "outlier_factor": OUTLIER_FACTOR},
        "note": "Heuristics flag likely mistakes; a cross-sector reference is valid when both sectors stream together.",
    }
    if include_nodes:
        report["nodes"] = [n for n in nodes if sector is None or n["sector"] == sector]
    if output is not None:
        target = Path(output)
        target.parent.mkdir(parents=True, exist_ok=True)
        full = dict(report)
        full["nodes"] = nodes
        target.write_text(json.dumps(full, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        report["report_file"] = str(target)
    return report
