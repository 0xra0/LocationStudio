# Project browser MCP tools

The project browser is read-only and returns saved LocationStudio data. It
supports the canonical item types `project`, `location`, `route`, `premise`,
`room`, `object`, `group`, `prefab`, `volume`, `camera`, `scene`, `asset`, and
`layer`.

## Find

`wb_find(query, types=[], limit=50, offset=0)` searches IDs, names, tags, notes,
templates, categories, and nested resource metadata. Search is case-insensitive
substring matching. Results include match fields and a relevance score; use the
returned `total`, `offset`, and `has_more` values to paginate.

```json
{"query":"clinic","types":["premise","room","object"],"limit":25,"offset":0}
```

## Tree

`wb_tree(root_id="", max_depth=2, limit=250)` returns a bounded project outline.
The default root has collection nodes. Use `root_id="collection:premise"` to
browse one collection, then pass a premise, room, or group ID to expand its
children. Scene and route nodes include their referenced items. `max_depth` is
1–8; `limit` is 1–1000. Children omitted due to the limit are marked truncated.

```json
{"root_id":"collection:premise","max_depth":4,"limit":250}
```

## Get

`wb_get(item_id, item_type="")` returns one item's summary and full saved
record. An optional `item_type` disambiguates the ID. Example:

```json
{"item_id":"room-123","item_type":"room"}
```

## References

`wb_refs(item_id, direction="both", item_type="", limit=200)` returns known
direct links. Direction may be `inbound`, `outbound`, or `both`. Current links
include premise/room containment, room shell objects, group parents and
membership, prefab source groups, route locations, camera look-at locations,
and scene membership. Dangling outbound IDs are returned with `missing=true`.
The tool reports explicit model relationships; it does not infer links from
free-form notes or arbitrary metadata.

```json
{"item_id":"location-123","direction":"inbound","limit":100}
```
