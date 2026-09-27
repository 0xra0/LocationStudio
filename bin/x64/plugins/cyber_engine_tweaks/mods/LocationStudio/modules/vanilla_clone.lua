local Util=require('modules/util')

-- Vanilla-world clone/import. Picks native streamed nodes (RedHotTools crosshair
-- or area scan) or nodes read offline from a WolvenKit-exported
-- .streamingsector JSON, and imports them as ordinary editable project objects
-- that keep the node's real resource path, appearance and transform. The
-- original nodes can be hidden through the existing reversible vanilla-removal
-- records so the clone replaces them in place.
--
-- Transform honesty: RedHotTools reports a streamed node's position but not
-- its orientation or scale. Such picks are `position_only` and import only
-- with allow_approximate (rotation 0, scale 1). Entity picks read the live
-- entity orientation, and sector-JSON nodes carry the exact nodeData
-- transform; both are `exact`.
local VanillaClone={};VanillaClone.__index=VanillaClone

-- Native node type -> World Builder definition, resource field, appearance field.
local NODE_TYPES={
    worldMeshNode={key='mesh_static',field='mesh_path',app='mesh_appearance'},
    worldBendedMeshNode={key='mesh_static',field='mesh_path',app='mesh_appearance',warning='bent mesh: the deformation is not preserved; the clone is a straight static mesh'},
    worldPhysicalDestructionNode={key='mesh_static',field='mesh_path',app='mesh_appearance',warning='destructible mesh: destruction physics are not preserved'},
    worldInstancedMeshNode={key='mesh_static',field='mesh_path',app='mesh_appearance',warning='one instance of an instanced mesh node; the other instances are separate picks'},
    worldStaticDecalNode={key='decal',field='material_path'},
    worldEffectNode={key='effect',field='effect_path'},
    worldStaticParticleNode={key='particle',field='particle_path'},
    worldEntityNode={key='entity_template',field='template_path',app='appearance'},
    worldDeviceNode={key='entity_template',field='template_path',app='appearance',warning='device: logic, persistent state and connections are not cloned; rewire it with the device tools'},
    worldPopulationSpawnerNode={key='entity_record',field='record_id',app='appearance',warning='population spawner: community and spawn conditions are not cloned'},
}
local UNSUPPORTED={
    worldFoliageNode='foliage populations have no per-instance resource to clone',
    worldTerrainMeshNode='terrain is not cloneable',
    worldCollisionNode='collision actors have no public resource; author collision with the collision tools',
    worldStaticLightNode='light parameters are not exposed by RedHotTools; recreate the light with the lighting tools',
    worldStaticOccluderMeshNode='occluders are authored with the visibility tools',
    worldInstancedOccluderNode='occluders are authored with the visibility tools',
}
local MESH_KEYS={mesh_static=true}

local function pick(t,...)
    for _,name in ipairs({...}) do local v=t[name];if v~=nil and v~='' then return v end end
    return nil
end
local function num(v,f) v=tonumber(v);if v==nil or v~=v then return f end;return v end
local function vec3(v) if type(v)~='table' then return nil end;local x,y,z=num(v.x or v.X),num(v.y or v.Y),num(v.z or v.Z);if not x or not y or not z then return nil end;return {x=x,y=y,z=z} end
local function rot(v) if type(v)~='table' then return nil end;local r,p,y=num(v.roll),num(v.pitch),num(v.yaw);if not r or not p or not y then return nil end;return {roll=r,pitch=p,yaw=y} end

function VanillaClone.new(app) return setmetatable({app=app,staged={},last_error=nil},VanillaClone) end

function VanillaClone:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

function VanillaClone:_rht()
    local rht=self.app.rht_inspector;if not rht then return nil,'RedHotTools inspector adapter is unavailable' end
    local status=rht:status();if not status.ready then return nil,status.error or 'RedHotTools WorldInspector is unavailable; install RedHotTools to pick vanilla nodes, or import from an exported sector JSON' end
    return rht
end

-- Existing clones by source key, so a node is not imported twice by accident.
function VanillaClone:_clone_index()
    local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local src=o.metadata and o.metadata.vanilla_source
        if src and src.key then out[src.key]=o.id end
    end
    return out
end

-- Normalize RedHotTools (camelCase), offline sector (snake_case) or MCP data.
function VanillaClone:normalize(raw,source)
    raw=raw or {}
    local c={
        node_id=pick(raw,'node_id','nodeID'),node_ref=pick(raw,'node_ref','nodeRef'),node_type=pick(raw,'node_type','nodeType'),
        sector_path=pick(raw,'sector_path','sectorPath'),node_index=num(pick(raw,'node_index','nodeIndex')),instance_index=num(pick(raw,'instance_index','instanceIndex')),
        debug_name=pick(raw,'debug_name','debugName'),mesh_path=pick(raw,'mesh_path','meshPath'),mesh_appearance=pick(raw,'mesh_appearance','meshAppearance'),
        material_path=pick(raw,'material_path','materialPath'),effect_path=pick(raw,'effect_path','effectPath'),particle_path=pick(raw,'particle_path','particlePath'),
        template_path=pick(raw,'template_path','templatePath'),record_id=pick(raw,'record_id','recordID'),appearance=pick(raw,'appearance','appearanceName'),
        entity_id=pick(raw,'entity_id','entityID'),entity_type=pick(raw,'entity_type','entityType'),is_entity=pick(raw,'is_entity','isEntity')==true,
        position=vec3(raw.position),rotation=rot(raw.rotation),scale=vec3(raw.scale),quaternion=raw.quaternion,
        distance=num(raw.distance or raw.centerDistance),source=raw.source_kind or source or 'crosshair',warnings={},supported=false,
    }
    if c.node_id then c.node_id=tostring(c.node_id) end
    if c.entity_id then c.entity_id=tostring(c.entity_id) end
    local def=c.node_type and NODE_TYPES[c.node_type]
    if not def and not c.node_type and c.is_entity then
        if c.template_path then def={key='entity_template',field='template_path',app='appearance',warning='dynamic entity (not a sector node): the clone is a static copy'}
        elseif c.record_id then def={key='entity_record',field='record_id',app='appearance',warning='dynamic entity (not a sector node): the clone is a static copy'} end
    end
    if not def then
        c.reason=c.node_type and (UNSUPPORTED[c.node_type] or ('node type '..c.node_type..' is not cloneable yet')) or 'the pick has no node type or entity resource'
    else
        c.definition_key=def.key;c.resource_path=c[def.field];c.appearance_name=def.app and c[def.app] or nil
        if def.warning then c.warnings[#c.warnings+1]=def.warning end
        if not c.resource_path then c.reason='no resource path was resolved for this '..tostring(c.node_type or 'entity')
        elseif not c.position then c.reason='the pick has no position'
        else c.supported=true end
    end
    c.confidence=c.rotation and 'exact' or 'position_only'
    c.scale_assumed=c.rotation~=nil and c.scale==nil and MESH_KEYS[c.definition_key or '']==true or nil
    if c.node_id then c.key='node:'..c.node_id..':'..tostring(c.instance_index or 0)
    elseif c.sector_path and c.node_index then c.key='sector:'..c.sector_path..':'..c.node_index..':'..tostring(c.instance_index or 0)
    elseif c.entity_id then c.key='entity:'..c.entity_id end
    c.name=c.debug_name and tostring(c.debug_name):gsub('^%[.-%]%s*','') or nil
    if not c.name or c.name=='' then c.name=c.resource_path and tostring(c.resource_path):gsub('\\','/'):match('([^/]+)$') or 'Vanilla node' end
    c.name=tostring(c.name):gsub('%.[%w]+$','')
    return c
end

function VanillaClone:_stage(list,append,source)
    if not append then self.staged={} end
    local cloned=self:_clone_index();local seen={}
    for _,c in ipairs(self.staged) do if c.key then seen[c.key]=true end end
    local added=0
    for _,raw in ipairs(list or {}) do
        local c=self:normalize(raw,source)
        if not (c.key and seen[c.key]) then
            if c.key then seen[c.key]=true end
            c.already_cloned=c.key and cloned[c.key] or nil
            c.selected=c.supported and not c.already_cloned
            self.staged[#self.staged+1]=c;added=added+1
        end
    end
    return self:candidates({added=added})
end

function VanillaClone:candidates(extra)
    local rows={};local supported=0;local selected=0
    for i,c in ipairs(self.staged) do
        rows[#rows+1]={index=i,name=c.name,node_type=c.node_type,definition_key=c.definition_key,resource_path=c.resource_path,appearance=c.appearance_name,
            node_id=c.node_id,node_ref=c.node_ref,sector_path=c.sector_path,node_index=c.node_index,instance_index=c.instance_index,position=c.position,rotation=c.rotation,
            confidence=c.confidence,supported=c.supported,reason=c.reason,warnings=c.warnings,already_cloned=c.already_cloned,selected=c.selected,distance=c.distance,source=c.source}
        if c.supported then supported=supported+1 end;if c.selected then selected=selected+1 end
    end
    local out={items=rows,count=#rows,supported=supported,selected=selected}
    for k,v in pairs(extra or {}) do out[k]=v end
    return out
end

function VanillaClone:pick_crosshair(args)
    args=args or {}
    local rht,err=self:_rht();if not rht then return nil,err end
    local result,cross_err=rht:crosshair({distance=num(args.distance,50)});if not result then return nil,cross_err end
    local list=result.targets or {}
    if args.all~=true then
        -- The nearest cloneable pick; fall back to the nearest of any kind so the user sees why.
        local best
        for _,t in ipairs(list) do local c=self:normalize(t);if c.supported then best=t;break end end
        list={best or list[1]}
    end
    local out=self:_stage(list,args.append==true,'crosshair');out.warning=result.warning
    return out
end

function VanillaClone:scan(args)
    args=args or {}
    local rht,err=self:_rht();if not rht then return nil,err end
    local result,scan_err=rht:scan({radius=num(args.radius,10),limit=num(args.limit,200),term=args.term,entities=args.entities==true,center=args.center})
    if not result then return nil,scan_err end
    local out=self:_stage(result.targets or {},args.append==true,'scan')
    out.warning=result.warning;out.note=result.note;out.truncated=result.truncated
    return out
end

-- Offline candidates (from lsbuild/vanilla.py or any caller) replace or extend the staged list.
function VanillaClone:stage(list,append) if type(list)~='table' then return nil,'candidates must be a list' end;return self:_stage(list,append==true,'sector_json') end

function VanillaClone:set_selected(index,value)
    if index=='all' or index=='none' then for _,c in ipairs(self.staged) do c.selected=index=='all' and c.supported and not c.already_cloned end;return self:candidates() end
    local c=self.staged[tonumber(index) or -1];if not c then return nil,'candidate not found' end
    if value and not c.supported then return nil,c.reason end
    c.selected=value==true;return self:candidates()
end

function VanillaClone:clear() self.staged={};return {cleared=true} end

-- World Builder entry (preferred: real WB class, appearance applied) or a direct CET template.
function VanillaClone:_resolve(c)
    local def=self.app.world_builder and self.app.world_builder:definition(c.definition_key)
    if def then
        local payload,err=self.app.world_builder:prepare_favorite_record({category=def.category,variant=def.variant,spawn_data=c.resource_path,name=c.name},c.name)
        if payload then
            local saved=payload.data and payload.data.spawnable
            if type(saved)=='table' then
                if c.appearance_name then saved.app=c.appearance_name end
                return {backend='world_builder',def=def,entry={name=payload.name,fileName=payload.name,data=saved}}
            end
        end
        if c.definition_key~='entity_template' then return nil,err or 'World Builder could not serialize this resource' end
    end
    if c.definition_key=='entity_template' then return {backend='cet'} end
    return nil,'World Builder is unavailable'
end

function VanillaClone:_value(c,resolved,args)
    local transform={position={x=c.position.x,y=c.position.y,z=c.position.z,w=1},rotation=c.rotation and Util.deepcopy(c.rotation) or {roll=0,pitch=0,yaw=0}}
    local scale=c.scale or {x=1,y=1,z=1}
    local source={key=c.key,node_id=c.node_id,node_ref=c.node_ref,node_type=c.node_type,sector_path=c.sector_path,node_index=c.node_index,instance_index=c.instance_index,
        debug_name=c.debug_name,resource_path=c.resource_path,appearance=c.appearance_name,record_id=c.record_id,entity_id=c.entity_id,confidence=c.confidence,scale_assumed=c.scale_assumed,
        quaternion=c.quaternion,source=c.source,original_transform=Util.deepcopy(transform),original_scale=Util.deepcopy(scale),warnings=Util.deepcopy(c.warnings),imported_at=Util.now_iso()}
    local value={premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id,name=c.name,enabled=true,transform=transform,
        size={x=1,y=1,z=1},metadata={source='LocationStudio vanilla clone',vanilla_source=source}}
    if resolved.backend=='world_builder' then
        local def=resolved.def
        value.kind=def.kind;value.template='';value.layer=args.layer or def.layer
        local apply_scale=MESH_KEYS[c.definition_key]==true
        if apply_scale then value.size=Util.deepcopy(scale) end
        value.metadata.world_builder={definition_key=def.key,category=def.category,variant=def.variant,class_module=def.class_module,module_path=def.class_module:gsub('^modules/classes/spawn/',''),
            resource_name=c.name,resource_path=c.resource_path,entry=resolved.entry,apply_scale=apply_scale}
    else
        value.kind='entity';value.template=c.resource_path;value.appearance=c.appearance_name;value.layer=args.layer or 'decoration'
    end
    if not MESH_KEYS[c.definition_key] and c.scale and (math.abs(c.scale.x-1)>1e-3 or math.abs(c.scale.y-1)>1e-3 or math.abs(c.scale.z-1)>1e-3) then
        source.warnings[#source.warnings+1]='the original node is scaled; this backend spawns clones at 1:1'
    end
    return value
end

-- Import staged candidates (indices, or every selected one) or explicit candidates.
function VanillaClone:import(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local list={}
    if type(args.candidates)=='table' then
        local cloned=self:_clone_index()
        for _,raw in ipairs(args.candidates) do local c=self:normalize(raw,'sector_json');c.already_cloned=c.key and cloned[c.key] or nil;list[#list+1]=c end
    elseif type(args.indices)=='table' then
        for _,i in ipairs(args.indices) do local c=self.staged[tonumber(i) or -1];if not c then return nil,'candidate '..tostring(i)..' not found' end;list[#list+1]=c end
    else for _,c in ipairs(self.staged) do if c.selected then list[#list+1]=c end end end
    if #list==0 then return nil,'no candidates selected; pick or scan vanilla nodes first' end
    if args.layer and self.app.layers then
        local l=self.app.layers:get(args.layer);if not l then return nil,'layer not found: '..tostring(args.layer) end
        if l.locked then return nil,'layer '..l.name..' is locked' end
    end

    local values,imported_from,skipped={}, {}, {}
    for _,c in ipairs(list) do
        local reason
        if not c.supported then reason=c.reason
        elseif c.already_cloned and args.allow_duplicate~=true then reason='already cloned as '..c.already_cloned..' (pass allow_duplicate to clone again)'
        elseif c.confidence=='position_only' and args.allow_approximate~=true then reason='RedHotTools reported only the position of this node; pass allow_approximate (rotation 0, scale 1, adjust afterwards) or import it from the exported sector JSON for the exact transform' end
        if not reason then
            local resolved,err=self:_resolve(c)
            if resolved then values[#values+1]=self:_value(c,resolved,args);imported_from[#values]=c else reason=err end
        end
        if reason then skipped[#skipped+1]={name=c.name,node_type=c.node_type,resource_path=c.resource_path,reason=reason} end
    end
    if #values==0 then return nil,'nothing was imported: '..tostring(skipped[1] and skipped[1].reason) end

    local model=self.app.model
    model:snapshot('Clone vanilla nodes')
    local objects=model:add_objects(values,true)
    local ids={};for _,o in ipairs(objects) do ids[#ids+1]=o.id end
    local group
    if args.group_name and Util.trim(args.group_name)~='' then
        local c={x=0,y=0,z=0};for _,o in ipairs(objects) do c.x=c.x+o.transform.position.x/#objects;c.y=c.y+o.transform.position.y/#objects;c.z=c.z+o.transform.position.z/#objects end
        group=model:create_object_group({name=Util.trim(args.group_name),premise_id=objects[1].premise_id,object_ids=ids,pivot_mode='center',pivot={position={x=c.x,y=c.y,z=c.z,w=1},rotation={roll=0,pitch=0,yaw=0}}},true)
    end
    for i,c in ipairs(imported_from) do if c.already_cloned==nil then c.already_cloned=objects[i].id end;c.selected=false end
    model:touch();self.app:mark_dirty()
    if self.app.selection and #ids>0 then self.app.selection:set_object_group(ids,ids[1]) end

    local result={imported=#objects,object_ids=ids,skipped=skipped,group_id=group and group.id or nil,hidden=0,hide_errors={},spawned=0,spawn_errors={},approximate=0,warnings={}}
    for i,o in ipairs(objects) do
        local src=o.metadata.vanilla_source
        if src.confidence=='position_only' then result.approximate=result.approximate+1 end
        for _,w in ipairs(src.warnings or {}) do result.warnings[#result.warnings+1]=o.name..': '..w end
        if args.hide_originals==true then
            if not src.node_id then result.hide_errors[#result.hide_errors+1]={object_id=o.id,error='no streamed node id (entity or offline pick without node id)'}
            elseif not self.app.vanilla_removal then result.hide_errors[#result.hide_errors+1]={object_id=o.id,error='vanilla removal is unavailable'}
            else
                local c=imported_from[i]
                local record,err=self.app.vanilla_removal:_record({node_id=src.node_id,node_ref=src.node_ref,node_type=src.node_type,sector_path=src.sector_path,
                    mesh_path=c.mesh_path,material_path=c.material_path,template_path=c.template_path,position=c.position},'clone')
                if record then src.removal_id=record.id;result.hidden=result.hidden+1 else result.hide_errors[#result.hide_errors+1]={object_id=o.id,error=err} end
            end
        end
        if args.spawn~=false then
            local ok,err=self.app.placement:spawn(o)
            if ok then result.spawned=result.spawned+1 else result.spawn_errors[#result.spawn_errors+1]={object_id=o.id,error=tostring(err)} end
        end
    end
    if result.approximate>0 then result.warning=result.approximate..' clone(s) use an approximate transform (rotation 0, scale 1); align them before exporting' end
    self.app.logger:info('vanilla_clone','imported',{count=#objects,skipped=#skipped,hidden=result.hidden})
    return result
end

local function differs(a,b,eps) return math.abs((tonumber(a) or 0)-(tonumber(b) or 0))>eps end

function VanillaClone:list(args)
    args=args or {}
    local rows={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local src=o.metadata and o.metadata.vanilla_source
        if src and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) then
            local ot=src.original_transform or {};local op=ot.position or {};local orr=ot.rotation or {};local p=o.transform.position;local r=o.transform.rotation
            local changes={}
            if differs(p.x,op.x,0.01) or differs(p.y,op.y,0.01) or differs(p.z,op.z,0.01) then changes[#changes+1]='position' end
            if differs(r.roll,orr.roll,0.1) or differs(r.pitch,orr.pitch,0.1) or differs(r.yaw,orr.yaw,0.1) then changes[#changes+1]='rotation' end
            local wb=o.metadata.world_builder;local app=wb and wb.entry and wb.entry.data and wb.entry.data.app or o.appearance
            if src.appearance and app and app~=src.appearance then changes[#changes+1]='appearance' end
            local removal=nil
            if src.removal_id and self.app.model.data.vanilla_removals then for _,rec in ipairs(self.app.model.data.vanilla_removals) do if rec.id==src.removal_id then removal=rec end end end
            rows[#rows+1]={id=o.id,name=o.name,node_type=src.node_type,node_ref=src.node_ref,sector_path=src.sector_path,resource_path=src.resource_path,
                confidence=src.confidence,changes=changes,modified=#changes>0,original_hidden=removal and removal.active~=false or false,removal_id=src.removal_id}
        end
    end
    return {items=rows,count=#rows}
end

-- Undo a clone: show the original node again and (by default) delete the clone.
function VanillaClone:revert(object_id,args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local o=self.app.model:get_object(object_id);local src=o and o.metadata and o.metadata.vanilla_source
    if not src then return nil,'object is not a vanilla clone' end
    local result={object_id=object_id,restored=false,deleted=false}
    if src.removal_id and self.app.vanilla_removal then
        local ok,err=self.app.vanilla_removal:restore(src.removal_id)
        if ok then result.restored=true else result.restore_error=err end
    end
    if args.delete~=false then
        if o.locked then return nil,'clone is locked; unlock it before deleting' end
        if self.app.placement:is_tracked(o) then local ok,err=self.app.placement:despawn(o);if not ok then result.error='could not despawn the clone: '..tostring(err);return result end end
        local ok,err=self.app.model:delete_object(object_id);if not ok then return nil,err end
        result.deleted=true;self.app:mark_dirty()
    else src.removal_id=result.restored and nil or src.removal_id;self.app:mark_dirty() end
    return result
end

function VanillaClone:status()
    local rht=self.app.rht_inspector and self.app.rht_inspector:status() or {ready=false,error='adapter unavailable'}
    local supported={};for k in pairs(NODE_TYPES) do supported[#supported+1]=k end;table.sort(supported)
    return {rht=rht,staged=#self.staged,clones=self:list({}).count,supported_node_types=supported,
        note='Live picks know the position only; use the exported sector JSON (vanilla_sector_nodes / vanilla_clone_from_sector) for exact rotation and scale.'}
end

return VanillaClone
