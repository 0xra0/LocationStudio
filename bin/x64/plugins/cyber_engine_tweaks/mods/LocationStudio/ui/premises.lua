local PremisesUI={}
local Widgets=require('ui/widgets')
PremisesUI.__index=PremisesUI

function PremisesUI.new(app,notify)
    return setmetatable({
        app=app,notify=notify,
        premise_name='New Premise',premise_kind='interior',
        room_name='New Room',room_width=6,room_depth=5,room_height=3,room_x=0,room_y=0,room_z=0,
        opening_kind='door',opening_wall='south',opening_offset=0,opening_width=1.2,opening_height=2.2,opening_sill=0,
        object_name='New Object',object_kind='prop',object_template='',object_appearance='',object_layer='decoration',
        object_x=0,object_y=0,object_z=0,object_yaw=0,
    },PremisesUI)
end

function PremisesUI:toast(message) if self.notify then self.notify(message) end end

local function selected_label(value,id) return tostring(value or 'Untitled')..'##'..tostring(id) end

local function short_path(path)
    path=tostring(path or ''):gsub('\\','/')
    return path:match('([^/]+)$') or path
end

function PremisesUI:draw_room_kit_editor(premise)
    local app=self.app;local kit=app.builder:room_kit();local label=kit.preset
    for _,preset in ipairs(app.builder:room_kit_presets()) do if preset.id==kit.preset then label=preset.name end end
    ImGui.Text('GAME-ASSET ROOM KIT')
    ImGui.TextWrapped('Every surface below is a real editable World Builder mesh. Changing a kit never alters existing rooms until you press Rebuild.')
    if ImGui.BeginCombo('Room kit preset',label) then
        for _,preset in ipairs(app.builder:room_kit_presets()) do
            if ImGui.Selectable(preset.name,kit.preset==preset.id) then local value,err=app.builder:set_room_kit_preset(preset.id);kit=value or kit;self:toast(value and ('Selected '..preset.name) or err) end
        end
        ImGui.EndCombo()
    end
    local changed;kit.collision,changed=ImGui.Checkbox('Create invisible collision boxes',kit.collision);if changed then app:mark_dirty() end
    kit.floor_thickness,changed=ImGui.InputFloat('Floor collision thickness',kit.floor_thickness,0.02,0.1,'%.2f');if changed then kit.floor_thickness=math.max(0.02,kit.floor_thickness);app:mark_dirty() end
    kit.wall_thickness,changed=ImGui.InputFloat('Wall collision thickness',kit.wall_thickness,0.02,0.1,'%.2f');if changed then kit.wall_thickness=math.max(0.02,kit.wall_thickness);app:mark_dirty() end

    local selected=app.model:get_asset(app.selected_asset_id or app.last_asset_id)
    ImGui.TextDisabled(selected and ('Selected project asset: '..selected.name) or 'Select an imported Static Mesh in ASSETS to assign it here.')
    for _,role_name in ipairs({'floor','wall','ceiling','door','window'}) do
        local role=kit.roles[role_name]
        ImGui.Separator();ImGui.Text(string.upper(role_name)..'  /  '..short_path(role.path))
        local path;path,changed=ImGui.InputText('Mesh path##kit_'..role_name,role.path or '',512)
        if changed then app.builder:update_room_kit_role(role_name,{path=path});role=kit.roles[role_name] end
        local x,y,z=role.native_x,role.native_y,role.native_z
        x,changed=ImGui.InputFloat('Native length X##kit_'..role_name,x,0.1,1,'%.2f');if changed then app.builder:update_room_kit_role(role_name,{native_x=x}) end
        ImGui.SameLine();y,changed=ImGui.InputFloat('Native width Y##kit_'..role_name,y,0.1,1,'%.2f');if changed then app.builder:update_room_kit_role(role_name,{native_y=y}) end
        ImGui.SameLine();z,changed=ImGui.InputFloat('Native height Z##kit_'..role_name,z,0.1,1,'%.2f');if changed then app.builder:update_room_kit_role(role_name,{native_z=z}) end
        local offset={role.offset_x,role.offset_y,role.offset_z};offset,changed=Widgets.input3('Pivot offset XYZ##kit_'..role_name,offset,'%.3f')
        if changed then app.builder:update_room_kit_role(role_name,{offset_x=offset[1],offset_y=offset[2],offset_z=offset[3]}) end
        local role_yaw;role_yaw,changed=ImGui.InputFloat('Rotation correction##kit_'..role_name,role.yaw,5,45,'%.1f');if changed then app.builder:update_room_kit_role(role_name,{yaw=role_yaw}) end
        if ImGui.Button('USE SELECTED AS '..string.upper(role_name)..'##kit_assign_'..role_name) then
            local value,err=app.builder:assign_room_kit_role(role_name,app.selected_asset_id or app.last_asset_id);self:toast(value and ('Assigned '..tostring(value.asset_name or short_path(value.path))) or tostring(err))
        end
    end
    ImGui.Separator()
    if ImGui.Button('REBUILD ALL WITH THIS KIT',230,32) then
        local result,err=app.builder:rebuild_premise_shells(premise.id)
        if result then local runtime,warn=app.placement:spawn_all_shells(premise.id);self:toast(runtime and (warn or ('Rebuilt '..result.rooms..' rooms / '..result.objects..' pieces')) or tostring(warn)) else self:toast(tostring(err)) end
    end
end

function PremisesUI:draw_premise_bar()
    local app=self.app
    self.premise_name=select(1,ImGui.InputText('Premise name',self.premise_name,128))
    self.premise_kind=select(1,ImGui.InputText('Kind',self.premise_kind,64))
    if ImGui.Button('CREATE AT PLAYER',170,32) then
        local item,err=app.actions:create_premise_from_player(self.premise_name,self.premise_kind)
        if item then self:toast('Created premise '..item.name) else self:toast(err or 'Player unavailable') end
    end
    ImGui.SameLine()
    if ImGui.Button('CLINIC PREFAB') and app.selected_premise_id then local result,err=app.quickstart:create_prefab_here('clinic',{});self:toast(result and (err or 'Clinic built and spawned') or err) end
    ImGui.SameLine()
    if ImGui.Button('APARTMENT PREFAB') and app.selected_premise_id then local result,err=app.quickstart:create_prefab_here('apartment',{});self:toast(result and (err or 'Apartment built and spawned') or err) end
    ImGui.SameLine()
    if ImGui.Button('WAREHOUSE PREFAB') and app.selected_premise_id then local result,err=app.quickstart:create_prefab_here('warehouse',{});self:toast(result and (err or 'Warehouse built and spawned') or err) end
    ImGui.Separator()
    ImGui.BeginChild('##premise_list',220,0,true)
    ImGui.Text('PREMISES')
    for _,premise in ipairs(app.model.data.premises) do
        if ImGui.Selectable(selected_label(premise.name,premise.id),app.selected_premise_id==premise.id) then
            app.selection:set('premise',premise.id)
        end
    end
    ImGui.EndChild()
end

function PremisesUI:draw_room_builder(premise)
    local app=self.app
    ImGui.Text('ROOM BUILDER')
    self.room_name=select(1,ImGui.InputText('Room name',self.room_name,128))
    self.room_width=select(1,ImGui.InputFloat('Width',self.room_width,0.25,1,'%.2f'))
    self.room_depth=select(1,ImGui.InputFloat('Depth',self.room_depth,0.25,1,'%.2f'))
    self.room_height=select(1,ImGui.InputFloat('Height',self.room_height,0.25,1,'%.2f'))
    local room_pos={self.room_x,self.room_y,self.room_z}; room_pos=select(1,Widgets.input3('Local XYZ',room_pos,'%.2f')); self.room_x,self.room_y,self.room_z=room_pos[1],room_pos[2],room_pos[3]
    if ImGui.Button('BUILD ROOM',145,30) then
        local room,err=app.actions:create_room({premise_id=premise.id,name=self.room_name,width=self.room_width,depth=self.room_depth,height=self.room_height,x=self.room_x,y=self.room_y,z=self.room_z})
        if room then app.selection:set('room',room.id); self:toast(err or ('Built and spawned '..room.name)) else self:toast(err) end
    end
    ImGui.SameLine()
    if ImGui.Button('BUILD CORRIDOR',150,30) then
        local room,err=app.actions:create_room({premise_id=premise.id,name=self.room_name,kind='corridor',width=self.room_width,depth=self.room_depth,height=self.room_height,x=self.room_x,y=self.room_y,z=self.room_z})
        if room then app.selection:set('room',room.id); self:toast(err or 'Built and spawned corridor') else self:toast(err) end
    end
    ImGui.Separator()
    ImGui.Text('ROOMS')
    for _,room in ipairs(app.model.data.rooms) do if room.premise_id==premise.id then
        if ImGui.Selectable(selected_label(room.name,room.id),app.selection:is('room',room.id)) then app.selection:set('room',room.id) end
    end end
end

function PremisesUI:draw_openings(room)
    local app=self.app
    ImGui.Text('ROOM GEOMETRY')
    local dimensions={room.size.width,room.size.depth,room.size.height}
    local changed
    dimensions,changed=Widgets.input3('Width / depth / height',dimensions,'%.2f')
    if changed then room.size.width=math.max(0.1,dimensions[1]);room.size.depth=math.max(0.1,dimensions[2]);room.size.height=math.max(0.1,dimensions[3]);app:mark_dirty() end
    local position={room.transform.position.x,room.transform.position.y,room.transform.position.z}
    position,changed=Widgets.input3('Room world XYZ',position,'%.3f')
    if changed then room.transform.position.x=position[1];room.transform.position.y=position[2];room.transform.position.z=position[3];app:mark_dirty() end
    local yaw; yaw,changed=ImGui.InputFloat('Room yaw',room.transform.rotation.yaw,5,45,'%.1f')
    if changed then room.transform.rotation.yaw=yaw;app:mark_dirty() end
    ImGui.Separator()
    ImGui.Text('DOORS + WINDOWS')
    if ImGui.BeginCombo('Opening type',self.opening_kind) then
        if ImGui.Selectable('door',self.opening_kind=='door') then self.opening_kind='door';self.opening_sill=0 end
        if ImGui.Selectable('window',self.opening_kind=='window') then self.opening_kind='window';self.opening_sill=0.9 end
        ImGui.EndCombo()
    end
    if ImGui.BeginCombo('Wall',self.opening_wall) then for _,wall in ipairs({'north','south','east','west'}) do if ImGui.Selectable(wall,self.opening_wall==wall) then self.opening_wall=wall end end; ImGui.EndCombo() end
    self.opening_offset=select(1,ImGui.InputFloat('Wall offset',self.opening_offset,0.1,0.5,'%.2f'))
    self.opening_width=select(1,ImGui.InputFloat('Opening width',self.opening_width,0.1,0.5,'%.2f'))
    self.opening_height=select(1,ImGui.InputFloat('Opening height',self.opening_height,0.1,0.5,'%.2f'))
    self.opening_sill=select(1,ImGui.InputFloat('Sill height',self.opening_sill,0.1,0.5,'%.2f'))
    if ImGui.Button('CUT OPENING',140,30) then
        local result,err=app.builder:add_opening({room_id=room.id,kind=self.opening_kind,wall=self.opening_wall,offset=self.opening_offset,width=self.opening_width,height=self.opening_height,sill=self.opening_sill})
        if result and app.model.data.settings.workspace.live_preview then local runtime,runtime_err=app.placement:spawn_room_shell(room.id);self:toast(runtime and (runtime_err or 'Opening added and shell refreshed') or runtime_err) else self:toast(err or 'Opening added; shell rebuilt') end
    end
    ImGui.SameLine()
    if ImGui.Button('REBUILD SHELL',145,30) then local result,err=app.builder:rebuild_room_shell(room.id);if result and app.model.data.settings.workspace.live_preview then local runtime,runtime_err=app.placement:spawn_room_shell(room.id);self:toast(runtime and (runtime_err or ('Rebuilt and spawned '..tostring(result.object_count)..' shell objects')) or runtime_err) else self:toast(err or ('Rebuilt '..tostring(result and result.object_count or 0)..' shell objects')) end end
    ImGui.SameLine()
    if ImGui.Button('DELETE ROOM') then app.selection:set('room',room.id);local ok,err=app.actions:delete_selected();self:toast(ok and 'Room deleted' or err) end
    for _,opening in ipairs(room.openings or {}) do ImGui.BulletText(string.format('%s / %s / offset %.2f / %.2fx%.2f',opening.kind,opening.wall,opening.offset,opening.width,opening.height)) end
end

function PremisesUI:draw_object_builder(premise)
    local app=self.app
    ImGui.Text('OBJECT PLACEMENT')
    self.object_name=select(1,ImGui.InputText('Object name',self.object_name,128))
    self.object_kind=select(1,ImGui.InputText('Object kind',self.object_kind,64))
    self.object_template=select(1,ImGui.InputText('Entity .ent template',self.object_template,512))
    self.object_appearance=select(1,ImGui.InputText('Appearance',self.object_appearance,128))
    self.object_layer=select(1,ImGui.InputText('Layer',self.object_layer,64))
    local pos={self.object_x,self.object_y,self.object_z}; pos=select(1,Widgets.input3('Object local XYZ',pos,'%.3f')); self.object_x,self.object_y,self.object_z=pos[1],pos[2],pos[3]
    self.object_yaw=select(1,ImGui.InputFloat('Object local yaw',self.object_yaw,5,45,'%.1f'))
    if ImGui.Button('ADD OBJECT',130,30) then
        local obj,err=app.builder:place_object({premise_id=premise.id,room_id=app.selected_room_id,name=self.object_name,kind=self.object_kind,template=self.object_template,appearance=self.object_appearance,layer=self.object_layer,x=self.object_x,y=self.object_y,z=self.object_z,yaw=self.object_yaw,source='ui'})
        if obj then app.selection:set('object',obj.id); self:toast('Object added') else self:toast(err) end
    end
    ImGui.SameLine()
    if ImGui.Button('ADD + SPAWN',140,30) then
        local obj,err=app.builder:place_object({premise_id=premise.id,room_id=app.selected_room_id,name=self.object_name,kind=self.object_kind,template=self.object_template,appearance=self.object_appearance,layer=self.object_layer,x=self.object_x,y=self.object_y,z=self.object_z,yaw=self.object_yaw,source='ui'})
        if obj then app.selection:set('object',obj.id); local _,spawn_err=app.placement:spawn(obj); self:toast(spawn_err or 'Object spawned') else self:toast(err) end
    end
    ImGui.SameLine()
    if ImGui.Button('ADD AT AIM',130,30) then
        local result,err=app.authoring:place_object_at_aim({premise_id=premise.id,room_id=app.selected_room_id,name=self.object_name,kind=self.object_kind,template=self.object_template,appearance=self.object_appearance,layer=self.object_layer,distance=10,yaw=self.object_yaw,spawn=false,source='ui:aim'})
        if result then app.selection:set('object',result.object.id);self:toast(result.spawn_error or ('Placed via '..result.placement_source)) else self:toast(err) end
    end
    ImGui.Separator()
    ImGui.Text('OBJECTS')
    ImGui.BeginChild('##object_list',0,145,true)
    for _,object in ipairs(app.model.data.objects) do if object.premise_id==premise.id then
        local marker=object.runtime and object.runtime.spawned and ' [live]' or ''
        if ImGui.Selectable(selected_label(object.name..marker,object.id),app.selection:is('object',object.id)) then app.selection:set('object',object.id) end
    end end
    ImGui.EndChild()
    local object=app.model:get_object(app.selected_object_id)
    if object then
        local p={object.transform.position.x,object.transform.position.y,object.transform.position.z}; local changed
        p,changed=Widgets.input3('Selected world XYZ',p,'%.3f')
        if changed then object.transform.position.x=p[1];object.transform.position.y=p[2];object.transform.position.z=p[3];app:mark_dirty() end
        local yaw;yaw,changed=ImGui.InputFloat('Selected yaw',object.transform.rotation.yaw,5,45,'%.1f')
        if changed then object.transform.rotation.yaw=yaw;app:mark_dirty() end
        if ImGui.Button('SPAWN / REFRESH') then local _,err=app.placement:refresh(object);self:toast(err or 'Object live') end
        ImGui.SameLine();if ImGui.Button('DESPAWN') then local _,err=app.placement:despawn(object);self:toast(err or 'Object despawned') end
        ImGui.SameLine();if ImGui.Button('DUPLICATE') then local copy=app.model:duplicate_object(object.id);if copy then app.selection:set('object',copy.id);app:mark_dirty();self:toast('Object duplicated') end end
        ImGui.SameLine();if ImGui.Button('DELETE OBJECT') then app.selection:set('object',object.id);local ok,err=app.actions:delete_selected();self:toast(ok and 'Object deleted' or err) end
        ImGui.TextDisabled(string.format('%s | %s | %s',object.kind,object.layer,object.template~='' and object.template or 'no template'))
    end
end

function PremisesUI:draw()
    local app=self.app
    ImGui.TextWrapped('Build premises from real Cyberpunk architecture meshes, editable World Builder objects, door/window modules, and separate invisible collision.')
    ImGui.Separator()
    self:draw_premise_bar()
    ImGui.SameLine()
    ImGui.BeginChild('##premise_workspace',0,0,true)
    local premise=app.model:get_premise(app.selected_premise_id)
    if not premise then ImGui.TextDisabled('Create or select a premise to begin construction.')
    elseif ImGui.BeginTabBar('##premise_tabs') then
        if ImGui.BeginTabItem('Rooms') then self:draw_room_builder(premise);ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Openings') then local room=app.model:get_room(app.selected_room_id);if room then self:draw_openings(room) else ImGui.TextDisabled('Select a room first.') end;ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Objects') then self:draw_object_builder(premise);ImGui.EndTabItem() end
        if ImGui.BeginTabItem('Build') then
            ImGui.Text(string.format('%d rooms / %d construction objects',#app.model.data.rooms,#app.model.data.objects))
            self:draw_room_kit_editor(premise)
            if ImGui.Button('SPAWN PREMISE',160,32) then local result=app.placement:spawn_premise(premise.id);self:toast(string.format('Spawned %d; failed %d',#result.spawned,#result.failed)) end
            ImGui.SameLine();if ImGui.Button('DESPAWN ALL',150,32) then app.placement:despawn_all();self:toast('All preview entities removed') end
            ImGui.SameLine();if ImGui.Button('EXPORT WB HANDOFF',190,32) then local ok,path=app:export('worldbuilder');self:toast(ok and ('Exported '..path) or path) end
            ImGui.Separator();ImGui.Text('LAYERS')
            for _,layer in ipairs(app.model.data.layers) do
                local visible;visible,changed=ImGui.Checkbox(layer.name..' visible##'..layer.id,layer.visible)
                if changed then layer.visible=visible;app:mark_dirty() end
                ImGui.SameLine(180)
                local locked;locked,changed=ImGui.Checkbox('locked##'..layer.id,layer.locked)
                if changed then layer.locked=locked;app:mark_dirty() end
            end
            ImGui.Separator();ImGui.TextWrapped('Room kit paths must be Static Mesh resources. Native dimensions control tiling and edge scaling. Pivot offsets and rotation correction let non-standard game meshes align cleanly.')
        ImGui.EndTabItem() end
        ImGui.EndTabBar()
    end
    ImGui.EndChild()
end

return PremisesUI
