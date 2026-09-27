local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end

local entity_seq=2000;local alive={};local ray_index=0
exEntitySpawner={}
function exEntitySpawner.Spawn(template,transform,appearance) entity_seq=entity_seq+1;alive[entity_seq]={template=template,transform=transform,appearance=appearance};return entity_seq end
function exEntitySpawner.Despawn(entity) if entity and entity.id then alive[entity.id]=nil end;return true end

local orientation={}
function orientation:ToEulerAngles() return {roll=0,pitch=0,yaw=45} end
local world={position=nil,orientation=nil}
function world:SetPosition(p) self.position=p end
function world:SetOrientation(q) self.orientation=q end
local player={}
function player:GetWorldPosition() return {x=10,y=20,z=30,w=1} end
function player:GetWorldOrientation() return orientation end
function player:GetWorldYaw() return 45 end
function player:GetWorldForward() return {x=1,y=0,z=0} end
function player:GetWorldTransform() return world end

function ToVector4(t) return t end
function ToEulerAngles(t) local e=t;function e:ToQuat() return {roll=self.roll,pitch=self.pitch,yaw=self.yaw} end;return e end

Game={}
function Game.GetPlayer() return player end
function Game.GetSpatialQueriesSystem()
    return {SyncRaycastByCollisionGroup=function(self,a,b,g)
        ray_index=ray_index+1
        return {position={x=12+ray_index,y=22,z=31,w=1}, normal={x=0,y=0,z=1}}
    end}
end
function Game.GetTargetingSystem() return {GetLookAtObject=function() return nil end} end
function Game.FindEntityByID(id) if alive[id] then return {id=id} end end
function Game.GetTeleportationFacility() return {Teleport=function(self,p,pos,rot) return true end} end
function Game.GetCameraSystem()
    return {
        GetActiveCameraPosition=function() return {x=10,y=20,z=31,w=1} end,
        GetActiveCameraRotation=function() return {roll=0,pitch=0,yaw=90} end,
        GetActiveCameraForward=function() return {x=1,y=0,z=0} end,
        GetActiveCameraFOV=function() return 70 end,
    }
end

ImGui={};ImGuiCond={FirstUseEver=1};ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
for _,n in ipairs({'Begin','End','BeginChild','EndChild','Button','SmallButton','Text','TextDisabled','TextWrapped','TextColored','Separator','SameLine','Selectable','InputText','InputTextWithHint','InputTextMultiline','InputFloat','InputFloat3','InputInt','Checkbox','SliderFloat','BeginTabBar','EndTabBar','BeginTabItem','EndTabItem','BeginCombo','EndCombo','BeginPopup','EndPopup','OpenPopup','CloseCurrentPopup','SetTooltip','SetNextWindowSize','PushStyleColor','PopStyleColor','PushItemWidth','PopItemWidth','GetContentRegionAvail'}) do ImGui[n]=function(...) return false end end

local app=dofile(mod..'/init.lua');events.onInit();assert(app.ready)
local premise,err=app.actions:create_premise_from_player('Preview Premise','interior');assert(premise,err)
local room;room,err=app.actions:create_room({name='Preview Room',width=6,depth=5,height=3});assert(room,err)
local asset=app.model:add_asset({name='Preview Chair',category='Props',kind='prop',template='base\\runtime\\chair.ent',appearance='default',layer='decoration'})
local status,warn=app.placement:preview_asset(asset.id,{mode='aim',distance=8,follow=true});assert(status and status.active,warn);assert(status.asset_id==asset.id)
local first_id=status.entity_id
local updated=app.placement:update_preview(true);assert(updated and updated.active)
assert(updated.entity_id~=first_id,'preview should refresh transient entity when following aim')
local placed,perr=app.placement:place_previewed(premise.id,room.id);assert(placed,perr);assert(app.model:get_object(placed.id)~=nil)
local cleared=app.placement:preview_status();assert(cleared.active==false,'preview should be cleared after placement')

local log=io.open(mod..'/logs/locationstudio.log','r');assert(log);local text=log:read('*a');log:close()
for _,needle in ipairs({'[placement:preview]','[action:place_asset]'}) do assert(string.find(text,needle,1,true),needle..' missing from log') end
print('LocationStudio asset preview runtime mock: OK')
