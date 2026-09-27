local Util=require('modules/util')

local StampSession={}
StampSession.__index=StampSession

local function number(value,fallback) return tonumber(value) or fallback or 0 end

local function restore_selection(app,prior)
    prior=prior or {}
    if not app.selection then return end
    if prior.kind and prior.kind~='object' and prior.id then
        app.selection:set(prior.kind,prior.id)
    elseif prior.kind=='object' then
        app.selection:set_object_group(prior.ids or {},prior.active_id or prior.id,prior.group_source or 'locationstudio')
    else
        app.selection:clear()
    end
    app.active_object_group_id=prior.active_group_id
end

local function stamped_value(asset,session,transform,index)
    local metadata=Util.deepcopy(asset.metadata or {})
    if metadata.room_kit==true then
        metadata.generated=false;metadata.room_kit=false;metadata.detached_from_room=true
        metadata.detached_at=Util.now_iso()
    end
    metadata.source='stamp:asset:'..tostring(asset.id)
    metadata.stamp_asset_id=asset.id
    metadata.locationstudio_asset_id=asset.id
    metadata.stamp_index=index
    return {
        premise_id=session.premise_id,room_id=session.room_id,
        name=asset.name,kind=asset.kind,template=asset.template,appearance=asset.appearance,
        layer=metadata.detached_from_room and 'decoration' or asset.layer,size=Util.deepcopy(asset.size),
        enabled=true,visible=true,locked=false,properties={},metadata=metadata,
        transform=Util.deepcopy(transform),
    }
end

function StampSession.new(app)
    return setmetatable({app=app,session=nil,last_error=nil,last_result=nil},StampSession)
end

function StampSession:is_active() return self.session~=nil end

function StampSession:begin(asset,args)
    args=args or {}
    if self.session then return nil,'a stamp stroke is already active' end
    if self.app.transform_session and self.app.transform_session:is_active() then return nil,'Commit or cancel the active transform session before starting a stamp stroke.' end
    if not asset then return nil,'asset not found' end
    local is_wb=asset.metadata and type(asset.metadata.world_builder)=='table'
    if not is_wb and Util.trim(asset.template)=='' then return nil,'asset has no spawnable game resource' end
    local premise_id=args.premise_id or self.app.selected_premise_id
    if not premise_id or not self.app.model:get_premise(premise_id) then return nil,'Select a location before starting a stamp stroke.' end
    local room_id=args.room_id or self.app.selected_room_id
    if room_id and room_id~='' then
        local room=self.app.model:get_room(room_id)
        if not room or room.premise_id~=premise_id then return nil,'The stamp room does not belong to the active location.' end
    else room_id=nil end
    local selection=self.app.selection
    local selection_before={
        kind=selection and selection.kind,id=selection and selection.id,
        ids=selection and Util.deepcopy(selection.object_ids) or {},
        active_id=selection and selection.id,group_source=selection and selection.group_source,
        active_group_id=self.app.active_object_group_id,
    }
    self.session={
        asset_id=asset.id,asset_name=asset.name,premise_id=premise_id,room_id=room_id,
        spacing=math.max(0,number(args.stamp_spacing,0.5)),created_ids={},last_position=nil,
        history_before=Util.deepcopy(self.app.model.data),selection_before=selection_before,
        dirty_before=self.app.dirty==true,dirty_since_before=self.app.dirty_since,
        started_at=Util.now_iso(),failed={},last_error=nil,
    }
    self.last_error=nil
    if self.app.logger then self.app.logger:info('stamp:stroke','started',{asset_id=asset.id,asset_name=asset.name,premise_id=premise_id,room_id=room_id,spacing=self.session.spacing}) end
    return self:status()
end

function StampSession:add(args)
    args=args or {}
    local s=self.session;if not s then return nil,'no stamp stroke is active' end
    local asset=self.app.model:get_asset(s.asset_id);if not asset then return nil,'stamp asset no longer exists' end
    local preview=self.app.placement.preview
    local transform=args.transform or (preview and preview.transform)
    if not transform or not transform.position then return nil,'stamp preview has no valid transform' end
    if preview and preview.asset_id~=s.asset_id then return nil,'active preview does not match the stamp asset' end
    local spacing=math.max(0,number(args.stamp_spacing,s.spacing));s.spacing=spacing
    if s.last_position and spacing>0 then
        local distance=Util.distance3(s.last_position,transform.position)
        if distance<spacing then
            local message=string.format('Move the preview at least %.2f m before stamping again (current %.2f m).',spacing,distance)
            s.last_error=message;self.last_error=message
            if preview then preview.last_error=message end
            if self.app.logger then self.app.logger:warn('stamp:stroke','spacing_blocked',{asset_id=s.asset_id,required=spacing,distance=distance,count=#s.created_ids}) end
            return nil,message
        end
    end
    if #s.created_ids>=200 then return nil,'A stamp stroke is limited to 200 objects; commit it before starting another.' end

    local project_updated=self.app.model.data.project.updated_at
    local values,add_err=self.app.model:add_objects({stamped_value(asset,s,transform,#s.created_ids+1)},true)
    local object=values and values[1]
    if not object then return nil,add_err or 'could not create stamped object' end
    local runtime_id,spawn_err=self.app.placement:spawn(object)
    if not runtime_id then
        for index=#self.app.model.data.objects,1,-1 do if self.app.model.data.objects[index].id==object.id then table.remove(self.app.model.data.objects,index);break end end
        self.app.model.data.project.updated_at=project_updated
        s.last_error='Stamp was not added because live spawning failed: '..tostring(spawn_err);self.last_error=s.last_error
        if self.app.logger then self.app.logger:error('stamp:stroke','spawn_failed',{asset_id=s.asset_id,object_id=object.id,error=spawn_err}) end
        return nil,s.last_error
    end
    table.insert(s.created_ids,object.id);s.last_position=Util.deepcopy(transform.position);s.last_error=nil;self.last_error=nil
    if preview then preview.last_stamp_position=Util.deepcopy(s.last_position);preview.placed_count=#s.created_ids;preview.last_error=nil end
    if self.app.logger then self.app.logger:info('stamp:stroke','stamped',{asset_id=s.asset_id,object_id=object.id,count=#s.created_ids,spacing=spacing,entity_id=tostring(runtime_id)}) end
    return object
end

function StampSession:commit()
    local s=self.session;if not s then return nil,'no stamp stroke is active' end
    local asset=self.app.model:get_asset(s.asset_id);if not asset then return nil,'stamp asset no longer exists' end
    local cleared,clear_err=self.app.placement:_clear_preview()
    if not cleared then
        s.last_error='Stamp commit is waiting because the preview could not be removed: '..tostring(clear_err);self.last_error=s.last_error
        if self.app.logger then self.app.logger:error('stamp:stroke','commit_blocked',{count=#s.created_ids,error=clear_err}) end
        return nil,s.last_error
    end
    local count=#s.created_ids
    if count>0 then
        self.app.model:mark_asset_used(s.asset_id)
        self.app.model:push_history(s.history_before,'Stamp stroke ('..count..' object'..(count==1 and '' or 's')..')');self.app.model:touch()
        if self.app.selection then self.app.selection:set_object_group(s.created_ids,s.created_ids[#s.created_ids],'stamp_stroke') end
        self.app:mark_dirty()
    else
        restore_selection(self.app,s.selection_before)
        self.app.dirty=s.dirty_before==true;self.app.dirty_since=s.dirty_since_before or self.app.dirty_since
        if s.history_before and s.history_before.project then self.app.model.data.project.updated_at=s.history_before.project.updated_at end
    end
    local result={committed=true,changed=count>0,count=count,created_ids=Util.deepcopy(s.created_ids),asset_id=s.asset_id,premise_id=s.premise_id,room_id=s.room_id,failed={}}
    self.session=nil;self.last_result=Util.deepcopy(result);self.last_error=nil
    if self.app.logger then self.app.logger:info('stamp:stroke','committed',{asset_id=result.asset_id,count=count,created_ids=result.created_ids}) end
    return result
end

function StampSession:cancel()
    local s=self.session;if not s then return nil,'no stamp stroke is active' end
    local failed={}
    for _,id in ipairs(s.created_ids) do
        local object=self.app.model:get_object(id)
        if object then local ok,err=self.app.placement:despawn(object);if not ok then table.insert(failed,{id=id,error=tostring(err)}) end end
    end
    if #failed>0 then
        s.failed=failed;s.last_error='Stamp cancel retained the stroke because '..tostring(#failed)..' live object(s) could not be removed.';self.last_error=s.last_error
        if self.app.logger then self.app.logger:error('stamp:stroke','cancel_blocked',{count=#s.created_ids,failed=failed}) end
        return nil,s.last_error
    end
    local cleared,clear_err=self.app.placement:_clear_preview()
    if not cleared then
        s.last_error='Stamp cancel retained the stroke because the preview could not be removed: '..tostring(clear_err);self.last_error=s.last_error
        if self.app.logger then self.app.logger:error('stamp:stroke','cancel_blocked',{count=#s.created_ids,error=clear_err}) end
        return nil,s.last_error
    end
    local remove={};for _,id in ipairs(s.created_ids) do remove[id]=true end
    local kept={};for _,object in ipairs(self.app.model.data.objects) do if not remove[object.id] then table.insert(kept,object) end end
    self.app.model.data.objects=kept
    if s.history_before and s.history_before.project then self.app.model.data.project.updated_at=s.history_before.project.updated_at end
    restore_selection(self.app,s.selection_before)
    self.app.dirty=s.dirty_before==true;self.app.dirty_since=s.dirty_since_before or self.app.dirty_since
    local result={cancelled=true,count=#s.created_ids,created_ids=Util.deepcopy(s.created_ids),asset_id=s.asset_id,premise_id=s.premise_id,room_id=s.room_id,failed={}}
    self.session=nil;self.last_result=Util.deepcopy(result);self.last_error=nil
    if self.app.logger then self.app.logger:info('stamp:stroke','cancelled',{asset_id=result.asset_id,count=result.count,removed=result.count}) end
    return result
end

function StampSession:status()
    local s=self.session
    if not s then return {active=false,last_error=self.last_error,last_result=Util.deepcopy(self.last_result)} end
    return {
        active=true,asset_id=s.asset_id,asset_name=s.asset_name,premise_id=s.premise_id,room_id=s.room_id,
        count=#s.created_ids,created_ids=Util.deepcopy(s.created_ids),spacing=s.spacing,
        last_position=Util.deepcopy(s.last_position),started_at=s.started_at,
        failed=Util.deepcopy(s.failed),last_error=s.last_error,
    }
end

return StampSession
