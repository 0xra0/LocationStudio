-- Entity IDs are spawn requests, not proof of an entity being loaded. Keep
-- ownership until confirmation/removal, including cancelled asynchronous spawns.
local Runtime={}
Runtime.__index=Runtime

local function find_object(app,id)
    if not app or not app.model or not id then return nil end
    return app.model:get_object(id)
end

function Runtime.new(app,persistent)
    persistent=persistent or {records={},retired={}}
    persistent.records=persistent.records or {};persistent.retired=persistent.retired or {}
    local self=setmetatable({app=app,records=persistent.records,retired=persistent.retired,clock=0,wall_start=os.time(),accumulator=0,timeout=10,max_records=256,last_error=nil},Runtime)
    -- Runtime records survive a LocationStudio code reload, but their model
    -- object references do not. Rebind by authored ID before the next tick.
    for _,record in pairs(self.records) do
        record.object=find_object(app,record.object_id)
        if record.object then
            local entity=self:_find(record)
            if entity then record.state='confirmed' elseif record.state=='confirmed' then record.state='missing' end
            record.object.runtime={spawned=record.state=='confirmed',status=record.state,backend='entity_spawner',entity_id=tostring(record.id),error=record.error}
        end
    end
    for _,record in ipairs(self.retired) do record.object=nil end
    return self
end

function Runtime:adopt(app)
    self.app=app
    for _,record in pairs(self.records) do
        record.object=find_object(app,record.object_id)
        if record.object then
            local entity=self:_find(record)
            if entity then record.state='confirmed' elseif record.state=='confirmed' then record.state='missing' end
            record.object.runtime={spawned=record.state=='confirmed',status=record.state,backend='entity_spawner',entity_id=tostring(record.id),error=record.error}
        end
    end
    return self
end

function Runtime:_log(level,message,fields)
    local logger=self.app.logger
    if logger then logger[level](logger,'runtime:entity',message,fields) end
end

function Runtime:_state(record,state,reason)
    if record.state==state and record.error==reason then return end
    record.state=state;record.error=reason
    if record.object then
        record.object.runtime={spawned=state=='confirmed',status=state,backend='entity_spawner',entity_id=tostring(record.id),error=reason}
    end
    if reason then self.last_error=reason end
    self:_log((state=='failed' or state=='missing') and 'error' or 'info',state,{key=record.key,entity_id=tostring(record.id),template=record.template,error=reason})
end

function Runtime:_find(record)
    if not Game or type(Game.FindEntityByID)~='function' then return nil,'Game.FindEntityByID is unavailable; cannot confirm spawn.' end
    local ok,entity=pcall(Game.FindEntityByID,record.id)
    if not ok then return nil,tostring(entity) end
    return entity
end

function Runtime:_despawn(entity)
    if not exEntitySpawner or type(exEntitySpawner.Despawn)~='function' then return false,'CET exEntitySpawner.Despawn is unavailable' end
    local ok,result=pcall(exEntitySpawner.Despawn,entity)
    if not ok or result==false then return false,ok and 'entity removal was rejected' or tostring(result) end
    return true
end

function Runtime:request(key,template,world,appearance,object)
    if self.records[key] then return nil,'A runtime request already owns '..key..'; remove or refresh it first.' end
    local count=#self.retired;for _ in pairs(self.records) do count=count+1 end
    if count>=self.max_records then return nil,'Runtime tracking limit reached; remove existing objects or reload the game before spawning more.' end
    if not exEntitySpawner or type(exEntitySpawner.Spawn)~='function' then return nil,'CET exEntitySpawner is unavailable' end
    local ok,id=pcall(exEntitySpawner.Spawn,template,world,appearance or '')
    if not ok or not id or id==0 then return nil,ok and 'spawner returned an invalid entity id' or tostring(id) end
    local record={key=key,id=id,template=template,object=object,object_id=object and object.id or nil,started=self.clock}
    self.records[key]=record
    self:_state(record,'pending')
    local entity=self:_find(record)
    if entity then self:_state(record,'confirmed') end
    return id
end

function Runtime:state(key)
    local record=self.records[key]
    if not record then return 'idle' end
    return record.state,record.error
end

function Runtime:remove(key)
    local record=self.records[key];if not record then return true,nil,false end
    local entity,find_error=self:_find(record)
    if find_error then return false,find_error,false end
    if entity then
        local ok,err=self:_despawn(entity);if not ok then self.last_error=err;self:_log('error','remove_failed',{key=key,error=err});return false,err,false end
    elseif record.state=='pending' or record.state=='failed' then
        -- The engine may still finish this request after the user cancels it.
        -- Retain the ID and remove that late entity when it first resolves.
        table.insert(self.retired,record)
    end
    self.records[key]=nil
    self:_state(record,'idle')
    record.object=nil
    self:_log('info',entity and 'removed' or 'cancel_queued',{key=key,entity_id=tostring(record.id)})
    return true,nil,entity~=nil
end

function Runtime:update(delta)
    delta=math.max(0,tonumber(delta) or 0)
    local next_clock=math.max(self.clock+delta,os.time()-self.wall_start)
    self.accumulator=self.accumulator+next_clock-self.clock;self.clock=next_clock
    if self.accumulator<0.1 then return end
    self.accumulator=0
    for _,record in pairs(self.records) do
        local entity,find_error=self:_find(record)
        if record.state=='failed' then
            -- Despawn is asynchronous: the entity keeps resolving for a while after
            -- the request, so wait before asking again instead of every tick.
            if entity and not (record.despawn_at and self.clock-record.despawn_at<5) then
                local ok,err=self:_despawn(entity)
                if ok then self:_log('info','late_failed_spawn_removed',{key=record.key});record.despawn_at=self.clock
                elseif record.cleanup_error~=err then record.cleanup_error=err;self:_log('error','late_cleanup_failed',{key=record.key,error=err}) end
            end
        elseif entity then self:_state(record,'confirmed')
        elseif record.state=='confirmed' then self:_state(record,'missing',find_error or 'Previously confirmed entity no longer resolves in the game.')
        elseif record.state=='pending' and self.clock-record.started>=self.timeout then
            self:_state(record,'failed',find_error or 'Spawn ID did not resolve to an entity within 10 seconds. Check the template and CET log.')
        end
    end
    for index=#self.retired,1,-1 do
        local record=self.retired[index];local entity=self:_find(record)
        if entity then
            local ok,err=self:_despawn(entity)
            if ok then table.remove(self.retired,index);self:_log('info','cancelled_spawn_removed',{key=record.key,entity_id=tostring(record.id)})
            elseif record.cleanup_error~=err then record.cleanup_error=err;self:_log('error','cancel_cleanup_failed',{key=record.key,error=err}) end
        end
    end
end

function Runtime:status()
    local counts={pending=0,confirmed=0,failed=0,missing=0,cleanup_pending=#self.retired,last_error=self.last_error}
    for _,record in pairs(self.records) do counts[record.state]=(counts[record.state] or 0)+1 end
    return counts
end

return Runtime
