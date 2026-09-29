# Streaming-sector partitioner

LocationStudio v0.83 divides a generated environment into streaming sectors automatically. A grammar build, a premise or a set of rooms can hold thousands of generated nodes: room shells, procedural geometry, colliders, lights, props. Assigning each one to a sector by hand does not scale. The partitioner decides from the layout:

- **spatial bounds:** rooms and cells have world boxes, and a sector stays within a size and node budget;
- **room connectivity:** doors between parametric rooms, and the room links of the scope's generated [navigation graph](NAVIGATION-GENERATOR.md) (open floor, stairs, ramps, off-mesh links);
- **visibility:** rooms and cells that see each other through doors, windows and open space;
- **expected player traversal:** the path from the entry, through doors and links, room by room.

Open it at **Spatial → Sectors → Automatic sector partition**, or use the MCP tools:

| Tool | What it does |
| --- | --- |
| `sector_partition_parameters` | Parameters, defaults and ranges (works offline) |
| `sector_partition_preview` | Dry run: the sectors, their members, transitions and warnings |
| `sector_partition_generate` | Partition and save the result (one undo step) |
| `sector_partition_regenerate` | Partition again from the saved scope, after the layout changed |
| `sector_partition_list` | Partitions in the project |
| `sector_partition_report` | A partition's full report, whether it is stale, and objects no sector holds |
| `sector_partition_sector_of` | The sector an object is in |
| `sector_partition_delete` | Delete a partition (objects are not changed) |
| `sector_partition_export` | Export through World Builder, one group per sector |

`grammar_generate` takes `sectors=True` (or a parameter object). The build's partition joins the build's undo step, is regenerated with the build (after its navigation graph, which it reads) and is removed with it.

## How it works

1. **Atoms.** Each room in scope is one atom, with the objects it owns and loose objects standing inside it. Rooms are never split. Objects outside rooms go into spatial cells of `loose_cell` m; a cell with more than `max_nodes` objects is quartered until it fits (four times at most). Members of one persistent object group stay in one atom, and so do the area and outline markers of an ambient reverb zone, which only export together.
2. **Links.** Pairs of atoms get weighted links:
   - *connectivity* (`w_connectivity`): each shared door of two parametric rooms counts once; navigation-graph links count 1.2 × for open floor, 0.8 × for stairs and ramps and 0.5 × for off-mesh links;
   - *visibility* (`w_visibility`): a line of sight at eye height between the two atoms, directly or through one of their openings, that no room wall or authored [occluder](OCCLUSION-VISIBILITY.md) blocks. Pairs further apart than `view_distance` are not tested, nor are pairs beyond the 3000 nearest;
   - *traversal* (`w_traversal`): added to every link on the breadth-first path from the entry, first over connectivity, then over sight and proximity. The entry is `entry=[x,y,z]`, else the navigation graph's entry, else a room with an exit door or link;
   - *proximity* (`w_proximity`): atoms closer than `proximity_gap`.
3. **Clustering.** Atoms merge greedily, strongest link per node first, while a sector keeps to `max_nodes` and to `max_extent` across (horizontally and vertically). Only a door, a walkable link or proximity can merge two atoms. A line of sight adds weight but never merges on its own, so a sector does not jump over rooms along a straight corridor. Ties are broken along the traversal. Sectors below `min_nodes` then join their best-linked neighbour, or the nearest sector that fits within `preload + proximity_gap`.
4. **Sectors.** Sectors are numbered `<base>_01`, `_02`... in traversal order. Each records:
   - its rooms and objects, node count, bounds and size;
   - its category: `interior` when it holds only rooms, otherwise `exterior`;
   - streaming extents: how far beyond its bounds it must stream in. That is at least `preload`, and far enough to cover every atom it can be seen from (capped at `view_distance + preload`);
   - its neighbours, with link weights and reasons, and the sectors it is visible from.

   The partition also lists **transitions**: the doors and links that a sector border cuts, and whether they lie on the expected path.

The same layout always partitions the same way, whatever its ids. Atoms are ordered by position.

## Pins

`pins = {room_or_object_id: label}` forces those rooms (or the atoms holding those objects) into one sector named by the label. Pinned atoms stay together even over budget. Atoms with different labels are never merged. `sector_partition_regenerate` merges new pins into the saved ones; a pin set to `""` or `false` is removed.

## Parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `max_nodes` | 600 | Most nodes (objects) in one sector |
| `min_nodes` | 40 | Sectors with fewer nodes join a neighbour |
| `max_extent` | 128 | Largest side of a sector (m); a single larger room stays whole and is reported |
| `loose_cell` | 32 | Cell size for objects outside rooms (m) |
| `view_distance` | 60 | Farthest pair distance tested for line of sight (m) |
| `preload` | 20 | How far ahead of the player a sector streams in (m) |
| `proximity_gap` | 4 | Atoms closer than this are linked by proximity (m) |
| `w_connectivity`, `w_traversal`, `w_visibility`, `w_proximity` | 10, 6, 3, 1 | Link weights |

Objects that are disabled, or on a layer that does not export, are left out and counted.

## Keeping it current

A partition records a digest of the rooms and objects it covers. `sector_partition_report` says `stale` when they changed, and lists `unassigned` objects added to the scope since then. `sector_partition_export` refuses a stale partition unless `allow_stale=True`. Run `sector_partition_regenerate` instead. Grammar builds do this themselves.

## Export

`sector_partition_export` exports through World Builder's own exporter, like `build_export`, but writes one WB group (`ls_<sector name>`) per sector and exports them together as one project. Each group gets:

- its sector's category, mapped by name to WB's `Interior`/`Exterior` category (left at WB's default when WB's category list cannot be read);
- its sector's streaming extents, as the group's `streamingX/Y/Z`;
- `level`, when given.

The objects must have live World Builder handles, as for `build_export`. Procedural geometry is added by Build Mod and is listed as `procedural`. Sectors without exportable objects are listed in `empty_groups`. Build the result with the `build_*` tools, and check it with [`sector_inspect`](SECTOR-INSPECTOR.md).

## Limits

- **Exporter behaviour is unverified in game.** The partition is LocationStudio data. Two assumptions are not yet checked in game: that WB writes one streaming sector per export group, and that it applies each group's streaming extents to that sector's streaming box. Check the export with `sector_inspect` (the sector count and bounds) and in game.
- **The weights are heuristics.** Visibility uses room boxes, their openings and authored occluders, not meshes. Traversal is breadth-first over links, not a player simulation. Node counts are object counts, not measured streaming cost; use the [performance analyzer](PERFORMANCE-ANALYZER.md) for relative cost.
