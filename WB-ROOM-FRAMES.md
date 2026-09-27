# Local room frames

LocationStudio v0.36.0 stores named coordinate frames in the project. A frame has a world origin and two orthonormal XY axes: local `u` and `v`. Local `z` maps to world +Z. Coordinates and origins use meters; yaw is degrees, counterclockwise around +Z.

## Create the 45-degree frame

```text
create_room_frame(
  name="Clinic Room A",
  origin={"x":-1908, "y":-2469.5, "z":24},
  yaw=45
)
```

Yaw creates a right-handed pair:

- `u=(cos(yaw), sin(yaw))`
- `v=(-sin(yaw), cos(yaw))`

You can instead supply explicit `u_axis={x,y}` and `v_axis={x,y}`. They must be unit-length, perpendicular, and right-handed.

At yaw 45, local `u=1, v=0, z=0` maps to approximately world `(-1907.2929, -2468.7929, 24)`. The inverse is available through `world_to_room_frame`.

## Place and move objects

```text
place_object_in_frame(
  premise_id="premise-1",
  frame_id="frame-1",
  name="Exam chair",
  template="base\\environment\\decoration\\furniture\\...",
  u=2.0, v=3.0, z=0.0, yaw=90
)

move_object_in_frame(
  object_id="object-1",
  frame_id="frame-1",
  u=1.5, v=2.0, z=0.0, yaw=0
)
```

The placement/move operations convert local coordinates to the object's stored world transform. Moves refresh the live entity by default; pass `respawn=false` to update only project data. Omit move `yaw` to preserve the object's existing local yaw. The object keeps a `metadata.local_frame` record for provenance.

Existing `place_object` remains premise/room-relative, and `update_object_transform` remains world-coordinate based. Use the explicit `*_in_frame` tools whenever coordinates are `u/v/z`.

## Frame edits

`list_room_frames`, `update_room_frame`, and `delete_room_frame` manage saved frames. Editing or deleting a frame does not move existing objects; the frame is a coordinate reference for later placement and movement, not a live parent or constraint. `room_frame_to_world` and `world_to_room_frame` allow checking conversions before placing anything.
