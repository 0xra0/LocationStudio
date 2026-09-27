local Util=require('modules/util')
local RuntimeState=require('modules/runtime_state')

-- Authoring environments: saved time/weather/fog conditions that can be
-- previewed and optionally held ("forced") so screenshots are repeatable.
-- Time uses CET's game-time system, weather uses the game WeatherSystem
-- (SetWeather/ResetWeather), fog uses a transient World Builder Fog Volume.
-- There is no verified CET API for exposure or independent rain intensity;
-- rain follows the chosen weather state and exposure is a note only.
local Environment={};Environment.__index=Environment

local FOG_ID='__env_fog_preview'
local FORCE_TIME_INTERVAL=1.0
local FORCE_WEATHER_INTERVAL=2.0
local FOG_FOLLOW_INTERVAL=0.5

-- Weather-state names used by the base game's 24h cycle and quests. The
-- WeatherSystem accepts any registered state, so custom names are allowed.
local WEATHER_STATES={
    {id='24h_weather_sunny',name='Sunny / clear',rain='none',fog=false},
    {id='24h_weather_light_clouds',name='Light clouds',rain='none',fog=false},
    {id='24h_weather_cloudy',name='Cloudy',rain='none',fog=false},
    {id='24h_weather_heavy_clouds',name='Heavy clouds',rain='none',fog=false},
    {id='24h_weather_fog',name='Fog',rain='none',fog=true},
    {id='24h_weather_pollution',name='Pollution / haze',rain='none',fog=true},
    {id='24h_weather_sandstorm',name='Sandstorm',rain='none',fog=true},
    {id='q302_light_rain',name='Light rain (quest state)',rain='light',fog=false},
    {id='24h_weather_rain',name='Rain',rain='heavy',fog=false},
    {id='q306_rainy_night',name='Rainy night (quest state)',rain='heavy',fog=false},
    {id='24h_weather_toxic_rain',name='Toxic rain',rain='toxic',fog=true},
    {id='q302_deeb_blue',name='Deep blue (quest state)',rain='none',fog=false},
    {id='q302_squat_morning',name='Squat morning (quest state)',rain='none',fog=false},
    {id='q306_epilogue_cloudy_morning',name='Epilogue cloudy morning (quest state)',rain='none',fog=false},
    {id='sa_courier_clouds',name='Courier clouds (side-job state)',rain='none',fog=false},
}
local WEATHER_BY_ID={};for _,w in ipairs(WEATHER_STATES) do WEATHER_BY_ID[w.id]=w end

local function name_to_string(value)
    if type(value)=='string' then return value end
    if value==nil then return nil end
    local ok,text=pcall(function() return Game.NameToString(value) end)
    if ok and type(text)=='string' then return text end
    ok,text=pcall(function() return value.value end)
    if ok and type(text)=='string' then return text end
    return tostring(value)
end

local function cname(value)
    if CName and type(CName.new)=='function' then local ok,v=pcall(CName.new,value);if ok and v~=nil then return v end end
    return value
end

function Environment.new(app,persistent)
    local state=persistent or RuntimeState.get()
    local self=setmetatable({app=app,state=state,force_time=0,force_weather=0,fog_follow=0,last_error=nil},Environment)
    -- A preview survives a CET reload through the process-lifetime state, so
    -- the original time/weather can still be restored after reloading the mod.
    state.environment_preview=state.environment_preview or nil
    return self
end

function Environment:weather_states()
    return Util.deepcopy(WEATHER_STATES)
end

function Environment:_weather_system()
    local ok,ws=pcall(function() return Game.GetWeatherSystem() end)
    if ok and ws then return ws end
    return nil,'CET WeatherSystem is unavailable'
end

function Environment:_time_system()
    local ok,sys=pcall(function() return Game.GetTimeSystem() end)
    if ok and sys then return sys end
    return nil,'CET game-time system is unavailable'
end

function Environment:capabilities()
    local ws=self:_weather_system();local ts=self:_time_system()
    local function has(obj,name) if not obj then return false end;local ok,fn=pcall(function() return obj[name] end);return ok and fn~=nil end
    return {time=ts~=nil,weather_set=has(ws,'SetWeather'),weather_reset=has(ws,'ResetWeather'),weather_read=has(ws,'GetWeatherState'),
        rain_read=has(ws,'GetRainIntensity'),fog_volume=self.app.world_builder~=nil and self.app.runtime_shell~=nil,
        rain_intensity_set=false,exposure_set=false,
        note='Rain follows the weather state. CET exposes no verified exposure or rain-intensity setter; exposure is stored as a note only.'}
end

-- Read-only snapshot of the live conditions.
function Environment:current()
    local out={}
    local ts=self:_time_system()
    if ts then
        local ok,seconds=pcall(function() local t=ts:GetGameTime();local ok2,s=pcall(function() return GameTime.GetSeconds(t) end);if ok2 and type(s)=='number' then return s end;return t.seconds end)
        if ok and type(seconds)=='number' then
            local day=seconds%86400;out.game_seconds=seconds;out.hour=math.floor(day/3600);out.minute=math.floor((day%3600)/60)
        end
    end
    local ws=self:_weather_system()
    if ws then
        local ok,state=pcall(function() return ws:GetWeatherState() end)
        if ok and state then local nok,n=pcall(function() return state.name end);out.weather=name_to_string(nok and n or nil) end
        local rok,rain=pcall(function() return ws:GetRainIntensity() end)
        if rok and type(rain)=='number' then out.rain_intensity=rain end
    end
    if out.weather and WEATHER_BY_ID[out.weather] then out.rain=WEATHER_BY_ID[out.weather].rain end
    return out
end

-- CRUD ---------------------------------------------------------------------

local function validate(value)
    if Util.trim(value.name or '')=='' then return nil,'environment name is required' end
    if value.weather and value.weather.state and not tostring(value.weather.state):match('^[%w_]+$') then return nil,'weather state must be a CName such as 24h_weather_rain' end
    return true
end

local function merge(base,patch)
    local out=Util.deepcopy(base or {})
    for key,value in pairs(patch or {}) do
        if type(value)=='table' and type(out[key])=='table' and #value==0 and next(value)~=nil then out[key]=merge(out[key],value) else out[key]=Util.deepcopy(value) end
    end
    return out
end

-- Accept flat MCP/UI arguments as well as nested {time,weather,fog} tables.
local function shape(args)
    args=args or {}
    local out={name=args.name,premise_id=args.premise_id,exposure_note=args.exposure_note,notes=args.notes}
    if type(args.time)=='table' then out.time=args.time end
    if args.hour~=nil or args.minute~=nil or args.time_enabled~=nil then out.time=merge(out.time,{hour=args.hour,minute=args.minute,enabled=args.time_enabled}) end
    if type(args.weather)=='table' then out.weather=args.weather end
    if args.weather_state~=nil or args.weather_enabled~=nil or args.blend_time~=nil or args.priority~=nil then
        out.weather=merge(out.weather,{state=args.weather_state,enabled=args.weather_enabled,blend_time=args.blend_time,priority=args.priority})
    end
    if type(args.fog)=='table' then out.fog=args.fog end
    for _,key in ipairs({'density_factor','density_falloff','absorption','blend_falloff','anchor','resource_path'}) do
        if args['fog_'..key]~=nil then out.fog=out.fog or {};out.fog[key]=args['fog_'..key] end
    end
    if args.fog_enabled~=nil then out.fog=out.fog or {};out.fog.enabled=args.fog_enabled==true end
    if type(args.fog_size)=='table' then out.fog=out.fog or {};out.fog.size=args.fog_size end
    if type(args.fog_color)=='table' then out.fog=out.fog or {};out.fog.color=args.fog_color end
    for key,value in pairs(out) do if value==nil then out[key]=nil end end
    return out
end

function Environment:list(args)
    args=args or {}
    local out={}
    for _,env in ipairs(self.app.model.data.environments or {}) do
        if not args.premise_id or args.premise_id=='' or env.premise_id==args.premise_id then
            local row=Util.deepcopy(env);local w=WEATHER_BY_ID[env.weather.state]
            row.rain=w and w.rain or 'unknown';row.weather_label=w and w.name or env.weather.state;out[#out+1]=row
        end
    end
    return {items=out,count=#out,active_preview=self:status().active and self.state.environment_preview.environment_id or nil}
end

function Environment:create(args)
    local value=shape(args)
    if Util.trim(value.name or '')=='' then value.name='Environment '..tostring(#(self.app.model.data.environments or {})+1) end
    if args and args.capture_current==true then
        local now=self:current()
        value.time=merge({hour=now.hour,minute=now.minute},value.time)
        if now.weather then value.weather=merge({state=now.weather},value.weather) end
    end
    value.premise_id=value.premise_id or self.app.selected_premise_id
    local ok,err=validate(value);if not ok then return nil,err end
    for _,env in ipairs(self.app.model.data.environments or {}) do if string.lower(env.name)==string.lower(Util.trim(value.name)) then return nil,'an environment with this name already exists' end end
    local env=self.app.model:add_environment(value);self.app:mark_dirty()
    return env
end

function Environment:update(id,patch)
    local env,idx=self.app.model:get_environment(id);if not env then return nil,'environment not found' end
    local shaped=shape(patch)
    local merged=merge(env,shaped);merged.id=env.id;merged.created_at=env.created_at
    local ok,err=validate(merged);if not ok then return nil,err end
    if shaped.name then for _,other in ipairs(self.app.model.data.environments) do if other.id~=id and string.lower(other.name)==string.lower(Util.trim(shaped.name)) then return nil,'an environment with this name already exists' end end end
    self.app.model:snapshot('Update environment')
    local value=self.app.model.normalize_environment(merged);self.app.model.data.environments[idx]=value
    self.app.model:touch();self.app:mark_dirty()
    local result={environment=value}
    local p=self.state.environment_preview
    if p and p.environment_id==id then
        local applied,apply_err=self:_apply(value,p);result.reapplied=applied~=nil;result.warning=apply_err
    end
    return result
end

function Environment:delete(id)
    local env,idx=self.app.model:get_environment(id);if not env then return nil,'environment not found' end
    local p=self.state.environment_preview
    if p and p.environment_id==id then local ok,err=self:restore();if not ok then return nil,'restore the active preview first: '..tostring(err) end end
    self.app.model:snapshot('Delete environment');table.remove(self.app.model.data.environments,idx);self.app.model:touch();self.app:mark_dirty()
    return {deleted=true,id=id}
end

-- Preview / force ------------------------------------------------------------

function Environment:status()
    local p=self.state.environment_preview
    if not p then return {active=false,current=self:current(),last_error=self.last_error} end
    local env=self.app.model:get_environment(p.environment_id)
    return {active=true,environment_id=p.environment_id,name=env and env.name or p.name,force=p.force==true,
        applied=Util.deepcopy(p.applied),original={game_seconds=p.original_seconds,weather=p.original_weather},
        fog_spawned=self.app.runtime_shell and self.app.runtime_shell.handles[FOG_ID]~=nil or false,
        current=self:current(),warnings=Util.deepcopy(p.warnings or {}),last_error=self.last_error}
end

function Environment:_set_time(hour,minute)
    local ts,err=self:_time_system();if not ts then return nil,err end
    local ok,set_err=pcall(function() ts:SetGameTimeByHMS(hour,minute,0) end)
    if not ok then return nil,'time change failed: '..tostring(set_err) end
    return true
end

function Environment:_set_weather(weather,blend)
    local ws,err=self:_weather_system();if not ws then return nil,err end
    local ok,set_err=pcall(function() ws:SetWeather(cname(weather.state),tonumber(blend or weather.blend_time) or 0,weather.priority or 9) end)
    if not ok then return nil,'weather change failed: '..tostring(set_err) end
    return true
end

function Environment:_fog_anchor(env)
    if env.fog.anchor=='premise' then
        local premise=self.app.model:get_premise(env.premise_id or self.app.selected_premise_id)
        if not premise then return nil,'fog anchor is premise, but the environment has no existing premise' end
        return Util.deepcopy(premise.transform.position)
    elseif env.fog.anchor=='camera' then
        local t=self.app.game:capture_camera_transform();if not t then return nil,'camera transform unavailable' end
        return Util.deepcopy(t.position)
    end
    local t,err=self.app.game:capture_transform();if not t then return nil,err end
    return Util.deepcopy(t.position)
end

function Environment:_fog_object(env,position)
    local wb=self.app.world_builder;if not wb then return nil,'World Builder backend is unavailable' end
    local result,err=wb:search('fog',env.fog.resource_path or '',50,false);if not result then return nil,err end
    local resource
    for _,item in ipairs(result.items or {}) do if env.fog.resource_path=='' or string.lower(item.path)==string.lower(env.fog.resource_path) or string.lower(item.name)==string.lower(env.fog.resource_path) then resource=item;break end end
    if not resource then return nil,'World Builder Fog Volume catalog has no matching preset' end
    local payload;payload,err=wb:prepare_favorite_record({category='Lighting',variant='Fog Volume',spawn_data=resource.path,name=resource.name},'Environment fog preview')
    if not payload then return nil,err end
    local saved=payload.data and payload.data.spawnable;if type(saved)~='table' then return nil,'World Builder returned no Fog Volume data' end
    local f=env.fog
    -- Field names follow World Builder's fog class (worldStaticFogVolumeNode).
    saved.scale={x=f.size.x,y=f.size.y,z=f.size.z};saved.densityFactor=f.density_factor;saved.densityFalloff=f.density_falloff
    saved.absorption=f.absorption;saved.blendFalloff=f.blend_falloff;saved.color={f.color[1],f.color[2],f.color[3]};saved.previewed=true
    return {id=FOG_ID,name='Environment fog preview',kind='volume',template='',size={x=1,y=1,z=1},enabled=true,
        transform={position={x=position.x,y=position.y,z=position.z,w=1},rotation={roll=0,pitch=0,yaw=0}},
        metadata={world_builder={definition_key='fog',category='Lighting',variant='Fog Volume',class_module='modules/classes/spawn/visual/fog',module_path='visual/fog',
            resource_name=resource.name,resource_path=resource.path,entry={name=payload.name,fileName=payload.name,data=saved},apply_scale=false}},runtime={}}
end

function Environment:_clear_fog()
    local shell=self.app.runtime_shell
    if not shell or not shell.handles[FOG_ID] then return true end
    local ok,err=shell:despawn({id=FOG_ID,runtime={backend='world_builder'}})
    if not ok then return nil,err end
    self.fog_object=nil
    return true
end

function Environment:_spawn_fog(env)
    local position,err=self:_fog_anchor(env);if not position then return nil,err end
    local object;object,err=self:_fog_object(env,position);if not object then return nil,err end
    local cleared,clear_err=self:_clear_fog();if not cleared then return nil,'previous fog preview could not be removed: '..tostring(clear_err) end
    local id;id,err=self.app.runtime_shell:spawn(object);if not id then return nil,err end
    self.fog_object=object
    return true
end

-- Apply an environment's enabled parts. Every part is attempted; failures are
-- collected so a missing fog catalog does not block the time/weather preview.
function Environment:_apply(env,p)
    local applied,warnings={},{}
    if env.time.enabled then
        local ok,err=self:_set_time(env.time.hour,env.time.minute)
        if ok then applied.time={hour=env.time.hour,minute=env.time.minute} else warnings[#warnings+1]=err end
    end
    if env.weather.enabled then
        local ok,err=self:_set_weather(env.weather)
        if ok then applied.weather={state=env.weather.state,blend_time=env.weather.blend_time,priority=env.weather.priority} else warnings[#warnings+1]=err end
    end
    if env.fog.enabled then
        local ok,err=self:_spawn_fog(env)
        if ok then applied.fog={anchor=env.fog.anchor,size=Util.deepcopy(env.fog.size),density_factor=env.fog.density_factor} else warnings[#warnings+1]='fog volume: '..tostring(err) end
    else
        local ok,err=self:_clear_fog();if not ok then warnings[#warnings+1]='fog volume removal: '..tostring(err) end
    end
    if Util.trim(env.exposure_note or '')~='' then warnings[#warnings+1]='exposure is a note only; CET exposes no verified exposure control' end
    p.applied=applied;p.warnings=warnings
    if next(applied)==nil then return nil,table.concat(warnings,'; ') end
    return applied,#warnings>0 and table.concat(warnings,'; ') or nil
end

function Environment:_blocked()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    return nil
end

function Environment:preview(id,args)
    args=args or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local env=self.app.model:get_environment(id);if not env then return nil,'environment not found' end
    local p=self.state.environment_preview
    if not p then
        -- Record what to restore once, before the first change.
        local now=self:current()
        local original_seconds=now.game_seconds
        local lighting=self.app.lighting
        if lighting and lighting.preview_time_seconds~=nil then original_seconds=lighting.preview_time_seconds;lighting.preview_time_seconds=nil end
        if env.time.enabled and original_seconds==nil then return nil,'could not read the current game time for restoration' end
        p={original_seconds=original_seconds,original_weather=now.weather,started_at=os.time()}
    end
    p.environment_id=env.id;p.name=env.name;p.force=args.force==true
    self.state.environment_preview=p
    local applied,err=self:_apply(env,p)
    if not applied then
        local restored=self:restore()
        return nil,'environment preview failed: '..tostring(err)..(restored and '' or '; original conditions could not be fully restored')
    end
    self.force_time,self.force_weather,self.fog_follow=0,0,0
    local status=self:status();status.warning=err
    return status
end

function Environment:set_force(force)
    local p=self.state.environment_preview;if not p then return nil,'no environment preview is active' end
    p.force=force==true;return self:status()
end

function Environment:restore(args)
    args=args or {}
    local p=self.state.environment_preview;if not p then return nil,'no environment preview to restore' end
    local errors,restored={}, {}
    local fog_ok,fog_err=self:_clear_fog();if fog_ok then restored.fog=true else errors[#errors+1]='fog: '..tostring(fog_err) end
    if p.applied and p.applied.weather then
        local ws,err=self:_weather_system()
        if ws then
            -- ResetWeather hands weather back to the game's normal cycle. A state
            -- forced by a quest before preview is re-evaluated by the game.
            local ok,reset_err=pcall(function() ws:ResetWeather(true,tonumber(args.blend_time) or 0) end)
            if ok then restored.weather='reset_to_game_cycle' else errors[#errors+1]='weather: '..tostring(reset_err) end
        else errors[#errors+1]='weather: '..tostring(err) end
    end
    if p.applied and p.applied.time and p.original_seconds~=nil then
        local ts,err=self:_time_system()
        if ts then
            local ok,time_err=pcall(function() ts:GetGameTime():SetGameTimeBySeconds(p.original_seconds) end)
            if ok then restored.time=p.original_seconds else errors[#errors+1]='time: '..tostring(time_err) end
        else errors[#errors+1]='time: '..tostring(err) end
    end
    if #errors>0 then
        -- Keep the restore point so a later retry can still reach the original state.
        self.last_error=table.concat(errors,'; ');return nil,'environment restore incomplete: '..self.last_error
    end
    self.state.environment_preview=nil;self.last_error=nil
    return {restored=true,parts=restored,original_weather=p.original_weather}
end

function Environment:update_tick(delta)
    local p=self.state.environment_preview;if not p then return end
    delta=tonumber(delta) or 0
    local env=self.app.model:get_environment(p.environment_id);if not env then return end
    if p.force then
        self.force_time=self.force_time+delta;self.force_weather=self.force_weather+delta
        if env.time.enabled and self.force_time>=FORCE_TIME_INTERVAL then
            self.force_time=0;local ok,err=self:_set_time(env.time.hour,env.time.minute);if not ok then self.last_error=err end
        end
        if env.weather.enabled and self.force_weather>=FORCE_WEATHER_INTERVAL then
            self.force_weather=0
            local now=self:current()
            if now.weather~=env.weather.state then local ok,err=self:_set_weather(env.weather,0);if not ok then self.last_error=err end end
        end
    end
    if env.fog.enabled and env.fog.anchor~='premise' and self.fog_object and self.app.runtime_shell.handles[FOG_ID] then
        self.fog_follow=self.fog_follow+delta
        if self.fog_follow>=FOG_FOLLOW_INTERVAL then
            self.fog_follow=0
            local position=self:_fog_anchor(env)
            if position then
                self.fog_object.transform.position={x=position.x,y=position.y,z=position.z,w=1}
                local ok,err=self.app.runtime_shell:update_object(self.fog_object,{silent=true});if not ok then self.last_error=err end
            end
        end
    end
end

Environment.FOG_ID=FOG_ID
return Environment
