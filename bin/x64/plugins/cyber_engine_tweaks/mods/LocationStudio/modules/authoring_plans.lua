local Util=require('modules/util')
local Builder=require('modules/builder')

local Plans={}
Plans.__index=Plans

local OP_KIND={
    register_asset='asset',create_premise='premise',create_room='room',add_opening='opening',place_asset='object',
    create_location='location',create_volume='volume',create_camera='camera',create_route='route',create_group='group',
    create_scene='scene',capture_scene='scene',edit_scene_members='scene',move='item',spawn='runtime',activate_scene='scene',deactivate_scene='scene',isolate_scene='scene',
    -- Version 2 operations (used by the Environment Definition Language compiler).
    edl_begin='edl',set_room_kit='settings',import_resource='asset',place_resource='object',create_light='object',create_collision='object',
    create_vfx='object',create_audio_emitter='object',create_reverb_zone='object',create_occluder='object',create_interactable='object',
    create_npc='object',create_workspot='location',create_npc_route='npc_route',add_route_waypoint='waypoint',create_device_graph='device_graph',
    add_device_node='device_node',add_device_link='device_link',link_fact='volume',import_navigation='navigation_graph',create_spline='spline',create_procedural='object',create_parametric_room='room',create_material='material',set_collision_rules='collision_rules',
    create_decal='object',populate_surfaces='populate',
}
local V2_ONLY={}
for _,op in ipairs({'edl_begin','set_room_kit','import_resource','place_resource','create_light','create_collision','create_vfx','create_audio_emitter',
    'create_reverb_zone','create_occluder','create_interactable','create_npc','create_workspot','create_npc_route','add_route_waypoint','create_device_graph',
    'add_device_node','add_device_link','link_fact','import_navigation','create_spline','create_procedural','create_parametric_room','create_material','set_collision_rules',
    'create_decal','populate_surfaces'}) do V2_ONLY[op]=true end
local NEEDS_PREMISE={create_room=true,create_volume=true,create_camera=true,create_scene=true,capture_scene=true,place_asset=true,place_resource=true,
    create_light=true,create_collision=true,create_vfx=true,create_audio_emitter=true,create_occluder=true,create_interactable=true,create_npc=true,create_procedural=true,create_parametric_room=true}
-- Ops that do not need the World Builder runtime.
local NO_RUNTIME={edl_begin=true,create_workspot=true,create_npc_route=true,add_route_waypoint=true,create_device_graph=true,add_device_node=true,
    add_device_link=true,link_fact=true,import_navigation=true,create_spline=true,create_material=true,set_collision_rules=true}
local MAX_STEPS={[1]=100,[2]=2000}
local EDL_DOC='^[%a_][%w_%-]*$'

local function number(value,fallback) return tonumber(value) or fallback or 0 end
local function is_ref(value) return type(value)=='string' and value:sub(1,1)=='$' and #value>1 end
local function ref_name(value) return is_ref(value) and value:sub(2) or nil end

local function selection_snapshot(app)
    local s=app.selection
    return {kind=s and s.kind,id=s and s.id,ids=s and Util.deepcopy(s.object_ids) or {},active_id=s and s.id,group_source=s and s.group_source,active_group_id=app.active_object_group_id}
end

local function restore_selection(app,prior)
    if not app.selection then return end;prior=prior or {}
    if prior.kind=='object' then app.selection:set_object_group(prior.ids or {},prior.active_id,prior.group_source or 'locationstudio')
    elseif prior.kind and prior.id and app.selection:resolve(prior.kind,prior.id) then app.selection:set(prior.kind,prior.id)
    else app.selection:clear() end
    app.active_object_group_id=prior.active_group_id
end

local function get_item(model,kind,id)
    local fn=model['get_'..tostring(kind)]
    return fn and fn(model,id) or nil
end

local function alias_pattern(alias)
    return type(alias)=='string' and alias:match('^[%a_][%w_%-]*$')~=nil
end

local function walk_refs(value,visit)
    if is_ref(value) then visit(ref_name(value));return end
    if type(value)=='table' then for _,child in pairs(value) do walk_refs(child,visit) end end
end

function Plans.new(app)
    return setmetatable({app=app,last_result=nil,last_error=nil,recovery=nil,running=false},Plans)
end

function Plans:schema()
    return {
        format='locationstudio-authoring-plan',version=1,max_steps=100,versions={['1']='core operations, 100 steps',['2']='adds the Environment Definition Language operations, 2000 steps'},
        origin={'player','camera','explicit transform'},reference='Use $alias after a step with as="alias".',
        operations={
            register_asset={'name','template','category?','kind?','metadata?'},
            create_premise={'as','name','kind?','transform? (defaults to plan origin)'},
            create_room={'as','premise_id','name','width','depth','height','x?','y?','z?','yaw?','spawn?'},
            add_opening={'room_id','kind','wall','offset?','width?','height?','sill?','spawn?'},
            place_asset={'as','asset_id or asset_query','premise_id','room_id?','source?','offset?','transform?','spawn?'},
            create_location={'as','name','type?','category?','offset?','transform?'},
            create_volume={'as','premise_id','room_id?','name','shape?','offset?','size_x?','size_y?','size_z?'},
            create_camera={'as','premise_id','room_id?','name','offset?','look_at? or look_at_location_id?','fov?'},
            create_route={'as','name','kind?','location_ids','loop?'},
            create_group={'as','name','object_ids','active_id?'},
            create_scene={'as','name','premise_id','room_ids?','object_ids?','location_ids?','volume_ids?','camera_ids?','route_ids?','activate?'},
            capture_scene={'as','name','premise_id','include_rooms?','include_objects?','include_spatial?','include_construction?','activate?'},
            edit_scene_members={'id','mode: add/remove/replace','room_ids?','object_ids?','location_ids?','volume_ids?','camera_ids?','route_ids?'},
            move={'kind','id','dx?','dy?','dz?','droll?','dpitch?','dyaw?','local_space? or transform'},
            spawn={'kind','id'},activate_scene={'id'},deactivate_scene={'id'},isolate_scene={'id'},
        },
        operations_v2={
            edl_begin={'doc','name?','hash?','source?','streaming?'},set_room_kit={'preset?','roles? {role=asset_id}'},
            import_resource={'as','definition_key','path','name?','allow_cet?'},
            place_resource={'as','asset_id','premise_id','room_id?','offset','yaw?','roll?','pitch?','scale?','appearance?','layer?','stream_range?','spawn?'},
            create_light={'as','premise_id','offset','config {color,intensity,radius,...}','preset_id?'},
            create_collision={'as','premise_id','offset','shape','size?','radius?','height?','preset?','material?'},
            create_vfx={'as','premise_id','offset','resource_path','scale?','emission_rate?'},
            create_audio_emitter={'as','premise_id','offset','resource_path or query','radius?'},
            create_reverb_zone={'as','room_id','preset_name?','sound_event?','reverb?'},
            create_occluder={'as','premise_id','offset','mesh','size'},
            create_interactable={'as','premise_id','asset_id','kind','offset','loot_table?','loot_items?','item_record?','fact_name?','fact_value?','lock_state?'},
            create_npc={'as','premise_id','asset_id (entity_record)','record','offset','appearance?','conditions?'},
            create_workspot={'as','name','offset','workspot_kind?','animation?'},create_npc_route={'as','npc_id','name?','loop?'},
            add_route_waypoint={'route_id','offset','wait_seconds?','transition?','workspot_location_id?','variant?'},
            create_device_graph={'as','name','premise_id?'},add_device_node={'as','graph_id','kind','name','object_id?','config?'},
            add_device_link={'graph_id','from_id','to_id','trigger?','condition_fact?','condition_value?'},
            link_fact={'volume_id','fact_name','value?'},import_navigation={'as','name','nodes [{id,offset}]','edges'},
            create_spline={'as','premise_id','points [offset]','closed?'},
            create_procedural={'as','premise_id','generator','params','offset','yaw?','material?','collision?','layer?'},
            set_collision_rules={'rules','room_id? | object_id? (default: project default)','regenerate?'},
            create_material={'as?','key','preset?','base?','path?','params?','textures?','overrides?','variants?'},
            create_parametric_room={'as','premise_id','spec {name,width,length,height,wall_thickness,doors,windows,floor,ceiling,trim,materials,lighting,collision}','offset','yaw?'},
        },
    }
end

function Plans:examples()
    return {
        starter_workspace={
            format='locationstudio-authoring-plan',version=1,name='Starter Workspace',origin='player',
            steps={
                {op='create_premise',as='place',name='My First Location',kind='interior'},
                {op='create_room',as='room',premise_id='$place',name='Main Room',width=6,depth=5,height=3,spawn=true},
                {op='place_asset',as='chair',asset_id='builtin_chair_poor',premise_id='$place',room_id='$room',offset={x=1,y=0,z=0},yaw=180,spawn=true},
                {op='create_location',as='entrance',name='Entrance',type='entrance',category='Gameplay',offset={x=0,y=-2,z=0}},
                {op='create_volume',as='trigger',premise_id='$place',room_id='$room',name='Entry Trigger',shape='box',offset={x=0,y=-1.5,z=1},size_x=2,size_y=1,size_z=2},
                {op='create_camera',as='camera',premise_id='$place',room_id='$room',name='Entrance Camera',offset={x=-2,y=-1.5,z=1.7},look_at_location_id='$entrance',fov=55},
                {op='create_scene',as='scene',name='First Scene',premise_id='$place',room_ids={'$room'},object_ids={'$chair'},location_ids={'$entrance'},volume_ids={'$trigger'},camera_ids={'$camera'},activate=true},
            },
        },
        gameplay_route={
            format='locationstudio-authoring-plan',version=1,name='Gameplay Route',origin='player',
            steps={
                {op='create_location',as='start',name='Patrol Start',type='patrol',category='AI',offset={x=0,y=0,z=0}},
                {op='create_location',as='middle',name='Patrol Middle',type='patrol',category='AI',offset={x=0,y=4,z=0}},
                {op='create_location',as='finish',name='Patrol Finish',type='patrol',category='AI',offset={x=3,y=4,z=0}},
                {op='create_route',as='route',name='Guard Patrol',kind='patrol',location_ids={'$start','$middle','$finish'},loop=true},
            },
        },
        furnished_room={
            format='locationstudio-authoring-plan',version=1,name='Furnished Room',origin='player',
            steps={
                {op='create_premise',as='place',name='Furnished Location',kind='interior'},
                {op='create_room',as='room',premise_id='$place',name='Furniture Test',width=8,depth=6,height=3,spawn=true},
                {op='place_asset',as='table',asset_id='builtin_table_lab',premise_id='$place',room_id='$room',offset={x=0,y=0,z=0},spawn=true},
                {op='place_asset',as='chair_a',asset_id='builtin_chair_corpo',premise_id='$place',room_id='$room',offset={x=-1.2,y=0,z=0},yaw=90,spawn=true},
                {op='place_asset',as='chair_b',asset_id='builtin_chair_corpo',premise_id='$place',room_id='$room',offset={x=1.2,y=0,z=0},yaw=-90,spawn=true},
                {op='place_asset',as='lamp',asset_id='builtin_wall_lamp',premise_id='$place',room_id='$room',offset={x=0,y=2.7,z=1.8},yaw=180,spawn=true},
                {op='create_scene',as='scene',name='Furnished Room Scene',premise_id='$place',room_ids={'$room'},object_ids={'$table','$chair_a','$chair_b','$lamp'},activate=true},
            },
        },
        captured_scene={
            format='locationstudio-authoring-plan',version=1,name='Captured Location Scene',origin='player',
            steps={
                {op='create_premise',as='place',name='Captured Scene Location',kind='interior'},
                {op='create_room',as='room',premise_id='$place',name='Scene Stage',width=7,depth=5,height=3,spawn=true},
                {op='place_asset',as='table',asset_id='builtin_table_lab',premise_id='$place',room_id='$room',offset={x=0,y=0,z=0},spawn=true},
                {op='place_asset',as='chair',asset_id='builtin_chair_corpo',premise_id='$place',room_id='$room',offset={x=0,y=-1.2,z=0},yaw=0,spawn=true},
                {op='create_volume',as='trigger',premise_id='$place',room_id='$room',name='Scene Trigger',shape='box',offset={x=0,y=-2,z=1},size_x=2,size_y=1,size_z=2},
                {op='capture_scene',as='scene',name='Captured Stage Scene',premise_id='$place',activate=true},
            },
        },
    }
end

function Plans:resolve_asset(asset_id,query,aliases)
    if is_ref(asset_id) then asset_id=aliases and aliases[ref_name(asset_id)] end
    if asset_id then
        local asset=self.app.model:get_asset(asset_id);if asset then return asset end
        return nil,'asset not found: '..tostring(asset_id)
    end
    query=Util.trim(query);if query=='' then return nil,'asset_id or asset_query is required' end
    local exact,partial={},{ }
    for _,asset in ipairs(self.app.model.data.assets or {}) do
        local q=string.lower(query);local id=string.lower(tostring(asset.id));local name=string.lower(tostring(asset.name));local template=string.lower(tostring(asset.template))
        if q==id or q==name or q==template then table.insert(exact,asset)
        elseif name:find(q,1,true) or template:find(q,1,true) then table.insert(partial,asset) end
    end
    local matches=#exact>0 and exact or partial
    if #matches==1 then return matches[1] end
    if #matches==0 then return nil,'no Project Asset matches: '..query end
    return nil,'asset query is ambiguous ('..tostring(#matches)..' matches): '..query
end

function Plans:validate(plan)
    local errors,warnings,aliases={}, {},{}
    if type(plan)~='table' then return {valid=false,errors={'plan must be an object'},warnings={},steps={}} end
    if plan.format and plan.format~='locationstudio-authoring-plan' then table.insert(errors,'unsupported plan format: '..tostring(plan.format)) end
    local version=tonumber(plan.version or 1)
    if not MAX_STEPS[version] then table.insert(errors,'unsupported plan version: '..tostring(plan.version));version=1 end
    local steps=plan.steps
    if type(steps)~='table' or #steps==0 then table.insert(errors,'plan.steps must contain at least one operation');steps={} end
    if #steps>MAX_STEPS[version] then table.insert(errors,'version '..version..' authoring plans are limited to '..MAX_STEPS[version]..' steps') end
    local normalized={}
    for index,raw in ipairs(steps) do
        local step=type(raw)=='table' and Util.deepcopy(raw) or {};local op=step.op
        if not OP_KIND[op] then table.insert(errors,string.format('step %d has unsupported op: %s',index,tostring(op)))
        elseif V2_ONLY[op] and version<2 then table.insert(errors,string.format('step %d: %s requires plan version 2',index,op)) end
        if op=='edl_begin' and (index~=1 or not tostring(step.doc or ''):match(EDL_DOC)) then table.insert(errors,string.format('step %d: edl_begin must be the first step and needs a doc id',index)) end
        if step.as~=nil then
            if not alias_pattern(step.as) then table.insert(errors,string.format('step %d has invalid alias',index))
            elseif aliases[step.as] then table.insert(errors,string.format('step %d repeats alias %s',index,step.as)) end
        end
        walk_refs(step,function(name) if name~=step.as and not aliases[name] then table.insert(errors,string.format('step %d references unknown or later alias $%s',index,name)) end end)
        if step.as and not aliases[step.as] then aliases[step.as]=OP_KIND[op] or 'unknown' end
        if op=='place_asset' and not is_ref(step.asset_id) then local _,err=self:resolve_asset(step.asset_id,step.asset_query);if err then table.insert(errors,string.format('step %d: %s',index,err)) end end
        if op=='create_room' then local ok,err=Builder.validate_size({width=step.width or 4,depth=step.depth or 4,height=step.height or 3},step.wall_thickness);if not ok then table.insert(errors,string.format('step %d: %s',index,err)) end end
        if op=='set_collision_rules' or ((op=='create_procedural') and step.collision_rules~=nil) then
            local CG=package.loaded['modules/collision_gen']
            if CG then local ok,err=CG.normalize_rules(op=='set_collision_rules' and step.rules or step.collision_rules);if not ok then table.insert(errors,string.format('step %d: %s',index,err)) end end
        end
        if op=='create_material' then
            local ML=package.loaded['modules/materials']
            if ML then local ok,err=ML.normalize(step);if not ok then table.insert(errors,string.format('step %d: %s',index,err)) end end
        end
        if op=='populate_surfaces' then
            local S=package.loaded['modules/surfaces']
            if S then
                local _,err=S.placement_options(step);if err then table.insert(errors,string.format('step %d: %s',index,err)) end
                local _,kerr=S.check_kind(step);if kerr and kerr~=err then table.insert(errors,string.format('step %d: %s',index,kerr)) end
                local kind=step.kind or 'asset'
                if kind=='asset' and not is_ref(step.asset_id) then local _,aerr=self:resolve_asset(step.asset_id,step.asset_query);if aerr then table.insert(errors,string.format('step %d: %s',index,aerr)) end end
                if kind=='procedural' then local P=package.loaded['modules/procedural'];if P and not P.GENERATORS[step.generator] then table.insert(errors,string.format('step %d: unknown generator %s',index,tostring(step.generator))) end end
            end
        end
        if op=='create_parametric_room' then
            local RG=package.loaded['modules/room_generator']
            local spec,terr=step.spec,nil
            if self.app.room_types and type(spec)=='table' and spec.type and not is_ref(spec.type) then spec,terr=self.app.room_types:apply(spec) end
            if not spec then table.insert(errors,string.format('step %d: %s',index,tostring(terr)))
            elseif RG then local ok,err=RG.normalize(spec);if not ok then table.insert(errors,string.format('step %d: %s',index,err)) end end
            if type(step.offset)~='table' and type(step.transform)~='table' then table.insert(errors,string.format('step %d: create_parametric_room requires offset',index)) end
        end
        if op=='move' and not step.kind then table.insert(errors,string.format('step %d: move requires kind',index)) end
        if NEEDS_PREMISE[op] and not step.premise_id then table.insert(errors,string.format('step %d: %s requires premise_id',index,op)) end
        if (op=='place_resource' or op=='create_interactable' or op=='create_npc') and not step.asset_id then table.insert(errors,string.format('step %d: %s requires asset_id',index,op)) end
        if op=='edit_scene_members' then
            if not step.id then table.insert(errors,string.format('step %d: edit_scene_members requires id',index)) end
            if step.mode and step.mode~='add' and step.mode~='remove' and step.mode~='replace' then table.insert(errors,string.format('step %d: scene member mode must be add, remove, or replace',index)) end
            local has_members=false;for _,field in ipairs({'room_ids','object_ids','location_ids','volume_ids','camera_ids','route_ids'}) do if step[field]~=nil then has_members=true end end
            if not has_members then table.insert(errors,string.format('step %d: edit_scene_members requires at least one membership list',index)) end
        end
        if op=='create_route' and (type(step.location_ids)~='table' or #step.location_ids==0) then table.insert(errors,string.format('step %d: create_route requires location_ids',index)) end
        table.insert(normalized,{index=index,op=op,alias=step.as,kind=OP_KIND[op]})
    end
    if plan.origin and plan.origin~='player' and plan.origin~='camera' and type(plan.origin)~='table' then table.insert(errors,'origin must be player, camera, or an explicit transform') end
    return {valid=#errors==0,errors=errors,warnings=warnings,step_count=#steps,steps=normalized,aliases=aliases,name=plan.name or 'Authoring Plan'}
end

function Plans:preflight(plan)
    if (plan.origin==nil or plan.origin=='player' or plan.origin=='camera') and not self.app.game:is_ready() then return nil,'Game/player is not ready for the requested plan origin.' end
    local needs_world_builder,needs_entities=false,false
    for _,step in ipairs(plan.steps or {}) do
        if step.op=='create_room' and step.spawn==true then needs_world_builder=true end
        if step.op=='add_opening' and step.spawn~=false then needs_world_builder=true end
        if step.op=='place_asset' and step.spawn~=false and not is_ref(step.asset_id) then
            local asset=self:resolve_asset(step.asset_id,step.asset_query)
            if asset and asset.metadata and type(asset.metadata.world_builder)=='table' then needs_world_builder=true else needs_entities=true end
        end
        if step.op=='spawn' and step.kind=='object' and not is_ref(step.id) then
            local object=self.app.model:get_object(step.id)
            if object and object.metadata and type(object.metadata.world_builder)=='table' then needs_world_builder=true else needs_entities=true end
        elseif step.op=='spawn' and (step.kind=='room' or step.kind=='premise') then needs_world_builder=true end
        if V2_ONLY[step.op] and not NO_RUNTIME[step.op] then needs_world_builder=true end
    end
    if needs_world_builder then local status=self.app.runtime_shell:status(true);if not status.available then return nil,'World Builder room/resource backend is not ready: '..tostring(status.reason or 'unavailable') end end
    if needs_entities and not self.app.placement:status().supported then return nil,'CET entity spawner is not ready for direct .ent assets.' end
    return {ready=true,world_builder=needs_world_builder,entities=needs_entities}
end

function Plans:_origin(plan)
    if type(plan.origin)=='table' then return Util.deepcopy(plan.origin),'explicit' end
    if plan.origin=='camera' then local value,err=self.app.game:capture_camera_transform();return value,err or 'camera' end
    local value,err=self.app.game:capture_transform();return value,err or 'player'
end

function Plans:_resolve(value,aliases)
    if is_ref(value) then
        local resolved=aliases[ref_name(value)];if not resolved then return nil,'unresolved alias: '..value end
        return resolved
    end
    if type(value)~='table' then return value end
    local out={}
    for key,child in pairs(value) do local resolved,err=self:_resolve(child,aliases);if err then return nil,err end;out[key]=resolved end
    return out
end

function Plans:_transform(origin,step)
    if type(step.transform)=='table' then return Util.deepcopy(step.transform) end
    local o=step.offset;if type(o)~='table' then return nil end
    local t=Builder.local_transform(origin,number(o.x),number(o.y),number(o.z),number(step.yaw,o.yaw))
    if t and (step.roll~=nil or step.pitch~=nil) then t.rotation.roll=number(step.roll);t.rotation.pitch=number(step.pitch) end
    return t
end

-- World position of a plan-local offset (navigation nodes, spline points).
function Plans:_point(origin,offset)
    local t=Builder.local_transform(origin,number(offset.x),number(offset.y),number(offset.z),0)
    return {x=t.position.x,y=t.position.y,z=t.position.z}
end

-- Environment Definition Language build registry (model.data.edl_builds).
local function edl_record(app,doc)
    for i,b in ipairs(app.model.data.edl_builds or {}) do if b.id==doc then return b,i end end
end

-- Remove everything a previous apply of the same document created.
function Plans:_edl_clear(record)
    local app,model=self.app,self.app.model
    if record.premise_id and model:get_premise(record.premise_id) then
        app.placement:despawn_premise(record.premise_id)
        if app.procedural then for _,o in ipairs(model.data.objects) do if o.premise_id==record.premise_id and o.metadata and o.metadata.procedural then app.procedural:hide(o) end end end
        local ok,err=model:delete_premise(record.premise_id);if not ok then return nil,err end
    end
    local items=record.items or {}
    local function release(o)
        if app.procedural and o.metadata and o.metadata.procedural then app.procedural:hide(o) end
        if app.placement:is_tracked(o) then return app.placement:despawn(o) end
        return true
    end
    -- Rooms built into an existing premise (grammar builds): their pieces go with them.
    for _,id in ipairs(items.room or {}) do
        if model:get_room(id) then
            for _,o in ipairs(model.data.objects) do if o.room_id==id then local ok,err=release(o);if not ok then return nil,err end end end
            model:delete_room(id)
        end
    end
    for _,id in ipairs(items.object or {}) do
        local o=model:get_object(id)
        if o then
            local ok,err=release(o);if not ok then return nil,err end
            for _,cid in ipairs(o.metadata and o.metadata.procedural and o.metadata.procedural.collider_ids or {}) do
                local c=model:get_object(cid);if c then local cok,cerr=release(c);if not cok then return nil,cerr end;model:delete_object(cid) end
            end
            model:delete_object(id)
        end
    end
    for _,id in ipairs(items.volume or {}) do if model:get_volume(id) then model:delete_volume(id) end end
    for _,id in ipairs(items.location or {}) do if model:get_location(id) then model:delete_location(id) end end
    for _,id in ipairs(items.route or {}) do if model:get_route(id) then model:delete_route(id) end end
    local function drop(collection,ids)
        local set={};for _,id in ipairs(ids or {}) do set[id]=true end
        local list=model.data[collection] or {}
        for i=#list,1,-1 do if set[list[i].id] then table.remove(list,i) end end
    end
    drop('material_defs',items.material);    drop('npc_routes',items.npc_route);drop('device_logic_graphs',items.device_graph);drop('navigation_graphs',items.navigation_graph);drop('splines',items.spline)
    return true
end

-- Objects and rooms made by the running plan (populate_surfaces from_plan).
function Plans:_track(result)
    local c=self._created;if not c or not result then return end
    if result.kind=='object' and result.id then c.objects[#c.objects+1]=result.id elseif result.kind=='room' and result.id then c.rooms[#c.rooms+1]=result.id end
end

function Plans:_edl_note(step,result)
    local rec=self._edl;if not rec or not result or not result.id or result.kind=='edl' then return end
    if result.kind=='populate' then
        for i,id in ipairs(result.ids or {}) do
            local k=result.kinds and result.kinds[i] or 'object'
            rec.items[k]=rec.items[k] or {};table.insert(rec.items[k],id)
        end
        return
    end
    local kind=result.kind
    if kind=='premise' then rec.premise_id=result.id end
    rec.items[kind]=rec.items[kind] or {};table.insert(rec.items[kind],result.id)
    if step.edl_element then rec.elements[step.edl_element]={kind=kind,id=result.id} end
end

function Plans:_run_step(step,aliases,origin)
    local app=self.app;local a,err=self:_resolve(step,aliases);if not a then return nil,err end
    local op=a.op;local item,warning,kind
    if op=='register_asset' then
        if Util.trim(a.template)=='' and not (a.metadata and type(a.metadata.world_builder)=='table') then return nil,'register_asset requires a .ent template or World Builder metadata' end
        item=app.model:add_asset(a);app:mark_dirty();kind='asset'
    elseif op=='create_premise' then
        item=app.model:add_premise({name=a.name,kind=a.kind,transform=a.transform or origin,levels=a.levels,floor_height=a.floor_height,tags=a.tags,notes=a.notes});app.selection:set('premise',item.id);app:mark_dirty();kind='premise'
    elseif op=='create_room' then
        item,warning=app.builder:create_room(a);kind='room'
        if item then app.selection:set('room',item.id) end
        if item and a.spawn==true then local runtime,runtime_err=app.placement:spawn_room_shell(item.id);if not runtime then return nil,runtime_err end;if runtime_err then warning=runtime_err end end
    elseif op=='add_opening' then
        local result;result,warning=app.builder:add_opening(a);item=result and result.opening;kind='opening'
        if item and a.spawn~=false then local runtime,runtime_err=app.placement:spawn_room_shell(a.room_id);if not runtime then return nil,runtime_err end;if runtime_err then warning=runtime_err end end
    elseif op=='place_asset' then
        local asset;asset,err=self:resolve_asset(a.asset_id,a.asset_query,aliases);if not asset then return nil,err end
        local transform=self:_transform(origin,a);local context=Util.deepcopy(a);context.transform=transform or a.transform;context.spawn=a.spawn~=false
        item,warning=app.actions:place_asset(asset.id,context.transform and 'preview' or (a.source or 'origin'),context);kind='object'
        if item and context.spawn and a.require_runtime~=false and not app.placement:is_tracked(item) then return nil,warning or 'asset did not acquire a live runtime backend' end
    elseif op=='create_location' then
        item=app.model:add_location({name=a.name,type=a.type,category=a.category,tags=a.tags,notes=a.notes,radius=a.radius,transform=self:_transform(origin,a) or a.transform or origin,metadata={source='authoring_plan'}});app.selection:set('location',item.id);app:mark_dirty();kind='location'
    elseif op=='create_volume' then
        a.transform=self:_transform(origin,a) or a.transform;item,warning=app.authoring:create_volume(a);kind='volume'
    elseif op=='create_camera' then
        a.transform=self:_transform(origin,a) or a.transform
        if type(a.look_at_offset)=='table' then a.look_at=self:_point(origin,a.look_at_offset) end
        item,warning=app.authoring:create_camera(a);kind='camera'
    elseif op=='create_route' then
        item=app.model:add_route({name=a.name,kind=a.kind,location_ids=a.location_ids,loop=a.loop,notes=a.notes});app.selection:set('route',item.id);app:mark_dirty();kind='route'
    elseif op=='create_group' then
        item,warning=app.assemblies:create_group({name=a.name,ids=a.object_ids or {},active_id=a.active_id,pivot_mode=a.pivot_mode,pivot=a.pivot,premise_id=a.premise_id,room_id=a.room_id});kind='group'
    elseif op=='create_scene' then
        item,warning=app.scenes:create(a);kind='scene'
        if item and a.activate==true then local _,activate_warning=app.scenes:activate(item.id,true);warning=warning or activate_warning end
    elseif op=='capture_scene' then
        local captured;captured,warning=app.scenes:capture_premise(a);item=captured and captured.scene;kind='scene'
        if item and a.activate==true then local _,activate_warning=app.scenes:activate(item.id,true);warning=warning or activate_warning end
    elseif op=='edit_scene_members' then
        item,warning=app.scenes:edit_members(a.id,a);kind='scene'
    elseif op=='move' then
        local target=get_item(app.model,a.kind,a.id);if not target or not target.transform then return nil,'move target not found: '..tostring(a.kind)..' '..tostring(a.id) end
        local transform=a.transform and Util.deepcopy(a.transform) or Util.deepcopy(target.transform)
        if not a.transform then
            local dx,dy=number(a.dx),number(a.dy);if a.local_space==true then dx,dy=Util.rotate_xy(dx,dy,transform.rotation.yaw) end
            transform.position.x=transform.position.x+dx;transform.position.y=transform.position.y+dy;transform.position.z=transform.position.z+number(a.dz)
            transform.rotation.roll=transform.rotation.roll+number(a.droll);transform.rotation.pitch=transform.rotation.pitch+number(a.dpitch);transform.rotation.yaw=transform.rotation.yaw+number(a.dyaw)
        end
        item,warning=app.authoring:set_transform(a.kind,a.id,transform,a.cascade~=false);kind=a.kind
        if item and a.kind=='object' and app.placement:is_tracked(item) then local _,refresh_err=app.placement:refresh(item);warning=warning or refresh_err end
        if item and (a.kind=='room' or a.kind=='premise') then local _,refresh_warning=app.ent_tools:refresh_live_scope(a.kind,a.id);warning=warning or refresh_warning end
    elseif op=='spawn' then
        if a.kind=='object' then local target=app.model:get_object(a.id);if not target then return nil,'object not found' end;local runtime_id;runtime_id,warning=app.placement:spawn(target);if runtime_id then item={id=target.id,entity_id=tostring(runtime_id)} end
        elseif a.kind=='room' then item,warning=app.placement:spawn_room_shell(a.id)
        elseif a.kind=='premise' then item=app.placement:spawn_premise(a.id)
        elseif a.kind=='scene' then item,warning=app.scenes:activate(a.id,true)
        else return nil,'spawn kind must be object, room, premise, or scene' end
        kind='runtime'
    elseif op=='edl_begin' then
        local previous,index=edl_record(app,a.doc)
        if previous then local ok,clear_err=self:_edl_clear(previous);if not ok then return nil,'could not remove the previous build of '..a.doc..': '..tostring(clear_err) end;table.remove(app.model.data.edl_builds,index) end
        local rec={id=a.doc,name=a.name or a.doc,hash=a.hash,source=a.source,streaming=Util.deepcopy(a.streaming or {}),applied_at=Util.now_iso(),
            elements={},items={},premise_id=nil,replaced=previous~=nil,mod_version=app.version}
        app.model.data.edl_builds=app.model.data.edl_builds or {};table.insert(app.model.data.edl_builds,rec)
        self._edl=rec;item={id=a.doc,replaced=previous~=nil};kind='edl'
    elseif op=='set_room_kit' then
        if a.preset and a.preset~='' then local kit,kit_err=app.builder:set_room_kit_preset(a.preset);if not kit then return nil,kit_err end end
        for role,asset_id in pairs(a.roles or {}) do local ok,role_err=app.builder:assign_room_kit_role(role,asset_id);if not ok then return nil,role_err end end
        item={id='room_kit'};kind='settings'
    elseif op=='import_resource' then
        local def=app.world_builder and app.world_builder:definition(a.definition_key)
        if not def then return nil,'unknown World Builder definition: '..tostring(a.definition_key) end
        local imported,import_err=app.world_builder:import_catalog_record({category=def.category,variant=def.variant,spawn_data=a.path,name=a.name})
        if imported then item=imported.asset
        elseif a.allow_cet==true and tostring(a.path):lower():match('%.ent$') then
            item=app.model:add_asset({name=a.name or a.path,template=a.path,kind='entity',category='EDL / CET entity',tags={'edl','cet'}})
            warning='not in the World Builder catalog; registered as a direct CET entity (not exportable to sectors)'
        else return nil,import_err end
        kind='asset'
    elseif op=='place_resource' then
        local asset;asset,err=self:resolve_asset(a.asset_id,nil,aliases);if not asset then return nil,err end
        local transform=self:_transform(origin,a) or a.transform
        item,warning=app.actions:place_asset(asset.id,'preview',{premise_id=a.premise_id,room_id=a.room_id,name=a.name,transform=transform,spawn=false});kind='object'
        if item then
            if a.layer then item.layer=a.layer end
            local wb=item.metadata and item.metadata.world_builder;local data=wb and wb.entry and wb.entry.data
            if a.appearance then if data then data.app=a.appearance else item.appearance=a.appearance end end
            if type(a.scale)=='table' then
                if wb and wb.apply_scale then item.size={x=number(a.scale.x,1),y=number(a.scale.y,1),z=number(a.scale.z,1)} else warning='scale ignored: this resource has no live scale' end
            end
            if a.stream_range and data then data.primaryRange=number(a.stream_range);data.secondaryRange=number(a.stream_range_secondary,number(a.stream_range)*1.2) end
            if a.spawn~=false then local id,spawn_err=app.placement:spawn(item);if not id and a.require_runtime~=false then return nil,spawn_err or 'resource did not spawn' end end
        end
    elseif op=='create_light' then
        item,warning=app.lighting:create({premise_id=a.premise_id,room_id=a.room_id,name=a.name,transform=self:_transform(origin,a),config=a.config,preset_id=a.preset_id,resource_name=a.resource_name,spawn=a.spawn});kind='object'
    elseif op=='create_collision' then
        local r;r,warning=app.collision:create_primitive({premise_id=a.premise_id,room_id=a.room_id,name=a.name,shape=a.shape,size=a.size,radius=a.radius,height=a.height,
            preset=a.preset,material=a.material,visualize=a.visualize,transform=self:_transform(origin,a),spawn=a.spawn});item=r and r.object;kind='object'
    elseif op=='create_vfx' then
        local r;r,warning=app.vfx:create({premise_id=a.premise_id,room_id=a.room_id,name=a.name,resource_path=a.resource_path,backend=a.backend,scale=a.scale,
            emission_rate=a.emission_rate,respawn_on_move=a.respawn_on_move,transform=self:_transform(origin,a),spawn=a.spawn});item=r and r.object;kind='object'
    elseif op=='create_audio_emitter' then
        local r;r,warning=app.ambient_audio:create_emitter({premise_id=a.premise_id,room_id=a.room_id,name=a.name,resource_path=a.resource_path,query=a.query,
            radius=a.radius,transform=self:_transform(origin,a),spawn=a.spawn});item=r and r.object;kind='object'
    elseif op=='create_reverb_zone' then
        local r;r,warning=app.ambient_audio:create_reverb_zone({premise_id=a.premise_id,room_id=a.room_id,name=a.name,preset_name=a.preset_name,sound_event=a.sound_event,
            reverb=a.reverb,priority=a.priority,width=a.width,depth=a.depth,height=a.height,spawn=a.spawn});item=r and r.zone;kind='object'
    elseif op=='create_occluder' then
        local r;r,warning=app.visibility:create_occluder({premise_id=a.premise_id,room_id=a.room_id,name=a.name,mesh=a.mesh,size=a.size,transform=self:_transform(origin,a),spawn=a.spawn});item=r and r.object;kind='object'
    elseif op=='create_interactable' then
        local asset;asset,err=self:resolve_asset(a.asset_id,nil,aliases);if not asset then return nil,err end
        item,warning=app.actions:create_interactable({kind=a.kind,asset_id=asset.id,premise_id=a.premise_id,room_id=a.room_id,name=a.name,transform=self:_transform(origin,a),
            item_record=a.item_record,loot_table=a.loot_table,loot_items=a.loot_items,entity_record=a.entity_record,fact_name=a.fact_name,fact_value=a.fact_value,lock_state=a.lock_state,spawn=a.spawn});kind='object'
    elseif op=='create_npc' then
        local asset;asset,err=self:resolve_asset(a.asset_id,nil,aliases);if not asset then return nil,err end
        item,warning=app.actions:create_npc_population({asset_id=asset.id,record=a.record,appearance=a.appearance,premise_id=a.premise_id,room_id=a.room_id,name=a.name,
            transform=self:_transform(origin,a),spawn_on_start=a.spawn_on_start,always_spawned=a.always_spawned,primary_range=a.primary_range,secondary_range=a.secondary_range,
            attitude=a.attitude,faction=a.faction,level=a.level,archetype=a.archetype,idle_behavior=a.idle_behavior,conditions=a.conditions,preview=a.preview});kind='object'
    elseif op=='create_workspot' then
        item=app.model:add_location({name=a.name or 'Workspot',type='workspot',category='NPC Workspots',tags={'npc',a.workspot_kind or 'sit'},radius=0.5,transform=self:_transform(origin,a) or origin,
            metadata={source='edl',workspot={kind=a.workspot_kind or 'sit',record=a.record or '',appearance=a.appearance or '',animation=Util.deepcopy(a.animation or {})}}});app:mark_dirty();kind='location'
    elseif op=='create_npc_route' then
        item,warning=app.actions:create_npc_route({npc_id=a.npc_id,name=a.name,loop=a.loop,kind=a.route_kind,notes=a.notes});kind='npc_route'
    elseif op=='add_route_waypoint' then
        item,warning=app.actions:add_npc_route_waypoint({route_id=a.route_id,variant=a.variant,transform=self:_transform(origin,a),name=a.name,wait_seconds=a.wait_seconds,facing_yaw=a.facing_yaw,
            speed=a.speed,transition=a.transition,workspot_location_id=a.workspot_location_id,branch_fact=a.branch_fact,branch_value=a.branch_value,branch_target_id=a.branch_target_id});kind='waypoint'
    elseif op=='create_device_graph' then item,warning=app.device_logic:create({name=a.name,premise_id=a.premise_id});kind='device_graph'
    elseif op=='add_device_node' then item,warning=app.device_logic:add_node({graph_id=a.graph_id,kind=a.kind,name=a.name,object_id=a.object_id,config=a.config,native=a.native});kind='device_node'
    elseif op=='add_device_link' then item,warning=app.device_logic:add_link({graph_id=a.graph_id,from_id=a.from_id,to_id=a.to_id,trigger=a.trigger,condition_fact=a.condition_fact,condition_value=a.condition_value});kind='device_link'
    elseif op=='link_fact' then
        local volume=app.model:get_volume(a.volume_id);if not volume then return nil,'volume not found' end
        local fact=Util.trim(a.fact_name or '');if not fact:match('^[%w_%.%-]+$') then return nil,'fact_name must use letters, numbers, underscore, dot, or hyphen' end
        local metadata=Util.deepcopy(volume.metadata or {});metadata.questforge=metadata.questforge or {};metadata.questforge.fact_name=fact;metadata.questforge.value=tonumber(a.value) or 1
        item,warning=app.model:update_volume(volume.id,{metadata=metadata});kind='volume'
    elseif op=='import_navigation' then
        local nodes={};for i,n in ipairs(a.nodes or {}) do nodes[i]={id=n.id,name=n.name,surface=n.surface,position=self:_point(origin,n.offset or {})} end
        item,warning=app.navigation:import_graph({name=a.name,nodes=nodes,edges=a.edges or {},source_format='locationstudio-edl'});kind='navigation_graph'
    elseif op=='create_spline' then
        local points={};for i,p in ipairs(a.points or {}) do points[i]={position=self:_point(origin,p.offset or p),mode=p.mode} end
        item,warning=app.splines:create({name=a.name,premise_id=a.premise_id,points=points,closed=a.closed,tension=a.tension,mode=a.mode});kind='spline'
    elseif op=='create_procedural' then
        if not app.procedural then return nil,'procedural geometry is unavailable' end
        local r;r,warning=app.procedural:create({generator=a.generator,params=a.params,premise_id=a.premise_id,room_id=a.room_id,name=a.name,layer=a.layer,
            material=a.material,collision=a.collision,collision_preset=a.collision_preset,collision_rules=a.collision_rules,stream_range=a.stream_range,surface=a.surface,surfaces=a.surfaces,transform=self:_transform(origin,a),spawn=a.spawn})
        item=r and r.object;kind='object';if r and r.preview_error then warning=r.preview_error end
    elseif op=='set_collision_rules' then
        if not app.collision_gen then return nil,'collision rules are unavailable' end
        local scope=a.room_id and ('room:'..a.room_id) or a.object_id and ('object:'..a.object_id) or 'default'
        local r;r,warning=app.collision_gen:set_rules(scope,a.rules or {},{regenerate=a.regenerate~=false})
        item=r and {id=scope,scope=scope,rules=r.rules};kind='collision_rules'
    elseif op=='create_material' then
        if not app.material_library then return nil,'material library is unavailable' end
        local def=Util.deepcopy(a);def.op=nil;def.as=nil;def.edl_element=nil
        item,warning=app.material_library:create(def);kind='material'
    elseif op=='create_decal' then
        if not app.mesh_appearance then return nil,'decals are unavailable' end
        local r;r,warning=app.mesh_appearance:create_decal({premise_id=a.premise_id,room_id=a.room_id,name=a.name,resource_name=a.resource_name,query=a.query,resource_path=a.resource_path,
            width=a.width,height=a.height,depth=a.depth,alpha=a.alpha,auto_hide_distance=a.auto_hide_distance,horizontal_flip=a.horizontal_flip,vertical_flip=a.vertical_flip,
            transform=self:_transform(origin,a),spawn=a.spawn})
        item=r and r.object;kind='object';if r and r.spawn_error then warning=r.spawn_error end
    elseif op=='populate_surfaces' then
        -- Place items on semantic surfaces (modules/surfaces.lua) of what exists now.
        if not app.surfaces then return nil,'semantic surfaces are unavailable' end
        local q=Util.deepcopy(a)
        if a.from_plan==true then q.object_ids=Util.deepcopy(self._created and self._created.objects or {});q.room_ids=Util.deepcopy(self._created and self._created.rooms or {}) end
        local sample;sample,err=app.surfaces:sample(q);if not sample then return nil,err end
        if sample.count==0 and a.required==true then return nil,'no placements on '..sample.surfaces_matched..' matching surface(s)' end
        local ids,kinds={},{}
        for i,p in ipairs(sample.items) do
            local sub;sub,err=app.surfaces.step_for(p,a,i);if not sub then return nil,err end
            local r;r,err=self:_run_step(sub,aliases,origin);if not r then return nil,'placement '..i..' on '..tostring(p.surface.tag)..': '..tostring(err) end
            ids[#ids+1]=r.id;kinds[#kinds+1]=r.kind;self:_track(r)
        end
        item={id=ids[1] or ('populate_'..Util.make_id('p')),ids=ids,kinds=kinds,count=#ids,surfaces_matched=sample.surfaces_matched,rejected=sample.rejected}
        kind='populate';if #ids==0 then warning='no placements on '..sample.surfaces_matched..' matching surface(s)' end
    elseif op=='create_parametric_room' then
        if not app.room_generator then return nil,'room generator is unavailable' end
        local r;r,warning=app.room_generator:create({spec=a.spec,premise_id=a.premise_id,transform=self:_transform(origin,a)})
        item=r and r.room;kind='room'
    elseif op=='activate_scene' then item,warning=app.scenes:activate(a.id,a.spawn~=false);kind='scene'
    elseif op=='deactivate_scene' then item,warning=app.scenes:deactivate(a.id);kind='scene'
    elseif op=='isolate_scene' then item,warning=app.scenes:isolate(a.id);kind='scene'
    else return nil,'unsupported operation: '..tostring(op) end
    if not item then return nil,warning or (tostring(op)..' failed') end
    local id=item.id or (item.object and item.object.id)
    return {item=item,id=id,kind=kind,warning=warning,ids=item.ids,kinds=item.kinds}
end

function Plans:_rollback_state(snapshot)
    local removed=self.app.placement:despawn_all()
    if removed and #(removed.failed or {})>0 then return nil,'Runtime cleanup refused '..tostring(#removed.failed)..' object(s).',removed.failed end
    self.app.model.data=Util.deepcopy(snapshot.data)
    self.app.model.undo_stack=Util.deepcopy(snapshot.undo);self.app.model.redo_stack=Util.deepcopy(snapshot.redo)
    self.app.dirty=snapshot.dirty;self.app.dirty_since=snapshot.dirty_since
    self.app.editing_scene_id=snapshot.editing_scene_id;self.app.live_scene_id=snapshot.live_scene_id
    restore_selection(self.app,snapshot.selection)
    local respawn_failed={}
    for _,id in ipairs(snapshot.live_ids) do local object=self.app.model:get_object(id);if object then local _,err=self.app.placement:spawn(object);if err then table.insert(respawn_failed,{id=id,error=tostring(err)}) end end end
    return {rolled_back=true,respawn_failed=respawn_failed}
end

function Plans:execute(plan,options)
    options=options or {}
    if self.running then return nil,'an authoring plan is already running' end
    if self.recovery then return nil,'Resolve the previous authoring-plan rollback before running another plan.' end
    if self.app.transform_session and self.app.transform_session:is_active() then return nil,'Commit or cancel the active transform session first.' end
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke first.' end
    local validation=self:validate(plan);if not validation.valid then self.last_error=table.concat(validation.errors,'; ');self.last_result={executed=false,validation=validation};return nil,self.last_error end
    local preflight,preflight_err=self:preflight(plan);if not preflight then self.last_error=preflight_err;self.last_result={executed=false,validation=validation,preflight={ready=false,error=preflight_err}};return nil,preflight_err end
    local origin,origin_source=self:_origin(plan);if not origin then return nil,origin_source end
    local live_ids={};for _,object in ipairs(self.app.model.data.objects) do if self.app.placement:is_tracked(object) then table.insert(live_ids,object.id) end end
    local snapshot={data=Util.deepcopy(self.app.model.data),undo=Util.deepcopy(self.app.model.undo_stack),redo=Util.deepcopy(self.app.model.redo_stack),dirty=self.app.dirty==true,dirty_since=self.app.dirty_since,selection=selection_snapshot(self.app),live_ids=live_ids,editing_scene_id=self.app.editing_scene_id,live_scene_id=self.app.live_scene_id}
    self.running=true;self._edl=nil;self._created={objects={},rooms={}};local aliases,outputs={},{}
    if self.app.logger then self.app.logger:info('authoring:plan','started',{name=validation.name,steps=validation.step_count,origin=origin_source}) end
    for index,step in ipairs(plan.steps) do
        local result,err=self:_run_step(step,aliases,origin)
        if not result then
            self.running=false;self._edl=nil;self._created=nil;local rolled,rollback_err,failed=self:_rollback_state(snapshot)
            if not rolled then
                self.recovery={snapshot=snapshot,plan_name=validation.name,step=index,error=tostring(err),cleanup_failed=failed};self.last_error='Plan failed at step '..index..' ('..tostring(step.op)..'): '..tostring(err)..'. Rollback is blocked: '..tostring(rollback_err)
                self.last_result={executed=false,partial=true,recovery_required=true,failed_step=index,error=tostring(err),outputs=outputs}
                if self.app.logger then self.app.logger:error('authoring:plan','rollback_blocked',{step=index,op=step.op,error=err,cleanup_failed=failed}) end
                return nil,self.last_error
            end
            self.last_error='Plan failed at step '..index..' ('..tostring(step.op)..'): '..tostring(err)..'. All plan changes were rolled back.'
            self.last_result={executed=false,rolled_back=true,failed_step=index,error=tostring(err),outputs=outputs,rollback=rolled}
            if self.app.logger then self.app.logger:error('authoring:plan','rolled_back',{step=index,op=step.op,error=err,respawn_failed=#(rolled.respawn_failed or {})}) end
            return nil,self.last_error
        end
        if step.as and result.id then aliases[step.as]=result.id end
        self:_edl_note(step,result);self:_track(result)
        table.insert(outputs,{index=index,op=step.op,alias=step.as,kind=result.kind,id=result.id,ids=result.ids,warning=result.warning})
    end
    self.running=false;self._created=nil
    local edl=self._edl;self._edl=nil
    self.app.model.undo_stack=Util.deepcopy(snapshot.undo);self.app.model.redo_stack={};self.app.model:push_history(snapshot.data,'Authoring plan '..tostring(validation.name or ''));self.app.model:touch();self.app:mark_dirty()
    local issues=self.app.model:validate();local result={executed=true,name=validation.name,step_count=#outputs,outputs=outputs,aliases=aliases,origin=origin,origin_source=origin_source,preflight=preflight,validation_issues=issues,one_undo=true}
    if edl then result.edl={doc=edl.id,premise_id=edl.premise_id,elements=Util.deepcopy(edl.elements),replaced=edl.replaced} end
    self.last_result=Util.deepcopy(result);self.last_error=nil
    if options.save==true then local ok,save_err=self.app:save(true);result.saved=ok;if not ok then result.save_error=save_err end end
    if self.app.logger then self.app.logger:info('authoring:plan','committed',{name=validation.name,steps=#outputs,aliases=aliases,issues=#issues,saved=result.saved==true}) end
    return result
end

-- Environment Definition Language builds applied to this project.
function Plans:edl_list()
    local rows={}
    for _,b in ipairs(self.app.model.data.edl_builds or {}) do
        local elements=0;for _ in pairs(b.elements or {}) do elements=elements+1 end
        rows[#rows+1]={id=b.id,name=b.name,hash=b.hash,source=b.source,applied_at=b.applied_at,premise_id=b.premise_id,elements=elements,streaming=Util.deepcopy(b.streaming)}
    end
    return {items=rows,count=#rows}
end

function Plans:edl_get(doc)
    local b=edl_record(self.app,doc);if not b then return nil,'no EDL build with id '..tostring(doc) end
    return Util.deepcopy(b)
end

-- Remove everything an EDL document built, as one undo step.
function Plans:edl_remove(doc)
    if self.running then return nil,'an authoring plan is running' end
    if self.recovery then return nil,'Resolve the pending authoring-plan recovery first.' end
    local b,index=edl_record(self.app,doc);if not b then return nil,'no EDL build with id '..tostring(doc) end
    local before=Util.deepcopy(self.app.model.data);local undo=Util.deepcopy(self.app.model.undo_stack)
    local ok,err=self:_edl_clear(b)
    if not ok then self.app.model.data=before;self.app.model.undo_stack=undo;return nil,err end
    table.remove(self.app.model.data.edl_builds,index)
    self.app.model.undo_stack=undo;self.app.model.redo_stack={};self.app.model:push_history(before,'Remove EDL build '..tostring(doc))
    self.app.model:touch();self.app:mark_dirty()
    return {removed=true,doc=doc}
end

function Plans:retry_rollback()
    if not self.recovery then return nil,'no authoring-plan recovery is pending' end
    local rolled,err,failed=self:_rollback_state(self.recovery.snapshot)
    if not rolled then self.recovery.cleanup_failed=failed;self.last_error='Rollback is still blocked: '..tostring(err);return nil,self.last_error end
    local result={rolled_back=true,recovered=true,plan_name=self.recovery.plan_name,failed_step=self.recovery.step,respawn_failed=rolled.respawn_failed}
    self.recovery=nil;self.last_result=Util.deepcopy(result);self.last_error=nil
    if self.app.logger then self.app.logger:info('authoring:plan','recovery_rolled_back',{plan=result.plan_name,failed_step=result.failed_step}) end
    return result
end

function Plans:keep_partial()
    if not self.recovery then return nil,'no authoring-plan recovery is pending' end
    local r=self.recovery;self.app.model.undo_stack=Util.deepcopy(r.snapshot.undo);self.app.model.redo_stack={};self.app.model:push_history(r.snapshot.data);self.app.model:touch();self.app:mark_dirty()
    local result={kept=true,partial=true,plan_name=r.plan_name,failed_step=r.step,error=r.error,one_undo=true}
    self.recovery=nil;self.last_result=Util.deepcopy(result);self.last_error=nil
    if self.app.logger then self.app.logger:warn('authoring:plan','recovery_kept_partial',{plan=result.plan_name,failed_step=result.failed_step}) end
    return result
end

function Plans:load_file(path)
    path=path or 'data/authoring-plan.json';local plan=Util.json_read(path,nil)
    if type(plan)~='table' then return nil,'Could not read a JSON authoring plan from '..tostring(path) end
    return plan
end

function Plans:execute_file(path,options)
    local plan,err=self:load_file(path);if not plan then return nil,err end
    return self:execute(plan,options)
end

function Plans:status()
    return {running=self.running==true,recovery_required=self.recovery~=nil,recovery=self.recovery and {plan_name=self.recovery.plan_name,failed_step=self.recovery.step,error=self.recovery.error,cleanup_failed=Util.deepcopy(self.recovery.cleanup_failed)} or nil,last_result=Util.deepcopy(self.last_result),last_error=self.last_error}
end

return Plans
