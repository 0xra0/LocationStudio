local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local L=assert(app.layers,'layer manager must be constructed')
local model=app.model

-- Defaults: the eight dedicated layers with stable ids.
local names={};for _,l in ipairs(model.data.layers) do names[l.id]=l.name end
assert(names.shell=='Architecture' and names.decoration=='Props' and names.gameplay=='Gameplay' and names.npc=='NPC'
    and names.lighting=='Lighting' and names.audio=='Audio' and names.quest=='Quest' and names.debug=='Debug')
assert(L:get('debug').export==false and L:get('decoration').export==true)

-- Migration of an older project: old defaults renamed, missing layers added, custom names kept.
local Model=require('modules/model')
local old=Model.new({layers={{id='shell',name='Shell',color='#5BC0EB'},{id='decoration',name='My Props',color='#9BC53D'},{id='gameplay',name='Gameplay',color='#FDE74C'}}})
local migrated={};for _,l in ipairs(old.data.layers) do migrated[l.id]=l end
assert(migrated.shell.name=='Architecture' and migrated.decoration.name=='My Props' and migrated.npc and migrated.debug and migrated.debug.export==false)

local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local function obj(name,layer,md,template)
    return model:add_object({premise_id=premise.id,name=name,kind='prop',layer=layer,template=template or 'base\\prop.ent',
        transform={position={x=10,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},metadata=md or {}})
end
local crate=obj('Crate','decoration')
local chair=obj('Chair','decoration')
local lamp=obj('Lamp','decoration',{world_builder={definition_key='light_static',entry={data={}}},lighting={radius=4}},'')
local guard=obj('Guard','gameplay',{npc_population={record='Character.guard'}},'')
local marker=obj('Debug pin','decoration',{world_builder={definition_key='static_marker',entry={data={}}}},'')
local custom=obj('Custom','quest')
assert(app.placement:spawn(crate) and app.placement:spawn(chair))

-- Colour label, rename, validation.
assert(L:update('decoration',{color='#112233'}).color=='#112233')
local r,g,b=L:color_rgb('decoration');assert(math.abs(r-0x11/255)<1e-6 and math.abs(b-0x33/255)<1e-6)
assert(not L:update('decoration',{color='red'}) and not L:update('decoration',{name='Architecture'}))
assert(not L:update('missing',{name='x'}))

-- Hide despawns live objects on the layer; show respawns exactly those.
local hidden=assert(L:set_visible('decoration',false))
assert(hidden.despawned==2 and not app.placement:is_tracked(crate) and not app.placement:is_tracked(chair))
assert(not app.placement:spawn(crate),'hidden layers refuse spawning')
local shown=assert(L:set_visible('decoration',true))
assert(shown.respawned==2 and app.placement:is_tracked(crate) and app.placement:is_tracked(chair))
assert(not app.placement:is_tracked(lamp),'objects that were not live stay unspawned')

-- Isolate shows one layer only and restores previous visibility.
assert(L:set_visible('audio',false))
assert(L:isolate('quest'))
for _,l in ipairs(model.data.layers) do assert(l.visible==(l.id=='quest'),'only the isolated layer is visible: '..l.id) end
assert(not app.placement:is_tracked(crate))
assert(L:isolate('decoration'),'re-isolating keeps the original snapshot')
assert(L:unisolate())
assert(L:get('audio').visible==false and L:get('quest').visible and L:get('decoration').visible,'previous visibility is restored')
assert(app.placement:is_tracked(crate),'isolation respawns what it hid')
assert(not L:unisolate(),'nothing to restore')
assert(L:set_visible('audio',true))

-- Lock marks objects locked; unlock releases only what the layer locked.
chair.locked=true
local locked=assert(L:set_locked('decoration',true));assert(locked.changed==3 and crate.locked and lamp.locked)
assert(not app.lighting:update(lamp.id,{intensity=5}),'layer lock blocks edits through existing lock checks')
assert(not L:assign({crate.id},'gameplay'),'locked objects cannot move')
assert(not L:assign({custom.id},'decoration'),'locked target layer refuses objects')
assert(L:set_locked('decoration',false).changed==3)
assert(not crate.locked and chair.locked,'an individually locked object stays locked')
chair.locked=false

-- Select all, assign, auto-assign, delete.
local sel=assert(L:select_all('decoration',{premise_id=premise.id}));assert(sel.selected==4 and app.selection:object_count()==4)
assert(not L:select_all('npc'))
assert(L:set_visible('debug',false))
local moved=assert(L:assign({crate.id},'debug'));assert(moved.moved==1 and moved.despawned==1 and crate.layer=='debug')
assert(L:set_visible('debug',true).respawned==1,'objects moved into a hidden layer respawn when it is shown')
assert(L:assign({crate.id},'decoration'))
local preview=assert(L:auto_assign({premise_id=premise.id}))
local want={};for _,m in ipairs(preview.moves) do want[m.name]=m.to end
assert(preview.dry_run and want.Lamp=='lighting' and want.Guard=='npc' and want['Debug pin']=='debug' and want.Crate==nil and want.Custom==nil)
assert(lamp.layer=='decoration','preview does not change anything')
local applied=assert(L:auto_assign({premise_id=premise.id,apply=true}));assert(applied.count==3 and lamp.layer=='lighting' and guard.layer=='npc')
assert(model:undo() and model:get_object(lamp.id).layer=='decoration','auto-assign is one undo step')
-- Undo restores a snapshot: re-fetch the live records.
crate,chair,lamp,guard,marker,custom=model:get_object(crate.id),model:get_object(chair.id),model:get_object(lamp.id),model:get_object(guard.id),model:get_object(marker.id),model:get_object(custom.id)
assert(L:auto_assign({premise_id=premise.id,apply=true}))
local created=assert(L:create({name='Set Dressing',color='#ABCDEF'}));assert(created.id=='layer_set_dressing' and created.export)
assert(not L:create({name='set dressing'}),'duplicate names are refused')
assert(L:assign({chair.id},created.id))
local deleted=assert(L:delete(created.id,'decoration'));assert(deleted.moved==1 and chair.layer=='decoration' and not L:get(created.id))
assert(not L:delete('decoration','decoration') and not L:delete('decoration','missing'))

-- Export skips layers with export disabled, reported separately.
local exporter=app.build_export
local scoped=exporter:_objects({premise_id=premise.id})
local ids={};for _,o in ipairs(scoped) do ids[o.id]=true end
assert(not ids[marker.id] and ids[crate.id],'Debug layer objects are left out of the export scope')
assert(#exporter.last_excluded_by_layer==1 and exporter.last_excluded_by_layer[1].layer=='debug')
assert(L:update('debug',{export=true}));assert(#exporter:_objects({premise_id=premise.id})==#scoped+1)

-- Bridge.
assert(#assert(app.bridge:handle({id='l1',op='layer_list',args={}})).layers>=8)
assert(assert(app.bridge:handle({id='l2',op='layer_set_visible',args={id='quest',visible=false}})).visible==false)
assert(assert(app.bridge:handle({id='l3',op='layer_isolate',args={id='npc'}})).isolated=='npc')
assert(assert(app.bridge:handle({id='l4',op='layer_isolate',args={}})).restored)
app.selection:set_object_group({crate.id},crate.id)
assert(assert(app.bridge:handle({id='l5',op='layer_assign',args={id='gameplay',use_selection=true}})).moved==1)
assert(assert(app.bridge:handle({id='l6',op='layer_auto_assign',args={}})).dry_run)
assert(assert(app.bridge:handle({id='l7',op='layer_create',args={name='Temp'}})).layer.id=='layer_temp')
assert(assert(app.bridge:handle({id='l8',op='layer_delete',args={id='layer_temp'}})).deleted=='layer_temp')

-- UI tab and hierarchy colour chips.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selected_premise_id=premise.id
env.clicks['HIDE##layervis_gameplay']=true;env:draw()
assert(L:get('gameplay').visible==false)
env.clicks['SHOW##layervis_gameplay']=true;env:draw()
assert(L:get('gameplay').visible)
env.clicks['LOCK##layerlock_npc']=true;env:draw();assert(L:get('npc').locked and guard.locked)
env.clicks['PREVIEW AUTO-ASSIGN']=true;env:draw();assert(app.ui.spatial.layer_auto)
print('layers_runtime_test: OK')
