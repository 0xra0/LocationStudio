#!/usr/bin/env python3
"""Environment Definition Language: compiler, golden plan and MCP tools."""
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
from lsbuild import edl  # noqa: E402

MOD = Path(__file__).resolve().parents[1]
EXAMPLE = MOD / "edl" / "examples" / "ripperdoc_clinic.edl.yaml"
FIXTURE = MOD.parents[5] / "tests" / "fixtures" / "edl_clinic.plan.json"


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def doc(**extra):
    base = {"edl": 1, "id": "t", "name": "T", "origin": {"position": [0, 0, 0]},
            "floors": [{"id": "g", "height": 3, "rooms": [{"id": "r", "size": [6, 4]}]}]}
    base.update(extra)
    return base


def steps(result, op):
    return [s for s in result["plan"]["steps"] if s["op"] == op]


class CompilerTests(unittest.TestCase):
    def test_example_matches_golden_plan(self):
        r = edl.compile_document(str(EXAMPLE))
        self.assertTrue(r["valid"], r["errors"])
        plan = r["plan"]
        plan["origin"] = {"position": {"x": 100, "y": 200, "z": 10, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": 0}}
        for s in plan["steps"]:
            if s["op"] == "edl_begin":
                s.pop("source", None)
        golden = json.loads(FIXTURE.read_text(encoding="utf-8"))
        self.assertEqual(plan, golden, "regenerate tests/fixtures/edl_clinic.plan.json when the compiler output changes on purpose")
        self.assertEqual(r["counts"]["room"], 2)
        self.assertEqual(r["streaming"], {"category": 1, "level": 1, "cell": {"x": 64.0, "y": 64.0, "z": 32.0}, "range": 80.0})
        self.assertEqual(len(r["resources"]), 4)

    def test_schema_file(self):
        schema = edl.schema()
        self.assertEqual(schema["properties"]["edl"], {"const": 1})
        self.assertIn("floors", schema["properties"])

    def test_frames_parameters_templates_repeat(self):
        r = edl.compile_document(doc(
            parameters={"w": 4},
            templates={"lamp": {"intensity": 50, "radius": 5}},
            floors=[{"id": "g", "height": 3, "rooms": [{"id": "r", "at": [10, 0], "yaw": 90, "size": ["${w * 2}", 4],
                                                        "lights": [{"id": "l", "use": "lamp", "at": [1, 0, 2.5]}],
                                                        "objects": [{"id": "o", "resource": "base\\a.mesh", "at": [0, 0, 0],
                                                                     "repeat": {"count": 3, "step": [1, 0, 0], "yaw_step": 10}}]}]},
                    {"id": "up", "height": 4, "rooms": [{"id": "r2", "size": [4, 4]}]}]))
        self.assertTrue(r["valid"], r["errors"])
        room = steps(r, "create_room")[0]
        self.assertEqual((room["width"], room["x"], room["yaw"]), (8.0, 10.0, 90.0))
        light = steps(r, "create_light")[0]
        self.assertAlmostEqual(light["offset"]["x"], 10.0)
        self.assertAlmostEqual(light["offset"]["y"], 1.0, msg="room yaw 90 turns +x into +y")
        self.assertEqual(light["config"]["intensity"], 50)
        objs = steps(r, "place_resource")
        self.assertEqual([o["as"] for o in objs], ["e_o_1", "e_o_2", "e_o_3"])
        self.assertAlmostEqual(objs[2]["offset"]["y"], 2.0)
        self.assertEqual(objs[2]["yaw"], 110.0)
        upper = steps(r, "create_room")[1]
        self.assertEqual((upper["level"], upper["z"]), (1, 0.0), "floor elevation 3 = level 1 x floor height 3")
        self.assertEqual(len(steps(r, "import_resource")), 1, "resources are imported once")

    def test_geometry(self):
        r = edl.compile_document(doc(floors=[{"id": "g", "height": 3, "rooms": [{"id": "r", "at": [5, 0], "yaw": 90, "size": [6, 4],
            "geometry": [{"id": "st", "generator": "stairs", "params": {"height": 3}, "at": [1, 0, 0], "material": "base\\stone.mesh"}]}]}],
            geometry=[{"id": "w", "generator": "wall", "params": {"length": 4}}]))
        self.assertTrue(r["valid"], r["errors"])
        st = [s for s in r["plan"]["steps"] if s["op"] == "create_procedural"]
        self.assertEqual([s["generator"] for s in st], ["stairs", "wall"])
        self.assertAlmostEqual(st[0]["offset"]["y"], 1.0, msg="room frame applies")
        self.assertEqual(st[0]["material"]["template"], "base\\stone.mesh")
        self.assertTrue(any("material.template" in w for w in r["warnings"]))
        self.assertFalse(edl.compile_document(doc(geometry=[{"id": "x", "generator": "dome"}]))["valid"])

    def test_parametric_room(self):
        room = {"id": "clinic", "at": [2, 3], "yaw": 90, "size": [6, 4], "build": "parametric", "walls": {"thickness": 0.25},
                "doors": [{"wall": "south", "offset": -1}], "windows": [{"wall": "east", "width": 1.5, "mullions_x": 1}],
                "parametric": {"ceiling": {"type": "beams"}, "materials": {"walls": "base\\plaster.mi"}, "lighting": {"anchors": "center"}},
                "geometry": [{"id": "st", "generator": "box", "params": {"size": [1, 1, 1]}, "at": [1, 0, 0]}]}
        r = edl.compile_document(doc(floors=[{"id": "g", "height": 3, "rooms": [room]}]))
        self.assertTrue(r["valid"], r["errors"])
        self.assertEqual(steps(r, "create_room"), [])
        self.assertEqual(steps(r, "add_opening"), [])
        (pr,) = steps(r, "create_parametric_room")
        self.assertEqual(pr["offset"], {"x": 2, "y": 3, "z": 0})
        self.assertEqual(pr["yaw"], 90)
        spec = pr["spec"]
        self.assertEqual((spec["width"], spec["length"], spec["height"], spec["wall_thickness"]), (6, 4, 3, 0.25))
        self.assertEqual(spec["doors"], [{"wall": "south", "offset": -1, "height": 2.1}])
        self.assertEqual(spec["windows"][0]["sill"], 1.0)
        self.assertEqual(spec["ceiling"]["type"], "beams")
        self.assertEqual(steps(r, "create_procedural")[0]["offset"]["x"], 2.0, msg="room elements use the room frame")
        bad = dict(room, parametric={"roof": "flat"})
        self.assertFalse(edl.compile_document(doc(floors=[{"id": "g", "height": 3, "rooms": [bad]}]))["valid"])
        self.assertFalse(edl.compile_document(doc(floors=[{"id": "g", "height": 3, "rooms": [dict(room, build="csg")]}]))["valid"])
        self.assertFalse(edl.compile_document(doc(floors=[{"id": "g", "height": 3, "rooms": [dict(room, doors=[{"wall": "south", "offset": 2.8}])]}]))["valid"])

    def test_errors(self):
        cases = {
            "duplicate id": doc(objects=[{"id": "r", "resource": "base\\a.mesh"}]),
            "unknown top-level key": doc(bogus=1),
            "must be north": doc(floors=[{"id": "g", "rooms": [{"id": "r", "size": [4, 4], "doors": [{"wall": "up"}]}]}]),
            "does not fit": doc(floors=[{"id": "g", "rooms": [{"id": "r", "size": [4, 4], "doors": [{"wall": "north", "width": 5}]}]}]),
            "unknown template": doc(objects=[{"id": "o", "use": "nope"}]),
            "cannot infer": doc(objects=[{"id": "o", "resource": "base\\a.png"}]),
            "Character.*": doc(npcs=[{"id": "n", "record": "Items.x"}]),
            "unknown workspot": doc(npcs=[{"id": "n", "record": "Character.a", "route": {"waypoints": [{"workspot": "ghost"}]}}]),
            "not a placed element": doc(logic=[{"id": "g1", "nodes": [{"id": "a", "kind": "switch", "element": "r"}]}]),
            "unknown parameter": doc(objects=[{"id": "o", "resource": "base\\a.mesh", "at": ["${nope}", 0, 0]}]),
            "only numbers": doc(parameters={"a": 1}, objects=[{"id": "o", "resource": "base\\a.mesh", "at": ["${__import__('os')}", 0, 0]}]),
            "LootTables": doc(devices=[{"id": "d", "kind": "loot_container", "resource": "base\\c.ent"}]),
            "reverb needs": doc(audio={"reverb": [{"room": "ghost"}]}),
            "unknown room": doc(lights=[{"id": "l", "room": "ghost"}]),
            "must be 1": doc(edl=2),
            "stable document id": doc(id="bad id"),
            "from/to": doc(navigation={"nodes": [{"id": "a", "at": [0, 0, 0]}], "edges": [{"from": "a", "to": "b"}]}),
        }
        for needle, d in cases.items():
            r = edl.compile_document(d)
            self.assertFalse(r["valid"], needle)
            self.assertTrue(any(needle in e for e in r["errors"]), (needle, r["errors"]))

    def test_json_text_yaml_and_overrides(self):
        text = json.dumps(doc(parameters={"h": 3}, floors=[{"id": "g", "height": "${h}", "rooms": [{"id": "r", "size": [4, 4]}]}]))
        r = edl.compile_document(text, parameters={"h": 5})
        self.assertTrue(r["valid"], r["errors"])
        self.assertEqual(steps(r, "create_room")[0]["height"], 5)
        y = edl.compile_document("edl: 1\nid: y\nfloors:\n  - id: g\n    rooms:\n      - {id: r, size: [3, 3]}\n")
        self.assertTrue(y["valid"], y["errors"])
        self.assertEqual(y["plan"]["origin"], "player")
        self.assertFalse(edl.compile_document("edl: [1\n")["valid"])
        self.assertFalse(edl.compile_document("/nope/missing.edl.yaml")["valid"])


class ToolTests(unittest.TestCase):
    def test_tools(self):
        sent: list[tuple[str, dict]] = []

        def fake_send(op, args=None, **_k):
            sent.append((op, args or {}))
            if op == "execute_authoring_plan":
                return {"executed": True, "edl": {"doc": "ripperdoc_clinic", "premise_id": "p1"}}
            if op == "edl_get":
                return {"id": "ripperdoc_clinic", "premise_id": "p1"}
            return {"ok": True}

        builds: list[dict] = []

        def fake_build(name, **kw):
            builds.append({"name": name, **kw})
            return json.dumps({"ran": kw.get("run"), "ok": True})

        with tempfile.TemporaryDirectory() as td, patch.object(server, "_send", fake_send), \
                patch.object(server, "EDL_EXPORTS", Path(td)), patch.object(server, "build_mod_from_project", fake_build), \
                patch.object(server, "preflight_run", lambda **k: json.dumps({"ready": k.get("premise_id") == "p1", "summary": {}})):
            self.assertIn("floors", call(server.edl_schema)["schema"]["properties"])
            v = call(server.edl_validate, str(EXAMPLE))
            self.assertTrue(v["valid"])
            self.assertNotIn("plan", v)
            c = call(server.edl_compile, "edl/examples/ripperdoc_clinic.edl.yaml", include_plan=True)
            self.assertTrue(Path(c["plan_file"]).is_file())
            self.assertEqual(c["plan"]["version"], 2)
            bad = call(server.edl_validate, document=doc(bogus=1))
            self.assertFalse(bad["valid"])
            with self.assertRaises(ValueError):
                call(server.edl_apply, document=doc(bogus=1))
            with self.assertRaises(ValueError):
                call(server.edl_validate)
            applied = call(server.edl_apply, str(EXAMPLE))
            self.assertTrue(applied["applied"]["executed"])
            self.assertEqual(sent[-1][0], "execute_authoring_plan")
            self.assertEqual(sent[-1][1]["plan"]["steps"][0]["op"], "edl_begin")
            out = call(server.edl_build, str(EXAMPLE), run=True)
            self.assertTrue(out["built"])
            self.assertEqual(builds[-1]["name"], "ripperdoc_clinic")
            self.assertEqual((builds[-1]["premise_id"], builds[-1]["category"], builds[-1]["level"], builds[-1]["streaming_x"]), ("p1", 1, 1, 64.0))
            call(server.edl_list)
            call(server.edl_get, "ripperdoc_clinic")
            call(server.edl_remove, "ripperdoc_clinic")
            self.assertEqual([op for op, _ in sent[-3:]], ["edl_list", "edl_get", "edl_remove"])
        with patch.object(server, "_send", fake_send), patch.object(server, "build_mod_from_project", fake_build), \
                patch.object(server, "preflight_run", lambda **k: json.dumps({"ready": False, "blocking": [{"check": "spawns"}]})):
            stopped = call(server.edl_build, str(EXAMPLE), run=True)
            self.assertEqual(stopped["stopped"], "preflight")
            self.assertFalse(stopped["built"])


if __name__ == "__main__":
    unittest.main()
