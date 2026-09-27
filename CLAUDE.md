# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in this repository.

## Repository purpose

LocationStudio v0.28.0 is a Cyberpunk 2077 in-game location editor implemented as a Cyber Engine Tweaks (CET) Lua mod. It authors locations, premises, game-asset room kits, placed objects, gameplay volumes, cameras, routes, persistent groups, prefabs, and scenes. It can materialize those authored records through CET's entity spawner or World Builder 1.0.81, and exposes the same operations through a file-backed MCP bridge.

The repository is a distributable source tree rather than a conventional standalone application. Most production code is under `bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/`; root documentation, isolated tests, and release tooling surround it.

## Commands

Run commands from the repository root.

### Lua test suites

The test runner requires the optional Python `lupa` package and runs every Lua file through an isolated temporary copy of the mod. It also performs a `loadfile` syntax check over all mod Lua files before running suites.

```sh
# Run all suites on LuaJIT 2.1 (default runtime)
python3 tests/run_tests.py --runtime luajit21

# Run all suites on Lua 5.1
python3 tests/run_tests.py --runtime lua51

# Run one suite; pass the filename relative to tests/
python3 tests/run_tests.py --runtime luajit21 scene_director_runtime_test.lua
python3 tests/run_tests.py --runtime lua51 storage_safety_test.lua
```

The runner accepts multiple test filenames after the runtime option. Do not pass `tests/foo.lua`; pass `foo.lua`, because the runner prefixes the argument with the repository's `tests/` directory.

### MCP bridge contract check

```sh
python3 bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/mcp_server/test_bridge.py
```

The MCP server itself is intended to run from the installed mod directory while Cyberpunk 2077 and CET are running. Install the Python dependencies from `mcp_server/requirements.txt` first, then use either the helper or the server directly:

```sh
cd bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio
./mcp_server/claude-add.sh
# or, for a direct stdio server invocation:
python3 mcp_server/server.py
```

The bridge is live only when the game has initialized the mod and is updating `bridge/status.json`. Use the MCP `get_status` operation before any live mutation.

### Release archives

Build release ZIPs into a directory outside the source tree. The builder creates upgrade-safe, source, and direct-mod-folder archives plus SHA-256 checksums, and rejects mutable project/runtime files.

```sh
python3 tools/build_release.py /tmp/locationstudio-release
```

There is no separate repository-wide formatter or linter. The Lua syntax pass in `tests/run_tests.py`, the isolated runtime suites, `test_bridge.py`, and the archive self-checks are the available automated validation.

## High-level architecture

### Runtime bootstrap and lifecycle

`bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/init.lua` is the composition root. It creates the logger first, safely requires the production modules, constructs the storage/model/runtime services in dependency order, registers CET events and hotkeys, and exposes a diagnostic fallback UI if initialization or the full editor fails.

The important lifecycle callbacks are `onInit`, `onOverlayOpen`, `onOverlayClose`, `onUpdate`, `onDraw`, and `onShutdown`. `onUpdate` polls the bridge, advances placement/preview and transform sessions, updates thumbnails, and autosaves only when no transaction or recovery gate is active. Closing the overlay and shutting down deliberately cancel unfinished transform or stamp sessions before cleanup.

When changing module initialization, event handling, or hotkeys, preserve the guarded callback/logger behavior. A failure should leave the safe diagnostics window usable rather than preventing all feedback from appearing.

### Authoring model and persistence

`modules/model.lua` is the in-memory project authority. It normalizes and migrates records into schema version 13 and owns the collections for locations, routes, premises, rooms, objects, object groups, prefabs, volumes, cameras, scenes, assets, layers, and settings. It also supplies IDs, validation, relationship cleanup, snapshots, undo/redo, and mutation helpers.

`modules/storage.lua` loads/saves `data/project.json` and `data/config.json`, performs staged/safer writes, and exports JSON, CSV, Lua, World Builder, and QuestForge representations. Runtime-owned mutable directories (`data`, `logs`, `bridge`, `exports`, and `thumbnails`) are intentionally excluded from upgrade-safe packages.

Treat model records as authored state, not proof that a live game object exists. Runtime fields and diagnostics distinguish saved ownership from actual CET/World Builder spawn state; a `spawn_error` is a runtime warning and does not necessarily mean the authored record was discarded.

### Runtime adapters and action orchestration

The mod has two important live backends:

- World Builder handles imported game resources such as static meshes, lights, collision, areas, and other catalog entries. These retain World Builder resource/class metadata and can generally update their handles in place.
- CET's entity spawner handles direct `.ent` templates. These objects use a guarded spawn/despawn/refresh path and often respawn on committed transform changes; live scale is not claimed where CET cannot support it.

`modules/game.lua` wraps player/camera/raycast/teleport operations. `modules/integrations.lua` discovers optional integrations. `modules/world_builder.lua` adapts the loaded World Builder catalog/API without importing private modules from another mod. `modules/runtime_shell.lua`, `placement.lua`, `builder.lua`, and `room_kits.lua` coordinate room construction and runtime spawning. `modules/authoring.lua` and `modules/actions.lua` provide higher-level mutations used by both UI and bridge operations.

Do not invent depot `.ent` paths, fake World Builder classes, or restore the legacy `base\\spawner\\cube.mesh` room fallback. Room shells must use configured game-asset room-kit resources; collision objects are intentionally invisible. When a room-kit piece must survive a rebuild, detach it before customization.

### Transactional editing

`modules/transform_session.lua` is the shared transaction engine for reversible grab moves, transform edits, duplicate-and-edit, placement-and-edit, linear patterns, mirrors, and scatter. `modules/stamp_session.lua` handles repeated asset stamping. These sessions create/update real runtime objects while preserving a session-start snapshot, prior selection, dirty state, and ownership. Commit creates the intended single undo operation; cancel removes/restores the complete transaction.

While a transaction is active, save/export/history and unrelated mutations are intentionally rejected. If backend removal fails, keep the transaction and authored ownership active; do not delete project records or reload the mod to hide the problem. The same recovery principle applies to failed authoring-plan rollback.

`modules/selection.lua` is the shared selection authority. It synchronizes LocationStudio selection with World Builder selection where supported. `modules/assemblies.lua` implements persistent groups/prefabs and their pivot/layout rules. `modules/viewport_tools.lua` owns camera-ray object picking, surface alignment, and aim/stamp support. `modules/ent_tools.lua` implements the higher-level transform/look-at/ground/duplicate/scatter tools.

### Scenes and declarative plans

`modules/scenes.lua` implements schema-13 scene collections. Scenes reference existing rooms, objects, locations, volumes, cameras, and routes; they do not duplicate members. Scene capture can derive room/object/spatial membership from a premise while preserving manually added semantic location/route membership. Activation and isolation spawn/despawn through real backends; deactivation retains scene data and refuses deletion when cleanup cannot be confirmed.

`modules/authoring_plans.lua` implements declarative JSON plans. Plans are validated before mutation, support backward-only `$alias` references, player/camera/explicit origins, asset resolution, scene operations, and a 100-step limit. Successful execution is one undoable change. Failed execution rolls back model/history/selection/dirty/runtime state; if runtime cleanup is refused, the project enters `recovery_required` and unrelated operations remain blocked until retry-rollback or an explicit keep-partial decision.

For complex authoring workflows, prefer a single validated plan over a long sequence of independent mutations. The plan format and examples are documented in `AUTHORING-PLANS.md` and `examples/`.

### UI and diagnostics

`ui/editor.lua` composes the user interface. The main workspaces are BUILD, ASSETS, and SCENE; specialist controls are available through Advanced Tools. UI modules such as `home.lua`, `premises.lua`, `browser.lua`, `hierarchy.lua`, `inspector.lua`, `viewport.lua`, `scene_director.lua`, and `tools.lua` should call the shared action/session/model layers rather than implementing separate mutation semantics.

`modules/logger.lua` provides the append-only rotating runtime log and structured event records. `modules/diagnostics.lua` gathers capability, integration, room-kit, selection, transaction, scene, and plan status. Support reports are written under `logs/`; they avoid project JSON by default but can contain resource paths and transforms. The viewport must remain CET-safe: do not reintroduce raw `GetWindowDrawList()` usage without verifying the exact CET binding.

### MCP file bridge

`mcp_server/server.py` is a Python stdio MCP server with a large tool surface. It reads saved project/status files directly for offline queries and sends one live command at a time through atomic JSON files in `bridge/command.json`, `bridge/response.json`, and `bridge/status.json`. A lock serializes requests, request IDs match responses, and a live-status age check prevents commands from being sent to an offline/stale game process.

The Python tools are thin wrappers around CET operations. Keep validation and authoritative mutation in the Lua mod so UI, hotkeys, authoring plans, and MCP share behavior. When adding a bridge operation, update the Lua bridge dispatch/status implementation, the Python tool wrapper, and bridge/static contract coverage together.

### Tests and what they do not cover

`tests/` contains isolated Lua runtime tests backed by `tests/support/cet_mock.lua` plus Python MCP bridge tests. The runner copies the mod into a temporary directory and creates empty runtime directories, so tests do not read or modify the user's live project. Test mocks validate contracts, rollback, ownership, selection, UI reachability, bridge payloads, and failure paths; they cannot render REDengine meshes, prove collision, or certify actual World Builder behavior in-game.

After changing runtime-facing behavior, run both Lua runtimes and the bridge contract test. For room visuals, pivots, collision, World Builder handles, camera rays, or CET hotkeys, follow `IN-GAME-CHECK.md` in addition to automated tests.

## Operational guidance for future changes

The nested `bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/CLAUDE.md` contains the detailed live-authoring/MCP rules and is authoritative for plan-first workflows, asset resolution, scene lifecycle, transaction completion, recovery handling, and backend limitations. Read it before changing or exercising live MCP behavior.

Before live operations, obtain status and diagnostics as appropriate. For failures, inspect `get_debug_log` and `get_diagnostics` before attempting repair. Never bypass the recovery gate, silently claim approximate aim as an exact raycast, or use arbitrary Lua execution.

The repository contains no `.cursor/rules/`, `.cursorrules`, or `.github/copilot-instructions.md` files. The root README, `FIRST-RUN.md`, `AUTHORING-PLANS.md`, `MCP-EXAMPLES.md`, `TROUBLESHOOTING.md`, and `IN-GAME-CHECK.md` are the primary project documentation.
