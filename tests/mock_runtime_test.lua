local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
Game={}
function Game.GetPlayer() return nil end
json={}
function json.decode(text) return {} end
function json.encode(value) return '{}' end
ImGuiCond={FirstUseEver=1}
ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
ImGui={}
function ImGui.Begin(name,open) return open,true end
function ImGui.End() end
function ImGui.BeginChild(...) return true end
function ImGui.EndChild() end
function ImGui.BeginTabBar(...) return true end
function ImGui.EndTabBar() end
function ImGui.BeginTabItem(...) return true end
function ImGui.EndTabItem() end
function ImGui.BeginCombo(...) return false end
function ImGui.EndCombo() end
function ImGui.BeginPopup(...) return false end
function ImGui.EndPopup() end
function ImGui.OpenPopup(...) end
function ImGui.CloseCurrentPopup() end
function ImGui.Text(...) end
function ImGui.TextDisabled(...) end
function ImGui.TextWrapped(...) end
function ImGui.TextColored(...) end
function ImGui.Separator() end
function ImGui.SameLine(...) end
function ImGui.Spacing() end
function ImGui.NewLine() end
function ImGui.BulletText(...) end
function ImGui.SetTooltip(...) end
function ImGui.SetNextWindowSize(...) end
function ImGui.PushStyleColor(...) end
function ImGui.PopStyleColor(...) end
function ImGui.PopStyleVar(...) end
function ImGui.PushItemWidth(...) end
function ImGui.PopItemWidth(...) end
function ImGui.Button(...) return false end
function ImGui.SmallButton(...) return false end
function ImGui.Selectable(...) return false end
function ImGui.InvisibleButton(...) return false end
function ImGui.IsItemHovered() return false end
function ImGui.IsItemClicked(...) return false end
function ImGui.InputText(label,value,...) return value,false end
function ImGui.InputTextWithHint(label,hint,value,...) return value,false end
function ImGui.InputTextMultiline(label,value,...) return value,false end
function ImGui.InputFloat(label,value,...) return value,false end
function ImGui.InputInt(label,value,...) return value,false end
function ImGui.InputFloat3(label,value,...) return value,false end
function ImGui.Checkbox(label,value) return value,false end
function ImGui.SliderFloat(label,value,...) return value,false end
function ImGui.GetContentRegionAvail() return 1200,700 end
-- Regression guard: the repaired viewport must not touch CET raw draw-list userdata.
function ImGui.GetWindowDrawList() error('raw draw list must not be used') end

local app=dofile(mod..'/init.lua')
assert(events.onInit,'onInit missing');events.onInit()
assert(app.ready==true,'app not ready')
assert(app.version=='0.67.0','wrong version '..tostring(app.version))
events.onOverlayOpen();events.onDraw();events.onUpdate(0.016)
assert(app.ui_failed==nil,'full editor failed: '..tostring(app.ui_failed))
assert(app.model.data.settings.workspace.panel=='HOME','v0.6 should open in HOME for first-time/simple users')
-- Create a model-only premise to force SCENE renderer down its item path while no Game player exists.
local premise=app.model:add_premise({name='Mock Premise',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selection:set('premise',premise.id)
app.model.data.settings.workspace.panel='SCENE'
events.onDraw()
assert(app.ui_failed==nil,'scene renderer failed: '..tostring(app.ui_failed))
app.model.data.settings.workspace.panel='BUILD';events.onDraw();assert(app.ui_failed==nil,'build panel failed: '..tostring(app.ui_failed))
app.model.data.settings.workspace.panel='SPATIAL';events.onDraw();assert(app.ui_failed==nil,'spatial panel failed: '..tostring(app.ui_failed))
app.model.data.settings.workspace.panel='TOOLS';events.onDraw();assert(app.ui_failed==nil,'tools panel failed: '..tostring(app.ui_failed))
events.onOverlayClose();events.onShutdown()
print('LocationStudio mocked CET runtime smoke: OK')
