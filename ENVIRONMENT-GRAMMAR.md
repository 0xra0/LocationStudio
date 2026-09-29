# Environment grammar

An environment grammar is a set of reusable rules that turn a box of space into a layout, for example:

```
Corridor -> walls + door every N m + ceiling lights + cable tray
```

A whole industrial block, clinic, apartment floor, bunker or laboratory is generated from the rules. One rule set gives many layouts, depending on size, parameters and seed. A generation produces real project content:

- parametric rooms with doors and windows (see [PARAMETRIC-ROOMS.md](PARAMETRIC-ROOMS.md));
- procedural geometry;
- static lights;
- Project Assets;
- volumes and markers.

It all runs as **one authoring plan**. The plan is validated before anything changes, is one undo step, and is rolled back completely if a step fails.

Open it at **Spatial → Grammar**. It is also available through the MCP tools `grammar_schema`, `grammar_library`, `grammar_get`, `grammar_save`, `grammar_delete`, `grammar_preview`, `grammar_generate`, `grammar_regenerate`, `grammar_remove` and `grammar_builds`.

## Built-in grammars

The library is in `grammars/library.json`.

| Grammar | What it builds |
| --- | --- |
| `common` | Reusable rules the others include: `Corridor`, `Door`, `Window`, `CeilingLight`, `CableTray`, `PipeRun`, `Duct`, `Shelf`, `ShelfRow`, `Workbench`, `Counter`, `Cabinet`, `Desk`, `Bed`, `Bunk` and `Crate`. `CorridorExtras` is an empty hook that runs inside every corridor. |
| `corridor` | The corridor on its own: doors every `door_every` m on both walls, a ceiling light every `light_every` m, and a cable tray. |
| `industrial` | A service corridor with pipes and a cable tray, between rows of workshops and storage rooms. |
| `clinic` | A reception, then a corridor wing of exam rooms, offices and toilets with outside windows. |
| `apartment` | A hallway with apartments on both sides. Each has a living room with a kitchen counter, a bedroom with a window and a bathroom. |
| `bunker` | 40 cm walls, a corridor with ducts and pipes, bunk rooms, armouries, a generator room and a command room. |
| `laboratory` | Wet labs, clean rooms with observation windows onto the corridor, and a server room. |
| `facility` | A corridor spine with offices, storage rooms, security rooms, maintenance rooms, clinics and a server room. Only shells and doors: every room is furnished by its [room type](ROOM-TYPES.md). `furnish: false` leaves them empty. |
| `room_interiors` | The interior rules of the built-in room types (`OfficeInterior`, `ClinicInterior`, `ServerInterior`, ...). Every grammar can use them. |

The grammars only use generated geometry, so they work in any project. Material parameters (`wall_material`, `floor_material`, `ceiling_material`) are empty by default. Set them to `.mi` paths from the catalog or to `@library` keys.

## Writing a grammar

```json
{
  "id": "my_corridor",
  "include": "common",
  "start": "Hall",
  "size": [30, 3.4, 3.2],
  "params": {"door_every": 5, "light_every": 3},
  "rules": {
    "Hall": [
      "Corridor",
      {"walls": {"sides": ["south"], "depth": 0.6, "symbol": "ShelfRow"}}
    ],
    "CorridorExtras": [{"walls": {"sides": ["south"], "depth": 0.3, "symbol": "PipeRun"}}]
  }
}
```

A grammar document has these keys:

- **`include`:** inherits the params and rules of other grammars. Rules with the same name override the inherited ones, which is how `CorridorExtras` is filled in.
- **`start` and `size`:** the first rule and the box it runs in. The box is centred on the origin, with the floor at z = 0.
- **`params`:** defaults that each generation can override.
- **`populate`:** placements on the semantic surfaces of what the generation built, such as props on desks, markers on medical surfaces or decals on walls. See [Populate](#populate).

### Scopes

Every rule runs in a **scope**, an oriented box. Its local axes are:

- x along the box;
- y across it;
- z up.

The origin is the min corner, and `sx`, `sy`, `sz` are the size of the box. A rule is a list of operations, a `{params, if, do}` object, or `{params, variants: [{weight, if, do}]}`. Variants are picked by weight among those whose condition holds.

### Structural operations

| Operation | Effect |
| --- | --- |
| `split` | `{axis, parts: [{size, symbol \| do, params}]}` divides the box. A `size` is an expression in metres or `"~w"`, a share of what the absolute parts leave. |
| `repeat` | `{axis, every \| step \| count, size, offset, margin, symbol \| do}` tiles the box. The three spacing keys work differently:<br>- `every` means about every N m: the count is rounded and the tiles fill the run evenly.<br>- `step` is exactly N m, centred, or starting from `offset`.<br>- `count` is exactly n tiles.<br>`i` and `n` give the tile index and count. `axis: z` stacks floors. |
| `place` | `{at \| center, size, yaw, symbol \| do}` is a child box, turned by `yaw` about its centre. |
| `walls` | `{sides, depth, inset, symbol \| do}` makes a strip along the inside of each side. In a strip, x runs along the wall and y points inward, so items face into the room. The variable `side` names the side. |
| `call` | `"Rule"`, or `{symbol, params}`, runs a rule in the same scope. A bare string operation is a call. A room made by the called rule stays in effect for the caller, which is how shell rules like `ClinicShell` work. |
| `choose` | `[{weight, if, symbol \| do}]` runs one option. |
| `chance` | `{p, symbol \| do, else}` runs its content with probability `p`. |
| `set` | `{name: expression}` sets variables for the rest of the rule and its children. |

Any operation can have `if: "expression"`.

### Terminals

| Terminal | Result |
| --- | --- |
| `room` | A parametric room whose **outer** footprint is the scope. It takes the room spec: `wall_thickness`, `floor`, `ceiling`, `trim`, `materials`, `lighting`, `collision`, `collision_rules`, explicit `doors`/`windows`, `surfaces` (`{floor, walls, exterior, ceiling, traits}`), `height` and `name`. The operations after it run in the room's **interior**, and `t` is the wall thickness. Neighbouring rooms stand back to back, each with its own wall. |
| `door` / `window` | An opening in the enclosing room's wall nearest the scope centre, or in `wall`. Its settings are `width`, `height`, `sill` (windows), `frame`, `frame_width` and `shift`. With `connect` (the default), the same opening is cut into the room behind the wall, so a door placed from either side joins both rooms. A door can also stand a door-leaf asset in the opening (`asset_id`/`asset_query`). |
| `geometry` | A procedural generator with `params` and `material`. `collision` defaults to true and `layer` to `decoration`. The object stands at `at`, which defaults to the bottom centre of the scope, and turns with the scope. Compound parts can use `[x, y, z]` arrays. `surface` tags its visible top faces (`"desk"`, `"$counter_surface"`), and compound parts can carry their own `surface`. See [SEMANTIC-SURFACES.md](SEMANTIC-SURFACES.md). |
| `asset` | A Project Asset (`asset_id` or `asset_query`) placed at `at`. |
| `light` | A static light (`intensity`, `radius`, `color` or `config`, or `preset_id`). By default it hangs 0.15 m under the top centre of the scope. |
| `volume` | A volume filling the scope, for example a trigger per room. |
| `marker` | A location, such as an NPC spot. |

### Values and expressions

In numeric fields a string is an **expression**. These fields include sizes, `at`, `every`, `step`, `count`, `width`, `height` and `yaw`.

In every other field a string is **literal** unless:

- it starts with `=`, which makes it an expression (`"=sx - 0.2"`);
- it is `$name`, which makes it a variable of any type (`"$wall_material"`, `"$door_sides"`).

Names can contain `{expression}`, as in `"Cell {i+1}"`.

Expressions support:

- numbers, `'strings'` and variables (`$` is optional);
- the operators `+ - * / % ^`;
- comparisons, `and`/`or`/`not` and `c ? a : b`;
- the functions `min`, `max`, `floor`, `ceil`, `round`, `abs`, `sqrt`, `sin`, `cos`, `clamp`, `if`, `rand`, `randint` and `opposite('north')`;
- the list functions `has(list, value)`, `count(list)` and `pick(list, index)` (index from 0; `''` past the end).

The following variables are available:

- grammar params and `set` variables;
- `sx`, `sy`, `sz`;
- `i`, `n` and `side`;
- `t` inside a room, and `room_type` after a typed room;
- `depth` and `pi`.

Params given to a child are evaluated in the child's scope.

`rand` is seeded by the generation seed and the rule path. The same seed always gives the same layout, and changing one part of a grammar does not reshuffle the rest.

## Populate

A grammar's `populate` list runs after the layout is built. Each entry places items of a kind (`asset`, `procedural`, `decal`, `light`, `effect` or `marker`) on the semantic surfaces of this generation: tags, groups or traits such as `desk`, `work_surface`, `medical`, `ceiling` or `exterior_wall`. Entries take the options of `surface_populate` ([SEMANTIC-SURFACES.md](SEMANTIC-SURFACES.md)): `count`, `per_surface`, `density`, `pattern`, `spacing`, `footprint`, `height`, `elevation` and `seed`, plus the kind's fields and `if`. Values can use params.

```json
"populate": [
  {"kind": "asset", "asset_query": "coffee mug", "tags": "desk", "count": 6, "footprint": 0.15, "height": 0.15},
  {"if": "supply_spots", "kind": "marker", "tags": "medical_surface", "per_surface": 1, "pattern": "center", "type": "supply_spot"}
]
```

Placements avoid other geometry and need room above them. `grammar_preview` estimates how many each entry makes and counts the layout's surfaces by tag. Included grammars' populate lists run first.

The built-in rules tag their furniture through params such as `desk_surface`, `counter_surface` and `workbench_surface`, and their rooms through `room_traits`. For example, the clinic sets `counter_surface: medical_surface` and `room_traits: ["medical"]`.

## Room types

A `room` can take a `type` such as `clinic`, `office`, `storage`, `security`, `maintenance`, `corridor` or `server_room` (see [ROOM-TYPES.md](ROOM-TYPES.md)):

- **Defaults and traits:** the type's spec defaults go under the room's spec, and its surface traits are added.
- **Variables:** its params override the grammar's defaults for the rest of the rule. Variables a rule sets or the generation passes in still win.
- **Interior:** once the whole layout has expanded and every door is known, its interior rules furnish the room. Items in front of a door are left out, with a warning.
- **Placements:** its placements go on that room's surfaces.

`furnish: false` keeps the defaults, traits and variables but skips the interior and placements. The built-in grammars use it because they furnish their rooms themselves.

```json
{"room": {"type": "server_room", "wall_thickness": "$wall"}}
```

Interior rules come from the grammar itself or from the `room_interiors` grammar. A rule of the same name in your grammar overrides the built-in one (for example your own `Desk`). `grammar_preview` reports `stats.room_types`, `stats.interior_items` and `stats.doorway_cleared`, and marks furnishing items with `furnishing`.

## Generating

1. **Preview** (`grammar_preview`) expands the grammar without changing the project. It lists the rooms (size, doors, windows) and items with their positions. It also reports rule call counts, openings connected between rooms, overlap warnings, and whether the compiled authoring plan validates.
2. **Generate** (`grammar_generate`) places the layout centre at the player, the camera or `position` with `yaw`. It builds into a new premise, or into `premise_id`.
3. **Regenerate** (`grammar_regenerate`) rebuilds the layout in place with new params, seed, size or start rule. The previous generation is removed first, including hand edits to its items. Objects you placed yourself in the premise stay.
4. **Remove** (`grammar_remove`) deletes everything the build made.

Each of these is one undo step. A generation is also recorded as an EDL build (`grammar_<build id>`), so `edl_list` shows it.

`grammar_generate` with `navigation: true` (or a parameter object) also generates the build's [navigation graph](NAVIGATION-GENERATOR.md) in the same undo step. Once a build has a graph, regenerating the build regenerates it, and removing the build removes it.

Checks happen before anything is built:

- Rooms must fit in their scope, and every opening must fit its wall, including openings connected from a neighbour. The error names the rule path.
- Geometry parameters are run through their generator.
- Asset queries must resolve.
- Overlapping rooms are reported as warnings.

## Limits

- A grammar can nest 32 levels deep and make 5000 rule calls, 1900 items and 200 rooms. A plan has at most 2000 steps.
- Doors and windows only open into rooms of the same generation. Windows between two rooms need `connect` (the default) to cut both walls.
- Rooms are boxes. Use `geometry` with the `csg` generator for other shapes.
- The preview in game is the procedural preview. Describe meshes as real only after a successful Build Mod and an in-game check.
