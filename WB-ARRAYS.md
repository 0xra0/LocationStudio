# World Builder array and layout tools

These MCP tools operate on **placed LocationStudio objects**, including editable
World Builder backed objects. They copy the selected object or group and leave
the source in place. Every array is authored as a single undo step. `spawn=true`
asks the live placement adapter to spawn the copies; with `spawn=false`, copies
are saved but remain unspawned. The game may reject a resource the current
World Builder/runtime cannot spawn; check the result's `failed` list and debug
log in that case.

Arrays create additional copies, not a total including the originals. Each
operation is limited to 100 new objects in a transaction. Multi-object
selections must belong to the same location.

## Path array

`wb_path_array(object_ids, path_points, count=5, orient_to_path=true, spawn=true)`
places `count` copies at equal distances along a 3D polyline. Points need finite
world `x`, `y`, and optional `z`; provide 2–256 distinct consecutive points.
Copies are sampled inside the endpoints at `i/(count+1)`, so the source group
remains separate. With orientation enabled, each group copy faces along its
local path segment. This tool uses straight segments between supplied points;
it does not smooth curves or project onto terrain.

```json
{"object_ids":["object-123"],"path_points":[{"x":10,"y":20,"z":0},{"x":20,"y":20,"z":0},{"x":25,"y":30,"z":1}],"count":6,"orient_to_path":true,"spawn":true}
```

## Radial array

`wb_radial_array(object_ids, center, radius, count=8, start_angle=0,
sweep_angle=360, rotate_objects=true, spawn=true)` places copies on a world-space
circle or arc. A full 360-degree sweep spaces copies without repeating the first
angle. Partial sweeps leave equal margins at each end. Angles are degrees in XY;
`center` includes world `x`, `y`, and `z`. With rotation enabled, each copy is
rotated by its sampled angle relative to the source group.

```json
{"object_ids":["object-123"],"center":{"x":100,"y":200,"z":5},"radius":4,"count":8,"start_angle":0,"sweep_angle":360,"rotate_objects":true}
```

## Grid array

`wb_grid(object_ids, origin, rows=2, columns=2, spacing_x=2, spacing_y=2,
spacing_z=0, yaw=0, rotate_objects=false, spawn=true)` places a copy of the
entire selection at each grid cell, beginning at `origin`. Rows advance along
local +Y and columns along local +X, rotated by `yaw` degrees. The source remains
where it is. Positive or negative spacings are accepted; both axes cannot be
zero at once. Set `rotate_objects=true` to rotate each copied group by the grid
yaw as well.

```json
{"object_ids":["object-123","object-456"],"origin":{"x":100,"y":200,"z":5},"rows":3,"columns":4,"spacing_x":2.5,"spacing_y":3,"yaw":90,"spawn":true}
```

## Align and distribute

LocationStudio already implements align and distribute in
`layout_object_selection`, routed to `layout_object_group`. `wb_align` and
`wb_distribute` are short aliases over that same implementation, so they share
its locking, refresh, validation and undo behavior.

- `wb_align(object_ids, axis, mode="center", active_id="")`: axis is `x`, `y`,
  or `z`; mode is `center` (mean position), `active`, `min`, or `max`.
- `wb_distribute(object_ids, axis)`: evenly spaces at least three objects
  between their current minimum and maximum coordinate on the chosen axis.

```json
{"object_ids":["object-123","object-456","object-789"],"axis":"z","mode":"active","active_id":"object-123"}
```

Both are authored transforms on project objects. They do not modify source mesh
files or infer object bounds, so alignment is by object origin/pivot.
