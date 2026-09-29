#!/usr/bin/env python3
"""Semantic room types: the offline catalog resolves inheritance like the Lua module, every interior rule and grammar
room type exists, and the MCP tools send the right bridge commands."""
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
LIBRARY = MOD / "grammars" / "library.json"
ROOM_TYPES = MOD / "grammars" / "room_types.json"
ROADMAP = {"clinic", "office", "storage", "security", "maintenance", "corridor", "server_room"}


def call(tool_name, *a, **k):
    tool = getattr(server, tool_name)
    return getattr(tool, "fn", tool)(*a, **k)


def literal_types(value, out):
    """Room types named literally by grammar room operations and set variables."""
    if isinstance(value, dict):
        room = value.get("room")
        if isinstance(room, dict) and isinstance(room.get("type"), str) and not room["type"].startswith("$"):
            out.add(room["type"])
        body = value.get("set")
        if isinstance(body, dict):
            for key in ("room_kind", "kind"):
                if isinstance(body.get(key), str):
                    out.add(body[key].strip("'"))
        for v in value.values():
            literal_types(v, out)
    elif isinstance(value, list):
        for v in value:
            literal_types(v, out)


class CatalogTest(unittest.TestCase):
    def test_catalog_resolves_inheritance(self):
        catalog = server.room_types_offline()
        types_ = catalog["types"]
        self.assertTrue(ROADMAP <= set(types_), ROADMAP - set(types_))
        armory = types_["armory"]
        self.assertEqual(armory["chain"], ["room", "security", "armory"])
        self.assertEqual(armory["traits"], ["security", "military"])
        self.assertIs(armory["spec"]["trim"]["skirting"], False)
        self.assertEqual(armory["populate"], [], "inherit_populate false")
        workshop = types_["workshop"]
        self.assertEqual(workshop["interior"], ["WorkshopInterior"])
        self.assertEqual(workshop["params"]["workbench_surface"], "industrial_surface")
        self.assertEqual(len(workshop["populate"]), 1)
        self.assertEqual(types_["server_room"]["spec"]["floor"], {"type": "raised", "raise": 0.3})

    def test_every_interior_rule_exists(self):
        catalog = server.room_types_offline()
        rules = set(catalog["interior_rules"])
        for tid, t in catalog["types"].items():
            for rule in t["interior"]:
                self.assertIn(rule, rules, f"{tid}: {rule}")

    def test_types_are_valid_documents(self):
        doc = json.loads(ROOM_TYPES.read_text(encoding="utf-8"))
        fields = {"name", "description", "extends", "traits", "tags", "spec", "params", "interior", "populate", "inherit_populate", "size"}
        for tid, t in doc["types"].items():
            self.assertRegex(tid, r"^[a-z_][a-z0-9_]*$")
            self.assertFalse(set(t) - fields, f"{tid}: {set(t) - fields}")
            for key in ("width", "length", "depth", "doors", "windows", "name", "type"):
                self.assertNotIn(key, t.get("spec", {}), f"{tid} spec sets {key}")
            for entry in t.get("populate", []):
                self.assertIn(entry.get("kind", "asset"), server.SURFACE_KINDS)

    def test_grammars_name_known_types(self):
        catalog = server.room_types_offline()
        library = json.loads(LIBRARY.read_text(encoding="utf-8"))
        used: set[str] = set()
        literal_types(library["grammars"], used)
        self.assertTrue(used, "the built-in grammars carry room types")
        self.assertFalse(used - set(catalog["types"]), used - set(catalog["types"]))
        self.assertTrue({"clinic", "office", "storage", "security", "maintenance", "server_room", "corridor"} <= used)

    def test_lua_and_python_agree_on_ids(self):
        lua = (MOD / "modules" / "room_types.lua").read_text(encoding="utf-8")
        self.assertIn("local ID='^[%l_][%l%d_]*$'", lua)
        self.assertIn("LIBRARY_PATH='grammars/room_types.json'", lua)
        self.assertTrue(re.search(r"INTERIORS='room_interiors'", lua))


class RoomTypeToolsTest(unittest.TestCase):
    def run_tool(self, tool_name, *a, **k):
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(tool_name, *a, **k)
        return sent[0]

    def test_library_tools(self):
        self.assertEqual(self.run_tool("room_type_list"), ("room_type_list", {}))
        self.assertEqual(self.run_tool("room_type_get", "clinic"), ("room_type_get", {"type": "clinic"}))
        doc = {"id": "ripperdoc", "extends": "clinic"}
        self.assertEqual(self.run_tool("room_type_save", doc), ("room_type_save", {"doc": doc}))
        self.assertEqual(self.run_tool("room_type_delete", "ripperdoc"), ("room_type_delete", {"type": "ripperdoc"}))
        self.assertEqual(self.run_tool("room_type_rooms", type_id="office", premise_id="p1"), ("room_type_rooms", {"type": "office", "premise_id": "p1"}))
        self.assertEqual(self.run_tool("room_type_reapply", "office"), ("room_type_reapply", {"type": "office"}))
        catalog = json.loads(call("room_type_catalog"))
        self.assertIn("server_room", catalog["types"])

    def test_room_tools(self):
        op, args = self.run_tool("room_type_assign", "r1", "storage", furnish=True, seed=4)
        self.assertEqual(op, "room_type_assign")
        self.assertEqual(args, {"room_id": "r1", "type": "storage", "clear": False, "regenerate": True, "furnish": True, "seed": 4})
        self.assertEqual(self.run_tool("room_type_assign", "r1", clear=True)[1]["clear"], True)
        with self.assertRaises(ValueError):
            call("room_type_assign", "r1")
        self.assertEqual(self.run_tool("room_type_preview", "r1", seed=2), ("room_type_preview", {"room_id": "r1", "seed": 2, "include_plan": False}))
        self.assertEqual(self.run_tool("room_type_furnish", "r1", "office"), ("room_type_furnish", {"room_id": "r1", "type": "office"}))
        self.assertEqual(self.run_tool("room_type_unfurnish", "r1"), ("room_type_unfurnish", {"room_id": "r1"}))

    def test_create_room(self):
        op, args = self.run_tool("room_type_create_room", "server_room", width=6, length=5, position=[1, 2, 3], yaw=90,
                                 spec={"doors": [{"wall": "south"}]}, premise_id="p1")
        self.assertEqual(op, "room_type_create_room")
        self.assertEqual(args["transform"], {"position": {"x": 1.0, "y": 2.0, "z": 3.0, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": 90}})
        self.assertEqual((args["type"], args["width"], args["length"], args["premise_id"], args["furnish"]), ("server_room", 6, 5, "p1", True))
        self.assertNotIn("height", args)
        self.assertEqual(self.run_tool("room_type_create_room", "office", source="camera")[1]["origin"], "camera")
        with self.assertRaises(ValueError):
            call("room_type_create_room", "office", source="moon")


if __name__ == "__main__":
    unittest.main()
