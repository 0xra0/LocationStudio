## 0.61.0 - 2026-09-27

- Added a streaming-sector inspector (`lsbuild/sectors.py`) for World Builder exports. Per node it reports sector, variant range, NodeRef, position/streaming reference point, ranges, device/PSID and referenced NodeRefs, and maps nodes back to LocationStudio objects. Per sector it reports bounds, category, level, node types and NodeRef/device/persistent-entry counts.
- Automatic flags: likely wrong sector (outside own box and inside another; far outlier from the sector's content, with a suggested sector), outside bounds, streaming reference point outside the sector, beyond streaming range, missing position, duplicate PSIDs and devices without a node. Cross-sector NodeRef and device references are listed with `cross_sector`/`external_or_missing`/`missing_device` status, along with premises split across sectors. The export is never modified.
- Added MCP tools `sector_inspect` and `sector_node`, an advisory `sectors` stage in Build Mod, and a Spatial → Sectors tab that reads `exports/sector-inspection.json` and selects flagged objects. Added `SECTOR-INSPECTOR.md` and Python/Lua tests. Bumped to v0.61.0.

## 0.60.0 - 2026-09-27

- Added collision authoring (`modules/collision.lua`, Spatial → Collision). It places World Builder `worldCollisionNode` box/capsule/sphere primitives, imports collision resources from World Builder's Collision Mesh catalog, and fits box colliders to a placed object's imported bounds. Shape, dimensions, layer, material, visualization and rotation are editable and undoable; live colliders respawn.
- Collision layers use World Builder's 59 presets with its physics-group hints; presets and materials are stored as the indices World Builder's collider class reads. Room-kit colliders are included in lists, layers and passability.
- Added visualization toggles for colliders, premises or layers, using World Builder's collider wireframe (`previewed`).
- Added a player/NPC passability preview from saved colliders. It returns a text map, blocking colliders and per-actor 8-neighbour routes, handles yaw-oriented boxes (conservative bounds for roll/pitch) and head/step height, and can cross-check with the live collision-ray walkability scan.
- Added MCP tools `collision_presets`, `collision_create_primitive`, `collision_search_meshes`, `collision_import_mesh`, `collision_fit_to_object`, `collision_update`, `collision_list`, `collision_layers`, `collision_visualization` and `collision_passability`, plus `COLLISION-AUTHORING.md` and runtime/UI/bridge/MCP tests. Bumped to v0.60.0.

## 0.59.0 - 2026-09-27

- Added deterministic screenshot mode (`modules/screenshot_mode.lua`). It records and then overrides configurable CET settings ConfigVars: HUD elements under `/interface/hud`, and motion blur/film grain/chromatic aberration/depth of field/lens flares under `/graphics/basic`. List settings fall back to `SetIndex`. Settings missing from the running build, or refusing a write, are reported and left alone.
- A near-zero named time dilation freezes NPCs, traffic and particles only while shooting. A streaming-readiness probe requires consecutive static-collision hits below the camera.
- Restore unfreezes, writes back every recorded value, and restores a forced environment. A failed restore keeps only the unrestored settings for a safe retry, and the restore record survives CET reloads.
- `visual_regression_capture(deterministic=true, …)` / `hotcycle_rebuild(visual_deterministic=true)` enter the mode (optionally with an environment) and wait for streaming per camera. They freeze, shoot until two consecutive frames agree within `stability_limit`, unfreeze, and always restore. Streaming timeouts and unstable frames mark the camera as not captured; the manifest and accepted baseline record the mode and flag `screenshot_mode_mismatch`.
- Added Spatial → Environment screenshot-mode controls, MCP tools `screenshot_mode_capabilities/status/enter/freeze/restore`, and runtime, UI, bridge and capture-sequence tests. Bumped to v0.59.0.

## 0.58.0 - 2026-09-27

- Added saved authoring environments (project schema 17, `environments`) with time, weather state (which determines rain), weather blend/priority, an optional World Builder Fog Volume (size, density, falloff, absorption, color; player/camera/premise anchor) and an exposure note.
- Added Spatial → Environment: create, capture current conditions, edit, preview, force (re-apply clock every 1 s and weather every 2 s when the game changes them), and restore. Restore sets the exact pre-preview game time, calls `ResetWeather` to return to the game cycle, and removes the fog volume; the restore point survives CET reloads and a failed restore is retryable.
- Exposure and independent rain intensity are not applied: CET exposes no verified setter. Live rain intensity is reported read-only when available.
- The Lighting time preview is refused while an environment preview is active, and an in-progress lighting time preview is taken over so restore returns to the true original time. Deleting a premise unlinks its environments instead of removing them.
- `visual_regression_capture` / `hotcycle_rebuild` accept an environment, force it for the whole shot series, restore afterwards, record it in the manifest and accepted baseline, and flag `environment_mismatch`.
- Added MCP tools `environment_weather_states`, `environment_list`, `environment_create`, `environment_update`, `environment_delete`, `environment_preview`, `environment_force`, `environment_status`, `environment_restore`, plus `ENVIRONMENT-PREVIEW.md` and mocked runtime/UI/bridge/MCP tests. Updated the static bridge test to the current schema and tool count. Bumped to v0.58.0.

## 0.57.0 - 2026-09-27

- Added a VFX / particle editor (Spatial → VFX) that searches World Builder's loaded Particles (`worldStaticParticleNode`) and Effects (`worldEffectNode`) catalogs, with keyword categories for smoke, steam, sparks, holograms, fire, dust, leaks, electrical and weather effects. Paths outside the loaded catalogs are rejected.
- Added a transient live preview that follows the aim point (optionally aligned to the hit surface), can be pinned and re-tuned, and commits as one undoable placed object. It is never saved and is cleared when the overlay closes or the mod reloads.
- Placed effects store roll/pitch/yaw, per-axis scale (0.01–100), and particle emission rate/respawn-on-move. Rotation and emission edits update the live node where World Builder exposes it; otherwise the node respawns.
- World Builder previews and exports these nodes at 1:1, so the new Build Mod `vfx` stage matches saved effects to exported nodes by resource and position and writes their scale into the workspace export copy. The stage fails on ambiguous matches, invalid scale, or emission mismatches.
- Added MCP tools `vfx_categories`, `vfx_search`, `vfx_create`, `vfx_update`, `vfx_list`, `vfx_preview`, `vfx_preview_status`, `vfx_preview_commit`, `vfx_preview_clear`, and `vfx_export_apply`, plus `VFX.md`, mocked runtime/UI/bridge tests and export-patching tests. Bumped mod version to v0.57.0.

## 0.56.0 - 2026-09-27

- Added persistent named world-state variants with one or more live quest-fact predicates, comparison operators, per-object show/hide memberships, priority conflict checks, previews, manual apply, and opt-in automatic fact polling.
- Applying a state uses LocationStudio's tracked spawn/despawn backend for placed game objects (including object-backed props, NPCs, lights, doors, decals, audio/effects), preserving each object's baseline enabled/visible/tracked state for fallback and rule removal. Apply is blocked during active transform/stamp/recovery sessions.
- Added spatial editor controls, MCP CRUD/preview/apply/auto-switch tools, validation, object-delete cascades, and Quest Forge handoff metadata. Native REDengine quest conditions and persistent world-state resources are not generated.
- Added mocked runtime tests for fact evaluation, scene switching, priority conflicts, automatic updates, bridge, and UI; bumped project schema to 16 and mod version to v0.56.0.

## 0.55.0 - 2026-09-27

- Added a Quest Debug panel that reads live `GetFactStr` values and maps authored trigger/interactable writers, condition readers, combat facts, route branches and device-logic references.
- Added staged set/reset and trigger-fact simulation. Every write requires confirmation with a one-time token after an active-save warning. No write happens during preview or preparation.
- Added MCP read, prepare, confirm and cancel tools. Trigger simulation explicitly writes its configured fact with `SetFactStr`; it does not dispatch a native volume collision/event. LocationStudio cannot roll back a changed game fact.
- Added mocked runtime regression checks for read-only inspection, mapping, persistent-write staging, confirmation, cancellation and trigger preparation; bumped to v0.55.0.

## 0.54.0 - 2026-09-27

- Added Quest Forge round-trip preview/import by stable LocationStudio IDs and previously imported NodeRefs. Matched local records receive linked NodeRef, manifest key, quest facts, and external-coordinate conflict metadata; local notes, names, and transforms are preserved by default.
- Added explicit opt-in coordinate application, inspector display for linked Quest Forge nodes/facts, editor preview/update controls, and MCP tools `questforge_sync_preview`, `questforge_sync_apply`, and `questforge_links`.
- Quest Forge export reuses imported manifest keys/NodeRefs and retains imported trigger facts. Unmatched nodes are reported and never auto-created; matching is exact to avoid accidental merges.
- Added round-trip tests for exact identity, local-edit preservation, facts, position conflict reporting, and explicit coordinate updates; bumped to v0.54.0.

## 0.53.0 - 2026-09-27

- Added persistent Device Logic graphs and a spatial editor node/link panel for terminals, doors, elevators, switches, cameras, security systems, quest facts, and actions.
- Added MCP graph/node/link CRUD, validation, handoff export, and validation-first `wb_device_logic_apply` to write reciprocal links into an existing World Builder export.
- Added native readiness audit for device class, sector NodeRef, persistent-state PSID/typed instanceData and exported reciprocal links. Validation-first WB apply can add missing resources only from complete typed payloads supplied from compatible presets; it never fabricates class-specific instanceData or claims fact/action execution in REDengine.
- Added `DEVICE-LOGIC.md` and mocked authoring, wire-application, and native-manifest tests; bumped to v0.53.0.

## 0.52.0 - 2026-09-27

- Added imported navigation graphs with validation, node/link and surface-polygon display, weighted graph reachability, typed door/stair/elevator/off-mesh transitions, and NPC workspot reports in the Navigation tab.
- Added MCP tools `navigation_graph_import`, `navigation_graph_list`, `navigation_graph_check`, and `navigation_workspot_report`.
- Imported graph status is explicitly separated from the existing collision-grid estimate. No native REDengine navmesh read/query is claimed: raw `.navmesh`/`.navdata` decoding and live engine AI pathfinding are not implemented.
- Added `NAVIGATION.md` and mock-runtime regression coverage; bumped to v0.52.0.

## 0.51.0 - 2026-09-27

- Added persistent cover nodes to the project model, with crouch/standing posture, facing yaw, exposure label, preferred spacing, provenance, validation, undo, delete cascades, and Quest Forge handoff.
- Added paired Static/Dynamic horizontal ray scans around V (or an explicit MCP center) to return wall/prop cover candidates. In-game Spatial Editor supports review, distance filtering, and importing candidates; existing marker template can visualize saved nodes.
- Added MCP tools `cover_node_create/list/update/delete` and `cover_scan`; scene view and Inspector selection support cover transforms.
- The scanner is a geometric candidate finder only. It does not query AI cover/navmesh, infer exposure, or create native REDengine cover records.
- Added `COVER-NODES.md`, scan/action/export/UI regression coverage, and bumped to v0.51.0.

## 0.50.0 - 2026-09-27

- Added persistent Combat Encounters with linked combat-area/trigger volumes, enemy groups built from saved NPC population IDs, faction/attitude relations, and immediate/volume/fact/after-wave reinforcement conditions.
- Added temporary wave/encounter test spawning through the existing CET/Codeware Character-record spawner and a reset action that removes the encounter's tagged entities. Test is capped at 64 NPCs and does not execute AI/quest logic.
- Added in-game Spatial editor controls, MCP CRUD/test/reset tools, and Quest Forge `combat_encounters` export with reference validation. Removing an NPC cleans it out of encounter groups and wave membership.
- Quest fact activation/reset, volume-trigger behavior, reinforcement scheduling, faction reactions, pathfinding, and persistent combat execution remain handoff-only; no unverified native guard/community/quest resources are claimed.
- Added `COMBAT-ENCOUNTERS.md`, regression coverage for group/wave authoring, temporary spawn/reset, Quest Forge export, and bumped to v0.50.0.

## 0.49.0 - 2026-09-27

- Added editable patrol, alert, and combat route variants linked by stable object ID to persistent NPC population points.
- Added waypoint placement at player/aim, reorder/delete/edit, looping, wait, facing, speed, workspot transitions, and fact-conditioned branch edges.
- Added MCP CRUD tools and Quest Forge `npc_ai_routes` export with cross-reference validation.
- NPC deletion cascades linked route deletion; deleting a waypoint clears branches targeting it.
- Route output is clearly marked handoff-only: native REDengine movement, navmesh, timer, combat/alert reaction, and workspot transition execution are not generated yet.
- Added `NPC-AI-ROUTES.md`, UI/action/export regression coverage, and bumped to v0.49.0.

## 0.48.0 - 2026-09-27

- Added an in-game NPC Population editor using imported World Builder `Character.*` Entity Records.
- Saved points export as persistent `worldPopulationSpawnerNode` data with native appearance, spawn-on-start, always-spawned, and streaming ranges. Temporary previews remain separate from persistent export.
- Added editable attitude/faction/level/archetype/idle/despawn/quest-fact profile handoff, MCP create/list/update/export-audit tools, and Quest Forge population handoff. These profile fields are clearly identified as handoff-only until a verified native profile pipeline consumes them.
- Added a build-time audit that matches saved points to exported native population nodes by record and position, and verifies appearance and spawn flags.
- Added `NPC-POPULATION.md` and bumped the mod to v0.48.0.

## 0.47.0 - 2026-09-27

- Added explicit loot item rows to interactable authoring and Quest Forge handoff.
- Added TweakXL `gamedataLootTable_Record` generation with item/count/drop-chance validation.
- Added native interactable build manifest reporting World Builder sector, device and persistent-state resource counts.
- Integrated interactable artifact generation and validation into Build Mod before CR2W conversion.
- Documented native boundaries: door/fact controller operations and entity components require tested compatible game entity/profile data; they are not fabricated from metadata.

## 0.46.0 - 2026-09-27

- Added read-only runtime reconciliation for LocationStudio-tracked spawned entities, including orphaned, changed, and unverifiable handles.
- Added explicit Sync Runtime in the editor and MCP, with safe update/removal, guarded against active transform/stamp sessions and plan recovery.
- Runtime comparison runs after initialization/project load, Undo/Redo, checkpoint restore, and at a throttled interval while the editor is open.
- Sync does not spawn project objects that were never live and does not touch unowned game entities.

## 0.45.0 - 2026-09-27

- Added named project checkpoints stored separately from the active project.
- Added object-level added/removed/moved/changed comparison and collection change counts.
- Added undoable authoring-data restore, UI controls with explicit confirmation, and four live MCP tools.
- Runtime entity handles are excluded from snapshots. Restoring a checkpoint does not implicitly despawn or respawn live game entities.

## 0.44.0 - 2026-09-27

- Added saved-camera screenshot regression runs through MCP, with stable camera-ID matching, PNG heatmaps, image-size checks, and per-run JSON manifests.
- Added explicit baseline acceptance; new runs never replace the accepted reference automatically.
- Added optional post-rebuild captures to `hotcycle_rebuild`, after archive hot-load and tagged respawn.
- Added standard-library PNG decoding/diff support and tests; documented Hyprland/grim requirements and consistency limits.

## 0.43.0 - 2026-09-27

- Added World Builder Static Audio Emitter placement from the loaded game audio catalog, with event, radius, metadata, room assignment, and MCP support.
- Added room-derived Ambient Area/reverb zones with four editable World Builder Outline Marker objects, native group export linking, and completeness validation.
- Added Ambient Audio UI and documentation. The guide explains that room soundstage effects require native world-edit export and that emitter audibility depends on the selected game event/context.

## 0.42.0 - 2026-09-27

- Added live World Builder static mesh appearance listing, preview, apply, and revert. The chooser accepts only variant names exposed by that spawned mesh instance; previews are live-only until Apply.
- Added searchable placement of real World Builder decal `.mi` materials as native `worldStaticDecalNode` objects, with width, height, alpha, flips, aim placement, and MCP support.
- Added `MESH-APPEARANCES-AND-DECALS.md` with in-game and Claude MCP setup and limitations.
- Added focused tests for listed-variant validation, live preview/revert, saved appearance data, and World Builder decal creation/spawn.

## 0.41.0 - 2026-09-27

- Added the Lighting tab backed by World Builder Static Light (`worldStaticLightNode`) data and the installed live Static Light class.
- Added placement at aim/player, editable RGB, intensity, radius and flicker parameters, six presets, and live tune via remove/respawn.
- Added game-clock preview and restore through CET TimeSystem, plus MCP tools `create_static_light`, `update_static_light`, `preview_time_of_day`, and `restore_time_of_day`.
- Added `LIGHTING.md` with setup, MCP examples, scope and runtime verification requirements.

## 0.37.0 - 2026-09-27

- Added an in-game Quest Forge fact field for trigger volumes and MCP tool `link_volume_to_quest_fact`.
- Expanded Quest Forge export with a world-sector fragment, quest-manifest location NodeRefs, marker/mappin/spot coordinates, and trigger fact links.
- Player-captured coordinates are verified; manually entered positions remain unverified until the author confirms they are standable in game. Trigger boxes convert full dimensions to Quest Forge half-extents.
- Added Lua runtime regression coverage for fact validation and handoff coordinates.

## 0.36.0 - 2026-09-27

- Added saved local room frames with named origins and orthonormal, right-handed u/v axes.
- Added MCP tools for frame CRUD, local/world conversion, placement in a frame, and moving an object in a frame.
- Added schema 14 migration/defaults and runtime checks for the 45-degree sample, round-trip conversion, invalid axes, placement, and move behavior.
- Frame edits affect future coordinates only; existing objects retain their world transforms.

## 0.35.0 - 2026-09-27

- Added `hotcycle_rebuild` and the `hotcycle.py` CLI wrapper to deploy script changes, wait for RedHotTools compilation, hot-load optional archives, and then respawn tagged entities.
- Script sources are recompiled even when their file bytes already match, guarding against files copied earlier without a successful in-game reload.
- Respawn now requires an explicit changed `.reds` source by default so pose edits cannot silently use stale deployed code; opting into the current installed script emits a stale-pose warning.
- Added tests for reload ordering, backup creation, refusal of stale-pose respawns, and game-root path validation.
- Checked for `wb_live_paths` in the project and supplied files; no implementation or description was found, so no guessed tool was added.

## 0.34.0 - 2026-09-27

- Added three prop validators: `wb_clipcheck`, live `wb_fixturecheck`, and `wb_fitcheck` with floor-support and wall modes.
- Added validator controls and a compact result summary in the CET Advanced Tools panel.
- Live validators are read-only and use Static collision raycasts; no props are despawned or changed.
- Added `WB-PROP-VALIDATORS.md` with practical MCP examples, bounds setup, output interpretation, and explicit approximation limits.
- Added runtime coverage for overlap detection, offline/live guards, fixture results, support and wall sampling, and invalid options.

## 0.33.0 - 2026-09-27

- Added read-only `wb_find`, `wb_tree`, `wb_get`, and `wb_refs` project browsing tools.
- Added bounded case-insensitive search, paged summaries, hierarchy expansion, complete item reads, and explicit relationship queries.
- Added MCP bridge routing and runtime coverage for search, tree limits, item detail, inbound/outbound links, and invalid inputs.

## 0.32.0 - 2026-09-27

- Added bounds-based `wb_collisions` project, premise and selection scans with skipped-bound reporting.
- Added read-only `wb_compat_scan` for loaded CET integrations, project resource readiness and installed mod-folder inventory.
- Documented broadphase false positives and limits of inspecting opaque archives/other mods.
- Added focused Lua and Python tests for scan results and mod inventory.

## 0.31.0 - 2026-09-27

- Added grouped path, radial and grid arrays for editable placed objects.
- Added `wb_align` and `wb_distribute` MCP aliases over the existing selection layout behavior.
- Added validation limits, one-step undo transactions and regression coverage.

## 0.30.0 - 2026-09-27

- Added `wb_polygon_scatter`, `wb_volume_scatter` and `wb_live_surface_scatter`
  using the existing editable object/asset copy and undo transaction.
- Polygon scatter validates simple polygon geometry; volume scatter samples
  rotated box, sphere and cylinder shapes; live-surface scatter requires a real
  hit normal and raycasts every copy before authoring any copies.
- Added `wb_rng_create` with the same Park-Miller RNG contract used by scatter.
- Added scatter types guide and deterministic containment/failure regressions.

## 0.29.0 - 2026-09-27

- Added `wb_device_connect` for reciprocal links in an existing World Builder
  device resource graph.
- Added `wb_elevator_wire`, which validates lift/terminal classes and writes
  terminal links in supplied floor order.
- Documented manual NodeRef, marker, persistence, instance-data and WolvenKit
  requirements; graph edits alone do not make an elevator game-functional.
- Added atomic-write and validation tests for valid, duplicate and invalid links.

## 0.28.0 - 2026-09-27

- Added five asset-backed World Builder generators: cable, fence, road,
  market-grid, and semantic NodeRef marker.
- Cable/fence/road require imported Static Mesh resources with valid local
  bounds, scale repeated segments in meters, and produce editable objects.
- Added live World Builder readiness preflight, explicit spawn results and
  per-object failure reporting; no fake game assets or primitive geometry.
- NodeRef markers are explicitly authoring metadata only, not native streaming
  nodes or deployable REDengine resources.
- Added `WB-GENERATORS.md`, MCP usage examples, and runtime tests.

## 0.27.0 - 2026-09-27

- Added real in-game saved-prefab thumbnails through `wb_prefab_render` and a
  matching Prefabs-panel action. Render uses temporary live World Builder/CET
  instances, captures the game frame, then removes the temporary instances.
- Persisted thumbnail path/source/time on the prefab record and added thumbnail
  caching/display plus safe backup on replacement.
- Added completion, error, timeout and cleanup-retry handling; no placeholder
  image is reported as a completed render.
- Added `WB-PREFAB-THUMBNAILS.md`, in-game/MCP examples and render-cleanup
  regression coverage.

## 0.26.0 - 2026-09-27

- Combined the v0.25 asset-bounds authoring math with native World Builder
  Favorites MCP support.
- Added `wb_favorite_add` and `wb_favorites_list`. Add previews by default,
  resolves the resource against World Builder's live catalog, and only writes
  with explicit `write=true`; it does not spawn or register the resource.
- Existing Favorites category files are backed up and atomically replaced,
  retaining unknown JSON fields. Duplicate category names are rejected.
- Added `WB-FAVORITES.md`, first-run/MCP examples, and Lua/Python regression
  tests for live resource serialization, dry-run behavior, idempotency, backups,
  and preservation of unknown fields.

## 0.25.0 - 2026-09-27

- Added persistent resource-local asset bounds in meters, with validation,
  import/edit/info operations, dimensions, source attribution, and propagation
  to existing placed instances that retain their originating asset ID.
- Added a versioned JSON bounds manifest and MCP tools `wb_bounds_import`,
  `wb_bounds_info`, `wb_bounds_set`, `wb_bounds_fit`,
  `wb_bounds_world_aabb`, and `wb_bounds_overlap`.
- Added transformed 8-corner world AABBs (position, Euler rotation and per-axis
  scale), stretch/uniform-contain fit calculations, and pairwise collision
  broad-phase overlap checks. These do not create engine collision geometry.
- Added `WB-ASSET-BOUNDS.md` and runtime tests for import validation, edits,
  instance propagation, transform math, fit math, and overlaps.

## Unreleased

- Added a headless build pipeline: LocationStudio objects -> World Builder
  `*_exported.json` -> CR2W streaming sectors -> `.archive` + `.xl` ->
  game-layout package -> verify/deploy. `export_project("worldbuilder")` is only
  a neutral JSON handoff and never produced an archive; the new `build_*` MCP
  tools do.
- The export is written by World Builder itself (`modules/build_export.lua`):
  live WB handles are serialized with WB's `serialize()`, saved as WB group
  `ls_<name>` and exported through WB's `exportUI`. CET-spawned `.ent` objects
  cannot be exported and are refused unless `allow_skipped=true`.
- Vendored cp77wb 1.0.1's build/native/worker/logs modules and the .NET
  WolvenKit worker source into `mcp_server/lsbuild/` (MIT), so cp77wb no longer
  needs to be installed. Writing steps are previews unless write/run/apply.
- 21 new MCP tools (195 total); new `build_export_runtime_test.lua` and
  `mcp_server/test_build.py`.
- Added a one-time migration of World Builder/cp77wb saved builds
  (`entSpawner/data/objects/*.json`) into the project
  (`modules/wb_import.lua`, `import_world_builder_build`,
  `list_world_builder_builds`). WB groups become nested LS object groups under a
  premise; every object keeps its full WB spawnable blob, so respawn and build
  export reproduce it exactly. Preview by default, one undo step, rolled back on
  failure; legacy Object Spawner builds, unknown classes and re-imports are
  refused unless explicitly allowed. 197 MCP tools; new
  `wb_import_runtime_test.lua`.
- Exposed the existing project-wide undo/redo over MCP (`undo`, `redo` with
  `steps`, and `get_history`). History entries now carry a label and
  timestamp (model adds, transform/stamp commits, gizmo moves, authoring plans,
  imports), and `get_history` computes per-collection added/removed/changed
  counts so unlabelled entries still say what they touch. The metadata never
  reaches project.json.
- Fixed: redo did not respawn objects that the undo had despawned (also
  affected the editor's REDO button). 200 MCP tools; new
  `history_bridge_runtime_test.lua`.
- Added offline search of the World Builder resource database (vendored
  cp77wb assets/semantics in `mcp_server/lsassets/`): `asset_catalog_build`,
  `asset_catalog_info`, `asset_catalog_search` (full-text, category/variant/
  module/extension filters), `asset_catalog_get`, `asset_semantic_build`,
  `asset_semantic_search` (role/style/material/condition facets; unknown facet
  values are rejected with the valid list). The index lives in
  `data/asset-catalog.sqlite3` (~360k entries, ~560 MB for a typical install).
- `import_catalog_asset` turns a hit into a Project Asset by resolving it
  against World Builder's loaded catalog, so the entry and class are WB's own
  and a stale index cannot create an unspawnable asset. 207 MCP tools; new
  `test_catalog.py` and `catalog_import_runtime_test.lua`.

## 0.24.0 - 2026-09-21

- Added an in-game Scene Director with separate editing/live scene state and
  functional capture, membership, synchronization, activation, isolation,
  deactivation, and object-selection controls.
- Added scene capture from an active premise or current selection. Location
  capture owns rooms, ordinary placed objects, volumes and cameras while room
  shells remain derived from room ownership; construction pieces are optional.
- Added validated add/remove/replace membership editing without deleting member
  data, plus preservation of global point/route membership during premise sync.
- Added backend-safe scene deactivation and deletion: a CET/World Builder
  removal refusal retains live ownership and blocks deletion.
- Added four declarative plan operations, seven MCP tools, four CET hotkeys,
  bridge operations/status, structured logs, a fourth built-in plan, and a
  captured-scene JSON example.
- All 32 isolated suites pass on Lua 5.1 and LuaJIT 2.1. All 147 MCP tools pass
  Python compilation and static contract checks.

## 0.23.0 - 2026-09-21

- Added declarative Authoring Plans covering registered assets, premises, real
  game-asset rooms/openings, placed assets, locations, volumes, cameras, routes,
  persistent groups, scenes, transforms, spawning, and scene activation.
- Added backward-only `$alias` references, player/camera/explicit origins,
  unambiguous asset resolution, 100-step validation, and three executable JSON
  examples.
- Made a successful plan exactly one Undo operation. A failed step cleans up
  runtime objects and restores project/history/selection/dirty state.
- Added explicit recovery when a CET or World Builder backend refuses cleanup;
  save, export, history, autosave, new plans, and unrelated bridge mutations are
  blocked until retry-rollback or keep-partial completes.
- Added schema-13 first-class Scenes with validated room/object/location/volume/
  camera/route membership, activation, object selection, hierarchy entries, and
  Inspector controls.
- Added the HELP + START workspace with live readiness, spawn smoke test,
  runnable starter/furnished/route plans, plan-file validation/execution,
  recovery controls, first-run guidance, and debug-report creation.
- Added scene/plan bridge status, structured logs, diagnostics, two CET hotkeys,
  and 17 new MCP tools for plan/scene lifecycle and safe file-based workflows.
- Added FIRST-RUN, AUTHORING-PLANS, MCP-EXAMPLES, and TROUBLESHOOTING manuals.
- All 31 isolated suites pass on Lua 5.1 and LuaJIT 2.1. All 140 MCP tools pass
  Python compilation and static contract checks.

## 0.22.0 - 2026-09-21

- Replaced independent fire-and-forget stamp clicks with a persistent live Stamp
  Stroke transaction for World Builder resources and direct CET `.ent` assets.
- Added one-undo commit, complete cancel, prior selection/dirty restoration,
  minimum-spacing enforcement, and a 200-object stroke safety limit.
- Made temporary asset previews non-mutating; asset-use metadata and project
  dirty state now change only when a non-empty stroke commits.
- Added runtime-removal refusal protection so a failed cancel retains authored
  ownership and the active stroke instead of orphaning live game entities.
- Blocked save, export, history, Transform Edit, and unrelated MCP mutations
  until the stroke commits or cancels; overlay close/shutdown cancels unfinished
  strokes.
- Added the persistent Stamp Stroke header, explicit commit/cancel controls, a
  cancel hotkey, bridge/status/diagnostic fields, three MCP tools, and structured
  `[stamp:stroke]` logging.
- Preserved old Stop Stamp and `stop_asset_preview` workflows as commit aliases.
- Added dedicated World Builder/direct CET, spacing, undo/redo, rollback,
  cleanup-refusal, overlay, preview, UI, bridge, MCP, hotkey and log coverage.
  All 30 suites pass on Lua 5.1 and LuaJIT 2.1; all 123 MCP tools compile.

## 0.21.0 - 2026-09-21

- Replaced the default asset-card Place and object Duplicate-at-Aim paths with
  transactional live Placement + Edit.
- Added Project Asset placement from crosshair, player, active preview, or an
  explicit transform, with surface offset/alignment and exact target diagnostics.
- Added crosshair placement for complete object selections while preserving
  assembly spacing, height offsets, resource metadata, and room-kit detachment.
- Made creation plus final transform one undo state; cancel/overlay close removes
  all copies and restores the prior object or asset selection.
- Added backend-removal refusal safety, real World Builder/direct CET spawning,
  preview handoff cleanup, mixed-backend editing, and explicit selection checks.
- Repaired legacy object `duplicate_at_aim` through the same transaction engine.
- Added default/advanced UI controls, a CET hotkey, one MCP tool, bridge support,
  diagnostics and structured placement logs.
- Added asset, preview, player, surface, mixed-backend group, rollback-refusal,
  undo/redo, legacy, UI, hotkey, bridge and log coverage. All 29 suites pass on
  Lua 5.1 and LuaJIT 2.1.

## 0.20.0 - 2026-09-21

- Replaced fire-and-forget Scatter Stamp with deterministic transactional
  Scatter + Edit for placed objects, mixed-backend assemblies, and Project
  Assets.
- Added seeded uniform-disk placement, optional assembly yaw, exact radius and
  aim distance, and preflight ground raycasts that reject partial creation.
- Preserved World Builder resource metadata and direct CET `.ent` spawning while
  making creation plus final transform exactly one undo operation.
- Added complete cancel/overlay-close cleanup, previous selection restoration,
  backend-removal refusal handling, and room-kit detachment.
- Repaired legacy `scatter_at_aim` as a safe auto-commit compatibility command
  and fixed caller-argument mutation in all created-edit session starts.
- Added compact/default and Advanced Tools controls, a CET hotkey, one MCP tool,
  bridge/status fields, deterministic diagnostics, and structured scatter logs.
- Added mixed-backend geometry, repeatability, asset-source, ground-failure,
  rollback-refusal, undo/redo, UI, hotkey, bridge, legacy, and log coverage. All
  28 suites pass on Lua 5.1 and LuaJIT 2.1.

## 0.19.0 - 2026-09-21

- Replaced the old Array and Mirror UI paths with transactional live Pattern
  Placement for one object or a complete selection.
- Added world/local XYZ array steps, per-repetition yaw, center/active pivots,
  mixed World Builder/direct CET spawning, and a 100-copy safety limit.
- Added Mirror X/Y copy placement around the location origin while explicitly
  avoiding unsupported negative-scale geometry claims.
- Made pattern creation plus final transform exactly one undo operation; cancel,
  overlay close, and shutdown remove all created runtime and project objects.
- Repaired legacy builder/MCP Array and Mirror commands to live-spawn, detach
  room-kit ownership, and auto-commit through the same transaction engine.
- Added compact default UI controls, exact Advanced Tools inputs, three hotkeys,
  two MCP tools, diagnostics fields, and structured pattern/mirror logs.
- Added mixed-backend geometry, rollback refusal, UI, bridge, hotkey, legacy
  compatibility, and undo/redo coverage. All 27 suites pass on Lua 5.1 and
  LuaJIT 2.1.

## 0.18.0 - 2026-09-21

- Added transactional Duplicate + Edit for a single placed asset or a complete
  mixed World Builder/direct CET object selection.
- Spawned copies through their actual runtime backends before editing and reused
  the reversible world/local Transform Edit toolbar for placement.
- Detached duplicated room-kit pieces from shell rebuild ownership.
- Made copy creation and all transform changes exactly one undo operation,
  including duplicate commits with no additional movement.
- Made cancel, overlay close, and shutdown despawn and remove all copies while
  restoring the original selection and pre-session dirty state.
- Kept cancellation active and retained authored ownership when a runtime backend
  refuses removal, preventing silent orphan entities.
- Added Scene/Inspector controls, a CET hotkey, one MCP tool, bridge/session
  status fields, and structured duplicate transaction logging.
- Added mixed-backend, failed-removal, undo/redo, overlay-close, UI, hotkey,
  bridge, and logging regressions. All 26 suites pass on Lua 5.1 and LuaJIT 2.1.

## 0.17.0 - 2026-09-21

- Added transactional Transform Edit sessions for single objects and complete
  object selections.
- Added reversible world/local movement, group yaw, single-object roll/pitch,
  center/active/custom pivots, and uniform World Builder scale.
- Updated World Builder handles in place and safely respawned live direct CET
  `.ent` resources after each accepted manual adjustment.
- Recomputed every preview from original session state to prevent cumulative
  transform drift; Reset and Cancel restore original transforms and sizes.
- Rejected unsupported group roll/pitch and direct CET scale instead of saving
  fake runtime state.
- Made a complete Transform Edit one undo operation and made no-op commits create
  no history entry.
- Added a persistent Transform Edit toolbar, Scene/Inspector entry points, a CET
  hotkey, six MCP tools, diagnostics, and structured logs.
- Added full Transform Edit runtime coverage. All 25 suites pass on Lua 5.1 and
  LuaJIT 2.1.

## 0.16.0 - 2026-09-20

- Added reversible crosshair Grab Move sessions for single objects and
  multi-object selections.
- Preserved relative group layout around center or active-object pivots and
  added incremental yaw, grid snapping, and single-object surface alignment.
- Updated World Builder handles continuously while deferring direct CET entity
  refresh to the stable commit path.
- Made commit one undoable operation and made cancel/overlay-close/shutdown
  restore exact original transforms.
- Blocked save, export, history, and unrelated MCP mutations during active
  sessions.
- Added five hotkeys, five MCP tools, session diagnostics, and structured logs.
- Added a full Grab Move runtime suite. All 24 suites pass on Lua 5.1 and
  LuaJIT 2.1.

## 0.15.0 - 2026-09-20

- Added camera-ray picking for saved project objects, with premise/visibility
  filtering, adjustable distance/radius, selection logging, and optional native
  World Builder handle focus.
- Added preview alignment to raycast surface normals while preserving artist yaw
  and the configured surface offset.
- Added persistent stamp sessions, one-shot stamp hotkeys, per-session counts,
  and minimum-spacing rejection for accidental duplicate placement.
- Kept stamped instances on the existing real CET/World Builder placement path;
  each instance is saved and individually editable.
- Added four MCP tools, expanded diagnostics/support logs, and exposed the new
  controls in the default Scene and Assets workspaces.
- Added end-to-end runtime coverage. All 23 suites pass on Lua 5.1 and LuaJIT 2.1.

## 0.14.0 - 2026-09-20

- Added min/center/max/active X/Y/Z alignment for object selections.
- Added even X/Y/Z distribution with stable endpoints.
- Added match-to-active rotation and World Builder scale.
- Added grid/angle snapping for complete selections.
- Added safe batch asset replacement with backend-aware despawn and respawn.
- Preserved construction mesh restrictions, collision protection, editing
  locks, and explicit CET scaling limitations.
- Recalculated persistent non-custom group pivots after precision layout.
- Added two MCP layout tools and a full precision-layout runtime suite.
- All 22 suites pass on Lua 5.1 and LuaJIT 2.1.

## 0.13.0 - 2026-09-20

- Added persistent nested object groups to the Scene hierarchy.
- Added recursive group selection and World Builder focus.
- Added center, active-object, and custom pivot modes; custom pivots can be
  captured from the player.
- Added reusable object prefabs that preserve actual CET entity or World Builder
  resource definitions and relative transforms.
- Added prefab placement at the player or aimed surface as editable, live,
  independently grouped objects.
- Detached prefab copies of room-kit pieces from rebuild ownership.
- Added group-cycle prevention, membership cleanup, validation, status counts,
  and diagnostics.
- Added ten MCP group/prefab tools and an assembly runtime regression suite.
- All 21 suites pass on Lua 5.1 and LuaJIT 2.1.

## 0.12.0 - 2026-09-20

- Added two-way selection synchronization between LocationStudio and World
  Builder for every LocationStudio-owned live World Builder handle.
- Added hierarchy selection toggles and Select Shown / Clear Set controls.
- Added center-pivot group move, yaw rotation and uniform scale with adjustable
  steps and world or active-object local axes.
- Added group show/hide, lock/unlock, spawn/despawn, duplicate and delete.
- Made live group transforms update World Builder handles in place and grouped
  each operation into one undo snapshot.
- Made duplicates of generated room pieces independent from shell rebuild
  ownership while preserving relative layout.
- Rejected unsupported live scaling for CET-spawned `.ent` objects instead of
  recording a misleading bounds-only edit.
- Added seven MCP selection/group tools and expanded selection diagnostics.
- Added multi-object regression coverage. All 20 suites pass on Lua 5.1 and
  LuaJIT 2.1.

## 0.11.0 - 2026-09-20

- Made generated game-asset room pieces visible in a dedicated Construction
  hierarchy in the default Scene workspace.
- Added native World Builder gizmo selection and automatic two-way transform and
  scale synchronization back into the saved LocationStudio project.
- Added room/location and surface-role scoped show, hide, lock and unlock actions.
- Enforced object locks across UI actions, authoring tools, bridge operations,
  duplication, deletion, replacement and native gizmo access.
- Added single-piece Static Mesh replacement from the full Game Database without
  rebuilding unrelated room surfaces.
- Added Detach / Make Unique so customized pieces survive future room rebuilds.
- Fixed generated-piece duplication and deletion ownership integrity.
- Fixed false validation warnings for World Builder resources with no `.ent`
  template and immediate runtime handling for hidden/shown construction.
- Added four construction MCP tools and expanded diagnostics with detached,
  locked and disabled piece counts.
- Added a construction-editor regression suite. All 19 suites pass on Lua 5.1
  and LuaJIT 2.1.

## 0.10.0 - 2026-09-20

- Replaced primitive-cube rooms with tiled base-game architecture mesh kits.
- Added Common Interior and Kitsch Apartment presets with floor, ceiling, wall,
  door-wall, and window-wall resource roles.
- Made every visual room piece a normal editable World Builder static mesh.
- Added hidden World Builder floor/wall collision nodes, with door gaps preserved.
- Added assignment of any imported Static Mesh to a room role, plus editable
  native dimensions, pivot offsets, and rotation correction.
- Added selected-room and premise-wide rebuild controls to Simple and Advanced UI.
- Added automatic migration of v0.9.x generated primitive shells and blocked all
  silent `base\spawner\cube.mesh` runtime fallback.
- Expanded diagnostics with kit paths, generated mesh/collider counts, legacy
  object detection, and collision-class probing.
- Added game-asset room kit, collision, custom-role, and migration regression
  coverage. All 18 suites pass on Lua 5.1 and LuaJIT 2.1.

## 0.9.4 - 2026-09-20

- Fixed the exact live failure reported by v0.9.3: CET cannot import World
  Builder's private spawn-class modules from another mod's `require()` scope.
- Resolved the live class object from World Builder 1.0.81's active resource list,
  cached it only in memory, and re-resolved it safely for saved projects.
- Made Game Database the default Assets view and automatically loaded the first
  Entity Templates page, so the six starter objects are no longer presented as
  the complete library.
- Added live World Builder position/rotation editing coverage and restart-style
  class recovery coverage with private class modules deliberately unavailable.
- Added entity/static-mesh class probes to diagnostics and versioned support
  reports to prevent old debug files from being mistaken for the current build.

## 0.9.3 - 2026-09-20

- Replaced the incompatible room adapter with the actual World Builder 1.0.81
  Spawn New API while retaining the legacy compatibility path.
- Added a paged Game Resources browser over every World Builder category and
  variant, with search, single import, shown-page import, preview, and Place Now.
- Added multiline `.ent` / `.mesh` bulk import and automatic duplicate skipping.
- Added normal-UI asset editing, duplication, deletion, and synchronized editing
  of World Builder resource paths.
- Added live placed-object position, rotation, scale, template/resource, and
  appearance editing with apply/refresh, duplicate, despawn, and delete actions.
- Fixed room/prefab buttons that previously created only invisible authoring data;
  their messages now reflect the live spawn result.
- Expanded diagnostics with World Builder API/catalog/search state, increased the
  retained log tail, and stopped repeated dirty-state log spam.
- Added World Builder 1.0.81 catalog/spawn/edit/despawn and complete Game
  Resources UI regression suites. All 17 LuaJIT 2.1 suites pass.

## 0.9.2 - 2026-09-19

- Repaired bit32-dependent IDs, stale preview aim transforms, opaque spawn-success
  assumptions, and discarded ownership after failed removals.
- Added bounded asynchronous entity tracking, timeout reporting, cancelled-spawn
  cleanup, and recovery when a previously confirmed entity streams back in.
- Fixed empty doorway primitive blockers, size preflight, and runtime room resizing.
- Replaced vector widget overload assumptions with scalar numeric fields.
- Added compact scene/Inspector navigation, persistent status messages, and
  one-click shareable debug reports in the main sidebar.
- Fixed thumbnail capture's obsolete window flag and preserved previous images
  on helper failure; added explicit sandbox capability errors.
- Added staged project/config saves with backups and refusal to overwrite invalid
  projects, live log rotation, and nil-safe logged function returns.
- Fixed empty Undo/Redo removing live entities and reconciled runtime instances
  after restoring a model snapshot.
- Added a repeatable isolated LuaJIT/Lua 5.1 test runner and six new regression
  suites. All 15 suites pass on both runtimes; no in-game certification claimed.

## 0.9.1 - 2026-09-18

- Fixed the editor window silently not appearing when `data/config.json` persisted `window_open=false`.
- Removed persisted close-state gating from the CET `onDraw` path.
- Opening the CET overlay now always restores LocationStudio visibility.
- LocationStudio now uses a non-closable ImGui window tied to CET overlay visibility; use the LocationStudio hotkey to temporarily hide/show it while the overlay is open.
- Added a first-frame `ui:draw` log entry and immediate diagnostic fallback if the full editor throws during its first draw.
- Added an optional one-shot window recenter recovery path.

## 0.9.0 - 2026-09-18

### Focused themed UI
- Rebuilt the default interface around three workspaces only: BUILD, ASSETS, and SCENE.
- Added a dark Night-City-inspired visual theme with signal yellow, electric cyan, rounded panels, clear runtime states, and primary/secondary/destructive action hierarchy.
- Removed the old default toolbar and bottom dock from Simple UI.
- Moved cameras, volumes, raw templates, transform utilities, scatter tools, exports, MCP, diagnostics, and other specialist controls behind one Advanced Tools switch.
- Simplified Quick Build to room creation, visible runtime status, room sizing, and connected-room growth.
- Simplified asset cards to Preview / Place with thumbnail capture shown contextually instead of on every card.
- Simplified the Scene inspector to game-facing actions that have concrete runtime effects.
- Advanced mode preserves the existing specialist authoring panels.

## 0.8.1 - 2026-09-18

- Fixed the real CET `SyncRaycastByCollisionGroup` return shape (`success, result`) that caused `game.lua:191` to index a boolean and break Move to Aim, Drop to Ground, camera capture and workspace panels.
- Added a World Builder / entSpawner runtime-shell adapter for generated room floor/wall/ceiling primitives. No World Builder code or archives are redistributed.
- Quick Build now attempts to spawn visible runtime shell geometry immediately and reports an explicit runtime failure instead of claiming model-only room data is visible.
- Added `SPAWN LOCATION NOW` / `DESPAWN LOCATION` and a runtime readiness banner.
- Seeded six starter game `.ent` assets so a fresh install can immediately test real CET entity spawning without manually registering paths.
- Added `SPAWN TEST CHAIR` / `REMOVE TEST` as an independent real-spawner self-test.
- Fixed runtime entity accounting so despawn counts represent entities that actually existed.
- Throttled camera debug logging to remove per-frame log spam.
- Diagnostics now report World Builder/runtime-shell readiness.
- Added a regression test covering boolean+result raycasts, visible Quick Build shell spawning, starter asset spawning, move/drop operations, and real despawn accounting.

# Changelog

## 0.8.0 - 2026-09-18

- Added a first-class **LIBRARY** workspace with an image-first asset grid.
- Added dynamic **All / Favorites / Recent / Missing / Category** views generated from the asset catalog.
- Added persistent favorite state, use counts and last-used timestamps so frequently used assets become easy to find again.
- Added real per-asset thumbnail caching under `thumbnails/<asset-id>.png` and direct rendering through CET `ImGui.LoadTexture` / `ImGui.Image`.
- Added **Capture Thumbnail** from the asset grid and Inspector. LocationStudio temporarily previews the real `.ent`, hides its own window, captures the center of the game frame, crops/resizes it, and caches the PNG.
- Added Linux/Proton capture helper support for `grim`, `maim`, `scrot`, ImageMagick `import`, `gnome-screenshot`, or `spectacle`, plus a Windows PowerShell capture helper.
- Added image cards with one-click favorite, select, preview, place and snapshot refresh controls.
- Added a large selected-asset preview pane with cached snapshot metadata and live-preview controls.
- Added thumbnail/category regression coverage and bumped the project schema to v7 with additive asset-library metadata/settings.

## v0.7.0 - Asset Preview UI

- Added temporary in-world asset preview ghosts that can be spawned from the asset browser, inspector, and HOME workspace before committing placement.
- Added preview controls in the UI: Preview at Aim, Preview Here, Place Previewed, and Clear Preview.
- Added asset preview settings for auto-preview on selection, follow aim, preview distance, and enable/disable state.
- Closing the overlay now clears any active preview ghost automatically.
- Added automated runtime test coverage for the preview flow.


## 0.6.0 - 2026-09-18

- Reoriented the default product around zero-documentation location and room creation.
- Added HOME / Quick Build as the first workspace for new and upgraded users.
- Added one-click **Create First Room Here**, which automatically creates the location container at the player position.
- Added Small, Medium, Large and Hall room presets plus direct width/depth/height controls.
- Added **New Room Here** using the player's current position with no coordinate entry.
- Added directional **Add North/South/East/West** room growth from the selected room.
- Added automatic paired doorway openings between newly connected adjacent rooms.
- Added one-click Apartment, Clinic and Warehouse starts without requiring a manually created premise first.
- Added persistent Simple mode; technical BUILD/SPATIAL/TOOLS panels are hidden until Advanced mode is requested.
- Simplified beginner hierarchy terminology from Premises/GamePlay to Locations/Extras and hid generated-shell internals.
- Added a beginner Inspector that hides raw transforms, `.ent` paths, layer fields and other engine-facing settings while keeping size/move/apply/common actions available.
- Made the object catalog optional in Simple mode and moved custom `.ent` registration behind Advanced mode.
- Bumped project schema to v5 with additive quick-start/workspace settings.
- Added a zero-doc Quick Start runtime regression test and expanded syntax coverage to all 27 Lua files.

## 0.5.0 - 2026-09-18

- Added a dedicated TOOLS workspace based on practical workflows from the supplied CP77_entSpawner source.
- Added active-camera transform, forward-vector, FOV and raycast capture for editor-style aim placement, with a player-eye fallback when the camera API is unavailable.
- Added copy/paste position, rotation and full transforms; reset rotation; move-to-player/aim; drop-to-ground; and teleport-player-to-selection operations.
- Added transform target management and look-at commands for selected targets, player position and crosshair hits.
- Added group-aware premise/room translation and rotation so child rooms, objects, volumes and cameras remain spatially coherent.
- Added duplicate-at-aim and scatter-stamp placement with count/radius/random-yaw/ground projection and optional live preview.
- Added active-camera capture as a persistent camera node and exposed all new workflows through Claude MCP.
- Expanded diagnostics and regression tests for camera/tool capability and ensured the raw ImGui draw-list crash path remains forbidden.

## 0.4.2 - 2026-09-18

- Removed the crashing raw ImGui draw-list viewport path (`viewport.lua:47` in v0.4.1) and replaced it with a CET-safe widget renderer.
- Connected Premises Builder and Spatial/Camera/Volume panels to the active editor.
- Unified UI and action selection state so hierarchy, inspector, hotkeys, builder, spatial tools, and MCP do not keep stale independent selections.
- Added real player-state capture for premise, volume, and camera creation, plus explicit camera aim fallback warnings.
- Hardened entity spawn/despawn/refresh with guarded `exEntitySpawner` calls and premise-scoped runtime cleanup.
- Added structured `action:*`, placement, game, and panel telemetry for every important authoring action.
- Preserved authored objects when live preview spawning fails and surfaced the failure as a warning / `spawn_error`.
- Fixed MCP deletion paths so deleting selected locations/assets/premises/rooms/objects/volumes/cameras clears stale selection state.
- Expanded diagnostics and added regression tests that forbid use of the old raw draw-list viewport.

## 0.4.1 - 2026-09-17

- Added an append-only, flushed runtime logger that starts before all other modules.
- Added 2 MiB log rotation and an in-memory tail for the UI.
- Added protected module loading, staged initialization, event callbacks, hotkeys, bridge commands, full-editor rendering, saving, exporting, and entity spawning.
- Added a minimal safe diagnostic window that remains available when the full editor fails.
- Added an in-editor debug-log panel and capability report generation.
- Removed unverified ImGui style-variable usage from the theme for broader CET compatibility.
- Added MCP tools for reading/clearing logs, running diagnostics, and producing a debug bundle.
- Added a Linux `collect-debug.sh` helper that excludes project content by default.

## 0.4.0 - 2026-09-17

- Replaced the tabbed database-form UI with a three-pane engine workspace and bottom content dock.
- Added a persistent scene hierarchy and one shared selection model across hierarchy, viewport, inspector, hotkeys, and actions.
- Added a contextual inspector with working type-specific controls and spawn/refresh/despawn state.
- Added a reusable `.ent` asset catalog with search, registration, edit, deletion, aim placement, player placement, and MCP access.
- Added Live Preview behavior so placed/spawned objects refresh through the same action layer used by the UI.
- Made the plan viewport permanently visible and added labels, stronger selection feedback, axes, snapping, and zoom controls.
- Consolidated premises prefabs, validation, runtime status, save, export, and MCP handoff into the bottom dock.
- Added schema v4 migration without losing prior locations, routes, premises, rooms, objects, volumes, or cameras.
- Expanded the Claude MCP toolset from 52 to 57 tools.

## 0.3.0 - 2026-09-17

- Added a clickable top-down floorplan with rooms, objects, volumes, cameras and look-at lines.
- Added local-axis transform controls, grid/angle snapping and batch transforms.
- Added aim placement with explicit raycast/entity/fallback source reporting.
- Added box, sphere and cylinder gameplay/trigger volumes.
- Added camera capture, look-at authoring, FOV/duration metadata and teleport preview.
- Added configurable transient in-world marker entities.
- Added QuestForge semantic handoff export.
- Extended World Builder handoff with cameras and volumes.
- Added schema v3 migration while preserving v0.1/v0.2 data.
- Expanded the Claude MCP toolset for visual/spatial authoring.

## 0.2.0 - 2026-09-17

- Added a full Premises Builder tab with premise anchors, rooms, corridors, levels and local-space placement.
- Added procedural room shells: floors, ceilings and wall segmentation around door/window openings.
- Added construction objects, semantic layers, templates, appearances, duplication, arrays and mirroring.
- Added live .ent preview spawning/despawning through CET exEntitySpawner.
- Added clinic, apartment and warehouse starter prefabs.
- Added World Builder/WolvenKit-neutral construction handoff export.
- Added schema-v1 to schema-v2 migration without losing existing locations or routes.
- Expanded validation for missing references, room geometry, openings, layers and templates.
- Expanded Claude MCP with premise, room, opening, object, spawn, array, mirror and prefab tools.

## 0.1.0 - 2026-09-17

- First functional CET LocationStudio scaffold.
- Location capture/library/editor/teleport testing.
- Routes, validation, undo/redo, autosave and exports.
- File-backed Claude MCP bridge using official MCPServer API.
- Optional World Builder / AMM / RedHotTools discovery.
## 0.38.0 - 2026-09-27

- Added saved sit, lean, and terminal NPC workspot points in the Spatial panel, editable XYZ/yaw, and temporary NPC preview at the saved point.
- Added MCP create, preview, and approach-check tools. Preview spawns a Codeware dynamic stand-in and starts the supplied AMM animation after the entity resolves.
- Added a three-ray Static/Dynamic collision hint with explicit limits; it does not claim REDengine navmesh/pathfinding access.
- Added `NPC-WORKSPOTS.md` and runtime coverage for saved-position preview requests, delayed NPC/workspot activation, and approach result semantics.
## 0.39.0 - 2026-09-27

- Added bounded floor-support and actor-clearance grid scans for V or a live NPC, followed by a four-neighbor route search with configurable footprint, grid spacing, and detour margin.
- Added potential blocker hit coordinates/groups, including Dynamic surfaces that may be props, plus in-game Spatial panel and MCP `walkability_check`.
- The result explicitly labels itself a geometric candidate and reports that a verified REDengine navmesh query is unavailable; bounded or unsupported scans return inconclusive.
- Added mocked regressions for clear routes, blocked corridors, NPC start positions, blocker reports, and grid-size caps; added `WALKABILITY.md`.
## 0.40.0 - 2026-09-27

- Added placement and editing for door, loot-container, shard, and item authoring entries using registered game Entity `.ent`, Entity Record, or Device assets.
- Added validated `Items.*`, `LootTables.*`, lock state, and fact/value fields; regular placed entity spawning is handled by the existing CET/World Builder placement path.
- Added MCP create/list/update/delete operations and Quest Forge `interactable_handoff` plus World Builder object metadata export.
- Marked all interaction settings `authoring_only`: CET does not rewrite `.ent` components, loot tables, streaming-sector persistent state, or native fact callbacks. Added `INTERACTABLES.md` documenting native resource requirements.
- Added runtime checks for placement metadata, record validation, edits, blocker behaviors, Quest Forge handoff, and mesh-only asset rejection.
