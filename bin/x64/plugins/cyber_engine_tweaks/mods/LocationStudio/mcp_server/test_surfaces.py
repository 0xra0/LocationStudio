#!/usr/bin/env python3
"""Semantic surfaces: the offline vocabulary matches the Lua source, grammars use known tags, and the MCP tools send the right bridge commands."""
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


def call(tool_name, *a, **k):
    tool = getattr(server, tool_name)
    return getattr(tool, "fn", tool)(*a, **k)


def surface_tags(value, out):
    """Every literal surface tag a grammar document uses."""
    if isinstance(value, dict):
        for key, v in value.items():
            if key == "surface":
                if isinstance(v, str):
                    out.add(v)
                elif isinstance(v, dict):
                    for k2, t in v.items():
                        if k2 in {"tag", "top", "bottom", "sides", "px", "nx", "py", "ny", "slope"} and isinstance(t, str):
                            out.add(t)
            elif key == "tags":
                out.update([v] if isinstance(v, str) else v)
            else:
                surface_tags(v, out)
    elif isinstance(value, list):
        for v in value:
            surface_tags(v, out)
    return out


class VocabularyTest(unittest.TestCase):
    def test_offline_vocabulary(self):
        out = json.loads(call("surface_vocabulary"))
        tags = {t["tag"]: t for t in out["tags"]}
        for name in ("floor", "wall", "ceiling", "desk", "shelf", "road", "medical_surface", "industrial_surface", "lab_surface"):
            self.assertIn(name, tags)
        self.assertEqual(tags["ceiling"]["orientation"], "down")
        self.assertEqual(tags["wall"]["orientation"], "side")
        self.assertIn("medical", tags["medical_surface"]["groups"])
        groups = {g["group"] for g in out["groups"]}
        for t in tags.values():
            self.assertTrue(set(t["groups"]) <= groups, t)
        kinds = {k["kind"]: k for k in out["kinds"]}
        self.assertEqual(set(kinds), server.SURFACE_KINDS)
        self.assertEqual(kinds["light"]["tags"], ["ceiling"])
        self.assertGreater(len(tags), 25)

    def test_grammars_use_known_tags(self):
        vocab = json.loads(call("surface_vocabulary"))
        known = {t["tag"] for t in vocab["tags"]} | {g["group"] for g in vocab["groups"]}
        doc = json.loads(LIBRARY.read_text(encoding="utf-8"))
        used = surface_tags(doc["grammars"], set())
        params = {}
        for g in doc["grammars"].values():
            params.update(g.get("params") or {})
        resolved = set()
        for t in used:
            if t.startswith("$"):
                for g in doc["grammars"].values():
                    v = (g.get("params") or {}).get(t[1:])
                    if isinstance(v, str):
                        resolved.add(v)
            else:
                resolved.add(t)
        self.assertTrue(resolved, "the library uses surface tags")
        self.assertFalse(resolved - known, resolved - known)
        self.assertIn("medical_surface", resolved)
        self.assertIn("lab_surface", resolved)


class SurfaceToolsTest(unittest.TestCase):
    def run_tool(self, tool_name, *a, **k):
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(tool_name, *a, **k)
        return sent[0]

    def test_query_and_object(self):
        op, args = self.run_tool("surface_query", premise_id="p1", tags=["work_surface"], traits=["medical"], orientation="up", min_area=0.2)
        self.assertEqual(op, "surface_query")
        self.assertEqual(args, {"premise_id": "p1", "tags": ["work_surface"], "traits": ["medical"], "orientation": "up", "min_area": 0.2, "limit": 200})
        self.assertEqual(self.run_tool("surface_object", "o1"), ("surface_object", {"object_id": "o1"}))
        with self.assertRaises(ValueError):
            call("surface_query", orientation="sideways")

    def test_sample_and_populate(self):
        op, args = self.run_tool("surface_sample", kind="decal", tags=["wall"], room_id="r1", pattern="center", footprint=[1, 0.5], elevation=1.5, seed=3)
        self.assertEqual(op, "surface_sample")
        self.assertEqual((args["kind"], args["pattern"], args["footprint"], args["elevation"], args["seed"], args["room_id"]),
                         ("decal", "center", [1, 0.5], 1.5, "3", "r1"))
        self.assertNotIn("count", args)
        op, args = self.run_tool("surface_populate", kind="asset", item={"asset_query": "mug"}, tags=["desk"], count=4, name="Mug {i}", max_items=10)
        self.assertEqual(op, "surface_populate")
        self.assertEqual((args["asset_query"], args["count"], args["name"], args["max"], args["dry_run"]), ("mug", 4, "Mug {i}", 10, False))
        with self.assertRaises(ValueError):
            call("surface_populate", kind="asset", item={"premise_id": "x"})
        with self.assertRaises(ValueError):
            call("surface_populate", kind="teapot")
        with self.assertRaises(ValueError):
            call("surface_sample", pattern="spiral")

    def test_tagging(self):
        op, args = self.run_tool("surface_tag", "o1", tag="table", inset=0.05, traits=["office"])
        self.assertEqual((op, args["tag"], args["face"], args["inset"], args["traits"]), ("surface_tag", "table", "top", 0.05, ["office"]))
        op, args = self.run_tool("surface_tag", "o1", surfaces=[{"tag": "shelf", "center": [0, 0, 1], "size": [1, 0.4]}])
        self.assertNotIn("tag", args)
        with self.assertRaises(ValueError):
            call("surface_tag", "o1")
        self.assertEqual(self.run_tool("surface_untag", "o1", tag="table"), ("surface_untag", {"object_id": "o1", "tag": "table"}))
        self.assertEqual(self.run_tool("surface_refresh"), ("surface_refresh", {}))

    def test_procedural_surface_option(self):
        op, args = self.run_tool("procedural_create", "box", params={"size": [1, 1, 1]}, position=[0, 0, 0], surface="counter")
        self.assertEqual(args["surface"], "counter")
        op, args = self.run_tool("procedural_update", "o1", clear_surface=True)
        self.assertIs(args["surface"], False)


if __name__ == "__main__":
    unittest.main()
