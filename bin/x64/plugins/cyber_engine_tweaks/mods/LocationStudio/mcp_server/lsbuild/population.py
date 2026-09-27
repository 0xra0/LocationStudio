"""Audit LocationStudio population points against World Builder native exports."""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any


def _nodes(export: dict[str, Any]) -> list[dict[str, Any]]:
    return [n for s in export.get("sectors", []) if isinstance(s, dict)
            for n in s.get("nodes", []) if isinstance(n, dict)]


def audit(project_file: str | Path, export_file: str | Path, output: str | Path | None = None) -> dict[str, Any]:
    project = json.loads(Path(project_file).read_text(encoding="utf-8"))
    export = json.loads(Path(export_file).read_text(encoding="utf-8"))
    populations = []
    for obj in project.get("objects", []):
        cfg = (obj.get("metadata") or {}).get("npc_population") if isinstance(obj, dict) else None
        if isinstance(cfg, dict) and obj.get("enabled") is not False:
            populations.append({"id": obj.get("id"), "name": obj.get("name"), "object": obj, "config": cfg})
    all_nodes = _nodes(export)
    remaining = [n for n in all_nodes if n.get("type") == "worldPopulationSpawnerNode"]
    issues: list[dict[str, str]] = []
    matched = []
    for row in populations:
        obj, cfg = row["object"], row["config"]
        record = str(cfg.get("record") or "")
        pos = ((obj.get("transform") or {}).get("position") or {})
        def candidate(node: dict[str, Any]) -> tuple[float, bool]:
            d = node.get("data") or {}
            rec = ((d.get("objectRecordId") or {}).get("$value"))
            npos = node.get("position") or {}
            dist = math.sqrt(sum((float(npos.get(k, 0) or 0) - float(pos.get(k, 0) or 0)) ** 2 for k in "xyz"))
            return dist, rec == record
        ranked = sorted(((candidate(n), i, n) for i, n in enumerate(remaining)), key=lambda x: (not x[0][1], x[0][0]))
        found = next((entry for entry in ranked if entry[0][1] and entry[0][0] <= 0.1), None)
        if not found:
            issues.append({"id": str(row["id"]), "error": f"no worldPopulationSpawnerNode matched Character record {record!r} at the saved position"})
            continue
        (_, index, node) = found
        remaining.pop(index)
        data = node.get("data") or {}
        app = ((data.get("appearanceName") or {}).get("$value"))
        expected_app = str(cfg.get("appearance") or "")
        start = data.get("spawnOnStart")
        always = data.get("alwaysSpawned")
        if expected_app and str(app or "") != expected_app:
            issues.append({"id": str(row["id"]), "error": f"native appearance {app!r} does not match authored {expected_app!r}"})
        if int(start or 0) != (1 if cfg.get("spawn_on_start", True) else 0):
            issues.append({"id": str(row["id"]), "error": "native spawnOnStart does not match authored setting"})
        if str(always) != ("true_" if cfg.get("always_spawned") else "false_"):
            issues.append({"id": str(row["id"]), "error": "native alwaysSpawned does not match authored setting"})
        for key in ("primary_range", "secondary_range"):
            actual = node.get("primaryRange" if key == "primary_range" else "secondaryRange")
            expected = cfg.get(key)
            if expected is not None and (actual is None or abs(float(actual) - float(expected)) > 0.01):
                issues.append({"id": str(row["id"]), "error": f"native {key} does not match authored setting"})
        matched.append({"id": row["id"], "name": row["name"], "record": record,
                        "appearance": app or expected_app, "native_node_type": node.get("type"),
                        "native_primary_range": node.get("primaryRange"), "native_secondary_range": node.get("secondaryRange"),
                        "native_spawn_on_start": start, "native_always_spawned": always,
                        "attitude": cfg.get("attitude", ""), "faction": cfg.get("faction", ""),
                        "level": cfg.get("level", 0), "archetype": cfg.get("archetype", ""),
                        "idle_behavior": cfg.get("idle_behavior", ""),
                        "despawn_distance": cfg.get("despawn_distance", 0),
                        "conditions": cfg.get("conditions", []),
                        "profile_fields_status": "handoff_only"})
    report = {"schema": "locationstudio-npc-population-audit/1", "export": str(Path(export_file)),
              "population_points": len(populations), "native_population_nodes": len(remaining) + len(matched),
              "matched": len(matched), "ready": not issues, "matched_points": matched, "issues": issues,
              "handoff_only_fields": ["attitude", "faction", "level", "archetype", "idle_behavior", "despawn_distance", "conditions"],
              "note": "Entity Record exports produce persistent worldPopulationSpawnerNode data. WB does not encode the handoff-only profile fields as node properties; faction/AI/quest behavior must be supplied by compatible Character/community/quest resources."}
    if output is not None:
        target = Path(output)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        report["report_file"] = str(target)
    return report
