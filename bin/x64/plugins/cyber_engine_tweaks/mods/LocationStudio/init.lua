local Logger=require('modules/logger')
local boot_logger=Logger.new('logs/locationstudio.log',{level='DEBUG',max_bytes=4194304,max_memory=1800})

local function safe_require(name)
    local ok,result=pcall(require,name)
    if not ok then boot_logger:fatal('require:'..name,result);return nil end
    boot_logger:debug('require:'..name,'loaded');return result
end

local Util=safe_require('modules/util')
local Storage=safe_require('modules/storage')
local GameFacade=safe_require('modules/game')
local Integrations=safe_require('modules/integrations')
local WorldBuilder=safe_require('modules/world_builder')
local Bridge=safe_require('modules/bridge')
local Builder=safe_require('modules/builder')
local RuntimeShell=safe_require('modules/runtime_shell')
local RuntimeState=safe_require('modules/runtime_state')
local Placement=safe_require('modules/placement')
local Authoring=safe_require('modules/authoring')
local Markers=safe_require('modules/markers')
local Selection=safe_require('modules/selection')
local ViewportTools=safe_require('modules/viewport_tools')
local TransformSession=safe_require('modules/transform_session')
local StampSession=safe_require('modules/stamp_session')
local Scenes=safe_require('modules/scenes')
local Assemblies=safe_require('modules/assemblies')
local EntTools=safe_require('modules/ent_tools')
local QuickStart=safe_require('modules/quickstart')
local Thumbnails=safe_require('modules/thumbnails')
local Actions=safe_require('modules/actions')
local Lighting=safe_require('modules/lighting')
local MeshAppearance=safe_require('modules/mesh_appearance')
local AmbientAudio=safe_require('modules/ambient_audio')
local AuthoringPlans=safe_require('modules/authoring_plans')
local Diagnostics=safe_require('modules/diagnostics')
local RhtInspector=safe_require('modules/rht_inspector')
local VanillaRemoval=safe_require('modules/vanilla_removal')
local LiveTools=safe_require('modules/live_tools')
local Navigation=safe_require('modules/navigation')
local DeviceLogic=safe_require('modules/device_logic')
local QuestForgeSync=safe_require('modules/questforge_sync')
local QuestSimulator=safe_require('modules/quest_simulator')
local WorldStates=safe_require('modules/world_states')
local Vfx=safe_require('modules/vfx')
local Environment=safe_require('modules/environment')
local ScreenshotMode=safe_require('modules/screenshot_mode')
local BuildExport=safe_require('modules/build_export')
local WbImport=safe_require('modules/wb_import')
local AssetBounds=safe_require('modules/asset_bounds')
local WorldBuilderGenerators=safe_require('modules/world_builder_generators')
local ProjectBrowser=safe_require('modules/project_browser')
local PropValidators=safe_require('modules/prop_validators')
local RoomFrames=safe_require('modules/room_frames')
local Checkpoints=safe_require('modules/checkpoints')
local Editor=safe_require('ui/editor')

local LocationStudio={
    version='0.59.0',ready=false,diagnostic_ready=true,init_failed=nil,ui_failed=nil,
    overlay_open=false,editor_visible=true,dirty=false,dirty_since=0,last_autosave=0,last_bridge_poll=0,
    selected_location_id=nil,selected_route_id=nil,selected_premise_id=nil,selected_room_id=nil,
    selected_object_id=nil,selected_volume_id=nil,selected_camera_id=nil,selected_scene_id=nil,editing_scene_id=nil,live_scene_id=nil,selected_asset_id=nil,last_asset_id=nil,selected_item_kind=nil,
    logger=boot_logger,util=Util,module_errors={},
    config={window_open=true,autosave_interval=2.0,bridge_poll_interval=0.15,status_interval=1.0},
}

local REQUIRED={util=Util,storage=Storage,game=GameFacade,integrations=Integrations,world_builder_module=WorldBuilder,lighting=Lighting,mesh_appearance=MeshAppearance,ambient_audio=AmbientAudio,bridge=Bridge,builder=Builder,runtime_shell=RuntimeShell,runtime_state=RuntimeState,placement=Placement,authoring=Authoring,markers=Markers,selection=Selection,viewport_tools=ViewportTools,transform_session=TransformSession,stamp_session=StampSession,scenes=Scenes,assemblies=Assemblies,ent_tools=EntTools,quickstart=QuickStart,thumbnails=Thumbnails,actions=Actions,authoring_plans=AuthoringPlans,asset_bounds=AssetBounds,prop_validators=PropValidators,room_frames=RoomFrames,world_builder_generators=WorldBuilderGenerators,project_browser=ProjectBrowser,checkpoints=Checkpoints,device_logic=DeviceLogic,questforge_sync=QuestForgeSync,quest_simulator=QuestSimulator,world_states=WorldStates}
for name,module in pairs(REQUIRED) do if not module then LocationStudio.module_errors[name]='module failed to load' end end

function LocationStudio:mark_dirty()
    local was_dirty=self.dirty
    self.dirty=true;self.dirty_since=os.clock()
    if not was_dirty then self.logger:debug('project','marked_dirty') end
end

function LocationStudio:save(force)
    if not self.model or not self.storage then return false,'model not initialized' end
    if self.transform_session and self.transform_session:is_active() then return false,'Commit or cancel the active transform session before saving.' end
    if self.stamp_session and self.stamp_session:is_active() then return false,'Commit or cancel the active stamp stroke before saving.' end
    if self.authoring_plans and self.authoring_plans:status().recovery_required then return false,'Authoring-plan rollback needs attention. Retry rollback or keep the partial result before saving.' end
    if not force and not self.dirty then return true end
    local ok,err=self.storage:save_model(self.model)
    if ok then self.dirty=false;self.last_autosave=os.clock();self.logger:info('project','saved',{forced=force==true})
    else self.logger:error('project','save_failed',{error=err}) end
    return ok,err
end

function LocationStudio:export(format,custom_path)
    if self.transform_session and self.transform_session:is_active() then return false,'Commit or cancel the active transform session before exporting.' end
    if self.stamp_session and self.stamp_session:is_active() then return false,'Commit or cancel the active stamp stroke before exporting.' end
    if self.authoring_plans and self.authoring_plans:status().recovery_required then return false,'Authoring-plan rollback needs attention. Retry rollback or keep the partial result before exporting.' end
    format=string.lower(format or 'json');local stamp=os.date('%Y%m%d_%H%M%S');local path=custom_path
    if not path or path=='' then local ext=format=='lua' and 'lua' or format;path='exports/locationstudio_'..stamp..'.'..ext end
    local ok,err
    if format=='json' then ok,err=self.storage:export_json(self.model,path)
    elseif format=='csv' then ok,err=self.storage:export_csv(self.model,path)
    elseif format=='lua' then ok,err=self.storage:export_lua(self.model,path)
    elseif format=='worldbuilder' or format=='world_builder' then if not custom_path or custom_path=='' then path='exports/locationstudio_'..stamp..'_worldbuilder.json' end;ok,err=self.storage:export_world_builder(self.model,path)
    elseif format=='questforge' or format=='quest_forge' then if not custom_path or custom_path=='' then path='exports/locationstudio_'..stamp..'_questforge.json' end;ok,err=self.storage:export_questforge(self.model,path)
    else return false,'unsupported export format: '..tostring(format) end
    if not ok then self.logger:error('export','failed',{format=format,error=err});return false,tostring(err) end
    self.logger:info('export','complete',{format=format,path=path});return true,path
end

function LocationStudio:reconcile_runtime()
    if not self.ready or not self.placement then return nil,'editor core is not ready' end
    if self.transform_session and self.transform_session:is_active() then return nil,'Commit or cancel the active transform session before reconciling runtime ownership.' end
    if self.stamp_session and self.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before reconciling runtime ownership.' end
    if self.authoring_plans and self.authoring_plans:status().recovery_required then return nil,'Authoring-plan rollback needs attention before reconciling runtime ownership.' end
    if self.integrations then self.integrations:refresh() end
    if self.world_builder then self.world_builder.class_cache={} end
    local result=self.placement:reconcile_runtime()
    if self.runtime_shell then self.runtime_shell:status(true) end
    return {reconciled=true,report=result,placement=self.placement:status()}
end

function LocationStudio:check_runtime_sync(force)
    if not self.placement then return {items={},counts={remove=0,update=0,missing=0},has_changes=false,checked=0} end
    local now=os.clock()
    if not force and now-(self.runtime_sync_checked_at or 0)<0.75 and self.runtime_sync_report then return self.runtime_sync_report end
    self.runtime_sync_checked_at=now
    local ok,report=pcall(function() return self.placement:compare_runtime() end)
    if ok then self.runtime_sync_report=report else
        self.runtime_sync_report={items={},counts={remove=0,update=0,missing=0},has_changes=false,checked=0,error=tostring(report)}
        self.logger:error('runtime_sync','comparison_failed',{error=tostring(report)})
    end
    return self.runtime_sync_report
end

function LocationStudio:sync_runtime()
    if not self.ready then return nil,'editor core is not ready' end
    local result,err=self.placement:sync_runtime()
    self:check_runtime_sync(true)
    if result then self.logger:info('runtime_sync','completed',{removed=result.removed,updated=result.updated,spawned=result.spawned,failed=#result.failed}) end
    return result,err
end

function LocationStudio:capture_quick()
    if not self.ready then return nil,'editor core is not ready' end
    local transform,err=self.game:capture_transform();if not transform then self.logger:error('hotkey:capture','capture_failed',{error=err});return nil,err end
    local loc=self.model:add_location({name=string.format('Quick Capture %03d',#self.model.data.locations+1),type='point',category='Quick Captures',tags={'quick'},transform=transform,metadata={source='hotkey:quick_capture'}})
    self.selection:set('location',loc.id);self:mark_dirty();self.logger:info('hotkey:capture','created',{id=loc.id,name=loc.name});return loc
end

local function construct(name,fn)
    LocationStudio.logger:debug('init:'..name,'start')
    local ok,result=LocationStudio.logger:guard('init:'..name,fn)
    if not ok then LocationStudio.init_failed='Initialization failed at '..name..': '..tostring(result);return nil end
    LocationStudio.logger:debug('init:'..name,'ready');return result
end

function LocationStudio:initialize()
    local persistent=RuntimeState and RuntimeState.get() or nil
    self.runtime_state=persistent
    self.logger:info('init','begin',{version=self.version,reload=persistent and persistent.preserved_at~=nil or false})
    for name in pairs(self.module_errors) do self.init_failed='Required module failed: '..name;self.logger:fatal('init',self.init_failed);return false end
    math.randomseed(os.time())
    self.storage=construct('storage',function() return Storage.new('data/project.json') end);if not self.storage then return false end
    self.config=construct('config',function() return self.storage:load_config() end) or self.config;self.config.window_open=true;self.editor_visible=true;self.force_ui_recenter=true
    self.model=construct('model',function() return self.storage:load_model() end);if not self.model then return false end
    self.game=construct('game',function() return GameFacade.new(self) end);if not self.game then return false end
    self.integrations=construct('integrations',function() local value=Integrations.new();value:refresh();return value end);if not self.integrations then return false end
    self.world_builder=construct('world_builder',function() return WorldBuilder.new(self) end);if not self.world_builder then return false end
    self.builder=construct('builder',function() return Builder.new(self) end);if not self.builder then return false end
    self.runtime_shell=construct('runtime_shell',function() return RuntimeShell.new(self,persistent) end);if not self.runtime_shell then return false end
    self.placement=construct('placement',function() return Placement.new(self,persistent) end);if not self.placement then return false end
    local reconciliation=construct('runtime_reconcile',function() return self.placement:reconcile_runtime() end)
    self.runtime_reconciliation=reconciliation
    local migration_ok,migration=self.logger:guard('init:room_kit_migration',function() return self.builder:migrate_legacy_room_shells() end)
    if migration_ok and migration and migration.migrated>0 then self.logger:info('init','legacy_rooms_converted',{rooms=migration.migrated})
    elseif not migration_ok then self.logger:error('init:room_kit_migration','migration_failed',{error=migration}) end
    self.authoring=construct('authoring',function() return Authoring.new(self) end);if not self.authoring then return false end
    self.markers=construct('markers',function() return Markers.new(self) end);if not self.markers then return false end
    self.selection=construct('selection',function() return Selection.new(self) end);if not self.selection then return false end
    self.viewport_tools=construct('viewport_tools',function() return ViewportTools.new(self) end);if not self.viewport_tools then return false end
    self.transform_session=construct('transform_session',function() return TransformSession.new(self) end);if not self.transform_session then return false end
    self.stamp_session=construct('stamp_session',function() return StampSession.new(self) end);if not self.stamp_session then return false end
    self.scenes=construct('scenes',function() return Scenes.new(self) end);if not self.scenes then return false end
    self.assemblies=construct('assemblies',function() return Assemblies.new(self) end);if not self.assemblies then return false end
    self.ent_tools=construct('ent_tools',function() return EntTools.new(self) end);if not self.ent_tools then return false end
    self.quickstart=construct('quickstart',function() return QuickStart.new(self) end);if not self.quickstart then return false end
    self.thumbnails=construct('thumbnails',function() return Thumbnails.new(self) end);if not self.thumbnails then return false end
    self.actions=construct('actions',function() return Actions.new(self) end);if not self.actions then return false end
    self.lighting=construct('lighting',function() return Lighting.new(self) end);if not self.lighting then return false end
    self.mesh_appearance=construct('mesh_appearance',function() return MeshAppearance.new(self) end);if not self.mesh_appearance then return false end
    self.ambient_audio=construct('ambient_audio',function() return AmbientAudio.new(self) end);if not self.ambient_audio then return false end
    self.authoring_plans=construct('authoring_plans',function() return AuthoringPlans.new(self) end);if not self.authoring_plans then return false end
    self.rht_inspector=RhtInspector and construct('rht_inspector',function() return RhtInspector.new(self) end) or nil
    self.vanilla_removal=VanillaRemoval and construct('vanilla_removal',function() return VanillaRemoval.new(self) end) or nil
    self.live_tools=LiveTools and construct('live_tools',function() return LiveTools.new(self) end) or nil
    self.navigation=Navigation and construct('navigation',function() return Navigation.new(self) end) or nil
    self.device_logic=DeviceLogic and construct('device_logic',function() return DeviceLogic.new(self) end) or nil
    self.questforge_sync=QuestForgeSync and construct('questforge_sync',function() return QuestForgeSync.new(self) end) or nil
    self.quest_simulator=QuestSimulator and construct('quest_simulator',function() return QuestSimulator.new(self) end) or nil
    self.world_states=WorldStates and construct('world_states',function() return WorldStates.new(self) end) or nil
    self.vfx=Vfx and construct('vfx',function() return Vfx.new(self) end) or nil
    self.environment=Environment and construct('environment',function() return Environment.new(self) end) or nil
    self.screenshot_mode=ScreenshotMode and construct('screenshot_mode',function() return ScreenshotMode.new(self) end) or nil
    self.build_export=BuildExport and construct('build_export',function() return BuildExport.new(self) end) or nil
    self.wb_import=WbImport and construct('wb_import',function() return WbImport.new(self) end) or nil
    self.asset_bounds=AssetBounds and construct('asset_bounds',function() return AssetBounds.new(self) end) or nil
    self.prop_validators=PropValidators and construct('prop_validators',function() return PropValidators.new(self) end) or nil
    self.room_frames=RoomFrames and construct('room_frames',function() return RoomFrames.new(self) end) or nil
    self.project_browser=ProjectBrowser and construct('project_browser',function() return ProjectBrowser.new(self) end) or nil
    self.checkpoints=construct('checkpoints',function() return Checkpoints.new(self) end);if not self.checkpoints then return false end
    self.world_builder_generators=WorldBuilderGenerators and construct('world_builder_generators',function() return WorldBuilderGenerators.new(self) end) or nil
    self.bridge=construct('bridge',function() return Bridge.new(self) end);if not self.bridge then return false end
    self.diagnostics=Diagnostics and construct('diagnostics',function() return Diagnostics.new(self) end) or nil
    self.ui=Editor and construct('ui',function() return Editor.new(self) end) or nil
    if not self.ui then self.ui_failed='Full editor failed to initialize; diagnostic window is active' end
    self.ready=true;self:check_runtime_sync(true);self.logger:info('init','core_ready',{ui=self.ui~=nil,reconciled=self.runtime_reconciliation~=nil,runtime_sync_pending=self.runtime_sync_report and self.runtime_sync_report.has_changes or false})
    if persistent then persistent.preserved_at=nil end
    if self.diagnostics then self.diagnostics:run() end
    self.logger:guard('bridge:initial_status',function() self.bridge:write_status() end)
    return true
end

function LocationStudio:draw_fallback()
    if not ImGui or type(ImGui.Begin)~='function' then return end
    local ok,err=pcall(function()
        local visible=ImGui.Begin('Location Studio Diagnostics##LocationStudioFallback',0)
        if visible~=false then
            ImGui.Text('LOCATION STUDIO v'..self.version..' - SAFE DIAGNOSTIC MODE');ImGui.Separator()
            if self.init_failed then ImGui.TextWrapped('INIT ERROR: '..self.init_failed) end
            if self.ui_failed then ImGui.TextWrapped('UI ERROR: '..self.ui_failed) end
            local status=self.logger:status();ImGui.TextWrapped('Log file: '..status.path);ImGui.TextWrapped('Diagnostics: logs/locationstudio-diagnostics.json')
            if ImGui.Button('RETRY FULL EDITOR',180,30) then self.ui_failed=nil;self.logger:info('ui','manual_retry') end
            ImGui.SameLine();if ImGui.Button('RUN DIAGNOSTICS',170,30) and self.diagnostics then self.diagnostics:run() end
            ImGui.SameLine();if ImGui.Button('CLEAR LOG',120,30) then self.logger:clear();self.logger:info('ui','clear_log_button') end
            ImGui.Separator();ImGui.Text('LAST 120 LOG LINES')
            ImGui.BeginChild('##diagnostic_log',0,0,true)
            for _,line in ipairs(self.logger:read_tail(120)) do ImGui.TextWrapped(line) end
            ImGui.EndChild()
        end
        ImGui.End()
    end)
    if not ok then self.logger:exception('ui:fallback',err) end
end

local function guarded_callback(scope,fn)
    return function(...)
        local ok,result=LocationStudio.logger:guard(scope,fn,...)
        if not ok and scope=='event:onInit' then LocationStudio.init_failed=tostring(result) end
        return result
    end
end

local function hotkey(id,label,fn)
    local ok,err=pcall(registerHotkey,id,label,guarded_callback('hotkey:'..id,fn))
    if not ok then LocationStudio.logger:error('hotkey:register','failed',{id=id,error=err}) else LocationStudio.logger:debug('hotkey:register','ready',{id=id}) end
end

hotkey('locationstudio_toggle_window','Location Studio - Toggle editor window',function() LocationStudio.editor_visible=not LocationStudio.editor_visible;LocationStudio.logger:info('hotkey:toggle','window',{open=LocationStudio.editor_visible}) end)
hotkey('locationstudio_quick_capture','Location Studio - Quick capture player location',function() LocationStudio:capture_quick() end)
hotkey('locationstudio_teleport_selected','Location Studio - Teleport to selected location',function()
    if not LocationStudio.ready or not LocationStudio.selected_location_id then return end;local loc=LocationStudio.model:get_location(LocationStudio.selected_location_id);if loc then local ok,err=LocationStudio.game:teleport(loc.transform);if not ok then LocationStudio.logger:error('hotkey:teleport','failed',{error=err}) end end
end)
hotkey('locationstudio_spawn_selected_object','Location Studio - Spawn selected construction object',function()
    if not LocationStudio.ready or not LocationStudio.selected_object_id then return end;local object=LocationStudio.model:get_object(LocationStudio.selected_object_id);if object then local _,err=LocationStudio.placement:refresh(object);if err then LocationStudio.logger:error('hotkey:spawn','failed',{error=err,id=object.id}) end end
end)
hotkey('locationstudio_place_selected_at_aim','Location Studio - Place selected object template at aim',function()
    if not LocationStudio.ready or not LocationStudio.selected_object_id or not LocationStudio.selected_premise_id then return end
    local source=LocationStudio.model:get_object(LocationStudio.selected_object_id);if not source then return end
    local result,err=LocationStudio.authoring:place_object_at_aim({premise_id=LocationStudio.selected_premise_id,room_id=LocationStudio.selected_room_id,name=source.name..' Aim Copy',kind=source.kind,template=source.template,appearance=source.appearance,layer=source.layer,distance=10,yaw=source.transform.rotation.yaw,spawn=true,source='hotkey:aim'})
    if result then LocationStudio.selection:set('object',result.object.id) else LocationStudio.logger:error('hotkey:aim','failed',{error=err}) end
end)
hotkey('locationstudio_move_selected_to_aim','Location Studio - Move selected item to crosshair',function() if LocationStudio.ready then LocationStudio.ent_tools:move_to_aim(nil,nil,12) end end)
hotkey('locationstudio_drop_selected_to_ground','Location Studio - Drop selected item to ground',function() if LocationStudio.ready then LocationStudio.ent_tools:drop_to_ground() end end)
hotkey('locationstudio_aim_selected_at_target','Location Studio - Aim selected item at stored target',function() if LocationStudio.ready then LocationStudio.ent_tools:aim_at_target() end end)
hotkey('locationstudio_refresh_markers','Location Studio - Refresh in-world markers',function() if LocationStudio.ready then LocationStudio.markers:refresh(LocationStudio.selected_premise_id) end end)
hotkey('locationstudio_pick_aimed_object','Location Studio - Select project object under crosshair',function()
    if not LocationStudio.ready then return end
    local _,err=LocationStudio.viewport_tools:pick_aimed_object({premise_only=true})
    if err then LocationStudio.logger:warn('hotkey:pick_aimed_object','result',{error=err}) end
end)
hotkey('locationstudio_stamp_preview','Location Studio - Stamp active asset preview once',function()
    if not LocationStudio.ready then return end
    local _,err=LocationStudio.placement:stamp_once(LocationStudio.selected_premise_id,LocationStudio.selected_room_id)
    if err then LocationStudio.logger:warn('hotkey:stamp_preview','result',{error=err}) end
end)
hotkey('locationstudio_stop_stamp','Location Studio - Commit active stamp stroke',function() if LocationStudio.ready then local _,err=LocationStudio.placement:stop_stamp();if err then LocationStudio.logger:warn('hotkey:commit_stamp','result',{error=err}) end end end)
hotkey('locationstudio_cancel_stamp','Location Studio - Cancel active stamp stroke',function() if LocationStudio.ready and LocationStudio.stamp_session:is_active() then local _,err=LocationStudio.stamp_session:cancel();if err then LocationStudio.logger:warn('hotkey:cancel_stamp','result',{error=err}) end end end)
hotkey('locationstudio_grab_selection','Location Studio - Grab selected object(s) with crosshair',function()
    if not LocationStudio.ready then return end;local _,err=LocationStudio.transform_session:start({})
    if err then LocationStudio.logger:warn('hotkey:grab_selection','result',{error=err}) end
end)
hotkey('locationstudio_edit_selection','Location Studio - Start reversible Transform Edit',function()
    if not LocationStudio.ready then return end
    local settings=LocationStudio.model.data.settings.transform_edit or {};local workspace=LocationStudio.model.data.settings.workspace or {};local count=LocationStudio.selection:object_count();local mode=(count>1 and workspace.multi_pivot_mode) or settings.pivot_mode
    local args={local_space=settings.local_space,pivot_mode=mode};if mode=='custom' then args.pivot={position=workspace.multi_custom_pivot or {x=0,y=0,z=0},rotation={yaw=0}} end
    local _,err=LocationStudio.transform_session:start_edit(args)
    if err then LocationStudio.logger:warn('hotkey:transform_edit','result',{error=err}) end
end)
hotkey('locationstudio_duplicate_edit','Location Studio - Duplicate selection and edit copies',function()
    if not LocationStudio.ready then return end
    local settings=LocationStudio.model.data.settings.transform_edit or {};local workspace=LocationStudio.model.data.settings.workspace or {};local count=LocationStudio.selection:object_count();local mode=(count>1 and workspace.multi_pivot_mode) or settings.pivot_mode
    local args={local_space=settings.local_space,pivot_mode=mode};if mode=='custom' then args.pivot={position=workspace.multi_custom_pivot or {x=0,y=0,z=0},rotation={yaw=0}} end
    local _,err=LocationStudio.transform_session:start_duplicate(args)
    if err then LocationStudio.logger:warn('hotkey:duplicate_edit','result',{error=err}) end
end)
hotkey('locationstudio_placement_edit','Location Studio - Place asset or copy selection at crosshair and edit',function()
    if not LocationStudio.ready then return end
    local kind=LocationStudio.selection.kind;local settings=LocationStudio.model.data.settings.asset_preview or {}
    local _,err=LocationStudio.transform_session:start_placement({kind=kind,id=LocationStudio.selection.id,mode='aim',distance=settings.distance or 10,surface_offset=settings.surface_offset,align_surface=settings.align_surface==true})
    if err then LocationStudio.logger:warn('hotkey:placement_edit','result',{error=err,kind=kind}) end
end)
hotkey('locationstudio_array_edit','Location Studio - Create a two-step array and edit copies',function()
    if not LocationStudio.ready then return end
    local grid=tonumber(LocationStudio.model.data.settings.snapping.grid) or 0.25
    local _,err=LocationStudio.transform_session:start_pattern({count=2,dx=grid,dy=0,dz=0,dyaw=0,pattern_local_space=true})
    if err then LocationStudio.logger:warn('hotkey:array_edit','result',{error=err}) end
end)
hotkey('locationstudio_mirror_x_edit','Location Studio - Mirror selection on location X and edit copies',function()
    if not LocationStudio.ready then return end;local _,err=LocationStudio.transform_session:start_mirror({axis='x'})
    if err then LocationStudio.logger:warn('hotkey:mirror_x_edit','result',{error=err}) end
end)
hotkey('locationstudio_mirror_y_edit','Location Studio - Mirror selection on location Y and edit copies',function()
    if not LocationStudio.ready then return end;local _,err=LocationStudio.transform_session:start_mirror({axis='y'})
    if err then LocationStudio.logger:warn('hotkey:mirror_y_edit','result',{error=err}) end
end)
hotkey('locationstudio_scatter_edit','Location Studio - Scatter selection or asset and edit copies',function()
    if not LocationStudio.ready then return end
    local settings=LocationStudio.model.data.settings.ent_tools or {}
    local _,err=LocationStudio.transform_session:start_scatter({
        count=settings.scatter_count or 6,radius=settings.scatter_radius or 2,distance=settings.scatter_distance or 12,
        seed=settings.scatter_seed or 2077,random_yaw=settings.scatter_random_yaw~=false,drop_to_ground=settings.scatter_drop~=false,
    })
    if err then LocationStudio.logger:warn('hotkey:scatter_edit','result',{error=err}) end
end)
hotkey('locationstudio_commit_grab','Location Studio - Commit active transform session',function() if LocationStudio.ready then local _,err=LocationStudio.transform_session:commit();if err then LocationStudio.logger:warn('hotkey:commit_transform','result',{error=err}) end end end)
hotkey('locationstudio_cancel_grab','Location Studio - Cancel active transform session',function() if LocationStudio.ready then local _,err=LocationStudio.transform_session:cancel();if err then LocationStudio.logger:warn('hotkey:cancel_transform','result',{error=err}) end end end)
hotkey('locationstudio_rotate_grab_left','Location Studio - Rotate grabbed selection left',function() if LocationStudio.ready and LocationStudio.transform_session:is_active() then LocationStudio.transform_session:rotate(-(tonumber(LocationStudio.model.data.settings.snapping.angle) or 5)) end end)
hotkey('locationstudio_rotate_grab_right','Location Studio - Rotate grabbed selection right',function() if LocationStudio.ready and LocationStudio.transform_session:is_active() then LocationStudio.transform_session:rotate(tonumber(LocationStudio.model.data.settings.snapping.angle) or 5) end end)
hotkey('locationstudio_run_authoring_plan','Location Studio - Run data/authoring-plan.json',function()
    if not LocationStudio.ready then return end
    local result,err=LocationStudio.authoring_plans:execute_file('data/authoring-plan.json',{save=true})
    if not result then LocationStudio.logger:error('hotkey:authoring_plan','failed',{error=err}) end
end)
hotkey('locationstudio_retry_plan_rollback','Location Studio - Retry failed authoring-plan rollback',function()
    if not LocationStudio.ready then return end
    local result,err=LocationStudio.authoring_plans:retry_rollback()
    if not result then LocationStudio.logger:error('hotkey:authoring_plan_rollback','failed',{error=err}) end
end)
hotkey('locationstudio_activate_editing_scene','Location Studio - Activate editing scene',function()
    if not LocationStudio.ready or not LocationStudio.editing_scene_id then return end
    local _,err=LocationStudio.scenes:activate(LocationStudio.editing_scene_id,true);if err then LocationStudio.logger:warn('hotkey:scene_activate','result',{error=err}) end
end)
hotkey('locationstudio_isolate_editing_scene','Location Studio - Isolate editing scene',function()
    if not LocationStudio.ready or not LocationStudio.editing_scene_id then return end
    local _,err=LocationStudio.scenes:isolate(LocationStudio.editing_scene_id);if err then LocationStudio.logger:warn('hotkey:scene_isolate','result',{error=err}) end
end)
hotkey('locationstudio_deactivate_live_scene','Location Studio - Deactivate live scene',function()
    if not LocationStudio.ready or not LocationStudio.live_scene_id then return end
    local _,err=LocationStudio.scenes:deactivate(LocationStudio.live_scene_id);if err then LocationStudio.logger:warn('hotkey:scene_deactivate','result',{error=err}) end
end)
hotkey('locationstudio_add_selection_to_scene','Location Studio - Add selection to editing scene',function()
    if not LocationStudio.ready or not LocationStudio.editing_scene_id then return end
    local _,err=LocationStudio.scenes:edit_current_selection(LocationStudio.editing_scene_id,'add');if err then LocationStudio.logger:warn('hotkey:scene_membership','result',{error=err}) end
end)

registerForEvent('onInit',guarded_callback('event:onInit',function() LocationStudio:initialize() end))
registerForEvent('onOverlayOpen',guarded_callback('event:onOverlayOpen',function() LocationStudio.overlay_open=true;LocationStudio.editor_visible=true;LocationStudio.config.window_open=true;LocationStudio.logger:debug('overlay','opened',{editor_visible=true}) end))
registerForEvent('onOverlayClose',guarded_callback('event:onOverlayClose',function()
    LocationStudio.overlay_open=false;if LocationStudio.ready then if LocationStudio.transform_session:is_active() then LocationStudio.transform_session:cancel() end;if LocationStudio.stamp_session:is_active() then LocationStudio.stamp_session:cancel() end;if not LocationStudio.stamp_session:is_active() then LocationStudio.placement:clear_preview() end;if LocationStudio.vfx then LocationStudio.vfx:preview_clear() end;LocationStudio:save(false);LocationStudio.storage:save_config(LocationStudio.config) end;LocationStudio.logger:debug('overlay','closed')
end))
registerForEvent('onUpdate',guarded_callback('event:onUpdate',function(delta)
    if not LocationStudio.ready then return end;local now=os.clock();local poll=tonumber(LocationStudio.config.bridge_poll_interval) or 0.15
    if now-LocationStudio.last_bridge_poll>=poll then LocationStudio.last_bridge_poll=now;LocationStudio.bridge:poll(now) end
    LocationStudio.placement:update(delta)
    if LocationStudio.world_states then LocationStudio.world_states:update(now) end
    if LocationStudio.vfx then LocationStudio.vfx:update_tick(delta) end
    if LocationStudio.environment then LocationStudio.environment:update_tick(delta) end
    if LocationStudio.live_tools then LocationStudio.live_tools:update(delta) end
    if LocationStudio.transform_session:is_active() then LocationStudio.transform_session:update(delta,false) end
    LocationStudio.placement:update_preview(false)
    LocationStudio.thumbnails:update(now)
    local interval=tonumber(LocationStudio.config.autosave_interval) or 2.0
    if LocationStudio.dirty and not LocationStudio.transform_session:is_active() and not LocationStudio.stamp_session:is_active() and not LocationStudio.authoring_plans:status().recovery_required and LocationStudio.model.data.settings.autosave~=false and now-LocationStudio.dirty_since>=interval then LocationStudio:save(false) end
end))
registerForEvent('onDraw',function()
    if not LocationStudio.overlay_open or not LocationStudio.editor_visible then return end
    if not LocationStudio.ready or not LocationStudio.ui or LocationStudio.ui_failed then LocationStudio:draw_fallback();return end
    if not LocationStudio._first_ui_draw_logged then
        LocationStudio._first_ui_draw_logged=true
        LocationStudio.logger:info('ui:draw','first_frame',{overlay_open=LocationStudio.overlay_open,editor_visible=LocationStudio.editor_visible})
    end
    local ok,err=LocationStudio.logger:guard('event:onDraw',function() LocationStudio.ui:draw() end)
    if not ok then
        LocationStudio.ui_failed=tostring(err)
        LocationStudio.logger:fatal('ui','full_editor_disabled_after_error',{error=tostring(err)})
        LocationStudio:draw_fallback()
    end
end)
registerForEvent('onShutdown',guarded_callback('event:onShutdown',function()
    -- CET invokes onShutdown for a script reload as well as for game exit. Do
    -- not remove live entities here: the process-lifetime runtime state keeps
    -- their IDs/World Builder handles available to the next module instance.
    LocationStudio.logger:info('shutdown','begin',{preserving_runtime=true})
    if LocationStudio.ready then
        if RuntimeState then RuntimeState.preserve() end
        if LocationStudio.thumbnails then LocationStudio.thumbnails:shutdown() end
        local saved,save_err=LocationStudio:save(true)
        if not saved then LocationStudio.logger:warn('shutdown','project_save_skipped',{error=save_err}) end
        LocationStudio.storage:save_config(LocationStudio.config)
        if LocationStudio.runtime_state then LocationStudio.runtime_state.preserved_at=RuntimeState and RuntimeState.get().preserved_at or nil end
    end
    LocationStudio.logger:info('shutdown','complete',{preserving_runtime=true})
end))

return LocationStudio
