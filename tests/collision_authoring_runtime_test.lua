local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local col=assert(app.collision,'collision module must be constructed')

-- Presets/materials mirror World Builder's tables, with WB's hint groups.
local presets=col:presets()
assert(#presets==59 and presets[34].name=='World Static' and presets[34].index==33)
local by_name={};for _,p in ipairs(presets) do by_name[p.name]=p end
assert(by_name['Player Blocker'].blocks_player and not by_name['Player Blocker'].blocks_npc)
assert(by_name['Simple Environment Collision'].blocks_npc and by_name['Simple Environment Collision'].blocks_player)
assert(not by_name['Particle'].blocks_player and not by_name['Particle'].blocks_npc)
local mats=col:materials();assert(#mats==83)
for i=2,#mats do assert(mats[i-1]<mats[i],'materials must use World Builder sorted order') end

-- Primitives: box/capsule/sphere with layer, material, visualization.
env.aim_x,env.aim_y,env.aim_z=5,0,0
local wall=assert(col:create_primitive({shape='box',size={x=4,y=0.4,z=3},preset='Player Blocker',material='concrete',source='aim',yaw=0,name='Gate blocker'}))
local wobj=wall.object
assert(wall.spawned and wobj.runtime.backend=='world_builder',tostring(wall.spawn_error))
local data=wobj.metadata.world_builder.entry.data
assert(data.shape==0 and data.scale.x==2 and data.scale.y==0.2 and data.scale.z==1.5,'box scale is WB half extents')
assert(data.preset==7 and data.material>=0)
assert(mats[data.material+1]=='concrete.physmat' and data.previewed==true)
assert(wobj.size.x==2 and wobj.metadata.world_builder.apply_scale==true and wobj.metadata.collision.preset=='Player Blocker')
assert(app.runtime_shell.handles[wobj.id].scale.x==2,'live collider receives its half extents through WB scale')
local cap=assert(col:create_primitive({shape='capsule',radius=0.3,height=2,preset='NPC Trace Obstacle',source='player',spawn=false}))
assert(cap.object.metadata.world_builder.entry.data.shape==1 and cap.object.metadata.world_builder.entry.data.scale.z==2)
local ball=assert(col:create_primitive({shape='sphere',radius=0.75,preset=19,source='player',visualize=false,spawn=false}))
assert(ball.object.metadata.world_builder.entry.data.previewed==false and ball.object.metadata.collision.preset=='Destructible')
assert(not col:create_primitive({shape='cone'}),'unknown shape must fail')
assert(not col:create_primitive({preset='Not A Layer'}),'unknown preset must fail')
assert(not col:create_primitive({material='unobtanium'}),'unknown material must fail')
assert(not col:create_primitive({size={x=0,y=1,z=1}}),'zero size must fail')

-- Edit: resize, relayer, toggle visualization; live colliders respawn.
local removed=env.wb_removed
local edited=assert(col:update(wobj.id,{size={x=6,y=0.4,z=3},preset='World Static',visualize=false}))
assert(edited.respawned and env.wb_removed==removed+1)
data=wobj.metadata.world_builder.entry.data
assert(data.scale.x==3 and wobj.size.x==3 and data.preset==33 and data.previewed==false and wobj.metadata.collision.preset=='World Static')
assert(assert(col:update(cap.object.id,{shape='box'})).object.metadata.world_builder.entry.data.shape==0)
assert(not col:update(wobj.id,{preset='nope'}))
assert(app.model:undo());assert(cap.object.metadata.world_builder.entry.data.shape==1 or app.model:get_object(cap.object.id).metadata.world_builder.entry.data.shape==1,'collision edits are undoable')

-- Visualization toggle across a premise/all colliders.
local vis=assert(col:set_visualization({visible=true}))
assert(vis.changed>=1 and vis.respawned>=1)
assert(app.model:get_object(wobj.id).metadata.world_builder.entry.data.previewed==true)
assert(assert(col:set_visualization({visible=true})).changed==0,'no-op visualization changes nothing')

-- Layers summary and list include room-kit colliders too.
local layers=col:layers({});assert(layers.count>=2)
local listed=col:list({});assert(listed.count==3 and listed.items[1].dimensions)

-- Imported collision mesh from WB's Collision Mesh catalog.
local search=app.world_builder.search
function app.world_builder:search(key,query,limit,force)
    if key=='collision_mesh' then return {items={{name='bench_collision',path='sector_hash_1:shape_2'}},total=1,shown=1} end
    return search(self,key,query,limit,force)
end
local prepare=app.world_builder.prepare_favorite_record
function app.world_builder:prepare_favorite_record(record,name)
    if record.variant=='Collision Mesh' then return {name=name,data={spawnable={sectorHash='1',shapeHash='2',meshType='x',scale={x=1,y=1,z=1},preset=33,material=5}}} end
    return prepare(self,record,name)
end
assert(assert(col:search_meshes({query='bench'})).items[1].path=='sector_hash_1:shape_2')
local mesh=assert(col:import_mesh({resource_path='sector_hash_1:shape_2',preset='NPC Collision',source='player',spawn=false}))
assert(mesh.object.metadata.world_builder.definition_key=='collision_mesh' and mesh.object.metadata.world_builder.entry.data.preset==3)
assert(mesh.object.metadata.world_builder.entry.data.material==5,'imported material is kept unless overridden')
assert(not col:import_mesh({resource_path='missing'}),'resources outside the catalog must be rejected')

-- Fit a box to an object's imported bounds.
local prop=app.model:add_object({name='Crate',kind='prop',template='base\\crate.ent',transform={position={x=20,y=20,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},
    metadata={asset_bounds={min={x=-0.5,y=-0.25,z=0},max={x=0.5,y=0.25,z=1},source='manual'}}})
local fit=assert(col:fit_to_object({object_id=prop.id,padding=0.1,spawn=false}))
local fd=fit.object.metadata.world_builder.entry.data
assert(math.abs(fd.scale.x-0.6)<1e-6 and math.abs(fd.scale.y-0.35)<1e-6 and math.abs(fd.scale.z-0.6)<1e-6)
assert(fit.object.transform.position.z==0.5 and fit.fitted_to==prop.id)
assert(not col:fit_to_object({object_id='missing'}))

-- Passability: a Player Blocker wall stops V but not NPCs; a World Static wall stops both.
app.model.data.objects={}
local function box(x,y,sx,sy,preset) return assert(col:create_primitive({shape='box',size={x=sx,y=sy,z=3},preset=preset,transform={position={x=x,y=y,z=1.5,w=1},rotation={roll=0,pitch=0,yaw=0}},spawn=false})).object end
local pb=box(0,0,0.4,20,'Player Blocker')
local args={center={x=0,y=0,z=0},half_width=5,half_depth=5,grid_step=0.5,start={x=-3,y=0,z=0},goal={x=3,y=0,z=0}}
local both=assert(col:passability(args))
assert(both.routes.player.status=='no_route' and both.routes.npc.status=='route',both.routes.player.status..' '..both.routes.npc.status)
assert(both.columns==20 and both.rows==20 and #both.map==20)
local joined=table.concat(both.map,'\n');assert(joined:find('p',1,true) and joined:find('S',1,true) and joined:find('G',1,true) and joined:find('*',1,true))
assert(both.blockers[1].id==pb.id and both.blockers[1].actors[1]=='player','blockers='..#both.blockers..' '..tostring(both.blockers[1] and both.blockers[1].id)..' vs '..tostring(pb.id)..' actors='..tostring(both.blockers[1] and table.concat(both.blockers[1].actors,',')))
assert(col:update(pb.id,{preset='World Static'}))
local blocked=assert(col:passability(args));assert(blocked.routes.player.status=='no_route' and blocked.routes.npc.status=='no_route')
-- A gap in the wall opens a route; the route bends through it.
assert(col:update(pb.id,{size={x=0.4,y=8,z=3},position={y=3}}))
local open=assert(col:passability(args));assert(open.routes.player.status=='route' and open.routes.player.path_length>6)
-- A collider above head height does not block; a rotated (yaw) wall uses its oriented footprint.
local high=assert(col:create_primitive({shape='box',size={x=2,y=2,z=0.5},preset='World Static',transform={position={x=-3,y=0,z=3},rotation={yaw=0}},spawn=false})).object
assert(col:passability(args).routes.player.status=='route','collider above head height must not block')
app.model:delete_object(high.id)
local diag=box(0,-2,0.4,6,'World Static');assert(col:update(diag.id,{yaw=45}))
local rotated=assert(col:passability({center={x=0,y=-2,z=0},half_width=3,grid_step=0.5,actor='player'}))
assert(rotated.routes.player.blocked_cells>0 and rotated.routes.player.blocked_cells<rotated.columns*rotated.rows)
-- Particle-layer colliders never block movement; start inside a blocker is reported.
local particle=box(-3,0,1,1,'Particle');assert(col:passability(args).routes.player.status~='start_blocked')
local solid=box(-3,0,1,1,'World Static');assert(col:passability(args).routes.player.status=='start_blocked')
assert(not col:passability({center={x=0,y=0},half_width=200,grid_step=0.1}),'oversized grids must fail')
-- Live cross-check reuses the collision-ray walkability scan.
Vector4.Distance=Vector4.Distance or function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
app.model:delete_object(solid.id)
local live=assert(col:passability({center={x=0,y=0,z=30},half_width=3,grid_step=0.5,actor='player',start={x=10,y=20,z=30},goal={x=11,y=20,z=30},live=true,include_all=true}))
assert(live.live and live.live.status,'live scan must run: '..tostring(live.live and live.live.error))
local distance=Vector4.Distance;Vector4.Distance=nil
local broken=assert(col:passability({center={x=0,y=0,z=30},half_width=3,grid_step=0.5,actor='player',start={x=10,y=20,z=30},goal={x=11,y=20,z=30},live=true}))
assert(broken.live.error and broken.routes.player,'a failing live scan is reported, not fatal')
Vector4.Distance=distance

-- Bridge operations.
assert(#assert(app.bridge:handle({id='c1',op='collision_presets',args={}})).presets==59)
local bc=assert(app.bridge:handle({id='c2',op='collision_create_primitive',args={shape='sphere',radius=1,source='player',spawn=false}}))
assert(assert(app.bridge:handle({id='c3',op='collision_update',args={id=bc.object.id,patch={radius=2}}})).object.metadata.world_builder.entry.data.scale.x==2)
assert(assert(app.bridge:handle({id='c4',op='collision_list',args={}})).count>=1)
assert(assert(app.bridge:handle({id='c5',op='collision_layers',args={}})).count>=1)
assert(assert(app.bridge:handle({id='c6',op='collision_visualization',args={visible=false}})).visible==false)
assert(assert(app.bridge:handle({id='c7',op='collision_passability',args=args})).routes.player)
assert(assert(app.bridge:handle({id='c8',op='collision_search_meshes',args={query='bench'}})).total==1)

-- The Spatial Collision tab draws and reaches the module.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
local before=#app.model.data.objects
env.clicks['PLACE COLLIDER AT AIM']=true;env:draw()
assert(#app.model.data.objects==before+1,'PLACE COLLIDER AT AIM must create a collider')
env.clicks['PREVIEW PASSABILITY']=true;env:draw()
assert(app.ui.spatial.pass_result and #app.ui.spatial.pass_result.map>0)
env.clicks['HIDE ALL COLLISION']=true;env:draw()
print('collision_authoring_runtime_test: OK')
