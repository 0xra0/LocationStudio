# LocationStudio v0.72.0 — Procedural Geometry

LocationStudio is an in-game Cyber Engine Tweaks editor for building locations,
placing the full World Builder game-resource catalog, moving live objects, and
saving reusable Cyberpunk 2077 scene layouts.

v0.50.0 adds a Combat Encounters editor for enemy groups, waves, volume/fact/reinforcement conditions, faction relations, temporary test/reset, and Quest Forge export. Trigger-driven combat execution remains dependent on compatible native quest/community wiring. See [COMBAT-ENCOUNTERS.md](COMBAT-ENCOUNTERS.md).

v0.53.0 adds persistent Device Logic graphs for terminals, doors, elevators, switches, cameras, security systems, facts, actions, and links. It can apply complete caller-supplied typed device/PS/node payloads into a WB export, wire device edges, and compile `.devices`/`.psrep` resources. Build Mod audits records and links. It does not invent class-specific instance payloads or execute fact/action semantics in REDengine. See [DEVICE-LOGIC.md](DEVICE-LOGIC.md).

v0.54.0 adds a conflict-aware Quest Forge round-trip. Preview/import matches exact LocationStudio IDs (or previously linked NodeRefs), displays linked facts beside selected objects, preserves local notes and placement by default, and only applies changed coordinates when explicitly enabled. See [QUEST-FORGE-ROUNDTRIP.md](QUEST-FORGE-ROUNDTRIP.md).

v0.55.0 adds a quest simulation/debug panel with live fact reads, writer/consumer mapping, and staged fact writes. Each write/reset/manual trigger requires a second confirmation after a persistent-save warning. Manual trigger simulation sets the configured fact; it does not dispatch a native volume event. See [QUEST-SIMULATION.md](QUEST-SIMULATION.md).

v0.72.0 adds procedural geometry: generate walls (with openings), floors, ceilings, columns, stairs, ramps, door frames, windows, railings, pipes, ducts and boxes from dimensions. Each piece gets collision and an in-game preview, and Build Mod turns it into a real `.mesh` (glTF → WolvenKit, reusing a template mesh's materials) placed in the exported sector. See [PROCEDURAL-GEOMETRY.md](PROCEDURAL-GEOMETRY.md).

v0.71.0 adds the Environment Definition Language: describe an entire location in one JSON/YAML file, and LocationStudio compiles it into one undoable in-game build and, through Build Mod, into game archives. The file can cover floors, rooms, walls, doors, windows, materials, props, lights, collision, devices and logic, NPCs with routes and workspots, audio, VFX, triggers, cameras, navigation and streaming. Re-applying a document updates its location in place. See [ENVIRONMENT-DEFINITION-LANGUAGE.md](ENVIRONMENT-DEFINITION-LANGUAGE.md).

v0.70.0 adds a full shipping preflight: one command (`preflight_run`) that checks broken resource paths, missing bounds, failed spawns, unresolved NodeRefs, invalid quest facts, missing native interactable setup, incomplete ambient areas, workspots with no route, bad device links, unexportable CET entities, missing dependencies, sector problems and visual-regression failures, and returns one verdict. See [PREFLIGHT.md](PREFLIGHT.md).

v0.69.0 adds an asset dependency resolver. Starting from every exported object, it recursively follows modded meshes, templates, appearances, materials, textures, particles, TweakDB records and audio events through your mod sources (WolvenKit projects, raw JSON, prebuilt archives). It classifies each one as ship, vanilla (from the game archive index), another installed mod, or missing (with the chain that needs it). Build Mod stages what ships and stops on missing dependencies. See [ASSET-DEPENDENCIES.md](ASSET-DEPENDENCIES.md).

v0.68.0 adds reference-area capture. Box-select part of the vanilla world and capture it into a read-only reference layer (locked, never exported, exact transforms from a WolvenKit sector JSON). Show it while you rebuild the location, compare your build against it (unchanged/moved/changed/missing/added), and copy or snap to the original pieces. See [REFERENCE-AREAS.md](REFERENCE-AREAS.md).

v0.67.0 adds vanilla-world clone/import. Point at existing vanilla nodes (RedHotTools crosshair or area scan) and import them as editable project objects. The clones keep their real mesh/decal/effect/template resources, appearances and transforms, and the originals can optionally be hidden (reversibly) so the clones replace them. For exact rotation and scale, the importer reads a WolvenKit-exported sector JSON. See [VANILLA-CLONE.md](VANILLA-CLONE.md).

v0.66.0 adds a cinematic timeline editor. You can place camera cuts and moves, NPC positions and animations, look-at targets, dialogue timing, light/VFX/audio events and quest facts on one timeline. You can preview it in game with full restore on stop, and export a structured scene handoff (shot list, cues, dialogue script and CSV cue sheet, facts, resolved references) for `.scene` authoring. See [TIMELINE.md](TIMELINE.md).

v0.65.0 adds persistent editable splines: control points with Bezier handles (auto/aligned/free/linear), open or closed curves, arc-length spacing and a live in-world preview. One spline drives cables, fences, roads, object distribution, NPC routes, camera paths and a native World Builder spline node, and every use regenerates after the curve is edited. See [SPLINES.md](SPLINES.md).

v0.64.0 adds a layer manager with dedicated Architecture, Props, Gameplay, NPC, Lighting, Audio, Quest and Debug layers. Layers can be hidden or shown (live objects despawn and respawn), locked (edits refused), isolated, selected, colour-labelled in the hierarchy and excluded from export; objects can be moved to a layer or auto-assigned by what they are. See [LAYERS.md](LAYERS.md).

v0.63.0 adds occlusion and visibility helpers. It authors World Builder Static Occluders (box and one- or two-sided planes), including one-click occluders on a room's solid wall spans that leave doors and windows open. It computes the rooms each saved camera can potentially see, from authored walls, openings and occluders with an optional live ray cross-check, and flags large meshes no camera can see that are still active. Visibility volumes are not exposed by World Builder and are reported as unsupported. See [OCCLUSION-VISIBILITY.md](OCCLUSION-VISIBILITY.md).

v0.62.0 adds a streaming/performance analyzer. Per room, premise and exported sector it counts nodes, lights, audio emitters, decals, VFX, dynamic entities and expensive resources, and computes a weighted relative cost. It reports budget overruns and distance from V, finds unusually dense clusters (median/MAD on a 5 m grid) and heavily overlapping lights, and can select a cluster's objects. See [PERFORMANCE-ANALYZER.md](PERFORMANCE-ANALYZER.md).

v0.61.0 adds a streaming-sector inspector for World Builder exports. It shows each node's sector, variant, NodeRef, device/PSID and references, sector bounds and counts, and cross-sector NodeRef/device references. It flags nodes likely in the wrong sector (outside their sector box and inside another, or far from the rest of their sector), duplicate PSIDs and orphan devices, and maps flags back to project objects in Spatial → Sectors. See [SECTOR-INSPECTOR.md](SECTOR-INSPECTOR.md).

v0.60.0 adds collision authoring. It places and edits real World Builder collision boxes, capsules and spheres, imported collision meshes, and boxes fitted to object bounds. Each has a collision layer (preset with its physics groups), a physics material and a wireframe visualization toggle. A player/NPC passability preview draws a blocked/free map and routes from the saved colliders, optionally cross-checked with live collision rays. See [COLLISION-AUTHORING.md](COLLISION-AUTHORING.md).

v0.59.0 adds deterministic screenshot mode for visual regression. It forces a saved environment, hides the HUD and turns off motion blur and other post effects through game settings (each previous value is restored). It also waits for streaming around each camera, freezes NPCs and traffic while shooting, and keeps only a frame that matches the next one. Settings missing from the running build are reported, not faked. See [VISUAL-REGRESSION.md](VISUAL-REGRESSION.md#deterministic-screenshot-mode).

v0.58.0 adds saved authoring environments: time, weather (which sets rain) and an optional World Builder fog volume, previewed live and optionally forced so the clock and weather stay put. Restore returns the original time and hands weather back to the game cycle. Visual-regression captures can force an environment and flag baselines shot under different conditions. Exposure has no verified CET control and is stored as a note only. See [ENVIRONMENT-PREVIEW.md](ENVIRONMENT-PREVIEW.md).

v0.57.0 adds a VFX / particle editor: search World Builder's loaded Particles and Effects catalogs by keyword category (smoke, steam, sparks, holograms, fire, dust, leaks, electrical, weather), preview one live effect that follows the aim point, then place it with roll/pitch/yaw, optional surface alignment, particle emission rate, and scale. Scale is written to the native node by Build Mod because World Builder previews particles/effects at 1:1. See [VFX.md](VFX.md).

v0.56.0 adds named fact-driven world-state variants. Preview or apply states such as `before_quest`, `destroyed`, or `cleaned`; assign placed assets to show/hide; resolve overlapping states by priority; optionally enable live automatic switching as quest facts change. This switches tracked LocationStudio entities and does not compile native REDengine world-state or quest resources. See [WORLD-STATE-VARIANTS.md](WORLD-STATE-VARIANTS.md).

v0.49.0 adds patrol, alert, and combat route editing linked directly to persistent NPC population points. Quest Forge receives ordered waypoint, looping, wait/facing/speed, workspot-transition, and conditional-branch data. Native REDengine movement and AI execution still needs compatible community/quest resource wiring. See [NPC-AI-ROUTES.md](NPC-AI-ROUTES.md).

v0.48.0 adds persistent Character.* population points through World Builder Entity Records, editable native spawn/streaming settings, temporary in-game preview, MCP operations, a Quest Forge handoff, and a native export audit. Character attitude/faction/AI/quest conditions remain explicit handoff metadata pending a compatible native profile pipeline. See [NPC-POPULATION.md](NPC-POPULATION.md).

v0.47.0 adds build-time TweakXL loot-table generation from explicit interactable item rows and reports native World Builder sector/device/persistent-state resources. Build Mod now validates these artifacts before CR2W conversion. Door/fact controller behavior still requires compatible tested native entity/profile data; see [INTERACTABLES.md](INTERACTABLES.md).

v0.46.0 added an explicit Runtime Sync report/action after project load, undo/redo, checkpoint restore, and detected live edits. It updates or removes tracked spawned entities without spawning every saved project object. See [RUNTIME-SYNC.md](RUNTIME-SYNC.md).

v0.45.0 adds named project snapshots, object-level diffs, and undoable project restore. See [PROJECT-CHECKPOINTS.md](PROJECT-CHECKPOINTS.md).

v0.43.0 added World Builder static audio emitters and room ambient/reverb zones. See [AMBIENT-AUDIO.md](AMBIENT-AUDIO.md). v0.42.0 added a live World Builder mesh appearance picker and searchable placement of real game decal materials. Requires a spawned World Builder static mesh for appearance listing/preview and World Builder's loaded Decals catalog for decal placement. See [MESH-APPEARANCES-AND-DECALS.md](MESH-APPEARANCES-AND-DECALS.md).

v0.41.0 adds World Builder Static Light placement, color/intensity/radius/flicker tuning, presets, and game-clock preview/restore. See [LIGHTING.md](LIGHTING.md).

v0.40.0 adds authoring and placement for doors, loot containers, shards, and items, including item/loot records, lock state, and quest fact handoff. The fields are saved and exported; completing working interaction callbacks still requires the correct native `.ent`, persistent-state, streaming-sector, and quest resources. See [INTERACTABLES.md](INTERACTABLES.md).

v0.39.0 adds an in-game and MCP floor/clearance grid route estimate for V and NPCs, with likely Dynamic collision blockers. It is not an engine navmesh result. See [WALKABILITY.md](WALKABILITY.md).

v0.38.0 adds saved sit/lean/terminal NPC workspots and temporary stand-in preview. See [NPC-WORKSPOTS.md](NPC-WORKSPOTS.md).

v0.37.0 adds Quest Forge handoff: connect gameplay volumes to named quest facts, export marker/mappin/spot world coordinates and quest manifest NodeRefs, and carry explicit coordinate provenance. See [QUEST-FORGE-LINKS.md](QUEST-FORGE-LINKS.md).

v0.36.0 added named local room frames. Create an origin and rotated `u/v` axes, then place or move objects using local `u/v/z` coordinates. See [WB-ROOM-FRAMES.md](WB-ROOM-FRAMES.md).

v0.35.0 adds `hotcycle_rebuild` and `mcp_server/hotcycle.py` for deploying a rebuilt redscript, waiting for RedHotTools compilation, hot-loading archives, and then respawning tagged entities. A changed pose in `.reds` must be deployed before `SyncProps`; without it the old pose returns. See [WB-HOTCYCLE.md](WB-HOTCYCLE.md).

v0.34.0 adds the prop validators `wb_clipcheck`, `wb_fixturecheck`, and `wb_fitcheck`. See [WB-PROP-VALIDATORS.md](WB-PROP-VALIDATORS.md) for working examples, data requirements, and limitations.

v0.33.0 adds four read-only project browsing tools: `wb_find`, `wb_tree`,
`wb_get`, and `wb_refs`. They search saved records, browse their hierarchy,
fetch an item by ID, and list explicit project relationships. See
[WB-PROJECT-BROWSER.md](WB-PROJECT-BROWSER.md) for types and examples.

v0.32.0 adds `wb_collisions` for conservative bounds-based overlap checks and
`wb_compat_scan` for loaded CET integrations plus a read-only installed-mod
inventory. These tools do not claim to inspect REDengine physics or opaque
archive conflicts. See [WB-COMPATIBILITY.md](WB-COMPATIBILITY.md).

v0.31.0 adds path, radial and grid array MCP tools for editable placed objects.
`wb_align` and `wb_distribute` expose existing LocationStudio selection layout
behavior. See [WB-ARRAYS.md](WB-ARRAYS.md) for semantics and examples.

v0.30.0 adds deterministic polygon, saved-volume and live-surface scatter MCP
tools, plus `wb_rng_create` for reproducible seed generation. See
[WB-SCATTER-TYPES.md](WB-SCATTER-TYPES.md) for inputs, limitations and examples.

The v0.24.0 Scene Director turns scene collections into a practical engine-style workflow. Capture
the active location or current selection, keep an editing scene while selecting
other objects, add/remove members without deleting them, synchronize location
content, and activate, isolate, or deactivate the scene through real CET and
World Builder runtime ownership.

v0.28.0 adds asset-backed cable, fence, road and market layout generators.
These create ordinary editable project objects from imported World Builder
Static Meshes; they do not synthesize geometry or invent game resource paths.
Cable, fence and road fit their repeated segments using authored asset bounds.
The new `wb_generate_noderef` creates a saved semantic marker only: native
REDengine nodes still require a compatible World Builder build template and
the supported build/import pipeline.

v0.27.0 added real in-game prefab thumbnails to the existing persistent,
editable asset bounds and native World Builder Favorites workflows. The new
`wb_prefab_render` operation temporarily spawns saved prefab members through
their live backends, captures the game frame, removes the temporary objects,
and stores a PNG on the prefab record.

v0.26.0 combines persistent, editable local-space bounds with native World
Builder Favorites support. Favorite addition is preview-only by default, checks
the live World Builder resource catalog, and writes the native Favorites JSON
only when `write=true` is explicitly requested. Existing category JSON is
backed up and unknown fields are preserved.

v0.25.0 added persistent, editable local-space bounds to Project Assets. Bounds
can be imported as a validated manifest, tuned through MCP, used to calculate
fit scales, transformed into world AABBs, and checked for pairwise overlap.
This is authoring math; it does not create or modify the game's collision mesh.

Start with [FIRST-RUN.md](FIRST-RUN.md), then the guides for [device logic](DEVICE-LOGIC.md), [navigation graphs](NAVIGATION.md), [cover nodes](COVER-NODES.md), [combat encounters](COMBAT-ENCOUNTERS.md), [NPC patrol routes](NPC-AI-ROUTES.md), [NPC population](NPC-POPULATION.md), [mesh appearances and decals](MESH-APPEARANCES-AND-DECALS.md), [lighting](LIGHTING.md), [VFX / particles](VFX.md), [environment & weather preview](ENVIRONMENT-PREVIEW.md), [collision authoring](COLLISION-AUTHORING.md), [sector inspector](SECTOR-INSPECTOR.md), [performance analyzer](PERFORMANCE-ANALYZER.md), [occlusion & visibility](OCCLUSION-VISIBILITY.md), [layers](LAYERS.md), [splines](SPLINES.md), [cinematic timeline](TIMELINE.md), [vanilla clone/import](VANILLA-CLONE.md), [reference areas](REFERENCE-AREAS.md), [asset dependencies](ASSET-DEPENDENCIES.md), [shipping preflight](PREFLIGHT.md), [Environment Definition Language](ENVIRONMENT-DEFINITION-LANGUAGE.md), [procedural geometry](PROCEDURAL-GEOMETRY.md), [interactables](INTERACTABLES.md), [walkability checks](WALKABILITY.md), and [NPC workspots](NPC-WORKSPOTS.md). Read [WB-ASSET-BOUNDS.md](WB-ASSET-BOUNDS.md)
for bounds manifests and calculations, [WB-FAVORITES.md](WB-FAVORITES.md) for
native favorite workflows, [WB-PREFAB-THUMBNAILS.md](WB-PREFAB-THUMBNAILS.md)
for capture requirements, [WB-ARRAYS.md](WB-ARRAYS.md) for arrays and layout,
[WB-COMPATIBILITY.md](WB-COMPATIBILITY.md) for collision and compatibility
scans, [WB-PROJECT-BROWSER.md](WB-PROJECT-BROWSER.md) for project browsing,
and [WB-DEVICE-WIRING.md](WB-DEVICE-WIRING.md) for device connections
and elevator limitations. For Quest Forge fact links and coordinate handoff, see
[QUEST-FORGE-LINKS.md](QUEST-FORGE-LINKS.md). Learn the JSON format in
[AUTHORING-PLANS.md](AUTHORING-PLANS.md), and use the safe Claude workflow in
[MCP-EXAMPLES.md](MCP-EXAMPLES.md). Runtime problems are routed in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md). See [WB-GENERATORS.md](WB-GENERATORS.md)
for asset-backed cable, fence, road, market and NodeRef tools.

## What changed in v0.44.0

- Added `visual_regression_capture` to screenshot all or selected enabled saved cameras and diff against the last accepted run.
- Added `visual_regression_accept` so baseline changes require an explicit review/action.
- Added optional `hotcycle_rebuild(capture_visuals=true)` integration to run comparisons after archive load and tagged respawn.
- Added local PNG diff heatmaps and manifests without adding a Python image-library dependency.

## What changed in v0.43.0

- Added searchable point audio emitters and rotated room-footprint Ambient Areas with linked Outline Markers.
- Added MCP tools `create_audio_emitter` and `create_room_reverb_zone`.
- World Builder native export groups the outline markers with the ambient area and rejects zones without all four outline markers. Room reverb requires a native world edit export; it is not previewed by CET.

## What changed in v0.42.0

- Added in-place preview/apply/revert for appearances returned by an actual spawned World Builder static mesh.
- Added `.mi` decal catalog search and native decal node placement at the camera ray hit.
- Added five MCP operations: list, preview, apply, cancel mesh appearance, and create decal.
- Added targeted runtime contract coverage. The harness verifies data flow and calls, not REDengine rendering.

## What changed in v0.41.0

Adds Static Light placement through World Builder, live tuning with respawn, six built-in lighting presets, and CET game-clock preview/restore. See [LIGHTING.md](LIGHTING.md) for requirements and MCP examples.

## What changed in v0.40.0

- Added Interactables authoring for doors, loot containers, shards and items, using registered game entity assets.
- Saved validated `Items.*`, `LootTables.*`, lock state, and fact/value fields on placed objects.
- Added MCP create/list/update/delete tools and Quest Forge `interactable_handoff` export.
- Kept native interaction setup explicit: CET metadata does not modify `.ent` components, loot tables, streaming-sector persistent state, or interaction callbacks.
- Added runtime validation, edit, placement, export-handoff, and mesh-only rejection coverage.

## What changed in v0.37.0

- Added an in-game Quest Forge fact field for trigger volumes and MCP tool `link_volume_to_quest_fact`.
- Expanded Quest Forge export with a world-sector fragment, manifest `locations` NodeRefs, marker/mappin/spot coordinates, and fact-linked trigger records.
- Player-captured points are marked verified; manually entered points remain unverified until an author confirms they are standable in game.
- Export validates linked fact identifiers and never passes an invalid fact name into the handoff.
- Added focused runtime coverage for handoff structure, fact validation, trigger half-extents, and coordinate export.

## What changed in v0.36.0

- Added persistent room frames with explicit origin and validated orthonormal local axes.
- Added frame creation/list/update/delete and local/world coordinate conversion tools.
- Added local-coordinate object placement and movement tools; existing objects keep world transforms when a frame changes.
- Bumped project schema to 14 and added rotated-frame, round-trip, placement, movement, and validation tests.

## What changed in v0.35.0

- Added `hotcycle_rebuild` and a Linux-friendly `hotcycle.py` CLI wrapper.
- Script deployment is backed up and forces a RedHotTools compile confirmation even when file bytes already match, before archive reload and optional respawn.
- Respawn requires the changed `.reds` source by default; using the installed script requires an explicit stale-pose acknowledgement.
- Checked for `wb_live_paths` in the current project and supplied files; no definition was available to implement safely. Existing path arrays and routes remain available.

## What changed in v0.34.0

- Added `wb_clipcheck` for bounds-based prop-to-prop intersections.
- Added live `wb_fixturecheck` and `wb_fitcheck` probes using read-only Static collision raycasts.
- Added direct validator buttons in Advanced Tools for project overlap and selected-prop live checks.
- Documented the bounds proxy, static-only limits, scan caps, and MCP examples in `WB-PROP-VALIDATORS.md`.

## What changed in v0.33.0

- Added `wb_find` with type filtering and bounded offset pagination over saved project records.
- Added `wb_tree` with collection, premise, room, group, scene, and route browsing plus depth/node limits.
- Added `wb_get` for complete item data and `wb_refs` for known inbound/outbound references.
- Added reference, pagination, hierarchy, and input-validation regression coverage.

## What changed in v0.32.0

- Added `wb_collisions` to scan project, premise or selected placed objects using imported bounds.
- Added `wb_compat_scan` for loaded integration states, project resource readiness, and installed mod folder inventory.
- Reports missing bounds and skipped objects; documents false positives and uninspected archive contents.
- Added regression coverage for AABB intersections, missing bounds, integration status, and installation inventory.

## What changed in v0.31.0

- Added `wb_path_array`, `wb_radial_array` and `wb_grid` for grouped copies of editable placed objects.
- Added `wb_align` and `wb_distribute` as MCP aliases over the existing `layout_object_selection` implementation.
- Arrays enforce finite geometry, same-location selections and a 100-created-object limit; each successful operation creates one undo step.
- Added path sampling, radial/grid placement, invalid-input and bridge alias regression coverage.

## What changed in v0.30.0

- Added uniform scatter inside validated non-crossing world XY polygons,
  including optional ground projection.
- Added deterministic sampling inside enabled box, sphere and cylinder volumes,
  respecting volume position, dimensions and rotation.
- Added live-surface scatter using a real crosshair hit and per-copy raycasts
  across Static, Terrain and Dynamic groups; misses fail before creation.
- Added `wb_rng_create` with a reproducible Park-Miller seed and sample preview.
- Added regression coverage for area containment, seed repetition, surface
  misses, invalid polygons and scatter runtime behavior.

## What changed in v0.25.0

- Added normalized resource-local AABB metadata (`min`/`max`, meter units,
  source, center and extents) with strict finite/positive validation.
- Added `wb_bounds_import`, `wb_bounds_info`, and `wb_bounds_set`, plus fit,
  world-AABB, and pairwise-overlap calculations over stored bounds.
- Bounds edits propagate to objects placed from the matching Project Asset;
  placement/stamp copies retain an asset ID so later corrections stay linked.
- Added one-undo manifest import, dry-run validation, bridge routing, six MCP
  tools, a bounds manifest example, and focused Lua runtime coverage.
- Bounds are conservative AABB math only; no game collider or mesh is generated.

## What changed in v0.29.0

- Added `wb_device_connect` to create reciprocal device-resource graph links.
- Added `wb_elevator_wire` with lift/terminal class checks and ordered floor
  links. See [WB-DEVICE-WIRING.md](WB-DEVICE-WIRING.md) for examples and scope.
- Added atomic-write and invalid-input tests. Elevator NodeRefs, markers,
  persistent instance data and WolvenKit build/import still require setup.

## What changed in v0.28.0

- Added `wb_generate_cable`, `wb_generate_fence`, `wb_generate_road`,
  `wb_generate_market`, and `wb_generate_noderef` with MCP bridge routing.
- Cable/fence/road generation requires imported Static Mesh assets with
  positive resource-local bounds and creates individually editable objects.
- Generators validate paths, dimensions, limits and World Builder runtime
  readiness; live spawn failures are returned explicitly per object.
- NodeRef generator creates authoring metadata, not native streaming-world data.
- Added examples, in-game checks and Lua runtime tests for all five tools.

## What changed in v0.27.0

- Added `wb_prefab_render(prefab_id, distance)` to render actual saved
  LocationStudio prefab members through World Builder/CET, capture the game
  frame, clean up temporary instances, and persist thumbnail metadata.
- Added a Prefabs-panel **RENDER THUMB** control and cached thumbnail display.
- Screenshot completion/timeout/error paths restore the editor and attempt
  cleanup; failed World Builder removal remains observable and retries.
- Added platform capture delay support, in-game/MCP usage docs, and a runtime
  regression test for rendering, cleanup, persistence, and non-destructive data.

## What changed in v0.26.0

- Added MCP tools `wb_favorite_add` and `wb_favorites_list` for World Builder's
  own `entSpawner/data/favorite/*.json` files, distinct from LocationStudio's
  Project Asset favorite flag.
- Favorite add defaults to preview; `write=true` is required to commit. The
  candidate is serialized from the live World Builder class/catalog and is not
  spawned into the world or imported into the LocationStudio project.
- Existing category JSON receives a timestamped backup and atomic replacement;
  unknown category fields are retained. Duplicate category names are rejected.
- Added a native Favorites guide and filesystem safety/regression tests.

## What changed in v0.24.0

- Added the in-game **SCENE DIRECTOR** with distinct editing/live scene state,
  membership counts, location/selection capture, selection add/remove, location
  resynchronization, activation, isolation, deactivation, and object selection.
- Capturing a location includes its rooms, ordinary placed assets, trigger
  volumes, and cameras. Room-kit construction remains owned through the room by
  default instead of being duplicated into explicit object membership.
- Editing-scene state survives selecting other rooms, props, points, volumes,
  cameras, and routes, so membership buttons operate on the intended scene.
- Activation spawns room shells and explicit objects through their real backend.
  Isolation removes other tracked project objects first. Deactivation preserves
  all project data and refuses scene deletion if runtime cleanup fails.
- Semantic location/route membership is preserved when location content is
  resynchronized because those global items cannot be inferred from premise id.
- Added `capture_scene`, `edit_scene_members`, `deactivate_scene`, and
  `isolate_scene` to declarative plans; seven MCP tools, four CET hotkeys, bridge
  operations/status, diagnostics, structured logs, and a captured-scene example.
- The MCP server now exposes 147 tools. All 32 isolated suites pass on Lua 5.1
  and LuaJIT 2.1, including forced World Builder cleanup-refusal coverage.

## What changed in v0.23.0

- Added schema-13 first-class **Scenes** that reference real rooms, placed
  objects, locations, volumes, cameras, and routes without duplicating them.
- Added 14 plan operations with `$alias` references, player/camera/explicit
  origins, exact or unambiguous asset resolution, 100-step validation, live
  spawning through existing CET/World Builder backends, and one-undo commit.
- Added full rollback of model, runtime ownership, history, selection, and dirty
  state. Cleanup refusal enters a visible recovery mode that blocks save,
  export, history, autosave, new plans, and unrelated MCP mutations.
- Added **HELP + START** with live dependency badges, a real spawn test, three
  executable examples, JSON file validation/execution, recovery actions,
  first-time instructions, and debug-report creation.
- Added scene hierarchy/inspector activation and object-selection controls,
  plan/scene diagnostics, structured logs, two CET hotkeys, three JSON examples,
  and four focused manuals.
- Expanded the MCP server to 140 tools, including complete plan lifecycle,
  scene lifecycle, asset resolution, safe plan-file writing, and rollback
  recovery.
- Added an isolated authoring-plan/scene/recovery/UI/MCP/log test. All 31 suites
  pass on Lua 5.1 and LuaJIT 2.1; the Python MCP server compiles and its static
  contract test passes.

## What changed in v0.22.0

- **Stamp placement** now opens a real transaction. **STAMP NOW** creates and
  live-spawns an owned object but does not dirty, save, or add undo history until
  the stroke is committed.
- Added a persistent **STAMP STROKE ACTIVE** toolbar with live object count,
  spacing, **STAMP NOW**, **COMMIT STROKE**, and **CANCEL STROKE** controls.
- One commit creates exactly one undo entry for the complete painted stroke.
  Cancel removes every World Builder/direct CET runtime object, removes the
  authored copies, and restores the prior selection and dirty state.
- Minimum spacing is enforced inside the transaction. A rejected overlapping
  click creates neither a project object nor a runtime request.
- Runtime-removal refusal keeps the stroke active and preserves authored
  ownership, preventing an untracked live entity from being left in the game.
- Temporary previews no longer mark the project dirty or increment asset-use
  history. Asset usage is recorded only when a non-empty stroke commits.
- Save, export, undo/redo, Transform Edit, and unrelated MCP mutations are
  blocked while a stroke is active. Closing CET or shutting down cancels an
  uncommitted stroke.
- Existing **Stop Stamp** behavior is upgrade-compatible: the hotkey and MCP
  `stop_asset_preview` now commit the stroke. A separate cancel hotkey and
  `cancel_stamp_stroke` tool provide explicit rollback.
- Added stroke status/commit/cancel bridge operations, three MCP tools,
  diagnostic state, and structured `[stamp:stroke]` logs.
- All 30 isolated suites pass on Lua 5.1 and LuaJIT 2.1; the MCP server exposes
  123 tools and passes Python compilation.

## Transactional Stamp workflow

1. Select a Project Asset and an active location, then enable **Stamp
   placement** and press **START STROKE**.
2. Aim the live preview and press **STAMP NOW** or the stamp hotkey. Move at
   least the configured spacing before adding the next object.
3. Continue painting. Every accepted object is immediately visible through its
   real World Builder or direct CET backend, while the project remains unsaved.
4. Press **COMMIT STROKE** for one undoable creation, or **CANCEL STROKE** to
   remove the entire uncommitted stroke and restore the previous selection.
5. If cancellation reports a runtime-removal refusal, do not reload or delete
   project data. Create a debug report, resolve the backend issue, and retry
   cancel so LocationStudio keeps ownership of the live object.

## v0.21 Placement + Edit foundation

v0.21.0 replaced the default fire-and-forget asset placement and object
Duplicate-at-Aim paths with a live Placement + Edit transaction. Place any
Project Asset—or copy a complete placed assembly—to the crosshair, player, or
active preview; refine the visible result, then commit once or cancel it fully.

## What changed in v0.21.0

- Project Asset cards now use **PLACE + EDIT** by default. If that asset already
  has a live preview, its exact preview transform is handed into the transaction;
  otherwise the active-camera crosshair ray is used.
- Added aim, player, preview, and explicit-transform placement modes, optional
  surface-normal alignment, surface offset, artist yaw, and precise target data
  in session diagnostics.
- Added **AIM COPY + EDIT** for one placed object or a complete multi-selection.
  The copied assembly preserves source spacing and height offsets around its
  center pivot, with an optional group yaw delta.
- Every created object spawns through its real World Builder or direct CET `.ent`
  backend before editing. Imported meshes, entities, lights, collision and other
  saved World Builder resources retain their resource metadata.
- Placement plus every final Transform Edit adjustment is exactly one undo
  operation. Cancel removes every runtime/project copy and restores the previous
  object or asset selection without dirtying a clean project.
- A failed runtime removal keeps the transaction active and retains authored
  ownership, preventing silent orphan entities.
- Repaired the legacy object `duplicate_at_aim` command as a transactional
  auto-commit compatibility wrapper; semantic locations, cameras and volumes
  retain their existing immediate duplication behavior.
- Added compact Asset/Inspector controls, Advanced Tools controls, a CET hotkey,
  `start_placement_edit`, bridge coverage, and `[transform:placement]` logs.
- Added validation so Placement and Scatter reject unrelated/stale selection
  types instead of accidentally using an older object group.
- All 29 isolated suites pass on Lua 5.1 and LuaJIT 2.1.

## Placement + Edit workflow

1. Select a Project Asset, or select one/more already placed objects.
2. For an asset, press **PLACE + EDIT** on its card or in the Inspector. Preview
   the asset first if you want to transfer the exact preview orientation.
3. For placed objects, press **AIM COPY + EDIT**. A multi-selection is copied as
   one assembly around its center pivot.
4. The real copies appear and enter the yellow **PLACEMENT EDIT ACTIVE** toolbar.
   Use world/local movement, yaw, supported World Builder scale, or reset.
5. Press **COMMIT** for one undoable creation, or **CANCEL** to despawn/remove all
   copies and restore the source selection.

## v0.20 Transactional Scatter foundation

## What changed in v0.20.0

- Added deterministic scatter generation with an explicit seed, uniform disk
  distribution, optional random yaw, exact radius/count/distance inputs, and a
  reproducible point list in session diagnostics.
- Added placed-object, multi-selection, and Project Asset sources. Imported
  World Builder resources retain their real resource metadata; direct `.ent`
  assets keep using CET entity spawning.
- Multi-object stamps preserve the source assembly's spacing and height offsets
  around a center pivot while each repeated stamp receives one coherent yaw.
- Optional ground placement raycasts every stamp center before project mutation.
  If any required ground ray misses, the operation fails without creating
  partial project objects or invisible runtime leftovers.
- Every copy is visible through its actual backend before commit and enters the
  existing Transform Edit toolbar. Creation plus final movement is one undo
  state; cancel removes every copy and restores the previous object or asset
  selection.
- A backend removal refusal keeps the session active and keeps project ownership
  instead of silently orphaning a live game object.
- Repaired the older `scatter_at_aim` MCP operation as a compatibility wrapper:
  it now uses the same transaction engine and auto-commits exactly one undo step.
- Added compact Inspector/Asset controls, exact Advanced Tools controls, a CET
  hotkey, `start_scatter_copy_edit`, bridge coverage, and structured
  `[transform:scatter]` / `[ent_tools:scatter]` logs.
- Fixed creation-session argument mutation, so a cancelled operation can be
  repeated safely with the same caller arguments.
- All 28 isolated suites pass on Lua 5.1 and LuaJIT 2.1.

## Scatter workflow

1. Select a placed object, a complete multi-object set, or a saved Project Asset.
2. For saved defaults, press **SCATTER** / **SCATTER + EDIT** in the Inspector.
   For exact Count, Radius, Aim Distance, Seed, Random Yaw and Ground settings,
   open **Advanced Tools → Duplicate / Pattern / Scatter**.
3. The editor resolves the crosshair hit, calculates every deterministic stamp,
   completes all requested ground raycasts, and spawns the real copies.
4. Use the yellow **SCATTER EDIT ACTIVE** toolbar to move, yaw, or reset the
   complete result.
5. Press **COMMIT** for one undoable creation or **CANCEL** to remove every copy
   and return to the source selection.

## v0.19 Pattern Placement foundation

## What changed in v0.19.0

- Added transactional linear patterns for single assets and complete selections,
  with 3D step distance, per-repetition yaw, world/local axes, and center/active
  source pivots.
- Added Mirror X/Y copy placement around the active location origin. This mirrors
  position and orientation; it does not pretend CET supports negative-scale mesh
  geometry.
- Every pattern copy spawns through its actual World Builder or direct CET `.ent`
  backend before commit and enters the existing Transform Edit workbench.
- Pattern creation plus final transform is exactly one undo state. Cancel,
  overlay close, or shutdown removes every created object and restores the source
  selection without dirtying the project.
- Repaired the legacy Array/Mirror builder and MCP commands: they now live-spawn,
  detach room-kit ownership, and auto-commit as one operation instead of writing
  one history snapshot per copy or leaving invisible project-only objects.
- Added a 100-object transaction limit and explicit rejection of zero-step
  overlapping patterns.
- Added compact Inspector/Scene controls, exact Advanced Tools inputs, three CET
  hotkeys, two MCP tools, session diagnostics, and `[transform:pattern]` /
  `[transform:mirror]` logs.
- All 27 isolated suites pass on Lua 5.1 and LuaJIT 2.1.

## Pattern Placement workflow

1. Select one object or a complete object set.
2. For a quick two-step pattern, press **ARRAY** in the Inspector or
   **ARRAY + EDIT** in Scene. For exact count, XYZ step, and yaw step, use
   **Advanced Tools → Duplicate / Pattern / Scatter**.
3. Use **MIRROR X** or **MIRROR Y** to reflect copies around the location origin.
4. The live copies enter the yellow **ARRAY EDIT ACTIVE** or **MIRROR EDIT
   ACTIVE** toolbar. Make any final world/local transform adjustments.
5. Press **COMMIT** for one undoable creation, or **CANCEL** to remove all copies
   and return selection to the source objects.

## v0.18 Duplicate + Edit foundation

## Duplicate + Edit workflow

1. In **SCENE**, select one placed object or a complete multi-object set.
2. Press **DUPLICATE + EDIT** (or **DUPLICATE SET** in the multi-object panel).
3. Use the persistent X/Y/Z and rotation controls to position the live copies.
4. Press **COMMIT** to save creation and placement as one undo step, or
   **CANCEL** to despawn and remove all copies and reselect the originals.

Mixed World Builder + direct CET selections are supported for translation and
rotation. Scale remains unavailable for a mixed selection because CET entity
spawning has no reliable live scale contract.

## v0.17 Transform Edit foundation

## Transform Edit workflow

1. In **SCENE**, select one live object or construct a multi-object set.
2. Press **EDIT TRANSFORM** or **EDIT SELECTION**.
3. Choose world/local axes and set the move, angle, and scale increments.
4. Use the X/Y/Z controls, Roll/Pitch/Yaw controls for a single object, or Yaw
   for a group. World Builder updates in place; direct CET entities respawn at
   each accepted transform.
5. Press **RESET** to return to the session start without closing it, **COMMIT**
   for one undoable operation, or **CANCEL** for an exact runtime restoration.

Scaling appears only for all-World-Builder selections. Closing the CET overlay
or shutting down the mod cancels an unfinished transaction.

## v0.16 reversible Grab Move foundation

- Added **Grab With Crosshair** for one object and **Grab Selection** for complete
  multi-object sets. Relative spacing and height offsets are preserved around a
  center or active-object pivot.
- World Builder resources update continuously through their existing live
  handles. Direct CET `.ent` objects use the stable spawner path and refresh once
  at commit; the UI reports both backend counts instead of pretending both have
  the same live-transform capability.
- Added session controls for grid snapping, single-object surface alignment,
  aim distance, and incremental yaw rotation.
- **Commit Move** creates exactly one undo state. **Cancel Move**, closing the CET
  overlay, or shutdown restores every original transform and live handle.
- Autosave, manual save, export, history, and unrelated MCP mutations are blocked
  while a session is unfinished, preventing a temporary crosshair position from
  becoming project data.
- Added five CET hotkeys and five MCP tools for starting, configuring, inspecting,
  committing, and cancelling grab sessions.
- Added transform-session state to bridge status, diagnostics, support reports,
  and structured logs.
- All 24 isolated suites passed on Lua 5.1 and LuaJIT 2.1.

## Grab Move workflow

1. In **SCENE**, select one object or build a multi-object selection.
2. Press **GRAB WITH CROSSHAIR** or **GRAB SELECTION**.
3. Aim at the destination. World Builder objects follow live; CET entity objects
   display their new project transform and respawn at it when committed.
4. Optionally enable **Surface align** for one object, enable **Grid snap**, or
   use **YAW − / YAW +**. Groups retain their original roll/pitch and layout.
5. Press **COMMIT MOVE** to create one undo step, or **CANCEL MOVE** to restore
   the exact original transforms.

The editor will not save or export while Grab Move is active. Closing the CET
overlay cancels the session deliberately.

## v0.15 aim/surface/stamp foundation

- Added **Pick Aimed Object** to the default Scene workspace. It projects every
  eligible saved project object onto the active camera ray, selects the closest
  match inside the configured radius, and focuses its tracked World Builder
  handle when available.
- Added configurable pick distance/radius and a dedicated CET hotkey. Hidden,
  disabled, out-of-premise, and out-of-range objects are excluded.
- Added **Align preview to surface**. Raycast normals drive preview roll/pitch,
  the normal offset remains respected, and lack of a real hit produces an
  explicit warning instead of claiming alignment.
- Added **Stamp placement** with a persistent following preview, one-click/hotkey
  instance commits, a placed counter, and minimum-distance protection against
  duplicate clicks at the same position.
- Every stamped item is a normal saved LocationStudio object using the same CET
  entity or World Builder resource metadata and spawn path as ordinary placement.
- Added four MCP tools for picking, previewing, stamping, and stopping preview.
- Picker, surface alignment, stamp spacing, UI reachability, diagnostics, and
  log records are covered by a new runtime suite. All 23 suites pass on Lua 5.1
  and LuaJIT 2.1.

## Aim and stamp workflow

1. Open **ASSETS → MY ASSETS** and select a registered game entity or imported
   World Builder resource.
2. Enable **Align preview to surface** for walls, slopes, or ceilings when the
   asset's authored local-up axis supports it.
3. Enable **Stamp placement**, choose the minimum spacing, and press
   **START STROKE**.
4. Aim at the world and press **STAMP NOW**, or bind the LocationStudio stamp
   hotkey in CET. Move farther than the spacing value before the next stamp.
5. Press **COMMIT STROKE** for one undo entry, or **CANCEL STROKE** to remove
   the entire uncommitted stroke. The legacy stop-stamp hotkey commits.
6. In **SCENE**, aim at an already saved object and press **PICK AIMED OBJECT**.
   Use the Inspector or World Builder gizmo to edit the resulting selection.

Aim picking operates on LocationStudio's saved project objects. It does not
claim to select arbitrary unregistered Night City entities. Surface rotation
aligns the asset's local up axis; resources authored around a different axis may
need a corrective rotation in the Inspector.

## v0.14 precision-layout foundation

- Added X/Y/Z alignment using minimum, center, maximum, or the active object's
  pivot.
- Added even X/Y/Z distribution while preserving the first and last objects.
- Added match-to-active rotation and World Builder scale.
- Added one-click selection snapping using the project's grid and angle values.
- Added batch asset replacement. Live instances are removed safely, resource
  metadata is changed once, and previously live objects are spawned again through
  the correct CET or World Builder backend.
- Room construction sets reject non-mesh replacement assets, collision pieces
  remain protected, locks are enforced, and unsupported CET live scale is still
  reported instead of faked.
- Persistent group pivots recalculate after precision layout unless the group
  intentionally uses a custom pivot.
- Added two MCP precision-layout tools and full live-runtime regression coverage.

## v0.13 group and prefab foundation

- Added persistent **Groups** to the Scene hierarchy. Groups can contain real
  placed objects, nest under other groups, select recursively, and dissolve
  without deleting their contents.
- Added **center**, **active-object**, and **custom** pivot modes to multi-object
  transforms. A custom pivot can be captured from V's current position.
- Added reusable **Prefabs** made from the current selection. Relative positions,
  rotations, scale, appearance, properties, and World Builder resource metadata
  are preserved.
- Added one-click prefab instantiation **At Player** or **At Aim**. Every instance
  is created as normal project objects, spawned through the correct backend,
  grouped, selected, and remains individually editable.
- Room-kit pieces saved into a prefab are detached from room rebuild ownership,
  preventing a later rebuild from deleting a customized prefab instance.
- Added group-cycle prevention, membership validation and cleanup, prefab
  resource validation, and group/prefab counts in diagnostics and bridge status.
- Added ten Claude MCP tools for persistent groups and reusable prefabs.
- Added an end-to-end assembly regression suite. It passes on Lua 5.1
  and LuaJIT 2.1.

## Scene group and prefab workflow

1. In **SCENE**, use the selection boxes to select placed objects or construction
   pieces.
2. Choose **PIVOT: CENTER**, **ACTIVE**, or **CUSTOM** in the Inspector. Custom
   pivot coordinates can be entered directly or captured from V.
3. Under **GROUPS**, enter a name and press **CREATE GROUP**. Selecting the group
   later restores the complete editable selection and World Builder focus.
4. Enter a reusable name and press **SAVE PREFAB**.
5. Under **PREFABS**, press **AT PLAYER** or **AT AIM**. The created resources
   appear as a new group and can be moved, edited, duplicated, or deleted like
   any other placed objects.
6. Press the group's **X** control to dissolve only the group container. The
   placed game objects remain.

## v0.12 multi-object foundation

- Added two-way selection synchronization. Selecting LocationStudio objects
  selects their World Builder handles; selecting or Ctrl-selecting those handles
  in World Builder updates LocationStudio's selection set.
- Added explicit `[ ]` selection toggles plus **Select Shown** and **Clear Set**
  controls to the Construction and Objects hierarchies.
- Added a multi-selection Inspector with adjustable move, rotation and scale
  steps, world/active-object local axes and center-pivot transforms.
- Group movement, yaw rotation and uniform scale update live World Builder
  objects immediately and create one undo snapshot per operation.
- Added group show, hide, lock, unlock, spawn, despawn, duplicate and delete.
- Duplicating a construction set preserves its relative layout and makes
  generated room pieces independent from future room rebuilds.
- Scaling reports an explicit limitation for `.ent` objects spawned directly by
  CET instead of pretending their bounds changed the live entity.
- Added seven Claude MCP tools for selection sets and group operations.
- Diagnostics now include selection IDs, active ID, count and selection source.

## Construction editing foundation

- Added a dedicated **CONSTRUCTION** hierarchy in Simple and Advanced UI. Room
  pieces are no longer hidden behind an off-by-default generated-object option.
- Selecting a live World Builder object now selects its native World Builder
  gizmo. Position, rotation and scale changes made with that gizmo synchronize
  back into the LocationStudio project automatically.
- Added role filters for wall, floor, ceiling, door, window and collision pieces,
  with room- or location-scoped **Show**, **Hide**, **Lock** and **Unlock**.
- Added real editing locks. Locked objects reject transform, replacement,
  duplication, deletion and native-gizmo access in UI, MCP and authoring tools.
- Added **Replace Asset** for changing one generated surface from the last Static
  Mesh selected in the full Game Database. Unrelated pieces are not rebuilt.
- Added **Detach / Make Unique**. Detached pieces survive later room rebuilds and
  become ordinary independent World Builder objects.
- Duplicating a generated piece now creates an independent object instead of an
  untracked fake shell member. Deleting a generated piece also cleans the room's
  ownership list.
- Hidden construction is despawned immediately; showing it submits only the
  matching pieces. Validation no longer reports false missing-template warnings
  for World Builder resources.
- Added Claude MCP tools: `detach_room_piece`, `replace_room_piece`,
  `set_construction_state`, and `focus_world_builder_object`.
- Expanded support reports with detached, locked and disabled construction counts.

## Game-asset room system

- The default **Common Interior** kit uses verified base-game floor, ceiling,
  wall, single-door wall, and window-wall `.mesh` resources.
- The included **Kitsch Apartment** kit provides a second coherent architecture
  set. Switching a preset does not destroy a room until **Rebuild** is pressed.
- Floors and ceilings tile across the requested footprint. Walls tile around the
  perimeter, edge pieces scale to the remaining length, and door/window requests
  use matching game wall modules instead of carving white primitives.
- Each generated visual piece stores complete World Builder `mesh_static`
  metadata. It can be selected, moved, rotated, scaled, duplicated, despawned,
  and refreshed with the same live transform path as a catalog asset.
- Floors and solid wall spans receive separate World Builder collision boxes.
  Their debug visualization is disabled, so collision does not appear as a room.
- Any imported **Static Mesh** from **Assets → Game Database** can replace the
  floor, wall, ceiling, door, or window role. Native dimensions, pivot offsets,
  and rotation correction are configurable under **Advanced Tools → Premises →
  Build**.
- Existing v0.9.x primitive room shells are converted to the current room kit when
  current LocationStudio release loads them. The runtime refuses to spawn any legacy
  `base\spawner\cube.mesh` shell that was not converted.
- **Save Debug Report** now records the active kit, all five resource paths,
  mesh/collision counts, legacy primitive count, and World Builder mesh/collision
  class probes.

The full World Builder 1.0.81 Game Database and live asset transform editor from
v0.9.4 remain available. The six built-in records are only starter shortcuts;
they are not the game-asset catalog.

## Install or upgrade

Extract the upgrade-safe ZIP into the Cyberpunk 2077 game root and allow it to
replace LocationStudio code:

```text
Cyberpunk 2077/
└── bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/
```

The upgrade archive deliberately omits `data/project.json`, `data/config.json`,
logs, exports, thumbnails, and bridge state. Restart the game or use CET
**Reload All Mods**, then confirm the header says **v0.37.0**.

Requirements: Cyber Engine Tweaks and World Builder 1.0.81. No game assets or
World Builder files are redistributed; the mod references resources already in
the installed game and uses World Builder's loaded public spawn catalog.

## Room workflow

1. Open **BUILD** and choose **Common Interior** or **Kitsch Apartment**.
2. Set room width, depth, and height, then create the room at V's position.
3. For an upgraded project, select a room and press **REBUILD SELECTED ROOM**, or
   press **REBUILD ALL ROOMS**.
4. To use another game mesh, import it under **ASSETS → GAME DATABASE**, select it,
   return to **BUILD**, and press **SET WALL**, **SET FLOOR**, **SET CEILING**,
   **SET DOOR**, or **SET WINDOW**. Rebuild to apply.
5. Open **SCENE → CONSTRUCTION**. Select a piece, then use its numeric transform
   controls or **WORLD BUILDER GIZMO**. Gizmo movement is saved automatically.
6. Choose a Static Mesh in **ASSETS**, select a generated piece, and press
   **REPLACE ASSET** to replace only that surface. Press **DETACH / MAKE UNIQUE**
   first if it must survive future room rebuilds.
7. Filter by role and use **SHOW / HIDE / LOCK / UNLOCK** for the selected room.
8. Use the `[ ]` toggles or **SELECT SHOWN** to build a set. The Inspector then
   exposes group move/rotate/scale and lifecycle controls.
9. Ctrl-select LocationStudio-spawned pieces in World Builder to pull that
   selection back into LocationStudio automatically.
10. If a custom modular mesh has a different pivot, open **Advanced Tools →
   Premises → Build** and tune its native dimensions, pivot offset, or rotation
   correction before rebuilding.

## Debug report

Immediately after a failure, press **SAVE DEBUG REPORT** and send:

```text
bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/logs/LocationStudio-v0.37.0-support.txt
```

If the window cannot open, send `logs/locationstudio.log` and CET's own log. The
report excludes project JSON and credentials, but resource paths and transforms
can appear in log lines.

## Validation

The source package contains 40 isolated Lua suites, runnable under Lua 5.1 and
LuaJIT 2.1. Dedicated transform-edit, grab-session, viewport, multi-selection,
duplicate-edit, placement-edit, stamp-stroke, pattern-edit, scatter-edit, and assembly coverage verifies transactional live transforms, direct CET
respawn-on-nudge, reversible crosshair movement, single-operation undo,
autosave/export blocking, camera-ray object picking, surface-normal transforms,
single-undo repeat stamping, full-stroke cancellation, removal-refusal safety,
two-way World Builder selection, center-pivot transforms, live updates, locking,
visibility,
duplication/deletion integrity, mixed-backend limits, UI controls and diagnostic
reporting, nested groups, cycle rejection, prefab coordinate reconstruction,
runtime spawning, metadata detachment and non-destructive dissolve. Room-kit
coverage still rejects primitive-cube fallback.

```sh
python3 tests/run_tests.py --runtime lua51
python3 tests/run_tests.py --runtime luajit21
python3 bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/mcp_server/test_bridge.py
```

Automated tests cannot render REDengine meshes. Follow
[IN-GAME-CHECK.md](IN-GAME-CHECK.md) for the final visual/pivot/collision check.

MIT license.
