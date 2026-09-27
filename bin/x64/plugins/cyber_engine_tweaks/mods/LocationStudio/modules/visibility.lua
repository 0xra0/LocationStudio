local Util=require('modules/util')

-- Occlusion and visibility helpers.
--   * Authors World Builder Static Occluders (worldStaticOccluderMeshNode):
--     box, one-sided plane or two-sided plane, including one-click occluders
--     covering a room's solid wall spans (door/window gaps left open).
--   * Estimates potentially visible rooms (PVS) from saved cameras using the
--     authored geometry: camera view cone, room walls with their door/window
--     openings, and authored occluders. Optional live collision rays cross-check.
--   * Flags large meshes that no saved camera can see but that stay enabled.
-- REDengine visibility volumes/portals are not exposed by World Builder, so
-- they are not authored here.
local Visibility={};Visibility.__index=Visibility

-- World Builder occluder meshes (occluder.lua occluderPaths, 1-based index).
local OCCLUDER_MESHES={box=1,plane_one_sided=2,plane_two_sided=3}
local OCCLUDER_NAMES={[1]='box',[2]='plane_one_sided',[3]='plane_two_sided'}
local PLANE_THICKNESS=0.05
local WALLS={'north','south','east','west'}

local function num(v,f) v=tonumber(v);if v==nil then return f end;return v end
local function vec(p) return {x=num(p and p.x,0),y=num(p and p.y,0),z=num(p and p.z,0)} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function len(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
local function rot2(x,y,deg) local r=math.rad(deg or 0);local c,s=math.cos(r),math.sin(r);return x*c-y*s,x*s+y*c end

function Visibility.new(app) return setmetatable({app=app,last_pvs=nil,last_hidden=nil},Visibility) end

function Visibility:capabilities()
    return {occluders=self.app.world_builder~=nil,occluder_meshes={'box','plane_one_sided','plane_two_sided'},
        visibility_volumes=false,
        note='World Builder exposes Static Occluders only; REDengine visibility volumes/portals are not authorable through it.'}
end

function Visibility:_blocked()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

-- Occluders -------------------------------------------------------------------

local function occluder_scale(mesh,size)
    size=size or {}
    local out={x=num(size.x,4),y=num(size.y,mesh==1 and 4 or 1),z=num(size.z,3)}
    for axis,v in pairs(out) do if v<0.05 or v>1000 then return nil,'occluder size.'..axis..' must be between 0.05 and 1000 m' end end
    return out
end

function Visibility:is_occluder(object)
    local wb=object and object.metadata and object.metadata.world_builder
    return wb~=nil and wb.definition_key=='occluder'
end

function Visibility:_occluder_object(args,transform,scale,mesh)
    local name=Util.trim(args.name or '')~='' and Util.trim(args.name) or ('Occluder '..OCCLUDER_NAMES[mesh])
    local data={occluderMesh=mesh,occluderType=math.floor(num(args.occluder_type,0)),scale=Util.deepcopy(scale),previewed=args.visualize~=false,
        modulePath='meta/occluder',dataType='Static Occluder'}
    return {premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id or self.app.selected_room_id,name=name,kind='meta',template='',layer='shell',
        transform=transform,size=Util.deepcopy(scale),enabled=true,
        metadata={source='LocationStudio visibility helpers',occluder={mesh=OCCLUDER_NAMES[mesh],occluder_type=data.occluderType,room_wall=args.room_wall},
            world_builder={definition_key='occluder',category='Meta',variant='Occluder',class_module='modules/classes/spawn/meta/occluder',module_path='meta/occluder',
                resource_name='Static Occluder',resource_path='',entry={name=name,fileName=name,data=data},apply_scale=true}}}
end

function Visibility:create_occluder(args)
    args=args or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local mesh=OCCLUDER_MESHES[args.mesh or 'box'];if not mesh then return nil,'mesh must be box, plane_one_sided or plane_two_sided' end
    local scale,err=occluder_scale(mesh,args.size);if not scale then return nil,err end
    local transform,source
    if type(args.transform)=='table' and type(args.transform.position)=='table' then transform=Util.deepcopy(args.transform);transform.rotation=transform.rotation or {roll=0,pitch=0,yaw=0};source='explicit'
    elseif args.source=='player' then transform,err=self.app.game:capture_transform();if not transform then return nil,err end;source='player'
    else local hit;hit,err=self.app.game:aim_point(args.distance or 10);if not hit then return nil,err end;transform={position=hit.position,rotation={roll=0,pitch=0,yaw=0}};source=hit.source end
    for _,axis in ipairs({'roll','pitch','yaw'}) do if args[axis]~=nil then transform.rotation[axis]=num(args[axis],0) end end
    self.app.model:snapshot()
    local object=self.app.model:add_object(self:_occluder_object(args,transform,scale,mesh))
    if not object then return nil,'project model rejected the occluder' end
    self.app.selection:set('object',object.id);self.app:mark_dirty()
    local result={object=object,placement_source=source,spawned=false}
    if args.spawn~=false then local id,spawn_err=self.app.placement:spawn(object);if id then result.spawned=true else result.spawn_error=tostring(spawn_err) end end
    return result
end

local function solid_spans(room,wall)
    local along=(wall=='north' or wall=='south') and room.size.width or room.size.depth
    local half=along/2;local gaps={}
    for _,o in ipairs(room.openings or {}) do
        if o.wall==wall then local l,r=math.max(-half,o.offset-o.width/2),math.min(half,o.offset+o.width/2);if r>l then gaps[#gaps+1]={l,r} end end
    end
    table.sort(gaps,function(a,b) return a[1]<b[1] end)
    local spans,cursor={}, -half
    for _,g in ipairs(gaps) do if g[1]>cursor then spans[#spans+1]={cursor,g[1]} end;cursor=math.max(cursor,g[2]) end
    if cursor<half then spans[#spans+1]={cursor,half} end
    return spans
end

local function wall_frame(room,wall,along)
    if wall=='north' then return along,room.size.depth/2,0 end
    if wall=='south' then return along,-room.size.depth/2,0 end
    if wall=='east' then return room.size.width/2,along,90 end
    return -room.size.width/2,along,90
end

-- Two-sided plane occluders on every solid span of a room's walls. Openings
-- stay open so the occluders never hide what a doorway or window shows.
function Visibility:occlude_room(args)
    args=args or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local room=self.app.model:get_room(args.room_id or self.app.selected_room_id);if not room then return nil,'select a room or pass room_id' end
    local walls=type(args.walls)=='table' and #args.walls>0 and args.walls or WALLS
    local inset=num(args.inset,0.05);local values={}
    local ryaw=num(room.transform.rotation.yaw,0);local base=room.transform.position
    for _,wall in ipairs(walls) do
        for i,span in ipairs(solid_spans(room,wall)) do
            local length=span[2]-span[1]
            if length>=num(args.min_span,0.5) then
                local lx,ly,wyaw=wall_frame(room,wall,(span[1]+span[2])/2)
                -- Pull the plane slightly into the room so it never pokes through the far side of the wall.
                if wall=='north' then ly=ly-inset elseif wall=='south' then ly=ly+inset elseif wall=='east' then lx=lx-inset else lx=lx+inset end
                local wx,wy=rot2(lx,ly,ryaw)
                values[#values+1]=self:_occluder_object({name=room.name..' / '..wall..' occluder '..i,premise_id=room.premise_id,room_id=room.id,visualize=args.visualize,
                    occluder_type=args.occluder_type,room_wall={room_id=room.id,wall=wall,span=i}},
                    {position={x=base.x+wx,y=base.y+wy,z=base.z+room.size.height/2,w=1},rotation={roll=0,pitch=0,yaw=ryaw+wyaw}},
                    {x=length,y=1,z=room.size.height},3)
            end
        end
    end
    if #values==0 then return nil,'the selected walls have no solid span long enough for an occluder' end
    local created=self.app.model:add_objects(values)
    self.app:mark_dirty()
    local spawned,failed=0,{}
    if args.spawn~=false then for _,o in ipairs(created) do local id,err=self.app.placement:spawn(o);if id then spawned=spawned+1 else failed[#failed+1]={object_id=o.id,error=tostring(err)} end end end
    return {room_id=room.id,created=created,count=#created,spawned=spawned,failed=failed}
end

function Visibility:update_occluder(id,patch)
    patch=patch or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local object=self.app.model:get_object(id);if not self:is_occluder(object) then return nil,'object is not an occluder' end
    if object.locked then return nil,'occluder is locked' end
    local data=object.metadata.world_builder.entry.data
    local mesh=data.occluderMesh or 1
    if patch.mesh then mesh=OCCLUDER_MESHES[patch.mesh];if not mesh then return nil,'mesh must be box, plane_one_sided or plane_two_sided' end end
    local scale=object.size
    if patch.size then local err;scale,err=occluder_scale(mesh,patch.size);if not scale then return nil,err end end
    self.app.model:snapshot('Update occluder')
    data.occluderMesh=mesh;data.scale=Util.deepcopy(scale);object.size=Util.deepcopy(scale)
    if patch.occluder_type~=nil then data.occluderType=math.floor(num(patch.occluder_type,0)) end
    if patch.visualize~=nil then data.previewed=patch.visualize==true end
    for _,axis in ipairs({'roll','pitch','yaw'}) do if patch[axis]~=nil then object.transform.rotation[axis]=num(patch[axis],0) end end
    object.metadata.occluder=object.metadata.occluder or {};object.metadata.occluder.mesh=OCCLUDER_NAMES[mesh];object.metadata.occluder.occluder_type=data.occluderType
    self.app.model:touch();self.app:mark_dirty()
    local result={object=object,respawned=false}
    if self.app.placement:is_tracked(object) then
        local ok,err=self.app.placement:despawn(object)
        if ok then local sid,serr=self.app.placement:spawn(object);result.respawned=sid~=nil;if not sid then result.warning='occluder respawn failed: '..tostring(serr) end
        else result.warning='old occluder could not be removed: '..tostring(err) end
    end
    return result
end

function Visibility:list_occluders(args)
    args=args or {};local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        if self:is_occluder(o) and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) then
            local d=o.metadata.world_builder.entry.data or {}
            out[#out+1]={id=o.id,name=o.name,mesh=OCCLUDER_NAMES[d.occluderMesh or 1],size=Util.deepcopy(o.size),occluder_type=d.occluderType or 0,
                visualized=d.previewed~=false,room_id=o.room_id,room_wall=o.metadata.occluder and o.metadata.occluder.room_wall,enabled=o.enabled~=false,
                spawned=o.runtime and o.runtime.spawned==true or false,transform=Util.deepcopy(o.transform)}
        end
    end
    return {items=out,count=#out}
end

-- Line-of-sight geometry -----------------------------------------------------

-- Walls of every enabled room with their openings, in room-local frames.
function Visibility:_walls(premise_id)
    local out={}
    for _,room in ipairs(self.app.model.data.rooms or {}) do
        if room.enabled~=false and (not premise_id or room.premise_id==premise_id) then out[#out+1]=room end
    end
    return out
end

-- Does segment a->b pass through a solid part of any room wall?
local function wall_blocks(rooms,a,b,skip_room_id)
    for _,room in ipairs(rooms) do
        local base=room.transform.position;local yaw=num(room.transform.rotation.yaw,0)
        local ax,ay=rot2(a.x-base.x,a.y-base.y,-yaw);local bx,by=rot2(b.x-base.x,b.y-base.y,-yaw)
        local az,bz=a.z-base.z,b.z-base.z
        local w2,d2,h=room.size.width/2,room.size.depth/2,room.size.height
        for _,wall in ipairs(WALLS) do
            local plane,axis_a,axis_b,along_a,along_b,extent
            if wall=='north' or wall=='south' then plane=wall=='north' and d2 or -d2;axis_a,axis_b=ay,by;along_a,along_b=ax,bx;extent=w2
            else plane=wall=='east' and w2 or -w2;axis_a,axis_b=ax,bx;along_a,along_b=ay,by;extent=d2 end
            if (axis_a-plane)*(axis_b-plane)<0 then
                local t=(plane-axis_a)/(axis_b-axis_a)
                local along=along_a+(along_b-along_a)*t;local z=az+(bz-az)*t
                if along>=-extent and along<=extent and z>=0 and z<=h then
                    local open=false
                    for _,o in ipairs(room.openings or {}) do
                        if o.wall==wall and along>=o.offset-o.width/2 and along<=o.offset+o.width/2 and z>=o.sill and z<=o.sill+o.height then open=true;break end
                    end
                    if not open then return true,{room_id=room.id,room=room.name,wall=wall} end
                end
            end
        end
    end
    return false
end

-- Slab test of segment a->b against an occluder's box (yaw-oriented).
local function occluder_blocks(occluders,a,b)
    for _,oc in ipairs(occluders) do
        local ax,ay=rot2(a.x-oc.cx,a.y-oc.cy,-oc.yaw);local bx,by=rot2(b.x-oc.cx,b.y-oc.cy,-oc.yaw)
        local p0={ax,ay,a.z-oc.cz};local d={bx-ax,by-ay,(b.z-oc.cz)-(a.z-oc.cz)};local half={oc.hx,oc.hy,oc.hz}
        local t0,t1=0,1;local hit=true
        for i=1,3 do
            if math.abs(d[i])<1e-9 then if math.abs(p0[i])>half[i] then hit=false;break end
            else
                local u,v=(-half[i]-p0[i])/d[i],(half[i]-p0[i])/d[i];if u>v then u,v=v,u end
                t0=math.max(t0,u);t1=math.min(t1,v);if t0>t1 then hit=false;break end
            end
        end
        if hit then return true,{occluder_id=oc.id,occluder=oc.name} end
    end
    return false
end

function Visibility:_occluders(premise_id)
    local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        if self:is_occluder(o) and o.enabled~=false and (not premise_id or o.premise_id==premise_id) then
            local d=o.metadata.world_builder.entry.data or {};local s=o.size or d.scale or {x=1,y=1,z=1};local mesh=d.occluderMesh or 1
            local p=o.transform.position
            out[#out+1]={id=o.id,name=o.name,cx=p.x,cy=p.y,cz=p.z,yaw=num(o.transform.rotation.yaw,0),
                hx=num(s.x,1)/2,hy=mesh==1 and num(s.y,1)/2 or PLANE_THICKNESS,hz=num(s.z,1)/2}
        end
    end
    return out
end

-- Camera direction: authored look-at point first, then rotation (game
-- convention: yaw 0 faces +Y, positive yaw turns toward -X).
local function camera_frame(camera)
    local p=vec(camera.transform.position)
    local look=camera.look_at
    if look and (num(look.x,0)~=0 or num(look.y,0)~=0 or num(look.z,0)~=0) then
        local d=sub(vec(look),p);local l=len(d)
        if l>0.01 then return p,{x=d.x/l,y=d.y/l,z=d.z/l},'look_at' end
    end
    local r=camera.transform.rotation or {};local yaw,pitch=math.rad(num(r.yaw,0)),math.rad(num(r.pitch,0))
    return p,{x=-math.sin(yaw)*math.cos(pitch),y=math.cos(yaw)*math.cos(pitch),z=math.sin(pitch)},'rotation'
end

-- Conservative view cone: the saved FOV is treated as vertical and widened to a
-- 16:9 horizontal FOV, and the cone uses the wider half-angle.
local function in_view(origin,forward,fov,point)
    local d=sub(point,origin);local l=len(d);if l<0.01 then return true,0 end
    local v=math.rad(math.max(1,math.min(179,num(fov,50))))
    local hfov=2*math.atan(math.tan(v/2)*16/9)
    local cos_angle=(d.x*forward.x+d.y*forward.y+d.z*forward.z)/l
    return cos_angle>=math.cos(math.min(math.pi,hfov/2+math.rad(2))),l
end

local function room_samples(room)
    local out={};local w,d,h=room.size.width,room.size.depth,room.size.height
    local base=room.transform.position;local yaw=num(room.transform.rotation.yaw,0)
    for _,fx in ipairs({-0.35,0,0.35}) do for _,fy in ipairs({-0.35,0,0.35}) do for _,fz in ipairs({0.25,0.75}) do
        local x,y=rot2(fx*w,fy*d,yaw);out[#out+1]={x=base.x+x,y=base.y+y,z=base.z+fz*h}
    end end end
    return out
end

local function inside_room(room,p)
    local base=room.transform.position;local x,y=rot2(p.x-base.x,p.y-base.y,-num(room.transform.rotation.yaw,0))
    return math.abs(x)<=room.size.width/2 and math.abs(y)<=room.size.depth/2 and p.z>=base.z and p.z<=base.z+room.size.height
end

function Visibility:_line_clear(rooms,occluders,a,b)
    local blocked,by=wall_blocks(rooms,a,b);if blocked then return false,by end
    blocked,by=occluder_blocks(occluders,a,b);if blocked then return false,by end
    return true
end

-- Potentially visible rooms from each enabled saved camera.
function Visibility:pvs(args)
    args=args or {}
    local model=self.app.model;local premise_id=args.premise_id~='' and args.premise_id or nil
    local max_distance=num(args.max_distance,150)
    -- Walls and occluders block sight whatever premise they belong to; only the
    -- reported rooms are limited to the requested premise.
    local rooms=self:_walls(premise_id);local blockers=self:_walls(nil);local occluders=self:_occluders(nil)
    local wanted={};if type(args.camera_ids)=='table' then for _,id in ipairs(args.camera_ids) do wanted[id]=true end end
    local cameras={}
    for _,c in ipairs(model.data.cameras or {}) do
        if c.enabled~=false and (next(wanted)==nil or wanted[c.id]) and (not premise_id or c.premise_id==premise_id or next(wanted)~=nil) then cameras[#cameras+1]=c end
    end
    if #cameras==0 then return nil,'no enabled saved cameras in scope; create cameras in Spatial → Cameras' end
    local results={};local seen_by={}
    for _,camera in ipairs(cameras) do
        local origin,forward,source=camera_frame(camera)
        local visible,hidden={}, {}
        for _,room in ipairs(rooms) do
            local contains=inside_room(room,origin)
            local clear,in_cone,nearest,blocked_names=0,0,nil,{}
            local samples=room_samples(room)
            for _,q in ipairs(samples) do
                local ok_view,dist=in_view(origin,forward,camera.fov,q)
                if ok_view and dist<=max_distance then
                    in_cone=in_cone+1
                    local ok,by=self:_line_clear(blockers,occluders,origin,q)
                    if ok then clear=clear+1;nearest=math.min(nearest or dist,dist)
                    elseif by then blocked_names[(by.occluder or (tostring(by.room)..' '..tostring(by.wall)))]=true end
                end
            end
            local row={room_id=room.id,name=room.name,contains_camera=contains,visible_samples=clear,in_view_samples=in_cone,samples=#samples,
                visible_fraction=math.floor(clear/#samples*100+0.5)/100,nearest_visible_distance=nearest and math.floor(nearest*10+0.5)/10 or nil}
            if clear>0 then visible[#visible+1]=row;seen_by[room.id]=seen_by[room.id] or {};table.insert(seen_by[room.id],camera.id)
            else
                local list={};for k in pairs(blocked_names) do list[#list+1]=k end;table.sort(list)
                row.reason=in_cone==0 and 'outside the camera view cone or beyond max_distance' or 'every line of sight is blocked';row.blocked_by=list
                hidden[#hidden+1]=row
            end
        end
        table.sort(visible,function(a,b) return a.visible_fraction>b.visible_fraction end)
        local entry={camera_id=camera.id,name=camera.name,fov=camera.fov,direction_source=source,position=origin,visible_rooms=visible,hidden_rooms=hidden}
        if args.live==true then entry.live=self:_live_check(origin,visible) end
        results[#results+1]=entry
    end
    local unseen={}
    for _,room in ipairs(rooms) do if not seen_by[room.id] then unseen[#unseen+1]={room_id=room.id,name=room.name} end end
    local report={cameras=results,rooms_never_visible=unseen,room_count=#rooms,occluder_count=#occluders,max_distance=max_distance,
        method='authored room walls with door/window openings, authored occluders, conservative camera view cone',
        caveat='Potentially visible = at least one sampled point has a clear authored line of sight. Vanilla geometry, props and mesh shapes are not included; use live=true to cross-check with collision rays.'}
    self.last_pvs=report
    return report
end

-- Live cross-check: rays against static collision toward the visible rooms' centres.
function Visibility:_live_check(origin,visible)
    local out={}
    for _,row in ipairs(visible) do
        local room=self.app.model:get_room(row.room_id)
        local target={x=room.transform.position.x,y=room.transform.position.y,z=room.transform.position.z+room.size.height*0.5}
        local ok,hit=pcall(function() return self.app.game:raycast(origin,target,{'Static'}) end)
        if not ok then out[#out+1]={room_id=row.room_id,error=tostring(hit)}
        else
            local blocked=hit and len(sub(vec(hit.position),origin))+0.3<len(sub(target,origin)) or false
            out[#out+1]={room_id=row.room_id,centre_ray_blocked=blocked,hit_group=hit and hit.group or nil}
        end
    end
    return out
end

-- Large meshes with known bounds that no saved camera can see.
function Visibility:hidden_meshes(args)
    args=args or {}
    local pvs,err=self:pvs(args);if not pvs then return nil,err end
    local premise_id=args.premise_id~='' and args.premise_id or nil
    local min_dim=num(args.min_dimension,6);local min_volume=num(args.min_volume,40);local max_distance=num(args.max_distance,150)
    local blockers=self:_walls(nil);local occluders=self:_occluders(nil)
    local cameras={};for _,entry in ipairs(pvs.cameras) do cameras[#cameras+1]=self.app.model:get_camera(entry.camera_id) end
    local flagged,unknown={},0
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local wb=o.metadata and not o.metadata.reference_area_id and o.metadata.world_builder
        local is_mesh=wb and (tostring(wb.definition_key):find('^mesh_') or wb.definition_key=='entity_template')
        if is_mesh and o.enabled~=false and (not premise_id or o.premise_id==premise_id) then
            local bounds=self.app.asset_bounds and self.app.asset_bounds:world_aabb(o.id)
            if not bounds then unknown=unknown+1 else
                local a=bounds.aabb;local dx,dy,dz=a.max.x-a.min.x,a.max.y-a.min.y,a.max.z-a.min.z
                if math.max(dx,dy,dz)>=min_dim or dx*dy*dz>=min_volume then
                    local points={{x=(a.min.x+a.max.x)/2,y=(a.min.y+a.max.y)/2,z=(a.min.z+a.max.z)/2}}
                    for _,x in ipairs({a.min.x+dx*0.05,a.max.x-dx*0.05}) do for _,y in ipairs({a.min.y+dy*0.05,a.max.y-dy*0.05}) do for _,z in ipairs({a.min.z+dz*0.05,a.max.z-dz*0.05}) do points[#points+1]={x=x,y=y,z=z} end end end
                    local seen=false
                    for _,camera in ipairs(cameras) do
                        local origin,forward=camera_frame(camera)
                        for _,q in ipairs(points) do
                            local ok_view,dist=in_view(origin,forward,camera.fov,q)
                            if ok_view and dist<=max_distance and self:_line_clear(blockers,occluders,origin,q) then seen=true;break end
                        end
                        if seen then break end
                    end
                    if not seen then
                        local live=o.runtime and o.runtime.spawned==true
                        flagged[#flagged+1]={id=o.id,name=o.name,definition=wb.definition_key,room_id=o.room_id,dimensions={x=dx,y=dy,z=dz},
                            volume=math.floor(dx*dy*dz+0.5),spawned=live,
                            suggestion=live and 'Not visible from any saved camera but spawned: disable it, move it into a world-state/scene variant, or confirm a camera is missing.'
                                or 'Not visible from any saved camera: consider removing it from the export or adding an occluder-friendly layout.'}
                    end
                end
            end
        end
    end
    table.sort(flagged,function(a,b) return a.volume>b.volume end)
    local report={flagged=flagged,count=#flagged,meshes_without_bounds=unknown,cameras=#cameras,thresholds={min_dimension=min_dim,min_volume=min_volume,max_distance=max_distance},
        note='Uses imported asset bounds (wb_bounds_import). Hidden means hidden from every saved camera by authored walls/occluders or out of view; gameplay views not covered by a saved camera are not considered.'}
    self.last_hidden=report
    return report
end

return Visibility
