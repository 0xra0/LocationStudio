local Util=require('modules/util')
local Builder=require('modules/builder')

local Actions={}
Actions.__index=Actions

function Actions.new(app) return setmetatable({app=app},Actions) end

function Actions:_log(level,name,message,fields)
    local logger=self.app.logger
    if logger and logger[level] then logger[level](logger,'action:'..name,message,fields) end
end

function Actions:_fail(name,err,fields)
    err=tostring(err or 'action failed')
    local data={error=err};for key,value in pairs(fields or {}) do data[key]=value end
    self:_log('error',name,'failed',data);return nil,err
end

function Actions:_ok(name,result,fields,warning)
    local data=fields or {}
    if warning then data.warning=warning;self:_log('warn',name,'complete_with_warning',data) else self:_log('info',name,'complete',data) end
    return result,warning
end

function Actions:_dirty(item)
    self.app:mark_dirty();return item
end

local function cover_number(value,default)
    if value==nil then return default end
    local n=tonumber(value)
    if not n or n~=n or n==math.huge or n==-math.huge then return nil end
    return n
end

function Actions:create_cover_node(args)
    args=args or {};local premise_id=args.premise_id or self.app.selected_premise_id
    if not premise_id or not self.app.model:get_premise(premise_id) then return self:_fail('create_cover_node','select a valid premise first') end
    local transform=args.transform
    if not transform then
        if args.source=='aim' then
            local hit,err=self.app.game:aim_point(args.distance or 8);if not hit then return self:_fail('create_cover_node',err or 'aim point unavailable') end
            local player=self.app.game:capture_transform();local yaw=player and player.rotation and player.rotation.yaw or 0
            transform={position={x=hit.position.x,y=hit.position.y,z=hit.position.z},rotation={roll=0,pitch=0,yaw=yaw}}
        else
            local err;transform,err=self.app.game:capture_transform();if not transform then return self:_fail('create_cover_node',err or 'player transform unavailable') end
        end
    end
    if type(transform)~='table' or type(transform.position)~='table' then return self:_fail('create_cover_node','transform with world position is required') end
    local p=transform.position;local r=transform.rotation or {}
    local x,y,z=cover_number(p.x),cover_number(p.y),cover_number(p.z);local yaw=cover_number(r.yaw,0)
    if not x or not y or not z or not yaw then return self:_fail('create_cover_node','position and yaw must be finite numbers') end
    local kind=args.cover_type or 'crouch';if kind~='crouch' and kind~='standing' then return self:_fail('create_cover_node','cover_type must be crouch or standing') end
    local exposure=args.exposure or 'medium';if not ({low=true,medium=true,high=true})[exposure] then return self:_fail('create_cover_node','exposure must be low, medium, or high') end
    local spacing=cover_number(args.spacing,1.5);if not spacing or spacing<0.25 or spacing>10 then return self:_fail('create_cover_node','spacing must be between 0.25 and 10 metres') end
    local room_id=args.room_id or self.app.selected_room_id;if room_id and not self.app.model:get_room(room_id) then return self:_fail('create_cover_node','room_id does not exist') end
    if room_id and self.app.model:get_room(room_id).premise_id~=premise_id then return self:_fail('create_cover_node','room must belong to the selected premise') end
    local item=self.app.model:add_cover_node({id=Util.make_id('cover'),premise_id=premise_id,room_id=room_id,name=Util.trim(args.name or '')~='' and Util.trim(args.name) or 'Cover Node',cover_type=kind,exposure=exposure,spacing=spacing,
        transform={position={x=x,y=y,z=z,w=cover_number(p.w,1)},rotation={roll=cover_number(r.roll,0),pitch=cover_number(r.pitch,0),yaw=yaw}},source=args.node_source or args.source or 'manual',confidence=cover_number(args.confidence,1)})
    self.app.selection:set('cover_node',item.id);self:_dirty(item)
    return self:_ok('create_cover_node',item,{id=item.id,premise_id=premise_id,source=item.source})
end

function Actions:update_cover_node(args)
    args=args or {};local item=self.app.model:get_cover_node(args.id);if not item then return self:_fail('update_cover_node','cover node not found') end
    local patch=args.patch or {};local merged=Util.deepcopy(item);for key,value in pairs(patch) do merged[key]=value end
    if merged.cover_type~='crouch' and merged.cover_type~='standing' then return self:_fail('update_cover_node','cover_type must be crouch or standing') end
    if not ({low=true,medium=true,high=true})[merged.exposure] then return self:_fail('update_cover_node','exposure must be low, medium, or high') end
    local spacing=cover_number(merged.spacing,1.5);if not spacing or spacing<0.25 or spacing>10 then return self:_fail('update_cover_node','spacing must be between 0.25 and 10 metres') end
    if merged.room_id and (not self.app.model:get_room(merged.room_id) or self.app.model:get_room(merged.room_id).premise_id~=merged.premise_id) then return self:_fail('update_cover_node','room_id must belong to the node premise') end
    if not self.app.model:get_premise(merged.premise_id) then return self:_fail('update_cover_node','premise_id must reference an existing premise') end
    local t=merged.transform;local p=t and t.position;local r=t and t.rotation or {};if not p then return self:_fail('update_cover_node','transform with world position is required') end
    for _,key in ipairs({'x','y','z'}) do if not cover_number(p[key]) then return self:_fail('update_cover_node','position coordinates must be finite numbers') end end
    if not cover_number(r.yaw,0) then return self:_fail('update_cover_node','yaw must be a finite number') end
    self.app.model:snapshot()
    for _,key in ipairs({'name','premise_id','room_id','cover_type','exposure','source','confidence'}) do if patch[key]~=nil then item[key]=Util.deepcopy(patch[key]) end end
    if patch.transform~=nil then item.transform={position={x=cover_number(p.x),y=cover_number(p.y),z=cover_number(p.z),w=cover_number(p.w,1)},rotation={roll=cover_number(r.roll,0),pitch=cover_number(r.pitch,0),yaw=cover_number(r.yaw,0)}} end
    item.spacing=spacing;item.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return self:_ok('update_cover_node',item,{id=item.id})
end

function Actions:delete_cover_node(id)
    local _,index=self.app.model:get_cover_node(id);if not index then return self:_fail('delete_cover_node','cover node not found') end
    self.app.model:snapshot();table.remove(self.app.model.data.cover_nodes,index);self.app.model:touch();self.app:mark_dirty()
    if self.app.selection.kind=='cover_node' and self.app.selection.id==id then self.app.selection:clear() end
    return self:_ok('delete_cover_node',{deleted=true,id=id},{id=id})
end

function Actions:scan_cover_candidates(args)
    args=args or {};if not self.app.live_tools or not self.app.live_tools.scan_cover_candidates then return self:_fail('scan_cover_candidates','live collision scanner is unavailable') end
    local result,err=self.app.live_tools:scan_cover_candidates(args);if not result then return self:_fail('scan_cover_candidates',err) end
    if args.save_to_project~=true then return result end
    local premise_id=args.premise_id or self.app.selected_premise_id
    if not premise_id or not self.app.model:get_premise(premise_id) then return self:_fail('scan_cover_candidates','save_to_project requires a valid premise_id') end
    local made,skipped={},0
    for _,candidate in ipairs(result.candidates or {}) do
        local near=false;for _,existing in ipairs(self.app.model.data.cover_nodes or {}) do
            if existing.premise_id==premise_id and Util.distance3(existing.transform.position,candidate.transform.position)<math.max(0.5,tonumber(args.min_spacing) or 1) then near=true;break end
        end
        if near then skipped=skipped+1 else
            local node,node_err=self:create_cover_node({premise_id=premise_id,room_id=args.room_id,transform=candidate.transform,name='Scanned Cover '..tostring(#made+1),cover_type=args.cover_type or 'crouch',exposure=candidate.exposure or 'medium',spacing=args.spacing or 1.5,node_source='live_collision_scan',confidence=candidate.confidence})
            if node then made[#made+1]=node else return self:_fail('scan_cover_candidates',node_err,{created=#made,skipped=skipped}) end
        end
    end
    result.saved=made;result.saved_count=#made;result.skipped_nearby=skipped
    return result
end

function Actions:create_premise_from_player(name,kind)
    self:_log('debug','create_premise','begin')
    local transform,err=self.app.game:capture_transform();if not transform then return self:_fail('create_premise',err) end
    local item=self.app.model:add_premise({name=name or 'New Premise',kind=kind or 'interior',transform=transform})
    if not item then return self:_fail('create_premise','model rejected premise') end
    self.app.selection:set('premise',item.id);self:_dirty(item)
    return self:_ok('create_premise',item,{id=item.id,name=item.name})
end

function Actions:capture_location(name,kind)
    self:_log('debug','capture_location','begin')
    local transform,err=self.app.game:capture_transform();if not transform then return self:_fail('capture_location',err) end
    local item=self.app.model:add_location({name=name or 'Captured Point',type=kind or 'point',category='Scene',transform=transform,metadata={source='captured from live player transform',coordinates_verified=true}})
    if not item then return self:_fail('capture_location','model rejected location') end
    self.app.selection:set('location',item.id);self:_dirty(item)
    return self:_ok('capture_location',item,{id=item.id,name=item.name})
end

function Actions:create_room(args)
    args=args or {};local premise_id=args.premise_id or self.app.selected_premise_id
    if not premise_id then return self:_fail('create_room','select a premise first') end
    local item,err=self.app.builder:create_room({
        premise_id=premise_id,name=args.name or 'New Room',kind=args.kind,width=args.width or 5,depth=args.depth or 5,height=args.height or 3,
        x=args.x or 0,y=args.y or 0,z=args.z or 0,yaw=args.yaw or 0,level=args.level,layer=args.layer,generate_shell=args.generate_shell~=false,
    })
    if not item then return self:_fail('create_room',err) end
    self.app.selection:set('room',item.id)
    local warning
    if self.app.model.data.settings.workspace.live_preview then
        local runtime,runtime_err=self.app.placement:spawn_room_shell(item.id)
        if not runtime then warning='Room data was created, but nothing spawned: '..tostring(runtime_err)
        elseif runtime_err then warning=runtime_err end
    end
    return self:_ok('create_room',item,{id=item.id,name=item.name,shell_objects=#(item.shell_object_ids or {})},warning)
end

function Actions:create_volume(args)
    args=args or {};local premise_id=args.premise_id or self.app.selected_premise_id
    if not premise_id then return self:_fail('create_volume','select a premise first') end
    local transform=args.transform;local transform_err
    if not transform and not args.at_origin then transform,transform_err=self.app.game:capture_transform() end
    if not transform and not args.at_origin then return self:_fail('create_volume',transform_err or 'player transform unavailable') end
    local item,err=self.app.authoring:create_volume({
        premise_id=premise_id,room_id=args.room_id or self.app.selected_room_id,name=args.name or 'Trigger Volume',purpose=args.purpose or 'trigger',shape=args.shape or 'box',
        transform=transform,width=args.width or args.size_x or 2,depth=args.depth or args.size_y or 2,height=args.height or args.size_z or 2,radius=args.radius,source=args.source or (transform and 'action:player' or 'action:origin'),
    })
    if not item then return self:_fail('create_volume',err) end
    self.app.selection:set('volume',item.id)
    return self:_ok('create_volume',item,{id=item.id,name=item.name})
end

function Actions:create_camera(args)
    args=args or {};local premise_id=args.premise_id or self.app.selected_premise_id
    if not premise_id then return self:_fail('create_camera','select a premise first') end
    local transform,err=args.transform,nil
    if not transform then transform,err=self.app.game:capture_camera_transform() end
    if not transform then return self:_fail('create_camera',err or 'active camera transform unavailable') end
    local look_at=args.look_at;local source='explicit'
    if not look_at then
        local hit;hit,err=self.app.game:aim_point(args.distance or 10)
        if not hit then return self:_fail('create_camera',err or 'aim target unavailable') end
        look_at=hit.position;source=hit.source
    end
    local item;item,err=self.app.authoring:create_camera({premise_id=premise_id,room_id=args.room_id or self.app.selected_room_id,name=args.name or 'Camera',kind=args.kind or 'shot',transform=transform,look_at=look_at,fov=args.fov or self.app.game:camera_fov() or 50,duration=args.duration or 3})
    if not item then return self:_fail('create_camera',err) end
    self.app.selection:set('camera',item.id)
    local warning=source=='forward_fallback' and 'No raycast/entity hit; camera look-at used the forward fallback point.' or nil
    return self:_ok('create_camera',item,{id=item.id,name=item.name,aim_source=source},warning)
end

function Actions:place_asset(asset_id,source,context)
    context=context or {};source=source or 'origin'
    local asset=self.app.model:get_asset(asset_id);if not asset then return self:_fail('place_asset','asset not found',{asset_id=asset_id}) end
    self.app.model:mark_asset_used(asset_id);self.app:mark_dirty()
    local wb_asset=asset.metadata and type(asset.metadata.world_builder)=='table'
    if not wb_asset and Util.trim(asset.template)=='' then return self:_fail('place_asset','asset has no .ent template',{asset_id=asset_id}) end
    local premise_id=context.premise_id or self.app.selected_premise_id
    if not premise_id then
        local premise,premise_err=self.app.quickstart:ensure_premise('Placed Assets')
        if not premise then return self:_fail('place_asset',premise_err or 'could not create a location container',{asset_id=asset_id}) end
        premise_id=premise.id
    end
    local metadata=Util.deepcopy(asset.metadata or {});metadata.locationstudio_asset_id=asset.id
    local args={premise_id=premise_id,room_id=context.room_id or self.app.selected_room_id,name=context.name or asset.name,kind=asset.kind,template=asset.template,appearance=asset.appearance,layer=asset.layer,size=asset.size,metadata=metadata,source='asset:'..asset.id,yaw=context.yaw or 0,distance=context.distance}
    local object,err,placement_source
    if context.transform then
        args.transform=Util.deepcopy(context.transform);object,err=self.app.builder:place_object(args);placement_source='explicit_transform'
    elseif source=='aim' then
        args.spawn=context.spawn;if args.spawn==nil then args.spawn=self.app.model.data.settings.workspace.live_preview end
        local result;result,err=self.app.authoring:place_object_at_aim(args);object=result and result.object;placement_source=result and result.placement_source
        if result and result.spawn_error then err='Placed, but live spawn failed: '..tostring(result.spawn_error) end
    elseif source=='player' then
        args.transform,err=self.app.game:capture_transform();if args.transform then object,err=self.app.builder:place_object(args) end
    else object,err=self.app.builder:place_object(args) end
    if not object then return self:_fail('place_asset',err,{asset_id=asset_id,source=source}) end
    self.app.selection:set('object',object.id)
    local should_spawn=context.spawn
    if should_spawn==nil then should_spawn=self.app.model.data.settings.workspace.live_preview end
    if source~='aim' and should_spawn then
        local _,spawn_err=self.app.placement:spawn(object);if spawn_err then err='Placed, but live spawn failed: '..tostring(spawn_err) end
    end
    return self:_ok('place_asset',object,{asset_id=asset_id,object_id=object.id,source=source,placement_source=placement_source},err)
end

local INTERACTABLE_KINDS={door=true,loot_container=true,shard=true,item=true}
local function valid_record(value,prefix)
    value=Util.trim(value or '')
    return value=='' or value:match('^'..prefix..'%.[%w_%.%-]+$')~=nil
end

function Actions:create_interactable(args)
    args=args or {}
    local kind=Util.trim(args.kind or '')
    if not INTERACTABLE_KINDS[kind] then return self:_fail('create_interactable','kind must be door, loot_container, shard, or item') end
    local asset_id=args.asset_id or self.app.last_asset_id or self.app.selected_asset_id
    local asset=asset_id and self.app.model:get_asset(asset_id)
    if not asset then return self:_fail('create_interactable','select a registered game entity asset first',{asset_id=asset_id}) end
    local wb=asset.metadata and asset.metadata.world_builder or {}
    local wb_key=tostring(wb.definition_key or '')
    local template=Util.trim(asset.template or '')
    local is_entity_template=template:lower():match('%.ent$')~=nil or wb_key=='entity_template' or wb_key=='entity_amm' or wb_key=='entity_record' or wb_key=='device'
    if not is_entity_template then return self:_fail('create_interactable','interactable needs a game Entity .ent, Entity Record, or Device asset; a mesh alone has no interaction behavior',{asset_id=asset_id}) end
    local item_record=Util.trim(args.item_record or '')
    local loot_table=Util.trim(args.loot_table or '')
    local entity_record=Util.trim(args.entity_record or '')
    local fact=Util.trim(args.fact_name or '')
    local loot_items=type(args.loot_items)=='table' and Util.deepcopy(args.loot_items) or {}
    if entity_record~='' and not entity_record:match('^[%w_]+%.[%w_%.%-]+$') then return self:_fail('create_interactable','entity_record must be a dotted game record identifier') end
    if (kind=='shard' or kind=='item') and (not item_record:match('^Items%.[%w_%.%-]+$')) then return self:_fail('create_interactable','shard/item requires a valid Items.* TweakDB record') end
    if item_record~='' and not valid_record(item_record,'Items') then return self:_fail('create_interactable','item_record must be an Items.* TweakDB record') end
    if kind=='loot_container' and not loot_table:match('^LootTables%.[%w_%.%-]+$') then return self:_fail('create_interactable','loot_container requires a LootTables.* record; items belong in that loot table') end
    if loot_table~='' and not valid_record(loot_table,'LootTables') then return self:_fail('create_interactable','loot_table must be a LootTables.* TweakDB record') end
    if fact~='' and not fact:match('^[%w_%.%-]+$') then return self:_fail('create_interactable','fact_name must use letters, numbers, underscore, dot, or hyphen') end
    for i,row in ipairs(loot_items) do
        if type(row)~='table' or not tostring(row.item_record or ''):match('^Items%.[%w_%.%-]+$') then return self:_fail('create_interactable','loot_items['..i..'] requires an Items.* record') end
        local lo,hi=tonumber(row.count_min) or 1,tonumber(row.count_max) or 1
        local chance=tonumber(row.drop_chance) or 1
        if lo<1 or hi<lo or lo%1~=0 or hi%1~=0 or chance<0 or chance>1 then return self:_fail('create_interactable','loot_items['..i..'] has invalid counts or drop_chance') end
    end
    local fact_value=math.floor(tonumber(args.fact_value) or 1)
    if fact_value < -2147483648 or fact_value > 2147483647 then return self:_fail('create_interactable','fact_value must fit a signed 32-bit quest fact') end
    local lock_state=args.lock_state or ((kind=='door' or kind=='loot_container') and 'unlocked' or 'not_applicable')
    if kind=='door' or kind=='loot_container' then
        if lock_state~='locked' and lock_state~='unlocked' then return self:_fail('create_interactable','door/loot lock_state must be locked or unlocked') end
    elseif lock_state~='not_applicable' then return self:_fail('create_interactable','shards/items use lock_state=not_applicable') end
    local warning
    local object,place_warning=self:place_asset(asset_id,args.source or 'aim',{premise_id=args.premise_id,room_id=args.room_id,name=args.name or asset.name,
        yaw=args.yaw or 0,distance=args.distance or 10,spawn=args.spawn~=false,transform=args.transform})
    if not object then return nil,place_warning end
    object.kind='interactable';object.metadata=object.metadata or {}
    object.metadata.interactable={kind=kind,asset_id=asset.id,entity_template=asset.template,entity_record=entity_record,item_record=item_record,
        loot_table=loot_table,loot_items=loot_items,lock_state=lock_state,fact_name=fact,fact_value=fact_value,fact_event='on_interact',
        native_setup_required=true,setup_status='authoring_only'}
    object.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    warning=place_warning
    if fact~='' or kind=='loot_container' or kind=='door' or kind=='shard' or kind=='item' then
        local native='Saved interactable configuration; native game interaction wiring is not generated by CET.'
        warning=warning and (warning..' '..native) or native
    end
    return self:_ok('create_interactable',object,{id=object.id,kind=kind,asset_id=asset.id,lock_state=lock_state,fact_name=fact,setup_status='authoring_only'},warning)
end

local function population_config(args,record)
    local conditions=type(args.conditions)=='table' and Util.deepcopy(args.conditions) or {}
    for i,c in ipairs(conditions) do
        if type(c)~='table' or not tostring(c.fact_name or ''):match('^[%w_%.%-]+$') then return nil,'conditions['..i..'] requires a valid quest fact name' end
        local fact_value=c.fact_value==nil and 1 or tonumber(c.fact_value)
        if not fact_value or fact_value~=fact_value or fact_value%1~=0 or fact_value < -2147483648 or fact_value > 2147483647 then return nil,'conditions['..i..'].fact_value must be a signed 32-bit integer' end
        c.fact_value=fact_value
    end
    local level=args.level
    if level~=nil then level=tonumber(level) or -1;if level~=level or level<0 or level>100 then return nil,'level must be from 0 to 100 (0 means use the Character record default)' end;level=math.floor(level) end
    local despawn=args.despawn_distance==nil and 0 or tonumber(args.despawn_distance)
    if not despawn or despawn~=despawn or despawn<0 or despawn>10000 then return nil,'despawn_distance must be from 0 to 10000 metres' end
    local primary=args.primary_range==nil and 100 or tonumber(args.primary_range)
    local secondary=args.secondary_range==nil and 120 or tonumber(args.secondary_range)
    if not primary or not secondary or primary~=primary or secondary~=secondary or primary<0 or secondary<primary or secondary>10000 then return nil,'streaming ranges must satisfy 0 <= primary_range <= secondary_range <= 10000' end
    return {record=record,appearance=Util.trim(args.appearance or ''),attitude=Util.trim(args.attitude or ''),faction=Util.trim(args.faction or ''),
        level=level or 0,archetype=Util.trim(args.archetype or ''),idle_behavior=Util.trim(args.idle_behavior or ''),despawn_distance=despawn,
        conditions=conditions,spawn_on_start=args.spawn_on_start~=false,always_spawned=args.always_spawned==true,
        primary_range=primary,secondary_range=secondary}
end

local function population_spawnable(object)
    local wb=object and object.metadata and object.metadata.world_builder
    local entry=wb and wb.entry
    local data=entry and entry.data
    if type(data)=='table' and type(data.spawnable)=='table' then data=data.spawnable end
    if type(data)~='table' then return nil end
    return data,wb
end

local ROUTE_VARIANTS={patrol='waypoints',alert='alert_waypoints',combat='combat_waypoints'}
local function npc_population_object(app,id)
    local object=id and app.model:get_object(id)
    return object and object.metadata and object.metadata.npc_population and object or nil
end
local function validate_npc_waypoint(app,value,variant)
    if type(value)~='table' then return nil,'waypoint must be an object' end
    local t=value.transform
    if type(t)~='table' or type(t.position)~='table' then return nil,'waypoint requires a saved world transform' end
    local p=t.position;local r=t.rotation or {}
    local function num(v,default) if v==nil then return default end;local n=tonumber(v);if not n or n~=n or n==math.huge or n==-math.huge then return nil end;return n end
    local out={id=value.id or Util.make_id('wp'),name=Util.trim(value.name or '') ~= '' and Util.trim(value.name) or 'Waypoint',
        transform={position={x=num(p.x),y=num(p.y),z=num(p.z),w=num(p.w,1)},rotation={roll=num(r.roll,0),pitch=num(r.pitch,0),yaw=num(r.yaw,0)}},
        wait_seconds=num(value.wait_seconds,0),facing_yaw=num(value.facing_yaw,r.yaw or 0),speed=num(value.speed,1),
        transition=value.transition or 'walk',workspot_location_id=value.workspot_location_id or '',
        branch_fact=Util.trim(value.branch_fact or ''),branch_value=num(value.branch_value,1),branch_target_id=value.branch_target_id or ''}
    for _,key in ipairs({'x','y','z'}) do if not out.transform.position[key] then return nil,'waypoint coordinates must be finite numbers' end end
    if not out.wait_seconds or not out.facing_yaw or not out.speed or not out.branch_value then return nil,'wait, facing, speed, and branch value must be finite numbers' end
    if out.wait_seconds~=out.wait_seconds or out.wait_seconds<0 or out.wait_seconds>3600 then return nil,'wait_seconds must be between 0 and 3600' end
    if out.facing_yaw~=out.facing_yaw or out.speed~=out.speed or out.speed<0.1 or out.speed>10 then return nil,'facing_yaw must be finite and speed must be between 0.1 and 10' end
    if out.transition~='walk' and out.transition~='workspot' then return nil,'transition must be walk or workspot' end
    if out.transition=='workspot' then
        local loc=app.model:get_location(out.workspot_location_id)
        if not loc or not (loc.metadata and loc.metadata.workspot) then return nil,'workspot transition must reference a saved NPC workspot location' end
    end
    if out.branch_fact~='' and (not out.branch_fact:match('^[%w_%.%-]+$') or out.branch_value~=out.branch_value or out.branch_value%1~=0) then return nil,'branch requires a valid fact name and integer value' end
    out.variant=variant
    return out
end

function Actions:create_npc_route(args)
    args=args or {};local npc=npc_population_object(self.app,args.npc_id)
    if not npc then return self:_fail('create_npc_route','npc_id must reference a saved NPC population point') end
    local route={id=Util.make_id('npcroute'),name=Util.trim(args.name or '')~='' and Util.trim(args.name) or (npc.name..' Patrol'),npc_id=npc.id,
        premise_id=npc.premise_id,loop=args.loop~=false,kind=args.kind or 'patrol',waypoints={},alert_waypoints={},combat_waypoints={},notes=tostring(args.notes or '')}
    self.app.model:snapshot();table.insert(self.app.model.data.npc_routes,route);npc.metadata.npc_route_ids=npc.metadata.npc_route_ids or {};table.insert(npc.metadata.npc_route_ids,route.id)
    self.app.model:touch();self.app:mark_dirty();return self:_ok('create_npc_route',route,{id=route.id,npc_id=npc.id})
end

function Actions:add_npc_route_waypoint(args)
    args=args or {};local route=self.app.model:get_npc_route(args.route_id)
    if not route then return self:_fail('add_npc_route_waypoint','NPC route not found') end
    local field=ROUTE_VARIANTS[args.variant or 'patrol'];if not field then return self:_fail('add_npc_route_waypoint','variant must be patrol, alert, or combat') end
    local transform=args.transform
    if not transform then
        if args.source=='aim' then local hit,err=self.app.game:aim_point(args.distance or 10);if not hit then return self:_fail('add_npc_route_waypoint',err) end;transform={position=hit.position,rotation={roll=0,pitch=0,yaw=0}}
        else local err;transform,err=self.app.game:capture_transform();if not transform then return self:_fail('add_npc_route_waypoint',err) end end
    end
    local waypoint,err=validate_npc_waypoint(self.app,{transform=transform,name=args.name,wait_seconds=args.wait_seconds,facing_yaw=args.facing_yaw,speed=args.speed,transition=args.transition,workspot_location_id=args.workspot_location_id,branch_fact=args.branch_fact,branch_value=args.branch_value,branch_target_id=args.branch_target_id},args.variant or 'patrol')
    if not waypoint then return self:_fail('add_npc_route_waypoint',err) end
    if waypoint.branch_target_id~='' then local exists=false;for _,wp in ipairs(route[field] or {}) do if wp.id==waypoint.branch_target_id then exists=true end end;if not exists then return self:_fail('add_npc_route_waypoint','branch_target_id must reference a waypoint in this route variant') end end
    self.app.model:snapshot();route[field]=route[field] or {};table.insert(route[field],waypoint);route.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return self:_ok('add_npc_route_waypoint',waypoint,{route_id=route.id,variant=waypoint.variant,index=#route[field]})
end

function Actions:update_npc_route_waypoint(args)
    args=args or {};local route=self.app.model:get_npc_route(args.route_id);if not route then return self:_fail('update_npc_route_waypoint','NPC route not found') end
    local field=ROUTE_VARIANTS[args.variant or 'patrol'];if not field then return self:_fail('update_npc_route_waypoint','variant must be patrol, alert, or combat') end
    for i,old in ipairs(route[field] or {}) do if old.id==args.waypoint_id then
        local merged=Util.deepcopy(old);for k,v in pairs(args.patch or {}) do merged[k]=v end
        local waypoint,err=validate_npc_waypoint(self.app,merged,args.variant or 'patrol');if not waypoint then return self:_fail('update_npc_route_waypoint',err) end
        if waypoint.branch_target_id~='' then local exists=false;for _,wp in ipairs(route[field] or {}) do if wp.id==waypoint.branch_target_id then exists=true end end;if not exists then return self:_fail('update_npc_route_waypoint','branch_target_id must reference a waypoint in this route variant') end end
        self.app.model:snapshot();route[field][i]=waypoint;route.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty();return waypoint
    end end
    return self:_fail('update_npc_route_waypoint','waypoint not found in selected route variant')
end

function Actions:delete_npc_route_waypoint(args)
    args=args or {};local route=self.app.model:get_npc_route(args.route_id);if not route then return self:_fail('delete_npc_route_waypoint','NPC route not found') end
    local field=ROUTE_VARIANTS[args.variant or 'patrol'];if not field then return self:_fail('delete_npc_route_waypoint','variant must be patrol, alert, or combat') end
    for i,wp in ipairs(route[field] or {}) do if wp.id==args.waypoint_id then self.app.model:snapshot();table.remove(route[field],i);for _,other in ipairs(route[field]) do if other.branch_target_id==args.waypoint_id then other.branch_target_id='';other.branch_fact='';other.branch_value=1 end end;route.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty();return {deleted=true,waypoint_id=args.waypoint_id} end end
    return self:_fail('delete_npc_route_waypoint','waypoint not found in selected route variant')
end

function Actions:move_npc_route_waypoint(args)
    args=args or {};local route=self.app.model:get_npc_route(args.route_id);if not route then return self:_fail('move_npc_route_waypoint','NPC route not found') end
    local field=ROUTE_VARIANTS[args.variant or 'patrol'];if not field then return self:_fail('move_npc_route_waypoint','variant must be patrol, alert, or combat') end
    local list=route[field] or {};local index
    for i,wp in ipairs(list) do if wp.id==args.waypoint_id then index=i;break end end
    if not index then return self:_fail('move_npc_route_waypoint','waypoint not found in selected route variant') end
    local delta=tonumber(args.delta) or 0;local target=math.max(1,math.min(#list,index+delta))
    if target==index then return route end
    self.app.model:snapshot();local item=table.remove(list,index);table.insert(list,target,item);route.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty();return route
end

function Actions:update_npc_route(args)
    args=args or {};local route=self.app.model:get_npc_route(args.id);if not route then return self:_fail('update_npc_route','NPC route not found') end
    local patch=args.patch or {};if patch.npc_id and not npc_population_object(self.app,patch.npc_id) then return self:_fail('update_npc_route','npc_id must reference a saved NPC population point') end
    local npc=patch.npc_id and npc_population_object(self.app,patch.npc_id) or self.app.model:get_object(route.npc_id)
    if not npc_population_object(self.app,npc and npc.id) then return self:_fail('update_npc_route','route must reference a saved NPC population point') end
    self.app.model:snapshot();if patch.npc_id and patch.npc_id~=route.npc_id then
        local old=self.app.model:get_object(route.npc_id);local ids=old and old.metadata and old.metadata.npc_route_ids or {};for i=#ids,1,-1 do if ids[i]==route.id then table.remove(ids,i) end end
        npc.metadata.npc_route_ids=npc.metadata.npc_route_ids or {};table.insert(npc.metadata.npc_route_ids,route.id);route.npc_id=npc.id
    end
    for _,key in ipairs({'name','loop','kind','notes'}) do if patch[key]~=nil then route[key]=patch[key] end end
    route.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty();return route
end

function Actions:delete_npc_route(route_id)
    local route=self.app.model:get_npc_route(route_id);if not route then return self:_fail('delete_npc_route','NPC route not found') end
    self.app.model:snapshot();local npc=self.app.model:get_object(route.npc_id);local ids=npc and npc.metadata and npc.metadata.npc_route_ids or {};for i=#ids,1,-1 do if ids[i]==route.id then table.remove(ids,i) end end
    for i,value in ipairs(self.app.model.data.npc_routes) do if value.id==route.id then table.remove(self.app.model.data.npc_routes,i);break end end
    self.app.model:touch();self.app:mark_dirty();return true
end

local function valid_quest_fact(value)
    value=Util.trim(value or '')
    return value=='' or value:match('^[%w_%.%-]+$')~=nil
end
local function encounter_by_id(app,id) return app.model:get_combat_encounter(id) end
local function has_volume(app,id,premise_id)
    if not id or id=='' then return true end
    local volume=app.model:get_volume(id);return volume and (not premise_id or volume.premise_id==premise_id) and volume or nil
end
local function group_by_id(encounter,id)
    for _,group in ipairs(encounter.groups or {}) do if group.id==id then return group end end
end

function Actions:create_combat_encounter(args)
    args=args or {};local premise_id=args.premise_id or self.app.selected_premise_id
    if not premise_id or not self.app.model:get_premise(premise_id) then return self:_fail('create_combat_encounter','select a valid location/premise first') end
    local area=args.area_volume_id or '';local trigger=args.trigger_volume_id or ''
    if area~='' and not has_volume(self.app,area,premise_id) then return self:_fail('create_combat_encounter','area_volume_id must reference a saved volume in this premise') end
    if trigger~='' and not has_volume(self.app,trigger,premise_id) then return self:_fail('create_combat_encounter','trigger_volume_id must reference a saved volume in this premise') end
    local fact=Util.trim(args.activation_fact or '');if not valid_quest_fact(fact) then return self:_fail('create_combat_encounter','activation_fact has invalid characters') end
    local activation_value=tonumber(args.activation_value) or 1;if activation_value%1~=0 or activation_value < -2147483648 or activation_value > 2147483647 then return self:_fail('create_combat_encounter','activation_value must be a signed 32-bit integer') end
    local item={id=Util.make_id('encounter'),name=Util.trim(args.name or '')~='' and Util.trim(args.name) or 'Combat Encounter',premise_id=premise_id,
        area_volume_id=area,trigger_volume_id=trigger,activation_fact=fact,activation_value=activation_value,
        reset_fact='',reset_value=0,groups={},waves={},faction_relations={},test_tag='ls_enc_'..Util.make_id('test'),notes=tostring(args.notes or '')}
    self.app.model:snapshot();table.insert(self.app.model.data.combat_encounters,item);self.app.model:touch();self.app:mark_dirty()
    return self:_ok('create_combat_encounter',item,{id=item.id,premise_id=premise_id})
end

function Actions:update_combat_encounter(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.id);if not encounter then return self:_fail('update_combat_encounter','encounter not found') end
    local patch=args.patch or {};local premise_id=patch.premise_id or encounter.premise_id
    if not self.app.model:get_premise(premise_id) then return self:_fail('update_combat_encounter','premise_id must reference a saved premise') end
    for _,key in ipairs({'area_volume_id','trigger_volume_id'}) do local id=patch[key];if id~=nil and id~='' and not has_volume(self.app,id,premise_id) then return self:_fail('update_combat_encounter',key..' must reference a saved volume in this premise') end end
    for _,key in ipairs({'activation_fact','reset_fact'}) do local fact=patch[key];if fact~=nil and not valid_quest_fact(fact) then return self:_fail('update_combat_encounter',key..' has invalid characters') end end
    for _,key in ipairs({'activation_value','reset_value'}) do local value=patch[key];if value~=nil then value=tonumber(value);if not value or value%1~=0 or value < -2147483648 or value > 2147483647 then return self:_fail('update_combat_encounter',key..' must be a signed 32-bit integer') end;patch[key]=value end end
    self.app.model:snapshot();for _,key in ipairs({'name','premise_id','area_volume_id','trigger_volume_id','activation_fact','activation_value','reset_fact','reset_value','notes'}) do if patch[key]~=nil then encounter[key]=patch[key] end end
    encounter.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty();return encounter
end

function Actions:create_encounter_group(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.encounter_id);if not encounter then return self:_fail('create_encounter_group','encounter not found') end
    local ids={};for _,id in ipairs(args.npc_ids or {}) do local npc=npc_population_object(self.app,id);if not npc or npc.premise_id~=encounter.premise_id then return self:_fail('create_encounter_group','npc_ids must reference saved NPC population points in this encounter premise') end;ids[#ids+1]=id end
    if #ids==0 then return self:_fail('create_encounter_group','add at least one saved NPC population point to the enemy group') end
    local spacing=tonumber(args.spacing or 1.5) or 1.5;if spacing<0 or spacing>50 or spacing~=spacing then return self:_fail('create_encounter_group','spacing must be between 0 and 50 metres') end
    local attitude=args.attitude or 'hostile';if not ({friendly=true,neutral=true,hostile=true})[attitude] then return self:_fail('create_encounter_group','attitude must be friendly, neutral, or hostile') end
    local group={id=Util.make_id('enemygroup'),name=Util.trim(args.name or '')~='' and Util.trim(args.name) or 'Enemy Group',faction=Util.trim(args.faction or ''),attitude=attitude,npc_ids=ids,spacing=spacing}
    self.app.model:snapshot();encounter.groups[#encounter.groups+1]=group;self.app.model:touch();self.app:mark_dirty();return group
end

function Actions:update_encounter_group(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.encounter_id);if not encounter then return self:_fail('update_encounter_group','encounter not found') end
    for _,group in ipairs(encounter.groups or {}) do if group.id==args.group_id then
        local patch=args.patch or {};local ids=patch.npc_ids or group.npc_ids
        for _,id in ipairs(ids or {}) do local npc=npc_population_object(self.app,id);if not npc or npc.premise_id~=encounter.premise_id then return self:_fail('update_encounter_group','npc_ids must reference saved NPC population points in this encounter premise') end end
        if #(ids or {})==0 then return self:_fail('update_encounter_group','enemy group must contain at least one NPC population point') end
        local spacing=patch.spacing~=nil and tonumber(patch.spacing) or group.spacing;if not spacing or spacing<0 or spacing>50 then return self:_fail('update_encounter_group','spacing must be between 0 and 50 metres') end
        if patch.attitude~=nil and not ({friendly=true,neutral=true,hostile=true})[patch.attitude] then return self:_fail('update_encounter_group','attitude must be friendly, neutral, or hostile') end
        self.app.model:snapshot();for _,key in ipairs({'name','faction','attitude','npc_ids'}) do if patch[key]~=nil then group[key]=patch[key] end end;group.spacing=spacing;self.app.model:touch();self.app:mark_dirty();return group
    end end
    return self:_fail('update_encounter_group','enemy group not found')
end

function Actions:delete_encounter_group(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.encounter_id);if not encounter then return self:_fail('delete_encounter_group','encounter not found') end
    for i,group in ipairs(encounter.groups or {}) do if group.id==args.group_id then
        self.app.model:snapshot();table.remove(encounter.groups,i)
        for _,wave in ipairs(encounter.waves or {}) do local kept={};for _,id in ipairs(wave.group_ids or {}) do if id~=args.group_id then kept[#kept+1]=id end end;wave.group_ids=kept end
        self.app.model:touch();self.app:mark_dirty();return {deleted=true,group_id=args.group_id}
    end end
    return self:_fail('delete_encounter_group','group not found')
end

function Actions:create_encounter_wave(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.encounter_id);if not encounter then return self:_fail('create_encounter_wave','encounter not found') end
    local activation=args.activation or 'immediate';if not ({immediate=true,volume=true,fact=true,after_wave=true})[activation] then return self:_fail('create_encounter_wave','activation must be immediate, volume, fact, or after_wave') end
    local ids={};for _,id in ipairs(args.group_ids or {}) do if not group_by_id(encounter,id) then return self:_fail('create_encounter_wave','group_ids must reference groups in this encounter') end;ids[#ids+1]=id end
    if #ids==0 then return self:_fail('create_encounter_wave','wave must include at least one enemy group') end
    local volume=args.trigger_volume_id;if not volume or volume=='' then volume=encounter.trigger_volume_id or '' end
    if activation=='volume' and (volume=='' or not has_volume(self.app,volume,encounter.premise_id)) then return self:_fail('create_encounter_wave','volume activation requires a trigger volume in this encounter premise') end
    local fact=Util.trim(args.fact_name or '')
    if fact~='' and not valid_quest_fact(fact) then return self:_fail('create_encounter_wave','fact_name has invalid characters') end
    if activation=='fact' and (fact=='' or not valid_quest_fact(fact)) then return self:_fail('create_encounter_wave','fact activation requires a valid fact_name') end
    local after=args.after_wave_id or ''
    if activation=='after_wave' and (after=='' or not (function() for _,w in ipairs(encounter.waves) do if w.id==after then return true end end end)()) then return self:_fail('create_encounter_wave','after_wave activation requires an existing wave ID') end
    local delay=tonumber(args.delay_seconds or 0) or 0;if delay<0 or delay>3600 or delay~=delay then return self:_fail('create_encounter_wave','delay_seconds must be between 0 and 3600') end
    local fact_value=tonumber(args.fact_value) or 1;if fact_value%1~=0 or fact_value < -2147483648 or fact_value > 2147483647 then return self:_fail('create_encounter_wave','fact_value must be a signed 32-bit integer') end
    local wave={id=Util.make_id('wave'),name=Util.trim(args.name or '')~='' and Util.trim(args.name) or ('Wave '..tostring(#encounter.waves+1)),group_ids=ids,
        activation=activation,trigger_volume_id=volume,fact_name=fact,fact_value=fact_value,after_wave_id=after,delay_seconds=delay}
    self.app.model:snapshot();encounter.waves[#encounter.waves+1]=wave;self.app.model:touch();self.app:mark_dirty();return wave
end

function Actions:update_encounter_wave(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.encounter_id);if not encounter then return self:_fail('update_encounter_wave','encounter not found') end
    for _,wave in ipairs(encounter.waves or {}) do if wave.id==args.wave_id then
        local patch=args.patch or {};local activation=patch.activation or wave.activation
        if not ({immediate=true,volume=true,fact=true,after_wave=true})[activation] then return self:_fail('update_encounter_wave','invalid activation mode') end
        local ids=patch.group_ids or wave.group_ids;for _,id in ipairs(ids or {}) do if not group_by_id(encounter,id) then return self:_fail('update_encounter_wave','group_ids must reference groups in this encounter') end end
        local volume=patch.trigger_volume_id~=nil and patch.trigger_volume_id or wave.trigger_volume_id
        if not volume or volume=='' then volume=encounter.trigger_volume_id or '' end
        if activation=='volume' and (volume=='' or not has_volume(self.app,volume,encounter.premise_id)) then return self:_fail('update_encounter_wave','volume activation requires a valid trigger volume') end
        local fact=patch.fact_name~=nil and patch.fact_name or wave.fact_name
        if fact and fact~='' and not valid_quest_fact(fact) then return self:_fail('update_encounter_wave','fact_name has invalid characters') end
        if activation=='fact' and (Util.trim(fact or '')=='' or not valid_quest_fact(fact)) then return self:_fail('update_encounter_wave','fact activation requires a valid fact_name') end
        if patch.fact_value~=nil then local value=tonumber(patch.fact_value);if not value or value%1~=0 or value < -2147483648 or value > 2147483647 then return self:_fail('update_encounter_wave','fact_value must be a signed 32-bit integer') end;patch.fact_value=value end
        local after=patch.after_wave_id~=nil and patch.after_wave_id or wave.after_wave_id or ''
        if activation=='after_wave' then local found=false;for _,candidate in ipairs(encounter.waves) do if candidate.id==after and candidate.id~=wave.id then found=true end end;if not found then return self:_fail('update_encounter_wave','after_wave activation requires a different existing wave ID') end end
        local delay=patch.delay_seconds~=nil and tonumber(patch.delay_seconds) or tonumber(wave.delay_seconds) or 0
        if not delay or delay<0 or delay>3600 then return self:_fail('update_encounter_wave','delay_seconds must be between 0 and 3600') end
        if patch.trigger_volume_id~=nil and patch.trigger_volume_id~='' and not has_volume(self.app,patch.trigger_volume_id,encounter.premise_id) then return self:_fail('update_encounter_wave','trigger_volume_id must reference a volume in this premise') end
        self.app.model:snapshot();for _,key in ipairs({'name','activation','group_ids','trigger_volume_id','fact_name','fact_value','after_wave_id','delay_seconds'}) do if patch[key]~=nil then wave[key]=patch[key] end end
        self.app.model:touch();self.app:mark_dirty();return wave
    end end
    return self:_fail('update_encounter_wave','wave not found')
end

function Actions:delete_encounter_wave(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.encounter_id);if not encounter then return self:_fail('delete_encounter_wave','encounter not found') end
    for i,wave in ipairs(encounter.waves or {}) do if wave.id==args.wave_id then
        self.app.model:snapshot();table.remove(encounter.waves,i);for _,other in ipairs(encounter.waves) do if other.after_wave_id==args.wave_id then other.after_wave_id='';other.activation='immediate' end end
        self.app.model:touch();self.app:mark_dirty();return {deleted=true,wave_id=args.wave_id}
    end end
    return self:_fail('delete_encounter_wave','wave not found')
end

function Actions:set_encounter_faction_relation(args)
    args=args or {};local encounter=encounter_by_id(self.app,args.encounter_id);if not encounter then return self:_fail('set_encounter_faction_relation','encounter not found') end
    local source,target=Util.trim(args.source_faction or ''),Util.trim(args.target_faction or '');local attitude=args.attitude or 'hostile'
    if source=='' or target=='' then return self:_fail('set_encounter_faction_relation','source_faction and target_faction are required') end
    if not ({friendly=true,neutral=true,hostile=true})[attitude] then return self:_fail('set_encounter_faction_relation','attitude must be friendly, neutral, or hostile') end
    self.app.model:snapshot();encounter.faction_relations=encounter.faction_relations or {}
    for _,row in ipairs(encounter.faction_relations) do if row.source_faction==source and row.target_faction==target then row.attitude=attitude;self.app.model:touch();self.app:mark_dirty();return row end end
    local row={source_faction=source,target_faction=target,attitude=attitude};table.insert(encounter.faction_relations,row);self.app.model:touch();self.app:mark_dirty();return row
end

function Actions:test_combat_encounter(encounter_id,wave_id)
    local encounter=encounter_by_id(self.app,encounter_id);if not encounter then return self:_fail('test_combat_encounter','encounter not found') end
    local wave;for _,item in ipairs(encounter.waves or {}) do if item.id==wave_id then wave=item;break end end
    if wave_id and not wave then return self:_fail('test_combat_encounter','wave not found') end
    if not self.app.live_tools then return self:_fail('test_combat_encounter','temporary NPC runtime tools are unavailable') end
    local reset,reset_err=self.app.live_tools:despawn_tag(encounter.test_tag);if not reset then return self:_fail('test_combat_encounter',reset_err) end
    local waves=wave and {wave} or encounter.waves;if #waves==0 then return self:_fail('test_combat_encounter','add at least one wave before testing the encounter') end
    local spawned={};local count=0
    for _,current in ipairs(waves or {}) do for _,group_id in ipairs(current.group_ids or {}) do local group=group_by_id(encounter,group_id)
        if group then for index,npc_id in ipairs(group.npc_ids or {}) do
            count=count+1;if count>64 then self.app.live_tools:despawn_tag(encounter.test_tag);return self:_fail('test_combat_encounter','test is capped at 64 temporary NPCs') end
            local npc=npc_population_object(self.app,npc_id);local cfg=npc and npc.metadata.npc_population
            if not cfg then self.app.live_tools:despawn_tag(encounter.test_tag);return self:_fail('test_combat_encounter','enemy group contains a missing NPC population point') end
            local p=npc.transform.position;local result,err=self.app.live_tools:spawn_record({record=cfg.record,appearance=cfg.appearance,position={x=p.x,y=p.y+(index-1)*(tonumber(group.spacing) or 1.5),z=p.z},yaw=(npc.transform.rotation or {}).yaw or 0,tag=encounter.test_tag})
            if not result then self.app.live_tools:despawn_tag(encounter.test_tag);return self:_fail('test_combat_encounter','temporary enemy spawn failed: '..tostring(err)) end
            result.population_id=npc_id;result.group_id=group.id;result.wave_id=current.id;table.insert(spawned,result)
        end end
    end end
    return self:_ok('test_combat_encounter',{encounter_id=encounter.id,wave_id=wave and wave.id or nil,spawned=spawned,count=#spawned,tag=encounter.test_tag,
        status='temporary_entities_spawned',runtime_limit='No trigger, faction AI, quest fact, navigation, or reinforcement behavior is executed by this preview.'})
end

function Actions:reset_combat_encounter(encounter_id)
    local encounter=encounter_by_id(self.app,encounter_id);if not encounter then return self:_fail('reset_combat_encounter','encounter not found') end
    if not self.app.live_tools then return self:_fail('reset_combat_encounter','temporary NPC runtime tools are unavailable') end
    local result,err=self.app.live_tools:despawn_tag(encounter.test_tag);if not result then return self:_fail('reset_combat_encounter',err) end;return result
end

function Actions:delete_combat_encounter(encounter_id)
    local encounter=encounter_by_id(self.app,encounter_id);if not encounter then return self:_fail('delete_combat_encounter','encounter not found') end
    if self.app.live_tools then self.app.live_tools:despawn_tag(encounter.test_tag) end
    self.app.model:snapshot();for i,item in ipairs(self.app.model.data.combat_encounters) do if item.id==encounter.id then table.remove(self.app.model.data.combat_encounters,i);break end end
    self.app.model:touch();self.app:mark_dirty();return true
end

function Actions:create_npc_population(args)
    args=args or {}
    local asset=self.app.model:get_asset(args.asset_id)
    local wb=asset and asset.metadata and asset.metadata.world_builder
    if not asset or not wb or wb.definition_key~='entity_record' then return self:_fail('create_npc_population','select/import a World Builder Entity Record (Character.*), not an entity mesh or temporary preview') end
    local record=Util.trim(args.record or asset.template or '')
    if not record:match('^Character%.[%w_%.%-]+$') then return self:_fail('create_npc_population','record must be a Character.* TweakDB record') end
    local config,config_err=population_config(args,record);if not config then return self:_fail('create_npc_population',config_err) end
    self.app.model:snapshot()
    local object,err=self:place_asset(asset.id,args.source or 'player',{premise_id=args.premise_id,room_id=args.room_id,name=args.name or asset.name,
        transform=args.transform,spawn=false})
    if not object then return nil,err end
    object.kind='npc_population';object.metadata=object.metadata or {};object.metadata.npc_population=config
    local data=population_spawnable(object)
    if not data then self.app.model:delete_object(object.id);return self:_fail('create_npc_population','World Builder Entity Record data is incomplete; re-import the record from the live catalog') end
    data.spawnData=record;data.app=config.appearance;data.spawnOnStart=config.spawn_on_start;data.alwaysSpawned=config.always_spawned
    data.primaryRange=config.primary_range;data.secondaryRange=config.secondary_range
    self.app.model:touch();self.app:mark_dirty()
    local preview_result,preview_error
    if args.preview==true then preview_result,preview_error=self.app.placement:spawn(object) end
    return self:_ok('create_npc_population',object,{id=object.id,record=record,native_node='worldPopulationSpawnerNode',persistent=true,
        preview_spawned=preview_result~=nil,profile_fields_handoff={'attitude','faction','level','archetype','idle_behavior','despawn_distance','conditions'}},preview_error)
end

function Actions:update_npc_population(object_id,patch)
    patch=patch or {};local object=self.app.model:get_object(object_id)
    if not object or not (object.metadata and object.metadata.npc_population) then return self:_fail('update_npc_population','NPC population point not found') end
    local cfg=Util.deepcopy(object.metadata.npc_population)
    for _,key in ipairs({'appearance','attitude','faction','level','archetype','idle_behavior','despawn_distance','conditions','spawn_on_start','always_spawned','primary_range','secondary_range'}) do if patch[key]~=nil then cfg[key]=patch[key] end end
    local validated,err=population_config(cfg,cfg.record);if not validated then return self:_fail('update_npc_population',err) end
    local data=population_spawnable(object);if not data then return self:_fail('update_npc_population','World Builder Entity Record data is unavailable') end
    data.spawnData=validated.record;data.app=validated.appearance;data.spawnOnStart=validated.spawn_on_start;data.alwaysSpawned=validated.always_spawned
    data.primaryRange=validated.primary_range;data.secondaryRange=validated.secondary_range
    self.app.model:snapshot();object.metadata.npc_population=validated;object.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return object
end

function Actions:update_interactable(object_id,patch)
    patch=patch or {};local object=self.app.model:get_object(object_id)
    if not object or not (object.metadata and object.metadata.interactable) then return self:_fail('update_interactable','interactable object not found',{id=object_id}) end
    local config=Util.deepcopy(object.metadata.interactable)
    config.entity_record=config.entity_record or '';config.item_record=config.item_record or '';config.loot_table=config.loot_table or '';config.fact_name=config.fact_name or '';config.loot_items=config.loot_items or {}
    for _,field in ipairs({'kind','entity_record','item_record','loot_table','loot_items','lock_state','fact_name','fact_value'}) do if patch[field]~=nil then config[field]=patch[field] end end
    local kind=config.kind
    if not INTERACTABLE_KINDS[kind] then return self:_fail('update_interactable','kind must be door, loot_container, shard, or item') end
    if (kind=='shard' or kind=='item') and not tostring(config.item_record or ''):match('^Items%.[%w_%.%-]+$') then return self:_fail('update_interactable','shard/item requires a valid Items.* TweakDB record') end
    if config.item_record~='' and not valid_record(config.item_record,'Items') then return self:_fail('update_interactable','item_record must be an Items.* TweakDB record') end
    if kind=='loot_container' and not tostring(config.loot_table or ''):match('^LootTables%.[%w_%.%-]+$') then return self:_fail('update_interactable','loot_container requires a LootTables.* record') end
    if type(config.loot_items)~='table' then return self:_fail('update_interactable','loot_items must be an array') end
    for i,row in ipairs(config.loot_items) do
        if type(row)~='table' or not tostring(row.item_record or ''):match('^Items%.[%w_%.%-]+$') then return self:_fail('update_interactable','loot_items['..i..'] requires an Items.* record') end
        local lo,hi=tonumber(row.count_min) or 1,tonumber(row.count_max) or 1
        local chance=tonumber(row.drop_chance) or 1
        if lo<1 or hi<lo or lo%1~=0 or hi%1~=0 or chance<0 or chance>1 then return self:_fail('update_interactable','loot_items['..i..'] has invalid counts or drop_chance') end
    end
    if config.loot_table~='' and not valid_record(config.loot_table,'LootTables') then return self:_fail('update_interactable','loot_table must be a LootTables.* TweakDB record') end
    if tostring(config.fact_name or '')~='' and not tostring(config.fact_name):match('^[%w_%.%-]+$') then return self:_fail('update_interactable','invalid quest fact name') end
    if tostring(config.entity_record or '')~='' and not tostring(config.entity_record):match('^[%w_]+%.[%w_%.%-]+$') then return self:_fail('update_interactable','entity_record must be a dotted game record identifier') end
    config.fact_value=math.floor(tonumber(config.fact_value) or 1)
    if config.fact_value < -2147483648 or config.fact_value > 2147483647 then return self:_fail('update_interactable','fact_value must fit a signed 32-bit quest fact') end
    if (kind=='door' or kind=='loot_container') and config.lock_state~='locked' and config.lock_state~='unlocked' then return self:_fail('update_interactable','door/loot lock_state must be locked or unlocked') end
    if (kind=='item' or kind=='shard') and config.lock_state~='not_applicable' then return self:_fail('update_interactable','shards/items use lock_state=not_applicable') end
    self.app.model:snapshot();object.metadata.interactable=config;object.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty()
    return object
end

function Actions:spawn_selected()
    local kind,item=self.app.selection.kind,self.app.selection:resolve()
    if kind=='object' and item then
        local entity,err=self.app.placement:spawn(item);if not entity then return self:_fail('spawn_selected',err,{kind=kind,id=item.id}) end
        return self:_ok('spawn_selected',entity,{kind=kind,id=item.id,entity_id=tostring(entity)})
    end
    if kind=='premise' and item then
        local result=self.app.placement:spawn_premise(item.id);local warning=#result.failed>0 and string.format('%d object(s) failed to spawn; see DEBUG LOG.',#result.failed) or nil
        return self:_ok('spawn_selected',result,{kind=kind,id=item.id,spawned=#result.spawned,failed=#result.failed},warning)
    end
    return self:_fail('spawn_selected','select an object or premise')
end

function Actions:refresh_selected()
    local kind,item=self.app.selection.kind,self.app.selection:resolve()
    if kind=='object' and item then
        local entity,err=self.app.placement:refresh(item);if not entity then return self:_fail('refresh_selected',err,{kind=kind,id=item.id}) end
        return self:_ok('refresh_selected',entity,{kind=kind,id=item.id,entity_id=tostring(entity)})
    end
    if kind=='room' and item then
        local result,err=self.app.builder:rebuild_room_shell(item.id);if not result then return self:_fail('refresh_selected',err,{kind=kind,id=item.id}) end
        return self:_ok('refresh_selected',result,{kind=kind,id=item.id,objects=result.object_count})
    end
    if kind=='premise' and item then
        local removed=self.app.placement:despawn_premise(item.id);local result=self.app.placement:spawn_premise(item.id)
        local failed=#removed.failed+#result.failed;local warning=failed>0 and string.format('%d runtime operation(s) failed; see DEBUG LOG.',failed) or nil
        return self:_ok('refresh_selected',result,{kind=kind,id=item.id,despawn_failed=#removed.failed,spawned=#result.spawned,spawn_failed=#result.failed},warning)
    end
    return self:_fail('refresh_selected','select an object, room, or premise')
end

function Actions:despawn_selected()
    local kind,item=self.app.selection.kind,self.app.selection:resolve()
    if kind=='object' and item then
        local ok,err=self.app.placement:despawn(item);if not ok then return self:_fail('despawn_selected',err,{kind=kind,id=item.id}) end
        return self:_ok('despawn_selected',true,{kind=kind,id=item.id})
    end
    if kind=='premise' and item then
        local result=self.app.placement:despawn_premise(item.id);local warning=#result.failed>0 and string.format('%d object(s) failed to despawn; see DEBUG LOG.',#result.failed) or nil
        return self:_ok('despawn_selected',true,{kind=kind,id=item.id,failed=#result.failed},warning)
    end
    return self:_fail('despawn_selected','select an object or premise')
end

function Actions:update_selected(patch)
    local kind,id=self.app.selection.kind,self.app.selection.id;if not kind or not id then return self:_fail('update_selected','nothing selected') end
    patch=patch or {};local model=self.app.model;local item,err
    local existing=self.app.selection:resolve()
    if not existing then return self:_fail('update_selected','selected item no longer exists') end
    if kind=='cover_node' then
        local item,err=self:update_cover_node({id=id,patch=patch});if not item then return nil,err end
        return item
    end
    if kind=='object' and existing.locked and patch.locked~=false then return self:_fail('update_selected','object is locked; unlock it before editing') end
    if kind=='room' then
        local valid,validation_err=Builder.validate_size(patch.size or existing.size,patch.wall_thickness or existing.wall_thickness)
        if not valid then return self:_fail('update_selected',validation_err) end
    end
    local rebuild_room=kind=='room' and (patch.size~=nil or patch.wall_thickness~=nil or patch.openings~=nil)
    local room_was_live=false
    if rebuild_room then
        for _,object in ipairs(model.data.objects) do if object.room_id==id and self.app.placement:is_tracked(object) then room_was_live=true;break end end
    end
    local transform=patch.transform
    local remaining=Util.deepcopy(patch);remaining.transform=nil
    -- Inspector caches are editing buffers, never authoritative runtime ownership.
    remaining.runtime=nil;remaining.shell_object_ids=nil
    -- A World Builder path lives both in the friendly template field and in the
    -- serialized Spawn New entry. Keep them synchronized so editing the path
    -- changes what is spawned instead of only changing the label in the UI.
    if (kind=='object' or kind=='asset') and remaining.metadata and remaining.metadata.world_builder and remaining.template~=nil then
        local wb=remaining.metadata.world_builder
        wb.resource_path=remaining.template
        if wb.entry and type(wb.entry.data)=='table' and wb.entry.data.spawnData~=nil then wb.entry.data.spawnData=remaining.template end
    end
    if transform and (kind=='location' or kind=='premise' or kind=='room' or kind=='object' or kind=='volume' or kind=='camera' or kind=='cover_node') then
        item,err=self.app.authoring:set_transform(kind,id,transform,true,kind=='object' and existing.locked and patch.locked==false)
        if not item then return self:_fail('update_selected',err,{kind=kind,id=id}) end
    end
    local has_remaining=false;for _ in pairs(remaining) do has_remaining=true;break end
    if has_remaining or not item then
        if kind=='location' then item,err=model:update_location(id,remaining)
        elseif kind=='route' then item,err=model:update_route(id,remaining)
        elseif kind=='premise' then item,err=model:update_premise(id,remaining)
        elseif kind=='room' then item,err=model:update_room(id,remaining)
        elseif kind=='object' then item,err=model:update_object(id,remaining)
        elseif kind=='volume' then item,err=model:update_volume(id,remaining)
        elseif kind=='camera' then item,err=model:update_camera(id,remaining)
        elseif kind=='cover_node' then item,err=model:update_cover_node(id,remaining)
        elseif kind=='scene' then item,err=self.app.scenes:update(id,remaining)
        elseif kind=='asset' then item,err=model:update_asset(id,remaining)
        else return self:_fail('update_selected','unsupported selection',{kind=kind,id=id}) end
    end
    if not item then return self:_fail('update_selected',err,{kind=kind,id=id}) end
    if kind=='object' and item.locked and self.app.runtime_shell then self.app.runtime_shell:unfocus(item) end
    self.app:mark_dirty()
    local warning
    if kind=='object' then
        local tracked=self.app.placement:is_tracked(item)
        if item.enabled==false or item.visible==false then
            if tracked then local ok,remove_err=self.app.placement:despawn(item);if not ok then warning='Saved, but live despawn failed: '..tostring(remove_err) end end
        elseif self.app.model.data.settings.workspace.live_preview and tracked then
            local _,refresh_err=self.app.placement:refresh(item);if refresh_err then warning='Saved, but live refresh failed: '..tostring(refresh_err) end
        elseif self.app.model.data.settings.workspace.live_preview and (patch.enabled~=nil or patch.visible~=nil) then
            local _,spawn_err=self.app.placement:spawn(item);if spawn_err then warning='Saved, but live spawn failed: '..tostring(spawn_err) end
        end
    elseif rebuild_room then
        local rebuilt,rebuild_err=self.app.builder:rebuild_room_shell(id)
        if not rebuilt then warning='Dimensions saved, but shell rebuild failed: '..tostring(rebuild_err)
        elseif room_was_live then local runtime,runtime_err=self.app.placement:spawn_room_shell(id);if not runtime then warning=runtime_err end end
    elseif kind=='room' or kind=='premise' then
        local _,refresh_warning=self.app.ent_tools:refresh_live_scope(kind,id);warning=refresh_warning
    end
    return self:_ok('update_selected',item,{kind=kind,id=id},warning)
end

function Actions:duplicate_selected()
    local kind,id=self.app.selection.kind,self.app.selection.id;local copy,err
    if kind=='object' then
        local source=self.app.model:get_object(id)
        if source and source.locked then return self:_fail('duplicate_selected','object is locked; unlock it before duplicating',{kind=kind,id=id}) end
        copy,err=self.app.model:duplicate_object(id)
        if copy and copy.metadata and copy.metadata.room_kit==true then
            copy.metadata.generated=false;copy.metadata.room_kit=false;copy.metadata.detached_from_room=true;copy.metadata.detached_at=Util.now_iso();copy.layer='decoration';copy.locked=false
        end
    elseif kind=='location' then copy,err=self.app.model:duplicate_location(id)
    elseif kind=='volume' then
        local source=self.app.model:get_volume(id);if source then local value=Util.deepcopy(source);value.id=nil;value.name=value.name..' Copy';value.transform.position.x=value.transform.position.x+0.5;copy=self.app.model:add_volume(value) else err='volume not found' end
    elseif kind=='camera' then
        local source=self.app.model:get_camera(id);if source then local value=Util.deepcopy(source);value.id=nil;value.name=value.name..' Copy';value.transform.position.x=value.transform.position.x+0.5;if value.look_at then value.look_at.x=(value.look_at.x or 0)+0.5 end;copy=self.app.model:add_camera(value) else err='camera not found' end
    elseif kind=='cover_node' then
        local source=self.app.model:get_cover_node(id);if source then local value=Util.deepcopy(source);value.id=nil;value.name=value.name..' Copy';value.transform.position.x=value.transform.position.x+0.5;copy=self.app.model:add_cover_node(value) else err='cover node not found' end
    elseif kind=='asset' then
        local source=self.app.model:get_asset(id);if source then local value=Util.deepcopy(source);value.id=nil;value.name=value.name..' Copy';copy=self.app.model:add_asset(value) else err='asset not found' end
    else return self:_fail('duplicate_selected','duplicate is supported for objects, locations, volumes, cameras, and assets',{kind=kind,id=id}) end
    if not copy then return self:_fail('duplicate_selected',err,{kind=kind,id=id}) end
    self.app.selection:set(kind,copy.id);self.app:mark_dirty()
    return self:_ok('duplicate_selected',copy,{kind=kind,source_id=id,id=copy.id})
end

local function resolve_object_group(model,ids)
    if type(ids)~='table' or #ids==0 then return nil,'select at least one object' end
    local objects,seen={},{ }
    for _,id in ipairs(ids) do
        if not seen[id] then local object=model:get_object(id);if not object then return nil,'object not found: '..tostring(id) end;seen[id]=true;table.insert(objects,object) end
    end
    return objects
end

function Actions:set_object_group_state(ids,patch)
    local objects,err=resolve_object_group(self.app.model,ids);if not objects then return self:_fail('group_state',err) end
    patch=patch or {};if patch.enabled==nil and patch.visible==nil and patch.locked==nil then return self:_fail('group_state','no state change was specified') end
    self.app.model:snapshot();local changed,spawned,despawned,failed=0,0,0,{}
    for _,object in ipairs(objects) do
        local touched=false
        for _,key in ipairs({'enabled','visible','locked'}) do if patch[key]~=nil and object[key]~=(patch[key]==true) then object[key]=patch[key]==true;touched=true end end
        if object.locked and self.app.runtime_shell then self.app.runtime_shell:unfocus(object) end
        if object.enabled==false or object.visible==false then
            if self.app.placement:is_tracked(object) then local ok,remove_err=self.app.placement:despawn(object);if ok then despawned=despawned+1 else table.insert(failed,{id=object.id,error=remove_err}) end end
        elseif self.app.model.data.settings.workspace.live_preview and not self.app.placement:is_tracked(object) and (patch.enabled~=nil or patch.visible~=nil) then
            local id,spawn_err=self.app.placement:spawn(object);if id then spawned=spawned+1 else table.insert(failed,{id=object.id,error=spawn_err}) end
        end
        if touched then changed=changed+1;object.updated_at=Util.now_iso() end
    end
    self.app.model:touch();self.app:mark_dirty();self.app.selection.revision=self.app.selection.revision+1
    local result={count=#objects,changed=changed,spawned=spawned,despawned=despawned,failed=failed}
    return self:_ok('group_state',result,{count=#objects,changed=changed,failed=#failed},#failed>0 and (tostring(#failed)..' runtime operation(s) failed') or nil)
end

function Actions:spawn_object_group(ids,spawn)
    local objects,err=resolve_object_group(self.app.model,ids);if not objects then return self:_fail('group_runtime',err) end
    local changed,failed=0,{}
    for _,object in ipairs(objects) do
        if spawn~=false then local id,e=self.app.placement:spawn(object);if id then changed=changed+1 else table.insert(failed,{id=object.id,error=e}) end
        else local ok,e,did=self.app.placement:despawn(object);if ok then if did then changed=changed+1 end else table.insert(failed,{id=object.id,error=e}) end end
    end
    local result={count=#objects,changed=changed,failed=failed,spawned=spawn~=false}
    return self:_ok('group_runtime',result,{count=#objects,changed=changed,failed=#failed},#failed>0 and (tostring(#failed)..' runtime operation(s) failed') or nil)
end

function Actions:duplicate_object_group(ids,offset)
    local objects,err=resolve_object_group(self.app.model,ids);if not objects then return self:_fail('group_duplicate',err) end
    for _,object in ipairs(objects) do if object.locked then return self:_fail('group_duplicate','object '..tostring(object.name)..' is locked') end end
    offset=offset or {x=self.app.model.data.settings.snapping.grid or 0.25,y=0,z=0};local queue={}
    for _,source in ipairs(objects) do
        local copy=Util.deepcopy(source);copy.id=nil;copy.created_at=nil;copy.updated_at=nil;copy.runtime=nil;copy.name=source.name..' Copy'
        copy.transform.position.x=copy.transform.position.x+(tonumber(offset.x) or 0);copy.transform.position.y=copy.transform.position.y+(tonumber(offset.y) or 0);copy.transform.position.z=copy.transform.position.z+(tonumber(offset.z) or 0)
        if copy.metadata and copy.metadata.room_kit==true then copy.metadata.generated=false;copy.metadata.room_kit=false;copy.metadata.detached_from_room=true;copy.metadata.detached_at=Util.now_iso();copy.layer='decoration';copy.locked=false end
        table.insert(queue,copy)
    end
    local copies=self.app.model:add_objects(queue);local failed={}
    if self.app.model.data.settings.workspace.live_preview then for _,copy in ipairs(copies) do local _,spawn_err=self.app.placement:spawn(copy);if spawn_err then table.insert(failed,{id=copy.id,error=spawn_err}) end end end
    local copy_ids={};for _,copy in ipairs(copies) do table.insert(copy_ids,copy.id) end
    self.app.selection:set_object_group(copy_ids,copy_ids[#copy_ids],'locationstudio');self.app:mark_dirty()
    if self.app.runtime_shell then self.app.runtime_shell:focus_many(copies,copy_ids[#copy_ids]) end
    return self:_ok('group_duplicate',{objects=copies,count=#copies,failed=failed},{count=#copies,failed=#failed},#failed>0 and (tostring(#failed)..' duplicate(s) failed to spawn') or nil)
end

function Actions:delete_object_group(ids)
    local objects,err=resolve_object_group(self.app.model,ids);if not objects then return self:_fail('group_delete',err) end
    for _,object in ipairs(objects) do if object.locked then return self:_fail('group_delete','object '..tostring(object.name)..' is locked') end end
    local failed={}
    for _,object in ipairs(objects) do local ok,remove_err=self.app.placement:despawn(object);if not ok then table.insert(failed,{id=object.id,error=remove_err}) end end
    if #failed>0 then return self:_fail('group_delete','Objects retained because '..#failed..' runtime removal(s) failed',{failed=#failed}) end
    local ok,delete_err,count=self.app.model:delete_objects(ids);if not ok then return self:_fail('group_delete',delete_err) end
    self.app.selection:clear_object_group();self.app:mark_dirty()
    return self:_ok('group_delete',{deleted=count},{count=count})
end

function Actions:replace_object_group_asset(ids,asset_id)
    local objects,err=resolve_object_group(self.app.model,ids);if not objects then return self:_fail('group_replace_asset',err) end
    local asset=self.app.model:get_asset(asset_id);if not asset then return self:_fail('group_replace_asset','Choose an asset first.') end
    local wb=asset.metadata and asset.metadata.world_builder;local is_wb=type(wb)=='table'
    local path=is_wb and (wb.resource_path or ((((wb.entry or {}).data or {}).spawnData))) or asset.template
    path=Util.trim(path or '')
    if path=='' then return self:_fail('group_replace_asset','Selected asset has no game resource path.') end
    for _,object in ipairs(objects) do
        if object.locked then return self:_fail('group_replace_asset','object '..tostring(object.name)..' is locked') end
        if object.metadata and object.metadata.room_collision==true then return self:_fail('group_replace_asset','collision pieces cannot be replaced') end
        if object.metadata and object.metadata.room_kit==true and (not is_wb or wb.definition_key~='mesh_static') then return self:_fail('group_replace_asset','room construction pieces require an imported Static Mesh') end
    end
    local was_live={};local failed={}
    for _,object in ipairs(objects) do
        if self.app.placement:is_tracked(object) then
            was_live[object.id]=true;local ok,remove_err=self.app.placement:despawn(object)
            if not ok then table.insert(failed,{id=object.id,error=remove_err}) end
        end
    end
    if #failed>0 then return self:_fail('group_replace_asset','Replacement cancelled because '..#failed..' live object(s) could not be removed.',{failed=#failed}) end
    self.app.model:snapshot()
    for _,object in ipairs(objects) do
        object.metadata=object.metadata or {}
        object.metadata.world_builder=is_wb and Util.deepcopy(wb) or nil
        if is_wb then
            object.metadata.world_builder.resource_path=path
            object.metadata.world_builder.entry=type(object.metadata.world_builder.entry)=='table' and object.metadata.world_builder.entry or {}
            object.metadata.world_builder.entry.name=path
            object.metadata.world_builder.entry.data=type(object.metadata.world_builder.entry.data)=='table' and object.metadata.world_builder.entry.data or {}
            object.metadata.world_builder.entry.data.spawnData=path
        end
        object.metadata.replacement_asset_id=asset.id;object.metadata.replacement_asset_name=asset.name
        object.template=path;object.appearance=asset.appearance or '';object.updated_at=Util.now_iso()
    end
    self.app.model:mark_asset_used(asset.id);self.app.model:touch();self.app:mark_dirty()
    for _,object in ipairs(objects) do
        if was_live[object.id] then local _,spawn_err=self.app.placement:spawn(object);if spawn_err then table.insert(failed,{id=object.id,error=spawn_err}) end end
    end
    local result={objects=objects,count=#objects,asset=asset,failed=failed}
    return self:_ok('group_replace_asset',result,{count=#objects,asset_id=asset.id,failed=#failed},#failed>0 and (tostring(#failed)..' replaced object(s) failed to respawn') or nil)
end

function Actions:history(direction,steps)
    if direction~='undo' and direction~='redo' then return nil,'invalid history direction' end
    steps=math.floor(tonumber(steps) or 1)
    if steps<1 then return nil,'steps must be at least 1' end
    if self.app.authoring_plans and self.app.authoring_plans:status().recovery_required then return nil,'Retry authoring-plan rollback or keep the partial result before using history.' end
    if self.app.transform_session and self.app.transform_session:is_active() then return nil,'Commit or cancel the active transform session before using history.' end
    if self.app.stamp_session and self.app.stamp_session:is_active() then return nil,'Commit or cancel the active stamp stroke before using history.' end
    local model=self.app.model
    local stack=direction=='undo' and model.undo_stack or model.redo_stack
    if #stack==0 then return nil,'Nothing to '..direction end
    if steps>#stack then return nil,'Only '..#stack..' '..direction..' step(s) available' end
    local live,live_before={}, {}
    for _,object in ipairs(model.data.objects) do if self.app.placement:is_tracked(object) then live[object.id]=true;table.insert(live_before,object.id) end end
    for index=#stack-steps+1,#stack do
        for _,object in ipairs(stack[index].objects or {}) do
            if object.runtime and (object.runtime.spawned or object.runtime.status=='pending') then live[object.id]=true end
        end
        -- Entries pushed by an earlier undo/redo were captured after despawn_all,
        -- so their runtime fields are empty; the live set is kept in the metadata.
        local meta=stack[index].__history
        for _,id in ipairs(meta and meta.live_ids or {}) do live[id]=true end
    end
    local cleared=self.app.placement:despawn_all()
    if #cleared.failed>0 then return self:_fail('history','History not applied: runtime cleanup failed.') end
    local labels={}
    for _=1,steps do
        local entry=stack[#stack];table.insert(labels,entry.__history and entry.__history.label or false)
        model[direction](model)
        local opposite=direction=='undo' and model.redo_stack or model.undo_stack
        local pushed=opposite[#opposite]
        if pushed and pushed.__history then pushed.__history.live_ids=Util.deepcopy(live_before) end
    end
    model:normalize() -- cached runtime IDs in history are never live ownership
    self.app.selection:clear();self.app:mark_dirty()
    for id in pairs(self.app.placement.expected_live) do self.app.placement.expected_live[id]=nil end
    for id in pairs(live) do self.app.placement.expected_live[id]=true end
    local failed=0
    for _,object in ipairs(model.data.objects) do
        if live[object.id] then local id=self.app.placement:spawn(object);if not id then failed=failed+1 end end
    end
    local runtime_sync=self.app.check_runtime_sync and self.app:check_runtime_sync(true) or nil
    self:_log('info','history',direction,{steps=steps,failed=failed})
    return {direction=direction,steps=steps,labels=labels,undo_count=#model.undo_stack,redo_count=#model.redo_stack,respawned_failed=failed,runtime_sync=runtime_sync},failed>0 and ('History restored, but '..failed..' runtime request(s) failed. See debug report.') or nil
end

function Actions:delete_selected()
    local kind,id=self.app.selection.kind,self.app.selection.id;if not kind or not id then return self:_fail('delete_selected','nothing selected') end
    local model=self.app.model;local ok,err
    if kind=='object' then local item=model:get_object(id);if item and item.locked then return self:_fail('delete_selected','object is locked; unlock it before deleting') end;if item then local removed,remove_err=self.app.placement:despawn(item);if not removed then return self:_fail('delete_selected',remove_err) end end;ok,err=model:delete_object(id)
    elseif kind=='location' then ok,err=model:delete_location(id)
    elseif kind=='route' then ok,err=model:delete_route(id)
    elseif kind=='premise' then
        local removed=self.app.placement:despawn_premise(id)
        if #removed.failed>0 then return self:_fail('delete_selected','Location retained: one or more runtime entities could not be removed.') end
        ok,err=model:delete_premise(id)
    elseif kind=='room' then
        for _,object in ipairs(model.data.objects) do if object.room_id==id then local removed,remove_err=self.app.placement:despawn(object);if not removed then return self:_fail('delete_selected',remove_err) end end end
        ok,err=model:delete_room(id)
    elseif kind=='volume' then ok,err=model:delete_volume(id)
    elseif kind=='camera' then ok,err=model:delete_camera(id)
    elseif kind=='cover_node' then ok,err=model:delete_cover_node(id)
    elseif kind=='scene' then local result;result,err=self.app.scenes:delete(id);ok=result~=nil
    elseif kind=='asset' then ok,err=model:delete_asset(id)
    else return self:_fail('delete_selected','unsupported selection',{kind=kind,id=id}) end
    if not ok then return self:_fail('delete_selected',err,{kind=kind,id=id}) end
    self.app.selection:clear();self.app:mark_dirty()
    self:_log('info','delete_selected','complete',{kind=kind,id=id});return true
end

return Actions
