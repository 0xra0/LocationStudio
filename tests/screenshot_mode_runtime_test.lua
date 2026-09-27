local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local mode=assert(app.screenshot_mode,'screenshot mode module must be constructed')
local cfg=app.model.data.settings.screenshot_mode
assert(cfg.hide_hud and cfg.freeze_world and #cfg.hud_vars>=10 and #cfg.post_effect_vars>=1)

-- Fake CET settings system: MotionBlur is a list var that only accepts SetIndex;
-- 'npc_names' does not exist in this "build"; 'minimap' refuses writes.
local vars={}
local function bool_var(value) return {value=value,GetValue=function(self) return self.value end,SetValue=function(self,v) self.value=v end} end
for _,v in ipairs(cfg.hud_vars) do vars[v.group..'/'..v.name]=bool_var(true) end
vars['/interface/hud/npc_names']=nil
vars['/interface/hud/minimap'].SetValue=function() error('read-only in this build') end
vars['/interface/hud/quest_tracker'].value=false -- already hidden: recorded, not changed
local blur={options={'Off','Low','High'},index=2}
function blur:GetValue() return self.options[self.index+1] end
function blur:SetValue() error('list settings need an index') end
function blur:GetValues() return self.options end
function blur:SetIndex(i) self.index=i end
vars['/graphics/basic/MotionBlur']=blur
vars['/graphics/basic/FilmGrain']=bool_var(true)
local confirmed=0
function Game.GetSettingsSystem()
    return {GetVar=function(_,group,name) return vars[group..'/'..name] end,NeedsConfirmation=function() return true end,ConfirmChanges=function() confirmed=confirmed+1 end}
end
-- Fake time dilation on the mocked time system.
local dilation={}
local base_time=Game.GetTimeSystem
function Game.GetTimeSystem()
    local ts=base_time()
    ts.SetTimeDilation=function(_,reason,value) dilation[tostring(reason)]=value end
    ts.UnsetTimeDilation=function(_,reason) dilation[tostring(reason)]=nil end
    return ts
end

local caps=mode:capabilities()
assert(caps.time_dilation and caps.environment)
local available=0;for _,row in ipairs(caps.settings) do if row.available then available=available+1 end end
assert(available==#caps.settings-4,'npc_names, ChromaticAberration, DepthOfField and LensFlares are missing in this fake build')
assert(vars['/interface/hud/healthbar'].value==true,'capabilities must not change settings')

-- Enter: record previous values, then apply.
local state=assert(mode:enter({}))
assert(state.active and not state.frozen)
assert(vars['/interface/hud/healthbar'].value==false and blur.index==0 and vars['/graphics/basic/FilmGrain'].value==false)
assert(confirmed>=1,'changed settings must be confirmed')
local reasons={};for _,row in ipairs(state.unavailable) do reasons[row.name]=row.reason end
assert(reasons.npc_names:find('does not exist',1,true) and reasons.minimap:find('could not set',1,true))
local quest;for _,row in ipairs(state.applied) do if row.name=='quest_tracker' then quest=row end end
assert(quest and quest.changed==false,'already-hidden settings are not rewritten')
assert(not mode:enter({}),'entering twice must fail')

-- Freeze only while shooting.
assert(assert(mode:freeze()).frozen and dilation.LocationStudioScreenshot==0.0001)
assert(mode:status().frozen)
assert(not assert(mode:unfreeze()).frozen and dilation.LocationStudioScreenshot==nil)

-- Streaming readiness needs consecutive collision hits.
cfg.ready_samples=3
mode:reset_ready()
assert(not mode:ready().ready and not mode:ready().ready)
local r=mode:ready();assert(r.ready and r.hits==3)
env.ground_miss=true
local miss=mode:ready();assert(not miss.ready and miss.hits==0 and miss.reason)
env.ground_miss=false

-- Restore returns exact previous values, including the list index, and unfreezes.
assert(mode:freeze())
local restored=assert(mode:restore())
assert(restored.restored and restored.settings_restored>=3)
assert(vars['/interface/hud/healthbar'].value==true and blur.index==2 and vars['/graphics/basic/FilmGrain'].value==true)
assert(vars['/interface/hud/quest_tracker'].value==false,'unchanged settings stay as they were')
assert(dilation.LocationStudioScreenshot==nil and not mode:status().active)
assert(not mode:restore(),'restore without screenshot mode must fail')

-- Options can skip HUD / post effects / freeze.
assert(mode:enter({hide_hud=false,freeze_world=false}))
assert(vars['/interface/hud/healthbar'].value==true and blur.index==0)
assert(assert(mode:freeze()).skipped)
assert(mode:restore());assert(blur.index==2)

-- A failed restore keeps only what still needs restoring, so a retry is safe.
assert(mode:enter({}))
local saved=vars['/interface/hud/healthbar'].SetValue
vars['/interface/hud/healthbar'].SetValue=function() error('temporarily locked') end
assert(not mode:restore());assert(mode:status().active and #mode:status().applied==1)
assert(vars['/graphics/basic/FilmGrain'].value==true,'other settings are restored even when one fails')
vars['/interface/hud/healthbar'].SetValue=saved
assert(mode:restore());assert(vars['/interface/hud/healthbar'].value==true)

-- Screenshot mode can force a saved environment and restores it too.
function Game.GetWeatherSystem() return {SetWeather=function() end,ResetWeather=function() end,GetWeatherState=function() return {name='24h_weather_sunny'} end} end
local environment=assert(app.environment:create({name='Shot env',hour=21,minute=0,weather_state='24h_weather_rain'}))
local with_env=assert(mode:enter({environment_id=environment.id}))
assert(with_env.environment_id==environment.id and with_env.environment_applied.time.hour==21)
assert(app.environment:status().active and app.environment:status().force)
assert(mode:restore());assert(not app.environment:status().active and app.environment:current().hour==8)
assert(not mode:enter({environment_id='missing'}),'unknown environment must fail')
assert(not mode:status().active and vars['/interface/hud/healthbar'].value==true,'a failed enter must restore what it changed')

-- Transactions block entering.
local real=app.transform_session.is_active
app.transform_session.is_active=function() return true end
assert(not mode:enter({}))
app.transform_session.is_active=real

-- Bridge operations.
assert(assert(app.bridge:handle({id='s1',op='screenshot_mode_capabilities',args={}})).time_dilation)
assert(assert(app.bridge:handle({id='s2',op='screenshot_mode_enter',args={}})).active)
assert(assert(app.bridge:handle({id='s3',op='screenshot_mode_freeze',args={}})).frozen)
assert(assert(app.bridge:handle({id='s4',op='screenshot_mode_unfreeze',args={}})).frozen==false)
assert(assert(app.bridge:handle({id='s5',op='screenshot_mode_reset_ready',args={}})).reset)
assert(app.bridge:handle({id='s6',op='screenshot_mode_ready',args={}}).hits==1)
assert(assert(app.bridge:handle({id='s7',op='screenshot_mode_status',args={}})).active)
assert(assert(app.bridge:handle({id='s8',op='screenshot_mode_restore',args={}})).restored)

-- UI section draws and reaches the module.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['ENTER SCREENSHOT MODE']=true;env:draw();assert(mode:status().active)
env.clicks['FREEZE WORLD']=true;env:draw();assert(mode:status().frozen)
env.clicks['RESTORE SCREENSHOT MODE']=true;env:draw();assert(not mode:status().active and dilation.LocationStudioScreenshot==nil)
env.clicks['CHECK GAME SETTINGS']=true;env:draw();assert(app.ui.spatial.shot_caps)
print('screenshot_mode_runtime_test: OK')
