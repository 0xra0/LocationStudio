local Util=require('modules/util')
local ViewportTools=require('modules/viewport_tools')

-- VFX / particle editor. Every placeable effect comes from World Builder's
-- loaded Particles (worldStaticParticleNode) and Effects (worldEffectNode)
-- catalogs; categories are keyword filters over those real catalog rows and
-- never invent depot paths.
local Vfx={};Vfx.__index=Vfx

local PREVIEW_ID='__vfx_preview'
local FOLLOW_INTERVAL=0.1

local BACKENDS={
    particle={key='particle',label='Particles',category='Deco',variant='Particles',module_path='visual/particle',class_module='modules/classes/spawn/visual/particle',kind='particle',node='worldStaticParticleNode'},
    effect={key='effect',label='Effects',category='Deco',variant='Effects',module_path='visual/effect',class_module='modules/classes/spawn/visual/effect',kind='effect',node='worldEffectNode'},
}
local BACKEND_ORDER={'particle','effect'}

-- Matched as plain lower-case substrings of the resource name and path.
local CATEGORIES={
    {id='smoke',name='Smoke',keywords={'smoke','smk','fumes','smolder','smoulder'}},
    {id='steam',name='Steam / vapor',keywords={'steam','vapor','vapour','mist','exhaust'}},
    {id='sparks',name='Sparks',keywords={'spark','weld'}},
    {id='hologram',name='Holograms',keywords={'holo'}},
    {id='fire',name='Fire',keywords={'fire','flame','burn','ember','torch','candle'}},
    {id='dust',name='Dust / debris',keywords={'dust','debris','sand','dirt','ash'}},
    {id='leak',name='Leaks / liquids',keywords={'leak','drip','spill','fluid','water','oil','splash','puddle'}},
    {id='electric',name='Electrical',keywords={'electr','zap','lightning','short_circuit','shortcircuit'}},
    {id='weather',name='Weather / ambient',keywords={'rain','snow','leaves','insect','flies','bugs','pollen'}},
}
local CATEGORY_BY_ID={};for _,c in ipairs(CATEGORIES) do CATEGORY_BY_ID[c.id]=c end

local function classify(text)
    text=string.lower(tostring(text or ''))
    local out={}
    for _,category in ipairs(CATEGORIES) do
        for _,keyword in ipairs(category.keywords) do
            if string.find(text,keyword,1,true) then out[#out+1]=category.id;break end
        end
    end
    if #out==0 then out[1]='other' end
    return out
end

local function has(list,value) for _,v in ipairs(list or {}) do if v==value then return true end end;return false end

local function clean_scale(value,base)
    if value==nil then value=base end
    if value==nil then return {x=1,y=1,z=1} end
    if type(value)=='number' or type(value)=='string' then local n=tonumber(value);if not n then return nil,'scale must be a number or {x,y,z}' end;value={x=n,y=n,z=n} end
    if type(value)~='table' then return nil,'scale must be a number or {x,y,z}' end
    local out={}
    for _,axis in ipairs({'x','y','z'}) do
        local n=tonumber(value[axis]);if n==nil and base then n=tonumber(base[axis]) end
        if not n or n<0.01 or n>100 then return nil,'scale.'..axis..' must be between 0.01 and 100' end
        out[axis]=n
    end
    return out
end

local function clean_rotation(args,base)
    base=base or {roll=0,pitch=0,yaw=0}
    local source=type(args.rotation)=='table' and args.rotation or args
    local out={}
    for _,axis in ipairs({'roll','pitch','yaw'}) do
        local raw=source[axis];if raw==nil then raw=base[axis] end
        local n=tonumber(raw or 0);if not n then return nil,axis..' must be a number of degrees' end
        out[axis]=n
    end
    return out
end

local function clean_emission(value,base)
    if value==nil then value=base end
    if value==nil then return 1 end
    local n=tonumber(value);if not n or n<0 or n>9999 then return nil,'emission_rate must be between 0 and 9999' end
    return n
end

function Vfx.new(app)
    local self=setmetatable({app=app,preview=nil,follow_elapsed=0,last_error=nil},Vfx)
    -- Runtime handles survive a CET script reload, but a preview is never saved;
    -- remove an orphaned one left by the previous module instance.
    local shell=app.runtime_shell
    if shell and shell.handles and shell.handles[PREVIEW_ID] then
        local ok=pcall(function() shell:despawn({id=PREVIEW_ID,runtime={backend='world_builder'}}) end)
        if not ok then shell.handles[PREVIEW_ID]=nil end
    end
    return self
end

function Vfx:categories()
    local out={}
    for _,c in ipairs(CATEGORIES) do out[#out+1]={id=c.id,name=c.name,keywords=Util.deepcopy(c.keywords)} end
    out[#out+1]={id='other',name='Other / unclassified',keywords={}}
    return out
end

function Vfx:backends()
    local out={};for _,key in ipairs(BACKEND_ORDER) do local b=BACKENDS[key];out[#out+1]={id=key,label=b.label,node=b.node} end;return out
end

function Vfx:_blocked()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

local function wanted_backends(backend)
    if backend==nil or backend=='' or backend=='all' then return BACKEND_ORDER end
    if BACKENDS[backend] then return {backend} end
    return nil
end

-- Search both loaded catalogs. `category` narrows to one keyword category;
-- totals are counted before `limit` so the UI can say how many were hidden.
function Vfx:search(args)
    args=args or {}
    if not self.app.world_builder then return nil,'World Builder backend is unavailable' end
    local backends=wanted_backends(args.backend);if not backends then return nil,'backend must be particle, effect or all' end
    local category=args.category;if category=='' or category=='all' then category=nil end
    if category and category~='other' and not CATEGORY_BY_ID[category] then return nil,'unknown VFX category: '..tostring(category) end
    local query=string.lower(Util.trim(args.query or ''))
    local limit=math.max(1,math.min(math.floor(tonumber(args.limit) or 80),500))
    local items,total,errors,counts,catalog={},0,{},{},{}
    for _,key in ipairs(backends) do
        local values,err=self.app.world_builder:load_catalog(key,args.refresh==true)
        if not values then errors[key]=tostring(err)
        else
            catalog[key]=#values
            for _,resource in ipairs(values) do
                local text=resource.name..' '..tostring(resource.path or '')
                if query=='' or string.find(string.lower(text),query,1,true) then
                    local cats=classify(text)
                    for _,c in ipairs(cats) do counts[c]=(counts[c] or 0)+1 end
                    if not category or has(cats,category) then
                        total=total+1
                        if #items<limit then items[#items+1]={name=resource.name,path=resource.path,backend=key,node=BACKENDS[key].node,categories=cats,category=cats[1]} end
                    end
                end
            end
        end
    end
    if next(catalog)==nil then
        local first=errors[backends[1]] or 'no VFX catalog is available'
        return nil,'World Builder VFX catalogs are unavailable: '..first
    end
    return {items=items,total=total,shown=#items,query=query,category=category or 'all',category_counts=counts,catalog_counts=catalog,errors=next(errors) and errors or nil}
end

-- Resolve an exact catalog row. With resource_path the row must exist in the
-- loaded catalog; otherwise the first search hit for query/category is used.
function Vfx:_resolve(args)
    local backends=wanted_backends(args.backend);if not backends then return nil,'backend must be particle, effect or all' end
    local path=args.resource_path and Util.trim(args.resource_path) or ''
    if path~='' then
        local wanted=string.lower(path);local errors={}
        for _,key in ipairs(backends) do
            local values,err=self.app.world_builder:load_catalog(key,false)
            if values then
                for _,resource in ipairs(values) do if string.lower(tostring(resource.path or ''))==wanted then return {name=resource.name,path=resource.path,backend=key,categories=classify(resource.name..' '..resource.path)} end end
            else errors[#errors+1]=key..': '..tostring(err) end
        end
        if #errors==#backends then return nil,'World Builder VFX catalogs are unavailable: '..table.concat(errors,'; ') end
        return nil,'resource_path is not in the loaded World Builder Particles/Effects catalog: '..path
    end
    local result,err=self:search({query=args.query,category=args.category,backend=args.backend,limit=1})
    if not result then return nil,err end
    local item=result.items[1];if not item then return nil,'no VFX resource matches that search; search the catalog and pass an exact resource_path' end
    return item
end

-- Serialize the chosen row through World Builder's own class (the same
-- zero-transform favorite payload WB writes), then apply VFX settings.
function Vfx:_entry(resource,name,config)
    local backend=BACKENDS[resource.backend]
    local payload,err=self.app.world_builder:prepare_favorite_record({category=backend.category,variant=backend.variant,spawn_data=resource.path,name=resource.name},name)
    if not payload then return nil,err end
    local saved=payload.data and payload.data.spawnable
    if type(saved)~='table' then return nil,'World Builder returned no serialized '..backend.label..' data' end
    if resource.backend=='particle' then saved.emissionRate=config.emission_rate;saved.respawnOnMove=config.respawn_on_move==true end
    return {name=payload.name,fileName=payload.name,data=saved}
end

function Vfx:_transform(args)
    if type(args.transform)=='table' and type(args.transform.position)=='table' then
        local t=Util.deepcopy(args.transform);local rotation,err=clean_rotation(args,t.rotation);if not rotation then return nil,err end
        t.rotation=rotation;return t,'explicit'
    end
    local position,source,normal
    if args.source=='player' then
        local t,err=self.app.game:capture_transform();if not t then return nil,err end;position=t.position;source='player'
    elseif args.source=='origin' then
        local premise=self.app.model:get_premise(args.premise_id or self.app.selected_premise_id);if not premise then return nil,'select a premise or provide a transform' end
        position=Util.deepcopy(premise.transform.position);source='premise_origin'
    else
        local hit,err=self.app.game:aim_point(args.distance or 10);if not hit then return nil,err end
        position=hit.position;source=hit.source or 'aim';normal=hit.normal
    end
    local base={roll=0,pitch=0,yaw=0}
    if args.align_to_surface==true and normal then base=ViewportTools.surface_rotation(normal,tonumber(args.yaw) or 0) end
    local rotation,err=clean_rotation(args,base);if not rotation then return nil,err end
    return {position={x=position.x,y=position.y,z=position.z,w=1},rotation=rotation},source
end

function Vfx:_config(resource,args,base)
    base=base or {}
    local scale,err=clean_scale(args.scale,base.scale);if not scale then return nil,err end
    local config={backend=resource.backend,node=BACKENDS[resource.backend].node,resource_name=resource.name,resource_path=resource.path,
        category=args.category and args.category~='' and args.category~='all' and args.category or (resource.categories and resource.categories[1]) or base.category or 'other',
        categories=Util.deepcopy(resource.categories or base.categories or {'other'}),scale=scale,live_scale=false}
    if resource.backend=='particle' then
        config.emission_rate,err=clean_emission(args.emission_rate,base.emission_rate);if not config.emission_rate then return nil,err end
        if args.respawn_on_move~=nil then config.respawn_on_move=args.respawn_on_move==true else config.respawn_on_move=base.respawn_on_move==true end
    end
    return config
end

local function wb_metadata(resource,entry)
    local b=BACKENDS[resource.backend]
    return {definition_key=b.key,category=b.category,variant=b.variant,class_module=b.class_module,module_path=b.module_path,resource_name=resource.name,resource_path=resource.path,entry=entry,apply_scale=false}
end

local SCALE_NOTE='Scale is saved and written to the native node by the Build Mod VFX stage. World Builder spawns particle/effect previews at 1:1, so the live preview does not show scale.'

function Vfx:create(args)
    args=args or {}
    if not self.app.world_builder then return nil,'World Builder VFX backend is unavailable' end
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local resource,err=self:_resolve(args);if not resource then return nil,err end
    local config;config,err=self:_config(resource,args);if not config then return nil,err end
    local transform,source=self:_transform(args);if not transform then return nil,source end
    local name=Util.trim(args.name or '')~='' and Util.trim(args.name) or resource.name
    local entry;entry,err=self:_entry(resource,name,config);if not entry then return nil,err end
    self.app.model:snapshot()
    local object=self.app.model:add_object({premise_id=args.premise_id or self.app.selected_premise_id,room_id=args.room_id or self.app.selected_room_id,
        name=name,kind=BACKENDS[resource.backend].kind,template='',layer='decoration',transform=transform,size={x=1,y=1,z=1},enabled=true,
        metadata={source='LocationStudio VFX editor',vfx=config,world_builder=wb_metadata(resource,entry)}})
    if not object then return nil,'project model rejected the VFX object' end
    self.app.selection:set('object',object.id);self.app:mark_dirty()
    local result={object=object,backend=resource.backend,resource_path=resource.path,placement_source=source,spawned=false,scale_note=SCALE_NOTE}
    if source=='forward_fallback' then result.warning='No surface was hit; the effect was placed along the camera ray at the requested distance.' end
    if args.spawn~=false then
        local id,spawn_err=self.app.placement:spawn(object)
        if id then result.spawned=true else self.last_error=tostring(spawn_err);result.spawn_error=tostring(spawn_err) end
    end
    return result
end

function Vfx:list(args)
    args=args or {}
    local out={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        local cfg=o.metadata and o.metadata.vfx
        if cfg and (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) and (not args.category or args.category=='' or args.category=='all' or has(cfg.categories,args.category) or cfg.category==args.category) then
            out[#out+1]={id=o.id,name=o.name,premise_id=o.premise_id,room_id=o.room_id,backend=cfg.backend,category=cfg.category,resource_path=cfg.resource_path,
                transform=Util.deepcopy(o.transform),scale=Util.deepcopy(cfg.scale),emission_rate=cfg.emission_rate,respawn_on_move=cfg.respawn_on_move,
                spawned=o.runtime and o.runtime.spawned==true or false,enabled=o.enabled~=false}
        end
    end
    return {items=out,count=#out}
end

local function live_entity(handle)
    if not handle then return nil end
    local ok,entity=pcall(function()
        if handle.spawnable and type(handle.spawnable.getEntity)=='function' then return handle.spawnable:getEntity() end
        if type(handle.getEntity)=='function' then return handle:getEntity() end
    end)
    return ok and entity or nil
end

-- Mirror World Builder's own particle editor: set emissionRate on the live
-- entParticlesComponent named "particle" instead of respawning.
local function set_live_emission(handle,rate)
    local entity=live_entity(handle);if not entity then return false end
    local ok,done=pcall(function()
        local component=entity:FindComponentByName('particle');if not component then return false end
        component.emissionRate=rate
        if handle.spawnable then handle.spawnable.emissionRate=rate end
        return true
    end)
    return ok and done==true
end

function Vfx:update(object_id,patch)
    patch=patch or {}
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local object=self.app.model:get_object(object_id);if not object then return nil,'VFX object not found' end
    local base=object.metadata and object.metadata.vfx;local wb=object.metadata and object.metadata.world_builder
    if not base or not wb then return nil,'selected object is not a LocationStudio VFX object' end
    if object.locked then return nil,'VFX object is locked; unlock it before editing' end
    local resource={name=base.resource_name,path=base.resource_path,backend=base.backend,categories=base.categories}
    local swap=patch.resource_path and Util.trim(patch.resource_path)~='' and string.lower(Util.trim(patch.resource_path))~=string.lower(tostring(base.resource_path or ''))
    if swap then local err;resource,err=self:_resolve({resource_path=patch.resource_path,backend=patch.backend});if not resource then return nil,err end end
    local config,err=self:_config(resource,{scale=patch.scale,category=patch.category or (not swap and base.category or nil),emission_rate=patch.emission_rate,respawn_on_move=patch.respawn_on_move},swap and {scale=base.scale} or base)
    if not config then return nil,err end
    local rotation_patch=type(patch.rotation)=='table' or patch.roll~=nil or patch.pitch~=nil or patch.yaw~=nil
    local rotation;if rotation_patch then rotation,err=clean_rotation(patch,object.transform.rotation);if not rotation then return nil,err end end
    local entry=wb.entry
    if swap or type(entry)~='table' or type(entry.data)~='table' then
        entry,err=self:_entry(resource,object.name,config);if not entry then return nil,err end
    elseif resource.backend=='particle' then entry.data.emissionRate=config.emission_rate;entry.data.respawnOnMove=config.respawn_on_move==true end
    local emission_changed=resource.backend=='particle' and not swap and base.emission_rate~=config.emission_rate
    local respawn_changed=resource.backend=='particle' and not swap and (base.respawn_on_move==true)~=(config.respawn_on_move==true)
    self.app.model:snapshot()
    object.metadata.vfx=config;object.metadata.world_builder=wb_metadata(resource,entry);object.kind=BACKENDS[resource.backend].kind
    if rotation then object.transform.rotation=rotation end
    object.updated_at=Util.now_iso();self.app:mark_dirty()
    local result={object=object,respawned=false,live_updated=false,scale_note=SCALE_NOTE}
    if not self.app.placement:is_tracked(object) then return result end
    local handle=self.app.runtime_shell and self.app.runtime_shell.handles[object.id]
    local needs_respawn=swap or respawn_changed or (rotation and config.respawn_on_move==true)
    if not needs_respawn and emission_changed then
        if set_live_emission(handle,config.emission_rate) then result.live_updated=true else needs_respawn=true end
    end
    if not needs_respawn and rotation then
        local ok,apply_err=self.app.runtime_shell:update_object(object);if ok then result.live_updated=true else needs_respawn=true;result.warning='live rotation failed: '..tostring(apply_err) end
    end
    if needs_respawn then
        local removed,remove_err=self.app.placement:despawn(object)
        if not removed then result.warning='settings saved, but the old effect could not be removed: '..tostring(remove_err);return result end
        local id,spawn_err=self.app.placement:spawn(object)
        if id then result.respawned=true else self.last_error=tostring(spawn_err);result.warning='settings saved, but effect respawn failed: '..tostring(spawn_err) end
    end
    return result
end

-- Live preview: one transient World Builder node that is never written to the
-- project. It can follow the camera aim point until committed or cleared.
function Vfx:preview_status()
    local p=self.preview
    if not p then return {active=false,last_error=self.last_error} end
    return {active=true,backend=p.resource.backend,resource_name=p.resource.name,resource_path=p.resource.path,follow=p.follow,align_to_surface=p.align_to_surface,
        transform=Util.deepcopy(p.object.transform),placement_source=p.source,config=Util.deepcopy(p.config),spawned=p.object.runtime and p.object.runtime.spawned==true or false}
end

function Vfx:_spawn_preview(resource,config,transform)
    local entry,err=self:_entry(resource,resource.name,config);if not entry then return nil,err end
    local object={id=PREVIEW_ID,name='VFX preview: '..resource.name,kind=BACKENDS[resource.backend].kind,template='',size={x=1,y=1,z=1},enabled=true,
        transform=transform,metadata={vfx=config,world_builder=wb_metadata(resource,entry)},runtime={}}
    local id;id,err=self.app.runtime_shell:spawn(object);if not id then return nil,err end
    return object
end

function Vfx:preview_start(args)
    args=args or {}
    if not self.app.world_builder or not self.app.runtime_shell then return nil,'World Builder VFX backend is unavailable' end
    local blocked=self:_blocked();if blocked then return nil,blocked end
    local resource,err=self:_resolve(args);if not resource then return nil,err end
    local config;config,err=self:_config(resource,args);if not config then return nil,err end
    local transform,source=self:_transform(args);if not transform then return nil,source end
    local cleared,clear_err=self:preview_clear();if not cleared then return nil,'previous VFX preview could not be removed: '..tostring(clear_err) end
    local object;object,err=self:_spawn_preview(resource,config,transform)
    if not object then self.last_error=tostring(err);return nil,'VFX preview spawn failed: '..tostring(err) end
    self.preview={object=object,resource=resource,config=config,source=source,follow=args.follow~=false and args.source~='player' and args.source~='origin' and args.transform==nil,
        align_to_surface=args.align_to_surface==true,distance=tonumber(args.distance) or 10,rotation=Util.deepcopy(transform.rotation)}
    self.follow_elapsed=0;self.last_error=nil
    local status=self:preview_status();status.scale_note=SCALE_NOTE
    if source=='forward_fallback' then status.warning='No surface was hit; the preview is on the camera ray at the requested distance.' end
    return status
end

function Vfx:preview_update(args)
    args=args or {}
    local p=self.preview;if not p then return nil,'no VFX preview is active' end
    if args.follow~=nil then p.follow=args.follow==true end
    if args.align_to_surface~=nil then p.align_to_surface=args.align_to_surface==true end
    if args.distance~=nil then p.distance=tonumber(args.distance) or p.distance end
    local resource=p.resource
    local swap=args.resource_path and Util.trim(args.resource_path)~='' and string.lower(Util.trim(args.resource_path))~=string.lower(resource.path)
    if swap then local err;resource,err=self:_resolve({resource_path=args.resource_path,backend=args.backend});if not resource then return nil,err end end
    local config,err=self:_config(resource,{scale=args.scale,category=args.category,emission_rate=args.emission_rate,respawn_on_move=args.respawn_on_move},swap and {scale=p.config.scale} or p.config)
    if not config then return nil,err end
    local rotation_patch=type(args.rotation)=='table' or args.roll~=nil or args.pitch~=nil or args.yaw~=nil
    if rotation_patch then local rotation;rotation,err=clean_rotation(args,p.rotation);if not rotation then return nil,err end;p.rotation=rotation;p.object.transform.rotation=Util.deepcopy(rotation) end
    if type(args.transform)=='table' and type(args.transform.position)=='table' then p.object.transform.position=Util.deepcopy(args.transform.position);p.follow=false;p.source='explicit' end
    local respawn=swap or (resource.backend=='particle' and (p.config.respawn_on_move==true)~=(config.respawn_on_move==true))
    local emission_changed=not swap and resource.backend=='particle' and p.config.emission_rate~=config.emission_rate
    p.resource=resource;p.config=config
    if not respawn and emission_changed and not set_live_emission(self.app.runtime_shell.handles[PREVIEW_ID],config.emission_rate) then respawn=true end
    if respawn then
        local transform=Util.deepcopy(p.object.transform)
        local removed,remove_err=self.app.runtime_shell:despawn(p.object);if not removed then return nil,'VFX preview could not be removed: '..tostring(remove_err) end
        local object;object,err=self:_spawn_preview(resource,config,transform)
        if not object then self.preview=nil;self.last_error=tostring(err);return nil,'VFX preview respawn failed: '..tostring(err) end
        p.object=object
    else
        p.object.metadata.vfx=config
        local ok,apply_err=self.app.runtime_shell:update_object(p.object,{silent=true});if not ok then return nil,'VFX preview update failed: '..tostring(apply_err) end
    end
    local status=self:preview_status();status.scale_note=SCALE_NOTE;return status
end

function Vfx:preview_clear()
    local p=self.preview;if not p then return true end
    local ok,err=self.app.runtime_shell:despawn(p.object)
    if not ok then self.last_error=tostring(err);return false,err end
    self.preview=nil;return true
end

function Vfx:preview_commit(args)
    args=args or {}
    local p=self.preview;if not p then return nil,'no VFX preview is active' end
    local create={resource_path=p.resource.path,backend=p.resource.backend,category=p.config.category,scale=args.scale or p.config.scale,
        emission_rate=args.emission_rate or p.config.emission_rate,respawn_on_move=p.config.respawn_on_move,
        transform=Util.deepcopy(p.object.transform),name=args.name,premise_id=args.premise_id,room_id=args.room_id,spawn=args.spawn}
    -- Remove the transient node before spawning the saved one so the committed
    -- effect is the only live instance at that position.
    local cleared,clear_err=self:preview_clear();if not cleared then return nil,'VFX preview could not be removed: '..tostring(clear_err) end
    local result,err=self:create(create);if not result then return nil,err end
    result.placement_source=p.source
    return result
end

function Vfx:update_tick(delta)
    local p=self.preview;if not p or not p.follow then return end
    self.follow_elapsed=self.follow_elapsed+(tonumber(delta) or 0)
    if self.follow_elapsed<FOLLOW_INTERVAL then return end
    self.follow_elapsed=0
    local hit=self.app.game:aim_point(p.distance);if not hit then return end
    local rotation=p.rotation
    if p.align_to_surface and hit.normal then local aligned=ViewportTools.surface_rotation(hit.normal,p.rotation.yaw);rotation={roll=aligned.roll,pitch=aligned.pitch,yaw=p.rotation.yaw} end
    p.object.transform={position={x=hit.position.x,y=hit.position.y,z=hit.position.z,w=1},rotation=Util.deepcopy(rotation)};p.source=hit.source or 'aim'
    local ok,err=self.app.runtime_shell:update_object(p.object,{silent=true})
    if not ok then self.last_error=tostring(err);p.follow=false end
end

Vfx.classify=classify
return Vfx
