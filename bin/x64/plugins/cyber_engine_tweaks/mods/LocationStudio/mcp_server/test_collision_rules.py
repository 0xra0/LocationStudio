#!/usr/bin/env python3
"""Collision code generator: MCP wrappers and EDL compilation."""
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
from lsbuild import edl  # noqa: E402


def fn(tool):
    return getattr(tool, "fn", tool)


def steps(result, op):
    return [s for s in result["plan"]["steps"] if s["op"] == op]


class WrapperTests(unittest.TestCase):
    def test_tools(self):
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            fn(server.collision_rules_get)("room:r1")
            fn(server.collision_rules_set)({"mode": "simplified", "actors": "player"}, scope="object:o1", clear=["exclude"])
            fn(server.collision_rules_preview)(object_id="o1", rules={"mode": "bounds"})
            fn(server.collision_rules_preview)(generator="wall", params={"length": 4})
            fn(server.collision_rules_regenerate)(room_id="r1")
            fn(server.collision_rules_report)()
            fn(server.collision_rules_room_enabled)("r1", enabled=False)
            fn(server.procedural_create)("box", params={"size": [1, 1, 1]}, position=[0, 0, 0], collision_rules={"rails": "none"})
            fn(server.procedural_update)("o1", collision_rules={"glass": "block"})
            fn(server.procedural_update)("o1", clear_collision_rules=True)
        ops = [op for op, _ in sent]
        self.assertEqual(ops[:7], ["collision_rules_get", "collision_rules_set", "collision_rules_preview", "collision_rules_preview",
                                   "collision_rules_regenerate", "collision_rules_report", "collision_rules_room_enabled"])
        self.assertEqual(sent[0][1], {"scope": "room:r1"})
        self.assertEqual(sent[1][1], {"scope": "object:o1", "rules": {"mode": "simplified", "actors": "player"}, "replace": False,
                                      "clear": ["exclude"], "regenerate": True})
        self.assertEqual(sent[2][1], {"object_id": "o1", "rules": {"mode": "bounds"}})
        self.assertEqual(sent[3][1], {"generator": "wall", "params": {"length": 4}})
        self.assertEqual(sent[4][1], {"room_id": "r1"})
        self.assertEqual(sent[6][1], {"room_id": "r1", "enabled": False})
        self.assertEqual(sent[7][1]["collision_rules"], {"rails": "none"})
        self.assertEqual(sent[8][1]["collision_rules"], {"glass": "block"})
        self.assertIs(sent[9][1]["collision_rules"], False)
        self.assertIn("player_vehicles", fn(server.collision_rules_set).__doc__)


class EdlTests(unittest.TestCase):
    def doc(self, room, **extra):
        d = {"edl": 1, "id": "t", "name": "T", "origin": {"position": [0, 0, 0]}, "floors": [{"id": "g", "height": 3, "rooms": [room]}]}
        d.update(extra)
        return d

    def test_rules(self):
        room = {"id": "r", "size": [6, 4], "collision_rules": {"actors": "npc", "per_room": True},
                "geometry": [{"id": "rail", "generator": "railing", "params": {"length": 3}, "collision_rules": {"rails": "solid", "rail_height": 1.4}}]}
        r = edl.compile_document(self.doc(room))
        self.assertTrue(r["valid"], r["errors"])
        (rules,) = steps(r, "set_collision_rules")
        self.assertEqual((rules["room_id"], rules["rules"]), ("$e_r", {"actors": "npc", "per_room": True}))
        ops = [s["op"] for s in r["plan"]["steps"]]
        self.assertLess(ops.index("create_room"), ops.index("set_collision_rules"))
        self.assertEqual(steps(r, "create_procedural")[0]["collision_rules"], {"rails": "solid", "rail_height": 1.4})
        param = edl.compile_document(self.doc(dict(room, build="parametric")))
        self.assertTrue(param["valid"], param["errors"])
        self.assertEqual(steps(param, "create_parametric_room")[0]["spec"]["collision_rules"], {"actors": "npc", "per_room": True})
        self.assertEqual(steps(param, "set_collision_rules"), [])
        plain = edl.compile_document(self.doc({"id": "r", "size": [6, 4], "geometry": [{"id": "b", "generator": "box", "params": {}}]}))
        self.assertNotIn("collision_rules", steps(plain, "create_procedural")[0])

    def test_errors(self):
        bad = edl.compile_document(self.doc({"id": "r", "size": [6, 4], "collision_rules": {"mode": "hull", "colour": 1}}))
        errs = " ".join(bad["errors"])
        self.assertIn("collision_rules.mode", errs)
        self.assertIn("collision_rules.colour", errs)
        self.assertFalse(edl.compile_document(self.doc({"id": "r", "size": [6, 4], "collision_rules": "solid"}))["valid"])


if __name__ == "__main__":
    unittest.main()
