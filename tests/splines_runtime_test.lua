local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local S=assert(app.splines,'spline editor must be constructed')
local model=app.model
assert(model.data.schema_version==20 and type(model.data.splines)=='table')
local function near(a,b,eps) return math.abs(a-b)<=(eps or 1e-6) end
local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end

local premise=model:add_premise({name='Street',kind='exterior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id

-- Linear open spline: exact length, arc-length sampling, tangent yaw.
local line=assert(S:create({name='Line',mode='linear',points={{x=0,y=0,z=0},{x=10,y=0,z=0}}}))
assert(near(S:length(line),10,1e-6))
local s=assert(S:sample(line.id,{spacing=2}))
assert(s.count==6 and near(s.points[3].position.x,4,1e-3) and near(s.points[6].position.x,10,1e-6) and near(s.points[2].yaw,0,1e-6))
assert(assert(S:sample(line.id,{count=3})).points[2].position.x>4.99)
assert(not S:sample(line.id,{spacing=0.001}) and not S:sample(line.id,{start_offset=6,end_offset=6}))

-- Closed linear square: 40 m, no duplicated end sample, 90° turns.
local square=assert(S:create({name='Square',mode='linear',closed=true,points={{x=0,y=0,z=0},{x=10,y=0,z=0},{x=10,y=10,z=0},{x=0,y=10,z=0}}}))
assert(near(S:length(square),40,1e-6))
local sq=assert(S:sample(square.id,{spacing=5}));assert(sq.count==8,'closed curves do not repeat the start sample, got '..sq.count)
assert(near(sq.points[4].yaw,90,1e-6) and near(sq.points[6].yaw,180,1e-6),'mid-side samples follow each side')

-- Auto tangents: smooth curve longer than its chords, tangent at a middle point parallel to its neighbours.
local curve=assert(S:create({name='Curve',points={{x=0,y=0,z=0},{x=10,y=5,z=0},{x=20,y=0,z=0}}}))
local chord=math.sqrt(125)*2
assert(S:length(curve)>chord)
local h=S:handles(curve)[2];assert(near(h.hout.y,0,1e-9) and h.hout.x>0 and near(h.hin.x,-h.hout.x,1e-9),'auto tangent follows next-prev')
local ten=S:length(curve);assert(S:update(curve.id,{tension=0}));assert(S:length(curve)<ten,'zero tension straightens the curve')
assert(S:update(curve.id,{tension=0.5}))

-- Aligned handles stay collinear; free handles are independent; linear removes handles.
assert(S:update_point(curve.id,2,{mode='aligned'}))
local before=S:handles(curve)[2]
local after=assert(S:update_point(curve.id,2,{handle_out={x=0,y=4,z=0}})).point
assert(after.mode=='aligned' and near(after.handle_in.x,0,1e-9) and after.handle_in.y<0 and near(math.abs(after.handle_in.y),math.abs(before.hin.x),1e-6))
assert(S:update_point(curve.id,2,{mode='free',handle_in={x=-1,y=-1,z=0}}).point.handle_out.y==4,'free handles do not mirror')
assert(S:update_point(curve.id,1,{handle_out={x=3,y=0,z=0}}).point.mode=='free','setting a handle on an auto point makes it free')
assert(S:update_point(curve.id,2,{mode='linear'}))
local lh=S:handles(curve)[2];assert(near(lh.hin.x,0) and near(lh.hout.y,0))
assert(not S:update_point(curve.id,2,{mode='bent'}) and not S:update_point(curve.id,9,{mode='free'}))

-- Point editing: add at aim, insert on the curve, move, delete, open/close.
env.aim_x,env.aim_y,env.aim_z=30,0,0
local added=assert(S:add_point(curve.id,{source='aim'}));assert(added.index==4 and curve.points[4].position.x==30)
local old_points=assert(S:sample(curve.id,{count=50})).points
local ins=assert(S:insert_at_distance(curve.id,5));assert(#curve.points==5 and ins.index==2)
local closest=math.huge;for _,q in ipairs(old_points) do closest=math.min(closest,dist(q.position,ins.point.position)) end
assert(closest<0.5,'inserted point lies on the previous curve')
assert(S:update_point(curve.id,5,{position={x=30,y=3,z=0}}).point.position.y==3)
assert(not S:update(line.id,{closed=true}),'closing needs three points')
assert(S:delete_point(square.id,4));assert(S:get(square.id).closed==true)
assert(S:delete_point(square.id,3));assert(S:get(square.id).closed==false,'closed spline with fewer than three points reopens')

-- Use: distribute assets along the curve, aligned to the tangent.
local chair=model:get_asset('builtin_chair_poor')
local rowline=assert(S:create({name='Row',mode='linear',points={{x=0,y=50,z=0},{x=0,y=60,z=0}}}))
local dist_use=assert(S:apply_use(rowline.id,'distribute',{asset_id=chair.id,spacing=2.5,spawn=false,lateral_offset=1}))
local ids=dist_use.use.outputs.object_ids;assert(#ids==5)
local first=model:get_object(ids[1]);assert(near(first.transform.rotation.yaw,90,1e-6) and near(first.transform.position.x,-1,1e-6),'aligned and offset to the left of travel')
assert(first.metadata.spline_use.spline_id==rowline.id)
-- Editing the curve and regenerating replaces the outputs as one undo step.
assert(S:update_point(rowline.id,2,{position={x=0,y=70,z=0}}))
local undo_depth=#model.undo_stack
local regen=assert(S:regenerate(rowline.id));assert(regen.count==1 and #model.undo_stack==undo_depth+1)
rowline=S:get(rowline.id)
local new_ids=rowline.uses[1].outputs.object_ids;assert(#new_ids==9 and not model:get_object(ids[1]),'old outputs are replaced')
assert(model:undo());assert(model:get_object(ids[1]) and #S:get(rowline.id).uses[1].outputs.object_ids==5,'undo restores the previous outputs')
assert(model:redo())

-- Use: cable/fence/road through the generators (one undo step, tagged objects).
local mesh=model:add_asset({name='Cable Mesh',kind='mesh',template='base\\cable.mesh',size={x=1,y=1,z=1},metadata={
    asset_bounds={min={x=-1,y=-0.1,z=0},max={x=1,y=0.1,z=0.2},units='m'},
    world_builder={definition_key='mesh_static',category='Mesh',variant='Mesh',module_path='mesh/mesh',apply_scale=true,resource_name='cable',resource_path='base\\cable.mesh',
        entry={name='base\\cable.mesh',fileName='cable',data={spawnData='base\\cable.mesh'}}}}})
curve=S:get(curve.id)
local depth=#model.undo_stack
local cable=assert(S:apply_use(curve.id,'cable',{asset_id=mesh.id,segment_length=2,spawn=false}))
assert(#model.undo_stack==depth+1,'a generator use is a single undo step')
assert(#cable.use.outputs.object_ids>10 and model:get_object(cable.use.outputs.object_ids[1]).metadata.spline_use.use_id==cable.use.id)
assert(not S:apply_use(curve.id,'cable',{asset_id='missing',spawn=false}) and #model.undo_stack==depth+1,'a failed use leaves no history entry')
local fence=assert(S:apply_use(square.id,'fence',{asset_id=mesh.id,segment_length=2,spawn=false}));assert(#fence.use.outputs.object_ids>=5)

-- Use: NPC path writes route waypoints from the curve; regenerate updates the same route.
local npc=model:add_object({premise_id=premise.id,name='Guard',kind='entity',template='',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
    size={x=1,y=1,z=1},metadata={npc_population={record='Character.guard'}}})
local loop=assert(S:create({name='Patrol loop',points={{x=0,y=0,z=0},{x=10,y=0,z=0},{x=10,y=10,z=0},{x=0,y=10,z=0}},closed=true}))
local patrol=assert(S:apply_use(loop.id,'npc_path',{npc_id=npc.id,spacing=4,speed=1.5}))
local route=model:get_npc_route(patrol.use.outputs.route_id)
assert(route and route.loop==true and #route.waypoints==patrol.use.outputs.waypoints and #route.waypoints>=8 and route.waypoints[1].speed==1.5)
assert(S:update_point(loop.id,1,{position={x=-5,y=-5,z=0}}))
local regen2=assert(S:regenerate(loop.id));assert(regen2.rebuilt[1].outputs.route_id==route.id,'regenerate keeps the same route')
assert(model:get_npc_route(route.id).waypoints[1].transform.position.x<-4)
assert(not S:apply_use(loop.id,'npc_path',{npc_id='missing'}))

-- Use: camera path with look-ahead, ordered tags and timing from speed.
local cams=assert(S:apply_use(rowline.id,'camera_path',{count=5,speed=2,look_ahead=3,fov=60}))
local cam_ids=cams.use.outputs.camera_ids;assert(#cam_ids==5)
local c1=model:get_camera(cam_ids[1]);assert(c1.kind=='path' and c1.fov==60 and c1.tags[3]=='order:001')
assert(c1.look_at.y>c1.transform.position.y,'cameras look ahead along the path')
assert(near(c1.duration,(20/4)/2,1e-6),'duration comes from spacing / speed')
assert(near(cams.use.outputs.total_duration,4*(20/4)/2+2,1e-6))
local fixed=assert(S:apply_use(rowline.id,'camera_path',{count=3,look_at={x=5,y=60,z=1}}))
assert(model:get_camera(fixed.use.outputs.camera_ids[2]).look_at.x==5)

-- Use: native World Builder spline node with Hermite tangents.
local native=assert(S:apply_use(curve.id,'native_spline',{spawn=false}))
local node=model:get_object(native.use.outputs.object_ids[1])
local data=node.metadata.world_builder.entry.data
assert(node.metadata.world_builder.definition_key=='spline' and #data.pointDefs==#curve.points and data.looped==false)
local hh=S:handles(curve)
assert(near(data.pointDefs[2].tangentOut.x,hh[2].hout.x*3,1e-9) and near(data.pointDefs[2].tangentIn.x,-hh[2].hin.x*3,1e-9))
assert(data.pointDefs[1].automaticTangents==false and data.pointDefs[2].automaticTangents==true and data.pointDefs[3].automaticTangents==false,'only auto points use automatic tangents')

-- Remove a use (outputs removed) and delete a spline (outputs removed unless kept).
local fixed_cam=fixed.use.outputs.camera_ids[1]
local rm=assert(S:remove_use(rowline.id,fixed.use.id,false));assert(not model:get_camera(fixed_cam))
local keep=S:get(rowline.id).uses[1].outputs.object_ids[1]
assert(S:delete(rowline.id,true));assert(model:get_object(keep),'keep_outputs leaves generated objects')
assert(S:delete(loop.id,false))
assert(not S:get(loop.id))

-- Preview markers are transient and ignored by Runtime Sync.
local marker_search=app.world_builder.search
function app.world_builder:search(key,q,l,f) if key=='static_marker' then return {items={{name='Marker',path='marker'}}} end;return marker_search(self,key,q,l,f) end
local prep=app.world_builder.prepare_favorite_record
function app.world_builder:prepare_favorite_record(r,n) if r.variant=='Static Marker' then return {name=n,data={spawnable={spawnData='marker'}}} end;return prep(self,r,n) end
local count=#model.data.objects
local pv=assert(S:preview(curve.id,{spacing=5}));assert(pv.markers>=#curve.points and #model.data.objects==count)
for _,item in ipairs(app.placement:compare_runtime().items) do assert(not tostring(item.id):find('__spline_preview_',1,true)) end
assert(S:preview_clear());assert(#S.preview_objects==0)

-- Transactions block edits.
local real=app.transform_session.is_active;app.transform_session.is_active=function() return true end
assert(not S:add_point(curve.id,{source='aim'}) and not S:apply_use(curve.id,'distribute',{asset_id=chair.id}))
app.transform_session.is_active=real

-- Bridge.
local b=assert(app.bridge:handle({id='s1',op='spline_create',args={name='Bridge',points={{x=0,y=0,z=0},{x=4,y=0,z=0}},mode='linear'}}))
assert(assert(app.bridge:handle({id='s2',op='spline_sample',args={id=b.spline.id,spacing=1}})).count==5)
assert(assert(app.bridge:handle({id='s3',op='spline_add_point',args={id=b.spline.id,position={x=4,y=4,z=0}}})).index==3)
assert(assert(app.bridge:handle({id='s4',op='spline_update_point',args={id=b.spline.id,index=2,patch={mode='auto'}}})).point.mode=='auto')
assert(assert(app.bridge:handle({id='s5',op='spline_apply_use',args={id=b.spline.id,kind='distribute',params={asset_id=chair.id,spacing=2,spawn=false}}})).use)
assert(assert(app.bridge:handle({id='s6',op='spline_regenerate',args={id=b.spline.id}})).count==1)
assert(assert(app.bridge:handle({id='s7',op='spline_list',args={}})).count>=1)
assert(assert(app.bridge:handle({id='s8',op='spline_delete',args={id=b.spline.id}})).deleted)

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['NEW SPLINE AT AIM']=true;env:draw()
local sid=app.ui.spatial.spline_id;assert(S:get(sid) and #S:get(sid).points==1)
env.clicks['ADD POINT AT AIM']=true;env:draw();assert(#S:get(sid).points==2)
env.clicks['CLOSE CURVE']=true;env:draw();assert(S:get(sid).closed==false,'closing two points is refused')
print('splines_runtime_test: OK')
