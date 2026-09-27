# LocationStudio MCP examples

Run the included `mcp_server/claude-add.sh` from the installed mod directory, or
configure the Python server manually as described in `README.md`. Keep the game
loaded and CET open enough for the file bridge to poll. `get_status` must report
`live: true` before live tools can work.

## Render a saved prefab thumbnail

```text
list_object_prefabs()
wb_prefab_render(prefab_id="prefab_...")
```

Aim at a clear space first. This captures an actual game screenshot of
temporary prefab instances and removes them afterward; it does not create a
saved prefab instance. See [WB-PREFAB-THUMBNAILS.md](WB-PREFAB-THUMBNAILS.md)
for supported backends and cleanup behavior.

## Generate cables, fences, roads, and a market layout

```text
list_premises()
wb_bounds_info(asset_id="MESH_ASSET_ID")
wb_bounds_set(asset_id="MESH_ASSET_ID", minimum={x=-1,y=-0.5,z=0}, maximum={x=1,y=0.5,z=2}, source="measured")
wb_generate_fence(
  premise_id="PREMISE_ID", asset_id="FENCE_PANEL_ID",
  points=[{x=0,y=0,z=0},{x=0,y=12,z=0}], segment_length=2,
  post_asset_id="POST_ASSET_ID", spawn=true
)
```

Use imported World Builder Static Mesh assets. Measure/set their local bounds
before cable, fence or road generation; do not guess bounds for a production
layout. `WB-GENERATORS.md` documents all five generator tools and explains
that NodeRef output is a semantic authoring marker, not a compiled world node.

Recommended Claude flow:

1. Call `get_status` and `get_integration_status`.
2. Call `resolve_authoring_asset` for every uncertain asset name. Ambiguous
   searches are rejected instead of guessing.
3. Call `get_authoring_plan_schema` or `get_authoring_plan_examples`.
4. Compose the entire plan, then call `validate_authoring_plan`.
5. Show the validated plan to the user. Call `execute_authoring_plan` only after
   they request execution. Leave `save=false` so the player can inspect and Undo.
6. Call `get_authoring_plan_status`. Save only after visual confirmation.

Example prompt:

> At my player position, create an 8 x 6 x 3 metre clinic room. Use registered
> game assets for one table, two chairs, and one wall light. Add an entrance
> point, a box trigger, a camera looking at the entrance, and a looping
> three-point patrol. Put all members in one scene. Resolve asset names first,
> show me the validated plan, then execute it without saving.

Useful plan tools are `validate_authoring_plan`, `execute_authoring_plan`,
`save_authoring_plan_file`, `validate_authoring_plan_file`,
`execute_authoring_plan_file`, and `get_authoring_plan_status`. Scene tools are
`list_scenes`, `create_scene`, `capture_scene_from_premise`,
`edit_scene_members`, `add_current_selection_to_scene`,
`remove_current_selection_from_scene`, `activate_scene`, `isolate_scene`,
`deactivate_scene`, `get_scene_status`, `select_scene_objects`, and
`delete_scene`.

If execution returns recovery required, call `get_authoring_plan_status`. Fix
the World Builder/CET removal problem and call `retry_authoring_plan_rollback`.
Call `keep_partial_authoring_plan` only when the user explicitly wants the
remaining partial build. During recovery, unrelated mutations are rejected.

For diagnosis, call `run_diagnostics`, `get_debug_log`, or
`create_debug_bundle`. The in-game **SAVE DEBUG REPORT** is the simplest file to
send for analysis.

## Build and deploy a mod headlessly

`export_project("worldbuilder")` only writes a handoff JSON. To ship the
authored objects as a real mod (`.archive` + `.xl`):

1. One-time: `build_worker(run=true)` builds the .NET WolvenKit worker, then
   `build_worker_preflight()` must report `ready: true`. Packing also needs a
   WolvenKit CLI (`cp77tools` or `WolvenKit.CLI` on PATH, or pass `cli=`).
2. In game, open World Builder's Export tab once per session (WB creates its
   sector-category table only when that tab is drawn).
3. `build_mod_from_project(name="my_bar", premise_id="...")` previews readiness
   and paths. Repeat with `run=true` to export, convert, pack, package and
   verify in `exports/build/my_bar/`. A failure names `failed_stage`.
4. `build_deploy(layout=".../exports/build/my_bar/dist")` previews the install;
   add `apply=true` to copy into the game. Conflicts need `overwrite=true` and
   are backed up to `<game>/.cp77wb-deploy-backups/`.

Only objects live in World Builder can be exported. CET-spawned `.ent` objects
are listed in the refusal; pass `allow_skipped=true` to build without them.
The individual stages are also exposed: `build_export_world_builder`,
`build_export_inspect`, `build_prepare`, `build_worker_import`,
`build_native_import` (template-bundle fallback), `build_status`, `build_pack`,
`build_package`, `build_verify`, `build_doctor`.

## Migrate World Builder / cp77wb saved builds

1. `list_world_builder_builds()` lists `entSpawner/data/objects/*.json` with
   object and group counts. `legacy: true` builds must be loaded and re-saved in
   World Builder once before import.
2. `import_world_builder_build(build="bar")` previews: object/group counts per
   WB class, plus any elements LS cannot represent.
3. `import_world_builder_build(build="bar", apply=true)` imports into a new
   premise (or `premise_id=`) as one undo step. Add `allow_skipped=true` if the
   preview listed unsupported elements. Add `spawn=true` only if the build is not
   also loaded in World Builder; otherwise every object appears twice.
4. `save_project()`. Importing the same build again is refused unless
   `allow_duplicate=true`.

Imported objects are ordinary WB-backed LS objects: they can be edited, put in
scenes, and shipped with `build_mod_from_project`.

## Undo, redo and history

`get_history(limit=10)` lists what `undo` would revert next (`undo[0]`) and
what `redo` would re-apply, each with a label, a timestamp and per-collection
counts such as `{"objects": {"added": 1, "removed": 0, "changed": 0}}`. It
covers every committed edit: editor, MCP, plans, transform/stamp sessions,
World Builder gizmo moves and saved-build imports.

`undo(steps=3)` jumps back three entries in one pass (live objects are
despawned once and respawned once); `redo(steps=...)` goes forward. Both are
refused while a transform or stamp session or plan recovery is active; commit
or cancel it first. Uncommitted session edits are not history entries.

## Find vanilla assets

One-time (and after updating World Builder): `asset_catalog_build()` then
`asset_semantic_build()`; together about a minute. Both run without the game.

- Keyword: `asset_catalog_search("bar stool", variant="Mesh")`.
- Semantic: `asset_semantic_search("office chair", role="furniture",
  category="Entity")`. Facets are coarse classes (a lamp is `role="light"`,
  a crate `role="container"`); put the specific object in the query.
- Place a hit: `import_catalog_asset("78987")` (game running) returns a Project
  Asset; use its id with `start_placement_edit`, `place_registered_asset` or an
  authoring plan.

## Import and edit resource bounds

The bounds manifest in `examples/asset-bounds-manifest.json` is a placeholder
template, not real measured game data. Replace its asset ID/resource path and
min/max coordinates with values measured in meters. Then preview the import and
apply only after checking the asset mapping:

```text
wb_bounds_import(manifest_file="/path/to/measured-bounds.json")
wb_bounds_import(manifest_file="/path/to/measured-bounds.json", dry_run=false)
wb_bounds_info(asset_id="asset-id")
wb_bounds_set(asset_id="asset-id", minimum={x=-1.2,y=-0.35,z=0}, maximum={x=1.2,y=0.35,z=0.82}, source="measured")
wb_bounds_fit(asset_id="asset-id", target_size={x=3,y=1,z=1}, mode="contain")
wb_bounds_world_aabb(object_id="object-id")
wb_bounds_overlap(object_ids=["object-a","object-b"], margin=0)
```

Bounds edits propagate to objects linked to that Project Asset. Fit returns a
scale suggestion only; overlap reports AABB broad-phase candidates and is not
an exact mesh collision test or an engine collider generator. See
`WB-ASSET-BOUNDS.md` for the coordinate contract.
# World Builder native Favorites

Search the offline resource index, then let the live World Builder catalog
prepare a native favorite. The first call is preview-only; make the second call
only after reviewing the proposed category/resource.

```text
asset_catalog_search(query="clinic chair", category="Mesh", variant="Mesh")
wb_favorite_add(catalog_id="12345", category="Clinic Props", name="Treatment chair", tags=["clinic", "furniture"])
wb_favorite_add(catalog_id="12345", category="Clinic Props", name="Treatment chair", tags=["clinic", "furniture"], write=true)
wb_favorites_list(category_filter="Clinic Props")
```

The write updates World Builder's own `data/favorite/*.json`, creates a
timestamped backup when modifying an existing category and preserves unknown
category fields. The World Builder Favorites panel loads files at initialization,
so reload World Builder/CET or restart the game after a successful write.

# Cover nodes

```text
cover_node_create(premise_id="premise-id", name="Desk cover", cover_type="crouch", exposure="medium", spacing=1.5, source="aim")
cover_node_list(premise_id="premise-id")
cover_node_update(node_id="cover-id", patch={"cover_type":"standing", "exposure":"low", "transform":{"position":{"x":1,"y":2,"z":3},"rotation":{"yaw":90}}})
cover_scan(radius=8, samples=24, spacing=1.5)
cover_scan(radius=8, samples=24, spacing=1.5, premise_id="premise-id", save_to_project=True)
cover_node_delete(node_id="cover-id")
```

`cover_scan` uses paired Static/Dynamic collision rays and returns candidates only. It does not query engine cover/navigation or infer exposure; review candidates in game. See `COVER-NODES.md`.

# Imported navigation graph

```text
navigation_graph_import(graph={"name":"Clinic floor","source_format":"offline-export-v1","nodes":[{"id":"entry","position":{"x":-10,"y":4,"z":2}},{"id":"room","position":{"x":-4,"y":4,"z":2}}],"edges":[{"id":"door-a","from":"entry","to":"room","kind":"door"}],"polygons":[]})
navigation_graph_list()
navigation_graph_check(start_x=-10,start_y=4,start_z=2,goal_x=-4,goal_y=4,goal_z=2)
navigation_workspot_report(start_x=-10,start_y=4,start_z=2)
walkability_check(goal_x=-4,goal_y=4,goal_z=2,start_x=-10,start_y=4,start_z=2,navigation_graph_id="graph-id")
```

Graph import expects converted JSON, not raw REDengine files. Reports describe imported-data connectivity only; see `NAVIGATION.md` for format and limits.

# Device Logic graphs

```text
device_logic_graph_create(name="Clinic door flow", premise_id="clinic-premise-id")
device_logic_node_add(graph_id="logic-id", kind="terminal", name="Reception panel", object_id="placed-device-id", native={"device_hash":"123","device_class":"DoorControllerPS","ps_entry_hash":"ps123","instance_data_ref":"preset-id","node_ref":"clinic_panel"})
device_logic_node_add(graph_id="logic-id", kind="fact", name="Clinic unlocked", config={"fact_name":"clinic.door_unlocked","value":1})
device_logic_node_add(graph_id="logic-id", kind="action", name="Unlock entrance", config={"operation":"unlock","target":"door-node-id"})
device_logic_link_add(graph_id="logic-id", from_id="panel-node-id", to_id="action-node-id", trigger="interact", condition_fact="clinic.door_unlocked", condition_value=1, native_operation="Unlock")
device_logic_validate(graph_id="logic-id")
wb_device_logic_apply(export_file="my_export.json", graph_id="logic-id")
```

The last call updates only the existing WB device child/parent link data when the export already contains compatible device and `PSID`/typed `instanceData` resources plus bound sector NodeRefs. Otherwise it lists missing resources and leaves the export untouched. Device/fact/action semantics are documented in `DEVICE-LOGIC.md`.
# Quest Forge round-trip

```text
questforge_sync_preview(file_path="/path/to/edited-questforge-handoff.json")
questforge_sync_apply(file_path="/path/to/edited-questforge-handoff.json")
questforge_links(kind="object", item_id="<object id>")
```

The default update preserves local coordinates and other authored fields. Review coordinate conflicts in preview; use `apply_positions=true` only to accept remote positions. See [QUEST-FORGE-ROUNDTRIP.md](QUEST-FORGE-ROUNDTRIP.md).
# Quest simulation/debug

```text
quest_simulation_state()
quest_simulation_state(fact_name="clinic.entry_unlocked")
quest_simulation_prepare_fact_write(fact_name="clinic.entry_unlocked", value=1)
quest_simulation_confirm_fact_write(token="<one-time-token-returned-by-prepare>")
quest_simulation_cancel_fact_write(token="<one-time-token-returned-by-prepare>")
quest_simulation_prepare_trigger(volume_id="<LocationStudio trigger volume id>")
```

Preparation never writes. Review its active-save warning before calling the confirm tool. Fact writes may advance quest logic and cannot be undone by LocationStudio. Trigger preparation only stages the volume's configured fact write; it does not dispatch a native volume event. See [QUEST-SIMULATION.md](QUEST-SIMULATION.md).
# Conditional world-state variants

```text
world_state_variant_create(name="during_quest", fact_name="clinic.quest_stage", value=1, priority=10)
world_state_variant_add_object(variant_id="<variant id>", object_id="<object id>", visible=true)
world_state_variant_create(name="cleaned", fact_name="clinic.cleaned", value=1, priority=20)
world_state_variant_add_object(variant_id="<cleaned id>", object_id="<debris object id>", visible=false)
world_state_preview()
world_state_apply()
world_state_auto_switch(enabled=true)
```

Variants switch tracked LocationStudio object entities only; they do not compile native REDengine quest conditions. See [WORLD-STATE-VARIANTS.md](WORLD-STATE-VARIANTS.md).
