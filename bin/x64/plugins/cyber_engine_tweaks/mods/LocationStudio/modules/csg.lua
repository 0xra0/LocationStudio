local Util=require('modules/util')

-- Constructive solid geometry for procedural objects.
--
-- A tree combines solids with union, subtract and intersect:
--   node = {op='union'|'subtract'|'intersect', children={...}, cut_material='main'|'glass', ['repeat']={count, step}}
--   leaf = a part {shape=box|wedge|cylinder|sphere|prism, center, size | radius/length | points/z0/z1, rotation, material}
--        | a generator {generator='wall', params={...}, offset={x,y,z}, rotation={...}}  (its parts, united)
-- `subtract` removes every later child from the first; `intersect` keeps what
-- all children share. `repeat` makes `count` copies of a node or leaf, each moved by `step`.
--
-- This module expands the tree into primitive leaves only (the exact form the
-- Build Mod mesh boolean in mcp_server/lsbuild/csg.py consumes) and decomposes
-- the result into boxes for the in-game preview, bounds and collision:
--   * the space is cut on a grid made of every leaf's bounding planes, so trees
--     of axis-aligned boxes (walls, doorways, windows, shafts, recesses, vents,
--     rooms) decompose exactly;
--   * curved, sloped or rotated leaves (cylinders, spheres, wedges, oblique
--     prisms, rotated boxes) add uniform grid lines at `resolution`, and their
--     boxes approximate the shape (reported as `approximate`).
-- Cells whose centre lies inside the solid are merged greedily into boxes.
local Csg={}

local OPS={union=true,subtract=true,intersect=true}
local SHAPES={box=true,wedge=true,cylinder=true,sphere=true,prism=true}
local MAX_LEAVES=500
local MAX_DEPTH=16
local MAX_CELLS=40000
local MAX_REPEAT=100
local EPS=1e-7

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function vec(p) if type(p)~='table' then return nil end;local x,y,z=num(p.x or p[1]),num(p.y or p[2]),num(p.z or p[3],0);if not x or not y then return nil end;return {x=x,y=y,z=z} end

-- R = Rz(yaw) * Rx(pitch) * Ry(roll), matching modules/procedural.lua.
local function rotate(v,r)
    local cy,sy=math.cos(math.rad(r.yaw or 0)),math.sin(math.rad(r.yaw or 0))
    local cp,sp=math.cos(math.rad(r.pitch or 0)),math.sin(math.rad(r.pitch or 0))
    local cr,sr=math.cos(math.rad(r.roll or 0)),math.sin(math.rad(r.roll or 0))
    local x,y,z=v.x*cr+v.z*sr,v.y,-v.x*sr+v.z*cr
    y,z=y*cp-z*sp,y*sp+z*cp
    return {x=x*cy-y*sy,y=x*sy+y*cy,z=z}
end
local function unrotate(v,r)
    v=rotate(v,{yaw=-(r.yaw or 0)});v=rotate(v,{pitch=-(r.pitch or 0)});return rotate(v,{roll=-(r.roll or 0)})
end
local function right_angle(a) a=(num(a,0)%90);return a<1e-6 or 90-a<1e-6 end
local function aligned(r) return right_angle(r.roll) and right_angle(r.pitch) and right_angle(r.yaw) end
-- World axis ('x','y','z') a local axis ends up on under an axis-aligned rotation.
local function axis_of(r,local_axis)
    local v={x=0,y=0,z=0};v[local_axis]=1
    local w=rotate(v,r)
    if math.abs(w.x)>0.5 then return 'x' elseif math.abs(w.y)>0.5 then return 'y' end;return 'z'
end

-- ------------------------------------------------------------------ expansion

local function clean_leaf(part,where)
    if type(part)~='table' or not SHAPES[part.shape] then return nil,where..' has an unknown shape' end
    local q=Util.deepcopy(part);q.material=q.material=='glass' and 'glass' or 'main'
    local r=type(q.rotation)=='table' and q.rotation or {};q.rotation={roll=num(r.roll,0),pitch=num(r.pitch,0),yaw=num(r.yaw,0)}
    if q.shape=='prism' then
        local pts={}
        for i,p in ipairs(type(q.points)=='table' and q.points or {}) do local v=vec(p);if not v then return nil,where..' point '..i..' must be [x, y]' end;pts[i]={x=v.x,y=v.y} end
        if #pts<3 or not num(q.z0) or not num(q.z1) or q.z1<=q.z0 then return nil,where..' (prism) needs 3+ points and z0 < z1' end
        q.points=pts;q.rotation=nil;q.center=nil
    else
        q.center=vec(q.center);if not q.center then return nil,where..' needs a center' end
        if q.shape=='box' or q.shape=='wedge' then
            local s=vec(q.size);if not s or s.x<=0 or s.y<=0 or s.z<=0 then return nil,where..' needs a positive size' end;q.size=s
        else
            q.radius=num(q.radius);if not q.radius or q.radius<=0 then return nil,where..' needs a positive radius' end
            if q.shape=='cylinder' then q.length=num(q.length);if not q.length or q.length<=0 then return nil,where..' needs a positive length' end end
        end
    end
    return q
end

-- Move/turn a primitive leaf: p' = offset + R p.
local function place(leaf,offset,rot)
    local q=Util.deepcopy(leaf)
    if q.shape=='prism' then
        if math.abs(rot.roll or 0)>1e-9 or math.abs(rot.pitch or 0)>1e-9 then return nil,'prisms can only be turned by yaw' end
        for _,p in ipairs(q.points) do local w=rotate({x=p.x,y=p.y,z=0},{yaw=rot.yaw});p.x,p.y=w.x+offset.x,w.y+offset.y end
        q.z0,q.z1=q.z0+offset.z,q.z1+offset.z
        return q
    end
    local c=rotate(q.center,rot);q.center={x=c.x+offset.x,y=c.y+offset.y,z=c.z+offset.z}
    if math.abs(rot.roll or 0)>1e-9 or math.abs(rot.pitch or 0)>1e-9 then
        if math.abs(q.rotation.roll)>1e-9 or math.abs(q.rotation.pitch)>1e-9 then return nil,'only one level of roll/pitch can be combined; turn the leaf itself instead' end
        q.rotation={roll=rot.roll or 0,pitch=rot.pitch or 0,yaw=(rot.yaw or 0)+q.rotation.yaw}
    else q.rotation.yaw=q.rotation.yaw+(rot.yaw or 0) end
    return q
end

local function transform_node(node,offset,rot)
    if node.shape then return place(node,offset,rot) end
    local out={op=node.op,cut_material=node.cut_material,children={}}
    for i,c in ipairs(node.children) do local t,err=transform_node(c,offset,rot);if not t then return nil,err end;out.children[i]=t end
    return out
end

-- Expand a raw tree into {op, children} nodes whose leaves are primitives.
-- `generate(name, params)` returns a generator's parts (or nil, err).
function Csg.expand(raw,generate,state,depth,where)
    state=state or {leaves=0};depth=depth or 0;where=where or 'tree'
    if depth>MAX_DEPTH then return nil,'the tree is deeper than '..MAX_DEPTH..' levels' end
    if type(raw)~='table' then return nil,where..' must be a node or a leaf' end
    local node,err
    if raw.op~=nil then
        if not OPS[raw.op] then return nil,where..': op must be union, subtract or intersect' end
        local kids=type(raw.children)=='table' and raw.children or {}
        if #kids==0 or (raw.op~='union' and #kids<2) then return nil,where..': '..raw.op..' needs '..(raw.op=='union' and 'children' or 'at least two children') end
        if #kids>64 then return nil,where..': at most 64 children per node' end
        node={op=raw.op,children={}}
        if raw.cut_material~=nil then node.cut_material=raw.cut_material=='glass' and 'glass' or 'main' end
        for i,c in ipairs(kids) do
            local child;child,err=Csg.expand(c,generate,state,depth+1,where..'.children['..i..']');if not child then return nil,err end
            node.children[i]=child
        end
    elseif raw.generator~=nil then
        if raw.generator=='csg' then return nil,where..': nest trees directly instead of a csg generator leaf' end
        if not generate then return nil,where..': generator leaves are unavailable' end
        local parts;parts,err=generate(raw.generator,type(raw.params)=='table' and raw.params or {})
        if not parts then return nil,where..' ('..tostring(raw.generator)..'): '..tostring(err) end
        local offset=vec(raw.offset) or {x=0,y=0,z=0}
        local r=type(raw.rotation)=='table' and raw.rotation or {yaw=num(raw.yaw,0)}
        local rot={roll=num(r.roll,0),pitch=num(r.pitch,0),yaw=num(r.yaw,0)}
        node={op='union',children={}}
        for i,part in ipairs(parts) do
            local leaf;leaf,err=clean_leaf(part,where..' part '..i);if not leaf then return nil,err end
            if raw.material=='glass' or raw.material=='main' then leaf.material=raw.material end
            leaf,err=place(leaf,offset,rot);if not leaf then return nil,where..': '..err end
            node.children[i]=leaf
        end
        state.leaves=state.leaves+#parts
    else
        node,err=clean_leaf(raw,where);if not node then return nil,err end
        state.leaves=state.leaves+1
    end
    if state.leaves>MAX_LEAVES then return nil,'the tree has more than '..MAX_LEAVES..' primitive leaves' end
    local rep=raw['repeat']
    if rep~=nil then
        if type(rep)~='table' then return nil,where..'.repeat must be {count, step}' end
        local count=math.floor(num(rep.count,0));local step=vec(rep.step)
        if count<1 or count>MAX_REPEAT or not step then return nil,where..'.repeat needs count 1-'..MAX_REPEAT..' and step [x, y, z]' end
        local copies={op='union',children={}}
        local per=0;local function count_leaves(n) if n.shape then per=per+1 else for _,c in ipairs(n.children) do count_leaves(c) end end end;count_leaves(node)
        state.leaves=state.leaves+per*(count-1)
        if state.leaves>MAX_LEAVES then return nil,'the tree has more than '..MAX_LEAVES..' primitive leaves (repeat)' end
        for i=0,count-1 do
            local copy;copy,err=transform_node(node,{x=step.x*i,y=step.y*i,z=step.z*i},{roll=0,pitch=0,yaw=0});if not copy then return nil,err end
            copies.children[#copies.children+1]=copy
        end
        node=copies
    end
    return node
end

-- ------------------------------------------------------------------ geometry queries

local function leaf_box(leaf)
    if leaf.shape=='prism' then
        local lo={x=math.huge,y=math.huge,z=leaf.z0};local hi={x=-math.huge,y=-math.huge,z=leaf.z1}
        for _,p in ipairs(leaf.points) do lo.x=math.min(lo.x,p.x);lo.y=math.min(lo.y,p.y);hi.x=math.max(hi.x,p.x);hi.y=math.max(hi.y,p.y) end
        return lo,hi
    end
    if leaf.shape=='sphere' then local c,r=leaf.center,leaf.radius;return {x=c.x-r,y=c.y-r,z=c.z-r},{x=c.x+r,y=c.y+r,z=c.z+r} end
    local h=leaf.shape=='cylinder' and {x=leaf.radius,y=leaf.length/2,z=leaf.radius} or {x=leaf.size.x/2,y=leaf.size.y/2,z=leaf.size.z/2}
    local lo={x=math.huge,y=math.huge,z=math.huge};local hi={x=-math.huge,y=-math.huge,z=-math.huge}
    for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do for _,sz in ipairs({-1,1}) do
        local w=rotate({x=sx*h.x,y=sy*h.y,z=sz*h.z},leaf.rotation)
        for _,k in ipairs({'x','y','z'}) do local v=leaf.center[k]+w[k];lo[k]=math.min(lo[k],v);hi[k]=math.max(hi[k],v) end
    end end end
    return lo,hi
end

function Csg.bounds(node)
    if node.shape then return leaf_box(node) end
    local lo,hi=Csg.bounds(node.children[1])
    if not lo then return nil end
    if node.op=='subtract' then return lo,hi end
    for i=2,#node.children do
        local a,b=Csg.bounds(node.children[i])
        if node.op=='union' then
            if a then for _,k in ipairs({'x','y','z'}) do lo[k]=math.min(lo[k],a[k]);hi[k]=math.max(hi[k],b[k]) end end
        else
            if not a then return nil end
            for _,k in ipairs({'x','y','z'}) do lo[k]=math.max(lo[k],a[k]);hi[k]=math.min(hi[k],b[k]) end
            if lo.x>=hi.x or lo.y>=hi.y or lo.z>=hi.z then return nil end
        end
    end
    return lo,hi
end

local function inside_polygon(pts,x,y)
    local inside=false;local j=#pts
    for i=1,#pts do
        local a,b=pts[i],pts[j]
        if (a.y>y)~=(b.y>y) and x<(b.x-a.x)*(y-a.y)/(b.y-a.y)+a.x then inside=not inside end
        j=i
    end
    return inside
end

local function leaf_contains(leaf,p)
    if leaf.shape=='prism' then return p.z>leaf.z0 and p.z<leaf.z1 and inside_polygon(leaf.points,p.x,p.y) end
    local d={x=p.x-leaf.center.x,y=p.y-leaf.center.y,z=p.z-leaf.center.z}
    if leaf.shape=='sphere' then return d.x*d.x+d.y*d.y+d.z*d.z<leaf.radius*leaf.radius end
    local l=unrotate(d,leaf.rotation)
    if leaf.shape=='cylinder' then return math.abs(l.y)<leaf.length/2 and l.x*l.x+l.z*l.z<leaf.radius*leaf.radius end
    local h={x=leaf.size.x/2,y=leaf.size.y/2,z=leaf.size.z/2}
    if math.abs(l.x)>=h.x or math.abs(l.y)>=h.y or math.abs(l.z)>=h.z then return false end
    if leaf.shape=='wedge' then return (l.z+h.z)<(l.y+h.y)/(2*h.y)*(2*h.z) end  -- rises towards +y
    return true
end

-- Material of the solid at p, or nil.
function Csg.contains(node,p)
    if node.shape then return leaf_contains(node,p) and node.material or nil end
    if node.op=='union' then
        for _,c in ipairs(node.children) do local m=Csg.contains(c,p);if m then return m end end
        return nil
    end
    local m=Csg.contains(node.children[1],p);if not m then return nil end
    for i=2,#node.children do
        local inside=Csg.contains(node.children[i],p)~=nil
        if node.op=='subtract' and inside then return nil end
        if node.op=='intersect' and not inside then return nil end
    end
    return m
end

-- ------------------------------------------------------------------ box decomposition

local function leaves(node,out) out=out or {};if node.shape then out[#out+1]=node else for _,c in ipairs(node.children) do leaves(c,out) end end;return out end

-- Axes on which a leaf's surface is not made of axis-aligned planes.
local function curved_axes(leaf)
    if leaf.shape=='sphere' then return {x=true,y=true,z=true} end
    if leaf.shape=='prism' then
        for i=1,#leaf.points do
            local a,b=leaf.points[i],leaf.points[i%#leaf.points+1]
            if math.abs(a.x-b.x)>1e-9 and math.abs(a.y-b.y)>1e-9 then return {x=true,y=true} end
        end
        return {}
    end
    if not aligned(leaf.rotation) then return {x=true,y=true,z=true} end
    if leaf.shape=='box' then return {} end
    if leaf.shape=='cylinder' then return {[axis_of(leaf.rotation,'x')]=true,[axis_of(leaf.rotation,'z')]=true} end
    return {[axis_of(leaf.rotation,'y')]=true,[axis_of(leaf.rotation,'z')]=true}  -- wedge slope
end

local function lines(tree,lo,hi,res)
    local set={x={lo.x,hi.x},y={lo.y,hi.y},z={lo.z,hi.z}}
    local approximate=false
    for _,leaf in ipairs(leaves(tree)) do
        local a,b=leaf_box(leaf)
        for _,k in ipairs({'x','y','z'}) do table.insert(set[k],a[k]);table.insert(set[k],b[k]) end
        if leaf.shape=='prism' then for _,p in ipairs(leaf.points) do table.insert(set.x,p.x);table.insert(set.y,p.y) end end
        for k in pairs(curved_axes(leaf)) do
            approximate=true
            for i=math.ceil(a[k]/res),math.floor(b[k]/res) do table.insert(set[k],i*res) end
        end
    end
    local out={}
    for _,k in ipairs({'x','y','z'}) do
        table.sort(set[k]);local list={}
        for _,v in ipairs(set[k]) do if v>=lo[k]-EPS and v<=hi[k]+EPS and (#list==0 or v-list[#list]>1e-5) then list[#list+1]=math.max(lo[k],math.min(hi[k],v)) end end
        out[k]=list
    end
    return out,approximate
end

-- Boxes filling the solid: parts (shape box, material main|glass) plus stats.
function Csg.decompose(tree,resolution)
    local lo,hi=Csg.bounds(tree)
    if not lo or lo.x>=hi.x or lo.y>=hi.y or lo.z>=hi.z then return nil,'the tree produces an empty solid' end
    local res=num(resolution,0.25)
    local g,approximate
    for _=1,10 do
        g,approximate=lines(tree,lo,hi,res)
        if (#g.x-1)*(#g.y-1)*(#g.z-1)<=MAX_CELLS then break end
        if not approximate then return nil,'the tree needs more than '..MAX_CELLS..' preview cells; split it into several objects' end
        res=res*2;g=nil
    end
    if not g then return nil,'the tree is too detailed for the preview grid; raise resolution' end
    local nx,ny,nz=#g.x-1,#g.y-1,#g.z-1
    local cell={}
    local filled=0
    for k=1,nz do local zc=(g.z[k]+g.z[k+1])/2
        for j=1,ny do local yc=(g.y[j]+g.y[j+1])/2
            for i=1,nx do
                local m=Csg.contains(tree,{x=(g.x[i]+g.x[i+1])/2,y=yc,z=zc})
                if m then cell[(k-1)*nx*ny+(j-1)*nx+i]=m;filled=filled+1 end
            end
        end
    end
    if filled==0 then return nil,'the tree produces an empty solid' end
    local function at(i,j,k) return cell[(k-1)*nx*ny+(j-1)*nx+i] end
    local function clear(i,j,k) cell[(k-1)*nx*ny+(j-1)*nx+i]=nil end
    local parts={}
    for k=1,nz do for j=1,ny do for i=1,nx do
        local m=at(i,j,k)
        if m then
            local i2=i;while i2<nx and at(i2+1,j,k)==m do i2=i2+1 end
            local j2=j
            while j2<ny do local ok=true;for ii=i,i2 do if at(ii,j2+1,k)~=m then ok=false;break end end;if not ok then break end;j2=j2+1 end
            local k2=k
            while k2<nz do
                local ok=true
                for jj=j,j2 do for ii=i,i2 do if at(ii,jj,k2+1)~=m then ok=false;break end end;if not ok then break end end
                if not ok then break end;k2=k2+1
            end
            for kk=k,k2 do for jj=j,j2 do for ii=i,i2 do clear(ii,jj,kk) end end end
            local x0,x1,y0,y1,z0,z1=g.x[i],g.x[i2+1],g.y[j],g.y[j2+1],g.z[k],g.z[k2+1]
            parts[#parts+1]={shape='box',center={x=(x0+x1)/2,y=(y0+y1)/2,z=(z0+z1)/2},size={x=x1-x0,y=y1-y0,z=z1-z0},rotation={roll=0,pitch=0,yaw=0},material=m}
        end
    end end end
    return parts,{cells=nx*ny*nz,filled=filled,boxes=#parts,resolution=res,approximate=approximate}
end

-- Example trees shared with the MCP server (csg/examples.json).
function Csg.examples(path)
    local file=io.open(path or 'csg/examples.json','r');if not file then return {} end
    local text=file:read('*a');file:close()
    local ok,doc=pcall(function() return json.decode(text) end)
    if not ok or type(doc)~='table' or type(doc.examples)~='table' then return {} end
    local out={}
    for id,e in pairs(doc.examples) do out[#out+1]={id=id,label=e.label or id,tree=e.tree} end
    table.sort(out,function(a,b) return a.id<b.id end)
    return out
end

Csg.rotate=rotate
return Csg
