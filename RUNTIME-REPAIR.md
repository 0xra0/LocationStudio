# LocationStudio v0.4.2 runtime repair

The supplied v0.4.1 log identified the first deterministic editor failure as `ui/viewport.lua:47: attempt to index local 'draw' (a userdata value)`. The editor then disabled the full UI. v0.4.2 removes that path rather than wrapping it in another error handler.

## What changed

The active editor now owns three real workspace panels: SCENE, BUILD, and SPATIAL. BUILD instantiates the existing premise/room/object authoring panel. SPATIAL instantiates the existing gameplay-volume/camera panel. Both use the same `modules/selection.lua` selection state as the hierarchy, inspector, actions, hotkeys, and MCP bridge.

The scene panel is implemented only with ordinary CET ImGui widgets. It displays scene entities, coordinates, runtime state, selection, and transform controls without calling raw draw-list methods.

Game-facing actions now distinguish authored-data success from live-preview success. An object remains created if its `.ent` spawn fails; the failure is returned and logged instead of losing the object reference and making the state ambiguous.

## Upgrade-safe install

The upgrade-safe ZIP intentionally omits `data/project.json`, `data/config.json`, live bridge JSON, logs, and exports. Extract it over the Cyberpunk 2077 game root. Existing LocationStudio project/configuration data stays in place.

## Verification performed outside the game

- Lua syntax compilation for all mod Lua files.
- Existing MCP static bridge tests.
- Mocked CET UI runtime with `ImGui.GetWindowDrawList()` forced to raise if called.
- Mocked game/entity-spawner action flow covering premise, room, volume, camera, point, object placement, spawn, refresh, despawn, duplicate, delete, and teleport.

Actual REDengine/CET behavior still requires one in-game run. v0.4.2 logs every important action so a remaining runtime-specific failure should identify the operation instead of looking like a dead button.

## Re-run the local regression tests

From the source package root (with `texlua` available):

```sh
MOD="$PWD/bin/x64/plugins/cyber_engine_tweaks/mods/LocationStudio"
texlua tests/lua_syntax_check.lua "$MOD"
TMP=$(mktemp -d); mkdir -p "$TMP"/{logs,data,bridge,exports}; (cd "$TMP" && texlua "$OLDPWD/tests/mock_runtime_test.lua" "$MOD"); rm -rf "$TMP"
TMP=$(mktemp -d); mkdir -p "$TMP"/{logs,data,bridge,exports}; (cd "$TMP" && texlua "$OLDPWD/tests/action_runtime_test.lua" "$MOD"); rm -rf "$TMP"
python3 "$MOD/mcp_server/test_bridge.py"
```
