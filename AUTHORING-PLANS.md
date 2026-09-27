# LocationStudio authoring plans

An authoring plan is declarative JSON executed by the same Lua operations used
by the in-game editor. It is not arbitrary Lua. A plan is validated before its
first mutation, runs synchronously in CET, and commits as one Undo operation.

Copy one file from the installed `examples` directory to
`data/authoring-plan.json`. In **HELP + START**, press **VALIDATE PLAN FILE**, then
**RUN PLAN FILE**. The CET hotkey **Run data/authoring-plan.json** uses the same
path.

```json
{
  "format": "locationstudio-authoring-plan",
  "version": 1,
  "name": "Tiny furnished room",
  "origin": "player",
  "steps": [
    {"op":"create_premise","as":"place","name":"Clinic"},
    {"op":"create_room","as":"room","premise_id":"$place","name":"Treatment","width":6,"depth":5,"height":3,"spawn":true},
    {"op":"place_asset","as":"chair","asset_query":"Starter Office Chair","premise_id":"$place","room_id":"$room","offset":{"x":1,"y":0,"z":0},"spawn":true},
    {"op":"create_scene","as":"scene","name":"Clinic Scene","premise_id":"$place","room_ids":["$room"],"object_ids":["$chair"],"activate":true}
  ]
}
```

`origin` may be `player`, `camera`, or an explicit transform. `offset` is local
to that origin. A step with `"as":"chair"` exposes its created id as `$chair`
to later steps. References must point backward; missing and forward aliases are
rejected before execution.

Supported operations:

- `register_asset`: add a `.ent` or complete World Builder resource definition.
- `create_premise`, `create_room`, `add_opening`: architectural ownership and
  real game-asset room pieces.
- `place_asset`: place any registered Project Asset by exact id or unambiguous
  name/template query and optionally spawn it.
- `create_location`, `create_volume`, `create_camera`, `create_route`: gameplay
  and cinematic authoring data.
- `create_group`, `create_scene`, `capture_scene`: persistent editable
  collections, including capture of the current premise contents.
- `edit_scene_members`: add, remove, or replace validated room/object/point/
  volume/camera/route references without deleting those authored items.
- `move`: translate/rotate an existing premise, room, object, point, volume, or
  camera; live objects are refreshed through their actual backend.
- `spawn`, `activate_scene`, `isolate_scene`, `deactivate_scene`: materialize or
  cleanly remove saved scene objects through their real runtime backends.

Direct `.ent` assets spawn with CET's entity spawner. Imported meshes, lights,
collision, areas, AI nodes, and other World Builder entries keep their full
resource metadata and use World Builder. Rooms never use blank white debug
primitives: their visible shell is composed from the configured room kit.

The engine limits version-1 plans to 100 steps. Version-2 plans (`"version": 2`, up to 2000 steps) add the operations the [Environment Definition Language](ENVIRONMENT-DEFINITION-LANGUAGE.md) compiles to: `import_resource`, `place_resource`, lights, collision, VFX, audio emitters and reverb, occluders, interactables, NPCs, workspots, NPC routes and waypoints, device-logic graphs, fact links, navigation, splines, room-kit settings and `edl_begin`, which replaces a previous build of the same document. Most authors should write EDL rather than version-2 plans by hand. A failed step triggers runtime cleanup and
restores model/history/selection/dirty state. If cleanup itself is refused, the
project remains owned and enters explicit recovery rather than silently losing
track of a live object.
