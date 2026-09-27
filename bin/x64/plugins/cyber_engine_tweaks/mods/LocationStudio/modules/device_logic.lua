-- Device behavior graph authoring and native-resource completeness audit.
local Util=require('modules/util')
local DeviceLogic={};DeviceLogic.__index=DeviceLogic
local node_kinds={terminal=true,door=true,elevator=true,switch=true,camera=true,security_system=true,fact=true,action=true}
local actions={set_fact=true,unlock=true,lock=true,enable=true,disable=true,alarm=true,set_camera_state=true,elevator_floor=true,emit_event=true,custom=true}
local function valid_fact(v) return type(v)=='string' and #v>0 and #v<=128 and v:match('^[%w_.]+$')~=nil end
local function clean(v,max) local s=Util.trim(tostring(v or ''));if #s>max then return nil end;return s end
local function find(rows,id) for _,v in ipairs(rows or {}) do if v.id==id then return v end end end
local function dirty(self) self.app.model:touch();self.app:mark_dirty() end
local function valid_int(v) local n=tonumber(v);return n and n==math.floor(n) and math.abs(n)<=2147483647 end
function DeviceLogic.new(app) return setmetatable({app=app},DeviceLogic) end
function DeviceLogic:list() return self.app.model.data.device_logic_graphs or {} end
function DeviceLogic:get(id) return find(self:list(),id) end
function DeviceLogic:create(a)
    a=a or {};local name=clean(a.name or 'Device Logic',128);if not name or name=='' then return nil,'graph name is required (max 128 characters)' end
    if a.premise_id and not self.app.model:get_premise(a.premise_id) then return nil,'premise_id does not exist' end
    self.app.model:snapshot('Create device logic graph');local graph={id=Util.make_id('logic'),name=name,premise_id=a.premise_id,nodes={},links={},native_status='authoring_only',created_at=Util.now_iso(),updated_at=Util.now_iso()}
    table.insert(self.app.model.data.device_logic_graphs,graph);dirty(self);return graph
end
function DeviceLogic:add_node(a)
    a=a or {};local g=self:get(a.graph_id);if not g then return nil,'device logic graph not found' end
    if not node_kinds[a.kind] then return nil,'unsupported node kind' end
    local name=clean(a.name or a.kind,128);if not name or name=='' then return nil,'node name is required' end
    local cfg=type(a.config)=='table' and Util.deepcopy(a.config) or {}
    if a.kind=='fact' and not valid_fact(cfg.fact_name) then return nil,'fact nodes require a valid fact_name' end
    if a.kind=='action' and not actions[cfg.operation] then return nil,'action nodes require a supported operation' end
    if cfg.operation=='set_fact' and not valid_fact(cfg.fact_name) then return nil,'set_fact action requires a valid fact_name' end
    if cfg.fact_name~=nil and cfg.fact_name~='' and not valid_fact(cfg.fact_name) then return nil,'fact_name is invalid' end
    if cfg.value~=nil and not valid_int(cfg.value) then return nil,'fact value must be a 32-bit integer' end
    if cfg.floor~=nil and (tonumber(cfg.floor)==nil or tonumber(cfg.floor)<0 or tonumber(cfg.floor)>100) then return nil,'floor must be from 0 to 100' end
    if a.object_id and not self.app.model:get_object(a.object_id) then return nil,'bound object_id does not exist' end
    self.app.model:snapshot('Add device logic node');local n={id=Util.make_id('logicnode'),name=name,kind=a.kind,object_id=a.object_id,config=cfg,native=type(a.native)=='table' and Util.deepcopy(a.native) or {},created_at=Util.now_iso()}
    table.insert(g.nodes,n);g.updated_at=Util.now_iso();dirty(self);return n
end
function DeviceLogic:update_node(a)
    a=a or {};local g=self:get(a.graph_id);local n=g and find(g.nodes,a.node_id);if not n then return nil,'device logic node not found' end
    local p=a.patch or {};local kind=p.kind or n.kind;if not node_kinds[kind] then return nil,'unsupported node kind' end
    local name=p.name~=nil and clean(p.name,128) or n.name;if not name or name=='' then return nil,'node name is required' end
    local cfg=p.config~=nil and (type(p.config)=='table' and Util.deepcopy(p.config) or nil) or n.config;if not cfg then return nil,'config must be an object' end
    if kind=='fact' and not valid_fact(cfg.fact_name) then return nil,'fact nodes require a valid fact_name' end
    if kind=='action' and not actions[cfg.operation] then return nil,'action nodes require a supported operation' end
    if cfg.operation=='set_fact' and not valid_fact(cfg.fact_name) then return nil,'set_fact action requires a valid fact_name' end
    if cfg.value~=nil and not valid_int(cfg.value) then return nil,'fact value must be a 32-bit integer' end
    if p.object_id and p.object_id~='' and not self.app.model:get_object(p.object_id) then return nil,'bound object_id does not exist' end
    if p.native~=nil and type(p.native)~='table' then return nil,'native binding must be an object' end
    self.app.model:snapshot('Update device logic node');n.name=name;n.kind=kind;n.config=cfg
    if p.object_id~=nil then n.object_id=p.object_id~='' and p.object_id or nil end;if p.native~=nil then n.native=Util.deepcopy(p.native) end
    g.updated_at=Util.now_iso();dirty(self);return n
end
function DeviceLogic:delete_node(graph_id,node_id)
    local g=self:get(graph_id);if not g then return nil,'device logic graph not found' end
    for i,n in ipairs(g.nodes) do if n.id==node_id then
        self.app.model:snapshot('Delete device logic node');table.remove(g.nodes,i);local kept,removed={},0
        for _,link in ipairs(g.links) do if link.from_id==node_id or link.to_id==node_id then removed=removed+1 else kept[#kept+1]=link end end
        g.links=kept;g.updated_at=Util.now_iso();dirty(self);return {deleted=true,removed_links=removed}
    end end
    return nil,'device logic node not found'
end
function DeviceLogic:add_link(a)
    a=a or {};local g=self:get(a.graph_id);if not g then return nil,'device logic graph not found' end
    local from,to=find(g.nodes,a.from_id),find(g.nodes,a.to_id);if not from or not to then return nil,'link endpoints must reference nodes in this graph' end
    if from.id==to.id then return nil,'a logic node cannot link to itself' end
    local trigger=clean(a.trigger or 'activate',64);if not trigger or trigger=='' then return nil,'trigger is required' end
    local fact=a.condition_fact or '';if fact~='' and not valid_fact(fact) then return nil,'condition_fact is invalid' end
    local condition_value=a.condition_value==nil and 1 or a.condition_value;if not valid_int(condition_value) then return nil,'condition_value must be a 32-bit integer' end
    for _,link in ipairs(g.links) do if link.from_id==from.id and link.to_id==to.id and link.trigger==trigger then return link,'link already exists' end end
    self.app.model:snapshot('Add device logic link');local link={id=Util.make_id('logiclink'),from_id=from.id,to_id=to.id,trigger=trigger,condition_fact=fact,condition_value=tonumber(condition_value),enabled=a.enabled~=false,order=#g.links+1,native_operation=clean(a.native_operation or '',128) or ''}
    table.insert(g.links,link);g.updated_at=Util.now_iso();dirty(self);return link
end
function DeviceLogic:delete_link(graph_id,link_id)
    local g=self:get(graph_id);if not g then return nil,'device logic graph not found' end
    for i,l in ipairs(g.links) do if l.id==link_id then self.app.model:snapshot('Delete device logic link');table.remove(g.links,i);for j,v in ipairs(g.links) do v.order=j end;g.updated_at=Util.now_iso();dirty(self);return {deleted=true} end end
    return nil,'device logic link not found'
end
function DeviceLogic:delete_graph(graph_id)
    for i,g in ipairs(self:list()) do if g.id==graph_id then self.app.model:snapshot('Delete device logic graph');table.remove(self.app.model.data.device_logic_graphs,i);dirty(self);return {deleted=true} end end
    return nil,'device logic graph not found'
end
function DeviceLogic:validate(graph_id)
    local graphs=graph_id and {self:get(graph_id)} or self:list();if graph_id and not graphs[1] then return nil,'device logic graph not found' end
    local report={graphs={},native_resources='not_generated_by_graph_editor'}
    for _,g in ipairs(graphs) do
        local ids,errors,warnings={}, {},{}
        for _,n in ipairs(g.nodes) do ids[n.id]=n
            local label=tostring(n.name or n.id or 'unnamed node');local cfg=type(n.config)=='table' and n.config or {}
            if n.kind=='fact' and not valid_fact(cfg.fact_name) then errors[#errors+1]='Fact node '..label..' has an invalid fact name' end
            if n.kind=='action' and not actions[cfg.operation] then errors[#errors+1]='Action node '..label..' has an unsupported operation' end
            if n.kind~='fact' and n.kind~='action' then
                if not n.object_id then warnings[#warnings+1]=label..' is not bound to a saved placed object' end
                if not (n.native and n.native.device_hash) then warnings[#warnings+1]=label..' has no World Builder device hash' end
                if not (n.native and n.native.ps_entry_hash and n.native.instance_data_ref) then warnings[#warnings+1]=label..' is missing a persistent-state/instance-data binding' end
                if not (n.native and n.native.node_ref) then warnings[#warnings+1]=label..' has no sector world nodeRef binding' end
            end
        end
        for _,l in ipairs(g.links) do if not ids[l.from_id] or not ids[l.to_id] then errors[#errors+1]='Link '..tostring(l.id or '?')..' has a missing endpoint' end;if l.condition_fact and l.condition_fact~='' and not valid_fact(l.condition_fact) then errors[#errors+1]='Link '..tostring(l.id or '?')..' has an invalid condition fact' end end
        report.graphs[#report.graphs+1]={id=g.id,name=g.name,node_count=#g.nodes,link_count=#g.links,errors=errors,warnings=warnings,status=#errors>0 and 'invalid' or (#warnings>0 and 'needs_native_resources' or 'authoring_graph_valid'),native_runtime_execution=false}
    end
    return report
end
return DeviceLogic
