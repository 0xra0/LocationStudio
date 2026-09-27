# Material resources

The material library describes material instances in code. Build Mod turns each one into a real `CMaterialInstance` (`.mi`) resource, shipped with the mod, for generated meshes to use.

A definition picks:

- a base material;
- textures;
- roughness, metallic, emissive parameters, tint, tiling and UV scale;
- raw parameter overrides;
- named variants.

Each variant becomes its own `.mi`, chained on the parent, and an extra appearance on every generated mesh that uses the material.

Open it at **Spatial → Materials**. It is also available through the MCP tools `material_*`, the authoring-plan v2 op `create_material`, and EDL `materials.library`.

## Definition

```json
{
  "key": "clinic_tile",
  "preset": "metal_base",
  "params": {"roughness": 0.6, "metallic": 0, "tint": [0.9, 0.95, 1, 1],
             "emissive_color": [0, 0.8, 1], "emissive_ev": 4,
             "uv_scale": [2, 2], "tiling": [1, 1]},
  "textures": {"base_color": {"solid": [0.8, 0.82, 0.85, 1]},
               "normal": "base\\...\\tiles_n.xbm",
               "roughness": {"file": "C:/textures/tiles_r.png"}},
  "overrides": {"SomeParameter": {"type": "Float", "value": 0.2}},
  "variants": [{"name": "dirty", "params": {"roughness": 0.85, "tint": [0.7, 0.68, 0.62, 1]}},
               {"name": "red", "textures": {"base_color": {"solid": [0.7, 0.1, 0.1, 1]}}}]
}
```

### Top-level fields

| Field | Meaning |
| --- | --- |
| `key` | Identifier. Geometry refers to the material as `@key`, or `@key:variant` to pin one variant. |
| `preset` | `metal_base` (PBR, default), `glass`, `multilayered` or `custom`. |
| `base` | Base material: any `.mt`, `.remt` or `.mi`. It defaults to the preset's, and a `base` without a preset means `custom`. Take it from the asset catalog. |
| `path` | Output `.mi` path. The default is `<root>\<key>.mi`, and the root is set with `material_settings` (default `mod\locationstudio\materials`). Variants are written to `<path>_<name>.mi`. |

### Presets

| Preset | Textures | Parameters |
| --- | --- | --- |
| `metal_base` | `base_color`, `normal`, `roughness`, `metalness`, `emissive`, `mask` | `tint`, `roughness`, `metallic`, `roughness_scale`, `metallic_scale`, `normal_strength`, `emissive_color`, `emissive_ev`, `alpha_threshold` |
| `glass` | `normal`, `mask` | `tint`, `roughness`, `ior`, `opacity`, `normal_strength` |
| `multilayered` | `mlsetup`, `mlmask`, `normal` | none |
| `custom` | none | `overrides` only |

On `metal_base`, a scalar `roughness` or `metallic` given without its texture also zeroes the texture scale. The value is then used as a constant.

### Tiling and UV scale

`uv_scale` is metres per texture repeat and `tiling` is repeats. Both are baked into the UVs of the generated mesh, so they work with every base material. Because the mesh is shared by all appearances, they cannot change per variant.

### Textures

Each texture is one of:

- a depot `.xbm` path (`.mlsetup` or `.mlmask` for multilayered);
- `{"file": "<local .png/.tga/.dds/.jpg>"}`;
- `{"solid": [r,g,b,a], "size": 4}` for a generated solid-colour PNG.

Build Mod imports images to `.xbm` with the WolvenKit CLI. The default path is `<material folder>\textures\<key>[_<variant>]_<texture>.xbm`, and `path` overrides it.

### Overrides

Overrides set raw parameters: `{name: {type, value}}` with the type `Float`, `Int32`, `Bool`, `Color`, `Vector4`, `texture`, `mlsetup`, `mlmask` or `CName`.

### Variants

- A variant only lists what changes: `params`, `textures` or `overrides`.
- Its `.mi` uses the parent `.mi` as its base material and stores only the values that differ.
- Variants that geometry uses cannot be removed.

## Using materials

| Where | How |
| --- | --- |
| Procedural objects | `materials: {main: "@clinic_tile", glass: "@glass"}`, or `material_assign`, or the UI **ASSIGN** buttons. |
| Parametric rooms | `materials: {walls: "@clinic_tile", floor: "@floor:worn", frame: "@steel", glass: "@glass"}`. |
| EDL | `materials: {library: [...]}` defines materials, and `material: "@key"` or `parametric.materials` references them. |

When a mesh references an unqualified `@key`, it gets:

- a `default` appearance;
- one appearance per variant.

The object's `material.appearance` selects which one the world node shows, for example `dirty`. `@key:variant` pins a single look instead.

Unknown references are refused when they are assigned. Preflight reports them, and Build Mod stops on them.

## Build Mod

The **materials** stage runs before the procedural meshes:

1. It writes every material used in scope as CR2W-JSON (`source/raw/<path>.json`).
2. The WolvenKit worker writes the binary `.mi` (`source/archive`).
3. The WolvenKit CLI imports generated and local textures to `.xbm`.
4. The meshes reference the `.mi` files and get their appearances.

The dependency resolver sees the generated files as shipped (`generated` offline, `project` in a build) and still follows their base materials and textures, so a missing modded texture is still reported.

`material_build` runs the same generation offline into `exports/materials` (add `write_cr2w=true` for binaries). `material_inspect` decodes any `.mi` JSON, or lists the parameters of a base-material JSON.

## Parameter verification

The parameter names for the presets are built-in and **unverified**. Each result reports a `profile_source`:

| `profile_source` | Meaning |
| --- | --- |
| `base-json` | A WolvenKit JSON export of the base material (for example `mod_sources/base/materials/metal_base.remt.json`) is in the mod sources. Every parameter name and type is checked against its `parameterName` list, and a mismatch stops the build. |
| `reference-mi` | A reference vanilla `.mi` export with the same base (`LOCATION_STUDIO_REFERENCE_MI_JSON` or `mod_sources/reference.mi.json`) uses every name. |
| `builtin-unverified` | Otherwise. The build warns. |

A reference `.mi` also supplies the exact value layout.

## Limits

- The live preview does not show materials; they are only visible in game after a successful Build Mod.
- Texture import uses the WolvenKit CLI with default settings. Set `LOCATION_STUDIO_TEXTURE_IMPORT_CMD` (a JSON list with `{cli}`, `{image}`, `{xbm}` and `{raw_dir}`) if your WolvenKit version needs other arguments.
- Check every generated material in game.
