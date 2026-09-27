# Interactable authoring and native build pipeline

## What v0.47 builds

The Interactables panel accepts a `LootTables.*` record and one explicit `Items.*` row. The full **Build Mod** path writes a TweakXL `gamedataLootTable_Record` with item ID, count range, and drop chance, then includes it in `source/resources/r6/tweaks/`. MCP `create_interactable` and `update_interactable` accept `loot_items`, an array of `{item_record, count_min, count_max, drop_chance}` rows, for multiple entries or custom quantities.

World Builder's typed native export remains the source for streaming-sector node instance data, `.devices`, and `.psrep`; LocationStudio converts those structures to CR2W files. Build Mod now creates `automation/interactables-native-manifest.json` with native resource counts and refuses to emit an empty loot table. It does not synthesize missing `.ent` components or guess controller-state schemas.

The Spatial **Interactables** tab places a registered game **Entity `.ent`**, **Entity Record**, or **Device** asset. It stores additional authoring fields on that placed object:

- `kind`: `door`, `loot_container`, `shard`, or `item`
- `entity_record`: optional game record identifier
- `item_record`: `Items.*` record for a shard or pickup
- `loot_table`: `LootTables.*` record for a loot container
- `loot_items`: one or more `Items.*` records and optional count/drop-chance values for generated loot tables
- `lock_state`: `locked` / `unlocked` for doors and containers
- `fact_name` and integer `fact_value`: intended result of the interaction

Mesh-only assets are rejected because they do not carry an interaction component. The chosen entity is placed using the existing CET/World Builder asset route. Saved lock/fact/item configuration is **authoring metadata and Quest Forge handoff**, not a runtime rewrite of the entity's components or persistent state. The operation response includes `setup_status: "authoring_only"` so automation can see this distinction.

## In-game workflow

1. Open **Spatial → Interactables**.
2. Search and select a game entity asset. Prefer a tested vanilla entity with the correct interaction/controller components. A `.mesh` is not an interactable entity.
3. Choose a kind. For loot containers provide a `LootTables.*` record. For shards/items provide an `Items.*` record. Configure lock state and a namespaced fact such as `my_mod_clinic_door_opened`.
4. Place at aim or at V. Edit the saved fact/lock fields in the placed list.
5. For a loot container, enter an item record in **Generated loot item**. The in-game field creates one guaranteed item (count 1). Use MCP `loot_items` for multiple entries, quantities, or drop chance.
6. Run **Build Mod** or MCP `build_interactable_artifacts(export_file, output)` to generate TweakXL YAML and a native-resource manifest. Build Mod places the YAML in the WolvenKit workspace before conversion.
7. Export **Quest Forge** when quest authoring is needed; its handoff preserves these fields.

## MCP

```text
create_interactable(
  kind="loot_container",
  asset_id="<registered entity asset id>",
  name="Clinic supply case",
  source="aim",
  loot_table="LootTables.MyMod_ClinicSupplies",
  loot_items=[
    {"item_record": "Items.money", "count_min": 20, "count_max": 40, "drop_chance": 1.0},
    {"item_record": "Items.FirstAidWhiffV0", "count_min": 1, "count_max": 1, "drop_chance": 0.25},
  ],
  lock_state="locked",
  fact_name="mymod_clinic_case_opened",
  fact_value=1
)
list_interactables()
update_interactable(
  object_id="<returned object id>",
  lock_state="unlocked",
  fact_name="mymod_clinic_case_opened",
  fact_value=1
)
```

For an item or shard, provide `item_record="Items.MyMod_ClinicShard"` and `lock_state="not_applicable"`. For an explicit placement, pass all of `x`, `y`, and `z`. `delete_interactable` removes the saved object and attempts to remove its tracked live instance.

## Native game behavior requirements

Native requirements depend on the chosen entity. The loot generator creates the TweakXL record, while the entity `.ent` and streaming-sector instance data must provide the actual container components and persistent-state type. Door facts require a working device controller and operations graph. Pickups require a pickup-compatible entity. LocationStudio reports the typed sector/device/PS resources received from World Builder, but does not fabricate unknown RED4 component or operation schemas from a fact name or lock flag:

- The current [lootable-world-object guide](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/miscellaneous/lootable-world-objects) describes the loot table, required interaction/inventory components, `LootContainerObjectAnimatedByTransformPS` instance state, and WolvenKit/streaming-sector work.
- The [Device Operations Container guide](https://wiki.redmodding.org/cyberpunk-2077-modding/modding-guides/world-editing/devices/device-operations-container) describes `FactsDeviceOperation` and `FactOperationsTrigger`. It requires the operations container on a device persistent-state chunk; storing a fact name in LocationStudio does not set that fact when an interaction occurs.
- Quest facts are global integer values stored in the save, and a fact alone does not cause behavior; quest/device logic must read it. See [Quest facts and files](https://wiki.redmodding.org/cyberpunk-2077-modding/for-mod-creators-theory/files-and-what-they-do/file-formats/quests-.scene-files/quests-facts-and-files).

The Quest Forge `interactable_handoff` contains the authored kind, entity/item/loot records, loot rows, lock state, fact/value, and transform. Build Mod can generate loot configuration and consume World Builder's typed sector/device/PS export. Verify the manifest and actual in-game behavior in a disposable save; successful file generation alone cannot prove that the selected entity has compatible components or that its controller sets a fact. The door/fact controller profile portion remains unimplemented until a verified native profile is available.
