"""Tests for generated TweakXL/native interactable build artifacts."""
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from lsbuild.interactables import generate


def test_loot_table_generation_and_native_manifest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        project = root / "project.json"
        export = root / "export.json"
        project.write_text(json.dumps({"objects": [{"id": "case1", "name": "Case", "metadata": {"interactable": {
            "kind": "loot_container", "loot_table": "LootTables.Test_Case", "loot_items": [
                {"item_record": "Items.money", "count_min": 2, "count_max": 4, "drop_chance": 0.5}]}}}]}))
        export.write_text(json.dumps({"sectors": [{"nodes": [{"type": "worldEntityNode"}]}],
                                      "devices": {"1": {}}, "psEntries": {"2": {}}}))
        result = generate(project, export, root / "out")
        assert result["ready"] is True
        assert result["native_export"] == {"sectors": 1, "nodes": 1, "devices": 1, "persistent_states": 1}
        yaml = Path(result["loot_yaml"]).read_text()
        assert "gamedataLootTable_Record" in yaml
        assert "itemID: Items.money" in yaml
        assert "dropCountMin: 2" in yaml and "dropCountMax: 4" in yaml


def test_empty_container_refuses_fake_empty_loot_table() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        project = root / "project.json"
        export = root / "export.json"
        project.write_text(json.dumps({"objects": [{"id": "case1", "metadata": {"interactable": {
            "kind": "loot_container", "loot_table": "LootTables.Test_Case", "loot_items": []}}}]}))
        export.write_text(json.dumps({"sectors": [{"nodes": []}]}))
        result = generate(project, export, root / "out")
        assert result["ready"] is False
        assert "no loot_items" in result["issues"][0]["error"]


def test_device_logic_audits_existing_native_resources_and_links() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        project, export = root / "project.json", root / "export.json"
        project.write_text(json.dumps({"objects": [], "device_logic_graphs": [{"id": "logic", "name": "Clinic",
            "nodes": [
                {"id": "door", "name": "Door", "kind": "door", "native": {"device_hash": "1", "device_class": "DoorControllerPS", "ps_entry_hash": "ps1", "instance_data_ref": "door-v1", "node_ref": "door_ref"}},
                {"id": "panel", "name": "Panel", "kind": "terminal", "native": {"device_hash": "2", "device_class": "TerminalPS", "ps_entry_hash": "ps2", "instance_data_ref": "terminal-v1", "node_ref": "panel_ref"}},
                {"id": "action", "name": "Unlock", "kind": "action", "config": {"operation": "unlock"}},
            ], "links": [
                {"id": "device-wire", "from_id": "panel", "to_id": "door"},
                {"id": "semantic-wire", "from_id": "panel", "to_id": "action"},
            ]}]}))
        export.write_text(json.dumps({"sectors": [{"nodes": [{"nodeRef": "door_ref"}, {"nodeRef": "panel_ref"}]}],
            "devices": {
                "1": {"className": "DoorControllerPS", "children": [], "parents": ["2"]},
                "2": {"className": "TerminalPS", "children": ["1"], "parents": []},
            }, "psEntries": {
                "ps1": {"PSID": "ps1", "instanceData": {"$type": "DoorInstance"}},
                "ps2": {"PSID": "ps2", "instanceData": {"$type": "TerminalInstance"}},
            }}))
        result = generate(project, export, root / "out")
        assert result["ready"] is True
        manifest = json.loads(Path(result["manifest"]).read_text())
        assert manifest["device_logic_graphs"][0]["device_edges"] == 1
        assert manifest["device_logic_graphs"][0]["semantic_fact_action_edges"] == 1
        assert manifest["device_logic_graphs"][0]["device_links_ready"] is True


def test_device_logic_missing_ps_instance_blocks_ready() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        project, export = root / "project.json", root / "export.json"
        project.write_text(json.dumps({"objects": [], "device_logic_graphs": [{"id": "logic", "name": "Broken graph",
            "nodes": [{"id": "door", "name": "Door", "kind": "door", "native": {"device_hash": "1", "ps_entry_hash": "missing", "node_ref": "ref"}}], "links": []}]}))
        export.write_text(json.dumps({"sectors": [{"nodes": [{"nodeRef": "ref"}]}], "devices": {"1": {"className": "DoorPS", "children": [], "parents": []}}, "psEntries": {}}))
        result = generate(project, export, root / "out")
        assert result["ready"] is False
        assert any("persistent-state PSID/instanceData" in issue["error"] for issue in result["issues"])


if __name__ == "__main__":
    test_loot_table_generation_and_native_manifest()
    test_empty_container_refuses_fake_empty_loot_table()
    test_device_logic_audits_existing_native_resources_and_links()
    test_device_logic_missing_ps_instance_blocks_ready()
    print("PASS interactable build pipeline")
