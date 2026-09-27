# Device Logic Graphs

LocationStudio v0.53 adds a persistent node/link authoring panel at **Spatial Editor → Device Logic**. It authors `terminal`, `door`, `elevator`, `switch`, `camera`, `security_system`, `fact`, and `action` nodes. Links carry an event/trigger, an optional quest-fact condition and value, ordering, and an optional native operation label.

Graphs are saved in the project, included in Quest Forge handoff, and carried into the Build Mod native-resource manifest. The panel can bind device nodes to placed objects and enter World Builder device hashes, class names, persistent-state entry keys, instance-data references, and world nodeRefs.

## MCP tools

- `device_logic_graph_create(name, premise_id="")`
- `device_logic_graph_list()`
- `device_logic_graph_delete(graph_id)`
- `device_logic_node_add(graph_id, kind, name, object_id="", config={}, native={})`
- `device_logic_node_update(graph_id, node_id, patch={...})`
- `device_logic_node_delete(graph_id, node_id)` — removes attached graph links too.
- `device_logic_link_add(graph_id, from_id, to_id, trigger="activate", condition_fact="", condition_value=1, native_operation="")`
- `device_logic_link_delete(graph_id, link_id)`
- `device_logic_validate(graph_id="")`
- `wb_device_logic_apply(export_file, graph_id)`

Fact node example:

```text
device_logic_node_add(graph_id="logic-id", kind="fact", name="Door unlocked", config={"fact_name":"clinic.entry_unlocked", "value":1})
```

Action node example:

```text
device_logic_node_add(graph_id="logic-id", kind="action", name="Unlock entrance", config={"operation":"unlock", "target":"door-node-id"})
```

Accepted action labels are `set_fact`, `unlock`, `lock`, `enable`, `disable`, `alarm`, `set_camera_state`, `elevator_floor`, `emit_event`, and `custom`. Fact names allow letters, digits, underscores, and dots. These are validated design semantics; the graph editor does not execute them in REDengine.

## Native World Builder link application

`wb_device_logic_apply` validates the entire graph before writing. It can add missing device records, persistent-state entries, and `worldDeviceNode` sector nodes **when the graph includes complete typed payloads copied from a compatible World Builder preset/export**. For example, a device node's `native` binding can contain `device_record` (`hash`, `className`, `nodePosition`, `children`, `parents`), `ps_entry` (`PSID`, `instanceData`), `sector_name`, and the full typed `world_node` record. Existing resource IDs are never overwritten. It then applies reciprocal device `children`/`parents` links atomically and validates elevator-to-floor-terminal classes/order. If any resource payload is absent or invalid, it returns blockers and leaves the export unchanged.

Use `device_logic_node_update` to attach an exact resource bundle to the graph node before applying it. The nested fields below are structural examples; the `instanceData` and `world_node.data` values must be copied from a compatible, working World Builder device preset/export for the actual device class. Placeholder tables are not buildable game resources.

```text
device_logic_node_update(graph_id="logic-id", node_id="door-node-id", patch={"native": {
  "device_hash":"unique-world-device-hash", "device_class":"DoorControllerPS",
  "ps_entry_hash":"unique-ps-entry-key", "instance_data_ref":"verified-preset-name",
  "node_ref":"$/locationstudio/#clinic_door", "sector_name":"clinic_sector",
  "device_record":{"hash":"unique-world-device-hash","className":"DoorControllerPS",
    "nodePosition":{"x":100,"y":200,"z":5},"children":[],"parents":[]},
  "ps_entry":{"PSID":"unique-persistent-state-id","instanceData":{"...":"copy exact typed WB payload"}},
  "world_node":{"name":"Clinic Door","type":"worldDeviceNode","nodeRef":"$/locationstudio/#clinic_door",
    "position":{"x":100,"y":200,"z":5},"rotation":{"i":0,"j":0,"k":0,"r":1},
    "scale":{"x":1,"y":1,"z":1},"data":{"...":"copy exact typed WB node data"}}
}})
wb_device_logic_apply(export_file="my_export.json", graph_id="logic-id")
```

Build Mod compiles the resulting typed `devices` and `psEntries` into `.devices` and `.psrep` CR2W resource files. The editor does not invent class-specific `instanceData`; users must supply payloads from compatible World Builder device presets/exports. The generated manifest audits resource presence, class, nodeRef, reciprocal wires, and handoff-only fact/action edges; a clean manifest is necessary but does not prove the device works in-game.

`wb_device_connect` and `wb_elevator_wire` remain useful for small direct edits. `wb_device_logic_apply` applies all device-to-device wires from a saved graph in one validation-first operation. Semantic fact/action edges remain in the handoff graph until mapped to a tested native controller/quest resource.
