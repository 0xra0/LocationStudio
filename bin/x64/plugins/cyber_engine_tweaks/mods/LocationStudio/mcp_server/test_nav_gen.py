#!/usr/bin/env python3
"""Navigation generator: the offline parameter table matches the Lua module, every tool sends the right bridge
command, and every op is wired into the Lua bridge (read-only ones allowed during transactions)."""
from __future__ import annotations

import importlib
import json
import re
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

MOD = Path(__file__).resolve().parent.parent
BRIDGE = (MOD / "modules" / "bridge.lua").read_text(encoding="utf-8")
NAV = (MOD / "modules" / "nav_gen.lua").read_text(encoding="utf-8")
OPS = ["nav_parameters", "nav_preview", "nav_generate", "nav_regenerate", "nav_report", "nav_delete", "nav_validate_plan",
       "nav_validate_start", "nav_validate_status", "nav_validate_cancel"]
READ_ONLY = ["nav_parameters", "nav_preview", "nav_report", "nav_validate_plan", "nav_validate_status"]


def call(tool_name, *a, **k):
    tool = getattr(server, tool_name)
    return getattr(tool, "fn", tool)(*a, **k)


class ParametersTest(unittest.TestCase):
    def test_offline_table(self):
        params = {p["name"]: p for p in server.nav_parameters_offline()}
        self.assertEqual(set(params), {"cell", "agent_radius", "agent_height", "max_step", "max_slope", "max_drop", "max_jump", "max_climb", "tile", "door_snap"})
        self.assertEqual(params["cell"]["default"], 0.25)
        self.assertEqual((params["agent_radius"]["min"], params["agent_radius"]["max"]), (0.1, 1.5))
        for p in params.values():
            self.assertTrue(p["min"] <= p["default"] <= p["max"], p)
        out = json.loads(call("nav_parameters"))
        self.assertEqual(set(out["leg_kinds"]), server.NAV_LEG_KINDS)

    def test_leg_kinds_match_lua(self):
        lua = set(re.search(r"local LEG_KINDS=\{(.*?)\}", NAV).group(1).replace("=true", "").split(","))
        self.assertEqual(lua, server.NAV_LEG_KINDS)

    def test_bridge_wiring(self):
        for op in OPS:
            self.assertIn(f"op == '{op}'", BRIDGE, op)
        allowlists = re.findall(r"local allowed=\{(.*?)\}", BRIDGE)
        self.assertEqual(len(allowlists), 3)
        for allowed in allowlists:
            for op in READ_ONLY:
                self.assertIn(f"{op}=true", allowed)
            for op in set(OPS) - set(READ_ONLY):
                self.assertNotIn(f"{op}=true", allowed)


class NavToolsTest(unittest.TestCase):
    def run_tool(self, tool_name, *a, **k):
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(tool_name, *a, **k)
        return sent[0]

    def test_scope(self):
        self.assertEqual(self.run_tool("nav_preview", premise_id="p1"), ("nav_preview", {"premise_id": "p1"}))
        self.assertEqual(self.run_tool("nav_preview", room_ids=["r1", "r2"], params={"cell": 0.5})[1], {"room_ids": ["r1", "r2"], "params": {"cell": 0.5}})
        self.assertEqual(self.run_tool("nav_generate", build_id="b1", premise_id="ignored")[1], {"build_id": "b1"})
        self.assertEqual(self.run_tool("nav_generate", all_rooms=True, name="Yard", entry=[1, 2, 3])[1],
                         {"all": True, "name": "Yard", "entry": {"x": 1.0, "y": 2.0, "z": 3.0}})
        with self.assertRaises(ValueError):
            call("nav_generate")

    def test_graph_tools(self):
        self.assertEqual(self.run_tool("nav_regenerate", "g1", params={"max_climb": 1}), ("nav_regenerate", {"graph_id": "g1", "params": {"max_climb": 1}}))
        self.assertEqual(self.run_tool("nav_report", "g1"), ("nav_report", {"graph_id": "g1"}))
        self.assertEqual(self.run_tool("nav_delete", "g1"), ("nav_delete", {"graph_id": "g1"}))

    def test_validation_tools(self):
        op, args = self.run_tool("nav_validate_plan", "g1", legs=["door", "stairs"], custom=[{"start": [0, 0, 0], "goal": {"x": 1, "y": 2, "z": 3}}])
        self.assertEqual(op, "nav_validate_plan")
        self.assertEqual(args["legs"], ["door", "stairs"])
        self.assertEqual(args["custom"][0]["goal"], {"x": 1.0, "y": 2.0, "z": 3.0})
        with self.assertRaises(ValueError):
            call("nav_validate_plan", "g1", legs=["teleport"])
        op, args = self.run_tool("nav_validate_start", "g1", npc_key="812", tolerance=1.0)
        self.assertEqual(op, "nav_validate_start")
        self.assertEqual((args["npc_key"], args["tolerance"], args["ignore_navigation"], args["run"]), ("812", 1.0, False, False))
        self.assertNotIn("record", args)
        args = self.run_tool("nav_validate_start", "g1", record="Character.stand_in", appearance="a")[1]
        self.assertEqual((args["record"], args["appearance"]), ("Character.stand_in", "a"))
        with self.assertRaises(ValueError):
            call("nav_validate_start", "g1", tolerance=10)
        self.assertEqual(self.run_tool("nav_validate_status"), ("nav_validate_status", {}))
        self.assertEqual(self.run_tool("nav_validate_cancel"), ("nav_validate_cancel", {}))

    def test_grammar_navigation(self):
        args = self.run_tool("grammar_generate", "facility", navigation=True, premise_id="p1")[1]
        self.assertIs(args["navigation"], True)
        self.assertNotIn("navigation", self.run_tool("grammar_generate", "facility", premise_id="p1")[1])


if __name__ == "__main__":
    unittest.main()
