# Layers

LocationStudio 0.64 turns project layers into a full layer manager for everyday editing. Scenes and groups organise content by purpose; layers organise it by kind, and apply across the whole project.

## Default layers

| Layer | id | Colour | Export | Typical content |
| --- | --- | --- | --- | --- |
| Architecture | `shell` | #5BC0EB | yes | room kits, walls, floors, structural meshes |
| Props | `decoration` | #9BC53D | yes | furniture, clutter, decals, VFX |
| Gameplay | `gameplay` | #FDE74C | yes | devices, interactables, trigger/gameplay areas, collision, occluders |
| NPC | `npc` | #C77DFF | yes | population points, Character records, AI spots/communities, workspots |
| Lighting | `lighting` | #E55934 | yes | static lights, reflection probes, fog volumes |
| Audio | `audio` | #4ECDC4 | yes | audio emitters, ambient/reverb areas |
| Quest | `quest` | #FA7921 | yes | quest-specific objects and cameras |
| Debug | `debug` | #9E9E9E | **no** | markers, splines, outline points, temporary helpers |

The ids `shell` and `decoration` are kept from earlier versions, so existing objects and tools keep working. Projects from earlier versions are migrated when loaded:
- the missing layers are added;
- the untouched old names "Shell" and "Decoration" become Architecture and Props;
- layers you renamed yourself keep your names.

## Operations

All of these are in **Spatial → Layers**, and are available as MCP tools:

- **Hide / show** (`layer_set_visible`): hiding despawns the layer's live objects and remembers which ones were live. Showing respawns exactly those. The list survives a CET reload. A hidden layer also refuses new spawns (`placement:spawn`), so scenes, world-state variants and creation tools respect it.
- **Lock / unlock** (`layer_set_locked`): locking marks every object on the layer as locked, so every existing lock check (transform tools, Inspector, lighting and VFX editors, and so on) refuses edits. Unlocking releases only the objects the layer lock set; an object you locked yourself stays locked. A locked layer also refuses objects being moved into it.
- **Isolate** (`layer_isolate(id)`): shows one layer only and remembers every layer's previous visibility. Isolating a second layer keeps that first snapshot. `layer_isolate()` with no id, or **SHOW ALL LAYERS AGAIN**, restores it.
- **Select all** (`layer_select_all`): multi-selects every object on the layer (optionally within one premise) for the transform and group tools.
- **Colour label** (`layer_update(color=#RRGGBB)`): the colour appears as a chip next to each object in the hierarchy. The chip shows `#` for a locked layer and `*` otherwise.
- **Export-enable** (`layer_update(export=…)`): objects on layers with export turned off are left out of `build_export_world_builder` and Build Mod. They are listed as `excluded_by_layer`, not as skipped objects, so they never block a build.
- **Move to layer** (`layer_assign`, or **MOVE SELECTION HERE**): moves objects or the current selection. Locked objects are refused. An object moved into a hidden layer is despawned and respawns when the layer is shown.
- **Auto-assign** (`layer_auto_assign`): suggests layers from what each object is:
  - room kit → Architecture
  - NPC records and AI → NPC
  - lights and fog → Lighting
  - audio → Audio
  - markers and splines → Debug
  - devices, areas, collision and occluders → Gameplay

  Only objects still on the generic Props/Gameplay layers move, unless `all_objects=true`. Preview first; applying is one undo step.
- **Create / rename / delete** layers: deleting moves the layer's objects, rooms, volumes and cameras to another layer (Props by default).

Visibility and isolation are view state and are saved with the project, but they are not undo steps. Assignment, locking, auto-assign, creating/updating and deleting layers are undoable.
