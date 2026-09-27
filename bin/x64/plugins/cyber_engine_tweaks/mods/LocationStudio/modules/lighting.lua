local Util=require('modules/util')
local Lighting={};Lighting.__index=Lighting

local PRESETS={
    {id='warm',name='Warm tungsten',color={1.0,0.62,0.30},intensity=100,radius=8,flickerStrength=0,flickerPeriod=0.2,flickerOffset=0},
    {id='cool',name='Cool office',color={0.58,0.78,1.0},intensity=130,radius=10,flickerStrength=0,flickerPeriod=0.2,flickerOffset=0},
    {id='neon_cyan',name='Neon cyan',color={0.05,0.86,1.0},intensity=180,radius=12,flickerStrength=0.04,flickerPeriod=0.18,flickerOffset=0},
    {id='neon_magenta',name='Neon magenta',color={1.0,0.08,0.52},intensity=180,radius=12,flickerStrength=0.03,flickerPeriod=0.2,flickerOffset=0},
    {id='emergency',name='Emergency red flicker',color={1.0,0.025,0.01},intensity=240,radius=14,flickerStrength=0.55,flickerPeriod=0.13,flickerOffset=0},
    {id='soft_fill',name='Soft fill',color={0.86,0.91,1.0},intensity=45,radius=6,flickerStrength=0,flickerPeriod=0.2,flickerOffset=0},
}
local function clean_config(input,base)
    input=input or {};base=base or {}
    local color=input.color or base.color or {1,1,1}
    if type(color)~='table' then return nil,'color must be an RGB array' end
    local out={color={}}
    for i=1,3 do local n=tonumber(color[i]);if not n or n<0 or n>1 then return nil,'RGB channels must be between 0 and 1' end;out.color[i]=n end
    local limits={intensity={0,9999},radius={0.05,9999},flickerStrength={0,1},flickerPeriod={0.05,9999},flickerOffset={0,9999}}
    for key,range in pairs(limits) do local n=tonumber(input[key]~=nil and input[key] or base[key]);if not n or n<range[1] or n>range[2] then return nil,key..' is outside supported range' end;out[key]=n end
    return out
end
local function set_saved(light,config)
    light=light or {};light.color=Util.deepcopy(config.color);light.intensity=config.intensity;light.radius=config.radius
    light.flickerStrength=config.flickerStrength;light.flickerPeriod=config.flickerPeriod;light.flickerOffset=config.flickerOffset
    light.lightType=light.lightType or 1
    return light
end
function Lighting.new(app) return setmetatable({app=app,preview_time_seconds=nil,last_error=nil},Lighting) end
function Lighting:presets() return Util.deepcopy(PRESETS) end
function Lighting:_light_payload(resource,name,config)
    local payload,err=self.app.world_builder:prepare_favorite_record({category='Lighting',variant='Static Light',spawn_data=resource.path,name=resource.name},name)
    if not payload then return nil,err end
    payload.data=payload.data or {};local saved=set_saved(payload.data.spawnable,config)
    -- The active World Builder class consumes catalog-style `{name,fileName,data}` entries.
    -- Reuse its own serialized Light:save() data so its loadSpawnData/onAssemble path creates the real light component.
    return {name=payload.name,fileName=payload.name,data=saved}
end
function Lighting:create(args)
    args=args or {}
    if not self.app.world_builder then return nil,'World Builder light backend is unavailable' end
    local input=args.config or args
    if args.preset_id then for _,preset in ipairs(PRESETS) do if preset.id==args.preset_id then input=preset;break end end end
    if not input.color then input={color={1,1,1},intensity=100,radius=15,flickerStrength=0,flickerPeriod=0.2,flickerOffset=0} end
    local config,err=clean_config(input);if not config then return nil,err end
    local result;result,err=self.app.world_builder:search('light_static',args.resource_name or '',60,true)
    if not result then return nil,err end
    local resource=result.items and result.items[1];if not resource then return nil,'World Builder Static Light catalog is empty; open World Builder and refresh its catalog first' end
    local transform=args.transform
    if not transform then
        if args.source=='aim' then local hit;hit,err=self.app.game:aim_point(args.distance or 10);if not hit then return nil,err end;transform={position=hit.position,rotation={roll=0,pitch=0,yaw=tonumber(args.yaw) or 0}}
        elseif args.source=='origin' then local premise=self.app.model:get_premise(args.premise_id or self.app.selected_premise_id);if not premise then return nil,'select a premise or provide a transform' end;transform=Util.deepcopy(premise.transform)
        else transform,err=self.app.game:capture_transform();if not transform then return nil,err end end
    end
    local name=Util.trim(args.name or '')~='' and Util.trim(args.name) or resource.name..' Light'
    local entry;entry,err=self:_light_payload(resource,name,config);if not entry then return nil,err end
    self.app.model:snapshot()
    local object=self.app.model:add_object({premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id or self.app.selected_room_id,
        name=name,kind='light',template='',layer='lighting',transform=transform,size={x=1,y=1,z=1},enabled=true,
        metadata={source='LocationStudio Static Light',lighting=Util.deepcopy(config),world_builder={definition_key='light_static',category='Lighting',variant='Static Light',class_module='modules/classes/spawn/light/light',module_path='light/light',resource_name=resource.name,resource_path=resource.path,entry=entry,apply_scale=false}}})
    if not object then return nil,'model rejected light object' end
    self.app.selection:set('object',object.id);self.app:mark_dirty()
    if args.spawn~=false then local id,spawn_err=self.app.placement:spawn(object);if not id then self.last_error=tostring(spawn_err);return object,'Light saved but live spawn failed: '..tostring(spawn_err) end end
    return object
end
function Lighting:update(object_id,patch)
    patch=patch or {}
    if patch.preset_id then return self:apply_preset(object_id,patch.preset_id) end
    local object=self.app.model:get_object(object_id);if not object then return nil,'light object not found' end
    local wb=object.metadata and object.metadata.world_builder
    if not wb or wb.definition_key~='light_static' then return nil,'selected object is not a World Builder Static Light' end
    if object.locked then return nil,'light is locked; unlock it before editing' end
    local base=object.metadata.lighting or {};local config,err=clean_config(patch,base);if not config then return nil,err end
    local payload=wb.entry or {};local saved=payload.data
    if type(saved)~='table' then return nil,'light spawn data is missing; respawn from the Lighting tab to repair it' end
    self.app.model:snapshot();object.metadata.lighting=config;set_saved(saved,config);object.updated_at=Util.now_iso()
    local was_live=self.app.placement:is_tracked(object)
    if was_live then
        local removed,remove_err=self.app.placement:despawn(object);if not removed then return nil,'settings saved, but old light could not be removed: '..tostring(remove_err) end
        local id,spawn_err=self.app.placement:spawn(object);if not id then self.app:mark_dirty();self.last_error=tostring(spawn_err);return object,'settings saved, but light respawn failed: '..tostring(spawn_err) end
    end
    self.app:mark_dirty();return object
end
function Lighting:apply_preset(object_id,preset_id)
    for _,preset in ipairs(PRESETS) do if preset.id==preset_id then return self:update(object_id,preset) end end
    return nil,'unknown lighting preset: '..tostring(preset_id)
end
function Lighting:preview_time(hour,minute)
    hour=math.floor(tonumber(hour) or -1);minute=math.floor(tonumber(minute) or 0)
    if hour<0 or hour>23 or minute<0 or minute>59 then return nil,'time must be between 00:00 and 23:59' end
    local ok,sys=pcall(function() return Game.GetTimeSystem() end);if not ok or not sys then return nil,'CET game-time system is unavailable' end
    if self.preview_time_seconds==nil then
        local got,current=pcall(function() return sys:GetGameTime() end);if not got or not current then return nil,'could not read current game time' end
        local seconds_ok,seconds=pcall(function() return GameTime.GetSeconds(current) end)
        if not seconds_ok or type(seconds)~='number' then seconds_ok,seconds=pcall(function() return current.seconds end) end
        if not seconds_ok or type(seconds)~='number' then return nil,'could not save current time for restoration' end
        self.preview_time_seconds=seconds
    end
    local set,set_err=pcall(function() sys:SetGameTimeByHMS(hour,minute,0) end);if not set then return nil,'time preview failed: '..tostring(set_err) end
    return {preview=true,hour=hour,minute=minute,restore_available=true}
end
function Lighting:restore_time()
    if self.preview_time_seconds==nil then return nil,'no time preview to restore' end
    local sys_ok,sys=pcall(function() return Game.GetTimeSystem() end);if not sys_ok or not sys then return nil,'CET game-time system is unavailable' end
    local ok,err=pcall(function() sys:GetGameTime():SetGameTimeBySeconds(self.preview_time_seconds) end);if not ok then return nil,'time restore failed: '..tostring(err) end
    self.preview_time_seconds=nil;return {restored=true}
end
return Lighting
