#!/usr/bin/env python3
"""Spline editor MCP payload contract."""
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


class SplineMcpTests(unittest.TestCase):
    def test_payloads(self):
        sent: list[tuple[str, dict]] = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.spline_create, "Road", points=[[0, 0, 0], {"x": 10, "y": 0, "z": 0}], closed=False, mode="linear")
            call(server.spline_create, "Start", source="aim")
            call(server.spline_add_point, "s1", position=[5, 5, 0], index=2)
            call(server.spline_add_point, "s1", source="player")
            call(server.spline_insert_point, "s1", 12.5)
            call(server.spline_update_point, "s1", 2, mode="aligned", handle_out=[2, 0, 0])
            call(server.spline_delete_point, "s1", 3)
            call(server.spline_update, "s1", closed=True, tension=0.3)
            call(server.spline_sample, "s1", spacing=2)
            call(server.spline_apply_use, "s1", "camera_path", {"count": 6, "look_at": [1, 2, 3]})
            call(server.spline_regenerate, "s1")
            call(server.spline_remove_use, "s1", "u1", keep_outputs=True)
            call(server.spline_preview, "s1", spacing=0.5)
            call(server.spline_preview_clear)
            call(server.spline_delete, "s1")
            call(server.spline_list)
            for bad in (lambda: call(server.spline_create, "x"), lambda: call(server.spline_create, "x", points=[[1, 2]]),
                        lambda: call(server.spline_create, "x", source="aim", mode="curvy"),
                        lambda: call(server.spline_add_point, "s1"), lambda: call(server.spline_update_point, "s1", 1),
                        lambda: call(server.spline_apply_use, "s1", "teleport")):
                with self.assertRaises(ValueError):
                    bad()
        ops = [op for op, _ in sent]
        self.assertEqual(ops, ["spline_create", "spline_create", "spline_add_point", "spline_add_point", "spline_insert_point",
                               "spline_update_point", "spline_delete_point", "spline_update", "spline_sample", "spline_apply_use",
                               "spline_regenerate", "spline_remove_use", "spline_preview", "spline_preview_clear",
                               "spline_delete", "spline_list"])
        self.assertEqual(sent[0][1]["points"], [{"x": 0.0, "y": 0.0, "z": 0.0}, {"x": 10.0, "y": 0.0, "z": 0.0}])
        self.assertEqual(sent[2][1], {"id": "s1", "mode": "auto", "position": {"x": 5.0, "y": 5.0, "z": 0.0}, "index": 2})
        self.assertEqual(sent[5][1]["patch"], {"mode": "aligned", "handle_out": {"x": 2.0, "y": 0.0, "z": 0.0}})
        self.assertEqual(sent[9][1]["params"]["look_at"], {"x": 1.0, "y": 2.0, "z": 3.0})


if __name__ == "__main__":
    unittest.main()
