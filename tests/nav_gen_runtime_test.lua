local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local N=assert(app.nav_gen,'the navigation generator must be constructed')
local NavGen=getmetatable(N).__index
local model=app.model
local T=function(x,y,z,yaw) return {position={x=x,y=y,z=z,w=1},rotation={roll=0,pitch=0,yaw=yaw or 0}} end
local function fails(needle,res,err) assert(res==nil,'expected a failure: '..tostring(needle));assert(tostring(err):find(needle,1,true),'expected "'..needle..'" in: '..tostring(err)) end
local function box(cx,cy,cz,sx,sy,sz) return {shape='box',center={x=cx,y=cy,z=cz},size={x=sx,y=sy,z=sz},rotation={roll=0,pitch=0,yaw=0},material='main'} end
local function count(list,pred) local n=0;for _,x in ipairs(list or {}) do if pred(x) then n=n+1 end end;return n end
assert(app.version=='0.83.0')

-- Parameters.
local P=assert(NavGen.normalize_params(nil))
assert(P.cell==0.25 and P.agent_radius==0.35 and P.max_climb==0)
fails('unknown navigation parameter',NavGen.normalize_params({radius=1}))
fails('cell must be a number from 0.1 to 1',NavGen.normalize_params({cell=2}))
fails('tile must be at least twice',NavGen.normalize_params({cell=1,tile=1}))
assert(#N:parameters()==10)

-- Scope.
fails('give premise_id, room_ids, build_id or all=true',N:generate({}))
fails('premise not found',N:generate({premise_id='nope'}))
fails('room not found',N:generate({room_ids={'nope'}}))
fails('no grammar build',N:generate({build_id='nope'}))

-- A test site: two rooms sharing a door (the hall also has an exit), an office door
-- blocked by a crate, a closet with a door too narrow for the agent, and outside on
-- the ground: stairs to a landing, a ramp to a platform, and two platforms with a gap.
local premise=assert(model:add_premise({name='Nav Lab',kind='interior',transform=T(0,0,0)}))
local empty=assert(model:add_premise({name='Empty',kind='interior',transform=T(0,0,0)}))
fails('no walkable surfaces in scope',N:generate({premise_id=empty.id}))
local rg=app.room_generator
local hall=assert(rg:create({spec={name='Hall',width=6,length=4,doors={{wall='north',width=1},{wall='south',width=1,offset=1.5}}},premise_id=premise.id,transform=T(0,0,0)})).room
local office=assert(rg:create({spec={name='Office',width=6,length=4,doors={{wall='south',width=1},{wall='east',width=1}}},premise_id=premise.id,transform=T(0,4.2,0)})).room
local closet=assert(rg:create({spec={name='Closet',width=2,length=2,doors={{wall='west',width=0.5}}},premise_id=premise.id,transform=T(-8,0,0)})).room
local proc=app.procedural
assert(proc:create({generator='compound',params={parts={box(0,0,-0.05,12,12,0.1)}},surface='ground',premise_id=premise.id,transform=T(18,0,0),spawn=false}))
local stairs=assert(proc:create({generator='stairs',params={width=1.2,height=1.5,length=2.4,landing=2},premise_id=premise.id,transform=T(14,-4,0),spawn=false})).object
assert(proc:create({generator='ramp',params={width=1.5,length=4,height=0.5},premise_id=premise.id,transform=T(19,-4,0),spawn=false}))
assert(proc:create({generator='compound',params={parts={box(0,0,0.25,3,3,0.5)}},surface='platform',premise_id=premise.id,transform=T(19,1.5,0),spawn=false}))
for _,x in ipairs({14,16.6}) do assert(proc:create({generator='compound',params={parts={box(0,0,0.5,2,2,1)}},surface='platform',premise_id=premise.id,transform=T(x,4,0),spawn=false})) end
local crate=assert(proc:create({generator='compound',params={parts={box(0,0,0.4,0.8,0.8,0.8)}},premise_id=premise.id,room_id=office.id,transform=T(2.5,4.2,0.2),spawn=false})).object

-- Preview changes nothing.
local undo=#model.undo_stack;local graphs=#model.data.navigation_graphs
local pv=assert(N:generate({premise_id=premise.id,dry_run=true}))
assert(pv.dry_run and pv.graph_id==nil and #model.undo_stack==undo and #model.data.navigation_graphs==graphs,'a preview is a dry run')
assert(pv.stats.walkable_area>100 and pv.stats.areas>10 and pv.native_redengine==false)
local pv2=assert(N:generate({premise_id=premise.id,dry_run=true}))
assert(#pv2.off_mesh==#pv.off_mesh and pv2.stats.edges==pv.stats.edges)
for i,o in ipairs(pv.off_mesh) do assert(o.id==pv2.off_mesh[i].id and o.from_area==pv2.off_mesh[i].from_area and o.length==pv2.off_mesh[i].length,'generation is deterministic') end

local r=assert(N:generate({premise_id=premise.id}))
assert(#model.undo_stack==undo+1,'generating is one undo step')
local g=assert(N:get(r.graph_id))
assert(g.generated and g.format=='locationstudio.navigation-graph.v1' and g.native_redengine==false and g.generator.scope.premise_id==premise.id)
assert(model.data.active_navigation_graph_id==g.id,'the first generated graph becomes the active one')
-- Polygons: rectangles on the walkable surfaces, each with an area node.
assert(#g.polygons==r.stats.areas and #g.polygons>0)
for _,poly in ipairs(g.polygons) do assert(#poly.vertices==4 and poly.node_id) end
for _,n in ipairs(g.nodes) do if n.kind=='area' and n.room_id==hall.id then assert(math.abs(n.position.z)<0.01,'hall floor at the floor top: '..n.position.z) end end

-- Doors.
local by={};for _,d in ipairs(r.doors) do for _,id in ipairs(d.rooms) do by[id]=by[id] or {};table.insert(by[id],d) end end
local shared
for _,d in ipairs(r.doors) do if #d.rooms==2 then shared=d end end
assert(shared and shared.status=='connected' and #shared.sides==2,'the door both rooms share is one connected transition')
assert(count(r.doors,function(d) return d.status=='exit' and d.rooms[1]==hall.id end)==1,'the hall south door leads outside')
local blocked;for _,d in ipairs(r.doors) do if d.status=='blocked' then blocked=d end end
assert(blocked and blocked.rooms[1]==office.id and blocked.blockers and blocked.blockers[1].object_id==crate.id,'the crate blocks the office east door and is named')
local narrow;for _,d in ipairs(r.doors) do if d.rooms[1]==closet.id then narrow=d end end
assert(narrow.status=='too_narrow')
for _,e in ipairs(g.edges) do if e.door_id==narrow.id then assert(e.enabled==false and e.notes:find('narrower',1,true)) end end
assert(r.stats.by_kind.door>=3)
-- Room links and reachability.
local door_link;for _,l in ipairs(r.room_links) do if l.kind=='door' then door_link=l end end
assert(door_link and ((door_link.from==hall.id and door_link.to==office.id) or (door_link.from==office.id and door_link.to==hall.id)))
assert(count(r.room_links,function(l) return l.kind=='exit' end)==1)
local status={};for _,row in ipairs(r.report.rooms) do status[row.room_id]=row.status end
assert(status[hall.id]=='reachable' and status[office.id]=='reachable','the entry island holds the most rooms')
assert(status[closet.id]=='unreachable','the closet is cut off: its only door is too narrow')

-- Stairs and ramps.
local flight,ramp
for _,f in ipairs(r.flights) do if f.kind=='stairs' then flight=f elseif f.kind=='ramp' then ramp=f end end
assert(flight and flight.status=='connected' and math.abs(flight.rise-1.5)<0.05 and flight.object_id==stairs.id,'stairs flight from the ground to the landing')
assert(flight.bottom.position.z<0.05 and math.abs(flight.top.position.z-1.5)<0.05)
assert(ramp and ramp.status=='connected' and math.abs(ramp.rise-0.5)<0.05)
assert(r.stats.by_kind.stairs>0 and r.stats.by_kind.ramp>0)
assert(r.stats.under_solid>0,'the ground under the solid stairs is left out')

-- Off-mesh links: one-way drops from the landing and platforms, and a jump between the platforms.
local drops,jumps=0,0
for _,o in ipairs(r.off_mesh) do
    if o.kind=='drop' then drops=drops+1;assert(o.one_way and o.rise>0.35 and o.rise<=2.0) end
    if o.kind=='jump' then jumps=jumps+1;assert(not o.one_way) end
end
assert(drops>=3,'drops from the landing and platforms: '..drops)
assert(jumps>=1,'a jump across the gap between the platforms')
for _,e in ipairs(g.edges) do if e.off_mesh=='drop' then assert(e.kind=='off_mesh' and e.one_way) elseif e.off_mesh=='jump' then assert(e.kind=='jump') end end
local ledges=0;for i=1,#r.off_mesh do for j=i+1,#r.off_mesh do local a,b=r.off_mesh[i],r.off_mesh[j]
    if a.kind==b.kind and a.from_area==b.from_area and a.to_area==b.to_area then ledges=ledges+1 end end end
assert(ledges==0,'at most one link per pair of areas')
-- Drops over walls do not exist: nothing starts in a room.
for _,o in ipairs(r.off_mesh) do assert(o.rooms[1]==nil,'off-mesh links only outside the rooms here') end

-- The generated graph works with the graph query.
local function area_of(room_id) for _,n in ipairs(g.nodes) do if n.kind=='area' and n.room_id==room_id then return n end end end
local q=assert(app.navigation:query({graph_id=g.id,start=area_of(hall.id).position,goal=area_of(office.id).position}))
assert(q.status=='reachable_in_imported_graph');local kinds={};for _,t in ipairs(q.transitions) do kinds[t.kind]=true end
assert(kinds.door,'hall to office goes through the door')
q=assert(app.navigation:query({graph_id=g.id,start=flight.bottom.position,goal=flight.top.position}))
assert(q.status=='reachable_in_imported_graph');kinds={};for _,t in ipairs(q.transitions) do kinds[t.kind]=true end
assert(kinds.stairs,'up the stairs')
q=assert(app.navigation:query({graph_id=g.id,start=area_of(hall.id).position,goal=flight.top.position}))
assert(q.status=='unreachable_in_imported_graph','the rooms do not reach the yard')

-- Parameters change the graph: climbable drops become two-way, no jumps.
local r2=assert(N:regenerate(g.id,{params={max_climb=1.6,max_jump=0}}))
assert(r2.graph_id==g.id and r2.replaced and #model.undo_stack==undo+2)
assert(count(r2.off_mesh,function(o) return o.kind=='jump' end)==0)
assert(count(r2.off_mesh,function(o) return o.kind=='drop_climb' and not o.one_way end)>=1)
g=N:get(g.id);assert(g.generator.params.max_climb==1.6)
-- A wider agent no longer fits the hall door either.
local wide=assert(N:generate({premise_id=premise.id,params={agent_radius=0.55},dry_run=true}))
for _,d in ipairs(wide.doors) do if #d.rooms==2 then assert(d.status=='too_narrow') end end

-- Staleness.
local rep=assert(N:report(g.id));assert(rep.stale==false and rep.generated and rep.stats.doors==r.stats.doors)
crate.transform.position.x=crate.transform.position.x-1
rep=assert(N:report(g.id));assert(rep.stale==true and rep.stale_hint)
assert(N:regenerate(g.id,{}));assert(N:report(g.id).stale==false)
crate.transform.position.x=crate.transform.position.x+1
assert(N:regenerate(g.id,{params={max_climb=0,max_jump=1}}))

-- Undo.
assert(model:undo());assert(N:get(g.id).generator.params.max_climb==1.6,'undo restores the previous generation')
assert(model:redo())

-- Scoped to rooms.
local only=assert(N:generate({room_ids={hall.id,office.id},dry_run=true}))
assert(only.stats.flights==0 and #only.off_mesh==0 and only.stats.doors==3,'room scope: the two rooms and their doors')
assert(N:_default_name({room_ids={hall.id,office.id}})=='Navigation: Hall +1')

-- Obstacles and clearance: a desk in the hall takes floor; a low ceiling blocks everything.
local before=only.stats.walkable_area
local desk=assert(proc:create({generator='compound',params={parts={box(0,0,0.375,1.6,0.8,0.75)}},premise_id=premise.id,room_id=hall.id,transform=T(-1,0,0.2),spawn=false})).object
local with_desk=assert(N:generate({room_ids={hall.id,office.id},dry_run=true}))
assert(with_desk.stats.walkable_area<before-1.5,'the desk and its clearance are not walkable')
assert(model:delete_objects({desk.id}))
local low=assert(rg:create({spec={name='Crawl',width=3,length=3,height=2},premise_id=empty.id,transform=T(0,-30,0)}))
fails('no walkable floor is left',N:generate({premise_id=empty.id,params={agent_height=2.5}}))
assert(N:generate({premise_id=empty.id,dry_run=true}).stats.walkable_area>3)

-- Bridge.
local b=assert(app.bridge:handle({op='nav_parameters',args={}}));assert(#b.parameters==10)
b=assert(app.bridge:handle({op='nav_preview',args={premise_id=premise.id}}));assert(b.dry_run and b.stats.doors==4)
b=assert(app.bridge:handle({op='nav_report',args={graph_id=g.id}}));assert(b.graph_id==g.id)
local lst=assert(app.bridge:handle({op='navigation_graph_list',args={}}));assert(#lst.graphs>=1)
local _,berr=app.bridge:handle({op='nav_frobnicate',args={}});assert(tostring(berr):find('unknown navigation operation',1,true))

-- Validation plan.
local plan=assert(N:validation_plan({graph_id=g.id}))
local legkinds={};for _,l in ipairs(plan.legs) do legkinds[l.kind]=(legkinds[l.kind] or 0)+1 end
assert(legkinds.door==1 and legkinds.stairs==1 and legkinds.ramp==1 and (legkinds.off_mesh or 0)>=3,'one leg per connected door, flight, ramp and off-mesh link')
for _,l in ipairs(plan.legs) do assert(l.graph_status=='reachable_in_imported_graph','the graph expects every leg to work: '..l.kind..' '..l.graph_status) end
fails('unknown leg kind',N:validation_plan({graph_id=g.id,legs={'teleport'}}))
fails('max_legs must be 1 to 60',N:validation_plan({graph_id=g.id,max_legs=0}))
local both=assert(N:validation_plan({graph_id=g.id,legs={'stairs'},both_directions=true}));assert(both.count==2)
local cust=assert(N:validation_plan({graph_id=g.id,legs={'door'},custom={{name='yard',start={x=18,y=0,z=0},goal={x=20,y=6,z=0}}}}));assert(cust.count==2 and cust.legs[2].kind=='custom')
local rooms_plan=assert(N:validation_plan({graph_id=g.id,legs={'rooms'}}));assert(rooms_plan.count==1)
b=assert(app.bridge:handle({op='nav_validate_plan',args={graph_id=g.id,max_legs=2}}));assert(b.count==2 and b.truncated)

-- Validation with a (mock) NPC: AI move commands, teleports and position sampling.
fails('no NPC to validate with',N:validate_start({graph_id=g.id}))
local npc={pos={x=0,y=0,z=0},cmds=0,cancelled=0,id={hash=4242}}
function npc:IsNPC() return true end
function npc:GetEntityID() return self.id end
function npc:GetWorldPosition() return {x=self.pos.x,y=self.pos.y,z=self.pos.z} end
function npc:GetAIControllerComponent() return {SendCommand=function(_,cmd) npc.cmd=cmd;npc.cmds=npc.cmds+1 end,CancelCommand=function(_,cmd) if npc.cmd==cmd then npc.cmd=nil end;npc.cancelled=npc.cancelled+1 end} end
Game.GetTargetingSystem=function() return {GetLookAtObject=function() return npc end} end
Game.GetTeleportationFacility=function() return {Teleport=function(_,ent,v) ent.pos={x=v.x,y=v.y,z=v.z};ent.cmd=nil end} end
WorldPosition={new=function() return {} end,SetVector4=function(wp,v) wp.v=v end}
AIPositionSpec={new=function() return {} end,SetWorldPosition=function(spec,wp) spec.wp=wp end}
AIMoveToCommand={new=function() return {} end}
moveMovementType={Walk='Walk',Run='Run'}
-- The "engine": walks straight at 1.5 m/s, except that nothing can climb onto the landing.
local function engine(dt)
    local c=npc.cmd;if not c then return end
    assert(c.ignoreNavigation==false and c.movementType=='Walk' and c.finishWhenDestinationReached==true)
    local goal=c.movementTarget.wp.v
    if goal.z>1 and npc.pos.z<1 then return end
    local dx,dy,dz=goal.x-npc.pos.x,goal.y-npc.pos.y,goal.z-npc.pos.z
    local d=math.sqrt(dx*dx+dy*dy+dz*dz);if d<0.05 then return end
    local s=math.min(1,1.5*dt/d);npc.pos={x=npc.pos.x+dx*s,y=npc.pos.y+dy*s,z=npc.pos.z+dz*s}
end
local function run_until_done(limit)
    for _=1,limit do engine(0.1);N:update(0.1);if N:validate_status().done then return true end end
end
local v=assert(N:validate_start({graph_id=g.id,legs={'door','stairs','ramp'}}))
assert(v.legs==3 and v.npc_key=='4242' and not v.spawned)
fails('a validation run is active',N:validate_start({graph_id=g.id}))
fails('a validation run is using this graph',N:regenerate(g.id,{}))
fails('a validation run is using this graph',N:delete(g.id))
assert(N:validate_status().state=='acquire')
assert(run_until_done(3000),'the run finishes')
local st=N:validate_status()
assert(st.state=='completed' and st.summary.legs==3)
local res={};for _,x in ipairs(st.results) do res[x.kind]=x end
assert(res.door.status=='traversed' and res.door.verdict=='confirmed' and res.door.passed_via==true,'the NPC walks through the door')
assert(res.ramp.status=='traversed' and res.ramp.verdict=='confirmed')
assert(res.stairs.status=='stalled' and res.stairs.verdict=='engine_disagrees','the engine refuses the stairs: the graph says they work')
assert(st.summary.traversed==2 and st.summary.failed==1 and st.summary.engine_disagrees==1)
assert(npc.cmds==3)
g=N:get(g.id)
assert(g.validation and g.validation.summary.traversed==2 and #g.validation.legs==3 and #g.validation.legs[1].trace>1)
local marked=0;for _,e in ipairs(g.edges) do if e.validation then marked=marked+1;assert(e.validation.run_id==g.validation.run_id) end end
assert(marked>=5,'each leg marks its links')
assert(N:report(g.id).validation.summary.traversed==2)
-- Cancel: finished legs are kept.
assert(N:validate_start({graph_id=g.id,legs={'off_mesh'},timeout_scale=0.5}))
for _=1,5 do engine(0.1);N:update(0.1) end
local c=assert(N:validate_cancel());assert(c.state=='cancelled')
assert(N:validate_status().done and N:get(g.id).validation.state=='cancelled')
fails('no validation run is active',N:validate_cancel())
-- Command failures are reported per leg.
local saved=AIMoveToCommand;AIMoveToCommand=nil
assert(N:validate_start({graph_id=g.id,legs={'door'}}));assert(run_until_done(200))
assert(N:validate_status().results[1].status=='command_failed')
AIMoveToCommand=saved
-- Results wait while a transform edit is open.
app.transform_session.is_active=function() return true end
assert(N:generate({premise_id=premise.id,dry_run=true}),'a preview works during an edit')
fails('Finish or cancel the active transform edit',N:generate({premise_id=premise.id}))
assert(N:validate_start({graph_id=g.id,legs={'ramp'}}));assert(run_until_done(1000))
local run_id=N.run.id;assert(N:get(g.id).validation.run_id~=run_id,'no write during a transaction')
app.transform_session.is_active=nil
N:update(0.1);assert(N:get(g.id).validation.run_id==run_id,'written once the transaction closes')
-- Bridge.
b=assert(app.bridge:handle({op='nav_validate_status',args={}}));assert(b.done)

-- UI.
app.selected_premise_id=premise.id
app.ui.spatial.nav_graph_id=g.id
app.ui.spatial:draw_navigation()
assert(env.labels['PREVIEW##navgen'] and env.labels['GENERATE NAVIGATION##navgen'] and env.labels['REGENERATE##navgen'] and env.labels['VALIDATE WITH NPC##navgen'])
env.clicks['PREVIEW##navgen']=true;app.ui.spatial:draw_navigation()
assert(app.ui.spatial.nav_gen_result.dry_run)
local n0=#model.data.navigation_graphs
env.clicks['GENERATE NAVIGATION##navgen']=true;app.ui.spatial:draw_navigation()
assert(#model.data.navigation_graphs==n0+1 and app.ui.spatial.nav_graph_id~=g.id)
app.ui.spatial.nav_graph_id=g.id
env.clicks['VALIDATE WITH NPC##navgen']=true;app.ui.spatial:draw_navigation()
assert(N.run and not N.run.done)
app.ui.spatial:draw_navigation();assert(env.labels['CANCEL VALIDATION##navgen'])
env.clicks['CANCEL VALIDATION##navgen']=true;app.ui.spatial:draw_navigation();assert(N.run.done)
env:draw()

-- Delete.
assert(N:delete(model.data.navigation_graphs[#model.data.navigation_graphs].id))
fails('navigation graph not found',N:report('nope'))
local imported=assert(app.navigation:import_graph({nodes={{id='a',position={x=0,y=0,z=0}},{id='b',position={x=1,y=0,z=0}}},edges={{from='a',to='b',kind='ramp'}}}))
fails('was imported, not generated',N:regenerate(imported.id,{}))
fails('was imported, not generated',N:generate({premise_id=premise.id,graph_id=imported.id}))

-- Grammar builds: navigation in the same undo step, kept up to date, removed with the build.
local Gr=app.env_grammar
local doc={id='nav_test',start='Root',size={6,5,3},rules={Root={{room={}},{walls={sides={'south'},depth=0.5,['do']={{door={width=1}}}}}}}}
local u0=#model.undo_stack
local built=assert(Gr:generate({doc=doc,transform=T(0,200,0),build_id='navb',navigation=true}))
assert(built.navigation and built.navigation.graph_id,'navigation=true generates the graph: '..tostring(built.navigation and built.navigation.error))
assert(#model.undo_stack==u0+1,'the graph joins the build undo step')
local bg=N:get(built.navigation.graph_id);assert(bg.generator.scope.build_id=='navb' and bg.stats.doors==1 and bg.doors[1].status=='exit')
local again=assert(Gr:regenerate('navb',{seed=5}))
assert(again.navigation and again.navigation.graph_id==bg.id and again.navigation.replaced,'regenerating the build regenerates its graph')
assert(model:undo());assert(N:get(bg.id),'undo returns to the first generation')
assert(model:undo());assert(not N:get(bg.id),'undo removes the build and its graph together')
assert(model:redo())
local off=assert(Gr:generate({doc=doc,transform=T(0,220,0),build_id='navc'}));assert(off.navigation==nil,'no graph unless asked')
local rm=assert(Gr:remove('navb'));assert(rm.navigation_removed==1 and not N:get(bg.id),'removing the build removes its graph')
assert(Gr:remove('navc'))

print('LocationStudio navigation generator: surfaces, doors, stairs, ramps, off-mesh links, room links, grammar builds and NPC validation: OK')
