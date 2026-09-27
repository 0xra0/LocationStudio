#!/usr/bin/env python3
"""Material resource generator: .mi documents, variants, textures, verification, Build Mod stage and tools."""
from __future__ import annotations

import importlib
import json
import stat
import struct
import sys
import tempfile
import types
import unittest
import zlib
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
from lsbuild import edl  # noqa: E402
from lsbuild import materials as mat  # noqa: E402
from lsbuild import meshres as mr  # noqa: E402
from lsbuild import procedural as pg  # noqa: E402
from lsbuild.build import MANIFEST_SCHEMA  # noqa: E402

BASE = "base\\materials\\metal_base.remt"


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def tile(**extra):
    d = {"key": "tile", "preset": "metal_base", "base": BASE, "path": "mod\\ls\\materials\\tile.mi",
         "params": {"roughness": 0.6, "tint": [1, 0.9, 0.8, 1], "uv_scale": [2, 2], "tiling": [2, 1]},
         "textures": {"base_color": {"solid": [0.5, 0.5, 0.5, 1], "size": 4}, "normal": "base\\surfaces\\n.xbm"},
         "overrides": {"Foo": {"type": "Float", "value": 2}},
         "variants": [{"name": "dirty", "path": "mod\\ls\\materials\\tile_dirty.mi", "params": {"roughness": 0.9}, "textures": {}, "overrides": {}},
                      {"name": "red", "path": "mod\\ls\\materials\\tile_red.mi", "params": {},
                       "textures": {"base_color": {"solid": [1, 0, 0, 1], "size": 4}}, "overrides": {}}]}
    d.update(extra)
    return d


def box(cx, cy, cz, sx, sy, sz, material="main"):
    return {"shape": "box", "center": {"x": cx, "y": cy, "z": cz}, "size": {"x": sx, "y": sy, "z": sz},
            "rotation": {"roll": 0, "pitch": 0, "yaw": 0}, "material": material}


def geometry(main="@tile", glass=None, appearance="default"):
    materials = {"main": main}
    parts = [box(0, 0, 1.5, 4, 0.2, 3)]
    if glass:
        materials["glass"] = glass
        parts.append(box(0, 0, 1.5, 1, 0.01, 1, material="glass"))
    return {"id": "obj_w", "name": "Wall", "premise_id": "p1", "layer": "shell", "enabled": True,
            "transform": {"position": {"x": 5, "y": 5, "z": 0}, "rotation": {"yaw": 0}},
            "metadata": {"procedural": {"generator": "compound", "parts": parts, "mesh_path": "mod\\ls\\procedural\\wall.mesh",
                                        "material": {"materials": materials, "appearance": appearance}}}}


def glass_def():
    return {"key": "glass", "preset": "glass", "base": "base\\materials\\glass.mt", "path": "mod\\ls\\materials\\glass.mi",
            "params": {"tint": [0.8, 0.9, 1, 0.3]}, "textures": {}, "overrides": {}, "variants": []}


def fake_worker(path: Path, *, ok: bool = True) -> Path:
    body = ("import sys\nargs=sys.argv[1:]\nout=args[args.index('--output')+1]\n"
            + ("open(out,'wb').write(b'CR2W'+open(args[args.index('--input')+1],'rb').read()[:8])\n" if ok else "sys.exit(4)\n"))
    path.write_text(f"#!{sys.executable}\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


def fake_cli(path: Path, *, ok: bool = True) -> Path:
    """`cli import -p image.png` writes image.xbm next to the image."""
    body = ("import sys, pathlib\nargs=sys.argv[1:]\nimg=pathlib.Path(args[args.index('-p')+1])\n"
            + ("img.with_suffix('.xbm').write_bytes(b'CR2W'+img.read_bytes()[:8])\n" if ok else "sys.exit(3)\n"))
    path.write_text(f"#!{sys.executable}\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


class DocumentTests(unittest.TestCase):
    def test_instance_and_variants(self):
        built = mat.build_material(tile())
        parent, dirty, red = built["documents"]
        root = parent["document"]["Data"]["RootChunk"]
        self.assertEqual(root["$type"], "CMaterialInstance")
        self.assertEqual(root["baseMaterial"]["DepotPath"]["$value"], BASE)
        values = mat.instance_values(parent["document"])
        self.assertEqual(values["RoughnessBias"], {"$type": "Float", "$value": 0.6})
        self.assertEqual(values["RoughnessScale"]["$value"], 0.0, "scalar roughness without a texture zeroes the texture scale")
        self.assertEqual(values["BaseColorScale"]["$type"], "Vector4")
        self.assertEqual(values["BaseColor"]["$type"], "rRef:ITexture")
        self.assertEqual(values["BaseColor"]["DepotPath"]["$value"], "mod\\ls\\materials\\textures\\tile_base_color.xbm")
        self.assertEqual(values["Foo"]["$value"], 2.0)
        # Variants chain on the parent and only store differences.
        self.assertEqual(dirty["document"]["Data"]["RootChunk"]["baseMaterial"]["DepotPath"]["$value"], "mod\\ls\\materials\\tile.mi")
        self.assertEqual(dirty["values"], {"RoughnessBias": 0.9})
        self.assertEqual(red["values"], {"BaseColor": "mod\\ls\\materials\\textures\\tile_red_base_color.xbm"})
        self.assertEqual([j["path"] for j in built["textures"]],
                         ["mod\\ls\\materials\\textures\\tile_base_color.xbm", "mod\\ls\\materials\\textures\\tile_red_base_color.xbm"])
        self.assertEqual(built["uv"], (1.0, 2.0), "uv_scale 2 m / tiling (2, 1)")
        self.assertEqual(built["profile_source"], "builtin-unverified")
        self.assertTrue(built["warnings"])
        decoded = mat.decode_instance(parent["document"])
        self.assertEqual(decoded["base_material"], BASE)
        self.assertIn({"name": "BaseColorScale", "type": "Vector4", "value": [1.0, 0.9, 0.8, 1.0]}, decoded["values"])

    def test_values_and_colors(self):
        self.assertEqual(mat.value_json("Color", [1, 0.5, 0, 1]), {"$type": "Color", "Alpha": 255, "Blue": 0, "Green": 128, "Red": 255})
        self.assertEqual(mat.value_json("mlsetup", "base\\a.mlsetup")["$type"], "rRef:Multilayer_Setup")
        self.assertEqual(mat.value_json("CName", "x")["$value"], "x")
        shaped = mat.value_json("Float", 0.25, {"$type": "Float", "Value": 1.0, "Extra": True})
        self.assertEqual(shaped, {"$type": "Float", "Value": 0.25, "Extra": True}, "a reference value supplies the shape")

    def test_base_json_verification(self):
        template = {"Data": {"RootChunk": {"$type": "CMaterialTemplate", "parameters": [[
            {"HandleId": "0", "Data": {"$type": "CMaterialParameterScalar", "parameterName": {"$type": "CName", "$value": "RoughnessBias"}}},
            {"HandleId": "1", "Data": {"$type": "CMaterialParameterScalar", "parameterName": {"$type": "CName", "$value": "RoughnessScale"}}},
            {"HandleId": "2", "Data": {"$type": "CMaterialParameterTexture", "parameterName": {"$type": "CName", "$value": "BaseColor"}}},
            {"HandleId": "3", "Data": {"$type": "CMaterialParameterColor", "parameterName": {"$type": "CName", "$value": "BaseColorScale"}}}]]}}}
        params = mat.template_parameters(template)
        self.assertEqual(params, {"RoughnessBias": "Float", "RoughnessScale": "Float", "BaseColor": "texture", "BaseColorScale": "Color"})
        ok = mat.build_material(tile(textures={"base_color": {"solid": [1, 1, 1, 1]}}, overrides={}, variants=[]), base_parameters=params)
        self.assertEqual((ok["profile_source"], ok["errors"]), ("base-json", []))
        bad = mat.build_material(tile(), base_parameters=params)
        self.assertTrue(any("no parameter Normal" in e for e in bad["errors"]))
        self.assertTrue(any("no parameter Foo" in e for e in bad["errors"]))
        wrong = mat.build_material(tile(textures={}, variants=[], overrides={"RoughnessBias": {"type": "texture", "value": "base\\a.xbm"}}),
                                   base_parameters=params)
        self.assertTrue(any("RoughnessBias" in e and "is Float" in e for e in wrong["errors"]))

    def test_reference_mi(self):
        reference = {"Data": {"RootChunk": {"$type": "CMaterialInstance", "cookingPlatform": "PLATFORM_PC", "resourceVersion": 4,
                                            "baseMaterial": mr.depot(BASE),
                                            "values": [mat._pair("RoughnessBias", {"$type": "Float", "$value": 0.1}),
                                                       mat._pair("RoughnessScale", {"$type": "Float", "$value": 1.0})]}}}
        built = mat.build_material(tile(params={"roughness": 0.3}, textures={}, overrides={}, variants=[]), reference=reference)
        self.assertEqual(built["profile_source"], "reference-mi")
        other_base = mat.build_material(tile(base="base\\x.mt", params={"roughness": 0.3}, textures={}, overrides={}, variants=[]), reference=reference)
        self.assertEqual(other_base["profile_source"], "builtin-unverified")

    def test_solid_png(self):
        png = mat.solid_png([1, 0, 0, 1], 2)
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        w, h = struct.unpack(">II", png[16:24])
        self.assertEqual((w, h), (2, 2))
        idat = png[png.index(b"IDAT") + 4: png.index(b"IEND") - 8]
        self.assertEqual(zlib.decompress(idat), b"\x00\xff\x00\x00\xff\xff\x00\x00\xff" * 2)


class ProjectTests(unittest.TestCase):
    def project(self, obj=None):
        return {"material_defs": [tile(), glass_def()], "objects": [obj or geometry(glass="@glass")]}

    def test_resolve_object_and_appearances(self):
        p = self.project()
        defs = mat.definitions(p)
        obj = mat.resolve_object(p["objects"][0], defs)
        m = obj["metadata"]["procedural"]["material"]
        self.assertEqual(m["materials"], {"main": "mod\\ls\\materials\\tile.mi", "glass": "mod\\ls\\materials\\glass.mi"})
        self.assertEqual(list(m["appearances"]), ["default", "dirty", "red"])
        self.assertEqual(m["appearances"]["dirty"], {"main": "mod\\ls\\materials\\tile_dirty.mi", "glass": "mod\\ls\\materials\\glass.mi"})
        self.assertEqual(m["slot_uv"], {"main": (1.0, 2.0), "glass": (1.0, 1.0)})
        pinned = mat.resolve_object(geometry(main="@tile:red"), defs)["metadata"]["procedural"]["material"]
        self.assertEqual((pinned["materials"]["main"], list(pinned["appearances"])), ("mod\\ls\\materials\\tile_red.mi", ["default"]))
        with self.assertRaises(ValueError):
            mat.resolve_object(geometry(main="@tile:rusty"), defs)
        with self.assertRaises(ValueError):
            mat.resolve_object(geometry(main="@nope"), defs)

    def test_mesh_appearances_and_uvs(self):
        p = self.project()
        obj = mat.resolve_object(p["objects"][0], mat.definitions(p))
        built = pg.native_mesh(obj)
        root = built["document"]["Data"]["RootChunk"]
        names = [a["Data"]["name"]["$value"] for a in root["appearances"]]
        self.assertEqual(names, ["default", "dirty", "red"])
        entries = [e["name"]["$value"] for e in root["materialEntries"]]
        paths = [e["DepotPath"]["$value"] for e in root["externalMaterials"]]
        self.assertEqual(entries, ["glass", "main", "main@dirty", "main@red"])
        self.assertEqual(paths[entries.index("main@dirty")], "mod\\ls\\materials\\tile_dirty.mi")
        dirty = root["appearances"][1]["Data"]["chunkMaterials"]
        self.assertEqual([c["$value"] for c in dirty], ["glass", "main@dirty"], "unchanged slots reuse the default entry")
        self.assertEqual(mr.decode(built["document"])["appearances"][2]["name"], "red")
        # UVs: the wall face (x across 4 m) divided by uv_scale 2 / tiling 2 -> 1 m per repeat.
        mesh = pg.object_mesh(obj)
        us = [uv[0] for uv in mesh.prims["main"]["uv"]]
        self.assertAlmostEqual(max(us) - min(us), 4.0)
        plain = pg.object_mesh(geometry(main="base\\a.mi"))
        us = [uv[0] for uv in plain.prims["main"]["uv"]]
        self.assertAlmostEqual(max(us) - min(us), 4.0)
        # Faces facing +y/-y project (x, z): z 0..3 m with the v divisor 2.
        face = [uv[1] for (p, n, uv) in zip(mesh.prims["main"]["pos"], mesh.prims["main"]["nrm"], mesh.prims["main"]["uv"]) if abs(n[1]) > 0.9]
        self.assertAlmostEqual(max(face) - min(face), 1.5, msg="v divisor 2")

    def test_generated_paths_and_dependencies(self):
        p = self.project()
        gen = mat.generated_paths(p)
        self.assertEqual(gen["mod\\ls\\materials\\tile.mi"], sorted([BASE, "base\\surfaces\\n.xbm", "mod\\ls\\materials\\textures\\tile_base_color.xbm"]))
        self.assertEqual(gen["mod\\ls\\materials\\tile_dirty.mi"], ["mod\\ls\\materials\\tile.mi"])
        self.assertIn("mod\\ls\\materials\\textures\\tile_red_base_color.xbm", gen)
        roots = dep.project_roots(p)
        refs = {r["value"] for r in roots[0]["refs"]}
        self.assertTrue({"mod\\ls\\materials\\tile.mi", "mod\\ls\\materials\\tile_dirty.mi", "mod\\ls\\materials\\tile_red.mi",
                         "mod\\ls\\materials\\glass.mi"} <= refs, refs)
        with tempfile.TemporaryDirectory() as td:
            report = dep.resolve(roots, sources=dep.Sources([td]), vanilla=dep.HashSet([dep.path_hash(BASE), dep.path_hash("base\\materials\\glass.mt"),
                                                                                       dep.path_hash("base\\surfaces\\n.xbm")]), generated=gen)
        self.assertTrue(report["ready"], report["missing"])
        self.assertEqual(report["nodes"]["mod\\ls\\materials\\tile.mi"]["status"], "generated")
        self.assertEqual(report["nodes"]["base\\surfaces\\n.xbm"]["status"], "vanilla")
        staged = dep.stage(report, Path(tempfile.mkdtemp()))
        self.assertTrue(any(s["reason"].startswith("written by the Build Mod") for s in staged["skipped"]))


class StageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.project = self.root / "project.json"
        self.project.write_text(json.dumps({"material_defs": [tile(), glass_def()], "objects": [geometry(glass="@glass", appearance="dirty")]}))
        self.ws = self.root / "ws"
        (self.ws / "source" / "raw").mkdir(parents=True)
        (self.ws / "source" / "raw" / "e.json").write_text(json.dumps({"sectors": [{"name": "s", "min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 9, "y": 9, "z": 9}, "nodes": []}]}))
        (self.ws / ".cp77wb-build.json").write_text(json.dumps({"schema": MANIFEST_SCHEMA, "exportFile": "source/raw/e.json", "exportSha256": "x"}))

    def tearDown(self):
        self.tmp.cleanup()

    def test_materials_then_meshes(self):
        worker = str(fake_worker(self.root / "w"))
        report = mat.apply_to_workspace(self.project, self.ws, worker=worker, cli=str(fake_cli(self.root / "cli")),
                                        output=self.ws / "automation" / "materials-report.json")
        self.assertTrue(report["ready"], report["issues"])
        self.assertEqual([m["key"] for m in report["materials"]], ["glass", "tile"])
        archive = self.ws / "source" / "archive" / "mod" / "ls" / "materials"
        for name in ("tile.mi", "tile_dirty.mi", "tile_red.mi", "glass.mi", "textures/tile_base_color.xbm", "textures/tile_red_base_color.xbm"):
            self.assertEqual((archive / name).read_bytes()[:4], b"CR2W", name)
        self.assertTrue((self.ws / "source" / "raw" / "mod" / "ls" / "materials" / "textures" / "tile_base_color.png").is_file())
        doc = json.loads((self.ws / "source" / "raw" / "mod" / "ls" / "materials" / "tile_dirty.mi.json").read_text())
        self.assertEqual(doc["Data"]["RootChunk"]["baseMaterial"]["DepotPath"]["$value"], "mod\\ls\\materials\\tile.mi")
        # The generated files are project sources for the dependency resolver.
        sources = dep.Sources([self.ws / "source" / "archive", self.ws / "source" / "raw"])
        self.assertEqual(sources.files["mod\\ls\\materials\\tile.mi"][1], "binary")
        meshes = pg.apply_to_workspace(self.project, self.ws, worker=worker)
        self.assertTrue(meshes["ready"], meshes["issues"])
        self.assertEqual(meshes["generated"][0]["stats"]["appearances"], ["default", "dirty", "red"])
        node = json.loads((self.ws / "source" / "raw" / "e.json").read_text())["sectors"][0]["nodes"][0]
        self.assertEqual(node["data"]["meshAppearance"]["$value"], "dirty")

    def test_failures(self):
        no_tools = mat.apply_to_workspace(self.project, self.ws)
        errors = " ".join(i["error"] for i in no_tools["issues"])
        self.assertIn("worker is not ready", errors)
        self.assertIn("WolvenKit CLI not found", errors)
        bad_cli = mat.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w")), cli=str(fake_cli(self.root / "c", ok=False)))
        self.assertTrue(any("did not write" in i["error"] and ".xbm" in i["error"] for i in bad_cli["issues"]))
        self.project.write_text(json.dumps({"material_defs": [tile()], "objects": [geometry(main="@tile", appearance="rusty")]}))
        meshes = pg.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w")))
        self.assertIn("appearance 'rusty'", meshes["issues"][0]["error"])
        self.project.write_text(json.dumps({"material_defs": [], "objects": [geometry(main="@gone")]}))
        dangling = mat.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w")))
        self.assertIn("unknown material @gone", dangling["issues"][0]["error"])
        image = tile(textures={"base_color": {"file": str(self.root / "missing.png")}}, variants=[])
        self.project.write_text(json.dumps({"material_defs": [image], "objects": [geometry()]}))
        missing = mat.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w")), cli=str(fake_cli(self.root / "c2")))
        self.assertTrue(any("does not exist" in i["error"] for i in missing["issues"]))

    def test_image_texture(self):
        img = self.root / "albedo.png"
        img.write_bytes(mat.solid_png([0, 1, 0, 1]))
        d = tile(textures={"base_color": {"file": str(img), "path": "mod\\ls\\tex\\albedo.xbm"}}, variants=[])
        self.project.write_text(json.dumps({"material_defs": [d], "objects": [geometry()]}))
        report = mat.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w")), cli=str(fake_cli(self.root / "c")))
        self.assertTrue(report["ready"], report["issues"])
        self.assertTrue((self.ws / "source" / "archive" / "mod" / "ls" / "tex" / "albedo.xbm").is_file())
        self.assertEqual(report["textures"][0]["source"], str(img))


class EdlTests(unittest.TestCase):
    def test_library(self):
        doc = {"edl": 1, "id": "t", "name": "T", "origin": {"position": [0, 0, 0]},
               "materials": {"library": [{"key": "tile", "params": {"roughness": 0.5}, "variants": [{"name": "dirty", "params": {"roughness": 0.9}}]}]},
               "floors": [{"id": "g", "height": 3, "rooms": [{"id": "r", "size": [6, 4], "build": "parametric",
                                                            "parametric": {"materials": {"walls": "@tile", "floor": "@stone"}},
                                                            "geometry": [{"id": "b", "generator": "box", "params": {"size": [1, 1, 1]}, "material": "@tile:dirty"}]}]}]}
        r = edl.compile_document(doc)
        self.assertTrue(r["valid"], r["errors"])
        steps = r["plan"]["steps"]
        ops = [s["op"] for s in steps]
        self.assertLess(ops.index("create_material"), ops.index("create_parametric_room"))
        cm = steps[ops.index("create_material")]
        self.assertEqual((cm["key"], cm["params"]["roughness"]), ("tile", 0.5))
        self.assertEqual(steps[ops.index("create_procedural")]["material"]["materials"], {"main": "@tile:dirty"})
        self.assertTrue(any("@stone" in w for w in r["warnings"]))
        bad = dict(doc, materials={"library": [{"key": "a"}, {"key": "a"}, {"key": "b", "colour": 1}]})
        errs = " ".join(edl.compile_document(bad)["errors"])
        self.assertIn("repeats material a", errs)
        self.assertIn("colour", errs)


class ToolTests(unittest.TestCase):
    def test_build_and_inspect(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            project = root / "project.json"
            project.write_text(json.dumps({"material_defs": [tile(), glass_def()], "objects": [geometry(glass="@glass")]}))
            sources = root / "sources"
            base_json = sources / "base" / "materials" / "glass.mt.json"
            base_json.parent.mkdir(parents=True)
            base_json.write_text(json.dumps({"Data": {"RootChunk": {"$type": "CMaterialTemplate", "parameters": [
                {"$type": "CMaterialParameterColor", "parameterName": {"$value": "TintColor"}}]}}}))
            worker = fake_worker(root / "w")
            with patch.object(server, "PROJECT", project), patch.object(server, "MOD_SOURCES", sources), \
                    patch.object(server._lsw, "worker_preflight", lambda **k: {"ready": True, "worker": str(worker)}), \
                    patch.object(server.shutil, "which", lambda name: str(fake_cli(root / "cli"))):
                out = call(server.material_build, output_dir=str(root / "out"), write_cr2w=True)
                rows = {m["key"]: m for m in out["materials"]}
                self.assertEqual(rows["glass"]["profile_source"], "base-json")
                self.assertEqual(rows["tile"]["profile_source"], "builtin-unverified")
                self.assertEqual([f["variant"] for f in rows["tile"]["files"]], [None, "dirty", "red"])
                self.assertTrue(all(f["cr2w_ok"] for f in rows["tile"]["files"]))
                self.assertTrue(all(t.get("xbm") for t in rows["tile"]["textures"]))
                one = call(server.material_build, key="@glass", output_dir=str(root / "out2"))
                self.assertEqual(one["count"], 1)
                summary = call(server.material_inspect, rows["tile"]["files"][1]["json"])
                self.assertEqual(summary["base_material"], "mod\\ls\\materials\\tile.mi")
                self.assertEqual(call(server.material_inspect, str(base_json))["parameters"], {"TintColor": "Color"})
                with self.assertRaises(ValueError):
                    call(server.material_build, key="missing")
                gen = call(server.mesh_resource_build, output_dir=str(root / "meshes"))
                self.assertEqual(gen["meshes"][0]["appearances"], ["default", "dirty", "red"])

    def test_live_wrappers(self):
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True, "items": []}):
            call(server.material_presets)
            call(server.material_create, {"key": "a"})
            call(server.material_update, "a", {"params": {"roughness": 0.2}})
            call(server.material_delete, "a")
            call(server.material_list)
            call(server.material_get, "a")
            call(server.material_assign, "o1", "@a:dirty", slot="glass")
            call(server.material_settings, root="mod\\x")
        self.assertEqual([op for op, _ in sent], ["material_presets", "material_create", "material_update", "material_delete", "material_list",
                                                  "material_get", "material_assign", "material_settings"])
        self.assertEqual(sent[6][1], {"object_id": "o1", "slot": "glass", "material": "@a:dirty"})


if __name__ == "__main__":
    unittest.main()
