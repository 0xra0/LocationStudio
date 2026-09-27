#!/usr/bin/env python3
"""Collision authoring MCP payload contract."""
from __future__ import annotations

import importlib
import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch


class Tool:
    def __init__(self, fn):
        self.fn = fn


class MCPServer:
    def __init__(self, *_args, **_kwargs): pass
    def tool(self): return lambda fn: Tool(fn)
    def resource(self, *_args, **_kwargs): return lambda fn: fn


fake_server = types.ModuleType("mcp.server")
fake_server.MCPServer = MCPServer
fake_mcp = types.ModuleType("mcp")
fake_mcp.server = fake_server
sys.modules.setdefault("mcp", fake_mcp)
sys.modules.setdefault("mcp.server", fake_server)
sys.path.insert(0, str(Path(__file__).resolve().parent))
server = importlib.import_module("server")


def call(tool, *args, **kwargs):
    return json.loads(getattr(tool, "fn", tool)(*args, **kwargs))


class CollisionMcpTests(unittest.TestCase):
    def test_payloads(self):
        sent: list[tuple[str, dict]] = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.collision_create_primitive, size_x=4, size_y=0.4, size_z=3, preset="Player Blocker", material="concrete")
            call(server.collision_create_primitive, shape="capsule", radius=0.3, height=2, x=1, y=2, z=3, yaw=90)
            call(server.collision_import_mesh, "sector:shape", preset="NPC Collision", scale=2)
            call(server.collision_fit_to_object, "obj1", padding=0.1)
            call(server.collision_update, "obj1", preset="World Static", visualize=False)
            call(server.collision_visualization, False, premise_id="p1")
            call(server.collision_passability, actor="player", center_x=0, center_y=0, start_x=-3, start_y=0, start_z=0,
                 goal_x=3, goal_y=0, goal_z=0, live=True)
            call(server.collision_layers)
            call(server.collision_list, preset="Player Blocker")
            call(server.collision_presets)
            call(server.collision_search_meshes, "bench")
            for bad in (lambda: call(server.collision_create_primitive, shape="cone"),
                        lambda: call(server.collision_create_primitive, size_x=1),
                        lambda: call(server.collision_create_primitive, x=1),
                        lambda: call(server.collision_update, "o", size_y=1),
                        lambda: call(server.collision_passability, actor="car"),
                        lambda: call(server.collision_passability, start_x=1)):
                with self.assertRaises(ValueError):
                    bad()
        ops = [op for op, _ in sent]
        self.assertEqual(ops, ["collision_create_primitive", "collision_create_primitive", "collision_import_mesh",
                               "collision_fit_to_object", "collision_update", "collision_visualization",
                               "collision_passability", "collision_layers", "collision_list", "collision_presets",
                               "collision_search_meshes"])
        box = sent[0][1]
        self.assertEqual(box["size"], {"x": 4, "y": 0.4, "z": 3})
        self.assertEqual((box["preset"], box["material"]), ("Player Blocker", "concrete"))
        self.assertNotIn("transform", box)
        capsule = sent[1][1]
        self.assertEqual(capsule["transform"]["position"], {"x": 1, "y": 2, "z": 3, "w": 1})
        self.assertEqual(capsule["transform"]["rotation"]["yaw"], 90)
        self.assertEqual(sent[4][1], {"id": "obj1", "patch": {"preset": "World Static", "visualize": False}})
        passability = sent[6][1]
        self.assertEqual(passability["start"], {"x": -3, "y": 0, "z": 0})
        self.assertTrue(passability["live"])


if __name__ == "__main__":
    unittest.main()
