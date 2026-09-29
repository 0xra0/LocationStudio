local Util=require('modules/util')
local NavGen=require('modules/nav_gen')

-- Streaming-sector partitioner for generated environments. Instead of the author
-- assigning every generated node to a sector by hand, the environment is divided
-- automatically:
--   1. Atoms. Every room in scope is one atom with the objects it owns (and loose
--      objects standing inside it). Everything else goes into spatial cells
--      (`loose_cell` m), split into quarters while a cell holds more than
--      `max_nodes`. Objects of one persistent group or one ambient reverb zone
--      stay in one atom, so the zone exports complete.
--   2. Links between atoms, each with a weight:
--        connectivity  shared doors of generated rooms, and the room links of
--                      the scope's generated navigation graph (door, open floor,
--                      stairs, ramp, off-mesh);
--        traversal     the path a player is expected to take: a breadth-first
--                      walk over the connectivity links from the entry;
--        visibility    rooms/cells that see each other through doors, windows
--                      and open space (lines of sight blocked by room walls and
--                      authored occluders, modules/visibility.lua);
--        proximity     atoms whose bounds are closer than `proximity_gap`.
--   3. Clustering. Atoms are merged greedily, strongest link per node first, while
--      a sector stays within `max_nodes` and `max_extent`. Sectors smaller than
--      `min_nodes` are then merged into their best neighbour. Rooms are never
--      split. Pins force atoms into a named sector.
--   4. Sectors: bounds, interior/exterior category, streaming extents that cover
--      every atom a sector is visible from plus a preload distance, neighbours,
--      the transitions a player crosses (door links cut by a sector border) and
--      the traversal order.
-- The result is a LocationStudio record (model.data.sector_partitions). Export
-- writes one World Builder group per sector (modules/build_export.lua), which
-- World Builder turns into one streaming sector each.
local SP={};SP.__index=SP
SP.VERSION=1

local DEFAULTS={max_nodes=600,min_nodes=40,max_extent=128,loose_cell=32,view_distance=60,preload=20,proximity_gap=4,
    w_connectivity=10,w_traversal=6,w_visibility=3,w_proximity=1}
local RANGES={max_nodes={10,20000},min_nodes={0,5000},max_extent={8,2048},loose_cell={4,512},view_distance={0,1000},preload={0,500},proximity_gap={0,100},
    w_connectivity={0,100},w_traversal={0,100},w_visibility={0,100},w_proximity={0,100}}
local HINTS={max_nodes='most nodes (objects) in one sector',min_nodes='sectors with fewer nodes are merged into a neighbour',
    max_extent='largest side of a sector (m); a single room larger than this stays whole',loose_cell='cell size for objects outside rooms (m)',
    view_distance='farthest distance at which rooms/cells are tested for line of sight (m)',preload='how far ahead of the player a sector streams in (m)',
    proximity_gap='atoms closer than this are linked by proximity (m)',w_connectivity='weight of a door or walkable link',
    w_traversal='extra weight of a link on the expected player path',w_visibility='weight of a line of sight',w_proximity='weight of spatial closeness'}
SP.DEFAULTS=DEFAULTS;SP.RANGES=RANGES
local LINK_FACTOR={door=1,open=1.2,stairs=0.8,ramp=0.8,off_mesh=0.5}
local MAX_VIS_PAIRS=3000
local MAX_SPLIT_DEPTH=4
local MAX_PINS=2000
local EYE=1.6

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function r2(v) return math.floor(v*100+0.5)/100 end
local function hash(str) local h=5381;for i=1,#str do h=(h*33+str:byte(i))%4294967291 end;return string.format('%08x',h) end
local function slug(s) return (tostring(s or 'x'):lower():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')) end
local function empty_box() return {min={x=math.huge,y=math.huge,z=math.huge},max={x=-math.huge,y=-math.huge,z=-math.huge}} end
local function grow(b,o) for _,k in ipairs({'x','y','z'}) do b.min[k]=math.min(b.min[k],o.min[k]);b.max[k]=math.max(b.max[k],o.max[k]) end end
local function box_ok(b) return b and b.min.x<=b.max.x end
local function center(b) return {x=(b.min.x+b.max.x)/2,y=(b.min.y+b.max.y)/2,z=(b.min.z+b.max.z)/2} end
local function gap(a,b)
    local d=0
    for _,k in ipairs({'x','y','z'}) do local g=math.max(a.min[k]-b.max[k],b.min[k]-a.max[k],0);d=d+g*g end
    return math.sqrt(d)
end
local function union(a,b) local u=empty_box();grow(u,a);grow(u,b);return u end
local function extent(b) return math.max(b.max.x-b.min.x,b.max.y-b.min.y),b.max.z-b.min.z end
local function round_box(b) return {min={x=r2(b.min.x),y=r2(b.min.y),z=r2(b.min.z)},max={x=r2(b.max.x),y=r2(b.max.y),z=r2(b.max.z)}} end

local function busy(app)
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and (app.authoring_plans.running or app.authoring_plans:status().recovery_required) then return 'Resolve the running or failed authoring plan first' end
end

function SP.normalize_params(p)
    if p~=nil and type(p)~='table' then return nil,'params must be an object' end
    for k in pairs(p or {}) do if DEFAULTS[k]==nil then return nil,'unknown partition parameter '..tostring(k) end end
    local out={}
    for k,d in pairs(DEFAULTS) do
        local v=p and p[k]
        if v==nil then out[k]=d
        else
            v=tonumber(v)
            if v==nil or v~=v or v<RANGES[k][1] or v>RANGES[k][2] then return nil,k..' must be a number from '..RANGES[k][1]..' to '..RANGES[k][2] end
            out[k]=v
        end
    end
    out.max_nodes=math.floor(out.max_nodes);out.min_nodes=math.floor(out.min_nodes)
    if out.min_nodes>=out.max_nodes then return nil,'min_nodes must be smaller than max_nodes' end
    return out
end

function SP.new(app) return setmetatable({app=app},SP) end

function SP:parameters()
    local rows={};for k,d in pairs(DEFAULTS) do rows[#rows+1]={name=k,default=d,min=RANGES[k][1],max=RANGES[k][2],hint=HINTS[k]} end
    table.sort(rows,function(a,b) return a.name<b.name end)
    return rows
end

function SP:list() return self.app.model.data.sector_partitions or {} end
function SP:get(id) for i,p in ipairs(self:list()) do if p.id==id then return p,i end end end

---------------------------------------------------------------------------
-- Scope and atoms
---------------------------------------------------------------------------

-- Same scopes as the navigation generator: build_id, room_ids, premise_id or all.
function SP:_scope(a) return NavGen._scope({app=self.app},a) end

local function in_scope(o,scope,rooms,objects)
    if scope.all then return true end
    if objects[o.id] or (o.room_id and rooms[o.room_id]) then return true end
    if scope.premise_id and not scope.build_id and not scope.room_ids and o.premise_id==scope.premise_id then return true end
    return false
end

function SP:_scope_sets(scope)
    local rooms,objects=NavGen._scope_sets({app=self.app},scope)
    return rooms,objects
end

-- A room's world box from its footprint (yaw applied) and height.
local function room_box(room)
    local p=room.transform and room.transform.position or {};local s=room.size or {}
    local w,d,h=num(s.width,4),num(s.depth,4),num(s.height,3)
    local yaw=math.rad(num(room.transform and room.transform.rotation and room.transform.rotation.yaw,0))
    local c,sn=math.abs(math.cos(yaw)),math.abs(math.sin(yaw))
    local hx,hy=(w*c+d*sn)/2,(w*sn+d*c)/2
    local x,y,z=num(p.x,0),num(p.y,0),num(p.z,0)
    return {min={x=x-hx,y=y-hy,z=z},max={x=x+hx,y=y+hy,z=z+h}}
end

local function inside_room(room,p)
    local base=room.transform and room.transform.position or {};local s=room.size or {}
    local r=math.rad(-num(room.transform and room.transform.rotation and room.transform.rotation.yaw,0))
    local dx,dy=p.x-num(base.x,0),p.y-num(base.y,0)
    local x,y=dx*math.cos(r)-dy*math.sin(r),dx*math.sin(r)+dy*math.cos(r)
    local z=p.z-num(base.z,0)
    return math.abs(x)<=num(s.width,4)/2 and math.abs(y)<=num(s.depth,4)/2 and z>=-0.5 and z<=num(s.height,3)
end

function SP:_object_box(o)
    local md=o.metadata or {};local box
    if self.app.bounds_gen and (md.procedural or md.collision_gen) then box=self.app.bounds_gen:world_aabb(o) end
    if not box and self.app.asset_bounds and type(md.asset_bounds)=='table' then local r=self.app.asset_bounds:world_aabb(o.id);box=r and r.aabb end
    if not box and o.transform and o.transform.position then
        local p=o.transform.position;local x,y,z=num(p.x,0),num(p.y,0),num(p.z,0)
        box={min={x=x-0.25,y=y-0.25,z=z-0.25},max={x=x+0.25,y=y+0.25,z=z+0.25}}
    end
    if box then return {min={x=box.min.x,y=box.min.y,z=box.min.z},max={x=box.max.x,y=box.max.y,z=box.max.z}} end
end

local function cell_key(p,size) return string.format('cell:%d:%d:%d',math.floor(p.x/size),math.floor(p.y/size),math.floor(p.z/size)) end

-- Objects and rooms in scope turned into atoms.
function SP:_atoms(scope,P,pins)
    local model=self.app.model
    local rooms,objects=self:_scope_sets(scope)
    local layers=self.app.layers
    local atoms,by_key,warnings={}, {}, {}
    local room_list={}
    for _,r in ipairs(model.data.rooms or {}) do if rooms[r.id] and r.enabled~=false then room_list[#room_list+1]=r end end
    for _,r in ipairs(room_list) do
        local a={key='room:'..r.id,kind='room',room_id=r.id,name=r.name,box=room_box(r),objects={},nodes=0}
        atoms[#atoms+1]=a;by_key[a.key]=a
    end
    local placed,excluded={},{disabled=0,layer=0}
    local key_of={};local members={}
    for _,o in ipairs(model.data.objects or {}) do
        if in_scope(o,scope,rooms,objects) then
            if o.enabled==false then excluded.disabled=excluded.disabled+1
            elseif layers and not layers:export_enabled(o) then excluded.layer=excluded.layer+1
            else
                local box=self:_object_box(o)
                if box then
                    local key
                    if o.room_id and by_key['room:'..o.room_id] then key='room:'..o.room_id
                    else
                        local c=center(box)
                        for _,r in ipairs(room_list) do if inside_room(r,c) then key='room:'..r.id;break end end
                    end
                    key_of[o.id]=key or false;members[#members+1]={o=o,box=box}
                end
            end
        end
    end
    -- Keep persistent groups and ambient reverb zones together: members follow
    -- the atom most of them are in (an ambient zone follows its area object).
    local function follow(ids,lead)
        local count,best,best_n={},nil,0
        for _,id in ipairs(ids) do local k=key_of[id];if k~=nil then k=k or '';count[k]=(count[k] or 0)+1;if count[k]>best_n or (count[k]==best_n and k<best) then best,best_n=k,count[k] end end end
        if lead and key_of[lead]~=nil then best=key_of[lead] or '' end
        if best==nil then return end
        for _,id in ipairs(ids) do if key_of[id]~=nil then key_of[id]=best~='' and best or false end end
    end
    for _,g in ipairs(model.data.object_groups or {}) do if type(g.object_ids)=='table' and #g.object_ids>1 then follow(g.object_ids) end end
    local zones={}
    for _,m in ipairs(members) do
        local z=m.o.metadata and m.o.metadata.ambient_zone
        if z and z.id then zones[z.id]=zones[z.id] or {ids={}};table.insert(zones[z.id].ids,m.o.id);if z.role=='area' then zones[z.id].lead=m.o.id end end
    end
    local zone_ids={};for id in pairs(zones) do zone_ids[#zone_ids+1]=id end;table.sort(zone_ids)
    for _,id in ipairs(zone_ids) do follow(zones[id].ids,zones[id].lead) end
    -- Loose objects: spatial cells, quartered while a cell is over budget. Grouped
    -- objects move together, so a cell is keyed by where the group's first member is.
    local loose={}
    for _,m in ipairs(members) do
        local k=key_of[m.o.id]
        if k then local a=by_key[k];a.objects[#a.objects+1]=m.o.id;a.nodes=a.nodes+1;grow(a.box,m.box);placed[m.o.id]=true
        else loose[#loose+1]=m end
    end
    local function split(list,size,depth,prefix)
        local cells,order={},{}
        for _,m in ipairs(list) do
            local k=prefix..cell_key(center(m.box),size)
            if not cells[k] then cells[k]={};order[#order+1]=k end
            table.insert(cells[k],m)
        end
        table.sort(order)
        for _,k in ipairs(order) do
            local items=cells[k]
            if #items>P.max_nodes and depth<MAX_SPLIT_DEPTH and size/2>=4 then split(items,size/2,depth+1,k..'/')
            else
                local a={key=k,kind='cell',name='cell '..k:gsub('^.*cell:',''),box=empty_box(),objects={},nodes=0,cell_size=size}
                for _,m in ipairs(items) do a.objects[#a.objects+1]=m.o.id;a.nodes=a.nodes+1;grow(a.box,m.box);placed[m.o.id]=true end
                if #items>P.max_nodes then warnings[#warnings+1]=string.format('cell %s holds %d nodes at the smallest cell size; it stays one sector over max_nodes',k,#items) end
                atoms[#atoms+1]=a;by_key[k]=a
            end
        end
    end
    split(loose,P.loose_cell,0,'')
    for _,a in ipairs(atoms) do
        if a.kind=='room' and a.nodes>P.max_nodes then warnings[#warnings+1]=string.format('room %s holds %d nodes, more than max_nodes %d; rooms are never split, so it gets its own sector',tostring(a.name),a.nodes,P.max_nodes) end
    end
    -- Pins: object or room ids -> sector label.
    local pin_ids={};for id in pairs(pins or {}) do pin_ids[#pin_ids+1]=id end;table.sort(pin_ids)
    for _,id in ipairs(pin_ids) do
        local label=pins[id]
        local a=by_key['room:'..id]
        if not a then for _,x in ipairs(atoms) do for _,oid in ipairs(x.objects) do if oid==id then a=x;break end end;if a then break end end end
        if not a then warnings[#warnings+1]='pin '..tostring(id)..' matches no room or object in scope'
        elseif a.pin and a.pin~=label then
            local win=a.pin<label and a.pin or label
            warnings[#warnings+1]=string.format('%s is pinned to both %s and %s (a pinned object is in that room); %s wins',tostring(a.name),a.pin,label,win);a.pin=win
        else a.pin=label end
    end
    -- Order by position (then key), so the same layout partitions the same way whatever its ids.
    local function pos(x) return {r2(x.box.min.z),r2(x.box.min.y),r2(x.box.min.x)} end
    table.sort(atoms,function(x,y)
        local p,q=pos(x),pos(y)
        for i=1,3 do if p[i]~=q[i] then return p[i]<q[i] end end
        return x.key<y.key
    end)
    for i,a in ipairs(atoms) do a.index=i;table.sort(a.objects) end
    return atoms,by_key,room_list,excluded,warnings
end

---------------------------------------------------------------------------
-- Links
---------------------------------------------------------------------------

-- The generated navigation graph for this scope, if one exists (explicit id first).
function SP:_nav_graph(scope,graph_id)
    local graphs=self.app.model.data.navigation_graphs or {}
    if graph_id and graph_id~='' then
        for _,g in ipairs(graphs) do if g.id==graph_id then return g end end
        return nil,'navigation graph not found: '..tostring(graph_id)
    end
    for _,g in ipairs(graphs) do
        local s=g.generated and g.generator and g.generator.scope
        if s and ((scope.build_id and s.build_id==scope.build_id) or (not scope.build_id and not s.build_id and scope.premise_id and s.premise_id==scope.premise_id) or (scope.all and s.all)) then return g end
    end
end

function SP:_links(atoms,by_key,room_list,P,graph,entry_point)
    local model=self.app.model
    local links={}
    local function link(a,b,kind,w,extra)
        if not a or not b or a==b then return end
        if a.index>b.index then a,b=b,a end
        local k=a.index..':'..b.index
        local l=links[k];if not l then l={a=a,b=b,weight=0,reasons={},doors={}};links[k]=l end
        l.weight=l.weight+w;l.reasons[kind]=(l.reasons[kind] or 0)+1
        if extra then l.doors[#l.doors+1]=extra end
        return l
    end
    -- Connectivity: doors of generated rooms, then navigation room links.
    local conn={}
    local function connect(a,b,kind,factor,extra)
        local l=link(a,b,kind,P.w_connectivity*factor,extra)
        if l then conn[a]=conn[a] or {};conn[b]=conn[b] or {};conn[a][b]=true;conn[b][a]=true end
    end
    -- A shared door is a portal on both rooms; count each pair's doors once (the
    -- side that lists more of them).
    local sides,pair_order={},{}
    for _,rec in ipairs(model.data.generated_rooms or {}) do
        local a=by_key['room:'..tostring(rec.id)]
        if a then
            for _,p in ipairs(rec.portals or {}) do
                local other=p.connects and by_key['room:'..tostring(p.connects)]
                if p.kind=='door' and other and other~=a then
                    local lo,hi=a.index<other.index and a or other,a.index<other.index and other or a
                    local k=lo.index..':'..hi.index
                    if not sides[k] then sides[k]={lo=lo,hi=hi,[lo]={},[hi]={}};pair_order[#pair_order+1]=k end
                    table.insert(sides[k][a],p.id)
                end
            end
        end
    end
    table.sort(pair_order)
    for _,k in ipairs(pair_order) do
        local s=sides[k];local from=#s[s.lo]>=#s[s.hi] and s.lo or s.hi
        for _,portal in ipairs(s[from]) do connect(s.lo,s.hi,'door',LINK_FACTOR.door,{kind='door',rooms={s.lo.room_id,s.hi.room_id},portal=portal}) end
    end
    if graph then
        for _,l in ipairs(graph.room_links or {}) do
            local a,b=by_key['room:'..tostring(l.from)],by_key['room:'..tostring(l.to)]
            local f=LINK_FACTOR[l.kind]
            if a and b and f and l.kind~='door' then connect(a,b,l.kind,f,{kind=l.kind,rooms={l.from,l.to}}) end
        end
    end
    -- Visibility (and proximity) between atom pairs within view distance.
    local vis=self.app.visibility
    local occluders=vis and vis:_occluders(nil) or {}
    local rbox={};for _,r in ipairs(room_list) do rbox[#rbox+1]={room=r,box=room_box(r)} end
    local function blockers(p,q)
        local seg={min={x=math.min(p.x,q.x),y=math.min(p.y,q.y),z=math.min(p.z,q.z)},max={x=math.max(p.x,q.x),y=math.max(p.y,q.y),z=math.max(p.z,q.z)}}
        local out={};for _,rb in ipairs(rbox) do if gap(rb.box,seg)<=0.01 then out[#out+1]=rb.room end end
        return out
    end
    local function eye(a) local c=center(a.box);c.z=math.min(a.box.min.z+EYE,a.box.max.z);return c end
    local function opening_points(a)
        local out={}
        local r=a.room_id and model:get_room(a.room_id)
        if not r then return out end
        local base=r.transform.position;local yaw=math.rad(num(r.transform.rotation and r.transform.rotation.yaw,0))
        local w2,d2=num(r.size.width,4)/2,num(r.size.depth,4)/2
        for _,o in ipairs(r.openings or {}) do
            local lx,ly
            if o.wall=='north' then lx,ly=num(o.offset,0),d2 elseif o.wall=='south' then lx,ly=num(o.offset,0),-d2
            elseif o.wall=='east' then lx,ly=w2,num(o.offset,0) elseif o.wall=='west' then lx,ly=-w2,num(o.offset,0) end
            if lx then
                local x,y=lx*math.cos(yaw)-ly*math.sin(yaw),lx*math.sin(yaw)+ly*math.cos(yaw)
                out[#out+1]={x=num(base.x,0)+x,y=num(base.y,0)+y,z=num(base.z,0)+num(o.sill,0)+num(o.height,2)/2}
            end
        end
        return out
    end
    local pairs_list={}
    for i=1,#atoms do for j=i+1,#atoms do
        local d=gap(atoms[i].box,atoms[j].box)
        if d<=math.max(P.view_distance,P.proximity_gap) then pairs_list[#pairs_list+1]={a=atoms[i],b=atoms[j],d=d} end
    end end
    table.sort(pairs_list,function(x,y) if x.d~=y.d then return x.d<y.d end;if x.a.index~=y.a.index then return x.a.index<y.a.index end;return x.b.index<y.b.index end)
    local visible,skipped={},0
    for n,pr in ipairs(pairs_list) do
        local a,b=pr.a,pr.b
        if pr.d<=P.proximity_gap and P.w_proximity>0 then link(a,b,'proximity',P.w_proximity*(1-pr.d/(P.proximity_gap+1))) end
        if vis and pr.d<=P.view_distance then
            if n>MAX_VIS_PAIRS then skipped=skipped+1
            else
                local ea,eb=eye(a),eye(b)
                local lines={{ea,eb}}
                for _,p in ipairs(opening_points(a)) do lines[#lines+1]={p,eb} end
                for _,p in ipairs(opening_points(b)) do lines[#lines+1]={ea,p} end
                for _,ln in ipairs(lines) do
                    if vis:_line_clear(blockers(ln[1],ln[2]),occluders,ln[1],ln[2]) then
                        visible[#visible+1]={a=a,b=b}
                        if P.w_visibility>0 then link(a,b,'visibility',P.w_visibility) end
                        break
                    end
                end
            end
        end
    end
    -- Expected traversal: breadth-first over connectivity (then proximity for
    -- atoms connectivity does not reach) from the entry.
    local entry
    if entry_point then
        local best=math.huge
        for _,a in ipairs(atoms) do local d=gap(a.box,{min=entry_point,max=entry_point});if d<best then best,entry=d,a end end
    end
    if not entry and graph and graph.report and graph.report.entry then
        for _,node in ipairs(graph.nodes or {}) do if node.id==graph.report.entry and node.room_id then entry=by_key['room:'..node.room_id] end end
    end
    if not entry then
        for _,l in ipairs(graph and graph.room_links or {}) do if l.kind=='exit' and by_key['room:'..tostring(l.from)] then entry=by_key['room:'..tostring(l.from)];break end end
    end
    if not entry then
        for _,rec in ipairs(model.data.generated_rooms or {}) do
            local a=by_key['room:'..tostring(rec.id)]
            if a then for _,p in ipairs(rec.portals or {}) do if p.kind=='door' and not p.connects then entry=entry and (entry.index<a.index and entry or a) or a end end end
        end
    end
    entry=entry or atoms[1]
    local adj={};for _,l in pairs(links) do adj[l.a]=adj[l.a] or {};adj[l.b]=adj[l.b] or {};table.insert(adj[l.a],l);table.insert(adj[l.b],l) end
    for _,list in pairs(adj) do table.sort(list,function(x,y) if x.a.index~=y.a.index then return x.a.index<y.a.index end;return x.b.index<y.b.index end) end
    local depth={[entry]=0};local order={entry};local head=1;local tree={}
    local function walk(use)
        while head<=#order do
            local a=order[head];head=head+1
            for _,l in ipairs(adj[a] or {}) do
                local b=l.a==a and l.b or l.a
                if depth[b]==nil and use(l) then depth[b]=depth[a]+1;order[#order+1]=b;tree[#tree+1]=l end
            end
        end
    end
    if entry then
        walk(function(l) return conn[l.a] and conn[l.a][l.b] end)
        head=1;walk(function(l) return (l.reasons.proximity or 0)>0 or (l.reasons.visibility or 0)>0 end)
    end
    for _,l in ipairs(tree) do if P.w_traversal>0 then l.weight=l.weight+P.w_traversal;l.reasons.traversal=(l.reasons.traversal or 0)+1 end end
    for _,a in ipairs(atoms) do a.depth=depth[a] end
    local out={};for _,l in pairs(links) do out[#out+1]=l end
    table.sort(out,function(x,y) if x.a.index~=y.a.index then return x.a.index<y.a.index end;return x.b.index<y.b.index end)
    return out,{entry=entry,visible=visible,visibility_pairs_skipped=skipped,unreached=#atoms-#order}
end

---------------------------------------------------------------------------
-- Clustering
---------------------------------------------------------------------------

local function cluster_of(a) return {atoms={a},nodes=a.nodes,box={min=Util.deepcopy(a.box.min),max=Util.deepcopy(a.box.max)},pin=a.pin,adj={},solid={},first=a.rank} end

local function fits(c1,c2,P)
    if c1.pin~=c2.pin and c1.pin and c2.pin then return false end
    if c1.nodes+c2.nodes>P.max_nodes then return false end
    local w,h=extent(union(c1.box,c2.box))
    return w<=P.max_extent and h<=P.max_extent
end

local function absorb(c1,c2,live)
    for _,a in ipairs(c2.atoms) do c1.atoms[#c1.atoms+1]=a end
    c1.nodes=c1.nodes+c2.nodes;c1.box=union(c1.box,c2.box);c1.pin=c1.pin or c2.pin;c1.first=math.min(c1.first,c2.first)
    for other,w in pairs(c2.adj) do
        if other~=c1 then c1.adj[other]=(c1.adj[other] or 0)+w;other.adj[c1]=(other.adj[c1] or 0)+w end
        other.adj[c2]=nil
    end
    for other,w in pairs(c2.solid) do
        if other~=c1 then c1.solid[other]=(c1.solid[other] or 0)+w;other.solid[c1]=(other.solid[c1] or 0)+w end
        other.solid[c2]=nil
    end
    c1.adj[c2]=nil;c1.solid[c2]=nil;live[c2]=nil
end

-- Links that make two atoms one walkable/contiguous space. A line of sight alone
-- never merges (it only adds weight), so a sector does not jump across rooms.
local SOLID={door=true,open=true,stairs=true,ramp=true,off_mesh=true,proximity=true}
local function solid(l) for r in pairs(l.reasons) do if SOLID[r] then return true end end;return false end

function SP:_cluster(atoms,links,P)
    local live,of={},{}
    -- Ties are broken along the expected traversal (entry first), not by ids.
    local ranked={};for _,a in ipairs(atoms) do ranked[#ranked+1]=a end
    table.sort(ranked,function(x,y) local dx,dy=x.depth or math.huge,y.depth or math.huge;if dx~=dy then return dx<dy end;return x.index<y.index end)
    for i,a in ipairs(ranked) do a.rank=i end
    -- Pinned atoms start merged, whatever the budget.
    local pinned={}
    for _,a in ipairs(atoms) do
        if a.pin and pinned[a.pin] then local c=pinned[a.pin];c.atoms[#c.atoms+1]=a;c.nodes=c.nodes+a.nodes;c.box=union(c.box,a.box);c.first=math.min(c.first,a.rank);of[a]=c
        else local c=cluster_of(a);live[c]=true;of[a]=c;if a.pin then pinned[a.pin]=c end end
    end
    for _,l in ipairs(links) do
        local c1,c2=of[l.a],of[l.b]
        if c1~=c2 then
            c1.adj[c2]=(c1.adj[c2] or 0)+l.weight;c2.adj[c1]=(c2.adj[c1] or 0)+l.weight
            if solid(l) then c1.solid[c2]=(c1.solid[c2] or 0)+l.weight;c2.solid[c1]=(c2.solid[c1] or 0)+l.weight end
        end
    end
    local function sorted_live()
        local list={};for c in pairs(live) do list[#list+1]=c end
        table.sort(list,function(x,y) return x.first<y.first end)
        return list
    end
    -- Greedy agglomeration: the strongest link per node first.
    while true do
        local best,bc1,bc2=0,nil,nil
        for _,c1 in ipairs(sorted_live()) do
            for c2,w in pairs(c1.adj) do
                if c1.first<c2.first and c1.solid[c2] and fits(c1,c2,P) then
                    local s=w/math.sqrt(math.max(1,c1.nodes)+math.max(1,c2.nodes))
                    if s>best+1e-9 or (math.abs(s-best)<=1e-9 and bc1 and (c1.first<bc1.first or (c1.first==bc1.first and c2.first<bc2.first))) then best,bc1,bc2=s,c1,c2 end
                end
            end
        end
        if not bc1 then break end
        absorb(bc1,bc2,live)
    end
    -- Small sectors join their best linked neighbour, else the nearest one that fits.
    local changed=true
    while changed do
        changed=false
        for _,c in ipairs(sorted_live()) do
            if live[c] and c.nodes<P.min_nodes and not c.pin then
                local target,score=nil,-math.huge
                for other,w in pairs(c.solid) do if live[other] and fits(c,other,P) and (w>score or (w==score and other.first<target.first)) then target,score=other,w end end
                if not target then
                    local best=math.huge
                    for other in pairs(live) do
                        if other~=c and fits(c,other,P) then local d=gap(c.box,other.box);if d<best or (d==best and other.first<target.first) then target,best=other,d end end
                    end
                    if target and best>P.preload+P.proximity_gap then target=nil end
                end
                if target then
                    if target.first<c.first then absorb(target,c,live) else absorb(c,target,live) end
                    changed=true;break
                end
            end
        end
    end
    return sorted_live()
end

---------------------------------------------------------------------------
-- Sectors
---------------------------------------------------------------------------

function SP:_compute(scope,P,a)
    local graph,gerr=self:_nav_graph(scope,a.navigation_graph_id);if gerr then return nil,gerr end
    local atoms,by_key,room_list,excluded,warnings=self:_atoms(scope,P,a.pins)
    if #atoms==0 then return nil,'nothing to partition: no rooms or objects in scope' end
    local entry_point=type(a.entry)=='table' and {x=num(a.entry.x,0),y=num(a.entry.y,0),z=num(a.entry.z,0)} or nil
    local links,info=self:_links(atoms,by_key,room_list,P,graph,entry_point)
    local clusters=self:_cluster(atoms,links,P)
    -- Order sectors along the expected traversal, then by position.
    for _,c in ipairs(clusters) do
        local d=math.huge;for _,x in ipairs(c.atoms) do if x.depth and x.depth<d then d=x.depth end end;c.depth=d
        table.sort(c.atoms,function(x,y) return x.index<y.index end)
    end
    table.sort(clusters,function(x,y) if x.depth~=y.depth then return x.depth<y.depth end;return x.first<y.first end)
    local base=slug(a.base_name or '');if base=='' then base=slug(scope.build_id or 'sector') end
    local sectors,sector_of={},{}
    for i,c in ipairs(clusters) do
        local rooms,objects,has_cell,has_room={}, {},false,false
        for _,x in ipairs(c.atoms) do
            sector_of[x]=i
            if x.kind=='room' then has_room=true;rooms[#rooms+1]={id=x.room_id,name=x.name} else has_cell=true end
            for _,id in ipairs(x.objects) do objects[#objects+1]=id end
        end
        local w,h=extent(c.box)
        sectors[i]={id=string.format('s%02d',i),name=base..'_'..string.format('%02d',i),category=has_cell and 'exterior' or 'interior',mixed=(has_cell and has_room) or nil,pin=c.pin,
            bounds=round_box(c.box),size={horizontal=r2(w),vertical=r2(h)},node_count=c.nodes,rooms=rooms,object_ids=objects,
            atoms=#c.atoms,traversal_depth=c.depth<math.huge and c.depth or nil,neighbours={},visible_from={}}
        if w>P.max_extent or h>P.max_extent then warnings[#warnings+1]=string.format('sector %s is %.0f m across, over max_extent %.0f m (one atom is that large)',sectors[i].name,math.max(w,h),P.max_extent) end
    end
    -- Neighbours, cut connectivity (transitions) and visibility between sectors.
    local nb,transitions={},{}
    for _,l in ipairs(links) do
        local s1,s2=sector_of[l.a],sector_of[l.b]
        if s1~=s2 then
            local k=math.min(s1,s2)..':'..math.max(s1,s2)
            nb[k]=nb[k] or {a=math.min(s1,s2),b=math.max(s1,s2),weight=0,reasons={}}
            nb[k].weight=nb[k].weight+l.weight
            for r,n in pairs(l.reasons) do nb[k].reasons[r]=(nb[k].reasons[r] or 0)+n end
            for _,d in ipairs(l.doors) do
                transitions[#transitions+1]={kind=d.kind,rooms=d.rooms,portal=d.portal,from=sectors[s1].name,to=sectors[s2].name,on_traversal=(l.reasons.traversal or 0)>0}
            end
        end
    end
    local nb_list={};for _,v in pairs(nb) do nb_list[#nb_list+1]=v end
    table.sort(nb_list,function(x,y) if x.a~=y.a then return x.a<y.a end;return x.b<y.b end)
    local cut_weight,total_weight=0,0
    for _,l in ipairs(links) do total_weight=total_weight+l.weight end
    for _,v in ipairs(nb_list) do
        cut_weight=cut_weight+v.weight
        table.insert(sectors[v.a].neighbours,{sector=sectors[v.b].name,weight=r2(v.weight),reasons=Util.deepcopy(v.reasons)})
        table.insert(sectors[v.b].neighbours,{sector=sectors[v.a].name,weight=r2(v.weight),reasons=Util.deepcopy(v.reasons)})
    end
    -- Streaming extents: a sector must be streamed in wherever the player can see
    -- it (an atom it is visible from) and `preload` m before the player reaches it.
    local need={}
    for i,s in ipairs(sectors) do need[i]={x=P.preload,y=P.preload,z=math.min(P.preload,math.max(4,P.preload/2))} end
    local function cover(i,box)
        local b=clusters[i].box
        for _,k in ipairs({'x','y','z'}) do
            local d=math.max(b.min[k]-box.min[k],box.max[k]-b.max[k],0)
            local cap=P.view_distance+P.preload
            need[i][k]=math.max(need[i][k],math.min(d,cap))
        end
    end
    local seen={}
    for _,v in ipairs(info.visible) do
        local s1,s2=sector_of[v.a],sector_of[v.b]
        if s1~=s2 then
            cover(s1,v.b.box);cover(s2,v.a.box)
            local k1,k2=s1..'>'..s2,s2..'>'..s1
            if not seen[k1] then seen[k1]=true;table.insert(sectors[s1].visible_from,sectors[s2].name) end
            if not seen[k2] then seen[k2]=true;table.insert(sectors[s2].visible_from,sectors[s1].name) end
        end
    end
    for i,s in ipairs(sectors) do
        table.sort(s.visible_from)
        s.streaming={x=r2(need[i].x),y=r2(need[i].y),z=r2(need[i].z)}
        s.streaming_box=round_box({min={x=clusters[i].box.min.x-need[i].x,y=clusters[i].box.min.y-need[i].y,z=clusters[i].box.min.z-need[i].z},
            max={x=clusters[i].box.max.x+need[i].x,y=clusters[i].box.max.y+need[i].y,z=clusters[i].box.max.z+need[i].z}})
    end
    -- Objects whose manual stream range is longer than their sector streams.
    local model=self.app.model
    for _,s in ipairs(sectors) do
        local longest=math.max(s.streaming.x,s.streaming.y)
        for _,id in ipairs(s.object_ids) do
            local o=model:get_object(id);local r=o and tonumber(o.stream_range)
            if r and r>longest+P.preload then warnings[#warnings+1]=string.format('%s has stream_range %.0f m but its sector %s streams %.0f m around its bounds',tostring(o.name),r,s.name,longest) end
        end
    end
    local traversal={};for _,s in ipairs(sectors) do if s.traversal_depth then traversal[#traversal+1]=s.name end end
    if info.unreached>0 then warnings[#warnings+1]=info.unreached..' room(s)/cell(s) are not reached from the entry by doors, links, sight or proximity; they are ordered last' end
    if info.visibility_pairs_skipped>0 then warnings[#warnings+1]=info.visibility_pairs_skipped..' atom pairs within view_distance were not tested for line of sight (limit '..MAX_VIS_PAIRS..'); lower view_distance' end
    if excluded.layer>0 then warnings[#warnings+1]=excluded.layer..' object(s) on layers that do not export are left out' end
    local nodes,largest,smallest=0,0,math.huge
    for _,s in ipairs(sectors) do nodes=nodes+s.node_count;largest=math.max(largest,s.node_count);smallest=math.min(smallest,s.node_count) end
    local counts={rooms=0,cells=0};for _,x in ipairs(atoms) do if x.kind=='room' then counts.rooms=counts.rooms+1 else counts.cells=counts.cells+1 end end
    local stats={sectors=#sectors,nodes=nodes,atoms=#atoms,rooms=counts.rooms,cells=counts.cells,links=#links,largest_sector=largest,smallest_sector=smallest,
        average_sector=r2(nodes/#sectors),transitions=#transitions,cut_weight=r2(cut_weight),kept_weight=r2(total_weight-cut_weight),
        visible_pairs=#info.visible,excluded_disabled=excluded.disabled,excluded_layer=excluded.layer,navigation_graph=graph and graph.id or nil}
    return {sectors=sectors,transitions=transitions,stats=stats,
        report={entry=info.entry and info.entry.name or nil,traversal=traversal,warnings=warnings},
        fingerprint=self:_fingerprint(scope)}
end

-- A digest of the rooms and objects a scope covers, to tell when a partition is out of date.
function SP:_fingerprint(scope)
    local rooms,objects=self:_scope_sets(scope)
    local parts={}
    for _,r in ipairs(self.app.model.data.rooms or {}) do
        if rooms[r.id] then
            local p=r.transform and r.transform.position or {};local s=r.size or {}
            parts[#parts+1]=string.format('r%s|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%d',r.id,num(p.x,0),num(p.y,0),num(p.z,0),num(s.width,0),num(s.depth,0),num(s.height,0),#(r.openings or {}))
        end
    end
    for _,o in ipairs(self.app.model.data.objects or {}) do
        if o.enabled~=false and in_scope(o,scope,rooms,objects) then
            local p=o.transform and o.transform.position or {}
            parts[#parts+1]=string.format('o%s|%.2f|%.2f|%.2f|%s|%s',o.id,num(p.x,0),num(p.y,0),num(p.z,0),tostring(o.room_id),tostring(o.layer))
        end
    end
    table.sort(parts)
    return hash(table.concat(parts,';'))
end

---------------------------------------------------------------------------
-- Records
---------------------------------------------------------------------------

local function normalize_pins(pins)
    if pins==nil then return {} end
    if type(pins)~='table' then return nil,'pins must be an object of room or object id -> sector label' end
    local out,n={},0
    for k,v in pairs(pins) do
        if type(k)~='string' or k=='' then return nil,'pins keys must be room or object ids' end
        local label=Util.trim(tostring(v or ''))
        if label=='' or not label:match('^[%w_%-]+$') then return nil,'pin label for '..k..' must use letters, digits, _ or -' end
        out[k]=label;n=n+1
    end
    if n>MAX_PINS then return nil,'at most '..MAX_PINS..' pins' end
    return out
end

local function summary(rec,res,dry)
    return {partition_id=rec and rec.id or nil,name=rec and rec.name or nil,dry_run=dry or nil,stats=Util.deepcopy(res.stats),sectors=Util.deepcopy(res.sectors),
        transitions=Util.deepcopy(res.transitions),report=Util.deepcopy(res.report),
        notice='Sector plan stored in LocationStudio. sector_partition_export writes one World Builder group per sector; World Builder builds the streaming sectors.'}
end

function SP:generate(a)
    a=a or {}
    local b=busy(self.app);if b and not a._inside and not a.dry_run then return nil,b end
    local P,err=SP.normalize_params(a.params);if not P then return nil,err end
    local pins;pins,err=normalize_pins(a.pins);if not pins then return nil,err end
    a.pins=pins
    local scope;scope,err=self:_scope(a);if not scope then return nil,err end
    local existing,index
    if a.partition_id and a.partition_id~='' then
        existing,index=self:get(a.partition_id)
        if not existing then return nil,'sector partition not found: '..tostring(a.partition_id) end
    elseif scope.build_id then
        for i,p in ipairs(self:list()) do if p.scope and p.scope.build_id==scope.build_id then existing,index=p,i end end
    end
    local base=a.base_name or (existing and existing.base_name)
    if base~=nil and (type(base)~='string' or not base:match('^[a-z0-9_]+$')) then return nil,'base_name must match [a-z0-9_]+ (sector names become World Builder group names)' end
    if base==nil then base=slug(scope.build_id or 'sector');if base=='' then base='sector' end end
    a.base_name=base
    local res;res,err=self:_compute(scope,P,a);if not res then return nil,err end
    if a.dry_run then return summary(nil,res,true) end
    local now=Util.now_iso()
    local name=Util.trim(a.name or '')~='' and Util.trim(a.name) or (existing and existing.name) or self:_default_name(scope)
    local rec={id=existing and existing.id or Util.make_id('secp'),name=name,base_name=base,format='locationstudio.sector-partition.v1',version=SP.VERSION,
        params=Util.deepcopy(P),pins=Util.deepcopy(pins),scope=Util.deepcopy(scope),entry=type(a.entry)=='table' and Util.deepcopy(a.entry) or nil,
        navigation_graph_id=a.navigation_graph_id,fingerprint=res.fingerprint,generated_at=now,mod_version=self.app.version,
        sectors=res.sectors,transitions=res.transitions,report=res.report,stats=res.stats,last_export=existing and existing.last_export or nil}
    local model=self.app.model
    if a._no_snapshot~=true then model:snapshot(existing and 'Regenerate sector partition' or 'Partition into sectors') end
    model.data.sector_partitions=model.data.sector_partitions or {}
    if index then model.data.sector_partitions[index]=rec else table.insert(model.data.sector_partitions,rec) end
    model:touch();self.app:mark_dirty()
    local out=summary(rec,res);out.replaced=existing~=nil
    return out
end

function SP:_default_name(scope)
    local m=self.app.model
    if scope.build_id then return 'Sectors: build '..scope.build_id end
    if scope.premise_id then local p=m:get_premise(scope.premise_id);return 'Sectors: '..(p and p.name or scope.premise_id) end
    if scope.room_ids then local r=m:get_room(scope.room_ids[1]);return 'Sectors: '..(r and r.name or 'rooms')..(#scope.room_ids>1 and (' +'..(#scope.room_ids-1)) or '') end
    return 'Sectors: project'
end

function SP:regenerate(id,patch)
    patch=patch or {}
    local rec=self:get(id);if not rec then return nil,'sector partition not found: '..tostring(id) end
    local params=Util.deepcopy(rec.params or {})
    for k,v in pairs(type(patch.params)=='table' and patch.params or {}) do params[k]=v end
    local pins=Util.deepcopy(rec.pins or {})
    if type(patch.pins)=='table' then for k,v in pairs(patch.pins) do if v==false or v=='' then pins[k]=nil else pins[k]=v end end end
    local a=Util.deepcopy(rec.scope or {});a.params=params;a.pins=pins;a.partition_id=rec.id;a.entry=patch.entry or rec.entry;a.dry_run=patch.dry_run
    a.navigation_graph_id=patch.navigation_graph_id or rec.navigation_graph_id;a.base_name=patch.base_name or rec.base_name;a.name=patch.name
    return self:generate(a)
end

function SP:delete(id)
    local b=busy(self.app);if b then return nil,b end
    local rec,i=self:get(id);if not rec then return nil,'sector partition not found: '..tostring(id) end
    local model=self.app.model
    model:snapshot('Delete sector partition');table.remove(model.data.sector_partitions,i)
    model:touch();self.app:mark_dirty()
    return {deleted=rec.id,name=rec.name}
end

function SP:summaries()
    local rows={}
    for _,p in ipairs(self:list()) do
        rows[#rows+1]={id=p.id,name=p.name,base_name=p.base_name,scope=Util.deepcopy(p.scope),sectors=p.stats and p.stats.sectors,nodes=p.stats and p.stats.nodes,generated_at=p.generated_at,
            last_export=p.last_export and p.last_export.name or nil}
    end
    return {items=rows,count=#rows}
end

-- Which sector an object is in.
function SP:sector_of(id,object_id)
    local rec=self:get(id);if not rec then return nil,'sector partition not found: '..tostring(id) end
    for _,s in ipairs(rec.sectors or {}) do for _,oid in ipairs(s.object_ids or {}) do if oid==object_id then return {sector=s.name,sector_id=s.id,category=s.category} end end end
    return nil,'object '..tostring(object_id)..' is not in partition '..rec.id
end

function SP:report(id)
    local rec=self:get(id);if not rec then return nil,'sector partition not found: '..tostring(id) end
    local out={partition_id=rec.id,name=rec.name,base_name=rec.base_name,params=Util.deepcopy(rec.params),pins=Util.deepcopy(rec.pins),scope=Util.deepcopy(rec.scope),
        generated_at=rec.generated_at,stats=Util.deepcopy(rec.stats),sectors=Util.deepcopy(rec.sectors),transitions=Util.deepcopy(rec.transitions),report=Util.deepcopy(rec.report),
        last_export=Util.deepcopy(rec.last_export)}
    local ok,fp=pcall(function() return self:_fingerprint(rec.scope) end)
    if ok then out.stale=fp~=rec.fingerprint end
    if out.stale then out.stale_hint='Rooms or objects changed since this partition was made; run sector_partition_regenerate.' end
    -- Objects added to the scope after partitioning.
    local assigned={};for _,s in ipairs(rec.sectors or {}) do for _,oid in ipairs(s.object_ids or {}) do assigned[oid]=true end end
    local ok2,rooms,objects=pcall(function() return self:_scope_sets(rec.scope) end)
    if ok2 then
        local missing,gone={},0
        for _,o in ipairs(self.app.model.data.objects or {}) do if o.enabled~=false and not assigned[o.id] and in_scope(o,rec.scope,rooms,objects) and (not self.app.layers or self.app.layers:export_enabled(o)) then missing[#missing+1]=o.id end end
        for oid in pairs(assigned) do if not self.app.model:get_object(oid) then gone=gone+1 end end
        out.unassigned=missing;out.missing_objects=gone
    end
    return out
end

---------------------------------------------------------------------------
-- Export: one World Builder group per sector
---------------------------------------------------------------------------

function SP:export(a)
    a=a or {}
    local b=busy(self.app);if b then return nil,b end
    local rec=self:get(a.partition_id);if not rec then return nil,'sector partition not found: '..tostring(a.partition_id) end
    local exporter=self.app.build_export;if not exporter then return nil,'World Builder export is unavailable' end
    local name=tostring(a.name or rec.base_name or '')
    if not name:match('^[a-z0-9_]+$') then return nil,'name must match [a-z0-9_]+ (it becomes the .archive, .xl and sector name).' end
    if a.allow_stale~=true then
        local fp=self:_fingerprint(rec.scope)
        if fp~=rec.fingerprint then return nil,'rooms or objects changed since this partition was made; regenerate it first or pass allow_stale=true' end
    end
    local wanted
    if type(a.sectors)=='table' then wanted={};for _,s in ipairs(a.sectors) do wanted[s]=true end end
    local groups={}
    for _,s in ipairs(rec.sectors or {}) do
        if not wanted or wanted[s.name] or wanted[s.id] then
            groups[#groups+1]={name=s.name,object_ids=Util.deepcopy(s.object_ids),category_name=s.category,level=a.level,streaming=Util.deepcopy(s.streaming)}
        end
    end
    if #groups==0 then return nil,'no sectors selected' end
    local r,err=exporter:export({name=name,groups=groups,allow_skipped=a.allow_skipped,xl_format=a.xl_format})
    if not r then return nil,err end
    rec.last_export={name=name,at=Util.now_iso(),sectors=#groups,exported=r.exported,world_builder_export_file=r.world_builder_export_file}
    self.app:mark_dirty()
    r.partition_id=rec.id
    return r
end

return SP
