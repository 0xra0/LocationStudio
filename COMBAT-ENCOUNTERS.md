# Combat Encounter Authoring

Combat Encounters connects persistent NPC population points, gameplay volumes, faction labels, and reinforcement conditions into one editable quest-combat plan.

## In game

1. Create persistent `Character.*` NPC population points first. Place their saved transforms where each member should appear.
2. Create a box or other gameplay volume for the **combat area** and another for the **entry trigger** in the same premise.
3. Open **Spatial → Combat encounters**, create an encounter, then choose its area and trigger volumes. Add optional encounter activation and reset fact names/values.
4. Select population records and create enemy groups. Add more saved NPC records to a selected group, assign its faction and friendly/neutral/hostile attitude, and set preview spacing.
5. Add waves. Choose immediate, volume, fact, or after-wave activation; assign a trigger/fact or prior wave and delay; check which groups appear in the wave.
6. Add faction relationships. These are explicit encounter relations, not a global TweakDB faction edit.
7. **TEST SELECTED WAVE** (or leave a wave unselected to test all waves) temporarily spawns the referenced Character records at their saved NPC transforms. **RESET TEST ENCOUNTER** removes the temporary entities. Test is capped at 64 temporary NPCs.
8. Export Quest Forge to get the `combat_encounters` data, linked group members, area/trigger volume geometry, wave conditions, reinforcement dependencies, and faction relationships. The exporter rejects missing NPC, group, wave, volume, and fact references.

## MCP examples

```json
{"tool":"combat_encounter_create","arguments":{"name":"Clinic ambush","premise_id":"PREMISE_ID","area_volume_id":"AREA_VOLUME_ID","trigger_volume_id":"TRIGGER_VOLUME_ID","activation_fact":"combat_enabled","activation_value":1}}
{"tool":"combat_group_create","arguments":{"encounter_id":"ENCOUNTER_ID","name":"Tyger Claws","npc_ids":["NPC_OBJECT_ID_1","NPC_OBJECT_ID_2"],"faction":"tyger_claws","attitude":"hostile","spacing":1.5}}
{"tool":"combat_wave_create","arguments":{"encounter_id":"ENCOUNTER_ID","name":"Initial defenders","group_ids":["GROUP_ID"],"activation":"volume","trigger_volume_id":"TRIGGER_VOLUME_ID"}}
{"tool":"combat_wave_create","arguments":{"encounter_id":"ENCOUNTER_ID","name":"Reinforcements","group_ids":["GROUP_ID"],"activation":"after_wave","after_wave_id":"WAVE_ID","delay_seconds":12}}
{"tool":"combat_faction_relation","arguments":{"encounter_id":"ENCOUNTER_ID","source_faction":"tyger_claws","target_faction":"player","attitude":"hostile"}}
{"tool":"combat_encounter_test","arguments":{"encounter_id":"ENCOUNTER_ID","wave_id":"WAVE_ID"}}
{"tool":"combat_encounter_reset","arguments":{"encounter_id":"ENCOUNTER_ID"}}
```

Other MCP tools: `combat_encounter_list`, `combat_encounter_update`, `combat_group_update`, `combat_group_delete`, `combat_wave_update`, `combat_wave_delete`, and `combat_encounter_delete`.

## Runtime boundary

The editor saves a structured encounter plan and Quest Forge handoff. The Test button uses CET/Codeware DynamicEntitySpec to spawn temporary Character-record stand-ins; Reset deletes the tagged stand-ins. This preview verifies that the chosen records can be requested from the temporary spawner, but it does not validate combat AI.

Trigger activation, quest fact writes/reset callbacks, reinforcement scheduling, navmesh/pathing, hostile perception, faction behavior, and persistent enemy group execution are **not run by this editor yet**. Compatible REDengine quest/community/guard-area resource wiring must consume the exported data. No native `worldGuardAreaNode`, community graph, quest controller, or callback is fabricated and presented as functional.
