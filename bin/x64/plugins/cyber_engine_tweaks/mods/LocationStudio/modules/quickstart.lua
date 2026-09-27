local Builder=require('modules/builder')

local QuickStart={}
QuickStart.__index=QuickStart

local OPPOSITE={north='south',south='north',east='west',west='east'}

local function room_count(model,premise_id)
    local n=0
    for _,room in ipairs(model.data.rooms or {}) do if room.premise_id==premise_id then n=n+1 end end
    return n
end

local function fit_door(room,wall,requested)
    local length=(wall=='north' or wall=='south') and room.size.width or room.size.depth
    return math.max(0.6,math.min(tonumber(requested) or 1.2,math.max(0.6,length-0.4)))
end

function QuickStart.new(app) return setmetatable({app=app},QuickStart) end

function QuickStart:preflight(args)
    args=args or {}
    local valid,err=Builder.validate_size({width=args.width or 5,depth=args.depth or 5,height=args.height or 3},args.wall_thickness)
    if not valid then return nil,err end
    if (self.app.model.data.settings.quickstart or {}).strict_runtime==false then return true end
    if not self.app.game:is_ready() then return nil,'Load a save and wait until V is available before building.' end
    local kit=self.app.builder and self.app.builder:room_kit() or nil
    for _,kind in ipairs({'wall','floor','ceiling'}) do
        if not kit or not kit.roles or not kit.roles[kind] or kit.roles[kind].path=='' then return nil,'Room kit has no '..kind..' Static Mesh. No room was added.' end
    end
    local status=self.app.runtime_shell and self.app.runtime_shell:status(true)
    if not status or not status.available then return nil,(status and status.reason or 'Room runtime backend is unavailable.')..' No room was added.' end
    return true
end

function QuickStart:_spawn_room_visible(room)
    local settings=self.app.model.data.settings.quickstart or {}
    local result,warning,detail=self.app.placement:spawn_room_shell(room.id)
    if not result then
        local message='Room authored but NOT visible in game: '..tostring(warning or 'runtime shell spawn failed')
        if self.app.logger then self.app.logger:error('quickstart:runtime','room_not_visible',{room_id=room.id,error=message}) end
        if settings.strict_runtime~=false then return nil,message,detail end
        return {spawned={},failed=detail and detail.failed or {}},message
    end
    if self.app.logger then self.app.logger:info('quickstart:runtime','room_runtime_submitted',{room_id=room.id,requested=#result.spawned,failed=#result.failed,visibility_verified=false}) end
    return result,warning
end


function QuickStart:next_room_name(premise_id)
    return 'Room '..tostring(room_count(self.app.model,premise_id)+1)
end

function QuickStart:ensure_premise(name)
    local premise=self.app.model:get_premise(self.app.selected_premise_id)
    if premise then return premise end
    local created,err=self.app.actions:create_premise_from_player(name or 'My Location','interior')
    if not created then return nil,err end
    return created
end

function QuickStart:create_room_here(args)
    args=args or {}
    local allowed,preflight_err=self:preflight(args);if not allowed then return nil,preflight_err end
    local premise,err=self:ensure_premise(args.location_name)
    if not premise then return nil,err end
    local transform
    if args.at_origin then
        transform=Builder.local_transform(premise.transform,args.x or 0,args.y or 0,args.z or 0,args.yaw or 0)
    else
        transform,err=self.app.game:capture_transform()
        if not transform then return nil,err end
    end
    local room
    room,err=self.app.builder:create_room({
        premise_id=premise.id,
        name=args.name or self:next_room_name(premise.id),
        kind=args.kind or 'room',
        width=args.width or 5,
        depth=args.depth or 5,
        height=args.height or premise.floor_height or 3,
        wall_thickness=args.wall_thickness,
        transform=transform,
        generate_shell=args.generate_shell~=false,
    })
    if not room then return nil,err end
    self.app.selection:set('room',room.id)
    self.app:mark_dirty()
    local runtime,runtime_warning=self:_spawn_room_visible(room)
    if not runtime then return nil,runtime_warning end
    if self.app.logger then self.app.logger:info('quickstart:create_room_here','created_submitted',{premise_id=premise.id,room_id=room.id,requested=#runtime.spawned}) end
    return {premise=premise,room=room,runtime=runtime},runtime_warning
end

function QuickStart:create_first_room(args)
    args=args or {}
    args.name=args.name or 'Room 1'
    local result,err=self:create_room_here(args)
    if not result then return nil,err end
    local ws=self.app.model.data.settings.workspace
    ws.panel='HOME';ws.beginner_mode=true;ws.v06_welcome_seen=true
    self.app:mark_dirty()
    return result
end

function QuickStart:add_adjacent_room(args)
    args=args or {}
    local source=self.app.model:get_room(args.source_room_id or self.app.selected_room_id)
    if not source then return nil,'select a room first' end
    local allowed,preflight_err=self:preflight(args);if not allowed then return nil,preflight_err end
    local premise=self.app.model:get_premise(source.premise_id)
    if not premise then return nil,'room premise not found' end
    local direction=args.direction or 'north'
    if not OPPOSITE[direction] then return nil,'direction must be north, south, east, or west' end

    local width=math.max(1.0,tonumber(args.width) or source.size.width)
    local depth=math.max(1.0,tonumber(args.depth) or source.size.depth)
    local height=math.max(1.0,tonumber(args.height) or source.size.height)
    local gap=tonumber(args.gap) or 0
    local dx,dy=0,0
    if direction=='north' then dy=(source.size.depth+depth)/2+gap
    elseif direction=='south' then dy=-((source.size.depth+depth)/2+gap)
    elseif direction=='east' then dx=(source.size.width+width)/2+gap
    else dx=-((source.size.width+width)/2+gap) end

    local transform=Builder.local_transform(source.transform,dx,dy,0,0)
    local room,err=self.app.builder:create_room({
        premise_id=premise.id,
        name=args.name or self:next_room_name(premise.id),
        kind=args.kind or 'room',
        width=width,depth=depth,height=height,
        transform=transform,
        generate_shell=args.generate_shell~=false,
    })
    if not room then return nil,err end

    local openings={}
    if args.auto_door~=false then
        local door_width=fit_door(source,direction,args.door_width)
        local first,first_err=self.app.builder:add_opening({room_id=source.id,kind='door',wall=direction,offset=0,width=door_width,height=math.min(2.2,source.size.height-0.1),sill=0})
        if not first then return nil,'room created, but source doorway failed: '..tostring(first_err) end
        local second,second_err=self.app.builder:add_opening({room_id=room.id,kind='door',wall=OPPOSITE[direction],offset=0,width=fit_door(room,OPPOSITE[direction],door_width),height=math.min(2.2,room.size.height-0.1),sill=0})
        if not second then return nil,'room created, but new-room doorway failed: '..tostring(second_err) end
        openings={first.opening,second.opening}
    end

    self.app.selection:set('room',room.id)
    self.app:mark_dirty()
    local source_runtime,source_warning=self:_spawn_room_visible(source)
    if not source_runtime then return nil,'New room authored, but source room runtime rebuild failed: '..tostring(source_warning) end
    local runtime,runtime_warning=self:_spawn_room_visible(room)
    if not runtime then return nil,runtime_warning end
    if self.app.logger then self.app.logger:info('quickstart:add_adjacent_room','created_submitted',{source_room_id=source.id,room_id=room.id,direction=direction,auto_door=args.auto_door~=false,requested=#runtime.spawned}) end
    return {premise=premise,source=source,room=room,openings=openings,direction=direction,runtime=runtime},runtime_warning
end

function QuickStart:create_prefab_here(kind,args)
    args=args or {}
    local allowed,preflight_err=self:preflight(args);if not allowed then return nil,preflight_err end
    local premise,err=self:ensure_premise(args.location_name)
    if not premise then return nil,err end
    local result
    result,err=self.app.builder:create_prefab({premise_id=premise.id,kind=kind})
    if not result then return nil,err end
    if result.rooms and result.rooms[1] then self.app.selection:set('room',result.rooms[1].id) else self.app.selection:set('premise',premise.id) end
    local ws=self.app.model.data.settings.workspace;ws.panel='HOME';ws.v06_welcome_seen=true
    self.app:mark_dirty()
    local runtime,runtime_warning=self.app.placement:spawn_all_shells(premise.id)
    if not runtime then
        local message='Layout authored but NOT visible in game: '..tostring(runtime_warning)
        if self.app.logger then self.app.logger:error('quickstart:create_prefab_here','runtime_failed',{premise_id=premise.id,kind=kind,error=message}) end
        if (self.app.model.data.settings.quickstart or {}).strict_runtime~=false then return nil,message end
    end
    if self.app.logger then self.app.logger:info('quickstart:create_prefab_here','created_submitted',{premise_id=premise.id,kind=kind,rooms=result.rooms and #result.rooms or 0,requested=runtime and runtime.spawned or 0}) end
    return {premise=premise,prefab=result,runtime=runtime},runtime_warning
end

return QuickStart
