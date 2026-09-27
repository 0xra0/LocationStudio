"""NPC population native export audit tests."""
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from lsbuild.population import audit


def _fixture(root: Path, *, record: str = "Character.test_npc", appearance: str = "street") -> tuple[Path, Path]:
    project = root / "project.json"
    export = root / "wb-export.json"
    project.write_text(json.dumps({"objects": [{"id": "pop-1", "name": "Clinic guard", "transform": {"position": {"x": 4, "y": 5, "z": 6}},
        "metadata": {"npc_population": {"record": "Character.test_npc", "appearance": "street", "spawn_on_start": True,
            "always_spawned": False, "attitude": "hostile", "faction": "clinic", "level": 10,
            "archetype": "guard", "idle_behavior": "patrol", "despawn_distance": 80,
            "conditions": [{"fact_name": "clinic_alarm", "fact_value": 1}]}}}]}), encoding="utf-8")
    export.write_text(json.dumps({"sectors": [{"nodes": [{"type": "worldPopulationSpawnerNode", "position": {"x": 4, "y": 5, "z": 6},
        "data": {"objectRecordId": {"$storage": "string", "$value": record},
                 "appearanceName": {"$storage": "string", "$value": appearance}, "spawnOnStart": 1,
                 "alwaysSpawned": "false_"}, "primaryRange": 100, "secondaryRange": 120}]}]}), encoding="utf-8")
    return project, export


def test_native_population_node_matches_project() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        project, export = _fixture(Path(tmp))
        report = audit(project, export)
        assert report["ready"] and report["matched"] == 1
        assert report["matched_points"][0]["native_node_type"] == "worldPopulationSpawnerNode"
        assert report["matched_points"][0]["conditions"][0]["fact_name"] == "clinic_alarm"
        assert report["matched_points"][0]["profile_fields_status"] == "handoff_only"


def test_native_record_mismatch_fails_audit() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        project, export = _fixture(Path(tmp), record="Character.other")
        report = audit(project, export)
        assert report["ready"] is False
        assert "no worldPopulationSpawnerNode matched" in report["issues"][0]["error"]


if __name__ == "__main__":
    test_native_population_node_matches_project()
    test_native_record_mismatch_fails_audit()
    print("PASS NPC population pipeline")
