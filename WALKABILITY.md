# Walkability and collision route checks

LocationStudio 0.39 adds **Spatial → Walkability** and MCP tool `walkability_check`. It samples a bounded 2D grid between the live position of V or a targeted NPC and a goal coordinate. Each cell needs a nearby floor hit and clearance for a small actor footprint. A breadth-first search connects clear cells, allowing a limited detour around obstacles.

## In game

1. Open **Spatial → Walkability**. This panel does not require a saved premise.
2. Aim at a floor point and click **Set goal from aim**. Or enter Goal world XYZ directly.
3. Choose `player`, or choose `npc` and put the NPC under the crosshair.
4. Click **Check live route**. Inspect status, sampled path length, and listed collision hits.

Grid spacing defaults to 1 m and detour margin to 2 m. The check is bounded to 120 cells; if the scan would exceed that limit it returns `inconclusive` and asks for a coarser grid or smaller margin. Increasing grid spacing makes the scan faster but can miss narrow openings. Clearance assumes a simple upright actor footprint and height.

## MCP

```text
walkability_check(
  goal_x=-1908.0, goal_y=-2469.5, goal_z=12.0,
  actor="npc", npc_key="812",
  grid_step=0.75, margin=2.0
)
```

For V, use `actor="player"` and omit `npc_key`. By default, the start is read from the live player or NPC position. To check between two manually specified coordinates, provide all of `start_x`, `start_y`, and `start_z`; in that mode the route scan does not require a live actor. NPCs can be selected by key from `npc_list_nearby`, or by leaving the key blank to use the crosshair target when using a live start.

The response uses these statuses:

- `candidate`: the sampled floor/clearance grid contains a route.
- `no_route_in_sampled_grid`: the bounded grid found no connected clear path.
- `inconclusive`: an endpoint lacks a compatible floor sample, the grid exceeds its cap, or input/runtime state prevents a useful scan.

Reported blockers are collision-hit positions and groups. A `Dynamic` hit may be a prop; CET's raycast result does not reliably identify the owning object, so the response does not invent object names. Scan a route through a doorway or corridor to find sampled hits that occupy it. A clear grid can miss thin or angled geometry between samples, and a blocked grid can include temporary dynamic objects.

## Navmesh limitation

This result is a **collision-based geometric route estimate**, not a REDengine navmesh/pathfinding answer. The current LocationStudio CET runtime interface has no verified navigation query to ask whether the game AI considers a route walkable. Doors, navigation links, stairs behavior, NPC locomotion, schedules, and collision filters can differ from this grid. Verify important routes by walking V through them and by observing the target NPC in game. A `candidate` is not proof the actor will walk it.
