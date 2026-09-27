local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.62.0')

local created,err=app.quickstart:create_first_room({location_name='Construction Editor',width=5,depth=4,height=3})
assert(created,err)
local room=created.room
assert(app.placement:spawn_room_shell(room.id))

local function first_piece(role)
    for _,id in ipairs(room.shell_object_ids) do
        local object=app.model:get_object(id)
        if object and object.metadata.room_collision~=true and (object.metadata.role or object.kind)==role then return object end
    end
end

local wall=assert(first_piece('wall'))
local other=assert(first_piece('floor'))
local other_path=other.metadata.world_builder.resource_path
assert(app.runtime_shell:focus(wall))
assert(env.wb_selected==app.runtime_shell.handles[wall.id] and env.wb_selected.selected==true,'World Builder selection was not synchronized')
local wall_handle=app.runtime_shell.handles[wall.id]
wall_handle.position={x=42,y=43,z=44,w=1};wall_handle.rotation={roll=1,pitch=2,yaw=3};wall_handle.scale={x=1.2,y=1.3,z=1.4}
local synchronized=assert(app.runtime_shell:sync_from_handle(wall));assert(synchronized.changed==true)
assert(wall.transform.position.x==42 and wall.transform.rotation.yaw==3 and wall.size.z==1.4,'gizmo transform did not synchronize back into the project')

local custom=app.model:add_asset({name='Replacement Wall',kind='mesh',template='base\\custom\\replacement_wall.mesh',metadata={world_builder={definition_key='mesh_static',category='Mesh',variant='Mesh',module_path='mesh/mesh',resource_name='replacement_wall',resource_path='base\\custom\\replacement_wall.mesh',apply_scale=true,entry={name='base\\custom\\replacement_wall.mesh',fileName='replacement_wall',data={spawnData='base\\custom\\replacement_wall.mesh'}}}}})
assert(app.selection:set('asset',custom.id));assert(app.last_asset_id==custom.id)
assert(app.selection:set('object',wall.id));assert(app.selected_asset_id==nil and app.last_asset_id==custom.id,'last selected asset was not preserved')
local replaced,warning=app.builder:replace_shell_object_asset(wall.id,app.last_asset_id)
assert(replaced,warning);assert(replaced.metadata.world_builder.resource_path==custom.template)
assert(other.metadata.world_builder.resource_path==other_path,'replacing one piece changed an unrelated surface')

local state=assert(app.builder:set_construction_state(created.premise.id,room.id,'wall',{locked=true}))
assert(state.matched>0 and wall.locked==true)
local focused,focus_err=app.runtime_shell:focus(wall);assert(not focused and focus_err:find('locked',1,true))
local moved,move_err=app.authoring:set_transform('object',wall.id,wall.transform,false)
assert(not moved and move_err:find('locked',1,true))
app.selection:set('object',wall.id)
local deleted,delete_err=app.actions:delete_selected();assert(not deleted and delete_err:find('locked',1,true))
assert(app.builder:set_construction_state(created.premise.id,room.id,'wall',{locked=false}))

local old_shell_count=#room.shell_object_ids
local detached=assert(app.builder:detach_shell_object(wall.id))
assert(detached.metadata.detached_from_room==true and detached.metadata.room_kit==false and detached.metadata.generated==false)
assert(#room.shell_object_ids==old_shell_count-1)
local rebuilt=assert(app.builder:rebuild_room_shell(room.id))
assert(app.model:get_object(detached.id)==detached,'detached piece was erased by room rebuild')

local generated=assert(first_piece('wall'))
app.selection:set('object',generated.id)
local duplicate=assert(app.actions:duplicate_selected())
assert(duplicate.metadata.detached_from_room==true and duplicate.metadata.room_kit==false,'duplicate remained tied to generated shell ownership')

local hidden=assert(app.builder:set_construction_state(created.premise.id,room.id,'wall',{enabled=false}))
assert(hidden.changed>0)
for _,object in ipairs(app.builder:construction_objects(created.premise.id,room.id,'wall',false)) do
    assert(object.enabled==false and object.visible==false and not app.placement:is_tracked(object))
end
local shown,show_warning=app.builder:set_construction_state(created.premise.id,room.id,'wall',{enabled=true})
assert(shown,show_warning)
for _,object in ipairs(app.builder:construction_objects(created.premise.id,room.id,'wall',false)) do
    assert(object.enabled==true and object.visible==true and app.placement:is_tracked(object))
end

local tracked=assert(first_piece('wall'));local tracked_id=tracked.id
local before=#room.shell_object_ids
assert(app.model:delete_object(tracked_id))
assert(#room.shell_object_ids==before-1)
for _,id in ipairs(room.shell_object_ids) do assert(id~=tracked_id,'deleted object left a stale room shell ID') end

local visible_piece=assert(first_piece('floor'))
app.selection:set('object',visible_piece.id)
app.model.data.settings.workspace.beginner_mode=true;app.model.data.settings.workspace.panel='SCENE'
events.onOverlayOpen();env:draw()
local construction_group=false
for label in pairs(env.labels) do if label:find('CONSTRUCTION',1,true) then construction_group=true;break end end
assert(construction_group,'construction hierarchy was not rendered in Simple UI')
assert(env.labels['WORLD BUILDER GIZMO'],'construction inspector did not expose the working gizmo action')
assert(env.labels['DETACH / MAKE UNIQUE'],'construction inspector did not expose detach')

local issues=app.model:validate()
for _,issue in ipairs(issues) do assert(not (issue.id and issue.message=='Enabled object has no spawn template' and app.model:get_object(issue.id) and app.model:get_object(issue.id).metadata.world_builder),'World Builder piece produced a false missing-template warning') end

print('LocationStudio construction selection / lock / replace / detach / visibility: OK')
