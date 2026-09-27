# Native Runtime Reconciliation

LocationStudio compares its saved object data with the project entities it currently owns in CET or World Builder. The comparison is read-only. If it finds drift, the editor header shows the affected object names and a **Sync Runtime** button.

Sync updates changed tracked objects to their current project transform/resource and removes tracked entities whose project object was deleted, disabled, hidden, or removed from a visible layer. CET-spawned entities are refreshed; World Builder handles are updated when possible. Failed operations remain listed in the returned report and are written to the debug log.

The comparison is refreshed after Undo/Redo, checkpoint restore, project initialization/load, and periodically while the editor is open to catch external edits. Sync does not spawn every authored project object: objects that have never been spawned remain unspawned. It also does not enumerate or modify arbitrary game entities that LocationStudio does not own.

## MCP

```text
get_runtime_sync_status()
sync_runtime()
```

The status tool reports `checked`, `has_changes`, per-action counts, and object entries. Sync is refused while a transform/stamp operation or authoring-plan recovery is active. After syncing, the report includes a fresh comparison; remaining differences usually indicate a spawn/removal failure.

## Limits

World Builder objects expose transform getters, so live gizmo edits can be compared directly. For CET entities, LocationStudio uses tracked spawn IDs, spawn templates, last synced authoring data, and live transform getters where the entity API provides them. A runtime object for which the game exposes no inspectable transform may be reported as unverified; LocationStudio avoids destructive refreshes when it cannot establish a mismatch.
