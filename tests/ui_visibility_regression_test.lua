local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
Game={};function Game.GetPlayer() return nil end
json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end

local main_begin_count=0
ImGuiCond={FirstUseEver=1};ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
ImGui={}
function ImGui.Begin(name,arg)
    if string.find(name,'Location Studio##LocationStudioMain',1,true) then main_begin_count=main_begin_count+1 end
    -- Reproduce CET's numeric-flags overload used by v0.9.3: single bool return.
    if type(arg)=='number' then return true end
    return arg,true
end
function ImGui.End() end
function ImGui.BeginChild(...) return true end;function ImGui.EndChild() end
function ImGui.BeginTabBar(...) return true end;function ImGui.EndTabBar() end
function ImGui.BeginTabItem(...) return true end;function ImGui.EndTabItem() end
function ImGui.BeginCombo(...) return false end;function ImGui.EndCombo() end
function ImGui.BeginPopup(...) return false end;function ImGui.EndPopup() end
function ImGui.OpenPopup(...) end;function ImGui.CloseCurrentPopup() end
function ImGui.Text(...) end;function ImGui.TextDisabled(...) end;function ImGui.TextWrapped(...) end;function ImGui.TextColored(...) end
function ImGui.Separator() end;function ImGui.SameLine(...) end;function ImGui.Spacing() end;function ImGui.NewLine() end;function ImGui.BulletText(...) end
function ImGui.SetTooltip(...) end;function ImGui.SetNextWindowSize(...) end;function ImGui.SetNextWindowPos(...) end
function ImGui.PushStyleColor(...) end;function ImGui.PopStyleColor(...) end;function ImGui.PopStyleVar(...) end;function ImGui.PushItemWidth(...) end;function ImGui.PopItemWidth(...) end
function ImGui.Button(...) return false end;function ImGui.SmallButton(...) return false end;function ImGui.Selectable(...) return false end;function ImGui.InvisibleButton(...) return false end
function ImGui.IsItemHovered() return false end;function ImGui.IsItemClicked(...) return false end
function ImGui.InputText(label,value,...) return value,false end;function ImGui.InputTextWithHint(label,hint,value,...) return value,false end;function ImGui.InputTextMultiline(label,value,...) return value,false end
function ImGui.InputFloat(label,value,...) return value,false end;function ImGui.InputInt(label,value,...) return value,false end;function ImGui.InputFloat3(label,value,...) return value,false end
function ImGui.Checkbox(label,value) return value,false end;function ImGui.SliderFloat(label,value,...) return value,false end
function ImGui.GetContentRegionAvail() return 1200,700 end
function ImGui.GetWindowDrawList() error('raw draw list must not be used') end

local app=dofile(mod..'/init.lua')
events.onInit();assert(app.ready);assert(app.version=='0.76.0')

-- Reproduce the v0.9.0 failure state: config persisted false before opening CET.
app.config.window_open=false;app.editor_visible=false
events.onOverlayOpen()
assert(app.config.window_open==true,'overlay open must repair stale persisted window_open=false')
assert(app.editor_visible==true,'overlay open must restore editor visibility')
events.onDraw()
assert(main_begin_count==1,'main editor window was not drawn after CET overlay opened')
assert(app.ui_failed==nil,'UI failed during visibility recovery: '..tostring(app.ui_failed))
assert(app._first_ui_draw_logged==true,'first-frame draw heartbeat was not recorded')

-- Hotkey may hide it during the current overlay session.
hotkeys.locationstudio_toggle_window();events.onDraw();assert(main_begin_count==1,'hidden editor should not draw')
-- Reopening CET must always restore the window again.
events.onOverlayClose();events.onOverlayOpen();events.onDraw();assert(main_begin_count==2,'reopening CET did not restore LocationStudio')

print('LocationStudio UI visibility regression: OK')
