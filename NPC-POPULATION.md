# NPC Population Editor

The NPC Population panel authors saved character spawn points for a location. Each point is a World Builder Entity Record whose `Character.*` record is exported as a native `worldPopulationSpawnerNode`. It is separate from the temporary NPC preview and from NPC workspots.

## In game

1. Open **Spatial → NPC population**.
2. Search the World Builder **Entity Record** catalog for a `Character.*` record and choose **Import + Select**.
3. Set the appearance and spawn settings. Attitude, faction, level, archetype, idle behavior, despawn distance and quest facts are stored as explicit profile handoff fields.
4. Choose **Create at Player + Preview** or **Create at Aim**. The saved point is placed at that transform. Preview is temporary and can fail independently; the saved point remains in the project.
5. Select a saved point below to edit its settings, then press **SAVE PROFILE CHANGES**.
6. Export the World Builder project. LocationStudio's build pipeline checks that each enabled saved point appears as a matching native `worldPopulationSpawnerNode` at the saved position.

`WB primary/secondary streaming range` controls World Builder streaming. It is not the separate `despawn_distance` profile preference.

## Claude MCP examples

First search the live catalog and import the desired resource through the in-game asset browser. Then use its imported LocationStudio asset ID:

```json
{"tool":"npc_population_create","arguments":{"asset_id":"ASSET_ID","name":"Clinic guard","appearance":"street","attitude":"hostile","faction":"clinic","level":10,"archetype":"guard","idle_behavior":"patrol","despawn_distance":80,"conditions":[{"fact_name":"clinic_alarm","fact_value":1}],"spawn_on_start":true,"always_spawned":false,"primary_range":100,"secondary_range":120,"x":-1908,"y":-2469.5,"z":12,"yaw":45}}
```

```json
{"tool":"npc_population_list","arguments":{}}
{"tool":"npc_population_update","arguments":{"object_id":"OBJECT_ID","appearance":"street","spawn_on_start":true}}
{"tool":"npc_population_export_audit","arguments":{"export_file":"exports/WorldBuilder-export.json"}}
```

The tool accepts `source` as `player`, `origin`, or `aim`; explicit `x/y/z` coordinates override source placement. `preview` requests a temporary live preview. The MCP server uses the same action layer as the in-game editor.

## What becomes game data

World Builder's Entity Record exporter supports the Character record, appearance, spawn-on-start, always-spawned flag, and primary/secondary streaming ranges on the population node. LocationStudio checks these values through the exported node and refuses to mark the population audit ready when a saved point is missing or mismatched.

The following fields are saved in the LocationStudio project and Quest Forge population handoff, but are **not implemented as native behavior by this editor**: attitude, faction, level override, archetype, idle behavior, despawn distance, and conditional quest facts. They need a compatible Character/profile, quest, or community resource pipeline that consumes the handoff. In particular, this editor does not claim to rewrite Character records or create quest fact callbacks. A temporary preview is not proof that the exported persistent NPC has the requested AI behavior.

## Troubleshooting

- If no records appear, open World Builder's Entity Record catalog and search for `Character.`; the game/catalog must be available to World Builder.
- If create reports that Entity Record data is incomplete, re-import the record from the live catalog.
- If temporary preview fails, use the LocationStudio debug log; the saved population point can still export.
- If the build audit fails, inspect `automation/npc-population-audit.json` in the prepared build workspace and check the corresponding native World Builder export.
- This validation checks exported node type, record, appearance, spawn flags, and position. It cannot confirm that the game loaded the final mod or that custom AI/quest behavior executes in game.
