# Reference areas

LocationStudio 0.68 can capture a box of the vanilla world into a **read-only reference layer** (project schema 20, `reference_areas`). Use it while you rebuild or modify a location, such as a clinic: you can always see exactly what originally occupied that space, compare your build against it, and copy or snap to the original pieces.

It is available in **Spatial → Reference** and through the `reference_area_*` MCP tools.

## Selecting the box

- **CORNER A / B AT V** or **AT AIM** (`reference_area_box(corner, source)`) sets the two corners of an axis-aligned box. You can also pass explicit positions.
- **BOX = SELECTED ROOM** (`reference_area_box(room_id, margin)`) fits the box around a room, including rotated rooms.
- **Padding** grows the box on every side.
- Each side can be up to 250 m; split larger areas.

## Capturing

**CAPTURE REFERENCE** (`reference_area_capture`) scans the box with RedHotTools and keeps the nodes inside it. Capture works like the [vanilla clone importer](VANILLA-CLONE.md), with the same node types, resource/appearance preservation and warnings:

- Cloneable nodes become reference items on their own layer, `reference_<name>`.
- Nodes that cannot be cloned (lights, collision, occluders, foliage...) are recorded on the area as **markers** with their type and position, so you still know a light was there. They are shown as "not captured".
- Live picks of streamed nodes know their **position only**. They are skipped (listed with the reason) unless you enable **Include position-only nodes**, which gives them rotation 0 and scale 1. Entities use their real orientation.
- For an exact reference, export the sector(s) with WolvenKit (*Convert to JSON*) and use `reference_capture_from_sector(name, sector_jsons, min, max)`. Every node instance inside the box is captured with its exact nodeData position, rotation and scale. It works without the game running; the capture happens once the game is live.
- Only streamed nodes in the camera frustum are scanned, so face the area and walk through large spaces before a live capture.

Capture is one undo step.

## Read-only guarantees

A reference layer is always **locked** and **export-disabled**, and its items are locked.

- The layer manager refuses to unlock the layer, enable its export, delete it, or move objects onto it.
- Its items cannot be moved or edited, and cannot be the target of **align**.
- Reference items are not counted as vanilla clones.
- They are left out of Build Mod exports (`excluded_by_layer`), performance estimates and hidden-mesh checks.

The only way to remove a reference is **DELETE** (`reference_area_delete`), which despawns and removes its items and layer. Delete is undoable, and the vanilla world itself is untouched.

## Seeing the reference

**SHOW / HIDE REFERENCE** (`reference_area_show`) spawns or despawns the reference items.

Show the reference once you have hidden or removed the vanilla originals, for example with [vanilla removal](README.md) or the clone importer's *hide originals*. You can also show it when building the location somewhere else. Showing it over untouched originals overlaps identical geometry.

## Rebuilding against it

- **COPY ALL TO EDITABLE** (`reference_area_copy`, optionally with specific `object_ids`) makes ordinary editable copies on the matching layer (Props, Lighting, ...) in one undo step. The copies keep `vanilla_source`, so a compare can match them.
- **ALIGN** (`reference_area_align`) snaps an editable object onto a reference item's position, and optionally its rotation and scale. It is undoable. In the tab, select one object and one reference item.
- **COMPARE** (`reference_area_compare`) classifies the current location against the reference:

  | Status | Meaning |
  | --- | --- |
  | `unchanged` | same resource and appearance, within 5 cm / 1° |
  | `moved` | matched, but moved or rotated (distance and angle reported) |
  | `changed` | matched, but the resource or appearance differs |
  | `missing` | an original with no counterpart within `move_radius` (5 m) |
  | `added` | a new object inside the box |
  | `not_captured` | uncloneable originals recorded as markers |

  Matches use the clone's `vanilla_source` first, then the nearest object with the same resource.
