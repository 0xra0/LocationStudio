local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.72.0')

local created,err=app.quickstart:create_first_room({location_name='Multi Select',width=6,depth=5,height=3})
assert(created,err)
local room=created.room
assert(app.placement:spawn_room_shell(room.id))

local walls={}
for _,id in ipairs(room.shell_object_ids) do
    local object=app.model:get_object(id)
    if object and object.metadata.room_collision~=true and object.kind=='wall' then table.insert(walls,object) end
end
assert(#walls>=3,'room did not produce enough selectable walls')

local ids={walls[1].id,walls[2].id,walls[3].id}
local group=assert(app.selection:set_object_group(ids,walls[2].id,'locationstudio'))
assert(#group==3 and app.selection:object_count()==3 and app.selection.id==walls[2].id)
local focused=assert(app.runtime_shell:focus_many(group,walls[2].id));assert(focused.count==3)
for _,wall in ipairs(group) do assert(app.runtime_shell.handles[wall.id].selected==true) end

-- Reproduce selection made directly in World Builder's viewport/hierarchy.
app.runtime_shell:clear_focus()
app.runtime_shell.handles[walls[1].id]:setSelected(true)
app.runtime_shell.handles[walls[3].id]:setSelected(true)
assert(app.runtime_shell:sync_world_builder_selection()==true)
assert(app.selection:object_count()==2 and app.selection.group_source=='world_builder')
assert(app.selection:contains_object(walls[1].id) and app.selection:contains_object(walls[3].id))

ids={walls[1].id,walls[3].id}
local before={}
for _,wall in ipairs({walls[1],walls[3]}) do before[wall.id]={x=wall.transform.position.x,y=wall.transform.position.y,z=wall.transform.position.z,yaw=wall.transform.rotation.yaw,size=wall.size.x} end
local moved,move_warning=app.authoring:transform_object_group(ids,{dx=1,dy=2,dz=0.5,active_id=walls[1].id})
assert(moved,move_warning);assert(moved.refreshed==2)
for _,wall in ipairs({walls[1],walls[3]}) do
    assert(math.abs(wall.transform.position.x-(before[wall.id].x+1))<0.0001)
    assert(math.abs(wall.transform.position.y-(before[wall.id].y+2))<0.0001)
    assert(math.abs(wall.transform.position.z-(before[wall.id].z+0.5))<0.0001)
end

local cx=(walls[1].transform.position.x+walls[3].transform.position.x)/2
local cy=(walls[1].transform.position.y+walls[3].transform.position.y)/2
local rotated=assert(app.authoring:transform_object_group(ids,{dyaw=90,active_id=walls[1].id}))
assert(math.abs(((walls[1].transform.position.x+walls[3].transform.position.x)/2)-cx)<0.0001)
assert(math.abs(((walls[1].transform.position.y+walls[3].transform.position.y)/2)-cy)<0.0001)
assert(math.abs(walls[1].transform.rotation.yaw-(before[walls[1].id].yaw+90))<0.0001)

local old_scale=walls[1].size.x
assert(app.authoring:transform_object_group(ids,{scale_factor=1.25,active_id=walls[1].id}))
assert(math.abs(walls[1].size.x-old_scale*1.25)<0.0001)

assert(app.actions:set_object_group_state(ids,{locked=true}))
local blocked,blocked_err=app.authoring:transform_object_group(ids,{dx=1});assert(not blocked and blocked_err:find('locked',1,true))
assert(app.actions:set_object_group_state(ids,{locked=false}))
assert(app.actions:set_object_group_state(ids,{enabled=false,visible=false}))
for _,id in ipairs(ids) do local object=app.model:get_object(id);assert(not app.placement:is_tracked(object) and object.enabled==false and object.visible==false) end
assert(app.actions:set_object_group_state(ids,{enabled=true,visible=true}))
for _,id in ipairs(ids) do assert(app.placement:is_tracked(app.model:get_object(id))) end

local duplicated,duplicate_warning=app.actions:duplicate_object_group(ids,{x=0.5,y=0,z=0})
assert(duplicated,duplicate_warning);assert(duplicated.count==2 and app.selection:object_count()==2)
local copy_ids={}
for _,copy in ipairs(duplicated.objects) do
    table.insert(copy_ids,copy.id)
    assert(copy.metadata.detached_from_room==true and copy.metadata.room_kit==false,'generated duplicate was not detached')
end
local deleted=assert(app.actions:delete_object_group(copy_ids));assert(deleted.deleted==2)
for _,id in ipairs(copy_ids) do assert(app.model:get_object(id)==nil) end

-- CET entity-spawned .ent objects cannot be scaled; report this instead of
-- pretending a bounds edit changed the live entity.
local chair=assert(app.actions:place_asset('builtin_chair_poor','origin',{premise_id=created.premise.id,spawn=false}))
local mixed_ids={walls[1].id,chair.id}
assert(app.selection:set_object_group(mixed_ids,chair.id,'locationstudio'))
local scaled,scale_err=app.authoring:transform_object_group(mixed_ids,{scale_factor=1.1,active_id=chair.id})
assert(not scaled and scale_err:find('World Builder resources',1,true))

app.selection:set_object_group(ids,walls[1].id,'locationstudio')
app.model.data.settings.workspace.beginner_mode=true;app.model.data.settings.workspace.panel='SCENE'
events.onOverlayOpen();env:draw()
for _,label in ipairs({'GROUP GIZMO','DUPLICATE SET','HIDE SET','LOCK SET','DELETE SET'}) do assert(env.labels[label],label..' missing from multi-selection Inspector') end

local report=app.diagnostics:run()
assert(report.runtime.selection.object_count==2 and #report.runtime.selection.object_ids==2)
print('LocationStudio two-way World Builder and multi-object editing: OK')
