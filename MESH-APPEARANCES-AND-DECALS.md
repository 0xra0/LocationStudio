# Mesh appearances and decals

LocationStudio v0.42.0 adds a mesh appearance picker and a World Builder decal workflow. Both use the active World Builder catalogs and serialized resource data; LocationStudio does not ship a guessed list of game materials.

## Requirements

- Cyberpunk 2077 with CET.
- World Builder / entSpawner loaded, with Spawn New initialized.
- The mesh appearance picker needs a placed, spawned **Static Mesh** object. It reads the `apps` list from that live World Builder mesh instance.
- Decal placement needs the World Builder **Decals** catalog available. The catalog supplies the `.mi` material path used by the native `worldStaticDecalNode`.

## In-game mesh appearance flow

1. Place or import a World Builder Static Mesh and spawn it through LocationStudio.
2. Open **Spatial → Meshes + Decals**.
3. Select the placed mesh and press **Load Variants**. If the resource is still loading, retry after a short delay. If the object is not spawned, spawn it first.
4. Select a listed variant to preview it on the live mesh.
5. Press **Apply Preview** to save the selected appearance into the project, or **Revert Preview** to restore the original live appearance.

Previewing only changes the live mesh component. It does not mark the project dirty or update the saved World Builder entry. Applying saves the name from the selected mesh's own `apps` list as the entry's `app` value. A game reload or respawn uses that saved value.

The UI intentionally shows no made-up fallback variants. Some meshes may have no named variants (the game's default appearance still works); in that case the picker reports the World Builder result and has nothing to select.

## Decal placement

Enter a search term from World Builder's loaded Decals catalog. LocationStudio uses the first matching catalog item, so make the search specific when it returns several results. The item must be a `.mi` decal material accepted by World Builder.

- **Place Decal at Aim** uses CET's camera ray hit when available. If the raycast misses, the existing game helper can fall back to a looked-at target or a point along the camera direction; check the `aim_source` field in the result before treating that coordinate as a confirmed surface hit.
- **Width / Height** are written to the World Builder saved scale X/Y fields, in meters.
- **Alpha** is clamped to 0–1.
- The object is saved to the selected premise/room when available and immediately sent through LocationStudio's World Builder spawn path.
- A failed runtime spawn leaves the project object saved and returns the spawn error; correct the catalog/runtime issue and retry spawning it.

The decal node's material and appearance are real World Builder data. The current UI does not orient the decal to arbitrary surface normals, offer a material thumbnail, or edit an already placed decal's alpha/flip values. Set its transform with the existing object transform tools. World Builder exports the native decal node and material reference; this feature does not package or author new `.mi` materials.

## Claude MCP examples

Use the selected LocationStudio mesh, or pass its `object_id` explicitly:

```text
mesh_appearance_list(object_id="OBJECT_ID")
mesh_appearance_preview(object_id="OBJECT_ID", appearance="damaged")
mesh_appearance_apply(object_id="OBJECT_ID", appearance="damaged")
```

To discard a preview without saving:

```text
mesh_appearance_cancel(object_id="OBJECT_ID")
```

Place a decal from the active catalog at the camera aim point:

```text
create_decal(
  resource_name="warning", name="Clinic warning decal",
  source="aim", width=1.2, height=0.8, alpha=0.9,
  premise_id="PREMISE_ID", room_id="ROOM_ID"
)
```

`create_decal` also accepts a precise `resource_path` returned by the World Builder asset search/catalog workflow. Supply `x`, `y`, and `z` together to place at explicit world coordinates. Set `spawn=false` to save the decal without attempting a live spawn.

## MCP operations

| Tool | Result |
| --- | --- |
| `mesh_appearance_list` | Names and current appearance exposed by a spawned mesh instance |
| `mesh_appearance_preview` | Validates a name against the list, then applies it live without saving |
| `mesh_appearance_apply` | Applies a listed name and stores it in the project's World Builder entry |
| `mesh_appearance_cancel` | Restores the original live appearance for an uncommitted preview |
| `create_decal` | Searches the loaded Decals catalog, saves native decal data, and optionally spawns it |

All appearance operations require a spawned static mesh. They return errors for non-mesh objects, missing live handles, unavailable appearance lists, and unlisted variant names. The Lua tests cover this contract with a mock World Builder; they do not replace an in-game CET/World Builder check.
