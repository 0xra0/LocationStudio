#!/usr/bin/env python3
"""Parametric room generator: MCP tool wrappers."""
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


def fn(tool):
    return getattr(tool, "fn", tool)


class RoomGeneratorToolTests(unittest.TestCase):
    def setUp(self):
        self.sent: list[tuple[str, dict]] = []
        self.patcher = patch.object(server, "_send", lambda op, args=None, **_k: self.sent.append((op, args or {})) or {"ok": True})
        self.patcher.start()

    def tearDown(self):
        self.patcher.stop()

    def test_create_with_position_and_source(self):
        spec = {"width": 6, "length": 4, "doors": [{"wall": "south"}]}
        json.loads(fn(server.room_generator_create)(spec, premise_id="p1", position=[1, 2, 3], yaw=90))
        op, args = self.sent[-1]
        self.assertEqual(op, "room_generator_create")
        self.assertEqual(args["spec"], spec)
        self.assertEqual(args["transform"], {"position": {"x": 1, "y": 2, "z": 3, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": 90}})
        fn(server.room_generator_create)(spec, source="aim")
        self.assertEqual(self.sent[-1][1]["source"], "aim")
        self.assertNotIn("premise_id", self.sent[-1][1])
        with self.assertRaises(ValueError):
            fn(server.room_generator_create)(spec, source="sky")

    def test_other_tools(self):
        fn(server.room_generator_preview)({"width": 5})
        fn(server.room_generator_update)("r1", {"height": 4})
        fn(server.room_generator_delete)("r1")
        fn(server.room_generator_list)()
        fn(server.room_generator_get)("r1")
        fn(server.room_generator_snap)("o1", "r1", "wall_north", offset=[0, 0.3, 0], yaw=180)
        ops = [op for op, _ in self.sent]
        self.assertEqual(ops, ["room_generator_preview", "room_generator_update", "room_generator_delete", "room_generator_list",
                               "room_generator_get", "room_generator_snap"])
        self.assertEqual(self.sent[1][1], {"room_id": "r1", "spec": {"height": 4}})
        snap = self.sent[-1][1]
        self.assertEqual((snap["offset_x"], snap["offset_y"], snap["offset_z"], snap["yaw"], snap["align"]), (0, 0.3, 0, 180, True))

    def test_docstrings_describe_the_spec(self):
        for tool in (server.room_generator_preview, server.room_generator_create):
            self.assertIn("coffered", fn(tool).__doc__)


if __name__ == "__main__":
    unittest.main()
