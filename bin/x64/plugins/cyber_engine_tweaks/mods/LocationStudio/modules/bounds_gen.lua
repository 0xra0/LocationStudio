local Util=require('modules/util')

-- Automatic bounds for generated resources: procedural objects (generators,
-- CSG, parametric-room pieces), their generated colliders, and generated rooms.
--
-- Every record is derived from the geometry, never typed in:
--   local       object-frame AABB. Exact per-shape extents (rotated boxes,
--               wedges, cylinders and spheres). CSG uses the tree bounds
--               clipped to the preview grid, flagged `exact=false` when the
--               tree is approximated.
--   world       world AABB of the oriented local box (procedural rotation
--               convention R = Rz(yaw) Rx(pitch) Ry(roll)), the oriented box
--               itself and a bounding sphere.
--   collision   union of the object's generated colliders (world AABB).
--   visibility  render bounds (world AABB) and the distance at which the
--               bounding sphere subtends `min_screen_angle` degrees.
--   streaming   primary range (visibility distance + margin, clamped),
--               secondary range, the world AABB grown by the range, and the
--               streaming cells the object overlaps.
-- A manual `stream_range` on the object still wins (source 'manual').
-- Records are stored in metadata.generated_bounds with the transform they were
-- computed for; `get` recomputes a stale one.
local Bounds={};Bounds.__index=Bounds

local DEFAULTS={min_screen_angle=1.0,stream_margin=10,min_range=30,max_range=800,secondary_factor=1.2,cell_size=128,padding=0}

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function rotate(v,r)
    local cy,sy=math.cos(math.rad(r.yaw or 0)),math.sin(math.rad(r.yaw or 0))
    local cp,sp=math.cos(math.rad(r.pitch or 0)),math.sin(math.rad(r.pitch or 0))
    local cr,sr=math.cos(math.rad(r.roll or 0)),math.sin(math.rad(r.roll or 0))
    local x,y,z=v.x*cr+v.z*sr,v.y,-v.x*sr+v.z*cr
    y,z=y*cp-z*sp,y*sp+z*cp
    return {x=x*cy-y*sy,y=x*sy+y*cy,z=z}
end
local AXES={'x','y','z'}
local function empty() return {min={x=math.huge,y=math.huge,z=math.huge},max={x=-math.huge,y=-math.huge,z=-math.huge}} end
local function grow(b,p) for _,k in ipairs(AXES) do b.min[k]=math.min(b.min[k],p[k]);b.max[k]=math.max(b.max[k],p[k]) end end
local function merge(a,b) for _,k in ipairs(AXES) do a.min[k]=math.min(a.min[k],b.min[k]);a.max[k]=math.max(a.max[k],b.max[k]) end;return a end
local function valid(b) return b and b.min.x<=b.max.x and b.min.y<=b.max.y and b.min.z<=b.max.z end
local function finish(b)
    b.center={x=(b.min.x+b.max.x)/2,y=(b.min.y+b.max.y)/2,z=(b.min.z+b.max.z)/2}
    b.extents={x=(b.max.x-b.min.x)/2,y=(b.max.y-b.min.y)/2,z=(b.max.z-b.min.z)/2}
    return b
end
local function round(b) for _,part in ipairs({'min','max','center','extents'}) do if b[part] then for _,k in ipairs(AXES) do b[part][k]=math.floor(b[part][k]*1e6+0.5)/1e6 end end end;return b end

function Bounds.new(app) return setmetatable({app=app},Bounds) end

function Bounds:settings()
    local s=self.app.model.data.settings;s.bounds=type(s.bounds)=='table' and s.bounds or {}
    local out={};for k,v in pairs(DEFAULTS) do out[k]=num(s.bounds[k],v) end
    return out
end

function Bounds:set_settings(patch)
    patch=type(patch)=='table' and patch or {}
    local ranges={min_screen_angle={0.05,45},stream_margin={0,500},min_range={1,5000},max_range={1,20000},secondary_factor={1,5},cell_size={4,4096},padding={0,1}}
    local s=self.app.model.data.settings;s.bounds=type(s.bounds)=='table' and s.bounds or {}
    local next_s=Util.deepcopy(s.bounds)
    for k,v in pairs(patch) do
        local r=ranges[k];if not r then return nil,'unknown bounds setting: '..tostring(k) end
        v=num(v);if not v or v<r[1] or v>r[2] then return nil,k..' must be between '..r[1]..' and '..r[2] end
        next_s[k]=v
    end
    local merged={};for k,v in pairs(DEFAULTS) do merged[k]=num(next_s[k],v) end
    if merged.min_range>merged.max_range then return nil,'min_range must not exceed max_range' end
    self.app.model:snapshot('Bounds settings');s.bounds=next_s;self.app:mark_dirty()
    return merged
end

-- ------------------------------------------------------------------ local bounds

-- Exact object-frame AABB of one part.
function Bounds.part_bounds(p)
    local b=empty()
    if p.shape=='prism' then
        for _,q in ipairs(p.points or {}) do grow(b,{x=q.x,y=q.y,z=p.z0});grow(b,{x=q.x,y=q.y,z=p.z1}) end
        return b
    end
    local c=p.center;local r=p.rotation or {}
    if p.shape=='sphere' then grow(b,{x=c.x-p.radius,y=c.y-p.radius,z=c.z-p.radius});grow(b,{x=c.x+p.radius,y=c.y+p.radius,z=c.z+p.radius});return b end
    if p.shape=='cylinder' then
        -- Axis along local +Y: extent per world axis = h|a_k| + r*sqrt(1 - a_k^2).
        local a=rotate({x=0,y=1,z=0},r);local h=p.length/2
        for _,k in ipairs(AXES) do
            local e=h*math.abs(a[k])+p.radius*math.sqrt(math.max(0,1-a[k]*a[k]))
            b.min[k]=c[k]-e;b.max[k]=c[k]+e
        end
        return b
    end
    local hx,hy,hz=p.size.x/2,p.size.y/2,p.size.z/2
    local corners
    if p.shape=='wedge' then corners={{-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{-1,1,1},{1,1,1}}
    else corners={} for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do corners[#corners+1]={sx,sy,sz} end end end end
    for _,s in ipairs(corners) do
        local w=rotate({x=s[1]*hx,y=s[2]*hy,z=s[3]*hz},r)
        grow(b,{x=c.x+w.x,y=c.y+w.y,z=c.z+w.z})
    end
    return b
end

-- Local bounds of a procedural object; exact=false when only approximate.
function Bounds.local_bounds(cfg)
    local b=empty()
    for _,p in ipairs(cfg.parts or {}) do merge(b,Bounds.part_bounds(p)) end
    local exact=true
    local csg=cfg.csg
    if csg and csg.tree then
        local ok,Csg=pcall(require,'modules/csg')
        if ok and Csg then
            local lo,hi=Csg.bounds(csg.tree)
            if lo and csg.approximate then
                -- The grid preview may miss up to one cell at curved surfaces; the tree bounds contain the solid.
                local res=num(csg.resolution,0.25)
                for _,k in ipairs(AXES) do b.min[k]=math.max(lo[k],b.min[k]-res);b.max[k]=math.min(hi[k],b.max[k]+res) end
                exact=false
            end
        end
    end
    if not valid(b) then return nil end
    return finish(b),exact
end

-- ------------------------------------------------------------------ world and derived bounds

local function transform_key(t)
    local p,r=t.position or {},t.rotation or {}
    return string.format('%.4f,%.4f,%.4f|%.3f,%.3f,%.3f',num(p.x,0),num(p.y,0),num(p.z,0),num(r.roll,0),num(r.pitch,0),num(r.yaw,0))
end

local function world_of(local_b,t)
    local p,r=t.position or {x=0,y=0,z=0},t.rotation or {}
    local w=empty()
    for _,x in ipairs({local_b.min.x,local_b.max.x}) do for _,y in ipairs({local_b.min.y,local_b.max.y}) do for _,z in ipairs({local_b.min.z,local_b.max.z}) do
        local q=rotate({x=x,y=y,z=z},r);grow(w,{x=q.x+p.x,y=q.y+p.y,z=q.z+p.z})
    end end end
    local c=rotate(local_b.center,r)
    return finish(w),{center={x=c.x+p.x,y=c.y+p.y,z=c.z+p.z},extents=Util.deepcopy(local_b.extents),rotation={roll=num(r.roll,0),pitch=num(r.pitch,0),yaw=num(r.yaw,0)}}
end

local function cells(b,size)
    local out={}
    local lo={};local hi={}
    for _,k in ipairs(AXES) do lo[k]=math.floor(b.min[k]/size);hi[k]=math.floor(b.max[k]/size) end
    local n=(hi.x-lo.x+1)*(hi.y-lo.y+1)*(hi.z-lo.z+1)
    if n>512 then return nil,n end
    for x=lo.x,hi.x do for y=lo.y,hi.y do for z=lo.z,hi.z do out[#out+1]=x..','..y..','..z end end end
    return out,n
end

-- Visibility/streaming distances for a bounding-sphere radius.
function Bounds.distances(radius,settings,manual)
    local vis=radius/math.tan(math.rad(settings.min_screen_angle)/2)
    vis=math.max(settings.min_range,math.min(settings.max_range,vis))
    local range=manual or math.max(settings.min_range,math.min(settings.max_range,vis+settings.stream_margin))
    return vis,range,range*settings.secondary_factor
end

-- Collider local bounds: box half extents (World Builder scale) or sphere radius.
local function collider_local(o)
    local data=o.metadata and o.metadata.world_builder and o.metadata.world_builder.entry and o.metadata.world_builder.entry.data or {}
    local s=o.size or data.scale or {x=0.5,y=0.5,z=0.5}
    local shape=tonumber(data.shape) or 0
    local hx,hy,hz=num(s.x,0.5),num(s.y,0.5),num(s.z,0.5)
    if shape==2 then hy,hz=hx,hx elseif shape==1 then hy=hx;hz=hz/2+hx end
    return finish({min={x=-hx,y=-hy,z=-hz},max={x=hx,y=hy,z=hz}})
end

function Bounds:kind_of(o)
    local md=o and o.metadata or {}
    if md.procedural then return 'procedural' end
    if md.collision_gen then return 'collider' end
    return nil
end

-- Full record for a generated resource (or nil, reason).
function Bounds:compute(o)
    local kind=self:kind_of(o);if not kind then return nil,'not a generated resource' end
    local settings=self:settings()
    local local_b,exact
    if kind=='procedural' then local_b,exact=Bounds.local_bounds(o.metadata.procedural);if not local_b then return nil,'the object has no geometry' end
    else local_b,exact=collider_local(o),true end
    local pad=settings.padding
    if pad>0 then for _,k in ipairs(AXES) do local_b.min[k]=local_b.min[k]-pad;local_b.max[k]=local_b.max[k]+pad end;finish(local_b) end
    local world,obb=world_of(local_b,o.transform)
    local e=local_b.extents
    local radius=math.sqrt(e.x*e.x+e.y*e.y+e.z*e.z)
    local manual=kind=='procedural' and num(o.metadata.procedural.stream_range,nil) or nil
    local vis,range,secondary=Bounds.distances(radius,settings,manual)
    local stream={min={},max={}}
    for _,k in ipairs(AXES) do stream.min[k]=world.min[k]-range;stream.max[k]=world.max[k]+range end
    finish(stream)
    local cell_list,cell_count=cells(world,settings.cell_size)
    local rec={version=1,kind=kind,exact=exact,transform_key=transform_key(o.transform),
        ['local']=round(Util.deepcopy(local_b)),world=round(world),obb=obb,sphere={center=Util.deepcopy(obb.center),radius=radius},
        visibility={min=Util.deepcopy(world.min),max=Util.deepcopy(world.max),distance=vis,render=kind=='procedural'},
        streaming={range=range,secondary_range=secondary,source=manual and 'manual' or 'auto',min=stream.min,max=stream.max,
            cells=cell_list,cell_count=cell_count,cell_size=settings.cell_size,ref_point=Util.deepcopy(obb.center)}}
    if kind=='collider' then rec.visibility.render=false;rec.visibility.distance=nil end
    -- Collision bounds: the object's own generated colliders.
    local cfg=o.metadata.procedural
    if cfg and #(cfg.collider_ids or {})>0 then
        local cb=empty();local n=0
        for _,id in ipairs(cfg.collider_ids) do
            local c=self.app.model:get_object(id)
            if c then local w=world_of(collider_local(c),c.transform);merge(cb,w);n=n+1 end
        end
        if n>0 then rec.collision=round(finish(cb));rec.collision.count=n end
    elseif kind=='collider' then rec.collision=round(Util.deepcopy(world));rec.collision.count=1 end
    return rec
end

-- World AABB for other modules (overlap, fit, visibility): always fresh for the current transform.
function Bounds:world_aabb(o)
    if not self:kind_of(o) then return nil end
    local rec=self:compute(o);return rec and rec.world or nil
end

function Bounds:store(o)
    local rec,err=self:compute(o);if not rec then return nil,err end
    rec.computed_at=Util.now_iso()
    o.metadata.generated_bounds=rec
    if rec.kind=='procedural' then
        o.metadata.asset_bounds={min=Util.deepcopy(rec['local'].min),max=Util.deepcopy(rec['local'].max),source='procedural',exact=rec.exact}
    end
    return rec
end

-- Stored record, recomputed when the transform (or geometry) changed since.
function Bounds:get(object_id)
    local o=self.app.model:get_object(object_id);if not o then return nil,'object not found' end
    if not self:kind_of(o) then return nil,'not a generated resource (procedural geometry or a generated collider)' end
    local rec=o.metadata.generated_bounds
    if rec and rec.transform_key==transform_key(o.transform) then return Util.deepcopy(rec) end
    local err;rec,err=self:store(o);if not rec then return nil,err end
    local out=Util.deepcopy(rec);out.refreshed=true
    return out
end

-- Room bounds from its generated pieces (parametric rooms).
function Bounds:room_bounds(room_id)
    local room=self.app.model:get_room(room_id);if not room then return nil,'room not found' end
    local b=empty();local n=0;local collision=empty();local nc=0
    for _,o in ipairs(self.app.model.data.objects) do
        if o.room_id==room_id then
            local kind=self:kind_of(o)
            if kind then
                local rec=self:compute(o)
                if rec then
                    if kind=='procedural' then merge(b,rec.world);n=n+1 else merge(collision,rec.world);nc=nc+1 end
                end
            end
        end
    end
    if n==0 then return nil,'the room has no generated geometry' end
    local out={room_id=room_id,world=round(finish(b)),pieces=n}
    if nc>0 then out.collision=round(finish(collision));out.collision.count=nc end
    local settings=self:settings()
    local e=out.world.extents;local radius=math.sqrt(e.x*e.x+e.y*e.y+e.z*e.z)
    local vis,range,secondary=Bounds.distances(radius,settings,nil)
    out.visibility_distance=vis;out.streaming={range=range,secondary_range=secondary,cells=(cells(out.world,settings.cell_size))}
    return out
end

-- Recompute and store bounds for every generated resource in scope (derived data, no undo step).
function Bounds:refresh(args)
    args=args or {}
    local n,errors=0,{}
    for _,o in ipairs(self.app.model.data.objects) do
        if self:kind_of(o) and (not args.premise_id or o.premise_id==args.premise_id) and (not args.room_id or o.room_id==args.room_id)
            and (not args.object_id or o.id==args.object_id) then
            local rec,err=self:store(o);if rec then n=n+1 else errors[#errors+1]={id=o.id,name=o.name,error=err} end
        end
    end
    for _,rec in ipairs(self.app.model.data.generated_rooms or {}) do
        local room=self.app.model:get_room(rec.id)
        if room and (not args.premise_id or room.premise_id==args.premise_id) and (not args.room_id or rec.id==args.room_id) then
            rec.bounds=self:room_bounds(rec.id)
        end
    end
    if n>0 then self.app:mark_dirty() end
    return {updated=n,errors=errors,settings=self:settings()}
end

-- Checks for preflight: stale/missing records, pop-in, sector straddling.
function Bounds:issues(objects)
    local out={}
    local settings=self:settings()
    for _,o in ipairs(objects) do
        local kind=self:kind_of(o)
        if kind=='procedural' then
            local rec=self:compute(o)
            if not rec then out[#out+1]={severity='error',object_id=o.id,name=o.name,message='generated geometry has no computable bounds'}
            else
                local stored=o.metadata.generated_bounds
                if not stored or stored.transform_key~=rec.transform_key then out[#out+1]={severity='info',object_id=o.id,name=o.name,message='bounds were refreshed for the current transform'};self:store(o) end
                if rec.streaming.source=='manual' and rec.streaming.range+1e-6<rec.visibility.distance then
                    out[#out+1]={severity='warning',object_id=o.id,name=o.name,message=string.format('stream_range %.0f m is shorter than its visibility distance %.0f m; it will pop in (clear stream_range to use the automatic range)',rec.streaming.range,rec.visibility.distance)}
                end
                if rec.streaming.cell_count and rec.streaming.cell_count>1 then
                    out[#out+1]={severity='info',object_id=o.id,name=o.name,message=string.format('spans %d streaming cells of %g m; it streams with the sector that holds its centre',rec.streaming.cell_count,settings.cell_size)}
                end
                if not rec.exact then out[#out+1]={severity='info',object_id=o.id,name=o.name,message='bounds are approximate (curved CSG); Build Mod uses the exact mesh bounds'} end
            end
        end
    end
    return out
end

Bounds.DEFAULTS=DEFAULTS
return Bounds
