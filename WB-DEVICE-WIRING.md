# World Builder device and elevator wiring

LocationStudio v0.29 adds two MCP tools that edit the `devices` graph in an
existing World Builder `*_exported.json` file. They update the same `children`
and `parents` arrays that LocationStudio's build exporter writes into the
REDengine device resource. The file is changed in place; make a copy before
using these operations if you need to preserve a particular export revision.

## `wb_device_connect`

Connect a source device to a target by their keys in the export's `devices`
object. The operation validates both records, adds `target` to
`source.children`, adds `source` to `target.parents`, and is safe to repeat.

```json
{
  "export_file": "my_location",
  "source_hash": "123456789",
  "target_hash": "987654321"
}
```

Pass either the export name (resolved under World Builder's `export` folder) or
the full path to its JSON file. `source_hash` and `target_hash` are device map
keys, not NodeRefs.

## `wb_elevator_wire`

Wire a lift device to at least two floor-terminal device records. It checks the
class names (`LiftControllerPS` and `ElevatorFloorTerminalControllerPS`) before
writing, makes each link reciprocal, and puts terminal hashes in the supplied
order in the lift's `children` array. Supply floors from lowest to highest.

```json
{
  "export_file": "my_location",
  "elevator_hash": "123456789",
  "floor_terminal_hashes": ["200001", "200002", "200003"]
}
```

## Elevator setup still required in World Builder

This tool writes the exported device-resource graph only. It does not generate
or infer NodeRefs, create elevator terminals or static markers, or edit
entity-instance persistent state. In World Builder, each floor terminal still
needs a unique NodeRef, persistent state enabled, its `floorMarker` NodeRef and
display name configured; each floor also needs a unique static marker NodeRef.
Set marker primary and secondary ranges above the lift's ranges. Add any door
connections separately. Then export, import/build through WolvenKit and test in
a fresh save. World Builder preview alone does not make a custom elevator
functional.

## Verify after editing

Run `build_export_inspect` on the same export and check for duplicate NodeRefs
or other validation errors. These graph tools do not prove that a game runtime
will activate the elevator; final behavior depends on the authored NodeRefs,
instance data, compiled resources and game-side testing.
