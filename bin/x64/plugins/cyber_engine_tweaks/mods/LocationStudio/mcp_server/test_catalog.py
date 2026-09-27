#!/usr/bin/env python3
"""Offline asset catalog + semantic tools against a tiny fake World Builder data/spawnables tree."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import server  # noqa: E402


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.wb = root / "entSpawner"
        (self.wb / "data/spawnables/mesh/all").mkdir(parents=True)
        (self.wb / "data/spawnables/entity/templates").mkdir(parents=True)
        (self.wb / "data/spawnables/mesh/all/base.txt").write_text(
            "﻿base\\environment\\decoration\\furniture\\restaurant\\bar_stool\\bar_stool_a.mesh\n"
            "base\\environment\\architecture\\common\\wall\\rusty_metal_wall_a.mesh\n", encoding="utf-8")
        (self.wb / "data/spawnables/entity/templates/base.txt").write_text(
            "base\\environment\\decoration\\furniture\\chairs\\office_chair_a.ent\n", encoding="utf-8")
        self.saved = (server.ASSET_DB, server.WORLD_BUILDER_ROOT, server._send)
        server.ASSET_DB = root / "data" / "asset-catalog.sqlite3"
        server.WORLD_BUILDER_ROOT = self.wb
        self.sent = []

        def fake_send(op, args=None, timeout=None):
            self.sent.append((op, args))
            return {"asset": {"id": "asset_1"}, "already_registered": False}

        server._send = fake_send

    def tearDown(self):
        server.ASSET_DB, server.WORLD_BUILDER_ROOT, server._send = self.saved
        self.tmp.cleanup()

    def test_search_requires_a_build(self):
        with self.assertRaises(FileNotFoundError):
            server.asset_catalog_search("stool")

    def test_build_search_semantic_and_import(self):
        built = json.loads(server.asset_catalog_build())
        # Static Mesh lists feed the Mesh, Rotating Mesh and Proxy Mesh variants, like WB's Spawn UI.
        self.assertEqual(built["assets"], 7)
        info = json.loads(server.asset_catalog_info())
        self.assertEqual(info["assets"], 7)

        hits = json.loads(server.asset_catalog_search("bar stool", variant="Mesh"))["results"]
        self.assertEqual(len(hits), 1)
        stool = hits[0]
        self.assertTrue(stool["spawn_data"].endswith("bar_stool_a.mesh"))
        self.assertFalse(stool["has_template"])
        self.assertEqual(json.loads(server.asset_catalog_get(f"#{stool['id']}"))["id"], stool["id"])
        with self.assertRaises(ValueError):
            server.asset_catalog_get("stool")

        with self.assertRaises(Exception):
            server.asset_semantic_search("chair")  # semantic index not built yet
        json.loads(server.asset_semantic_build())
        rusty = json.loads(server.asset_semantic_search("wall", condition="rusty"))["results"]
        self.assertTrue(rusty and all("rusty" in r["conditions"] for r in rusty))
        chairs = json.loads(server.asset_semantic_search("chair", role="furniture", category="Entity"))["results"]
        with self.assertRaisesRegex(ValueError, "valid values: .*furniture"):
            server.asset_semantic_search("chair", role="chair")
        self.assertEqual([r["file_name"] for r in chairs], ["office_chair_a.ent"])

        result = json.loads(server.import_catalog_asset(str(stool["id"])))
        op, args = self.sent[-1]
        self.assertEqual(op, "import_catalog_asset")
        self.assertEqual(args["record"]["category"], "Mesh")
        self.assertEqual(args["record"]["variant"], "Mesh")
        self.assertTrue(args["record"]["spawn_data"].endswith("bar_stool_a.mesh"))
        self.assertEqual(result["catalog_id"], stool["id"])


if __name__ == "__main__":
    unittest.main()
