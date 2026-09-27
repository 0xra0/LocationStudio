local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.59.0' and app.world_states)
local facts={['quest.stage']=0}
local quests={};function quests:GetFactStr(name)return facts[name] or 0 end
Game={GetQuestsSystem=function()return quests end}
local live={};local calls={spawn=0,despawn=0}
function app.placement:is_tracked(object)return live[object.id]==true end
function app.placement:spawn(object)live[object.id]=true;calls.spawn=calls.spawn+1;return 'runtime:'..object.id end
function app.placement:despawn(object)local did=live[object.id]==true;live[object.id]=nil;calls.despawn=calls.despawn+1;return true,nil,did end
local object=app.model:add_object({id='scene-prop',name='Clinic Debris',template='test.ent',enabled=true,visible=true})
local before=assert(app.world_states:create({name='before_quest',fact_name='quest.stage',operator='==',value=0,priority=10}))
local after=assert(app.world_states:create({name='after_quest',fact_name='quest.stage',operator='>=',value=2,priority=10}))
assert(app.world_states:add_member(before.id,object.id,true))
assert(app.world_states:add_member(after.id,object.id,false))
local plan=assert(app.world_states:preview());assert(#plan.active_variants==1 and plan.active_variants[1].id==before.id and plan.assignments[object.id].visible)
local report=assert(app.world_states:apply());assert(report.spawned==1 and live[object.id] and object.visible)
facts['quest.stage']=2
plan=assert(app.world_states:preview());assert(plan.active_variants[1].id==after.id and plan.assignments[object.id].visible==false)
report=assert(app.world_states:apply());assert(report.despawned==1 and not live[object.id] and object.visible==false)
local conflict=assert(app.world_states:create({name='after_quest_conflict',fact_name='quest.stage',operator='==',value=2,priority=10}))
assert(app.world_states:add_member(conflict.id,object.id,true))
plan=assert(app.world_states:preview());assert(#plan.conflicts==1 and not plan.ready)
assert(not app.world_states:apply())
assert(app.world_states:delete(conflict.id))
assert(app.world_states:set_auto(true));facts['quest.stage']=0;app.world_states:update(os.clock()+2);assert(live[object.id])
local bridge=assert(app.bridge:handle({op='world_state_preview',args={}}));assert(bridge.ready)
assert(app.storage:export_questforge(app.model,'exports/test_world_states.json'))
local handoff=assert(json.decode(assert(app.util.read_file('exports/test_world_states.json'))))
assert(handoff.world_state_variants[1].name=='before_quest')
local ui=app.ui.spatial;ui.world_variant_id=before.id;ui:draw_world_states()
assert(env.labels['CREATE FACT-DRIVEN VARIANT'] and env.labels['APPLY CURRENT FACT STATE'] and env.labels['Auto-switch live objects when quest facts change'])
print('LocationStudio conditional world-state variants: fact predicates, previews, spawn/despawn, priority conflicts, auto switching, bridge and UI: OK')
