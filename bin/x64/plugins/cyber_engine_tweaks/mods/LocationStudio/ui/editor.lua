local Theme=require('ui/theme')
local Hierarchy=require('ui/hierarchy')
local Inspector=require('ui/inspector')
local Browser=require('ui/browser')
local Viewport=require('ui/viewport')
local Premises=require('ui/premises')
local Spatial=require('ui/spatial')
local Tools=require('ui/tools')
local Home=require('ui/home')
local Help=require('ui/help')
local SceneDirector=require('ui/scene_director')

local Editor={}
Editor.__index=Editor

local function xy(a,b)
    if (type(a)=='table' or type(a)=='userdata') and a.x then return a.x,a.y end
    return a,b
end

local function traceback(err)
    if debug and debug.traceback then return debug.traceback(tostring(err),2) end
    return tostring(err)
end

function Editor.new(app)
    local self=setmetatable({app=app,toast=nil,toast_until=0,panel_errors={}},Editor)
    local notify=function(message) self:notify(message) end
    self.hierarchy=Hierarchy.new(app,notify)
    self.inspector=Inspector.new(app,notify)
    self.browser=Browser.new(app,notify)
    self.viewport=Viewport.new(app,notify)
    self.premises=Premises.new(app,notify)
    self.spatial=Spatial.new(app,notify)
    self.tools=Tools.new(app,notify)
    self.home=Home.new(app,notify)
    self.help=Help.new(app,notify)
    self.scene_director=SceneDirector.new(app,notify)
    local ws=app.model.data.settings.workspace
    if ws.beginner_mode~=false then
        if ws.panel~='LIBRARY' and ws.panel~='SCENE' and ws.panel~='HELP' then ws.panel='HOME' end
    end
    ws.panel=ws.panel or 'HOME'
    return self
end

function Editor:notify(text,seconds)
    self.toast=tostring(text or 'Done');self.toast_until=os.clock()+(seconds or 3.5)
    if self.app.logger then self.app.logger:info('ui:notification',self.toast) end
end

function Editor:run(label,fn,scope)
    scope=scope or label
    if self.app.logger then self.app.logger:debug('ui:action','clicked',{action=scope}) end
    local packed={xpcall(fn,traceback)};local ok=packed[1]
    if not ok then
        local err=tostring(packed[2]);if self.app.logger then self.app.logger:error('ui:action','exception',{action=scope,error=err}) end
        self:notify(label..' failed: '..err,6);return nil,err
    end
    local result,err=packed[2],packed[3]
    if result then self:notify(err or label) else self:notify(err or (label..' failed'),6) end
    return result,err
end

function Editor:child(id,width,height,draw,border)
    ImGui.BeginChild(id,width,height,border~=false)
    local ok,err=xpcall(draw,traceback)
    if not ok then
        if self.panel_errors[id]~=tostring(err) and self.app.logger then self.app.logger:error('ui:panel','panel_failed',{panel=id,error=tostring(err)}) end
        self.panel_errors[id]=tostring(err)
        ImGui.Separator();Theme.bad('PANEL ERROR');ImGui.TextWrapped(tostring(err));Theme.muted('Other panels remain usable. See DEBUG LOG in Advanced Tools.')
    else self.panel_errors[id]=nil end
    ImGui.EndChild()
    return ok,err
end

function Editor:draw_transform_session()
    local session=self.app.transform_session;local status=session and session:status() or {active=false}
    if not status.active then return end
    if status.kind=='edit' then
        local titles={duplicate='DUPLICATE EDIT ACTIVE',placement='PLACEMENT EDIT ACTIVE',pattern='ARRAY EDIT ACTIVE',mirror='MIRROR EDIT ACTIVE',scatter='SCATTER EDIT ACTIVE'}
        local title=titles[status.operation] or 'TRANSFORM EDIT ACTIVE'
        Theme.warning(string.format('%s / %d OBJECT%s',title,status.count or 0,(status.count or 0)==1 and '' or 'S'))
        local context='';local creation=status.creation or {}
        if status.operation=='pattern' then context=string.format(' | %d set(s) x %d source(s)',creation.repetitions or 0,creation.source_count or 0)
        elseif status.operation=='mirror' then context=' | location '..string.upper(tostring(creation.axis or '?'))..' axis'
        elseif status.operation=='placement' then context=' | '..tostring(creation.source_kind or '?')..' from '..tostring(creation.placement_source or creation.mode or '?')
        elseif status.operation=='scatter' then context=string.format(' | %d stamp(s), seed %s',creation.repetitions or 0,tostring(creation.seed or '?')) end
        ImGui.SameLine();Theme.muted(string.format('%s axes | pivot %s | WB in-place %d | CET respawn %d%s',status.local_space and 'local' or 'world',tostring(status.pivot_mode or 'center'),status.live_world_builder or 0,status.deferred_cet or 0,context))
        local settings=self.app.model.data.settings.transform_edit or {};local changed
        settings.local_space,changed=ImGui.Checkbox('Local axes##edit_header',status.local_space==true);if changed then self.app:mark_dirty();local _,err=session:adjust({local_space=settings.local_space});if err then self:notify(err) end end
        ImGui.SameLine();ImGui.PushItemWidth(78);settings.move_step,changed=ImGui.InputFloat('Move##edit_header',tonumber(settings.move_step) or 0.25,0.05,0.5,'%.3f');ImGui.PopItemWidth();if changed then settings.move_step=math.max(0.001,settings.move_step);self.app:mark_dirty() end
        ImGui.SameLine();ImGui.PushItemWidth(72);settings.angle_step,changed=ImGui.InputFloat('Angle##edit_header',tonumber(settings.angle_step) or 5,1,15,'%.1f');ImGui.PopItemWidth();if changed then settings.angle_step=math.max(0.1,settings.angle_step);self.app:mark_dirty() end
        ImGui.SameLine();ImGui.PushItemWidth(70);settings.scale_step,changed=ImGui.InputFloat('Scale##edit_header',tonumber(settings.scale_step) or 0.1,0.01,0.25,'%.3f');ImGui.PopItemWidth();if changed then settings.scale_step=math.max(0.001,settings.scale_step);self.app:mark_dirty() end
        local function adjust(patch,label)
            local result,err=session:adjust(patch);self:notify(err or (result and label or 'Transform failed'))
        end
        local move=math.max(0.001,tonumber(settings.move_step) or 0.25);local angle=math.max(0.1,tonumber(settings.angle_step) or 5);local scale=math.max(0.001,tonumber(settings.scale_step) or 0.1)
        if Theme.action_button('-X##edit_header',38,27) then adjust({dx=-move},'Moved -X') end;ImGui.SameLine();if Theme.action_button('+X##edit_header',38,27) then adjust({dx=move},'Moved +X') end
        ImGui.SameLine();if Theme.action_button('-Y##edit_header',38,27) then adjust({dy=-move},'Moved -Y') end;ImGui.SameLine();if Theme.action_button('+Y##edit_header',38,27) then adjust({dy=move},'Moved +Y') end
        ImGui.SameLine();if Theme.action_button('-Z##edit_header',38,27) then adjust({dz=-move},'Moved -Z') end;ImGui.SameLine();if Theme.action_button('+Z##edit_header',38,27) then adjust({dz=move},'Moved +Z') end
        ImGui.NewLine()
        if (status.count or 0)==1 then
            if Theme.action_button('ROLL -##edit_header',62,27) then adjust({droll=-angle},'Rolled') end;ImGui.SameLine();if Theme.action_button('ROLL +##edit_header',62,27) then adjust({droll=angle},'Rolled') end
            ImGui.SameLine();if Theme.action_button('PITCH -##edit_header',68,27) then adjust({dpitch=-angle},'Pitched') end;ImGui.SameLine();if Theme.action_button('PITCH +##edit_header',68,27) then adjust({dpitch=angle},'Pitched') end
            ImGui.SameLine()
        end
        if Theme.action_button('YAW -##edit_header',62,27) then adjust({dyaw=-angle},'Rotated') end;ImGui.SameLine();if Theme.action_button('YAW +##edit_header',62,27) then adjust({dyaw=angle},'Rotated') end
        if (status.deferred_cet or 0)==0 then
            ImGui.SameLine();if Theme.action_button('SIZE -##edit_header',62,27) then adjust({scale_factor=1/(1+scale)},'Scaled down') end
            ImGui.SameLine();if Theme.action_button('SIZE +##edit_header',62,27) then adjust({scale_factor=1+scale},'Scaled up') end
        else ImGui.SameLine();Theme.muted('Scale requires World Builder resources') end
        ImGui.SameLine();if Theme.action_button('RESET##edit_header',62,27) then local result,err=session:reset_edit();self:notify(err or (result and 'Transform reset' or 'Reset failed')) end
        ImGui.SameLine();if Theme.primary_button('COMMIT##edit_header',86,29) then local result,err=session:commit();self:notify(err or (result and 'Transform committed' or 'Commit failed')) end
        ImGui.SameLine();if Theme.danger_button('CANCEL##edit_header',82,29) then local result,err=session:cancel();self:notify(err or (result and 'Transform cancelled' or 'Cancel failed')) end
        local t=status.translation or {};local r=status.rotation_delta or {}
        Theme.muted(string.format('Delta  X %.3f  Y %.3f  Z %.3f  |  Roll %.1f  Pitch %.1f  Yaw %.1f  |  Scale %.3f',t.x or 0,t.y or 0,t.z or 0,r.roll or 0,r.pitch or 0,r.yaw or 0,status.scale_factor or 1))
        if status.last_warning then ImGui.TextWrapped(status.last_warning) end
        ImGui.Separator();return
    end
    Theme.warning(string.format('GRAB MOVE ACTIVE / %d OBJECT%s',status.count or 0,(status.count or 0)==1 and '' or 'S'))
    ImGui.SameLine();Theme.muted(string.format('source %s | yaw %.1f | WB live %d | CET on commit %d',tostring(status.source or 'waiting'),tonumber(status.yaw_delta) or 0,status.live_world_builder or 0,status.deferred_cet or 0))
    local settings=self.app.model.data.settings.transform_grab;local changed
    settings.align_surface,changed=ImGui.Checkbox('Surface align##grab_header',status.align_surface==true);if changed then self.app:mark_dirty();session:configure({align_surface=settings.align_surface}) end
    ImGui.SameLine();settings.snap_position,changed=ImGui.Checkbox('Grid snap##grab_header',status.snap_position==true);if changed then self.app:mark_dirty();session:configure({snap_position=settings.snap_position}) end
    ImGui.SameLine();ImGui.PushItemWidth(90);settings.distance,changed=ImGui.InputFloat('Distance##grab_header',tonumber(status.distance) or 12,0.5,2,'%.1f');ImGui.PopItemWidth();if changed then settings.distance=math.max(0.25,settings.distance);self.app:mark_dirty();session:configure({distance=settings.distance}) end
    local angle=tonumber(self.app.model.data.settings.snapping.angle) or 5
    ImGui.SameLine();if Theme.action_button('YAW -##grab_header',70,27) then session:rotate(-angle) end
    ImGui.SameLine();if Theme.action_button('YAW +##grab_header',70,27) then session:rotate(angle) end
    ImGui.SameLine();if Theme.primary_button('COMMIT MOVE##grab_header',125,29) then local result,err=session:commit();self:notify(err or (result and 'Grab Move committed' or 'Commit failed')) end
    ImGui.SameLine();if Theme.danger_button('CANCEL MOVE##grab_header',115,29) then local result,err=session:cancel();self:notify(err or (result and 'Grab Move cancelled' or 'Cancel failed')) end
    if status.last_warning then ImGui.TextWrapped(status.last_warning) end
    ImGui.Separator()
end

function Editor:draw_stamp_session()
    local session=self.app.stamp_session;local status=session and session:status() or {active=false}
    if not status.active then return end
    Theme.warning(string.format('STAMP STROKE ACTIVE / %d OBJECT%s',status.count or 0,(status.count or 0)==1 and '' or 'S'))
    ImGui.SameLine();Theme.muted(string.format('%s | spacing %.2f m | one undo when committed',tostring(status.asset_name or status.asset_id or 'Asset'),tonumber(status.spacing) or 0))
    if Theme.action_button('STAMP NOW##stroke_header',112,29) then
        local result,err=self.app.placement:stamp_once(status.premise_id,status.room_id);self:notify(err or (result and 'Object added to stroke' or 'Stamp failed'))
    end
    ImGui.SameLine();if Theme.primary_button('COMMIT STROKE##stroke_header',132,29) then local result,err=session:commit();self:notify(err or (result and ('Committed '..tostring(result.count)..' stamped object(s)') or 'Commit failed')) end
    ImGui.SameLine();if Theme.danger_button('CANCEL STROKE##stroke_header',128,29) then local result,err=session:cancel();self:notify(err or (result and 'Stamp stroke cancelled' or 'Cancel failed')) end
    if status.last_error then ImGui.TextWrapped(status.last_error) end
    Theme.muted('Move the live preview with the crosshair, then stamp again. Closing CET cancels the uncommitted stroke.')
    ImGui.Separator()
end

function Editor:draw_header()
    local app=self.app;local project=app.model.data.project;local placement=app.placement:status();local shell=placement.runtime_shell or {}
    Theme.accent('LOCATION STUDIO');ImGui.SameLine();Theme.muted(' / '..tostring(project.name or 'Untitled')..' / v'..app.version)
    ImGui.Separator()
    Theme.pill(app.game:is_ready() and 'GAME ONLINE' or 'GAME OFFLINE',app.game:is_ready() and 'good' or 'bad')
    ImGui.SameLine();Theme.pill(placement.supported and 'ENTITY SPAWN READY' or 'ENTITY SPAWN OFF',placement.supported and 'good' or 'bad')
    ImGui.SameLine();Theme.pill(shell.available and 'GAME-ASSET ROOMS READY' or 'ROOM RUNTIME OFF',shell.available and 'good' or 'bad')
    local entities=placement.entities or {}
    Theme.muted(string.format('Entities: %d confirmed / %d pending / %d failed | Room pieces: %d submitted',entities.confirmed or 0,entities.pending or 0,(entities.failed or 0)+(entities.missing or 0),placement.shell_spawned or 0))
    local sync=app:check_runtime_sync(false)
    if sync.has_changes then
        local changes=(sync.counts.remove or 0)+(sync.counts.update or 0)+(sync.counts.missing or 0)
        Theme.warning(string.format('RUNTIME OUT OF SYNC · %d change(s)',changes));ImGui.SameLine()
        if Theme.primary_button('SYNC RUNTIME##header',145,28) then
            local result,err=app:sync_runtime()
            self:notify(err or (result and string.format('Runtime synced · %d spawned · %d updated · %d removed',result.spawned or 0,result.updated,result.removed) or 'Runtime sync failed'))
        end
        for _,item in ipairs(sync.items or {}) do if item.action=='remove' or item.action=='update' or item.action=='spawn' then ImGui.TextDisabled(string.format('  %s: %s (%s)',item.action,item.name,item.backend or 'tracked entity')) end end
    elseif #((sync.items) or {})>0 then
        Theme.muted('Runtime comparison includes unverified tracked entity state; no safe automatic mismatch was found.')
    end
    local scene_status=app.scenes and app.scenes:status() or {};if scene_status.live_scene_id then ImGui.SameLine();Theme.pill('LIVE SCENE: '..tostring(scene_status.live_scene_name),'good') end
    if app.dirty then ImGui.SameLine();Theme.warning('UNSAVED') end
    if self.toast then
        ImGui.TextWrapped(self.toast)
        if ImGui.SmallButton('DISMISS MESSAGE') then self.toast=nil end
    end
    if placement.last_error then ImGui.TextWrapped('Runtime: '..tostring(placement.last_error)) end
    local plan_status=app.authoring_plans and app.authoring_plans:status() or {}
    if plan_status.recovery_required then
        Theme.bad('AUTHORING PLAN RECOVERY REQUIRED');ImGui.SameLine();Theme.muted('save/export/history are paused')
        if Theme.primary_button('RETRY ROLLBACK##header',150,27) then local result,err=app.authoring_plans:retry_rollback();self:notify(result and 'Rollback completed.' or err) end
        ImGui.SameLine();if Theme.danger_button('KEEP PARTIAL##header',130,27) then local result,err=app.authoring_plans:keep_partial();self:notify(result and 'Partial result kept as one undo.' or err) end
    end
    ImGui.Separator()
    self:draw_stamp_session()
    self:draw_transform_session()
end

local SIMPLE_NAV={{id='HOME',label='BUILD'},{id='LIBRARY',label='ASSETS'},{id='SCENE',label='SCENE'},{id='HELP',label='HELP + START'}}

function Editor:draw_simple_sidebar(height)
    local app=self.app;local ws=app.model.data.settings.workspace
    Theme.kicker('WORKSPACE');ImGui.Spacing()
    for _,item in ipairs(SIMPLE_NAV) do
        if Theme.nav_button(item.label,ws.panel==item.id,154,40) then ws.panel=item.id;app:mark_dirty() end
        ImGui.Spacing()
    end
    ImGui.Separator();ImGui.Spacing()
    Theme.kicker('PROJECT')
    Theme.muted(string.format('%d rooms',#(app.model.data.rooms or {})))
    Theme.muted(string.format('%d placed objects',#(app.model.data.objects or {})))
    Theme.muted(string.format('%d library assets',#(app.model.data.assets or {})))
    ImGui.Spacing()
    if Theme.action_button('SAVE PROJECT',154,32) then local ok,err=app:save(true);self:notify(ok and 'Project saved' or err) end
    if Theme.action_button('SAVE DEBUG REPORT',154,32) then
        local path,err
        if app.diagnostics then path,err=app.diagnostics:write_support_report() else err='Diagnostics module unavailable; send logs/locationstudio.log.' end
        self:notify(path and ('Send this file: '..path) or ('Report failed: '..tostring(err)))
    end

    -- Keep technical/editor tooling out of the default workflow. The single switch
    -- below is the only doorway to the legacy advanced panels.
    ImGui.Spacing();ImGui.Separator();ImGui.Spacing()
    local advanced=false;advanced=select(1,ImGui.Checkbox('Advanced Tools',advanced))
    if advanced then ws.beginner_mode=false;ws.panel='BUILD';app:mark_dirty() end
    Theme.muted('Raw templates, cameras, volumes, exports, MCP, diagnostics and transform utilities.')
end

function Editor:draw_simple_scene(center_w,body_h)
    self:child('##simple_scene_director',0,205,function() self.scene_director:draw() end)
    body_h=math.max(260,body_h-213)
    if center_w<1150 then
        -- Keep the Inspector reachable on laptop-sized screens.
        self:child('##simple_scene_tree',235,body_h,function() self.hierarchy:draw() end)
        ImGui.SameLine();self:child('##simple_scene_detail',0,body_h,function()
            if Theme.nav_button('INSPECTOR',self.compact_scene~='overview',125,28) then self.compact_scene='inspector' end
            ImGui.SameLine();if Theme.nav_button('OVERVIEW',self.compact_scene=='overview',125,28) then self.compact_scene='overview' end
            ImGui.Separator()
            if self.compact_scene=='overview' then self.viewport.canvas_h=math.max(180,body_h-100);self.viewport:draw() else self.inspector:draw() end
        end)
        return
    end
    local hierarchy_w=math.max(230,math.min(290,center_w*0.28))
    local inspector_w=math.max(275,math.min(330,center_w*0.30))
    local viewport_w=math.max(360,center_w-hierarchy_w-inspector_w-16)
    self:child('##simple_scene_tree',hierarchy_w,body_h,function() self.hierarchy:draw() end)
    ImGui.SameLine();self:child('##simple_scene_view',viewport_w,body_h,function()
        Theme.section('SCENE','what exists in the current location')
        self.viewport.canvas_h=math.max(250,body_h-72);self.viewport:draw()
    end)
    ImGui.SameLine();self:child('##simple_scene_inspector',inspector_w,body_h,function() self.inspector:draw() end)
end

function Editor:draw_simple_workspace()
    local app=self.app;local ws=app.model.data.settings.workspace
    local avail_x,avail_y=xy(ImGui.GetContentRegionAvail());avail_x=tonumber(avail_x) or 1450;avail_y=tonumber(avail_y) or 760
    local side=178;local main=math.max(640,avail_x-side-8)
    self:child('##simple_nav',side,avail_y,function() self:draw_simple_sidebar(avail_y) end)
    ImGui.SameLine();self:child('##simple_main',main,avail_y,function()
        if ws.panel=='LIBRARY' then
            Theme.section('ASSET LIBRARY','preview first, place second')
            self.browser:assets()
        elseif ws.panel=='SCENE' then
            self:draw_simple_scene(main-20,avail_y-20)
        elseif ws.panel=='HELP' then
            self.help:draw()
        else
            self.home:draw()
        end
    end)
end

-- Advanced mode preserves all specialist tools, but it is intentionally not the
-- default UI. This lets experienced authors keep the existing deep controls
-- without forcing new users through them.
function Editor:advanced_panel_button(panel,width)
    local ws=self.app.model.data.settings.workspace;local selected=(ws.panel or 'BUILD')==panel
    if Theme.nav_button(panel,selected,width or 88,28) then ws.panel=panel;self.app:mark_dirty() end
end

function Editor:draw_advanced_toolbar()
    local app=self.app;local ws=app.model.data.settings.workspace
    if Theme.action_button('SIMPLE UI',104,30) then ws.beginner_mode=true;ws.panel='HOME';app:mark_dirty() end
    ImGui.SameLine();if ImGui.Button('UNDO',72,30) then local result,err=app.actions:history('undo');self:notify(err or (result and 'Undo' or 'Nothing to undo')) end
    ImGui.SameLine();if ImGui.Button('REDO',72,30) then local result,err=app.actions:history('redo');self:notify(err or (result and 'Redo' or 'Nothing to redo')) end
    ImGui.SameLine();if ImGui.Button('SAVE',72,30) then local ok,err=app:save(true);self:notify(ok and 'Project saved' or err) end
    local changed;ImGui.SameLine();ws.live_preview,changed=ImGui.Checkbox('Live preview',ws.live_preview);if changed then app:mark_dirty() end
end

function Editor:draw_advanced_center(body)
    local ws=self.app.model.data.settings.workspace
    Theme.section('ADVANCED TOOLS','specialist authoring')
    self:advanced_panel_button('BUILD',86);ImGui.SameLine();self:advanced_panel_button('SPATIAL',92);ImGui.SameLine();self:advanced_panel_button('TOOLS',86);ImGui.SameLine();self:advanced_panel_button('SCENE',86);ImGui.SameLine();self:advanced_panel_button('LIBRARY',96);ImGui.SameLine();self:advanced_panel_button('HELP',78)
    ImGui.Separator()
    if ws.panel=='BUILD' then self.premises:draw()
    elseif ws.panel=='SPATIAL' then self.spatial:draw()
    elseif ws.panel=='TOOLS' then self.tools:draw()
    elseif ws.panel=='LIBRARY' then self.browser:assets()
    elseif ws.panel=='HELP' then self.help:draw()
    elseif ws.panel=='SCENE' then self.scene_director:draw();ImGui.Separator();self.viewport.canvas_h=math.max(220,body-285);self.viewport:draw()
    else self.viewport.canvas_h=math.max(250,body-80);self.viewport:draw() end
end

function Editor:draw_advanced_workspace()
    local app=self.app;local ws=app.model.data.settings.workspace
    local avail_x,avail_y=xy(ImGui.GetContentRegionAvail());avail_x=tonumber(avail_x) or 1450;avail_y=tonumber(avail_y) or 720
    local bottom=math.max(150,math.min(ws.bottom_height or 210,avail_y*0.30));local body=math.max(320,avail_y-bottom-8)
    local left=math.max(220,ws.hierarchy_width or 280);local right=math.max(280,ws.inspector_width or 340);local center=math.max(430,avail_x-left-right-16)
    self:child('##advanced_tree',left,body,function() self.hierarchy:draw() end)
    ImGui.SameLine();self:child('##advanced_main',center,body,function() self:draw_advanced_center(body) end)
    ImGui.SameLine();self:child('##advanced_inspector',right,body,function() self.inspector:draw() end)
    self:child('##advanced_bottom',0,bottom,function() self.browser:draw() end)
end

function Editor:draw()
    local app=self.app;local color_count,var_count=Theme.push()
    if app.force_ui_recenter then ImGui.SetNextWindowSize(1180,760) else ImGui.SetNextWindowSize(1180,760,ImGuiCond.FirstUseEver) end
    if type(ImGui.SetNextWindowPos)=='function' and app.force_ui_recenter then
        -- Only used as a recovery path when the window was previously hidden/off-screen.
        -- CET accepts screen-space coordinates here; a conservative top-left position
        -- is safer than assuming a specific monitor resolution.
        pcall(ImGui.SetNextWindowPos,40,40)
        app.force_ui_recenter=false
    end
    local begun=false
    local ok,err=xpcall(function()
        -- Use the flags overload (number) instead of the closable-window overload.
        -- The editor is tied to the CET overlay, so there is no persisted X/close state
        -- that can silently suppress every future onDraw call.
        local visible=ImGui.Begin('Location Studio##LocationStudioMain',0);begun=true
        if visible~=false then
            self:draw_header()
            if app.model.data.settings.workspace.beginner_mode~=false then self:draw_simple_workspace() else self:draw_advanced_toolbar();ImGui.Separator();self:draw_advanced_workspace() end
        end
    end,traceback)
    if begun then ImGui.End() end
    Theme.pop(color_count,var_count)
    if not ok then error(err,0) end
end

return Editor
