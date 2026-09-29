# Parametric rooms

The parametric room generator builds a complete room from one specification: width, length, height, wall thickness, doorways, windows, floor type, ceiling type, trims, materials and lighting. From that single spec it creates:

- the geometry;
- collision;
- material slots;
- portals;
- lighting anchors;
- snapping sockets.

The result is one undo step. Regenerating or deleting the room is also one undo step each.

Open it at **Spatial → Room gen**. It is also available through the MCP tools `room_generator_*`, the authoring-plan v2 op `create_parametric_room`, and EDL rooms with `build: parametric`.

## Specification

```json
{
  "name": "Clinic",
  "width": 6, "length": 4, "height": 3, "wall_thickness": 0.2,
  "doors":   [{"wall": "south", "offset": -1, "width": 1, "height": 2.1, "frame": true}],
  "windows": [{"wall": "east", "offset": 0, "width": 1.5, "height": 1.2, "sill": 1,
               "frame": true, "glass": true, "mullions_x": 1, "mullions_y": 0}],
  "floor":   {"type": "slab", "thickness": 0.2},
  "ceiling": {"type": "beams", "thickness": 0.2, "beam_spacing": 1.5, "beam_width": 0.2, "beam_depth": 0.25},
  "trim":    {"skirting": true, "skirting_height": 0.1, "crown": false},
  "materials": {"floor": "base\\...\\floor.mi", "walls": "base\\...\\plaster.mi", "ceiling": "...",
                "trim": "...", "frame": "...", "glass": "base\\...\\glass.mi"},
  "lighting": {"anchors": "grid", "spacing": 3, "create_lights": false,
               "light": {"color": [1, 0.95, 0.85], "intensity": 60, "radius": 6}},
  "collision": true, "block_windows": true
}
```

### Room frame

- The origin is the centre of the floor. `width` runs along x and `length` along y. Both are the clear interior dimensions, and the walls stand outside them.
- The walls are named `north` (+y), `south` (−y), `east` (+x) and `west` (−x), as for kit rooms.
- An opening `offset` is measured from the middle of its wall: along x on north/south walls and along y on east/west walls.

### Validation

The whole spec is checked before anything is created:

- **Sizes:**
  - width and length: 1–100 m;
  - height: 2–30 m;
  - wall thickness: 0.05–2 m.
- **Openings:**
  - must fit on their wall, frame included;
  - must be lower than the room;
  - must not overlap.
- **Types:**
  - floor: `slab`, `raised` or `none`;
  - ceiling: `flat`, `beams`, `coffered` or `none`;
  - lighting anchors: `grid`, `center` or `none`.

### Materials

| Value | Effect |
| --- | --- |
| A `.mi`/`.mt` path | Becomes the piece's `main` material slot, which gives a native mesh at Build Mod. See [MESH-RESOURCES.md](MESH-RESOURCES.md). |
| A `.mesh` path | Is used as the template for the WolvenKit import backend. |

Material fallbacks:

- `trim` falls back to `walls`.
- Frames fall back to `trim`.
- `glass` becomes the windows' `glass` slot and needs a frame or trim `.mi`.

Always take paths from the asset catalog.

## What gets generated

| Part | How |
| --- | --- |
| Room record | A normal room with its size and openings, so visibility, reverb, room frames, EDL and performance see a real room. It has no kit shell: rebuilding a kit shell is refused for parametric rooms, and premise-wide rebuilds skip them. |
| Geometry | One procedural object per role: `floor`, `walls`, `ceiling`, `trim`, `door_frames`, `windows`. Each role has its own material set and becomes its own mesh at Build Mod. Walls are cut around every opening. Beams and coffers hang under the ceiling. Skirting is split at doors. |
| Collision | Floor, walls and ceiling get real collision boxes. Window openings get an invisible blocker (`block_windows`), so players cannot walk through the glass. Doors stay open. |
| Portals | One per door and window: `{id, kind, wall, center, width, height, sill, normal, connects}`. `connects` names the adjoining generated room when a door opens into one. Links refresh whenever a room in the premise changes. |
| Lighting anchors | A grid (spacing `lighting.spacing`) or a single centre anchor just under the ceiling. With `create_lights` each anchor gets a World Builder static light. |
| Sockets | See the socket table below. |
| Group | A persistent object group with every generated piece, pivoted on the room. |

Sockets:

| Socket | Position |
| --- | --- |
| `floor_center` | Centre of the floor |
| `ceiling_center` | Centre of the ceiling |
| `wall_north`, `wall_south`, `wall_east`, `wall_west` | Inner face of each wall, at floor level, facing into the room |
| `corner_ne`, `corner_nw`, `corner_se`, `corner_sw` | Interior corners, facing the centre |
| `door_N` | Door thresholds |
| `window_N` | Window sills |
| `light_N` | Lighting anchors |

## Editing

- **Regenerate** (`room_generator_update`, **REGENERATE FROM SPEC**):
  - Changed keys are merged over the saved spec; lists replace.
  - The room keeps its id and transform. Generated pieces are replaced, and objects you placed yourself stay.
  - A spec that fails validation changes nothing.
- **Delete** removes the pieces, colliders, lights, group and room.
- **Snap** (`room_generator_snap`, the **SNAP** buttons):
  - Moves an object onto a socket and turns it to face the socket's direction.
  - `offset` is in the socket frame: +y is the direction the socket faces.
  - Generated pieces themselves cannot be snapped.
- Everything is refused while a transform or stamp session, or an authoring-plan recovery, is active.
- If any step fails, the whole operation is rolled back, including the live preview.

## Authoring plans and EDL

```json
{"op": "create_parametric_room", "as": "clinic", "premise_id": "$premise",
 "offset": {"x": 4, "y": 0, "z": 0}, "yaw": 90, "spec": {"width": 6, "length": 4, "doors": [{"wall": "south"}]}}
```

In EDL, mark a room `build: parametric`:

- `size`, `walls.thickness`, `doors` and `windows` keep their usual meaning.
- Everything else goes in `parametric:`.
- Room elements such as objects, lights and geometry still use the room frame.

```yaml
rooms:
  - id: clinic
    build: parametric
    at: [4, 0]
    size: [6, 4]
    walls: {thickness: 0.25}
    doors: [{wall: south, offset: -1}]
    windows: [{wall: east, width: 1.5, mullions_x: 1}]
    parametric:
      ceiling: {type: coffered, beam_spacing: 2}
      materials: {walls: "base\\...\\plaster.mi", frame: "base\\...\\metal.mi", glass: "base\\...\\glass.mi"}
      lighting: {anchors: grid, spacing: 3, create_lights: true}
```

## Semantic surfaces

Each room records its interior floor, its walls without the doors and windows, its ceiling and its exterior walls as semantic surfaces. The spec's `surfaces` key (`{floor, walls, exterior, ceiling, traits}`) renames or drops them, or adds traits such as `medical`. See [SEMANTIC-SURFACES.md](SEMANTIC-SURFACES.md).

## Limits

- Rooms are rectangular. Use procedural `floor`/`wall` pieces for other shapes.
- The live preview is made of World Builder shapes. The real meshes exist only after a successful Build Mod; check them in game.
- Portals are authoring data for connectivity, visibility and quest tools. They are not engine portals.
