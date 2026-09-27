"""Build-time interactable artifacts from LocationStudio's semantic handoff.

Loot-table records are generated from explicit item rows. Native entity/PS
and device graphs are intentionally taken from World Builder's typed export;
we validate their presence instead of fabricating RED4 component payloads.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

_ITEM = re.compile(r"^Items\.[A-Za-z0-9_.-]+$")
_LOOT = re.compile(r"^LootTables\.[A-Za-z0-9_.-]+$")


def _yaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _rows(project: dict[str, Any]) -> list[dict[str, Any]]:
    objects = project.get("objects", [])
    if not isinstance(objects, list):
        raise ValueError("project.objects must be an array")
    result = []
    for obj in objects:
        meta = obj.get("metadata") if isinstance(obj, dict) else None
        cfg = meta.get("interactable") if isinstance(meta, dict) else None
        if isinstance(cfg, dict):
            result.append({"id": obj.get("id"), "name": obj.get("name"), "config": cfg})
    return result


def _device_logic(project: dict[str, Any], export: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, str]]]:
    graphs = project.get("device_logic_graphs", [])
    if not isinstance(graphs, list):
        return [], [{"graph": "", "error": "device_logic_graphs must be an array"}]
    devices = export.get("devices") if isinstance(export.get("devices"), dict) else {}
    ps_entries = export.get("psEntries") if isinstance(export.get("psEntries"), dict) else {}
    world_refs = {str(node.get("nodeRef")) for sector in export.get("sectors", []) if isinstance(sector, dict)
                  for node in sector.get("nodes", []) if isinstance(node, dict) and node.get("nodeRef")}
    out, issues = [], []
    for graph in graphs:
        if not isinstance(graph, dict):
            issues.append({"graph": "", "error": "device logic graph must be an object"})
            continue
        nodes = graph.get("nodes", []) if isinstance(graph.get("nodes"), list) else []
        links = graph.get("links", []) if isinstance(graph.get("links"), list) else []
        by_id = {str(node.get("id")): node for node in nodes if isinstance(node, dict) and node.get("id")}
        bound = {}
        for node in nodes:
            if not isinstance(node, dict) or node.get("kind") in {"fact", "action"}:
                continue
            native = node.get("native") if isinstance(node.get("native"), dict) else {}
            device_hash = str(native.get("device_hash") or "")
            device = devices.get(device_hash) if device_hash else None
            if not isinstance(device, dict):
                issues.append({"graph": str(graph.get("name", graph.get("id", ""))), "node": str(node.get("name", node.get("id", ""))), "error": "missing native World Builder device record"})
            else:
                bound[str(node.get("id"))] = device_hash
                expected = str(native.get("device_class") or "")
                if expected and expected not in str(device.get("className") or ""):
                    issues.append({"graph": str(graph.get("name", "")), "node": str(node.get("name", "")), "error": f"device class mismatch: expected {expected}"})
            ps_hash = str(native.get("ps_entry_hash") or "")
            ps = ps_entries.get(ps_hash) if ps_hash else None
            if not isinstance(ps, dict) or not ps.get("PSID") or not isinstance(ps.get("instanceData"), dict):
                issues.append({"graph": str(graph.get("name", "")), "node": str(node.get("name", "")), "error": "missing typed persistent-state PSID/instanceData entry"})
            node_ref = str(native.get("node_ref") or "")
            if not node_ref or node_ref not in world_refs:
                issues.append({"graph": str(graph.get("name", "")), "node": str(node.get("name", "")), "error": "missing sector world nodeRef/instance association"})
        native_edges, semantic_edges, missing_links = 0, 0, []
        elevator_floors: dict[str, list[str]] = {}
        for link in links:
            if not isinstance(link, dict):
                continue
            a, b = by_id.get(str(link.get("from_id"))), by_id.get(str(link.get("to_id")))
            if not a or not b:
                issues.append({"graph": str(graph.get("name", "")), "error": "graph link has a missing endpoint"})
                continue
            if a.get("kind") in {"fact", "action"} or b.get("kind") in {"fact", "action"}:
                semantic_edges += 1
                continue
            native_edges += 1
            ah, bh = bound.get(str(a.get("id"))), bound.get(str(b.get("id")))
            da, db = devices.get(ah, {}) if ah else {}, devices.get(bh, {}) if bh else {}
            if a.get("kind") == "elevator" and bh:
                elevator_floors.setdefault(ah or "", []).append(bh)
            if not (ah and bh and bh in [str(x) for x in da.get("children", [])] and ah in [str(x) for x in db.get("parents", [])]):
                missing_links.append(str(link.get("id", "")))
        for elevator_hash, expected_floors in elevator_floors.items():
            actual = [str(value) for value in devices.get(elevator_hash, {}).get("children", [])]
            if actual != expected_floors:
                issues.append({"graph": str(graph.get("name", "")), "node": elevator_hash, "error": "elevator floor terminals are not stored in graph order"})
        for link_id in missing_links:
            issues.append({"graph": str(graph.get("name", "")), "link": link_id, "error": "device graph link is not present reciprocally in exported device resources"})
        out.append({"id": graph.get("id"), "name": graph.get("name"), "nodes": len(nodes), "device_edges": native_edges,
                    "semantic_fact_action_edges": semantic_edges, "device_links_ready": not missing_links,
                    "native_execution": False, "source_status": "native-resource-audit"})
    return out, issues


def generate(project_file: str | Path, export_file: str | Path, output: str | Path) -> dict[str, Any]:
    """Write TweakXL loot records and an auditable native build manifest.

    Each loot item row is {item_record, count_min, count_max, drop_chance}.
    Export node/device/PS data is retained as the native source of truth.
    """
    project = json.loads(Path(project_file).read_text(encoding="utf-8"))
    export = json.loads(Path(export_file).read_text(encoding="utf-8"))
    rows = _rows(project)
    logic_graphs, logic_issues = _device_logic(project, export)
    out = Path(output)
    out.mkdir(parents=True, exist_ok=True)
    yaml_lines: list[str] = ["# Generated by LocationStudio. Edit source project metadata, then regenerate."]
    generated: list[str] = []
    issues: list[dict[str, str]] = []
    issues.extend({"object": item.get("node", item.get("link", item.get("graph", ""))), "error": item["error"]} for item in logic_issues)
    for row in rows:
        cfg = row["config"]
        kind = cfg.get("kind")
        if kind not in {"door", "loot_container", "shard", "item"}:
            issues.append({"object": str(row["id"]), "error": "unknown interactable kind"})
            continue
        if kind != "loot_container":
            continue
        record = str(cfg.get("loot_table") or "")
        if not _LOOT.fullmatch(record):
            issues.append({"object": str(row["id"]), "error": "loot_container has no valid LootTables.* record"})
            continue
        items = cfg.get("loot_items")
        if not isinstance(items, list) or not items:
            issues.append({"object": str(row["id"]), "error": f"{record} has no loot_items; refusing to emit an empty/fake loot table"})
            continue
        if record in generated:
            issues.append({"object": str(row["id"]), "error": f"duplicate loot record {record}"})
            continue
        normalized = []
        for idx, item in enumerate(items):
            if not isinstance(item, dict) or not _ITEM.fullmatch(str(item.get("item_record") or "")):
                issues.append({"object": str(row["id"]), "error": f"loot_items[{idx}] needs an Items.* item_record"})
                continue
            lo, hi = item.get("count_min", 1), item.get("count_max", 1)
            chance = item.get("drop_chance", 1)
            if not isinstance(lo, int) or isinstance(lo, bool) or not isinstance(hi, int) or isinstance(hi, bool) or lo < 1 or hi < lo:
                issues.append({"object": str(row["id"]), "error": f"loot_items[{idx}] count range must satisfy 1 <= count_min <= count_max"})
                continue
            if not isinstance(chance, (int, float)) or isinstance(chance, bool) or not 0 <= chance <= 1:
                issues.append({"object": str(row["id"]), "error": f"loot_items[{idx}] drop_chance must be from 0 to 1"})
                continue
            normalized.append((str(item["item_record"]), lo, hi, float(chance)))
        if not normalized:
            continue
        generated.append(record)
        yaml_lines.extend([
            f"{record}:", "  $type: gamedataLootTable_Record", "  lootGenerationType: dropChance", "  lootItems:",
        ])
        for item_record, lo, hi, chance in normalized:
            yaml_lines.extend([
                "  - $type: gamedataLootItem_Record",
                f"    dropChance: {chance:g}", f"    dropCountMax: {hi}", f"    dropCountMin: {lo}",
                f"    itemID: {item_record}",
            ])
        total = len(normalized)
        yaml_lines.extend([f"  maxItemsToLoot: {total}", f"  minItemsToLoot: {total}", ""])

    handoff_path = out / "interactables-native-manifest.json"
    nodes = [n for s in export.get("sectors", []) if isinstance(s, dict) for n in s.get("nodes", []) if isinstance(n, dict)]
    native = {
        "schema": "locationstudio-native-interactables/1",
        "export": str(Path(export_file)),
        "objects": [{"id": r["id"], "name": r["name"], **r["config"]} for r in rows],
        "device_logic_graphs": logic_graphs,
        "native_export": {"sectors": len(export.get("sectors", [])), "nodes": len(nodes),
                          "devices": len(export.get("devices", {})), "persistent_states": len(export.get("psEntries", {}))},
        "loot_records_generated": generated,
        "issues": issues,
        "native_note": "Sector, device and PS CR2W files are compiled from typed World Builder export data. The Device Logic audit checks existing device records, reciprocal links, nodeRefs and PSID/instanceData. It reports absent records but does not synthesize class-specific state. Fact/action semantic edges are handoff only. Entity .ent components and controller operations must be present in the selected game asset/profile.",
    }
    handoff_path.write_text(json.dumps(native, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    yaml_path = out / "locationstudio_interactables.yaml"
    if generated:
        yaml_path.write_text("\n".join(yaml_lines).rstrip() + "\n", encoding="utf-8")
    return {"manifest": str(handoff_path), "loot_yaml": str(yaml_path) if generated else None,
            "loot_records": generated, "interactables": len(rows), "native_export": native["native_export"], "issues": issues,
            "ready": not issues and (not rows or native["native_export"]["nodes"] > 0)}
