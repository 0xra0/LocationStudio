# Vanilla-world clone / import

LocationStudio 0.67 can turn existing vanilla world nodes into ordinary, editable project objects. This is how you modify an existing interior, such as a clinic, instead of rebuilding it by hand. You can use it in **Spatial → Vanilla clone** or through the `vanilla_clone_*` MCP tools.

Each clone keeps the original's:
- **real resource reference**: the mesh, decal material, effect, particle or entity template, or the population record;
- **appearance**: `meshAppearance` / `appearanceName`, written to the World Builder `app` field or to the CET entity appearance;
- **transform**, with its source recorded (see below);
- **provenance** in `metadata.vanilla_source`: node id, NodeRef, node type, sector path, node index, instance index, debug name, the original transform and scale, and warnings.

Clones spawn through the normal World Builder backend and export with Build Mod like any other object. An entity template that is not in the loaded World Builder catalog falls back to a direct CET `.ent` object. A mesh, decal or effect that is not in the catalog is skipped and reported; it is never registered by guesswork.

## Picking nodes

RedHotTools (WorldInspector) is required for live picks.

- **PICK CROSSHAIR** (`vanilla_clone_pick`) stages the nearest cloneable node under the crosshair. `all_hits` stages everything along the ray.
- **SCAN AREA** (`vanilla_clone_scan`) stages streamed nodes within a radius of V, optionally filtered by path, type, debug name or NodeRef. Only nodes in the camera frustum stream, so turn to cover the room.

Staged candidates show:
- the node type, resource and appearance;
- whether they are cloneable (and why not);
- transform confidence;
- warnings;
- whether they are already cloned.

Select candidates with the list, or with `vanilla_clone_select`.

| Node type | Clone | Notes |
| --- | --- | --- |
| `worldMeshNode` | World Builder Static Mesh | appearance and scale kept |
| `worldBendedMeshNode` | Static Mesh | bending is lost |
| `worldPhysicalDestructionNode` | Static Mesh | destruction physics are lost |
| `worldInstancedMeshNode` | Static Mesh (the picked instance) | live pick only |
| `worldStaticDecalNode` | Decal | |
| `worldEffectNode` / `worldStaticParticleNode` | Effect / Particles | |
| `worldEntityNode` | Entity Template | appearance kept |
| `worldDeviceNode` | Entity Template | device logic, persistent state and connections are **not** cloned |
| `worldPopulationSpawnerNode` | Entity Record | community/spawn conditions are not cloned |
| lights, collision, occluders, foliage, terrain | not cloneable | recreate them with the lighting, collision or visibility tools |

## Transform accuracy

- **Entities** picked live report their real world orientation: `exact`.
- **Streamed nodes** picked live report only their **position**. RedHotTools does not expose a node's orientation or scale through its verified API, so these candidates are `position_only`. They import only with **allow approximate** (rotation 0, scale 1), and the result reports how many clones need aligning.
- **Exact import from the sector:**
  1. Export the sector with WolvenKit (*Convert to JSON*); the pick shows its `sector_path`.
  2. Run `vanilla_clone_from_sector` with `match_staged=true` to re-stage your in-game picks with the exact `nodeData` transform (position, orientation quaternion → Euler, scale).
  3. Alternatively, choose nodes by `node_indices`, `term` or `center`/`radius`. `vanilla_sector_nodes` lists them offline, without the game running.

  Nodes whose instances live in their own buffer (instanced meshes, foliage) are listed as not cloneable from the sector; pick those instances in game.

The Euler conversion uses REDengine's convention: roll about Y, pitch about X and yaw about Z, with q = qz(yaw) · qx(pitch) · qy(roll).

## Importing

**IMPORT SELECTED** (`vanilla_clone_import`) creates every selected clone in **one undo step**. The options are:
- premise/room;
- layer (a locked layer is refused);
- an optional **group name**, which makes a persistent group around the clones' center;
- **hide the originals**.

Hiding uses the existing reversible vanilla-removal records (RedHotTools `ToggleNodeVisibility`), so the clone replaces the original in place. Hiding works only for nodes that have a node id and are currently streamed; failures are listed per object.

Nodes that are already cloned are refused unless you pass `allow_duplicate`.

## Managing clones

The **CLONES** list (`vanilla_clone_list`) shows each clone with what changed since import (position, rotation, appearance) and whether its original is hidden. **REVERT** (`vanilla_clone_revert`) shows the original again and deletes the clone. Pass `delete=false` to keep the clone.

Hidden originals are visibility toggles, not deletions. To remove vanilla geometry in a shipped mod, use your usual archive/AXL workflow; the clone's `vanilla_source` gives you the sector, node index and NodeRef.
