local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.57.0')

local created,err=app.quickstart:create_first_room({location_name='Precision Layout',width=8,depth=6,height=3})
assert(created,err)
local room=created.room
assert(app.placement:spawn_room_shell(room.id))

local objects={}
for _,id in ipairs(room.shell_object_ids) do
    local object=app.model:get_object(id)
    if object and object.kind=='wall' and object.metadata.room_collision~=true then table.insert(objects,object) end
end
assert(#objects>=3)
objects={objects[1],objects[2],objects[3]}
local ids={objects[1].id,objects[2].id,objects[3].id}

objects[1].transform.position.x=0;objects[2].transform.position.x=2;objects[3].transform.position.x=10
objects[1].transform.position.z=0;objects[2].transform.position.z=1;objects[3].transform.position.z=5
objects[1].transform.rotation={roll=1,pitch=2,yaw=33}
objects[2].transform.rotation={roll=0,pitch=0,yaw=80}
objects[3].transform.rotation={roll=0,pitch=0,yaw=120}
objects[1].size={x=2,y=3,z=4};objects[2].size={x=1,y=1,z=1};objects[3].size={x=0.5,y=0.5,z=0.5}
for _,object in ipairs(objects) do assert(app.runtime_shell:update_object(object)) end

local group=assert(app.assemblies:create_group({name='Precision Set',ids=ids,active_id=objects[1].id,pivot_mode='center'}))
local distributed,warning=app.authoring:layout_object_group(ids,{operation='distribute',axis='x',active_id=objects[1].id})
assert(distributed,warning)
assert(math.abs(objects[1].transform.position.x-0)<0.0001)
assert(math.abs(objects[2].transform.position.x-5)<0.0001)
assert(math.abs(objects[3].transform.position.x-10)<0.0001)

local aligned=assert(app.authoring:layout_object_group(ids,{operation='align',axis='z',mode='max',active_id=objects[1].id}))
assert(aligned.count==3)
for _,object in ipairs(objects) do assert(math.abs(object.transform.position.z-5)<0.0001) end

assert(app.authoring:layout_object_group(ids,{operation='match_rotation',active_id=objects[1].id}))
assert(objects[2].transform.rotation.yaw==33 and objects[3].transform.rotation.pitch==2)
assert(app.authoring:layout_object_group(ids,{operation='match_scale',active_id=objects[1].id}))
for _,object in ipairs(objects) do assert(object.size.x==2 and object.size.y==3 and object.size.z==4) end

objects[1].transform.position.x=0.14;objects[2].transform.position.x=5.36;objects[3].transform.position.x=10.62
objects[2].transform.rotation.yaw=32.1
assert(app.authoring:layout_object_group(ids,{operation='snap',grid=0.25,angle=5,active_id=objects[1].id}))
assert(math.abs(objects[1].transform.position.x-0.25)<0.0001)
assert(math.abs(objects[2].transform.position.x-5.25)<0.0001)
assert(math.abs(objects[3].transform.position.x-10.5)<0.0001)
assert(objects[2].transform.rotation.yaw==30)
assert(group.pivot and group.pivot.position,'saved group pivot was not recalculated')

objects[2].locked=true
local blocked,blocked_err=app.authoring:layout_object_group(ids,{operation='align',axis='y',mode='center'})
assert(not blocked and blocked_err:find('locked',1,true))
objects[2].locked=false

local path='base\\environment\\architecture\\walls\\replacement_wall.mesh'
local asset=app.model:add_asset({
    name='Replacement Wall',category='Imported Game Resources',kind='mesh',template=path,
    metadata={world_builder={
        definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',
        resource_path=path,resource_name='replacement_wall',
        entry={name=path,fileName='replacement_wall',data={spawnData=path}},
    }},
})
local replaced,replace_warning=app.actions:replace_object_group_asset(ids,asset.id)
assert(replaced,replace_warning);assert(replaced.count==3 and #replaced.failed==0)
for _,object in ipairs(objects) do
    assert(object.template==path)
    assert(object.metadata.replacement_asset_id==asset.id)
    assert(object.metadata.world_builder.resource_path==path)
    assert(app.placement:is_tracked(object))
end

app.selection:set_object_group(ids,objects[1].id,'locationstudio')
app.model.data.settings.workspace.beginner_mode=true;app.model.data.settings.workspace.panel='SCENE'
events.onOverlayOpen();env:draw()
for _,label in ipairs({'ALIGN X##multi','ALIGN Y##multi','ALIGN Z##multi','SPACE X##multi','SPACE Y##multi','SPACE Z##multi','MATCH ROTATION##multi','MATCH SCALE##multi','SNAP SET##multi','REPLACE SET ASSET##multi'}) do
    assert(env.labels[label],label..' missing from precision layout UI')
end

print('LocationStudio precision multi-object layout and batch replacement: OK')
