-- Asset-backed repeat/path generators. These create ordinary editable project
-- objects using imported World Builder assets; they do not synthesize meshes.
local Util=require('modules/util')
local Generators={}
Generators.__index=Generators

local function finite(n) return type(n)=='number' and n==n and n~=math.huge and n~=-math.huge end
local function point(v)
    return type(v)=='table' and finite(tonumber(v.x)) and finite(tonumber(v.y)) and finite(tonumber(v.z))
end
local function yaw(dx,dy)
    if math.atan2 then return math.deg(math.atan2(dy,dx)) end
    if dx>0 then return math.deg(math.atan(dy/dx)) end
    if dx<0 and dy>=0 then return math.deg(math.atan(dy/dx))+180 end
    if dx<0 then return math.deg(math.atan(dy/dx))-180 end
    return dy>=0 and 90 or -90
end
local function distance(a,b) local x,y,z=b.x-a.x,b.y-a.y,b.z-a.z;return math.sqrt(x*x+y*y+z*z) end

function Generators.new(app) return setmetatable({app=app},Generators) end

function Generators:_asset(asset_id)
    local asset=self.app.model:get_asset(asset_id)
    if not asset then return nil,'asset not found: '..tostring(asset_id) end
    local wb=asset.metadata and asset.metadata.world_builder
    if type(wb)~='table' or type(wb.entry)~='table' then return nil,'generator requires an imported World Builder asset with entry metadata: '..tostring(asset_id) end
    if wb.definition_key~='mesh_static' then return nil,'generator asset must be a Static Mesh (mesh_static): '..tostring(asset_id) end
    local resource=Util.trim(wb.resource_path or asset.template or '')
    if resource=='' then return nil,'imported Static Mesh has no resource path: '..tostring(asset_id) end
    return asset
end

function Generators:_premise(id)
    local premise=self.app.model:get_premise(id)
    if not premise then return nil,'premise_id must reference an existing premise' end
    return premise
end

function Generators:_append(asset,premise,name,position,rotation,scale,layer,extra)
    rotation=type(rotation)=='table' and rotation or {yaw=tonumber(rotation) or 0,pitch=0}
    local metadata=Util.deepcopy(asset.metadata or {})
    metadata.locationstudio_asset_id=asset.id
    metadata.generator=Util.deepcopy(extra or {})
    local wb=metadata.world_builder
    wb.resource_path=wb.resource_path or asset.template
    wb.entry=wb.entry or {};wb.entry.name=wb.resource_path
    wb.entry.data=wb.entry.data or {};wb.entry.data.spawnData=wb.resource_path
    wb.apply_scale=true
    return {premise_id=premise.id,name=name,kind='mesh',template=asset.template,
        layer=layer or asset.layer or 'decoration',size=scale or asset.size,
        transform={position={x=position.x,y=position.y,z=position.z,w=1},rotation={roll=0,pitch=rotation.pitch or 0,yaw=rotation.yaw or 0}},
        metadata=metadata}
end

function Generators:_finish(kind,objects,spawn)
    objects=self.app.model:add_objects(objects)
    local spawned,failed={},{}
    if spawn then
        for _,object in ipairs(objects) do
            local handle,err=self.app.placement:spawn(object)
            if not handle then table.insert(failed,{id=object.id,error=tostring(err)}) else table.insert(spawned,object.id) end
        end
    end
    self.app:mark_dirty()
    if self.app.logger then self.app.logger:info('world_builder_generators','generated',{generator=kind,objects=#objects,spawned=#spawned,failed=#failed}) end
    return {generator=kind,count=#objects,object_ids=(function() local r={} for _,o in ipairs(objects) do r[#r+1]=o.id end return r end)(),spawned_ids=spawned,failed=failed,spawned=spawn==true}
end

function Generators:_preflight(spawn)
    if not spawn then return true end
    local status=self.app.runtime_shell and self.app.runtime_shell:status(true)
    if not status or not status.available then return nil,'World Builder runtime is not ready: '..tostring(status and status.reason or 'runtime unavailable') end
    return true
end

function Generators:_path(kind,args,options)
    args=args or {};options=options or {}
    local premise,err=self:_premise(args.premise_id);if not premise then return nil,err end
    local asset;asset,err=self:_asset(args.asset_id);if not asset then return nil,err end
    local ready;ready,err=self:_preflight(args.spawn~=false);if not ready then return nil,err end
    local points=args.points
    if type(points)~='table' or #points<2 or #points>128 then return nil,'points must contain 2–128 finite world-space XYZ positions' end
    for i,p in ipairs(points) do if not point(p) then return nil,'invalid XYZ point at index '..i end end
    local bounds=asset.metadata and asset.metadata.asset_bounds
    local dimensions=bounds and bounds.min and bounds.max and {x=bounds.max.x-bounds.min.x,y=bounds.max.y-bounds.min.y,z=bounds.max.z-bounds.min.z}
    if not dimensions or dimensions.x<=0 or dimensions.y<=0 or dimensions.z<=0 then return nil,'generator needs imported resource bounds; use wb_bounds_set before generating' end
    local repeat_distance=tonumber(args.segment_length) or tonumber(args.spacing) or dimensions.x
    if not finite(repeat_distance) or repeat_distance<0.1 or repeat_distance>100 then return nil,'segment_length must be between 0.1 and 100 meters' end
    local target_width=tonumber(args.width) or dimensions.y
    if not finite(target_width) or target_width<0.05 or target_width>100 then return nil,'width must be between 0.05 and 100 meters' end
    local base=asset.size or {x=1,y=1,z=1};local objects={};local total=0
    for pi=1,#points-1 do
        local a,b=points[pi],points[pi+1];local len=distance(a,b)
        if len>0.001 then
            total=total+len;if total>2000 then return nil,'path length exceeds 2000 meters' end
            local count=math.max(1,math.ceil(len/repeat_distance));if #objects+count>256 then return nil,'generator is limited to 256 placed segments' end
            for si=1,count do
                local along=math.min((si-0.5)*len/count,len);local f=along/len
                local pos={x=a.x+(b.x-a.x)*f,y=a.y+(b.y-a.y)*f,z=a.z+(b.z-a.z)*f}
                local segment=len/count
                local size={x=math.max(0.001,segment/dimensions.x),
                    y=math.max(0.001,target_width/dimensions.y),
                    z=math.max(0.001,tonumber(args.height) and tonumber(args.height)/dimensions.z or tonumber(base.z) or 1)}
                local horizontal=math.sqrt((b.x-a.x)^2+(b.y-a.y)^2)
                local rotation={yaw=yaw(b.x-a.x,b.y-a.y),pitch=-math.deg(math.atan2 and math.atan2(b.z-a.z,horizontal) or math.atan((b.z-a.z)/(horizontal>0.0001 and horizontal or 0.0001)))}
                local object=self:_append(asset,premise,string.format('%s %03d',args.name or kind:upper(),#objects+1),pos,rotation,size,
                    options.layer or args.layer,{generator=kind,source_asset_id=asset.id,segment_index=#objects+1,segment_count=count,segment_length=segment})
                objects[#objects+1]=object
            end
        end
    end
    if #objects==0 then return nil,'path has no non-zero length segments' end
    local result;result,err=self:_finish(kind,objects,args.spawn~=false);if not result then return nil,err end
    result.path_length=total;return result
end

function Generators:cable(args) return self:_path('cable',args,{layer='decoration'}) end
function Generators:fence(args)
    args=args or {};local post_asset
    if args.post_asset_id and args.post_asset_id~='' then local post_err;post_asset,post_err=self:_asset(args.post_asset_id);if not post_asset then return nil,post_err end end
    local result,err=self:_path('fence',args,{layer='shell'});if not result then return nil,err end
    -- Optional fence posts are real imported assets, placed at each path vertex.
    if post_asset then
        local premise=self:_premise(args.premise_id)
        local posts={};for i,p in ipairs(args.points or {}) do posts[#posts+1]=self:_append(post_asset,premise,(args.name or 'Fence')..' Post '..i,p,0,nil,'shell',{generator='fence',source_asset_id=post_asset.id,post=true}) end
        local finished;finished,err=self:_finish('fence_posts',posts,args.spawn~=false);if not finished then return nil,err end
        for _,id in ipairs(finished.object_ids) do result.object_ids[#result.object_ids+1]=id end
        for _,id in ipairs(finished.spawned_ids) do result.spawned_ids[#result.spawned_ids+1]=id end
        for _,failure in ipairs(finished.failed) do result.failed[#result.failed+1]=failure end
        result.count=#result.object_ids
    end
    return result
end
function Generators:road(args) return self:_path('road',args,{road=true,layer='shell'}) end

function Generators:market(args)
    args=args or {};local premise,err=self:_premise(args.premise_id);if not premise then return nil,err end
    local ids=args.asset_ids;if type(ids)~='table' or #ids==0 or #ids>32 then return nil,'asset_ids must contain 1–32 imported World Builder Static Mesh assets' end
    local assets={};for _,id in ipairs(ids) do local a;a,err=self:_asset(id);if not a then return nil,err end;assets[#assets+1]=a end
    local ready;ready,err=self:_preflight(args.spawn~=false);if not ready then return nil,err end
    local origin=args.origin;if not point(origin) then return nil,'origin must be a finite world-space XYZ point' end
    local rows=math.floor(tonumber(args.rows) or 2);local columns=math.floor(tonumber(args.columns) or #assets)
    local sx=tonumber(args.spacing_x) or 2.5;local sy=tonumber(args.spacing_y) or 3.0
    if rows<1 or rows>16 or columns<1 or columns>16 or rows*columns>128 then return nil,'market grid must be 1–16 rows/columns and at most 128 placements' end
    if not finite(sx) or not finite(sy) or sx<0.5 or sy<0.5 or sx>30 or sy>30 then return nil,'market spacing must be between 0.5 and 30 meters' end
    local rotation=tonumber(args.yaw) or 0;local rad=math.rad(rotation);local objects={}
    for row=1,rows do for col=1,columns do
        local a=assets[((row-1)*columns+(col-1))%#assets+1]
        local lx=(col-(columns+1)/2)*sx;local ly=(row-1)*sy
        local pos={x=origin.x+lx*math.cos(rad)-ly*math.sin(rad),y=origin.y+lx*math.sin(rad)+ly*math.cos(rad),z=origin.z}
        objects[#objects+1]=self:_append(a,premise,string.format('%s %02d-%02d',args.name or 'Market Stall',row,col),pos,rotation,nil,'decoration',{generator='market',source_asset_id=a.id,row=row,column=col})
    end end
    return self:_finish('market',objects,args.spawn~=false)
end

function Generators:noderef(args)
    args=args or {};local label=Util.trim(args.node_ref)
    if label=='' or #label>160 then return nil,'node_ref must be a non-empty string up to 160 characters' end
    local origin=args.position
    if not point(origin) then local transform,err=self.app.game:capture_transform();if not transform then return nil,err end;origin=transform.position end
    -- A NodeRef is authoring metadata, not a live CET-spawnable entity. The native
    -- World Builder/REDengine node is only created during the supported export/build pipeline.
    for _,loc in ipairs(self.app.model.data.locations or {}) do if loc.metadata and loc.metadata.world_builder_node_ref==label then return nil,'NodeRef already exists: '..label end end
    local location=self.app.model:add_location({name=args.name or label,type='noderef',category='World Builder',
        transform={position={x=origin.x,y=origin.y,z=origin.z,w=1},rotation={roll=0,pitch=0,yaw=tonumber(args.yaw) or 0}},
        metadata={source='wb_generate_noderef',world_builder_node_ref=label,node_ref_status='authoring_only'}})
    self.app:mark_dirty();self.app.selection:set('location',location.id)
    return {generator='noderef',id=location.id,node_ref=label,status='authoring_only',message='Saved NodeRef marker only; native REDengine node creation requires a compatible World Builder build template and export/import pipeline.'}
end

return Generators
