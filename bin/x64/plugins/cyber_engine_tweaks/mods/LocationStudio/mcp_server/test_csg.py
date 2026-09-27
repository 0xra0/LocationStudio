#!/usr/bin/env python3
"""Constructive solid geometry: exact BSP booleans, watertightness, materials, UVs, build integration and tools."""
from __future__ import annotations

import importlib
import json
import math
import stat
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
from lsbuild import csg  # noqa: E402
from lsbuild import edl  # noqa: E402
from lsbuild import meshres as mr  # noqa: E402
from lsbuild import procedural as pg  # noqa: E402
from lsbuild.build import MANIFEST_SCHEMA  # noqa: E402

EXAMPLES = json.loads((Path(__file__).resolve().parents[1] / "csg" / "examples.json").read_text())["examples"]


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def B(c, s, **extra):
    return {"shape": "box", "center": c, "size": s, "rotation": {"roll": 0, "pitch": 0, "yaw": 0}, **extra}


def polygon_area(sides: int, r: float) -> float:
    return sides / 2 * r * r * math.sin(2 * math.pi / sides)


class BooleanTests(unittest.TestCase):
    def check(self, tree, expected, places=6):
        mesh = csg.mesh_from_tree(csg.expand(tree))
        self.assertAlmostEqual(csg.volume(mesh), expected, places=places)
        self.assertEqual(csg.open_edges(mesh), 0, "watertight")
        return mesh

    def test_operations(self):
        a, b = B([0, 0, 0.5], [4, 2, 1]), B([1, 2, 0.5], [2, 4, 1])
        self.check({"op": "union", "children": [a, b]}, 14)
        self.check({"op": "intersect", "children": [a, b]}, 2)
        self.check({"op": "subtract", "children": [a, b]}, 6)
        self.check({"op": "subtract", "children": [b, a]}, 6)
        self.check({"op": "union", "children": [a]}, 8)

    def test_architecture(self):
        self.check({"op": "subtract", "children": [B([0, 0, 1.5], [5, 0.2, 3]), B([-1.2, 0, 1.05], [1, 0.4, 2.1]), B([1.1, 0, 1.6], [1.4, 0.4, 1.2])]},
                   (15 - 2.1 - 1.68) * 0.2)
        tunnel = {"op": "subtract", "children": [B([0, 0, 2], [6, 4, 4]), {"shape": "cylinder", "center": [0, 0, 2], "radius": 1.5, "length": 4.2, "sides": 24}]}
        self.check(tunnel, 96 - polygon_area(24, 1.5) * 4)
        shaft = {"op": "subtract", "children": [B([0, 0, -0.15], [10, 8, 0.3]), B([3, 2, -0.15], [2, 2.5, 0.5])]}
        mesh = self.check(shaft, (80 - 5) * 0.3)
        self.assertEqual(mesh.bounds(), {"min": [-5.0, -4.0, -0.3], "max": [5.0, 4.0, 0.0]})
        vents = {"op": "subtract", "children": [B([0, 0, 1], [1.2, 0.05, 0.6]),
                                                {"shape": "box", "center": [-0.45, 0, 1], "size": [0.06, 0.2, 0.4], "repeat": {"count": 8, "step": [0.12, 0, 0]}}]}
        self.check(vents, 1.2 * 0.05 * 0.6 - 8 * 0.06 * 0.05 * 0.4)
        ball = csg.mesh_from_tree({"op": "intersect", "children": [B([0, 0, 0], [2, 2, 2]), {"shape": "sphere", "center": [0, 0, 0], "radius": 1.2, "sides": 16}]})
        self.assertEqual(csg.open_edges(ball), 0)
        self.assertTrue(4 / 3 * math.pi < csg.volume(ball) < 8, "a rounded cube: more than the unit sphere, less than the cube")
        prism = {"op": "subtract", "children": [{"shape": "prism", "points": [[0, 0], [4, 0], [4, 3], [0, 3]], "z0": 0, "z1": 1},
                                                {"shape": "prism", "points": [[1, 1], [3, 1], [2, 2.5]], "z0": -1, "z1": 2}]}
        self.check(prism, 12 - 1.5)
        wedge = {"op": "subtract", "children": [B([0, 0, 0.5], [2, 2, 1]), {"shape": "wedge", "center": [0, 0, 0.5], "size": [2.2, 2, 1]}]}
        self.check(wedge, 4 - 2)

    def test_every_example_is_watertight(self):
        for name, e in EXAMPLES.items():
            with self.subTest(name):
                mesh = csg.mesh_from_tree(csg.expand(e["tree"]))
                self.assertGreater(csg.volume(mesh), 0)
                self.assertEqual(csg.open_edges(mesh), 0)

    def test_materials(self):
        window = EXAMPLES["round_window"]["tree"]
        mesh = csg.mesh_from_tree(window)
        self.assertEqual(set(mesh.prims), {"main", "glass"})
        glass = csg.mesh_from_tree({"op": "union", "children": [window["children"][1]]})
        self.assertAlmostEqual(csg.volume(glass), polygon_area(24, 0.5) * 0.01, places=6)
        # A glass cutter leaves main-material faces unless cut_material says otherwise.
        cut = {"op": "subtract", "children": [B([0, 0, 0], [2, 2, 2]), B([0, 0, 1], [1, 1, 1], material="glass")]}
        self.assertEqual(set(csg.mesh_from_tree(cut).prims), {"main"})
        cut["cut_material"] = "glass"
        self.assertEqual(set(csg.mesh_from_tree(cut).prims), {"main", "glass"})

    def test_uvs_and_normals(self):
        mesh = csg.mesh_from_tree({"op": "subtract", "children": [B([0, 0, 1.5], [4, 0.2, 3]), B([0, 0, 1], [1, 0.4, 2])]}, uv_scale=2.0)
        prim = mesh.prims["main"]
        front = [uv for p, n, uv in zip(prim["pos"], prim["nrm"], prim["uv"]) if n[1] > 0.9]
        self.assertAlmostEqual(max(u for u, _v in front) - min(u for u, _v in front), 2.0, msg="4 m at 2 m per repeat")
        for n in prim["nrm"]:
            self.assertAlmostEqual(math.sqrt(sum(c * c for c in n)), 1.0, places=6)
        tube = csg.mesh_from_tree({"op": "union", "children": [{"shape": "cylinder", "center": [0, 0, 0], "radius": 1, "length": 2, "sides": 16}]})
        side = [n for n in tube.prims["main"]["nrm"] if abs(n[1]) < 0.1]
        self.assertTrue(any(abs(n[0]) not in (0.0, 1.0) for n in side), "cylinder sides keep smooth normals")

    def test_errors(self):
        with self.assertRaises(ValueError):
            csg.expand({"op": "union", "children": [{"generator": "wall", "params": {}}]})
        with self.assertRaises(ValueError):
            csg.expand({"children": []})
        with self.assertRaises(ValueError):
            csg.expand({"shape": "box", "center": [0, 0, 0], "size": [1, 1, 1], "repeat": {"count": 500, "step": [1, 0, 0]}})
        with self.assertRaises(ValueError):
            csg.evaluate({"op": "xor", "children": [B([0, 0, 0], [1, 1, 1])]})
        with self.assertRaises(ValueError):
            csg.mesh_from_tree({"op": "subtract", "children": [B([0, 0, 0], [1, 1, 1]), B([0, 0, 0], [2, 2, 2])]})

    def test_t_junction_repair(self):
        # Two boxes side by side: the small one's edge vertices sit on the big one's edges.
        polys = csg.union(csg.leaf_polygons(B([0, 0, 0], [2, 2, 2])), csg.leaf_polygons(B([1.5, 0, 0], [1, 1, 1])))
        fixed = csg.fix_t_junctions(csg.weld(polys))
        self.assertGreater(sum(len(p.verts) for p in fixed), sum(len(p.verts) for p in polys))
        self.assertEqual(csg.open_edges(csg.to_mesh(polys)), 0)


def csg_object(tree, **material):
    return {"id": "obj_c", "name": "Arch", "premise_id": "p1", "layer": "shell", "enabled": True,
            "transform": {"position": {"x": 5, "y": 5, "z": 0}, "rotation": {"yaw": 0}},
            "metadata": {"procedural": {"generator": "csg", "params": {"tree": tree}, "csg": {"tree": tree, "approximate": True},
                                        "parts": [B([0, 0, 1.6], [4, 0.3, 3.2])], "mesh_path": "mod\\ls\\procedural\\arch.mesh",
                                        "material": material or {"materials": {"main": "base\\wall.mi"}}}}}


def fake_worker(path: Path) -> Path:
    path.write_text(f"#!{sys.executable}\nimport sys\nargs=sys.argv[1:]\nopen(args[args.index('--output')+1],'wb').write(b'CR2W'+b'x'*8)\n")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


class BuildTests(unittest.TestCase):
    def test_object_mesh_uses_the_exact_tree(self):
        tree = csg.expand(EXAMPLES["arched_doorway"]["tree"])
        obj = csg_object(tree)
        mesh = pg.object_mesh(obj)
        self.assertEqual(csg.open_edges(mesh), 0)
        self.assertLess(csg.volume(mesh), 4 * 0.3 * 3.2, "the doorway is cut out, not the preview box")
        doc = pg.native_mesh(obj)
        self.assertEqual(mr.decode(doc["document"])["materials"], ["main"])
        broken = csg_object(tree)
        del broken["metadata"]["procedural"]["csg"]
        with self.assertRaises(ValueError):
            pg.object_mesh(broken)

    def test_stage(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            project = root / "project.json"
            project.write_text(json.dumps({"objects": [csg_object(csg.expand(EXAMPLES["tunnel"]["tree"]))]}))
            ws = root / "ws"
            (ws / "source" / "raw").mkdir(parents=True)
            (ws / "source" / "raw" / "e.json").write_text(json.dumps({"sectors": [{"name": "s", "min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 9, "y": 9, "z": 9}, "nodes": []}]}))
            (ws / ".cp77wb-build.json").write_text(json.dumps({"schema": MANIFEST_SCHEMA, "exportFile": "source/raw/e.json", "exportSha256": "x"}))
            report = pg.apply_to_workspace(project, ws, worker=str(fake_worker(root / "w")))
            self.assertTrue(report["ready"], report["issues"])
            glb = pg.read_glb(Path(report["generated"][0]["glb"]).read_bytes())
            self.assertGreater(report["generated"][0]["triangles"], 200)
            self.assertEqual(glb["asset"]["version"], "2.0")


class EdlAndToolTests(unittest.TestCase):
    def test_edl(self):
        doc = {"edl": 1, "id": "t", "name": "T", "origin": {"position": [0, 0, 0]},
               "geometry": [{"id": "arch", "generator": "csg", "params": {"tree": EXAMPLES["arched_doorway"]["tree"]}, "material": "base\\wall.mesh"}]}
        r = edl.compile_document(doc)
        self.assertTrue(r["valid"], r["errors"])
        step = [s for s in r["plan"]["steps"] if s["op"] == "create_procedural"][0]
        self.assertEqual(step["generator"], "csg")

    def test_tools(self):
        self.assertEqual(len(call(server.csg_examples)["examples"]), 9)
        with tempfile.TemporaryDirectory() as td:
            out = call(server.csg_mesh, tree=EXAMPLES["vents"]["tree"], glb_path=str(Path(td) / "vents.glb"))
            self.assertEqual(out["open_edges"], 0)
            self.assertAlmostEqual(out["volume"], 1.2 * 0.05 * 0.6 - 8 * 0.06 * 0.05 * 0.4, places=6)
            self.assertTrue(Path(out["glb"]).is_file())
            project = Path(td) / "p.json"
            project.write_text(json.dumps({"objects": [csg_object(csg.expand(EXAMPLES["shaft"]["tree"]))]}))
            with patch.object(server, "PROJECT", project):
                saved = call(server.csg_mesh, object_id="obj_c")
                self.assertAlmostEqual(saved["volume"], 22.5, places=6)
                with self.assertRaises(ValueError):
                    call(server.csg_mesh, object_id="missing")
        with self.assertRaises(ValueError):
            call(server.csg_mesh)
        sent = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.csg_create, example="tunnel", position=[1, 2, 3], materials={"main": "@rock"}, resolution=0.1)
            call(server.csg_create, tree={"op": "union", "children": [B([0, 0, 0], [1, 1, 1])]}, source="aim")
            with self.assertRaises(ValueError):
                call(server.csg_create, example="nope")
            with self.assertRaises(ValueError):
                call(server.csg_create)
        op, args = sent[0]
        self.assertEqual((op, args["generator"], args["params"]["resolution"], args["name"]), ("procedural_create", "csg", 0.1, "Tunnel through rock"))
        self.assertEqual(args["params"]["tree"], EXAMPLES["tunnel"]["tree"])
        self.assertEqual(args["material"]["materials"], {"main": "@rock"})
        self.assertEqual(sent[1][1]["source"], "aim")


if __name__ == "__main__":
    unittest.main()
