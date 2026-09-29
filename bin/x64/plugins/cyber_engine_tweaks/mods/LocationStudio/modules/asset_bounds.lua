-- Local-space asset bounds and deterministic AABB helpers.
-- Bounds are authored in meters relative to the resource pivot. They are
-- metadata only: this module never invents geometry or changes WB resources.
local Util=require('modules/util')

local AssetBounds={}
AssetBounds.__index=AssetBounds
local FORMAT='locationstudio-asset-bounds/1'

local function finite(value)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return nil end
    return value
end

local function vec3(value,label)
    if type(value)~='table' then return nil,(label or 'vector')..' must be an object with x, y, z' end
    local x,y,z=finite(value.x),finite(value.y),finite(value.z)
    if not x or not y or not z then return nil,(label or 'vector')..' x, y, and z must be finite numbers' end
    return {x=x,y=y,z=z}
end

local function normalize_bounds(value,source)
    if type(value)~='table' then return nil,'bounds must be an object' end
    local min,err=vec3(value.min,'bounds.min');if not min then return nil,err end
    local max;max,err=vec3(value.max,'bounds.max');if not max then return nil,err end
    for _,axis in ipairs({'x','y','z'}) do
        if max[axis]<=min[axis] then return nil,'bounds.max.'..axis..' must be greater than bounds.min.'..axis end
    end
    local units=tostring(value.units or 'm')
    if units~='m' then return nil,"bounds units must be meters ('m'); convert imported values before storing" end
    local out={min=min,max=max,units='m',source=tostring(source or value.source or 'manual'),
        center={x=(min.x+max.x)/2,y=(min.y+max.y)/2,z=(min.z+max.z)/2},
        dimensions={x=max.x-min.x,y=max.y-min.y,z=max.z-min.z},
        extents={x=(max.x-min.x)/2,y=(max.y-min.y)/2,z=(max.z-min.z)/2}}
    if value.imported_at then out.imported_at=tostring(value.imported_at) end
    if value.resource then out.resource=tostring(value.resource) end
    return out
end

function AssetBounds.new(app) return setmetatable({app=app,last_import=nil},AssetBounds) end

function AssetBounds:info(asset_id)
    local asset,err=self.app.model:get_asset(asset_id)
    if not asset then return nil,err or ('asset not found: '..tostring(asset_id)) end
    local bounds=asset.metadata and asset.metadata.asset_bounds
    local dimensions=type(bounds)=='table' and bounds.min and bounds.max and {x=bounds.max.x-bounds.min.x,y=bounds.max.y-bounds.min.y,z=bounds.max.z-bounds.min.z} or nil
    return {asset_id=asset.id,name=asset.name,template=asset.template,has_bounds=type(bounds)=='table',bounds=Util.deepcopy(bounds),dimensions=dimensions,
        fallback_size=Util.deepcopy(asset.size),units='m',note=type(bounds)=='table' and 'Imported/authored resource-local AABB.' or 'No explicit bounds; size is only a fallback scale hint.'}
end

local function object_refers_to(object,asset_id)
    local metadata=object.metadata or {}
    if metadata.locationstudio_asset_id==asset_id or metadata.stamp_asset_id==asset_id then return true end
    return metadata.source=='asset:'..asset_id or metadata.source=='stamp:asset:'..asset_id
end

local function store_bounds(model,asset,bounds)
    local metadata=Util.deepcopy(asset.metadata or {})
    metadata.asset_bounds=Util.deepcopy(bounds)
    asset.metadata=metadata;asset.updated_at=Util.now_iso()
    local propagated=0
    for _,object in ipairs(model.data.objects or {}) do
        if object_refers_to(object,asset.id) then
            object.metadata=Util.deepcopy(object.metadata or {})
            object.metadata.asset_bounds=Util.deepcopy(bounds)
            object.updated_at=Util.now_iso();propagated=propagated+1
        end
    end
    return propagated
end

function AssetBounds:set(asset_id,value,source)
    local asset=self.app.model:get_asset(asset_id)
    if not asset then return nil,'asset not found: '..tostring(asset_id) end
    local bounds,err=normalize_bounds(value,source);if not bounds then return nil,err end
    self.app.model:snapshot('Set asset bounds')
    local propagated=store_bounds(self.app.model,asset,bounds)
    self.app.model:touch()
    self.app:mark_dirty()
    if self.app.logger then self.app.logger:info('asset_bounds','set',{asset_id=asset_id,source=bounds.source,propagated=propagated,extents=bounds.extents}) end
    local result=self:info(asset_id);result.propagated_objects=propagated;return result
end

local function resolve_asset(model,row)
    local id=row.asset_id or row.id
    if id then
        local asset=model:get_asset(tostring(id))
        if not asset then return nil,'asset not found: '..tostring(id) end
        return asset
    end
    local query=tostring(row.template or row.name or '')
    if query=='' then return nil,'each bounds entry needs asset_id, template, or name' end
    local exact={}
    for _,asset in ipairs(model.data.assets or {}) do
        if asset.template==query or asset.name==query then table.insert(exact,asset) end
    end
    if #exact==1 then return exact[1] end
    if #exact>1 then return nil,'asset reference is ambiguous: '..query end
    return nil,'no asset matches template/name: '..query
end

-- Import a versioned bounds manifest. The whole batch is validated before the
-- first write and becomes one undo operation.
function AssetBounds:import_manifest(args)
    args=args or {}
    local manifest=args.manifest or args
    if type(manifest)~='table' then return nil,'manifest must be a JSON object' end
    local entries=manifest.assets or manifest.entries
    if type(entries)~='table' or #entries==0 then return nil,'manifest.assets must contain at least one entry' end
    if manifest.format~=FORMAT then return nil,'unsupported bounds manifest format: '..tostring(manifest.format)..'; expected '..FORMAT end
    local planned,seen={},{}
    for index,row in ipairs(entries) do
        if type(row)~='table' then return nil,'assets['..index..'] must be an object' end
        local asset,err=resolve_asset(self.app.model,row);if not asset then return nil,'assets['..index..']: '..err end
        if seen[asset.id] then return nil,'duplicate asset in manifest: '..asset.id end
        seen[asset.id]=true
        local payload=row.bounds or row
        local bounds;bounds,err=normalize_bounds(payload,manifest.source or 'manifest:'..(manifest.name or 'import'))
        if not bounds then return nil,'assets['..index..']: '..err end
        bounds.resource=tostring(row.resource or asset.template or '')
        table.insert(planned,{asset=asset,bounds=bounds})
    end
    local summary={format=FORMAT,source=tostring(manifest.source or args.source or manifest.name or 'manifest'),count=#planned,assets={}}
    for _,item in ipairs(planned) do table.insert(summary.assets,{asset_id=item.asset.id,name=item.asset.name,bounds=item.bounds}) end
    if args.dry_run==true or manifest.dry_run==true then summary.dry_run=true;return summary end
    local model=self.app.model;local propagated=0
    model:snapshot('Import asset bounds')
    for _,item in ipairs(planned) do propagated=propagated+store_bounds(model,item.asset,item.bounds) end
    model:touch()
    self.app:mark_dirty();self.last_import=summary
    summary.propagated_objects=propagated
    if self.app.logger then self.app.logger:info('asset_bounds','imported',{count=#planned,source=summary.source,propagated=propagated}) end
    return summary
end

local function rotate_point(point,rotation)
    local r=rotation or {};local roll=math.rad(tonumber(r.roll) or 0);local pitch=math.rad(tonumber(r.pitch) or 0);local yaw=math.rad(tonumber(r.yaw) or 0)
    local cr,sr=math.cos(roll),math.sin(roll);local cp,sp=math.cos(pitch),math.sin(pitch);local cy,sy=math.cos(yaw),math.sin(yaw)
    -- Apply roll (X), pitch (Y), then yaw (Z), matching LS transform fields.
    local x1=point.x;local y1=point.y*cr-point.z*sr;local z1=point.y*sr+point.z*cr
    local x2=x1*cp+z1*sp;local y2=y1;local z2=-x1*sp+z1*cp
    return {x=x2*cy-y2*sy,y=x2*sy+y2*cy,z=z2}
end

function AssetBounds:world_aabb(object_id)
    local object,err=self.app.model:get_object(object_id)
    if not object then return nil,err or ('object not found: '..tostring(object_id)) end
    -- Generated resources: bounds computed from their geometry (modules/bounds_gen.lua), in their own rotation convention.
    local generated=self.app.bounds_gen and self.app.bounds_gen:world_aabb(object)
    if generated then return {object_id=object.id,name=object.name,units='m',aabb={min=generated.min,max=generated.max},source='generated'} end
    local bounds=object.metadata and object.metadata.asset_bounds
    if type(bounds)~='table' then return nil,'object has no imported asset_bounds metadata: '..object.id end
    local normalized;normalized,err=normalize_bounds(bounds,bounds.source);if not normalized then return nil,err end
    local min,max=normalized.min,normalized.max
    local wb=object.metadata and object.metadata.world_builder
    -- `size` is only a planning hint for direct CET .ent entities. WB resources
    -- carry an explicit scale contract in their metadata; only those bounds are
    -- scaled here, avoiding false collisions for unscalable CET entities.
    local scale=type(wb)=='table' and wb.apply_scale==true and object.size or {x=1,y=1,z=1}
    local p=object.transform.position;local rotation=object.transform.rotation
    local out={min={x=math.huge,y=math.huge,z=math.huge},max={x=-math.huge,y=-math.huge,z=-math.huge}}
    for _,x in ipairs({min.x,max.x}) do for _,y in ipairs({min.y,max.y}) do for _,z in ipairs({min.z,max.z}) do
        local corner=rotate_point({x=x*(tonumber(scale.x) or 1),y=y*(tonumber(scale.y) or 1),z=z*(tonumber(scale.z) or 1)},rotation)
        for _,axis in ipairs({'x','y','z'}) do local value=corner[axis]+(tonumber(p[axis]) or 0);out.min[axis]=math.min(out.min[axis],value);out.max[axis]=math.max(out.max[axis],value) end
    end end end
    return {object_id=object.id,name=object.name,units='m',aabb=out,source=bounds.source}
end

function AssetBounds:overlap(object_ids,margin)
    if type(object_ids)~='table' or #object_ids<2 then return nil,'object_ids must contain at least two IDs' end
    margin=finite(margin or 0) or 0;if margin<0 then return nil,'margin must be >= 0' end
    local bounds={}
    for _,id in ipairs(object_ids) do local result,err=self:world_aabb(id);if not result then return nil,err end;table.insert(bounds,result) end
    local overlaps={}
    for i=1,#bounds-1 do for j=i+1,#bounds do
        local a,b=bounds[i].aabb,bounds[j].aabb;local hit=true
        for _,axis in ipairs({'x','y','z'}) do if a.max[axis]+margin<=b.min[axis] or b.max[axis]+margin<=a.min[axis] then hit=false;break end end
        if hit then table.insert(overlaps,{a=bounds[i].object_id,b=bounds[j].object_id,a_name=bounds[i].name,b_name=bounds[j].name}) end
    end end
    return {units='m',tested=#bounds,overlap_count=#overlaps,overlaps=overlaps,margin=margin}
end

-- Broadphase project collision/clearance audit. These are conservative world
-- AABBs from authored/imported bounds, not REDengine physics or mesh tests.
function AssetBounds:collisions(args)
    args=args or {};local model=self.app.model;local ids={};local seen={}
    if type(args.object_ids)=='table' and #args.object_ids>0 then
        for _,id in ipairs(args.object_ids) do
            if not seen[id] then if not model:get_object(id) then return nil,'object not found: '..tostring(id) end;seen[id]=true;table.insert(ids,id) end
        end
    else
        for _,object in ipairs(model.data.objects or {}) do
            if (not args.premise_id or object.premise_id==args.premise_id) and object.enabled~=false and object.visible~=false then table.insert(ids,object.id) end
        end
    end
    if #ids<2 then return nil,'collision scan needs at least two visible placed objects in scope' end
    if #ids>300 then return nil,'collision scan is limited to 300 placed objects per request' end
    local margin=finite(args.margin or 0);if not margin or margin<0 or margin>100 then return nil,'margin must be between 0 and 100 meters' end
    local tested,skipped={},{}
    for _,id in ipairs(ids) do
        local object=model:get_object(id)
        if args.premise_id and object.premise_id~=args.premise_id then return nil,'object is outside the requested premise: '..tostring(id) end
        local box,err=self:world_aabb(id)
        if box then table.insert(tested,box)
        else table.insert(skipped,{object_id=id,name=object.name,reason=tostring(err)}) end
    end
    local pairs={};local collision_total=0;local truncated=false
    for i=1,#tested-1 do for j=i+1,#tested do
        local a,b=tested[i],tested[j];local overlap={x=0,y=0,z=0};local hit=true
        for _,axis in ipairs({'x','y','z'}) do
            overlap[axis]=math.min(a.aabb.max[axis]+margin,b.aabb.max[axis]+margin)-math.max(a.aabb.min[axis]-margin,b.aabb.min[axis]-margin)
            if overlap[axis]<=0 then hit=false;break end
        end
        if hit then
            collision_total=collision_total+1
            if #pairs<2000 then table.insert(pairs,{a=a.object_id,b=b.object_id,a_name=a.name,b_name=b.name,intersection_m=overlap,approximate=true}) else truncated=true end
        end
    end end
    return {units='m',scope=args.premise_id and 'premise' or (args.object_ids and 'selection' or 'project'),premise_id=args.premise_id,
        selected=#ids,tested=#tested,skipped=skipped,skipped_count=#skipped,collision_count=collision_total,collisions_returned=#pairs,collisions=pairs,
        collisions_truncated=truncated,margin=margin,method='rotated local bounds transformed to world AABBs; broadphase only',
        warning='AABB intersections can be false positives for rotated or non-box meshes. This does not query or change REDengine collision.'}
end

function AssetBounds:fit(asset_id,target_size,mode)
    local asset,err=self.app.model:get_asset(asset_id)
    if not asset then return nil,err or ('asset not found: '..tostring(asset_id)) end
    local bounds=asset.metadata and asset.metadata.asset_bounds
    if type(bounds)~='table' then return nil,'asset has no imported asset_bounds metadata: '..asset.id end
    local target;target,err=vec3(target_size,'target_size');if not target then return nil,err end
    for _,axis in ipairs({'x','y','z'}) do if target[axis]<=0 then return nil,'target_size.'..axis..' must be greater than zero' end end
    local size={x=bounds.max.x-bounds.min.x,y=bounds.max.y-bounds.min.y,z=bounds.max.z-bounds.min.z}
    local current=asset.size or {x=1,y=1,z=1}
    local dims={x=size.x*(tonumber(current.x) or 1),y=size.y*(tonumber(current.y) or 1),z=size.z*(tonumber(current.z) or 1)}
    local factors={x=target.x/dims.x,y=target.y/dims.y,z=target.z/dims.z}
    if mode=='contain' then local uniform=math.min(factors.x,factors.y,factors.z);factors={x=uniform,y=uniform,z=uniform}
    elseif mode~='stretch' and mode~='fit' and mode~=nil then return nil,"mode must be 'stretch' or 'contain'" end
    local wb=asset.metadata and asset.metadata.world_builder
    local scale_supported=type(wb)=='table' and wb.apply_scale==true
    return {asset_id=asset.id,mode=mode or 'stretch',units='m',current_dimensions=dims,target_size=target,
        scale_multiplier=factors,scale_supported_by_backend=scale_supported,
        warning=not scale_supported and 'This asset has no verified World Builder scale contract; values are planning suggestions only.' or nil,
        suggested_asset_size={x=(tonumber(current.x) or 1)*factors.x,y=(tonumber(current.y) or 1)*factors.y,z=(tonumber(current.z) or 1)*factors.z}}
end

AssetBounds.FORMAT=FORMAT
AssetBounds.normalize=normalize_bounds
return AssetBounds
