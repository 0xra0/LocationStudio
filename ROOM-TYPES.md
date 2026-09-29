# Semantic room types

A room can carry a **type**, such as `clinic`, `office`, `storage`, `security`, `maintenance`, `corridor`, `server_room`, or one of your own. The room then inherits the generation rules for that environment:

- **Shell defaults:** floor, ceiling, trim, lighting anchors and so on. A server room gets a raised floor; a maintenance room gets exposed beams.
- **Surface traits:** every semantic surface of the room carries them (`medical`, `office`, `tech`...), so [placement queries](SEMANTIC-SURFACES.md) can ask for them.
- **Grammar variables:** for example, counters in a clinic become `medical_surface` and workbenches in a maintenance room become `industrial_surface`.
- **Interior rules:** these furnish the room once its doors are known. Furniture that would block a doorway is left out.
- **Placements:** markers and props on the room's own surfaces, such as a supply spot on every medical counter or a workstation on every desk.

Open it at **Spatial → Room types**. It is also available through the MCP tools:

| Tool | What it does |
| --- | --- |
| `room_type_catalog` | Built-in types and what each inherits (works offline) |
| `room_type_list`, `room_type_get` | Project and built-in types, and the rooms using them |
| `room_type_save`, `room_type_delete` | Project types |
| `room_type_rooms` | Rooms that carry a type |
| `room_type_assign` | Set or clear a room's type |
| `room_type_preview`, `room_type_furnish`, `room_type_unfurnish` | Furnish a room from its type |
| `room_type_create_room` | A new typed room with its interior |
| `room_type_reapply` | Update every room of a type after the type changes |

## Built-in types

Every built-in type extends `room`. Run `room_type_catalog` for the full rules. Most types also have an advisory minimum size; a room smaller than that gets a warning.

| Type | Traits | Shell | Interior | Placements |
| --- | --- | --- | --- | --- |
| `corridor` | circulation | flat ceiling, light anchors every 4 m | a cable tray along the long axis (grammar variable `tray`) | patrol points every 6 m |
| `office` | office | crown moulding, lights every 3 m | rows of desks (rooms from 3 x 3 m), up to 3 cabinets on a free wall | a workstation on every desk |
| `reception` (office) | office | as office | a counter in front of the far wall | a receptionist spot on the counter |
| `clinic` | medical | crown moulding, lights every 2.5 m | an exam bed on the first wall without a door, a `medical_surface` counter on the next (rooms from 3.4 m) | a supply spot on every medical surface |
| `storage` | storage | beams, lights every 4.5 m | shelf rows on free walls, crates in the middle (rooms from 3.5 m; `crates`) | 3 loot spots on the shelves |
| `security` | security | no skirting | a monitoring desk at the far wall, up to 4 lockers, a security zone trigger volume | a guard post in the middle of the floor |
| `armory` (security) | security, military | as security | cabinets along the free walls | none |
| `maintenance` | industrial, maintenance | beams, no skirting | an `industrial_surface` workbench, a tool cabinet, a pipe under the ceiling | a repair spot on the bench |
| `workshop` (maintenance) | industrial, maintenance | as maintenance | workbenches along the walls without doors, crates in the middle | a repair spot on each bench |
| `server_room` | tech | raised floor (0.3 m), flat ceiling, lights every 2.5 m | rows of racks along the long axis with 1.2 m aisles (`rack_aisle`), a cable tray | none |
| `lab` | lab | lights every 3 m | `lab_surface` benches along the walls without doors | sample spots, 0.5 per m² |
| `bedroom` | residential | one central light | a bed on the first wall without a door, a wardrobe (rooms from 4.2 m) | a sleep spot on the bed |
| `bunk_room` (bedroom) | residential, military | as bedroom | bunks along the free walls | a sleep spot on each bunk level |
| `bathroom` | residential | one central light | a counter on the first wall without a door | none |
| `kitchen` | residential | as room | `kitchen_surface` counters along the walls without doors | none |

## Where rooms get a type

### Parametric rooms

Add `type` to the spec (`room_generator_create`, plan op `create_parametric_room`):

```json
{"name": "Servers", "type": "server_room", "width": 6, "length": 5, "doors": [{"wall": "south"}]}
```

- The type's `spec` goes under the room's spec. Keys the room sets itself win. Objects merge key by key, so `"lighting": {"spacing": 5}` keeps the type's `anchors`. Lists replace.
- The room's traits are added to the type's traits.
- The room remembers its own spec apart from the type. `room_generator_update` with `{"type": "clinic"}` regenerates the shell: the server room's raised floor goes and the clinic's crown moulding comes. `{"type": false}` clears the type.
- The room record keeps the type as `room_type`, and the type's tags are added to its tags.

### Grammars

A grammar room takes `type`, and optionally `furnish`:

```json
{"room": {"type": "clinic", "wall_thickness": "$wall"}}
```

- **Shell and traits:** the type's spec and traits apply as above.
- **Variables:** the type's `params` override the grammar's defaults for the rest of the rule and its children. They do not override variables that a rule sets (`set`, rule or child params) or that the generation passes in. `room_type` holds the type id.
- **Interior:** after the whole layout has expanded, and doors have been cut through shared walls, each typed room runs its interior rules in its interior box.
- **Placements:** its `populate` entries only use that room's surfaces.
- **`furnish: false`** keeps the defaults, traits and variables, but skips the interior and the placements.

The built-in grammars label every room with a type (a clinic's exam rooms are `clinic`, the bunker's cells are `bunk_room`, `armory` or `maintenance`, and so on) with `furnish: false`, because they furnish their rooms themselves. The **`facility`** grammar only builds shells and doors. Its offices, storage rooms, security rooms, maintenance rooms, clinics and server room are all furnished by their types; `"furnish": false` turns that off.

### Any room, with `room_type_assign`

- **Room-kit and hand-made rooms** just record the type and its tags.
- **Parametric rooms** regenerate their shell with the type's defaults, as one undo step.
- **`furnish: true`** furnishes the room afterwards.
- **Clearing the type** also removes the furnishing that came from it.

## Furnishing a room

`room_type_furnish` runs the type's interior rules and placements in an existing room. This works for parametric rooms and room-kit rooms: the room's size, wall thickness, raised floor and doors come from the room.

- It is one authoring plan: validated, one undo step, rolled back completely on failure.
- Furnishing again replaces the previous furnishing. Objects you placed by hand stay, and placements avoid them.
- `room_type_preview` is a dry run. It shows the items by kind, placement estimates, warnings and whether the plan validates.
- `seed` changes the random choices, and `params` override variables.
- `room_type_unfurnish` removes the furnishing.

Rooms made by a grammar are furnished by their grammar build. Regenerate the build (with a new seed) rather than furnishing them again.

`room_type_create_room` makes a new parametric room of a type, with its interior, in one step. It takes an interior `width` and `length`, an optional `height` and `spec` (doors, windows, materials...), and a position and yaw (or player/camera). It is a small grammar build, so `grammar_regenerate` and `grammar_remove` work on it.

## Keeping doorways clear

Interior rules run once every door of the room is known. Any furnishing item that overlaps a door's clearance zone is left out, and the preview warns about it. The zone is the door width plus 0.15 m on each side, 1 m deep into the room, up to the door height. Lights and volumes are never left out, and neither are items higher than the door, such as ceiling pipes.

The built-in interiors avoid doors by using the side variables below.

## Custom types

Save a type to the project with `room_type_save` or plan it offline from `room_type_catalog`:

```json
{
  "id": "ripperdoc",
  "name": "Ripperdoc",
  "extends": "clinic",
  "traits": ["cyberware"],
  "params": {"light_intensity": 30},
  "populate": [{"kind": "marker", "tags": "bed", "pattern": "center", "per_surface": 1, "height": 0, "type": "patient_spot"}]
}
```

| Field | Meaning |
| --- | --- |
| `id` | Lowercase letters, digits and `_`. A project type with a built-in id overrides the built-in; deleting it brings the built-in back. |
| `extends` | The parent type. Its rules are inherited, and this type overrides them (up to 8 levels; cycles are refused). |
| `traits`, `tags` | Added to the parent's. |
| `spec` | Parametric room defaults: `height`, `wall_thickness`, `floor`, `ceiling`, `trim`, `materials`, `lighting`, `collision`, `collision_rules`, `surfaces`. Not `width`, `length`, `doors`, `windows` or `name`, which belong to each room. Validated like a room spec. |
| `params` | Variables the room's rules see. |
| `interior` | A rule name or list of rule names, or `false` for none. Replaces the parent's. |
| `populate` | [Surface placements](SEMANTIC-SURFACES.md#placing-things-on-surfaces). Added after the parent's unless `inherit_populate` is `false`. |
| `size` | `{min_width, min_length, min_height, max_width, max_length, max_height}`. Advisory: rooms outside it get a warning. |

Take material paths and resources from the catalog and search tools; never invent them.

A saved type is checked with its whole chain, along with every project type that extends it. After changing a type, `room_type_reapply` brings its rooms up to date, including rooms of types that extend it. Each update is its own undo step:

- grammar builds containing those rooms regenerate;
- other parametric rooms regenerate their shell;
- furnished rooms are furnished again with the same seed.

### Interior rules

Interior rules are [grammar rules](ENVIRONMENT-GRAMMAR.md). The built-in ones are in the `room_interiors` grammar (`OfficeInterior`, `ClinicInterior`, `StorageInterior`, `SecurityInterior`, `MaintenanceInterior`, `ServerInterior`, `RackRows`, ...). It includes `common`, so its Desk, Shelf, Counter, Workbench, Cabinet, Bed, Bunk, Crate, CableTray and PipeRun rules are available.

Every grammar can use these rules. A grammar that defines a rule of the same name overrides it, and room furnishing uses the override too. Custom types can name rules from your own grammar when rooms are made by that grammar.

Interior rules run in the room's interior box: x across the width, y along the length, from the floor top up to the ceiling. `walls` sides match the room's walls. They cannot make rooms, doors or windows. They also see:

| Variable | Value |
| --- | --- |
| `room_type`, `room_width`, `room_length`, `room_height` | The room |
| `doors_on`, `windows_on` | Sides with doors or windows |
| `wall_sides` | Sides without doors, far side first |
| `free_sides` | Sides without doors or windows, far side first |
| `wall_side`, `free_side` | Their first entry, or `''` |
| `entry_side` | The first door's side (`south` without doors) |
| `back_side` | The side opposite the entry, or `''` if it has a door |
| `long_axis` | `x` or `y` |

The expression functions `has(list, value)`, `count(list)` and `pick(list, index)` (index from 0; `''` past the end) work with these lists:

```json
{"if": "count(free_sides) > 1", "walls": {"sides": ["=pick(free_sides, 1)"], "depth": 0.5, "symbol": "Cabinet"}}
```

## Limits

- Room types furnish rectangular rooms. Clearance checks use bounding boxes.
- The doorway rule only knows the room's own doors. Openings to rooms made later, or doors placed as separate objects, are not known.
- Built-in interiors are simple procedural blocks (desks, shelves, racks, benches). Swap them for game assets by overriding the rule in your grammar (`Desk` → `asset`), or add props with `populate`.
- Furnishing is authoring data. Check in game that furniture stands clear of doors and that nothing clips (see [IN-GAME-CHECK.md](IN-GAME-CHECK.md)).
