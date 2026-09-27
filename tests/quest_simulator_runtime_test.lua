local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.71.0' and app.quest_simulator)
local saved_facts={['clinic.entry']=0}
local quests={facts=saved_facts}
function quests:GetFactStr(name) return self.facts[name] or 0 end
function quests:SetFactStr(name,value) self.facts[name]=value;return true end
Game={GetQuestsSystem=function() return quests end}
local volume=app.model:add_volume({id='debug-trigger',name='Clinic Trigger',metadata={questforge={fact_name='clinic.entry',value=1}}})
local encounter={id='enc-1',name='Clinic Encounter',activation_fact='clinic.entry',activation_value=1,reset_fact='clinic.done',reset_value=0}
app.model.data.combat_encounters={encounter}
local state=assert(app.quest_simulator:catalog());assert(state.game_api_available and #state.facts==2)
local entry=assert(app.quest_simulator:inspect('clinic.entry'));assert(entry.value==0 and #entry.writers==1 and #entry.consumers==1)
local ui=app.ui.spatial;ui.questsim_fact='clinic.entry';ui:draw_quest_debug()
assert(env.labels['PREPARE FACT WRITE'] and env.labels['PREPARE RESET TO 0'] and env.labels['PREPARE TRIGGER FACT'])
local pending=assert(app.quest_simulator:prepare_write('clinic.entry',1,'test'))
assert(pending.persistent_save_warning and quests.facts['clinic.entry']==0)
assert(not app.quest_simulator:confirm_write('wrong-token') and quests.facts['clinic.entry']==0)
assert(app.quest_simulator:confirm_write(pending.token));assert(quests.facts['clinic.entry']==1)
local trigger_pending=assert(app.quest_simulator:prepare_trigger(volume.id));assert(trigger_pending.source:find('manual trigger simulation',1,true))
assert(app.quest_simulator:cancel_write(trigger_pending.token) and quests.facts['clinic.entry']==1)
local reset=assert(app.quest_simulator:prepare_write('clinic.entry',0,'reset'));assert(quests.facts['clinic.entry']==1)
assert(app.quest_simulator:confirm_write(reset.token));assert(quests.facts['clinic.entry']==0)
local bridged=assert(app.bridge:handle({op='quest_simulation_state',args={fact_name='clinic.entry'}}));assert(bridged.value==0)
assert(not app.quest_simulator:prepare_write('bad fact',1))
print('LocationStudio Quest Simulation: live reads, source mapping, two-step persistent writes, cancellation and trigger preparation: OK')
