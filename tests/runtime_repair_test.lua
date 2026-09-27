local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end
function ModArchiveExists(name) return name=='baseEntity.archive' end

local wb_spawned=0;local wb_removed=0
local spawnUI={}
function spawnUI.getSpawnListByModulePath(path) if path=='mesh/mesh' then return {class={}} end end
function spawnUI.resolveEntryClass(list,entry) return {new=function() return {modulePath='mesh/mesh'} end} end
function spawnUI.spawnNew(entry,class,isFavorite,options)
    wb_spawned=wb_spawned+1
    local e={removed=false}
    function e:setPosition(pos) self.position=pos end
    function e:setRotation(rot) self.rotation=rot end
    function e:remove() if not self.removed then self.removed=true;wb_removed=wb_removed+1 end end
    return e
end
local wb={baseUI={spawnUI=spawnUI}}
function GetMod(name) if name=='entSpawner' or name=='WorldBuilder' then return wb end end

Vector4={};function Vector4.new(x,y,z,w) return {x=x,y=y,z=z,w=w or 1} end
EulerAngles={};function EulerAngles.new(r,p,y) return {roll=r,pitch=p,yaw=y} end
function ToVector4(t) return t end
function ToEulerAngles(t) local e=t;function e:ToQuat() return e end;return e end

local entity_seq=4000;local alive={}
exEntitySpawner={}
function exEntitySpawner.Spawn(template,transform,appearance) entity_seq=entity_seq+1;alive[entity_seq]=true;return entity_seq end
function exEntitySpawner.Despawn(entity) if entity then alive[entity.id]=nil end return true end

local orientation={};function orientation:ToEulerAngles() return {roll=0,pitch=0,yaw=90} end
local world={};function world:SetPosition(p) self.position=p end;function world:SetOrientation(q) self.orientation=q end
local player={}
function player:GetWorldPosition() return {x=10,y=20,z=30,w=1} end
function player:GetWorldOrientation() return orientation end
function player:GetWorldYaw() return 90 end
function player:GetWorldForward() return {x=1,y=0,z=0,w=0} end
function player:GetWorldTransform() return world end
Game={}
function Game.GetPlayer() return player end
function Game.FindEntityByID(id) if alive[id] then return {id=id} end end
function Game.GetSpatialQueriesSystem()
    return {SyncRaycastByCollisionGroup=function(self,a,b,group,...) return true,{position={x=15,y=20,z=30,w=1},normal={x=0,y=0,z=1,w=0}} end}
end
function Game.GetTargetingSystem() return {GetLookAtObject=function() return nil end} end
function Game.GetCameraSystem() return {GetActiveCameraPosition=function() return {x=10,y=20,z=31,w=1} end,GetActiveCameraRotation=function() return {roll=0,pitch=0,yaw=90} end,GetActiveCameraForward=function() return {x=1,y=0,z=0,w=0} end} end
function Game.GetTeleportationFacility() return {Teleport=function() return true end} end

ImGui={};ImGuiCond={FirstUseEver=1};ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
for _,n in ipairs({'Begin','End','BeginChild','EndChild','Button','SmallButton','Text','TextDisabled','TextWrapped','TextColored','Separator','SameLine','Selectable','InputText','InputTextWithHint','InputTextMultiline','InputFloat','InputFloat3','InputInt','Checkbox','SliderFloat','BeginTabBar','EndTabBar','BeginTabItem','EndTabItem','BeginCombo','EndCombo','BeginPopup','EndPopup','OpenPopup','CloseCurrentPopup','SetTooltip','SetNextWindowSize','PushStyleColor','PopStyleColor','PushStyleVar','PopStyleVar','PushItemWidth','PopItemWidth','GetContentRegionAvail','Spacing','NewLine','BulletText','IsItemHovered'}) do ImGui[n]=function(...) return false end end

local app=dofile(mod..'/init.lua');events.onInit();assert(app.ready);assert(app.version=='0.59.0')
assert(app.model.data.schema_version==17)
assert(#app.model.data.assets>=6,'starter catalog was not seeded')
local shell=app.runtime_shell:status(true);assert(shell.available,shell.reason)
local selftest,selferr=app.placement:spawn_test_asset('builtin_chair_poor');assert(selftest,selferr);assert(selftest.entity_id)
local cleared_test,clearerr=app.placement:clear_test_asset();assert(cleared_test,clearerr)

-- Current CET raycast shape: bool + result. This was the real game.lua:191 crash.
local hit,rayerr=app.game:raycast({x=0,y=0,z=1,w=1},{x=20,y=0,z=1,w=1},{'Static'});assert(hit,rayerr);assert(hit.position.x==15)

local first,err=app.quickstart:create_first_room({location_name='Runtime Visible',width=5,depth=4,height=3});assert(first,err)
assert(first.runtime and #first.runtime.spawned>0,'quick room did not spawn visible shell')
assert(wb_spawned>0,'World Builder primitive API was not called')

-- Starter assets must be immediately spawnable without registering paths by hand.
local asset=app.model:get_asset('builtin_chair_poor');assert(asset and asset.template~='')
local object;object,err=app.actions:place_asset(asset.id,'aim',{spawn=true});assert(object,err);assert(object.runtime and object.runtime.spawned and object.runtime.backend=='entity_spawner')

app.selection:set('object',object.id)
local moved;moved,err=app.ent_tools:move_to_aim(nil,nil,10);assert(moved,err)
local grounded;grounded,err=app.ent_tools:drop_to_ground();assert(grounded,err)

local before=app.placement:status();assert(before.spawned>0 and before.shell_spawned>0 and before.entity_spawned>0)
local cleared=app.placement:despawn_all();assert(cleared.despawned>0);assert(wb_removed>0)
local after=app.placement:status();assert(after.spawned==0,'real runtime count should reach zero after despawn')
print('LocationStudio v0.8.1 runtime repair: OK')
