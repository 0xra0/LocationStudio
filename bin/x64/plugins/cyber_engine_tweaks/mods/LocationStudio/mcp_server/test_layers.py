#!/usr/bin/env python3
"""Layer manager MCP payload contract."""
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


class LayerMcpTests(unittest.TestCase):
    def test_payloads(self):
        sent: list[tuple[str, dict]] = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.layer_list)
            call(server.layer_create, "Set Dressing", color="#ABCDEF", export=False)
            call(server.layer_update, "debug", export=True)
            call(server.layer_set_visible, "decoration", False)
            call(server.layer_set_locked, "shell", True)
            call(server.layer_isolate, "lighting")
            call(server.layer_isolate)
            call(server.layer_select_all, "npc", premise_id="p1")
            call(server.layer_assign, "audio", use_selection=True)
            call(server.layer_auto_assign, apply=True)
            call(server.layer_delete, "layer_x", move_to="gameplay")
            with self.assertRaises(ValueError):
                call(server.layer_update, "debug")
            with self.assertRaises(ValueError):
                call(server.layer_assign, "audio")
        ops = [op for op, _ in sent]
        self.assertEqual(ops, ["layer_list", "layer_create", "layer_update", "layer_set_visible", "layer_set_locked",
                               "layer_isolate", "layer_isolate", "layer_select_all", "layer_assign", "layer_auto_assign",
                               "layer_delete"])
        self.assertEqual(sent[1][1]["export"], False)
        self.assertEqual(sent[2][1], {"id": "debug", "patch": {"export": True}})
        self.assertEqual(sent[6][1], {"id": None})
        self.assertTrue(sent[8][1]["use_selection"])
        self.assertEqual(sent[9][1], {"premise_id": None, "apply": True, "all": False})


if __name__ == "__main__":
    unittest.main()
