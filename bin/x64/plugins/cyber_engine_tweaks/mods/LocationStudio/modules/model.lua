local Util = require('modules/util')
local RoomKits = require('modules/room_kits')

local Model = {}
Model.__index = Model

local function blank_project()
    return {
        schema_version = 19,
        project = {
            id = 'default', name = 'Night City Location Project', description = '', author = '', tags = {},
            created_at = Util.now_iso(), updated_at = Util.now_iso(),
        },
        locations = {}, routes = {}, npc_routes = {}, combat_encounters = {}, cover_nodes = {}, navigation_graphs = {}, device_logic_graphs = {}, world_state_variants = {}, environments = {}, splines = {}, timelines = {}, premises = {}, rooms = {}, objects = {}, object_groups = {}, object_prefabs = {}, volumes = {}, cameras = {}, scenes = {}, assets = {}, vanilla_removals = {}, room_frames = {},
        -- Layer ids 'shell' and 'decoration' are kept for compatibility; they are
        -- shown as Architecture and Props.
        layers = {
            {id='shell', name='Architecture', color='#5BC0EB', visible=true, locked=false, export=true},
            {id='decoration', name='Props', color='#9BC53D', visible=true, locked=false, export=true},
            {id='gameplay', name='Gameplay', color='#FDE74C', visible=true, locked=false, export=true},
            {id='npc', name='NPC', color='#C77DFF', visible=true, locked=false, export=true},
            {id='lighting', name='Lighting', color='#E55934', visible=true, locked=false, export=true},
            {id='audio', name='Audio', color='#4ECDC4', visible=true, locked=false, export=true},
            {id='quest', name='Quest', color='#FA7921', visible=true, locked=false, export=true},
            {id='debug', name='Debug', color='#9E9E9E', visible=true, locked=false, export=false},
        },
        settings = {
            grid_step=0.25, angle_step=5.0, duplicate_distance=0.35, autosave=true,
            local_space=true, spawn_on_create=false,
            shell_templates={wall='', floor='', ceiling='', door='', window=''},
            room_kit=RoomKits.default_settings(),
            snapping={enabled=true, grid=0.25, angle=5.0, surface_offset=0.02},
            visuals={enabled=true, marker_template='', marker_appearance='', max_distance=80.0, floorplan_scale=18.0},
            workspace={mode='BUILD', panel='HOME', beginner_mode=true, v06_welcome_seen=false, bottom_panel='ASSETS', live_preview=true, show_generated=true, show_collision=false, construction_role='all', multi_step=0.25, multi_angle=5.0, multi_scale_step=0.10, multi_local_space=false, multi_pivot_mode='center', multi_custom_pivot={x=0,y=0,z=0,w=1}, layout_align_mode='center', group_name='New Group', prefab_name='New Prefab', hierarchy_width=280, inspector_width=340, bottom_height=210},
            quickstart={width=5.0,depth=5.0,height=3.0,auto_door=true,door_width=1.2,strict_runtime=true},
            ent_tools={scatter_count=6, scatter_radius=2.0, scatter_distance=12.0, scatter_seed=2077, scatter_random_yaw=true, scatter_drop=true},
            asset_preview={
                enabled=true,auto_on_select=false,auto_follow=true,mode='aim',distance=10.0,yaw_mode='camera',surface_offset=0.02,
                align_surface=false,stamp_mode=false,stamp_spacing=0.5,pick_distance=40.0,pick_radius=0.75,pick_focus_world_builder=true,
            },
            transform_grab={distance=12.0,surface_offset=0.02,align_surface=false,snap_position=false,pivot_mode='center',update_interval=0.08},
            transform_edit={move_step=0.25,angle_step=5.0,scale_step=0.10,local_space=false,pivot_mode='center'},
            asset_browser={view='ALL',card_width=246,thumbnail_height=138,show_missing=true},
            -- Deterministic screenshot mode. Settings variables are CET ConfigVars
            -- ({group,name,value}); names missing from a game build are reported,
            -- never faked, and every applied value is restored afterwards.
            screenshot_mode={
                hide_hud=true,disable_post_effects=true,freeze_world=true,wait_for_streaming=true,
                freeze_dilation=0.0001,ready_timeout=20.0,ready_samples=3,
                hud_vars={
                    {group='/interface/hud',name='action_buttons',value=false},{group='/interface/hud',name='activity_log',value=false},
                    {group='/interface/hud',name='ammo_counter',value=false},{group='/interface/hud',name='boss_healthbar',value=false},
                    {group='/interface/hud',name='crouch_indicator',value=false},{group='/interface/hud',name='dpad',value=false},
                    {group='/interface/hud',name='healthbar',value=false},{group='/interface/hud',name='input_hints',value=false},
                    {group='/interface/hud',name='johnny_hud',value=false},{group='/interface/hud',name='minimap',value=false},
                    {group='/interface/hud',name='npc_healthbar',value=false},{group='/interface/hud',name='npc_names',value=false},
                    {group='/interface/hud',name='object_markers',value=false},{group='/interface/hud',name='phone_avatar',value=false},
                    {group='/interface/hud',name='prompts',value=false},{group='/interface/hud',name='quest_tracker',value=false},
                    {group='/interface/hud',name='stamina_oxygen',value=false},
                },
                post_effect_vars={
                    {group='/graphics/basic',name='MotionBlur',value='Off'},{group='/graphics/basic',name='FilmGrain',value=false},
                    {group='/graphics/basic',name='ChromaticAberration',value=false},{group='/graphics/basic',name='DepthOfField',value=false},
                    {group='/graphics/basic',name='LensFlares',value=false},
                },
                camera_shake_vars={},extra_vars={},
            },
            -- Streaming/performance analyzer. Costs are relative estimates, not
            -- measured frame time; budgets and cluster thresholds are editable.
            performance={
                cell_size=5.0,cluster_min_cost=40,cluster_sigma=3.0,light_overlap_limit=4,
                room_budget={nodes=250,lights=12,audio=8,decals=60,vfx=10,dynamic=25,cost=400},
                premise_budget={nodes=1200,lights=40,audio=30,decals=250,vfx=40,dynamic=100,cost=1800},
            },
            starter_assets_seeded=false,
        },
    }
end

local function normalize_transform(t)
    t = t or {}; local p = t.position or {}; local r = t.rotation or {}
    return {
        position={x=tonumber(p.x) or 0.0, y=tonumber(p.y) or 0.0, z=tonumber(p.z) or 0.0, w=tonumber(p.w) or 1.0},
        rotation={roll=tonumber(r.roll) or 0.0, pitch=tonumber(r.pitch) or 0.0, yaw=tonumber(r.yaw) or 0.0},
    }
end

local function normalize_location(loc)
    loc = loc or {}; local now = Util.now_iso()
    return {
        id=loc.id or Util.make_id('loc'),
        name=Util.trim(loc.name) ~= '' and Util.trim(loc.name) or 'Untitled Location',
        type=Util.trim(loc.type) ~= '' and Util.trim(loc.type) or 'point',
        category=Util.trim(loc.category) ~= '' and Util.trim(loc.category) or 'General',
        tags=type(loc.tags) == 'table' and loc.tags or Util.split_csv(loc.tags or ''),
        notes=tostring(loc.notes or ''), enabled=loc.enabled ~= false, radius=tonumber(loc.radius) or 0.5,
        transform=normalize_transform(loc.transform), metadata=type(loc.metadata) == 'table' and loc.metadata or {},
        created_at=loc.created_at or now, updated_at=now,
    }
end

local function normalize_route(route)
    route = route or {}; local now = Util.now_iso()
    return {
        id=route.id or Util.make_id('route'), name=Util.trim(route.name) ~= '' and Util.trim(route.name) or 'Route',
        kind=Util.trim(route.kind) ~= '' and Util.trim(route.kind) or 'patrol',
        location_ids=type(route.location_ids) == 'table' and route.location_ids or {}, loop=route.loop == true,
        notes=tostring(route.notes or ''), created_at=route.created_at or now, updated_at=now,
    }
end

local function normalize_premise(item)
    item = item or {}; local now = Util.now_iso()
    return {
        id=item.id or Util.make_id('premise'), name=Util.trim(item.name) ~= '' and Util.trim(item.name) or 'New Premise',
        kind=Util.trim(item.kind) ~= '' and Util.trim(item.kind) or 'interior',
        transform=normalize_transform(item.transform), levels=math.max(1, math.floor(tonumber(item.levels) or 1)),
        floor_height=math.max(0.1, tonumber(item.floor_height) or 3.0), tags=type(item.tags) == 'table' and item.tags or {},
        notes=tostring(item.notes or ''), enabled=item.enabled ~= false,
        created_at=item.created_at or now, updated_at=now,
    }
end

local function normalize_opening(item)
    item = item or {}
    return {
        id=item.id or Util.make_id('opening'), kind=item.kind == 'window' and 'window' or 'door',
        wall=({north=true,south=true,east=true,west=true})[item.wall] and item.wall or 'south',
        offset=tonumber(item.offset) or 0.0, width=math.max(0.1, tonumber(item.width) or 1.2),
        height=math.max(0.1, tonumber(item.height) or 2.2), sill=math.max(0.0, tonumber(item.sill) or 0.0),
        template=tostring(item.template or ''),
    }
end

local function normalize_room(item)
    item = item or {}; local now = Util.now_iso(); local openings = {}
    for _, opening in ipairs(type(item.openings) == 'table' and item.openings or {}) do table.insert(openings, normalize_opening(opening)) end
    return {
        id=item.id or Util.make_id('room'), premise_id=item.premise_id,
        name=Util.trim(item.name) ~= '' and Util.trim(item.name) or 'Room', kind=item.kind or 'room',
        transform=normalize_transform(item.transform),
        size={width=math.max(0.1, tonumber((item.size or {}).width) or 4.0), depth=math.max(0.1, tonumber((item.size or {}).depth) or 4.0), height=math.max(0.1, tonumber((item.size or {}).height) or 3.0)},
        wall_thickness=math.max(0.01, tonumber(item.wall_thickness) or 0.15), level=math.floor(tonumber(item.level) or 0),
        layer=item.layer or 'shell', openings=openings, shell_object_ids=type(item.shell_object_ids) == 'table' and item.shell_object_ids or {},
        tags=type(item.tags) == 'table' and item.tags or {}, notes=tostring(item.notes or ''), enabled=item.enabled ~= false,
        created_at=item.created_at or now, updated_at=now,
    }
end

local function normalize_object(item)
    item = item or {}; local now = Util.now_iso(); local size = item.size or item.dimensions or {}
    return {
        id=item.id or Util.make_id('obj'), premise_id=item.premise_id, room_id=item.room_id, parent_id=item.parent_id,
        name=Util.trim(item.name) ~= '' and Util.trim(item.name) or 'Object', kind=item.kind or 'prop',
        template=tostring(item.template or item.template_path or ''), appearance=tostring(item.appearance or ''),
        layer=item.layer or 'decoration', transform=normalize_transform(item.transform),
        size={x=math.max(0.001, tonumber(size.x) or 1.0), y=math.max(0.001, tonumber(size.y) or 1.0), z=math.max(0.001, tonumber(size.z) or 1.0)},
        enabled=item.enabled ~= false, visible=item.visible ~= false, locked=item.locked == true,
        properties=type(item.properties) == 'table' and item.properties or {}, metadata=type(item.metadata) == 'table' and item.metadata or {},
        runtime={spawned=false, entity_id=nil}, created_at=item.created_at or now, updated_at=now,
    }
end

local function normalize_object_group(item)
    item=item or {};local now=Util.now_iso();local pivot_mode=item.pivot_mode
    if pivot_mode~='active' and pivot_mode~='custom' then pivot_mode='center' end
    return {
        id=item.id or Util.make_id('group'),name=Util.trim(item.name)~='' and Util.trim(item.name) or 'Object Group',
        premise_id=item.premise_id,room_id=item.room_id,parent_id=item.parent_id,
        object_ids=type(item.object_ids)=='table' and item.object_ids or {},pivot_mode=pivot_mode,
        pivot=normalize_transform(item.pivot),visible=item.visible~=false,locked=item.locked==true,
        created_at=item.created_at or now,updated_at=now,
    }
end

local function normalize_prefab_object(item)
    item=item or {};local size=item.size or {}
    return {
        name=Util.trim(item.name)~='' and Util.trim(item.name) or 'Prefab Object',kind=item.kind or 'prop',
        template=tostring(item.template or ''),appearance=tostring(item.appearance or ''),layer=item.layer or 'decoration',
        transform=normalize_transform(item.transform),
        size={x=math.max(0.001,tonumber(size.x) or 1),y=math.max(0.001,tonumber(size.y) or 1),z=math.max(0.001,tonumber(size.z) or 1)},
        enabled=item.enabled~=false,visible=item.visible~=false,locked=false,
        properties=type(item.properties)=='table' and item.properties or {},metadata=type(item.metadata)=='table' and item.metadata or {},
    }
end

local function normalize_object_prefab(item)
    item=item or {};local now=Util.now_iso();local id=item.id or Util.make_id('prefab');local objects={}
    for _,object in ipairs(type(item.objects)=='table' and item.objects or {}) do table.insert(objects,normalize_prefab_object(object)) end
    local pivot_mode=item.pivot_mode;if pivot_mode~='active' and pivot_mode~='custom' then pivot_mode='center' end
    return {
        id=id,name=Util.trim(item.name)~='' and Util.trim(item.name) or 'Object Prefab',
        category=Util.trim(item.category)~='' and Util.trim(item.category) or 'Assemblies',tags=type(item.tags)=='table' and item.tags or Util.split_csv(item.tags or ''),
        objects=objects,pivot_mode=pivot_mode,source_group_id=item.source_group_id,
        thumbnail_path=Util.trim(item.thumbnail_path)~='' and tostring(item.thumbnail_path) or ('thumbnails/prefab_'..tostring(id):gsub('[^%w_-]','_')..'.png'),
        thumbnail_captured_at=tostring(item.thumbnail_captured_at or ''),thumbnail_source=tostring(item.thumbnail_source or ''),
        notes=tostring(item.notes or ''),created_at=item.created_at or now,updated_at=now,
    }
end

local function normalize_volume(item)
    item=item or {}; local now=Util.now_iso(); local size=item.size or {}
    local shape=({box=true,sphere=true,cylinder=true})[item.shape] and item.shape or 'box'
    return {
        id=item.id or Util.make_id('volume'),premise_id=item.premise_id,room_id=item.room_id,
        name=Util.trim(item.name)~='' and Util.trim(item.name) or 'Trigger Volume',
        purpose=Util.trim(item.purpose)~='' and Util.trim(item.purpose) or 'trigger',shape=shape,
        transform=normalize_transform(item.transform),
        size={x=math.max(0.01,tonumber(size.x) or 2.0),y=math.max(0.01,tonumber(size.y) or 2.0),z=math.max(0.01,tonumber(size.z) or 2.0)},
        radius=math.max(0.01,tonumber(item.radius) or 1.0),height=math.max(0.01,tonumber(item.height) or 2.0),
        layer=item.layer or 'gameplay',enabled=item.enabled~=false,tags=type(item.tags)=='table' and item.tags or {},
        notes=tostring(item.notes or ''),metadata=type(item.metadata)=='table' and item.metadata or {},
        created_at=item.created_at or now,updated_at=now,
    }
end

local function normalize_camera(item)
    item=item or {}; local now=Util.now_iso(); local look=item.look_at or {}
    return {
        id=item.id or Util.make_id('camera'),premise_id=item.premise_id,room_id=item.room_id,
        name=Util.trim(item.name)~='' and Util.trim(item.name) or 'Camera',
        kind=item.kind or 'shot',transform=normalize_transform(item.transform),
        look_at={x=tonumber(look.x) or 0.0,y=tonumber(look.y) or 0.0,z=tonumber(look.z) or 0.0,location_id=look.location_id},
        fov=math.max(1.0,math.min(179.0,tonumber(item.fov) or 50.0)),
        duration=math.max(0.0,tonumber(item.duration) or 3.0),layer=item.layer or 'quest',
        tags=type(item.tags)=='table' and item.tags or {},notes=tostring(item.notes or ''),enabled=item.enabled~=false,
        created_at=item.created_at or now,updated_at=now,
    }
end

local function normalize_cover_node(item)
    item=type(item)=='table' and item or {}
    local kind=item.cover_type=='standing' and 'standing' or 'crouch'
    local exposure=({low=true,medium=true,high=true})[item.exposure] and item.exposure or 'medium'
    local transform=normalize_transform(item.transform)
    return {id=tostring(item.id or Util.make_id('cover')),premise_id=item.premise_id,room_id=item.room_id,
        name=tostring(item.name or 'Cover Node'),cover_type=kind,exposure=exposure,
        spacing=math.max(0.25,math.min(10,tonumber(item.spacing) or 1.5)),transform=transform,
        source=tostring(item.source or 'manual'),confidence=math.max(0,math.min(1,tonumber(item.confidence) or 1)),
        created_at=item.created_at or Util.now_iso(),updated_at=item.updated_at or Util.now_iso()}
end

local function normalize_scene(item)
    item=item or {};local now=Util.now_iso()
    local function ids(value) return type(value)=='table' and value or {} end
    return {
        id=item.id or Util.make_id('scene'),premise_id=item.premise_id,
        name=Util.trim(item.name)~='' and Util.trim(item.name) or 'Scene',kind=Util.trim(item.kind)~='' and Util.trim(item.kind) or 'gameplay',
        room_ids=ids(item.room_ids),object_ids=ids(item.object_ids),location_ids=ids(item.location_ids),
        volume_ids=ids(item.volume_ids),camera_ids=ids(item.camera_ids),route_ids=ids(item.route_ids),
        tags=type(item.tags)=='table' and item.tags or Util.split_csv(item.tags or ''),notes=tostring(item.notes or ''),enabled=item.enabled~=false,
        created_at=item.created_at or now,updated_at=now,
    }
end

local function normalize_world_state_variant(item)
    item=item or {};local now=Util.now_iso()
    return {id=item.id or Util.make_id('wsv'),name=Util.trim(item.name or '')~='' and Util.trim(item.name) or 'World State',
        premise_id=item.premise_id,priority=tonumber(item.priority) or 0,enabled=item.enabled~=false,
        conditions=type(item.conditions)=='table' and item.conditions or {},members=type(item.members)=='table' and item.members or {},
        description=tostring(item.description or ''),created_at=item.created_at or now,updated_at=now}
end

local function clamp(value,low,high,fallback)
    local n=tonumber(value);if not n then return fallback end
    return math.max(low,math.min(high,n))
end

-- Authoring environment: time/weather/fog conditions for preview and
-- deterministic screenshots. Weather is a game weather-state CName; fog is an
-- optional World Builder Fog Volume spawned only while previewing.
local function normalize_environment(item)
    item=item or {};local now=Util.now_iso()
    local time=type(item.time)=='table' and item.time or {}
    local weather=type(item.weather)=='table' and item.weather or {}
    local fog=type(item.fog)=='table' and item.fog or {}
    local size=type(fog.size)=='table' and fog.size or {}
    local color=type(fog.color)=='table' and fog.color or {}
    return {id=item.id or Util.make_id('env'),name=Util.trim(item.name or '')~='' and Util.trim(item.name) or 'Environment',
        premise_id=item.premise_id,
        time={enabled=time.enabled~=false,hour=math.floor(clamp(time.hour,0,23,12)),minute=math.floor(clamp(time.minute,0,59,0))},
        weather={enabled=weather.enabled~=false,state=Util.trim(weather.state or '')~='' and Util.trim(weather.state) or '24h_weather_sunny',
            blend_time=clamp(weather.blend_time,0,600,0),priority=math.floor(clamp(weather.priority,0,100,9))},
        fog={enabled=fog.enabled==true,anchor=({player=true,premise=true,camera=true})[fog.anchor] and fog.anchor or 'player',
            size={x=clamp(size.x,1,2000,60),y=clamp(size.y,1,2000,60),z=clamp(size.z,1,1000,20)},
            density_factor=clamp(fog.density_factor,0,100,1),density_falloff=clamp(fog.density_falloff,0,100,1),
            absorption=clamp(fog.absorption,0,100,1),blend_falloff=clamp(fog.blend_falloff,0,100,1),
            color={clamp(color[1],0,1,1),clamp(color[2],0,1,1),clamp(color[3],0,1,1)},resource_path=tostring(fog.resource_path or '')},
        exposure_note=tostring(item.exposure_note or ''),notes=tostring(item.notes or ''),
        created_at=item.created_at or now,updated_at=now}
end

local SPLINE_MODES={auto=true,aligned=true,free=true,linear=true}
local function vec3(v) v=type(v)=='table' and v or {};return {x=tonumber(v.x) or 0,y=tonumber(v.y) or 0,z=tonumber(v.z) or 0} end
-- Editable spline: control points with cubic Bezier handles (offsets from the
-- point). `uses` remember what was generated from the spline so it can be
-- regenerated after edits.
local function normalize_spline(item)
    item=item or {};local now=Util.now_iso();local points={}
    for _,p in ipairs(type(item.points)=='table' and item.points or {}) do
        if type(p)=='table' then
            points[#points+1]={id=p.id or Util.make_id('spt'),position=vec3(p.position or p),handle_in=vec3(p.handle_in),handle_out=vec3(p.handle_out),
                mode=SPLINE_MODES[p.mode] and p.mode or 'auto'}
        end
    end
    local color=tostring(item.color or '#6EC6FF');if not color:match('^#%x%x%x%x%x%x$') then color='#6EC6FF' end
    return {id=item.id or Util.make_id('spline'),name=Util.trim(item.name or '')~='' and Util.trim(item.name) or 'Spline',premise_id=item.premise_id,
        closed=item.closed==true,tension=math.max(0,math.min(1,tonumber(item.tension) or 0.5)),color=color,points=points,
        uses=type(item.uses)=='table' and item.uses or {},notes=tostring(item.notes or ''),created_at=item.created_at or now,updated_at=now}
end

local TIMELINE_TRACKS={camera=true,npc=true,look_at=true,dialogue=true,event=true,fact=true,marker=true}
-- Cinematic timeline: typed tracks of time-ordered keys. Key payloads are kept
-- as authored; references are validated by modules/timeline.lua.
local function normalize_timeline(item)
    item=item or {};local now=Util.now_iso();local tracks={}
    for _,t in ipairs(type(item.tracks)=='table' and item.tracks or {}) do
        if type(t)=='table' and TIMELINE_TRACKS[t.kind] then
            local keys={}
            for _,k in ipairs(type(t.keys)=='table' and t.keys or {}) do
                if type(k)=='table' then local key=Util.deepcopy(k);key.id=key.id or Util.make_id('key');key.time=math.max(0,tonumber(key.time) or 0);keys[#keys+1]=key end
            end
            table.sort(keys,function(a,b) if a.time==b.time then return tostring(a.id)<tostring(b.id) end;return a.time<b.time end)
            tracks[#tracks+1]={id=t.id or Util.make_id('track'),kind=t.kind,name=Util.trim(t.name or '')~='' and Util.trim(t.name) or t.kind,
                target_id=t.target_id,npc_key=t.npc_key,enabled=t.enabled~=false,muted=t.muted==true,keys=keys}
        end
    end
    return {id=item.id or Util.make_id('timeline'),name=Util.trim(item.name or '')~='' and Util.trim(item.name) or 'Timeline',
        premise_id=item.premise_id,scene_id=item.scene_id,duration=math.max(0.1,math.min(3600,tonumber(item.duration) or 30)),
        fps=math.max(1,math.min(120,math.floor(tonumber(item.fps) or 30))),tracks=tracks,notes=tostring(item.notes or ''),
        created_at=item.created_at or now,updated_at=now}
end

local function normalize_layer(item)
    item = item or {}
    local color=tostring(item.color or '#FFFFFF');if not color:match('^#%x%x%x%x%x%x$') then color='#FFFFFF' end
    return {id=item.id or Util.make_id('layer'), name=Util.trim(item.name or '')~='' and Util.trim(item.name) or 'Layer', color=color,
        visible=item.visible ~= false, locked=item.locked == true, export=item.export ~= false, description=tostring(item.description or '')}
end

-- Older projects: add the newer default layers and rename untouched defaults.
local LEGACY_LAYER_NAMES={shell={Shell='Architecture'},decoration={Decoration='Props'}}
local function migrate_layers(layers,defaults)
    local by_id={};for _,layer in ipairs(layers) do by_id[layer.id]=layer end
    for id,renames in pairs(LEGACY_LAYER_NAMES) do local layer=by_id[id];if layer and renames[layer.name] then layer.name=renames[layer.name] end end
    for _,default in ipairs(defaults) do if not by_id[default.id] then table.insert(layers,Util.deepcopy(default)) end end
end

local function normalize_asset(item)
    item=item or {}; local now=Util.now_iso(); local size=item.size or {};local id=item.id or Util.make_id('asset')
    return {
        id=id,
        name=Util.trim(item.name)~='' and Util.trim(item.name) or 'Unnamed Asset',
        category=Util.trim(item.category)~='' and Util.trim(item.category) or 'Props',
        kind=Util.trim(item.kind)~='' and Util.trim(item.kind) or 'prop',
        template=tostring(item.template or item.template_path or ''),appearance=tostring(item.appearance or ''),
        layer=item.layer or 'decoration',favorite=item.favorite==true,
        tags=type(item.tags)=='table' and item.tags or Util.split_csv(item.tags or ''),
        size={x=math.max(0.001,tonumber(size.x) or 1.0),y=math.max(0.001,tonumber(size.y) or 1.0),z=math.max(0.001,tonumber(size.z) or 1.0)},
        thumbnail_path=Util.trim(item.thumbnail_path)~='' and tostring(item.thumbnail_path) or ('thumbnails/'..id..'.png'),
        thumbnail_captured_at=tostring(item.thumbnail_captured_at or ''),thumbnail_source=tostring(item.thumbnail_source or ''),
        last_used_at=tostring(item.last_used_at or ''),use_count=math.max(0,math.floor(tonumber(item.use_count) or 0)),
        notes=tostring(item.notes or ''),metadata=type(item.metadata)=='table' and item.metadata or {},created_at=item.created_at or now,updated_at=now,
    }
end

local BUILTIN_ASSETS={
    {id='builtin_chair_poor',name='Starter Chair',category='Starter Props',kind='prop',template='base\\environment\\decoration\\furniture\\living_room\\poor_residential_chair\\poor_residential_chair_a_dst.ent',layer='decoration',tags={'starter','furniture'},size={x=0.7,y=0.7,z=1.1}},
    {id='builtin_chair_corpo',name='Starter Office Chair',category='Starter Props',kind='prop',template='base\\items\\interactive\\furniture\\int_furniture_002__corpo_office_chair_a.ent',layer='decoration',tags={'starter','furniture'},size={x=0.8,y=0.8,z=1.2}},
    {id='builtin_table_lab',name='Starter Table',category='Starter Props',kind='prop',template='base\\gameplay\\loot\\decorative_containers\\tables\\appearances\\lab_table_big_a.ent',layer='decoration',tags={'starter','furniture'},size={x=1.8,y=0.9,z=1.0}},
    {id='builtin_crates_stack',name='Starter Crates',category='Starter Props',kind='prop',template='base\\prefabs\\environment\\decoration\\containers\\cargo\\stack_of_crates\\stack_of_crates_a.ent',layer='decoration',tags={'starter','container'},size={x=1.5,y=1.2,z=1.4}},
    {id='builtin_case_military',name='Starter Military Case',category='Starter Props',kind='prop',template='base\\gameplay\\loot\\decorative_containers\\cases\\appearances\\military_case_medium_a.ent',layer='decoration',tags={'starter','container'},size={x=1.2,y=0.6,z=0.6}},
    {id='builtin_wall_lamp',name='Starter Wall Lamp',category='Starter Props',kind='device',template='base\\environment\\decoration\\lighting\\residential\\wall_lamps\\wall_lamp_a_device.ent',layer='lighting',tags={'starter','light'},size={x=0.5,y=0.3,z=0.5}},
}

local function seed_builtin_assets(self)
    if self.data.settings.starter_assets_seeded==true then return 0 end
    local ids={};for _,asset in ipairs(self.data.assets or {}) do ids[asset.id]=true end
    local added=0
    for _,seed in ipairs(BUILTIN_ASSETS) do
        if not ids[seed.id] then table.insert(self.data.assets,normalize_asset(seed));added=added+1 end
    end
    self.data.settings.starter_assets_seeded=true
    return added
end

function Model.new(data)
    local self=setmetatable({}, Model); self.data=data or blank_project(); self:normalize(); self.undo_stack={}; self.redo_stack={}; self.max_history=75; return self
end
function Model.blank() return blank_project() end

function Model:normalize()
    if type(self.data) ~= 'table' then self.data=blank_project() end
    local defaults=blank_project(); self.data.schema_version=19
    self.data.project=self.data.project or defaults.project; self.data.locations=self.data.locations or {}; self.data.routes=self.data.routes or {}
    self.data.npc_routes=type(self.data.npc_routes)=='table' and self.data.npc_routes or {}
    self.data.combat_encounters=type(self.data.combat_encounters)=='table' and self.data.combat_encounters or {}
    self.data.cover_nodes=type(self.data.cover_nodes)=='table' and self.data.cover_nodes or {}
    self.data.navigation_graphs=type(self.data.navigation_graphs)=='table' and self.data.navigation_graphs or {}
    self.data.device_logic_graphs=type(self.data.device_logic_graphs)=='table' and self.data.device_logic_graphs or {}
    self.data.world_state_variants=type(self.data.world_state_variants)=='table' and self.data.world_state_variants or {}
    for i,v in ipairs(self.data.world_state_variants) do self.data.world_state_variants[i]=normalize_world_state_variant(v) end
    self.data.environments=type(self.data.environments)=='table' and self.data.environments or {}
    self.data.splines=type(self.data.splines)=='table' and self.data.splines or {}
    self.data.timelines=type(self.data.timelines)=='table' and self.data.timelines or {}
    for i,v in ipairs(self.data.timelines) do self.data.timelines[i]=normalize_timeline(v) end
    for i,v in ipairs(self.data.splines) do self.data.splines[i]=normalize_spline(v) end
    for i,v in ipairs(self.data.environments) do self.data.environments[i]=normalize_environment(v) end
    for _,graph in ipairs(self.data.device_logic_graphs) do if type(graph)=='table' then
        graph.nodes=type(graph.nodes)=='table' and graph.nodes or {};graph.links=type(graph.links)=='table' and graph.links or {}
        for _,node in ipairs(graph.nodes) do if type(node)=='table' then
            node.config=type(node.config)=='table' and node.config or {};node.native=type(node.native)=='table' and node.native or {}
        end end
    end end
    self.data.premises=self.data.premises or {}; self.data.rooms=self.data.rooms or {}; self.data.objects=self.data.objects or {}
    self.data.object_groups=self.data.object_groups or {};self.data.object_prefabs=self.data.object_prefabs or {}
    self.data.volumes=self.data.volumes or {}; self.data.cameras=self.data.cameras or {}; self.data.scenes=self.data.scenes or {}; self.data.assets=self.data.assets or {}; self.data.vanilla_removals=self.data.vanilla_removals or {};self.data.room_frames=type(self.data.room_frames)=='table' and self.data.room_frames or {}
    self.data.layers=self.data.layers or defaults.layers; self.data.settings=self.data.settings or defaults.settings
    for k,v in pairs(defaults.settings) do if self.data.settings[k] == nil then self.data.settings[k]=Util.deepcopy(v) end end
    for _,key in ipairs({'snapping','visuals','shell_templates','workspace','quickstart','ent_tools','asset_preview','asset_browser','transform_grab','transform_edit','screenshot_mode','performance'}) do
        self.data.settings[key]=self.data.settings[key] or Util.deepcopy(defaults.settings[key])
        for k,v in pairs(defaults.settings[key]) do if self.data.settings[key][k]==nil then self.data.settings[key][k]=Util.deepcopy(v) end end
    end
    self.data.settings.room_kit=RoomKits.normalize(self.data.settings.room_kit or Util.deepcopy(defaults.settings.room_kit))
    for i,v in ipairs(self.data.locations) do self.data.locations[i]=normalize_location(v) end
    for i,v in ipairs(self.data.routes) do self.data.routes[i]=normalize_route(v) end
    for i,v in ipairs(self.data.premises) do self.data.premises[i]=normalize_premise(v) end
    for i,v in ipairs(self.data.rooms) do self.data.rooms[i]=normalize_room(v) end
    for i,v in ipairs(self.data.objects) do self.data.objects[i]=normalize_object(v) end
    for i,v in ipairs(self.data.object_groups) do self.data.object_groups[i]=normalize_object_group(v) end
    for i,v in ipairs(self.data.object_prefabs) do self.data.object_prefabs[i]=normalize_object_prefab(v) end
    local object_ids={};for _,object in ipairs(self.data.objects) do object_ids[object.id]=true end
    local group_ids,groups_by_id={},{};for _,group in ipairs(self.data.object_groups) do group_ids[group.id]=true;groups_by_id[group.id]=group end
    local assigned={}
    for _,group in ipairs(self.data.object_groups) do
        local kept={};for _,id in ipairs(group.object_ids) do if object_ids[id] and not assigned[id] then assigned[id]=group.id;table.insert(kept,id) end end;group.object_ids=kept
        if group.parent_id==group.id or not group_ids[group.parent_id] then group.parent_id=nil end
    end
    for _,group in ipairs(self.data.object_groups) do
        local seen={};local cursor=group
        while cursor do
            if seen[cursor.id] then group.parent_id=nil;break end
            seen[cursor.id]=true;cursor=cursor.parent_id and groups_by_id[cursor.parent_id] or nil
        end
    end
    for i,v in ipairs(self.data.volumes) do self.data.volumes[i]=normalize_volume(v) end
    for i,v in ipairs(self.data.cover_nodes) do self.data.cover_nodes[i]=normalize_cover_node(v) end
    for i,v in ipairs(self.data.cameras) do self.data.cameras[i]=normalize_camera(v) end
    for i,v in ipairs(self.data.scenes) do self.data.scenes[i]=normalize_scene(v) end
    for i,v in ipairs(self.data.assets) do self.data.assets[i]=normalize_asset(v) end
    self.data.vanilla_removals=self.data.vanilla_removals or {}
    seed_builtin_assets(self)
    migrate_layers(self.data.layers,defaults.layers)
    for i,v in ipairs(self.data.layers) do self.data.layers[i]=normalize_layer(v) end
end

-- A history entry is the project state before a change. Its label and time
-- live in entry[HISTORY_META], which is stripped whenever an entry becomes
-- self.data again, so it never reaches project.json.
local HISTORY_META='__history'
local function history_entry(data,label)
    local entry=Util.deepcopy(data);entry[HISTORY_META]={label=label,at=Util.now_iso()};return entry
end
local function restore_entry(entry) local meta=entry[HISTORY_META];entry[HISTORY_META]=nil;return entry,meta or {} end
function Model:snapshot(label) table.insert(self.undo_stack,history_entry(self.data,label)); if #self.undo_stack>self.max_history then table.remove(self.undo_stack,1) end; self.redo_stack={} end
function Model:push_history(data,label) table.insert(self.undo_stack,history_entry(data or self.data,label));if #self.undo_stack>self.max_history then table.remove(self.undo_stack,1) end;self.redo_stack={} end
-- Label the most recent entry when the change is only named after it happened
-- (for example a gizmo drag that snapshots on its first movement).
function Model:label_last_history(label) local entry=self.undo_stack[#self.undo_stack];if entry and entry[HISTORY_META] then entry[HISTORY_META].label=label end end
function Model:touch() self.data.project.updated_at=Util.now_iso() end
-- The entry moved to the opposite stack keeps the label of the change it
-- undoes/redoes, so `redo` names the same change `undo` just reverted.
function Model:undo()
    if #self.undo_stack==0 then return false end
    local data,meta=restore_entry(table.remove(self.undo_stack))
    local current=history_entry(self.data,meta.label);current[HISTORY_META].at=meta.at
    table.insert(self.redo_stack,current);self.data=data;return true
end
function Model:redo()
    if #self.redo_stack==0 then return false end
    local data,meta=restore_entry(table.remove(self.redo_stack))
    local current=history_entry(self.data,meta.label);current[HISTORY_META].at=meta.at
    table.insert(self.undo_stack,current);self.data=data;return true
end

local HISTORY_IGNORED={runtime=true,updated_at=true,created_at=true}
local function same(a,b,depth)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for key,value in pairs(a) do if not (depth==0 and HISTORY_IGNORED[key]) and not same(value,b[key],depth+1) then return false end end
    for key in pairs(b) do if a[key]==nil and not (depth==0 and HISTORY_IGNORED[key]) then return false end end
    return true
end
-- Per-collection added/removed/changed record counts between two states.
local function diff_states(before,after)
    local out={}
    for key,list in pairs(after) do
        local old=before[key]
        if type(list)=='table' and type(old)=='table' and (list[1]==nil or type(list[1])=='table' and list[1].id~=nil) and (old[1]==nil or type(old[1])=='table' and old[1].id~=nil) then
            local by_id={};for _,item in ipairs(old) do by_id[item.id]=item end
            local added,changed,seen=0,0,{}
            for _,item in ipairs(list) do
                seen[item.id]=true
                if by_id[item.id]==nil then added=added+1 elseif not same(by_id[item.id],item,0) then changed=changed+1 end
            end
            local removed=0;for id in pairs(by_id) do if not seen[id] then removed=removed+1 end end
            if added+removed+changed>0 then out[key]={added=added,removed=removed,changed=changed} end
        end
    end
    return out
end

-- Newest first. `undo[1]` is what the next undo reverts; `redo[1]` is what the
-- next redo re-applies. `changes` is computed, so unlabeled entries still say
-- what they touch.
function Model:history(limit)
    limit=math.max(1,math.floor(tonumber(limit) or 20))
    local function list(stack,newer_state)
        local out={}
        for index=#stack,math.max(1,#stack-limit+1),-1 do
            local entry=stack[index];local meta=entry[HISTORY_META] or {}
            local after=newer_state(index)
            table.insert(out,{steps=#stack-index+1,label=meta.label,at=meta.at,changes=diff_states(entry,after)})
        end
        return out
    end
    local undo=list(self.undo_stack,function(index) return self.undo_stack[index+1] or self.data end)
    -- A redo entry is the state after its change; compare it with the state it replaces.
    local redo={}
    for index=#self.redo_stack,math.max(1,#self.redo_stack-limit+1),-1 do
        local entry=self.redo_stack[index];local meta=entry[HISTORY_META] or {}
        local before=self.redo_stack[index+1] or self.data
        table.insert(redo,{steps=#self.redo_stack-index+1,label=meta.label,at=meta.at,changes=diff_states(before,entry)})
    end
    return {undo=undo,redo=redo,undo_count=#self.undo_stack,redo_count=#self.redo_stack,max_history=self.max_history}
end

local function get_by_id(items,id) local idx=Util.table_index_by_id(items,id); return idx and items[idx] or nil,idx end
function Model:get_location(id) return get_by_id(self.data.locations,id) end
function Model:get_route(id) return get_by_id(self.data.routes,id) end
function Model:get_npc_route(id) return get_by_id(self.data.npc_routes,id) end
function Model:get_combat_encounter(id) return get_by_id(self.data.combat_encounters,id) end
function Model:get_cover_node(id) return get_by_id(self.data.cover_nodes,id) end
function Model:get_premise(id) return get_by_id(self.data.premises,id) end
function Model:get_room(id) return get_by_id(self.data.rooms,id) end
function Model:get_object(id) return get_by_id(self.data.objects,id) end
function Model:get_object_group(id) return get_by_id(self.data.object_groups,id) end
function Model:get_object_prefab(id) return get_by_id(self.data.object_prefabs,id) end
function Model:get_volume(id) return get_by_id(self.data.volumes,id) end
function Model:get_camera(id) return get_by_id(self.data.cameras,id) end
function Model:get_scene(id) return get_by_id(self.data.scenes,id) end
function Model:get_asset(id) return get_by_id(self.data.assets,id) end
function Model:get_world_state_variant(id) return get_by_id(self.data.world_state_variants,id) end
function Model:get_environment(id) return get_by_id(self.data.environments,id) end
function Model:get_spline(id) return get_by_id(self.data.splines,id) end
function Model:get_timeline(id) return get_by_id(self.data.timelines,id) end
Model.normalize_timeline=normalize_timeline
Model.normalize_spline=normalize_spline
Model.normalize_environment=normalize_environment

local function add(self,key,item,normalizer) self:snapshot('Add '..key:gsub('s$','')); local value=normalizer(item); table.insert(self.data[key],value); self:touch(); return value end
function Model:add_location(v) return add(self,'locations',v,normalize_location) end
function Model:add_route(v) return add(self,'routes',v,normalize_route) end
function Model:add_premise(v) return add(self,'premises',v,normalize_premise) end
function Model:add_room(v) return add(self,'rooms',v,normalize_room) end
function Model:add_object(v) return add(self,'objects',v,normalize_object) end
function Model:add_volume(v) return add(self,'volumes',v,normalize_volume) end
function Model:add_cover_node(v) return add(self,'cover_nodes',v,normalize_cover_node) end
function Model:add_camera(v) return add(self,'cameras',v,normalize_camera) end
Model.normalize_camera=normalize_camera
function Model:add_scene(v) return add(self,'scenes',v,normalize_scene) end
function Model:add_asset(v) return add(self,'assets',v,normalize_asset) end
function Model:add_world_state_variant(v) return add(self,'world_state_variants',v,normalize_world_state_variant) end
function Model:add_environment(v) return add(self,'environments',v,normalize_environment) end
function Model:add_spline(v) return add(self,'splines',v,normalize_spline) end
function Model:add_timeline(v) return add(self,'timelines',v,normalize_timeline) end
function Model:add_assets(values)
    if type(values)~='table' then return {} end
    if #values==0 then return {} end
    self:snapshot();local out={}
    for _,value in ipairs(values) do local asset=normalize_asset(value);table.insert(self.data.assets,asset);table.insert(out,asset) end
    self:touch();return out
end

function Model:mark_asset_used(id)
    local asset=self:get_asset(id);if not asset then return nil,'asset not found' end
    asset.last_used_at=Util.now_iso();asset.use_count=(tonumber(asset.use_count) or 0)+1;asset.updated_at=Util.now_iso();self:touch();return asset
end

function Model:set_asset_favorite(id,value)
    local asset=self:get_asset(id);if not asset then return nil,'asset not found' end
    self:snapshot();asset.favorite=value==true;asset.updated_at=Util.now_iso();self:touch();return asset
end
function Model:add_objects(values,skip_snapshot)
    if type(values)~='table' then return {},'values must be a list' end
    if not skip_snapshot then self:snapshot() end;local out={}
    for _,value in ipairs(values) do local object=normalize_object(value);table.insert(self.data.objects,object);table.insert(out,object) end
    self:touch();return out
end

function Model:create_object_group(value,skip_snapshot)
    value=value or {};local ids=value.object_ids or {};local seen={}
    for _,id in ipairs(ids) do if seen[id] then return nil,'duplicate object in group: '..tostring(id) end;if not self:get_object(id) then return nil,'object not found: '..tostring(id) end;seen[id]=true end
    if value.parent_id then
        local parent=self:get_object_group(value.parent_id);if not parent then return nil,'parent group not found' end
        local cursor=parent;while cursor do if cursor.id==value.id then return nil,'group parent cycle detected' end;cursor=cursor.parent_id and self:get_object_group(cursor.parent_id) or nil end
    end
    if not skip_snapshot then self:snapshot() end
    for _,group in ipairs(self.data.object_groups) do local kept={};for _,id in ipairs(group.object_ids) do if not seen[id] then table.insert(kept,id) end end;group.object_ids=kept end
    local group=normalize_object_group(value);table.insert(self.data.object_groups,group);self:touch();return group
end

function Model:update_object_group(id,patch)
    local group=self:get_object_group(id);if not group then return nil,'group not found' end;patch=patch or {}
    if patch.parent_id then
        local parent=self:get_object_group(patch.parent_id);if not parent then return nil,'parent group not found' end
        local cursor=parent;while cursor do if cursor.id==id then return nil,'group parent cycle detected' end;cursor=cursor.parent_id and self:get_object_group(cursor.parent_id) or nil end
    end
    if patch.object_ids then
        local seen={};for _,object_id in ipairs(patch.object_ids) do
            if seen[object_id] then return nil,'duplicate object in group: '..tostring(object_id) end
            if not self:get_object(object_id) then return nil,'object not found: '..tostring(object_id) end;seen[object_id]=true
        end
    end
    self:snapshot()
    if patch.object_ids then
        local moving={};for _,object_id in ipairs(patch.object_ids) do moving[object_id]=true end
        for _,other in ipairs(self.data.object_groups) do if other.id~=id then local kept={};for _,object_id in ipairs(other.object_ids) do if not moving[object_id] then table.insert(kept,object_id) end end;other.object_ids=kept end end
    end
    for key,value in pairs(patch) do
        if key~='id' and key~='created_at' then
            if key=='pivot' then group[key]=normalize_transform(value)
            elseif key=='parent_id' and value==false then group[key]=nil
            else group[key]=value end
        end
    end
    group.updated_at=Util.now_iso();self:touch();return group
end

function Model:delete_object_group_meta(id)
    local _,idx=self:get_object_group(id);if not idx then return false,'group not found' end
    self:snapshot();table.remove(self.data.object_groups,idx)
    for _,group in ipairs(self.data.object_groups) do if group.parent_id==id then group.parent_id=nil end end
    self:touch();return true
end

function Model:add_object_prefab(value) return add(self,'object_prefabs',value,normalize_object_prefab) end
function Model:update_object_prefab(id,patch)
    local prefab=self:get_object_prefab(id);if not prefab then return nil,'prefab not found' end
    self:snapshot();for key,value in pairs(patch or {}) do if key~='id' and key~='created_at' then prefab[key]=value end end
    prefab.updated_at=Util.now_iso();self:touch();return prefab
end
function Model:delete_object_prefab(id) local _,idx=self:get_object_prefab(id);if not idx then return false,'prefab not found' end;self:snapshot();table.remove(self.data.object_prefabs,idx);self:touch();return true end

local function patch_item(self,item,patch)
    if not item then return nil,'not found' end; self:snapshot()
    for k,v in pairs(patch or {}) do if k~='id' and k~='created_at' then item[k]=(k=='transform' and normalize_transform(v) or v) end end
    item.updated_at=Util.now_iso(); self:touch(); return item
end
function Model:update_location(id,patch) local item=self:get_location(id); if patch and patch.tags and type(patch.tags)~='table' then patch.tags=Util.split_csv(patch.tags) end; return patch_item(self,item,patch) end
function Model:update_route(id,patch) return patch_item(self,self:get_route(id),patch) end
function Model:update_premise(id,patch) return patch_item(self,self:get_premise(id),patch) end
function Model:update_room(id,patch) return patch_item(self,self:get_room(id),patch) end
function Model:update_object(id,patch) return patch_item(self,self:get_object(id),patch) end
function Model:update_volume(id,patch) return patch_item(self,self:get_volume(id),patch) end
function Model:update_camera(id,patch) return patch_item(self,self:get_camera(id),patch) end
function Model:update_cover_node(id,patch) return patch_item(self,self:get_cover_node(id),patch) end
function Model:update_scene(id,patch) return patch_item(self,self:get_scene(id),patch) end
function Model:update_asset(id,patch) return patch_item(self,self:get_asset(id),patch) end

function Model:delete_location(id)
    local _,idx=self:get_location(id); if not idx then return false,'location not found' end; self:snapshot(); table.remove(self.data.locations,idx)
    for _,route in ipairs(self.data.routes) do local kept={}; for _,v in ipairs(route.location_ids or {}) do if v~=id then table.insert(kept,v) end end; route.location_ids=kept end
    for _,scene in ipairs(self.data.scenes or {}) do local kept={};for _,v in ipairs(scene.location_ids or {}) do if v~=id then table.insert(kept,v) end end;scene.location_ids=kept end
    self:touch(); return true
end
function Model:delete_route(id)
    local _,idx=self:get_route(id);if not idx then return false,'route not found' end;self:snapshot();table.remove(self.data.routes,idx)
    for _,scene in ipairs(self.data.scenes or {}) do local kept={};for _,v in ipairs(scene.route_ids or {}) do if v~=id then table.insert(kept,v) end end;scene.route_ids=kept end
    self:touch();return true
end
function Model:delete_objects(ids)
    if type(ids)~='table' then return false,'object IDs must be a list' end
    local remove={};local count=0
    for _,id in ipairs(ids) do if not remove[id] then if not self:get_object(id) then return false,'object not found: '..tostring(id) end;remove[id]=true;count=count+1 end end
    if count==0 then return false,'no objects selected' end
    self:snapshot()
    for i=#self.data.objects,1,-1 do if remove[self.data.objects[i].id] then table.remove(self.data.objects,i) end end
    local kept_npc_routes={};for _,route in ipairs(self.data.npc_routes or {}) do if not remove[route.npc_id] then table.insert(kept_npc_routes,route) end end;self.data.npc_routes=kept_npc_routes
    for _,encounter in ipairs(self.data.combat_encounters or {}) do
        local kept_groups={};local group_ids={}
        for _,group in ipairs(encounter.groups or {}) do local members={};for _,id in ipairs(group.npc_ids or {}) do if not remove[id] then table.insert(members,id) end end;group.npc_ids=members;if #members>0 then kept_groups[#kept_groups+1]=group;group_ids[group.id]=true end end
        encounter.groups=kept_groups
        for _,wave in ipairs(encounter.waves or {}) do local ids={};for _,id in ipairs(wave.group_ids or {}) do if group_ids[id] then ids[#ids+1]=id end end;wave.group_ids=ids end
    end
    for _,room in ipairs(self.data.rooms or {}) do
        local kept={}
        for _,object_id in ipairs(room.shell_object_ids or {}) do if not remove[object_id] then table.insert(kept,object_id) end end
        room.shell_object_ids=kept
    end
    for i=#self.data.object_groups,1,-1 do
        local group=self.data.object_groups[i];local kept={};for _,object_id in ipairs(group.object_ids or {}) do if not remove[object_id] then table.insert(kept,object_id) end end;group.object_ids=kept
        if #kept==0 then local removed_id=group.id;table.remove(self.data.object_groups,i);for _,child in ipairs(self.data.object_groups) do if child.parent_id==removed_id then child.parent_id=nil end end end
    end
    for _,scene in ipairs(self.data.scenes or {}) do local kept={};for _,object_id in ipairs(scene.object_ids or {}) do if not remove[object_id] then table.insert(kept,object_id) end end;scene.object_ids=kept end
    for _,variant in ipairs(self.data.world_state_variants or {}) do local kept={};for _,member in ipairs(variant.members or {}) do if not (member.kind=='object' and remove[member.item_id]) then table.insert(kept,member) end end;variant.members=kept end
    self:touch();return true,nil,count
end
function Model:delete_object(id) return self:delete_objects({id}) end
function Model:delete_volume(id)
    local _,idx=self:get_volume(id);if not idx then return false,'volume not found' end;self:snapshot();table.remove(self.data.volumes,idx)
    for _,scene in ipairs(self.data.scenes or {}) do local kept={};for _,v in ipairs(scene.volume_ids or {}) do if v~=id then table.insert(kept,v) end end;scene.volume_ids=kept end
    self:touch();return true
end
function Model:delete_camera(id)
    local _,idx=self:get_camera(id);if not idx then return false,'camera not found' end;self:snapshot();table.remove(self.data.cameras,idx)
    for _,scene in ipairs(self.data.scenes or {}) do local kept={};for _,v in ipairs(scene.camera_ids or {}) do if v~=id then table.insert(kept,v) end end;scene.camera_ids=kept end
    self:touch();return true
end
function Model:delete_cover_node(id)
    local _,idx=self:get_cover_node(id);if not idx then return false,'cover node not found' end
    self:snapshot();table.remove(self.data.cover_nodes,idx);self:touch();return true
end
function Model:delete_scene(id) local _,idx=self:get_scene(id);if not idx then return false,'scene not found' end;self:snapshot();table.remove(self.data.scenes,idx);self:touch();return true end
function Model:delete_asset(id) local _,idx=self:get_asset(id); if not idx then return false,'asset not found' end; self:snapshot(); table.remove(self.data.assets,idx); self:touch(); return true end
function Model:delete_room(id)
    local _,idx=self:get_room(id); if not idx then return false,'room not found' end; self:snapshot(); table.remove(self.data.rooms,idx)
    local removed_objects,removed_volumes,removed_cameras={},{},{}
    for _,item in ipairs(self.data.objects) do if item.room_id==id then removed_objects[item.id]=true end end
    for _,item in ipairs(self.data.volumes) do if item.room_id==id then removed_volumes[item.id]=true end end
    for _,item in ipairs(self.data.cameras) do if item.room_id==id then removed_cameras[item.id]=true end end
    for i=#self.data.cover_nodes,1,-1 do if self.data.cover_nodes[i].room_id==id then table.remove(self.data.cover_nodes,i) end end
    for i=#self.data.objects,1,-1 do if self.data.objects[i].room_id==id then table.remove(self.data.objects,i) end end
    for i=#self.data.volumes,1,-1 do if self.data.volumes[i].room_id==id then table.remove(self.data.volumes,i) end end
    for i=#self.data.cameras,1,-1 do if self.data.cameras[i].room_id==id then table.remove(self.data.cameras,i) end end
    for i=#self.data.object_groups,1,-1 do if self.data.object_groups[i].room_id==id then table.remove(self.data.object_groups,i) end end
    for _,scene in ipairs(self.data.scenes or {}) do
        local rooms={};for _,value in ipairs(scene.room_ids or {}) do if value~=id then table.insert(rooms,value) end end;scene.room_ids=rooms
        local objects={};for _,value in ipairs(scene.object_ids or {}) do if not removed_objects[value] then table.insert(objects,value) end end;scene.object_ids=objects
        local volumes={};for _,value in ipairs(scene.volume_ids or {}) do if not removed_volumes[value] then table.insert(volumes,value) end end;scene.volume_ids=volumes
        local cameras={};for _,value in ipairs(scene.camera_ids or {}) do if not removed_cameras[value] then table.insert(cameras,value) end end;scene.camera_ids=cameras
    end
    self:touch(); return true
end
function Model:delete_premise(id)
    local _,idx=self:get_premise(id); if not idx then return false,'premise not found' end; self:snapshot(); table.remove(self.data.premises,idx)
    for i=#self.data.rooms,1,-1 do if self.data.rooms[i].premise_id==id then table.remove(self.data.rooms,i) end end
    for i=#self.data.objects,1,-1 do if self.data.objects[i].premise_id==id then table.remove(self.data.objects,i) end end
    for i=#self.data.volumes,1,-1 do if self.data.volumes[i].premise_id==id then table.remove(self.data.volumes,i) end end
    for i=#self.data.cameras,1,-1 do if self.data.cameras[i].premise_id==id then table.remove(self.data.cameras,i) end end
    for i=#self.data.cover_nodes,1,-1 do if self.data.cover_nodes[i].premise_id==id then table.remove(self.data.cover_nodes,i) end end
    for i=#self.data.object_groups,1,-1 do if self.data.object_groups[i].premise_id==id then table.remove(self.data.object_groups,i) end end
    for i=#self.data.scenes,1,-1 do if self.data.scenes[i].premise_id==id then table.remove(self.data.scenes,i) end end
    -- Environments are reusable conditions; keep them and drop only the premise link.
    for _,environment in ipairs(self.data.environments or {}) do if environment.premise_id==id then environment.premise_id=nil end end
    for _,spline in ipairs(self.data.splines or {}) do if spline.premise_id==id then spline.premise_id=nil end end
    for _,timeline in ipairs(self.data.timelines or {}) do if timeline.premise_id==id then timeline.premise_id=nil end end
    self:touch(); return true
end

function Model:duplicate_location(id,name) local v=self:get_location(id); if not v then return nil,'location not found' end; local c=Util.deepcopy(v); c.id=nil;c.created_at=nil;c.updated_at=nil;c.name=name or(v.name..' Copy');c.transform.position.x=c.transform.position.x+0.5;return self:add_location(c) end
function Model:duplicate_object(id,name,offset)
    local v=self:get_object(id); if not v then return nil,'object not found' end; local c=Util.deepcopy(v); c.id=nil;c.created_at=nil;c.updated_at=nil;c.name=name or(v.name..' Copy'); offset=offset or {x=0.5,y=0,z=0}
    c.transform.position.x=c.transform.position.x+(offset.x or 0); c.transform.position.y=c.transform.position.y+(offset.y or 0); c.transform.position.z=c.transform.position.z+(offset.z or 0); return self:add_object(c)
end

function Model:add_opening(room_id,opening) local room=self:get_room(room_id); if not room then return nil,'room not found' end; self:snapshot(); local value=normalize_opening(opening); table.insert(room.openings,value); room.updated_at=Util.now_iso(); self:touch(); return value end

function Model:find_duplicates(distance)
    local max_d=tonumber(distance) or tonumber(self.data.settings.duplicate_distance) or 0.35; local out={}
    for i=1,#self.data.locations do for j=i+1,#self.data.locations do local d=Util.distance3(self.data.locations[i].transform.position,self.data.locations[j].transform.position); if d<=max_d then table.insert(out,{a=self.data.locations[i].id,b=self.data.locations[j].id,distance=d}) end end end
    return out
end

function Model:validate()
    local issues={}; local names={}; local premise_ids={}; local room_ids={}; local layer_ids={}
    for _,v in ipairs(self.data.premises) do premise_ids[v.id]=true end; for _,v in ipairs(self.data.rooms) do room_ids[v.id]=true end; for _,v in ipairs(self.data.layers) do layer_ids[v.id]=true end
    for _,loc in ipairs(self.data.locations) do
        if Util.trim(loc.name)=='' then table.insert(issues,{severity='error',id=loc.id,message='Location has an empty name'}) end
        local key=string.lower(loc.name); names[key]=(names[key] or 0)+1; local p=loc.transform.position
        if math.abs(p.x)>10000 or math.abs(p.y)>10000 or p.z< -2000 or p.z>3000 then table.insert(issues,{severity='warning',id=loc.id,message='Coordinate is far outside normal Night City bounds'}) end
        if loc.radius<0 then table.insert(issues,{severity='error',id=loc.id,message='Radius cannot be negative'}) end
    end
    for name,count in pairs(names) do if count>1 then table.insert(issues,{severity='warning',message='Duplicate location name: '..name}) end end
    for _,pair in ipairs(self:find_duplicates()) do table.insert(issues,{severity='info',message=string.format('Very close points: %s / %s (%.3fm)',pair.a,pair.b,pair.distance)}) end
    for _,room in ipairs(self.data.rooms) do
        if not premise_ids[room.premise_id] then table.insert(issues,{severity='error',id=room.id,message='Room references a missing premise'}) end
        if room.size.width<=room.wall_thickness*2 or room.size.depth<=room.wall_thickness*2 then table.insert(issues,{severity='error',id=room.id,message='Room is too small for its wall thickness'}) end
        for _,o in ipairs(room.openings) do local wall_length=(o.wall=='north' or o.wall=='south') and room.size.width or room.size.depth; if o.width>=wall_length then table.insert(issues,{severity='error',id=o.id,message='Opening is wider than its wall'}) end; if o.sill+o.height>room.size.height then table.insert(issues,{severity='error',id=o.id,message='Opening exceeds room height'}) end end
    end
    local object_ids={};for _,object in ipairs(self.data.objects) do object_ids[object.id]=true end
    local group_ids={};for _,group in ipairs(self.data.object_groups or {}) do group_ids[group.id]=true end
    for _,group in ipairs(self.data.object_groups or {}) do
        if group.premise_id and not premise_ids[group.premise_id] then table.insert(issues,{severity='error',id=group.id,message='Object group references a missing premise'}) end
        if group.parent_id and not group_ids[group.parent_id] then table.insert(issues,{severity='error',id=group.id,message='Object group references a missing parent group'}) end
        for _,object_id in ipairs(group.object_ids or {}) do if not object_ids[object_id] then table.insert(issues,{severity='error',id=group.id,message='Object group references missing object: '..tostring(object_id)}) end end
    end
    for _,prefab in ipairs(self.data.object_prefabs or {}) do
        if #(prefab.objects or {})==0 then table.insert(issues,{severity='warning',id=prefab.id,message='Reusable prefab has no objects'}) end
        for index,object in ipairs(prefab.objects or {}) do
            if Util.trim(object.template)=='' and not (object.metadata and type(object.metadata.world_builder)=='table') then table.insert(issues,{severity='warning',id=prefab.id,message='Prefab object '..index..' has no spawnable resource'}) end
        end
    end
    for _,obj in ipairs(self.data.objects) do
        if obj.premise_id and not premise_ids[obj.premise_id] then table.insert(issues,{severity='error',id=obj.id,message='Object references a missing premise'}) end
        if obj.room_id and not room_ids[obj.room_id] then table.insert(issues,{severity='warning',id=obj.id,message='Object references a missing room'}) end
        if not layer_ids[obj.layer] then table.insert(issues,{severity='warning',id=obj.id,message='Object uses an unknown layer: '..tostring(obj.layer)}) end
        if obj.enabled and obj.kind~='marker' and Util.trim(obj.template)=='' and not (obj.metadata and type(obj.metadata.world_builder)=='table') then table.insert(issues,{severity='warning',id=obj.id,message='Enabled object has no spawn template'}) end
    end
    for _,variant in ipairs(self.data.world_state_variants or {}) do
        if Util.trim(variant.name or '')=='' then table.insert(issues,{severity='error',id=variant.id,message='World-state variant has an empty name'}) end
        if variant.premise_id and not premise_ids[variant.premise_id] then table.insert(issues,{severity='error',id=variant.id,message='World-state variant references a missing premise'}) end
        if #(variant.conditions or {})==0 then table.insert(issues,{severity='error',id=variant.id,message='World-state variant requires at least one fact condition'}) end
        for _,member in ipairs(variant.members or {}) do if member.kind=='object' and not object_ids[member.item_id] then table.insert(issues,{severity='error',id=variant.id,message='World-state variant references missing object: '..tostring(member.item_id)}) end end
    end
    for _,volume in ipairs(self.data.volumes) do
        if volume.premise_id and not premise_ids[volume.premise_id] then table.insert(issues,{severity='error',id=volume.id,message='Volume references a missing premise'}) end
        if volume.room_id and not room_ids[volume.room_id] then table.insert(issues,{severity='warning',id=volume.id,message='Volume references a missing room'}) end
        if volume.shape=='box' and (volume.size.x<=0 or volume.size.y<=0 or volume.size.z<=0) then table.insert(issues,{severity='error',id=volume.id,message='Box volume dimensions must be positive'}) end
        if (volume.shape=='sphere' or volume.shape=='cylinder') and volume.radius<=0 then table.insert(issues,{severity='error',id=volume.id,message='Volume radius must be positive'}) end
    end
    for _,camera in ipairs(self.data.cameras) do
        if camera.premise_id and not premise_ids[camera.premise_id] then table.insert(issues,{severity='error',id=camera.id,message='Camera references a missing premise'}) end
        if camera.room_id and not room_ids[camera.room_id] then table.insert(issues,{severity='warning',id=camera.id,message='Camera references a missing room'}) end
        local p=camera.transform.position; local l=camera.look_at
        if Util.distance3(p,l)<0.05 then table.insert(issues,{severity='warning',id=camera.id,message='Camera look-at target is too close to camera position'}) end
    end
    for _,cover in ipairs(self.data.cover_nodes or {}) do
        if not premise_ids[cover.premise_id] then table.insert(issues,{severity='error',id=cover.id,message='Cover node references a missing premise'}) end
        if cover.room_id and not room_ids[cover.room_id] then table.insert(issues,{severity='warning',id=cover.id,message='Cover node references a missing room'}) end
        if cover.cover_type~='crouch' and cover.cover_type~='standing' then table.insert(issues,{severity='error',id=cover.id,message='Cover node type must be crouch or standing'}) end
        if not ({low=true,medium=true,high=true})[cover.exposure] then table.insert(issues,{severity='error',id=cover.id,message='Cover exposure must be low, medium, or high'}) end
        if cover.spacing<0.25 or cover.spacing>10 then table.insert(issues,{severity='error',id=cover.id,message='Cover spacing must be between 0.25 and 10 metres'}) end
    end
    local location_ids,volume_ids,camera_ids,route_ids={},{},{},{}
    for _,item in ipairs(self.data.locations) do location_ids[item.id]=true end
    for _,item in ipairs(self.data.volumes) do volume_ids[item.id]=true end
    for _,item in ipairs(self.data.cameras) do camera_ids[item.id]=true end
    for _,item in ipairs(self.data.routes) do route_ids[item.id]=true end
    for _,scene in ipairs(self.data.scenes or {}) do
        if scene.premise_id and not premise_ids[scene.premise_id] then table.insert(issues,{severity='error',id=scene.id,message='Scene references a missing premise'}) end
        for _,id in ipairs(scene.room_ids or {}) do if not room_ids[id] then table.insert(issues,{severity='error',id=scene.id,message='Scene references missing room: '..tostring(id)}) end end
        for _,id in ipairs(scene.object_ids or {}) do if not object_ids[id] then table.insert(issues,{severity='error',id=scene.id,message='Scene references missing object: '..tostring(id)}) end end
        for _,id in ipairs(scene.location_ids or {}) do if not location_ids[id] then table.insert(issues,{severity='error',id=scene.id,message='Scene references missing location: '..tostring(id)}) end end
        for _,id in ipairs(scene.volume_ids or {}) do if not volume_ids[id] then table.insert(issues,{severity='error',id=scene.id,message='Scene references missing volume: '..tostring(id)}) end end
        for _,id in ipairs(scene.camera_ids or {}) do if not camera_ids[id] then table.insert(issues,{severity='error',id=scene.id,message='Scene references missing camera: '..tostring(id)}) end end
        for _,id in ipairs(scene.route_ids or {}) do if not route_ids[id] then table.insert(issues,{severity='error',id=scene.id,message='Scene references missing route: '..tostring(id)}) end end
    end
    for _,asset in ipairs(self.data.assets) do
        if Util.trim(asset.template)=='' then table.insert(issues,{severity='warning',id=asset.id,message='Asset has no .ent template: '..asset.name}) end
    end
    return issues
end

return Model
