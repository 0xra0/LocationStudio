# NPC Patrol and AI Route Editor

LocationStudio's Spatial panel now contains **Patrol & AI routes**. A route is linked to one saved NPC population point by object ID, so the route remains attached to that NPC when you move it or update its profile.

## In game

1. Create and save a persistent NPC in **Spatial → NPC population**.
2. Open **Spatial → Patrol & AI routes**, select the NPC population point, then create a route.
3. Choose the **patrol**, **alert**, or **combat** waypoint sequence and set the loop option.
4. Add waypoints at V or at the aim hit. Select a waypoint to edit its name, world XYZ/rotation, wait time, facing yaw, movement-speed multiplier, transition, and optional fact branch. Reorder with the up/down controls.
5. A workspot transition must point to a saved LocationStudio NPC workspot. Branch targets must name another waypoint in the same variant and include a quest fact and value.
6. Export Quest Forge to get `npc_ai_routes`, including the NPC object ID and `Character.*` record, each route variant, ordered waypoint coordinates, loop edges, and branch/workspot metadata.

## MCP examples

`npc_id` is the LocationStudio object ID returned when the population point was created. Explicit coordinates are optional; without them the tool captures the player position or current aim point.

```json
{"tool":"npc_route_create","arguments":{"npc_id":"NPC_OBJECT_ID","name":"Clinic patrol","loop":true}}
{"tool":"npc_route_add_waypoint","arguments":{"route_id":"ROUTE_ID","variant":"patrol","name":"South entrance","x":-1908,"y":-2469.5,"z":12,"yaw":45,"wait_seconds":2,"facing_yaw":90,"speed":0.8}}
{"tool":"npc_route_add_waypoint","arguments":{"route_id":"ROUTE_ID","variant":"alert","name":"Alarm position","x":-1904,"y":-2465,"z":12,"wait_seconds":0,"speed":1.2}}
{"tool":"npc_route_list","arguments":{"npc_id":"NPC_OBJECT_ID"}}
{"tool":"npc_route_move_waypoint","arguments":{"route_id":"ROUTE_ID","waypoint_id":"WAYPOINT_ID","delta":-1,"variant":"patrol"}}
```

Other tools: `npc_route_update_waypoint`, `npc_route_delete_waypoint`, `npc_route_update`, and `npc_route_delete`.

## Data and runtime limits

Waypoint data is editable, undoable project data. Quest Forge exports patrol, alert, and combat sequences separately and validates NPC and workspot references plus fact-branch targets. Default sequence edges follow waypoint order; the final waypoint links back to the first when looping is enabled. A conditional branch is an additional edge.

The route plan currently has **handoff-only** runtime status. It does not move a live NPC between waypoints, assign navmesh paths, execute wait timers, react to alert/combat facts, or run workspot transitions. World Builder has native AI Spot and Community node types, but a generic `worldPopulationSpawnerNode` does not automatically consume these route plans. LocationStudio does not claim to generate that native community/AI wiring yet. The exported route schema is the explicit bridge for a compatible quest/community resource build pipeline.
