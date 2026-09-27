-- Contract fixture, not a REDengine emulator. Delayed entity loading is
-- controllable so a returned ID cannot silently stand in for a visible object.
local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path
local env={instant=true,alive={},seq=100,aim_x=15,aim_y=20,aim_z=30,aim_normal={x=0,y=0,z=1},clicks={},inputs={},labels={},windows={},width=1100,wb_entries={},wb_removed=0,wb_enabled=true,wb_selected=nil,stack={},styles=0,widths=0}
events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(name,label,fn) hotkeys[name]=fn end
json={encode=function(value) return test_json_encode(value) end,decode=function(value) return test_json_decode(value) end}
local player={}
function ToVector4(value) return value end
Vector4={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
CName={new=function(value) return value end}
EulerAngles={new=function(roll,pitch,yaw) return {roll=roll,pitch=pitch,yaw=yaw} end}
function ToEulerAngles(value) function value:ToQuat() return self end;return value end
function player:GetWorldPosition() return {x=10,y=20,z=30,w=1} end
function player:GetWorldOrientation() return {ToEulerAngles=function() return {roll=0,pitch=0,yaw=0} end} end
function player:GetWorldYaw() return 0 end
function player:GetWorldForward() return {x=0,y=1,z=0} end
function player:GetWorldTransform() return {SetPosition=function(self,v) self.position=v end,SetOrientation=function(self,v) self.rotation=v end} end
Game={}
local mock_time=8*3600
function Game.GetTimeSystem() return {GetGameTime=function() return {seconds=mock_time,SetGameTimeBySeconds=function(self,v) mock_time=v end} end,SetGameTimeByHMS=function(self,h,m,ss) mock_time=h*3600+m*60+ss end} end
GameTime={GetSeconds=function(value) return value.seconds end}
function Game.GetPlayer() if not env.offline then return player end end
function Game.FindEntityByID(id) return env.alive[id] end
function Game.GetTeleportationFacility() return {Teleport=function() return true end} end
function Game.GetCameraSystem()
    return {GetActiveCameraPosition=function() return {x=10,y=20,z=31,w=1} end,GetActiveCameraRotation=function() return {roll=0,pitch=0,yaw=0} end,GetActiveCameraForward=function() return {x=0,y=1,z=0} end}
end
function Game.GetSpatialQueriesSystem() return {SyncRaycastByCollisionGroup=function(self,a,b)
    if b.z<a.z-0.5 then
        if env.ground_miss then return false,nil end
        return true,{position={x=a.x,y=a.y,z=env.ground_z or env.aim_z,w=1},normal={x=0,y=0,z=1}}
    end
    return true,{position={x=env.aim_x,y=env.aim_y,z=env.aim_z,w=1},normal={x=env.aim_normal.x,y=env.aim_normal.y,z=env.aim_normal.z}}
end} end
function Game.GetTargetingSystem() return {GetLookAtObject=function() return nil end} end
exEntitySpawner={}
function exEntitySpawner.Spawn(template,world,appearance)
    if env.spawn_throws then error('injected spawn failure') end
    env.seq=env.seq+1
    env.last_world=world
    if env.instant then env.alive[env.seq]={id=env.seq} end
    return env.seq
end
function exEntitySpawner.Despawn(entity)
    if env.remove_rejected then return false end
    env.alive[entity.id]=nil
end
local spawnUI={selectedType=0,selectedVariant=0,filter='',spawnedUI={root={}}}
function spawnUI.spawnedUI.unselectAll()
    env.wb_selected=nil
    for _,handle in ipairs(env.wb_entries) do handle.selected=false end
end
local wb_category='Entity'
local function wb_class(module_path) return {new=function()
    local instance={modulePath=module_path,apps={'default','damaged'},app='default',alpha=1,scale={x=1,y=1,z=1}}
    local component={meshAppearance='default',LoadAppearance=function(self) self.loaded=true end}
    instance.entity={FindComponentByName=function(_,name) if name=='mesh' then return component end end}
    function instance:loadSpawnData(data) self.spawnData=data.spawnData or data.name or 'test-resource';self.app=data.app or 'default';self.alpha=data.alpha or 1;self.scale=data.scale or self.scale end
    function instance:save() return {spawnData=self.spawnData or 'default-light',app=self.app,alpha=self.alpha,autoHideDistance=150,horizontalFlip=false,verticalFlip=false,scale=self.scale,color={1,1,1},intensity=100,radius=15,flickerStrength=0,flickerPeriod=0.2,flickerOffset=0} end
    function instance:getEntity() return self.entity end
    return instance
end} end
local wb_lists={
    Entity={data={{name='base\\environment\\decoration\\furniture\\chairs\\game_chair.ent',fileName='game_chair',data={spawnData='base\\environment\\decoration\\furniture\\chairs\\game_chair.ent'}}},class=wb_class('entity/entityTemplate'),modulePath='entity/entityTemplate',isPaths=true},
    Mesh={data={{name='base\\environment\\architecture\\walls\\game_wall.mesh',fileName='game_wall',data={spawnData='base\\environment\\architecture\\walls\\game_wall.mesh'}}},class=wb_class('mesh/mesh'),modulePath='mesh/mesh',isPaths=true},
    Lighting={data={{name='Static Light Default',fileName='Static Light Default',data={spawnData='test-light-preset'}}},class=wb_class('light/light'),modulePath='light/light',isPaths=false},
    Deco={data={{name='base\\decal\\test.mi',fileName='test_decal',data={spawnData='base\\decal\\test.mi'}}},class=wb_class('visual/decal'),modulePath='visual/decal',isPaths=true},
    Collision={data={{name='Box - Default',fileName='Box - Default',data={shape=0,scale={x=1,y=1,z=1},previewed=false,modulePath='collision/collider',dataType='Collision Shape'}}},class=wb_class('collision/collider'),modulePath='collision/collider',isPaths=false},
}
function spawnUI.getCategoryIndex(name) local values={Entity=1,Mesh=2,Lighting=3,Deco=4,Collision=5,Meta=6,Area=7,AI=8};return assert(values[name]) end
function spawnUI.getVariantIndex(category,name) return 1 end
function spawnUI.updateCategory() local values={[0]='Entity',[1]='Mesh',[2]='Lighting',[3]='Deco',[4]='Collision'};wb_category=values[spawnUI.selectedType] or wb_category end
function spawnUI.updateVariant() end
function spawnUI.refresh() end
function spawnUI.getActiveSpawnList() return wb_lists[wb_category] end
function spawnUI.getSpawnListByModulePath(path) assert(path=='mesh/mesh');return {} end
function spawnUI.resolveEntryClass() return {} end
function spawnUI.spawnNew(entry,class)
    assert(type(class)=='table','World Builder active-list class was not supplied')
    local handle={entry=entry,spawnable=class:new()}
    handle.spawnable:loadSpawnData(entry.data or {})
    function handle:getEntity() return self.spawnable:getEntity() end
    handle.apps=handle.spawnable.apps
    table.insert(env.wb_entries,handle)
    function handle:setPosition(value) self.position=value end
    function handle:setRotation(value) self.rotation=value end
    function handle:setScale(value) self.scale=value end
    function handle:getPosition() return self.position end
    function handle:getRotation() return self.rotation end
    function handle:getScale() return self.scale end
    function handle:setSelected(value) self.selected=value==true;if self.selected then env.wb_selected=self end end
    function handle:remove() if env.wb_remove_error then error('injected WB remove failure') end;self.removed=true;env.wb_removed=env.wb_removed+1 end
    return handle
end
function GetMod(name) if env.wb_enabled and (name=='entSpawner' or name=='WorldBuilder') then return {baseUI={spawnUI=spawnUI}} end end
function ModArchiveExists(name) return name=='baseEntity.archive' and env.wb_enabled end

local function push(kind) table.insert(env.stack,kind) end
local function pop(kind) assert(table.remove(env.stack)==kind,'unbalanced ImGui '..kind) end
local function button(label)
    env.labels[label]=true
    if env.clicks[label] then env.clicks[label]=nil;return true end
    return false
end
ImGui={};ImGuiCond={FirstUseEver=1}
ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8,WindowBg=9,ChildBg=10}
function ImGui.Begin(name,flags) assert(type(flags)=='number','expected numeric window flags');push('window');env.windows[name]=(env.windows[name] or 0)+1;return not env.collapsed end
function ImGui.End() pop('window') end
function ImGui.BeginChild() push('child');return true end
function ImGui.EndChild() pop('child') end
function ImGui.BeginTabBar() push('tabs');return true end
function ImGui.EndTabBar() pop('tabs') end
function ImGui.BeginTabItem() push('tab');return true end
function ImGui.EndTabItem() pop('tab') end
function ImGui.BeginCombo() return false end
function ImGui.EndCombo() error('unexpected EndCombo') end
function ImGui.BeginPopup() return false end
function ImGui.EndPopup() error('unexpected EndPopup') end
function ImGui.Button(label) return button(label) end
ImGui.SmallButton=ImGui.Button;ImGui.Selectable=ImGui.Button
function ImGui.InputFloat(label,value)
    assert(type(value)=='number','non-numeric '..label)
    local v=env.inputs[label];if v~=nil then env.inputs[label]=nil;return v,v~=value end
    return value,false
end
ImGui.InputInt=ImGui.InputFloat;ImGui.SliderFloat=ImGui.InputFloat
function ImGui.InputText(label,value)
    assert(type(value)=='string','non-string '..label)
    local v=env.inputs[label];if v~=nil then env.inputs[label]=nil;return v,v~=value end
    return value,false
end
ImGui.InputTextMultiline=ImGui.InputText
function ImGui.InputTextWithHint(label,hint,value) return ImGui.InputText(label,value) end
function ImGui.Checkbox(label,value) if button(label) then return not value,true end;return value,false end
function ImGui.ColorEdit3(label,r,g,b) return r,g,b,false end
function ImGui.InputFloat3() error('unverified vector overload must not be called') end
function ImGui.GetWindowDrawList() error('raw draw lists must not be called') end
function ImGui.GetContentRegionAvail() return env.width,650 end
function ImGui.PushStyleColor() env.styles=env.styles+1 end
function ImGui.PopStyleColor(count) env.styles=env.styles-(count or 1);assert(env.styles>=0) end
function ImGui.PushItemWidth() env.widths=env.widths+1 end
function ImGui.PopItemWidth() env.widths=env.widths-1;assert(env.widths>=0) end
function ImGui.IsItemHovered() return false end
for _,name in ipairs({'Text','TextDisabled','TextWrapped','TextColored','Separator','SameLine','Spacing','NewLine','BulletText','SetTooltip','SetNextWindowSize','SetNextWindowPos','OpenPopup','CloseCurrentPopup'}) do ImGui[name]=function() end end

env.app=dofile(mod..'/init.lua');events.onInit();assert(env.app.ready,env.app.init_failed)
function env:draw()
    events.onDraw()
    assert(not self.app.ui_failed,self.app.ui_failed)
    for panel,err in pairs(self.app.ui.panel_errors) do error(panel..': '..err) end
    assert(#self.stack==0,'unbalanced UI scopes');assert(self.styles==0 and self.widths==0,'unbalanced UI styles/widths')
end
return env
