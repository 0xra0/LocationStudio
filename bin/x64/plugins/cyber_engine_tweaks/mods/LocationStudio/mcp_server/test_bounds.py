#!/usr/bin/env python3
"""Automatic bounds (Build Mod side): exact mesh bounds, streaming ranges, sector placement and tools."""
from __future__ import annotations

import importlib
import json
import math
import stat
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch


class Tool:
    def __init__(self, fn):
        self.fn = fn


class MCPServer:
    def __init__(self, *_a, **_k): pass
    def tool(self): return lambda fn: Tool(fn)
    def resource(self, *_a, **_k): return lambda fn: fn


fake_server = types.ModuleType("mcp.server")
fake_server.MCPServer = MCPServer
fake_mcp = types.ModuleType("mcp")
fake_mcp.server = fake_server
sys.modules.setdefault("mcp", fake_mcp)
sys.modules.setdefault("mcp.server", fake_server)
sys.path.insert(0, str(Path(__file__).resolve().parent))
server = importlib.import_module("server")
from lsbuild import bounds as bd  # noqa: E402
from lsbuild import procedural as pg  # noqa: E402
from lsbuild.build import MANIFEST_SCHEMA  # noqa: E402


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def box(cx, cy, cz, sx, sy, sz):
    return {"shape": "box", "center": {"x": cx, "y": cy, "z": cz}, "size": {"x": sx, "y": sy, "z": sz},
            "rotation": {"roll": 0, "pitch": 0, "yaw": 0}, "material": "main"}


def obj(oid="w", parts=None, position=(10, 20, 5), yaw=90.0, **cfg):
    return {"id": oid, "name": "Wall " + oid, "premise_id": "p", "enabled": True,
            "transform": {"position": {"x": position[0], "y": position[1], "z": position[2]}, "rotation": {"roll": 0, "pitch": 0, "yaw": yaw}},
            "metadata": {"procedural": {"generator": "box", "parts": parts or [box(0, 0, 1.5, 4, 0.2, 3)], "mesh_path": f"mod\\ls\\{oid}.mesh",
                                        "material": {"materials": {"main": "base\\a.mi"}}, **cfg}}}


def fake_worker(path: Path) -> Path:
    path.write_text(f"#!{sys.executable}\nimport sys\nargs=sys.argv[1:]\nopen(args[args.index('--output')+1],'wb').write(b'CR2W'+b'x'*8)\n")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


class RecordTests(unittest.TestCase):
    def test_record(self):
        s = bd.settings({})
        rec = bd.record(obj(), s)
        self.assertEqual(rec["local"]["min"], {"x": -2.0, "y": -0.1, "z": 0.0})
        # Yaw 90 turns local x onto world y.
        self.assertAlmostEqual(rec["world"]["min"]["y"], 18)
        self.assertAlmostEqual(rec["world"]["max"]["y"], 22)
        self.assertAlmostEqual(rec["world"]["min"]["x"], 9.9)
        self.assertAlmostEqual(rec["world"]["max"]["z"], 8)
        radius = math.sqrt(4 + 0.01 + 2.25)
        self.assertAlmostEqual(rec["sphere"]["radius"], radius)
        vis = radius / math.tan(math.radians(0.5))
        self.assertAlmostEqual(rec["visibility"]["distance"], vis)
        self.assertAlmostEqual(rec["streaming"]["range"], vis + 10)
        self.assertAlmostEqual(rec["streaming"]["secondary_range"], (vis + 10) * 1.2)
        self.assertEqual(rec["streaming"]["cells"], ["0,0,0"])
        manual = bd.record(obj(stream_range=40), s)
        self.assertEqual((manual["streaming"]["range"], manual["streaming"]["source"]), (40.0, "manual"))

    def test_settings_and_distances(self):
        s = bd.settings({"settings": {"bounds": {"min_screen_angle": 2, "cell_size": 4, "min_range": "bad"}}})
        self.assertEqual((s["min_screen_angle"], s["cell_size"], s["min_range"]), (2.0, 4.0, 30.0))
        self.assertEqual(bd.distances(0.01, bd.DEFAULTS)[:2], (30.0, 40.0))
        self.assertEqual(bd.distances(500, bd.DEFAULTS)[:2], (800.0, 800.0))

    def test_cells_span(self):
        rec = bd.record(obj(parts=[box(0, 0, 0.5, 20, 1, 1)], position=(0, 0, 0), yaw=0), {**bd.DEFAULTS, "cell_size": 8})
        # x -10..10 and y -0.5..0.5 with 8 m cells: four columns, two rows (y straddles 0).
        self.assertEqual(rec["streaming"]["cells"], ["-2,-1,0", "-2,0,0", "-1,-1,0", "-1,0,0", "0,-1,0", "0,0,0", "1,-1,0", "1,0,0"])

    def test_csg_exact_vs_saved(self):
        tree = {"op": "union", "children": [{"shape": "cylinder", "center": [0, 0, 1], "radius": 1, "length": 0.3, "sides": 24}]}
        o = obj(position=(0, 0, 0), yaw=0)
        o["metadata"]["procedural"].update(generator="csg", csg={"tree": tree, "approximate": True})
        rec = bd.record(o, bd.DEFAULTS)
        self.assertAlmostEqual(rec["local"]["max"]["z"], 2)
        self.assertAlmostEqual(rec["local"]["max"]["y"], 0.15)
        self.assertAlmostEqual(bd.compare({"min": {"x": -1.25, "y": -0.15, "z": 0}, "max": {"x": 1, "y": 0.15, "z": 2}}, rec["local"]), 0.25)
        self.assertIsNone(bd.compare(None, rec["local"]))


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.ws = self.root / "ws"
        (self.ws / "source" / "raw").mkdir(parents=True)
        sectors = [{"name": "a", "min": {"x": -100, "y": -100, "z": -50}, "max": {"x": 0, "y": 100, "z": 50}, "nodes": []},
                   {"name": "b", "min": {"x": 0, "y": -100, "z": -50}, "max": {"x": 100, "y": 100, "z": 50}, "nodes": []}]
        (self.ws / "source" / "raw" / "e.json").write_text(json.dumps({"sectors": sectors}))
        (self.ws / ".cp77wb-build.json").write_text(json.dumps({"schema": MANIFEST_SCHEMA, "exportFile": "source/raw/e.json", "exportSha256": "x"}))

    def tearDown(self):
        self.tmp.cleanup()

    def test_nodes_use_bounds(self):
        # Pivot at x=-1 but the geometry extends to +x: the world centre (x=+4) is in sector b.
        o = obj("long", parts=[box(5, 0, 0.5, 10, 1, 1)], position=(-1, 0, 0), yaw=0)
        saved = dict(o)
        saved["metadata"] = json.loads(json.dumps(o["metadata"]))
        saved["metadata"]["generated_bounds"] = {"local": {"min": {"x": 0, "y": -0.5, "z": 0}, "max": {"x": 9, "y": 0.5, "z": 1}}}
        project = self.root / "project.json"
        project.write_text(json.dumps({"objects": [saved], "settings": {"bounds": {"stream_margin": 0}}}))
        report = pg.apply_to_workspace(project, self.ws, worker=str(fake_worker(self.root / "w")))
        self.assertTrue(report["ready"], report["issues"])
        entry = report["generated"][0]
        radius = math.sqrt(25 + 0.25 + 0.25)
        vis = radius / math.tan(math.radians(0.5))
        self.assertAlmostEqual(entry["bounds"]["primary_range"], vis)
        self.assertTrue(any("differ from the built mesh" in w for w in report.get("warnings", [])))
        export = json.loads((self.ws / "source" / "raw" / "e.json").read_text())
        b = next(s for s in export["sectors"] if s["name"] == "b")
        self.assertEqual(len(b["nodes"]), 1)
        node = b["nodes"][0]
        self.assertAlmostEqual(node["primaryRange"], vis)
        self.assertAlmostEqual(node["secondaryRange"], vis * 1.2)
        self.assertEqual(report["nodes"][0]["sector"], "b")

    def test_rotated_growth(self):
        o = obj("r", parts=[box(0, 0, 0.5, 40, 1, 1)], position=(50, 0, 0), yaw=90)
        placed = pg.inject_nodes({"sectors": [{"name": "s", "min": {"x": 40, "y": -5, "z": 0}, "max": {"x": 60, "y": 5, "z": 2}, "nodes": []}]}, [o])
        self.assertEqual(placed[0]["sector"], "s")
        export = {"sectors": [{"name": "s", "min": {"x": 40, "y": -5, "z": 0}, "max": {"x": 60, "y": 5, "z": 2}, "nodes": []}]}
        pg.inject_nodes(export, [o])
        s = export["sectors"][0]
        self.assertAlmostEqual(s["min"]["y"], -21)
        self.assertAlmostEqual(s["max"]["y"], 21)
        self.assertEqual((s["min"]["x"], s["max"]["x"]), (40, 60), "the rotated 40 m wall runs along y, not x")


class ToolTests(unittest.TestCase):
    def test_report_and_wrappers(self):
        with tempfile.TemporaryDirectory() as td:
            project = Path(td) / "p.json"
            o = obj()
            o["metadata"]["generated_bounds"] = {"local": {"min": {"x": -2, "y": -0.1, "z": 0}, "max": {"x": 2, "y": 0.1, "z": 3}}}
            collider = {"id": "c1", "premise_id": "p", "metadata": {"collision_gen": {"owner": "w"}, "generated_bounds": {"world": {"min": {}, "max": {}}}}}
            project.write_text(json.dumps({"objects": [o, obj("x", parts=[box(0, 0, 0.5, 300, 1, 1)]), collider]}))
            with patch.object(server, "PROJECT", project):
                out = call(server.bounds_report)
        self.assertEqual(out["count"], 2)
        first = next(r for r in out["objects"] if r["object_id"] == "w")
        self.assertAlmostEqual(first["saved_difference"], 0)
        self.assertEqual(out["colliders"][0]["owner"], "w")
        self.assertTrue(any(i.get("info", "").startswith("spans") for i in out["issues"]))
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.bounds_get, object_id="w")
            call(server.bounds_get, room_id="r")
            call(server.bounds_refresh, premise_id="p")
            call(server.bounds_settings)
            call(server.bounds_settings, min_screen_angle=2, cell_size=64)
        self.assertEqual(sent, [("bounds_get", {"object_id": "w"}), ("bounds_get", {"room_id": "r"}), ("bounds_refresh", {"premise_id": "p"}),
                                ("bounds_settings", {}), ("bounds_settings", {"min_screen_angle": 2, "cell_size": 64})])


if __name__ == "__main__":
    unittest.main()
