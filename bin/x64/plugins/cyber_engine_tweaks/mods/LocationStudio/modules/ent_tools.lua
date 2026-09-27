local Util=require('modules/util')

local EntTools={}
EntTools.__index=EntTools

local TRANSFORM_KINDS={premise=true,room=true,object=true,volume=true,camera=true,location=true}

function EntTools.new(app)
    return setmetatable({
        app=app,
        clipboard={position=nil,rotation=nil,transform=nil},
        target_kind=nil,target_id=nil,
        last_warning=nil,
    },EntTools)
end

function EntTools:_log(level,scope,message,fields)
    local logger=self.app and self.app.logger
    if logger and logger[level] then logger[level](logger,'ent_tools:'..scope,message,fields) end
end

function EntTools:_resolve(kind,id)
    if not TRANSFORM_KINDS[kind] then return nil,'selection has no transform' end
    local item=self.app.selection:resolve(kind,id)
    if not item or not item.transform then return nil,'item not found or has no transform' end
    return item
end

function EntTools:_selected()
    local kind,id=self.app.selection.kind,self.app.selection.id
    if not kind or not id then return nil,nil,'select a transformable scene item first' end
    local item,err=self:_resolve(kind,id)
    if not item then return nil,nil,err end
    return kind,item
end

function EntTools:_refresh_object(object)
    if object and self.app.placement:is_tracked(object) then
        local _,err=self.app.placement:refresh(object)
        if err then self:_log('warn','live_refresh','object_refresh_failed',{id=object.id,error=tostring(err)});return false,err end
    end
    return true
end

function EntTools:refresh_live_scope(kind,id)
    local failures={}
    if kind=='object' then
        local object=self.app.model:get_object(id)
        local ok,err=self:_refresh_object(object);if not ok then table.insert(failures,{id=id,error=tostring(err)}) end
    elseif kind=='room' then
        for _,object in ipairs(self.app.model.data.objects) do
            if object.room_id==id and self.app.placement:is_tracked(object) then
                local ok,err=self:_refresh_object(object);if not ok then table.insert(failures,{id=object.id,error=tostring(err)}) end
            end
        end
    elseif kind=='premise' then
        for _,object in ipairs(self.app.model.data.objects) do
            if object.premise_id==id and self.app.placement:is_tracked(object) then
                local ok,err=self:_refresh_object(object);if not ok then table.insert(failures,{id=object.id,error=tostring(err)}) end
            end
        end
    end
    if #failures>0 then return false,string.format('%d live preview object(s) failed to refresh',#failures),failures end
    return true
end

function EntTools:_after_transform(kind,item)
    local ok,warning=self:refresh_live_scope(kind,item.id)
    self.last_warning=ok and nil or warning
    return item,warning
end

function EntTools:copy(part,kind,id)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local t=item.transform
    if part=='position' then self.clipboard.position=Util.deepcopy(t.position)
    elseif part=='rotation' then self.clipboard.rotation=Util.deepcopy(t.rotation)
    else
        self.clipboard.transform=Util.deepcopy(t)
        self.clipboard.position=Util.deepcopy(t.position)
        self.clipboard.rotation=Util.deepcopy(t.rotation)
        part='transform'
    end
    self:_log('info','copy','copied',{kind=kind,id=id,part=part})
    return {copied=true,kind=kind,id=id,part=part}
end

function EntTools:paste(part,kind,id)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local next_transform=Util.deepcopy(item.transform)
    if part=='position' then
        if not self.clipboard.position then return nil,'position clipboard is empty' end
        next_transform.position=Util.deepcopy(self.clipboard.position)
    elseif part=='rotation' then
        if not self.clipboard.rotation then return nil,'rotation clipboard is empty' end
        next_transform.rotation=Util.deepcopy(self.clipboard.rotation)
    else
        if not self.clipboard.transform then return nil,'transform clipboard is empty' end
        next_transform=Util.deepcopy(self.clipboard.transform);part='transform'
    end
    local updated;updated,err=self.app.authoring:set_transform(kind,id,next_transform,true)
    if not updated then return nil,err end
    self:_log('info','paste','pasted',{kind=kind,id=id,part=part})
    return self:_after_transform(kind,updated)
end

function EntTools:reset_rotation(kind,id)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local t=Util.deepcopy(item.transform);t.rotation={roll=0,pitch=0,yaw=0}
    local updated;updated,err=self.app.authoring:set_transform(kind,id,t,true);if not updated then return nil,err end
    self:_log('info','reset_rotation','complete',{kind=kind,id=id})
    return self:_after_transform(kind,updated)
end

function EntTools:move_to_player(kind,id,copy_rotation)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local player;player,err=self.app.game:capture_transform();if not player then return nil,err end
    local t=Util.deepcopy(item.transform);t.position=Util.deepcopy(player.position)
    if copy_rotation then t.rotation=Util.deepcopy(player.rotation) end
    local updated;updated,err=self.app.authoring:set_transform(kind,id,t,true);if not updated then return nil,err end
    self:_log('info','move_to_player','complete',{kind=kind,id=id,copy_rotation=copy_rotation==true})
    return self:_after_transform(kind,updated)
end

function EntTools:move_to_aim(kind,id,distance)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local hit;hit,err=self.app.game:aim_point(distance or 10);if not hit then return nil,err end
    local t=Util.deepcopy(item.transform);t.position=Util.deepcopy(hit.position)
    local updated;updated,err=self.app.authoring:set_transform(kind,id,t,true);if not updated then return nil,err end
    self:_log('info','move_to_aim','complete',{kind=kind,id=id,source=hit.source})
    local result,warning=self:_after_transform(kind,updated)
    return result,warning or (hit.source=='forward_fallback' and 'No surface hit; used camera forward fallback.' or nil)
end

function EntTools:drop_to_ground(kind,id,max_distance,offset)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local hit;hit,err=self.app.game:ground_below(item.transform.position,max_distance or 50,offset or self.app.model.data.settings.snapping.surface_offset)
    if not hit then return nil,err end
    local t=Util.deepcopy(item.transform);t.position=Util.deepcopy(hit.position)
    local updated;updated,err=self.app.authoring:set_transform(kind,id,t,true);if not updated then return nil,err end
    self:_log('info','drop_to_ground','complete',{kind=kind,id=id,source=hit.source})
    return self:_after_transform(kind,updated)
end

function EntTools:teleport_player_to(kind,id)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local ok;ok,err=self.app.game:teleport(item.transform);if not ok then return nil,err end
    self:_log('info','teleport_player','complete',{kind=kind,id=id})
    return {teleported=true,kind=kind,id=id}
end

function EntTools:set_target(kind,id)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    self.target_kind=kind;self.target_id=id
    self:_log('info','target','set',{kind=kind,id=id})
    return {target_kind=kind,target_id=id,name=item.name}
end

function EntTools:clear_target()
    self.target_kind=nil;self.target_id=nil;self:_log('debug','target','cleared');return {cleared=true}
end

function EntTools:get_target()
    if not self.target_kind or not self.target_id then return nil end
    local item=self.app.selection:resolve(self.target_kind,self.target_id)
    if not item then self.target_kind=nil;self.target_id=nil;return nil end
    return {kind=self.target_kind,id=self.target_id,item=item}
end

function EntTools:_aim_at_position(kind,id,target_position,target_ref)
    local item,err=self:_resolve(kind,id);if not item then return nil,err end
    local t=Util.deepcopy(item.transform);t.rotation=Util.look_at_rotation(t.position,target_position)
    local updated;updated,err=self.app.authoring:set_transform(kind,id,t,false);if not updated then return nil,err end
    if kind=='camera' then
        updated.look_at=Util.deepcopy(target_position)
        if target_ref and target_ref.kind=='location' then updated.look_at.location_id=target_ref.id end
        updated.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    end
    self:_log('info','aim','complete',{kind=kind,id=id,target_kind=target_ref and target_ref.kind or 'world',target_id=target_ref and target_ref.id or nil})
    return self:_after_transform(kind,updated)
end

function EntTools:aim_at_target(kind,id,target_kind,target_id)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    target_kind=target_kind or self.target_kind;target_id=target_id or self.target_id
    if not target_kind or not target_id then return nil,'no target is set' end
    if kind==target_kind and id==target_id then return nil,'source and target are the same item' end
    local target,err=self:_resolve(target_kind,target_id);if not target then return nil,err end
    return self:_aim_at_position(kind,id,target.transform.position,{kind=target_kind,id=target_id})
end

function EntTools:aim_at_player(kind,id)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local t,err=self.app.game:capture_transform();if not t then return nil,err end
    return self:_aim_at_position(kind,id,t.position,{kind='player',id='player'})
end

function EntTools:aim_at_crosshair(kind,id,distance)
    if not kind then kind,id=self.app.selection.kind,self.app.selection.id end
    local hit,err=self.app.game:aim_point(distance or 20);if not hit then return nil,err end
    local result,warning=self:_aim_at_position(kind,id,hit.position,{kind='aim',id=hit.source})
    return result,warning or (hit.source=='forward_fallback' and 'No surface hit; aimed at camera forward fallback.' or nil)
end

function EntTools:duplicate_at_aim(kind,id,distance,spawn)
    kind=kind or self.app.selection.kind;id=id or self.app.selection.id
    if kind~='object' and kind~='location' and kind~='volume' and kind~='camera' then return nil,'duplicate-at-aim supports object, location, volume, or camera' end
    if kind=='object' then
        local started,warning=self.app.transform_session:start_placement({kind='object',ids={id},active_id=id,mode='aim',distance=distance or 10,spawn=spawn})
        if not started then return nil,warning end
        local committed,commit_warning=self.app.transform_session:commit();if not committed then return nil,commit_warning end
        local object=committed.created_ids and self.app.model:get_object(committed.created_ids[1]) or nil
        if not object then return nil,'placement transaction committed without a created object' end
        local final_warning=warning or commit_warning
        self:_log('info','duplicate_at_aim','complete',{kind=kind,source_id=id,id=object.id,aim_source=(committed.creation or {}).placement_source,failed=#(committed.failed or {}),transactional=true})
        return object,final_warning
    end
    local source,err=self:_resolve(kind,id);if not source then return nil,err end
    local hit;hit,err=self.app.game:aim_point(distance or 10);if not hit then return nil,err end
    local copy=Util.deepcopy(source);copy.id=nil;copy.created_at=nil;copy.updated_at=nil;copy.name=(source.name or kind)..' Copy';copy.transform.position=Util.deepcopy(hit.position)
    if copy.runtime then copy.runtime={spawned=false,entity_id=nil} end
    local result
    if kind=='location' then result=self.app.model:add_location(copy)
    elseif kind=='volume' then result=self.app.model:add_volume(copy)
    elseif kind=='camera' then
        local delta={x=hit.position.x-source.transform.position.x,y=hit.position.y-source.transform.position.y,z=hit.position.z-source.transform.position.z}
        if copy.look_at then copy.look_at.x=(copy.look_at.x or 0)+delta.x;copy.look_at.y=(copy.look_at.y or 0)+delta.y;copy.look_at.z=(copy.look_at.z or 0)+delta.z end
        result=self.app.model:add_camera(copy)
    end
    self.app.selection:set(kind,result.id);self.app:mark_dirty()
    local spawn_error
    if kind=='object' and spawn~=false and self.app.model.data.settings.workspace.live_preview then local _,e=self.app.placement:spawn(result);spawn_error=e end
    self:_log('info','duplicate_at_aim','complete',{kind=kind,source_id=id,id=result.id,aim_source=hit.source,spawn_error=spawn_error})
    return result,spawn_error and ('Duplicated, but live spawn failed: '..tostring(spawn_error)) or nil
end

function EntTools:scatter_at_aim(args)
    args=args or {}
    local started,warning=self.app.transform_session:start_scatter(args);if not started then return nil,warning end
    local committed,commit_warning=self.app.transform_session:commit();if not committed then return nil,commit_warning end
    local made,spawned={},0
    for _,id in ipairs(committed.created_ids or {}) do
        local object=self.app.model:get_object(id)
        if object then table.insert(made,object);if self.app.placement:is_tracked(object) then spawned=spawned+1 end end
    end
    local final_warning=warning or commit_warning
    self:_log('info','scatter','complete',{source_kind=(committed.creation or {}).source_kind,source_id=(committed.source_ids or {})[1],count=#made,spawned=spawned,failed=#(committed.failed or {}),radius=(committed.creation or {}).radius,seed=(committed.creation or {}).seed,scatter_area=(committed.creation or {}).scatter_area or 'circle',transactional=true})
    return {objects=made,count=#made,spawned=spawned,failed=committed.failed or {},aim_source=(committed.creation or {}).aim_source,seed=(committed.creation or {}).seed,scatter_area=(committed.creation or {}).scatter_area or 'circle',volume_id=(committed.creation or {}).volume_id,points=(committed.creation or {}).points,committed=true},final_warning
end

return EntTools
