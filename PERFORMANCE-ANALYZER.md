# Streaming / performance analyzer

A location can look right and still stream badly. LocationStudio 0.62 estimates what each room, premise and exported sector asks the engine to load. It reports:

- node counts: static meshes, lights, audio emitters, decals, VFX, dynamic entities, collision and meta nodes;
- expensive resources;
- a weighted relative cost;
- budget overruns;
- distance from V;
- unusually dense clusters and heavily overlapping lights.

**The cost is a relative estimate for comparing areas, not measured frame time.**

## What is counted

| Category | Resources (cost weight) | Marked expensive when |
| --- | --- | --- |
| static | static mesh (1), proxy mesh (0.5), instanced mesh (1) | — |
| lights | static light (4, +radius/5 when radius > 15 m, +1 flicker), reflection probe (6) | radius > 15 m; reflection probe |
| audio | static audio emitter (2), ambient area (1) | — |
| decals | decal (1.5, +2 when larger than 16 m²) | large decal |
| vfx | particle / effect (4, +emission/5 when emission > 5), fog volume (5), water patch (6) | emission > 5; fog; water |
| dynamic | entity templates/AMM/devices and direct CET `.ent` spawns (3), rotating mesh (3), dynamic mesh (5), cloth (6), Character records / NPC population (6), AI community (4) | cloth, physics, NPCs, rotating, communities |
| collision | collision shape (0.5), collision mesh (1) | — |
| meta | markers, splines, areas, occluders, AI spots (0.1–0.5) | — |

Live analysis classifies project objects by their World Builder resource definition. Export analysis classifies native node types (`worldStaticLightNode`, `worldClothMeshNode`, …) and reads the light `radius` and particle `emissionRate` from the node data. Exported nodes with a `secondaryRange` over 1000 m are listed as long streaming range: they stay loaded from far away.

## Budgets

| Scope | nodes | lights | audio | decals | vfx | dynamic | cost |
| --- | --- | --- | --- | --- | --- | --- | --- |
| room (default) | 250 | 12 | 8 | 60 | 10 | 25 | 400 |
| premise (default) | 1200 | 40 | 30 | 250 | 40 | 100 | 1800 |
| exported sector | 1500 | 60 | 40 | 300 | 50 | 150 | 2500 |

Room and premise budgets live in `settings.performance` and can be changed with `performance_set_budget`. Objects outside any room are grouped as "<premise> (outside rooms)".

## Dense clusters and overlapping lights

The objects are binned into 5 m XY cells. A cell is dense when its cost reaches at least `cluster_min_cost` (40), and also exceeds the median cell cost by `cluster_sigma` (3) × the robust spread (MAD × 1.4826). Using the median and MAD means one very busy corner can't hide itself by raising the average. Touching dense cells merge into a cluster, reported with its centre, radius, counts, rooms, distance from V and its most expensive contributors. A light whose radius overlaps more than `light_overlap_limit` (4) other lights is listed separately.

## Using it

- **In game, Spatial → Performance:** analyze the selected premise or the whole project. It lists rooms by cost, with budget overruns and distance from V, and dense clusters with **SELECT**, which selects every object in the cluster for the transform or Inspector tools. It also shows overlapping lights. When a sector report is loaded, it shows per-sector costs too.
- **MCP:**
  - `performance_analyze(premise_id?)`, `performance_set_budget(scope, …)` and `performance_select_cluster(index)` work on the live project.
  - `performance_export(export_file)` analyzes the sectors of an exported World Builder file, with distances from V when the bridge is live.
- **Sector report:** `sector_inspect` and the Build Mod `sectors` stage include the same per-sector analysis under `performance`.

## Limits

- Vanilla world content around the location is not included, and the engine's actual LODs, occlusion, shadow settings and resource sizes are unknown to LocationStudio. Use the numbers to find outliers, then confirm with in-game frame timing.
- Distances use V's current position. With the game offline they are omitted.
