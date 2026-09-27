local Util=require('modules/util')
local Sync={};Sync.__index=Sync

local function table_or_empty(v) return type(v)=='table' and v or {} end
local function id_of(row) return row and tostring(row.id or '') or '' end
local function point_of(row)
    local p=row and (row.pos or row.position)
    if type(p)=='table' then return {x=tonumber(p.x or p[1]) or 0,y=tonumber(p.y or p[2]) or 0,z=tonumber(p.z or p[3]) or 0} end
end
local function close(a,b)
    if not a or not b then return false end
    return math.abs(a.x-b.x)<0.001 and math.abs(a.y-b.y)<0.001 and math.abs(a.z-b.z)<0.001
end
local function ensure_index(index,kind,rows)
    for _,row in ipairs(table_or_empty(rows)) do
        local link=row._locationStudio or row.locationStudio or row.location_studio or {}
        local local_id=tostring(link.id or row.location_id or row.volume_id or row.object_id or '')
        if local_id~='' and not index[kind..':'..local_id] then index[kind..':'..local_id]=row end
        local node_id=tostring(row.node_ref or row.id or '')
        if node_id~='' and not index[kind..'_node:'..node_id] then index[kind..'_node:'..node_id]=row end
    end
end

function Sync.new(app) return setmetatable({app=app,last_preview=nil},Sync) end

function Sync:_collect(incoming)
    if type(incoming)~='table' then return nil,'Quest Forge input must be a JSON object' end
    if incoming.format and incoming.format~='locationstudio-questforge-handoff' and incoming.format~='questforge' and incoming.format~='questforge/v2' then
        return nil,'Unsupported Quest Forge document format: '..tostring(incoming.format)
    end
    local index={};local world=table_or_empty(incoming.questforge_world or incoming.world or incoming)
    for _,sector in ipairs(table_or_empty(world.sectors)) do ensure_index(index,'location',sector.markers);ensure_index(index,'volume',sector.triggers) end
    ensure_index(index,'location',incoming.locations);ensure_index(index,'location',incoming.semantic_locations)
    ensure_index(index,'volume',incoming.volumes);ensure_index(index,'camera',incoming.cameras)
    for _,key in ipairs({'interactable_handoff','npc_population_handoff','npc_ai_routes','combat_encounters','cover_nodes'}) do
        local kind=key=='npc_ai_routes' and 'object' or 'object'
        ensure_index(index,kind,incoming[key])
    end
    local facts_by_id={}
    local function add_fact(target,name,value,source)
        name=tostring(name or '')
        if name=='' then return end
        for _,old in ipairs(target) do if old.name==name and old.value==(tonumber(value) or 1) and old.source==(source or 'Quest Forge') then return end end
        target[#target+1]={name=name,value=tonumber(value) or 1,source=source or 'Quest Forge'}
    end
    for _,fact in ipairs(table_or_empty(incoming.fact_triggers)) do
        local id=tostring(fact.volume_id or fact._locationStudio_id or fact.trigger_id or '')
        if id~='' then facts_by_id[id]=facts_by_id[id] or {};add_fact(facts_by_id[id],fact.fact,fact.value,'trigger') end
    end
    for _,sector in ipairs(table_or_empty(world.sectors)) do
        for _,trigger in ipairs(table_or_empty(sector.triggers)) do
            local link=trigger._locationStudio or {};local id=tostring(link.id or '')
            local qf=trigger._questforge or {}
            if id~='' and qf.fact then facts_by_id[id]=facts_by_id[id] or {};add_fact(facts_by_id[id],qf.fact,qf.value,'trigger') end
        end
    end
    for _,population in ipairs(table_or_empty(incoming.npc_population_handoff)) do
        local id=tostring(population.id or '')
        if id~='' then for _,condition in ipairs(table_or_empty(population.conditions)) do facts_by_id[id]=facts_by_id[id] or {};add_fact(facts_by_id[id],condition.fact_name,condition.fact_value,'npc condition') end end
    end
    for _,enc in ipairs(table_or_empty(incoming.combat_encounters)) do
        local id=tostring(enc.id or '')
        if id~='' then facts_by_id[id]=facts_by_id[id] or {};add_fact(facts_by_id[id],enc.activation_fact,enc.activation_value,'encounter activation');add_fact(facts_by_id[id],enc.reset_fact,enc.reset_value,'encounter reset') end
    end
    for _,graph in ipairs(table_or_empty(incoming.device_logic_graphs)) do
        for _,node in ipairs(table_or_empty(graph.nodes)) do
            local oid=tostring(node.object_id or (node.config or {}).object_id or '')
            local fact=(node.config or {}).fact_name
            if oid~='' and fact then facts_by_id[oid]=facts_by_id[oid] or {};add_fact(facts_by_id[oid],fact,(node.config or {}).value,'device logic') end
        end
    end
    local manifest=((incoming.quest_manifest_fragment or {}).locations) or ((incoming.quest_manifest or {}).locations)
    return {index=index,facts=facts_by_id,manifest=table_or_empty(manifest),source_project=table_or_empty(incoming.project)}
end

local COLLECTIONS={{key='locations',kind='location'},{key='volumes',kind='volume'},{key='cameras',kind='camera'},{key='objects',kind='object'}}
function Sync:preview(incoming)
    local data,err=self:_collect(incoming);if not data then return nil,err end
    local rows={};local seen={};local counts={matched=0,unmatched=0,position_conflicts=0,facts=0}
    for _,spec in ipairs(COLLECTIONS) do
        for _,local_item in ipairs(self.app.model.data[spec.key] or {}) do
            local metadata=local_item.metadata or {};local old=metadata.questforge_sync or {}
            local remote=data.index[spec.kind..':'..id_of(local_item)] or (old.node_ref and data.index[spec.kind..'_node:'..tostring(old.node_ref)])
            local remote_point=point_of(remote)
            local local_point=((local_item.transform or {}).position or {})
            local conflict=remote_point and not close({x=tonumber(local_point.x) or 0,y=tonumber(local_point.y) or 0,z=tonumber(local_point.z) or 0},remote_point)
            local manifest_name,node_ref
            for name,m in pairs(data.manifest) do if remote and m.node_ref and (m.node_ref==remote.id or m.node_ref==remote.node_ref) then manifest_name=name;node_ref=m.node_ref;break end end
            if remote then
                seen[spec.kind..':'..id_of(local_item)]=true;counts.matched=counts.matched+1
                if conflict then counts.position_conflicts=counts.position_conflicts+1 end
                local facts=data.facts[id_of(local_item)] or data.facts[tostring(old.node_ref or '')] or {}
                counts.facts=counts.facts+#facts
                rows[#rows+1]={id=local_item.id,name=local_item.name,kind=spec.kind,node_ref=node_ref or remote.node_ref or remote.id,
                    manifest_name=manifest_name,facts=Util.deepcopy(facts),position_conflict=conflict==true,
                    remote_position=remote_point,local_position=Util.deepcopy(local_point),had_link=old.linked==true}
            end
        end
    end
    for key in pairs(data.index) do if not seen[key] then counts.unmatched=counts.unmatched+1 end end
    self.last_preview={data=data,rows=rows,counts=counts,incoming=incoming}
    return {rows=rows,counts=counts,source_project=data.source_project.name or data.source_project.id or '',safe_default='metadata_only'}
end

function Sync:apply(incoming,options)
    options=options or {};local preview,err=self:preview(incoming);if not preview then return nil,err end
    local p=self.last_preview;local applied=0
    self.app.model:snapshot('Import Quest Forge links')
    for _,row in ipairs(p.rows) do
        local item
        for _,spec in ipairs(COLLECTIONS) do for _,candidate in ipairs(self.app.model.data[spec.key] or {}) do if candidate.id==row.id then item=candidate;break end end;if item then break end end
        if item then
            item.metadata=item.metadata or {};local prev=item.metadata.questforge_sync or {}
            item.metadata.questforge_sync={linked=true,kind=row.kind,node_ref=row.node_ref,manifest_name=row.manifest_name,
                facts=Util.deepcopy(row.facts),external_position=Util.deepcopy(row.remote_position),position_conflict=row.position_conflict,
                local_position=Util.deepcopy(row.local_position),last_imported_at=Util.now_iso(),source_project=p.data.source_project.name or p.data.source_project.id or '',
                previous_link_at=prev.last_imported_at}
            if options.apply_positions==true and row.remote_position and row.position_conflict and item.transform then
                item.transform.position.x=row.remote_position.x;item.transform.position.y=row.remote_position.y;item.transform.position.z=row.remote_position.z
                item.metadata.questforge_sync.position_conflict=false;item.metadata.questforge_sync.local_position=Util.deepcopy(row.remote_position)
            end
            item.updated_at=Util.now_iso();applied=applied+1
        end
    end
    if applied>0 then self.app.model:touch();self.app:mark_dirty() end
    return {applied=applied,counts=preview.counts,positions_applied=options.apply_positions==true,
        preserved_local_fields={'name','notes','tags','category','radius','enabled','non-Quest-Forge metadata'},warning='Only exact LocationStudio IDs are linked; unmatched Quest Forge nodes are not imported as new spatial objects.'}
end

function Sync:links(kind,id)
    local item
    for _,spec in ipairs(COLLECTIONS) do if not kind or kind==spec.kind then for _,candidate in ipairs(self.app.model.data[spec.key] or {}) do if candidate.id==id then item=candidate;break end end end;if item then break end end
    if not item then return nil,'linked project item not found' end
    local link=((item.metadata or {}).questforge_sync) or {}
    return {id=item.id,name=item.name,kind=kind or 'item',linked=link.linked==true,node_ref=link.node_ref,manifest_name=link.manifest_name,
        facts=Util.deepcopy(link.facts or {}),position_conflict=link.position_conflict==true,local_position=link.local_position,external_position=link.external_position}
end
return Sync
