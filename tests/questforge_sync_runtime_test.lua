local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.73.0' and app.questforge_sync)
local location=app.model:add_location({id='loc-linked',name='Local Entry',notes='Keep my note',transform={position={x=10,y=20,z=30},rotation={yaw=15}},metadata={custom='keep'}})
local volume=app.model:add_volume({id='vol-linked',name='Entry Trigger',transform={position={x=1,y=2,z=3}},metadata={local_custom='keep'}})
local sector={markers={{id='marker_entry',pos={100,200,300},_locationStudio={id=location.id,name='Entry'}}},
    triggers={{id='trigger_entry',pos={1,2,3},_locationStudio={id=volume.id},_questforge={fact='clinic.door_open',value=1}}}}
local document={format='locationstudio-questforge-handoff',version=2,project={id='qf-project',name='Edited Quest'},
    questforge_world={sectors={sector}},
    semantic_locations={{id=location.id,name='Changed name in QF',node_ref='marker_entry'}},
    quest_manifest_fragment={locations={entry={node_ref='marker_entry'}}},
    fact_triggers={{volume_id=volume.id,fact='clinic.door_open',value=1}},
    device_logic_graphs={{nodes={{id='fact_node',kind='fact',object_id=location.id,config={fact_name='clinic.powered',value=1}}}}}}
local preview=assert(app.questforge_sync:preview(document))
assert(preview.counts.matched==2 and preview.counts.position_conflicts==1 and preview.counts.facts==2)
local bridge_preview=assert(app.bridge:handle({op='questforge_sync_preview',args={document=document}}))
assert(bridge_preview.counts.matched==2)
local result=assert(app.questforge_sync:apply(document))
assert(result.applied==2 and result.positions_applied==false)
assert(location.name=='Local Entry' and location.notes=='Keep my note' and location.transform.position.x==10 and location.metadata.custom=='keep')
assert(location.metadata.questforge_sync.node_ref=='marker_entry' and location.metadata.questforge_sync.manifest_name=='entry')
assert(volume.transform.position.x==1 and volume.metadata.local_custom=='keep')
assert(#volume.metadata.questforge_sync.facts==1 and volume.metadata.questforge_sync.facts[1].name=='clinic.door_open')
local links=assert(app.questforge_sync:links('location',location.id));assert(links.linked and links.position_conflict and #links.facts==1)
local bridge_links=assert(app.bridge:handle({op='questforge_links',args={kind='volume',id=volume.id}}));assert(bridge_links.linked and #bridge_links.facts==1)
local applied=assert(app.questforge_sync:apply(document,{apply_positions=true}));assert(applied.positions_applied and location.transform.position.x==100 and location.notes=='Keep my note')
assert(app.storage:export_questforge(app.model,'exports/test_questforge_roundtrip.json'))
local handoff=assert(json.decode(assert(app.util.read_file('exports/test_questforge_roundtrip.json'))))
assert(handoff.questforge_world.sectors[1].markers[1].id=='marker_entry')
assert(handoff.quest_manifest_fragment.locations.entry.node_ref=='marker_entry')
assert(handoff.fact_triggers[1].fact=='clinic.door_open')
assert(not app.questforge_sync:preview({format='unrelated'}))
print('LocationStudio Quest Forge round-trip: safe preview, ID linking, fact mapping, conflict reporting and opt-in coordinate updates: OK')
