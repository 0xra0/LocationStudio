local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.65.0')

local premise=assert(app.actions:create_premise_from_player('Pattern Edit Test','exterior'))
local function wb_metadata(path,name)
    return {room_kit=true,generated=true,world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name=name,entry={name=path,fileName=name,data={spawnData=path}}}}
end
local wb=assert(app.builder:place_object({premise_id=premise.id,name='Pattern WB',kind='mesh',template='base\\pattern.mesh',size={x=1,y=1,z=1},transform={position={x=11,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata=wb_metadata('base\\pattern.mesh','pattern')}))
assert(app.placement:spawn(wb));assert(app:save(true));app.selection:set('object',wb.id)

local object_count=#app.model.data.objects;local undo_before=#app.model.undo_stack
local started=assert(app.transform_session:start_pattern({count=3,dx=1,dy=0,dz=0,dyaw=0,pattern_local_space=false,pattern_pivot_mode='active'}))
assert(started.operation=='pattern' and started.count==3 and started.creation.repetitions==3 and started.creation.source_count==1)
assert(#started.created_ids==3 and #app.model.data.objects==object_count+3)
for index,id in ipairs(started.created_ids) do
    local copy=assert(app.model:get_object(id));assert(copy.transform.position.x==11+index and app.placement:is_tracked(copy))
    assert(copy.metadata.room_kit==false and copy.metadata.detached_from_room==true)
end
assert(#app.model.undo_stack==undo_before and app.dirty==false)
env.wb_remove_error=true
local blocked,blocked_err=app.transform_session:cancel();assert(not blocked and blocked_err:find('retained the copies',1,true))
assert(app.transform_session:is_active() and #app.model.data.objects==object_count+3)
env.wb_remove_error=false;assert(app.transform_session:cancel())
assert(#app.model.data.objects==object_count and #app.model.undo_stack==undo_before and app.selection.id==wb.id and app.dirty==false)

local cet=assert(app.builder:place_object({premise_id=premise.id,name='Pattern CET',kind='prop',template='base\\pattern.ent',size={x=1,y=1,z=1},transform={position={x=13,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=10}}}))
assert(app.placement:spawn(cet));assert(app:save(true));app.selection:set_object_group({wb.id,cet.id},cet.id,'locationstudio')
local too_many,too_many_err=app.transform_session:start_pattern({count=51,dx=1});assert(not too_many and too_many_err:find('100 created objects',1,true))
local zero,zero_err=app.transform_session:start_pattern({count=2,dx=0,dy=0,dz=0,dyaw=0});assert(not zero and zero_err:find('non-zero',1,true))

undo_before=#app.model.undo_stack;object_count=#app.model.data.objects
started=assert(app.transform_session:start_pattern({count=2,dx=0,dy=2,dz=0,dyaw=90,pattern_local_space=false,pattern_pivot_mode='center'}))
assert(started.operation=='pattern' and started.count==4 and #started.created_ids==4)
local copies={};for index,id in ipairs(started.created_ids) do copies[index]=assert(app.model:get_object(id));assert(app.placement:is_tracked(copies[index])) end
assert(math.abs(copies[1].transform.position.x-12)<0.001 and math.abs(copies[1].transform.position.y-21)<0.001)
assert(math.abs(copies[2].transform.position.x-12)<0.001 and math.abs(copies[2].transform.position.y-23)<0.001)
assert(math.abs(copies[3].transform.position.x-13)<0.001 and math.abs(copies[3].transform.position.y-24)<0.001)
assert(math.abs(copies[4].transform.position.x-11)<0.001 and math.abs(copies[4].transform.position.y-24)<0.001)
assert(copies[1].transform.rotation.yaw==90 and copies[2].transform.rotation.yaw==100)
assert(app.transform_session:adjust({dx=0.5,dz=0.25}))
assert(math.abs(env.last_world.position.x-11.5)<0.001 and math.abs(env.last_world.position.z-30.25)<0.001,'direct CET pattern did not refresh live')
local scaled,scale_err=app.transform_session:adjust({scale_factor=1.1});assert(not scaled and scale_err:find('World Builder resources',1,true))
local committed=assert(app.transform_session:commit());assert(committed.operation=='pattern' and #committed.created_ids==4)
assert(#app.model.undo_stack==undo_before+1 and #app.model.data.objects==object_count+4)
assert(app.actions:history('undo'));assert(#app.model.data.objects==object_count)
assert(app.actions:history('redo'));assert(#app.model.data.objects==object_count+4)

app.selection:set_object_group({wb.id,cet.id},cet.id,'locationstudio');object_count=#app.model.data.objects;undo_before=#app.model.undo_stack
started=assert(app.transform_session:start_mirror({axis='x'}));assert(started.operation=='mirror' and started.count==2 and started.creation.axis=='x')
local mirror_wb=assert(app.model:get_object(started.created_ids[1]));local mirror_cet=assert(app.model:get_object(started.created_ids[2]))
assert(mirror_wb.transform.position.x==9 and mirror_wb.transform.rotation.yaw==180)
assert(mirror_cet.transform.position.x==7 and mirror_cet.transform.rotation.yaw==170)
assert(app.placement:is_tracked(mirror_wb) and app.placement:is_tracked(mirror_cet))
assert(app.transform_session:cancel());assert(#app.model.data.objects==object_count and #app.model.undo_stack==undo_before)

app.selection:set('object',wb.id);undo_before=#app.model.undo_stack
local legacy_array=assert(app.builder:array_object(wb.id,2,0,1,0,0));assert(#legacy_array==2)
assert(#app.model.undo_stack==undo_before+1 and app.placement:is_tracked(legacy_array[1]) and legacy_array[1].metadata.detached_from_room==true)
assert(app.actions:history('undo'));assert(not app.model:get_object(legacy_array[1].id))
undo_before=#app.model.undo_stack
local legacy_mirror=assert(app.builder:mirror_object(wb.id,'y'));assert(legacy_mirror.transform.position.y==20)
assert(#app.model.undo_stack==undo_before+1 and app.placement:is_tracked(legacy_mirror))
assert(app.actions:history('undo'))

events.onOverlayOpen();app.model.data.settings.workspace.panel='SCENE';app.ui.compact_scene='overview';app.selection:set('object',wb.id);env:draw()
assert(env.labels['ARRAY + EDIT##scene_pattern_edit'],'Scene Array Edit entry is missing')
app.ui.tools:draw()
for _,label in ipairs({'CREATE ARRAY + EDIT','MIRROR X + EDIT','MIRROR Y + EDIT'}) do assert(env.labels[label],label..' missing from tools') end
assert(hotkeys.locationstudio_array_edit and hotkeys.locationstudio_mirror_x_edit and hotkeys.locationstudio_mirror_y_edit)

local bridge_pattern=assert(app.bridge:handle({id='pattern-start',op='start_pattern_transform_edit',args={ids={wb.id},active_id=wb.id,count=2,dx=0.5,dy=0,dz=0,dyaw=0}}))
assert(bridge_pattern.operation=='pattern' and #bridge_pattern.created_ids==2);assert(app.bridge:handle({id='pattern-cancel',op='cancel_transform_edit',args={}}))
local bridge_mirror=assert(app.bridge:handle({id='mirror-start',op='start_mirror_transform_edit',args={ids={wb.id},active_id=wb.id,axis='y'}}))
assert(bridge_mirror.operation=='mirror' and #bridge_mirror.created_ids==1);assert(app.bridge:handle({id='mirror-cancel',op='cancel_transform_edit',args={}}))

local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[transform:pattern] started','[transform:pattern] adjusted','[transform:pattern] committed','[transform:pattern] cancel_blocked','[transform:pattern] cancelled','[transform:mirror] started','[transform:mirror] committed','[transform:mirror] cancelled'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio transactional Pattern Placement: OK')
