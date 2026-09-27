local Util=require('modules/util')
local Builder=require('modules/builder')

local Authoring={}
Authoring.__index=Authoring

function Authoring.new(app) return setmetatable({app=app},Authoring) end

local function base_for(app,premise_id,room_id)
    if room_id then local room=app.model:get_room(room_id);if room then return room.transform end end
    local premise=app.model:get_premise(premise_id);return premise and premise.transform or nil
end

local function resolve_item(model,kind,id)
    if kind=='object' then return model:get_object(id)
    elseif kind=='room' then return model:get_room(id)
    elseif kind=='volume' then return model:get_volume(id)
    elseif kind=='cover_node' then return model:get_cover_node(id)
    elseif kind=='camera' then return model:get_camera(id)
    elseif kind=='location' then return model:get_location(id)
    elseif kind=='premise' then return model:get_premise(id) end
end

local function refresh_objects(app,objects)
    local failed={};local refreshed=0
    for _,object in ipairs(objects or {}) do
        if app.placement:is_tracked(object) then
            local id,err
            if object.metadata and type(object.metadata.world_builder)=='table' then id,err=app.runtime_shell:update_object(object)
            else id,err=app.placement:refresh(object) end
            if id then refreshed=refreshed+1 else table.insert(failed,{id=object.id,error=tostring(err)}) end
        end
    end
    return refreshed,failed
end

local function object_group(model,ids)
    if type(ids)~='table' or #ids==0 then return nil,'select at least one object' end
    local objects,seen={},{}
    for _,id in ipairs(ids) do
        if not seen[id] then
            local object=model:get_object(id);if not object then return nil,'object not found: '..tostring(id) end
            if object.locked then return nil,'object '..tostring(object.name or id)..' is locked' end
            seen[id]=true;table.insert(objects,object)
        end
    end
    return objects
end

local function rotate_point(position,origin,dyaw)
    local dx=(position.x or 0)-(origin.x or 0);local dy=(position.y or 0)-(origin.y or 0)
    local rx,ry=Util.rotate_xy(dx,dy,dyaw)
    return {x=(origin.x or 0)+rx,y=(origin.y or 0)+ry,z=position.z or 0,w=position.w or 1}
end

local function transform_point(position,origin,dx,dy,dz,dyaw)
    local p=rotate_point(position,origin,dyaw)
    p.x=p.x+dx;p.y=p.y+dy;p.z=p.z+dz;return p
end

local function apply_child_delta(item,origin,dx,dy,dz,dyaw)
    if not item or not item.transform then return end
    item.transform.position=transform_point(item.transform.position,origin,dx,dy,dz,dyaw)
    item.transform.rotation=item.transform.rotation or {roll=0,pitch=0,yaw=0}
    item.transform.rotation.yaw=(item.transform.rotation.yaw or 0)+dyaw
    if item.look_at and item.look_at.x~=nil then
        local moved=transform_point(item.look_at,origin,dx,dy,dz,dyaw)
        moved.location_id=item.look_at.location_id;item.look_at=moved
    end
    item.updated_at=Util.now_iso()
end

function Authoring:_cascade_delta(kind,id,origin,dx,dy,dz,dyaw)
    local model=self.app.model
    if kind=='premise' then
        for _,room in ipairs(model.data.rooms) do if room.premise_id==id then apply_child_delta(room,origin,dx,dy,dz,dyaw) end end
        for _,object in ipairs(model.data.objects) do if object.premise_id==id then apply_child_delta(object,origin,dx,dy,dz,dyaw) end end
        for _,volume in ipairs(model.data.volumes) do if volume.premise_id==id then apply_child_delta(volume,origin,dx,dy,dz,dyaw) end end
        for _,camera in ipairs(model.data.cameras) do if camera.premise_id==id then apply_child_delta(camera,origin,dx,dy,dz,dyaw) end end
    elseif kind=='room' then
        for _,object in ipairs(model.data.objects) do if object.room_id==id then apply_child_delta(object,origin,dx,dy,dz,dyaw) end end
        for _,volume in ipairs(model.data.volumes) do if volume.room_id==id then apply_child_delta(volume,origin,dx,dy,dz,dyaw) end end
        for _,camera in ipairs(model.data.cameras) do if camera.room_id==id then apply_child_delta(camera,origin,dx,dy,dz,dyaw) end end
    end
end

function Authoring:set_transform(kind,id,transform,cascade,allow_locked)
    local item=resolve_item(self.app.model,kind,id);if not item then return nil,'item not found' end
    if kind=='object' and item.locked and allow_locked~=true then return nil,'object is locked; unlock it before moving it' end
    if not item.transform then return nil,'item has no transform' end
    if type(transform)~='table' or type(transform.position)~='table' or type(transform.rotation)~='table' then return nil,'invalid transform' end
    local old=Util.deepcopy(item.transform);local old_pos=old.position;local old_yaw=tonumber(old.rotation.yaw) or 0
    local new_pos=transform.position;local new_yaw=tonumber(transform.rotation.yaw) or 0
    local dx=(tonumber(new_pos.x) or 0)-(tonumber(old_pos.x) or 0)
    local dy=(tonumber(new_pos.y) or 0)-(tonumber(old_pos.y) or 0)
    local dz=(tonumber(new_pos.z) or 0)-(tonumber(old_pos.z) or 0)
    local dyaw=new_yaw-old_yaw
    self.app.model:snapshot()
    item.transform=Util.deepcopy(transform);item.transform.position.w=item.transform.position.w or 1
    item.updated_at=Util.now_iso()
    if cascade~=false and (kind=='premise' or kind=='room') then self:_cascade_delta(kind,id,old_pos,dx,dy,dz,dyaw) end
    self.app.model:touch();self.app:mark_dirty();return item
end

function Authoring:create_volume(args)
    args=args or {};local base=base_for(self.app,args.premise_id,args.room_id)
    if not base then return nil,'premise or room not found' end
    local transform=args.transform or Builder.local_transform(base,args.x or 0,args.y or 0,args.z or 0,args.yaw or 0)
    local item=self.app.model:add_volume({
        premise_id=args.premise_id,room_id=args.room_id,name=args.name,purpose=args.purpose,shape=args.shape,
        transform=transform,size={x=args.width or args.size_x,y=args.depth or args.size_y,z=args.size_z or args.height},
        radius=args.radius,height=args.height or args.size_z,layer=args.layer,tags=args.tags,notes=args.notes,metadata={source=args.source or 'authoring'},
    })
    if self.app.selection then self.app.selection:set('volume',item.id) else self.app.selected_volume_id=item.id end;self.app:mark_dirty();return item
end

function Authoring:create_camera(args)
    args=args or {};local base=base_for(self.app,args.premise_id,args.room_id)
    if not base then return nil,'premise or room not found' end
    local transform=args.transform or Builder.local_transform(base,args.x or 0,args.y or 0,args.z or 1.7,args.yaw or 0)
    local look=args.look_at
    if not look and args.look_at_location_id then
        local location=self.app.model:get_location(args.look_at_location_id);if not location then return nil,'look-at location not found' end
        look=Util.deepcopy(location.transform.position);look.location_id=location.id
    end
    look=look or Builder.local_transform(base,args.look_x or 2,args.look_y or 0,args.look_z or 1.4,0).position
    if args.keep_rotation~=true then transform.rotation=Util.look_at_rotation(transform.position,look) end
    local camera=self.app.model:add_camera({
        premise_id=args.premise_id,room_id=args.room_id,name=args.name,kind=args.kind,transform=transform,
        look_at=look,fov=args.fov,duration=args.duration,layer=args.layer,tags=args.tags,notes=args.notes,
    })
    if self.app.selection then self.app.selection:set('camera',camera.id) else self.app.selected_camera_id=camera.id end;self.app:mark_dirty();return camera
end

function Authoring:set_camera_look_at(camera_id,target)
    local camera=self.app.model:get_camera(camera_id);if not camera then return nil,'camera not found' end
    local look=target
    if target and target.location_id then
        local location=self.app.model:get_location(target.location_id);if not location then return nil,'look-at location not found' end
        look=Util.deepcopy(location.transform.position);look.location_id=location.id
    end
    if not look then return nil,'look-at target required' end
    local transform=Util.deepcopy(camera.transform);transform.rotation=Util.look_at_rotation(transform.position,look)
    local updated=self.app.model:update_camera(camera_id,{look_at=look,transform=transform});self.app:mark_dirty();return updated
end

function Authoring:preview_camera(camera_id)
    local camera=self.app.model:get_camera(camera_id);if not camera then return nil,'camera not found' end
    local ok,err=self.app.game:teleport(camera.transform);if not ok then return nil,err end
    return {previewed=true,id=camera.id,name=camera.name,fov=camera.fov}
end

function Authoring:snap_item(kind,id,grid,angle)
    local item=resolve_item(self.app.model,kind,id);if not item then return nil,'item not found' end
    local snapped=Util.snap_transform(item.transform,grid or self.app.model.data.settings.snapping.grid,angle or self.app.model.data.settings.snapping.angle)
    local updated,err=self:set_transform(kind,id,snapped,true);if not updated then return nil,err end
    if kind=='camera' and item.look_at then item.transform.rotation=Util.look_at_rotation(item.transform.position,item.look_at) end
    return item
end

function Authoring:batch_transform(kind,ids,dx,dy,dz,dyaw,local_space)
    if type(ids)~='table' then return nil,'ids must be a list' end
    if kind=='object' then
        for _,id in ipairs(ids) do local item=resolve_item(self.app.model,kind,id);if item and item.locked then return nil,'object '..tostring(item.name or id)..' is locked' end end
    end
    self.app.model:snapshot();local updated={};dx=dx or 0;dy=dy or 0;dz=dz or 0;dyaw=dyaw or 0
    for _,id in ipairs(ids) do
        local item=resolve_item(self.app.model,kind,id)
        if item and item.transform then
            local old_pos=Util.deepcopy(item.transform.position)
            local mx,my=dx,dy;if local_space then mx,my=Util.rotate_xy(dx,dy,item.transform.rotation.yaw) end
            item.transform.position.x=item.transform.position.x+mx;item.transform.position.y=item.transform.position.y+my;item.transform.position.z=item.transform.position.z+dz
            item.transform.rotation.yaw=item.transform.rotation.yaw+dyaw;item.updated_at=Util.now_iso()
            if kind=='premise' or kind=='room' then self:_cascade_delta(kind,id,old_pos,mx,my,dz,dyaw) end
            table.insert(updated,item)
        end
    end
    self.app.model:touch();self.app:mark_dirty()
    local refreshed,failed=0,{}
    if kind=='object' then refreshed,failed=refresh_objects(self.app,updated) end
    return updated,#failed>0 and (tostring(#failed)..' live object(s) failed to update') or nil,{refreshed=refreshed,failed=failed}
end

function Authoring:transform_object_group(ids,args)
    if type(ids)~='table' or #ids==0 then return nil,'select at least one object' end
    args=args or {};local objects,seen={},{ }
    for _,id in ipairs(ids) do
        if not seen[id] then
            local object=self.app.model:get_object(id);if not object then return nil,'object not found: '..tostring(id) end
            if object.locked then return nil,'object '..tostring(object.name or id)..' is locked' end
            seen[id]=true;table.insert(objects,object)
        end
    end
    local supplied=args.pivot and (args.pivot.position or args.pivot)
    local pivot={x=tonumber(supplied and supplied.x) or 0,y=tonumber(supplied and supplied.y) or 0,z=tonumber(supplied and supplied.z) or 0,w=1}
    if not supplied then
        for _,object in ipairs(objects) do local p=object.transform.position;pivot.x=pivot.x+p.x;pivot.y=pivot.y+p.y;pivot.z=pivot.z+p.z end
        pivot.x=pivot.x/#objects;pivot.y=pivot.y/#objects;pivot.z=pivot.z/#objects
    end
    local active=self.app.model:get_object(args.active_id);local base_yaw=active and active.transform.rotation.yaw or 0
    local dx,dy,dz=tonumber(args.dx) or 0,tonumber(args.dy) or 0,tonumber(args.dz) or 0
    if args.local_space==true then dx,dy=Util.rotate_xy(dx,dy,base_yaw) end
    local dyaw=tonumber(args.dyaw) or 0;local factor=tonumber(args.scale_factor) or 1
    if factor<=0.001 then return nil,'scale factor must be greater than zero' end
    if factor~=1 then
        for _,object in ipairs(objects) do if not (object.metadata and type(object.metadata.world_builder)=='table') then return nil,'group scaling requires World Builder resources; '..tostring(object.name)..' uses CET entity spawning' end end
    end
    self.app.model:snapshot()
    local angle=dyaw*math.pi/180;local c,s=math.cos(angle),math.sin(angle)
    for _,object in ipairs(objects) do
        local p=object.transform.position;local ox=(p.x-pivot.x)*factor;local oy=(p.y-pivot.y)*factor
        object.transform.position.x=pivot.x+ox*c-oy*s+dx
        object.transform.position.y=pivot.y+ox*s+oy*c+dy
        object.transform.position.z=pivot.z+(p.z-pivot.z)*factor+dz
        object.transform.rotation.yaw=(object.transform.rotation.yaw or 0)+dyaw
        if factor~=1 then
            object.size.x=math.max(0.001,(object.size.x or 1)*factor)
            object.size.y=math.max(0.001,(object.size.y or 1)*factor)
            object.size.z=math.max(0.001,(object.size.z or 1)*factor)
        end
        object.updated_at=Util.now_iso()
    end
    self.app.model:touch();self.app:mark_dirty()
    local refreshed,failed=refresh_objects(self.app,objects)
    if self.app.selection then self.app.selection.revision=self.app.selection.revision+1 end
    local result={objects=objects,count=#objects,pivot={position={x=pivot.x+dx,y=pivot.y+dy,z=pivot.z+dz,w=1},rotation={roll=0,pitch=0,yaw=(tonumber(args.pivot and args.pivot.rotation and args.pivot.rotation.yaw) or base_yaw)+dyaw}},refreshed=refreshed,failed=failed}
    return result,#failed>0 and (tostring(#failed)..' live object(s) failed to update; see DEBUG LOG.') or nil
end

function Authoring:layout_object_group(ids,args)
    args=args or {};local objects,err=object_group(self.app.model,ids);if not objects then return nil,err end
    local operation=tostring(args.operation or '');local axis=args.axis
    if operation=='align' or operation=='distribute' then
        if axis~='x' and axis~='y' and axis~='z' then return nil,'axis must be x, y, or z' end
    end
    local active=self.app.model:get_object(args.active_id)
    if (operation=='match_rotation' or operation=='match_scale' or (operation=='align' and args.mode=='active')) and not active then return nil,'active object not found' end
    if operation=='match_scale' then
        for _,object in ipairs(objects) do if not (object.metadata and type(object.metadata.world_builder)=='table') then return nil,'matching live scale requires World Builder resources; '..tostring(object.name)..' uses CET entity spawning' end end
    end
    if operation=='distribute' and #objects<3 then return nil,'distribution requires at least three objects' end
    if operation~='align' and operation~='distribute' and operation~='match_rotation' and operation~='match_scale' and operation~='snap' then return nil,'unsupported layout operation: '..operation end

    self.app.model:snapshot()
    if operation=='align' then
        local mode=args.mode or 'center';local target
        if mode=='active' then
            target=active.transform.position[axis]
        elseif mode=='min' or mode=='max' then
            target=objects[1].transform.position[axis]
            for _,object in ipairs(objects) do local value=object.transform.position[axis];if (mode=='min' and value<target) or (mode=='max' and value>target) then target=value end end
        else
            target=0;for _,object in ipairs(objects) do target=target+object.transform.position[axis] end;target=target/#objects
        end
        for _,object in ipairs(objects) do object.transform.position[axis]=target;object.updated_at=Util.now_iso() end
    elseif operation=='distribute' then
        table.sort(objects,function(a,b) return a.transform.position[axis]<b.transform.position[axis] end)
        local first=objects[1].transform.position[axis];local last=objects[#objects].transform.position[axis];local step=(last-first)/(#objects-1)
        for index,object in ipairs(objects) do object.transform.position[axis]=first+step*(index-1);object.updated_at=Util.now_iso() end
    elseif operation=='match_rotation' then
        for _,object in ipairs(objects) do if object.id~=active.id then object.transform.rotation=Util.deepcopy(active.transform.rotation);object.updated_at=Util.now_iso() end end
    elseif operation=='match_scale' then
        for _,object in ipairs(objects) do if object.id~=active.id then object.size=Util.deepcopy(active.size);object.updated_at=Util.now_iso() end end
    elseif operation=='snap' then
        local grid=tonumber(args.grid) or tonumber(self.app.model.data.settings.snapping.grid) or 0.25
        local angle=tonumber(args.angle) or tonumber(self.app.model.data.settings.snapping.angle) or 5
        for _,object in ipairs(objects) do object.transform=Util.snap_transform(object.transform,grid,angle);object.updated_at=Util.now_iso() end
    end
    self.app.model:touch();self.app:mark_dirty()
    if self.app.assemblies and self.app.active_object_group_id then self.app.assemblies:refresh_group_pivot(self.app.active_object_group_id,args.active_id) end
    if self.app.selection then self.app.selection.revision=self.app.selection.revision+1 end
    local refreshed,failed=refresh_objects(self.app,objects)
    local result={operation=operation,axis=axis,mode=args.mode,count=#objects,objects=objects,refreshed=refreshed,failed=failed}
    return result,#failed>0 and (tostring(#failed)..' live object(s) failed to update; see DEBUG LOG.') or nil
end

function Authoring:place_object_at_aim(args)
    args=args or {};local hit,err=self.app.game:aim_point(args.distance);if not hit then return nil,err end
    local p=Util.deepcopy(hit.position)
    local offset=tonumber(args.surface_offset)
    if offset==nil then offset=tonumber(self.app.model.data.settings.snapping.surface_offset) or 0 end
    if hit.normal and offset~=0 then p.x=p.x+(hit.normal.x or 0)*offset;p.y=p.y+(hit.normal.y or 0)*offset;p.z=p.z+(hit.normal.z or 0)*offset end
    args.transform={position=p,rotation={roll=args.roll or 0,pitch=args.pitch or 0,yaw=args.yaw or 0}}
    local object,place_err=self.app.builder:place_object(args);if not object then return nil,place_err end
    local entity_id,spawn_error
    if args.spawn then entity_id,spawn_error=self.app.placement:spawn(object) end
    return {object=object,placement_source=hit.source,normal=hit.normal,entity_id=entity_id and tostring(entity_id) or nil,spawn_error=spawn_error}
end

return Authoring
