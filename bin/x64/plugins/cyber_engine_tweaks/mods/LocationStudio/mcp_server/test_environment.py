#!/usr/bin/env python3
"""Environment preview MCP contract and deterministic visual-regression capture."""
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
from visual_regression import write_rgba_png  # noqa: E402


def call(tool, *args, **kwargs):
    return json.loads(getattr(tool, "fn", tool)(*args, **kwargs))


RAINY = {"id": "env-rain", "name": "Rainy night", "time": {"enabled": True, "hour": 22, "minute": 30},
         "weather": {"enabled": True, "state": "24h_weather_rain", "blend_time": 0, "priority": 9},
         "fog": {"enabled": False}, "exposure_note": ""}
NOON = {**RAINY, "id": "env-noon", "name": "Noon", "time": {"enabled": True, "hour": 12, "minute": 0},
        "weather": {"enabled": True, "state": "24h_weather_sunny", "blend_time": 0, "priority": 9}}


class EnvironmentMcpTests(unittest.TestCase):
    def test_tools_send_only_given_fields(self):
        sent: list[tuple[str, dict]] = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.environment_create, "Rainy night", hour=22, minute=30, weather_state="24h_weather_rain",
                 fog_enabled=True, fog_size_x=40, fog_size_y=30, fog_size_z=12, fog_color=[0.8, 0.8, 1])
            call(server.environment_update, "env-1", minute=45)
            call(server.environment_preview, "env-1", force=True)
            call(server.environment_force, False)
            call(server.environment_status)
            call(server.environment_restore)
            call(server.environment_delete, "env-1")
            for bad in (lambda: call(server.environment_create, "x", weather_state="rain; drop"),
                        lambda: call(server.environment_create, "x", fog_anchor="moon"),
                        lambda: call(server.environment_create, "x", fog_size_x=4),
                        lambda: call(server.environment_create, "x", fog_color=[2, 0, 0])):
                with self.assertRaises(ValueError):
                    bad()
        ops = [op for op, _ in sent]
        self.assertEqual(ops, ["environment_create", "environment_update", "environment_preview", "environment_force",
                               "environment_status", "environment_restore", "environment_delete"])
        create = sent[0][1]
        self.assertEqual(create["fog_size"], {"x": 40, "y": 30, "z": 12})
        self.assertEqual(create["weather_state"], "24h_weather_rain")
        self.assertNotIn("time_enabled", create)
        self.assertEqual(sent[1][1], {"id": "env-1", "patch": {"minute": 45}})
        self.assertEqual(sent[2][1], {"id": "env-1", "force": True})

    def test_capture_forces_and_restores_environment(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "screen.png"
            write_rgba_png(source, 2, 2, [(20, 30, 40, 255)] * 4)
            sent: list[tuple[str, dict]] = []

            def mock_send(op, args=None, **_kwargs):
                sent.append((op, args or {}))
                if op == "capture_player":
                    return {"position": {"x": 1, "y": 2, "z": 3, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": 0}}
                if op == "environment_preview":
                    return {"active": True, "applied": {"time": {"hour": 22, "minute": 30}}, "warning": None}
                return {"ok": True}

            project = {"cameras": [{"id": "cam", "name": "Front", "enabled": True}], "environments": [RAINY, NOON]}
            with patch.object(server, "REGRESSION_DIR", root / "regression"), \
                 patch.object(server, "_project", lambda: project), \
                 patch.object(server, "_send", mock_send), \
                 patch.object(server, "screenshot", Tool(lambda **_k: json.dumps({"path": str(source)}))), \
                 patch.object(server.time, "sleep", lambda _s: None):
                first = call(server.visual_regression_capture, settle_s=0, fullscreen=False, environment_id="env-rain")
                ops = [op for op, _ in sent]
                self.assertLess(ops.index("environment_preview"), ops.index("preview_camera"))
                self.assertEqual(ops[-1], "environment_restore", "the original conditions are restored after the series")
                self.assertEqual(sent[ops.index("environment_preview")][1], {"id": "env-rain", "force": True})
                self.assertEqual(first["environment"]["id"], "env-rain")
                self.assertEqual(first["environment_applied"]["time"]["hour"], 22)
                call(server.visual_regression_accept, first["run_id"])

                same = call(server.visual_regression_capture, settle_s=0, fullscreen=False, environment_id="env-rain")
                self.assertEqual(same["status"], "passed")
                self.assertFalse(same["environment_mismatch"])

                other = call(server.visual_regression_capture, settle_s=0, fullscreen=False, environment_id="env-noon")
                self.assertTrue(other["environment_mismatch"])
                self.assertIn("different environment", other["environment_note"])

                with self.assertRaises(ValueError):
                    call(server.visual_regression_capture, settle_s=0, environment_id="missing")

    def test_restore_runs_even_when_a_shot_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            sent: list[str] = []

            def mock_send(op, args=None, **_kwargs):
                sent.append(op)
                if op == "capture_player":
                    return {"position": {"x": 0, "y": 0, "z": 0, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": 0}}
                if op == "preview_camera":
                    raise RuntimeError("camera bridge offline")
                return {"ok": True}

            project = {"cameras": [{"id": "cam", "enabled": True}], "environments": [RAINY]}
            with patch.object(server, "REGRESSION_DIR", Path(tmp) / "regression"), \
                 patch.object(server, "_project", lambda: project), \
                 patch.object(server, "_send", mock_send), \
                 patch.object(server.time, "sleep", lambda _s: None):
                result = call(server.visual_regression_capture, settle_s=0, environment_id="env-rain")
            self.assertFalse(result["complete"])
            self.assertIn("environment_restore", sent)


if __name__ == "__main__":
    unittest.main()
