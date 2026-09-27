# LocationStudio Lighting

LocationStudio creates World Builder **Static Light** nodes (`worldStaticLightNode`) using the Static Light class and catalog exposed by World Builder. These are real game light components in the live preview, not lamp meshes or drawn markers. World Builder must be installed, loaded, and its Spawn New catalog initialized. Static lights are World Builder resources, so ordinary CET entity spawning is not used.

## In game

1. Open LocationStudio and choose **Spatial → Lighting**.
2. Choose a built-in preset and click **PLACE AT AIM** or **PLACE AT PLAYER**.
3. Select the light in the list. Tune color, intensity, radius and flicker, then click **APPLY SETTINGS + RESPAWN**. The node is removed and respawned with the updated World Builder data.
4. Use **APPLY PRESET** to set the selected light to another preset.
5. Preview a time from 00:00 to 23:59. LocationStudio records the current game-clock seconds on the first preview; **RESTORE PREVIEW TIME** returns to that time. Repeated previews retain the original time until restored.

Presets: Warm tungsten, Cool office, Neon cyan, Neon magenta, Emergency red flicker, and Soft fill. RGB uses normalized 0–1 channels. Intensity and radius use World Builder light units; flicker strength is 0–1 and flicker period/offset are seconds accepted by its light component.

## MCP examples

```json
{"tool":"create_static_light","arguments":{"name":"Clinic work light","source":"aim","preset_id":"cool"}}
{"tool":"update_static_light","arguments":{"object_id":"<light id>","color":[0.15,0.85,1.0],"intensity":220,"radius":14,"flicker_strength":0.08,"flicker_period":0.18}}
{"tool":"preview_time_of_day","arguments":{"hour":22,"minute":15}}
{"tool":"restore_time_of_day","arguments":{}}
```

MCP changes use the same saved project and live World Builder node as the in-game editor. `update_static_light` updates a live node by removing and respawning it; a failed respawn is returned as a warning and logged.

## Time preview scope

For saved time + weather + fog conditions, use the Environment tab ([ENVIRONMENT-PREVIEW.md](ENVIRONMENT-PREVIEW.md)); this time preview is refused while an environment preview is active.


Time preview changes Cyberpunk's game clock through CET's `Game.GetTimeSystem()` / `SetGameTimeByHMS`. It does not change weather, cloud cover, exposure, or the sun independently. Another mod that writes the game clock at the same time can override this preview. The restore value is in memory for the current LocationStudio session and is cleared after a successful restore.

## Requirements and limits

- Live light creation and tuning require a compatible World Builder / entSpawner with its Static Light class and catalog ready. If that backend is absent or its catalog is not initialized, the create call returns a clear error and does not create a fake light.
- A preview light is a live World Builder node. Its saved LocationStudio object and configuration survive project saves, but the light is not automatically baked into a distributable `worldStreamingSector`; use World Builder's native build/export workflow for a game mod.
- CET in-game execution was not available during this build. The automated runtime fixture verifies LocationStudio's catalog lookup, Static Light data serialization, live-node respawn request, and clock-preview/restore control flow; verify actual rendering in game after installing.

## References

- [CDPR modding documentation: World Builder supported nodes](https://github.com/CDPR-Modding-Documentation/Cyberpunk-Modding-Docs/blob/main/modding-guides/world-editing/object-spawner/supported-nodes.md) describes Static Light nodes and their color, intensity, radius and flicker settings.
- [World Builder Static Light implementation](https://github.com/justarandomguyintheinternet/CP77_entSpawner/blob/5b2f924ebdf4460e72a55490cb53d4d833c94947/modules/classes/spawn/light/light.lua) shows `worldStaticLightNode`, the live light component configuration and serialized light fields.
- [CET game time API](https://wiki.redmodding.org/scripting-cyberpunk/cyber-engine-tweaks/cet-functions/misc/getters-functions) documents `GetSingleton("gameTimeSystem")`, `SetGameTimeByHMS`, and game-time restoration; LocationStudio uses the current `Game.GetTimeSystem()` accessor and restores through the returned `GameTime` value.
