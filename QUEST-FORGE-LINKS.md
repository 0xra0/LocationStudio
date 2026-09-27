# Quest Forge links

LocationStudio exports a Quest Forge handoff in the **Export + MCP** tab. The
handoff keeps semantic coordinates separate from world-node data so it can be
reviewed and merged into a Quest Forge project without pretending that the
game has created or tested a quest node.

## In the game

1. Create or select a volume on **Premises Builder → Spatial → Volumes**.
2. Enter a fact name under **Quest Forge fact** before creating the volume, or
   select an existing volume and enter **Linked Quest Forge fact**.
3. Give it the intended box dimensions and position. Quest Forge's world trigger
   representation is an axis-aligned bounding box; exported trigger size is
   half-extents in metres. Sphere and cylinder volumes export as bounding boxes.
4. Create locations with type `marker`, `mappin`, or `spot` for points used by
   quest flow, objectives, or scene/workspot planning. Each location becomes a
   static marker NodeRef with its world position and yaw.
5. Export format `questforge`.

Hand-captured locations are marked verified automatically because V is standing
at the recorded position. Manually entered points remain `verified: false` until
you check **Verified in game (standable coordinate)** in the location inspector.
Quest Forge uses that flag to distinguish known-standable positions from
estimates. This is intended to prevent the OI-9 class of coordinate mistake.

## MCP example

```python
create_location_at(
    name="Clinic entrance",
    x=-1891.75, y=-2486.90, z=27.95, yaw=39.5,
    location_type="mappin",
)

create_volume(
    premise_id="clinic-premise-id",
    name="Clinic entrance trigger",
    purpose="trigger",
    x=0, y=0, z=0,
    width=8, depth=6, height=4,
)

link_volume_to_quest_fact(
    volume_id="trigger-volume-id",
    fact_name="clinic_entered",
    value=1,
)

export_project(format="questforge")
```

The operation rejects fact names containing spaces or unsupported punctuation;
the export also blocks invalid names added through the UI. Declare the linked
fact under `facts:` in `quest.yaml`. Pass an empty `fact_name` to clear a link.

## What the export contains

- `questforge_world`: a Quest Forge `world.json`-compatible sector fragment
  with static markers and trigger areas. Marker coordinates are `[x,y,z]` with
  yaw in degrees; trigger `size` uses half-extents.
- `quest_manifest_fragment.locations`: names mapped to marker NodeRefs, ready
  to copy into the `locations:` section of `quest.yaml`.
- `fact_triggers`: the linked volume, fact, value, and intended
  `player_inside` event. `_questforge` metadata is informational: a
  `worldTriggerAreaNode` does not set a quest fact by itself. Wire its entry
  event to the fact in the quest flow and validate the resulting project.
- `semantic_locations`: includes the original LocationStudio ID, semantic kind,
  coordinates, yaw, radius and verification state for marker, mappin and spot
  points.

The target formats keep different responsibilities: merge `questforge_world`
into the Quest Forge project's `world.json`, then copy the generated mapping to
`quest.yaml` under `locations:`. The Quest Forge loader/compiler remains the
authority for validating the complete quest manifest. LocationStudio does not
write into the Quest Forge project directory or edit existing quest files.

Example manifest use:

```yaml
locations:
  clinic_entrance:
    node_ref: mappin_loc_...

journal:
  objectives:
    enter_clinic:
      text: Enter the clinic.
      marker: clinic_entrance
```

Mappins and spots currently export as static marker NodeRefs, the node type
Quest Forge's `world.json` uses for map targets and scene origins. The export
does not author a distinct native GPS marker or workspot node.
