local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local premise=assert(app.actions:create_premise_from_player('Reload premise'))
local asset=app.model:get_asset('builtin_chair_poor')
local object=assert(app.actions:place_asset(asset.id,'player',{premise_id=premise.id,spawn=true}))
local direct_id=tonumber(object.runtime.entity_id)
assert(env.alive[direct_id],'direct entity did not spawn')

-- Use a verified World Builder catalog entry, not a fabricated resource.
local wb_asset=assert(app.world_builder:import_resource({
    name='base\\walls\\wall_a.mesh',fileName='wall_a',
    data={spawnData='base\\walls\\wall_a.mesh'},
    modulePath='mesh/mesh',category='Mesh'
}))
local wb_object=app.model:add_object({name='Reload wall',template=wb_asset.template,size={x=1,y=1,z=1},metadata=wb_asset.metadata,
    transform={position={x=1,y=2,z=3,w=1},rotation={roll=0,pitch=0,yaw=0}}})
assert(app.placement:spawn(wb_object))
local handle=app.runtime_shell.handles[wb_object.id]
assert(handle and not handle.removed)

-- CET may invoke onShutdown while reloading a Lua mod. The live objects must
-- remain in the engine and ownership must be adopted by the next instance.
events.onShutdown()
assert(env.alive[direct_id],'hot reload shutdown despawned direct entity')
assert(not handle.removed,'hot reload shutdown removed World Builder handle')

local reloaded=dofile(mod..'/init.lua');events.onInit();assert(reloaded.ready,reloaded.init_failed)
local direct=reloaded.model:get_object(object.id)
local wall=reloaded.model:get_object(wb_object.id)
assert(direct and direct.runtime.status=='confirmed','direct entity was not reconciled')
assert(reloaded.placement.entity_ids[object.id]==direct_id,'direct entity ID was not retained')
assert(wall and reloaded.runtime_shell.handles[wb_object.id]==handle,'World Builder handle was not retained')
assert(reloaded.runtime_reconciliation and reloaded.runtime_reconciliation.world_builder_preserved>=1)

-- Explicit cleanup remains available after reload and still owns the same IDs.
assert(reloaded.placement:despawn(direct));assert(not env.alive[direct_id])
assert(reloaded.placement:despawn(wall));assert(handle.removed)
print('LocationStudio hot reload runtime ownership: OK')
