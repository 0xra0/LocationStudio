local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.62.0')
assert(app.model.data.schema_version==17 and type(app.model.data.scenes)=='table')

local examples=app.authoring_plans:examples()
local validation=app.authoring_plans:validate(examples.starter_workspace)
assert(validation.valid and validation.step_count==7,table.concat(validation.errors or {},'; '))
local invalid=app.authoring_plans:validate({format='locationstudio-authoring-plan',version=1,steps={{op='create_route',name='Bad',location_ids={'$later'}}}})
assert(not invalid.valid and invalid.errors[1]:find('unknown or later alias',1,true))

assert(app:save(true))
local before={premises=#app.model.data.premises,rooms=#app.model.data.rooms,objects=#app.model.data.objects,locations=#app.model.data.locations,scenes=#app.model.data.scenes,history=#app.model.undo_stack}
local built,build_warning=app.authoring_plans:execute(examples.starter_workspace)
assert(built,build_warning)
assert(built.executed and built.one_undo and built.step_count==7)
assert(built.aliases.place and built.aliases.room and built.aliases.chair and built.aliases.scene)
assert(#app.model.data.premises==before.premises+1 and #app.model.data.rooms==before.rooms+1)
assert(#app.model.data.objects>before.objects and #app.model.data.locations==before.locations+1 and #app.model.data.scenes==before.scenes+1)
assert(#app.model.undo_stack==before.history+1,'plan must become exactly one history entry')
local scene=assert(app.model:get_scene(built.aliases.scene));assert(scene.premise_id==built.aliases.place and scene.room_ids[1]==built.aliases.room and scene.object_ids[1]==built.aliases.chair)
assert(app.placement:is_tracked(assert(app.model:get_object(built.aliases.chair))))
local activated=assert(app.scenes:activate(scene.id,true));assert(activated.activated and activated.counts.rooms==1 and activated.counts.objects==1)
local selected=assert(app.scenes:select_objects(scene.id));assert(selected.selected==1 and app.selection:object_count()==1)

assert(app.actions:history('undo'));assert(#app.model.data.premises==before.premises and #app.model.data.scenes==before.scenes)
assert(app.actions:history('redo'));assert(#app.model.data.scenes==before.scenes+1)
app.placement:despawn_all()

local premise=assert(app.actions:create_premise_from_player('Rollback Location','exterior'))
local wb_asset=app.model:add_asset({
    name='Rollback Mesh',kind='mesh',template='base\\rollback.mesh',layer='decoration',size={x=1,y=1,z=1},
    metadata={world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path='base\\rollback.mesh',resource_name='rollback',entry={name='base\\rollback.mesh',fileName='rollback',data={spawnData='base\\rollback.mesh'}}}},
})
assert(app:save(true));local object_count=#app.model.data.objects
local failing={format='locationstudio-authoring-plan',version=1,name='Rollback Probe',origin='player',steps={
    {op='place_asset',as='placed',asset_id=wb_asset.id,premise_id=premise.id,offset={x=1,y=0,z=0},spawn=true},
    {op='move',kind='object',id='missing-object',dx=1},
}}
env.wb_remove_error=true
local failed,fail_err=app.authoring_plans:execute(failing)
assert(not failed and fail_err:find('Rollback is blocked',1,true))
assert(app.authoring_plans:status().recovery_required and #app.model.data.objects==object_count+1)
local save_ok,save_err=app:save(true);assert(not save_ok and save_err:find('rollback',1,true))
local undo_ok,undo_err=app.actions:history('undo');assert(not undo_ok and undo_err:find('rollback',1,true))
local denied,denied_err=app.bridge:handle({id='blocked',op='create_premise',args={name='Blocked'}});assert(not denied and denied_err:find('rollback',1,true))
assert(app.bridge:handle({id='status',op='get_authoring_plan_status',args={}}).recovery_required)
env.wb_remove_error=false
local recovered=assert(app.bridge:handle({id='recover',op='retry_authoring_plan_rollback',args={}}));assert(recovered.recovered)
assert(not app.authoring_plans:status().recovery_required and #app.model.data.objects==object_count)

local schema=assert(app.bridge:handle({id='schema',op='get_authoring_plan_schema',args={}}));assert(schema.version==1 and schema.max_steps==100)
local bridge_validation=assert(app.bridge:handle({id='validate',op='validate_authoring_plan',args={plan=examples.gameplay_route}}));assert(bridge_validation.valid)
assert(#assert(app.bridge:handle({id='scenes',op='list_scenes',args={}}))>=1)

app.model.data.settings.workspace.beginner_mode=true;app.model.data.settings.workspace.panel='HELP'
events.onOverlayOpen();env:draw()
for _,label in ipairs({'HELP + START','BUILD STARTER WORKSPACE','BUILD FURNISHED ROOM','BUILD GAMEPLAY ROUTE','VALIDATE PLAN FILE','RUN PLAN FILE','SAVE DEBUG REPORT'}) do assert(env.labels[label],label..' missing from Help UI') end
local report=app.diagnostics:run();assert(report.modules.scenes and report.modules.authoring_plans and report.project.scenes>=1 and report.runtime.authoring_plans)

local mcp=assert(io.open('mcp_server/server.py','r'));local mcp_text=mcp:read('*a');mcp:close()
for _,needle in ipairs({'def execute_authoring_plan(','def save_authoring_plan_file(','def create_scene(','def retry_authoring_plan_rollback('}) do assert(mcp_text:find(needle,1,true),needle..' missing from MCP server') end
local log=assert(io.open('logs/locationstudio.log','r'));local log_text=log:read('*a');log:close()
for _,needle in ipairs({'[authoring:plan] started','[authoring:plan] committed','[authoring:plan] rollback_blocked','[authoring:plan] recovery_rolled_back','[scene] created','[scene] activated'}) do assert(log_text:find(needle,1,true),needle..' missing from structured log') end

print('LocationStudio unified authoring plans and scenes: OK')
