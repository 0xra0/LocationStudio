from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


ISSUE_RE = re.compile(r"(?:error|warn(?:ing)?|failed|failure|exception|traceback|fatal|assert)", re.IGNORECASE)


@dataclass(frozen=True)
class LogSpec:
    name: str
    relative_paths: tuple[str, ...]


LOG_SPECS = (
    LogSpec("WorldBuilder", (
        "bin/x64/plugins/cyber_engine_tweaks/mods/entSpawner/entSpawner.log",
    )),
    LogSpec("cp77wb_bridge", (
        "bin/x64/plugins/cyber_engine_tweaks/mods/cp77wb_bridge/cp77wb_bridge.log",
    )),
    LogSpec("CyberEngineTweaks", (
        "bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.log",
        "bin/x64/plugins/cyber_engine_tweaks/cyber_engine_tweaks.log.txt",
    )),
    LogSpec("RED4ext", (
        "red4ext/logs/red4ext.log",
        "red4ext/logs/red4ext.log.txt",
    )),
    LogSpec("redscript", (
        "red4ext/logs/redscript.log",
        "red4ext/logs/redscript_rCURRENT.log",
    )),
    LogSpec("ArchiveXL", (
        "red4ext/plugins/ArchiveXL/ArchiveXL.log",
        "red4ext/logs/ArchiveXL.log",
    )),
    LogSpec("TweakXL", (
        "red4ext/plugins/TweakXL/TweakXL.log",
        "red4ext/logs/TweakXL.log",
    )),
)


def normalize_game_root(path: str | Path) -> Path:
    p = Path(path).expanduser().resolve()
    # Also accept .../CET/mods/entSpawner and walk back to the game root.
    marker = Path("bin/x64/plugins/cyber_engine_tweaks/mods/entSpawner")
    parts = p.parts
    marker_parts = marker.parts
    if len(parts) >= len(marker_parts) and tuple(parts[-len(marker_parts):]) == marker_parts:
        return Path(*parts[:-len(marker_parts)])
    return p


def discover_logs(game_root: str | Path) -> list[tuple[str, Path]]:
    root = normalize_game_root(game_root)
    found: list[tuple[str, Path]] = []
    seen: set[Path] = set()
    for spec in LOG_SPECS:
        for rel in spec.relative_paths:
            path = root / rel
            if path.is_file() and path not in seen:
                found.append((spec.name, path))
                seen.add(path)
                break
    return found


def _tail_text(path: Path, max_lines: int) -> list[str]:
    # Logs are normally modest, but cap bytes so a pathological log cannot make
    # a single Claude/MCP call allocate hundreds of MB.
    max_bytes = 4 * 1024 * 1024
    with path.open("rb") as f:
        try:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - max_bytes))
        except OSError:
            f.seek(0)
        raw = f.read()
    text = raw.decode("utf-8", errors="replace")
    lines = text.splitlines()
    if max_lines > 0:
        lines = lines[-max_lines:]
    return lines


def read_logs(
    game_root: str | Path,
    *,
    tail: int = 200,
    issues_only: bool = False,
) -> dict[str, Any]:
    if tail < 1 or tail > 5000:
        raise ValueError("tail must be between 1 and 5000")
    root = normalize_game_root(game_root)
    logs: list[dict[str, Any]] = []
    for name, path in discover_logs(root):
        lines = _tail_text(path, tail)
        if issues_only:
            lines = [line for line in lines if ISSUE_RE.search(line)]
        stat = path.stat()
        logs.append({
            "name": name,
            "path": str(path),
            "size": stat.st_size,
            "mtime": stat.st_mtime,
            "lines": lines,
        })
    return {
        "gameRoot": str(root),
        "found": len(logs),
        "issuesOnly": bool(issues_only),
        "tail": tail,
        "logs": logs,
    }
