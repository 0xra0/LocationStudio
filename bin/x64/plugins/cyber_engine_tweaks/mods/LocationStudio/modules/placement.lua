local Util=require('modules/util')
local RuntimeEntities=require('modules/runtime_entities')
local RuntimeState=require('modules/runtime_state')
local ViewportTools=require('modules/viewport_tools')

local Placement={}
Placement.__index=Placement

function Placement.new(app,persistent)
    local state=persistent or RuntimeState.get()
    state.entity_ids=state.entity_ids or {};state.transient_ids=state.transient_ids or {}
    local entities=RuntimeEntities.new(app,state.entities)
    state.expected_live=state.expected_live or {}
    local self=setmetatable({app=app,entities=entities,entity_ids=state.entity_ids,transient_ids=state.transient_ids,expected_live=state.expected_live,preview=nil,last_error=nil,last_preview_refresh=0,runtime_state=state},Placement)
    for key,id in pairs(self.transient_ids) do
        local record=self.entities.records['transient:'..key]
        if not record then
            record={key='transient:'..key,id=id,started=0,state='pending'}
            self.entities.records[record.key]=record
        end
        local entity=self.entities:_find(record)
        if entity then record.state='confirmed' else record.state='missing' end
    end
    -- Recover direct CET ownership from authored runtime IDs when a stale or
    -- partial state table survived. Never issue a second spawn during adoption.
    for _,object in ipairs(app.model.data.objects or {}) do
        local id=self.entity_ids[object.id]
        if not id and object.runtime and object.runtime.backend=='entity_spawner' and object.runtime.entity_id then
            id=tonumber(object.runtime.entity_id) or object.runtime.entity_id
            self.entity_ids[object.id]=id
        end
        if id and not self.entities.records['object:'..object.id] then
            local record={key='object:'..object.id,id=id,template=object.template,object=object,object_id=object.id,started=0,state='pending'}
            local entity=self.entities:_find(record)
            if entity then record.state='confirmed';object.runtime={spawned=true,status='confirmed',backend='entity_spawner',entity_id=tostring(id)}
            else record.state='missing';object.runtime={spawned=false,status='missing',backend='entity_spawner',entity_id=tostring(id),error='Saved runtime ID is not currently resolvable.'} end
            self.entities.records[record.key]=record
        end
    end
    return self
end

function Placement:is_opening_placeholder(object)
    return object and object.metadata and object.metadata.opening_id and Util.trim(object.template)==''
end

local function procedural(self,object) return object and object.metadata and object.metadata.procedural and self.app.procedural end

function Placement:is_tracked(object)
    -- Procedural geometry has no live mesh until the mod is built; its preview shapes stand in.
    if procedural(self,object) then return self.app.procedural:is_shown(object) end
    return object and (self.entity_ids[object.id]~=nil or (self.app.runtime_shell and self.app.runtime_shell.handles[object.id]~=nil)) or false
end

local function authored_signature(object)
    local t=object and object.transform or {};local p=t.position or {};local r=t.rotation or {};local s=object and object.size or {}
    local value={template=object and object.template,appearance=object and object.appearance,enabled=object and object.enabled,visible=object and object.visible,
        position={x=p.x or 0,y=p.y or 0,z=p.z or 0},rotation={roll=r.roll or 0,pitch=r.pitch or 0,yaw=r.yaw or 0},size={x=s.x,y=s.y,z=s.z},
        resource=object and object.metadata and object.metadata.world_builder and object.metadata.world_builder.definition_key}
    local ok,result=pcall(json.encode,value);return ok and result or tostring(object and object.id)
end

local function close(a,b,epsilon) return math.abs((tonumber(a) or 0)-(tonumber(b) or 0))<=(epsilon or 0.001) end

function Placement:_track_synced(object)
    local signature=authored_signature(object)
    local record=self.entities.records['object:'..object.id]
    if record then record.synced_signature=signature end
    local handle=self.app.runtime_shell and self.app.runtime_shell.handles[object.id]
    if handle then handle.synced_signature=signature end
    return signature
end

function Placement:_should_be_spawned(object)
    if not object or object.enabled==false or object.visible==false or self:is_opening_placeholder(object) then return false end
    local layer=object.layer
    for _,item in ipairs(self.app.model.data.layers or {}) do if item.id==layer and item.visible==false then return false end end
    if procedural(self,object) then return true end
    return object.template~=nil and object.template~='' or self.app.runtime_shell and (self.app.runtime_shell:is_generated(object) or self.app.runtime_shell:is_world_builder(object))
end

function Placement:compare_runtime()
    local tracked={}
    for id in pairs(self.entity_ids) do tracked[id]=true end
    for id in pairs((self.app.runtime_shell and self.app.runtime_shell.handles) or {}) do tracked[id]=true end
    for id in pairs(self.expected_live) do tracked[id]=true end
    -- The VFX and environment editors own their transient preview nodes.
    tracked['__vfx_preview']=nil
    tracked['__env_fog_preview']=nil
    for id in pairs(tracked) do if type(id)=='string' and id:sub(1,7)=='__proc_' then tracked[id]=nil end end
    for id in pairs(tracked) do if type(id)=='string' and id:sub(1,17)=='__spline_preview_' then tracked[id]=nil end end
    local report={items={},counts={remove=0,update=0,missing=0},has_changes=false,checked=0}
    for id in pairs(tracked) do
        report.checked=report.checked+1
        local object=self.app.model:get_object(id)
        local handle=self.app.runtime_shell and self.app.runtime_shell.handles[id]
        local record=self.entities.records['object:'..id]
        local item={id=id,name=object and object.name or (record and record.object and record.object.name) or id}
        if not object or not self:_should_be_spawned(object) then
            item.action='remove';report.counts.remove=report.counts.remove+1
        elseif self.expected_live[id] and not self.entity_ids[id] and not handle then
            item.action='spawn';item.backend=(object.metadata and (object.metadata.generated or object.metadata.world_builder)) and 'world_builder' or 'entity_spawner';report.counts.missing=report.counts.missing+1
        elseif handle then
            local signature=authored_signature(object);local actual_matches=nil
            if type(handle.getPosition)=='function' and type(handle.getRotation)=='function' then
                local ok,p,r,s=pcall(function() return handle:getPosition(),handle:getRotation(),type(handle.getScale)=='function' and handle:getScale() or nil end)
                if ok and p and r then
                    local t=object.transform or {};local ep=t.position or {};local er=t.rotation or {};local size=object.size or {}
                    actual_matches=close(ep.x,p.x) and close(ep.y,p.y) and close(ep.z,p.z) and close(er.roll,r.roll,0.01) and close(er.pitch,r.pitch,0.01) and close(er.yaw,r.yaw,0.01)
                    local wb=object.metadata and object.metadata.world_builder
                    if actual_matches and s and (not wb or wb.apply_scale~=false) then actual_matches=close(size.x,s.x) and close(size.y,s.y) and close(size.z,s.z) end
                end
            end
            if actual_matches==false or (actual_matches==nil and handle.synced_signature and handle.synced_signature~=signature) then item.action='update';item.backend='world_builder'
            elseif actual_matches==nil and not handle.synced_signature then item.action='unverified';item.backend='world_builder'
            end
            if item.action=='update' then report.counts.update=report.counts.update+1 end
        elseif self.entity_ids[id] then
            local live=self.entities:_find(record or {id=self.entity_ids[id]});local actual_matches=nil
            if live then
                local ok,p,r=pcall(function()
                    local position=type(live.GetWorldPosition)=='function' and live:GetWorldPosition() or nil
                    local orientation=type(live.GetWorldOrientation)=='function' and live:GetWorldOrientation() or nil
                    local angles=orientation and type(orientation.ToEulerAngles)=='function' and orientation:ToEulerAngles() or nil
                    return position,angles
                end)
                if ok and p then
                    local t=object.transform or {};local ep=t.position or {};actual_matches=close(ep.x,p.x) and close(ep.y,p.y) and close(ep.z,p.z)
                    if r then local er=(t.rotation or {});actual_matches=actual_matches and close(er.roll,r.roll,0.1) and close(er.pitch,r.pitch,0.1) and close(er.yaw,r.yaw,0.1) end
                end
            end
            if not live or actual_matches==false or (record and record.template and record.template~=object.template) or (record and record.synced_signature and record.synced_signature~=authored_signature(object)) then
                item.action='update';item.backend='entity_spawner';report.counts.update=report.counts.update+1
            elseif (actual_matches==nil and (not record or not record.synced_signature)) then item.action='unverified';item.backend='entity_spawner' end
        end
        if item.action then report.items[#report.items+1]=item end
    end
    table.sort(report.items,function(a,b)return a.id<b.id end)
    report.has_changes=report.counts.remove+report.counts.update+report.counts.missing>0
    return report
end

function Placement:sync_runtime()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return nil,'Commit or cancel the active transform session before syncing runtime.' end
    if app.stamp_session and app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before syncing runtime.' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return nil,'Resolve authoring-plan recovery before syncing runtime.' end
    local before=self:compare_runtime();local result={removed=0,updated=0,spawned=0,failed={}};local failed_ids={}
    for _,entry in ipairs(before.items) do
        if entry.action=='remove' or entry.action=='update' then
            local object=app.model:get_object(entry.id)
            local is_wb=self.app.runtime_shell and self.app.runtime_shell.handles[entry.id]~=nil
            local runtime_object=is_wb and {id=entry.id,runtime={backend='world_builder'}} or (object or {id=entry.id,runtime={backend='entity_spawner'}})
            local ok,err,did=self:despawn(runtime_object)
            if ok and object then object.runtime={spawned=false,backend=nil,entity_id=nil} end
            if not ok then failed_ids[entry.id]=true;table.insert(result.failed,{id=entry.id,error=err})
            elseif did then result.removed=result.removed+1 end
            if ok and entry.action=='remove' then self.expected_live[entry.id]=nil end
        end
    end
    for _,entry in ipairs(before.items) do
        if (entry.action=='update' or entry.action=='spawn') and not failed_ids[entry.id] then
            local object=app.model:get_object(entry.id)
            if object then
                local id,err=self:spawn(object)
                if id then
                    if entry.action=='spawn' then result.spawned=result.spawned+1 else result.updated=result.updated+1 end
                    self:_track_synced(object)
                else table.insert(result.failed,{id=entry.id,error=err}) end
            end
        end
    end
    result.after=self:compare_runtime();result.has_changes=result.after.has_changes
    if app.logger then app.logger:info('placement','runtime_sync_complete',{removed=result.removed,updated=result.updated,spawned=result.spawned,failed=#result.failed,remaining=result.after.counts}) end
    return result,#result.failed>0 and ('Runtime sync partially failed for '..#result.failed..' object(s). See the debug log.') or nil
end

function Placement:update(delta)
    self.entities:update(delta)
    if self.app.runtime_shell then self.app.runtime_shell:update(delta) end
end

local function world_transform(t)
    local ok,result=pcall(function()
        local player=Game.GetPlayer();if not player then error('player not available') end
        local transform=player:GetWorldTransform();if not transform then error('world transform unavailable') end
        local p=(t and t.position) or {};local r=(t and t.rotation) or {}
        transform:SetPosition(ToVector4{x=p.x or 0,y=p.y or 0,z=p.z or 0,w=p.w or 1})
        local euler=ToEulerAngles{roll=r.roll or 0,pitch=r.pitch or 0,yaw=r.yaw or 0}
        transform:SetOrientation(euler:ToQuat())
        return transform
    end)
    if not ok then return nil,tostring(result) end
    return result
end

function Placement:_error(scope,message,fields)
    self.last_error=tostring(message)
    if self.app.logger then self.app.logger:error(scope,self.last_error,fields) end
    return nil,self.last_error
end

function Placement:_preview_settings()
    local s=(self.app.model and self.app.model.data and self.app.model.data.settings and self.app.model.data.settings.asset_preview) or {}
    return {
        enabled=s.enabled~=false,
        auto_on_select=s.auto_on_select~=false,
        auto_follow=s.auto_follow~=false,
        mode=s.mode or 'aim',
        distance=tonumber(s.distance) or 10.0,
        yaw_mode=s.yaw_mode or 'camera',
        surface_offset=tonumber(s.surface_offset),
        align_surface=s.align_surface==true,
        stamp_mode=s.stamp_mode==true,
        stamp_spacing=math.max(0,tonumber(s.stamp_spacing) or 0.5),
    }
end

function Placement:_preview_yaw(mode)
    local transform,err
    if mode=='player' then transform,err=self.app.game:capture_transform() else transform,err=self.app.game:capture_camera_transform() end
    if transform and transform.rotation then return tonumber(transform.rotation.yaw) or 0 end
    transform=self.app.game:capture_transform()
    if transform and transform.rotation then return tonumber(transform.rotation.yaw) or 0 end
    return 0,err
end

function Placement:_preview_transform(asset,options)
    options=options or {}
    if options.transform then
        return Util.deepcopy(options.transform), options.source or 'explicit', options.warning
    end
    local settings=self:_preview_settings()
    local mode=options.mode or settings.mode or 'aim'
    local yaw=options.yaw
    if yaw==nil then yaw=self:_preview_yaw((options.yaw_mode or settings.yaw_mode)=='player' and 'player' or 'camera') end
    local offset=options.surface_offset
    if offset==nil then
        offset=settings.surface_offset
        if offset==nil then offset=tonumber(self.app.model.data.settings.snapping.surface_offset) or 0 end
    end

    local align_surface=options.align_surface
    if align_surface==nil then align_surface=settings.align_surface end
    if mode=='player' then
        local transform,err=self.app.game:capture_transform();if not transform then return nil,err end
        transform=Util.deepcopy(transform)
        transform.rotation={roll=0,pitch=0,yaw=yaw or 0}
        return transform,'player'
    end

    local hit,err=self.app.game:aim_point(options.distance or settings.distance or 10)
    if not hit then return nil,err end
    local p=Util.deepcopy(hit.position)
    if hit.normal and offset~=0 then
        p.x=(p.x or 0)+(hit.normal.x or 0)*offset
        p.y=(p.y or 0)+(hit.normal.y or 0)*offset
        p.z=(p.z or 0)+(hit.normal.z or 0)*offset
    end
    local rotation={roll=0,pitch=0,yaw=yaw or 0}
    local warning=hit.source=='forward_fallback' and 'No surface hit; using camera forward fallback point for preview.' or nil
    if align_surface then
        if hit.normal then rotation=ViewportTools.surface_rotation(hit.normal,yaw)
        else warning='Surface alignment requested, but the aim ray has no surface normal; keeping upright rotation.' end
    end
    local transform={position=p,rotation=rotation}
    return transform,hit.source,warning,hit.normal and Util.deepcopy(hit.normal) or nil
end

function Placement:spawn(object)
    local logger=self.app.logger
    if not object then return self:_error('placement:spawn','object not found') end
    if object.enabled==false or object.visible==false then return self:_error('placement:spawn','object is disabled or hidden',{id=object.id}) end
    for _,layer in ipairs(self.app.model.data.layers or {}) do
        if layer.id==object.layer and layer.visible==false then return nil,'layer '..tostring(layer.name)..' is hidden; show the layer to spawn its objects' end
    end
    if self:is_opening_placeholder(object) then return nil,'Empty opening; no door/window asset is assigned.' end
    if procedural(self,object) then
        local shown,err=self.app.procedural:show(object);if not shown then return nil,err end
        return 'procedural:'..object.id,err
    end
    if object.runtime and object.runtime.spawned then
        if object.runtime.backend=='world_builder_primitive' or object.runtime.backend=='world_builder' then self.expected_live[object.id]=true;return object.runtime.entity_id end
        if self.entity_ids[object.id] then self.expected_live[object.id]=true;return self.entity_ids[object.id] end
    end
    if object.metadata and (object.metadata.generated==true or type(object.metadata.world_builder)=='table') then
        if not self.app.runtime_shell then return self:_error('placement:spawn','generated shell runtime backend is unavailable',{id=object.id}) end
        local runtime_id,err=self.app.runtime_shell:spawn(object)
        if not runtime_id then return self:_error('placement:spawn',err,{id=object.id,backend='world_builder'}) end
        self:_track_synced(object)
        self.expected_live[object.id]=true
        if logger then logger:info('placement:spawn','spawned',{id=object.id,backend='world_builder',entity_id=tostring(runtime_id)}) end
        return runtime_id
    end
    if object.template==nil or object.template=='' then return self:_error('placement:spawn','object has no .ent template',{id=object.id}) end
    if not exEntitySpawner or type(exEntitySpawner.Spawn)~='function' then return self:_error('placement:spawn','CET exEntitySpawner is unavailable',{id=object.id}) end
    if self.entity_ids[object.id] then
        local state,reason=self.entities:state('object:'..object.id)
        if state=='failed' or state=='missing' then return nil,reason end
        if logger then logger:debug('placement:spawn','already_spawned',{id=object.id,entity_id=tostring(self.entity_ids[object.id])}) end
        return self.entity_ids[object.id]
    end
    local transform,err=world_transform(object.transform);if not transform then return self:_error('placement:spawn',err,{id=object.id}) end
    local entity_id,spawn_err=self.entities:request('object:'..object.id,object.template,transform,object.appearance,object)
    if not entity_id then return self:_error('placement:spawn',spawn_err,{id=object.id,template=object.template}) end
    self.entity_ids[object.id]=entity_id;self.last_error=nil
    self:_track_synced(object)
    self.expected_live[object.id]=true
    if logger then logger:info('placement:spawn','request_accepted',{id=object.id,template=object.template,status=object.runtime.status,entity_id=tostring(entity_id)}) end
    return entity_id
end

function Placement:spawn_transient(key,template,appearance,transform)
    if not template or template=='' then return nil,'marker template is not configured' end
    if not exEntitySpawner or type(exEntitySpawner.Spawn)~='function' then return nil,'CET exEntitySpawner is unavailable' end
    local clear_ok,clear_err=self:despawn_transient(key);if not clear_ok then return nil,clear_err end
    local world,err=world_transform(transform);if not world then return nil,err end
    local entity_id,spawn_err=self.entities:request('transient:'..key,template,world,appearance)
    if not entity_id then self.last_error=spawn_err;return nil,spawn_err end
    self.transient_ids[key]=entity_id;return entity_id
end

function Placement:despawn_transient(key)
    local id=self.transient_ids[key];if not id then return true end
    local ok,err=self.entities:remove('transient:'..key)
    if not ok then return false,err end
    self.transient_ids[key]=nil
    if key=='asset_preview' and self.preview then self.preview.entity_id=nil;self.preview.active=false end
    return true
end

function Placement:clear_transients()
    local keys={};for key in pairs(self.transient_ids) do table.insert(keys,key) end
    local failed={};for _,key in ipairs(keys) do local ok,err=self:despawn_transient(key);if not ok then table.insert(failed,{key=key,error=err}) end end
    self.preview=nil
    return {cleared=true,failed=failed}
end

function Placement:spawn_test_asset(asset_id)
    local asset=self.app.model:get_asset(asset_id or 'builtin_chair_poor')
    if not asset then return nil,'starter test asset not found' end
    local transform,source,warning=self:_preview_transform(asset,{mode='aim',distance=5,follow=false})
    if not transform then return nil,source end
    local entity_id,err=self:spawn_transient('runtime_self_test',asset.template,asset.appearance,transform)
    if not entity_id then return nil,err end
    if self.app.logger then self.app.logger:info('placement:self_test','spawned',{asset_id=asset.id,entity_id=tostring(entity_id),source=source}) end
    return {asset_id=asset.id,entity_id=tostring(entity_id),source=source,status=self.entities:state('transient:runtime_self_test')},warning
end

function Placement:clear_test_asset()
    local ok,err=self:despawn_transient('runtime_self_test')
    if ok and self.app.logger then self.app.logger:info('placement:self_test','cleared') end
    return ok,err
end

function Placement:preview_status()
    if not self.preview then return {active=false,last_error=self.last_error} end
    local p=self.preview
    local stroke=self.app.stamp_session and self.app.stamp_session:status() or {active=false}
    local state,reason
    if p.backend=='world_builder' then state=self.app.runtime_shell and self.app.runtime_shell.preview_object and 'confirmed' or 'missing'
    else state,reason=self.entities:state('transient:asset_preview') end
    return {
        active=p.active==true and state~='failed' and state~='missing', status=state, confirmed=state=='confirmed', asset_id=p.asset_id, asset_name=p.asset_name, template=p.template, appearance=p.appearance,
        mode=p.mode, distance=p.distance, source=p.source, entity_id=p.entity_id and tostring(p.entity_id) or nil,
        transform=Util.deepcopy(p.transform), normal=Util.deepcopy(p.normal),follow=p.follow==true,
        align_surface=p.align_surface==true,stamp_mode=p.stamp_mode==true,stamp_spacing=p.stamp_spacing,placed_count=stroke.active and stroke.count or (p.placed_count or 0),
        stroke_active=stroke.active==true,stroke=stroke.active and stroke or nil,
        last_stamp_position=Util.deepcopy(p.last_stamp_position),last_error=reason or p.last_error or self.last_error,last_warning=p.last_warning,
    }
end

function Placement:preview_asset(asset_or_id,options)
    options=options or {}
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before changing the preview.' end
    local asset=type(asset_or_id)=='table' and asset_or_id or self.app.model:get_asset(asset_or_id)
    if not asset then return nil,'asset not found' end
    local is_wb=asset.metadata and type(asset.metadata.world_builder)=='table'
    if not is_wb and Util.trim(asset.template)=='' then return nil,'asset has no .ent template' end
    local settings=self:_preview_settings()
    local align_surface=options.align_surface;if align_surface==nil then align_surface=settings.align_surface end
    local stamp_mode=options.stamp_mode;if stamp_mode==nil then stamp_mode=settings.stamp_mode end
    local stamp_spacing=math.max(0,tonumber(options.stamp_spacing) or settings.stamp_spacing)
    local transform,source,warning,normal=self:_preview_transform(asset,options)
    if not transform then return nil,source end
    local entity_id,err
    if is_wb then entity_id,err=self.app.runtime_shell:preview_asset(asset,transform)
    else entity_id,err=self:spawn_transient('asset_preview',asset.template,asset.appearance,transform) end
    if not entity_id then return nil,err end
    self.preview={
        active=true,asset_id=asset.id,asset_name=asset.name,template=asset.template,appearance=asset.appearance,
        mode=options.mode or settings.mode,distance=tonumber(options.distance) or settings.distance,
        source=source,entity_id=entity_id,transform=Util.deepcopy(transform),normal=normal,follow=options.follow==true,last_warning=warning,last_error=nil,backend=is_wb and 'world_builder' or 'entity_spawner',
        yaw=transform.rotation and transform.rotation.yaw or 0,surface_offset=options.surface_offset,
        align_surface=align_surface==true,stamp_mode=stamp_mode==true,stamp_spacing=stamp_spacing,placed_count=0,last_stamp_position=nil,
    }
    self.last_error=nil
    if self.app.logger then self.app.logger:info('placement:preview','spawned',{asset_id=asset.id,name=asset.name,source=source,entity_id=tostring(entity_id),follow=options.follow==true,align_surface=align_surface==true,stamp_mode=stamp_mode==true,stamp_spacing=stamp_spacing}) end
    return self:preview_status(),warning
end

function Placement:update_preview(force)
    if not self.preview or not self.preview.asset_id then return nil end
    if not force and self.preview.follow~=true then return self:preview_status() end
    local state=self.preview.backend=='world_builder' and 'confirmed' or self.entities:state('transient:asset_preview')
    if state=='pending' or state=='failed' or state=='missing' then return self:preview_status() end
    local now=os.clock()
    if not force and now-(self.last_preview_refresh or 0)<0.12 then return self:preview_status() end
    self.last_preview_refresh=now
    local asset=self.app.model:get_asset(self.preview.asset_id)
    if not asset then
        self:clear_preview()
        return nil,'preview asset no longer exists'
    end
    -- Passing self.preview used to reuse its .transform before a raycast ran.
    -- Only pass placement options so every follow update samples the camera.
    local transform,source,warning,normal=self:_preview_transform(asset,{mode=self.preview.mode,distance=self.preview.distance,surface_offset=self.preview.surface_offset,align_surface=self.preview.align_surface})
    if not transform then self.preview.last_error=source;return nil,source end
    local current=self.preview.transform or {}
    local moved=(not current.position) or Util.distance3(current.position,transform.position)>=0.03
    local rotated=(not current.rotation)
        or math.abs((current.rotation.roll or 0)-(transform.rotation.roll or 0))>=0.5
        or math.abs((current.rotation.pitch or 0)-(transform.rotation.pitch or 0))>=0.5
        or math.abs((current.rotation.yaw or 0)-(transform.rotation.yaw or 0))>=0.5
    if not force and not moved and not rotated then return self:preview_status() end
    local entity_id,err
    if self.preview.backend=='world_builder' then entity_id,err=self.app.runtime_shell:update_preview(transform)
    else entity_id,err=self:spawn_transient('asset_preview',asset.template,asset.appearance,transform) end
    if not entity_id then self.preview.last_error=err;return nil,err end
    self.preview.active=true;self.preview.entity_id=entity_id;self.preview.transform=Util.deepcopy(transform);self.preview.normal=normal;self.preview.source=source;self.preview.last_warning=warning;self.preview.last_error=nil
    if self.app.logger then self.app.logger:debug('placement:preview','updated',{asset_id=asset.id,source=source,entity_id=tostring(entity_id)}) end
    return self:preview_status(),warning
end

function Placement:_clear_preview()
    local had=self.preview~=nil
    local ok,err
    if self.preview and self.preview.backend=='world_builder' then ok,err=self.app.runtime_shell:clear_preview()
    else ok,err=self:despawn_transient('asset_preview') end
    if not ok then return nil,err end
    self.preview=nil
    if had and self.app.logger then self.app.logger:info('placement:preview','cleared') end
    return {cleared=true}
end

function Placement:clear_preview()
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before clearing its preview.' end
    return self:_clear_preview()
end

function Placement:start_stamp(asset_or_id,options)
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before starting another.' end
    if self.app.transform_session and self.app.transform_session:is_active() then return nil,'Commit or cancel the active transform session before starting a stamp stroke.' end
    options=Util.deepcopy(options or {});options.stamp_mode=true;options.follow=true
    local asset=type(asset_or_id)=='table' and asset_or_id or self.app.model:get_asset(asset_or_id)
    if not asset then return nil,'asset not found' end
    local preview,err=self:preview_asset(asset,options);if not preview then return nil,err end
    if not self.app.stamp_session then self:_clear_preview();return nil,'stamp transaction module is unavailable' end
    local started,start_err=self.app.stamp_session:begin(asset,options)
    if not started then self:_clear_preview();return nil,start_err end
    return self:preview_status(),err
end

function Placement:place_previewed(premise_id,room_id,options)
    options=options or {}
    if not self.preview or not self.preview.asset_id or not self.preview.transform then return nil,'no asset preview is active' end
    local status=Util.deepcopy(self.preview)
    local keep_preview=options.keep_preview
    if keep_preview==nil then keep_preview=status.stamp_mode==true end
    if status.stamp_mode==true then
        if not self.app.stamp_session or not self.app.stamp_session:is_active() then return nil,'start a stamp stroke first' end
        local object,err=self.app.stamp_session:add({transform=status.transform,stamp_spacing=options.stamp_spacing or status.stamp_spacing})
        if object then self:update_preview(true) end
        return object,err
    end
    local spacing=math.max(0,tonumber(options.stamp_spacing) or tonumber(status.stamp_spacing) or 0)
    if keep_preview and status.last_stamp_position and spacing>0 then
        local distance=Util.distance3(status.last_stamp_position,status.transform.position)
        if distance<spacing then
            local message=string.format('Move the preview at least %.2f m before stamping again (current %.2f m).',spacing,distance)
            self.preview.last_error=message;self.last_error=message
            if self.app.logger then self.app.logger:warn('placement:stamp','spacing_blocked',{asset_id=status.asset_id,required=spacing,distance=distance}) end
            return nil,message
        end
    end
    local object,err=self.app.actions:place_asset(status.asset_id,'preview',{premise_id=premise_id,room_id=room_id,transform=status.transform,distance=status.distance})
    if object then
        if keep_preview then
            self.preview.last_stamp_position=Util.deepcopy(status.transform.position)
            self.preview.placed_count=(tonumber(status.placed_count) or 0)+1
            self.preview.last_error=nil;self.last_error=nil
            if self.app.logger then self.app.logger:info('placement:stamp','placed',{asset_id=status.asset_id,object_id=object.id,count=self.preview.placed_count,spacing=spacing}) end
            self:update_preview(true)
        else self:clear_preview() end
    end
    return object,err
end

function Placement:stamp_once(premise_id,room_id)
    if not self.preview or self.preview.stamp_mode~=true then return nil,'start a stamp preview first' end
    return self:place_previewed(premise_id,room_id,{keep_preview=true})
end

function Placement:stop_stamp()
    if self.app.stamp_session and self.app.stamp_session:is_active() then return self.app.stamp_session:commit() end
    return self:clear_preview()
end

function Placement:despawn(object)
    if not object then return false,'object not found',false end
    if procedural(self,object) then local was=self.app.procedural:is_shown(object);self.app.procedural:hide(object);return true,nil,was end
    if object.runtime and (object.runtime.backend=='world_builder_primitive' or object.runtime.backend=='world_builder') and self.app.runtime_shell then
        local ok,err,did=self.app.runtime_shell:despawn(object)
        if not ok then return false,err,false end
        self.expected_live[object.id]=nil
        return true,nil,did==true
    end
    local id=self.entity_ids[object.id]
    if not id then object.runtime={spawned=false,backend=nil,entity_id=nil};self.expected_live[object.id]=nil;return true,nil,false end
    local ok,err,found=self.entities:remove('object:'..object.id)
    if not ok then self.last_error=tostring(err);if self.app.logger then self.app.logger:error('placement:despawn','failed',{id=object.id,error=self.last_error}) end;return false,self.last_error,false end
    self.entity_ids[object.id]=nil;object.runtime={spawned=false,backend=nil,entity_id=nil};self.last_error=nil
    self.expected_live[object.id]=nil
    if self.app.logger then self.app.logger:info('placement:despawn',found and 'despawned' or 'entity_already_missing',{id=object.id,entity_id=tostring(id)}) end
    return true,nil,found
end

function Placement:refresh(object)
    local ok,err=self:despawn(object);if not ok then return nil,err end
    return self:spawn(object)
end

function Placement:spawn_premise(premise_id)
    local spawned,failed={},{};local visible_layers={}
    for _,layer in ipairs(self.app.model.data.layers or {}) do visible_layers[layer.id]=layer.visible~=false end
    for _,object in ipairs(self.app.model.data.objects) do
        if object.premise_id==premise_id and object.enabled and object.visible and visible_layers[object.layer]~=false and not self:is_opening_placeholder(object) then
            local id,err=self:spawn(object)
            if id then table.insert(spawned,{object_id=object.id,entity_id=tostring(id)}) else table.insert(failed,{object_id=object.id,error=err}) end
        end
    end
    if self.app.logger then self.app.logger:info('placement:premise','spawn_complete',{premise_id=premise_id,spawned=#spawned,failed=#failed}) end
    return {spawned=spawned,failed=failed}
end

function Placement:spawn_room_shell(room_id)
    local room=self.app.model:get_room(room_id);if not room then return nil,'room not found' end
    local spawned,failed={},{}
    for _,id in ipairs(room.shell_object_ids or {}) do
        local object=self.app.model:get_object(id)
        if object and object.enabled~=false and object.visible~=false and not self:is_opening_placeholder(object) then
            local runtime_id,err=self:spawn(object)
            if runtime_id then table.insert(spawned,{object_id=object.id,entity_id=tostring(runtime_id)}) else table.insert(failed,{object_id=object.id,error=err}) end
        end
    end
    if self.app.logger then self.app.logger:info('placement:room_shell','spawn_complete',{room_id=room_id,spawned=#spawned,failed=#failed}) end
    if #spawned==0 then
        local reason=failed[1] and failed[1].error or 'room shell contains no spawnable pieces'
        return nil,reason,{spawned=spawned,failed=failed}
    end
    local warning=#failed>0 and string.format('%d shell piece(s) failed; see DEBUG LOG.',#failed) or nil
    return {room_id=room_id,spawned=spawned,failed=failed},warning
end

function Placement:spawn_all_shells(premise_id)
    local total,failed,rooms=0,{},0
    for _,room in ipairs(self.app.model.data.rooms or {}) do
        if (not premise_id) or room.premise_id==premise_id then
            rooms=rooms+1
            local result,err,detail=self:spawn_room_shell(room.id)
            if result then total=total+#result.spawned;for _,f in ipairs(result.failed) do table.insert(failed,f) end
            else table.insert(failed,{room_id=room.id,error=err,detail=detail}) end
        end
    end
    if total==0 then return nil,(failed[1] and failed[1].error or 'no room shell geometry was spawned'),{rooms=rooms,failed=failed} end
    return {rooms=rooms,spawned=total,failed=failed},(#failed>0 and tostring(#failed)..' room/shell failure(s); see DEBUG LOG.' or nil)
end

function Placement:despawn_premise(premise_id)
    local count=0;local failed={}
    for _,object in ipairs(self.app.model.data.objects) do
        if object.premise_id==premise_id then
            local ok,err,did=self:despawn(object)
            if ok and did then count=count+1 elseif not ok then table.insert(failed,{object_id=object.id,error=err}) end
        end
    end
    if self.app.logger then self.app.logger:info('placement:premise','despawn_complete',{premise_id=premise_id,despawned=count,failed=#failed}) end
    return {despawned=count,failed=failed}
end

function Placement:despawn_all()
    local failed={};local count=0
    for _,object in ipairs(self.app.model.data.objects) do local ok,err,did=self:despawn(object);if ok and did then count=count+1 elseif not ok then table.insert(failed,{object_id=object.id,error=err}) end end
    local transient=self:clear_transients();for _,item in ipairs(transient.failed) do table.insert(failed,item) end
    if self.app.logger then self.app.logger:info('placement','despawn_all',{despawned=count,failed=#failed}) end
    return {despawned=count,failed=failed}
end

function Placement:reconcile_runtime()
    local report={direct_confirmed=0,direct_missing=0,world_builder_preserved=0,world_builder_missing=0,transient_preserved=0,failed={}}
    for _,object in ipairs(self.app.model.data.objects or {}) do
        if self.entity_ids[object.id] then
            local record=self.entities.records['object:'..object.id]
            if record then
                record.object=object;record.object_id=object.id
                local entity,err=self.entities:_find(record)
                if entity then self.entities:_state(record,'confirmed');report.direct_confirmed=report.direct_confirmed+1
                else self.entities:_state(record,'missing',err or 'Live entity ID no longer resolves after reload.');report.direct_missing=report.direct_missing+1 end
            end
        elseif self.app.runtime_shell and self.app.runtime_shell.handles[object.id] then
            object.runtime={spawned=true,status='confirmed',backend='world_builder',entity_id='wb:'..object.id}
            report.world_builder_preserved=report.world_builder_preserved+1
        elseif object.runtime and object.runtime.backend=='world_builder' and object.runtime.spawned then
            object.runtime={spawned=false,status='missing',backend='world_builder',entity_id='wb:'..object.id,error='World Builder handle was not retained across reload; object was not respawned.'}
            report.world_builder_missing=report.world_builder_missing+1
        end
    end
    for _ in pairs(self.transient_ids) do report.transient_preserved=report.transient_preserved+1 end
    self.last_error=nil
    if report.direct_missing+report.world_builder_missing>0 then
        self.last_error='Runtime reconciliation found '..tostring(report.direct_missing+report.world_builder_missing)..' saved live object(s) without a verified handle.'
    end
    if self.app.logger then self.app.logger:info('placement','runtime_reconciled',report) end
    return report
end

function Placement:status()
    local count=0;for _ in pairs(self.entity_ids) do count=count+1 end
    local transient=0;for _ in pairs(self.transient_ids) do transient=transient+1 end
    local shell=self.app.runtime_shell and self.app.runtime_shell:status(false) or {available=false,spawned=0,reason='runtime shell module unavailable'}
    local entities=self.entities:status()
    return {supported=exEntitySpawner~=nil and type(exEntitySpawner.Spawn)=='function',despawn_supported=exEntitySpawner~=nil and type(exEntitySpawner.Despawn)=='function',spawned=count+(shell.spawned or 0),entity_spawned=count,shell_spawned=shell.spawned or 0,entities=entities,self_test=self.entities:state('transient:runtime_self_test'),markers=transient,last_error=self.last_error or entities.last_error,preview=self:preview_status(),runtime_shell=shell}
end

return Placement
