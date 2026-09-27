local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.60.0')

local premise=assert(app.actions:create_premise_from_player('Scatter Edit Test','exterior'))
local function wb_metadata(path,name)
    return {room_kit=true,generated=true,world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name=name,entry={name=path,fileName=name,data={spawnData=path}}}}
end
local wb=assert(app.builder:place_object({premise_id=premise.id,name='Scatter WB',kind='mesh',template='base\\scatter.mesh',size={x=1,y=1,z=1},transform={position={x=11,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata=wb_metadata('base\\scatter.mesh','scatter')}))
local cet=assert(app.builder:place_object({premise_id=premise.id,name='Scatter CET',kind='prop',template='base\\scatter.ent',size={x=1,y=1,z=1},transform={position={x=13,y=20,z=31,w=1},rotation={roll=0,pitch=0,yaw=10}}}))
assert(app.placement:spawn(wb));assert(app.placement:spawn(cet));assert(app:save(true))
app.selection:set_object_group({wb.id,cet.id},cet.id,'locationstudio')
env.aim_x=40;env.aim_y=50;env.aim_z=20;env.ground_z=5

local object_count=#app.model.data.objects;local undo_before=#app.model.undo_stack
local args={count=2,radius=3,distance=15,seed=12345,random_yaw=true,drop_to_ground=true}
local started=assert(app.transform_session:start_scatter(args))
assert(started.operation=='scatter' and started.count==4 and started.creation.repetitions==2 and started.creation.source_count==2)
assert(started.creation.seed==12345 and #started.creation.points==2 and #started.created_ids==4)
local snapshot={}
for index,id in ipairs(started.created_ids) do
    local copy=assert(app.model:get_object(id));assert(app.placement:is_tracked(copy))
    snapshot[index]={x=copy.transform.position.x,y=copy.transform.position.y,z=copy.transform.position.z,yaw=copy.transform.rotation.yaw}
    local point=started.creation.points[math.floor((index-1)/2)+1]
    local dx=point.x-40;local dy=point.y-50;assert(math.sqrt(dx*dx+dy*dy)<=3.00001)
    assert(math.abs(point.z-5.02)<0.001 and point.ground_source=='ground_raycast')
end
assert(app.model:get_object(started.created_ids[1]).metadata.detached_from_room==true)
for set=0,1 do
    local a=app.model:get_object(started.created_ids[set*2+1]);local b=app.model:get_object(started.created_ids[set*2+2])
    local dx=a.transform.position.x-b.transform.position.x;local dy=a.transform.position.y-b.transform.position.y
    assert(math.abs(math.sqrt(dx*dx+dy*dy)-2)<0.001 and math.abs((b.transform.position.z-a.transform.position.z)-1)<0.001)
end
assert(#app.model.undo_stack==undo_before and app.dirty==false)
assert(app.transform_session:cancel());assert(#app.model.data.objects==object_count and app.dirty==false and app.selection.id==cet.id)

started=assert(app.transform_session:start_scatter(args))
for index,id in ipairs(started.created_ids) do
    local copy=app.model:get_object(id);local before=snapshot[index]
    assert(math.abs(copy.transform.position.x-before.x)<0.000001 and math.abs(copy.transform.position.y-before.y)<0.000001)
    assert(math.abs(copy.transform.rotation.yaw-before.yaw)<0.000001,'same seed must reproduce yaw')
end
env.wb_remove_error=true
local blocked,blocked_err=app.transform_session:cancel();assert(not blocked and blocked_err:find('retained the copies',1,true));assert(app.transform_session:is_active())
env.wb_remove_error=false;assert(app.transform_session:cancel())

app.selection:set_object_group({wb.id,cet.id},cet.id,'locationstudio')
started=assert(app.transform_session:start_scatter(args));assert(app.transform_session:adjust({dx=0.5,dy=-0.25,dz=0.1}))
local committed=assert(app.transform_session:commit());assert(committed.operation=='scatter' and #committed.created_ids==4)
assert(#app.model.undo_stack==undo_before+1 and #app.model.data.objects==object_count+4)
assert(app.actions:history('undo'));assert(#app.model.data.objects==object_count)
assert(app.actions:history('redo'));assert(#app.model.data.objects==object_count+4)

app.selection:set_object_group({wb.id,cet.id},cet.id,'locationstudio')
local too_many,limit_err=app.transform_session:start_scatter({count=51,radius=1,drop_to_ground=false});assert(not too_many and limit_err:find('100 created objects',1,true))
env.ground_miss=true;local before_failure=#app.model.data.objects
local missed,miss_err=app.transform_session:start_scatter({count=1,radius=1,seed=9,drop_to_ground=true});assert(not missed and miss_err:find('ground raycast failed',1,true))
assert(not app.transform_session:is_active() and #app.model.data.objects==before_failure)
env.ground_miss=false

local asset=app.model:add_asset({name='Scatter Asset WB',kind='mesh',template='base\\asset.mesh',size={x=1,y=1,z=1},metadata=wb_metadata('base\\asset.mesh','asset')})
assert(app:save(true));app.selection:set('asset',asset.id);object_count=#app.model.data.objects;undo_before=#app.model.undo_stack
started=assert(app.transform_session:start_scatter({kind='asset',id=asset.id,premise_id=premise.id,count=2,radius=0,seed=77,drop_to_ground=false}))
assert(started.creation.source_kind=='asset' and #started.created_ids==2)
for _,id in ipairs(started.created_ids) do local copy=app.model:get_object(id);assert(copy.metadata.world_builder and app.placement:is_tracked(copy)) end
assert(app.transform_session:cancel());assert(#app.model.data.objects==object_count and app.selection.kind=='asset' and app.selection.id==asset.id and #app.model.undo_stack==undo_before)

local legacy_asset=assert(app.ent_tools:scatter_at_aim({kind='asset',id=asset.id,premise_id=premise.id,count=1,radius=0,seed=78,drop_to_ground=false,spawn=false}))
assert(legacy_asset.committed and legacy_asset.count==1 and not app.placement:is_tracked(legacy_asset.objects[1]))
assert(app.actions:history('undo'))

app.selection:set('object',cet.id);undo_before=#app.model.undo_stack
local legacy=assert(app.ent_tools:scatter_at_aim({kind='object',id=cet.id,count=2,radius=0,seed=44,distance=10,drop_to_ground=false,spawn=false}))
assert(legacy.committed and legacy.count==2 and legacy.seed==44 and #app.model.undo_stack==undo_before+1)
for _,copy in ipairs(legacy.objects) do assert(not app.placement:is_tracked(copy)) end
assert(app.actions:history('undo'))

events.onOverlayOpen();app.ui.tools:draw()
for _,label in ipairs({'SCATTER + EDIT','Ground each stamp'}) do assert(env.labels[label],label..' missing from tools') end
local tools_source=assert(io.open('ui/tools.lua','r'));local tools_text=tools_source:read('*a');tools_source:close();assert(tools_text:find('Deterministic seed',1,true))
assert(hotkeys.locationstudio_scatter_edit,'scatter hotkey missing')
app.selection:set('object',cet.id)
local bridge=assert(app.bridge:handle({id='scatter-start',op='start_scatter_transform_edit',args={ids={cet.id},active_id=cet.id,count=2,radius=1,seed=88,drop_to_ground=false}}))
assert(bridge.operation=='scatter' and bridge.creation.seed==88);assert(app.bridge:handle({id='scatter-cancel',op='cancel_transform_edit',args={}}))

local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[transform:scatter] started','[transform:scatter] adjusted','[transform:scatter] committed','[transform:scatter] cancel_blocked','[transform:scatter] cancelled','[ent_tools:scatter] complete'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio transactional Scatter Placement: OK')
