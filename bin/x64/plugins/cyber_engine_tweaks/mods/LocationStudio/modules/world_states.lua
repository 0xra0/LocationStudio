local Util=require('modules/util')
local WorldStates={};WorldStates.__index=WorldStates
local FACT='^[%w_%.%-]+$'
local OPS={['==']=true,['~=']=true,['>']=true,['>=']=true,['<']=true,['<=']=true}

function WorldStates.new(app) return setmetatable({app=app,auto_enabled=false,last_poll=0,last_signature=nil,last_report=nil},WorldStates) end
local function valid_int(v) v=tonumber(v);return v and v==v and v%1==0 and v>=-2147483648 and v<=2147483647 end
local function find_member(variant,id)
    for _,m in ipairs(variant.members or {}) do if m.kind=='object' and m.item_id==id then return m end end
end

function WorldStates:list() return Util.deepcopy(self.app.model.data.world_state_variants or {}) end

local function member_elsewhere(variants,variant_id,object_id)
    for _,variant in ipairs(variants or {}) do if variant.id~=variant_id then for _,member in ipairs(variant.members or {}) do if member.kind=='object' and member.item_id==object_id then return true end end end end
    return false
end

function WorldStates:_restore_baseline(object_id,baseline)
    local object=self.app.model:get_object(object_id);if not object then return true end
    baseline=baseline or {enabled=true,visible=true,tracked=false}
    local old_enabled,old_visible=object.enabled,object.visible;local tracked=self.app.placement:is_tracked(object)
    local should_spawn=baseline.enabled~=false and baseline.visible~=false and baseline.tracked==true
    if should_spawn then
        object.enabled=true;object.visible=true
        if not tracked then local id,err=self.app.placement:spawn(object);if not id then object.enabled=old_enabled;object.visible=old_visible;return nil,err end end
        object.enabled=baseline.enabled~=false;object.visible=baseline.visible~=false
    else
        if tracked then local ok,err=self.app.placement:despawn(object);if not ok then object.enabled=old_enabled;object.visible=old_visible;return nil,err end end
        object.enabled=baseline.enabled~=false;object.visible=baseline.visible~=false
    end
    return true
end

function WorldStates:create(args)
    args=args or {};local name=Util.trim(args.name or '')
    if name=='' then return nil,'Variant name is required' end
    if not tostring(args.fact_name or ''):match(FACT) then return nil,'A valid quest fact name is required' end
    if not valid_int(args.value) then return nil,'Fact value must be a signed 32-bit integer' end
    local op=args.operator or '==' ;if not OPS[op] then return nil,'Unsupported comparison operator' end
    for _,v in ipairs(self.app.model.data.world_state_variants or {}) do if string.lower(v.name)==string.lower(name) then return nil,'A world-state variant with this name already exists' end end
    local variant=self.app.model:add_world_state_variant({name=name,premise_id=args.premise_id,priority=tonumber(args.priority) or 0,
        conditions={{fact_name=args.fact_name,operator=op,value=tonumber(args.value)}},members={},description=args.description or ''})
    self.app:mark_dirty();return variant
end

function WorldStates:update(id,patch)
    local variant=self.app.model:get_world_state_variant(id);if not variant then return nil,'World-state variant not found' end
    patch=patch or {};local next_conditions=patch.conditions or variant.conditions
    if type(next_conditions)~='table' or #next_conditions==0 then return nil,'Each variant requires at least one quest-fact condition' end
    for i,c in ipairs(next_conditions) do if type(c)~='table' or not tostring(c.fact_name or ''):match(FACT) or not OPS[c.operator or '=='] or not valid_int(c.value) then return nil,'Invalid fact condition at index '..i end end
    self.app.model:snapshot('Edit world-state variant')
    if patch.name~=nil then if Util.trim(patch.name)=='' then return nil,'Variant name cannot be empty' end;variant.name=Util.trim(patch.name) end
    if patch.priority~=nil then variant.priority=tonumber(patch.priority) or 0 end
    if patch.conditions~=nil then variant.conditions=Util.deepcopy(patch.conditions) end
    if patch.enabled~=nil then variant.enabled=patch.enabled==true end
    if patch.description~=nil then variant.description=tostring(patch.description) end
    variant.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty();self.last_signature=nil;return variant
end

function WorldStates:add_member(variant_id,object_id,visible)
    local variant=self.app.model:get_world_state_variant(variant_id);if not variant then return nil,'World-state variant not found' end
    local object=self.app.model:get_object(object_id);if not object then return nil,'World-state variants currently control placed game objects; object not found' end
    if self.app.placement:is_opening_placeholder(object) then return nil,'Empty door/window opening placeholders cannot be switched as game assets' end
    local old=find_member(variant,object_id);self.app.model:snapshot('Add object to world-state variant')
    if old then old.visible=visible~=false;old.updated_at=Util.now_iso()
    else
        local baseline=nil
        for _,v in ipairs(self.app.model.data.world_state_variants or {}) do local m=find_member(v,object_id);if m and m.baseline then baseline=m.baseline;break end end
        baseline=baseline or {enabled=object.enabled~=false,visible=object.visible~=false,tracked=self.app.placement:is_tracked(object)==true}
        table.insert(variant.members,{kind='object',item_id=object_id,visible=visible~=false,baseline=Util.deepcopy(baseline)})
    end
    variant.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty();self.last_signature=nil
    return {variant_id=variant_id,object_id=object_id,visible=visible~=false,baseline=Util.deepcopy(find_member(variant,object_id).baseline)}
end

function WorldStates:remove_member(variant_id,object_id)
    local variant=self.app.model:get_world_state_variant(variant_id);if not variant then return nil,'World-state variant not found' end
    for i,m in ipairs(variant.members or {}) do if m.kind=='object' and m.item_id==object_id then
        if not member_elsewhere(self.app.model.data.world_state_variants,variant_id,object_id) then local ok,err=self:_restore_baseline(object_id,m.baseline);if not ok then return nil,'Could not restore object baseline: '..tostring(err) end end
        self.app.model:snapshot('Remove object from world-state variant');table.remove(variant.members,i);self.app.model:touch();self.app:mark_dirty();self.last_signature=nil;return {removed=true}
    end end
    return nil,'Object is not a member of this variant'
end

function WorldStates:delete(id)
    local _,idx=self.app.model:get_world_state_variant(id);if not idx then return nil,'World-state variant not found' end
    local variant=self.app.model.data.world_state_variants[idx]
    for _,member in ipairs(variant.members or {}) do if member.kind=='object' and not member_elsewhere(self.app.model.data.world_state_variants,id,member.item_id) then
        local ok,err=self:_restore_baseline(member.item_id,member.baseline);if not ok then return nil,'Could not restore '..tostring(member.item_id)..' baseline: '..tostring(err) end
    end end
    self.app.model:snapshot('Delete world-state variant');table.remove(self.app.model.data.world_state_variants,idx);self.app.model:touch();self.app:mark_dirty();self.last_signature=nil
    return {deleted=true,id=id}
end

function WorldStates:_read_fact(name)
    if type(Game)~='table' or type(Game.GetQuestsSystem)~='function' then return nil,'Quest runtime is unavailable' end
    local ok,system=pcall(Game.GetQuestsSystem);if not ok or not system then return nil,'Quest system is unavailable' end
    local read,value=pcall(function() return system:GetFactStr(name) end)
    if not read then return nil,'Could not read '..name..': '..tostring(value) end
    value=tonumber(value);if not value then return nil,'Quest fact '..name..' did not return a number' end
    return value
end

local function matches(actual,op,wanted)
    if op=='==' then return actual==wanted elseif op=='~=' then return actual~=wanted elseif op=='>' then return actual>wanted elseif op=='>=' then return actual>=wanted elseif op=='<' then return actual<wanted elseif op=='<=' then return actual<=wanted end
end

function WorldStates:preview()
    local variants=self.app.model.data.world_state_variants or {};local active,values={},{}
    for _,variant in ipairs(variants) do if variant.enabled~=false then
        local hit=true
        for _,condition in ipairs(variant.conditions or {}) do
            local value,err=self:_read_fact(condition.fact_name);if value==nil then return nil,err end
            values[condition.fact_name]=value
            if not matches(value,condition.operator or '==',tonumber(condition.value)) then hit=false end
        end
        if hit then active[#active+1]=variant end
    end end
    table.sort(active,function(a,b) if (a.priority or 0)==(b.priority or 0) then return a.id<b.id end return (a.priority or 0)>(b.priority or 0) end)
    local winners,conflicts={},{}
    for _,variant in ipairs(active) do for _,member in ipairs(variant.members or {}) do if member.kind=='object' then
        local old=winners[member.item_id]
        if not old or (variant.priority or 0)>(old.priority or 0) then winners[member.item_id]={visible=member.visible~=false,priority=variant.priority or 0,variant_id=variant.id,variant_name=variant.name,baseline=member.baseline}
        elseif (variant.priority or 0)==(old.priority or 0) and old.visible~=(member.visible~=false) then conflicts[#conflicts+1]={object_id=member.item_id,variants={old.variant_name,variant.name},priority=variant.priority or 0} end
    end end end
    return {active_variants=active,assignments=winners,conflicts=conflicts,facts=values,ready=#conflicts==0,
        note='Conditions use live quest facts. One winning variant per object is chosen by highest priority; equal-priority conflicting rules block apply.'}
end

function WorldStates:apply()
    if self.app.transform_session and self.app.transform_session:is_active() then return nil,'Commit or cancel the active transform session before applying a world state' end
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before applying a world state' end
    if self.app.authoring_plans and self.app.authoring_plans:status().recovery_required then return nil,'Resolve authoring-plan recovery before applying a world state' end
    local plan,err=self:preview();if not plan then return nil,err end
    if #plan.conflicts>0 then return nil,'Conflicting active variants target the same object at equal priority',plan.conflicts end
    local assigned={}
    for _,variant in ipairs(self.app.model.data.world_state_variants or {}) do for _,member in ipairs(variant.members or {}) do
        if member.kind=='object' then assigned[member.item_id]=assigned[member.item_id] or member.baseline or {enabled=true,visible=true,tracked=false} end
    end end
    local changed,spawned,despawned,failed={},0,0,{}
    self.app.model:snapshot('Apply fact-driven world state')
    for object_id,baseline in pairs(assigned) do
        local object=self.app.model:get_object(object_id)
        if object then
            local winner=plan.assignments[object_id]
            local target_enabled,target_visible,target_tracked
            if winner then target_enabled=winner.visible;target_visible=winner.visible;target_tracked=winner.visible
            else target_enabled=baseline.enabled~=false;target_visible=baseline.visible~=false;target_tracked=baseline.tracked==true end
            local was_enabled,was_visible=object.enabled,object.visible
            local should_spawn=target_enabled and target_visible and target_tracked
            local was_tracked=self.app.placement:is_tracked(object)
            local ok,spawn_error=true,nil
            if should_spawn then
                object.enabled=true;object.visible=true
                if not was_tracked then local entity;entity,spawn_error=self.app.placement:spawn(object);ok=entity~=nil end
                if ok then spawned=spawned+(was_tracked and 0 or 1) end
            else
                if was_tracked then local did;ok,spawn_error,did=self.app.placement:despawn(object);if ok and did then despawned=despawned+1 end end
                if ok then object.enabled=target_enabled;object.visible=target_visible end
            end
            if not ok then object.enabled=was_enabled;object.visible=was_visible;failed[#failed+1]={object_id=object_id,error=tostring(spawn_error)}
            elseif was_enabled~=object.enabled or was_visible~=object.visible then changed[#changed+1]=object_id end
        else failed[#failed+1]={object_id=object_id,error='object no longer exists'} end
    end
    if #changed>0 then self.app.model:touch();self.app:mark_dirty() end
    local active_ids={};for _,variant in ipairs(plan.active_variants) do active_ids[#active_ids+1]=variant.id end
    self.last_signature=table.concat(active_ids,'|')..':'..(function() local keys={};for k in pairs(plan.facts) do keys[#keys+1]=k end;table.sort(keys);local out={};for _,k in ipairs(keys) do out[#out+1]=k..'='..plan.facts[k] end;return table.concat(out,',') end)()
    self.last_report={applied=#changed>0 or spawned>0 or despawned>0,active_variants=active_ids,spawned=spawned,despawned=despawned,failed=failed,conflicts=plan.conflicts,facts=plan.facts}
    return self.last_report,#failed>0 and 'World state was partially applied; see failed items.' or nil
end

function WorldStates:set_auto(enabled)
    self.auto_enabled=enabled==true;self.last_signature=nil
    if self.auto_enabled then return self:apply() end
    return {auto_enabled=false,active_variants=self.last_report and self.last_report.active_variants or {}}
end

function WorldStates:update(now)
    if not self.auto_enabled then return end
    if (self.app.transform_session and self.app.transform_session:is_active()) or (self.app.stamp_session and self.app.stamp_session:is_active()) or (self.app.authoring_plans and self.app.authoring_plans:status().recovery_required) then return end
    now=now or os.clock();if now-self.last_poll<0.75 then return end;self.last_poll=now
    local plan=self:preview();if not plan or #plan.conflicts>0 then return end
    local ids={};for _,variant in ipairs(plan.active_variants) do ids[#ids+1]=variant.id end
    local keys={};for key in pairs(plan.facts) do keys[#keys+1]=key end;table.sort(keys);local vals={};for _,key in ipairs(keys) do vals[#vals+1]=key..'='..plan.facts[key] end
    local signature=table.concat(ids,'|')..':'..table.concat(vals,',')
    if signature~=self.last_signature then self:apply() end
end

function WorldStates:status()
    return {auto_enabled=self.auto_enabled==true,last_report=Util.deepcopy(self.last_report),variant_count=#(self.app.model.data.world_state_variants or {}),
        runtime_control='tracked CET/World Builder entities only',native_quest_execution=false}
end
return WorldStates
