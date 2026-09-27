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
        if ImGui.BeginTabItem('Volumes') then if premise then self:draw_volumes(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Cameras') then if premise then self:draw_cameras(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('NPC workspots') then if premise then self:draw_workspots(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('NPC population') then if premise then self:draw_population(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Patrol & AI routes') then self:draw_npc_routes(premise);ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Cover nodes') then if premise then self:draw_cover_nodes(premise) else ImGui.TextDisabled('Select a premise in Premises Builder first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Combat encounters') then self:draw_combat_encounters(premise);ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Lighting') then self:draw_lighting();ImGui.EndTabItem() end
        if ImGui.BeginTabItem('VFX') then self:draw_vfx();ImGui.EndTabItem() end
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
