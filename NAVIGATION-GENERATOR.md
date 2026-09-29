# Navigation generator

LocationStudio v0.82 generates navigation from the geometry it generates. The generator builds a navigation graph from the [semantic surfaces](SEMANTIC-SURFACES.md) of parametric rooms, grammar builds, stairs, ramps and platforms. The graph contains:

- **Navigation surfaces:** walkable floor, cleared for an agent's radius and height and merged into area polygons, one area node each.
- **Door transitions:** every door of a parametric room, linked to the floor on both sides, with its width and height checked against the agent.
- **Stairs and ramp links:** grouped into flights, each with a bottom and a top.
- **Off-mesh connections:** drops from ledges (one way, or two way when they are low enough to climb) and jumps over gaps.
- **Room links:** which rooms reach which, and through what. Rooms that cannot be reached from the entry are reported.

A validation run then sends a real NPC along every door, flight, ramp and off-mesh link, using the game's own AI movement, and records what the NPC actually does.

Open it at **Spatial → Navigation → Generate from geometry**, or use the MCP tools:

| Tool | What it does |
| --- | --- |
| `nav_parameters` | Parameters, defaults and ranges (works offline) |
| `nav_preview` | Dry run: what the graph would contain, with doors, flights, off-mesh links, room links and warnings |
| `nav_generate` | Generate and save a graph (one undo step) |
| `nav_regenerate` | Regenerate a graph in place from its saved scope, after the geometry changed |
| `nav_report` | A graph's report, whether it is stale, and its last validation |
| `nav_delete` | Delete a graph |
| `nav_validate_plan` | The legs a validation run would walk |
| `nav_validate_start`, `nav_validate_status`, `nav_validate_cancel` | Validate with a real NPC |

## What it is, and what it is not

The generated graph is LocationStudio navigation data, in the same format as [imported graphs](NAVIGATION.md). `navigation_graph_check`, `navigation_workspot_report` and `walkability_check` (with `navigation_graph_id`) all use it.

It does **not** change REDengine's navmesh. The game's navmesh is baked into the world's streaming data, and CET offers no way to write or rebuild it. Geometry that LocationStudio spawns through World Builder or CET does not add to it either. An NPC in a generated room therefore walks on whatever navmesh was already there, which may not match the new walls and floors, or may not exist at all.

The graph is still useful:

- it shows that the layout is connected, as designed, for an agent of a given size;
- it lists every door, flight, ramp and off-mesh link that a native navmesh would need;
- its polygons and links are an export-ready description for a navmesh tool.

**NPC validation** is the check against the real engine.

## Generating

```text
nav_preview(premise_id="premise_...")
nav_generate(premise_id="premise_...", params={"agent_radius": 0.4})
```

The scope is one of:

- `premise_id`: every generated room and object of a premise;
- `room_ids`: those rooms and the objects in them;
- `build_id`: a [grammar build](ENVIRONMENT-GRAMMAR.md);
- `all_rooms`: the whole project.

`entry` (`[x, y, z]`) picks the area that reachability is measured from. Without it, the entry is the largest area of the island that holds the most rooms.

`graph_id` replaces an earlier generated graph. A graph for a grammar build is also found by its build, so `nav_generate(build_id=...)` replaces it.

### Grammar builds

`grammar_generate(..., navigation=True)` generates the build's graph in the same undo step. Pass a parameter object instead of `True` to set parameters.

- Once a build has a graph, `grammar_regenerate` regenerates the graph with it.
- `grammar_remove` removes the graph.
- `navigation=False` skips it.

### Parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `cell` | 0.25 m | Grid cell. Smaller cells find narrower gaps and take longer |
| `agent_radius` | 0.35 m | Floor closer than this to a wall, edge or obstacle is left out. Doors narrower than twice this are `too_narrow` |
| `agent_height` | 1.8 m | Headroom needed. Floor under something lower is left out. Doors lower than this are `too_low` |
| `max_step` | 0.35 m | Highest step walked without a link |
| `max_slope` | 45° | Steeper walkable surfaces are left out |
| `max_drop` | 2.0 m | Highest ledge for a drop link; 0 = no drops |
| `max_jump` | 1.0 m | Widest gap for a jump link; 0 = no jumps |
| `max_climb` | 0 m | Drops up to this height also get a climb back up; 0 = drops are one way |
| `tile` | 4 m | Largest side of an area polygon |
| `door_snap` | 1.0 m | How far from a door its floor may be |

## How it works

1. **Surfaces.**
   - *Walkable:* surfaces that face up and are in the `walkable` group (`floor`, `ground`, `sidewalk`, `platform`, `roof`, `stairs`, `ramp`, `road`, or any surface with a `walkable` trait).
   - *Walls:* vertical surfaces. A door opening leaves a gap in them.
   - *Headroom:* ceilings and other surfaces that face down.
2. **Grid.** Each walkable surface is sampled on the grid. Several levels can share a grid column: a floor, the stairs above it and a platform above that.
3. **Headroom.** A floor cell is left out when any of these is true:
   - another walkable surface is less than `agent_height` above it;
   - a ceiling is less than `agent_height` above it;
   - it is under solid stairs or a solid ramp.
4. **Obstacles.** Objects in the scope take floor out by their bounds, grown by `agent_radius`. This covers furniture, props, crates and hand-placed colliders. It does not cover:
   - room shells and generated colliders;
   - decals;
   - objects lower than `max_step`;
   - objects higher than `agent_height` above the floor.
5. **Links between cells.** Neighbouring cells are linked when:
   - the step between them is no higher than `max_step` (more on stairs and ramps);
   - no wall is in between.

   Links straight across a door line are replaced by the door's own links.
6. **Clearance.** Floor closer than `agent_radius` to the edge of the walkable area is left out. Pockets too small to stand in are dropped.
7. **Areas.** The remaining cells are merged into rectangles, one surface at a time and no larger than `tile`. Each rectangle is a polygon with an area node. Neighbouring areas are linked:
   - `stairs` when either area is stairs;
   - `ramp` when either area is a ramp;
   - otherwise `walk`.
8. **Doors.** Each door of a parametric room is a door node. Floor is looked for on both sides, and a door that two rooms share is one node. Its status is one of:

   | Status | Meaning |
   | --- | --- |
   | `connected` | Floor on both sides |
   | `exit` | Floor inside only, and nothing outside |
   | `blocked` | Floor missing on a side because something stands there. The blocking objects are listed |
   | `too_narrow` or `too_low` | The door's links are disabled |

9. **Off-mesh links.** Links are looked for from the ledges of floors and platforms, but not from the sides of stairs and ramps.
   - A **drop** goes down onto lower floor within reach. It is up to `max_drop` high and does not pass through a wall.
   - A **jump** crosses a real gap to floor at the same level. The gap is up to `max_jump` wide and has no furniture in it.

   Each stretch of ledge gets one link. Each link runs between two ledge nodes, with walk links to the areas on either side.
10. **Flights.**
    - *Grouping:* connected stairs areas form a flight, and so do connected ramp areas.
    - *Ends:* the bottom and top are where the flight meets other floor.
    - *Status:* `connected` (it joins two levels), `one_end` or `isolated`.
11. **Report.**
    - Islands of connected areas.
    - Each room's status: `reachable`, `unreachable`, `one_way` (entered by a drop and cannot be left) or `no_walkable_area`.
    - Room links: `door`, `open`, `stairs`, `ramp`, `off_mesh` or `exit`.
    - Warnings.

`nav_report` compares a digest of the scope's objects with the one saved at generation. `stale: true` means the geometry moved or changed; run `nav_regenerate`.

## Validating with an NPC

```text
nav_validate_plan(graph_id="nav_...")
nav_validate_start(graph_id="nav_...")          # NPC under the crosshair
nav_validate_start(graph_id="nav_...", npc_key="812")
nav_validate_start(graph_id="nav_...", record="Character.<a record the user gives>")
nav_validate_status()
```

**Legs.** A run walks one leg per:

- connected door (from the floor on one side to the floor on the other);
- stairs flight and ramp (bottom to top; `both_directions` adds the way down);
- off-mesh link.

`legs` picks kinds: `door`, `stairs`, `ramp`, `off_mesh`, and `rooms` (between the largest areas of linked rooms). `custom` adds your own legs as `[{start, goal}]`. `max_legs` caps the run (at most 60).

**Walking a leg.**

1. The NPC is teleported to the start and settles for a second.
2. It gets an `AIMoveToCommand` to the goal. The command uses the game's navigation, not `ignoreNavigation`, and walks unless `run` is set.
3. Its position is sampled four times a second.

**Leg status.**

| Status | When |
| --- | --- |
| `traversed` | The NPC comes within `tolerance` of the goal (default 0.75 m, and 1 m in height) |
| `stalled` | No progress for `stall_time` seconds (default 5) |
| `timeout` | Time runs out: 10 s plus the time to walk 2.5× the straight distance at 0.8 m/s, times `timeout_scale` |
| `command_failed` | The AI command could not be built or sent |
| `npc_lost` | The NPC could not be found or teleported |

**Verdicts.** Each leg is compared with the graph:

| Verdict | Meaning |
| --- | --- |
| `confirmed` | The graph and the NPC agree |
| `engine_disagrees` | The graph says the leg works, but the NPC could not walk it. Usually the game has no navmesh there, or navmesh that does not match the new geometry |
| `engine_only` | The NPC walked a leg that the graph does not connect |
| `expected_failure` | Both fail |

Door legs also report whether the NPC passed within 1 m of the door (`passed_via`). Stairs legs report the height reached.

**Where results go.** They are saved on the graph (`validation`), and each link records its last result. The trace is kept at up to 60 points. While a transform edit, stamp stroke or authoring plan is open, the results wait until it closes.

**Spawned NPCs.** A record passed as `record` is spawned for the run and removed afterwards. Take the record from the user or from the NPC tools; never invent one.

A run moves and teleports the NPC. Tell the user before starting one, and use a stand-in NPC, not a quest character.

## Limits

- **Geometry sources:** only generated geometry with semantic surfaces. Room-kit rooms and game-asset floors are walkable only when tagged by hand (`surface_tag`).
- **Doors:** only doors of parametric rooms. Doors placed as separate objects are not known, and neither are openings between rooms made by hand.
- **Obstacles and headroom:** these use bounding boxes, so an L-shaped desk takes its whole box.
- **Elevators, ladders and vaults:** not generated.
- **Off-mesh links:** these are candidates. NPCs only use off-mesh links that the game's navmesh defines.
- **Validation:** the AI command API (`AIMoveToCommand`, `AIPositionSpec`, `WorldPosition`) is guarded but unverified in this CET build. If every leg reports `command_failed`, report the detail, which names the step that failed. A validation run proves what one NPC did once; archetype, schedules, combat state and door locks can change the outcome.
