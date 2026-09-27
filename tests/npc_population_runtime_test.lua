local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.56.0')
local premise=assert(app.actions:create_premise_from_player('NPC Population Test','interior'))
local record='Character.test_population_guard'
local asset=app.model:add_asset({name='Population Guard',kind='entity_record',template=record,size={x=1,y=1,z=1},metadata={world_builder={
    definition_key='entity_record',module_path='entity/entityRecord',category='Entity Record',variant='Entity Record',resource_path=record,resource_name='Population Guard',
    entry={name='Population Guard',fileName='Population Guard',data={modulePath='entity/entityRecord',spawnData=record,app='default',primaryRange=100,secondaryRange=120,spawnOnStart=true,alwaysSpawned=false}}
}}})
local transform={position={x=12,y=24,z=36,w=1},rotation={roll=0,pitch=0,yaw=45}}
local object=assert(app.actions:create_npc_population({asset_id=asset.id,name='Clinic guard',appearance='street',attitude='hostile',faction='clinic',level=10,
    archetype='guard',idle_behavior='patrol',despawn_distance=80,conditions={{fact_name='clinic_alarm',fact_value=1}},spawn_on_start=false,
    always_spawned=true,primary_range=90,secondary_range=140,transform=transform,premise_id=premise.id,source='player',preview=false}))
assert(object.kind=='npc_population' and object.template==record)
local cfg=object.metadata.npc_population
assert(cfg.record==record and cfg.appearance=='street' and cfg.attitude=='hostile' and cfg.conditions[1].fact_name=='clinic_alarm')
local data=object.metadata.world_builder.entry.data
assert(data.spawnData==record and data.app=='street' and data.spawnOnStart==false and data.alwaysSpawned==true)
assert(data.primaryRange==90 and data.secondaryRange==140)
local updated=assert(app.actions:update_npc_population(object.id,{appearance='worker',spawn_on_start=true,always_spawned=false,primary_range=60,secondary_range=80}))
assert(updated.metadata.npc_population.appearance=='worker' and data.app=='worker' and data.spawnOnStart==true)
assert(data.alwaysSpawned==false and data.primaryRange==60 and data.secondaryRange==80)
local invalid,err=app.actions:update_npc_population(object.id,{conditions={{fact_name='not valid!',fact_value=1}}})
assert(not invalid and err:find('valid quest fact',1,true))
invalid,err=app.actions:update_npc_population(object.id,{despawn_distance='bad'})
assert(not invalid and err:find('despawn_distance',1,true))
print('LocationStudio persistent NPC population authoring: OK')
