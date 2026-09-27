# Spline editor

LocationStudio 0.65 adds persistent, editable splines (project schema 18, `splines`). A spline is saved with the project and is the single source of truth for everything built along it. When you edit the curve, **REGENERATE** rebuilds the cables, fences, roads, object rows, NPC routes, camera paths and native spline nodes made from it.

## Curve model

- **Control points** (up to 256), each with cubic Bezier **handles** stored as offsets from the point, and a **tangent mode**:

  | Mode | Handles |
  | --- | --- |
  | `auto` | smooth; derived from the neighbouring points (Catmull-Rom, scaled by the spline's **tension**, 0–1, default 0.5) |
  | `aligned` | editable; setting one handle mirrors the other's *direction* and keeps its length, so the curve stays smooth |
  | `free` | fully independent handles, for corners and kinks |
  | `linear` | zero handles: straight segments meeting at the point |

  Setting a handle on an `auto` or `linear` point switches it to `free`. Switching `auto` → `aligned`/`free` starts from the current automatic handles.
- **Open or closed.** A closed spline joins the last point back to the first and needs at least three points; deleting points below three reopens it.
- **Spacing.** Sampling is by arc length: a `spacing` in metres, or a fixed `count`, with optional start/end offsets. Each sample carries its position, the tangent's yaw and pitch, and its distance along the curve. A full closed loop never repeats its start point.

## Editing

In game, open **Spatial → Splines**:
- **NEW SPLINE AT AIM**, **ADD POINT AT AIM / AT PLAYER**, **MOVE POINT TO AIM** and **DELETE POINT** edit the points.
- The tangent-mode picker, **SET OUT HANDLE** (x/y/z) and the auto-tangent tension slider shape the curve.
- **CLOSE / OPEN CURVE** toggles closure.
- **PREVIEW IN WORLD** spawns transient World Builder static markers on the control points and every metre along the curve. They are never saved, are ignored by Runtime Sync, and are cleared on **CLEAR PREVIEW** or when the overlay closes.

MCP: `spline_create`, `spline_add_point`, `spline_insert_point` (on the curve at a distance), `spline_update_point` (position, mode, handles), `spline_delete_point`, `spline_update` (name, closed, tension, colour), `spline_sample`. Every edit is undoable.

## Using a spline

`spline_apply_use(spline_id, kind, params)`, or **APPLY USE**, builds something along the curve and remembers the parameters:

| kind | What it builds | Main params |
| --- | --- | --- |
| `cable`, `fence`, `road` | the existing asset-backed path generators, fed a polyline sampled from the curve (≤ 128 points; closed curves are closed) | `asset_id` (imported Static Mesh with bounds), `segment_length`, `width`, `height`, `post_asset_id` (fence), `sample_spacing` |
| `distribute` | copies of any project asset along the curve (≤ 512) | `asset_id`, `spacing` or `count`, `align` (face along the curve, default on), `yaw_offset`, `random_yaw` + `seed`, `lateral_offset` (+ is left of travel), `height_offset`, `follow_pitch` |
| `npc_path` | a patrol/alert/combat route for a saved NPC population point, looping when the spline is closed (≤ 64 waypoints) | `npc_id` (or an existing `route_id`), `spacing`, `speed`, `wait_seconds`, `variant` |
| `camera_path` | an ordered series of saved shot cameras (kind `path`, tagged `spline_path:<id>` and `order:NNN`) looking ahead along the curve, or at a fixed point; each camera's duration is its spacing divided by `speed` | `count` or `spacing`, `speed` (m/s), `look_ahead` (m) or `look_at` [x,y,z], `fov`, `height_offset`, `hold` |
| `native_spline` | a World Builder **Spline** object (`worldSplineNode`) with the same points and tangents, for export | `name`, `layer` |

- **Undo:** each use is one undo step. A use that fails leaves no history entry and no partial output.
- **Regenerate:** `spline_regenerate` (or **REGENERATE ALL USES**) removes each use's previous output and rebuilds it from the current curve, as one undo step. NPC routes keep their route id and have their waypoints replaced.
- **Removing:** `spline_remove_use` forgets a use and deletes its output unless `keep_outputs=true`. `spline_delete` does the same for every use of the spline.
- **Native spline tangents:** they are written as Hermite tangents, three times the Bezier handles, with both tangents pointing along the curve (the standard Bezier↔Hermite conversion). Only `auto` points set `automaticTangents`. Confirm the curve shape in World Builder after the first export.

## Limits

- The in-game editor edits handles numerically; there is no drag gizmo for handles.
- Cameras are ordered saved shots with durations, not an interpolated dolly move; LocationStudio has no camera-animation playback.
- Generated objects are ordinary project objects. Edits made to them by hand are replaced on the next regenerate; remove the use with `keep_outputs=true` to keep hand edits.
