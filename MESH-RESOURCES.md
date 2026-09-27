# Native mesh resources

LocationStudio 0.73 turns [procedural geometry](PROCEDURAL-GEOMETRY.md) into **native Cyberpunk mesh resources**. It no longer needs an existing mesh to import over. The generated architecture is packed into the mod as real `.mesh` game assets.

## What is generated

`lsbuild/meshres.py` builds a complete `CMesh` document in WolvenKit's CR2W-JSON form. The WolvenKit worker (the same one Build Mod already uses for sectors) writes it as a binary `.mesh`. The document contains:

| Part | Content |
| --- | --- |
| Render chunks (submeshes) | one per material slot (`main`, `glass`), split at 65 535 vertices; `materialId`, `numVertices`, `numIndices`, `lodMask`, vertex factory and render masks |
| Vertex buffer | per chunk and stream, 16-byte aligned, in the chunk's vertex layout: quantized positions (`quantizationScale`/`quantizationOffset` from the bounds), packed normals and tangents (with handedness from the UVs), UV0/UV1, and white vertex colour; other static usages are zero-filled |
| Index buffer | 16-bit (`IBCT_Uint16`) after the vertex data (`indexBufferOffset`, 16-byte aligned), one range per chunk (`teOffset`) |
| Bounds | `boundingBox` and `surfaceAreaPerAxis` |
| LOD metadata | `lodLevelInfo` (LOD 0 plus optional `lod_distances`) and chunk LOD masks; every chunk is LOD 0 |
| Materials | `materialEntries` per slot, `externalMaterials` pointing at your `.mi`/`.mt` depot paths, and one appearance (`chunkMaterials`) |

Skinned layouts are refused; these are static meshes.

## Vertex layout: use a reference mesh

The game is strict about vertex layouts. Give LocationStudio one **reference static mesh** exported to JSON with WolvenKit (*Convert to JSON* on any vanilla static `.mesh`). Save it as `mod_sources/reference_static.mesh.json`, set `LOCATION_STUDIO_REFERENCE_MESH_JSON`, or pass `reference_json`.

LocationStudio copies from the reference:
- the first chunk's vertex layout (element types, usages, streams and padded strides);
- the chunk's vertex factory and render masks;
- the blob header constants (version, data processing);
- the other CMesh fields.

It then encodes the generated vertices exactly in that layout (`layout_source: reference`). `mesh_resource_inspect` shows any mesh JSON's layout, so you can check a reference before using it.

Without a reference, a built-in static-mesh layout is used (`layout_source: builtin-unverified`) and every result carries a warning. Treat those meshes as untested until you have seen them in game.

## Using it

- **Materials.** Give a procedural object `materials: {main: <.mi>, glass: <.mi>}`: `procedural_create(materials=…)`, the Geometry tab's *Material .mi* field, or EDL `material: {materials: {...}}`. Such objects use the native backend. The preflight requires `materials.glass` when the geometry has glass, and the dependency resolver follows the `.mi` paths. Objects that only have `material.template` keep the WolvenKit import backend from 0.72.
- **Build Mod.** The `procedural` stage writes `source/raw/<mesh>.mesh.json` and has the worker write `source/archive/<mesh>.mesh`, which Build Mod packs into the archive, then places the node in the sector. It stops, naming the object, if the worker is not ready, a slot has no material, or the worker does not write a CR2W file.
- **Offline.** `mesh_resource_build` writes the documents (and, with `write_cr2w=true`, the binary meshes) for saved procedural objects, with optional `materials` and `lod_distances` overrides. `mesh_resource_inspect(path, vertices=true)` decodes a document back into chunks, layouts, positions, normals, tangents, UVs and indices.

## Limits

- Every chunk is LOD 0. `lod_distances` records LOD distances, but no simplified LOD geometry is generated; the pieces are already low-poly.
- No embedded physics: use the generated collision boxes.
- Automated tests prove the buffers round-trip against the layout; only the game proves the result renders. Follow IN-GAME-CHECK the first time you use a new reference mesh.
