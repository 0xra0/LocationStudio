local Theme=require('ui/theme')

local Tools={}
Tools.__index=Tools

function Tools.new(app,notify)
    local settings=app.model.data.settings.ent_tools
    return setmetatable({app=app,notify=notify,array_count=4,array_dx=1,array_dy=0,array_dz=0,array_dyaw=0,scatter_count=settings.scatter_count,scatter_radius=settings.scatter_radius,scatter_distance=settings.scatter_distance,scatter_seed=settings.scatter_seed or 2077,scatter_random_yaw=settings.scatter_random_yaw,scatter_drop=settings.scatter_drop},Tools)
end

function Tools:run(label,fn)
    local ok,result,warning=pcall(fn)
    if not ok then self.notify(label..' failed: '..tostring(result));return nil end
    if not result then self.notify(warning or (label..' failed'));return nil end
    self.notify(warning or label);return result
end

function Tools:selection_label()
    local kind=self.app.selection.kind;local item=self.app.selection:resolve()
    if not item then return 'Nothing selected' end
    return string.format('%s / %s',string.upper(kind),item.name or item.id)
end

function Tools:draw_transform()
    local app=self.app;local tools=app.ent_tools
    Theme.section('entSpawner-style Transform Tools','copy / paste / snap / placement')
    ImGui.Text(self:selection_label())
    if ImGui.Button('COPY POS',105,28) then self:run('Position copied',function() return tools:copy('position') end) end
    ImGui.SameLine();if ImGui.Button('COPY ROT',105,28) then self:run('Rotation copied',function() return tools:copy('rotation') end) end
    ImGui.SameLine();if ImGui.Button('COPY XFORM',115,28) then self:run('Transform copied',function() return tools:copy('transform') end) end
    if ImGui.Button('PASTE POS',105,28) then self:run('Position pasted',function() return tools:paste('position') end) end
    ImGui.SameLine();if ImGui.Button('PASTE ROT',105,28) then self:run('Rotation pasted',function() return tools:paste('rotation') end) end
    ImGui.SameLine();if ImGui.Button('PASTE XFORM',115,28) then self:run('Transform pasted',function() return tools:paste('transform') end) end
    ImGui.SameLine();if ImGui.Button('RESET ROT',105,28) then self:run('Rotation reset',function() return tools:reset_rotation() end) end

    ImGui.Spacing()
    if ImGui.Button('MOVE TO PLAYER',145,30) then self:run('Moved to player',function() return tools:move_to_player(nil,nil,false) end) end
    ImGui.SameLine();if ImGui.Button('MOVE TO AIM',125,30) then self:run('Moved to aim',function() return tools:move_to_aim(nil,nil,self.scatter_distance) end) end
    ImGui.SameLine();if ImGui.Button('DROP TO GROUND',145,30) then self:run('Dropped to surface',function() return tools:drop_to_ground() end) end
    ImGui.SameLine();if ImGui.Button('PLAYER -> SELECTED',160,30) then self:run('Player teleported',function() return tools:teleport_player_to() end) end
end

function Tools:draw_targeting()
    local tools=self.app.ent_tools;local target=tools:get_target()
    Theme.section('Targeting / Look-at','adapted from entSpawner targeting')
    if target then Theme.good('TARGET  '..string.upper(target.kind)..' / '..(target.item.name or target.id)) else Theme.warning('NO TARGET STORED') end
    if ImGui.Button('SET TARGET = SELECTION',190,28) then self:run('Target stored',function() return tools:set_target() end) end
    ImGui.SameLine();if ImGui.Button('CLEAR TARGET',120,28) then self:run('Target cleared',function() return tools:clear_target() end) end
    if ImGui.Button('AIM SELECTION AT TARGET',205,30) then self:run('Aimed at target',function() return tools:aim_at_target() end) end
    ImGui.SameLine();if ImGui.Button('AIM AT PLAYER',135,30) then self:run('Aimed at player',function() return tools:aim_at_player() end) end
    ImGui.SameLine();if ImGui.Button('AIM AT CROSSHAIR',155,30) then self:run('Aimed at crosshair',function() return tools:aim_at_crosshair(nil,nil,self.scatter_distance) end) end
end

function Tools:draw_array_scatter()
    local app=self.app;local tools=app.ent_tools;local kind=app.selection.kind
    Theme.section('Duplicate / Pattern / Scatter','live transactional placement')
    if ImGui.Button('PLACE / AIM COPY + EDIT',205,30) then self:run('Placement preview started',function() return app.transform_session:start_placement({kind=kind,mode='aim',distance=self.scatter_distance}) end) end
    if kind=='object' then
        ImGui.SameLine();if ImGui.Button('MIRROR X + EDIT',135,30) then self:run('Mirror X preview started',function() return app.transform_session:start_mirror({axis='x'}) end) end
        ImGui.SameLine();if ImGui.Button('MIRROR Y + EDIT',135,30) then self:run('Mirror Y preview started',function() return app.transform_session:start_mirror({axis='y'}) end) end
    end

    ImGui.TextDisabled('Array selected object')
    self.array_count=select(1,ImGui.InputInt('Count##array',self.array_count,1,5))
    self.array_dx=select(1,ImGui.InputFloat('dX##array',self.array_dx,0.1,1,'%.2f'));ImGui.SameLine();self.array_dy=select(1,ImGui.InputFloat('dY##array',self.array_dy,0.1,1,'%.2f'))
    self.array_dz=select(1,ImGui.InputFloat('dZ##array',self.array_dz,0.1,1,'%.2f'));ImGui.SameLine();self.array_dyaw=select(1,ImGui.InputFloat('dYaw##array',self.array_dyaw,1,15,'%.1f'))
    if ImGui.Button('CREATE ARRAY + EDIT',175,30) then
        self:run('Array preview started',function()
            if app.selection.kind~='object' then return nil,'select an object first' end
            return app.transform_session:start_pattern({count=self.array_count,dx=self.array_dx,dy=self.array_dy,dz=self.array_dz,dyaw=self.array_dyaw,pattern_local_space=true})
        end)
    end

    ImGui.Separator();ImGui.TextDisabled('Scatter selected object/group or Project Asset around the crosshair')
    self.scatter_count=select(1,ImGui.InputInt('Scatter count',self.scatter_count,1,5))
    self.scatter_radius=select(1,ImGui.InputFloat('Scatter radius',self.scatter_radius,0.1,1,'%.2fm'))
    self.scatter_distance=select(1,ImGui.InputFloat('Aim distance',self.scatter_distance,1,5,'%.1fm'))
    self.scatter_seed=select(1,ImGui.InputInt('Deterministic seed',self.scatter_seed,1,100))
    self.scatter_random_yaw=select(1,ImGui.Checkbox('Random yaw',self.scatter_random_yaw));ImGui.SameLine();self.scatter_drop=select(1,ImGui.Checkbox('Ground each stamp',self.scatter_drop))
    if ImGui.Button('SCATTER + EDIT',170,32) then
        local settings=app.model.data.settings.ent_tools;settings.scatter_count=self.scatter_count;settings.scatter_radius=self.scatter_radius;settings.scatter_distance=self.scatter_distance;settings.scatter_seed=self.scatter_seed;settings.scatter_random_yaw=self.scatter_random_yaw;settings.scatter_drop=self.scatter_drop;app:mark_dirty()
        self:run('Scatter preview started',function()
            if kind~='object' and kind~='asset' then return nil,'select an object/group or Project Asset first' end
            return app.transform_session:start_scatter({count=self.scatter_count,radius=self.scatter_radius,distance=self.scatter_distance,seed=self.scatter_seed,random_yaw=self.scatter_random_yaw,drop_to_ground=self.scatter_drop})
        end)
    end
end

function Tools:draw_camera()
    Theme.section('Active Camera','camera-aware placement from entSpawner')
    local summary=self.app.game:camera_summary()
    if summary.ready then
        ImGui.Text(string.format('Camera %.2f, %.2f, %.2f  |  yaw %.1f',summary.transform.position.x,summary.transform.position.y,summary.transform.position.z,summary.transform.rotation.yaw or 0))
        if summary.fov then ImGui.SameLine();ImGui.TextDisabled(string.format('FOV %.1f',summary.fov)) end
    else ImGui.TextDisabled('Active camera transform unavailable; placement falls back to player view.') end
    if ImGui.Button('CAPTURE CAMERA NODE',185,30) then
        self:run('Camera node captured',function()
            local transform,err=self.app.game:capture_camera_transform();if not transform then return nil,err end
            return self.app.actions:create_camera({transform=transform,name='Camera View'})
        end)
    end
end

function Tools:draw_prop_validators()
    local app=self.app
    Theme.section('Prop Validators','bounds checks + live Static collision probes')
    ImGui.TextDisabled('All checks are read-only. Import asset bounds first for useful results.')
    if ImGui.Button('CHECK PROP OVERLAPS',185,30) then
        self.last_validation=self:run('Prop overlap scan',function()
            return app.prop_validators:clipcheck({})
        end)
    end
    local item=app.selection.kind=='object' and app.selection:resolve() or nil
    if item then
        ImGui.SameLine();if ImGui.Button('CHECK SELECTED FIT',175,30) then
            self.last_validation=self:run('Live support check',function()
                return app.prop_validators:fitcheck({object_ids={item.id},mode='live'})
            end)
        end
        ImGui.SameLine();if ImGui.Button('CHECK WALL FIT',145,30) then
            self.last_validation=self:run('Live wall check',function()
                return app.prop_validators:fitcheck({object_ids={item.id},mode='wall'})
            end)
        end
        if ImGui.Button('CHECK FIXTURES AROUND SELECTED',255,30) then
            self.last_validation=self:run('Live fixture check',function()
                return app.prop_validators:fixturecheck({object_ids={item.id}})
            end)
        end
    else
        Theme.muted('Select a placed object to run live fit and fixture checks.')
    end
    local result=self.last_validation
    if result then
        ImGui.Separator()
        ImGui.Text(string.format('%s  |  %d tested',result.validator or 'VALIDATION',tonumber(result.tested) or 0))
        if result.collision_count then
            if result.collision_count>0 then Theme.warning(string.format('%d overlapping prop pair(s)',result.collision_count))
            else Theme.good('No overlapping bounds found') end
        elseif result.results and result.results[1] then
            local row=result.results[1]
            if row.fixture_hits then
                if row.fixture_hits>0 then Theme.warning(string.format('%d Static fixture hit(s)',row.fixture_hits))
                else Theme.good('No Static fixture hits at sampled points') end
            else
                local hits=0;for _,v in ipairs(row.hits or {}) do if v.hit then hits=hits+1 end end
                ImGui.Text(string.format('%d of %d sampled rays hit Static collision',hits,#(row.hits or {})))
            end
        end
        if result.warning then Theme.muted(result.warning) end
    end
end

function Tools:draw_checkpoints()
    local cp=self.app.checkpoints;if not cp then return end
    Theme.section('Project Checkpoints','named snapshots · compare changes · undoable restore')
    self.checkpoint_name=select(1,ImGui.InputText('Checkpoint name',self.checkpoint_name or '',80))
    self.checkpoint_description=select(1,ImGui.InputText('Description##checkpoint',self.checkpoint_description or '',160))
    if ImGui.Button('SAVE CHECKPOINT',165,30) then
        local row,err=cp:create({name=self.checkpoint_name,description=self.checkpoint_description})
        if row then self.checkpoint_selected=row.id;self.checkpoint_a=self.checkpoint_a or row.id;self.checkpoint_b=row.id;self.restore_armed=false;self.notify('Checkpoint saved: '..row.name)
        else self.notify('Checkpoint failed: '..tostring(err)) end
    end
    local listing=cp:list().checkpoints
    ImGui.TextDisabled(string.format('%d checkpoint(s) · saved in data/checkpoint_*.json',#listing))
    for _,row in ipairs(listing) do
        if ImGui.Selectable(string.format('%s  ·  %d objects  ·  %s##checkpoint_%s',row.name,row.object_count or 0,row.created_at or '',row.id),self.checkpoint_selected==row.id) then
            self.checkpoint_selected=row.id;self.restore_armed=false
            if not self.checkpoint_a then self.checkpoint_a=row.id elseif not self.checkpoint_b then self.checkpoint_b=row.id end
        end
    end
    local function choose(label,key)
        local current=self[key] or '';local current_name=current
        for _,row in ipairs(listing) do if row.id==current then current_name=row.name end end
        if ImGui.BeginCombo(label,current_name) then
            for _,row in ipairs(listing) do if ImGui.Selectable(row.name..'##'..key..row.id,current==row.id) then self[key]=row.id;self.last_checkpoint_diff=nil;self.restore_armed=false end end
            ImGui.EndCombo()
        end
    end
    choose('Compare from##checkpoint','checkpoint_a');ImGui.SameLine();choose('Compare to##checkpoint','checkpoint_b')
    if ImGui.Button('COMPARE CHECKPOINTS',190,30) then
        local result,err=cp:diff(self.checkpoint_a,self.checkpoint_b)
        if result then self.last_checkpoint_diff=result else self.notify('Diff failed: '..tostring(err)) end
    end
    if self.last_checkpoint_diff then
        local row=self.last_checkpoint_diff.objects
        ImGui.Text(string.format('Objects: +%d  -%d  moved %d  changed %d',row.counts.added,row.counts.removed,row.counts.moved,row.counts.changed))
        for _,kind in ipairs({'added','removed','moved','changed'}) do for _,item in ipairs(row[kind]) do ImGui.TextDisabled(kind..': '..item.name..' ['..item.id..']') end end
        for _,kind in ipairs({'rooms','locations','premises','volumes','cameras','scenes','routes'}) do
            local counts=self.last_checkpoint_diff.collections[kind].counts
            if counts.added+counts.removed+counts.moved+counts.changed>0 then ImGui.TextDisabled(string.format('%s: +%d -%d ~%d',kind,counts.added,counts.removed,counts.changed)) end
        end
    end
    if self.checkpoint_selected then
        if ImGui.Button(self.restore_armed and 'CANCEL RESTORE' or 'RESTORE SELECTED CHECKPOINT',225,30) then self.restore_armed=not self.restore_armed end
        if self.restore_armed then
            Theme.warning('Restore replaces project data. Existing in-game spawned entities remain as they are.')
            if ImGui.Button('CONFIRM RESTORE (UNDOABLE)',230,30) then
                local result,err=cp:restore(self.checkpoint_selected)
                if result then self.restore_armed=false;self.notify('Checkpoint restored; use Undo to reverse') else self.notify('Restore failed: '..tostring(err)) end
            end
        end
    end
end

function Tools:draw()
    self:draw_camera();self:draw_transform();self:draw_targeting();self:draw_array_scatter();self:draw_prop_validators();self:draw_checkpoints()
end

return Tools
