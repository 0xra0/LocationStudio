# Render thumbnails for saved prefabs

LocationStudio v0.28.0 adds the MCP tool `wb_prefab_render(prefab_id,
distance=12.0)` and a matching **RENDER THUMB** control in the in-game Prefabs
panel. It works on saved LocationStudio object prefabs (`list_object_prefabs`),
including prefab members backed by World Builder assets.

This does not render arbitrary native World Builder saved-build JSON files
from `entSpawner/data/objects`; those are a different data format and are not
loaded as LocationStudio object prefabs by this operation.

## What it does

1. Resolves the saved prefab in the live LocationStudio project.
2. Places temporary preview instances at the current camera aim point. Visible,
   enabled World Builder objects use their live World Builder handles; `.ent`
   objects use CET's transient entity-spawner path.
3. Captures the actual game screen with the existing platform screenshot helper.
4. Removes the temporary preview instances, writes
   `thumbnails/prefab_<prefab-id>.png`, and persists thumbnail metadata on the
   prefab. It does not add preview objects to the project or save them as an
   authored placement.

```text
list_object_prefabs()
wb_prefab_render(prefab_id="prefab_...")
```

The MCP call waits for capture and cleanup, then returns the PNG path. If a
World Builder removal fails, cleanup remains pending and is logged rather than
pretending the render finished cleanly. Existing thumbnails are retained as a
`.bak` file before replacement.

## Requirements and troubleshooting

- Cyberpunk, CET, and the LocationStudio bridge must be running with a save
  loaded. Aim at a safe, unobstructed spot large enough for the preview.
- Every visible prefab member must resolve to a live World Builder resource or
  a valid `.ent` template; unsupported/missing members stop the render.
- Windows uses the bundled PowerShell screen capture helper. Linux/Proton uses
  an installed screenshot utility (`grim`, `maim`, `scrot`, ImageMagick
  `import`, `gnome-screenshot`, or `spectacle`). The helper reports missing
  dependencies rather than returning a success-shaped placeholder.
- The thumbnail is a crop of the real game frame, so pause menus, HUD elements,
  unrelated world objects, or an off-center aim point may be visible. Re-aim
  and render again for a better result.
- A larger `distance` moves the preview point farther along the camera ray; it
  does not change FOV or automatically fit a very large prefab.
- The headless build/test environment can verify spawning/cleanup contracts and
  file persistence, but only an in-game run can verify REDengine rendering and
  the final composition.
