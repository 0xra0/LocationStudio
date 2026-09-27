#!/usr/bin/env python3
"""Cinematic timeline MCP payload contract."""
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


class TimelineMcpTests(unittest.TestCase):
    def test_payloads(self):
        sent: list[tuple[str, dict]] = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.timeline_create, "Intro", duration=20)
            call(server.timeline_add_track, "t1", "npc", target_id="o1", npc_key="42")
            call(server.timeline_add_key, "t1", "tr1", 4.0, {"camera_id": "c1", "transition": "move", "duration": 2})
            call(server.timeline_update_key, "t1", "tr1", "k1", {"time": 5})
            call(server.timeline_update, "t1", duration=40)
            call(server.timeline_update_track, "t1", "tr1", muted=True)
            call(server.timeline_play, "t1", speed=2, start=3)
            call(server.timeline_seek, 6)
            call(server.timeline_pause)
            call(server.timeline_stop)
            call(server.timeline_status)
            call(server.timeline_evaluate, "t1", 2.5)
            call(server.timeline_validate, "t1")
            call(server.timeline_export, "t1")
            call(server.timeline_delete_key, "t1", "tr1", "k1")
            call(server.timeline_delete_track, "t1", "tr1")
            call(server.timeline_get, "t1")
            call(server.timeline_list)
            call(server.timeline_delete, "t1")
            for bad in (lambda: call(server.timeline_create, "x", duration=0),
                        lambda: call(server.timeline_add_track, "t1", "sound"),
                        lambda: call(server.timeline_add_key, "t1", "tr1", -1)):
                with self.assertRaises(ValueError):
                    bad()
        ops = dict(sent)
        self.assertEqual(ops["timeline_create"]["duration"], 20)
        self.assertEqual(ops["timeline_add_track"], {"id": "t1", "kind": "npc", "name": "", "target_id": "o1", "npc_key": "42"})
        self.assertEqual(ops["timeline_add_key"]["key"], {"camera_id": "c1", "transition": "move", "duration": 2, "time": 4.0})
        self.assertEqual(ops["timeline_update"]["patch"], {"duration": 40})
        self.assertEqual(ops["timeline_update_track"]["patch"], {"muted": True})
        self.assertEqual(ops["timeline_play"]["from"], 3)
        self.assertEqual(ops["timeline_export"], {"id": "t1", "path": None})
        self.assertEqual(len(sent), 19)


if __name__ == "__main__":
    unittest.main()
