local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local function call(op,args) return app.bridge:handle({id=op,op=op,args=args or {}}) end

app.model.undo_stack={};app.model.redo_stack={}
local premise=assert(app.actions:create_premise_from_player('History premise'))
local asset=app.model:get_asset('builtin_chair_poor')
local object=assert(app.actions:place_asset(asset.id,'player',{premise_id=premise.id,spawn=true}))
local entity=tonumber(object.runtime.entity_id)
assert(env.alive[entity],'placed object did not spawn')
local depth=#app.model.undo_stack
assert(depth>=2,'expected premise and object history entries')

local history=assert(call('get_history',{limit=5}))
assert(history.undo_count==depth and history.redo_count==0)
local newest=history.undo[1]
assert(newest.steps==1 and newest.changes.objects and newest.changes.objects.added==1,'newest entry must report the added object')
assert(newest.label=='Add object','model adds must be labelled, got '..tostring(newest.label))
assert(newest.at,'entries must be timestamped')
assert(#history.undo<=5)
assert(app.model.data.__history==nil,'history metadata must never be in project data')

-- Undo back to before the premise existed, in one call.
local steps=0
for index=#history.undo,1,-1 do if history.undo[index].changes.premises then steps=history.undo[index].steps;break end end
assert(steps>0,'premise entry not found in history')
local undone=assert(call('history_undo',{steps=steps}))
assert(undone.steps==steps and #undone.labels==steps and undone.labels[1]=='Add object')
assert(app.model:get_object(object.id)==nil and app.model:get_premise(premise.id)==nil,'multi-step undo incomplete')
assert(not env.alive[entity],'undo must despawn the removed object')
assert(app.model.data.__history==nil,'restored state leaked history metadata')

history=assert(call('get_history'))
assert(history.redo_count==steps and history.redo[1].changes.premises and history.redo[1].changes.premises.added==1,'next redo must re-add the premise')
assert(history.redo[steps].label=='Add object','redo labels must follow the undone change')

local ok,err=call('history_redo',{steps=steps+1})
assert(not ok and err:find('Only'),'over-long redo must be refused: '..tostring(err))
local redone=assert(call('history_redo',{steps=steps}))
assert(redone.redo_count==0 and app.model:get_object(object.id),'redo must restore the object')
local restored=app.model:get_object(object.id)
assert(restored.runtime and restored.runtime.spawned and env.alive[tonumber(restored.runtime.entity_id)],'redo must respawn the object that was live')
assert(#app.model.undo_stack==depth,'undo depth must be restored after redo')

-- A new edit clears redo.
assert(call('history_undo',{}))
assert(#app.model.redo_stack==1)
app.model:add_volume({name='Fresh'})
assert(#app.model.redo_stack==0 and app.model.undo_stack[#app.model.undo_stack].__history.label=='Add volume')

ok,err=call('history_undo',{steps=0})
assert(not ok and err:find('at least 1'))

print('history_bridge_runtime_test: OK')
