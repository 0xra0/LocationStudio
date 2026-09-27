local Util=require('modules/util')

local ViewportTools={}
ViewportTools.__index=ViewportTools

local function number(value,fallback) return tonumber(value) or fallback or 0 end

local function normalized(value)
    if not value then return nil end
    local x,y,z=number(value.x),number(value.y),number(value.z)
    local length=math.sqrt(x*x+y*y+z*z)
    if length<0.000001 then return nil end
    return {x=x/length,y=y/length,z=z/length,w=0}
end

-- Align the transform's local up axis to the hit normal while leaving yaw as
-- an independent artist-controlled heading.  Game resources with a different
-- authored up axis can still be corrected in the Inspector after placement.
function ViewportTools.surface_rotation(normal,yaw)
    local n=normalized(normal)
    if not n then return {roll=0,pitch=0,yaw=number(yaw)} end
    local roll=math.deg(math.atan2(n.y,n.z))
    local pitch=math.deg(math.atan2(-n.x,math.sqrt(n.y*n.y+n.z*n.z)))
    return {roll=roll,pitch=pitch,yaw=number(yaw)}
end

function ViewportTools.new(app)
    return setmetatable({app=app,last_pick=nil,last_error=nil},ViewportTools)
end

function ViewportTools:_settings()
    local settings=(((self.app.model or {}).data or {}).settings or {}).asset_preview or {}
    return {
        distance=math.max(1,number(settings.pick_distance,40)),
        radius=math.max(0.05,number(settings.pick_radius,0.75)),
        focus=settings.pick_focus_world_builder~=false,
    }
end

function ViewportTools:_eligible(object,args,visible_layers)
    if not object or not object.transform or not object.transform.position then return false end
    if object.enabled==false or object.visible==false then return false end
    if visible_layers[object.layer]==false then return false end
    if args.include_locked==false and object.locked then return false end
    local premise_id=args.premise_id
    if premise_id==nil and args.premise_only~=false then premise_id=self.app.selected_premise_id end
    if premise_id and object.premise_id~=premise_id then return false end
    return true
end

function ViewportTools:pick_aimed_object(args)
    args=args or {}
    local settings=self:_settings()
    local max_distance=math.max(1,number(args.max_distance,settings.distance))
    local radius=math.max(0.05,number(args.radius,settings.radius))
    local camera,camera_err=self.app.game:capture_camera_transform()
    local forward,forward_source=self.app.game:camera_forward()
    forward=normalized(forward)
    if not camera or not camera.position or not forward then
        self.last_error=camera_err or 'active camera ray is unavailable'
        if self.app.logger then self.app.logger:error('viewport:pick','camera_unavailable',{error=self.last_error}) end
        return nil,self.last_error
    end

    local origin=camera.position
    local visible_layers={}
    for _,layer in ipairs(self.app.model.data.layers or {}) do visible_layers[layer.id]=layer.visible~=false end
    local best,candidates=nil,0
    for _,object in ipairs(self.app.model.data.objects or {}) do
        if self:_eligible(object,args,visible_layers) then
            local p=object.transform.position
            local vx=number(p.x)-number(origin.x);local vy=number(p.y)-number(origin.y);local vz=number(p.z)-number(origin.z)
            local along=vx*forward.x+vy*forward.y+vz*forward.z
            if along>=0 and along<=max_distance then
                local cx=number(origin.x)+forward.x*along;local cy=number(origin.y)+forward.y*along;local cz=number(origin.z)+forward.z*along
                local dx=number(p.x)-cx;local dy=number(p.y)-cy;local dz=number(p.z)-cz
                local perpendicular=math.sqrt(dx*dx+dy*dy+dz*dz)
                local size=object.size or {};local extent=math.min(1.5,math.max(number(size.x),number(size.y),number(size.z))*0.2)
                local tolerance=radius+extent
                if perpendicular<=tolerance then
                    candidates=candidates+1
                    local score=perpendicular+(along/max_distance)*0.05
                    if not best or score<best.score then
                        best={object=object,perpendicular_distance=perpendicular,ray_distance=along,tolerance=tolerance,score=score}
                    end
                end
            end
        end
    end

    if not best then
        self.last_error=string.format('No project object is within %.2f m of the crosshair ray.',radius)
        self.last_pick={ok=false,error=self.last_error,radius=radius,max_distance=max_distance,candidate_count=0,timestamp=Util.now_iso()}
        if self.app.logger then self.app.logger:warn('viewport:pick','no_match',{radius=radius,max_distance=max_distance,premise_id=args.premise_id or self.app.selected_premise_id}) end
        return nil,self.last_error
    end

    local object=best.object
    local selected,select_err=self.app.selection:set('object',object.id)
    if not selected then return nil,select_err end
    local focus,focus_warning
    local should_focus=args.focus_world_builder
    if should_focus==nil then should_focus=settings.focus end
    if should_focus and self.app.runtime_shell and self.app.placement:is_tracked(object) and object.metadata and type(object.metadata.world_builder)=='table' then
        focus,focus_warning=self.app.runtime_shell:focus(object)
    end
    self.last_error=nil
    self.last_pick={
        ok=true,object_id=object.id,object_name=object.name,perpendicular_distance=best.perpendicular_distance,
        ray_distance=best.ray_distance,tolerance=best.tolerance,candidate_count=candidates,
        source='camera_ray_projected',camera_source=self.app.game.last_camera_source,forward_source=forward_source,
        focused=focus and true or false,focus_warning=focus_warning,timestamp=Util.now_iso(),
    }
    if self.app.logger then self.app.logger:info('viewport:pick','selected',self.last_pick) end
    return {object=object,pick=Util.deepcopy(self.last_pick),focus=focus},focus_warning
end

function ViewportTools:status()
    return {last_pick=Util.deepcopy(self.last_pick),last_error=self.last_error,settings=self:_settings()}
end

return ViewportTools
