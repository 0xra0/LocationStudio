local Util=require('modules/util')

-- Semantic surfaces. Generated geometry records what each of its surfaces is
-- (floor, wall, ceiling, desk, shelf, road, medical_surface, ...), so code
-- generators can place props, decals, lights and effects on the right ones.
--
-- A surface is a flat rectangle in its object's local frame:
--   {tag, traits, center={x,y,z}, normal={x,y,z}, u={x,y,z}, size={u,v}, poly?}
-- `u` runs along the surface, v = normal x u. On a vertical surface v points up.
-- `poly` (optional) is an outline in (u, v) for non-rectangular faces.
--
-- Where surfaces come from:
--   * procedural parts carry a `surface` annotation (generators set them: the
--     floor slab's top is `floor`, stair treads are `stairs`, ...);
--   * a procedural object's `surface` option tags its visible top faces and can
--     retag annotated ones; `surfaces` adds explicit rectangles;
--   * parametric rooms add their interior floor, walls, ceiling and exterior
--     walls (openings are left out);
--   * any object can be tagged by hand from its bounds (metadata.surfaces).
-- Derived surfaces are saved on metadata.procedural.surfaces; hand tags on
-- metadata.surfaces. Queries return them in world space.
local Surfaces={};Surfaces.__index=Surfaces

local MAX_PER_OBJECT=400
local MIN_AREA=0.01
local MAX_PLACEMENTS=500
local MAX_ATTEMPTS=20000
local TAG_PATTERN='^[a-z][a-z0-9_]*$'

-- Vocabulary: the orientation a tag is expected to have and the groups it belongs to.
-- Queries match a tag, any of its groups, or a trait.
local TAGS={
    floor={o='up',is={'walkable','support','interior'},hint='interior floor'},
    ground={o='up',is={'walkable','support','exterior'},hint='outdoor ground'},
    road={o='up',is={'walkable','exterior','traffic'},hint='road surface; keep props off it'},
    sidewalk={o='up',is={'walkable','support','exterior'},hint='pavement'},
    platform={o='up',is={'walkable','support'},hint='raised platform, catwalk, landing'},
    roof={o='up',is={'walkable','support','exterior'},hint='roof top'},
    stairs={o='up',is={'walkable'},hint='stair treads'},
    ramp={o='up',is={'walkable'},hint='sloped walkway'},
    desk={o='up',is={'work_surface','support'},hint='desk top'},
    table={o='up',is={'work_surface','support'},hint='table top'},
    counter={o='up',is={'work_surface','support'},hint='counter top'},
    workbench={o='up',is={'work_surface','support','industrial'},hint='workbench top'},
    medical_surface={o='up',is={'work_surface','support','medical'},hint='examination / treatment / instrument surface'},
    industrial_surface={o='up',is={'work_surface','support','industrial'},hint='machine bed, industrial bench'},
    lab_surface={o='up',is={'work_surface','support','lab'},hint='laboratory bench'},
    kitchen_surface={o='up',is={'work_surface','support','kitchen'},hint='kitchen worktop'},
    shelf={o='up',is={'storage','support'},hint='shelf board'},
    cabinet={o='up',is={'storage','support'},hint='cabinet or locker top'},
    crate={o='up',is={'storage','support'},hint='crate or container top'},
    machine={o='up',is={'support','industrial'},hint='top of a machine or generator'},
    bed={o='up',is={'furniture','support'},hint='bed or bunk mattress'},
    seat={o='up',is={'furniture'},hint='seat'},
    wall={o='side',is={'vertical','interior'},hint='interior wall face'},
    exterior_wall={o='side',is={'vertical','exterior'},hint='outside wall face'},
    partition={o='side',is={'vertical','interior'},hint='partition or screen'},
    glass={o='side',is={'vertical'},hint='window glass'},
    ceiling={o='down',is={'overhead','interior'},hint='ceiling underside'},
    underside={o='down',is={'overhead'},hint='underside of a slab, beam or duct'},
}
local GROUPS={
    walkable='surfaces people walk on',support='anything that can hold props',work_surface='desks, counters, benches',
    storage='shelves, cabinets, crates',furniture='beds and seats',vertical='walls and other vertical faces',overhead='ceilings and undersides',
    interior='inside a building',exterior='outside',traffic='vehicle lanes',medical='medical use',industrial='industrial use',lab='laboratory use',kitchen='kitchen use',
}
Surfaces.TAGS=TAGS;Surfaces.GROUPS=GROUPS

-- Placement defaults per kind: what a generator gets when it does not say.
local KINDS={
    asset={tags={'support'},footprint={0.4,0.4},height=0.4,offset=0},
    procedural={tags={'support'},footprint={0.4,0.4},height=0.4,offset=0},
    decal={tags={'floor','wall'},footprint={1,1},height=0,offset=0.005,avoid=false},
    light={tags={'ceiling'},footprint={0.3,0.3},height=0,offset=0.15,pattern='grid',spacing=3,elevation=2.2,avoid=false},
    effect={tags={'support'},footprint={0.3,0.3},height=0.3,offset=0.02},
    marker={tags={'walkable'},footprint={0.6,0.6},height=1.9,offset=0},
}
Surfaces.KINDS=KINDS

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function r4(v) return math.floor(v*1e4+0.5)/1e4 end
local function vec(p,f)
    if type(p)~='table' then return f end
    local x,y,z=num(p.x or p[1]),num(p.y or p[2]),num(p.z or p[3],0)
    if not x or not y then return f end
    return {x=x,y=y,z=z}
end
local function add(a,b) return {x=a.x+b.x,y=a.y+b.y,z=a.z+b.z} end
local function sub(a,b) return {x=a.x-b.x,y=a.y-b.y,z=a.z-b.z} end
local function mul(a,s) return {x=a.x*s,y=a.y*s,z=a.z*s} end
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
local function cross(a,b) return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
local function len(a) return math.sqrt(dot(a,a)) end
local function unit(a) local l=len(a);if l<1e-9 then return nil end;return mul(a,1/l) end
local function round_vec(a) return {x=r4(a.x),y=r4(a.y),z=r4(a.z)} end
local UP={x=0,y=0,z=1}

-- Same convention as modules/procedural.lua: R = Rz(yaw) * Rx(pitch) * Ry(roll).
local function rotate(v,r)
    r=r or {}
    local cy,sy=math.cos(math.rad(r.yaw or 0)),math.sin(math.rad(r.yaw or 0))
    local cp,sp=math.cos(math.rad(r.pitch or 0)),math.sin(math.rad(r.pitch or 0))
    local cr,sr=math.cos(math.rad(r.roll or 0)),math.sin(math.rad(r.roll or 0))
    local x,y,z=v.x*cr+v.z*sr,v.y,-v.x*sr+v.z*cr
    y,z=y*cp-z*sp,y*sp+z*cp
    return {x=x*cy-y*sy,y=x*sy+y*cy,z=z}
end
local function unrotate(v,r)
    r=r or {}
    local cy,sy=math.cos(math.rad(r.yaw or 0)),math.sin(math.rad(r.yaw or 0))
    local cp,sp=math.cos(math.rad(r.pitch or 0)),math.sin(math.rad(r.pitch or 0))
    local cr,sr=math.cos(math.rad(r.roll or 0)),math.sin(math.rad(r.roll or 0))
    local x,y,z=v.x*cy+v.y*sy,-v.x*sy+v.y*cy,v.z
    y,z=y*cp+z*sp,-y*sp+z*cp
    return {x=x*cr-z*sr,y=y,z=x*sr+z*cr}
end
Surfaces.rotate=rotate

local function orientation(n) if n.z>0.7 then return 'up' elseif n.z< -0.7 then return 'down' end;return 'side' end
Surfaces.orientation=orientation

-- u axis for a normal: horizontal and to the right when looking at a vertical face,
-- so that v = n x u points up; for horizontal faces the given hint (object x).
local function u_for(n,hint)
    if math.abs(n.z)<0.99 then return unit(cross(UP,n)) end
    local h=hint and unit({x=hint.x,y=hint.y,z=0}) or {x=1,y=0,z=0}
    return h
end

function Surfaces.check_tag(tag)
    if type(tag)~='string' or #tag>40 or not tag:match(TAG_PATTERN) then return nil,'surface tag must be lowercase letters, digits and underscores (max 40), starting with a letter: '..tostring(tag) end
    return tag
end
local function check_traits(list,label)
    if list==nil then return {} end
    if type(list)=='string' then list={list} end
    if type(list)~='table' then return nil,(label or 'traits')..' must be a list of names' end
    local out,seen={},{}
    for _,t in ipairs(list) do
        local ok,err=Surfaces.check_tag(t);if not ok then return nil,(label or 'traits')..': '..err end
        if not seen[t] then seen[t]=true;out[#out+1]=t end
    end
    return out
end

-- A surface from a centre, normal and the four corner points (projected onto u/v).
local function face(tag,traits,center,normal,corners,uhint,poly)
    local n=unit(normal);if not n then return nil end
    local u=u_for(n,uhint);local v=cross(n,u)
    local hu,hv=0,0
    for _,c in ipairs(corners or {}) do local d=sub(c,center);hu=math.max(hu,math.abs(dot(d,u)));hv=math.max(hv,math.abs(dot(d,v))) end
    local s={tag=tag,traits=traits,center=round_vec(center),normal=round_vec(n),u=round_vec(u),size={u=r4(2*hu),v=r4(2*hv)}}
    if poly then
        local p={};for i,q in ipairs(poly) do local d=sub(q,center);p[i]={r4(dot(d,u)),r4(dot(d,v))} end
        s.poly=p
    end
    return s
end

local function area(s)
    if s.poly then
        local a=0;local p=s.poly
        for i=1,#p do local j=i%#p+1;a=a+p[i][1]*p[j][2]-p[j][1]*p[i][2] end
        return math.abs(a)/2
    end
    return s.size.u*s.size.v
end
Surfaces.area=area

-- Faces of one part, keyed top/bottom/px/nx/py/ny/slope.
local BOX_FACES={
    top={n={x=0,y=0,z=1},a={x=1,y=0,z=0},b={x=0,y=1,z=0},ka='x',kb='y',kd='z'},
    bottom={n={x=0,y=0,z=-1},a={x=1,y=0,z=0},b={x=0,y=1,z=0},ka='x',kb='y',kd='z'},
    px={n={x=1,y=0,z=0},a={x=0,y=1,z=0},b={x=0,y=0,z=1},ka='y',kb='z',kd='x'},
    nx={n={x=-1,y=0,z=0},a={x=0,y=1,z=0},b={x=0,y=0,z=1},ka='y',kb='z',kd='x'},
    py={n={x=0,y=1,z=0},a={x=1,y=0,z=0},b={x=0,y=0,z=1},ka='x',kb='z',kd='y'},
    ny={n={x=0,y=-1,z=0},a={x=1,y=0,z=0},b={x=0,y=0,z=1},ka='x',kb='z',kd='y'},
}
local function part_face(part,key)
    local rot=part.rotation or {}
    if part.shape=='box' or (part.shape=='wedge' and key~='top' and key~='slope') then
        local f=BOX_FACES[key];if not f then return nil end
        if part.shape=='wedge' and key~='bottom' and key~='ny' then return nil end
        local h={x=part.size.x/2,y=part.size.y/2,z=part.size.z/2}
        local c=add(part.center,rotate(mul(f.n,h[f.kd]),rot))
        local a,b=rotate(mul(f.a,h[f.ka]),rot),rotate(mul(f.b,h[f.kb]),rot)
        local corners={add(add(c,a),b),add(sub(c,a),b),sub(add(c,a),b),sub(sub(c,a),b)}
        return c,rotate(f.n,rot),corners,rotate({x=1,y=0,z=0},rot)
    elseif part.shape=='wedge' then
        -- The sloped face rises from (y=-sy/2, z=-sz/2) to (y=+sy/2, z=+sz/2).
        local h={x=part.size.x/2,y=part.size.y/2,z=part.size.z/2}
        local n=rotate(unit({x=0,y=-part.size.z,z=part.size.y}),rot)
        local pts={{x=-h.x,y=-h.y,z=-h.z},{x=h.x,y=-h.y,z=-h.z},{x=h.x,y=h.y,z=h.z},{x=-h.x,y=h.y,z=h.z}}
        local corners={};for i,p in ipairs(pts) do corners[i]=add(part.center,rotate(p,rot)) end
        return part.center,n,corners,rotate({x=1,y=0,z=0},rot)
    elseif part.shape=='prism' and (key=='top' or key=='bottom') then
        local z=key=='top' and part.z1 or part.z0
        local lo,hi={x=math.huge,y=math.huge},{x=-math.huge,y=-math.huge}
        local poly={}
        for i,q in ipairs(part.points) do lo.x=math.min(lo.x,q.x);lo.y=math.min(lo.y,q.y);hi.x=math.max(hi.x,q.x);hi.y=math.max(hi.y,q.y);poly[i]={x=q.x,y=q.y,z=z} end
        local c={x=(lo.x+hi.x)/2,y=(lo.y+hi.y)/2,z=z}
        return c,{x=0,y=0,z=key=='top' and 1 or -1},{{x=lo.x,y=lo.y,z=z},{x=hi.x,y=hi.y,z=z}},nil,poly
    elseif part.shape=='cylinder' and (key=='top' or key=='bottom') then
        -- Caps of an upright cylinder (cylinders run along local +Y).
        local axis=rotate({x=0,y=1,z=0},rot)
        if math.abs(axis.z)<0.99 then return nil end
        local sign=(key=='top')==(axis.z>0) and 1 or -1
        local c=add(part.center,mul(axis,sign*part.length/2))
        local n={x=0,y=0,z=key=='top' and 1 or -1}
        local poly={};local sides=math.max(6,math.min(32,math.floor(num(part.sides,12))))
        for i=1,sides do local t=2*math.pi*(i-1)/sides;poly[i]={x=c.x+part.radius*math.cos(t),y=c.y+part.radius*math.sin(t),z=c.z} end
        return c,n,{{x=c.x-part.radius,y=c.y-part.radius,z=c.z},{x=c.x+part.radius,y=c.y+part.radius,z=c.z}},nil,poly
    end
    return nil
end

-- Is point p inside a part (used to drop faces hidden under other parts)?
local function inside(part,p)
    if part.shape=='box' then
        local d=unrotate(sub(p,part.center),part.rotation)
        return math.abs(d.x)<part.size.x/2-1e-4 and math.abs(d.y)<part.size.y/2-1e-4 and math.abs(d.z)<part.size.z/2-1e-4
    elseif part.shape=='prism' then
        if p.z<=part.z0+1e-4 or p.z>=part.z1-1e-4 then return false end
        local c=false;local pts=part.points
        for i=1,#pts do local a,b=pts[i],pts[i%#pts+1]
            if (a.y>p.y)~=(b.y>p.y) and p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x then c=not c end end
        return c
    elseif part.shape=='cylinder' then
        local d=unrotate(sub(p,part.center),part.rotation)
        return math.abs(d.y)<part.length/2-1e-4 and d.x*d.x+d.z*d.z<(part.radius-1e-4)^2
    elseif part.shape=='sphere' then
        local d=sub(p,part.center);return dot(d,d)<(part.radius-1e-4)^2
    elseif part.shape=='wedge' then
        local d=unrotate(sub(p,part.center),part.rotation);local h=part.size
        if math.abs(d.x)>=h.x/2 or math.abs(d.y)>=h.y/2 or d.z<=-h.z/2 then return false end
        return d.z<-h.z/2+h.z*(d.y+h.y/2)/h.y
    end
    return false
end

local ANNOTATION_KEYS={top=true,bottom=true,px=true,nx=true,py=true,ny=true,slope=true,sides=true,traits=true}

-- Normalize a part annotation: string -> {top=tag}.
local function annotation(value,i)
    if value==nil then return nil end
    if type(value)=='string' then value={top=value} end
    if type(value)~='table' then return nil,'part '..i..': surface must be a tag or {top, bottom, sides, px, nx, py, ny, slope, traits}' end
    local out={}
    for k,v in pairs(value) do
        if not ANNOTATION_KEYS[k] then return nil,'part '..i..': unknown surface key '..tostring(k) end
        if k=='traits' then local t,err=check_traits(v,'part '..i..' surface traits');if not t then return nil,err end;out.traits=t
        elseif v~=false and v~='' then local ok,err=Surfaces.check_tag(v);if not ok then return nil,'part '..i..': '..err end;out[k]=v end
    end
    if out.sides then for _,k in ipairs({'px','nx','py','ny'}) do out[k]=out[k] or out.sides end;out.sides=nil end
    if out.slope then out.top=out.top or out.slope;out.slope=nil end
    return out
end

-- Object-level surface option: string tag or {tag, traits, retag}.
function Surfaces.normalize_option(value)
    if value==nil or value==false or value=='' then return nil end
    if type(value)=='string' then value={tag=value} end
    if type(value)~='table' then return nil,'surface must be a tag or {tag, traits, retag}' end
    local out={}
    if value.tag~=nil and value.tag~=false and value.tag~='' then local ok,err=Surfaces.check_tag(value.tag);if not ok then return nil,err end;out.tag=value.tag end
    local t,err=check_traits(value.traits);if not t then return nil,err end;if #t>0 then out.traits=t end
    if value.retag~=nil then
        if type(value.retag)~='table' then return nil,'surface.retag must map tags to tags' end
        out.retag={}
        for from,to in pairs(value.retag) do
            local ok;ok,err=Surfaces.check_tag(from);if not ok then return nil,'surface.retag: '..err end
            if to~=false then ok,err=Surfaces.check_tag(to);if not ok then return nil,'surface.retag: '..err end end
            out.retag[from]=to
        end
    end
    if next(out)==nil then return nil end
    return out
end

-- Explicit surface rectangles: {tag, center, size [u, v], normal | orientation, yaw, traits, poly}.
function Surfaces.normalize_explicit(list,label)
    label=label or 'surfaces'
    if list==nil then return {} end
    if type(list)~='table' then return nil,label..' must be a list' end
    local out={}
    for i,s in ipairs(list) do
        if type(s)~='table' then return nil,label..' '..i..' must be an object' end
        local tag,err=Surfaces.check_tag(s.tag);if not tag then return nil,label..' '..i..': '..err end
        local traits;traits,err=check_traits(s.traits,label..' '..i..' traits');if not traits then return nil,err end
        local c=vec(s.center);if not c then return nil,label..' '..i..' needs a center [x, y, z]' end
        local sz=s.size;local su,sv
        if type(sz)=='table' then su,sv=num(sz.u or sz.x or sz[1]),num(sz.v or sz.y or sz[2]) end
        if not su or not sv or su<=0 or sv<=0 then return nil,label..' '..i..' needs a positive size [u, v]' end
        local n
        if s.normal~=nil then n=vec(s.normal);n=n and unit(n);if not n then return nil,label..' '..i..' has an invalid normal' end
        else
            local o=s.orientation or (TAGS[tag] and TAGS[tag].o) or 'up'
            local yaw=math.rad(num(s.yaw,0))
            if o=='up' then n={x=0,y=0,z=1} elseif o=='down' then n={x=0,y=0,z=-1}
            elseif o=='side' then n={x=-math.sin(yaw),y=math.cos(yaw),z=0}
            else return nil,label..' '..i..': orientation must be up, down or side' end
        end
        local hint;if math.abs(n.z)>=0.99 then local yaw=math.rad(num(s.yaw,0));hint={x=math.cos(yaw),y=math.sin(yaw),z=0} end
        local u=u_for(n,hint)
        local given=s.u~=nil and vec(s.u)
        if given then local g=sub(given,mul(n,dot(given,n)));g=unit(g);if not g then return nil,label..' '..i..': u must not be parallel to the normal' end;u=g end
        local rec={tag=tag,traits=traits,center=round_vec(c),normal=round_vec(n),u=round_vec(u),size={u=r4(su),v=r4(sv)}}
        if s.poly~=nil then
            if type(s.poly)~='table' or #s.poly<3 then return nil,label..' '..i..': poly needs 3+ [u, v] points' end
            rec.poly={}
            for j,q in ipairs(s.poly) do local a,b=num(type(q)=='table' and (q.u or q[1])),num(type(q)=='table' and (q.v or q[2]));if not a or not b then return nil,label..' '..i..': poly point '..j..' must be [u, v]' end;rec.poly[j]={r4(a),r4(b)} end
        end
        out[#out+1]=rec
    end
    return out
end

local function merge_traits(a,b)
    if (not a or #a==0) and (not b or #b==0) then return nil end
    local out,seen={},{}
    for _,list in ipairs({a or {},b or {}}) do for _,t in ipairs(list) do if not seen[t] then seen[t]=true;out[#out+1]=t end end end
    return out
end

-- Surfaces of a generated part list.
-- opts: option (normalized object option), explicit (normalized list).
-- Returns list, warnings.
function Surfaces.from_parts(parts,opts)
    opts=opts or {}
    local option=opts.option or {}
    local out,warnings={},{}
    local default=option.tag
    local check_hidden=#parts<=300
    for i,part in ipairs(parts or {}) do
        local ann,err=annotation(part.surface,i);if err then return nil,err end
        local keys={}
        if ann then for _,k in ipairs({'top','bottom','px','nx','py','ny'}) do if ann[k] then keys[#keys+1]={k,ann[k],ann.traits} end end end
        local annotated_top=ann and ann.top
        if default and not annotated_top and part.material~='glass' then keys[#keys+1]={'top',default,nil,true} end
        for _,entry in ipairs(keys) do
            local key,tag,traits,implicit=entry[1],entry[2],entry[3],entry[4]
            local c,n,corners,uhint,poly=part_face(part,key)
            if c then
                local nn=unit(n)
                -- An implicit (object-level) tag only goes on faces that face up.
                if not implicit or (nn and nn.z>0.5) then
                    local hidden=false
                    if check_hidden and implicit then
                        local probe=add(c,mul(nn,0.02))
                        for j,other in ipairs(parts) do if j~=i and inside(other,probe) then hidden=true;break end end
                    end
                    if not hidden then
                        if option.retag and option.retag[tag]~=nil then tag=option.retag[tag] end
                        if tag then
                            local s=face(tag,merge_traits(traits,option.traits),c,n,corners,uhint,poly)
                            if s and area(s)>=MIN_AREA then s.part=i;out[#out+1]=s end
                        end
                    end
                end
            end
        end
    end
    for _,s in ipairs(opts.explicit or {}) do
        local tag=s.tag
        if option.retag and option.retag[tag]~=nil then tag=option.retag[tag] end
        if tag then local q=Util.deepcopy(s);q.tag=tag;q.traits=merge_traits(q.traits,option.traits);out[#out+1]=q end
    end
    for _,s in ipairs(out) do if s.traits and #s.traits==0 then s.traits=nil end end
    if #out>MAX_PER_OBJECT then
        table.sort(out,function(a,b) return area(a)>area(b) end)
        warnings[#warnings+1]=#out..' surfaces; kept the '..MAX_PER_OBJECT..' largest'
        for k=#out,MAX_PER_OBJECT+1,-1 do out[k]=nil end
    end
    return out,warnings
end

function Surfaces.summary(list)
    local by={};local total=0
    for _,s in ipairs(list or {}) do by[s.tag]=(by[s.tag] or 0)+1;total=total+1 end
    return {count=total,by_tag=by}
end

---------------------------------------------------------------------------
-- World space, matching and sampling (pure)
---------------------------------------------------------------------------

-- A local surface in world space for a transform {position, rotation}.
function Surfaces.to_world(s,transform,extra)
    local p=transform and transform.position or {x=0,y=0,z=0};local r=transform and transform.rotation or {}
    local c=add({x=num(p.x,0),y=num(p.y,0),z=num(p.z,0)},rotate(s.center,r))
    local n=rotate(s.normal,r);local u=rotate(s.u,r)
    local w={tag=s.tag,traits=s.traits and Util.deepcopy(s.traits) or nil,center=round_vec(c),normal=round_vec(n),u=round_vec(u),size={u=s.size.u,v=s.size.v},
        poly=s.poly and Util.deepcopy(s.poly) or nil,orientation=orientation(n)}
    w.area=r4(area(w))
    for k,v in pairs(extra or {}) do w[k]=v end
    return w
end

local function list_of(v) if v==nil then return nil end;if type(v)=='string' then return {v} end;return v end

-- Does a (world) surface match a filter: tags (tag, group or trait; any), traits (all),
-- exclude_tags, orientation, min_area, min_size.
function Surfaces.matches(s,f)
    f=f or {}
    local groups=TAGS[s.tag] and TAGS[s.tag].is or {}
    local function has(name)
        if s.tag==name then return true end
        for _,g in ipairs(groups) do if g==name then return true end end
        for _,t in ipairs(s.traits or {}) do if t==name then return true end end
        return false
    end
    local tags=list_of(f.tags or f.tag)
    if tags and #tags>0 then local any=false;for _,t in ipairs(tags) do if has(t) then any=true;break end end;if not any then return false end end
    for _,t in ipairs(list_of(f.traits or f.trait) or {}) do if not has(t) then return false end end
    for _,t in ipairs(list_of(f.exclude_tags or f.exclude) or {}) do if has(t) then return false end end
    local o=list_of(f.orientation)
    if o and #o>0 then local any=false;for _,v in ipairs(o) do if v==s.orientation then any=true end end;if not any then return false end end
    if f.min_area and (s.area or area(s))<num(f.min_area,0) then return false end
    if f.min_size and math.min(s.size.u,s.size.v)<num(f.min_size,0) then return false end
    return true
end

local function contains_poly(poly,a,b)
    local c=false
    for i=1,#poly do local p,q=poly[i],poly[i%#poly+1]
        if (p[2]>b)~=(q[2]>b) and a<(q[1]-p[1])*(b-p[2])/(q[2]-p[2])+p[1] then c=not c end end
    return c
end
-- Point (world) inside a surface's outline, shrunk by `inset` (rectangles only).
local function contains(s,p,inset)
    inset=inset or 0
    local d=sub(p,s.center);local v=cross(s.normal,s.u)
    local a,b=dot(d,s.u),dot(d,v)
    if math.abs(a)>s.size.u/2-inset+1e-6 or math.abs(b)>s.size.v/2-inset+1e-6 then return false end
    if s.poly then return contains_poly(s.poly,a,b) end
    return true
end
Surfaces.contains=contains

-- Deterministic RNG (Park-Miller) seeded from a string.
local function hash(str) local h=5381;for i=1,#str do h=(h*33+str:byte(i))%2147483647 end;return h==0 and 1 or h end
local function rng(seed)
    local state=hash(tostring(seed))
    return function(lo,hi) state=(state*16807)%2147483647;local t=state/2147483647;if lo then return lo+(hi-lo)*t end;return t end
end
Surfaces.rng=rng

local function facing(n) return math.deg(math.atan2(-n.x,n.y)) end
local function wrap(a) a=a%360;if a>180 then a=a-360 end;return r4(a) end
local function heading(u) return math.deg(math.atan2(u.y,u.x)) end

-- Placement options, with the kind's defaults filled in.
function Surfaces.placement_options(args)
    args=args or {}
    local kind=args.kind or 'asset'
    local k=KINDS[kind];if not k then return nil,'kind must be one of asset, procedural, decal, light, effect, marker' end
    local o={kind=kind}
    o.tags=list_of(args.tags or args.tag) or k.tags
    o.traits=list_of(args.traits or args.trait);o.exclude_tags=list_of(args.exclude_tags or args.exclude)
    o.orientation=args.orientation;o.min_area=args.min_area;o.min_size=args.min_size
    local fp=args.footprint;local fx,fy
    if type(fp)=='table' then fx,fy=num(fp.x or fp[1]),num(fp.y or fp[2]) elseif fp~=nil then fx=num(fp);fy=fx end
    o.footprint={x=fx or k.footprint[1],y=fy or fx or k.footprint[2]}
    if o.footprint.x<=0 or o.footprint.y<=0 or o.footprint.x>50 or o.footprint.y>50 then return nil,'footprint must be between 0 and 50 m' end
    o.height=num(args.height,k.height);if o.height<0 then return nil,'height must be >= 0' end
    o.offset=num(args.offset,k.offset)
    o.margin=num(args.margin,0.05);if o.margin<0 then return nil,'margin must be >= 0' end
    o.pattern=args.pattern or k.pattern or 'random'
    if o.pattern~='random' and o.pattern~='grid' and o.pattern~='line' and o.pattern~='center' then return nil,'pattern must be random, grid, line or center' end
    o.count=args.count~=nil and math.floor(num(args.count,0)) or nil
    o.per_surface=args.per_surface~=nil and math.floor(num(args.per_surface,0)) or nil
    o.density=args.density~=nil and num(args.density,0) or nil
    o.spacing=num(args.spacing,k.spacing or math.max(o.footprint.x,o.footprint.y)*2)
    if o.spacing<0.05 then return nil,'spacing must be at least 0.05 m' end
    if o.count and o.count<0 or o.per_surface and o.per_surface<0 or o.density and o.density<0 then return nil,'count, per_surface and density must be >= 0' end
    if o.pattern=='random' and not o.count and not o.per_surface and not o.density then o.per_surface=1 end
    o.max=math.min(MAX_PLACEMENTS,math.floor(num(args.max,MAX_PLACEMENTS)))
    o.min_distance=num(args.min_distance,math.max(o.footprint.x,o.footprint.y))
    o.seed=args.seed~=nil and tostring(args.seed) or 'surfaces'
    o.yaw=args.yaw==nil and 'align' or args.yaw
    if o.yaw~='align' and o.yaw~='random' and not num(o.yaw) then return nil,'yaw must be align, random or a number of degrees' end
    o.yaw_step=num(args.yaw_step,0);o.yaw_offset=num(args.yaw_offset,0)
    o.elevation=args.elevation~=nil and num(args.elevation) or k.elevation
    o.avoid=args.avoid_objects==nil and k.avoid~=false or args.avoid_objects==true
    o.clearance=args.check_clearance==nil and o.height>0 or args.check_clearance==true
    return o
end

-- Candidate points on one surface, in (a, b) surface coordinates.
local function candidates(s,o,rand)
    local hu,hv=s.size.u/2,s.size.v/2
    local side=s.orientation=='side'
    -- Inset: half the footprint (along the surface) plus the margin.
    local iu=o.footprint.x/2+o.margin
    local iv=side and o.margin or o.footprint.y/2+o.margin
    if not side and s.orientation=='up' then iv=o.footprint.y/2+o.margin end
    local ua,ub=-hu+iu,hu-iu
    local va,vb=-hv+iv,hv-iv
    if side then
        -- On walls, items sit at an elevation above the bottom edge (or anywhere that fits).
        local top=hv-o.margin-(o.height>0 and o.height or o.footprint.y)/2
        local bottom=-hv+o.margin+(o.height>0 and o.height or o.footprint.y)/2
        if o.elevation then local b=-hv+o.elevation;va,vb=b,b;if b<bottom-1e-6 or b>top+1e-6 then return {} end else va,vb=bottom,top end
    end
    if ua>ub+1e-9 or va>vb+1e-9 then return {} end
    local out={}
    if o.pattern=='center' then out[1]={(ua+ub)/2,(va+vb)/2}
    elseif o.pattern=='line' or o.pattern=='grid' then
        local function fit(a,b)
            local L=b-a;if L<1e-6 then return {(a+b)/2} end
            local n=math.min(200,math.max(1,math.floor(L/o.spacing+0.5)+1))
            if n==1 then return {(a+b)/2} end
            local r={};for i=0,n-1 do r[#r+1]=a+L*i/(n-1) end;return r
        end
        local us=fit(ua,ub)
        local vs=(o.pattern=='line' or side and o.elevation) and {(va+vb)/2} or fit(va,vb)
        for _,a in ipairs(us) do for _,b in ipairs(vs) do out[#out+1]={a,b} end end
    else
        local n=o.per_surface or 0
        if o.density then n=math.floor(area(s)*o.density+0.5) end
        for _=1,n*20 do out[#out+1]={rand(ua,ub),rand(va,vb),random=true} end
        out.want=n
    end
    return out
end

local function yaw_for(s,o,rand)
    local base
    if s.orientation=='side' then base=facing(s.normal) else base=heading(s.u) end
    local y
    if o.yaw=='random' then y=rand(-180,180)
    elseif o.yaw=='align' then y=base
    else y=base+num(o.yaw,0) end
    if o.yaw_step>0 then y=y+o.yaw_step*math.floor(rand(0,360/o.yaw_step)) end
    return wrap(y+o.yaw_offset)
end

local function rotation_for(s,o,yaw)
    if o.kind=='decal' then
        -- Decals project along their local -Z: walls get pitch -90 (into the wall), ceilings roll 180.
        if s.orientation=='side' then return {roll=0,pitch=-90,yaw=yaw} end
        if s.orientation=='down' then return {roll=180,pitch=0,yaw=yaw} end
    end
    return {roll=0,pitch=0,yaw=yaw}
end

-- Place items on a pool of world surfaces.
-- pool: world surfaces (Surfaces.to_world, each with id); obstacles: {{min, max, owner}} world AABBs.
-- Returns {items, surfaces_matched, rejected={reason=n}}.
function Surfaces.sample_pool(pool,args,obstacles)
    local o,err=Surfaces.placement_options(args);if not o then return nil,err end
    local matched={}
    for _,s in ipairs(pool or {}) do if Surfaces.matches(s,o) then matched[#matched+1]=s end end
    table.sort(matched,function(a,b) return tostring(a.id)<tostring(b.id) end)
    local horizontal={};for _,s in ipairs(pool or {}) do if s.orientation~='side' then horizontal[#horizontal+1]=s end end
    local placed={};local rejected={};local attempts=0;local truncated=false
    local function reject(why) rejected[why]=(rejected[why] or 0)+1 end
    local function free(p,s)
        for _,q in ipairs(placed) do local d=sub(q.position,p);if d.x*d.x+d.y*d.y+d.z*d.z<o.min_distance*o.min_distance-1e-9 then return false,'spacing' end end
        if o.clearance and s.orientation=='up' then
            for _,t in ipairs(horizontal) do
                if t~=s and t.center.z>p.z+0.01 and t.center.z<p.z+o.height-1e-6 and contains(t,{x=p.x,y=p.y,z=t.center.z},0) then return false,'clearance' end
            end
        end
        if o.avoid and obstacles then
            local r=math.max(o.footprint.x,o.footprint.y)/2
            local lo,hi
            if s.orientation=='side' then
                lo={x=p.x-r,y=p.y-r,z=p.z-o.footprint.y/2};hi={x=p.x+r,y=p.y+r,z=p.z+o.footprint.y/2}
            elseif s.orientation=='down' then lo={x=p.x-r,y=p.y-r,z=p.z-o.height};hi={x=p.x+r,y=p.y+r,z=p.z-0.02}
            else lo={x=p.x-r,y=p.y-r,z=p.z+0.02};hi={x=p.x+r,y=p.y+r,z=p.z+math.max(o.height,0.05)} end
            for _,b in ipairs(obstacles) do
                if b.owner~=s.object_id and lo.x<b.max.x and hi.x>b.min.x and lo.y<b.max.y and hi.y>b.min.y and lo.z<b.max.z and hi.z>b.min.z then return false,'occupied' end
            end
        end
        return true
    end
    local function try(s,a,b,rand)
        attempts=attempts+1
        local v=cross(s.normal,s.u)
        local pt=add(add(s.center,mul(s.u,a)),mul(v,b))
        if s.poly and not contains_poly(s.poly,a,b) then reject('outline');return false end
        local p=add(pt,mul(s.normal,o.offset))
        local ok,why=free(p,s);if not ok then reject(why);return false end
        local yaw=yaw_for(s,o,rand)
        placed[#placed+1]={position=round_vec(p),rotation=rotation_for(s,o,yaw),normal=Util.deepcopy(s.normal),orientation=s.orientation,
            surface={id=s.id,tag=s.tag,traits=s.traits and Util.deepcopy(s.traits) or nil,object_id=s.object_id,room_id=s.room_id,premise_id=s.premise_id}}
        return true
    end
    if o.count then
        -- A total, spread over the surfaces by usable area.
        local rand=rng(o.seed..'|count')
        local weights,total={},0
        for i,s in ipairs(matched) do
            local w=math.max(0,s.size.u-o.footprint.x)
            if s.orientation~='side' then w=w*math.max(0,s.size.v-o.footprint.y) end
            weights[i]=w;total=total+w
        end
        local tries=0
        while #placed<math.min(o.count,o.max) and total>0 and tries<math.min(MAX_ATTEMPTS,o.count*60) do
            tries=tries+1
            local pick=rand(0,total);local s
            for i,w in ipairs(weights) do pick=pick-w;if pick<=0 and w>0 then s=matched[i];break end end
            s=s or matched[#matched]
            local cands=candidates(s,{kind=o.kind,footprint=o.footprint,margin=o.margin,height=o.height,elevation=o.elevation,pattern='random',per_surface=1,spacing=o.spacing},rand)
            if cands[1] then try(s,cands[1][1],cands[1][2],rand) end
        end
    else
        for _,s in ipairs(matched) do
            if #placed>=o.max then break end
            local rand=rng(o.seed..'|'..tostring(s.id))
            local cands=candidates(s,o,rand)
            local want=cands.want;local got=0
            for _,c in ipairs(cands) do
                if #placed>=o.max or (want and got>=want) then break end
                if attempts>=MAX_ATTEMPTS then truncated=true;break end
                if try(s,c[1],c[2],rand) then got=got+1 end
            end
            if truncated then break end
        end
    end
    return {items=placed,count=#placed,surfaces_matched=#matched,rejected=rejected,truncated=truncated or nil,options={kind=o.kind,tags=o.tags,traits=o.traits,pattern=o.pattern,footprint=o.footprint,height=o.height}}
end

-- The authoring-plan step that creates one placement.
local PASS={
    asset={'asset_id','asset_query','spawn','require_runtime','layer'},
    procedural={'generator','params','material','collision','collision_preset','layer','surface','surfaces'},
    decal={'resource_name','query','resource_path','alpha','auto_hide_distance','horizontal_flip','vertical_flip','spawn'},
    light={'config','preset_id','resource_name','spawn'},
    effect={'resource_path','resource_name','query','backend','scale','emission_rate','spawn'},
    marker={'type','category','tags','radius','notes'},
}
local OPS={asset='place_asset',procedural='create_procedural',decal='create_decal',light='create_light',effect='create_vfx',marker='create_location'}
-- What each kind needs besides the placement.
function Surfaces.check_kind(args)
    local kind=args.kind or 'asset'
    if not KINDS[kind] then return nil,'kind must be one of asset, procedural, decal, light, effect, marker' end
    if kind=='asset' and args.asset_id==nil and args.asset_query==nil then return nil,'asset placements need asset_id or asset_query' end
    if kind=='procedural' and type(args.generator)~='string' then return nil,'procedural placements need a generator' end
    if kind=='effect' and args.resource_path==nil and args.resource_name==nil and args.query==nil then return nil,'effect placements need resource_path, resource_name or query' end
    if kind=='decal' and args.resource_path==nil and args.resource_name==nil and args.query==nil then return nil,'decal placements need resource_path, resource_name or query' end
    return true
end
function Surfaces.step_for(p,args,index)
    local kind=args.kind or 'asset'
    local op=OPS[kind];if not op then return nil,'unknown kind '..tostring(kind) end
    local name=args.name and tostring(args.name):gsub('{i}',tostring(index)) or nil
    local step={op=op,name=name,premise_id=p.surface.premise_id,room_id=p.surface.room_id,
        transform={position={x=p.position.x,y=p.position.y,z=p.position.z,w=1},rotation=Util.deepcopy(p.rotation)}}
    for _,k in ipairs(PASS[kind]) do if args[k]~=nil then step[k]=Util.deepcopy(args[k]) end end
    if kind=='procedural' and step.collision==nil then step.collision=false end
    if kind=='decal' then
        -- The decal covers the footprint unless decal_width/decal_height say otherwise.
        local fp=args.footprint;local fx,fy
        if type(fp)=='table' then fx,fy=num(fp.x or fp[1]),num(fp.y or fp[2]) elseif fp~=nil then fx=num(fp) end
        step.width=num(args.decal_width,fx or 1);step.height=num(args.decal_height,fy or step.width)
    end
    if kind=='effect' and args.query and not args.resource_name then step.resource_name=args.query end
    if kind=='marker' then step.premise_id=nil;step.room_id=nil;step.type=step.type or 'spot';step.category=step.category or 'Surface spots' end
    if kind=='asset' and not step.asset_id and not step.asset_query then return nil,'asset placements need asset_id or asset_query' end
    if kind=='procedural' and not step.generator then return nil,'procedural placements need a generator' end
    return step
end

---------------------------------------------------------------------------
-- Project surfaces (instance)
---------------------------------------------------------------------------
function Surfaces.new(app) return setmetatable({app=app},Surfaces) end

function Surfaces:vocabulary()
    local tags={}
    for name,t in pairs(TAGS) do tags[#tags+1]={tag=name,orientation=t.o,groups=Util.deepcopy(t.is),hint=t.hint} end
    table.sort(tags,function(a,b) return a.tag<b.tag end)
    local groups={};for name,d in pairs(GROUPS) do groups[#groups+1]={group=name,hint=d} end
    table.sort(groups,function(a,b) return a.group<b.group end)
    local kinds={};for name,k in pairs(KINDS) do kinds[#kinds+1]={kind=name,tags=Util.deepcopy(k.tags),footprint=Util.deepcopy(k.footprint),height=k.height,offset=k.offset,pattern=k.pattern or 'random'} end
    table.sort(kinds,function(a,b) return a.kind<b.kind end)
    return {tags=tags,groups=groups,kinds=kinds,custom_tags='any lowercase name ([a-z][a-z0-9_]*) is accepted as a custom tag'}
end

-- Local surfaces of an object: derived (generated geometry) and hand-tagged.
function Surfaces:local_surfaces(o)
    local out={}
    local cfg=o and o.metadata and o.metadata.procedural
    for i,s in ipairs(cfg and cfg.surfaces or {}) do local q=Util.deepcopy(s);q.source='generated';q.index=i;out[#out+1]=q end
    for i,s in ipairs(o and o.metadata and o.metadata.surfaces or {}) do local q=Util.deepcopy(s);q.source='manual';q.index=i;out[#out+1]=q end
    return out
end

-- World surfaces of the project, filtered by premise_id, room_id, object_ids.
function Surfaces:collect(f)
    f=f or {}
    local ids;if type(f.object_ids)=='table' then ids={};for _,id in ipairs(f.object_ids) do ids[id]=true end end
    local rooms;if type(f.room_ids)=='table' then rooms={};for _,id in ipairs(f.room_ids) do rooms[id]=true end end
    local pool={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local keep=o.enabled~=false and (not f.premise_id or f.premise_id=='' or o.premise_id==f.premise_id) and (not f.room_id or f.room_id=='' or o.room_id==f.room_id)
        if keep and (ids or rooms) then keep=(ids and ids[o.id]) or (rooms and o.room_id and rooms[o.room_id]) or false end
        if keep then
            for _,s in ipairs(self:local_surfaces(o)) do
                local w=Surfaces.to_world(s,o.transform,{object_id=o.id,object_name=o.name,room_id=o.room_id,premise_id=o.premise_id,source=s.source,
                    id=o.id..(s.source=='manual' and ':m' or ':')..s.index})
                pool[#pool+1]=w
            end
        end
    end
    return pool
end

function Surfaces:query(args)
    args=args or {}
    local pool=self:collect(args)
    local rows={}
    for _,s in ipairs(pool) do if Surfaces.matches(s,args) then rows[#rows+1]=s end end
    local limit=math.floor(num(args.limit,200))
    local summary=Surfaces.summary(rows)
    local items={};for i=1,math.min(#rows,limit) do items[i]=rows[i] end
    return {items=items,count=#rows,truncated=#rows>limit or nil,by_tag=summary.by_tag}
end

function Surfaces:object(object_id)
    local o=self.app.model:get_object(object_id);if not o then return nil,'object not found: '..tostring(object_id) end
    local rows=self:collect({object_ids={o.id}})
    return {object_id=o.id,name=o.name,items=rows,count=#rows,by_tag=Surfaces.summary(rows).by_tag}
end

-- World AABBs of placed objects that placements must not overlap (room shells,
-- colliders and decals excluded; objects without bounds count as a 0.4 m box).
function Surfaces:obstacles(f)
    local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local md=o.metadata or {}
        local skip=o.enabled==false or md.room_generator or md.collision_gen or md.collision or o.kind=='decal' or o.kind=='collision'
        if not skip and (not f.premise_id or f.premise_id=='' or o.premise_id==f.premise_id) then
            local box
            if self.app.bounds_gen and md.procedural then box=self.app.bounds_gen:world_aabb(o)
            elseif self.app.asset_bounds and type(md.asset_bounds)=='table' then local r=self.app.asset_bounds:world_aabb(o.id);box=r and r.aabb end
            -- Without bounds an object still takes a small space at its pivot.
            if not box and o.transform and o.transform.position then
                local p=o.transform.position;local x,y,z=num(p.x,0),num(p.y,0),num(p.z,0)
                local lit=md.light~=nil or o.kind=='light'
                box={min={x=x-0.2,y=y-0.2,z=lit and z-0.2 or z},max={x=x+0.2,y=y+0.2,z=z+(lit and 0.2 or 0.4)}}
            end
            if box then out[#out+1]={min=box.min,max=box.max,owner=o.id} end
        end
    end
    return out
end

function Surfaces:sample(args)
    args=args or {}
    local pool=self:collect(args)
    local obstacles=args.avoid_objects~=false and self:obstacles(args) or nil
    return Surfaces.sample_pool(pool,args,obstacles)
end

function Surfaces:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

-- Place items on matching surfaces as one authoring plan (one undo step, full rollback on failure).
-- dry_run returns the placements only.
function Surfaces:populate(args)
    args=args or {}
    local ok,err=Surfaces.check_kind(args);if not ok then return nil,err end
    local sample;sample,err=self:sample(args);if not sample then return nil,err end
    if args.dry_run==true then sample.dry_run=true;return sample end
    if sample.count==0 then
        local why={};for k,v in pairs(sample.rejected) do why[#why+1]=k..' '..v end;table.sort(why)
        return nil,'no placements: '..sample.surfaces_matched..' matching surface(s)'..(#why>0 and ('; rejected: '..table.concat(why,', ')) or '')
    end
    local busy=self:_busy();if busy then return nil,busy end
    local steps={}
    for i,p in ipairs(sample.items) do local step,serr=Surfaces.step_for(p,args,i);if not step then return nil,serr end;steps[#steps+1]=step end
    local first=sample.items[1].position
    local plan={format='locationstudio-authoring-plan',version=2,name=args.label or ('Populate '..tostring(args.kind or 'asset')..' on surfaces'),
        origin={position={x=first.x,y=first.y,z=first.z,w=1},rotation={roll=0,pitch=0,yaw=0}},steps=steps}
    local result;result,err=self.app.authoring_plans:execute(plan)
    if not result then return nil,err end
    local ids={};for _,out in ipairs(result.outputs or {}) do ids[#ids+1]=out.id end
    return {created=#ids,object_ids=ids,surfaces_matched=sample.surfaces_matched,rejected=sample.rejected,one_undo=true}
end

-- Tag an object by hand from its bounds: face top | bottom | front | back | left | right.
local FACES={top={n={x=0,y=0,z=1}},bottom={n={x=0,y=0,z=-1}},front={n={x=0,y=1,z=0}},back={n={x=0,y=-1,z=0}},right={n={x=1,y=0,z=0}},left={n={x=-1,y=0,z=0}}}
function Surfaces:tag(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local model=self.app.model
    local o=model:get_object(args.object_id);if not o then return nil,'object not found: '..tostring(args.object_id) end
    if o.locked then return nil,'object is locked' end
    local list
    if args.surfaces~=nil then
        local err;list,err=Surfaces.normalize_explicit(args.surfaces);if not list then return nil,err end
    else
        local tag,err=Surfaces.check_tag(args.tag);if not tag then return nil,err end
        local traits;traits,err=check_traits(args.traits);if not traits then return nil,err end
        local f=FACES[args.face or 'top'];if not f then return nil,'face must be top, bottom, front, back, left or right' end
        local b=o.metadata and o.metadata.asset_bounds
        if type(b)~='table' or type(b.min)~='table' or type(b.max)~='table' then return nil,'the object has no bounds; import asset bounds first or pass explicit surfaces' end
        local lo,hi=vec(b.min),vec(b.max);if not lo or not hi then return nil,'the object bounds are invalid' end
        local inset=num(args.inset,0)
        local c={x=(lo.x+hi.x)/2,y=(lo.y+hi.y)/2,z=(lo.z+hi.z)/2}
        local h={x=(hi.x-lo.x)/2,y=(hi.y-lo.y)/2,z=(hi.z-lo.z)/2}
        local n=f.n
        local fc={x=c.x+n.x*h.x,y=c.y+n.y*h.y,z=c.z+n.z*h.z}
        if args.height~=nil and (args.face or 'top')=='top' then fc.z=lo.z+num(args.height,h.z*2) end
        -- The face's corners: the other two axes at their extremes, on the face plane.
        local corners={}
        for _,sa in ipairs({-1,1}) do for _,sb in ipairs({-1,1}) do
            local p={x=fc.x,y=fc.y,z=fc.z}
            if n.x~=0 then p.y=c.y+sa*h.y;p.z=c.z+sb*h.z elseif n.y~=0 then p.x=c.x+sa*h.x;p.z=c.z+sb*h.z else p.x=c.x+sa*h.x;p.y=c.y+sb*h.y end
            corners[#corners+1]=p
        end end
        local s=face(tag,traits,fc,n,corners,{x=1,y=0,z=0})
        s.size.u=r4(math.max(0.01,s.size.u-2*inset));s.size.v=r4(math.max(0.01,s.size.v-2*inset))
        if #traits==0 then s.traits=nil end
        list={s}
    end
    local existing=args.replace~=true and o.metadata and type(o.metadata.surfaces)=='table' and #o.metadata.surfaces or 0
    if existing+#list>MAX_PER_OBJECT then return nil,'an object can have at most '..MAX_PER_OBJECT..' hand-tagged surfaces' end
    model:snapshot('Tag surfaces')
    o.metadata=o.metadata or {}
    if args.replace==true or type(o.metadata.surfaces)~='table' then o.metadata.surfaces={} end
    for _,s in ipairs(list) do o.metadata.surfaces[#o.metadata.surfaces+1]=s end
    model:touch();self.app:mark_dirty()
    return self:object(o.id)
end

function Surfaces:untag(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local model=self.app.model
    local o=model:get_object(args.object_id);if not o then return nil,'object not found: '..tostring(args.object_id) end
    if o.locked then return nil,'object is locked' end
    local list=o.metadata and o.metadata.surfaces
    if type(list)~='table' or #list==0 then return nil,'the object has no hand-tagged surfaces' end
    local kept,removed={},0
    for _,s in ipairs(list) do if args.tag and s.tag~=args.tag then kept[#kept+1]=s else removed=removed+1 end end
    if removed==0 then return nil,'no hand-tagged surface with tag '..tostring(args.tag) end
    model:snapshot('Remove surface tags')
    o.metadata.surfaces=#kept>0 and kept or nil
    model:touch();self.app:mark_dirty()
    return {object_id=o.id,removed=removed}
end

-- Recompute derived surfaces of procedural objects and generated rooms (for projects
-- made before surfaces existed). Geometry is not rebuilt. One undo step.
function Surfaces:refresh(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local model=self.app.model
    local P=package.loaded['modules/procedural'] or require('modules/procedural')
    local RG=package.loaded['modules/room_generator'] or require('modules/room_generator')
    model:snapshot('Refresh semantic surfaces')
    local updated,failed=0,{}
    local room_plans={}
    for _,rec in ipairs(model.data.generated_rooms or {}) do local plan=RG.plan(rec.spec);if plan then room_plans[rec.id]=plan end end
    for _,o in ipairs(model.data.objects or {}) do
        local cfg=o.metadata and o.metadata.procedural
        if cfg and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) then
            local params=Util.deepcopy(cfg.params or {})
            local rg=o.metadata.room_generator
            if rg and room_plans[rg.room_id] then params.surfaces=room_plans[rg.room_id].surfaces[rg.role] end
            local info,err=P.generate(cfg.generator,params,cfg.surface)
            if info then
                cfg.surfaces=info.surfaces;updated=updated+1
                if rg then cfg.params.surfaces=params.surfaces end
            else failed[#failed+1]={id=o.id,error=err} end
        end
    end
    model:touch();self.app:mark_dirty()
    return {updated=updated,failed=failed}
end

return Surfaces
