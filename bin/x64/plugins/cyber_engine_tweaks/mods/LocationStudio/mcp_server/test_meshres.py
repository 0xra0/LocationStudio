#!/usr/bin/env python3
"""Native mesh resources: encoders, CMesh documents, decoding, build stage and tools."""
from __future__ import annotations

import base64
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
from lsbuild import meshres as mr, procedural as pg  # noqa: E402
from lsbuild.build import MANIFEST_SCHEMA  # noqa: E402


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


def box(cx, cy, cz, sx, sy, sz, material="main", rot=None):
    return {"shape": "box", "center": {"x": cx, "y": cy, "z": cz}, "size": {"x": sx, "y": sy, "z": sz},
            "rotation": rot or {"roll": 0, "pitch": 0, "yaw": 0}, "material": material}


MATS = {"main": "base\\surfaces\\plaster.mi", "glass": "base\\surfaces\\glass.mi"}

REFERENCE = {"Header": {"WolvenKitVersion": "8.16.0"}, "Data": {"RootChunk": {
    "$type": "CMesh", "objectType": "MeshType_Static", "cookingPlatform": "PLATFORM_PC", "consumingLodCount": 1,
    "renderResourceBlob": {"HandleId": "0", "Data": {"$type": "rendRenderMeshBlob", "header": {
        "$type": "rendRenderMeshBlobHeader", "version": 99, "dataProcessing": 7,
        "renderChunkInfos": [{"$type": "rendChunk", "vertexFactory": 25, "renderMask": 3, "mergedRenderMask": 1,
                              "chunkVertices": {"$type": "rendVertexBufferChunk", "byteOffsets": [0, 0, 0, 0, 0], "vertexLayout": {
                                  "elements": [
                                      {"type": "PT_Float3", "usage": "PS_Position", "usageIndex": 0, "streamIndex": 0, "streamType": "ST_PerVertex"},
                                      {"type": "PT_Float16_2", "usage": "PS_TexCoord", "usageIndex": 0, "streamIndex": 1, "streamType": "ST_PerVertex"},
                                      {"type": "PT_Byte4N", "usage": "PS_Normal", "usageIndex": 0, "streamIndex": 1, "streamType": "ST_PerVertex"},
                                      {"type": "PT_Dec4", "usage": "PS_Tangent", "usageIndex": 0, "streamIndex": 1, "streamType": "ST_PerVertex"},
                                      {"type": "PT_UInt1", "usage": "PS_LightBlockerIntensity", "usageIndex": 0, "streamIndex": 2, "streamType": "ST_PerVertex"}],
                                  "slotStrides": [12, 16, 4, 0, 0, 0, 0, 0]}}}]}}}}}}


class EncodingTests(unittest.TestCase):
    def test_roundtrip(self):
        cases = {"PT_Float3": ((1.5, -2.25, 3.0), 1e-9), "PT_Float16_2": ((0.5, 12.25), 1e-3), "PT_Short4N": ((0.5, -0.25, 1.0, -1.0), 1e-4),
                 "PT_Dec4": ((0.6, -0.8, 0.0, 1.0), 2e-3), "PT_Color": ((1.0, 0.5, 0.0, 1.0), 3e-3), "PT_Byte4N": ((0.6, -0.8, 0.0, 1.0), 1e-2),
                 "PT_UShort2N": ((0.25, 0.75), 1e-4), "PT_UByte4": ((1, 2, 3, 4), 0)}
        for etype, (values, tol) in cases.items():
            raw = mr.encode(etype, values)
            self.assertEqual(len(raw), mr.PACKING[etype][0], etype)
            back = mr.decode_value(etype, raw)
            for a, b in zip(values, back):
                self.assertAlmostEqual(a, b, delta=tol + 1e-12, msg=etype)
        self.assertEqual(mr.decode_value("PT_Dec4", mr.encode("PT_Dec4", (0, 0, 1, -1)))[3], -1.0, "tangent sign")

    def test_layout(self):
        layout = mr.Layout(mr.BUILTIN_LAYOUT)
        self.assertEqual(layout.strides, {0: 8, 1: 4, 2: 8, 3: 8})
        self.assertEqual(layout.json()["slotMask"], 0b1111)
        with self.assertRaises(ValueError):
            mr.Layout([{"type": "PT_UByte4", "usage": "PS_SkinIndices", "streamIndex": 0}, {"type": "PT_Float3", "usage": "PS_Position"}])
        with self.assertRaises(ValueError):
            mr.Layout([{"type": "PT_Float3", "usage": "PS_Normal"}])
        padded = mr.Layout.from_json(REFERENCE["Data"]["RootChunk"]["renderResourceBlob"]["Data"]["header"]["renderChunkInfos"][0]["chunkVertices"]["vertexLayout"], "reference")
        self.assertEqual(padded.strides[1], 16, "reference slot strides with padding are honoured")


class MeshResourceTests(unittest.TestCase):
    def mesh(self):
        rot = {"roll": 0, "pitch": 0, "yaw": 30}
        return pg.mesh_from_parts([box(0, 0, 1.5, 4, 0.2, 3, rot=rot), box(1, 0, 1, 1, 0.01, 1, material="glass")], uv_scale=2)

    def test_builtin_document(self):
        mesh = self.mesh()
        r = mr.build_mesh_resource(mesh, MATS, lod_distances=[25])
        doc, st = r["document"], r["stats"]
        root = doc["Data"]["RootChunk"]
        self.assertEqual(root["$type"], "CMesh")
        self.assertEqual(st["layout_source"], "builtin-unverified")
        self.assertIn("reference", st["warning"])
        self.assertEqual((st["chunks"], st["vertices"], st["indices"]), (2, 48, 72))
        self.assertEqual(root["lodLevelInfo"], [0.0, 25.0])
        self.assertEqual([m["name"]["$value"] for m in root["materialEntries"]], ["glass", "main"])
        self.assertEqual([m["DepotPath"]["$value"] for m in root["externalMaterials"]], [MATS["glass"], MATS["main"]])
        self.assertEqual(root["appearances"][0]["Data"]["chunkMaterials"][1]["$value"], "main")
        ids = [root["renderResourceBlob"]["HandleId"], root["appearances"][0]["HandleId"]]
        self.assertEqual(len(set(ids)), 2, "unique handle ids")
        header = root["renderResourceBlob"]["Data"]["header"]
        raw = base64.b64decode(root["renderResourceBlob"]["Data"]["renderBuffer"]["Bytes"])
        self.assertEqual(header["indexBufferOffset"] % 16, 0)
        self.assertEqual(len(raw), header["indexBufferOffset"] + header["indexBufferSize"])
        self.assertEqual(header["vertexBufferSize"] <= header["indexBufferOffset"], True)
        for c in header["renderChunkInfos"]:
            self.assertEqual((c["lodMask"], c["chunkIndices"]["pe"]), (1, "IBCT_Uint16"))
            self.assertEqual(c["vertexFactory"], mr.BUILTIN_VERTEX_FACTORY)
        bb = root["boundingBox"]
        self.assertAlmostEqual(bb["Max"]["Z"], 3.0)
        self.assertGreater(root["surfaceAreaPerAxis"]["Z"], 0)

    def test_decode_matches_source(self):
        mesh = self.mesh()
        doc = mr.build_mesh_resource(mesh, MATS)["document"]
        d = mr.decode(doc, vertices=True)
        src = mesh.prims["main"]
        chunk = d["chunks"][1]
        self.assertEqual(chunk["indices_data"], src["idx"])
        scale = max(b - a for a, b in zip(d["bounds"]["min"], d["bounds"]["max"]))
        for got, want in zip(chunk["attributes"]["PS_Position0"], src["pos"]):
            for k in range(3):
                self.assertAlmostEqual(got[k], want[k], delta=scale / 32767 + 1e-6)
        for got, want in zip(chunk["attributes"]["PS_Normal0"], src["nrm"]):
            for k in range(3):
                self.assertAlmostEqual(got[k], want[k], delta=3e-3)
        for got, want in zip(chunk["attributes"]["PS_TexCoord0"], src["uv"]):
            self.assertAlmostEqual(got[0], want[0], delta=2e-3)
        for t, n in zip(chunk["attributes"]["PS_Tangent0"], chunk["attributes"]["PS_Normal0"]):
            self.assertLess(abs(sum(t[k] * n[k] for k in range(3))), 1e-2, "tangent is perpendicular to the normal")
        self.assertEqual(d["external_materials"], [MATS["glass"], MATS["main"]])

    def test_reference_layout(self):
        mesh = pg.mesh_from_parts([box(0, 0, 0.5, 1, 1, 1)])
        r = mr.build_mesh_resource(mesh, {"main": MATS["main"]}, reference=REFERENCE)
        root = r["document"]["Data"]["RootChunk"]
        header = root["renderResourceBlob"]["Data"]["header"]
        chunk = header["renderChunkInfos"][0]
        self.assertEqual(r["stats"]["layout_source"], "reference")
        self.assertNotIn("warning", r["stats"])
        self.assertEqual((header["version"], header["dataProcessing"], chunk["vertexFactory"], chunk["renderMask"]), (99, 7, 25, 3))
        self.assertEqual(root["consumingLodCount"], 1, "other reference fields are kept")
        d = mr.decode(r["document"], vertices=True)
        self.assertEqual(d["chunks"][0]["layout"][0], "PS_Position0:PT_Float3@0")
        self.assertEqual(d["chunks"][0]["attributes"]["PS_Position0"][0], tuple(mesh.prims["main"]["pos"][0]), "float positions are exact")
        self.assertEqual(d["chunks"][0]["strides"][1], 16)
        with self.assertRaises(ValueError):
            mr.build_mesh_resource(mesh, MATS, reference={"Data": {"RootChunk": {"$type": "CMaterialInstance"}}})

    def test_errors_and_split(self):
        mesh = self.mesh()
        with self.assertRaises(ValueError):
            mr.build_mesh_resource(mesh, {"main": MATS["main"]})
        with self.assertRaises(ValueError):
            mr.build_mesh_resource(mesh, {"main": "base\\a.png", "glass": MATS["glass"]})
        with self.assertRaises(ValueError):
            mr.build_mesh_resource(pg.Mesh(), MATS)
        n = 70000
        prim = {"pos": [(i, 0.0, 0.0) for i in range(n)], "nrm": [(0.0, 0.0, 1.0)] * n, "uv": [(0.0, 0.0)] * n, "idx": list(range(n - n % 3))}
        chunks = mr._split(prim)
        self.assertEqual(len(chunks), 2)
        self.assertTrue(all(len(c["pos"]) <= mr.MAX_CHUNK_VERTICES for c in chunks))
        self.assertEqual(sum(len(c["idx"]) for c in chunks), len(prim["idx"]))
        self.assertEqual(chunks[1]["pos"][0], prim["pos"][chunks[0]["idx"].__len__()])


def fake_worker(path: Path, *, ok: bool = True) -> Path:
    body = ("import sys\nargs=sys.argv[1:]\nout=args[args.index('--output')+1]\n"
            + ("open(out,'wb').write(b'CR2W'+open(args[args.index('--input')+1],'rb').read()[:8])\n" if ok else "sys.exit(4)\n"))
    path.write_text(f"#!{sys.executable}\n" + body, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IEXEC)
    return path


def native_object():
    return {"id": "obj_w", "name": "Wall", "premise_id": "p1", "layer": "shell", "enabled": True,
            "transform": {"position": {"x": 5, "y": 5, "z": 0}, "rotation": {"yaw": 0}},
            "metadata": {"procedural": {"generator": "window", "parts": [box(0, 0, 1.5, 4, 0.2, 3), box(0, 0, 1.5, 1, 0.01, 1, material="glass")],
                                        "bounds": {"min": {"x": -2, "y": -0.1, "z": 0}, "max": {"x": 2, "y": 0.1, "z": 3}},
                                        "mesh_path": "mod\\ls\\procedural\\window.mesh", "material": {"materials": MATS, "appearance": "default"}}}}


class StageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.project = self.root / "project.json"
        self.project.write_text(json.dumps({"objects": [native_object()]}), encoding="utf-8")
        self.ws = self.root / "ws"
        (self.ws / "source" / "raw").mkdir(parents=True)
        (self.ws / "source" / "raw" / "e.json").write_text(json.dumps({"sectors": [{"name": "s", "min": {"x": 0, "y": 0, "z": 0}, "max": {"x": 9, "y": 9, "z": 9}, "nodes": []}]}))
        (self.ws / ".cp77wb-build.json").write_text(json.dumps({"schema": MANIFEST_SCHEMA, "exportFile": "source/raw/e.json", "exportSha256": "x"}))

    def tearDown(self):
        self.tmp.cleanup()

    def test_native_backend(self):
        report = pg.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w")), reference=REFERENCE)
        self.assertTrue(report["ready"], report["issues"])
        entry = report["generated"][0]
        self.assertEqual((entry["backend"], entry["converted"]), ("native", True))
        self.assertEqual(entry["stats"]["layout_source"], "reference")
        mesh = self.ws / "source" / "archive" / "mod" / "ls" / "procedural" / "window.mesh"
        self.assertEqual(mesh.read_bytes()[:4], b"CR2W")
        doc = json.loads((self.ws / "source" / "raw" / "mod" / "ls" / "procedural" / "window.mesh.json").read_text())
        self.assertEqual(doc["Data"]["RootChunk"]["$type"], "CMesh")
        export = json.loads((self.ws / "source" / "raw" / "e.json").read_text())
        self.assertEqual(export["sectors"][0]["nodes"][0]["data"]["mesh"]["DepotPath"]["$value"], "mod\\ls\\procedural\\window.mesh")

    def test_native_failures(self):
        no_worker = pg.apply_to_workspace(self.project, self.ws, worker=None)
        self.assertIn("worker is not ready", no_worker["issues"][0]["error"])
        self.assertTrue(any("built-in" in w for w in no_worker.get("warnings", [])))
        bad = pg.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w2", ok=False)))
        self.assertIn("did not write a CR2W", bad["issues"][0]["error"])
        obj = native_object()
        obj["metadata"]["procedural"]["material"]["materials"] = {"main": MATS["main"]}
        self.project.write_text(json.dumps({"objects": [obj]}))
        missing = pg.apply_to_workspace(self.project, self.ws, worker=str(fake_worker(self.root / "w3")))
        self.assertIn("no material for slot(s) glass", missing["issues"][0]["error"])


class ToolTests(unittest.TestCase):
    def test_build_and_inspect(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            project = root / "project.json"
            project.write_text(json.dumps({"objects": [native_object()]}), encoding="utf-8")
            ref = root / "ref.mesh.json"
            ref.write_text(json.dumps(REFERENCE))
            worker = fake_worker(root / "w")
            with patch.object(server, "PROJECT", project), patch.object(server, "MOD_SOURCES", root / "none"), \
                    patch.object(server._lsw, "worker_preflight", lambda **k: {"ready": True, "worker": str(worker)}):
                out = call(server.mesh_resource_build, output_dir=str(root / "out"), reference_json=str(ref), lod_distances=[30], write_cr2w=True)
                row = out["meshes"][0]
                self.assertEqual((row["layout_source"], row["lod_levels"], row["cr2w_ok"]), ("reference", [0.0, 30.0], True))
                self.assertTrue(row["json"].endswith("window.mesh.json"))
                self.assertTrue(Path(row["cr2w"]).is_file())
                builtin = call(server.mesh_resource_build, output_dir=str(root / "out2"), materials={"main": MATS["main"], "glass": MATS["glass"]})
                self.assertEqual(builtin["meshes"][0]["layout_source"], "builtin-unverified")
                summary = call(server.mesh_resource_inspect, row["json"], vertices=True)
                self.assertEqual(len(summary["chunks"]), 2)
                self.assertIn("PS_Position0", summary["chunks"][1]["attributes"])
                ref_summary = call(server.mesh_resource_inspect, str(ref))
                self.assertEqual(ref_summary["chunks"][0]["vertex_factory"], 25)
                with self.assertRaises(ValueError):
                    call(server.mesh_resource_build, object_id="missing")
                with self.assertRaises(ValueError):
                    call(server.mesh_resource_inspect, str(root / "nope.json"))
            with patch.object(server, "PROJECT", project), patch.object(server._lsw, "worker_preflight", lambda **k: {"ready": False}):
                with self.assertRaises(RuntimeError):
                    call(server.mesh_resource_build, output_dir=str(root / "out3"), write_cr2w=True)


if __name__ == "__main__":
    unittest.main()
