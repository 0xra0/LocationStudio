# Visual regression shots — LocationStudio 0.44

This workflow captures repeatable views from saved LocationStudio cameras after a rebuild, compares each PNG with the last explicitly accepted set, and writes a per-camera heatmap and JSON manifest. It runs through the MCP server because screenshots are taken by the Linux desktop compositor, not by CET's in-game Lua sandbox.

## One-time setup

1. In **Spatial → Cameras**, create and save a camera for every view you want to track. Set position, orientation/look-at, and name. Give each saved camera a stable ID by keeping that camera in the project; the ID is the comparison key.
2. Ensure the game is running under Hyprland and `grim` is installed. The existing MCP `screenshot` tool uses `hyprctl` and `grim` to capture the game window.
3. Optionally set `LOCATION_STUDIO_SHOT_DIR` to the directory where you want screenshot runs. The regression data is stored below `<shot-dir>/locationstudio-regression`. Set `LOCATION_STUDIO_REGRESSION_DIR` to place regression data elsewhere.

## Capture after rebuild

Use `hotcycle_rebuild` with `capture_visuals=true`. It deploys scripts, hot-loads archives and respawns requested tagged entities first; after those steps complete, it captures the selected cameras. If `visual_camera_ids` is omitted or empty, it captures all enabled saved cameras.

```text
hotcycle_rebuild(
  archives=["/path/to/rebuilt.archive"],
  script_files={"r6/scripts/MyMod/MyMod.reds": "/path/to/rebuilt/MyMod.reds"},
  respawn_tags=["my-location-props"],
  system="MyMod.LocationGlue",
  capture_visuals=true,
  visual_camera_ids=[],
  visual_settle_s=7,
  visual_pixel_threshold=24,
  visual_change_limit=0.01
)
```

You can also run `visual_regression_capture` on its own after a rebuild. Its optional `camera_ids` selects a subset; omit it to capture all enabled saved cameras. Every selected camera must still exist and be enabled in the project.

The result includes a `run_id`, screenshot paths, per-camera diff metrics, and the run directory. PNGs are saved as `runs/<run-id>/camera_<stable-camera-hash>.png`; diffs use `diff_<hash>.png`; `manifest.json` records camera names/IDs, FOV metadata, comparison results, and errors. The player is returned to their captured transform after the shot series when the bridge remains available.

## Accept a baseline

The first capture has no baseline. Inspect its screenshots, then explicitly accept it:

```text
visual_regression_accept(run_id="20260927-142200-1a2b3c4d")
```

Future captures compare only with this accepted run. A new capture never changes the baseline automatically. Review the diff PNGs and manifest before accepting a changed build. Accepting a run requires all requested screenshots to have been captured successfully.

The default comparison marks a pixel changed when its largest RGB channel difference exceeds 24/255. A camera is flagged when more than 1% of its pixels differ. Both values are configurable on capture and hotcycle. A resolution mismatch is always incompatible and flagged; the images are not resized to hide it.

## Deterministic screenshot mode

Pass `deterministic=true` to `visual_regression_capture`, or `visual_deterministic=true` to `hotcycle_rebuild`, to remove run-to-run noise:

```text
visual_regression_capture(environment_id="env_…", deterministic=true)
```

1. **Enter** (`screenshot_mode_enter`): each configured game setting has its current value recorded before it is changed.
   - HUD elements (`/interface/hud`: minimap, quest tracker, health bar, prompts, …) are turned off.
   - Post effects (`/graphics/basic`: MotionBlur, FilmGrain, ChromaticAberration, DepthOfField, LensFlares) are turned off.
   - With `environment_id`, that saved environment is forced (fixed time, weather and optional fog; see [ENVIRONMENT-PREVIEW.md](ENVIRONMENT-PREVIEW.md)).
2. **Per camera:**
   - After the camera teleport and `settle_s`, the capture **waits for streaming**: static collision below the camera must answer `ready_samples` probes in a row, within `ready_timeout_s`.
   - The world is then **frozen** with a near-zero named time dilation, which stops NPCs, traffic, particles and cloud movement.
   - Shots are repeated until two consecutive frames differ by at most `stability_limit` (up to `stability_max_shots`).
   - The world is unfrozen before the next teleport.
3. **Restore** (`screenshot_mode_restore`, always in `finally`): the world is unfrozen, every changed setting is written back to its recorded value, and the environment is restored.

Camera shake is handled like this:
- The saved camera preview stands the player still.
- Freezing stops time-driven shake.
- No verified camera-shake setting ships in the defaults; add one to `settings.screenshot_mode.camera_shake_vars` if your game build has one.

Settings that don't exist in the running build, or refuse a write, are listed in `screenshot_mode_unavailable` and left untouched. Run `screenshot_mode_capabilities` (or **Spatial → Environment → CHECK GAME SETTINGS**) to see which of the configured settings exist and their current values. The HUD, post-effect and extra lists live in the project's `settings.screenshot_mode` and can be edited.

A camera whose world never finishes streaming, or whose frames never stabilize, is recorded as not captured, so the run can't become a baseline. The manifest records the mode options, the settings applied, the ones unavailable and any restore error. Accepting stores the mode with the baseline, and a later capture made with different mode options sets `screenshot_mode_mismatch`. If a restore fails, the unrestored settings stay recorded; call `screenshot_mode_restore` again. The restore record also survives a CET mod reload.

## Repeatability limits

Saved cameras fix the player position and rotation through LocationStudio's existing camera preview/teleport. Camera FOV is recorded from the saved camera, but this workflow does not change the game's global camera FOV. Keep the game graphics FOV, resolution, HUD state, and other mods consistent between the accepted baseline and later runs. Pass `environment_id` (a saved authoring environment, see [ENVIRONMENT-PREVIEW.md](ENVIRONMENT-PREVIEW.md)) to force the same time, weather and fog for every run; the manifest flags `environment_mismatch` when the accepted baseline used different conditions. NPC animation, traffic, lighting, and weather can still create legitimate pixel changes. Increase `visual_settle_s` if teleport motion blur or streaming has not settled.

The screenshot helper currently targets a Cyberpunk window found by Hyprland and uses `grim`. Other desktop environments or unsupported screenshot commands fail with a clear tool error; they do not produce a fake pass. Screenshot/diff files remain on the local machine and are not uploaded automatically.
