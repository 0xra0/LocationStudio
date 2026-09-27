local Util = require('modules/util')

local Bridge = {}
Bridge.__index = Bridge

function Bridge.new(app)
    local self = setmetatable({}, Bridge)
    self.app = app
    self.command_path = 'bridge/command.json'
    self.response_path = 'bridge/response.json'
    self.status_path = 'bridge/status.json'
    self.last_command_id = nil
    self.last_status_write = 0
    return self
end

local function response(id, ok, result, err)
    return {
        id = id,
        ok = ok,
        result = result,
        error = err,
        timestamp = Util.now_iso(),
    }
end

function Bridge:write_response(data)
    Util.json_write(self.response_path, data)
end

function Bridge:write_status()
    local app = self.app
    local status = {
        name = 'LocationStudio',
        version = app.version,
        online = true,
        timestamp = Util.now_iso(),
        player = app.game:player_summary(),
        project = {
            name = app.model.data.project.name,
            location_count = #app.model.data.locations,
            route_count = #app.model.data.routes,
            premise_count = #app.model.data.premises,
            room_count = #app.model.data.rooms,
            object_count = #app.model.data.objects,
            object_group_count = #(app.model.data.object_groups or {}),
            object_prefab_count = #(app.model.data.object_prefabs or {}),
            volume_count = #app.model.data.volumes,
            camera_count = #app.model.data.cameras,
            cover_node_count = #(app.model.data.cover_nodes or {}),
            device_logic_graph_count = #(app.model.data.device_logic_graphs or {}),
            world_state_variant_count = #(app.model.data.world_state_variants or {}),
            environment_count = #(app.model.data.environments or {}),
            asset_count = #app.model.data.assets,
            scene_count = #(app.model.data.scenes or {}),
            dirty = app.dirty,
        },
        integrations = app.integrations:status(),
        placement = app.placement:status(),
        transform_session = app.transform_session and app.transform_session:status() or {active=false},
        stamp_session = app.stamp_session and app.stamp_session:status() or {active=false},
        scenes = app.scenes and app.scenes:status() or nil,
        vanilla_removal = app.vanilla_removal and app.vanilla_removal:status() or nil,
        authoring_plans = app.authoring_plans and app.authoring_plans:status() or nil,
        screenshot_mode = app.screenshot_mode and app.screenshot_mode:status() or {active=false},
        environment_preview = app.environment and app.environment.state.environment_preview and {active=true,environment_id=app.environment.state.environment_preview.environment_id,force=app.environment.state.environment_preview.force==true} or {active=false},
        markers = app.markers:status(),
        logger = app.logger and app.logger:status() or nil,
        init_failed = app.init_failed,
        ui_failed = app.ui_failed,
    }
    Util.json_write(self.status_path, status)
end

function Bridge:handle(command)
    local app = self.app
    local op = command.op
    local a = command.args or {}
    if app.logger then app.logger:info('bridge','command',{id=command.id,op=op}) end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then
        local allowed={ping=true,get_authoring_plan_status=true,get_scene_status=true,wb_find=true,wb_tree=true,wb_get=true,wb_refs=true,wb_frame_list=true,wb_frame_get=true,wb_frame_to_world=true,wb_world_to_frame=true,wb_bounds_info=true,wb_bounds_world_aabb=true,wb_bounds_overlap=true,wb_collisions=true,wb_clipcheck=true,wb_fixturecheck=true,wb_fitcheck=true,wb_compat_scan=true,wb_bounds_fit=true,wb_favorite_prepare=true,wb_prefab_render_status=true,retry_authoring_plan_rollback=true,keep_partial_authoring_plan=true,run_diagnostics=true,integration_status=true,rht_status=true,rht_crosshair=true,rht_scan=true,rht_node=true,vanilla_removal_status=true,list_vanilla_removals=true,get_history=true,build_export_status=true,walkability_check=true,cover_node_list=true,vfx_categories=true,vfx_search=true,vfx_list=true,vfx_preview_status=true,vfx_preview_clear=true,environment_weather_states=true,environment_list=true,environment_status=true,environment_restore=true,screenshot_mode_capabilities=true,screenshot_mode_status=true,screenshot_mode_unfreeze=true,screenshot_mode_restore=true,collision_presets=true,collision_list=true,collision_layers=true,collision_passability=true,collision_search_meshes=true,sector_report_load=true,sector_report_flags=true,performance_analyze=true,visibility_capabilities=true,visibility_list_occluders=true,visibility_pvs=true,visibility_hidden_meshes=true,layer_list=true}
        if not allowed[op] then return nil,'Authoring-plan rollback needs attention. Retry rollback or keep the partial result before running '..tostring(op)..'.' end
    end
    if app.transform_session and app.transform_session:is_active() then
        local allowed={ping=true,get_scene_status=true,wb_find=true,wb_tree=true,wb_get=true,wb_refs=true,wb_frame_list=true,wb_frame_get=true,wb_frame_to_world=true,wb_world_to_frame=true,wb_bounds_info=true,wb_bounds_world_aabb=true,wb_bounds_overlap=true,wb_collisions=true,wb_clipcheck=true,wb_fixturecheck=true,wb_fitcheck=true,wb_compat_scan=true,wb_bounds_fit=true,wb_favorite_prepare=true,wb_prefab_render_status=true,get_transform_grab_status=true,get_transform_session_status=true,configure_transform_grab=true,adjust_transform_edit=true,reset_transform_edit=true,commit_transform_grab=true,cancel_transform_grab=true,commit_transform_edit=true,cancel_transform_edit=true,aim_point=true,capture_player=true,capture_camera=true,integration_status=true,run_diagnostics=true,rht_status=true,rht_crosshair=true,rht_scan=true,rht_node=true,vanilla_removal_status=true,list_vanilla_removals=true,get_history=true,walkability_check=true,cover_node_list=true,vfx_categories=true,vfx_search=true,vfx_list=true,vfx_preview_status=true,vfx_preview_clear=true,environment_weather_states=true,environment_list=true,environment_status=true,environment_restore=true,screenshot_mode_capabilities=true,screenshot_mode_status=true,screenshot_mode_unfreeze=true,screenshot_mode_restore=true,collision_presets=true,collision_list=true,collision_layers=true,collision_passability=true,collision_search_meshes=true,sector_report_load=true,sector_report_flags=true,performance_analyze=true,visibility_capabilities=true,visibility_list_occluders=true,visibility_pvs=true,visibility_hidden_meshes=true,layer_list=true}
        if not allowed[op] then return nil,'Commit or cancel the active transform session before running '..tostring(op)..'.' end
    end
    if app.stamp_session and app.stamp_session:is_active() then
        local allowed={ping=true,get_scene_status=true,wb_find=true,wb_tree=true,wb_get=true,wb_refs=true,wb_frame_list=true,wb_frame_get=true,wb_frame_to_world=true,wb_world_to_frame=true,wb_bounds_info=true,wb_bounds_world_aabb=true,wb_bounds_overlap=true,wb_collisions=true,wb_clipcheck=true,wb_fixturecheck=true,wb_fitcheck=true,wb_compat_scan=true,wb_bounds_fit=true,wb_favorite_prepare=true,wb_prefab_render_status=true,get_stamp_stroke_status=true,stamp_preview=true,commit_stamp_stroke=true,cancel_stamp_stroke=true,clear_asset_preview=true,aim_point=true,capture_player=true,capture_camera=true,integration_status=true,run_diagnostics=true,rht_status=true,rht_crosshair=true,rht_scan=true,rht_node=true,vanilla_removal_status=true,list_vanilla_removals=true,get_history=true,walkability_check=true,cover_node_list=true,vfx_categories=true,vfx_search=true,vfx_list=true,vfx_preview_status=true,vfx_preview_clear=true,environment_weather_states=true,environment_list=true,environment_status=true,environment_restore=true,screenshot_mode_capabilities=true,screenshot_mode_status=true,screenshot_mode_unfreeze=true,screenshot_mode_restore=true,collision_presets=true,collision_list=true,collision_layers=true,collision_passability=true,collision_search_meshes=true,sector_report_load=true,sector_report_flags=true,performance_analyze=true,visibility_capabilities=true,visibility_list_occluders=true,visibility_pvs=true,visibility_hidden_meshes=true,layer_list=true}
        if not allowed[op] then return nil,'Commit or cancel the active stamp stroke before running '..tostring(op)..'.' end
    end

    if op == 'reload_runtime' then
        return app:reconcile_runtime()
    elseif op == 'get_authoring_plan_schema' then
        return app.authoring_plans:schema()
    elseif op == 'get_authoring_plan_examples' then
        return app.authoring_plans:examples()
    elseif op == 'validate_authoring_plan' then
        return app.authoring_plans:validate(a.plan or a)
    elseif op == 'execute_authoring_plan' then
        local result,err=app.authoring_plans:execute(a.plan or a,{save=a.save==true});if not result then return nil,err end;return result
    elseif op == 'validate_authoring_plan_file' then
        local plan,err=app.authoring_plans:load_file('data/authoring-plan.json');if not plan then return nil,err end;return app.authoring_plans:validate(plan)
    elseif op == 'execute_authoring_plan_file' then
        local result,err=app.authoring_plans:execute_file('data/authoring-plan.json',{save=a.save==true});if not result then return nil,err end;return result
    elseif op == 'get_authoring_plan_status' then
        return app.authoring_plans:status()
    elseif op == 'retry_authoring_plan_rollback' then
        local result,err=app.authoring_plans:retry_rollback();if not result then return nil,err end;return result
    elseif op == 'keep_partial_authoring_plan' then
        local result,err=app.authoring_plans:keep_partial();if not result then return nil,err end;return result
    elseif op == 'resolve_authoring_asset' then
        local asset,err=app.authoring_plans:resolve_asset(a.asset_id,a.query);if not asset then return nil,err end;return asset
    elseif op == 'list_scenes' then
        return app.model.data.scenes or {}
    elseif op == 'create_scene' then
        local result,err=app.scenes:create(a);if not result then return nil,err end;return result
    elseif op == 'update_scene' then
        local result,err=app.scenes:update(a.id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'delete_scene' then
        local result,err=app.scenes:delete(a.id);if not result then return nil,err end;return result
    elseif op == 'activate_scene' then
        local result,err=app.scenes:activate(a.id,a.spawn~=false);if not result then return nil,err end;return result
    elseif op == 'deactivate_scene' then
        local result,err=app.scenes:deactivate(a.id);if not result then return nil,err end;return result
    elseif op == 'isolate_scene' then
        local result,err=app.scenes:isolate(a.id);if not result then return nil,err end;return result
    elseif op == 'capture_scene_from_premise' then
        local result,err=app.scenes:capture_premise(a);if not result then return nil,err end;return result
    elseif op == 'edit_scene_members' then
        local result,err=app.scenes:edit_members(a.id,a);if not result then return nil,err end;return result
    elseif op == 'add_selection_to_scene' then
        local result,err=app.scenes:edit_current_selection(a.id,'add');if not result then return nil,err end;return result
    elseif op == 'remove_selection_from_scene' then
        local result,err=app.scenes:edit_current_selection(a.id,'remove');if not result then return nil,err end;return result
    elseif op == 'get_scene_status' then
        return app.scenes:status()
    elseif op == 'select_scene_objects' then
        local result,err=app.scenes:select_objects(a.id);if not result then return nil,err end;return result
    elseif op == 'ping' then
        return {pong=true, version=app.version}
    elseif op == 'run_lua' then
        -- Dev hook for the local MCP client: run a Lua chunk inside CET and return its result.
        -- The chunk gets 'app' (this mod) as its only argument, e.g. "return Game.GetPlayer():GetWorldPosition().x".
        local chunk,cerr=loadstring(tostring(a.code or ''),'=run_lua')
        if not chunk then return nil,'compile: '..tostring(cerr) end
        local ok,res=pcall(chunk,app)
        if not ok then return nil,'runtime: '..tostring(res) end
        if type(res)=='table' then return res end
        return {result=res~=nil and tostring(res) or nil}
    elseif op == 'npc_play_anim' or op == 'npc_stop_anim' or op == 'npc_stop_all_anims' or op == 'npc_anim_status' or op == 'npc_list' or op == 'raycast_batch' or op == 'floor_probe' or op == 'respawn_tagged' or op == 'camera_pitch' or op == 'npc_spawn_record' or op == 'npc_despawn_tag' or op == 'npc_preview_workspot' or op == 'npc_workspot_approach' or op == 'walkability_check' or op == 'cover_scan_live' then
        local lt=app.live_tools;if not lt then return nil,'live tools module failed to load' end
        local result,err
        if op == 'npc_play_anim' then result,err=lt:play(a)
        elseif op == 'npc_stop_anim' then result,err=lt:stop(a)
        elseif op == 'npc_stop_all_anims' then result,err=lt:stop_all()
        elseif op == 'npc_anim_status' then result,err=lt:status()
        elseif op == 'npc_list' then result,err=lt:list_npcs(a)
        elseif op == 'raycast_batch' then result,err=lt:raycast_batch(a)
        elseif op == 'floor_probe' then result,err=lt:floor_probe(a)
        elseif op == 'respawn_tagged' then result,err=lt:respawn_tagged(a)
        elseif op == 'npc_spawn_record' then result,err=lt:spawn_record(a)
        elseif op == 'npc_despawn_tag' then result,err=lt:despawn_tag(a)
        elseif op == 'npc_preview_workspot' then result,err=lt:preview_workspot(a)
        elseif op == 'npc_workspot_approach' then result,err=lt:workspot_approach(a)
        elseif op == 'walkability_check' then result,err=lt:walkability_check(a)
        elseif op == 'cover_scan_live' then result,err=lt:scan_cover_candidates(a)
        else result,err=lt:camera_pitch(a) end
        if not result then return nil,err end
        return result
    elseif op == 'call_system' then
        -- Dev hook: call a no-argument method on a scriptable system, e.g. re-run a mod's sync after
        -- RedHotTools hot-reloaded its redscript (a reload does not re-run OnAttach/OnRestored).
        local ok,res=pcall(function()
            local sys=Game.GetScriptableSystemsContainer():Get(a.system)
            if not sys then error('no scriptable system '..tostring(a.system)) end
            return sys[a.method](sys)
        end)
        if not ok then return nil,tostring(res) end
        return {called=a.system..'.'..a.method,result=res~=nil and tostring(res) or nil}
    elseif op == 'teleport_raw' then
        -- Used by the MCP hot_reload_archives tool to re-stream sectors after RedHotTools swaps an archive.
        local ok,err=app.game:teleport({position=a.position,rotation=a.rotation or {roll=0,pitch=0,yaw=0}})
        if not ok then return nil,err end
        return {teleported=true,position=a.position}
    elseif op == 'capture_player' then
        local t, err = app.game:capture_transform()
        if not t then return nil, err end
        return t
    elseif op == 'create_from_player' then
        local t, err = app.game:capture_transform()
        if not t then return nil, err end
        local loc = app.model:add_location({
            name = a.name or 'Captured Location', type = a.type or 'point',
            category = a.category or 'General', tags = a.tags or {}, notes = a.notes or '',
            radius = a.radius or 0.5, transform = t,
            metadata = {source='captured from live player transform',coordinates_verified=true}
        })
        app:mark_dirty()
        app.selection:set('location',loc.id)
        return loc
    elseif op == 'create_location' then
        local loc = app.model:add_location({
            name=a.name, type=a.type, category=a.category, tags=a.tags, notes=a.notes,
            radius=a.radius,
            transform={
                position={x=a.x, y=a.y, z=a.z, w=1},
                rotation={roll=a.roll or 0, pitch=a.pitch or 0, yaw=a.yaw or 0}
            },
            metadata=a.metadata or {source='mcp:create_location'}
        })
        app:mark_dirty()
        app.selection:set('location',loc.id)
        return loc
    elseif op == 'update_location' then
        local loc, err = app.model:update_location(a.id, a.patch or {})
        if not loc then return nil, err end
        app:mark_dirty()
        return loc
    elseif op == 'delete_location' then
        local ok, err = app.model:delete_location(a.id)
        if not ok then return nil, err end
        app:mark_dirty()
        if app.selection:is('location',a.id) then app.selection:clear() end
        return {deleted=true, id=a.id}
    elseif op == 'teleport' then
        local loc = app.model:get_location(a.id)
        if not loc then return nil, 'location not found' end
        local ok, err = app.game:teleport(loc.transform)
        if not ok then return nil, tostring(err) end
        return {teleported=true, id=loc.id, name=loc.name}
    elseif op == 'set_from_player' then
        local loc = app.model:get_location(a.id)
        if not loc then return nil, 'location not found' end
        local t, err = app.game:capture_transform()
        if not t then return nil, err end
        local metadata=app.util.deepcopy(loc.metadata or {});metadata.source='recaptured from live player transform';metadata.coordinates_verified=true
        local updated = app.model:update_location(a.id, {transform=t,metadata=metadata})
        app:mark_dirty()
        return updated
    elseif op == 'duplicate_location' then
        local loc, err = app.model:duplicate_location(a.id, a.name)
        if not loc then return nil, err end
        app:mark_dirty()
        return loc
    elseif op == 'create_relative' then
        local base = app.model:get_location(a.base_id)
        if not base then return nil, 'base location not found' end
        local p = base.transform.position
        local r = base.transform.rotation
        local loc = app.model:add_location({
            name=a.name or (base.name .. ' Offset'), type=a.type or base.type,
            category=a.category or base.category, tags=a.tags or base.tags, notes=a.notes or '',
            radius=a.radius or base.radius,
            transform={
                position={x=p.x+(a.dx or 0), y=p.y+(a.dy or 0), z=p.z+(a.dz or 0), w=1},
                rotation={roll=r.roll+(a.droll or 0), pitch=r.pitch+(a.dpitch or 0), yaw=r.yaw+(a.dyaw or 0)}
            },
            metadata={source='mcp:create_relative', base_id=base.id}
        })
        app:mark_dirty()
        return loc
    elseif op == 'add_route' then
        local route = app.model:add_route({name=a.name, kind=a.kind, location_ids=a.location_ids or {}, loop=a.loop, notes=a.notes})
        app:mark_dirty()
        return route
    elseif op == 'update_route' then
        local route, err = app.model:update_route(a.id, a.patch or {})
        if not route then return nil, err end
        app:mark_dirty()
        return route
    elseif op == 'npc_route_create' then
        return app.actions:create_npc_route(a)
    elseif op == 'npc_route_list' then
        local out={};for _,route in ipairs(app.model.data.npc_routes or {}) do if not a.npc_id or route.npc_id==a.npc_id then table.insert(out,route) end end;return out
    elseif op == 'npc_route_add_waypoint' then
        return app.actions:add_npc_route_waypoint(a)
    elseif op == 'npc_route_update_waypoint' then
        return app.actions:update_npc_route_waypoint(a)
    elseif op == 'npc_route_delete_waypoint' then
        return app.actions:delete_npc_route_waypoint(a)
    elseif op == 'npc_route_move_waypoint' then
        return app.actions:move_npc_route_waypoint(a)
    elseif op == 'npc_route_update' then
        return app.actions:update_npc_route(a)
    elseif op == 'npc_route_delete' then
        return app.actions:delete_npc_route(a.id)
    elseif op == 'cover_node_create' then
        return app.actions:create_cover_node(a)
    elseif op == 'cover_node_update' then
        return app.actions:update_cover_node(a)
    elseif op == 'cover_node_delete' then
        return app.actions:delete_cover_node(a.id)
    elseif op == 'cover_node_list' then
        local out={};for _,node in ipairs(app.model.data.cover_nodes or {}) do if not a.premise_id or node.premise_id==a.premise_id then out[#out+1]=node end end;return {count=#out,cover_nodes=out}
    elseif op == 'navigation_graph_import' then
        if not app.navigation then return nil,'navigation module failed to load' end
        return app.navigation:import_graph(a.graph)
    elseif op == 'navigation_graph_list' then
        local out={};for _,g in ipairs(app.navigation and app.navigation:list() or {}) do out[#out+1]={id=g.id,name=g.name,source=g.source,source_format=g.source_format,node_count=#(g.nodes or {}),edge_count=#(g.edges or {}),polygon_count=#(g.polygons or {}),coordinate_space=g.coordinate_space,native_redengine=false} end
        return {graphs=out,native_redengine_query=false,note='Imported graph metadata only; use an explicit graph check for route details.'}
    elseif op == 'navigation_graph_check' then
        if not app.navigation then return nil,'navigation module failed to load' end
        return app.navigation:query(a)
    elseif op == 'navigation_workspot_report' then
        if not app.navigation then return nil,'navigation module failed to load' end
        return app.navigation:workspot_report(a)
    elseif op == 'device_logic_graph_create' then return app.device_logic:create(a)
    elseif op == 'device_logic_graph_list' then return {graphs=app.device_logic:list(),native_runtime_execution=false}
    elseif op == 'device_logic_graph_get' then local graph=app.device_logic:get(a.graph_id);if not graph then return nil,'device logic graph not found' end;return graph
    elseif op == 'device_logic_graph_delete' then return app.device_logic:delete_graph(a.graph_id)
    elseif op == 'device_logic_node_add' then return app.device_logic:add_node(a)
    elseif op == 'device_logic_node_update' then return app.device_logic:update_node(a)
    elseif op == 'device_logic_node_delete' then return app.device_logic:delete_node(a.graph_id,a.node_id)
    elseif op == 'device_logic_link_add' then return app.device_logic:add_link(a)
    elseif op == 'device_logic_link_delete' then return app.device_logic:delete_link(a.graph_id,a.link_id)
    elseif op == 'device_logic_validate' then return app.device_logic:validate(a.graph_id)
    elseif op == 'cover_scan' then
        return app.actions:scan_cover_candidates(a)
    elseif op == 'combat_encounter_create' then
        return app.actions:create_combat_encounter(a)
    elseif op == 'combat_encounter_list' then
        local out={};for _,encounter in ipairs(app.model.data.combat_encounters or {}) do if not a.premise_id or encounter.premise_id==a.premise_id then table.insert(out,encounter) end end;return out
    elseif op == 'combat_encounter_update' then
        return app.actions:update_combat_encounter(a)
    elseif op == 'combat_group_create' then
        return app.actions:create_encounter_group(a)
    elseif op == 'combat_group_update' then
        return app.actions:update_encounter_group(a)
    elseif op == 'combat_group_delete' then
        return app.actions:delete_encounter_group(a)
    elseif op == 'combat_wave_create' then
        return app.actions:create_encounter_wave(a)
    elseif op == 'combat_wave_update' then
        return app.actions:update_encounter_wave(a)
    elseif op == 'combat_wave_delete' then
        return app.actions:delete_encounter_wave(a)
    elseif op == 'combat_faction_relation' then
        return app.actions:set_encounter_faction_relation(a)
    elseif op == 'combat_encounter_test' then
        return app.actions:test_combat_encounter(a.encounter_id,a.wave_id)
    elseif op == 'combat_encounter_reset' then
        return app.actions:reset_combat_encounter(a.encounter_id)
    elseif op == 'combat_encounter_delete' then
        return app.actions:delete_combat_encounter(a.id)
    elseif op == 'create_premise' then
        local transform=a.transform
        if a.from_player then
            local captured,err=app.game:capture_transform(); if not captured then return nil,err end; transform=captured
        end
        local premise=app.model:add_premise({
            name=a.name,kind=a.kind,transform=transform,levels=a.levels,floor_height=a.floor_height,tags=a.tags,notes=a.notes,
        })
        app.selection:set('premise',premise.id); app:mark_dirty(); return premise
    elseif op == 'register_asset' then
        local asset=app.model:add_asset(a);app:mark_dirty();return asset
    elseif op == 'update_asset' then
        local asset,err=app.model:update_asset(a.id,a.patch or {});if not asset then return nil,err end;app:mark_dirty();return asset
    elseif op == 'wb_bounds_import' then
        if not app.asset_bounds then return nil,'asset bounds module failed to load' end
        local result,err=app.asset_bounds:import_manifest(a);if not result then return nil,err end;return result
    elseif op == 'wb_bounds_info' then
        if not app.asset_bounds then return nil,'asset bounds module failed to load' end
        local result,err=app.asset_bounds:info(a.asset_id);if not result then return nil,err end;return result
    elseif op == 'wb_bounds_set' then
        if not app.asset_bounds then return nil,'asset bounds module failed to load' end
        local result,err=app.asset_bounds:set(a.asset_id,a.bounds,a.source);if not result then return nil,err end;return result
    elseif op == 'wb_bounds_world_aabb' then
        if not app.asset_bounds then return nil,'asset bounds module failed to load' end
        local result,err=app.asset_bounds:world_aabb(a.object_id);if not result then return nil,err end;return result
    elseif op == 'wb_bounds_overlap' then
        if not app.asset_bounds then return nil,'asset bounds module failed to load' end
        local result,err=app.asset_bounds:overlap(a.object_ids,a.margin);if not result then return nil,err end;return result
    elseif op == 'wb_collisions' then
        if not app.asset_bounds then return nil,'asset bounds module failed to load' end
        local result,err=app.asset_bounds:collisions(a);if not result then return nil,err end;return result
    elseif op == 'wb_clipcheck' or op == 'wb_fixturecheck' or op == 'wb_fitcheck' then
        if not app.prop_validators then return nil,'prop validators module failed to load' end
        local method=op:sub(4)
        local result,err=app.prop_validators[method](app.prop_validators,a);if not result then return nil,err end
        if app.logger then app.logger:info('validator:'..method,'complete',{tested=result.tested,skipped=#(result.skipped or {}),hits=result.collision_count or nil}) end
        return result
    elseif op == 'wb_compat_scan' then
        if not app.integrations or not app.integrations.compatibility_scan then return nil,'compatibility scan unavailable' end
        return app.integrations:compatibility_scan(app)
    elseif op == 'wb_find' then
        if not app.project_browser then return nil,'project browser unavailable' end
        local result,err=app.project_browser:find(a);if not result then return nil,err end;return result
    elseif op == 'wb_tree' then
        if not app.project_browser then return nil,'project browser unavailable' end
        local result,err=app.project_browser:tree(a);if not result then return nil,err end;return result
    elseif op == 'wb_get' then
        if not app.project_browser then return nil,'project browser unavailable' end
        local result,err=app.project_browser:get(a);if not result then return nil,err end;return result
    elseif op == 'wb_refs' then
        if not app.project_browser then return nil,'project browser unavailable' end
        local result,err=app.project_browser:refs(a);if not result then return nil,err end;return result
    elseif op == 'wb_frame_create' or op == 'wb_frame_list' or op == 'wb_frame_get' or op == 'wb_frame_update' or op == 'wb_frame_delete' or op == 'wb_frame_to_world' or op == 'wb_world_to_frame' then
        if not app.room_frames then return nil,'room frames module unavailable' end
        local result,err
        if op=='wb_frame_create' then result,err=app.room_frames:create(a)
        elseif op=='wb_frame_list' then result=app.room_frames:list()
        elseif op=='wb_frame_get' then result,err=app.room_frames:get(a.frame_id)
        elseif op=='wb_frame_update' then result,err=app.room_frames:update(a.frame_id,a.patch or {})
        elseif op=='wb_frame_delete' then result,err=app.room_frames:delete(a.frame_id)
        elseif op=='wb_frame_to_world' then result,err=app.room_frames:to_world(a.frame_id,a.local_position or a)
        else result,err=app.room_frames:to_local(a.frame_id,a.transform) end
        if not result then return nil,err end
        return result
    elseif op == 'place_object_in_frame' then
        if not app.room_frames then return nil,'room frames module unavailable' end
        local mapped,err=app.room_frames:to_world(a.frame_id,{u=a.u,v=a.v,z=a.z or 0,
            rotation={yaw=a.yaw or 0,roll=a.roll or 0,pitch=a.pitch or 0}})
        if not mapped then return nil,err end
        local args=Util.deepcopy(a);args.transform=mapped.transform
        if type(args.metadata)~='table' then args.metadata={} end
        args.metadata.local_frame={id=mapped.frame_id,name=mapped.frame_name,position=mapped.local_position}
        local object;object,err=app.builder:place_object(args);if not object then return nil,err end
        app.selection:set('object',object.id)
        local entity_id,spawn_error;if a.spawn then entity_id,spawn_error=app.placement:spawn(object) end
        return {object=object,frame={id=mapped.frame_id,name=mapped.frame_name},local_position=mapped.local_position,world_transform=mapped.transform,
            entity_id=entity_id and tostring(entity_id) or nil,spawn_error=spawn_error and tostring(spawn_error) or nil}
    elseif op == 'move_object_in_frame' then
        if not app.room_frames then return nil,'room frames module unavailable' end
        local current=app.model:get_object(a.object_id);if not current then return nil,'object not found: '..tostring(a.object_id) end
        if current.locked then return nil,'object is locked; unlock it before editing' end
        local previous_local,frame_err=app.room_frames:to_local(a.frame_id,current.transform);if not previous_local then return nil,frame_err end
        local mapped,err=app.room_frames:to_world(a.frame_id,{u=a.u,v=a.v,z=a.z or 0,
            rotation={yaw=a.yaw~=nil and a.yaw or previous_local.rotation.yaw,
                roll=current.transform.rotation.roll,pitch=current.transform.rotation.pitch}})
        if not mapped then return nil,err end
        local metadata=Util.deepcopy(current.metadata or {})
        metadata.local_frame={id=mapped.frame_id,name=mapped.frame_name,position=mapped.local_position}
        local object;object,err=app.model:update_object(current.id,{transform=mapped.transform,metadata=metadata});if not object then return nil,err end
        app:mark_dirty()
        local entity_id,respawn_error
        if a.respawn~=false then entity_id,respawn_error=app.placement:refresh(object) end
        if a.respawn~=false and not entity_id then return nil,respawn_error end
        return {object=object,frame={id=mapped.frame_id,name=mapped.frame_name},local_position=mapped.local_position,world_transform=mapped.transform,
            entity_id=entity_id and tostring(entity_id) or nil,respawned=a.respawn~=false}
    elseif op == 'wb_bounds_fit' then
        if not app.asset_bounds then return nil,'asset bounds module failed to load' end
        local result,err=app.asset_bounds:fit(a.asset_id,a.target_size,a.mode);if not result then return nil,err end;return result
    elseif op == 'wb_generate_cable' or op == 'wb_generate_fence' or op == 'wb_generate_road' or op == 'wb_generate_market' or op == 'wb_generate_noderef' then
        if not app.world_builder_generators then return nil,'World Builder generators module failed to load' end
        local generator=op:sub(13)
        local result,err=app.world_builder_generators[generator](app.world_builder_generators,a)
        if not result then return nil,err end
        return result
    elseif op == 'create_static_light' then
        if not app.lighting then return nil,'lighting module is unavailable' end
        local object,err=app.lighting:create(a);if not object then return nil,err end
        return {object=object,spawned=object.runtime and object.runtime.spawned==true,warning=err}
    elseif op == 'update_static_light' then
        if not app.lighting then return nil,'lighting module is unavailable' end
        local object,err=app.lighting:update(a.object_id,a.patch or {});if not object then return nil,err end
        return {object=object,spawned=object.runtime and object.runtime.spawned==true,warning=err}
    elseif op == 'preview_time_of_day' then
        local result,err=app.lighting:preview_time(a.hour,a.minute);if not result then return nil,err end;return result
    elseif op == 'restore_time_of_day' then
        local result,err=app.lighting:restore_time();if not result then return nil,err end;return result
    elseif op == 'layer_list' then
        if not app.layers then return nil,'layer manager is unavailable' end
        return app.layers:list()
    elseif op == 'layer_create' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err=app.layers:create(a);if not result then return nil,err end;return {layer=result}
    elseif op == 'layer_update' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err=app.layers:update(a.id,a.patch or {});if not result then return nil,err end;return {layer=result}
    elseif op == 'layer_set_visible' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err=app.layers:set_visible(a.id,a.visible);if not result then return nil,err end;return result
    elseif op == 'layer_set_locked' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err=app.layers:set_locked(a.id,a.locked);if not result then return nil,err end;return result
    elseif op == 'layer_isolate' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err
        if a.id and a.id~='' then result,err=app.layers:isolate(a.id) else result,err=app.layers:unisolate() end
        if not result then return nil,err end;return result
    elseif op == 'layer_select_all' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err=app.layers:select_all(a.id,a);if not result then return nil,err end;return result
    elseif op == 'layer_assign' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local ids=a.object_ids
        if (type(ids)~='table' or #ids==0) and a.use_selection then ids={};for _,o in ipairs(app.selection:selected_objects()) do ids[#ids+1]=o.id end end
        local result,err=app.layers:assign(ids,a.id);if not result then return nil,err end;return result
    elseif op == 'layer_auto_assign' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err=app.layers:auto_assign(a);if not result then return nil,err end;return result
    elseif op == 'layer_delete' then
        if not app.layers then return nil,'layer manager is unavailable' end
        local result,err=app.layers:delete(a.id,a.move_to);if not result then return nil,err end;return result
    elseif op == 'visibility_capabilities' or op == 'visibility_create_occluder' or op == 'visibility_occlude_room' or op == 'visibility_list_occluders' or op == 'visibility_pvs' or op == 'visibility_hidden_meshes' then
        if not app.visibility then return nil,'visibility module is unavailable' end
        local method=op:sub(12)
        local result,err=app.visibility[method](app.visibility,a);if not result then return nil,err end;return result
    elseif op == 'visibility_update_occluder' then
        if not app.visibility then return nil,'visibility module is unavailable' end
        local result,err=app.visibility:update_occluder(a.id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'performance_analyze' then
        if not app.performance then return nil,'performance module is unavailable' end
        return app.performance:analyze(a)
    elseif op == 'performance_set_budget' then
        if not app.performance then return nil,'performance module is unavailable' end
        local result,err=app.performance:set_budget(a.scope,a.values);if not result then return nil,err end;return {budget=result,scope=a.scope or 'room'}
    elseif op == 'performance_select_cluster' then
        if not app.performance then return nil,'performance module is unavailable' end
        if not app.performance.last_report then app.performance:analyze({}) end
        local result,err=app.performance:select_cluster(a.index);if not result then return nil,err end;return result
    elseif op == 'sector_report_load' or op == 'sector_report_flags' or op == 'sector_report_select' then
        if not app.sector_inspector then return nil,'sector inspector module is unavailable' end
        local result,err
        if op=='sector_report_load' then result,err=app.sector_inspector:load()
        elseif op=='sector_report_flags' then
            if not app.sector_inspector.report then app.sector_inspector:load() end
            result,err=app.sector_inspector:flags(a)
        else
            if not app.sector_inspector.report then app.sector_inspector:load() end
            result,err=app.sector_inspector:select_flagged(a.index)
        end
        if not result then return nil,err end;return result
    elseif op == 'collision_presets' then
        if not app.collision then return nil,'collision module is unavailable' end
        return {presets=app.collision:presets(),materials=app.collision:materials(),actors=app.collision:actor_profiles()}
    elseif op == 'collision_create_primitive' or op == 'collision_import_mesh' or op == 'collision_fit_to_object' or op == 'collision_search_meshes' or op == 'collision_list' or op == 'collision_layers' or op == 'collision_passability' then
        if not app.collision then return nil,'collision module is unavailable' end
        local method=op:sub(11)
        local result,err=app.collision[method](app.collision,a);if not result then return nil,err end;return result
    elseif op == 'collision_update' then
        if not app.collision then return nil,'collision module is unavailable' end
        local result,err=app.collision:update(a.id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'collision_visualization' then
        if not app.collision then return nil,'collision module is unavailable' end
        local result,err=app.collision:set_visualization(a);if not result then return nil,err end;return result
    elseif op == 'screenshot_mode_capabilities' then
        if not app.screenshot_mode then return nil,'screenshot mode module is unavailable' end
        return app.screenshot_mode:capabilities()
    elseif op == 'screenshot_mode_status' then
        if not app.screenshot_mode then return nil,'screenshot mode module is unavailable' end
        return app.screenshot_mode:status()
    elseif op == 'screenshot_mode_enter' or op == 'screenshot_mode_freeze' or op == 'screenshot_mode_unfreeze' or op == 'screenshot_mode_ready' or op == 'screenshot_mode_reset_ready' or op == 'screenshot_mode_restore' then
        if not app.screenshot_mode then return nil,'screenshot mode module is unavailable' end
        local method=op:sub(17)
        local result,err=app.screenshot_mode[method](app.screenshot_mode,a);if not result then return nil,err end;return result
    elseif op == 'environment_weather_states' then
        if not app.environment then return nil,'environment module is unavailable' end
        return {weather_states=app.environment:weather_states(),capabilities=app.environment:capabilities()}
    elseif op == 'environment_list' then
        if not app.environment then return nil,'environment module is unavailable' end
        return app.environment:list(a)
    elseif op == 'environment_create' then
        if not app.environment then return nil,'environment module is unavailable' end
        local result,err=app.environment:create(a);if not result then return nil,err end;return {environment=result}
    elseif op == 'environment_update' then
        if not app.environment then return nil,'environment module is unavailable' end
        local result,err=app.environment:update(a.id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'environment_delete' then
        if not app.environment then return nil,'environment module is unavailable' end
        local result,err=app.environment:delete(a.id);if not result then return nil,err end;return result
    elseif op == 'environment_preview' then
        if not app.environment then return nil,'environment module is unavailable' end
        local result,err=app.environment:preview(a.id,a);if not result then return nil,err end;return result
    elseif op == 'environment_force' then
        if not app.environment then return nil,'environment module is unavailable' end
        local result,err=app.environment:set_force(a.force);if not result then return nil,err end;return result
    elseif op == 'environment_status' then
        if not app.environment then return nil,'environment module is unavailable' end
        return app.environment:status()
    elseif op == 'environment_restore' then
        if not app.environment then return nil,'environment module is unavailable' end
        local result,err=app.environment:restore(a);if not result then return nil,err end;return result
    elseif op == 'vfx_categories' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        return {categories=app.vfx:categories(),backends=app.vfx:backends()}
    elseif op == 'vfx_search' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        local result,err=app.vfx:search(a);if not result then return nil,err end;return result
    elseif op == 'vfx_create' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        local result,err=app.vfx:create(a);if not result then return nil,err end;return result
    elseif op == 'vfx_update' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        local result,err=app.vfx:update(a.object_id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'vfx_list' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        return app.vfx:list(a)
    elseif op == 'vfx_preview' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        local result,err
        if a.update==true then result,err=app.vfx:preview_update(a) else result,err=app.vfx:preview_start(a) end
        if not result then return nil,err end;return result
    elseif op == 'vfx_preview_status' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        return app.vfx:preview_status()
    elseif op == 'vfx_preview_commit' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        local result,err=app.vfx:preview_commit(a);if not result then return nil,err end;return result
    elseif op == 'vfx_preview_clear' then
        if not app.vfx then return nil,'VFX module is unavailable' end
        local ok,err=app.vfx:preview_clear();if not ok then return nil,err end;return {cleared=true}
    elseif op == 'create_audio_emitter' then
        if not app.ambient_audio then return nil,'ambient audio module is unavailable' end
        local result,err=app.ambient_audio:create_emitter(a);if not result then return nil,err end;return result
    elseif op == 'create_room_reverb_zone' then
        if not app.ambient_audio then return nil,'ambient audio module is unavailable' end
        local result,err=app.ambient_audio:create_reverb_zone(a);if not result then return nil,err end;return result
    elseif op == 'mesh_appearance_list' then
        if not app.mesh_appearance then return nil,'mesh appearance module is unavailable' end
        local result,err=app.mesh_appearance:list(a.object_id);if not result then return nil,err end;return result
    elseif op == 'mesh_appearance_preview' then
        if not app.mesh_appearance then return nil,'mesh appearance module is unavailable' end
        local result,err=app.mesh_appearance:preview(a);if not result then return nil,err end;return result
    elseif op == 'mesh_appearance_apply' then
        if not app.mesh_appearance then return nil,'mesh appearance module is unavailable' end
        local result,err=app.mesh_appearance:apply(a);if not result then return nil,err end;return result
    elseif op == 'mesh_appearance_cancel' then
        if not app.mesh_appearance then return nil,'mesh appearance module is unavailable' end
        local result,err=app.mesh_appearance:cancel(a);if not result then return nil,err end;return result
    elseif op == 'create_decal' then
        if not app.mesh_appearance then return nil,'mesh appearance module is unavailable' end
        local result,err=app.mesh_appearance:create_decal(a);if not result then return nil,err end;return result
    elseif op == 'delete_asset' then
        local ok,err=app.model:delete_asset(a.id);if not ok then return nil,err end; if app.selection:is('asset',a.id) then app.selection:clear() end; app:mark_dirty();return {deleted=true,id=a.id}
    elseif op == 'place_asset' then
        local object,err=app.actions:place_asset(a.id,a.source or 'aim',a);if not object then return nil,err end;return object
    elseif op == 'update_premise' then
        local premise,err=app.model:update_premise(a.id,a.patch or {}); if not premise then return nil,err end; app:mark_dirty(); return premise
    elseif op == 'delete_premise' then
        app.placement:despawn_premise(a.id)
        local should_clear=app.selected_premise_id==a.id
        local result,err=app.model:delete_premise(a.id); if not result then return nil,err end
        if should_clear then app.selection:clear() end; app:mark_dirty(); return {deleted=true,id=a.id}
    elseif op == 'create_room' then
        local room,err=app.builder:create_room(a); if not room then return nil,err end; app.selection:set('room',room.id); return room
    elseif op == 'create_corridor' then
        local room,err=app.builder:create_corridor(a); if not room then return nil,err end; app.selection:set('room',room.id); return room
    elseif op == 'update_room' then
        local room,err=app.model:update_room(a.id,a.patch or {}); if not room then return nil,err end
        local shell
        if a.rebuild_shell~=false then shell=app.builder:rebuild_room_shell(room.id) end
        app:mark_dirty(); return {room=room,shell=shell}
    elseif op == 'delete_room' then
        for _,object in ipairs(app.model.data.objects) do if object.room_id==a.id then app.placement:despawn(object) end end
        local should_clear=app.selected_room_id==a.id
        local result,err=app.model:delete_room(a.id); if not result then return nil,err end
        if should_clear then app.selection:clear() end; app:mark_dirty(); return {deleted=true,id=a.id}
    elseif op == 'add_opening' then
        local result,err=app.builder:add_opening(a); if not result then return nil,err end; return result
    elseif op == 'rebuild_room_shell' then
        local result,err=app.builder:rebuild_room_shell(a.id); if not result then return nil,err end; return result
    elseif op == 'detach_shell_piece' then
        local result,err=app.builder:detach_shell_object(a.id);if not result then return nil,err end;return result
    elseif op == 'replace_shell_piece' then
        local result,err=app.builder:replace_shell_object_asset(a.id,a.asset_id);if not result then return nil,err end;return result
    elseif op == 'set_construction_state' then
        local result,err=app.builder:set_construction_state(a.premise_id,a.room_id,a.role,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'focus_world_builder_object' then
        local object=app.model:get_object(a.id);if not object then return nil,'object not found' end
        if not app.placement:is_tracked(object) then local _,spawn_err=app.placement:spawn(object);if spawn_err then return nil,spawn_err end end
        local result,err=app.runtime_shell:focus(object);if not result then return nil,err end;return result
    elseif op == 'get_object_selection' then
        local objects=app.selection:selected_objects();local ids={};for _,object in ipairs(objects) do table.insert(ids,object.id) end
        return {ids=ids,count=#ids,active_id=app.selection.kind=='object' and app.selection.id or nil,source=app.selection.group_source}
    elseif op == 'set_object_selection' then
        local objects,err=app.selection:set_object_group(a.ids or {},a.active_id,a.source or 'mcp');if not objects then return nil,err end
        local focus
        if a.focus_world_builder and #objects>0 then focus,err=app.runtime_shell:focus_many(objects,a.active_id);if not focus then return nil,err end end
        return {objects=objects,count=#objects,focus=focus}
    elseif op == 'transform_object_group' then
        local result,err=app.authoring:transform_object_group(a.ids or {},a);if not result then return nil,err end;return result
    elseif op == 'set_object_group_state' then
        local result,err=app.actions:set_object_group_state(a.ids or {},a.patch or {});if not result then return nil,err end;return result
    elseif op == 'spawn_object_group' then
        local result,err=app.actions:spawn_object_group(a.ids or {},a.spawn~=false);if not result then return nil,err end;return result
    elseif op == 'duplicate_object_group' then
        local result,err=app.actions:duplicate_object_group(a.ids or {},a.offset);if not result then return nil,err end;return result
    elseif op == 'delete_object_group' then
        local result,err=app.actions:delete_object_group(a.ids or {});if not result then return nil,err end;return result
    elseif op == 'layout_object_group' then
        local result,err=app.authoring:layout_object_group(a.ids or {},a);if not result then return nil,err end;return result
    elseif op == 'wb_align' or op == 'wb_distribute' then
        a.operation=op=='wb_align' and 'align' or 'distribute'
        local result,err=app.authoring:layout_object_group(a.ids or {},a);if not result then return nil,err end;return result
    elseif op == 'wb_path_array' then
        local result,err=app.transform_session:create_array('path',a);if not result then return nil,err end;return result
    elseif op == 'wb_radial_array' then
        local result,err=app.transform_session:create_array('radial',a);if not result then return nil,err end;return result
    elseif op == 'wb_grid' then
        local result,err=app.transform_session:create_array('grid',a);if not result then return nil,err end;return result
    elseif op == 'replace_object_group_asset' then
        local result,err=app.actions:replace_object_group_asset(a.ids or {},a.asset_id);if not result then return nil,err end;return result
    elseif op == 'list_object_groups' then
        return {groups=app.model.data.object_groups or {},count=#(app.model.data.object_groups or {})}
    elseif op == 'create_object_group' then
        local result,err=app.assemblies:create_group({name=a.name,ids=a.ids or {},active_id=a.active_id,parent_id=a.parent_id,pivot_mode=a.pivot_mode,pivot=a.pivot,premise_id=a.premise_id,room_id=a.room_id});if not result then return nil,err end;return result
    elseif op == 'update_object_group' then
        local result,err=app.assemblies:update_group(a.id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'select_object_group' then
        local result,err=app.assemblies:select_group(a.id,a.recursive~=false,a.focus~=false);if not result then return nil,err end;return result
    elseif op == 'transform_saved_group' then
        local result,err=app.assemblies:transform_group(a.id,a);if not result then return nil,err end;return result
    elseif op == 'dissolve_object_group' then
        local result,err=app.assemblies:dissolve_group(a.id);if not result then return nil,err end;return result
    elseif op == 'list_object_prefabs' then
        return {prefabs=app.model.data.object_prefabs or {},count=#(app.model.data.object_prefabs or {})}
    elseif op == 'save_object_prefab' then
        local result,err=app.assemblies:save_prefab({name=a.name,ids=a.ids or {},active_id=a.active_id,pivot_mode=a.pivot_mode,pivot=a.pivot,category=a.category,tags=a.tags,notes=a.notes,source_group_id=a.source_group_id});if not result then return nil,err end;return result
    elseif op == 'instantiate_object_prefab' then
        local result,err=app.assemblies:instantiate_prefab(a.id,a);if not result then return nil,err end;return result
    elseif op == 'delete_object_prefab' then
        local result,err=app.assemblies:delete_prefab(a.id);if not result then return nil,err end;return result
    elseif op == 'wb_prefab_render' then
        local result,err=app.thumbnails:render_prefab(a.id,a);if not result then return nil,err end;return result
    elseif op == 'wb_prefab_render_status' then
        return app.thumbnails:status()
    elseif op == 'place_object' then
        local object,err=app.builder:place_object(a); if not object then return nil,err end; app.selection:set('object',object.id)
        local entity_id,spawn_error
        if a.spawn then entity_id,spawn_error=app.placement:spawn(object) end
        return {object=object,entity_id=entity_id and tostring(entity_id) or nil,spawn_error=spawn_error and tostring(spawn_error) or nil}
    elseif op == 'update_object' then
        local current=app.model:get_object(a.id);if not current then return nil,'object not found' end
        if current.locked and not (a.patch and a.patch.locked==false) then return nil,'object is locked; unlock it before editing' end
        local object,err=app.model:update_object(a.id,a.patch or {}); if not object then return nil,err end
        app:mark_dirty(); if a.respawn then local id,e=app.placement:refresh(object); if not id then return nil,e end end; return object
    elseif op == 'delete_object' then
        local object=app.model:get_object(a.id); if not object then return nil,'object not found' end;if object.locked then return nil,'object is locked; unlock it before deleting' end; app.placement:despawn(object)
        local result,err=app.model:delete_object(a.id); if not result then return nil,err end
        if app.selection:is('object',a.id) then app.selection:clear() end; app:mark_dirty(); return {deleted=true,id=a.id}
    elseif op == 'spawn_object' then
        local object=app.model:get_object(a.id); if not object then return nil,'object not found' end
        local id,err=app.placement:spawn(object); if not id then return nil,err end; return {spawned=true,id=a.id,entity_id=tostring(id)}
    elseif op == 'despawn_object' then
        local object=app.model:get_object(a.id); if not object then return nil,'object not found' end
        local ok,err=app.placement:despawn(object); if not ok then return nil,err end; return {despawned=true,id=a.id}
    elseif op == 'spawn_premise' then
        if not app.model:get_premise(a.id) then return nil,'premise not found' end; return app.placement:spawn_premise(a.id)
    elseif op == 'despawn_all' then
        return app.placement:despawn_all()
    elseif op == 'array_object' then
        local objects,err=app.builder:array_object(a.id,a.count,a.dx,a.dy,a.dz,a.dyaw); if not objects then return nil,err end; return objects
    elseif op == 'mirror_object' then
        local object,err=app.builder:mirror_object(a.id,a.axis); if not object then return nil,err end; return object
    elseif op == 'create_prefab' then
        local result,err=app.builder:create_prefab(a); if not result then return nil,err end; return result
    elseif op == 'aim_point' then
        local result,err=app.game:aim_point(a.distance);if not result then return nil,err end;return result
    elseif op == 'pick_aimed_object' then
        local result,err=app.viewport_tools:pick_aimed_object(a);if not result then return nil,err end;return result
    elseif op == 'preview_asset' then
        local result,err
        if a.stamp_mode then result,err=app.placement:start_stamp(a.id,a) else result,err=app.placement:preview_asset(a.id,a) end
        if not result then return nil,err end;return result
    elseif op == 'stamp_preview' then
        local result,err=app.placement:stamp_once(a.premise_id,a.room_id);if not result then return nil,err end;return result
    elseif op == 'clear_asset_preview' then
        local result,err
        if app.stamp_session and app.stamp_session:is_active() then result,err=app.placement:stop_stamp() else result,err=app.placement:clear_preview() end
        if not result then return nil,err end;return result
    elseif op == 'commit_stamp_stroke' then
        local result,err=app.stamp_session:commit();if not result then return nil,err end;return result
    elseif op == 'cancel_stamp_stroke' then
        local result,err=app.stamp_session:cancel();if not result then return nil,err end;return result
    elseif op == 'get_stamp_stroke_status' then
        return app.stamp_session:status()
    elseif op == 'place_object_at_aim' then
        local result,err=app.authoring:place_object_at_aim(a);if not result then return nil,err end;return result
    elseif op == 'create_interactable' then
        local result,err=app.actions:create_interactable(a);if not result then return nil,err end;return {object=result,setup_status=result.metadata.interactable.setup_status,warning=err}
    elseif op == 'list_interactables' then
        local objects={};for _,object in ipairs(app.model.data.objects or {}) do if object.metadata and object.metadata.interactable then table.insert(objects,object) end end
        return {count=#objects,objects=objects}
    elseif op == 'update_interactable' then
        local result,err=app.actions:update_interactable(a.id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'delete_interactable' then
        local object=app.model:get_object(a.id);if not object or not (object.metadata and object.metadata.interactable) then return nil,'interactable object not found' end
        local previous_kind,previous_id=app.selection.kind,app.selection.id
        app.selection:set('object',object.id);local ok,err=app.actions:delete_selected()
        if not ok then if previous_kind and previous_id then app.selection:set(previous_kind,previous_id) end;return nil,err end
        return {deleted=true,id=a.id}
    elseif op == 'create_npc_population' then
        local result,err=app.actions:create_npc_population(a);if not result then return nil,err end;return {object=result,persistent=true,native_node='worldPopulationSpawnerNode',preview=result.runtime and result.runtime.status or 'not_spawned'}
    elseif op == 'list_npc_population' then
        local objects={};for _,object in ipairs(app.model.data.objects or {}) do if object.metadata and object.metadata.npc_population then table.insert(objects,object) end end
        return {count=#objects,objects=objects}
    elseif op == 'update_npc_population' then
        local result,err=app.actions:update_npc_population(a.id,a.patch or {});if not result then return nil,err end;return result
    elseif op == 'create_volume' then
        local result,err=app.authoring:create_volume(a);if not result then return nil,err end;return result
    elseif op == 'update_volume' then
        local result,err=app.model:update_volume(a.id,a.patch or {});if not result then return nil,err end;app:mark_dirty();return result
    elseif op == 'link_volume_fact' then
        local volume=app.model:get_volume(a.id);if not volume then return nil,'volume not found' end
        local fact=app.util.trim(a.fact_name or '')
        if fact~='' and not fact:match('^[%w_%.%-]+$') then return nil,'fact_name must use letters, numbers, underscore, dot, or hyphen' end
        local metadata=app.util.deepcopy(volume.metadata or {})
        metadata.questforge=metadata.questforge or {}
        if fact=='' then metadata.questforge.fact_name=nil;metadata.questforge.value=nil
        else metadata.questforge.fact_name=fact;metadata.questforge.value=tonumber(a.value) or 1 end
        local result,err=app.model:update_volume(a.id,{metadata=metadata});if not result then return nil,err end
        app:mark_dirty();return {volume=result,linked=fact~='',fact_name=fact~='' and fact or nil,value=fact~='' and (tonumber(a.value) or 1) or nil}
    elseif op == 'delete_volume' then
        local result,err=app.model:delete_volume(a.id);if not result then return nil,err end; if app.selection:is('volume',a.id) then app.selection:clear() end;app:mark_dirty();return {deleted=true,id=a.id}
    elseif op == 'create_camera' then
        local result,err=app.authoring:create_camera(a);if not result then return nil,err end;return result
    elseif op == 'update_camera' then
        local result,err=app.model:update_camera(a.id,a.patch or {});if not result then return nil,err end;app:mark_dirty();return result
    elseif op == 'set_camera_look_at' then
        local result,err=app.authoring:set_camera_look_at(a.id,a.target);if not result then return nil,err end;return result
    elseif op == 'preview_camera' then
        local result,err=app.authoring:preview_camera(a.id);if not result then return nil,err end;return result
    elseif op == 'delete_camera' then
        local result,err=app.model:delete_camera(a.id);if not result then return nil,err end; if app.selection:is('camera',a.id) then app.selection:clear() end;app:mark_dirty();return {deleted=true,id=a.id}
    elseif op == 'snap_item' then
        local result,err=app.authoring:snap_item(a.kind,a.id,a.grid,a.angle);if not result then return nil,err end;return result
    elseif op == 'batch_transform' then
        local result,err=app.authoring:batch_transform(a.kind,a.ids,a.dx,a.dy,a.dz,a.dyaw,a.local_space);if not result then return nil,err end;return result
    elseif op == 'capture_camera' then
        local result,err=app.game:capture_camera_transform();if not result then return nil,err end;return {transform=result,fov=app.game:camera_fov(),source=app.game.last_camera_source}
    elseif op == 'copy_transform' then
        local result,err=app.ent_tools:copy(a.part or 'transform',a.kind,a.id);if not result then return nil,err end;return result
    elseif op == 'paste_transform' then
        local result,err=app.ent_tools:paste(a.part or 'transform',a.kind,a.id);if not result then return nil,err end;return result
    elseif op == 'reset_rotation' then
        local result,err=app.ent_tools:reset_rotation(a.kind,a.id);if not result then return nil,err end;return result
    elseif op == 'move_item_to_player' then
        local result,err=app.ent_tools:move_to_player(a.kind,a.id,a.copy_rotation==true);if not result then return nil,err end;return result
    elseif op == 'move_item_to_aim' then
        local result,err=app.ent_tools:move_to_aim(a.kind,a.id,a.distance);if not result then return nil,err end;return result
    elseif op == 'start_transform_grab' then
        local result,err=app.transform_session:start(a);if not result then return nil,err end;return result
    elseif op == 'configure_transform_grab' then
        local result,err=app.transform_session:configure(a);if not result then return nil,err end;return result
    elseif op == 'commit_transform_grab' then
        local result,err=app.transform_session:commit();if not result then return nil,err end;return result
    elseif op == 'cancel_transform_grab' then
        local result,err=app.transform_session:cancel();if not result then return nil,err end;return result
    elseif op == 'get_transform_grab_status' then
        return app.transform_session:status()
    elseif op == 'start_transform_edit' then
        local result,err=app.transform_session:start_edit(a);if not result then return nil,err end;return result
    elseif op == 'start_duplicate_transform_edit' then
        local result,err=app.transform_session:start_duplicate(a);if not result then return nil,err end;return result
    elseif op == 'start_placement_transform_edit' then
        local result,err=app.transform_session:start_placement(a);if not result then return nil,err end;return result
    elseif op == 'start_pattern_transform_edit' then
        local result,err=app.transform_session:start_pattern(a);if not result then return nil,err end;return result
    elseif op == 'start_mirror_transform_edit' then
        local result,err=app.transform_session:start_mirror(a);if not result then return nil,err end;return result
    elseif op == 'start_scatter_transform_edit' then
        local result,err=app.transform_session:start_scatter(a);if not result then return nil,err end;return result
    elseif op == 'adjust_transform_edit' then
        local result,err=app.transform_session:adjust(a);if not result then return nil,err end;return result
    elseif op == 'reset_transform_edit' then
        local result,err=app.transform_session:reset_edit();if not result then return nil,err end;return result
    elseif op == 'commit_transform_edit' then
        local result,err=app.transform_session:commit();if not result then return nil,err end;return result
    elseif op == 'cancel_transform_edit' then
        local result,err=app.transform_session:cancel();if not result then return nil,err end;return result
    elseif op == 'get_transform_session_status' then
        return app.transform_session:status()
    elseif op == 'drop_item_to_ground' then
        local result,err=app.ent_tools:drop_to_ground(a.kind,a.id,a.max_distance,a.offset);if not result then return nil,err end;return result
    elseif op == 'teleport_player_to_item' then
        local result,err=app.ent_tools:teleport_player_to(a.kind,a.id);if not result then return nil,err end;return result
    elseif op == 'set_transform_target' then
        local result,err=app.ent_tools:set_target(a.kind,a.id);if not result then return nil,err end;return result
    elseif op == 'clear_transform_target' then
        return app.ent_tools:clear_target()
    elseif op == 'aim_item_at_target' then
        local result,err=app.ent_tools:aim_at_target(a.kind,a.id,a.target_kind,a.target_id);if not result then return nil,err end;return result
    elseif op == 'aim_item_at_player' then
        local result,err=app.ent_tools:aim_at_player(a.kind,a.id);if not result then return nil,err end;return result
    elseif op == 'aim_item_at_crosshair' then
        local result,err=app.ent_tools:aim_at_crosshair(a.kind,a.id,a.distance);if not result then return nil,err end;return result
    elseif op == 'duplicate_at_aim' then
        local result,err=app.ent_tools:duplicate_at_aim(a.kind,a.id,a.distance,a.spawn);if not result then return nil,err end;return result
    elseif op == 'scatter_at_aim' then
        local result,err=app.ent_tools:scatter_at_aim(a);if not result then return nil,err end;return result
    elseif op == 'refresh_markers' then
        return app.markers:refresh(a.premise_id)
    elseif op == 'clear_markers' then
        return app.markers:clear()
    elseif op == 'validate' then
        return {issues=app.model:validate()}
    elseif op == 'save' then
        local ok, err = app:save(true)
        if not ok then return nil, tostring(err) end
        return {saved=true}
    elseif op == 'export' then
        local ok, path_or_err = app:export(a.format or 'json', a.path)
        if not ok then return nil, path_or_err end
        return {exported=true, path=path_or_err}
    elseif op == 'questforge_sync_preview' then
        if not app.questforge_sync then return nil,'Quest Forge sync module is unavailable' end
        return app.questforge_sync:preview(a.document)
    elseif op == 'questforge_sync_apply' then
        if not app.questforge_sync then return nil,'Quest Forge sync module is unavailable' end
        return app.questforge_sync:apply(a.document,{apply_positions=a.apply_positions==true})
    elseif op == 'questforge_links' then
        if not app.questforge_sync then return nil,'Quest Forge sync module is unavailable' end
        return app.questforge_sync:links(a.kind,a.id)
    elseif op == 'quest_simulation_state' then
        if not app.quest_simulator then return nil,'Quest simulation module is unavailable' end
        if a.fact_name and a.fact_name~='' then return app.quest_simulator:inspect(a.fact_name) end
        return app.quest_simulator:catalog()
    elseif op == 'quest_simulation_prepare_write' then
        if not app.quest_simulator then return nil,'Quest simulation module is unavailable' end
        return app.quest_simulator:prepare_write(a.fact_name,a.value,a.source)
    elseif op == 'quest_simulation_prepare_trigger' then
        if not app.quest_simulator then return nil,'Quest simulation module is unavailable' end
        return app.quest_simulator:prepare_trigger(a.volume_id)
    elseif op == 'quest_simulation_confirm_write' then
        if not app.quest_simulator then return nil,'Quest simulation module is unavailable' end
        return app.quest_simulator:confirm_write(a.token)
    elseif op == 'quest_simulation_cancel_write' then
        if not app.quest_simulator then return nil,'Quest simulation module is unavailable' end
        return app.quest_simulator:cancel_write(a.token)
    elseif op == 'world_state_list' then
        return {variants=app.world_states:list(),status=app.world_states:status()}
    elseif op == 'world_state_create' then
        return app.world_states:create(a)
    elseif op == 'world_state_update' then
        return app.world_states:update(a.id,a.patch or {})
    elseif op == 'world_state_delete' then
        return app.world_states:delete(a.id)
    elseif op == 'world_state_add_object' then
        return app.world_states:add_member(a.variant_id,a.object_id,a.visible~=false)
    elseif op == 'world_state_remove_object' then
        return app.world_states:remove_member(a.variant_id,a.object_id)
    elseif op == 'world_state_preview' then
        return app.world_states:preview()
    elseif op == 'world_state_apply' then
        return app.world_states:apply()
    elseif op == 'world_state_auto' then
        return app.world_states:set_auto(a.enabled==true)
    elseif op == 'import_catalog_asset' then
        if not app.world_builder then return nil,'World Builder adapter is unavailable' end
        local result,err=app.world_builder:import_catalog_record(a.record);if not result then return nil,err end;return result
    elseif op == 'wb_favorite_prepare' then
        if not app.world_builder then return nil,'World Builder adapter is unavailable' end
        local result,err=app.world_builder:prepare_favorite_record(a.record,a.name);if not result then return nil,err end;return result
    elseif op == 'get_history' then
        return app.model:history(a.limit)
    elseif op == 'checkpoint_create' then
        return app.checkpoints:create(a)
    elseif op == 'checkpoint_list' then
        return app.checkpoints:list()
    elseif op == 'checkpoint_diff' then
        return app.checkpoints:diff(a.checkpoint_a or a.a,a.checkpoint_b or a.b)
    elseif op == 'checkpoint_restore' then
        return app.checkpoints:restore(a.checkpoint_id or a.id)
    elseif op == 'get_runtime_sync_status' then
        return app:check_runtime_sync(true)
    elseif op == 'sync_runtime' then
        local result,err=app:sync_runtime();if not result then return nil,err end;result.warning=err;return result
    elseif op == 'history_undo' or op == 'history_redo' then
        local result,message=app.actions:history(op=='history_undo' and 'undo' or 'redo',a.steps)
        if not result then return nil,message end
        result.warning=message;return result
    elseif op == 'import_world_builder_build' then
        if not app.wb_import then return nil,'wb_import module failed to load' end
        local result,err=app.wb_import:import(a);if not result then return nil,err end;return result
    elseif op == 'build_export_status' then
        if not app.build_export then return nil,'build_export module failed to load' end
        return app.build_export:status()
    elseif op == 'build_export_world_builder' then
        if not app.build_export then return nil,'build_export module failed to load' end
        local result,err=app.build_export:export(a);if not result then return nil,err end;return result
    elseif op == 'integration_status' then
        return app.integrations:status()
    elseif op == 'vanilla_removal_status' or op == 'remove_vanilla_crosshair' or op == 'remove_vanilla_nearby' or op == 'restore_vanilla_removal' or op == 'restore_all_vanilla_removals' or op == 'list_vanilla_removals' then
        if not app.vanilla_removal then return nil,'vanilla removal module failed to load' end
        local result,err
        if op == 'vanilla_removal_status' then result=app.vanilla_removal:status()
        elseif op == 'remove_vanilla_crosshair' then result,err=app.vanilla_removal:remove_crosshair(a)
        elseif op == 'remove_vanilla_nearby' then result,err=app.vanilla_removal:remove_nearby(a)
        elseif op == 'restore_vanilla_removal' then result,err=app.vanilla_removal:restore(a.id)
        elseif op == 'restore_all_vanilla_removals' then result,err=app.vanilla_removal:restore_all()
        else result,err=app.vanilla_removal:list() end
        if not result then return nil,err end
        return result
    elseif op == 'rht_status' or op == 'rht_crosshair' or op == 'rht_scan' or op == 'rht_node' then
        if not app.rht_inspector then return nil,'rht_inspector module failed to load' end
        if op == 'rht_status' then return app.rht_inspector:status() end
        local result,err
        if op == 'rht_crosshair' then result,err=app.rht_inspector:crosshair(a)
        elseif op == 'rht_scan' then result,err=app.rht_inspector:scan(a)
        else result,err=app.rht_inspector:node(a) end
        if not result then return nil,err end
        if a.save ~= false and op ~= 'rht_node' then
            local file='exports/rht-'..op:sub(5)..'-'..os.date('%Y%m%d-%H%M%S')..'.json'
            Util.json_write(file,result);result.saved_to=file
        end
        return result
    elseif op == 'clear_debug_log' then
        local ok,err=app.logger:clear();if not ok then return nil,err end;return {cleared=true,path=app.logger.path}
    elseif op == 'run_diagnostics' then
        if not app.diagnostics then return nil,'diagnostics unavailable' end
        return app.diagnostics:run()
    end

    return nil, 'unknown operation: ' .. tostring(op)
end

function Bridge:poll(now)
    if now - self.last_status_write >= (self.app.config.status_interval or 1.0) then
        self.last_status_write = now
        self:write_status()
    end

    local command = Util.json_read(self.command_path, nil)
    if type(command) ~= 'table' or not command.id or command.id == self.last_command_id then return end
    self.last_command_id = command.id

    local ok, result, err = pcall(function()
        local r, e = self:handle(command)
        return r, e
    end)
    if not ok then
        if self.app.logger then self.app.logger:error('bridge:'..tostring(command.op),result,{id=command.id}) end
        self:write_response(response(command.id, false, nil, tostring(result)))
    elseif result == nil then
        if self.app.logger then self.app.logger:error('bridge:'..tostring(command.op),err or 'operation failed',{id=command.id}) end
        self:write_response(response(command.id, false, nil, tostring(err or 'operation failed')))
    else
        if self.app.logger then self.app.logger:debug('bridge:'..tostring(command.op),'complete',{id=command.id}) end
        self:write_response(response(command.id, true, result, nil))
    end
end

return Bridge
