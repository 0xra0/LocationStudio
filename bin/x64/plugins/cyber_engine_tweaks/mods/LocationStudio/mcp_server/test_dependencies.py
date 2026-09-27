#!/usr/bin/env python3
"""Asset dependency resolver: RDAR index, recursion, statuses, staging, MCP and build stage."""
from __future__ import annotations

import importlib
import json
import struct
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
from lsbuild import dependencies as dep  # noqa: E402


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def write_archive(path: Path, files: dict[str, list[str]] | dict[int, list[int]]) -> None:
    """Minimal RDAR: header, then index with file entries, no segments, dependency table."""
    entries, deps = b"", []
    for key, children in files.items():
        h = key if isinstance(key, int) else dep.path_hash(key)
        d0 = len(deps)
        deps.extend(c if isinstance(c, int) else dep.path_hash(c) for c in children)
        entries += struct.pack("<QqIIIII", h, 0, 0, 0, 0, d0, len(deps)) + b"\0" * 20
    index = struct.pack("<IIQIII", 8, 0, 0, len(files), 0, len(deps)) + entries + b"".join(struct.pack("<Q", d) for d in deps)
    header = struct.pack("<4sIQIQIQ", b"RDAR", 12, 40, len(index), 0, 0, 40 + len(index))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + index)


def depot_json(*paths: str) -> dict:
    return {"Header": {}, "Data": {"RootChunk": {"$type": "CMesh", "materials": [
        {"DepotPath": {"$type": "ResourcePath", "$storage": "string", "$value": p}, "Flags": "Soft"} for p in paths]}}}


class Fixture:
    def __init__(self, root: Path):
        self.root = root
        self.game = root / "game"
        write_archive(self.game / "archive/pc/content/basegame_1.archive", {"base\\materials\\metal.mt": [], "base\\props\\vanilla_chair.mesh": []})
        write_archive(self.game / "archive/pc/ep1/ep1_1.archive", {"ep1\\fx\\steam.particle": []})
        write_archive(self.game / "archive/pc/mod/othermod.archive", {"othermod\\props\\crate.mesh": []})
        (self.game / "r6/tweaks").mkdir(parents=True)
        (self.game / "r6/tweaks/other.yaml").write_text("Items.other_gun:\n  $type: WeaponItem\n", encoding="utf-8")
        self.src = root / "mod_sources"
        mesh = self.src / "wkit/source/raw/mymod/props/chair.mesh.json"
        mesh.parent.mkdir(parents=True)
        mesh.write_text(json.dumps(depot_json("mymod\\materials\\chair.mi", "base\\materials\\metal.mt")), encoding="utf-8")
        mi = self.src / "wkit/source/archive/mymod/materials/chair.mi"
        mi.parent.mkdir(parents=True)
        mi.write_bytes(b"CR2W\x00\x01" + b"mymod\\textures\\chair_d.xbm\x00" + b"base\\materials\\metal.mt\x00" + b"\xff\xfe")
        ent = self.src / "wkit/source/archive/mymod/npc/npc.ent"
        ent.parent.mkdir(parents=True)
        ent.write_bytes(b"CR2W\x00" + b"mymod\\npc\\npc.app\x00" + b"base\\characters\\{gender}_body.mesh\x00")
        app = self.src / "wkit/source/archive/mymod/npc/npc.app"
        app.write_bytes(b"CR2W\x00" + b"base\\props\\vanilla_chair.mesh\x00")
        write_archive(self.src / "prebuilt/lamps.archive", {"mymod\\props\\lamp.mesh": ["base\\materials\\metal.mt", 0x1234]})
        tweaks = self.src / "wkit/source/resources/r6/tweaks"
        tweaks.mkdir(parents=True)
        (tweaks / "npc.yaml").write_text("Character.my_npc:\n  $base: Character.base_npc\n  entityTemplatePath: mymod\\npc\\npc.ent\n", encoding="utf-8")
        sounds = self.src / "sounds/customSounds"
        sounds.mkdir(parents=True)
        (sounds / "info.json").write_text(json.dumps({"customSounds": [{"name": "mymod_hum", "type": "mod_sfx_2d"}]}), encoding="utf-8")
        self.index = root / "data/vanilla-archive-index.bin"
        self.project = {"layers": [{"id": "decoration"}, {"id": "debug", "export": False}], "objects": [
            {"id": "o1", "name": "Chair", "layer": "decoration", "template": "", "metadata": {"world_builder": {"definition_key": "mesh_static", "resource_path": "mymod\\props\\chair.mesh", "entry": {"data": {"spawnData": "mymod\\props\\chair.mesh"}}}}},
            {"id": "o2", "name": "Lamp", "layer": "decoration", "metadata": {"world_builder": {"definition_key": "mesh_static", "resource_path": "mymod\\props\\lamp.mesh"}}},
            {"id": "o3", "name": "NPC", "layer": "decoration", "metadata": {"world_builder": {"definition_key": "entity_record", "resource_path": "Character.my_npc"}}},
            {"id": "o4", "name": "Crate", "layer": "decoration", "template": "othermod\\props\\crate.mesh", "metadata": {}},
            {"id": "o5", "name": "Hum", "layer": "decoration", "metadata": {"world_builder": {"definition_key": "audio", "resource_path": "mymod_hum"}}},
            {"id": "o6", "name": "Ghost", "layer": "decoration", "template": "mymod\\props\\ghost.ent", "metadata": {"npc_population": {"record": "Character.vanilla_guard"}}},
            {"id": "o7", "name": "Debug", "layer": "debug", "template": "mymod\\debug\\marker.ent", "metadata": {}},
            {"id": "o8", "name": "Ref", "layer": "decoration", "template": "mymod\\ref.ent", "metadata": {"reference_area_id": "ra1"}},
            {"id": "o9", "name": "Steam", "layer": "decoration", "metadata": {"vfx": {"resource_path": "ep1\\fx\\steam.particle"}}},
        ]}

    def resolve(self, vanilla=True):
        src = dep.Sources([self.src])
        return dep.resolve(dep.project_roots(self.project), sources=src,
                           vanilla=dep.HashSet.load(self.index) if vanilla else None,
                           mods=dep.mod_archives(self.game), project_tweaks=dep.tweak_records([self.src]),
                           mod_tweaks=dep.tweak_records([self.game / "r6/tweaks"]), sounds=dep.custom_sounds([self.src]))


class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        self.meta = dep.build_index(self.fx.game, self.fx.index)

    def tearDown(self):
        self.tmp.cleanup()

    def test_hash_and_archive_index(self):
        self.assertEqual(dep.normalize("Base/Props/X.MESH"), "base\\props\\x.mesh")
        self.assertEqual(dep.path_hash("base/props/x.mesh"), dep.path_hash("BASE\\props\\x.mesh"))
        self.assertEqual(self.meta["hashes"], 3)
        self.assertEqual(len(self.meta["archives"]), 2)
        vanilla = dep.HashSet.load(self.fx.index)
        self.assertIn(dep.path_hash("base\\materials\\metal.mt"), vanilla)
        self.assertNotIn(dep.path_hash("othermod\\props\\crate.mesh"), vanilla)
        info = dep.read_archive(self.fx.src / "prebuilt/lamps.archive", dependencies=True)
        self.assertEqual(info["dependencies"][dep.path_hash("mymod\\props\\lamp.mesh")], [dep.path_hash("base\\materials\\metal.mt"), 0x1234])
        self.assertTrue(dep.index_info(self.fx.index)["available"])
        with self.assertRaises(ValueError):
            bad = Path(self.tmp.name) / "bad.archive"
            bad.write_bytes(b"NOPE" * 20)
            dep.read_archive(bad)

    def test_project_roots(self):
        roots = {r["object_id"]: r for r in dep.project_roots(self.fx.project)}
        self.assertNotIn("o7", roots, "export-disabled layers are not built")
        self.assertNotIn("o8", roots, "reference-area items are not built")
        self.assertEqual({(r["kind"], r["value"]) for r in roots["o1"]["refs"]}, {("path", "mymod\\props\\chair.mesh")})
        self.assertEqual(roots["o3"]["refs"][0]["kind"], "record")
        self.assertEqual({r["kind"] for r in roots["o6"]["refs"]}, {"path", "record"})
        self.assertEqual(roots["o5"]["refs"][0], {"kind": "audio", "value": "mymod_hum", "field": "world_builder.resource_path"})

    def test_resolve(self):
        r = self.fx.resolve()
        n = r["nodes"]
        self.assertEqual(n["mymod\\props\\chair.mesh"]["status"], "project")
        self.assertEqual(n["mymod\\props\\chair.mesh"]["format"], "json")
        self.assertEqual(n["mymod\\materials\\chair.mi"]["status"], "project")
        self.assertEqual(n["base\\materials\\metal.mt"]["status"], "vanilla")
        self.assertEqual(n["mymod\\textures\\chair_d.xbm"]["status"], "missing")
        self.assertEqual(n["mymod\\textures\\chair_d.xbm"]["chain"],
                         ["object:o1", "mymod\\props\\chair.mesh", "mymod\\materials\\chair.mi", "mymod\\textures\\chair_d.xbm"])
        self.assertEqual(n["mymod\\props\\lamp.mesh"]["status"], "project_archive")
        self.assertEqual(n["#0000000000001234"]["status"], "missing")
        self.assertEqual(n["record:Character.my_npc"]["status"], "project")
        self.assertEqual(n["mymod\\npc\\npc.ent"]["status"], "project")
        self.assertEqual(n["mymod\\npc\\npc.app"]["status"], "project")
        self.assertEqual(n["base\\props\\vanilla_chair.mesh"]["status"], "vanilla")
        self.assertEqual(n["base\\characters\\{gender}_body.mesh"]["status"], "dynamic")
        self.assertEqual(n["record:Character.base_npc"]["status"], "unverified")
        self.assertEqual(n["othermod\\props\\crate.mesh"]["status"], "other_mod")
        self.assertEqual(n["audio:mymod_hum"]["status"], "project")
        self.assertEqual(n["mymod\\props\\ghost.ent"]["status"], "missing")
        self.assertEqual(n["ep1\\fx\\steam.particle"]["status"], "vanilla")
        self.assertFalse(r["ready"])
        self.assertEqual(r["counts"]["missing"], 3)
        self.assertEqual(r["external_requirements"], {"othermod.archive": ["othermod\\props\\crate.mesh"]})
        self.assertEqual(r["raw_json_only"], ["mymod\\props\\chair.mesh"])
        objects = {o["object_id"]: o for o in r["objects"]}
        self.assertEqual(objects["o1"]["missing"], ["mymod\\textures\\chair_d.xbm"])
        self.assertEqual(objects["o2"]["missing"], ["#0000000000001234"])
        self.assertEqual(objects["o3"]["missing"], [])
        self.assertGreaterEqual(objects["o3"]["dependencies"], 4)
        ship = {s["path"] for s in r["ship"]}
        self.assertTrue({"mymod\\materials\\chair.mi", "mymod\\npc\\npc.ent", "record:Character.my_npc", "audio:mymod_hum"} <= ship)
        # Without the vanilla index, unknown instead of missing (never a false "missing").
        r2 = self.fx.resolve(vanilla=False)
        self.assertEqual(r2["nodes"]["base\\materials\\metal.mt"]["status"], "unknown")
        self.assertTrue(r2["ready"])

    def test_stage(self):
        r = self.fx.resolve()
        ws = Path(self.tmp.name) / "ws"
        out = dep.stage(r, ws)
        self.assertTrue((ws / "source/archive/mymod/materials/chair.mi").is_file())
        self.assertTrue((ws / "source/raw/mymod/props/chair.mesh.json").is_file())
        self.assertTrue((ws / "source/resources/r6/tweaks/npc.yaml").is_file())
        self.assertTrue((ws / "source/resources/archive/pc/mod/lamps.archive").is_file())
        self.assertTrue((ws / "source/customSounds/customSounds/info.json").is_file())
        self.assertEqual(out["needs_conversion"], ["mymod\\props\\chair.mesh"])

    def test_mcp_and_build_stage(self):
        root = Path(self.tmp.name)
        project = root / "data/project.json"
        project.write_text(json.dumps(self.fx.project), encoding="utf-8")
        report = root / "exports/dependency-report.json"
        with patch.object(server, "PROJECT", project), patch.object(server, "MOD_SOURCES", self.fx.src), \
                patch.object(server, "VANILLA_INDEX", self.fx.index), patch.object(server, "DEPENDENCY_REPORT", report), \
                patch.object(server, "_send", lambda *a, **k: {"ok": True}):
            scan = call(server.dependency_scan, game_root=str(self.fx.game))
            self.assertFalse(scan["ready"])
            self.assertNotIn("nodes", scan)
            saved = json.loads(report.read_text(encoding="utf-8"))
            self.assertEqual(saved["schema"], "locationstudio-dependencies/1")
            self.assertEqual(len(saved["missing"]), 3)
            check = call(server.dependency_check, ["base/materials/metal.mt", "Character.my_npc", "audio:vanilla_evt", "mymod\\nope.mesh"],
                         game_root=str(self.fx.game))
            self.assertEqual((check["counts"]["vanilla"], check["counts"]["missing"]), (2, 1), "metal.mt and, via the record, vanilla_chair.mesh")
            self.assertEqual(check["objects"][0]["references"]["record:Character.my_npc"], "project")
            self.assertEqual(check["objects"][0]["references"]["audio:vanilla_evt"], "unverified")
            self.assertEqual(call(server.dependency_index_info)["hashes"], 3)
            with self.assertRaises(ValueError):
                call(server.dependency_stage, "nope")


if __name__ == "__main__":
    unittest.main()
