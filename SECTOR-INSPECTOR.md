# Streaming-sector inspector

To divide a generated environment into sectors in the first place, see the [sector partitioner](SECTOR-PARTITIONER.md).

LocationStudio 0.61 inspects the streaming sectors in a World Builder export (`*_exported.json`), before or after it is built into a mod. For every exported node it reports:

- the sector it belongs to, and the sector's variant range;
- its NodeRef, position and streaming reference point, and its primary/secondary streaming ranges;
- the device record and persistent-state ID (PSID) placed at the node, if any;
- the NodeRefs its data references;
- the LocationStudio object it came from, matched by position (0.1 m) and name, when the saved project is available.

Per sector it shows the name, bounds (`min`/`max`), category, level, variant count, node types, and NodeRef/device/persistent-entry counts.

## Flags

| Code | Severity | Meaning |
| --- | --- | --- |
| `outside_sector_inside_other` | error | The node is outside its sector box (0.5 m tolerance) and inside another sector's box. It is **likely in the wrong sector**; `suggested_sector` names the containing one. |
| `sector_outlier` | warning | The node is far from the rest of its sector: more than max(50 m, 3 × the sector's 90th-percentile spread) from the sector's node centroid. `suggested_sector` is the sector whose content is nearest. Also counted as likely wrong sector. |
| `outside_sector_bounds` | warning | Outside its sector box and inside no other sector. |
| `streaming_ref_outside_sector` | warning | The node's streaming reference point is outside its sector box. |
| `beyond_streaming_range` | info | The node is further from its sector centroid than its own secondary streaming range. |
| `missing_position` | error | The node has no valid position. |
| `duplicate_psid` | error | Several persistent-state entries share a PSID. |
| `device_without_node` | warning | A device record's `nodePosition` matches no single exported node, so its sector is unknown. |

Cross-sector references are listed separately:
- `node_ref` references to a NodeRef defined in another sector (`cross_sector`), or not defined in this export (`external_or_missing`, for example a vanilla NodeRef);
- `device_link` parent/child links between devices in different sectors (`cross_sector`), or to a device missing from `devices` (`missing_device`).

A cross-sector reference is valid when both sectors stream together; it is listed so you can confirm that. The report also lists premises whose objects ended up in more than one sector.

The inspector is read-only and never changes the export. The flags are heuristics that point at likely mistakes; they don't prove how REDengine will stream the sector.

## Using it

- **MCP:**
  - `sector_inspect(export_file, sector?, include_nodes?, write_report=true, flags_limit=200)`: `export_file` is an export name such as `clinic` or a path to the JSON file.
  - `sector_node(export_file, node_ref | name | object_id)`: shows one node's sector, variant, device/PSID, references and flags.
- **Build Mod:** `build_mod_from_project` runs an advisory `sectors` stage after preparing the workspace. It writes `automation/sector-inspection.json` in the workspace and never blocks the build.
- **In game:** **Spatial → Sectors** reads the latest report from `exports/sector-inspection.json`, which both of the above write. It shows the sectors and their bounds, filters flags by sector and severity, lists cross-sector references, and has **SELECT** buttons that select the LocationStudio object behind a flag (and focus it in World Builder when it is live). CET cannot read World Builder's own export folder, so run the MCP inspection first.
