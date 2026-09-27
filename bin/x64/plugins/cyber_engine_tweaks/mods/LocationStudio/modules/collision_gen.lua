local Util=require('modules/util')

-- Collision generator for procedural geometry.
--
-- Turns the parts of a procedural object into World Builder collision
-- primitives following rules. Rules are set at three levels, each overriding the one before:
-- project default -> room (model.data.collision_rules.rooms[room_id]) ->
-- object (metadata.procedural.collision_rules).
--
--   mode        exact (one collider per part) | simplified (merge boxes within
--               `tolerance` of extra volume, then down to `max_boxes`) |
--               convex (one box per connected piece; World Builder colliders are
--               primitives, so a piece's convex hull is its fitted box) |
--               bounds (one box) | none
--   actors      who the colliders block, as a collision preset:
--               all (World Static) | player (Player Blocker) | npc (NPC Trace
--               Obstacle) | player_vehicles | vehicles | camera | sight.
--               `preset` names any preset explicitly.
--   material    physics material (concrete, metal, glass, ...)
--   doorways    auto: door openings of the premise's rooms are cut out of the
--               colliders (from the room floor to the door head,
--               `door_clearance` either side of the wall) | keep
--   exclude     extra boxes [{center, size, yaw}] cut out, in the frame of
--               the scope that sets them (world / room / object)
--   rails       solid: a railing becomes one thin barrier per segment,
--               `rail_height` high (default the railing's height) | parts | none
--   glass       pass (glass slots get no collision) | block
--   min_thickness  thin colliders are thickened to this (m)
--   per_room    split colliders at room boundaries and assign each piece to
--               its room, so collision can be reported and toggled per room
--
-- Cuts and room splits are exact when the boxes are aligned: the same
-- roll/pitch, and a yaw difference that is a multiple of 90 degrees. A cut that
-- is not aligned leaves the collider whole and reports a warning.
local Gen={};Gen.__index=Gen

local ACTOR_PRESETS={all='World Static',player='Player Blocker',npc='NPC Trace Obstacle',player_vehicles='Block Player and Vehicles',
    vehicles='Vehicle Blocker',camera='Block PhotoMode Camera',sight='Sight Blocker'}
local MODES={exact=true,simplified=true,convex=true,bounds=true,none=true}
local DEFAULTS={mode='exact',actors='all',max_boxes=64,tolerance=0.1,min_thickness=0.05,doorways='auto',door_clearance=0.3,
    rails='solid',rail_thickness=0.1,glass='pass',per_room=false}
local MAX_COLLIDERS=200
local MAX_PAIRWISE=400
local TINY=1e-3
local MIN_PIECE=0.02 -- World Builder colliders are at least 2 cm on every axis

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function vec(p) if type(p)~='table' then return nil end;local x,y,z=num(p.x or p[1]),num(p.y or p[2]),num(p.z or p[3],0);if not x or not y then return nil end;return {x=x,y=y,z=z} end
local function rotate(v,r)
    local cy,sy=math.cos(math.rad(r.yaw or 0)),math.sin(math.rad(r.yaw or 0))
    local cp,sp=math.cos(math.rad(r.pitch or 0)),math.sin(math.rad(r.pitch or 0))
    local cr,sr=math.cos(math.rad(r.roll or 0)),math.sin(math.rad(r.roll or 0))
    local x,y,z=v.x*cr+v.z*sr,v.y,-v.x*sr+v.z*cr
    y,z=y*cp-z*sp,y*sp+z*cp
    return {x=x*cy-y*sy,y=x*sy+y*cy,z=z}
end
local function unrotate(v,r) v=rotate(v,{yaw=-(r.yaw or 0)});v=rotate(v,{pitch=-(r.pitch or 0)});return rotate(v,{roll=-(r.roll or 0)}) end
local function add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function rot(r) r=r or {};return {roll=num(r.roll,0),pitch=num(r.pitch,0),yaw=num(r.yaw,0)} end
local function mod(a,m) return a-math.floor(a/m)*m end

function Gen.new(app) return setmetatable({app=app},Gen) end
function Gen.defaults() return Util.deepcopy(DEFAULTS) end
function Gen.actor_presets() return Util.deepcopy(ACTOR_PRESETS) end

-- ------------------------------------------------------------------ rules

local function clean_box(b,where)
    if type(b)~='table' then return nil,where..' must be {center, size, yaw}' end
    local c,s=vec(b.center),vec(b.size)
    if not c or not s or s.x<=0 or s.y<=0 or s.z<=0 then return nil,where..' needs a center and a positive size' end
    return {center=c,size=s,yaw=num(b.yaw,0)}
end

-- Validate a (partial) rule set; only the keys given are kept.
function Gen.normalize_rules(r)
    if r==nil then return {} end
    if type(r)~='table' then return nil,'rules must be an object' end
    local out={}
    for k,v in pairs(r) do
        if k=='mode' then if not MODES[v] then return nil,'mode must be exact, simplified, convex, bounds or none' end;out.mode=v
        elseif k=='actors' then if not ACTOR_PRESETS[v] then return nil,'actors must be all, player, npc, player_vehicles, vehicles, camera or sight' end;out.actors=v
        elseif k=='preset' or k=='material' then if v~='' then if type(v)~='string' and type(v)~='number' then return nil,k..' must be a name' end;out[k]=v end
        elseif k=='max_boxes' then v=math.floor(num(v,0));if v<1 or v>MAX_COLLIDERS then return nil,'max_boxes must be 1-'..MAX_COLLIDERS end;out.max_boxes=v
        elseif k=='tolerance' then v=num(v);if not v or v<0 or v>1 then return nil,'tolerance must be 0-1 (extra volume per merge)' end;out.tolerance=v
        elseif k=='min_thickness' or k=='rail_thickness' then v=num(v);if not v or v<MIN_PIECE or v>2 then return nil,k..' must be 0.02-2 m' end;out[k]=v
        elseif k=='door_clearance' then v=num(v);if not v or v<0 or v>2 then return nil,'door_clearance must be 0-2 m' end;out.door_clearance=v
        elseif k=='rail_height' then v=num(v);if not v or v<0.1 or v>10 then return nil,'rail_height must be 0.1-10 m' end;out.rail_height=v
        elseif k=='doorways' then if v~='auto' and v~='keep' then return nil,'doorways must be auto or keep' end;out.doorways=v
        elseif k=='rails' then if v~='solid' and v~='parts' and v~='none' then return nil,'rails must be solid, parts or none' end;out.rails=v
        elseif k=='glass' then if v~='pass' and v~='block' then return nil,'glass must be pass or block' end;out.glass=v
        elseif k=='per_room' then out.per_room=v==true
        elseif k=='exclude' then
            if type(v)~='table' then return nil,'exclude must be a list of boxes' end
            out.exclude={}
            for i,b in ipairs(v) do local c,err=clean_box(b,'exclude['..i..']');if not c then return nil,err end;out.exclude[i]=c end
            if #out.exclude>64 then return nil,'at most 64 exclusion boxes' end
        else return nil,'unknown collision rule: '..tostring(k) end
    end
    return out
end

local function store(model)
    local s=model.data.collision_rules
    if type(s)~='table' then s={};model.data.collision_rules=s end
    if type(s.default)~='table' then s.default={} end
    if type(s.rooms)~='table' or (next(s.rooms)~=nil and #s.rooms>0) then s.rooms={} end
    return s
end

-- scope: 'default' | 'room:<id>' | 'object:<id>' -> table, kind, id
function Gen:_scope(scope)
    scope=tostring(scope or 'default')
    local kind,id=scope:match('^(%a+):(.+)$')
    if scope=='default' then return store(self.app.model).default,'default' end
    if kind=='room' then
        if not self.app.model:get_room(id) then return nil,'room not found: '..id end
        return store(self.app.model).rooms[id] or {},'room',id
    end
    if kind=='object' then
        local o=self.app.model:get_object(id);local cfg=o and o.metadata and o.metadata.procedural
        if not cfg then return nil,'not a procedural object: '..id end
        return cfg.collision_rules or {},'object',id
    end
    return nil,'scope must be default, room:<id> or object:<id>'
end

function Gen:get_rules(scope)
    local r,kind,id=self:_scope(scope);if not r then return nil,kind end
    return {scope=scope or 'default',kind=kind,id=id,rules=Util.deepcopy(r)}
end

-- Rules for an object, and where each key came from.
function Gen:effective(object)
    local out=Util.deepcopy(DEFAULTS);local source={}
    for k in pairs(DEFAULTS) do source[k]='builtin' end
    local s=store(self.app.model)
    local excludes={}
    local function apply(r,label,frame)
        for k,v in pairs(r or {}) do
            if k=='exclude' then for _,b in ipairs(v) do excludes[#excludes+1]={box=b,frame=frame} end
            else out[k]=Util.deepcopy(v);source[k]=label end
        end
    end
    apply(s.default,'default',{kind='world'})
    local room=object.room_id and self.app.model:get_room(object.room_id)
    if room then apply(s.rooms[room.id],'room:'..room.id,{kind='room',room=room}) end
    local cfg=object.metadata and object.metadata.procedural or {}
    apply(cfg.collision_rules,'object',{kind='object'})
    out.exclude=excludes
    return out,source
end

-- ------------------------------------------------------------------ box algebra
-- Boxes: {center, size, rotation, shape='box'|'sphere', radius, material_slot, role}

-- Frame relation of b inside a: aligned -> b's centre and half extents in a's frame.
local function in_frame(a,b)
    local ra,rb=a.rotation,b.rotation
    if math.abs(ra.roll-rb.roll)>1e-6 or math.abs(ra.pitch-rb.pitch)>1e-6 then return nil end
    if (math.abs(ra.roll)>1e-6 or math.abs(ra.pitch)>1e-6) and math.abs(ra.yaw-rb.yaw)>1e-6 then return nil end
    local d=mod(rb.yaw-ra.yaw,90);if d>1e-6 and 90-d>1e-6 then return nil end
    local quarter=math.floor(mod(rb.yaw-ra.yaw,360)/90+0.5)%2==1
    local c=unrotate(sub(b.center,a.center),ra)
    local h={x=b.size.x/2,y=b.size.y/2,z=b.size.z/2};if quarter then h.x,h.y=h.y,h.x end
    return c,h
end

local function from_frame(a,lo,hi)
    local c={x=(lo.x+hi.x)/2,y=(lo.y+hi.y)/2,z=(lo.z+hi.z)/2}
    local out=Util.deepcopy(a);out.center=add(a.center,rotate(c,a.rotation));out.size={x=hi.x-lo.x,y=hi.y-lo.y,z=hi.z-lo.z}
    return out
end

-- a minus b (aligned only): list of boxes, or nil when not aligned.
function Gen.subtract(a,b)
    if a.shape=='sphere' then return nil end
    local c,h=in_frame(a,b);if not c then return nil end
    local alo,ahi={x=-a.size.x/2,y=-a.size.y/2,z=-a.size.z/2},{x=a.size.x/2,y=a.size.y/2,z=a.size.z/2}
    local blo,bhi={x=c.x-h.x,y=c.y-h.y,z=c.z-h.z},{x=c.x+h.x,y=c.y+h.y,z=c.z+h.z}
    for _,k in ipairs({'x','y','z'}) do if bhi[k]<=alo[k]+TINY or blo[k]>=ahi[k]-TINY then return {a},false end end
    local out={};local lo,hi=Util.deepcopy(alo),Util.deepcopy(ahi)
    for _,k in ipairs({'x','y','z'}) do
        -- Slabs thinner than a collider can be are dropped (a sliver under a door, for example).
        if blo[k]>lo[k]+TINY then local l,h2=Util.deepcopy(lo),Util.deepcopy(hi);h2[k]=blo[k];if h2[k]-l[k]>=MIN_PIECE then out[#out+1]=from_frame(a,l,h2) end;lo[k]=blo[k] end
        if bhi[k]<hi[k]-TINY then local l,h2=Util.deepcopy(lo),Util.deepcopy(hi);l[k]=bhi[k];if h2[k]-l[k]>=MIN_PIECE then out[#out+1]=from_frame(a,l,h2) end;hi[k]=bhi[k] end
    end
    return out,true
end

-- a intersect b (aligned only): box, false when disjoint, nil when not aligned.
function Gen.intersect(a,b)
    local c,h=in_frame(a,b);if not c then return nil end
    local lo,hi={},{}
    for _,k in ipairs({'x','y','z'}) do
        lo[k]=math.max(-a.size[k]/2,c[k]-h[k]);hi[k]=math.min(a.size[k]/2,c[k]+h[k])
        if hi[k]-lo[k]<=TINY then return false end
    end
    return from_frame(a,lo,hi)
end

-- Rotation class: boxes that can be merged share it (yaw modulo 90, same roll/pitch).
local function class_of(b)
    local r=b.rotation
    if math.abs(r.roll)>1e-6 or math.abs(r.pitch)>1e-6 then return string.format('r%.4f/%.4f/%.4f',r.roll,r.pitch,r.yaw),{roll=r.roll,pitch=r.pitch,yaw=r.yaw} end
    local y0=mod(r.yaw,90);if 90-y0<1e-6 then y0=0 end
    return string.format('y%.4f',y0),{roll=0,pitch=0,yaw=y0}
end

-- To/from axis-aligned boxes in a class frame.
local function to_aabb(b,frame)
    local c,h=in_frame({center={x=0,y=0,z=0},rotation=frame,size={x=0,y=0,z=0}},b)
    return {lo={x=c.x-h.x,y=c.y-h.y,z=c.z-h.z},hi={x=c.x+h.x,y=c.y+h.y,z=c.z+h.z}}
end
local function from_aabb(q,frame,template)
    local base={center={x=0,y=0,z=0},rotation=frame,size={x=0,y=0,z=0},shape='box'}
    local out=from_frame(base,q.lo,q.hi);out.shape='box';out.role=template and template.role or 'geometry'
    return out
end
local function vol(q) return (q.hi.x-q.lo.x)*(q.hi.y-q.lo.y)*(q.hi.z-q.lo.z) end
local function union_box(a,b) return {lo={x=math.min(a.lo.x,b.lo.x),y=math.min(a.lo.y,b.lo.y),z=math.min(a.lo.z,b.lo.z)},hi={x=math.max(a.hi.x,b.hi.x),y=math.max(a.hi.y,b.hi.y),z=math.max(a.hi.z,b.hi.z)}} end
local function overlap(a,b)
    local v=1
    for _,k in ipairs({'x','y','z'}) do local d=math.min(a.hi[k],b.hi[k])-math.max(a.lo[k],b.lo[k]);if d<=0 then return 0 end;v=v*d end
    return v
end
local function extra(a,b) return vol(union_box(a,b))-vol(a)-vol(b)+overlap(a,b) end

-- Merge boxes that share a whole face (lossless), sweeping each axis.
local function exact_merge(list)
    local changed=true
    while changed do
        changed=false
        for _,k in ipairs({'x','y','z'}) do
            local o={x={'y','z'},y={'x','z'},z={'x','y'}};local a1,a2=o[k][1],o[k][2]
            local function key(q) return string.format('%.4f|%.4f|%.4f|%.4f',q.lo[a1],q.hi[a1],q.lo[a2],q.hi[a2]) end
            table.sort(list,function(p,q) local kp,kq=key(p),key(q);if kp~=kq then return kp<kq end;return p.lo[k]<q.lo[k] end)
            local out={}
            for _,q in ipairs(list) do
                local last=out[#out]
                if last and key(last)==key(q) and q.lo[k]<=last.hi[k]+TINY then last.hi[k]=math.max(last.hi[k],q.hi[k]);changed=true
                else out[#out+1]={lo=Util.deepcopy(q.lo),hi=Util.deepcopy(q.hi)} end
            end
            list=out
        end
    end
    return list
end

-- Greedy lossy merge: cheapest extra volume first, within tolerance, then down to `budget`.
local function greedy_merge(list,tolerance,budget)
    local n=#list;local forced=0
    local alive={};for i=1,n do alive[i]=true end
    local best,bestj={},{}
    local function rescan(i)
        best[i],bestj[i]=math.huge,nil
        for j=1,n do if j~=i and alive[j] then local c=extra(list[i],list[j]);if c<best[i] then best[i],bestj[i]=c,j end end end
    end
    for i=1,n do rescan(i) end
    local count=n
    while count>1 do
        local bi;for i=1,n do if alive[i] and bestj[i] and (not bi or best[i]<best[bi]) then bi=i end end
        if not bi then break end
        local j=bestj[bi];local merged=union_box(list[bi],list[j])
        local within=best[bi]<=tolerance*vol(merged)+1e-12
        if not within and count<=budget then break end
        if not within then forced=forced+1 end
        list[bi]=merged;alive[j]=false;count=count-1
        rescan(bi)
        for i=1,n do
            if alive[i] and i~=bi then
                if bestj[i]==bi or bestj[i]==j then rescan(i)
                else local c=extra(list[i],list[bi]);if c<best[i] then best[i],bestj[i]=c,bi end end
            end
        end
    end
    local out={};for i=1,n do if alive[i] then out[#out+1]=list[i] end end
    return out,forced
end

-- ------------------------------------------------------------------ sources

local function part_boxes(parts,rules)
    local out={}
    for _,p in ipairs(parts or {}) do
        if p.material~='glass' or rules.glass=='block' then
            local r=rot(p.rotation)
            if p.shape=='box' then out[#out+1]={shape='box',center=Util.deepcopy(p.center),size=Util.deepcopy(p.size),rotation=r}
            elseif p.shape=='cylinder' then out[#out+1]={shape='box',center=Util.deepcopy(p.center),size={x=p.radius*2,y=p.length,z=p.radius*2},rotation=r}
            elseif p.shape=='sphere' then out[#out+1]={shape='sphere',center=Util.deepcopy(p.center),radius=p.radius,size={x=p.radius*2,y=p.radius*2,z=p.radius*2},rotation={roll=0,pitch=0,yaw=0}}
            elseif p.shape=='wedge' then
                local L,H=p.size.y,p.size.z;local len=math.sqrt(L*L+H*H)
                out[#out+1]={shape='box',center=Util.deepcopy(p.center),size={x=p.size.x,y=len,z=0.05},rotation={roll=0,pitch=math.deg(math.atan(H/L)),yaw=r.yaw}}
            elseif p.shape=='prism' then
                local lo={x=math.huge,y=math.huge};local hi={x=-math.huge,y=-math.huge}
                for _,q in ipairs(p.points) do lo.x=math.min(lo.x,q.x);lo.y=math.min(lo.y,q.y);hi.x=math.max(hi.x,q.x);hi.y=math.max(hi.y,q.y) end
                out[#out+1]={shape='box',center={x=(lo.x+hi.x)/2,y=(lo.y+hi.y)/2,z=(p.z0+p.z1)/2},size={x=hi.x-lo.x,y=hi.y-lo.y,z=p.z1-p.z0},rotation={roll=0,pitch=0,yaw=0}}
            end
            if out[#out] then out[#out].role=p.material=='glass' and 'glass' or 'geometry' end
        end
    end
    return out
end

-- One barrier per railing segment.
local function rail_boxes(params,rules)
    local pts={}
    if type(params.points)=='table' then for _,p in ipairs(params.points) do local v=vec(p);if v then pts[#pts+1]=v end end
    else local L=num(params.length,3);pts={{x=-L/2,y=0,z=0},{x=L/2,y=0,z=0}} end
    local h=rules.rail_height or num(params.height,1);local t=rules.rail_thickness
    local out={}
    for i=1,#pts-1 do
        local a,b=pts[i],pts[i+1];local d=sub(b,a);local len=math.sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
        if len>1e-4 then
            local r={roll=0,pitch=math.deg(math.asin(math.max(-1,math.min(1,d.z/len)))),yaw=math.deg(math.atan2(-d.x,d.y))}
            local mid={x=(a.x+b.x)/2,y=(a.y+b.y)/2,z=(a.z+b.z)/2}
            out[#out+1]={shape='box',center=add(mid,rotate({x=0,y=0,z=h/2},r)),size={x=t,y=len,z=h},rotation=r,role='rail'}
        end
    end
    return out
end

-- World box of a scope exclusion or a door opening -> object frame.
local function to_object(object,box)
    local t=object.transform;local r=rot(t.rotation)
    local c=unrotate(sub(box.center,t.position),r)
    return {shape='box',center=c,size=box.size,rotation={roll=-r.roll,pitch=-r.pitch,yaw=(box.yaw or 0)-r.yaw}}
end
local function room_to_world(room,local_c,yaw)
    local r=rot(room.transform.rotation)
    return add(room.transform.position,rotate(local_c,{yaw=r.yaw})),r.yaw+(yaw or 0)
end

function Gen:_generated_floor(room_id)
    for _,rec in ipairs(self.app.model.data.generated_rooms or {}) do
        if rec.id==room_id then local f=rec.spec and rec.spec.floor or {};return f.type=='raised' and (f.raise or 0) or 0,rec.spec.wall_thickness end
    end
    return 0,nil
end

-- Exclusion boxes (world) for the door openings of the premise's rooms.
function Gen:door_volumes(premise_id,clearance)
    local out={}
    for _,room in ipairs(self.app.model.data.rooms or {}) do
        if room.premise_id==premise_id then
            local floor_top,gen_t=self:_generated_floor(room.id)
            local T=gen_t or room.wall_thickness or 0.2
            local W,D=room.size.width,room.size.depth
            for _,o in ipairs(room.openings or {}) do
                if o.kind=='door' then
                    local across=2*T+2*clearance
                    local z0=floor_top+(o.sill or 0);local z1=(o.sill or 0)+o.height
                    if z1>z0 then
                        local lc,size
                        if o.wall=='north' or o.wall=='south' then
                            lc={x=o.offset,y=(o.wall=='north' and 1 or -1)*D/2,z=(z0+z1)/2};size={x=o.width,y=across,z=z1-z0}
                        else
                            lc={x=(o.wall=='east' and 1 or -1)*W/2,y=o.offset,z=(z0+z1)/2};size={x=across,y=o.width,z=z1-z0}
                        end
                        local c,yaw=room_to_world(room,lc,0)
                        out[#out+1]={center=c,size=size,yaw=yaw,room_id=room.id,wall=o.wall,opening_id=o.id}
                    end
                end
            end
        end
    end
    return out
end

-- Room volumes (world) used by per-room splitting.
function Gen:_room_volumes(premise_id)
    local out={}
    for _,room in ipairs(self.app.model.data.rooms or {}) do
        if room.premise_id==premise_id then
            local _,gen_t=self:_generated_floor(room.id);local T=gen_t or room.wall_thickness or 0.2
            local h=room.size.height or 3
            local c,yaw=room_to_world(room,{x=0,y=0,z=h/2},0)
            out[#out+1]={room_id=room.id,center=c,size={x=room.size.width+T,y=room.size.depth+T,z=h+1},yaw=yaw}
        end
    end
    return out
end

-- ------------------------------------------------------------------ plan

-- Colliders (object frame) for a procedural object, under its effective rules.
function Gen:plan(object,parts)
    local cfg=object.metadata and object.metadata.procedural or {}
    local rules,source=self:effective(object)
    local stats={mode=rules.mode,source_boxes=0,merged=0,forced_merges=0,excluded=0,split=0}
    local warnings={}
    if rules.mode=='none' then return {boxes={},rules=rules,source=source,stats=stats,warnings=warnings,preset=nil} end
    local boxes
    if cfg.generator=='railing' and rules.rails~='parts' then
        boxes=rules.rails=='solid' and rail_boxes(cfg.params or {},rules) or {}
    else boxes=part_boxes(parts or cfg.parts,rules) end
    stats.source_boxes=#boxes
    -- Thin boxes get the minimum thickness.
    for _,b in ipairs(boxes) do if b.shape=='box' then for _,k in ipairs({'x','y','z'}) do if b.size[k]<rules.min_thickness then b.size[k]=rules.min_thickness end end end end
    -- Simplification.
    if rules.mode~='exact' and #boxes>0 then
        local classes,order={},{}
        for _,b in ipairs(boxes) do
            if b.shape=='sphere' then b=Util.deepcopy(b);b.shape='box' end
            local key,frame=class_of(b)
            if not classes[key] then classes[key]={frame=frame,items={},roles={}};order[#order+1]=key end
            local q=to_aabb(b,frame);classes[key].items[#classes[key].items+1]=q;classes[key].roles[b.role or 'geometry']=true
        end
        local out={}
        if rules.mode=='bounds' or rules.mode=='convex' then
            -- Connected pieces (touching within 1 cm) in the object frame; one fitted box each.
            local all={};for _,key in ipairs(order) do local c=classes[key];for _,q in ipairs(c.items) do all[#all+1]={q=q,frame=c.frame,key=key} end end
            local parent={};for i=1,#all do parent[i]=i end
            local function find(i) while parent[i]~=i do parent[i]=parent[parent[i]];i=parent[i] end;return i end
            local world={}
            for i,a in ipairs(all) do
                local lo,hi={x=math.huge,y=math.huge,z=math.huge},{x=-math.huge,y=-math.huge,z=-math.huge}
                local b=from_aabb(a.q,a.frame)
                for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
                    local p=add(b.center,rotate({x=sx*b.size.x/2,y=sy*b.size.y/2,z=sz*b.size.z/2},b.rotation))
                    for _,k in ipairs({'x','y','z'}) do lo[k]=math.min(lo[k],p[k]);hi[k]=math.max(hi[k],p[k]) end
                end end end
                world[i]={lo=lo,hi=hi}
            end
            if rules.mode=='convex' then
                for i=1,#all do for j=i+1,#all do
                    local touch=true
                    for _,k in ipairs({'x','y','z'}) do if world[i].lo[k]>world[j].hi[k]+0.01 or world[j].lo[k]>world[i].hi[k]+0.01 then touch=false end end
                    if touch then parent[find(i)]=find(j) end
                end end
            else for i=2,#all do parent[find(i)]=find(1) end end
            local groups,gorder={},{}
            for i=1,#all do local r=find(i);if not groups[r] then groups[r]={};gorder[#gorder+1]=r end;table.insert(groups[r],i) end
            for _,r in ipairs(gorder) do
                local members=groups[r];local same=true
                for _,i in ipairs(members) do if all[i].key~=all[members[1]].key then same=false end end
                local q
                if same then q=all[members[1]].q;for _,i in ipairs(members) do q=union_box(q,all[i].q) end;out[#out+1]=from_aabb(q,all[members[1]].frame)
                else q=world[members[1]];for _,i in ipairs(members) do q=union_box(q,world[i]) end;out[#out+1]=from_aabb(q,{roll=0,pitch=0,yaw=0}) end
            end
        else
            for _,key in ipairs(order) do
                local c=classes[key]
                local list=exact_merge(c.items)
                if #list>MAX_PAIRWISE then return nil,'simplified collision would compare '..#list..' boxes; use mode convex or bounds for this geometry' end
                local forced;list,forced=greedy_merge(list,rules.tolerance,math.max(1,math.floor(rules.max_boxes*#c.items/#boxes)))
                stats.forced_merges=stats.forced_merges+forced
                for _,q in ipairs(list) do out[#out+1]=from_aabb(q,c.frame,{role=c.roles.rail and 'rail' or 'geometry'}) end
            end
            if #out>rules.max_boxes then warnings[#warnings+1]=#out..' boxes remain across '..#order..' rotation groups (max_boxes '..rules.max_boxes..')' end
        end
        stats.merged=#boxes-#out
        boxes=out
    end
    -- Exclusions: door openings and rule boxes, cut out of the colliders.
    local cutters={}
    if rules.doorways=='auto' and object.premise_id then
        for _,d in ipairs(self:door_volumes(object.premise_id,rules.door_clearance)) do cutters[#cutters+1]={box=to_object(object,d),label='door '..tostring(d.wall)..' of '..tostring(d.room_id)} end
    end
    for _,e in ipairs(rules.exclude or {}) do
        local b=e.box;local world
        if e.frame.kind=='object' then cutters[#cutters+1]={box={shape='box',center=b.center,size=b.size,rotation={roll=0,pitch=0,yaw=b.yaw}},label='exclude'}
        else
            if e.frame.kind=='room' then local c,yaw=room_to_world(e.frame.room,b.center,b.yaw);world={center=c,size=b.size,yaw=yaw}
            else world={center=b.center,size=b.size,yaw=b.yaw} end
            cutters[#cutters+1]={box=to_object(object,world),label='exclude'}
        end
    end
    for _,cut in ipairs(cutters) do
        local out={}
        for _,b in ipairs(boxes) do
            local pieces,hit=Gen.subtract(b,cut.box)
            if pieces==nil then
                local c,h=cut.box.center,{x=cut.box.size.x/2+b.size.x/2,y=cut.box.size.y/2+b.size.y/2,z=cut.box.size.z/2+b.size.z/2}
                local d=sub(b.center,c)
                if math.abs(d.x)<math.max(h.x,h.y) and math.abs(d.y)<math.max(h.x,h.y) and math.abs(d.z)<h.z then
                    warnings[#warnings+1]='a '..tostring(b.shape)..' collider is not aligned with the '..cut.label..' exclusion and was kept whole'
                end
                out[#out+1]=b
            else
                if hit then stats.excluded=stats.excluded+1 end
                for _,p in ipairs(pieces) do p.role=b.role;out[#out+1]=p end
            end
        end
        boxes=out
    end
    -- Rooms.
    for _,b in ipairs(boxes) do b.room_id=object.room_id end
    if rules.per_room and object.premise_id then
        local rooms={};for _,v in ipairs(self:_room_volumes(object.premise_id)) do rooms[#rooms+1]={room_id=v.room_id,box=to_object(object,v)} end
        local out={}
        for _,b in ipairs(boxes) do
            local rest={b};local pieces=0
            for _,room in ipairs(rooms) do
                local next_rest={}
                for _,piece in ipairs(rest) do
                    local inside=Gen.intersect(piece,room.box)
                    if inside==nil then
                        -- Not aligned: assign the whole piece by its centre.
                        local c=unrotate(sub(piece.center,room.box.center),room.box.rotation)
                        if math.abs(c.x)<=room.box.size.x/2 and math.abs(c.y)<=room.box.size.y/2 and math.abs(c.z)<=room.box.size.z/2 then piece.room_id=room.room_id;out[#out+1]=piece;pieces=pieces+1
                        else next_rest[#next_rest+1]=piece end
                    elseif inside==false then next_rest[#next_rest+1]=piece
                    else
                        inside.room_id=room.room_id;inside.role=piece.role;out[#out+1]=inside;pieces=pieces+1
                        local remain=Gen.subtract(piece,room.box)
                        for _,r in ipairs(remain or {}) do r.role=piece.role;next_rest[#next_rest+1]=r end
                    end
                end
                rest=next_rest
            end
            for _,r in ipairs(rest) do out[#out+1]=r;pieces=pieces+1 end
            if pieces>1 then stats.split=stats.split+pieces-1 end
        end
        boxes=out
    end
    if #boxes>MAX_COLLIDERS then return nil,'these rules produce '..#boxes..' colliders; the limit is '..MAX_COLLIDERS..' (use mode simplified/convex/bounds or turn collision off)' end
    local preset=rules.preset or cfg.collision_preset or ACTOR_PRESETS[rules.actors]
    return {boxes=boxes,rules=rules,source=source,stats=stats,warnings=warnings,preset=preset,material=rules.material}
end

-- ------------------------------------------------------------------ operations

function Gen:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required and not app.authoring_plans.running then return 'Resolve authoring-plan recovery first' end
    return nil
end

-- Procedural objects with collision in a scope ({object_id} | {room_id} | {premise_id} | {}).
function Gen:_objects(args)
    local out={}
    for _,o in ipairs(self.app.model.data.objects) do
        local cfg=o.metadata and o.metadata.procedural
        if cfg and cfg.collision and (not args.object_id or o.id==args.object_id) and (not args.room_id or o.room_id==args.room_id)
            and (not args.premise_id or o.premise_id==args.premise_id) then out[#out+1]=o end
    end
    return out
end

-- Dry run for an existing object (optionally with trial rules), or for generator output.
function Gen:preview(args)
    args=args or {}
    local object
    if args.object_id then
        object=self.app.model:get_object(args.object_id)
        if not (object and object.metadata and object.metadata.procedural) then return nil,'not a procedural object' end
        object=Util.deepcopy(object)
    else
        if not self.app.procedural then return nil,'procedural geometry is unavailable' end
        local info,err=self.app.procedural.generate(args.generator,args.params);if not info then return nil,err end
        object={id='__preview',premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id,
            transform=args.transform or {position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
            metadata={procedural={generator=args.generator,params=args.params or {},parts=info.parts,collision=true}}}
    end
    if args.rules~=nil then
        local r,err=Gen.normalize_rules(args.rules);if not r then return nil,err end
        local merged=Util.deepcopy(object.metadata.procedural.collision_rules or {});for k,v in pairs(r) do merged[k]=v end
        object.metadata.procedural.collision_rules=merged
    end
    local plan,err=self:plan(object,object.metadata.procedural.parts);if not plan then return nil,err end
    local rooms={}
    for _,b in ipairs(plan.boxes) do local k=b.room_id or '';rooms[k]=(rooms[k] or 0)+1 end
    return {colliders=#plan.boxes,boxes=plan.boxes,preset=plan.preset,material=plan.material,stats=plan.stats,warnings=plan.warnings,
        rules=plan.rules,source=plan.source,rooms=rooms}
end

-- Rebuild the colliders of every procedural object in scope under their current rules. One undo step.
function Gen:regenerate(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    if not self.app.procedural then return nil,'procedural geometry is unavailable' end
    local objects=self:_objects(args)
    for _,o in ipairs(objects) do local _,err=self:plan(o,o.metadata.procedural.parts);if err then return nil,o.name..': '..err end end
    local model=self.app.model
    local before=Util.deepcopy(model.data)
    local live={};for _,o in ipairs(model.data.objects) do if self.app.placement:is_tracked(o) then live[#live+1]=o.id end end
    model:snapshot(args.label or 'Regenerate collision');local mark=#model.undo_stack
    local total,warnings=0,{}
    for _,o in ipairs(objects) do
        local ok,err=self.app.procedural:_rebuild_colliders(o,{parts=o.metadata.procedural.parts})
        if not ok then
            for _,x in ipairs(model.data.objects) do if self.app.placement:is_tracked(x) then pcall(function() self.app.placement:despawn(x) end) end end
            model.data=before;while #model.undo_stack>mark-1 do table.remove(model.undo_stack) end
            for _,id in ipairs(live) do local x=model:get_object(id);if x then pcall(function() self.app.placement:spawn(x) end) end end
            return nil,o.name..': '..tostring(err)
        end
        total=total+#o.metadata.procedural.collider_ids
        for _,w in ipairs(o.metadata.procedural.collision_warnings or {}) do warnings[#warnings+1]=o.name..': '..w end
    end
    while #model.undo_stack>mark do table.remove(model.undo_stack) end
    model:touch();self.app:mark_dirty()
    return {objects=#objects,colliders=total,warnings=warnings}
end

function Gen:set_rules(scope,rules,args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local clean,err=Gen.normalize_rules(rules);if not clean then return nil,err end
    local current,kind,id=self:_scope(scope);if not current then return nil,kind end
    local merged=args.replace and {} or Util.deepcopy(current)
    for k,v in pairs(clean) do merged[k]=v end
    for _,k in ipairs(args.clear or {}) do merged[k]=nil end
    -- Dry-run every affected object first.
    local model=self.app.model
    local backup=Util.deepcopy(current)
    local function put(value)
        if kind=='default' then store(model).default=value
        elseif kind=='room' then store(model).rooms[id]=next(value) and value or nil
        else model:get_object(id).metadata.procedural.collision_rules=next(value) and value or nil end
    end
    put(merged)
    local scope_args=kind=='room' and {room_id=id} or kind=='object' and {object_id=id} or {}
    for _,o in ipairs(self:_objects(scope_args)) do
        local _,perr=self:plan(o,o.metadata.procedural.parts)
        if perr then put(backup);return nil,o.name..': '..perr end
    end
    put(backup)
    model:snapshot('Collision rules '..tostring(scope or 'default'));local mark=#model.undo_stack
    put(merged)
    local result={scope=scope or 'default',rules=Util.deepcopy(merged)}
    if args.regenerate~=false then
        local r,rerr=self:regenerate(Util.deepcopy(scope_args))
        if not r then put(backup);while #model.undo_stack>=mark do table.remove(model.undo_stack) end;return nil,rerr end
        result.regenerated=r
    end
    while #model.undo_stack>mark do table.remove(model.undo_stack) end
    model:touch();self.app:mark_dirty()
    return result
end

-- Generated colliders per room: count, presets, who they block, enabled state.
function Gen:report(args)
    args=args or {}
    local presets={};if self.app.collision then for _,p in ipairs(self.app.collision:presets()) do presets[p.name]=p end end
    local rooms,order={},{}
    for _,o in ipairs(self.app.model.data.objects) do
        local g=o.metadata and o.metadata.collision_gen
        if g and (not args.premise_id or o.premise_id==args.premise_id) then
            local k=o.room_id or '';if not rooms[k] then rooms[k]={room_id=o.room_id,colliders=0,enabled=0,presets={},blocks_player=0,blocks_npc=0,roles={}};order[#order+1]=k end
            local r=rooms[k];r.colliders=r.colliders+1;if o.enabled~=false then r.enabled=r.enabled+1 end
            local name=o.metadata.collision and o.metadata.collision.preset or '?';r.presets[name]=(r.presets[name] or 0)+1
            local p=presets[name];if p and p.blocks_player then r.blocks_player=r.blocks_player+1 end;if p and p.blocks_npc then r.blocks_npc=r.blocks_npc+1 end
            r.roles[g.role or 'geometry']=(r.roles[g.role or 'geometry'] or 0)+1
        end
    end
    local out={};for _,k in ipairs(order) do local r=rooms[k];local room=r.room_id and self.app.model:get_room(r.room_id);r.room=room and room.name or nil;out[#out+1]=r end
    table.sort(out,function(a,b) return tostring(a.room or '')<tostring(b.room or '') end)
    return {rooms=out,count=#out}
end

-- Turn a room's generated colliders on or off (they stay authored). One undo step.
function Gen:set_room_enabled(room_id,enabled)
    local busy=self:_busy();if busy then return nil,busy end
    if not self.app.model:get_room(room_id) then return nil,'room not found' end
    local list={}
    for _,o in ipairs(self.app.model.data.objects) do if o.metadata and o.metadata.collision_gen and o.room_id==room_id then list[#list+1]=o end end
    self.app.model:snapshot((enabled and 'Enable' or 'Disable')..' room collision')
    local failed=0
    for _,o in ipairs(list) do
        o.enabled=enabled==true
        if enabled then if self.app.model.data.settings.workspace.live_preview~=false and not self.app.placement:is_tracked(o) then local id=self.app.placement:spawn(o);if not id then failed=failed+1 end end
        elseif self.app.placement:is_tracked(o) then local ok=self.app.placement:despawn(o);if not ok then failed=failed+1 end end
    end
    self.app.model:touch();self.app:mark_dirty()
    return {room_id=room_id,enabled=enabled==true,colliders=#list,runtime_failures=failed}
end

Gen.ACTOR_PRESETS=ACTOR_PRESETS
return Gen
