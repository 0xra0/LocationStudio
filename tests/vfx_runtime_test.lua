local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local vfx=assert(app.vfx,'VFX module must be constructed')

local catalogs={
    particle={
        {name='smoke_chimney_thick',path='base\\fx\\environment\\smoke\\smoke_chimney_thick.particle'},
        {name='steam_vent_small',path='base\\fx\\environment\\steam\\steam_vent_small.particle'},
        {name='sparks_welding_loop',path='base\\fx\\environment\\sparks\\sparks_welding_loop.particle'},
        {name='pipe_leak_water_drip',path='base\\fx\\environment\\water\\pipe_leak_water_drip.particle'},
        {name='generic_glow',path='base\\fx\\misc\\generic_glow.particle'},
    },
    effect={
        {name='hologram_ad_flicker',path='base\\fx\\holo\\hologram_ad_flicker.effect'},
        {name='barrel_fire_small',path='base\\fx\\environment\\fire\\barrel_fire_small.effect'},
    },
}
local loads={}
function app.world_builder:load_catalog(key,force)
    loads[#loads+1]={key=key,force=force}
    if env.vfx_catalog_error==key then return nil,'catalog '..key..' offline' end
    local out={}
    for i,row in ipairs(catalogs[key] or {}) do out[i]={index=i,name=row.name,path=row.path,entry={data={spawnData=row.path}}} end
    return out
end
function app.world_builder:prepare_favorite_record(record,name)
    local saved={spawnData=record.spawn_data,modulePath=record.variant=='Particles' and 'visual/particle' or 'visual/effect',dataType=record.variant}
    if record.variant=='Particles' then saved.emissionRate=1;saved.respawnOnMove=false end
    return {name=name,data={name=name,modulePath='modules/classes/editor/spawnableElement',spawnable=saved}}
end

-- Catalog search and categories.
local all=assert(vfx:search({}))
assert(all.total==7 and all.catalog_counts.particle==5 and all.catalog_counts.effect==2)
local smoke=assert(vfx:search({category='smoke'}))
assert(smoke.total==1 and smoke.items[1].name=='smoke_chimney_thick' and smoke.items[1].backend=='particle')
assert(assert(vfx:search({category='hologram'})).items[1].node=='worldEffectNode')
assert(assert(vfx:search({category='leak'})).items[1].name=='pipe_leak_water_drip')
assert(assert(vfx:search({category='other'})).items[1].name=='generic_glow')
assert(assert(vfx:search({query='FIRE',backend='effect'})).total==1)
assert(assert(vfx:search({query='fire',backend='particle'})).total==0)
assert(assert(vfx:search({limit=2})).shown==2)
assert(not vfx:search({category='nonsense'}),'unknown category must fail')
assert(not vfx:search({backend='mesh'}),'unknown backend must fail')
env.vfx_catalog_error='effect'
local partial=assert(vfx:search({}));assert(partial.total==5 and partial.errors.effect,'one missing catalog must be reported, not fatal')
env.vfx_catalog_error=nil
assert(#vfx:categories()>=10)

-- Place a scaled, rotated particle at the aim point.
local placed=assert(vfx:create({resource_path=catalogs.particle[2].path,name='Vent steam',source='aim',roll=0,pitch=90,yaw=45,scale=2.5,emission_rate=3}))
local obj=placed.object
assert(placed.spawned and obj.runtime.backend=='world_builder',tostring(placed.spawn_error))
assert(obj.kind=='particle' and obj.metadata.world_builder.definition_key=='particle' and obj.metadata.world_builder.apply_scale==false)
assert(obj.metadata.vfx.scale.x==2.5 and obj.metadata.vfx.scale.z==2.5 and obj.metadata.vfx.category=='steam')
assert(obj.metadata.world_builder.entry.data.emissionRate==3)
assert(obj.transform.rotation.pitch==90 and obj.transform.rotation.yaw==45)
assert(obj.transform.position.x==env.aim_x and obj.transform.position.z==env.aim_z)
local handle=app.runtime_shell.handles[obj.id];assert(handle and handle.rotation.pitch==90)
assert(handle.scale==nil,'World Builder VFX nodes must not receive a fake live scale')
assert(not vfx:create({resource_path='base\\fx\\invented.particle'}),'paths outside the loaded catalog must be rejected')
assert(not vfx:create({resource_path=catalogs.particle[1].path,scale=0}),'zero scale must fail')
assert(not vfx:create({resource_path=catalogs.particle[1].path,emission_rate=-1}),'negative emission must fail')

-- Surface alignment uses the aimed normal.
env.aim_normal={x=0,y=-1,z=0}
local aligned=assert(vfx:create({resource_path=catalogs.particle[4].path,source='aim',align_to_surface=true,yaw=10,spawn=false}))
assert(math.abs(aligned.object.transform.rotation.roll+90)<0.001 and aligned.object.transform.rotation.yaw==10)
env.aim_normal={x=0,y=0,z=1}

-- Effects have no emission settings.
local holo=assert(vfx:create({query='hologram',source='player',scale={x=1,y=2,z=3}}))
assert(holo.object.kind=='effect' and holo.object.metadata.vfx.emission_rate==nil and holo.object.metadata.vfx.scale.y==2)
assert(holo.object.metadata.world_builder.entry.data.emissionRate==nil)

-- Rotation edits apply live; emission falls back to respawn when no live component is exposed.
local removed=env.wb_removed
local rotated=assert(vfx:update(obj.id,{yaw=180}))
assert(rotated.live_updated and not rotated.respawned and env.wb_removed==removed)
assert(app.runtime_shell.handles[obj.id].rotation.yaw==180)
local respawned=assert(vfx:update(obj.id,{emission_rate=5,scale={x=1,y=1,z=4}}))
assert(respawned.respawned and env.wb_removed==removed+1)
assert(obj.metadata.vfx.emission_rate==5 and obj.metadata.world_builder.entry.data.emissionRate==5 and obj.metadata.vfx.scale.z==4 and obj.metadata.vfx.scale.x==1)
-- With World Builder's live particle component available, emission changes without respawning.
local component={emissionRate=5}
local live=app.runtime_shell.handles[obj.id]
live.spawnable.getEntity=function() return {FindComponentByName=function(_,n) if n=='particle' then return component end end} end
local tuned=assert(vfx:update(obj.id,{emission_rate=0.5}))
assert(tuned.live_updated and not tuned.respawned and component.emissionRate==0.5 and live.spawnable.emissionRate==0.5)
-- Resource swap respawns with the new catalog row.
local swapped=assert(vfx:update(obj.id,{resource_path=catalogs.particle[3].path}))
assert(swapped.respawned and obj.metadata.vfx.resource_path==catalogs.particle[3].path and obj.metadata.vfx.scale.z==4)
assert(obj.metadata.world_builder.entry.data.spawnData==catalogs.particle[3].path)
assert(not vfx:update(obj.id,{scale=500}),'scale above 100 must fail')
assert(not vfx:update('missing',{}),'unknown object must fail')

local listed=vfx:list({category='sparks'});assert(listed.count==1 and listed.items[1].id==obj.id)
assert(vfx:list().count==3)

-- Live preview is transient, follows aim, and commits into one saved object.
local count=#app.model.data.objects
local preview=assert(vfx:preview_start({query='fire',source='aim',yaw=30}))
assert(preview.active and preview.follow and preview.backend=='effect')
assert(app.runtime_shell.handles.__vfx_preview,'preview must be a live WB node')
assert(#app.model.data.objects==count,'preview must not create a project object')
for _,item in ipairs(app.placement:compare_runtime().items) do assert(item.id~='__vfx_preview','Runtime Sync must not treat the VFX preview as an orphan') end
env.aim_x=40
vfx:update_tick(0.2)
assert(vfx:preview_status().transform.position.x==40 and app.runtime_shell.handles.__vfx_preview.position.x==40)
assert(assert(vfx:preview_update({follow=false,pitch=15})).transform.rotation.pitch==15)
env.aim_x=55;vfx:update_tick(0.2)
assert(vfx:preview_status().transform.position.x==40,'pinned preview must not follow aim')
local swap=assert(vfx:preview_update({resource_path=catalogs.particle[1].path}))
assert(swap.backend=='particle' and swap.resource_name=='smoke_chimney_thick')
local committed=assert(vfx:preview_commit({name='Chimney smoke',scale=3}))
assert(not vfx:preview_status().active and app.runtime_shell.handles.__vfx_preview==nil)
assert(#app.model.data.objects==count+1 and committed.object.name=='Chimney smoke')
assert(committed.object.transform.position.x==40 and committed.object.transform.rotation.pitch==15 and committed.object.metadata.vfx.scale.x==3)
assert(not vfx:preview_commit({}),'commit without a preview must fail')
assert(vfx:preview_clear(),'clearing with no preview is a no-op')

-- Transactions block VFX mutations.
local real=app.transform_session.is_active
app.transform_session.is_active=function() return true end
assert(not vfx:create({query='smoke',source='player'}))
assert(not vfx:preview_start({query='smoke'}))
app.transform_session.is_active=real

-- Undo removes the committed effect record.
assert(app.model:undo())
assert(#app.model.data.objects==count)

-- Bridge operations share the same module.
local bridge_search=assert(app.bridge:handle({id='v1',op='vfx_search',args={category='sparks'}}))
assert(bridge_search.total==1)
local bridge_cats=assert(app.bridge:handle({id='v2',op='vfx_categories',args={}}));assert(#bridge_cats.backends==2)
local bridge_create=assert(app.bridge:handle({id='v3',op='vfx_create',args={query='steam',source='player',scale=1.5}}))
assert(bridge_create.object.metadata.vfx.scale.y==1.5)
local bridge_update=assert(app.bridge:handle({id='v4',op='vfx_update',args={object_id=bridge_create.object.id,patch={roll=5}}}))
assert(bridge_update.object.transform.rotation.roll==5)
assert(assert(app.bridge:handle({id='v5',op='vfx_preview',args={query='holo',source='player'}})).active)
assert(assert(app.bridge:handle({id='v6',op='vfx_preview',args={update=true,yaw=90}})).transform.rotation.yaw==90)
assert(assert(app.bridge:handle({id='v7',op='vfx_preview_status',args={}})).active)
assert(assert(app.bridge:handle({id='v8',op='vfx_preview_clear',args={}})).cleared)
assert(assert(app.bridge:handle({id='v9',op='vfx_list',args={}})).count>=1)

-- The Spatial VFX tab draws and its buttons reach the module.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['SEARCH VFX CATALOG']=true
env:draw()
assert(env.labels['SEARCH VFX CATALOG'],'VFX tab must be drawn')
assert(app.ui.spatial.vfx_results and app.ui.spatial.vfx_results.total==7)
env.clicks['PREVIEW AT AIM##vfx']=true;env:draw()
assert(vfx:preview_status().active,'PREVIEW AT AIM must start a live preview')
env.clicks['CLEAR PREVIEW##vfx']=true;env:draw()
assert(not vfx:preview_status().active)
print('vfx_runtime_test: OK')
