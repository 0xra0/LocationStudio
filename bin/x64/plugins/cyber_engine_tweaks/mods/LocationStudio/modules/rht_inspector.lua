-- Read-only bridge to RedHotTools' WorldInspector (RED4ext plugin + its CET API).
-- Ports the resolve logic of RedHotTools' own CET world module (support/cet/modules/world)
-- so the MCP server can ask "what is this object and where does it come from" without
-- the RHT overlay: sector path, node index/type/ID, nodeRef, mesh/template/record, entity
-- and community data. Nothing here mutates the world.

local RhtInspector = {}
RhtInspector.__index = RhtInspector

-- RedHotTools' collision-groups.lua, enabled rows only.
local COLLISION_GROUPS = {'Dynamic','Static','Vehicle','Destructible','Collider','Particle','Debris','Terrain',
    'PlayerBlocker','VehicleBlocker','DestructibleCluster','Visibility','Interaction','Shooting','Water',
    'NetworkDevice','FoliageDestructible'}

function RhtInspector.new(app)
    return setmetatable({app=app}, RhtInspector)
end

local function defined(v) return v ~= nil and IsDefined(v) end

-- uint64 hashes arrive as number or cdata depending on the CET build; JSON gets them as strings.
local function id(v)
    if v == nil then return nil end
    local s = tostring(v):gsub('ULL$', ''):gsub('LL$', '')
    if s == '0' or s == '' then return nil end
    return s
end

local function str(v)
    if v == nil then return nil end
    if type(v) == 'userdata' and v.value ~= nil then v = v.value end
    v = tostring(v)
    if v == '' or v == 'None' then return nil end
    return v
end

local function vec(v)
    if not v then return nil end
    return {x=v.x, y=v.y, z=v.z}
end

-- RHT pauses its frustum scan 3 s after the last query (freeze fix), so the
-- first query after a pause wakes it and reads the list from before the pause.
local STALE = 'RHT frustum scan was paused and has just been woken; call again in a second for current nodes.'
local last_frustum_query
local function frustum_woken()
    local now = os.clock()
    local stale = not last_frustum_query or now - last_frustum_query > 2.5
    last_frustum_query = now
    return stale
end

local function dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function path(hash)
    if hash == nil then return nil end
    return str(RedHotTools.GetResourcePath(hash))
end

local function is(obj, class)
    return obj ~= nil and RedHotTools.IsInstanceOf(obj, class)
end

function RhtInspector:systems()
    if type(RedHotTools) ~= 'table' and type(RedHotTools) ~= 'userdata' then
        return nil, 'RedHotTools RED4ext plugin is not loaded (no RedHotTools global in CET)'
    end
    local ok, inspector = pcall(function() return Game.GetWorldInspector() end)
    if not ok or not inspector then return nil, 'RedHotTools WorldInspector system is unavailable' end
    if not inspector:IsReady() then return nil, 'RedHotTools WorldInspector is not ready (load a save first)' end
    return inspector
end

function RhtInspector:status()
    local inspector, err = self:systems()
    local result = {plugin=type(RedHotTools) ~= 'nil', ready=inspector ~= nil, error=err}
    if inspector then
        result.frustum_distance = inspector:GetFrustumDistance()
        result.targeting_distance = inspector:GetTargetingDistance()
    end
    return result
end

-- fillTargetNodeData() of the RHT module, minus UI-only fields.
local function fill_node(inspector, target, data)
    local sector
    if defined(target.nodeInstance) then
        sector = inspector:ResolveSectorDataFromNodeInstance(target.nodeInstance)
    elseif target.nodeID then
        sector = inspector:ResolveSectorDataFromNodeID(target.nodeID)
    end
    if sector and id(sector.sectorHash) then
        data.sectorPath = path(sector.sectorHash)
        data.instanceIndex = sector.instanceIndex
        data.instanceCount = sector.instanceCount
        data.nodeIndex = sector.nodeIndex
        data.nodeCount = sector.nodeCount
        data.nodeType = str(sector.nodeType)
        data.nodeID = id(sector.nodeID)
        data.nodeProxyID = id(sector.proxyID)
        data.nodeParentID = id(sector.parentID)
        data.debugName = str(sector.debugName)
        data.sourcePrefabHash = id(sector.sourcePrefabHash)
        data.interior = sector.interior
    end

    local node = defined(target.nodeDefinition) and target.nodeDefinition or nil
    if node then
        data.nodeType = str(RedHotTools.GetTypeName(node))
        if is(node,'worldMeshNode') or is(node,'worldInstancedMeshNode') or is(node,'worldBendedMeshNode')
        or is(node,'worldFoliageNode') or is(node,'worldPhysicalDestructionNode') then
            data.meshPath = path(node.mesh.hash)
            data.meshAppearance = str(node.meshAppearance)
        end
        if is(node,'worldTerrainMeshNode') then data.meshPath = path(node.meshRef.hash) end
        if is(node,'worldStaticDecalNode') then data.materialPath = path(node.material.hash) end
        if is(node,'worldEffectNode') then data.effectPath = path(node.effect.hash) end
        if is(node,'worldPopulationSpawnerNode') then
            data.recordID = str(node.objectRecordId)
            data.appearanceName = str(node.appearanceName)
        end
        if is(node,'worldEntityNode') then
            data.templatePath = path(node.entityTemplate.hash)
            data.appearanceName = str(node.appearanceName)
        end
        if is(node,'worldDeviceNode') then data.deviceClass = str(node.deviceClassName) end
        if is(node,'worldTriggerAreaNode') then
            data.triggerNotifiers = {}
            for _, notifier in ipairs(node.notifiers) do
                table.insert(data.triggerNotifiers, str(RedHotTools.GetTypeName(notifier)))
            end
        end
        if is(node,'worldStaticOccluderMeshNode') or is(node,'worldInstancedOccluderNode') then
            data.meshPath = path(node.mesh.hash)
        end
        if is(node,'worldAISpotNode') and node.spot and node.spot.resource then
            data.workspotPath = path(node.spot.resource.hash)
        end
        if is(node,'worldCollisionNode') or is(node,'worldInstancedMeshNode') or is(node,'worldInstancedDestructibleMeshNode') then
            data.actorIndex = target.actorIndex
            data.actorCount = target.actorCount
            data.physicsProxyID = target.proxyID
        end
        if is(node,'worldStaticParticleNode') then data.particlePath = path(node.particleSystem.hash) end
    end

    local nodeID = data.nodeID or id(target.nodeID)
    if nodeID then data.nodeRef = str(inspector:ResolveNodeRefFromNodeHash(target.nodeID or sector.nodeID)) end
    if data.nodeProxyID then data.nodeProxyRef = str(inspector:ResolveNodeRefFromNodeHash(sector.proxyID)) end
    if data.nodeParentID then data.nodeParentRef = str(inspector:ResolveNodeRefFromNodeHash(sector.parentID)) end
end

-- fillTargetEntityData() + fillTargetCommunityData(), without inventory/attachments/components.
local function fill_entity(inspector, entity, component, data)
    local entityID = entity:GetEntityID().hash
    data.entityID = id(entityID)
    data.entityType = str(entity:GetClassName())
    local template = RedHotTools.GetEntityTemplatePath(entity)
    data.templatePath = data.templatePath or path(template.hash)
    data.appearanceName = data.appearanceName or str(entity:GetCurrentAppearanceName())
    if entity:IsA('gameObject') then
        local recordID = entity:GetTDBID()
        if recordID and TDBID.IsValid(recordID) then data.recordID = str(recordID) end
    end
    if defined(component) then
        data.componentName = str(component.name)
        data.componentType = str(component:GetClassName())
    end
    local community = inspector:ResolveCommunityEntryDataFromEntityID(entityID)
    if community and id(community.sectorHash) then
        data.communityRegistryPath = path(community.sectorHash)
        data.communityID = id(community.communityID.hash)
        data.communityEntryName = str(community.entryName)
        data.communityEntryPhase = str(community.entryPhase)
    end
    -- Entities spawned by a worldEntityNode share the node's hash; this names their sector.
    if not data.sectorPath then fill_node(inspector, {nodeID=entityID}, data) end
    data.position = data.position or vec(entity:GetWorldPosition())
end

function RhtInspector:describe(inspector, target)
    local data = {distance=target.distance, collision=target.collision, enabled=target.enabled,
        position=vec(target.position)}
    local entity = defined(target.entity) and target.entity or nil
    if defined(target.nodeInstance) or defined(target.nodeDefinition) or id(target.nodeID) then
        fill_node(inspector, target, data)
    end
    if entity then fill_entity(inspector, entity, target.component, data) end
    data.isEntity = entity ~= nil
    data.isNode = data.nodeType ~= nil
    return data
end

local function player_and_camera(distance)
    local player = GetPlayer()
    if not defined(player) then return nil, 'no player' end
    local position, forward = Game.GetTargetingSystem():GetCrosshairData(player)
    return player, {position=position, forward=forward, distance=distance}
end

-- getLookAtTargets() of the RHT module: GamePhysics rays per collision group + the look-at
-- component, plus the StaticBounds hits (nodes without collision, e.g. decals).
function RhtInspector:crosshair(args)
    local inspector, err = self:systems(); if not inspector then return nil, err end
    local distance = tonumber(args.distance) or 50.0
    local player, camera = player_and_camera(distance); if not player then return nil, camera end
    local results, seen = {}, {}
    local function add(target, collision)
        local key = id(target.hash) or tostring(#results + 1)
        if seen[key] then return end
        seen[key] = true
        target.collision = collision
        table.insert(results, self:describe(inspector, target))
    end

    local component = Game.GetTargetingSystem():GetLookAtComponent(player, true, false)
    if defined(component) then
        local entity = component:GetEntity()
        add({hash=RedHotTools.GetObjectHash(entity), entity=entity, component=component,
             distance=dist(camera.position, entity:GetWorldPosition())}, 'LookAt')
    end
    for _, group in ipairs(COLLISION_GROUPS) do
        local filter = physicsQueryFilter.AddGroup(StringToName(group))
        for _, trace in ipairs(inspector:SyncRaycastMultiple(camera.position, camera.forward, distance, filter)) do
            local target = inspector:GetPhysicsTraceObject(trace)
            if target.resolved and not (defined(target.entity) and target.entity:GetEntityID().hash == player:GetEntityID().hash) then
                add(target, group)
            end
        end
    end
    local stale = frustum_woken()
    for _, target in ipairs(inspector:GetStreamedNodesInCrosshair()) do add(target, 'StaticBounds') end

    table.sort(results, function(a, b) return (a.distance or 1e9) < (b.distance or 1e9) end)
    return {count=#results, targets=results, warning=stale and STALE or nil}
end

local function matches(data, term)
    if not term or term == '' then return true end
    term = term:lower()
    for _, field in ipairs({'nodeType','nodeRef','sectorPath','meshPath','materialPath','effectPath','templatePath',
                            'recordID','debugName','entityType','appearanceName','communityRegistryPath'}) do
        local v = data[field]
        if v and tostring(v):lower():find(term, 1, true) then return true end
    end
    return false
end

-- scanTargets() of the RHT module (streamed nodes in the camera frustum), filtered by
-- distance from a center (player by default) and a substring term, plus nearby entities.
function RhtInspector:scan(args)
    local inspector, err = self:systems(); if not inspector then return nil, err end
    local player = GetPlayer(); if not defined(player) then return nil, 'no player' end
    local radius = tonumber(args.radius) or 25.0
    local limit = tonumber(args.limit) or 300
    local c = args.center or vec(player:GetWorldPosition())
    if args.frustum_distance then inspector:SetFrustumDistance(tonumber(args.frustum_distance)) end

    local results, seen, total = {}, {}, 0
    local function consider(target, source)
        local pos = target.position
        if pos and dist(c, pos) > radius then return end
        local data = self:describe(inspector, target)
        local key = data.nodeID or data.entityID
        if key then if seen[key] then return end; seen[key] = true end
        if not matches(data, args.term) then return end
        total = total + 1
        data.source = source
        data.centerDistance = data.position and dist(c, data.position) or nil
        table.insert(results, data)
    end

    local stale = frustum_woken()
    for _, target in ipairs(inspector:GetStreamedNodesInFrustum()) do consider(target, 'frustum') end
    if args.entities ~= false then
        local ok, e = pcall(function()
            local query = TSQ_ALL()
            query.maxDistance = radius
            query.testedSet = TargetingSet.Complete
            query.ignoreInstigator = true
            local found, parts = Game.GetTargetingSystem():GetTargetParts(player, query)
            if not found then return end
            for _, part in ipairs(parts) do
                local component = part:GetComponent()
                local entity = defined(component) and component:GetEntity() or nil
                if defined(entity) then
                    consider({entity=entity, component=component, position=entity:GetWorldPosition()}, 'entity')
                end
            end
        end)
        if not ok then self.app.logger:warn('rht:scan', 'entity query failed', {error=tostring(e)}) end
    end

    table.sort(results, function(a, b) return (a.centerDistance or 1e9) < (b.centerDistance or 1e9) end)
    local truncated = #results > limit
    while #results > limit do table.remove(results) end
    return {center=c, radius=radius, term=args.term, total=total, truncated=truncated, targets=results,
            warning=stale and STALE or nil,
            note='Frustum scan: only nodes the camera can see are streamed into the scan; turn to cover the room.'}
end

function RhtInspector:node(args)
    local inspector, err = self:systems(); if not inspector then return nil, err end
    local nodeID = args.node_id and (tonumber(args.node_id) or args.node_id)
    if not nodeID and args.node_ref then nodeID = inspector:ComputeNodeRefHash(args.node_ref) end
    if not nodeID then return nil, 'node_id or node_ref is required' end
    local target = inspector:FindStreamedNode(nodeID)
    if not target.resolved then target = {nodeID=nodeID} end
    local data = self:describe(inspector, target)
    data.streamed = target.resolved == true
    return data
end

-- Return the opaque streamed-node target needed by the one verified mutation
-- exposed by RedHotTools. This is intentionally not exported as arbitrary Lua.
function RhtInspector:removal_target(args)
    local inspector, err = self:systems(); if not inspector then return nil, err end
    local nodeID = args and args.node_id and (tonumber(args.node_id) or args.node_id)
    if not nodeID then return nil, 'node_id is required' end
    local ok, target = pcall(inspector.FindStreamedNode, inspector, nodeID)
    if not ok or not target or target.resolved ~= true or not defined(target.nodeInstance) then
        return nil, 'streamed node is not currently resolved; turn toward it or rescan after it streams' end
    local data = self:describe(inspector, target)
    data.node_id=data.nodeID or id(nodeID)
    data.node_ref=data.nodeRef
    data.node_type=data.nodeType
    data.node_parent_id=data.nodeParentID
    data.sector_path=data.sectorPath
    data.mesh_path=data.meshPath
    data.material_path=data.materialPath
    data.template_path=data.templatePath
    data.is_node=data.isNode
    data.is_entity=data.isEntity
    data.is_visible_node=data.isVisibleNode ~= false and (data.meshPath ~= nil or data.materialPath ~= nil or data.templatePath ~= nil or data.effectPath ~= nil)
    target.is_visible_node=data.is_visible_node
    return data, target
end

function RhtInspector:toggle_node(target)
    local inspector, err = self:systems(); if not inspector then return false, err end
    if type(target) ~= 'table' or not defined(target.nodeInstance) then return false, 'target has no live streamed node instance' end
    local ok, call_err = pcall(inspector.ToggleNodeVisibility, inspector, target.nodeInstance)
    if not ok then return false, tostring(call_err) end
    return true
end

return RhtInspector
