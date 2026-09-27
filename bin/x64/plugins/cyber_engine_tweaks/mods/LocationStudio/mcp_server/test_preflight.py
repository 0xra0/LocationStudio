#!/usr/bin/env python3
"""Shipping preflight: offline checks, merge rules and the MCP tool."""
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
from lsbuild import preflight as pf, sectors as _lssec  # noqa: E402
import test_sectors  # noqa: E402


def call(tool, *a, **k):
    return json.loads(getattr(tool, "fn", tool)(*a, **k))


LIVE = {"schema": "locationstudio-preflight/1", "ready": True, "live": True, "checks": [
    {"id": cid, "label": label, "status": "pass", "issues": []} for cid, label in pf.LIVE_CHECKS]}


def run_manifest(root: Path, run_id: str, status: str, cameras=None, created="2026-09-27T10:00:00+0000", **extra):
    d = root / "runs" / run_id
    d.mkdir(parents=True)
    (d / "manifest.json").write_text(json.dumps({"run_id": run_id, "status": status, "created_at": created,
                                                 "cameras": cameras or [], **extra}), encoding="utf-8")


class PreflightUnitTests(unittest.TestCase):
    def test_dependencies_check(self):
        c = pf.dependencies_check({"missing": [{"path": "mymod\\a.xbm", "chain": ["object:o1", "mymod\\a.mesh", "mymod\\a.xbm"]}],
                                   "raw_json_only": ["mymod\\b.mesh"], "external_requirements": {"other.archive": ["x"]},
                                   "unknown": [{"path": "y"}], "unverified": [{"reference": "record:A.b"}]})
        self.assertEqual(c["status"], "fail")
        self.assertEqual(c["issues"][0]["object_id"], "o1")
        self.assertIn("mymod\\a.mesh → mymod\\a.xbm", c["issues"][0]["message"])
        self.assertEqual([i["severity"] for i in c["issues"]], ["error", "error", "warning", "warning", "info"])
        self.assertEqual(pf.dependencies_check(None, "boom")["status"], "skipped")
        self.assertEqual(pf.dependencies_check({"missing": []})["status"], "pass")

    def test_sectors_check(self):
        with tempfile.TemporaryDirectory() as td:
            export, project = test_sectors.fixture(Path(td))
            data = json.loads(export.read_text())
            data["sectors"][0]["nodes"].append(test_sectors.node("[Mesh] Broken", None, 2, 2, data={"owner": "$/demo/#missing_thing"}))
            export.write_text(json.dumps(data))
            report = _lssec.inspect(export, project, include_nodes=True)
        c, refs, devices = pf.sectors_check(report)
        self.assertEqual(c["status"], "fail")
        self.assertTrue(any(i.get("object_id") == "obj_stray" for i in c["issues"]))
        by_ref = {i["node_ref"]: i["severity"] for i in refs}
        self.assertEqual(by_ref["$/demo/#missing_thing"], "error", "a missing ref under the export's own root")
        self.assertEqual(by_ref["$/03_night_city/#vanilla_sign"], "warning", "vanilla refs cannot be verified")
        self.assertEqual(len(devices), 1)
        self.assertIn("444", devices[0]["message"])
        self.assertEqual(pf.sectors_check(None)[0]["status"], "skipped")

    def test_visual_check(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.assertEqual(pf.visual_check(root)["status"], "skipped")
            run_manifest(root, "20260927-1", "passed")
            self.assertEqual(pf.visual_check(root)["status"], "pass")
            self.assertEqual(pf.visual_check(root, project_updated_at="2026-09-28T00:00:00Z")["status"], "warn", "stale run")
            run_manifest(root, "20260927-2", "regression", cameras=[
                {"camera_id": "c1", "name": "Lobby", "regression": True, "comparison": {"compatible": True, "changed_fraction": 0.12}},
                {"camera_id": "c2", "name": "Hall", "regression": False}])
            c = pf.visual_check(root)
            self.assertEqual(c["status"], "fail")
            self.assertIn("Lobby changed 12.0%", c["issues"][0]["message"])
            self.assertEqual(pf.visual_check(root, capture={"run_id": "x", "status": "captured"})["status"], "warn")
            self.assertEqual(pf.visual_check(root, capture={"run_id": "x", "status": "passed", "environment_mismatch": True})["status"], "warn")

    def test_merge(self):
        ok = pf.merge(LIVE, [pf.Check("dependencies", "Asset dependencies")])
        self.assertTrue(ok["ready"])
        offline_only = pf.merge(None, [pf.Check("dependencies", "Asset dependencies")], live_error="bridge offline")
        self.assertFalse(offline_only["ready"], "never ready without the in-game checks")
        self.assertEqual(offline_only["summary"]["skipped"], len(pf.LIVE_CHECKS))
        self.assertIn("bridge offline", offline_only["checks"][0]["note"])
        merged = pf.merge(LIVE, [], noderef_issues=[{"severity": "error", "message": "x"}], device_issues=[{"severity": "warning", "message": "y"}])
        by = {c["id"]: c for c in merged["checks"]}
        self.assertEqual((by["noderefs"]["status"], by["device_links"]["status"]), ("fail", "warn"))
        self.assertEqual(merged["blocking"], [{"check": "noderefs", "label": "NodeRefs", "errors": 1}])
        warn_only = pf.merge(LIVE, [pf.Check("x", "X").add("warning", "w")])
        self.assertTrue(warn_only["ready"])
        self.assertFalse(pf.merge(LIVE, [pf.Check("x", "X").add("warning", "w")], strict=True)["ready"])


class PreflightToolTests(unittest.TestCase):
    def test_tool(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            export, project = test_sectors.fixture(root)
            wb = root / "entSpawner"
            (wb / "export").mkdir(parents=True)
            export.rename(wb / "export" / "demo_exported.json")
            reg = root / "regression"
            run_manifest(reg, "20260927-1", "passed")
            sent: list[str] = []

            def fake_send(op, args=None, **_k):
                sent.append(op)
                if op == "preflight_run":
                    return LIVE
                return {"ok": True}

            with patch.object(server, "PROJECT", project), patch.object(server, "WORLD_BUILDER_ROOT", wb), \
                    patch.object(server, "MOD_SOURCES", root / "mod_sources"), patch.object(server, "VANILLA_INDEX", root / "none.bin"), \
                    patch.object(server, "DEPENDENCY_REPORT", root / "exports/dependency-report.json"), \
                    patch.object(server, "PREFLIGHT_REPORT", root / "exports/preflight-report.json"), \
                    patch.object(server, "REGRESSION_DIR", reg), patch.object(server, "_send", fake_send):
                out = call(server.preflight_run)
                self.assertEqual(out["scope"]["export"], str(wb / "export" / "demo_exported.json"))
                by = {c["id"]: c for c in out["checks"]}
                for cid in ("dependencies", "sectors", "native_interactables", "npc_population", "visual_regression", "noderefs", "device_links", "spawns"):
                    self.assertIn(cid, by)
                self.assertEqual(by["sectors"]["status"], "fail")
                self.assertEqual(by["noderefs"]["status"], "warn", "only the vanilla sign ref is unresolved")
                self.assertEqual(by["device_links"]["status"], "fail")
                self.assertEqual(by["visual_regression"]["status"], "pass")
                self.assertFalse(out["ready"])
                self.assertIn("sectors", [b["check"] for b in out["blocking"]])
                saved = json.loads((root / "exports/preflight-report.json").read_text())
                self.assertEqual(saved["schema"], "locationstudio-preflight/1")
                self.assertEqual(sent, ["preflight_run", "preflight_load"])

                def offline(op, args=None, **_k):
                    raise RuntimeError("LocationStudio bridge is offline")
                with patch.object(server, "_send", offline):
                    off = call(server.preflight_run, export_name="missing", write_report=False)
                self.assertFalse(off["ready"])
                self.assertIn("offline", off["live_error"])
                by = {c["id"]: c for c in off["checks"]}
                self.assertEqual(by["spawns"]["status"], "skipped")
                self.assertEqual(by["sectors"]["status"], "skipped")
                self.assertIn("not found", by["sectors"]["note"])


if __name__ == "__main__":
    unittest.main()
