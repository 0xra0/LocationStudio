# Asset-backed World Builder generators

LocationStudio v0.28.0 adds five MCP operations. The cable, fence, road and
market operations create standard project objects from real imported World
Builder Static Mesh assets; when `spawn=true`, the live objects are materialized
through World Builder. They remain individually editable and removable in the
LocationStudio hierarchy.

## Before running a path generator

1. Build or refresh the World Builder asset catalog and import the desired
   Static Mesh (`asset_catalog_search`, `asset_catalog_get`,
   `import_catalog_asset`).
2. Inspect dimensions with `wb_bounds_info`. If the resource does not have
   measured/authored bounds, set them with `wb_bounds_set`. Bounds are required
   to turn requested meter lengths and widths into actual scale factors.
3. Create a premise and copy its ID from `list_premises`.
4. Supply 2–128 world-space points and the imported `asset_id`.

Example bounds (replace the values with dimensions for the selected resource):

```text
wb_bounds_set(
  asset_id="ASSET_ID",
  minimum={x=-1, y=-0.5, z=0},
  maximum={x=1, y=0.5, z=2},
  source="measured"
)
```

## Cable, fence and road

The operations distribute segments evenly along each polyline leg, align them
to the leg's yaw and pitch, and scale length to fit. Current bounds and road
width/height are interpreted in meters. Maximum path length is 2,000 m and the
maximum is 256 generated line segments. Fence may use a second imported mesh
for posts at each input vertex.

```text
wb_generate_cable(
  premise_id="PREMISE_ID", asset_id="CABLE_MESH_ID",
  points=[{x=0,y=0,z=2}, {x=0,y=12,z=2}, {x=5,y=18,z=3}],
  segment_length=2, spawn=true
)

wb_generate_fence(
  premise_id="PREMISE_ID", asset_id="FENCE_PANEL_ID",
  post_asset_id="FENCE_POST_ID",
  points=[{x=0,y=0,z=0}, {x=0,y=16,z=0}],
  segment_length=2.5, height=2, spawn=true
)

wb_generate_road(
  premise_id="PREMISE_ID", asset_id="ROAD_TILE_ID",
  points=[{x=0,y=0,z=0}, {x=0,y=40,z=0}, {x=15,y=55,z=0}],
  segment_length=8, width=7, height=0.25, spawn=true
)
```

If the World Builder runtime is unavailable and `spawn=true`, the operation
stops before adding project objects. Set `spawn=false` to create editable
project records without trying to materialize them immediately. If an
individual runtime spawn still fails after preflight, its object ID and error
are returned in `failed`; the records are retained so the user can fix/retry
them instead of losing authored work.

Mesh origins/pivots vary across game resources. Bounds correct scale, but do
not automatically correct an off-center mesh pivot or guarantee a seamless
UV/material join. Preview and adjust the resulting objects in World Builder.

## Market grid

`wb_generate_market` arranges the supplied imported Static Mesh IDs in a
rotatable grid. The supplied IDs repeat in order if the grid has more slots
than assets. It supports at most 16 rows/columns and 128 objects.

```text
wb_generate_market(
  premise_id="PREMISE_ID",
  asset_ids=["STALL_A_ID", "STALL_B_ID", "CRATE_ID"],
  origin={x=100,y=200,z=4}, rows=2, columns=4,
  spacing_x=3, spacing_y=5, yaw=30, spawn=true
)
```

## NodeRef marker (metadata only)

```text
wb_generate_noderef(
  node_ref="my_market.vendor_01",
  position={x=100,y=200,z=4}, yaw=30
)
```

This creates a persistent LocationStudio semantic marker with a unique
`metadata.world_builder_node_ref`. It is useful as a named authoring anchor,
but it does **not** create a live REDengine node or a World Builder streaming
node. Native NodeRef output is only produced by a compatible build/export
workflow that has the required node-type templates; do not treat the marker as
a compiled or deployable game object.

## In-game verification

1. Confirm World Builder is initialized in LocationStudio's status line.
2. Invoke each generator on a safe area using a small path (two or three
   segments) and `spawn=true`.
3. Confirm the returned `count`/`spawned_ids`, then inspect the generated
   objects in the hierarchy and World Builder selection/gizmo.
4. Move/delete a segment and save/reload the project to verify objects remain
   independent and persistent.
5. Test `spawn=false` separately; it should create records without live handles.

Headless tests validate calls, transforms, scaling contracts, persistence and
error paths; they cannot confirm REDengine visuals or in-game mesh pivots.
