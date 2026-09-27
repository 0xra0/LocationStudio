local Util=require('modules/util')
local RuntimeState=require('modules/runtime_state')

local RuntimeShell={}
RuntimeShell.__index=RuntimeShell

local function vec4(p)
    p=p or {}
    if Vector4 and Vector4.new then return Vector4.new(p.x or 0,p.y or 0,p.z or 0,p.w or 1) end
    if ToVector4 then return ToVector4{x=p.x or 0,y=p.y or 0,z=p.z or 0,w=p.w or 1} end
    return p
end

local function euler(r)
    r=r or {}
    if EulerAngles and EulerAngles.new then return EulerAngles.new(r.roll or 0,r.pitch or 0,r.yaw or 0) end
    if ToEulerAngles then return ToEulerAngles{roll=r.roll or 0,pitch=r.pitch or 0,yaw=r.yaw or 0} end
    return r
end

function RuntimeShell.new(app,persistent)
    local state=persistent or RuntimeState.get()
    state.handles=state.handles or {}
    return setmetatable({app=app,handles=state.handles,last_error=nil,last_status=nil,sync_session=nil,sync_elapsed=0,last_wb_selection_signature=''},RuntimeShell)
end

local function selection_signature(ids)
    local values={};for _,id in ipairs(ids or {}) do table.insert(values,tostring(id)) end
    table.sort(values);return table.concat(values,'|')
end

function RuntimeShell:_log(level,message,fields)
    local logger=self.app and self.app.logger
    if logger and logger[level] then logger[level](logger,'runtime_shell',message,fields) end
end

function RuntimeShell:_world_builder()
    local wb=self.app.integrations and self.app.integrations.world_builder or nil
    if not wb and GetMod then
        local ok,value=pcall(function() return GetMod('entSpawner') end)
        if ok then wb=value end
    end
    return wb
end

function RuntimeShell:status(refresh)
    if refresh and self.app.integrations then self.app.integrations:refresh() end
    local wb=self:_world_builder()
    local spawnUI=wb and wb.baseUI and wb.baseUI.spawnUI or nil
    local archive_exists=nil
    if type(ModArchiveExists)=='function' then
        local ok,value=pcall(function() return ModArchiveExists('baseEntity.archive') end)
        if ok then archive_exists=value==true end
    end
    local modern=spawnUI~=nil and type(spawnUI.spawnNew)=='function' and spawnUI.spawnedUI~=nil and spawnUI.spawnedUI.root~=nil
    local legacy=spawnUI~=nil and type(spawnUI.getSpawnListByModulePath)=='function' and type(spawnUI.resolveEntryClass)=='function' and type(spawnUI.spawnNew)=='function'
    local ready=modern or legacy
    local reason
    if not wb then reason='World Builder / entSpawner is not loaded.'
    elseif not spawnUI then reason='World Builder loaded, but spawnUI is not initialized yet.'
    elseif not ready then reason='World Builder Spawn New is not initialized. Open World Builder once, then reopen Location Studio.'
    elseif archive_exists==false then reason='World Builder baseEntity.archive is missing, so runtime game resources cannot spawn.' end
    if archive_exists==false then ready=false end
    local count=0;for _ in pairs(self.handles) do count=count+1 end
    self.last_status={available=ready,world_builder=wb~=nil,archive_exists=archive_exists,spawned=count,reason=reason,room_backend='game_assets',api=modern and '1.0.81' or (legacy and 'legacy' or 'unavailable'),catalog_available=modern and type(spawnUI.getActiveSpawnList)=='function'}
    return self.last_status
end

function RuntimeShell:is_generated(object)
    return object and object.metadata and object.metadata.generated==true
end

function RuntimeShell:is_world_builder(object)
    return object and object.metadata and type(object.metadata.world_builder)=='table'
end

function RuntimeShell:_entry_for(object)
    local metadata=object.metadata or {};local wb=metadata.world_builder
    if wb then
        if type(wb.entry)~='table' then return nil,nil,nil,'Imported game resource has no World Builder entry data.' end
        return Util.deepcopy(wb.entry),wb.definition_key,wb.module_path
    end
    return nil,nil,nil,'Legacy primitive shell blocked. Rebuild this room with a real game-asset room kit.'
end

function RuntimeShell:_apply(handle,object)
    handle:setPosition(vec4(object.transform and object.transform.position))
    handle:setRotation(euler(object.transform and object.transform.rotation))
    local size=object.size;local wb=object.metadata and object.metadata.world_builder
    local apply_scale=not wb or wb.apply_scale~=false
    if size and apply_scale and type(handle.setScale)=='function' then
        handle:setScale({x=math.max(0.001,tonumber(size.x) or 1),y=math.max(0.001,tonumber(size.y) or 1),z=math.max(0.001,tonumber(size.z) or 1)},true)
    end
end

function RuntimeShell:spawn(object)
    if not object then return nil,'object not found' end
    if not self:is_generated(object) and not self:is_world_builder(object) then return nil,'object is not a World Builder resource' end
    if self.handles[object.id] then return 'wb:'..object.id end
    local status=self:status(true)
    if not status.available then
        self.last_error=status.reason
        self:_log('error','backend_unavailable',{id=object.id,error=self.last_error})
        return nil,self.last_error
    end
    local wb=self:_world_builder();local spawnUI=wb.baseUI.spawnUI
    local entry,definition_key,module_path,entry_err=self:_entry_for(object);if not entry then return nil,entry_err end
    local size=object.size or {x=1,y=1,z=1}
    local ok,handle=pcall(function()
        local class
        if self.last_status and self.last_status.api=='legacy' then
            local list=spawnUI.getSpawnListByModulePath(module_path or 'mesh/mesh')
            if not list then error('World Builder resource list is not ready') end
            class=spawnUI.resolveEntryClass(list,entry)
        else
            local class_error
            if self.app.world_builder then class,class_error=self.app.world_builder:class_for({world_builder={definition_key=definition_key}}) end
            if not class then error('World Builder resource class is unavailable for '..tostring(definition_key)..': '..tostring(class_error or 'adapter unavailable')) end
        end
        if not class then error('World Builder resource class is unavailable for '..tostring(definition_key)) end
        local element=spawnUI.spawnNew(entry,class,false)
        if not element then error('World Builder returned no spawned element') end
        local configured,config_err=pcall(function()
            self:_apply(element,object)
        end)
        if not configured then
            -- Retain the handle if rollback itself fails; it must remain removable.
            self.handles[object.id]=element
            object.runtime={spawned=true,status='failed',backend='world_builder',entity_id='wb:'..object.id}
            local removed,result=pcall(function() return element:remove() end)
            if removed and result~=false then self.handles[object.id]=nil;object.runtime={spawned=false,status='failed',error=tostring(config_err)} end
            error(config_err)
        end
        return element
    end)
    if not ok or not handle then
        self.last_error=tostring(handle)
        self:_log('error','spawn_failed',{id=object.id,name=object.name,error=self.last_error})
        return nil,self.last_error
    end
    self.handles[object.id]=handle
    object.runtime={spawned=true,status='confirmed',backend='world_builder',entity_id='wb:'..object.id}
    self.last_error=nil
    local resource=object.metadata and object.metadata.world_builder
    self:_log('info','spawned_in_world_builder',{id=object.id,name=object.name,x=size.x,y=size.y,z=size.z,api=status.api,resource=true,definition=resource and resource.definition_key,path=resource and resource.resource_path,room_kit=object.metadata and object.metadata.room_kit==true})
    return 'wb:'..object.id
end

function RuntimeShell:update_object(object,options)
    if not object then return nil,'object not found' end
    local handle=self.handles[object.id];if not handle then return self:spawn(object) end
    local ok,err=pcall(function() self:_apply(handle,object) end)
    if not ok then self.last_error=tostring(err);self:_log('error','update_failed',{id=object.id,error=self.last_error});return nil,self.last_error end
    object.runtime={spawned=true,status='confirmed',backend='world_builder',entity_id='wb:'..object.id}
    if not (options and options.silent) then self:_log('info','updated',{id=object.id}) end
    return 'wb:'..object.id
end

function RuntimeShell:focus(object)
    if not object then return nil,'object not found' end
    if object.locked then return nil,'object is locked; unlock it before using the World Builder gizmo' end
    local result,err=self:focus_many({object},object.id);if not result then return nil,err end
    return {selected=true,id=object.id,count=result.count}
end

function RuntimeShell:focus_many(objects,active_id)
    if type(objects)~='table' or #objects==0 then return nil,'select at least one object' end
    local wb=self:_world_builder();local spawnedUI=wb and wb.baseUI and wb.baseUI.spawnUI and wb.baseUI.spawnUI.spawnedUI
    local selected,skipped,ids={},{},{}
    local ok,err=pcall(function()
        if spawnedUI and type(spawnedUI.unselectAll)=='function' then spawnedUI.unselectAll() end
        for _,object in ipairs(objects) do
            local handle=self.handles[object.id]
            if object.locked then table.insert(skipped,{id=object.id,error='locked'})
            elseif not handle then table.insert(skipped,{id=object.id,error='not spawned in World Builder'})
            else
                if type(handle.setSelected)=='function' then handle:setSelected(true) else handle.selected=true end
                table.insert(selected,object);table.insert(ids,object.id)
            end
        end
    end)
    if not ok then
        self.last_error=tostring(err);self:_log('error','focus_failed',{active_id=active_id,error=self.last_error})
        return nil,self.last_error
    end
    if #selected==0 then return nil,skipped[1] and skipped[1].error or 'no World Builder objects were available' end
    local lookup={};for _,id in ipairs(ids) do lookup[id]=true end
    self.sync_session={ids=lookup,key=selection_signature(ids),snapshotted=false}
    self.last_wb_selection_signature=self.sync_session.key
    self:_log('info','focused_in_world_builder',{active_id=active_id,count=#selected,skipped=#skipped})
    return {selected=selected,skipped=skipped,count=#selected,active_id=active_id}
end

function RuntimeShell:unfocus(object)
    if not object then return true end
    local handle=self.handles[object.id]
    if handle and type(handle.setSelected)=='function' then pcall(function() handle:setSelected(false) end) end
    if self.sync_session and self.sync_session.ids and self.sync_session.ids[object.id] then self.sync_session=nil end
    return true
end

function RuntimeShell:clear_focus()
    local wb=self:_world_builder();local spawnedUI=wb and wb.baseUI and wb.baseUI.spawnUI and wb.baseUI.spawnUI.spawnedUI
    if spawnedUI and type(spawnedUI.unselectAll)=='function' then pcall(function() spawnedUI.unselectAll() end) end
    self.sync_session=nil;self.last_wb_selection_signature='';return true
end

function RuntimeShell:world_builder_selection()
    local wb=self:_world_builder();local spawnedUI=wb and wb.baseUI and wb.baseUI.spawnUI and wb.baseUI.spawnUI.spawnedUI
    local refs={};for id,handle in pairs(self.handles) do refs[handle]=id end
    local ids,lookup={},{}
    if spawnedUI and type(spawnedUI.selectedPaths)=='table' then
        for _,entry in ipairs(spawnedUI.selectedPaths) do
            local id=entry and refs[entry.ref]
            if id and not lookup[id] then table.insert(ids,id);lookup[id]=true end
        end
    end
    for id,handle in pairs(self.handles) do
        if handle.selected==true and not lookup[id] then table.insert(ids,id);lookup[id]=true end
    end
    table.sort(ids);return ids
end

function RuntimeShell:sync_world_builder_selection()
    if not self.app.selection then return false end
    local ids=self:world_builder_selection();local signature=selection_signature(ids)
    if signature==self.last_wb_selection_signature then return false end
    self.last_wb_selection_signature=signature
    if #ids>0 then
        self.app.selection:set_object_group(ids,ids[#ids],'world_builder')
        local lookup={};for _,id in ipairs(ids) do lookup[id]=true end
        self.sync_session={ids=lookup,key=signature,snapshotted=false}
        self:_log('info','selection_pulled_from_world_builder',{count=#ids,active_id=ids[#ids]})
        return true
    elseif self.app.selection.group_source=='world_builder' then
        self.app.selection:set_object_group({},nil,'world_builder');self.sync_session=nil
        return true
    end
    return false
end

local function differs(a,b,epsilon)
    return math.abs((tonumber(a) or 0)-(tonumber(b) or 0))>(epsilon or 0.0001)
end

function RuntimeShell:sync_from_handle(object)
    if not object then return nil,'object not found' end
    if object.locked then return nil,'object is locked' end
    local handle=self.handles[object.id];if not handle then return nil,'object is not spawned in World Builder' end
    if type(handle.getPosition)~='function' or type(handle.getRotation)~='function' then return nil,'World Builder handle does not expose transform getters' end
    local ok,position,rotation,scale=pcall(function()
        local p=handle:getPosition();local r=handle:getRotation();local s=type(handle.getScale)=='function' and handle:getScale() or nil
        return p,r,s
    end)
    if not ok then return nil,tostring(position) end
    if not position or not rotation then return nil,'World Builder returned an incomplete transform' end
    local current=object.transform or {};local cp=current.position or {};local cr=current.rotation or {};local size=object.size or {x=1,y=1,z=1}
    local changed=differs(cp.x,position.x) or differs(cp.y,position.y) or differs(cp.z,position.z) or differs(cr.roll,rotation.roll,0.001) or differs(cr.pitch,rotation.pitch,0.001) or differs(cr.yaw,rotation.yaw,0.001)
    local wb=object.metadata and object.metadata.world_builder
    if scale and (not wb or wb.apply_scale~=false) then changed=changed or differs(size.x,scale.x) or differs(size.y,scale.y) or differs(size.z,scale.z) end
    if not changed then return {changed=false,id=object.id} end
    if not self.sync_session or not self.sync_session.ids or not self.sync_session.ids[object.id] then self.sync_session={ids={[object.id]=true},key=tostring(object.id),snapshotted=false} end
    if not self.sync_session.snapshotted then self.app.model:snapshot('World Builder gizmo move');self.sync_session.snapshotted=true end
    object.transform={position={x=tonumber(position.x) or 0,y=tonumber(position.y) or 0,z=tonumber(position.z) or 0,w=tonumber(position.w) or 1},rotation={roll=tonumber(rotation.roll) or 0,pitch=tonumber(rotation.pitch) or 0,yaw=tonumber(rotation.yaw) or 0}}
    if scale and (not wb or wb.apply_scale~=false) then object.size={x=math.max(0.001,tonumber(scale.x) or 1),y=math.max(0.001,tonumber(scale.y) or 1),z=math.max(0.001,tonumber(scale.z) or 1)} end
    object.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    if self.app.selection and self.app.selection:is('object',object.id) then self.app.selection.revision=self.app.selection.revision+1 end
    return {changed=true,id=object.id,transform=Util.deepcopy(object.transform),size=Util.deepcopy(object.size)}
end

function RuntimeShell:update(delta)
    self.sync_elapsed=(self.sync_elapsed or 0)+(tonumber(delta) or 0)
    if self.sync_elapsed<0.08 then return end
    self.sync_elapsed=0
    self:sync_world_builder_selection()
    local selection=self.app.selection;if not selection then return end
    local objects=selection:selected_objects();local changed=0;local failures={}
    for _,object in ipairs(objects) do
        local handle=self.handles[object.id]
        if handle and handle.selected==true and not object.locked then
            local result,err=self:sync_from_handle(object)
            if result and result.changed then changed=changed+1 elseif err and err~='World Builder handle does not expose transform getters' then table.insert(failures,{id=object.id,error=err}) end
        end
    end
    if #failures>0 then self:_log('warn','gizmo_sync_failed',{count=#failures,first=failures[1].error}) end
    return {changed=changed,failed=failures}
end

function RuntimeShell:preview_asset(asset,transform)
    if not asset or not self.app.world_builder then return nil,'World Builder asset metadata is unavailable' end
    self:clear_preview()
    local object={id='__asset_preview',name=asset.name,kind=asset.kind,template=asset.template,size=Util.deepcopy(asset.size),transform=Util.deepcopy(transform),metadata=Util.deepcopy(asset.metadata),runtime={}}
    local id,err=self:spawn(object);if not id then return nil,err end
    self.preview_object=object;return id
end

function RuntimeShell:update_preview(transform)
    if not self.preview_object then return nil,'no World Builder preview is active' end
    self.preview_object.transform=Util.deepcopy(transform)
    return self:update_object(self.preview_object)
end

function RuntimeShell:clear_preview()
    if not self.preview_object then return true end
    local object=self.preview_object;local ok,err=self:despawn(object)
    if ok then self.preview_object=nil end
    return ok,err
end

function RuntimeShell:despawn(object)
    if not object then return false,'object not found',false end
    local handle=self.handles[object.id]
    if not handle then
        if object.runtime and (object.runtime.backend=='world_builder_primitive' or object.runtime.backend=='world_builder') then object.runtime={spawned=false,backend=nil,entity_id=nil} end
        return true,nil,false
    end
    local ok,err=pcall(function() return handle:remove() end)
    if not ok or err==false then
        self.last_error=ok and 'World Builder refused removal' or tostring(err);self:_log('error','despawn_failed',{id=object.id,error=self.last_error});return false,self.last_error,false
    end
    self.handles[object.id]=nil;object.runtime={spawned=false,backend=nil,entity_id=nil}
    if self.sync_session and self.sync_session.ids and self.sync_session.ids[object.id] then self.sync_session=nil end
    self:_log('info','despawned',{id=object.id})
    return true,nil,true
end

function RuntimeShell:refresh(object)
    local ok,err=self:despawn(object);if not ok then return nil,err end
    return self:spawn(object)
end

function RuntimeShell:clear()
    local ids={};for id in pairs(self.handles) do table.insert(ids,id) end
    local count,failed=0,{}
    for _,id in ipairs(ids) do
        local object=self.app.model:get_object(id)
        if object then local ok,err,did=self:despawn(object);if ok and did then count=count+1 elseif not ok then table.insert(failed,{id=id,error=err}) end
        else self.handles[id]=nil end
    end
    return {despawned=count,failed=failed}
end

return RuntimeShell
