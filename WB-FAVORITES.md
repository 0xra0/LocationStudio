# World Builder Favorites through MCP

LocationStudio v0.26.0 exposes two MCP tools that read and write World Builder's
native Favorites categories under `entSpawner/data/favorite/`.

## List saved favorites

`wb_favorites_list(category_filter="")` is read-only. It returns category names,
source filenames, favorite names/tags, the spawn class and resource path. A
filter matches category names. Malformed category JSON is reported under
`warnings`; it is never deleted or repaired automatically.

## Add a favorite (preview first)

`wb_favorite_add(catalog_id, category="LocationStudio", name="", tags=[], write=false)`
uses the offline asset-catalog ID only to identify a candidate. It then asks the
live World Builder 1.0.81 resource catalog to resolve the exact category,
variant and resource path and to serialize that loaded spawn class' default
data. It does not spawn anything in the world or import an asset into the
LocationStudio project.

The default `write=false` returns a preview. Review the category, favorite name
and resource path; repeat with the same arguments and `write=true` to commit.
An existing favorite with the same live spawn class and resource path is
idempotent and is not duplicated.

```text
asset_catalog_search(query="metal chair", category="Mesh", variant="Mesh")
wb_favorite_add(catalog_id="12345", category="Props", name="Clinic chair", tags=["clinic"])
wb_favorite_add(catalog_id="12345", category="Props", name="Clinic chair", tags=["clinic"], write=true)
wb_favorites_list(category_filter="Props")
```

## Safety and refresh behavior

- Writes are off unless `write=true` is explicitly supplied.
- Existing category JSON is backed up beside the original with a UTC timestamp
  before it is atomically replaced.
- Existing category keys and fields unknown to LocationStudio are retained.
- New categories use a timestamped filename. Ambiguous duplicate category names
  are rejected rather than guessing which World Builder file to edit.
- Adding favorites requires the CET bridge to be live and the selected catalog
  entry to exist in World Builder's currently loaded resource list.
- World Builder reads Favorites into memory during initialization. After a
  successful disk write, reload World Builder/CET or restart the game before
  expecting the entry in its UI. `wb_favorites_list` reads the file immediately.
- The tool writes the installed World Builder favorites JSON, not
  LocationStudio's separate Project Asset favorite flag.

If World Builder is installed somewhere other than the normal sibling mod
folder `.../mods/entSpawner` or `.../mods/WorldBuilder`,
`wb_favorites_list` reports the missing directory; the tool does not search
arbitrary disks or write to a user-supplied path. If both known directories
exist, it refuses to guess which installation is active.
