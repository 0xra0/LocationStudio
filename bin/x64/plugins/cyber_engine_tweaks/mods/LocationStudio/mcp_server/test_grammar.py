#!/usr/bin/env python3
"""Environment grammar: the shipped library is well formed and the MCP tools send the right bridge commands."""
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

LIBRARY = Path(__file__).resolve().parent.parent / "grammars" / "library.json"
STRUCTURAL = {"split", "repeat", "place", "walls", "call", "choose", "chance", "set"}
TERMINALS = {"room", "door", "window", "geometry", "asset", "light", "volume", "marker"}
META = {"if", "name", "comment"}


def call(name, *a, **k):
    tool = getattr(server, name)
    return getattr(tool, "fn", tool)(*a, **k)


def rules_of(grammars, gid, seen=()):
    g = grammars[gid]
    inc = g.get("include") or []
    inc = [inc] if isinstance(inc, str) else inc
    out = {}
    for other in inc:
        assert other in grammars and other not in seen, (gid, other)
        out.update(rules_of(grammars, other, seen + (gid,)))
    out.update(g.get("rules") or {})
    return out


def references(ops, found):
    for op in ops:
        if isinstance(op, str):
            found.add(op)
            continue
        kinds = [k for k in op if k in STRUCTURAL or k in TERMINALS]
        assert len(kinds) == 1 and all(k in STRUCTURAL or k in TERMINALS or k in META for k in op), op
        body = op[kinds[0]]
        children = []
        if kinds[0] == "split":
            children = body["parts"]
        elif kinds[0] in {"repeat", "place", "walls", "chance"}:
            children = [body] + ([body["else"]] if isinstance(body, dict) and "else" in body else [])
        elif kinds[0] == "choose":
            children = body.get("options", body) if isinstance(body, dict) else body
        elif kinds[0] == "call":
            children = [{"symbol": body}] if isinstance(body, str) else [body]
        for c in children:
            if "symbol" in c:
                found.add(c["symbol"])
            if "do" in c:
                references(c["do"], found)


class GrammarLibraryTest(unittest.TestCase):
    def setUp(self):
        self.doc = json.loads(LIBRARY.read_text(encoding="utf-8"))
        self.grammars = self.doc["grammars"]

    def test_shipped_grammars(self):
        self.assertTrue({"common", "corridor", "industrial", "clinic", "apartment", "bunker", "laboratory"} <= set(self.grammars))
        for gid in self.grammars:
            rules = rules_of(self.grammars, gid)
            found: set[str] = set()
            for name, rule in rules.items():
                if isinstance(rule, list):
                    references(rule, found)
                elif "variants" in rule:
                    for v in rule["variants"]:
                        references(v["do"], found)
                else:
                    references(rule["do"], found)
            self.assertFalse(found - set(rules), (gid, found - set(rules)))
            start = self.grammars[gid].get("start")
            if start:
                self.assertIn(start, rules)
                self.assertEqual(len(self.grammars[gid]["size"]), 3)

    def test_schema_tool_is_offline(self):
        out = json.loads(call("grammar_schema"))
        self.assertIn("repeat", out["schema"]["structural"])
        self.assertIn("door", out["schema"]["terminals"])
        self.assertEqual(out["builtin"]["corridor"]["start"], "Corridor")
        self.assertIn("CableTray", out["builtin"]["common"]["rules"])


class GrammarToolsTest(unittest.TestCase):
    def run_tool(self, name, *a, **k):
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(name, *a, **k)
        return sent[0]

    def test_preview_and_generate(self):
        op, args = self.run_tool("grammar_preview", grammar="clinic", params={"room_width": 6}, seed=3, position=[1, 2, 3], yaw=90)
        self.assertEqual(op, "grammar_preview")
        self.assertEqual(args["transform"]["position"], {"x": 1.0, "y": 2.0, "z": 3.0, "w": 1})
        self.assertEqual(args["transform"]["rotation"]["yaw"], 90)
        self.assertEqual((args["grammar"], args["seed"], args["params"]), ("clinic", 3, {"room_width": 6}))
        op, args = self.run_tool("grammar_generate", grammar="bunker", source="camera", build_id="b1", size=[30, 20, 3])
        self.assertEqual((op, args["origin"], args["build_id"], args["size"]), ("grammar_generate", "camera", "b1", [30.0, 20.0, 3.0]))
        self.assertNotIn("premise_id", args)
        with self.assertRaises(ValueError):
            call("grammar_generate")
        with self.assertRaises(ValueError):
            call("grammar_preview", grammar="corridor", source="aim")

    def test_library_ops(self):
        self.assertEqual(self.run_tool("grammar_regenerate", "b1", seed=4), ("grammar_regenerate", {"build_id": "b1", "params": {}, "seed": 4}))
        self.assertEqual(self.run_tool("grammar_remove", "b1"), ("grammar_remove", {"build_id": "b1"}))
        self.assertEqual(self.run_tool("grammar_save", {"id": "x", "rules": {}})[0], "grammar_save")
        self.assertEqual(self.run_tool("grammar_get", "clinic"), ("grammar_get", {"id": "clinic"}))
        self.assertEqual(self.run_tool("grammar_builds")[0], "grammar_builds")


if __name__ == "__main__":
    unittest.main()
