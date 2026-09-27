#!/usr/bin/env python3
"""LocationStudio MCP bridge for Claude Code.

The MCP process communicates with the in-game CET mod through three JSON files
inside LocationStudio/bridge. Only one live command is in flight at a time.
"""
from __future__ import annotations

import json
import math
import os
import shutil
import sys
import threading
import time
import uuid
import zipfile
from pathlib import Path
from typing import Any

from mcp.server import MCPServer

MOD_DIR = Path(os.environ.get("LOCATION_STUDIO_MOD_DIR", Path(__file__).resolve().parents[1])).expanduser().resolve()
BRIDGE_DIR = MOD_DIR / "bridge"
DATA_DIR = MOD_DIR / "data"
COMMAND = BRIDGE_DIR / "command.json"
RESPONSE = BRIDGE_DIR / "response.json"
STATUS = BRIDGE_DIR / "status.json"
PROJECT = DATA_DIR / "project.json"
AUTHORING_PLAN = DATA_DIR / "authoring-plan.json"
DEFAULT_TIMEOUT = float(os.environ.get("LOCATION_STUDIO_TIMEOUT", "8.0"))

mcp = MCPServer("LocationStudio")
_lock = threading.Lock()


def _read_json(path: Path, fallback: Any = None) -> Any:
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return fallback


def _atomic_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def _live_status(max_age: float = 3.0) -> dict[str, Any]:
    data = _read_json(STATUS, {}) or {}
    try:
        age = time.time() - STATUS.stat().st_mtime
    except OSError:
        age = 999999
    data["bridge_file_age_seconds"] = round(age, 3)
    data["live"] = bool(data.get("online")) and age <= max_age
    data["mod_dir"] = str(MOD_DIR)
    return data


def _project() -> dict[str, Any]:
    return _read_json(PROJECT, {}) or {}


def _send(op: str, args: dict[str, Any] | None = None, timeout: float = DEFAULT_TIMEOUT) -> Any:
    """Send one command to CET and wait for its matching response."""
    with _lock:
        status = _live_status()
        if not status.get("live"):
            raise RuntimeError(
                "LocationStudio CET bridge is not live. Start Cyberpunk 2077, load a save, "
                "and ensure the LocationStudio CET mod initialized."
            )
        request_id = uuid.uuid4().hex
        _atomic_json(COMMAND, {
            "id": request_id,
            "op": op,
            "args": args or {},
            "timestamp": time.time(),
        })
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            response = _read_json(RESPONSE, {}) or {}
            if response.get("id") == request_id:
                if not response.get("ok"):
                    raise RuntimeError(str(response.get("error") or f"{op} failed"))
                return response.get("result")
            time.sleep(0.05)
        raise TimeoutError(f"LocationStudio timed out waiting for CET operation {op!r}")


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)


def _find_location(location_id: str) -> dict[str, Any] | None:
    for loc in _project().get("locations", []):
        if loc.get("id") == location_id:
            return loc
    return None


def _find_item(collection: str, item_id: str) -> dict[str, Any] | None:
    for item in _project().get(collection, []):
        if item.get("id") == item_id:
            return item
    return None


@mcp.tool()
def get_status() -> str:
    """Get live CET/player/project/integration status for LocationStudio."""
    return _json(_live_status())


@mcp.tool()
def get_project() -> str:
    """Read the complete saved LocationStudio project, even when the game is offline."""
    return _json(_project())


@mcp.tool()
def get_debug_log(tail_lines: int = 400) -> str:
    """Read the latest LocationStudio runtime log without requiring the game bridge."""
    path = MOD_DIR / "logs" / "locationstudio.log"
    if not path.exists():
        return _json({"path": str(path), "exists": False, "lines": []})
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    count = max(1, min(int(tail_lines), 5000))
    return _json({"path": str(path), "exists": True, "line_count": len(lines), "lines": lines[-count:]})


@mcp.tool()
def get_diagnostics() -> str:
    """Read the last capability and initialization report written by the CET mod."""
    path = MOD_DIR / "logs" / "locationstudio-diagnostics.json"
    return _json(_read_json(path, {"exists": False, "path": str(path)}))


@mcp.tool()
def clear_debug_log() -> str:
    """Clear the live runtime log through CET and start a new logged session segment."""
    return _json(_send("clear_debug_log"))


@mcp.tool()
def run_diagnostics() -> str:
    """Ask the live CET mod to probe capabilities and rewrite the diagnostic report."""
    return _json(_send("run_diagnostics"))


@mcp.tool()
def create_debug_bundle(include_project: bool = False) -> str:
    """Create a ZIP containing logs, bridge status, configuration, and optionally project data."""
    logs = MOD_DIR / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    output = logs / f"LocationStudio-debug-{time.strftime('%Y%m%d-%H%M%S')}.zip"
    candidates = [
        logs / "locationstudio.log", logs / "locationstudio.log.1",
        logs / "locationstudio-diagnostics.json", logs / "LocationStudio-support.txt", BRIDGE_DIR / "status.json",
        BRIDGE_DIR / "response.json", DATA_DIR / "config.json",
    ]
    candidates.extend(sorted(logs.glob("LocationStudio-v*-support.txt")))
    if include_project:
        candidates.append(PROJECT)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in candidates:
            if path.is_file():
                archive.write(path, path.relative_to(MOD_DIR))
    return _json({"created": True, "path": str(output), "include_project": include_project})


@mcp.tool()
def list_assets(query: str = "", category: str = "") -> str:
    """List registered, reusable .ent asset catalog entries from the saved project."""
    q = query.casefold().strip()
    c = category.casefold().strip()
    values = []
    for asset in _project().get("assets", []):
        blob = " ".join([
            str(asset.get("name", "")), str(asset.get("category", "")),
            str(asset.get("kind", "")), " ".join(map(str, asset.get("tags", []))),
        ]).casefold()
        if q and q not in blob:
            continue
        if c and str(asset.get("category", "")).casefold() != c:
            continue
        values.append(asset)
    return _json({"count": len(values), "assets": values})


@mcp.tool()
def register_asset(
    name: str,
    template: str,
    category: str = "Props",
    kind: str = "prop",
    appearance: str = "",
    layer: str = "decoration",
    tags: list[str] | None = None,
) -> str:
    """Register a reusable real .ent template in LocationStudio's asset catalog."""
    return _json(_send("register_asset", {
        "name": name, "template": template, "category": category, "kind": kind,
        "appearance": appearance, "layer": layer, "tags": tags or [],
    }))


@mcp.tool()
def update_asset(asset_id: str, patch: dict[str, Any]) -> str:
    """Update an asset catalog entry without changing already placed objects."""
    return _json(_send("update_asset", {"id": asset_id, "patch": patch}))


@mcp.tool()
def wb_bounds_import(
    manifest_file: str = "",
    manifest: dict[str, Any] | None = None,
    dry_run: bool = True,
) -> str:
    """Import a versioned LocationStudio asset-bounds JSON manifest.

    Entries match a Project Asset by asset_id, exact resource template, or
    unambiguous name. The complete manifest is validated before apply. Pass
    manifest_file as a local JSON path, or supply the decoded manifest object.
    dry_run defaults to true; set false to store all bounds in one undo step.
    """
    payload = manifest
    source = ""
    if manifest_file:
        path = Path(manifest_file).expanduser().resolve()
        if not path.is_file():
            raise FileNotFoundError(f"Bounds manifest not found: {path}")
        if path.stat().st_size > 16 * 1024 * 1024:
            raise ValueError("Bounds manifest exceeds 16 MiB")
        try:
            payload = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ValueError(f"Could not read bounds manifest {path}: {exc}") from exc
        source = str(path)
    if not isinstance(payload, dict):
        raise ValueError("Provide manifest_file or a manifest JSON object")
    return _json(_send("wb_bounds_import", {
        "manifest": payload, "dry_run": bool(dry_run), "source": source or payload.get("source", "MCP manifest")
    }, timeout=30.0))


@mcp.tool()
def wb_bounds_info(asset_id: str) -> str:
    """Live: inspect a Project Asset's stored local bounds, units, source, and fallback size."""
    return _json(_send("wb_bounds_info", {"asset_id": asset_id}))


@mcp.tool()
def wb_bounds_set(
    asset_id: str,
    minimum: dict[str, float],
    maximum: dict[str, float],
    source: str = "manual",
) -> str:
    """Live: set editable resource-local AABB min/max in meters for a Project Asset."""
    return _json(_send("wb_bounds_set", {
        "asset_id": asset_id, "source": source,
        "bounds": {"min": minimum, "max": maximum, "units": "m", "source": source},
    }))


@mcp.tool()
def wb_bounds_world_aabb(object_id: str) -> str:
    """Live: transform an object's stored local bounds by its current rotation, position, and scale."""
    return _json(_send("wb_bounds_world_aabb", {"object_id": object_id}))


@mcp.tool()
def wb_bounds_overlap(object_ids: list[str], margin: float = 0.0) -> str:
    """Live: test pairwise world-space AABB overlap for objects that have stored bounds."""
    return _json(_send("wb_bounds_overlap", {"object_ids": object_ids, "margin": margin}))


@mcp.tool()
def wb_collisions(object_ids: list[str] | None = None, premise_id: str = "", margin: float = 0.0) -> str:
    """Scan a selection, premise, or whole LS project for broadphase overlaps using imported object bounds."""
    return _json(_send("wb_collisions", {"object_ids": object_ids or None, "premise_id": premise_id or None, "margin": margin}, timeout=30.0))


@mcp.tool()
def wb_clipcheck(object_ids: list[str] | None = None, premise_id: str = "", tolerance: float = 0.02) -> str:
    """Check selected/premise props for bounds-based prop-to-prop intersections (no mesh triangles)."""
    return _json(_send("wb_clipcheck", {"object_ids": object_ids or None, "premise_id": premise_id or None, "tolerance": tolerance}, timeout=30.0))


@mcp.tool()
def wb_fixturecheck(object_ids: list[str] | None = None, premise_id: str = "", cell_size: float = 0.25, margin: float = 0.25) -> str:
    """Live Static-collision ray scan around selected prop bounds for fixture intrusions."""
    return _json(_send("wb_fixturecheck", {"object_ids": object_ids or None, "premise_id": premise_id or None, "cell_size": cell_size, "margin": margin}, timeout=120.0))


@mcp.tool()
def wb_fitcheck(object_ids: list[str] | None = None, premise_id: str = "", mode: str = "live", max_distance: float = 4.0) -> str:
    """Live support fit check, or mode='wall' for Static wall clearance at three heights."""
    return _json(_send("wb_fitcheck", {"object_ids": object_ids or None, "premise_id": premise_id or None, "mode": mode, "max_distance": max_distance}, timeout=120.0))


@mcp.tool()
def wb_compat_scan(game_root: str = "") -> str:
    """Read-only compatibility audit of loaded CET integrations, LS project resources, and installed mod inventory."""
    result = _send("wb_compat_scan", timeout=30.0)
    if not isinstance(result, dict):
        result = {"live_scan": result}
    root = _optional_game_root(game_root or None)
    result["installed_mod_inventory"] = _scan_mod_installation(root) if root else {
        "available": False,
        "reason": "Game root could not be inferred; pass game_root to inventory installed mod folders.",
        "verified_compatibility": False,
    }
    result.setdefault("limits", []).append("Installed mod folders and archive filenames are inventory only; opaque archive contents are not analyzed for resource conflicts.")
    return _json(result)


@mcp.tool()
def wb_find(query: str, types: list[str] | None = None, limit: int = 50, offset: int = 0) -> str:
    """Search saved project items by name, ID, tags, notes, template, category, or resource metadata."""
    return _json(_send("wb_find", {"query": query, "types": types or [], "limit": limit, "offset": offset}, timeout=30.0))


@mcp.tool()
def wb_tree(root_id: str = "", max_depth: int = 2, limit: int = 250, root_type: str = "") -> str:
    """Browse the project hierarchy; start at project, a collection:<type>, premise, room, or object group ID."""
    return _json(_send("wb_tree", {"root_id": root_id or None, "root_type": root_type or None,
                           "max_depth": max_depth, "limit": limit}, timeout=30.0))


@mcp.tool()
def wb_get(item_id: str, item_type: str = "") -> str:
    """Fetch one saved project item by ID, optionally disambiguating its type."""
    return _json(_send("wb_get", {"item_id": item_id, "item_type": item_type or None}))


@mcp.tool()
def wb_refs(item_id: str, direction: str = "both", item_type: str = "", limit: int = 200) -> str:
    """List known inbound/outbound project links for an item (scene, room, group, route, camera, and object links)."""
    if direction not in {"both", "inbound", "outbound"}:
        raise ValueError("direction must be both, inbound or outbound")
    return _json(_send("wb_refs", {"item_id": item_id, "item_type": item_type or None,
                           "direction": direction, "limit": limit}, timeout=30.0))


@mcp.tool()
def wb_bounds_fit(asset_id: str, target_size: dict[str, float], mode: str = "stretch") -> str:
    """Live: calculate a suggested asset scale to stretch or uniformly contain it in target dimensions (meters)."""
    return _json(_send("wb_bounds_fit", {"asset_id": asset_id, "target_size": target_size, "mode": mode}))


@mcp.tool()
def wb_generate_cable(premise_id: str, asset_id: str, points: list[dict[str, float]], segment_length: float = 2.0, width: float | None = None, name: str = "Cable", spawn: bool = True) -> str:
    """Generate editable cable mesh segments along a 2–128 point world-space path. Requires an imported World Builder Static Mesh asset."""
    return _json(_send("wb_generate_cable", {"premise_id": premise_id, "asset_id": asset_id, "points": points, "segment_length": segment_length, "width": width, "name": name, "spawn": spawn}, timeout=60.0))


@mcp.tool()
def wb_generate_fence(premise_id: str, asset_id: str, points: list[dict[str, float]], segment_length: float = 2.0, width: float | None = None, height: float | None = None, post_asset_id: str = "", name: str = "Fence", spawn: bool = True) -> str:
    """Generate editable fence mesh segments along a polyline, optionally placing a second imported Static Mesh at every vertex."""
    return _json(_send("wb_generate_fence", {"premise_id": premise_id, "asset_id": asset_id, "points": points, "segment_length": segment_length, "width": width, "height": height, "post_asset_id": post_asset_id or None, "name": name, "spawn": spawn}, timeout=60.0))


@mcp.tool()
def wb_generate_road(premise_id: str, asset_id: str, points: list[dict[str, float]], segment_length: float = 8.0, width: float = 6.0, height: float | None = None, name: str = "Road", spawn: bool = True) -> str:
    """Generate editable, scaled road-mesh segments along a polyline using an imported World Builder Static Mesh."""
    return _json(_send("wb_generate_road", {"premise_id": premise_id, "asset_id": asset_id, "points": points, "segment_length": segment_length, "width": width, "height": height, "name": name, "spawn": spawn}, timeout=60.0))


@mcp.tool()
def wb_generate_market(premise_id: str, asset_ids: list[str], origin: dict[str, float], rows: int = 2, columns: int = 3, spacing_x: float = 2.5, spacing_y: float = 3.0, yaw: float = 0.0, name: str = "Market Stall Grid", spawn: bool = True) -> str:
    """Arrange imported World Builder Static Mesh assets into an editable market grid. The asset list repeats across the grid."""
    return _json(_send("wb_generate_market", {"premise_id": premise_id, "asset_ids": asset_ids, "origin": origin, "rows": rows, "columns": columns, "spacing_x": spacing_x, "spacing_y": spacing_y, "yaw": yaw, "name": name, "spawn": spawn}, timeout=60.0))


@mcp.tool()
def wb_generate_noderef(node_ref: str, position: dict[str, float] | None = None, yaw: float = 0.0, name: str = "NodeRef") -> str:
    """Create a saved semantic NodeRef marker. This is authoring metadata only; it does not create a live REDengine World Builder node."""
    return _json(_send("wb_generate_noderef", {"node_ref": node_ref, "position": position, "yaw": yaw, "name": name}))


@mcp.tool()
def delete_asset(asset_id: str) -> str:
    """Delete an asset catalog entry; existing placed objects remain intact."""
    return _json(_send("delete_asset", {"id": asset_id}))


@mcp.tool()
def mesh_appearance_list(object_id: str = "") -> str:
    """List the real named appearance variants exposed by a spawned World Builder static mesh. The mesh must be selected in LocationStudio or identified by object_id."""
    return _json(_send("mesh_appearance_list", {"object_id": object_id or None}))


@mcp.tool()
def mesh_appearance_preview(appearance: str, object_id: str = "") -> str:
    """Preview one listed appearance on the live mesh component without saving it. Use mesh_appearance_apply to keep it or mesh_appearance_cancel to restore the original."""
    return _json(_send("mesh_appearance_preview", {"appearance": appearance, "object_id": object_id or None}))


@mcp.tool()
def mesh_appearance_apply(appearance: str, object_id: str = "") -> str:
    """Apply and save a variant listed by mesh_appearance_list to the selected spawned World Builder static mesh."""
    return _json(_send("mesh_appearance_apply", {"appearance": appearance, "object_id": object_id or None}))


@mcp.tool()
def mesh_appearance_cancel(object_id: str = "") -> str:
    """Restore the mesh's original appearance after a preview that has not been applied."""
    return _json(_send("mesh_appearance_cancel", {"object_id": object_id or None}))


@mcp.tool()
def create_decal(resource_name: str = "", resource_path: str = "", name: str = "LocationStudio Decal",
                 source: str = "aim", width: float = 1.0, height: float = 1.0, alpha: float = 1.0,
                 horizontal_flip: bool = False, vertical_flip: bool = False, spawn: bool = True,
                 premise_id: str = "", room_id: str = "", x: float | None = None,
                 y: float | None = None, z: float | None = None, yaw: float = 0.0) -> str:
    """Create a real World Builder worldStaticDecalNode using a matching loaded .mi decal material. By default it uses the camera ray hit; alternatively provide x, y, and z together."""
    if source not in {"aim", "player"}:
        raise ValueError("source must be aim or player")
    args: dict[str, Any] = {"resource_name": resource_name, "resource_path": resource_path or None,
        "name": name, "source": source, "width": width, "height": height, "alpha": alpha,
        "horizontal_flip": horizontal_flip, "vertical_flip": vertical_flip, "spawn": spawn,
        "premise_id": premise_id or None, "room_id": room_id or None, "yaw": yaw}
    if any(v is not None for v in (x, y, z)):
        if any(v is None for v in (x, y, z)):
            raise ValueError("x, y, and z must be supplied together")
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1},
            "rotation": {"roll": 0, "pitch": 0, "yaw": yaw}}
    return _json(_send("create_decal", args))


@mcp.tool()
def create_static_light(name: str = "LocationStudio Light", source: str = "aim", premise_id: str = "",
                       room_id: str = "", preset_id: str = "warm", spawn: bool = True,
                       x: float | None = None, y: float | None = None, z: float | None = None, yaw: float = 0.0) -> str:
    """Create a real World Builder worldStaticLightNode with a built-in color/intensity/radius/flicker preset. Requires World Builder 1.0.81 to be loaded and its Static Light catalog ready."""
    if source not in {"aim", "player", "origin"}:
        raise ValueError("source must be aim, player, or origin")
    args: dict[str, Any] = {"name": name, "source": source, "premise_id": premise_id or None,
        "room_id": room_id or None, "preset_id": preset_id, "spawn": spawn, "yaw": yaw}
    if any(v is not None for v in (x, y, z)):
        if any(v is None for v in (x, y, z)):
            raise ValueError("x, y, and z must be supplied together")
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1},
            "rotation": {"roll": 0, "pitch": 0, "yaw": yaw}}
    return _json(_send("create_static_light", args))


@mcp.tool()
def create_audio_emitter(resource_path: str = "", query: str = "amb_", name: str = "Room Tone",
                        source: str = "aim", radius: float = 5.0, emitter_metadata_name: str = "",
                        room_id: str = "", premise_id: str = "", x: float | None = None,
                        y: float | None = None, z: float | None = None, yaw: float = 0.0,
                        spawn: bool = True) -> str:
    """Place a World Builder Static Audio Emitter from its loaded game catalog. Give resource_path to choose an exact sound event; otherwise query selects the first catalog match. Live playback depends on the event and game context."""
    if source not in {"aim", "player", "room"}:
        raise ValueError("source must be aim, player, or room")
    args: dict[str, Any] = {"resource_path": resource_path or None, "query": query, "name": name,
        "source": source, "radius": radius, "emitter_metadata_name": emitter_metadata_name or None,
        "room_id": room_id or None, "premise_id": premise_id or None, "spawn": spawn, "yaw": yaw}
    if any(v is not None for v in (x, y, z)):
        if any(v is None for v in (x, y, z)):
            raise ValueError("x, y, and z must be supplied together")
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1},
            "rotation": {"roll": 0, "pitch": 0, "yaw": yaw}}
    return _json(_send("create_audio_emitter", args))


@mcp.tool()
def create_room_reverb_zone(room_id: str, name: str = "Room Reverb", reverb: str = "revb_interior_room_medium",
                            sound_event: str = "", priority: int = 16, outer_distance: float = 10.0,
                            vertical_outer_distance: float = 1.0, width: float | None = None,
                            depth: float | None = None, height: float | None = None,
                            spawn: bool = True) -> str:
    """Create a World Builder Ambient Area using the room's rotated footprint and four Outline Markers. This is saved authoring data; reverb activates after exporting the complete group as a native world edit."""
    args: dict[str, Any] = {"room_id": room_id, "name": name, "reverb": reverb,
        "sound_event": sound_event or None, "priority": priority, "outer_distance": outer_distance,
        "vertical_outer_distance": vertical_outer_distance, "spawn": spawn}
    for key, value in (("width", width), ("depth", depth), ("height", height)):
        if value is not None:
            args[key] = value
    return _json(_send("create_room_reverb_zone", args))


@mcp.tool()
def update_static_light(object_id: str, color: list[float] | None = None, intensity: float | None = None,
                        radius: float | None = None, flicker_strength: float | None = None,
                        flicker_period: float | None = None, flicker_offset: float | None = None,
                        preset_id: str = "") -> str:
    """Tune a saved static light. Live edits remove and respawn the World Builder node so changes reach the game component."""
    patch: dict[str, Any] = {}
    for key, value in (("color", color), ("intensity", intensity), ("radius", radius),
                       ("flickerStrength", flicker_strength), ("flickerPeriod", flicker_period),
                       ("flickerOffset", flicker_offset)):
        if value is not None:
            patch[key] = value
    if preset_id:
        patch["preset_id"] = preset_id
    return _json(_send("update_static_light", {"object_id": object_id, "patch": patch}))


@mcp.tool()
def preview_time_of_day(hour: int, minute: int = 0) -> str:
    """Temporarily set the game clock to preview lighting; call restore_time_of_day when finished."""
    return _json(_send("preview_time_of_day", {"hour": hour, "minute": minute}))


@mcp.tool()
def restore_time_of_day() -> str:
    """Restore the game clock captured before the most recent time-of-day preview."""
    return _json(_send("restore_time_of_day", {}))


@mcp.tool()
def place_registered_asset(
    asset_id: str,
    premise_id: str,
    room_id: str = "",
    source: str = "aim",
    spawn: bool = True,
    distance: float = 10.0,
    yaw: float = 0.0,
) -> str:
    """Place a catalog asset at the player's aim, player transform, or premise/room origin."""
    if source not in {"aim", "player", "origin"}:
        raise ValueError("source must be aim, player, or origin")
    return _json(_send("place_asset", {
        "id": asset_id, "premise_id": premise_id, "room_id": room_id or None,
        "source": source, "spawn": spawn, "distance": distance, "yaw": yaw,
    }))


@mcp.tool()
def create_interactable(kind: str, asset_id: str, name: str = "", source: str = "aim",
                        premise_id: str = "", room_id: str = "", x: float | None = None,
                        y: float | None = None, z: float | None = None, yaw: float = 0.0,
                        entity_record: str = "", item_record: str = "", loot_table: str = "",
                        lock_state: str = "", fact_name: str = "", fact_value: int = 1,
                        spawn: bool = True, loot_items: list[dict[str, Any]] | None = None) -> str:
    """Place a registered game .ent/Entity Record/Device asset and attach door, loot-container, shard, or item authoring data. Shards/items require an Items.* record; loot containers require a LootTables.* record. Lock/fact values are a native-resource handoff and do not by themselves create runtime interaction behavior."""
    if source not in {"aim", "player", "origin"}:
        raise ValueError("source must be aim, player, or origin")
    args: dict[str, Any] = {"kind": kind, "asset_id": asset_id, "name": name or None,
        "source": source, "premise_id": premise_id or None, "room_id": room_id or None,
        "yaw": yaw, "entity_record": entity_record, "item_record": item_record,
        "loot_table": loot_table, "lock_state": lock_state or None,
        "fact_name": fact_name, "fact_value": fact_value, "spawn": spawn, "loot_items": loot_items or []}
    if any(value is not None for value in (x, y, z)):
        if any(value is None for value in (x, y, z)):
            raise ValueError("provide x, y, and z together for an explicit placement")
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1.0},
            "rotation": {"roll": 0.0, "pitch": 0.0, "yaw": yaw}}
    return _json(_send("create_interactable", args))


@mcp.tool()
def list_interactables() -> str:
    """List saved placed interactables and their record, lock, and fact settings."""
    return _json(_send("list_interactables"))


@mcp.tool()
def update_interactable(object_id: str, kind: str | None = None, entity_record: str | None = None,
                        item_record: str | None = None, loot_table: str | None = None,
                        lock_state: str | None = None, fact_name: str | None = None,
                        fact_value: int | None = None, loot_items: list[dict[str, Any]] | None = None) -> str:
    """Edit saved interactable data. Does not modify a spawned entity's native controller."""
    patch = {key: value for key, value in {"kind": kind, "entity_record": entity_record,
        "item_record": item_record, "loot_table": loot_table, "lock_state": lock_state,
        "fact_name": fact_name, "fact_value": fact_value, "loot_items": loot_items}.items() if value is not None}
    return _json(_send("update_interactable", {"id": object_id, "patch": patch}))


@mcp.tool()
def delete_interactable(object_id: str) -> str:
    """Delete a saved interactable and remove its tracked live instance when possible."""
    return _json(_send("delete_interactable", {"id": object_id}))


@mcp.tool()
def build_interactable_artifacts(export_file: str, output: str) -> str:
    """Generate TweakXL loot tables and audit native World Builder sector/device/PS data.

    loot_items rows use item_record (Items.*), count_min, count_max and drop_chance (0..1).
    Does not fabricate entity components or controller operations; selected game entities must carry required native setup.
    """
    return _json(_lsip.generate(PROJECT, _export_file(export_file), Path(output).expanduser()))


@mcp.tool()
def create_interactable(kind: str, asset_id: str, name: str = "", source: str = "aim",
                        premise_id: str = "", room_id: str = "", x: float | None = None,
                        y: float | None = None, z: float | None = None, yaw: float = 0.0,
                        entity_record: str = "", item_record: str = "", loot_table: str = "",
                        lock_state: str = "", fact_name: str = "", fact_value: int = 1,
                        spawn: bool = True, loot_items: list[dict[str, Any]] | None = None) -> str:
    """Place a registered game .ent/Entity Record/Device asset and attach door, loot-container, shard, or item authoring data. Shards/items require an Items.* record; loot containers require a LootTables.* record. Lock/fact settings are handoff metadata: CET does not rewrite native entity PS/streaming-sector interaction wiring."""
    if source not in {"aim", "player", "origin"}:
        raise ValueError("source must be aim, player, or origin")
    args: dict[str, Any] = {"kind": kind, "asset_id": asset_id, "name": name or None,
        "source": source, "premise_id": premise_id or None, "room_id": room_id or None,
        "yaw": yaw, "entity_record": entity_record, "item_record": item_record,
        "loot_table": loot_table, "lock_state": lock_state or None,
        "fact_name": fact_name, "fact_value": fact_value, "spawn": spawn, "loot_items": loot_items or []}
    coords = (x, y, z)
    if any(v is not None for v in coords):
        if any(v is None for v in coords):
            raise ValueError("provide all of x, y, and z for an explicit position")
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1.0},
            "rotation": {"roll": 0.0, "pitch": 0.0, "yaw": yaw}}
    return _json(_send("create_interactable", args))


@mcp.tool()
def list_interactables() -> str:
    """List placed interactable objects and their item, lock, and quest-fact handoff settings."""
    return _json(_send("list_interactables"))


@mcp.tool()
def update_interactable(object_id: str, kind: str | None = None, entity_record: str | None = None,
                        item_record: str | None = None, loot_table: str | None = None,
                        lock_state: str | None = None, fact_name: str | None = None,
                        fact_value: int | None = None, loot_items: list[dict[str, Any]] | None = None) -> str:
    """Edit saved interactable authoring settings. This does not patch the live entity's native interaction controller."""
    patch = {key: value for key, value in {"kind": kind, "entity_record": entity_record,
        "item_record": item_record, "loot_table": loot_table, "lock_state": lock_state,
        "fact_name": fact_name, "fact_value": fact_value, "loot_items": loot_items}.items() if value is not None}
    return _json(_send("update_interactable", {"id": object_id, "patch": patch}))


@mcp.tool()
def delete_interactable(object_id: str) -> str:
    """Remove a saved interactable object and despawn its tracked live instance when possible."""
    return _json(_send("delete_interactable", {"id": object_id}))


@mcp.tool()
def list_locations(query: str = "", location_type: str = "", category: str = "") -> str:
    """List saved locations, optionally filtering by text, type, or category."""
    q = query.casefold().strip()
    t = location_type.casefold().strip()
    c = category.casefold().strip()
    results: list[dict[str, Any]] = []
    for loc in _project().get("locations", []):
        blob = " ".join([
            str(loc.get("name", "")), str(loc.get("type", "")), str(loc.get("category", "")),
            " ".join(map(str, loc.get("tags", []))), str(loc.get("notes", "")),
        ]).casefold()
        if q and q not in blob:
            continue
        if t and str(loc.get("type", "")).casefold() != t:
            continue
        if c and str(loc.get("category", "")).casefold() != c:
            continue
        results.append(loc)
    return _json({"count": len(results), "locations": results})


@mcp.tool()
def get_location(location_id: str) -> str:
    """Get one saved location by LocationStudio id."""
    loc = _find_location(location_id)
    if loc is None:
        raise ValueError(f"Unknown location id: {location_id}")
    return _json(loc)


@mcp.tool()
def list_premises() -> str:
    """List constructed premises with their room and object counts."""
    project = _project()
    result = []
    for premise in project.get("premises", []):
        item = dict(premise)
        item["room_count"] = sum(r.get("premise_id") == premise.get("id") for r in project.get("rooms", []))
        item["object_count"] = sum(o.get("premise_id") == premise.get("id") for o in project.get("objects", []))
        result.append(item)
    return _json({"count": len(result), "premises": result})


@mcp.tool()
def get_premise(premise_id: str) -> str:
    """Get one premise plus all of its rooms and construction objects."""
    project = _project()
    premise = _find_item("premises", premise_id)
    if premise is None:
        raise ValueError(f"Unknown premise id: {premise_id}")
    return _json({
        "premise": premise,
        "rooms": [r for r in project.get("rooms", []) if r.get("premise_id") == premise_id],
        "objects": [o for o in project.get("objects", []) if o.get("premise_id") == premise_id],
    })


@mcp.tool()
def create_premise(
    name: str,
    kind: str = "interior",
    from_player: bool = True,
    levels: int = 1,
    floor_height: float = 3.0,
    notes: str = "",
) -> str:
    """Create a construction premise, normally anchored at V's current transform."""
    return _json(_send("create_premise", {
        "name": name, "kind": kind, "from_player": from_player,
        "levels": levels, "floor_height": floor_height, "notes": notes,
    }))


@mcp.tool()
def create_room(
    premise_id: str,
    name: str,
    width: float,
    depth: float,
    height: float = 3.0,
    x: float = 0.0,
    y: float = 0.0,
    z: float = 0.0,
    yaw: float = 0.0,
    level: int = 0,
    wall_thickness: float = 0.15,
    generate_shell: bool = True,
) -> str:
    """Build a rectangular room in premise-local space with floor, ceiling, and segmented walls."""
    return _json(_send("create_room", {
        "premise_id": premise_id, "name": name, "width": width, "depth": depth, "height": height,
        "x": x, "y": y, "z": z, "yaw": yaw, "level": level,
        "wall_thickness": wall_thickness, "generate_shell": generate_shell,
    }))


@mcp.tool()
def create_corridor(
    premise_id: str,
    name: str,
    length: float,
    width: float = 2.0,
    height: float = 3.0,
    x: float = 0.0,
    y: float = 0.0,
    z: float = 0.0,
    yaw: float = 0.0,
) -> str:
    """Build a corridor in premise-local space."""
    return _json(_send("create_corridor", {
        "premise_id": premise_id, "name": name, "length": length, "width": width,
        "height": height, "x": x, "y": y, "z": z, "yaw": yaw,
    }))


@mcp.tool()
def add_opening(
    room_id: str,
    wall: str,
    kind: str = "door",
    offset: float = 0.0,
    width: float = 1.2,
    height: float = 2.2,
    sill: float = 0.0,
    template: str = "",
) -> str:
    """Cut a door or window opening into north/south/east/west wall and rebuild its shell segments."""
    return _json(_send("add_opening", {
        "room_id": room_id, "wall": wall, "kind": kind, "offset": offset,
        "width": width, "height": height, "sill": sill, "template": template,
    }))


@mcp.tool()
def rebuild_room_shell(room_id: str) -> str:
    """Regenerate a room's wall/floor/ceiling objects after geometry or opening changes."""
    return _json(_send("rebuild_room_shell", {"id": room_id}))


@mcp.tool()
def detach_room_piece(object_id: str) -> str:
    """Detach one generated room piece so later room rebuilds preserve it as an independent object."""
    return _json(_send("detach_shell_piece", {"id": object_id}))


@mcp.tool()
def replace_room_piece(object_id: str, asset_id: str) -> str:
    """Replace one generated room piece with an imported World Builder Static Mesh asset."""
    return _json(_send("replace_shell_piece", {"id": object_id, "asset_id": asset_id}))


@mcp.tool()
def set_construction_state(
    premise_id: str,
    room_id: str = "",
    role: str = "all",
    enabled: bool | None = None,
    locked: bool | None = None,
    include_collision: bool = False,
) -> str:
    """Show/hide or lock/unlock room-kit pieces by location, room, and surface role."""
    patch: dict[str, Any] = {"include_collision": include_collision}
    if enabled is not None: patch["enabled"] = enabled
    if locked is not None: patch["locked"] = locked
    return _json(_send("set_construction_state", {
        "premise_id": premise_id, "room_id": room_id or None, "role": role, "patch": patch,
    }, timeout=30.0))


@mcp.tool()
def focus_world_builder_object(object_id: str) -> str:
    """Spawn an object if needed and select it in World Builder so its native gizmo becomes active."""
    return _json(_send("focus_world_builder_object", {"id": object_id}))


@mcp.tool()
def get_object_selection() -> str:
    """Return the current LocationStudio/World Builder multi-selection and active object."""
    return _json(_send("get_object_selection"))


@mcp.tool()
def set_object_selection(object_ids: list[str], active_id: str = "", focus_world_builder: bool = True) -> str:
    """Replace the object selection set and optionally select its spawned resources in World Builder."""
    return _json(_send("set_object_selection", {
        "ids": object_ids, "active_id": active_id or None,
        "focus_world_builder": focus_world_builder, "source": "mcp",
    }))


@mcp.tool()
def transform_object_selection(
    object_ids: list[str],
    dx: float = 0.0,
    dy: float = 0.0,
    dz: float = 0.0,
    dyaw: float = 0.0,
    scale_factor: float = 1.0,
    local_space: bool = False,
    active_id: str = "",
) -> str:
    """Move, center-pivot rotate, or uniformly scale an object set and update its live instances."""
    return _json(_send("transform_object_group", {
        "ids": object_ids, "dx": dx, "dy": dy, "dz": dz, "dyaw": dyaw,
        "scale_factor": scale_factor, "local_space": local_space,
        "active_id": active_id or None,
    }))


@mcp.tool()
def set_object_selection_state(
    object_ids: list[str],
    enabled: bool | None = None,
    visible: bool | None = None,
    locked: bool | None = None,
) -> str:
    """Show, hide, enable, disable, lock, or unlock a specific object set."""
    patch: dict[str, Any] = {}
    if enabled is not None: patch["enabled"] = enabled
    if visible is not None: patch["visible"] = visible
    if locked is not None: patch["locked"] = locked
    return _json(_send("set_object_group_state", {"ids": object_ids, "patch": patch}))


@mcp.tool()
def set_object_selection_spawned(object_ids: list[str], spawned: bool = True) -> str:
    """Spawn or despawn every object in a selection set."""
    return _json(_send("spawn_object_group", {"ids": object_ids, "spawn": spawned}, timeout=30.0))


@mcp.tool()
def duplicate_object_selection(object_ids: list[str], dx: float = 0.25, dy: float = 0.0, dz: float = 0.0) -> str:
    """Duplicate an object set once, preserving relative layout and selecting the copies."""
    return _json(_send("duplicate_object_group", {
        "ids": object_ids, "offset": {"x": dx, "y": dy, "z": dz},
    }, timeout=30.0))


@mcp.tool()
def delete_object_selection(object_ids: list[str]) -> str:
    """Delete an unlocked object set after all live instances are removed successfully."""
    return _json(_send("delete_object_group", {"ids": object_ids}, timeout=30.0))


@mcp.tool()
def layout_object_selection(
    object_ids: list[str],
    operation: str,
    axis: str = "",
    mode: str = "center",
    active_id: str = "",
    grid: float = 0.25,
    angle: float = 5.0,
) -> str:
    """Align, evenly distribute, match rotation/scale, or snap an editable object selection."""
    return _json(_send("layout_object_group", {
        "ids": object_ids, "operation": operation, "axis": axis or None,
        "mode": mode, "active_id": active_id or None, "grid": grid, "angle": angle,
    }, timeout=30.0))


@mcp.tool()
def wb_align(object_ids: list[str], axis: str, mode: str = "center", active_id: str = "") -> str:
    """Align placed objects on x, y or z. Reuses LocationStudio's layout_object_selection implementation."""
    if axis not in {"x", "y", "z"}:
        raise ValueError("axis must be x, y or z")
    if mode not in {"center", "active", "min", "max"}:
        raise ValueError("mode must be center, active, min or max")
    return _json(_send("wb_align", {"ids": object_ids, "axis": axis, "mode": mode, "active_id": active_id or None}, timeout=30.0))


@mcp.tool()
def wb_distribute(object_ids: list[str], axis: str) -> str:
    """Evenly distribute at least three placed objects along x, y or z using the existing layout operation."""
    if axis not in {"x", "y", "z"}:
        raise ValueError("axis must be x, y or z")
    return _json(_send("wb_distribute", {"ids": object_ids, "axis": axis}, timeout=30.0))


@mcp.tool()
def wb_path_array(object_ids: list[str], path_points: list[dict[str, float]], count: int = 5,
                  orient_to_path: bool = True, spawn: bool = True) -> str:
    """Create evenly spaced copies of placed objects along a 3D polyline; count is additional copies."""
    return _json(_send("wb_path_array", {"ids": object_ids, "path_points": path_points, "count": count,
                   "orient_to_path": orient_to_path, "spawn": spawn}, timeout=60.0))


@mcp.tool()
def wb_radial_array(object_ids: list[str], center: dict[str, float], radius: float, count: int = 8,
                    start_angle: float = 0.0, sweep_angle: float = 360.0,
                    rotate_objects: bool = True, spawn: bool = True) -> str:
    """Create evenly spaced copies of placed objects around a world-space center; count is additional copies."""
    return _json(_send("wb_radial_array", {"ids": object_ids, "center": center, "radius": radius,
                   "count": count, "start_angle": start_angle, "sweep_angle": sweep_angle,
                   "rotate_objects": rotate_objects, "spawn": spawn}, timeout=60.0))


@mcp.tool()
def wb_grid(object_ids: list[str], origin: dict[str, float], rows: int = 2, columns: int = 2,
            spacing_x: float = 2.0, spacing_y: float = 2.0, spacing_z: float = 0.0,
            yaw: float = 0.0, rotate_objects: bool = False, spawn: bool = True) -> str:
    """Create copies of a placed object selection in a yaw-rotated grid; the original selection stays in place."""
    return _json(_send("wb_grid", {"ids": object_ids, "origin": origin, "rows": rows, "columns": columns,
                   "spacing_x": spacing_x, "spacing_y": spacing_y, "spacing_z": spacing_z,
                   "yaw": yaw, "rotate_objects": rotate_objects, "spawn": spawn}, timeout=60.0))


@mcp.tool()
def replace_object_selection_asset(object_ids: list[str], asset_id: str) -> str:
    """Replace an unlocked object set with one verified project asset and respawn every live member."""
    return _json(_send("replace_object_group_asset", {
        "ids": object_ids, "asset_id": asset_id,
    }, timeout=30.0))


@mcp.tool()
def list_object_groups() -> str:
    """List persistent scene-outliner groups and their direct object membership."""
    return _json(_send("list_object_groups"))


@mcp.tool()
def create_object_group(
    name: str,
    object_ids: list[str],
    active_id: str = "",
    parent_group_id: str = "",
    pivot_mode: str = "center",
) -> str:
    """Create a persistent editable group from placed objects; an object belongs to at most one direct group."""
    return _json(_send("create_object_group", {
        "name": name, "ids": object_ids, "active_id": active_id or None,
        "parent_id": parent_group_id or None, "pivot_mode": pivot_mode,
    }))


@mcp.tool()
def update_object_group(
    group_id: str,
    name: str = "",
    parent_group_id: str = "",
    pivot_mode: str = "",
    recalculate_pivot: bool = False,
) -> str:
    """Rename or reparent an outliner group and optionally recalculate its stored pivot."""
    patch: dict[str, Any] = {"recalculate_pivot": recalculate_pivot}
    if name: patch["name"] = name
    if parent_group_id: patch["parent_id"] = parent_group_id
    if pivot_mode: patch["pivot_mode"] = pivot_mode
    return _json(_send("update_object_group", {"id": group_id, "patch": patch}))


@mcp.tool()
def select_object_group(group_id: str, recursive: bool = True, focus_world_builder: bool = True) -> str:
    """Select a saved group, including nested child groups, and optionally focus its World Builder handles."""
    return _json(_send("select_object_group", {
        "id": group_id, "recursive": recursive, "focus": focus_world_builder,
    }))


@mcp.tool()
def transform_saved_group(
    group_id: str,
    dx: float = 0.0,
    dy: float = 0.0,
    dz: float = 0.0,
    dyaw: float = 0.0,
    scale_factor: float = 1.0,
    local_space: bool = False,
) -> str:
    """Move, rotate, or uniformly scale a saved group around its persistent pivot."""
    return _json(_send("transform_saved_group", {
        "id": group_id, "dx": dx, "dy": dy, "dz": dz, "dyaw": dyaw,
        "scale_factor": scale_factor, "local_space": local_space,
    }, timeout=30.0))


@mcp.tool()
def dissolve_object_group(group_id: str) -> str:
    """Remove an outliner group while preserving every placed object."""
    return _json(_send("dissolve_object_group", {"id": group_id}))


@mcp.tool()
def list_object_prefabs() -> str:
    """List reusable object assemblies saved in the active LocationStudio project."""
    return _json(_send("list_object_prefabs"))


@mcp.tool()
def save_object_prefab(
    name: str,
    object_ids: list[str],
    active_id: str = "",
    pivot_mode: str = "center",
    category: str = "Assemblies",
    notes: str = "",
) -> str:
    """Save real selected game resources and their relative transforms as a reusable editable prefab."""
    return _json(_send("save_object_prefab", {
        "name": name, "ids": object_ids, "active_id": active_id or None,
        "pivot_mode": pivot_mode, "category": category, "notes": notes,
    }))


@mcp.tool()
def instantiate_object_prefab(
    prefab_id: str,
    premise_id: str,
    room_id: str = "",
    source: str = "player",
    yaw: float = 0.0,
    spawn: bool = True,
    group_name: str = "",
) -> str:
    """Instantiate a saved prefab at the player or aimed surface as independently editable live objects."""
    return _json(_send("instantiate_object_prefab", {
        "id": prefab_id, "premise_id": premise_id, "room_id": room_id or None,
        "source": source, "yaw": yaw, "spawn": spawn,
        "group_name": group_name or None,
    }, timeout=30.0))


@mcp.tool()
def delete_object_prefab(prefab_id: str) -> str:
    """Delete a reusable prefab definition without deleting any placed instances."""
    return _json(_send("delete_object_prefab", {"id": prefab_id}))


@mcp.tool()
def wb_prefab_render(prefab_id: str, distance: float = 12.0) -> str:
    """Render a saved prefab from live game assets into a persistent PNG thumbnail.

    The CET mod temporarily spawns visible prefab members at the aimed point,
    captures the actual game frame, then removes the temporary instances. It
    saves no placement objects; removal failures remain visible for cleanup.
    """
    started = _send("wb_prefab_render", {"id": prefab_id, "distance": distance}, timeout=30.0)
    if not started.get("pending"):
        return _json(started)
    deadline = time.monotonic() + 45.0
    while time.monotonic() < deadline:
        status = _send("wb_prefab_render_status", {}, timeout=10.0)
        if status.get("last_error") and not status.get("pending"):
            raise RuntimeError(str(status["last_error"]))
        result = status.get("last_result") or {}
        if result.get("prefab_id") == prefab_id and not status.get("pending"):
            return _json({"rendered": True, **result})
        if not status.get("pending"):
            raise RuntimeError("Prefab render ended without a completed thumbnail; inspect get_debug_log().")
        time.sleep(0.25)
    raise TimeoutError("Prefab thumbnail is still rendering/cleaning up. Check wb_prefab_render_status through CET logs or retry after cleanup finishes.")


@mcp.tool()
def place_object(
    premise_id: str,
    name: str,
    template: str,
    room_id: str = "",
    kind: str = "prop",
    layer: str = "decoration",
    appearance: str = "",
    x: float = 0.0,
    y: float = 0.0,
    z: float = 0.0,
    yaw: float = 0.0,
    spawn: bool = False,
) -> str:
    """Place an editable .ent-backed construction object in premise- or room-local space."""
    return _json(_send("place_object", {
        "premise_id": premise_id, "room_id": room_id or None, "name": name,
        "template": template, "kind": kind, "layer": layer, "appearance": appearance,
        "x": x, "y": y, "z": z, "yaw": yaw, "spawn": spawn,
    }))


@mcp.tool()
def update_object_transform(
    object_id: str,
    x: float,
    y: float,
    z: float,
    yaw: float = 0.0,
    pitch: float = 0.0,
    roll: float = 0.0,
    respawn: bool = True,
) -> str:
    """Set an object's world transform and optionally refresh its live preview entity."""
    return _json(_send("update_object", {
        "id": object_id, "respawn": respawn,
        "patch": {"transform": {
            "position": {"x": x, "y": y, "z": z, "w": 1.0},
            "rotation": {"roll": roll, "pitch": pitch, "yaw": yaw},
        }},
    }))


@mcp.tool()
def create_room_frame(name: str, origin: dict[str, float], yaw: float = 0.0,
                      u_axis: dict[str, float] | None = None, v_axis: dict[str, float] | None = None,
                      notes: str = "") -> str:
    """Create a named local room coordinate frame. yaw rotates local u/v axes counterclockwise in world XY."""
    return _json(_send("wb_frame_create", {"name": name, "origin": origin, "yaw": yaw,
                                            "u_axis": u_axis, "v_axis": v_axis, "notes": notes}))


@mcp.tool()
def list_room_frames() -> str:
    """List saved named coordinate frames and their world origins and axes."""
    return _json(_send("wb_frame_list"))


@mcp.tool()
def update_room_frame(frame_id: str, patch: dict[str, Any]) -> str:
    """Update a room frame for future local-coordinate operations. Existing objects keep their world transforms."""
    return _json(_send("wb_frame_update", {"frame_id": frame_id, "patch": patch}))


@mcp.tool()
def delete_room_frame(frame_id: str) -> str:
    """Delete a saved local frame. This does not move or delete placed objects."""
    return _json(_send("wb_frame_delete", {"frame_id": frame_id}))


@mcp.tool()
def room_frame_to_world(frame_id: str, u: float, v: float, z: float = 0.0, yaw: float = 0.0) -> str:
    """Convert local u/v/z and local yaw to a world transform for a named frame."""
    return _json(_send("wb_frame_to_world", {"frame_id": frame_id, "local_position": {"u": u, "v": v, "z": z, "yaw": yaw}}))


@mcp.tool()
def world_to_room_frame(frame_id: str, x: float, y: float, z: float, yaw: float = 0.0) -> str:
    """Convert a world position/yaw to coordinates in a named local frame."""
    return _json(_send("wb_world_to_frame", {"frame_id": frame_id, "transform": {
        "position": {"x": x, "y": y, "z": z}, "rotation": {"yaw": yaw}}}))


@mcp.tool()
def place_object_in_frame(premise_id: str, frame_id: str, name: str, template: str,
                          u: float, v: float, z: float = 0.0, yaw: float = 0.0,
                          room_id: str = "", kind: str = "prop", layer: str = "decoration",
                          appearance: str = "", spawn: bool = False) -> str:
    """Place an editable object using local u/v/z coordinates from a named room frame."""
    return _json(_send("place_object_in_frame", {"premise_id": premise_id, "frame_id": frame_id,
        "name": name, "template": template, "u": u, "v": v, "z": z, "yaw": yaw,
        "room_id": room_id or None, "kind": kind, "layer": layer, "appearance": appearance, "spawn": spawn}))


@mcp.tool()
def move_object_in_frame(object_id: str, frame_id: str, u: float, v: float, z: float,
                         yaw: float | None = None, respawn: bool = True) -> str:
    """Move an existing object to local u/v/z; preserve its local yaw unless yaw is supplied."""
    return _json(_send("move_object_in_frame", {"object_id": object_id, "frame_id": frame_id,
        "u": u, "v": v, "z": z, "yaw": yaw, "respawn": respawn}))


@mcp.tool()
def reload_runtime() -> str:
    """Reconcile LocationStudio's CET and World Builder ownership after a Lua hot reload without respawning or removing live objects."""
    return _json(_send("reload_runtime", timeout=15.0))


@mcp.tool()
def spawn_object(object_id: str) -> str:
    """Spawn a construction object's .ent template through CET exEntitySpawner."""
    return _json(_send("spawn_object", {"id": object_id}))


@mcp.tool()
def despawn_object(object_id: str) -> str:
    """Remove a construction object's live preview entity."""
    return _json(_send("despawn_object", {"id": object_id}))


@mcp.tool()
def spawn_premise(premise_id: str) -> str:
    """Spawn all enabled template-backed objects in a premise and report per-object failures."""
    return _json(_send("spawn_premise", {"id": premise_id}, timeout=30.0))


@mcp.tool()
def despawn_all_objects() -> str:
    """Remove every LocationStudio live preview entity."""
    return _json(_send("despawn_all", timeout=30.0))


@mcp.tool()
def array_object(
    object_id: str,
    count: int,
    dx: float = 0.0,
    dy: float = 0.0,
    dz: float = 0.0,
    dyaw: float = 0.0,
) -> str:
    """Create up to 100 repeated copies with a cumulative local transform step."""
    return _json(_send("array_object", {
        "id": object_id, "count": count, "dx": dx, "dy": dy, "dz": dz, "dyaw": dyaw,
    }))


@mcp.tool()
def mirror_object(object_id: str, axis: str = "x") -> str:
    """Mirror an object across the premise origin on the x or y world axis."""
    return _json(_send("mirror_object", {"id": object_id, "axis": axis}))


@mcp.tool()
def create_premise_prefab(premise_id: str, kind: str = "clinic") -> str:
    """Generate an editable clinic, apartment, or warehouse room layout."""
    return _json(_send("create_prefab", {"premise_id": premise_id, "kind": kind}, timeout=30.0))


@mcp.tool()
def get_aim_point(distance: float = 10.0) -> str:
    """Get the surface/entity/fallback position along the active game camera ray."""
    return _json(_send("aim_point", {"distance": distance}))


@mcp.tool()
def pick_aimed_project_object(
    max_distance: float = 40.0,
    radius: float = 0.75,
    premise_only: bool = True,
    include_locked: bool = True,
    focus_world_builder: bool = True,
) -> str:
    """Select the saved LocationStudio object nearest the active camera ray."""
    return _json(_send("pick_aimed_object", {
        "max_distance": max_distance, "radius": radius, "premise_only": premise_only,
        "include_locked": include_locked, "focus_world_builder": focus_world_builder,
    }))


@mcp.tool()
def preview_registered_asset(
    asset_id: str,
    distance: float = 10.0,
    align_surface: bool = False,
    stamp_mode: bool = False,
    stamp_spacing: float = 0.5,
    follow: bool = True,
) -> str:
    """Start a live asset preview; optionally align local up to the hit surface or keep a stamp session active."""
    return _json(_send("preview_asset", {
        "id": asset_id, "mode": "aim", "distance": distance, "follow": follow,
        "align_surface": align_surface, "stamp_mode": stamp_mode, "stamp_spacing": stamp_spacing,
    }))


@mcp.tool()
def stamp_asset_preview_once(premise_id: str, room_id: str = "") -> str:
    """Add one live instance to the active transactional stamp stroke."""
    return _json(_send("stamp_preview", {"premise_id": premise_id, "room_id": room_id or None}))


@mcp.tool()
def stop_asset_preview() -> str:
    """Clear a normal preview, or commit the active stamp stroke as one undo step."""
    return _json(_send("clear_asset_preview", {}))


@mcp.tool()
def get_stamp_stroke_status() -> str:
    """Inspect the active transactional stamp stroke, its count, spacing, and owned object IDs."""
    return _json(_send("get_stamp_stroke_status", {}))


@mcp.tool()
def commit_stamp_stroke() -> str:
    """Commit every object in the active stamp stroke as one undoable project edit."""
    return _json(_send("commit_stamp_stroke", {}))


@mcp.tool()
def cancel_stamp_stroke() -> str:
    """Remove every live object created by the active stamp stroke and restore prior project state."""
    return _json(_send("cancel_stamp_stroke", {}))


@mcp.tool()
def place_object_at_aim(
    premise_id: str,
    name: str,
    template: str,
    room_id: str = "",
    kind: str = "prop",
    layer: str = "decoration",
    appearance: str = "",
    distance: float = 10.0,
    yaw: float = 0.0,
    spawn: bool = False,
) -> str:
    """Place an editable object at the current raycast/look/fallback aim point."""
    return _json(_send("place_object_at_aim", {
        "premise_id": premise_id, "room_id": room_id or None, "name": name, "template": template,
        "kind": kind, "layer": layer, "appearance": appearance, "distance": distance,
        "yaw": yaw, "spawn": spawn, "source": "mcp:aim",
    }))


@mcp.tool()
def list_volumes(premise_id: str = "") -> str:
    """List trigger/gameplay volumes, optionally for one premise."""
    values = _project().get("volumes", [])
    if premise_id:
        values = [v for v in values if v.get("premise_id") == premise_id]
    return _json({"count": len(values), "volumes": values})


@mcp.tool()
def create_volume(
    premise_id: str,
    name: str,
    purpose: str = "trigger",
    shape: str = "box",
    room_id: str = "",
    x: float = 0.0,
    y: float = 0.0,
    z: float = 0.0,
    yaw: float = 0.0,
    width: float = 2.0,
    depth: float = 2.0,
    height: float = 2.0,
    radius: float = 1.0,
) -> str:
    """Create a box, sphere, or cylinder volume in premise/room-local space."""
    return _json(_send("create_volume", {
        "premise_id": premise_id, "room_id": room_id or None, "name": name, "purpose": purpose,
        "shape": shape, "x": x, "y": y, "z": z, "yaw": yaw,
        "width": width, "depth": depth, "height": height, "radius": radius, "source": "mcp",
    }))


@mcp.tool()
def update_volume(
    volume_id: str,
    name: str | None = None,
    purpose: str | None = None,
    enabled: bool | None = None,
) -> str:
    """Update descriptive state for an existing volume."""
    patch: dict[str, Any] = {}
    if name is not None: patch["name"] = name
    if purpose is not None: patch["purpose"] = purpose
    if enabled is not None: patch["enabled"] = enabled
    return _json(_send("update_volume", {"id": volume_id, "patch": patch}))


@mcp.tool()
def link_volume_to_quest_fact(volume_id: str, fact_name: str = "", value: int = 1) -> str:
    """Attach or clear Quest Forge fact metadata on a trigger volume for manifest handoff."""
    return _json(_send("link_volume_fact", {"id": volume_id, "fact_name": fact_name, "value": value}))


@mcp.tool()
def delete_volume(volume_id: str) -> str:
    """Delete one trigger/gameplay volume."""
    return _json(_send("delete_volume", {"id": volume_id}))


@mcp.tool()
def list_cameras(premise_id: str = "") -> str:
    """List authored cameras, optionally for one premise."""
    values = _project().get("cameras", [])
    if premise_id:
        values = [v for v in values if v.get("premise_id") == premise_id]
    return _json({"count": len(values), "cameras": values})


@mcp.tool()
def create_camera(
    premise_id: str,
    name: str,
    room_id: str = "",
    x: float = 0.0,
    y: float = 0.0,
    z: float = 1.7,
    look_x: float = 2.0,
    look_y: float = 0.0,
    look_z: float = 1.4,
    fov: float = 50.0,
    duration: float = 3.0,
) -> str:
    """Create a camera and look-at target in premise/room-local coordinates."""
    return _json(_send("create_camera", {
        "premise_id": premise_id, "room_id": room_id or None, "name": name,
        "x": x, "y": y, "z": z, "look_x": look_x, "look_y": look_y, "look_z": look_z,
        "fov": fov, "duration": duration,
    }))


@mcp.tool()
def capture_camera_from_player(
    premise_id: str,
    name: str,
    room_id: str = "",
    aim_distance: float = 10.0,
    fov: float = 0.0,
    duration: float = 3.0,
) -> str:
    """Capture the active game camera (including free-camera views when exposed by CET) and its aim point."""
    camera = _send("capture_camera")
    hit = _send("aim_point", {"distance": aim_distance})
    return _json(_send("create_camera", {
        "premise_id": premise_id, "room_id": room_id or None, "name": name,
        "transform": camera["transform"], "look_at": hit["position"],
        "fov": fov if fov > 0 else (camera.get("fov") or 50.0), "duration": duration,
    }))


@mcp.tool()
def set_camera_look_at(
    camera_id: str,
    x: float | None = None,
    y: float | None = None,
    z: float | None = None,
    location_id: str = "",
) -> str:
    """Point a camera toward explicit coordinates or a saved location ID."""
    if location_id:
        target: dict[str, Any] = {"location_id": location_id}
    elif x is not None and y is not None and z is not None:
        target = {"x": x, "y": y, "z": z}
    else:
        raise ValueError("Provide location_id or x, y, and z")
    return _json(_send("set_camera_look_at", {"id": camera_id, "target": target}))


@mcp.tool()
def preview_camera(camera_id: str) -> str:
    """Teleport V to an authored camera transform for composition testing."""
    return _json(_send("preview_camera", {"id": camera_id}))


@mcp.tool()
def delete_camera(camera_id: str) -> str:
    """Delete one authored camera."""
    return _json(_send("delete_camera", {"id": camera_id}))


@mcp.tool()
def snap_item(
    kind: str,
    item_id: str,
    grid: float = 0.25,
    angle: float = 5.0,
) -> str:
    """Snap a premise, room, object, volume, camera, or location transform."""
    return _json(_send("snap_item", {"kind": kind, "id": item_id, "grid": grid, "angle": angle}))


@mcp.tool()
def batch_transform(
    kind: str,
    item_ids: list[str],
    dx: float = 0.0,
    dy: float = 0.0,
    dz: float = 0.0,
    dyaw: float = 0.0,
    local_space: bool = True,
) -> str:
    """Move/rotate multiple same-kind items with one reversible model operation."""
    return _json(_send("batch_transform", {
        "kind": kind, "ids": item_ids, "dx": dx, "dy": dy, "dz": dz,
        "dyaw": dyaw, "local_space": local_space,
    }))


@mcp.tool()
def capture_active_camera() -> str:
    """Read the active game camera transform/FOV; falls back to V when the camera API is unavailable."""
    return _json(_send("capture_camera"))


@mcp.tool()
def copy_item_transform(kind: str, item_id: str, part: str = "transform") -> str:
    """Copy an item's position, rotation, or full transform into LocationStudio's runtime transform clipboard."""
    if part not in {"position", "rotation", "transform"}:
        raise ValueError("part must be position, rotation, or transform")
    return _json(_send("copy_transform", {"kind": kind, "id": item_id, "part": part}))


@mcp.tool()
def paste_item_transform(kind: str, item_id: str, part: str = "transform") -> str:
    """Paste the runtime transform clipboard onto an item; room/premise transforms move their authored children too."""
    if part not in {"position", "rotation", "transform"}:
        raise ValueError("part must be position, rotation, or transform")
    return _json(_send("paste_transform", {"kind": kind, "id": item_id, "part": part}))


@mcp.tool()
def reset_item_rotation(kind: str, item_id: str) -> str:
    """Reset an authored item's Euler rotation to zero."""
    return _json(_send("reset_rotation", {"kind": kind, "id": item_id}))


@mcp.tool()
def move_item_to_player(kind: str, item_id: str, copy_rotation: bool = False) -> str:
    """Move an item to V; optionally copy V's rotation. Premises/rooms carry their children."""
    return _json(_send("move_item_to_player", {"kind": kind, "id": item_id, "copy_rotation": copy_rotation}))


@mcp.tool()
def move_item_to_aim(kind: str, item_id: str, distance: float = 12.0) -> str:
    """Move an item to the active-camera crosshair/raycast point."""
    return _json(_send("move_item_to_aim", {"kind": kind, "id": item_id, "distance": distance}))


@mcp.tool()
def start_crosshair_grab(
    object_ids: list[str] | None = None,
    active_id: str = "",
    distance: float = 12.0,
    align_surface: bool = False,
    snap_position: bool = False,
    pivot_mode: str = "center",
) -> str:
    """Start a reversible Grab Move session for explicit IDs or the current object selection."""
    if pivot_mode not in {"center", "active"}:
        raise ValueError("pivot_mode must be center or active")
    return _json(_send("start_transform_grab", {
        "ids": object_ids or [], "active_id": active_id or None, "distance": distance,
        "align_surface": align_surface, "snap_position": snap_position, "pivot_mode": pivot_mode,
    }))


@mcp.tool()
def update_crosshair_grab(
    distance: float | None = None,
    surface_offset: float | None = None,
    align_surface: bool | None = None,
    snap_position: bool | None = None,
    yaw_delta: float | None = None,
) -> str:
    """Change active Grab Move options; yaw_delta is relative to the session's original transforms."""
    payload: dict[str, Any] = {}
    if distance is not None: payload["distance"] = distance
    if surface_offset is not None: payload["surface_offset"] = surface_offset
    if align_surface is not None: payload["align_surface"] = align_surface
    if snap_position is not None: payload["snap_position"] = snap_position
    if yaw_delta is not None: payload["yaw_delta"] = yaw_delta
    return _json(_send("configure_transform_grab", payload))


@mcp.tool()
def get_crosshair_grab_status() -> str:
    """Inspect the active reversible Grab Move session and its live/deferred backend counts."""
    return _json(_send("get_transform_grab_status", {}))


@mcp.tool()
def commit_crosshair_grab() -> str:
    """Commit the active Grab Move as one undoable transform operation."""
    return _json(_send("commit_transform_grab", {}))


@mcp.tool()
def cancel_crosshair_grab() -> str:
    """Restore every grabbed object to its exact pre-session transform."""
    return _json(_send("cancel_transform_grab", {}))


@mcp.tool()
def start_reversible_transform_edit(
    object_ids: list[str] | None = None,
    active_id: str = "",
    local_space: bool = False,
    pivot_mode: str = "center",
    pivot_x: float = 0.0,
    pivot_y: float = 0.0,
    pivot_z: float = 0.0,
) -> str:
    """Begin one reversible move/rotate/scale transaction for explicit IDs or the current selection."""
    if pivot_mode not in {"center", "active", "custom"}:
        raise ValueError("pivot_mode must be center, active, or custom")
    payload: dict[str, Any] = {
        "ids": object_ids or [], "active_id": active_id or None,
        "local_space": local_space, "pivot_mode": pivot_mode,
    }
    if pivot_mode == "custom":
        payload["pivot"] = {"position": {"x": pivot_x, "y": pivot_y, "z": pivot_z, "w": 1.0}}
    return _json(_send("start_transform_edit", payload))


@mcp.tool()
def duplicate_selection_and_edit(
    object_ids: list[str] | None = None,
    active_id: str = "",
    offset_x: float = 0.25,
    offset_y: float = 0.0,
    offset_z: float = 0.0,
    local_space: bool = False,
    pivot_mode: str = "center",
) -> str:
    """Duplicate selected game assets and begin one reversible transform transaction on the live copies."""
    if pivot_mode not in {"center", "active"}:
        raise ValueError("pivot_mode must be center or active")
    return _json(_send("start_duplicate_transform_edit", {
        "ids": object_ids or [], "active_id": active_id or None,
        "offset": {"x": offset_x, "y": offset_y, "z": offset_z},
        "local_space": local_space, "pivot_mode": pivot_mode,
    }))


@mcp.tool()
def start_placement_edit(
    kind: str = "object",
    item_id: str = "",
    object_ids: list[str] | None = None,
    active_id: str = "",
    mode: str = "aim",
    distance: float = 12.0,
    premise_id: str = "",
    room_id: str = "",
    yaw: float = 0.0,
    yaw_delta: float = 0.0,
    surface_offset: float = 0.02,
    align_surface: bool = False,
) -> str:
    """Place a Project Asset or copy a placed object selection at aim/player/preview, then edit and commit or cancel the live result."""
    if kind not in {"object", "asset"}:
        raise ValueError("kind must be object or asset")
    if mode not in {"aim", "player", "preview"}:
        raise ValueError("mode must be aim, player, or preview")
    if kind == "asset" and not item_id:
        raise ValueError("item_id is required when kind is asset")
    payload: dict[str, Any] = {
        "kind": kind, "mode": mode, "distance": distance,
        "premise_id": premise_id or None, "room_id": room_id or None,
        "yaw": yaw, "yaw_delta": yaw_delta, "surface_offset": surface_offset,
        "align_surface": align_surface,
    }
    if kind == "asset":
        payload["id"] = item_id
    else:
        payload["ids"] = object_ids or ([item_id] if item_id else [])
        payload["active_id"] = active_id or item_id or None
    return _json(_send("start_placement_transform_edit", payload, timeout=30.0))


@mcp.tool()
def start_linear_pattern_edit(
    object_ids: list[str] | None = None,
    active_id: str = "",
    repetitions: int = 2,
    step_x: float = 1.0,
    step_y: float = 0.0,
    step_z: float = 0.0,
    yaw_step: float = 0.0,
    local_axes: bool = True,
    pivot_mode: str = "center",
) -> str:
    """Preview a live linear/rotating array, then finish it with the normal Transform Edit commit or cancel tool."""
    if pivot_mode not in {"center", "active"}:
        raise ValueError("pivot_mode must be center or active")
    return _json(_send("start_pattern_transform_edit", {
        "ids": object_ids or [], "active_id": active_id or None,
        "count": repetitions, "step": {"x": step_x, "y": step_y, "z": step_z},
        "yaw_step": yaw_step, "pattern_local_space": local_axes,
        "pattern_pivot_mode": pivot_mode,
    }))


@mcp.tool()
def start_mirror_copy_edit(
    axis: str = "x",
    object_ids: list[str] | None = None,
    active_id: str = "",
) -> str:
    """Mirror live copies of a selection across its location origin, then commit or cancel the transaction."""
    if axis not in {"x", "y"}:
        raise ValueError("axis must be x or y")
    return _json(_send("start_mirror_transform_edit", {
        "ids": object_ids or [], "active_id": active_id or None, "axis": axis,
    }))


@mcp.tool()
def start_scatter_copy_edit(
    kind: str = "object",
    item_id: str = "",
    object_ids: list[str] | None = None,
    active_id: str = "",
    count: int = 6,
    radius: float = 2.0,
    distance: float = 12.0,
    seed: int = 2077,
    random_yaw: bool = True,
    drop_to_ground: bool = True,
    premise_id: str = "",
    room_id: str = "",
) -> str:
    """Create a deterministic live scatter from a placed selection or Project Asset, then commit or cancel it as one transaction."""
    if kind not in {"object", "asset"}:
        raise ValueError("kind must be object or asset")
    if kind == "asset" and not item_id:
        raise ValueError("item_id is required when kind is asset")
    payload: dict[str, Any] = {
        "kind": kind, "count": count, "radius": radius, "distance": distance, "seed": seed,
        "random_yaw": random_yaw, "drop_to_ground": drop_to_ground,
        "premise_id": premise_id or None, "room_id": room_id or None,
    }
    if kind == "asset":
        payload["id"] = item_id
    else:
        payload["ids"] = object_ids or ([item_id] if item_id else [])
        payload["active_id"] = active_id or item_id or None
    return _json(_send("start_scatter_transform_edit", payload, timeout=30.0))


@mcp.tool()
def adjust_reversible_transform_edit(
    dx: float = 0.0,
    dy: float = 0.0,
    dz: float = 0.0,
    droll: float = 0.0,
    dpitch: float = 0.0,
    dyaw: float = 0.0,
    scale_factor: float = 1.0,
    local_space: bool | None = None,
) -> str:
    """Apply an incremental transform to the active transaction and update supported live backends."""
    payload: dict[str, Any] = {
        "dx": dx, "dy": dy, "dz": dz, "droll": droll,
        "dpitch": dpitch, "dyaw": dyaw, "scale_factor": scale_factor,
    }
    if local_space is not None:
        payload["local_space"] = local_space
    return _json(_send("adjust_transform_edit", payload))


@mcp.tool()
def reset_reversible_transform_edit() -> str:
    """Reset the active transaction preview to its exact starting transforms without closing it."""
    return _json(_send("reset_transform_edit", {}))


@mcp.tool()
def get_transform_session_status() -> str:
    """Inspect the active Grab Move or Transform Edit transaction and backend refresh state."""
    return _json(_send("get_transform_session_status", {}))


@mcp.tool()
def commit_reversible_transform_edit() -> str:
    """Commit the active Transform Edit transaction as exactly one undo operation."""
    return _json(_send("commit_transform_edit", {}))


@mcp.tool()
def cancel_reversible_transform_edit() -> str:
    """Cancel the active Transform Edit and restore project and live runtime transforms."""
    return _json(_send("cancel_transform_edit", {}))


@mcp.tool()
def drop_item_to_ground(
    kind: str,
    item_id: str,
    max_distance: float = 50.0,
    offset: float = 0.02,
) -> str:
    """Raycast downward and place an authored item on the nearest static/terrain surface."""
    return _json(_send("drop_item_to_ground", {
        "kind": kind, "id": item_id, "max_distance": max_distance, "offset": offset,
    }))


@mcp.tool()
def teleport_player_to_item(kind: str, item_id: str) -> str:
    """Teleport V to any transformable authored item."""
    return _json(_send("teleport_player_to_item", {"kind": kind, "id": item_id}))


@mcp.tool()
def set_transform_target(kind: str, item_id: str) -> str:
    """Store an authored item as the look-at target for later aim operations."""
    return _json(_send("set_transform_target", {"kind": kind, "id": item_id}))


@mcp.tool()
def clear_transform_target() -> str:
    """Clear LocationStudio's stored look-at target."""
    return _json(_send("clear_transform_target"))


@mcp.tool()
def aim_item_at_target(
    kind: str,
    item_id: str,
    target_kind: str = "",
    target_id: str = "",
) -> str:
    """Rotate an item to look at an explicit target or the stored transform target."""
    payload: dict[str, Any] = {"kind": kind, "id": item_id}
    if target_kind: payload["target_kind"] = target_kind
    if target_id: payload["target_id"] = target_id
    return _json(_send("aim_item_at_target", payload))


@mcp.tool()
def aim_item_at_player(kind: str, item_id: str) -> str:
    """Rotate an item to look at V's current position."""
    return _json(_send("aim_item_at_player", {"kind": kind, "id": item_id}))


@mcp.tool()
def aim_item_at_crosshair(kind: str, item_id: str, distance: float = 20.0) -> str:
    """Rotate an item toward the active-camera crosshair/raycast point."""
    return _json(_send("aim_item_at_crosshair", {"kind": kind, "id": item_id, "distance": distance}))


@mcp.tool()
def duplicate_item_at_aim(
    kind: str,
    item_id: str,
    distance: float = 12.0,
    spawn: bool = True,
) -> str:
    """Duplicate an object/location/volume/camera directly at the active-camera aim point."""
    return _json(_send("duplicate_at_aim", {
        "kind": kind, "id": item_id, "distance": distance, "spawn": spawn,
    }))


@mcp.tool()
def scatter_at_aim(
    kind: str,
    item_id: str,
    count: int = 6,
    radius: float = 2.0,
    distance: float = 12.0,
    seed: int = 2077,
    random_yaw: bool = True,
    drop_to_ground: bool = True,
    spawn: bool = True,
    premise_id: str = "",
    room_id: str = "",
) -> str:
    """Compatibility command: deterministically scatter and immediately commit the copies as one undo step."""
    payload = {
        "kind": kind, "id": item_id, "count": count, "radius": radius, "distance": distance,
        "seed": seed, "random_yaw": random_yaw, "drop_to_ground": drop_to_ground, "spawn": spawn,
        "premise_id": premise_id or None, "room_id": room_id or None,
    }
    if kind == "object": payload.update({"ids": [item_id], "active_id": item_id})
    return _json(_send("scatter_at_aim", payload, timeout=30.0))


def _wb_scatter_args(kind: str, item_id: str, count: int, seed: int, random_yaw: bool,
                     premise_id: str, room_id: str, spawn: bool) -> dict[str, Any]:
    if kind not in {"asset", "object"}:
        raise ValueError("kind must be asset or object")
    if not item_id:
        raise ValueError("item_id is required")
    if count < 1 or count > 100:
        raise ValueError("count must be between 1 and 100")
    payload = {"kind": kind, "id": item_id, "count": count, "seed": seed,
            "random_yaw": random_yaw, "premise_id": premise_id or None,
            "room_id": room_id or None, "spawn": spawn}
    if kind == "object": payload.update({"ids": [item_id], "active_id": item_id})
    return payload


@mcp.tool()
def wb_polygon_scatter(
    kind: str,
    item_id: str,
    polygon: list[dict[str, float]],
    count: int = 10,
    seed: int = 2077,
    z: float | None = None,
    random_yaw: bool = True,
    drop_to_ground: bool = True,
    premise_id: str = "",
    room_id: str = "",
    spawn: bool = True,
) -> str:
    """Scatter a saved asset/object uniformly inside a simple world-XY polygon."""
    payload = _wb_scatter_args(kind, item_id, count, seed, random_yaw, premise_id, room_id, spawn)
    payload.update({"scatter_area": "polygon", "polygon": polygon, "z": z,
                    "drop_to_ground": drop_to_ground})
    return _json(_send("scatter_at_aim", payload, timeout=60.0))


@mcp.tool()
def wb_volume_scatter(
    kind: str,
    item_id: str,
    volume_id: str,
    count: int = 10,
    seed: int = 2077,
    random_yaw: bool = True,
    premise_id: str = "",
    room_id: str = "",
    spawn: bool = True,
) -> str:
    """Scatter copies within a saved box, sphere, or cylinder authoring volume."""
    if not volume_id:
        raise ValueError("volume_id is required")
    payload = _wb_scatter_args(kind, item_id, count, seed, random_yaw, premise_id, room_id, spawn)
    payload.update({"scatter_area": "volume", "volume_id": volume_id, "drop_to_ground": False})
    return _json(_send("scatter_at_aim", payload, timeout=60.0))


@mcp.tool()
def wb_live_surface_scatter(
    kind: str,
    item_id: str,
    count: int = 10,
    radius: float = 3.0,
    distance: float = 20.0,
    seed: int = 2077,
    random_yaw: bool = True,
    surface_offset: float = 0.02,
    premise_id: str = "",
    room_id: str = "",
    spawn: bool = True,
) -> str:
    """Scatter onto a live, raycastable surface under the crosshair; requires a real hit normal."""
    if count > 32:
        raise ValueError("live-surface scatter is capped at 32 copies per call to bound synchronous game raycasts")
    if not math.isfinite(radius) or radius <= 0 or radius > 25:
        raise ValueError("radius must be finite, greater than 0, and at most 25 meters")
    if not math.isfinite(distance) or distance <= 0 or distance > 100:
        raise ValueError("distance must be finite and between 0 and 100 meters")
    if not math.isfinite(surface_offset):
        raise ValueError("surface_offset must be finite")
    payload = _wb_scatter_args(kind, item_id, count, seed, random_yaw, premise_id, room_id, spawn)
    payload.update({"scatter_area": "live_surface", "radius": radius, "distance": distance,
                    "surface_offset": surface_offset, "drop_to_ground": False, "align_surface": True})
    return _json(_send("scatter_at_aim", payload, timeout=120.0))


@mcp.tool()
def wb_rng_create(seed: int | None = None, sample_count: int = 8) -> str:
    """Create a reproducible Park-Miller seed and optional preview samples for scatter calls."""
    return _json(_lsrng.create(seed, sample_count))


@mcp.tool()
def refresh_in_world_markers(premise_id: str = "") -> str:
    """Refresh transient marker entities using the configured marker .ent template."""
    return _json(_send("refresh_markers", {"premise_id": premise_id or None}, timeout=30.0))


@mcp.tool()
def clear_in_world_markers() -> str:
    """Remove all transient LocationStudio marker entities."""
    return _json(_send("clear_markers", timeout=30.0))


@mcp.tool()
def capture_player_transform() -> str:
    """Read V's current world position and Euler rotation from the running game."""
    return _json(_send("capture_player"))


@mcp.tool()
def create_location_from_player(
    name: str,
    location_type: str = "point",
    category: str = "General",
    tags: list[str] | None = None,
    notes: str = "",
    radius: float = 0.5,
) -> str:
    """Capture V's current transform and save it as a named location."""
    return _json(_send("create_from_player", {
        "name": name, "type": location_type, "category": category,
        "tags": tags or [], "notes": notes, "radius": radius,
    }))


@mcp.tool()
def create_location_at(
    name: str,
    x: float,
    y: float,
    z: float,
    yaw: float = 0.0,
    pitch: float = 0.0,
    roll: float = 0.0,
    location_type: str = "point",
    category: str = "General",
    tags: list[str] | None = None,
    notes: str = "",
    radius: float = 0.5,
) -> str:
    """Create a location at explicit world coordinates without moving the player."""
    return _json(_send("create_location", {
        "name": name, "x": x, "y": y, "z": z, "yaw": yaw, "pitch": pitch, "roll": roll,
        "type": location_type, "category": category, "tags": tags or [], "notes": notes, "radius": radius,
    }))


@mcp.tool()
def update_location(
    location_id: str,
    name: str | None = None,
    location_type: str | None = None,
    category: str | None = None,
    tags: list[str] | None = None,
    notes: str | None = None,
    radius: float | None = None,
) -> str:
    """Update descriptive fields on an existing location."""
    patch: dict[str, Any] = {}
    if name is not None: patch["name"] = name
    if location_type is not None: patch["type"] = location_type
    if category is not None: patch["category"] = category
    if tags is not None: patch["tags"] = tags
    if notes is not None: patch["notes"] = notes
    if radius is not None: patch["radius"] = radius
    return _json(_send("update_location", {"id": location_id, "patch": patch}))


@mcp.tool()
def set_location_transform(
    location_id: str,
    x: float,
    y: float,
    z: float,
    yaw: float = 0.0,
    pitch: float = 0.0,
    roll: float = 0.0,
) -> str:
    """Replace a location's world transform with explicit coordinates."""
    patch = {"transform": {
        "position": {"x": x, "y": y, "z": z, "w": 1.0},
        "rotation": {"roll": roll, "pitch": pitch, "yaw": yaw},
    }}
    return _json(_send("update_location", {"id": location_id, "patch": patch}))


@mcp.tool()
def set_location_from_player(location_id: str) -> str:
    """Replace a location transform with V's current transform."""
    return _json(_send("set_from_player", {"id": location_id}))


@mcp.tool()
def teleport_to_location(location_id: str) -> str:
    """Teleport V to a saved location for immediate in-game testing."""
    return _json(_send("teleport", {"id": location_id}))


@mcp.tool()
def duplicate_location(location_id: str, new_name: str = "") -> str:
    """Duplicate a saved point, nudged +0.5m on X for convenient editing."""
    args: dict[str, Any] = {"id": location_id}
    if new_name:
        args["name"] = new_name
    return _json(_send("duplicate_location", args))


@mcp.tool()
def create_relative_location(
    base_location_id: str,
    name: str,
    dx: float = 0.0,
    dy: float = 0.0,
    dz: float = 0.0,
    dyaw: float = 0.0,
    dpitch: float = 0.0,
    droll: float = 0.0,
    location_type: str = "",
    category: str = "",
    notes: str = "",
) -> str:
    """Create a point by applying local authoring offsets to a saved base point."""
    args: dict[str, Any] = {
        "base_id": base_location_id, "name": name,
        "dx": dx, "dy": dy, "dz": dz, "dyaw": dyaw, "dpitch": dpitch, "droll": droll,
        "notes": notes,
    }
    if location_type: args["type"] = location_type
    if category: args["category"] = category
    return _json(_send("create_relative", args))


@mcp.tool()
def delete_location(location_id: str) -> str:
    """Delete a location and automatically remove it from all routes."""
    return _json(_send("delete_location", {"id": location_id}))


@mcp.tool()
def create_route(
    name: str,
    location_ids: list[str],
    kind: str = "patrol",
    loop: bool = False,
    notes: str = "",
) -> str:
    """Create an ordered route from existing LocationStudio point ids."""
    return _json(_send("add_route", {
        "name": name, "kind": kind, "location_ids": location_ids, "loop": loop, "notes": notes,
    }))


@mcp.tool()
def update_route_points(route_id: str, location_ids: list[str], loop: bool | None = None) -> str:
    """Replace the ordered point list of a route and optionally its loop setting."""
    patch: dict[str, Any] = {"location_ids": location_ids}
    if loop is not None: patch["loop"] = loop
    return _json(_send("update_route", {"id": route_id, "patch": patch}))


@mcp.tool()
def validate_project() -> str:
    """Check the project for duplicate names, very close points, invalid radius, and suspicious coordinates."""
    return _json(_send("validate"))


@mcp.tool()
def save_project() -> str:
    """Force-save the live project to data/project.json."""
    return _json(_send("save"))


@mcp.tool()
def export_project(format: str = "json") -> str:
    """Export as json, csv, lua, worldbuilder, or questforge. Quest Forge export includes world-sector coordinates, manifest NodeRefs and trigger-to-fact links."""
    return _json(_send("export", {"format": format}))


@mcp.tool()
def questforge_sync_preview(file_path: str) -> str:
    """Preview importing an edited LocationStudio Quest Forge handoff. Matches stable LocationStudio IDs and reports facts, unmatched nodes, and transform conflicts without changing the project."""
    path = Path(file_path).expanduser().resolve()
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return _json({"error": f"Cannot read Quest Forge JSON: {exc}"})
    if not isinstance(document, dict):
        return _json({"error": "Quest Forge document root must be a JSON object"})
    return _json(_send("questforge_sync_preview", {"document": document}))


@mcp.tool()
def questforge_sync_apply(file_path: str, apply_positions: bool = False) -> str:
    """Import/update Quest Forge links and facts by exact LocationStudio IDs. Preserves local names, notes, tags and transforms by default; set apply_positions only to deliberately replace conflicting local coordinates."""
    path = Path(file_path).expanduser().resolve()
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return _json({"error": f"Cannot read Quest Forge JSON: {exc}"})
    if not isinstance(document, dict):
        return _json({"error": "Quest Forge document root must be a JSON object"})
    return _json(_send("questforge_sync_apply", {"document": document, "apply_positions": apply_positions}))


@mcp.tool()
def questforge_links(kind: str, item_id: str) -> str:
    """Get Quest Forge nodeRef, manifest name, linked facts, and position-conflict status for a LocationStudio location, volume, camera, or object."""
    return _json(_send("questforge_links", {"kind": kind, "id": item_id}))


@mcp.tool()
def quest_simulation_state(fact_name: str = "") -> str:
    """Read current live quest facts and show linked LocationStudio writers, consumers, and references. This is read-only; it does not change the save."""
    return _json(_send("quest_simulation_state", {"fact_name": fact_name}))


@mcp.tool()
def quest_simulation_prepare_fact_write(fact_name: str, value: int, source: str = "MCP test") -> str:
    """Stage a quest fact change without applying it. Returns the current value and a persistent-save warning. You must separately call quest_simulation_confirm_fact_write with the returned one-time token."""
    return _json(_send("quest_simulation_prepare_write", {"fact_name": fact_name, "value": value, "source": source}))


@mcp.tool()
def quest_simulation_prepare_trigger(volume_id: str) -> str:
    """Stage the linked fact write for a trigger-volume test. This does not dispatch a native volume event; it stages SetFactStr for the configured fact and requires a separate explicit confirmation."""
    return _json(_send("quest_simulation_prepare_trigger", {"volume_id": volume_id}))


@mcp.tool()
def quest_simulation_confirm_fact_write(token: str) -> str:
    """Apply a previously staged fact write. This changes active game quest state and may affect the save or advance quest scripts; use only after reviewing the warning from the prepare tool."""
    return _json(_send("quest_simulation_confirm_write", {"token": token}))


@mcp.tool()
def quest_simulation_cancel_fact_write(token: str = "") -> str:
    """Cancel a staged fact write without changing quest state."""
    return _json(_send("quest_simulation_cancel_write", {"token": token}))


@mcp.tool()
def world_state_variant_list() -> str:
    """List authored fact-driven world-state variants and runtime switching status."""
    return _json(_send("world_state_list", {}))


@mcp.tool()
def world_state_variant_create(name: str, fact_name: str, value: int, operator: str = "==",
                               priority: int = 0, premise_id: str = "") -> str:
    """Create a location variant activated by one live quest fact condition, such as before_quest/during_quest/destroyed/cleaned."""
    return _json(_send("world_state_create", {"name": name, "fact_name": fact_name, "value": value,
                                                "operator": operator, "priority": priority,
                                                "premise_id": premise_id or None}))


@mcp.tool()
def world_state_variant_update(variant_id: str, conditions: list[dict[str, Any]] | None = None,
                               priority: int | None = None, enabled: bool | None = None) -> str:
    """Edit variant fact conditions (all must match), priority, or enabled state. Equal-priority contradictory rules block scene apply."""
    patch = {k: v for k, v in {"conditions": conditions, "priority": priority, "enabled": enabled}.items() if v is not None}
    return _json(_send("world_state_update", {"id": variant_id, "patch": patch}))


@mcp.tool()
def world_state_variant_delete(variant_id: str) -> str:
    """Delete a world-state variant rule group."""
    return _json(_send("world_state_delete", {"id": variant_id}))


@mcp.tool()
def world_state_variant_add_object(variant_id: str, object_id: str, visible: bool = True) -> str:
    """Add a placed game object to a variant, showing it or hiding it when that variant's conditions match."""
    return _json(_send("world_state_add_object", {"variant_id": variant_id, "object_id": object_id, "visible": visible}))


@mcp.tool()
def world_state_variant_remove_object(variant_id: str, object_id: str) -> str:
    """Remove an object's visibility rule from a variant."""
    return _json(_send("world_state_remove_object", {"variant_id": variant_id, "object_id": object_id}))


@mcp.tool()
def world_state_preview() -> str:
    """Evaluate live fact conditions and show active variants/object visibility winners without spawning or despawning anything."""
    return _json(_send("world_state_preview", {}))


@mcp.tool()
def world_state_apply() -> str:
    """Apply visibility rules for the current live quest facts by spawning/despawning tracked CET/World Builder game objects. Does not change quest facts."""
    return _json(_send("world_state_apply", {}))


@mcp.tool()
def world_state_auto_switch(enabled: bool) -> str:
    """Enable or pause automatic live object switching when linked quest facts change. Enabling applies the current matching state immediately; it does not write facts."""
    return _json(_send("world_state_auto", {"enabled": enabled}))


@mcp.tool()
def get_integration_status() -> str:
    """Check whether World Builder, AMM, and RedHotTools were discovered by CET."""
    return _json(_send("integration_status"))


# Game root is six levels above the mod dir: game/bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio.
GAME_DIR = MOD_DIR.parents[5]


def _rht_log() -> Path | None:
    logs = sorted((GAME_DIR / "red4ext" / "plugins" / "RedHotTools").glob("RedHotTools-*.log"),
                  key=lambda p: p.stat().st_mtime)
    return logs[-1] if logs else None


@mcp.tool()
def hot_reload_archives(paths: list[str], restream: bool = True, rise_m: float = 1500.0,
                        wait_s: float = 6.0, timeout_s: float = 60.0,
                        loose: dict[str, str] | None = None) -> str:
    """Hot-load built .archive / .xl files into the running game through RedHotTools - no restart.

    Each file is backed up in archive/pc/mod (<name>.bak-<date>-hot-<time>), then dropped into
    archive/pc/hot, where RedHotTools unloads the old archive, loads the new one, invalidates changed
    resources and calls ArchiveXL.Reload. Sectors already streamed in keep their old state, so with
    restream=True V is lifted rise_m straight up for wait_s seconds and put back, which unloads and
    reloads the nearby streaming sectors with the new node/collision deletions applied.

    loose maps a destination relative to the game dir to a source file, for redscript and
    TweakXL files (e.g. {"r6/scripts/AshCache/AshCacheGlue.reds": "/mnt/.../AshCacheGlue.reds"}).
    Each is backed up and copied, then RedHotTools is told to recompile scripts (.hot-scripts)
    and/or reload tweaks (.hot-tweaks). paths may be empty when only loose files changed."""
    import shutil
    hot = GAME_DIR / "archive" / "pc" / "hot"
    mod = GAME_DIR / "archive" / "pc" / "mod"
    if not hot.is_dir():
        raise RuntimeError(f"{hot} does not exist - is RedHotTools installed?")
    stamp = time.strftime("%Y-%m-%d") + "-hot-" + time.strftime("%H%M%S")
    srcs = [Path(p).expanduser().resolve() for p in paths]
    for src in srcs:
        if not src.is_file() or src.suffix not in (".archive", ".xl"):
            raise ValueError(f"not an .archive or .xl file: {src}")
    log = _rht_log()
    log_pos = log.stat().st_size if log else 0
    report: dict[str, Any] = {"files": []}
    rht_dir = GAME_DIR / "red4ext" / "plugins" / "RedHotTools"
    kinds = set()
    for dest_rel, src_s in (loose or {}).items():
        src, dest = Path(src_s).expanduser().resolve(), (GAME_DIR / dest_rel).resolve()
        if GAME_DIR.resolve() not in dest.parents or not src.is_file():
            raise ValueError(f"bad loose entry {dest_rel!r} <- {src_s!r}")
        backup = None
        if dest.exists():
            if dest.read_bytes() == src.read_bytes():
                report["files"].append({"file": dest_rel, "unchanged": True})
                continue
            backup = dest.with_name(f"{dest.name}.bak-{stamp}")
            shutil.copy2(dest, backup)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)
        kinds.add("scripts" if dest.suffix == ".reds" else "tweaks" if dest.suffix in (".yaml", ".yml", ".tweak") else "other")
        report["files"].append({"file": dest_rel, "backup": str(backup) if backup else None})
    # RedHotTools polls for these two files and acts when one appears.
    if "scripts" in kinds:
        (rht_dir / ".hot-scripts").touch()
    if "tweaks" in kinds:
        (rht_dir / ".hot-tweaks").touch()
    # .xl last: RedHotTools reloads ArchiveXL once the archive swap is done.
    for src in sorted(srcs, key=lambda p: p.suffix == ".xl"):
        target = mod / src.name
        backup = None
        if target.exists():
            backup = target.with_name(f"{src.name}.bak-{stamp}")
            shutil.copy2(target, backup)
        # Written under a name the watcher ignores, then renamed, so RHT never sees half a file.
        part = hot / (src.name + ".part")
        shutil.copyfile(src, part)
        os.replace(part, hot / src.name)
        report["files"].append({"file": src.name, "backup": str(backup) if backup else None})
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline and any((hot / s.name).exists() for s in srcs):
        time.sleep(0.25)
    pending = [s.name for s in srcs if (hot / s.name).exists()]
    for entry, src in zip(report["files"], sorted(srcs, key=lambda p: p.suffix == ".xl")):
        target = mod / src.name
        entry["loaded"] = target.exists() and target.read_bytes() == src.read_bytes()
    report["pending_in_hot"] = pending
    if log and log.exists():
        with open(log, "rb") as f:
            f.seek(log_pos)
            lines = f.read().decode("utf-8", "replace").splitlines()
        report["rht_log"] = [l for l in lines if any(k in l for k in ("ArchiveLoader", "ArchiveXL", "Script", "Tweak"))
                             or "error" in l.lower()][-25:]
    if pending:
        report["error"] = "RedHotTools did not pick the files up - is the game running with RHT loaded?"
        return _json(report)
    if restream:
        here = _send("capture_player")
        pos, rot = here["position"], here["rotation"]
        up = dict(pos, z=pos["z"] + rise_m)
        _send("teleport_raw", {"position": up, "rotation": rot})
        time.sleep(wait_s)
        _send("teleport_raw", {"position": pos, "rotation": rot})
        report["restreamed"] = {"from": pos, "rise_m": rise_m, "wait_s": wait_s}
    return _json(report)


def _deploy_redscripts_wait(sources: dict[str, str], timeout_s: float) -> dict[str, Any]:
    """Copy only explicit .reds inputs, then wait until RedHotTools confirms compilation."""
    if not isinstance(sources, dict) or not sources:
        return {"changed": [], "unchanged": [], "reloaded": False}
    if not 1 <= timeout_s <= 300:
        raise ValueError("script_timeout_s must be between 1 and 300 seconds")
    rht_dir = GAME_DIR / "red4ext" / "plugins" / "RedHotTools"
    if not rht_dir.is_dir():
        raise RuntimeError(f"{rht_dir} does not exist - RedHotTools is required for script reload")
    log = _rht_log()
    if not log:
        raise RuntimeError("No RedHotTools log found; cannot confirm script recompilation")
    start = log.stat().st_size
    stamp = time.strftime("%Y-%m-%d") + "-hot-" + time.strftime("%H%M%S")
    changed: list[dict[str, Any]] = []
    unchanged: list[str] = []
    planned: list[tuple[Path, Path, str]] = []
    for relative, source_s in sources.items():
        rel = Path(relative)
        if rel.is_absolute() or ".." in rel.parts or rel.suffix.lower() != ".reds" or not rel.parts or rel.parts[0] != "r6":
            raise ValueError(f"script destination must be a relative r6/*.reds path: {relative!r}")
        source = Path(source_s).expanduser().resolve()
        dest = (GAME_DIR / rel).resolve()
        if GAME_DIR.resolve() not in dest.parents or not source.is_file():
            raise ValueError(f"script source missing or destination escapes game root: {relative!r} <- {source}")
        if dest.is_file() and dest.read_bytes() == source.read_bytes():
            unchanged.append(rel.as_posix())
            continue
        planned.append((rel, source, source_s))
    for rel, source, source_s in planned:
        dest = (GAME_DIR / rel).resolve()
        dest.parent.mkdir(parents=True, exist_ok=True)
        backup = None
        if dest.exists():
            backup = dest.with_name(f"{dest.name}.bak-{stamp}")
            shutil.copy2(dest, backup)
        temp = dest.with_name(dest.name + ".locationstudio-tmp")
        shutil.copyfile(source, temp)
        os.replace(temp, dest)
        changed.append({"file": rel.as_posix(), "backup": str(backup) if backup else None})
    # Even byte-identical sources must be recompiled: the installed file may
    # have been copied during an earlier cycle without RedHotTools loading it.
    # This is the stale-pose gotcha that can otherwise survive into SyncProps.
    (rht_dir / ".hot-scripts").touch()
    deadline = time.monotonic() + timeout_s
    tail = ""
    while time.monotonic() < deadline:
        try:
            with log.open("rb") as stream:
                stream.seek(start)
                tail = stream.read().decode("utf-8", "replace")
        except OSError as exc:
            raise RuntimeError(f"Could not read RedHotTools reload log: {exc}") from exc
        if "Scripts reload completed" in tail:
            return {"changed": changed, "unchanged": unchanged, "reloaded": True,
                    "forced_recompile": not bool(changed), "log_tail": tail[-4000:]}
        if "ScriptLoader" in tail and "rror" in tail:
            raise RuntimeError("RedHotTools script reload reported an error:\n" + tail[-4000:])
        time.sleep(1)
    raise TimeoutError(f"RedHotTools did not confirm 'Scripts reload completed' within {timeout_s:g}s. Log tail:\n{tail[-2000:]}")


@mcp.tool()
def hotcycle_rebuild(archives: list[str] | None = None, script_files: dict[str, str] | None = None,
                     respawn_tags: list[str] | None = None, system: str = "", method: str = "SyncProps",
                     restream: bool = False, script_timeout_s: float = 120.0,
                     allow_current_script: bool = False, capture_visuals: bool = False,
                     visual_camera_ids: list[str] | None = None, visual_settle_s: float = 6.0,
                     visual_pixel_threshold: int = 24, visual_change_limit: float = 0.01) -> str:
    """Deploy changed .reds files and/or rebuilt archives, then optionally respawn tagged entities.

    A pose change stored in redscript exists only in the deployed .reds. If respawn_tags are requested,
    script_files must include the changed .reds unless allow_current_script=true explicitly accepts the
    currently installed script and its possibly old pose. RedHotTools reload completion is awaited before
    the archive hot-load and respawn. Each script destination is relative to the game root, e.g.
    r6/scripts/AshCache/AshCacheGlue.reds.
    When capture_visuals is true, capture all enabled saved cameras (or visual_camera_ids) after
    reload and respawn, then compare against the last explicitly accepted baseline.
    """
    scripts = script_files or {}
    tags = [str(tag).strip() for tag in (respawn_tags or []) if str(tag).strip()]
    if tags and (not system or not method):
        raise ValueError("system and method are required when respawn_tags are supplied")
    if tags and not scripts and not allow_current_script:
        raise ValueError("Pose changes live in the .reds file. Pass the rebuilt script_files before respawn, or set allow_current_script=true to knowingly use the currently installed pose.")
    if archives:
        hot_dir = GAME_DIR / "archive" / "pc" / "hot"
        if not hot_dir.is_dir():
            raise RuntimeError(f"{hot_dir} does not exist - is RedHotTools installed?")
        for archive in archives:
            path = Path(archive).expanduser()
            if not path.is_file() or path.suffix not in (".archive", ".xl"):
                raise ValueError(f"not an existing .archive or .xl file: {path}")
    script_result = _deploy_redscripts_wait(scripts, float(script_timeout_s))
    archive_result: dict[str, Any] | None = None
    if archives:
        reload_fn = getattr(hot_reload_archives, "fn", hot_reload_archives)
        archive_result = json.loads(reload_fn(paths=archives, restream=restream))
        if archive_result.get("error") or archive_result.get("pending_in_hot"):
            raise RuntimeError("Archive hot-load did not complete; tagged entities were not respawned: " + json.dumps(archive_result))
    respawn_result = None
    if tags:
        respawn_result = _send("respawn_tagged", {"tags": tags, "system": system, "method": method}, timeout=30.0)
    visual_result = None
    if capture_visuals:
        try:
            tool = getattr(visual_regression_capture, "fn", visual_regression_capture)
            visual_result = json.loads(tool(camera_ids=visual_camera_ids, settle_s=visual_settle_s,
                                            pixel_threshold=visual_pixel_threshold,
                                            change_limit=visual_change_limit))
        except Exception as exc:
            visual_result = {"error": str(exc), "rebuild_completed": True}
    return _json({"script": script_result, "archives": archive_result, "respawn": respawn_result,
                  "visual_regression": visual_result,
                  "used_current_script_without_deploy": bool(tags and not scripts and allow_current_script),
                  "warning": "Respawning without script_files uses the deployed redscript pose, which may be stale." if tags and not scripts else None})


SHOT_DIR = Path(os.environ.get("LOCATION_STUDIO_SHOT_DIR", "/mnt/sata/Cyberpunk2077/shots/ls"))


def _hypr(*args: str) -> str:
    import subprocess
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=10).stdout


def _hypr_do(lua: str, legacy: str) -> None:
    """Hyprland >= 0.56 with a Lua config takes Lua dispatch expressions; older ones the legacy words."""
    if "error" in _hypr("dispatch", lua):
        _hypr("dispatch", *legacy.split(" ", 1))


def _focus(address: str) -> None:
    _hypr_do(f'hl.dsp.focus({{ window = "address:{address}" }})', f"focuswindow address:{address}")


def _toggle_fullscreen() -> None:
    _hypr_do('hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })', "fullscreen 0")


@mcp.tool()
def screenshot(fullscreen: bool = True, settle_s: float = 1.5, name: str = "") -> str:
    """Screenshot the running game window (Hyprland + grim) so the result can be checked visually.

    The game usually sits in a small tile, so by default it is made fullscreen for the capture
    and put back afterwards, with focus returned to the window that had it. Returns the PNG path;
    open it with the Read tool to look at it."""
    import subprocess
    clients = json.loads(_hypr("clients", "-j") or "[]")
    game = next((c for c in clients if c.get("class") == "steam_proton" and "Cyberpunk" in c.get("title", "")), None)
    if not game:
        raise RuntimeError("Cyberpunk 2077 window not found in hyprctl clients")
    active = json.loads(_hypr("activewindow", "-j") or "{}").get("address")
    was_full = bool(game.get("fullscreen"))
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    out = SHOT_DIR / f"{time.strftime('%Y%m%d-%H%M%S')}{'-' + name if name else ''}.png"
    toggled = False
    try:
        if fullscreen and not was_full:
            _focus(game["address"])
            _toggle_fullscreen()
            toggled = True
            time.sleep(settle_s)
            mon = json.loads(_hypr("monitors", "-j"))
            name_ = next((m["name"] for m in mon if m["id"] == game["monitor"]), mon[0]["name"])
            cmd = ["grim", "-o", name_, str(out)]
        else:
            (x, y), (w, h) = game["at"], game["size"]
            cmd = ["grim", "-g", f"{x},{y} {w}x{h}", str(out)]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        if r.returncode != 0:
            raise RuntimeError(f"grim failed: {r.stderr.strip()}")
    finally:
        if toggled:
            _toggle_fullscreen()
            if active:
                _focus(active)
    return _json({"path": str(out), "fullscreen": fullscreen, "bytes": out.stat().st_size})


REGRESSION_DIR = Path(os.environ.get("LOCATION_STUDIO_REGRESSION_DIR", SHOT_DIR / "locationstudio-regression")).expanduser()


def _visual_camera_key(camera_id: str) -> str:
    import hashlib
    return hashlib.sha256(camera_id.encode("utf-8")).hexdigest()[:16]


def _visual_regression_capture(camera_ids: list[str] | None, settle_s: float,
                               pixel_threshold: int, change_limit: float,
                               fullscreen: bool = True) -> dict[str, Any]:
    import shutil
    from visual_regression import compare_pngs

    if not 0 <= settle_s <= 60:
        raise ValueError("settle_s must be between 0 and 60 seconds")
    if not 0 <= pixel_threshold <= 255:
        raise ValueError("pixel_threshold must be between 0 and 255")
    if not 0 <= change_limit <= 1:
        raise ValueError("change_limit must be between 0 and 1")
    project_cameras = [c for c in _project().get("cameras", []) if c.get("enabled", True)]
    if camera_ids:
        wanted = set(camera_ids)
        missing = sorted(wanted - {str(c.get("id")) for c in project_cameras})
        if missing:
            raise ValueError("unknown or disabled saved camera ID(s): " + ", ".join(missing))
        cameras = [c for c in project_cameras if c.get("id") in wanted]
    else:
        cameras = project_cameras
    if not cameras:
        raise RuntimeError("No enabled saved cameras to capture. Create cameras in Spatial → Cameras first.")

    stamp = time.strftime("%Y%m%d-%H%M%S")
    run_id = f"{stamp}-{uuid.uuid4().hex[:8]}"
    run_dir = REGRESSION_DIR / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=False)
    accepted = _read_json(REGRESSION_DIR / "accepted.json", {}) or {}
    accepted_id = str(accepted.get("run_id", ""))
    if accepted and not __import__("re").fullmatch(r"\d{8}-\d{6}-[0-9a-f]{8}", accepted_id):
        raise RuntimeError("accepted visual baseline pointer is malformed")
    baseline_dir = REGRESSION_DIR / "runs" / accepted_id if accepted else None
    try:
        player_transform = _send("capture_player")
    except Exception as exc:
        raise RuntimeError(f"Could not capture the player's starting transform: {exc}") from exc

    from visual_regression import read_png
    records: list[dict[str, Any]] = []
    restore_error = None
    try:
        for camera in cameras:
            camera_id = str(camera["id"])
            key = _visual_camera_key(camera_id)
            image_name = f"camera_{key}.png"
            image_path = run_dir / image_name
            record: dict[str, Any] = {"camera_id": camera_id, "name": camera.get("name", camera_id),
                                      "fov_setting": camera.get("fov"), "image": image_name}
            try:
                _send("preview_camera", {"id": camera_id}, timeout=20.0)
                if settle_s:
                    time.sleep(settle_s)
                shot_fn = getattr(screenshot, "fn", screenshot)
                shot = json.loads(shot_fn(fullscreen=fullscreen, settle_s=1.0,
                                          name=f"lsvr_{key}"))
                source = Path(shot["path"])
                if not source.is_file() or source.stat().st_size <= 64:
                    raise RuntimeError("screenshot helper returned no usable PNG file")
                read_png(source)  # Fail here with an actionable error if the PNG is malformed/unsupported.
                shutil.copy2(source, image_path)
                record["image"] = image_name
                record["captured"] = True
                baseline_image = baseline_dir / image_name if baseline_dir else None
                if baseline_image and baseline_image.is_file():
                    metrics = compare_pngs(baseline_image, image_path, run_dir / f"diff_{key}.png", pixel_threshold)
                    record["comparison"] = metrics
                    record["regression"] = (not metrics["compatible"] or metrics["changed_fraction"] > change_limit)
                elif accepted:
                    record["comparison"] = {"available": False, "reason": "camera is absent from the accepted baseline"}
                    record["regression"] = None
                else:
                    record["comparison"] = {"available": False, "reason": "no accepted baseline"}
                    record["regression"] = None
            except Exception as exc:
                record["captured"] = False
                record["error"] = str(exc)
            records.append(record)
    finally:
        try:
            _send("teleport_raw", {"position": player_transform["position"],
                                    "rotation": player_transform["rotation"]}, timeout=20.0)
        except Exception as exc:
            restore_error = str(exc)

    completed = all(record.get("captured") for record in records) and restore_error is None
    has_baseline = bool(accepted)
    compared = [r for r in records if r.get("comparison", {}).get("compatible") is True]
    regressions = [r for r in records if r.get("regression") is True]
    status = ("incomplete" if not completed else "captured") if not has_baseline else \
             "regression" if regressions else "passed" if completed and len(compared) == len(records) else "incomplete"
    manifest = {"run_id": run_id, "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "complete": completed, "status": status, "accepted_baseline_run_id": accepted.get("run_id"),
                "pixel_threshold": pixel_threshold, "change_limit": change_limit,
                "settle_s": settle_s, "cameras": records, "player_restore_error": restore_error}
    _atomic_json(run_dir / "manifest.json", manifest)
    return {**manifest, "run_dir": str(run_dir),
            "accept_tool": "visual_regression_accept(run_id='" + run_id + "')" if completed else None}


@mcp.tool()
def visual_regression_capture(camera_ids: list[str] | None = None, settle_s: float = 6.0,
                              pixel_threshold: int = 24, change_limit: float = 0.01,
                              fullscreen: bool = True) -> str:
    """Capture every enabled saved camera (or the selected camera IDs) and compare against the last explicitly accepted set. Saves screenshots, per-camera diff PNGs, and a JSON manifest under LOCATION_STUDIO_REGRESSION_DIR or the configured screenshot directory. An empty baseline is never accepted automatically."""
    return _json(_visual_regression_capture(camera_ids, settle_s, pixel_threshold, change_limit, fullscreen))


@mcp.tool()
def visual_regression_accept(run_id: str) -> str:
    """Explicitly make one complete visual-regression run the accepted baseline used by future comparisons. Review its screenshots and diffs before accepting."""
    import re
    if not re.fullmatch(r"\d{8}-\d{6}-[0-9a-f]{8}", run_id):
        raise ValueError("invalid visual regression run_id")
    run_dir = REGRESSION_DIR / "runs" / run_id
    manifest = _read_json(run_dir / "manifest.json", {}) or {}
    if manifest.get("run_id") != run_id or not manifest.get("complete"):
        raise ValueError("run does not exist or is incomplete; only a complete capture can become the baseline")
    for camera in manifest.get("cameras", []):
        image_name = camera.get("image", "")
        if Path(image_name).name != image_name or not (run_dir / image_name).is_file():
            raise ValueError("run is missing a screenshot required for its baseline")
    payload = {"run_id": run_id, "accepted_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
               "camera_count": len(manifest.get("cameras", []))}
    _atomic_json(REGRESSION_DIR / "accepted.json", payload)
    return _json({"accepted": True, **payload, "baseline_dir": str(run_dir)})


@mcp.tool()
def run_lua(code: str, timeout_s: float = 15.0) -> str:
    """Run a Lua chunk inside CET in the running game and return its result (a table comes back
    as JSON, anything else as a string). The chunk receives LocationStudio's app object as '...'.
    Example: "local des = GameInstance.GetDynamicEntitySystem(); des:DeleteTagged('mytag'); return 'ok'"."""
    return _json(_send("run_lua", {"code": code}, timeout=timeout_s))


AMM_DB = MOD_DIR.parent / "AppearanceMenuMod" / "db.sqlite3"


def _amm_rows(where: str, params: tuple, limit: int) -> list[dict[str, Any]]:
    import sqlite3
    if not AMM_DB.is_file():
        raise RuntimeError(f"AMM database not found at {AMM_DB}; is Appearance Menu Mod installed?")
    con = sqlite3.connect(f"file:{AMM_DB}?mode=ro", uri=True)
    try:
        rows = con.execute(f"SELECT anim_name, anim_rig, anim_comp, anim_ent, anim_cat FROM workspots WHERE {where} "
                           f"ORDER BY anim_name LIMIT ?", params + (limit,)).fetchall()
    finally:
        con.close()
    return [{"name": n, "rig": r, "comp": c, "ent": e, "category": cat} for n, r, c, e, cat in rows]


@mcp.tool()
def npc_animations_search(text: str, rig: str = "Woman Average", limit: int = 50) -> str:
    """Search AMM's workspot animation catalog (read-only). Every space-separated word of text must
    occur in the animation name, e.g. "stand tablet" or "arms_crossed look". Rigs include
    "Woman Average", "Man Average", "Big", "Fat", "Child", "Player Woman" and their "... Scenes" sets."""
    words = [w for w in text.split() if w]
    where = " AND ".join(["anim_rig = ?"] + ["anim_name LIKE ?"] * len(words))
    return _json(_amm_rows(where, (rig, *[f"%{w}%" for w in words]), limit))


def _npc_target(target: str, key: str, x: float | None, y: float | None, z: float | None, radius: float) -> dict[str, Any]:
    args: dict[str, Any] = {"target": target, "key": key or None, "radius": radius}
    if x is not None and y is not None:
        args["position"] = {"x": x, "y": y, "z": z if z is not None else 0.0}
    return args


@mcp.tool()
def npc_list_nearby(x: float | None = None, y: float | None = None, z: float | None = None, search: float = 30.0) -> str:
    """List NPCs near a point (default: V) with their key, record, position, yaw and any animation
    LocationStudio is playing on them."""
    args: dict[str, Any] = {"search": search}
    if x is not None and y is not None:
        args["position"] = {"x": x, "y": y, "z": z if z is not None else 0.0}
    return _json(_send("npc_list", args))


@mcp.tool()
def npc_play_animation(anim_name: str, rig: str = "Woman Average", target: str = "crosshair", key: str = "",
                       x: float | None = None, y: float | None = None, z: float | None = None,
                       radius: float = 3.0, instant: bool = True) -> str:
    """Play an AMM workspot animation on an NPC in the running game, exactly as AMM's Poses tab does.
    target="crosshair" uses the NPC V looks at; target="nearest" uses the NPC closest to x/y/z (or V)
    within radius; key re-targets an NPC from an earlier result. Waits until the animation is playing.
    Find names with npc_animations_search. Needs AMM's archive installed."""
    rows = _amm_rows("anim_name = ? AND anim_rig = ?", (anim_name, rig), 1)
    if not rows:
        raise RuntimeError(f"no AMM animation {anim_name!r} for rig {rig!r}")
    args = _npc_target(target, key, x, y, z, radius)
    args.update({"anim": rows[0], "instant": instant})
    started = _send("npc_play_anim", args)
    for _ in range(40):
        time.sleep(0.25)
        for item in _send("npc_anim_status").get("animations", []):
            if item.get("key") == started.get("key") and item.get("state") != "pending":
                started.update(state=item.get("state"), error=item.get("error"))
                return _json(started)
    started["state"] = "pending (timed out waiting)"
    return _json(started)


@mcp.tool()
def npc_stop_animation(key: str = "", target: str = "crosshair", x: float | None = None, y: float | None = None,
                       z: float | None = None, radius: float = 3.0, stop_all: bool = False) -> str:
    """Stop an animation started by npc_play_animation (by key, crosshair or nearest), or all=True for every one."""
    if stop_all:
        return _json(_send("npc_stop_all_anims"))
    return _json(_send("npc_stop_anim", _npc_target(target, key, x, y, z, radius)))


@mcp.tool()
def npc_animation_status() -> str:
    """List NPC animations LocationStudio is currently playing: key, animation, state, error."""
    return _json(_send("npc_anim_status"))


@mcp.tool()
def npc_spawn_record(record: str, x: float | None = None, y: float | None = None, z: float | None = None,
                     yaw: float = 0.0, appearance: str = "", tag: str = "ls_npc") -> str:
    """Spawn a character TweakDB record (e.g. "Character.ashcache_mara") as a temporary Codeware dynamic
    entity at x/y/z facing yaw (default: at V), with an optional appearance name. Not saved. Use it as a
    stand-in for animation auditions; remove it with npc_despawn_tag(tag)."""
    args: dict[str, Any] = {"record": record, "yaw": yaw, "appearance": appearance, "tag": tag}
    if x is not None and y is not None and z is not None:
        args["position"] = {"x": x, "y": y, "z": z}
    return _json(_send("npc_spawn_record", args))


@mcp.tool()
def npc_population_create(asset_id: str, name: str, appearance: str = "", attitude: str = "", faction: str = "",
                          level: int = 0, archetype: str = "", idle_behavior: str = "", despawn_distance: float = 0,
                          conditions: list[dict[str, Any]] | None = None, spawn_on_start: bool = True,
                          always_spawned: bool = False, primary_range: float = 100, secondary_range: float = 120,
                          x: float | None = None, y: float | None = None, z: float | None = None, yaw: float = 0,
                          source: str = "player", preview: bool = True) -> str:
    """Author a persistent WB Character.* population point as worldPopulationSpawnerNode. asset_id must be an imported WB Entity Record. Record/appearance/spawn/ranges are native; other profile fields and conditions are explicit handoff data."""
    if source not in {"player", "origin", "aim"}:
        raise ValueError("source must be player, origin, or aim")
    coords = (x, y, z)
    if any(v is not None for v in coords) and any(v is None for v in coords):
        raise ValueError("provide x, y, and z together")
    args: dict[str, Any] = {"asset_id": asset_id, "name": name, "appearance": appearance, "attitude": attitude,
        "faction": faction, "level": level, "archetype": archetype, "idle_behavior": idle_behavior,
        "despawn_distance": despawn_distance, "conditions": conditions or [], "spawn_on_start": spawn_on_start,
        "always_spawned": always_spawned, "primary_range": primary_range, "secondary_range": secondary_range,
        "yaw": yaw, "source": source, "preview": preview}
    if x is not None:
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": yaw}}
    return _json(_send("create_npc_population", args))


@mcp.tool()
def npc_population_list() -> str:
    """List saved persistent NPC population points and their native/handoff profile fields."""
    return _json(_send("list_npc_population"))


@mcp.tool()
def npc_population_update(object_id: str, appearance: str | None = None, attitude: str | None = None,
                          faction: str | None = None, level: int | None = None, archetype: str | None = None,
                          idle_behavior: str | None = None, despawn_distance: float | None = None,
                          conditions: list[dict[str, Any]] | None = None, spawn_on_start: bool | None = None,
                          always_spawned: bool | None = None, primary_range: float | None = None,
                          secondary_range: float | None = None) -> str:
    """Edit a saved population point's native spawn settings and profile handoff fields."""
    patch = {k: v for k, v in locals().items() if k not in {"object_id"} and v is not None}
    return _json(_send("update_npc_population", {"id": object_id, "patch": patch}))


@mcp.tool()
def npc_population_export_audit(export_file: str) -> str:
    """Compare saved NPC population points with exported World Builder worldPopulationSpawnerNode records."""
    return _json(_lsp.audit(PROJECT, _export_file(export_file)))


@mcp.tool()
def npc_route_create(npc_id: str, name: str = "NPC Patrol", loop: bool = True, notes: str = "") -> str:
    """Create an editable patrol plan linked directly to a saved NPC population object ID."""
    return _json(_send("npc_route_create", {"npc_id": npc_id, "name": name, "loop": loop, "notes": notes}))


@mcp.tool()
def npc_route_list(npc_id: str | None = None) -> str:
    """List saved patrol/alert/combat route plans, optionally filtered to one persistent NPC population ID."""
    return _json(_send("npc_route_list", {"npc_id": npc_id} if npc_id else {}))


@mcp.tool()
def npc_route_add_waypoint(route_id: str, variant: str = "patrol", name: str = "Waypoint",
                           wait_seconds: float = 0, facing_yaw: float = 0, speed: float = 1,
                           transition: str = "walk", workspot_location_id: str = "",
                           branch_fact: str = "", branch_value: int = 1, branch_target_id: str = "",
                           x: float | None = None, y: float | None = None, z: float | None = None,
                           yaw: float = 0, source: str = "player") -> str:
    """Append a waypoint to patrol, alert, or combat sequence. Workspot transitions must reference a saved NPC workspot location. Coordinates may be explicit or captured from player/aim."""
    if source not in {"player", "aim"}:
        raise ValueError("source must be player or aim")
    coords = (x, y, z)
    if any(v is not None for v in coords) and any(v is None for v in coords):
        raise ValueError("provide x, y, and z together")
    args: dict[str, Any] = {"route_id": route_id, "variant": variant, "name": name, "wait_seconds": wait_seconds,
        "facing_yaw": facing_yaw, "speed": speed, "transition": transition,
        "workspot_location_id": workspot_location_id, "branch_fact": branch_fact, "branch_value": branch_value,
        "branch_target_id": branch_target_id, "source": source}
    if x is not None:
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": yaw}}
    return _json(_send("npc_route_add_waypoint", args))


@mcp.tool()
def npc_route_update_waypoint(route_id: str, waypoint_id: str, variant: str = "patrol",
                              wait_seconds: float | None = None, facing_yaw: float | None = None,
                              speed: float | None = None, transition: str | None = None,
                              workspot_location_id: str | None = None, branch_fact: str | None = None,
                              branch_value: int | None = None, branch_target_id: str | None = None,
                              name: str | None = None, x: float | None = None, y: float | None = None,
                              z: float | None = None, yaw: float | None = None) -> str:
    """Edit waypoint position/rotation, timing, facing, speed, workspot transition, or conditional branch fields."""
    coords = (x, y, z)
    if any(v is not None for v in coords) and any(v is None for v in coords):
        raise ValueError("provide x, y, and z together")
    patch = {k: v for k, v in locals().items() if k not in {"route_id", "waypoint_id", "variant", "x", "y", "z", "yaw"} and v is not None}
    if x is not None:
        patch["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1}, "rotation": {"roll": 0, "pitch": 0, "yaw": yaw or 0}}
    return _json(_send("npc_route_update_waypoint", {"route_id": route_id, "waypoint_id": waypoint_id, "variant": variant, "patch": patch}))


@mcp.tool()
def npc_route_move_waypoint(route_id: str, waypoint_id: str, delta: int, variant: str = "patrol") -> str:
    """Move a waypoint earlier or later in its patrol/alert/combat sequence; delta is typically -1 or 1."""
    return _json(_send("npc_route_move_waypoint", {"route_id": route_id, "waypoint_id": waypoint_id, "delta": delta, "variant": variant}))


@mcp.tool()
def npc_route_delete_waypoint(route_id: str, waypoint_id: str, variant: str = "patrol") -> str:
    """Delete a waypoint from a route variant."""
    return _json(_send("npc_route_delete_waypoint", {"route_id": route_id, "waypoint_id": waypoint_id, "variant": variant}))


@mcp.tool()
def npc_route_update(route_id: str, name: str | None = None, loop: bool | None = None,
                     npc_id: str | None = None, notes: str | None = None) -> str:
    """Rename a route, toggle looping, or relink it to another saved NPC population point."""
    patch = {k: v for k, v in locals().items() if k not in {"route_id"} and v is not None}
    return _json(_send("npc_route_update", {"id": route_id, "patch": patch}))


@mcp.tool()
def npc_route_delete(route_id: str) -> str:
    """Delete a saved NPC route and unlink it from its population point."""
    return _json(_send("npc_route_delete", {"id": route_id}))


@mcp.tool()
def combat_encounter_create(name: str, premise_id: str, area_volume_id: str = "", trigger_volume_id: str = "",
                            activation_fact: str = "", activation_value: int = 1, notes: str = "") -> str:
    """Create a combat encounter linked to saved combat-area and trigger volumes in one premise."""
    return _json(_send("combat_encounter_create", {"name": name, "premise_id": premise_id,
        "area_volume_id": area_volume_id, "trigger_volume_id": trigger_volume_id,
        "activation_fact": activation_fact, "activation_value": activation_value, "notes": notes}))


@mcp.tool()
def combat_encounter_list(premise_id: str | None = None) -> str:
    """List authored combat encounters and their enemy groups and waves."""
    return _json(_send("combat_encounter_list", {"premise_id": premise_id} if premise_id else {}))


@mcp.tool()
def combat_encounter_update(encounter_id: str, name: str | None = None, premise_id: str | None = None,
                            area_volume_id: str | None = None, trigger_volume_id: str | None = None,
                            activation_fact: str | None = None, activation_value: int | None = None,
                            reset_fact: str | None = None, reset_value: int | None = None,
                            notes: str | None = None) -> str:
    """Edit encounter bounds/trigger references and activation/reset quest facts."""
    patch = {k: v for k, v in locals().items() if k != "encounter_id" and v is not None}
    return _json(_send("combat_encounter_update", {"id": encounter_id, "patch": patch}))


@mcp.tool()
def combat_group_create(encounter_id: str, name: str, npc_ids: list[str], faction: str = "",
                        attitude: str = "hostile", spacing: float = 1.5) -> str:
    """Create an enemy/friendly group from persistent NPC population object IDs in the encounter's premise."""
    return _json(_send("combat_group_create", {"encounter_id": encounter_id, "name": name,
        "npc_ids": npc_ids, "faction": faction, "attitude": attitude, "spacing": spacing}))


@mcp.tool()
def combat_group_update(encounter_id: str, group_id: str, name: str | None = None,
                        npc_ids: list[str] | None = None, faction: str | None = None,
                        attitude: str | None = None, spacing: float | None = None) -> str:
    """Edit enemy group composition, faction, attitude, and preview spacing."""
    patch = {k: v for k, v in locals().items() if k not in {"encounter_id", "group_id"} and v is not None}
    return _json(_send("combat_group_update", {"encounter_id": encounter_id, "group_id": group_id, "patch": patch}))


@mcp.tool()
def combat_group_delete(encounter_id: str, group_id: str) -> str:
    """Delete a group and remove it from all encounter waves."""
    return _json(_send("combat_group_delete", {"encounter_id": encounter_id, "group_id": group_id}))


@mcp.tool()
def combat_wave_create(encounter_id: str, name: str, group_ids: list[str], activation: str = "immediate",
                       trigger_volume_id: str = "", fact_name: str = "", fact_value: int = 1,
                       after_wave_id: str = "", delay_seconds: float = 0) -> str:
    """Add a wave activated immediately, by trigger volume, quest fact, or after another wave."""
    return _json(_send("combat_wave_create", {"encounter_id": encounter_id, "name": name,
        "group_ids": group_ids, "activation": activation, "trigger_volume_id": trigger_volume_id,
        "fact_name": fact_name, "fact_value": fact_value, "after_wave_id": after_wave_id,
        "delay_seconds": delay_seconds}))


@mcp.tool()
def combat_wave_update(encounter_id: str, wave_id: str, name: str | None = None,
                       group_ids: list[str] | None = None, activation: str | None = None,
                       trigger_volume_id: str | None = None, fact_name: str | None = None,
                       fact_value: int | None = None, after_wave_id: str | None = None,
                       delay_seconds: float | None = None) -> str:
    """Edit a wave's group composition, trigger/fact condition, prior-wave dependency, or delay."""
    patch = {k: v for k, v in locals().items() if k not in {"encounter_id", "wave_id"} and v is not None}
    return _json(_send("combat_wave_update", {"encounter_id": encounter_id, "wave_id": wave_id, "patch": patch}))


@mcp.tool()
def combat_wave_delete(encounter_id: str, wave_id: str) -> str:
    """Delete a wave and clear reinforcement links that targeted it."""
    return _json(_send("combat_wave_delete", {"encounter_id": encounter_id, "wave_id": wave_id}))


@mcp.tool()
def combat_faction_relation(encounter_id: str, source_faction: str, target_faction: str,
                            attitude: str = "hostile") -> str:
    """Save a friendly/neutral/hostile faction relationship as encounter handoff data."""
    return _json(_send("combat_faction_relation", {"encounter_id": encounter_id,
        "source_faction": source_faction, "target_faction": target_faction, "attitude": attitude}))


@mcp.tool()
def combat_encounter_test(encounter_id: str, wave_id: str = "") -> str:
    """Spawn temporary Character-record stand-ins for one wave (or all waves) at their saved NPC transforms."""
    args = {"encounter_id": encounter_id}
    if wave_id:
        args["wave_id"] = wave_id
    return _json(_send("combat_encounter_test", args))


@mcp.tool()
def combat_encounter_reset(encounter_id: str) -> str:
    """Delete temporary NPCs created by Test Encounter."""
    return _json(_send("combat_encounter_reset", {"encounter_id": encounter_id}))


@mcp.tool()
def combat_encounter_delete(encounter_id: str) -> str:
    """Delete an encounter and clean up its temporary test NPCs."""
    return _json(_send("combat_encounter_delete", {"id": encounter_id}))


@mcp.tool()
def npc_despawn_tag(tag: str = "ls_npc") -> str:
    """Delete every dynamic entity spawned with this tag (npc_spawn_record), stopping their animations first."""
    return _json(_send("npc_despawn_tag", {"tag": tag}))


@mcp.tool()
def npc_workspot_create(name: str, kind: str, x: float, y: float, z: float, yaw: float = 0.0,
                        animation_name: str = "", rig: str = "Woman Average", component: str = "",
                        workspot_ent: str = "", npc_record: str = "", appearance: str = "") -> str:
    """Save an editable sit/lean/terminal NPC workspot at explicit world coordinates. Provide exact AMM animation/component/.ent fields to enable preview."""
    if kind not in {"sit", "lean", "terminal"}:
        raise ValueError("kind must be sit, lean, or terminal")
    metadata = {"source": "mcp:npc_workspot", "workspot": {"kind": kind, "record": npc_record,
                "appearance": appearance, "animation": {"name": animation_name, "rig": rig,
                "comp": component, "ent": workspot_ent}}}
    return _json(_send("create_location", {"name": name, "type": "workspot", "category": "NPC Workspots",
        "tags": ["npc", kind], "x": x, "y": y, "z": z, "yaw": yaw, "metadata": metadata}))


@mcp.tool()
def npc_workspot_preview(location_id: str, npc_record: str = "", appearance: str = "",
                         animation_name: str = "", rig: str = "Woman Average", component: str = "",
                         workspot_ent: str = "", tag: str = "ls_workspot_preview") -> str:
    """Spawn a temporary NPC at a saved workspot and play the specified AMM workspot entry. Requires Codeware dynamic entities, CET exEntitySpawner and AMM's archive; spawned NPC is not saved."""
    args: dict[str, Any] = {"location_id": location_id, "record": npc_record, "appearance": appearance, "tag": tag}
    if animation_name or component or workspot_ent:
        args["anim"] = {"name": animation_name, "comp": component, "ent": workspot_ent}
    return _json(_send("npc_preview_workspot", args))


@mcp.tool()
def npc_workspot_check_approach(location_id: str, key: str = "", target: str = "crosshair") -> str:
    """Check three collision rays between a live NPC and a saved workspot. This is only a straight-line collision hint, not a REDengine navmesh/pathfinding result."""
    args = {"location_id": location_id, "target": target}
    if key:
        args["key"] = key
    return _json(_send("npc_workspot_approach", args))


@mcp.tool()
def raycast_batch(rays: list[dict[str, Any]], groups: list[str] | None = None) -> str:
    """Cast many rays in one bridge call. rays = [{"from": {x,y,z}, "to": {x,y,z}}, ...] (max 4000).
    groups are collision groups, default ["Static"] (vanilla world; spawned props are "Dynamic").
    Per ray: hit, x/y/z, distance from 'from', group - the nearest hit over all groups."""
    return _json(_send("raycast_batch", {"rays": rays, "groups": groups or ["Static"]}, timeout=120.0))


@mcp.tool()
def floor_probe(points: list[dict[str, float]], z_from: float | None = None, z_to: float | None = None) -> str:
    """Floor height under each {x, y}: a Static+Dynamic ray from z_from down to z_to (default V's z +2.4
    / -1.5). inside_solid=true means the ray started inside geometry - a teleport there lands V on top
    of it. Use before choosing camera or standing spots."""
    args: dict[str, Any] = {"points": points}
    if z_from is not None:
        args["z_from"] = z_from
    if z_to is not None:
        args["z_to"] = z_to
    return _json(_send("floor_probe", args, timeout=60.0))


@mcp.tool()
def walkability_check(goal_x: float, goal_y: float, goal_z: float, actor: str = "player", npc_key: str = "",
                      start_x: float | None = None, start_y: float | None = None, start_z: float | None = None,
                      grid_step: float = 1.0, margin: float = 2.0, actor_radius: float | None = None,
                      actor_height: float | None = None, navigation_graph_id: str = "",
                      snap_distance: float = 3.0) -> str:
    """Estimate a floor-supported, collision-clear route from V (or an NPC) to a goal. Returns sampled path cells and blocking hit positions, including Dynamic hits that may be props. This is not a REDengine navmesh query: validate candidates in game. Defaults sample a 1 m grid with a 2 m detour margin; max 120 cells."""
    if actor not in {"player", "npc"}:
        raise ValueError("actor must be 'player' or 'npc'")
    args: dict[str, Any] = {"goal": {"x": goal_x, "y": goal_y, "z": goal_z}, "actor": actor,
        "npc_key": npc_key, "grid_step": grid_step, "margin": margin}
    if start_x is not None or start_y is not None or start_z is not None:
        if start_x is None or start_y is None or start_z is None:
            raise ValueError("provide all of start_x, start_y, and start_z, or omit all three")
        args["start"] = {"x": start_x, "y": start_y, "z": start_z}
    if actor_radius is not None:
        args["actor_radius"] = actor_radius
    if actor_height is not None:
        args["actor_height"] = actor_height
    if navigation_graph_id:
        args["navigation_graph_id"] = navigation_graph_id
        args["snap_distance"] = snap_distance
    return _json(_send("walkability_check", args, timeout=120.0))


@mcp.tool()
def navigation_graph_import(graph: dict[str, Any]) -> str:
    """Import portable LocationStudio graph/navdata (not raw REDengine navmesh files). Format: {name,source_format,nodes:[{id,position:{x,y,z},name?}],edges:[{id,from,to,kind:walk|door|stairs|elevator|jump|off_mesh|custom,one_way?,enabled?,cost?}],polygons:[{id,vertices:[{x,y,z},...],surface?}]}. Coordinates are world coordinates. Limits: 50k nodes, 100k edges, 25k polygons."""
    return _json(_send("navigation_graph_import", {"graph": graph}, timeout=120.0))


@mcp.tool()
def navigation_graph_list() -> str:
    """List imported graph metadata and node/edge/polygon counts. This does not report live REDengine navmesh data."""
    return _json(_send("navigation_graph_list", {}))


@mcp.tool()
def navigation_graph_check(start_x: float, start_y: float, start_z: float, goal_x: float, goal_y: float,
                           goal_z: float, graph_id: str = "", snap_distance: float = 3.0) -> str:
    """Check connectivity in an imported graph using Dijkstra. This is not native AI reachability."""
    args = {"start": {"x": start_x, "y": start_y, "z": start_z},
            "goal": {"x": goal_x, "y": goal_y, "z": goal_z}, "snap_distance": snap_distance}
    if graph_id:
        args["graph_id"] = graph_id
    return _json(_send("navigation_graph_check", args))


@mcp.tool()
def navigation_workspot_report(start_x: float, start_y: float, start_z: float,
                                graph_id: str = "", snap_distance: float = 3.0) -> str:
    """Mark saved workspots reachable/unreachable/unmapped in an imported graph from this start. Not a REDengine navmesh query."""
    args = {"start": {"x": start_x, "y": start_y, "z": start_z}, "snap_distance": snap_distance}
    if graph_id:
        args["graph_id"] = graph_id
    return _json(_send("navigation_workspot_report", args))


@mcp.tool()
def cover_node_create(premise_id: str, name: str = "Cover Node", cover_type: str = "crouch",
                      exposure: str = "medium", spacing: float = 1.5, source: str = "player",
                      room_id: str = "", transform: dict[str, Any] | None = None) -> str:
    """Create a persistent cover-position authoring node. source is player or aim when transform is omitted; this does not create native AI cover data."""
    if cover_type not in {"crouch", "standing"}:
        raise ValueError("cover_type must be crouch or standing")
    if exposure not in {"low", "medium", "high"}:
        raise ValueError("exposure must be low, medium, or high")
    args: dict[str, Any] = {"premise_id": premise_id, "name": name, "cover_type": cover_type,
        "exposure": exposure, "spacing": spacing, "source": source}
    if room_id:
        args["room_id"] = room_id
    if transform is not None:
        args["transform"] = transform
    return _json(_send("cover_node_create", args))


@mcp.tool()
def cover_node_list(premise_id: str = "") -> str:
    """List saved editable cover nodes, optionally filtered by premise."""
    args = {"premise_id": premise_id} if premise_id else {}
    return _json(_send("cover_node_list", args))


@mcp.tool()
def cover_node_update(node_id: str, patch: dict[str, Any]) -> str:
    """Edit a saved cover node's transform, facing yaw, crouch/standing posture, exposure, or spacing."""
    return _json(_send("cover_node_update", {"id": node_id, "patch": patch}))


@mcp.tool()
def cover_node_delete(node_id: str) -> str:
    """Delete a saved cover node from the project."""
    return _json(_send("cover_node_delete", {"id": node_id}))


@mcp.tool()
def cover_scan(radius: float = 8.0, samples: int = 24, spacing: float = 1.5,
               center_x: float | None = None, center_y: float | None = None, center_z: float | None = None,
               premise_id: str = "", room_id: str = "", save_to_project: bool = False,
               cover_type: str = "crouch") -> str:
    """Scan around V (or an explicit center) for wall/prop candidates using paired Static/Dynamic collision rays. Results are heuristics, not engine cover or navmesh data. Saving candidates requires premise_id."""
    supplied = (center_x is not None, center_y is not None, center_z is not None)
    if any(supplied) and not all(supplied):
        raise ValueError("provide all center_x/center_y/center_z or omit all three")
    if cover_type not in {"crouch", "standing"}:
        raise ValueError("cover_type must be crouch or standing")
    if save_to_project and not premise_id:
        raise ValueError("premise_id is required when save_to_project is true")
    args: dict[str, Any] = {"radius": radius, "samples": samples, "spacing": spacing,
        "save_to_project": save_to_project, "cover_type": cover_type}
    if all(supplied):
        args["center"] = {"x": center_x, "y": center_y, "z": center_z}
    if premise_id:
        args["premise_id"] = premise_id
    if room_id:
        args["room_id"] = room_id
    return _json(_send("cover_scan", args, timeout=60.0))


@mcp.tool()
def respawn_tagged(tags: list[str], system: str = "", method: str = "SyncProps") -> str:
    """Delete Codeware dynamic entities by tag, then (if system is given) call that scriptable system's
    no-argument method, e.g. system="AshCache.AshCacheGlue" to respawn props at their current pose."""
    return _json(_send("respawn_tagged", {"tags": tags, "system": system or None, "method": method}))


@mcp.tool()
def capture_views(views: list[dict[str, Any]], settle_s: float = 9.0) -> str:
    """Screenshot a list of camera spots. Each view: {x, y, yaw, pitch, name, z?}. For every view the floor
    is probed first; a spot inside solid geometry, or with no floor within 1.5 m, is skipped with a reason
    instead of teleporting V on top of something. Then V is teleported, the camera pitch is locked,
    settle_s seconds pass (teleport motion blur lasts ~5-8 s), a screenshot is taken and the pitch
    limits are always restored. Only use spots in already-streamed areas. Returns per view the PNG
    path or the skip reason; open PNGs with the Read tool."""
    shot = getattr(screenshot, "fn", screenshot)
    here = _send("capture_player")
    base_z = float(here.get("position", {}).get("z", 0.0))
    results = []
    for view in views:
        name = str(view.get("name") or "view")
        vz = float(view.get("z", base_z))
        probe = _send("floor_probe", {"points": [{"x": view["x"], "y": view["y"]}], "z_from": vz + 2.4, "z_to": vz - 1.5})
        point = probe["points"][0]
        floor_z = point.get("floor_z")
        if point.get("inside_solid") or floor_z is None or abs(floor_z - vz) > 1.5:
            results.append({"name": name, "skipped": "inside solid geometry" if point.get("inside_solid") else f"no floor near z {vz:.2f} (hit {floor_z})"})
            continue
        if floor_z - vz > 0.3:
            results.append({"name": name, "skipped": f"floor here is {floor_z - vz:+.2f} m above the expected level (on top of furniture?)"})
            continue
        _send("teleport_raw", {"position": {"x": view["x"], "y": view["y"], "z": floor_z + 0.02, "w": 1},
                               "rotation": {"roll": 0, "pitch": 0, "yaw": float(view.get("yaw", 0.0))}})
        try:
            _send("camera_pitch", {"pitch": float(view.get("pitch", 0.0))})
            time.sleep(settle_s)
            out = shot(name=name)
            results.append({"name": name, "floor_z": floor_z, "shot": json.loads(out).get("path", out) if out.startswith("{") else out})
        finally:
            _send("camera_pitch", {"restore": True})
    return _json(results)


@mcp.tool()
def call_scriptable_system(system: str, method: str) -> str:
    """Call a no-argument method on a redscript ScriptableSystem in the running game, e.g.
    system="AshCache.AshCacheGlue", method="SyncProps". Use after a hot script reload: RedHotTools
    swaps the code, but OnAttach/OnRestored do not run again, so state-driven spawns need a nudge."""
    return _json(_send("call_system", {"system": system, "method": method}))


@mcp.tool()
def teleport_player(x: float, y: float, z: float, yaw: float = 0.0) -> str:
    """Teleport V to a world position facing yaw (degrees). Only use points known to be walkable
    AND streamed in: a teleport into an area whose collision is still loading drops V through the floor."""
    return _json(_send("teleport_raw", {"position": {"x": x, "y": y, "z": z, "w": 1},
                                        "rotation": {"roll": 0, "pitch": 0, "yaw": yaw}}))


@mcp.tool()
def rht_status() -> str:
    """Check that the RedHotTools RED4ext plugin and its WorldInspector are loaded and ready."""
    return _json(_send("rht_status"))


@mcp.tool()
def rht_inspect_crosshair(distance: float = 50.0) -> str:
    """RedHotTools inspect of everything under the crosshair: physics hits in every collision group,
    the look-at entity, and static-bounds nodes. Each target reports sectorPath, nodeIndex, nodeType,
    nodeID/nodeRef, mesh/material/template path, appearance, recordID, entity/community data.
    Also saved to exports/ in the mod folder."""
    return _json(_send("rht_crosshair", {"distance": distance}, timeout=30.0))


@mcp.tool()
def rht_scan(
    radius: float = 25.0,
    term: str = "",
    x: float | None = None,
    y: float | None = None,
    z: float | None = None,
    limit: int = 300,
    entities: bool = True,
    frustum_distance: float | None = None,
) -> str:
    """RedHotTools scan of streamed world nodes in the camera frustum plus nearby entities, within
    radius of (x, y, z) or the player, filtered by a substring term (type, sector, mesh, template,
    record, nodeRef, debug name). Only what the camera frustum covers is scanned. Also saved to exports/."""
    args: dict = {"radius": radius, "term": term, "limit": limit, "entities": entities}
    if x is not None and y is not None and z is not None:
        args["center"] = {"x": x, "y": y, "z": z}
    if frustum_distance is not None:
        args["frustum_distance"] = frustum_distance
    return _json(_send("rht_scan", args, timeout=60.0))


@mcp.tool()
def rht_inspect_node(node_id: str = "", node_ref: str = "") -> str:
    """RedHotTools lookup of one world node by its 64-bit node ID (decimal) or by nodeRef ($/...)."""
    return _json(_send("rht_node", {"node_id": node_id or None, "node_ref": node_ref or None}))


@mcp.tool()
def vanilla_removal_status() -> str:
    """Report native-world removal capability and active reversible hidden-node records."""
    return _json(_send("vanilla_removal_status"))


@mcp.tool()
def remove_vanilla_under_crosshair(distance: float = 50.0) -> str:
    """Hide and persist the visible vanilla streamed world node under the crosshair. This is reversible visibility removal, not permanent deletion."""
    return _json(_send("remove_vanilla_crosshair", {"distance": distance}, timeout=30.0))


@mcp.tool()
def remove_nearby_vanilla_assets(radius: float = 25.0, term: str = "", limit: int = 300) -> str:
    """Hide and persist nearby visible vanilla streamed nodes in the RedHotTools frustum scan. This is reversible visibility removal, not permanent deletion."""
    return _json(_send("remove_vanilla_nearby", {"radius": radius, "term": term, "limit": limit}, timeout=60.0))


@mcp.tool()
def restore_vanilla_removal(removal_id: str = "") -> str:
    """Restore one previously hidden vanilla streamed node, or the first active record when no ID is supplied."""
    return _json(_send("restore_vanilla_removal", {"id": removal_id or None}, timeout=30.0))


@mcp.tool()
def restore_all_vanilla_removals() -> str:
    """Restore every active reversible vanilla-node visibility removal."""
    return _json(_send("restore_all_vanilla_removals", {}, timeout=60.0))


@mcp.tool()
def list_vanilla_removals() -> str:
    """List persistent vanilla-node visibility removal records."""
    return _json(_send("list_vanilla_removals"))


@mcp.tool()
def list_scenes(premise_id: str = "") -> str:
    """List saved scene collections and their owned room/object/gameplay references."""
    scenes = _project().get("scenes", [])
    if premise_id:
        scenes = [scene for scene in scenes if scene.get("premise_id") == premise_id]
    return _json({"count": len(scenes), "scenes": scenes})


@mcp.tool()
def create_scene(
    name: str,
    premise_id: str,
    kind: str = "gameplay",
    room_ids: list[str] | None = None,
    object_ids: list[str] | None = None,
    location_ids: list[str] | None = None,
    volume_ids: list[str] | None = None,
    camera_ids: list[str] | None = None,
    route_ids: list[str] | None = None,
    notes: str = "",
) -> str:
    """Create a validated reusable scene collection without duplicating its members."""
    return _json(_send("create_scene", {
        "name": name, "premise_id": premise_id, "kind": kind,
        "room_ids": room_ids or [], "object_ids": object_ids or [],
        "location_ids": location_ids or [], "volume_ids": volume_ids or [],
        "camera_ids": camera_ids or [], "route_ids": route_ids or [], "notes": notes,
    }))


@mcp.tool()
def update_scene(scene_id: str, patch: dict[str, Any]) -> str:
    """Update scene metadata or membership; all referenced ids are validated by CET."""
    return _json(_send("update_scene", {"id": scene_id, "patch": patch}))


@mcp.tool()
def delete_scene(scene_id: str) -> str:
    """Delete only a scene collection; member rooms, objects, and gameplay data are preserved."""
    return _json(_send("delete_scene", {"id": scene_id}))


@mcp.tool()
def activate_scene(scene_id: str, spawn: bool = True) -> str:
    """Select a scene and optionally spawn every owned room shell and object through real game backends."""
    return _json(_send("activate_scene", {"id": scene_id, "spawn": spawn}))


@mcp.tool()
def deactivate_scene(scene_id: str) -> str:
    """Despawn a scene's owned room-shell and explicit objects while preserving all saved authoring data."""
    return _json(_send("deactivate_scene", {"id": scene_id}))


@mcp.tool()
def isolate_scene(scene_id: str) -> str:
    """Despawn other tracked project objects, then activate only the requested scene."""
    return _json(_send("isolate_scene", {"id": scene_id}))


@mcp.tool()
def capture_scene_from_premise(
    premise_id: str,
    name: str = "New Scene",
    scene_id: str = "",
    mode: str = "replace",
    include_rooms: bool = True,
    include_objects: bool = True,
    include_spatial: bool = True,
    include_construction: bool = False,
) -> str:
    """Create or synchronize a scene from real authored contents of one premise/location."""
    return _json(_send("capture_scene_from_premise", {
        "premise_id": premise_id, "name": name, "scene_id": scene_id or None,
        "mode": mode, "include_rooms": include_rooms, "include_objects": include_objects,
        "include_spatial": include_spatial, "include_construction": include_construction,
    }))


@mcp.tool()
def edit_scene_members(
    scene_id: str,
    mode: str = "add",
    room_ids: list[str] | None = None,
    object_ids: list[str] | None = None,
    location_ids: list[str] | None = None,
    volume_ids: list[str] | None = None,
    camera_ids: list[str] | None = None,
    route_ids: list[str] | None = None,
) -> str:
    """Add, remove, or replace explicit validated scene membership lists."""
    if mode not in {"add", "remove", "replace"}:
        raise ValueError("mode must be add, remove, or replace")
    args: dict[str, Any] = {"id": scene_id, "mode": mode}
    for key, value in {
        "room_ids": room_ids, "object_ids": object_ids,
        "location_ids": location_ids, "volume_ids": volume_ids,
        "camera_ids": camera_ids, "route_ids": route_ids,
    }.items():
        if value is not None:
            args[key] = value
    return _json(_send("edit_scene_members", args))


@mcp.tool()
def add_current_selection_to_scene(scene_id: str) -> str:
    """Add LocationStudio's current room/object/point/volume/camera/route selection to an editing scene."""
    return _json(_send("add_selection_to_scene", {"id": scene_id}))


@mcp.tool()
def remove_current_selection_from_scene(scene_id: str) -> str:
    """Remove LocationStudio's current selection from a scene without deleting the authored members."""
    return _json(_send("remove_selection_from_scene", {"id": scene_id}))


@mcp.tool()
def get_scene_status() -> str:
    """Get editing/live scene ids plus the last scene lifecycle result or error."""
    return _json(_send("get_scene_status"))


@mcp.tool()
def select_scene_objects(scene_id: str) -> str:
    """Select a scene's object members as one editable transform selection in LocationStudio."""
    return _json(_send("select_scene_objects", {"id": scene_id}))


@mcp.tool()
def get_authoring_plan_schema() -> str:
    """Get the supported declarative plan operations for assets, rooms, locations, scenes, movement, and spawning."""
    return _json(_send("get_authoring_plan_schema"))


@mcp.tool()
def get_authoring_plan_examples() -> str:
    """Get executable starter-workspace, furnished-room, gameplay-route, and captured-scene plans."""
    return _json(_send("get_authoring_plan_examples"))


@mcp.tool()
def resolve_authoring_asset(asset_id: str = "", query: str = "") -> str:
    """Resolve one Project Asset exactly or by an unambiguous name/template substring before writing a plan."""
    return _json(_send("resolve_authoring_asset", {"asset_id": asset_id or None, "query": query}))


@mcp.tool()
def validate_authoring_plan(plan: dict[str, Any]) -> str:
    """Dry-validate a complete authoring plan without changing project or game state."""
    return _json(_send("validate_authoring_plan", {"plan": plan}))


@mcp.tool()
def execute_authoring_plan(plan: dict[str, Any], save: bool = False) -> str:
    """Execute one validated plan transaction. Success creates one undo; failure rolls every step back."""
    return _json(_send("execute_authoring_plan", {"plan": plan, "save": save}, timeout=max(DEFAULT_TIMEOUT, 30.0)))


@mcp.tool()
def save_authoring_plan_file(plan: dict[str, Any], overwrite: bool = False) -> str:
    """Validate through live CET, then save data/authoring-plan.json for repeatable player/hotkey execution."""
    validation = _send("validate_authoring_plan", {"plan": plan})
    if not validation.get("valid"):
        raise ValueError("Invalid authoring plan: " + "; ".join(map(str, validation.get("errors", []))))
    if AUTHORING_PLAN.exists() and not overwrite:
        raise FileExistsError(f"{AUTHORING_PLAN} already exists; pass overwrite=true to replace it")
    _atomic_json(AUTHORING_PLAN, plan)
    return _json({"saved": True, "path": str(AUTHORING_PLAN), "validation": validation})


@mcp.tool()
def validate_authoring_plan_file() -> str:
    """Validate data/authoring-plan.json in CET without executing it."""
    return _json(_send("validate_authoring_plan_file"))


@mcp.tool()
def execute_authoring_plan_file(save: bool = False) -> str:
    """Execute data/authoring-plan.json as one reversible transaction."""
    return _json(_send("execute_authoring_plan_file", {"save": save}, timeout=max(DEFAULT_TIMEOUT, 30.0)))


@mcp.tool()
def get_authoring_plan_status() -> str:
    """Get the last plan result and any rollback-recovery state."""
    return _json(_send("get_authoring_plan_status"))


@mcp.tool()
def retry_authoring_plan_rollback() -> str:
    """Retry safe cleanup and restore the project snapshot after a blocked plan rollback."""
    return _json(_send("retry_authoring_plan_rollback", timeout=max(DEFAULT_TIMEOUT, 30.0)))


@mcp.tool()
def keep_partial_authoring_plan() -> str:
    """Explicitly keep a failed plan's partial result as one undoable project change."""
    return _json(_send("keep_partial_authoring_plan"))


@mcp.resource("locationstudio://project")
def project_resource() -> str:
    """Current saved LocationStudio project JSON."""
    return _json(_project())


@mcp.resource("locationstudio://status")
def status_resource() -> str:
    """Current live LocationStudio/CET status snapshot."""
    return _json(_live_status())


# ---------------------------------------------------------------------------
# Headless build: LS objects -> World Builder *_exported.json -> CR2W sectors
# -> .archive + .xl -> game-layout package -> verify/deploy. The pipeline code
# is vendored from cp77wb 1.0.1 in lsbuild/. Every writing step is a preview
# unless write/run/apply is set, matching cp77wb's safety contract.
# ---------------------------------------------------------------------------

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mod_inventory import scan_mod_installation as _scan_mod_installation  # noqa: E402
from lsbuild import build as _lsb, native as _lsn, worker as _lsw, wiring as _lswire, rng as _lsrng, interactables as _lsip, population as _lsp, vfx as _lsvfx  # noqa: E402

WORLD_BUILDER_ROOT = MOD_DIR.parent / "entSpawner"
BUILD_ROOT = MOD_DIR / "exports" / "build"


def _game_root(game_root: str | None) -> Path:
    if game_root:
        return Path(game_root).expanduser()
    # .../<game>/bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio
    candidate = MOD_DIR.parents[5]
    if (candidate / "bin" / "x64" / "Cyberpunk2077.exe").is_file():
        return candidate
    raise ValueError(f"Cannot infer the game root from {MOD_DIR}; pass game_root explicitly.")


def _optional_game_root(game_root: str | None) -> Path | None:
    try:
        return _game_root(game_root)
    except ValueError:
        return None


def _export_file(name_or_path: str) -> Path:
    p = Path(name_or_path).expanduser()
    if p.suffix == ".json":
        return p
    return WORLD_BUILDER_ROOT / "export" / f"{name_or_path}_exported.json"


def _workspace(name: str, workspace: str | None) -> Path:
    return Path(workspace).expanduser() if workspace else BUILD_ROOT / name


@mcp.tool()
def build_export_world_builder(
    name: str,
    premise_id: str | None = None,
    scene_id: str | None = None,
    object_ids: list[str] | None = None,
    category: int | None = None,
    level: int | None = None,
    streaming_x: float | None = None,
    streaming_y: float | None = None,
    streaming_z: float | None = None,
    xl_format: int = 0,
    allow_skipped: bool = False,
) -> str:
    """Live: write a real World Builder *_exported.json from LocationStudio objects.

    Scope is premise_id, scene_id, object_ids, or the whole project. Only objects
    live in World Builder can be exported; CET-spawned objects are refused unless
    allow_skipped=true. Saves WB group `ls_<name>` and runs WB's own exporter.
    `name` must match [a-z0-9_]+ and becomes the .archive/.xl/sector name.
    """
    streaming = {k: v for k, v in (("x", streaming_x), ("y", streaming_y), ("z", streaming_z)) if v is not None}
    args: dict[str, Any] = {"name": name, "premise_id": premise_id, "scene_id": scene_id, "object_ids": object_ids,
                            "category": category, "level": level, "streaming": streaming, "xl_format": xl_format,
                            "allow_skipped": allow_skipped}
    result = _send("build_export_world_builder", {k: v for k, v in args.items() if v is not None}, timeout=30.0)
    result["export_file"] = str(_export_file(name))
    result["export_file_exists"] = _export_file(name).is_file()
    return _json(result)


@mcp.tool()
def build_export_status() -> str:
    """Live: whether World Builder's exporter is reachable, plus the last export result."""
    return _json(_send("build_export_status"))


@mcp.tool()
def build_export_inspect(export_file: str) -> str:
    """Validate a WB export (path, or export name under entSpawner/export) before conversion."""
    return _json(_lsb.inspect_export(_export_file(export_file)))


@mcp.tool()
def wb_device_connect(export_file: str, source_hash: str, target_hash: str) -> str:
    """Write one World Builder device-resource link into an existing exported JSON.

    Hashes must be keys in export.devices. Updates source.children and the reciprocal
    target.parents entry, idempotently. Does not invent missing device/instance data.
    """
    return _json(_lswire.connect(_export_file(export_file), source_hash, target_hash))


@mcp.tool()
def wb_elevator_wire(export_file: str, elevator_hash: str, floor_terminal_hashes: list[str]) -> str:
    """Wire an elevator to an ordered list of floor terminal device hashes.

    Validates LiftControllerPS and ElevatorFloorTerminalControllerPS class names,
    then writes the device graph and preserves caller order (lowest floor first).
    The separate NodeRefs, floor markers and terminal persistent instance setup are
    still authored in World Builder; this operation reports its exact limited scope.
    """
    return _json(_lswire.elevator(_export_file(export_file), elevator_hash, floor_terminal_hashes))


@mcp.tool()
def wb_device_logic_apply(export_file: str, graph_id: str) -> str:
    """Apply a saved Device Logic graph to a World Builder export. It can add missing device/PS/sector-node entries only when complete typed native.device_record, native.ps_entry, native.world_node, and sector_name payloads are supplied from compatible WB presets. Otherwise it returns blockers without modifying the export. Applies device-to-device links; semantic facts/actions are not executed by REDengine."""
    graph = _send("device_logic_graph_get", {"graph_id": graph_id})
    return _json(_lswire.apply_logic_graph(_export_file(export_file), graph))


@mcp.tool()
def device_logic_graph_create(name: str, premise_id: str = "") -> str:
    """Create a persistent Device Logic graph in the active LocationStudio project."""
    args: dict[str, Any] = {"name": name}
    if premise_id:
        args["premise_id"] = premise_id
    return _json(_send("device_logic_graph_create", args))


@mcp.tool()
def device_logic_graph_list() -> str:
    """List saved Device Logic graphs and their node/link authoring data."""
    return _json(_send("device_logic_graph_list", {}))


@mcp.tool()
def device_logic_graph_delete(graph_id: str) -> str:
    """Delete a saved Device Logic graph."""
    return _json(_send("device_logic_graph_delete", {"graph_id": graph_id}))


@mcp.tool()
def device_logic_node_add(graph_id: str, kind: str, name: str, object_id: str = "",
                          config: dict[str, Any] | None = None, native: dict[str, Any] | None = None) -> str:
    """Add terminal/door/elevator/switch/camera/security_system/fact/action node. Fact nodes need config.fact_name; action nodes need config.operation. Device bindings use native.device_hash/device_class/ps_entry_hash/instance_data_ref/node_ref; see DEVICE-LOGIC.md for optional complete typed device_record/ps_entry/world_node creation payloads."""
    args: dict[str, Any] = {"graph_id": graph_id, "kind": kind, "name": name, "config": config or {}}
    if object_id:
        args["object_id"] = object_id
    if native is not None:
        args["native"] = native
    return _json(_send("device_logic_node_add", args))


@mcp.tool()
def device_logic_node_update(graph_id: str, node_id: str, patch: dict[str, Any]) -> str:
    """Update a graph node. patch may include name, kind, config, object_id, or native binding. Complete supplied native record payloads are required to create missing game resources; see DEVICE-LOGIC.md."""
    return _json(_send("device_logic_node_update", {"graph_id": graph_id, "node_id": node_id, "patch": patch}))


@mcp.tool()
def device_logic_node_delete(graph_id: str, node_id: str) -> str:
    """Delete a graph node and its connected links."""
    return _json(_send("device_logic_node_delete", {"graph_id": graph_id, "node_id": node_id}))


@mcp.tool()
def device_logic_link_add(graph_id: str, from_id: str, to_id: str, trigger: str = "activate",
                          condition_fact: str = "", condition_value: int = 1,
                          native_operation: str = "") -> str:
    """Connect two graph nodes with an event trigger and optional quest-fact condition."""
    return _json(_send("device_logic_link_add", {"graph_id": graph_id, "from_id": from_id, "to_id": to_id,
        "trigger": trigger, "condition_fact": condition_fact, "condition_value": condition_value,
        "native_operation": native_operation}))


@mcp.tool()
def device_logic_link_delete(graph_id: str, link_id: str) -> str:
    """Remove a graph link."""
    return _json(_send("device_logic_link_delete", {"graph_id": graph_id, "link_id": link_id}))


@mcp.tool()
def device_logic_validate(graph_id: str = "") -> str:
    """Validate graph endpoints and semantics. Reports missing World Builder device hashes and persistent-state/instance-data bindings; never claims native runtime execution."""
    args = {"graph_id": graph_id} if graph_id else {}
    return _json(_send("device_logic_validate", args))


@mcp.tool()
def build_export_xl(export_file: str, output: str | None = None, format: str | None = None, write: bool = False) -> str:
    """Show the ArchiveXL (.xl) config a WB export implies; write=true writes it to output."""
    path = _export_file(export_file)
    if not write:
        return _json({"written": False, "xl": _lsb.archive_xl_config(_lsb._read_json(path))})
    if not output:
        raise ValueError("output is required when write=true")
    return _json({"written": True, "result": _lsb.write_archive_xl(path, output, format=format)})


@mcp.tool()
def build_backends(cli: str | None = None) -> str:
    """Report which CR2W conversion backends (.NET worker, WolvenKit CLI, WScript) are usable here."""
    return _json(_lsb.backend_scan(cli=cli, world_builder_root=WORLD_BUILDER_ROOT if WORLD_BUILDER_ROOT.is_dir() else None))


@mcp.tool()
def build_prepare(export_file: str, workspace: str | None = None, project_name: str | None = None, author: str = "",
                  project_version: str = "1.0.0", description: str = "Built with LocationStudio",
                  force: bool = False, write: bool = False) -> str:
    """Preview or create the WolvenKit workspace (.cpmodproj, raw export, .xl). Default parent: exports/build."""
    path = _export_file(export_file)
    report = _lsb.inspect_export(path)
    name = project_name or report.get("name")
    parent = Path(workspace).expanduser() if workspace else BUILD_ROOT
    if not write:
        return _json({"written": False, "export": report, "workspace": str(parent / str(name)), "requiresWrite": True})
    wb_root = WORLD_BUILDER_ROOT if WORLD_BUILDER_ROOT.is_dir() else None
    return _json({"written": True, "result": _lsb.prepare_build_workspace(
        path, parent, world_builder_root=wb_root, project_name=project_name, author=author,
        version=project_version, description=description, force=force)})


@mcp.tool()
def build_status(workspace: str) -> str:
    """Check that every expected streamingsector/block/device file exists and the raw export is unchanged."""
    return _json(_lsb.build_status(workspace))


@mcp.tool()
def build_worker(run: bool = False, dotnet: str | None = None, output: str | None = None, log_file: str | None = None,
                 timeout: int = 600) -> str:
    """Preview or build the bundled .NET WolvenKit worker (lsbuild/wkit_worker). run=false by default."""
    return _json(_lsw.build_worker(output=output, dotnet=dotnet, run=run, timeout=timeout, log_file=log_file))


@mcp.tool()
def build_worker_preflight(worker: str | None = None, timeout: int = 30) -> str:
    """Run the worker self-test. The worker backend is authoritative only when this reports ready."""
    return _json(_lsw.worker_preflight(worker=worker, timeout=timeout))


@mcp.tool()
def build_worker_inspect(worker: str | None = None, timeout: int = 30) -> str:
    """Inspect the worker's discovered WolvenKit assemblies and serializer/writer API profile."""
    return _json(_lsw.worker_inspect(worker=worker, timeout=timeout))


@mcp.tool()
def build_worker_doctor(worker: str | None = None, output: str | None = None, timeout: int = 30) -> str:
    """Collect .NET/worker diagnostics; output=<zip> also writes a support bundle."""
    return _json(_lsw.worker_doctor(worker=worker, output=output, timeout=timeout))


@mcp.tool()
def build_worker_import(workspace: str, worker: str | None = None, run: bool = False, timeout: int = 300) -> str:
    """Preview or convert a prepared workspace to CR2W through the verified .NET worker. run=false by default."""
    return _json(_lsb.build_worker_import(workspace, worker=worker, run=run, timeout=timeout))


@mcp.tool()
def build_native_preflight(cli: str | None = None, timeout: int = 30) -> str:
    """Probe a WolvenKit CLI/cp77tools for `convert deserialize` (fallback conversion backend)."""
    return _json(_lsn.native_preflight(cli=cli, timeout=timeout))


@mcp.tool()
def build_native_template_verify(export_file: str, bundle: str) -> str:
    """Check a captured RED template bundle covers every type the WB export needs."""
    return _json(_lsn.verify_template_bundle(_export_file(export_file), bundle))


@mcp.tool()
def build_native_import(workspace: str, bundle: str, cli: str | None = None, run: bool = False, timeout: int = 300) -> str:
    """Fallback backend: template bundle + WolvenKit CLI deserialize into a workspace. run=false by default."""
    return _json(_lsb.build_native_import(workspace, bundle, cli=cli, run=run, timeout=timeout))


@mcp.tool()
def build_pack(workspace: str, cli: str | None = None, output: str | None = None, run: bool = False,
               timeout: int = 300) -> str:
    """Preview or pack the workspace into <name>.archive with WolvenKit CLI/cp77tools. Requires importComplete."""
    return _json(_lsb.build_pack(workspace, cli=cli, output=output, run=run, timeout=timeout))


@mcp.tool()
def build_package(workspace: str, archive: str, output: str | None = None, zip: str | None = None,
                  write: bool = False) -> str:
    """Preview or assemble the game-layout folder (archive/pc/mod/*.archive + .xl) and optional ZIP."""
    layout = Path(output).expanduser() if output else Path(workspace) / "dist"
    if not write:
        return _json({"written": False, "workspace": workspace, "archive": archive, "output": str(layout), "zip": zip,
                      "requiresWrite": True})
    return _json({"written": True, "result": _lsb.build_package(workspace, archive=archive, output=layout, zip_output=zip)})


@mcp.tool()
def build_verify(layout: str, game_root: str | None = None) -> str:
    """Verify a game-layout package; with a game root (inferred when omitted) also report install conflicts."""
    return _json(_lsb.verify_package(layout, game_root=_optional_game_root(game_root)))


@mcp.tool()
def build_deploy(layout: str, game_root: str | None = None, apply: bool = False, overwrite: bool = False) -> str:
    """Preview or copy a package into the game. apply=false by default; conflicts need overwrite and are backed up."""
    return _json(_lsb.deploy_layout(layout, _game_root(game_root), apply=apply, overwrite=overwrite))


@mcp.tool()
def build_doctor(layout: str, game_root: str | None = None, tail: int = 200) -> str:
    """Verify a package and summarize issue lines from WB/CET/RED4ext/redscript/ArchiveXL logs."""
    return _json(_lsb.build_doctor(layout, game_root=_optional_game_root(game_root), tail=tail))


@mcp.tool()
def build_mod_from_project(
    name: str,
    premise_id: str | None = None,
    scene_id: str | None = None,
    allow_skipped: bool = False,
    worker: str | None = None,
    cli: str | None = None,
    run: bool = False,
) -> str:
    """Whole pipeline: WB export -> inspect -> workspace -> VFX scale -> worker CR2W -> status -> pack -> package -> verify.

    run=false only reports readiness (live WB exporter, worker, CLI) and the
    planned paths; nothing is written. run=true executes every stage and stops at
    the first failure, naming it. Deployment stays separate: call build_deploy.
    """
    workspace = BUILD_ROOT / name
    layout = workspace / "dist"
    if not run:
        readiness: dict[str, Any] = {"worker": _lsw.worker_preflight(worker=worker)}
        cli_path = cli or _lsb.shutil.which("cp77tools") or _lsb.shutil.which("WolvenKit.CLI")
        readiness["cli"] = {"path": cli_path, "ready": bool(cli_path)}
        try:
            readiness["world_builder_export"] = _send("build_export_status")
        except (RuntimeError, TimeoutError) as exc:
            readiness["world_builder_export"] = {"available": False, "reason": str(exc)}
        ready = bool(readiness["worker"].get("ready") and cli_path and readiness["world_builder_export"].get("available"))
        return _json({"ran": False, "ready": ready, "readiness": readiness, "workspace": str(workspace),
                      "export_file": str(_export_file(name)), "layout": str(layout)})

    stages: dict[str, Any] = {}

    def stage(label: str, fn):
        try:
            stages[label] = fn()
        except Exception as exc:  # report the failing stage instead of a bare traceback
            stages[label] = {"error": f"{type(exc).__name__}: {exc}"}
            raise _StageFailed(label) from exc
        return stages[label]

    try:
        stage("export", lambda: json.loads(build_export_world_builder(name, premise_id=premise_id, scene_id=scene_id,
                                                                       allow_skipped=allow_skipped)))
        report = stage("inspect", lambda: _lsb.inspect_export(_export_file(name)))
        if not report["valid"]:
            stages["inspect"]["error"] = f"{report['errors']} export error(s)"
            raise _StageFailed("inspect")
        wb_root = WORLD_BUILDER_ROOT if WORLD_BUILDER_ROOT.is_dir() else None
        stage("prepare", lambda: _lsb.prepare_build_workspace(_export_file(name), BUILD_ROOT, world_builder_root=wb_root,
                                                              description="Built with LocationStudio", force=True))
        population_audit = stage("npc_population", lambda: _lsp.audit(PROJECT, _export_file(name),
            workspace / "automation" / "npc-population-audit.json"))
        if not population_audit.get("ready"):
            stages["npc_population"]["error"] = "one or more saved population points did not become a matching native worldPopulationSpawnerNode"
            raise _StageFailed("npc_population")
        vfx_report = stage("vfx", lambda: _lsvfx.apply_to_workspace(PROJECT, workspace,
            workspace / "automation" / "vfx-export.json"))
        if not vfx_report.get("ready"):
            stages["vfx"]["error"] = "one or more saved VFX objects could not be written to a unique native particle/effect node"
            raise _StageFailed("vfx")
        artifacts = stage("interactables", lambda: _lsip.generate(PROJECT, _export_file(name), workspace / "interactables"))
        if not artifacts.get("ready"):
            stages["interactables"]["error"] = "interactable artifacts are incomplete; fix loot item rows and retry"
            raise _StageFailed("interactables")
        if artifacts.get("loot_yaml"):
            tweak_dir = workspace / "source" / "resources" / "r6" / "tweaks"
            tweak_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(artifacts["loot_yaml"], tweak_dir / f"{name}_interactables.yaml")
        shutil.copy2(artifacts["manifest"], workspace / "automation" / "interactables-native-manifest.json")
        stage("convert", lambda: _lsb.build_worker_import(workspace, worker=worker, run=True))
        status = stage("status", lambda: _lsb.build_status(workspace))
        if not status.get("importComplete"):
            stages["status"]["error"] = "CR2W outputs incomplete"
            raise _StageFailed("status")
        packed = stage("pack", lambda: _lsb.build_pack(workspace, cli=cli, run=True))
        stage("package", lambda: _lsb.build_package(workspace, archive=packed["archive"], output=layout,
                                                    zip_output=workspace / f"{name}.zip"))
        stage("verify", lambda: _lsb.verify_package(layout, game_root=_optional_game_root(None)))
    except _StageFailed as failed:
        return _json({"ran": True, "ok": False, "failed_stage": failed.stage, "stages": stages})
    return _json({"ran": True, "ok": True, "layout": str(layout), "zip": str(workspace / f"{name}.zip"),
                  "next": "build_deploy(layout, apply=true)", "stages": stages})


@mcp.tool()
def vfx_categories() -> str:
    """List the VFX editor's keyword categories (smoke, steam, sparks, holograms, fire, dust, leaks, electrical, weather) and its Particles/Effects backends."""
    return _json(_send("vfx_categories"))


@mcp.tool()
def vfx_search(query: str = "", category: str = "all", backend: str = "all", limit: int = 80,
               refresh: bool = False) -> str:
    """Search World Builder's loaded Particles (worldStaticParticleNode) and Effects (worldEffectNode) catalogs.

    category is a keyword filter from vfx_categories (or 'other'); backend is particle, effect, or all.
    Every returned path is a real catalog row; pass it unchanged as resource_path to vfx_create/vfx_preview.
    """
    if backend not in {"all", "particle", "effect"}:
        raise ValueError("backend must be all, particle, or effect")
    return _json(_send("vfx_search", {"query": query, "category": category, "backend": backend,
                                      "limit": limit, "refresh": refresh}))


def _vfx_args(resource_path: str, query: str, category: str, backend: str, source: str,
              x: float | None, y: float | None, z: float | None, roll: float | None, pitch: float | None,
              yaw: float | None, scale: float | None, scale_x: float | None, scale_y: float | None,
              scale_z: float | None, emission_rate: float | None, respawn_on_move: bool | None,
              align_to_surface: bool | None, distance: float | None) -> dict[str, Any]:
    if source not in {"aim", "player", "origin"}:
        raise ValueError("source must be aim, player, or origin")
    if backend not in {"", "all", "particle", "effect"}:
        raise ValueError("backend must be particle, effect, or empty")
    args: dict[str, Any] = {"resource_path": resource_path or None, "query": query, "category": category or None,
                            "backend": backend or None, "source": source}
    for key, value in (("roll", roll), ("pitch", pitch), ("yaw", yaw), ("emission_rate", emission_rate),
                       ("respawn_on_move", respawn_on_move), ("align_to_surface", align_to_surface),
                       ("distance", distance)):
        if value is not None:
            args[key] = value
    axes = (scale_x, scale_y, scale_z)
    if any(v is not None for v in axes):
        if any(v is None for v in axes):
            raise ValueError("scale_x, scale_y, and scale_z must be supplied together")
        args["scale"] = {"x": scale_x, "y": scale_y, "z": scale_z}
    elif scale is not None:
        args["scale"] = scale
    if any(v is not None for v in (x, y, z)):
        if any(v is None for v in (x, y, z)):
            raise ValueError("x, y, and z must be supplied together")
        args["transform"] = {"position": {"x": x, "y": y, "z": z, "w": 1},
                             "rotation": {"roll": roll or 0, "pitch": pitch or 0, "yaw": yaw or 0}}
    return args


@mcp.tool()
def vfx_create(resource_path: str = "", query: str = "", category: str = "", backend: str = "", name: str = "",
               source: str = "aim", x: float | None = None, y: float | None = None, z: float | None = None,
               roll: float | None = None, pitch: float | None = None, yaw: float | None = None,
               scale: float | None = None, scale_x: float | None = None, scale_y: float | None = None,
               scale_z: float | None = None, emission_rate: float | None = None, respawn_on_move: bool | None = None,
               align_to_surface: bool = False, distance: float = 10.0, room_id: str = "", premise_id: str = "",
               spawn: bool = True) -> str:
    """Save and spawn a World Builder particle/effect node (smoke, steam, sparks, holograms, fire, dust, leaks...).

    Prefer an exact resource_path from vfx_search; otherwise query/category picks the first match.
    Orientation is roll/pitch/yaw in degrees (align_to_surface points the up axis along the aimed normal).
    Scale (0.01-100, uniform or per-axis) is saved and written to the native node by build_mod_from_project;
    World Builder's live preview stays 1:1. emission_rate/respawn_on_move apply to particles only.
    """
    args = _vfx_args(resource_path, query, category, backend, source, x, y, z, roll, pitch, yaw, scale,
                     scale_x, scale_y, scale_z, emission_rate, respawn_on_move, align_to_surface, distance)
    args.update({"name": name, "room_id": room_id or None, "premise_id": premise_id or None, "spawn": spawn})
    return _json(_send("vfx_create", args))


@mcp.tool()
def vfx_update(object_id: str, resource_path: str = "", roll: float | None = None, pitch: float | None = None,
               yaw: float | None = None, scale: float | None = None, scale_x: float | None = None,
               scale_y: float | None = None, scale_z: float | None = None, emission_rate: float | None = None,
               respawn_on_move: bool | None = None) -> str:
    """Edit a saved VFX object. Rotation and particle emission update the live node when possible; a resource swap respawns it."""
    patch: dict[str, Any] = {}
    if resource_path:
        patch["resource_path"] = resource_path
    for key, value in (("roll", roll), ("pitch", pitch), ("yaw", yaw), ("emission_rate", emission_rate),
                       ("respawn_on_move", respawn_on_move)):
        if value is not None:
            patch[key] = value
    axes = (scale_x, scale_y, scale_z)
    if any(v is not None for v in axes):
        if any(v is None for v in axes):
            raise ValueError("scale_x, scale_y, and scale_z must be supplied together")
        patch["scale"] = {"x": scale_x, "y": scale_y, "z": scale_z}
    elif scale is not None:
        patch["scale"] = scale
    return _json(_send("vfx_update", {"object_id": object_id, "patch": patch}))


@mcp.tool()
def vfx_list(premise_id: str = "", category: str = "") -> str:
    """List saved VFX objects with backend, category, resource path, transform, scale and live spawn state."""
    return _json(_send("vfx_list", {"premise_id": premise_id or None, "category": category or None}))


@mcp.tool()
def vfx_preview(resource_path: str = "", query: str = "", category: str = "", backend: str = "",
                source: str = "aim", follow: bool | None = None, update: bool = False,
                x: float | None = None, y: float | None = None, z: float | None = None,
                roll: float | None = None, pitch: float | None = None, yaw: float | None = None,
                scale: float | None = None, emission_rate: float | None = None, respawn_on_move: bool | None = None,
                align_to_surface: bool | None = None, distance: float | None = None) -> str:
    """Spawn (or with update=true, adjust) one temporary live VFX preview. It is never saved; it follows the aim point unless follow=false.

    With update=true only the arguments you pass change; omitted follow/alignment/distance keep their current values.

    Call vfx_preview_commit to save it as a placed effect or vfx_preview_clear to remove it.
    """
    args = _vfx_args(resource_path, query, category, backend, source, x, y, z, roll, pitch, yaw, scale,
                     None, None, None, emission_rate, respawn_on_move, align_to_surface, distance)
    args["update"] = update
    if follow is not None:
        args["follow"] = follow
    return _json(_send("vfx_preview", args))


@mcp.tool()
def vfx_preview_status() -> str:
    """Report the live VFX preview: resource, transform, follow state and settings."""
    return _json(_send("vfx_preview_status"))


@mcp.tool()
def vfx_preview_commit(name: str = "", scale: float | None = None, room_id: str = "", premise_id: str = "") -> str:
    """Save the current VFX preview at its current transform as one undoable placed effect."""
    args: dict[str, Any] = {"name": name, "room_id": room_id or None, "premise_id": premise_id or None}
    if scale is not None:
        args["scale"] = scale
    return _json(_send("vfx_preview_commit", args))


@mcp.tool()
def vfx_preview_clear() -> str:
    """Remove the temporary VFX preview without saving anything."""
    return _json(_send("vfx_preview_clear"))


@mcp.tool()
def vfx_export_apply(export_file: str, write: bool = False) -> str:
    """Offline: match saved VFX objects to a World Builder export and report (write=false) or write (write=true) their authored node scale.

    build_mod_from_project already does this on its workspace copy; use this for a manual WolvenKit import.
    """
    return _json(_lsvfx.apply(PROJECT, _export_file(export_file), write=write))


# ---------------------------------------------------------------------------
# Offline vanilla asset catalog (vendored cp77wb assets/semantics in lsassets/).
# Built from World Builder's data/spawnables, so every hit is a resource WB can
# spawn. import_catalog_asset turns a hit into a project asset via WB's live
# catalog entry.
# ---------------------------------------------------------------------------

from lsassets import assets as _lsa, semantics as _lss  # noqa: E402
from wbfavorites import add_favorite as _wb_favorite_add, list_favorites as _wb_favorites_list  # noqa: E402

ASSET_DB = Path(os.environ.get("LOCATION_STUDIO_ASSET_DB", DATA_DIR / "asset-catalog.sqlite3")).expanduser()


def _catalog_id(catalog_id: int | str) -> int:
    text = str(catalog_id).lstrip("#")
    if not text.isdigit():
        raise ValueError(f"catalog_id must be a number such as 78987 or #78987, got {catalog_id!r}")
    return int(text)


def _require_catalog() -> Path:
    if not ASSET_DB.is_file():
        raise FileNotFoundError(f"Asset catalog not built yet ({ASSET_DB}); run asset_catalog_build first.")
    return ASSET_DB


def _hit(result: Any) -> dict[str, Any]:
    out = result.to_dict()
    out["has_template"] = out.pop("template") is not None
    return out


@mcp.tool()
def asset_catalog_build(world_builder_root: str | None = None) -> str:
    """Offline: (re)build the vanilla asset index from World Builder's data/spawnables (~360k entries, ~30 s).

    Rebuild after updating World Builder. Run asset_semantic_build afterwards for semantic search.
    """
    root = Path(world_builder_root).expanduser() if world_builder_root else WORLD_BUILDER_ROOT
    ASSET_DB.parent.mkdir(parents=True, exist_ok=True)
    return _json(_lsa.build_catalog(root, ASSET_DB))


@mcp.tool()
def asset_catalog_info() -> str:
    """Offline: catalog size, per-category counts, source World Builder root and whether FTS5 is available."""
    return _json(_lsa.catalog_info(_require_catalog()))


@mcp.tool()
def asset_catalog_search(query: str, category: str | None = None, variant: str | None = None,
                         module_path: str | None = None, extension: str | None = None, limit: int = 25) -> str:
    """Offline keyword search over vanilla resources (depot path/name full-text; all terms first, then any).

    Filters: category (Mesh, Entity, Deco, Lighting, AI, ...), variant (Mesh, Template, Device, Particles, ...),
    module_path (mesh/mesh, entity/entityTemplate, ...), extension (mesh, ent, particle, ...).
    Pass a hit's id to import_catalog_asset to place it.
    """
    hits = _lsa.search_catalog(_require_catalog(), query, category=category, variant=variant,
                               module_path=module_path, extension=extension, limit=limit)
    return _json({"count": len(hits), "results": [_hit(h) for h in hits]})


@mcp.tool()
def asset_catalog_get(catalog_id: str) -> str:
    """Offline: one catalog record by id (e.g. 78987 or #78987), including any JSON template payload."""
    return _json(_lsa.get_asset(_require_catalog(), _catalog_id(catalog_id)).to_dict())


@mcp.tool()
def asset_semantic_build(overrides: str | None = None) -> str:
    """Offline: derive role/style/material/condition tags for every catalog entry (~40 s).

    overrides: optional JSON file {"overrides":[{"asset":"#id","tags":[...],"roles":[...],...}]}.
    """
    return _json(_lss.build_semantic_index(_require_catalog(), overrides))


@mcp.tool()
def asset_semantic_search(query: str, role: str | None = None, style: str | None = None,
                          material: str | None = None, condition: str | None = None, category: str | None = None,
                          variant: str | None = None, limit: int = 25) -> str:
    """Offline semantic search: free text plus coarse facets derived from depot-path words.

    Facets are fixed vocabularies, e.g. role=furniture (chairs, tables...), light
    (lamps, neon), container, wall, door, vehicle; condition=rusty/dirty/damaged;
    material=metal/wood/concrete; style=industrial/corpo/arasaka. Put the specific
    object in `query` ("chair") and the class in `role`. An unknown facet value is
    rejected with the valid list. Treat hits as candidates and check them.
    """
    for facet, value in (("roles", role), ("styles", style), ("materials", material), ("conditions", condition)):
        allowed = sorted(_lss.TAXONOMY[facet])
        if value and value.lower() not in allowed:
            raise ValueError(f"Unknown {facet[:-1]} {value!r}; valid values: {', '.join(allowed)}")
    hits = _lss.semantic_search(_require_catalog(), query, role=role, style=style, material=material,
                                condition=condition, category=category, variant=variant, limit=limit)
    return _json({"count": len(hits), "results": hits})


@mcp.tool()
def import_catalog_asset(catalog_id: str) -> str:
    """Live: register a catalog hit as a Project Asset, resolved against World Builder's loaded catalog.

    Returns the project asset (use its id with place_registered_asset, start_placement_edit or plans).
    Re-importing returns the existing asset.
    """
    record = _lsa.get_asset(_require_catalog(), _catalog_id(catalog_id))
    payload = {k: getattr(record, k) for k in ("category", "variant", "module_path", "spawn_data", "name", "file_name")}
    result = _send("import_catalog_asset", {"record": payload}, timeout=30.0)
    result["catalog_id"] = record.id
    return _json(result)


def _world_builder_favorites_dir() -> Path:
    # Resolve only the known World Builder mod directory names beside
    # LocationStudio; never accept a user-supplied output path.
    mods = MOD_DIR.parent
    candidates = [(mods / name / "data" / "favorite").resolve() for name in ("entSpawner", "WorldBuilder")]
    present = [path for path in candidates if path.is_dir()]
    if len(present) > 1:
        raise RuntimeError("Both entSpawner and WorldBuilder Favorites directories exist; resolve the active install before writing.")
    return present[0] if present else candidates[0]


@mcp.tool()
def wb_favorite_add(catalog_id: str, category: str = "LocationStudio", name: str = "", tags: list[str] | None = None, write: bool = False) -> str:
    """Preview a native World Builder favorite; set write=true to save it.

    The catalog hit must resolve against World Builder's live resource catalog.
    Writes target entSpawner/data/favorite, preserve unknown category fields,
    create a timestamped backup when updating a file, and use an atomic replace.
    """
    record = _lsa.get_asset(_require_catalog(), _catalog_id(catalog_id))
    payload = {k: getattr(record, k) for k in ("category", "variant", "module_path", "spawn_data", "name", "file_name")}
    favorite = _send("wb_favorite_prepare", {"record": payload, "name": name}, timeout=30.0)
    favorite["name"] = str(name or favorite.get("name") or record.name).strip()
    favorite["tags"] = {str(tag).strip(): True for tag in (tags or []) if str(tag).strip()}
    result = _wb_favorite_add(_world_builder_favorites_dir(), category, favorite, write=write)
    result["catalog_id"] = record.id
    result["live_resource"] = favorite.get("resource")
    return _json(result)


@mcp.tool()
def wb_favorites_list(category_filter: str = "") -> str:
    """List native World Builder Favorites categories and entries on disk."""
    return _json(_wb_favorites_list(_world_builder_favorites_dir(), category_filter))


@mcp.tool()
def get_history(limit: int = 20) -> str:
    """Live: project undo/redo history, newest first, with labels and per-collection added/removed/changed counts.

    Covers every committed edit: UI, MCP, authoring plans, transform/stamp
    sessions, World Builder gizmo moves and imports. `undo[0]` is what `undo`
    reverts next.
    """
    return _json(_send("get_history", {"limit": limit}))


@mcp.tool()
def undo(steps: int = 1) -> str:
    """Live: undo `steps` project changes. Live objects are despawned, the state restored, then respawned.

    Refused while a transform/stamp session or plan recovery is active. Check
    get_history first when undoing more than one step.
    """
    return _json(_send("history_undo", {"steps": steps}, timeout=30.0))


@mcp.tool()
def redo(steps: int = 1) -> str:
    """Live: redo `steps` previously undone project changes (same runtime handling as undo)."""
    return _json(_send("history_redo", {"steps": steps}, timeout=30.0))


@mcp.tool()
def create_project_checkpoint(name: str, description: str = "") -> str:
    """Save the current LocationStudio project data as a named, immutable checkpoint."""
    return _json(_send("checkpoint_create", {"name": name, "description": description}, timeout=30.0))


@mcp.tool()
def list_project_checkpoints() -> str:
    """List saved project checkpoints, newest/oldest in creation order."""
    return _json(_send("checkpoint_list", {}, timeout=30.0))


@mcp.tool()
def diff_project_checkpoints(checkpoint_a: str, checkpoint_b: str) -> str:
    """Compare two checkpoint IDs. Reports added, removed, moved, and changed objects plus other collection changes."""
    return _json(_send("checkpoint_diff", {"checkpoint_a": checkpoint_a, "checkpoint_b": checkpoint_b}, timeout=30.0))


@mcp.tool()
def restore_project_checkpoint(checkpoint_id: str) -> str:
    """Restore saved authoring data from a checkpoint. The operation is undoable; already spawned game entities are not automatically removed or respawned."""
    return _json(_send("checkpoint_restore", {"checkpoint_id": checkpoint_id}, timeout=30.0))


@mcp.tool()
def get_runtime_sync_status() -> str:
    """Compare current project objects with tracked spawned game entities; returns required removals and updates without changing the game."""
    return _json(_send("get_runtime_sync_status", {}, timeout=30.0))


@mcp.tool()
def sync_runtime() -> str:
    """Apply the current project transforms/resources to tracked spawned entities, remove tracked entities missing or disabled in the project, and respawn changed resources."""
    return _json(_send("sync_runtime", {}, timeout=60.0))


def _saved_build_file(name_or_path: str) -> Path:
    p = Path(name_or_path).expanduser()
    if p.suffix == ".json":
        return p
    return WORLD_BUILDER_ROOT / "data" / "objects" / f"{name_or_path}.json"


def _count_saved_build(node: dict[str, Any]) -> tuple[int, int]:
    if isinstance(node.get("spawnable"), dict):
        return 1, 0
    objects, groups = 0, 1
    for child in node.get("childs") or []:
        if isinstance(child, dict):
            o, g = _count_saved_build(child)
            objects, groups = objects + o, groups + g
    return objects, groups


@mcp.tool()
def list_world_builder_builds() -> str:
    """Offline: list World Builder/cp77wb saved builds in entSpawner/data/objects with object/group counts."""
    folder = WORLD_BUILDER_ROOT / "data" / "objects"
    builds = []
    for path in sorted(folder.glob("*.json")) if folder.is_dir() else []:
        try:
            data = json.loads(path.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            data = None
        if not isinstance(data, dict):
            builds.append({"name": path.stem, "file": str(path), "error": "not a JSON object"})
            continue
        objects, groups = _count_saved_build(data)
        legacy = "modulePath" not in data and ("type" in data or "path" in data)
        builds.append({"name": path.stem, "file": str(path), "objects": objects, "groups": groups, "legacy": legacy})
    return _json({"folder": str(folder), "builds": builds})


@mcp.tool()
def import_world_builder_build(
    build: str,
    premise_id: str | None = None,
    premise_name: str | None = None,
    apply: bool = False,
    spawn: bool = False,
    allow_skipped: bool = False,
    allow_duplicate: bool = False,
) -> str:
    """Live: migrate a World Builder/cp77wb saved build into the LS project as one undoable change.

    `build` is a saved-build name in entSpawner/data/objects or a .json path.
    apply=false (default) only reports what would be imported. WB groups become
    LS object groups under a new premise (or premise_id); objects keep their full
    WB spawnable data. spawn=true also spawns them; do not spawn a build that is
    still loaded in World Builder, or it will be doubled.
    """
    path = _saved_build_file(build)
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        raise FileNotFoundError(f"Saved build not found: {path}") from None
    args: dict[str, Any] = {"build": data, "source": path.stem, "premise_id": premise_id, "premise_name": premise_name,
                            "dry_run": not apply, "spawn": spawn, "allow_skipped": allow_skipped,
                            "allow_duplicate": allow_duplicate}
    result = _send("import_world_builder_build", {k: v for k, v in args.items() if v is not None}, timeout=60.0)
    result["file"] = str(path)
    return _json(result)


class _StageFailed(Exception):
    def __init__(self, stage: str):
        super().__init__(stage)
        self.stage = stage


if __name__ == "__main__":
    if not MOD_DIR.exists():
        print(f"LocationStudio mod directory does not exist: {MOD_DIR}", file=sys.stderr)
        raise SystemExit(2)
    BRIDGE_DIR.mkdir(parents=True, exist_ok=True)
    mcp.run("stdio")
