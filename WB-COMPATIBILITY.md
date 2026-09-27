# Collision and compatibility scans

## `wb_collisions`

`wb_collisions(object_ids=[], premise_id="", margin=0)` checks a selected set,
a single premise, or all visible and enabled placed objects. It uses only
resource-local bounds stored in object metadata and transforms those eight
corners into conservative world axis-aligned boxes. Objects without usable
bounds appear in `skipped`; they are never treated as collision-free. The scan
is limited to 300 objects per request and caps returned collision pairs at
2,000.

```json
{"premise_id":"premise-123","margin":0.02}
```

`margin` expands both boxes before comparison, so positive values flag close
clearances as well as intersections. Results include pair IDs, names, expanded
intersection dimensions, skipped reasons, scan scope, and a truncation flag.
Touching faces are not counted as intersections.

This is a broadphase check only. Rotated or irregular meshes can produce false
positive AABB intersections. It does not query actual REDengine physics, infer
missing mesh bounds, test navmesh, or add/change game collision geometry. Import
accurate bounds for useful results. Existing `wb_bounds_overlap` remains the
explicit-pair operation when every supplied object must have bounds.

## `wb_compat_scan`

`wb_compat_scan(game_root="")` is read-only. Its live CET portion reports the
loaded state of integrations visible through `GetMod` (currently World Builder/
entSpawner, AMM, and RedHotTools) and checks LocationStudio objects for missing
resource paths and bounds coverage. Its MCP process also inventories filenames
and folder names in common mod locations: `archive/pc/mod`, `r6/scripts`,
`r6/tweaks`, RED4ext plugins, and CET mods. Supply `game_root` if the MCP server
cannot infer the Cyberpunk installation directory.

The folder inventory is context, not a compatibility verdict. The scanner does
not read opaque `.archive` internals, resolve redscript/tweak load order, inspect
mod source for patches, or prove binary/API compatibility. An integration is
reported as loaded only if CET exposes it under one of the `GetMod` keys that
LocationStudio checks. Review `findings`, `loaded_integrations`, and
`installed_mod_inventory` together; `verified_compatibility` remains false.

```json
{"game_root":"/games/Cyberpunk 2077"}
```
