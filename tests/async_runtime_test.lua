local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local premise=assert(app.actions:create_premise_from_player('Async test'))
local object=assert(app.builder:place_object({premise_id=premise.id,name='Delayed object',template='base\\test.ent'}))
env.instant=false
local id=assert(app.placement:spawn(object))
assert(object.runtime.status=='pending' and not object.runtime.spawned,'request must not be reported as loaded')
env.alive[id]={id=id};app.placement:update(0.2)
assert(object.runtime.status=='confirmed' and object.runtime.spawned)
env.alive[id]=nil;app.placement:update(0.2)
assert(object.runtime.status=='missing')
app.placement:update(11)
assert(object.runtime.status=='missing','previously loaded entity was misclassified as a timed-out spawn')
env.alive[id]={id=id};app.placement:update(0.2)
assert(object.runtime.status=='confirmed','streamed-out entity must be allowed to recover')
env.remove_rejected=true
app.selection:set('object',object.id)
local deleted,err=app.actions:delete_selected()
assert(not deleted and err,'false Despawn return must be an error')
assert(app.model:get_object(object.id) and app.placement.entity_ids[object.id],'failed deletion must preserve ownership')
env.remove_rejected=false;assert(app.actions:delete_selected());assert(not env.alive[id])

local late=assert(app.placement:spawn_transient('late','base\\test.ent','',object.transform))
assert(app.placement:despawn_transient('late'));assert(app.placement.entities:status().cleanup_pending==1)
env.alive[late]={id=late};app.placement:update(0.2)
assert(not env.alive[late],'cancelled pending request leaked an entity')
assert(app.placement.entities:status().cleanup_pending==0)

local failed_object=assert(app.builder:place_object({premise_id=premise.id,name='Bad template',template='base\\missing.ent'}))
local failed_id=assert(app.placement:spawn(failed_object))
app.placement:update(10.2)
assert(failed_object.runtime.status=='failed' and not failed_object.runtime.spawned)
assert(failed_object.runtime.error:find('10 seconds',1,true))
env.alive[failed_id]={id=failed_id};app.placement:update(0.2)
assert(not env.alive[failed_id],'timed-out request must not spawn a surprise late object')

env.instant=true
local asset=app.model:get_asset('builtin_chair_poor')
local preview=assert(app.placement:preview_asset(asset.id,{follow=true}))
env.aim_x=env.aim_x+8
local moved=assert(app.placement:update_preview(true))
assert(moved.transform.position.x~=preview.transform.position.x,'follow aim reused stale preview transform')
assert(moved.transform.position.x==env.aim_x)
print('Asynchronous lifecycle + preview coordinates: OK')
