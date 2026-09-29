# Generated bounds

Every generated resource gets its bounds computed from its geometry, so none have to be typed in. This covers:

- procedural objects (generators, CSG, parametric-room pieces);
- the colliders generated for them;
- parametric rooms.

In game the bounds are kept in `metadata.generated_bounds`. Build Mod recomputes them from the exact mesh and uses them to write the nodes.

Open it at **Spatial → Bounds**. It is also available through the MCP tools `bounds_get`, `bounds_refresh`, `bounds_settings` and `bounds_report`.

## What is computed

| Bounds | How |
| --- | --- |
| **Local** | Object-frame AABB with exact extents per shape: rotated boxes, wedges, cylinders at any angle, spheres and prisms. For CSG with curved leaves, it is the tree bounds clipped to the preview grid plus one cell, and the record is marked `exact: false`. |
| **World** | The world AABB of the oriented local box, using the procedural rotation convention R = Rz(yaw)·Rx(pitch)·Ry(roll). The oriented box and a bounding sphere are kept too. |
| **Collision** | The union of the object's generated colliders. Each collider also has its own record. |
| **Visibility** | The render AABB (colliders are not rendered), plus the **visibility distance** at which the bounding sphere subtends `min_screen_angle`: `radius / tan(angle / 2)`, clamped to `[min_range, max_range]`. |
| **Streaming** | The primary range is the visibility distance plus `stream_margin`, clamped; the secondary range is that times `secondary_factor`. The record also holds the world AABB grown by the range and the streaming cells (`cell_size`) the object overlaps. A manual `stream_range` on the object still wins (`source: manual`). |

A parametric room also gets the bounds of all its pieces, which cover world, collision, visibility distance and streaming. They are stored on the generated-room record.

Keeping bounds current:

- Records are stored on create, update and collider generation.
- `bounds_get` recomputes a record whose transform has changed.
- `bounds_refresh` recomputes a whole scope.
- The overlap, fit and visibility tools (`asset_bounds:world_aabb`) now use the generated bounds for generated resources. Before this, tilted procedural geometry used the wrong rotation order there. Hidden-mesh checks now include generated geometry.

## Settings (`bounds_settings`)

| Setting | Default | Meaning |
| --- | --- | --- |
| `min_screen_angle` | 1.0° | Angular size at which an object stops being visible. |
| `stream_margin` | 10 m | Streaming starts this much before the object becomes visible. |
| `min_range` / `max_range` | 30 / 800 m | Clamp for the visibility and streaming distances. |
| `secondary_factor` | 1.2 | Secondary range = primary × this. |
| `cell_size` | 128 m | The streaming grid used for the cell report. Match the export's `streaming_x/y/z`. |
| `padding` | 0 m | Grows the local bounds. |

## Build Mod

The procedural stage computes bounds from the **built mesh**, which is exact for CSG too, and uses them as follows:

- Each generated `worldMeshNode` gets `primaryRange` and `secondaryRange` from the automatic streaming ranges, instead of a fixed 150 m.
- The node goes into the sector that holds its **world-bounds centre**, not its pivot.
- Sectors grow by the node's **rotated** world AABB.

The stage report lists each object's local and world bounds, ranges, visibility distance and cells. It warns when the saved in-game bounds differ from the mesh, for example for approximated CSG. In that case the mesh bounds are used. `bounds_report` runs the same computation offline.

The native sector writer keeps World Builder's own conventions for its `nodeData` fields. The ranges are what change.

## Preflight

The **Generated bounds** check covers four cases:

- A **warning** when a manual `stream_range` is shorter than the visibility distance, because the object would pop in.
- A note for objects spanning several streaming cells. They stream with the sector that holds their centre.
- A note for approximate CSG bounds.
- Records that are missing or stale are refreshed.

## Limits

- Visibility distance is a screen-size rule, not a renderer measurement. Check pop-in in game and adjust `min_screen_angle` or `stream_margin`.
- Bounds of World Builder catalog assets still come from imported bounds (`wb_bounds_import`); only generated resources are computed.
