local Util=require('modules/util')
local Widgets=require('ui/widgets')
local Theme=require('ui/theme')

local Inspector={}
Inspector.__index=Inspector

function Inspector.new(app,notify) return setmetatable({app=app,notify=notify,cache=nil,selection_revision=-1},Inspector) end

function Inspector:start_grab()
    local settings=self.app.model.data.settings.transform_grab or {}
    local result,err=self.app.transform_session:start({distance=settings.distance,align_surface=settings.align_surface,snap_position=settings.snap_position,pivot_mode=settings.pivot_mode})
    self.notify(err or (result and ('Grab Move started for '..tostring(result.count)..' object(s)') or 'Grab Move failed'))
    return result,err
end

function Inspector:start_edit()
    local settings=self.app.model.data.settings.transform_edit or {}
    local workspace=self.app.model.data.settings.workspace or {}
    local selected=self.app.selection:object_count()
    local pivot_mode=(selected>1 and workspace.multi_pivot_mode) or settings.pivot_mode or 'center'
    local args={active_id=self.app.selection.id,pivot_mode=pivot_mode,local_space=settings.local_space==true}
    if pivot_mode=='custom' then args.pivot={position=workspace.multi_custom_pivot or {x=0,y=0,z=0},rotation={yaw=0}} end
    local result,err=self.app.transform_session:start_edit(args)
    self.notify(err or (result and ('Transform Edit started for '..tostring(result.count)..' object(s)') or 'Transform Edit failed'))
    return result,err
end

function Inspector:start_duplicate_edit()
    local settings=self.app.model.data.settings.transform_edit or {}
    local workspace=self.app.model.data.settings.workspace or {}
    local selected=self.app.selection:object_count()
    local pivot_mode=(selected>1 and workspace.multi_pivot_mode) or settings.pivot_mode or 'center'
    local args={active_id=self.app.selection.id,pivot_mode=pivot_mode,local_space=settings.local_space==true}
    if pivot_mode=='custom' then args.pivot={position=workspace.multi_custom_pivot or {x=0,y=0,z=0},rotation={yaw=0}} end
    local result,err=self.app.transform_session:start_duplicate(args)
    self.notify(err or (result and ('Duplicated '..tostring(result.count)..' object(s); position the copies, then commit') or 'Duplicate Edit failed'))
    return result,err
end

function Inspector:start_pattern_edit()
    local grid=tonumber(self.app.model.data.settings.snapping.grid) or 0.25
    local result,err=self.app.transform_session:start_pattern({count=2,dx=grid,dy=0,dz=0,dyaw=0,pattern_local_space=true})
    self.notify(err or (result and ('Array preview started with '..tostring(result.count)..' live copies') or 'Array Edit failed'))
    return result,err
end

function Inspector:start_mirror_edit(axis)
    local result,err=self.app.transform_session:start_mirror({axis=axis})
    self.notify(err or (result and ('Mirror '..string.upper(axis)..' preview started') or 'Mirror Edit failed'))
    return result,err
end

function Inspector:start_scatter_edit()
    local settings=self.app.model.data.settings.ent_tools or {}
    local result,err=self.app.transform_session:start_scatter({
        count=settings.scatter_count or 6,radius=settings.scatter_radius or 2,distance=settings.scatter_distance or 12,
        seed=settings.scatter_seed or 2077,random_yaw=settings.scatter_random_yaw~=false,drop_to_ground=settings.scatter_drop~=false,
    })
    self.notify(err or (result and ('Scatter preview started with '..tostring(result.count)..' live copies') or 'Scatter Edit failed'))
    return result,err
end

function Inspector:start_placement_edit(mode)
    local kind=self.app.selection.kind
    if kind~='asset' and kind~='object' then self.notify('Select a Project Asset or placed object first');return nil,'invalid selection' end
    local preview=self.app.model.data.settings.asset_preview or {}
    local result,err=self.app.transform_session:start_placement({
        kind=kind,id=self.app.selection.id,mode=mode or 'aim',distance=preview.distance or 10,
        surface_offset=preview.surface_offset,align_surface=preview.align_surface==true,
    })
    self.notify(err or (result and ('Placement Edit started for '..tostring(result.count)..' object(s)') or 'Placement Edit failed'))
    return result,err
end

function Inspector:sync()
    local item=self.app.selection:resolve();if not item then self.cache=nil;return end
    self.cache=Util.deepcopy(item);self.selection_revision=self.app.selection.revision
end

local function input3(label,value,format)
    local v={tonumber(value.x) or 0,tonumber(value.y) or 0,tonumber(value.z) or 0}
    v=select(1,Widgets.input3(label,v,format or '%.3f'))
    return {x=v[1],y=v[2],z=v[3],w=value.w}
end

function Inspector:draw_transform(c)
    if not c.transform then return end
    Theme.section('Transform','world space')
    c.transform.position=input3('Position',c.transform.position,'%.4f')
    local r=c.transform.rotation
    local values={r.roll,r.pitch,r.yaw};values=select(1,Widgets.input3('Rotation',values,'%.2f'))
    c.transform.rotation={roll=values[1],pitch=values[2],yaw=values[3]}
    local settings=self.app.model.data.settings.snapping
    if ImGui.Button('SNAP TO GRID') then
        local item,err=self.app.authoring:snap_item(self.app.selection.kind,self.app.selection.id,settings.grid,settings.angle)
        if item then self:sync();self.notify('Snapped '..item.name) else self.notify(err) end
    end
    ImGui.SameLine();ImGui.TextDisabled(string.format('%.2fm / %.1f deg',settings.grid,settings.angle))
    local tools=self.app.ent_tools
    if tools then
        if ImGui.Button('COPY XFORM',105,26) then local _,err=tools:copy('transform');self.notify(err or 'Transform copied') end
        ImGui.SameLine();if ImGui.Button('PASTE XFORM',110,26) then local item,err=tools:paste('transform');if item then self:sync() end;self.notify(err or (item and 'Transform pasted' or 'Paste failed')) end
        ImGui.SameLine();if ImGui.Button('RESET ROT',92,26) then local item,err=tools:reset_rotation();if item then self:sync() end;self.notify(err or (item and 'Rotation reset' or 'Reset failed')) end
        if ImGui.Button('TO PLAYER',95,26) then local item,err=tools:move_to_player(nil,nil,false);if item then self:sync() end;self.notify(err or (item and 'Moved to player' or 'Move failed')) end
        ImGui.SameLine();if ImGui.Button('TO AIM',82,26) then local item,err=tools:move_to_aim(nil,nil,12);if item then self:sync() end;self.notify(err or (item and 'Moved to aim' or 'Move failed')) end
        ImGui.SameLine();if ImGui.Button('GROUND',90,26) then local item,err=tools:drop_to_ground();if item then self:sync() end;self.notify(err or (item and 'Dropped to ground' or 'Drop failed')) end
    end
    if self.app.selection.kind=='object' and Theme.primary_button('GRAB WITH CROSSHAIR',175,30) then self:start_grab() end
    if self.app.selection.kind=='object' then ImGui.SameLine();if Theme.action_button('EDIT TRANSFORM',135,30) then self:start_edit() end end
end

function Inspector:draw_type_fields(kind,c)
    if kind=='premise' then
        c.kind=select(1,ImGui.InputText('Kind',c.kind,64));c.levels=select(1,ImGui.InputInt('Levels',c.levels,1,5));c.floor_height=select(1,ImGui.InputFloat('Floor height',c.floor_height,0.1,0.5,'%.2f'))
    elseif kind=='room' then
        c.kind=select(1,ImGui.InputText('Kind',c.kind,64));c.level=select(1,ImGui.InputInt('Level',c.level,1,5))
        c.size.width=select(1,ImGui.InputFloat('Width',c.size.width,0.1,1,'%.2f'));c.size.depth=select(1,ImGui.InputFloat('Depth',c.size.depth,0.1,1,'%.2f'));c.size.height=select(1,ImGui.InputFloat('Height',c.size.height,0.1,1,'%.2f'))
        c.wall_thickness=select(1,ImGui.InputFloat('Wall thickness',c.wall_thickness,0.01,0.1,'%.3f'))
    elseif kind=='object' then
        c.kind=select(1,ImGui.InputText('Kind',c.kind,64));c.template=select(1,ImGui.InputText('Entity template',c.template,512));c.appearance=select(1,ImGui.InputText('Appearance',c.appearance,128));c.layer=select(1,ImGui.InputText('Layer',c.layer,64))
        c.size=input3('Bounds XYZ',c.size,'%.2f');c.enabled=select(1,ImGui.Checkbox('Enabled',c.enabled));ImGui.SameLine();c.visible=select(1,ImGui.Checkbox('Visible',c.visible));ImGui.SameLine();c.locked=select(1,ImGui.Checkbox('Locked',c.locked==true))
    elseif kind=='location' then
        c.type=select(1,ImGui.InputText('Type',c.type,64));c.category=select(1,ImGui.InputText('Category',c.category,96));c.radius=select(1,ImGui.InputFloat('Radius',c.radius,0.1,1,'%.2f'))
        c.metadata=c.metadata or {};c.metadata.coordinates_verified=select(1,ImGui.Checkbox('Verified in game (standable coordinate)',c.metadata.coordinates_verified==true))
        c.metadata.source=select(1,ImGui.InputText('Coordinate source / note',c.metadata.source or '',160))
    elseif kind=='volume' then
        c.purpose=select(1,ImGui.InputText('Purpose',c.purpose,64));c.shape=select(1,ImGui.InputText('Shape',c.shape,32));c.size=input3('Size XYZ',c.size,'%.2f');c.radius=select(1,ImGui.InputFloat('Radius',c.radius,0.1,1,'%.2f'))
    elseif kind=='camera' then
        c.kind=select(1,ImGui.InputText('Shot type',c.kind,64));c.fov=select(1,ImGui.SliderFloat('FOV',c.fov,10,140,'%.1f'));c.duration=select(1,ImGui.InputFloat('Duration',c.duration,0.1,1,'%.2fs'));c.look_at=input3('Look at',c.look_at,'%.3f')
    elseif kind=='cover_node' then
        if ImGui.BeginCombo('Cover posture',c.cover_type or 'crouch') then for _,value in ipairs({'crouch','standing'}) do if ImGui.Selectable(value,c.cover_type==value) then c.cover_type=value end end;ImGui.EndCombo() end
        if ImGui.BeginCombo('Exposure',c.exposure or 'medium') then for _,value in ipairs({'low','medium','high'}) do if ImGui.Selectable(value,c.exposure==value) then c.exposure=value end end;ImGui.EndCombo() end
        c.spacing=select(1,ImGui.InputFloat('Spacing (m)',c.spacing,0.25,0.5,'%.2f'));c.source=select(1,ImGui.InputText('Source',c.source or '',64))
        ImGui.TextDisabled('Cover direction is the selected transform yaw. Candidate exposure is an authoring estimate.')
    elseif kind=='route' then
        c.kind=select(1,ImGui.InputText('Route type',c.kind,64));c.loop=select(1,ImGui.Checkbox('Loop',c.loop));ImGui.TextDisabled(string.format('%d route points',#(c.location_ids or {})))
    elseif kind=='scene' then
        c.kind=select(1,ImGui.InputText('Scene type',c.kind,64));c.enabled=select(1,ImGui.Checkbox('Enabled',c.enabled~=false))
        ImGui.TextDisabled(string.format('%d rooms / %d objects / %d points / %d volumes / %d cameras / %d routes',#(c.room_ids or {}),#(c.object_ids or {}),#(c.location_ids or {}),#(c.volume_ids or {}),#(c.camera_ids or {}),#(c.route_ids or {})))
    elseif kind=='asset' then
        c.category=select(1,ImGui.InputText('Category',c.category,64));c.kind=select(1,ImGui.InputText('Kind',c.kind,64));c.template=select(1,ImGui.InputText('Entity template',c.template,512));c.appearance=select(1,ImGui.InputText('Appearance',c.appearance,128));c.layer=select(1,ImGui.InputText('Layer',c.layer,64));c.favorite=select(1,ImGui.Checkbox('Favorite',c.favorite))
    end
end

function Inspector:focus_world_builder(c)
    local object=self.app.model:get_object(c and c.id);if not object then return nil,'object not found' end
    if not self.app.placement:is_tracked(object) then
        local _,spawn_err=self.app.placement:spawn(object);if spawn_err then return nil,spawn_err end
    end
    return self.app.runtime_shell:focus(object)
end

function Inspector:draw_construction_actions(c)
    local metadata=c.metadata or {};local wb=metadata.world_builder
    if type(wb)~='table' then return end
    if Theme.action_button('WORLD BUILDER GIZMO',175,30) then
        local result,err=self:focus_world_builder(c);self:sync();self.notify(err or (result and 'World Builder gizmo selected' or 'Gizmo selection failed'))
    end
    if metadata.room_kit~=true then return end
    if metadata.room_collision~=true then
        local asset=self.app.model:get_asset(self.app.last_asset_id)
        ImGui.SameLine();if Theme.action_button('REPLACE ASSET',125,30) then
            local object,err=self.app.builder:replace_shell_object_asset(c.id,self.app.last_asset_id)
            if object then self:sync() end;self.notify(err or ('Replaced with '..tostring(asset and asset.name or 'selected asset')))
        end
        if asset then Theme.muted('Replacement: '..asset.name) else Theme.warning('Choose a Static Mesh in ASSETS, then return to this piece.') end
    end
    if Theme.action_button('DETACH / MAKE UNIQUE',175,30) then
        local object,err=self.app.builder:detach_shell_object(c.id);if object then self:sync() end;self.notify(err or 'Piece detached; room rebuilds will preserve it')
    end
    if c.room_id then
        ImGui.SameLine();if Theme.action_button('REBUILD ROOM',125,30) then
            local room_id=c.room_id;local result,err=self.app.builder:rebuild_room_shell(room_id)
            if result and self.app.model.data.settings.workspace.live_preview then local _,runtime_err=self.app.placement:spawn_room_shell(room_id);err=runtime_err or err end
            if result then self.app.selection:set('room',room_id);self:sync() end
            self.notify(err or (result and ('Rebuilt '..result.object_count..' room pieces') or 'Room rebuild failed'))
        end
    end
    Theme.muted('Room rebuild restores kit-managed pieces. Detach first to preserve a custom piece.')
end

function Inspector:draw_multi_object_editor(c)
    local objects=self.app.selection:selected_objects();if #objects<=1 then return false end
    local ids={};for _,object in ipairs(objects) do table.insert(ids,object.id) end
    local workspace=self.app.model.data.settings.workspace
    Theme.section('Multi-selection',tostring(#objects)..' objects / center pivot')
    if Theme.primary_button('GRAB SELECTION',145,30) then self:start_grab() end
    ImGui.SameLine();if Theme.action_button('EDIT SELECTION',130,30) then self:start_edit() end
    if Theme.action_button('DUPLICATE + EDIT',155,30) then self:start_duplicate_edit() end
    ImGui.SameLine();if Theme.action_button('ARRAY + EDIT',120,30) then self:start_pattern_edit() end
    if Theme.action_button('AIM COPY + EDIT',145,28) then self:start_placement_edit('aim') end
    ImGui.SameLine();Theme.muted('Copies the complete selection to the crosshair')
    Theme.muted('Live copy patterns / one commit or full cancel')
    if Theme.action_button('MIRROR X',110,28) then self:start_mirror_edit('x') end
    ImGui.SameLine();if Theme.action_button('MIRROR Y',110,28) then self:start_mirror_edit('y') end
    ImGui.SameLine();if Theme.action_button('SCATTER',100,28) then self:start_scatter_edit() end
    local changed
    workspace.multi_step,changed=ImGui.InputFloat('Move step##multi',tonumber(workspace.multi_step) or 0.25,0.05,0.5,'%.3f');if changed then self.app:mark_dirty() end
    workspace.multi_angle,changed=ImGui.InputFloat('Angle step##multi',tonumber(workspace.multi_angle) or 5,1,15,'%.1f');if changed then self.app:mark_dirty() end
    workspace.multi_scale_step,changed=ImGui.InputFloat('Scale step##multi',tonumber(workspace.multi_scale_step) or 0.1,0.01,0.25,'%.3f');if changed then self.app:mark_dirty() end
    workspace.multi_local_space,changed=ImGui.Checkbox('Active-object local axes##multi',workspace.multi_local_space==true);if changed then self.app:mark_dirty() end
    local pivot_modes={'center','active','custom'};local pivot_mode=workspace.multi_pivot_mode or 'center'
    if Theme.action_button('PIVOT: '..string.upper(pivot_mode)..'##multi',130,28) then
        local next_mode='center';for index,value in ipairs(pivot_modes) do if value==pivot_mode then next_mode=pivot_modes[index%#pivot_modes+1];break end end
        workspace.multi_pivot_mode=next_mode;pivot_mode=next_mode;self.app:mark_dirty()
    end
    if pivot_mode=='custom' then
        workspace.multi_custom_pivot=input3('Custom pivot##multi',workspace.multi_custom_pivot or {x=0,y=0,z=0},'%.3f')
        if Theme.action_button('PIVOT FROM PLAYER##multi',145,28) then
            local captured,err=self.app.game:capture_transform()
            if captured then workspace.multi_custom_pivot=Util.deepcopy(captured.position);self.app:mark_dirty() end
            self.notify(err or (captured and 'Custom pivot captured' or 'Pivot capture failed'))
        end
    end
    local function transform(args,label)
        args.active_id=c.id;args.local_space=workspace.multi_local_space
        if pivot_mode=='active' then args.pivot=c.transform elseif pivot_mode=='custom' then args.pivot={position=workspace.multi_custom_pivot,rotation={yaw=c.transform.rotation.yaw or 0}} end
        local result,err;local group_id=self.app.active_object_group_id;local saved=group_id and self.app.model:get_object_group(group_id)
        if saved then
            local grouped=self.app.assemblies:objects_for_group(group_id,true);local exact=grouped and #grouped==#objects
            if exact then for _,object in ipairs(grouped) do if not self.app.selection:contains_object(object.id) then exact=false;break end end end
            if exact then result,err=self.app.assemblies:transform_group(group_id,args) else self.app.active_object_group_id=nil end
        end
        if not result and not err then result,err=self.app.authoring:transform_object_group(ids,args) end
        if result then
            if group_id and self.app.model:get_object_group(group_id) and result.pivot then self.app.model:get_object_group(group_id).pivot=Util.deepcopy(result.pivot) end
            self:sync()
        end
        self.notify(err or (label..' '..#objects..' object(s)'))
    end
    local step=tonumber(workspace.multi_step) or 0.25;local angle=tonumber(workspace.multi_angle) or 5;local scale_step=math.max(0.001,tonumber(workspace.multi_scale_step) or 0.1)
    if Theme.action_button('-X##multi',42,28) then transform({dx=-step},'Moved') end;ImGui.SameLine();if Theme.action_button('+X##multi',42,28) then transform({dx=step},'Moved') end
    ImGui.SameLine();if Theme.action_button('-Y##multi',42,28) then transform({dy=-step},'Moved') end;ImGui.SameLine();if Theme.action_button('+Y##multi',42,28) then transform({dy=step},'Moved') end
    ImGui.SameLine();if Theme.action_button('-Z##multi',42,28) then transform({dz=-step},'Moved') end;ImGui.SameLine();if Theme.action_button('+Z##multi',42,28) then transform({dz=step},'Moved') end
    if Theme.action_button('YAW -##multi',78,28) then transform({dyaw=-angle},'Rotated') end;ImGui.SameLine();if Theme.action_button('YAW +##multi',78,28) then transform({dyaw=angle},'Rotated') end
    ImGui.SameLine();if Theme.action_button('SCALE -##multi',82,28) then transform({scale_factor=math.max(0.01,1-scale_step)},'Scaled') end;ImGui.SameLine();if Theme.action_button('SCALE +##multi',82,28) then transform({scale_factor=1+scale_step},'Scaled') end
    Theme.kicker('PRECISION LAYOUT')
    local align_modes={'min','center','max','active'};local align_mode=workspace.layout_align_mode or 'center'
    if Theme.action_button('ALIGN: '..string.upper(align_mode)..'##multi',130,28) then
        local next_mode='center';for index,value in ipairs(align_modes) do if value==align_mode then next_mode=align_modes[index%#align_modes+1];break end end
        workspace.layout_align_mode=next_mode;align_mode=next_mode;self.app:mark_dirty()
    end
    local function layout(operation,axis,label)
        local result,err=self.app.authoring:layout_object_group(ids,{operation=operation,axis=axis,mode=align_mode,active_id=c.id})
        if result then self:sync() end;self.notify(err or (label..' '..#objects..' object(s)'))
    end
    if Theme.action_button('ALIGN X##multi',78,28) then layout('align','x','Aligned') end
    ImGui.SameLine();if Theme.action_button('ALIGN Y##multi',78,28) then layout('align','y','Aligned') end
    ImGui.SameLine();if Theme.action_button('ALIGN Z##multi',78,28) then layout('align','z','Aligned') end
    if Theme.action_button('SPACE X##multi',78,28) then layout('distribute','x','Distributed') end
    ImGui.SameLine();if Theme.action_button('SPACE Y##multi',78,28) then layout('distribute','y','Distributed') end
    ImGui.SameLine();if Theme.action_button('SPACE Z##multi',78,28) then layout('distribute','z','Distributed') end
    if Theme.action_button('MATCH ROTATION##multi',125,28) then layout('match_rotation',nil,'Matched rotation on') end
    ImGui.SameLine();if Theme.action_button('MATCH SCALE##multi',105,28) then layout('match_scale',nil,'Matched scale on') end
    ImGui.SameLine();if Theme.action_button('SNAP SET##multi',88,28) then
        local result,err=self.app.authoring:layout_object_group(ids,{operation='snap',grid=self.app.model.data.settings.snapping.grid,angle=self.app.model.data.settings.snapping.angle,active_id=c.id})
        if result then self:sync() end;self.notify(err or (result and ('Snapped '..#objects..' object(s)') or 'Snap failed'))
    end
    if Theme.action_button('REPLACE SET ASSET##multi',155,28) then
        local result,err=self.app.actions:replace_object_group_asset(ids,self.app.last_asset_id)
        if result then self:sync() end;self.notify(err or (result and ('Replaced '..result.count..' object(s) with '..result.asset.name) or 'Replacement failed'))
    end
    if Theme.action_button('GROUP GIZMO',110,28) then local result,err=self.app.runtime_shell:focus_many(objects,c.id);self.notify(err or (result and ('World Builder selected '..result.count..' object(s)') or 'Selection failed')) end
    ImGui.SameLine();if Theme.action_button('DUPLICATE SET',120,28) then self:start_duplicate_edit() end
    if Theme.action_button('SHOW SET',90,28) then local result,err=self.app.actions:set_object_group_state(ids,{enabled=true,visible=true});self:sync();self.notify(err or (result and 'Selection shown' or 'Show failed')) end
    ImGui.SameLine();if Theme.action_button('HIDE SET',90,28) then local result,err=self.app.actions:set_object_group_state(ids,{enabled=false,visible=false});self:sync();self.notify(err or (result and 'Selection hidden' or 'Hide failed')) end
    ImGui.SameLine();if Theme.action_button('LOCK SET',90,28) then local result,err=self.app.actions:set_object_group_state(ids,{locked=true});self:sync();self.notify(err or (result and 'Selection locked' or 'Lock failed')) end
    ImGui.SameLine();if Theme.action_button('UNLOCK SET',100,28) then local result,err=self.app.actions:set_object_group_state(ids,{locked=false});self:sync();self.notify(err or (result and 'Selection unlocked' or 'Unlock failed')) end
    if Theme.action_button('SPAWN SET',100,28) then local result,err=self.app.actions:spawn_object_group(ids,true);self:sync();self.notify(err or (result and 'Selection spawned' or 'Spawn failed')) end
    ImGui.SameLine();if Theme.action_button('DESPAWN SET',110,28) then local result,err=self.app.actions:spawn_object_group(ids,false);self:sync();self.notify(err or (result and 'Selection despawned' or 'Despawn failed')) end
    ImGui.SameLine();if Theme.danger_button('DELETE SET',100,28) then local result,err=self.app.actions:delete_object_group(ids);self:sync();self.notify(err or (result and ('Deleted '..result.deleted..' object(s)') or 'Delete failed')) end
    Theme.muted('Individual fields below edit only the active object: '..tostring(c.name or c.id))
    return true
end

function Inspector:draw_actions(kind,c)
    Theme.section('Actions','selection driven')
    if kind=='object' then
        local spawned=c.runtime and c.runtime.spawned
        Theme.info('RUNTIME: '..string.upper((c.runtime or {}).status or (spawned and 'submitted' or 'idle')))
        if (c.runtime or {}).error then ImGui.TextWrapped(c.runtime.error) end
        if ImGui.Button('SPAWN',92,30) then local _,err=self.app.actions:spawn_selected();self:sync();self.notify(err or 'Object spawned') end
        ImGui.SameLine();if ImGui.Button('REFRESH',92,30) then local _,err=self.app.actions:refresh_selected();self:sync();self.notify(err or 'Object refreshed') end
        ImGui.SameLine();if ImGui.Button('DESPAWN',92,30) then local ok,err=self.app.actions:despawn_selected();self:sync();self.notify(ok and 'Object despawned' or err) end
        self:draw_construction_actions(c)
    elseif kind=='room' then
        if ImGui.Button('REBUILD SHELL',190,30) then local _,err=self.app.actions:refresh_selected();self.notify(err or 'Room shell rebuilt') end
    elseif kind=='premise' then
        if ImGui.Button('SPAWN PREMISE',140,30) then local _,err=self.app.actions:spawn_selected();self.notify(err or 'Premise spawned') end
        ImGui.SameLine();if ImGui.Button('DESPAWN',110,30) then local ok,err=self.app.actions:despawn_selected();self.notify(ok and 'Premise despawned' or err) end
    elseif kind=='location' then
        if ImGui.Button('TELEPORT TEST',170,30) then local ok,err=self.app.game:teleport(c.transform);self.notify(ok and 'Teleported' or err) end
    elseif kind=='camera' then
        if ImGui.Button('PREVIEW CAMERA',170,30) then local _,err=self.app.authoring:preview_camera(c.id);self.notify(err or 'Camera preview') end
    elseif kind=='scene' then
        if Theme.primary_button('ACTIVATE SCENE',145,30) then local result,err=self.app.scenes:activate(c.id,true);self:sync();self.notify(err or (result and ('Activated; '..#result.spawned..' object(s) submitted') or 'Activation failed')) end
        ImGui.SameLine();if Theme.action_button('ISOLATE SCENE',130,30) then local result,err=self.app.scenes:isolate(c.id);self:sync();self.notify(err or (result and 'Scene isolated' or 'Isolation failed')) end
        if Theme.action_button('DEACTIVATE SCENE',155,30) then local result,err=self.app.scenes:deactivate(c.id);self:sync();self.notify(err or (result and 'Scene deactivated' or 'Deactivation failed')) end
        ImGui.SameLine();if Theme.action_button('SELECT OBJECTS',145,30) then local result,err=self.app.scenes:select_objects(c.id);self:sync();self.notify(err or (result and ('Selected '..result.selected..' object(s)') or 'Selection failed')) end
    elseif kind=='asset' then
        local settings=self.app.model.data.settings.asset_preview
        if ImGui.Button('PREVIEW AT AIM',140,30) then local _,err=self.app.placement:preview_asset(c.id,{mode='aim',distance=settings.distance or 10,follow=settings.auto_follow~=false,surface_offset=settings.surface_offset});self.notify(err or 'Asset preview active') end
        ImGui.SameLine();if ImGui.Button('PREVIEW HERE',120,30) then local _,err=self.app.placement:preview_asset(c.id,{mode='player',follow=false,surface_offset=settings.surface_offset});self.notify(err or 'Asset preview active') end
        if ImGui.Button('PLACE + EDIT',140,30) then self:start_placement_edit('aim') end
        ImGui.SameLine();if ImGui.Button('HERE + EDIT',120,30) then self:start_placement_edit('player') end
        ImGui.SameLine();if ImGui.Button('PREVIEW + EDIT',145,30) then self:start_placement_edit('preview') end
        if Theme.action_button('SCATTER + EDIT',145,30) then self:start_scatter_edit() end
        ImGui.SameLine();Theme.muted('Uses deterministic settings from Advanced Tools')
        if ImGui.Button('CAPTURE THUMBNAIL',165,30) then local _,err=self.app.thumbnails:capture(c.id);self.notify(err or 'Capturing real thumbnail...') end
        ImGui.SameLine();if ImGui.Button('CLEAR PREVIEW',120,30) then local _,err=self.app.placement:clear_preview();self.notify(err or 'Preview cleared') end
    end
end


local SIMPLE_NAMES={premise='LOCATION',room='ROOM',object='OBJECT',location='POINT',volume='VOLUME',cover_node='COVER NODE',camera='CAMERA',route='ROUTE',scene='SCENE',asset='SAVED OBJECT'}

function Inspector:draw_simple(kind,c)
    Theme.section('SELECTED','only useful game-facing controls')
    Theme.accent(SIMPLE_NAMES[kind] or string.upper(kind));ImGui.SameLine();ImGui.TextDisabled(c.name or c.id)
    self:draw_questforge_link(kind,c)

    if kind=='premise' then
        ImGui.TextWrapped('Location container. Select a room or placed object to edit it.')
        return
    end

    if kind=='scene' then
        ImGui.TextWrapped(string.format('Reusable scene collection: %d rooms, %d objects, %d gameplay points, %d volumes, %d cameras, %d routes.',#(c.room_ids or {}),#(c.object_ids or {}),#(c.location_ids or {}),#(c.volume_ids or {}),#(c.camera_ids or {}),#(c.route_ids or {})))
        if Theme.primary_button('ACTIVATE SCENE',145,32) then local result,err=self.app.scenes:activate(c.id,true);self:sync();self.notify(err or (result and ('Scene activated; '..#result.spawned..' object(s) submitted.') or 'Activation failed')) end
        ImGui.SameLine();if Theme.action_button('ISOLATE SCENE',130,32) then local result,err=self.app.scenes:isolate(c.id);self:sync();self.notify(err or (result and 'Scene isolated.' or 'Isolation failed')) end
        if Theme.action_button('DEACTIVATE SCENE',155,32) then local result,err=self.app.scenes:deactivate(c.id);self:sync();self.notify(err or (result and 'Scene deactivated.' or 'Deactivation failed')) end
        ImGui.SameLine();if Theme.action_button('SELECT OBJECTS',145,32) then local result,err=self.app.scenes:select_objects(c.id);self:sync();self.notify(err or (result and ('Selected '..result.selected..' object(s).') or 'Selection failed')) end
        ImGui.Spacing();if Theme.danger_button('DELETE SCENE',120,30) then local ok,err=self.app.actions:delete_selected();self:sync();self.notify(ok and 'Scene collection deleted; its members were preserved.' or err) end
        return
    end
    if kind=='cover_node' then
        ImGui.TextWrapped(string.format('%s cover position; %s exposure; spacing %.2f m. Direction is world yaw %.1f°.',c.cover_type or 'crouch',c.exposure or 'medium',c.spacing or 1.5,(c.transform.rotation or {}).yaw or 0))
        c.cover_type=select(1,ImGui.InputText('Posture (crouch/standing)',c.cover_type or 'crouch',24))
        c.exposure=select(1,ImGui.InputText('Exposure (low/medium/high)',c.exposure or 'medium',24))
        c.spacing=select(1,ImGui.InputFloat('Spacing (m)',c.spacing or 1.5,0.25,0.5,'%.2f'))
        ImGui.TextDisabled('Automatic candidates use Static/Dynamic collision rays; review cover, direction and exposure in game.')
        self:draw_transform(c)
        if ImGui.Button('APPLY',120,32) then local item,err=self.app.actions:update_cover_node({id=c.id,patch={name=c.name,cover_type=c.cover_type,exposure=c.exposure,spacing=c.spacing,transform=c.transform}});if item then self:sync();self.notify('Cover node saved') else self.notify(err) end end
        ImGui.SameLine();if ImGui.Button('DELETE',100,32) then local ok,err=self.app.actions:delete_selected();self:sync();self.notify(ok and 'Cover node deleted' or err) end
        return
    end

    c.name=select(1,ImGui.InputText('Name',c.name or '',160))
    local current=self.app.selection:resolve()
    if current and c.name~=current.name and Theme.action_button('APPLY NAME',115,28) then
        local item,err=self.app.actions:update_selected({name=c.name});if item then self:sync() end;self.notify(err or 'Name saved')
    end
    if kind=='room' then
        Theme.kicker('ROOM SIZE')
        c.size.width=select(1,ImGui.InputFloat('Width',c.size.width,0.25,1,'%.2f'))
        c.size.depth=select(1,ImGui.InputFloat('Depth',c.size.depth,0.25,1,'%.2f'))
        c.size.height=select(1,ImGui.InputFloat('Height',c.size.height,0.25,1,'%.2f'))
        ImGui.Spacing()
        if Theme.primary_button('UPDATE ROOM IN GAME',190,34) then
            local item,err=self.app.actions:update_selected(c)
            if item then
                local runtime,runtime_err=self.app.placement:spawn_room_shell(item.id)
                self:sync();self.notify(runtime and (err or runtime_err or ('Updated '..item.name..'; shell submitted.')) or (runtime_err or err or 'Room update failed'))
            else self.notify(err or 'Room update failed') end
        end
        ImGui.SameLine();if Theme.danger_button('DELETE ROOM',115,34) then local ok,err=self.app.actions:delete_selected();self:sync();self.notify(ok and 'Room deleted' or err) end
        return
    end

    if kind=='object' then
        local metadata=c.metadata or {};local role=metadata.room_collision and 'collision' or (metadata.role or c.kind or 'object')
        if metadata.room_kit==true then Theme.kicker('CONSTRUCTION PIECE / '..string.upper(role)) end
        self:draw_multi_object_editor(c)
        local spawned=c.runtime and c.runtime.spawned
        Theme.info('RUNTIME: '..string.upper((c.runtime or {}).status or (spawned and 'submitted' or 'idle')))
        if (c.runtime or {}).error then ImGui.TextWrapped(c.runtime.error) end
        local locked,lock_changed=ImGui.Checkbox('LOCK EDITING##simple_object',c.locked==true)
        if lock_changed then
            local item,err=self.app.actions:update_selected({locked=locked});if item then self:sync();c=self.cache end;self.notify(err or (locked and 'Object locked' or 'Object unlocked'))
        end
        self:draw_construction_actions(c)
        if c.locked then
            Theme.warning('LOCKED: transform, replacement, duplication and deletion are blocked.')
            if not spawned then if Theme.primary_button('SPAWN',90,32) then local _,err=self.app.actions:spawn_selected();self:sync();self.notify(err or 'Object spawned') end
            else if Theme.action_button('DESPAWN',95,32) then local ok,err=self.app.actions:despawn_selected();self:sync();self.notify(ok and 'Object despawned' or err) end end
            return
        end
        Theme.kicker('TRANSFORM')
        c.transform.position=input3('Position##simple_object',c.transform.position,'%.3f')
        local rotation={c.transform.rotation.roll,c.transform.rotation.pitch,c.transform.rotation.yaw};rotation=select(1,Widgets.input3('Rotation##simple_object',rotation,'%.2f'))
        c.transform.rotation={roll=rotation[1],pitch=rotation[2],yaw=rotation[3]}
        c.size=input3('Scale / bounds##simple_object',c.size or {x=1,y=1,z=1},'%.3f')
        c.template=select(1,ImGui.InputText('Template / resource##simple_object',c.template or '',512))
        c.appearance=select(1,ImGui.InputText('Appearance##simple_object',c.appearance or '',128))
        ImGui.Spacing()
        if Theme.primary_button('APPLY + REFRESH',145,32) then local item,err=self.app.actions:update_selected(c);if item then self:sync() end;self.notify(err or 'Object updated in game') end
        ImGui.SameLine();if Theme.action_button('DUPLICATE + EDIT',145,32) then self:start_duplicate_edit() end
        ImGui.SameLine();if Theme.action_button('AIM COPY + EDIT',145,32) then self:start_placement_edit('aim') end
        Theme.muted('PATTERN COPIES')
        if Theme.action_button('ARRAY',90,30) then self:start_pattern_edit() end
        ImGui.SameLine();if Theme.action_button('MIRROR X',100,30) then self:start_mirror_edit('x') end
        ImGui.SameLine();if Theme.action_button('MIRROR Y',100,30) then self:start_mirror_edit('y') end
        ImGui.SameLine();if Theme.action_button('SCATTER',95,30) then self:start_scatter_edit() end
        ImGui.Spacing()
        local tools=self.app.ent_tools
        if Theme.primary_button('GRAB WITH CROSSHAIR',175,32) then self:start_grab() end
        ImGui.SameLine();if Theme.action_button('EDIT TRANSFORM',135,32) then self:start_edit() end
        if tools then ImGui.SameLine();if Theme.action_button('MOVE TO AIM',120,32) then local item,err=tools:move_to_aim(nil,nil,12);if item then self:sync() end;self.notify(err or 'Moved to aim') end end
        if tools then ImGui.SameLine();if Theme.action_button('GROUND',90,32) then local item,err=tools:drop_to_ground();if item then self:sync() end;self.notify(err or 'Dropped to ground') end end
        if not spawned then ImGui.SameLine();if Theme.primary_button('SPAWN',90,32) then local _,err=self.app.actions:spawn_selected();self:sync();self.notify(err or 'Object spawned') end end
        if spawned then ImGui.SameLine();if Theme.action_button('DESPAWN',95,32) then local ok,err=self.app.actions:despawn_selected();self:sync();self.notify(ok and 'Object despawned' or err) end end
        ImGui.Spacing();if Theme.danger_button('DELETE OBJECT',125,30) then local ok,err=self.app.actions:delete_selected();self:sync();self.notify(ok and 'Object deleted' or err) end
        return
    end

    if kind=='location' then
        ImGui.TextWrapped('Captured location point.')
        if Theme.primary_button('TELEPORT HERE',130,32) then local ok,err=self.app.game:teleport(c.transform);self.notify(ok and 'Teleported' or err) end
        ImGui.SameLine();if Theme.danger_button('DELETE POINT',110,32) then local ok,err=self.app.actions:delete_selected();self:sync();self.notify(ok and 'Point deleted' or err) end
        return
    end

    if kind=='asset' then
        ImGui.TextWrapped('Preview one copy, place one copy, or start a reversible scatter transaction.')
        if Theme.action_button('PREVIEW AT AIM',135,32) then local settings=self.app.model.data.settings.asset_preview or {};local _,err=self.app.placement:preview_asset(c.id,{mode='aim',distance=settings.distance or 10,follow=settings.auto_follow~=false,surface_offset=settings.surface_offset});self.notify(err or 'Asset preview active') end
        ImGui.SameLine();if Theme.primary_button('PLACE + EDIT',125,32) then self:start_placement_edit('aim') end
        if Theme.action_button('SCATTER + EDIT',145,32) then self:start_scatter_edit() end
        ImGui.SameLine();Theme.muted('Commit once or cancel all copies')
        return
    end

    -- Cameras, volumes and routes are intentionally not part of the simple UI.
    ImGui.TextWrapped('This item is an advanced authoring type. Enable Advanced Tools to edit it.')
end

function Inspector:draw_questforge_link(kind,item)
    if not self.app.questforge_sync or not item or not ({location=true,volume=true,camera=true,object=true})[kind] then return end
    local link=self.app.questforge_sync:links(kind,item.id)
    if not link or not link.linked then return end
    Theme.section('QUEST FORGE LINK','synced reference data')
    ImGui.Text('NodeRef: '..tostring(link.node_ref or 'unmapped'))
    if link.manifest_name then ImGui.Text('Manifest key: '..tostring(link.manifest_name)) end
    if link.position_conflict then Theme.warning('Incoming Quest Forge coordinates differ; local placement is preserved.') end
    if #(link.facts or {})==0 then ImGui.TextDisabled('No linked quest facts') end
    for _,fact in ipairs(link.facts or {}) do ImGui.BulletText(tostring(fact.name)..' = '..tostring(fact.value)..' · '..tostring(fact.source)) end
end

function Inspector:draw()
    Theme.section('Inspector','context')
    if self.app.transform_session and self.app.transform_session:is_active() then
        local status=self.app.transform_session:status();Theme.warning(status.kind=='edit' and 'TRANSFORM EDIT ACTIVE' or 'GRAB MOVE ACTIVE')
        if status.kind=='edit' then
            ImGui.TextWrapped(string.format('%d object(s) are in one reversible transform transaction. Use the move/rotate/scale controls in the editor header, then commit or cancel.',status.count or 0))
            if (status.deferred_cet or 0)>0 then ImGui.TextWrapped('Direct CET entities respawn at every manual adjustment; World Builder resources update in place.') end
        else
            ImGui.TextWrapped(string.format('%d object(s) follow the crosshair. Use the controls in the editor header or the CET commit/cancel hotkeys.',status.count or 0))
            if (status.deferred_cet or 0)>0 then ImGui.TextWrapped('Direct CET entities update after commit; World Builder resources update live.') end
        end
        return
    end
    if self.selection_revision~=self.app.selection.revision then self:sync() end
    local kind=self.app.selection.kind;local c=self.cache
    if c and kind=='object' then
        local current=self.app.selection:resolve()
        if current then c.runtime=Util.deepcopy(current.runtime) end
    end
    if not c then ImGui.TextDisabled('Select an item in the scene or viewport.');ImGui.Spacing();ImGui.TextWrapped('The inspector changes with the selection. Spawn controls only appear for spawnable objects; shell controls only appear for rooms.') return end
    if self.app.model.data.settings.workspace.beginner_mode~=false then self:draw_simple(kind,c);return end
    Theme.accent(string.upper(kind));ImGui.SameLine();ImGui.TextDisabled(c.id)
    self:draw_questforge_link(kind,c)
    c.name=select(1,ImGui.InputText('Name',c.name or '',160))
    if kind=='object' then self:draw_multi_object_editor(c) end
    self:draw_type_fields(kind,c);self:draw_transform(c)
    if c.notes~=nil then Theme.section('Notes');c.notes=select(1,ImGui.InputTextMultiline('##notes',c.notes,1024,-1,62)) end
    if ImGui.Button('APPLY',120,32) then local item,err=self.app.actions:update_selected(c);if item then self:sync();self.notify(err or ('Applied '..item.name)) else self.notify(err) end end
    ImGui.SameLine();if ImGui.Button('REVERT',92,32) then self:sync() end
    self:draw_actions(kind,c)
    if kind=='object' or kind=='location' or kind=='volume' or kind=='camera' or kind=='asset' then
        if ImGui.Button('DUPLICATE',120,28) then local _,err=self.app.actions:duplicate_selected();self:sync();self.notify(err or 'Duplicated') end;ImGui.SameLine()
    end
    if ImGui.Button('DELETE',100,28) then local ok,err=self.app.actions:delete_selected();self:sync();self.notify(ok and 'Deleted' or err) end
end

return Inspector
