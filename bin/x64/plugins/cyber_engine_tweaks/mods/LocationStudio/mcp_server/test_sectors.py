#!/usr/bin/env python3
"""Streaming-sector inspector: sector membership, references, persistent IDs and wrong-sector flags."""
from __future__ import annotations

import importlib
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lsbuild import sectors  # noqa: E402


def node(name, ref, x, y, z=0.0, ntype="worldStaticMeshNode", data=None, **extra):
    out = {"name": name, "type": ntype, "position": {"x": x, "y": y, "z": z, "w": 0},
           "rotation": {"i": 0, "j": 0, "k": 0, "r": 1}, "scale": {"x": 1, "y": 1, "z": 1},
           "primaryRange": 100, "secondaryRange": 120, "data": data or {}}
    if ref:
        out["nodeRef"] = ref
    out.update(extra)
    return out


def fixture(root: Path) -> tuple[Path, Path]:
    a_nodes = [node("[Mesh] Wall A", "$/demo/#wall_a", 1, 1), node("[Mesh] Wall B", None, 5, 5),
               node("[Mesh] Crate", None, 8, 2), node("[Mesh] Shelf", None, 2, 8),
               # Belongs to sector B's box: wrong sector.
               node("[Mesh] Stray lamp", "$/demo/#stray", 105, 5),
               # Device whose data references a NodeRef in sector B.
               node("[Device] Door", "$/demo/#door", 3, 3, ntype="worldDeviceNode",
                    data={"target": {"$type": "NodeRef", "$storage": "string", "$value": "$/demo/#terminal"}}),
               # References a NodeRef that is not in this export (vanilla or missing).
               node("[Mesh] Sign", None, 4, 4, data={"owner": "$/03_night_city/#vanilla_sign"}),
               # Streaming reference point outside the sector.
               node("[Mesh] Pipe", None, 6, 6, streamingRefPoint={"x": 500, "y": 500, "z": 0})]
    b_nodes = [node("[Device] Terminal", "$/demo/#terminal", 102, 3, ntype="worldDeviceNode"), node("[Mesh] Floor", None, 101, 1),
               node("[Mesh] Rail", None, 103, 8), node("[Mesh] Post", None, 108, 8),
               # Far outside every sector.
               node("[Mesh] Lost bench", None, 400, 400)]
    export = {
        "name": "demo", "sectors": [
            {"name": "demo_a", "min": {"x": 0, "y": 0, "z": -5}, "max": {"x": 10, "y": 10, "z": 5}, "category": "Interior", "level": 1,
             "variantIndices": [0, 6], "variants": [{"name": "broken", "rangeIndex": 1}], "nodes": a_nodes},
            {"name": "demo_b", "min": {"x": 100, "y": 0, "z": -5}, "max": {"x": 110, "y": 10, "z": 5}, "category": "Exterior", "level": 1,
             "variantIndices": [0], "variants": [], "nodes": b_nodes},
        ],
        "devices": {
            "111": {"hash": "111", "className": "DoorControllerPS", "nodePosition": {"x": 3, "y": 3, "z": 0}, "children": ["222"], "parents": []},
            "222": {"hash": "222", "className": "TerminalControllerPS", "nodePosition": {"x": 102, "y": 3, "z": 0}, "children": [], "parents": ["111"]},
            "333": {"hash": "333", "className": "GhostPS", "nodePosition": {"x": 999, "y": 0, "z": 0}, "children": ["444"], "parents": []},
        },
        "psEntries": {"111": {"PSID": "9001", "instanceData": {}}, "222": {"PSID": "9002", "instanceData": {}},
                      "333": {"PSID": "9001", "instanceData": {}}},
    }
    project = {"objects": [
        {"id": "obj_stray", "name": "Stray lamp", "premise_id": "p1", "transform": {"position": {"x": 105, "y": 5, "z": 0}},
         "metadata": {"world_builder": {"definition_key": "mesh_static"}}},
        {"id": "obj_wall", "name": "Wall A", "premise_id": "p1", "transform": {"position": {"x": 1, "y": 1, "z": 0}},
         "metadata": {"world_builder": {"definition_key": "mesh_static"}}},
        {"id": "obj_terminal", "name": "Terminal", "premise_id": "p1", "transform": {"position": {"x": 102, "y": 3, "z": 0}},
         "metadata": {"world_builder": {"definition_key": "device"}}},
    ]}
    export_file, project_file = root / "demo_exported.json", root / "project.json"
    export_file.write_text(json.dumps(export), encoding="utf-8")
    project_file.write_text(json.dumps(project), encoding="utf-8")
    return export_file, project_file


class SectorInspectorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.export_file, self.project_file = fixture(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def codes(self, report, name):
        return {f["code"] for f in report["flags"] if f.get("node_name") == name}

    def test_membership_counts_and_refs(self):
        before = self.export_file.read_bytes()
        report = sectors.inspect(self.export_file, self.project_file, output=self.root / "report.json")
        self.assertEqual(self.export_file.read_bytes(), before, "inspection is read-only")
        self.assertEqual((report["sector_count"], report["node_count"], report["device_count"], report["ps_entry_count"]), (2, 13, 3, 3))
        a = next(s for s in report["sectors"] if s["name"] == "demo_a")
        self.assertEqual((a["node_refs"], a["devices"], a["ps_entries"], a["category"]), (3, 1, 1, "Interior"))
        self.assertEqual(a["bounds"]["max"]["x"], 10)
        door = next(n for n in report["nodes"] if n["name"] == "[Device] Door")
        self.assertEqual((door["sector"], door["device_hash"], door["psid"]), ("demo_a", "111", "9001"))
        self.assertEqual(door["references"], ["$/demo/#terminal"])
        self.assertEqual(next(n for n in report["nodes"] if n["name"] == "[Mesh] Pipe")["variant"]["name"], "broken")
        self.assertEqual(next(n for n in report["nodes"] if n["name"] == "[Mesh] Wall A")["variant"]["name"], "default")
        self.assertTrue(Path(report["report_file"]).is_file())

    def test_wrong_sector_and_other_flags(self):
        report = sectors.inspect(self.export_file, self.project_file)
        stray = next(f for f in report["flags"] if f["code"] == "outside_sector_inside_other")
        self.assertEqual((stray["node_name"], stray["suggested_sector"], stray["severity"], stray["object_id"]),
                         ("[Mesh] Stray lamp", "demo_b", "error", "obj_stray"))
        self.assertIn(stray, report["likely_wrong_sector"])
        self.assertIn("outside_sector_bounds", self.codes(report, "[Mesh] Lost bench"))
        self.assertIn("sector_outlier", self.codes(report, "[Mesh] Lost bench"))
        self.assertIn("streaming_ref_outside_sector", self.codes(report, "[Mesh] Pipe"))
        self.assertEqual(self.codes(report, "[Mesh] Wall A"), set(), "well-placed nodes are not flagged")
        by_code = {f["code"] for f in report["flags"]}
        self.assertIn("duplicate_psid", by_code)
        self.assertIn("device_without_node", by_code)
        self.assertEqual(report["flags"][0]["severity"], "error", "errors are listed first")

    def test_cross_sector_references(self):
        report = sectors.inspect(self.export_file, self.project_file)
        refs = report["cross_sector_references"]
        node_ref = next(r for r in refs if r["kind"] == "node_ref" and r["status"] == "cross_sector")
        self.assertEqual((node_ref["from_sector"], node_ref["target_sector"], node_ref["target_ref"]), ("demo_a", "demo_b", "$/demo/#terminal"))
        self.assertTrue(any(r["status"] == "external_or_missing" and r["target_ref"] == "$/03_night_city/#vanilla_sign" for r in refs))
        link = next(r for r in refs if r["kind"] == "device_link" and r["status"] == "cross_sector")
        self.assertEqual((link["from_device"], link["to_device"]), ("111", "222"))
        self.assertTrue(any(r["kind"] == "device_link" and r["status"] == "missing_device" for r in refs))
        self.assertEqual(report["premises_split_across_sectors"], [{"premise_id": "p1", "sectors": ["demo_a", "demo_b"]}])

    def test_sector_filter_and_no_project(self):
        report = sectors.inspect(self.export_file, None, sector="demo_b")
        self.assertTrue(all(n["sector"] == "demo_b" for n in report["nodes"]))
        self.assertEqual(report["matched_objects"], 0)


class Tool:
    def __init__(self, fn):
        self.fn = fn


class MCPServer:
    def __init__(self, *_a, **_k): pass
    def tool(self): return lambda fn: Tool(fn)
    def resource(self, *_a, **_k): return lambda fn: fn


class SectorMcpTests(unittest.TestCase):
    def test_tools_and_in_game_report(self):
        fake_server = types.ModuleType("mcp.server")
        fake_server.MCPServer = MCPServer
        fake_mcp = types.ModuleType("mcp")
        fake_mcp.server = fake_server
        sys.modules.setdefault("mcp", fake_mcp)
        sys.modules.setdefault("mcp.server", fake_server)
        server = importlib.import_module("server")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            export_file, project_file = fixture(root)
            with patch.object(server, "PROJECT", project_file), patch.object(server, "SECTOR_REPORT", root / "exports" / "sector-inspection.json"):
                out = json.loads(getattr(server.sector_inspect, "fn", server.sector_inspect)(str(export_file), flags_limit=2))
                self.assertEqual(out["flags_truncated"], len(sectors.inspect(export_file, project_file)["flags"]) - 2)
                self.assertTrue((root / "exports" / "sector-inspection.json").is_file())
                self.assertNotIn("nodes", out)
                found = json.loads(getattr(server.sector_node, "fn", server.sector_node)(str(export_file), object_id="obj_stray"))
                self.assertEqual(found["match_count"], 1)
                self.assertEqual(found["flags"][0]["code"], "outside_sector_inside_other")
                with self.assertRaises(ValueError):
                    getattr(server.sector_node, "fn", server.sector_node)(str(export_file))
                safe = server._sector_report_safe(root / "missing.json", root / "ws" / "r.json")
                self.assertIn("advisory_error", safe, "the build stage never raises")


if __name__ == "__main__":
    unittest.main()
