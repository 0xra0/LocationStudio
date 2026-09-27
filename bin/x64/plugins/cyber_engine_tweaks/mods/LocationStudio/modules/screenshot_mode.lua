local Util=require('modules/util')
local RuntimeState=require('modules/runtime_state')

-- Deterministic screenshot mode. Removes run-to-run noise before a capture and
-- restores every change afterwards:
--   * HUD and post effects (motion blur, film grain, ...) through CET settings
--     ConfigVars. The previous value of each variable is recorded before it
--     is changed; variables missing from this game build are reported.
--   * NPC, traffic, cloud and particle motion through a named global time
--     dilation that is held only for the instant of a shot.
--   * Streaming readiness through repeated collision probes around the camera.
-- Fixed time/weather comes from a saved environment (modules/environment).
local ScreenshotMode={};ScreenshotMode.__index=ScreenshotMode

local DILATION_REASON='LocationStudioScreenshot'

local function cname(value)
    if CName and type(CName.new)=='function' then local ok,v=pcall(CName.new,value);if ok and v~=nil then return v end end
    return value
end

function ScreenshotMode.new(app,persistent)
    return setmetatable({app=app,state=persistent or RuntimeState.get(),last_error=nil,ready_hits=0},ScreenshotMode)
end

function ScreenshotMode:settings()
    return self.app.model.data.settings.screenshot_mode
end

function ScreenshotMode:_settings_system()
    local ok,sys=pcall(function() return Game.GetSettingsSystem() end)
    if ok and sys then return sys end
    return nil,'CET settings system is unavailable'
end

function ScreenshotMode:_var(group,name)
    local sys,err=self:_settings_system();if not sys then return nil,err end
    local ok,var=pcall(function() return sys:GetVar(group,name) end)
    if not ok or var==nil then return nil,'setting '..tostring(group)..'/'..tostring(name)..' does not exist in this game build' end
    return var
end

local function read_value(var)
    local ok,value=pcall(function() return var:GetValue() end)
    if ok then return value end
    return nil
end

-- List settings (for example MotionBlur Off/Low/High) may only accept an
-- index; fall back to SetIndex when a direct SetValue is refused.
local function write_value(var,value)
    local ok,err=pcall(function() var:SetValue(value) end)
    if ok then return true end
    local list_ok,values=pcall(function() return var:GetValues() end)
    if list_ok and type(values)=='table' then
        for i,candidate in ipairs(values) do
            if tostring(candidate)==tostring(value) then
                local set_ok,set_err=pcall(function() var:SetIndex(i-1) end)
                if set_ok then return true end
                return nil,tostring(set_err)
            end
        end
    end
    return nil,tostring(err)
end

function ScreenshotMode:_confirm()
    local sys=self:_settings_system();if not sys then return end
    pcall(function() if sys:NeedsConfirmation() then sys:ConfirmChanges() end end)
end

function ScreenshotMode:_selected_vars(options)
    local s=self:settings();local out={}
    local function add(list,kind) for _,v in ipairs(list or {}) do if type(v)=='table' and v.group and v.name then out[#out+1]={group=v.group,name=v.name,value=v.value,kind=kind} end end end
    if options.hide_hud~=false and s.hide_hud~=false then add(s.hud_vars,'hud') end
    if options.disable_post_effects~=false and s.disable_post_effects~=false then add(s.post_effect_vars,'post_effect');add(s.camera_shake_vars,'camera_shake') end
    add(s.extra_vars,'extra')
    return out
end

-- Report which configured variables exist in the running game, without changing them.
function ScreenshotMode:capabilities()
    local rows={}
    for _,v in ipairs(self:_selected_vars({})) do
        local var,err=self:_var(v.group,v.name)
        rows[#rows+1]={group=v.group,name=v.name,kind=v.kind,available=var~=nil,current=var and read_value(var) or nil,reason=err}
    end
    local ts_ok,ts=pcall(function() return Game.GetTimeSystem() end)
    local function has(obj,name) if not obj then return false end;local ok,fn=pcall(function() return obj[name] end);return ok and fn~=nil end
    return {settings=rows,time_dilation=ts_ok and has(ts,'SetTimeDilation') and has(ts,'UnsetTimeDilation') or false,
        environment=self.app.environment~=nil,camera_shake_note='No verified camera-shake setting ships in the defaults; freezing the world stops time-driven shake. Add a ConfigVar to camera_shake_vars if your build has one.'}
end

function ScreenshotMode:status()
    local rec=self.state.screenshot_mode
    if not rec then return {active=false,frozen=false,last_error=self.last_error} end
    return {active=true,frozen=rec.frozen==true,applied=Util.deepcopy(rec.applied),unavailable=Util.deepcopy(rec.unavailable),
        environment_id=rec.environment_id,started_at=rec.started_at,last_error=self.last_error}
end

function ScreenshotMode:enter(args)
    args=args or {}
    if self.state.screenshot_mode then return nil,'screenshot mode is already active; restore it first' end
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return nil,'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return nil,'Stop the active stamp session first' end
    local rec={applied={},unavailable={},started_at=os.time(),frozen=false,freeze=args.freeze_world~=false and self:settings().freeze_world~=false}
    self.state.screenshot_mode=rec
    -- Record every previous value before changing anything, so restore can
    -- always return the exact user settings even after a partial failure.
    for _,v in ipairs(self:_selected_vars(args)) do
        local var,err=self:_var(v.group,v.name)
        if not var then rec.unavailable[#rec.unavailable+1]={group=v.group,name=v.name,kind=v.kind,reason=err}
        else
            local previous=read_value(var)
            if previous==nil then rec.unavailable[#rec.unavailable+1]={group=v.group,name=v.name,kind=v.kind,reason='current value could not be read, so it would not be restorable'}
            elseif previous==v.value then rec.applied[#rec.applied+1]={group=v.group,name=v.name,kind=v.kind,previous=previous,value=v.value,changed=false}
            else
                local ok,set_err=write_value(var,v.value)
                if ok then rec.applied[#rec.applied+1]={group=v.group,name=v.name,kind=v.kind,previous=previous,value=v.value,changed=true}
                else rec.unavailable[#rec.unavailable+1]={group=v.group,name=v.name,kind=v.kind,reason='could not set: '..tostring(set_err)} end
            end
        end
    end
    self:_confirm()
    if args.environment_id and args.environment_id~='' then
        if not app.environment then self:restore();return nil,'environment module is unavailable' end
        local result,err=app.environment:preview(args.environment_id,{force=true})
        if not result then self:restore();return nil,'could not apply environment: '..tostring(err) end
        rec.environment_id=args.environment_id;rec.environment_warning=result.warning;rec.environment_applied=Util.deepcopy(result.applied)
    end
    self.ready_hits=0
    local status=self:status();status.environment_warning=rec.environment_warning;status.environment_applied=rec.environment_applied
    return status
end

function ScreenshotMode:_dilation(value)
    local ok,ts=pcall(function() return Game.GetTimeSystem() end)
    if not ok or not ts then return nil,'CET game-time system is unavailable' end
    local set_ok,err=pcall(function()
        if value then ts:SetTimeDilation(cname(DILATION_REASON),value)
        else ts:UnsetTimeDilation(cname(DILATION_REASON)) end
    end)
    if not set_ok then return nil,'time dilation failed: '..tostring(err) end
    return true
end

-- Freeze only around the shot itself: streaming and teleport settling run in
-- normal time, then NPCs/traffic/particles are held for the capture.
function ScreenshotMode:freeze()
    local rec=self.state.screenshot_mode;if not rec then return nil,'screenshot mode is not active' end
    if not rec.freeze then return {frozen=false,skipped='freeze_world is off'} end
    if rec.frozen then return {frozen=true} end
    local ok,err=self:_dilation(math.max(0.00001,tonumber(self:settings().freeze_dilation) or 0.0001))
    if not ok then return nil,err end
    rec.frozen=true;return {frozen=true}
end

function ScreenshotMode:unfreeze()
    local rec=self.state.screenshot_mode
    if not rec or not rec.frozen then return {frozen=false} end
    local ok,err=self:_dilation(nil);if not ok then return nil,err end
    rec.frozen=false;return {frozen=false}
end

-- Streaming readiness: static collision below and in front of the camera must
-- answer for several consecutive probes. Missing collision means the sector
-- around the shot has not streamed in yet.
function ScreenshotMode:ready()
    local game=self.app.game
    if not Game.GetPlayer() then self.ready_hits=0;return {ready=false,reason='player is not available (loading screen?)'} end
    local camera=game:capture_camera_transform()
    if not camera then self.ready_hits=0;return {ready=false,reason='camera transform unavailable'} end
    local p=camera.position
    local ground=game:raycast({x=p.x,y=p.y,z=p.z,w=1},{x=p.x,y=p.y,z=p.z-60,w=1},{'Static','Terrain'})
    local forward=game:camera_forward()
    local ahead=forward and game:raycast({x=p.x,y=p.y,z=p.z,w=1},{x=p.x+forward.x*80,y=p.y+forward.y*80,z=p.z+forward.z*80,w=1},{'Static','Terrain'}) or nil
    if ground then self.ready_hits=self.ready_hits+1 else self.ready_hits=0 end
    local needed=math.max(1,math.floor(tonumber(self:settings().ready_samples) or 3))
    return {ready=self.ready_hits>=needed,hits=self.ready_hits,needed=needed,ground=ground~=nil,ahead=ahead~=nil,
        reason=ground and nil or 'no static collision below the camera yet'}
end

function ScreenshotMode:reset_ready() self.ready_hits=0;return {reset=true} end

function ScreenshotMode:restore()
    local rec=self.state.screenshot_mode;if not rec then return nil,'screenshot mode is not active' end
    local errors,restored={},0
    if rec.frozen then local ok,err=self:_dilation(nil);if ok then rec.frozen=false else errors[#errors+1]=err end end
    local remaining={}
    for i=#rec.applied,1,-1 do
        local v=rec.applied[i]
        if v.changed then
            local var,err=self:_var(v.group,v.name)
            local ok,set_err
            if var then ok,set_err=write_value(var,v.previous) end
            if ok then restored=restored+1 else errors[#errors+1]=v.group..'/'..v.name..': '..tostring(err or set_err);table.insert(remaining,1,v) end
        end
    end
    self:_confirm()
    local env_restored=nil
    if rec.environment_id and self.app.environment and self.app.environment:status().active then
        local ok,err=self.app.environment:restore()
        if ok then env_restored=true else errors[#errors+1]='environment: '..tostring(err) end
    end
    if #errors>0 then
        -- Keep only what still needs restoring so a retry is safe.
        rec.applied=remaining;if env_restored then rec.environment_id=nil end
        self.last_error=table.concat(errors,'; ')
        return nil,'screenshot mode restore incomplete: '..self.last_error
    end
    self.state.screenshot_mode=nil;self.last_error=nil;self.ready_hits=0
    return {restored=true,settings_restored=restored,environment_restored=env_restored==true}
end

return ScreenshotMode
