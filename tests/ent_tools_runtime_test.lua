local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end

local entity_seq=2000;local alive={}
exEntitySpawner={}
function exEntitySpawner.Spawn(template,transform,appearance) entity_seq=entity_seq+1;alive[entity_seq]=true;return entity_seq end
function exEntitySpawner.Despawn(entity) if entity and entity.id then alive[entity.id]=nil end;return true end

function ToVector4(t) return t end
function ToEulerAngles(t) local e=t;function e:ToQuat() return {roll=self.roll,pitch=self.pitch,yaw=self.yaw} end;return e end

local orientation={};function orientation:ToEulerAngles() return {roll=0,pitch=0,yaw=90} end
local player={}
function player:GetWorldPosition() return {x=10,y=20,z=30,w=1} end
function player:GetWorldOrientation() return orientation end
function player:GetWorldYaw() return 90 end
function player:GetWorldForward() return {x=1,y=0,z=0,w=0} end

local cameraSystem={}
function cameraSystem:GetActiveCameraPosition() return {x=100,y=200,z=50,w=1} end
function cameraSystem:GetActiveCameraRotation() return {roll=0,pitch=0,yaw=0} end
function cameraSystem:GetActiveCameraForward() return {x=1,y=0,z=0,w=0} end
function cameraSystem:GetActiveCameraFOV() return 72 end

Game={}
function Game.GetPlayer() return player end
function Game.GetCameraSystem() return cameraSystem end
function Game.GetSpatialQueriesSystem()
    return {SyncRaycastByCollisionGroup=function(self,a,b,g)
        if b.z < a.z-1 then return {position={x=a.x,y=a.y,z=5,w=1},normal={x=0,y=0,z=1,w=0}} end
        return {position={x=105,y=200,z=50,w=1},normal={x=0,y=0,z=1,w=0}}
    end}
end
function Game.GetTargetingSystem() return {GetLookAtObject=function() return nil end} end
function Game.FindEntityByID(id) if alive[id] then return {id=id} end end
function Game.GetTeleportationFacility() return {Teleport=function(self,p,pos,rot) return true end} end

ImGui={};ImGuiCond={FirstUseEver=1};ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
for _,n in ipairs({'Begin','End','BeginChild','EndChild','Button','SmallButton','Text','TextDisabled','TextWrapped','TextColored','Separator','SameLine','Spacing','NewLine','BulletText','Selectable','InputText','InputTextWithHint','InputTextMultiline','InputFloat','InputFloat3','InputInt','Checkbox','SliderFloat','BeginTabBar','EndTabBar','BeginTabItem','EndTabItem','BeginCombo','EndCombo','BeginPopup','EndPopup','OpenPopup','CloseCurrentPopup','SetTooltip','SetNextWindowSize','PushStyleColor','PopStyleColor','PushStyleVar','PopStyleVar','PushItemWidth','PopItemWidth','GetContentRegionAvail','IsItemHovered'}) do ImGui[n]=function(...) return false end end

local app=dofile(mod..'/init.lua');events.onInit();assert(app.ready);assert(app.version=='0.74.0')
local premise=app.model:add_premise({name='P',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}});app.selection:set('premise',premise.id)
local room=app.builder:create_room({premise_id=premise.id,name='R',width=4,depth=4,height=3,x=2,y=0,generate_shell=false})
local object=app.builder:place_object({premise_id=premise.id,room_id=room.id,name='O',template='base\\o.ent',transform={position={x=3,y=0,z=1,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selection:set('object',object.id)

local camera,warning=app.game:capture_camera_transform();assert(camera,warning);assert(camera.position.x==100);assert(app.game:camera_fov()==72)
local hit,err=app.game:aim_point(10);assert(hit,err);assert(hit.position.x==105,'aim must use active camera ray')

local copied;copied,err=app.ent_tools:copy('transform');assert(copied,err)
object.transform.position.x=44
local pasted;pasted,err=app.ent_tools:paste('transform');assert(pasted,err);assert(object.transform.position.x==3)

local moved;moved,err=app.ent_tools:move_to_aim('object',object.id,10);assert(moved,err);assert(object.transform.position.x==105)
local dropped;dropped,err=app.ent_tools:drop_to_ground('object',object.id,100,0.1);assert(dropped,err);assert(math.abs(object.transform.position.z-5.1)<0.001)

local target=app.model:add_location({name='Target',transform={position={x=object.transform.position.x,y=object.transform.position.y+10,z=object.transform.position.z,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local aimed;aimed,err=app.ent_tools:aim_at_target('object',object.id,'location',target.id);assert(aimed,err);assert(math.abs(object.transform.rotation.yaw-90)<0.01)

local old_room_x=room.transform.position.x;local old_obj_x=object.transform.position.x
local group;group,err=app.authoring:batch_transform('premise',{premise.id},5,0,0,90,false);assert(group,err)
assert(math.abs(premise.transform.position.x-5)<0.001)
assert(room.transform.position.x~=old_room_x,'room must cascade with premise')
assert(object.transform.position.x~=old_obj_x,'object must cascade with premise')

app.selection:set('object',object.id)
local dup;dup,err=app.ent_tools:duplicate_at_aim('object',object.id,10,false);assert(dup,err);assert(dup.id~=object.id);assert(dup.transform.position.x==105)
local scatter;scatter,err=app.ent_tools:scatter_at_aim({kind='object',id=object.id,count=3,radius=0,distance=10,drop_to_ground=true,spawn=false});assert(scatter,err);assert(scatter.count==3)
for _,made in ipairs(scatter.objects) do assert(math.abs(made.transform.position.z-5.02)<0.001) end

local log=io.open(mod..'/logs/locationstudio.log','r');assert(log);local text=log:read('*a');log:close()
for _,needle in ipairs({'[ent_tools:copy]','[ent_tools:move_to_aim]','[ent_tools:drop_to_ground]','[ent_tools:aim]','[ent_tools:scatter]'}) do assert(string.find(text,needle,1,true),needle..' missing from log') end
print('LocationStudio entSpawner-style tools runtime mock: OK')
