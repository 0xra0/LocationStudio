#!/usr/bin/env python3
"""Mocked MCP workflow test for saved-camera capture, compare, and explicit acceptance."""
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
from visual_regression import write_rgba_png


class VisualRegressionMcpTests(unittest.TestCase):
    def test_capture_diff_and_accept(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shots = root / "shots"
            shots.mkdir()
            source = shots / "screen.png"
            state = {"pixel": (20, 30, 40, 255)}
            write_rgba_png(source, 2, 2, [state["pixel"]] * 4)

            def mock_screenshot(**_kwargs):
                return json.dumps({"path": str(source), "bytes": source.stat().st_size})

            def mock_send(op, args=None, **_kwargs):
                if op == "capture_player":
                    return {"position": {"x": 1, "y": 2, "z": 3, "w": 1},
                            "rotation": {"roll": 0, "pitch": 0, "yaw": 4}}
                return {"ok": True}

            project = {"cameras": [{"id": "cam-fixed", "name": "Clinic entrance", "fov": 50, "enabled": True}]}
            with patch.object(server, "REGRESSION_DIR", root / "regression"), \
                 patch.object(server, "_project", lambda: project), \
                 patch.object(server, "_send", mock_send), \
                 patch.object(server, "screenshot", Tool(mock_screenshot)), \
                 patch.object(server.time, "sleep", lambda _s: None):
                first = json.loads(server.visual_regression_capture.fn(settle_s=0, fullscreen=False))
                self.assertEqual(first["status"], "captured")
                self.assertTrue(first["complete"])
                self.assertTrue((Path(first["run_dir"]) / first["cameras"][0]["image"]).is_file())
                accepted = json.loads(server.visual_regression_accept.fn(first["run_id"]))
                self.assertTrue(accepted["accepted"])

                same = json.loads(server.visual_regression_capture.fn(settle_s=0, fullscreen=False))
                self.assertEqual(same["status"], "passed")
                self.assertFalse(same["cameras"][0]["regression"])

                state["pixel"] = (255, 0, 0, 255)
                write_rgba_png(source, 2, 2, [state["pixel"]] * 4)
                changed = json.loads(server.visual_regression_capture.fn(settle_s=0, fullscreen=False))
                self.assertEqual(changed["status"], "regression")
                self.assertTrue(changed["cameras"][0]["regression"])
                self.assertTrue(Path(changed["run_dir"], changed["cameras"][0]["comparison"]["diff_image"]).exists())


if __name__ == "__main__":
    unittest.main()
