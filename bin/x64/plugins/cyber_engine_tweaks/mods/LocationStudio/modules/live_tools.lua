-- Live helpers for quest dressing work: NPC animation auditioning and batched world probes.
-- NPC animations reuse AMM's workspot entities with the same WorkspotSystem calls AMM's Poses
-- tab makes, so AMM's archive must be installed. The animation list itself lives in AMM's
-- sqlite database, which the MCP server reads; CET cannot open another mod's database.
local LiveTools={}
LiveTools.__index=LiveTools

local SPAWN_TIMEOUT=5
local MAX_RAYS=4000

local function num(v,fallback) v=tonumber(v);if v==nil then return fallback end;return v end

local function vec(p) return Vector4.new(num(p.x,0),num(p.y,0),num(p.z,0),1) end

local function key_of(npc) return tostring(npc:GetEntityID().hash) end

local function describe(npc)
    local pos=npc:GetWorldPosition()
    local record=''
    pcall(function() record=TDBID.ToStringDEBUG(npc:GetRecordID()) end)
    return {key=key_of(npc),record=record,position={x=pos.x,y=pos.y,z=pos.z},yaw=npc:GetWorldOrientation():ToEulerAngles().yaw}
end

function LiveTools.new(app)
    return setmetatable({app=app,anims={},clock=0,spawned={},preview_pending={}},LiveTools)
end

-- Every NPC within search metres of V, as {npc,distance-to-position}.
function LiveTools:_npcs_near(position,search)
    local player=Game.GetPlayer();if not player then return nil,'player is not available' end
    local query=Game['TSQ_NPC;']();query.maxDistance=search
    local ok,parts=Game.GetTargetingSystem():GetTargetParts(player,query)
    if not ok then return {} end
    local found,seen={},{}
    for _,part in ipairs(parts) do
        local entity=part:GetComponent(part):GetEntity()
        if entity and entity:IsNPC() then
            local key=key_of(entity)
            if not seen[key] then
                seen[key]=true
                table.insert(found,{npc=entity,distance=Vector4.Distance(entity:GetWorldPosition(),position)})
            end
        end
    end
    table.sort(found,function(a,b) return a.distance<b.distance end)
    return found
end

-- target: 'crosshair' (default) or 'nearest' (to a.position, else V; within a.radius, default 3 m).
-- A key from an earlier result addresses an NPC this module is already animating.
function LiveTools:find_npc(a)
    a=a or {}
    if a.key and a.key~='' then
        local rec=self.anims[a.key];if rec then return rec.npc end
        local spawned=self.spawned[tostring(a.key)]
        if spawned then
            local ok,npc=pcall(Game.FindEntityByID,spawned.id)
            if ok and npc and npc:IsNPC() then return npc end
        end
        local p=Game.GetPlayer();if not p then return nil,'player is not available' end
        local list=self:_npcs_near(p:GetWorldPosition(),num(a.search,60)) or {}
        for _,item in ipairs(list) do if key_of(item.npc)==tostring(a.key) then return item.npc end end
        return nil,'no NPC with key '..tostring(a.key)..' within '..num(a.search,60)..' m of V'
    end
    local player=Game.GetPlayer();if not player then return nil,'player is not available' end
    if (a.target or 'crosshair')=='crosshair' then
        local obj=Game.GetTargetingSystem():GetLookAtObject(player,false,false)
        if obj and obj:IsNPC() then return obj end
        return nil,'no NPC under the crosshair'
    end
    local position=a.position and vec(a.position) or player:GetWorldPosition()
    local radius=num(a.radius,3)
    local list,err=self:_npcs_near(position,num(a.search,60));if not list then return nil,err end
    if list[1] and list[1].distance<=radius then return list[1].npc end
    return nil,string.format('no NPC within %.1f m of %.2f %.2f %.2f',radius,position.x,position.y,position.z)
end

function LiveTools:list_npcs(a)
    a=a or {}
    local player=Game.GetPlayer();if not player then return nil,'player is not available' end
    local position=a.position and vec(a.position) or player:GetWorldPosition()
    local list,err=self:_npcs_near(position,num(a.search,30));if not list then return nil,err end
    local out={}
    for _,item in ipairs(list) do
        local d=describe(item.npc);d.distance=item.distance;d.animating=self.anims[d.key] and self.anims[d.key].anim.name or nil
        table.insert(out,d)
    end
    return {npcs=out}
end

function LiveTools:_release(rec)
    pcall(function() Game.GetWorkspotSystem():StopInDevice(rec.npc) end)
    local device=rec.device or Game.FindEntityByID(rec.device_id)
    if device and exEntitySpawner then pcall(exEntitySpawner.Despawn,device) end
end

-- a.anim = {name, comp, ent} as stored in AMM's workspots table.
function LiveTools:play(a)
    a=a or {}
    local anim=a.anim
    if type(anim)~='table' or not anim.name or not anim.comp or not anim.ent then return nil,'anim {name, comp, ent} is required' end
    if not exEntitySpawner or type(exEntitySpawner.Spawn)~='function' then return nil,'CET exEntitySpawner is unavailable' end
    local npc,err=self:find_npc(a);if not npc then return nil,err end
    local key=key_of(npc)
    if self.anims[key] then self:_release(self.anims[key]);self.anims[key]=nil end
    -- AMM spawns the workspot device on the NPC, turned 180 degrees, so the animation plays in place.
    local transform=npc:GetWorldTransform()
    transform:SetPosition(npc:GetWorldPosition())
    transform:SetOrientationEuler(EulerAngles.new(0,0,npc:GetWorldOrientation():ToEulerAngles().yaw+180))
    local ok,id=pcall(exEntitySpawner.Spawn,anim.ent,transform,'')
    if not ok or not id then return nil,'workspot device spawn failed: '..tostring(id) end
    self.anims[key]={npc=npc,device_id=id,anim=anim,instant=a.instant~=false,state='pending',started=self.clock}
    return {key=key,npc=describe(npc),anim=anim.name,state='pending'}
end

function LiveTools:stop(a)
    a=a or {}
    local key=a.key
    if not key or key=='' then
        local npc,err=self:find_npc(a);if not npc then return nil,err end
        key=key_of(npc)
    end
    local rec=self.anims[key];if not rec then return nil,'this NPC is not playing a LocationStudio animation' end
    self:_release(rec);self.anims[key]=nil
    return {key=key,stopped=rec.anim.name}
end

function LiveTools:stop_all()
    local n=0
    for key,rec in pairs(self.anims) do self:_release(rec);self.anims[key]=nil;n=n+1 end
    return {stopped=n}
end

function LiveTools:status()
    local out={}
    for key,rec in pairs(self.anims) do table.insert(out,{key=key,anim=rec.anim.name,state=rec.state,error=rec.error}) end
    return {animations=out}
end

function LiveTools:update(delta)
    self.clock=self.clock+math.max(0,num(delta,0))
    for _,rec in pairs(self.anims) do
        if rec.state=='pending' then
            local device=Game.FindEntityByID(rec.device_id)
            if device then
                rec.device=device
                local ok,err=pcall(function()
                    local ws=Game.GetWorkspotSystem()
                    ws:PlayInDeviceSimple(device,rec.npc,false,rec.anim.comp,CName.new('LS_WORKSPOT'),nil,0,1,nil)
                    ws:SendJumpToAnimEnt(rec.npc,rec.anim.name,rec.instant)
                end)
                if ok then rec.state='playing' else rec.state='failed';rec.error=tostring(err) end
            elseif self.clock-rec.started>SPAWN_TIMEOUT then
                rec.state='failed';rec.error='workspot device did not spawn within '..SPAWN_TIMEOUT..' s (is AMM\'s archive installed?)'
            end
        end
    end
    for i=#self.preview_pending,1,-1 do
        local pending=self.preview_pending[i]
        local npc=self:find_npc({key=pending.key,search=100})
        if npc then
            local result,err=self:play({key=pending.key,anim=pending.anim,instant=pending.instant})
            table.remove(self.preview_pending,i)
            if not result and self.app.logger then self.app.logger:warn('workspot_preview','failed',{key=pending.key,error=err}) end
        elseif self.clock-pending.started>SPAWN_TIMEOUT then
            table.remove(self.preview_pending,i)
            if self.app.logger then self.app.logger:warn('workspot_preview','spawn_timeout',{key=pending.key}) end
        end
    end
end

-- Spawn a character record as a Codeware dynamic entity, e.g. a stand-in for a quest NPC while
-- auditioning animations. Not persisted in saves. tag (default 'ls_npc') is what despawn deletes.
function LiveTools:spawn_record(a)
    a=a or {}
    if not a.record or a.record=='' then return nil,'record is required, e.g. Character.ashcache_mara' end
    if not DynamicEntitySpec then return nil,'Codeware DynamicEntitySpec is unavailable' end
    local spec=DynamicEntitySpec.new()
    spec.recordID=TweakDBID.new(a.record)
    if a.appearance and a.appearance~='' then spec.appearanceName=a.appearance end
    local pos=a.position or {}
    if not pos.x then local p=Game.GetPlayer():GetWorldPosition();pos={x=p.x,y=p.y,z=p.z} end
    spec.position=vec(pos)
    spec.orientation=EulerAngles.ToQuat(EulerAngles.new(0,0,num(a.yaw,0)))
    spec.persistState=false;spec.persistSpawn=false;spec.alwaysSpawned=true
    local tag=(a.tag and a.tag~='') and a.tag or 'ls_npc'
    spec.tags={tag}
    local id=Game.GetDynamicEntitySystem():CreateEntity(spec)
    if not id then return nil,'CreateEntity returned no id' end
    local key=tostring(id.hash)
    self.spawned[key]={id=id,tag=tag}
    return {record=a.record,tag=tag,key=key,position=pos,yaw=num(a.yaw,0)}
end

-- Spawn a temporary stand-in at the authored location and start its AMM workspot after it loads.
function LiveTools:preview_workspot(a)
    a=a or {}
    if a.location_id and self.app.model then
        local item=self.app.model:get_location(a.location_id)
        if not item or not item.metadata or not item.metadata.workspot then return nil,'NPC workspot not found: '..tostring(a.location_id) end
        local config=item.metadata.workspot;local saved=config.animation or {}
        a.position=a.position or item.transform.position;a.yaw=a.yaw or item.transform.rotation.yaw
        a.record=(a.record and a.record~='') and a.record or config.record
        a.appearance=(a.appearance and a.appearance~='') and a.appearance or config.appearance
        a.anim=a.anim or {name=saved.name,rig=saved.rig,comp=saved.comp,ent=saved.ent}
    end
    if type(a.anim)~='table' or not a.anim.name or not a.anim.comp or not a.anim.ent then return nil,'animation {name, comp, ent} is required' end
    local spawned,err=self:spawn_record({record=a.record,appearance=a.appearance,position=a.position,yaw=a.yaw,tag=a.tag or 'ls_workspot_preview'})
    if not spawned then return nil,err end
    table.insert(self.preview_pending,{key=spawned.key,tag=spawned.tag,anim=a.anim,instant=a.instant~=false,started=self.clock})
    return {state='spawning',key=spawned.key,tag=spawned.tag,position=spawned.position,animation=a.anim.name}
end

-- Collision-only straight-approach hint. It does not query REDengine AI navigation.
function LiveTools:workspot_approach(a)
    a=a or {};local target=a.position
    if a.location_id and self.app.model then
        local item=self.app.model:get_location(a.location_id)
        if not item or not item.metadata or not item.metadata.workspot then return nil,'NPC workspot not found: '..tostring(a.location_id) end
        target=target or item.transform.position
    end
    if type(target)~='table' or target.x==nil or target.y==nil or target.z==nil then return nil,'target position x/y/z is required' end
    local actor,err
    if a.key and a.key~='' then actor,err=self:find_npc({key=a.key,search=100}) else actor,err=self:find_npc({target=a.target or 'crosshair'}) end
    if not actor then return nil,err end
    local p=actor:GetWorldPosition();local dx,dy=target.x-p.x,target.y-p.y;local len=math.sqrt(dx*dx+dy*dy)
    if len<0.05 then return {status='candidate',clear=true,distance=len,method='collision_rays',caveat='Not an REDengine AI navmesh query.'} end
    local ox,oy=-dy/len*0.28,dx/len*0.28;local rays={}
    for _,height in ipairs({0.25,0.9,1.55}) do rays[#rays+1]={from={x=p.x+ox,y=p.y+oy,z=p.z+height},to={x=target.x+ox,y=target.y+oy,z=target.z+height}} end
    local result,rayerr=self:raycast_batch({rays=rays,groups={'Static','Dynamic'}});if not result then return nil,rayerr end
    local blocked=0;for _,hit in ipairs(result.hits) do if hit.hit then blocked=blocked+1 end end
    return {status=blocked==0 and 'candidate' or 'blocked_or_inconclusive',clear=blocked==0,distance=len,blocked_rays=blocked,total_rays=#rays,method='three_collision_rays',caveat='Straight collision check only; it does not query REDengine AI navmesh or prove NPC pathfinding.'}
end

-- Bounded floor-and-clearance grid route estimate. CET does not expose REDengine navmesh queries
-- through this mod; this reports geometric candidates and collision hits, never engine AI verdicts.
function LiveTools:walkability_check(a)
    a=a or {}
    local actor_kind=a.actor=='npc' and 'npc' or 'player'
    local actor,err
    if not a.start then
        if actor_kind=='npc' then actor,err=self:find_npc({key=a.npc_key,target=a.target or 'crosshair',search=100});if not actor then return nil,err end
        else actor=Game.GetPlayer();if not actor then return nil,'player is not available' end end
    end
    local actual=actor and actor:GetWorldPosition() or nil
    local start=a.start or {x=actual.x,y=actual.y,z=actual.z}
    local goal=a.goal
    if type(goal)~='table' or tonumber(goal.x)==nil or tonumber(goal.y)==nil or tonumber(goal.z)==nil then return nil,'goal x/y/z is required' end
    start={x=num(start.x,nil),y=num(start.y,nil),z=num(start.z,nil)}
    goal={x=num(goal.x,nil),y=num(goal.y,nil),z=num(goal.z,nil)}
    if not start.x or not start.y or not start.z then return nil,'start x/y/z is invalid' end
    if a.navigation_graph_id and a.navigation_graph_id~='' then
        if not self.app.navigation then return nil,'imported navigation graph checker is unavailable' end
        return self.app.navigation:query({graph_id=a.navigation_graph_id,start=start,goal=goal,snap_distance=a.snap_distance})
    end
    local step=math.max(0.5,math.min(2,num(a.grid_step,1.0)))
    local margin=math.max(0,math.min(6,num(a.margin,2.0)))
    local radius=math.max(0.2,math.min(0.8,num(a.actor_radius,actor_kind=='npc' and 0.32 or 0.35)))
    local height=math.max(1.2,math.min(2.2,num(a.actor_height,actor_kind=='npc' and 1.75 or 1.8)))
    local low_i=math.floor((math.min(start.x,goal.x)-margin-start.x)/step)
    local high_i=math.ceil((math.max(start.x,goal.x)+margin-start.x)/step)
    local low_j=math.floor((math.min(start.y,goal.y)-margin-start.y)/step)
    local high_j=math.ceil((math.max(start.y,goal.y)+margin-start.y)/step)
    local end_i=math.floor((goal.x-start.x)/step+0.5);local end_j=math.floor((goal.y-start.y)/step+0.5)
    local cell_count=(high_i-low_i+1)*(high_j-low_j+1)
    if cell_count>120 then return {status='inconclusive',reason='sample grid exceeds 120 cells; increase grid_step or reduce margin',cells=cell_count,navmesh_available=false,method='sampled_collision_grid'} end
    local nodes,ordered={},{}
    local dx,dy=goal.x-start.x,goal.y-start.y;local denom=dx*dx+dy*dy
    local function node_key(i,j) return tostring(i)..':'..tostring(j) end
    for i=low_i,high_i do for j=low_j,high_j do
        local x,y=start.x+i*step,start.y+j*step
        local t=denom>0 and ((x-start.x)*dx+(y-start.y)*dy)/denom or 0;t=math.max(0,math.min(1,t))
        local node={i=i,j=j,x=x,y=y,expected_z=start.z+(goal.z-start.z)*t,clear=true}
        nodes[node_key(i,j)]=node;ordered[#ordered+1]=node
    end end
    local start_node=nodes[node_key(0,0)];local goal_node=nodes[node_key(end_i,end_j)]
    if not start_node or not goal_node then return {status='inconclusive',reason='start or goal lies outside sampled grid',navmesh_available=false,method='sampled_collision_grid'} end
    local floor_rays={}
    local z_from=math.max(start.z,goal.z)+3;local z_to=math.min(start.z,goal.z)-3
    for _,node in ipairs(ordered) do floor_rays[#floor_rays+1]={from={x=node.x,y=node.y,z=z_from},to={x=node.x,y=node.y,z=z_to}} end
    local floor_result,floor_err=self:raycast_batch({rays=floor_rays,groups={'Static','Dynamic'}})
    if not floor_result then return nil,floor_err end
    local floor_hits=0
    for index,node in ipairs(ordered) do
        local hit=floor_result.hits[index]
        if hit.hit and math.abs(hit.z-node.expected_z)<=math.max(1.5,step*1.6) then node.floor_z=hit.z;floor_hits=floor_hits+1
        else node.clear=false;node.no_floor=true end
    end
    local clearance_rays,owners={},{}
    for _,node in ipairs(ordered) do
        if node.floor_z then
            node.clear=true
            local offsets={{0,0},{radius,0},{-radius,0},{0,radius},{0,-radius}}
            for _,offset in ipairs(offsets) do
                clearance_rays[#clearance_rays+1]={from={x=node.x+offset[1],y=node.y+offset[2],z=node.floor_z+0.08},to={x=node.x+offset[1],y=node.y+offset[2],z=node.floor_z+height}}
                owners[#owners+1]=node
            end
        end
    end
    local clear_result,clear_err=self:raycast_batch({rays=clearance_rays,groups={'Static','Dynamic'}})
    if not clear_result then return nil,clear_err end
    local blocker_map={};local blocker_count=0
    for index,hit in ipairs(clear_result.hits) do if hit.hit then
        local node=owners[index]
        if not (a.start==nil and node==start_node) then
            node.clear=false;node.blocked=true
            local k=string.format('%.1f:%.1f',hit.x,hit.y)
            if not blocker_map[k] then blocker_map[k]={x=hit.x,y=hit.y,z=hit.z,group=hit.group,grid_x=node.x,grid_y=node.y};blocker_count=blocker_count+1 end
        end
    end end
    -- The occupied live actor is expected at the route origin; still require a floor sample there.
    if a.start==nil and start_node.floor_z then start_node.clear=true end
    local queue={};local head=1;local visited={};local parent={}
    if start_node.clear then visited[node_key(start_node.i,start_node.j)]=true;queue[1]=start_node end
    local offsets={{1,0},{-1,0},{0,1},{0,-1}}
    while head<=#queue and not visited[node_key(goal_node.i,goal_node.j)] do
        local current=queue[head];head=head+1
        for _,offset in ipairs(offsets) do
            local ni,nj=current.i+offset[1],current.j+offset[2];local key=node_key(ni,nj);local next_node=nodes[key]
            if next_node and next_node.clear and not visited[key] and math.abs(next_node.floor_z-current.floor_z)<=0.55 then
                visited[key]=true;parent[key]=current;queue[#queue+1]=next_node
            end
        end
    end
    local goal_key=node_key(goal_node.i,goal_node.j);local reachable=visited[goal_key]==true
    local path={};local length=0
    if reachable then
        local cursor=goal_node;while cursor do table.insert(path,1,{x=cursor.x,y=cursor.y,z=cursor.floor_z});cursor=parent[node_key(cursor.i,cursor.j)] end
        for i=2,#path do local p,q=path[i-1],path[i];local ax,ay,az=q.x-p.x,q.y-p.y,q.z-p.z;length=length+math.sqrt(ax*ax+ay*ay+az*az) end
    end
    local blockers={};for _,hit in pairs(blocker_map) do table.insert(blockers,hit) end
    table.sort(blockers,function(a1,b1) if a1.group~=b1.group then return a1.group=='Dynamic' end;return a1.x<b1.x end)
    while #blockers>24 do table.remove(blockers) end
    local endpoint_ok=start_node.floor_z~=nil and goal_node.floor_z~=nil
    local status=not endpoint_ok and 'inconclusive' or (reachable and 'candidate' or 'no_route_in_sampled_grid')
    return {status=status,geometric_path_candidate=reachable,actor=actor_kind,actor_key=actor and actor_kind=='npc' and key_of(actor) or nil,
        start={x=start.x,y=start.y,z=start.z},goal={x=goal.x,y=goal.y,z=goal.z},grid_step=step,margin=margin,actor_radius=radius,actor_height=height,
        sampled_cells=#ordered,floor_supported_cells=floor_hits,path_cells=#path,path_length=reachable and length or nil,path=path,
        blockers=blockers,blocker_count=blocker_count,navmesh_available=false,navmesh_status='CET integration does not expose an AI navmesh query',
        method='bounded floor and 5-point clearance grid',caveat='Geometric route estimate only. It does not model REDengine navigation links, doors, stairs semantics, NPC schedules, or actor-specific movement.'}
end

function LiveTools:despawn_tag(a)
    a=a or {}
    local tag=(a.tag and a.tag~='') and a.tag or 'ls_npc'
    local des=Game.GetDynamicEntitySystem()
    local ok,ents=pcall(function() return des:GetTagged(tag) end)
    for _,e in ipairs(ok and ents or {}) do
        local key=key_of(e)
        if self.anims[key] then self:_release(self.anims[key]);self.anims[key]=nil end
    end
    des:DeleteTagged(tag)
    for key,item in pairs(self.spawned) do if item.tag==tag then self.spawned[key]=nil end end
    for i=#self.preview_pending,1,-1 do if self.preview_pending[i].tag==tag then table.remove(self.preview_pending,i) end end
    return {deleted=tag}
end

-- rays: {{from={x,y,z},to={x,y,z}},...}; groups: collision groups, nearest hit to 'from' wins.
function LiveTools:raycast_batch(a)
    a=a or {}
    local rays=a.rays or {}
    if #rays>MAX_RAYS then return nil,'at most '..MAX_RAYS..' rays per call' end
    local groups=a.groups or {'Static'}
    local sq=Game.GetSpatialQueriesSystem()
    local out={}
    for i,ray in ipairs(rays) do
        local from,to=vec(ray.from),vec(ray.to)
        local best
        for _,group in ipairs(groups) do
            local ok,hit,res=pcall(function() return sq:SyncRaycastByCollisionGroup(from,to,group,false,false) end)
            if ok and hit then
                local p=res.position
                local d=Vector4.Distance(from,Vector4.new(p.x,p.y,p.z,1))
                if not best or d<best.distance then best={hit=true,x=p.x,y=p.y,z=p.z,distance=d,group=group} end
            end
        end
        out[i]=best or {hit=false}
    end
    return {hits=out}
end

-- Heuristic cover scan: paired horizontal collision rays locate vertical surfaces around
-- the player/explicit center. Returned points are candidates, never native AI cover nodes.
function LiveTools:scan_cover_candidates(a)
    a=a or {};local center=a.center
    if type(center)~='table' then
        local player=Game.GetPlayer();if not player then return nil,'player is not available' end
        local p=player:GetWorldPosition();center={x=p.x,y=p.y,z=p.z}
    end
    local x,y,z=num(center.x,nil),num(center.y,nil),num(center.z,nil)
    if not x or not y or not z then return nil,'center requires finite x/y/z coordinates' end
    local radius=math.max(1,math.min(20,num(a.radius,8)))
    local count=math.max(8,math.min(48,math.floor(num(a.samples,24))))
    local stride=math.max(0.5,math.min(2,num(a.spacing,1.5)))
    local rays,meta={},{}
    for i=0,count-1 do
        local angle=(math.pi*2*i)/count;local dx,dy=math.cos(angle),math.sin(angle)
        local from={x=x+dx*0.15,y=y+dy*0.15,z=z+0.45}
        local to={x=x+dx*(radius+0.25),y=y+dy*(radius+0.25),z=z+0.45}
        rays[#rays+1]={from=from,to=to};meta[#meta+1]={i=i,dx=dx,dy=dy,height='low'}
        local high_from={x=from.x,y=from.y,z=z+1.15};local high_to={x=to.x,y=to.y,z=z+1.15}
        rays[#rays+1]={from=high_from,to=high_to};meta[#meta+1]={i=i,dx=dx,dy=dy,height='high'}
    end
    local response,err=self:raycast_batch({rays=rays,groups={'Static','Dynamic'}});if not response then return nil,err end
    local pairs_by_angle={}
    for index,hit in ipairs(response.hits) do if hit.hit then
        local info=meta[index];local row=pairs_by_angle[info.i] or {dx=info.dx,dy=info.dy};pairs_by_angle[info.i]=row;row[info.height]=hit
    end end
    local candidates={}
    for index=0,count-1 do
        local pair=pairs_by_angle[index]
        if pair and pair.low and pair.high and math.abs(pair.low.distance-pair.high.distance)<=0.65 then
            local low,high=pair.low,pair.high;local hx=(low.x+high.x)*0.5;local hy=(low.y+high.y)*0.5
            local px,py=hx-pair.dx*0.45,hy-pair.dy*0.45
            local angle_fn=math.atan2 or math.atan
            local yaw=math.deg(angle_fn(-pair.dy,-pair.dx))
            local duplicate=false
            for _,old in ipairs(candidates) do local op=old.transform.position;local ddx,ddy=op.x-px,op.y-py;if ddx*ddx+ddy*ddy<stride*stride then duplicate=true;break end end
            if not duplicate then
                candidates[#candidates+1]={name='Cover Candidate '..tostring(#candidates+1),cover_type='crouch',exposure='medium',spacing=stride,
                    transform={position={x=px,y=py,z=z},rotation={roll=0,pitch=0,yaw=yaw}},source='live_collision_scan',confidence=0.7,
                    surface_group=low.group,wall_hit={x=hx,y=hy,z=(low.z+high.z)*0.5},scan_angle_degrees=(360*index/count)}
            end
        end
    end
    return {center={x=x,y=y,z=z},radius=radius,samples=count,candidate_count=#candidates,candidates=candidates,
        method='paired_horizontal_collision_rays',groups={'Static','Dynamic'},navmesh_available=false,
        caveat='Heuristic wall/prop surface candidates from collision rays. It does not query REDengine AI cover/navigation; inspect and adjust candidates in game before export.'}
end

-- Floor under each {x,y}: a Static+Dynamic ray from z_from down to z_to. inside_solid means the ray
-- started inside geometry (hit within 1 mm of its start), so V would land on top of whatever it is.
function LiveTools:floor_probe(a)
    a=a or {}
    local z_from,z_to=num(a.z_from,nil),num(a.z_to,nil)
    if not z_from or not z_to then
        local p=Game.GetPlayer():GetWorldPosition()
        z_from=z_from or p.z+2.4;z_to=z_to or p.z-1.5
    end
    local rays={}
    for i,pt in ipairs(a.points or {}) do rays[i]={from={x=pt.x,y=pt.y,z=z_from},to={x=pt.x,y=pt.y,z=z_to}} end
    local res,err=self:raycast_batch({rays=rays,groups=a.groups or {'Static','Dynamic'}});if not res then return nil,err end
    local out={}
    for i,h in ipairs(res.hits) do
        local pt=a.points[i]
        out[i]={x=pt.x,y=pt.y,floor_z=h.hit and h.z or nil,group=h.group,inside_solid=h.hit and h.distance<0.001 or false}
    end
    return {z_from=z_from,z_to=z_to,points=out}
end

-- Delete Codeware dynamic entities by tag, then optionally call a scriptable system's no-arg method
-- (e.g. a mod's SyncProps) so they come back with their current pose.
function LiveTools:respawn_tagged(a)
    a=a or {}
    local des=Game.GetDynamicEntitySystem()
    for _,tag in ipairs(a.tags or {}) do des:DeleteTagged(tag) end
    local called
    if a.system and a.system~='' then
        local ok,err=pcall(function()
            local sys=Game.GetScriptableSystemsContainer():Get(a.system)
            if not sys then error('no scriptable system '..tostring(a.system)) end
            sys[a.method or 'SyncProps'](sys)
        end)
        if not ok then return nil,tostring(err) end
        called=a.system..'.'..(a.method or 'SyncProps')
    end
    return {deleted=a.tags or {},called=called}
end

-- Fix the FPP camera pitch for a screenshot (pitch) or put the normal limits back (restore=true).
function LiveTools:camera_pitch(a)
    a=a or {}
    local cam=Game.GetPlayer():GetFPPCameraComponent()
    if a.restore then cam.pitchMax=79.999992370605;cam.pitchMin=-79.999992370605
    else local p=num(a.pitch,0);cam.pitchMax=p;cam.pitchMin=p end
    return {pitchMin=cam.pitchMin,pitchMax=cam.pitchMax}
end

return LiveTools
