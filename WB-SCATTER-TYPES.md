# Polygon, volume and live-surface scatter

LocationStudio v0.30 adds four MCP tools. They use the existing saved Asset or
placed Object as the source, create ordinary editable scene objects, and commit
the copies as one undoable operation. Polygon and volume scatter allow up to
100 copies per call; live-surface scatter is capped at 32 copies and 25 m radius
because every point requires synchronous game raycasts.

## `wb_rng_create`

Create a reproducible seed before scattering. If `seed` is omitted, the tool
generates one. `sample_count` is optional and capped at 64.

```json
{"seed": 18421, "sample_count": 5}
```

It returns the normalized seed and preview numbers from the Park-Miller
generator (`48271 mod 2147483647`). Pass that seed unchanged to a scatter tool
to reproduce its placement pattern. Each scatter shape consumes random values
in its own order, so preview numbers are generator samples, not world positions.

## `wb_polygon_scatter`

Supply 3–128 finite world-space XY vertices in boundary order. The polygon must
have non-zero area and non-crossing edges. Points are sampled uniformly inside
the polygon. Optional `z` sets their base height; when omitted, LocationStudio
uses the active camera aim position's Z. `drop_to_ground=true` (default) then
raycasts down to place each copy on static/terrain ground. The polygon constrains
the scatter pivot; large asset geometry can extend beyond its edge.

```json
{
  "kind": "asset",
  "item_id": "asset_abc",
  "polygon": [{"x": 10, "y": 20}, {"x": 18, "y": 20}, {"x": 16, "y": 26}, {"x": 11, "y": 27}],
  "count": 24,
  "seed": 18421,
  "premise_id": "premise_abc"
}
```

## `wb_volume_scatter`

Pass a saved LocationStudio volume ID. Box, sphere and cylinder volumes are
sampled by their actual shape, dimensions, center and rotation. Copies stay
with their placement pivots inside the volume and are not dropped to ground.
Large asset geometry can extend past the volume boundary.

```json
{
  "kind": "asset",
  "item_id": "asset_abc",
  "volume_id": "volume_abc",
  "count": 30,
  "seed": 18421,
  "premise_id": "premise_abc"
}
```

The volume must be enabled and belong to the same location as the source.

## `wb_live_surface_scatter`

Aim at a visible game surface and scatter over a tangent disk around that hit.
Every sample is individually raycast against Static, Terrain and Dynamic
collision groups, and copies align to the hit normal. It requires a real camera
ray hit with a readable normal; a forward fallback or look-at entity is rejected
with an error. If any sample has no surface hit, the call fails before creating
copies.

```json
{
  "kind": "asset",
  "item_id": "asset_abc",
  "count": 12,
  "radius": 2.5,
  "distance": 20,
  "seed": 18421,
  "premise_id": "premise_abc"
}
```

Use the tool while the game bridge is live. Geometry that does not participate
in those game collision groups cannot be scattered onto. The resulting objects
use the normal World Builder/CET spawn adapters and report spawn failures.
