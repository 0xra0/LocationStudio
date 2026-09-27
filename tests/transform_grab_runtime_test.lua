local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.70.0')

local premise=assert(app.actions:create_premise_from_player('Grab Test','exterior'))
local function wb_metadata(path,name)
    return {world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name=name,entry={name=path,fileName=name,data={spawnData=path}}}}
end
local function wb_object(name,path,x)
    return assert(app.builder:place_object({premise_id=premise.id,name=name,kind='mesh',template=path,size={x=1,y=1,z=1},transform={position={x=x,y=5,z=2,w=1},rotation={roll=0,pitch=0,yaw=10}},metadata=wb_metadata(path,name)}))
end

local a=wb_object('Grab A','base\\grab_a.mesh',0)
local b=wb_object('Grab B','base\\grab_b.mesh',2)
assert(app.placement:spawn(a));assert(app.placement:spawn(b))
app.selection:set_object_group({a.id,b.id},b.id,'locationstudio')

local undo_before=#app.model.undo_stack
env.aim_x=15;env.aim_y=20;env.aim_z=30;env.aim_normal={x=0,y=0,z=1}
local started,start_warning=app.transform_session:start({distance=20,pivot_mode='center'})
assert(started,start_warning);assert(started.active and started.count==2)
assert(math.abs(a.transform.position.x-14)<0.001 and math.abs(b.transform.position.x-16)<0.001,'group offsets were not preserved around center pivot')
assert(math.abs(a.transform.position.y-20)<0.001 and math.abs(a.transform.position.z-30.02)<0.001)
assert(app.runtime_shell.handles[a.id].position.x==a.transform.position.x,'World Builder handle did not update live')
local saved,save_err=app:save(true);assert(not saved and save_err:find('transform session',1,true))
local exported,export_err=app:export('json','exports/should_not_exist.json');assert(not exported and export_err:find('transform session',1,true))
local history,history_err=app.actions:history('undo');assert(not history and history_err:find('transform session',1,true))
local bridge_result,bridge_err=app.bridge:handle({id='blocked-during-grab',op='create_location',args={name='Must Not Exist'}})
assert(not bridge_result and bridge_err:find('transform session',1,true),'unrelated MCP mutations must be blocked during Grab Move')
assert(#app.model.undo_stack==undo_before,'grab preview must not create undo history')

assert(app.transform_session:rotate(90))
assert(math.abs(a.transform.position.x-15)<0.001 and math.abs(a.transform.position.y-19)<0.001)
assert(math.abs(b.transform.position.x-15)<0.001 and math.abs(b.transform.position.y-21)<0.001)
assert(a.transform.rotation.yaw==100 and b.transform.rotation.yaw==100)
local cancelled,cancel_warning=app.transform_session:cancel();assert(cancelled,cancel_warning)
assert(a.transform.position.x==0 and b.transform.position.x==2 and a.transform.rotation.yaw==10)
assert(#app.model.undo_stack==undo_before,'cancel must not add undo history')
assert(app.runtime_shell.handles[a.id].position.x==0,'cancel did not restore live World Builder transform')

app.selection:set('object',a.id)
env.aim_x=15.13;env.aim_y=20.12;env.aim_z=30.11;env.aim_normal={x=1,y=0,z=0}
started=assert(app.transform_session:start({distance=20,align_surface=true,snap_position=true,pivot_mode='active'}))
assert(math.abs(a.transform.position.x-15.25)<0.001 and math.abs(a.transform.position.y-20)<0.001 and math.abs(a.transform.position.z-30)<0.001)
assert(math.abs(a.transform.rotation.pitch+90)<0.001)
local committed,commit_warning=app.transform_session:commit();assert(committed,commit_warning)
assert(#app.model.undo_stack==undo_before+1,'commit must create exactly one undo state')
assert(app.dirty==true)
local final_x=a.transform.position.x
assert(app.actions:history('undo'))
a=app.model:get_object(a.id);assert(a.transform.position.x==0 and a.transform.rotation.yaw==10,'undo did not restore pre-grab transform')
assert(final_x~=a.transform.position.x)

local cet=assert(app.builder:place_object({premise_id=premise.id,name='CET Grab',kind='prop',template='base\\grab.ent',transform={position={x=1,y=1,z=1,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
assert(app.placement:spawn(cet));app.selection:set('object',cet.id)
env.aim_x=17;env.aim_y=22;env.aim_z=31;env.aim_normal={x=0,y=0,z=1}
local cet_session=assert(app.transform_session:start({distance=15}))
assert(cet_session.deferred_cet==1 and cet_session.live_world_builder==0)
assert(cet.transform.position.x==17)
assert(app.transform_session:commit())
assert(env.last_world.position.x==17 and env.last_world.position.y==22,'CET entity was not refreshed at committed transform')

app.selection:set('object',b.id);env.aim_x=25
assert(app.transform_session:start({distance=20}))
events.onOverlayClose();assert(not app.transform_session:is_active());b=app.model:get_object(b.id);assert(b.transform.position.x==2,'overlay close must cancel uncommitted grab')

events.onOverlayOpen();app.model.data.settings.workspace.panel='SCENE';app.ui.compact_scene='overview';env:draw()
assert(env.labels['GRAB SELECTION##scene_grab'],'scene Grab Selection button missing')
app.selection:set_object_group({a.id,b.id},b.id,'locationstudio');assert(app.transform_session:start({distance=20}))
env:draw()
for _,label in ipairs({'YAW -##grab_header','YAW +##grab_header','COMMIT MOVE##grab_header','CANCEL MOVE##grab_header'}) do assert(env.labels[label],label..' missing from active-session header') end
assert(app.transform_session:cancel())

for _,id in ipairs({'locationstudio_grab_selection','locationstudio_commit_grab','locationstudio_cancel_grab','locationstudio_rotate_grab_left','locationstudio_rotate_grab_right'}) do assert(hotkeys[id],id..' hotkey missing') end
local report=app.diagnostics:run();assert(report.modules.transform_session and report.runtime.transform_session)
local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[transform:grab] started','[transform:grab] committed','[transform:grab] cancelled'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio reversible live Grab Move sessions: OK')
