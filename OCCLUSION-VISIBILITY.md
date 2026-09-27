# Occlusion and visibility helpers

LocationStudio 0.63 adds tools to author occlusion and to see what saved cameras can actually see.

## Occluders

World Builder exposes one occlusion primitive: the **Static Occluder** (`worldStaticOccluderMeshNode`). Anything completely behind it is not rendered. LocationStudio authors it with World Builder's own fields:

| Mesh | World Builder mesh | Size |
| --- | --- | --- |
| `box` | `engine\meshes\editor\box_occluder.w2mesh` | full X × Y × Z metres |
| `plane_one_sided` | `plane_occluder_onesided_xz.mesh` | width X × height Z |
| `plane_two_sided` | `plane_occluder_twosided_xz.mesh` | width X × height Z |

`occluder_type` is World Builder's `visWorldOccluderType` index (0 by default). **Visualize** toggles World Builder's preview box.

- **OCCLUDE SELECTED ROOM WALLS** (`visibility_occlude_room`) adds a two-sided plane occluder over every *solid* span of a room's walls. Door and window openings are left clear, so the occluders never hide what a doorway or window shows. The planes sit 5 cm inside the room.
- Occluders are ordinary project objects, so undo, the transform tools, scenes and export all work with them. `visibility_update_occluder` changes the mesh, size, yaw, type or visualization; live occluders respawn.

**Visibility volumes and portals are not supported.** World Builder has no class for them, so LocationStudio does not fake them. `visibility_capabilities` reports this.

## Potentially visible rooms (PVS) from saved cameras

`visibility_pvs`, or **COMPUTE VISIBLE ROOMS** in Spatial → Visibility, checks each enabled saved camera against every room in scope:

- **Camera direction:** the camera's saved look-at point is used; if it has none, its rotation is used (the game convention: yaw 0 faces +Y). The result reports which source was used.
- **View cone:** conservative. The saved FOV is treated as vertical and widened to a 16:9 horizontal FOV, plus 2° of margin, so the estimate errs on the side of *visible*.
- **Samples:** each room is sampled at 18 interior points (a 3 × 3 grid at 25 % and 75 % of its height). A room is potentially visible if any in-view sample within `max_distance` (150 m) has a clear line of sight.
- **What blocks a line of sight:**
  - the solid part of any room's walls; door and window openings (offset, width, sill, height) let it through;
  - any enabled authored occluder (boxes as oriented boxes; planes as 5 cm thick slabs).

  Every room's walls and every occluder count as blockers, whatever premise they belong to.

Each camera lists its visible rooms (visible fraction, nearest visible distance, whether the camera is inside) and its hidden rooms with the reason: out of view, or blocked by named walls or occluders. The report also lists rooms that no camera can see. `live=true` adds a collision ray from each camera to each visible room's centre, as a cross-check against vanilla geometry.

## Large hidden meshes

`visibility_hidden_meshes`, or **FIND HIDDEN LARGE MESHES**, looks at static, rotating, dynamic and proxy meshes and entity templates that have imported bounds (`wb_bounds_import`). A mesh counts as large when its largest dimension is at least 6 m or its volume at least 40 m³. It is flagged when:
- none of its sample points (centre plus 8 inset corners) can be seen from any saved camera,
- and it is still enabled.

Spawned meshes get a stronger suggestion: disable it, move it into a world-state or scene variant, or add a camera if the view is actually used. Meshes without bounds are counted and listed as unchecked.

## Limits

- The geometry is authored rooms and occluders only. Props, mesh shapes and the vanilla world don't block in the estimate; `live=true` adds collision rays.
- "Hidden" means hidden from every *saved camera*. Gameplay viewpoints you have not saved as cameras are not considered. Add cameras for important views before acting on the results.
- The analysis reads the project and never changes it. Deciding what to disable is up to you.
