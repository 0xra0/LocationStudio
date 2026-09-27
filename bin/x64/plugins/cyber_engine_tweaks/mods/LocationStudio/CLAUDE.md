# LocationStudio v0.24.0 MCP guidance

LocationStudio is authoritative for semantic locations, premises, construction objects, volumes and camera composition.

For a complete location build, prefer one declarative authoring plan over a
long sequence of independent mutations. Call `get_authoring_plan_schema`,
resolve uncertain resources with `resolve_authoring_asset`, then call
`validate_authoring_plan` before `execute_authoring_plan`. A successful plan is
one undo operation; a failure rolls back all plan steps. If status reports
`recovery_required`, stop unrelated mutations and use
`retry_authoring_plan_rollback` after repairing the runtime adapter. Use
`keep_partial_authoring_plan` only after explicit user approval.

Scenes are persistent collections of existing rooms, objects, locations,
volumes, cameras, and routes. They do not duplicate their members. Use
`create_scene`, `activate_scene`, and `select_scene_objects` for coherent
scene-level work.

Prefer `capture_scene_from_premise` when a location already contains authored
rooms and props. Use `edit_scene_members` for deterministic membership changes;
use current-selection tools only when the user is visibly selecting in the CET
editor. `isolate_scene` may despawn other tracked project objects. A failed
deactivation intentionally retains scene ownership; fix the runtime adapter and
retry instead of deleting scene data.

1. Call get_status before live operations.
2. Resolve premise, room and object IDs before edits.
3. Prefer exact local coordinates for planned layouts.
4. For place_object_at_aim, inspect placement_source. Report forward_fallback or look_at_entity as approximate.
5. Never invent .ent depot paths. Ask for or discover a valid template.
6. Use create_volume for quest triggers, encounter areas, audio zones and streaming annotations.
7. Use capture_camera_from_player for human-composed shots; use create_camera for generated blocking.
8. Preserve camera look-at targets when moving cameras.
9. Use batch_transform only on same-kind item IDs; validate afterward.
10. In-world markers require a configured template. The floorplan does not.
11. Call validate_project and save_project after mutation batches.
12. Export questforge for semantic quest/scene handoff and worldbuilder for physical construction handoff.

Rooms are game-asset kits in v0.24.0. Do not assume generated room objects are
debug primitives: their `metadata.world_builder` entries are authoritative game
resources and their `size` values are live World Builder scale factors. Collision
objects are deliberately invisible. Never reintroduce `base\spawner\cube.mesh`
as a fallback; request a room rebuild or a valid Static Mesh role instead.

Generated construction is editable by piece. Use `replace_room_piece` to change
one kit-managed surface, and use `detach_room_piece` before customization when it
must survive a future room rebuild. `set_construction_state` can show/hide or
lock/unlock by room and role. Locked objects must not be edited. Native World
Builder gizmo movement synchronizes back into the project while that object is
selected; `focus_world_builder_object` activates that workflow.

Selection sets are shared with World Builder. Use `get_object_selection`
before modifying an interactive selection, `set_object_selection` to replace it,
and `transform_object_selection` for center-pivot group transforms. Use the
selection-state/runtime/duplicate/delete tools for set operations. Group scaling
is valid only for World Builder resources; direct CET `.ent` entities do not
expose live scale and must return an explicit error.

v0.13 persistent groups are scene-outliner containers, not merged geometry.
Use `create_object_group` after establishing a meaningful selection,
`select_object_group` to restore it recursively, and `transform_saved_group`
to operate around its stored pivot. Dissolving a group must preserve all
objects. Parent cycles are invalid.

Use `save_object_prefab` to capture a reusable assembly from verified objects
and `instantiate_object_prefab` to place it at the player or aimed surface.
Prefab instances are ordinary editable project objects. Their source resource
metadata is preserved, while room-kit ownership is intentionally removed so a
room rebuild cannot delete the instance.

Use `layout_object_selection` for deterministic align, distribute, match, and
snap operations instead of approximating repeated transforms. Distribution
requires at least three objects. Matching scale is valid only for World Builder
resources. Use `replace_object_selection_asset` only with an existing verified
project asset; room construction sets accept Static Mesh resources only.

Use `pick_aimed_project_object` to select only a LocationStudio-owned saved
object near the active camera ray; it is not arbitrary world-entity picking.

For native vanilla-world cleanup, use `vanilla_removal_status` first, then
`remove_vanilla_under_crosshair` or `remove_nearby_vanilla_assets`. These
operations persist reversible visibility-removal records for streamed nodes;
they do not permanently delete REDengine world data. Use the restore operations
to undo them. Entity-only targets are intentionally rejected, and an unavailable
RedHotTools WorldInspector must be reported rather than bypassed with `run_lua`.
Use `preview_registered_asset` with `align_surface=true` only when a raycast
normal is available and the resource's authored local-up axis is appropriate.
For repeated placement, start it with `stamp_mode=true`, call
`stamp_asset_preview_once`, and inspect `get_stamp_stroke_status`. Every accepted
click is a real live object but remains part of one unsaved transaction. Finish
with `commit_stamp_stroke` for exactly one undo operation or
`cancel_stamp_stroke` to remove the complete stroke and restore prior state.
`stop_asset_preview` is retained as a commit alias. Respect a nonzero stamp
spacing instead of retrying a rejected duplicate at the same point. If cancel
reports a runtime-removal refusal, the active stroke and authored ownership are
intentionally retained; collect the debug report and retry cleanup rather than
deleting project records.

Use `start_crosshair_grab` for an interactive reversible move of an explicit
object set or the current selection. World Builder resources update live;
direct CET entities intentionally refresh only at commit. Use
`update_crosshair_grab` for distance, snap, surface alignment, or yaw changes,
then always finish with `commit_crosshair_grab` or `cancel_crosshair_grab`.
Inspect `get_crosshair_grab_status` before assuming a session is inactive.
Unrelated bridge mutations, save, and export are rejected during an active
session so temporary preview transforms cannot become project data.

Use `start_reversible_transform_edit` for precise transactional editing instead
of issuing many independent transform commands. Apply incremental world/local
movement, rotation, and supported scale with
`adjust_reversible_transform_edit`, inspect `get_transform_session_status`, and
finish with `commit_reversible_transform_edit` or
`cancel_reversible_transform_edit`. `reset_reversible_transform_edit` returns
the live preview to its session-start state without closing the transaction.
World Builder resources update in place; direct CET `.ent` resources safely
respawn after each deliberate adjustment. Group roll/pitch and direct CET scale
are unsupported and must remain explicit errors. A complete edit is one undo
operation; a no-op commit creates no history.

Use `duplicate_selection_and_edit` for engine-style copy placement rather than
calling the older immediate duplicate operation followed by unrelated transform
commands. The copies spawn through their real World Builder or direct CET
backend and become the active Transform Edit selection. Finish with
`commit_reversible_transform_edit` to record creation and placement as one undo
operation, or `cancel_reversible_transform_edit` to despawn and remove every
copy and restore the source selection. A backend removal refusal deliberately
keeps the transaction active; inspect diagnostics and retry instead of deleting
project ownership.

Use `start_placement_edit` for the primary single-placement workflow. With
`kind="asset"`, supply a verified Project Asset ID and choose `aim`, `player`,
or `preview`; preview mode requires a currently active preview of that same
asset. With `kind="object"`, supply explicit object IDs to copy a complete
assembly to the target while preserving relative spacing and height offsets.
Inspect `placement_source`, target transform, normal, and backend counts, then
finish with `commit_reversible_transform_edit` or
`cancel_reversible_transform_edit`. Do not follow immediate placement with an
unrelated transform command when the transactional tool can express the job.

Use `start_linear_pattern_edit` for a live repeated assembly. Supply verified
object IDs, a repetition count, XYZ step, yaw step, local/world choice, and a
center or active source pivot. Use `start_mirror_copy_edit` to reflect placement
and facing around the owning location's X or Y origin. Mirror does not perform
unsupported negative mesh scale. Both operations enter the normal Transform
Edit transaction and must finish with `commit_reversible_transform_edit` or
`cancel_reversible_transform_edit`. A transaction may create at most 100 objects
and a zero-step/zero-yaw pattern is rejected to prevent invisible overlaps.

Use `start_scatter_copy_edit` for deterministic environmental dressing. It
accepts a placed object selection or a saved Project Asset, an explicit seed,
count, radius, aim distance, optional random yaw, and optional ground placement.
A multi-object source is stamped as one assembly, preserving its relative
spacing and height offsets. Ground placement preflights every stamp and rejects
the whole operation if a required raycast misses. Inspect the returned point
list and aim source, then finish with `commit_reversible_transform_edit` or
`cancel_reversible_transform_edit`. Prefer this reversible tool over the legacy
`scatter_at_aim`, which now exists only as a transactional auto-commit wrapper.

Do not use arbitrary Lua execution. Do not silently convert fallback aim positions into exact surface claims.
Prefer the asset catalog for repeatable construction: register a verified `.ent` once, then place it with `place_registered_asset`. Do not invent depot paths. The editor and MCP share the same project objects and live spawn state.

When anything fails, call `get_debug_log` and `get_diagnostics` before attempting a repair. Use `create_debug_bundle` when the user needs a single archive. Treat the logged CET traceback and capability report as authoritative; do not infer that a runtime API exists merely because a command is exposed.


## v0.5.0 runtime-result rules

- A created object can be valid authoring data even when its live CET spawn fails. Treat `spawn_error` as a preview/runtime warning, not proof that the object was never created.
- After delete operations, re-resolve IDs rather than relying on cached selection state.
- Prefer the shared action operations for UI-equivalent behavior; `action:*` records in `logs/locationstudio.log` are the audit trail for whether a click/command reached its implementation.
- The scene viewport intentionally avoids raw `GetWindowDrawList()` method calls. Do not reintroduce the v0.4.1 draw-list path without verifying the exact CET Lua binding behavior.

## entSpawner-style authoring tools

Prefer these higher-level tools when building or adjusting scenes:

- `capture_active_camera` for a persistent camera from the current editor/game view.
- `copy_item_transform` / `paste_item_transform` / `reset_item_rotation` for repeatable transforms.
- `move_item_to_player`, `move_item_to_aim`, and `drop_item_to_ground` for spatial placement.
- `set_transform_target`, `aim_item_at_target`, `aim_item_at_player`, and `aim_item_at_crosshair` for look-at authoring.
- `duplicate_item_at_aim` for one immediate copy; `start_scatter_copy_edit` for
  reversible repeated layout. Use `scatter_at_aim` only when immediate commit is
  explicitly desired.

Aim operations use the active game camera where CET exposes it; inspect the returned placement source/warning when exact raycast placement is important.

## Headless build (`build_*` tools)

`export_project` never produces an `.archive`. To ship a mod use
`build_mod_from_project` (preview first, then `run=true`), then `build_deploy`
with `apply=true` only after the user approves installing into the game. Only
World Builder-backed objects export; never pass `allow_skipped=true` without
telling the user which objects the refusal listed. If export fails with the
"Open World Builder > Export tab" message, ask the user to open that tab once;
do not work around it with `run_lua`. Contract tests use fake worker/CLI
binaries, so a real CR2W result is proven only by `build_worker_preflight`
reporting `ready` on this machine plus an in-game check of the deployed mod.

## Saved-build migration

Use `list_world_builder_builds`, then `import_world_builder_build` without
`apply` to preview. Apply only after the user confirms the target premise. Ask
before `spawn=true` (a build still loaded in World Builder would be doubled) and
before `allow_skipped` or `allow_duplicate`. For a legacy build, ask the user to
re-save it in World Builder; do not hand-convert the JSON.

## Undo and redo

Call `get_history` before `undo`/`redo` with `steps>1` and confirm the entries
you will revert are the ones the user means; history is project-wide, so it
includes the user's own editor edits. Never use undo to hide a failed
transaction; follow the session/recovery rules above instead.

## Finding game resources

To find a depot path, search the offline catalog (`asset_catalog_search`, or
`asset_semantic_search` with coarse facets) instead of guessing, then call
`import_catalog_asset` with the hit's id and place the returned Project Asset.
If import reports the path is not in the loaded World Builder catalog, rebuild
the catalog; never register the path by hand.


## VFX / particles

Use `vfx_search` (optionally with a `category` from `vfx_categories`) and pass
the returned exact `resource_path` to `vfx_preview`/`vfx_create`; never invent
`.particle`/`.effect` paths. Prefer `vfx_preview` followed by
`vfx_preview_commit` when the user is looking at the spot, and always finish
with commit or `vfx_preview_clear`. Report `placement_source=forward_fallback`
as approximate. Scale is saved and applied to native nodes at build time only;
do not claim the live preview shows it. Rotation and particle emission edits
may update live; a resource swap respawns the node.

## Environment preview

Use `environment_list`/`environment_create` for saved time, weather and fog
conditions; rain is chosen through the weather state, and exposure is a note
that is never applied. `environment_preview` changes the running game's clock
and weather: tell the user, and always finish with `environment_restore`. For
repeatable screenshots pass `environment_id` to `visual_regression_capture` and
report `environment_mismatch` instead of treating that diff as a regression.

## Deterministic screenshots

For regression shots prefer `visual_regression_capture(deterministic=true,
environment_id=...)`. It changes the user's HUD/graphics settings and freezes
time only for the capture and restores them in `finally`; if the result reports
`screenshot_mode_restore_error`, call `screenshot_mode_restore` before anything
else and tell the user. Report `screenshot_mode_unavailable` settings instead of
claiming they were disabled.

## Collision authoring

Author blockers with `collision_create_primitive` (or `collision_fit_to_object`)
and a preset from `collision_presets`; never invent collision mesh paths, use
`collision_search_meshes`. `collision_passability` is an estimate from saved
colliders on one floor level: report it as such, and use `live=true` or the
walkability/navigation tools before claiming an actor can or cannot pass.

## Streaming sectors

After exporting, run `sector_inspect(name)` and review `likely_wrong_sector`,
`duplicate_psid` and cross-sector references before building. Treat flags as
heuristics: explain them to the user and use `sector_node` for details; never
edit the export to "fix" a sector without the user's approval.

## Performance estimates

`performance_analyze` / `performance_export` give relative cost estimates, not
frame times. Use them to point at dense clusters and over-budget rooms; do not
promise FPS gains. Ask before deleting or thinning objects to meet a budget.

## Occlusion and visibility

Only World Builder Static Occluders can be authored; say so if the user asks
for visibility volumes or portals. `visibility_pvs` and
`visibility_hidden_meshes` consider saved cameras only: suggest adding
cameras for important gameplay views, and never disable a flagged mesh
without the user's approval.

## Layers

Respect layer state: do not unlock a locked layer or show a hidden layer
without the user's approval, and do not move objects onto a locked layer.
Use `layer_auto_assign` with `apply=false` first and show the moves. Objects on
export-disabled layers (Debug by default) are intentionally absent from
builds; report `excluded_by_layer` instead of treating it as a failure.

## Splines

Prefer one spline plus `spline_apply_use` over hand-computed point lists for
cables, fences, roads, rows of props, NPC patrols and camera paths. After
editing a curve, call `spline_regenerate`; warn the user that hand edits to
generated objects are replaced unless the use is removed with
`keep_outputs=true`.
