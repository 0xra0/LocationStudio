local Util=require('modules/util')
local AmbientAudio={};AmbientAudio.__index=AmbientAudio

local function clean_name(value,fallback)
    local name=Util.trim(value or '')
    if name=='' then name=fallback end
    return name
end
local function event_entry(name)
    return {['$type']='audioAudEventStruct',event={['$type']='CName',['$storage']='string',['$value']=name}}
end
local function cname(value)
    return {['$type']='CName',['$storage']='string',['$value']=value or ''}
end
local function group_slug(value)
    return (tostring(value or 'zone'):gsub('[^%w_%-]','_'))
end
function AmbientAudio.new(app) return setmetatable({app=app},AmbientAudio) end
function AmbientAudio:_catalog_resource(key,query,path)
    local result,err=self.app.world_builder:search(key,query or '',80,true);if not result then return nil,err end
    if path then for _,item in ipairs(result.items or {}) do if item.path==path then return item end end;return nil,'requested resource path is not in the active World Builder catalog' end
    local item=result.items and result.items[1];if not item then return nil,'World Builder catalog returned no matching resources' end
    return item
end
function AmbientAudio:_serialized(definition_key,category,variant,resource,name)
    local payload,err=self.app.world_builder:prepare_favorite_record({category=category,variant=variant,spawn_data=resource.path,name=resource.name},name)
    if not payload then return nil,err end
    local saved=payload.data and payload.data.spawnable
    if type(saved)~='table' then return nil,'World Builder returned no serialized '..definition_key..' data' end
    return {name=payload.name,fileName=payload.name,data=saved},saved
end
function AmbientAudio:_spawn(objects,enabled)
    if enabled==false then return {spawned=0,failed={}} end
    local spawned,failed=0,{}
    for _,object in ipairs(objects) do
        local id,err=self.app.placement:spawn(object)
        if id then spawned=spawned+1 else failed[#failed+1]={object_id=object.id,error=tostring(err)} end
    end
    return {spawned=spawned,failed=failed}
end
function AmbientAudio:create_emitter(args)
    args=args or {}
    local resource,err=self:_catalog_resource('audio',args.query or args.resource_name,args.resource_path)
    if not resource then return nil,err end
    local name=clean_name(args.name,resource.name..' Emitter')
    local entry,saved=self:_serialized('audio','Deco','Static Audio Emitter',resource,name);if not entry then return nil,saved end
    saved.radius=math.max(0,tonumber(args.radius) or tonumber(saved.radius) or 5)
    if args.emitter_metadata_name~=nil then saved.emitterMetadataName=tostring(args.emitter_metadata_name) end
    if args.use_doppler~=nil then saved.useDoppler=args.use_doppler==true end
    if args.use_physics_obstruction~=nil then saved.usePhysicsObstruction=args.use_physics_obstruction==true end
    local transform
    if args.transform then transform=Util.deepcopy(args.transform)
    elseif args.source=='room' then
        local room=self.app.model:get_room(args.room_id or self.app.selected_room_id);if not room then return nil,'select a room or provide room_id for room placement' end
        transform=Util.deepcopy(room.transform)
    elseif args.source=='player' then transform,err=self.app.game:capture_transform();if not transform then return nil,err end
    else local hit;hit,err=self.app.game:aim_point(args.distance or 10);if not hit then return nil,err end;transform={position=hit.position,rotation={roll=0,pitch=0,yaw=tonumber(args.yaw) or 0}} end
    local premise_id=args.premise_id or self.app.selected_premise_id
    local object=self.app.model:add_object({premise_id=premise_id,room_id=args.room_id or self.app.selected_room_id,name=name,kind='audio',template='',layer='decoration',transform=transform,size={x=1,y=1,z=1},enabled=true,
        metadata={source='LocationStudio World Builder Static Audio Emitter',ambient_audio={role='emitter',event=resource.path,radius=saved.radius},world_builder={definition_key='audio',category='Deco',variant='Static Audio Emitter',class_module='modules/classes/spawn/visual/audio',module_path='visual/audio',resource_name=resource.name,resource_path=resource.path,entry=entry,apply_scale=false}}})
    if not object then return nil,'project model rejected the World Builder audio emitter' end
    self.app.selection:set('object',object.id);self.app:mark_dirty()
    local runtime=self:_spawn({object},args.spawn)
    return {object=object,resource_path=resource.path,spawned=runtime.spawned==1,spawn_error=runtime.failed[1] and runtime.failed[1].error or nil}
end
function AmbientAudio:create_reverb_zone(args)
    args=args or {}
    local room=self.app.model:get_room(args.room_id or self.app.selected_room_id)
    if not room then return nil,'select an existing room or provide room_id; reverb bounds are built from that room footprint' end
    local width=tonumber(args.width) or room.size.width;local depth=tonumber(args.depth) or room.size.depth;local height=tonumber(args.height) or room.size.height
    for key,value in pairs({width=width,depth=depth,height=height}) do if value<0.5 or value>500 then return nil,key..' must be between 0.5 and 500 metres' end end
    local area_resource,err=self:_catalog_resource('area_ambient',args.preset_name or 'Interior Muffling Area',args.preset_path)
    if not area_resource then return nil,'World Builder Ambient Area preset unavailable: '..tostring(err) end
    local area_name=clean_name(args.name,room.name..' Reverb Zone')
    local zone_id=Util.make_id('ambient')
    local slug=group_slug(zone_id)
    local outline_group='ls_ambient_'..slug..'_outline'
    local area_entry,area_saved=self:_serialized('area_ambient','Area','Ambient Area',area_resource,area_name)
    if not area_entry then return nil,area_saved end
    local trigger=area_saved.trigger
    local settings=trigger and trigger.Settings and trigger.Settings.Data
    if type(settings)~='table' then return nil,'World Builder Ambient Area preset has no audioAmbientAreaSettings.Data structure' end
    settings.Reverb=cname(tostring(args.reverb or (settings.Reverb and settings.Reverb['$value']) or ''))
    settings.Priority=math.floor(tonumber(args.priority) or tonumber(settings.Priority) or 16)
    settings.outerDistance=math.max(0,tonumber(args.outer_distance) or tonumber(settings.outerDistance) or 10)
    settings.verticalOuterDistance=math.max(0,tonumber(args.vertical_outer_distance) or tonumber(settings.verticalOuterDistance) or 1)
    if args.sound_event and Util.trim(args.sound_event)~='' then settings.EventsOnActive={event_entry(Util.trim(args.sound_event))} end
    local marker_resource;marker_resource,err=self:_catalog_resource('area_outline',args.marker_preset or '',args.marker_preset_path)
    if not marker_resource then return nil,'World Builder Outline Marker preset unavailable: '..tostring(err) end
    local marker_entry,marker_saved=self:_serialized('area_outline','Area','Outline Marker',marker_resource,area_name..' Outline Point')
    if not marker_entry then return nil,marker_saved end
    local center=room.transform.position;local yaw=math.rad(room.transform.rotation.yaw or 0);local c,s=math.cos(yaw),math.sin(yaw)
    local corners={{-width/2,-depth/2},{width/2,-depth/2},{width/2,depth/2},{-width/2,depth/2}}
    local positions={}
    for i,p in ipairs(corners) do
        local position={x=center.x+p[1]*c-p[2]*s,y=center.y+p[1]*s+p[2]*c,z=center.z,w=1};positions[i]=position
    end
    area_saved.outlinePath=outline_group;area_saved.markers=Util.deepcopy(positions);area_saved.height=height
    local premise_id=args.premise_id or room.premise_id
    local created={}
    for i,position in ipairs(positions) do
        local marker_data=Util.deepcopy(marker_saved);marker_data.height=height
        local marker={name=area_name..' Outline '..i,fileName=area_name..' Outline '..i,data=marker_data}
        local object=self.app.model:add_object({premise_id=premise_id,room_id=room.id,name=area_name..' Outline '..i,kind='marker',template='',layer='gameplay',transform={position=position,rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=height},enabled=true,
            metadata={source='LocationStudio World Builder Ambient Area outline',ambient_zone={id=zone_id,role='outline_marker',index=i,height=height,outline_group=outline_group},world_builder={definition_key='area_outline',category='Area',variant='Outline Marker',class_module='modules/classes/spawn/area/outlineMarker',module_path='area/outlineMarker',resource_name=marker_resource.name,resource_path=marker_resource.path,entry=marker,apply_scale=false}}})
        if not object then for _,prior in ipairs(created) do self.app.model:delete_object(prior.id) end;return nil,'project model rejected an outline marker' end
        created[#created+1]=object
    end
    local area_object=self.app.model:add_object({premise_id=premise_id,room_id=room.id,name=area_name,kind='audio_zone',template='',layer='gameplay',transform={position=Util.deepcopy(center),rotation={roll=0,pitch=0,yaw=0}},size={x=width,y=depth,z=height},enabled=true,
        metadata={source='LocationStudio World Builder Ambient Area',ambient_zone={id=zone_id,role='area',outline_group=outline_group,room_id=room.id,markers=Util.deepcopy(positions),height=height,reverb=settings.Reverb['$value'],sound_event=args.sound_event or '',priority=settings.Priority},world_builder={definition_key='area_ambient',category='Area',variant='Ambient Area',class_module='modules/classes/spawn/area/ambientArea',module_path='area/ambientArea',resource_name=area_resource.name,resource_path=area_resource.path,entry=area_entry,apply_scale=false}}})
    if not area_object then for _,prior in ipairs(created) do self.app.model:delete_object(prior.id) end;return nil,'project model rejected the ambient area' end
    created[#created+1]=area_object
    self.app.selection:set('object',area_object.id);self.app:mark_dirty()
    local runtime=self:_spawn(created,args.spawn)
    local markers={};for i=1,#positions do markers[i]=created[i] end
    return {zone=area_object,outline=markers,outline_points=Util.deepcopy(positions),outline_group=outline_group,room_id=room.id,room_size={width=width,depth=depth,height=height},spawned=runtime.spawned,failed=runtime.failed,warning='World Builder does not preview Ambient Area soundstage effects; export the complete group to native world edit to activate reverb.'}
end
return AmbientAudio
