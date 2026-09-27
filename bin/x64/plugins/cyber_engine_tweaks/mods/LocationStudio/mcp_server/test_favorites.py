#!/usr/bin/env python3
"""Filesystem contract tests for native World Builder Favorites writes."""
from __future__ import annotations

import json
from pathlib import Path
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from wbfavorites import add_favorite, list_favorites


def _favorite(name: str = "Chair") -> dict:
    return {"name": name, "icon": "", "tags": {"test": True}, "data": {
        "name": name, "modulePath": "modules/classes/editor/spawnableElement",
        "spawnable": {"modulePath": "mesh/mesh", "spawnData": "base\\props\\chair.mesh", "dataType": "Spawnable"}}}


def test_preview_write_backup_and_unknown_field_preservation() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        existing = folder / "Props.json"
        original = {"name": "Props", "icon": "Cube", "favorites": [], "futureField": {"keep": 42}}
        existing.write_text(json.dumps(original), encoding="utf-8")
        preview = add_favorite(folder, "Props", _favorite(), write=False)
        assert preview["preview"] and not preview["written"]
        assert json.loads(existing.read_text(encoding="utf-8")) == original
        written = add_favorite(folder, "Props", _favorite(), write=True)
        assert written["written"] and written["backup"]
        payload = json.loads(existing.read_text(encoding="utf-8"))
        assert payload["futureField"] == {"keep": 42}
        assert len(payload["favorites"]) == 1
        assert (folder / written["backup"]).read_text(encoding="utf-8") == json.dumps(original)
        assert list_favorites(folder)["count"] == 1
        duplicate = add_favorite(folder, "Props", _favorite("Renamed"), write=True)
        assert duplicate["already_favorite"] and not duplicate["written"]


def test_new_category_and_invalid_favorites() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        preview = add_favorite(folder, "LocationStudio", _favorite(), write=False)
        assert preview["preview"] and preview["file"].endswith(".json")
        assert list_favorites(folder)["category_count"] == 0
        result = add_favorite(folder, "LocationStudio", _favorite(), write=True)
        assert result["written"] and result["backup"] is None
        assert list_favorites(folder)["category_count"] == 1
        try:
            add_favorite(folder, "Bad", {"name": "invalid"}, write=True)
        except ValueError:
            pass
        else:
            raise AssertionError("invalid favorite payload was accepted")


if __name__ == "__main__":
    test_preview_write_backup_and_unknown_field_preservation()
    test_new_category_and_invalid_favorites()
    print("World Builder Favorites write tests: OK")
