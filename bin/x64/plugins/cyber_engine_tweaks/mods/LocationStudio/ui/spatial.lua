local SpatialUI={}
local Widgets=require('ui/widgets')
SpatialUI.__index=SpatialUI

function SpatialUI.new(app,notify)
    return setmetatable({
        app=app,notify=notify,volume_name='New Trigger',volume_shape='box',volume_purpose='trigger',volume_fact_name='',
        volume_size={2,2,2},volume_radius=1,volume_height=2,
        camera_name='New Camera',camera_fov=50,camera_duration=3,aim_distance=10,
        workspot_name='New NPC Workspot',workspot_kind='sit',workspot_record='',workspot_appearance='',workspot_anim='',workspot_rig='Woman Average',workspot_comp='',workspot_ent='',
        population_search='',population_results=nil,population_asset_id='',population_name='New NPC',population_appearance='',population_attitude='',population_faction='',population_level=0,population_archetype='',population_idle='',population_despawn=0,population_fact='',population_fact_value=1,population_primary=100,population_secondary=120,population_always=false,population_spawn_on_start=true,population_edit_id=nil,
        npc_route_npc_id='',npc_route_id='',npc_route_variant='patrol',npc_route_name='NPC Patrol',npc_route_loop=true,npc_route_wait=1,npc_route_facing=0,npc_route_speed=1,npc_route_transition='walk',npc_route_workspot='',npc_route_branch_fact='',npc_route_branch_value=1,npc_route_branch_target='',npc_route_wp_edit_id='',npc_route_wp_name='',npc_route_wp_position={0,0,0},npc_route_wp_yaw=0,
        combat_encounter_id='',combat_name='New Combat Encounter',combat_area_volume='',combat_trigger_volume='',combat_activation_fact='',combat_activation_value=1,combat_reset_fact='',combat_reset_value=0,
        combat_npc_id='',combat_group_id='',combat_group_name='Enemy Group',combat_group_faction='',combat_group_attitude='hostile',combat_group_spacing=1.5,
        combat_wave_id='',combat_wave_name='Wave 1',combat_wave_activation='immediate',combat_wave_trigger='',combat_wave_fact='',combat_wave_value=1,combat_wave_after='',combat_wave_delay=0,combat_wave_groups={},
        combat_relation_source='',combat_relation_target='',combat_relation_attitude='hostile',
        walk_actor='player',walk_goal={0,0,0},walk_grid_step=1.0,walk_margin=2.0,walk_result=nil,
        nav_graph_id='',nav_snap_distance=3.0,nav_start=nil,nav_result=nil,nav_workspots=nil,
        logic_graph_id='',logic_graph_name='New Device Logic Graph',logic_node_id='',logic_link_id='',logic_node_kind='terminal',logic_node_name='New Device',logic_object_id='',logic_fact_name='',logic_fact_value=1,logic_action='unlock',logic_operation_arg='',logic_native_operation='',logic_device_hash='',logic_device_class='',logic_ps_hash='',logic_instance_ref='',logic_node_ref='',logic_from_id='',logic_to_id='',logic_trigger='activate',logic_condition_fact='',logic_condition_value=1,
        questforge_path='exports/questforge_edited.json',questforge_preview=nil,questforge_apply_positions=false,
        questsim_filter='',questsim_fact='',questsim_value=1,questsim_trigger_id='',questsim_pending=nil,questsim_catalog=nil,
        world_variant_id='',world_variant_name='before_quest',world_variant_fact='',world_variant_value=1,world_variant_operator='==',world_variant_priority=0,world_variant_object_visible=true,world_variant_auto=false,
        cover_name='Cover Node',cover_type='crouch',cover_exposure='medium',cover_spacing=1.5,cover_radius=8,cover_samples=24,cover_nodes_scan=nil,cover_selected_id='',cover_position={0,0,0},cover_yaw=0,
        spline_id='',spline_name='New Spline',spline_point=1,spline_handle={2,0,0},spline_use_kind='distribute',spline_asset_id='',spline_spacing=2,spline_npc_id='',spline_sample=nil,
        vc_radius=8,vc_term='',vc_hide=true,vc_approx=false,vc_group='',
        tl_id='',tl_name='New Timeline',tl_duration=30,tl_time=0,tl_track_id='',tl_speaker='V',tl_line='',tl_line_dur=3,tl_fact='',tl_fact_value=1,tl_marker='Beat',tl_move=2,tl_npc_key='',tl_validation=nil,
        layer_new_name='Set Dressing',layer_edit_id='',layer_auto=nil,
        vis_mesh='plane_two_sided',vis_size={4,1,3},vis_pvs=nil,vis_hidden=nil,vis_live=false,
        perf_report=nil,perf_scope='premise',
        sector_filter='',sector_severity='',
        col_shape='box',col_size={2,0.3,3},col_radius=0.5,col_height=1.8,col_preset=33,col_material='',col_visualize=true,col_name='Blocker',col_mesh_query='',col_mesh_results=nil,col_mesh_path='',col_edit_id=nil,col_edit=nil,
        pass_actor='both',pass_step=0.5,pass_half=8,pass_goal=nil,pass_live=false,pass_result=nil,
        env_selected_id='',env_new_name='Golden hour rain',env_edit_id=nil,env_edit=nil,env_force=true,
        vfx_query='',vfx_category='all',vfx_backend='all',vfx_results=nil,vfx_selected=nil,vfx_name='',vfx_scale={1,1,1},vfx_rotation={0,0,0},vfx_emission=1,vfx_respawn_on_move=false,vfx_align=false,vfx_follow=true,vfx_distance=10,vfx_edit_id=nil,vfx_edit=nil,
        lighting_name='New Static Light',lighting_preset='warm',lighting_search='',lighting_hour=20,lighting_minute=0,
        audio_query='amb_',audio_results=nil,audio_selected_path='',audio_name='Room Tone',audio_radius=5,audio_metadata='',
        reverb_name='Room Reverb',reverb_bus='revb_interior_room_medium',reverb_sound_event='',reverb_priority=16,reverb_outer=10,reverb_vertical=1,
        interactable_asset_id='',interactable_search='',interactable_kind='door',interactable_name='New Interactable',interactable_entity_record='',interactable_item_record='',interactable_loot_table='',interactable_loot_item_record='',interactable_lock_state='locked',interactable_fact_name='',interactable_fact_value=1,
        mesh_decal_search='',mesh_decal_name='New Decal',mesh_decal_width=1,mesh_decal_height=1,mesh_decal_alpha=1,mesh_decal_results=nil,mesh_decal_selected=nil,mesh_appearances=nil,mesh_appearance_error=nil,
    },SpatialUI)
end
function SpatialUI:toast(text) if self.notify then self.notify(text) end end

function SpatialUI:draw_npc_routes(premise)
    local app=self.app
    ImGui.Text('PATROL & AI ROUTES');ImGui.TextWrapped('Routes are linked to saved NPC population points. They provide editable patrol/alert/combat plans and a Quest Forge handoff; native REDengine AI execution still requires compatible community/quest resources.')
    local populations={};for _,obj in ipairs(app.model.data.objects or {}) do if obj.metadata and obj.metadata.npc_population and (not premise or obj.premise_id==premise.id) then populations[#populations+1]=obj end end
    local selected_npc=app.model:get_object(self.npc_route_npc_id)
    local npc_label=selected_npc and (selected_npc.name or 'NPC population') or 'Select saved NPC'
    if ImGui.BeginCombo('NPC population point##route',npc_label) then
        for _,obj in ipairs(populations) do if ImGui.Selectable((obj.name or obj.metadata.npc_population.record)..'##npcroute_'..obj.id,self.npc_route_npc_id==obj.id) then self.npc_route_npc_id=obj.id;self.npc_route_id='' end end
        ImGui.EndCombo()
    end
    ImGui.SameLine();self.npc_route_name=select(1,ImGui.InputText('Route name',self.npc_route_name,128))
    if ImGui.Button('CREATE ROUTE') then
        local route,err=app.actions:create_npc_route({npc_id=self.npc_route_npc_id,name=self.npc_route_name,loop=self.npc_route_loop})
        if route then self.npc_route_id=route.id;self:toast('Created route for saved NPC') else self:toast(err) end
    end
    local routes={};for _,route in ipairs(app.model.data.npc_routes or {}) do if route.npc_id==self.npc_route_npc_id then routes[#routes+1]=route end end
    local route_label='Select route';for _,route in ipairs(routes) do if route.id==self.npc_route_id then route_label=route.name end end
    if ImGui.BeginCombo('Route##npcroute',route_label) then for _,route in ipairs(routes) do if ImGui.Selectable(route.name..'##'..route.id,self.npc_route_id==route.id) then self.npc_route_id=route.id;self.npc_route_wp_edit_id='' end end;ImGui.EndCombo() end
    local route=self.npc_route_id~='' and app.model:get_npc_route(self.npc_route_id) or nil
    if not route then ImGui.TextDisabled('Choose a saved NPC population point, then create or select its route.');return end
    local changed;route.loop,changed=ImGui.Checkbox('Loop patrol route',route.loop==true)
    if changed then app.actions:update_npc_route({id=route.id,patch={loop=route.loop}}) end
    if ImGui.BeginCombo('Route variant',self.npc_route_variant) then for _,variant in ipairs({'patrol','alert','combat'}) do if ImGui.Selectable(variant,self.npc_route_variant==variant) then self.npc_route_variant=variant;self.npc_route_wp_edit_id='' end end;ImGui.EndCombo() end
    local field=self.npc_route_variant=='alert' and 'alert_waypoints' or (self.npc_route_variant=='combat' and 'combat_waypoints' or 'waypoints')
    route[field]=route[field] or {};ImGui.Separator();ImGui.Text(string.upper(self.npc_route_variant)..' WAYPOINTS')
    self.npc_route_wait=select(1,ImGui.InputFloat('Wait seconds',self.npc_route_wait,0.25,1,'%.2f'))
    self.npc_route_facing=select(1,ImGui.InputFloat('Facing yaw',self.npc_route_facing,5,15,'%.1f'))
    self.npc_route_speed=select(1,ImGui.InputFloat('Movement speed multiplier',self.npc_route_speed,0.1,0.5,'%.2f'))
    if ImGui.BeginCombo('Transition',self.npc_route_transition=='walk' and 'Walk to next' or 'Use workspot') then
        if ImGui.Selectable('Walk to next',self.npc_route_transition=='walk') then self.npc_route_transition='walk' end
        if ImGui.Selectable('Use workspot',self.npc_route_transition=='workspot') then self.npc_route_transition='workspot' end
        ImGui.EndCombo()
    end
    local workspots={};for _,loc in ipairs(app.model.data.locations or {}) do if loc.metadata and loc.metadata.workspot then workspots[#workspots+1]=loc end end
    if self.npc_route_transition=='workspot' then
        local label='Choose saved workspot';for _,loc in ipairs(workspots) do if loc.id==self.npc_route_workspot then label=loc.name end end
        if ImGui.BeginCombo('Workspot##route',label) then for _,loc in ipairs(workspots) do if ImGui.Selectable(loc.name..'##wp_'..loc.id,self.npc_route_workspot==loc.id) then self.npc_route_workspot=loc.id end end;ImGui.EndCombo() end
    end
    self.npc_route_branch_fact=select(1,ImGui.InputText('Branch quest fact (optional)',self.npc_route_branch_fact,128))
    self.npc_route_branch_value=select(1,ImGui.InputInt('Branch fact value',self.npc_route_branch_value))
    self.npc_route_branch_target=select(1,ImGui.InputText('Branch target waypoint ID (optional)',self.npc_route_branch_target,128))
    if ImGui.Button('ADD WAYPOINT AT PLAYER') then
        local transform,err=app.game:capture_transform();if transform then local wp;wp,err=app.actions:add_npc_route_waypoint({route_id=route.id,variant=self.npc_route_variant,transform=transform,wait_seconds=self.npc_route_wait,facing_yaw=self.npc_route_facing,speed=self.npc_route_speed,transition=self.npc_route_transition,workspot_location_id=self.npc_route_workspot,branch_fact=self.npc_route_branch_fact,branch_value=self.npc_route_branch_value,branch_target_id=self.npc_route_branch_target});if wp then self.npc_route_wp_edit_id=wp.id end end;self:toast(err or 'Added route waypoint')
    end
    ImGui.SameLine();if ImGui.Button('ADD WAYPOINT AT AIM') then local hit,err=app.game:aim_point(self.aim_distance);if hit then local transform={position=hit.position,rotation={roll=0,pitch=0,yaw=0}};local wp;wp,err=app.actions:add_npc_route_waypoint({route_id=route.id,variant=self.npc_route_variant,transform=transform,wait_seconds=self.npc_route_wait,facing_yaw=self.npc_route_facing,speed=self.npc_route_speed,transition=self.npc_route_transition,workspot_location_id=self.npc_route_workspot,branch_fact=self.npc_route_branch_fact,branch_value=self.npc_route_branch_value,branch_target_id=self.npc_route_branch_target});if wp then self.npc_route_wp_edit_id=wp.id end end;self:toast(err or 'Added route waypoint') end
    ImGui.BeginChild('##npc_route_waypoints',0,180,true)
    for index,wp in ipairs(route[field]) do
        local p=wp.transform.position
        if ImGui.Selectable(string.format('%02d  %s   %.1f, %.1f, %.1f   wait %.1fs',index,wp.name,p.x,p.y,p.z,wp.wait_seconds or 0)..'##npcwp_'..wp.id,self.npc_route_wp_edit_id==wp.id) then
            self.npc_route_wp_edit_id=wp.id;self.npc_route_wp_name=wp.name or 'Waypoint';self.npc_route_wp_position={p.x,p.y,p.z};self.npc_route_wp_yaw=(wp.transform.rotation or {}).yaw or 0;self.npc_route_wait=wp.wait_seconds or 0;self.npc_route_facing=wp.facing_yaw or 0;self.npc_route_speed=wp.speed or 1;self.npc_route_transition=wp.transition or 'walk';self.npc_route_workspot=wp.workspot_location_id or '';self.npc_route_branch_fact=wp.branch_fact or '';self.npc_route_branch_value=wp.branch_value or 1;self.npc_route_branch_target=wp.branch_target_id or ''
        end
    end
    ImGui.EndChild()
    local selected;local index;for i,wp in ipairs(route[field]) do if wp.id==self.npc_route_wp_edit_id then selected=wp;index=i end end
    if selected then
        self.npc_route_wp_name=select(1,ImGui.InputText('Waypoint name##routewp',self.npc_route_wp_name,128))
        self.npc_route_wp_position,changed=Widgets.input3('Waypoint world XYZ',self.npc_route_wp_position,'%.3f')
        self.npc_route_wp_yaw=select(1,ImGui.InputFloat('Waypoint rotation yaw',self.npc_route_wp_yaw,5,15,'%.1f'))
        if ImGui.Button('SAVE WAYPOINT SETTINGS') then local value,err=app.actions:update_npc_route_waypoint({route_id=route.id,variant=self.npc_route_variant,waypoint_id=selected.id,patch={name=self.npc_route_wp_name,transform={position={x=self.npc_route_wp_position[1],y=self.npc_route_wp_position[2],z=self.npc_route_wp_position[3],w=1},rotation={roll=0,pitch=0,yaw=self.npc_route_wp_yaw}},wait_seconds=self.npc_route_wait,facing_yaw=self.npc_route_facing,speed=self.npc_route_speed,transition=self.npc_route_transition,workspot_location_id=self.npc_route_workspot,branch_fact=self.npc_route_branch_fact,branch_value=self.npc_route_branch_value,branch_target_id=self.npc_route_branch_target}});self:toast(err or (value and 'Saved waypoint') or 'Save failed') end
        ImGui.SameLine();if ImGui.Button('↑##routeup') then app.actions:move_npc_route_waypoint({route_id=route.id,variant=self.npc_route_variant,waypoint_id=selected.id,delta=-1}) end;ImGui.SameLine();if ImGui.Button('↓##routedown') then app.actions:move_npc_route_waypoint({route_id=route.id,variant=self.npc_route_variant,waypoint_id=selected.id,delta=1}) end;ImGui.SameLine();if ImGui.Button('DELETE WAYPOINT') then app.actions:delete_npc_route_waypoint({route_id=route.id,variant=self.npc_route_variant,waypoint_id=selected.id});self.npc_route_wp_edit_id='' end
    end
    if ImGui.Button('DELETE ROUTE') then app.actions:delete_npc_route(route.id);self.npc_route_id='';self.npc_route_wp_edit_id='';self:toast('Deleted route') end
end

function SpatialUI:draw_combat_encounters(premise)
    local app=self.app
    ImGui.Text('COMBAT ENCOUNTERS');ImGui.TextWrapped('Build encounter plans from persistent NPC records, enemy groups, waves, trigger/area volumes, faction relations, and quest facts. TEST spawns temporary NPCs; RESET removes those test entities.')
    if not premise then ImGui.TextDisabled('Select a location/premise first.');return end
    local encounters={};for _,enc in ipairs(app.model.data.combat_encounters or {}) do if enc.premise_id==premise.id then encounters[#encounters+1]=enc end end
    local selected=app.model:get_combat_encounter(self.combat_encounter_id)
    local function volume_combo(label,state_key)
        local id=self[state_key] or '';local title='None';for _,v in ipairs(app.model.data.volumes or {}) do if v.id==id then title=v.name end end
        if ImGui.BeginCombo(label,title) then
            if ImGui.Selectable('None',id=='') then self[state_key]='' end
            for _,v in ipairs(app.model.data.volumes or {}) do if v.premise_id==premise.id then if ImGui.Selectable(v.name..'##'..label..v.id,id==v.id) then self[state_key]=v.id end end end
            ImGui.EndCombo()
        end
    end
    if not selected then
        self.combat_name=select(1,ImGui.InputText('Encounter name',self.combat_name,128))
        volume_combo('Combat area volume','combat_area_volume');volume_combo('Default trigger volume','combat_trigger_volume')
        self.combat_activation_fact=select(1,ImGui.InputText('Encounter activation fact (optional)',self.combat_activation_fact,128))
        self.combat_activation_value=select(1,ImGui.InputInt('Activation fact value',self.combat_activation_value))
        if ImGui.Button('CREATE ENCOUNTER') then local enc,err=app.actions:create_combat_encounter({premise_id=premise.id,name=self.combat_name,area_volume_id=self.combat_area_volume,trigger_volume_id=self.combat_trigger_volume,activation_fact=self.combat_activation_fact,activation_value=self.combat_activation_value});if enc then self.combat_encounter_id=enc.id end;self:toast(err or (enc and 'Encounter created') or 'Create failed') end
    end
    local enc_title=selected and selected.name or 'Select an encounter'
    if ImGui.BeginCombo('Saved encounter',enc_title) then for _,enc in ipairs(encounters) do if ImGui.Selectable(enc.name..'##enc_'..enc.id,self.combat_encounter_id==enc.id) then self.combat_encounter_id=enc.id;self.combat_name=enc.name;self.combat_area_volume=enc.area_volume_id or '';self.combat_trigger_volume=enc.trigger_volume_id or '';self.combat_activation_fact=enc.activation_fact or '';self.combat_activation_value=enc.activation_value or 1;self.combat_reset_fact=enc.reset_fact or '';self.combat_reset_value=enc.reset_value or 0;self.combat_group_id='';self.combat_wave_id='';selected=enc end end;ImGui.EndCombo() end
    selected=app.model:get_combat_encounter(self.combat_encounter_id);if not selected then return end
    self.combat_name=select(1,ImGui.InputText('Edit encounter name##combat',self.combat_name,128))
    volume_combo('Combat area volume##combat','combat_area_volume');volume_combo('Default trigger volume##combat','combat_trigger_volume')
    self.combat_activation_fact=select(1,ImGui.InputText('Encounter activation fact##combat',selected.activation_fact or '',128))
    self.combat_activation_value=select(1,ImGui.InputInt('Encounter activation value##combat',selected.activation_value or 1))
    self.combat_reset_fact=select(1,ImGui.InputText('Encounter reset fact##combat',selected.reset_fact or '',128))
    self.combat_reset_value=select(1,ImGui.InputInt('Encounter reset value##combat',selected.reset_value or 0))
    if ImGui.Button('SAVE ENCOUNTER SETTINGS') then local value,err=app.actions:update_combat_encounter({id=selected.id,patch={name=self.combat_name,area_volume_id=self.combat_area_volume,trigger_volume_id=self.combat_trigger_volume,activation_fact=self.combat_activation_fact,activation_value=self.combat_activation_value,reset_fact=self.combat_reset_fact,reset_value=self.combat_reset_value}});self:toast(err or (value and 'Saved encounter settings') or 'Save failed') end
    ImGui.Separator();ImGui.Text('ENEMY GROUPS')
    local npc_title='Select saved NPC population';local npc=app.model:get_object(self.combat_npc_id);if npc then npc_title=npc.name or npc_title end
    if ImGui.BeginCombo('NPC record for group',npc_title) then for _,obj in ipairs(app.model.data.objects or {}) do if obj.premise_id==premise.id and obj.metadata and obj.metadata.npc_population then if ImGui.Selectable((obj.name or obj.metadata.npc_population.record)..'##combatnpc_'..obj.id,self.combat_npc_id==obj.id) then self.combat_npc_id=obj.id end end end;ImGui.EndCombo() end
    self.combat_group_name=select(1,ImGui.InputText('Enemy group name',self.combat_group_name,128));self.combat_group_faction=select(1,ImGui.InputText('Group faction',self.combat_group_faction,128))
    if ImGui.BeginCombo('Group attitude',self.combat_group_attitude) then for _,v in ipairs({'hostile','neutral','friendly'}) do if ImGui.Selectable(v,self.combat_group_attitude==v) then self.combat_group_attitude=v end end;ImGui.EndCombo() end
    if ImGui.Button('CREATE GROUP FROM SELECTED NPC') then local group,err=app.actions:create_encounter_group({encounter_id=selected.id,name=self.combat_group_name,faction=self.combat_group_faction,attitude=self.combat_group_attitude,npc_ids={self.combat_npc_id},spacing=self.combat_group_spacing});if group then self.combat_group_id=group.id end;self:toast(err or (group and 'Created enemy group') or 'Create failed') end
    local group_title='Select enemy group';for _,group in ipairs(selected.groups or {}) do if group.id==self.combat_group_id then group_title=group.name end end
    if ImGui.BeginCombo('Edit group',group_title) then for _,group in ipairs(selected.groups or {}) do if ImGui.Selectable(group.name..'##group'..group.id,self.combat_group_id==group.id) then self.combat_group_id=group.id;self.combat_group_name=group.name;self.combat_group_faction=group.faction or '';self.combat_group_attitude=group.attitude or 'hostile';self.combat_group_spacing=group.spacing or 1.5 end end;ImGui.EndCombo() end
    local group;for _,g in ipairs(selected.groups or {}) do if g.id==self.combat_group_id then group=g end end
    if group then
        self.combat_group_spacing=select(1,ImGui.InputFloat('Group spacing metres',self.combat_group_spacing,0.25,1,'%.2f'))
        ImGui.Text(string.format('%d NPC record(s) in this group',#(group.npc_ids or {})))
        if ImGui.Button('ADD SELECTED NPC TO GROUP') then local ids={};for _,id in ipairs(group.npc_ids or {}) do ids[#ids+1]=id end;if self.combat_npc_id~='' then ids[#ids+1]=self.combat_npc_id end;local value,err=app.actions:update_encounter_group({encounter_id=selected.id,group_id=group.id,patch={npc_ids=ids}});self:toast(err or (value and 'Added NPC record') or 'Update failed') end
        if ImGui.Button('SAVE GROUP SETTINGS') then local value,err=app.actions:update_encounter_group({encounter_id=selected.id,group_id=group.id,patch={name=self.combat_group_name,faction=self.combat_group_faction,attitude=self.combat_group_attitude,spacing=self.combat_group_spacing}});self:toast(err or (value and 'Saved group') or 'Save failed') end
        ImGui.SameLine();if ImGui.Button('DELETE GROUP') then app.actions:delete_encounter_group({encounter_id=selected.id,group_id=group.id});self.combat_group_id='';self:toast('Deleted group and removed it from waves') end
    end
    ImGui.Separator();ImGui.Text('WAVES & REINFORCEMENTS')
    self.combat_wave_name=select(1,ImGui.InputText('Wave name',self.combat_wave_name,128))
    if ImGui.BeginCombo('Wave activation',self.combat_wave_activation) then for _,v in ipairs({'immediate','volume','fact','after_wave'}) do if ImGui.Selectable(v,self.combat_wave_activation==v) then self.combat_wave_activation=v end end;ImGui.EndCombo() end
    volume_combo('Wave trigger volume','combat_wave_trigger')
    self.combat_wave_fact=select(1,ImGui.InputText('Wave activation fact',self.combat_wave_fact,128));self.combat_wave_value=select(1,ImGui.InputInt('Wave fact value',self.combat_wave_value));self.combat_wave_delay=select(1,ImGui.InputFloat('Reinforcement delay seconds',self.combat_wave_delay,1,5,'%.1f'))
    if self.combat_wave_activation=='after_wave' then local previous='Select previous wave';if self.combat_wave_after~='' then previous=self.combat_wave_after end;if ImGui.BeginCombo('Reinforce after',previous) then for _,w in ipairs(selected.waves or {}) do if ImGui.Selectable(w.name..'##after_'..w.id,self.combat_wave_after==w.id) then self.combat_wave_after=w.id end end;ImGui.EndCombo() end end
    local group_ids={};for _,g in ipairs(selected.groups or {}) do self.combat_wave_groups[g.id]=self.combat_wave_groups[g.id]~=false;local val,changed=ImGui.Checkbox('Include '..g.name..'##wavegroup_'..g.id,self.combat_wave_groups[g.id]);self.combat_wave_groups[g.id]=val;if val then group_ids[#group_ids+1]=g.id end end
    if ImGui.Button('CREATE WAVE') then local wave,err=app.actions:create_encounter_wave({encounter_id=selected.id,name=self.combat_wave_name,activation=self.combat_wave_activation,trigger_volume_id=self.combat_wave_trigger,fact_name=self.combat_wave_fact,fact_value=self.combat_wave_value,after_wave_id=self.combat_wave_after,delay_seconds=self.combat_wave_delay,group_ids=group_ids});if wave then self.combat_wave_id=wave.id end;self:toast(err or (wave and 'Created wave') or 'Create failed') end
    local wave_title='Select wave';for _,w in ipairs(selected.waves or {}) do if w.id==self.combat_wave_id then wave_title=w.name end end
    if ImGui.BeginCombo('Saved wave',wave_title) then for _,w in ipairs(selected.waves or {}) do if ImGui.Selectable(w.name..'##wave_'..w.id,self.combat_wave_id==w.id) then self.combat_wave_id=w.id;self.combat_wave_name=w.name;self.combat_wave_activation=w.activation;self.combat_wave_trigger=w.trigger_volume_id or '';self.combat_wave_fact=w.fact_name or '';self.combat_wave_value=w.fact_value or 1;self.combat_wave_after=w.after_wave_id or '';self.combat_wave_delay=w.delay_seconds or 0;self.combat_wave_groups={};for _,gid in ipairs(w.group_ids or {}) do self.combat_wave_groups[gid]=true end end end;ImGui.EndCombo() end
    local wave;for _,w in ipairs(selected.waves or {}) do if w.id==self.combat_wave_id then wave=w end end
    if wave then
        if ImGui.Button('SAVE WAVE SETTINGS') then local value,err=app.actions:update_encounter_wave({encounter_id=selected.id,wave_id=wave.id,patch={name=self.combat_wave_name,activation=self.combat_wave_activation,trigger_volume_id=self.combat_wave_trigger,fact_name=self.combat_wave_fact,fact_value=self.combat_wave_value,after_wave_id=self.combat_wave_after,delay_seconds=self.combat_wave_delay,group_ids=group_ids}});self:toast(err or (value and 'Saved wave') or 'Save failed') end
        ImGui.SameLine();if ImGui.Button('DELETE WAVE') then app.actions:delete_encounter_wave({encounter_id=selected.id,wave_id=wave.id});self.combat_wave_id='';self:toast('Deleted wave') end
    end
    ImGui.Separator();ImGui.Text('FACTION RELATIONSHIPS')
    self.combat_relation_source=select(1,ImGui.InputText('Source faction',self.combat_relation_source,128));self.combat_relation_target=select(1,ImGui.InputText('Target faction',self.combat_relation_target,128))
    if ImGui.BeginCombo('Relation attitude',self.combat_relation_attitude) then for _,v in ipairs({'hostile','neutral','friendly'}) do if ImGui.Selectable(v,self.combat_relation_attitude==v) then self.combat_relation_attitude=v end end;ImGui.EndCombo() end
    if ImGui.Button('SET FACTION RELATION') then local value,err=app.actions:set_encounter_faction_relation({encounter_id=selected.id,source_faction=self.combat_relation_source,target_faction=self.combat_relation_target,attitude=self.combat_relation_attitude});self:toast(err or (value and 'Saved faction relation') or 'Save failed') end
    for _,relation in ipairs(selected.faction_relations or {}) do ImGui.Text(relation.source_faction..' → '..relation.target_faction..': '..relation.attitude) end
    ImGui.Separator()
    if ImGui.Button('TEST SELECTED WAVE') then local result,err=app.actions:test_combat_encounter(selected.id,self.combat_wave_id~='' and self.combat_wave_id or nil);self:toast(err or (result and ('Spawned '..result.count..' temporary NPCs')) or 'Test failed') end
    ImGui.SameLine();if ImGui.Button('RESET TEST ENCOUNTER') then local result,err=app.actions:reset_combat_encounter(selected.id);self:toast(err or (result and 'Removed temporary encounter NPCs') or 'Reset failed') end
    ImGui.SameLine();if ImGui.Button('DELETE ENCOUNTER') then app.actions:delete_combat_encounter(selected.id);self.combat_encounter_id='';self:toast('Deleted encounter') end
    ImGui.TextWrapped('Quest trigger activation, reinforcement scheduling, faction reactions, combat AI and reset facts are exported handoff data. The Test button only spawns temporary Character records at their saved positions.')
end

function SpatialUI:draw_population(premise)
    local app=self.app
    ImGui.Text('NPC POPULATION')
    ImGui.TextWrapped('Creates a native World Builder Entity Record node (worldPopulationSpawnerNode). Runtime preview is temporary; spawn-on-start is saved into the exported game node.')
    self.population_search=select(1,ImGui.InputText('Search Character records',self.population_search,128))
    ImGui.SameLine()
    if ImGui.Button('SEARCH RECORDS') then
        local result,err=app.world_builder:search('entity_record',self.population_search,80,true)
        self.population_results=result and result.items or {};if err then self:toast(err) end
    end
    ImGui.BeginChild('##population_records',0,130,true)
    for _,resource in ipairs(self.population_results or {}) do
        if tostring(resource.path or ''):match('^Character%.[%w_%.%-]+$') then
        ImGui.PushID(tostring(resource.path))
        ImGui.Text(resource.name..'  '..tostring(resource.path))
        ImGui.SameLine()
        if ImGui.SmallButton('IMPORT + SELECT') then
            local asset,err=app.world_builder:import_resource(resource)
            if asset then self.population_asset_id=asset.id;self.population_name=resource.name;self:toast('Selected '..resource.path) else self:toast(err or 'Record import failed') end
        end
        ImGui.PopID()
        end
    end
    ImGui.EndChild()
    local asset=self.population_asset_id~='' and app.model:get_asset(self.population_asset_id) or nil
    ImGui.Text('Selected: '..(asset and (asset.name..' — '..asset.template) or 'choose an Entity Record above'))
    self.population_name=select(1,ImGui.InputText('Population point name',self.population_name,128))
    self.population_appearance=select(1,ImGui.InputText('Appearance override',self.population_appearance,128))
    self.population_attitude=select(1,ImGui.InputText('Attitude profile (handoff)',self.population_attitude,128))
    self.population_faction=select(1,ImGui.InputText('Faction (handoff)',self.population_faction,128))
    self.population_level=select(1,ImGui.InputInt('Level override (0 = record default)',self.population_level))
    self.population_archetype=select(1,ImGui.InputText('Archetype (handoff)',self.population_archetype,128))
    self.population_idle=select(1,ImGui.InputText('Idle behavior (handoff)',self.population_idle,128))
    self.population_despawn=select(1,ImGui.InputFloat('Despawn distance (handoff)',self.population_despawn,1,10,'%.1f'))
    self.population_fact=select(1,ImGui.InputText('Required quest fact (optional handoff)',self.population_fact,128))
    self.population_fact_value=select(1,ImGui.InputInt('Required fact value',self.population_fact_value))
    self.population_primary=select(1,ImGui.InputFloat('WB primary streaming range',self.population_primary,5,25,'%.1f'))
    self.population_secondary=select(1,ImGui.InputFloat('WB secondary streaming range',self.population_secondary,5,25,'%.1f'))
    self.population_always=select(1,ImGui.Checkbox('Always spawned (disable normal culling)',self.population_always))
    self.population_spawn_on_start=select(1,ImGui.Checkbox('Spawn on start',self.population_spawn_on_start))
    local function create(transform)
        if not asset then self:toast('Import a World Builder Entity Record first');return end
        local conditions={}
        if self.population_fact~='' then conditions={{fact_name=self.population_fact,fact_value=self.population_fact_value}} end
        local object,err=app.actions:create_npc_population({asset_id=asset.id,name=self.population_name,appearance=self.population_appearance,
            attitude=self.population_attitude,faction=self.population_faction,level=self.population_level,archetype=self.population_archetype,
            idle_behavior=self.population_idle,despawn_distance=self.population_despawn,conditions=conditions,
            always_spawned=self.population_always,spawn_on_start=self.population_spawn_on_start,primary_range=self.population_primary,secondary_range=self.population_secondary,
            transform=transform,source='player',premise_id=premise.id,room_id=app.selected_room_id,preview=true})
        self:toast(err or (object and 'Saved persistent Character spawn point and requested temporary preview' or 'Population point failed'))
    end
    if ImGui.Button('CREATE AT PLAYER + PREVIEW',230,30) then local transform,err=app.game:capture_transform();if transform then create(transform) else self:toast(err or 'Player transform unavailable') end end
    ImGui.SameLine()
    if ImGui.Button('CREATE AT AIM',150,30) then local hit,err=app.game:aim_point(self.aim_distance);if hit then create({position=hit.position,rotation={roll=0,pitch=0,yaw=0}}) else self:toast(err or 'Aim point unavailable') end end
    ImGui.Separator();ImGui.Text('SAVED POPULATION POINTS')
    ImGui.BeginChild('##population_points',0,155,true)
    for _,object in ipairs(app.model.data.objects or {}) do
        local cfg=object.metadata and object.metadata.npc_population
        if cfg then
            if ImGui.Selectable((object.name or cfg.record)..'  ['..tostring(cfg.record)..']##'..object.id,self.population_edit_id==object.id) then self.population_edit_id=object.id end
        end
    end
    ImGui.EndChild()
    local selected=self.population_edit_id and app.model:get_object(self.population_edit_id)
    if selected and selected.metadata and selected.metadata.npc_population then
        local cfg=selected.metadata.npc_population
        if self.population_edit_for~=selected.id then
            self.population_edit_for=selected.id
            local condition=cfg.conditions and cfg.conditions[1] or {}
            self.population_edit={appearance=cfg.appearance or '',attitude=cfg.attitude or '',faction=cfg.faction or '',level=tonumber(cfg.level) or 0,
                archetype=cfg.archetype or '',idle_behavior=cfg.idle_behavior or '',despawn_distance=tonumber(cfg.despawn_distance) or 0,
                condition_fact=condition.fact_name or '',condition_value=tonumber(condition.fact_value) or 1,
                always_spawned=cfg.always_spawned==true,spawn_on_start=cfg.spawn_on_start~=false,primary_range=tonumber(cfg.primary_range) or 100,secondary_range=tonumber(cfg.secondary_range) or 120}
        end
        local edit=self.population_edit
        ImGui.Text('Edit persistent point: '..tostring(cfg.record))
        edit.appearance=select(1,ImGui.InputText('Appearance override##popedit',edit.appearance,128))
        edit.attitude=select(1,ImGui.InputText('Attitude profile##popedit',edit.attitude,128))
        edit.faction=select(1,ImGui.InputText('Faction##popedit',edit.faction,128))
        edit.level=select(1,ImGui.InputInt('Level override##popedit',edit.level))
        edit.archetype=select(1,ImGui.InputText('Archetype##popedit',edit.archetype,128))
        edit.idle_behavior=select(1,ImGui.InputText('Idle behavior##popedit',edit.idle_behavior,128))
        edit.despawn_distance=select(1,ImGui.InputFloat('Despawn distance##popedit',edit.despawn_distance,1,10,'%.1f'))
        edit.condition_fact=select(1,ImGui.InputText('Required quest fact##popedit',edit.condition_fact,128))
        edit.condition_value=select(1,ImGui.InputInt('Required fact value##popedit',edit.condition_value))
        edit.always_spawned=select(1,ImGui.Checkbox('Always spawned##popedit',edit.always_spawned))
        edit.spawn_on_start=select(1,ImGui.Checkbox('Spawn on start##popedit',edit.spawn_on_start))
        edit.primary_range=select(1,ImGui.InputFloat('WB primary range##popedit',edit.primary_range,5,25,'%.1f'))
        edit.secondary_range=select(1,ImGui.InputFloat('WB secondary range##popedit',edit.secondary_range,5,25,'%.1f'))
        if ImGui.Button('SAVE POPULATION SETTINGS') then
            local conditions=edit.condition_fact~='' and {{fact_name=edit.condition_fact,fact_value=edit.condition_value}} or {}
            local updated,err=app.actions:update_npc_population(selected.id,{appearance=edit.appearance,attitude=edit.attitude,faction=edit.faction,
                level=edit.level,archetype=edit.archetype,idle_behavior=edit.idle_behavior,despawn_distance=edit.despawn_distance,
                conditions=conditions,always_spawned=edit.always_spawned,spawn_on_start=edit.spawn_on_start,primary_range=edit.primary_range,secondary_range=edit.secondary_range})
            self:toast(err or (updated and 'Saved native spawn settings and profile handoff' or 'Save failed'))
        end
        ImGui.SameLine()
        if ImGui.Button('REFRESH LIVE PREVIEW') then local _,err=app.placement:refresh(selected);self:toast(err or 'Preview refreshed') end
        ImGui.SameLine()
        if ImGui.Button('DELETE POPULATION POINT') then app.selection:set('object',selected.id);local ok,err=app.actions:delete_selected();self.population_edit_id=nil;self:toast(ok and 'Population point deleted' or err) end
    end
end

function SpatialUI:draw_volumes(premise)
    local app=self.app
    ImGui.Text('TRIGGER / GAMEPLAY VOLUMES')
    self.volume_name=select(1,ImGui.InputText('Volume name',self.volume_name,128))
    self.volume_purpose=select(1,ImGui.InputText('Purpose',self.volume_purpose,64))
    self.volume_fact_name=select(1,ImGui.InputText('Quest Forge fact (optional)',self.volume_fact_name,128))
    if ImGui.BeginCombo('Shape',self.volume_shape) then for _,shape in ipairs({'box','sphere','cylinder'}) do if ImGui.Selectable(shape,self.volume_shape==shape) then self.volume_shape=shape end end;ImGui.EndCombo() end
    self.volume_size=select(1,Widgets.input3('Box size XYZ',self.volume_size,'%.2f'))
    self.volume_radius=select(1,ImGui.InputFloat('Radius',self.volume_radius,0.1,1,'%.2f'))
    self.volume_height=select(1,ImGui.InputFloat('Cylinder height',self.volume_height,0.1,1,'%.2f'))
    if ImGui.Button('CREATE AT PLAYER',160,30) then
        local transform,err=app.game:capture_transform()
        if transform then local item,e=app.actions:create_volume({premise_id=premise.id,room_id=app.selected_room_id,name=self.volume_name,purpose=self.volume_purpose,shape=self.volume_shape,transform=transform,size_x=self.volume_size[1],size_y=self.volume_size[2],size_z=self.volume_size[3],radius=self.volume_radius,height=self.volume_shape=='cylinder' and self.volume_height or self.volume_size[3],source='ui:player'});if item and self.volume_fact_name~='' then item.metadata.questforge={fact_name=self.volume_fact_name,value=1};app:mark_dirty() end;self:toast(e or (item and ('Created '..item.name) or 'Create failed')) else self:toast(err) end
    end
    ImGui.SameLine()
    if ImGui.Button('CREATE AT AIM',150,30) then
        local hit,err=app.game:aim_point(self.aim_distance)
        if hit then local transform={position=hit.position,rotation={roll=0,pitch=0,yaw=0}};local item,e=app.actions:create_volume({premise_id=premise.id,room_id=app.selected_room_id,name=self.volume_name,purpose=self.volume_purpose,shape=self.volume_shape,transform=transform,size_x=self.volume_size[1],size_y=self.volume_size[2],size_z=self.volume_size[3],radius=self.volume_radius,height=self.volume_shape=='cylinder' and self.volume_height or self.volume_size[3],source='ui:'..hit.source});if item and self.volume_fact_name~='' then item.metadata.questforge={fact_name=self.volume_fact_name,value=1};app:mark_dirty() end;self:toast(e or (item and ('Created via '..hit.source) or 'Create failed')) else self:toast(err) end
    end
    ImGui.Separator();ImGui.BeginChild('##volume_list',260,220,true)
    for _,item in ipairs(app.model.data.volumes) do if item.premise_id==premise.id then if ImGui.Selectable(item.name..'##'..item.id,app.selection:is('volume',item.id)) then app.selection:set('volume',item.id) end end end
    ImGui.EndChild();ImGui.SameLine();ImGui.BeginChild('##volume_edit',0,220,true)
    local item=app.model:get_volume(app.selected_volume_id)
    if item then
        ImGui.Text(item.name);local changed
        item.metadata=item.metadata or {};item.metadata.questforge=item.metadata.questforge or {}
        item.metadata.questforge.fact_name,changed=ImGui.InputText('Linked Quest Forge fact##volume',item.metadata.questforge.fact_name or '',128);if changed then app:mark_dirty() end
        ImGui.TextDisabled('This records the intended quest link; export it and wire the trigger event in quest flow.')
        local p={item.transform.position.x,item.transform.position.y,item.transform.position.z};p,changed=Widgets.input3('World XYZ##volume',p,'%.3f');if changed then item.transform.position.x=p[1];item.transform.position.y=p[2];item.transform.position.z=p[3];app:mark_dirty() end
        if item.shape=='box' then local s={item.size.x,item.size.y,item.size.z};s,changed=Widgets.input3('Size XYZ##volume',s,'%.2f');if changed then item.size.x=s[1];item.size.y=s[2];item.size.z=s[3];app:mark_dirty() end
        else item.radius,changed=ImGui.InputFloat('Radius##volume',item.radius,0.1,1,'%.2f');if changed then app:mark_dirty() end end
        if ImGui.Button('SNAP VOLUME') then app.authoring:snap_item('volume',item.id) end;ImGui.SameLine()
        if ImGui.Button('DELETE VOLUME') then app.selection:set('volume',item.id);local ok,err=app.actions:delete_selected();self:toast(ok and 'Volume deleted' or err) end
    else ImGui.TextDisabled('Select a volume.') end
    ImGui.EndChild()
end

function SpatialUI:draw_cameras(premise)
    local app=self.app
    ImGui.Text('CAMERA + LOOK-AT AUTHORING')
    self.camera_name=select(1,ImGui.InputText('Camera name',self.camera_name,128))
    self.camera_fov=select(1,ImGui.InputFloat('FOV',self.camera_fov,1,5,'%.1f'))
    self.camera_duration=select(1,ImGui.InputFloat('Duration',self.camera_duration,0.1,1,'%.1f'))
    self.aim_distance=select(1,ImGui.InputFloat('Aim distance',self.aim_distance,0.5,5,'%.1f'))
    if ImGui.Button('CAPTURE PLAYER CAMERA',210,32) then
        local camera,err=app.actions:create_camera({premise_id=premise.id,room_id=app.selected_room_id,name=self.camera_name,fov=self.camera_fov,duration=self.camera_duration,distance=self.aim_distance})
        self:toast(err or (camera and ('Captured '..camera.name) or 'Capture failed'))
    end
    ImGui.Separator();ImGui.BeginChild('##camera_list',260,240,true)
    for _,item in ipairs(app.model.data.cameras) do if item.premise_id==premise.id then if ImGui.Selectable(item.name..'##'..item.id,app.selection:is('camera',item.id)) then app.selection:set('camera',item.id) end end end
    ImGui.EndChild();ImGui.SameLine();ImGui.BeginChild('##camera_edit',0,240,true)
    local camera=app.model:get_camera(app.selected_camera_id)
    if camera then
        ImGui.Text(camera.name);local changed
        local p={camera.transform.position.x,camera.transform.position.y,camera.transform.position.z};p,changed=Widgets.input3('Camera world XYZ',p,'%.3f');if changed then camera.transform.position.x=p[1];camera.transform.position.y=p[2];camera.transform.position.z=p[3];app.authoring:set_camera_look_at(camera.id,camera.look_at) end
        local look={camera.look_at.x,camera.look_at.y,camera.look_at.z};look,changed=Widgets.input3('Look-at XYZ',look,'%.3f');if changed then app.authoring:set_camera_look_at(camera.id,{x=look[1],y=look[2],z=look[3]}) end
        camera.fov,changed=ImGui.SliderFloat('FOV##camera',camera.fov,10,120,'%.1f');if changed then app:mark_dirty() end
        if ImGui.Button('LOOK AT PLAYER') then local t=app.game:capture_transform();if t then app.authoring:set_camera_look_at(camera.id,t.position) end end
        ImGui.SameLine();if ImGui.Button('PREVIEW') then local _,err=app.authoring:preview_camera(camera.id);self:toast(err or 'Teleported to camera') end
        ImGui.SameLine();if ImGui.Button('SNAP CAMERA') then app.authoring:snap_item('camera',camera.id) end
        ImGui.SameLine();if ImGui.Button('DELETE CAMERA') then app.selection:set('camera',camera.id);local ok,err=app.actions:delete_selected();self:toast(ok and 'Camera deleted' or err) end
    else ImGui.TextDisabled('Select a camera.') end
    ImGui.EndChild()
end

function SpatialUI:draw_markers(premise)
    local app=self.app;local settings=app.model.data.settings.visuals;local changed
    settings.enabled,changed=ImGui.Checkbox('Enable in-world authoring markers',settings.enabled);if changed then app:mark_dirty() end
    settings.marker_template,changed=ImGui.InputText('Marker .ent template',settings.marker_template or '',512);if changed then app:mark_dirty() end
    settings.marker_appearance,changed=ImGui.InputText('Marker appearance',settings.marker_appearance or '',128);if changed then app:mark_dirty() end
    settings.max_distance,changed=ImGui.InputFloat('Marker distance',settings.max_distance,5,20,'%.1f');if changed then app:mark_dirty() end
    if ImGui.Button('REFRESH MARKERS',170,30) then local result=app.markers:refresh(premise.id);self:toast(result.skipped or string.format('Spawned %d markers; %d failed',result.spawned,#result.failed)) end
    ImGui.SameLine();if ImGui.Button('CLEAR MARKERS',150,30) then app.markers:clear();self:toast('Markers cleared') end
    ImGui.TextWrapped('Markers use one configurable .ent template and are transient. The visual floorplan remains available without a marker asset.')
end

function SpatialUI:draw_mesh_appearance()
    local app=self.app
    ImGui.Text('MESH APPEARANCE')
    ImGui.TextWrapped('Select a spawned static mesh. Variants come from that live World Builder mesh; preview changes the in-game component and does not save until Apply.')
    local meshes={}
    for _,object in ipairs(app.model.data.objects or {}) do
        local wb=object.metadata and object.metadata.world_builder
        if wb and wb.definition_key=='mesh_static' then meshes[#meshes+1]=object end
    end
    if #meshes==0 then ImGui.TextDisabled('No World Builder static meshes in this project.')
    else
        local selected=app.model:get_object(app.selected_object_id)
        local label=selected and selected.name or 'Select placed mesh'
        if ImGui.BeginCombo('Placed mesh##appearance',label) then
            for _,object in ipairs(meshes) do if ImGui.Selectable(object.name..'##appearance_'..object.id,object.id==app.selected_object_id) then app.selection:set('object',object.id);self.mesh_appearances=nil end end
            ImGui.EndCombo()
        end
        if ImGui.Button('LOAD VARIANTS') then
            local result,err=app.mesh_appearance:list()
            if result then self.mesh_appearances=result;self.mesh_appearance_error=nil else self.mesh_appearance_error=err end
        end
        if self.mesh_appearance_error then ImGui.TextWrapped(self.mesh_appearance_error) end
        if self.mesh_appearances then
            ImGui.Text(('Resource: %s'):format(self.mesh_appearances.resource or 'unknown'))
            ImGui.Text(('Current: %s'):format(self.mesh_appearances.current~='' and self.mesh_appearances.current or '(default)'))
            if #self.mesh_appearances.appearances==0 then ImGui.TextDisabled('World Builder reports no named appearances for this mesh.') end
            for _,appearance in ipairs(self.mesh_appearances.appearances) do
                if ImGui.Selectable(appearance..'##mesh_app',false) then
                    local _,err=app.mesh_appearance:preview({appearance=appearance});self:toast(err or ('Previewing '..appearance))
                end
            end
            if ImGui.Button('APPLY PREVIEW') then
                local object=app.model:get_object(app.selected_object_id);local preview=object and app.mesh_appearance.preview_state[object.id]
                if preview then local result,err=app.mesh_appearance:apply({appearance=preview.current});self:toast(err or (result and 'Appearance saved to project' or 'Apply failed'))
                else self:toast('Choose a variant first') end
            end
            ImGui.SameLine()
            if ImGui.Button('REVERT PREVIEW') then local _,err=app.mesh_appearance:cancel({});self:toast(err or 'Original appearance restored') end
        end
    end
    ImGui.Separator();ImGui.Text('PLACE GAME DECAL')
    ImGui.TextWrapped('Searches World Builder’s loaded Decals catalog for real .mi materials, then creates a worldStaticDecalNode at the camera ray hit.')
    self.mesh_decal_search=select(1,ImGui.InputText('Decal material search',self.mesh_decal_search,200))
    if ImGui.Button('SEARCH DECAL CATALOG') then
        local results,err=app.world_builder:search('decal',self.mesh_decal_search,40,true)
        if results then self.mesh_decal_results=results.items;self.mesh_decal_selected=nil;self.mesh_appearance_error=nil
        else self.mesh_appearance_error=err end
    end
    if self.mesh_appearance_error then ImGui.TextWrapped(self.mesh_appearance_error) end
    if self.mesh_decal_results then
        ImGui.BeginChild('##decal_catalog_results',0,130,true)
        for _,resource in ipairs(self.mesh_decal_results) do
            if ImGui.Selectable(resource.name..' — '..resource.path..'##decal_resource',self.mesh_decal_selected==resource.path) then
                self.mesh_decal_selected=resource.path;self.mesh_decal_name=resource.name..' Decal'
            end
        end
        ImGui.EndChild()
    end
    self.mesh_decal_name=select(1,ImGui.InputText('Decal name',self.mesh_decal_name,128))
    self.mesh_decal_width=select(1,ImGui.InputFloat('Width (m)##decal',self.mesh_decal_width,0.1,1,'%.2f'))
    self.mesh_decal_height=select(1,ImGui.InputFloat('Height (m)##decal',self.mesh_decal_height,0.1,1,'%.2f'))
    self.mesh_decal_alpha=select(1,ImGui.SliderFloat('Alpha##decal',self.mesh_decal_alpha,0,1,'%.2f'))
    if ImGui.Button('PLACE DECAL AT AIM') then
        if not self.mesh_decal_selected then self:toast('Search the catalog and select a decal material first')
        else
        local result,err=app.mesh_appearance:create_decal({query=self.mesh_decal_search,resource_path=self.mesh_decal_selected,name=self.mesh_decal_name,width=self.mesh_decal_width,height=self.mesh_decal_height,alpha=self.mesh_decal_alpha,source='aim'})
        if result then self:toast(result.spawn_error and ('Saved; live spawn failed: '..result.spawn_error) or ('Placed '..result.object.name)) else self:toast(err or 'Decal placement failed') end
        end
    end
end

function SpatialUI:draw_workspots(premise)
    local app=self.app
    ImGui.Text('NPC WORKSPOTS')
    ImGui.TextWrapped('Save a sit, lean, or terminal point. Preview spawns a temporary NPC stand-in at the saved transform; it does not modify an existing NPC.')
    self.workspot_name=select(1,ImGui.InputText('Workspot name',self.workspot_name,128))
    if ImGui.BeginCombo('Workspot kind',self.workspot_kind) then for _,kind in ipairs({'sit','lean','terminal'}) do if ImGui.Selectable(kind,self.workspot_kind==kind) then self.workspot_kind=kind end end;ImGui.EndCombo() end
    ImGui.TextDisabled('Optional AMM preview setup (copy exact values from npc_animations_search).')
    self.workspot_record=select(1,ImGui.InputText('NPC record',self.workspot_record,256))
    self.workspot_appearance=select(1,ImGui.InputText('Appearance (optional)',self.workspot_appearance,128))
    self.workspot_anim=select(1,ImGui.InputText('AMM animation name',self.workspot_anim,128))
    self.workspot_rig=select(1,ImGui.InputText('AMM rig',self.workspot_rig,128))
    self.workspot_comp=select(1,ImGui.InputText('AMM component',self.workspot_comp,256))
    self.workspot_ent=select(1,ImGui.InputText('AMM workspot .ent',self.workspot_ent,512))
    local function create(transform,err)
        if not transform then self:toast(err or 'Could not get a placement transform');return end
        local item=app.model:add_location({name=self.workspot_name,type='workspot',category='NPC Workspots',tags={'npc',self.workspot_kind},radius=0.5,transform=transform,metadata={source='ui:npc_workspot:'..self.workspot_kind,workspot={kind=self.workspot_kind,record=self.workspot_record,appearance=self.workspot_appearance,animation={name=self.workspot_anim,rig=self.workspot_rig,comp=self.workspot_comp,ent=self.workspot_ent}}}})
        if not item then self:toast('Workspot was not saved');return end
        app.selection:set('location',item.id);app:mark_dirty();self:toast('Saved '..item.name)
    end
    if ImGui.Button('PLACE AT PLAYER',155,30) then local t,e=app.game:capture_transform();create(t,e) end
    ImGui.SameLine()
    if ImGui.Button('PLACE AT AIM',145,30) then local hit,e=app.game:aim_point(self.aim_distance);if hit then create({position=hit.position,rotation={roll=0,pitch=0,yaw=0}},nil) else self:toast(e or 'Aim point unavailable') end end
    ImGui.Separator();ImGui.BeginChild('##workspot_list',240,245,true)
    for _,item in ipairs(app.model.data.locations) do if item.metadata and item.metadata.workspot then if ImGui.Selectable(item.name..'##'..item.id,app.selection:is('location',item.id)) then app.selection:set('location',item.id) end end end
    ImGui.EndChild();ImGui.SameLine();ImGui.BeginChild('##workspot_edit',0,245,true)
    local item=app.model:get_location(app.selected_location_id)
    if item and item.metadata and item.metadata.workspot then
        local meta=item.metadata.workspot;meta.animation=meta.animation or {};local changed
        item.name,changed=ImGui.InputText('Selected workspot name',item.name,128);if changed then app:mark_dirty() end
        local p={item.transform.position.x,item.transform.position.y,item.transform.position.z};p,changed=Widgets.input3('Workspot world XYZ',p,'%.3f');if changed then item.transform.position.x=p[1];item.transform.position.y=p[2];item.transform.position.z=p[3];app:mark_dirty() end
        item.transform.rotation.yaw,changed=ImGui.InputFloat('Yaw##workspot',item.transform.rotation.yaw,1,5,'%.1f');if changed then app:mark_dirty() end
        local a=meta.animation
        a.name,changed=ImGui.InputText('Animation name##workspot',a.name or '',128);if changed then app:mark_dirty() end
        a.rig,changed=ImGui.InputText('Rig##workspot',a.rig or 'Woman Average',128);if changed then app:mark_dirty() end
        a.comp,changed=ImGui.InputText('Component##workspot',a.comp or '',256);if changed then app:mark_dirty() end
        a.ent,changed=ImGui.InputText('Workspot .ent##workspot',a.ent or '',512);if changed then app:mark_dirty() end
        meta.record,changed=ImGui.InputText('Preview NPC record##workspot',meta.record or '',256);if changed then app:mark_dirty() end
        meta.appearance,changed=ImGui.InputText('Preview appearance##workspot',meta.appearance or '',128);if changed then app:mark_dirty() end
        if ImGui.Button('PREVIEW TEMP NPC',180,30) then
            if not meta.record or meta.record=='' then self:toast('Enter a valid NPC TweakDB record first')
            elseif not a.name or a.name=='' or not a.comp or a.comp=='' or not a.ent or a.ent=='' then self:toast('Enter exact AMM animation, component and .ent values first')
            else local result,err=app.live_tools:preview_workspot({record=meta.record,appearance=meta.appearance,position=item.transform.position,yaw=item.transform.rotation.yaw,anim=a});self:toast(err or (result and ('NPC spawn requested ('..result.key..'); animation starts after it loads') or 'Preview failed')) end
        end
        ImGui.SameLine()
        if ImGui.Button('CHECK APPROACH',155,30) then local result,err=app.live_tools:workspot_approach({position=item.transform.position,target='crosshair'});if not result then self:toast(err) else self:toast(result.status..' — '..result.caveat) end end
        ImGui.TextDisabled('Approach check is a 3-ray collision hint from the NPC under your crosshair; it cannot prove AI navmesh reachability.')
        if ImGui.Button('DELETE WORKSPOT') then app.selection:set('location',item.id);local ok,err=app.actions:delete_selected();self:toast(ok and 'Workspot deleted' or err) end
    else ImGui.TextDisabled('Select a saved NPC workspot.') end
    ImGui.EndChild()
end

function SpatialUI:draw_walkability()
    local app=self.app
    ImGui.Text('WALKABILITY / BLOCKER SCAN')
    ImGui.TextWrapped('Samples floor support and actor clearance on a bounded grid between the live actor and a goal point. Dynamic collision hits may be props blocking the route.')
    if ImGui.BeginCombo('Actor to check',self.walk_actor) then for _,kind in ipairs({'player','npc'}) do if ImGui.Selectable(kind,self.walk_actor==kind) then self.walk_actor=kind end end;ImGui.EndCombo() end
    self.walk_goal=select(1,Widgets.input3('Goal world XYZ',self.walk_goal,'%.2f'))
    self.walk_grid_step=select(1,ImGui.InputFloat('Grid spacing (m)',self.walk_grid_step,0.1,0.25,'%.2f'))
    self.walk_margin=select(1,ImGui.InputFloat('Detour search margin (m)',self.walk_margin,0.5,1,'%.1f'))
    if ImGui.Button('SET GOAL FROM AIM',180,30) then
        local hit,err=app.game:aim_point(40)
        if hit then self.walk_goal={hit.position.x,hit.position.y,hit.position.z};self:toast('Goal set from '..tostring(hit.source)) else self:toast(err or 'Aim point unavailable') end
    end
    ImGui.SameLine()
    if ImGui.Button('CHECK LIVE ROUTE',180,30) then
        local args={actor=self.walk_actor,goal={x=self.walk_goal[1],y=self.walk_goal[2],z=self.walk_goal[3]},grid_step=self.walk_grid_step,margin=self.walk_margin}
        if self.walk_actor=='npc' then args.target='crosshair' end
        local result,err=app.live_tools:walkability_check(args)
        self.walk_result=result
        self:toast(err or (result and ('Walkability: '..result.status) or 'Walkability check failed'))
    end
    local r=self.walk_result
    if r then
        ImGui.Separator();ImGui.Text('Result: '..tostring(r.status));ImGui.TextWrapped(tostring(r.caveat or r.reason or ''))
        if r.sampled_cells then ImGui.Text(string.format('Grid: %d cells; %d floor-supported; route: %d cells / %.1f m',r.sampled_cells,r.floor_supported_cells or 0,r.path_cells or 0,r.path_length or 0)) end
        if r.blockers and #r.blockers>0 then
            ImGui.Text('Potential collision blockers (world position / group):')
            for i,hit in ipairs(r.blockers) do ImGui.Text(string.format('%02d  %.2f, %.2f, %.2f  [%s]',i,hit.x,hit.y,hit.z,hit.group or '?')) end
        elseif r.sampled_cells then ImGui.Text('No sampled clearance hits.') end
        ImGui.TextDisabled('Navmesh: '..tostring(r.navmesh_status or 'not queried'))
    end
end

function SpatialUI:draw_navigation()
    local app=self.app;local nav=app.navigation
    ImGui.Text('IMPORTED NAVIGATION GRAPH')
    ImGui.TextWrapped('Import a portable graph with the LocationStudio MCP tool. Nodes and door/stair/off-mesh links are displayed here. Reachability is evaluated only against that imported graph; live REDengine AI navigation is not exposed by this mod.')
    if not nav then ImGui.TextDisabled('Navigation module unavailable.');return end
    local graphs=nav:list();local label='Select graph';for _,g in ipairs(graphs) do if g.id==self.nav_graph_id then label=g.name end end
    if ImGui.BeginCombo('Graph',label) then for _,g in ipairs(graphs) do if ImGui.Selectable(g.name..'##nav_'..g.id,self.nav_graph_id==g.id) then self.nav_graph_id=g.id;self.nav_result=nil;self.nav_workspots=nil end end;ImGui.EndCombo() end
    local graph;for _,g in ipairs(graphs) do if g.id==self.nav_graph_id then graph=g end end
    if not graph then ImGui.TextDisabled('No graph selected. Import one with navigation_graph_import through MCP.');return end
    ImGui.Text(string.format('%s  |  %d nodes  |  %d links  |  %d surface polygons  |  %s',graph.name,#graph.nodes,#graph.edges,#(graph.polygons or {}),tostring(graph.source_format)))
    ImGui.TextDisabled('Source: '..tostring(graph.source)..'   Imported '..tostring(graph.imported_at)..'   REDengine query: unavailable')
    if ImGui.Button('CHECK WORKSPOTS FROM PLAYER',230,30) then
        local t,err=app.game:capture_transform();if t then self.nav_workspots,err=nav:workspot_report({graph_id=graph.id,start=t.position,snap_distance=self.nav_snap_distance}) end
        self:toast(err or (self.nav_workspots and 'Workspot graph checks complete') or 'Could not capture player position')
    end
    self.nav_snap_distance=select(1,ImGui.InputFloat('Endpoint snap distance (m)',self.nav_snap_distance,0.25,1,'%.2f'))
    if self.nav_workspots then
        ImGui.Text('Workspot status (imported graph only):')
        for _,item in ipairs(self.nav_workspots.workspots or {}) do ImGui.Text(string.format('%s  —  %s',item.name,item.status)) end
        if #(self.nav_workspots.workspots or {})==0 then ImGui.TextDisabled('No saved workspots.') end
    end
    ImGui.Separator();ImGui.Text('NAVDATA NODES (world coordinates)')
    ImGui.BeginChild('##nav_nodes',0,190,true)
    for i,n in ipairs(graph.nodes) do if i<=300 then local p=n.position;ImGui.Text(string.format('%s  [%.2f, %.2f, %.2f]',n.name,p.x,p.y,p.z)) end end
    if #graph.nodes>300 then ImGui.TextDisabled('Display capped at 300 rows.') end
    ImGui.EndChild();ImGui.Text('TRANSITIONS')
    ImGui.BeginChild('##nav_edges',0,140,true)
    for i,e in ipairs(graph.edges) do if i<=300 then ImGui.Text(string.format('%s: %s → %s  (%s%s)',e.id,e.from,e.to,e.kind,e.one_way and ', one-way' or '')) end end
    if #graph.edges>300 then ImGui.TextDisabled('Display capped at 300 rows.') end
    ImGui.EndChild()
    if #(graph.polygons or {})>0 then
        ImGui.Text('NAVMESH SURFACES');ImGui.BeginChild('##nav_polygons',0,110,true)
        for i,p in ipairs(graph.polygons) do if i<=150 then
            ImGui.Text(string.format('%s  %s  (%d vertices)',p.id,p.surface or 'walkable',#p.vertices))
            for j,v in ipairs(p.vertices) do ImGui.TextDisabled(string.format('  %02d  %.2f, %.2f, %.2f',j,v.x,v.y,v.z)) end
        end end
        if #graph.polygons>150 then ImGui.TextDisabled('Display capped at 150 rows.') end
        ImGui.EndChild()
    end
end

function SpatialUI:draw_device_logic(premise)
    local app=self.app;local logic=app.device_logic
    ImGui.Text('DEVICE LOGIC GRAPH')
    ImGui.TextWrapped('Author terminals, doors, elevators, switches, cameras, security systems, quest facts, actions and links. Saved graphs are validated and exported as handoff data. REDengine execution requires compatible device, persistent-state and instance records.')
    if not logic then ImGui.TextDisabled('Device Logic module unavailable.');return end
    self.logic_graph_name=select(1,ImGui.InputText('New graph name',self.logic_graph_name,128))
    if ImGui.Button('CREATE GRAPH') then local g,err=logic:create({name=self.logic_graph_name,premise_id=premise and premise.id});if g then self.logic_graph_id=g.id end;self:toast(err or (g and 'Device Logic graph created')) end
    local graphs=logic:list();local graph_label='Select graph';for _,g in ipairs(graphs) do if g.id==self.logic_graph_id then graph_label=g.name end end
    if ImGui.BeginCombo('Saved graph',graph_label) then for _,g in ipairs(graphs) do if ImGui.Selectable(g.name..'##logicgraph_'..g.id,self.logic_graph_id==g.id) then self.logic_graph_id=g.id;self.logic_node_id='';self.logic_link_id='' end end;ImGui.EndCombo() end
    local graph=logic:get(self.logic_graph_id);if not graph then ImGui.TextDisabled('Create or select a graph.');return end
    ImGui.Text(string.format('%d nodes / %d links',#graph.nodes,#graph.links))
    if ImGui.BeginCombo('Node type',self.logic_node_kind) then for _,kind in ipairs({'terminal','door','elevator','switch','camera','security_system','fact','action'}) do if ImGui.Selectable(kind,self.logic_node_kind==kind) then self.logic_node_kind=kind end end;ImGui.EndCombo() end
    self.logic_node_name=select(1,ImGui.InputText('Node name',self.logic_node_name,128))
    local entity_label='No placed entity binding';for _,obj in ipairs(app.model.data.objects or {}) do if obj.id==self.logic_object_id then entity_label=(obj.name or obj.id)..' ['..obj.id..']' end end
    if ImGui.BeginCombo('Bind placed object (optional)',entity_label) then
        if ImGui.Selectable('No placed entity binding',self.logic_object_id=='') then self.logic_object_id='' end
        for _,obj in ipairs(app.model.data.objects or {}) do if obj.premise_id==nil or not premise or obj.premise_id==premise.id then
            local interactable=obj.metadata and obj.metadata.interactable
            if interactable or (obj.template or ''):lower():match('%.ent$') then if ImGui.Selectable((obj.name or 'Object')..'##logicobj_'..obj.id,self.logic_object_id==obj.id) then self.logic_object_id=obj.id end end
        end end;ImGui.EndCombo()
    end
    local config={}
    if self.logic_node_kind=='fact' then
        self.logic_fact_name=select(1,ImGui.InputText('Quest fact name',self.logic_fact_name,128));config.fact_name=self.logic_fact_name
        self.logic_fact_value=select(1,ImGui.InputInt('Fact value',self.logic_fact_value));config.value=self.logic_fact_value
    elseif self.logic_node_kind=='action' then
        if ImGui.BeginCombo('Action operation',self.logic_action) then for _,op in ipairs({'set_fact','unlock','lock','enable','disable','alarm','set_camera_state','elevator_floor','emit_event','custom'}) do if ImGui.Selectable(op,self.logic_action==op) then self.logic_action=op end end;ImGui.EndCombo() end
        config.operation=self.logic_action
        self.logic_operation_arg=select(1,ImGui.InputText('Action fact / target / payload',self.logic_operation_arg,128))
        if self.logic_action=='set_fact' then config.fact_name=self.logic_operation_arg;config.value=self.logic_fact_value else config.target=self.logic_operation_arg end
    end
    local native={}
    if self.logic_node_kind~='fact' and self.logic_node_kind~='action' then
        ImGui.Separator();ImGui.Text('World Builder binding (optional until native build)')
        self.logic_device_hash=select(1,ImGui.InputText('WB device hash',self.logic_device_hash or '',64));native.device_hash=self.logic_device_hash
        self.logic_device_class=select(1,ImGui.InputText('WB device class',self.logic_device_class or '',128));native.device_class=self.logic_device_class
        self.logic_ps_hash=select(1,ImGui.InputText('PS entry hash',self.logic_ps_hash or '',64));native.ps_entry_hash=self.logic_ps_hash
        self.logic_instance_ref=select(1,ImGui.InputText('Instance data ref',self.logic_instance_ref or '',256));native.instance_data_ref=self.logic_instance_ref
        self.logic_node_ref=select(1,ImGui.InputText('World nodeRef',self.logic_node_ref or '',128));native.node_ref=self.logic_node_ref
    end
    if ImGui.Button('ADD NODE') then
        local node,err=logic:add_node({graph_id=graph.id,kind=self.logic_node_kind,name=self.logic_node_name,object_id=self.logic_object_id~='' and self.logic_object_id or nil,config=config,native=native})
        if node then self.logic_node_id=node.id end;self:toast(err or (node and 'Node added'))
    end
    ImGui.Separator();ImGui.Text('NODES')
    ImGui.BeginChild('##device_logic_nodes',0,160,true)
    for _,node in ipairs(graph.nodes) do if ImGui.Selectable(node.kind..'  |  '..node.name..'##logicnode_'..node.id,self.logic_node_id==node.id) then
        self.logic_node_id=node.id;self.logic_node_kind=node.kind;self.logic_node_name=node.name;self.logic_object_id=node.object_id or ''
        local cfg=node.config or {};self.logic_fact_name=cfg.fact_name or '';self.logic_fact_value=cfg.value or 1;self.logic_action=cfg.operation or 'unlock';self.logic_operation_arg=cfg.fact_name or cfg.target or ''
        local native=node.native or {};self.logic_device_hash=native.device_hash or '';self.logic_device_class=native.device_class or '';self.logic_ps_hash=native.ps_entry_hash or '';self.logic_instance_ref=native.instance_data_ref or '';self.logic_node_ref=native.node_ref or ''
    end end
    ImGui.EndChild()
    local selected;for _,node in ipairs(graph.nodes) do if node.id==self.logic_node_id then selected=node end end
    if selected then ImGui.Text('Selected: '..selected.name..'  ('..selected.kind..')')
        self.logic_node_name=select(1,ImGui.InputText('Edit node name',self.logic_node_name,128))
        self.logic_object_id=select(1,ImGui.InputText('Edit bound object ID',self.logic_object_id,128))
        local edit_config
        if selected.kind=='fact' then
            self.logic_fact_name=select(1,ImGui.InputText('Edit fact name',self.logic_fact_name,128));self.logic_fact_value=select(1,ImGui.InputInt('Edit fact value',self.logic_fact_value));edit_config={fact_name=self.logic_fact_name,value=self.logic_fact_value}
        elseif selected.kind=='action' then
            if ImGui.BeginCombo('Edit action operation',self.logic_action) then for _,op in ipairs({'set_fact','unlock','lock','enable','disable','alarm','set_camera_state','elevator_floor','emit_event','custom'}) do if ImGui.Selectable(op,self.logic_action==op) then self.logic_action=op end end;ImGui.EndCombo() end
            self.logic_operation_arg=select(1,ImGui.InputText('Edit action fact / target',self.logic_operation_arg,128))
            if self.logic_action=='set_fact' then edit_config={operation=self.logic_action,fact_name=self.logic_operation_arg,value=self.logic_fact_value} else edit_config={operation=self.logic_action,target=self.logic_operation_arg} end
        else edit_config={} end
        if selected.kind~='fact' and selected.kind~='action' then
            self.logic_device_hash=select(1,ImGui.InputText('Edit WB device hash',self.logic_device_hash,64))
            self.logic_device_class=select(1,ImGui.InputText('Edit WB device class',self.logic_device_class,128))
            self.logic_ps_hash=select(1,ImGui.InputText('Edit PS entry hash',self.logic_ps_hash,64))
            self.logic_instance_ref=select(1,ImGui.InputText('Edit instance data ref',self.logic_instance_ref,256))
            self.logic_node_ref=select(1,ImGui.InputText('Edit world nodeRef',self.logic_node_ref,128))
        end
        if ImGui.Button('SAVE NODE EDITS') then
            local native={device_hash=self.logic_device_hash,device_class=self.logic_device_class,ps_entry_hash=self.logic_ps_hash,instance_data_ref=self.logic_instance_ref,node_ref=self.logic_node_ref}
            local object_id=self.logic_object_id~='' and self.logic_object_id or ''
            local updated,err=logic:update_node({graph_id=graph.id,node_id=selected.id,patch={name=self.logic_node_name,object_id=object_id,config=edit_config,native=native}})
            self:toast(err or (updated and 'Node saved') or 'Node save failed')
        end
        if ImGui.Button('DELETE SELECTED NODE') then local result,err=logic:delete_node(graph.id,selected.id);self.logic_node_id='';self:toast(err or ('Deleted node and '..tostring(result.removed_links)..' links')) end
    end
    ImGui.Separator();ImGui.Text('LINK NODES')
    local function node_combo(label,key)
        local title='Select node';for _,n in ipairs(graph.nodes) do if n.id==self[key] then title=n.name..' ('..n.kind..')' end end
        if ImGui.BeginCombo(label,title) then for _,n in ipairs(graph.nodes) do if ImGui.Selectable(n.name..' ('..n.kind..')##'..label..n.id,self[key]==n.id) then self[key]=n.id end end;ImGui.EndCombo() end
    end
    node_combo('From##logiclink','logic_from_id');node_combo('To##logiclink','logic_to_id')
    self.logic_trigger=select(1,ImGui.InputText('Trigger / event',self.logic_trigger,64))
    self.logic_condition_fact=select(1,ImGui.InputText('Condition fact (optional)',self.logic_condition_fact,128))
    self.logic_condition_value=select(1,ImGui.InputInt('Condition value',self.logic_condition_value))
    self.logic_native_operation=select(1,ImGui.InputText('Native operation (optional)',self.logic_native_operation,128))
    if ImGui.Button('CONNECT NODES') then local link,err=logic:add_link({graph_id=graph.id,from_id=self.logic_from_id,to_id=self.logic_to_id,trigger=self.logic_trigger,condition_fact=self.logic_condition_fact,condition_value=self.logic_condition_value,native_operation=self.logic_native_operation});if link then self.logic_link_id=link.id end;self:toast(err or (link and 'Nodes connected')) end
    ImGui.Text('LINKS');ImGui.BeginChild('##device_logic_links',0,135,true)
    for _,link in ipairs(graph.links) do local a,b;for _,n in ipairs(graph.nodes) do if n.id==link.from_id then a=n.name end;if n.id==link.to_id then b=n.name end end
        if ImGui.Selectable((a or link.from_id)..' → '..(b or link.to_id)..'  ['..link.trigger..']##logiclink_'..link.id,self.logic_link_id==link.id) then self.logic_link_id=link.id end
    end;ImGui.EndChild()
    if self.logic_link_id~='' and ImGui.Button('DELETE SELECTED LINK') then local _,err=logic:delete_link(graph.id,self.logic_link_id);self.logic_link_id='';self:toast(err or 'Link deleted') end
    if ImGui.Button('VALIDATE NATIVE READINESS') then self.logic_validation=logic:validate(graph.id);self:toast('Validation complete; inspect resource warnings below.') end
    if ImGui.Button('DELETE GRAPH') then local _,err=logic:delete_graph(graph.id);self.logic_graph_id='';self:toast(err or 'Graph deleted') end
    local validation=self.logic_validation;if validation then for _,entry in ipairs(validation.graphs or {}) do if entry.id==graph.id then
        ImGui.Text('Status: '..entry.status..' — native execution: '..tostring(entry.native_runtime_execution))
        for _,message in ipairs(entry.errors) do ImGui.TextWrapped('ERROR: '..message) end
        for _,message in ipairs(entry.warnings) do ImGui.TextWrapped('NEEDS SETUP: '..message) end
    end end end
end

function SpatialUI:draw_cover_nodes(premise)
    local app=self.app;local nodes={};for _,node in ipairs(app.model.data.cover_nodes or {}) do if node.premise_id==premise.id then nodes[#nodes+1]=node end end
    ImGui.Text('COVER POSITIONS');ImGui.TextWrapped('Save cover points in this premise, choose crouch/standing posture, facing direction, exposure and spacing. In-world markers use the configured marker .ent. These are authoring candidates; they do not create native REDengine AI cover records.')
    self.cover_name=select(1,ImGui.InputText('Node name',self.cover_name,128))
    if ImGui.BeginCombo('Posture##cover',self.cover_type) then for _,value in ipairs({'crouch','standing'}) do if ImGui.Selectable(value,self.cover_type==value) then self.cover_type=value end end;ImGui.EndCombo() end
    ImGui.SameLine();if ImGui.BeginCombo('Exposure##cover',self.cover_exposure) then for _,value in ipairs({'low','medium','high'}) do if ImGui.Selectable(value,self.cover_exposure==value) then self.cover_exposure=value end end;ImGui.EndCombo() end
    self.cover_spacing=select(1,ImGui.InputFloat('Preferred spacing (m)',self.cover_spacing,0.25,0.5,'%.2f'))
    local function create(source)
        local node,err=app.actions:create_cover_node({premise_id=premise.id,room_id=app.selected_room_id,name=self.cover_name,cover_type=self.cover_type,exposure=self.cover_exposure,spacing=self.cover_spacing,source=source})
        self:toast(err or (node and ('Saved '..node.cover_type..' cover point; adjust direction in Inspector') or 'Could not save cover point'))
        if node then self.cover_selected_id=node.id;local p=node.transform.position;self.cover_position={p.x,p.y,p.z};self.cover_yaw=node.transform.rotation.yaw end
    end
    if ImGui.Button('PLACE AT PLAYER##cover',175,30) then create('player') end
    ImGui.SameLine();if ImGui.Button('PLACE AT AIM##cover',165,30) then create('aim') end
    ImGui.SameLine();if ImGui.Button('REFRESH COVER MARKERS##cover',215,30) then local result=app.markers:refresh(premise.id);self:toast(result.skipped or string.format('Refreshed %d markers, including cover nodes; %d failed',result.spawned,#result.failed)) end
    ImGui.Separator();ImGui.Text('SCAN WALLS / PROPS FOR CANDIDATES')
    self.cover_radius=select(1,ImGui.InputFloat('Scan radius (m)',self.cover_radius,1,2,'%.1f'))
    ImGui.SameLine();self.cover_samples=select(1,ImGui.InputInt('Directions##cover_scan',self.cover_samples,4,8))
    if ImGui.Button('SCAN AROUND PLAYER##cover',210,30) then
        local result,err=app.live_tools:scan_cover_candidates({radius=self.cover_radius,samples=self.cover_samples,spacing=self.cover_spacing})
        self.cover_nodes_scan=result;self:toast(err or (result and ('Found '..tostring(result.candidate_count)..' cover candidates') or 'Cover scan failed'))
    end
    if self.cover_nodes_scan then
        local scan=self.cover_nodes_scan;ImGui.TextWrapped(string.format('%d candidates · %s',scan.candidate_count or 0,scan.method or 'collision scan'))
        ImGui.TextWrapped(scan.caveat or '')
        local shown=math.min(16,#(scan.candidates or {}));ImGui.BeginChild('##cover_candidates',0,150,true)
        for i=1,shown do local candidate=scan.candidates[i];local p=candidate.transform.position
            ImGui.Text(string.format('%02d  %.2f, %.2f, %.2f  yaw %.1f°  confidence %.0f%%',i,p.x,p.y,p.z,candidate.transform.rotation.yaw or 0,(candidate.confidence or 0)*100))
        end
        if #scan.candidates>shown then ImGui.TextDisabled('Showing first '..shown..' of '..#scan.candidates) end
        ImGui.EndChild()
        if ImGui.Button('ADD SCAN CANDIDATES TO PROJECT##cover',270,30) then
            local added,skipped=0,0
            for _,candidate in ipairs(scan.candidates or {}) do
                local near=false;for _,old in ipairs(app.model.data.cover_nodes or {}) do if old.premise_id==premise.id and app.util.distance3(old.transform.position,candidate.transform.position)<self.cover_spacing then near=true;break end end
                if near then skipped=skipped+1 else
                    local node=app.actions:create_cover_node({premise_id=premise.id,room_id=app.selected_room_id,name='Scanned Cover '..tostring(added+1),cover_type=self.cover_type,exposure=candidate.exposure or self.cover_exposure,spacing=self.cover_spacing,transform=candidate.transform,node_source='live_collision_scan',confidence=candidate.confidence})
                    if node then added=added+1 end
                end
            end
            self.cover_nodes_scan=nil;self:toast(string.format('Saved %d cover candidates; skipped %d too close to existing nodes',added,skipped))
        end
        ImGui.SameLine();if ImGui.Button('DISCARD SCAN##cover',120,30) then self.cover_nodes_scan=nil end
    end
    ImGui.Separator();ImGui.Text(string.format('SAVED COVER NODES · %d',#nodes))
    local selected=app.model:get_cover_node(self.cover_selected_id)
    local label=selected and selected.name or 'Select cover node'
    if ImGui.BeginCombo('Cover node##cover_select',label) then
        for _,node in ipairs(nodes) do if ImGui.Selectable(node.name..'  ['..node.cover_type..']##cover_'..node.id,self.cover_selected_id==node.id) then
            self.cover_selected_id=node.id;self.cover_name=node.name;self.cover_type=node.cover_type;self.cover_exposure=node.exposure;self.cover_spacing=node.spacing
            local p=node.transform.position;self.cover_position={p.x,p.y,p.z};self.cover_yaw=node.transform.rotation.yaw or 0;app.selection:set('cover_node',node.id)
        end end
        ImGui.EndCombo()
    end
    if selected then
        local changed;self.cover_name,changed=ImGui.InputText('Selected name##cover_edit',self.cover_name,128)
        local pos=self.cover_position;local xyz={pos[1],pos[2],pos[3]};xyz,changed=Widgets.input3('World position##cover_edit',xyz,'%.3f');self.cover_position=xyz
        self.cover_yaw,changed=ImGui.InputFloat('Facing yaw (degrees)##cover_edit',self.cover_yaw,1,15,'%.2f')
        if ImGui.Button('SAVE COVER NODE##cover_edit',200,30) then
            local result,err=app.actions:update_cover_node({id=selected.id,patch={name=self.cover_name,cover_type=self.cover_type,exposure=self.cover_exposure,spacing=self.cover_spacing,transform={position={x=xyz[1],y=xyz[2],z=xyz[3]},rotation={roll=0,pitch=0,yaw=self.cover_yaw}}}})
            self:toast(err or (result and 'Cover node saved' or 'Cover node update failed'))
        end
        ImGui.SameLine();if ImGui.Button('DELETE COVER NODE##cover_edit',200,30) then local result,err=app.actions:delete_cover_node(selected.id);self.cover_selected_id='';self:toast(err or (result and 'Cover node deleted' or 'Delete failed')) end
    end
end

local function asset_is_entity(asset)
    local wb=asset and asset.metadata and asset.metadata.world_builder or {}
    local key=tostring(wb.definition_key or '')
    return tostring(asset and asset.template or ''):lower():match('%.ent$')~=nil or key=='entity_template' or key=='entity_amm' or key=='entity_record' or key=='device'
end

local function interactable_name(object)
    local data=object.metadata.interactable or {}
    return string.format('%s  [%s / %s]',object.name,data.kind or '?',data.lock_state or 'n/a')
end

function SpatialUI:draw_interactables()
    local app=self.app
    ImGui.Text('PLACE GAME ENTITY + AUTHOR INTERACTION DATA')
    ImGui.TextWrapped('Choose an actual entity asset. Placement spawns the selected game entity; item, lock, and fact fields are saved for the native resource handoff.')
    self.interactable_search=select(1,ImGui.InputText('Find entity asset',self.interactable_search,128))
    ImGui.BeginChild('##interactable_assets',0,115,true)
    local q=(self.interactable_search or ''):lower();local shown=0
    for _,asset in ipairs(app.model.data.assets or {}) do
        if asset_is_entity(asset) then
            local blob=(tostring(asset.name)..' '..tostring(asset.template)..' '..tostring(asset.category)):lower()
            if q=='' or blob:find(q,1,true) then
                shown=shown+1
                if ImGui.Selectable(asset.name..'  —  '..(asset.template~='' and asset.template or (asset.metadata.world_builder.resource_path or 'Entity Record'))..'##ia_'..asset.id,self.interactable_asset_id==asset.id) then self.interactable_asset_id=asset.id end
                if shown>=24 then break end
            end
        end
    end
    if shown==0 then ImGui.TextDisabled('No matching registered .ent / Entity Record / Device assets. Import one in Assets or use the Assets browser search.') end
    ImGui.EndChild()
    local selected_asset=self.interactable_asset_id~='' and app.model:get_asset(self.interactable_asset_id) or nil
    if selected_asset then ImGui.TextWrapped('Selected: '..selected_asset.name..' — '..(selected_asset.template~='' and selected_asset.template or selected_asset.category))
    else ImGui.TextDisabled('Select an entity asset above. Mesh-only assets are excluded because they do not provide interactions.') end
    if ImGui.BeginCombo('Interactable kind',self.interactable_kind) then
        for _,kind in ipairs({'door','loot_container','shard','item'}) do
            if ImGui.Selectable(kind,self.interactable_kind==kind) then self.interactable_kind=kind;self.interactable_lock_state=(kind=='door' or kind=='loot_container') and 'locked' or 'not_applicable' end
        end
        ImGui.EndCombo()
    end
    self.interactable_name=select(1,ImGui.InputText('Placed object name',self.interactable_name,128))
    self.interactable_entity_record=select(1,ImGui.InputText('Entity record (optional)',self.interactable_entity_record,256))
    self.interactable_item_record=select(1,ImGui.InputText('Item record (Items.*)',self.interactable_item_record,256))
    self.interactable_loot_table=select(1,ImGui.InputText('Loot table (LootTables.*)',self.interactable_loot_table,256))
    self.interactable_loot_item_record=self.interactable_loot_item_record or ''
    self.interactable_loot_item_record=select(1,ImGui.InputText('Generated loot item (Items.*)',self.interactable_loot_item_record,256))
    if ImGui.BeginCombo('Lock state',self.interactable_lock_state) then for _,state in ipairs({'locked','unlocked','not_applicable'}) do if ImGui.Selectable(state,self.interactable_lock_state==state) then self.interactable_lock_state=state end end;ImGui.EndCombo() end
    self.interactable_fact_name=select(1,ImGui.InputText('Quest fact set on interaction',self.interactable_fact_name,128))
    self.interactable_fact_value=select(1,ImGui.InputInt('Fact value',self.interactable_fact_value))
    if ImGui.Button('PLACE AT AIM',145,30) then
        if not selected_asset then self:toast('Select a real game entity asset first')
        else local object,err=app.actions:create_interactable({kind=self.interactable_kind,asset_id=selected_asset.id,name=self.interactable_name,source='aim',premise_id=app.selected_premise_id,room_id=app.selected_room_id,
            entity_record=self.interactable_entity_record,item_record=self.interactable_item_record,loot_table=self.interactable_loot_table,loot_items=self.interactable_loot_item_record~='' and {{item_record=self.interactable_loot_item_record,count_min=1,count_max=1,drop_chance=1}} or {},lock_state=self.interactable_lock_state,fact_name=self.interactable_fact_name,fact_value=self.interactable_fact_value,spawn=true})
            if object then app.selection:set('object',object.id) end;self:toast(err or (object and ('Placed '..object.name..'; interaction setup saved for native handoff') or 'Placement failed')) end
    end
    ImGui.SameLine()
    if ImGui.Button('PLACE AT PLAYER',160,30) then
        if not selected_asset then self:toast('Select a real game entity asset first')
        else local object,err=app.actions:create_interactable({kind=self.interactable_kind,asset_id=selected_asset.id,name=self.interactable_name,source='player',premise_id=app.selected_premise_id,room_id=app.selected_room_id,
            entity_record=self.interactable_entity_record,item_record=self.interactable_item_record,loot_table=self.interactable_loot_table,loot_items=self.interactable_loot_item_record~='' and {{item_record=self.interactable_loot_item_record,count_min=1,count_max=1,drop_chance=1}} or {},lock_state=self.interactable_lock_state,fact_name=self.interactable_fact_name,fact_value=self.interactable_fact_value,spawn=true})
            if object then app.selection:set('object',object.id) end;self:toast(err or (object and ('Placed '..object.name..'; interaction setup saved for native handoff') or 'Placement failed')) end
    end
    ImGui.Separator();ImGui.Text('PLACED INTERACTABLES')
    ImGui.BeginChild('##interactable_list',0,125,true)
    for _,object in ipairs(app.model.data.objects or {}) do
        if object.metadata and object.metadata.interactable then
            if ImGui.Selectable(interactable_name(object)..'##'..object.id,app.selected_interactable_id==object.id) then app.selected_interactable_id=object.id end
        end
    end
    ImGui.EndChild()
    local object=app.selected_interactable_id and app.model:get_object(app.selected_interactable_id)
    if object and object.metadata and object.metadata.interactable then
        local config=object.metadata.interactable;local changed=false;local any=false
        ImGui.Text('Edit: '..object.name..' — '..tostring(config.entity_template or object.template))
        local edit={kind=config.kind or 'door',entity_record=config.entity_record or '',item_record=config.item_record or '',loot_table=config.loot_table or '',lock_state=config.lock_state or 'unlocked',fact_name=config.fact_name or '',fact_value=tonumber(config.fact_value) or 1}
        edit.kind,changed=ImGui.InputText('Kind##edit_interactable',edit.kind,32);any=any or changed
        edit.entity_record,changed=ImGui.InputText('Entity record##edit_interactable',edit.entity_record,256);any=any or changed
        edit.item_record,changed=ImGui.InputText('Item record##edit_interactable',edit.item_record,256);any=any or changed
        edit.loot_table,changed=ImGui.InputText('Loot table##edit_interactable',edit.loot_table,256);any=any or changed
        edit.loot_item_record=(config.loot_items and config.loot_items[1] and config.loot_items[1].item_record) or ''
        edit.loot_item_record,changed=ImGui.InputText('First generated loot item##edit_interactable',edit.loot_item_record,256);any=any or changed
        edit.fact_name,changed=ImGui.InputText('Fact name##edit_interactable',edit.fact_name,128);any=any or changed
        edit.fact_value,changed=ImGui.InputInt('Fact value##edit_interactable',edit.fact_value);any=any or changed
        if edit.kind=='door' or edit.kind=='loot_container' then
            if ImGui.BeginCombo('Lock##edit_interactable',edit.lock_state) then for _,state in ipairs({'locked','unlocked'}) do if ImGui.Selectable(state,edit.lock_state==state) then edit.lock_state=state;any=true end end;ImGui.EndCombo() end
        else edit.lock_state='not_applicable' end
        edit.loot_items=edit.loot_item_record~='' and {{item_record=edit.loot_item_record,count_min=1,count_max=1,drop_chance=1}} or {}
        if any then local updated,err=app.actions:update_interactable(object.id,edit);if not updated then self:toast(err) else self:toast('Saved interactable settings') end end
        ImGui.TextDisabled('Saved data only: a shard/item record does not populate inventory, and lock/fact behavior requires native entity, persistent-state, and quest wiring.')
        if ImGui.Button('DELETE INTERACTABLE') then app.selection:set('object',object.id);local ok,err=app.actions:delete_selected();app.selected_interactable_id=nil;self:toast(ok and 'Interactable removed' or err) end
    end
    ImGui.TextDisabled('Build Mod generates TweakXL loot records from these item rows. Native entity components and door/controller operations still require a compatible game entity; World Builder provides typed sector, device and PS resources.')
end

function SpatialUI:draw_lighting()
    local app=self.app
    ImGui.Text('WORLD BUILDER STATIC LIGHTS')
    ImGui.TextWrapped('Creates real worldStaticLightNode lights through World Builder. Color, intensity, radius and flicker are saved in the light spawn data. Changes respawn the light so they take effect.')
    self.lighting_name=select(1,ImGui.InputText('Light name',self.lighting_name,128))
    local presets=app.lighting:presets();local preset_name=self.lighting_preset
    for _,p in ipairs(presets) do if p.id==self.lighting_preset then preset_name=p.name end end
    if ImGui.BeginCombo('Preset',preset_name) then for _,p in ipairs(presets) do if ImGui.Selectable(p.name,self.lighting_preset==p.id) then self.lighting_preset=p.id end end;ImGui.EndCombo() end
    if ImGui.Button('PLACE AT AIM',145,30) then local obj,err=app.lighting:create({name=self.lighting_name,source='aim',premise_id=app.selected_premise_id,room_id=app.selected_room_id,preset_id=self.lighting_preset});if obj then app.selection:set('object',obj.id) end;self:toast(err or (obj and 'Static light placed and spawned' or 'Could not place static light')) end
    ImGui.SameLine()
    if ImGui.Button('PLACE AT PLAYER',160,30) then local obj,err=app.lighting:create({name=self.lighting_name,source='player',premise_id=app.selected_premise_id,room_id=app.selected_room_id,preset_id=self.lighting_preset});if obj then app.selection:set('object',obj.id) end;self:toast(err or (obj and 'Static light placed and spawned' or 'Could not place static light')) end
    ImGui.Separator();ImGui.Text('LIGHT OBJECTS');ImGui.BeginChild('##lighting_list',245,230,true)
    for _,o in ipairs(app.model.data.objects or {}) do if o.metadata and o.metadata.world_builder and o.metadata.world_builder.definition_key=='light_static' then if ImGui.Selectable(o.name..'##light_'..o.id,app.selection:is('object',o.id)) then app.selection:set('object',o.id) end end end
    ImGui.EndChild();ImGui.SameLine();ImGui.BeginChild('##lighting_edit',0,230,true)
    local obj=app.selected_object_id and app.model:get_object(app.selected_object_id);local cfg=obj and obj.metadata and obj.metadata.lighting
    if obj and cfg and obj.metadata.world_builder and obj.metadata.world_builder.definition_key=='light_static' then
        if self.lighting_edit_id~=obj.id then self.lighting_edit_id=obj.id;self.lighting_edit=app.util.deepcopy(cfg) end
        local edit=self.lighting_edit;ImGui.Text(obj.name);local changed=false
        local r,g,b; r,g,b,changed=ImGui.ColorEdit3('Color##light',edit.color[1],edit.color[2],edit.color[3]);if changed then edit.color={r,g,b} end
        edit.intensity,changed=ImGui.InputFloat('Intensity',edit.intensity,1,10,'%.1f')
        edit.radius,changed=ImGui.InputFloat('Radius (m)',edit.radius,0.25,1,'%.2f')
        edit.flickerStrength,changed=ImGui.SliderFloat('Flicker strength',edit.flickerStrength,0,1,'%.2f')
        edit.flickerPeriod,changed=ImGui.InputFloat('Flicker period',edit.flickerPeriod,0.01,0.1,'%.2f')
        edit.flickerOffset,changed=ImGui.InputFloat('Flicker offset',edit.flickerOffset,0.01,0.1,'%.2f')
        if ImGui.Button('APPLY SETTINGS + RESPAWN',225,30) then local updated,err=app.lighting:update(obj.id,edit);if updated then self.lighting_edit=app.util.deepcopy(updated.metadata.lighting) end;self:toast(err or (updated and 'Light updated and respawned' or 'Light update failed')) end
        if ImGui.Button('APPLY PRESET',135,30) then local ok,err=app.lighting:apply_preset(obj.id,self.lighting_preset);if ok then self.lighting_edit=app.util.deepcopy(ok.metadata.lighting) end;self:toast(err or (ok and 'Preset applied' or 'Preset failed')) end
        ImGui.SameLine();if ImGui.Button('DELETE LIGHT') then app.selection:set('object',obj.id);local ok,err=app.actions:delete_selected();self:toast(err or (ok and 'Light deleted' or 'Delete failed')) end
    else ImGui.TextDisabled('Select a light from the list to tune it.') end
    ImGui.EndChild()
    ImGui.Separator();ImGui.Text('TIME OF DAY PREVIEW (changes the game clock)')
    self.lighting_hour=select(1,ImGui.InputInt('Hour (0–23)',self.lighting_hour));self.lighting_minute=select(1,ImGui.InputInt('Minute (0–59)',self.lighting_minute))
    if ImGui.Button('PREVIEW TIME',140,30) then local result,err=app.lighting:preview_time(self.lighting_hour,self.lighting_minute);self:toast(err or (result and 'Game clock changed; restore when finished' or 'Preview failed')) end
    ImGui.SameLine();if ImGui.Button('RESTORE PREVIEW TIME',190,30) then local result,err=app.lighting:restore_time();self:toast(err or (result and 'Original game time restored' or 'Restore failed')) end
end

function SpatialUI:_vfx_args(extra)
    local args={name=self.vfx_name,scale={x=self.vfx_scale[1],y=self.vfx_scale[2],z=self.vfx_scale[3]},
        roll=self.vfx_rotation[1],pitch=self.vfx_rotation[2],yaw=self.vfx_rotation[3],emission_rate=self.vfx_emission,respawn_on_move=self.vfx_respawn_on_move,
        align_to_surface=self.vfx_align,follow=self.vfx_follow,distance=self.vfx_distance,premise_id=self.app.selected_premise_id,room_id=self.app.selected_room_id}
    local item=self.vfx_selected
    if item then args.resource_path=item.path;args.backend=item.backend;args.category=self.vfx_category~='all' and self.vfx_category or item.category
    else args.query=self.vfx_query;args.category=self.vfx_category;args.backend=self.vfx_backend end
    for k,v in pairs(extra or {}) do args[k]=v end
    return args
end

function SpatialUI:draw_splines()
    local app=self.app;local S=app.splines
    ImGui.Text('SPLINE EDITOR')
    if not S then ImGui.TextDisabled('The spline editor failed to load.');return end
    ImGui.TextWrapped('Persistent Bezier splines with control points and tangent handles. Build cables, fences, roads, object rows, NPC routes, camera paths or a native World Builder spline from one curve, then REGENERATE after editing it.')
    self.spline_name=select(1,ImGui.InputText('Spline name',self.spline_name,64))
    if ImGui.Button('NEW SPLINE AT AIM',170,28) then local sp,err=S:create({name=self.spline_name,source='aim'});if sp then self.spline_id=sp.id;self.spline_point=1 end;self:toast(err or 'Spline created; add points at aim') end
    ImGui.BeginChild('##spline_list',0,80,true)
    for _,row in ipairs(S:list({premise_id=app.selected_premise_id}).items) do
        if ImGui.Selectable(string.format('%s · %d pts · %.1f m%s · %d use(s)##spl_%s',row.name,row.points,row.length,row.closed and ' · closed' or '',#row.uses,row.id),self.spline_id==row.id) then self.spline_id=row.id;self.spline_point=1 end
    end
    ImGui.EndChild()
    local sp=S:get(self.spline_id)
    if not sp then ImGui.TextDisabled('Create or select a spline.');return end
    ImGui.Text(sp.name..(sp.closed and ' (closed)' or ' (open)'))
    if ImGui.Button('ADD POINT AT AIM',160,26) then local r,err=S:add_point(sp.id,{source='aim'});if r then self.spline_point=r.index end;self:toast(err or ('Point '..r.index..' added')) end
    ImGui.SameLine();if ImGui.Button('ADD AT PLAYER',140,26) then local r,err=S:add_point(sp.id,{source='player'});if r then self.spline_point=r.index end;self:toast(err or 'Point added') end
    ImGui.SameLine();if ImGui.Button(sp.closed and 'OPEN CURVE' or 'CLOSE CURVE',130,26) then local _,err=S:update(sp.id,{closed=not sp.closed});self:toast(err or 'Updated') end
    local tension,tchanged=ImGui.SliderFloat('Auto tangent tension',sp.tension,0,1,'%.2f');if tchanged then S:update(sp.id,{tension=tension}) end
    self.spline_point=math.max(1,math.min(#sp.points,(select(1,ImGui.InputInt('Control point',self.spline_point)))))
    local p=sp.points[self.spline_point]
    if p then
        ImGui.TextDisabled(string.format('Point %d: (%.2f, %.2f, %.2f) · %s',self.spline_point,p.position.x,p.position.y,p.position.z,p.mode))
        if ImGui.BeginCombo('Tangent mode',p.mode) then for _,m in ipairs({'auto','aligned','free','linear'}) do if ImGui.Selectable(m..'##splmode_'..m,p.mode==m) then S:update_point(sp.id,self.spline_point,{mode=m}) end end;ImGui.EndCombo() end
        if ImGui.Button('MOVE POINT TO AIM',170,26) then local _,err=S:update_point(sp.id,self.spline_point,{source='aim'});self:toast(err or 'Point moved') end
        ImGui.SameLine();if ImGui.Button('DELETE POINT',130,26) then local _,err=S:delete_point(sp.id,self.spline_point);self:toast(err or 'Point deleted') end
        self.spline_handle[1]=select(1,ImGui.InputFloat('Out handle X',self.spline_handle[1],0.1,1,'%.2f'))
        self.spline_handle[2]=select(1,ImGui.InputFloat('Out handle Y',self.spline_handle[2],0.1,1,'%.2f'))
        self.spline_handle[3]=select(1,ImGui.InputFloat('Out handle Z',self.spline_handle[3],0.1,1,'%.2f'))
        if ImGui.Button('SET OUT HANDLE',150,26) then local _,err=S:update_point(sp.id,self.spline_point,{handle_out={x=self.spline_handle[1],y=self.spline_handle[2],z=self.spline_handle[3]}});self:toast(err or 'Handle set (mirrored when aligned)') end
    end
    if ImGui.Button('PREVIEW IN WORLD',160,26) then local r,err=S:preview(sp.id,{spacing=1});self:toast(err or (r.markers..' preview marker(s)')) end
    ImGui.SameLine();if ImGui.Button('CLEAR PREVIEW##spline',140,26) then local _,err=S:preview_clear();self:toast(err or 'Preview cleared') end
    ImGui.Separator();ImGui.Text('USE THIS SPLINE')
    if ImGui.BeginCombo('Use',self.spline_use_kind) then for _,k in ipairs({'distribute','cable','fence','road','npc_path','camera_path','native_spline'}) do if ImGui.Selectable(k..'##spluse_'..k,self.spline_use_kind==k) then self.spline_use_kind=k end end;ImGui.EndCombo() end
    if self.spline_use_kind=='npc_path' then self.spline_npc_id=select(1,ImGui.InputText('NPC population object id',self.spline_npc_id,64))
    elseif self.spline_use_kind~='camera_path' and self.spline_use_kind~='native_spline' then self.spline_asset_id=select(1,ImGui.InputText('Asset id',self.spline_asset_id,96)) end
    self.spline_spacing=select(1,ImGui.InputFloat('Spacing (m)',self.spline_spacing,0.25,1,'%.2f'))
    if ImGui.Button('APPLY USE',130,28) then
        local params={asset_id=self.spline_asset_id,spacing=self.spline_spacing,npc_id=self.spline_npc_id,premise_id=app.selected_premise_id}
        if self.spline_use_kind=='camera_path' then params.spacing=nil;params.count=8 end
        local r,err=S:apply_use(sp.id,self.spline_use_kind,params);self:toast(err or (self.spline_use_kind..' created'))
    end
    ImGui.SameLine();if ImGui.Button('REGENERATE ALL USES',190,28) then local r,err=S:regenerate(sp.id);self:toast(err or ('Rebuilt '..r.count..' use(s)')) end
    for _,use in ipairs(sp.uses) do
        local out=use.outputs or {}
        ImGui.BulletText(use.kind..': '..(out.object_ids and (#out.object_ids..' object(s)') or out.camera_ids and (#out.camera_ids..' camera(s)') or out.route_id and (tostring(out.waypoints)..' waypoint(s)') or ''))
        ImGui.SameLine();if ImGui.SmallButton('REMOVE##spluserm_'..use.id) then local _,err=S:remove_use(sp.id,use.id,false);self:toast(err or 'Use and its output removed') end
    end
end

function SpatialUI:draw_vanilla_clone()
    local app=self.app;local V=app.vanilla_clone
    ImGui.Text('VANILLA CLONE / IMPORT')
    if not V then ImGui.TextDisabled('The vanilla clone importer failed to load.');return end
    ImGui.TextWrapped('Import existing vanilla world nodes as editable project objects that keep their real resource, appearance and transform. Optionally hide the originals (reversible) so the clones replace them. RedHotTools picks know the position only; for exact rotation and scale, stage the same nodes from a WolvenKit-exported sector JSON through MCP (vanilla_clone_from_sector).')
    local status=V:status()
    if not status.rht.ready then ImGui.TextColored(1,0.6,0.2,1,'RedHotTools: '..tostring(status.rht.error or 'not ready')) end
    if ImGui.Button('PICK CROSSHAIR##vc',150,28) then local r,err=V:pick_crosshair({append=true});self:toast(err or (r.added..' candidate(s) staged')) end
    ImGui.SameLine();self.vc_radius=select(1,ImGui.InputFloat('Scan radius (m)',self.vc_radius,1,5,'%.1f'))
    self.vc_term=select(1,ImGui.InputText('Filter (path, type, name)',self.vc_term,96))
    if ImGui.Button('SCAN AREA##vc',150,28) then local r,err=V:scan({radius=self.vc_radius,term=self.vc_term});self:toast(err or (r.count..' candidate(s), '..r.supported..' cloneable')) end
    ImGui.SameLine();if ImGui.Button('CLEAR##vc',90,28) then V:clear() end
    local c=V:candidates()
    ImGui.Text(string.format('%d staged · %d cloneable · %d selected',c.count,c.supported,c.selected))
    ImGui.SameLine();if ImGui.SmallButton('ALL##vcsel') then V:set_selected('all') end
    ImGui.SameLine();if ImGui.SmallButton('NONE##vcsel') then V:set_selected('none') end
    ImGui.BeginChild('##vc_candidates',0,160,true)
    for _,row in ipairs(c.items) do
        local label=string.format('%s %s [%s] %s%s##vccand_%d',row.selected and '[x]' or '[ ]',row.name,tostring(row.node_type or 'entity'),row.confidence=='exact' and 'exact' or 'position only',row.already_cloned and ' · cloned' or '',row.index)
        if ImGui.Selectable(label,row.selected) then
            local _,err=V:set_selected(row.index,not row.selected);if err then self:toast(err) end
        end
        if not row.supported then ImGui.TextDisabled('   '..tostring(row.reason)) end
        for _,w in ipairs(row.warnings or {}) do ImGui.TextDisabled('   ! '..w) end
    end
    ImGui.EndChild()
    self.vc_hide=select(1,ImGui.Checkbox('Hide the originals (reversible)',self.vc_hide))
    self.vc_approx=select(1,ImGui.Checkbox('Allow position-only picks (rotation 0, scale 1)',self.vc_approx))
    self.vc_group=select(1,ImGui.InputText('Group name (optional)',self.vc_group,64))
    if ImGui.Button('IMPORT SELECTED',170,30) then
        local r,err=V:import({premise_id=app.selected_premise_id,hide_originals=self.vc_hide,allow_approximate=self.vc_approx,group_name=self.vc_group})
        self:toast(err or string.format('Imported %d, skipped %d, hid %d original(s)',r.imported,#r.skipped,r.hidden))
    end
    ImGui.Separator();ImGui.Text('CLONES')
    for _,row in ipairs(V:list({}).items) do
        ImGui.BulletText(string.format('%s%s%s',row.name,row.modified and (' · changed: '..table.concat(row.changes,', ')) or '',row.original_hidden and ' · original hidden' or ''))
        ImGui.SameLine();if ImGui.SmallButton('SELECT##vcobj_'..row.id) then app.selection:set('object',row.id) end
        ImGui.SameLine();if ImGui.SmallButton('REVERT##vcrev_'..row.id) then local r,err=V:revert(row.id,{});self:toast(err or r.error or 'Clone removed and original shown') end
    end
end

function SpatialUI:draw_timeline()
    local app=self.app;local T=app.timeline
    ImGui.Text('CINEMATIC TIMELINE')
    if not T then ImGui.TextDisabled('The timeline editor failed to load.');return end
    ImGui.TextWrapped('Camera cuts and moves, NPC positions and animations, look-ats, dialogue timing, light/VFX/audio events and quest facts on one timeline. PLAY previews it in game (facts are only logged); STOP restores everything. EXPORT HANDOFF writes a structured scene handoff, not a native .scene.')
    self.tl_name=select(1,ImGui.InputText('Timeline name',self.tl_name,64))
    self.tl_duration=select(1,ImGui.InputFloat('Duration (s)',self.tl_duration,1,10,'%.1f'))
    if ImGui.Button('NEW TIMELINE',140,28) then local tl,err=T:create({name=self.tl_name,duration=self.tl_duration});if tl then self.tl_id=tl.id;self.tl_time=0;self.tl_track_id=tl.tracks[1] and tl.tracks[1].id or '' end;self:toast(err or 'Timeline created') end
    ImGui.BeginChild('##timeline_list',0,70,true)
    for _,row in ipairs(T:list({}).items) do
        if ImGui.Selectable(string.format('%s · %.1f s · %d track(s) · %d key(s)##tl_%s',row.name,row.duration,row.tracks,row.keys,row.id),self.tl_id==row.id) then self.tl_id=row.id;self.tl_time=0;self.tl_track_id='' end
    end
    ImGui.EndChild()
    local tl=T:get(self.tl_id)
    if not tl then ImGui.TextDisabled('Create or select a timeline.');return end
    local status=T:status()
    local playing_this=status.active and status.timeline_id==tl.id
    if playing_this then self.tl_time=status.time end
    local t=select(1,ImGui.SliderFloat('Playhead (s)',self.tl_time,0,tl.duration,'%.2f'))
    t=math.max(0,math.min(tl.duration,tonumber(t) or 0))
    if t~=self.tl_time then self.tl_time=t;if playing_this then local _,err=T:seek(t);if err then self:toast(err) end end end
    if ImGui.Button(playing_this and status.playing and 'PAUSE##tl' or 'PLAY##tl',90,28) then
        if playing_this and status.playing then T:pause() else local _,err=T:play(tl.id,{from=self.tl_time});self:toast(err or 'Previewing timeline') end
    end
    ImGui.SameLine();if ImGui.Button('STOP & RESTORE##tl',160,28) then local _,err=T:stop();self:toast(err or 'Preview stopped and restored') end
    ImGui.SameLine();if ImGui.Button('VALIDATE##tl',100,28) then self.tl_validation=T:validate(tl.id);self:toast(self.tl_validation.valid and 'No errors' or (self.tl_validation.errors..' error(s)')) end
    ImGui.SameLine();if ImGui.Button('EXPORT HANDOFF',150,28) then local r,err=T:export(tl.id);self:toast(err or ('Wrote '..r.json)) end
    local state=T:evaluate(tl,self.tl_time)
    if state then
        ImGui.TextDisabled('Camera: '..(state.camera and (tostring(state.camera.name)..(state.camera.blend<1 and string.format(' (moving %.0f%%)',state.camera.blend*100) or '')) or 'none'))
        for _,d in ipairs(state.dialogue) do ImGui.TextColored(0.6,0.9,1,1,d.speaker..': '..d.line) end
        if playing_this then for _,f in ipairs(status.facts_not_written or {}) do ImGui.TextDisabled('would set '..f.fact..' = '..f.value) end end
    end
    if self.tl_validation and self.tl_validation.timeline_id==tl.id then for _,i in ipairs(self.tl_validation.issues) do ImGui.BulletText(i.severity..': '..i.message) end end
    ImGui.Separator();ImGui.Text('TRACKS')
    for _,track in ipairs(tl.tracks) do
        if ImGui.Selectable(string.format('[%s] %s · %d key(s)%s%s##tltrack_%s',track.kind,track.name,#track.keys,track.muted and ' · muted' or '',track.enabled and '' or ' · disabled',track.id),self.tl_track_id==track.id) then self.tl_track_id=track.id end
        ImGui.SameLine();if ImGui.SmallButton((track.muted and 'UNMUTE' or 'MUTE')..'##tlmute_'..track.id) then T:update_track(tl.id,track.id,{muted=not track.muted}) end
        ImGui.SameLine();if ImGui.SmallButton('DELETE##tltrackdel_'..track.id) then local _,err=T:delete_track(tl.id,track.id);self:toast(err or 'Track deleted') end
        if self.tl_track_id==track.id then
            for _,k in ipairs(track.keys) do
                local label=k.camera_id and ((k.transition or 'cut')..' '..k.camera_id) or k.line and (k.speaker..': '..k.line) or k.fact and (k.fact..'='..k.value) or k.object_id and (k.action..' '..k.object_id) or k.label or (k.anim and k.anim.name) or (k.position and 'position') or k.subject_id or ''
                ImGui.BulletText(string.format('%.2f s  %s',k.time,label))
                ImGui.SameLine();if ImGui.SmallButton('GO##tlkeygo_'..k.id) then self.tl_time=k.time;if playing_this then T:seek(k.time) end end
                ImGui.SameLine();if ImGui.SmallButton('DEL##tlkeydel_'..k.id) then T:delete_key(tl.id,track.id,k.id) end
            end
        end
    end
    for _,kind in ipairs({'camera','dialogue','event','fact','marker','look_at'}) do
        if ImGui.SmallButton('+ '..kind..'##tladd_'..kind) then local tr,err=T:add_track(tl.id,{kind=kind});if tr then self.tl_track_id=tr.id end;self:toast(err or (kind..' track added')) end
        ImGui.SameLine()
    end
    ImGui.NewLine()
    self.tl_npc_key=select(1,ImGui.InputText('Live NPC key (for animation preview)',self.tl_npc_key,32))
    if ImGui.SmallButton('+ NPC TRACK FROM SELECTED OBJECT') then
        local tr,err=T:add_track(tl.id,{kind='npc',target_id=app.selected_object_id,npc_key=self.tl_npc_key~='' and self.tl_npc_key or nil})
        if tr then self.tl_track_id=tr.id end;self:toast(err or 'NPC track added')
    end
    local track=nil;for _,tr in ipairs(tl.tracks) do if tr.id==self.tl_track_id then track=tr end end
    if not track then ImGui.TextDisabled('Select a track to add keys at the playhead.');return end
    ImGui.Separator();ImGui.Text(string.format('ADD %s KEY AT %.2f s',track.kind:upper(),self.tl_time))
    local function add(payload,msg) payload.time=self.tl_time;local _,err=T:add_key(tl.id,track.id,payload);self:toast(err or msg) end
    if track.kind=='camera' then
        self.tl_move=select(1,ImGui.InputFloat('Move blend (s)',self.tl_move,0.5,1,'%.1f'))
        if ImGui.Button('CUT TO SELECTED CAMERA',200,26) then add({camera_id=app.selected_camera_id,transition='cut'},'Cut added') end
        ImGui.SameLine();if ImGui.Button('MOVE TO SELECTED CAMERA',210,26) then add({camera_id=app.selected_camera_id,transition='move',duration=self.tl_move},'Move added') end
    elseif track.kind=='dialogue' then
        self.tl_speaker=select(1,ImGui.InputText('Speaker',self.tl_speaker,48))
        self.tl_line=select(1,ImGui.InputText('Line',self.tl_line,256))
        self.tl_line_dur=select(1,ImGui.InputFloat('Line duration (s)',self.tl_line_dur,0.5,1,'%.1f'))
        if ImGui.Button('ADD LINE',120,26) then add({speaker=self.tl_speaker,line=self.tl_line,duration=self.tl_line_dur},'Line added') end
    elseif track.kind=='event' then
        for _,action in ipairs({'show','hide','toggle'}) do
            if ImGui.Button(action:upper()..' SELECTED OBJECT##tlev_'..action,190,26) then add({object_id=app.selected_object_id,action=action},'Event added') end
            ImGui.SameLine()
        end
        ImGui.NewLine()
    elseif track.kind=='fact' then
        self.tl_fact=select(1,ImGui.InputText('Fact name',self.tl_fact,96))
        self.tl_fact_value=select(1,ImGui.InputInt('Fact value',self.tl_fact_value))
        if ImGui.Button('ADD FACT',120,26) then add({fact=self.tl_fact,value=self.tl_fact_value},'Fact added') end
    elseif track.kind=='marker' then
        self.tl_marker=select(1,ImGui.InputText('Marker label',self.tl_marker,64))
        if ImGui.Button('ADD MARKER',120,26) then add({label=self.tl_marker},'Marker added') end
    elseif track.kind=='npc' then
        local o=app.model:get_object(track.target_id or '')
        if ImGui.Button('KEY NPC POSITION FROM ITS OBJECT',260,26) then
            if not o then self:toast('This track has no saved NPC object') else add({position={x=o.transform.position.x,y=o.transform.position.y,z=o.transform.position.z},yaw=o.transform.rotation.yaw},'Position keyed') end
        end
        if ImGui.Button('STOP ANIMATION KEY',180,26) then add({action='stop'},'Stop keyed') end
        ImGui.TextDisabled('Animation keys take AMM workspot data {name, comp, ent}; add them through MCP timeline_add_key.')
    elseif track.kind=='look_at' then
        if ImGui.Button('SELECTED OBJECT LOOKS AT CROSSHAIR',290,26) then
            local hit,err=app.game:aim_point(30)
            if not hit then self:toast(err or 'No aim point') else add({subject_id=app.selected_object_id,target={x=hit.position.x,y=hit.position.y,z=hit.position.z}},'Look-at added') end
        end
    end
end

function SpatialUI:draw_layers()
    local app=self.app;local L=app.layers
    ImGui.Text('LAYERS')
    if not L then ImGui.TextDisabled('The layer manager failed to load.');return end
    ImGui.TextWrapped('Hide/show despawns and respawns a layer’s live objects. Lock protects every object on the layer from edits. Isolate shows one layer only. Export-disabled layers (Debug by default) are left out of World Builder builds.')
    local data=L:list()
    if data.isolation then ImGui.TextColored(1,0.8,0.2,1,'Isolating '..tostring(data.isolation.layer_id));ImGui.SameLine();if ImGui.SmallButton('SHOW ALL LAYERS AGAIN') then local _,err=L:unisolate();self:toast(err or 'Layer visibility restored') end end
    for _,layer in ipairs(data.layers) do
        local r,g,b=L:color_rgb(layer.id);local c=layer.counts
        ImGui.TextColored(r,g,b,1,'■');ImGui.SameLine()
        ImGui.Text(layer.name..' ('..c.objects..' obj, '..c.live..' live'..(c.rooms>0 and (', '..c.rooms..' rooms') or '')..')'..(layer.visible and '' or ' [hidden]')..(layer.locked and ' [locked]' or '')..(layer.export and '' or ' [no export]'))
        ImGui.SameLine();if ImGui.SmallButton((layer.visible and 'HIDE' or 'SHOW')..'##layervis_'..layer.id) then local res,err=L:set_visible(layer.id,not layer.visible);self:toast(err or (layer.name..(res.visible and ' shown' or ' hidden')..' ('..(res.respawned+res.despawned)..' object(s))')) end
        ImGui.SameLine();if ImGui.SmallButton((layer.locked and 'UNLOCK' or 'LOCK')..'##layerlock_'..layer.id) then local res,err=L:set_locked(layer.id,not layer.locked);self:toast(err or (layer.name..(res.locked and ' locked' or ' unlocked'))) end
        ImGui.SameLine();if ImGui.SmallButton('ISOLATE##layeriso_'..layer.id) then local _,err=L:isolate(layer.id);self:toast(err or ('Showing only '..layer.name)) end
        ImGui.SameLine();if ImGui.SmallButton('SELECT##layersel_'..layer.id) then local res,err=L:select_all(layer.id,{premise_id=app.selected_premise_id});self:toast(err or ('Selected '..res.selected..' object(s)')) end
        ImGui.SameLine();if ImGui.SmallButton((layer.export and 'NO EXPORT' or 'EXPORT')..'##layerexp_'..layer.id) then local _,err=L:update(layer.id,{export=not layer.export});self:toast(err or 'Export flag changed') end
        ImGui.SameLine();if ImGui.SmallButton('MOVE SELECTION HERE##layermove_'..layer.id) then
            local ids={};for _,o in ipairs(app.selection:selected_objects()) do ids[#ids+1]=o.id end
            local res,err=L:assign(ids,layer.id);self:toast(err or ('Moved '..res.moved..' object(s) to '..layer.name))
        end
        ImGui.SameLine();if ImGui.SmallButton('EDIT##layeredit_'..layer.id) then self.layer_edit_id=layer.id end
    end
    for _,u in ipairs(data.unknown_layers) do ImGui.TextDisabled('! '..u.objects..' object(s) use unknown layer "'..tostring(u.id)..'"') end
    local edit=L:get(self.layer_edit_id)
    if edit then
        ImGui.Separator();ImGui.Text('EDIT LAYER: '..edit.id)
        local name,changed=ImGui.InputText('Layer name',edit.name,64);if changed then local _,err=L:update(edit.id,{name=name});if err then self:toast(err) end end
        local r,g,b=L:color_rgb(edit.id);local nr,ng,nb,cchanged=ImGui.ColorEdit3('Layer colour',r,g,b)
        if cchanged then local _,err=L:update(edit.id,{color=string.format('#%02X%02X%02X',math.floor(nr*255+0.5),math.floor(ng*255+0.5),math.floor(nb*255+0.5))});if err then self:toast(err) end end
        if ImGui.Button('DELETE LAYER (move objects to Props)',300,26) then local res,err=L:delete(edit.id,'decoration');if res then self.layer_edit_id='' end;self:toast(err or ('Deleted; moved '..res.moved..' item(s)')) end
    end
    ImGui.Separator()
    self.layer_new_name=select(1,ImGui.InputText('New layer name',self.layer_new_name,64))
    if ImGui.Button('CREATE LAYER',150,28) then local layer,err=L:create({name=self.layer_new_name});self:toast(err or ('Created '..layer.name)) end
    ImGui.SameLine();if ImGui.Button('PREVIEW AUTO-ASSIGN',190,28) then self.layer_auto=L:auto_assign({premise_id=app.selected_premise_id});self:toast(self.layer_auto.count..' object(s) would move to a more specific layer') end
    if self.layer_auto and self.layer_auto.count>0 then
        ImGui.SameLine();if ImGui.Button('APPLY AUTO-ASSIGN',180,28) then local res,err=L:auto_assign({premise_id=app.selected_premise_id,apply=true});self.layer_auto=nil;self:toast(err or ('Moved '..res.count..' object(s)')) end
        ImGui.BeginChild('##layer_auto',0,110,true)
        for _,m in ipairs(self.layer_auto.moves) do ImGui.TextDisabled(m.name..': '..m.from..' → '..m.to) end
        ImGui.EndChild()
    end
end

function SpatialUI:draw_visibility()
    local app=self.app;local vis=app.visibility
    ImGui.Text('OCCLUSION & VISIBILITY')
    if not vis then ImGui.TextDisabled('The visibility module failed to load.');return end
    ImGui.TextWrapped('Author World Builder Static Occluders, see which rooms each saved camera can potentially see through doors and windows, and find large meshes no camera can see. World Builder exposes occluders only; REDengine visibility volumes are not authorable here.')
    ImGui.Separator();ImGui.Text('OCCLUDERS')
    if ImGui.BeginCombo('Occluder mesh',self.vis_mesh) then for _,m in ipairs({'box','plane_one_sided','plane_two_sided'}) do if ImGui.Selectable(m..'##vismesh_'..m,self.vis_mesh==m) then self.vis_mesh=m end end;ImGui.EndCombo() end
    self.vis_size[1]=select(1,ImGui.InputFloat('Occluder width X (m)',self.vis_size[1],0.1,1,'%.2f'))
    if self.vis_mesh=='box' then self.vis_size[2]=select(1,ImGui.InputFloat('Occluder depth Y (m)',self.vis_size[2],0.1,1,'%.2f')) end
    self.vis_size[3]=select(1,ImGui.InputFloat('Occluder height Z (m)',self.vis_size[3],0.1,1,'%.2f'))
    if ImGui.Button('PLACE OCCLUDER AT AIM',210,28) then local r,err=vis:create_occluder({mesh=self.vis_mesh,size={x=self.vis_size[1],y=self.vis_size[2],z=self.vis_size[3]},source='aim'});self:toast(err or (r.spawned and 'Occluder placed' or ('Occluder saved; spawn failed: '..tostring(r.spawn_error)))) end
    ImGui.SameLine();if ImGui.Button('OCCLUDE SELECTED ROOM WALLS',250,28) then local r,err=vis:occlude_room({room_id=app.selected_room_id});self:toast(err or ('Added '..r.count..' wall occluder(s); openings left clear')) end
    local list=vis:list_occluders({premise_id=app.selected_premise_id}).items
    ImGui.TextDisabled(#list..' occluder(s) in the selected premise')
    ImGui.Separator();ImGui.Text('POTENTIALLY VISIBLE ROOMS FROM SAVED CAMERAS')
    self.vis_live=select(1,ImGui.Checkbox('Cross-check with live collision rays',self.vis_live))
    if ImGui.Button('COMPUTE VISIBLE ROOMS',210,28) then local r,err=vis:pvs({premise_id=app.selected_premise_id,live=self.vis_live});self.vis_pvs=r;self:toast(err or (#r.cameras..' camera(s) checked; '..#r.rooms_never_visible..' room(s) never visible')) end
    local r=self.vis_pvs
    if r then
        ImGui.BeginChild('##vis_pvs',0,170,true)
        for _,cam in ipairs(r.cameras) do
            local names={};for _,room in ipairs(cam.visible_rooms) do names[#names+1]=room.name..string.format(' (%d%%)',math.floor(room.visible_fraction*100)) end
            ImGui.TextWrapped(cam.name..' ['..cam.direction_source..']: '..(#names>0 and table.concat(names,', ') or 'no rooms visible'))
        end
        if #r.rooms_never_visible>0 then
            local names={};for _,room in ipairs(r.rooms_never_visible) do names[#names+1]=room.name end
            ImGui.TextDisabled('Never visible from any camera: '..table.concat(names,', '))
        end
        ImGui.EndChild()
    end
    ImGui.Separator();ImGui.Text('LARGE HIDDEN MESHES')
    if ImGui.Button('FIND HIDDEN LARGE MESHES',220,28) then local h,err=vis:hidden_meshes({premise_id=app.selected_premise_id});self.vis_hidden=h;self:toast(err or (h.count..' large mesh(es) hidden from every saved camera')) end
    local h=self.vis_hidden
    if h then
        ImGui.BeginChild('##vis_hidden',0,130,true)
        for i,m in ipairs(h.flagged) do
            ImGui.TextWrapped(string.format('%s  %.0f×%.0f×%.0f m%s — %s',m.name,m.dimensions.x,m.dimensions.y,m.dimensions.z,m.spawned and ' (spawned)' or '',m.suggestion))
            ImGui.SameLine();if ImGui.SmallButton('SELECT##vishidden_'..i) then app.selection:set('object',m.id) end
        end
        if h.meshes_without_bounds>0 then ImGui.TextDisabled(h.meshes_without_bounds..' mesh(es) have no imported bounds and were not checked (wb_bounds_import).') end
        ImGui.EndChild()
    end
end

local function perf_counts(c)
    return string.format('%d nodes · %d lights · %d audio · %d decals · %d VFX · %d dynamic · %d expensive · cost %.0f',
        c.nodes or 0,c.lights or 0,c.audio or 0,c.decals or 0,c.vfx or 0,c.dynamic or 0,c.expensive or 0,c.cost or 0)
end

function SpatialUI:draw_performance()
    local app=self.app;local perf=app.performance
    ImGui.Text('STREAMING / PERFORMANCE ANALYZER')
    if not perf then ImGui.TextDisabled('The performance module failed to load.');return end
    ImGui.TextWrapped('Estimates what each room, premise and exported sector asks the engine to stream. Costs are relative weights by resource type (not measured frame time); budgets are editable in project settings.')
    if ImGui.BeginCombo('Scope##perf',self.perf_scope=='premise' and 'Selected premise' or 'Whole project') then
        if ImGui.Selectable('Selected premise##perfscope',self.perf_scope=='premise') then self.perf_scope='premise' end
        if ImGui.Selectable('Whole project##perfscope',self.perf_scope=='project') then self.perf_scope='project' end
        ImGui.EndCombo()
    end
    if ImGui.Button('ANALYZE STREAMING COST',210,30) then
        self.perf_report=perf:analyze({premise_id=self.perf_scope=='premise' and app.selected_premise_id or nil})
        self:toast(#self.perf_report.warnings..' budget warning(s), '..#self.perf_report.clusters..' dense cluster(s)')
    end
    local r=self.perf_report
    if not r then ImGui.TextDisabled('Run the analysis to see rooms, clusters and budget warnings.') else
        ImGui.Text('Total: '..perf_counts(r.totals))
        ImGui.TextDisabled(r.player_position and 'Distances are from V’s current position.' or 'Player position unavailable; distances omitted.')
        ImGui.Text('ROOMS (highest cost first)')
        ImGui.BeginChild('##perf_rooms',0,150,true)
        for _,room in ipairs(r.rooms) do
            local over={};for _,o in ipairs(room.over_budget) do over[#over+1]=o.metric..' '..o.value..'/'..o.limit end
            ImGui.TextWrapped(room.name..(room.distance_from_player and string.format(' · %.0f m',room.distance_from_player) or '')..': '..perf_counts(room.counts)..(#over>0 and ('  ! over budget: '..table.concat(over,', ')) or ''))
        end
        ImGui.EndChild()
        ImGui.Text('DENSE CLUSTERS ('..r.cluster_stats.cell_size..' m cells, threshold cost '..r.cluster_stats.threshold..')')
        ImGui.BeginChild('##perf_clusters',0,110,true)
        for i,c in ipairs(r.clusters) do
            ImGui.TextWrapped(string.format('#%d r=%.0f m at (%.0f, %.0f)',i,c.radius,c.center.x,c.center.y)..(c.distance_from_player and string.format(' · %.0f m away',c.distance_from_player) or '')..': '..perf_counts(c.counts))
            ImGui.SameLine();if ImGui.SmallButton('SELECT##perfcluster_'..i) then local ok,err=perf:select_cluster(i);self:toast(err or ('Selected '..ok.selected..' object(s)')) end
        end
        if #r.clusters==0 then ImGui.TextDisabled('No unusually dense clusters.') end
        ImGui.EndChild()
        for _,l in ipairs(r.light_overlaps) do ImGui.TextDisabled('! '..tostring(l.name)..' overlaps '..l.overlapping..' other lights (limit '..l.limit..')') end
    end
    local sr=app.sector_inspector and app.sector_inspector.report
    if sr and sr.performance then
        ImGui.Separator();ImGui.Text('EXPORTED SECTORS ('..tostring(sr.export_name)..')')
        for _,sec in ipairs(sr.performance.sectors or {}) do
            local over={};for _,o in ipairs(sec.over_budget or {}) do over[#over+1]=o.metric end
            ImGui.BulletText(sec.name..': '..perf_counts(sec.counts)..((sec.long_streaming_total or 0)>0 and (' · '..sec.long_streaming_total..' long-range') or '')..(#over>0 and ('  ! '..table.concat(over,', ')) or ''))
        end
    else ImGui.TextDisabled('Load a sector report (Sectors tab) to include exported-sector costs.') end
end

function SpatialUI:draw_sectors()
    local app=self.app;local si=app.sector_inspector
    ImGui.Text('STREAMING-SECTOR INSPECTOR')
    if not si then ImGui.TextDisabled('The sector inspector module failed to load.');return end
    ImGui.TextWrapped('Shows the last report from the MCP tool sector_inspect or the Build Mod sectors stage: sector bounds, node/NodeRef/device/PSID counts, cross-sector references, and nodes likely in the wrong sector.')
    if ImGui.Button('LOAD LATEST REPORT',180,28) or (not si.report and not si.last_error) then local r,err=si:load();self:toast(err or ('Loaded '..r.sector_count..' sector(s), '..r.node_count..' node(s)')) end
    local r=si.report
    if not r then ImGui.TextDisabled(si.last_error or 'No report loaded.');return end
    local c=r.flag_counts or {}
    ImGui.Text(tostring(r.export_name)..': '..r.sector_count..' sector(s), '..r.node_count..' node(s), '..r.device_count..' device(s), '..tostring(r.ps_entry_count)..' persistent entries')
    ImGui.TextDisabled((c.error or 0)..' error(s) · '..(c.warning or 0)..' warning(s) · '..(c.info or 0)..' info · '..#(r.likely_wrong_sector or {})..' likely wrong sector · '..#(r.cross_sector_references or {})..' cross-sector reference(s)')
    ImGui.BeginChild('##sector_list',0,130,true)
    for _,sec in ipairs(r.sectors or {}) do
        local b=sec.bounds
        local box=b and string.format(' [%.0f,%.0f,%.0f → %.0f,%.0f,%.0f]',b.min.x,b.min.y,b.min.z,b.max.x,b.max.y,b.max.z) or ' [no bounds]'
        if ImGui.Selectable(sec.name..' · '..tostring(sec.category)..' L'..tostring(sec.level)..' · '..sec.node_count..' nodes, '..sec.node_refs..' refs, '..sec.devices..' dev, '..sec.ps_entries..' PS'..box..'##sec_'..sec.index,self.sector_filter==sec.name) then
            self.sector_filter=self.sector_filter==sec.name and '' or sec.name
        end
    end
    ImGui.EndChild()
    if ImGui.BeginCombo('Severity##sectors',self.sector_severity=='' and 'all' or self.sector_severity) then
        for _,level in ipairs({'','error','warning','info'}) do if ImGui.Selectable((level=='' and 'all' or level)..'##sev_'..level,self.sector_severity==level) then self.sector_severity=level end end
        ImGui.EndCombo()
    end
    ImGui.BeginChild('##sector_flags',0,200,true)
    for i,f in ipairs(r.flags or {}) do
        if (self.sector_filter=='' or f.sector==self.sector_filter) and (self.sector_severity=='' or f.severity==self.sector_severity) then
            ImGui.TextWrapped('['..f.severity..'] '..tostring(f.sector or '-')..' · '..tostring(f.node_name or f.device_hash or f.psid or '')..(f.suggested_sector and (' → '..f.suggested_sector) or '')..': '..f.message)
            if f.object_id then ImGui.SameLine();if ImGui.SmallButton('SELECT##secflag_'..i) then local ok,err=si:select_flagged(i);self:toast(err or ('Selected '..ok.name)) end end
        end
    end
    ImGui.EndChild()
    local refs=r.cross_sector_references or {}
    if #refs>0 then
        ImGui.Text('CROSS-SECTOR REFERENCES')
        ImGui.BeginChild('##sector_refs',0,100,true)
        for _,ref in ipairs(refs) do ImGui.TextDisabled(ref.kind..': '..tostring(ref.from_sector)..' → '..tostring(ref.target_sector or '?')..' ('..ref.status..') '..tostring(ref.target_ref or ref.to_device or '')) end
        ImGui.EndChild()
    end
end

function SpatialUI:_collision_args(extra)
    local args={shape=self.col_shape,preset=self.col_preset,material=self.col_material~='' and self.col_material or nil,visualize=self.col_visualize,name=self.col_name,
        premise_id=self.app.selected_premise_id,room_id=self.app.selected_room_id}
    if self.col_shape=='box' then args.size={x=self.col_size[1],y=self.col_size[2],z=self.col_size[3]} else args.radius=self.col_radius;args.height=self.col_height end
    for k,v in pairs(extra or {}) do args[k]=v end
    return args
end

function SpatialUI:draw_collision()
    local app=self.app;local col=app.collision
    ImGui.Text('COLLISION AUTHORING')
    if not col then ImGui.TextDisabled('The collision module failed to load. Check the debug log.');return end
    ImGui.TextWrapped('Creates real World Builder worldCollisionNode colliders. The preset is the collision layer; its physics groups decide what it blocks. Visualization draws World Builder’s collider wireframe. Passability is an estimate from saved colliders; cross-check with live rays.')
    local presets=col:presets();local preset=presets[self.col_preset+1] or presets[34]
    ImGui.Separator();ImGui.Text('NEW PRIMITIVE')
    if ImGui.BeginCombo('Shape##col',self.col_shape) then for _,shape in ipairs({'box','capsule','sphere'}) do if ImGui.Selectable(shape..'##colshape_'..shape,self.col_shape==shape) then self.col_shape=shape end end;ImGui.EndCombo() end
    if self.col_shape=='box' then
        self.col_size[1]=select(1,ImGui.InputFloat('Width X (m)',self.col_size[1],0.05,0.5,'%.2f'))
        self.col_size[2]=select(1,ImGui.InputFloat('Depth Y (m)',self.col_size[2],0.05,0.5,'%.2f'))
        self.col_size[3]=select(1,ImGui.InputFloat('Height Z (m)',self.col_size[3],0.05,0.5,'%.2f'))
    else
        self.col_radius=select(1,ImGui.InputFloat('Radius (m)',self.col_radius,0.05,0.5,'%.2f'))
        if self.col_shape=='capsule' then self.col_height=select(1,ImGui.InputFloat('Capsule height (m)',self.col_height,0.05,0.5,'%.2f')) end
    end
    if ImGui.BeginCombo('Collision preset / layer',preset.name) then
        for _,p in ipairs(presets) do if ImGui.Selectable(p.name..(p.blocks_player and ' [P]' or '')..(p.blocks_npc and ' [N]' or '')..'##colpreset_'..p.index,self.col_preset==p.index) then self.col_preset=p.index end end
        ImGui.EndCombo()
    end
    ImGui.TextDisabled('Groups: '..table.concat(preset.groups,' + ')..(preset.blocks_player and ' · blocks player' or '')..(preset.blocks_npc and ' · blocks NPC' or ''))
    self.col_material=select(1,ImGui.InputText('Physics material (blank = WB default)',self.col_material,64))
    self.col_name=select(1,ImGui.InputText('Name##col',self.col_name,96))
    self.col_visualize=select(1,ImGui.Checkbox('Visualize collider',self.col_visualize))
    if ImGui.Button('PLACE COLLIDER AT AIM',200,28) then local r,err=col:create_primitive(self:_collision_args({source='aim'}));self:toast(err or r.warning or (r.spawned and 'Collider placed' or ('Collider saved; spawn failed: '..tostring(r.spawn_error)))) end
    ImGui.SameLine();if ImGui.Button('PLACE AT PLAYER##col',170,28) then local r,err=col:create_primitive(self:_collision_args({source='player'}));self:toast(err or (r.spawned and 'Collider placed' or ('Collider saved; spawn failed: '..tostring(r.spawn_error)))) end
    ImGui.SameLine();if ImGui.Button('FIT TO SELECTED OBJECT',210,28) then local r,err=col:fit_to_object(self:_collision_args({object_id=app.selected_object_id,padding=0.02}));self:toast(err or 'Box collider fitted to the object bounds') end
    ImGui.Separator();ImGui.Text('IMPORTED COLLISION MESH')
    self.col_mesh_query=select(1,ImGui.InputText('Search collision meshes',self.col_mesh_query,128))
    if ImGui.Button('SEARCH COLLISION CATALOG',220,28) then local r,err=col:search_meshes({query=self.col_mesh_query});self.col_mesh_results=r and r.items or {};self:toast(err or ('Found '..#self.col_mesh_results..' collision meshes')) end
    ImGui.BeginChild('##col_mesh_list',0,90,true)
    for i,item in ipairs(self.col_mesh_results or {}) do if ImGui.Selectable(item.name..'##colmesh_'..i,self.col_mesh_path==item.path) then self.col_mesh_path=item.path end end
    ImGui.EndChild()
    if ImGui.Button('IMPORT MESH AT AIM',180,28) then local r,err=col:import_mesh(self:_collision_args({resource_path=self.col_mesh_path,source='aim'}));self:toast(err or 'Collision mesh placed') end
    ImGui.Separator();ImGui.Text('LAYERS & VISUALIZATION')
    local layers=col:layers({premise_id=app.selected_premise_id}).layers
    for _,l in ipairs(layers) do ImGui.BulletText(l.preset..': '..l.count..' collider(s), '..l.visualized..' visualized'..(l.blocks_player and ' · P' or '')..(l.blocks_npc and ' · N' or '')) end
    if #layers==0 then ImGui.TextDisabled('No collision objects in the selected premise.') end
    if ImGui.Button('SHOW ALL COLLISION',180,28) then local r,err=col:set_visualization({premise_id=app.selected_premise_id,visible=true});self:toast(err or ('Visualization on for '..r.changed..' collider(s)')) end
    ImGui.SameLine();if ImGui.Button('HIDE ALL COLLISION',180,28) then local r,err=col:set_visualization({premise_id=app.selected_premise_id,visible=false});self:toast(err or ('Visualization off for '..r.changed..' collider(s)')) end
    local obj=app.selected_object_id and app.model:get_object(app.selected_object_id)
    if obj and col:is_collision(obj) then
        ImGui.Separator();ImGui.Text('SELECTED COLLIDER: '..obj.name)
        local data=obj.metadata.world_builder.entry.data
        if self.col_edit_id~=obj.id then self.col_edit_id=obj.id;self.col_edit={preset=tonumber(data.preset) or 33,visualize=data.previewed~=false} end
        local e=self.col_edit;local ep=presets[e.preset+1] or preset
        if ImGui.BeginCombo('Layer##coledit',ep.name) then for _,p in ipairs(presets) do if ImGui.Selectable(p.name..'##coleditp_'..p.index,e.preset==p.index) then e.preset=p.index end end;ImGui.EndCombo() end
        e.visualize=select(1,ImGui.Checkbox('Visualize##coledit',e.visualize))
        if ImGui.Button('APPLY TO COLLIDER',180,28) then local r,err=col:update(obj.id,{preset=e.preset,visualize=e.visualize});if r then self.col_edit_id=nil end;self:toast(err or r.warning or 'Collider updated') end
        ImGui.TextDisabled('Resize and move with the normal transform tools; collider dimensions follow the object scale.')
    end
    ImGui.Separator();ImGui.Text('PASSABILITY PREVIEW')
    if ImGui.BeginCombo('Actor##pass',self.pass_actor) then for _,a in ipairs({'both','player','npc'}) do if ImGui.Selectable(a..'##passactor_'..a,self.pass_actor==a) then self.pass_actor=a end end;ImGui.EndCombo() end
    self.pass_step=select(1,ImGui.InputFloat('Grid step (m)',self.pass_step,0.1,0.5,'%.2f'))
    self.pass_half=select(1,ImGui.InputFloat('Half size around V (m)',self.pass_half,1,5,'%.0f'))
    self.pass_live=select(1,ImGui.Checkbox('Cross-check with live collision rays',self.pass_live))
    if ImGui.Button('SET GOAL FROM AIM##pass',190,28) then local hit,err=app.game:aim_point(20);if hit then self.pass_goal={x=hit.position.x,y=hit.position.y,z=hit.position.z} end;self:toast(err or 'Goal set') end
    ImGui.SameLine();if ImGui.Button('PREVIEW PASSABILITY',190,28) then
        local args={actor=self.pass_actor,grid_step=self.pass_step,live=self.pass_live,goal=self.pass_goal}
        local room=app.model:get_room(app.selected_room_id)
        if room then args.room_id=room.id else args.half_width=self.pass_half;args.premise_id=app.selected_premise_id end
        if self.pass_goal then local t=app.game:capture_transform();if t then args.start={x=t.position.x,y=t.position.y,z=t.position.z} end end
        local r,err=col:passability(args);self.pass_result=r
        local summary=r and (r.routes.player or r.routes.npc) or nil
        self:toast(err or ('Passability: '..r.colliders_considered..' collider(s)'..(summary and summary.status and (' · '..summary.status) or '')))
    end
    local r=self.pass_result
    if r then
        for name,route in pairs(r.routes) do ImGui.TextDisabled(name..': '..route.free_cells..' free / '..route.blocked_cells..' blocked'..(route.status and (' · '..route.status) or '')) end
        if r.live then ImGui.TextDisabled('Live rays: '..tostring(r.live.status or r.live.error)) end
        ImGui.BeginChild('##pass_map',0,180,true)
        for _,line in ipairs(r.map) do ImGui.Text(line) end
        ImGui.EndChild()
        ImGui.TextDisabled('# both  p player  n NPC  . free  * route  S start  G goal · top row = far edge')
    end
end

function SpatialUI:draw_environment()
    local app=self.app;local envs=app.environment
    ImGui.Text('ENVIRONMENT & WEATHER PREVIEW')
    if not envs then ImGui.TextDisabled('The environment module failed to load. Check the debug log.');return end
    ImGui.TextWrapped('Save time, weather (which sets rain) and a local fog volume as a named authoring environment. Preview applies it; Force holds the clock and weather while you work or capture screenshots. Restore returns the original time and hands weather back to the game cycle.')
    local status=envs:status();local cur=status.current or {}
    ImGui.TextDisabled('Live: '..(cur.hour and string.format('%02d:%02d',cur.hour,cur.minute) or 'time ?')..' · '..tostring(cur.weather or 'weather ?')..(cur.rain_intensity and string.format(' · rain %.2f',cur.rain_intensity) or ''))
    self.env_new_name=select(1,ImGui.InputText('New environment name',self.env_new_name,96))
    if ImGui.Button('NEW ENVIRONMENT',170,28) then local env,err=envs:create({name=self.env_new_name});if env then self.env_selected_id=env.id end;self:toast(err or 'Environment created') end
    ImGui.SameLine();if ImGui.Button('CAPTURE CURRENT CONDITIONS',240,28) then local env,err=envs:create({name=self.env_new_name,capture_current=true});if env then self.env_selected_id=env.id end;self:toast(err or 'Current time and weather saved') end
    ImGui.BeginChild('##env_list',230,300,true)
    for _,env in ipairs(envs:list().items) do
        local mark=status.active and status.environment_id==env.id and ' ●' or ''
        if ImGui.Selectable(env.name..mark..'##env_'..env.id,self.env_selected_id==env.id) then self.env_selected_id=env.id end
    end
    ImGui.EndChild();ImGui.SameLine();ImGui.BeginChild('##env_edit',0,300,true)
    local env=app.model:get_environment(self.env_selected_id)
    if env then
        if self.env_edit_id~=env.id then self.env_edit_id=env.id;self.env_edit=app.util.deepcopy(env) end
        local e=self.env_edit
        e.name=select(1,ImGui.InputText('Name##env',e.name,96))
        e.time.enabled=select(1,ImGui.Checkbox('Set time',e.time.enabled))
        e.time.hour=select(1,ImGui.InputInt('Hour##env',e.time.hour));e.time.minute=select(1,ImGui.InputInt('Minute##env',e.time.minute))
        e.weather.enabled=select(1,ImGui.Checkbox('Set weather',e.weather.enabled))
        local label=e.weather.state
        for _,w in ipairs(envs:weather_states()) do if w.id==e.weather.state then label=w.name..(w.rain~='none' and (' — rain: '..w.rain) or '') end end
        if ImGui.BeginCombo('Weather##env',label) then
            for _,w in ipairs(envs:weather_states()) do if ImGui.Selectable(w.name..(w.rain~='none' and (' — rain: '..w.rain) or '')..(w.fog and ' — haze/fog' or '')..'##w_'..w.id,e.weather.state==w.id) then e.weather.state=w.id end end
            ImGui.EndCombo()
        end
        e.weather.state=select(1,ImGui.InputText('Weather state CName',e.weather.state,96))
        e.weather.blend_time=select(1,ImGui.InputFloat('Blend time (s)',e.weather.blend_time,1,5,'%.1f'))
        e.weather.priority=select(1,ImGui.InputInt('Weather priority',e.weather.priority))
        e.fog.enabled=select(1,ImGui.Checkbox('Local fog volume (World Builder)',e.fog.enabled))
        if e.fog.enabled then
            if ImGui.BeginCombo('Fog anchor',e.fog.anchor) then for _,a in ipairs({'player','camera','premise'}) do if ImGui.Selectable(a..'##fog_'..a,e.fog.anchor==a) then e.fog.anchor=a end end;ImGui.EndCombo() end
            e.fog.size.x=select(1,ImGui.InputFloat('Fog width (m)',e.fog.size.x,1,10,'%.0f'))
            e.fog.size.y=select(1,ImGui.InputFloat('Fog depth (m)',e.fog.size.y,1,10,'%.0f'))
            e.fog.size.z=select(1,ImGui.InputFloat('Fog height (m)',e.fog.size.z,1,10,'%.0f'))
            e.fog.density_factor=select(1,ImGui.InputFloat('Density factor',e.fog.density_factor,0.05,0.5,'%.2f'))
            e.fog.density_falloff=select(1,ImGui.InputFloat('Density falloff',e.fog.density_falloff,0.05,0.5,'%.2f'))
            e.fog.absorption=select(1,ImGui.InputFloat('Absorption',e.fog.absorption,0.05,0.5,'%.2f'))
            e.fog.blend_falloff=select(1,ImGui.InputFloat('Blend falloff',e.fog.blend_falloff,0.05,0.5,'%.2f'))
            local r,g,b,changed=ImGui.ColorEdit3('Fog color',e.fog.color[1],e.fog.color[2],e.fog.color[3]);if changed then e.fog.color={r,g,b} end
        end
        e.exposure_note=select(1,ImGui.InputText('Exposure note (not applied)',e.exposure_note,160))
        if ImGui.Button('SAVE ENVIRONMENT',170,28) then
            local result,err=envs:update(env.id,{name=e.name,time=e.time,weather=e.weather,fog=e.fog,exposure_note=e.exposure_note})
            if result then self.env_edit_id=nil end
            self:toast(err or result.warning or (result.reapplied and 'Saved and re-applied to the preview' or 'Environment saved'))
        end
        ImGui.SameLine();if ImGui.Button('DELETE ENVIRONMENT',180,28) then local ok,err=envs:delete(env.id);if ok then self.env_selected_id='' end;self:toast(err or 'Environment deleted') end
    else ImGui.TextDisabled('Select or create an environment.') end
    ImGui.EndChild()
    ImGui.Separator()
    self.env_force=select(1,ImGui.Checkbox('Force (hold time and weather) while previewing',self.env_force))
    if ImGui.Button('PREVIEW ENVIRONMENT',190,30) then local result,err=envs:preview(self.env_selected_id,{force=self.env_force});self:toast(err or (result.warning and ('Previewing with warnings: '..result.warning)) or 'Environment applied') end
    ImGui.SameLine();if ImGui.Button('RESTORE ORIGINAL',170,30) then local result,err=envs:restore();self:toast(err or 'Original time restored; weather returned to the game cycle') end
    if status.active then
        ImGui.TextDisabled('Previewing '..tostring(status.name)..(status.force and ' (forced)' or '')..(status.fog_spawned and ' · fog volume live' or ''))
        if not status.force then ImGui.SameLine();if ImGui.SmallButton('FORCE NOW') then envs:set_force(true) end
        else ImGui.SameLine();if ImGui.SmallButton('STOP FORCING') then envs:set_force(false) end end
        for _,w in ipairs(status.warnings or {}) do ImGui.TextDisabled('! '..w) end
    end
    self:draw_screenshot_mode()
end

function SpatialUI:draw_screenshot_mode()
    local app=self.app;local mode=app.screenshot_mode
    ImGui.Separator();ImGui.Text('DETERMINISTIC SCREENSHOT MODE')
    if not mode then ImGui.TextDisabled('The screenshot mode module failed to load.');return end
    ImGui.TextWrapped('Used by visual_regression_capture(deterministic=true). Hides HUD and post effects through game settings (previous values are recorded and restored), forces the selected environment, and freezes NPCs/traffic only while shooting.')
    local cfg=mode:settings();local changed
    cfg.hide_hud,changed=ImGui.Checkbox('Hide HUD',cfg.hide_hud);if changed then app:mark_dirty() end
    cfg.disable_post_effects,changed=ImGui.Checkbox('Disable motion blur / film grain / DOF / lens effects',cfg.disable_post_effects);if changed then app:mark_dirty() end
    cfg.freeze_world,changed=ImGui.Checkbox('Freeze NPCs, traffic and particles while shooting',cfg.freeze_world);if changed then app:mark_dirty() end
    if ImGui.Button('CHECK GAME SETTINGS',190,28) then
        local caps=mode:capabilities();local missing=0
        for _,row in ipairs(caps.settings) do if not row.available then missing=missing+1 end end
        self.shot_caps=caps;self:toast(#caps.settings-missing..' of '..#caps.settings..' settings available'..(caps.time_dilation and '; world freeze available' or '; world freeze unavailable'))
    end
    local status=mode:status()
    if not status.active then
        ImGui.SameLine();if ImGui.Button('ENTER SCREENSHOT MODE',210,28) then local result,err=mode:enter({environment_id=app.model:get_environment(self.env_selected_id) and self.env_selected_id or nil});self:toast(err or ('Screenshot mode on; '..#result.unavailable..' setting(s) unavailable')) end
    else
        ImGui.SameLine();if ImGui.Button(status.frozen and 'UNFREEZE WORLD' or 'FREEZE WORLD',150,28) then local _,err;if status.frozen then _,err=mode:unfreeze() else _,err=mode:freeze() end;self:toast(err or (status.frozen and 'World unfrozen' or 'World frozen')) end
        ImGui.SameLine();if ImGui.Button('RESTORE SCREENSHOT MODE',220,28) then local result,err=mode:restore();self:toast(err or ('Restored '..result.settings_restored..' setting(s)')) end
        ImGui.TextDisabled('Active: '..#status.applied..' setting(s) managed'..(status.frozen and ' · world frozen' or '')..(status.environment_id and ' · environment forced' or ''))
        for _,row in ipairs(status.unavailable or {}) do ImGui.TextDisabled('! '..row.group..'/'..row.name..': '..tostring(row.reason)) end
    end
    if self.shot_caps and not status.active then
        for _,row in ipairs(self.shot_caps.settings) do if not row.available then ImGui.TextDisabled('! '..row.group..'/'..row.name..' unavailable') end end
    end
end

function SpatialUI:draw_vfx()
    local app=self.app;local vfx=app.vfx
    ImGui.Text('VFX / PARTICLE EDITOR')
    if not vfx then ImGui.TextDisabled('The VFX module failed to load. Check the debug log.');return end
    ImGui.TextWrapped('Searches World Builder’s loaded Particles (worldStaticParticleNode) and Effects (worldEffectNode) catalogs. Categories are keyword filters over real catalog rows. Preview spawns one temporary node that is not saved; place it to keep it.')
    self.vfx_query=select(1,ImGui.InputText('Search particles/effects',self.vfx_query,160))
    local category_label='All categories'
    for _,c in ipairs(vfx:categories()) do if c.id==self.vfx_category then category_label=c.name end end
    if ImGui.BeginCombo('Category##vfx',category_label) then
        if ImGui.Selectable('All categories',self.vfx_category=='all') then self.vfx_category='all' end
        for _,c in ipairs(vfx:categories()) do if ImGui.Selectable(c.name..'##vfxcat_'..c.id,self.vfx_category==c.id) then self.vfx_category=c.id end end
        ImGui.EndCombo()
    end
    local backend_label=self.vfx_backend=='particle' and 'Particles only' or self.vfx_backend=='effect' and 'Effects only' or 'Particles + Effects'
    if ImGui.BeginCombo('Source##vfx',backend_label) then
        if ImGui.Selectable('Particles + Effects',self.vfx_backend=='all') then self.vfx_backend='all' end
        if ImGui.Selectable('Particles only',self.vfx_backend=='particle') then self.vfx_backend='particle' end
        if ImGui.Selectable('Effects only',self.vfx_backend=='effect') then self.vfx_backend='effect' end
        ImGui.EndCombo()
    end
    if ImGui.Button('SEARCH VFX CATALOG',190,28) then
        local result,err=vfx:search({query=self.vfx_query,category=self.vfx_category,backend=self.vfx_backend,limit=200})
        self.vfx_results=result;self.vfx_selected=nil
        self:toast(err or ('Showing '..result.shown..' of '..result.total..' matching effects'))
    end
    if self.vfx_results and self.vfx_results.total>self.vfx_results.shown then ImGui.SameLine();ImGui.TextDisabled(self.vfx_results.total-self.vfx_results.shown..' more; refine the search') end
    ImGui.BeginChild('##vfx_catalog',0,150,true)
    for i,item in ipairs(self.vfx_results and self.vfx_results.items or {}) do
        local tag=item.backend=='particle' and 'P' or 'E'
        if ImGui.Selectable('['..tag..'] ['..item.category..'] '..item.name..'  '..tostring(item.path)..'##vfxrow_'..i,self.vfx_selected==item) then
            self.vfx_selected=item;if self.vfx_name=='' then self.vfx_name=item.name end
        end
    end
    ImGui.EndChild()
    ImGui.TextDisabled(self.vfx_selected and ('Selected: '..self.vfx_selected.path) or 'No row selected; placement uses the first search match.')
    self.vfx_name=select(1,ImGui.InputText('Name##vfx',self.vfx_name,128))
    ImGui.Text('Orientation (degrees)')
    self.vfx_rotation[1]=select(1,ImGui.InputFloat('Roll##vfx',self.vfx_rotation[1],1,15,'%.1f'))
    self.vfx_rotation[2]=select(1,ImGui.InputFloat('Pitch##vfx',self.vfx_rotation[2],1,15,'%.1f'))
    self.vfx_rotation[3]=select(1,ImGui.InputFloat('Yaw##vfx',self.vfx_rotation[3],1,15,'%.1f'))
    self.vfx_align=select(1,ImGui.Checkbox('Align up axis to aimed surface',self.vfx_align))
    ImGui.Text('Scale (saved; applied in native build)')
    self.vfx_scale[1]=select(1,ImGui.InputFloat('Scale X##vfx',self.vfx_scale[1],0.05,0.5,'%.2f'))
    self.vfx_scale[2]=select(1,ImGui.InputFloat('Scale Y##vfx',self.vfx_scale[2],0.05,0.5,'%.2f'))
    self.vfx_scale[3]=select(1,ImGui.InputFloat('Scale Z##vfx',self.vfx_scale[3],0.05,0.5,'%.2f'))
    self.vfx_emission=select(1,ImGui.InputFloat('Emission rate (particles)',self.vfx_emission,0.05,0.5,'%.2f'))
    self.vfx_respawn_on_move=select(1,ImGui.Checkbox('Respawn on move (particles)',self.vfx_respawn_on_move))
    self.vfx_distance=select(1,ImGui.InputFloat('Aim distance (m)',self.vfx_distance,0.5,2,'%.1f'))
    ImGui.Separator();ImGui.Text('LIVE PREVIEW')
    local status=vfx:preview_status()
    ImGui.TextDisabled(status.active and ('Previewing '..tostring(status.resource_name)..(status.follow and ' (following aim)' or ' (pinned)')) or 'No preview active.')
    self.vfx_follow=select(1,ImGui.Checkbox('Follow aim',self.vfx_follow))
    if ImGui.Button('PREVIEW AT AIM##vfx',150,30) then local result,err=vfx:preview_start(self:_vfx_args({source='aim'}));self:toast(err or (result.warning or 'Preview spawned; it is not saved until placed')) end
    ImGui.SameLine();if ImGui.Button('UPDATE PREVIEW##vfx',150,30) then local result,err=vfx:preview_update(self:_vfx_args());self:toast(err or 'Preview updated') end
    if ImGui.Button('PLACE PREVIEW##vfx',150,30) then local result,err=vfx:preview_commit(self:_vfx_args());self:toast(err or (result.spawned and 'Effect saved and spawned' or ('Effect saved; live spawn failed: '..tostring(result.spawn_error)))) end
    ImGui.SameLine();if ImGui.Button('CLEAR PREVIEW##vfx',150,30) then local ok,err=vfx:preview_clear();self:toast(err or 'Preview removed') end
    ImGui.Separator();ImGui.Text('PLACE DIRECTLY')
    if ImGui.Button('PLACE AT AIM##vfx',150,30) then local result,err=vfx:create(self:_vfx_args({source='aim'}));self:toast(err or result.warning or (result.spawned and 'Effect saved and spawned' or ('Effect saved; live spawn failed: '..tostring(result.spawn_error)))) end
    ImGui.SameLine();if ImGui.Button('PLACE AT PLAYER##vfx',160,30) then local result,err=vfx:create(self:_vfx_args({source='player'}));self:toast(err or (result.spawned and 'Effect saved and spawned' or ('Effect saved; live spawn failed: '..tostring(result.spawn_error)))) end
    ImGui.Separator();ImGui.Text('PLACED EFFECTS');ImGui.BeginChild('##vfx_list',245,230,true)
    for _,row in ipairs(vfx:list().items) do if ImGui.Selectable('['..tostring(row.category)..'] '..row.name..'##vfxobj_'..row.id,app.selection:is('object',row.id)) then app.selection:set('object',row.id) end end
    ImGui.EndChild();ImGui.SameLine();ImGui.BeginChild('##vfx_edit',0,230,true)
    local obj=app.selected_object_id and app.model:get_object(app.selected_object_id);local cfg=obj and obj.metadata and obj.metadata.vfx
    if obj and cfg then
        if self.vfx_edit_id~=obj.id then
            local r=obj.transform.rotation or {}
            self.vfx_edit_id=obj.id;self.vfx_edit={scale={cfg.scale.x,cfg.scale.y,cfg.scale.z},rotation={r.roll or 0,r.pitch or 0,r.yaw or 0},emission=cfg.emission_rate or 1,respawn=cfg.respawn_on_move==true}
        end
        local e=self.vfx_edit;ImGui.Text(obj.name);ImGui.TextDisabled(tostring(cfg.backend)..' · '..tostring(cfg.resource_path))
        e.rotation[1]=select(1,ImGui.InputFloat('Roll##vfxedit',e.rotation[1],1,15,'%.1f'))
        e.rotation[2]=select(1,ImGui.InputFloat('Pitch##vfxedit',e.rotation[2],1,15,'%.1f'))
        e.rotation[3]=select(1,ImGui.InputFloat('Yaw##vfxedit',e.rotation[3],1,15,'%.1f'))
        e.scale[1]=select(1,ImGui.InputFloat('Scale X##vfxedit',e.scale[1],0.05,0.5,'%.2f'))
        e.scale[2]=select(1,ImGui.InputFloat('Scale Y##vfxedit',e.scale[2],0.05,0.5,'%.2f'))
        e.scale[3]=select(1,ImGui.InputFloat('Scale Z##vfxedit',e.scale[3],0.05,0.5,'%.2f'))
        if cfg.backend=='particle' then
            e.emission=select(1,ImGui.InputFloat('Emission rate##vfxedit',e.emission,0.05,0.5,'%.2f'))
            e.respawn=select(1,ImGui.Checkbox('Respawn on move##vfxedit',e.respawn))
        end
        if ImGui.Button('APPLY VFX SETTINGS',190,30) then
            local result,err=vfx:update(obj.id,{scale={x=e.scale[1],y=e.scale[2],z=e.scale[3]},roll=e.rotation[1],pitch=e.rotation[2],yaw=e.rotation[3],emission_rate=cfg.backend=='particle' and e.emission or nil,respawn_on_move=cfg.backend=='particle' and e.respawn or nil})
            if result then self.vfx_edit_id=nil end
            self:toast(err or result.warning or (result.respawned and 'Effect updated and respawned' or result.live_updated and 'Effect updated live' or 'Effect settings saved'))
        end
        ImGui.SameLine();if ImGui.Button('DELETE EFFECT') then app.selection:set('object',obj.id);local ok,err=app.actions:delete_selected();self:toast(err or (ok and 'Effect deleted' or 'Delete failed')) end
    else ImGui.TextDisabled('Select a placed effect to edit it.') end
    ImGui.EndChild()
    ImGui.TextDisabled('World Builder previews particles/effects at 1:1. Scale is written to the native node by Build Mod; confirm the look in game after building.')
end

function SpatialUI:draw_ambient_audio()
    local app=self.app
    ImGui.Text('AMBIENT AUDIO — WORLD BUILDER NODES')
    ImGui.TextWrapped('Point emitters and room soundstage zones are saved as native World Builder objects. Select a room before creating a reverb zone. Zone effects become active in a native world edit export; CET/World Builder preview cannot audition the finished reverb.')
    ImGui.Separator();ImGui.Text('POINT SOUND EMITTER')
    self.audio_query=select(1,ImGui.InputText('Search loaded game audio',self.audio_query,160))
    if ImGui.Button('SEARCH AUDIO CATALOG',190,28) then
        local result,err=app.world_builder:search('audio',self.audio_query,80,true)
        self.audio_results=result and result.items or {};self.audio_selected_path=''
        self:toast(err or ('Loaded '..#self.audio_results..' matching audio events'))
    end
    ImGui.SameLine();ImGui.TextDisabled('Search is limited to World Builder’s loaded Audio Emitters catalog.')
    ImGui.BeginChild('##ambient_audio_catalog',0,140,true)
    for _,item in ipairs(self.audio_results or {}) do
        local label=(item.name or item.path)..'  ['..tostring(item.path)..']'
        if ImGui.Selectable(label,self.audio_selected_path==item.path) then self.audio_selected_path=item.path end
    end
    ImGui.EndChild()
    self.audio_name=select(1,ImGui.InputText('Emitter name',self.audio_name,128))
    self.audio_radius=select(1,ImGui.InputFloat('Radius (m)',self.audio_radius,0.25,1,'%.2f'))
    self.audio_metadata=select(1,ImGui.InputText('Emitter metadata name (optional)',self.audio_metadata,128))
    if ImGui.Button('PLACE EMITTER AT AIM',200,30) then
        local obj,err=app.ambient_audio:create_emitter({resource_path=self.audio_selected_path~='' and self.audio_selected_path or nil,query=self.audio_query,name=self.audio_name,radius=self.audio_radius,emitter_metadata_name=self.audio_metadata,source='aim',room_id=app.selected_room_id,premise_id=app.selected_premise_id})
        self:toast(err or (obj and obj.spawned and 'Emitter saved and spawned' or obj and ('Emitter saved; runtime spawn failed: '..tostring(obj.spawn_error)) or 'Emitter creation failed'))
    end
    ImGui.SameLine();if ImGui.Button('PLACE AT PLAYER',160,30) then
        local obj,err=app.ambient_audio:create_emitter({resource_path=self.audio_selected_path~='' and self.audio_selected_path or nil,query=self.audio_query,name=self.audio_name,radius=self.audio_radius,emitter_metadata_name=self.audio_metadata,source='player',room_id=app.selected_room_id,premise_id=app.selected_premise_id})
        self:toast(err or (obj and obj.spawned and 'Emitter saved and spawned' or obj and ('Emitter saved; runtime spawn failed: '..tostring(obj.spawn_error)) or 'Emitter creation failed'))
    end
    ImGui.Separator();ImGui.Text('ROOM REVERB / AMBIENT ZONE')
    local room=app.model:get_room(app.selected_room_id)
    ImGui.TextDisabled(room and ('Selected room: '..room.name..' ('..room.size.width..' × '..room.size.depth..' × '..room.size.height..' m)') or 'Select a saved room in Premises Builder first.')
    self.reverb_name=select(1,ImGui.InputText('Zone name',self.reverb_name,128))
    self.reverb_bus=select(1,ImGui.InputText('Reverb bus CName',self.reverb_bus,128))
    self.reverb_sound_event=select(1,ImGui.InputText('Optional active sound event',self.reverb_sound_event,160))
    self.reverb_priority=select(1,ImGui.InputInt('Priority',self.reverb_priority))
    self.reverb_outer=select(1,ImGui.InputFloat('Outer distance',self.reverb_outer,0.5,2,'%.1f'))
    self.reverb_vertical=select(1,ImGui.InputFloat('Vertical outer distance',self.reverb_vertical,0.25,1,'%.1f'))
    if ImGui.Button('CREATE REVERB ZONE FROM ROOM',270,32) then
        local result,err=app.ambient_audio:create_reverb_zone({room_id=app.selected_room_id,name=self.reverb_name,reverb=self.reverb_bus,sound_event=self.reverb_sound_event,priority=self.reverb_priority,outer_distance=self.reverb_outer,vertical_outer_distance=self.reverb_vertical})
        self:toast(err or (result and ('Saved room zone with '..#result.outline..' outline points; export the complete World Builder group to activate it') or 'Could not create room zone'))
    end
    ImGui.Separator();ImGui.TextDisabled('Object transforms remain editable through the scene hierarchy/transform tools. Removing one or more outline points makes the zone incomplete; native export checks for all four saved points.')
end

function SpatialUI:draw()
    local premise=self.app.model:get_premise(self.app.selected_premise_id)
    if ImGui.BeginTabBar('##spatial_tabs') then
        if ImGui.BeginTabItem('Layers') then self:draw_layers();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Splines') then self:draw_splines();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Timeline') then self:draw_timeline();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Vanilla clone') then self:draw_vanilla_clone();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Volumes') then if premise then self:draw_volumes(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Cameras') then if premise then self:draw_cameras(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('NPC workspots') then if premise then self:draw_workspots(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('NPC population') then if premise then self:draw_population(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Patrol & AI routes') then self:draw_npc_routes(premise);ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Cover nodes') then if premise then self:draw_cover_nodes(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Combat encounters') then self:draw_combat_encounters(premise);ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Lighting') then self:draw_lighting();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('VFX') then self:draw_vfx();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Environment') then self:draw_environment();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Collision') then self:draw_collision();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Sectors') then self:draw_sectors();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Performance') then self:draw_performance();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Visibility') then self:draw_visibility();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Ambient Audio') then self:draw_ambient_audio();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Meshes + Decals') then self:draw_mesh_appearance();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Interactables') then self:draw_interactables();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Walkability') then self:draw_walkability();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Navigation') then self:draw_navigation();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Device Logic') then self:draw_device_logic(premise);ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Quest Forge Sync') then self:draw_questforge_sync();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Quest Debug') then self:draw_quest_debug();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('World States') then self:draw_world_states();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('In-world markers') then if premise then self:draw_markers(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        ImGui.EndTabBar()
    end
end

function SpatialUI:draw_quest_debug()
    local sim=self.app.quest_simulator
    ImGui.Text('QUEST SIMULATION / DEBUG');
    ImGui.TextWrapped('Reads live game facts and maps them to authored writers/readers. Writing a fact changes active quest state and can advance scripts. Every write is staged first and requires a separate confirmation.')
    if ImGui.Button('REFRESH QUEST STATE',180,32) or not self.questsim_catalog then self.questsim_catalog=sim:catalog() end
    if self.questsim_catalog and not self.questsim_catalog.game_api_available then ImGui.TextDisabled('Quest runtime is unavailable right now. Project links are listed, but live values cannot be read.') end
    self.questsim_filter=select(1,ImGui.InputText('Filter fact names',self.questsim_filter,128))
    local rows=(self.questsim_catalog or {}).facts or {}
    if ImGui.BeginChild('##quest_debug_fact_list',-1,230,true) then
        local shown=0
        for _,row in ipairs(rows) do
            if self.questsim_filter=='' or string.find(string.lower(row.name),string.lower(self.questsim_filter),1,true) then
                shown=shown+1;local current=row.value==nil and 'unread' or tostring(row.value)
                if ImGui.Selectable(row.name..' = '..current..'##qfact_'..row.name,self.questsim_fact==row.name) then self.questsim_fact=row.name;self.questsim_value=row.value or 1 end
                ImGui.SameLine();ImGui.TextDisabled(string.format('writes %d / reads %d',#row.writers,#row.consumers))
            end
        end
        if shown==0 then ImGui.TextDisabled('No linked facts match the filter. Type a fact name below to inspect it.') end
        ImGui.EndChild()
    end
    self.questsim_fact=select(1,ImGui.InputText('Quest fact',self.questsim_fact,128))
    self.questsim_value=select(1,ImGui.InputInt('Value to write',self.questsim_value))
    if ImGui.Button('PREPARE FACT WRITE',175,32) then local prepared,err=sim:prepare_write(self.questsim_fact,self.questsim_value,'in-game quest debug panel');self.questsim_pending=prepared;self:toast(err or 'Fact write staged; review the save warning before confirming') end
    ImGui.SameLine();if ImGui.Button('PREPARE RESET TO 0',175,32) then local prepared,err=sim:prepare_write(self.questsim_fact,0,'in-game quest debug reset');self.questsim_pending=prepared;self:toast(err or 'Reset staged; review the save warning before confirming') end

    local volumes=self.app.model.data.volumes or {};local selected_label='Select a linked trigger volume'
    for _,volume in ipairs(volumes) do if volume.id==self.questsim_trigger_id then selected_label=volume.name or volume.id end end
    if ImGui.BeginCombo('Trigger to simulate',selected_label) then for _,volume in ipairs(volumes) do
        local meta=volume.metadata or {};local has_fact=((meta.questforge or {}).fact_name~=nil) or #(((meta.questforge_sync or {}).facts) or {})>0
        if has_fact and ImGui.Selectable((volume.name or volume.id)..'##qtrigger_'..volume.id,self.questsim_trigger_id==volume.id) then self.questsim_trigger_id=volume.id end
    end;ImGui.EndCombo() end
    if ImGui.Button('PREPARE TRIGGER FACT',185,32) then local prepared,err=sim:prepare_trigger(self.questsim_trigger_id);self.questsim_pending=prepared;self:toast(err or 'Trigger fact staged; this writes the linked fact, not the native volume event') end
    ImGui.TextDisabled('Manual trigger test writes the linked fact with SetFactStr. It does not dispatch the volume collision/event itself.')

    if self.questsim_pending then
        ImGui.Separator();ImGui.Text('PENDING SAVE CHANGE');ImGui.TextWrapped('Fact: '..self.questsim_pending.fact_name..'   '..tostring(self.questsim_pending.current_value or 'unknown')..' → '..tostring(self.questsim_pending.new_value))
        ImGui.TextWrapped(self.questsim_pending.persistent_save_warning)
        if ImGui.Button('CONFIRM & CHANGE ACTIVE SAVE',260,36) then local result,err=sim:confirm_write(self.questsim_pending.token);self.questsim_pending=nil;self.questsim_catalog=sim:catalog();self:toast(err or (result and 'Fact changed. LocationStudio cannot undo game save facts.')) end
        ImGui.SameLine();if ImGui.Button('CANCEL; KEEP SAVE UNCHANGED',230,36) then sim:cancel_write(self.questsim_pending.token);self.questsim_pending=nil;self:toast('Pending fact change cancelled') end
    end

    local selected=sim:inspect(self.questsim_fact)
    if selected then
        ImGui.Separator();ImGui.Text('LINKS FOR '..(selected.name or self.questsim_fact))
        for _,entry in ipairs(selected.writers or {}) do ImGui.BulletText('Writes: '..tostring(entry.label)..' ['..tostring(entry.kind)..']') end
        for _,entry in ipairs(selected.consumers or {}) do ImGui.BulletText('Reads/conditions: '..tostring(entry.label)..' ['..tostring(entry.kind)..']') end
        for _,entry in ipairs(selected.references or {}) do ImGui.BulletText('Reference: '..tostring(entry.label)..' ['..tostring(entry.kind)..']') end
    end
end

function SpatialUI:draw_world_states()
    local states=self.app.world_states
    ImGui.Text('CONDITIONAL WORLD-STATE VARIANTS')
    ImGui.TextWrapped('Build fact-driven versions of this location: before/during/after a quest, destroyed, cleaned, or any custom state. Rules control which saved CET/World Builder object entities are spawned or despawned. Lights, NPCs, doors, decals, audio and effects can be included when represented by a placed object.')
    ImGui.TextDisabled('This is a live LocationStudio scene switch; it does not generate native REDengine quest/device state graphs. Auto-switching starts only after you enable it below.')
    self.world_variant_name=select(1,ImGui.InputText('Variant name',self.world_variant_name,96))
    self.world_variant_fact=select(1,ImGui.InputText('Fact condition',self.world_variant_fact,128))
    if ImGui.BeginCombo('Fact comparison',self.world_variant_operator) then for _,op in ipairs({'==','~=','>','>=','<','<='}) do if ImGui.Selectable(op,self.world_variant_operator==op) then self.world_variant_operator=op end end;ImGui.EndCombo() end
    self.world_variant_value=select(1,ImGui.InputInt('Fact value',self.world_variant_value))
    self.world_variant_priority=select(1,ImGui.InputInt('Priority (higher wins)',self.world_variant_priority))
    if ImGui.Button('CREATE FACT-DRIVEN VARIANT',245,34) then
        local variant,err=states:create({name=self.world_variant_name,fact_name=self.world_variant_fact,operator=self.world_variant_operator,value=self.world_variant_value,priority=self.world_variant_priority,premise_id=self.app.selected_premise_id})
        if variant then self.world_variant_id=variant.id end;self:toast(err or 'Variant created. Select an object and add it below.')
    end
    local variants=states:list();local selected_name='Select world-state variant'
    for _,variant in ipairs(variants) do if variant.id==self.world_variant_id then selected_name=variant.name end end
    if ImGui.BeginCombo('Editing variant',selected_name) then for _,variant in ipairs(variants) do if ImGui.Selectable(variant.name..'##wsv_'..variant.id,self.world_variant_id==variant.id) then self.world_variant_id=variant.id end end;ImGui.EndCombo() end
    local variant=self.world_variant_id~='' and self.app.model:get_world_state_variant(self.world_variant_id) or nil
    if variant then
        ImGui.Text(string.format('%d saved object rule(s), priority %d',#(variant.members or {}),variant.priority or 0))
        if ImGui.Button('ADD SELECTED OBJECT: SHOW',210,32) then local object=self.app.model:get_object(self.app.selected_object_id);local result,err;if object then result,err=states:add_member(variant.id,object.id,true) else err='Select a placed object first' end;self:toast(err or (result and ('Added '..object.name..' to '..variant.name) or 'Add failed')) end
        ImGui.SameLine();if ImGui.Button('ADD SELECTED OBJECT: HIDE',210,32) then local object=self.app.model:get_object(self.app.selected_object_id);local result,err;if object then result,err=states:add_member(variant.id,object.id,false) else err='Select a placed object first' end;self:toast(err or (result and ('Added hidden rule for '..object.name) or 'Add failed')) end
        for _,member in ipairs(variant.members or {}) do
            local object=self.app.model:get_object(member.item_id)
            ImGui.BulletText((object and object.name or member.item_id)..' · '..(member.visible and 'shown in this state' or 'hidden in this state'))
            ImGui.SameLine();if ImGui.SmallButton('REMOVE##wsvmember_'..member.item_id) then local _,err=states:remove_member(variant.id,member.item_id);self:toast(err or 'Removed object rule') end
        end
    end
    ImGui.Separator()
    local status=states:status();local changed;self.world_variant_auto,changed=ImGui.Checkbox('Auto-switch live objects when quest facts change',status.auto_enabled)
    if changed then local result,err=states:set_auto(self.world_variant_auto);self:toast(err or (self.world_variant_auto and 'Fact-driven live switching enabled' or 'Automatic switching paused')) end
    if ImGui.Button('PREVIEW CURRENT FACT STATE',220,32) then local plan,err=states:preview();self.world_state_preview=plan;self:toast(err or (plan and (plan.ready and 'World-state preview is ready' or 'Resolve same-priority conflicts before apply') or 'Could not read quest facts')) end
    ImGui.SameLine();if ImGui.Button('APPLY CURRENT FACT STATE',220,32) then local report,err=states:apply();self.world_state_preview=report;self:toast(err or (report and ('Applied world state; spawned '..report.spawned..', despawned '..report.despawned) or 'World-state apply failed')) end
    local preview=self.world_state_preview
    if preview then
        for _,active in ipairs(preview.active_variants or {}) do ImGui.BulletText('Active: '..active.name) end
        for fact,value in pairs(preview.facts or {}) do ImGui.TextDisabled(fact..' = '..tostring(value)) end
        for _,conflict in ipairs(preview.conflicts or {}) do ImGui.TextWrapped('CONFLICT: '..conflict.object_id..' has equal-priority rules from '..table.concat(conflict.variants,', ')) end
        for _,failure in ipairs(preview.failed or {}) do ImGui.TextWrapped('FAILED: '..failure.object_id..' — '..failure.error) end
        if preview.note then ImGui.TextWrapped(preview.note) end
    end
end

function SpatialUI:draw_questforge_sync()
    local app=self.app
    ImGui.Text('QUEST FORGE ROUND-TRIP');ImGui.TextWrapped('Import an edited LocationStudio Quest Forge handoff. Exact LocationStudio IDs link nodes. The default update imports quest links/facts only; saved names, notes and local transforms stay intact.')
    self.questforge_path=select(1,ImGui.InputText('Quest Forge JSON file (mod-relative)',self.questforge_path,256))
    local function read_document()
        local file,err=io.open(self.questforge_path,'r');if not file then return nil,'Cannot read '..self.questforge_path..': '..tostring(err) end
        local text=file:read('*a');file:close();local ok,value=pcall(json.decode,text or '')
        if not ok or type(value)~='table' then return nil,'File is not a valid Quest Forge JSON document' end
        return value
    end
    if ImGui.Button('PREVIEW IMPORT',150,32) then local document,err=read_document();if document then self.questforge_preview,err=app.questforge_sync:preview(document) end;self:toast(err or 'Quest Forge import preview ready') end
    ImGui.SameLine();local changed;self.questforge_apply_positions,changed=ImGui.Checkbox('Apply incoming positions (overwrites local transforms)',self.questforge_apply_positions)
    if self.questforge_preview then
        local counts=self.questforge_preview.counts or {}
        ImGui.Separator();ImGui.Text(string.format('Matched %d  •  unmatched %d  •  linked facts %d  •  position conflicts %d',counts.matched or 0,counts.unmatched or 0,counts.facts or 0,counts.position_conflicts or 0))
        if ImGui.Button('UPDATE LINKED ITEMS',190,34) then local document,err=read_document();if document then local result;result,err=app.questforge_sync:apply(document,{apply_positions=self.questforge_apply_positions});if result then self.questforge_preview=nil end end;self:toast(err or 'Updated Quest Forge links. Local notes and other fields were preserved.') end
        for _,row in ipairs(self.questforge_preview.rows or {}) do
            ImGui.BulletText(string.format('%s  [%s]  NodeRef: %s',row.name or row.id,row.kind,row.node_ref or 'unmapped'))
            for _,fact in ipairs(row.facts or {}) do ImGui.Indent();ImGui.TextDisabled('Fact: '..fact.name..' = '..tostring(fact.value)..' ('..fact.source..')');ImGui.Unindent() end
            if row.position_conflict then ImGui.Indent();ImGui.TextColored(1,0.65,0.25,1,'Quest Forge position differs from your local placement; preserved unless Apply incoming positions is checked.');ImGui.Unindent() end
        end
    end
end

return SpatialUI
