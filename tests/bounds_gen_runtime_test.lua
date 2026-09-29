local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local Bd=assert(app.bounds_gen,'bounds generator must be constructed')
local B=getmetatable(Bd).__index
local P=app.procedural
local model=app.model
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-6) end
local function box(c,s,r) return {shape='box',center={x=c[1],y=c[2],z=c[3]},size={x=s[1],y=s[2],z=s[3]},rotation=r or {roll=0,pitch=0,yaw=0}} end

-- Exact part extents.
local b=B.part_bounds(box({0,0,0},{2,2,2},{roll=0,pitch=0,yaw=45}))
assert(close(b.max.x,math.sqrt(2)) and close(b.max.z,1),'rotated box')
b=B.part_bounds({shape='cylinder',center={x=1,y=0,z=0},radius=0.5,length=2,rotation={roll=0,pitch=0,yaw=0}})
assert(close(b.min.x,0.5) and close(b.max.y,1) and close(b.max.z,0.5),'cylinder along +Y')
b=B.part_bounds({shape='cylinder',center={x=0,y=0,z=0},radius=0.5,length=2,rotation={roll=0,pitch=90,yaw=0}})
assert(close(b.max.z,1) and close(b.max.y,0.5),'pitched up: the axis turns to Z')
b=B.part_bounds({shape='cylinder',center={x=0,y=0,z=0},radius=1,length=2,rotation={roll=0,pitch=0,yaw=45}})
assert(close(b.max.x,math.sqrt(0.5)+math.sqrt(0.5)),'exact, not the rotated square box: '..b.max.x)
b=B.part_bounds({shape='sphere',center={x=0,y=0,z=2},radius=1})
assert(close(b.min.z,1) and close(b.max.x,1))
b=B.part_bounds({shape='wedge',center={x=0,y=0,z=0},size={x=1,y=2,z=1},rotation={roll=0,pitch=0,yaw=0}})
assert(close(b.max.z,0.5) and close(b.min.y,-1))
b=B.part_bounds({shape='prism',points={{x=0,y=0},{x=3,y=0},{x=0,y=2}},z0=-1,z1=1})
assert(close(b.max.x,3) and close(b.min.z,-1))

-- Distances.
local s=Bd:settings()
assert(s.min_screen_angle==1 and s.min_range==30 and s.max_range==800)
local vis,range,sec=B.distances(2,s,nil)
assert(close(vis,2/math.tan(math.rad(0.5))) and close(range,vis+10) and close(sec,range*1.2))
vis,range=B.distances(0.05,s,nil);assert(vis==30 and range==40,'clamped to min_range')
vis,range=B.distances(100,s,nil);assert(vis==800 and range==800,'clamped to max_range')
local _,manual=B.distances(2,s,75);assert(manual==75)

-- A procedural object gets its bounds on create.
local premise=model:add_premise({name='Yard',kind='exterior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
local T={position={x=10,y=20,z=5,w=1},rotation={roll=0,pitch=0,yaw=90}}
local wall=assert(P:create({generator='box',params={size={4,0.2,3}},transform=T,collision=true,material={template='base\\a.mesh'}}))
local rec=assert(wall.object.metadata.generated_bounds)
assert(rec.kind=='procedural' and rec.exact and close(rec['local'].extents.x,2) and close(rec['local'].min.z,0))
-- Yaw 90 turns local x onto world y.
assert(close(rec.world.min.y,18) and close(rec.world.max.y,22) and close(rec.world.min.x,9.9) and close(rec.world.max.z,8))
assert(close(rec.sphere.radius,math.sqrt(4+0.01+2.25)) and close(rec.sphere.center.z,6.5))
assert(rec.streaming.source=='auto' and close(rec.streaming.range,B.distances(rec.sphere.radius,s,nil)+10) and rec.streaming.cell_count==1)
assert(rec.collision and rec.collision.count==1 and close(rec.collision.min.y,18) and close(rec.collision.max.z,8),'collision bounds from the generated collider')
assert(rec.visibility.render and close(rec.visibility.distance,B.distances(rec.sphere.radius,s,nil)))
local collider=model:get_object(wall.object.metadata.procedural.collider_ids[1])
assert(collider.metadata.generated_bounds.kind=='collider' and close(collider.metadata.generated_bounds.world.max.y,22))
assert(wall.object.metadata.asset_bounds.source=='procedural')

-- Moving the object: get() recomputes.
wall.object.transform.position.x=50
local moved=assert(Bd:get(wall.object.id))
assert(moved.refreshed and close(moved.world.min.x,49.9) and close(model:get_object(wall.object.id).metadata.generated_bounds.world.min.x,49.9))
assert(not Bd:get(wall.object.id).refreshed,'a fresh record is not recomputed')

-- Tilted geometry: world_aabb uses the procedural rotation convention.
local tilt=assert(P:create({generator='box',params={size={4,0.2,1},anchor='center'},transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=90,yaw=0}},material={template='base\\a.mesh'}}))
local aabb=assert(app.asset_bounds:world_aabb(tilt.object.id))
assert(aabb.source=='generated')
-- Pitch rotates about X: local y (0.2) goes to z and local z goes to -y.
local lb=tilt.object.metadata.generated_bounds['local']
assert(close(aabb.aabb.max.z-aabb.aabb.min.z,0.2) and close(aabb.aabb.max.y-aabb.aabb.min.y,lb.max.z-lb.min.z) and close(aabb.aabb.max.x,2))

-- Manual stream range.
assert(P:update(tilt.object.id,{stream_range=20}))
rec=model:get_object(tilt.object.id).metadata.generated_bounds
assert(rec.streaming.source=='manual' and rec.streaming.range==20 and close(rec.streaming.secondary_range,24))

-- CSG with curved leaves: approximate, but contains the solid.
local arch=assert(P:create({generator='csg',params={resolution=0.5,tree={op='union',children={{shape='cylinder',center={0,0,1},radius=1,length=0.3}}}},
    transform={position={x=0,y=100,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},material={template='base\\a.mesh'}}))
rec=arch.object.metadata.generated_bounds
assert(rec.exact==false and rec['local'].min.x>=-1-1e-9 and rec['local'].max.z<=2+1e-9 and rec['local'].max.x>=0.99,'within the tree bounds, covering the solid')

-- Settings: validated, one undo step, used by new records.
assert(not Bd:set_settings({min_screen_angle=0}) and not Bd:set_settings({min_range=900}) and not Bd:set_settings({colour=1}))
local h=#model.undo_stack
assert(Bd:set_settings({min_screen_angle=2,cell_size=8}).cell_size==8 and #model.undo_stack==h+1)
local r=Bd:refresh({premise_id=premise.id});assert(r.updated==4 and #r.errors==0,'refresh '..json.encode(r))
rec=model:get_object(wall.object.id).metadata.generated_bounds
assert(rec.streaming.cell_size==8 and rec.streaming.cell_count>=1)
assert(close(rec.visibility.distance,math.max(30,rec.sphere.radius/math.tan(math.rad(1)))))

-- Preflight: pop-in and multi-cell notes.
local long=assert(P:create({generator='box',params={size={20,1,1}},transform={position={x=0,y=-50,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},stream_range=5,material={template='base\\a.mesh'}}))
local check;for _,c in ipairs(app.preflight:run({}).checks) do if c.id=='generated_bounds' then check=c end end
local pop,cellsnote=false,false
for _,i in ipairs(check.issues) do
    if i.object_id==long.object.id and i.message:find('pop in',1,true) then pop=true;assert(i.severity=='warning') end
    if i.object_id==long.object.id and i.message:find('streaming cells',1,true) then cellsnote=true end
end
assert(pop and cellsnote and check.status=='warn')

-- Parametric room: room bounds from its pieces.
local room=assert(app.room_generator:create({spec={name='Box',width=4,length=3,height=3},premise_id=premise.id,transform={position={x=200,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local gr=app.room_generator:get(room.room.id)
assert(gr.bounds and gr.bounds.pieces>=3 and gr.bounds.world.min.x<198 and gr.bounds.world.max.z>=3 and gr.bounds.collision.count>=3)
local rb=assert(Bd:room_bounds(room.room.id));assert(close(rb.world.max.x,gr.bounds.world.max.x))
assert(not Bd:room_bounds('nope'))

-- Visibility: generated meshes are considered by hidden-mesh checks.
local vis_ok=pcall(function() return app.visibility and app.visibility:hidden_meshes({premise_id=premise.id}) end);assert(vis_ok)

-- Bridge.
local g=assert(app.bridge:handle({id='b1',op='bounds_get',args={object_id=wall.object.id}}));assert(g.world and g.streaming)
assert(assert(app.bridge:handle({id='b2',op='bounds_get',args={room_id=room.room.id}})).pieces>=3)
assert(assert(app.bridge:handle({id='b3',op='bounds_refresh',args={premise_id=premise.id}})).updated>=4)
assert(assert(app.bridge:handle({id='b4',op='bounds_settings',args={}})).cell_size==8)
assert(assert(app.bridge:handle({id='b5',op='bounds_settings',args={cell_size=64}})).cell_size==64)
assert(not app.bridge:handle({id='b6',op='bounds_get',args={object_id=premise.id}}))

-- UI.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selection:set('object',wall.object.id)
env:draw()
env.clicks['REFRESH ALL##bd']=true;env:draw()

print('LocationStudio bounds generator: OK')
