-- Read-only prop validation from imported resource bounds and optional live raycasts.
-- Mesh triangle checks require extracted GLB data; these checks report their proxy method.
local PropValidators={}
PropValidators.__index=PropValidators

local function finite(v,default)
    v=tonumber(v);if not v or v~=v or v==math.huge or v==-math.huge then return default end;return v
end
local function rotate(x,y,yaw)
    local r=math.rad(yaw or 0);local c,s=math.cos(r),math.sin(r);return x*c-y*s,x*s+y*c
end
local function cross(a,b,c) return (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x) end
local function point_in_poly(p,poly)
    local inside=false;local j=#poly
    for i=1,#poly do local a,b=poly[i],poly[j]
        if ((a.y>p.y)~=(b.y>p.y)) and p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x then inside=not inside end;j=i
    end
    return inside
end
local function project(poly,ax,ay)
    local lo,hi=math.huge,-math.huge
    for _,p in ipairs(poly) do local v=p.x*ax+p.y*ay;lo=math.min(lo,v);hi=math.max(hi,v) end
    return lo,hi
end
local function polygons_overlap(a,b,tol)
    local smallest=math.huge
    for _,poly in ipairs({a,b}) do for i=1,#poly do
        local p,q=poly[i],poly[i%#poly+1];local dx,dy=q.x-p.x,q.y-p.y;local l=math.sqrt(dx*dx+dy*dy)
        if l>1e-8 then local ax,ay=-dy/l,dx/l;local amin,amax=project(a,ax,ay);local bmin,bmax=project(b,ax,ay)
            local depth=math.min(amax,bmax)-math.max(amin,bmin);if depth<=tol then return false,depth end;smallest=math.min(smallest,depth)
        end
    end end
    return true,smallest
end

function PropValidators.new(app) return setmetatable({app=app},PropValidators) end
function PropValidators:_object(id)
    local row,err=self.app.model:get_object(id);if not row then return nil,err or ('object not found: '..tostring(id)) end
    local box;box,err=self.app.asset_bounds:world_aabb(id);if not box then return nil,err end
    local p=row.transform.position;local b=row.metadata.asset_bounds;local r=row.transform.rotation or {}
    local wb=row.metadata.world_builder;local scale=type(wb)=='table' and wb.apply_scale==true and row.size or {x=1,y=1,z=1}
    local poly={}
    for _,xy in ipairs({{b.min.x,b.min.y},{b.max.x,b.min.y},{b.max.x,b.max.y},{b.min.x,b.max.y}}) do
        local x,y=rotate(xy[1]*(scale.x or 1),xy[2]*(scale.y or 1),r.yaw)
        poly[#poly+1]={x=x+p.x,y=y+p.y}
    end
    return {row=row,aabb=box.aabb,poly=poly}
end
function PropValidators:_select(a)
    a=a or {};local ids={};local seen={}
    if type(a.object_ids)=='table' and #a.object_ids>0 then
        for _,id in ipairs(a.object_ids) do if not seen[id] then
            local row=self.app.model:get_object(tostring(id));if not row then return nil,'object not found: '..tostring(id) end
            if a.premise_id and row.premise_id~=a.premise_id then return nil,'object is outside requested premise: '..tostring(id) end
            seen[id]=true;ids[#ids+1]=tostring(id)
        end end
    else
        for _,row in ipairs(self.app.model.data.objects or {}) do if (not a.premise_id or row.premise_id==a.premise_id) and row.enabled~=false and row.visible~=false then ids[#ids+1]=row.id end end
    end
    if #ids==0 then return nil,'no placed objects in scope' end
    if #ids>160 then return nil,'prop validators are limited to 160 objects per request' end
    return ids
end
function PropValidators:clipcheck(a)
    a=a or {};local ids,err=self:_select(a);if not ids then return nil,err end
    if #ids<2 then return nil,'clipcheck requires at least two placed objects' end
    local tol=finite(a.tolerance,0.02);if tol<0 or tol>2 then return nil,'tolerance must be between 0 and 2 meters' end
    local rows,skipped={},{}
    for _,id in ipairs(ids) do local item,e=self:_object(id);if item then rows[#rows+1]=item else skipped[#skipped+1]={object_id=id,reason=e} end end
    local pairs={}
    for i=1,#rows-1 do for j=i+1,#rows do local x,y=rows[i],rows[j]
        local z=math.min(x.aabb.max.z,y.aabb.max.z)-math.max(x.aabb.min.z,y.aabb.min.z)
        if z>tol then local hit,depth=polygons_overlap(x.poly,y.poly,tol)
            if hit then pairs[#pairs+1]={a=x.row.id,b=y.row.id,a_name=x.row.name,b_name=y.row.name,vertical_intersection_m=z,footprint_penetration_m=depth,approximate=true} end
        end
    end end
    return {validator='clipcheck',tested=#rows,skipped=skipped,collision_count=#pairs,collisions=pairs,tolerance_m=tol,
        method='oriented rectangular footprints from imported local AABBs plus vertical interval; no triangle mesh data',
        warning='Bounds proxy only: irregular mesh shapes and sub-bound voids are not represented.'}
end
function PropValidators:_live()
    if not self.app.game or not self.app.game:is_ready() then return nil,'live game spatial queries are unavailable' end
    return true
end
function PropValidators:_cast(x,y,z1,z2,groups)
    return self.app.game:raycast({x=x,y=y,z=z1},{x=x,y=y,z=z2},groups)
end
function PropValidators:fixturecheck(a)
    a=a or {};local ready,err=self:_live();if not ready then return nil,err end
    local ids;ids,err=self:_select(a);if not ids then return nil,err end
    local cell=finite(a.cell_size,0.25);if cell<0.1 or cell>1 then return nil,'cell_size must be between 0.1 and 1 meter' end
    local margin=finite(a.margin,0.25);if margin<0 or margin>2 then return nil,'margin must be between 0 and 2 meters' end
    local results,skipped={},{}
    for _,id in ipairs(ids) do
        local item,e=self:_object(id)
        if not item then skipped[#skipped+1]={object_id=id,reason=e}
        else
            local bb=item.aabb;local xs,ys={},{}
            for x=bb.min.x+cell/2,bb.max.x,cell do for y=bb.min.y+cell/2,bb.max.y,cell do
                if point_in_poly({x=x,y=y},item.poly) then xs[#xs+1]=x;ys[#ys+1]=y end
            end end
            local tested,hits=0,{}
            if #xs>500 then skipped[#skipped+1]={object_id=id,reason='footprint exceeds 500 ray cells; increase cell_size'} else
                for i,x in ipairs(xs) do local y=ys[i];tested=tested+1
                    local down=self:_cast(x,y,bb.max.z+0.30,bb.min.z+0.015,{'Static'})
                    if down and down.position and down.position.z<bb.max.z+0.295 and down.position.z>bb.min.z+0.015 then
                        hits[#hits+1]={x=x,y=y,z=down.position.z,side='down',clearance_m=down.position.z-bb.max.z}
                    end
                    local up=self:_cast(x,y,bb.min.z+0.015,bb.max.z+margin,{'Static'})
                    if up and up.position and up.position.z>bb.min.z+0.018 then
                        hits[#hits+1]={x=x,y=y,z=up.position.z,side='up',clearance_m=up.position.z-bb.max.z}
                    end
                end
                results[#results+1]={object_id=id,name=item.row.name,tested_cells=tested,fixture_hits=#hits,hits=hits}
            end
        end
    end
    return {validator='fixturecheck',live=true,collision_group='Static',tested=#results,results=results,skipped=skipped,cell_size_m=cell,margin_m=margin,
        method='live vertical Static raycasts over an oriented bounds footprint',
        warning='Static collision hits are not tagged by vanilla/mod source. Bounds proxy can over-report for non-box props.'}
end
function PropValidators:fitcheck(a)
    a=a or {};local ready,err=self:_live();if not ready then return nil,err end
    local ids;ids,err=self:_select(a);if not ids then return nil,err end
    local mode=a.mode or 'live';if mode~='live' and mode~='wall' then return nil,"mode must be 'live' or 'wall'" end
    local max_distance=finite(a.max_distance,4);if max_distance<0.1 or max_distance>30 then return nil,'max_distance must be between 0.1 and 30 meters' end
    local results,skipped={},{}
    for _,id in ipairs(ids) do
        local item,e=self:_object(id)
        if not item then skipped[#skipped+1]={object_id=id,reason=e}
        else
            local bb=item.aabb;local p=item.row.transform.position;local row={object_id=id,name=item.row.name,mode=mode,hits={}}
            if mode=='live' then
                -- Static-only avoids a false self-hit from the checked dynamic prop. It intentionally
                -- does not claim support from other dynamic props.
                local points={}
                for _,corner in ipairs(item.poly) do points[#points+1]={x=corner.x,y=corner.y} end
                points[#points+1]={x=(bb.min.x+bb.max.x)/2,y=(bb.min.y+bb.max.y)/2}
                for i,pt in ipairs(points) do
                    local hit=self:_cast(pt.x,pt.y,bb.min.z+0.30,bb.min.z-0.40,{'Static'})
                    row.hits[i]={x=pt.x,y=pt.y,hit=hit~=nil,support_z=hit and hit.position.z or nil,gap_m=hit and (bb.min.z-hit.position.z) or nil}
                end
            else
                local center={x=(bb.min.x+bb.max.x)/2,y=(bb.min.y+bb.max.y)/2}
                local yaw=finite(item.row.transform.rotation and item.row.transform.rotation.yaw,0)
                local dirs={{name='+x',x=math.cos(math.rad(yaw)),y=math.sin(math.rad(yaw))},{name='-x',x=-math.cos(math.rad(yaw)),y=-math.sin(math.rad(yaw))},
                    {name='+y',x=-math.sin(math.rad(yaw)),y=math.cos(math.rad(yaw))},{name='-y',x=math.sin(math.rad(yaw)),y=-math.cos(math.rad(yaw))}}
                for _,d in ipairs(dirs) do
                    local extent=0;for _,pt in ipairs(item.poly) do extent=math.max(extent,(pt.x-center.x)*d.x+(pt.y-center.y)*d.y) end
                    local dir={name=d.name,levels={}}
                    for _,f in ipairs({0.25,0.5,0.75}) do local z=bb.min.z+f*(bb.max.z-bb.min.z)
                        local hit=self.app.game:raycast({x=center.x,y=center.y,z=z},{x=center.x+d.x*(extent+max_distance),y=center.y+d.y*(extent+max_distance),z=z},{'Static'})
                        dir.levels[#dir.levels+1]={fraction=f,hit=hit~=nil,gap_m=hit and math.sqrt((hit.position.x-center.x)^2+(hit.position.y-center.y)^2)-extent or nil}
                    end
                    row.hits[#row.hits+1]=dir
                end
            end
            results[#results+1]=row
        end
    end
    return {validator='fitcheck',live=true,mode=mode,tested=#results,results=results,skipped=skipped,
        method=mode=='wall' and 'Static horizontal rays from center at 25/50/75 percent bounds height' or 'Static support rays at oriented footprint corners and center',
        warning=mode=='wall' and 'Bounds proxy; static walls only.' or 'Static-only support avoids self-hits. Dynamic support props are not included.'}
end
return PropValidators
