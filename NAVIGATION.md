# Navigation data and reachability

> Since v0.82, graphs can also be **generated** from generated geometry, and validated with a real NPC. See [NAVIGATION-GENERATOR.md](NAVIGATION-GENERATOR.md). Generated graphs use the format below and work with every tool on this page.

LocationStudio v0.52 adds a portable navigation graph importer, a Navigation tab, typed transitions, and graph connectivity checks. It does **not** read or query REDengine's live AI navmesh. CET's current mod API usage in this project provides collision queries but no verified navmesh/path API, so native results are reported as unavailable instead of guessed.

## What this does

- Import world-coordinate node/link graphs and optional walkable surface polygons through MCP.
- Display nodes, polygons, and links in **Spatial Editor → Navigation**.
- Preserve door, stair, elevator, jump, and off-mesh links explicitly; links can be one-way, disabled, weighted, and annotated.
- Run Dijkstra over enabled imported links. The tool reports `reachable_in_imported_graph`, `unreachable_in_imported_graph`, `unmapped`, or `unavailable`.
- Check all saved NPC workspots from the current player position and show the graph result beside each workspot.

An unreachable result means disconnected in the selected imported graph only. It does not establish that the game AI cannot reach the workspot. Likewise, connected graph nodes do not prove the actual navmesh, door state, actor size, or NPC schedule permits movement. Use **Walkability** separately for the existing floor/clearance collision estimate.

The MCP `walkability_check` tool accepts optional `navigation_graph_id`. When supplied, it checks that imported graph instead of running the collision-grid scan; without it, the existing collision-grid behavior remains the default.

## Import format

Call MCP `navigation_graph_import` with JSON shaped like this (positions are world coordinates):

```json
{
  "name": "Clinic floor 1",
  "source_format": "my-nav-export-v1",
  "source": "optional provenance",
  "nodes": [
    {"id": "lobby", "name": "Lobby", "position": {"x": 1, "y": 2, "z": 3}},
    {"id": "clinic", "name": "Clinic", "position": {"x": 5, "y": 2, "z": 3}}
  ],
  "polygons": [
    {"id": "floor_a", "surface": "walkable", "vertices": [
      {"x": 0, "y": 0, "z": 3}, {"x": 4, "y": 0, "z": 3}, {"x": 4, "y": 4, "z": 3}
    ]}
  ],
  "edges": [
    {"id": "clinic_door", "from": "lobby", "to": "clinic", "kind": "door", "one_way": false, "cost": 1}
  ]
}
```

Allowed edge kinds: `walk`, `door`, `stairs`, `ramp`, `elevator`, `jump`, `off_mesh`, and `custom`. Each edge must connect two imported node IDs. Limits are 50,000 nodes, 100,000 edges, 25,000 polygons, and 3–64 vertices per polygon. The importer expects an already-converted JSON interchange graph; it does not decode REDengine `.navmesh`/`.navdata` files. A converter must retain coordinates, surface polygons, and link semantics and record its source.

## MCP examples

- `navigation_graph_list()` — graph metadata and imported data.
- `navigation_graph_check(start_x, start_y, start_z, goal_x, goal_y, goal_z, graph_id="", snap_distance=3)` — nearest-node snap and graph path.
- `navigation_workspot_report(start_x, start_y, start_z, graph_id="", snap_distance=3)` — per-workspot imported-graph status.

Start/goal points farther than `snap_distance` from a graph node are returned as `unmapped`, not unreachable. A route result lists graph node IDs and non-walk transitions used.

## Native REDengine integration status

There is no live navmesh read, native path query, automatic game-navdata extractor, or native navigation overlay in this release. Raw REDengine navdata parsing is not implemented. The imported graph is an inspectable authoring/interchange layer that can be supplied by an offline extractor when one is available. Native integration remains a separate future task requiring a verified runtime/API or tested data extractor and in-game validation.
