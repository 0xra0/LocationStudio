local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.80.0')

local premise=assert(app.actions:create_premise_from_player('Duplicate Edit Test','exterior'))
local function wb_metadata(path,name)
    return {room_kit=true,generated=true,world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name=name,entry={name=path,fileName=name,data={spawnData=path}}}}
end
local wb=assert(app.builder:place_object({premise_id=premise.id,name='WB Original',kind='mesh',template='base\\duplicate.mesh',size={x=1,y=1,z=1},transform={position={x=2,y=3,z=1,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata=wb_metadata('base\\duplicate.mesh','duplicate')}))
assert(app.placement:spawn(wb))
assert(app:save(true));app.selection:set('object',wb.id)

local object_count=#app.model.data.objects;local undo_before=#app.model.undo_stack
local started=assert(app.transform_session:start_duplicate({offset={x=1,y=0,z=0},pivot_mode='active'}))
assert(started.active and started.kind=='edit' and started.operation=='duplicate' and started.count==1)
assert(#started.created_ids==1 and #app.model.data.objects==object_count+1)
local copy_id=started.created_ids[1];local copy=assert(app.model:get_object(copy_id))
assert(copy.id~=wb.id and copy.transform.position.x==3 and app.placement:is_tracked(copy))
assert(copy.metadata.room_kit==false and copy.metadata.generated==false and copy.metadata.detached_from_room==true)
assert(app.selection.id==copy_id and app.selection:contains_object(copy_id))
assert(app.dirty==false,'starting Duplicate Edit must not dirty the project before commit')

env.wb_remove_error=true
local blocked,blocked_err=app.transform_session:cancel()
assert(not blocked and blocked_err:find('retained the copies',1,true))
assert(app.transform_session:is_active() and app.model:get_object(copy_id),'failed cancel must keep authored ownership')
env.wb_remove_error=false
local cancelled=assert(app.transform_session:cancel())
assert(cancelled.operation=='duplicate' and not app.model:get_object(copy_id))
assert(#app.model.data.objects==object_count and #app.model.undo_stack==undo_before)
assert(app.selection.id==wb.id and app.selection:contains_object(wb.id))
assert(app.dirty==false,'cancel must restore pre-session dirty state')

local cet=assert(app.builder:place_object({premise_id=premise.id,name='CET Original',kind='prop',template='base\\duplicate.ent',size={x=1,y=1,z=1},transform={position={x=5,y=3,z=1,w=1},rotation={roll=0,pitch=0,yaw=10}}}))
assert(app.placement:spawn(cet));assert(app:save(true))
app.selection:set_object_group({wb.id,cet.id},cet.id,'locationstudio')
undo_before=#app.model.undo_stack;object_count=#app.model.data.objects
started=assert(app.transform_session:start_duplicate({offset={x=0.5,y=0,z=0},pivot_mode='center'}))
assert(started.operation=='duplicate' and started.count==2 and #started.created_ids==2)
local copy_a=assert(app.model:get_object(started.created_ids[1]));local copy_b=assert(app.model:get_object(started.created_ids[2]))
assert(app.placement:is_tracked(copy_a) and app.placement:is_tracked(copy_b))
assert(app.transform_session:adjust({dx=1,dz=0.5,dyaw=30}))
assert(wb.transform.position.x==2 and cet.transform.position.x==5,'source objects changed during duplicate edit')
assert(copy_a.transform.position.z==1.5 and copy_b.transform.position.z==1.5)
assert(env.last_world.position.z==1.5,'direct CET duplicate was not respawned at its edited transform')
local scaled,scale_err=app.transform_session:adjust({scale_factor=1.1})
assert(not scaled and scale_err:find('World Builder resources',1,true))
local committed=assert(app.transform_session:commit())
assert(committed.operation=='duplicate' and committed.changed==true and #committed.created_ids==2)
assert(#app.model.undo_stack==undo_before+1,'duplicate plus transform must be one history entry')
assert(#app.model.data.objects==object_count+2)

assert(app.actions:history('undo'))
assert(#app.model.data.objects==object_count and not app.model:get_object(copy_a.id) and not app.model:get_object(copy_b.id))
assert(app.model:get_object(wb.id) and app.model:get_object(cet.id))
assert(app.actions:history('redo'))
assert(#app.model.data.objects==object_count+2 and app.model:get_object(copy_a.id) and app.model:get_object(copy_b.id))

app.selection:set('object',wb.id);undo_before=#app.model.undo_stack
started=assert(app.transform_session:start_duplicate({offset={x=0,y=0,z=0},pivot_mode='active'}))
local created_without_move=started.created_ids[1]
committed=assert(app.transform_session:commit())
assert(committed.changed==true and app.model:get_object(created_without_move))
assert(#app.model.undo_stack==undo_before+1,'duplicate creation must be undoable even without a transform delta')
assert(app.actions:history('undo'));assert(not app.model:get_object(created_without_move))

events.onOverlayOpen();app.selection:set('object',wb.id);object_count=#app.model.data.objects
started=assert(app.transform_session:start_duplicate({offset={x=0.25,y=0,z=0}}));local overlay_copy=started.created_ids[1]
events.onOverlayClose()
assert(not app.transform_session:is_active() and not app.model:get_object(overlay_copy) and #app.model.data.objects==object_count)

events.onOverlayOpen();app.model.data.settings.workspace.panel='SCENE';app.ui.compact_scene='overview';app.selection:set('object',wb.id);env:draw()
assert(env.labels['DUPLICATE + EDIT##scene_duplicate_edit'],'Scene Duplicate Edit entry is missing')
assert(hotkeys.locationstudio_duplicate_edit,'Duplicate Edit hotkey is missing')

local bridge_started=assert(app.bridge:handle({id='duplicate-start',op='start_duplicate_transform_edit',args={ids={wb.id},active_id=wb.id,offset={x=0.25,y=0,z=0},pivot_mode='active'}}))
assert(bridge_started.operation=='duplicate' and #bridge_started.created_ids==1)
assert(app.bridge:handle({id='duplicate-cancel',op='cancel_transform_edit',args={}}))

local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[transform:duplicate] started','[transform:duplicate] adjusted','[transform:duplicate] committed','[transform:duplicate] cancel_blocked','[transform:duplicate] cancelled'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio transactional Duplicate Edit: OK')
