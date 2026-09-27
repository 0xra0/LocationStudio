-- Reversible removal of native streamed world nodes through RedHotTools.
-- This deliberately implements visibility removal, not permanent REDengine deletion:
-- the public runtime API exposes ToggleNodeVisibility, but no supported delete API.
local VanillaRemoval = {}
VanillaRemoval.__index = VanillaRemoval

local function number(v, fallback)
    v = tonumber(v)
    return v or fallback
end

local function copy_position(p)
    if type(p) ~= 'table' then return nil end
    return {x=number(p.x, 0), y=number(p.y, 0), z=number(p.z, 0)}
end

function VanillaRemoval.new(app)
    return setmetatable({app=app, last_error=nil}, VanillaRemoval)
end

function VanillaRemoval:_records()
    self.app.model.data.vanilla_removals=self.app.model.data.vanilla_removals or {}
    return self.app.model.data.vanilla_removals
end

function VanillaRemoval:_rht()
    if not self.app.rht_inspector then return nil, 'RedHotTools inspector adapter is unavailable' end
    local status=self.app.rht_inspector:status()
    if not status.ready then return nil, status.error or 'RedHotTools WorldInspector is unavailable' end
    return self.app.rht_inspector
end

function VanillaRemoval:status()
    local records=self:_records()
    local active=0
    for _, record in ipairs(records) do if record.active ~= false then active=active+1 end end
    local rht=self.app.rht_inspector and self.app.rht_inspector:status() or {plugin=false,ready=false,error='adapter unavailable'}
    return {count=#records, active=active, reversible=true, persistent=true,
            operation='toggle_visibility', permanent_delete=false, rht=rht,
            limitation='Native streamed nodes are hidden through RedHotTools ToggleNodeVisibility; permanent deletion is not exposed by the verified API.'}
end

function VanillaRemoval:_find(node_id)
    local rht,err=self:_rht(); if not rht then return nil,err end
    local data,target_or_err=rht:removal_target({node_id=node_id})
    if not data then return nil,target_or_err end
    return target_or_err
end

function VanillaRemoval:_toggle(record, desired_hidden)
    local target,err=self:_find(record.node_id)
    if not target then return false,err end
    if not target.is_visible_node then return false,'target is not a visible streamed world node' end
    -- RHT only exposes a toggle. A stored state lets us make restore deterministic.
    if (record.hidden == true) ~= (desired_hidden == true) then
        local ok,toggle_err=self.app.rht_inspector:toggle_node(target)
        if not ok then return false,toggle_err end
    end
    record.updated_at=self.app.util.now_iso()
    record.hidden=desired_hidden==true
    record.active=desired_hidden==true
    return true
end

-- RedHotTools describe() reports camelCase fields; accept both spellings.
local function snake(data)
    if type(data) ~= 'table' then return data end
    data.node_id = data.node_id or data.nodeID
    data.node_ref = data.node_ref or data.nodeRef
    data.node_type = data.node_type or data.nodeType
    data.node_parent_id = data.node_parent_id or data.nodeParentID
    data.sector_path = data.sector_path or data.sectorPath
    data.mesh_path = data.mesh_path or data.meshPath
    data.material_path = data.material_path or data.materialPath
    data.template_path = data.template_path or data.templatePath
    if data.is_node == nil then data.is_node = data.isNode end
    if data.is_entity == nil then data.is_entity = data.isEntity end
    return data
end

function VanillaRemoval:_record(data, source)
    data = snake(data)
    if not data or not data.node_id then return nil,'target has no stable streamed node ID' end
    if data.is_entity and not data.node_id then return nil,'entity-only targets cannot be removed safely' end
    for _, existing in ipairs(self:_records()) do
        if existing.node_id == tostring(data.node_id) then
            if existing.active ~= false then return nil,'that vanilla node is already hidden' end
            local ok,err=self:_toggle(existing,true); if not ok then return nil,err end
            return existing
        end
    end
    local record={
        id=self.app.util.make_id('vanilla'), node_id=tostring(data.node_id), node_ref=data.node_ref,
        node_type=data.node_type, node_parent_id=data.node_parent_id, sector_path=data.sector_path,
        mesh_path=data.mesh_path, material_path=data.material_path, template_path=data.template_path,
        position=copy_position(data.position), source=source or 'crosshair', hidden=false, active=false,
        created_at=self.app.util.now_iso(), updated_at=self.app.util.now_iso(),
    }
    local ok,err=self:_toggle(record,true)
    if not ok then return nil,err end
    table.insert(self:_records(),record)
    self.app.model:touch(); self.app:mark_dirty()
    self.app.logger:info('vanilla_removal','hidden',{id=record.id,node_id=record.node_id,source=source})
    return record
end

function VanillaRemoval:remove_crosshair(args)
    args=args or {}
    local rht,err=self:_rht(); if not rht then return nil,err end
    local result,cross_err=rht:crosshair({distance=number(args.distance,50)})
    if not result then return nil,cross_err end
    local target
    for _, candidate in ipairs(result.targets or {}) do
        candidate=snake(candidate)
        if candidate.node_id and candidate.is_node then target=candidate;break end
    end
    if not target then return nil,'crosshair did not resolve a removable streamed world node; entity-only targets are not mutated' end
    local record,remove_err=self:_record(target,'crosshair')
    if not record then return nil,remove_err end
    return {removed=true,operation='toggle_visibility',permanent=false,reversible=true,persistent=true,
            record=record,warning='This hides the native streamed node; it is not permanent deletion.'}
end

function VanillaRemoval:remove_nearby(args)
    args=args or {}
    local rht,err=self:_rht(); if not rht then return nil,err end
    local radius=math.max(0.1,number(args.radius,25))
    local scan,scan_err=rht:scan({radius=radius,limit=number(args.limit,300),term=args.term,entities=false})
    if not scan then return nil,scan_err end
    local removed,failed={},{}
    for _, target in ipairs(scan.targets or {}) do
        target=snake(target)
        if target.node_id and target.is_node then
            local record,remove_err=self:_record(target,'nearby')
            if record then table.insert(removed,record) else table.insert(failed,{target=target,error=remove_err}) end
        end
    end
    if #removed>0 then self.app.model:touch();self.app:mark_dirty() end
    return {removed=#removed,failed=#failed,radius=radius,records=removed,failures=failed,
            operation='toggle_visibility',permanent=false,reversible=true,persistent=true,
            warning='Nearby removal hides eligible streamed nodes only; it is not permanent deletion.',scan_warning=scan.warning}
end

function VanillaRemoval:restore(id)
    local records=self:_records(); local target
    for _, record in ipairs(records) do
        if (id and record.id==id) or (not id and record.active ~= false) then target=record;break end
    end
    if not target then return nil,id and 'vanilla removal record not found' or 'no vanilla removal records' end
    local ok,err=self:_toggle(target,false); if not ok then return nil,err end
    target.updated_at=self.app.util.now_iso(); self.app.model:touch(); self.app:mark_dirty()
    return {restored=true,id=target.id,node_id=target.node_id,reversible=true}
end

function VanillaRemoval:restore_all()
    local restored,failed=0,{}
    for _, record in ipairs(self:_records()) do
        if record.active ~= false then
            local ok,err=self:_toggle(record,false)
            if ok then restored=restored+1 else table.insert(failed,{id=record.id,error=err}) end
        end
    end
    if restored>0 then self.app.model:touch();self.app:mark_dirty() end
    return {restored=restored,failed=#failed,failures=failed}
end

function VanillaRemoval:list()
    return {records=self:_records(),status=self:status()}
end

return VanillaRemoval
