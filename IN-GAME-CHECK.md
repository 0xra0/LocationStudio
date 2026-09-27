# LocationStudio 0.28.0 in-game check

## Install

1. Close Cyberpunk and back up the existing LocationStudio `data` folder.
2. Extract `LocationStudio-v0.28.0-game-resources-upgrade-safe.zip` into the game
   root and allow file replacement.
3. Start the game, load a save, open CET, and confirm **v0.28.0** in the header.

The upgrade archive does not contain project/config JSON, logs, exports,
thumbnails, or bridge state.

## World Builder native Favorites smoke check

1. Confirm `wb_favorites_list()` returns categories from the installed
   World Builder Favorites folder.
2. Search `asset_catalog_search` and choose a result ID. Call
   `wb_favorite_add(catalog_id, category="LocationStudio")` without `write`;
   confirm the result says `preview=true` and no file changed.
3. Repeat with `write=true`. Confirm the tool reports the category file and
   favorite name. For an existing category it must report a timestamped backup.
4. Call `wb_favorites_list(category_filter="LocationStudio")` and confirm the
   resource path appears once. Reload World Builder/CET or restart the game to
   refresh the in-memory Favorites panel.

This check edits World Builder's favorite JSON but does not spawn an object or
register one in LocationStudio's Project Assets.

## Saved prefab thumbnail smoke check

1. Save a small prefab from visible placed game-asset objects in the SCENE
   hierarchy, or use `list_object_prefabs()` to choose an existing one.
2. Aim at clear open space, then invoke
   `wb_prefab_render(prefab_id="...")` or use **SCENE → PREFABS → RENDER THUMB**.
3. Confirm the MCP result reports `rendered: true` and
   `thumbnails/prefab_<id>.png`; the temporary preview objects should be gone.
4. Re-open the Prefabs panel and confirm the thumbnail appears. If it does not,
   inspect `get_debug_log()` and the screenshot helper's `.error` file.

The frame is an actual game screenshot crop, not a synthetic or placeholder
image. HUD/background clutter and framing depend on the aim point and current
camera; use the thumbnail guide for capture requirements.

## Native vanilla-world visibility removal

This workflow hides streamed vanilla world nodes through the verified
RedHotTools `ToggleNodeVisibility` API. It does not permanently delete game
world data, and it does not mutate entity-only targets.

1. Call `vanilla_removal_status` and confirm RedHotTools WorldInspector reports
   `ready=true`. If it reports that `Game.GetWorldInspector` is unavailable,
   stop and collect diagnostics; do not use `run_lua` as a workaround.
2. Aim at a visible static vanilla mesh or other streamed world node and call
   `remove_vanilla_under_crosshair`. Confirm the result says
   `operation=toggle_visibility`, `permanent=false`, and returns a persistent
   removal record. Confirm the target disappears without affecting a
   LocationStudio-owned object.
3. Call `list_vanilla_removals`, then `restore_vanilla_removal` with the record
   ID. Confirm the same node becomes visible again.
4. Turn the camera across a room and call `remove_nearby_vanilla_assets` with a
   small radius. Confirm only eligible nodes in the RedHotTools frustum are
   hidden; the response may report failures for nodes that stream out.
5. Call `restore_all_vanilla_removals` and save the project. Reload the Lua mod
   or the save only after confirming the records and runtime state are clean.

## Hot reload / runtime ownership

1. Start Cyberpunk 2077, load a save, and open Location Studio. Spawn at least one verified direct `.ent` object through CET and one verified World Builder resource. Confirm both are visible and selected state is usable.
2. Reload only the LocationStudio Lua mod using the CET development reload workflow, without exiting or reloading the game. The reload must not call `despawn_all`; both existing objects must remain visible.
3. Open the editor again and run the typed `reload_runtime` operation, or call the MCP `reload_runtime` tool. Confirm the result reports direct entities as `direct_confirmed` and retained World Builder handles as `world_builder_preserved`; no object should be respawned.
4. Move the retained World Builder object with its native gizmo and verify the transform still synchronizes to the project. Confirm the direct CET object's ownership remains tracked and an explicit delete/despawn still removes it.
5. If reconciliation reports missing handles, do not delete project JSON or repeatedly reload. Capture `get_debug_log`, `get_diagnostics`, and a support report; restore the backend and retry reconciliation. Active transform/stamp transactions and `recovery_required` intentionally block reload reconciliation.

## v0.24 Scene Director acceptance

1. Build or load a location containing a real room shell, two placed props, a
   trigger volume, and a camera. Open **SCENE** and confirm Scene Director shows
   separate editing/live status.
2. Enter a name and press **NEW FROM LOCATION**. The new scene must contain the
   room, ordinary props, volume and camera. Room-kit wall/floor pieces must not
   be duplicated in explicit object membership unless **Include construction
   pieces** was enabled.
3. Select another placed object. Confirm the editing scene name remains visible,
   then press **ADD CURRENT SELECTION**. Remove it again and verify the object
   remains in the project and game.
4. Add a semantic point and route to the scene. Press **SYNC LOCATION CONTENT**.
   The room/prop/volume/camera membership must update while the manually added
   point and route remain members.
5. Press **ACTIVATE**. Every room shell and explicit scene object must be live.
   Place/spawn an unrelated project object, then press **ISOLATE**. The unrelated
   object must despawn while scene objects remain live.

## v0.25 Asset bounds acceptance

1. Import or register a real World Builder mesh asset. Call `wb_bounds_info`;
   without a bounds record it must clearly report `has_bounds=false`, not invent
   geometry from the asset name.
2. Dry-run `wb_bounds_import` using `examples/asset-bounds-manifest.json` (or
   an equivalent manifest with the selected asset ID). Confirm the returned
   entry count and dimensions without changing project state. Apply it and
   confirm the operation is one Undo step.
3. Use `wb_bounds_set` with measured local min/max values. Confirm `info` shows
   the edited values/source and an existing object placed from that asset gets
   the updated bounds.
4. Verify `wb_bounds_fit` returns only a proposed scale; it must not silently
   resize the asset. Verify `wb_bounds_world_aabb` accounts for rotation,
   translation and per-axis scale.
5. Run `wb_bounds_overlap` on two known object IDs. Confirm separated boxes do
   not overlap and intersecting boxes are returned as broad-phase candidates.
   Do not interpret AABB intersection as exact mesh collision or as creation of
   an in-game collider.
6. Press **DEACTIVATE**. Scene runtime objects must disappear, while rooms,
   props, gameplay data and the scene collection remain saved.
7. Bind and verify the Activate Editing Scene, Isolate Editing Scene,
   Deactivate Live Scene, and Add Selection to Editing Scene CET hotkeys.
8. Through MCP, test `capture_scene_from_premise`, `edit_scene_members`,
   `get_scene_status`, `activate_scene`, `isolate_scene`, and `deactivate_scene`.
9. Run `examples/authoring-plan-captured-scene.json`. Confirm its room, table,
   chair, trigger, captured scene and runtime activation commit as one Undo.
10. Save a debug report and confirm its scene status contains both
    `editing_scene_id` and `live_scene_id` when applicable.

If deactivation reports a cleanup refusal, do not delete the scene. Repair the
backend and retry deactivation so LocationStudio retains runtime ownership.

## v0.23 Authoring Plan and Scene acceptance

1. Open **HELP + START**. Confirm GAME READY, ENTITY SPAWNER READY, and ROOM
   ASSETS READY. Spawn and remove the test chair.
2. Stand in a clear area and press **BUILD STARTER WORKSPACE**. Confirm a visible
   game-asset room and chair appear, and SCENE lists the new room, construction
   pieces, chair, and First Scene.
3. Select First Scene and press **ACTIVATE SCENE**. Select its objects and move
   the chair with **GRAB WITH CROSSHAIR**; cancel once and commit once.
4. Press Undo once after the original plan build. The complete premise, room,
   chair, point, volume, camera, and scene must disappear together. Redo and
   activate the scene to respawn saved project objects.
5. Copy `examples/authoring-plan-furnished-room.json` to
   `data/authoring-plan.json`. Validate and run it from HELP + START. Confirm the
   table, chairs, lamp, room shell, and scene are created as one Undo.
6. Change one alias reference to `$missing` and validate. It must reject the
   plan without changing project or live game state.
7. Through MCP, call `get_authoring_plan_schema`, resolve assets, validate a
   plan, execute it with `save=false`, inspect `get_authoring_plan_status`, and
   select/activate its scene.
8. Run diagnostics and save a debug report. Confirm it includes `scenes` and
   `authoring_plans` runtime sections and uses the v0.28.0 filename.

Do not intentionally force runtime-removal refusal in a normal save. The
isolated contract test covers the recovery gate; if it occurs naturally, follow
TROUBLESHOOTING.md and retry rollback before saving.

## v0.22 Transactional Stamp Stroke acceptance

1. Select a location and an imported World Builder asset. Under **ASSETS**,
   enable **Stamp placement**, set spacing to `0.75`, and press **START STROKE**.
   The live preview and yellow **STAMP STROKE ACTIVE** toolbar must appear.
2. Aim at a visible surface and press **STAMP NOW** twice without moving. The
   first real object must appear; the second click must be rejected by spacing
   and must not create an overlapping project or runtime object.
3. Move the crosshair more than `0.75 m` and stamp at least two more objects.
   The toolbar count must match every accepted visible object.
4. Press **CANCEL STROKE**. Every object from the stroke and its preview must
   disappear, the previously selected Project Asset must return, and undo
   history/project dirty state must remain unchanged.
5. Repeat and press **COMMIT STROKE**. One **UNDO** must remove the complete
   stroke and one **REDO** must restore every saved stamped object.
6. Repeat with a direct CET `.ent` Project Asset. Every click must create a
   visible entity through CET rather than a project-only/invisible object.
7. While a stroke is active, try Save, Undo, Placement + Edit, and an unrelated
   MCP mutation. Each must explicitly require commit/cancel instead of saving
   partial stroke state.
8. Start a stroke, stamp objects, and close the CET overlay. Reopen it and verify
   the uncommitted objects were cancelled and no undo entry was added.
9. Bind **Location Studio - Stamp active asset preview once**, **Commit active
   stamp stroke**, and **Cancel active stamp stroke**. Confirm all three operate
   the same transaction shown in the toolbar.
10. Through MCP, start a stamp preview, add several objects, inspect
    `get_stamp_stroke_status`, then test `cancel_stamp_stroke` and
    `commit_stamp_stroke`. `stop_asset_preview` must remain a commit alias.
11. If cancel reports that a live object could not be removed, do not delete the
    object or reload immediately. Press **SAVE DEBUG REPORT** and send the report
    while the stroke is still active so ownership and backend errors are logged.

## v0.21 Placement + Edit acceptance

1. Open **ASSETS**, choose an imported World Builder mesh and press **PREVIEW**.
   Aim it at a visible surface, then press **PLACE + EDIT**. The preview must be
   replaced by one real visible copy at exactly the previewed transform and the
   yellow **PLACEMENT EDIT ACTIVE** toolbar must appear.
2. Move and yaw the copy, then press **CANCEL**. It must disappear completely and
   the original Project Asset must be selected again. Undo history must not gain
   an entry.
3. Repeat and press **COMMIT**. One **UNDO** must remove the placed asset and one
   **REDO** must restore it.
4. Repeat with a direct CET `.ent` Project Asset. Movement/yaw must refresh the
   visible entity; scale must remain explicitly unavailable for direct CET.
5. Test **HERE + EDIT**. The asset must start at V's transform and enter the same
   transaction instead of becoming an uneditable immediate object.
6. Select one World Builder object and one direct CET object in **SCENE**, then
   press **AIM COPY + EDIT**. Both copies must appear at the crosshair while
   preserving their spacing and height difference.
7. Cancel that mixed selection and verify both copies disappear and both source
   objects are reselected. Repeat, commit, and verify one undo removes both.
8. Enable surface alignment, aim at a sloped Static/Terrain surface and place a
   single asset. Its local-up axis must align to the returned normal while its
   yaw remains independently editable.
9. Start Placement + Edit and close CET. Reopen it and verify all uncommitted
   copies were removed.
10. Bind **Location Studio - Place asset or copy selection at crosshair and
    edit**. If any step fails, create a support report immediately before reload.

## v0.20 Transactional Scatter acceptance

1. Place and spawn one World Builder mesh. In **Advanced Tools → Duplicate /
   Pattern / Scatter**, set Count `6`, Radius `2`, Seed `2077`, enable Random Yaw
   and Ground, then press **SCATTER + EDIT**. Six visible copies and the yellow
   **SCATTER EDIT ACTIVE** toolbar must appear.
2. Press **CANCEL**. Every copy must disappear, the original must remain selected
   and unchanged, and undo history must not gain an entry.
3. Repeat with the same seed and settings. The positions and yaw values must be
   identical. Change only the seed and verify the layout changes.
4. Select two objects as a set—one World Builder resource and one direct CET
   `.ent` object. Scatter two stamps. Each stamp must preserve the pair's spacing
   and height offset while both backends remain visible.
5. Move and yaw the scattered result, then press **COMMIT**. One **UNDO** must
   remove every created copy; one **REDO** must restore the complete result.
6. Select an imported Project Asset instead of a placed object and press
   **SCATTER + EDIT**. Verify its real resource type is used, including non-`.ent`
   World Builder assets.
7. Aim above a surface with Ground enabled. Each stamp center must reach the
   surface while a multi-object stamp preserves internal height offsets. Aim
   where no downward Static/Terrain hit exists and verify no partial copies are
   created.
8. Scatter a generated room-kit piece, commit, and rebuild its room. All scatter
   copies must survive as detached decoration.
9. Start a scatter and close CET before committing. Reopen CET and verify every
   preview copy was removed.
10. Bind **Location Studio - Scatter selection or asset and edit copies**. If a
    copy fails to spawn, move, undo, or disappear, immediately create the support
    report and send it with `logs/locationstudio.log`.

## v0.19 Pattern Placement acceptance

1. Place and spawn one World Builder mesh. Select it and press **ARRAY** in the
   Inspector. Two additional live copies and the yellow **ARRAY EDIT ACTIVE**
   toolbar must appear.
2. Move and yaw the pattern with the toolbar, then press **CANCEL**. Every copy
   must disappear, the source must remain unchanged and selected, and undo
   history must not gain an entry.
3. Open **Advanced Tools → Duplicate / Pattern / Scatter**. Set Count `4`, dX
   `1.0`, dY/dZ `0`, dYaw `0`, then press **CREATE ARRAY + EDIT**. Copies must
   appear at cumulative one-metre steps. Commit, then verify one **UNDO** removes
   all four copies and one **REDO** restores all four.
4. Repeat with dYaw `30`. A single source must rotate 30/60/90... degrees; a
   multi-object selection must rotate as an assembly around its source pivot
   without losing relative spacing.
5. Repeat with one World Builder mesh plus one direct CET `.ent` asset selected.
   Every copy must appear and respond to Transform Edit; scale must remain
   unavailable for the mixed selection.
6. Press **MIRROR X**, then **MIRROR Y**. Verify reflected position and facing
   around the location origin. This is placement/orientation mirroring, not
   negative-scale mesh geometry.
7. Pattern a generated room piece and commit it. Rebuild the room; every created
   copy must survive as independent decoration.
8. Start an array, close CET without committing, reopen it, and verify every
   preview copy was removed.
9. Bind the Array, Mirror X and Mirror Y hotkeys. Generate a debug report
   immediately if a copy fails to spawn, update, undo, or disappear on cancel.

## v0.18 Duplicate + Edit acceptance

1. Place and spawn one World Builder mesh, select it in **SCENE**, and press
   **DUPLICATE + EDIT**. A second visible mesh and the yellow **DUPLICATE EDIT
   ACTIVE** toolbar must appear; the original must remain unchanged.
2. Press **+X**, **+Z**, and **YAW +**. Only the copy must move and rotate.
   Press **CANCEL**; the copy must disappear and the original must be selected.
3. Repeat, press **COMMIT**, then **UNDO** once. The duplicate must disappear.
   Press **REDO** once; the same saved duplicate must return.
4. Start Duplicate + Edit and immediately press **COMMIT** without moving it.
   One **UNDO** must still remove the new copy.
5. Select two or more World Builder assets, press **DUPLICATE SET**, and move and
   yaw the copies. Their spacing and height offsets must remain stable.
6. Select one World Builder asset plus one direct CET `.ent` asset. Duplicate and
   move them together. Both live copies must update; scale controls must remain
   unavailable for the mixed selection.
7. Duplicate a generated room wall/floor/ceiling piece and commit it. Rebuild the
   room; the detached duplicate must survive as an independent decoration.
8. Start Duplicate + Edit, close CET without committing, reopen CET, and confirm
   that all copies were removed and no extra undo step was created.
9. Bind and test **Location Studio - Duplicate selection and edit copies** in CET
   Bindings. Generate a debug report immediately if any runtime copy does not
   appear or disappear as described.

## v0.17 Transform Edit acceptance

1. In **SCENE**, select one live World Builder mesh and press **EDIT TRANSFORM**.
   The yellow Transform Edit toolbar must appear without moving the object.
2. Press **+X**, **+Y**, and **YAW +**. The same World Builder handle must update
   in place after every click, and the displayed deltas must match the configured
   move and angle steps.
3. Press **SIZE +**, then **RESET**. Position, rotation, and scale must return
   exactly to the session-start values while the session remains active.
4. Apply another move and press **CANCEL**. The project object and World Builder
   handle must return to their original values and **UNDO** must have no new step.
5. Start again, adjust the object, and press **COMMIT**. Exactly one **UNDO** must
   restore its complete starting transform and scale.
6. Select three World Builder meshes, choose **PIVOT: CENTER**, and press
   **EDIT SELECTION**. Move, yaw, and scale the set. Relative spacing and height
   offsets must remain stable; group Roll/Pitch controls must not be shown.
7. Change to **PIVOT: ACTIVE** and enable **Local axes**. With an active object
   that has a nonzero yaw, +X must follow that object's local X direction.
8. Repeat with one direct CET `.ent` object. Each X/Y/Z or rotation click must
   visibly replace it at the preview transform before commit. Scale controls
   must be unavailable because direct CET scale is unsupported.
9. While Transform Edit is active, **SAVE PROJECT**, export, undo/redo, and an
   unrelated MCP mutation must be refused until commit or cancel.
10. Start an edit and close the CET overlay. Reopen it and confirm that the
    uncommitted transform was cancelled and restored. Generate a debug report.

## v0.16 Grab Move acceptance

1. In **SCENE**, select one live World Builder mesh and press
   **GRAB WITH CROSSHAIR**. The yellow Grab Move header must appear and the mesh
   must follow the crosshair without creating copies.
2. Press **YAW +** twice, toggle **Grid snap**, and aim at another surface. The
   live mesh and stored transform values must use the new position and yaw.
3. Press **CANCEL MOVE**. Position, rotation, scale, and the live World Builder
   handle must return exactly to their starting values.
4. Start again and press **COMMIT MOVE**. Save must now work, and one press of
   **UNDO** must restore the original position in both LocationStudio and World
   Builder.
5. Select three World Builder objects, press **GRAB SELECTION**, rotate and move
   them. Their relative spacing and height differences must remain unchanged.
6. While Grab Move is active, press **SAVE PROJECT**. It must refuse and request
   commit/cancel. Close the CET overlay without committing, reopen it, and verify
   the selection returned to its original transforms.
7. Repeat with one direct `.ent` object. The header must report it as **CET on
   commit**; after commit the old entity must be replaced at the final position.
8. Bind and test the CET hotkeys for Grab, Commit, Cancel, Rotate Left, and Rotate
   Right. Generate a debug report afterward.

## v0.15 aim/surface/stamp regression

1. Open **ASSETS → MY ASSETS**, select an imported Static Mesh or valid `.ent`,
   enable **Align preview to surface**, and press **PREVIEW**. Aim at a floor:
   the preview should remain upright and follow the raycast point.
2. Aim at a wall. The preview must visibly rotate to the wall normal. If the
   resource uses an unusual authored axis, confirm the stored roll/pitch changes
   and note the resource path in the report.
3. Enable **Stamp placement**, set minimum spacing to `0.50`, and press
   **START STROKE** then **STAMP NOW**. One normal editable project object must
   appear and the temporary preview must remain active.
4. Press **STAMP NOW** again without moving. It must refuse the duplicate with a
   spacing message. Aim at least 0.5 m away and stamp again; the second object
   must appear while the first remains editable.
5. Open **SCENE**, aim directly at one stamped object, and press
   **PICK AIMED OBJECT**. The Inspector must select that object; for World Builder
   assets its native handle/gizmo must also become selected.
6. Press **COMMIT STROKE**, save, reload all mods, and confirm both stamped
   objects remain in the project.
   Run **SAVE DEBUG REPORT** and confirm diagnostics include `viewport_tools`,
   preview stamp state, and the last pick record.

## Full construction regression

1. Open **BUILD**. Confirm **GAME-ASSET ROOMS READY** and **REAL GAME ASSETS** appear.
2. Choose **COMMON INTERIOR**, enable collision, and create a 5×5×3 m room in an
   open area. The result must be textured architecture pieces—not white cubes.
3. Walk on the floor and into a solid wall. You should not fall through or pass
   through it. Collision debug boxes must not be visible.
4. Add an adjacent north room with automatic doorway. The shared opening should
   use a door-wall module and remain passable.
5. Open **SCENE** and confirm a populated **CONSTRUCTION** group appears without
   enabling Advanced Tools. Filter it to **WALL** and select one wall.
6. Press **WORLD BUILDER GIZMO**, move/rotate/scale the wall, then select another
   item and return. The Inspector values and saved project must retain the move.
7. Use the `[ ]` toggles to select at least three walls. Confirm **MULTI-SELECTION**
   appears in the Inspector. Move X/Y/Z, rotate yaw and scale the set. Movement
   must preserve relative layout; rotation and scale must use the selected pivot.
8. Press **GROUP GIZMO**. All spawned pieces in the set must become selected in
   World Builder. Change the World Builder selection with Ctrl-click and confirm
   LocationStudio updates its selection count and active object.
9. Move three selected objects to visibly different X, Y, and Z values. Cycle
   **ALIGN: MIN → CENTER → MAX → ACTIVE**, then test **ALIGN X/Y/Z**.
10. Move the middle object off-center and test **SPACE X/Y/Z**. The first and
   last pivots must remain fixed and the middle pivot must become evenly spaced.
11. Give the active object a unique rotation and scale. Test **MATCH ROTATION**
   and **MATCH SCALE**; all selected World Builder resources must update live.
12. Put selection transforms off-grid and press **SNAP SET**. Position and angle
   values must follow the current project grid/angle settings.
13. Select an imported Static Mesh and press **REPLACE SET ASSET**. Every selected
   mesh must respawn with that resource while relative transforms remain intact.
14. Cycle **PIVOT: CENTER → ACTIVE → CUSTOM**. Confirm rotation visibly changes
   origin. Capture the custom pivot from V and verify the set rotates around V.
15. Under **GROUPS**, name the selection and press **CREATE GROUP**. Clear the
   selection, select the group row, and confirm every member is restored.
16. Name the same selection and press **SAVE PREFAB**. A matching entry with the
   correct object count must appear under **PREFABS**.
17. Press **AT PLAYER**, then **AT AIM**. Each action must create visible game
   resources as a selected editable group—not an invisible room or marker.
18. Move one prefab instance, edit one member separately, then dissolve its group
   with **X**. Every placed object must remain after the group disappears.
19. Lock the set. Transform, delete, duplicate, replace and gizmo access must be
   rejected until it is unlocked.
20. Hide and show the set, then duplicate it. Only selected live objects must
   despawn/respawn, and duplicated generated pieces must be independent.
21. Delete the duplicated set and confirm the original room remains intact.
22. In **ASSETS → GAME DATABASE**, import/select a Static Mesh. Return to the wall
   and press **REPLACE ASSET**. Only that wall should change.
23. Press **DETACH / MAKE UNIQUE**, then rebuild the parent room. The detached wall
   must remain while all still-managed room pieces are regenerated.
24. Use the role toolbar to hide and show walls. Matching live meshes must despawn
   and respawn; floors and ceilings must remain unchanged.
25. Return to **BUILD**, choose **KITSCH APARTMENT**, and press **REBUILD SELECTED
   ROOM**. The selected room should be replaced by Kitsch architecture.
26. Open **ASSETS → GAME DATABASE**, choose **Static Meshes**, search for a modular
   wall, import and select it. Return to BUILD, press **SET WALL**, then rebuild.
   New wall pieces must use that selected resource.
27. Press **SAVE PROJECT**, reload all mods, and confirm the selected kit, custom
   role, rooms, placed objects, groups, and prefab definitions remain present.

For an upgraded v0.9.x project, the first load should log
`builder:room_kit legacy_migration`. If a legacy generated object somehow remains,
the runtime must report **Legacy primitive shell blocked** instead of spawning a
white cube.

## Send a failure report

Immediately after the first failed step, press **SAVE DEBUG REPORT** and send:

```text
bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio/logs/LocationStudio-v0.28.0-support.txt
```

Include the failed step and a screenshot. If LocationStudio cannot open, send
`logs/locationstudio.log` and CET's log. The support report includes the active
kit/resource paths, mesh and collider counts, legacy object count, World Builder
catalog/class status, current selection, panel errors, and recent action logs.
