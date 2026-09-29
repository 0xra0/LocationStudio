local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local Gr=assert(app.env_grammar,'environment grammar must be constructed')
local G=getmetatable(Gr).__index
local model=app.model
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-4) end
local function fails(needle,res,err) assert(res==nil,'expected a failure: '..tostring(needle));assert(tostring(err):find(needle,1,true),'expected "'..needle..'" in: '..tostring(err)) end
local ORIGIN={position={x=100,y=200,z=10,w=1},rotation={roll=0,pitch=0,yaw=0}}

-- Expressions.
assert(G.eval('2+3*4')==14 and G.eval('(2+3)*4')==20 and G.eval('2^3')==8 and G.eval('-2^2')==-4 and G.eval('7 % 3')==1)
assert(G.eval('$a*2+b',{a=3,b=1})==7,'$ prefix is optional')
assert(G.eval('min(4, 2, 3) + max(1, 5)')==7 and G.eval('clamp(12, 0, 10)')==10 and G.eval('round(2.346, 2)')==2.35 and G.eval('floor(2.7) + ceil(0.2)')==3)
assert(G.eval('x > 2 and y',{x=3,y=true})==true and G.eval('x > 2 && !y',{x=3,y=false})==true,'logic')
assert(G.eval("side == 'north' ? 1 : 2",{side='north'})==1 and G.eval("if(0, 1, 2)")==2)
assert(G.eval("opposite('east')")=='west')
local _,e=G.eval('nope + 1');assert(e:find('unknown variable nope'))
_,e=G.eval('1/0');assert(e:find('division by zero'))
_,e=G.eval('1 +');assert(e and e:find('unexpected end'))
_,e=G.eval('foo(1)');assert(e:find('unknown function'))
local r1=G.eval('rand()',{},function() return 0.25 end);assert(r1==0.25)

-- Validation.
local function doc(rules,extra) local d={id='t',start='Root',size={10,4,3},rules=rules};for k,v in pairs(extra or {}) do d[k]=v end;return d end
local _,verr=G.normalize(doc({Root={'Missing'}}));assert(verr:find('unknown rule Missing'))
_,verr=G.normalize(doc({Root={{explode={}}}}));assert(verr:find('unknown operation "explode"'))
_,verr=G.normalize(doc({Root={{geometry={generator='teapot'}}}}));assert(verr:find('unknown generator teapot'))
_,verr=G.normalize(doc({Root={{split={axis='w',parts={}}}}}));assert(verr:find('split needs axis'))
_,verr=G.normalize(doc({Root={{room={},door={}}}}));assert(verr:find('has both'))
_,verr=G.normalize(doc({Root={}},{start='Nope'}));assert(verr:find('start rule not found'))
local lib={a={id='a',include='b',rules={X={}}},b={id='b',include='a',rules={Y={}}}}
_,verr=G.normalize(lib.a,function(id) return lib[id] end);assert(verr:find('include cycle'))
_,verr=G.normalize({id='c',include='zzz',rules={X={}}},function() return nil end);assert(verr:find('included grammar not found'))

local function expand(rules,args,extra) local g=assert(G.normalize(doc(rules,extra)));return G.expand(g,args) end
local function markers(exp) local out={};for _,it in ipairs(exp.items) do if it.kind=='marker' then out[#out+1]=it end end;return out end

-- Split: absolute parts first, the rest shared by weight. The start scope is centred on the origin.
local exp=assert(expand({Root={{split={axis='x',parts={{size=2,['do']={{marker={}}}},{size='~1',['do']={{marker={}}}},{size='~3',['do']={{marker={}}}}}}}}}))
local m=markers(exp);assert(#m==3 and close(m[1].offset.x,-4) and close(m[2].offset.x,-2) and close(m[3].offset.x,2) and close(m[3].offset.y,0))
fails('split sizes add up to 11.00 m but the scope is 10.00 m',expand({Root={{split={axis='x',parts={{size=11,['do']={{marker={}}}}}}}}}))
-- Expressions in sizes see the scope: sx/2 halves it.
m=markers(assert(expand({Root={{split={axis='x',parts={{size='sx/2',['do']={{marker={}}}},{size='~1'}}}}}})));assert(#m==1 and close(m[1].offset.x,-2.5))

-- Repeat: every (fitted), step (exact, centred or from offset), count.
local function xs(body) local mm=markers(assert(expand({Root={{['repeat']=body}}})));local out={};for i,v in ipairs(mm) do out[i]=v.offset.x end;return out end
body={axis='x',every=3,['do']={{marker={}}}}
local x=xs(body);assert(#x==3 and close(x[1],-10/3) and close(x[2],0) and close(x[3],10/3),'every 3 on 10 m: 3 tiles of 3.33 m')
x=xs({axis='x',step=3,['do']={{marker={}}}});assert(#x==3 and close(x[1],-3) and close(x[3],3),'step 3: exact, centred')
x=xs({axis='x',count=4,['do']={{marker={}}}});assert(#x==4 and close(x[1],-3.75) and close(x[4],3.75))
x=xs({axis='x',step=3,offset=1,size=1,['do']={{marker={}}}});assert(#x==3 and close(x[1],-4) and close(x[3],2),'from the offset while tiles fit: '..#x)
x=xs({axis='x',every=2,margin=2,['do']={{marker={}}}});assert(#x==3 and close(x[1],-2),'margins shrink the run')
-- Tile variables i and n.
m=markers(assert(expand({Root={{['repeat']={axis='x',count=3,['do']={{marker={name='Tile {i+1} of {n}'}}}}}}})));assert(m[3].name=='Tile 3 of 3')
-- Vertical repeat stacks floors.
m=markers(assert(expand({Root={{['repeat']={axis='z',step=3,['do']={{marker={}}}}}}},{size={4,4,9}})));assert(#m==3 and close(m[2].offset.z,3) and close(m[3].offset.z,6))

-- Walls: strips inside each side, x along the wall, y inward (the item faces into the scope).
m=markers(assert(expand({Root={{walls={depth=1,['do']={{marker={name='{side}'}}}}}}})))
local by={};for _,v in ipairs(m) do by[v.name]=v end
assert(close(by.south.offset.y,-1.5) and by.south.yaw==0 and close(by.north.offset.y,1.5) and by.north.yaw==180)
assert(close(by.east.offset.x,4.5) and by.east.yaw==90 and close(by.west.offset.x,-4.5) and by.west.yaw==-90)
-- 'at' inside a strip: x runs along the wall. The north strip runs from east to west.
m=markers(assert(expand({Root={{walls={sides={'north'},depth=1,['do']={{marker={at={1,0,0}}}}}}}})));assert(close(m[1].offset.x,4) and close(m[1].offset.y,2))

-- Place: min corner or centre, optional yaw about the centre.
m=markers(assert(expand({Root={{place={at={1,1,0},size={2,2,1},['do']={{marker={}}}}}}})));assert(close(m[1].offset.x,-3) and close(m[1].offset.y,0))
m=markers(assert(expand({Root={{place={center={5,2,0.5},size={4,2,1},yaw=90,['do']={{marker={at={0,0,0}}}}}}}})))
-- The 4 x 2 box turned 90 degrees about (0, 0): its min corner goes to (1, -2).
assert(close(m[1].offset.x,1) and close(m[1].offset.y,-2) and m[1].yaw==90)

-- Variables: grammar params, overrides, set, child params, and literal vs expression values.
exp=assert(expand({Root={{set={k='w*2'}},{marker={name='{k}',type='$kind'}},{call={symbol='Sub',params={q='=k+1'}}}},Sub={{marker={name='{q}'}}}},{params={w=5}},{params={w=1,kind='spot'}}))
m=markers(exp);assert(m[1].name=='10' and m[1].type=='spot' and m[2].name=='11')
exp=assert(expand({Root={{marker={name='{w}'}}}},{params={w=3,extra=1}},{params={w=1}}));assert(markers(exp)[1].name=='3' and exp.warnings[1]:find('extra'))
fails('unknown variable zz',expand({Root={{marker={name='{zz}'}}}}))
fails('unknown variable zz',expand({Root={{marker={type='$zz'}}}}))
-- Conditions on operations and rule variants.
exp=assert(expand({Root={{['if']='sx > 20',marker={}},{['if']='sx < 20',marker={name='small'}}}}));assert(#markers(exp)==1 and markers(exp)[1].name=='small')
exp=assert(expand({Root={variants={{['if']='sx > 20',['do']={{marker={name='big'}}}},{['if']='sx <= 20',['do']={{marker={name='small'}}}}}}}));assert(markers(exp)[1].name=='small')

-- Choose / chance: seeded and deterministic.
local rules={Root={{['repeat']={axis='x',count=8,['do']={{choose={{weight=1,['do']={{marker={name='a'}}}},{weight=1,['do']={{marker={name='b'}}}}}}}}}}}
local function names(seed) local out={};for _,v in ipairs(markers(assert(expand(rules,{seed=seed})))) do out[#out+1]=v.name:sub(1,1) end;return table.concat(out) end
assert(names(3)==names(3),'same seed, same layout')
local variety=false;for s=1,6 do if names(s)~=names(1) then variety=true end end;assert(variety,'seeds change choices')
local both={a=false,b=false};for c in names(1):gmatch('.') do both[c]=true end
exp=assert(expand({Root={{chance={p=1,['do']={{marker={name='yes'}}},['else']={['do']={{marker={name='no'}}}}}},{chance={p=0,['do']={{marker={name='never'}}},['else']={['do']={{marker={name='else'}}}}}}}}))
assert(markers(exp)[1].name=='yes' and markers(exp)[2].name=='else')

-- Limits.
fails('nest deeper',expand({Root={'Root'}}))
fails('tiles; the limit is 1900',expand({Root={{['repeat']={axis='x',step=0.02,['do']={{marker={}}}}}}},{size={100,4,3}}))
fails('more than 1900 items',expand({Root={{['repeat']={axis='x',count=50,['do']={{['repeat']={axis='y',count=50,['do']={{marker={}}}}}}}}}}))

-- Rooms: the scope is the outer footprint, later operations run inside the walls.
exp=assert(expand({Root={{room={wall_thickness=0.2}},{marker={name='{sx}x{sy}x{sz} t{t}'}}}}))
assert(#exp.rooms==1 and close(exp.rooms[1].width,9.6) and close(exp.rooms[1].length,3.6) and exp.rooms[1].height==3)
assert(markers(exp)[1].name=='9.6x3.6x3 t0.2' and markers(exp)[1].room==exp.rooms[1],'items inside a room belong to it')
fails('room needs at least 1 m inside its walls',expand({Root={{room={wall_thickness=0.2}}}},nil,{size={1.2,4,3}}))
fails('ceiling type must be',expand({Root={{room={ceiling={type='dome'}}}}}))
fails('door needs an enclosing room',expand({Root={{door={}}}}))
fails('as close to the',expand({Root={{room={}},{door={}}}}))
-- A door in the east strip of the west room cuts both rooms' shared wall.
local two={Root={{split={axis='x',parts={{size='~1',symbol='West'},{size='~1',symbol='East'}}}}},
    West={{room={name='West',wall_thickness=0.15}},{walls={sides={'east'},depth=0.5,['do']={{door={width=1.2}}}}},{walls={sides={'north'},depth=0.5,['do']={{window={width=1.5}}}}}},
    East={{room={name='East',wall_thickness=0.15}}}}
exp=assert(expand(two))
local west,east=exp.rooms[1],exp.rooms[2]
assert(west.final.doors[1].wall=='east' and close(west.final.doors[1].offset,0) and west.final.doors[1].width==1.2)
assert(#east.final.doors==1 and east.final.doors[1].wall=='west' and close(east.final.doors[1].offset,0),'connected into the room behind the wall')
assert(#west.final.windows==1 and #east.final.windows==0 and exp.stats.connected_openings==1,'an outside window has no room behind it')
-- connect=false keeps it to one room; an opening that does not fit the other room is reported.
two.West[2].walls['do'][1].door.connect=false
exp=assert(expand(two));assert(#exp.rooms[2].final.doors==0)
two.West[2].walls['do'][1].door.connect=nil
two.East[1].room.wall_thickness=nil
exp=assert(expand({Root={{split={axis='x',parts={{size='~1',symbol='A'},{size='~1',symbol='B'}}}}},
    A={{room={}},{walls={sides={'east'},depth=0.5,['do']={{door={width=1}}}}}},B={{split={axis='y',parts={{size=1.4,['do']={{room={}}}},{size='~1'}}}}}}))
assert(#exp.rooms==2,'the neighbour is a small room')
local tiny={Root={{split={axis='x',parts={{size='~1',symbol='A'},{size='~1',symbol='B'}}}}},
    A={{room={}},{walls={sides={'east'},depth=0.5,['do']={{door={width=1.5}}}}}},B={{place={at={0,'sy/2-0.8',0},size={'sx',1.6,'sz'},['do']={{room={}}}}}}}
local _,terr=expand(tiny,nil,{size={10,6,3}});assert(terr and terr:find('connected from'),'tells where the opening came from: '..tostring(terr))
-- Overlapping rooms warn.
exp=assert(expand({Root={{room={}},{place={at={0,0,0},size={4,3,3},['do']={{room={}}}}}}}));assert(exp.warnings[1] and exp.warnings[1]:find('overlap'))
-- A door leaf asset stands in the opening, facing out of the wall.
exp=assert(expand({Root={{room={wall_thickness=0.2}},{walls={sides={'north'},depth=0.5,['do']={{door={asset_query='door'}}}}}}}))
local leaf=exp.items[1];assert(leaf.kind=='asset' and leaf.asset_query=='door' and close(leaf.offset.y,1.9) and leaf.yaw==0)

-- Geometry: parameters are evaluated, compound parts may use arrays, the generator is checked.
exp=assert(expand({Root={{geometry={generator='compound',params={parts={{shape='box',center={0,0,'=sz/2'},size={'=sx',1,'=sz'}}}},at={'sx/2','sy/2',0},collision=false}}}}))
local geo=exp.items[1];assert(geo.params.parts[1].size.x==10 and geo.params.parts[1].center.z==1.5 and geo.collision==false and geo.layer=='decoration' and geo.parts==1)
fails('size.x must be between',expand({Root={{geometry={generator='box',params={size={0,1,1}}}}}}))

-- Every shipped grammar expands and compiles into a valid plan.
local shipped=0
for _,row in ipairs(Gr:library().items) do
    if row.start then
        shipped=shipped+1
        local p=assert(Gr:preview({grammar=row.id,seed=7,transform=ORIGIN}))
        assert(p.valid,row.id..': '..tostring(p.errors and p.errors[1]))
        assert(#p.warnings==0,row.id..': '..tostring(p.warnings[1]))
        assert(p.stats.rooms>=1 and p.steps<=2000)
        if row.id~='corridor' then assert(p.stats.rooms>=5 and p.stats.connected_openings>=4,row.id..' has connected rooms') end
    end
end
assert(shipped>=6,'corridor, industrial, clinic, apartment, bunker, laboratory')
local corridor=assert(Gr:preview({grammar='corridor',transform=ORIGIN}))
assert(corridor.stats.kinds.door==8 and corridor.stats.kinds.light==6 and corridor.rooms[1].doors==8,'door every 6 m on both walls of 24 m, lights every 4 m')
local tray=false;for _,it in ipairs(corridor.items) do if it.name=='Cable tray' then tray=true end end;assert(tray)
-- Params change the layout.
local fewer=assert(Gr:preview({grammar='corridor',params={door_every=12,lights=false,tray=false},transform=ORIGIN}))
assert(fewer.stats.kinds.door==4 and not fewer.stats.kinds.light)
assert(Gr:preview({grammar='industrial',seed=1,transform=ORIGIN}).stats.items>0)
local s1,s2=Gr:preview({grammar='industrial',seed=1}),Gr:preview({grammar='industrial',seed=2})
assert(s1 and s2)

-- Compile: edl_begin, the premise, rooms, then items linked to their rooms by alias.
local plan=assert(Gr:plan({grammar='corridor',transform=ORIGIN,build_id='c1'})).plan
assert(plan.version==2 and plan.steps[1].op=='edl_begin' and plan.steps[1].doc=='grammar_c1' and plan.steps[2].op=='create_premise' and plan.steps[3].op=='create_parametric_room')
local linked=false;for _,st in ipairs(plan.steps) do if st.op=='create_light' and st.room_id=='$room_1' then linked=true end end;assert(linked)

-- Generate: one authoring plan, one undo step.
local undo=#model.undo_stack
local gen=assert(Gr:generate({grammar='corridor',transform=ORIGIN,build_id='c1',seed=3}))
assert(#model.undo_stack==undo+1 and gen.one_undo)
local premise=assert(model:get_premise(gen.premise_id))
assert(premise.name=='Service corridor')
local rooms=0;for _,r in ipairs(model.data.rooms) do if r.premise_id==premise.id then rooms=rooms+1 end end;assert(rooms==1)
local rg=app.room_generator:list({premise_id=premise.id}).items;assert(#rg==1 and rg[1].doors==8)
local lights,geo_count=0,0
for _,o in ipairs(model.data.objects) do
    if o.premise_id==premise.id and o.kind=='light' then lights=lights+1 end
    if o.premise_id==premise.id and o.metadata and o.metadata.procedural and not o.metadata.room_generator then geo_count=geo_count+1;assert(o.room_id==rg[1].id) end
end
assert(lights==6 and geo_count==7,'6 lights, 6 light panels and a cable tray: '..lights..' '..geo_count)
local room=model:get_room(rg[1].id);assert(close(room.transform.position.x,100) and close(room.transform.position.y,200) and close(room.transform.position.z,10))
local b=Gr:builds().items;assert(#b==1 and b[1].id=='c1' and b[1].present and b[1].rooms==1)
assert(app.authoring_plans:edl_get('grammar_c1').source=='grammar')

-- Regenerate in place with new params: the previous build goes, one undo step.
undo=#model.undo_stack
local regen=assert(Gr:regenerate('c1',{params={door_every=12}}))
assert(regen.replaced and #model.undo_stack==undo+1 and not model:get_premise(premise.id) and model:get_premise(regen.premise_id))
assert(#Gr:builds().items==1 and Gr:build('c1').params.door_every==12)
assert(app.room_generator:list({premise_id=regen.premise_id}).items[1].doors==4)
local room2=model:get_room(app.room_generator:list({premise_id=regen.premise_id}).items[1].id);assert(close(room2.transform.position.x,100),'regenerating keeps the origin')
-- Undo brings back the first build.
model:undo()
assert(model:get_premise(premise.id) and not model:get_premise(regen.premise_id) and Gr:build('c1').params.door_every==nil)
model:redo()
assert(model:get_premise(regen.premise_id))

-- Into an existing premise: regenerating removes the rooms it made there.
local host=model:add_premise({name='Host',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local mine=model:add_object({premise_id=host.id,name='Hand placed',kind='prop',template='x.ent',transform={position={x=1,y=1,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local lab=assert(Gr:generate({grammar='clinic',premise_id=host.id,transform={position={x=0,y=500,z=0,w=1},rotation={roll=0,pitch=0,yaw=90}},build_id='clinic1',seed=4}))
assert(lab.premise_id==host.id)
local function count_rooms(pid) local n=0;for _,r in ipairs(model.data.rooms) do if r.premise_id==pid then n=n+1 end end;return n end
local objects_before=#model.data.objects
local n1=count_rooms(host.id);assert(n1==lab.stats.rooms)
assert(Gr:regenerate('clinic1',{seed=5}))
assert(count_rooms(host.id)==Gr:build('clinic1').stats.rooms and model:get_object(mine.id),'the old rooms are replaced; hand-placed objects stay')
local orphans=0;for _,o in ipairs(model.data.objects) do if o.room_id and not model:get_room(o.room_id) then orphans=orphans+1 end end;assert(orphans==0,'no orphaned pieces')
local gr_orphans=0;for _,r in ipairs(model.data.generated_rooms) do if not model:get_room(r.id) then gr_orphans=gr_orphans+1 end end;assert(gr_orphans==0)
local _=objects_before
-- Yaw 90 turns the layout: the reception (west end) moves to the south.
local rec_room;for _,r in ipairs(app.room_generator:list({premise_id=host.id}).items) do if r.name=='Reception' then rec_room=model:get_room(r.id) end end
assert(rec_room and rec_room.transform.position.y<500-5 and close(rec_room.transform.rotation.yaw,90))

-- Remove: everything of the build goes in one undo step.
undo=#model.undo_stack
assert(Gr:remove('clinic1'))
assert(count_rooms(host.id)==0 and model:get_object(mine.id) and not Gr:build('clinic1') and #model.undo_stack==undo+1)
fails('no grammar build',Gr:remove('clinic1'))

-- A failing plan changes nothing (the asset does not exist).
local before_premises=#model.data.premises
fails('no Project Asset matches',Gr:generate({doc=doc({Root={{room={}},{asset={asset_query='no such asset anywhere'}}}}),transform=ORIGIN}))
assert(#model.data.premises==before_premises and #Gr:builds().items==1)

-- Project library: save (validated, one undo step), override, delete; built-ins stay.
fails('needs an id',Gr:save({id='bad id!',rules={}}))
fails('unknown rule Nope',Gr:save({id='mine',rules={Root={'Nope'}}}))
undo=#model.undo_stack
local saved=assert(Gr:save({id='kiosk',name='Kiosk',include='common',start='Kiosk',size={4,3,3},params={door_every=0,tray=false},
    rules={Kiosk={{room={wall_thickness=0.1}},{walls={sides={'south'},depth=0.5,symbol='Door'}},{place={at={'sx/2-0.8',0.5,0},size={1.6,0.6,1},symbol='Counter'}},'CeilingLight'}}}))
assert(saved.check.ok and saved.check.rooms==1 and #model.undo_stack==undo+1)
local row;for _,r in ipairs(Gr:library().items) do if r.id=='kiosk' then row=r end end;assert(row and row.source=='project')
assert(Gr:preview({grammar='kiosk',transform=ORIGIN}).valid)
fails('built-in grammars cannot be deleted',Gr:delete('common'))
assert(Gr:delete('kiosk') and not Gr:find('kiosk'))
local sch=Gr:schema();assert(sch.terminals and sch.terminals.room and sch.structural['repeat'])

-- Bridge.
assert(assert(app.bridge:handle({id='g1',op='grammar_library',args={}})).count>=7)
assert(assert(app.bridge:handle({id='g2',op='grammar_get',args={id='industrial'}})).include=='common')
assert(assert(app.bridge:handle({id='g3',op='grammar_schema',args={}})).structural)
local bp=assert(app.bridge:handle({id='g4',op='grammar_preview',args={grammar='laboratory',seed=2,include_plan=true,position={0,0,0}}}))
assert(bp.valid and bp.plan and bp.plan.origin.position.x==0)
local bg=assert(app.bridge:handle({id='g5',op='grammar_generate',args={grammar='corridor',build_id='b1',position={0,50,0},yaw=0}}))
assert(bg.build_id=='b1' and model:get_premise(bg.premise_id))
assert(assert(app.bridge:handle({id='g6',op='grammar_regenerate',args={build_id='b1',seed=9}})).build_id=='b1')
assert(assert(app.bridge:handle({id='g7',op='grammar_builds',args={}})).count==2)
assert(assert(app.bridge:handle({id='g8',op='grammar_remove',args={build_id='b1'}})).removed=='b1')
assert(assert(app.bridge:handle({id='g9',op='grammar_save',args={doc={id='tiny',start='R',size={3,3,3},rules={R={{room={}}}}}}})).saved)
assert(assert(app.bridge:handle({id='g10',op='grammar_delete',args={id='tiny'}})).deleted=='tiny')
assert(not app.bridge:handle({id='g11',op='grammar_get',args={id='nope'}}))

-- UI.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env:draw()
env.clicks['PREVIEW##gr']=true;env:draw()
local builds_before=#Gr:builds().items
env.clicks['GENERATE AT PLAYER##gr']=true;env:draw()
assert(#Gr:builds().items==builds_before+1,'generated from the UI')
env:draw()

print('LocationStudio environment grammar: OK')
