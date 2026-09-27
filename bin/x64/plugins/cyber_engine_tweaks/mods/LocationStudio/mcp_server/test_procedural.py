#!/usr/bin/env python3
"""Procedural geometry: triangulation, glTF, workspace stage and MCP tools."""
from __future__ import annotations

import importlib
import json
import math
import os
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
from lsbuild import procedural as pg  # noqa: E402
from lsbuild.build import MANIFEST_SCHEMA  # noqa: E402


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def signed_volume(mesh: pg.Mesh) -> float:
    """Divergence theorem: positive and equal to the solid volume only if every face winds outward."""
    v = 0.0
    for prim in mesh.prims.values():
        p, idx = prim["pos"], prim["idx"]
        for i in range(0, len(idx), 3):
            a, b, c = p[idx[i]], p[idx[i + 1]], p[idx[i + 2]]
            v += (a[0] * (b[1] * c[2] - b[2] * c[1]) - a[1] * (b[0] * c[2] - b[2] * c[0]) + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6
    return v


def box(cx, cy, cz, sx, sy, sz, rot=None, material="main"):
    return {"shape": "box", "center": {"x": cx, "y": cy, "z": cz}, "size": {"x": sx, "y": sy, "z": sz},
            "rotation": rot or {"roll": 0, "pitch": 0, "yaw": 0}, "material": material}


class MeshTests(unittest.TestCase):
    def test_rotation_matches_lua(self):
        m = pg.rot_matrix({"roll": 0, "pitch": 30, "yaw": 90})
        v = pg._apply(m, (0, 1, 0))
        self.assertAlmostEqual(v[0], -math.cos(math.radians(30)))
        self.assertAlmostEqual(v[1], 0)
        self.assertAlmostEqual(v[2], 0.5)

    def test_volumes_and_winding(self):
        rot = {"roll": 10, "pitch": 20, "yaw": 30}
        cases = [
            ([box(0, 0, 0, 2, 3, 4)], 24),
            ([box(5, -2, 1, 2, 3, 4, rot)], 24),
            ([{"shape": "wedge", "center": {"x": 0, "y": 2, "z": 0.5}, "size": {"x": 2, "y": 4, "z": 1}, "rotation": rot}], 4),
            ([{"shape": "cylinder", "center": {"x": 0, "y": 0, "z": 0}, "radius": 1, "length": 2, "sides": 16, "rotation": rot}], 16 / 2 * math.sin(2 * math.pi / 16) * 2),
            ([{"shape": "prism", "points": [{"x": 0, "y": 0}, {"x": 4, "y": 0}, {"x": 4, "y": 1}, {"x": 1, "y": 1}, {"x": 1, "y": 3}, {"x": 0, "y": 3}], "z0": -0.2, "z1": 0}],
             (4 * 1 + 1 * 2) * 0.2),
        ]
        for parts, expected in cases:
            mesh = pg.mesh_from_parts(parts)
            self.assertAlmostEqual(signed_volume(mesh), expected, places=6, msg=parts[0]["shape"])
        sphere = pg.mesh_from_parts([{"shape": "sphere", "center": {"x": 0, "y": 0, "z": 0}, "radius": 1, "sides": 16}])
        self.assertTrue(3.0 < signed_volume(sphere) < 4.19)
        # Clockwise prism input is reordered; the volume stays positive.
        cw = pg.mesh_from_parts([{"shape": "prism", "points": [{"x": 0, "y": 0}, {"x": 0, "y": 2}, {"x": 2, "y": 2}, {"x": 2, "y": 0}], "z0": 0, "z1": 1}])
        self.assertAlmostEqual(signed_volume(cw), 4)
        with self.assertRaises(ValueError):
            pg.mesh_from_parts([{"shape": "torus"}])

    def test_uv_scale(self):
        m1 = pg.mesh_from_parts([box(0, 0, 0, 4, 4, 4)], uv_scale=1)
        m2 = pg.mesh_from_parts([box(0, 0, 0, 4, 4, 4)], uv_scale=2)
        self.assertAlmostEqual(max(u for u, _ in m1.prims["main"]["uv"]), 2)
        self.assertAlmostEqual(max(u for u, _ in m2.prims["main"]["uv"]), 1)

    def test_glb(self):
        mesh = pg.mesh_from_parts([box(0, 0, 1.5, 4, 0.2, 3), box(0, 0, 1.5, 1, 0.01, 1, material="glass")])
        data = pg.write_glb(mesh, name="wall")
        doc = pg.read_glb(data)
        self.assertEqual(doc["asset"]["version"], "2.0")
        self.assertEqual([m["name"] for m in doc["materials"]], ["glass", "main"])
        main = doc["meshes"][0]["primitives"][1]
        pos = doc["accessors"][main["attributes"]["POSITION"]]
        self.assertEqual(pos["max"][1], 3.0, "REDengine z becomes glTF y")
        self.assertAlmostEqual(pos["max"][2], 0.1)
        self.assertEqual(doc["accessors"][main["indices"]]["count"], 36)
        self.assertEqual(len(data) % 4, 0)
        with self.assertRaises(ValueError):
            pg.read_glb(b"nope" * 8)


def wall_object(template="base\\walls\\plaster.mesh", pos=(5, 5, 0)):
    return {"id": "obj_wall", "name": "Wall", "premise_id": "p1", "layer": "shell", "enabled": True,
            "transform": {"position": {"x": pos[0], "y": pos[1], "z": pos[2], "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": 90}},
            "metadata": {"procedural": {"generator": "wall", "parts": [box(0, 0, 1.5, 4, 0.2, 3)], "bounds": {"min": {"x": -2, "y": -0.1, "z": 0}, "max": {"x": 2, "y": 0.1, "z": 3}},
                                        "mesh_path": "mod\\ls\\procedural\\wall.mesh", "material": {"template": template, "appearance": "white", "uv_scale": 1}, "stream_range": 90}}}


def write_workspace(root: Path, variants=None) -> Path:
    ws = root / "ws"
    (ws / "source" / "raw").mkdir(parents=True)
    export = {"name": "demo", "sectors": [
        {"name": "far", "min": {"x": 500, "y": 500, "z": -5}, "max": {"x": 510, "y": 510, "z": 5}, "nodes": [{"name": "a", "type": "worldMeshNode"}]},
        {"name": "near", "min": {"x": 0, "y": 0, "z": -5}, "max": {"x": 10, "y": 10, "z": 5},
         "nodes": [{"name": "n0"}, {"name": "n1"}, {"name": "n2"}], "variantIndices": variants or [0]}]}
    (ws / "source" / "raw" / "demo_exported.json").write_text(json.dumps(export), encoding="utf-8")
    (ws / ".cp77wb-build.json").write_text(json.dumps({"schema": MANIFEST_SCHEMA, "exportFile": "source/raw/demo_exported.json", "exportSha256": "x",
                                                        "nativeRequiredTypes": ["worldStaticMeshNode"]}), encoding="utf-8")
    return ws


def fake_cli(path: Path, *, fail: bool = False) -> Path:
    body = "import sys\n"
    if fail:
        body += "sys.exit(3)\n"
    else:
        body += ("args=sys.argv[1:]\nglb=args[args.index('-p')+1]\nmesh=glb[:-4]+'.mesh'\n"
                 "open(mesh,'ab').write(b'IMPORTED:'+open(glb,'rb').read()[:4])\n")
    path.write_text(f"#!{sys.executable}\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


class StageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.template = self.root / "plaster.mesh"
        self.template.write_bytes(b"CR2W-template")
        self.project = self.root / "project.json"

    def tearDown(self):
        self.tmp.cleanup()

    def run_stage(self, obj, cli, variants=None, premise_id=None):
        self.project.write_text(json.dumps({"layers": [{"id": "shell"}], "objects": [obj]}), encoding="utf-8")
        ws = write_workspace(self.root, variants)
        report = pg.apply_to_workspace(self.project, ws, premise_id=premise_id, cli=str(cli) if cli else None,
                                       template_file=lambda p: self.template if p == "base\\walls\\plaster.mesh" else None)
        return ws, report

    def test_success(self):
        ws, report = self.run_stage(wall_object(), fake_cli(self.root / "cli"), variants=[0, 2])
        self.assertTrue(report["ready"], report["issues"])
        mesh = ws / "source" / "archive" / "mod" / "ls" / "procedural" / "wall.mesh"
        self.assertTrue(mesh.read_bytes().startswith(b"CR2W-templateIMPORTED:glTF"))
        self.assertTrue((ws / "source" / "raw" / "mod" / "ls" / "procedural" / "wall.glb").is_file())
        export = json.loads((ws / "source" / "raw" / "demo_exported.json").read_text())
        near = export["sectors"][1]
        self.assertEqual(near["variantIndices"], [0, 3], "inserted before the variant range")
        node = near["nodes"][2]
        self.assertEqual(node["type"], "worldMeshNode")
        self.assertEqual(node["data"]["mesh"]["DepotPath"]["$value"], "mod\\ls\\procedural\\wall.mesh")
        self.assertEqual(node["data"]["meshAppearance"]["$value"], "white")
        self.assertAlmostEqual(node["rotation"]["k"], math.sqrt(0.5))
        self.assertEqual((node["primaryRange"], node["secondaryRange"]), (90.0, 108.0))
        self.assertLessEqual(near["min"]["z"], -1)
        manifest = json.loads((ws / ".cp77wb-build.json").read_text())
        self.assertIn("worldMeshNode", manifest["nativeRequiredTypes"])
        self.assertNotEqual(manifest["exportSha256"], "x")
        self.assertEqual(manifest["sourceExportSha256"], "x")
        # Re-running replaces, never duplicates.
        again = pg.inject_nodes(export, [wall_object()])
        self.assertEqual(sum(1 for n in export["sectors"][1]["nodes"] if (n.get("locationstudio") or {}).get("procedural")), 1)
        self.assertEqual(again[0]["sector"], "near")

    def test_blocking_issues(self):
        for obj, cli, needle in ((wall_object(template=""), fake_cli(self.root / "c1"), "no material.template"),
                                 (wall_object(template="base\\other.mesh"), fake_cli(self.root / "c2"), "not available locally"),
                                 (wall_object(), None, "CLI not found"),
                                 (wall_object(), fake_cli(self.root / "c3", fail=True), "did not import")):
            ws, report = self.run_stage(obj, cli)
            self.assertFalse(report["ready"], needle)
            self.assertIn(needle, report["issues"][0]["error"])
            export = json.loads((ws / "source" / "raw" / "demo_exported.json").read_text())
            self.assertEqual(len(export["sectors"][1]["nodes"]), 3, "nothing injected when not ready")
            import shutil
            shutil.rmtree(ws)

    def test_scope(self):
        ws, report = self.run_stage(wall_object(), fake_cli(self.root / "cli"), premise_id="other")
        self.assertEqual(report["objects"], 0)
        self.assertTrue(report["ready"])

    def test_custom_command(self):
        cli = fake_cli(self.root / "cli")
        with patch.dict(os.environ, {"LOCATION_STUDIO_MESH_IMPORT_CMD": json.dumps(["{cli}", "import", "-p", "{glb}", "--keep"])}):
            _, report = self.run_stage(wall_object(), cli)
        self.assertTrue(report["ready"], report["issues"])


class ToolTests(unittest.TestCase):
    def test_tools(self):
        sent: list[tuple[str, dict]] = []
        with patch.object(server, "_send", lambda op, args=None, **_k: sent.append((op, args or {})) or {"ok": True}):
            call(server.procedural_generators)
            call(server.procedural_preview_parts, "stairs", {"height": 3})
            call(server.procedural_create, "wall", {"length": 5}, name="W", position=[1, 2, 3], yaw=90, material_template="base\\a.mesh")
            call(server.procedural_create, "ramp", source="aim")
            with self.assertRaises(ValueError):
                call(server.procedural_create, "ramp", source="moon")
            call(server.procedural_update, "o1", {"height": 4}, appearance="dirty", collision=False)
            call(server.procedural_delete, "o1")
            call(server.procedural_list)
            call(server.procedural_show, "o1", visible=False)
            call(server.procedural_settings, proxy="mesh", proxy_asset_id="a1", proxy_native_size=[1, 1, 1], mesh_root="mod\\x")
        ops = {}
        for op, args in sent:
            ops.setdefault(op, []).append(args)
        create = ops["procedural_create"][0]
        self.assertEqual(create["transform"], {"position": {"x": 1.0, "y": 2.0, "z": 3.0, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": 90}})
        self.assertEqual(create["material"]["template"], "base\\a.mesh")
        self.assertEqual(ops["procedural_create"][1]["source"], "aim")
        self.assertEqual(ops["procedural_update"][0], {"id": "o1", "params": {"height": 4}, "replace_params": False, "material": {"appearance": "dirty"}, "collision": False})
        self.assertEqual(ops["procedural_settings"][0]["proxy_native_size"], {"x": 1.0, "y": 1.0, "z": 1.0})

    def test_export_glb(self):
        with tempfile.TemporaryDirectory() as td:
            project = Path(td) / "project.json"
            project.write_text(json.dumps({"objects": [wall_object()]}), encoding="utf-8")
            with patch.object(server, "PROJECT", project):
                out = call(server.procedural_export_glb, output_dir=td)
                self.assertEqual(out["count"], 1)
                self.assertEqual(out["files"][0]["triangles"], 12)
                self.assertTrue(Path(out["files"][0]["file"]).read_bytes().startswith(b"glTF"))
                with self.assertRaises(ValueError):
                    call(server.procedural_export_glb, object_id="missing")


if __name__ == "__main__":
    unittest.main()
