local Util = require('modules/util')
local Model = require('modules/model')

local Storage = {}
Storage.__index = Storage

function Storage.new(project_path)
    local self = setmetatable({}, Storage)
    self.project_path = project_path or 'data/project.json'
    self.config_path = 'data/config.json'
    self.last_error = nil
    return self
end

function Storage:load_model()
    local file,read_err,code=io.open(self.project_path,'r')
    if not file then
        local message=string.lower(tostring(read_err))
        if code==2 or message:find('no such file',1,true) or message:find('file not found',1,true) then return Model.new() end
        error('Cannot read project; original file has not been changed: '..tostring(read_err))
    end
    local text=file:read('*a');file:close()
    local ok,data=pcall(json.decode,text or '')
    if not ok or type(data)~='table' or type(data.project)~='table' then
        self.last_error='Project JSON is empty, damaged, or has no project header. Original preserved at '..self.project_path..'. Check '..self.project_path..'.bak before restoring it manually.'
        error(self.last_error)
    end
    local loaded,model=pcall(Model.new,data)
    if not loaded then self.last_error='Project cannot be loaded; original preserved: '..tostring(model);error(self.last_error) end
    return model
end

function Storage:save_model(model)
    if not model or not model.data then return false, 'invalid model' end
    local data=Util.deepcopy(model.data)
    for _,object in ipairs(data.objects or {}) do object.runtime=nil end
    local ok, err = self:atomic_write(self.project_path,data)
    if not ok then self.last_error = tostring(err) else self.last_error=nil end
    return ok, err
end

function Storage:atomic_write(path,data)
    local encoded_ok,encoded=pcall(json.encode,data)
    if not encoded_ok or type(encoded)~='string' then return false,'JSON encoding failed: '..tostring(encoded) end
    if type(os.rename)~='function' then return false,'Atomic file rename is unavailable; original project left untouched.' end
    local tmp,backup=path..'.tmp',path..'.bak'
    local written,write_err=Util.write_file(tmp,encoded)
    if not written then return false,'Temporary save failed: '..tostring(write_err) end
    local original=Util.file_exists(path)
    local function rename(a,b)
        local ran,value,err=pcall(os.rename,a,b)
        return ran and value,ran and err or value
    end
    if original then
        if Util.file_exists(backup) then
            local ran,removed,remove_err=pcall(os.remove,backup)
            if not ran or not removed then return false,'Cannot rotate previous backup: '..tostring(remove_err or removed) end
        end
        local moved,move_err=rename(path,backup)
        if not moved then return false,'Cannot back up original project: '..tostring(move_err) end
    end
    local committed,commit_err=rename(tmp,path)
    if not committed then
        if original then
            local restored=rename(backup,path)
            if not restored then return false,'Save failed; original remains in '..backup..': '..tostring(commit_err) end
        end
        return false,'Save failed; original preserved: '..tostring(commit_err)
    end
    return true
end

function Storage:load_config()
    local config=Util.json_read(self.config_path, {
        window_open = true,
        autosave_interval = 2.0,
        bridge_poll_interval = 0.15,
        status_interval = 1.0,
        ui_scale = 1.0,
    })
    -- v0.9.0 persisted this field and onDraw used it as a hard gate. If it ever
    -- became false, opening CET produced no LocationStudio window and no UI error.
    -- The editor is now visible whenever the CET overlay opens.
    config.window_open=true
    return config
end

function Storage:save_config(config)
    return self:atomic_write(self.config_path,config)
end

function Storage:export_json(model, path)
    return Util.json_write(path, model.data)
end

function Storage:export_csv(model, path)
    local lines = {'id,name,type,category,x,y,z,roll,pitch,yaw,radius,tags,notes'}
    local function esc(v)
        v = tostring(v or ''):gsub('"', '""')
        return '"' .. v .. '"'
    end
    for _, loc in ipairs(model.data.locations) do
        local p = loc.transform.position
        local r = loc.transform.rotation
        table.insert(lines, table.concat({
            esc(loc.id), esc(loc.name), esc(loc.type), esc(loc.category),
            tostring(p.x), tostring(p.y), tostring(p.z),
            tostring(r.roll), tostring(r.pitch), tostring(r.yaw),
            tostring(loc.radius), esc(Util.join_csv(loc.tags)), esc(loc.notes)
        }, ','))
    end
    return Util.write_file(path, table.concat(lines, '\n'))
end

function Storage:export_lua(model, path)
    local out = {'-- LocationStudio generated teleport helpers', 'local locations = {}', ''}
    for _, loc in ipairs(model.data.locations) do
        local p = loc.transform.position
        local r = loc.transform.rotation
        table.insert(out, string.format("locations[%q] = {x=%.6f, y=%.6f, z=%.6f, roll=%.3f, pitch=%.3f, yaw=%.3f}",
            loc.name, p.x, p.y, p.z, r.roll, r.pitch, r.yaw))
    end
    table.insert(out, '')
    table.insert(out, [[
local function teleport(name)
    local l = locations[name]
    if not l then return false end
    local player = Game.GetPlayer()
    if not player then return false end
    Game.GetTeleportationFacility():Teleport(
        player,
        ToVector4{x=l.x, y=l.y, z=l.z, w=1},
        ToEulerAngles{roll=l.roll, pitch=l.pitch, yaw=l.yaw}
    )
    return true
end

return { locations = locations, teleport = teleport }
]])
    return Util.write_file(path, table.concat(out, '\n'))
end

function Storage:export_world_builder(model, path)
    local groups = {}
    for _, premise in ipairs(model.data.premises or {}) do
        local group = {
            id = premise.id,
            name = premise.name,
            kind = premise.kind,
            transform = premise.transform,
            rooms = {},
            objects = {},
            volumes = {},
            cameras = {},
        }
        for _, room in ipairs(model.data.rooms or {}) do
            if room.premise_id == premise.id then
                table.insert(group.rooms, {
                    id=room.id, name=room.name, kind=room.kind, transform=room.transform,
                    size=room.size, openings=room.openings, level=room.level,
                })
            end
        end
        for _, object in ipairs(model.data.objects or {}) do
            if object.premise_id == premise.id then
                table.insert(group.objects, {
                    id=object.id, room_id=object.room_id, name=object.name, kind=object.kind,
                    template=object.template, appearance=object.appearance, layer=object.layer,
                    transform=object.transform, size=object.size, properties=object.properties, metadata=object.metadata,
                })
            end
        end
        for _, volume in ipairs(model.data.volumes or {}) do
            if volume.premise_id == premise.id then table.insert(group.volumes, volume) end
        end
        for _, camera in ipairs(model.data.cameras or {}) do
            if camera.premise_id == premise.id then table.insert(group.cameras, camera) end
        end
        table.insert(groups, group)
    end
    return Util.json_write(path, {
        format='locationstudio-worldbuilder-handoff',
        version=1,
        units='meters',
        coordinate_system='REDengine world XYZ / Euler RPY',
        project=model.data.project,
        layers=model.data.layers,
        groups=groups,
        note='Neutral handoff: map object templates to the installed World Builder asset catalog before sector export.',
    })
end

function Storage:export_questforge(model,path)
    local function slug(value)
        local out=tostring(value or ''):lower():gsub('[^%w_%-]+','_'):gsub('_+','_'):gsub('^[_%-]+',''):gsub('[_%-]+$','')
        if out=='' then out='location' end
        return out
    end
    local function xyz(item)
        local p=((item or {}).transform or {}).position or {}
        return {tonumber(p.x) or 0,tonumber(p.y) or 0,tonumber(p.z) or 0}
    end
    local project=model.data.project or {};local sector_id=slug(project.id or project.name or 'locationstudio')
    local prefix='$/locationstudio/#'..sector_id
    local markers,manifest_locations,semantic_locations,triggers,fact_triggers,interactable_handoff,npc_population_handoff,npc_ai_routes,combat_encounters,cover_nodes={},{},{},{},{},{},{},{},{},{}
    local used,used_manifest_names={},{}
    for _,loc in ipairs(model.data.locations or {}) do
        if loc.enabled~=false then
            local kind=({marker=true,mappin=true,spot=true})[string.lower(tostring(loc.type or ''))] and string.lower(loc.type) or 'marker'
            local linked=((loc.metadata or {}).questforge_sync) or {}
            local key=tostring(linked.node_ref or (kind..'_'..slug(loc.id or loc.name)))
            if key=='' then key=kind..'_'..slug(loc.id or loc.name) end
            if used[key] then key=key..'_'..slug(loc.name) end
            if used[key] then key=key..'_'..tostring(#markers+1) end
            used[key]=true
            local node_ref=key
            local manifest_name=tostring(linked.manifest_name or slug(loc.name))
            if manifest_name=='' then manifest_name=slug(loc.name) end
            if used_manifest_names[manifest_name] then manifest_name=manifest_name..'_'..slug(loc.id or key) end
            used_manifest_names[manifest_name]=true
            local transform=loc.transform or {};local rotation=transform.rotation or {}
            local point={id=key,pos=xyz(loc),yaw=tonumber(rotation.yaw) or 0,
                _source=tostring(((loc.metadata or {}).source) or 'LocationStudio export; coordinate provenance not asserted'),verified=((loc.metadata or {}).coordinates_verified)==true,
                _locationStudio={id=loc.id,name=loc.name,kind=kind}}
            table.insert(markers,point)
            manifest_locations[manifest_name]={node_ref=node_ref}
            local semantic={id=loc.id,name=loc.name,kind=kind,manifest_name=manifest_name,node_ref=node_ref,position=point.pos,yaw=point.yaw,
                radius=tonumber(loc.radius) or 0.5,verified=point.verified}
            table.insert(semantic_locations,semantic)
        end
    end
    local sector={id=sector_id,markers=markers,triggers=triggers}
    for _,volume in ipairs(model.data.volumes or {}) do
        if volume.enabled~=false and (volume.purpose=='trigger' or volume.purpose=='quest_trigger' or ((volume.metadata or {}).questforge or {}).fact_name) then
            local transform=volume.transform or {};local rotation=transform.rotation or {};local size=volume.size or {}
            local qf=(volume.metadata or {}).questforge or {};local synced=((volume.metadata or {}).questforge_sync or {}).facts or {}
            local fact=tostring(qf.fact_name or (synced[1] and synced[1].name) or '')
            local fact_value=tonumber(qf.value) or tonumber(synced[1] and synced[1].value) or 1
            if fact~='' and not fact:match('^[%w_%.%-]+$') then return false,'Invalid Quest Forge fact name on volume '..tostring(volume.name)..': '..fact end
            local linked=(volume.metadata or {}).questforge_sync or {}
            local id=tostring(linked.node_ref or ('trigger_'..slug(volume.id or volume.name)));if id=='' then id='trigger_'..slug(volume.id or volume.name) end
            local base_id=id;local suffix=2
            while used[id] do id=base_id..'_'..tostring(suffix);suffix=suffix+1 end
            used[id]=true
            local trigger={id=id,pos=xyz(volume),yaw=tonumber(rotation.yaw) or 0,
                size={(tonumber(size.x) or 2)/2,(tonumber(size.y) or 2)/2,(tonumber(size.z) or 2)/2},
                _source=tostring((volume.metadata or {}).source or 'LocationStudio export; coordinate provenance not asserted'),verified=((volume.metadata or {}).coordinates_verified)==true,
                _locationStudio={id=volume.id,name=volume.name,shape=volume.shape or 'box'}}
            if fact~='' then
                trigger._questforge={fact=fact,event='player_inside',value=fact_value}
                table.insert(fact_triggers,{trigger_id=id,volume_id=volume.id,fact=fact,event='player_inside',value=fact_value,
                    note='Bind this trigger event to the named fact in quest flow; worldTriggerAreaNode does not set quest facts by itself.'})
            end
            for i=2,#synced do
                local synced_fact=synced[i]
                if tostring(synced_fact.name or '')~='' and not (synced_fact.source=='trigger' and synced_fact.name==fact) then
                    table.insert(fact_triggers,{trigger_id=id,volume_id=volume.id,fact=synced_fact.name,event='player_inside',value=tonumber(synced_fact.value) or 1,
                        note='Imported Quest Forge fact link; preserve and bind this event in quest flow.'})
                end
            end
            table.insert(triggers,trigger)
        end
    end
    for _,object in ipairs(model.data.objects or {}) do
        local population=(object.metadata or {}).npc_population
        if population and object.enabled~=false then
            local record=tostring(population.record or '')
            if not record:match('^Character%.[%w_%.%-]+$') then return false,'NPC population '..tostring(object.name)..' requires a Character.* record' end
            local conditions=type(population.conditions)=='table' and Util.deepcopy(population.conditions) or {}
            for i,c in ipairs(conditions) do
                if type(c)~='table' or not tostring(c.fact_name or ''):match('^[%w_%.%-]+$') then return false,'NPC population conditions['..i..'] has an invalid quest fact' end
                c.fact_value=math.floor(tonumber(c.fact_value) or 1)
            end
            local rotation=(object.transform or {}).rotation or {}
            table.insert(npc_population_handoff,{id=object.id,name=object.name,record=record,appearance=population.appearance or '',
                attitude=population.attitude or '',faction=population.faction or '',level=tonumber(population.level) or 0,
                archetype=population.archetype or '',idle_behavior=population.idle_behavior or '',despawn_distance=tonumber(population.despawn_distance) or 0,
                spawn_on_start=population.spawn_on_start~=false,always_spawned=population.always_spawned==true,
                streaming_range={primary=tonumber(population.primary_range) or 100,secondary=tonumber(population.secondary_range) or 120},
                conditions=conditions,position=xyz(object),yaw=tonumber(rotation.yaw) or 0,
                native_node='worldPopulationSpawnerNode',native_supported_fields={'record','appearance','spawn_on_start','always_spawned','streaming_range'},
                profile_fields_handoff={'attitude','faction','level','archetype','idle_behavior','despawn_distance','conditions'}})
        end
        local data=(object.metadata or {}).interactable
        if data and object.enabled~=false then
            local kind=tostring(data.kind or '')
            if not ({door=true,loot_container=true,shard=true,item=true})[kind] then return false,'Invalid interactable kind on '..tostring(object.name) end
            local item=tostring(data.item_record or '');local loot=tostring(data.loot_table or '');local fact=tostring(data.fact_name or '')
            if (kind=='shard' or kind=='item') and not item:match('^Items%.[%w_%.%-]+$') then return false,'Interactable '..tostring(object.name)..' requires an Items.* record' end
            if item~='' and not item:match('^Items%.[%w_%.%-]+$') then return false,'Invalid item record on interactable '..tostring(object.name) end
            if kind=='loot_container' and not loot:match('^LootTables%.[%w_%.%-]+$') then return false,'Loot container '..tostring(object.name)..' requires a LootTables.* record' end
            if loot~='' and not loot:match('^LootTables%.[%w_%.%-]+$') then return false,'Invalid loot table on interactable '..tostring(object.name) end
            local loot_items=data.loot_items or {}
            if type(loot_items)~='table' then return false,'loot_items must be an array on '..tostring(object.name) end
            for i,row in ipairs(loot_items) do
                if type(row)~='table' or not tostring(row.item_record or ''):match('^Items%.[%w_%.%-]+$') then return false,'loot_items['..i..'] requires an Items.* record on '..tostring(object.name) end
                local lo,hi,chance=tonumber(row.count_min) or 1,tonumber(row.count_max) or 1,tonumber(row.drop_chance) or 1
                if lo<1 or hi<lo or lo%1~=0 or hi%1~=0 or chance<0 or chance>1 then return false,'Invalid loot item quantity/chance on '..tostring(object.name) end
            end
            if fact~='' and not fact:match('^[%w_%.%-]+$') then return false,'Invalid quest fact on interactable '..tostring(object.name) end
            if tostring(data.entity_record or '')~='' and not tostring(data.entity_record):match('^[%w_]+%.[%w_%.%-]+$') then return false,'Invalid entity record on interactable '..tostring(object.name) end
            if (kind=='door' or kind=='loot_container') and data.lock_state~='locked' and data.lock_state~='unlocked' then return false,'Invalid lock state on interactable '..tostring(object.name) end
            local rotation=(object.transform or {}).rotation or {}
            table.insert(interactable_handoff,{id=object.id,name=object.name,kind=kind,entity_template=data.entity_template or object.template,
                entity_record=data.entity_record,item_record=item~='' and item or nil,loot_table=loot~='' and loot or nil,
                loot_items=Util.deepcopy(loot_items),
                lock_state=data.lock_state,fact_on_interact=fact~='' and {name=fact,value=tonumber(data.fact_value) or 1,event=data.fact_event or 'on_interact'} or nil,
                position=xyz(object),yaw=tonumber(rotation.yaw) or 0,native_setup_required=true,setup_status='authoring_only'})
        end
    end
    local npc_by_id={};for _,object in ipairs(model.data.objects or {}) do if object.metadata and object.metadata.npc_population then npc_by_id[object.id]=object end end
    for _,route in ipairs(model.data.npc_routes or {}) do
        local npc=npc_by_id[route.npc_id]
        if not npc then return false,'NPC route '..tostring(route.name)..' must reference a saved NPC population point' end
        local function export_variant(list,variant)
            list=type(list)=='table' and list or {};local ids={};for _,wp in ipairs(list) do ids[wp.id]=true end
            local result={}
            for index,wp in ipairs(list) do
                local p=((wp.transform or {}).position or {});local r=((wp.transform or {}).rotation or {})
                local next_id=list[index+1] and list[index+1].id or ((route.loop and list[1]) and list[1].id or nil)
                local branch=wp.branch_target_id or ''
                if branch~='' and (not ids[branch] or not tostring(wp.branch_fact or ''):match('^[%w_%.%-]+$')) then return nil,'NPC route '..tostring(route.name)..' has a branch with a missing waypoint or invalid fact' end
                if wp.transition=='workspot' then
                    local found=false;for _,loc in ipairs(model.data.locations or {}) do if loc.id==wp.workspot_location_id and loc.metadata and loc.metadata.workspot then found=true;break end end
                    if not found then return nil,'NPC route '..tostring(route.name)..' references a missing workspot location' end
                end
                result[#result+1]={id=wp.id,name=wp.name,position={tonumber(p.x) or 0,tonumber(p.y) or 0,tonumber(p.z) or 0},yaw=tonumber(r.yaw) or 0,
                    facing_yaw=tonumber(wp.facing_yaw) or tonumber(r.yaw) or 0,wait_seconds=tonumber(wp.wait_seconds) or 0,speed=tonumber(wp.speed) or 1,
                    transition=wp.transition or 'walk',workspot_location_id=wp.workspot_location_id or '',next_waypoint_id=next_id,
                    branch=branch~='' and {fact=wp.branch_fact,value=tonumber(wp.branch_value) or 1,target_waypoint_id=branch} or nil}
            end
            return result
        end
        local patrol,err=export_variant(route.waypoints,'patrol');if not patrol then return false,err end
        local alert;alert,err=export_variant(route.alert_waypoints,'alert');if not alert then return false,err end
        local combat;combat,err=export_variant(route.combat_waypoints,'combat');if not combat then return false,err end
        table.insert(npc_ai_routes,{id=route.id,name=route.name,npc_id=npc.id,character_record=npc.metadata.npc_population.record,
            loop=route.loop==true,kind=route.kind or 'patrol',waypoints=patrol,alert_waypoints=alert,combat_waypoints=combat,
            runtime_status='handoff_only',notes=route.notes or ''})
    end
    local encounter_npcs={};for _,object in ipairs(model.data.objects or {}) do if object.metadata and object.metadata.npc_population and object.enabled~=false then encounter_npcs[object.id]=object end end
    local encounter_volumes={};for _,volume in ipairs(model.data.volumes or {}) do encounter_volumes[volume.id]=volume end
    for _,encounter in ipairs(model.data.combat_encounters or {}) do
        local premise=model:get_premise(encounter.premise_id);if not premise then return false,'Combat encounter '..tostring(encounter.name)..' references a missing premise' end
        local function volume_ref(id,label)
            if not id or id=='' then return nil end
            local volume=encounter_volumes[id]
            if not volume or volume.premise_id~=encounter.premise_id then return false,'Combat encounter '..tostring(encounter.name)..' references an invalid '..label end
            local rotation=(volume.transform or {}).rotation or {}
            return {id=volume.id,name=volume.name,shape=volume.shape,purpose=volume.purpose,position=xyz(volume),yaw=tonumber(rotation.yaw) or 0,size=volume.size,radius=volume.radius,height=volume.height}
        end
        local area,area_err=volume_ref(encounter.area_volume_id,'combat area volume');if area==false then return false,area_err end
        local trigger,trigger_err=volume_ref(encounter.trigger_volume_id,'activation trigger volume');if trigger==false then return false,trigger_err end
        local groups_by_id,groups_out={},{}
        for _,group in ipairs(encounter.groups or {}) do
            local members={}
            for _,id in ipairs(group.npc_ids or {}) do
                local npc=encounter_npcs[id];if not npc or npc.premise_id~=encounter.premise_id then return false,'Enemy group '..tostring(group.name)..' references an invalid or disabled NPC population point' end
                local cfg=npc.metadata.npc_population;local rot=(npc.transform or {}).rotation or {}
                members[#members+1]={population_id=npc.id,name=npc.name,record=cfg.record,appearance=cfg.appearance or '',position=xyz(npc),yaw=tonumber(rot.yaw) or 0}
            end
            if #members==0 then return false,'Enemy group '..tostring(group.name)..' must contain at least one NPC population point' end
            groups_by_id[group.id]=true;groups_out[#groups_out+1]={id=group.id,name=group.name,faction=group.faction or '',attitude=group.attitude or 'hostile',spacing=tonumber(group.spacing) or 1.5,members=members}
        end
        local waves_by_id={};for _,wave in ipairs(encounter.waves or {}) do waves_by_id[wave.id]=true end
        local waves_out={}
        for _,wave in ipairs(encounter.waves or {}) do
            local group_ids={};for _,id in ipairs(wave.group_ids or {}) do if not groups_by_id[id] then return false,'Combat wave '..tostring(wave.name)..' references a missing enemy group' end;group_ids[#group_ids+1]=id end
            if #group_ids==0 then return false,'Combat wave '..tostring(wave.name)..' must contain at least one enemy group' end
            local activation=wave.activation or 'immediate';if not ({immediate=true,volume=true,fact=true,after_wave=true})[activation] then return false,'Combat wave '..tostring(wave.name)..' has invalid activation mode' end
            local wave_volume_id=wave.trigger_volume_id;if not wave_volume_id or wave_volume_id=='' then wave_volume_id=encounter.trigger_volume_id end
            local wave_trigger,wave_trigger_err=volume_ref(wave_volume_id,'wave trigger volume');if wave_trigger==false then return false,wave_trigger_err end
            local fact=tostring(wave.fact_name or '')
            if fact~='' and not fact:match('^[%w_%.%-]+$') then return false,'Combat wave '..tostring(wave.name)..' has an invalid activation fact' end
            if activation=='volume' and not wave_trigger then return false,'Combat wave '..tostring(wave.name)..' requires a trigger volume' end
            if activation=='fact' and fact=='' then return false,'Combat wave '..tostring(wave.name)..' requires an activation fact' end
            local fact_value=tonumber(wave.fact_value) or 1;local delay=tonumber(wave.delay_seconds) or 0
            if fact_value%1~=0 or fact_value < -2147483648 or fact_value > 2147483647 then return false,'Combat wave '..tostring(wave.name)..' has an invalid fact value' end
            if delay<0 or delay>3600 then return false,'Combat wave '..tostring(wave.name)..' has an invalid reinforcement delay' end
            local after=wave.after_wave_id or '';if activation=='after_wave' and (after=='' or not waves_by_id[after] or after==wave.id) then return false,'Combat wave '..tostring(wave.name)..' has an invalid reinforcement wave link' end
            waves_out[#waves_out+1]={id=wave.id,name=wave.name,group_ids=group_ids,activation=activation,trigger_volume=wave_trigger,
                fact_name=fact,fact_value=fact_value,after_wave_id=after,delay_seconds=delay}
        end
        local activation_fact=tostring(encounter.activation_fact or '');local reset_fact=tostring(encounter.reset_fact or '')
        if activation_fact~='' and not activation_fact:match('^[%w_%.%-]+$') then return false,'Combat encounter '..tostring(encounter.name)..' has an invalid activation fact' end
        if reset_fact~='' and not reset_fact:match('^[%w_%.%-]+$') then return false,'Combat encounter '..tostring(encounter.name)..' has an invalid reset fact' end
        local activation_value=tonumber(encounter.activation_value) or 1;local reset_value=tonumber(encounter.reset_value) or 0
        if activation_value%1~=0 or activation_value < -2147483648 or activation_value > 2147483647 or reset_value%1~=0 or reset_value < -2147483648 or reset_value > 2147483647 then return false,'Combat encounter '..tostring(encounter.name)..' has an invalid activation/reset fact value' end
        table.insert(combat_encounters,{id=encounter.id,name=encounter.name,premise_id=encounter.premise_id,combat_area=area,trigger_volume=trigger,
            activation_fact=activation_fact,activation_value=activation_value,reset_fact=reset_fact,reset_value=reset_value,
            faction_relations=Util.deepcopy(encounter.faction_relations or {}),groups=groups_out,waves=waves_out,
            runtime_status='handoff_only',test_mode='temporary_dynamic_entities',notes=encounter.notes or ''})
    end
    for _,cover in ipairs(model.data.cover_nodes or {}) do
        local premise=model:get_premise(cover.premise_id);if not premise then return false,'Cover node '..tostring(cover.name)..' references a missing premise' end
        local room_id=cover.room_id
        if room_id then local room=model:get_room(room_id);if not room or room.premise_id~=cover.premise_id then return false,'Cover node '..tostring(cover.name)..' references an invalid room' end end
        local p=((cover.transform or {}).position or {});local r=((cover.transform or {}).rotation or {})
        if cover.cover_type~='crouch' and cover.cover_type~='standing' then return false,'Cover node '..tostring(cover.name)..' has an invalid posture' end
        if not ({low=true,medium=true,high=true})[cover.exposure] then return false,'Cover node '..tostring(cover.name)..' has an invalid exposure value' end
        table.insert(cover_nodes,{id=cover.id,name=cover.name,premise_id=cover.premise_id,room_id=room_id,posture=cover.cover_type,exposure=cover.exposure,
            spacing=tonumber(cover.spacing) or 1.5,position=xyz(cover),yaw=tonumber(r.yaw) or 0,source=cover.source or 'manual',confidence=tonumber(cover.confidence) or 1,
            runtime_status='authoring_handoff_only'})
    end
    local world={nodeRefPrefix=prefix,block='mod\\locationstudio\\worlds\\'..sector_id..'.streamingblock',
        sectorDir='mod\\locationstudio\\worlds',sectors={sector}}
    return Util.json_write(path,{
        format='locationstudio-questforge-handoff',version=2,project=project,
        questforge_world=world,
        quest_manifest_fragment={schema='questforge/v2',locations=manifest_locations},
        semantic_locations=semantic_locations,locations=model.data.locations,routes=model.data.routes,
        fact_triggers=fact_triggers,interactable_handoff=interactable_handoff,npc_population_handoff=npc_population_handoff,npc_ai_routes=npc_ai_routes,combat_encounters=combat_encounters,cover_nodes=cover_nodes,device_logic_graphs=model.data.device_logic_graphs or {},world_state_variants=model.data.world_state_variants or {},volumes=model.data.volumes,cameras=model.data.cameras,premises=model.data.premises,
        notes={
            'questforge_world is a Quest Forge world.json-compatible sector fragment; merge its sector into the quest project world.json.',
            'quest_manifest_fragment.locations maps these names to NodeRefs for quest.yaml. Markers, mappins, and spots are static marker NodeRefs.',
            'Fact-linked trigger metadata documents the intended quest flow link. A worldTriggerAreaNode does not set a quest fact automatically.',
            'interactable_handoff preserves placed entity/item/loot/lock/fact configuration. TweakXL loot tables can be generated from explicit loot_items by build_interactable_artifacts. Native .ent components and controller operations still require a compatible game entity/profile; WB builds sector/device/PS CR2W resources from typed export data.',
            'npc_population_handoff preserves population profile preferences. Character record, appearance, spawn-on-start, always-spawned and streaming ranges are written into World Builder worldPopulationSpawnerNode. Attitude/faction/level/archetype/idle behavior/despawn_distance/conditional facts are handoff fields only until a verified native Character or community profile maps them.',
            'npc_ai_routes links editable patrol/alert/combat waypoint sequences to persistent NPC population IDs. Wait/facing/speed/workspot/branch details are explicit handoff data; this editor does not claim they execute in REDengine until mapped into tested native community/AI resources.',
            'combat_encounters links combat/trigger volumes, enemy groups, population records, reinforcement waves, faction relationships, and quest facts. Manual Test spawns temporary tagged NPCs and Reset despawns them. Quest fact triggers, reinforcement scheduling, faction AI, encounter completion, and reset callbacks are handoff-only; no native combat controller or guard/community AI graph is generated.',
            'cover_nodes are editable spatial authoring hints detected from paired Static/Dynamic collision rays. They are not native REDengine cover/navigation resources and must be inspected before game export.',
            'device_logic_graphs preserve typed terminals, doors, elevators, switches, cameras, security systems, facts, actions, and links. They are semantic authoring/handoff graphs, not REDengine runtime scripts. Native links can be applied to an existing World Builder export only after device records and compatible PSID/instanceData entries already exist; missing class-specific persistent-state payloads are reported and never fabricated.',
            'world_state_variants store fact predicates and object visibility memberships for LocationStudio live entity switching. They are exported as authoring metadata only; this does not compile native REDengine quest phases or persistent world-state resources.',
            'Coordinates are exported as verified=false unless metadata.coordinates_verified=true. Stand on and recapture points before treating them as verified (OI-9).',
            'Quest Forge trigger size uses half-extents in metres. Non-box LocationStudio volumes are exported as their bounding box.',
        },
    })
end

return Storage
