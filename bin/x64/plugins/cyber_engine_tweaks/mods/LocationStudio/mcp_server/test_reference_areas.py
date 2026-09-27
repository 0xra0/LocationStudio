#!/usr/bin/env python3
"""Reference-area MCP payload contract and sector box capture."""
from __future__ import annotations

import importlib
import json
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
from lsbuild import vanilla  # noqa: E402


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def sector(nodes):
    return {"Data": {"RootChunk": {"$type": "worldStreamingSector",
        "nodes": [{"HandleId": str(i), "Data": {"$type": t, "mesh": {"DepotPath": {"$value": p}}}} for i, (t, p, _pos) in enumerate(nodes)],
        "nodeData": {"Data": [{"Id": str(100 + i), "NodeIndex": i,
                               "Position": {"X": pos[0], "Y": pos[1], "Z": pos[2]},
                               "Orientation": {"i": 0, "j": 0, "k": 0, "r": 1}, "Scale": {"X": 1, "Y": 1, "Z": 1}}
                              for i, (_t, _p, pos) in enumerate(nodes)]}}}}


class ReferenceAreaTests(unittest.TestCase):
    def test_box_filter(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "a.streamingsector.json"
            f.write_text(json.dumps(sector([("worldMeshNode", "base\\a.mesh", (1, 1, 1)), ("worldMeshNode", "base\\b.mesh", (9, 1, 1))])), encoding="utf-8")
            r = vanilla.read_sector(f, box={"min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 5, "y": 5, "z": 5}})
            self.assertEqual([i["mesh_path"] for i in r["items"]], ["base\\a.mesh"])

    def test_payloads(self):
        sent: list[tuple[str, dict]] = []
        with tempfile.TemporaryDirectory() as d, \
                patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            a = Path(d) / "a.streamingsector.json"
            b = Path(d) / "b.streamingsector.json"
            a.write_text(json.dumps(sector([("worldMeshNode", "base\\a.mesh", (1, 1, 1)), ("worldStaticLightNode", "", (2, 2, 2))])), encoding="utf-8")
            b.write_text(json.dumps(sector([("worldMeshNode", "base\\c.mesh", (3, 3, 3)), ("worldMeshNode", "base\\far.mesh", (50, 3, 3))])), encoding="utf-8")
            call(server.reference_area_box, corner="a", source="aim")
            call(server.reference_area_box, corner="b", position=[1, 2, 3])
            call(server.reference_area_box, room_id="r1", margin=1)
            call(server.reference_area_box)
            call(server.reference_area_capture, "Clinic", padding_horizontal=0.5, allow_approximate=True)
            call(server.reference_area_capture, "Box", min_corner=[0, 0, 0], max_corner=[4, 4, 4])
            out = call(server.reference_capture_from_sector, "Exact", [str(a), str(b)], [5, 5, 5], [0, 0, 0], show=True)
            call(server.reference_area_show, "ra1", visible=False)
            call(server.reference_area_compare, "ra1", move_radius=3)
            call(server.reference_area_copy, "ra1", object_ids=["o1"], layer="decoration")
            call(server.reference_area_align, "o2", "o1", scale=False)
            call(server.reference_area_delete, "ra1")
            call(server.reference_area_get, "ra1")
            call(server.reference_area_list)
            for bad in (lambda: call(server.reference_area_box, corner="c"),
                        lambda: call(server.reference_area_box, corner="a", source="moon"),
                        lambda: call(server.reference_area_capture, "x", min_corner=[0, 0, 0]),
                        lambda: call(server.reference_capture_from_sector, "x", [str(a)], [100, 100, 100], [101, 101, 101])):
                with self.assertRaises(ValueError):
                    bad()
        box = [args for op, args in sent if op == "reference_area_box"]
        self.assertEqual(box[0], {"corner": "a", "source": "aim"})
        self.assertEqual(box[1]["position"], {"x": 1.0, "y": 2.0, "z": 3.0})
        self.assertEqual(box[2], {"room_id": "r1", "margin": 1})
        self.assertEqual(box[3], {})
        caps = [args for op, args in sent if op == "reference_area_capture"]
        self.assertEqual(caps[0]["padding"]["horizontal"], 0.5)
        self.assertTrue(caps[0]["allow_approximate"])
        self.assertNotIn("min", caps[0])
        self.assertEqual(caps[1]["max"], {"x": 4.0, "y": 4.0, "z": 4.0})
        exact = caps[2]
        self.assertEqual(exact["min"], {"x": 0.0, "y": 0.0, "z": 0.0})
        self.assertEqual(sorted(c.get("mesh_path", c["node_type"]) for c in exact["candidates"]),
                         ["base\\a.mesh", "base\\c.mesh", "worldStaticLightNode"])
        self.assertTrue(exact["show"])
        self.assertEqual(out["candidates"], 3)
        ops = dict(sent)
        self.assertEqual(ops["reference_area_align"], {"object_id": "o2", "reference_id": "o1", "rotation": True, "scale": False})
        self.assertEqual(ops["reference_area_copy"]["object_ids"], ["o1"])
        self.assertEqual(ops["reference_area_compare"]["move_radius"], 3)


if __name__ == "__main__":
    unittest.main()
