local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end

local entity_seq=1000;local alive={}
exEntitySpawner={}
function exEntitySpawner.Spawn(template,transform,appearance) entity_seq=entity_seq+1;alive[entity_seq]=true;return entity_seq end
function exEntitySpawner.Despawn(entity) if entity and entity.id then alive[entity.id]=nil end;return true end

local orientation={}
function orientation:ToEulerAngles() return {roll=1,pitch=2,yaw=90} end
local world={position=nil,orientation=nil}
function world:SetPosition(p) self.position=p end
function world:SetOrientation(q) self.orientation=q end
local player={}
function player:GetWorldPosition() return {x=10,y=20,z=30,w=1} end
function player:GetWorldOrientation() return orientation end
function player:GetWorldYaw() return 90 end
function player:GetWorldForward() return {x=1,y=0,z=0} end
function player:GetWorldTransform() return world end

function ToVector4(t) return t end
function ToEulerAngles(t) local e=t;function e:ToQuat() return {roll=self.roll,pitch=self.pitch,yaw=self.yaw} end;return e end

Game={}
function Game.GetPlayer() return player end
function Game.GetSpatialQueriesSystem() return {SyncRaycastByCollisionGroup=function(self,a,b,g) return {position={x=15,y=20,z=31,w=1}} end} end
function Game.GetTargetingSystem() return {GetLookAtObject=function() return nil end} end
function Game.FindEntityByID(id) if alive[id] then return {id=id} end end
function Game.GetTeleportationFacility() return {Teleport=function(self,p,pos,rot) return true end} end

-- Only minimum ImGui needed for module initialization; no onDraw in this test.
ImGui={};ImGuiCond={FirstUseEver=1};ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
for _,n in ipairs({'Begin','End','BeginChild','EndChild','Button','SmallButton','Text','TextDisabled','TextWrapped','TextColored','Separator','SameLine','Selectable','InputText','InputTextWithHint','InputTextMultiline','InputFloat','InputFloat3','InputInt','Checkbox','SliderFloat','BeginTabBar','EndTabBar','BeginTabItem','EndTabItem','BeginCombo','EndCombo','BeginPopup','EndPopup','OpenPopup','CloseCurrentPopup','SetTooltip','SetNextWindowSize','PushStyleColor','PopStyleColor','PushItemWidth','PopItemWidth','GetContentRegionAvail'}) do ImGui[n]=function(...) return false end end

local app=dofile(mod..'/init.lua');events.onInit();assert(app.ready)
local premise,err=app.actions:create_premise_from_player('Runtime Premise','interior');assert(premise,err);assert(app.selection:is('premise',premise.id));assert(app.selected_premise_id==premise.id)
local room;room,err=app.actions:create_room({name='Runtime Room',width=6,depth=5,height=3});assert(room,err);assert(app.selection:is('room',room.id));assert(#room.shell_object_ids>0)
local volume;volume,err=app.actions:create_volume({name='Runtime Volume',shape='box',size_x=2,size_y=3,size_z=4});assert(volume,err);assert(app.selection:is('volume',volume.id));assert(volume.transform.position.x==10)
local camera;camera,err=app.actions:create_camera({name='Runtime Camera',distance=8});assert(camera,err);assert(app.selection:is('camera',camera.id));assert(camera.look_at.x==15)
local point;point,err=app.actions:capture_location('Runtime Point','point');assert(point,err);assert(app.selection:is('location',point.id));assert(app.selected_premise_id==premise.id,'global selection must preserve active premise')
local asset=app.model:add_asset({name='Chair',category='Props',kind='prop',template='base\\runtime\\chair.ent',appearance='',layer='decoration'});app:mark_dirty()
app.model.data.settings.workspace.live_preview=true
local object;object,err=app.actions:place_asset(asset.id,'player');assert(object,err);assert(app.selection:is('object',object.id));assert(object.runtime and object.runtime.spawned==true,err)
local first_entity=object.runtime.entity_id
local refreshed;refreshed,err=app.actions:refresh_selected();assert(refreshed,err);assert(object.runtime.spawned)
local ok;ok,err=app.actions:despawn_selected();assert(ok,err);assert(object.runtime.spawned==false)
local entity;entity,err=app.actions:spawn_selected();assert(entity,err);assert(object.runtime.spawned==true)
local updated;updated,err=app.actions:update_selected({name='Chair Updated'});assert(updated,err);assert(updated.name=='Chair Updated')
local copy;copy,err=app.actions:duplicate_selected();assert(copy,err);assert(copy.id~=object.id);assert(app.selection:is('object',copy.id))
ok,err=app.actions:delete_selected();assert(ok,err);assert(app.model:get_object(copy.id)==nil);assert(app.selected_object_id==nil)
app.selection:set('premise',premise.id)
local spawn_result,warn=app.actions:spawn_selected();assert(spawn_result);assert(type(spawn_result.failed)=='table')
local despawn_ok,despawn_warn=app.actions:despawn_selected();assert(despawn_ok)
local tp,tp_err=app.game:teleport(point.transform);assert(tp,tp_err)

local log=io.open(mod..'/logs/locationstudio.log','r');assert(log);local text=log:read('*a');log:close()
for _,needle in ipairs({'[action:create_premise]','[action:create_room]','[action:create_volume]','[action:create_camera]','[action:place_asset]','[placement:spawn]','[action:delete_selected]'}) do assert(string.find(text,needle,1,true),needle..' missing from log') end
print('LocationStudio action/runtime mock: OK')
