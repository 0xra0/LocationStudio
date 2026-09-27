local Util=require('modules/util')

local WorldBuilder={}
WorldBuilder.__index=WorldBuilder

-- These names are the public Spawn New categories exposed by World Builder 1.0.81.
-- Keeping the mapping here lets Location Studio browse the already-loaded game
-- resource database without copying tens of thousands of paths into project.json.
local DEFINITIONS={
    {key='entity_template',label='Entity Templates',category='Entity',variant='Template',class_module='modules/classes/spawn/entity/entityTemplate',kind='entity',layer='decoration'},
    {key='entity_amm',label='AMM Entities',category='Entity',variant='Template (AMM)',class_module='modules/classes/spawn/entity/ammEntity',kind='entity',layer='decoration'},
    {key='entity_record',label='Entity Records',category='Entity',variant='Record',class_module='modules/classes/spawn/entity/entityRecord',kind='entity',layer='decoration'},
    {key='device',label='Devices',category='Entity',variant='Device',class_module='modules/classes/spawn/entity/device',kind='device',layer='gameplay'},
    {key='mesh_static',label='Static Meshes',category='Mesh',variant='Mesh',class_module='modules/classes/spawn/mesh/mesh',kind='mesh',layer='decoration'},
    {key='mesh_rotating',label='Rotating Meshes',category='Mesh',variant='Rotating Mesh',class_module='modules/classes/spawn/mesh/rotatingMesh',kind='mesh',layer='decoration'},
    {key='mesh_cloth',label='Cloth Meshes',category='Mesh',variant='Cloth Mesh',class_module='modules/classes/spawn/mesh/clothMesh',kind='mesh',layer='decoration'},
    {key='mesh_dynamic',label='Dynamic Meshes',category='Mesh',variant='Dynamic Mesh',class_module='modules/classes/spawn/physics/dynamicMesh',kind='mesh',layer='decoration'},
    {key='mesh_proxy',label='Proxy Meshes',category='Mesh',variant='Proxy Mesh',class_module='modules/classes/spawn/mesh/proxyMesh',kind='mesh',layer='decoration'},
    {key='light_static',label='Static Lights',category='Lighting',variant='Static Light',class_module='modules/classes/spawn/light/light',kind='light',layer='lighting'},
    {key='light_probe',label='Reflection Probes',category='Lighting',variant='Reflection Probe',class_module='modules/classes/spawn/meta/reflectionProbe',kind='light',layer='lighting'},
    {key='light_channel',label='Light Channel Areas',category='Lighting',variant='Light Channel Area',class_module='modules/classes/spawn/light/lightChannelArea',kind='volume',layer='lighting'},
    {key='fog',label='Fog Volumes',category='Lighting',variant='Fog Volume',class_module='modules/classes/spawn/visual/fog',kind='volume',layer='lighting'},
    {key='collision_shape',label='Collision Shapes',category='Collision',variant='Collision Shape',class_module='modules/classes/spawn/collision/collider',kind='collision',layer='shell'},
    {key='collision_mesh',label='Collision Meshes',category='Collision',variant='Collision Mesh',class_module='modules/classes/spawn/collision/meshCollider',kind='collision',layer='shell'},
    {key='decal',label='Decals',category='Deco',variant='Decals',class_module='modules/classes/spawn/visual/decal',kind='decal',layer='decoration'},
    {key='particle',label='Particles',category='Deco',variant='Particles',class_module='modules/classes/spawn/visual/particle',kind='particle',layer='decoration'},
    {key='effect',label='Effects',category='Deco',variant='Effects',class_module='modules/classes/spawn/visual/effect',kind='effect',layer='decoration'},
    {key='audio',label='Audio Emitters',category='Deco',variant='Static Audio Emitter',class_module='modules/classes/spawn/visual/audio',kind='audio',layer='decoration'},
    {key='water',label='Water Patches',category='Deco',variant='Water Patch',class_module='modules/classes/spawn/visual/waterPatch',kind='water',layer='decoration'},
    {key='occluder',label='Occluders',category='Meta',variant='Occluder',class_module='modules/classes/spawn/meta/occluder',kind='meta',layer='shell'},
    {key='static_marker',label='Static Markers',category='Meta',variant='Static Marker',class_module='modules/classes/spawn/meta/staticMarker',kind='marker',layer='gameplay'},
    {key='spline_point',label='Spline Points',category='Meta',variant='Spline Point',class_module='modules/classes/spawn/meta/splineMarker',kind='marker',layer='gameplay'},
    {key='spline',label='Splines',category='Meta',variant='Spline',class_module='modules/classes/spawn/meta/spline',kind='spline',layer='gameplay'},
    {key='area_outline',label='Outline Markers',category='Area',variant='Outline Marker',class_module='modules/classes/spawn/area/outlineMarker',kind='area',layer='gameplay'},
    {key='area_trigger',label='Trigger Areas',category='Area',variant='Trigger Area',class_module='modules/classes/spawn/area/triggerArea',kind='area',layer='gameplay'},
    {key='area_kill',label='Kill Areas',category='Area',variant='Kill Area',class_module='modules/classes/spawn/area/killArea',kind='area',layer='gameplay'},
    {key='area_prevention',label='Prevention Free Areas',category='Area',variant='Prevention Free',class_module='modules/classes/spawn/area/preventionFree',kind='area',layer='gameplay'},
    {key='area_water_null',label='Water Null Areas',category='Area',variant='Water Null',class_module='modules/classes/spawn/area/waterNull',kind='area',layer='gameplay'},
    {key='area_ambient',label='Ambient Areas',category='Area',variant='Ambient Area',class_module='modules/classes/spawn/area/ambientArea',kind='area',layer='gameplay'},
    {key='area_dummy',label='Dummy Areas',category='Area',variant='Dummy Area',class_module='modules/classes/spawn/area/dummyArea',kind='area',layer='gameplay'},
    {key='area_conversation',label='Conversation Areas',category='Area',variant='Conversation Area',class_module='modules/classes/spawn/area/conversationArea',kind='area',layer='gameplay'},
    {key='area_crowd_null',label='Crowd Null Areas',category='Area',variant='Crowd Null Area',class_module='modules/classes/spawn/area/crowdNull',kind='area',layer='gameplay'},
    {key='area_guard',label='Guard Areas',category='Area',variant='Guard Area',class_module='modules/classes/spawn/area/guardArea',kind='area',layer='gameplay'},
    {key='ai_spot',label='AI Spots',category='AI',variant='AI Spot',class_module='modules/classes/spawn/ai/aiSpot',kind='ai',layer='gameplay'},
    {key='ai_community',label='AI Communities',category='AI',variant='Community',class_module='modules/classes/spawn/ai/communityArea',kind='ai',layer='gameplay'},
}

local BY_KEY={}
for _,definition in ipairs(DEFINITIONS) do BY_KEY[definition.key]=definition end

local function basename(path)
    path=tostring(path or ''):gsub('\\','/')
    local name=path:match('([^/]+)$') or path
    return name:gsub('%.[^%.]+$','')
end

function WorldBuilder.new(app)
    return setmetatable({app=app,cache={},class_cache={},last_error=nil,last_query=nil},WorldBuilder)
end

function WorldBuilder:_log(level,message,fields)
    local logger=self.app and self.app.logger
    if logger and logger[level] then logger[level](logger,'world_builder',message,fields) end
end

function WorldBuilder:_mod()
    local wb=self.app and self.app.integrations and self.app.integrations.world_builder or nil
    if not wb and type(GetMod)=='function' then
        local ok,value=pcall(function() return GetMod('entSpawner') or GetMod('WorldBuilder') end)
        if ok then wb=value end
    end
    return wb
end

function WorldBuilder:spawn_ui()
    local wb=self:_mod()
    return wb and wb.baseUI and wb.baseUI.spawnUI or nil
end

function WorldBuilder:definitions()
    local out={};for _,value in ipairs(DEFINITIONS) do table.insert(out,value) end;return out
end

function WorldBuilder:definition(key) return BY_KEY[key] end

-- Saved builds store a spawnable's class as e.g. `mesh/mesh`, relative to
-- `modules/classes/spawn/`.
function WorldBuilder:definition_for_module_path(module_path)
    local class_module='modules/classes/spawn/'..tostring(module_path or '')
    for _,definition in ipairs(DEFINITIONS) do if definition.class_module==class_module then return definition end end
    return nil
end

function WorldBuilder:status()
    local wb=self:_mod();local ui=self:spawn_ui()
    local catalog=ui and type(ui.getActiveSpawnList)=='function' and type(ui.getCategoryIndex)=='function' and type(ui.getVariantIndex)=='function' and type(ui.updateCategory)=='function' and type(ui.updateVariant)=='function'
    local spawn=ui and type(ui.spawnNew)=='function' and ui.spawnedUI~=nil and ui.spawnedUI.root~=nil
    local reason
    if not wb then reason='World Builder / entSpawner is not loaded.'
    elseif not ui then reason='World Builder loaded, but Spawn New is not initialized yet.'
    elseif not catalog then reason='World Builder 1.0.81 resource catalog API is not ready.'
    elseif not spawn then reason='World Builder 1.0.81 Spawn New API is not ready.' end
    return {available=spawn==true and catalog==true,catalog_available=catalog==true,world_builder=wb~=nil,reason=reason}
end

function WorldBuilder:_read_list(definition)
    local ui=self:spawn_ui();if not ui then return nil,'World Builder Spawn New UI is unavailable' end
    local old_type,old_variant,old_filter=ui.selectedType,ui.selectedVariant,ui.filter
    local ok,result=xpcall(function()
        local category=ui.getCategoryIndex(definition.category)
        ui.selectedType=category-1;ui.updateCategory()
        local variant=ui.getVariantIndex(definition.category,definition.variant)
        ui.selectedVariant=variant-1;ui.updateVariant()
        local active=ui.getActiveSpawnList()
        if not active or type(active.data)~='table' then error('World Builder returned no resource list') end
        if type(active.class)~='table' or type(active.class.new)~='function' then error('World Builder returned a resource list without a usable spawn class') end
        return {data=active.data,class=active.class,module_path=active.modulePath,is_paths=active.isPaths==true}
    end,function(err) return debug and debug.traceback and debug.traceback(tostring(err),2) or tostring(err) end)
    pcall(function()
        ui.selectedType=old_type;ui.updateCategory();ui.selectedVariant=old_variant;ui.updateVariant();ui.filter=old_filter or '';ui.refresh()
    end)
    if not ok then self.last_error=tostring(result);self:_log('error','catalog_read_failed',{key=definition.key,error=self.last_error});return nil,self.last_error end
    self.class_cache[definition.key]=result.class
    return result
end

function WorldBuilder:load_catalog(key,force)
    local definition=BY_KEY[key];if not definition then return nil,'unknown game-resource type: '..tostring(key) end
    if not force and self.cache[key] then return self.cache[key] end
    local status=self:status();if not status.catalog_available then return nil,status.reason or 'World Builder catalog API is unavailable' end
    local source,err=self:_read_list(definition);if not source then return nil,err end
    local values={}
    for index,entry in pairs(source.data) do
        if type(entry)=='table' then
            local data=entry.data or {};local path=type(data)=='table' and tostring(data.spawnData or '') or ''
            local name=tostring(entry.fileName or entry.name or basename(path) or ('Resource '..tostring(index)))
            table.insert(values,{index=index,name=name,path=path,entry=entry,definition=definition,module_path=source.module_path,is_paths=source.is_paths})
        end
    end
    table.sort(values,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    self.cache[key]=values;self.last_error=nil
    self:_log('info','catalog_loaded',{key=key,count=#values})
    return values
end

function WorldBuilder:search(key,query,limit,force)
    local values,err=self:load_catalog(key,force);if not values then return nil,err end
    query=string.lower(Util.trim(query or ''));limit=math.max(1,math.min(tonumber(limit) or 60,250))
    local matches={};local total=0
    for _,resource in ipairs(values) do
        local hit=query=='' or string.find(string.lower(resource.name..' '..resource.path),query,1,true)~=nil
        if hit then total=total+1;if #matches<limit then table.insert(matches,resource) end end
    end
    self.last_query={key=key,query=query,total=total,shown=#matches}
    self:_log('info','catalog_search',{key=key,query=query,total=total,shown=#matches})
    return {items=matches,total=total,shown=#matches,catalog_count=#values,key=key,query=query}
end

function WorldBuilder:resource_to_asset(resource)
    if not resource or not resource.definition or not resource.entry then return nil,'invalid World Builder resource' end
    local definition=resource.definition;local entry=Util.deepcopy(resource.entry)
    local template=resource.path or ''
    return {
        name=resource.name,category='Game / '..definition.category,kind=definition.kind,template=template,
        layer=definition.layer,tags={'game-resource','world-builder',definition.key},
        metadata={world_builder={definition_key=definition.key,category=definition.category,variant=definition.variant,class_module=definition.class_module,module_path=resource.module_path,entry=entry,resource_name=resource.name,resource_path=template,apply_scale=resource.is_paths==true}},
        notes='Imported from the World Builder game-resource catalog.',
    }
end

function WorldBuilder:find_project_asset(resource)
    if not resource then return nil end
    local key=resource.definition and resource.definition.key;local name=resource.name;local path=resource.path
    for _,asset in ipairs(self.app.model.data.assets or {}) do
        local wb=asset.metadata and asset.metadata.world_builder
        if wb and wb.definition_key==key and wb.resource_name==name and tostring(wb.resource_path or '')==tostring(path or '') then return asset end
    end
    return nil
end

function WorldBuilder:import_resource(resource)
    local existing=self:find_project_asset(resource);if existing then return existing,'Already in Project Assets' end
    local value,err=self:resource_to_asset(resource);if not value then return nil,err end
    local asset=self.app.model:add_asset(value);self.app:mark_dirty()
    self:_log('info','resource_imported',{asset_id=asset.id,key=resource.definition.key,name=resource.name,path=resource.path})
    return asset
end

function WorldBuilder:import_many(resources)
    local values={};local skipped=0
    for _,resource in ipairs(resources or {}) do
        if self:find_project_asset(resource) then skipped=skipped+1 else
            local value=self:resource_to_asset(resource);if value then table.insert(values,value) end
        end
    end
    local added=self.app.model:add_assets(values);if #added>0 then self.app:mark_dirty() end
    self:_log('info','resource_batch_imported',{added=#added,skipped=skipped})
    return {assets=added,added=#added,skipped=skipped}
end

-- Resolve an offline catalog record ({category,variant,spawn_data,name,file_name})
-- to the matching entry in World Builder's loaded catalog, then register it as
-- a project asset. The live entry and class are WB's own; nothing is built from
-- the record itself, so a stale catalog cannot produce an unspawnable asset.
function WorldBuilder:import_catalog_record(record)
    if type(record)~='table' then return nil,'catalog record is required' end
    local definition
    for _,value in ipairs(DEFINITIONS) do
        if value.category==record.category and value.variant==record.variant then definition=value;break end
    end
    if not definition then return nil,'No LocationStudio World Builder definition for '..tostring(record.category)..'/'..tostring(record.variant) end
    local values,err=self:load_catalog(definition.key);if not values then return nil,err end
    local path=string.lower(tostring(record.spawn_data or ''))
    local names={[string.lower(tostring(record.name or ''))]=true,[string.lower(tostring(record.file_name or ''))]=true}
    names['']=nil
    local match
    for _,resource in ipairs(values) do
        if path~='' and string.lower(resource.path)==path then match=resource;break end
        if path=='' and (names[string.lower(resource.name)] or names[string.lower(tostring(resource.entry and resource.entry.name or ''))]) then match=resource;break end
    end
    if not match then
        return nil,'Not found in the loaded World Builder '..definition.label..' catalog: '..tostring(record.spawn_data~='' and record.spawn_data or record.name)..'. Rebuild the offline catalog if World Builder was updated.'
    end
    local asset,note=self:import_resource(match)
    if not asset then return nil,note end
    return {asset=asset,already_registered=note~=nil,definition_key=definition.key}
end

-- Build the same zero-transform favorite payload World Builder creates from
-- a Spawn New entry. The live catalog/class remains authoritative; this only
-- serializes default data and never calls spawnNew or creates a world object.
function WorldBuilder:prepare_favorite_record(record,name)
    if type(record)~='table' then return nil,'catalog record is required' end
    local definition
    for _,value in ipairs(DEFINITIONS) do
        if value.category==record.category and value.variant==record.variant then definition=value;break end
    end
    if not definition then return nil,'No LocationStudio World Builder definition for '..tostring(record.category)..'/'..tostring(record.variant) end
    local values,err=self:load_catalog(definition.key);if not values then return nil,err end
    local path=string.lower(tostring(record.spawn_data or ''))
    local wanted=string.lower(tostring(record.name or record.file_name or ''))
    local match
    for _,resource in ipairs(values) do
        if path~='' and string.lower(resource.path)==path then match=resource;break end
        if path=='' and wanted~='' and string.lower(resource.name)==wanted then match=resource;break end
    end
    if not match then return nil,'Not found in the loaded World Builder '..definition.label..' catalog: '..tostring(record.spawn_data or record.name) end
    local ok,payload=xpcall(function()
        local spawnable=match.entry and match.entry.data and self.class_cache[definition.key]
        if not spawnable then error('World Builder did not return a usable live spawn class') end
        spawnable=spawnable:new()
        if type(spawnable.loadSpawnData)~='function' or type(spawnable.save)~='function' then error('World Builder spawn class cannot serialize favorites') end
        spawnable:loadSpawnData(match.entry.data,Vector4.new(0,0,0,0),EulerAngles.new(0,0,0))
        local saved=spawnable:save()
        local empty_spawn_data_ok=definition.key=='area_ambient' or definition.key=='area_outline'
        if type(saved)~='table' or (not empty_spawn_data_ok and tostring(saved.spawnData or '')=='') then error('World Builder returned incomplete favorite spawn data') end
        local data={
            name=Util.trim(name or match.name),modulePath='modules/classes/editor/spawnableElement',
            headerOpen=false,propertyHeaderStates={},visible=true,hiddenByParent=false,
            expandable=false,selected=false,isUsingSpawnables=true,childs={},
            transformExpanded=true,rotationRelative=false,scaleLocked=true,rotationLocked=false,
            randomizationSettings={probability=0.5,randomizeRotation=false,randomizeRotationAxis=2,randomizeAppearance=false},
            pos={x=0,y=0,z=0,w=0},applyRotationWhenDropped=true,
            spawnable=saved,
        }
        if data.name=='' then data.name=match.name end
        return {name=data.name,icon='',tags={},data=data,resource={category=definition.category,variant=definition.variant,module_path=match.module_path,spawn_data=match.path}}
    end,function(e) return debug and debug.traceback and debug.traceback(tostring(e),2) or tostring(e) end)
    if not ok then return nil,tostring(payload) end
    return payload
end

function WorldBuilder:class_for(metadata)
    local wb=metadata and metadata.world_builder or metadata
    if not wb then return nil,'World Builder class metadata is missing' end
    local key=wb.definition_key
    if not key and wb.category and wb.variant then
        for _,definition in ipairs(DEFINITIONS) do
            if definition.category==wb.category and definition.variant==wb.variant then key=definition.key;break end
        end
    end
    local definition=key and BY_KEY[key]
    if not definition then return nil,'Unknown World Builder resource definition: '..tostring(key) end
    if self.class_cache[key] then return self.class_cache[key] end
    -- CET resolves `require()` relative to the calling mod. Requiring World
    -- Builder's private class module here therefore fails in the real game.
    -- The active public resource list already owns the exact loaded class
    -- object that spawnNew expects, so resolve and cache that object instead.
    local source,err=self:_read_list(definition)
    if not source then return nil,err end
    return source.class
end

return WorldBuilder
