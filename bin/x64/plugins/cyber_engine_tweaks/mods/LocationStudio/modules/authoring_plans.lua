local Util=require('modules/util')
local Builder=require('modules/builder')

local Plans={}
Plans.__index=Plans

local OP_KIND={
    register_asset='asset',create_premise='premise',create_room='room',add_opening='opening',place_asset='object',
    create_location='location',create_volume='volume',create_camera='camera',create_route='route',create_group='group',
    create_scene='scene',capture_scene='scene',edit_scene_members='scene',move='item',spawn='runtime',activate_scene='scene',deactivate_scene='scene',isolate_scene='scene',
}

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
        format='locationstudio-authoring-plan',version=1,max_steps=100,
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
    if plan.version and tonumber(plan.version)~=1 then table.insert(errors,'unsupported plan version: '..tostring(plan.version)) end
    local steps=plan.steps
    if type(steps)~='table' or #steps==0 then table.insert(errors,'plan.steps must contain at least one operation');steps={} end
    if #steps>100 then table.insert(errors,'authoring plans are limited to 100 steps') end
    local normalized={}
    for index,raw in ipairs(steps) do
        local step=type(raw)=='table' and Util.deepcopy(raw) or {};local op=step.op
        if not OP_KIND[op] then table.insert(errors,string.format('step %d has unsupported op: %s',index,tostring(op))) end
        if step.as~=nil then
            if not alias_pattern(step.as) then table.insert(errors,string.format('step %d has invalid alias',index))
            elseif aliases[step.as] then table.insert(errors,string.format('step %d repeats alias %s',index,step.as)) end
        end
        walk_refs(step,function(name) if name~=step.as and not aliases[name] then table.insert(errors,string.format('step %d references unknown or later alias $%s',index,name)) end end)
        if step.as and not aliases[step.as] then aliases[step.as]=OP_KIND[op] or 'unknown' end
        if op=='place_asset' and not is_ref(step.asset_id) then local _,err=self:resolve_asset(step.asset_id,step.asset_query);if err then table.insert(errors,string.format('step %d: %s',index,err)) end end
        if op=='create_room' then local ok,err=Builder.validate_size({width=step.width or 4,depth=step.depth or 4,height=step.height or 3},step.wall_thickness);if not ok then table.insert(errors,string.format('step %d: %s',index,err)) end end
        if op=='move' and not step.kind then table.insert(errors,string.format('step %d: move requires kind',index)) end
        if (op=='create_room' or op=='create_volume' or op=='create_camera' or op=='create_scene' or op=='capture_scene' or op=='place_asset') and not step.premise_id then table.insert(errors,string.format('step %d: %s requires premise_id',index,op)) end
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
    return Builder.local_transform(origin,number(o.x),number(o.y),number(o.z),number(step.yaw,o.yaw))
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
        a.transform=self:_transform(origin,a) or a.transform;item,warning=app.authoring:create_camera(a);kind='camera'
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
    elseif op=='activate_scene' then item,warning=app.scenes:activate(a.id,a.spawn~=false);kind='scene'
    elseif op=='deactivate_scene' then item,warning=app.scenes:deactivate(a.id);kind='scene'
    elseif op=='isolate_scene' then item,warning=app.scenes:isolate(a.id);kind='scene'
    else return nil,'unsupported operation: '..tostring(op) end
    if not item then return nil,warning or (tostring(op)..' failed') end
    local id=item.id or (item.object and item.object.id)
    return {item=item,id=id,kind=kind,warning=warning}
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
    self.running=true;local aliases,outputs={},{}
    if self.app.logger then self.app.logger:info('authoring:plan','started',{name=validation.name,steps=validation.step_count,origin=origin_source}) end
    for index,step in ipairs(plan.steps) do
        local result,err=self:_run_step(step,aliases,origin)
        if not result then
            self.running=false;local rolled,rollback_err,failed=self:_rollback_state(snapshot)
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
        table.insert(outputs,{index=index,op=step.op,alias=step.as,kind=result.kind,id=result.id,warning=result.warning})
    end
    self.running=false
    self.app.model.undo_stack=Util.deepcopy(snapshot.undo);self.app.model.redo_stack={};self.app.model:push_history(snapshot.data,'Authoring plan '..tostring(validation.name or ''));self.app.model:touch();self.app:mark_dirty()
    local issues=self.app.model:validate();local result={executed=true,name=validation.name,step_count=#outputs,outputs=outputs,aliases=aliases,origin=origin,origin_source=origin_source,preflight=preflight,validation_issues=issues,one_undo=true}
    self.last_result=Util.deepcopy(result);self.last_error=nil
    if options.save==true then local ok,save_err=self.app:save(true);result.saved=ok;if not ok then result.save_error=save_err end end
    if self.app.logger then self.app.logger:info('authoring:plan','committed',{name=validation.name,steps=#outputs,aliases=aliases,issues=#issues,saved=result.saved==true}) end
    return result
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
