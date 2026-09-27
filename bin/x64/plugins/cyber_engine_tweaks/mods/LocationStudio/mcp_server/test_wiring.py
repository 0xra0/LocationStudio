from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from lsbuild import wiring


def fixture(path: Path) -> Path:
    path.write_text(json.dumps({
        "name": "wiring_test",
        "devices": {
            "lift": {"hash": "1", "className": "LiftControllerPS", "children": [], "parents": [], "nodePosition": {"x": 0, "y": 0, "z": 0}},
            "low": {"hash": "2", "className": "ElevatorFloorTerminalControllerPS", "children": [], "parents": [], "nodePosition": {"x": 0, "y": 0, "z": 0}},
            "high": {"hash": "3", "className": "ElevatorFloorTerminalControllerPS", "children": [], "parents": [], "nodePosition": {"x": 0, "y": 0, "z": 0}},
            "other": {"hash": "4", "className": "DoorControllerPS", "children": [], "parents": [], "nodePosition": {"x": 0, "y": 0, "z": 0}},
        },
    }), encoding="utf-8")
    return path


class DeviceWiringTests(unittest.TestCase):
    def test_connect_is_reciprocal_and_idempotent(self):
        with tempfile.TemporaryDirectory() as td:
            path = fixture(Path(td) / "world.json")
            first = wiring.connect(path, "other", "low")
            second = wiring.connect(path, "other", "low")
            saved = json.loads(path.read_text())["devices"]
            self.assertTrue(first["changed"])
            self.assertFalse(second["changed"])
            self.assertEqual(saved["other"]["children"], ["low"])
            self.assertEqual(saved["low"]["parents"], ["other"])

    def test_elevator_wiring_preserves_floor_order_and_checks_classes(self):
        with tempfile.TemporaryDirectory() as td:
            path = fixture(Path(td) / "world.json")
            result = wiring.elevator(path, "lift", ["low", "high"])
            devices = json.loads(path.read_text())["devices"]
            self.assertEqual(devices["lift"]["children"], ["low", "high"])
            self.assertEqual(devices["low"]["parents"], ["lift"])
            self.assertEqual(result["ordered_floor_terminal_hashes"], ["low", "high"])
            wiring.elevator(path, "lift", ["high", "low"])
            self.assertEqual(json.loads(path.read_text())["devices"]["lift"]["children"], ["high", "low"])

    def test_bad_device_or_role_does_not_partially_write(self):
        with tempfile.TemporaryDirectory() as td:
            path = fixture(Path(td) / "world.json")
            before = path.read_bytes()
            with self.assertRaisesRegex(ValueError, "not class"):
                wiring.elevator(path, "lift", ["low", "other"])
            self.assertEqual(path.read_bytes(), before)
            with self.assertRaisesRegex(ValueError, "not found"):
                wiring.connect(path, "missing", "low")

    def test_logic_graph_applies_device_links_when_native_records_exist(self):
        with tempfile.TemporaryDirectory() as td:
            path = fixture(Path(td) / "world.json")
            data = json.loads(path.read_text())
            data["psEntries"] = {key: {"PSID": key, "instanceData": {"$type": "TypedInstance"}} for key in ("ps-other", "ps-low")}
            data["sectors"] = [{"nodes": [{"nodeRef": "ref-door"}, {"nodeRef": "ref-panel"}]}]
            path.write_text(json.dumps(data), encoding="utf-8")
            graph = {"id": "logic-test", "nodes": [
                {"id": "door", "name": "Entry", "kind": "door", "native": {"device_hash": "other", "device_class": "DoorControllerPS", "ps_entry_hash": "ps-other", "instance_data_ref": "verified-door-preset", "node_ref": "ref-door"}},
                {"id": "terminal", "name": "Panel", "kind": "terminal", "native": {"device_hash": "low", "device_class": "ElevatorFloorTerminalControllerPS", "ps_entry_hash": "ps-low", "instance_data_ref": "verified-terminal-preset", "node_ref": "ref-panel"}},
                {"id": "fact", "name": "Unlocked", "kind": "fact", "config": {"fact_name": "clinic.door_open"}},
            ], "links": [{"id": "wire", "from_id": "door", "to_id": "terminal", "order": 1},
                        {"id": "semantic", "from_id": "terminal", "to_id": "fact", "order": 2}]}
            result = wiring.apply_logic_graph(path, graph)
            devices = json.loads(path.read_text())["devices"]
            self.assertTrue(result["ready"])
            self.assertEqual(result["device_edge_count"], 1)
            self.assertEqual(result["semantic_edge_count"], 1)
            self.assertEqual(devices["other"]["children"], ["low"])
            self.assertEqual(devices["low"]["parents"], ["other"])

    def test_logic_graph_missing_ps_instance_is_blocked_without_writing(self):
        with tempfile.TemporaryDirectory() as td:
            path = fixture(Path(td) / "world.json")
            before = path.read_bytes()
            graph = {"nodes": [
                {"id": "a", "kind": "door", "native": {"device_hash": "other", "ps_entry_hash": "absent"}},
                {"id": "b", "kind": "terminal", "native": {"device_hash": "low", "ps_entry_hash": "absent"}},
            ], "links": [{"id": "ab", "from_id": "a", "to_id": "b"}]}
            result = wiring.apply_logic_graph(path, graph)
            self.assertFalse(result["ready"])
            self.assertFalse(result["written"])
            self.assertGreaterEqual(len(result["missing_resources"]), 2)
            self.assertTrue(any(item["resource"] == "persistent_state_instance" for item in result["missing_resources"]))
            self.assertEqual(path.read_bytes(), before)

    def test_logic_graph_orders_elevator_floor_links(self):
        with tempfile.TemporaryDirectory() as td:
            path = fixture(Path(td) / "world.json")
            data = json.loads(path.read_text())
            data["psEntries"] = {key: {"PSID": key, "instanceData": {"$type": "TypedInstance"}} for key in ("ps-lift", "ps-low", "ps-high")}
            data["sectors"] = [{"nodes": [{"nodeRef": ref} for ref in ("lift-ref", "low-ref", "high-ref")]}]
            path.write_text(json.dumps(data), encoding="utf-8")
            graph = {"id": "lift-graph", "nodes": [
                {"id": "lift", "name": "Lift", "kind": "elevator", "native": {"device_hash": "lift", "ps_entry_hash": "ps-lift", "instance_data_ref": "lift-v1", "node_ref": "lift-ref"}},
                {"id": "low", "name": "Ground", "kind": "terminal", "native": {"device_hash": "low", "ps_entry_hash": "ps-low", "instance_data_ref": "low-v1", "node_ref": "low-ref"}},
                {"id": "high", "name": "Roof", "kind": "terminal", "native": {"device_hash": "high", "ps_entry_hash": "ps-high", "instance_data_ref": "high-v1", "node_ref": "high-ref"}},
            ], "links": [{"id": "floor-low", "from_id": "lift", "to_id": "low", "order": 1},
                        {"id": "floor-high", "from_id": "lift", "to_id": "high", "order": 2}]}
            result = wiring.apply_logic_graph(path, graph)
            devices = json.loads(path.read_text())["devices"]
            self.assertTrue(result["ready"])
            self.assertEqual(devices["lift"]["children"], ["low", "high"])
            self.assertEqual(devices["low"]["parents"], ["lift"])
            self.assertEqual(devices["high"]["parents"], ["lift"])

    def test_logic_graph_creates_resources_from_explicit_typed_payloads(self):
        with tempfile.TemporaryDirectory() as td:
            path = fixture(Path(td) / "world.json")
            data = json.loads(path.read_text())
            data["sectors"] = [{"name": "main", "min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 1, "y": 1, "z": 1}, "nodes": []}]
            path.write_text(json.dumps(data), encoding="utf-8")
            graph = {"id": "create-resources", "nodes": [{"id": "door", "name": "New Door", "kind": "door", "native": {
                "device_hash": "door-hash", "device_class": "DoorControllerPS", "ps_entry_hash": "door-ps-hash",
                "instance_data_ref": "verified-door-instance-v1", "node_ref": "door-node-ref", "sector_name": "main",
                "device_record": {"hash": "door-hash", "className": "DoorControllerPS", "nodePosition": {"x": 4, "y": 5, "z": 6}, "children": [], "parents": []},
                "ps_entry": {"PSID": "door-persistent-state-id", "instanceData": {"$type": "DoorInstanceData", "verifiedPreset": "v1"}},
                "world_node": {"name": "New Door", "type": "worldDeviceNode", "nodeRef": "door-node-ref", "position": {"x": 4, "y": 5, "z": 6}, "rotation": {"i": 0, "j": 0, "k": 0, "r": 1}, "scale": {"x": 1, "y": 1, "z": 1}, "data": {"$type": "VerifiedDoorNodeData"}},
            }}], "links": []}
            result = wiring.apply_logic_graph(path, graph)
            saved = json.loads(path.read_text())
            self.assertTrue(result["ready"])
            self.assertEqual(result["created_device_records"], 1)
            self.assertEqual(result["created_ps_entries"], 1)
            self.assertEqual(result["created_world_nodes"], 1)
            self.assertIn("door-hash", saved["devices"])
            self.assertEqual(saved["psEntries"]["door-ps-hash"]["PSID"], "door-persistent-state-id")
            self.assertEqual(saved["sectors"][0]["nodes"][0]["nodeRef"], "door-node-ref")


if __name__ == "__main__":
    unittest.main()
