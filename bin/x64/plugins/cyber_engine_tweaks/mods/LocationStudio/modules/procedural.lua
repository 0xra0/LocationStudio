local Util=require('modules/util')
local Csg=require('modules/csg')

-- Procedural geometry. Generators turn dimensions and parameters into a list
-- of solid "parts" (box, wedge, cylinder, sphere, prism) in the object's local
-- frame (x right, y forward, z up, metres). The parts are saved on a
-- `procedural` project object and are the single source of the geometry:
--   * in game they are previewed as transient World Builder shapes (collision
--     shape previews or a configured unit mesh), optionally backed by real
--     exported collision primitives;
--   * at Build Mod the MCP server triangulates them into a UV-mapped glTF,
--     converts it to a .mesh with WolvenKit (using a template mesh for its
--     materials) and injects a native worldMeshNode into the export.
-- Segment parts (pipes, ducts, rails, stringers) are oriented along local +Y:
-- yaw turns +Y towards the segment in the XY plane, pitch raises it.
local Procedural={};Procedural.__index=Procedural

local PREFIX='__proc_'
local MAX_PARTS=2000
local MAX_COLLIDERS=200

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function vec(p) if type(p)~='table' then return nil end;local x,y,z=num(p.x or p[1]),num(p.y or p[2]),num(p.z or p[3],0);if not x or not y then return nil end;return {x=x,y=y,z=z} end
local function box(cx,cy,cz,sx,sy,sz,rot,material) return {shape='box',center={x=cx,y=cy,z=cz},size={x=sx,y=sy,z=sz},rotation=rot or {roll=0,pitch=0,yaw=0},material=material or 'main'} end

local function range(p,key,default,lo,hi,label)
    local v=num(p[key],default)
    if v==nil then return nil,(label or key)..' is required' end
    if v<lo or v>hi then return nil,string.format('%s must be between %g and %g',label or key,lo,hi) end
    return v
end

-- Orientation that turns local +Y onto direction d.
local function segment(a,b)
    local dx,dy,dz=b.x-a.x,b.y-a.y,b.z-a.z
    local len=math.sqrt(dx*dx+dy*dy+dz*dz)
    if len<1e-4 then return nil end
    return len,{roll=0,pitch=math.deg(math.asin(math.max(-1,math.min(1,dz/len)))),yaw=math.deg(math.atan2(-dx,dy))},
        {x=(a.x+b.x)/2,y=(a.y+b.y)/2,z=(a.z+b.z)/2}
end

local function points(p,key,min_count,flat)
    local out={}
    for i,v in ipairs(type(p[key])=='table' and p[key] or {}) do
        local q=vec(v);if not q then return nil,key..'['..i..'] must be [x, y(, z)]' end
        if flat then q.z=0 end
        out[#out+1]=q
    end
    if #out<min_count then return nil,key..' needs at least '..min_count..' points' end
    return out
end

local G={}

G.box={label='Box / slab / beam',params={size='[x, y, z] metres',anchor='bottom | center'},fn=function(p)
    local s=vec(p.size or {1,1,1});if not s then return nil,'size must be [x, y, z]' end
    for _,k in ipairs({'x','y','z'}) do if s[k]<0.01 or s[k]>200 then return nil,'size.'..k..' must be between 0.01 and 200' end end
    return {box(0,0,p.anchor=='center' and 0 or s.z/2,s.x,s.y,s.z)}
end}

G.wall={label='Wall with openings',params={length='m',height='m',thickness='m',openings='[{offset, width, height, sill}] (offset = centre along the wall from its middle)'},fn=function(p)
    local L,err=range(p,'length',4,0.1,100);if not L then return nil,err end
    local H;H,err=range(p,'height',3,0.1,30);if not H then return nil,err end
    local T;T,err=range(p,'thickness',0.15,0.02,5);if not T then return nil,err end
    local ops={}
    for i,o in ipairs(type(p.openings)=='table' and p.openings or {}) do
        local w,h,s,c=num(o.width,1),num(o.height,2.1),num(o.sill,0),num(o.offset,0)
        if w<=0 or h<=0 or s<0 then return nil,'opening '..i..' needs a positive width and height' end
        if c-w/2< -L/2-1e-6 or c+w/2>L/2+1e-6 then return nil,'opening '..i..' extends past the wall ends' end
        if s+h>H+1e-6 then return nil,'opening '..i..' is taller than the wall' end
        ops[#ops+1]={a=c-w/2,b=c+w/2,s=s,h=h}
    end
    table.sort(ops,function(x,y) return x.a<y.a end)
    for i=2,#ops do if ops[i].a<ops[i-1].b-1e-6 then return nil,'openings overlap' end end
    local parts={};local cursor=-L/2
    local function solid(a,b,z0,z1) if b-a>1e-4 and z1-z0>1e-4 then parts[#parts+1]=box((a+b)/2,0,(z0+z1)/2,b-a,T,z1-z0) end end
    for _,o in ipairs(ops) do
        solid(cursor,o.a,0,H)
        solid(o.a,o.b,o.s+o.h,H)
        solid(o.a,o.b,0,o.s)
        cursor=o.b
    end
    solid(cursor,L/2,0,H)
    return parts
end}

local function slab(p,z_top)
    local T,err=range(p,'thickness',0.2,0.01,5);if not T then return nil,err end
    if p.points then
        local pts;pts,err=points(p,'points',3,true);if not pts then return nil,err end
        local flat={};for i,q in ipairs(pts) do flat[i]={x=q.x,y=q.y} end
        return {{shape='prism',points=flat,z0=z_top-T,z1=z_top,material='main'}}
    end
    local W;W,err=range(p,'width',4,0.1,200);if not W then return nil,err end
    local D;D,err=range(p,'depth',4,0.1,200);if not D then return nil,err end
    return {box(0,0,z_top-T/2,W,D,T)}
end
G.floor={label='Floor slab',params={width='m',depth='m',thickness='m',points='optional polygon [[x,y],...] instead of width/depth'},fn=function(p) return slab(p,0) end}
G.ceiling={label='Ceiling slab',params={width='m',depth='m',thickness='m',height='underside height (m)',points='optional polygon'},fn=function(p)
    local h,err=range(p,'height',3,0,50);if not h then return nil,err end
    local T=num(p.thickness,0.2);return slab(p,h+T)
end}

G.column={label='Column (box or round, with base and cap)',params={shape='box | round',width='m',depth='m',radius='m',height='m',base='{height, overhang}',cap='{height, overhang}',sides='round sides'},fn=function(p)
    local H,err=range(p,'height',3,0.1,50);if not H then return nil,err end
    local round=p.shape=='round'
    local W,D,R
    if round then R,err=range(p,'radius',0.2,0.02,10);if not R then return nil,err end;W,D=R*2,R*2
    else W,err=range(p,'width',0.4,0.02,20);if not W then return nil,err end;D,err=range(p,'depth',W,0.02,20);if not D then return nil,err end end
    local base=type(p.base)=='table' and p.base or {};local cap=type(p.cap)=='table' and p.cap or {}
    local bh,bo=num(base.height,0),num(base.overhang,0.05);local ch,co=num(cap.height,0),num(cap.overhang,0.05)
    if bh<0 or ch<0 or bh+ch>=H then return nil,'base and cap must be shorter than the column' end
    local parts={}
    if bh>0 then parts[#parts+1]=box(0,0,bh/2,W+2*bo,D+2*bo,bh) end
    local z0,z1=bh,H-ch
    if round then parts[#parts+1]={shape='cylinder',center={x=0,y=0,z=(z0+z1)/2},radius=R,length=z1-z0,sides=math.floor(num(p.sides,16)),rotation={roll=0,pitch=90,yaw=0},material='main'}
    else parts[#parts+1]=box(0,0,(z0+z1)/2,W,D,z1-z0) end
    if ch>0 then parts[#parts+1]=box(0,0,H-ch/2,W+2*co,D+2*co,ch) end
    return parts
end}

G.stairs={label='Straight stairs',params={width='m',height='total rise (m)',length='total run (m)',steps='count (default: risers <= 0.18 m)',solid='true = solid steps, false = floating treads',tread='tread thickness when not solid',landing='top landing depth (m)',stringers='side stringers'},fn=function(p)
    local W,err=range(p,'width',1.2,0.3,20);if not W then return nil,err end
    local H;H,err=range(p,'height',3,0.1,20);if not H then return nil,err end
    local L;L,err=range(p,'length',H*1.6,0.2,60);if not L then return nil,err end
    local N=math.floor(num(p.steps,math.max(1,math.ceil(H/0.18-1e-9))))
    if N<1 or N>200 then return nil,'steps must be between 1 and 200' end
    local landing=num(p.landing,0);if landing<0 then return nil,'landing must be >= 0' end
    local r,d=H/N,L/N;local solid=p.solid~=false;local t=num(p.tread,0.05)
    local parts={}
    for i=0,N-1 do
        local top=(i+1)*r
        if solid then parts[#parts+1]=box(0,(i+0.5)*d,top/2,W,d,top) else parts[#parts+1]=box(0,(i+0.5)*d,top-t/2,W,d,t) end
    end
    if landing>0 then if solid then parts[#parts+1]=box(0,L+landing/2,H/2,W,landing,H) else parts[#parts+1]=box(0,L+landing/2,H-t/2,W,landing,t) end end
    if p.stringers==true then
        local s=num(p.stringer_width,0.06);local depth=num(p.stringer_depth,0.25)
        local len,rot,mid=segment({x=0,y=0,z=0},{x=0,y=L,z=H})
        for _,side in ipairs({-1,1}) do parts[#parts+1]=box(side*(W/2+s/2),mid.y,mid.z,s,len,depth,rot) end
    end
    return parts
end}

G.ramp={label='Ramp',params={width='m',length='m',height='rise (m)',solid='true = solid wedge, false = sloped slab',thickness='slab thickness'},fn=function(p)
    local W,err=range(p,'width',1.5,0.2,50);if not W then return nil,err end
    local L;L,err=range(p,'length',4,0.2,100);if not L then return nil,err end
    local H;H,err=range(p,'height',0.5,0.01,20);if not H then return nil,err end
    if p.solid~=false then return {{shape='wedge',center={x=0,y=L/2,z=H/2},size={x=W,y=L,z=H},rotation={roll=0,pitch=0,yaw=0},material='main'}} end
    local T=num(p.thickness,0.15);local len,rot,mid=segment({x=0,y=0,z=0},{x=0,y=L,z=H})
    return {box(0,mid.y,mid.z-T/2,W,len,T,rot)}
end}

G.door_frame={label='Door frame',params={width='opening width (m)',height='opening height (m)',frame='profile width (m)',depth='frame depth (m)',threshold='add a threshold'},fn=function(p)
    local W,err=range(p,'width',1,0.3,10);if not W then return nil,err end
    local H;H,err=range(p,'height',2.1,0.5,10);if not H then return nil,err end
    local f=num(p.frame,0.08);local d=num(p.depth,0.2)
    if f<=0 or d<=0 then return nil,'frame and depth must be positive' end
    local parts={box(-(W/2+f/2),0,(H+f)/2,f,d,H+f),box(W/2+f/2,0,(H+f)/2,f,d,H+f),box(0,0,H+f/2,W,d,f)}
    if p.threshold==true then parts[#parts+1]=box(0,0,0.01,W,d,0.02) end
    return parts
end}

G.window={label='Window frame with mullions and glass',params={width='m',height='m',sill='bottom height (m)',frame='profile (m)',depth='m',mullions_x='vertical bars',mullions_y='horizontal bars',glass='add a glass pane (material slot "glass")'},fn=function(p)
    local W,err=range(p,'width',1.5,0.2,20);if not W then return nil,err end
    local H;H,err=range(p,'height',1.2,0.2,20);if not H then return nil,err end
    local S=num(p.sill,1);local f=num(p.frame,0.06);local d=num(p.depth,0.12)
    local mx,my=math.floor(num(p.mullions_x,0)),math.floor(num(p.mullions_y,0))
    if f<=0 or d<=0 or S<0 or mx<0 or my<0 or mx>20 or my>20 then return nil,'frame/depth must be positive, sill >= 0, mullions 0-20' end
    local parts={box(-(W/2+f/2),0,S+H/2,f,d,H+2*f),box(W/2+f/2,0,S+H/2,f,d,H+2*f),box(0,0,S-f/2,W,d,f),box(0,0,S+H+f/2,W,d,f)}
    local m=f*0.6
    for i=1,mx do parts[#parts+1]=box(-W/2+W*i/(mx+1),0,S+H/2,m,d*0.8,H) end
    for i=1,my do parts[#parts+1]=box(0,0,S+H*i/(my+1),W,d*0.8,m) end
    if p.glass~=false then parts[#parts+1]=box(0,0,S+H/2,W,0.01,H,nil,'glass') end
    return parts
end}

G.railing={label='Railing',params={points='polyline [[x,y,z],...] (or length)',length='m when no points',height='m',post_spacing='m',post_size='m',rails='rail count',rail_size='m'},fn=function(p)
    local pts,err
    if p.points then pts,err=points(p,'points',2,false);if not pts then return nil,err end
    else local L;L,err=range(p,'length',3,0.1,500);if not L then return nil,err end;pts={{x=-L/2,y=0,z=0},{x=L/2,y=0,z=0}} end
    local H=num(p.height,1);local spacing=num(p.post_spacing,1.2);local ps=num(p.post_size,0.05);local rails=math.floor(num(p.rails,2));local rs=num(p.rail_size,0.04)
    if H<=0.1 or H>5 or spacing<0.1 or ps<=0 or rs<=0 or rails<1 or rails>10 then return nil,'height 0.1-5, post_spacing >= 0.1, rails 1-10, sizes positive' end
    local parts={};local posts={}
    local function post(q) for _,o in ipairs(posts) do if math.abs(o.x-q.x)<1e-3 and math.abs(o.y-q.y)<1e-3 and math.abs(o.z-q.z)<1e-3 then return end end
        posts[#posts+1]=q;parts[#parts+1]=box(q.x,q.y,q.z+H/2,ps,ps,H) end
    for i=1,#pts-1 do
        local a,b=pts[i],pts[i+1]
        local len,rot,mid=segment(a,b);if not len then return nil,'points '..i..' and '..(i+1)..' coincide' end
        local n=math.max(1,math.ceil(len/spacing))
        for k=0,n do local t=k/n;post({x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t,z=a.z+(b.z-a.z)*t}) end
        for r=1,rails do local z=H*r/rails-rs/2;parts[#parts+1]=box(mid.x,mid.y,mid.z+z,rs,len,rs,rot) end
    end
    return parts
end}

local function swept(p,profile)
    local pts,err=points(p,'points',2,false);if not pts then return nil,err end
    local parts={}
    for i=1,#pts-1 do
        local len,rot,mid=segment(pts[i],pts[i+1]);if not len then return nil,'points '..i..' and '..(i+1)..' coincide' end
        parts[#parts+1]=profile(len,rot,mid)
    end
    return parts,pts
end
G.pipe={label='Pipe along a polyline',params={points='[[x,y,z],...]',radius='m',sides='8-32',elbows='spheres at bends'},fn=function(p)
    local R,err=range(p,'radius',0.1,0.01,3);if not R then return nil,err end
    local sides=math.floor(num(p.sides,12));if sides<3 or sides>64 then return nil,'sides must be 3-64' end
    local parts,pts=swept(p,function(len,rot,mid) return {shape='cylinder',center=mid,radius=R,length=len,sides=sides,rotation=rot,material='main'} end)
    if not parts then return nil,pts end
    if p.elbows~=false then for i=2,#pts-1 do parts[#parts+1]={shape='sphere',center=pts[i],radius=R,sides=sides,rotation={roll=0,pitch=0,yaw=0},material='main'} end end
    return parts
end}
G.duct={label='Rectangular duct along a polyline',params={points='[[x,y,z],...]',width='m',height='m'},fn=function(p)
    local W,err=range(p,'width',0.5,0.05,5);if not W then return nil,err end
    local H;H,err=range(p,'height',0.3,0.05,5);if not H then return nil,err end
    local parts,pts=swept(p,function(len,rot,mid) return box(mid.x,mid.y,mid.z,W,len,H,rot) end)
    if not parts then return nil,pts end
    local j=math.max(W,H)
    for i=2,#pts-1 do parts[#parts+1]=box(pts[i].x,pts[i].y,pts[i].z,j,j,j) end
    return parts
end}

-- Precomputed parts (used by the parametric room generator), validated.
local SHAPE_OK={box=true,wedge=true,cylinder=true,sphere=true,prism=true}
G.compound={label='Compound (explicit parts)',params={parts='[{shape, center, size | radius/length | points/z0/z1, rotation, material}]'},fn=function(p)
    local out={}
    for i,part in ipairs(type(p.parts)=='table' and p.parts or {}) do
        if type(part)~='table' or not SHAPE_OK[part.shape] then return nil,'part '..i..' has an unknown shape' end
        local q=Util.deepcopy(part);q.material=q.material=='glass' and 'glass' or 'main';q.rotation=q.rotation or {roll=0,pitch=0,yaw=0}
        if q.shape=='prism' then
            if type(q.points)~='table' or #q.points<3 or not num(q.z0) or not num(q.z1) or q.z1<=q.z0 then return nil,'prism part '..i..' needs 3+ points and z0 < z1' end
        else
            if not vec(q.center) then return nil,'part '..i..' needs a center' end
            if q.shape=='box' or q.shape=='wedge' then local sz=vec(q.size);if not sz or sz.x<=0 or sz.y<=0 or sz.z<=0 then return nil,'part '..i..' needs a positive size' end
            elseif not num(q.radius) or q.radius<=0 or (q.shape=='cylinder' and (not num(q.length) or q.length<=0)) then return nil,'part '..i..' needs a positive radius/length' end
        end
        out[#out+1]=q
    end
    if #out==0 then return nil,'compound geometry needs at least one part' end
    return out
end}

-- Constructive solid geometry: union / subtract / intersect of parts and generator outputs
-- (modules/csg.lua). Parts are the preview/collision boxes; the exact tree is saved as
-- metadata.procedural.csg.tree and meshed exactly at Build Mod.
G.csg={label='CSG (union / subtract / intersect)',params={tree='{op = union|subtract|intersect, children = [...]} | part | {generator, params, offset, rotation}; any node may have repeat = {count, step}',
    resolution='grid for curved/rotated shapes in the preview and collision (m, default 0.25)'},fn=function(p)
    local res=num(p.resolution,0.25);if res<0.02 or res>2 then return nil,'resolution must be between 0.02 and 2 m' end
    if type(p.tree)~='table' then return nil,'csg needs a tree' end
    local tree,err=Csg.expand(p.tree,function(name,params)
        local g=G[name];if not g or name=='csg' then return nil,'unknown generator '..tostring(name) end
        return g.fn(params)
    end)
    if not tree then return nil,err end
    local parts,stats=Csg.decompose(tree,res);if not parts then return nil,stats end
    parts.csg={tree=tree,resolution=stats.resolution,approximate=stats.approximate,cells=stats.cells,boxes=stats.boxes}
    return parts
end}

Procedural.GENERATORS=G

-- Local-frame AABB of the parts.
local function rotate(v,r)
    local cy,sy=math.cos(math.rad(r.yaw or 0)),math.sin(math.rad(r.yaw or 0))
    local cp,sp=math.cos(math.rad(r.pitch or 0)),math.sin(math.rad(r.pitch or 0))
    local cr,sr=math.cos(math.rad(r.roll or 0)),math.sin(math.rad(r.roll or 0))
    -- R = Rz(yaw) * Rx(pitch) * Ry(roll)
    local x,y,z=v.x*cr+v.z*sr,v.y,-v.x*sr+v.z*cr
    y,z=y*cp-z*sp,y*sp+z*cp
    return {x=x*cy-y*sy,y=x*sy+y*cy,z=z}
end
Procedural.rotate=rotate

local function part_extent(part)
    if part.shape=='prism' then
        local lo,hi={x=math.huge,y=math.huge,z=part.z0},{x=-math.huge,y=-math.huge,z=part.z1}
        for _,q in ipairs(part.points) do lo.x=math.min(lo.x,q.x);lo.y=math.min(lo.y,q.y);hi.x=math.max(hi.x,q.x);hi.y=math.max(hi.y,q.y) end
        return lo,hi
    end
    local half
    if part.shape=='cylinder' then half={x=part.radius,y=part.length/2,z=part.radius}
    elseif part.shape=='sphere' then half={x=part.radius,y=part.radius,z=part.radius}
    else half={x=part.size.x/2,y=part.size.y/2,z=part.size.z/2} end
    local lo,hi={x=math.huge,y=math.huge,z=math.huge},{x=-math.huge,y=-math.huge,z=-math.huge}
    for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
        local c=rotate({x=sx*half.x,y=sy*half.y,z=sz*half.z},part.rotation or {})
        for _,k in ipairs({'x','y','z'}) do local v=c[k]+part.center[k];lo[k]=math.min(lo[k],v);hi[k]=math.max(hi[k],v) end
    end end end
    return lo,hi
end
Procedural.part_extent=part_extent

local function bounds(parts)
    local lo,hi={x=math.huge,y=math.huge,z=math.huge},{x=-math.huge,y=-math.huge,z=-math.huge}
    for _,part in ipairs(parts) do
        local a,b=part_extent(part)
        for _,k in ipairs({'x','y','z'}) do lo[k]=math.min(lo[k],a[k]);hi[k]=math.max(hi[k],b[k]) end
    end
    return {min=lo,max=hi}
end

-- Run a generator: parts, bounds and stats, or nil plus an error.
function Procedural.generate(generator,params)
    local g=G[generator];if not g then return nil,'unknown generator: '..tostring(generator) end
    local ok,parts,err=pcall(g.fn,type(params)=='table' and params or {})
    if not ok then return nil,'generator '..generator..' failed: '..tostring(parts) end
    if not parts then return nil,err end
    if #parts==0 then return nil,'the parameters produce no geometry' end
    if #parts>MAX_PARTS then return nil,'the parameters produce '..#parts..' parts; the limit is '..MAX_PARTS end
    local csg=parts.csg;parts.csg=nil
    local info={parts=parts,bounds=bounds(parts),stats={parts=#parts},csg=csg}
    if csg then info.stats.csg={approximate=csg.approximate,resolution=csg.resolution,boxes=csg.boxes} end
    return info
end

-- Collision boxes approximating the parts (exported as World Builder collision shapes).
function Procedural.colliders(parts)
    local out={}
    for _,part in ipairs(parts) do
        if part.material~='glass' then
            if part.shape=='box' then out[#out+1]={center=part.center,size=part.size,rotation=part.rotation}
            elseif part.shape=='cylinder' then out[#out+1]={center=part.center,size={x=part.radius*2,y=part.length,z=part.radius*2},rotation=part.rotation}
            elseif part.shape=='wedge' then
                local L,H=part.size.y,part.size.z;local len=math.sqrt(L*L+H*H)
                out[#out+1]={center={x=part.center.x,y=part.center.y,z=part.center.z},size={x=part.size.x,y=len,z=0.05},rotation={roll=0,pitch=math.deg(math.atan(H/L)),yaw=part.rotation.yaw or 0}}
            elseif part.shape=='prism' then
                local lo,hi=part_extent(part)
                out[#out+1]={center={x=(lo.x+hi.x)/2,y=(lo.y+hi.y)/2,z=(lo.z+hi.z)/2},size={x=hi.x-lo.x,y=hi.y-lo.y,z=hi.z-lo.z},rotation={roll=0,pitch=0,yaw=0}}
            end
        end
    end
    return out
end

function Procedural.new(app) return setmetatable({app=app,proxies={},last_error=nil},Procedural) end

function Procedural:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required and not app.authoring_plans.running then return 'Resolve authoring-plan recovery first' end
    return nil
end

function Procedural:settings()
    local s=self.app.model.data.settings;s.procedural=type(s.procedural)=='table' and s.procedural or {}
    local p=s.procedural
    if p.proxy~='collision' and p.proxy~='mesh' and p.proxy~='none' then p.proxy='collision' end
    p.mesh_root=type(p.mesh_root)=='string' and p.mesh_root~='' and p.mesh_root or 'mod\\locationstudio\\procedural'
    return p
end

function Procedural:generators()
    local out={}
    for key,g in pairs(G) do out[#out+1]={id=key,label=g.label,params=Util.deepcopy(g.params)} end
    table.sort(out,function(a,b) return a.id<b.id end)
    return {items=out,count=#out,settings=Util.deepcopy(self:settings())}
end

local function slug(s) return (tostring(s or 'x'):lower():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')) end

function Procedural:_mesh_path(object)
    local premise=self.app.model:get_premise(object.premise_id)
    return self:settings().mesh_root..'\\'..slug(premise and premise.name or 'project')..'\\'..slug(object.name)..'_'..slug(object.id)..'.mesh'
end

function Procedural:_transform(args)
    if type(args.transform)=='table' and type(args.transform.position)=='table' then return Util.deepcopy(args.transform) end
    local t,err
    if args.source=='aim' then local hit;hit,err=self.app.game:aim_point(num(args.distance,10));if not hit then return nil,err end;t={position=hit.position,rotation={roll=0,pitch=0,yaw=num(args.yaw,0)}}
    else t,err=self.app.game:capture_transform();if not t then return nil,err end;t.rotation={roll=0,pitch=0,yaw=num(args.yaw,t.rotation and t.rotation.yaw or 0)} end
    t.position.w=1
    return t
end

local SLOTS={main=true,glass=true}

-- Material setup: either `materials` (slot -> .mi/.mt, built as a native CMesh)
-- or `template` (a .mesh the geometry is imported over with WolvenKit).
local function clean_material(m,base,library)
    m=type(m)=='table' and m or {};base=base or {}
    local out={template=m.template or base.template or '',appearance=m.appearance or base.appearance or 'default',uv_scale=num(m.uv_scale,base.uv_scale or 1),
        glass_template=m.glass_template or base.glass_template or '',materials=Util.deepcopy(type(m.materials)=='table' and m.materials or base.materials or {})}
    if out.uv_scale<=0 then return nil,'uv_scale must be positive' end
    if out.template~='' and not tostring(out.template):lower():match('%.mesh$') then return nil,'material.template must be a .mesh depot path whose materials the generated mesh uses' end
    for slot,path in pairs(out.materials) do
        if not SLOTS[slot] then return nil,'material slot must be main or glass: '..tostring(slot) end
        local p=tostring(path):lower()
        if p=='' then out.materials[slot]=nil
        elseif p:sub(1,1)=='@' then
            if not library then return nil,'material library references (@key) need the material library' end
            local _,err=library:resolve(tostring(path));if err then return nil,'materials.'..slot..': '..err end
        elseif not (p:match('%.mi$') or p:match('%.mt$') or p:match('%.remt$')) then return nil,'materials.'..slot..' must be a .mi/.mt depot path' end
    end
    if out.materials.glass and not out.materials.main then return nil,'materials.main is required when glass is set' end
    return out
end

-- Real collision objects owned by a procedural object.
function Procedural:_rebuild_colliders(object,info)
    local cfg=object.metadata.procedural
    for _,id in ipairs(cfg.collider_ids or {}) do
        local c=self.app.model:get_object(id)
        if c then if self.app.placement:is_tracked(c) then self.app.placement:despawn(c) end;self.app.model:delete_objects({id}) end
    end
    cfg.collider_ids={}
    cfg.collision_warnings=nil;cfg.collision_stats=nil
    if not cfg.collision then return true end
    if not self.app.collision then return nil,'collision authoring is unavailable' end
    local boxes,preset,material=nil,cfg.collision_preset,nil
    local gen=self.app.collision_gen
    if gen then
        -- Collision rules (modules/collision_gen.lua): mode, actors, doorways, rails, rooms.
        local plan,err=gen:plan(object,info.parts);if not plan then return nil,err end
        boxes,preset,material=plan.boxes,plan.preset,plan.material
        cfg.collision_warnings=#plan.warnings>0 and plan.warnings or nil;cfg.collision_stats=plan.stats
    else
        boxes=Procedural.colliders(info.parts)
        for _,b in ipairs(boxes) do b.shape='box';b.rotation=b.rotation or {} end
    end
    if #boxes>MAX_COLLIDERS then return nil,'this geometry needs '..#boxes..' collision boxes; the limit is '..MAX_COLLIDERS..' (turn collision off or simplify)' end
    local base=object.transform
    for i,b in ipairs(boxes) do
        local c=rotate(b.center,base.rotation)
        local transform={position={x=base.position.x+c.x,y=base.position.y+c.y,z=base.position.z+c.z,w=1},
            rotation={roll=b.rotation.roll or 0,pitch=b.rotation.pitch or 0,yaw=(b.rotation.yaw or 0)+(base.rotation.yaw or 0)}}
        local args={premise_id=object.premise_id,room_id=b.room_id or object.room_id,name=object.name..' collision '..i,shape=b.shape or 'box',
            preset=preset,material=material,transform=transform,visualize=false,spawn=cfg.spawn_collision~=false}
        if args.shape=='sphere' then args.radius=b.radius else args.size={x=b.size.x,y=b.size.y,z=b.size.z} end
        local r,err=self.app.collision:create_primitive(args)
        if not r then return nil,err end
        r.object.metadata.procedural_owner=object.id
        r.object.metadata.collision_gen={owner=object.id,role=b.role or 'geometry'}
        cfg.collider_ids[#cfg.collider_ids+1]=r.object.id
    end
    return true
end

-- Collapse the history entries created since `mark` into one.
local function collapse(model,mark)
    while #model.undo_stack>mark do table.remove(model.undo_stack) end
end

-- Put the project back exactly as it was before a failed create/update.
function Procedural:_abort(before,mark,created_colliders)
    for _,id in ipairs(created_colliders or {}) do
        local c=self.app.model:get_object(id);if c and self.app.placement:is_tracked(c) then self.app.placement:despawn(c) end
    end
    self.app.model.data=before
    collapse(self.app.model,mark-1)
end

function Procedural:create(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local info,err=Procedural.generate(args.generator,args.params);if not info then return nil,err end
    local material;material,err=clean_material(args.material,nil,self.app.material_library);if not material then return nil,err end
    local transform;transform,err=self:_transform(args);if not transform then return nil,err end
    local rules
    if args.collision_rules~=nil then
        if not self.app.collision_gen then return nil,'collision rules are unavailable' end
        rules,err=self.app.collision_gen.normalize_rules(args.collision_rules);if not rules then return nil,err end
        if next(rules)==nil then rules=nil end
    end
    local model=self.app.model
    local before=Util.deepcopy(model.data)
    model:snapshot('Create procedural '..tostring(args.generator));local mark=#model.undo_stack
    local object=model:add_object({premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id,
        name=Util.trim(args.name or '')~='' and Util.trim(args.name) or (G[args.generator].label),kind='procedural',template='',
        layer=args.layer or 'shell',transform=transform,size={x=1,y=1,z=1},enabled=true,
        metadata={source='LocationStudio procedural geometry',procedural={generator=args.generator,params=Util.deepcopy(args.params or {}),parts=info.parts,
            bounds=info.bounds,stats=info.stats,csg=info.csg,material=material,collision=args.collision==true,collision_rules=rules,collision_preset=args.collision_preset,collider_ids={},
            stream_range=num(args.stream_range,nil)},asset_bounds={min=Util.deepcopy(info.bounds.min),max=Util.deepcopy(info.bounds.max),source='procedural'}}})
    if not object then self:_abort(before,mark);return nil,'project model rejected the procedural object' end
    object.metadata.procedural.mesh_path=args.mesh_path or self:_mesh_path(object)
    local ok;ok,err=self:_rebuild_colliders(object,info)
    if not ok then self:_abort(before,mark,object.metadata.procedural.collider_ids);return nil,err end
    collapse(model,mark)
    model:touch();self.app:mark_dirty()
    if self.app.selection then self.app.selection:set('object',object.id) end
    local result={object=object,parts=#info.parts,bounds=info.bounds,mesh_path=object.metadata.procedural.mesh_path,colliders=#object.metadata.procedural.collider_ids}
    if args.spawn~=false then local shown,show_err=self:show(object);result.proxies=shown and shown.proxies or 0;result.preview_error=show_err end
    return result
end

function Procedural:update(object_id,patch)
    patch=patch or {}
    local busy=self:_busy();if busy then return nil,busy end
    local object=self.app.model:get_object(object_id);local cfg=object and object.metadata and object.metadata.procedural
    if not cfg then return nil,'not a procedural object' end
    if object.locked then return nil,'object is locked' end
    local params=Util.deepcopy(cfg.params)
    if type(patch.params)=='table' then for k,v in pairs(patch.params) do params[k]=Util.deepcopy(v) end end
    if patch.replace_params==true then params=Util.deepcopy(patch.params or {}) end
    local generator=patch.generator or cfg.generator
    local info,err=Procedural.generate(generator,params);if not info then return nil,err end
    local material=cfg.material
    if patch.material~=nil then material,err=clean_material(patch.material,cfg.material,self.app.material_library);if not material then return nil,err end end
    local rules=cfg.collision_rules
    if patch.collision_rules~=nil then
        if patch.collision_rules==false then rules=nil
        else
            if not self.app.collision_gen then return nil,'collision rules are unavailable' end
            rules,err=self.app.collision_gen.normalize_rules(patch.collision_rules);if not rules then return nil,err end
            if next(rules)==nil then rules=nil end
        end
    end
    local model=self.app.model
    local before=Util.deepcopy(model.data)
    local old_colliders={}
    for _,id in ipairs(cfg.collider_ids or {}) do local c=model:get_object(id);if c and self.app.placement:is_tracked(c) then old_colliders[#old_colliders+1]=id end end
    self:hide(object)
    model:snapshot('Edit procedural geometry');local mark=#model.undo_stack
    cfg.generator=generator;cfg.params=params;cfg.parts=info.parts;cfg.bounds=info.bounds;cfg.stats=info.stats;cfg.csg=info.csg;cfg.material=material;cfg.collision_rules=rules
    if patch.collision~=nil then cfg.collision=patch.collision==true end
    if patch.stream_range~=nil then cfg.stream_range=num(patch.stream_range,nil) end
    object.metadata.asset_bounds={min=Util.deepcopy(info.bounds.min),max=Util.deepcopy(info.bounds.max),source='procedural'}
    if patch.name then object.name=Util.trim(patch.name) end
    local ok;ok,err=self:_rebuild_colliders(object,info)
    if not ok then
        self:_abort(before,mark,cfg.collider_ids)
        -- The previous colliders were despawned while rebuilding: bring them and the preview back.
        for _,id in ipairs(old_colliders) do local c=model:get_object(id);if c then self.app.placement:spawn(c) end end
        self:show(model:get_object(object_id))
        return nil,err
    end
    collapse(model,mark)
    model:touch();self.app:mark_dirty()
    local shown=self:show(model:get_object(object_id))
    return {object=model:get_object(object_id),parts=#info.parts,bounds=info.bounds,proxies=shown and shown.proxies or 0}
end

function Procedural:delete(object_id)
    local busy=self:_busy();if busy then return nil,busy end
    local object=self.app.model:get_object(object_id);local cfg=object and object.metadata and object.metadata.procedural
    if not cfg then return nil,'not a procedural object' end
    if object.locked then return nil,'object is locked' end
    self:hide(object)
    local ids={object.id}
    for _,id in ipairs(cfg.collider_ids or {}) do local c=self.app.model:get_object(id);if c then if self.app.placement:is_tracked(c) then self.app.placement:despawn(c) end;ids[#ids+1]=id end end
    local ok,err=self.app.model:delete_objects(ids);if not ok then return nil,err end
    self.app:mark_dirty()
    return {deleted=object_id,colliders=#ids-1}
end

function Procedural:list(args)
    args=args or {}
    local rows={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local cfg=o.metadata and o.metadata.procedural
        if cfg and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) then
            rows[#rows+1]={id=o.id,name=o.name,generator=cfg.generator,parts=#(cfg.parts or {}),bounds=cfg.bounds,mesh_path=cfg.mesh_path,
                material=cfg.material,collision=cfg.collision,colliders=#(cfg.collider_ids or {}),shown=self:is_shown(o)}
        end
    end
    return {items=rows,count=#rows,settings=Util.deepcopy(self:settings())}
end

function Procedural:set_settings(patch)
    patch=patch or {}
    local s=self:settings()
    if patch.proxy~=nil then if patch.proxy~='collision' and patch.proxy~='mesh' and patch.proxy~='none' then return nil,'proxy must be collision, mesh or none' end;s.proxy=patch.proxy end
    if patch.proxy_asset_id~=nil then
        if patch.proxy_asset_id=='' then s.proxy_asset_id=nil else
            local asset=self.app.model:get_asset(patch.proxy_asset_id);local wb=asset and asset.metadata and asset.metadata.world_builder
            if not wb or not tostring(wb.definition_key):match('^mesh_') then return nil,'proxy_asset_id must be a registered World Builder mesh asset' end
            local size=vec(patch.proxy_native_size) or (asset.metadata.asset_bounds and {x=asset.metadata.asset_bounds.max.x-asset.metadata.asset_bounds.min.x,
                y=asset.metadata.asset_bounds.max.y-asset.metadata.asset_bounds.min.y,z=asset.metadata.asset_bounds.max.z-asset.metadata.asset_bounds.min.z})
            if not size or size.x<=0 or size.y<=0 or size.z<=0 then return nil,'give proxy_native_size [x,y,z] or import bounds for the proxy mesh' end
            s.proxy_asset_id=asset.id;s.proxy_native_size=size
        end
    end
    if patch.mesh_root~=nil then
        local root=Util.trim(tostring(patch.mesh_root)):gsub('/','\\'):gsub('\\+$','')
        if root=='' or not root:match('^[%w_\\%-]+$') then return nil,'mesh_root must be a depot folder such as mod\\mymod\\procedural' end
        s.mesh_root=root
    end
    self.app:mark_dirty()
    return Util.deepcopy(s)
end

-- Preview -------------------------------------------------------------------

function Procedural:is_shown(object) return object~=nil and self.proxies[object.id]~=nil end

function Procedural:_proxy_entry(b,index,object)
    local s=self:settings()
    if s.proxy=='mesh' and s.proxy_asset_id then
        local asset=self.app.model:get_asset(s.proxy_asset_id);local wb=asset and asset.metadata.world_builder
        if not wb then return nil,'proxy mesh asset is missing' end
        local n=s.proxy_native_size
        return {metadata={world_builder=Util.deepcopy(wb)},size={x=b.size.x/n.x,y=b.size.y/n.y,z=b.size.z/n.z},kind='mesh'}
    end
    local name=object.name..' preview '..index
    local data={shape=0,scale={x=b.size.x/2,y=b.size.y/2,z=b.size.z/2},preset=0,previewed=true,modulePath='collision/collider',dataType='Collision Shape'}
    return {metadata={world_builder={definition_key='collision_shape',category='Collision',variant='Collision Shape',class_module='modules/classes/spawn/collision/collider',
        module_path='collision/collider',resource_name='Collision Shape',resource_path='',entry={name=name,fileName=name,data=data},apply_scale=true}},
        size={x=b.size.x/2,y=b.size.y/2,z=b.size.z/2},kind='collision'}
end

-- Spawn transient preview shapes for the parts (approximating non-box parts by boxes).
function Procedural:show(object)
    local cfg=object and object.metadata and object.metadata.procedural;if not cfg then return nil,'not a procedural object' end
    self:hide(object)
    local s=self:settings()
    if s.proxy=='none' then self.proxies[object.id]={};return {proxies=0,mode='none'} end
    if not self.app.runtime_shell then return nil,'World Builder is unavailable for the preview' end
    local list={};local failed=0
    for i,b in ipairs(Procedural.colliders(cfg.parts or {})) do
        local entry,err=self:_proxy_entry(b,i,object);if not entry then return nil,err end
        local c=rotate(b.center,object.transform.rotation)
        local proxy={id=PREFIX..object.id..'_'..i,name=object.name..' preview '..i,kind=entry.kind,template='',enabled=true,size=entry.size,
            transform={position={x=object.transform.position.x+c.x,y=object.transform.position.y+c.y,z=object.transform.position.z+c.z,w=1},
                rotation={roll=b.rotation.roll or 0,pitch=b.rotation.pitch or 0,yaw=(b.rotation.yaw or 0)+(object.transform.rotation.yaw or 0)}},
            metadata=entry.metadata,runtime={}}
        if self.app.runtime_shell:spawn(proxy) then list[#list+1]=proxy else failed=failed+1 end
    end
    self.proxies[object.id]=list
    if failed>0 then return {proxies=#list,failed=failed,mode=s.proxy},failed..' preview shape(s) failed to spawn' end
    return {proxies=#list,mode=s.proxy}
end

function Procedural:hide(object)
    local list=object and self.proxies[object.id];if not list then return true end
    for _,proxy in ipairs(list) do pcall(function() self.app.runtime_shell:despawn(proxy) end) end
    self.proxies[object.id]=nil
    return true
end

function Procedural:hide_all() for id in pairs(self.proxies) do self:hide({id=id}) end;return true end

return Procedural
