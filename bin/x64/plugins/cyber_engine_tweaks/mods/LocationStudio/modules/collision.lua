local Util=require('modules/util')

-- Collision authoring. Creates World Builder `worldCollisionNode` objects:
-- box/capsule/sphere primitives (Collision Shape) and imported collision
-- meshes (Collision Mesh) from WB's loaded catalog. Presets are the physics
-- collision layers; each preset's group list is World Builder's own hint
-- table. Passability is an authored-geometry estimate, optionally
-- cross-checked with the live collision-ray walkability scan.
local Collision={};Collision.__index=Collision

-- Copied from World Builder's modules/classes/spawn/collision/colliderBase.lua
-- (CP77_entSpawner). WB stores `preset`/`material` as 0-based indices into
-- these lists (materials sorted), so the order must match WB exactly.
local ORIGINAL_MATERIALS={
    'meatbag.physmat','linoleum.physmat','trash.physmat','plastic.physmat','character_armor.physmat','furniture_upholstery.physmat',
    'metal_transparent.physmat','tire_car.physmat','meat.physmat','metal_car_pipe_steam.physmat','character_flesh.physmat','brick.physmat',
    'character_flesh_head.physmat','leaves.physmat','flesh.physmat','water.physmat','plastic_road.physmat','metal_hollow.physmat',
    'cyberware_flesh.physmat','plaster.physmat','plexiglass.physmat','character_vr.physmat','vehicle_chassis.physmat','sand.physmat',
    'glass_electronics.physmat','leaves_stealth.physmat','tarmac.physmat','metal_car.physmat','tiles.physmat','glass_car.physmat',
    'grass.physmat','concrete.physmat','carpet_techpiercable.physmat','wood_hedge.physmat','stone.physmat','leaves_semitransparent.physmat',
    'metal_catwalk.physmat','upholstery_car.physmat','cyberware_metal.physmat','paper.physmat','leather.physmat','metal_pipe_steam.physmat',
    'metal_pipe_water.physmat','metal_semitransparent.physmat','neon.physmat','glass_dst.physmat','plastic_car.physmat','mud.physmat',
    'dirt.physmat','metal_car_pipe_water.physmat','furniture_leather.physmat','asphalt.physmat','wood_bamboo_poles.physmat','glass_opaque.physmat',
    'carpet.physmat','food.physmat','cyberware_metal_head.physmat','metal_road.physmat','wood_tree.physmat','wood_player_npc_semitransparent.physmat',
    'wood.physmat','metal_car_ricochet.physmat','cardboard.physmat','wood_crown.physmat','metal_ricochet.physmat','plastic_electronics.physmat',
    'glass_semitransparent.physmat','metal_painted.physmat','rubber.physmat','ceramic.physmat','glass_bulletproof.physmat','metal_car_electronics.physmat',
    'trash_bag.physmat','character_cyberflesh.physmat','metal_heavypiercable.physmat','metal.physmat','plastic_car_electronics.physmat','oil_spill.physmat',
    'fabrics.physmat','glass.physmat','metal_techpiercable.physmat','concrete_water_puddles.physmat','character_metal.physmat',
}
local PRESETS={
    'World Dynamic','Player Collision','Player Hitbox','NPC Collision',
    'NPC Trace Obstacle','NPC Hitbox','Big NPC Collision','Player Blocker',
    'Block Player and Vehicles','Vehicle Blocker','Block PhotoMode Camera','Ragdoll',
    'Ragdoll Inner','RagdollVehicle','Terrain','Sight Blocker',
    'Moving Kinematic','Interaction Object','Particle','Destructible',
    'Debris','Debris Cluster','Foliage Debris','ItemDrop',
    'Shooting','Moving Platform','Water','Window',
    'Device transparent','Device solid visible','Vehicle Device','Environment transparent',
    'Bullet logic','World Static','Simple Environment Collision','Complex Environment Collision',
    'Foliage Trunk','Foliage Trunk Destructible','Foliage Low Trunk','Foliage Crown',
    'Vehicle Part','Vehicle Proxy','Vehicle Part Query Only Exception','Vehicle Chassis',
    'Chassis Bottom','Chassis Bottom Traffic','Vehicle Chassis Traffic','AV Chassis',
    'Tank Chassis','Vehicle Chassis LOD3','Vehicle Chassis Traffic LOD3','Tank Chassis LOD3',
    'Drone','Prop Interaction','Nameplate','Road Barrier Simple Collision',
    'Road Barrier Complex Collision','Lootable Corpse','Spider Tank',
}
local PRESET_HINTS={
    'Dynamic + Visibility + PhotoModeCamera + VehicleBlocker + TankBlocker + Shooting','Visibility',
    'Player + Shooting','AI + PhotoModeCamera + NPCCollision',
    'NPCTraceObstacle','AI',
    'AI + PhotoModeCamera + VehicleBlocker + TankBlocker + NPCCollision','PlayerBlocker',
    'PlayerBlocker + VehicleBlocker + TankBlocker','VehicleBlocker + TankBlocker',
    'PhotoModeCamera','Ragdoll + Shooting',
    'Ragdoll Inner','Ragdoll + Shooting',
    'Terrain + Visibility + Shooting + PhotoModeCamera + VehicleBlocker + TankBlocker + PlayerBlocker','Visibility',
    'Dynamic + PhotoModeCamera + Visibility + VehicleBlocker + TankBlocker + PlayerBlocker','Interaction',
    'Particle','Destructible + PhotoModeCamera + Visibility + PlayerBlocker',
    'Debris + Visibility','Destructible + PhotoModeCamera + Visibility + PlayerBlocker',
    'Debris + Visibility','Interaction',
    'Shooting','Visibility + Dynamic + Shooting + PhotoModeCamera + NPCBlocker + VehicleBlocker + TankBlocker + PlayerBlocker',
    'Water','Collider + Visibility',
    'Dynamic + Collider + Interaction + PhotoModeCamera + PlayerBlocker + VehicleBlocker + TankBlocker + Visibility','Dynamic + Collider + VehicleBlocker + TankBlocker + Visibility + Interaction + PhotoModeCamera + PlayerBlocker + NPCBlocker',
    'Dynamic + Collider + Visibility + Interaction + PhotoModeCamera + PlayerBlocker','Collider + PlayerBlocker + VehicleBlocker + TankBlocker',
    'Player + AI + Dynamic + Destructible + Terrain + Collider + Particle + Ragdoll + Debris + Shooting','Static + Visibility + Shooting + VehicleBlocker + PhotoModeCamera + VehicleBlocker + TankBlocker + PlayerBlocker',
    'Static + VehicleBlocker + TankBlocker + PlayerBlocker + NPCBlocker + PhotoModeCamera','Shooting + Visibility',
    'Shooting + PlayerBlocker + VehicleBlocker + Visibility + PhotoModeCamera','Shooting + PlayerBlocker + VehicleBlocker + Visibility + PhotoModeCamera + FoliageDestructible',
    'Shooting + PlayerBlocker + Visibility + PhotoModeCamera','Visibility',
    'Vehicle + Visibility + Shooting + PhotoModeCamera + Interaction','Visibility + Shooting + PhotoModeCamera',
    'PlayerBlocker + Shooting + Visibility + Interaction','Vehicle + Interaction',
    'Vehicle','Vehicle',
    'Vehicle + Interaction','Vehicle + Interaction',
    'Vehicle + Tank + Interaction','Vehicle + Interaction + Shooting',
    'Vehicle + Interaction + Shooting','Vehicle + Tank + Interaction + Shooting',
    'PlayerBlocker + Visibility + Shooting','Interaction + Visibility',
    'NPCNameplate + Cloth','PlayerBlocker + VehicleBlocker + TankBlocker',
    'Dynamic + Visibility + Shooting + PhotoModeCamera','Visibility + Interaction + PhotoModeCamera + Shooting',
    'Tank + PlayerBlocker + VehicleBlocker + TankBlocker + Visibility + Shooting',
}

local MATERIALS=Util.deepcopy(ORIGINAL_MATERIALS);table.sort(MATERIALS,function(a,b) return a<b end)
local DEFAULT_PRESET=33 -- 'World Static', World Builder's collider default
local SHAPES={box=0,capsule=1,sphere=2}
local SHAPE_NAMES={[0]='box',[1]='capsule',[2]='sphere'}
local MAX_CELLS=6400

local function split_groups(hint)
    local out,seen={},{}
    for raw in tostring(hint or ''):gmatch('[^+]+') do
        local group=Util.trim(raw);if group~='' and not seen[group] then seen[group]=true;out[#out+1]=group end
    end
    return out
end
local PRESET_GROUPS={};for i=1,#PRESETS do PRESET_GROUPS[i]=split_groups(PRESET_HINTS[i]) end

-- Physics groups that stop an actor capsule in this estimate. The player and
-- NPC controllers collide with static/terrain/dynamic geometry and with their
-- own blocker groups. Callers can pass blocking_groups to test other rules.
local ACTORS={
    player={radius=0.35,height=1.8,step=0.35,blocking_groups={'Static','Terrain','Dynamic','Destructible','PlayerBlocker'}},
    npc={radius=0.4,height=1.9,step=0.35,blocking_groups={'Static','Terrain','Dynamic','Destructible','NPCBlocker','NPCTraceObstacle'}},
}

local function preset_index(value)
    if value==nil or value=='' then return DEFAULT_PRESET end
    local n=tonumber(value);if n and n>=0 and n<#PRESETS and n==math.floor(n) then return n end
    local wanted=string.lower(tostring(value))
    for i,name in ipairs(PRESETS) do if string.lower(name)==wanted then return i-1 end end
    return nil
end

local function material_index(value)
    if value==nil or value=='' then return nil end
    local wanted=string.lower(tostring(value));if not wanted:find('%.physmat$') then wanted=wanted..'.physmat' end
    for i,name in ipairs(MATERIALS) do if name==wanted then return i-1 end end
    return false
end

local function blocks(groups,blocking)
    for _,g in ipairs(groups or {}) do for _,b in ipairs(blocking) do if g==b then return true end end end
    return false
end

local function positive(value,fallback,low,high)
    local n=tonumber(value);if n==nil then n=fallback end
    if n==nil or n<low or n>high then return nil end
    return n
end

function Collision.new(app)
    return setmetatable({app=app,last_error=nil,last_passability=nil},Collision)
end

function Collision:presets()
    local out={}
    for i,name in ipairs(PRESETS) do
        out[#out+1]={index=i-1,name=name,groups=Util.deepcopy(PRESET_GROUPS[i]),
            blocks_player=blocks(PRESET_GROUPS[i],ACTORS.player.blocking_groups),blocks_npc=blocks(PRESET_GROUPS[i],ACTORS.npc.blocking_groups)}
    end
    return out
end
function Collision:materials() return Util.deepcopy(MATERIALS) end
function Collision:actor_profiles() return Util.deepcopy(ACTORS) end

function Collision:_blocked()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

-- Collision records --------------------------------------------------------------

local function wb_of(object) return object and object.metadata and object.metadata.world_builder end
function Collision:is_collision(object)
    local wb=wb_of(object);return wb~=nil and (wb.definition_key=='collision_shape' or wb.definition_key=='collision_mesh')
end

-- Primitive dimensions -> WB collider scale (box half extents; capsule r,r,h; sphere r).
local function primitive_scale(shape,args,base)
    base=base or {}
    if shape==0 then
        local size=type(args.size)=='table' and args.size or nil
        local out={}
        for _,axis in ipairs({'x','y','z'}) do
            local full=size and size[axis];local n=full~=nil and tonumber(full) and tonumber(full)/2 or (base[axis])
            n=positive(n,nil,0.01,500);if not n then return nil,'box size.'..axis..' must be between 0.02 and 1000 m' end
            out[axis]=n
        end
        return out
    elseif shape==1 then
        local r=positive(args.radius,base.x,0.01,100);if not r then return nil,'capsule radius must be between 0.01 and 100 m' end
        local h=positive(args.height,base.z,0.01,500);if not h then return nil,'capsule height must be between 0.01 and 500 m' end
        return {x=r,y=r,z=h}
    end
    local r=positive(args.radius,base.x,0.01,250);if not r then return nil,'sphere radius must be between 0.01 and 250 m' end
    return {x=r,y=r,z=r}
end

local function describe_scale(shape,scale)
    if shape==0 then return {size={x=scale.x*2,y=scale.y*2,z=scale.z*2}} end
    if shape==1 then return {radius=scale.x,height=scale.z} end
    return {radius=scale.x}
end

function Collision:_transform(args)
    if type(args.transform)=='table' and type(args.transform.position)=='table' then
        local t=Util.deepcopy(args.transform);t.rotation=t.rotation or {}
        for _,axis in ipairs({'roll','pitch','yaw'}) do if args[axis]~=nil then t.rotation[axis]=tonumber(args[axis]) or 0 end;t.rotation[axis]=tonumber(t.rotation[axis]) or 0 end
        return t,'explicit'
    end
    local position,source
    if args.source=='player' then local t,err=self.app.game:capture_transform();if not t then return nil,err end;position=t.position;source='player'
    else local hit,err=self.app.game:aim_point(args.distance or 10);if not hit then return nil,err end;position=hit.position;source=hit.source or 'aim' end
    return {position={x=position.x,y=position.y,z=position.z,w=1},rotation={roll=tonumber(args.roll) or 0,pitch=tonumber(args.pitch) or 0,yaw=tonumber(args.yaw) or 0}},source
end

function Collision:_layer_fields(args,base)
    base=base or {}
    local preset=preset_index(args.preset~=nil and args.preset or base.preset)
    if preset==nil then return nil,'unknown collision preset: '..tostring(args.preset)..' (see collision_presets)' end
    local material=base.material
    if args.material~=nil and args.material~='' then
        material=material_index(args.material);if material==false then return nil,'unknown physics material: '..tostring(args.material) end
    end
    return {preset=preset,material=material}
end

local function collision_meta(kind,preset,material)
    return {kind=kind,preset=PRESETS[preset+1],preset_index=preset,groups=Util.deepcopy(PRESET_GROUPS[preset+1]),
        material=material and MATERIALS[material+1] or nil,material_index=material}
end

function Collision:_save_and_spawn(object,args,result)
    self.app.selection:set('object',object.id);self.app:mark_dirty()
    result.object=object;result.spawned=false
    if args.spawn~=false then
        local id,err=self.app.placement:spawn(object)
        if id then result.spawned=true else self.last_error=tostring(err);result.spawn_error=tostring(err) end
    end
    return result
end

function Collision:create_primitive(args)
    args=args or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local shape=SHAPES[args.shape or 'box'];if shape==nil then return nil,'shape must be box, capsule or sphere' end
    local defaults={x=0.5,y=0.5,z=0.5};if shape==1 then defaults={x=0.4,y=0.4,z=1.8} end
    local scale,err=primitive_scale(shape,args,defaults);if not scale then return nil,err end
    local layer;layer,err=self:_layer_fields(args);if not layer then return nil,err end
    local transform,source=self:_transform(args);if not transform then return nil,source end
    local name=Util.trim(args.name or '')~='' and Util.trim(args.name) or ('Collision '..SHAPE_NAMES[shape])
    local data={shape=shape,scale=Util.deepcopy(scale),preset=layer.preset,material=layer.material,previewed=args.visualize~=false,modulePath='collision/collider',dataType='Collision Shape'}
    self.app.model:snapshot()
    local object=self.app.model:add_object({premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id or self.app.selected_room_id,
        name=name,kind='collision',template='',layer='shell',transform=transform,size=Util.deepcopy(scale),enabled=true,
        metadata={source='LocationStudio collision authoring',collision=collision_meta('primitive',layer.preset,layer.material),
            world_builder={definition_key='collision_shape',category='Collision',variant='Collision Shape',class_module='modules/classes/spawn/collision/collider',
                module_path='collision/collider',resource_name='Collision Shape',resource_path='',entry={name=name,fileName=name,data=data},apply_scale=true}}})
    if not object then return nil,'project model rejected the collision object' end
    local result={shape=SHAPE_NAMES[shape],dimensions=describe_scale(shape,scale),placement_source=source}
    if source=='forward_fallback' then result.warning='No surface was hit; the collider sits on the camera ray at the requested distance.' end
    return self:_save_and_spawn(object,args,result)
end

-- Imported collision resource from World Builder's Collision Mesh catalog.
function Collision:search_meshes(args)
    args=args or {}
    local result,err=self.app.world_builder:search('collision_mesh',args.query or '',args.limit or 80,args.refresh==true)
    if not result then return nil,err end
    local items={};for _,item in ipairs(result.items or {}) do items[#items+1]={name=item.name,path=item.path} end
    return {items=items,total=result.total,shown=result.shown}
end

function Collision:import_mesh(args)
    args=args or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local found,err=self.app.world_builder:search('collision_mesh',args.resource_path or args.query or '',250,false)
    if not found then return nil,err end
    local resource
    for _,item in ipairs(found.items or {}) do
        if not args.resource_path or args.resource_path=='' or string.lower(item.path)==string.lower(args.resource_path) or string.lower(item.name)==string.lower(args.resource_path) then resource=item;break end
    end
    if not resource then return nil,'collision resource is not in the loaded World Builder Collision Mesh catalog' end
    local layer;layer,err=self:_layer_fields(args);if not layer then return nil,err end
    local payload;payload,err=self.app.world_builder:prepare_favorite_record({category='Collision',variant='Collision Mesh',spawn_data=resource.path,name=resource.name},args.name or resource.name)
    if not payload then return nil,err end
    local saved=payload.data and payload.data.spawnable;if type(saved)~='table' then return nil,'World Builder returned no Collision Mesh data' end
    saved.preset=layer.preset;if layer.material then saved.material=layer.material end;saved.previewed=args.visualize~=false
    local s=tonumber(args.scale) or 1;if s<0.01 or s>100 then return nil,'scale must be between 0.01 and 100' end
    saved.scale={x=s,y=s,z=s}
    local transform,source=self:_transform(args);if not transform then return nil,source end
    local name=Util.trim(args.name or '')~='' and Util.trim(args.name) or resource.name
    self.app.model:snapshot()
    local object=self.app.model:add_object({premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id or self.app.selected_room_id,
        name=name,kind='collision',template='',layer='shell',transform=transform,size={x=s,y=s,z=s},enabled=true,
        metadata={source='LocationStudio collision authoring',collision=collision_meta('mesh',layer.preset,layer.material or saved.material),
            world_builder={definition_key='collision_mesh',category='Collision',variant='Collision Mesh',class_module='modules/classes/spawn/collision/meshCollider',
                module_path='collision/meshCollider',resource_name=resource.name,resource_path=resource.path,entry={name=name,fileName=name,data=saved},apply_scale=true}}})
    if not object then return nil,'project model rejected the collision mesh' end
    return self:_save_and_spawn(object,args,{resource_path=resource.path,placement_source=source,
        note='Passability uses imported asset bounds for collision meshes; without them the mesh is listed as not rasterized.'})
end

-- Fit a box collider to a placed object's imported world bounds.
function Collision:fit_to_object(args)
    args=args or {}
    if not self.app.asset_bounds then return nil,'asset bounds module is unavailable' end
    local bounds,err=self.app.asset_bounds:world_aabb(args.object_id);if not bounds then return nil,err end
    local pad=tonumber(args.padding) or 0;if pad<0 or pad>5 then return nil,'padding must be between 0 and 5 m' end
    local a=bounds.aabb
    local source=self.app.model:get_object(args.object_id)
    local create=Util.deepcopy(args);create.shape='box';create.object_id=nil;create.padding=nil
    create.size={x=a.max.x-a.min.x+pad*2,y=a.max.y-a.min.y+pad*2,z=a.max.z-a.min.z+pad*2}
    create.transform={position={x=(a.min.x+a.max.x)/2,y=(a.min.y+a.max.y)/2,z=(a.min.z+a.max.z)/2,w=1},rotation={roll=0,pitch=0,yaw=0}}
    create.name=args.name or ((source and source.name or 'Object')..' Collision')
    create.premise_id=args.premise_id or (source and source.premise_id);create.room_id=args.room_id or (source and source.room_id)
    local result;result,err=self:create_primitive(create);if not result then return nil,err end
    result.fitted_to=args.object_id;result.bounds_source=bounds.source
    return result
end

function Collision:_respawn(object,result)
    if not self.app.placement:is_tracked(object) then return result end
    local removed,remove_err=self.app.placement:despawn(object)
    if not removed then result.warning='saved, but the old collider could not be removed: '..tostring(remove_err);return result end
    local id,err=self.app.placement:spawn(object)
    if id then result.respawned=true else result.warning='saved, but collider respawn failed: '..tostring(err) end
    return result
end

function Collision:update(id,patch)
    patch=patch or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local object=self.app.model:get_object(id);if not self:is_collision(object) then return nil,'object is not a collision shape or collision mesh' end
    if object.locked then return nil,'collision object is locked' end
    local wb=wb_of(object);local data=wb.entry and wb.entry.data;if type(data)~='table' then return nil,'collision spawn data is missing' end
    local layer,err=self:_layer_fields(patch,{preset=tonumber(data.preset) or DEFAULT_PRESET,material=data.material});if not layer then return nil,err end
    local scale=wb.apply_scale and object.size or data.scale
    local shape=tonumber(data.shape) or 0
    if wb.definition_key=='collision_shape' then
        if patch.shape~=nil then shape=SHAPES[patch.shape];if shape==nil then return nil,'shape must be box, capsule or sphere' end end
        if patch.shape~=nil or patch.size~=nil or patch.radius~=nil or patch.height~=nil then
            local base=scale;if patch.shape~=nil and shape~=(tonumber(data.shape) or 0) then base={x=scale.x,y=scale.x,z=shape==1 and scale.z*2 or scale.x} end
            scale,err=primitive_scale(shape,patch,base);if not scale then return nil,err end
        end
    elseif patch.scale~=nil then
        local s=tonumber(patch.scale);if not s or s<0.01 or s>100 then return nil,'scale must be between 0.01 and 100' end
        scale={x=s,y=s,z=s}
    end
    local transform=Util.deepcopy(object.transform)
    for _,axis in ipairs({'roll','pitch','yaw'}) do if patch[axis]~=nil then transform.rotation[axis]=tonumber(patch[axis]) or 0 end end
    if type(patch.position)=='table' then for _,axis in ipairs({'x','y','z'}) do if patch.position[axis]~=nil then transform.position[axis]=tonumber(patch.position[axis]) or transform.position[axis] end end end
    self.app.model:snapshot('Update collision')
    data.shape=wb.definition_key=='collision_shape' and shape or data.shape;data.scale=Util.deepcopy(scale);data.preset=layer.preset;data.material=layer.material
    if patch.visualize~=nil then data.previewed=patch.visualize==true end
    object.size=Util.deepcopy(scale);object.transform=transform
    if patch.name and Util.trim(patch.name)~='' then object.name=Util.trim(patch.name) end
    local kind=object.metadata.collision and object.metadata.collision.kind or (wb.definition_key=='collision_mesh' and 'mesh' or 'room_kit')
    object.metadata.collision=collision_meta(kind,layer.preset,layer.material)
    object.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return self:_respawn(object,{object=object,respawned=false})
end

-- Every collision object in scope, including room-kit colliders.
function Collision:list(args)
    args=args or {}
    local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        if self:is_collision(o) and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) and (not args.room_id or args.room_id=='' or o.room_id==args.room_id) then
            local wb=wb_of(o);local data=wb.entry and wb.entry.data or {}
            local preset=tonumber(data.preset) or DEFAULT_PRESET
            local shape=wb.definition_key=='collision_mesh' and 'mesh' or SHAPE_NAMES[tonumber(data.shape) or 0]
            local row={id=o.id,name=o.name,premise_id=o.premise_id,room_id=o.room_id,shape=shape,preset=PRESETS[preset+1],preset_index=preset,
                groups=Util.deepcopy(PRESET_GROUPS[preset+1]),material=data.material and MATERIALS[data.material+1] or 'World Builder default',
                visualized=data.previewed~=false,room_kit=o.metadata.room_collision==true,enabled=o.enabled~=false,
                spawned=o.runtime and o.runtime.spawned==true or false,transform=Util.deepcopy(o.transform),resource_path=wb.resource_path}
            if shape~='mesh' then row.dimensions=describe_scale(tonumber(data.shape) or 0,wb.apply_scale and o.size or data.scale or {x=0.5,y=0.5,z=0.5}) end
            if not args.preset or args.preset=='' or row.preset==args.preset or tostring(row.preset_index)==tostring(args.preset) then out[#out+1]=row end
        end
    end
    return {items=out,count=#out}
end

-- Collision layers in use, grouped by preset.
function Collision:layers(args)
    local by={}
    for _,row in ipairs(self:list(args).items) do
        local entry=by[row.preset]
        if not entry then entry={preset=row.preset,preset_index=row.preset_index,groups=row.groups,count=0,visualized=0,object_ids={},
            blocks_player=blocks(row.groups,ACTORS.player.blocking_groups),blocks_npc=blocks(row.groups,ACTORS.npc.blocking_groups)};by[row.preset]=entry end
        entry.count=entry.count+1;if row.visualized then entry.visualized=entry.visualized+1 end;entry.object_ids[#entry.object_ids+1]=row.id
    end
    local out={};for _,e in pairs(by) do out[#out+1]=e end
    table.sort(out,function(a,b) return a.preset_index<b.preset_index end)
    return {layers=out,count=#out}
end

-- Toggle World Builder's collider wireframe visualization. The WB class draws
-- it from `previewed` when the node is assembled, so live colliders respawn.
function Collision:set_visualization(args)
    args=args or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local visible=args.visible~=false
    local ids={}
    if type(args.object_ids)=='table' and #args.object_ids>0 then for _,id in ipairs(args.object_ids) do ids[id]=true end end
    local changed,respawned,failed=0,0,{}
    local touched={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local row_ok=self:is_collision(o) and (next(ids)==nil or ids[o.id]) and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id)
            and (not args.preset or args.preset=='' or (tonumber((wb_of(o).entry.data or {}).preset) or DEFAULT_PRESET)==preset_index(args.preset))
        if row_ok then
            local data=wb_of(o).entry and wb_of(o).entry.data
            if type(data)=='table' and (data.previewed~=false)~=visible then touched[#touched+1]={object=o,data=data} end
        end
    end
    if #touched==0 then return {changed=0,respawned=0,failed={},visible=visible} end
    self.app.model:snapshot('Collision visualization')
    for _,t in ipairs(touched) do
        t.data.previewed=visible;changed=changed+1
        local r=self:_respawn(t.object,{})
        if r.respawned then respawned=respawned+1 elseif r.warning then failed[#failed+1]={object_id=t.object.id,error=r.warning} end
    end
    self.app.model:touch();self.app:mark_dirty()
    return {changed=changed,respawned=respawned,failed=failed,visible=visible}
end

-- Passability ------------------------------------------------------------------

local function rotate2(x,y,deg) local r=math.rad(deg or 0);local c,s=math.cos(r),math.sin(r);return x*c-y*s,x*s+y*c end

-- Horizontal footprint + vertical extent for one collider, or nil and why not.
function Collision:_footprint(object)
    local wb=wb_of(object);local data=wb.entry and wb.entry.data or {}
    local p=object.transform.position;local r=object.transform.rotation or {}
    if wb.definition_key=='collision_mesh' then
        if not self.app.asset_bounds then return nil,'no asset bounds module' end
        local b=self.app.asset_bounds:world_aabb(object.id)
        if not b then return nil,'collision mesh has no imported asset bounds' end
        local a=b.aabb
        return {kind='aabb',cx=(a.min.x+a.max.x)/2,cy=(a.min.y+a.max.y)/2,hx=(a.max.x-a.min.x)/2,hy=(a.max.y-a.min.y)/2,yaw=0,zmin=a.min.z,zmax=a.max.z}
    end
    local s=wb.apply_scale and object.size or data.scale or {x=0.5,y=0.5,z=0.5}
    local shape=tonumber(data.shape) or 0
    local hx,hy,hz=tonumber(s.x) or 0.5,tonumber(s.y) or 0.5,tonumber(s.z) or 0.5
    if shape==1 then hx,hy,hz=hx,hx,hz/2+hx elseif shape==2 then hx,hy,hz=hx,hx,hx end
    local tilted=math.abs(tonumber(r.roll) or 0)>0.5 or math.abs(tonumber(r.pitch) or 0)>0.5
    if tilted then
        -- Conservative: world AABB of the rotated box (roll/pitch/yaw).
        local rad=math.rad;local cr,sr=math.cos(rad(r.roll or 0)),math.sin(rad(r.roll or 0));local cp,sp=math.cos(rad(r.pitch or 0)),math.sin(rad(r.pitch or 0));local cy,sy=math.cos(rad(r.yaw or 0)),math.sin(rad(r.yaw or 0))
        local ex,ey,ez=0,0,0
        for _,c in ipairs({{hx,hy,hz},{-hx,hy,hz},{hx,-hy,hz},{hx,hy,-hz},{-hx,-hy,hz},{-hx,hy,-hz},{hx,-hy,-hz},{-hx,-hy,-hz}}) do
            local x,y,z=c[1],c[2],c[3]
            y,z=y*cr-z*sr,y*sr+z*cr;x,z=x*cp+z*sp,-x*sp+z*cp;x,y=x*cy-y*sy,x*sy+y*cy
            ex,ey,ez=math.max(ex,math.abs(x)),math.max(ey,math.abs(y)),math.max(ez,math.abs(z))
        end
        return {kind='aabb',cx=p.x,cy=p.y,hx=ex,hy=ey,yaw=0,zmin=p.z-ez,zmax=p.z+ez,round=false}
    end
    return {kind=shape==0 and 'box' or 'round',cx=p.x,cy=p.y,hx=hx,hy=hy,yaw=tonumber(r.yaw) or 0,zmin=p.z-hz,zmax=p.z+hz}
end

local function cell_hits(fp,x,y,radius)
    local lx,ly=rotate2(x-fp.cx,y-fp.cy,-(fp.yaw or 0))
    if fp.kind=='round' then return lx*lx+ly*ly<=(fp.hx+radius)^2 end
    local dx=math.max(0,math.abs(lx)-fp.hx);local dy=math.max(0,math.abs(ly)-fp.hy)
    return dx*dx+dy*dy<=radius*radius
end

local function region_from(self,args)
    if args.room_id and args.room_id~='' then
        local room=self.app.model:get_room(args.room_id);if not room then return nil,'room not found' end
        local margin=tonumber(args.margin) or 1
        return {cx=room.transform.position.x,cy=room.transform.position.y,hx=room.size.width/2+margin,hy=room.size.depth/2+margin,z=room.transform.position.z,yaw=room.transform.rotation.yaw or 0,premise_id=room.premise_id}
    end
    if type(args.center)=='table' then
        local hx=tonumber(args.half_width) or 10;local hy=tonumber(args.half_depth) or hx
        return {cx=tonumber(args.center.x) or 0,cy=tonumber(args.center.y) or 0,hx=hx,hy=hy,z=tonumber(args.center.z) or tonumber(args.floor_z) or 0,yaw=0,premise_id=args.premise_id}
    end
    local t=self.app.game:capture_transform();if not t then return nil,'provide room_id or center, or stand in the area to preview' end
    local hx=tonumber(args.half_width) or 10;local hy=tonumber(args.half_depth) or hx
    return {cx=t.position.x,cy=t.position.y,hx=hx,hy=hy,z=t.position.z,yaw=0,premise_id=args.premise_id}
end

-- 2.5D estimate on one floor level from authored colliders: each cell holds an
-- upright actor capsule; it is blocked when a collider whose groups block that
-- actor overlaps the capsule between step height and head height.
function Collision:passability(args)
    args=args or {}
    local step=tonumber(args.grid_step) or 0.5;if step<0.1 or step>4 then return nil,'grid_step must be between 0.1 and 4 m' end
    local region,err=region_from(self,args);if not region then return nil,err end
    local floor_z=tonumber(args.floor_z) or region.z
    local cols=math.max(1,math.floor(region.hx*2/step+0.5));local rows=math.max(1,math.floor(region.hy*2/step+0.5))
    if cols*rows>MAX_CELLS then return nil,'grid would have '..cols*rows..' cells; use a coarser grid_step or smaller area (max '..MAX_CELLS..')' end
    local wanted=args.actor or 'both'
    local actors=wanted=='both' and {'player','npc'} or {wanted}
    for _,name in ipairs(actors) do if not ACTORS[name] then return nil,'actor must be player, npc or both' end end
    local profiles={}
    for _,name in ipairs(actors) do
        local base=ACTORS[name];local custom=args[name] or {}
        profiles[name]={radius=tonumber(custom.radius) or base.radius,height=tonumber(custom.height) or base.height,step=tonumber(custom.step) or base.step,
            blocking_groups=type(custom.blocking_groups)=='table' and custom.blocking_groups or base.blocking_groups}
    end
    local footprints,skipped={}, {}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        if self:is_collision(o) and o.enabled~=false and (args.include_all or not region.premise_id or o.premise_id==region.premise_id) then
            local fp,why=self:_footprint(o)
            if fp then
                local data=wb_of(o).entry.data or {};local preset=tonumber(data.preset) or DEFAULT_PRESET
                fp.id=o.id;fp.name=o.name;fp.groups=PRESET_GROUPS[preset+1];fp.preset=PRESETS[preset+1];footprints[#footprints+1]=fp
            else skipped[#skipped+1]={id=o.id,name=o.name,reason=why} end
        end
    end
    local c,s=math.cos(math.rad(region.yaw)),math.sin(math.rad(region.yaw))
    local function world(i,j)
        local lx=-region.hx+(i-0.5)*step;local ly=-region.hy+(j-0.5)*step
        return region.cx+lx*c-ly*s,region.cy+lx*s+ly*c
    end
    local grids,blockers={}, {}
    for _,name in ipairs(actors) do
        local prof=profiles[name];local grid={}
        local zlow,zhigh=floor_z+prof.step,floor_z+prof.height
        for j=1,rows do grid[j]={} for i=1,cols do
            local x,y=world(i,j);local hit=false
            for _,fp in ipairs(footprints) do
                if fp.zmax>zlow and fp.zmin<zhigh and blocks(fp.groups,prof.blocking_groups) and cell_hits(fp,x,y,prof.radius) then
                    hit=true;blockers[fp.id]=blockers[fp.id] or {id=fp.id,name=fp.name,preset=fp.preset,actors={}};blockers[fp.id].actors[name]=true;break
                end
            end
            grid[j][i]=hit
        end end
        grids[name]=grid
    end
    local function cell_of(point)
        if type(point)~='table' then return nil end
        local dx,dy=(tonumber(point.x) or 0)-region.cx,(tonumber(point.y) or 0)-region.cy
        local lx,ly=dx*c+dy*s,-dx*s+dy*c
        local i=math.floor((lx+region.hx)/step)+1;local j=math.floor((ly+region.hy)/step)+1
        if i<1 or j<1 or i>cols or j>rows then return nil end
        return i,j
    end
    local si,sj=cell_of(args.start);local gi,gj=cell_of(args.goal)
    local routes={}
    for _,name in ipairs(actors) do
        local grid=grids[name];local free=0
        for j=1,rows do for i=1,cols do if not grid[j][i] then free=free+1 end end end
        local route={free_cells=free,blocked_cells=cols*rows-free}
        if args.start or args.goal then
            if not si or not gi then route.status='endpoint_outside_area'
            elseif grid[sj][si] then route.status='start_blocked'
            elseif grid[gj][gi] then route.status='goal_blocked'
            else
                -- 8-neighbour BFS without diagonal corner cutting.
                local parent,queue,head={},{{si,sj}},1;parent[sj*100000+si]=true
                while head<=#queue do
                    local ci,cj=queue[head][1],queue[head][2];head=head+1
                    if ci==gi and cj==gj then break end
                    for dj=-1,1 do for di=-1,1 do if di~=0 or dj~=0 then
                        local ni,nj=ci+di,cj+dj
                        if ni>=1 and nj>=1 and ni<=cols and nj<=rows and not grid[nj][ni] and parent[nj*100000+ni]==nil
                            and (di==0 or dj==0 or (not grid[cj][ni] and not grid[nj][ci])) then
                            parent[nj*100000+ni]={ci,cj};queue[#queue+1]={ni,nj}
                        end
                    end end end
                end
                if parent[gj*100000+gi]~=nil then
                    local path,cur={}, {gi,gj}
                    while cur and cur~=true do path[#path+1]={i=cur[1],j=cur[2]};cur=parent[cur[2]*100000+cur[1]] end
                    route.status='route';route.path_cells=#path;route.path={};local length=0
                    for k=#path,1,-1 do
                        local x,y=world(path[k].i,path[k].j);local prev=route.path[#route.path]
                        if prev then length=length+math.sqrt((x-prev.x)^2+(y-prev.y)^2) end
                        route.path[#route.path+1]={x=x,y=y,z=floor_z}
                    end
                    route.path_length=length
                    route._cells=path
                else route.status='no_route' end
            end
        end
        routes[name]=route
    end
    -- Text map, top row = far edge (+Y in the area's frame).
    local on_path={}
    for _,name in ipairs(actors) do for _,cell in ipairs(routes[name]._cells or {}) do on_path[cell.j*100000+cell.i]=true end;routes[name]._cells=nil end
    local lines={}
    for j=rows,1,-1 do
        local chars={}
        for i=1,cols do
            local ch
            if i==si and j==sj then ch='S' elseif i==gi and j==gj then ch='G'
            else
                local p=grids.player and grids.player[j][i];local n=grids.npc and grids.npc[j][i]
                if #actors==2 then ch=(p and n) and '#' or p and 'p' or n and 'n' or '.' else ch=(p or n) and '#' or '.' end
                if ch=='.' and on_path[j*100000+i] then ch='*' end
            end
            chars[i]=ch
        end
        lines[#lines+1]=table.concat(chars)
    end
    local list={};for _,b in pairs(blockers) do local a={};for k in pairs(b.actors) do a[#a+1]=k end;table.sort(a);b.actors=a;list[#list+1]=b end
    table.sort(list,function(a,b) return a.name<b.name end)
    local result={method='authored collider footprint grid',actors=actors,profiles=profiles,grid_step=step,columns=cols,rows=rows,floor_z=floor_z,
        area={center={x=region.cx,y=region.cy},half_width=region.hx,half_depth=region.hy,yaw=region.yaw},colliders_considered=#footprints,
        skipped_colliders=skipped,blockers=list,routes=routes,map=lines,
        legend=#actors==2 and {['#']='blocks player and NPC',p='blocks player only',n='blocks NPC only',['.']='free',['*']='route',S='start',G='goal'} or {['#']='blocked',['.']='free',['*']='route',S='start',G='goal'},
        caveat='Estimate from saved LocationStudio colliders on one floor level. Vanilla world collision, navmesh, doors and stairs are not included; use live=true to cross-check with collision rays.'}
    if args.live==true and args.start and args.goal then
        if not self.app.live_tools then result.live={error='live tools unavailable'}
        else
            local ok,live,live_err=pcall(function() return self.app.live_tools:walkability_check({start=args.start,goal=args.goal,actor=actors[1]=='npc' and 'npc' or 'player',grid_step=math.max(0.5,step),margin=tonumber(args.live_margin) or 2}) end)
            if not ok then result.live={error='live collision scan failed: '..tostring(live)} else result.live=live or {error=live_err} end
        end
    end
    self.last_passability=result
    return result
end

Collision.PRESETS=PRESETS
return Collision
