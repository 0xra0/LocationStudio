local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.68.0')
assert(app.model.data.schema_version==20)

local created,err=app.quickstart:create_first_room({location_name='Assembly Test',width=7,depth=6,height=3})
assert(created,err)
local room=created.room
assert(app.placement:spawn_room_shell(room.id))

local walls={}
for _,id in ipairs(room.shell_object_ids) do
    local object=app.model:get_object(id)
    if object and object.kind=='wall' and object.metadata.room_collision~=true then table.insert(walls,object) end
end
assert(#walls>=3,'room kit did not produce three editable mesh walls')

local parent=assert(app.assemblies:create_group({name='Exterior',ids={walls[3].id},active_id=walls[3].id,pivot_mode='active'}))
local child=assert(app.assemblies:create_group({name='Door Assembly',ids={walls[1].id,walls[2].id},active_id=walls[1].id,pivot_mode='center',parent_id=parent.id}))
assert(child.parent_id==parent.id)
local recursive=assert(app.assemblies:objects_for_group(parent.id,true))
assert(#recursive==3,'nested group selection did not include child objects')
assert(app.assemblies:select_group(parent.id,true,false).count==3)

-- Cycles must be rejected instead of corrupting the outliner tree.
local cycle,cycle_err=app.assemblies:update_group(parent.id,{parent_id=child.id})
assert(not cycle and cycle_err:find('cycle',1,true))

local prefab=assert(app.assemblies:save_prefab({
    name='Reusable Door Assembly',ids={walls[1].id,walls[2].id},active_id=walls[1].id,pivot_mode='center',source_group_id=child.id,
}))
assert(#prefab.objects==2)
for _,object in ipairs(prefab.objects) do
    assert(object.metadata.room_kit==false and object.metadata.generated==false)
    assert(type(object.metadata.world_builder)=='table','World Builder resource definition was not preserved')
end

-- Render real live-prefab members to a persisted thumbnail, then prove the
-- temporary WB instances were removed and no authored objects were added.
local Util=require('modules/util')
local old_execute=os.execute;local object_count_before=#app.model.data.objects
local function handle_count() local n=0;for _ in pairs(app.runtime_shell.handles) do n=n+1 end;return n end
local handle_count_before=handle_count()
app.thumbnails._capture_backend=function(_,path,delay) assert(delay>=1);return 'mock-capture '..path,'test-helper' end
os.execute=function() return 0 end
local render_request,render_warning=app.thumbnails:render_prefab(prefab.id,{distance=10});assert(render_request and render_request.pending,render_warning)
assert(not app.editor_visible,'editor overlay must hide while game screenshot is captured')
assert(Util.write_file(render_request.path,string.rep('valid-mock-png-',12)))
local rendered,render_err=app.thumbnails:update(os.clock());assert(rendered and rendered.prefab_id==prefab.id,render_err)
assert(app.editor_visible and #app.model.data.objects==object_count_before,'render must restore UI and not author preview objects')
assert(app.model:get_object_prefab(prefab.id).thumbnail_captured_at~='')
assert(handle_count()==handle_count_before,'preview must not retain temporary World Builder handles')
assert(app.thumbnails:has_prefab(prefab),'saved prefab thumbnail was not registered')
os.execute=old_execute

local target={position={x=100,y=200,z=10,w=1},rotation={roll=0,pitch=0,yaw=90}}
local instance,warning=app.assemblies:instantiate_prefab(prefab.id,{
    premise_id=created.premise.id,room_id=room.id,transform=target,spawn=true,group_name='Door Instance',
})
assert(instance,warning)
assert(instance.count==2 and #instance.failed==0)
assert(instance.group.pivot_mode=='custom' and instance.group.name=='Door Instance')
assert(app.selection:object_count()==2)
for index,object in ipairs(instance.objects) do
    local local_position=prefab.objects[index].transform.position
    assert(math.abs(object.transform.position.x-(target.position.x-local_position.y))<0.0001)
    assert(math.abs(object.transform.position.y-(target.position.y+local_position.x))<0.0001)
    assert(math.abs(object.transform.position.z-(target.position.z+local_position.z))<0.0001)
    assert(object.metadata.prefab_source==prefab.id and object.metadata.prefab_instance==true)
    assert(app.placement:is_tracked(object),'prefab object was not submitted to the live runtime')
end

local before_x=instance.group.pivot.position.x
local transformed,transform_warning=app.assemblies:transform_group(instance.group.id,{dx=1,dy=0,dz=0,dyaw=15})
assert(transformed,transform_warning)
assert(math.abs(instance.group.pivot.position.x-(before_x+1))<0.0001)
assert(math.abs(instance.group.pivot.rotation.yaw-105)<0.0001)

local dissolved=assert(app.assemblies:dissolve_group(instance.group.id))
assert(dissolved.objects_released==2 and app.model:get_object_group(instance.group.id)==nil)
for _,object in ipairs(instance.objects) do assert(app.model:get_object(object.id),'dissolving a group deleted an object') end

app.model.data.settings.workspace.beginner_mode=true
app.model.data.settings.workspace.panel='SCENE'
events.onOverlayOpen();env:draw()
assert(env.labels['CREATE GROUP##scene_group_create'])
assert(env.labels['SAVE PREFAB##scene_prefab_save'])
assert(env.labels['AT PLAYER##prefab_player_'..prefab.id])
assert(env.labels['AT AIM##prefab_aim_'..prefab.id])

local report=app.diagnostics:run()
assert(report.modules.assemblies==true)
assert(report.project.object_groups>=2 and report.project.object_prefabs==1)
assert(#app.model:validate()>=0)
print('LocationStudio persistent groups and real-resource prefabs: OK')
