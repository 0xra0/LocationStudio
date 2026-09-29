local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local P=assert(app.preflight,'preflight must be constructed')
local model=app.model

local function by_id(report) local out={};for _,c in ipairs(report.checks) do out[c.id]=c end;return out end
local function has(c,text) for _,i in ipairs(c.issues) do if i.message:find(text,1,true) then return i end end;return nil end

-- A clean project passes.
local clean=P:run({})
assert(clean.schema=='locationstudio-preflight/1' and clean.ready,'empty project is ready: '..json.encode(clean.summary))
assert(#clean.checks==12)

local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local T={position={x=1,y=2,z=3,w=1},rotation={roll=0,pitch=0,yaw=0}}
local function wb(key,path,extra)
    local md={world_builder={definition_key=key,resource_path=path,entry={data={spawnData=path}}}}
    for k,v in pairs(extra or {}) do md[k]=v end
    return md
end
local good=model:add_object({premise_id=premise.id,name='Good mesh',kind='mesh',template='',transform=T,metadata=wb('mesh_static','base\\a.mesh',{asset_bounds={min={x=-1,y=-1,z=0},max={x=1,y=1,z=2},source='test'}})})
local nobounds=model:add_object({premise_id=premise.id,name='No bounds',kind='mesh',template='',transform=T,metadata=wb('mesh_static','base\\b.mesh')})
local badpath=model:add_object({premise_id=premise.id,name='Bad path',kind='mesh',template='',transform=T,metadata=wb('mesh_static','base\\b.ent')})
local nopath=model:add_object({premise_id=premise.id,name='No path',kind='entity',template='',transform=T,metadata=wb('entity_template','')})
local cet=model:add_object({premise_id=premise.id,name='CET chair',kind='prop',template='base\\chair.ent',transform=T,metadata={}})
local badtpl=model:add_object({premise_id=premise.id,name='Bad template',kind='prop',template='base\\chair.mesh',transform=T,metadata={}})
local failed=model:add_object({premise_id=premise.id,name='Failed',kind='mesh',template='',transform=T,metadata=wb('mesh_static','base\\c.mesh',{asset_bounds={min={x=0,y=0,z=0},max={x=1,y=1,z=1},source='t'}})})
failed.runtime={spawn_error='resource not found'}
local debug=model:add_object({premise_id=premise.id,name='Debug stray',kind='prop',template='nope',layer='debug',transform=T,metadata={}})
-- NodeRefs.
good.metadata.node_ref='$/mod/clinic/#door';nobounds.metadata.node_ref='$/mod/clinic/#door'
badpath.metadata.node_ref='bad ref'
-- Facts.
model:add_volume({premise_id=premise.id,name='Trigger',shape='box',transform=T,size={x=1,y=1,z=1},metadata={questforge={fact_name='bad fact!',value=1}}})
table.insert(model.data.world_state_variants,{id='wsv1',name='After',conditions={{fact_name='ok_fact',operator='==',value=1.5}},members={}})
-- Interactables.
local loot=model:add_object({premise_id=premise.id,name='Crate',kind='interactable',template='',transform=T,metadata=wb('entity_template','base\\crate.ent',{interactable={kind='loot_container',loot_table='LootTables.clinic',loot_items={{item_record='Weapons.bad'}},setup_status='authoring_only',native_setup_required=true,fact_name='crate_opened',fact_value=1}})})
local shard=model:add_object({premise_id=premise.id,name='Shard',kind='interactable',template='',transform=T,metadata=wb('entity_template','base\\shard.ent',{interactable={kind='shard',item_record='',setup_status='native_ready'}})})
-- Ambient areas.
local area=model:add_object({premise_id=premise.id,name='Ambience',kind='area',template='',transform=T,metadata=wb('area_ambient','',{ambient_zone={id='z1',role='area',outline_group='g1',height=3,sound_event=''}})})
for i=1,2 do model:add_object({premise_id=premise.id,name='Outline '..i,kind='area',template='',transform=T,metadata=wb('area_outline','',{ambient_zone={id='z1',role='outline_marker',outline_group='g1'}})}) end
model:add_object({premise_id=premise.id,name='Emitter',kind='audio',template='',transform=T,metadata=wb('audio','amb_hum',{ambient_audio={role='emitter',event=''}})})
-- Workspots and routes.
local ws=model:add_location({name='Desk workspot',transform=T,metadata={workspot={anim='sit'}}})
local lonely=model:add_location({name='Lonely workspot',transform=T,metadata={workspot={anim='lean'}}})
local npc=model:add_object({premise_id=premise.id,name='Nurse',kind='npc',template='',transform=T,metadata=wb('entity_record','Character.nurse',{npc_population={record='Character.nurse'}})})
table.insert(model.data.npc_routes,{id='r1',name='Nurse patrol',npc_id=npc.id,waypoints={{id='w1',transition='workspot',workspot_location_id=ws.id}},alert_waypoints={},combat_waypoints={}})
table.insert(model.data.npc_routes,{id='r2',name='Ghost route',npc_id='gone',waypoints={{id='w2',transition='workspot',workspot_location_id='loc_gone'}}})
-- Device links.
table.insert(model.data.device_logic_graphs,{id='g1',name='Doors',nodes={{id='n1',kind='device',name='Door',object_id=good.id,native={device_hash='1',ps_entry_hash='2',instance_data_ref='3',node_ref='$/mod/clinic/#door'}}},links={{id='l1',from_id='n1',to_id='n_gone'}}})

local r=P:run({})
local c=by_id(r)
assert(not r.ready and r.summary.fail>=8,json.encode(r.summary))
assert(c.resource_paths.status=='fail' and has(c.resource_paths,'does not end in .mesh') and has(c.resource_paths,'no resource path for entity_template') and has(c.resource_paths,'template is not an .ent'))
assert(not has(c.resource_paths,'nope'),'export-disabled layers are out of scope')
assert(c.bounds.status=='warn' and has(c.bounds,'no imported bounds').object_id==nobounds.id)
assert(c.spawns.status=='fail' and has(c.spawns,'resource not found').object_id==failed.id)
assert(c.noderefs.status=='fail' and has(c.noderefs,'is used by both') and has(c.noderefs,'malformed NodeRef'))
assert(c.quest_facts.status=='fail' and has(c.quest_facts,'bad fact!') and has(c.quest_facts,'not an integer'))
assert(c.interactables.status=='fail' and has(c.interactables,'Items.* record') and has(c.interactables,'shard needs') and has(c.interactables,'authoring-only'))
assert(c.ambient_areas.status=='fail' and has(c.ambient_areas,'2 outline marker') and has(c.ambient_areas,'no sound event') and has(c.ambient_areas,'neither a sound event'))
assert(c.workspots.status=='fail' and has(c.workspots,'Lonely workspot') and has(c.workspots,'deleted workspot') and has(c.workspots,'deleted NPC'))
assert(not has(c.workspots,'Desk workspot'),'a workspot on a route passes')
assert(c.device_links.status=='fail' and has(c.device_links,'missing endpoint'))
assert(c.cet_entities.status=='fail' and has(c.cet_entities,'CET entity-spawner').object_id==cet.id)
assert(c.project,'model validation included')

-- Premise scope and deep catalog lookup.
local other=model:add_premise({name='Other',kind='interior',transform=T})
assert(P:run({premise_id=other.id}).scope.objects==0)
function app.world_builder:load_catalog(key) return {{path='base\\a.mesh',name='a',index=1,definition=self:definition(key),entry={data={}}}} end
local deep=by_id(P:run({deep=true}))
assert(has(deep.resource_paths,'not in the World Builder mesh_static catalog') and has(deep.resource_paths,'base\\c.mesh'))

-- Bridge and selection.
local br=assert(app.bridge:handle({id='p1',op='preflight_run',args={}}));assert(br.schema=='locationstudio-preflight/1' and not br.ready)
local idx;for k,issue in ipairs(by_id(P.last).cet_entities.issues) do if issue.object_id==cet.id then idx=k end end
local sel=assert(P:select_issue('cet_entities',idx));assert(sel.selected==cet.id and app.selected_object_id==cet.id)
assert(not P:select_issue('workspots',1),'route issues are not objects')
assert(assert(app.bridge:handle({id='p2',op='preflight_select',args={check_id='spawns',index=1}})).selected==failed.id)

-- Full report written by MCP.
os.remove('exports/preflight-report.json')
assert(not P:load())
local full={schema='locationstudio-preflight/1',source='mcp',ready=false,summary={pass=5,warn=1,fail=2,skipped=0},checks={{id='dependencies',label='Asset dependencies',status='fail',issues={{severity='error',message='missing x',object_id=good.id}}}}}
local f=assert(io.open('exports/preflight-report.json','w'));f:write(json.encode(full));f:close()
assert(assert(P:load()).summary.fail==2)
assert(assert(P:select_issue('dependencies',1)).selected==good.id)

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['RUN CHECKS##pf']=true;env:draw()
assert(P.last and P.loaded==nil)
env.clicks['Spawns (1)##pfcheck_spawns']=true;env:draw()
assert(app.ui.spatial.pf_open=='spawns')
app.selection:set('object',nil)
env.clicks['SELECT##pfsel_spawns_1']=true;env:draw()
assert(app.selected_object_id==failed.id)
env.clicks['LOAD FULL REPORT##pf']=true;env:draw();assert(P.loaded)
os.remove('exports/preflight-report.json')
print('preflight_runtime_test: OK')
