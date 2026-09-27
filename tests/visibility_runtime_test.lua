local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local vis=assert(app.visibility,'visibility module must be constructed')
local model=app.model
assert(vis:capabilities().visibility_volumes==false,'visibility volumes are reported as unsupported')

local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local function room(name,x,y,openings)
    return model:add_room({name=name,premise_id=premise.id,transform={position={x=x,y=y,z=0},rotation={yaw=0}},size={width=10,depth=10,height=3},openings=openings or {}})
end
-- A and B share the x=5 wall; aligned doors connect them. C is closed.
local A=room('Lobby',0,0,{{kind='door',wall='east',offset=0,width=1.2,height=2.2}})
local B=room('Office',10,0,{{kind='door',wall='west',offset=0,width=1.2,height=2.2}})
local C=room('Vault',0,20,{})
local function camera(name,pos,look,rotation)
    return model:add_camera({name=name,premise_id=premise.id,transform={position=pos,rotation=rotation or {roll=0,pitch=0,yaw=0}},look_at=look or {x=0,y=0,z=0},fov=60})
end
local cam_lobby=camera('Lobby cam',{x=-3,y=0,z=1.6},{x=10,y=0,z=1.6})
local cam_vault=camera('Vault outside',{x=0,y=40,z=1.6},{x=0,y=20,z=1.5})

local function visible(report,camera_id)
    local set={}
    for _,c in ipairs(report.cameras) do if c.camera_id==camera_id then for _,r in ipairs(c.visible_rooms) do set[r.name]=r end end end
    return set
end
local r=assert(vis:pvs({premise_id=premise.id}))
local seen=visible(r,cam_lobby.id)
assert(seen.Lobby and seen.Lobby.contains_camera,'the camera room is visible')
assert(seen.Office and seen.Office.visible_samples>0 and seen.Office.visible_samples<seen.Lobby.visible_samples,'Office is seen only through the door')
assert(not seen.Vault)
local lobby_cam;for _,c in ipairs(r.cameras) do if c.camera_id==cam_lobby.id then lobby_cam=c end end
assert(lobby_cam.direction_source=='look_at')
local vault_hidden;for _,h in ipairs(lobby_cam.hidden_rooms) do if h.name=='Vault' then vault_hidden=h end end
assert(vault_hidden and vault_hidden.reason)
assert(not visible(r,cam_vault.id).Vault,'a closed room is hidden from outside')
local outside;for _,c in ipairs(r.cameras) do if c.camera_id==cam_vault.id then outside=c end end
local blocked;for _,h in ipairs(outside.hidden_rooms) do if h.name=='Vault' then blocked=h end end
assert(blocked.reason=='every line of sight is blocked' and blocked.blocked_by[1]:find('Vault north',1,true))
assert(#r.rooms_never_visible==1 and r.rooms_never_visible[1].name=='Vault')
for _,room in ipairs(model.data.rooms) do for _,o in ipairs(room.openings) do assert(o._used==nil,'analysis must not modify saved openings') end end

-- A window in the vault's north wall makes it visible from outside.
table.insert(C.openings,{id='w1',kind='window',wall='north',offset=0,width=2,height=1.5,sill=0.8})
assert(visible(vis:pvs({premise_id=premise.id}),cam_vault.id).Vault,'a window opens a line of sight')
table.remove(C.openings)

-- Rotation fallback uses the game convention (yaw -90 faces +X).
local rot_cam=camera('Rotated',{x=-3,y=0,z=1.6},{x=0,y=0,z=0},{roll=0,pitch=0,yaw=-90})
local rot=assert(vis:pvs({premise_id=premise.id,camera_ids={rot_cam.id}}))
assert(rot.cameras[1].direction_source=='rotation' and visible(rot,rot_cam.id).Office,'yaw -90 looks down +X through the door')
model:delete_camera(rot_cam.id)

-- An occluder across the doorway hides the office.
-- Created without a premise: occluders block sight whatever premise they belong to.
local occ=assert(vis:create_occluder({mesh='plane_two_sided',size={x=3,y=1,z=3},transform={position={x=4.5,y=0,z=1.5,w=1},rotation={roll=0,pitch=0,yaw=90}},spawn=false}))
local od=occ.object.metadata.world_builder.entry.data
assert(od.occluderMesh==3 and od.scale.x==3 and occ.object.metadata.world_builder.definition_key=='occluder')
assert(not visible(vis:pvs({premise_id=premise.id}),cam_lobby.id).Office,'the occluder blocks the doorway')
-- A disabled occluder does not block.
occ.object.enabled=false
assert(visible(vis:pvs({premise_id=premise.id}),cam_lobby.id).Office)
occ.object.enabled=true
assert(vis:update_occluder(occ.object.id,{yaw=0}).object.transform.rotation.yaw==0)
assert(vis:update_occluder(occ.object.id,{mesh='box',size={x=1,y=3,z=3}}).object.metadata.world_builder.entry.data.occluderMesh==1)
assert(not visible(vis:pvs({premise_id=premise.id}),cam_lobby.id).Office,'a box occluder blocks regardless of yaw')
model:delete_object(occ.object.id)
assert(not vis:create_occluder({mesh='cone'}) and not vis:create_occluder({size={x=0,y=1,z=1}}))

-- Room-wall occluders cover solid spans only; the door gap stays clear.
local walls=assert(vis:occlude_room({room_id=A.id,spawn=false}))
assert(walls.count==5,'three full walls + two east spans, got '..walls.count)
local east=0;for _,o in ipairs(walls.created) do if o.metadata.occluder.room_wall.wall=='east' then east=east+1;assert(math.abs(o.size.x-4.4)<1e-6) end end
assert(east==2)
local after=assert(vis:pvs({premise_id=premise.id}))
assert(visible(after,cam_lobby.id).Office and visible(after,cam_lobby.id).Lobby,'wall occluders keep the doorway and the inside visible')
assert(after.occluder_count==5 and vis:list_occluders({premise_id=premise.id}).count==5)
assert(not vis:occlude_room({room_id='missing'}))

-- Large hidden meshes: a big mesh in the closed vault is flagged; one in the lobby is not.
local function mesh(name,x,y,dims)
    return model:add_object({premise_id=premise.id,name=name,kind='mesh',template='',transform={position={x=x,y=y,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},
        metadata={world_builder={definition_key='mesh_static',entry={data={}},apply_scale=true},asset_bounds=dims and {min={x=-dims.x/2,y=-dims.y/2,z=0},max={x=dims.x/2,y=dims.y/2,z=dims.z},source='manual'} or nil}})
end
local vault_mesh=mesh('Vault machinery',0,20,{x=8,y=6,z=2.5})
mesh('Lobby desk',0,2,{x=8,y=2,z=1.2})
mesh('Tiny vault box',1,21,{x=0.5,y=0.5,z=0.5})
mesh('Unknown mesh',0,22,nil)
vault_mesh.runtime={spawned=true,backend='world_builder'}
local hidden=assert(vis:hidden_meshes({premise_id=premise.id}))
assert(hidden.count==1 and hidden.flagged[1].id==vault_mesh.id and hidden.flagged[1].spawned)
assert(hidden.flagged[1].suggestion:find('disable',1,true) and hidden.meshes_without_bounds==1)

-- Live cross-check runs collision rays.
local live=assert(vis:pvs({premise_id=premise.id,camera_ids={cam_lobby.id},live=true}))
assert(live.cameras[1].live and #live.cameras[1].live>=1)
assert(not vis:pvs({camera_ids={'missing'}}),'no cameras in scope must fail')

-- Bridge.
assert(assert(app.bridge:handle({id='v1',op='visibility_capabilities',args={}})).occluders)
assert(assert(app.bridge:handle({id='v2',op='visibility_pvs',args={premise_id=premise.id}})).room_count==3)
assert(assert(app.bridge:handle({id='v3',op='visibility_hidden_meshes',args={premise_id=premise.id}})).count==1)
local bo=assert(app.bridge:handle({id='v4',op='visibility_create_occluder',args={mesh='box',size={x=2,y=2,z=2},source='player',spawn=false}}))
assert(assert(app.bridge:handle({id='v5',op='visibility_update_occluder',args={id=bo.object.id,patch={visualize=false}}})).object.metadata.world_builder.entry.data.previewed==false)
assert(assert(app.bridge:handle({id='v6',op='visibility_list_occluders',args={}})).count>=6)
assert(assert(app.bridge:handle({id='v7',op='visibility_occlude_room',args={room_id=C.id,spawn=false}})).count==4)

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selected_premise_id=premise.id
env.clicks['COMPUTE VISIBLE ROOMS']=true;env:draw()
assert(app.ui.spatial.vis_pvs and #app.ui.spatial.vis_pvs.cameras==2)
env.clicks['FIND HIDDEN LARGE MESHES']=true;env:draw()
assert(app.ui.spatial.vis_hidden and app.ui.spatial.vis_hidden.count>=1)
print('visibility_runtime_test: OK')
