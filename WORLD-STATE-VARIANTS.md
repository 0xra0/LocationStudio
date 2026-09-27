# Conditional World-State Variants

Variants let one authored location show different sets of placed game assets as quest facts change. Example states include `before_quest`, `during_quest`, `after_quest`, `destroyed`, and `cleaned`.

## In-game authoring

1. Open **Spatial Editor → World States**.
2. Create a named variant with a quest fact condition and expected integer value. For more complex logic, edit conditions through MCP; every condition in a variant must match.
3. Select each placed object and add it to the variant as **show** or **hide**. Objects can represent props, NPCs, doors, light entities, decals, sound entities, and effects when they are authored as spawnable LocationStudio object assets.
4. Create additional variants for the other quest phases and assign their show/hide rules. All variants for a shared location should cover each expected phase.
5. Click **Preview Current Fact State** and resolve any equal-priority conflicts. **Apply Current Fact State** switches the tracked scene objects for the current live facts.
6. Enable **Auto-switch live objects when quest facts change** if you want LocationStudio to poll facts and apply transitions during the current game session. This toggle is session-only and starts off after restarting the mod.

## Behavior and safety

- Conditions use live quest facts; supported comparisons are `==`, `~=`, `>`, `>=`, `<`, and `<=`. Multiple conditions on one variant are ANDed.
- Higher priority wins when multiple active variants target the same object. Conflicting show/hide rules at the same priority block apply and appear in the preview.
- The first time an object is added to a variant set, LocationStudio records its baseline enabled, visible, and tracked state. If no state rule matches, it restores that baseline. Removing an object's final rule or deleting its final variant also restores the baseline.
- Applying a variant spawns or despawns the actual tracked CET/World Builder object entities; it does not modify quest facts. It is blocked while transform/stamp transactions or authoring-plan recovery are active.
- Automatic switching polls about once per second. It pauses during active transform/stamp/recovery work.
- This system is a LocationStudio runtime authoring/test layer. It does not create native REDengine quest graphs, world-state components, persistent-state records, or native trigger events. If a selected object has no usable entity/resource, its spawn failure is reported and its prior flags are restored.
- Volumes and cameras are not directly switched as independent spawned entities by this feature. Add their represented spawnable object assets when the visible scene element is a game object.

## MCP workflow

```text
world_state_variant_create(name="before_quest", fact_name="clinic.quest_stage", value=0, priority=10)
world_state_variant_add_object(variant_id="<variant id>", object_id="<object id>", visible=true)
world_state_variant_create(name="destroyed", fact_name="clinic.destroyed", value=1, priority=20)
world_state_variant_add_object(variant_id="<destroyed id>", object_id="<intact wall id>", visible=false)
world_state_variant_add_object(variant_id="<destroyed id>", object_id="<rubble id>", visible=true)
world_state_preview()
world_state_apply()
world_state_auto_switch(enabled=true)
```

`world_state_preview` is read-only. Applying or enabling auto-switch changes the in-game scene by spawning/despawning the configured LocationStudio entities, but does not write quest/save facts. Use `quest_simulation_prepare_fact_write` and its separate confirmation flow only if you also intend to change active quest state; see [QUEST-SIMULATION.md](QUEST-SIMULATION.md).
