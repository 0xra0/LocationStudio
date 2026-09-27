# entSpawner-inspired tools in LocationStudio v0.5.0

LocationStudio v0.5.0 adapts useful authoring workflows from the supplied `CP77_entSpawner` source into LocationStudio's own persistent scene model, shared selection state, live-preview layer, and Claude MCP bridge.

This is an integration of editor concepts, not a vendored copy of entSpawner. LocationStudio keeps its own data schema and only uses CET/REDengine APIs already available to the mod at runtime.

## Active-camera placement

Aim placement now starts from the active game camera when CET exposes it. This makes free-camera and cinematic placement behave like an editor viewport rather than always projecting from the player origin. When the camera transform is unavailable, LocationStudio falls back to the player transform and raises the ray to approximate eye height.

The **TOOLS** workspace can capture the active camera as a persistent LocationStudio camera node, including FOV where available.

## Transform clipboard

For premises, rooms, objects, volumes, cameras, and locations:

- Copy position
- Copy rotation
- Copy full transform
- Paste position
- Paste rotation
- Paste full transform
- Reset rotation
- Move to player
- Move to aim/crosshair
- Drop to ground
- Teleport player to the selected item

Premise and room transforms are group-aware. Moving or rotating a premise transforms its child rooms, construction objects, volumes, and cameras around the premise anchor. Room transforms similarly preserve its authored contents.

## Look-at / targeting

A selected transformable item can be stored as a transform target. Other selected items can then be aimed at that target, at the player, or at the current crosshair hit. Cameras preserve and transform their authored `look_at` point when a parent room/premise is transformed.

## Duplication and procedural placement

The **TOOLS** workspace adds:

- Duplicate at aim
- Object mirror X/Y
- Linear array with position and yaw increments
- Scatter stamp around the current aim point
- Scatter count and radius controls
- Optional random yaw
- Optional per-copy ground projection
- Optional live spawning through LocationStudio's existing preview system

Scatter is implemented as a batched LocationStudio model operation, so generated objects remain normal editable project objects rather than unmanaged transient entities.

## Claude MCP

v0.5.0 exposes the same workflows to Claude through the file-backed MCP bridge: active-camera capture, transform copy/paste/reset, move-to-player, move-to-aim, drop-to-ground, player teleport, transform target management, look-at operations, duplicate-at-aim, and scatter-at-aim.

## Runtime boundary

Raycasts and camera access depend on the CET/REDengine APIs exposed by the installed game/runtime. LocationStudio records whether placement used an active camera ray, an entity look-at hit, or a forward fallback. Live `.ent` preview spawning still requires `exEntitySpawner` and a valid depot path.
