# Environment and weather preview

LocationStudio 0.58 saves named **authoring environments** in the project (`environments`, project schema 17) and applies them live. An environment can set:

| Part | How it is applied | Restored by |
| --- | --- | --- |
| Time (hour:minute) | CET game-time system `SetGameTimeByHMS` | the exact game time recorded before the first preview |
| Weather | game WeatherSystem `SetWeather(state, blend, priority)` | `ResetWeather`, which returns weather to the game's normal cycle |
| Rain | follows the chosen weather state (for example `24h_weather_rain`, `q302_light_rain`, `24h_weather_toxic_rain`) | weather reset |
| Fog | an optional transient World Builder **Fog Volume** (`worldStaticFogVolumeNode`) with size, density factor/falloff, absorption, blend falloff and color, anchored to the player, camera or premise | removed on restore |
| Exposure | **not applied**. It is a saved note only | — |

CET exposes no verified setter for exposure or independent rain intensity, so LocationStudio does not claim to set them. The live rain intensity is shown read-only when the WeatherSystem provides `GetRainIntensity`. Weather states with haze or fog (fog, pollution, sandstorm, toxic rain) also change atmospheric density.

The weather list contains the base game's 24h states and several quest states. The WeatherSystem accepts any registered state, so a custom state CName can be typed in.

## In game

1. Open **Advanced → Spatial → Environment**.
2. Click **NEW ENVIRONMENT**, or **CAPTURE CURRENT CONDITIONS** to seed one from the live clock and weather.
3. Select it, then set the time, weather, blend time/priority and the optional local fog volume. Click **SAVE ENVIRONMENT**.
4. Click **PREVIEW ENVIRONMENT**. With **Force** on, the clock is re-applied every second and the weather every two seconds whenever the game changes it. This keeps a location frozen at "22:30, rain" while you work. **STOP FORCING** / **FORCE NOW** toggle this during a preview.
5. Click **RESTORE ORIGINAL** when finished.

The preview is not cleared when the CET overlay closes, so you can walk around in it. It survives a CET mod reload: the restore point is kept in LocationStudio's process-lifetime runtime state. Saving an edited environment while it is previewed re-applies it. A lighting time-of-day preview that is already running is taken over, so restoring goes back to the time before either preview. While an environment preview is active, the Lighting tab's time preview is refused.

The preview is refused during an active transform edit or stamp stroke. If one part fails (for example no World Builder Fog Volume catalog), the other parts still apply and the failure is listed as a warning. If nothing can be applied, the original conditions are restored and the call fails. A failed restore keeps the restore point so you can retry.

## Deterministic visual regression

`visual_regression_capture` and `hotcycle_rebuild` accept an environment:

```text
visual_regression_capture(environment_id="env_…", environment_settle_s=4)
hotcycle_rebuild(archives=[…], capture_visuals=true, visual_environment_id="env_…")
```

The capture works like this:
- The environment is previewed with force on before the first camera and stays forced for the whole series.
- The original conditions are restored afterwards, even when a shot fails.
- The run manifest records the environment's time/weather/fog settings.
- Accepting a run stores those settings with the baseline. A later capture under a different environment, or with none, sets `environment_mismatch` and explains that pixel changes may come from conditions rather than the build.

NPCs, traffic, weather particles and cloud motion still animate. Keep `pixel_threshold`/`change_limit` suited to the scene.

## MCP

- `environment_weather_states` lists the known states and the capabilities the current session supports.
- `environment_list`, `environment_create`, `environment_update` (only the given fields change) and `environment_delete` (undoable) manage saved environments.
- `environment_preview(environment_id, force)`, `environment_force(force)`, `environment_status` and `environment_restore(blend_time)` drive the live preview.

`environment_create` and `environment_update` take flat fields: `hour`, `minute`, `time_enabled`, `weather_state`, `weather_enabled`, `blend_time`, `priority`, `fog_enabled`, `fog_anchor`, `fog_size_x/y/z` (together), `fog_density_factor`, `fog_density_falloff`, `fog_absorption`, `fog_blend_falloff`, `fog_color` (three 0–1 values) and `exposure_note`. `capture_current=true` on create reads the live clock and weather.

A preview changes the running game's clock and weather, so always finish with `environment_restore`. Restore returns weather to the normal game cycle. It does not re-pin a weather state that a quest had forced before the preview; the game re-evaluates quest weather itself.

## Limits

- The automated tests run against a mocked CET runtime with a fake WeatherSystem. They check the saved data, apply/force/restore control flow, reload-safe restore points, the fog volume data, the bridge/MCP contracts and the screenshot-capture sequencing. They do not render weather. Check in game with [IN-GAME-CHECK.md](IN-GAME-CHECK.md).
- Some quest states only look right in their quest areas. A World Builder fog volume may not show fully in preview because World Builder does not preview light channels.
