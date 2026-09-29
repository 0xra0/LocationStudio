local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.83.0')

local premise=assert(app.actions:create_premise_from_player('Transform Edit Test','exterior'))
local function wb_metadata(path,name)
    return {world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name=name,entry={name=path,fileName=name,data={spawnData=path}}}}
end
local function wb_object(name,path,x,yaw)
    return assert(app.builder:place_object({premise_id=premise.id,name=name,kind='mesh',template=path,size={x=1,y=1,z=1},transform={position={x=x,y=5,z=2,w=1},rotation={roll=0,pitch=0,yaw=yaw or 0}},metadata=wb_metadata(path,name)}))
end

local a=wb_object('Edit A','base\\edit_a.mesh',0,0)
local b=wb_object('Edit B','base\\edit_b.mesh',2,0)
assert(app.placement:spawn(a));assert(app.placement:spawn(b))
app.selection:set_object_group({a.id,b.id},b.id,'locationstudio')

local undo_before=#app.model.undo_stack
local started=assert(app.transform_session:start_edit({pivot_mode='center',local_space=false}))
assert(started.active and started.kind=='edit' and started.count==2)
local saved,save_err=app:save(true);assert(not saved and save_err:find('transform session',1,true))
local history,history_err=app.actions:history('undo');assert(not history and history_err:find('transform session',1,true))
local blocked,blocked_err=app.bridge:handle({id='blocked-edit',op='create_location',args={name='Must Not Exist'}})
assert(not blocked and blocked_err:find('transform session',1,true))

local edited=assert(app.transform_session:adjust({dx=1,dy=2,dz=0.5,dyaw=90,scale_factor=1.5}))
assert(math.abs(a.transform.position.x-2)<0.001 and math.abs(a.transform.position.y-5.5)<0.001)
assert(math.abs(b.transform.position.x-2)<0.001 and math.abs(b.transform.position.y-8.5)<0.001)
assert(math.abs(a.transform.position.z-2.5)<0.001 and a.transform.rotation.yaw==90)
assert(math.abs(a.size.x-1.5)<0.001 and math.abs(b.size.z-1.5)<0.001)
assert(math.abs(app.runtime_shell.handles[a.id].position.y-5.5)<0.001)
assert(math.abs(app.runtime_shell.handles[b.id].scale.x-1.5)<0.001)
assert(edited.translation.x==1 and edited.rotation_delta.yaw==90 and edited.scale_factor==1.5)
assert(#app.model.undo_stack==undo_before,'preview adjustments must not create history')
local bad_rotation,bad_rotation_err=app.transform_session:adjust({droll=5})
assert(not bad_rotation and bad_rotation_err:find('yaw rotation only',1,true))

assert(app.transform_session:reset_edit())
assert(a.transform.position.x==0 and b.transform.position.x==2 and a.size.x==1 and b.size.x==1)
assert(app.runtime_shell.handles[a.id].position.x==0)
assert(app.transform_session:adjust({dx=3,dyaw=45,scale_factor=1.25}))
local cancelled=assert(app.transform_session:cancel());assert(cancelled.kind=='edit')
assert(a.transform.position.x==0 and b.transform.position.x==2 and a.transform.rotation.yaw==0 and a.size.x==1)
assert(#app.model.undo_stack==undo_before,'cancelled Transform Edit must not create history')

app.selection:set('object',a.id)
assert(app.transform_session:start_edit({pivot_mode='active',local_space=true}))
assert(app.transform_session:adjust({dx=1,droll=10,dpitch=-5,dyaw=15,scale_factor=2}))
assert(math.abs(a.transform.position.x-1)<0.001 and math.abs(a.transform.position.y-5)<0.001)
assert(a.transform.rotation.roll==10 and a.transform.rotation.pitch==-5 and a.transform.rotation.yaw==15)
assert(a.size.x==2)
local committed=assert(app.transform_session:commit());assert(committed.kind=='edit' and committed.scale_factor==2)
assert(#app.model.undo_stack==undo_before+1,'Transform Edit commit must create exactly one history state')
assert(app.actions:history('undo'))
a=app.model:get_object(a.id);assert(a.transform.position.x==0 and a.size.x==1 and a.transform.rotation.roll==0)

local local_object=wb_object('Local Axis','base\\local.mesh',4,90);assert(app.placement:spawn(local_object));app.selection:set('object',local_object.id)
assert(app.transform_session:start_edit({pivot_mode='active',local_space=true}))
assert(app.transform_session:adjust({dx=1}))
assert(math.abs(local_object.transform.position.x-4)<0.001 and math.abs(local_object.transform.position.y-6)<0.001,'local X did not follow active yaw')
assert(app.transform_session:cancel())

local cet=assert(app.builder:place_object({premise_id=premise.id,name='CET Live Edit',kind='prop',template='base\\edit.ent',size={x=1,y=1,z=1},transform={position={x=1,y=1,z=1,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
assert(app.placement:spawn(cet));app.selection:set('object',cet.id)
started=assert(app.transform_session:start_edit({pivot_mode='active'}));assert(started.deferred_cet==1)
assert(app.transform_session:adjust({dx=3,dyaw=20}))
assert(cet.transform.position.x==4 and cet.transform.rotation.yaw==20)
assert(env.last_world.position.x==4,'direct CET entity was not respawned at the adjusted transform')
local scaled,scale_err=app.transform_session:adjust({scale_factor=1.1})
assert(not scaled and scale_err:find('World Builder resources',1,true));assert(cet.size.x==1)
assert(app.transform_session:cancel());assert(cet.transform.position.x==1 and env.last_world.position.x==1)

events.onOverlayOpen();app.model.data.settings.workspace.panel='SCENE';app.ui.compact_scene='overview';app.selection:set('object',b.id);env:draw()
assert(env.labels['EDIT SELECTION##scene_edit'],'Scene Transform Edit entry is missing')
assert(app.transform_session:start_edit({pivot_mode='active'}));env:draw()
for _,label in ipairs({'-X##edit_header','+X##edit_header','YAW -##edit_header','YAW +##edit_header','SIZE -##edit_header','SIZE +##edit_header','RESET##edit_header','COMMIT##edit_header','CANCEL##edit_header'}) do assert(env.labels[label],label..' missing') end
assert(app.transform_session:cancel())
assert(hotkeys.locationstudio_edit_selection,'Transform Edit hotkey is missing')

local bridge_started=assert(app.bridge:handle({id='edit-start',op='start_transform_edit',args={ids={b.id},active_id=b.id,pivot_mode='active'}}));assert(bridge_started.kind=='edit')
local bridge_adjusted=assert(app.bridge:handle({id='edit-adjust',op='adjust_transform_edit',args={dz=0.5,dyaw=5}}));assert(bridge_adjusted.translation.z==0.5)
local bridge_status=assert(app.bridge:handle({id='edit-status',op='get_transform_session_status',args={}}));assert(bridge_status.kind=='edit')
assert(app.bridge:handle({id='edit-reset',op='reset_transform_edit',args={}}))
assert(app.bridge:handle({id='edit-cancel',op='cancel_transform_edit',args={}}))

local noop_history=#app.model.undo_stack
app.selection:set('object',b.id);assert(app.transform_session:start_edit({pivot_mode='active'}))
local noop=assert(app.transform_session:commit());assert(noop.changed==false and #app.model.undo_stack==noop_history,'no-op edit must not create history')

local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[transform:edit] started','[transform:edit] adjusted','[transform:edit] reset','[transform:edit] committed','[transform:edit] cancelled'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio transactional Transform Edit: OK')
