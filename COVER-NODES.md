# Cover Nodes

The **Cover nodes** tab in Spatial Editor stores authored cover positions inside a premise. A node has a world transform (including facing yaw), crouch or standing posture, a low/medium/high exposure label, preferred spacing, and source/confidence metadata. Nodes also appear in the scene list and can be selected/transformed there.

## Place and edit

1. Select a premise in Premises Builder.
2. Open **Spatial Editor → Cover nodes**.
3. Set posture, exposure and spacing, then use **Place at player** or **Place at aim**.
4. Select the node in the Cover nodes tab or scene view. Edit its position and facing yaw, then save. The cover direction is stored as the transform's world yaw.
5. To see points in the game world, configure the existing in-world marker `.ent` in **In-world markers**, enable markers, and refresh them. Markers are temporary visual helpers; the cover-node data itself is saved in the project.

## Find candidate positions

Set a scan radius and direction count, stand near the area, then press **Scan around player**. The scanner sends paired horizontal rays at low and upper body height using the `Static` and `Dynamic` collision groups. It keeps points where both rays meet a nearby surface, offsets each point slightly toward the open side, and filters candidates by spacing. **Add scan candidates to project** saves the returned candidates. Existing nearby cover nodes are skipped.

The scan is deliberately a geometric estimate. Collision hits can come from walls, props, or other dynamic objects; a pair of hits does not prove that a character can use the position or that the object blocks AI vision. Exposure is an authoring label and is not inferred by this scanner. Review candidate placement, facing, posture, spacing and exposure in game, then run walkability checks where useful.

## MCP

```python
cover_node_create(premise_id="premise-id", name="Desk cover",
                  cover_type="crouch", exposure="medium", spacing=1.5,
                  source="aim")
cover_node_list(premise_id="premise-id")
cover_node_update(node_id="cover-id", patch={
    "cover_type": "standing", "exposure": "low", "spacing": 2.0,
    "transform": {"position": {"x": 1, "y": 2, "z": 3},
                  "rotation": {"yaw": 90}},
})
cover_scan(radius=8, samples=24, spacing=1.5,
           premise_id="premise-id", save_to_project=True)
cover_node_delete(node_id="cover-id")
```

`cover_scan` without `save_to_project` returns candidates without changing the project. Use all three center coordinates or omit them to scan around V. A saved scan requires a valid premise ID.

## Interchange boundary

Project JSON and Quest Forge handoff include cover nodes, facing, posture, exposure, spacing, and source/confidence. LocationStudio does not generate native REDengine AI cover records or guarantee combat AI uses these points. In-world marker placement visualizes positions only. See [WALKABILITY.md](WALKABILITY.md) and [NPC-AI-ROUTES.md](NPC-AI-ROUTES.md) for adjacent spatial checks and route authoring.
