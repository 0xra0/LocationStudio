local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local RT=assert(app.room_types,'room types must be constructed')
local Types=getmetatable(RT).__index
local G=require('modules/env_grammar')
local Gr=app.env_grammar
local S=app.surfaces
local model=app.model
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-3) end
local function fails(needle,res,err) assert(res==nil,'expected a failure: '..tostring(needle));assert(tostring(err):find(needle,1,true),'expected "'..needle..'" in: '..tostring(err)) end
local function has(list,v) for _,x in ipairs(list or {}) do if x==v then return true end end;return false end
local T=function(x,y,z,yaw) return {position={x=x,y=y,z=z,w=1},rotation={roll=0,pitch=0,yaw=yaw or 0}} end
local function count(list,pred) local n=0;for _,x in ipairs(list) do if pred(x) then n=n+1 end end;return n end
local function locations(kind) return count(model.data.locations,function(l) return l.type==kind end) end

-- Built-in catalog: the environments the roadmap names, all resolvable.
local list=RT:list().items
local by={};for _,t in ipairs(list) do by[t.id]=t end
for _,id in ipairs({'room','clinic','office','storage','security','maintenance','corridor','server_room','reception','armory','workshop','lab','bedroom','bunk_room','bathroom','kitchen'}) do
    assert(by[id] and by[id].valid and by[id].source=='builtin','built-in type '..id)
end
local armory=assert(RT:resolve('armory'))
assert(table.concat(armory.chain,'>')=='room>security>armory','inheritance chain')
assert(has(armory.traits,'security') and has(armory.traits,'military'),'traits add up along the chain')
assert(armory.spec.trim.skirting==false,'a child overrides a parent spec key')
assert(armory.interior[1]=='ArmoryInterior' and #armory.populate==0,'inherit_populate false drops the guard post')
local workshop=assert(RT:resolve('workshop'))
assert(workshop.params.workbench_surface=='industrial_surface' and workshop.interior[1]=='WorkshopInterior' and #workshop.populate==1,'params and placements are inherited; interior is replaced')
local server=assert(RT:resolve('server_room'))
assert(server.spec.floor.type=='raised' and close(server.spec.floor.raise,0.3) and has(server.traits,'tech'))

-- Pure validation, resolution and merging.
fails('lowercase',Types.check({id='Clinic'}))
fails('unknown field',Types.check({id='x',colour='red'}))
fails('spec cannot set width',Types.check({id='x',spec={width=4}}))
fails('spec: floor type',Types.check({id='x',spec={floor={type='carpet'}}}))
fails('cannot extend itself',Types.check({id='x',extends='x'}))
fails('interior rules must be rule names',Types.check({id='x',interior={'9bad'}}))
fails('kind must be',Types.check({id='x',populate={{kind='teapot'}}}))
fails('size: unknown key',Types.check({id='x',size={min_area=4}}))
assert(Types.check({id='ok_type',extends='clinic',traits={'cyberware'},params={counter_surface='counter'},interior=false,populate={{kind='marker',tags='floor'}}}))
local docs={a={id='a',extends='b'},b={id='b',extends='a'},c={id='c',extends='missing'}}
local look=function(id) return docs[id] end
fails('cycle',Types.resolve_with('a',look))
fails('extends unknown type missing',Types.resolve_with('c',look))
fails('unknown room type: zzz',RT:resolve('zzz'))
local applied=Types.apply_spec({height=4,surfaces={traits={'mine'}},lighting={spacing=5}},server)
assert(applied.type=='server_room' and applied.height==4 and applied.floor.type=='raised','type defaults go under the spec')
assert(applied.lighting.spacing==5 and applied.lighting.anchors=='grid','objects merge key by key; the spec wins')
assert(has(applied.surfaces.traits,'tech') and has(applied.surfaces.traits,'mine'),'traits add up')
assert(#Types.size_warnings(server,2,5,3)==1 and #Types.size_warnings(server,4,4,3)==0,'advisory sizes')
local merged=Types.merge({a={1,2},b={c=1,d=2}},{a={3},b={c=5}})
assert(#merged.a==1 and merged.b.c==5 and merged.b.d==2,'lists replace, objects merge')

-- Expression helpers for interior rules.
assert(G.eval("has(xs, 'north')",{xs={'north','east'}})==true and G.eval('count(xs)',{xs={'a','b'}})==2)
assert(G.eval('pick(xs, 1)',{xs={'a','b'}})=='b' and G.eval('pick(xs, 5)',{xs={'a'}})=='')

-- Parametric rooms carry a type and inherit its shell defaults.
local premise=assert(model:add_premise({name='Types Lab',kind='interior',transform=T(0,0,0)}))
app.selected_premise_id=premise.id
local rg=app.room_generator
local prev=assert(rg:preview({type='server_room',width=2,length=5,height=3}))
assert(prev.type.id=='server_room' and prev.spec.floor.type=='raised' and #prev.warnings==1,'preview applies the type and warns about size')
local srv=assert(rg:create({spec={name='Servers',type='server_room',width=6,length=5,doors={{wall='south',width=1}}},premise_id=premise.id,transform=T(0,0,0)}))
local room=model:get_room(srv.room.id)
assert(room.room_type=='server_room' and has(room.tags,'restricted'),'the room records its type and the type tags')
assert(srv.generated.spec.floor.type=='raised' and srv.generated.spec.type=='server_room')
assert(srv.generated.base_spec.floor==nil,'the room keeps its own spec apart from the type defaults')
assert(S:query({room_id=room.id,traits='tech'}).count>0,'surfaces carry the type traits')
local own=assert(rg:create({spec={name='Flat servers',type='server_room',width=5,length=5,floor={type='slab'}},premise_id=premise.id,transform=T(20,0,0)}))
assert(own.generated.spec.floor.type=='slab','an explicit spec key beats the type default')
-- Re-typing regenerates the shell with the new type's defaults.
local up=assert(rg:update(room.id,{type='clinic'}))
assert(model:get_room(room.id).room_type=='clinic' and up.generated.spec.floor.type=='slab' and up.generated.spec.trim.crown==true,'server defaults go, clinic defaults come')
assert(S:query({room_id=room.id,traits='medical'}).count>0 and S:query({room_id=room.id,traits='tech'}).count==0)
assert(rg:update(room.id,{type=false}))
assert(model:get_room(room.id).room_type==nil,'type false clears it')
fails('unknown room type',rg:create({spec={type='spaceship',width=4,length=4},premise_id=premise.id,transform=T(40,0,0)}))
fails('type must be a room type id',rg:create({spec={type='Bad Type',width=4,length=4},premise_id=premise.id,transform=T(40,0,0)}))
local v=app.authoring_plans:validate({format='locationstudio-authoring-plan',version=2,origin=T(0,0,0),steps={{op='create_parametric_room',as='r',premise_id=premise.id,offset={x=0,y=0,z=0},spec={type='spaceship',width=4,length=4}}}})
assert(not v.valid and table.concat(v.errors,';'):find('unknown room type',1,true),'plans validate the room type')
-- The model keeps the type through normalization.
assert(model:add_room({premise_id=premise.id,name='Kit room',room_type='storage'}).room_type=='storage')

-- Grammar rooms: defaults, params, interiors after the doors, placements in the room.
local doc={id='typed_test',start='Root',size={6,5,3},params={counter_surface='counter'},
    rules={Root={{room={type='clinic'}},{walls={sides={'south'},depth=0.5,['do']={{door={width=1}}}}},
        {place={at={0.3,'sy-0.9',0},size={1.2,0.6,1},symbol='Counter'}}}}}
local p=assert(Gr:preview({doc=doc,transform=T(0,100,0),seed=2}))
assert(p.valid,table.concat(p.errors or {},'; '))
assert(p.rooms[1].type=='clinic' and p.stats.room_types.clinic==1)
assert(p.stats.surfaces.by_tag.medical_surface>=2,'the type param overrides the grammar default for the grammar counter and the interior counter')
assert(p.stats.interior_items>=2,'the clinic interior furnishes the room: '..tostring(p.stats.interior_items))
local furn={};for _,it in ipairs(p.items) do if it.furnishing then furn[#furn+1]=it.name end end
assert(#p.populate==1 and p.populate[1].room_type=='clinic' and p.populate[1].estimate>=1,'the type places supply spots on its medical surfaces')
-- A rule's own set, and a generation param, beat the type's params.
local doc2={id='typed_set',start='Root',size={6,5,3},rules={Root={{set={counter_surface="'kitchen_surface'"}},{room={type='clinic',furnish=false}},{place={at={1,1,0},size={1.2,0.6,1},symbol='Counter'}}}}}
p=assert(Gr:preview({doc=doc2,transform=T(0,100,0)}))
assert(p.stats.surfaces.by_tag.kitchen_surface==1 and not p.stats.surfaces.by_tag.medical_surface,'set wins over the type param')
assert(p.stats.interior_items==0 and #p.populate==0,'furnish false keeps defaults but skips the interior and placements')
p=assert(Gr:preview({doc=doc,transform=T(0,100,0),params={counter_surface='lab_surface'}}))
assert((p.stats.surfaces.by_tag.lab_surface or 0)>=2,'generation params win over the type param')
-- Built grammar: rooms carry the type, furnishing and placements are real and scoped.
local built=assert(Gr:generate({doc=doc,transform=T(0,100,0),seed=2,build_id='typed1',premise_id=premise.id}))
local grammar_room
for _,r in ipairs(model.data.rooms) do if r.room_type=='clinic' and r.premise_id==premise.id and r.name=='Root' then grammar_room=r end end
assert(grammar_room,'the grammar room carries its type')
local grec=rg:get(grammar_room.id);assert(grec.base_spec.type=='clinic' and grec.base_spec.trim==nil,'the built room keeps its own spec; the type is applied when it is built')
assert(grec.spec.trim.crown==true,'clinic crown moulding')
assert(locations('supply_spot')>=1,'supply spots on the medical surfaces')
for _,l in ipairs(model.data.locations) do if l.type=='supply_spot' then assert(close(l.transform.position.z,0.9,0.02),'spots sit on the counters: '..l.transform.position.z) end end
local beds=count(model.data.objects,function(o) return o.room_id==grammar_room.id and o.name=='Bed' and o.metadata and o.metadata.procedural~=nil end)
assert(beds==1,'the clinic interior adds an exam bed: '..beds)
assert(Gr:remove('typed1'))
assert(locations('supply_spot')==0,'removing the build removes the type placements')

-- Doorway clearance, interior limits and missing rules.
assert(RT:save({id='blocker',name='Blocker',interior='Slab'}))
local doc3={id='clear_test',start='Root',size={6,6,3},rules={
    Root={{room={type='blocker'}},{walls={sides={'south'},depth=0.5,['do']={{door={width=1}}}}}},
    Slab={{place={at={0,0,0},size={'sx',0.8,1},['do']={{geometry={generator='box',params={size={'=sx',0.8,0.8}}}}}}},{place={at={'sx/2-0.4','sy/2-0.4',0},size={0.8,0.8,1},['do']={{geometry={generator='box',params={size={0.8,0.8,0.8}}}}}}}}}}
p=assert(Gr:preview({doc=doc3,transform=T(0,0,0)}))
assert(p.stats.interior_items==1 and p.stats.doorway_cleared==1,'a slab across the doorway is left out: '..p.stats.interior_items..'/'..p.stats.doorway_cleared)
local warned=false;for _,w in ipairs(p.warnings) do if w:find('keep doorways clear',1,true) then warned=true end end;assert(warned)
assert(RT:save({id='door_maker',interior='AddDoor'}))
fails('cannot add doors',Gr:preview({doc={id='d',start='Root',size={5,5,3},rules={Root={{room={type='door_maker'}}},AddDoor={{door={wall='north'}}}}},transform=T(0,0,0)}))
assert(RT:save({id='no_rules',interior='NoSuchRule'}))
fails('interior rule NoSuchRule not found',Gr:preview({doc={id='d',start='Root',size={5,5,3},rules={Root={{room={type='no_rules'}}}}},transform=T(0,0,0)}))
fails('unknown room type: spaceship',Gr:preview({doc={id='d',start='Root',size={5,5,3},rules={Root={{room={type='spaceship'}}}}},transform=T(0,0,0)}))
-- A grammar's own rule of the same name overrides the room_interiors one.
p=assert(Gr:preview({doc={id='o',start='Root',size={6,6,3},rules={Root={{room={type='bathroom'}}},BathroomInterior={{marker={type='custom_bath'}}}}},transform=T(0,0,0)}))
assert(p.stats.interior_items==1 and p.items[1].kind=='marker')

-- Every interior rule expands in rooms of several sizes and door layouts, without warnings about doorways.
for _,t in ipairs(list) do
    for _,size in ipairs({{3,3},{5,4},{8,6},{4,10}}) do
        for _,wall in ipairs({'south','east'}) do
            local d={id='sweep',start='Root',size={size[1],size[2],3},rules={Root={{room={type=t.id}},{walls={sides={wall},depth=0.5,['do']={{door={width=1}}}}}}}}
            local q,err=Gr:preview({doc=d,transform=T(0,0,0),seed=5})
            assert(q,t.id..' '..size[1]..'x'..size[2]..': '..tostring(err))
            assert(q.valid,t.id..': '..table.concat(q.errors or {},'; '))
        end
    end
end

-- The facility grammar is furnished by its room types only.
local fac=assert(Gr:preview({grammar='facility',transform=T(0,300,0),seed=2}))
assert(fac.valid and fac.stats.interior_items>20 and fac.stats.room_types.corridor==1)
local offices=fac.stats.room_types.office or 0
assert(offices>0 and (fac.stats.surfaces.by_tag.desk or 0)>=offices,'offices get desks')
local unfurnished=assert(Gr:preview({grammar='facility',transform=T(0,300,0),seed=2,params={furnish=false}}))
assert(unfurnished.stats.interior_items==0)
-- Built-in grammars label their rooms and keep their own furnishing.
local clinic=assert(Gr:preview({grammar='clinic',transform=T(0,300,0),seed=4}))
assert(clinic.stats.room_types.clinic>0 and clinic.stats.room_types.reception==1 and clinic.stats.interior_items==0)
assert((clinic.stats.surfaces.by_tag.medical_surface or 0)>0)
local labp=assert(Gr:preview({grammar='laboratory',transform=T(0,300,0),seed=4}))
assert(labp.stats.room_types.lab>0 and (labp.stats.surfaces.by_tag.lab_surface or 0)>0)

-- Furnishing an existing room (a room-kit room) from its type.
local kit=assert(app.builder:create_room({premise_id=premise.id,name='Stock room',width=6,depth=5,height=3,generate_shell=false,transform=T(60,0,0)}))
kit.openings={{id='o1',kind='door',wall='south',offset=0,width=1.2,height=2.2,sill=0}}
local a=assert(RT:assign(kit.id,'storage'))
assert(a.regenerated==false and model:get_room(kit.id).room_type=='storage')
local dry=assert(RT:furnish(kit.id,{dry_run=true,seed=3}))
assert(dry.dry_run and dry.valid and dry.items>0 and dry.kinds.geometry>0,'the preview lists the furnishing')
local undo_before=#model.undo_stack
local f=assert(RT:furnish(kit.id,{seed=3}))
assert(f.one_undo and #model.undo_stack==undo_before+1,'furnishing is one undo step')
local function in_room(id) return count(model.data.objects,function(o) return o.room_id==id and o.metadata and o.metadata.procedural~=nil and not o.metadata.room_generator end) end
local n1=in_room(kit.id)
assert(n1==dry.items,'every item lands in the room: '..n1..' vs '..dry.items)
for _,o in ipairs(model.data.objects) do if o.room_id==kit.id then local pos=o.transform.position;assert(pos.x>60-3.01 and pos.x<60+3.01 and pos.y>-2.51 and pos.y<2.51,'inside the room') end end
assert(locations('loot_spot')>=1,'loot spots on the shelves')
local again=assert(RT:furnish(kit.id,{seed=3}))
assert(again.replaced and in_room(kit.id)==n1,'furnishing again replaces the previous furnishing')
local rows=RT:rooms({type='storage'}).items;assert(#rows==2);for _,r in ipairs(rows) do assert(r.furnished==(r.id==kit.id) and r.generated==false) end
assert(model:undo());assert(in_room(kit.id)==n1,'undo restores the previous furnishing')
assert(RT:unfurnish(kit.id));assert(in_room(kit.id)==0 and locations('loot_spot')==0)
fails('no furnishing',RT:unfurnish(kit.id))
-- A generated room furnishes around its own doors.
local office=assert(rg:create({spec={name='Office A',type='office',width=6,length=5,doors={{wall='east',width=1}}},premise_id=premise.id,transform=T(80,0,0)}))
local fo=assert(RT:furnish(office.room.id,{}))
assert(fo.kinds.geometry>=2 and locations('workstation')>=1,'desks and workstation markers')
fails('the room has no type',RT:furnish(model:add_room({premise_id=premise.id,name='Plain'}).id,{}))
-- Clearing the type removes the furnishing too; setting a type on a generated room regenerates it.
local cleared=assert(RT:assign(office.room.id,false))
assert(cleared.regenerated,'regenerated');assert(cleared.unfurnished,'unfurnished: '..tostring(cleared.unfurnish_error));assert(in_room(office.room.id)==0 and locations('workstation')==0)
local set=assert(RT:assign(office.room.id,'security',{furnish=true}))
assert(set.regenerated and set.furnish and set.furnish.items>0 and model:get_room(office.room.id).room_type=='security')
assert(count(model.data.volumes,function(vol) return vol.room_id==office.room.id end)==1,'the security zone volume')

-- A new typed room in one step (a grammar build).
local c=assert(RT:create_room({type='clinic',width=5,length=4,spec={doors={{wall='south',width=1}}},premise_id=premise.id,transform=T(100,0,0),build_id='clinic_a'}))
assert(c.build_id=='clinic_a' and c.rooms[1].type=='clinic' and #c.items>=2)
local croom;for _,r in ipairs(model.data.rooms) do if r.room_type=='clinic' and r.name=='Clinic' then croom=r end end
assert(croom and close(croom.size.width,5) and close(croom.size.depth,4),'the room has the requested interior size')
assert(close(croom.transform.position.x,100) and close(croom.transform.position.y,0),'centred where asked')
assert(Gr:regenerate('clinic_a',{seed=9}))
assert(Gr:remove('clinic_a'))
fails('unknown room type',RT:create_room({type='spaceship'}))

-- Project types: save, override, extend, reapply, delete.
local saved=assert(RT:save({id='ripperdoc',name='Ripperdoc',extends='clinic',traits={'cyberware'},params={light_intensity=30},
    populate={{kind='marker',tags='bed',pattern='center',per_surface=1,height=0,type='patient_spot'}}}))
assert(saved.effective.chain[2]=='clinic' and has(saved.effective.traits,'medical') and has(saved.effective.traits,'cyberware'))
fails('cycle',RT:save({id='clinic',extends='ripperdoc'}))
local rd=assert(RT:create_room({type='ripperdoc',width=5,length=4,spec={doors={{wall='south'}}},premise_id=premise.id,transform=T(120,0,0),build_id='rd'}))
assert(locations('patient_spot')==1 and locations('supply_spot')>=1,'a custom type adds its placements to the inherited ones')
assert(S:query({premise_id=premise.id,traits='cyberware'}).count>0)
assert(RT:save({id='ripperdoc',name='Ripperdoc',extends='clinic',traits={'cyberware'},inherit_populate=false,
    populate={{kind='marker',tags='bed',pattern='center',per_surface=1,height=0,type='patient_spot'}}}))
local re=assert(RT:reapply('ripperdoc'))
assert(re.rooms==1 and re.failed==0 and re.results[1].action=='regenerate_build')
assert(locations('supply_spot')==0 and locations('patient_spot')==1,'reapplying rebuilds the rooms with the changed type')
local ov=assert(RT:save({id='storage',name='Storage (project)',extends='room',interior=false}))
assert(ov.overrides_builtin and RT:get('storage').source=='project')
fails('built-in room types cannot be deleted',RT:delete('office'))
fails('extends ripperdoc',(function() assert(RT:save({id='ripper_vip',extends='ripperdoc'}));return RT:delete('ripperdoc') end)())
assert(RT:delete('ripper_vip'))
local del=assert(RT:delete('storage'));assert(del.falls_back_to_builtin and RT:get('storage').source=='builtin')
assert(Gr:remove('rd'))

-- Bridge.
local h=function(op,args) return app.bridge:handle({id=op,op=op,args=args or {}}) end
assert(#assert(h('room_type_list')).items>=16)
assert(assert(h('room_type_get',{type='server_room'})).effective.spec.floor.type=='raised')
assert(assert(h('room_type_rooms',{type='security'})).count>=1)
assert(assert(h('room_type_assign',{room_id=kit.id,type='kitchen'})).type=='kitchen')
assert(assert(h('room_type_preview',{room_id=kit.id})).dry_run)
assert(assert(h('room_type_furnish',{room_id=kit.id,seed=1})).one_undo)
assert(assert(h('room_type_unfurnish',{room_id=kit.id})).removed)
assert(assert(h('room_type_save',{doc={id='bridge_type',extends='office'}})).saved)
assert(assert(h('room_type_reapply',{type='bridge_type'})).rooms==0)
assert(assert(h('room_type_delete',{type='bridge_type'})).deleted=='bridge_type')
local br=assert(h('room_type_create_room',{type='maintenance',width=4,length=4,premise_id=premise.id,transform=T(140,0,0),build_id='br'}))
assert(br.rooms[1].type=='maintenance');assert(Gr:remove('br'))
assert(assert(h('room_type_assign',{room_id=kit.id,clear=true})).type==nil and model:get_room(kit.id).room_type==nil)

-- UI: Spatial -> Room types.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selected_premise_id=premise.id
app.selection:set('room',kit.id)
env:draw()
assert(env.labels['SET TYPE##rt'] and env.labels['FURNISH##rt'] and env.labels['CREATE ROOM##rt'],'room types panel is reachable')
env.clicks['storage##rtt_storage']=true;env:draw()
app.selection:set('room',kit.id);env.clicks['SET TYPE##rt']=true;env:draw()
assert(model:get_room(kit.id).room_type=='storage','the panel sets the type')
app.selection:set('room',kit.id);env.clicks['PREVIEW##rt']=true;env:draw()
app.selection:set('room',kit.id);env.clicks['FURNISH##rt']=true;env:draw()
assert(in_room(kit.id)>0,'the panel furnishes the room')
app.selection:set('room',kit.id);env.clicks['UNFURNISH##rt']=true;env:draw()
assert(in_room(kit.id)==0)
app.selection:set('room',kit.id);env.clicks['CLEAR TYPE##rt']=true;env:draw()
assert(model:get_room(kit.id).room_type==nil)
local rooms_before=#model.data.rooms
env.clicks['CREATE ROOM##rt']=true;env:draw()
assert(#model.data.rooms==rooms_before+1,'the panel creates a typed room: '..tostring(app.ui and app.ui.toast))
print('LocationStudio room types: OK')
