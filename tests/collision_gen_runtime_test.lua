local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local C=assert(app.collision_gen,'collision generator must be constructed')
local Gen=getmetatable(C).__index
local P=app.procedural
local model=app.model
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-6) end
local function B(c,s,yaw) return {shape='box',center={x=c[1],y=c[2],z=c[3]},size={x=s[1],y=s[2],z=s[3]},rotation={roll=0,pitch=0,yaw=yaw or 0}} end
local function vol(list) local v=0;for _,b in ipairs(list) do v=v+b.size.x*b.size.y*b.size.z end;return v end
local function colliders(id) local out={};for _,cid in ipairs(model:get_object(id).metadata.procedural.collider_ids) do out[#out+1]=model:get_object(cid) end;return out end
local function preset_of(o) return o.metadata.collision.preset end
-- Collider objects store World Builder scale: half extents.
local function dims(c) return {x=c.size.x*2,y=c.size.y*2,z=c.size.z*2} end
local function cvol(list) local v=0;for _,c in ipairs(list) do local d=dims(c);v=v+d.x*d.y*d.z end;return v end

-- Rule validation.
assert(not Gen.normalize_rules({mode='hull'}) and not Gen.normalize_rules({actors='ghosts'}) and not Gen.normalize_rules({max_boxes=0}))
assert(not Gen.normalize_rules({tolerance=2}) and not Gen.normalize_rules({doorways='open'}) and not Gen.normalize_rules({rails='glass'}))
assert(not Gen.normalize_rules({min_thickness=0.001}) and not Gen.normalize_rules({exclude={{center={0,0,0}}}}) and not Gen.normalize_rules({colour=1}))
local r=assert(Gen.normalize_rules({mode='simplified',actors='npc',per_room=true,exclude={{center={1,2,3},size={1,1,1},yaw=90}}}))
assert(r.mode=='simplified' and r.per_room==true and r.exclude[1].size.z==1 and r.exclude[1].yaw==90)

-- Box algebra (aligned cuts are exact).
local wall=B({0,0,1.5},{5,0.2,3})
local pieces=assert(Gen.subtract(wall,B({-1,0,1.05},{1,1,2.1})))
assert(#pieces==3 and close(vol(pieces),15*0.2-2.1*0.2),'left, right, above the door: '..vol(pieces))
local turned=assert(Gen.subtract(B({0,0,1.5},{5,0.2,3},90),B({0,1,1},{1,0.6,2},180)),'a 90-degree difference is still aligned')
assert(close(vol(turned),3-0.2*0.6*2),'turned cut '..vol(turned))
assert(Gen.subtract(wall,B({0,0,1},{1,1,1},30))==nil,'not aligned')
local kept,hit=Gen.subtract(wall,B({10,0,1},{1,1,1}));assert(#kept==1 and hit==false)
local inter=assert(Gen.intersect(wall,B({2.5,0,1.5},{1,1,1})));assert(close(inter.size.x,0.5) and close(inter.center.x,2.25))
assert(Gen.intersect(wall,B({9,0,0},{1,1,1}))==false)
local sliver=Gen.subtract(B({0,0,1.5},{5,0.2,3}),B({0,0,1.51},{1,1,2.98}))
for _,p in ipairs(sliver) do for _,k in ipairs({'x','y','z'}) do assert(p.size[k]>=0.02,'no sub-2 cm pieces') end end

-- A room with a door and a wall piece across it.
local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
local room=assert(app.builder:create_room({premise_id=premise.id,name='Lobby',width=6,depth=4,height=3,generate_shell=false,
    transform={position={x=100,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
assert(model:add_opening(room.id,{kind='door',wall='north',offset=-1,width=1,height=2.1}))
-- Wall object along the north wall (world y = 2), no opening in its geometry.
local north=assert(P:create({generator='box',params={size={6.4,0.2,3}},name='North wall',room_id=room.id,premise_id=premise.id,collision=true,
    transform={position={x=100,y=2,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local cs=colliders(north.object.id)
assert(#cs==3,'the doorway is cut out of the collider: '..#cs)
for _,c in ipairs(cs) do
    assert(preset_of(c)=='World Static' and c.room_id==room.id and c.metadata.collision_gen.role=='geometry')
    -- Nothing solid in the doorway (x 98.5..99.5, z 0..2.1).
    local p,s=c.transform.position,{x=c.size.x,y=c.size.y,z=c.size.z}
    assert(not (math.abs(p.x-99)+s.x<0.5+1e-6 and p.z-s.z<2.1-1e-6),'collider inside the doorway')
end
local st=model:get_object(north.object.id).metadata.procedural.collision_stats
assert(st.excluded==1 and st.source_boxes==1)

-- Rules: object scope actors, keep doorway.
local h=#model.undo_stack
local res=assert(C:set_rules('object:'..north.object.id,{actors='player',doorways='keep',material='concrete'}))
assert(#model.undo_stack==h+1,'rules + regeneration are one undo step')
assert(res.regenerated.colliders==1)
cs=colliders(north.object.id);assert(#cs==1 and preset_of(cs[1])=='Player Blocker' and cs[1].metadata.collision.material=='concrete.physmat')
assert(model:undo() and #colliders(north.object.id)==3 and preset_of(colliders(north.object.id)[1])=='World Static','undo restores rules and colliders')
assert(C:get_rules('object:'..north.object.id).rules.actors==nil)
assert(C:set_rules('object:'..north.object.id,{actors='npc'}))
assert(preset_of(colliders(north.object.id)[1])=='NPC Trace Obstacle')
assert(not C:set_rules('object:nope',{}) and not C:set_rules('planet',{}))

-- Room scope with object override; effective sources.
local pillar=assert(P:create({generator='compound',params={parts={B({0,0,0.5},{1,1,1}),B({0,0,1.5},{1,1,1}),B({3,0,0.5},{1,1,1})}},room_id=room.id,premise_id=premise.id,collision=true,
    transform={position={x=100,y=-1,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
assert(#colliders(pillar.object.id)==3)
assert(C:set_rules('room:'..room.id,{mode='bounds'}))
do local cc=colliders(pillar.object.id);assert(#cc==1 and close(dims(cc[1]).x,4),'bounds: '..#cc..' '..tostring(cc[1] and cc[1].size.x)) end
local eff,src=C:effective(model:get_object(pillar.object.id));assert(eff.mode=='bounds' and src.mode=='room:'..room.id and src.actors=='builtin')
assert(C:set_rules('object:'..pillar.object.id,{mode='convex'}))
cs=colliders(pillar.object.id);assert(#cs==2,'convex: one box per connected piece')
assert(C:set_rules('object:'..pillar.object.id,{mode='simplified'}))
cs=colliders(pillar.object.id);assert(#cs==2 and close(cvol(cs),3),'the stacked boxes merge losslessly')
assert(C:set_rules('object:'..pillar.object.id,{mode='simplified',max_boxes=1}))
assert(#colliders(pillar.object.id)==1,'forced merge down to max_boxes')
assert(C:set_rules('object:'..pillar.object.id,{mode='none'}) and #colliders(pillar.object.id)==0)
assert(C:set_rules('object:'..pillar.object.id,{},{replace=true}))
assert(C:set_rules('room:'..room.id,{},{replace=true}) and #colliders(pillar.object.id)==3)

-- Simplified stairs: many steps collapse within tolerance.
local stairs=assert(P:create({generator='stairs',params={width=1.2,height=1.8,length=2.7,landing=1},premise_id=premise.id,collision=true,
    collision_rules={mode='simplified',tolerance=0.6},transform={position={x=50,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local exact=#assert(C:preview({object_id=stairs.object.id,rules={mode='exact'}})).boxes
assert(#colliders(stairs.object.id)<exact,'simplified '..#colliders(stairs.object.id)..' < exact '..exact)
assert(model:get_object(stairs.object.id).metadata.procedural.collision_rules.mode=='simplified')

-- Rails.
local rail=assert(P:create({generator='railing',params={points={{0,0,0},{3,0,0},{3,2,0}},height=1},premise_id=premise.id,collision=true,
    transform={position={x=0,y=30,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
cs=colliders(rail.object.id);assert(#cs==2 and cs[1].metadata.collision_gen.role=='rail','one barrier per segment')
assert(close(dims(cs[1]).z,1) and close(cs[1].transform.position.z,0.5))
assert(C:set_rules('object:'..rail.object.id,{rail_height=1.6,rail_thickness=0.2}))
cs=colliders(rail.object.id);assert(close(dims(cs[1]).z,1.6) and close(dims(cs[1]).x,0.2))
local parts_count=#rail.object.metadata.procedural.parts
assert(C:set_rules('object:'..rail.object.id,{rails='parts'}) and #colliders(rail.object.id)==parts_count)
assert(C:set_rules('object:'..rail.object.id,{rails='none'}) and #colliders(rail.object.id)==0)

-- Glass and minimum thickness.
local win=assert(P:create({generator='window',params={},premise_id=premise.id,collision=true,transform={position={x=0,y=40,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local frame_only=#colliders(win.object.id)
assert(C:set_rules('object:'..win.object.id,{glass='block',min_thickness=0.08}))
cs=colliders(win.object.id);assert(#cs==frame_only+1)
local pane;for _,c in ipairs(cs) do if c.metadata.collision_gen.role=='glass' then pane=c end end
assert(pane and close(dims(pane).y,0.08),'the 1 cm pane is thickened')

-- Exclusion boxes: default scope in world space.
local slab=assert(P:create({generator='box',params={size={4,4,0.3}},premise_id=premise.id,collision=true,transform={position={x=-50,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
assert(C:set_rules('default',{exclude={{center={-50,0,0.15},size={1,1,1}}}}))
cs=colliders(slab.object.id);assert(#cs==4 and close(cvol(cs),(16-1)*0.3),'a shaft through the slab')
assert(C:set_rules('default',{},{replace=true}) and #colliders(slab.object.id)==1)

-- Per-room: a floor under two adjacent rooms is split and assigned.
local east=assert(app.builder:create_room({premise_id=premise.id,name='Office',width=4,depth=4,height=3,generate_shell=false,
    transform={position={x=105.2,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local floor=assert(P:create({generator='box',params={size={10,4,0.2}},premise_id=premise.id,room_id=room.id,collision=true,
    collision_rules={per_room=true,doorways='keep'},transform={position={x=102,y=0,z=-0.1,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
cs=colliders(floor.object.id)
local by={};for _,c in ipairs(cs) do by[c.room_id or '']=(by[c.room_id or ''] or 0)+dims(c).x end
-- The office volume starts half a wall before its interior; the rest (lobby volume and any gap) stays with the floor's room.
local east_start=105.2-2-east.wall_thickness/2
assert(close(by[east.id],107-east_start) and close(by[room.id],east_start-97),'split at the room boundary: '..tostring(by[room.id])..' / '..tostring(by[east.id]))
local rep=C:report({premise_id=premise.id})
local lobby;for _,row in ipairs(rep.rooms) do if row.room_id==room.id then lobby=row end end
assert(lobby and lobby.colliders>=1 and lobby.blocks_player>=1)
h=#model.undo_stack
local off=assert(C:set_room_enabled(east.id,false));assert(off.colliders>=1 and #model.undo_stack==h+1)
for _,c in ipairs(cs) do if c.room_id==east.id then assert(model:get_object(c.id).enabled==false and not app.placement:is_tracked(model:get_object(c.id))) end end
local scoped=app.build_export:_objects({premise_id=premise.id})
local disabled_ids={};for _,d in ipairs(app.build_export.last_disabled_collision) do disabled_ids[d.id]=true end
for _,x in ipairs(scoped) do assert(not disabled_ids[x.id],'disabled room collision is not exported') end
assert(next(disabled_ids),'and it is reported')
assert(C:set_room_enabled(east.id,true))

-- Too many colliders: refused, nothing changes.
local many={};for i=1,150 do many[i]=B({i*2,0,0.5},{1,1,1}) end
local row=assert(P:create({generator='compound',params={parts=many},premise_id=premise.id,collision=true,transform={position={x=0,y=-80,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local count=#model.data.objects;h=#model.undo_stack
assert(not C:set_rules('object:'..row.object.id,{exclude={{center={0,0,0.5},size={1000,0.2,0.2}}}}),'300 pieces are over the limit')
assert(#model.data.objects==count and #model.undo_stack==h and C:get_rules('object:'..row.object.id).rules.exclude==nil)
assert(C:set_rules('object:'..row.object.id,{mode='bounds'}) and #colliders(row.object.id)==1)

-- Preview of generator output.
local pv=assert(C:preview({generator='wall',params={length=4,height=3,openings={{offset=0,width=1,height=2}}},rules={mode='bounds'}}))
assert(pv.colliders==1 and pv.preset=='World Static' and pv.stats.source_boxes==3)

-- Parametric rooms: room-scope rules from the spec.
local gen=assert(app.room_generator:create({spec={name='Tiled',width=4,length=4,doors={{wall='south'}},collision_rules={actors='player_vehicles'}},premise_id=premise.id,
    transform={position={x=200,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local rec=app.room_generator:get(gen.room.id)
assert(C:get_rules('room:'..gen.room.id).rules.actors=='player_vehicles')
assert(preset_of(colliders(rec.piece_ids.walls)[1])=='Block Player and Vehicles')

-- Bridge.
local g=assert(app.bridge:handle({id='c1',op='collision_rules_get',args={scope='default'}}));assert(g.defaults.mode=='exact' and g.actor_presets.player=='Player Blocker')
assert(assert(app.bridge:handle({id='c2',op='collision_rules_set',args={scope='object:'..north.object.id,rules={actors='all'}}})).rules.actors=='all')
assert(assert(app.bridge:handle({id='c3',op='collision_rules_preview',args={object_id=north.object.id,rules={doorways='keep'}}})).colliders==1)
assert(assert(app.bridge:handle({id='c4',op='collision_rules_regenerate',args={room_id=room.id}})).objects>=2)
assert(assert(app.bridge:handle({id='c5',op='collision_rules_report',args={premise_id=premise.id}})).count>=2)
assert(assert(app.bridge:handle({id='c6',op='collision_rules_room_enabled',args={room_id=room.id,enabled=true}})).enabled)

-- Plan op.
local plan={format='locationstudio-authoring-plan',version=2,origin={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},steps={
    {op='create_premise',as='p',name='Plan'},
    {op='create_room',as='r',premise_id='$p',name='Hall',width=4,depth=4,height=3},
    {op='set_collision_rules',room_id='$r',rules={actors='npc'}},
    {op='create_procedural',as='w',premise_id='$p',room_id='$r',generator='box',params={size={4,0.2,3}},offset={x=0,y=2,z=0},collision=true,collision_rules={mode='bounds'},material={template='base\\a.mesh'}}}}
assert(app.authoring_plans:execute(plan))
local hall;for _,x in ipairs(model.data.rooms) do if x.name=='Hall' then hall=x end end
assert(C:get_rules('room:'..hall.id).rules.actors=='npc')
assert(not app.authoring_plans:validate({format='locationstudio-authoring-plan',version=2,steps={{op='set_collision_rules',rules={mode='x'}}}}).valid)

-- UI.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selection:set('object',slab.object.id)
env:draw()
env.clicks['Selected geometry: '..model:get_object(slab.object.id).name..'##crscope_2']=true;env:draw()
assert(app.ui.spatial.cr_scope=='object:'..slab.object.id)
app.ui.spatial.cr_text='{"mode":"bounds","actors":"camera"}'
env.clicks['PREVIEW##cr']=true;env:draw();assert(app.ui.spatial.cr_preview.preset=='Block PhotoMode Camera')
env.clicks['APPLY RULES##cr']=true;env:draw()
assert(preset_of(colliders(slab.object.id)[1])=='Block PhotoMode Camera')

print('LocationStudio collision generator: OK')
