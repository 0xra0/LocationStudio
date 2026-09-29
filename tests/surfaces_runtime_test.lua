local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local S=assert(app.surfaces,'semantic surfaces must be constructed')
local Surf=getmetatable(S).__index
local P=require('modules/procedural')
local RG=require('modules/room_generator')
local model=app.model
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-3) end
local function fails(needle,res,err) assert(res==nil,'expected a failure: '..tostring(needle));assert(tostring(err):find(needle,1,true),'expected "'..needle..'" in: '..tostring(err)) end
local function tags(list) local by={};for _,s in ipairs(list) do by[s.tag]=(by[s.tag] or 0)+1 end;return by end
local function box(c,sz,extra) local p={shape='box',center={x=c[1],y=c[2],z=c[3]},size={x=sz[1],y=sz[2],z=sz[3]},rotation={roll=0,pitch=0,yaw=0},material='main'};for k,v in pairs(extra or {}) do p[k]=v end;return p end

-- Vocabulary and tag names.
local vocab=S:vocabulary()
local known={};for _,t in ipairs(vocab.tags) do known[t.tag]=t end
for _,t in ipairs({'floor','wall','ceiling','desk','shelf','road','medical_surface','industrial_surface'}) do assert(known[t],'vocabulary lacks '..t) end
assert(known.medical_surface.orientation=='up' and known.wall.orientation=='side' and known.ceiling.orientation=='down')
assert(Surf.check_tag('conveyor_belt'),'custom tags are allowed')
fails('lowercase',Surf.check_tag('Desk'))
fails('lowercase',Surf.check_tag('9lives'))

-- Parts: annotations, implicit top tags, hidden faces.
local info=assert(P.generate('box',{size={2,1,0.9}},'counter'))
assert(#info.surfaces==1 and info.surfaces[1].tag=='counter' and close(info.surfaces[1].center.z,0.9) and close(info.surfaces[1].size.u*info.surfaces[1].size.v,2))
-- A desk: legs stand under the top, so only the top is tagged.
local desk_parts={box({0,0,0.74},{1.6,0.8,0.04}),box({-0.78,0,0.36},{0.04,0.8,0.72}),box({0.78,0,0.36},{0.04,0.8,0.72})}
info=assert(P.generate('compound',{parts=desk_parts},'desk'))
assert(#info.surfaces==1 and info.surfaces[1].tag=='desk' and close(info.surfaces[1].center.z,0.76),'only the visible top: '..#info.surfaces)
-- Part annotations win over the object tag; sides; traits; retag.
local parts={box({0,0,0.5},{1,1,1},{surface={top='machine',sides='industrial_surface',traits={'hot'}}}),box({3,0,0.25},{1,1,0.5})}
info=assert(P.generate('compound',{parts=parts},{tag='crate',traits={'metal'}}))
local by=tags(info.surfaces);assert(by.machine==1 and by.industrial_surface==4 and by.crate==1,'annotated faces + implicit top')
for _,s in ipairs(info.surfaces) do
    if s.tag=='machine' then assert(#s.traits==2,'part and object traits merge') end
    if s.tag=='industrial_surface' then assert(math.abs(s.normal.z)<1e-6 and close(s.size.v,1) and close(s.u.z,0),'vertical faces: v points up') end
end
info=assert(P.generate('compound',{parts=parts},{retag={machine='workbench',industrial_surface=false}}))
by=tags(info.surfaces);assert(by.workbench==1 and by.industrial_surface==nil and by.machine==nil)
fails('unknown surface key',P.generate('compound',{parts={box({0,0,0},{1,1,1},{surface={roof='x'}})}}))
fails('surface tag must be lowercase',P.generate('box',{size={1,1,1}},'Bad Tag'))
-- Generators tag their own faces.
by=tags(assert(P.generate('floor',{width=4,depth=3})).surfaces);assert(by.floor==1)
info=assert(P.generate('ceiling',{width=4,depth=3,height=3}));assert(info.surfaces[1].tag=='ceiling' and info.surfaces[1].normal.z==-1 and close(info.surfaces[1].center.z,3))
info=assert(P.generate('wall',{length=4,height=3,thickness=0.2,openings={{offset=0,width=1,height=2.1}}}))
by=tags(info.surfaces);assert(by.wall==6,'three segments, two faces each: '..tostring(by.wall))
by=tags(assert(P.generate('stairs',{width=1.2,height=1.8,length=3,steps=6,landing=1})).surfaces);assert(by.stairs==6 and by.platform==1)
info=assert(P.generate('ramp',{width=2,length=4,height=1}));assert(info.surfaces[1].tag=='ramp' and close(info.surfaces[1].size.v,math.sqrt(17)) and info.surfaces[1].normal.z>0.9)
-- Polygon floors keep their outline; upright cylinder caps are round.
info=assert(P.generate('floor',{points={{0,0},{4,0},{0,3}}}));assert(info.surfaces[1].poly and #info.surfaces[1].poly==3 and close(Surf.area(info.surfaces[1]),6))
info=assert(P.generate('compound',{parts={{shape='cylinder',center={x=0,y=0,z=0.4},radius=0.5,length=0.8,sides=16,rotation={roll=0,pitch=90,yaw=0},material='main'}}},'table'))
assert(info.surfaces[1].tag=='table' and close(info.surfaces[1].center.z,0.8) and #info.surfaces[1].poly==16)
-- Explicit surfaces.
info=assert(P.generate('box',{size={1,1,1}},{surfaces={{tag='display',center={0,0.5,0.5},size={0.8,0.6},orientation='side'}}}))
assert(#info.surfaces==1 and info.surfaces[1].normal.y==1 and info.surfaces[1].tag=='display')
fails('positive size',P.generate('box',{size={1,1,1}},{surfaces={{tag='x',center={0,0,0},size={0,1}}}}))

-- Procedural objects save their surfaces; queries return them in world space.
local premise=assert(model:add_premise({name='Surface Lab',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
app.selected_premise_id=premise.id
local T=function(x,y,z,yaw) return {position={x=x,y=y,z=z,w=1},rotation={roll=0,pitch=0,yaw=yaw or 0}} end
local d=assert(app.procedural:create({generator='compound',params={parts=desk_parts},surface={tag='desk',traits={'office'}},premise_id=premise.id,transform=T(10,20,0,90),spawn=false}))
assert(d.surfaces.count==1 and d.surfaces.by_tag.desk==1)
local q=S:query({premise_id=premise.id,tags='desk'})
assert(q.count==1 and close(q.items[1].center.x,10) and close(q.items[1].center.z,0.76) and q.items[1].orientation=='up' and q.items[1].object_id==d.object.id)
assert(close(math.abs(q.items[1].u.y),1),'u turns with the object')
assert(S:query({premise_id=premise.id,tags='work_surface'}).count==1,'groups match')
assert(S:query({premise_id=premise.id,traits='office'}).count==1 and S:query({premise_id=premise.id,traits='medical'}).count==0,'traits match')
-- Updating keeps the option; replacing it retags.
assert(app.procedural:update(d.object.id,{params={parts=desk_parts}}))
assert(S:query({premise_id=premise.id,tags='desk'}).count==1)
assert(app.procedural:update(d.object.id,{surface='medical_surface'}))
assert(S:query({premise_id=premise.id,tags='desk'}).count==0 and S:query({premise_id=premise.id,tags='medical'}).count==1)
assert(app.procedural:update(d.object.id,{surface='desk'}))

-- Parametric rooms: floor, walls without openings, ceiling, exterior walls; traits.
local plan=assert(RG.plan({width=5,length=4,height=3,wall_thickness=0.2,doors={{wall='south',width=1,height=2.1}},surfaces={traits={'medical'}}}))
local function area_of(list,tag) local a=0;for _,s in ipairs(list) do if s.tag==tag then a=a+s.size.u*s.size.v end end;return a end
assert(#plan.surfaces.floor==1 and #plan.surfaces.ceiling==1 and plan.surfaces.floor[1].traits[1]=='medical')
assert(close(area_of(plan.surfaces.walls,'wall'),2*(5+4)*3-1*2.1),'interior wall area minus the door: '..area_of(plan.surfaces.walls,'wall'))
assert(close(area_of(plan.surfaces.walls,'exterior_wall'),2*(5.4+4)*3-1*2.1),'exterior wall area')
for _,s in ipairs(plan.surfaces.walls) do
    if s.tag=='wall' then assert(s.center.x*s.normal.x+s.center.y*s.normal.y<0,'interior walls face into the room') end
end
fails('unknown surfaces key',RG.plan({surfaces={roof='x'}}))
plan=assert(RG.plan({width=4,length=4,surfaces={floor='road',ceiling=false,exterior=false}}))
assert(plan.surfaces.floor[1].tag=='road' and #plan.surfaces.ceiling==0)
local room=assert(app.room_generator:create({spec={name='Exam',width=5,length=4,height=3,doors={{wall='south',width=1}},surfaces={traits={'medical'}}},premise_id=premise.id,transform=T(0,0,0)}))
local rq=S:query({room_id=room.room.id})
assert(rq.by_tag.floor==1 and rq.by_tag.ceiling==1 and rq.by_tag.wall>=5 and rq.by_tag.exterior_wall>=5,'room surfaces')
assert(S:query({room_id=room.room.id,tags='floor',traits='medical'}).count==1)
assert(app.room_generator:preview({width=5,length=4}).surfaces.floor==1)

-- Sampling: props on the floor avoid the desk, go on the desk top, respect spacing.
local d2=assert(app.procedural:create({generator='compound',params={parts=desk_parts},surface='desk',premise_id=premise.id,room_id=room.room.id,transform=T(0,0.8,0),spawn=false}))
local floor_pts=assert(S:sample({room_id=room.room.id,tags='floor',pattern='grid',spacing=0.25,footprint=0.2,height=0.3,avoid_objects=true,premise_id=premise.id}))
assert(floor_pts.count>20 and floor_pts.rejected.occupied>0,'floor points under the desk are rejected')
for _,p in ipairs(floor_pts.items) do
    assert(not (math.abs(p.position.x)<0.8 and math.abs(p.position.y-0.8)<0.4),'no point under the desk')
    assert(p.position.z==0 and p.surface.tag=='floor' and p.rotation.yaw==0)
end
local top=assert(S:sample({room_id=room.room.id,tags='work_surface',count=3,seed=7,footprint=0.2,min_distance=0.3}))
assert(top.count==3,'three props on the desk: '..top.count)
for i,p in ipairs(top.items) do
    assert(close(p.position.z,0.76) and p.surface.object_id==d2.object.id)
    for j=i+1,#top.items do local o=top.items[j].position;assert((o.x-p.position.x)^2+(o.y-p.position.y)^2>=0.3^2-1e-6,'min_distance') end
end
local again=assert(S:sample({room_id=room.room.id,tags='work_surface',count=3,seed=7,footprint=0.2,min_distance=0.3}))
for i,p in ipairs(top.items) do assert(p.position.x==again.items[i].position.x and p.position.y==again.items[i].position.y,'same seed, same points') end
-- Clearance: a tall item does not fit under the desk top, a small one does (when not avoiding objects).
local under=assert(S:sample({room_id=room.room.id,tags='floor',pattern='grid',spacing=0.2,footprint=0.2,height=1.0,avoid_objects=false}))
for _,p in ipairs(under.items) do assert(not (math.abs(p.position.x)<0.7 and math.abs(p.position.y-0.8)<0.3),'1 m items need 1 m of clearance') end
assert(under.rejected.clearance>0)
-- Walls: decals face into the room and project into the wall; lights hang from the ceiling.
local decals=assert(S:sample({kind='decal',room_id=room.room.id,tags='wall',pattern='center',footprint={0.8,0.6},elevation=1.5}))
assert(decals.count>=4)
for _,p in ipairs(decals.items) do
    assert(p.rotation.pitch==-90 and close(p.position.z,1.5))
    local r=math.rad(p.rotation.yaw);local fx,fy=-math.sin(r),math.cos(r)
    assert(close(fx,p.normal.x) and close(fy,p.normal.y),'yaw faces along the wall normal')
    assert(close(p.position.x*p.normal.x+p.position.y*p.normal.y,-(2.5*math.abs(p.normal.x)+2*math.abs(p.normal.y))+0.005),'on the inner face, 5 mm off it')
end
local lights=assert(S:sample({kind='light',room_id=room.room.id,spacing=2.4}))
assert(lights.count>=2 and lights.items[1].surface.tag=='ceiling' and close(lights.items[1].position.z,3-0.15),'lights 15 cm under the ceiling')
fails('kind must be one of',S:sample({kind='teapot'}))
fails('pattern must be',S:sample({pattern='spiral'}))

-- Populate: one authoring plan, one undo step.
local undo=#model.undo_stack
local dry=assert(S:populate({kind='marker',room_id=room.room.id,tags='work_surface',count=2,seed=1,footprint=0.2,height=0.2,dry_run=true}))
assert(dry.dry_run and dry.count==2 and #model.undo_stack==undo)
local locs=#model.data.locations
local pop=assert(S:populate({kind='marker',name='Supply {i}',room_id=room.room.id,tags='work_surface',count=2,seed=1,footprint=0.2,height=0.2,type='prop_spot'}))
assert(pop.created==2 and #model.data.locations==locs+2 and #model.undo_stack==undo+1)
local spot=model.data.locations[#model.data.locations];assert(spot.name=='Supply 2' and spot.type=='prop_spot' and close(spot.transform.position.z,0.76))
assert(app.actions:history('undo'));assert(#model.data.locations==locs)
local asset=model:add_asset({name='Surface Mug',category='Props',kind='prop',template='base\\surface\\mug.ent',layer='decoration'})
local objs=#model.data.objects
pop=assert(S:populate({kind='asset',asset_query='Surface Mug',room_id=room.room.id,tags='desk',per_surface=2,seed=3,footprint=0.15}))
assert(pop.created==2 and #model.data.objects==objs+2)
local mug=model:get_object(pop.object_ids[1]);assert(close(mug.transform.position.z,0.76) and mug.room_id==room.room.id and mug.premise_id==premise.id)
fails('no placements',S:populate({kind='marker',tags='bed',premise_id=premise.id}))
fails('asset placements need',S:populate({kind='asset',room_id=room.room.id,tags='desk',count=1}))
-- Placed props now block the spots they occupy.
local after=assert(S:sample({room_id=room.room.id,tags='desk',pattern='grid',spacing=0.05,footprint=0.15,premise_id=premise.id}))
for _,p in ipairs(after.items) do for _,id in ipairs(pop.object_ids) do local o=model:get_object(id).transform.position;assert(math.abs(p.position.x-o.x)>0.05 or math.abs(p.position.y-o.y)>0.05) end end

-- Plan op: validation and from_plan scoping.
local v=app.authoring_plans:validate({format='locationstudio-authoring-plan',version=2,steps={{op='populate_surfaces',kind='teapot'}}})
assert(not v.valid and v.errors[1]:find('kind must be one of',1,true))
v=app.authoring_plans:validate({format='locationstudio-authoring-plan',version=1,steps={{op='populate_surfaces',kind='marker'}}})
assert(not v.valid and v.errors[1]:find('requires plan version 2',1,true))
local built=assert(app.authoring_plans:execute({format='locationstudio-authoring-plan',version=2,origin=T(50,0,0),steps={
    {op='create_procedural',as='bench',generator='box',params={size={2,0.8,0.9}},surface='workbench',premise_id=premise.id,offset={x=0,y=0,z=0},spawn=false},
    {op='populate_surfaces',as='tools',kind='marker',from_plan=true,tags='workbench',count=3,seed=2,footprint=0.2},
}}))
for _,id in ipairs(built.outputs[2].ids) do local l=model:get_location(id);assert(l and close(l.transform.position.x,50,1.01) and close(l.transform.position.z,0.9),l and (l.transform.position.x..","..l.transform.position.y..","..l.transform.position.z)) end
for _,id in ipairs(built.outputs[2].ids) do local l=model:get_location(id);assert(l and close(l.transform.position.x,50,1.01) and close(l.transform.position.z,0.9)) end

-- Hand tags from bounds for any object (e.g. a game-asset desk).
local prop=model:add_object({premise_id=premise.id,name='Vanilla Table',kind='prop',template='base\\t.ent',transform=T(-10,0,0,90),size={x=1,y=1,z=1},enabled=true,
    metadata={asset_bounds={min={x=-0.6,y=-0.4,z=0},max={x=0.6,y=0.4,z=0.75}}}})
local tagged=assert(S:tag({object_id=prop.id,tag='table',inset=0.05}))
assert(tagged.count==1 and close(tagged.items[1].center.z,0.75) and close(tagged.items[1].size.u,1.1) and close(tagged.items[1].size.v,0.7) and tagged.items[1].source=='manual')
assert(S:tag({object_id=prop.id,tag='partition',face='front'}).count==2)
assert(S:object(prop.id).by_tag.partition==1)
assert(S:untag({object_id=prop.id,tag='partition'}).removed==1 and S:object(prop.id).count==1)
fails('no hand-tagged surface with tag',S:untag({object_id=prop.id,tag='nope'}))
fails('face must be',S:tag({object_id=prop.id,tag='x',face='inside'}))
local bare=model:add_object({premise_id=premise.id,name='No Bounds',kind='prop',template='base\\n.ent',transform=T(0,0,0),size={x=1,y=1,z=1},enabled=true})
fails('the object has no bounds',S:tag({object_id=bare.id,tag='table'}))
assert(S:tag({object_id=bare.id,surfaces={{tag='shelf',center={0,0,1},size={1,0.4}}}}).count==1,'explicit hand tags need no bounds')

-- Refresh recomputes derived surfaces (projects made before surfaces existed).
local rp=model:get_object(room.room and app.room_generator:get(room.room.id).piece_ids.floor)
rp.metadata.procedural.surfaces=nil;rp.metadata.procedural.params.surfaces=nil
assert(S:query({room_id=room.room.id,tags='floor'}).count==0)
local ref=assert(S:refresh({premise_id=premise.id}));assert(ref.updated>0 and #ref.failed==0)
assert(S:query({room_id=room.room.id,tags='floor',traits='medical'}).count==1,'room surfaces come back with their traits')

-- Grammar: surfaces from rules, populate estimates in the preview and real placements.
local Gr=app.env_grammar
local g={id='surf_test',start='Root',size={8,6,3},params={wall=0.15},
    rules={Root={{room={wall_thickness='$wall',surfaces={traits={'lab'}}}},{place={at={'sx/2-1','sy/2-0.4',0},size={2,0.8,1},['do']={{geometry={generator='box',params={size={2,0.8,0.9}},surface='lab_surface'}}}}}}},
    populate={{kind='marker',tags='lab_surface',count=2,footprint=0.2,type='sample_spot'},{kind='light',tags='ceiling',spacing=3,config={intensity=10}},{['if']='wall > 1',kind='marker',tags='floor'}}}
local prev=assert(Gr:preview({doc=g,transform=T(0,100,0)}))
assert(prev.valid,table.concat(prev.errors or {},'; '))
assert(prev.stats.surfaces.by_tag.lab_surface==1 and prev.stats.surfaces.by_tag.floor==1 and prev.stats.surfaces.by_tag.wall==4)
assert(#prev.populate==2 and prev.populate[1].estimate==2 and prev.populate[2].estimate>=2,'the if drops the third entry')
local gen=assert(Gr:generate({doc=g,transform=T(0,100,0),build_id='surf1',seed=1}))
local spots=0;for _,l in ipairs(model.data.locations) do if l.type=='sample_spot' then spots=spots+1;assert(close(l.transform.position.z,0.9)) end end
assert(spots==2,'populate markers on the lab bench: '..spots)
assert(Gr:regenerate('surf1',{seed=2}))
spots=0;for _,l in ipairs(model.data.locations) do if l.type=='sample_spot' then spots=spots+1 end end
assert(spots==2,'regenerating replaces the placements: '..spots)
assert(Gr:remove('surf1'))
spots=0;for _,l in ipairs(model.data.locations) do if l.type=='sample_spot' then spots=spots+1 end end
assert(spots==0,'removing the build removes the placements')
local _,perr=Gr:preview({doc={id='bad',start='Root',size={4,4,3},rules={Root={{room={}}}},populate={{kind='teapot'}}}})
assert(tostring(perr):find('kind must be',1,true))
_,perr=Gr:preview({doc={id='bad2',start='Root',size={4,4,3},rules={Root={{room={}}}},populate={{kind='marker',pattern='spiral'}}}})
assert(tostring(perr):find('pattern must be',1,true))

-- Built-in grammars carry semantic surfaces.
local clinic=assert(Gr:preview({grammar='clinic',transform=T(0,300,0),seed=4}))
assert(clinic.valid and (clinic.stats.surfaces.by_tag.medical_surface or 0)>0 and (clinic.stats.surfaces.by_tag.desk or 0)>0 and (clinic.stats.surfaces.by_tag.bed or 0)>0)
local lab=assert(Gr:preview({grammar='laboratory',transform=T(0,300,0),seed=4}))
assert((lab.stats.surfaces.by_tag.lab_surface or 0)>0)
local ind=assert(Gr:preview({grammar='industrial',transform=T(0,300,0),seed=4}))
assert((ind.stats.surfaces.by_tag.industrial_surface or 0)>0 and (ind.stats.surfaces.by_tag.shelf or 0)>0)

-- The bridge exposes the operations.
assert(#assert(app.bridge:handle({id='s1',op='surface_vocabulary',args={}})).tags>20)
assert(assert(app.bridge:handle({id='s2',op='surface_query',args={premise_id=premise.id,tags='desk'}})).count>=1)
assert(assert(app.bridge:handle({id='s3',op='surface_object',args={object_id=prop.id}})).count==1)
assert(assert(app.bridge:handle({id='s4',op='surface_sample',args={room_id=room.room.id,tags='floor',count=2,seed=1}})).count==2)
assert(assert(app.bridge:handle({id='s5',op='surface_tag',args={object_id=prop.id,tag='seat',face='top',height=0.45}})).count==2)
assert(assert(app.bridge:handle({id='s6',op='surface_untag',args={object_id=prop.id,tag='seat'}})).removed==1)
assert(assert(app.bridge:handle({id='s7',op='surface_populate',args={kind='marker',room_id=room.room.id,tags='floor',count=1,dry_run=true}})).dry_run)
assert(assert(app.bridge:handle({id='s8',op='surface_refresh',args={premise_id=premise.id}})).updated>0)

-- UI: Spatial -> Surfaces.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selected_premise_id=premise.id
app.selection:set('object',prop.id)
env:draw()
assert(env.labels['TAG FROM BOUNDS##sf'] and env.labels['POPULATE##sfp'],'surfaces panel is reachable')
env.clicks['TAG FROM BOUNDS##sf']=true;env:draw()
assert(S:object(prop.id).by_tag.table==2,'the panel tags the top as a table')
env.clicks['PREVIEW##sfp']=true;env:draw()
local before_locs=#model.data.locations
env.clicks['POPULATE##sfp']=true;env:draw()
assert(#model.data.locations>before_locs,'the panel populates markers on work surfaces')
app.selection:set('object',prop.id);env:draw()
env.clicks['CLEAR HAND TAGS##sf']=true;env:draw()
assert(S:object(prop.id).count==0,tostring(app.ui and app.ui.toast))
print('LocationStudio semantic surfaces: OK')
