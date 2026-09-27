local Util=require('modules/util')

-- Reference-area capture. A box in the vanilla world is captured into a
-- read-only reference layer: locked, never exported, and refused by every
-- layer operation that would unlock, export, delete or receive objects. Its
-- objects are vanilla clones (see vanilla_clone.lua) that keep the real
-- resource, appearance and transform, so an author rebuilding or modifying
-- the location can always show exactly what originally occupied that space.
-- Nodes that cannot be cloned (lights, collision, occluders, foliage...) are
-- recorded on the area as markers with their position and type.
local ReferenceAreas={};ReferenceAreas.__index=ReferenceAreas

local MAX_EXTENT=250
local REF_COLOR='#9A8FD1'

local function num(v,f) v=tonumber(v);if v==nil or v~=v then return f end;return v end
local function v3(p) if type(p)~='table' then return nil end;local x,y,z=num(p.x or p[1]),num(p.y or p[2]),num(p.z or p[3]);if not x or not y or not z then return nil end;return {x=x,y=y,z=z} end
local function inside(b,p,tol) tol=tol or 0;return p and p.x>=b.min.x-tol and p.x<=b.max.x+tol and p.y>=b.min.y-tol and p.y<=b.max.y+tol and p.z>=b.min.z-tol and p.z<=b.max.z+tol end
local function dist(a,b) local dx,dy,dz=a.x-b.x,a.y-b.y,a.z-b.z;return math.sqrt(dx*dx+dy*dy+dz*dz) end
local function angle_delta(a,b) return math.abs(((num(a,0)-num(b,0)+180)%360)-180) end
local function slug(s) return (tostring(s):lower():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')) end

function ReferenceAreas.new(app) return setmetatable({app=app,box={},last_error=nil},ReferenceAreas) end

function ReferenceAreas:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

function ReferenceAreas:get(id) return self.app.model:get_reference_area(id) end

function ReferenceAreas:objects(area_id)
    local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do if o.metadata and o.metadata.reference_area_id==area_id then out[#out+1]=o end end
    return out
end

local function normalize_box(a,b,pad)
    pad=pad or {}
    local lo={x=math.min(a.x,b.x),y=math.min(a.y,b.y),z=math.min(a.z,b.z)}
    local hi={x=math.max(a.x,b.x),y=math.max(a.y,b.y),z=math.max(a.z,b.z)}
    local ph,pv=num(pad.horizontal,0),num(pad.below,0)
    lo.x=lo.x-ph;lo.y=lo.y-ph;hi.x=hi.x+ph;hi.y=hi.y+ph;lo.z=lo.z-pv;hi.z=hi.z+num(pad.above,0)
    return {min=lo,max=hi}
end

local function check_box(b)
    for _,k in ipairs({'x','y','z'}) do
        local e=b.max[k]-b.min[k]
        if e<=0.01 then return nil,'the box has no '..k..' extent; set two different corners or add padding' end
        if e>MAX_EXTENT then return nil,string.format('the box is %.0f m along %s; the limit is %d m (split the area)',e,k,MAX_EXTENT) end
    end
    return true
end

-- Box selection: corners from V, the crosshair or explicit points, or a room.
function ReferenceAreas:set_corner(which,args)
    args=args or {}
    if which~='a' and which~='b' then return nil,'corner must be a or b' end
    local p=v3(args.position)
    if not p then
        if args.source=='aim' then local hit,err=self.app.game:aim_point(num(args.distance,30));if not hit then return nil,err end;p=v3(hit.position)
        else local t,err=self.app.game:capture_transform();if not t then return nil,err end;p=v3(t.position) end
    end
    self.box[which]=p
    return self:box_status()
end

function ReferenceAreas:box_from_room(room_id,margin)
    local room=self.app.model:get_room(room_id);if not room then return nil,'room not found' end
    margin=num(margin,0.5)
    local c=room.transform.position;local yaw=math.rad(num(room.transform.rotation.yaw,0))
    local hx,hy=room.size.width/2+margin,room.size.depth/2+margin
    local ex=math.abs(hx*math.cos(yaw))+math.abs(hy*math.sin(yaw));local ey=math.abs(hx*math.sin(yaw))+math.abs(hy*math.cos(yaw))
    self.box={a={x=c.x-ex,y=c.y-ey,z=c.z-margin},b={x=c.x+ex,y=c.y+ey,z=c.z+room.size.height+margin}}
    return self:box_status()
end

function ReferenceAreas:box_status()
    local out={a=self.box.a,b=self.box.b,ready=self.box.a~=nil and self.box.b~=nil}
    if out.ready then out.bounds=normalize_box(self.box.a,self.box.b);out.size={x=out.bounds.max.x-out.bounds.min.x,y=out.bounds.max.y-out.bounds.min.y,z=out.bounds.max.z-out.bounds.min.z} end
    return out
end

function ReferenceAreas:_bounds(args)
    local lo,hi=v3(args.min),v3(args.max)
    if lo and hi then return normalize_box(lo,hi,args.padding) end
    if not (self.box.a and self.box.b) then return nil,'set both box corners (or a room) first, or pass min/max' end
    return normalize_box(self.box.a,self.box.b,args.padding)
end

function ReferenceAreas:list(args)
    args=args or {}
    local rows={}
    for _,a in ipairs(self.app.model.data.reference_areas or {}) do
        if not args.premise_id or args.premise_id=='' or a.premise_id==args.premise_id then
            local layer=self.app.layers and self.app.layers:get(a.layer_id)
            local live=0;for _,o in ipairs(self:objects(a.id)) do if self.app.placement:is_tracked(o) then live=live+1 end end
            rows[#rows+1]={id=a.id,name=a.name,premise_id=a.premise_id,layer_id=a.layer_id,bounds=a.bounds,source=a.source,captured_at=a.captured_at,
                items=a.item_count,approximate=a.approximate,unsupported=#a.unsupported,skipped=#a.skipped,shown=layer and layer.visible~=false or false,live=live}
        end
    end
    return {items=rows,count=#rows,box=self:box_status()}
end

function ReferenceAreas:describe(id)
    local a=self:get(id);if not a then return nil,'reference area not found' end
    local items={}
    for _,o in ipairs(self:objects(id)) do
        local src=o.metadata.vanilla_source or {}
        items[#items+1]={id=o.id,name=o.name,node_type=src.node_type,resource_path=src.resource_path,appearance=src.appearance,node_ref=src.node_ref,
            sector_path=src.sector_path,node_index=src.node_index,confidence=src.confidence,position=Util.deepcopy(o.transform.position),rotation=Util.deepcopy(o.transform.rotation)}
    end
    local out=Util.deepcopy(a);out.objects=items
    return out
end

-- Capture: live RedHotTools scan of the box, or explicit candidates (sector JSON).
function ReferenceAreas:capture(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local VC=self.app.vanilla_clone;if not VC then return nil,'vanilla clone importer is unavailable' end
    local bounds,err=self:_bounds(args);if not bounds then return nil,err end
    local ok;ok,err=check_box(bounds);if not ok then return nil,err end
    local raw,source,warning={},'scan',nil
    if type(args.candidates)=='table' then raw=args.candidates;source='sector_json'
    else
        local rht=self.app.rht_inspector;if not rht then return nil,'RedHotTools inspector adapter is unavailable' end
        local st=rht:status();if not st.ready then return nil,st.error or 'RedHotTools WorldInspector is unavailable; capture from an exported sector JSON instead' end
        local c={x=(bounds.min.x+bounds.max.x)/2,y=(bounds.min.y+bounds.max.y)/2,z=(bounds.min.z+bounds.max.z)/2}
        local scan,scan_err=rht:scan({center=c,radius=dist(c,bounds.max)+0.5,limit=num(args.limit,2000),entities=args.entities==true})
        if not scan then return nil,scan_err end
        raw=scan.targets or {};warning=scan.warning
    end
    -- Keep what lies in the box; dedupe by node/instance.
    local list,seen,sectors={}, {}, {}
    for _,r in ipairs(raw) do
        local c=VC:normalize(r,source)
        if c.position and inside(bounds,c.position,num(args.tolerance,0.05)) and not (c.key and seen[c.key]) then
            if c.key then seen[c.key]=true end
            list[#list+1]=c
            if c.sector_path then sectors[c.sector_path]=true end
        end
    end
    local values,from,skipped=VC:prepare(list,{allow_approximate=args.allow_approximate==true,allow_duplicate=true,layer='__reference'})
    local unsupported,rejected={},{}
    for _,s in ipairs(skipped) do
        local row={name=s.name,node_type=s.node_type,resource_path=s.resource_path,position=s.position,node_ref=s.node_ref,reason=s.reason}
        if s.supported==false then unsupported[#unsupported+1]=row else rejected[#rejected+1]=row end
    end
    if #values==0 and #unsupported==0 then
        return nil,#rejected>0 and ('nothing was captured: '..tostring(rejected[1].reason)) or 'no vanilla nodes were found inside the box; face the area so it streams, or capture from a sector JSON'
    end

    local model=self.app.model
    local name=Util.trim(args.name or '')~='' and Util.trim(args.name) or ('Reference '..(#(model.data.reference_areas or {})+1))
    for _,a in ipairs(model.data.reference_areas) do if string.lower(a.name)==string.lower(name) then return nil,'a reference area with this name already exists' end end
    model:snapshot('Capture reference area')
    local area=model.normalize_reference_area({name=name,premise_id=args.premise_id or self.app.selected_premise_id,bounds=bounds,source=source,notes=args.notes})
    local layer_id='reference_'..slug(name);local n=1
    while self.app.layers and self.app.layers:get(layer_id) do n=n+1;layer_id='reference_'..slug(name)..'_'..n end
    area.layer_id=layer_id
    table.insert(model.data.layers,{id=layer_id,name='Reference: '..name,color=REF_COLOR,visible=args.show==true,locked=true,export=false,
        description='Read-only vanilla reference captured by LocationStudio',reference=area.id})
    local approximate=0
    for _,v in ipairs(values) do
        v.layer=layer_id;v.locked=true;v.premise_id=nil;v.room_id=nil;v.name='[REF] '..v.name
        v.metadata.reference_area_id=area.id;v.metadata.source='LocationStudio reference area'
        if v.metadata.vanilla_source.confidence=='position_only' then approximate=approximate+1 end
    end
    local objects=model:add_objects(values,true)
    local list_sectors={};for k in pairs(sectors) do list_sectors[#list_sectors+1]=k end;table.sort(list_sectors)
    area.item_count=#objects;area.approximate=approximate;area.unsupported=unsupported;area.skipped=rejected;area.sectors=list_sectors
    table.insert(model.data.reference_areas,area)
    model:touch();self.app:mark_dirty()
    local result={area=Util.deepcopy(area),captured=#objects,unsupported=#unsupported,skipped=#rejected,approximate=approximate,layer_id=layer_id,warning=warning}
    if approximate>0 then result.note=approximate..' reference item(s) have position only (rotation 0, scale 1); recapture from the sector JSON for exact transforms' end
    if args.show==true then local shown=self:show(area.id,true);result.spawned=shown and shown.spawned or 0 end
    self.app.logger:info('reference_area','captured',{id=area.id,items=#objects,unsupported=#unsupported,source=source})
    return result
end

-- Show/hide the reference layer. This is runtime state, like layer visibility.
function ReferenceAreas:show(id,visible)
    local a=self:get(id);if not a then return nil,'reference area not found' end
    local layer=self.app.layers and self.app.layers:get(a.layer_id);if not layer then return nil,'reference layer is missing' end
    visible=visible~=false
    layer.visible=visible;if self.app.layers.state then self.app.layers.state.layer_hidden_live[a.layer_id]=nil end
    local result={area_id=id,visible=visible,spawned=0,despawned=0,failed={}}
    for _,o in ipairs(self:objects(id)) do
        local live=self.app.placement:is_tracked(o)
        if visible and not live then
            local sid,err=self.app.placement:spawn(o)
            if sid then result.spawned=result.spawned+1 else result.failed[#result.failed+1]={object_id=o.id,error=tostring(err)} end
        elseif not visible and live then
            local ok,err=self.app.placement:despawn(o)
            if ok then result.despawned=result.despawned+1 else result.failed[#result.failed+1]={object_id=o.id,error=tostring(err)} end
        end
    end
    self.app:mark_dirty()
    return result
end

local function resource_key(o)
    local wb=o.metadata and o.metadata.world_builder
    local path=wb and wb.resource_path or o.template
    return path and path~='' and string.lower(tostring(path)) or nil
end
local function appearance(o)
    local wb=o.metadata and o.metadata.world_builder
    return wb and wb.entry and wb.entry.data and wb.entry.data.app or o.appearance
end

-- Compare the authored location against the reference.
function ReferenceAreas:compare(id,args)
    args=args or {}
    local a=self:get(id);if not a then return nil,'reference area not found' end
    local move_radius=num(args.move_radius,5);local pos_tol=num(args.position_tolerance,0.05);local rot_tol=num(args.rotation_tolerance,1)
    local refs=self:objects(id)
    local by_key={}
    local candidates={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local md=o.metadata or {}
        if not md.reference_area_id and o.enabled~=false then
            local src=md.vanilla_source
            if src and src.key then by_key[src.key]=o end
            if inside(a.bounds,o.transform.position,move_radius) or (src and src.key) then candidates[#candidates+1]=o end
        end
    end
    local used,rows={}, {}
    local counts={unchanged=0,moved=0,changed=0,missing=0,added=0,not_captured=#a.unsupported}
    local function classify(ref,o,via)
        used[o.id]=true
        local rp,op=ref.transform.position,o.transform.position;local d=dist(rp,op)
        local rr,orr=ref.transform.rotation,o.transform.rotation
        local drot=math.max(angle_delta(rr.roll,orr.roll),angle_delta(rr.pitch,orr.pitch),angle_delta(rr.yaw,orr.yaw))
        local app_changed=appearance(ref)~=appearance(o) and appearance(o)~=nil
        local res_changed=resource_key(ref)~=resource_key(o)
        local status='unchanged'
        if res_changed or app_changed then status='changed' elseif d>pos_tol or drot>rot_tol then status='moved' end
        counts[status]=counts[status]+1
        rows[#rows+1]={status=status,reference_id=ref.id,object_id=o.id,name=o.name,matched_by=via,distance=math.floor(d*1000+0.5)/1000,
            rotation_delta=math.floor(drot*10+0.5)/10,appearance_changed=app_changed or nil,resource_changed=res_changed or nil}
    end
    local pending={}
    for _,ref in ipairs(refs) do
        local src=ref.metadata.vanilla_source or {}
        local o=src.key and by_key[src.key]
        if o and not used[o.id] then classify(ref,o,'vanilla_source') else pending[#pending+1]=ref end
    end
    for _,ref in ipairs(pending) do
        local key=resource_key(ref);local best,bd
        for _,o in ipairs(candidates) do
            if not used[o.id] and resource_key(o)==key then
                local d=dist(ref.transform.position,o.transform.position)
                if d<=move_radius and (not bd or d<bd) then best,bd=o,d end
            end
        end
        if best then classify(ref,best,'resource')
        else counts.missing=counts.missing+1;rows[#rows+1]={status='missing',reference_id=ref.id,name=ref.name,position=Util.deepcopy(ref.transform.position)} end
    end
    for _,o in ipairs(candidates) do
        if not used[o.id] and inside(a.bounds,o.transform.position,0) and (not a.premise_id or not o.premise_id or o.premise_id==a.premise_id) then
            counts.added=counts.added+1;rows[#rows+1]={status='added',object_id=o.id,name=o.name,position=Util.deepcopy(o.transform.position)}
        end
    end
    local order={changed=1,moved=2,missing=3,added=4,unchanged=5}
    table.sort(rows,function(x,y) if order[x.status]~=order[y.status] then return order[x.status]<order[y.status] end;return tostring(x.name)<tostring(y.name) end)
    return {area_id=id,counts=counts,items=rows,not_captured=Util.deepcopy(a.unsupported),references=#refs}
end

-- Editable copies of reference items, for reconstruction. One undo step.
function ReferenceAreas:copy_to_editable(id,args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local a=self:get(id);if not a then return nil,'reference area not found' end
    local refs={}
    if type(args.object_ids)=='table' and #args.object_ids>0 then
        for _,oid in ipairs(args.object_ids) do
            local o=self.app.model:get_object(oid)
            if not o or not o.metadata or o.metadata.reference_area_id~=id then return nil,'not an item of this reference area: '..tostring(oid) end
            refs[#refs+1]=o
        end
    else refs=self:objects(id) end
    if #refs==0 then return nil,'the reference area has no items' end
    if args.layer and self.app.layers then
        local l=self.app.layers:get(args.layer);if not l then return nil,'layer not found' end
        if l.locked then return nil,'layer '..l.name..' is locked' end
    end
    local values={}
    for _,ref in ipairs(refs) do
        local v=Util.deepcopy(ref);v.id=nil;v.runtime=nil;v.locked=false
        v.name=tostring(ref.name):gsub('^%[REF%]%s*','')
        v.metadata.reference_area_id=nil;v.metadata.source='LocationStudio vanilla clone (from reference area)'
        local def=self.app.world_builder and v.metadata.world_builder and self.app.world_builder:definition(v.metadata.world_builder.definition_key)
        v.layer=args.layer or (def and def.layer) or 'decoration'
        v.premise_id=args.premise_id or a.premise_id or self.app.selected_premise_id
        values[#values+1]=v
    end
    self.app.model:snapshot('Copy reference items')
    local objects=self.app.model:add_objects(values,true)
    local ids={};for _,o in ipairs(objects) do ids[#ids+1]=o.id end
    self.app.model:touch();self.app:mark_dirty()
    if self.app.selection then self.app.selection:set_object_group(ids,ids[1]) end
    local result={copied=#objects,object_ids=ids,spawned=0,spawn_errors={}}
    if args.spawn~=false then
        for _,o in ipairs(objects) do
            local ok,err=self.app.placement:spawn(o)
            if ok then result.spawned=result.spawned+1 else result.spawn_errors[#result.spawn_errors+1]={object_id=o.id,error=tostring(err)} end
        end
    end
    return result
end

-- Snap an editable object to a reference item's transform (and scale when both support it).
function ReferenceAreas:align(object_id,reference_id,args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local o=self.app.model:get_object(object_id);if not o then return nil,'object not found' end
    local ref=self.app.model:get_object(reference_id)
    if not ref or not ref.metadata or not ref.metadata.reference_area_id then return nil,'reference_id is not a reference-area item' end
    if o.metadata and o.metadata.reference_area_id then return nil,'reference items are read-only' end
    if o.locked then return nil,'object is locked' end
    self.app.model:snapshot('Align to reference')
    o.transform.position=Util.deepcopy(ref.transform.position)
    if args.rotation~=false then o.transform.rotation=Util.deepcopy(ref.transform.rotation) end
    local owb,rwb=o.metadata and o.metadata.world_builder,ref.metadata.world_builder
    local scaled=false
    if args.scale~=false and owb and owb.apply_scale and rwb and rwb.apply_scale then o.size=Util.deepcopy(ref.size);scaled=true end
    self.app.model:touch();self.app:mark_dirty()
    local result={object_id=o.id,reference_id=ref.id,transform=Util.deepcopy(o.transform),scaled=scaled}
    if self.app.placement:is_tracked(o) then local _,err=self.app.placement:refresh(o);if err then result.refresh_error=tostring(err) end end
    return result
end

function ReferenceAreas:delete(id)
    local busy=self:_busy();if busy then return nil,busy end
    local a,index=self:get(id);if not a then return nil,'reference area not found' end
    local failed={}
    for _,o in ipairs(self:objects(id)) do
        if self.app.placement:is_tracked(o) then local ok,err=self.app.placement:despawn(o);if not ok then failed[#failed+1]=tostring(err) end end
    end
    if #failed>0 then return nil,'could not despawn reference items; nothing was deleted: '..failed[1] end
    local model=self.app.model
    model:snapshot('Delete reference area')
    local removed=0
    for i=#model.data.objects,1,-1 do if model.data.objects[i].metadata and model.data.objects[i].metadata.reference_area_id==id then table.remove(model.data.objects,i);removed=removed+1 end end
    for i=#model.data.layers,1,-1 do if model.data.layers[i].reference==id then table.remove(model.data.layers,i) end end
    table.remove(model.data.reference_areas,index)
    model:touch();self.app:mark_dirty()
    return {deleted=id,removed_items=removed}
end

return ReferenceAreas
