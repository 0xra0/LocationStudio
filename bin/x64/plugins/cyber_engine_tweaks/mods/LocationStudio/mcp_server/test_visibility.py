#!/usr/bin/env python3
"""Occlusion/visibility MCP payload contract."""
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


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


class VisibilityMcpTests(unittest.TestCase):
    def test_payloads(self):
        sent: list[tuple[str, dict]] = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.visibility_capabilities)
            call(server.visibility_create_occluder, mesh="plane_two_sided", size_x=3, size_z=2.5, x=1, y=2, z=3, yaw=90)
            call(server.visibility_occlude_room, "room1", walls=["north", "east"])
            call(server.visibility_update_occluder, "occ1", mesh="box", size_x=1, size_y=2, size_z=3)
            call(server.visibility_list_occluders, premise_id="p1")
            call(server.visibility_pvs, camera_ids=["cam1"], live=True)
            call(server.visibility_hidden_meshes, min_dimension=8)
            for bad in (lambda: call(server.visibility_create_occluder, mesh="sphere"),
                        lambda: call(server.visibility_create_occluder, x=1),
                        lambda: call(server.visibility_occlude_room, "r", walls=["up"]),
                        lambda: call(server.visibility_update_occluder, "o", size_x=1)):
                with self.assertRaises(ValueError):
                    bad()
        ops = [op for op, _ in sent]
        self.assertEqual(ops, ["visibility_capabilities", "visibility_create_occluder", "visibility_occlude_room",
                               "visibility_update_occluder", "visibility_list_occluders", "visibility_pvs",
                               "visibility_hidden_meshes"])
        occ = sent[1][1]
        self.assertEqual(occ["transform"]["rotation"]["yaw"], 90)
        self.assertEqual(occ["size"], {"x": 3, "y": 4.0, "z": 2.5})
        self.assertEqual(sent[2][1]["walls"], ["north", "east"])
        self.assertEqual(sent[3][1], {"id": "occ1", "patch": {"mesh": "box", "size": {"x": 1, "y": 2, "z": 3}}})
        self.assertEqual(sent[5][1]["camera_ids"], ["cam1"])
        self.assertTrue(sent[5][1]["live"])


if __name__ == "__main__":
    unittest.main()
