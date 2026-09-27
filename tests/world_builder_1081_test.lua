local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

json={encode=function() return '{}' end,decode=function() return {} end}
Vector4={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
EulerAngles={new=function(roll,pitch,yaw) return {roll=roll,pitch=pitch,yaw=yaw} end}
function ModArchiveExists(name) return name=='baseEntity.archive' end

local category_index={Entity=1,Mesh=2}
local variant_index={Entity={Template=1},Mesh={Mesh=1}}
local selected_category='Entity'
local lists={
    Entity={Template={data={
        {name='base\\chairs\\chair_a.ent',fileName='chair_a',data={spawnData='base\\chairs\\chair_a.ent'}},
        {name='base\\tables\\table_a.ent',fileName='table_a',data={spawnData='base\\tables\\table_a.ent'}},
    },class=nil,modulePath='entity/entityTemplate',isPaths=true}},
    Mesh={Mesh={data={
        {name='base\\walls\\wall_a.mesh',fileName='wall_a',data={spawnData='base\\walls\\wall_a.mesh'}},
    },class=nil,modulePath='mesh/mesh',isPaths=true}},
}

local function class(module_path)
    return {new=function() return {modulePath=module_path,
        loadSpawnData=function(self,data,position,rotation) self.spawnData=data.spawnData;self.position=position;self.rotation=rotation end,
        save=function(self) return {modulePath=self.modulePath,spawnData=self.spawnData,dataType='Spawnable',position=self.position,rotation=self.rotation} end} end}
end
lists.Entity.Template.class=class('entity/entityTemplate')
lists.Mesh.Mesh.class=class('mesh/mesh')

local removed=0
local spawnUI={selectedType=0,selectedVariant=0,filter='',spawnedUI={root={}}}
function spawnUI.getCategoryIndex(name) return assert(category_index[name]) end
function spawnUI.getVariantIndex(category,name) return assert(variant_index[category][name]) end
function spawnUI.updateCategory() selected_category=spawnUI.selectedType==0 and 'Entity' or 'Mesh' end
function spawnUI.updateVariant() end
function spawnUI.refresh() end
function spawnUI.getActiveSpawnList() return lists[selected_category][spawnUI.selectedVariant==0 and (selected_category=='Entity' and 'Template' or 'Mesh')] end
function spawnUI.spawnNew(entry,class,is_favorite)
    assert(entry and class and is_favorite==false)
    local handle={entry=entry}
    function handle:setPosition(value) self.position=value end
    function handle:setRotation(value) self.rotation=value end
    function handle:setScale(value) self.scale=value end
    function handle:remove() removed=removed+1;return true end
    return handle
end
local wb={baseUI={spawnUI=spawnUI}}
function GetMod(name) if name=='entSpawner' then return wb end end

local Model=require('modules/model')
local WorldBuilder=require('modules/world_builder')
local RuntimeShell=require('modules/runtime_shell')
local RoomKits=require('modules/room_kits')
local app={model=Model.new(Model.blank()),integrations={world_builder=wb,refresh=function() end},dirty=false}
function app:mark_dirty() self.dirty=true end
app.world_builder=WorldBuilder.new(app)
app.runtime_shell=RuntimeShell.new(app)

local status=app.world_builder:status();assert(status.available and status.catalog_available,status.reason)
local result,err=app.world_builder:search('entity_template','chair',60);assert(result,err);assert(result.total==1 and result.items[1].name=='chair_a')
local prepared;prepared,err=app.world_builder:prepare_favorite_record({category='Entity',variant='Template',spawn_data='base\\chairs\\chair_a.ent',name='chair_a'},'Chair Test');assert(prepared,err)
assert(prepared.name=='Chair Test' and prepared.data.modulePath=='modules/classes/editor/spawnableElement')
assert(prepared.data.spawnable.modulePath=='entity/entityTemplate' and prepared.data.spawnable.spawnData=='base\\chairs\\chair_a.ent')
assert(prepared.data.pos.x==0 and prepared.data.pos.y==0 and prepared.data.pos.z==0)
local invalid_favorite,invalid_favorite_error=app.world_builder:prepare_favorite_record({category='Entity',variant='Template',spawn_data='base\\invented\\missing.ent'});assert(not invalid_favorite and invalid_favorite_error:find('Not found',1,true))
local asset;asset,err=app.world_builder:import_resource(result.items[1]);assert(asset,err);assert(asset.metadata.world_builder.class_module=='modules/classes/spawn/entity/entityTemplate')
local existing,warning=app.world_builder:import_resource(result.items[1]);assert(existing.id==asset.id and warning)

-- Simulate a game restart: serialized metadata remains, private World Builder
-- modules are inaccessible, and the live class must be recovered again from
-- getActiveSpawnList().
app.world_builder.class_cache={}
local object=app.model:add_object({name='Chair',template=asset.template,size={x=1,y=1,z=1},metadata=asset.metadata,transform={position={x=1,y=2,z=3,w=1},rotation={roll=0,pitch=0,yaw=90}}})
local id;id,err=app.runtime_shell:spawn(object);assert(id,err);assert(object.runtime.backend=='world_builder' and object.runtime.status=='confirmed')
object.transform.position.x=9;assert(app.runtime_shell:update_object(object));assert(app.runtime_shell.handles[object.id].position.x==9)
local ok;ok,err=app.runtime_shell:despawn(object);assert(ok,err);assert(removed==1)

local role=RoomKits.default_settings().roles.wall
local scale={x=2,y=1,z=0.75}
local generated=app.model:add_object({name='Wall',size=scale,metadata=RoomKits.mesh_metadata(role,scale,'common_interior'),transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
id,err=app.runtime_shell:spawn(generated);assert(id,err);assert(app.runtime_shell.handles[generated.id].scale.x==2);assert(app.runtime_shell.handles[generated.id].entry.data.spawnData==role.path);assert(spawnUI.selectedType==0,'World Builder catalog selection was not restored')
local legacy=app.model:add_object({name='Legacy White Cube',size={x=4,y=0.2,z=3},metadata={generated=true},transform={position={x=0,y=0,z=1.5,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local blocked,blocked_err=app.runtime_shell:spawn(legacy);assert(not blocked and blocked_err:find('Legacy primitive shell blocked',1,true))
print('LocationStudio World Builder 1.0.81 catalog / spawn / edit adapter: OK')
