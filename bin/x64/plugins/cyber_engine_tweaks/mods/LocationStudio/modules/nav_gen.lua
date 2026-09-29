local Util=require('modules/util')
local Surfaces=require('modules/surfaces')

-- Navigation generator. Builds a navigation graph from generated geometry:
--   * navigation surfaces: the walkable semantic surfaces (floors, platforms,
--     stairs, ramps, ...) rasterized on a grid, cleared for an agent's radius and
--     height, and merged into rectangles (polygons + one area node each);
--   * door transitions: every door of a parametric room becomes a door node linked
--     to the floor on both sides, with its width checked against the agent;
--   * stairs and ramp links, grouped into flights with a bottom and a top;
--   * off-mesh connections: drops from ledges (one way, or two way when low
--     enough to climb) and jumps over gaps;
--   * room links: which rooms reach which, through doors, open floor, stairs or
--     off-mesh links, and whether every room can be reached from an entry.
-- The graph uses the navigation-graph format of modules/navigation.lua, so
-- navigation_graph_check, workspot reports and walkability checks use it.
--
-- It is LocationStudio data. CET cannot write or rebuild REDengine's navmesh, so
-- a generated graph does not change where NPCs walk. The validator below sends a
-- real NPC along the graph's links with AI move commands and records what it
-- actually does.
local NavGen={};NavGen.__index=NavGen
NavGen.VERSION=1

local DEFAULTS={cell=0.25,agent_radius=0.35,agent_height=1.8,max_step=0.35,max_slope=45,max_drop=2.0,max_jump=1.0,max_climb=0,tile=4,door_snap=1.0}
local RANGES={cell={0.1,1},agent_radius={0.1,1.5},agent_height={0.5,4},max_step={0.05,1},max_slope={5,60},max_drop={0,10},max_jump={0,4},max_climb={0,3},tile={0.5,16},door_snap={0.2,3}}
local HINTS={cell='grid cell size (m)',agent_radius='agent radius: floor closer than this to a wall or obstacle is left out (m)',agent_height='headroom the agent needs (m)',
    max_step='highest step the agent walks up without a link (m)',max_slope='steepest walkable slope (degrees)',max_drop='highest ledge a drop link may go down (m); 0 = no drops',
    max_jump='widest gap a jump link may cross (m); 0 = no jumps',max_climb='drops up to this height also get a climb back up (m); 0 = drops are one way',
    tile='largest side of an area polygon (m)',door_snap='how far from a door its floor may be (m)'}
NavGen.DEFAULTS=DEFAULTS;NavGen.RANGES=RANGES
local MAX_COLUMNS=4000000
local MAX_SPANS=250000
local MAX_OFF_MESH=400
local OFF_MESH_SPACING=1.5
local MAX_NODES,MAX_EDGES,MAX_POLYGONS=50000,100000,25000
local MERGE_Z=0.1
local KEY=131072

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function r3(v) return math.floor(v*1000+0.5)/1000 end
local function cross(a,b) return {x=a.y*b.z-a.z*b.y,y=a.z*b.x-a.x*b.z,z=a.x*b.y-a.y*b.x} end
local function dist3(a,b) local x,y,z=a.x-b.x,a.y-b.y,a.z-b.z;return math.sqrt(x*x+y*y+z*z) end
local function dist2(a,b) local x,y=a.x-b.x,a.y-b.y;return math.sqrt(x*x+y*y) end
local function rotate_yaw(p,yaw) local r=math.rad(num(yaw,0));local c,s=math.cos(r),math.sin(r);return {x=p.x*c-p.y*s,y=p.x*s+p.y*c,z=p.z or 0} end
local function hash(str) local h=5381;for i=1,#str do h=(h*33+str:byte(i))%4294967291 end;return string.format('%08x',h) end

local function busy(app)
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and (app.authoring_plans.running or app.authoring_plans:status().recovery_required) then return 'Resolve the running or failed authoring plan first' end
end

function NavGen.normalize_params(p)
    if p~=nil and type(p)~='table' then return nil,'params must be an object' end
    local out={}
    for k in pairs(p or {}) do if DEFAULTS[k]==nil then return nil,'unknown navigation parameter '..tostring(k) end end
    for k,d in pairs(DEFAULTS) do
        local v=p and p[k]
        if v==nil then out[k]=d
        else
            v=tonumber(v);local r=RANGES[k]
            if not v or v<r[1] or v>r[2] then return nil,k..' must be a number from '..r[1]..' to '..r[2] end
            out[k]=v
        end
    end
    if out.tile<out.cell*2 then return nil,'tile must be at least twice the cell size' end
    return out
end

function NavGen.new(app) return setmetatable({app=app,run=nil,clock=0},NavGen) end

function NavGen:parameters()
    local rows={};for k,d in pairs(DEFAULTS) do rows[#rows+1]={name=k,default=d,min=RANGES[k][1],max=RANGES[k][2],hint=HINTS[k]} end
    table.sort(rows,function(a,b) return a.name<b.name end)
    return rows
end

---------------------------------------------------------------------------
-- Scope: what geometry a graph is generated from
---------------------------------------------------------------------------

function NavGen:_scope(a)
    local model=self.app.model;local s={}
    if a.build_id and a.build_id~='' then
        local g=self.app.env_grammar;if not g then return nil,'grammars are unavailable' end
        local rec=g:build(a.build_id);if not rec then return nil,'no grammar build with id '..tostring(a.build_id) end
        local edl=self.app.authoring_plans and self.app.authoring_plans:edl_get(rec.doc)
        if not edl then return nil,'grammar build '..rec.id..' has nothing built (was it removed?)' end
        s.build_id=rec.id;s.premise_id=rec.premise_id;s.room_ids=Util.deepcopy(edl.items and edl.items.room or {});s.object_ids=Util.deepcopy(edl.items and edl.items.object or {})
    elseif (type(a.room_ids)=='table' and #a.room_ids>0) or (a.room_id and a.room_id~='') then
        local ids=type(a.room_ids)=='table' and a.room_ids or {a.room_id}
        s.room_ids={}
        for _,id in ipairs(ids) do if not model:get_room(id) then return nil,'room not found: '..tostring(id) end;s.room_ids[#s.room_ids+1]=id end
    elseif a.premise_id and a.premise_id~='' then
        if not model:get_premise(a.premise_id) then return nil,'premise not found: '..tostring(a.premise_id) end
        s.premise_id=a.premise_id
    elseif a.all==true then s.all=true
    else return nil,'give premise_id, room_ids, build_id or all=true' end
    return s
end

-- Premises, rooms and objects a scope covers.
function NavGen:_scope_sets(scope)
    local model=self.app.model
    local rooms,objects,premises={},{},{}
    for _,id in ipairs(scope.room_ids or {}) do rooms[id]=true;local r=model:get_room(id);if r and r.premise_id then premises[r.premise_id]=true end end
    for _,id in ipairs(scope.object_ids or {}) do objects[id]=true end
    if scope.premise_id then premises[scope.premise_id]=true end
    for _,r in ipairs(model.data.rooms or {}) do
        if scope.all or (scope.premise_id and r.premise_id==scope.premise_id and not scope.build_id) then rooms[r.id]=true end
    end
    return rooms,objects,premises
end

local function in_scope(o,scope,rooms,objects,premises)
    if scope.all then return true end
    if objects[o.id] or (o.room_id and rooms[o.room_id]) then return true end
    if scope.premise_id and not scope.build_id and o.premise_id==scope.premise_id then return true end
    return false
end

-- A hand-placed collider's box: its size around its position (conservative, yaw ignored).
local function collider_box(o)
    local p=o.transform and o.transform.position;if not p then return nil end
    local s=o.size or {};local hx=math.max(num(s.x,0.5),num(s.y,0.5))/2;local hz=num(s.z,0.5)/2
    return {min={x=num(p.x,0)-hx,y=num(p.y,0)-hx,z=num(p.z,0)-hz},max={x=num(p.x,0)+hx,y=num(p.y,0)+hx,z=num(p.z,0)+hz}}
end

-- Objects whose walkable surfaces make them part of the floor. Solid stairs and
-- ramps fill the space under their treads; other walkable objects (platforms,
-- open stairs) are obstacles by their bounds.
local SOLID_GENERATORS={stairs=true,ramp=true}
local function walk_kind(o)
    local cfg=o and o.metadata and o.metadata.procedural
    if cfg and SOLID_GENERATORS[cfg.generator] and not (type(cfg.params)=='table' and cfg.params.solid==false) then return 'solid' end
    return 'open'
end

function NavGen:_obstacles(scope,rooms,objects,premises,walk_owner)
    local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local md=o.metadata or {}
        local near=in_scope(o,scope,rooms,objects,premises) or (o.premise_id and premises[o.premise_id])
        local skip=o.enabled==false or not near or md.room_generator or md.collision_gen or o.kind=='decal' or walk_owner[o.id]=='solid'
        if not skip then
            local box
            if o.kind=='collision' or md.collision then box=collider_box(o)
            elseif self.app.bounds_gen and md.procedural then box=self.app.bounds_gen:world_aabb(o)
            elseif self.app.asset_bounds and type(md.asset_bounds)=='table' then local r=self.app.asset_bounds:world_aabb(o.id);box=r and r.aabb end
            if not box and o.transform and o.transform.position then
                local p=o.transform.position;local x,y,z=num(p.x,0),num(p.y,0),num(p.z,0)
                local lit=md.light~=nil or o.kind=='light'
                box={min={x=x-0.2,y=y-0.2,z=lit and z-0.2 or z},max={x=x+0.2,y=y+0.2,z=z+(lit and 0.2 or 0.4)}}
            end
            if box then out[#out+1]={min=box.min,max=box.max,owner=o.id,name=o.name} end
        end
    end
    return out
end

-- Generated rooms a scope covers, with their doors in world space.
function NavGen:_doors(rooms)
    local model=self.app.model;local out={}
    for _,rec in ipairs(model.data.generated_rooms or {}) do
        local room=model:get_room(rec.id)
        if room and rooms[rec.id] and rec.spec then
            local T=num(rec.spec.wall_thickness,0.2);local yaw=room.transform and room.transform.rotation and room.transform.rotation.yaw or 0
            local origin=room.transform and room.transform.position or {x=0,y=0,z=0}
            local sockets={};for _,s in ipairs(rec.sockets or {}) do sockets[s.id]=s end
            for _,p in ipairs(rec.portals or {}) do
                if p.kind=='door' then
                    local floor_z=sockets[p.id] and sockets[p.id].position.z or (p.sill or 0)
                    local c=rotate_yaw({x=p.center.x,y=p.center.y,z=0},yaw);local n=rotate_yaw(p.normal,yaw)
                    out[#out+1]={room_id=room.id,room_name=room.name,portal=p.id,connects=p.connects,width=num(p.width,1),height=num(p.height,2.1),thickness=T,
                        center={x=num(origin.x,0)+c.x,y=num(origin.y,0)+c.y,z=num(origin.z,0)+floor_z},normal={x=n.x,y=n.y,z=0}}
                end
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Segments (walls and door portals) for crossing tests
---------------------------------------------------------------------------

local BUCKET=2
local function seg_hash() return {cells={},list={},stamp=0} end
local function seg_add(h,seg)
    h.list[#h.list+1]=seg;seg.mark=0
    local x0,x1=math.floor(math.min(seg.a.x,seg.b.x)/BUCKET),math.floor(math.max(seg.a.x,seg.b.x)/BUCKET)
    local y0,y1=math.floor(math.min(seg.a.y,seg.b.y)/BUCKET),math.floor(math.max(seg.a.y,seg.b.y)/BUCKET)
    for i=x0,x1 do for j=y0,y1 do local k=i..':'..j;local b=h.cells[k];if not b then b={};h.cells[k]=b end;b[#b+1]=seg end end
end
local function orient(a,b,c) return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) end
local function crosses(p,q,a,b)
    local d1,d2=orient(a,b,p),orient(a,b,q);local d3,d4=orient(p,q,a),orient(p,q,b)
    return ((d1>0 and d2<0) or (d1<0 and d2>0)) and ((d3>0 and d4<0) or (d3<0 and d4>0))
end
-- The first segment the line p->q crosses whose height range overlaps [z0, z1].
local function seg_hit(h,p,q,z0,z1)
    h.stamp=h.stamp+1
    local x0,x1=math.floor(math.min(p.x,q.x)/BUCKET),math.floor(math.max(p.x,q.x)/BUCKET)
    local y0,y1=math.floor(math.min(p.y,q.y)/BUCKET),math.floor(math.max(p.y,q.y)/BUCKET)
    for i=x0,x1 do for j=y0,y1 do
        for _,seg in ipairs(h.cells[i..':'..j] or {}) do
            if seg.mark~=h.stamp then
                seg.mark=h.stamp
                if seg.z1>z0 and seg.z0<z1 and crosses(p,q,seg.a,seg.b) then return seg end
            end
        end
    end end
    return nil
end

---------------------------------------------------------------------------
-- Generation
---------------------------------------------------------------------------

local function surface_class(s)
    if s.tag=='stairs' then return 'stairs' end
    if s.tag=='ramp' or s.normal.z<0.9986 then return 'ramp' end
    return 'floor'
end
local function plane_z(s,x,y) return s.center.z-(s.normal.x*(x-s.center.x)+s.normal.y*(y-s.center.y))/s.normal.z end
local function world_rect(s)
    local v=cross(s.normal,s.u);local hu,hv=s.size.u/2,s.size.v/2
    local lo,hi={x=math.huge,y=math.huge,z=math.huge},{x=-math.huge,y=-math.huge,z=-math.huge}
    for _,a in ipairs({-1,1}) do for _,b in ipairs({-1,1}) do
        local p={x=s.center.x+s.u.x*hu*a+v.x*hv*b,y=s.center.y+s.u.y*hu*a+v.y*hv*b,z=s.center.z+s.u.z*hu*a+v.z*hv*b}
        for _,k in ipairs({'x','y','z'}) do lo[k]=math.min(lo[k],p[k]);hi[k]=math.max(hi[k],p[k]) end
    end end
    return lo,hi,v
end

function NavGen:_room_name(id)
    local r=id and self.app.model:get_room(id);return r and r.name or nil
end

-- The whole computation. Pure apart from reading the project.
function NavGen:_compute(scope,P,a)
    a=a or {}
    local app=self.app;local model=app.model
    if not app.surfaces then return nil,'semantic surfaces are unavailable' end
    local rooms,objects,premises=self:_scope_sets(scope)
    local pool=app.surfaces:collect({premise_id=(not scope.build_id) and scope.premise_id or nil,room_ids=scope.room_ids,object_ids=scope.object_ids})
    if scope.build_id then local kept={};for _,s in ipairs(pool) do if (s.object_id and objects[s.object_id]) or (s.room_id and rooms[s.room_id]) then kept[#kept+1]=s end end;pool=kept end
    local cos_slope=math.cos(math.rad(P.max_slope))
    local walk,overhead,walls={},{},seg_hash()
    local warnings={};local skipped={too_steep=0}
    local walk_owner={}
    for _,s in ipairs(pool) do
        if s.orientation=='up' and Surfaces.matches(s,{tags='walkable'}) then
            if s.normal.z<cos_slope then skipped.too_steep=skipped.too_steep+1
            else
                s.class=surface_class(s);walk[#walk+1]=s
                if s.object_id then local o=model:get_object(s.object_id);walk_owner[s.object_id]=o and walk_kind(o) or 'open' end
            end
        elseif s.orientation=='down' then overhead[#overhead+1]=s
        elseif s.orientation=='side' then
            local lo,hi,v=world_rect(s)
            local h=s.u;local half=s.size.u/2
            if math.abs(s.u.z)>0.5 then h=v;half=s.size.v/2 end
            local l=math.sqrt(h.x*h.x+h.y*h.y)
            if l>1e-6 and half>0.01 then
                local hx,hy=h.x/l*half,h.y/l*half
                seg_add(walls,{a={x=s.center.x-hx,y=s.center.y-hy},b={x=s.center.x+hx,y=s.center.y+hy},z0=lo.z,z1=hi.z,kind='wall',tag=s.tag,object_id=s.object_id})
            end
        end
    end
    if skipped.too_steep>0 then warnings[#warnings+1]=skipped.too_steep..' walkable surface(s) steeper than '..P.max_slope..' degrees were left out' end
    if #walk==0 then return nil,'no walkable surfaces in scope: generate rooms, stairs or ramps first (surfaces tagged floor, platform, stairs, ramp, ground...)' end
    -- Door portals: walking straight across a door line is replaced by the door's own links.
    local doors=self:_doors(rooms)
    for _,d in ipairs(doors) do
        local t={x=-d.normal.y,y=d.normal.x};local hw=d.width/2
        seg_add(walls,{a={x=d.center.x-t.x*hw,y=d.center.y-t.y*hw},b={x=d.center.x+t.x*hw,y=d.center.y+t.y*hw},z0=d.center.z-0.5,z1=d.center.z+d.height,kind='portal'})
    end
    -- Grid.
    local cell=P.cell
    local lo,hi={x=math.huge,y=math.huge},{x=-math.huge,y=-math.huge}
    for _,s in ipairs(walk) do local a0,b0=world_rect(s);s.lo=a0;s.hi=b0;lo.x=math.min(lo.x,a0.x);lo.y=math.min(lo.y,a0.y);hi.x=math.max(hi.x,b0.x);hi.y=math.max(hi.y,b0.y) end
    local ox,oy=math.floor(lo.x/cell)*cell-cell,math.floor(lo.y/cell)*cell-cell
    local nx,ny=math.ceil((hi.x-ox)/cell)+2,math.ceil((hi.y-oy)/cell)+2
    if nx*ny>MAX_COLUMNS or nx>=KEY or ny>=KEY then return nil,string.format('the area is too large for a %.2f m grid (%d x %d cells); use a larger cell',cell,nx,ny) end
    local function cx(ix) return ox+(ix+0.5)*cell end
    local function cy(iy) return oy+(iy+0.5)*cell end
    local cols={};local spans={}
    for si,s in ipairs(walk) do
        local ix0,ix1=math.floor((s.lo.x-ox)/cell),math.floor((s.hi.x-ox)/cell)
        local iy0,iy1=math.floor((s.lo.y-oy)/cell),math.floor((s.hi.y-oy)/cell)
        for ix=ix0,ix1 do for iy=iy0,iy1 do
            local x,y=cx(ix),cy(iy);local z=plane_z(s,x,y)
            if Surfaces.contains(s,{x=x,y=y,z=z},0) then
                local key=ix*KEY+iy;local col=cols[key]
                if not col then col={};cols[key]=col end
                local merged=false
                for _,j in ipairs(col) do local q=spans[j]
                    if math.abs(q.z-z)<MERGE_Z then
                        -- Keep the higher span; on a tie prefer stairs/ramps, which carry the transition.
                        if z>q.z+1e-6 or (math.abs(z-q.z)<=1e-6 and s.class~='floor' and walk[q.s].class=='floor') then q.z=z;q.s=si end
                        merged=true;break
                    end
                end
                if not merged then
                    if #spans>=MAX_SPANS then return nil,'too many grid cells ('..MAX_SPANS..'); use a larger cell or a smaller scope' end
                    spans[#spans+1]={ix=ix,iy=iy,z=z,s=si,key=key};col[#col+1]=#spans
                end
            end
        end end
    end
    -- Overhead: other walkable spans and ceiling-like surfaces less than agent_height above.
    local under_solid=0
    for _,col in pairs(cols) do
        for _,i in ipairs(col) do
            local q=spans[i]
            for _,j in ipairs(col) do
                if j~=i then local o=spans[j];local own=walk[o.s].object_id
                    if o.z>q.z+MERGE_Z*0.5 and (o.z<q.z+P.agent_height or (own and own~=walk[q.s].object_id and walk_owner[own]=='solid')) then
                        q.blocked='overhead';if walk_owner[own or '']=='solid' then under_solid=under_solid+1 end;break
                    end
                end
            end
        end
    end
    for _,s in ipairs(overhead) do
        local a0,b0=world_rect(s)
        local ix0,ix1=math.floor((a0.x-ox)/cell),math.floor((b0.x-ox)/cell)
        local iy0,iy1=math.floor((a0.y-oy)/cell),math.floor((b0.y-oy)/cell)
        if (ix1-ix0+1)*(iy1-iy0+1)<=200000 then
            for ix=ix0,ix1 do for iy=iy0,iy1 do
                local col=cols[ix*KEY+iy]
                if col then
                    local x,y=cx(ix),cy(iy)
                    for _,i in ipairs(col) do local q=spans[i]
                        if not q.blocked and math.abs(s.normal.z)>1e-3 then
                            local z=plane_z(s,x,y)
                            if z>q.z+0.05 and z<q.z+P.agent_height and Surfaces.contains(s,{x=x,y=y,z=z},0) then q.blocked='low_ceiling' end
                        end
                    end
                end
            end end
        end
    end
    -- Obstacles, grown by the agent radius.
    local obstacles=self:_obstacles(scope,rooms,objects,premises,walk_owner)
    for oi,ob in ipairs(obstacles) do
        local r=P.agent_radius
        local ix0,ix1=math.floor((ob.min.x-r-ox)/cell),math.floor((ob.max.x+r-ox)/cell)
        local iy0,iy1=math.floor((ob.min.y-r-oy)/cell),math.floor((ob.max.y+r-oy)/cell)
        if (ix1-ix0+1)*(iy1-iy0+1)<=200000 then
            for ix=ix0,ix1 do for iy=iy0,iy1 do
                local col=cols[ix*KEY+iy]
                if col then
                    local x,y=cx(ix),cy(iy)
                    local dx=math.max(ob.min.x-x,0,x-ob.max.x);local dy=math.max(ob.min.y-y,0,y-ob.max.y)
                    if dx*dx+dy*dy<=r*r then
                        for _,i in ipairs(col) do local q=spans[i]
                            if not q.blocked and walk[q.s].object_id~=ob.owner and ob.max.z>q.z+P.max_step and ob.min.z<q.z+P.agent_height then q.obstacle=oi end
                        end
                    end
                end
            end end
        end
    end
    -- Structural links (ignoring obstacles): step height, walls and door portals.
    local DIRS={{1,0},{-1,0},{0,1},{0,-1}}
    local links={};local portal_cuts=0
    local function allowed_dz(a,b)
        local ca,cb=walk[a.s].class,walk[b.s].class
        if ca=='stairs' or cb=='stairs' then return P.max_step+cell end
        if ca=='ramp' or cb=='ramp' then return P.max_step+cell*math.tan(math.rad(P.max_slope)) end
        return P.max_step
    end
    for i,q in ipairs(spans) do
        links[i]={}
        if q.blocked~='overhead' and q.blocked~='low_ceiling' then
            for d,dir in ipairs(DIRS) do
                local col=cols[(q.ix+dir[1])*KEY+q.iy+dir[2]]
                if col then
                    local best,bd
                    for _,j in ipairs(col) do local o=spans[j]
                        if o.blocked~='overhead' and o.blocked~='low_ceiling' then
                            local dz=math.abs(o.z-q.z)
                            if dz<=allowed_dz(q,o) and (not bd or dz<bd) then best,bd=j,dz end
                        end
                    end
                    if best then
                        local o=spans[best];local zl=math.max(q.z,o.z)
                        local seg=seg_hit(walls,{x=cx(q.ix),y=cy(q.iy)},{x=cx(o.ix),y=cy(o.iy)},zl+P.max_step,zl+P.agent_height)
                        if not seg then links[i][d]=best elseif seg.kind=='portal' then portal_cuts=portal_cuts+1 end
                    end
                end
            end
        end
    end
    -- Erosion: keep floor at least agent_radius from any edge of the structure.
    local dist={};local queue={};local head=1
    for i,q in ipairs(spans) do
        if q.blocked~='overhead' and q.blocked~='low_ceiling' then
            local n=0;for d=1,4 do if links[i][d] then n=n+1 end end
            if n<4 then dist[i]=0;queue[#queue+1]=i end
        end
    end
    while head<=#queue do
        local i=queue[head];head=head+1
        for d=1,4 do local j=links[i][d];if j and dist[j]==nil then dist[j]=dist[i]+1;queue[#queue+1]=j end end
    end
    local kept={};local kept_count=0
    for i,q in ipairs(spans) do
        if q.blocked~='overhead' and q.blocked~='low_ceiling' then
            local d=dist[i] or math.huge
            if not q.obstacle and (d+0.5)*cell>=P.agent_radius-1e-6 then kept[i]=true;kept_count=kept_count+1 elseif not q.obstacle then q.blocked='edge' end
        end
    end
    local function klink(i,d) local j=links[i][d];if j and kept[i] and kept[j] then return j end end
    -- Pockets too small for the agent to stand in (corners between furniture) are dropped.
    local pockets=0;local seen={}
    local min_cells=math.max(2,math.ceil((2*P.agent_radius)^2/(cell*cell)-1e-9))
    for i in pairs(kept) do
        if not seen[i] then
            local group={i};seen[i]=true;local h=1
            while h<=#group do local u=group[h];h=h+1;for d=1,4 do local j=klink(u,d);if j and not seen[j] then seen[j]=true;group[#group+1]=j end end end
            if #group<min_cells then for _,j in ipairs(group) do spans[j].blocked='pocket' end;pockets=pockets+1 end
        end
    end
    for i,q in ipairs(spans) do if q.blocked=='pocket' and kept[i] then kept[i]=nil;kept_count=kept_count-1 end end
    -- Areas: rectangles of kept cells on one surface, at most `tile` on a side.
    local rect_of={};local rects={}
    local maxc=math.max(1,math.floor(P.tile/cell+1e-9))
    local order={};for i in pairs(kept) do order[#order+1]=i end
    table.sort(order,function(a,b) local p,q=spans[a],spans[b];if p.s~=q.s then return p.s<q.s end;if p.iy~=q.iy then return p.iy<q.iy end;return p.ix<q.ix end)
    for _,i in ipairs(order) do
        if not rect_of[i] then
            local q=spans[i];local row={i}
            while #row<maxc do local j=klink(row[#row],1);if j and spans[j].s==q.s and not rect_of[j] then row[#row+1]=j else break end end
            local rows={row}
            while #rows<maxc do
                local prev=rows[#rows];local nextrow={}
                for k,j in ipairs(prev) do local up=klink(j,3);if up and spans[up].s==q.s and not rect_of[up] and (k==1 or klink(nextrow[k-1],1)==up) then nextrow[k]=up else nextrow=nil;break end end
                if nextrow and #nextrow==#row then rows[#rows+1]=nextrow else break end
            end
            local id=#rects+1;local cells=0
            for _,r in ipairs(rows) do for _,j in ipairs(r) do rect_of[j]=id;cells=cells+1 end end
            local s=walk[q.s]
            local ix0,iy0=q.ix,q.iy;local ix1,iy1=q.ix+#row-1,q.iy+#rows-1
            local x,y=ox+(ix0+ix1+1)/2*cell,oy+(iy0+iy1+1)/2*cell
            rects[id]={id=id,s=q.s,class=s.class,tag=s.tag,room_id=s.room_id,object_id=s.object_id,ix0=ix0,iy0=iy0,ix1=ix1,iy1=iy1,cells=cells,
                center={x=r3(x),y=r3(y),z=r3(plane_z(s,x,y))}}
        end
    end
    -- Graph.
    local nodes,edges,polygons={},{},{}
    local node_of_rect={}
    local function add_node(n) nodes[#nodes+1]=n;n.index=#nodes;return n end
    for _,r in ipairs(rects) do
        local rn=self:_room_name(r.room_id)
        local label=(rn and (rn..' ') or '')..r.tag..' '..r.id
        local n=add_node({id='a'..r.id,name=label,position=r.center,surface=r.tag,source='generated',kind='area',class=r.class,room_id=r.room_id,object_id=r.object_id,area=r3(r.cells*cell*cell)})
        node_of_rect[r.id]=n
        local s=walk[r.s];local xs={ox+r.ix0*cell,ox+(r.ix1+1)*cell};local ys={oy+r.iy0*cell,oy+(r.iy1+1)*cell}
        local verts={}
        for _,c in ipairs({{1,1},{2,1},{2,2},{1,2}}) do local x,y=xs[c[1]],ys[c[2]];verts[#verts+1]={x=r3(x),y=r3(y),z=r3(plane_z(s,x,y))} end
        polygons[#polygons+1]={id='p'..r.id,vertices=verts,surface=r.tag,source='generated',class=r.class,room_id=r.room_id,node_id=n.id}
    end
    local edge_pairs={}
    local function add_edge(e) edges[#edges+1]=e;e.id=e.id or ('e'..#edges);if e.enabled==nil then e.enabled=true end;e.one_way=e.one_way==true;e.notes=e.notes or '';return e end
    local FACTOR={walk=1,stairs=1.5,ramp=1.2}
    local function area_kind(r1,r2)
        if r1.class=='stairs' or r2.class=='stairs' then return 'stairs' end
        if r1.class=='ramp' or r2.class=='ramp' then return 'ramp' end
        return 'walk'
    end
    for _,i in ipairs(order) do
        for d=1,4 do local j=klink(i,d)
            if j then
                local a1,b1=rect_of[i],rect_of[j]
                if a1~=b1 then
                    local k=math.min(a1,b1)..'-'..math.max(a1,b1)
                    if not edge_pairs[k] then
                        local r1,r2=rects[math.min(a1,b1)],rects[math.max(a1,b1)]
                        local kind=area_kind(r1,r2)
                        edge_pairs[k]=add_edge({from=node_of_rect[r1.id].id,to=node_of_rect[r2.id].id,kind=kind,cost=r3(math.max(0.01,dist3(r1.center,r2.center)*FACTOR[kind])),rooms={r1.room_id,r2.room_id}})
                    end
                end
            end
        end
    end
    -- Nearest kept span to a point.
    local function snap(p,reach,dz)
        local best,bd;local n=math.ceil(reach/cell)
        local ix,iy=math.floor((p.x-ox)/cell),math.floor((p.y-oy)/cell)
        for i=ix-n,ix+n do for j=iy-n,iy+n do
            for _,k in ipairs(cols[i*KEY+j] or {}) do
                if kept[k] then local q=spans[k];local d=dist2(p,{x=cx(i),y=cy(j)})
                    if d<=reach and math.abs(q.z-p.z)<=dz and (not bd or d<bd) then best,bd=k,d end
                end
            end
        end end
        return best,bd
    end
    local function obstacle_near(p,reach)
        local n=math.ceil(reach/cell);local ix,iy=math.floor((p.x-ox)/cell),math.floor((p.y-oy)/cell);local found={}
        for i=ix-n,ix+n do for j=iy-n,iy+n do for _,k in ipairs(cols[i*KEY+j] or {}) do local q=spans[k]
            if q.obstacle and math.abs(q.z-p.z)<=P.max_step then local ob=obstacles[q.obstacle];found[ob.owner]=ob.name or ob.owner end
        end end end
        local out={};for id,name in pairs(found) do out[#out+1]={object_id=id,name=name} end
        table.sort(out,function(x,y) return x.object_id<y.object_id end)
        return out
    end
    -- Doors. A door shared by two rooms appears in both; they merge by position.
    local door_list={};local by_pos={}
    for _,d in ipairs(doors) do
        local key=math.floor(d.center.x/0.3+0.5)..':'..math.floor(d.center.y/0.3+0.5)..':'..math.floor(d.center.z/0.5+0.5)
        local rec=by_pos[key]
        if not rec then
            rec={id='door'..(#door_list+1),center=d.center,normal=d.normal,width=d.width,height=d.height,thickness=d.thickness,rooms={},portals={}};by_pos[key]=rec;door_list[#door_list+1]=rec
        else rec.width=math.min(rec.width,d.width);rec.height=math.min(rec.height,d.height);rec.thickness=math.max(rec.thickness,d.thickness) end
        rec.rooms[#rec.rooms+1]=d.room_id;rec.portals[#rec.portals+1]={room_id=d.room_id,portal=d.portal}
    end
    local door_rows={}
    for _,door in ipairs(door_list) do
        local off=door.thickness/2+P.agent_radius+cell
        local sides={}
        for _,sgn in ipairs({1,-1}) do
            local p={x=door.center.x+door.normal.x*off*sgn,y=door.center.y+door.normal.y*off*sgn,z=door.center.z}
            local k=snap(p,P.door_snap,P.max_step+0.15)
            sides[#sides+1]={probe=p,span=k,rect=k and rect_of[k] or nil}
        end
        local node=add_node({id=door.id,name='Door '..door.id:sub(5)..(door.rooms[1] and (' ('..(self:_room_name(door.rooms[1]) or door.rooms[1])..(door.rooms[2] and (' / '..(self:_room_name(door.rooms[2]) or door.rooms[2])) or '')..')') or ''),
            position={x=r3(door.center.x),y=r3(door.center.y),z=r3(door.center.z)},surface='door',source='generated',kind='door',room_ids=Util.deepcopy(door.rooms),width=door.width,height=door.height})
        local narrow=door.width<2*P.agent_radius+0.05
        local low=door.height<P.agent_height
        local connected={}
        for _,side in ipairs(sides) do
            if side.rect then
                local r=rects[side.rect]
                local e=add_edge({from=node.id,to=node_of_rect[r.id].id,kind='door',cost=r3(math.max(0.01,dist3(node.position,r.center))),door_id=door.id,rooms={r.room_id},
                    enabled=not (narrow or low) and true or false,notes=narrow and 'door narrower than the agent' or (low and 'door lower than the agent' or '')})
                connected[#connected+1]={rect=r.id,room_id=r.room_id,edge_id=e.id,node_id=node_of_rect[r.id].id}
            end
        end
        local status
        if narrow then status='too_narrow' elseif low then status='too_low'
        elseif #connected==2 then status='connected'
        elseif #connected==1 then
            -- One side has floor. Outside a room with no neighbour it is an exit; otherwise something blocks it.
            local missing=sides[1].rect and sides[2] or sides[1]
            local blockers=obstacle_near(missing.probe,P.door_snap)
            if #blockers>0 then status='blocked';door.blockers=blockers
            elseif #door.rooms>1 then status='blocked'
            else status='exit' end
        else status='blocked';door.blockers=obstacle_near(door.center,P.door_snap+door.thickness) end
        door.status=status;door.node_id=node.id;door.sides=connected
        door_rows[#door_rows+1]={id=door.id,node_id=node.id,status=status,rooms=Util.deepcopy(door.rooms),width=door.width,height=door.height,position=Util.deepcopy(node.position),
            sides=connected,blockers=door.blockers}
    end
    -- Off-mesh links: drops from ledges and jumps over gaps, from the edge of the kept floor.
    local off_mesh={};local off_pairs={}
    if P.max_drop>0 or P.max_jump>0 then
        local ANG={}
        for k=0,7 do local t=k*math.pi/4;ANG[#ANG+1]={math.cos(t),math.sin(t)} end
        local reach=math.max(P.max_jump+2*P.agent_radius+cell,2*P.agent_radius+3*cell)
        local function spans_at(x,y) return cols[math.floor((x-ox)/cell)*KEY+math.floor((y-oy)/cell)] end
        for _,i in ipairs(order) do
            local nk=0;for d=1,4 do if klink(i,d) then nk=nk+1 end end
            -- Off-mesh links start from ledges of floor and platforms, not from the sides of stairs and ramps.
            if nk<4 and walk[spans[i].s].class=='floor' then
                local q=spans[i];local x0,y0=cx(q.ix),cy(q.iy)
                for _,dir in ipairs(ANG) do
                    local gap,stop=false,false
                    local cands={}
                    local steps=math.floor(reach/cell)
                    for st=1,steps do
                        local d=st*cell;local x,y=x0+dir[1]*d,y0+dir[2]*d
                        local col=spans_at(x,y)
                        local level=false
                        for _,j in ipairs(col or {}) do local o=spans[j]
                            if o.z>q.z+P.max_step and o.z<q.z+P.agent_height then stop=true
                            elseif math.abs(o.z-q.z)<=P.max_step then
                                level=true
                                if kept[j] then
                                    if rect_of[j]~=rect_of[i] and gap and P.max_jump>0 and d-2*P.agent_radius<=P.max_jump then cands[#cands+1]={j,'jump',d} end
                                    stop=true
                                elseif o.obstacle then stop=true end
                            elseif o.z<q.z and kept[j] and not cands.drop and q.z-o.z<=P.max_drop and P.max_drop>0 and d>=2*P.agent_radius-1e-6 then
                                cands.drop=true;cands[#cands+1]={j,'drop',d}
                            end
                        end
                        if not level then gap=true end
                        if stop then break end
                    end
                    for _,c in ipairs(cands) do
                        local found,kind=c[1],c[2]
                        local o=spans[found];local p1={x=x0,y=y0};local p2={x=cx(o.ix),y=cy(o.iy)}
                        local zl=math.min(q.z,o.z)
                        if not seg_hit(walls,p1,p2,zl+P.max_step,math.max(q.z,o.z)+P.agent_height) then
                            local ra,rb=rect_of[i],rect_of[found]
                            local pk=kind=='jump' and (math.min(ra,rb)..'-'..math.max(ra,rb)) or (ra..'>'..rb)
                            local d=dist3({x=p1.x,y=p1.y,z=q.z},{x=p2.x,y=p2.y,z=o.z})
                            local prev=off_pairs[pk]
                            if not prev or d<prev.d then off_pairs[pk]={d=d,kind=kind,from=i,to=found} end
                        end
                    end
                end
            end
        end
        local keys={};for k in pairs(off_pairs) do keys[#keys+1]=k end
        table.sort(keys,function(x,y) local a1,b1=off_pairs[x],off_pairs[y];if math.abs(a1.d-b1.d)>1e-9 then return a1.d<b1.d end;return x<y end)
        -- One link per stretch of ledge: skip a link that starts and ends near one already made.
        local accepted={}
        local function near(c)
            local s1,t1=spans[c.from],spans[c.to]
            for _,o in ipairs(accepted) do
                if o.kind==c.kind and dist3({x=cx(s1.ix),y=cy(s1.iy),z=s1.z},o.a)<OFF_MESH_SPACING and dist3({x=cx(t1.ix),y=cy(t1.iy),z=t1.z},o.b)<OFF_MESH_SPACING then return true end
            end
        end
        for _,k in ipairs(keys) do
            if #off_mesh>=MAX_OFF_MESH then warnings[#warnings+1]='off-mesh links capped at '..MAX_OFF_MESH;break end
            local c=off_pairs[k];local ra,rb=rect_of[c.from],rect_of[c.to]
            local ek=math.min(ra,rb)..'-'..math.max(ra,rb)
            if not (c.kind=='jump' and edge_pairs[ek]) and not near(c) then
                local sa,sb=spans[c.from],spans[c.to]
                accepted[#accepted+1]={kind=c.kind,a={x=cx(sa.ix),y=cy(sa.iy),z=sa.z},b={x=cx(sb.ix),y=cy(sb.iy),z=sb.z}}
                local a1,b1=spans[c.from],spans[c.to]
                local n1=add_node({id='l'..(#off_mesh*2+1),name='Ledge '..(#off_mesh+1)..' start',position={x=r3(cx(a1.ix)),y=r3(cy(a1.iy)),z=r3(a1.z)},surface=walk[a1.s].tag,source='generated',kind='ledge',room_id=walk[a1.s].room_id})
                local n2=add_node({id='l'..(#off_mesh*2+2),name='Ledge '..(#off_mesh+1)..' end',position={x=r3(cx(b1.ix)),y=r3(cy(b1.iy)),z=r3(b1.z)},surface=walk[b1.s].tag,source='generated',kind='ledge',room_id=walk[b1.s].room_id})
                local rise=a1.z-b1.z
                local climb=c.kind=='drop' and P.max_climb>0 and rise<=P.max_climb
                local sub=c.kind=='jump' and 'jump' or (climb and 'drop_climb' or 'drop')
                add_edge({from=node_of_rect[ra].id,to=n1.id,kind='walk',cost=r3(math.max(0.01,dist3(rects[ra].center,n1.position)))})
                add_edge({from=n2.id,to=node_of_rect[rb].id,kind='walk',cost=r3(math.max(0.01,dist3(rects[rb].center,n2.position)))})
                local e=add_edge({from=n1.id,to=n2.id,kind=c.kind=='jump' and 'jump' or 'off_mesh',off_mesh=sub,one_way=c.kind=='drop' and not climb,
                    cost=r3(math.max(0.01,c.d*(c.kind=='jump' and 3 or 2))),notes=sub=='drop' and string.format('drop %.2f m',rise) or (sub=='drop_climb' and string.format('drop / climb %.2f m',rise) or string.format('jump %.2f m gap',math.max(0,c.d-2*P.agent_radius))),rooms={rects[ra].room_id,rects[rb].room_id}})
                off_mesh[#off_mesh+1]={id=e.id,kind=sub,from=n1.id,to=n2.id,from_area=node_of_rect[ra].id,to_area=node_of_rect[rb].id,rise=r3(rise),length=r3(c.d),rooms={rects[ra].room_id,rects[rb].room_id},one_way=e.one_way}
            end
        end
    end
    -- Stairs flights and ramps: connected runs of stairs (ramp) areas and where they meet other floor.
    local flights={}
    for _,class in ipairs({'stairs','ramp'}) do
        local parent={}
        local function find(x) while parent[x]~=x do parent[x]=parent[parent[x]];x=parent[x] end;return x end
        for _,r in ipairs(rects) do if r.class==class then parent[r.id]=r.id end end
        local entries={}
        for _,e in ipairs(edges) do
            local ra,rb=tonumber(e.from:match('^a(%d+)$')),tonumber(e.to:match('^a(%d+)$'))
            if ra and rb then
                if parent[ra] and parent[rb] then local x,y=find(ra),find(rb);if x~=y then parent[x]=y end
                elseif parent[ra] or parent[rb] then entries[#entries+1]={inside=parent[ra] and ra or rb,outside=parent[ra] and rb or ra,edge=e} end
            end
        end
        local groups={};local ids={}
        for id in pairs(parent) do local root=find(id);if not groups[root] then groups[root]={rects={},entries={}};ids[#ids+1]=root end;table.insert(groups[root].rects,id) end
        table.sort(ids)
        for _,en in ipairs(entries) do table.insert(groups[find(en.inside)].entries,en) end
        for _,root in ipairs(ids) do
            local g=groups[root];local zlo,zhi=math.huge,-math.huge
            for _,id in ipairs(g.rects) do local z=rects[id].center.z;zlo=math.min(zlo,z);zhi=math.max(zhi,z) end
            local bottom,top
            for _,en in ipairs(g.entries) do local r=rects[en.outside];if not bottom or r.center.z<rects[bottom.outside].center.z then bottom=en end;if not top or r.center.z>rects[top.outside].center.z then top=en end end
            local rise=bottom and top and rects[top.outside].center.z-rects[bottom.outside].center.z or 0
            local status=(#g.entries==0 and 'isolated') or ((rise>=math.max(P.max_step,(zhi-zlo)*0.5)) and 'connected') or 'one_end'
            local rooms={}
            for _,en in ipairs(g.entries) do en.edge.flight='f'..(#flights+1) end
            flights[#flights+1]={id='f'..(#flights+1),kind=class,areas=#g.rects,status=status,z_min=r3(zlo),z_max=r3(zhi),rise=r3(rise),
                bottom=bottom and {node_id=node_of_rect[bottom.outside].id,position=Util.deepcopy(rects[bottom.outside].center),room_id=rects[bottom.outside].room_id,edge_id=bottom.edge.id} or nil,
                top=top and {node_id=node_of_rect[top.outside].id,position=Util.deepcopy(rects[top.outside].center),room_id=rects[top.outside].room_id,edge_id=top.edge.id} or nil,
                object_id=rects[g.rects[1]].object_id,rooms=rooms}
        end
    end
    -- Room links.
    local room_links={};local link_idx={}
    local function link(a1,b1,kind,via)
        if a1==b1 then return end
        local x,y=a1 or '',b1 or ''
        if x>y then x,y=y,x end
        local k=x..'|'..y..'|'..kind
        local l=link_idx[k]
        if not l then l={from=x~='' and x or nil,to=y~='' and y or nil,kind=kind,via={},from_name=self:_room_name(x),to_name=self:_room_name(y)};link_idx[k]=l;room_links[#room_links+1]=l end
        if via and #l.via<8 then l.via[#l.via+1]=via end
    end
    for _,d in ipairs(door_rows) do
        if #d.sides==2 then link(d.sides[1].room_id,d.sides[2].room_id,'door',d.id)
        elseif d.status=='exit' then link(d.rooms[1],nil,'exit',d.id) end
    end
    for _,e in ipairs(edges) do
        if e.rooms and (e.kind=='walk' or e.kind=='stairs' or e.kind=='ramp') and e.rooms[1]~=e.rooms[2] and not e.door_id then link(e.rooms[1],e.rooms[2],e.kind=='walk' and 'open' or e.kind,e.flight or e.id) end
    end
    for _,f in ipairs(flights) do if f.bottom and f.top then link(f.bottom.room_id,f.top.room_id,f.kind,f.id) end end
    for _,o in ipairs(off_mesh) do link(o.rooms[1],o.rooms[2],'off_mesh',o.id) end
    for _,e in ipairs(edges) do e.rooms=nil end
    if #nodes==0 then return nil,'no walkable floor is left after clearance for the agent (radius '..P.agent_radius..' m, height '..P.agent_height..' m)' end
    if #nodes>MAX_NODES or #edges>MAX_EDGES or #polygons>MAX_POLYGONS then
        return nil,string.format('the graph is too large (%d nodes, %d links, %d polygons); use a larger cell or tile, or a smaller scope',#nodes,#edges,#polygons)
    end
    -- Connectivity.
    local adj,radj={},{}
    for _,n in ipairs(nodes) do adj[n.id]={};radj[n.id]={} end
    for _,e in ipairs(edges) do if e.enabled then
        table.insert(adj[e.from],e.to);table.insert(radj[e.to],e.from)
        if not e.one_way then table.insert(adj[e.to],e.from);table.insert(radj[e.from],e.to) end
    end end
    local comp={};local comps={}
    for _,n in ipairs(nodes) do
        if not comp[n.id] then
            local c={id=#comps+1,nodes=0,area=0,rooms={}};comps[#comps+1]=c
            local stack={n.id};comp[n.id]=c.id
            while #stack>0 do
                local u=table.remove(stack);c.nodes=c.nodes+1
                for _,v in ipairs(adj[u]) do if not comp[v] then comp[v]=c.id;stack[#stack+1]=v end end
                for _,v in ipairs(radj[u]) do if not comp[v] then comp[v]=c.id;stack[#stack+1]=v end end
            end
        end
    end
    local byid={};for _,n in ipairs(nodes) do byid[n.id]=n end
    for _,n in ipairs(nodes) do local c=comps[comp[n.id]];c.area=c.area+(n.area or 0);if n.room_id then c.rooms[n.room_id]=true end end
    -- Entry: the area nearest a.entry, else the largest area of the island holding the most rooms (then the most floor).
    local entry
    if type(a.entry)=='table' and tonumber(a.entry.x) then
        local bd;for _,n in ipairs(nodes) do if n.kind=='area' then local d=dist3(n.position,{x=num(a.entry.x,0),y=num(a.entry.y,0),z=num(a.entry.z,0)});if not bd or d<bd then entry,bd=n,d end end end
    else
        local function nrooms(c) local n=0;for id in pairs(c.rooms) do if rooms[id] then n=n+1 end end;return n end
        local big;for _,c in ipairs(comps) do if not big or nrooms(c)>nrooms(big) or (nrooms(c)==nrooms(big) and c.area>big.area) then big=c end end
        local ba;for _,n in ipairs(nodes) do if n.kind=='area' and comp[n.id]==big.id and (not ba or (n.area or 0)>ba) then entry,ba=n,n.area or 0 end end
    end
    local function bfs(start,g) local seen={[start]=true};local st={start};while #st>0 do local u=table.remove(st);for _,v in ipairs(g[u]) do if not seen[v] then seen[v]=true;st[#st+1]=v end end end;return seen end
    local reach=entry and bfs(entry.id,adj) or {}
    local back=entry and bfs(entry.id,radj) or {}
    local room_rows={};local room_area={}
    for _,n in ipairs(nodes) do if n.kind=='area' and n.room_id then
        local r=room_area[n.room_id];if not r then r={area=0,reach=false,back=false};room_area[n.room_id]=r end
        r.area=r.area+(n.area or 0);if reach[n.id] then r.reach=true end;if back[n.id] then r.back=true end
    end end
    local unreachable,one_way,no_floor={},{},{}
    local room_ids={};for id in pairs(rooms) do room_ids[#room_ids+1]=id end;table.sort(room_ids)
    for _,id in ipairs(room_ids) do
        local r=room_area[id];local status
        if not r then status='no_walkable_area';no_floor[#no_floor+1]=id
        elseif not r.reach then status='unreachable';unreachable[#unreachable+1]=id
        elseif not r.back then status='one_way';one_way[#one_way+1]=id
        else status='reachable' end
        room_rows[#room_rows+1]={room_id=id,name=self:_room_name(id),status=status,walkable_area=r and r3(r.area) or 0}
    end
    local counts={}
    for _,d in ipairs(door_rows) do counts[d.status]=(counts[d.status] or 0)+1 end
    if (counts.blocked or 0)>0 then warnings[#warnings+1]=counts.blocked..' door(s) blocked: no clear floor on one side (see doors[].blockers)' end
    if (counts.too_narrow or 0)+(counts.too_low or 0)>0 then warnings[#warnings+1]=((counts.too_narrow or 0)+(counts.too_low or 0))..' door(s) too small for the agent; their links are disabled' end
    if #unreachable>0 then warnings[#warnings+1]=#unreachable..' room(s) cannot be reached from the entry area' end
    if #one_way>0 then warnings[#warnings+1]=#one_way..' room(s) can be entered but not left (one-way drops)' end
    for _,f in ipairs(flights) do if f.status~='connected' then warnings[#warnings+1]=f.kind..' '..f.id..' '..(f.status=='isolated' and 'meets no floor' or 'meets floor at one end only') end end
    local walkable_area=0;for _,r in ipairs(rects) do walkable_area=walkable_area+r.cells*cell*cell end
    local stats={walkable_surfaces=#walk,cells=#spans,kept_cells=kept_count,walkable_area=r3(walkable_area),areas=#rects,nodes=#nodes,edges=#edges,polygons=#polygons,
        doors=#door_rows,flights=0,ramps=0,off_mesh=#off_mesh,islands=#comps,obstacles=#obstacles,portal_cuts=portal_cuts,under_solid=under_solid,pockets=pockets,
        by_kind={}}
    for _,f in ipairs(flights) do if f.kind=='stairs' then stats.flights=stats.flights+1 else stats.ramps=stats.ramps+1 end end
    for _,e in ipairs(edges) do stats.by_kind[e.kind]=(stats.by_kind[e.kind] or 0)+1 end
    local islands={};for _,c in ipairs(comps) do if c.area>0 then local rl={};for id in pairs(c.rooms) do rl[#rl+1]=id end;table.sort(rl);islands[#islands+1]={id=c.id,nodes=c.nodes,area=r3(c.area),rooms=rl,entry=entry and comp[entry.id]==c.id or nil} end end
    table.sort(islands,function(x,y) return x.area>y.area end)
    local cut_off=0;for _,c in ipairs(islands) do if not c.entry then cut_off=cut_off+1 end end
    if cut_off>0 then warnings[#warnings+1]=cut_off..' walkable island(s) are not connected to the entry area' end
    for _,n in ipairs(nodes) do n.index=nil end
    return {nodes=nodes,edges=edges,polygons=polygons,doors=door_rows,flights=flights,off_mesh=off_mesh,room_links=room_links,
        report={rooms=room_rows,islands=islands,entry=entry and entry.id or nil,door_status=counts,warnings=warnings,unreachable_rooms=unreachable,one_way_rooms=one_way,rooms_without_floor=no_floor},
        stats=stats,fingerprint=self:_fingerprint(scope)}
end

-- A digest of the geometry a scope covers, to tell when a graph is out of date.
function NavGen:_fingerprint(scope)
    local rooms,objects,premises=self:_scope_sets(scope)
    local parts={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        if o.enabled~=false and (in_scope(o,scope,rooms,objects,premises) or (o.premise_id and premises[o.premise_id])) then
            local p=o.transform and o.transform.position or {};local r=o.transform and o.transform.rotation or {}
            local md=o.metadata or {};local cfg=md.procedural
            parts[#parts+1]=string.format('%s|%.3f|%.3f|%.3f|%.2f|%.2f|%.2f|%d|%d|%s',o.id,num(p.x,0),num(p.y,0),num(p.z,0),num(r.roll,0),num(r.pitch,0),num(r.yaw,0),
                cfg and #(cfg.surfaces or {}) or 0,#(md.surfaces or {}),cfg and tostring(cfg.bounds and cfg.bounds.max and cfg.bounds.max.z or '') or '')
        end
    end
    table.sort(parts)
    return hash(table.concat(parts,';'))
end

function NavGen:get(graph_id)
    for i,g in ipairs(self.app.model.data.navigation_graphs or {}) do if g.id==graph_id then return g,i end end
end

local function summary(g,res,dry)
    local out={graph_id=g and g.id or nil,name=g and g.name or nil,dry_run=dry or nil,stats=Util.deepcopy(res.stats),doors=Util.deepcopy(res.doors),flights=Util.deepcopy(res.flights),
        off_mesh=Util.deepcopy(res.off_mesh),room_links=Util.deepcopy(res.room_links),report=Util.deepcopy(res.report),native_redengine=false,
        notice='Generated LocationStudio navigation data. It does not change REDengine navmesh; run nav_validate_start to see where a real NPC walks.'}
    return out
end

function NavGen:generate(a)
    a=a or {}
    -- A dry run changes nothing, so it also works while an edit or plan is open.
    local b=busy(self.app);if b and not a._inside and not a.dry_run then return nil,b end
    local P,err=NavGen.normalize_params(a.params);if not P then return nil,err end
    local scope;scope,err=self:_scope(a);if not scope then return nil,err end
    local existing,index
    if a.graph_id and a.graph_id~='' then
        existing,index=self:get(a.graph_id)
        if not existing then return nil,'navigation graph not found: '..tostring(a.graph_id) end
        if not existing.generated then return nil,'graph '..existing.id..' was imported, not generated; generate a new graph instead' end
    elseif scope.build_id then
        for i,g in ipairs(self.app.model.data.navigation_graphs or {}) do if g.generated and g.generator and g.generator.scope and g.generator.scope.build_id==scope.build_id then existing,index=g,i end end
    end
    if existing and self.run and self.run.graph_id==existing.id then return nil,'a validation run is using this graph; cancel it first' end
    local res;res,err=self:_compute(scope,P,a);if not res then return nil,err end
    if a.dry_run then return summary(nil,res,true) end
    local now=Util.now_iso()
    local name=Util.trim(a.name or '')~='' and Util.trim(a.name) or (existing and existing.name) or self:_default_name(scope)
    local graph={id=existing and existing.id or Util.make_id('nav'),name=name,format='locationstudio.navigation-graph.v1',source_format='locationstudio-generated',source='nav_gen v'..NavGen.VERSION,
        coordinate_space='world',native_redengine=false,generated=true,
        generator={version=NavGen.VERSION,params=Util.deepcopy(P),scope=Util.deepcopy(scope),entry=type(a.entry)=='table' and Util.deepcopy(a.entry) or nil,fingerprint=res.fingerprint,generated_at=now,mod_version=self.app.version},
        nodes=res.nodes,edges=res.edges,polygons=res.polygons,doors=res.doors,flights=res.flights,off_mesh=res.off_mesh,room_links=res.room_links,report=res.report,stats=res.stats,
        imported_at=now}
    local model=self.app.model
    if a._no_snapshot~=true then model:snapshot(existing and 'Regenerate navigation' or 'Generate navigation') end
    model.data.navigation_graphs=model.data.navigation_graphs or {}
    if index then model.data.navigation_graphs[index]=graph else table.insert(model.data.navigation_graphs,graph) end
    if not model.data.active_navigation_graph_id or not self:get(model.data.active_navigation_graph_id) then model.data.active_navigation_graph_id=graph.id end
    model:touch();self.app:mark_dirty()
    local out=summary(graph,res);out.replaced=existing~=nil
    return out
end

function NavGen:_default_name(scope)
    local m=self.app.model
    if scope.build_id then return 'Navigation: build '..scope.build_id end
    if scope.premise_id then local p=m:get_premise(scope.premise_id);return 'Navigation: '..(p and p.name or scope.premise_id) end
    if scope.room_ids then local r=m:get_room(scope.room_ids[1]);return 'Navigation: '..(r and r.name or 'rooms')..(#scope.room_ids>1 and (' +'..(#scope.room_ids-1)) or '') end
    return 'Navigation: project'
end

function NavGen:regenerate(graph_id,patch)
    patch=patch or {}
    local g=self:get(graph_id);if not g then return nil,'navigation graph not found: '..tostring(graph_id) end
    if not g.generated then return nil,'graph '..g.id..' was imported, not generated' end
    local params=Util.deepcopy(g.generator.params or {})
    for k,v in pairs(type(patch.params)=='table' and patch.params or {}) do params[k]=v end
    local a=Util.deepcopy(g.generator.scope or {});a.params=params;a.graph_id=g.id;a.entry=patch.entry or g.generator.entry;a.dry_run=patch.dry_run
    return self:generate(a)
end

function NavGen:delete(graph_id)
    local b=busy(self.app);if b then return nil,b end
    local g,i=self:get(graph_id);if not g then return nil,'navigation graph not found: '..tostring(graph_id) end
    if self.run and self.run.graph_id==g.id then return nil,'a validation run is using this graph; cancel it first' end
    local model=self.app.model
    model:snapshot('Delete navigation graph');table.remove(model.data.navigation_graphs,i)
    if model.data.active_navigation_graph_id==g.id then model.data.active_navigation_graph_id=nil end
    model:touch();self.app:mark_dirty()
    return {deleted=g.id,name=g.name}
end

function NavGen:report(graph_id)
    local g=self:get(graph_id);if not g then return nil,'navigation graph not found: '..tostring(graph_id) end
    local out={graph_id=g.id,name=g.name,generated=g.generated==true,native_redengine=false,node_count=#(g.nodes or {}),edge_count=#(g.edges or {}),polygon_count=#(g.polygons or {})}
    if g.generated then
        out.params=Util.deepcopy(g.generator.params);out.scope=Util.deepcopy(g.generator.scope);out.generated_at=g.generator.generated_at
        out.stats=Util.deepcopy(g.stats);out.doors=Util.deepcopy(g.doors);out.flights=Util.deepcopy(g.flights);out.off_mesh=Util.deepcopy(g.off_mesh)
        out.room_links=Util.deepcopy(g.room_links);out.report=Util.deepcopy(g.report)
        local ok,fp=pcall(function() return self:_fingerprint(g.generator.scope) end)
        if ok then out.stale=fp~=g.generator.fingerprint end
        if out.stale then out.stale_hint='The geometry changed since this graph was generated; run nav_regenerate.' end
    end
    out.validation=g.validation and Util.deepcopy(g.validation) or nil
    return out
end

---------------------------------------------------------------------------
-- In-game validation with a real NPC
---------------------------------------------------------------------------

local LEG_KINDS={door=true,stairs=true,ramp=true,off_mesh=true,rooms=true}

-- The legs a validation run walks: every door, stairs flight, ramp and off-mesh
-- link (and optionally a route between every pair of linked rooms).
function NavGen:validation_plan(a)
    a=a or {}
    local g=self:get(a.graph_id);if not g then return nil,'navigation graph not found: '..tostring(a.graph_id) end
    local kinds={}
    local list=a.legs;if type(list)=='string' then list={list} end
    if type(list)=='table' and #list>0 then for _,k in ipairs(list) do if not LEG_KINDS[k] then return nil,'unknown leg kind '..tostring(k)..' (door, stairs, ramp, off_mesh, rooms)' end;kinds[k]=true end
    else kinds={door=true,stairs=true,ramp=true,off_mesh=true} end
    local byid={};for _,n in ipairs(g.nodes or {}) do byid[n.id]=n end
    local legs={}
    local function add(kind,ref,from,to,via,edges)
        if not from or not to then return end
        legs[#legs+1]={id='leg'..(#legs+1),kind=kind,ref=ref,start=Util.deepcopy(from),goal=Util.deepcopy(to),via=via and Util.deepcopy(via) or nil,edge_ids=edges or {}}
    end
    if kinds.door then for _,d in ipairs(g.doors or {}) do
        if #(d.sides or {})==2 then
            local s1,s2=byid[d.sides[1].node_id],byid[d.sides[2].node_id]
            add('door',d.id,s1 and s1.position,s2 and s2.position,d.position,{d.sides[1].edge_id,d.sides[2].edge_id})
        end
    end end
    for _,f in ipairs(g.flights or {}) do
        if kinds[f.kind] and f.bottom and f.top then
            add(f.kind,f.id,f.bottom.position,f.top.position,nil,{f.bottom.edge_id,f.top.edge_id})
            if a.both_directions then add(f.kind,f.id,f.top.position,f.bottom.position,nil,{f.bottom.edge_id,f.top.edge_id}) end
        end
    end
    if kinds.off_mesh then for _,o in ipairs(g.off_mesh or {}) do
        local s1,s2=byid[o.from],byid[o.to]
        add('off_mesh',o.id,s1 and s1.position,s2 and s2.position,nil,{o.id})
    end end
    if kinds.rooms then
        local rep={}
        for _,n in ipairs(g.nodes or {}) do if n.kind=='area' and n.room_id and (not rep[n.room_id] or (n.area or 0)>(rep[n.room_id].area or 0)) then rep[n.room_id]=n end end
        for _,l in ipairs(g.room_links or {}) do
            if l.from and l.to and rep[l.from] and rep[l.to] then add('rooms',l.from..'>'..l.to,rep[l.from].position,rep[l.to].position,nil,{}) end
        end
    end
    if type(a.custom)=='table' then
        for _,c in ipairs(a.custom) do
            if type(c)=='table' and type(c.start)=='table' and type(c.goal)=='table' and tonumber(c.start.x) and tonumber(c.goal.x) then
                add('custom',c.name or ('custom'..#legs+1),{x=num(c.start.x,0),y=num(c.start.y,0),z=num(c.start.z,0)},{x=num(c.goal.x,0),y=num(c.goal.y,0),z=num(c.goal.z,0)},nil,{})
            else return nil,'custom legs need start and goal {x,y,z}' end
        end
    end
    local max=math.floor(num(a.max_legs,20));if max<1 or max>60 then return nil,'max_legs must be 1 to 60' end
    local total=#legs;while #legs>max do table.remove(legs) end
    -- What the graph expects for each leg.
    for _,leg in ipairs(legs) do
        local q=self.app.navigation and self.app.navigation:query({graph_id=g.id,start=leg.start,goal=leg.goal,snap_distance=3})
        leg.graph_status=q and q.status or 'unknown';leg.graph_cost=q and q.cost or nil
        leg.expected_length=r3(dist3(leg.start,leg.goal))
    end
    return {graph_id=g.id,legs=legs,count=#legs,total=total,truncated=total>#legs or nil}
end

local function vec4(p) return Vector4.new(p.x,p.y,p.z,1) end

-- An AI move command for an NPC. Every call is guarded: the result says which step failed.
local function send_move(npc,goal,opts)
    local steps={}
    local ok,err=pcall(function()
        local v=vec4(goal)
        local wp
        if WorldPosition and WorldPosition.new then
            wp=WorldPosition.new()
            local set=pcall(function() WorldPosition.SetVector4(wp,v) end)
            if not set then pcall(function() wp:SetVector4(wp,v) end) end
        end
        local spec=AIPositionSpec.new()
        local set=wp and pcall(function() AIPositionSpec.SetWorldPosition(spec,wp) end)
        if not set and wp then set=pcall(function() spec:SetWorldPosition(spec,wp) end) end
        if not set then steps[#steps+1]='position spec' end
        local cmd=AIMoveToCommand.new()
        cmd.movementTarget=spec
        cmd.rotateEntityTowardsFacingTarget=false
        cmd.ignoreNavigation=opts.ignore_navigation==true
        cmd.desiredDistanceFromTarget=opts.tolerance*0.5
        pcall(function() cmd.movementType=opts.run and moveMovementType.Run or moveMovementType.Walk end)
        cmd.finishWhenDestinationReached=true
        npc:GetAIControllerComponent():SendCommand(cmd)
        return cmd
    end)
    if not ok then return nil,'AI move command failed: '..tostring(err) end
    return err,#steps>0 and ('incomplete: '..table.concat(steps,', ')) or nil
end
local function cancel_move(npc,cmd)
    if npc and cmd then pcall(function() npc:GetAIControllerComponent():CancelCommand(cmd) end) end
end
local function teleport(npc,p,yaw)
    return pcall(function() Game.GetTeleportationFacility():Teleport(npc,Vector4.new(p.x,p.y,p.z+0.05,1),EulerAngles.new(0,0,yaw or 0)) end)
end
local function npc_pos(npc)
    local ok,p=pcall(function() return npc:GetWorldPosition() end)
    if ok and p then return {x=p.x,y=p.y,z=p.z} end
end

function NavGen:validate_start(a)
    a=a or {}
    if self.run and not self.run.done then return nil,'a validation run is active; wait for it or cancel it' end
    if self.run and self.run.pending_write then
        if busy(self.app) then return nil,'the last run\'s results are waiting for the open edit to close' end
        self:_store_results()
    end
    if not self.app.live_tools then return nil,'live NPC tools are unavailable' end
    local plan,err=self:validation_plan(a);if not plan then return nil,err end
    if plan.count==0 then return nil,'this graph has nothing to validate (no connected doors, flights, ramps or off-mesh links; add custom legs)' end
    local opts={tolerance=num(a.tolerance,0.75),stall_time=num(a.stall_time,5),timeout_scale=num(a.timeout_scale,1),settle=num(a.settle,1),run=a.run==true,ignore_navigation=a.ignore_navigation==true}
    if opts.tolerance<0.2 or opts.tolerance>3 then return nil,'tolerance must be 0.2 to 3 m' end
    if opts.stall_time<1 or opts.stall_time>30 then return nil,'stall_time must be 1 to 30 s' end
    if opts.timeout_scale<0.5 or opts.timeout_scale>5 then return nil,'timeout_scale must be 0.5 to 5' end
    local run={id=Util.make_id('navrun'),graph_id=plan.graph_id,legs=plan.legs,index=0,opts=opts,started_at=Util.now_iso(),clock=0,state='acquire',results={}}
    if a.record and a.record~='' then
        local first=plan.legs[1].start
        local r,serr=self.app.live_tools:spawn_record({record=a.record,appearance=a.appearance,position={x=first.x,y=first.y,z=first.z+0.1},yaw=0,tag='ls_nav_validate'})
        if not r then return nil,'NPC spawn failed: '..tostring(serr) end
        run.npc_key=r.key;run.spawned=true;run.record=a.record;run.state='spawning';run.wait=0
    else
        local npc;npc,err=self.app.live_tools:find_npc({key=a.npc_key,target=a.target or 'crosshair',search=a.search})
        if not npc then return nil,'no NPC to validate with: '..tostring(err)..' (aim at an NPC, pass npc_key, or pass a character record to spawn)' end
        run.npc=npc;run.npc_key=tostring(npc:GetEntityID().hash)
    end
    self.run=run
    return {run_id=run.id,graph_id=run.graph_id,state=run.state,legs=#run.legs,npc_key=run.npc_key,spawned=run.spawned or false,
        note='The NPC walks each leg with REDengine navigation. Poll nav_validate_status; results are saved on the graph.'}
end

function NavGen:_leg_done(status,detail)
    local run=self.run;local leg=run.legs[run.index];local st=run.leg
    cancel_move(run.npc,st and st.cmd)
    local trace=st and st.trace or {}
    local length=0;for i=2,#trace do length=length+dist3(trace[i-1],trace[i]) end
    local keep={};local step=math.max(1,math.ceil(#trace/60));for i=1,#trace,step do keep[#keep+1]=trace[i] end
    if #trace>0 and keep[#keep]~=trace[#trace] then keep[#keep+1]=trace[#trace] end
    local final=st and st.last or nil
    local verdict
    if status=='traversed' then verdict=leg.graph_status=='reachable_in_imported_graph' and 'confirmed' or 'engine_only'
    elseif leg.graph_status=='reachable_in_imported_graph' then verdict='engine_disagrees' else verdict='expected_failure' end
    run.results[#run.results+1]={leg_id=leg.id,kind=leg.kind,ref=leg.ref,status=status,verdict=verdict,detail=detail,graph_status=leg.graph_status,edge_ids=leg.edge_ids,
        start=leg.start,goal=leg.goal,elapsed=st and r3(st.t) or 0,final_distance=final and r3(dist3(final,leg.goal)) or nil,walked_length=r3(length),expected_length=leg.expected_length,
        passed_via=leg.via and st and st.via_min and st.via_min<=1.0 or nil,via_distance=st and st.via_min and r3(st.via_min) or nil,
        z_reached=final and r3(final.z) or nil,trace=keep}
    run.leg=nil
end

function NavGen:update(delta)
    local run=self.run;if not run then return end
    if run.done then if run.pending_write and not busy(self.app) then self:_store_results() end;return end
    delta=math.max(0,num(delta,0));run.clock=run.clock+delta
    if run.cancel then self:_finish('cancelled');return end
    if run.state=='spawning' then
        run.wait=run.wait+delta
        local npc=self.app.live_tools:find_npc({key=run.npc_key,search=100})
        if npc then run.npc=npc;run.state='acquire'
        elseif run.wait>8 then run.error='the spawned NPC did not appear within 8 s';self:_finish('failed');return end
        return
    end
    if run.state=='acquire' then
        run.index=run.index+1
        if run.index>#run.legs then self:_finish('completed');return end
        local leg=run.legs[run.index]
        local yaw=math.deg(math.atan2(-(leg.goal.x-leg.start.x),leg.goal.y-leg.start.y))
        if not teleport(run.npc,leg.start,yaw) then self:_leg_done('npc_lost','could not teleport the NPC to the leg start');return end
        run.leg={t=0,settle=0,trace={},sample=0};run.state='settle'
        return
    end
    local leg=run.legs[run.index];local st=run.leg
    if run.state=='settle' then
        st.settle=st.settle+delta
        if st.settle>=run.opts.settle then
            local p=npc_pos(run.npc);if not p then self:_leg_done('npc_lost','the NPC is gone');run.state='acquire';return end
            st.start_actual=p
            local cmd,warn=send_move(run.npc,leg.goal,run.opts)
            if not cmd then self:_leg_done('command_failed',warn);run.state='acquire';return end
            st.cmd=cmd;st.warning=warn;st.best=dist3(p,leg.goal);st.best_t=0;st.last=p;st.trace[1]=p
            st.timeout=(10+leg.expected_length/0.8*2.5)*run.opts.timeout_scale
            run.state='move'
        end
        return
    end
    if run.state=='move' then
        st.t=st.t+delta;st.sample=st.sample+delta
        if st.sample<0.25 then return end
        st.sample=0
        local p=npc_pos(run.npc);if not p then self:_leg_done('npc_lost','the NPC is gone');run.state='acquire';return end
        st.last=p;if #st.trace<600 then st.trace[#st.trace+1]=p end
        if leg.via then local d=dist3(p,leg.via);if not st.via_min or d<st.via_min then st.via_min=d end end
        local d=dist3(p,leg.goal)
        if d<st.best-0.2 then st.best=d;st.best_t=st.t end
        if dist2(p,leg.goal)<=run.opts.tolerance and math.abs(p.z-leg.goal.z)<=1.0 then self:_leg_done('traversed',st.warning);run.state='acquire'
        elseif st.t-st.best_t>=run.opts.stall_time then self:_leg_done('stalled',string.format('no progress for %.0f s, %.2f m from the goal',run.opts.stall_time,d));run.state='acquire'
        elseif st.t>=st.timeout then self:_leg_done('timeout',string.format('%.2f m from the goal after %.0f s',d,st.t));run.state='acquire' end
    end
end

function NavGen:_finish(state)
    local run=self.run
    if run.leg then self:_leg_done(state=='cancelled' and 'cancelled' or 'npc_lost',run.error) end
    run.done=true;run.state=state;run.finished_at=Util.now_iso()
    if run.spawned then pcall(function() self.app.live_tools:despawn_tag({tag='ls_nav_validate'}) end) end
    local sum={legs=#run.results,traversed=0,failed=0,confirmed=0,engine_disagrees=0,by_status={}}
    for _,r in ipairs(run.results) do
        sum.by_status[r.status]=(sum.by_status[r.status] or 0)+1
        if r.status=='traversed' then sum.traversed=sum.traversed+1 elseif r.status~='cancelled' then sum.failed=sum.failed+1 end
        if r.verdict=='confirmed' then sum.confirmed=sum.confirmed+1 elseif r.verdict=='engine_disagrees' then sum.engine_disagrees=sum.engine_disagrees+1 end
    end
    run.summary=sum
    run.pending_write=true
    if not busy(self.app) then self:_store_results() end
    run.npc=nil
    if self.app.logger then self.app.logger:info('nav_validate','finished',{run=run.id,state=state,traversed=sum.traversed,failed=sum.failed}) end
end

-- Results go on the graph, and each link records its last result (deferred while a transaction is open).
function NavGen:_store_results()
    local run=self.run;run.pending_write=nil
    local sum=run.summary;local state=run.state
    local g=self:get(run.graph_id)
    if g then
        g.validation={run_id=run.id,state=state,started_at=run.started_at,finished_at=run.finished_at,npc={key=run.npc_key,record=run.record,spawned=run.spawned or false},
            settings=Util.deepcopy(run.opts),summary=Util.deepcopy(sum),legs=Util.deepcopy(run.results),error=run.error}
        local by={};for _,e in ipairs(g.edges or {}) do by[e.id]=e end
        for _,r in ipairs(run.results) do for _,id in ipairs(r.edge_ids or {}) do if by[id] and r.status~='cancelled' then by[id].validation={status=r.status,run_id=run.id,at=run.finished_at} end end end
        self.app.model:touch();self.app:mark_dirty()
    end
end

function NavGen:validate_status()
    local run=self.run
    if not run then return {state='idle'} end
    local leg=run.legs[run.index]
    local out={run_id=run.id,graph_id=run.graph_id,state=run.state,done=run.done or false,leg_index=run.index,legs=#run.legs,error=run.error,npc_key=run.npc_key,
        current=(not run.done and leg) and {id=leg.id,kind=leg.kind,ref=leg.ref,elapsed=run.leg and r3(run.leg.t) or 0} or nil,
        results=Util.deepcopy(run.results),summary=run.summary and Util.deepcopy(run.summary) or nil}
    for _,r in ipairs(out.results) do r.trace=nil end
    return out
end

function NavGen:validate_cancel()
    local run=self.run
    if not run or run.done then return nil,'no validation run is active' end
    run.cancel=true;self:update(0)
    return {run_id=run.id,state=run.state,legs_done=#run.results}
end

return NavGen
