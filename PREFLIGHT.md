# Shipping preflight

LocationStudio 0.70 adds one command that answers "can I ship this?": **`preflight_run`** (MCP). It runs every check the project has, in game and offline, and gives one verdict with a report of what blocks it. In game, **Spatial → Preflight** runs the in-game half, loads the full report, and selects the object behind an issue.

## Checks

Each check is `pass`, `warn`, `fail` or `skipped`, and its issues name the object, route or graph involved.

**In game** (needs the running game; skipped otherwise):

| Check | Fails on | Warns on |
| --- | --- | --- |
| Project data | model validation errors | model validation warnings |
| Resource paths | missing/unknown World Builder definitions, empty resource paths, wrong extensions (`.mesh`, `.ent`, `.mi`…), bad TweakDB ids, templates that are not `.ent`, missing WB entry data | with `deep=true`: paths absent from the loaded World Builder catalogs (usually modded; see the dependency check) |
| Asset bounds | — | meshes without imported bounds |
| Spawns | stored spawn errors, objects expected live but not spawned | live objects that differ from saved data |
| NodeRefs | malformed or duplicate NodeRefs, device nodes bound to deleted objects | — |
| Quest facts | invalid fact names or non-integer values (volumes, world-state variants, encounters and waves, route branches, interactables, population conditions, timeline fact keys) | — |
| Native interactable setup | unknown kinds, invalid or duplicate `LootTables.*` records, empty loot, non-`Items.*` records | interactions still authoring-only |
| Ambient areas | areas with fewer than 3 outline markers or no height, emitters without an event | areas with neither sound event nor reverb, orphan outline markers |
| Workspots and routes | routes using deleted workspots or NPCs | workspots on no NPC route, empty routes |
| Device links | device-logic graph errors (missing endpoints, bad facts or operations) | missing native device, PS or NodeRef bindings |
| Exportable objects | CET entity-spawner objects (not exportable to sectors), nothing exportable in scope | World Builder objects that are not live for export |

**Offline** (always run):

| Check | Source |
| --- | --- |
| Asset dependencies | [dependency resolver](ASSET-DEPENDENCIES.md). Missing files and raw-JSON-only files fail. External mod requirements and unclassified files warn. |
| Streaming sectors | [sector inspector](SECTOR-INSPECTOR.md) on the latest (or named) World Builder export. Its error flags fail. It also feeds NodeRefs: a reference under the export's own NodeRef root that is missing fails, while vanilla or other-mod references warn because they cannot be verified. It also feeds device links: links to devices missing from the export fail. |
| Native interactable artifacts | a dry generation of the TweakXL loot records and native manifest |
| NPC population export | population points without a matching `worldPopulationSpawnerNode` |
| Visual regression | the latest run (or a new capture with `run_visual_regression=true`). Regressions fail. A run without a baseline, an environment mismatch, or a run older than the last project change warns. |

## Verdict

`ready` is true only when:
- the in-game checks ran,
- no check failed, and
- with `strict=true`, nothing warned either.

`blocking` lists the failing checks. Checks the game could not run are `skipped`, and the report says to rerun with the game open; an offline preflight is never `ready`.

Arguments:
- `export_name`: which World Builder export to inspect (default: the newest);
- `premise_id`: limits the object checks;
- `deep`: looks paths up in the World Builder catalogs;
- `sources` / `game_root`: passed on to the dependency resolver.

The report is saved to `exports/preflight-report.json`. In game, click **LOAD FULL REPORT**, open a check, and click **SELECT** on an issue.

Recommended order before shipping:
1. Run `preflight_run(strict=true, run_visual_regression=true)` with the game open.
2. Fix what it lists, then run it again.
3. Run `build_mod_from_project`.
4. Follow `IN-GAME-CHECK.md`.
