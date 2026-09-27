#!/usr/bin/env python3
"""Vanilla clone: sector JSON reader and MCP payload contract."""
from __future__ import annotations

import importlib
import json
import math
import random
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


def path_ref(p):
    return {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": p}, "Flags": "Default"}


def cname(v):
    return {"$type": "CName", "$storage": "string", "$value": v}


def node_data(index, pos, yaw=0.0, scale=(1, 1, 1), node_id="0", ref=None):
    q = vanilla.euler_to_quat(0, 0, yaw)
    return {"Id": node_id, "NodeIndex": index,
            "Position": {"$type": "Vector4", "X": pos[0], "Y": pos[1], "Z": pos[2], "W": 0},
            "Orientation": {"$type": "Quaternion", **q},
            "Scale": {"$type": "Vector3", "X": scale[0], "Y": scale[1], "Z": scale[2]},
            "QuestPrefabRefHash": {"$type": "NodeRef", "$storage": "string", "$value": ref} if ref else
            {"$type": "NodeRef", "$storage": "uint64", "$value": "0"}}


SECTOR = {"Header": {}, "Data": {"RootChunk": {
    "$type": "worldStreamingSector",
    "nodes": [
        {"HandleId": "0", "Data": {"$type": "worldMeshNode", "debugName": cname("clinic_bed"), "mesh": path_ref("base\\clinic\\bed.mesh"), "meshAppearance": cname("dirty")}},
        {"HandleId": "1", "Data": {"$type": "worldEntityNode", "debugName": cname("monitor"), "entityTemplate": path_ref("base\\clinic\\monitor.ent"), "appearanceName": cname("on")}},
        {"HandleId": "2", "Data": {"$type": "worldInstancedMeshNode", "mesh": path_ref("base\\clinic\\tile.mesh")}},
        {"HandleId": "3", "Data": {"$type": "worldStaticLightNode"}},
    ],
    "nodeData": {"Type": "worldNodeDataBuffer", "Data": [
        node_data(0, (10, 20, 30), yaw=90, scale=(2, 2, 1), node_id="1001", ref="$/clinic/#bed"),
        node_data(0, (15, 20, 30), yaw=-45, node_id="1002"),
        node_data(1, (11, 21, 31), yaw=180),
        node_data(2, (0, 0, 0)),
        node_data(3, (12, 20, 33)),
    ]},
}}}


class VanillaSectorTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.file = Path(self.dir.name) / "interior_1_2_3_0.streamingsector.json"
        self.file.write_text(json.dumps(SECTOR), encoding="utf-8")

    def tearDown(self):
        self.dir.cleanup()

    def test_quaternion_roundtrip(self):
        rng = random.Random(4)
        for _ in range(300):
            r, p, y = rng.uniform(-179, 179), rng.uniform(-89, 89), rng.uniform(-179, 179)
            e = vanilla.quat_to_euler(**vanilla.euler_to_quat(r, p, y))
            self.assertAlmostEqual(e["roll"], r, places=2)
            self.assertAlmostEqual(e["pitch"], p, places=2)
            self.assertAlmostEqual(e["yaw"], y, places=2)
        q = vanilla.euler_to_quat(0, 0, 90)
        self.assertAlmostEqual(q["k"], math.sqrt(0.5))

    def test_read_sector(self):
        report = vanilla.read_sector(self.file)
        self.assertEqual(report["sector"], "interior_1_2_3_0")
        self.assertEqual(report["instance_count"], 5)
        rows = report["items"]
        bed = rows[0]
        self.assertEqual((bed["node_index"], bed["instance_index"], bed["node_id"], bed["node_ref"]), (0, 0, "1001", "$/clinic/#bed"))
        self.assertEqual(bed["mesh_path"], "base\\clinic\\bed.mesh")
        self.assertEqual(bed["mesh_appearance"], "dirty")
        self.assertAlmostEqual(bed["rotation"]["yaw"], 90, places=3)
        self.assertEqual(bed["scale"], {"x": 2.0, "y": 2.0, "z": 1.0})
        self.assertEqual(rows[1]["instance_index"], 1)
        self.assertAlmostEqual(rows[1]["rotation"]["yaw"], -45, places=3)
        self.assertEqual(rows[2]["template_path"], "base\\clinic\\monitor.ent")
        self.assertEqual(rows[2]["appearance"], "on")
        self.assertFalse(rows[3]["cloneable"])
        self.assertIn("buffer", rows[3]["reason"])
        self.assertFalse(rows[4]["cloneable"])
        only = vanilla.read_sector(self.file, cloneable_only=True)
        self.assertEqual(only["matched"], 3)
        near = vanilla.read_sector(self.file, center={"x": 10, "y": 20, "z": 30}, radius=2)
        self.assertEqual([r["node_index"] for r in near["items"]], [0, 1], "bed instance 0 and the monitor are within 2 m")
        self.assertEqual(vanilla.read_sector(self.file, term="monitor")["matched"], 1)
        self.assertEqual(vanilla.read_sector(self.file, match=[{"node_index": 0, "instance_index": 1}])["items"][0]["node_id"], "1002")
        with self.assertRaises(ValueError):
            bad = Path(self.dir.name) / "bad.json"
            bad.write_text(json.dumps({"Data": {"RootChunk": {"$type": "CMesh"}}}), encoding="utf-8")
            vanilla.read_sector(bad)

    def test_mcp_payloads(self):
        sent: list[tuple[str, dict]] = []

        def fake_send(op, args=None, **_k):
            sent.append((op, args or {}))
            if op == "vanilla_clone_candidates":
                return {"items": [{"index": 1, "node_index": 0, "instance_index": 1, "sector_path": "base\\worlds\\interior_1_2_3_0.streamingsector"},
                                  {"index": 2, "node_index": 1, "sector_path": "base\\worlds\\other.streamingsector"}]}
            return {"ok": True}

        with patch.object(server, "_send", fake_send):
            call(server.vanilla_clone_pick, distance=20, all_hits=True)
            call(server.vanilla_clone_scan, radius=6, term="bed")
            call(server.vanilla_clone_select, "all")
            call(server.vanilla_clone_select, "3", selected=False)
            call(server.vanilla_clone_import, indices=[1, 2], hide_originals=True, allow_approximate=True, group_name="Clinic")
            call(server.vanilla_clone_revert, "o1", delete=False)
            call(server.vanilla_clone_list)
            call(server.vanilla_clone_status)
            call(server.vanilla_clone_clear)
            call(server.vanilla_clone_candidates)
            listed = call(server.vanilla_sector_nodes, str(self.file), cloneable_only=False)
            staged = call(server.vanilla_clone_from_sector, str(self.file), match_staged=True)
            imported = call(server.vanilla_clone_from_sector, str(self.file), node_indices=[0], import_now=True, hide_originals=True)
            with self.assertRaises(ValueError):
                call(server.vanilla_clone_from_sector, str(self.file))
            with self.assertRaises(ValueError):
                call(server.vanilla_sector_nodes, "missing.json")
        ops = {}
        for op, args in sent:
            ops.setdefault(op, []).append(args)
        self.assertEqual(ops["vanilla_clone_pick"][0], {"distance": 20, "all": True, "append": False})
        self.assertEqual(ops["vanilla_clone_select"][0]["index"], "all")
        self.assertEqual(ops["vanilla_clone_select"][1], {"index": 3, "selected": False})
        imp = ops["vanilla_clone_import"][0]
        self.assertEqual((imp["indices"], imp["hide_originals"], imp["allow_approximate"], imp["group_name"]), ([1, 2], True, True, "Clinic"))
        self.assertEqual(ops["vanilla_clone_revert"][0], {"id": "o1", "delete": False})
        self.assertEqual(listed["instance_count"], 5)
        stage = ops["vanilla_clone_stage"][0]["candidates"]
        self.assertEqual([(c["node_index"], c["instance_index"]) for c in stage], [(0, 1)], "only this sector's staged pick")
        self.assertEqual(staged["matched"], 1)
        direct = ops["vanilla_clone_import"][1]
        self.assertEqual(len(direct["candidates"]), 2)
        self.assertTrue(direct["hide_originals"])
        self.assertEqual(imported["matched"], 2)


if __name__ == "__main__":
    unittest.main()
