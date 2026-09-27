# Collision authoring

LocationStudio 0.60 places and edits real collision instead of only checking object bounding boxes for overlap. Every collider is a World Builder `worldCollisionNode`, saved as an ordinary project object (kind `collision`, layer `shell`). It works with undo, scenes, the transform tools and World Builder export.

| Collider | Source | Dimensions |
| --- | --- | --- |
| Box | World Builder Collision Shape class | full size in metres (stored as WB half extents) |
| Capsule | World Builder Collision Shape class | radius and height |
| Sphere | World Builder Collision Shape class | radius |
| Imported collision mesh | World Builder's loaded **Collision Mesh** catalog | uniform scale |
| Fitted box | a placed object's imported bounds (`wb_bounds_import`) | bounds + padding |

Room-kit floor and wall colliders appear in the same lists, layers and passability preview.

## Layers (collision presets)

A collider's **preset** is its collision layer: World Dynamic, World Static, Player Blocker, NPC Trace Obstacle, Vehicle Blocker, Particle, Water and so on (59 in total). The preset names, their physics groups and the physics-material list are copied from World Builder's `colliderBase.lua`. `preset` and `material` are saved as the same indices World Builder reads, so a collider behaves exactly as if it had been placed in World Builder. The default is World Static, World Builder's own default.

`collision_presets` and the preset picker show each preset's physics groups (for example `Static + VehicleBlocker + TankBlocker + PlayerBlocker + NPCBlocker + PhotoModeCamera`). `collision_layers` shows which layers the project uses and how many colliders are on each.

## Visualization

**Visualize** sets World Builder's collider wireframe flag (`previewed`). World Builder draws the box, capsule or sphere outline in its collider color. **SHOW ALL / HIDE ALL COLLISION** toggles it for a premise, a layer, or chosen colliders. The flag is read when the node is built, so live colliders respawn when it changes. The wireframe is an editor aid and does not change what the collider blocks.

## Passability preview

`collision_passability`, or **PREVIEW PASSABILITY** in the Spatial → Collision tab, builds a grid over a room, a centre point or the area around V. For each actor (player, NPC or both), a cell is blocked when an enabled collider:
- has a physics group that blocks that actor,
- overlaps an upright actor capsule placed in that cell,
- and reaches between step height and head height above the floor level.

| Actor | Radius | Height | Step | Blocking groups |
| --- | --- | --- | --- | --- |
| player | 0.35 m | 1.8 m | 0.35 m | Static, Terrain, Dynamic, Destructible, PlayerBlocker |
| npc | 0.40 m | 1.9 m | 0.35 m | Static, Terrain, Dynamic, Destructible, NPCBlocker, NPCTraceObstacle |

These blocking rules are LocationStudio's interpretation of World Builder's group names. Override them per call with `player`/`npc` profiles `{radius, height, step, blocking_groups}`.

The result contains:
- a text map: `#` blocks both actors, `p` blocks only the player, `n` blocks only NPCs, `.` is free, `*` is the route, `S` and `G` are start and goal. The top row is the far (+Y) edge of the area.
- the colliders that caused the blocks;
- per actor, a start→goal route (8-neighbour, no diagonal corner-cutting) and its status: `route`, `no_route`, `start_blocked`, `goal_blocked` or `endpoint_outside_area`.

Box footprints follow the collider's yaw. A collider with roll or pitch uses its rotated axis-aligned bounds, which is conservative. Imported collision meshes need imported asset bounds, or they are listed under `skipped_colliders`.

Set `live=true` (or check **Cross-check with live collision rays**) to also run the existing collision-ray walkability scan between the same points. That scan includes vanilla world geometry, which the authored-collider grid does not.

## MCP

- `collision_presets`, `collision_list` and `collision_layers` are read-only.
- `collision_create_primitive`, `collision_search_meshes` / `collision_import_mesh` and `collision_fit_to_object` create colliders.
- `collision_update` changes shape, dimensions, layer, material, visualization or rotation. It is undoable, and live colliders respawn.
- `collision_visualization(visible, object_ids|premise_id|preset)`.
- `collision_passability(actor, room_id | center_x/center_y, grid_step, start_*/goal_*, live)`.

## Limits

- Passability is an estimate on one floor level from saved LocationStudio colliders. It does not include vanilla collision (use `live=true`), navmesh, doors, stairs or navigation links. The walkability and navigation guides cover those checks.
- Whether a preset stops V or an NPC in game depends on the engine's filter tables. The groups come from World Builder's hint list and the blocking rules are an interpretation. Verify important blockers by walking V into them.
- The mocked tests cover serialization into World Builder's collider fields, layer/material indices, visualization respawns, fitting to bounds, footprint rasterization, routing and the live-scan hand-off. They do not run PhysX. Check in game with [IN-GAME-CHECK.md](IN-GAME-CHECK.md).
