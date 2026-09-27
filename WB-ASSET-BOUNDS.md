# World Builder asset bounds

LocationStudio stores a resource-local axis-aligned bounding box on each Project
Asset as `metadata.asset_bounds`. Coordinates are in meters relative to the
asset's authored pivot. Bounds are descriptive authoring metadata: LocationStudio
does not change a `.mesh`, create a WolvenKit resource, or add a runtime
collision collider when these values are edited.

## Manifest format

Use a JSON file produced by your asset inspection workflow, or write one by
hand after measuring the resource. The top-level format identifier prevents
silently accepting unrelated JSON. Each row resolves to one existing Project
Asset by exact `asset_id`, exact `template`, or unambiguous `name`.
The packaged `examples/asset-bounds-manifest.json` is a template only: replace
its placeholder asset/resource IDs and all illustrative dimensions with
measured values before applying it.

```json
{
  "format": "locationstudio-asset-bounds/1",
  "name": "clinic prop bounds",
  "source": "WolvenKit measurement",
  "assets": [
    {
      "asset_id": "asset_123",
      "resource": "base\\environment\\clinic\\exam_table.mesh",
      "bounds": {
        "min": {"x": -1.20, "y": -0.35, "z": 0.00},
        "max": {"x": 1.20, "y": 0.35, "z": 0.82},
        "units": "m"
      }
    }
  ]
}
```

`max` must be strictly greater than `min` on all axes. Non-finite numbers and
units other than meters are rejected. Convert centimeters or raw engine units
before import. Import validates the entire batch first; a successful import is
one undoable project change. Dry-run is the default.

## MCP workflow

1. Create/import the Project Asset using `import_catalog_asset` or the existing
   asset registration workflow.
2. Call `wb_bounds_import(manifest_file="/path/to/bounds.json")` to preview.
3. Repeat with `dry_run=false` to store the bounds. Or use
   `wb_bounds_set(asset_id, minimum, maximum, source)` for one measured asset.
4. Call `wb_bounds_info(asset_id)` to verify stored values and derived
   dimensions.
5. Call `wb_bounds_fit(asset_id, target_size, mode="stretch"|"contain")` to
   calculate a scale suggestion. It does not mutate asset scale.
6. Place the asset. Its authored local bounds and source asset ID are copied
   into the object. `wb_bounds_world_aabb(object_id)` transforms all eight
   corners by the object's current scale, Euler rotation and position.
7. Call `wb_bounds_overlap(object_ids, margin=0)` for broad-phase overlap
   candidates. A returned overlap means the AABBs intersect, not necessarily
   that the actual meshes collide; AABBs intentionally favor speed and safety.

The `wb_bounds_set` operation updates the asset and any tracked objects created
from it in one undo step. Imported assets without bounds remain supported; their
existing `size` value remains a fallback scale hint, never fabricated geometry.

## Coordinate and math contract

- Bounds are local to the mesh/resource pivot, before the placed object's
  transform.
- World AABB calculation applies per-axis scale only when the World Builder
  metadata confirms `apply_scale=true`, then roll, pitch, yaw, and world
  translation to all eight corners. Direct CET `.ent` objects cannot be scaled
  live; their `size` remains a layout hint and is not used as geometry scale.
- `stretch` computes independent X/Y/Z scale multipliers to match the target
  dimensions. `contain` chooses one uniform multiplier that fits inside all
  three target dimensions. `scale_supported_by_backend=false` means the result
  is a planning suggestion only, not a value that can be applied to a live CET
  entity.
- Overlap is strict on each axis; boxes that only touch at a face/edge/point do
  not count as overlapping. `margin` expands the tested separation tolerance
  and must be non-negative.
- These results are useful for layout warnings, fit estimates and collision
  broad phase only. Exact mesh collision requires the actual game's collider or
  World Builder collision resource.

## Troubleshooting

- `asset reference is ambiguous`: use the exact Project Asset ID in the
  manifest.
- `no explicit bounds`: inspect or set a record; the mod deliberately does not
  guess dimensions from resource names or arbitrary `size` hints.
- `object has no imported asset_bounds metadata`: the object was not created
  from a bounded asset, or was authored before asset-ID linkage was added. Set
  bounds, then replace/re-place that legacy object or edit its project metadata
  explicitly.
- `bounds units must be meters`: convert source measurements to meters and
  retry; the tool will not silently scale imported numbers.
