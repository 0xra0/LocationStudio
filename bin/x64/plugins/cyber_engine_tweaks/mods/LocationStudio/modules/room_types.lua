local Util=require('modules/util')
local Surfaces=require('modules/surfaces')

-- Semantic room types. A room carries a type (clinic, office, storage, security,
-- maintenance, corridor, server_room, ... or a project's own) and inherits the
-- generation rules of that environment:
--   * spec     parametric room defaults (height, floor, ceiling, trim, lighting,
--              materials, collision); the room's own spec overrides them;
--   * traits   semantic surface traits every surface of the room carries;
--   * params   grammar variables its rules see (counter_surface = medical_surface);
--   * interior grammar rules that furnish the room once its doors are known
--              (modules/env_grammar.lua; furniture is kept out of doorways);
--   * populate placements on the room's semantic surfaces (modules/surfaces.lua).
-- Types extend each other (`extends`). Built-in types live in
-- grammars/room_types.json and interior rules in the room_interiors grammar;
-- project types (model.data.room_types) override built-ins of the same id.
local RoomTypes={};RoomTypes.__index=RoomTypes

local LIBRARY_PATH='grammars/room_types.json'
local ID='^[%l_][%l%d_]*$'
local RULE='^[%a_][%w_]*$'
local MAX_CHAIN=8
local FIELDS={id=true,name=true,description=true,extends=true,traits=true,tags=true,spec=true,params=true,interior=true,populate=true,inherit_populate=true,size=true,
    source=true,created_at=true,updated_at=true}
local ROOM_ONLY={width=true,length=true,depth=true,doors=true,windows=true,name=true,type=true,furnish=true}
local SIZE_KEYS={min_width=true,min_length=true,min_height=true,max_width=true,max_length=true,max_height=true}

RoomTypes.INTERIORS='room_interiors'
RoomTypes.ID=ID

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function is_list(t) return type(t)=='table' and (t[1]~=nil or next(t)==nil) end

-- Objects merge key by key (over wins); lists and values replace.
local function merge(base,over)
    if type(base)~='table' or type(over)~='table' or is_list(over) or is_list(base) and next(base)~=nil then return Util.deepcopy(over) end
    local out=Util.deepcopy(base)
    for k,v in pairs(over) do out[k]=type(v)=='table' and type(out[k])=='table' and not is_list(v) and not is_list(out[k]) and merge(out[k],v) or Util.deepcopy(v) end
    return out
end
RoomTypes.merge=merge

local function union(a,b)
    local out,seen={},{}
    for _,list in ipairs({a or {},b or {}}) do for _,v in ipairs(list) do if not seen[v] then seen[v]=true;out[#out+1]=v end end end
    return out
end

local function strings(v,what)
    if v==nil then return {} end
    if type(v)=='string' then v={v} end
    if type(v)~='table' then return nil,what..' must be a list of names' end
    local out={}
    for _,s in ipairs(v) do if type(s)~='string' or s=='' then return nil,what..' must be a list of names' end;out[#out+1]=s end
    return out
end

-- Validate one type document (not its parent chain).
function RoomTypes.check(doc)
    if type(doc)~='table' then return nil,'a room type must be an object' end
    if type(doc.id)~='string' or not doc.id:match(ID) then return nil,'a room type id uses lowercase letters, digits and _ (server_room)' end
    for k in pairs(doc) do if not FIELDS[k] then return nil,'room type '..doc.id..': unknown field '..tostring(k) end end
    if doc.name~=nil and type(doc.name)~='string' then return nil,'name must be text' end
    if doc.description~=nil and type(doc.description)~='string' then return nil,'description must be text' end
    if doc.extends~=nil then
        if type(doc.extends)~='string' or not doc.extends:match(ID) then return nil,'extends must be a room type id' end
        if doc.extends==doc.id then return nil,'a room type cannot extend itself' end
    end
    local _,err=strings(doc.tags,'tags');if err then return nil,err end
    if doc.traits~=nil then local opt;opt,err=Surfaces.normalize_option({traits=doc.traits});if err then return nil,'traits: '..err end;if not opt then return nil,'traits must be a list' end end
    if doc.spec~=nil then
        if type(doc.spec)~='table' or is_list(doc.spec) and next(doc.spec)~=nil then return nil,'spec must be an object of parametric room settings' end
        for k in pairs(doc.spec) do if ROOM_ONLY[k] then return nil,'spec cannot set '..k..' (it belongs to each room)' end end
        local RG=package.loaded['modules/room_generator'] or require('modules/room_generator')
        local probe=Util.deepcopy(doc.spec);probe.width=5;probe.length=5
        local ok,serr=RG.normalize(probe);if not ok then return nil,'spec: '..tostring(serr) end
    end
    if doc.params~=nil then
        if type(doc.params)~='table' or is_list(doc.params) and next(doc.params)~=nil then return nil,'params must be an object of variables' end
        for k in pairs(doc.params) do if type(k)~='string' or not k:match(RULE) then return nil,'param names must be identifiers: '..tostring(k) end end
    end
    if doc.interior~=nil and doc.interior~=false then
        local list=type(doc.interior)=='string' and {doc.interior} or doc.interior
        if type(list)~='table' then return nil,'interior must be a rule name, a list of rule names or false' end
        for _,r in ipairs(list) do if type(r)~='string' or not r:match(RULE) then return nil,'interior rules must be rule names: '..tostring(r) end end
    end
    if doc.populate~=nil then
        if type(doc.populate)~='table' then return nil,'populate must be a list of placements' end
        for i,e in ipairs(doc.populate) do
            if type(e)~='table' then return nil,'populate '..i..' must be an object' end
            local kind=e.kind or 'asset'
            if not Surfaces.KINDS[kind] then return nil,'populate '..i..': kind must be asset, procedural, decal, light, effect or marker' end
            local ok,kerr=Surfaces.check_kind(e);if not ok then return nil,'populate '..i..': '..kerr end
            local _,perr=Surfaces.placement_options(e);if perr then return nil,'populate '..i..': '..perr end
        end
    end
    if doc.inherit_populate~=nil and type(doc.inherit_populate)~='boolean' then return nil,'inherit_populate must be true or false' end
    if doc.size~=nil then
        if type(doc.size)~='table' then return nil,'size must be {min_width, min_length, min_height, max_width, max_length, max_height}' end
        for k,v in pairs(doc.size) do
            if not SIZE_KEYS[k] then return nil,'size: unknown key '..tostring(k) end
            if not num(v) or num(v)<0 then return nil,'size.'..k..' must be metres' end
        end
    end
    return true
end

-- Effective type: the chain from the root ancestor down to `id`, merged.
-- lookup(id) returns a type document.
function RoomTypes.resolve_with(id,lookup)
    if type(id)~='string' or id=='' then return nil,'room type must be an id' end
    local chain,seen={},{}
    local cur=id
    while cur do
        if seen[cur] then return nil,'room type inheritance cycle through '..cur end
        if #chain>=MAX_CHAIN then return nil,'room type '..id..' extends more than '..MAX_CHAIN..' levels' end
        local doc=lookup(cur)
        if not doc then return nil,#chain==0 and ('unknown room type: '..cur) or ('room type '..chain[1].id..' extends unknown type '..cur) end
        seen[cur]=true;table.insert(chain,1,doc);cur=doc.extends
    end
    local eff={id=id,chain={},traits={},tags={},spec={},params={},interior={},populate={},size={}}
    for _,d in ipairs(chain) do
        eff.chain[#eff.chain+1]=d.id
        eff.traits=union(eff.traits,type(d.traits)=='string' and {d.traits} or d.traits)
        eff.tags=union(eff.tags,type(d.tags)=='string' and {d.tags} or d.tags)
        if type(d.spec)=='table' then eff.spec=merge(eff.spec,d.spec) end
        for k,v in pairs(type(d.params)=='table' and d.params or {}) do eff.params[k]=Util.deepcopy(v) end
        if d.interior==false then eff.interior={}
        elseif d.interior~=nil then eff.interior=type(d.interior)=='string' and {d.interior} or Util.deepcopy(d.interior) end
        if d.inherit_populate==false then eff.populate={} end
        for _,e in ipairs(type(d.populate)=='table' and d.populate or {}) do eff.populate[#eff.populate+1]=Util.deepcopy(e) end
        for k,v in pairs(type(d.size)=='table' and d.size or {}) do eff.size[k]=num(v) end
    end
    local leaf=chain[#chain]
    eff.name=leaf.name or id;eff.description=leaf.description or ''
    return eff
end

-- A room spec with the type's defaults under it. The spec wins; traits add up.
function RoomTypes.apply_spec(spec,eff)
    spec=type(spec)=='table' and spec or {}
    local own=Util.deepcopy(spec)
    local out=merge(eff.spec or {},own)
    local traits=own.surfaces and own.surfaces.traits
    if type(traits)=='string' then traits={traits} end
    local all=union(eff.traits,type(traits)=='table' and traits or nil)
    if #all>0 then out.surfaces=type(out.surfaces)=='table' and out.surfaces or {};out.surfaces.traits=all end
    out.type=eff.id
    return out
end

-- Advisory size check: a list of warnings.
function RoomTypes.size_warnings(eff,width,length,height)
    local out={};local s=eff.size or {}
    local function check(v,lo,hi,what)
        if v and lo and v<lo-1e-6 then out[#out+1]=string.format('%s is %.2f m; a %s room is at least %.2f m',what,v,eff.id,lo) end
        if v and hi and v>hi+1e-6 then out[#out+1]=string.format('%s is %.2f m; a %s room is at most %.2f m',what,v,eff.id,hi) end
    end
    check(width,s.min_width,s.max_width,'width');check(length,s.min_length,s.max_length,'length');check(height,s.min_height,s.max_height,'height')
    return out
end

-- Built-in catalog (grammars/room_types.json), read once.
local BUILTIN
function RoomTypes.builtin()
    if BUILTIN then return BUILTIN end
    local out={schema={},types={}}
    local file=io.open(LIBRARY_PATH,'r')
    if file then
        local text=file:read('*a');file:close()
        local ok,doc=pcall(json.decode,text)
        if ok and type(doc)=='table' then
            out.schema=type(doc.schema)=='table' and doc.schema or {}
            for id,t in pairs(type(doc.types)=='table' and doc.types or {}) do if type(t)=='table' then t.id=t.id or id;out.types[t.id]=t end end
        end
    end
    BUILTIN=out
    return out
end
function RoomTypes.builtin_lookup() return function(id) return RoomTypes.builtin().types[id] end end

---------------------------------------------------------------------------
-- Project library and room assignment (instance methods)
---------------------------------------------------------------------------
function RoomTypes.new(app) return setmetatable({app=app},RoomTypes) end

local function project_list(model) model.data.room_types=type(model.data.room_types)=='table' and model.data.room_types or {};return model.data.room_types end
local function furnishings(model) model.data.room_furnishings=type(model.data.room_furnishings)=='table' and model.data.room_furnishings or {};return model.data.room_furnishings end

function RoomTypes:find(id)
    for i,t in ipairs(project_list(self.app.model)) do if t.id==id then return t,'project',i end end
    local b=RoomTypes.builtin().types[id];if b then return b,'builtin' end
end
function RoomTypes:lookup() return function(id) return (self:find(id)) end end
function RoomTypes:resolve(id) return RoomTypes.resolve_with(id,self:lookup()) end

-- Room spec with its type applied (spec.type set); untyped specs come back unchanged.
function RoomTypes:apply(spec)
    if type(spec)~='table' or spec.type==nil or spec.type==false or spec.type=='' then return spec end
    if type(spec.type)~='string' or not spec.type:match(ID) then return nil,'type must be a room type id (lowercase letters, digits and _)' end
    local eff,err=self:resolve(spec.type);if not eff then return nil,err end
    return RoomTypes.apply_spec(spec,eff),eff
end

function RoomTypes:schema() return Util.deepcopy(RoomTypes.builtin().schema) end

local function busy(app)
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and (app.authoring_plans.running or app.authoring_plans:status().recovery_required) then return 'Resolve the running or failed authoring plan first' end
end

-- Rooms using a type (directly or through a type that extends it).
function RoomTypes:_uses(eff_id,room_type)
    if room_type==eff_id then return true end
    local eff=room_type and self:resolve(room_type)
    if not eff then return false end
    for _,id in ipairs(eff.chain) do if id==eff_id then return true end end
    return false
end

function RoomTypes:list()
    local rows,seen={},{}
    local counts={};for _,r in ipairs(self.app.model.data.rooms or {}) do if r.room_type then counts[r.room_type]=(counts[r.room_type] or 0)+1 end end
    local function add(t,source)
        if seen[t.id] then return end;seen[t.id]=true
        local eff,err=self:resolve(t.id)
        rows[#rows+1]={id=t.id,name=t.name or t.id,description=t.description or '',extends=t.extends,source=source,valid=eff~=nil,error=err,
            traits=eff and eff.traits or nil,tags=eff and eff.tags or nil,interior=eff and eff.interior or nil,populate=eff and #eff.populate or 0,rooms=counts[t.id] or 0,
            overrides_builtin=source=='project' and RoomTypes.builtin().types[t.id]~=nil or nil}
    end
    for _,t in ipairs(project_list(self.app.model)) do add(t,'project') end
    local ids={};for id in pairs(RoomTypes.builtin().types) do ids[#ids+1]=id end;table.sort(ids)
    for _,id in ipairs(ids) do add(RoomTypes.builtin().types[id],'builtin') end
    return {items=rows,count=#rows}
end

function RoomTypes:get(id)
    local doc,source=self:find(id);if not doc then return nil,'unknown room type: '..tostring(id) end
    local eff,err=self:resolve(id);if not eff then return nil,err end
    local rooms={}
    for _,r in ipairs(self.app.model.data.rooms or {}) do if r.room_type==id then rooms[#rooms+1]={id=r.id,name=r.name,premise_id=r.premise_id} end end
    return {id=id,source=source,document=Util.deepcopy(doc),effective=eff,rooms=rooms}
end

-- Save a project type (validated; its chain and the types extending it must resolve). One undo step.
function RoomTypes:save(doc)
    local b=busy(self.app);if b then return nil,b end
    local ok,err=RoomTypes.check(doc);if not ok then return nil,err end
    local copy=Util.deepcopy(doc);copy.source=nil
    local base=self:lookup()
    local function with(id) if id==copy.id then return copy end;return base(id) end
    local eff;eff,err=RoomTypes.resolve_with(copy.id,with);if not eff then return nil,err end
    local dependents={}
    for _,t in ipairs(project_list(self.app.model)) do
        if t.id~=copy.id then
            local e,derr=RoomTypes.resolve_with(t.id,with)
            if not e then return nil,'room type '..t.id..' would break: '..derr end
            for _,cid in ipairs(e.chain) do if cid==copy.id then dependents[#dependents+1]=t.id;break end end
        end
    end
    local model=self.app.model
    model:snapshot('Save room type '..copy.id)
    copy.updated_at=Util.now_iso()
    local _,source,index=self:find(copy.id)
    local list=project_list(model)
    if source=='project' then copy.created_at=list[index].created_at;list[index]=copy else copy.created_at=copy.updated_at;list[#list+1]=copy end
    model:touch();self.app:mark_dirty()
    local rooms=0;for _,r in ipairs(model.data.rooms or {}) do if self:_uses(copy.id,r.room_type) then rooms=rooms+1 end end
    return {id=copy.id,saved=true,replaced=source=='project',overrides_builtin=RoomTypes.builtin().types[copy.id]~=nil,effective=eff,dependents=dependents,rooms=rooms}
end

function RoomTypes:delete(id)
    local b=busy(self.app);if b then return nil,b end
    local _,source,index=self:find(id)
    if source~='project' then return nil,source=='builtin' and 'built-in room types cannot be deleted' or 'unknown room type: '..tostring(id) end
    local list=project_list(self.app.model)
    local fallback=RoomTypes.builtin().types[id]
    if not fallback then
        for _,t in ipairs(list) do if t.id~=id and t.extends==id then return nil,'room type '..t.id..' extends '..id..'; change or delete it first' end end
    end
    local rooms=0;for _,r in ipairs(self.app.model.data.rooms or {}) do if r.room_type==id then rooms=rooms+1 end end
    self.app.model:snapshot('Delete room type '..id)
    table.remove(list,index)
    self.app.model:touch();self.app:mark_dirty()
    return {deleted=id,rooms=rooms,falls_back_to_builtin=fallback~=nil}
end

-- Typed rooms of the project.
function RoomTypes:rooms(args)
    args=args or {};local rows={}
    local furnished=furnishings(self.app.model)
    for _,r in ipairs(self.app.model.data.rooms or {}) do
        if r.room_type and (not args.premise_id or args.premise_id=='' or r.premise_id==args.premise_id) and (not args.type or args.type=='' or self:_uses(args.type,r.room_type)) then
            local eff=self:resolve(r.room_type)
            rows[#rows+1]={id=r.id,name=r.name,premise_id=r.premise_id,type=r.room_type,type_name=eff and eff.name or nil,valid=eff~=nil,
                generated=self.app.room_generator and self.app.room_generator:get(r.id)~=nil or false,furnished=furnished[r.id]~=nil}
        end
    end
    return {items=rows,count=#rows}
end

-- Describe a room for furnishing: its interior box and openings.
function RoomTypes:_room_desc(room)
    local rec=self.app.room_generator and self.app.room_generator:get(room.id)
    local d={id=room.id,name=room.name,doors={},windows={},center=Util.deepcopy(room.transform.position),yaw=num(room.transform.rotation and room.transform.rotation.yaw,0)}
    if rec and rec.spec then
        local s=rec.spec
        d.width,d.length,d.height,d.T=s.width,s.length,s.height,s.wall_thickness
        d.floor_top=s.floor and s.floor.type=='raised' and s.floor.raise or 0
        for _,o in ipairs(s.doors or {}) do d.doors[#d.doors+1]=Util.deepcopy(o) end
        for _,o in ipairs(s.windows or {}) do d.windows[#d.windows+1]=Util.deepcopy(o) end
    else
        d.width,d.length,d.height,d.T=room.size.width,room.size.depth,room.size.height,room.wall_thickness or 0.15
        d.floor_top=0
        for _,o in ipairs(room.openings or {}) do
            local c={wall=o.wall,offset=o.offset,width=o.width,height=o.height,sill=o.sill}
            if o.kind=='window' then d.windows[#d.windows+1]=c else d.doors[#d.doors+1]=c end
        end
    end
    return d
end

local function furnish_doc(room_id) return 'room_furnish_'..tostring(room_id):gsub('[^%w_%-]','_') end
RoomTypes.furnish_doc=furnish_doc

-- Expand a room's interior rules and populate entries (no changes).
function RoomTypes:furnish_plan(room_id,args)
    args=args or {}
    local room=self.app.model:get_room(room_id);if not room then return nil,'room not found: '..tostring(room_id) end
    local type_id=args.type or room.room_type
    if not type_id or type_id=='' then return nil,'the room has no type; give type or assign one first' end
    local G=package.loaded['modules/env_grammar'];local grammar=self.app.env_grammar
    if not G or not grammar then return nil,'environment grammars are unavailable' end
    local eff,err=self:resolve(type_id);if not eff then return nil,err end
    local g;g,err=G.normalize({id='room_furnish',name='Furnish '..tostring(room.name),rules={Furnish={}}},grammar:_resolver());if not g then return nil,err end
    local desc=self:_room_desc(room);desc.type=type_id
    local pool,obstacles={},{}
    if self.app.surfaces then
        local doc=furnish_doc(room.id)
        local previous=self.app.authoring_plans and self.app.authoring_plans:edl_get(doc)
        local skip={};for _,id in ipairs(previous and previous.items and previous.items.object or {}) do skip[id]=true end
        for _,s in ipairs(self.app.surfaces:collect({room_id=room.id})) do if not skip[s.object_id] then pool[#pool+1]=s end end
        for _,o in ipairs(self.app.surfaces:obstacles({premise_id=room.premise_id})) do if not skip[o.owner] then obstacles[#obstacles+1]=o end end
    end
    local exp;exp,err=G.furnish(g,desc,{seed=args.seed,params=args.params,type_lookup=self:lookup(),pool=pool,obstacles=obstacles})
    if not exp then return nil,err end
    local plan=G.compile(exp,{doc=furnish_doc(room.id),premise_id=room.premise_id,origin={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
        label='Furnish '..tostring(room.name)..' ('..type_id..')'})
    return {room=room,type=eff,expansion=exp,plan=plan}
end

local function furnish_summary(p)
    local kinds={};for _,it in ipairs(p.expansion.items) do kinds[it.kind]=(kinds[it.kind] or 0)+1 end
    local populate={}
    for k,e in ipairs(p.expansion.populate or {}) do populate[k]={kind=e.entry.kind or 'asset',tags=e.entry.tags,estimate=e.estimate,surfaces_matched=e.surfaces_matched} end
    return {room_id=p.room.id,type=p.type.id,seed=p.expansion.seed,items=#p.expansion.items,kinds=kinds,populate=populate,warnings=Util.deepcopy(p.expansion.warnings),steps=#p.plan.steps}
end

-- Furnish a room from its type: one authoring plan (one undo step); furnishing again replaces the previous furnishing.
function RoomTypes:furnish(room_id,args)
    args=args or {}
    local b=args.dry_run~=true and busy(self.app);if b then return nil,b end
    if not self.app.authoring_plans then return nil,'authoring plans are unavailable' end
    local p,err=self:furnish_plan(room_id,args);if not p then return nil,err end
    local out=furnish_summary(p)
    if args.dry_run==true then
        out.dry_run=true;if args.include_plan then out.plan=p.plan end
        local v=self.app.authoring_plans:validate(p.plan);out.valid=v.valid;out.errors=v.errors
        return out
    end
    local result;result,err=self.app.authoring_plans:execute(p.plan);if not result then return nil,err end
    local model=self.app.model
    furnishings(model)[p.room.id]={type=p.type.id,seed=p.expansion.seed,params=Util.deepcopy(args.params),doc=furnish_doc(p.room.id),furnished_at=Util.now_iso()}
    local warnings={};for _,o in ipairs(result.outputs or {}) do if o.warning then warnings[#warnings+1]='step '..o.index..' ('..o.op..'): '..tostring(o.warning) end end
    out.runtime_warnings=warnings;out.one_undo=true;out.replaced=result.edl and result.edl.replaced or false;out.created=#(result.outputs or {})-1
    return out
end

-- Remove a room's furnishing (one undo step).
function RoomTypes:unfurnish(room_id)
    local b=busy(self.app);if b then return nil,b end
    local plans=self.app.authoring_plans;if not plans then return nil,'authoring plans are unavailable' end
    local doc=furnish_doc(room_id)
    if not plans:edl_get(doc) then furnishings(self.app.model)[room_id]=nil;return nil,'the room has no furnishing from its type' end
    local r,err=plans:edl_remove(doc);if not r then return nil,err end
    furnishings(self.app.model)[room_id]=nil
    return {room_id=room_id,removed=true}
end

-- Set (or clear with false) a room's type. Generated rooms regenerate their shell
-- with the new type's defaults; furnish=true furnishes it afterwards.
function RoomTypes:assign(room_id,type_id,args)
    args=args or {}
    local b=busy(self.app);if b then return nil,b end
    local model=self.app.model
    local room=model:get_room(room_id);if not room then return nil,'room not found: '..tostring(room_id) end
    if type_id=='' then type_id=false end
    local eff
    if type_id then local err;eff,err=self:resolve(type_id);if not eff then return nil,err end end
    local out={room_id=room.id,type=type_id or nil,previous=room.room_type}
    local rg=self.app.room_generator
    if rg and rg:get(room.id) and args.regenerate~=false then
        local r,err=rg:update(room.id,{type=type_id or false});if not r then return nil,err end
        out.regenerated=true
    else
        model:snapshot(type_id and ('Set room type '..type_id) or 'Clear room type')
        room.room_type=type_id or nil
        if eff then local tags=union(room.tags,eff.tags);room.tags=tags end
        room.updated_at=Util.now_iso();model:touch();self.app:mark_dirty()
        out.regenerated=false
    end
    room=model:get_room(room_id)
    if eff then out.warnings=RoomTypes.size_warnings(eff,room.size.width,room.size.depth,room.size.height) end
    if args.furnish==true and type_id then
        local f,err=self:furnish(room.id,{seed=args.seed,params=args.params});if not f then out.furnish_error=err else out.furnish=f end
    elseif not type_id and args.furnish~=false and furnishings(model)[room.id] then
        local f,err=self:unfurnish(room.id);out.unfurnished=f~=nil;out.unfurnish_error=err
    end
    if self.app.selection then self.app.selection:set('room',room.id) end
    return out
end

-- A new typed parametric room with its interior, as a grammar build (one undo step;
-- env_grammar regenerate/remove work on it).
function RoomTypes:create_room(args)
    args=args or {}
    local grammar=self.app.env_grammar;if not grammar then return nil,'environment grammars are unavailable' end
    local type_id=args.type;local eff,err=self:resolve(type_id);if not eff then return nil,err end
    local spec=type(args.spec)=='table' and Util.deepcopy(args.spec) or {}
    for _,k in ipairs({'width','length','height','wall_thickness','doors','windows','floor','ceiling','trim','materials','lighting','collision','surfaces'}) do if args[k]~=nil then spec[k]=Util.deepcopy(args[k]) end end
    local applied=RoomTypes.apply_spec(spec,eff)
    local W,L=num(applied.width,4),num(applied.length or applied.depth,4)
    local T=num(applied.wall_thickness,0.15);local H=num(applied.height,3)
    if W<1 or L<1 or W>100 or L>100 then return nil,'width and length must be between 1 and 100 m' end
    spec.width=nil;spec.length=nil;spec.depth=nil;spec.wall_thickness=T;spec.height=H;spec.type=type_id
    if args.furnish==false then spec.furnish=false end
    -- Braces in a name would read as expressions.
    spec.name=(Util.trim(args.name or '')~='' and Util.trim(args.name) or eff.name):gsub('[{}]','')
    local doc={id='room_type_'..type_id,name=eff.name..' room',start='Room',size={W+2*T,L+2*T,H},rules={Room={{room=spec}}}}
    local build=args.build_id or ('room_'..type_id..'_'..Util.make_id('b'))
    local r;r,err=grammar:generate({doc=doc,build_id=build,premise_id=args.premise_id or self.app.selected_premise_id,premise_name=args.premise_name,seed=args.seed,params=args.params,
        transform=args.transform,position=args.position,yaw=args.yaw,origin=args.origin})
    if not r then return nil,err end
    r.type=type_id;r.warnings=r.warnings or {}
    for _,w in ipairs(RoomTypes.size_warnings(eff,W,L,H)) do r.warnings[#r.warnings+1]=w end
    return r
end

-- Bring rooms of a type (or a type extending it) up to date after the type changed:
-- grammar builds containing them regenerate, other generated rooms regenerate their
-- shell and furnished rooms furnish again with the same seed. Each is its own undo step.
function RoomTypes:reapply(type_id,args)
    args=args or {}
    local b=busy(self.app);if b then return nil,b end
    local eff,err=self:resolve(type_id);if not eff then return nil,err end
    local model=self.app.model;local plans=self.app.authoring_plans
    local results,done={},{}
    local rooms={};for _,r in ipairs(model.data.rooms or {}) do if self:_uses(type_id,r.room_type) and (not args.premise_id or r.premise_id==args.premise_id) then rooms[#rooms+1]=r.id end end
    -- Grammar builds first: they rebuild their rooms with new ids.
    if self.app.env_grammar and plans then
        for _,bld in ipairs(Util.deepcopy(self.app.env_grammar:builds().items)) do
            local edl=plans:edl_get('grammar_'..bld.id)
            local hit=false
            for _,rid in ipairs(edl and edl.items and edl.items.room or {}) do for _,id in ipairs(rooms) do if id==rid then hit=true;done[id]=true end end end
            if hit then
                local r,rerr=self.app.env_grammar:regenerate(bld.id)
                results[#results+1]={build_id=bld.id,action='regenerate_build',ok=r~=nil,error=rerr}
            end
        end
    end
    for _,id in ipairs(rooms) do
        if not done[id] and model:get_room(id) then
            if self.app.room_generator and self.app.room_generator:get(id) then
                local r,rerr=self.app.room_generator:update(id,{})
                results[#results+1]={room_id=id,action='regenerate_room',ok=r~=nil,error=rerr}
            end
            local f=furnishings(model)[id]
            if f and plans and plans:edl_get(f.doc) then
                local r,rerr=self:furnish(id,{seed=f.seed,params=f.params})
                results[#results+1]={room_id=id,action='furnish',ok=r~=nil,error=rerr}
            end
        end
    end
    local failed=0;for _,r in ipairs(results) do if not r.ok then failed=failed+1 end end
    return {type=type_id,rooms=#rooms,results=results,failed=failed}
end

return RoomTypes
