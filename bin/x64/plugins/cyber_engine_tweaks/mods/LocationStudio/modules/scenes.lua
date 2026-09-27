local Util=require('modules/util')

local Scenes={}
Scenes.__index=Scenes

local MEMBERS={room_ids='room',object_ids='object',location_ids='location',volume_ids='volume',camera_ids='camera',route_ids='route'}

local function get(model,kind,id)
    local fn=model['get_'..kind]
    return fn and fn(model,id) or nil
end

local function unique_ids(values)
    local out,seen={},{}
    for _,id in ipairs(type(values)=='table' and values or {}) do
        id=tostring(id or '')
        if id~='' and not seen[id] then seen[id]=true;table.insert(out,id) end
    end
    return out
end

local function merge_ids(current,added)
    local out=unique_ids(current);local seen={};for _,id in ipairs(out) do seen[id]=true end
    for _,id in ipairs(unique_ids(added)) do if not seen[id] then seen[id]=true;table.insert(out,id) end end
    return out
end

local function remove_ids(current,removed)
    local drop={};for _,id in ipairs(unique_ids(removed)) do drop[id]=true end
    local out={};for _,id in ipairs(unique_ids(current)) do if not drop[id] then table.insert(out,id) end end
    return out
end

function Scenes.new(app) return setmetatable({app=app,last_result=nil,last_error=nil},Scenes) end

function Scenes:validate(value,existing_id)
    value=value or {};local issues={};local premise_id=value.premise_id
    if premise_id and not self.app.model:get_premise(premise_id) then table.insert(issues,'premise not found: '..tostring(premise_id)) end
    for field,kind in pairs(MEMBERS) do
        for _,id in ipairs(unique_ids(value[field])) do
            local item=get(self.app.model,kind,id)
            if not item then table.insert(issues,kind..' not found: '..id)
            elseif premise_id and item.premise_id and item.premise_id~=premise_id then table.insert(issues,kind..' belongs to another location: '..id) end
        end
    end
    if existing_id and not self.app.model:get_scene(existing_id) then table.insert(issues,'scene not found: '..tostring(existing_id)) end
    return #issues==0,issues
end

function Scenes:_normalized(args)
    local value=Util.deepcopy(args or {})
    for field in pairs(MEMBERS) do value[field]=unique_ids(value[field]) end
    return value
end

function Scenes:create(args)
    local value=self:_normalized(args);local ok,issues=self:validate(value)
    if not ok then self.last_error=table.concat(issues,'; ');return nil,self.last_error end
    local scene=self.app.model:add_scene(value);self.app:mark_dirty()
    self.app.editing_scene_id=scene.id
    if self.app.selection then self.app.selection:set('scene',scene.id) end
    self.last_result={created=true,id=scene.id};self.last_error=nil
    if self.app.logger then self.app.logger:info('scene','created',{id=scene.id,name=scene.name,premise_id=scene.premise_id,objects=#scene.object_ids,rooms=#scene.room_ids}) end
    return scene
end

function Scenes:update(id,patch)
    local current=self.app.model:get_scene(id);if not current then return nil,'scene not found' end
    local merged=Util.deepcopy(current);for key,value in pairs(patch or {}) do if key~='id' and key~='created_at' then merged[key]=value end end
    merged=self:_normalized(merged);local ok,issues=self:validate(merged,id)
    if not ok then self.last_error=table.concat(issues,'; ');return nil,self.last_error end
    local scene,err=self.app.model:update_scene(id,merged);if not scene then return nil,err end
    self.app:mark_dirty();self.last_result={updated=true,id=id};self.last_error=nil
    if self.app.logger then self.app.logger:info('scene','updated',{id=id,name=scene.name}) end
    return scene
end

function Scenes:delete(id)
    local scene=self.app.model:get_scene(id);if not scene then return nil,'scene not found' end
    if self.app.live_scene_id==id then local result,err=self:deactivate(id);if not result or #(result.failed or {})>0 then return nil,err or 'scene runtime cleanup failed' end end
    local ok,err=self.app.model:delete_scene(id);if not ok then return nil,err end
    if self.app.selection and self.app.selection:is('scene',id) then self.app.selection:clear() end
    if self.app.editing_scene_id==id then self.app.editing_scene_id=nil end
    self.app:mark_dirty();self.last_result={deleted=true,id=id};self.last_error=nil
    if self.app.logger then self.app.logger:info('scene','deleted',{id=id,name=scene.name}) end
    return self.last_result
end

function Scenes:activate(id,spawn)
    local scene=self.app.model:get_scene(id);if not scene then return nil,'scene not found' end
    local spawned,failed,seen={}, {},{}
    local function spawn_object(object)
        if not object or seen[object.id] then return end;seen[object.id]=true
        local runtime_id,err=self.app.placement:spawn(object)
        if runtime_id then table.insert(spawned,{object_id=object.id,entity_id=tostring(runtime_id)}) else table.insert(failed,{object_id=object.id,error=tostring(err)}) end
    end
    if spawn~=false then
        for _,room_id in ipairs(scene.room_ids or {}) do
            local room=self.app.model:get_room(room_id)
            if room then for _,object_id in ipairs(room.shell_object_ids or {}) do spawn_object(self.app.model:get_object(object_id)) end end
        end
        for _,object_id in ipairs(scene.object_ids or {}) do spawn_object(self.app.model:get_object(object_id)) end
    end
    if self.app.selection then self.app.selection:set('scene',scene.id) end
    self.app.editing_scene_id=id
    local active=#failed==0;self.app.live_scene_id=active and id or self.app.live_scene_id
    local result={activated=active,id=scene.id,name=scene.name,spawned=spawned,failed=failed,counts={rooms=#scene.room_ids,objects=#scene.object_ids,locations=#scene.location_ids,volumes=#scene.volume_ids,cameras=#scene.camera_ids,routes=#scene.route_ids}}
    self.last_result=Util.deepcopy(result);self.last_error=#failed>0 and (tostring(#failed)..' scene object(s) failed to spawn') or nil
    if self.app.logger then self.app.logger:info('scene','activated',{id=scene.id,spawned=#spawned,failed=#failed}) end
    return result,self.last_error
end

function Scenes:select_objects(id)
    local scene=self.app.model:get_scene(id);if not scene then return nil,'scene not found' end
    local values,err=self.app.selection:set_object_group(scene.object_ids or {},(scene.object_ids or {})[#(scene.object_ids or {})],'scene')
    if not values then return nil,err end
    if self.app.runtime_shell and #values>0 then self.app.runtime_shell:focus_many(values,self.app.selection.id) end
    self.app.editing_scene_id=id
    return {selected=#values,ids=Util.deepcopy(scene.object_ids or {}),scene_id=id}
end

function Scenes:member_object_ids(id)
    local scene=type(id)=='table' and id or self.app.model:get_scene(id);if not scene then return nil,'scene not found' end
    local ids=unique_ids(scene.object_ids);local seen={};for _,value in ipairs(ids) do seen[value]=true end
    for _,room_id in ipairs(scene.room_ids or {}) do
        local room=self.app.model:get_room(room_id)
        if room then for _,object_id in ipairs(room.shell_object_ids or {}) do if not seen[object_id] then seen[object_id]=true;table.insert(ids,object_id) end end end
    end
    return ids
end

function Scenes:edit_members(id,args)
    local scene=self.app.model:get_scene(id);if not scene then return nil,'scene not found' end
    args=args or {};local mode=args.mode or 'add';if mode~='add' and mode~='remove' and mode~='replace' then return nil,'scene member mode must be add, remove, or replace' end
    local patch={};local source=args.members or args
    for field in pairs(MEMBERS) do
        if source[field]~=nil then
            if mode=='add' then patch[field]=merge_ids(scene[field],source[field])
            elseif mode=='remove' then patch[field]=remove_ids(scene[field],source[field])
            else patch[field]=unique_ids(source[field]) end
        end
    end
    local updated,err=self:update(id,patch);if not updated then return nil,err end
    self.app.editing_scene_id=id
    local result={updated=true,id=id,mode=mode,counts={}}
    for field in pairs(MEMBERS) do result.counts[field]=#(updated[field] or {}) end
    self.last_result=Util.deepcopy(result)
    if self.app.logger then self.app.logger:info('scene','members_edited',{id=id,mode=mode,counts=result.counts}) end
    return result
end

function Scenes:selection_members()
    local selection=self.app.selection;if not selection then return nil,'selection unavailable' end
    local members={};local kind=selection.kind
    if kind=='object' then members.object_ids={};for _,object in ipairs(selection:selected_objects()) do table.insert(members.object_ids,object.id) end
    elseif kind and MEMBERS[kind..'_ids'] then members[kind..'_ids']={selection.id}
    elseif kind=='room' then members.room_ids={selection.id}
    elseif kind=='location' then members.location_ids={selection.id}
    elseif kind=='volume' then members.volume_ids={selection.id}
    elseif kind=='camera' then members.camera_ids={selection.id}
    elseif kind=='route' then members.route_ids={selection.id}
    else return nil,'Select placed objects, a room, point, volume, camera, or route first.' end
    local count=0;for _,values in pairs(members) do count=count+#values end
    if count==0 then return nil,'selection has no scene members' end
    return members
end

function Scenes:edit_current_selection(id,mode)
    id=id or self.app.editing_scene_id;local members,err=self:selection_members();if not members then return nil,err end
    return self:edit_members(id,{mode=mode or 'add',members=members})
end

function Scenes:capture_premise(args)
    args=args or {};local premise_id=args.premise_id or self.app.selected_premise_id;local premise=self.app.model:get_premise(premise_id)
    if not premise then return nil,'select a location first' end
    local members={room_ids={},object_ids={},volume_ids={},camera_ids={}}
    if args.location_ids~=nil or not args.scene_id then members.location_ids=unique_ids(args.location_ids) end
    if args.route_ids~=nil or not args.scene_id then members.route_ids=unique_ids(args.route_ids) end
    if args.include_rooms~=false then for _,item in ipairs(self.app.model.data.rooms or {}) do if item.premise_id==premise_id then table.insert(members.room_ids,item.id) end end end
    if args.include_objects~=false then for _,item in ipairs(self.app.model.data.objects or {}) do
        local metadata=item.metadata or {};if item.premise_id==premise_id and (metadata.room_kit~=true or args.include_construction==true) then table.insert(members.object_ids,item.id) end
    end end
    if args.include_spatial~=false then
        for _,item in ipairs(self.app.model.data.volumes or {}) do if item.premise_id==premise_id then table.insert(members.volume_ids,item.id) end end
        for _,item in ipairs(self.app.model.data.cameras or {}) do if item.premise_id==premise_id then table.insert(members.camera_ids,item.id) end end
    end
    local scene,err
    if args.scene_id then
        local result;result,err=self:edit_members(args.scene_id,{mode=args.mode or 'replace',members=members});scene=result and self.app.model:get_scene(args.scene_id)
    else
        local value={name=args.name or (premise.name..' Scene'),kind=args.kind or 'gameplay',premise_id=premise_id,notes=args.notes}
        for field,ids in pairs(members) do value[field]=ids end
        scene,err=self:create(value)
    end
    if not scene then return nil,err end
    self.app.editing_scene_id=scene.id
    local result={captured=true,scene=scene,id=scene.id,premise_id=premise_id,counts={}}
    for field in pairs(MEMBERS) do result.counts[field]=#(scene[field] or {}) end
    self.last_result=Util.deepcopy(result)
    if self.app.logger then self.app.logger:info('scene','premise_captured',{id=scene.id,premise_id=premise_id,counts=result.counts}) end
    return result
end

function Scenes:deactivate(id)
    id=id or self.app.live_scene_id;local scene=self.app.model:get_scene(id);if not scene then return nil,'scene not found' end
    local ids=self:member_object_ids(scene);local removed,failed={},{}
    for _,object_id in ipairs(ids) do local object=self.app.model:get_object(object_id);if object and self.app.placement:is_tracked(object) then
        local ok,err=self.app.placement:despawn(object);if ok then table.insert(removed,object_id) else table.insert(failed,{id=object_id,error=tostring(err)}) end
    end end
    local complete=#failed==0;if complete and self.app.live_scene_id==id then self.app.live_scene_id=nil end
    local result={deactivated=complete,id=id,removed=removed,failed=failed};self.last_result=Util.deepcopy(result);self.last_error=complete and nil or (tostring(#failed)..' scene object(s) refused to despawn')
    if self.app.logger then self.app.logger[complete and 'info' or 'error'](self.app.logger,'scene',complete and 'deactivated' or 'deactivate_failed',{id=id,removed=#removed,failed=#failed}) end
    return result,self.last_error
end

function Scenes:isolate(id)
    local scene=self.app.model:get_scene(id);if not scene then return nil,'scene not found' end
    local member_ids=self:member_object_ids(scene);local keep={};for _,value in ipairs(member_ids) do keep[value]=true end
    local hidden,failed={},{}
    for _,object in ipairs(self.app.model.data.objects or {}) do if not keep[object.id] and self.app.placement:is_tracked(object) then
        local ok,err=self.app.placement:despawn(object);if ok then table.insert(hidden,object.id) else table.insert(failed,{id=object.id,error=tostring(err)}) end
    end end
    if #failed>0 then self.last_error='Isolation stopped: '..tostring(#failed)..' outside object(s) refused to despawn.';self.last_result={isolated=false,id=id,hidden=hidden,failed=failed};return nil,self.last_error end
    local activated,warning=self:activate(id,true);if not activated then return nil,warning end
    activated.isolated=activated.activated;activated.hidden=hidden;self.last_result=Util.deepcopy(activated)
    if self.app.logger then self.app.logger:info('scene','isolated',{id=id,hidden=#hidden,spawned=#(activated.spawned or {}),failed=#(activated.failed or {})}) end
    return activated,warning
end

function Scenes:status()
    local editing=self.app.model:get_scene(self.app.editing_scene_id);local live=self.app.model:get_scene(self.app.live_scene_id)
    return {scene_count=#(self.app.model.data.scenes or {}),editing_scene_id=editing and editing.id or nil,editing_scene_name=editing and editing.name or nil,live_scene_id=live and live.id or nil,live_scene_name=live and live.name or nil,last_result=Util.deepcopy(self.last_result),last_error=self.last_error}
end

return Scenes
