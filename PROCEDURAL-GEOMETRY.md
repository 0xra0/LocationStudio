# Procedural geometry

LocationStudio 0.72 generates structural geometry from dimensions and parameters. Structural meshes no longer have to exist in the game already. You can build it in **Spatial → Geometry**, with the `procedural_*` MCP tools, or from the [Environment Definition Language](ENVIRONMENT-DEFINITION-LANGUAGE.md) (`geometry:` lists).

| Generator | Parameters (metres) |
| --- | --- |
| `wall` | `length`, `height`, `thickness`, `openings [{offset, width, height, sill}]`; `offset` is the opening centre measured from the wall's middle |
| `floor` | `width`, `depth`, `thickness`, or `points [[x,y],…]` for any simple polygon (concave allowed) |
| `ceiling` | like `floor`, plus `height` (underside) |
| `column` | `shape box/round`, `width`/`depth` or `radius`, `height`, `base {height, overhang}`, `cap {height, overhang}`, `sides` |
| `stairs` | `width`, `height` (rise), `length` (run), `steps` (default: risers ≤ 18 cm), `solid`, `tread`, `landing`, `stringers` |
| `ramp` | `width`, `length`, `height`; `solid` wedge or sloped slab with `thickness` |
| `door_frame` | opening `width`, `height`, `frame` profile, `depth`, `threshold` |
| `window` | `width`, `height`, `sill`, `frame`, `depth`, `mullions_x`, `mullions_y`, `glass` (separate `glass` material slot) |
| `railing` | `points` polyline (3D; follows stairs) or `length`, `height`, `post_spacing`, `post_size`, `rails`, `rail_size` |
| `pipe` | `points` polyline (3D), `radius`, `sides`, `elbows` |
| `duct` | `points` polyline (3D), `width`, `height` |
| `box` | `size [x,y,z]`, `anchor bottom/center`; use it for beams, slabs and plinths |

The local frame is x right, y forward and z up, with the origin at the object's transform. The object's yaw rotates everything. Invalid parameters are refused with a reason: openings past the wall ends, overlapping openings, openings taller than the wall, coincident polyline points, and values out of range.

## What gets created

Creating is **one undo step**, and so is editing the parameters (`procedural_update`). If an edit is invalid, nothing changes.

- **A `procedural` project object.** It stores the generator, its parameters and the generated **parts** (box, wedge, cylinder, sphere, prism): the single source of the geometry. Its bounds become `asset_bounds`, so overlap, fit, performance and visibility checks can measure it.
- **Collision** (on by default): real World Builder collision boxes that approximate the parts (glass excluded, ramps as sloped slabs). They are exported like any collision. The limit is 200 per object.
- **A preview.** The generated mesh does not exist in the game until the mod is built, so the parts are previewed with transient World Builder shapes:
  - `collision` (default): visualized collision shapes; no setup, but they block movement while shown;
  - `mesh`: a registered unit mesh scaled per part (`procedural_settings(proxy_asset_id, proxy_native_size)`);
  - `none`.

  Non-box parts are previewed as boxes. The preview is never exported.

## Materials and the real mesh

**Since 0.73 the preferred path is a native mesh.** Give `materials: {main: <.mi>, glass: <.mi>}`, and Build Mod writes a complete CMesh resource without any template; see [MESH-RESOURCES.md](MESH-RESOURCES.md). The template import described below remains for objects that only name a template mesh.

Each object names a **material template**: an existing `.mesh` whose materials and appearances the generated mesh reuses. Use `asset_catalog_search`, or pick one of your own modded meshes. Set `appearance` to one of its appearances, and `uv_scale` to the metres per texture repeat; UVs are box-projected in world metres, so textures tile evenly at any size. Window glass uses the `glass` material slot.

Build Mod runs a **`procedural`** stage after preparing the workspace and before the dependency check. For every procedural object in scope it:
1. triangulates the parts into a glTF binary (`source/raw/<mesh path>.glb`, Y-up), with outward normals and one primitive per material slot;
2. copies the local template mesh next to it and imports the glb over it with the WolvenKit CLI (`cp77tools` / `WolvenKit.CLI`, default command `import -p <glb> -k`; override with `LOCATION_STUDIO_MESH_IMPORT_CMD` as a JSON list using `{cli}`, `{glb}`, `{mesh}`, `{raw_dir}`), and puts the result in `source/archive/<mesh path>.mesh`;
3. adds a native `worldMeshNode` for it to the nearest exported sector. The node goes before any variant range, the sector bounds grow to fit it, and the object's stream range (default 150 m) is used.

The stage **stops the build** when:
- an object has no template;
- the template is not available locally (extract it with WolvenKit into `mod_sources/` or another source folder);
- the CLI is missing or the import did not change the mesh.

The glb files are still written for inspection. `procedural_export_glb` writes them offline at any time, for example to check them in Blender.

Generated meshes live under `mod\locationstudio\procedural\<premise>\` by default (`procedural_settings(mesh_root=...)`). The dependency resolver treats the template mesh as a dependency and does not report the generated mesh as missing. The preflight fails a procedural object without a template and otherwise counts it as exportable.

## Semantic surfaces

Generators tag their own faces, such as the floor top, the ceiling underside, wall faces, stair treads and the ramp slope. The `surface` option (`"desk"`, `"medical_surface"`, or `{tag, traits, retag, surfaces}`) tags the visible top faces of any procedural object, so props, decals and lights can be placed on it. See [SEMANTIC-SURFACES.md](SEMANTIC-SURFACES.md).

## Limits

- The export needs at least one World Builder object in scope (a light, collision or prop) for the sector to exist. Procedural collision boxes are enough.
- Importing over a template reuses its material setup. Whether a particular template imports cleanly depends on your WolvenKit version; verify the first build in game (IN-GAME-CHECK).
- Scene-scoped builds add every procedural object of the premise.
