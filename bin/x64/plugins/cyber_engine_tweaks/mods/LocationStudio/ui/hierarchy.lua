local Util=require('modules/util')
local Theme=require('ui/theme')

local Hierarchy={}
Hierarchy.__index=Hierarchy

function Hierarchy.new(app,notify) return setmetatable({app=app,notify=notify,search='',show={scenes=true,rooms=true,construction=true,groups=true,prefabs=true,objects=true,gameplay=true},group_open={},group_names={}},Hierarchy) end

local function matches(item,search)
    if search=='' then return true end
    return Util.contains_ci((item.name or '')..' '..(item.kind or item.type or item.purpose or ''),search)
end

function Hierarchy:item(kind,item,prefix)
    if not matches(item,self.search) then return end
    local selected=self.app.selection:is(kind,item.id)
    local label=(prefix or '')..(item.name or item.id)..'##tree_'..kind..'_'..item.id
    if ImGui.Selectable(label,selected) then
        self.app.selection:set(kind,item.id)
        if kind=='object' and self.app.runtime_shell and self.app.placement:is_tracked(item) then self.app.runtime_shell:focus(item) end
    end
    if type(ImGui.IsItemHovered)=='function' and ImGui.IsItemHovered() and type(ImGui.SetTooltip)=='function' then ImGui.SetTooltip(string.upper(kind)..'\n'..tostring(item.id)) end
end

function Hierarchy:focus_object_group()
    local objects=self.app.selection:selected_objects()
    if self.app.runtime_shell then
        self.app.runtime_shell:clear_focus()
        if #objects>0 then self.app.runtime_shell:focus_many(objects,self.app.selection.id) end
    end
end

function Hierarchy:object_item(item,prefix)
    local member=self.app.selection:contains_object(item.id)
    if ImGui.SmallButton((member and '[x]' or '[ ]')..'##multi_'..item.id) then
        local values,err=self.app.selection:toggle_object(item.id)
        if values then self:focus_object_group() end
        if err then self.notify(err) end
    end
    ImGui.SameLine();self:item('object',item,prefix)
end

function Hierarchy:selection_toolbar(objects,key)
    local count=self.app.selection:object_count();Theme.muted(tostring(count)..' selected')
    if ImGui.SmallButton('SELECT SHOWN##select_shown_'..key) then
        local ids={};for _,object in ipairs(objects) do table.insert(ids,object.id) end
        local values,err=self.app.selection:set_object_group(ids,ids[#ids],'locationstudio')
        if values then self:focus_object_group();self.notify('Selected '..#values..' object(s)') else self.notify(err) end
    end
    ImGui.SameLine();if ImGui.SmallButton('CLEAR SET##clear_set_'..key) then self.app.selection:clear_object_group();if self.app.runtime_shell then self.app.runtime_shell:clear_focus() end end
end

function Hierarchy:assembly_toolbar()
    local app=self.app;local ws=app.model.data.settings.workspace;local count=app.selection:object_count()
    local mode=ws.multi_pivot_mode or 'center';local custom=mode=='custom' and {position=ws.multi_custom_pivot,rotation={yaw=0}} or nil
    ws.group_name=select(1,ImGui.InputTextWithHint('##new_group_name','Group name',ws.group_name or 'New Group',96))
    if ImGui.SmallButton('CREATE GROUP##scene_group_create') then
        local ids={};for _,object in ipairs(app.selection:selected_objects()) do table.insert(ids,object.id) end
        local group,err=app.assemblies:create_group({name=ws.group_name,ids=ids,active_id=app.selection.id,pivot_mode=mode,pivot=custom})
        self.notify(err or (group and ('Created group '..group.name) or 'Create group failed'))
    end
    ImGui.SameLine();Theme.muted(tostring(count)..' selected')
    ws.prefab_name=select(1,ImGui.InputTextWithHint('##new_prefab_name','Reusable prefab name',ws.prefab_name or 'New Prefab',96))
    if ImGui.SmallButton('SAVE PREFAB##scene_prefab_save') then
        local ids={};for _,object in ipairs(app.selection:selected_objects()) do table.insert(ids,object.id) end
        local prefab,err=app.assemblies:save_prefab({name=ws.prefab_name,ids=ids,active_id=app.selection.id,pivot_mode=mode,pivot=custom})
        self.notify(err or (prefab and ('Saved reusable prefab '..prefab.name) or 'Save prefab failed'))
    end
    if count==0 then Theme.muted('Select placed objects first. Prefabs contain real entity/mesh resources and editable transforms.') end
end

function Hierarchy:draw_group_node(group,children,object_by_id,depth)
    local app=self.app;local direct={}
    for _,id in ipairs(group.object_ids or {}) do if object_by_id[id] then table.insert(direct,object_by_id[id]) end end
    local nested=children[group.id] or {};local open=self.group_open[group.id]~=false;local indent=string.rep('  ',depth or 0)
    if ImGui.SmallButton((open and 'v' or '>')..'##group_open_'..group.id) then self.group_open[group.id]=not open;open=not open end
    ImGui.SameLine()
    local result=app.assemblies:objects_for_group(group.id,true);local count=result and #result or #direct
    if ImGui.Selectable(indent..'[G] '..group.name..'  ('..count..')##scene_group_'..group.id,false) then
        local selected,err=app.assemblies:select_group(group.id,true,true)
        local ws=app.model.data.settings.workspace;ws.multi_pivot_mode=group.pivot_mode or 'center'
        if group.pivot and group.pivot.position then ws.multi_custom_pivot=Util.deepcopy(group.pivot.position) end
        self.notify(err or (selected and ('Selected '..selected.count..' object(s)') or 'Group selection failed'))
    end
    ImGui.SameLine();if ImGui.SmallButton('X##group_dissolve_'..group.id) then
        local dissolved,err=app.assemblies:dissolve_group(group.id);self.notify(err or (dissolved and 'Group dissolved; objects preserved' or 'Dissolve failed'))
    end
    if not open then return end
    self.group_names[group.id]=self.group_names[group.id] or group.name
    self.group_names[group.id]=select(1,ImGui.InputText('##group_name_'..group.id,self.group_names[group.id],96))
    ImGui.SameLine();if ImGui.SmallButton('RENAME##group_rename_'..group.id) then
        local renamed,err=app.assemblies:update_group(group.id,{name=self.group_names[group.id]});self.notify(err or (renamed and 'Group renamed' or 'Rename failed'))
    end
    for _,object in ipairs(direct) do self:object_item(object,indent..'    ') end
    for _,child in ipairs(nested) do self:draw_group_node(child,children,object_by_id,(depth or 0)+1) end
end

function Hierarchy:draw_prefabs(premise_id)
    local app=self.app
    for _,prefab in ipairs(app.model.data.object_prefabs or {}) do
        if matches(prefab,self.search) then
            ImGui.TextWrapped('[P] '..prefab.name..'  ('..tostring(#(prefab.objects or {}))..')')
            if app.thumbnails and app.thumbnails:has_prefab(prefab) then
                app.thumbnails:draw_prefab(prefab,92,64);ImGui.SameLine()
            end
            if ImGui.SmallButton('RENDER THUMB##prefab_render_'..prefab.id) then
                local result,err=app.thumbnails:render_prefab(prefab.id)
                self.notify(err or (result and 'Rendering prefab thumbnail in-game…' or 'Prefab thumbnail render failed'))
            end
            ImGui.SameLine()
            if ImGui.SmallButton('AT PLAYER##prefab_player_'..prefab.id) then
                local result,err=app.assemblies:instantiate_prefab(prefab.id,{premise_id=premise_id,room_id=app.selected_room_id,source='player',spawn=true})
                self.notify(err or (result and ('Placed '..result.count..' editable object(s)') or 'Prefab placement failed'))
            end
            ImGui.SameLine();if ImGui.SmallButton('AT AIM##prefab_aim_'..prefab.id) then
                local result,err=app.assemblies:instantiate_prefab(prefab.id,{premise_id=premise_id,room_id=app.selected_room_id,source='aim',spawn=true})
                self.notify(err or (result and ('Placed '..result.count..' editable object(s)') or 'Prefab placement failed'))
            end
            ImGui.SameLine();if ImGui.SmallButton('DELETE##prefab_delete_'..prefab.id) then
                local result,err=app.assemblies:delete_prefab(prefab.id);self.notify(err or (result and 'Prefab deleted' or 'Delete failed'))
            end
        end
    end
    if #(app.model.data.object_prefabs or {})==0 then Theme.muted('No saved prefabs. Multi-select placed objects, then use SAVE PREFAB.') end
end

function Hierarchy:draw_group(label,key,count,draw_items)
    local open=self.show[key]
    if ImGui.SmallButton((open and 'v ' or '> ')..label..'  '..count..'##group_'..key) then self.show[key]=not open end
    if open then draw_items() end
end

local CONSTRUCTION_ROLES={'all','wall','floor','ceiling','door','window','collision'}

function Hierarchy:construction_toolbar(premise_id,construction)
    local app=self.app;local workspace=app.model.data.settings.workspace
    local role=workspace.construction_role or 'all';local index=1
    for i,value in ipairs(CONSTRUCTION_ROLES) do if value==role then index=i;break end end
    if ImGui.SmallButton('ROLE: '..string.upper(role)..'##construction_role') then
        index=index%#CONSTRUCTION_ROLES+1;workspace.construction_role=CONSTRUCTION_ROLES[index];app:mark_dirty()
    end
    ImGui.SameLine()
    local show_collision,changed=ImGui.Checkbox('Collision##construction_collision',workspace.show_collision==true)
    if changed then workspace.show_collision=show_collision;app:mark_dirty() end
    local room_id=app.selected_room_id
    local scope=room_id and 'ROOM' or 'LOCATION'
    local include_collision=workspace.show_collision or workspace.construction_role=='collision'
    self:selection_toolbar(construction,'construction')
    if ImGui.SmallButton('SHOW '..scope..'##construction_show') then
        local result,err=app.builder:set_construction_state(premise_id,room_id,workspace.construction_role,{enabled=true,include_collision=include_collision})
        self.notify(err or (result and ('Enabled '..result.changed..' construction piece(s)') or 'No construction changed'))
    end
    ImGui.SameLine();if ImGui.SmallButton('HIDE##construction_hide') then
        local result,err=app.builder:set_construction_state(premise_id,room_id,workspace.construction_role,{enabled=false,include_collision=include_collision})
        self.notify(err or (result and ('Hidden '..result.changed..' construction piece(s)') or 'No construction changed'))
    end
    ImGui.SameLine();if ImGui.SmallButton('LOCK##construction_lock') then
        local result,err=app.builder:set_construction_state(premise_id,room_id,workspace.construction_role,{locked=true,include_collision=include_collision})
        self.notify(err or (result and ('Locked '..result.changed..' construction piece(s)') or 'No construction changed'))
    end
    ImGui.SameLine();if ImGui.SmallButton('UNLOCK##construction_unlock') then
        local result,err=app.builder:set_construction_state(premise_id,room_id,workspace.construction_role,{locked=false,include_collision=include_collision})
        self.notify(err or (result and ('Unlocked '..result.changed..' construction piece(s)') or 'No construction changed'))
    end
end

function Hierarchy:draw()
    Theme.section('Scene','hierarchy')
    self.search=select(1,ImGui.InputTextWithHint('##scene_search','Filter scene...',self.search,128))
    ImGui.Spacing()
    local app=self.app;local premise_id=app.selected_premise_id;local simple=app.model.data.settings.workspace.beginner_mode~=false
    Theme.accent(simple and 'LOCATION' or 'PREMISES')
    for _,premise in ipairs(app.model.data.premises) do self:item('premise',premise,simple and '  ' or '[P]  ') end
    if #app.model.data.premises==0 then ImGui.TextDisabled(simple and 'No location yet. Open HOME to create your first room.' or 'No premise. Create one from player.') end
    if not premise_id then return end

    local scenes,rooms,construction,objects,gameplay={},{},{},{},{}
    for _,v in ipairs(app.model.data.scenes or {}) do if v.premise_id==premise_id then table.insert(scenes,v) end end
    for _,v in ipairs(app.model.data.rooms) do if v.premise_id==premise_id then table.insert(rooms,v) end end
    for _,v in ipairs(app.model.data.objects) do
        local metadata=v.metadata or {}
        if v.premise_id==premise_id then
            if metadata.room_kit==true then
                local role=metadata.room_collision and 'collision' or (metadata.role or v.kind)
                local role_filter=app.model.data.settings.workspace.construction_role or 'all'
                if (metadata.room_collision~=true or app.model.data.settings.workspace.show_collision==true or role_filter=='collision') and (role_filter=='all' or role_filter==role) then table.insert(construction,v) end
            else table.insert(objects,v) end
        end
    end
    for _,v in ipairs(app.model.data.locations) do table.insert(gameplay,{kind='location',item=v}) end
    for _,v in ipairs(app.model.data.volumes) do if v.premise_id==premise_id then table.insert(gameplay,{kind='volume',item=v}) end end
    for _,v in ipairs(app.model.data.cameras) do if v.premise_id==premise_id then table.insert(gameplay,{kind='camera',item=v}) end end
    for _,v in ipairs(app.model.data.routes) do table.insert(gameplay,{kind='route',item=v}) end

    ImGui.Spacing()
    self:draw_group('SCENES','scenes',#scenes,function() for _,v in ipairs(scenes) do self:item('scene',v,simple and '    ' or '   [S]  ') end end)
    self:draw_group('ROOMS','rooms',#rooms,function() for _,v in ipairs(rooms) do self:item('room',v,simple and '    ' or '   [R]  ') end end)
    self:draw_group('CONSTRUCTION','construction',#construction,function()
        self:construction_toolbar(premise_id,construction)
        for _,v in ipairs(construction) do
            local metadata=v.metadata or {};local role=metadata.room_collision and 'collision' or (metadata.role or v.kind or 'piece')
            local state=(v.locked and '[L] ' or (v.enabled==false or v.visible==false) and '[-] ' or '    ')
            self:object_item(v,'   '..state..string.upper(string.sub(role,1,1))..'  ')
        end
    end)
    local premise_groups,group_children,assigned,object_by_id={},{},{},{}
    for _,object in ipairs(objects) do object_by_id[object.id]=object end
    for _,group in ipairs(app.model.data.object_groups or {}) do
        if group.premise_id==premise_id then
            table.insert(premise_groups,group);group_children[group.parent_id or 'root']=group_children[group.parent_id or 'root'] or {};table.insert(group_children[group.parent_id or 'root'],group)
            for _,id in ipairs(group.object_ids or {}) do assigned[id]=true end
        end
    end
    self:draw_group('GROUPS','groups',#premise_groups,function()
        self:assembly_toolbar()
        for _,group in ipairs(group_children.root or {}) do self:draw_group_node(group,group_children,object_by_id,0) end
    end)
    self:draw_group('PREFABS','prefabs',#(app.model.data.object_prefabs or {}),function() self:draw_prefabs(premise_id) end)
    local ungrouped={};for _,object in ipairs(objects) do if not assigned[object.id] then table.insert(ungrouped,object) end end
    self:draw_group('OBJECTS','objects',#ungrouped,function()
        self:selection_toolbar(ungrouped,'objects')
        for _,v in ipairs(ungrouped) do
            local state=(v.runtime and v.runtime.spawned) and '* ' or '  '
            self:object_item(v,'   '..state)
        end
    end)
    if not simple then
        self:draw_group('GAMEPLAY','gameplay',#gameplay,function()
            for _,v in ipairs(gameplay) do self:item(v.kind,v.item,'   ['..string.upper(string.sub(v.kind,1,1))..']  ') end
        end)
    end

end

return Hierarchy
