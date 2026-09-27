#!/usr/bin/env python3
"""Per-sector streaming/performance estimate for World Builder exports."""
from __future__ import annotations

import importlib
import json
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lsbuild import performance, sectors  # noqa: E402


def node(ntype, x, y, data=None, **extra):
    out = {"name": f"{ntype}@{x},{y}", "type": ntype, "position": {"x": x, "y": y, "z": 0, "w": 0}, "data": data or {},
           "primaryRange": 100, "secondaryRange": 120}
    out.update(extra)
    return out


def export() -> dict:
    quiet = [node("worldStaticMeshNode", x, 0) for x in range(0, 40, 8)]
    busy = ([node("worldStaticLightNode", 101 + i * 0.2, 1, {"radius": 25}) for i in range(8)]
            + [node("worldStaticParticleNode", 102, 1 + i * 0.2, {"emissionRate": 20}) for i in range(6)]
            + [node("worldStaticDecalNode", 103, 2) for _ in range(5)]
            + [node("worldClothMeshNode", 104, 3), node("worldPopulationSpawnerNode", 104, 4),
               node("worldStaticSoundEmitterNode", 103, 3), node("worldStaticMeshNode", 130, 30, secondaryRange=3000),
               node("worldAreaShapeNode", 140, 40)])
    return {"name": "demo", "sectors": [
        {"name": "quiet", "min": {"x": 0, "y": -5, "z": -5}, "max": {"x": 40, "y": 5, "z": 5}, "nodes": quiet},
        {"name": "busy", "min": {"x": 100, "y": 0, "z": -5}, "max": {"x": 140, "y": 40, "z": 5}, "nodes": busy},
    ]}


class ExportPerformanceTests(unittest.TestCase):
    def test_counts_costs_budgets_and_clusters(self):
        report = performance.analyze_export(export(), budget={"lights": 6, "vfx": 4, "nodes": 1000},
                                            player={"x": 0, "y": 0, "z": 0})
        busy = report["sectors"][0]
        self.assertEqual(busy["name"], "busy", "sectors are sorted by cost")
        c = busy["counts"]
        self.assertEqual((c["nodes"], c["lights"], c["vfx"], c["decals"], c["audio"], c["dynamic"], c["static"], c["meta"]),
                         (24, 8, 6, 5, 1, 2, 1, 1))
        self.assertEqual(c["expensive"], 16, "large lights, high-emission particles, cloth and population spawner")
        self.assertEqual({o["metric"] for o in busy["over_budget"]}, {"lights", "vfx"})
        self.assertEqual(busy["long_streaming_total"], 1)
        self.assertAlmostEqual(busy["distance_from_player"], ((120 ** 2) + (20 ** 2)) ** 0.5, places=0)
        quiet = report["sectors"][1]
        self.assertEqual((quiet["counts"]["nodes"], quiet["over_budget"], quiet["expensive_total"]), (5, [], 0))
        self.assertEqual(len(report["clusters"]), 1, report["cluster_stats"])
        cluster = report["clusters"][0]
        self.assertEqual(cluster["sectors"], ["busy"])
        self.assertEqual(cluster["counts"]["lights"], 8)
        self.assertIn("distance_from_player", cluster)
        self.assertTrue(any(w["metric"] == "long_streaming_range" for w in report["warnings"]))

    def test_single_dense_cell_is_not_hidden_by_few_cells(self):
        rows = [{"position": {"x": 0.5, "y": 0.5, "z": 0}, "info": {"category": "lights", "cost": 100.0, "expensive": None}}]
        rows += [{"position": {"x": 20.0 * i, "y": 0, "z": 0}, "info": {"category": "static", "cost": 1.0, "expensive": None}} for i in range(1, 4)]
        found, stats = performance.clusters(rows)
        self.assertEqual(len(found), 1)
        self.assertEqual(stats["threshold"], 40.0)

    def test_sector_report_includes_performance(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "demo_exported.json"
            path.write_text(json.dumps(export()), encoding="utf-8")
            report = sectors.inspect(path)
            self.assertEqual(report["performance"]["totals"]["nodes"], 29)


class Tool:
    def __init__(self, fn):
        self.fn = fn


class MCPServer:
    def __init__(self, *_a, **_k): pass
    def tool(self): return lambda fn: Tool(fn)
    def resource(self, *_a, **_k): return lambda fn: fn


class PerformanceMcpTests(unittest.TestCase):
    def test_tools(self):
        fake_server = types.ModuleType("mcp.server")
        fake_server.MCPServer = MCPServer
        fake_mcp = types.ModuleType("mcp")
        fake_mcp.server = fake_server
        sys.modules.setdefault("mcp", fake_mcp)
        sys.modules.setdefault("mcp.server", fake_server)
        server = importlib.import_module("server")
        sent = []

        def fake_send(op, args=None, **_k):
            sent.append((op, args or {}))
            if op == "capture_player":
                return {"position": {"x": 0, "y": 0, "z": 0}}
            return {"ok": True}

        def call(tool, *a, **k):
            return json.loads(getattr(tool, "fn", tool)(*a, **k))

        with tempfile.TemporaryDirectory() as tmp, patch.object(server, "_send", fake_send):
            path = Path(tmp) / "demo_exported.json"
            path.write_text(json.dumps(export()), encoding="utf-8")
            result = call(server.performance_export, str(path))
            self.assertEqual(result["sectors"][0]["name"], "busy")
            self.assertIn("distance_from_player", result["sectors"][0])
            call(server.performance_analyze, premise_id="p1")
            call(server.performance_set_budget, "premise", lights=20)
            call(server.performance_select_cluster, 2)
            with self.assertRaises(ValueError):
                call(server.performance_set_budget, "sector", lights=1)
            with self.assertRaises(ValueError):
                call(server.performance_set_budget, "room")
        ops = [op for op, _ in sent]
        self.assertEqual(ops, ["capture_player", "performance_analyze", "performance_set_budget", "performance_select_cluster"])
        self.assertEqual(sent[2][1], {"scope": "premise", "values": {"lights": 20}})


if __name__ == "__main__":
    unittest.main()
