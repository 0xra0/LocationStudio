local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local R=assert(app.room_generator,'room generator must be constructed')
local RoomGen=getmetatable(R).__index
local model=app.model
local function close(a,b) return math.abs(a-b)<1e-6 end

-- Validation.
assert(not RoomGen.normalize({width=0.5}))
assert(not RoomGen.normalize({height=1}))
assert(not RoomGen.normalize({floor='lava'}))
assert(not RoomGen.normalize({ceiling={type='dome'}}))
assert(not RoomGen.normalize({width=4,doors={{wall='north',offset=1.8,width=1}}}),'door past the wall end')
assert(not RoomGen.normalize({height=3,windows={{wall='east',height=2,sill=1.5}}}),'window taller than the room')
assert(not RoomGen.normalize({width=6,doors={{wall='south',offset=0,width=1}},windows={{wall='south',offset=0.8,width=1}}}),'overlapping openings')
assert(not RoomGen.normalize({doors={{wall='up'}}}))
assert(not RoomGen.normalize({materials={glass='base\\glass.mi'},windows={{wall='north'}}}),'glass without a frame material')

-- Plan: geometry, portals, anchors, sockets (room frame).
local spec={name='Clinic',width=6,length=4,height=3,wall_thickness=0.2,
    doors={{wall='south',offset=-1,width=1,height=2.1}},
    windows={{wall='east',offset=0,width=1.5,height=1.2,sill=1,mullions_x=1}},
    floor={type='slab',thickness=0.2},ceiling={type='beams',beam_spacing=1.5},
    materials={floor='base\\floor.mi',walls='base\\plaster.mi',ceiling='base\\ceiling.mi',trim='base\\trim.mi',glass='base\\glass.mi'},
    lighting={anchors='grid',spacing=3}}
local plan=assert(RoomGen.plan(spec))
assert(#plan.roles.floor==1 and close(plan.roles.floor[1].size.x,6.4) and close(plan.roles.floor[1].center.z,-0.1))
-- Walls: north/west plain (1 each), south with a door (3), east with a window (4).
assert(#plan.roles.walls==9,#plan.roles.walls)
local east_len=0;for _,p in ipairs(plan.roles.walls) do if close(p.center.x,3.1) then assert(p.rotation.yaw==90);east_len=east_len+p.size.x*p.size.z end end
assert(close(east_len,4*3-1.5*1.2),'east wall area excludes the window')
-- Ceiling slab plus two beams (length 4 / spacing 1.5 -> 2 bays... floor(4/1.5)=2 -> 1 beam).
assert(#plan.roles.ceiling==2 and close(plan.roles.ceiling[1].center.z,3.1))
-- Skirting: north, east, west whole; south split around the door frame.
assert(#plan.roles.trim==5,#plan.roles.trim)
assert(#plan.roles.door_frames==3)
local glass=0;for _,p in ipairs(plan.roles.windows) do if p.material=='glass' then glass=glass+1;assert(close(p.center.x,3.1)) end end
assert(glass==1 and #plan.roles.windows==6)
assert(#plan.portals==2 and plan.portals[1].id=='door_1' and plan.portals[1].normal.y==-1 and close(plan.portals[1].center.x,-1) and close(plan.portals[1].center.y,-2.1))
assert(plan.portals[2].kind=='window' and close(plan.portals[2].center.z,1.6) and plan.portals[2].normal.x==1)
assert(#plan.anchors==2 and close(plan.anchors[1].position.x,-1.5) and close(plan.anchors[1].position.z,2.95))
local sockets={};for _,sk in ipairs(plan.sockets) do sockets[sk.id]=sk end
assert(sockets.floor_center and sockets.ceiling_center and sockets.wall_north and sockets.corner_ne and sockets.door_1 and sockets.window_1 and sockets.light_1)
assert(close(sockets.wall_north.position.y,2) and sockets.wall_north.yaw==180,'wall sockets sit on the inner face, facing in')
assert(close(sockets.corner_ne.yaw,135),'corner faces the centre: '..sockets.corner_ne.yaw)
assert(close(sockets.door_1.position.y,-2) and sockets.door_1.position.z==0 and close(sockets.window_1.position.z,1))
local raised=assert(RoomGen.plan({floor='raised',ceiling='none',lighting='none'}))
assert(#raised.roles.floor==2 and not raised.roles.ceiling and #raised.anchors==0 and close(raised.floor_top,0.15))
local coffered=assert(RoomGen.plan({width=6,length=6,ceiling={type='coffered',beam_spacing=2}}))
assert(#coffered.roles.ceiling==1+2+2)

-- Preview through the bridge.
local pv=assert(app.bridge:handle({id='p1',op='room_generator_preview',args={spec=spec}}))
assert(pv.parts.walls==9 and #pv.portals==2)

-- Create: one undo, room record with openings, pieces with collision, window blocker, lights.
local premise=model:add_premise({name='Watson Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
local T={position={x=100,y=50,z=10,w=1},rotation={roll=0,pitch=0,yaw=90}}
local history=#model.undo_stack
local objects=#model.data.objects
spec.lighting.create_lights=true
local made=assert(R:create({spec=spec,premise_id=premise.id,transform=T}))
assert(#model.undo_stack==history+1,'create is one undo step')
local room=made.room
assert(room.premise_id==premise.id and room.size.width==6 and room.size.depth==4 and #room.openings==2 and #(room.shell_object_ids or {})==0)
local rec=assert(R:get(room.id))
for _,role in ipairs({'floor','walls','ceiling','trim','door_frames','windows'}) do
    local o=assert(model:get_object(rec.piece_ids[role]),role)
    assert(o.kind=='procedural' and o.room_id==room.id and o.metadata.room_generator.role==role)
    assert(o.metadata.procedural.generator=='compound' and o.transform.rotation.yaw==90)
    assert((#o.metadata.procedural.collider_ids>0)==(role=='floor' or role=='walls' or role=='ceiling'),role..' collision')
end
assert(model:get_object(rec.piece_ids.floor).metadata.procedural.material.materials.main=='base\\floor.mi')
local win=model:get_object(rec.piece_ids.windows).metadata.procedural.material.materials
assert(win.main=='base\\trim.mi' and win.glass=='base\\glass.mi','window frames fall back to the trim material')
assert(#rec.collider_ids==1)
local blocker=model:get_object(rec.collider_ids[1])
-- Window portal centre (3.1, 0, 1.6) rotated by yaw 90 -> (0, 3.1), plus the room position.
assert(close(blocker.transform.position.x,100) and close(blocker.transform.position.y,53.1) and close(blocker.transform.position.z,11.6))
assert(#rec.light_ids==2 and model:get_object(rec.light_ids[1]).kind=='light')
local group=assert(model:get_object_group(rec.group_id))
assert(#group.object_ids>=6+1+2)
assert(#model.data.objects>objects)
assert(app.placement:is_tracked(model:get_object(rec.piece_ids.walls)),'pieces preview live')

-- Kit shell rebuilds refuse generated rooms; premise-wide rebuilds skip them.
assert(not app.builder:rebuild_room_shell(room.id))
assert(app.builder:rebuild_premise_shells(premise.id).rooms==0)

-- Sockets and snapping (world space).
local sk=assert(R:socket(room.id,'wall_north'))
-- local (0, 2, 0) with yaw 90 -> (-2, 0)
assert(close(sk.transform.position.x,98) and close(sk.transform.position.y,50) and close(sk.transform.rotation.yaw,270))
local prop=model:add_object({premise_id=premise.id,room_id=room.id,name='Cabinet',kind='entity',template='base\\cabinet.ent',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
history=#model.undo_stack
local snapped=assert(R:snap(prop.id,room.id,'wall_north',{offset_y=0.3}))
assert(#model.undo_stack==history+1)
-- Offset 0.3 along the socket's facing (+Y rotated by 270) -> +x.
assert(close(snapped.transform.position.x,98.3) and close(snapped.transform.position.y,50) and close(snapped.transform.rotation.yaw,270))
assert(not R:snap(rec.piece_ids.walls,room.id,'floor_center'),'room pieces are not snappable')
assert(not R:snap(prop.id,room.id,'nope'))

-- Regenerate: new spec, same room, one undo; failure changes nothing.
local old_walls=rec.piece_ids.walls
history=#model.undo_stack
local count=#model.data.objects
assert(not R:update(room.id,{width=0.1}))
assert(not R:update(room.id,{doors={{wall='north',offset=10}}}))
assert(#model.data.objects==count and #model.undo_stack==history and R:get(room.id).piece_ids.walls==old_walls)
local up=assert(R:update(room.id,{width=8,doors={{wall='south',offset=-1,width=1},{wall='north',offset=2,width=1.2}},lighting={anchors='center',create_lights=false}}))
assert(#model.undo_stack==history+1)
rec=R:get(room.id)
assert(not model:get_object(old_walls) and model:get_object(rec.piece_ids.walls) and rec.spec.width==8 and #rec.light_ids==0 and #rec.anchors==1)
assert(model:get_room(room.id).size.width==8 and #model:get_room(room.id).openings==3)
assert(model:get_object(prop.id),'hand-placed objects survive regeneration')
assert(model:undo() and R:get(room.id).spec.width==6,'undo restores the previous room')
rec=R:get(room.id)

-- Portal links between adjoining generated rooms.
local T2={position={x=100+2.2+2,y=50+1,z=10,w=1},rotation={roll=0,pitch=0,yaw=90}}
-- Room 1 door_1 sits at local (-1,-2.1) -> world (102.1, 49); room 2 (4 x 4) centred at (104.2, 51) with yaw 90 contains it.
local second=assert(R:create({spec={name='Office',width=4,length=4,height=3,doors={{wall='west',offset=0,width=1}}},premise_id=premise.id,transform=T2}))
rec=R:get(room.id)
assert(rec.portals[1].connects==second.room.id,'door links to the adjoining room')
assert(rec.portals[2].connects==nil,'windows do not link')

-- List and bridge.
local list=assert(app.bridge:handle({id='r1',op='room_generator_list',args={premise_id=premise.id}}))
assert(list.count==2 and list.items[1].doors==1 and list.items[1].portals==2)
assert(assert(app.bridge:handle({id='r2',op='room_generator_get',args={room_id=room.id}})).id==room.id)
assert(assert(app.bridge:handle({id='r3',op='room_generator_socket',args={room_id=room.id,socket_id='floor_center'}})).kind=='floor')
assert(assert(app.bridge:handle({id='r4',op='room_generator_update',args={room_id=second.room.id,spec={height=3.5}}})).room.size.height==3.5)
assert(assert(app.bridge:handle({id='r5',op='room_generator_snap',args={object_id=prop.id,room_id=second.room.id,socket_id='corner_sw'}})).socket=='corner_sw')

-- Delete: removes pieces, colliders, lights, group and the room; one undo.
local ids={};for _,id in pairs(rec.piece_ids) do ids[#ids+1]=id end
local collider_of_walls=model:get_object(rec.piece_ids.walls).metadata.procedural.collider_ids[1]
history=#model.undo_stack
assert(assert(app.bridge:handle({id='r6',op='room_generator_delete',args={room_id=room.id}})).deleted==room.id)
assert(#model.undo_stack==history+1 and not model:get_room(room.id) and not R:get(room.id))
for _,id in ipairs(ids) do assert(not model:get_object(id)) end
assert(not model:get_object(collider_of_walls) and not model:get_object(rec.collider_ids[1]) and not model:get_object_group(rec.group_id))
assert(model:get_object(prop.id))
assert(R:get(second.room.id).portals[1].connects==nil,'links are refreshed after delete')
assert(model:undo() and model:get_room(room.id) and R:get(room.id))

-- Deleting the room through the model drops the registry entry.
assert(model:delete_room(second.room.id) and not R:get(second.room.id))

-- Guards: an active transform session blocks changes.
local real=app.transform_session.is_active;app.transform_session.is_active=function() return true end
assert(not R:create({spec={},premise_id=premise.id,transform=T}))
app.transform_session.is_active=real

-- Authoring plan v2 op.
local plan_doc={format='locationstudio-authoring-plan',version=2,origin={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},steps={
    {op='create_premise',as='p',name='Plan Premise',kind='interior'},
    {op='create_parametric_room',as='r',premise_id='$p',offset={x=10,y=0,z=0},yaw=0,spec={name='Plan Room',width=4,length=5,doors={{wall='north',offset=0}}}}}}
local res=assert(app.authoring_plans:execute(plan_doc))
local plan_room;for _,r in ipairs(model.data.rooms) do if r.name=='Plan Room' then plan_room=r end end
assert(plan_room and R:get(plan_room.id) and close(plan_room.transform.position.x,10))
assert(not app.authoring_plans:validate({format='locationstudio-authoring-plan',version=2,steps={{op='create_parametric_room',spec={width=0.1}}}}).valid)

-- UI tab: create, select, snap, regenerate.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selected_premise_id=premise.id
local before=#model.data.generated_rooms
env.clicks['CREATE AT V##rg']=true;env:draw()
assert(#model.data.generated_rooms==before+1,'UI generated a room')
local ui_room=app.ui.spatial.rg_selected;assert(R:get(ui_room))
app.selection:set('object',prop.id)
env.clicks['SNAP##rgsk_floor_center']=true;env:draw()
local fc=assert(R:socket(ui_room,'floor_center'))
assert(close(model:get_object(prop.id).transform.position.x,fc.transform.position.x),'UI snapped the selected object')
app.ui.spatial.rg_spec='{"name":"Clinic","width":7,"length":4,"height":3}'
env.clicks['REGENERATE FROM SPEC##rg']=true;env:draw()
assert(R:get(ui_room).spec.width==7)

print('LocationStudio parametric room generator: OK')
