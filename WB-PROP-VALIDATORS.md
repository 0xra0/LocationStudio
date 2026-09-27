# Prop validators

v0.34.0 adds three read-only validators exposed in CET and through Claude MCP.

| MCP tool | Use | Data source |
| --- | --- | --- |
| `wb_clipcheck` | Find prop-to-prop overlap | Imported resource-local bounds; oriented rectangular footprints |
| `wb_fixturecheck` | Find static collision intrusions around a prop | Live, vertical `Static` raycasts across the placed prop footprint |
| `wb_fitcheck` | Check floor support, or wall clearance | Live `Static` rays; `mode="wall"` checks four horizontal directions at three heights |

Examples:

```text
wb_clipcheck(object_ids=["object-1", "object-2"])
wb_clipcheck(premise_id="premise-1", tolerance=0.03)
wb_fixturecheck(object_ids=["object-1"], cell_size=0.25, margin=0.25)
wb_fitcheck(object_ids=["object-1"], mode="live")
wb_fitcheck(object_ids=["object-1"], mode="wall", max_distance=4)
```

Live checks require a running game with CET spatial queries available. All checks are read-only and do not spawn, remove, teleport, or change props.

## Reading results correctly

The checker scripts use extracted GLB triangle geometry and custom developer data. LocationStudio does not have that geometry in the installed mod, so `wb_clipcheck` uses oriented rectangular footprints from imported bounds and reports that approximation. It may flag empty space inside irregular bounds and cannot see clipping between triangles that do not overlap the bounds.

`wb_fixturecheck` uses the stored bounds footprint at a configurable grid spacing. It raycasts against REDengine's `Static` group; hits are not labeled as vanilla versus modded. It is a live collision probe, not a mesh-level asset identity check.

`wb_fitcheck(mode="live")` samples four footprint corners and the center using `Static` collision only. Static-only avoids treating the checked dynamic prop as its own support, but will not find support from other dynamic props. `mode="wall"` casts Static rays out from the bounds center at 25%, 50%, and 75% of bounds height in four local horizontal directions.

Import bounds before running checks. Missing-bound objects are reported in `skipped`; they are never silently treated as clear. Fixture scans are capped at 500 cells per object, and each call is limited to 160 selected objects.
