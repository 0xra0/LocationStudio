local Util=require('modules/util')

-- Persistent editable splines. Each control point has cubic Bezier handles
-- (offsets from the point) and a mode:
--   auto    handles derived from the neighbours (Catmull-Rom, scaled by tension)
--   aligned handles stay collinear; editing one mirrors the other's direction
--   free    handles are independent (corners/kinks)
--   linear  zero handles (straight segments)
-- A spline is open or closed and is sampled by arc length. The same spline
-- drives cables/fences/roads, object distribution, NPC routes, camera paths
-- and a native World Builder worldSplineNode. Every such output is recorded as
-- a "use" so it can be regenerated after the curve changes.
local Splines={};Splines.__index=Splines

local MAX_POINTS=256
local LENGTH_STEPS=32
local PREVIEW_PREFIX='__spline_preview_'
local USE_KINDS={cable=true,fence=true,road=true,distribute=true,npc_path=true,camera_path=true,native_spline=true}

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function v3(x,y,z) return {x=x,y=y,z=z} end
local function add(a,b) return v3(a.x+b.x,a.y+b.y,a.z+b.z) end
local function sub(a,b) return v3(a.x-b.x,a.y-b.y,a.z-b.z) end
local function mul(a,s) return v3(a.x*s,a.y*s,a.z*s) end
local function len(a) return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z) end
local function point(v) return type(v)=='table' and num(v.x)~=nil and num(v.y)~=nil and num(v.z)~=nil end
local function copy(v) return v3(num(v.x,0),num(v.y,0),num(v.z,0)) end
local function yaw_of(d) return math.deg(math.atan2(d.y,d.x)) end
local function pitch_of(d) return -math.deg(math.atan2(d.z,math.sqrt(d.x*d.x+d.y*d.y))) end

function Splines.new(app) return setmetatable({app=app,preview_objects={}},Splines) end

function Splines:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

function Splines:get(id) return self.app.model:get_spline(id) end

-- Curve evaluation -------------------------------------------------------------

-- Effective handles for every point (auto/linear resolved).
function Splines:handles(spline)
    local pts=spline.points;local n=#pts;local out={}
    for i,p in ipairs(pts) do
        local hin,hout
        if p.mode=='linear' then hin,hout=v3(0,0,0),v3(0,0,0)
        elseif p.mode=='auto' then
            local prev=pts[i-1] or (spline.closed and pts[n]) or p
            local nxt=pts[i+1] or (spline.closed and pts[1]) or p
            local d=mul(sub(nxt.position,prev.position),spline.tension/3)
            if (prev==p or nxt==p) and n>1 then d=mul(d,2) end
            hin,hout=mul(d,-1),d
        else hin,hout=copy(p.handle_in),copy(p.handle_out) end
        out[i]={hin=hin,hout=hout}
    end
    return out
end

function Splines:_segments(spline)
    local pts=spline.points;local n=#pts;local h=self:handles(spline);local segs={}
    local last=spline.closed and n or n-1
    for i=1,last do
        local j=i%n+1
        local p0,p3=pts[i].position,pts[j].position
        segs[#segs+1]={p0=p0,p1=add(p0,h[i].hout),p2=add(p3,h[j].hin),p3=p3,from=i,to=j}
    end
    return segs
end

local function bezier(s,t)
    local u=1-t
    local a,b,c,d=u*u*u,3*u*u*t,3*u*t*t,t*t*t
    return v3(s.p0.x*a+s.p1.x*b+s.p2.x*c+s.p3.x*d,s.p0.y*a+s.p1.y*b+s.p2.y*c+s.p3.y*d,s.p0.z*a+s.p1.z*b+s.p2.z*c+s.p3.z*d)
end
local function derivative(s,t)
    local u=1-t
    local a,b,c=3*u*u,6*u*t,3*t*t
    return v3((s.p1.x-s.p0.x)*a+(s.p2.x-s.p1.x)*b+(s.p3.x-s.p2.x)*c,(s.p1.y-s.p0.y)*a+(s.p2.y-s.p1.y)*b+(s.p3.y-s.p2.y)*c,(s.p1.z-s.p0.z)*a+(s.p2.z-s.p1.z)*b+(s.p3.z-s.p2.z)*c)
end

-- Arc-length table: list of {distance, segment, t}.
function Splines:_table(spline)
    local segs=self:_segments(spline);local rows={};local total=0
    for si,s in ipairs(segs) do
        local prev=bezier(s,0)
        if si==1 then rows[#rows+1]={d=0,s=si,t=0} end
        for k=1,LENGTH_STEPS do
            local t=k/LENGTH_STEPS;local p=bezier(s,t);total=total+len(sub(p,prev));prev=p
            rows[#rows+1]={d=total,s=si,t=t}
        end
    end
    return rows,segs,total
end

function Splines:length(spline) local _,_,total=self:_table(spline);return total end

local function at_distance(rows,segs,d)
    if #rows==0 then return nil end
    if d<=0 then return segs[1],0 end
    for i=2,#rows do
        local a,b=rows[i-1],rows[i]
        if d<=b.d then
            local f=(b.d>a.d) and (d-a.d)/(b.d-a.d) or 0
            if a.s==b.s then return segs[b.s],a.t+(b.t-a.t)*f end
            return segs[b.s],b.t*f
        end
    end
    local last=rows[#rows];return segs[last.s],last.t
end

-- Evenly spaced samples by arc length (or `count` samples).
function Splines:sample(id,args)
    args=args or {}
    local spline=type(id)=='table' and id or self:get(id);if not spline then return nil,'spline not found' end
    if #spline.points<2 then return nil,'a spline needs at least two control points' end
    local rows,segs,total=self:_table(spline)
    if total<=0.0001 then return nil,'spline has zero length' end
    local start=math.max(0,num(args.start_offset,0));local stop=total-math.max(0,num(args.end_offset,0))
    if stop<=start then return nil,'offsets leave no length to sample' end
    local spacing=num(args.spacing,nil);local count=num(args.count,nil)
    if count then count=math.floor(count);if count<2 or count>2000 then return nil,'count must be between 2 and 2000' end;spacing=(stop-start)/(count-1)
    else spacing=spacing or 1;if spacing<0.05 or spacing>500 then return nil,'spacing must be between 0.05 and 500 m' end end
    local out={};local d=start
    -- A full closed loop ends where it starts; never emit that point twice.
    local full_loop=spline.closed and num(args.end_offset,0)==0
    local include_end=args.include_end~=false and not full_loop
    while (full_loop and d<stop-1e-6 or not full_loop and d<=stop+1e-6) and #out<2000 do
        local s,t=at_distance(rows,segs,d);local p=bezier(s,t);local tangent=derivative(s,t)
        if len(tangent)<1e-6 then tangent=sub(s.p3,s.p0) end
        out[#out+1]={position=p,tangent=tangent,yaw=yaw_of(tangent),pitch=pitch_of(tangent),distance=d,segment=s.from}
        d=d+spacing
    end
    if include_end and out[#out] and stop-out[#out].distance>spacing*0.25 then
        local s,t=at_distance(rows,segs,stop);local p=bezier(s,t);local tangent=derivative(s,t)
        out[#out+1]={position=p,tangent=tangent,yaw=yaw_of(tangent),pitch=pitch_of(tangent),distance=stop,segment=s.from}
    end
    for _,o in ipairs(out) do o.tangent=nil end
    return {spline_id=spline.id,length=total,spacing=spacing,closed=spline.closed,points=out,count=#out}
end

-- CRUD / editing -------------------------------------------------------------

function Splines:_position(args)
    if point(args.position) then return copy(args.position) end
    if args.source=='player' then local t,err=self.app.game:capture_transform();if not t then return nil,err end;return copy(t.position) end
    if args.source=='aim' then local hit,err=self.app.game:aim_point(args.distance or 20);if not hit then return nil,err end;return copy(hit.position) end
    return nil,'give a position or source aim/player'
end

function Splines:list(args)
    args=args or {};local out={}
    for _,s in ipairs(self.app.model.data.splines or {}) do
        if not args.premise_id or args.premise_id=='' or s.premise_id==args.premise_id then
            local uses={};for _,u in ipairs(s.uses or {}) do uses[#uses+1]={id=u.id,kind=u.kind} end
            out[#out+1]={id=s.id,name=s.name,premise_id=s.premise_id,closed=s.closed,points=#s.points,length=#s.points>=2 and self:length(s) or 0,uses=uses,color=s.color}
        end
    end
    return {items=out,count=#out}
end

function Splines:create(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local points={}
    for i,p in ipairs(type(args.points)=='table' and args.points or {}) do
        local pos=point(p) and p or (type(p)=='table' and p.position)
        if not point(pos) then return nil,'invalid point at index '..i end
        points[#points+1]={position=copy(pos),mode=type(p)=='table' and p.mode or args.mode or 'auto',handle_in=p.handle_in,handle_out=p.handle_out}
    end
    if #points==0 and args.source then local pos,err=self:_position(args);if not pos then return nil,err end;points[1]={position=pos,mode=args.mode or 'auto'} end
    if #points>MAX_POINTS then return nil,'a spline can have at most '..MAX_POINTS..' control points' end
    local spline=self.app.model:add_spline({name=args.name,premise_id=args.premise_id or self.app.selected_premise_id,closed=args.closed==true,tension=args.tension,color=args.color,points=points})
    self.app:mark_dirty()
    return spline
end

function Splines:update(id,patch)
    patch=patch or {}
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    if patch.closed==true and #spline.points<3 then return nil,'a closed spline needs at least three control points' end
    self.app.model:snapshot('Update spline')
    if patch.name and Util.trim(patch.name)~='' then spline.name=Util.trim(patch.name) end
    if patch.closed~=nil then spline.closed=patch.closed==true end
    if patch.tension~=nil then spline.tension=math.max(0,math.min(1,num(patch.tension,0.5))) end
    if patch.color and tostring(patch.color):match('^#%x%x%x%x%x%x$') then spline.color=patch.color end
    spline.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return spline
end

function Splines:add_point(id,args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    if #spline.points>=MAX_POINTS then return nil,'a spline can have at most '..MAX_POINTS..' control points' end
    local pos,err=self:_position(args);if not pos then return nil,err end
    local index=math.floor(num(args.index,#spline.points+1));index=math.max(1,math.min(#spline.points+1,index))
    self.app.model:snapshot('Add spline point')
    table.insert(spline.points,index,{id=Util.make_id('spt'),position=pos,handle_in=v3(0,0,0),handle_out=v3(0,0,0),mode=args.mode or 'auto'})
    spline.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return {spline=spline,index=index,point=spline.points[index]}
end

-- Insert a point on the curve at `distance` (arc length) without changing its shape much.
function Splines:insert_at_distance(id,distance)
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    local rows,segs=self:_table(spline);local s,t=at_distance(rows,segs,num(distance,0));if not s then return nil,'spline has no segments' end
    return self:add_point(id,{position=bezier(s,t),index=s.from+1,mode='auto'})
end

function Splines:update_point(id,index,patch)
    patch=patch or {}
    local busy=self:_busy();if busy then return nil,busy end
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    local p=spline.points[math.floor(num(index,0))];if not p then return nil,'control point not found' end
    local pos
    if patch.position~=nil or patch.source then local err;pos,err=self:_position(patch);if not pos then return nil,err end end
    if patch.mode~=nil and not ({auto=true,aligned=true,free=true,linear=true})[patch.mode] then return nil,'mode must be auto, aligned, free or linear' end
    if patch.handle_in~=nil and not point(patch.handle_in) then return nil,'handle_in must be {x,y,z}' end
    if patch.handle_out~=nil and not point(patch.handle_out) then return nil,'handle_out must be {x,y,z}' end
    self.app.model:snapshot('Edit spline point')
    if pos then p.position=pos end
    if patch.mode then
        -- Switching from auto keeps the current effective handles as a starting point.
        if p.mode=='auto' and patch.mode~='auto' and patch.mode~='linear' then local h=self:handles(spline)[math.floor(index)];p.handle_in,p.handle_out=h.hin,h.hout end
        p.mode=patch.mode
    end
    if patch.handle_out or patch.handle_in then
        if p.mode=='auto' or p.mode=='linear' then p.mode='free' end
        if patch.handle_out then p.handle_out=copy(patch.handle_out) end
        if patch.handle_in then p.handle_in=copy(patch.handle_in) end
        if p.mode=='aligned' then
            -- Keep the handles collinear: mirror the edited handle's direction, keep the other's length.
            if patch.handle_out and not patch.handle_in then local l=len(p.handle_in);local d=len(p.handle_out);if d>1e-9 then p.handle_in=mul(p.handle_out,-l/d) end
            elseif patch.handle_in and not patch.handle_out then local l=len(p.handle_out);local d=len(p.handle_in);if d>1e-9 then p.handle_out=mul(p.handle_in,-l/d) end end
        end
    end
    spline.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return {spline=spline,index=math.floor(index),point=p}
end

function Splines:delete_point(id,index)
    local busy=self:_busy();if busy then return nil,busy end
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    index=math.floor(num(index,0));if not spline.points[index] then return nil,'control point not found' end
    self.app.model:snapshot('Delete spline point')
    table.remove(spline.points,index)
    if spline.closed and #spline.points<3 then spline.closed=false end
    spline.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return {spline=spline,deleted=index}
end

-- Uses -----------------------------------------------------------------------

function Splines:_asset_object(asset,premise_id,sample,name,args,index)
    local metadata=Util.deepcopy(asset.metadata or {});metadata.locationstudio_asset_id=asset.id
    metadata.spline_use={spline_id=args._spline_id,use_id=args._use_id,index=index}
    local lateral=num(args.lateral_offset,0)
    local p=sample.position
    if lateral~=0 then local r=math.rad(sample.yaw+90);p=v3(p.x+math.cos(r)*lateral,p.y+math.sin(r)*lateral,p.z) end
    local yaw=args.align~=false and sample.yaw or 0
    yaw=yaw+num(args.yaw_offset,0)
    if args.random_yaw==true then yaw=yaw+((index*7919+num(args.seed,2077))%360) end
    local pitch=args.follow_pitch==true and sample.pitch or 0
    return {premise_id=premise_id,room_id=args.room_id,name=string.format('%s %03d',name,index),kind=asset.kind,template=asset.template,appearance=asset.appearance,
        layer=args.layer or asset.layer or 'decoration',size=Util.deepcopy(asset.size),
        transform={position={x=p.x,y=p.y,z=p.z+num(args.height_offset,0),w=1},rotation={roll=0,pitch=pitch,yaw=yaw}},metadata=metadata}
end

-- Remove what a use generated. Returns false when a live object cannot be removed.
function Splines:_clear_outputs(use)
    local out=use.outputs or {}
    for _,oid in ipairs(out.object_ids or {}) do
        local o=self.app.model:get_object(oid)
        if o and self.app.placement:is_tracked(o) then local ok,err=self.app.placement:despawn(o);if not ok then return false,'could not remove generated object '..tostring(o.name)..': '..tostring(err) end end
    end
    if out.object_ids and #out.object_ids>0 then
        local drop={};for _,oid in ipairs(out.object_ids) do drop[oid]=true end
        local kept={};for _,o in ipairs(self.app.model.data.objects) do if not drop[o.id] then kept[#kept+1]=o end end
        self.app.model.data.objects=kept
        for _,group in ipairs(self.app.model.data.object_groups or {}) do local ids={};for _,oid in ipairs(group.object_ids or {}) do if not drop[oid] then ids[#ids+1]=oid end end;group.object_ids=ids end
        for _,scene in ipairs(self.app.model.data.scenes or {}) do local ids={};for _,oid in ipairs(scene.object_ids or {}) do if not drop[oid] then ids[#ids+1]=oid end end;scene.object_ids=ids end
    end
    if out.camera_ids and #out.camera_ids>0 then
        local drop={};for _,cid in ipairs(out.camera_ids) do drop[cid]=true end
        local kept={};for _,c in ipairs(self.app.model.data.cameras) do if not drop[c.id] then kept[#kept+1]=c end end
        self.app.model.data.cameras=kept
        for _,scene in ipairs(self.app.model.data.scenes or {}) do local ids={};for _,cid in ipairs(scene.camera_ids or {}) do if not drop[cid] then ids[#ids+1]=cid end end;scene.camera_ids=ids end
    end
    use.outputs={}
    return true
end

-- Build a use's outputs. The caller has already taken one snapshot.
function Splines:_build(spline,use)
    local args=Util.deepcopy(use.params or {});args._spline_id=spline.id;args._use_id=use.id
    local premise_id=args.premise_id or spline.premise_id or self.app.selected_premise_id
    local kind=use.kind
    if kind=='cable' or kind=='fence' or kind=='road' then
        if not self.app.world_builder_generators then return nil,'path generators are unavailable' end
        local spacing=num(args.sample_spacing,nil) or math.max(0.5,self:length(spline)/127)
        local sampled,err=self:sample(spline,{spacing=spacing});if not sampled then return nil,err end
        if #sampled.points>128 then local sp;sp,err=self:sample(spline,{count=128});if not sp then return nil,err end;sampled=sp end
        local pts={};for _,s in ipairs(sampled.points) do pts[#pts+1]={x=s.position.x,y=s.position.y,z=s.position.z} end
        if spline.closed then pts[#pts+1]=Util.deepcopy(pts[1]) end
        local gen_args=Util.deepcopy(args);gen_args.points=pts;gen_args.premise_id=premise_id;gen_args.name=args.name or (spline.name..' '..kind)
        gen_args._spline_id=nil;gen_args._use_id=nil;gen_args.sample_spacing=nil
        -- Generators snapshot/add on their own; keep everything inside this spline operation.
        local model=self.app.model;local saved_snapshot=model.snapshot;model.snapshot=function() end
        local ok,result,gen_err=pcall(function() return self.app.world_builder_generators[kind](self.app.world_builder_generators,gen_args) end)
        model.snapshot=saved_snapshot
        if not ok then return nil,tostring(result) end
        if not result then return nil,gen_err end
        for _,oid in ipairs(result.object_ids or {}) do local o=model:get_object(oid);if o then o.metadata.spline_use={spline_id=spline.id,use_id=use.id} end end
        use.outputs={object_ids=result.object_ids,path_length=result.path_length,spawned=#(result.spawned_ids or {}),failed=result.failed}
        return use
    elseif kind=='distribute' then
        local asset=self.app.model:get_asset(args.asset_id);if not asset then return nil,'asset_id must reference a project asset' end
        local sampled,err=self:sample(spline,{spacing=args.spacing or 2,count=args.count,start_offset=args.start_offset,end_offset=args.end_offset})
        if not sampled then return nil,err end
        if #sampled.points>512 then return nil,'distribution is limited to 512 objects; increase spacing' end
        local values={}
        for i,s in ipairs(sampled.points) do values[#values+1]=self:_asset_object(asset,premise_id,s,args.name or asset.name,args,i) end
        local objects=self.app.model:add_objects(values,true)
        local ids,spawned,failed={},0,{}
        for _,o in ipairs(objects) do
            ids[#ids+1]=o.id
            if args.spawn~=false then local sid,serr=self.app.placement:spawn(o);if sid then spawned=spawned+1 else failed[#failed+1]={object_id=o.id,error=tostring(serr)} end end
        end
        use.outputs={object_ids=ids,spawned=spawned,failed=failed}
        return use
    elseif kind=='npc_path' then
        local route=args.route_id and self.app.model:get_npc_route(args.route_id)
        local sampled,err=self:sample(spline,{spacing=args.spacing or 3});if not sampled then return nil,err end
        if #sampled.points>64 then local sp;sp,err=self:sample(spline,{count=64});if not sp then return nil,err end;sampled=sp end
        if not route then
            local npc=self.app.model:get_object(args.npc_id)
            if not npc or not (npc.metadata and npc.metadata.npc_population) then return nil,'npc_id must reference a saved NPC population point' end
            route={id=Util.make_id('npcroute'),name=args.name or (spline.name..' route'),npc_id=npc.id,premise_id=npc.premise_id,loop=spline.closed,kind=args.route_kind or 'patrol',
                waypoints={},alert_waypoints={},combat_waypoints={},notes='Generated from spline '..spline.name}
            table.insert(self.app.model.data.npc_routes,route)
            npc.metadata.npc_route_ids=npc.metadata.npc_route_ids or {};table.insert(npc.metadata.npc_route_ids,route.id)
            use.params.route_id=route.id
        end
        local field=({patrol='waypoints',alert='alert_waypoints',combat='combat_waypoints'})[args.variant or 'patrol'] or 'waypoints'
        local wps={}
        for i,s in ipairs(sampled.points) do
            wps[#wps+1]={id=Util.make_id('wp'),name=string.format('Spline %02d',i),transform={position={x=s.position.x,y=s.position.y,z=s.position.z,w=1},rotation={roll=0,pitch=0,yaw=s.yaw}},
                wait_seconds=num(args.wait_seconds,0),facing_yaw=s.yaw,speed=num(args.speed,1),transition='walk',workspot_location_id='',branch_fact='',branch_value=1,branch_target_id='',variant=args.variant or 'patrol'}
        end
        route[field]=wps;route.loop=spline.closed;route.updated_at=Util.now_iso()
        use.outputs={route_id=route.id,waypoints=#wps}
        return use
    elseif kind=='camera_path' then
        local sampled,err=self:sample(spline,{spacing=args.spacing,count=args.count or 8});if not sampled then return nil,err end
        if #sampled.points>64 then return nil,'camera paths are limited to 64 cameras' end
        local speed=math.max(0.1,num(args.speed,2));local lookahead=math.max(0.5,num(args.look_ahead,4))
        local rows,segs,total=self:_table(spline)
        local ids={}
        for i,s in ipairs(sampled.points) do
            local look
            if point(args.look_at) then look=copy(args.look_at)
            else local d=s.distance+lookahead;if spline.closed then d=d%total else d=math.min(d,total) end;local seg,t=at_distance(rows,segs,d);look=bezier(seg,t)
                if len(sub(look,s.position))<0.1 then look=add(s.position,v3(math.cos(math.rad(s.yaw)),math.sin(math.rad(s.yaw)),0)) end end
            local nxt=sampled.points[i+1];local duration=nxt and math.max(0.1,(nxt.distance-s.distance)/speed) or num(args.hold,2)
            local pos=v3(s.position.x,s.position.y,s.position.z+num(args.height_offset,0))
            local camera=self.app.model.normalize_camera({premise_id=premise_id,name=string.format('%s %02d',args.name or (spline.name..' cam'),i),kind='path',
                transform={position={x=pos.x,y=pos.y,z=pos.z,w=1},rotation=Util.look_at_rotation(pos,look)},look_at={x=look.x,y=look.y,z=look.z},
                fov=num(args.fov,50),duration=duration,tags={'spline_path:'..spline.id,'spline_use:'..use.id,string.format('order:%03d',i)}})
            table.insert(self.app.model.data.cameras,camera);ids[#ids+1]=camera.id
        end
        use.outputs={camera_ids=ids,total_duration=(function() local t=0;for _,cid in ipairs(ids) do t=t+self.app.model:get_camera(cid).duration end;return t end)()}
        return use
    elseif kind=='native_spline' then
        local h=self:handles(spline);local defs={}
        -- Hermite tangents for REDengine: 3x the Bezier handles, both pointing along the curve.
        for i,p in ipairs(spline.points) do
            defs[#defs+1]={position={x=p.position.x,y=p.position.y,z=p.position.z},tangentIn=mul(h[i].hin,-3),tangentOut=mul(h[i].hout,3),automaticTangents=p.mode=='auto'}
        end
        local first=spline.points[1].position;local name=args.name or spline.name
        local object=self.app.model:add_objects({{premise_id=premise_id,name=name,kind='spline',template='',layer=args.layer or 'gameplay',
            transform={position={x=first.x,y=first.y,z=first.z,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},
            metadata={source='LocationStudio spline',spline_use={spline_id=spline.id,use_id=use.id},world_builder={definition_key='spline',category='Meta',variant='Spline',
                class_module='modules/classes/spawn/meta/spline',module_path='meta/spline',resource_name='Spline',resource_path='',apply_scale=false,
                entry={name=name,fileName=name,data={pointDefs=defs,looped=spline.closed,modulePath='meta/spline',dataType='Spline'}}}}}},true)[1]
        local spawned=false
        if args.spawn~=false then spawned=self.app.placement:spawn(object)~=nil end
        use.outputs={object_ids={object.id},spawned=spawned and 1 or 0}
        return use
    end
    return nil,'unknown spline use kind: '..tostring(kind)
end

function Splines:apply_use(id,kind,params)
    local busy=self:_busy();if busy then return nil,busy end
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    if not USE_KINDS[kind] then return nil,'kind must be cable, fence, road, distribute, npc_path, camera_path or native_spline' end
    if #spline.points<2 then return nil,'a spline needs at least two control points' end
    self.app.model:snapshot('Spline '..kind)
    local use={id=Util.make_id('suse'),kind=kind,params=Util.deepcopy(params or {}),outputs={}}
    local built,err=self:_build(spline,use)
    if not built then self.app.model:undo();self.app.model.redo_stack={};return nil,err end
    use.updated_at=Util.now_iso();table.insert(spline.uses,use)
    self.app.model:touch();self.app:mark_dirty()
    return {spline_id=spline.id,use=use}
end

-- Rebuild every use (or one) from the current curve as one undo step.
function Splines:regenerate(id,use_id)
    local busy=self:_busy();if busy then return nil,busy end
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    if #spline.points<2 then return nil,'a spline needs at least two control points' end
    self.app.model:snapshot('Regenerate spline uses')
    local rebuilt={}
    for _,use in ipairs(spline.uses) do
        if not use_id or use.id==use_id then
            local ok,err=self:_clear_outputs(use)
            if ok then ok,err=self:_build(spline,use) end
            if not ok then self.app.model:undo();self.app.model.redo_stack={};return nil,'regenerating '..use.kind..' failed: '..tostring(err) end
            use.updated_at=Util.now_iso();rebuilt[#rebuilt+1]={id=use.id,kind=use.kind,outputs=use.outputs}
        end
    end
    self.app.model:touch();self.app:mark_dirty()
    return {spline_id=spline.id,rebuilt=rebuilt,count=#rebuilt}
end

function Splines:remove_use(id,use_id,keep_outputs)
    local busy=self:_busy();if busy then return nil,busy end
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    for i,use in ipairs(spline.uses) do if use.id==use_id then
        self.app.model:snapshot('Remove spline use')
        if not keep_outputs then local ok,err=self:_clear_outputs(use);if not ok then self.app.model:undo();self.app.model.redo_stack={};return nil,err end end
        table.remove(spline.uses,i);self.app.model:touch();self.app:mark_dirty()
        return {removed=use_id,kept_outputs=keep_outputs==true}
    end end
    return nil,'use not found'
end

function Splines:delete(id,keep_outputs)
    local busy=self:_busy();if busy then return nil,busy end
    local spline,index=self:get(id);if not spline then return nil,'spline not found' end
    local cleared=self:preview_clear();if not cleared then return nil,'clear the spline preview first' end
    self.app.model:snapshot('Delete spline')
    if not keep_outputs then for _,use in ipairs(spline.uses) do local ok,err=self:_clear_outputs(use);if not ok then self.app.model:undo();self.app.model.redo_stack={};return nil,err end end end
    table.remove(self.app.model.data.splines,index);self.app.model:touch();self.app:mark_dirty()
    return {deleted=id,kept_outputs=keep_outputs==true}
end

-- Live preview: transient World Builder static markers on the control points
-- and along the curve. Never saved.
function Splines:preview(id,args)
    args=args or {}
    local spline=self:get(id);if not spline then return nil,'spline not found' end
    local wb=self.app.world_builder;if not wb or not self.app.runtime_shell then return nil,'World Builder is unavailable for the preview' end
    local cleared,err=self:preview_clear();if not cleared then return nil,err end
    local found;found,err=wb:search('static_marker','',5,false);if not found then return nil,err end
    local resource=found.items and found.items[1];if not resource then return nil,'World Builder Static Marker catalog is empty' end
    local payload;payload,err=wb:prepare_favorite_record({category='Meta',variant='Static Marker',spawn_data=resource.path,name=resource.name},'Spline preview')
    if not payload then return nil,err end
    local positions={}
    for i,p in ipairs(spline.points) do positions[#positions+1]={p=p.position,label='point '..i} end
    if #spline.points>=2 and args.curve~=false then
        local sampled=self:sample(spline,{spacing=args.spacing or 1})
        if sampled then for _,s in ipairs(sampled.points) do if #positions<400 then positions[#positions+1]={p=s.position,label='curve'} end end end
    end
    local spawned=0
    for i,item in ipairs(positions) do
        local object={id=PREVIEW_PREFIX..i,name='Spline preview '..item.label,kind='marker',template='',size={x=1,y=1,z=1},enabled=true,
            transform={position={x=item.p.x,y=item.p.y,z=item.p.z,w=1},rotation={roll=0,pitch=0,yaw=0}},
            metadata={world_builder={definition_key='static_marker',category='Meta',variant='Static Marker',class_module='modules/classes/spawn/meta/staticMarker',module_path='meta/staticMarker',
                resource_name=resource.name,resource_path=resource.path,entry={name=payload.name,fileName=payload.name,data=Util.deepcopy(payload.data.spawnable)},apply_scale=false}},runtime={}}
        local sid=self.app.runtime_shell:spawn(object)
        if sid then spawned=spawned+1;self.preview_objects[#self.preview_objects+1]=object end
    end
    return {spline_id=id,markers=spawned,control_points=#spline.points}
end

function Splines:preview_clear()
    local remaining={}
    for _,object in ipairs(self.preview_objects) do
        local ok=self.app.runtime_shell:despawn(object);if not ok then remaining[#remaining+1]=object end
    end
    self.preview_objects=remaining
    if #remaining>0 then return nil,#remaining..' preview marker(s) could not be removed' end
    return true
end

Splines.PREVIEW_PREFIX=PREVIEW_PREFIX
return Splines
