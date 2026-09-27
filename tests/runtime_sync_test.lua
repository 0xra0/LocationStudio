local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.62.0')
local object=app.model:add_object({id='sync_target',name='Sync target',template='base\\sync.ent',transform={position={x=1,y=2,z=3},rotation={yaw=0}}})
local first=assert(app.placement:spawn(object));local old_entity=app.placement.entity_ids[object.id]
assert(first and old_entity and env.alive[old_entity])
local clean=app:check_runtime_sync(true);assert(not clean.has_changes)
object.transform.position.x=8
local drift=app:check_runtime_sync(true)
assert(drift.has_changes and drift.counts.update==1 and drift.items[1].id==object.id)
local synced=assert(app:sync_runtime())
assert(synced.updated==1 and not synced.has_changes and app.placement.entity_ids[object.id]~=old_entity)
local removed_id=app.placement.entity_ids[object.id]
app.model.data.objects={}
local stale=app:check_runtime_sync(true)
assert(stale.has_changes and stale.counts.remove==1)
local cleaned=assert(app:sync_runtime())
assert(cleaned.removed==1 and not cleaned.has_changes and app.placement.entity_ids[object.id]==nil and env.alive[removed_id]==nil)
local refreshed=assert(app:check_runtime_sync(true));assert(not refreshed.has_changes)
local retry=app.model:add_object({id='sync_retry',name='Retry spawn',template='base\\retry.ent'})
app.placement.expected_live[retry.id]=true
env.spawn_throws=true
local failed_id=app.placement:spawn(retry);assert(not failed_id)
env.spawn_throws=false
local missing=app:check_runtime_sync(true);assert(missing.has_changes and missing.counts.missing==1)
local retried=assert(app:sync_runtime());assert(retried.spawned==1 and not retried.has_changes)
print('LocationStudio Native Runtime Sync: OK')
