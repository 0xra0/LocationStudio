"""Bounded, read-only inventory of standard Cyberpunk 2077 mod locations."""
from __future__ import annotations

from pathlib import Path
from typing import Any


def scan_mod_installation(game_root: Path) -> dict[str, Any]:
    """List candidate mod filenames/folders without reading archive contents."""
    locations = {
        "archives": game_root / "archive" / "pc" / "mod",
        "redscript": game_root / "r6" / "scripts",
        "tweaks": game_root / "r6" / "tweaks",
        "red4ext": game_root / "bin" / "x64" / "plugins" / "red4ext" / "plugins",
        "cet": game_root / "bin" / "x64" / "plugins" / "cyber_engine_tweaks" / "mods",
    }
    # Also recognize a top-level red4ext layout used by some Linux mod setups.
    if not locations["red4ext"].is_dir():
        alternate = game_root / "red4ext" / "plugins"
        if alternate.is_dir():
            locations["red4ext"] = alternate
    result: dict[str, Any] = {
        "available": True,
        "game_root": str(game_root),
        "verified_compatibility": False,
        "locations": {},
    }
    for label, directory in locations.items():
        try:
            if not directory.is_dir():
                result["locations"][label] = {"path": str(directory), "exists": False, "count": 0, "entries": []}
                continue
            entries = sorted(directory.iterdir(), key=lambda item: item.name.casefold())
            if label in {"archives", "redscript", "tweaks"}:
                relevant = [entry for entry in entries if entry.is_dir() or entry.suffix.casefold() in {".archive", ".reds", ".yaml", ".yml"}]
            else:
                relevant = [entry for entry in entries if entry.is_dir() or entry.name.casefold() in {"info.json", "mod.json"}]
            result["locations"][label] = {
                "path": str(directory), "exists": True, "count": len(relevant),
                "entries": [entry.name for entry in relevant[:200]],
                "truncated": len(relevant) > 200,
            }
        except OSError as exc:
            result["locations"][label] = {"path": str(directory), "exists": None, "count": 0, "entries": [], "error": str(exc)}
    return result
