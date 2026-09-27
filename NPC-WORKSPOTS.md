# NPC workspots

LocationStudio 0.38 adds saved NPC workspot points for **sit**, **lean**, and **terminal** use. They are stored as ordinary project locations with `type: "workspot"` and `metadata.workspot`, so they remain editable and portable in `project.json`.

## In game

1. Select a premise, then open **Spatial → NPC workspots**.
2. Choose a kind and use **Place at player** or **Place at aim**. The new point is saved in the project; move its XYZ and yaw in the editor.
3. To preview, enter a character TweakDB record such as `Character.ashcache_mara` and the exact AMM animation name, rig, component, and workspot `.ent`. Those AMM fields can be found with the MCP tool `npc_animations_search`.
4. Press **Preview temp NPC**. LocationStudio requests a Codeware temporary NPC spawn at the saved position, then starts AMM's workspot animation after that entity is available. It is not persisted into the game save. Remove preview actors with MCP `npc_despawn_tag(tag="ls_workspot_preview")`.
5. Put a live NPC under the crosshair and press **Check approach** to run the collision hint.

The preview needs Codeware's `DynamicEntitySpec`, CET `exEntitySpawner`, a valid NPC TweakDB record, and AMM's workspot archive. A spawn/animation failure is logged under `logs/locationstudio.log`; the button reports only that a request was queued, not that the animation succeeded. Use `npc_animation_status` or the log to inspect the result.

## MCP example

```text
npc_workspot_create(
  name="Clinic terminal",
  kind="terminal",
  x=-1908.0, y=-2469.5, z=12.0, yaw=45,
  animation_name="stand__lh_tablet__01",
  rig="Woman Average",
  component="amm_workspot_base",
  workspot_ent="base\\amm_workspots\\entity\\workspot_anim.ent",
  npc_record="Character.ashcache_mara"
)
npc_workspot_preview(location_id="<returned location id>")
npc_workspot_check_approach(location_id="<returned location id>", target="crosshair")
```

`npc_workspot_check_approach` casts three Static/Dynamic collision rays from a live NPC toward the saved point. `candidate` means those rays were clear. `blocked_or_inconclusive` means at least one ray hit. Neither result calls or proves REDengine AI navmesh reachability; a doorway, stairs, obstacle avoidance, animation-specific alignment, and NPC behavior can still make the spot unusable. Treat this as a quick geometry check and verify the actual NPC in game.

## Project data shape

```json
{
  "type": "workspot",
  "category": "NPC Workspots",
  "metadata": {
    "workspot": {
      "kind": "sit",
      "record": "Character.example",
      "appearance": "",
      "animation": {"name": "", "rig": "Woman Average", "comp": "", "ent": ""}
    }
  }
}
```

The spot is an authoring point, not a native REDengine workspot resource. For shipped content, build and wire the underlying workspot/scene resources with the relevant game modding tools.
