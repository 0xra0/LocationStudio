local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={};local labels={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
Game={};function Game.GetPlayer() return nil end
json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end
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
function ImGui.Button(label,...) labels[label]=true;return false end
function ImGui.SmallButton(label,...) labels[label]=true;return false end
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
function ImGui.GetContentRegionAvail() return 1400,760 end
function ImGui.GetWindowDrawList() error('raw draw list must not be used') end

local app=dofile(mod..'/init.lua');events.onInit();assert(app.ready);assert(app.version=='0.65.0')
app.config.window_open=true;app.model.data.settings.workspace.beginner_mode=true;app.model.data.settings.workspace.panel='HOME'
events.onOverlayOpen();events.onDraw();assert(app.ui_failed==nil,tostring(app.ui_failed))
for _,required in ipairs({'BUILD','ASSETS','SCENE','SAVE PROJECT','CREATE ROOM HERE'}) do assert(labels[required],required..' missing from Simple UI') end
for _,forbidden in ipairs({'+ POINT HERE','POINT HERE','CAMERA HERE','VOLUME HERE','APARTMENT','CLINIC','WAREHOUSE','COPY XFORM','PASTE XFORM','SCATTER STAMP','CAPTURE LOCATION POINT','RUN VALIDATION','WORLD BUILDER##export','QUESTFORGE##export'}) do
    assert(not labels[forbidden],forbidden..' should not render in Simple UI')
end
print('LocationStudio focused Simple UI contract: OK')
