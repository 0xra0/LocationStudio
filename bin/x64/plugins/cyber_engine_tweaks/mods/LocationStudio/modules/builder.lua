local Util = require('modules/util')
local RoomKits = require('modules/room_kits')

local Builder = {}
Builder.__index = Builder

local function radians(deg) return (tonumber(deg) or 0) * math.pi / 180.0 end

local function local_transform(base, dx, dy, dz, dyaw)
    base = base or {position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}
    local yaw = radians((base.rotation or {}).yaw)
    local c, s = math.cos(yaw), math.sin(yaw)
    return {
        position={
            x=(base.position.x or 0) + dx*c - dy*s,
            y=(base.position.y or 0) + dx*s + dy*c,
            z=(base.position.z or 0) + dz,
            w=1,
        },
        rotation={
            roll=(base.rotation or {}).roll or 0,
            pitch=(base.rotation or {}).pitch or 0,
            yaw=((base.rotation or {}).yaw or 0) + (dyaw or 0),
        },
    }
end

function Builder.new(app) return setmetatable({app=app},Builder) end
function Builder.local_transform(base,dx,dy,dz,dyaw) return local_transform(base,dx,dy,dz,dyaw) end

function Builder.validate_size(size,thickness)
    thickness=tonumber(thickness) or 0.15
    if thickness~=thickness or thickness<0.01 or thickness>2 then return nil,'Wall thickness must be between 0.01 and 2 metres.' end
    for _,key in ipairs({'width','depth','height'}) do
        local value=tonumber(size and size[key])
        if not value or value~=value or value<0.5 or value>100 then return nil,key..' must be between 0.5 and 100 metres.' end
        if value<=thickness*2 then return nil,key..' must be greater than twice the wall thickness.' end
    end
    return true
end

local function wall_axis(wall)
    if wall=='north' or wall=='south' then return 'x' end
    return 'y'
end

local function opening_intervals(room,wall)
    local length = wall_axis(wall)=='x' and room.size.width or room.size.depth
    local half = length/2
    local openings = {}
    for _,o in ipairs(room.openings or {}) do
        if o.wall==wall then
            local left=math.max(-half,o.offset-o.width/2)
            local right=math.min(half,o.offset+o.width/2)
            if right>left then table.insert(openings,{left=left,right=right,item=o}) end
        end
    end
    table.sort(openings,function(a,b) return a.left<b.left end)
    return openings,-half,half
end

local function solid_wall_spans(room,wall)
    local openings,from,to=opening_intervals(room,wall)
    local spans={};local cursor=from
    for _,o in ipairs(openings) do
        if o.left>cursor then table.insert(spans,{from=cursor,to=o.left}) end
        cursor=math.max(cursor,o.right)
    end
    if cursor<to then table.insert(spans,{from=cursor,to=to}) end
    return spans
end

local function piece_transform(room,x,y,z,yaw,role)
    role=role or {};local angle=radians(yaw or 0);local c,s=math.cos(angle),math.sin(angle)
    local ox=(role.offset_x or 0)*c-(role.offset_y or 0)*s
    local oy=(role.offset_x or 0)*s+(role.offset_y or 0)*c
    return local_transform(room.transform,x+ox,y+oy,z+(role.offset_z or 0),(yaw or 0)+(role.yaw or 0))
end

local function wall_geometry(room,wall,along)
    if wall=='north' then return along,room.size.depth/2,180,false end
    if wall=='south' then return along,-room.size.depth/2,0,true end
    if wall=='east' then return room.size.width/2,along,90,true end
    return -room.size.width/2,along,-90,false
end

function Builder:_queue_surface(queue,room,name,kind,layer,transform,size,metadata)
    table.insert(queue,{
        premise_id=room.premise_id, room_id=room.id, name=room.name..' / '..name, kind=kind,
        template='', layer=layer or room.layer or 'shell', transform=transform, size=size,
        metadata=metadata or {},
    })
end

function Builder:room_kit()
    local settings=self.app.model.data.settings
    settings.room_kit=RoomKits.normalize(settings.room_kit)
    return settings.room_kit
end

function Builder:room_kit_presets() return RoomKits.presets() end

function Builder:set_room_kit_preset(id)
    local kit,err=RoomKits.apply_preset(self:room_kit(),id);if not kit then return nil,err end
    self.app.model.data.settings.room_kit=kit;self.app:mark_dirty()
    return kit
end

function Builder:assign_room_kit_role(role,asset_id)
    local asset=self.app.model:get_asset(asset_id);if not asset then return nil,'Select an asset from MY ASSETS first.' end
    local value,err=RoomKits.assign_asset(self:room_kit(),role,asset);if not value then return nil,err end
    self.app:mark_dirty();return value
end

function Builder:update_room_kit_role(role,patch)
    local kit=self:room_kit();local value=kit.roles[role];if not value then return nil,'unknown room-kit role' end
    for key,input in pairs(patch or {}) do
        if key=='path' then value.path=Util.trim(input);value.world_builder=nil;value.asset_id=nil;value.asset_name=nil
        elseif ({native_x=true,native_y=true,native_z=true})[key] then value[key]=math.max(0.01,tonumber(input) or value[key])
        elseif ({yaw=true,offset_x=true,offset_y=true,offset_z=true})[key] then value[key]=tonumber(input) or value[key] end
    end
    kit.preset='custom';self.app:mark_dirty();return value
end

function Builder:construction_objects(premise_id,room_id,role,include_collision)
    local values={};role=role or 'all'
    for _,object in ipairs(self.app.model.data.objects or {}) do
        local metadata=object.metadata or {}
        local matches=metadata.room_kit==true and (not premise_id or object.premise_id==premise_id) and (not room_id or object.room_id==room_id)
        if matches and (include_collision==true or metadata.room_collision~=true) then
            local object_role=metadata.room_collision and 'collision' or (metadata.role or object.kind)
            if role=='all' or role==object_role then table.insert(values,object) end
        end
    end
    return values
end

function Builder:detach_shell_object(object_id)
    local object=self.app.model:get_object(object_id);if not object then return nil,'object not found' end
    local metadata=object.metadata or {}
    if metadata.room_kit~=true then return nil,'object is not a generated room-kit piece' end
    if object.locked then return nil,'object is locked; unlock it before detaching' end
    self.app.model:snapshot()
    local room=self.app.model:get_room(object.room_id)
    if room then
        local kept={};for _,id in ipairs(room.shell_object_ids or {}) do if id~=object.id then table.insert(kept,id) end end
        room.shell_object_ids=kept;room.updated_at=Util.now_iso()
    end
    metadata.generated=false;metadata.room_kit=false;metadata.detached_from_room=true;metadata.detached_at=Util.now_iso()
    object.metadata=metadata;object.locked=false;object.layer='decoration';object.updated_at=Util.now_iso()
    self.app.model:touch();self.app:mark_dirty()
    if self.app.logger then self.app.logger:info('builder:construction','piece_detached',{id=object.id,room_id=object.room_id,role=metadata.role}) end
    return object
end

function Builder:replace_shell_object_asset(object_id,asset_id)
    local object=self.app.model:get_object(object_id);if not object then return nil,'object not found' end
    if object.locked then return nil,'object is locked; unlock it before replacing its asset' end
    if not (object.metadata and object.metadata.room_kit==true) then return nil,'object is not a generated room-kit piece' end
    if object.metadata.room_collision==true then return nil,'collision pieces cannot be replaced with a mesh asset' end
    local asset=self.app.model:get_asset(asset_id);if not asset then return nil,'Choose a Static Mesh in the asset browser first.' end
    local wb=asset.metadata and asset.metadata.world_builder
    if type(wb)~='table' or wb.definition_key~='mesh_static' then return nil,'The last selected asset is not an imported Static Mesh.' end
    local path=Util.trim(wb.resource_path or asset.template or (((wb.entry or {}).data or {}).spawnData) or '')
    if path=='' then return nil,'The selected mesh has no game resource path.' end
    self.app.model:snapshot()
    object.metadata.world_builder=Util.deepcopy(wb)
    object.metadata.world_builder.resource_path=path
    object.metadata.world_builder.entry=type(object.metadata.world_builder.entry)=='table' and object.metadata.world_builder.entry or {}
    object.metadata.world_builder.entry.name=path
    object.metadata.world_builder.entry.fileName=object.metadata.world_builder.resource_name or asset.name
    object.metadata.world_builder.entry.data=type(object.metadata.world_builder.entry.data)=='table' and object.metadata.world_builder.entry.data or {}
    object.metadata.world_builder.entry.data.spawnData=path
    object.metadata.replacement_asset_id=asset.id;object.metadata.replacement_asset_name=asset.name
    object.template=path;object.appearance=asset.appearance or '';object.updated_at=Util.now_iso()
    self.app.model:mark_asset_used(asset.id);self.app.model:touch();self.app:mark_dirty()
    local warning
    if self.app.placement:is_tracked(object) then
        local _,err=self.app.placement:refresh(object);if err then warning='Asset was saved, but live refresh failed: '..tostring(err) end
    end
    if self.app.logger then self.app.logger:info('builder:construction','piece_asset_replaced',{id=object.id,asset_id=asset.id,path=path,warning=warning}) end
    return object,warning
end

function Builder:set_construction_state(premise_id,room_id,role,patch)
    patch=patch or {};if patch.enabled==nil and patch.locked==nil then return nil,'Specify enabled and/or locked state.' end
    local objects=self:construction_objects(premise_id,room_id,role,patch.include_collision==true)
    if #objects==0 then return nil,'No matching construction pieces were found.' end
    self.app.model:snapshot();local changed,spawned,despawned,failed=0,0,0,{}
    for _,object in ipairs(objects) do
        local touched=false
        if patch.locked~=nil and object.locked~=(patch.locked==true) then
            object.locked=patch.locked==true;touched=true
            if object.locked and self.app.runtime_shell then self.app.runtime_shell:unfocus(object) end
        end
        if patch.enabled~=nil then
            local enabled=patch.enabled==true
            if object.enabled~=enabled or object.visible~=enabled then object.enabled=enabled;object.visible=enabled;touched=true end
            if not enabled and self.app.placement:is_tracked(object) then
                local ok,err=self.app.placement:despawn(object);if ok then despawned=despawned+1 else table.insert(failed,{id=object.id,error=err}) end
            elseif enabled and self.app.model.data.settings.workspace.live_preview and not self.app.placement:is_tracked(object) then
                local id,err=self.app.placement:spawn(object);if id then spawned=spawned+1 else table.insert(failed,{id=object.id,error=err}) end
            end
        end
        if touched then object.updated_at=Util.now_iso();changed=changed+1 end
    end
    self.app.model:touch();self.app:mark_dirty()
    local result={matched=#objects,changed=changed,spawned=spawned,despawned=despawned,failed=failed,role=role or 'all'}
    if self.app.logger then self.app.logger:info('builder:construction','state_changed',{premise_id=premise_id,room_id=room_id,role=result.role,matched=#objects,changed=changed,failed=#failed}) end
    return result,#failed>0 and (tostring(#failed)..' runtime operation(s) failed; see DEBUG LOG.') or nil
end

function Builder:clear_room_shell(room_id)
    local room=self.app.model:get_room(room_id); if not room then return false,'room not found' end
    local ids={}; for _,id in ipairs(room.shell_object_ids or {}) do ids[id]=true end
    -- Never erase the only cleanup reference to an entity that failed removal.
    for _,object in ipairs(self.app.model.data.objects) do
        if ids[object.id] then
            local ok,err=self.app.placement:despawn(object)
            if not ok then return false,'Cannot replace room shell: '..tostring(err) end
        end
    end
    self.app.model:snapshot()
    for i=#self.app.model.data.objects,1,-1 do
        local object=self.app.model.data.objects[i]
        if ids[object.id] then table.remove(self.app.model.data.objects,i) end
    end
    room.shell_object_ids={}; room.updated_at=Util.now_iso(); self.app.model:touch(); return true
end

function Builder:rebuild_room_shell(room_id)
    local room=self.app.model:get_room(room_id); if not room then return nil,'room not found' end
    if self:is_generated(room_id) then return nil,'this room is parametric; regenerate it with the room generator instead of rebuilding a kit shell' end
    local valid,validation_err=Builder.validate_size(room.size,room.wall_thickness)
    if not valid then return nil,validation_err end
    local kit=self:room_kit();local roles=kit.roles
    for _,role in ipairs({'floor','ceiling','wall'}) do if Util.trim((roles[role] or {}).path)=='' then return nil,'Room kit has no '..role..' mesh. Choose a preset or assign a Static Mesh.' end end
    local w,d,h=room.size.width,room.size.depth,room.size.height
    local floor_tiles=math.ceil(w/roles.floor.native_x)*math.ceil(d/roles.floor.native_y)
    local ceiling_tiles=math.ceil(w/roles.ceiling.native_x)*math.ceil(d/roles.ceiling.native_y)
    local wall_tiles=2*math.ceil(w/roles.wall.native_x)+2*math.ceil(d/roles.wall.native_x)
    if floor_tiles+ceiling_tiles+wall_tiles>1200 then return nil,'This room would create more than 1200 kit pieces. Use larger source meshes or a smaller room.' end
    local cleared,clear_err=self:clear_room_shell(room_id)
    if not cleared then return nil,clear_err end
    local queue={};local kit_name=kit.preset

    local function add_mesh(name,kind,role,x,y,z,yaw,scale,extra)
        local metadata,err=RoomKits.mesh_metadata(role,scale,kit_name);if not metadata then return nil,err end
        for key,value in pairs(extra or {}) do metadata[key]=value end
        self:_queue_surface(queue,room,name,kind,'shell',piece_transform(room,x,y,z,yaw,role),scale,metadata)
        return true
    end

    local function tile_plane(role,kind,z)
        local ix=0;local x=-w/2
        while x<w/2-0.001 do
            ix=ix+1;local piece_x=math.min(role.native_x,w/2-x);local iy=0;local y=-d/2
            while y<d/2-0.001 do
                iy=iy+1;local piece_y=math.min(role.native_y,d/2-y)
                local scale={x=piece_x/role.native_x,y=piece_y/role.native_y,z=1}
                add_mesh(string.format('%s %02d-%02d',kind,ix,iy),kind,role,x,y,z,0,scale,{role=kind,tile_x=ix,tile_y=iy,dimensions={x=piece_x,y=piece_y,z=0}})
                y=y+piece_y
            end
            x=x+piece_x
        end
    end

    tile_plane(roles.floor,'floor',0)
    tile_plane(roles.ceiling,'ceiling',h)

    local function tile_wall_span(wall,span,index)
        local role=roles.wall;local length=span.to-span.from;local consumed=0;local tile=0
        while consumed<length-0.001 do
            tile=tile+1;local piece=math.min(role.native_x,length-consumed)
            local _,_,_,positive=wall_geometry(room,wall,0)
            local along=positive and (span.from+consumed) or (span.to-consumed)
            local x,y,yaw=wall_geometry(room,wall,along)
            local scale={x=piece/role.native_x,y=1,z=h/role.native_z}
            add_mesh(string.format('%s wall %02d-%02d',wall,index,tile),'wall',role,x,y,0,yaw,scale,{role='wall',wall=wall,segment='solid',dimensions={x=piece,y=kit.wall_thickness,z=h}})
            consumed=consumed+piece
        end
    end

    for _,wall in ipairs({'north','south','east','west'}) do
        for index,span in ipairs(solid_wall_spans(room,wall)) do tile_wall_span(wall,span,index) end
        local openings=opening_intervals(room,wall)
        for index,item in ipairs(openings) do
            local opening=item.item;local role=roles[opening.kind]
            if role and Util.trim(role.path)~='' then
                local _,_,_,positive=wall_geometry(room,wall,0)
                local along=positive and item.left or item.right
                local x,y,yaw=wall_geometry(room,wall,along)
                local width=item.right-item.left;local scale={x=width/role.native_x,y=1,z=h/role.native_z}
                add_mesh(string.format('%s %s %02d',wall,opening.kind,index),opening.kind,role,x,y,0,yaw,scale,{role=opening.kind,wall=wall,opening_id=opening.id,dimensions={x=width,y=kit.wall_thickness,z=h}})
            end
        end
    end

    if kit.collision then
        local floor_scale={x=w/2,y=d/2,z=kit.floor_thickness/2}
        self:_queue_surface(queue,room,'Floor Collision','collision','shell',local_transform(room.transform,0,0,-kit.floor_thickness/2,0),floor_scale,RoomKits.collision_metadata(floor_scale,'floor'))
        for _,wall in ipairs({'north','south','east','west'}) do
            local spans=solid_wall_spans(room,wall)
            if wall then
                local openings=opening_intervals(room,wall)
                for _,item in ipairs(openings) do if item.item.kind=='window' then table.insert(spans,{from=item.left,to=item.right}) end end
            end
            for index,span in ipairs(spans) do
                local center=(span.from+span.to)/2;local length=span.to-span.from
                local x,y,yaw=wall_geometry(room,wall,center)
                local scale={x=length/2,y=kit.wall_thickness/2,z=h/2}
                local metadata=RoomKits.collision_metadata(scale,'wall');metadata.wall=wall;metadata.segment=index
                self:_queue_surface(queue,room,string.format('%s Collision %02d',wall,index),'collision','shell',local_transform(room.transform,x,y,h/2,yaw),scale,metadata)
            end
        end
    end

    local objects=self.app.model:add_objects(queue)
    for _,object in ipairs(objects) do table.insert(room.shell_object_ids,object.id) end
    room.updated_at=Util.now_iso(); self.app:mark_dirty()
    if self.app.logger then self.app.logger:info('builder:room_kit','shell_rebuilt',{room_id=room.id,kit=kit_name,objects=#room.shell_object_ids,collision=kit.collision}) end
    return {room=room,object_count=#room.shell_object_ids,object_ids=Util.deepcopy(room.shell_object_ids)}
end

function Builder:is_generated(room_id)
    for _,rec in ipairs(self.app.model.data.generated_rooms or {}) do if rec.id==room_id then return true end end
    return false
end

function Builder:rebuild_premise_shells(premise_id)
    local rooms,objects=0,0
    for _,room in ipairs(self.app.model.data.rooms or {}) do
        if (not premise_id or room.premise_id==premise_id) and not self:is_generated(room.id) then
            local result,err=self:rebuild_room_shell(room.id);if not result then return nil,err end
            rooms=rooms+1;objects=objects+result.object_count
        end
    end
    return {rooms=rooms,objects=objects}
end

function Builder:migrate_legacy_room_shells()
    local migrated,failed=0,{}
    for _,room in ipairs(self.app.model.data.rooms or {}) do
        local legacy=false
        for _,id in ipairs(room.shell_object_ids or {}) do
            local object=self.app.model:get_object(id);local metadata=object and object.metadata or {}
            if object and metadata.generated==true and type(metadata.world_builder)~='table' then legacy=true;break end
        end
        if legacy then
            local result,err=self:rebuild_room_shell(room.id)
            if result then migrated=migrated+1 else table.insert(failed,{room_id=room.id,error=err}) end
        end
    end
    if self.app.logger then self.app.logger:info('builder:room_kit','legacy_migration',{migrated=migrated,failed=#failed}) end
    return {migrated=migrated,failed=failed}
end

function Builder:create_room(args)
    args=args or {}; local premise=self.app.model:get_premise(args.premise_id)
    if not premise then return nil,'premise not found' end
    local valid,validation_err=Builder.validate_size({width=args.width or 4,depth=args.depth or 4,height=args.height or premise.floor_height},args.wall_thickness)
    if not valid then return nil,validation_err end
    local transform=args.transform or local_transform(premise.transform,args.x or 0,args.y or 0,(args.z or 0)+(args.level or 0)*premise.floor_height,args.yaw or 0)
    local room=self.app.model:add_room({
        premise_id=premise.id,name=args.name,kind=args.kind,size={width=args.width,depth=args.depth,height=args.height or premise.floor_height},
        wall_thickness=args.wall_thickness,level=args.level,layer=args.layer,transform=transform,tags=args.tags,notes=args.notes,room_type=args.room_type,
    })
    if args.generate_shell~=false then self:rebuild_room_shell(room.id) end
    self.app:mark_dirty(); return room
end

function Builder:create_corridor(args)
    args=args or {}; args.kind='corridor'; args.width=args.width or 2.0; args.depth=args.length or args.depth or 6.0
    return self:create_room(args)
end

function Builder:add_opening(args)
    local opening,err=self.app.model:add_opening(args.room_id,{
        kind=args.kind,wall=args.wall,offset=args.offset,width=args.width,height=args.height,sill=args.sill,template=args.template,
    })
    if not opening then return nil,err end
    local result,rebuild_err=self:rebuild_room_shell(args.room_id); if not result then return nil,rebuild_err end
    return {opening=opening,shell=result}
end

function Builder:place_object(args)
    args=args or {}; local premise=self.app.model:get_premise(args.premise_id); if not premise then return nil,'premise not found' end
    local base=premise.transform; if args.room_id then local room=self.app.model:get_room(args.room_id); if not room then return nil,'room not found' end; base=room.transform end
    local transform=args.transform or local_transform(base,args.x or 0,args.y or 0,args.z or 0,args.yaw or 0)
    local metadata=type(args.metadata)=='table' and Util.deepcopy(args.metadata) or {}
    metadata.source=args.source or metadata.source or 'builder'
    local obj=self.app.model:add_object({
        premise_id=premise.id,room_id=args.room_id,name=args.name,kind=args.kind,template=args.template,appearance=args.appearance,
        layer=args.layer,transform=transform,size=args.size,properties=args.properties,metadata=metadata,
    })
    self.app:mark_dirty(); return obj
end

function Builder:array_object(id,count,dx,dy,dz,dyaw)
    local source=self.app.model:get_object(id); if not source then return nil,'object not found' end
    if not self.app.transform_session then return nil,'transactional pattern editor is unavailable' end
    local started,err=self.app.transform_session:start_pattern({ids={id},active_id=id,count=count,dx=dx,dy=dy,dz=dz,dyaw=dyaw,pattern_local_space=true,pivot_mode='active'})
    if not started then return nil,err end
    local committed,warning=self.app.transform_session:commit();if not committed then return nil,warning end
    local made={};for _,created_id in ipairs(committed.created_ids or {}) do local object=self.app.model:get_object(created_id);if object then table.insert(made,object) end end
    return made,warning
end

function Builder:mirror_object(id,axis)
    local source=self.app.model:get_object(id); if not source then return nil,'object not found' end
    if not self.app.transform_session then return nil,'transactional mirror editor is unavailable' end
    local started,err=self.app.transform_session:start_mirror({ids={id},active_id=id,axis=axis,pivot_mode='active'})
    if not started then return nil,err end
    local committed,warning=self.app.transform_session:commit();if not committed then return nil,warning end
    local object=committed.created_ids and self.app.model:get_object(committed.created_ids[1]) or nil
    return object,warning
end

function Builder:create_prefab(args)
    args=args or {}; local kind=args.kind or 'clinic'; local premise=self.app.model:get_premise(args.premise_id)
    if not premise then return nil,'premise not found' end
    local rooms={}
    if kind=='clinic' then
        table.insert(rooms,(self:create_room({premise_id=premise.id,name='Reception',width=6,depth=5,height=3,x=0,y=0})))
        table.insert(rooms,(self:create_corridor({premise_id=premise.id,name='Clinic Corridor',width=2,length=4,height=3,x=0,y=4.5})))
        table.insert(rooms,(self:create_room({premise_id=premise.id,name='Treatment Room',width=6,depth=5,height=3,x=0,y=9})))
        self:add_opening({room_id=rooms[1].id,kind='door',wall='north',offset=0,width=1.4,height=2.2})
        self:add_opening({room_id=rooms[2].id,kind='door',wall='south',offset=0,width=1.4,height=2.2})
        self:add_opening({room_id=rooms[2].id,kind='door',wall='north',offset=0,width=1.4,height=2.2})
        self:add_opening({room_id=rooms[3].id,kind='door',wall='south',offset=0,width=1.4,height=2.2})
    elseif kind=='apartment' then
        table.insert(rooms,(self:create_room({premise_id=premise.id,name='Living Room',width=7,depth=5,height=3,x=0,y=0})))
        table.insert(rooms,(self:create_room({premise_id=premise.id,name='Bedroom',width=4,depth=4,height=3,x=5.5,y=0})))
        table.insert(rooms,(self:create_room({premise_id=premise.id,name='Bathroom',width=3,depth=2.5,height=3,x=5.5,y=3.25})))
    elseif kind=='warehouse' then
        table.insert(rooms,(self:create_room({premise_id=premise.id,name='Warehouse Bay',width=16,depth=24,height=7,x=0,y=0})))
        table.insert(rooms,(self:create_room({premise_id=premise.id,name='Office',width=5,depth=4,height=3,x=-5,y=-8})))
    else return nil,'unknown prefab: '..tostring(kind) end
    return {kind=kind,premise_id=premise.id,rooms=rooms}
end

return Builder
