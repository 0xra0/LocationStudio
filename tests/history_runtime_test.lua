local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local premise=assert(app.actions:create_premise_from_player('History'))
local object=assert(app.actions:place_asset('builtin_chair_poor','player',{spawn=true}))
app.model.undo_stack={};app.model.redo_stack={}
local id=app.placement.entity_ids[object.id]
local none=app.actions:history('undo');assert(not none and env.alive[id],'empty Undo must not despawn the scene')
app.selection:set('object',object.id)
assert(app.actions:update_selected({name='Changed'}))
assert(app.actions:history('undo'))
local restored=app.model:get_object(object.id)
assert(restored.name~= 'Changed' and restored.runtime.status=='confirmed','Undo must reconcile runtime ownership')
assert(app.actions:history('redo'))
assert(app.model:get_object(object.id).name=='Changed')
print('History availability and live-state reconciliation: OK')
