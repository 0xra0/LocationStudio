local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local envs=assert(app.environment,'environment module must be constructed')
assert(app.model.data.schema_version==24 and type(app.model.data.environments)=='table')

-- Fake WeatherSystem with the CET method shapes used by weather mods.
local weather={state='24h_weather_sunny',calls={},resets=0,rain=0}
function Game.GetWeatherSystem()
    return {
        SetWeather=function(_,name,blend,priority) weather.calls[#weather.calls+1]={name=name,blend=blend,priority=priority};weather.state=name;weather.rain=name:find('rain') and 0.8 or 0 end,
        ResetWeather=function(_,force,blend) weather.resets=weather.resets+1;weather.state='24h_weather_cloudy';weather.rain=0 end,
        GetWeatherState=function() return {name=weather.state} end,
        GetRainIntensity=function() return weather.rain end,
    }
end
Game.NameToString=function(v) return tostring(v) end

-- Fake World Builder Fog Volume catalog.
local fog_saved
local search=app.world_builder.search
function app.world_builder:search(key,query,limit,force)
    if key=='fog' then return {items={{name='Fog Volume Default',path='fog_default'}}} end
    return search(self,key,query,limit,force)
end
local prepare=app.world_builder.prepare_favorite_record
function app.world_builder:prepare_favorite_record(record,name)
    if record.variant=='Fog Volume' then fog_saved={spawnData=record.spawn_data,scale={x=5,y=5,z=5},densityFactor=1,densityFalloff=1,absorption=1,blendFalloff=1,color={1,1,1}};return {name=name,data={spawnable=fog_saved}} end
    return prepare(self,record,name)
end

local caps=envs:capabilities()
assert(caps.time and caps.weather_set and caps.weather_reset and caps.weather_read and caps.rain_read and not caps.exposure_set)
assert(#envs:weather_states()>=10)

-- Create / validate / capture.
local rainy=assert(envs:create({name='Rainy night',hour=22,minute=30,weather_state='24h_weather_rain',fog_enabled=true,fog_density_factor=2.5,fog_size={x=40,y=30,z=12},exposure_note='slightly darker than default'}))
assert(rainy.time.hour==22 and rainy.weather.state=='24h_weather_rain' and rainy.fog.enabled and rainy.fog.density_factor==2.5 and rainy.fog.size.x==40)
assert(not envs:create({name='Rainy night'}),'duplicate names must fail')
assert(not envs:create({name='Bad',weather_state='rain; drop'}),'weather state must be a CName')
local clamped=assert(envs:create({name='Clamp',hour=99,minute=-5}));assert(clamped.time.hour==23 and clamped.time.minute==0)
weather.state='24h_weather_fog'
local captured=assert(envs:create({name='Captured',capture_current=true}))
assert(captured.weather.state=='24h_weather_fog' and captured.time.hour==8,'capture must read the live clock and weather')
local listed=envs:list();assert(listed.count==3 and listed.items[1].rain=='heavy')

-- Preview applies time, weather and a transient fog volume, then restores.
weather.state='24h_weather_sunny'
local before=envs:current();assert(before.hour==8)
local count=#app.model.data.objects
local status=assert(envs:preview(rainy.id,{force=false}))
assert(status.active and status.applied.time.hour==22 and status.applied.weather.state=='24h_weather_rain' and status.applied.fog)
assert(status.warning and status.warning:find('exposure is a note only',1,true),'exposure must be reported as not applied')
assert(envs:current().hour==22 and envs:current().weather=='24h_weather_rain' and envs:current().rain_intensity==0.8)
local fog_handle=app.runtime_shell.handles.__env_fog_preview;assert(fog_handle,'fog preview must be a live World Builder node')
assert(fog_saved.densityFactor==2.5 and fog_saved.scale.x==40 and fog_saved.scale.z==12)
assert(#app.model.data.objects==count,'fog preview must not create project objects')
for _,item in ipairs(app.placement:compare_runtime().items) do assert(item.id~='__env_fog_preview','Runtime Sync must ignore the environment fog preview') end
assert(not app.lighting:preview_time(12,0),'lighting time preview must defer to an active environment preview')

-- Unforced preview lets time and weather drift; forced preview holds them.
Game.GetTimeSystem():SetGameTimeByHMS(23,15,0);weather.state='24h_weather_cloudy'
envs:update_tick(3);assert(envs:current().hour==23 and envs:current().weather=='24h_weather_cloudy')
assert(envs:set_force(true).force)
envs:update_tick(2.5);assert(envs:current().hour==22 and envs:current().minute==30 and envs:current().weather=='24h_weather_rain','force must re-apply clock and weather')
-- The fog volume follows the player anchor.
local player=Game.GetPlayer();local original_pos=player.GetWorldPosition
player.GetWorldPosition=function() return {x=55,y=20,z=30,w=1} end
envs:update_tick(0.6);assert(app.runtime_shell.handles.__env_fog_preview.position.x==55,'fog volume must follow the player anchor')
player.GetWorldPosition=original_pos

-- Editing the previewed environment re-applies it.
local edited=assert(envs:update(rainy.id,{hour=6,weather_state='q302_light_rain',fog_enabled=false}))
assert(edited.reapplied and envs:current().hour==6 and weather.state=='q302_light_rain')
assert(app.runtime_shell.handles.__env_fog_preview==nil,'disabling fog must remove the preview volume')

-- Restore returns the original clock and hands weather back to the game.
local restored=assert(envs:restore())
assert(restored.restored and restored.parts.weather=='reset_to_game_cycle' and weather.resets==1)
assert(envs:current().hour==8,'original time must be restored')
assert(not envs:status().active and not envs:restore(),'second restore must fail')

-- A lighting time preview in progress is adopted so restore goes back to the true original.
assert(app.lighting:preview_time(20,0))
assert(envs:preview(captured.id,{}))
assert(app.lighting.preview_time_seconds==nil)
assert(envs:restore());assert(envs:current().hour==8,'restore must return to the time before the lighting preview')

-- A failed fog/weather part is a warning; a total failure restores and errors.
local no_weather=Game.GetWeatherSystem
Game.GetWeatherSystem=function() return nil end
local partial=assert(envs:preview(rainy.id,{}));assert(partial.warning:find('WeatherSystem',1,true) and partial.applied.time)
assert(envs:restore())
local weather_only=assert(envs:create({name='Weather only',time_enabled=false}))
assert(not envs:preview(weather_only.id,{}),'nothing applied must fail')
assert(not envs:status().active,'failed preview must leave no active preview')
Game.GetWeatherSystem=no_weather

-- Restore failure keeps the restore point for a retry.
assert(envs:preview(rainy.id,{}))
local saved_ts=Game.GetTimeSystem
Game.GetTimeSystem=function() return nil end
assert(not envs:restore());assert(envs:status().active,'failed restore must keep the restore point')
Game.GetTimeSystem=saved_ts
assert(envs:restore())

-- Delete restores an active preview first; undo brings the record back.
assert(envs:preview(clamped.id,{force=true}))
assert(envs:delete(clamped.id));assert(not envs:status().active and not app.model:get_environment(clamped.id))
assert(app.model:undo());assert(app.model:get_environment(clamped.id))

-- Deleting a premise keeps its environments but unlinks them.
local premise=app.model:add_premise({name='Env Premise',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local linked=assert(envs:create({name='Linked',premise_id=premise.id}))
assert(app.model:delete_premise(premise.id));assert(app.model:get_environment(linked.id).premise_id==nil)

-- Saved environments round-trip through normalization.
local Model=require('modules/model')
local copy=Model.new(app.util.deepcopy(app.model.data));assert(copy:get_environment(rainy.id).weather.state=='q302_light_rain')

-- Bridge operations share the module.
local b=assert(app.bridge:handle({id='e1',op='environment_create',args={name='Bridge env',hour=12,weather_state='24h_weather_sunny'}}))
assert(assert(app.bridge:handle({id='e2',op='environment_preview',args={id=b.environment.id,force=true}})).force)
assert(assert(app.bridge:handle({id='e3',op='environment_status',args={}})).active)
assert(assert(app.bridge:handle({id='e4',op='environment_restore',args={}})).restored)
assert(assert(app.bridge:handle({id='e5',op='environment_weather_states',args={}})).capabilities.weather_set)
assert(assert(app.bridge:handle({id='e6',op='environment_update',args={id=b.environment.id,patch={minute=45}}})).environment.time.minute==45)
assert(assert(app.bridge:handle({id='e7',op='environment_list',args={}})).count>=4)
assert(assert(app.bridge:handle({id='e8',op='environment_delete',args={id=b.environment.id}})).deleted)

-- The Spatial Environment tab draws and reaches the module.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.ui.spatial.env_selected_id=rainy.id
env.clicks['PREVIEW ENVIRONMENT']=true;env:draw()
assert(env.labels['SAVE ENVIRONMENT'] and envs:status().active,'PREVIEW ENVIRONMENT must apply the selected environment')
env.clicks['RESTORE ORIGINAL']=true;env:draw()
assert(not envs:status().active)
env.clicks['CAPTURE CURRENT CONDITIONS']=true;env:draw()
assert(envs:list().count>=5)
print('environment_runtime_test: OK')
