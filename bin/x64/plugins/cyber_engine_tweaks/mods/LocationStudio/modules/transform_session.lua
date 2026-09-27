local Util=require('modules/util')
local ViewportTools=require('modules/viewport_tools')

local TransformSession={}
TransformSession.__index=TransformSession

local function number(value,fallback) return tonumber(value) or fallback or 0 end

local function is_world_builder(object)
    return object and object.metadata and type(object.metadata.world_builder)=='table'
end

local function object_list(app,ids)
    local values,seen={},{}
    for _,id in ipairs(ids or {}) do
        if not seen[id] then
            local object=app.model:get_object(id)
            if not object then return nil,'object not found: '..tostring(id) end
            if object.locked then return nil,'object '..tostring(object.name or id)..' is locked' end
            if object.enabled==false or object.visible==false then return nil,'object '..tostring(object.name or id)..' is hidden or disabled' end
            seen[id]=true;table.insert(values,object)
        end
    end
    if #values==0 then return nil,'select at least one object' end
    return values
end

local function center_pivot(objects,active_id,mode)
    if mode=='active' then
        for _,object in ipairs(objects) do if object.id==active_id then return Util.deepcopy(object.transform) end end
    end
    local pivot={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}
    for _,object in ipairs(objects) do
        local p=object.transform.position;pivot.position.x=pivot.position.x+p.x;pivot.position.y=pivot.position.y+p.y;pivot.position.z=pivot.position.z+p.z
    end
    pivot.position.x=pivot.position.x/#objects;pivot.position.y=pivot.position.y/#objects;pivot.position.z=pivot.position.z/#objects
    return pivot
end

local function requested_pivot(objects,active_id,mode,value)
    if mode=='custom' and type(value)=='table' then
        local source=value.position or value
        return {
            position={x=number(source.x),y=number(source.y),z=number(source.z),w=number(source.w,1)},
            rotation={roll=0,pitch=0,yaw=number(value.rotation and value.rotation.yaw)},
        }
    end
    return center_pivot(objects,active_id,mode)
end

local function rotate_xy(dx,dy,degrees)
    return Util.rotate_xy(dx,dy,degrees)
end

local function seeded_random(seed)
    local state=math.floor(math.abs(number(seed,1)))%2147483647
    if state==0 then state=1 end
    return function()
        state=(state*48271)%2147483647
        return state/2147483647
    end,state
end

local function finite(value)
    value=tonumber(value)
    return value and value==value and value~=math.huge and value~=-math.huge
end

local function point_in_polygon(x,y,vertices)
    local inside=false;local previous=#vertices
    for index=1,#vertices do
        local a,b=vertices[index],vertices[previous]
        if ((a.y>y)~=(b.y>y)) and x<(b.x-a.x)*(y-a.y)/(b.y-a.y)+a.x then inside=not inside end
        previous=index
    end
    return inside
end

local function segments_intersect(a,b,c,d)
    local function orient(p,q,r) return (q.x-p.x)*(r.y-p.y)-(q.y-p.y)*(r.x-p.x) end
    local ab_c,ab_d=orient(a,b,c),orient(a,b,d)
    local cd_a,cd_b=orient(c,d,a),orient(c,d,b)
    local eps=1e-9
    local function on_segment(p,q,r)
        return math.abs(orient(p,q,r))<=eps and r.x>=math.min(p.x,q.x)-eps and r.x<=math.max(p.x,q.x)+eps
            and r.y>=math.min(p.y,q.y)-eps and r.y<=math.max(p.y,q.y)+eps
    end
    if ((ab_c>eps and ab_d< -eps) or (ab_c< -eps and ab_d>eps)) and ((cd_a>eps and cd_b< -eps) or (cd_a< -eps and cd_b>eps)) then return true end
    return on_segment(a,b,c) or on_segment(a,b,d) or on_segment(c,d,a) or on_segment(c,d,b)
end

local function valid_polygon(vertices)
    if type(vertices)~='table' or #vertices<3 or #vertices>128 then return nil,'polygon requires 3 to 128 vertices' end
    local points={}
    local min_x,max_x,min_y,max_y=math.huge,-math.huge,math.huge,-math.huge
    for index,point in ipairs(vertices) do
        if type(point)~='table' or not finite(point.x) or not finite(point.y) then return nil,'polygon vertices must contain finite world x and y coordinates' end
        points[index]={x=tonumber(point.x),y=tonumber(point.y)}
        if math.abs(points[index].x)>100000 or math.abs(points[index].y)>100000 then return nil,'polygon coordinates exceed the supported world-coordinate range' end
        min_x=math.min(min_x,points[index].x);max_x=math.max(max_x,points[index].x)
        min_y=math.min(min_y,points[index].y);max_y=math.max(max_y,points[index].y)
    end
    for index,point in ipairs(points) do
        local next_point=points[index%#points+1]
        if math.abs(point.x-next_point.x)<0.000001 and math.abs(point.y-next_point.y)<0.000001 then return nil,'polygon cannot repeat adjacent vertices' end
    end
    if max_x-min_x<0.001 or max_y-min_y<0.001 then return nil,'polygon must enclose a non-zero XY area' end
    for i=1,#points do
        local a,b=points[i],points[i%#points+1]
        for j=i+1,#points do
            if j~=i and j~=i+1 and not (i==1 and j==#points) then
                local c,d=points[j],points[j%#points+1]
                if segments_intersect(a,b,c,d) then return nil,'polygon edges must not cross' end
            end
        end
    end
    local twice_area=0
    for index,a in ipairs(points) do local b=points[index%#points+1];twice_area=twice_area+a.x*b.y-b.x*a.y end
    if math.abs(twice_area)<0.002 then return nil,'polygon must enclose a non-zero XY area' end
    return {vertices=points,min_x=min_x,max_x=max_x,min_y=min_y,max_y=max_y}
end

local function sample_polygon(random,polygon)
    local attempts=math.max(100,math.min(10000,math.ceil((polygon.max_x-polygon.min_x)*(polygon.max_y-polygon.min_y)*5)))
    for _=1,attempts do
        local x=polygon.min_x+random()*(polygon.max_x-polygon.min_x)
        local y=polygon.min_y+random()*(polygon.max_y-polygon.min_y)
        if point_in_polygon(x,y,polygon.vertices) then return x,y end
    end
    return nil,nil
end

local function sample_volume(random,volume)
    local transform=volume.transform or {};local center=transform.position or {};local rotation=transform.rotation or {}
    local shape=volume.shape or 'box';local lx,ly,lz
    if shape=='sphere' then
        local z=2*random()-1;local phi=2*math.pi*random();local radial=math.pow(random(),1/3)*volume.radius
        local planar=radial*math.sqrt(math.max(0,1-z*z));lx=planar*math.cos(phi);ly=planar*math.sin(phi);lz=z*radial
    elseif shape=='cylinder' then
        local radial=math.sqrt(random())*volume.radius;local angle=2*math.pi*random()
        lx=radial*math.cos(angle);ly=radial*math.sin(angle);lz=(random()-0.5)*(volume.height or volume.size.z or 2)
    else
        lx=(random()-0.5)*volume.size.x;ly=(random()-0.5)*volume.size.y;lz=(random()-0.5)*volume.size.z
    end
    local roll,pitch,yaw=math.rad(number(rotation.roll)),math.rad(number(rotation.pitch)),math.rad(number(rotation.yaw))
    local cr,sr=math.cos(roll),math.sin(roll);local cp,sp=math.cos(pitch),math.sin(pitch);local cy,sy=math.cos(yaw),math.sin(yaw)
    local x1,y1,z1=lx,ly*cr-lz*sr,ly*sr+lz*cr
    local x2,y2,z2=x1*cp+z1*sp,y1,-x1*sp+z1*cp
    local rx,ry,rz=x2*cy-y2*sy,x2*sy+y2*cy,z2
    return {x=number(center.x)+rx,y=number(center.y)+ry,z=number(center.z)+rz,w=1}
end

local function surface_basis(normal)
    local nx,ny,nz=number(normal.x),number(normal.y),number(normal.z)
    local length=math.sqrt(nx*nx+ny*ny+nz*nz);if length<0.0001 then return nil end
    nx,ny,nz=nx/length,ny/length,nz/length
    local rx,ry,rz=0,0,1
    if math.abs(nz)>0.95 then rx,ry,rz=1,0,0 end
    local tx,ty,tz=ny*rz-nz*ry,nz*rx-nx*rz,nx*ry-ny*rx
    local tl=math.sqrt(tx*tx+ty*ty+tz*tz);tx,ty,tz=tx/tl,ty/tl,tz/tl
    local bx,by,bz=ny*tz-nz*ty,nz*tx-nx*tz,nx*ty-ny*tx
    return {x=nx,y=ny,z=nz},{x=tx,y=ty,z=tz},{x=bx,y=by,z=bz}
end

local function restore_selection(app,prior)
    prior=prior or {}
    if not app.selection then return end
    if prior.kind and prior.kind~='object' and prior.id then
        app.selection:set(prior.kind,prior.id)
    else
        app.selection:set_object_group(prior.ids or {},prior.active_id or prior.id,prior.group_source or 'locationstudio')
    end
end

function TransformSession.new(app)
    return setmetatable({app=app,session=nil,last_error=nil,last_result=nil},TransformSession)
end

function TransformSession:is_active() return self.session~=nil end

function TransformSession:_settings()
    local settings=self.app.model.data.settings.transform_grab or {}
    return {
        distance=math.max(0.25,number(settings.distance,12)),
        surface_offset=number(settings.surface_offset,0.02),
        align_surface=settings.align_surface==true,
        snap_position=settings.snap_position==true,
        pivot_mode=settings.pivot_mode=='active' and 'active' or 'center',
        update_interval=math.max(0.03,number(settings.update_interval,0.08)),
    }
end

function TransformSession:_selection_ids(args)
    if type(args.ids)=='table' and #args.ids>0 then return args.ids,args.active_id end
    local selected=self.app.selection and self.app.selection:selected_objects() or {}
    local ids={};for _,object in ipairs(selected) do table.insert(ids,object.id) end
    return ids,args.active_id or (self.app.selection and self.app.selection.id)
end

function TransformSession:_runtime_update(force)
    local s=self.session;if not s then return 0,{} end
    local updated,failed=0,{}
    for _,id in ipairs(s.ids) do
        local object=self.app.model:get_object(id);local runtime=s.runtime[id] or {}
        if object and is_world_builder(object) and self.app.placement:is_tracked(object) then
            local result,err=self.app.runtime_shell:update_object(object,{silent=true})
            if result then updated=updated+1 else table.insert(failed,{id=id,error=tostring(err)}) end
        elseif object and force and runtime.was_live then
            local result,err=self.app.placement:refresh(object)
            if result then updated=updated+1 else table.insert(failed,{id=id,error=tostring(err)}) end
        end
    end
    s.live_updates=(s.live_updates or 0)+updated;s.failed=failed
    return updated,failed
end

function TransformSession:_restore_originals()
    local s=self.session;if not s then return end
    for _,id in ipairs(s.ids) do
        local object=self.app.model:get_object(id);local original=s.originals[id]
        if object and original then
            object.transform=Util.deepcopy(original.transform)
            object.size=Util.deepcopy(original.size)
            object.updated_at=original.updated_at
        end
    end
end

function TransformSession:_begin(args,kind)
    args=args or {}
    kind=kind=='edit' and 'edit' or 'grab'
    if self.session then return nil,'a transform session is already active' end
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before starting a transform session.' end
    local ids,active_id=self:_selection_ids(args)
    local objects,err=object_list(self.app,ids);if not objects then return nil,err end
    local settings=self:_settings();active_id=active_id or objects[#objects].id
    local mode=args.pivot_mode or settings.pivot_mode
    if mode~='active' and mode~='custom' then mode='center' end
    local pivot=requested_pivot(objects,active_id,mode,args.pivot)
    local originals,runtime={},{};local live_world_builder,deferred_cet=0,0
    local session_live_preview=args.spawn
    if session_live_preview==nil then session_live_preview=self.app.model.data.settings.workspace.live_preview~=false end
    for _,object in ipairs(objects) do
        originals[object.id]={transform=Util.deepcopy(object.transform),size=Util.deepcopy(object.size),updated_at=object.updated_at}
        local was_live=self.app.placement:is_tracked(object)
        runtime[object.id]={was_live=was_live,spawned_for_session=false,spawn_on_commit=(not was_live and session_live_preview)}
        if is_world_builder(object) then live_world_builder=live_world_builder+1 else deferred_cet=deferred_cet+1 end
    end
    if self.app.placement:preview_status().active then self.app.placement:clear_preview() end
    self.session={
        kind=kind,ids=Util.deepcopy(ids),active_id=active_id,count=#objects,originals=originals,runtime=runtime,pivot=pivot,pivot_mode=mode,
        distance=math.max(0.25,number(args.distance,settings.distance)),surface_offset=number(args.surface_offset,settings.surface_offset),
        align_surface=args.align_surface==nil and settings.align_surface or args.align_surface==true,
        snap_position=args.snap_position==nil and settings.snap_position or args.snap_position==true,
        yaw_delta=number(args.yaw_delta,0),update_interval=settings.update_interval,elapsed=settings.update_interval,
        translation={x=0,y=0,z=0},rotation_delta={roll=0,pitch=0,yaw=0},scale_factor=1,
        local_space=args.local_space==true,changed=false,
        started_at=Util.now_iso(),live_world_builder=live_world_builder,deferred_cet=deferred_cet,live_updates=0,failed={},
    }
    for _,object in ipairs(objects) do
        local state=runtime[object.id]
        if is_world_builder(object) and not state.was_live and state.spawn_on_commit then
            local spawned,spawn_err=self.app.placement:spawn(object)
            if spawned then state.spawned_for_session=true
            else table.insert(self.session.failed,{id=object.id,error=tostring(spawn_err)}) end
        end
    end
    self.last_error=nil
    return self:status()
end

function TransformSession:start(args)
    local result,err=self:_begin(args,'grab');if not result then return nil,err end
    result,err=self:update(0,true)
    if not result then self:cancel();self.last_error=err;return nil,err end
    local s=self.session
    if self.app.logger then self.app.logger:info('transform:grab','started',{count=s.count,active_id=s.active_id,pivot_mode=s.pivot_mode,align_surface=s.align_surface,snap_position=s.snap_position,live_world_builder=s.live_world_builder,deferred_cet=s.deferred_cet}) end
    return result,result.last_warning
end

function TransformSession:start_edit(args)
    args=args or {}
    local settings=self.app.model.data.settings.transform_edit or {}
    if args.pivot_mode==nil then args.pivot_mode=settings.pivot_mode end
    if args.local_space==nil then args.local_space=settings.local_space==true end
    local result,err=self:_begin(args,'edit');if not result then return nil,err end
    local s=self.session
    if self.app.logger then self.app.logger:info('transform:edit','started',{count=s.count,active_id=s.active_id,pivot_mode=s.pivot_mode,local_space=s.local_space,live_world_builder=s.live_world_builder,live_cet=s.deferred_cet}) end
    return result
end

local function creation_scope(session)
    return 'transform:'..tostring(session and session.operation or 'creation')
end

local function is_creation(session)
    return session and type(session.created_ids)=='table'
end

local function duplicate_value(source,name)
    local copy=Util.deepcopy(source)
    copy.id=nil;copy.created_at=nil;copy.updated_at=nil;copy.runtime=nil;copy.parent_id=nil
    copy.name=name or (tostring(source.name or 'Object')..' Copy')
    if copy.metadata and copy.metadata.room_kit==true then
        copy.metadata.generated=false;copy.metadata.room_kit=false;copy.metadata.detached_from_room=true
        copy.metadata.detached_at=Util.now_iso();copy.layer='decoration';copy.locked=false
    end
    return copy
end

local function asset_value(app,args)
    local asset_id=args.id or (app.selection and app.selection.id) or app.selected_asset_id
    local asset=app.model:get_asset(asset_id);if not asset then return nil,nil,'select a project asset first' end
    local wb=asset.metadata and type(asset.metadata.world_builder)=='table'
    if not wb and Util.trim(asset.template)=='' then return nil,nil,'selected asset has no spawnable game resource' end
    local premise_id=args.premise_id or app.selected_premise_id
    if not premise_id or not app.model:get_premise(premise_id) then return nil,nil,'select a location before placing an asset' end
    local value={
        id=asset.id,premise_id=premise_id,room_id=args.room_id or app.selected_room_id,
        name=args.name or asset.name,kind=asset.kind,template=asset.template,appearance=asset.appearance,layer=asset.layer,size=Util.deepcopy(asset.size),
        enabled=true,visible=true,locked=false,properties={},metadata=Util.deepcopy(asset.metadata or {}),
        transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=number(args.yaw)}},
    }
    value.metadata.source='asset:'..tostring(asset.id)
    value.metadata.locationstudio_asset_id=asset.id
    return value,asset
end

function TransformSession:_start_created_edit(args,operation,ids,sources,queue,details)
    args=args or {}
    if self.session then return nil,'a transform session is already active' end
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before creating objects.' end
    local active_id=args.active_id or sources[#sources].id
    local history_before=Util.deepcopy(self.app.model.data)
    local dirty_before=self.app.dirty==true;local dirty_since_before=self.app.dirty_since
    local selection_before={
        kind=self.app.selection and self.app.selection.kind or 'object',id=self.app.selection and self.app.selection.id or active_id,
        ids=Util.deepcopy(ids),active_id=active_id,group_source=self.app.selection and self.app.selection.group_source or 'locationstudio',active_group_id=self.app.active_object_group_id,
    }
    local copies,add_err=self.app.model:add_objects(queue,true);if not copies or #copies~=#queue then return nil,add_err or 'could not create duplicate objects' end
    local copy_ids={};local initial_failed={}
    for _,copy in ipairs(copies) do table.insert(copy_ids,copy.id) end
    local should_spawn=args.spawn
    if should_spawn==nil then should_spawn=self.app.model.data.settings.workspace.live_preview~=false end
    if should_spawn then
        for _,copy in ipairs(copies) do
            local spawned,spawn_err=self.app.placement:spawn(copy)
            if not spawned then table.insert(initial_failed,{id=copy.id,error=tostring(spawn_err)}) end
        end
    end
    local active_index=math.max(1,math.min(#copies,math.floor(number(details and details.active_index,#copies))))
    local active_copy_id=copies[active_index].id
    self.app.selection:set_object_group(copy_ids,active_copy_id,tostring(operation)..'_session')
    local settings=self.app.model.data.settings.transform_edit or {};local begin_args=Util.deepcopy(args)
    if begin_args.pivot_mode==nil then begin_args.pivot_mode=settings.pivot_mode end
    if begin_args.local_space==nil then begin_args.local_space=settings.local_space==true end
    begin_args.ids=copy_ids;begin_args.active_id=active_copy_id
    local result,begin_err=self:_begin(begin_args,'edit')
    if not result then
        for _,copy in ipairs(copies) do self.app.placement:despawn(copy) end
        local lookup={};for _,id in ipairs(copy_ids) do lookup[id]=true end
        local kept={};for _,object in ipairs(self.app.model.data.objects) do if not lookup[object.id] then table.insert(kept,object) end end
        self.app.model.data.objects=kept;self.app.model.data.project.updated_at=history_before.project.updated_at
        restore_selection(self.app,selection_before)
        self.app.active_object_group_id=selection_before.active_group_id
        return nil,begin_err
    end
    local s=self.session
    s.operation=operation;s.created_ids=Util.deepcopy(copy_ids);s.source_ids=Util.deepcopy(ids);s.history_before=history_before
    s.selection_before=selection_before;s.dirty_before=dirty_before;s.dirty_since_before=dirty_since_before;s.changed=true;s.initial_offset=Util.deepcopy(details and details.offset)
    s.creation=Util.deepcopy(details or {});s.creation.active_index=nil
    for _,id in ipairs(copy_ids) do
        local state=s.runtime[id]
        if state then state.spawn_on_commit=should_spawn and not state.was_live end
    end
    local unresolved={}
    for _,failure in ipairs(initial_failed) do
        local copy=self.app.model:get_object(failure.id)
        if copy and not self.app.placement:is_tracked(copy) then table.insert(unresolved,failure);table.insert(s.failed,failure) end
    end
    if #unresolved>0 then s.last_warning=tostring(#unresolved)..' created object(s) could not spawn live; the authored copies remain editable and details are in the debug log.' end
    if self.app.logger then self.app.logger:info(creation_scope(s),'started',{count=s.count,source_ids=ids,created_ids=copy_ids,creation=s.creation,live_world_builder=s.live_world_builder,live_cet=s.deferred_cet,failed=#unresolved}) end
    return self:status(),s.last_warning
end

function TransformSession:start_duplicate(args)
    args=args or {}
    if self.session then return nil,'a transform session is already active' end
    local ids,active_id=self:_selection_ids(args)
    local sources,err=object_list(self.app,ids);if not sources then return nil,err end
    local offset=args.offset or {x=number(self.app.model.data.settings.snapping.grid,0.25),y=0,z=0}
    local queue={};local active_index=#sources
    for index,source in ipairs(sources) do
        local copy=duplicate_value(source)
        local p=copy.transform.position;p.x=number(p.x)+number(offset.x);p.y=number(p.y)+number(offset.y);p.z=number(p.z)+number(offset.z)
        table.insert(queue,copy);if source.id==(active_id or sources[#sources].id) then active_index=index end
    end
    args.active_id=active_id or sources[#sources].id
    return self:_start_created_edit(args,'duplicate',ids,sources,queue,{active_index=active_index,offset=Util.deepcopy(offset)})
end

function TransformSession:start_pattern(args)
    args=args or {}
    if self.session then return nil,'a transform session is already active' end
    local ids,active_id=self:_selection_ids(args)
    local sources,err=object_list(self.app,ids);if not sources then return nil,err end
    active_id=active_id or sources[#sources].id
    local count=math.floor(number(args.count,1));if count<1 then return nil,'pattern count must be at least one' end
    if count*#sources>100 then return nil,'pattern is limited to 100 created objects per transaction' end
    local step=args.step or {x=args.dx,y=args.dy,z=args.dz}
    step={x=number(step.x),y=number(step.y),z=number(step.z)}
    local yaw_step=number(args.yaw_step,args.dyaw)
    if math.abs(step.x)<0.000001 and math.abs(step.y)<0.000001 and math.abs(step.z)<0.000001 and math.abs(yaw_step)<0.000001 then return nil,'pattern step or yaw must be non-zero' end
    local pivot_mode=args.pattern_pivot_mode=='active' and 'active' or 'center'
    local pivot=requested_pivot(sources,active_id,pivot_mode,nil).position
    local active_yaw=0;local active_source_index=#sources
    for index,source in ipairs(sources) do if source.id==active_id then active_yaw=number(source.transform.rotation.yaw);active_source_index=index;break end end
    local local_axes=args.pattern_local_space==true
    local sx,sy=step.x,step.y;if local_axes then sx,sy=rotate_xy(sx,sy,active_yaw) end
    local queue={}
    for repeat_index=1,count do
        local angle=yaw_step*repeat_index
        for _,source in ipairs(sources) do
            local copy=duplicate_value(source,string.format('%s Array %02d',tostring(source.name or 'Object'),repeat_index+1))
            local p=source.transform.position;local ox,oy=rotate_xy(number(p.x)-number(pivot.x),number(p.y)-number(pivot.y),angle)
            copy.transform.position={x=number(pivot.x)+ox+sx*repeat_index,y=number(pivot.y)+oy+sy*repeat_index,z=number(p.z)+step.z*repeat_index,w=number(p.w,1)}
            copy.transform.rotation.yaw=number(source.transform.rotation.yaw)+angle
            table.insert(queue,copy)
        end
    end
    args.active_id=active_id
    return self:_start_created_edit(args,'pattern',ids,sources,queue,{active_index=(count-1)*#sources+active_source_index,repetitions=count,source_count=#sources,step=step,yaw_step=yaw_step,pattern_local_space=local_axes,pattern_pivot_mode=pivot_mode,pattern_pivot=Util.deepcopy(pivot)})
end

-- Build one undoable set of duplicates from editable placed objects. `placements`
-- describes the desired pivot position and optional yaw delta for each copy.
function TransformSession:_start_array(args,operation,placements,details)
    args=args or {}
    if self.session then return nil,'a transform session is already active' end
    local ids,active_id=self:_selection_ids(args)
    local sources,err=object_list(self.app,ids);if not sources then return nil,err end
    if #placements<1 or #placements*#sources>100 then return nil,'array is limited to 100 created objects per transaction' end
    local premise_id=sources[1].premise_id
    for _,source in ipairs(sources) do if source.premise_id~=premise_id then return nil,'array selection must belong to one location' end end
    local pivot={x=0,y=0,z=0};local active_index=#sources;local active_yaw=0
    for index,source in ipairs(sources) do
        local p=source.transform.position;pivot.x=pivot.x+number(p.x);pivot.y=pivot.y+number(p.y);pivot.z=pivot.z+number(p.z)
        if source.id==(active_id or sources[#sources].id) then active_index=index;active_yaw=number(source.transform.rotation.yaw) end
    end
    pivot.x=pivot.x/#sources;pivot.y=pivot.y/#sources;pivot.z=pivot.z/#sources
    local queue={}
    for pi,placement in ipairs(placements) do
        local delta=placement.target_yaw~=nil and (number(placement.target_yaw)-active_yaw) or number(placement.rotation_delta)
        for _,source in ipairs(sources) do
            local copy=duplicate_value(source,string.format('%s %s %02d',tostring(source.name or 'Object'),operation,pi))
            local p=source.transform.position
            local ox,oy=rotate_xy(number(p.x)-pivot.x,number(p.y)-pivot.y,delta)
            copy.transform.position={x=number(placement.x)+ox,y=number(placement.y)+oy,z=number(placement.z)+number(p.z)-pivot.z,w=number(p.w,1)}
            copy.transform.rotation.yaw=number(source.transform.rotation.yaw)+delta
            table.insert(queue,copy)
        end
    end
    args.active_id=active_id or sources[#sources].id
    details=details or {};details.active_index=(#placements-1)*#sources+active_index;details.copy_count=#placements;details.source_count=#sources
    return self:_start_created_edit(args,operation,ids,sources,queue,details)
end

local function valid_world_point(point)
    return type(point)=='table' and finite(point.x) and finite(point.y) and finite(point.z or 0)
        and math.abs(tonumber(point.x))<=100000 and math.abs(tonumber(point.y))<=100000 and math.abs(tonumber(point.z or 0))<=100000
end

local function sample_polyline(points,t)
    local lengths,total={},0
    for i=1,#points-1 do
        local a,b=points[i],points[i+1];local dx,dy,dz=b.x-a.x,b.y-a.y,b.z-a.z
        local length=math.sqrt(dx*dx+dy*dy+dz*dz);if length<0.001 then return nil,'path contains repeated or near-identical points' end
        lengths[i]=length;total=total+length
    end
    local target=total*t;local passed=0
    for i,length in ipairs(lengths) do
        if target<=passed+length or i==#lengths then
            local a,b=points[i],points[i+1];local f=math.max(0,math.min(1,(target-passed)/length))
            return {x=a.x+(b.x-a.x)*f,y=a.y+(b.y-a.y)*f,z=a.z+(b.z-a.z)*f},
                math.deg(math.atan2(b.y-a.y,b.x-a.x))
        end
        passed=passed+length
    end
end

function TransformSession:start_path_array(args)
    args=args or {};local count=math.floor(number(args.count,1));local path=args.path_points or args.points
    if count<1 then return nil,'path array count must be at least one' end
    if type(path)~='table' or #path<2 or #path>256 then return nil,'path array requires 2 to 256 world points' end
    local points={}
    for i,p in ipairs(path) do if not valid_world_point(p) then return nil,'path points require finite world x, y and z coordinates' end;points[i]={x=tonumber(p.x),y=tonumber(p.y),z=tonumber(p.z or 0)} end
    local placements={}
    for i=1,count do local point,yaw=sample_polyline(points,i/(count+1));if not point then return nil,yaw end;placements[i]={x=point.x,y=point.y,z=point.z,target_yaw=args.orient_to_path==false and nil or yaw} end
    return self:_start_array(args,'path_array',placements,{path_points=points,orient_to_path=args.orient_to_path~=false})
end

function TransformSession:start_radial_array(args)
    args=args or {};local count=math.floor(number(args.count,1));local center=args.center;local radius=tonumber(args.radius)
    if count<1 or count>100 then return nil,'radial array count must be between 1 and 100' end
    if not valid_world_point(center) then return nil,'radial array center requires finite world x, y and z coordinates' end
    if not finite(radius) or radius<=0 or radius>100000 then return nil,'radial array radius must be greater than zero' end
    local start=number(args.start_angle);local sweep=number(args.sweep_angle,360);if not finite(sweep) or math.abs(sweep)<0.001 or math.abs(sweep)>3600 then return nil,'radial array sweep angle must be between 0.001 and 3600 degrees' end
    local placements={};local full=math.abs(math.abs(sweep)-360)<0.0001
    for i=1,count do local angle=(start+sweep*(full and (i-1)/count or i/(count+1)))*math.pi/180
        placements[i]={x=tonumber(center.x)+math.cos(angle)*radius,y=tonumber(center.y)+math.sin(angle)*radius,z=tonumber(center.z or 0),rotation_delta=args.rotate_objects==false and 0 or start+sweep*(full and (i-1)/count or i/(count+1))}
    end
    return self:_start_array(args,'radial_array',placements,{center=Util.deepcopy(center),radius=radius,start_angle=start,sweep_angle=sweep,rotate_objects=args.rotate_objects~=false})
end

function TransformSession:start_grid_array(args)
    args=args or {};local rows=math.floor(number(args.rows,1));local columns=math.floor(number(args.columns,1));local origin=args.origin
    if rows<1 or columns<1 or rows*columns>100 then return nil,'grid rows and columns must create between 1 and 100 copies' end
    if not valid_world_point(origin) then return nil,'grid origin requires finite world x, y and z coordinates' end
    local sx,sy,sz=number(args.spacing_x,2),number(args.spacing_y,2),number(args.spacing_z)
    if not finite(sx) or not finite(sy) or not finite(sz) or (math.abs(sx)<0.001 and math.abs(sy)<0.001 and math.abs(sz)<0.001) then return nil,'grid spacing must be finite and non-zero' end
    local yaw=number(args.yaw);local placements={}
    for row=1,rows do for col=1,columns do local dx,dy=rotate_xy((col-1)*sx,(row-1)*sy,yaw)
        placements[#placements+1]={x=tonumber(origin.x)+dx,y=tonumber(origin.y)+dy,z=tonumber(origin.z or 0)+(row-1)*sz,rotation_delta=args.rotate_objects==true and yaw or 0}
    end end
    return self:_start_array(args,'grid',placements,{origin=Util.deepcopy(origin),rows=rows,columns=columns,spacing_x=sx,spacing_y=sy,spacing_z=sz,yaw=yaw})
end

function TransformSession:create_array(kind,args)
    local started,err
    if kind=='path' then started,err=self:start_path_array(args)
    elseif kind=='radial' then started,err=self:start_radial_array(args)
    elseif kind=='grid' then started,err=self:start_grid_array(args)
    else return nil,'unsupported array type' end
    if not started then return nil,err end
    local result,commit_err=self:commit();if not result then self:cancel();return nil,commit_err end
    result.start_warning=err;result.commit_warning=commit_err;return result
end

function TransformSession:start_mirror(args)
    args=args or {}
    if self.session then return nil,'a transform session is already active' end
    local ids,active_id=self:_selection_ids(args)
    local sources,err=object_list(self.app,ids);if not sources then return nil,err end
    active_id=active_id or sources[#sources].id
    local axis=args.axis=='y' and 'y' or (args.axis=='x' and 'x' or nil);if not axis then return nil,'mirror axis must be x or y' end
    local premise_id=sources[1].premise_id
    for _,source in ipairs(sources) do if source.premise_id~=premise_id then return nil,'mirror selection must belong to one location' end end
    local premise=self.app.model:get_premise(premise_id);if not premise then return nil,'location not found for mirror pivot' end
    local pivot=args.mirror_pivot or premise.transform.position;local queue={};local active_index=#sources
    for index,source in ipairs(sources) do
        local copy=duplicate_value(source,tostring(source.name or 'Object')..' Mirror '..string.upper(axis))
        local p=copy.transform.position
        if axis=='x' then p.x=2*number(pivot.x)-number(p.x);copy.transform.rotation.yaw=180-number(copy.transform.rotation.yaw)
        else p.y=2*number(pivot.y)-number(p.y);copy.transform.rotation.yaw=-number(copy.transform.rotation.yaw) end
        table.insert(queue,copy);if source.id==active_id then active_index=index end
    end
    args.active_id=active_id
    return self:_start_created_edit(args,'mirror',ids,sources,queue,{active_index=active_index,axis=axis,mirror_pivot=Util.deepcopy(pivot),source_count=#sources})
end

function TransformSession:start_placement(args)
    args=args or {}
    if self.session then return nil,'a transform session is already active' end
    local kind=args.kind or (self.app.selection and self.app.selection.kind)
    if kind~='asset' and kind~='object' then return nil,'placement requires a Project Asset or placed object selection' end
    local ids,active_id,sources,source_kind,asset
    if kind=='asset' then
        local template,asset_err;template,asset,asset_err=asset_value(self.app,args);if not template then return nil,asset_err end
        ids={asset.id};active_id=asset.id;sources={template};source_kind='asset'
    else
        ids,active_id=self:_selection_ids(args)
        local err;sources,err=object_list(self.app,ids);if not sources then return nil,err end
        if #sources>100 then return nil,'placement is limited to 100 created objects per transaction' end
        active_id=active_id or sources[#sources].id;source_kind='object'
        local premise_id=sources[1].premise_id
        for _,source in ipairs(sources) do if source.premise_id~=premise_id then return nil,'placement selection must belong to one location' end end
    end

    local mode=args.mode or args.source or 'aim';if mode~='aim' and mode~='player' and mode~='preview' and mode~='transform' then return nil,'placement mode must be aim, player, preview, or transform' end
    local target,normal,placement_source
    if type(args.transform)=='table' then
        target=Util.deepcopy(args.transform);mode='transform';placement_source='explicit_transform'
    elseif mode=='preview' then
        if source_kind~='asset' then return nil,'preview placement requires a Project Asset' end
        local preview=self.app.placement:preview_status()
        if not preview.active or preview.asset_id~=asset.id or not preview.transform then return nil,'start a preview for this asset first' end
        target=Util.deepcopy(preview.transform);normal=Util.deepcopy(preview.normal);placement_source=preview.source or 'asset_preview'
    elseif mode=='player' then
        local capture,capture_err=self.app.game:capture_transform();if not capture then return nil,capture_err end
        target=Util.deepcopy(capture);placement_source='player'
    else
        local hit,aim_err=self.app.game:aim_point(args.distance or 12);if not hit then return nil,aim_err end
        local p=Util.deepcopy(hit.position);local offset=number(args.surface_offset,self.app.model.data.settings.snapping.surface_offset)
        if hit.normal and offset~=0 then p.x=p.x+number(hit.normal.x)*offset;p.y=p.y+number(hit.normal.y)*offset;p.z=p.z+number(hit.normal.z)*offset end
        target={position=p,rotation={roll=number(args.roll),pitch=number(args.pitch),yaw=number(args.yaw)}}
        normal=Util.deepcopy(hit.normal);placement_source=hit.source
    end
    target.position=target.position or {x=0,y=0,z=0,w=1};target.rotation=target.rotation or {roll=0,pitch=0,yaw=0}
    if source_kind=='asset' and args.align_surface==true and normal then target.rotation=ViewportTools.surface_rotation(normal,target.rotation.yaw) end

    local pivot_mode=args.placement_pivot_mode=='active' and 'active' or 'center'
    local pivot=requested_pivot(sources,active_id,pivot_mode,nil).position
    local active_index=#sources;for index,source in ipairs(sources) do if source.id==active_id then active_index=index;break end end
    local yaw_delta=number(args.yaw_delta);local queue={}
    for _,source in ipairs(sources) do
        local label=source_kind=='asset' and tostring(source.name or 'Asset') or (tostring(source.name or 'Object')..' Aim Copy')
        local copy=duplicate_value(source,label);local p=source.transform.position
        local ox,oy=rotate_xy(number(p.x)-number(pivot.x),number(p.y)-number(pivot.y),yaw_delta)
        copy.transform.position={x=number(target.position.x)+ox,y=number(target.position.y)+oy,z=number(target.position.z)+(number(p.z)-number(pivot.z)),w=number(target.position.w,1)}
        if source_kind=='asset' then copy.transform.rotation=Util.deepcopy(target.rotation)
        else
            copy.transform.rotation.yaw=number(copy.transform.rotation.yaw)+yaw_delta
            if args.align_surface==true and #sources==1 and normal then copy.transform.rotation=ViewportTools.surface_rotation(normal,copy.transform.rotation.yaw) end
        end
        copy.metadata=copy.metadata or {};copy.metadata.source='transform:placement';copy.metadata.placement_source_kind=source_kind;copy.metadata.placement_source_id=source.id
        table.insert(queue,copy)
    end
    args.active_id=active_id
    local result,warning=self:_start_created_edit(args,'placement',ids,sources,queue,{
        active_index=active_index,source_kind=source_kind,source_count=#sources,asset_id=asset and asset.id or nil,
        mode=mode,placement_source=placement_source,target=Util.deepcopy(target),normal=Util.deepcopy(normal),yaw_delta=yaw_delta,
        placement_pivot_mode=pivot_mode,placement_pivot=Util.deepcopy(pivot),surface_aligned=args.align_surface==true and #sources==1 and normal~=nil,
    })
    if not result then return nil,warning end
    if placement_source=='forward_fallback' then
        local fallback='No surface was hit by the crosshair; placement used the camera-forward fallback point.'
        local s=self.session;if s then s.last_warning=warning and (warning..' '..fallback) or fallback end
        result=self:status();warning=result.last_warning
    end
    return result,warning
end

function TransformSession:start_scatter(args)
    args=args or {}
    if self.session then return nil,'a transform session is already active' end
    local kind=args.kind or (self.app.selection and self.app.selection.kind)
    if kind~='asset' and kind~='object' then return nil,'scatter requires a Project Asset or placed object selection' end
    local ids,active_id,sources,source_kind
    if kind=='asset' then
        local asset,asset_err;local template;template,asset,asset_err=asset_value(self.app,{id=args.id,premise_id=args.premise_id,room_id=args.room_id,yaw=args.asset_yaw});if not template then return nil,asset_err end
        template.metadata.source='scatter:asset:'..tostring(asset.id)
        ids={asset.id};active_id=asset.id;sources={template};source_kind='asset'
    else
        ids,active_id=self:_selection_ids(args)
        local err;sources,err=object_list(self.app,ids);if not sources then return nil,err end
        active_id=active_id or sources[#sources].id;source_kind='object'
        local premise_id=sources[1].premise_id
        for _,source in ipairs(sources) do if source.premise_id~=premise_id then return nil,'scatter selection must belong to one location' end end
    end

    local count=math.floor(number(args.count,6));if count<1 then return nil,'scatter count must be at least one' end
    if count*#sources>100 then return nil,'scatter is limited to 100 created objects per transaction' end
    local radius=number(args.radius,2);if radius<0 then return nil,'scatter radius cannot be negative' end
    local distance=math.max(0.25,number(args.distance,12));local max_drop=math.max(0.5,number(args.max_drop,30))
    local area=args.scatter_area or 'circle'
    if area~='circle' and area~='polygon' and area~='volume' and area~='live_surface' then return nil,'scatter area must be circle, polygon, volume, or live_surface' end
    local polygon
    if area=='polygon' then local polygon_err;polygon,polygon_err=valid_polygon(args.polygon);if not polygon then return nil,polygon_err end end
    local volume
    if area=='volume' then
        volume=self.app.model:get_volume(args.volume_id)
        if not volume then return nil,'volume_id must reference a saved LocationStudio volume' end
        if volume.premise_id~=sources[1].premise_id then return nil,'scatter volume and source objects must belong to the same location' end
        if volume.enabled==false then return nil,'cannot scatter inside a disabled volume' end
    end
    local random_yaw=args.random_yaw~=false
    local drop_to_ground=args.drop_to_ground
    if drop_to_ground==nil then drop_to_ground=area=='circle' or area=='polygon' end
    local align_surface=args.align_surface
    if align_surface==nil then align_surface=area=='live_surface' end
    local requested_seed=math.floor(number(args.seed,1));local random,seed=seeded_random(requested_seed)
    local hit,aim_err
    if area=='circle' or area=='live_surface' or (area=='polygon' and args.z==nil) then
        hit,aim_err=self.app.game:aim_point(distance);if not hit then return nil,aim_err end
    end
    if area=='live_surface' and (not hit.normal or hit.source~='camera_raycast') then
        return nil,'live-surface scatter needs an actual camera ray hit with a surface normal; aim at a visible surface first'
    end
    local volume_origin=volume and volume.transform and volume.transform.position or nil
    local polygon_z=number(args.z,hit and hit.position.z or (sources[1].transform.position.z or 0))
    local normal0, tangent0, tangent1
    if area=='live_surface' then normal0,tangent0,tangent1=surface_basis(hit.normal);if not normal0 then return nil,'live surface hit returned an invalid normal' end end
    local pivot_mode=args.scatter_pivot_mode=='active' and 'active' or 'center'
    local pivot=requested_pivot(sources,active_id,pivot_mode,nil).position
    local active_source_index=#sources
    for index,source in ipairs(sources) do if source.id==active_id then active_source_index=index;break end end
    local queue={};local points={}
    for repeat_index=1,count do
        local target,point_normal,ground_source
        if area=='volume' then
            target=sample_volume(random,volume)
        elseif area=='polygon' then
            local x,y=sample_polygon(random,polygon)
            if not x then return nil,'could not sample inside polygon within bounded attempts; use a less narrow polygon' end
            target={x=x,y=y,z=polygon_z,w=1}
        else
            local angle=random()*math.pi*2;local spread=math.sqrt(random())*radius
            if area=='live_surface' then
                local origin=hit.position
                local ox=tangent0.x*math.cos(angle)*spread+tangent1.x*math.sin(angle)*spread
                local oy=tangent0.y*math.cos(angle)*spread+tangent1.y*math.sin(angle)*spread
                local oz=tangent0.z*math.cos(angle)*spread+tangent1.z*math.sin(angle)*spread
                local probe=math.max(2,radius+1)
                local from={x=origin.x+ox+normal0.x*probe,y=origin.y+oy+normal0.y*probe,z=origin.z+oz+normal0.z*probe,w=1}
                local to={x=origin.x+ox-normal0.x*probe,y=origin.y+oy-normal0.y*probe,z=origin.z+oz-normal0.z*probe,w=1}
                local sampled,sample_err=self.app.game:raycast(from,to,{'Static','Terrain','Dynamic'})
                if not sampled then return nil,string.format('live surface raycast failed for scatter point %d: %s',repeat_index,tostring(sample_err or 'no hit')) end
                target={x=sampled.position.x+normal0.x*number(args.surface_offset,0.02),y=sampled.position.y+normal0.y*number(args.surface_offset,0.02),z=sampled.position.z+normal0.z*number(args.surface_offset,0.02),w=1}
                point_normal=sampled.normal and surface_basis(sampled.normal) or normal0
                ground_source='live_surface_raycast'
            else
                target={x=number(hit.position.x)+math.cos(angle)*spread,y=number(hit.position.y)+math.sin(angle)*spread,z=number(hit.position.z),w=1}
            end
        end
        local yaw=random_yaw and random()*360 or 0
        if drop_to_ground then
            local probe={x=target.x,y=target.y,z=target.z+math.max(2,radius),w=1}
            local ground,ground_err=self.app.game:ground_below(probe,max_drop,args.surface_offset or self.app.model.data.settings.snapping.surface_offset)
            if not ground then return nil,string.format('ground raycast failed for scatter point %d: %s',repeat_index,tostring(ground_err or 'no surface')) end
            target.z=ground.position.z;ground_source=ground.source
        end
        table.insert(points,{x=target.x,y=target.y,z=target.z,yaw=yaw,normal=point_normal,ground_source=ground_source})
        for _,source in ipairs(sources) do
            local copy=duplicate_value(source,string.format('%s Scatter %02d',tostring(source.name or 'Object'),repeat_index))
            local p=source.transform.position;local ox,oy=rotate_xy(number(p.x)-number(pivot.x),number(p.y)-number(pivot.y),yaw)
            copy.transform.position={x=target.x+ox,y=target.y+oy,z=target.z+(number(p.z)-number(pivot.z)),w=number(p.w,1)}
            copy.transform.rotation.yaw=number(source.transform.rotation.yaw)+yaw
            if area=='live_surface' and align_surface and point_normal then copy.transform.rotation=ViewportTools.surface_rotation(point_normal,copy.transform.rotation.yaw) end
            copy.metadata=copy.metadata or {};copy.metadata.source='transform:scatter';copy.metadata.scatter_source_kind=source_kind;copy.metadata.scatter_source_id=source.id;copy.metadata.scatter_seed=seed;copy.metadata.scatter_index=repeat_index;copy.metadata.scatter_area=area
            table.insert(queue,copy)
        end
    end
    args.active_id=active_id
    local result,warning=self:_start_created_edit(args,'scatter',ids,sources,queue,{
        active_index=(count-1)*#sources+active_source_index,repetitions=count,source_count=#sources,source_kind=source_kind,
        radius=radius,distance=distance,seed=seed,random_yaw=random_yaw,drop_to_ground=drop_to_ground,align_surface=align_surface,
        scatter_area=area,volume_id=volume and volume.id or nil,polygon=polygon and polygon.vertices or nil,
        scatter_pivot_mode=pivot_mode,scatter_pivot=Util.deepcopy(pivot),aim_source=hit and hit.source or (volume and 'saved_volume'),aim_position=hit and Util.deepcopy(hit.position) or Util.deepcopy(volume_origin),points=points,
    })
    if not result then return nil,warning end
    if hit and hit.source=='forward_fallback' then
        local fallback='No surface was hit by the crosshair; scatter used the camera-forward fallback center.'
        local s=self.session;if s then s.last_warning=warning and (warning..' '..fallback) or fallback end
        result=self:status();warning=result.last_warning
    end
    return result,warning
end

function TransformSession:update(delta,force)
    local s=self.session;if not s then return nil,'no transform session is active' end
    if s.kind~='grab' then return self:status() end
    s.elapsed=(s.elapsed or 0)+math.max(0,number(delta,0))
    if not force and s.elapsed<s.update_interval then return self:status() end
    s.elapsed=0
    local hit,err=self.app.game:aim_point(s.distance);if not hit then self.last_error=err;s.last_error=err;return nil,err end
    local target=Util.deepcopy(hit.position);local normal=hit.normal
    if normal and s.surface_offset~=0 then
        target.x=target.x+(normal.x or 0)*s.surface_offset;target.y=target.y+(normal.y or 0)*s.surface_offset;target.z=target.z+(normal.z or 0)*s.surface_offset
    end
    if s.snap_position then
        local grid=number(self.app.model.data.settings.snapping.grid,0.25)
        target.x=Util.snap(target.x,grid);target.y=Util.snap(target.y,grid);target.z=Util.snap(target.z,grid)
    end
    local pivot=s.pivot.position;local warning
    for _,id in ipairs(s.ids) do
        local object=self.app.model:get_object(id);local original=s.originals[id]
        if object and original then
            local p=original.transform.position;local rx,ry=rotate_xy(p.x-pivot.x,p.y-pivot.y,s.yaw_delta)
            object.transform.position={x=target.x+rx,y=target.y+ry,z=target.z+(p.z-pivot.z),w=1}
            local rotation=Util.deepcopy(original.transform.rotation)
            rotation.yaw=(number(rotation.yaw)+s.yaw_delta)
            if s.align_surface and s.count==1 then
                if normal then rotation=ViewportTools.surface_rotation(normal,rotation.yaw)
                else warning='Surface alignment is enabled, but the current aim result has no surface normal.' end
            elseif s.align_surface and s.count>1 then warning='Surface alignment applies only to a single-object grab; group roll/pitch is preserved.' end
            object.transform.rotation=rotation
        end
    end
    if hit.source=='forward_fallback' then warning='No surface hit; grab is using the camera-forward fallback point.' end
    s.target=target;s.normal=normal and Util.deepcopy(normal) or nil;s.source=hit.source;s.last_warning=warning;s.last_error=nil
    s.changed=true
    local _,failed=self:_runtime_update(false)
    if #failed>0 then s.last_warning=tostring(#failed)..' World Builder object(s) failed to update live; see the debug log.' end
    self.last_error=nil
    return self:status(),s.last_warning
end

function TransformSession:configure(patch)
    local s=self.session;if not s then return nil,'no transform session is active' end
    if s.kind~='grab' then return nil,'the active transform session is not a crosshair Grab Move' end
    patch=patch or {}
    if patch.distance~=nil then s.distance=math.max(0.25,number(patch.distance,s.distance)) end
    if patch.surface_offset~=nil then s.surface_offset=number(patch.surface_offset,s.surface_offset) end
    if patch.align_surface~=nil then s.align_surface=patch.align_surface==true end
    if patch.snap_position~=nil then s.snap_position=patch.snap_position==true end
    if patch.yaw_delta~=nil then s.yaw_delta=number(patch.yaw_delta,s.yaw_delta) end
    return self:update(0,true)
end

function TransformSession:rotate(delta)
    local s=self.session;if not s then return nil,'no transform session is active' end
    if s.kind=='edit' then return self:adjust({dyaw=delta}) end
    s.yaw_delta=s.yaw_delta+number(delta,0)
    return self:update(0,true)
end

function TransformSession:_apply_edit()
    local s=self.session;if not s or s.kind~='edit' then return nil,'no Transform Edit session is active' end
    local translation=Util.deepcopy(s.translation);local active=s.originals[s.active_id]
    if s.local_space and active then
        translation.x,translation.y=rotate_xy(translation.x,translation.y,number(active.transform.rotation.yaw))
    end
    local pivot=s.pivot.position;local rotation=s.rotation_delta;local factor=s.scale_factor
    for _,id in ipairs(s.ids) do
        local object=self.app.model:get_object(id);local original=s.originals[id]
        if object and original then
            local p=original.transform.position
            local ox=(number(p.x)-number(pivot.x))*factor;local oy=(number(p.y)-number(pivot.y))*factor
            local rx,ry=rotate_xy(ox,oy,rotation.yaw)
            object.transform.position={
                x=number(pivot.x)+rx+translation.x,
                y=number(pivot.y)+ry+translation.y,
                z=number(pivot.z)+(number(p.z)-number(pivot.z))*factor+translation.z,
                w=number(p.w,1),
            }
            local r=original.transform.rotation
            object.transform.rotation={roll=number(r.roll)+rotation.roll,pitch=number(r.pitch)+rotation.pitch,yaw=number(r.yaw)+rotation.yaw}
            object.size={
                x=math.max(0.001,number(original.size and original.size.x,1)*factor),
                y=math.max(0.001,number(original.size and original.size.y,1)*factor),
                z=math.max(0.001,number(original.size and original.size.z,1)*factor),
            }
        end
    end
    s.target={x=number(pivot.x)+translation.x,y=number(pivot.y)+translation.y,z=number(pivot.z)+translation.z,w=1}
    local _,failed=self:_runtime_update(true)
    if #failed>0 then s.last_warning=tostring(#failed)..' live object(s) failed to refresh; cancel is still available and details are in the debug log.' else s.last_warning=nil end
    if self.app.selection then self.app.selection.revision=self.app.selection.revision+1 end
    return self:status(),s.last_warning
end

function TransformSession:adjust(patch)
    local s=self.session;if not s or s.kind~='edit' then return nil,'no Transform Edit session is active' end
    patch=patch or {}
    local next_translation={
        x=s.translation.x+number(patch.dx),
        y=s.translation.y+number(patch.dy),
        z=s.translation.z+number(patch.dz),
    }
    local next_rotation={
        roll=s.rotation_delta.roll+number(patch.droll),
        pitch=s.rotation_delta.pitch+number(patch.dpitch),
        yaw=s.rotation_delta.yaw+number(patch.dyaw),
    }
    local scale_delta=patch.scale_factor==nil and 1 or number(patch.scale_factor,1)
    local next_scale=s.scale_factor*scale_delta
    if next_scale<=0.001 then return nil,'scale factor must remain greater than zero' end
    if s.count>1 and (math.abs(next_rotation.roll)>0.0001 or math.abs(next_rotation.pitch)>0.0001) then
        return nil,'group Transform Edit supports yaw rotation only; edit one object for roll or pitch'
    end
    if math.abs(next_scale-1)>0.0001 then
        for _,id in ipairs(s.ids) do
            local object=self.app.model:get_object(id)
            if object and not is_world_builder(object) then return nil,'live scaling requires World Builder resources; '..tostring(object.name or id)..' uses CET entity spawning' end
        end
    end
    s.translation=next_translation;s.rotation_delta=next_rotation;s.scale_factor=next_scale
    if patch.local_space~=nil then s.local_space=patch.local_space==true end
    s.changed=is_creation(s) or math.abs(s.translation.x)>0.000001 or math.abs(s.translation.y)>0.000001 or math.abs(s.translation.z)>0.000001
        or math.abs(s.rotation_delta.roll)>0.000001 or math.abs(s.rotation_delta.pitch)>0.000001 or math.abs(s.rotation_delta.yaw)>0.000001
        or math.abs(s.scale_factor-1)>0.000001
    local result,warning=self:_apply_edit()
    if result and self.app.logger then self.app.logger:debug(is_creation(s) and creation_scope(s) or 'transform:edit','adjusted',{count=s.count,dx=s.translation.x,dy=s.translation.y,dz=s.translation.z,roll=s.rotation_delta.roll,pitch=s.rotation_delta.pitch,yaw=s.rotation_delta.yaw,scale=s.scale_factor,local_space=s.local_space,failed=#(s.failed or {})}) end
    return result,warning
end

function TransformSession:reset_edit()
    local s=self.session;if not s or s.kind~='edit' then return nil,'no Transform Edit session is active' end
    s.translation={x=0,y=0,z=0};s.rotation_delta={roll=0,pitch=0,yaw=0};s.scale_factor=1;s.changed=is_creation(s)
    local result,warning=self:_apply_edit()
    if result and self.app.logger then self.app.logger:info(is_creation(s) and creation_scope(s) or 'transform:edit','reset',{count=s.count}) end
    return result,warning
end

local function history_before_commit(app,s)
    local before=Util.deepcopy(app.model.data)
    for _,object in ipairs(before.objects or {}) do
        local original=s.originals[object.id]
        if original then object.transform=Util.deepcopy(original.transform);object.size=Util.deepcopy(original.size);object.updated_at=original.updated_at end
    end
    return before
end

function TransformSession:commit()
    local s=self.session;if not s then return nil,'no transform session is active' end
    local before=s.changed and (s.history_before or history_before_commit(self.app,s)) or nil
    local now=Util.now_iso()
    if s.changed then
        for _,id in ipairs(s.ids) do local object=self.app.model:get_object(id);if object then object.updated_at=now end end
        local label=s.operation and ('Transform '..tostring(s.operation)) or (s.kind=='grab' and 'Grab move' or 'Transform edit')
        self.app.model:push_history(before,label..' ('..#s.ids..' object'..(#s.ids==1 and '' or 's')..')');self.app.model:touch()
    end
    local _,failed=self:_runtime_update(true)
    for _,id in ipairs(s.ids) do
        local object=self.app.model:get_object(id);local state=s.runtime[id]
        if object and state and state.spawn_on_commit and not self.app.placement:is_tracked(object) then
            local _,spawn_err=self.app.placement:spawn(object);if spawn_err then table.insert(failed,{id=id,error=tostring(spawn_err)}) end
        end
    end
    if self.app.active_object_group_id and self.app.assemblies then self.app.assemblies:refresh_group_pivot(self.app.active_object_group_id,s.active_id) end
    if self.app.selection then self.app.selection.revision=self.app.selection.revision+1 end
    if s.changed then self.app:mark_dirty() end
    local result={committed=true,changed=s.changed,kind=s.kind,operation=s.operation,count=s.count,ids=Util.deepcopy(s.ids),created_ids=Util.deepcopy(s.created_ids),source_ids=Util.deepcopy(s.source_ids),creation=Util.deepcopy(s.creation),target=Util.deepcopy(s.target),source=s.source,yaw_delta=s.yaw_delta,translation=Util.deepcopy(s.translation),rotation_delta=Util.deepcopy(s.rotation_delta),scale_factor=s.scale_factor,failed=failed}
    self.session=nil;self.last_result=Util.deepcopy(result);self.last_error=nil
    if self.app.logger then self.app.logger:info(result.created_ids and ('transform:'..tostring(result.operation)) or ('transform:'..tostring(result.kind)),'committed',{count=result.count,source=result.source,yaw_delta=result.yaw_delta,scale=result.scale_factor,failed=#failed}) end
    return result,#failed>0 and (tostring(#failed)..' runtime object(s) failed to update after commit.') or nil
end

function TransformSession:cancel()
    local s=self.session;if not s then return nil,'no transform session is active' end
    if is_creation(s) then
        local failed={}
        for _,id in ipairs(s.created_ids or s.ids) do
            local object=self.app.model:get_object(id)
            if object then local ok,err=self.app.placement:despawn(object);if not ok then table.insert(failed,{id=id,error=tostring(err)}) end end
        end
        if #failed>0 then
            s.failed=failed;s.last_error='Creation cancel retained the copies because '..tostring(#failed)..' live object(s) could not be removed.';self.last_error=s.last_error
            if self.app.logger then self.app.logger:error(creation_scope(s),'cancel_blocked',{count=s.count,failed=failed}) end
            return nil,s.last_error
        end
        local remove={};for _,id in ipairs(s.created_ids or s.ids) do remove[id]=true end
        local kept={};for _,object in ipairs(self.app.model.data.objects) do if not remove[object.id] then table.insert(kept,object) end end
        self.app.model.data.objects=kept
        if s.history_before and s.history_before.project then self.app.model.data.project.updated_at=s.history_before.project.updated_at end
        local prior=s.selection_before or {}
        if self.app.selection then restore_selection(self.app,prior) end
        self.app.active_object_group_id=prior.active_group_id
        self.app.dirty=s.dirty_before==true;self.app.dirty_since=s.dirty_since_before or self.app.dirty_since
        local result={cancelled=true,kind=s.kind,operation=s.operation,count=s.count,ids=Util.deepcopy(s.ids),created_ids=Util.deepcopy(s.created_ids),source_ids=Util.deepcopy(s.source_ids),creation=Util.deepcopy(s.creation),failed={}}
        self.session=nil;self.last_result=Util.deepcopy(result);self.last_error=nil
        if self.app.logger then self.app.logger:info(creation_scope(s),'cancelled',{count=result.count,removed=#(result.created_ids or {})}) end
        return result
    end
    self:_restore_originals()
    local failed={}
    for _,id in ipairs(s.ids) do
        local object=self.app.model:get_object(id);local state=s.runtime[id]
        if object and state then
            if state.spawned_for_session and not state.was_live then
                local ok,err=self.app.placement:despawn(object);if not ok then table.insert(failed,{id=id,error=tostring(err)}) end
            elseif state.was_live then
                local result,err
                if is_world_builder(object) then result,err=self.app.runtime_shell:update_object(object,{silent=true}) else result,err=self.app.placement:refresh(object) end
                if not result then table.insert(failed,{id=id,error=tostring(err)}) end
            end
        end
    end
    if self.app.selection then self.app.selection.revision=self.app.selection.revision+1 end
    local result={cancelled=true,kind=s.kind,count=s.count,ids=Util.deepcopy(s.ids),failed=failed}
    self.session=nil;self.last_result=Util.deepcopy(result);self.last_error=nil
    if self.app.logger then self.app.logger:info('transform:'..tostring(result.kind),'cancelled',{count=result.count,failed=#failed}) end
    return result,#failed>0 and (tostring(#failed)..' runtime object(s) failed to restore after cancel.') or nil
end

function TransformSession:status()
    local s=self.session
    if not s then return {active=false,last_error=self.last_error,last_result=Util.deepcopy(self.last_result)} end
    return {
        active=true,kind=s.kind,operation=s.operation,count=s.count,ids=Util.deepcopy(s.ids),created_ids=Util.deepcopy(s.created_ids),source_ids=Util.deepcopy(s.source_ids),creation=Util.deepcopy(s.creation),active_id=s.active_id,pivot_mode=s.pivot_mode,pivot=Util.deepcopy(s.pivot),distance=s.distance,
        surface_offset=s.surface_offset,align_surface=s.align_surface,snap_position=s.snap_position,yaw_delta=s.yaw_delta,
        translation=Util.deepcopy(s.translation),rotation_delta=Util.deepcopy(s.rotation_delta),scale_factor=s.scale_factor,local_space=s.local_space,changed=s.changed,
        target=Util.deepcopy(s.target),normal=Util.deepcopy(s.normal),source=s.source,last_warning=s.last_warning,last_error=s.last_error,
        live_world_builder=s.live_world_builder,deferred_cet=s.deferred_cet,live_updates=s.live_updates,failed=Util.deepcopy(s.failed),started_at=s.started_at,
    }
end

return TransformSession
