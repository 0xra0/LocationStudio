local Util=require('modules/util')
local Procedural=require('modules/procedural')
local Surfaces=require('modules/surfaces')

-- Parametric room generator. One specification (width, length, height, wall
-- thickness, doors, windows, floor/ceiling type, trims, materials, lighting)
-- produces a complete room:
--   * a normal room record with its openings (so visibility, reverb, EDL room
--     frames and performance see a real room);
--   * procedural geometry per surface role (floor, walls, ceiling, trim, door
--     frames, windows), each its own material set, with collision;
--   * collision blockers behind window glass;
--   * portals for every opening, linked to adjoining generated rooms;
--   * lighting anchors on the ceiling (optionally real lights);
--   * snapping sockets (walls, corners, doors, windows, floor/ceiling centre,
--     light anchors) that objects can be snapped to;
--   * semantic surfaces (modules/surfaces.lua): interior floor, walls (without
--     the openings) and ceiling, and the exterior walls.
-- Everything is recorded in model.data.generated_rooms and regenerates or
-- deletes as one undo step.
--
-- Room frame: origin at the centre of the floor, x across the width, y along
-- the length, z up. width/length are the clear interior; walls stand outside
-- it. Opening offsets follow the builder: north/south walls run along +x,
-- east/west walls along +y, measured from the middle of the wall.
local RoomGen={};RoomGen.__index=RoomGen

local WALLS={north={axis='x',yaw=0},south={axis='x',yaw=0},east={axis='y',yaw=90},west={axis='y',yaw=90}}
local ROLES={'floor','walls','ceiling','trim','door_frames','windows'}
local FLOORS={slab=true,raised=true,none=true}
local CEILINGS={flat=true,beams=true,coffered=true,none=true}

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function bool(v,f) if v==nil then return f end;return v==true end
local function part_box(cx,cy,cz,sx,sy,sz,yaw,material) return {shape='box',center={x=cx,y=cy,z=cz},size={x=sx,y=sy,z=sz},rotation={roll=0,pitch=0,yaw=yaw or 0},material=material or 'main'} end

function RoomGen.new(app) return setmetatable({app=app},RoomGen) end

function RoomGen:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required and not app.authoring_plans.running then return 'Resolve authoring-plan recovery first' end
    return nil
end

local function registry(model) model.data.generated_rooms=model.data.generated_rooms or {};return model.data.generated_rooms end
function RoomGen:get(room_id) for i,r in ipairs(registry(self.app.model)) do if r.id==room_id then return r,i end end end

-- Material value: '<.mi>' (native mesh), '<.mesh>' (template import) or a procedural material table.
local function material(value,glass)
    local m
    if type(value)=='string' and value~='' then
        local v=value:lower()
        if v:match('%.mesh$') then m={template=value} else m={materials={main=value}} end
    elseif type(value)=='table' then m=Util.deepcopy(value) else m={} end
    if glass and glass~='' then m.materials=m.materials or {};m.materials.glass=glass end
    return m
end

-- Normalize and validate a specification.
function RoomGen.normalize(spec)
    spec=type(spec)=='table' and Util.deepcopy(spec) or {}
    local s={name=Util.trim(spec.name or '')~='' and Util.trim(spec.name) or 'Room',
        width=num(spec.width,5),length=num(spec.length or spec.depth,4),height=num(spec.height,3),wall_thickness=num(spec.wall_thickness,0.2),
        doors={},windows={},collision=bool(spec.collision,true),block_windows=bool(spec.block_windows,true)}
    if s.width<1 or s.width>100 or s.length<1 or s.length>100 then return nil,'width and length must be between 1 and 100 m' end
    if s.height<2 or s.height>30 then return nil,'height must be between 2 and 30 m' end
    if s.wall_thickness<0.05 or s.wall_thickness>2 then return nil,'wall_thickness must be between 0.05 and 2 m' end
    local f=type(spec.floor)=='table' and spec.floor or {type=spec.floor}
    s.floor={type=f.type or 'slab',thickness=num(f.thickness,0.2),raise=num(f.raise,0.15)}
    if not FLOORS[s.floor.type] then return nil,'floor type must be slab, raised or none' end
    local c=type(spec.ceiling)=='table' and spec.ceiling or {type=spec.ceiling}
    s.ceiling={type=c.type or 'flat',thickness=num(c.thickness,0.2),beam_spacing=num(c.beam_spacing,1.5),beam_width=num(c.beam_width,0.2),beam_depth=num(c.beam_depth,0.25)}
    if not CEILINGS[s.ceiling.type] then return nil,'ceiling type must be flat, beams, coffered or none' end
    if s.ceiling.beam_spacing<0.3 or s.ceiling.beam_width<=0 or s.ceiling.beam_depth<=0 or s.ceiling.beam_depth>=s.height/2 then return nil,'ceiling beams need spacing >= 0.3 m and a positive width/depth under half the height' end
    local t=type(spec.trim)=='table' and spec.trim or {}
    s.trim={skirting=bool(t.skirting,true),skirting_height=num(t.skirting_height,0.1),skirting_depth=num(t.skirting_depth,0.015),crown=bool(t.crown,false),crown_size=num(t.crown_size,0.08)}
    local l=type(spec.lighting)=='table' and spec.lighting or {anchors=spec.lighting}
    s.lighting={anchors=l.anchors or 'grid',spacing=num(l.spacing,3),drop=num(l.drop,0.05),create_lights=l.create_lights==true,light=type(l.light)=='table' and Util.deepcopy(l.light) or {}}
    if s.lighting.anchors~='grid' and s.lighting.anchors~='center' and s.lighting.anchors~='none' then return nil,'lighting.anchors must be grid, center or none' end
    if s.lighting.spacing<0.5 then return nil,'lighting.spacing must be at least 0.5 m' end
    if spec.collision_rules~=nil then
        local CG=package.loaded['modules/collision_gen']
        if not CG then return nil,'collision rules are unavailable' end
        local r,err=CG.normalize_rules(spec.collision_rules);if not r then return nil,'collision_rules: '..err end
        s.collision_rules=r
    end
    -- Semantic surface tags; false leaves a surface out.
    local sf=spec.surfaces;if sf~=nil and type(sf)~='table' then return nil,'surfaces must be {floor, walls, exterior, ceiling, traits}' end
    sf=sf or {}
    s.surfaces={floor='floor',walls='wall',exterior='exterior_wall',ceiling='ceiling'}
    for k,v in pairs(sf) do
        local key=k=='wall' and 'walls' or k
        if key=='traits' then
            local opt,err=Surfaces.normalize_option({traits=v});if err then return nil,'surfaces.traits: '..err end
            s.surfaces.traits=opt and opt.traits or nil
        elseif s.surfaces[key]==nil then return nil,'unknown surfaces key '..tostring(k)..' (floor, walls, exterior, ceiling, traits)'
        elseif v==false or v=='' then s.surfaces[key]=false
        else local ok,err=Surfaces.check_tag(v);if not ok then return nil,'surfaces.'..k..': '..err end;s.surfaces[key]=v end
    end
    local mats=type(spec.materials)=='table' and spec.materials or {}
    s.materials={floor=material(mats.floor),walls=material(mats.walls or mats.wall),ceiling=material(mats.ceiling),trim=material(mats.trim or mats.walls or mats.wall),
        door_frames=material(mats.frames or mats.frame or mats.trim),windows=material(mats.frames or mats.frame or mats.trim,type(mats.glass)=='string' and mats.glass or nil)}
    if s.materials.windows.materials and s.materials.windows.materials.glass and not s.materials.windows.materials.main then return nil,'materials.glass needs a frame material (materials.frame or materials.trim as a .mi)' end
    local function interior(wall) return WALLS[wall].axis=='x' and s.width or s.length end
    local function opening(o,kind,i)
        if type(o)~='table' or not WALLS[o.wall] then return nil,kind..' '..i..' needs wall north, south, east or west' end
        local out={wall=o.wall,offset=num(o.offset,0),width=num(o.width,kind=='door' and 1 or 1.5),height=num(o.height,kind=='door' and 2.1 or 1.2),
            sill=kind=='door' and 0 or num(o.sill,1),frame=bool(o.frame,true),frame_width=num(o.frame_width,kind=='door' and 0.08 or 0.06),
            glass=bool(o.glass,true),mullions_x=math.floor(num(o.mullions_x,0)),mullions_y=math.floor(num(o.mullions_y,0))}
        local half=interior(o.wall)/2
        local margin=out.frame and out.frame_width or 0
        if out.width<=0.3 or math.abs(out.offset)+out.width/2+margin>half+1e-6 then return nil,kind..' '..i..' does not fit on the '..o.wall..' wall ('..interior(o.wall)..' m)' end
        if out.sill+out.height+margin>s.height-(s.ceiling.type=='none' and 0 or 0.05) then return nil,kind..' '..i..' is taller than the room' end
        return out
    end
    for i,o in ipairs(type(spec.doors)=='table' and spec.doors or {}) do local d,err=opening(o,'door',i);if not d then return nil,err end;s.doors[#s.doors+1]=d end
    for i,o in ipairs(type(spec.windows)=='table' and spec.windows or {}) do local w,err=opening(o,'window',i);if not w then return nil,err end;s.windows[#s.windows+1]=w end
    -- Openings on one wall must not overlap (checked with their frames).
    for wall in pairs(WALLS) do
        local spans={}
        for _,list in ipairs({s.doors,s.windows}) do for _,o in ipairs(list) do if o.wall==wall then local m=o.frame and o.frame_width or 0;spans[#spans+1]={o.offset-o.width/2-m,o.offset+o.width/2+m} end end end
        table.sort(spans,function(a,b) return a[1]<b[1] end)
        for i=2,#spans do if spans[i][1]<spans[i-1][2]-1e-6 then return nil,'openings overlap on the '..wall..' wall' end end
    end
    return s
end

-- Wall placement in the room frame: centre of the wall line and its yaw.
local function wall_line(s,wall)
    local T=s.wall_thickness
    if wall=='north' then return 0,s.length/2+T/2,0,s.width+2*T end
    if wall=='south' then return 0,-(s.length/2+T/2),0,s.width+2*T end
    if wall=='east' then return s.width/2+T/2,0,90,s.length end
    return -(s.width/2+T/2),0,90,s.length
end
-- Room-frame point at distance `along` on a wall line.
local function on_wall(s,wall,along,dz,inset)
    local cx,cy,yaw=wall_line(s,wall)
    local inward=({north={0,-1},south={0,1},east={-1,0},west={1,0}})[wall]
    local d=(inset or 0)
    if yaw==0 then return cx+along+inward[1]*d,cy+inward[2]*d,dz end
    return cx+inward[1]*d,cy+along+inward[2]*d,dz
end

local function transform_parts(parts,dx,dy,dz,yaw)
    local out={}
    for _,p in ipairs(parts) do
        local q=Util.deepcopy(p)
        if q.shape=='prism' then
            for _,pt in ipairs(q.points) do local r=Procedural.rotate({x=pt.x,y=pt.y,z=0},{yaw=yaw});pt.x,pt.y=r.x+dx,r.y+dy end
            q.z0,q.z1=q.z0+dz,q.z1+dz
        else
            local c=Procedural.rotate(q.center,{roll=0,pitch=0,yaw=yaw})
            q.center={x=c.x+dx,y=c.y+dy,z=c.z+dz}
            q.rotation={roll=q.rotation.roll or 0,pitch=q.rotation.pitch or 0,yaw=(q.rotation.yaw or 0)+yaw}
        end
        out[#out+1]=q
    end
    return out
end
local function append(dst,src) for _,v in ipairs(src) do dst[#dst+1]=v end end

-- Everything the room consists of, in the room frame. Pure: no project changes.
function RoomGen.plan(spec)
    local s,err=RoomGen.normalize(spec);if not s then return nil,err end
    local G=Procedural.GENERATORS
    local W,L,H,T=s.width,s.length,s.height,s.wall_thickness
    local roles={}
    local floor_top=0
    -- Floor: covers the walls' footprint too.
    if s.floor.type~='none' then
        local parts=assert(G.box.fn({size={W+2*T,L+2*T,s.floor.thickness}}))
        parts[1].center.z=-s.floor.thickness/2
        if s.floor.type=='raised' then floor_top=s.floor.raise;append(parts,{part_box(0,0,floor_top/2,W,L,floor_top)}) end
        roles.floor=parts
    end
    -- Walls with openings.
    local walls={}
    for wall in pairs(WALLS) do
        local cx,cy,yaw,len=wall_line(s,wall)
        local ops={}
        for _,list in ipairs({s.doors,s.windows}) do for _,o in ipairs(list) do if o.wall==wall then ops[#ops+1]={offset=o.offset,width=o.width,height=o.height,sill=o.sill} end end end
        local parts,werr=G.wall.fn({length=len,height=H,thickness=T,openings=ops});if not parts then return nil,wall..' wall: '..tostring(werr) end
        for _,q in ipairs(parts) do q.surface=nil end
        append(walls,transform_parts(parts,cx,cy,0,yaw))
    end
    roles.walls=walls
    -- Ceiling.
    if s.ceiling.type~='none' then
        local c=s.ceiling;local parts={part_box(0,0,H+c.thickness/2,W+2*T,L+2*T,c.thickness)}
        local bw,bd,sp=c.beam_width,c.beam_depth,c.beam_spacing
        if c.type=='beams' or c.type=='coffered' then
            local n=math.max(1,math.floor(L/sp));for i=1,n-1 do parts[#parts+1]=part_box(0,-L/2+L*i/n,H-bd/2,W,bw,bd) end
            if c.type=='coffered' then local m=math.max(1,math.floor(W/sp));for i=1,m-1 do parts[#parts+1]=part_box(-W/2+W*i/m,0,H-bd/2,bw,L,bd) end end
        end
        roles.ceiling=parts
    end
    -- Trims: skirting between doors, optional crown moulding.
    local trim={}
    for wall,info in pairs(WALLS) do
        local len=info.axis=='x' and W or L
        if s.trim.skirting then
            local cuts={};for _,d in ipairs(s.doors) do if d.wall==wall then cuts[#cuts+1]={d.offset-d.width/2-(d.frame and d.frame_width or 0),d.offset+d.width/2+(d.frame and d.frame_width or 0)} end end
            table.sort(cuts,function(a,b) return a[1]<b[1] end)
            local cursor=-len/2
            local function seg(a,b)
                if b-a>0.02 then
                    local x,y,z=on_wall(s,wall,(a+b)/2,floor_top+s.trim.skirting_height/2,T/2+s.trim.skirting_depth/2)
                    trim[#trim+1]=part_box(x,y,z,b-a,s.trim.skirting_depth,s.trim.skirting_height,info.yaw)
                end
            end
            for _,cut in ipairs(cuts) do seg(cursor,cut[1]);cursor=math.max(cursor,cut[2]) end
            seg(cursor,len/2)
        end
        if s.trim.crown and s.ceiling.type~='none' then
            local x,y,z=on_wall(s,wall,0,H-s.trim.crown_size/2,T/2+s.trim.crown_size/2)
            trim[#trim+1]=part_box(x,y,z,len,s.trim.crown_size,s.trim.crown_size,info.yaw)
        end
    end
    if #trim>0 then roles.trim=trim end
    -- Door frames and windows on the wall centre line.
    local frames,windows={},{}
    for _,d in ipairs(s.doors) do
        if d.frame then
            local x,y=on_wall(s,d.wall,d.offset,0,0)
            append(frames,transform_parts(assert(G.door_frame.fn({width=d.width,height=d.height,frame=d.frame_width,depth=T+0.04})),x,y,0,WALLS[d.wall].yaw))
        end
    end
    for _,w in ipairs(s.windows) do
        local x,y=on_wall(s,w.wall,w.offset,0,0)
        local parts
        if w.frame then parts=assert(G.window.fn({width=w.width,height=w.height,sill=w.sill,frame=w.frame_width,depth=T+0.02,mullions_x=w.mullions_x,mullions_y=w.mullions_y,glass=w.glass}))
        elseif w.glass then parts={part_box(0,0,w.sill+w.height/2,w.width,0.01,w.height,0,'glass')} end
        if parts then append(windows,transform_parts(parts,x,y,0,WALLS[w.wall].yaw)) end
    end
    if #frames>0 then roles.door_frames=frames end
    if #windows>0 then roles.windows=windows end
    -- Portals, anchors, sockets.
    local portals={}
    local function portal(o,kind,i)
        local x,y=on_wall(s,o.wall,o.offset,0,0)
        local n=({north={0,1},south={0,-1},east={1,0},west={-1,0}})[o.wall]
        portals[#portals+1]={id=kind..'_'..i,kind=kind,wall=o.wall,center={x=x,y=y,z=o.sill+o.height/2},width=o.width,height=o.height,sill=o.sill,normal={x=n[1],y=n[2],z=0}}
    end
    for i,d in ipairs(s.doors) do portal(d,'door',i) end
    for i,w in ipairs(s.windows) do portal(w,'window',i) end
    local anchors={}
    if s.lighting.anchors=='center' then anchors[1]={id='light_1',position={x=0,y=0,z=H-s.lighting.drop}}
    elseif s.lighting.anchors=='grid' then
        local nx,ny=math.max(1,math.floor(W/s.lighting.spacing+0.5)),math.max(1,math.floor(L/s.lighting.spacing+0.5))
        for i=1,nx do for j=1,ny do anchors[#anchors+1]={id='light_'..#anchors+1,position={x=-W/2+W*(i-0.5)/nx,y=-L/2+L*(j-0.5)/ny,z=H-s.lighting.drop}} end end
    end
    local sockets={{id='floor_center',kind='floor',position={x=0,y=0,z=floor_top},yaw=0},{id='ceiling_center',kind='ceiling',position={x=0,y=0,z=H},yaw=0}}
    local facing={north=180,south=0,east=90,west=-90}
    for wall in pairs(WALLS) do
        local x,y=on_wall(s,wall,0,0,T/2)
        sockets[#sockets+1]={id='wall_'..wall,kind='wall',position={x=x,y=y,z=floor_top},yaw=facing[wall],wall=wall}
    end
    for _,c in ipairs({{'ne',1,1},{'nw',-1,1},{'se',1,-1},{'sw',-1,-1}}) do
        sockets[#sockets+1]={id='corner_'..c[1],kind='corner',position={x=c[2]*W/2,y=c[3]*L/2,z=floor_top},yaw=math.deg(math.atan2(c[2],-c[3]))}
    end
    for _,p in ipairs(portals) do
        local base={x=p.center.x,y=p.center.y}
        local inward=({north={0,-1},south={0,1},east={-1,0},west={1,0}})[p.wall]
        sockets[#sockets+1]={id=p.id,kind=p.kind,position={x=base.x+inward[1]*T/2,y=base.y+inward[2]*T/2,z=p.kind=='door' and floor_top or p.sill},yaw=facing[p.wall],wall=p.wall}
    end
    for _,a in ipairs(anchors) do sockets[#sockets+1]={id=a.id,kind='light',position=Util.deepcopy(a.position),yaw=0} end
    -- Semantic surfaces per role, in the room frame.
    local st=s.surfaces;local surfaces={floor={},walls={},ceiling={}}
    local function rect(list,tag,c,n,su,sv)
        if tag and su>0.01 and sv>0.01 then list[#list+1]={tag=tag,traits=st.traits and Util.deepcopy(st.traits) or nil,center=c,normal=n,size={u=su,v=sv}} end
    end
    if s.floor.type~='none' then rect(surfaces.floor,st.floor,{x=0,y=0,z=floor_top},{x=0,y=0,z=1},W,L) end
    if s.ceiling.type~='none' then rect(surfaces.ceiling,st.ceiling,{x=0,y=0,z=H},{x=0,y=0,z=-1},W,L) end
    local inward_of={north={0,-1},south={0,1},east={-1,0},west={1,0}}
    for _,wall in ipairs({'north','east','south','west'}) do
        local cx,cy,yaw,full=wall_line(s,wall)
        local inward=inward_of[wall]
        local ops={}
        for _,list in ipairs({s.doors,s.windows}) do for _,o in ipairs(list) do if o.wall==wall then ops[#ops+1]={offset=o.offset,width=o.width,height=o.height,sill=o.sill} end end end
        -- Inner faces span the interior length from the floor top; exterior faces the full wall.
        for _,side in ipairs({{tag=st.walls,length=WALLS[wall].axis=='x' and W or L,sign=1,z0=floor_top},{tag=st.exterior,length=full,sign=-1,z0=0}}) do
            if side.tag then
                local parts=G.wall.fn({length=side.length,height=H,thickness=T,openings=ops})
                for _,q in ipairs(parts or {}) do
                    local z0=math.max(side.z0,q.center.z-q.size.z/2);local z1=math.min(H,q.center.z+q.size.z/2)
                    local r=Procedural.rotate({x=q.center.x,y=0,z=0},{yaw=yaw})
                    local c={x=cx+r.x+side.sign*inward[1]*T/2,y=cy+r.y+side.sign*inward[2]*T/2,z=(z0+z1)/2}
                    rect(surfaces.walls,side.tag,c,{x=side.sign*inward[1],y=side.sign*inward[2],z=0},q.size.x,z1-z0)
                end
            end
        end
    end
    return {spec=s,roles=roles,portals=portals,anchors=anchors,sockets=sockets,floor_top=floor_top,surfaces=surfaces}
end

function RoomGen:_world(room,p)
    local r=Procedural.rotate(p,room.transform.rotation)
    return {x=room.transform.position.x+r.x,y=room.transform.position.y+r.y,z=room.transform.position.z+r.z}
end

function RoomGen:_clear(rec)
    local model=self.app.model
    for _,id in pairs(rec.piece_ids or {}) do if model:get_object(id) and self.app.procedural then local ok,err=self.app.procedural:delete(id);if not ok then return nil,err end end end
    for _,list in ipairs({rec.collider_ids or {},rec.light_ids or {}}) do
        for _,id in ipairs(list) do local o=model:get_object(id);if o then if self.app.placement:is_tracked(o) then self.app.placement:despawn(o) end;model:delete_objects({id}) end end
    end
    if rec.group_id and model:get_object_group(rec.group_id) then
        for i,g in ipairs(model.data.object_groups) do if g.id==rec.group_id then table.remove(model.data.object_groups,i);break end end
    end
    return true
end

-- Build pieces for a room record from a plan; fills rec.
function RoomGen:_build(room,plan,rec)
    local s=plan.spec;local app=self.app
    -- Room-scope collision rules apply to every piece (modules/collision_gen.lua).
    local cr=app.model.data.collision_rules
    if s.collision_rules~=nil and type(cr)=='table' and type(cr.rooms)=='table' then cr.rooms[room.id]=next(s.collision_rules) and Util.deepcopy(s.collision_rules) or nil end
    rec.piece_ids={};rec.collider_ids={};rec.light_ids={}
    local ids={}
    for _,role in ipairs(ROLES) do
        local parts=plan.roles[role]
        if parts then
            local collision=s.collision and (role=='floor' or role=='walls' or role=='ceiling')
            local r,err=app.procedural:create({generator='compound',params={parts=parts,surfaces=plan.surfaces[role]},name=room.name..' / '..role,premise_id=room.premise_id,room_id=room.id,
                layer='shell',transform=Util.deepcopy(room.transform),material=s.materials[role],collision=collision,spawn=true,
                mesh_path=app.procedural:settings().mesh_root..'\\'..tostring(room.name):lower():gsub('[^%w]+','_')..'_'..room.id..'\\'..role..'.mesh'})
            if not r then return nil,role..': '..tostring(err) end
            r.object.metadata.room_generator={room_id=room.id,role=role}
            rec.piece_ids[role]=r.object.id;ids[#ids+1]=r.object.id
            for _,cid in ipairs(r.object.metadata.procedural.collider_ids or {}) do ids[#ids+1]=cid end
        end
    end
    if s.collision and s.block_windows and app.collision then
        for _,p in ipairs(plan.portals) do
            if p.kind=='window' then
                local c=self:_world(room,p.center)
                local r,err=app.collision:create_primitive({premise_id=room.premise_id,room_id=room.id,name=room.name..' / '..p.id..' blocker',shape='box',
                    size={x=p.width,y=s.wall_thickness,z=p.height},visualize=false,
                    transform={position={x=c.x,y=c.y,z=c.z,w=1},rotation={roll=0,pitch=0,yaw=(room.transform.rotation.yaw or 0)+WALLS[p.wall].yaw}}})
                if not r then return nil,'window blocker: '..tostring(err) end
                r.object.metadata.room_generator={room_id=room.id,role='window_blocker'}
                rec.collider_ids[#rec.collider_ids+1]=r.object.id;ids[#ids+1]=r.object.id
            end
        end
    end
    if s.lighting.create_lights and #plan.anchors>0 then
        if not app.lighting then return nil,'lighting is unavailable' end
        local l=s.lighting.light
        local config={color=l.color or {1,0.95,0.85},intensity=num(l.intensity,60),radius=num(l.radius,s.lighting.spacing*2),flickerStrength=0,flickerPeriod=0.2,flickerOffset=0}
        for _,a in ipairs(plan.anchors) do
            local p=self:_world(room,a.position)
            local o,err=app.lighting:create({premise_id=room.premise_id,room_id=room.id,name=room.name..' / '..a.id,config=config,
                transform={position={x=p.x,y=p.y,z=p.z,w=1},rotation={roll=0,pitch=0,yaw=0}}})
            if not o then return nil,'light: '..tostring(err) end
            o.metadata.room_generator={room_id=room.id,role='light',anchor=a.id}
            rec.light_ids[#rec.light_ids+1]=o.id;ids[#ids+1]=o.id
        end
    end
    -- Room openings mirror the spec so room-aware tools see the portals.
    room.openings={}
    for _,list in ipairs({{s.doors,'door'},{s.windows,'window'}}) do
        for _,o in ipairs(list[1]) do room.openings[#room.openings+1]={id=Util.make_id('opening'),kind=list[2],wall=o.wall,offset=o.offset,width=o.width,height=o.height,sill=o.sill,template=''} end
    end
    local group=self.app.model:create_object_group({name=room.name..' (generated)',premise_id=room.premise_id,room_id=room.id,object_ids=ids,pivot_mode='explicit',
        pivot={position=Util.deepcopy(room.transform.position),rotation=Util.deepcopy(room.transform.rotation)}},true)
    rec.group_id=group and group.id or nil
    rec.portals=plan.portals;rec.anchors=plan.anchors;rec.sockets=plan.sockets;rec.spec=plan.spec
    rec.bounds=app.bounds_gen and app.bounds_gen:room_bounds(room.id) or nil
    return true
end

-- Link portals that open into another generated room of the same premise.
function RoomGen:_link_portals(premise_id)
    local model=self.app.model;local list={}
    for _,rec in ipairs(registry(model)) do local room=model:get_room(rec.id);if room and room.premise_id==premise_id then list[#list+1]={rec=rec,room=room} end end
    for _,a in ipairs(list) do
        for _,p in ipairs(a.rec.portals or {}) do
            p.connects=nil
            if p.kind=='door' then
                local c=self:_world(a.room,{x=p.center.x+p.normal.x*a.rec.spec.wall_thickness,y=p.center.y+p.normal.y*a.rec.spec.wall_thickness,z=p.center.z})
                for _,b in ipairs(list) do
                    if b.rec.id~=a.rec.id then
                        local local_p=Procedural.rotate({x=c.x-b.room.transform.position.x,y=c.y-b.room.transform.position.y,z=0},{yaw=-(b.room.transform.rotation.yaw or 0)})
                        local s=b.rec.spec;local T=s.wall_thickness
                        if math.abs(local_p.x)<=s.width/2+T*1.5 and math.abs(local_p.y)<=s.length/2+T*1.5 then p.connects=b.rec.id end
                    end
                end
            end
        end
    end
end

local function collapse(model,mark) while #model.undo_stack>mark do table.remove(model.undo_stack) end end

function RoomGen:_transaction(label,fn)
    local busy=self:_busy();if busy then return nil,busy end
    if not self.app.procedural then return nil,'procedural geometry is unavailable' end
    local model=self.app.model
    local before=Util.deepcopy(model.data)
    local live={};for _,o in ipairs(model.data.objects) do if self.app.placement:is_tracked(o) then live[#live+1]=o.id end end
    model:snapshot(label);local mark=#model.undo_stack
    local ok,result,err=pcall(fn)
    if not ok or not result then
        err=ok and err or tostring(result)
        -- Remove what this call spawned, restore the data, then bring back what was live before.
        for _,o in ipairs(model.data.objects) do if self.app.placement:is_tracked(o) then pcall(function() self.app.placement:despawn(o) end) end end
        model.data=before;collapse(model,mark-1)
        for _,id in ipairs(live) do local o=model:get_object(id);if o then pcall(function() self.app.placement:spawn(o) end) end end
        return nil,err
    end
    collapse(model,mark);model:touch();self.app:mark_dirty()
    return result
end

function RoomGen:preview(spec)
    local plan,err=RoomGen.plan(spec);if not plan then return nil,err end
    local counts={}
    for role,parts in pairs(plan.roles) do counts[role]=#parts end
    local tags={}
    for _,list in pairs(plan.surfaces) do for _,q in ipairs(list) do tags[q.tag]=(tags[q.tag] or 0)+1 end end
    return {spec=plan.spec,parts=counts,portals=plan.portals,anchors=plan.anchors,sockets=plan.sockets,surfaces=tags}
end

function RoomGen:create(args)
    args=args or {}
    local plan,err=RoomGen.plan(args.spec or args);if not plan then return nil,err end
    local premise=self.app.model:get_premise(args.premise_id or self.app.selected_premise_id);if not premise then return nil,'select a premise or give premise_id' end
    local transform=args.transform
    if not transform then
        local t
        if args.source=='aim' then local hit;hit,err=self.app.game:aim_point(num(args.distance,8));if not hit then return nil,err end;t={position=hit.position}
        else t,err=self.app.game:capture_transform();if not t then return nil,err end end
        transform={position={x=t.position.x,y=t.position.y,z=t.position.z,w=1},rotation={roll=0,pitch=0,yaw=num(args.yaw,0)}}
    end
    local s=plan.spec
    return self:_transaction('Generate room '..s.name,function()
        local room,rerr=self.app.builder:create_room({premise_id=premise.id,name=s.name,width=s.width,depth=s.length,height=s.height,wall_thickness=math.min(s.wall_thickness,s.width/2-0.01),
            transform=transform,generate_shell=false,tags={'parametric'}})
        if not room then return nil,rerr end
        local rec={id=room.id,created_at=Util.now_iso()}
        local ok,berr=self:_build(room,plan,rec);if not ok then return nil,berr end
        table.insert(registry(self.app.model),rec)
        self:_link_portals(premise.id)
        if self.app.selection then self.app.selection:set('room',room.id) end
        return {room=room,generated=Util.deepcopy(rec)}
    end)
end

function RoomGen:update(room_id,patch)
    local rec=self:get(room_id);if not rec then return nil,'not a generated room' end
    local room=self.app.model:get_room(room_id);if not room then return nil,'room not found' end
    local spec=Util.deepcopy(rec.spec)
    for k,v in pairs(type(patch)=='table' and (patch.spec or patch) or {}) do if k~='id' then spec[k]=Util.deepcopy(v) end end
    local plan,err=RoomGen.plan(spec);if not plan then return nil,err end
    return self:_transaction('Regenerate room '..plan.spec.name,function()
        local r=self:get(room_id);local ok,cerr=self:_clear(r);if not ok then return nil,cerr end
        local s=plan.spec
        room=self.app.model:get_room(room_id)
        room.name=s.name;room.size={width=s.width,depth=s.length,height=s.height};room.wall_thickness=math.min(s.wall_thickness,s.width/2-0.01)
        local bok,berr=self:_build(room,plan,r);if not bok then return nil,berr end
        r.updated_at=Util.now_iso()
        self:_link_portals(room.premise_id)
        return {room=room,generated=Util.deepcopy(r)}
    end)
end

function RoomGen:delete(room_id)
    local rec,index=self:get(room_id);if not rec then return nil,'not a generated room' end
    return self:_transaction('Delete generated room',function()
        local r,i=self:get(room_id);local ok,err=self:_clear(r);if not ok then return nil,err end
        table.remove(registry(self.app.model),i)
        local room=self.app.model:get_room(room_id);local premise_id=room and room.premise_id
        for k,v in ipairs(self.app.model.data.rooms) do if v.id==room_id then table.remove(self.app.model.data.rooms,k);break end end
        if premise_id then self:_link_portals(premise_id) end
        return {deleted=room_id}
    end)
end

function RoomGen:list(args)
    args=args or {};local rows={}
    for _,rec in ipairs(registry(self.app.model)) do
        local room=self.app.model:get_room(rec.id)
        if room and (not args.premise_id or args.premise_id=='' or room.premise_id==args.premise_id) then
            local pieces=0;for _ in pairs(rec.piece_ids or {}) do pieces=pieces+1 end
            rows[#rows+1]={id=rec.id,name=room.name,size={width=rec.spec.width,length=rec.spec.length,height=rec.spec.height},doors=#rec.spec.doors,windows=#rec.spec.windows,
                floor=rec.spec.floor.type,ceiling=rec.spec.ceiling.type,pieces=pieces,lights=#(rec.light_ids or {}),portals=#(rec.portals or {}),sockets=#(rec.sockets or {})}
        end
    end
    return {items=rows,count=#rows}
end

-- World transform of a socket.
function RoomGen:socket(room_id,socket_id)
    local rec=self:get(room_id);if not rec then return nil,'not a generated room' end
    local room=self.app.model:get_room(room_id)
    for _,sk in ipairs(rec.sockets or {}) do
        if sk.id==socket_id then
            local p=self:_world(room,sk.position)
            return {id=sk.id,kind=sk.kind,wall=sk.wall,transform={position={x=p.x,y=p.y,z=p.z,w=1},rotation={roll=0,pitch=0,yaw=(room.transform.rotation.yaw or 0)+(sk.yaw or 0)}}}
        end
    end
    return nil,'socket not found: '..tostring(socket_id)
end

-- Snap an object to a socket (optionally offset in the socket's facing frame). One undo step.
function RoomGen:snap(object_id,room_id,socket_id,args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local o=self.app.model:get_object(object_id);if not o then return nil,'object not found' end
    if o.locked then return nil,'object is locked' end
    if o.metadata and o.metadata.room_generator then return nil,'generated room pieces cannot be snapped; regenerate the room instead' end
    local sk,err=self:socket(room_id,socket_id);if not sk then return nil,err end
    local off=Procedural.rotate({x=num(args.offset_x,0),y=num(args.offset_y,0),z=num(args.offset_z,0)},sk.transform.rotation)
    self.app.model:snapshot('Snap to socket')
    o.transform.position={x=sk.transform.position.x+off.x,y=sk.transform.position.y+off.y,z=sk.transform.position.z+off.z,w=1}
    if args.align~=false then o.transform.rotation={roll=0,pitch=0,yaw=sk.transform.rotation.yaw+num(args.yaw,0)} end
    self.app.model:touch();self.app:mark_dirty()
    if self.app.placement:is_tracked(o) then self.app.placement:refresh(o) end
    return {object_id=o.id,socket=socket_id,transform=Util.deepcopy(o.transform)}
end

return RoomGen
