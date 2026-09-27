local root=arg[1]
local files={
'init.lua','modules/actions.lua','modules/ambient_audio.lua','modules/authoring.lua','modules/bridge.lua','modules/builder.lua','modules/diagnostics.lua','modules/ent_tools.lua','modules/game.lua','modules/integrations.lua','modules/logger.lua','modules/markers.lua','modules/model.lua','modules/placement.lua','modules/quickstart.lua','modules/runtime_shell.lua','modules/thumbnails.lua','modules/selection.lua','modules/storage.lua','modules/util.lua','modules/world_builder.lua','modules/build_export.lua','ui/browser.lua','ui/editor.lua','ui/hierarchy.lua','ui/home.lua','ui/inspector.lua','ui/premises.lua','ui/spatial.lua','ui/theme.lua','ui/tools.lua','ui/viewport.lua'}
local bad=0
for _,rel in ipairs(files) do
  local path=root..'/'..rel
  local fn,err=loadfile(path)
  if not fn then io.stderr:write(rel..': '..tostring(err)..'\n');bad=bad+1 end
end
if bad>0 then os.exit(1) end
print('Lua syntax check: OK ('..#files..' files)')
