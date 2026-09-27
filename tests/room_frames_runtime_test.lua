local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.64.0')
assert(app.model.data.schema_version==17 and type(app.model.data.room_frames)=='table')
local frame=assert(app.bridge:handle({id='frame-create',op='wb_frame_create',args={
    name='Clinic room',origin={x=-1908,y=-2469.5,z=24},yaw=45}}))
assert(frame.name=='Clinic room' and math.abs(frame.yaw-45)<0.001)
local list=assert(app.bridge:handle({id='frame-list',op='wb_frame_list',args={}}))
assert(list.count==1 and list.frames[1].id==frame.id)
local restored=require('modules/model').new(app.util.deepcopy(app.model.data))
assert(restored.data.room_frames[1].name==frame.name and math.abs(restored.data.room_frames[1].yaw-45)<0.001)
local mapped=assert(app.bridge:handle({id='frame-to-world',op='wb_frame_to_world',args={
    frame_id=frame.id,local_position={u=1,v=0,z=2,yaw=15}}}))
assert(math.abs(mapped.transform.position.x-(-1908+math.sqrt(0.5)))<0.0001)
assert(math.abs(mapped.transform.position.y-(-2469.5+math.sqrt(0.5)))<0.0001)
assert(mapped.transform.position.z==26 and math.abs(mapped.transform.rotation.yaw-60)<0.001)
local back=assert(app.bridge:handle({id='world-to-frame',op='wb_world_to_frame',args={frame_id=frame.id,transform=mapped.transform}}))
assert(math.abs(back.position.u-1)<0.0001 and math.abs(back.position.v)<0.0001 and math.abs(back.position.z-2)<0.0001)
assert(math.abs(back.rotation.yaw-15)<0.001)
local invalid,invalid_err=app.bridge:handle({id='invalid-axes',op='wb_frame_create',args={
    name='Bad',origin={x=0,y=0},u_axis={x=1,y=0},v_axis={x=1,y=0}}})
assert(not invalid and invalid_err:find('perpendicular',1,true))
local duplicate,duplicate_err=app.bridge:handle({id='duplicate-frame',op='wb_frame_create',args={
    name='clinic ROOM',origin={x=0,y=0},yaw=0}})
assert(not duplicate and duplicate_err:find('already exists',1,true))

local premise=assert(app.actions:create_premise_from_player('Frame Placement','interior'))
local placed=assert(app.bridge:handle({id='frame-place',op='place_object_in_frame',args={
    premise_id=premise.id,frame_id=frame.id,name='Local Chair',template='base\\frame_test.ent',
    u=2,v=3,z=0.5,yaw=0,spawn=false}}))
local object=placed.object
assert(placed.frame.id==frame.id and object.metadata.local_frame.id==frame.id)
assert(math.abs(object.transform.position.x-(-1908+2*math.sqrt(0.5)-3*math.sqrt(0.5)))<0.0001)
assert(math.abs(object.transform.position.y-(-2469.5+2*math.sqrt(0.5)+3*math.sqrt(0.5)))<0.0001)
assert(object.transform.position.z==24.5 and math.abs(object.transform.rotation.yaw-45)<0.001)
local moved=assert(app.bridge:handle({id='frame-move',op='move_object_in_frame',args={
    object_id=object.id,frame_id=frame.id,u=0,v=2,z=1,yaw=90,respawn=false}}))
assert(moved.object.transform.position.z==25 and math.abs(moved.object.transform.rotation.yaw-135)<0.001)
assert(math.abs(moved.local_position.u)<0.0001 and math.abs(moved.local_position.v-2)<0.0001)
local moved_preserve=assert(app.bridge:handle({id='frame-move-preserve',op='move_object_in_frame',args={
    object_id=object.id,frame_id=frame.id,u=1,v=1,z=1,respawn=false}}))
assert(math.abs(moved_preserve.object.transform.rotation.yaw-135)<0.001,"omitted yaw should preserve the object's local yaw")
local original_world_x=moved_preserve.object.transform.position.x
assert(app.bridge:handle({id='frame-update',op='wb_frame_update',args={frame_id=frame.id,patch={origin={x=0,y=0,z=0}}}}))
assert(app.model:get_object(object.id).transform.position.x==original_world_x,'editing a frame must not move existing objects')
local deleted=assert(app.bridge:handle({id='frame-delete',op='wb_frame_delete',args={frame_id=frame.id}}))
assert(deleted.deleted and #app.model.data.room_frames==0)
print('LocationStudio Local Room Frames: OK')
