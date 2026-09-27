# Constructive solid geometry

CSG builds architecture from code by combining solids. It can make a wall with a doorway and a window, a tunnel, a shaft, a recess, vents, or a complex room shape, all without external 3D modelling.

A CSG object is a procedural object with the generator `csg`, so it keeps everything procedural geometry has: one undo step, collision, library materials (`@key`), Build Mod meshes, EDL and plans.

Open it at **Spatial → Geometry**, generator `csg`. The example buttons load the trees from `csg/examples.json`. From MCP, use `csg_create`, `csg_examples` and `csg_mesh`.

## Trees

```json
{"op": "subtract", "children": [
  {"shape": "box", "center": [0, 0, 1.5], "size": [5, 0.2, 3]},
  {"shape": "box", "center": [-1.2, 0, 1.05], "size": [1, 0.4, 2.1]},
  {"shape": "box", "center": [1.1, 0, 1.6], "size": [1.4, 0.4, 1.2]}
]}
```

### Nodes

A node is `{op, children, cut_material?, repeat?}`:

| `op` | Result |
| --- | --- |
| `union` | Everything in any child. |
| `subtract` | The first child minus every later child. |
| `intersect` | What all the children share. |

Each node takes up to 64 children, and trees are up to 16 levels deep.

### Leaves

A leaf is one of:

- **A part:** any procedural part.
  - `box` or `wedge`: `center` and `size`. A wedge rises towards +Y.
  - `cylinder`: `center`, `radius` and `length`, along local +Y. `sides` sets the facet count (default 12).
  - `sphere`: `center` and `radius`.
  - `prism`: `points`, `z0` and `z1`.
  - Any part also takes `rotation` (roll/pitch/yaw) and `material` (`main` or `glass`).
- **A generator's output:** `{"generator": "stairs", "params": {...}, "offset": [x, y, z], "rotation": {...}}`. Any procedural generator except `csg` works, and its parts are united.

### Repeat and cut material

- `repeat: {count, step: [x, y, z]}` on any node or leaf makes `count` copies (up to 100), each moved by `step`. Use it for vent slots, window rows or columns.
- `cut_material` (on a subtract node) is the material slot of the faces the cut creates. The default is `main`, so a hole reveals the wall material even when the cutter was glass.

### Limits

- Up to 500 primitive leaves after `repeat` and generator expansion.
- Coordinates are metres in the object's frame, with z up. The object's transform places it in the world.

## Two representations

| | Where | Accuracy |
| --- | --- | --- |
| Build Mod mesh | `mcp_server/lsbuild/csg.py` | **Exact.** The boolean is computed on the faceted solids with BSP trees (the csg.js algorithm). T-junctions are repaired, so the mesh is watertight, material slots are kept, normals stay smooth and UVs are world-projected (library `uv_scale` and `tiling` apply). |
| Preview, bounds, collision | `modules/csg.lua` | Grid boxes. **Exact for trees of axis-aligned boxes** (right-angle rotations included) and for prisms with axis-aligned edges. Curved, sloped or rotated leaves are sampled at `resolution` (default 0.25 m; 0.02–2) and reported as `stats.csg.approximate`. |

More about each representation:

- **Tree storage:** the in-game module expands the tree (generator leaves and repeats) and saves it as `metadata.procedural.csg.tree`, which is what the build meshes.
- **Grid budget:** the preview grid is capped at 40 000 cells. For approximate trees it coarsens the resolution automatically instead of failing, and it reports the resolution it used.
- **Collision:** there is one collision box per preview box, capped at 200. For detailed curved shapes, raise `resolution` or turn collision off and add simple colliders.

`csg_mesh` meshes a saved object (`object_id`) or a raw tree offline. It reports:

- triangles per slot;
- bounds;
- volume;
- `open_edges` (0 means watertight).

Add `glb_path` to write the mesh as glTF for Blender.

## Examples

| Id | What |
| --- | --- |
| `wall_door_window` | Wall minus a doorway minus a window |
| `arched_doorway` | Doorway = box ∪ cylinder, subtracted from a wall |
| `tunnel` | Rock block minus a box ∪ cylinder tunnel |
| `shaft` | Floor slab minus a shaft |
| `recess` | Wall minus a shelf recess |
| `vents` | Panel minus 8 repeated slots |
| `l_room` | L-shaped room shell: (outer ∪ outer) − (inner ∪ inner) − doorway |
| `round_window` | Wall with a round hole, plus a glass pane |
| `column_capital` | Intersection of a box and a vertical cylinder |

## EDL and plans

```yaml
geometry:
  - id: arch
    generator: csg
    params:
      resolution: 0.1
      tree: {op: subtract, children: [...]}
    material: "@plaster"
```

Plans use `create_procedural` with `generator: "csg"`.

## Limits

- Curved leaves are faceted (`sides`), and the result is exact for those facets.
- The in-game preview and collision are boxes; only the built mesh has the exact shape. Check it in game, or look at `csg_mesh` output in Blender.
