local Diagnostics={}
Diagnostics.__index=Diagnostics

function Diagnostics.new(app) return setmetatable({app=app,last=nil},Diagnostics) end

local function exists(root,name) return type(root)=='table' and root[name]~=nil end

function Diagnostics:run()
    local app=self.app;local report={timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ'),version=app.version,capabilities={},modules={},project={},runtime={viewport_renderer='compat_widgets'}}
    report.environment={lua=_VERSION,jit=jit and jit.version or nil}
    if type(GetVersion)=='function' then local ok,value=pcall(GetVersion);if ok then report.environment.cet=tostring(value) end end
    local capabilities=report.capabilities
    capabilities.game=Game~=nil;capabilities.imgui=ImGui~=nil;capabilities.json=json~=nil
    capabilities.camera_system=Game~=nil and type(Game.GetCameraSystem)=='function';capabilities.spatial_queries=Game~=nil and type(Game.GetSpatialQueriesSystem)=='function'
    capabilities.entity_spawner=exEntitySpawner~=nil and type(exEntitySpawner.Spawn)=='function';capabilities.entity_despawner=exEntitySpawner~=nil and type(exEntitySpawner.Despawn)=='function'
    local shell_status=app.runtime_shell and app.runtime_shell:status(true) or {available=false,world_builder=false,reason='runtime shell unavailable'}
    capabilities.world_builder=shell_status.world_builder==true;capabilities.runtime_shell=shell_status.available==true
    capabilities.debug_traceback=debug~=nil and type(debug.traceback)=='function'
    for _,name in ipairs({'Begin','End','BeginChild','EndChild','BeginTabBar','EndTabBar','BeginTabItem','EndTabItem','Button','SmallButton','Text','TextDisabled','TextWrapped','TextColored','Separator','SameLine','Spacing','NewLine','BulletText','Selectable','InputText','InputTextWithHint','InputTextMultiline','InputFloat','InputFloat3','InputInt','Checkbox','SliderFloat','BeginCombo','EndCombo','BeginPopup','EndPopup','OpenPopup','CloseCurrentPopup','SetTooltip','SetNextWindowSize','SetNextWindowPos','PushStyleColor','PopStyleColor','PushStyleVar','PopStyleVar','PushItemWidth','PopItemWidth','GetContentRegionAvail','IsItemHovered'}) do
        capabilities['imgui_'..name]=exists(ImGui,name)
    end
    for _,name in ipairs({'storage','model','game','integrations','world_builder','builder','placement','authoring','markers','selection','viewport_tools','transform_session','stamp_session','scenes','assemblies','ent_tools','quickstart','runtime_shell','actions','authoring_plans','asset_bounds','project_browser','bridge','ui'}) do report.modules[name]=app[name]~=nil end
    if app.model and app.model.data then
        local d=app.model.data;local legacy,kit_meshes,colliders,detached,locked,disabled=0,0,0,0,0,0
        for _,object in ipairs(d.objects or {}) do
            local metadata=object.metadata or {}
            if metadata.generated and type(metadata.world_builder)~='table' then legacy=legacy+1 end
            if metadata.room_kit and not metadata.room_collision then kit_meshes=kit_meshes+1 end
            if metadata.room_collision then colliders=colliders+1 end
            if metadata.detached_from_room then detached=detached+1 end
            if metadata.room_kit and object.locked then locked=locked+1 end
            if metadata.room_kit and (object.enabled==false or object.visible==false) then disabled=disabled+1 end
        end
        local kit=(d.settings or {}).room_kit or {};local roles={}
        for _,name in ipairs({'floor','wall','ceiling','door','window'}) do local role=(kit.roles or {})[name] or {};roles[name]={path=role.path,native_x=role.native_x,native_y=role.native_y,native_z=role.native_z} end
        report.project={schema_version=d.schema_version,locations=#(d.locations or {}),premises=#(d.premises or {}),rooms=#(d.rooms or {}),objects=#(d.objects or {}),object_groups=#(d.object_groups or {}),object_prefabs=#(d.object_prefabs or {}),volumes=#(d.volumes or {}),cameras=#(d.cameras or {}),scenes=#(d.scenes or {}),assets=#(d.assets or {}),room_kit={preset=kit.preset,collision=kit.collision,roles=roles,mesh_objects=kit_meshes,collision_objects=colliders,detached_objects=detached,locked_objects=locked,disabled_objects=disabled,legacy_primitive_objects=legacy}}
    end
    report.logger=app.logger and app.logger:status() or {available=false};report.runtime.game_ready=app.game and app.game:is_ready() or false;report.runtime.spawner=app.placement and app.placement:status() or {};report.runtime.viewport_tools=app.viewport_tools and app.viewport_tools:status() or {};report.runtime.transform_session=app.transform_session and app.transform_session:status() or {active=false};report.runtime.stamp_session=app.stamp_session and app.stamp_session:status() or {active=false};report.runtime.scenes=app.scenes and app.scenes:status() or {};report.runtime.authoring_plans=app.authoring_plans and app.authoring_plans:status() or {};report.runtime.runtime_shell=shell_status;report.runtime.ui={overlay_open=app.overlay_open==true,editor_visible=app.editor_visible~=false,force_recenter=app.force_ui_recenter==true,first_draw_logged=app._first_ui_draw_logged==true};report.ready=app.ready;report.init_failed=app.init_failed;report.ui_failed=app.ui_failed
    if app.world_builder then
        local wb_status=app.world_builder:status();local cached={};local classes={}
        for key,values in pairs(app.world_builder.cache or {}) do cached[key]=#values end
        for _,key in ipairs({'entity_template','mesh_static','collision_shape'}) do
            local class,class_err=app.world_builder:class_for({world_builder={definition_key=key}})
            classes[key]={available=type(class)=='table' and type(class.new)=='function',error=class_err}
        end
        report.runtime.world_builder_catalog={status=wb_status,cached_counts=cached,class_probes=classes,last_query=app.world_builder.last_query,last_error=app.world_builder.last_error}
    end
    report.runtime.panel_errors=app.ui and app.ui.panel_errors or {}
    report.runtime.storage_error=app.storage and app.storage.last_error or nil
    local selection_ids={}
    if app.selection then for _,object in ipairs(app.selection:selected_objects()) do table.insert(selection_ids,object.id) end end
    report.runtime.selection=app.selection and {kind=app.selection.kind,id=app.selection.id,last_asset_id=app.last_asset_id,object_ids=selection_ids,object_count=#selection_ids,group_source=app.selection.group_source} or {}
    self.last=report
    if app.logger then
        for name,value in pairs(capabilities) do app.logger:info('diagnostics','capability',{name=name,available=value}) end
        app.logger:info('diagnostics','report_complete',report.project)
    end
    if app.util and app.util.json_write then
        local ok,err=app.util.json_write('logs/locationstudio-diagnostics.json',report)
        if not ok and app.logger then app.logger:error('diagnostics','report_write_failed',{error=err}) end
    end
    return report
end

function Diagnostics:write_support_report()
    local app=self.app
    local ok,report=pcall(function() return self:run() end)
    if not ok then report={version=app.version,diagnostic_error=tostring(report)} end
    local encoded_ok,encoded=pcall(json.encode,report)
    if not encoded_ok then encoded='Diagnostics encoding failed: '..tostring(encoded) end
    local lines={
        'LocationStudio support report / v'..tostring(app.version),
        'Includes diagnostics and recent logs. No project JSON or credentials are included.',
        'Logs may contain asset names, template paths, and transforms. Review before sharing.',
        '', 'DIAGNOSTICS',tostring(encoded),'','RECENT LOG',
    }
    if app.logger then for _,line in ipairs(app.logger:read_tail(600)) do table.insert(lines,line) end end
    local content=table.concat(lines,'\n')
    local path='logs/LocationStudio-v'..tostring(app.version)..'-support.txt'
    local saved,err=app.util.write_file(path,content)
    if not saved then return nil,err end
    -- Keep the historic filename current too, but return the versioned path so
    -- users can never mistake an older downloaded report for the active build.
    app.util.write_file('logs/LocationStudio-support.txt',content)
    return path
end

return Diagnostics
