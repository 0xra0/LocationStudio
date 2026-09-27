local Util=require('modules/util')
local Simulator={};Simulator.__index=Simulator
local NAME='^[%w_%.%-]+$'

function Simulator.new(app) return setmetatable({app=app,pending=nil,last_state=nil},Simulator) end

local function add(map,name,role,kind,id,label,value)
    name=tostring(name or ''):match('^%s*(.-)%s*$')
    if name=='' or not name:match(NAME) then return end
    local row=map[name] or {name=name,value=nil,writers={},consumers={},references={}}
    map[name]=row;local list=row[role] or row.references;list[#list+1]={kind=kind,id=id,label=label or id,value=tonumber(value)}
end

local function linked_facts(map,item,kind,id)
    for _,fact in ipairs(((item.metadata or {}).questforge_sync or {}).facts or {}) do
        local source=tostring(fact.source or '')
        local role=(source=='npc condition' or source=='encounter activation') and 'consumers' or 'writers'
        add(map,fact.name,role,kind,id,item.name,fact.value)
    end
end

function Simulator:catalog()
    local app=self.app;local facts={}
    for _,volume in ipairs(app.model.data.volumes or {}) do
        local meta=volume.metadata or {};local qf=meta.questforge or {}
        add(facts,qf.fact_name,'writers','volume',volume.id,volume.name,qf.value)
        linked_facts(facts,volume,'volume',volume.id)
    end
    for _,object in ipairs(app.model.data.objects or {}) do
        local meta=object.metadata or {};local cfg=meta.interactable or {}
        add(facts,cfg.fact_name,'writers','interactable',object.id,object.name,cfg.fact_value)
        local pop=meta.npc_population or {}
        add(facts,pop.condition_fact,'consumers','npc',object.id,object.name,pop.condition_value)
        for _,condition in ipairs(pop.conditions or {}) do add(facts,condition.fact_name,'consumers','npc_condition',object.id,object.name,condition.fact_value) end
        linked_facts(facts,object,'object',object.id)
    end
    for _,route in ipairs(app.model.data.npc_routes or {}) do
        for _,field in ipairs({'waypoints','alert_waypoints','combat_waypoints'}) do
            for _,point in ipairs(route[field] or {}) do add(facts,point.branch_fact,'consumers','npc_route',route.id,route.name,point.branch_value) end
        end
    end
    for _,enc in ipairs(app.model.data.combat_encounters or {}) do
        add(facts,enc.activation_fact,'consumers','encounter',enc.id,enc.name,enc.activation_value)
        add(facts,enc.reset_fact,'writers','encounter_reset',enc.id,enc.name,enc.reset_value)
    end
    for _,graph in ipairs(app.model.data.device_logic_graphs or {}) do
        for _,node in ipairs(graph.nodes or {}) do
            local cfg=node.config or {};local role=node.kind=='action' and cfg.operation=='set_fact' and 'writers' or 'references'
            add(facts,cfg.fact_name,role,'device_logic',node.id,graph.name..' / '..(node.name or node.kind),cfg.value)
        end
        for _,link in ipairs(graph.links or {}) do add(facts,link.condition_fact,'consumers','device_logic_link',link.id,graph.name..' / '..(link.trigger or 'link'),link.condition_value) end
    end
    local system=self:_quests_system()
    for name,fact in pairs(facts) do
        if system then
            local ok,value=pcall(function() return system:GetFactStr(name) end)
            if ok and tonumber(value) then fact.value=tonumber(value);fact.read_status='read' else fact.read_status='unavailable' end
        else fact.read_status='game_unavailable' end
    end
    self.last_state=facts
    local out={};for _,fact in pairs(facts) do table.insert(out,fact) end;table.sort(out,function(a,b)return a.name<b.name end)
    return {facts=out,game_api_available=system~=nil,read_only=true,warning='Fact reads are live game state; writes affect the active save and are irreversible through this panel.'}
end

function Simulator:_quests_system()
    if type(Game)~='table' or type(Game.GetQuestsSystem)~='function' then return nil end
    local ok,system=pcall(Game.GetQuestsSystem);if ok then return system end
    return nil
end

function Simulator:inspect(name)
    name=tostring(name or '')
    if not name:match(NAME) then return nil,'Invalid quest fact name' end
    local cached=self.last_state and self.last_state[name]
    if cached then
        local system=self:_quests_system()
        if system then local ok,value=pcall(function() return system:GetFactStr(name) end);if ok and tonumber(value) then cached.value=tonumber(value);cached.read_status='read' end end
        return Util.deepcopy(cached)
    end
    local system=self:_quests_system();if not system then return {name=name,value=nil,read_status='game_unavailable',writers={},consumers={},references={}} end
    local ok,value=pcall(function() return system:GetFactStr(name) end)
    if not ok then return nil,'GetFactStr failed: '..tostring(value) end
    return {name=name,value=tonumber(value),read_status='read',writers={},consumers={},references={}}
end

function Simulator:prepare_write(name,value,source)
    name=tostring(name or '');value=tonumber(value)
    if not name:match(NAME) then return nil,'Invalid quest fact name' end
    if not value or value%1~=0 or value < -2147483648 or value > 2147483647 then return nil,'Fact value must be a signed 32-bit integer' end
    local system=self:_quests_system();if not system then return nil,'Game.GetQuestsSystem() is unavailable; no fact was changed' end
    local current,read_error
    local read_ok,result=pcall(function() return system:GetFactStr(name) end)
    if read_ok then current=tonumber(result) else read_error=tostring(result) end
    local token=Util.make_id('questwrite')
    self.pending={token=token,name=name,value=value,current=current,source=source or 'manual',prepared_at=Util.now_iso()}
    return {token=token,fact_name=name,current_value=current,new_value=value,source=self.pending.source,
        persistent_save_warning='CONFIRMATION REQUIRED: writing this fact changes the active game save, may advance quests or trigger scripts, and cannot be undone by LocationStudio. Use a backup save. '..(read_error and ('Current-value read failed: '..read_error) or '')}
end

function Simulator:prepare_trigger(volume_id)
    local volume=self.app.model:get_volume(volume_id);if not volume then return nil,'Trigger volume not found' end
    local meta=volume.metadata or {};local qf=meta.questforge or {};local name=qf.fact_name;local value=qf.value
    if not name then
        for _,fact in ipairs(((meta.questforge_sync or {}).facts) or {}) do if fact.source=='trigger' then name=fact.name;value=fact.value;break end end
    end
    if not name or tostring(name)=='' then return nil,'This volume has no linked Quest Forge fact to simulate' end
    return self:prepare_write(name,value or 1,'manual trigger simulation: '..tostring(volume.name or volume.id))
end

function Simulator:confirm_write(token)
    local pending=self.pending
    if not pending or tostring(token or '')~=pending.token then return nil,'No matching pending confirmation. Prepare the fact write again.' end
    local system=self:_quests_system();if not system then self.pending=nil;return nil,'Game quest system became unavailable; no fact was changed' end
    local ok,result=pcall(function() return system:SetFactStr(pending.name,pending.value) end)
    if not ok or result==false then self.pending=nil;return nil,'SetFactStr failed: '..tostring(result) end
    self.pending=nil
    local state=self:inspect(pending.name)
    return {written=true,fact_name=pending.name,requested_value=pending.value,current_value=state and state.value,
        source=pending.source,warning='The active save may have changed quest progression. LocationStudio cannot roll this fact back.'}
end

function Simulator:cancel_write(token)
    if not self.pending or (token and token~=self.pending.token) then return nil,'No matching pending fact write' end
    local name=self.pending.name;self.pending=nil;return {cancelled=true,fact_name=name,save_unchanged=true}
end

return Simulator
