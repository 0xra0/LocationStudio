"""Safe read/write helpers for World Builder's native Favorites JSON files."""
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from typing import Any


def _read_category(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as stream:
        data = json.load(stream)
    if not isinstance(data, dict) or not isinstance(data.get("favorites"), list):
        raise ValueError(f"Not a World Builder Favorites category: {path.name}")
    return data


def list_favorites(directory: Path, category_filter: str = "") -> dict[str, Any]:
    if not directory.is_dir():
        return {"available": False, "directory_exists": False, "count": 0, "categories": [],
                "reason": f"World Builder Favorites directory not found: {directory}"}
    categories: list[dict[str, Any]] = []
    warnings: list[dict[str, str]] = []
    for path in sorted(directory.glob("*.json"), key=lambda item: item.name.casefold()):
        try:
            data = _read_category(path)
            name = str(data.get("name") or path.stem)
            if category_filter and category_filter.casefold() not in name.casefold():
                continue
            entries = []
            for favorite in data["favorites"]:
                if not isinstance(favorite, dict):
                    continue
                item = favorite.get("data") if isinstance(favorite.get("data"), dict) else {}
                spawnable = item.get("spawnable") if isinstance(item.get("spawnable"), dict) else {}
                entries.append({"name": favorite.get("name"), "icon": favorite.get("icon", ""),
                                "tags": favorite.get("tags", {}), "module_path": spawnable.get("modulePath"),
                                "spawn_data": spawnable.get("spawnData"), "data_type": spawnable.get("dataType")})
            categories.append({"name": name, "file": path.name, "count": len(entries), "favorites": entries})
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            warnings.append({"file": path.name, "error": str(exc)})
    return {"available": True, "directory_exists": True, "count": sum(c["count"] for c in categories),
            "category_count": len(categories), "categories": categories, "warnings": warnings}


def _identity(favorite: dict[str, Any]) -> tuple[str, str]:
    data = favorite.get("data") if isinstance(favorite.get("data"), dict) else {}
    spawnable = data.get("spawnable") if isinstance(data.get("spawnable"), dict) else {}
    return str(spawnable.get("modulePath") or ""), str(spawnable.get("spawnData") or "").casefold()


def _safe_new_name(category: str, directory: Path) -> str:
    slug = re.sub(r"[^A-Za-z0-9_-]+", "_", category).strip("_") or "LocationStudio"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    candidate = f"{slug}_{stamp}.json"
    counter = 1
    while (directory / candidate).exists():
        candidate = f"{slug}_{stamp}_{counter}.json"
        counter += 1
    return candidate


def _write_atomic(path: Path, payload: dict[str, Any]) -> None:
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=4)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp_name, path)
    finally:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass


def add_favorite(directory: Path, category_name: str, favorite: dict[str, Any], *, write: bool = False) -> dict[str, Any]:
    category_name = str(category_name or "").strip()
    if not category_name or len(category_name) > 100:
        raise ValueError("category must be 1–100 characters")
    if not directory.is_dir():
        raise FileNotFoundError(f"World Builder Favorites directory not found: {directory}")
    if not isinstance(favorite, dict) or not str(favorite.get("name") or "").strip():
        raise ValueError("live World Builder favorite payload is invalid")
    identity = _identity(favorite)
    if not all(identity):
        raise ValueError("favorite payload is missing its live spawn class or resource path")

    matches: list[Path] = []
    for candidate in sorted(directory.glob("*.json"), key=lambda item: item.name.casefold()):
        try:
            existing = _read_category(candidate)
        except (OSError, json.JSONDecodeError, ValueError):
            continue
        if str(existing.get("name") or "").casefold() == category_name.casefold():
            matches.append(candidate)
    if len(matches) > 1:
        raise ValueError(f"More than one favorites file is named {category_name!r}; resolve duplicate categories in World Builder first")

    is_new = not matches
    path = matches[0] if matches else directory / _safe_new_name(category_name, directory)
    if path.is_symlink() or path.resolve().parent != directory.resolve():
        raise ValueError("favorites category path is not a regular file in the World Builder Favorites directory")
    if is_new:
        category = {"name": category_name, "icon": "EmoticonOutline", "headerOpen": True,
                    "grouped": False, "virtualGroupsPS": {}, "favorites": []}
    else:
        category = _read_category(path)

    for current in category["favorites"]:
        if isinstance(current, dict) and _identity(current) == identity:
            return {"written": False, "already_favorite": True, "preview": not write,
                    "category": category_name, "file": path.name, "favorite_name": current.get("name"),
                    "backup": None, "changes": "No change; this resource is already in this category."}

    before_count = len(category["favorites"])
    category["favorites"].append(favorite)
    result = {"written": False, "already_favorite": False, "preview": not write,
              "category": category_name, "file": path.name, "favorite_name": favorite["name"],
              "resource": identity[1], "previous_count": before_count, "new_count": before_count + 1,
              "changes": "Append one native World Builder favorite; preserve all existing category fields."}
    if not write:
        result["requires"] = "Call again with write=true to commit this exact favorite."
        return result

    backup: Path | None = None
    if not is_new:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
        backup = path.with_name(f"{path.name}.bak-{stamp}")
        shutil.copy2(path, backup)
    _write_atomic(path, category)
    result.update({"written": True, "preview": False, "backup": backup.name if backup else None,
                   "reload_note": "World Builder loads Favorites at mod initialization; reload World Builder/CET or restart the game to refresh its in-memory panel."})
    return result
