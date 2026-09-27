# Environment Definition Language (EDL)

LocationStudio 0.71 can build a whole location from a declarative document. You write **one JSON or YAML file**. LocationStudio validates it, compiles it, builds it in the game through the same backends as the editor, and turns it into game archives with Build Mod.

The file can describe:
- floors, rooms, walls, doors and windows;
- room-kit materials and props with their appearances;
- lights and collision;
- devices and their logic;
- NPCs with routes and workspots;
- audio emitters and reverb, and VFX;
- quest triggers, cameras and occluders;
- splines, navigation and streaming settings.

```
document.edl.yaml ──edl_validate──▶ errors with locations
                  ──edl_compile───▶ exports/edl/<id>.plan.json   (authoring plan v2, reviewable)
                  ──edl_apply─────▶ live World Builder location   (one undo; rollback on failure)
                  ──edl_build─────▶ apply → preflight → Build Mod → .archive / .xl
```

The schema is `bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/edl/locationstudio-edl-1.schema.json`. Point your editor's YAML/JSON language server at it for completion and inline checks; the example's first line does this. A complete example lives in `edl/examples/ripperdoc_clinic.edl.yaml`.

## Document

```yaml
edl: 1                      # language version
id: ripperdoc_clinic        # stable id: applying it again REPLACES the previous build
name: Ripperdoc Clinic
origin: player              # player | camera | {position: [x, y, z], yaw: 90}
parameters: {ceiling: 3.2}  # used as ${ceiling} or ${ceiling - 0.2}
templates:                  # reusable fields, merged with `use: <name>`
  ceiling_light: {intensity: 60, radius: 6, color: [0.85, 0.95, 1]}
materials:
  room_kit: common_interior # or kitsch_apartment
  roles: {wall: base\...\wall.mesh}   # optional kit role overrides (project-wide)
defaults: {spawn: true, layer: decoration, stream_range: 80}
streaming: {category: interior, level: 1, cell: [64, 64, 32], range: 80}
floors: [...]
objects / lights / collisions / devices / npcs / workspots / vfx / triggers / cameras / occluders: [...]
audio: {emitters: [...], reverb: [...]}
splines: [...]
navigation: {nodes: [...], edges: [...]}
logic: [...]
scene: {name: Clinic, activate: false}
```

## Coordinates

- **Units and frame.** Coordinates are metres in the **location frame**, where the origin is V, the camera, or an explicit transform. `at` takes `[x, y, z]`, `[x, y]` or `{x, y, z}`. `yaw` is in degrees, and `rotation: {roll, pitch, yaw}` is also accepted.
- **Floors** stack upwards. Each has a `height`, and an optional `elevation` (default: on top of the floor below) and `level`.
- **Rooms** have `at` (their centre), `yaw`, `size: [width, depth(, height)]`, `walls: {thickness}`, `doors` and `windows`. Each opening is `{wall: north|south|east|west, offset, width, height, sill}`. The compiler checks that every opening fits its wall and the room height.
- **Room-relative elements.** Any element list nested in a room (or any element with `room: <id>`) uses the **room frame**: `at` is relative to the room centre at floor level, and `yaw` is added to the room's yaw. Elements with `floor: <id>` are raised to that floor.

## Elements

Every element needs a unique `id` (letters, digits, `_` and `-`). Ids name what was built and are how documents reference each other.

| List | Fields | Builds |
| --- | --- | --- |
| `objects` | `resource` or `asset`, `scale`, `appearance`, `layer`, `stream_range` | a World Builder resource (mesh, entity, decal, particle…) |
| `geometry` | `generator` (wall, floor, ceiling, column, stairs, ramp, door_frame, window, railing, pipe, duct, box), `params`, `material` (template `.mesh` or `{template, appearance, uv_scale}`), `collision` | [procedural geometry](PROCEDURAL-GEOMETRY.md) built from dimensions |
| `lights` | `color [r,g,b]`, `intensity`, `radius`, `flicker {strength, period, offset}`, `preset` | a Static Light |
| `collisions` | `shape box/capsule/sphere`, `size`, `radius`, `height`, `preset`, `material` | a collision primitive |
| `devices` | `kind door/loot_container/shard/item`, `resource`, `locked`, `loot_table`, `loot [{item, min, max, chance}]`, `item`, `fact {name, value}` | an interactable (native wiring at Build Mod) |
| `npcs` | `record Character.*`, `appearance`, `conditions [{fact, op, value}]`, `route {loop, waypoints [{at, wait, workspot, speed, variant}]}` | an NPC population point and its route |
| `workspots` | `kind`, `animation {name, comp, ent}`, `record`, `appearance` | an NPC workspot |
| `vfx` | `resource .particle/.effect`, `scale`, `emission_rate` | a particle or effect |
| `triggers` | `shape box/sphere/cylinder`, `size`, `radius`, `fact {name, value}` | a volume linked to a quest fact |
| `cameras` | `look_at [x,y,z]` (same frame), `fov` | a saved camera |
| `occluders` | `mesh box/plane/plane_two_sided`, `size` | a Static Occluder |
| `audio.emitters` | `resource` (event) or `query`, `radius` | a Static Audio Emitter |
| `audio.reverb` / room `reverb` | `room`, `preset`, `sound_event`, `reverb` | an ambient reverb area over the room |
| `splines` | `points`, `closed`, `tension` | a spline (use it with `spline_apply_use`) |
| `navigation` | `nodes [{id, at}]`, `edges [{from, to, kind, one_way, cost}]` | an imported navigation graph |
| `logic` | `nodes [{id, kind, element, config}]`, `links [{from, to, trigger, when {fact, value}}]` | a device-logic graph bound to built elements |

**Resources** are depot paths or records. The type is inferred from the extension (`.mesh`, `.ent`, `.mi`, `.particle`, `.effect`) or from a `Character.*` record, or set explicitly as `{type: mesh_dynamic, path: ...}`. Every resource is imported from the loaded World Builder catalog, once per path. **Nothing is invented**: a path missing from the catalog fails the apply and rolls it back. Use `asset_catalog_search` to find paths.

For an `.ent` that is not in the catalog, `{type: entity_template, path: ..., backend: cet}` registers it as a direct CET entity. It cannot be exported to sectors, and the preflight reports that.

**Reuse:**
- `parameters` accept numbers and arithmetic (`${w / 2 + 3}`); in YAML, quote expressions inside `[ ]` or `{ }`.
- `templates` are merged with `use:`.
- `repeat: {count, step: [x, y, z], yaw_step}` expands one element into numbered copies (`bench_1`, `bench_2`, …).

## Applying and rebuilding

`edl_apply` runs the compiled plan (authoring plan **version 2**, up to 2000 steps) as **one transaction**:
- Everything succeeds and becomes one undo step, or any failure rolls every change back, including live spawns.
- Before building, the plan removes everything the previous apply of the same `id` created. Editing the file and applying it again therefore updates the location in place; code is the source of truth.
- Each build is recorded in the project (`edl_builds`): its hash, source and streaming settings, and which project item each element id became. Read it with `edl_list` / `edl_get`.
- `edl_remove` deletes a build as one undo step.

Hand edits to built items are replaced on the next apply. Change the document instead, or detach the items by removing them from the document.

## Game resources

`edl_build` applies the document, runs the [shipping preflight](PREFLIGHT.md) for its premise, and stops if the preflight is not ready (`strict` also blocks on warnings). It then calls `build_mod_from_project` with the document's streaming category, level and cell size:
- with `run=false`, you get the build readiness report;
- with `run=true`, it exports the World Builder sectors, converts them to CR2W, generates the native interactables, stages dependencies, and packs the `.archive` and `.xl`.

Deploy with `build_deploy`. Per-node `stream_range` values are written into each resource's streaming ranges.

## Limits

- Room-kit `materials.roles` change the project-wide room kit, so the change affects rooms built afterwards too.
- Live objects removed by `edl_remove` are not respawned by undo; use Runtime Sync.
- The EDL describes LocationStudio's authoring model. Anything LocationStudio cannot build is out of reach: native `.scene` files, vanilla-world edits and non-World-Builder node types.
