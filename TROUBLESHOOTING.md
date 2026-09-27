# LocationStudio troubleshooting

## Nothing spawns

Open **HELP + START** and check all three readiness badges. Run **SPAWN TEST
CHAIR** first. If it fails, the problem is the direct CET entity path rather than
room construction. If the chair works but rooms do not, inspect World Builder
1.0.81 compatibility and the **ROOM ASSETS READY** reason.

## Only the starter assets appear

Open **ASSETS**, select **GAME DATABASE**, search, choose a result, and save it
as a Project Asset. The six starter entries are only known-good smoke tests. The
game database/World Builder catalog supplies the broader resource catalog.
Place direct `.ent` entries through CET; imported World Builder entries retain
their entry/class/resource metadata.

## An object spawns but will not move

Select the placed object under **SCENE**, not the catalog card. Use **GRAB WITH
CROSSHAIR** or **EDIT TRANSFORM**, then commit. A locked object must be unlocked.
World Builder objects update in place when supported; direct CET entities are
refreshed after edits.

## A room is invisible or wrong

Rooms depend on the real game-asset room kit and World Builder. Select the room
and use **REBUILD ROOM** only after **ROOM ASSETS READY** is green. Check the
diagnostic report's `room_kit` roles and World Builder class probes. Room data is
not created when strict runtime preflight fails.

## A plan is stuck in recovery

Do not reload mods, save, export, Undo, or manually delete project JSON. Read
the header/error, repair the backend, then press **RETRY ROLLBACK**. If the
remaining objects are genuinely wanted, **KEEP PARTIAL** converts them into one
undoable change. This is deliberate orphan prevention.

## Send a useful report

Press **SAVE DEBUG REPORT**. Send
`logs/LocationStudio-v0.28.0-support.txt`. It includes capability probes,
integration/placement/scene/plan status and recent structured log lines, but not
the project JSON. `mcp_server` also offers `create_debug_bundle` for a ZIP.
