local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end

local orientation={};function orientation:ToEulerAngles() return {roll=0,pitch=0,yaw=0} end
local world={};function world:SetPosition(p) self.position=p end;function world:SetOrientation(q) self.orientation=q end
local player={};function player:GetWorldPosition() return {x=100,y=200,z=10,w=1} end;function player:GetWorldOrientation() return orientation end;function player:GetWorldYaw() return 0 end;function player:GetWorldForward() return {x=0,y=1,z=0} end;function player:GetWorldTransform() return world end
function ToVector4(t) return t end
function ToEulerAngles(t) local e=t;function e:ToQuat() return e end;return e end
Game={};function Game.GetPlayer() return player end

ImGui={};ImGuiCond={FirstUseEver=1};ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
for _,n in ipairs({'Begin','End','BeginChild','EndChild','Button','SmallButton','Text','TextDisabled','TextWrapped','TextColored','Separator','SameLine','Selectable','InputText','InputTextWithHint','InputTextMultiline','InputFloat','InputFloat3','InputInt','Checkbox','SliderFloat','BeginTabBar','EndTabBar','BeginTabItem','EndTabItem','BeginCombo','EndCombo','BeginPopup','EndPopup','OpenPopup','CloseCurrentPopup','SetTooltip','SetNextWindowSize','PushStyleColor','PopStyleColor','PushItemWidth','PopItemWidth','GetContentRegionAvail','Spacing','NewLine','BulletText'}) do ImGui[n]=function(...) return false end end

local app=dofile(mod..'/init.lua');events.onInit();assert(app.ready);assert(app.version=='0.67.0');app.model.data.settings.quickstart.strict_runtime=false
local first,err=app.quickstart:create_first_room({location_name='Zero Docs',width=5,depth=4,height=3});assert(first,err)
assert(#app.model.data.premises==1);assert(#app.model.data.rooms==1);assert(first.room.name=='Room 1')
assert(first.room.transform.position.x==100 and first.room.transform.position.y==200)
local north;north,err=app.quickstart:add_adjacent_room({direction='north',width=5,depth=4,height=3,auto_door=true});assert(north,err)
assert(#app.model.data.rooms==2);assert(north.room.transform.position.y==204)
assert(#first.room.openings==1 and first.room.openings[1].wall=='north')
assert(#north.room.openings==1 and north.room.openings[1].wall=='south')
local east;east,err=app.quickstart:add_adjacent_room({direction='east',width=3,depth=4,height=3,auto_door=false});assert(east,err)
assert(#app.model.data.rooms==3);assert(#east.room.openings==0)
assert(app.selection:is('room',east.room.id))
print('LocationStudio zero-doc quickstart runtime: OK')
