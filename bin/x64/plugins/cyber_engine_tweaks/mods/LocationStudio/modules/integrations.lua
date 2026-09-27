local Integrations = {}
Integrations.__index = Integrations

function Integrations.new()
    return setmetatable({amm=nil, world_builder=nil, redhottools=nil, checked=false}, Integrations)
end

function Integrations:refresh()
    local function safe_get(name)
        local ok, value = pcall(function() return GetMod(name) end)
        if ok then return value end
        return nil
    end

    self.amm = safe_get('AppearanceMenuMod') or safe_get('AMM')
    self.world_builder = safe_get('entSpawner') or safe_get('WorldBuilder')
    self.redhottools = safe_get('RedHotTools') or safe_get('redHotTools')
    self.checked = true
end

function Integrations:status()
    if not self.checked then self:refresh() end
    return {
        amm = self.amm ~= nil,
        world_builder = self.world_builder ~= nil,
        redhottools = self.redhottools ~= nil,
    }
end

-- CET only reports mods that expose a GetMod key. This audit combines those
-- live signals with LocationStudio's own project metadata; it cannot inspect
-- native archive contents or prove compatibility with arbitrary third-party mods.
function Integrations:compatibility_scan(app)
    self:refresh()
    local loaded={AppearanceMenuMod=self.amm~=nil,WorldBuilder=self.world_builder~=nil,RedHotTools=self.redhottools~=nil}
    local counts={objects=0,world_builder=0,cet_entities=0,missing_resource=0,missing_bounds=0}
    local findings={}
    for _,object in ipairs(app.model.data.objects or {}) do
        counts.objects=counts.objects+1
        local metadata=object.metadata or {};local wb=type(metadata.world_builder)=='table'
        if wb then
            counts.world_builder=counts.world_builder+1
            if tostring(metadata.world_builder.resource_path or object.template or '')=='' then
                counts.missing_resource=counts.missing_resource+1
                table.insert(findings,{severity='error',code='world_builder_resource_missing',object_id=object.id,name=object.name,message='World Builder object has no resource path/template.'})
            end
            if type(metadata.asset_bounds)~='table' then counts.missing_bounds=counts.missing_bounds+1 end
        else
            counts.cet_entities=counts.cet_entities+1
            if tostring(object.template or '')=='' then
                counts.missing_resource=counts.missing_resource+1
                table.insert(findings,{severity='error',code='cet_template_missing',object_id=object.id,name=object.name,message='CET entity has no template path.'})
            end
        end
    end
    if counts.world_builder>0 and not loaded.WorldBuilder then
        table.insert(findings,1,{severity='warning',code='world_builder_not_loaded',message='The project contains World Builder objects, but GetMod did not report World Builder/entSpawner loaded; live spawning and editing may be unavailable.'})
    end
    if counts.missing_bounds>0 then table.insert(findings,{severity='info',code='collision_bounds_incomplete',count=counts.missing_bounds,message='Some World Builder objects lack imported bounds and will be skipped by the bounds-based collision scan.'}) end
    return {read_only=true,timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ'),loaded_integrations=loaded,project=counts,findings=findings,
        limits={'Loaded integrations are detected only through CET GetMod keys.','Arbitrary third-party mod contents, archive resources, load order and binary compatibility cannot be verified by CET.'}}
end

function Integrations:export_hint(location)
    local status = self:status()
    return {
        world_builder_available = status.world_builder,
        amm_available = status.amm,
        redhottools_available = status.redhottools,
        note = 'LocationStudio deliberately exports neutral transforms. World Builder/AMM APIs differ by version; use exported coordinates as the stable handoff.',
        location = location,
    }
end

return Integrations
