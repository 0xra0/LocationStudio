# Quest Simulation and Debug Panel

Open **Spatial Editor → Quest Debug** to inspect the current quest facts linked to the authored location. The panel scans trigger volumes, interactables, NPC conditions, route branches, combat encounters and device-logic nodes/links, then reads live values through CET's quest system when it is available.

## Inspect

- Click **Refresh Quest State** to read the live values again.
- Filter the fact list or enter any fact name to inspect it.
- Select a fact to see its authored writers, readers/conditions and references.
- A missing game API or unavailable read is shown as unavailable; LocationStudio does not substitute the project's intended value for a live value.

## Set, reset, or simulate a trigger fact

1. Select or type a fact name and enter the desired integer value.
2. Click **Prepare Fact Write** or **Prepare Reset to 0**. For a trigger, choose a linked volume and click **Prepare Trigger Fact**.
3. Review the pending fact name and current/requested values, then read the warning.
4. Click **Confirm & Change Active Save** to invoke `SetFactStr`, or cancel to leave the game unchanged.

Preparation and preview do not change game state. Confirmation changes active quest state, may activate quest scripts or advance progression, and cannot be undone by LocationStudio. Make a backup save before confirming test writes. Setting a fact to `0` is a write, not a restore of the previous quest history.

Manual trigger simulation writes the value attached to the volume's Quest Forge fact using `SetFactStr`. It does not cause the engine's trigger volume collision/event to fire, and it does not test native trigger geometry or event wiring.

## MCP tools

- `quest_simulation_state()` — list linked facts and current live values.
- `quest_simulation_state(fact_name="... ")` — inspect one fact.
- `quest_simulation_prepare_fact_write(fact_name, value, source)` — stage and return a one-time confirmation token and save warning.
- `quest_simulation_prepare_trigger(volume_id)` — stage the configured trigger-fact value.
- `quest_simulation_confirm_fact_write(token)` — apply only the matching pending write.
- `quest_simulation_cancel_fact_write(token)` — discard the pending write.

There is intentionally no direct MCP set/reset command. The confirmation token is transient and is discarded on cancel, successful write, or game/mod restart.

## Runtime boundary

LocationStudio reads `Game.GetQuestsSystem():GetFactStr(name)` and confirms writes with `SetFactStr(name, value)`. These calls are guarded and reported as unavailable/failure if CET or the game rejects them. A successful API call confirms the fact value was requested; it does not verify that every native quest node, device, trigger or AI action reacted as intended. Verify the quest behavior in game after using a disposable test save.
