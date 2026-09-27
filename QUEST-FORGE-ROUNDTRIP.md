# Quest Forge round-trip

LocationStudio can import an edited Quest Forge handoff after its first export. It previews exact identity matches, associates Quest Forge NodeRefs and facts with local locations, trigger volumes, cameras and objects, and shows those links in the selected-item inspector.

## Safe update behavior

- Matching uses the embedded LocationStudio ID first, then a NodeRef already linked on that local item. It does not fuzzy-match names or create new local geometry from unknown nodes.
- The default import updates only `metadata.questforge_sync`. It preserves the local transform, name, notes, tags, category, and other metadata.
- Changed external coordinates are shown as conflicts. Check **Apply incoming positions** only when you want those coordinates to replace local placement.
- Re-export reuses imported NodeRefs and manifest keys and carries linked trigger facts forward.
- Unmatched Quest Forge nodes are counted in the preview and left untouched.

## In-game workflow

1. Export a Quest Forge handoff from LocationStudio.
2. Edit that world/manifest in Quest Forge and save the edited handoff JSON.
3. Copy the file into the LocationStudio mod folder (or its `exports/` folder).
4. Open **Spatial Editor → Quest Forge Sync**, enter the mod-relative JSON path, and click **Preview Import**.
5. Review the linked rows, facts, unmatched count, and coordinate conflicts. Leave coordinate application off to keep your local placement.
6. Click **Update Linked Items**, then save the project. Inspect any selected location, volume, camera or object to see its NodeRef and facts.

The editor path is relative to the mod's current CET working directory. If that path is inconvenient, use the MCP file-path tools below; those read the specified JSON file on the machine running the MCP server.

## MCP workflow

```text
questforge_sync_preview(file_path="/path/to/edited-questforge-handoff.json")
questforge_sync_apply(file_path="/path/to/edited-questforge-handoff.json")
questforge_links(kind="volume", item_id="<LocationStudio volume id>")
```

Coordinates are preserved by default. To deliberately accept Quest Forge position edits:

```text
questforge_sync_apply(file_path="/path/to/edited-questforge-handoff.json", apply_positions=true)
```

`kind` is `location`, `volume`, `camera`, or `object`. IDs are available from LocationStudio's project export and existing MCP list tools. A preview has no project side effects; apply is undoable and marks the project dirty for save.

## Matching limitations

The exact ID mapping is carried in the handoff's `_locationStudio` annotations. If a Quest Forge workflow strips those annotations, previously imported NodeRefs still match after the first sync. On a first import where both the IDs and annotations have been removed, the rows remain unmatched rather than risking a destructive name-based merge. Quest Forge facts are descriptive links; importing them does not compile REDengine quest logic.
