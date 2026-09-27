# LocationStudio v0.37.0 first run

1. Install Cyber Engine Tweaks and World Builder 1.0.81 or a compatible newer
   version. Extract the upgrade-safe archive into the Cyberpunk 2077 game root.
2. Load a save, open CET, and confirm the LocationStudio header says `v0.37.0`.
3. Open **HELP + START**. The page reports live game, entity-spawner, and room
   backend readiness. Red means stop and create a debug report.
4. Press **SPAWN TEST CHAIR**. A chair must appear near V. Press **REMOVE TEST
   CHAIR** and confirm it disappears.
5. Stand at the intended origin. Press **BUILD STARTER WORKSPACE**. This invokes
   one validated transaction that creates a real game-asset room shell, chair,
   entrance, trigger volume, camera, and scene collection.
6. Open **SCENE**, select the chair, and use **GRAB WITH CROSSHAIR** or **EDIT
   TRANSFORM**. Commit to keep the move; cancel to restore it.
7. Press **UNDO** once. The complete starter workspace must be removed. Press
   **REDO** once to restore its project data, then activate the scene to respawn.
8. Save only after the result is correct.

To use Scene Director, open **SCENE**, choose a location, enter a scene name and
press **NEW FROM LOCATION**. Select props in the hierarchy and use **ADD CURRENT
SELECTION** or **REMOVE CURRENT SELECTION**. **ISOLATE** leaves only that scene's
tracked game objects live; **DEACTIVATE** removes them without deleting data.

Your mutable `data/project.json`, `data/config.json`, logs, exports, thumbnails,
and bridge state are omitted from every upgrade-safe archive.

If a plan fails and the header says **RECOVERY REQUIRED**, do not reload mods or
delete project data. Use **RETRY SAFE ROLLBACK** after fixing the runtime adapter,
or deliberately choose **KEEP PARTIAL RESULT**. Save/export/history stay paused
until that decision prevents orphaned game objects.

For support, press **SAVE DEBUG REPORT** and send the versioned file from
`logs/LocationStudio-v0.37.0-support.txt`. It excludes project JSON but may show
asset paths and transforms, so review it before sharing.
