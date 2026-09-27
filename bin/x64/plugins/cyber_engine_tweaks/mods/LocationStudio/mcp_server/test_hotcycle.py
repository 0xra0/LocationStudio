#!/usr/bin/env python3
"""Small filesystem-only test for script deploy ordering and pose safety."""
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
    def __init__(self, *_args, **_kwargs):
        pass

    def tool(self):
        return lambda fn: Tool(fn)

    def resource(self, *_args, **_kwargs):
        return lambda fn: fn


fake_server = types.ModuleType("mcp.server")
fake_server.MCPServer = MCPServer
fake_mcp = types.ModuleType("mcp")
fake_mcp.server = fake_server
sys.modules.setdefault("mcp", fake_mcp)
sys.modules.setdefault("mcp.server", fake_server)
sys.path.insert(0, str(Path(__file__).resolve().parent))
server = importlib.import_module("server")


class HotcycleTests(unittest.TestCase):
    def test_script_is_reloaded_before_respawn_and_old_pose_requires_ack(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            game = root / "game"
            rht = game / "red4ext/plugins/RedHotTools"
            rht.mkdir(parents=True)
            hot = game / "archive/pc/hot"
            hot.mkdir(parents=True)
            log = rht / "RedHotTools-test.log"
            log.write_text("boot\n", encoding="utf-8")
            source = root / "Glue.reds"
            source.write_text("new pose\n", encoding="utf-8")
            archive = root / "demo.archive"
            archive.write_bytes(b"archive")
            dest = game / "r6/scripts/Test/Glue.reds"
            dest.parent.mkdir(parents=True)
            dest.write_text("old pose\n", encoding="utf-8")
            sent = []
            events = []

            def sleep(_seconds):
                with log.open("a", encoding="utf-8") as stream:
                    stream.write("Scripts reload completed\n")
                events.append("script_reloaded")

            archive_tool = Tool(lambda **_kwargs: events.append("archive_loaded") or json.dumps({"files": [], "pending_in_hot": []}))
            visual_tool = Tool(lambda **_kwargs: events.append("visual") or json.dumps({"status": "passed", "run_id": "test"}))
            def send(op, *_args, **_kwargs):
                events.append("respawn")
                sent.append(op)
                return {"deleted": True}

            with patch.object(server, "GAME_DIR", game), patch.object(server, "_rht_log", lambda: log), \
                 patch.object(server.time, "sleep", sleep), patch.object(server, "_send", send), \
                 patch.object(server, "hot_reload_archives", archive_tool), \
                 patch.object(server, "visual_regression_capture", visual_tool):
                with self.assertRaisesRegex(ValueError, "Pose changes live in the .reds"):
                    server.hotcycle_rebuild.fn(respawn_tags=["prop"], system="Test.Glue")
                result = server.hotcycle_rebuild.fn(
                    script_files={"r6/scripts/Test/Glue.reds": str(source)},
                    archives=[str(archive)], respawn_tags=["prop"], system="Test.Glue",
                    capture_visuals=True, visual_camera_ids=["cam-1"], visual_settle_s=0)
                self.assertEqual(dest.read_text(encoding="utf-8"), "new pose\n")
                self.assertTrue(list(dest.parent.glob("Glue.reds.bak-*")))
                self.assertTrue(result.find('"reloaded": true') >= 0)
                self.assertEqual(sent, ["respawn_tagged"])
                self.assertEqual(events, ["script_reloaded", "archive_loaded", "respawn", "visual"])
                self.assertEqual(json.loads(result)["visual_regression"]["status"], "passed")
                forced = server.hotcycle_rebuild.fn(script_files={"r6/scripts/Test/Glue.reds": str(source)},
                                                     respawn_tags=["prop"], system="Test.Glue")
                self.assertTrue(json.loads(forced)["script"]["forced_recompile"])
                acknowledged = server.hotcycle_rebuild.fn(respawn_tags=["prop"], system="Test.Glue", allow_current_script=True)
                self.assertTrue(json.loads(acknowledged)["used_current_script_without_deploy"])

    def test_script_destination_cannot_escape_game(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rht = root / "red4ext/plugins/RedHotTools"
            rht.mkdir(parents=True)
            log = rht / "RedHotTools-test.log"
            log.write_text("boot\n", encoding="utf-8")
            source = root / "Glue.reds"
            source.write_text("pose\n", encoding="utf-8")
            with patch.object(server, "GAME_DIR", root), patch.object(server, "_rht_log", lambda: log):
                with self.assertRaisesRegex(ValueError, "destination must"):
                    server._deploy_redscripts_wait({"../outside.reds": str(source)}, 5)


if __name__ == "__main__":
    unittest.main()
