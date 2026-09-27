local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local light,err=app.lighting:create({name='Clinic cyan',source='origin',premise_id=app.model.data.premises[1] and app.model.data.premises[1].id,spawn=true,preset_id='neon_cyan'})
-- The test harness starts with no premise, so use a captured transform to exercise the same live World Builder path.
if not light then light,err=app.lighting:create({name='Clinic cyan',source='player',preset_id='neon_cyan'}) end
assert(light,err)
assert(light.metadata.world_builder.definition_key=='light_static')
assert(light.metadata.world_builder.entry.data.intensity==180)
assert(light.metadata.world_builder.entry.data.color[2]==0.86)
assert(light.runtime and light.runtime.spawned and light.runtime.backend=='world_builder')
local updated=assert(app.lighting:update(light.id,{color={1,0.1,0.2},intensity=250,radius=20,flickerStrength=0.5,flickerPeriod=0.1,flickerOffset=0.25}))
assert(updated.metadata.lighting.intensity==250 and updated.metadata.world_builder.entry.data.radius==20)
assert(updated.runtime.spawned and env.wb_removed==1,'editing a live light must replace its spawned node')
assert(not app.lighting:update(light.id,{intensity=-1}),'invalid intensity must fail')
local preview=assert(app.lighting:preview_time(22,30));assert(preview.preview)
assert(not app.lighting:preview_time(24,0),'invalid game time must fail')
assert(assert(app.lighting:restore_time()).restored)
assert(not app.lighting:restore_time(),'restore without preview must fail')
print('lighting_runtime_test: OK')
