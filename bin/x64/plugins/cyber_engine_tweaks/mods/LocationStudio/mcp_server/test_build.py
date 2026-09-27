#!/usr/bin/env python3
"""Headless build pipeline tests (lsbuild + build_* MCP tools).

Fixtures are cp77wb 1.0.1's own contract fakes: a fake .NET worker speaking
the worker protocol and a fake WolvenKit CLI `pack`. They prove orchestration,
gating and file layout, not real CR2W correctness; run build_worker_preflight
on a real machine for that.
"""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import server  # noqa: E402
from lsbuild import build as _lsb, worker as _lsw  # noqa: E402


def write_export(path: Path, *, duplicate_ref: bool = False, devices: bool = True) -> Path:
    nodes = [
        {
            "name": "Wall", "type": "worldStaticMeshNode", "nodeRef": "$/demo/#wall",
            "position": {"x": 1, "y": 2, "z": 3},
            "rotation": {"i": 0, "j": 0, "k": 0, "r": 1},
            "scale": {"x": 1, "y": 1, "z": 1},
            "primaryRange": 100, "secondaryRange": 50, "uk10": 0, "uk11": 0,
            "data": {"debugName": {"$type": "CName", "$storage": "string", "$value": "Wall"}},
        },
        {
            "name": "Lamp", "type": "worldStaticMeshNode", "nodeRef": "$/demo/#wall" if duplicate_ref else "$/demo/#lamp",
            "position": {"x": 4, "y": 5, "z": 6},
            "rotation": {"i": 0, "j": 0, "k": 0, "r": 1},
            "scale": {"x": 1, "y": 1, "z": 1},
            "primaryRange": 100, "secondaryRange": 50, "uk10": 0, "uk11": 0,
            "data": {"debugName": {"$type": "CName", "$storage": "string", "$value": "Lamp"}},
        },
    ]
    data = {
        "name": "demo_world", "xlFormat": 1, "version": "1.0.4",
        "sectors": [{"name": "sector_a", "min": {"x":0,"y":0,"z":0}, "max": {"x":10,"y":10,"z":10}, "category":"Exterior", "level":255, "variantIndices":[0], "variants":[], "nodes": nodes}],
        "devices": ({"123": {"hash":"123","children":[],"parents":[],"className":"DevicePS","nodePosition":{"x":1,"y":2,"z":3}}} if devices else {}),
        "psEntries": ({"456": {"PSID":"456","instanceData":{"$type":"gamePersistentStateDataResource"}}} if devices else {}),
    }
    path.write_text(json.dumps(data), encoding="utf-8")
    return path




def write_fake_worker(path: Path, *, protocol: str = _lsw.WORKER_PROTOCOL) -> Path:
    path.write_text(f'''#!/usr/bin/env python3
import json,sys,pathlib
PROTOCOL={protocol!r}
def out(x): print(json.dumps(x,separators=(",",":")))
cmd=sys.argv[1] if len(sys.argv)>1 else "help"
if cmd=="selftest":
 out({{"protocol":PROTOCOL,"ready":True,"apiProfile":"fake-profile","wolvenKitVersion":"9.0.1","dotnetVersion":"10.0.0","capabilities":{{"createTemplates":True,"jsonToCr2w":True}}}});sys.exit(0)
if cmd=="inspect":
 out({{"protocol":PROTOCOL,"apiProfile":"fake-profile","wolvenKitVersion":"9.0.1","dotnetVersion":"10.0.0","discovery":{{"serializer":"Fake.RedJsonSerializer","writer":"Fake.CR2WWriter","serializerMethods":["Serialize(Fake)"],"writerMethods":["Write(Fake)"]}}}});sys.exit(0)
if cmd=="templates":
 a=sys.argv; types=json.loads(pathlib.Path(a[a.index("--types")+1]).read_text()); target=pathlib.Path(a[a.index("--output")+1])
 base={{
 "worldStreamingSector":{{"nodes":[],"nodeRefs":[],"nodeData":{{}}}},
 "gameDeviceResource":{{}},"gamePersistentStateDataResource":{{}},"worldStreamingBlock":{{"descriptors":[]}},
 "worldStreamingSectorDescriptor":{{"category":"Exterior","level":255,"numNodeRanges":1,"streamingBox":{{"Max":{{"X":0,"Y":0,"Z":0}},"Min":{{"X":0,"Y":0,"Z":0}}}},"data":{{"DepotPath":{{"$type":"ResourcePath","$storage":"uint64","$value":"0"}}}},"questPrefabNodeRef":{{"$type":"NodeRef","$storage":"uint64","$value":"0"}},"variants":[]}},
 "worldStreamingSectorVariant":{{"enabledByDefault":False,"name":{{"$type":"CName","$storage":"string","$value":""}},"nodeRef":{{"$type":"NodeRef","$storage":"uint64","$value":"0"}},"rangeIndex":0,"variantId":0}},
 "worldStaticMeshNode":{{"debugName":{{"$type":"CName","$storage":"string","$value":""}}}}
 }}
 target.parent.mkdir(parents=True,exist_ok=True);target.write_text(json.dumps({{"schema":"cp77wb-wkit-templates/1","generatedBy":"fake-worker","wolvenKitVersion":"9.0.1","types":{{t:base.get(t,{{}}) for t in types}}}}))
 out({{"protocol":PROTOCOL,"ok":True,"output":str(target),"count":len(types)}});sys.exit(0)
if cmd=="deserialize":
 a=sys.argv; target=pathlib.Path(a[a.index("--output")+1]);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b"CR2WFAKE")
 out({{"protocol":PROTOCOL,"ok":True,"output":str(target)}});sys.exit(0)
out({{"protocol":PROTOCOL,"error":"unsupported"}});sys.exit(2)
''', encoding='utf-8')
    path.chmod(0o755)
    return path




def write_fake_cli(path: Path) -> Path:
    path.write_text('#!/bin/sh\nout=""\nwhile [ "$#" -gt 0 ]; do if [ "$1" = "-o" ]; then shift; out="$1"; fi; shift; done\n'
                    'mkdir -p "$out"\nprintf REDARCHIVE > "$out/archive.archive"\n', encoding="utf-8")
    path.chmod(0o755)
    return path


class Sandbox:
    """Point server paths at a temp tree and fake the live CET export."""

    def __init__(self, root: Path, *, send_error: str | None = None):
        self.root = root
        self.send_error = send_error
        self.sent: list[tuple[str, dict]] = []

    def __enter__(self):
        self.saved = (server.WORLD_BUILDER_ROOT, server.BUILD_ROOT, server._send)
        server.WORLD_BUILDER_ROOT = self.root / "entSpawner"
        server.BUILD_ROOT = self.root / "build"

        def fake_send(op, args=None, timeout=None):
            self.sent.append((op, args or {}))
            if self.send_error:
                raise RuntimeError(self.send_error)
            if op == "build_export_status":
                return {"available": True}
            if op == "import_world_builder_build":
                return {"dry_run": args["dry_run"]}
            name = args["name"]
            out = server.WORLD_BUILDER_ROOT / "export" / f"{name}_exported.json"
            out.parent.mkdir(parents=True, exist_ok=True)
            write_export(out, devices=False)
            data = json.loads(out.read_text())
            data["name"] = name
            out.write_text(json.dumps(data))
            return {"name": name, "exported": 2, "skipped": []}

        server._send = fake_send
        return self

    def __exit__(self, *exc):
        server.WORLD_BUILDER_ROOT, server.BUILD_ROOT, server._send = self.saved


class HeadlessBuildTests(unittest.TestCase):
    def test_worker_source_is_vendored(self):
        src = Path(_lsw.__file__).resolve().parent / "wkit_worker"
        for name in ("Program.cs", "cp77wb-wkit-worker.csproj", "build.sh"):
            self.assertTrue((src / name).is_file(), name)
        preview = _lsw.build_worker(run=False)
        self.assertEqual(Path(preview["source"]), src / "cp77wb-wkit-worker.csproj")
        self.assertFalse(preview.get("ran", False))

    def test_worker_found_in_default_publish_dir(self):
        saved = _lsw.LOCAL_PUBLISH_DIR
        with tempfile.TemporaryDirectory() as td:
            _lsw.LOCAL_PUBLISH_DIR = Path(td)
            try:
                target = write_fake_worker(Path(td) / _lsw.DEFAULT_WORKER_NAME)
                found = _lsw._resolve_worker(None)
                if found != str(target):
                    self.skipTest(f"a worker on PATH or CP77WB_WKIT_WORKER takes precedence: {found}")
                self.assertEqual(found, str(target))
            finally:
                _lsw.LOCAL_PUBLISH_DIR = saved

    def test_preview_writes_nothing(self):
        with tempfile.TemporaryDirectory() as td, Sandbox(Path(td)) as box:
            result = json.loads(server.build_mod_from_project("demo_world", worker=str(Path(td) / "missing")))
            self.assertFalse(result["ran"])
            self.assertFalse(result["ready"])
            self.assertEqual([op for op, _ in box.sent], ["build_export_status"])
            self.assertFalse((Path(td) / "build").exists())
            self.assertFalse((Path(td) / "entSpawner").exists())

    def test_full_pipeline_with_contract_fakes(self):
        with tempfile.TemporaryDirectory() as td, Sandbox(Path(td)) as box:
            root = Path(td)
            worker = write_fake_worker(root / "worker")
            cli = write_fake_cli(root / "cp77tools")
            result = json.loads(server.build_mod_from_project("demo_world", premise_id="p1", worker=str(worker),
                                                              cli=str(cli), run=True))
            self.assertTrue(result["ok"], json.dumps(result.get("stages"), indent=1)[:3000])
            self.assertEqual(box.sent[0], ("build_export_world_builder", {"name": "demo_world", "premise_id": "p1",
                                                                         "streaming": {}, "xl_format": 0,
                                                                         "allow_skipped": False}))
            layout = Path(result["layout"])
            self.assertEqual((layout / "archive/pc/mod/demo_world.archive").read_bytes(), b"REDARCHIVE")
            self.assertTrue((layout / "archive/pc/mod/demo_world.xl").is_file())
            self.assertTrue(Path(result["zip"]).is_file())
            self.assertTrue(result["stages"]["status"]["importComplete"])
            self.assertTrue(result["stages"]["verify"]["valid"])

    def test_pipeline_reports_failing_stage(self):
        with tempfile.TemporaryDirectory() as td, Sandbox(Path(td), send_error="bridge offline"):
            result = json.loads(server.build_mod_from_project("demo_world", run=True))
            self.assertFalse(result["ok"])
            self.assertEqual(result["failed_stage"], "export")
            self.assertIn("bridge offline", result["stages"]["export"]["error"])

    def test_pipeline_stops_before_pack_without_worker(self):
        with tempfile.TemporaryDirectory() as td, Sandbox(Path(td)):
            result = json.loads(server.build_mod_from_project("demo_world", worker=str(Path(td) / "missing"), run=True))
            self.assertEqual(result["failed_stage"], "convert")
            self.assertNotIn("pack", result["stages"])

    def test_deploy_defaults_to_preview(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            layout = root / "dist" / "archive" / "pc" / "mod"
            layout.mkdir(parents=True)
            (layout / "demo_world.archive").write_bytes(b"RED")
            game = root / "game"
            game.mkdir()
            result = json.loads(server.build_deploy(str(root / "dist"), game_root=str(game)))
            self.assertFalse((game / "archive/pc/mod/demo_world.archive").exists())
            self.assertFalse(result.get("applied", False))

    def test_export_name_resolution(self):
        with tempfile.TemporaryDirectory() as td, Sandbox(Path(td)):
            self.assertEqual(server._export_file("abc"), Path(td) / "entSpawner" / "export" / "abc_exported.json")
            self.assertEqual(server._export_file("/x/y.json"), Path("/x/y.json"))

    def test_list_and_import_saved_builds(self):
        with tempfile.TemporaryDirectory() as td, Sandbox(Path(td)) as box:
            objects = Path(td) / "entSpawner" / "data" / "objects"
            objects.mkdir(parents=True)
            leaf = {"name": "Wall", "modulePath": "modules/classes/editor/spawnableElement", "childs": [],
                    "spawnable": {"modulePath": "mesh/mesh", "spawnData": "base\\a.mesh"}}
            (objects / "bar.json").write_text("\ufeff" + json.dumps({"name": "Bar", "modulePath": "modules/classes/editor/positionableGroup",
                                                                     "childs": [leaf, {"name": "Sub", "modulePath": "modules/classes/editor/positionableGroup", "childs": [leaf]}]}),
                                              encoding="utf-8")
            (objects / "old.json").write_text(json.dumps({"name": "Old", "type": "group", "childs": []}), encoding="utf-8")
            listed = {b["name"]: b for b in json.loads(server.list_world_builder_builds())["builds"]}
            self.assertEqual((listed["bar"]["objects"], listed["bar"]["groups"], listed["bar"]["legacy"]), (2, 2, False))
            self.assertTrue(listed["old"]["legacy"])

            box_result = json.loads(server.import_world_builder_build("bar"))
            op, args = box.sent[-1]
            self.assertEqual(op, "import_world_builder_build")
            self.assertTrue(args["dry_run"], "import must default to a preview")
            self.assertEqual(args["source"], "bar")
            self.assertEqual(args["build"]["childs"][1]["name"], "Sub")
            self.assertEqual(box_result["file"], str(objects / "bar.json"))
            server.import_world_builder_build("bar", apply=True, spawn=True)
            self.assertFalse(box.sent[-1][1]["dry_run"])
            with self.assertRaises(FileNotFoundError):
                server.import_world_builder_build("missing")


if __name__ == "__main__":
    unittest.main()
