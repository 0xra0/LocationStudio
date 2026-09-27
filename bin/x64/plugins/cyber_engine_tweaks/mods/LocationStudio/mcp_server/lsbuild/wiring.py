"""Validated edits to the World Builder export's native device graph."""
from __future__ import annotations

import json
import copy
import math
import os
import tempfile
from pathlib import Path
from typing import Any


def _device(data: dict[str, Any], key: str) -> dict[str, Any]:
    devices = data.get("devices")
    if not isinstance(devices, dict) or key not in devices:
        raise ValueError(f"Device hash {key!r} was not found in export.devices")
    item = devices[key]
    if not isinstance(item, dict):
        raise ValueError(f"Device {key!r} is malformed")
    for field in ("children", "parents"):
        if not isinstance(item.get(field), list):
            raise ValueError(f"Device {key!r} has no valid {field} array")
    return item


def _link(data: dict[str, Any], source: str, target: str) -> bool:
    if source == target:
        raise ValueError("A device cannot connect to itself")
    a, b = _device(data, source), _device(data, target)
    if not a.get("className") or not b.get("className"):
        raise ValueError("Both devices must have a World Builder device className")
    changed = False
    # These are the arrays serialized by World Builder into gameDeviceResourceData.
    if target not in [str(v) for v in a["children"]]:
        a["children"].append(target)
        changed = True
    if source not in [str(v) for v in b["parents"]]:
        b["parents"].append(source)
        changed = True
    return changed


def _edit(path: str | Path, edit) -> dict[str, Any]:
    p = Path(path).expanduser().resolve()
    if not p.is_file():
        raise FileNotFoundError(p)
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Expected a World Builder export object")
    if data.get("devices") is None:
        data["devices"] = {}
    if not isinstance(data.get("devices"), dict):
        raise ValueError("World Builder export devices must be an object")
    if data.get("psEntries") is None:
        data["psEntries"] = {}
    if not isinstance(data.get("psEntries"), dict):
        raise ValueError("World Builder export psEntries must be an object")
    result = edit(data)
    encoded = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    fd, temp_name = tempfile.mkstemp(prefix=p.name + ".", suffix=".tmp", dir=str(p.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, p)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
    return {"file": str(p), "changed": result, "device_count": len(data["devices"])}


def connect(path: str | Path, source_hash: str, target_hash: str) -> dict[str, Any]:
    source_hash, target_hash = str(source_hash).strip(), str(target_hash).strip()
    if not source_hash or not target_hash:
        raise ValueError("source_hash and target_hash are required")
    result = _edit(path, lambda data: _link(data, source_hash, target_hash))
    result.update({"source_hash": source_hash, "target_hash": target_hash,
                   "relation": "source.children += target; target.parents += source"})
    return result


def elevator(path: str | Path, elevator_hash: str, floor_terminal_hashes: list[str]) -> dict[str, Any]:
    elevator_hash = str(elevator_hash).strip()
    floors = [str(value).strip() for value in floor_terminal_hashes]
    if not elevator_hash or len(floors) < 2 or any(not value for value in floors):
        raise ValueError("Provide an elevator hash and at least two ordered floor terminal hashes")
    if len(set(floors)) != len(floors) or elevator_hash in floors:
        raise ValueError("Elevator and floor terminal hashes must be unique")

    def apply(data: dict[str, Any]) -> bool:
        lift = _device(data, elevator_hash)
        if "LiftControllerPS" not in str(lift.get("className", "")):
            raise ValueError(f"Device {elevator_hash!r} is not class LiftControllerPS")
        # Validate every floor before mutating any record. Input order is gameplay order.
        for terminal_hash in floors:
            terminal = _device(data, terminal_hash)
            if "ElevatorFloorTerminalControllerPS" not in str(terminal.get("className", "")):
                raise ValueError(f"Device {terminal_hash!r} is not class ElevatorFloorTerminalControllerPS")
        old_children = [str(value) for value in lift["children"]]
        for old_hash in old_children:
            if old_hash not in data["devices"]:
                raise ValueError(f"Existing elevator child hash {old_hash!r} is missing from export.devices")
        changed = False
        # Elevator configuration is an ordered floor list: replace the prior list
        # and remove its reciprocal parent entries before adding the requested floors.
        for old_hash in old_children:
            old = _device(data, old_hash)
            old_parents = [str(value) for value in old["parents"]]
            if elevator_hash in old_parents and old_hash not in floors:
                old["parents"] = [value for value in old["parents"] if str(value) != elevator_hash]
                changed = True
        if old_children != floors:
            lift["children"] = []
            changed = True
        for terminal_hash in floors:
            changed |= _link(data, elevator_hash, terminal_hash)
        return changed

    result = _edit(path, apply)
    result.update({"elevator_hash": elevator_hash, "ordered_floor_terminal_hashes": floors,
                   "order_note": "first item must be the lowest floor",
                   "scope": "device graph only; floor NodeRefs, markers and persistent instance data remain World Builder setup"})
    return result


def apply_logic_graph(path: str | Path, graph: dict[str, Any]) -> dict[str, Any]:
    """Create missing typed WB records, then apply device-to-device graph edges.

    Fact/action links remain in the semantic graph. Missing device/PS instance records are
    reported; this routine copies caller-supplied class-specific instance data rather than
    synthesizing payloads from incomplete metadata.
    """
    p = Path(path).expanduser().resolve()
    if not p.is_file():
        raise FileNotFoundError(p)
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Expected a World Builder export object")
    if data.get("devices") is None:
        data["devices"] = {}
    if not isinstance(data.get("devices"), dict):
        raise ValueError("World Builder export devices must be an object")
    if data.get("psEntries") is None:
        data["psEntries"] = {}
    if not isinstance(data.get("psEntries"), dict):
        raise ValueError("World Builder export psEntries must be an object")
    nodes, links = graph.get("nodes"), graph.get("links")
    if not isinstance(nodes, list) or not isinstance(links, list):
        raise ValueError("Device logic graph must contain nodes[] and links[]")
    by_id: dict[str, dict[str, Any]] = {}
    for node in nodes:
        if not isinstance(node, dict) or not isinstance(node.get("id"), str) or node["id"] in by_id:
            raise ValueError("Graph nodes require unique string IDs")
        by_id[node["id"]] = node
    proposed = copy.deepcopy(data)
    missing: list[dict[str, str]] = []
    bound: dict[str, dict[str, Any]] = {}
    ps_entries = proposed["psEntries"]
    new_devices, new_ps_entries, new_world_nodes = 0, 0, 0
    sectors = proposed.get("sectors") if isinstance(proposed.get("sectors"), list) else []
    world_refs = {str(node.get("nodeRef")) for sector in sectors if isinstance(sector, dict)
                  for node in sector.get("nodes", []) if isinstance(node, dict) and node.get("nodeRef")}
    for node in nodes:
        if node.get("kind") in {"fact", "action"}:
            continue
        native = node.get("native") if isinstance(node.get("native"), dict) else {}
        device_hash = str(native.get("device_hash") or "")
        if not device_hash:
            missing.append({"node_id": node["id"], "resource": "device_hash", "reason": "No World Builder device hash binding"})
            continue
        device = proposed["devices"].get(device_hash)
        if not isinstance(device, dict):
            record = native.get("device_record") if isinstance(native.get("device_record"), dict) else None
            point = record.get("nodePosition") if record else None
            valid_point = isinstance(point, dict) and all(isinstance(point.get(axis), (int, float)) and math.isfinite(point[axis]) for axis in ("x", "y", "z"))
            if (not record or str(record.get("hash")) != device_hash or not record.get("className") or not valid_point
                    or not isinstance(record.get("children"), list) or not isinstance(record.get("parents"), list)):
                missing.append({"node_id": node["id"], "resource": "devices", "reason": f"Device {device_hash!r} is absent; native.device_record must supply hash/className/nodePosition/children/parents"})
                continue
            device = copy.deepcopy(record)
            proposed["devices"][device_hash] = device
            new_devices += 1
        expected_class = str(native.get("device_class") or "")
        if expected_class and expected_class not in str(device.get("className") or ""):
            missing.append({"node_id": node["id"], "resource": "device_class", "reason": f"Expected {expected_class!r}; export has {device.get('className')!r}"})
        ps_hash = str(native.get("ps_entry_hash") or "")
        ps_entry = ps_entries.get(ps_hash) if ps_hash else None
        if not isinstance(ps_entry, dict) or not ps_entry.get("PSID") or not isinstance(ps_entry.get("instanceData"), dict):
            candidate = native.get("ps_entry") if isinstance(native.get("ps_entry"), dict) else None
            psid_used = candidate and any(isinstance(entry, dict) and entry.get("PSID") == candidate.get("PSID") for key, entry in ps_entries.items() if key != ps_hash)
            if ps_hash and ps_hash not in ps_entries and candidate and candidate.get("PSID") and isinstance(candidate.get("instanceData"), dict) and not psid_used:
                ps_entries[ps_hash] = copy.deepcopy(candidate)
                new_ps_entries += 1
            else:
                missing.append({"node_id": node["id"], "resource": "persistent_state_instance", "reason": f"Missing/invalid PSID/instanceData for ps_entry_hash {ps_hash!r}; a new entry requires a unique PSID and typed instanceData object"})
        node_ref = str(native.get("node_ref") or "")
        if not node_ref or node_ref not in world_refs:
            world_node = native.get("world_node") if isinstance(native.get("world_node"), dict) else None
            sector_name = str(native.get("sector_name") or "")
            sector = next((s for s in sectors if isinstance(s, dict) and s.get("name") == sector_name), None)
            position = world_node.get("position") if world_node else None
            valid_position = isinstance(position, dict) and all(isinstance(position.get(axis), (int, float)) and math.isfinite(position[axis]) for axis in ("x", "y", "z"))
            rotation = world_node.get("rotation") if world_node else None
            scale = world_node.get("scale") if world_node else None
            valid_rotation = isinstance(rotation, dict) and all(isinstance(rotation.get(axis), (int, float)) and not isinstance(rotation.get(axis), bool) and math.isfinite(rotation[axis]) for axis in ("i", "j", "k", "r"))
            valid_scale = isinstance(scale, dict) and all(isinstance(scale.get(axis), (int, float)) and not isinstance(scale.get(axis), bool) and math.isfinite(scale[axis]) for axis in ("x", "y", "z"))
            valid_node = (world_node and world_node.get("type") == "worldDeviceNode" and world_node.get("nodeRef") == node_ref
                          and isinstance(world_node.get("name"), str) and valid_position and valid_rotation and valid_scale
                          and isinstance(world_node.get("data"), dict) and bool(world_node.get("data")))
            if sector and valid_node and node_ref and node_ref not in world_refs:
                sector.setdefault("nodes", []).append(copy.deepcopy(world_node))
                world_refs.add(node_ref)
                new_world_nodes += 1
                bounds_min, bounds_max = sector.get("min"), sector.get("max")
                if isinstance(bounds_min, dict) and isinstance(bounds_max, dict):
                    for axis in ("x", "y", "z"):
                        bounds_min[axis] = min(float(bounds_min.get(axis, position[axis])), position[axis])
                        bounds_max[axis] = max(float(bounds_max.get(axis, position[axis])), position[axis])
            else:
                missing.append({"node_id": node["id"], "resource": "sector_node_ref", "reason": f"World NodeRef {node_ref!r} is absent; provide sector_name and a complete typed worldDeviceNode payload for an existing sector"})
        bound[node["id"]] = {"hash": device_hash, "device": device, "node": node}
    native_edges, semantic_edges = [], []
    for link in links:
        if not isinstance(link, dict) or link.get("from_id") not in by_id or link.get("to_id") not in by_id:
            raise ValueError("Every link must reference graph node IDs")
        a, b = by_id[link["from_id"]], by_id[link["to_id"]]
        if a.get("kind") in {"fact", "action"} or b.get("kind") in {"fact", "action"}:
            semantic_edges.append(link)
        else:
            native_edges.append(link)
    if missing:
        return {"file": str(p), "written": False, "ready": False, "missing_resources": missing,
                "device_edge_count": len(native_edges), "semantic_edge_count": len(semantic_edges),
                "proposed_device_records": new_devices, "proposed_ps_entries": new_ps_entries, "proposed_world_nodes": new_world_nodes,
                "note": "No file changes were made. Supply complete class-compatible typed payloads for every listed missing native resource."}

    def apply(export: dict[str, Any]) -> dict[str, Any]:
        export.clear()
        export.update(copy.deepcopy(proposed))
        changed_edges = []
        ordered_edges = sorted(native_edges, key=lambda v: (int(v.get("order", 0)), str(v.get("id", ""))))
        elevator_groups: dict[str, list[dict[str, Any]]] = {}
        for link in ordered_edges:
            if by_id[link["from_id"]].get("kind") == "elevator":
                elevator_groups.setdefault(link["from_id"], []).append(link)
        elevator_link_ids = {link.get("id", "") for group in elevator_groups.values() for link in group}
        for node_id, floors in elevator_groups.items():
            source = bound[node_id]
            if "LiftControllerPS" not in str(source["device"].get("className", "")):
                raise ValueError(f"Elevator node {source['node']['name']!r} must bind to LiftControllerPS")
            if len(floors) < 2:
                raise ValueError(f"Elevator node {source['node']['name']!r} needs at least two ordered floor terminals")
            target_hashes = [bound[link["to_id"]]["hash"] for link in floors]
            if len(set(target_hashes)) != len(target_hashes):
                raise ValueError(f"Elevator node {source['node']['name']!r} repeats a floor terminal")
            for link in floors:
                target = bound[link["to_id"]]
                if "ElevatorFloorTerminalControllerPS" not in str(target["device"].get("className", "")):
                    raise ValueError(f"Elevator destination {target['node']['name']!r} must bind to ElevatorFloorTerminalControllerPS")
            lift = _device(export, source["hash"])
            old_children = [str(value) for value in lift["children"]]
            for old_hash in old_children:
                if old_hash not in export["devices"]:
                    raise ValueError(f"Existing elevator child hash {old_hash!r} is missing from export.devices")
            for old_hash in old_children:
                if old_hash not in target_hashes:
                    old = _device(export, old_hash)
                    old["parents"] = [value for value in old["parents"] if str(value) != source["hash"]]
            lift["children"] = []
            for link in floors:
                target = bound[link["to_id"]]
                _link(export, source["hash"], target["hash"])
                changed_edges.append(link.get("id", ""))
        for link in ordered_edges:
            if link.get("id", "") in elevator_link_ids:
                continue
            source, target = bound[link["from_id"]], bound[link["to_id"]]
            if _link(export, source["hash"], target["hash"]):
                changed_edges.append(link.get("id", ""))
        return {"graph_id": graph.get("id"), "changed_edges": changed_edges,
                "device_edge_count": len(native_edges), "semantic_edge_count": len(semantic_edges),
                "device_count": len(export["devices"]), "persistent_state_count": len(export.get("psEntries", {})),
                "created_device_records": new_devices, "created_ps_entries": new_ps_entries, "created_world_nodes": new_world_nodes}

    result = _edit(p, apply)
    details = result.pop("changed")
    if isinstance(details, dict):
        result.update(details)
    result.update({"written": True, "ready": True, "missing_resources": [],
                   "note": "Supplied typed records were added to the World Builder export where needed, then graph links were applied. Fact/action semantics remain handoff data; class-specific payload validity still depends on the source presets and in-game build verification."})
    return result
