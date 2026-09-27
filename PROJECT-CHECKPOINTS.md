# Project Checkpoints

Checkpoints save a named copy of LocationStudio's editable project data in the mod's `data` folder. They do not include live game handles or runtime state.

## In the game

Open **Tools → Project Checkpoints**, enter a unique name, and select **Save Checkpoint**. Select two checkpoint entries in the comparison controls and choose **Compare Checkpoints**. Object changes are listed as added, removed, moved, or changed. Room, location, premise, volume, camera, scene, and route counts are also summarized.

To restore, select a checkpoint, choose **Restore Selected Checkpoint**, then confirm. Restore enters the normal undo history, so use **Undo** to reverse it. The project is marked dirty and is saved by the normal autosave or explicit save button. If the restored data differs from currently spawned entities, the header reports **Runtime Out of Sync**; inspect the listed changes and choose **Sync Runtime** to apply them.

## Claude MCP

The four tools use the live CET bridge; LocationStudio must be running in game.

```text
create_project_checkpoint(name, description="")
list_project_checkpoints()
diff_project_checkpoints(checkpoint_a, checkpoint_b)
restore_project_checkpoint(checkpoint_id)
get_runtime_sync_status()
sync_runtime()
```

Use IDs returned by create/list, rather than checkpoint names, for diff and restore. The diff compares the first ID to the second. Object position/rotation changes are reported as moves (position tolerance 1 mm, rotation tolerance 0.01 degrees); other object edits are reported as changes.

## Files and limits

The mod stores the index in `data/checkpoints.json` and each snapshot in `data/checkpoint_<id>.json`. Checkpoints are immutable and are not automatically pruned. Copy these files with the project to transfer checkpoint history to another installation.

Restore changes the editable project model. Sync Runtime only reconciles entities currently tracked as spawned by LocationStudio; it leaves saved objects that were never spawned alone. A checkpoint is not a full backup of game files, World Builder files, or external mod resources.
