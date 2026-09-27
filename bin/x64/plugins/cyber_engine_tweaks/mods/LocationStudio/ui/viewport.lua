local Util=require('modules/util')

local Viewport={}
Viewport.__index=Viewport

function Viewport.new(app,notify)
    return setmetatable({app=app,notify=notify,canvas_h=430,last_error=nil},Viewport)
end

function Viewport:to_local(premise,position)
    local dx=(position.x or 0)-(premise.transform.position.x or 0)
    local dy=(position.y or 0)-(premise.transform.position.y or 0)
    return Util.rotate_xy(dx,dy,-(premise.transform.rotation.yaw or 0))
end

function Viewport:is_selected(kind,id)
    if kind=='object' and self.app.selection then return self.app.selection:contains_object(id) end
    return self.app.selection and self.app.selection:is(kind,id) or false
end

function Viewport:select(kind,id)
    if self.app.selection then self.app.selection:set(kind,id) end
end

local function fmt_xyz(position)
    position=position or {}
    return string.format('X %.2f  Y %.2f  Z %.2f',tonumber(position.x) or 0,tonumber(position.y) or 0,tonumber(position.z) or 0)
end

function Viewport:row(kind,item,premise,extra)
    local p=item.transform and item.transform.position or item.position
    if not p then return end
    local lx,ly=self:to_local(premise,p)
    local label=string.format('[%s]  %s##safe_view_%s_%s',string.upper(string.sub(kind,1,1)),item.name or item.id,kind,item.id)
    if ImGui.Selectable(label,self:is_selected(kind,item.id)) then self:select(kind,item.id) end
    ImGui.SameLine(245)
    ImGui.TextDisabled(string.format('local %.2f, %.2f  |  %s%s',lx,ly,fmt_xyz(p),extra and ('  |  '..extra) or ''))
end

function Viewport:draw_canvas(premise)
    local app=self.app
    local rooms,objects,volumes,cameras,covers,locations=0,0,0,0,0,0
    for _,v in ipairs(app.model.data.rooms) do if v.premise_id==premise.id then rooms=rooms+1 end end
    for _,v in ipairs(app.model.data.objects) do if v.premise_id==premise.id and not (v.metadata and v.metadata.generated) then objects=objects+1 end end
    for _,v in ipairs(app.model.data.volumes) do if v.premise_id==premise.id then volumes=volumes+1 end end
    for _,v in ipairs(app.model.data.cameras) do if v.premise_id==premise.id then cameras=cameras+1 end end
    for _,v in ipairs(app.model.data.cover_nodes or {}) do if v.premise_id==premise.id then covers=covers+1 end end
    locations=#(app.model.data.locations or {})

    ImGui.Text(string.format('Origin: %s',fmt_xyz(premise.transform.position)))
    ImGui.TextDisabled(string.format('%d rooms  |  %d objects  |  %d volumes  |  %d cameras  |  %d cover nodes  |  %d points',rooms,objects,volumes,cameras,covers,locations))
    ImGui.TextWrapped('Compatibility scene view: uses only CET-supported ImGui widgets. Select any row to edit it in the Inspector; transform buttons below operate on the shared selection.')
    ImGui.Separator()

    ImGui.BeginChild('##locationstudio_safe_scene',0,self.canvas_h,true)
    if rooms>0 then
        ImGui.Text('ROOMS')
        for _,room in ipairs(app.model.data.rooms) do if room.premise_id==premise.id then
            self:row('room',room,premise,string.format('%.1f x %.1f x %.1f',room.size.width,room.size.depth,room.size.height))
        end end
        ImGui.Separator()
    end

    if objects>0 then
        ImGui.Text('OBJECTS')
        for _,object in ipairs(app.model.data.objects) do if object.premise_id==premise.id and not (object.metadata and object.metadata.generated) then
            local live=(object.runtime and object.runtime.spawned) and 'LIVE' or 'offline'
            local template=(object.template and object.template~='') and object.template or 'no .ent template'
            self:row('object',object,premise,live..' / '..template)
        end end
        ImGui.Separator()
    end

    if volumes>0 then
        ImGui.Text('VOLUMES')
        for _,volume in ipairs(app.model.data.volumes) do if volume.premise_id==premise.id then
            self:row('volume',volume,premise,(volume.purpose or 'volume')..' / '..(volume.shape or 'box'))
        end end
        ImGui.Separator()
    end

    if cameras>0 then
        ImGui.Text('CAMERAS')
        for _,camera in ipairs(app.model.data.cameras) do if camera.premise_id==premise.id then
            self:row('camera',camera,premise,string.format('FOV %.1f',tonumber(camera.fov) or 50))
        end end
        ImGui.Separator()
    end

    if covers>0 then
        ImGui.Text('COVER NODES')
        for _,cover in ipairs(app.model.data.cover_nodes or {}) do if cover.premise_id==premise.id then
            self:row('cover_node',cover,premise,(cover.cover_type or 'crouch')..' / '..(cover.exposure or 'medium'))
        end end
        ImGui.Separator()
    end

    if locations>0 then
        ImGui.Text('POINTS')
        for _,location in ipairs(app.model.data.locations) do self:row('location',location,premise,location.type or 'point') end
    end

    if rooms+objects+volumes+cameras+covers+locations==0 then
        ImGui.TextDisabled('Scene is empty. Use BUILD, + POINT, + VOLUME, or + CAMERA to create authored data.')
    end
    ImGui.EndChild()
end

function Viewport:selected()
    local kind=self.app.selection.kind
    return kind,self.app.selection:resolve()
end

function Viewport:draw_aim_tools(premise)
    local settings=self.app.model.data.settings.asset_preview
    local changed
    if ImGui.Button('PICK AIMED OBJECT##scene_pick',185,28) then
        local result,warning=self.app.viewport_tools:pick_aimed_object({premise_id=premise.id,premise_only=true})
        if result then
            local message='Selected '..tostring(result.object.name or result.object.id)
            if warning then message=message..' (project selection works; WB focus: '..tostring(warning)..')' end
            if self.notify then self.notify(message) end
        elseif self.notify then self.notify(warning or 'No project object under crosshair') end
    end
    ImGui.SameLine();if ImGui.Button('GRAB SELECTION##scene_grab',150,28) then
        local grab=self.app.model.data.settings.transform_grab or {}
        local result,err=self.app.transform_session:start({distance=grab.distance,align_surface=grab.align_surface,snap_position=grab.snap_position,pivot_mode=grab.pivot_mode})
        if self.notify then self.notify(err or (result and ('Grab Move started for '..tostring(result.count)..' object(s)') or 'Grab Move failed')) end
    end
    ImGui.SameLine();if ImGui.Button('EDIT SELECTION##scene_edit',145,28) then
        local edit=self.app.model.data.settings.transform_edit or {};local workspace=self.app.model.data.settings.workspace or {}
        local selected=self.app.selection:object_count();local args={active_id=self.app.selection.id,pivot_mode=(selected>1 and workspace.multi_pivot_mode) or edit.pivot_mode or 'center',local_space=edit.local_space==true}
        if args.pivot_mode=='custom' then args.pivot={position=workspace.multi_custom_pivot or {x=0,y=0,z=0},rotation={yaw=0}} end
        local result,err=self.app.transform_session:start_edit(args)
        if self.notify then self.notify(err or (result and ('Transform Edit started for '..tostring(result.count)..' object(s)') or 'Transform Edit failed')) end
    end
    if ImGui.Button('DUPLICATE + EDIT##scene_duplicate_edit',175,28) then
        local edit=self.app.model.data.settings.transform_edit or {};local workspace=self.app.model.data.settings.workspace or {}
        local selected=self.app.selection:object_count();local args={active_id=self.app.selection.id,pivot_mode=(selected>1 and workspace.multi_pivot_mode) or edit.pivot_mode or 'center',local_space=edit.local_space==true}
        if args.pivot_mode=='custom' then args.pivot={position=workspace.multi_custom_pivot or {x=0,y=0,z=0},rotation={yaw=0}} end
        local result,err=self.app.transform_session:start_duplicate(args)
        if self.notify then self.notify(err or (result and ('Duplicated '..tostring(result.count)..' object(s); position and commit') or 'Duplicate Edit failed')) end
    end
    ImGui.SameLine();if ImGui.Button('ARRAY + EDIT##scene_pattern_edit',145,28) then
        local grid=tonumber(self.app.model.data.settings.snapping.grid) or 0.25
        local result,err=self.app.transform_session:start_pattern({count=2,dx=grid,dy=0,dz=0,dyaw=0,pattern_local_space=true})
        if self.notify then self.notify(err or (result and ('Array preview started with '..tostring(result.count)..' copies') or 'Array Edit failed')) end
    end
    ImGui.PushItemWidth(100)
    settings.pick_distance,changed=ImGui.InputFloat('Pick distance',tonumber(settings.pick_distance) or 40,1,5,'%.1f');if changed then settings.pick_distance=math.max(1,settings.pick_distance);self.app:mark_dirty() end
    ImGui.SameLine();settings.pick_radius,changed=ImGui.InputFloat('Pick radius',tonumber(settings.pick_radius) or 0.75,0.05,0.25,'%.2f');if changed then settings.pick_radius=math.max(0.05,settings.pick_radius);self.app:mark_dirty() end
    ImGui.PopItemWidth();ImGui.SameLine()
    settings.pick_focus_world_builder,changed=ImGui.Checkbox('Focus WB gizmo',settings.pick_focus_world_builder~=false);if changed then self.app:mark_dirty() end
    local status=self.app.viewport_tools:status()
    if status.last_pick and status.last_pick.ok then
        ImGui.TextDisabled(string.format('Last pick: %s | ray %.2f m | crosshair error %.2f m',status.last_pick.object_name or status.last_pick.object_id,status.last_pick.ray_distance or 0,status.last_pick.perpendicular_distance or 0))
    else
        ImGui.TextDisabled('Aim at a saved project object, then pick it. This selects the LocationStudio object and its World Builder handle when available.')
    end
end

function Viewport:draw_gizmo()
    local kind,item=self:selected()
    if not item then ImGui.TextDisabled('Select a room, object, volume, camera, point, or premise to transform it.');return end
    if not item.transform then ImGui.TextDisabled(string.upper(kind)..' selection has no transform.');return end
    local settings=self.app.model.data.settings.snapping
    local step=settings.enabled and settings.grid or 0.1
    local angle=settings.enabled and settings.angle or 5
    ImGui.Separator()
    local group=kind=='object' and self.app.selection:selected_objects() or nil
    local group_count=group and #group or 1
    ImGui.Text(string.format('SELECTED: %s / %s%s',string.upper(kind),item.name or item.id,group_count>1 and (' + '..tostring(group_count-1)..' more') or ''))
    local function move(dx,dy,dz,dyaw)
        local updated,err
        if kind=='object' and group_count>1 then
            local ids={};for _,object in ipairs(group) do table.insert(ids,object.id) end
            updated,err=self.app.authoring:transform_object_group(ids,{dx=dx,dy=dy,dz=dz,dyaw=dyaw,local_space=true,active_id=item.id})
        else updated,err=self.app.authoring:batch_transform(kind,{item.id},dx,dy,dz,dyaw,true) end
        if not updated and self.notify then self.notify(err or 'Transform failed') elseif err and self.notify then self.notify(err) end
    end
    if ImGui.Button('-X##gizmo') then move(-step,0,0,0) end;ImGui.SameLine();if ImGui.Button('+X##gizmo') then move(step,0,0,0) end
    ImGui.SameLine();if ImGui.Button('-Y##gizmo') then move(0,-step,0,0) end;ImGui.SameLine();if ImGui.Button('+Y##gizmo') then move(0,step,0,0) end
    ImGui.SameLine();if ImGui.Button('-Z##gizmo') then move(0,0,-step,0) end;ImGui.SameLine();if ImGui.Button('+Z##gizmo') then move(0,0,step,0) end
    ImGui.SameLine();if ImGui.Button('ROT -##gizmo') then move(0,0,0,-angle) end;ImGui.SameLine();if ImGui.Button('ROT +##gizmo') then move(0,0,0,angle) end
    ImGui.SameLine();if ImGui.Button('SNAP##gizmo') then
        local snapped,err=self.app.authoring:snap_item(kind,item.id,settings.grid,settings.angle)
        if snapped and kind=='object' and self.app.placement:is_tracked(snapped) then
            if snapped.metadata and type(snapped.metadata.world_builder)=='table' then self.app.runtime_shell:update_object(snapped) else self.app.placement:refresh(snapped) end
        elseif snapped and self.app.ent_tools then self.app.ent_tools:refresh_live_scope(kind,item.id) end
        if not snapped and self.notify then self.notify(err or 'Snap failed') end
    end
end

function Viewport:draw()
    local premise=self.app.model:get_premise(self.app.selected_premise_id)
    if not premise then ImGui.TextDisabled('Select or create a premise to open the scene view.');return end
    local snapping=self.app.model.data.settings.snapping;local changed
    snapping.enabled,changed=ImGui.Checkbox('Snapping',snapping.enabled);if changed then self.app:mark_dirty() end
    ImGui.SameLine();snapping.grid,changed=ImGui.InputFloat('Grid',snapping.grid,0.05,0.5,'%.3f');if changed then self.app:mark_dirty() end
    ImGui.SameLine();snapping.angle,changed=ImGui.InputFloat('Angle',snapping.angle,1,15,'%.1f');if changed then self.app:mark_dirty() end
    self:draw_aim_tools(premise)
    self:draw_canvas(premise)
    self:draw_gizmo()
end

return Viewport
