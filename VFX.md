# LocationStudio VFX / particle editor

LocationStudio 0.57 adds a searchable editor for game visual effects: smoke, steam, sparks, holograms, fire, dust, leaks and other FX. Each effect is placed as a real World Builder node:

- **Particles** (`worldStaticParticleNode`) play a `.particle` system. They have an emission rate and a *respawn on move* option.
- **Effects** (`worldEffectNode`) play an `.effect` resource.

Every placeable row comes from World Builder's loaded **Deco → Particles** and **Deco → Effects** catalogs. LocationStudio does not ship or invent depot paths. A path passed to MCP must exist in the loaded catalog, or the call is rejected.

## Categories

The categories are keyword filters over the real catalog rows' names and paths:

| Category | Matches |
| --- | --- |
| Smoke | `smoke`, `smk`, `fumes`, `smolder` |
| Steam / vapor | `steam`, `vapor`, `mist`, `exhaust` |
| Sparks | `spark`, `weld` |
| Holograms | `holo` |
| Fire | `fire`, `flame`, `burn`, `ember`, `torch`, `candle` |
| Dust / debris | `dust`, `debris`, `sand`, `dirt`, `ash` |
| Leaks / liquids | `leak`, `drip`, `spill`, `fluid`, `water`, `oil`, `splash`, `puddle` |
| Electrical | `electr`, `zap`, `lightning`, `short_circuit` |
| Weather / ambient | `rain`, `snow`, `leaves`, `insect`, `flies`, `bugs`, `pollen` |
| Other | Rows that match none of the above |

A row can belong to several categories. Its first match is shown as its primary category. Use the free-text search with a category to narrow large catalogs.

## In game

1. Open **Advanced → Spatial → VFX**. World Builder must be loaded, and its Spawn New catalog must be initialized.
2. Type a search term, pick a category and source (Particles, Effects, or both), and click **SEARCH VFX CATALOG**. Select an exact row.
3. Set the orientation (roll, pitch and yaw in degrees), the scale, and, for particles, the emission rate. **Align up axis to aimed surface** points the effect's up axis along the hit normal while keeping your yaw. This suits leaks, sparks and steam coming out of walls.
4. Click **PREVIEW AT AIM**. One temporary node spawns and follows your aim point while **Follow aim** is on. Turn off *Follow aim* and click **UPDATE PREVIEW** to pin the preview. UPDATE PREVIEW also applies new rotation, emission or a different selected row.
5. Click **PLACE PREVIEW** to save the preview at its current transform as one undoable object. **CLEAR PREVIEW** removes it without saving. Closing the CET overlay also clears it.
6. **PLACE AT AIM** and **PLACE AT PLAYER** save an effect directly, without a preview.
7. Select a placed effect in *PLACED EFFECTS* to edit it:
   - Rotation changes move the live node in place.
   - Particle emission changes are written to the live `entParticlesComponent` when World Builder exposes it; otherwise the node respawns.
   - Changing *respawn on move* or the resource respawns the node.

The preview is never written to `project.json`. Placed effects are ordinary project objects (`kind` `particle`/`effect`, layer `decoration`). They work with the hierarchy, transform tools, scenes, world-state variants, undo and World Builder export.

## Scale

World Builder spawns and exports particle and effect nodes at 1:1 scale, and its live preview has no scale control. LocationStudio therefore:

- saves the authored scale (0.01–100, uniform or per axis) in `metadata.vfx.scale`;
- keeps the live preview at 1:1 and never claims a live scale;
- writes the scale into each matching exported node's transform in the **Build Mod** `vfx` stage (`build_mod_from_project`). The native sector writer copies it into the node's `Scale`.

The stage patches the build workspace's copy of the export (`source/raw/…_exported.json`) and records the new hash in the build manifest. The original export is kept as `sourceExportSha256`, and the World Builder export itself is not modified. Nodes are matched by node type, resource path and position (within 0.1 m).

The stage fails when:
- two exported nodes share one effect's resource and position;
- a saved scale is out of range;
- an exported particle's `emissionRate` differs from the saved value.

A saved effect that is missing from the export is a warning, because premise- and scene-scoped builds leave other effects out on purpose.

How much a particular `.particle` or `.effect` visibly responds to node scale depends on the resource. Check the built mod in game.

## MCP examples

```json
{"tool":"vfx_search","arguments":{"query":"vent","category":"steam"}}
{"tool":"vfx_preview","arguments":{"resource_path":"<exact path from vfx_search>","align_to_surface":true,"yaw":90}}
{"tool":"vfx_preview","arguments":{"update":true,"follow":false,"emission_rate":2.5}}
{"tool":"vfx_preview_commit","arguments":{"name":"Clinic vent steam","scale":1.5}}
{"tool":"vfx_create","arguments":{"query":"holo","category":"hologram","source":"player","yaw":180,"scale_x":1,"scale_y":1,"scale_z":2}}
{"tool":"vfx_update","arguments":{"object_id":"<id>","pitch":-20,"emission_rate":4}}
{"tool":"vfx_list","arguments":{"category":"sparks"}}
{"tool":"vfx_export_apply","arguments":{"export_file":"clinic","write":false}}
```

All the tools:
- `vfx_categories`, `vfx_search` and `vfx_list` are read-only.
- `vfx_create` and `vfx_update` save changes. `vfx_create` uses the first `query` match when no `resource_path` is given; pass the exact path for repeatable results.
- `vfx_preview` (`update=true` adjusts the active preview), `vfx_preview_status`, `vfx_preview_commit` and `vfx_preview_clear` drive the live preview.
- `vfx_export_apply` reads a World Builder export offline and reports the scale it would write, or writes it with `write=true`. Use it for a manual WolvenKit import; `build_mod_from_project` already runs the same step.

Check `placement_source` in create and preview results. `forward_fallback` means no surface was hit and the effect sits on the camera ray at the requested distance.

## Requirements and limits

- Requires CET, World Builder 1.0.81 with its Particles/Effects catalogs, and a spawned World Builder session. Without these, calls return a clear error; no fake effect is created.
- Create, update and preview are rejected during an active transform edit, stamp stroke or authoring-plan recovery. Search, list, preview status and preview clear stay available.
- Some effects only play in particular game states, or are one-shot effects that end quickly. A successful spawn means World Builder accepted the node, not that the effect is visible at that moment.
- The automated tests use a mocked CET/World Builder runtime. They check catalog filtering, serialization, preview/commit/undo control flow, live-edit fallbacks, bridge/MCP contracts and native export patching. They do not render REDengine particles. Check placement in game with [IN-GAME-CHECK.md](IN-GAME-CHECK.md).

## References

- [World Builder particle class](https://github.com/justarandomguyintheinternet/CP77_entSpawner/blob/main/modules/classes/spawn/visual/particle.lua): `worldStaticParticleNode`, `entParticlesComponent` named `particle`, `emissionRate`, `respawnOnMove`.
- [World Builder effect class](https://github.com/justarandomguyintheinternet/CP77_entSpawner/blob/main/modules/classes/spawn/visual/effect.lua): `worldEffectNode` and `entEffectSpawnerComponent`.
