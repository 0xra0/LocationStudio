local Util=require('modules/util')

local Assemblies={}
Assemblies.__index=Assemblies

function Assemblies.new(app) return setmetatable({app=app},Assemblies) end

local function unique_objects(model,ids)
    if type(ids)~='table' then return nil,'object IDs must be a list' end
    local out,seen={},{}
    for _,id in ipairs(ids) do
        if not seen[id] then
            local object=model:get_object(id);if not object then return nil,'object not found: '..tostring(id) end
            seen[id]=true;table.insert(out,object)
        end
    end
    return out
end

local function pivot_for(objects,mode,active_id,custom)
    if #objects==0 then return nil,'group has no objects' end
    if mode=='custom' and type(custom)=='table' then
        local p=custom.position or custom;local r=custom.rotation or {}
        return {position={x=tonumber(p.x) or 0,y=tonumber(p.y) or 0,z=tonumber(p.z) or 0,w=1},rotation={roll=tonumber(r.roll) or 0,pitch=tonumber(r.pitch) or 0,yaw=tonumber(r.yaw or custom.yaw) or 0}}
    end
    if mode=='active' and active_id then
        for _,object in ipairs(objects) do if object.id==active_id then return Util.deepcopy(object.transform) end end
    end
    local result={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}
    for _,object in ipairs(objects) do local p=object.transform.position;result.position.x=result.position.x+p.x;result.position.y=result.position.y+p.y;result.position.z=result.position.z+p.z end
    result.position.x=result.position.x/#objects;result.position.y=result.position.y/#objects;result.position.z=result.position.z/#objects
    return result
end

function Assemblies:objects_for_group(id,recursive)
    local root=self.app.model:get_object_group(id);if not root then return nil,'group not found' end
    local ids,seen,visited={},{},{}
    local function collect(group)
        if visited[group.id] then return end;visited[group.id]=true
        for _,object_id in ipairs(group.object_ids or {}) do if not seen[object_id] then seen[object_id]=true;table.insert(ids,object_id) end end
        if recursive~=false then for _,child in ipairs(self.app.model.data.object_groups or {}) do if child.parent_id==group.id then collect(child) end end end
    end
    collect(root);return unique_objects(self.app.model,ids)
end

function Assemblies:create_group(args)
    args=args or {};local ids=args.ids or {}
    local objects,err=unique_objects(self.app.model,ids);if not objects then return nil,err end
    local premise_id=args.premise_id;local room_id=args.room_id
    if #objects>0 then
        premise_id=premise_id or objects[1].premise_id;room_id=room_id or objects[1].room_id
        for _,object in ipairs(objects) do if object.premise_id~=premise_id then premise_id=nil end;if object.room_id~=room_id then room_id=nil end end
    end
    local mode=args.pivot_mode or 'center';local pivot
    if #objects>0 then pivot=assert(pivot_for(objects,mode,args.active_id,args.pivot)) else pivot=args.pivot end
    local group,group_err=self.app.model:create_object_group({
        name=args.name,premise_id=premise_id,room_id=room_id,parent_id=args.parent_id,object_ids=ids,
        pivot_mode=mode,pivot=pivot,visible=args.visible,locked=args.locked,
    })
    if not group then return nil,group_err end
    self.app:mark_dirty()
    if #objects>0 and self.app.selection then self.app.selection:set_object_group(ids,args.active_id or ids[#ids],'saved_group');self.app.active_object_group_id=group.id end
    return group
end

function Assemblies:update_group(id,patch)
    patch=patch or {};local group=self.app.model:get_object_group(id);if not group then return nil,'group not found' end
    if patch.recalculate_pivot then
        local objects,err=self:objects_for_group(id,true);if not objects then return nil,err end
        patch.pivot=assert(pivot_for(objects,patch.pivot_mode or group.pivot_mode,patch.active_id,patch.pivot or group.pivot));patch.recalculate_pivot=nil;patch.active_id=nil
    end
    patch.recalculate_pivot=nil;patch.active_id=nil
    local updated,err=self.app.model:update_object_group(id,patch);if not updated then return nil,err end
    self.app:mark_dirty();return updated
end

function Assemblies:dissolve_group(id)
    local group=self.app.model:get_object_group(id);if not group then return nil,'group not found' end
    local count=#(group.object_ids or {});local ok,err=self.app.model:delete_object_group_meta(id);if not ok then return nil,err end
    self.app:mark_dirty();return {dissolved=true,id=id,objects_released=count}
end

function Assemblies:select_group(id,recursive,focus)
    local objects,err=self:objects_for_group(id,recursive);if not objects then return nil,err end
    local ids={};for _,object in ipairs(objects) do table.insert(ids,object.id) end
    if #ids==0 then return {objects={},count=0,group_id=id} end
    self.app.selection:set_object_group(ids,ids[#ids],'saved_group');self.app.active_object_group_id=id
    local focused
    if focus~=false and self.app.runtime_shell then focused=self.app.runtime_shell:focus_many(objects,ids[#ids]) end
    return {objects=objects,count=#objects,group_id=id,focus=focused}
end

function Assemblies:transform_group(id,args)
    local group=self.app.model:get_object_group(id);if not group then return nil,'group not found' end
    if group.locked then return nil,'group is locked' end
    local objects,err=self:objects_for_group(id,true);if not objects then return nil,err end
    local ids={};for _,object in ipairs(objects) do table.insert(ids,object.id) end
    args=args or {};args.pivot=args.pivot or group.pivot;args.active_id=args.active_id or ids[#ids]
    local result,warning=self.app.authoring:transform_object_group(ids,args)
    if result then
        group.pivot=Util.deepcopy(result.pivot);group.updated_at=Util.now_iso()
        self.app:mark_dirty()
    end
    return result,warning
end

function Assemblies:refresh_group_pivot(id,active_id)
    local group=self.app.model:get_object_group(id);if not group then return nil,'group not found' end
    if group.pivot_mode=='custom' then return group.pivot end
    local objects,err=self:objects_for_group(id,true);if not objects then return nil,err end
    local pivot,pivot_err=pivot_for(objects,group.pivot_mode,active_id,group.pivot);if not pivot then return nil,pivot_err end
    group.pivot=pivot;group.updated_at=Util.now_iso();return pivot
end

local function prefab_metadata(metadata)
    local result=Util.deepcopy(metadata or {})
    result.generated=false;result.room_kit=false;result.room_collision=nil;result.detached_from_room=true
    result.prefab_source=nil;result.prefab_instance=nil
    return result
end

function Assemblies:save_prefab(args)
    args=args or {};local objects,err=unique_objects(self.app.model,args.ids or {});if not objects then return nil,err end
    if #objects==0 then return nil,'select at least one object' end
    local mode=args.pivot_mode or 'center';local pivot=pivot_for(objects,mode,args.active_id,args.pivot)
    local yaw=pivot.rotation.yaw or 0;local values={}
    for _,object in ipairs(objects) do
        local p=object.transform.position;local lx,ly=Util.rotate_xy(p.x-pivot.position.x,p.y-pivot.position.y,-yaw)
        table.insert(values,{
            name=object.name,kind=object.kind,template=object.template,appearance=object.appearance,layer=object.layer,
            transform={position={x=lx,y=ly,z=p.z-pivot.position.z,w=1},rotation={roll=object.transform.rotation.roll,pitch=object.transform.rotation.pitch,yaw=(object.transform.rotation.yaw or 0)-yaw}},
            size=Util.deepcopy(object.size),enabled=object.enabled,visible=object.visible,properties=Util.deepcopy(object.properties),metadata=prefab_metadata(object.metadata),
        })
    end
    local prefab=self.app.model:add_object_prefab({
        name=args.name,category=args.category,tags=args.tags,notes=args.notes,objects=values,pivot_mode=mode,source_group_id=args.source_group_id,
    })
    self.app:mark_dirty();return prefab
end

local function target_transform(app,args)
    if type(args.transform)=='table' then
        local t=args.transform;local p=t.position or {};local r=t.rotation or {}
        return {position={x=tonumber(p.x) or 0,y=tonumber(p.y) or 0,z=tonumber(p.z) or 0,w=1},rotation={roll=tonumber(r.roll) or 0,pitch=tonumber(r.pitch) or 0,yaw=tonumber(r.yaw) or 0}}
    end
    if args.source=='aim' then
        local hit,err=app.game:aim_point(args.distance);if not hit then return nil,err end
        return {position=Util.deepcopy(hit.position),rotation={roll=0,pitch=0,yaw=tonumber(args.yaw) or 0}}
    end
    return app.game:capture_transform()
end

function Assemblies:instantiate_prefab(id,args)
    args=args or {};local prefab=self.app.model:get_object_prefab(id);if not prefab then return nil,'prefab not found' end
    if #(prefab.objects or {})==0 then return nil,'prefab has no objects' end
    local target,err=target_transform(self.app,args);if not target then return nil,err end
    local premise_id=args.premise_id or self.app.selected_premise_id;if not premise_id or not self.app.model:get_premise(premise_id) then return nil,'select a destination location first' end
    local room_id=args.room_id or self.app.selected_room_id;local yaw=target.rotation.yaw or 0;local queue={}
    for _,source in ipairs(prefab.objects) do
        local local_p=source.transform.position;local ox,oy=Util.rotate_xy(local_p.x,local_p.y,yaw);local metadata=prefab_metadata(source.metadata)
        metadata.prefab_source=prefab.id;metadata.prefab_instance=true
        table.insert(queue,{
            premise_id=premise_id,room_id=room_id,name=source.name,kind=source.kind,template=source.template,appearance=source.appearance,layer=source.layer,
            transform={position={x=target.position.x+ox,y=target.position.y+oy,z=target.position.z+local_p.z,w=1},rotation={roll=source.transform.rotation.roll,pitch=source.transform.rotation.pitch,yaw=yaw+(source.transform.rotation.yaw or 0)}},
            size=Util.deepcopy(source.size),enabled=source.enabled,visible=source.visible,locked=false,properties=Util.deepcopy(source.properties),metadata=metadata,
        })
    end
    self.app.model:snapshot()
    local objects=self.app.model:add_objects(queue,true);local ids={};for _,object in ipairs(objects) do table.insert(ids,object.id) end
    local group,group_err=self.app.model:create_object_group({
        name=args.group_name or (prefab.name..' Instance'),premise_id=premise_id,room_id=room_id,object_ids=ids,pivot_mode='custom',pivot=target,
    },true)
    if not group then return nil,group_err end
    local failed={}
    if args.spawn==true or (args.spawn~=false and self.app.model.data.settings.workspace.live_preview~=false) then
        for _,object in ipairs(objects) do local _,spawn_err=self.app.placement:spawn(object);if spawn_err then table.insert(failed,{id=object.id,error=spawn_err}) end end
    end
    self.app.selection:set_object_group(ids,ids[#ids],'saved_group');self.app.active_object_group_id=group.id;if self.app.runtime_shell then self.app.runtime_shell:focus_many(objects,ids[#ids]) end
    self.app:mark_dirty()
    return {prefab=prefab,group=group,objects=objects,count=#objects,failed=failed,target=target},#failed>0 and (tostring(#failed)..' prefab object(s) failed to spawn') or nil
end

function Assemblies:delete_prefab(id)
    local ok,err=self.app.model:delete_object_prefab(id);if not ok then return nil,err end;self.app:mark_dirty();return {deleted=true,id=id}
end

return Assemblies
