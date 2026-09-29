#!/usr/bin/env python3
"""Sector partitioner: the offline parameter table matches the Lua module, every tool sends the right bridge command,
and every op is wired into the Lua bridge (read-only ones allowed during transactions)."""
from __future__ import annotations

import importlib
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
OPS = ["sector_partition_parameters", "sector_partition_preview", "sector_partition_generate", "sector_partition_regenerate",
       "sector_partition_list", "sector_partition_report", "sector_partition_sector_of", "sector_partition_delete", "sector_partition_export"]
READ_ONLY = ["sector_partition_parameters", "sector_partition_preview", "sector_partition_list", "sector_partition_report", "sector_partition_sector_of"]


def call(tool_name, *a, **k):
    tool = getattr(server, tool_name)
    return getattr(tool, "fn", tool)(*a, **k)


class ParametersTest(unittest.TestCase):
    def test_offline_table(self):
        params = {p["name"]: p for p in server.sector_partition_parameters_offline()}
        self.assertEqual(set(params), {"max_nodes", "min_nodes", "max_extent", "loose_cell", "view_distance", "preload", "proximity_gap",
                                       "w_connectivity", "w_traversal", "w_visibility", "w_proximity"})
        self.assertEqual(params["max_nodes"]["default"], 600)
        self.assertEqual((params["max_extent"]["min"], params["max_extent"]["max"]), (8, 2048))
        for p in params.values():
            self.assertTrue(p["min"] <= p["default"] <= p["max"], p)

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


class SectorToolsTest(unittest.TestCase):
    def run_tool(self, tool_name, *a, **k):
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(tool_name, *a, **k)
        return sent[0]

    def test_scope_and_options(self):
        self.assertEqual(self.run_tool("sector_partition_preview", premise_id="p1"), ("sector_partition_preview", {"premise_id": "p1"}))
        op, args = self.run_tool("sector_partition_generate", build_id="b1", params={"max_nodes": 300}, pins={"r1": "hub"},
                                 entry=[1, 2, 3], base_name="yard", navigation_graph_id="nav1", name="Yard")
        self.assertEqual(op, "sector_partition_generate")
        self.assertEqual(args, {"build_id": "b1", "params": {"max_nodes": 300}, "pins": {"r1": "hub"}, "entry": {"x": 1.0, "y": 2.0, "z": 3.0},
                                "base_name": "yard", "navigation_graph_id": "nav1", "name": "Yard"})
        with self.assertRaises(ValueError):
            call("sector_partition_generate")
        with self.assertRaises(ValueError):
            call("sector_partition_generate", premise_id="p1", base_name="Bad Name")
        with self.assertRaises(ValueError):
            call("sector_partition_preview", premise_id="p1", pins={"r1": "bad label"})

    def test_record_tools(self):
        self.assertEqual(self.run_tool("sector_partition_regenerate", "sp1", params={"preload": 30}, pins={"r2": ""}),
                         ("sector_partition_regenerate", {"partition_id": "sp1", "params": {"preload": 30}, "pins": {"r2": ""}}))
        self.assertEqual(self.run_tool("sector_partition_list"), ("sector_partition_list", {}))
        self.assertEqual(self.run_tool("sector_partition_report", "sp1"), ("sector_partition_report", {"partition_id": "sp1"}))
        self.assertEqual(self.run_tool("sector_partition_sector_of", "sp1", "o1"), ("sector_partition_sector_of", {"partition_id": "sp1", "object_id": "o1"}))
        self.assertEqual(self.run_tool("sector_partition_delete", "sp1"), ("sector_partition_delete", {"partition_id": "sp1"}))

    def test_export(self):
        op, args = self.run_tool("sector_partition_export", "sp1", name="wing", sectors=["wing_01"], level=2)
        self.assertEqual(op, "sector_partition_export")
        self.assertEqual(args, {"partition_id": "sp1", "xl_format": 0, "allow_skipped": False, "allow_stale": False, "name": "wing", "sectors": ["wing_01"], "level": 2})
        with self.assertRaises(ValueError):
            call("sector_partition_export", "sp1", name="Wing")

    def test_grammar_sectors(self):
        args = self.run_tool("grammar_generate", "facility", sectors=True, premise_id="p1")[1]
        self.assertIs(args["sectors"], True)
        self.assertNotIn("sectors", self.run_tool("grammar_generate", "facility", premise_id="p1")[1])


if __name__ == "__main__":
    unittest.main()
