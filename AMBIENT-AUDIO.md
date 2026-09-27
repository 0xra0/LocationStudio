# Ambient audio in LocationStudio 0.43

LocationStudio authors two World Builder object types from World Builder's loaded catalogs:

- A **Static Audio Emitter** (`worldStaticSoundEmitterNode`) places a sound event at a point. Its emitter radius and World Builder options are stored with the object.
- An **Ambient Area** (`worldAmbientAreaNode`) describes a room soundstage/reverb zone. LocationStudio derives four outline points from the selected room's rotated rectangular footprint and stores them as World Builder Outline Marker objects.

This feature needs Cyber Engine Tweaks, LocationStudio, and a running World Builder 1.0.81 session with the relevant Spawn New catalogs initialized. It does not copy or invent an audio-event database.

## In game

1. Create or select a room in Premises Builder. Check its position, yaw, width, depth and height first.
2. Open **Spatial → Ambient Audio**.
3. For a point sound, search the loaded catalog (the default search is `amb_`), select an exact row, set the radius, then place at the camera aim point or player.
4. For reverb, keep that room selected, enter the intended reverb CName, then create the zone. The saved zone and four marker objects can be moved through the normal hierarchy/transform tools.
5. Save the project. Spawn the zone's World Builder objects, then use **Build → World Builder Export** with all four outline points and the ambient area in scope. Export stops with an error if anything other than all four live outline marker objects are present.
6. Use World Builder's native export/build pipeline to put the area into a native world edit. The area modifies the soundstage after that build; it is not an audible CET preview.

The known default from World Builder's Interior Muffling Area preset is `revb_interior_room_medium`. The optional active event field is stored in `EventsOnActive`. Use names exposed by the installed game/World Builder data for project-specific sound and reverb choices.

## Claude MCP examples

```text
Search the Spatial → Ambient Audio catalog for amb_int_roomtone_office.
Use the exact returned resource path to create an emitter named Clinic aircon,
placed at the aim point, radius 7.5 m, assigned to the selected room.
```

```text
Create a reverb zone for room_id ROOM_ID using
revb_interior_room_medium, priority 16, outer distance 10 m and vertical distance 1 m.
Then save and export the whole room's World Builder objects as clinic_interior.
```

Equivalent tools:

- `create_audio_emitter(resource_path?, query?, name?, source?, radius?, emitter_metadata_name?, room_id?, premise_id?, x?, y?, z?, yaw?, spawn?)`
- `create_room_reverb_zone(room_id, name?, reverb?, sound_event?, priority?, outer_distance?, vertical_outer_distance?, width?, depth?, height?, spawn?)`

If a sound path is supplied it must exist in the currently loaded Audio Emitters catalog. Without a path, `query` chooses the first matching result, so search and pass the exact path for reliable MCP use. Coordinates must be supplied as `x`, `y`, and `z` together. The room zone accepts optional dimensions in metres and otherwise uses the selected room footprint.

## Runtime limits

World Builder data is authoritative. A successful LocationStudio placement means the catalog entry was accepted and the runtime spawn call succeeded; it does not guarantee that REDengine will make every sound event audible in the current scene. Some audio events require particular game states or native world context. The upstream World Builder sound emitter editor similarly notes that not all audio paths are audible as loose emitters. Reverb and room soundstage behavior must be checked after native world-edit export in game.

The UI does not synthesize `.wem`/`.opus` audio, invent reverb buses, cook native world sectors, or modify quest state. If an emitter is silent, capture the LocationStudio debug log and include its exact resource path and in-game location.
