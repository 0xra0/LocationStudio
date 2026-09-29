# Semantic surfaces

Generated geometry knows what its surfaces are: a floor, a wall, a ceiling, a desk top, a shelf board, a road, a medical or industrial work surface, and so on. Code generators use this to put things in sensible places:

- props go on desks, counters and shelves, not inside them or under them;
- decals go on floors and walls, lying flat against them;
- lights hang from ceilings or sit on walls;
- effects and NPC markers go where there is room for them.

Open it at **Spatial → Surfaces**. It is also available through the MCP tools `surface_vocabulary`, `surface_query`, `surface_object`, `surface_tag`, `surface_untag`, `surface_sample`, `surface_populate` and `surface_refresh`.

## What a surface is

A surface is a flat rectangle (or outline) on an object, stored in the object's own frame and returned in world space. It has:

- a **tag**, such as `desk`;
- optional **traits**, such as `medical` or `office`;
- a centre, a normal and a size;
- an **orientation**: `up` (floors, desk tops), `side` (walls) or `down` (ceilings).

On a vertical surface, the `v` axis points up.

### Tags

Run `surface_vocabulary` for the full list. Each tag belongs to groups, and a query can ask for a tag, a group or a trait.

| Tags | Orientation | Groups |
| --- | --- | --- |
| `floor`, `ground`, `sidewalk`, `platform`, `roof` | up | walkable, support |
| `road` | up | walkable, traffic (not support: props stay off it) |
| `stairs`, `ramp` | up | walkable |
| `desk`, `table`, `counter`, `workbench`, `kitchen_surface` | up | work_surface, support |
| `medical_surface`, `industrial_surface`, `lab_surface` | up | work_surface, support, plus medical / industrial / lab |
| `shelf`, `cabinet`, `crate` | up | storage, support |
| `bed`, `seat` | up | furniture |
| `machine` | up | support, industrial |
| `wall`, `partition`, `glass` | side | vertical (interior) |
| `exterior_wall` | side | vertical, exterior |
| `ceiling`, `underside` | down | overhead |

Any other lowercase name (`conveyor_belt`) also works as a custom tag.

## Where surfaces come from

### Procedural generators

Generators tag their own faces:

| Generator | Surfaces |
| --- | --- |
| `floor` | top as `floor` (polygon floors keep their outline) |
| `ceiling` | underside as `ceiling` |
| `wall` | both faces of every solid segment as `wall` (openings are left out) |
| `stairs` | each tread as `stairs`, the landing as `platform` |
| `ramp` | the slope as `ramp` |
| `window` | the glass as `glass` |

### Procedural objects

Any procedural object takes a `surface` option (`procedural_create`, plan op `create_procedural`, grammar `geometry`):

- `"surface": "desk"` tags every **visible** top face that the generator did not tag. Faces hidden under another part, such as desk legs under the top, are skipped.
- `"surface": {"tag": "counter", "traits": ["kitchen"], "retag": {"floor": "road"}, "surfaces": [...]}` adds traits, renames or drops (`false`) tags, and adds explicit rectangles.
- A `compound` part can carry its own `surface`, either a tag for its top or `{top, bottom, sides, px, nx, py, ny, traits}`. Upright cylinders get round caps.

The surfaces are saved with the object and recomputed whenever its geometry changes.

### Parametric rooms

Parametric rooms add these surfaces:

- the interior floor (above a raised floor);
- the interior walls, from the floor to the ceiling, without their doors and windows;
- the ceiling;
- the exterior walls.

The room spec's `surfaces` key changes them: `{"floor": "road", "walls": "wall", "exterior": false, "ceiling": "ceiling", "traits": ["medical"]}`. A [room type](ROOM-TYPES.md) adds its traits (`medical`, `office`, `tech`...) to every surface of the room.

### Hand tags

Hand tags work on any object, for example a game-asset desk (`surface_tag`, or **TAG FROM BOUNDS** in the panel):

- `face` picks the side of the object's bounds to tag: `top`, `bottom`, `front`, `back`, `left` or `right`;
- `inset` shrinks the surface;
- `height` puts a top surface at a given height, such as a seat or a shelf board inside the bounds;
- explicit `surfaces` in the object's frame need no bounds.

Hand tags are kept on the object (`metadata.surfaces`), apart from the generated ones.

For projects made before surfaces existed, run `surface_refresh`. It recomputes the surfaces of procedural objects and parametric rooms without rebuilding them.

## Placing things on surfaces

`surface_sample` is a dry run. It returns world positions and rotations for items of a **kind**:

| Kind | Default tags | Default placement |
| --- | --- | --- |
| `asset` | support | upright, aligned with the surface, 0.4 x 0.4 x 0.4 m |
| `procedural` | support | as `asset`; no collision by default |
| `effect` | support | as `asset`, 2 cm above the surface |
| `decal` | floor, wall | 5 mm off the surface. The size is the footprint, or `decal_width`/`decal_height`. |
| `light` | ceiling | on a 3 m grid, 15 cm under the ceiling. On walls, 2.2 m up. |
| `marker` | walkable | needs 1.9 m of headroom |

### Filters

- `tags`: a tag, group or trait; any of them may match.
- `traits`: all must match.
- `exclude_tags`, `orientation`, `min_area`.
- Scope: `premise_id`, `room_id` or `object_ids`.

### Patterns

- `random`: `count` in total, spread by usable area; or `per_surface`; or `density` per m².
- `grid` and `line`: `spacing`.
- `center`.
- The same `seed` gives the same points.

### Fit

An item has a `footprint` [x, y] and a `height`. A placement is kept only if:

- the footprint fits inside the surface (minus `margin`);
- there is at least `height` of clearance under anything above, such as a desk top over the floor or the next shelf board up;
- it does not overlap an object already there (`avoid_objects`, default on for props). Objects without bounds count as a 0.4 m box. Room shells, colliders and decals are ignored.
- it keeps `min_distance` from the other new placements.

`rejected` counts why candidates were dropped: `spacing`, `clearance`, `occupied` or `outline`.

### Facing

- Items on `up` surfaces are aligned with the surface's u axis (`yaw: align`), or turned with `yaw: random`, a number, or `yaw_step` (random multiples, such as 90).
- Items on walls face out of the wall into the room. `elevation` sets their height above the wall's bottom edge.
- Items on ceilings hang `offset` below them.

### Populating

`surface_populate` creates the items as **one authoring plan**: validated, one undo step, fully rolled back on failure. The kind's fields go in `item`:

- `asset`: `asset_id` or `asset_query` for a Project Asset;
- `procedural`: `generator`, `params`, `material`, `surface`;
- `decal`: `resource_name` or `resource_path` from the decal catalog, `alpha`;
- `light`: `config` or `preset_id`;
- `effect`: `resource_path` or `resource_name`;
- `marker`: `type`, `category`.

`name` can contain `{i}`. `dry_run` only lists the placements.

### Authoring plans

Authoring plans (version 2) have the op `populate_surfaces`, which takes the same keys. With `from_plan: true` it only uses surfaces of objects and rooms made earlier in the same plan.

## Grammars

A grammar's `populate` list runs after the layout is built, on the surfaces of that generation only ([ENVIRONMENT-GRAMMAR.md](ENVIRONMENT-GRAMMAR.md)):

```json
"populate": [
  {"if": "supply_spots", "kind": "marker", "tags": "medical_surface", "per_surface": 1, "pattern": "center", "type": "supply_spot"},
  {"kind": "asset", "asset_query": "coffee mug", "tags": "desk", "count": 6, "footprint": 0.15, "height": 0.15},
  {"kind": "decal", "resource_name": "graffiti", "tags": "exterior_wall", "count": 4, "elevation": 1.5, "footprint": [1.5, 1]}
]
```

Values can use the grammar's params (`"$param"`, `"=expression"`). `grammar_preview` lists each entry with an **estimate** of how many placements it makes, and counts the layout's surfaces by tag. The estimate uses the layout's own geometry and not objects already in the premise, so the real count can be lower. Regenerating or removing the build removes the placements too.

The built-in grammars tag their furniture:

- **Common rules:** desks, counters, workbenches, shelves, cabinets, beds, bunks, crates and machines.
- **Room traits:**
  - clinic rooms are `medical`, and exam-room counters are `medical_surface`;
  - labs are `lab`, and their benches are `lab_surface`;
  - the industrial block is `industrial`, and its workbenches are `industrial_surface`;
  - apartments are `residential`, and kitchen counters are `kitchen_surface`;
  - the bunker is `military`.
- **Populate examples:** the clinic marks a supply spot on every medical surface, and the laboratory scatters sample spots on its lab benches. Turn them off with `supply_spots: false` or `sample_spots: false`.

## Limits

- Surfaces are planes, so curved parts are left out except for upright cylinder caps. CSG results only get the object-level top tag, on their preview boxes.
- An object keeps at most 400 surfaces (the largest), and one sampling call makes at most 500 placements and 20000 attempts.
- Clearance and overlap checks use surfaces and bounding boxes, not exact meshes.
- Rotation conventions for decals are an assumption: decals are pitched −90° on walls and rolled 180° on ceilings, so that they project into the surface. Check wall and ceiling decals in game.
- Placements are authoring data. As with any generated layout, check in game that props sit on the surface and nothing clips.
