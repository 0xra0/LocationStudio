# Cinematic timeline editor

LocationStudio 0.66 adds cinematic timelines (project schema 19, `timelines`), available in **Spatial → Timeline** and through the `timeline_*` MCP tools. A timeline puts a location's shots, NPC blocking, dialogue timing, light/VFX/audio events and quest facts on one time axis. You preview it in game, then export a **structured scene handoff** for whoever builds the real `.scene`.

It does not replace `.scene` tooling. LocationStudio does not generate native scene resources, write quest facts, or drive the game camera independently of V.

## Tracks and keys

A timeline has a duration (0.1–3600 s), an fps value (recorded for the handoff), an optional linked premise and scene, and any number of tracks. Each track holds keys sorted by time, in seconds.

| Track | Key payload | Meaning |
| --- | --- | --- |
| `camera` | `camera_id`, `transition` `cut`/`move`, `duration` (move blend), `fov` | cut to a saved camera, or move there from the previous shot (smoothstep blend) |
| `npc` | `position {x,y,z}`, `yaw`, `anim {name, comp, ent}`, `action: stop` | NPC blocking and AMM-style workspot animations. The track binds a saved NPC population object (`target_id`) and/or a live NPC (`npc_key` from `npc_list`) |
| `look_at` | `subject_id`, `target_object_id` or `target {x,y,z}` | who looks at what |
| `dialogue` | `speaker`, `line`, `duration` (defaults from line length), `line_id` | timing markers for lines; `line_id` can carry a localization key |
| `event` | `object_id`, `action` `show`/`hide`/`toggle` | lights, VFX, audio emitters or props turning on and off |
| `fact` | `fact` (`[A-Za-z0-9_.-]`), `value` | quest facts expected at that moment |
| `marker` | `label` | beats and sync points |

Every add, edit or delete of a timeline, track or key is one undo step. Keys are checked against their track kind when added and when edited. **Mute** skips a track in the preview and in evaluation; **disabled** tracks are also left out of the export.

## Evaluate and validate

`timeline_evaluate(time)` returns the state at a given moment:
- the active camera, with its blended transform during a move;
- each NPC's latest position and current animation;
- look-ats, the dialogue being spoken, object visibility after events, the latest fact values, and the markers already passed.

`timeline_validate` reports:
- missing cameras or objects (errors);
- keys past the end;
- a speaker starting a line before their previous one ends;
- dialogue running past the end;
- a first camera key that is a move;
- animation keys on NPC tracks without a live `npc_key`;
- timelines with no shots.

## In-game preview

**PLAY** (`timeline_play`) advances the playhead every frame at 0.1–4× speed, optionally looping. It applies state as follows:
- **Camera:** V is teleported to the current shot and moved along the blend during a move. This uses the same mechanism as camera preview in the Cameras tab.
- **Events:** objects are spawned or despawned through the normal placement path. Hidden layers still refuse spawning.
- **NPCs:** animations start on the bound live NPC through Live Tools when their key is crossed, and `action: stop` ends them.
- **Facts:** these are *not* written. They appear as "would set" entries in the status.

**Seek** jumps to a time and applies that state. **Pause** keeps it applied.

**STOP & RESTORE** (`timeline_stop`) returns every object it touched to its original spawn state, stops the animations it started and teleports V back to where the preview began. Closing the overlay also stops the preview. If a restore step fails, the error is reported and kept in `last_error`.

## Scene handoff export

**EXPORT HANDOFF** (`timeline_export`) writes two files.

`exports/timeline_<name>.json` uses the schema `locationstudio-timeline-handoff/1` and contains:
- the timeline header and the full tracks;
- a chronological cue list with each cue's track kind;
- a **shot list** (start, end, length, transition and blend per camera);
- the **dialogue script** and the **quest facts**;
- **resolved references**: camera transforms, look-at and FOV; object names, resources, layers and NodeRefs; NPC records, appearances and transforms;
- the validation result.

`exports/timeline_<name>_dialogue.csv` is a cue sheet (`time_s,duration_s,speaker,line_id,line`) for VO and localization.

Use the handoff to build the `.scene` in WolvenKit (or another scene tool) and to wire facts in Quest Forge. Timings are seconds from the start of the timeline.
