local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.81.0')

local created,err=app.quickstart:create_first_room({location_name='Director Location',room_name='Stage',width=6,depth=5,height=3})
assert(created,err);local premise,room=created.premise,created.room
assert(app.placement:spawn_room_shell(room.id))
local chair=assert(app.actions:place_asset('builtin_chair_poor','origin',{premise_id=premise.id,room_id=room.id,transform={position={x=11,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},spawn=true}))
local table_object=assert(app.actions:place_asset('builtin_table_lab','origin',{premise_id=premise.id,room_id=room.id,transform={position={x=12,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},spawn=true}))

local captured=assert(app.scenes:capture_premise({name='Director Scene',premise_id=premise.id}))
local scene=captured.scene
assert(#scene.room_ids==1 and #scene.object_ids==2)
for _,id in ipairs(scene.object_ids) do assert(not (app.model:get_object(id).metadata or {}).room_kit,'room-kit construction duplicated into explicit scene objects') end
assert(app.editing_scene_id==scene.id)

-- The editing scene must remain remembered while object selection changes.
app.selection:set('object',table_object.id);assert(app.editing_scene_id==scene.id)
assert(app.scenes:edit_current_selection(scene.id,'remove'));assert(#scene.object_ids==1 and app.model:get_object(table_object.id))
assert(app.scenes:edit_current_selection(scene.id,'add'));assert(#scene.object_ids==2)
local duplicate_add=assert(app.scenes:edit_current_selection(scene.id,'add'));assert(duplicate_add.counts.object_ids==2)

local volume=assert(app.authoring:create_volume({premise_id=premise.id,room_id=room.id,name='Director Trigger',shape='box',size_x=2,size_y=2,size_z=2}))
app.selection:set('volume',volume.id);assert(app.scenes:edit_current_selection(scene.id,'add'));assert(scene.volume_ids[1]==volume.id)
local point=app.model:add_location({name='Director Point',type='scene',transform=premise.transform});app.selection:set('location',point.id);assert(app.scenes:edit_current_selection(scene.id,'add'));assert(scene.location_ids[1]==point.id)

local selected=assert(app.scenes:select_objects(scene.id));assert(selected.selected==2 and app.selection:object_count()==2)
local activated,activate_warning=app.scenes:activate(scene.id,true);assert(activated,activate_warning);assert(activated.activated and app.live_scene_id==scene.id)
for _,id in ipairs(assert(app.scenes:member_object_ids(scene))) do assert(app.placement:is_tracked(assert(app.model:get_object(id)))) end

local outsider=assert(app.actions:place_asset('builtin_crates_stack','origin',{premise_id=premise.id,room_id=room.id,transform={position={x=14,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},spawn=true}))
assert(app.placement:is_tracked(outsider))
local isolated,isolate_warning=app.scenes:isolate(scene.id);assert(isolated,isolate_warning);assert(isolated.isolated and #isolated.hidden==1 and not app.placement:is_tracked(outsider))

env.wb_remove_error=true
local partial,partial_err=app.scenes:deactivate(scene.id);assert(partial and not partial.deactivated and partial_err:find('refused',1,true));assert(app.live_scene_id==scene.id)
env.wb_remove_error=false
local deactivated,deactivate_warning=app.scenes:deactivate(scene.id);assert(deactivated,deactivate_warning);assert(deactivated.deactivated and app.live_scene_id==nil)
for _,id in ipairs(assert(app.scenes:member_object_ids(scene))) do assert(not app.placement:is_tracked(assert(app.model:get_object(id)))) end

local sync=assert(app.scenes:capture_premise({scene_id=scene.id,premise_id=premise.id,mode='replace'}));assert(sync.id==scene.id and #scene.object_ids==3 and scene.volume_ids[1]==volume.id and scene.location_ids[1]==point.id)

local bridge_status=assert(app.bridge:handle({id='scene-status',op='get_scene_status',args={}}));assert(bridge_status.editing_scene_id==scene.id)
assert(app.bridge:handle({id='scene-edit',op='edit_scene_members',args={id=scene.id,mode='remove',object_ids={outsider.id}}}))
assert(#scene.object_ids==2 and app.model:get_object(outsider.id))
assert(app.bridge:handle({id='scene-capture',op='capture_scene_from_premise',args={scene_id=scene.id,premise_id=premise.id,mode='replace'}}))
assert(app.bridge:handle({id='scene-activate',op='activate_scene',args={id=scene.id}}).activated)
assert(app.bridge:handle({id='scene-deactivate',op='deactivate_scene',args={id=scene.id}}).deactivated)

local protected_scene=assert(app.scenes:create({name='Protected Live Scene',premise_id=premise.id,room_ids={room.id}}));assert(app.scenes:activate(protected_scene.id,true).activated)
env.wb_remove_error=true;local blocked_delete,blocked_delete_err=app.scenes:delete(protected_scene.id);assert(not blocked_delete and blocked_delete_err:find('refused',1,true) and app.model:get_scene(protected_scene.id))
env.wb_remove_error=false;assert(app.scenes:delete(protected_scene.id));assert(not app.model:get_scene(protected_scene.id) and app.model:get_room(room.id))

local plan={format='locationstudio-authoring-plan',version=1,name='Captured Scene Plan',origin='player',steps={
    {op='create_premise',as='plan_place',name='Plan Location'},
    {op='create_room',as='plan_room',premise_id='$plan_place',name='Plan Room',width=4,depth=4,height=3,spawn=true},
    {op='place_asset',as='plan_prop',asset_id='builtin_case_military',premise_id='$plan_place',room_id='$plan_room',offset={x=0,y=0,z=0},spawn=true},
    {op='capture_scene',as='plan_scene',name='Captured Plan Scene',premise_id='$plan_place',activate=true},
}}
local plan_validation=app.authoring_plans:validate(plan);assert(plan_validation.valid,table.concat(plan_validation.errors or {},'; '))
local plan_result,plan_warning=app.authoring_plans:execute(plan);assert(plan_result,plan_warning);assert(app.model:get_scene(plan_result.aliases.plan_scene))

app.model.data.settings.workspace.beginner_mode=true;app.model.data.settings.workspace.panel='SCENE'
events.onOverlayOpen();env:draw()
for _,label in ipairs({'NEW FROM LOCATION','NEW FROM SELECTED','ACTIVATE','ISOLATE','DEACTIVATE','ADD CURRENT SELECTION','REMOVE CURRENT SELECTION','SYNC LOCATION CONTENT'}) do assert(env.labels[label],label..' missing from Scene Director') end
for _,id in ipairs({'locationstudio_activate_editing_scene','locationstudio_isolate_editing_scene','locationstudio_deactivate_live_scene','locationstudio_add_selection_to_scene'}) do assert(type(hotkeys[id])=='function',id..' hotkey missing') end

local report=app.diagnostics:run();assert(report.runtime.scenes.editing_scene_id and report.runtime.scenes.live_scene_id)
local mcp=assert(io.open('mcp_server/server.py','r'));local mcp_text=mcp:read('*a');mcp:close()
for _,needle in ipairs({'def capture_scene_from_premise(','def edit_scene_members(','def deactivate_scene(','def isolate_scene(','def get_scene_status('}) do assert(mcp_text:find(needle,1,true),needle..' missing from MCP server') end
local log=assert(io.open('logs/locationstudio.log','r'));local log_text=log:read('*a');log:close()
for _,needle in ipairs({'[scene] premise_captured','[scene] members_edited','[scene] isolated','[scene] deactivate_failed','[scene] deactivated'}) do assert(log_text:find(needle,1,true),needle..' missing from scene log') end

print('LocationStudio Scene Director membership and runtime lifecycle: OK')
