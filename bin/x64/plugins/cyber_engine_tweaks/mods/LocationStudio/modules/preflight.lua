local Util=require('modules/util')

-- Shipping preflight: the project/live half of one validator. Every check
-- returns pass / warn / fail / skipped with issues naming the object. The MCP
-- `preflight_run` tool merges this with the offline checks (dependencies,
-- sector report, native interactables, NPC population audit, visual
-- regression) into one report and verdict.
local Preflight={};Preflight.__index=Preflight

Preflight.SCHEMA='locationstudio-preflight/1'
Preflight.REPORT_PATH='exports/preflight-report.json'

local FACT='^[%w_%.%-]+$'
-- World Builder definitions whose resource_path must name a real resource.
local RESOURCE_KEYS={entity_template=true,entity_amm=true,entity_record=true,device=true,mesh_static=true,mesh_rotating=true,mesh_cloth=true,
    mesh_dynamic=true,mesh_proxy=true,collision_mesh=true,decal=true,particle=true,effect=true,audio=true,water=true}
local MESH_KEYS={mesh_static=true,mesh_rotating=true,mesh_cloth=true,mesh_dynamic=true,mesh_proxy=true}
local PATH_EXT={mesh_static='mesh',mesh_rotating='mesh',mesh_cloth='mesh',mesh_dynamic='mesh',mesh_proxy='mesh',collision_mesh='mesh',
    entity_template='ent',entity_amm='ent',device='ent',decal='mi',particle='particle',effect='effect'}

local function valid_fact(v) v=tostring(v or '');return #v>0 and #v<=128 and v:match(FACT)~=nil end

function Preflight.new(app) return setmetatable({app=app,last=nil,loaded=nil,last_error=nil},Preflight) end

function Preflight:_scope(args)
    local out={}
    local layers=self.app.layers
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local md=o.metadata or {}
        if not md.reference_area_id and (not layers or layers:export_enabled(o)) and (not args.premise_id or o.premise_id==args.premise_id) then out[#out+1]=o end
    end
    return out
end

local function check(id,label)
    local c={id=id,label=label,issues={},status='pass'}
    function c.add(severity,message,extra)
        local issue={severity=severity,message=message};for k,v in pairs(extra or {}) do issue[k]=v end
        c.issues[#c.issues+1]=issue
        if severity=='error' then c.status='fail' elseif severity=='warning' and c.status=='pass' then c.status='warn' end
    end
    return c
end
local function obj(o) return {object_id=o.id,name=o.name} end

function Preflight:_project(args)
    local c=check('project','Project data')
    for _,i in ipairs(self.app.model:validate() or {}) do
        if i.severity=='error' or i.severity=='warning' then c.add(i.severity,i.message,{item_id=i.id}) end
    end
    return c
end

function Preflight:_resource_paths(objects,args)
    local c=check('resource_paths','Resource paths')
    local catalogs={}
    for _,o in ipairs(objects) do
        local wb=o.metadata and o.metadata.world_builder
        local proc=o.metadata and o.metadata.procedural
        if proc then
            if #(proc.parts or {})==0 then c.add('error','procedural geometry has no parts; regenerate it',obj(o)) end
            if not tostring(proc.mesh_path or ''):lower():match('%.mesh$') then c.add('error','procedural mesh path is not a .mesh depot path',obj(o)) end
            local mat=proc.material or {};local tpl=Util.trim(tostring(mat.template or ''))
            local slots=type(mat.materials)=='table' and mat.materials or {}
            if tpl=='' and not slots.main then c.add('error','procedural geometry needs materials.main (a .mi for the native mesh) or material.template (a .mesh to import over) before Build Mod',obj(o)) end
            for slot,ref in pairs(slots) do
                if type(ref)=='string' and ref:sub(1,1)=='@' then
                    local err='the material library is unavailable'
                    if self.app.material_library then local _r;_r,err=self.app.material_library:resolve(ref) end
                    if err then c.add('error','materials.'..slot..': '..tostring(err or 'the material library is unavailable'),obj(o)) end
                end
            end
            if slots.main then
                local glass=false;for _,part in ipairs(proc.parts or {}) do if part.material=='glass' then glass=true end end
                if glass and not slots.glass then c.add('error','the geometry has glass but materials.glass is not set',obj(o)) end
            end
        elseif type(wb)=='table' then
            local key=wb.definition_key;local path=Util.trim(tostring(wb.resource_path or ''))
            if not (self.app.world_builder and self.app.world_builder:definition(key)) then c.add('error','unknown World Builder definition '..tostring(key),obj(o))
            elseif RESOURCE_KEYS[key] and path=='' then c.add('error','no resource path for '..key,obj(o))
            elseif RESOURCE_KEYS[key] then
                local ext=PATH_EXT[key]
                if ext and not path:lower():match('%.'..ext..'$') then c.add('error',key..' resource does not end in .'..ext..': '..path,obj(o))
                elseif key=='entity_record' and not path:match('^[%w_]+%.[%w_%.]+$') then c.add('error','entity record is not a TweakDB id: '..path,obj(o))
                elseif args.deep==true and self.app.world_builder then
                    if catalogs[key]==nil then
                        local values=self.app.world_builder:load_catalog(key,false)
                        local set=false
                        if values then set={};for _,r in ipairs(values) do set[string.lower(tostring(r.path or ''))]=true end end
                        catalogs[key]=set
                    end
                    if catalogs[key] and not catalogs[key][path:lower()] then c.add('warning','not in the World Builder '..key..' catalog (modded? see the dependency check): '..path,obj(o)) end
                end
            end
            if type(wb.entry)~='table' or type(wb.entry.data)~='table' then c.add('error','World Builder entry data is missing',obj(o)) end
        else
            local template=Util.trim(tostring(o.template or ''))
            if template=='' and o.kind~='marker' then c.add('error','no template or World Builder resource',obj(o))
            elseif template~='' and not template:lower():match('%.ent$') then c.add('error','template is not an .ent: '..template,obj(o)) end
        end
    end
    if args.deep~=true then c.note='Pass deep=true to also look every path up in the loaded World Builder catalogs.' end
    return c
end

function Preflight:_bounds(objects)
    local c=check('bounds','Asset bounds')
    for _,o in ipairs(objects) do
        local wb=o.metadata and o.metadata.world_builder
        if type(wb)=='table' and MESH_KEYS[wb.definition_key] then
            local ok=self.app.asset_bounds and self.app.asset_bounds:world_aabb(o.id)
            if not ok then c.add('warning','no imported bounds; overlap, fit, performance and visibility checks cannot measure it (wb_bounds_import)',obj(o)) end
        end
    end
    return c
end

function Preflight:_generated_bounds(objects)
    local c=check('generated_bounds','Generated bounds')
    if not self.app.bounds_gen then return c end
    for _,i in ipairs(self.app.bounds_gen:issues(objects)) do c.add(i.severity,i.message,{object_id=i.object_id,name=i.name}) end
    return c
end

function Preflight:_spawns(objects,live)
    local c=check('spawns','Spawns')
    for _,o in ipairs(objects) do
        local r=o.runtime or {}
        if r.spawn_error or r.state=='failed' then c.add('error','spawn failed: '..tostring(r.spawn_error or r.error or 'unknown error'),obj(o)) end
    end
    if live and self.app.placement and self.app.placement.compare_runtime then
        local ok,report=pcall(function() return self.app.placement:compare_runtime() end)
        if ok and report then
            for _,item in ipairs(report.items or {}) do
                if item.action=='spawn' then c.add('error','expected live but not spawned ('..tostring(item.backend)..')',{object_id=item.id,name=item.name})
                elseif item.action=='update' then c.add('warning','live object differs from saved data; run sync_runtime',{object_id=item.id,name=item.name}) end
            end
        elseif not ok then c.add('warning','runtime comparison failed: '..tostring(report)) end
    elseif not live then c.note='Game runtime not ready: only stored spawn errors were checked.' end
    return c
end

function Preflight:_noderefs()
    local c=check('noderefs','NodeRefs')
    local seen={}
    local function visit(kind,item,ref)
        if ref==nil or ref=='' then return end
        ref=tostring(ref)
        if ref:find('%s') or not ref:match('^[%w_%$/#%.%-:]+$') then c.add('error','malformed NodeRef '..ref,{item_id=item.id,name=item.name,kind=kind}) end
        if seen[ref] then c.add('error','NodeRef '..ref..' is used by both '..seen[ref]..' and '..tostring(item.name),{item_id=item.id,name=item.name,kind=kind})
        else seen[ref]=tostring(item.name) end
    end
    for _,collection in ipairs({'objects','locations','volumes'}) do
        for _,item in ipairs(self.app.model.data[collection] or {}) do
            local md=item.metadata or {}
            if not md.reference_area_id then
                visit(collection,item,md.node_ref)
                visit(collection,item,md.questforge_sync and md.questforge_sync.linked and md.questforge_sync.node_ref)
            end
        end
    end
    for _,g in ipairs(self.app.model.data.device_logic_graphs or {}) do
        for _,n in ipairs(g.nodes or {}) do
            local ref=n.native and n.native.node_ref
            if ref and ref~='' and not seen[tostring(ref)] and n.object_id and not self.app.model:get_object(n.object_id) then
                c.add('error','device node '..tostring(n.name or n.id)..' is bound to a deleted object',{graph=g.name})
            end
        end
    end
    c.note='Sector-level NodeRef resolution (references to nodes missing from the export) is added by the MCP preflight from the sector report.'
    return c
end

function Preflight:_quest_facts()
    local c=check('quest_facts','Quest facts')
    local function test(fact,where,extra) if fact~=nil and fact~='' and not valid_fact(fact) then c.add('error','invalid fact name "'..tostring(fact)..'" in '..where,extra) end end
    local data=self.app.model.data
    for _,v in ipairs(data.volumes or {}) do local qf=v.metadata and v.metadata.questforge;if qf then test(qf.fact_name,'volume '..v.name,{item_id=v.id}) end end
    for _,v in ipairs(data.world_state_variants or {}) do
        for i,cond in ipairs(v.conditions or {}) do
            if not valid_fact(cond.fact_name) then c.add('error','world-state variant '..v.name..' condition '..i..' has an invalid fact name',{item_id=v.id}) end
            if cond.value~=nil and (tonumber(cond.value)==nil or tonumber(cond.value)%1~=0) then c.add('error','world-state variant '..v.name..' condition '..i..' value is not an integer',{item_id=v.id}) end
        end
    end
    for _,e in ipairs(data.combat_encounters or {}) do
        test(e.activation_fact,'encounter '..tostring(e.name),{item_id=e.id});test(e.reset_fact,'encounter '..tostring(e.name),{item_id=e.id})
        for _,w in ipairs(e.waves or {}) do test(w.fact_name,'encounter '..tostring(e.name)..' wave',{item_id=e.id}) end
    end
    for _,r in ipairs(data.npc_routes or {}) do
        for _,field in ipairs({'waypoints','alert_waypoints','combat_waypoints'}) do for _,wp in ipairs(r[field] or {}) do test(wp.branch_fact,'route '..tostring(r.name),{item_id=r.id}) end end
    end
    for _,o in ipairs(data.objects or {}) do
        local md=o.metadata or {}
        if md.interactable then test(md.interactable.fact_name,'interactable '..o.name,obj(o))
            local v=tonumber(md.interactable.fact_value);if md.interactable.fact_name and md.interactable.fact_name~='' and (not v or v%1~=0 or v< -2147483648 or v>2147483647) then c.add('error','interactable '..o.name..' fact value must be a 32-bit integer',obj(o)) end
        end
        for i,cond in ipairs((md.npc_population and md.npc_population.conditions) or {}) do test(cond.fact_name,'population '..o.name..' condition '..i,obj(o)) end
    end
    for _,t in ipairs(data.timelines or {}) do
        for _,tr in ipairs(t.tracks or {}) do if tr.kind=='fact' then for _,k in ipairs(tr.keys or {}) do test(k.fact,'timeline '..t.name,{item_id=t.id}) end end end
    end
    return c
end

function Preflight:_interactables(objects)
    local c=check('interactables','Native interactable setup')
    local loot_seen={}
    for _,o in ipairs(objects) do
        local cfg=o.metadata and o.metadata.interactable
        if cfg then
            local kind=cfg.kind
            if not ({door=true,loot_container=true,shard=true,item=true})[kind] then c.add('error','unknown interactable kind '..tostring(kind),obj(o)) end
            if kind=='loot_container' then
                local t=tostring(cfg.loot_table or '')
                if not t:match('^LootTables%.[%w_%.]+$') then c.add('error','loot container has no valid LootTables.* record',obj(o))
                elseif loot_seen[t] then c.add('error','loot table '..t..' is used by two containers',obj(o)) else loot_seen[t]=true end
                if type(cfg.loot_items)~='table' or #cfg.loot_items==0 then c.add('error','loot container has no loot items',obj(o)) end
                for i,item in ipairs(cfg.loot_items or {}) do if not tostring(item.item_record or ''):match('^Items%.[%w_%.]+$') then c.add('error','loot item '..i..' needs an Items.* record',obj(o)) end end
            elseif (kind=='shard' or kind=='item') and not tostring(cfg.item_record or ''):match('^Items%.[%w_%.]+$') then c.add('error',kind..' needs an Items.* item record',obj(o)) end
            if cfg.native_setup_required~=false and cfg.setup_status~='native_ready' then
                c.add('warning','interaction wiring is authoring-only until Build Mod generates it ('..tostring(cfg.setup_status or 'authoring_only')..')',obj(o))
            end
        end
    end
    return c
end

function Preflight:_ambient_areas(objects)
    local c=check('ambient_areas','Ambient areas')
    local markers,areas={}, {}
    for _,o in ipairs(objects) do
        local z=o.metadata and o.metadata.ambient_zone
        if z and z.role=='outline_marker' then local g=tostring(z.outline_group or z.id);markers[g]=(markers[g] or 0)+1
        elseif z and z.role=='area' then areas[#areas+1]=o end
        local a=o.metadata and o.metadata.ambient_audio
        if a and a.role=='emitter' and Util.trim(tostring(a.event or ''))=='' then c.add('error','audio emitter has no sound event',obj(o)) end
    end
    local owned={}
    for _,o in ipairs(areas) do
        local z=o.metadata.ambient_zone;local g=tostring(z.outline_group or z.id);owned[g]=true
        if (markers[g] or 0)<3 then c.add('error','ambient area has '..tostring(markers[g] or 0)..' outline marker(s); it needs at least 3',obj(o)) end
        if not tonumber(z.height) or tonumber(z.height)<=0 then c.add('error','ambient area has no height',obj(o)) end
        if Util.trim(tostring(z.sound_event or ''))=='' and (z.reverb==nil or z.reverb=='' or z.reverb=='None') then c.add('warning','ambient area has neither a sound event nor a reverb',obj(o)) end
    end
    for g,n in pairs(markers) do if not owned[g] then c.add('warning',n..' outline marker(s) of group '..g..' belong to no ambient area') end end
    return c
end

function Preflight:_workspots()
    local c=check('workspots','Workspots and routes')
    local used={}
    for _,r in ipairs(self.app.model.data.npc_routes or {}) do
        local count=0
        for _,field in ipairs({'waypoints','alert_waypoints','combat_waypoints'}) do
            for _,wp in ipairs(r[field] or {}) do
                count=count+1
                if wp.transition=='workspot' then
                    local loc=self.app.model:get_location(wp.workspot_location_id)
                    if not loc or not (loc.metadata and loc.metadata.workspot) then c.add('error','route '..tostring(r.name)..' uses a deleted workspot',{item_id=r.id})
                    else used[loc.id]=true end
                end
            end
        end
        if count==0 then c.add('warning','NPC route '..tostring(r.name)..' has no waypoints',{item_id=r.id}) end
        if not self.app.model:get_object(r.npc_id) then c.add('error','NPC route '..tostring(r.name)..' belongs to a deleted NPC',{item_id=r.id}) end
    end
    for _,loc in ipairs(self.app.model.data.locations or {}) do
        if loc.metadata and loc.metadata.workspot and not used[loc.id] then c.add('warning','workspot '..tostring(loc.name)..' is not on any NPC route; no NPC will use it',{item_id=loc.id,name=loc.name}) end
    end
    return c
end

function Preflight:_device_links()
    local c=check('device_links','Device links')
    if not self.app.device_logic then c.status='skipped';c.note='device logic module unavailable';return c end
    local report=self.app.device_logic:validate()
    for _,g in ipairs(report and report.graphs or {}) do
        for _,e in ipairs(g.errors or {}) do c.add('error',g.name..': '..e,{item_id=g.id}) end
        for _,w in ipairs(g.warnings or {}) do c.add('warning',g.name..': '..w,{item_id=g.id}) end
    end
    return c
end

function Preflight:_cet_entities(objects,live)
    local c=check('cet_entities','Exportable objects')
    local exportable=0
    for _,o in ipairs(objects) do
        if o.enabled~=false then
            local wb=o.metadata and o.metadata.world_builder
            if o.metadata and o.metadata.procedural then exportable=exportable+1
            elseif type(wb)~='table' then c.add('error','CET entity-spawner object cannot be exported to a native sector; re-create it from a World Builder Entity Template asset',obj(o))
            else
                exportable=exportable+1
                if live then
                    local handle=self.app.runtime_shell and self.app.runtime_shell.handles[o.id]
                    if not handle then c.add('warning','World Builder object is not live; Build Mod export needs it spawned',obj(o)) end
                end
            end
        end
    end
    if exportable==0 and #objects>0 then c.add('error','nothing in scope can be exported') end
    return c
end

-- Run every project/live check. args: premise_id, deep.
function Preflight:run(args)
    args=args or {}
    local live=self.app.ready==true and self.app.world_builder~=nil and (self.app.world_builder:status() or {}).available==true
    local objects=self:_scope(args)
    local checks={}
    local function run(fn,...)
        local ok,c=pcall(fn,self,...)
        if ok then checks[#checks+1]=c else checks[#checks+1]={id='internal',label='Internal error',status='fail',issues={{severity='error',message=tostring(c)}}} end
    end
    run(self._project,args)
    run(self._resource_paths,objects,args)
    run(self._bounds,objects)
    run(self._generated_bounds,objects)
    run(self._spawns,objects,live)
    run(self._noderefs)
    run(self._quest_facts)
    run(self._interactables,objects)
    run(self._ambient_areas,objects)
    run(self._workspots)
    run(self._device_links)
    run(self._cet_entities,objects,live)
    local summary={pass=0,warn=0,fail=0,skipped=0,errors=0,warnings=0}
    for _,c in ipairs(checks) do
        c.count=#c.issues;summary[c.status]=(summary[c.status] or 0)+1
        for _,i in ipairs(c.issues) do if i.severity=='error' then summary.errors=summary.errors+1 else summary.warnings=summary.warnings+1 end end
    end
    local report={schema=Preflight.SCHEMA,generated_at=Util.now_iso(),mod_version=self.app.version,scope={premise_id=args.premise_id,objects=#objects},
        live=live,checks=checks,summary=summary,ready=summary.fail==0,source='cet'}
    self.last=report
    return report
end

-- The merged report the MCP preflight writes (includes offline checks).
function Preflight:load()
    if not Util.file_exists(Preflight.REPORT_PATH) then self.loaded=nil;self.last_error='No full preflight report yet. Run preflight_run from MCP.';return nil,self.last_error end
    local report=Util.json_read(Preflight.REPORT_PATH,nil)
    if type(report)~='table' or report.schema~=Preflight.SCHEMA then self.loaded=nil;self.last_error='Preflight report is unreadable or from an unsupported version.';return nil,self.last_error end
    self.loaded=report;self.last_error=nil
    return {ready=report.ready,summary=report.summary,generated_at=report.generated_at}
end

function Preflight:select_issue(check_id,index)
    local report=self.loaded or self.last;if not report then return nil,'run the preflight first' end
    for _,c in ipairs(report.checks or {}) do
        if c.id==check_id then
            local issue=(c.issues or {})[tonumber(index) or 0];if not issue then return nil,'issue not found' end
            local id=issue.object_id;if not id then return nil,'this issue is not about a placed object' end
            local o=self.app.model:get_object(id);if not o then return nil,'the object no longer exists' end
            self.app.selection:set('object',o.id);return {selected=o.id,name=o.name,issue=Util.deepcopy(issue)}
        end
    end
    return nil,'check not found'
end

return Preflight
