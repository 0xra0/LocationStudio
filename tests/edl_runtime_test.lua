local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local model=app.model
local Plans=app.authoring_plans

local f=assert(io.open(arg[2]..'/fixtures/edl_clinic.plan.json','r'));local plan=json.decode(f:read('*a'));f:close()
assert(plan.version==2 and #plan.steps==39)

-- World Builder catalogs: every resource the clinic uses, plus light/audio/area presets.
local catalog={
    mesh_static={'base\\environment\\decoration\\furniture\\bench\\bench_metal_a.mesh','base\\environment\\decoration\\medical\\medical_chair\\medical_chair_a.mesh'},
    entity_template={'base\\gameplay\\devices\\containers\\medical_cabinet\\medical_cabinet_a.ent'},
    entity_record={'Character.ripperdoc_nurse'},
    particle={'base\\fx\\environment\\steam\\steam_vent_small.particle'},
    light_static={'Static Light'},audio={'amb_int_fridge_hum'},area_ambient={'Interior Muffling Area'},area_outline={'Outline Marker'},
}
function app.world_builder:load_catalog(key)
    local out={}
    for i,path in ipairs(catalog[key] or {}) do
        local name=path:match('([^\\]+)$'):gsub('%.[%w]+$','')
        out[i]={index=i,name=name,path=path,definition=self:definition(key),module_path=key,entry={data={spawnData=path}}}
    end
    return out
end
function app.world_builder:prepare_favorite_record(record,name)
    local saved={spawnData=record.spawn_data,app='default',emissionRate=1,respawnOnMove=false,radius=5}
    if record.variant=='Ambient Area' then
        saved={outlinePath='',markers={},height=0,trigger={Notifier={['$type']='audioAmbientAreaNotifier'},Settings={Data={['$type']='audioAmbientAreaSettings',
            EventsOnActive={},EventsOnEnter={},EventsOnExit={},outerDistance=10,verticalOuterDistance=1,Priority=16,Reverb={['$type']='CName',['$value']='revb_interior_room_medium'},Parameters={},isMusic=false}}}}
    elseif record.variant=='Outline Marker' then saved={height=3} end
    return {name=name,data={name=name,modulePath='modules/classes/editor/spawnableElement',spawnable=saved}}
end

-- Version gating.
local v1={format='locationstudio-authoring-plan',version=1,steps={{op='create_light',premise_id='x'}}}
local vr=Plans:validate(v1);assert(not vr.valid and table.concat(vr.errors,' '):find('requires plan version 2',1,true))
local late={format='locationstudio-authoring-plan',version=2,steps={{op='create_premise',as='p',name='x'},{op='edl_begin',doc='d'}}}
assert(not Plans:validate(late).valid,'edl_begin must be first')
assert(Plans:validate(plan).valid,table.concat(Plans:validate(plan).errors or {},'; '))

-- Apply.
local history=#model.undo_stack
local result,err=Plans:execute(plan)
assert(result,err)
assert(result.one_undo and #model.undo_stack==history+1,'one undo step')
assert(result.edl.doc=='ripperdoc_clinic' and not result.edl.replaced)
local build=model.data.edl_builds[1]
assert(build.id=='ripperdoc_clinic' and build.hash and build.streaming.category==1 and build.streaming.cell.x==64)
local E=build.elements
local premise=model:get_premise(build.premise_id);assert(premise and premise.name=='Ripperdoc Clinic' and premise.transform.position.x==100)
local waiting=model:get_room(E.waiting.id);assert(waiting and waiting.size.width==6 and #waiting.openings==3)
local surgery=model:get_room(E.surgery.id);assert(math.abs(surgery.transform.position.x-106.5)<1e-6)
local bench2=model:get_object(E.bench_2.id);assert(math.abs(bench2.transform.position.x-99.8)<1e-6 and bench2.transform.rotation.yaw==180)
assert(bench2.metadata.world_builder.resource_path:find('bench_metal_a',1,true))
local chair=model:get_object(E.surgery_chair.id);assert(chair.metadata.world_builder.entry.data.app=='default' and chair.room_id==surgery.id)
local light=model:get_object(E.surgery_light.id);assert(light.kind=='light' and light.metadata.lighting.intensity==140 and light.transform.position.z==13)
assert(model:get_object(E.counter_block.id).metadata.collision)
local cabinet=model:get_object(E.supply_cabinet.id);assert(cabinet.metadata.interactable.kind=='loot_container' and cabinet.metadata.interactable.lock_state=='locked')
assert(cabinet.metadata.interactable.loot_items[1].item_record=='Items.FirstAidWhiffV0')
local desk=model:get_location(E.nurse_desk.id);assert(desk.metadata.workspot.kind=='stand')
assert(model:get_object(E.steam.id).metadata.vfx)
local trigger=model:get_volume(E.entry_trigger.id);assert(trigger.metadata.questforge.fact_name=='clinic_entered')
local cam=model:get_camera(E.overview.id);assert(math.abs(cam.look_at.x-103)<1e-6)
local nurse=model:get_object(E.nurse.id);assert(nurse.metadata.npc_population.record=='Character.ripperdoc_nurse')
local route=model.data.npc_routes[1];assert(route.npc_id==nurse.id and #route.waypoints==2 and route.waypoints[2].workspot_location_id==desk.id)
local nav=model.data.navigation_graphs[1];assert(nav and #nav.nodes==4 and nav.nodes[1].position.y==197.6)
local graph=model.data.device_logic_graphs[1];assert(graph.nodes[1].object_id==cabinet.id and #graph.links==1)
assert(model:get_object(E.fridge_hum.id).metadata.ambient_audio)
assert(model:get_object(E.waiting_reverb.id).metadata.ambient_zone.role=='area')
assert(#model.data.scenes==1)
assert(app.placement:is_tracked(bench2),'resources are live')

-- Re-apply replaces the previous build: no duplicates, new ids.
local objects_before=#model.data.objects
local again=assert(Plans:execute(plan))
assert(again.edl.replaced and #model.data.edl_builds==1)
assert(#model.data.objects==objects_before,'no duplicated objects: '..#model.data.objects..' vs '..objects_before)
assert(#model.data.npc_routes==1 and #model.data.navigation_graphs==1 and #model.data.device_logic_graphs==1 and #model.data.premises==1)
assert(not model:get_object(bench2.id),'old objects were removed')
assert(model:undo() and model:get_object(bench2.id),'undo restores the previous build')

-- A failing step rolls everything back (resource missing from the catalog).
local bad=json.decode(json.encode(plan))
bad.steps[2].path='base\\missing\\nope.mesh'
local count=#model.data.objects;local builds=#model.data.edl_builds
local ok,ferr=Plans:execute(bad)
assert(not ok and ferr:find('rolled back',1,true) and ferr:find('step 2',1,true))
assert(#model.data.objects==count and #model.data.edl_builds==builds and model:get_object(bench2.id),'nothing changed')

-- Bridge: EDL registry.
local listed=assert(app.bridge:handle({id='x1',op='edl_list',args={}}));assert(listed.count==1 and listed.items[1].id=='ripperdoc_clinic')
local got=assert(app.bridge:handle({id='x2',op='edl_get',args={doc='ripperdoc_clinic'}}));assert(got.elements.nurse)
local removed=assert(app.bridge:handle({id='x3',op='edl_remove',args={doc='ripperdoc_clinic'}}))
assert(removed.removed and #model.data.edl_builds==0 and #model.data.premises==0 and #model.data.npc_routes==0)
assert(model:undo() and #model.data.edl_builds==1,'remove is one undo step')
print('edl_runtime_test: OK')
