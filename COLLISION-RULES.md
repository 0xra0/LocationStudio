# Collision rules

LocationStudio generates collision automatically for procedural geometry. This covers generated walls, floors, stairs, railings, parametric rooms and CSG objects. The colliders are real World Builder collision primitives, and they are rebuilt whenever the geometry changes. Rules decide how they are generated:

- simplified or convex collision;
- per-room collision;
- doorway exclusions;
- rail barriers;
- player- or NPC-specific blocking.

Open it at **Spatial → Collision rules**. It is also available through the MCP tools `collision_rules_*`, `collision_rules` on procedural objects, parametric-room specs and EDL, and the plan op `set_collision_rules`.

## Scopes

Rules can be set at three levels. A more specific level overrides the one before it, key by key:

| Scope | Where it is stored | Applies to |
| --- | --- | --- |
| `default` | `collision_rules.default` | Every procedural object in the project. |
| `room:<id>` | `collision_rules.rooms[id]` | Objects whose `room_id` is that room. |
| `object:<id>` | `metadata.procedural.collision_rules` | One object. |

Setting rules plans every affected object first, then saves the rules and regenerates the colliders as **one undo step**. If any object would fail, for example by exceeding the 200-collider limit, nothing changes. `collision_rules_preview` shows the result without applying it.

## Rules

| Key | Values | Meaning |
| --- | --- | --- |
| `mode` | `exact` (default) | One collider per part: boxes, fitted boxes for cylinders and prisms, spheres, and slabs for sloped wedges. |
| | `simplified` | Boxes that share a face are merged losslessly. After that, the cheapest pairs are merged while the added volume stays under `tolerance` of the merged box (default 0.1), and merging continues until at most `max_boxes` remain (default 64). |
| | `convex` | One box per connected piece. |
| | `bounds` | One box for the whole object. |
| | `none` | No colliders. |
| `actors` | `all` (World Static), `player` (Player Blocker), `npc` (NPC Trace Obstacle), `player_vehicles`, `vehicles`, `camera`, `sight` | Who the colliders block, as a collision preset. `preset` names any preset directly. |
| `material` | a physics material (`concrete`, `metal`, `glass`, ...) | Physics material of the colliders. |
| `doorways` | `auto` (default) / `keep` | `auto` cuts every door opening of the premise's rooms out of the colliders. The cut runs from the room floor to the door head, and `door_clearance` (default 0.3 m) either side of the wall. |
| `exclude` | `[{center, size, yaw}]` | Extra boxes cut out, in the frame of the scope that sets them: world for `default`, room for `room:`, object for `object:`. Use them for shafts, vents or a passage through solid geometry. |
| `rails` | `solid` (default) / `parts` / `none` | For railings: `solid` gives one barrier per segment, `rail_height` high (default the railing's height) and `rail_thickness` thick (default 0.1 m). `parts` gives one collider per post and rail. |
| `glass` | `pass` (default) / `block` | Whether glass parts get colliders. |
| `min_thickness` | metres (default 0.05, minimum 0.02) | Thin colliders are thickened to this. |
| `per_room` | `true` / `false` | Colliders are split at the room volumes (the interior plus half a wall) and each piece is assigned to its room. |

Some notes on the rules:

- **Cutting and splitting:** these are exact when the boxes are aligned, meaning the same roll and pitch and a yaw difference that is a multiple of 90°. A cut that is not aligned leaves the collider whole and reports a warning. Pieces thinner than 2 cm are dropped.
- **"Convex":** World Builder colliders are primitives (box, capsule, sphere), so a piece's convex hull is represented by its fitted box.
- **Rooms:** pieces that fall outside every room stay with the object's room. `collision_rules_report` lists each room's colliders and how many block the player or NPCs (an estimate from the preset groups). `collision_rules_room_enabled` switches a room's generated collision off or on. Disabled colliders are despawned and left out of the export (reported as `disabled_collision`).

## Using rules

```json
{"op": "set_collision_rules", "room_id": "$lobby", "rules": {"actors": "player", "per_room": true}}
```

Rules can also be given in these places:

- `procedural_create(..., collision_rules={"mode": "simplified"})`;
- a parametric room spec `collision_rules` (stored as that room's rules);
- EDL `collision_rules` on rooms and geometry elements.

After room openings change, run `collision_rules_regenerate` (for the object, room or premise) so the doorway cuts follow.

## Limits

- Only procedural geometry is generated this way. Other collision is still authored with `collision_create_primitive`, `collision_fit_to_object` or imported collision meshes. The window blockers of parametric rooms are separate colliders and do not follow these rules.
- Actor presets are estimates from the preset groups. Check blocking in game, and with `collision_passability` and the live walkability tools.
