local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
events.onOverlayOpen()

env.clicks['ASSETS']=true;env:draw()
assert(app.ui.browser.asset_source=='GAME','Assets must open on the full game database, not the six starter assets')
assert(env.labels['SEARCH GAME'],'Game Resources search controls did not render')
assert(app.ui.browser.game_results and app.ui.browser.game_results.total==1,'World Builder resource search did not return the fixture')
assert(env.labels['PLACE NOW##resource_entity_template_1'],'Place Now did not render for the game resource')

env.clicks['PLACE NOW##resource_entity_template_1']=true;env:draw()
assert(#app.model.data.assets==7,'resource was not imported into Project Assets')
assert(app.selection.kind=='object','placed resource did not become the selected object')
local object=app.selection:resolve();assert(object and object.runtime.backend=='world_builder' and object.runtime.spawned,'resource did not spawn through World Builder')
assert(#env.wb_entries>0,'World Builder spawnNew was not called')

app.model.data.settings.workspace.panel='SCENE';env:draw()
assert(env.labels['APPLY + REFRESH'],'placed-object editor controls are missing')
env.inputs['X##Position##simple_object_1']=44
env.inputs['Z##Rotation##simple_object_3']=35
env.clicks['APPLY + REFRESH']=true;env:draw()
object=app.selection:resolve();assert(object.transform.position.x==44 and object.transform.rotation.yaw==35,'World Builder object transform edit was not saved')
local handle=app.runtime_shell.handles[object.id];assert(handle and handle.position.x==44 and handle.rotation.yaw==35,'World Builder object transform edit did not reach the live handle')
print('LocationStudio Game Resources search / import / place / edit UI: OK')
