local Util=require('modules/util')

-- Material library: material instances described in code. Each definition picks
-- a base material (preset or any .mt/.remt/.mi), sets textures and semantic
-- parameters (roughness, metallic, emissive, tint, tiling, UV scale), raw
-- parameter overrides and named variants. Build Mod turns every definition into
-- a real CMaterialInstance (.mi) resource; each variant becomes its own .mi
-- whose base material is the parent .mi, and an extra appearance on generated
-- meshes that use it.
--
-- Geometry refers to a definition as '@key' (or '@key:variant') in any
-- material slot. Definitions are stored in model.data.material_defs.
local Materials={};Materials.__index=Materials

-- Base-material presets. Parameter names are resolved by the build
-- (mcp_server/lsbuild/materials.py), which owns the name/type tables.
local PRESETS={
    {id='metal_base',label='PBR (metal_base)',base='base\\materials\\metal_base.remt',textures={'base_color','normal','roughness','metalness','emissive','mask'},
        params={'tint','roughness','metallic','roughness_scale','metallic_scale','normal_strength','emissive_color','emissive_ev','alpha_threshold'}},
    {id='glass',label='Glass',base='base\\materials\\glass.mt',textures={'normal','mask'},params={'tint','roughness','ior','opacity','normal_strength'}},
    {id='multilayered',label='Multilayered',base='engine\\materials\\multilayered.mt',textures={'mlsetup','mlmask','normal'},params={}},
    {id='custom',label='Custom base material',base=nil,textures={},params={}},
}
local PRESET_BY_ID={};for _,p in ipairs(PRESETS) do PRESET_BY_ID[p.id]=p end

local SCALARS={roughness={0,1},metallic={0,1},roughness_scale={0,10},metallic_scale={0,10},normal_strength={0,10},emissive_ev={-10,30},
    alpha_threshold={0,1},ior={1,3},opacity={0,1}}
local COLORS={tint=4,emissive_color=4}
local TEXTURES={base_color='xbm',normal='xbm',roughness='xbm',metalness='xbm',emissive='xbm',mask='xbm',mlsetup='mlsetup',mlmask='mlmask'}
local IMAGE_EXT={png=true,tga=true,dds=true,jpg=true,jpeg=true}
local OVERRIDE_TYPES={Float=true,Int32=true,Bool=true,Color=true,Vector4=true,texture=true,mlsetup=true,mlmask=true,CName=true}
local KEY='^[%a_][%w_]*$'
local MAX_VARIANTS=16

local function num(v) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return nil end;return v end
local function ext(path) return tostring(path):lower():match('%.([%w]+)$') end
local function depot_ok(path) return type(path)=='string' and path~='' and not path:find('[/:]') and not path:find('%.%.') end
local function slug(s) return (tostring(s or 'material'):lower():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')) end

function Materials.new(app) return setmetatable({app=app},Materials) end
function Materials.presets() return Util.deepcopy(PRESETS) end

function Materials:settings()
    local s=self.app.model.data.settings;s.materials=type(s.materials)=='table' and s.materials or {}
    local m=s.materials;m.root=type(m.root)=='string' and m.root~='' and m.root or 'mod\\locationstudio\\materials'
    return m
end

local function clean_color(v,where)
    if type(v)~='table' then return nil,where..' must be [r, g, b] or [r, g, b, a]' end
    local out={}
    for i=1,4 do
        local x=v[i];if x==nil and i==4 then x=1 end
        x=num(x);if not x or x<0 or x>(i==4 and 1 or 16) then return nil,where..' needs components 0-16 (alpha 0-1)' end
        out[i]=x
    end
    if #v<3 or #v>4 then return nil,where..' must have 3 or 4 components' end
    return out
end

local function clean_texture(v,kind,where)
    if type(v)=='string' then
        if not depot_ok(v) or ext(v)~=kind then return nil,where..' must be a .'..kind..' depot path' end
        return v
    end
    if type(v)~='table' then return nil,where..' must be a depot path, {file=...} or {solid=[r,g,b,a]}' end
    local out={}
    if v.path~=nil then
        if not depot_ok(v.path) or ext(v.path)~='xbm' then return nil,where..'.path must be a .xbm depot path' end
        out.path=v.path
    end
    if kind~='xbm' then return nil,where..' must be a .'..kind..' depot path' end
    if v.file~=nil then
        if type(v.file)~='string' or not IMAGE_EXT[ext(v.file) or ''] then return nil,where..'.file must be a .png, .tga, .dds or .jpg image' end
        out.file=v.file
    elseif v.solid~=nil then
        local c,err=clean_color(v.solid,where..'.solid');if not c then return nil,err end
        for i=1,3 do if c[i]>1 then return nil,where..'.solid components must be 0-1' end end
        out.solid=c;out.size=math.floor(num(v.size) or 4);if out.size<1 or out.size>256 then return nil,where..'.size must be 1-256' end
    else return nil,where..' needs file or solid' end
    out.srgb=v.srgb;out.compression=type(v.compression)=='string' and v.compression or nil
    return out
end

-- Semantic parameters and textures (used for the definition and each variant).
local function clean_block(src,where,partial)
    src=type(src)=='table' and src or {}
    local params,textures,overrides={},{},{}
    for k,v in pairs(type(src.params)=='table' and src.params or {}) do
        if SCALARS[k] then
            local x=num(v);if not x or x<SCALARS[k][1] or x>SCALARS[k][2] then return nil,where..'params.'..k..' must be '..SCALARS[k][1]..'-'..SCALARS[k][2] end
            params[k]=x
        elseif COLORS[k] then local c,err=clean_color(v,where..'params.'..k);if not c then return nil,err end;params[k]=c
        elseif k=='tiling' or k=='uv_scale' then
            local u,vv
            if type(v)=='table' then u,vv=num(v[1]),num(v[2]) else u=num(v);vv=u end
            if not u or not vv or u<=0 or vv<=0 or u>1000 or vv>1000 then return nil,where..'params.'..k..' must be a positive number or [u, v]' end
            params[k]={u,vv}
        else return nil,where..'unknown parameter '..tostring(k)..' (use overrides for raw material parameters)' end
    end
    for k,v in pairs(type(src.textures)=='table' and src.textures or {}) do
        if not TEXTURES[k] then return nil,where..'unknown texture '..tostring(k) end
        local t,err=clean_texture(v,TEXTURES[k],where..'textures.'..k);if not t then return nil,err end
        textures[k]=t
    end
    for name,v in pairs(type(src.overrides)=='table' and src.overrides or {}) do
        if type(name)~='string' or not name:match('^[%a_][%w_]*$') then return nil,where..'override names must be material parameter names' end
        if type(v)~='table' or not OVERRIDE_TYPES[v.type] then return nil,where..'overrides.'..name..' needs {type = Float|Int32|Bool|Color|Vector4|texture|mlsetup|mlmask|CName, value}' end
        local value=v.value
        if v.type=='Float' or v.type=='Int32' then value=num(value);if not value then return nil,where..'overrides.'..name..' needs a number' end
        elseif v.type=='Bool' then value=value==true
        elseif v.type=='Color' or v.type=='Vector4' then local c,err=clean_color(value,where..'overrides.'..name);if not c then return nil,err end;value=c
        elseif v.type=='CName' then if type(value)~='string' then return nil,where..'overrides.'..name..' needs a string' end
        else local t,err=clean_texture(value,v.type=='texture' and 'xbm' or v.type,where..'overrides.'..name);if not t then return nil,err end;value=t end
        overrides[name]={type=v.type,value=value}
    end
    return {params=params,textures=textures,overrides=overrides}
end

-- Validate and normalize a definition (pure).
function Materials.normalize(def,settings)
    def=type(def)=='table' and def or {}
    local key=Util.trim(tostring(def.key or ''))
    if not key:match(KEY) or #key>64 then return nil,'key must be an identifier (letters, digits, _), used as @key' end
    local preset=def.preset or (def.base and 'custom') or 'metal_base'
    local p=PRESET_BY_ID[preset];if not p then return nil,'preset must be metal_base, glass, multilayered or custom' end
    local base=def.base or p.base
    if not depot_ok(base) or not ({mt=true,remt=true,mi=true})[ext(base) or ''] then return nil,'base must be a .mt, .remt or .mi depot path' end
    local root=(settings and settings.root) or 'mod\\locationstudio\\materials'
    local path=def.path or (root..'\\'..key..'.mi')
    if not depot_ok(path) or ext(path)~='mi' then return nil,'path must be a .mi depot path' end
    local block,err=clean_block(def,'')
    if not block then return nil,err end
    if p.id~='custom' then
        local allowed={};for _,k in ipairs(p.textures) do allowed[k]=true end
        for k in pairs(block.textures) do if not allowed[k] then return nil,'preset '..p.id..' has no '..k..' texture (use overrides or preset custom)' end end
        local okp={uv_scale=true,tiling=true};for _,k in ipairs(p.params) do okp[k]=true end
        for k in pairs(block.params) do if not okp[k] then return nil,'preset '..p.id..' has no '..k..' parameter (use overrides or preset custom)' end end
    else
        for k in pairs(block.params) do if k~='uv_scale' and k~='tiling' then return nil,'a custom base material only takes overrides (and uv_scale/tiling), not '..k end end
        if next(block.textures) then return nil,'a custom base material only takes overrides for textures' end
    end
    local out={key=key,name=Util.trim(tostring(def.name or ''))~='' and Util.trim(def.name) or key,preset=p.id,base=base,path=path,
        params=block.params,textures=block.textures,overrides=block.overrides,variants={},notes=type(def.notes)=='string' and def.notes or nil}
    local seen={}
    for i,v in ipairs(type(def.variants)=='table' and def.variants or {}) do
        if i>MAX_VARIANTS then return nil,'at most '..MAX_VARIANTS..' variants' end
        local name=type(v)=='table' and Util.trim(tostring(v.name or '')) or ''
        if not name:match('^[%l%d_]+$') or name=='default' or #name>32 then return nil,'variant '..i..' needs a lowercase name (letters, digits, _) other than default' end
        if seen[name] then return nil,'variant '..name..' is repeated' end;seen[name]=true
        local vb;vb,err=clean_block(v,'variant '..name..': ');if not vb then return nil,err end
        if vb.params.uv_scale or vb.params.tiling then return nil,'variant '..name..': uv_scale and tiling are baked into the mesh UVs and cannot change per variant' end
        if p.id=='custom' and (next(vb.textures) or next(vb.params)) then return nil,'variant '..name..': a custom base material only takes overrides' end
        out.variants[#out.variants+1]={name=name,params=vb.params,textures=vb.textures,overrides=vb.overrides,path=path:sub(1,-4)..'_'..name..'.mi'}
    end
    return out
end

local function registry(model) model.data.material_defs=model.data.material_defs or {};return model.data.material_defs end
function Materials:get(ref)
    ref=tostring(ref or ''):gsub('^@',''):gsub(':.*$','')
    for i,d in ipairs(registry(self.app.model)) do if d.id==ref or d.key==ref then return d,i end end
end

-- '@key' or '@key:variant' -> {path, key, variant}
function Materials:resolve(ref)
    if type(ref)~='string' or ref:sub(1,1)~='@' then return nil,'not a material reference' end
    local key,variant=ref:sub(2):match('^([^:]+):?(.*)$')
    local d=self:get(key or '');if not d then return nil,'unknown material @'..tostring(key) end
    if variant=='' then return {key=d.key,path=d.path,variant=nil} end
    for _,v in ipairs(d.variants) do if v.name==variant then return {key=d.key,path=v.path,variant=variant} end end
    return nil,'material @'..d.key..' has no variant '..variant
end

-- Objects and generated rooms that refer to a definition.
function Materials:users(key)
    local out={}
    local function refs(mat) for _,v in pairs(type(mat)=='table' and mat or {}) do if type(v)=='string' and v:sub(2):match('^([^:]+)')==key and v:sub(1,1)=='@' then return true end end end
    for _,o in ipairs(self.app.model.data.objects) do
        local proc=o.metadata and o.metadata.procedural
        if proc and refs((proc.material or {}).materials) then out[#out+1]={kind='object',id=o.id,name=o.name} end
    end
    return out
end

function Materials:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required and not app.authoring_plans.running then return 'Resolve authoring-plan recovery first' end
    return nil
end

function Materials:create(def)
    local busy=self:_busy();if busy then return nil,busy end
    local clean,err=Materials.normalize(def,self:settings());if not clean then return nil,err end
    if self:get(clean.key) then return nil,'a material with key '..clean.key..' already exists' end
    for _,d in ipairs(registry(self.app.model)) do
        if d.path:lower()==clean.path:lower() then return nil,'another material already writes '..clean.path end
    end
    clean.id=Util.make_id('material');clean.premise_id=type(def)=='table' and def.premise_id or nil
    clean.created_at=Util.now_iso();clean.updated_at=clean.created_at
    self.app.model:snapshot('Create material '..clean.key)
    table.insert(registry(self.app.model),clean)
    self.app.model:touch();self.app:mark_dirty()
    return Util.deepcopy(clean)
end

-- Patch keys replace the saved ones (params/textures/overrides/variants as whole tables).
function Materials:update(ref,patch)
    local busy=self:_busy();if busy then return nil,busy end
    local d,index=self:get(ref);if not d then return nil,'material not found' end
    patch=type(patch)=='table' and patch or {}
    local merged=Util.deepcopy(d)
    for k,v in pairs(patch) do if k~='id' and k~='key' then merged[k]=Util.deepcopy(v) end end
    if patch.base~=nil and patch.preset==nil and not PRESET_BY_ID[merged.preset] then merged.preset='custom' end
    if patch.path==nil and d.path==self:settings().root..'\\'..d.key..'.mi' then merged.path=nil end
    local clean,err=Materials.normalize(merged,self:settings());if not clean then return nil,err end
    for _,o in ipairs(registry(self.app.model)) do if o.id~=d.id and o.path:lower()==clean.path:lower() then return nil,'another material already writes '..clean.path end end
    -- Variants still used by geometry must survive.
    local kept={};for _,v in ipairs(clean.variants) do kept[v.name]=true end
    for _,o in ipairs(self.app.model.data.objects) do
        local proc=o.metadata and o.metadata.procedural
        for _,v in pairs(proc and type((proc.material or {}).materials)=='table' and proc.material.materials or {}) do
            local k,variant=tostring(v):match('^@([^:]+):(.+)$')
            if k==d.key and not kept[variant] then return nil,'variant '..variant..' is used by '..tostring(o.name)..'; reassign it first' end
        end
    end
    clean.id=d.id;clean.premise_id=patch.premise_id~=nil and patch.premise_id or d.premise_id;clean.created_at=d.created_at;clean.updated_at=Util.now_iso()
    self.app.model:snapshot('Update material '..d.key)
    registry(self.app.model)[index]=clean
    self.app.model:touch();self.app:mark_dirty()
    return Util.deepcopy(clean)
end

function Materials:delete(ref)
    local busy=self:_busy();if busy then return nil,busy end
    local d,index=self:get(ref);if not d then return nil,'material not found' end
    local users=self:users(d.key)
    if #users>0 then return nil,'material @'..d.key..' is used by '..#users..' object(s) (first: '..tostring(users[1].name)..'); reassign them first' end
    self.app.model:snapshot('Delete material '..d.key)
    table.remove(registry(self.app.model),index)
    self.app.model:touch();self.app:mark_dirty()
    return {deleted=d.key}
end

function Materials:list(args)
    args=args or {};local rows={}
    for _,d in ipairs(registry(self.app.model)) do
        if not args.premise_id or args.premise_id=='' or not d.premise_id or d.premise_id==args.premise_id then
            local tex=0;for _ in pairs(d.textures) do tex=tex+1 end
            local variants={};for _,v in ipairs(d.variants) do variants[#variants+1]=v.name end
            rows[#rows+1]={id=d.id,key=d.key,name=d.name,preset=d.preset,base=d.base,path=d.path,textures=tex,variants=variants,users=#self:users(d.key)}
        end
    end
    table.sort(rows,function(a,b) return a.key<b.key end)
    return {items=rows,count=#rows,settings=Util.deepcopy(self:settings())}
end

-- Assign a library material to a procedural object's slot (main/glass). One undo step.
function Materials:assign(object_id,slot,ref)
    if not self.app.procedural then return nil,'procedural geometry is unavailable' end
    local o=self.app.model:get_object(object_id);if not o or not (o.metadata and o.metadata.procedural) then return nil,'not a procedural object' end
    slot=slot or 'main';if slot~='main' and slot~='glass' then return nil,'slot must be main or glass' end
    if ref~=nil and ref~='' then local _,err=self:resolve(ref);if err then return nil,err end end
    local materials=Util.deepcopy((o.metadata.procedural.material or {}).materials or {})
    materials[slot]=(ref~='' and ref) or nil
    local r,err=self.app.procedural:update(o.id,{material={materials=materials}})
    if not r then return nil,err end
    return {object_id=o.id,slot=slot,material=ref}
end

function Materials:set_settings(patch)
    patch=patch or {}
    if patch.root~=nil then
        local root=Util.trim(tostring(patch.root)):gsub('/','\\'):gsub('\\+$','')
        if root=='' or not root:match('^[%w_\\%-]+$') then return nil,'root must be a depot folder such as mod\\mymod\\materials' end
        self.app.model:snapshot('Material settings');self:settings().root=root;self.app:mark_dirty()
    end
    return Util.deepcopy(self:settings())
end

Materials.PRESETS=PRESETS
return Materials
