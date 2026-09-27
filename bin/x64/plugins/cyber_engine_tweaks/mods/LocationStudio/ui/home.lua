local Theme=require('ui/theme')

local Home={}
Home.__index=Home

local PRESETS={
    {name='SMALL',width=3.5,depth=3.5,height=3.0},
    {name='MEDIUM',width=5.0,depth=5.0,height=3.0},
    {name='LARGE',width=8.0,depth=6.0,height=3.5},
    {name='HALL',width=3.0,depth=8.0,height=3.0},
}

function Home.new(app,notify)
    local qs=app.model.data.settings.quickstart or {}
    return setmetatable({
        app=app,notify=notify,location_name='My Location',room_name='',preset='MEDIUM',
        width=qs.width or 5,depth=qs.depth or 5,height=qs.height or 3,
        auto_door=qs.auto_door~=false,door_width=qs.door_width or 1.2,
    },Home)
end

function Home:toast(message) if self.notify then self.notify(message) end end

function Home:save_defaults()
    local qs=self.app.model.data.settings.quickstart
    qs.width=self.width;qs.depth=self.depth;qs.height=self.height;qs.auto_door=self.auto_door;qs.door_width=self.door_width
    self.app:mark_dirty()
end

function Home:set_preset(name)
    for _,preset in ipairs(PRESETS) do if preset.name==name then
        self.preset=name;self.width=preset.width;self.depth=preset.depth;self.height=preset.height;self:save_defaults();return
    end end
end

function Home:draw_runtime_banner()
    local shell=self.app.runtime_shell and self.app.runtime_shell:status(false) or {available=false,reason='Room runtime unavailable'}
    local entity=self.app.placement:status().supported
    if shell.available and entity then
        Theme.good('ADAPTERS AVAILABLE');ImGui.SameLine();Theme.muted('Entity loading is checked after each spawn request.')
    else
        Theme.bad('RUNTIME NOT READY')
        if not shell.available then ImGui.TextWrapped(tostring(shell.reason or 'Room runtime backend unavailable.')) end
        if not entity then ImGui.TextWrapped('CET entity spawner is unavailable.') end
        ImGui.TextDisabled('Room creation checks dependencies before adding any room data.')
    end
    if Theme.action_button('SPAWN TEST CHAIR',160,28) then
        local r,e=self.app.placement:spawn_test_asset('builtin_chair_poor')
        self:toast(r and 'Test chair requested. Watch the status below for confirmation.' or ('Spawn check failed: '..tostring(e)))
    end
    ImGui.SameLine();if Theme.action_button('REMOVE TEST CHAIR',170,28) then
        local removed,err=self.app.placement:clear_test_asset();self:toast(removed and 'Test chair removal requested.' or tostring(err))
    end
    local state,reason=self.app.placement.entities:state('transient:runtime_self_test')
    if state~='idle' then Theme.info('CHAIR CHECK: '..string.upper(state));if reason then ImGui.TextWrapped(reason) end end
    Theme.muted('Rooms use real game meshes through World Builder. Hidden collision is generated separately.')
    ImGui.Separator()
end

local function path_name(path)
    path=tostring(path or ''):gsub('\\','/')
    return path:match('([^/]+)$') or path
end

function Home:draw_room_kit(room,premise)
    local app=self.app;local kit=app.builder:room_kit();local preset_name=kit.preset
    for _,preset in ipairs(app.builder:room_kit_presets()) do if preset.id==kit.preset then preset_name=preset.name end end
    Theme.kicker('ROOM MATERIAL KIT')
    if ImGui.BeginCombo('Architecture kit',preset_name) then
        for _,preset in ipairs(app.builder:room_kit_presets()) do
            if ImGui.Selectable(preset.name,kit.preset==preset.id) then
                local value,err=app.builder:set_room_kit_preset(preset.id);kit=value or kit;self:toast(value and ('Selected '..preset.name..'. Rebuild to apply it.') or err)
            end
        end
        ImGui.EndCombo()
    end
    local changed;kit.collision,changed=ImGui.Checkbox('Generate invisible player collision',kit.collision);if changed then app:mark_dirty() end
    Theme.good('REAL GAME ASSETS')
    for _,role in ipairs({'floor','wall','ceiling','door','window'}) do
        ImGui.TextDisabled(string.upper(role)..': '..path_name((kit.roles[role] or {}).path))
    end
    local selected=app.model:get_asset(app.selected_asset_id or app.last_asset_id)
    if selected then Theme.muted('Selected asset: '..selected.name) else Theme.muted('Select a Static Mesh in ASSETS to replace any kit part.') end
    for index,role in ipairs({'wall','floor','ceiling','door','window'}) do
        if index>1 then ImGui.SameLine() end
        if Theme.action_button('SET '..string.upper(role),92,26) then
            local value,err=app.builder:assign_room_kit_role(role,app.selected_asset_id or app.last_asset_id)
            self:toast(value and ('Assigned '..tostring(value.asset_name or path_name(value.path))..' as '..role..'.') or tostring(err))
        end
    end
    if room then
        if Theme.primary_button('REBUILD SELECTED ROOM',215,34) then
            local result,err=app.builder:rebuild_room_shell(room.id)
            if result then local runtime,warn=app.placement:spawn_room_shell(room.id);self:toast(runtime and (warn or ('Rebuilt with '..result.object_count..' editable game-asset pieces.')) or tostring(warn)) else self:toast(tostring(err)) end
        end
        ImGui.SameLine()
    end
    if premise and Theme.action_button('REBUILD ALL ROOMS',190,34) then
        local result,err=app.builder:rebuild_premise_shells(premise.id)
        if result then local runtime,warn=app.placement:spawn_all_shells(premise.id);self:toast(runtime and (warn or ('Rebuilt '..result.rooms..' rooms / '..result.objects..' pieces.')) or tostring(warn)) else self:toast(tostring(err)) end
    end
    ImGui.Separator()
end

function Home:draw_room_size()
    Theme.kicker('ROOM SIZE')
    for i,preset in ipairs(PRESETS) do
        if i>1 then ImGui.SameLine() end
        local selected=self.preset==preset.name
        if Theme.nav_button(preset.name,selected,105,28) then self:set_preset(preset.name) end
    end
    local changed
    self.width,changed=ImGui.InputFloat('Width (m)',self.width,0.25,1,'%.2f');if changed then self.preset='CUSTOM';self:save_defaults() end
    self.depth,changed=ImGui.InputFloat('Depth (m)',self.depth,0.25,1,'%.2f');if changed then self.preset='CUSTOM';self:save_defaults() end
    self.height,changed=ImGui.InputFloat('Height (m)',self.height,0.25,1,'%.2f');if changed then self.preset='CUSTOM';self:save_defaults() end
end

function Home:draw_empty_project()
    local app=self.app
    Theme.kicker('NEW LOCATION')
    ImGui.TextWrapped('Stand where the first room should be. Choose a size and create it. Location Studio handles the project container and visible room shell for you.')
    ImGui.Spacing()
    self.location_name=select(1,ImGui.InputText('Location name',self.location_name,128))
    self.room_name=select(1,ImGui.InputText('Room name (optional)',self.room_name,128))
    ImGui.Spacing();self:draw_room_kit(nil,nil);self:draw_room_size();ImGui.Spacing()
    if Theme.primary_button('CREATE ROOM HERE',230,42) then
        local result,err=app.quickstart:create_first_room({location_name=self.location_name,name=self.room_name~='' and self.room_name or nil,width=self.width,depth=self.depth,height=self.height})
        self:toast(result and (err or ('Created '..result.room.name..'; room geometry submitted to the runtime adapter.')) or tostring(err))
    end
end

local function count_rooms(app,premise_id)
    local n=0;for _,r in ipairs(app.model.data.rooms or {}) do if r.premise_id==premise_id then n=n+1 end end;return n
end

function Home:add_adjacent(direction)
    local app=self.app
    local result,err=app.quickstart:add_adjacent_room({direction=direction,name=self.room_name~='' and self.room_name or nil,width=self.width,depth=self.depth,height=self.height,auto_door=self.auto_door,door_width=self.door_width})
    self:toast(result and ('Added '..result.room.name..' '..direction) or tostring(err))
end

function Home:draw_extend_controls(room)
    Theme.kicker('EXTEND SELECTED ROOM')
    if not room then
        Theme.warning('Select a room in SCENE first.');return
    end
    Theme.muted(room.name..'  /  add a connected room')
    ImGui.Spacing()
    ImGui.TextDisabled('                         ');ImGui.SameLine();if Theme.action_button('NORTH',112,34) then self:add_adjacent('north') end
    if Theme.action_button('WEST',112,34) then self:add_adjacent('west') end
    ImGui.SameLine();Theme.muted('   +   ');ImGui.SameLine();if Theme.action_button('EAST',112,34) then self:add_adjacent('east') end
    ImGui.TextDisabled('                         ');ImGui.SameLine();if Theme.action_button('SOUTH',112,34) then self:add_adjacent('south') end
end

function Home:draw_active_project(premise)
    local app=self.app;local room=app.model:get_room(app.selected_room_id);local count=count_rooms(app,premise.id)
    Theme.kicker('CURRENT LOCATION')
    Theme.accent(premise.name);ImGui.SameLine();Theme.muted(string.format(' / %d room%s',count,count==1 and '' or 's'))
    local status=app.placement:status()
    if count>0 and (status.shell_spawned or 0)==0 then
        ImGui.SameLine();Theme.warning('NOT VISIBLE')
        ImGui.Spacing()
        if Theme.primary_button('SHOW LOCATION IN GAME',210,34) then
            local r,e=app.placement:spawn_all_shells(premise.id)
            self:toast(r and (e or string.format('Submitted %d shell pieces. Check the result in game.',r.spawned or 0)) or tostring(e))
        end
    end
    ImGui.Spacing();ImGui.Separator();ImGui.Spacing();self:draw_room_kit(room,premise)

    self.room_name=select(1,ImGui.InputText('Next room name (optional)',self.room_name,128))
    self:draw_room_size()
    local changed;self.auto_door,changed=ImGui.Checkbox('Create doorway when rooms connect',self.auto_door);if changed then self:save_defaults() end
    if self.auto_door then ImGui.SameLine();self.door_width,changed=ImGui.InputFloat('Door width',self.door_width,0.1,0.5,'%.2f');if changed then self:save_defaults() end end

    ImGui.Spacing();if Theme.primary_button('CREATE ROOM AT MY POSITION',255,40) then
        local result,err=app.quickstart:create_room_here({name=self.room_name~='' and self.room_name or nil,width=self.width,depth=self.depth,height=self.height})
        self:toast(result and (err or ('Created '..result.room.name..'; room geometry submitted to the runtime adapter.')) or tostring(err))
    end

    ImGui.Spacing();ImGui.Separator();ImGui.Spacing();self:draw_extend_controls(room)
end

function Home:draw()
    local app=self.app
    Theme.section('BUILD','rooms first — no technical setup')
    self:draw_runtime_banner()
    local premise=app.model:get_premise(app.selected_premise_id)
    if not premise and #(app.model.data.premises or {})>0 then premise=app.model.data.premises[1];app.selection:set('premise',premise.id) end
    if not premise then self:draw_empty_project() else self:draw_active_project(premise) end
end

return Home
