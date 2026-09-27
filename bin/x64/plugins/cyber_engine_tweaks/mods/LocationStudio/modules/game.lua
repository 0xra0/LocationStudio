local GameFacade={}
GameFacade.__index=GameFacade

function GameFacade.new(app)
    return setmetatable({app=app,last_error=nil,last_aim_source=nil,last_camera_source=nil,last_camera_log=0},GameFacade)
end

function GameFacade:_log(level,scope,message,fields)
    local logger=self.app and self.app.logger
    if logger and logger[level] then logger[level](logger,scope,message,fields) end
end

local function xyz(value)
    if not value then return nil end
    return {x=tonumber(value.x) or 0,y=tonumber(value.y) or 0,z=tonumber(value.z) or 0,w=tonumber(value.w) or 1}
end

local function euler(value)
    if not value then return nil end
    return {roll=tonumber(value.roll) or 0,pitch=tonumber(value.pitch) or 0,yaw=tonumber(value.yaw) or 0}
end

local function get_transform_position(transform)
    if not transform then return nil end
    if transform.GetTranslation then local ok,v=pcall(function() return transform:GetTranslation() end);if ok and v then return v end end
    if transform.GetPosition then local ok,v=pcall(function() return transform:GetPosition() end);if ok and v then return v end end
    return transform.position or transform.Position
end

local function get_transform_rotation(transform)
    if not transform then return nil end
    if transform.GetRotation then local ok,v=pcall(function() return transform:GetRotation() end);if ok and v then return v end end
    local orientation=transform.orientation or transform.Orientation
    if orientation and orientation.ToEulerAngles then local ok,v=pcall(function() return orientation:ToEulerAngles() end);if ok and v then return v end end
    if transform.GetOrientation then
        local ok,v=pcall(function() local q=transform:GetOrientation();return q and q:ToEulerAngles() or nil end)
        if ok and v then return v end
    end
    return nil
end

local function get_transform_forward(transform)
    if not transform then return nil end
    if transform.GetAxisY then local ok,v=pcall(function() return transform:GetAxisY() end);if ok and v then return v end end
    local orientation=transform.orientation or transform.Orientation
    if orientation and orientation.GetForward then local ok,v=pcall(function() return orientation:GetForward() end);if ok and v then return v end end
    local rotation=get_transform_rotation(transform)
    if rotation and rotation.GetForward then local ok,v=pcall(function() return rotation:GetForward() end);if ok and v then return v end end
    return nil
end

function GameFacade:is_ready()
    local ok,player=pcall(function() return Game and Game.GetPlayer and Game.GetPlayer() end)
    return ok and player~=nil
end

function GameFacade:capture_transform()
    local ok,player=pcall(function() return Game.GetPlayer() end)
    if not ok or not player then
        local err=ok and 'player not available' or tostring(player)
        self.last_error=err;self:_log('error','game:capture_transform','player_unavailable',{error=err})
        return nil,err
    end
    local success,result=pcall(function()
        local p=player:GetWorldPosition()
        local roll,pitch,yaw=0,0,0
        local orientation_ok,orientation=pcall(function() return player:GetWorldOrientation() end)
        if orientation_ok and orientation then
            local e_ok,e=pcall(function() return orientation:ToEulerAngles() end)
            if e_ok and e then roll=e.roll or 0;pitch=e.pitch or 0;yaw=e.yaw or 0 end
        end
        if yaw==0 then pcall(function() yaw=player:GetWorldYaw() or 0 end) end
        return {position={x=p.x,y=p.y,z=p.z,w=p.w or 1.0},rotation={roll=roll,pitch=pitch,yaw=yaw}}
    end)
    if not success then
        self.last_error=tostring(result);self:_log('error','game:capture_transform','failed',{error=self.last_error});return nil,self.last_error
    end
    self.last_error=nil;return result
end

function GameFacade:_active_camera_world_transform()
    local ok,system=pcall(function() return Game.GetCameraSystem and Game.GetCameraSystem() or nil end)
    if not ok or not system then return nil end
    if Transform and Transform.new and system.GetActiveCameraWorldTransform then
        local transform=Transform.new()
        local good,has=pcall(function() return system:GetActiveCameraWorldTransform(transform) end)
        if good and has then return transform end
    end
    return nil
end

function GameFacade:_fpp_camera_transform()
    local ok,player=pcall(function() return Game.GetPlayer() end);if not ok or not player or not player.GetFPPCameraComponent then return nil end
    local good,camera=pcall(function() return player:GetFPPCameraComponent() end);if not good or not camera or not camera.GetLocalToWorld then return nil end
    local t_ok,t=pcall(function() return camera:GetLocalToWorld() end);return t_ok and t or nil
end

function GameFacade:camera_forward()
    local ok,system=pcall(function() return Game.GetCameraSystem and Game.GetCameraSystem() or nil end)
    if ok and system and system.GetActiveCameraForward then
        local good,forward=pcall(function() return system:GetActiveCameraForward() end)
        if good and forward then return forward,'camera_system' end
    end
    local active=self:_active_camera_world_transform();local forward=get_transform_forward(active)
    if forward then return forward,'camera_transform' end
    local fpp=self:_fpp_camera_transform();forward=get_transform_forward(fpp)
    if forward then return forward,'fpp_camera' end
    local p_ok,player=pcall(function() return Game.GetPlayer() end)
    if p_ok and player and player.GetWorldForward then local good,v=pcall(function() return player:GetWorldForward() end);if good and v then return v,'player' end end
    return nil,'unavailable'
end

function GameFacade:capture_camera_transform()
    local transform=self:_active_camera_world_transform() or self:_fpp_camera_transform()
    if transform then
        local p=get_transform_position(transform);local r=get_transform_rotation(transform)
        if p then
            if not r then
                local forward=self:camera_forward()
                if forward and forward.ToRotation then local ok,v=pcall(function() return forward:ToRotation() end);if ok then r=v end end
            end
            local result={position=xyz(p),rotation=euler(r) or {roll=0,pitch=0,yaw=0}}
            self.last_camera_source='camera_transform';self.last_error=nil
            local now=os.clock();if now-(self.last_camera_log or 0)>1.0 then self.last_camera_log=now;self:_log('debug','game:camera','captured',{source=self.last_camera_source}) end
            return result
        end
    end

    local ok,system=pcall(function() return Game.GetCameraSystem and Game.GetCameraSystem() or nil end)
    if ok and system then
        local p,r
        if system.GetActiveCameraPosition then local good,v=pcall(function() return system:GetActiveCameraPosition() end);if good then p=v end end
        if system.GetActiveCameraRotation then local good,v=pcall(function() return system:GetActiveCameraRotation() end);if good then r=v end end
        if p then
            self.last_camera_source='camera_system';return {position=xyz(p),rotation=euler(r) or {roll=0,pitch=0,yaw=0}}
        end
    end

    local player,err=self:capture_transform()
    if player then self.last_camera_source='player_fallback';return player,'active camera transform unavailable; using player transform' end
    return nil,err or 'camera transform unavailable'
end

function GameFacade:camera_fov()
    local ok,system=pcall(function() return Game.GetCameraSystem and Game.GetCameraSystem() or nil end)
    if ok and system and system.GetActiveCameraFOV then local good,v=pcall(function() return system:GetActiveCameraFOV() end);if good and v then return tonumber(v) end end
    local p_ok,player=pcall(function() return Game.GetPlayer() end)
    if p_ok and player and player.GetFPPCameraComponent then
        local good,camera=pcall(function() return player:GetFPPCameraComponent() end)
        if good and camera and camera.GetFOV then local f_ok,v=pcall(function() return camera:GetFOV() end);if f_ok and v then return tonumber(v) end end
    end
    return nil
end

function GameFacade:camera_summary()
    local t,err=self:capture_camera_transform()
    return {ready=t~=nil,transform=t,fov=self:camera_fov(),source=self.last_camera_source,error=err}
end

function GameFacade:teleport(transform)
    local ok,player=pcall(function() return Game.GetPlayer() end)
    if not ok or not player then return false,'player not available' end
    local p=transform and transform.position or nil;local r=transform and transform.rotation or nil
    if not p or not r then return false,'invalid transform' end
    local success,err=pcall(function()
        local facility=Game.GetTeleportationFacility()
        if not facility then error('teleportation facility unavailable') end
        facility:Teleport(player,ToVector4{x=p.x,y=p.y,z=p.z,w=p.w or 1.0},ToEulerAngles{roll=r.roll or 0,pitch=r.pitch or 0,yaw=r.yaw or 0})
    end)
    if not success then self.last_error=tostring(err);self:_log('error','game:teleport','failed',{error=self.last_error});return false,self.last_error end
    self.last_error=nil;self:_log('info','game:teleport','success',{x=p.x,y=p.y,z=p.z});return true
end

function GameFacade:player_summary()
    if not self:is_ready() then return {ready=false} end
    local transform,err=self:capture_transform()
    return {ready=transform~=nil,transform=transform,error=err}
end

function GameFacade:raycast(start_position,end_position,collision_groups)
    local groups=collision_groups
    if type(groups)~='table' then groups={groups or 'Static'} end
    local ok,queries=pcall(function() return Game.GetSpatialQueriesSystem and Game.GetSpatialQueriesSystem() or nil end)
    if not ok or not queries then return nil,'spatial queries unavailable' end
    local start=ToVector4{x=start_position.x,y=start_position.y,z=start_position.z,w=start_position.w or 1}
    local finish=ToVector4{x=end_position.x,y=end_position.y,z=end_position.z,w=end_position.w or 1}
    local last_error
    for _,group in ipairs(groups) do
        -- Current CET returns (success:boolean, result:RaycastResult). Older builds/mod mocks
        -- sometimes return the result directly. Preserve both shapes and never index a boolean.
        local call_ok,first,second=pcall(function() return queries:SyncRaycastByCollisionGroup(start,finish,group,false,false) end)
        if not call_ok then
            last_error=tostring(first)
        else
            local result,hit_ok
            if type(first)=='boolean' then hit_ok=first;result=second else hit_ok=first~=nil;result=first end
            if hit_ok and result and type(result)~='boolean' then
                local field_ok,hit,normal=pcall(function()
                    local p=result.position or result.hitPosition or result.hitPositionWorld
                    local n=result.normal or result.hitNormal or result.normalWorld
                    return p,n
                end)
                if field_ok and hit then return {position=xyz(hit),normal=normal and xyz(normal) or nil,group=group,raw=result} end
                if not field_ok then last_error='raycast result could not be read: '..tostring(hit) end
            end
        end
    end
    return nil,last_error or 'raycast did not hit'
end

function GameFacade:aim_point(distance)
    distance=math.max(0.25,tonumber(distance) or 8.0)
    local camera,camera_warning=self:capture_camera_transform()
    local forward,forward_source=self:camera_forward()
    if not camera or not forward then return nil,camera_warning or 'camera ray unavailable' end
    local start={x=camera.position.x,y=camera.position.y,z=camera.position.z,w=camera.position.w or 1}
    -- entSpawner-style camera placement should originate at the actual camera.
    -- When CET cannot expose it and we fall back to the player transform, lift
    -- the ray to approximate eye height instead of shooting from V's feet.
    if self.last_camera_source=='player_fallback' then start.z=(start.z or 0)+1.6 end
    local finish={x=start.x+(forward.x or 0)*distance,y=start.y+(forward.y or 0)*distance,z=start.z+(forward.z or 0)*distance,w=1}
    local hit,ray_err=self:raycast(start,finish,{'Static','Terrain'})
    if hit then
        self.last_aim_source='camera_raycast';self:_log('debug','game:aim','raycast_hit',{distance=distance,camera_source=self.last_camera_source,forward_source=forward_source,group=hit.group})
        return {position=hit.position,normal=hit.normal,source='camera_raycast',distance=distance,collision_group=hit.group}
    end

    local target_ok,target=pcall(function()
        local player=Game.GetPlayer();local system=Game.GetTargetingSystem();return player and system and system:GetLookAtObject(player,false,false) or nil
    end)
    if target_ok and target then
        local pos_ok,target_pos=pcall(function() return target:GetWorldPosition() end)
        if pos_ok and target_pos then
            self.last_aim_source='look_at_entity';self:_log('debug','game:aim','entity_hit',{distance=distance})
            return {position=xyz(target_pos),source='look_at_entity',distance=distance}
        end
    end

    self.last_aim_source='forward_fallback'
    self:_log('warn','game:aim','no_hit_using_forward_fallback',{distance=distance,ray_error=ray_err,camera_source=self.last_camera_source})
    return {position=finish,source='forward_fallback',distance=distance}
end

function GameFacade:ground_below(position,max_distance,offset)
    if not position then return nil,'position required' end
    max_distance=math.max(0.5,tonumber(max_distance) or 50)
    offset=tonumber(offset) or 0
    local start={x=position.x,y=position.y,z=(position.z or 0)+0.75,w=1}
    local finish={x=position.x,y=position.y,z=(position.z or 0)-max_distance,w=1}
    local hit,err=self:raycast(start,finish,{'Static','Terrain'})
    if not hit then return nil,err or 'no ground below item' end
    hit.position.z=hit.position.z+offset
    hit.source='ground_raycast'
    self:_log('debug','game:ground','hit',{x=hit.position.x,y=hit.position.y,z=hit.position.z,group=hit.group})
    return hit
end

return GameFacade
