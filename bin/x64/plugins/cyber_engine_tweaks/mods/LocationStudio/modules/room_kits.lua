local Util=require('modules/util')

local RoomKits={}

local STATIC_MESH_DEFINITION={
    definition_key='mesh_static',category='Mesh',variant='Mesh',
    class_module='modules/classes/spawn/mesh/mesh',module_path='mesh/mesh',apply_scale=true,
}

local PRESETS={
    common_interior={
        id='common_interior',name='COMMON INTERIOR',description='Neutral Night City interior architecture.',
        roles={
            floor={path='base\\environment\\architecture\\common\\int\\int_common_a\\int_common_a_floor_l300_w200_a.mesh',native_x=3.0,native_y=2.0,native_z=1.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            ceiling={path='base\\environment\\architecture\\common\\int\\int_common_a\\int_common_a_ceiling_tiles_b_l300_w200_a.mesh',native_x=3.0,native_y=2.0,native_z=1.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            wall={path='base\\environment\\architecture\\common\\int\\int_common_a\\int_common_a_wall_h400_l200_a.mesh',native_x=2.0,native_y=1.0,native_z=4.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            door={path='base\\environment\\architecture\\common\\int\\int_common_a\\int_common_a_wall_door_single_h400_l200_a.mesh',native_x=2.0,native_y=1.0,native_z=4.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            window={path='base\\environment\\architecture\\common\\int\\int_common_a\\int_common_a_wall_window_mid_h400_l200_a.mesh',native_x=2.0,native_y=1.0,native_z=4.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
        },
    },
    kitsch_apartment={
        id='kitsch_apartment',name='KITSCH APARTMENT',description='Residential Kitsch apartment shell pieces.',
        roles={
            floor={path='base\\environment\\architecture\\common\\int\\int_kts_apartment_a\\int_kts_apartment_a_floor_a_l300_w200.mesh',native_x=3.0,native_y=2.0,native_z=1.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            ceiling={path='base\\environment\\architecture\\common\\int\\int_kts_apartment_a\\int_kts_apartment_a_ceiling_a_l300_w200.mesh',native_x=3.0,native_y=2.0,native_z=1.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            wall={path='base\\environment\\architecture\\common\\int\\int_kts_apartment_a\\int_kts_apartment_a_wall_a_l200.mesh',native_x=2.0,native_y=1.0,native_z=4.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            door={path='base\\environment\\architecture\\common\\int\\int_kts_apartment_a\\int_kts_apartment_a_wall_door_single_a_l300.mesh',native_x=3.0,native_y=1.0,native_z=4.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
            window={path='base\\environment\\architecture\\common\\int\\int_kts_apartment_a\\int_kts_apartment_a_wall_window_a_middle_l200.mesh',native_x=2.0,native_y=1.0,native_z=4.0,yaw=0,offset_x=0,offset_y=0,offset_z=0},
        },
    },
}

local ORDER={'common_interior','kitsch_apartment'}

local function basename(path)
    path=tostring(path or ''):gsub('\\','/')
    local name=path:match('([^/]+)$') or path
    return name:gsub('%.[^%.]+$','')
end

local function normalized_role(role,fallback)
    role=type(role)=='table' and role or {};fallback=fallback or {}
    return {
        path=Util.trim(role.path or fallback.path or ''),
        native_x=math.max(0.01,tonumber(role.native_x) or tonumber(fallback.native_x) or 1),
        native_y=math.max(0.01,tonumber(role.native_y) or tonumber(fallback.native_y) or 1),
        native_z=math.max(0.01,tonumber(role.native_z) or tonumber(fallback.native_z) or 1),
        yaw=tonumber(role.yaw) or tonumber(fallback.yaw) or 0,
        offset_x=tonumber(role.offset_x) or tonumber(fallback.offset_x) or 0,
        offset_y=tonumber(role.offset_y) or tonumber(fallback.offset_y) or 0,
        offset_z=tonumber(role.offset_z) or tonumber(fallback.offset_z) or 0,
        asset_id=role.asset_id,
        asset_name=role.asset_name,
        world_builder=type(role.world_builder)=='table' and Util.deepcopy(role.world_builder) or nil,
    }
end

function RoomKits.default_settings()
    local preset=PRESETS.common_interior
    return {preset=preset.id,collision=true,floor_thickness=0.20,wall_thickness=0.15,roles=Util.deepcopy(preset.roles)}
end

function RoomKits.normalize(settings)
    settings=type(settings)=='table' and settings or {}
    local requested=settings.preset
    local preset=PRESETS[requested] or PRESETS.common_interior
    settings.preset=requested=='custom' and 'custom' or preset.id
    settings.collision=settings.collision~=false
    settings.floor_thickness=math.max(0.02,tonumber(settings.floor_thickness) or 0.20)
    settings.wall_thickness=math.max(0.02,tonumber(settings.wall_thickness) or 0.15)
    settings.roles=type(settings.roles)=='table' and settings.roles or {}
    for _,role in ipairs({'floor','ceiling','wall','door','window'}) do
        settings.roles[role]=normalized_role(settings.roles[role],preset.roles[role])
    end
    return settings
end

function RoomKits.presets()
    local values={}
    for _,id in ipairs(ORDER) do table.insert(values,PRESETS[id]) end
    return values
end

function RoomKits.preset(id) return PRESETS[id] end

function RoomKits.apply_preset(settings,id)
    local preset=PRESETS[id];if not preset then return nil,'unknown room kit: '..tostring(id) end
    settings=RoomKits.normalize(settings)
    settings.preset=id;settings.roles=Util.deepcopy(preset.roles)
    return settings
end

function RoomKits.assign_asset(settings,role,asset)
    if not ({floor=true,ceiling=true,wall=true,door=true,window=true})[role] then return nil,'unknown room-kit role: '..tostring(role) end
    local wb=asset and asset.metadata and asset.metadata.world_builder
    if not wb or wb.definition_key~='mesh_static' then return nil,'Select an imported Static Mesh game asset first.' end
    settings=RoomKits.normalize(settings)
    local current=settings.roles[role]
    current.path=Util.trim(wb.resource_path or asset.template or ((wb.entry or {}).data or {}).spawnData or '')
    if current.path=='' then return nil,'The selected mesh has no game resource path.' end
    current.asset_id=asset.id;current.asset_name=asset.name;current.world_builder=Util.deepcopy(wb)
    settings.preset='custom'
    return current
end

function RoomKits.mesh_metadata(role,scale,kit)
    local path=Util.trim(role and role.path or '')
    if path=='' then return nil,'Room-kit mesh path is empty.' end
    local wb=role.world_builder and Util.deepcopy(role.world_builder) or Util.deepcopy(STATIC_MESH_DEFINITION)
    wb.definition_key='mesh_static';wb.category='Mesh';wb.variant='Mesh';wb.module_path=wb.module_path or 'mesh/mesh';wb.apply_scale=true
    wb.resource_path=path;wb.resource_name=role.asset_name or basename(path)
    wb.entry=type(wb.entry)=='table' and wb.entry or {}
    wb.entry.name=path;wb.entry.fileName=wb.resource_name
    wb.entry.data=type(wb.entry.data)=='table' and wb.entry.data or {}
    wb.entry.data.spawnData=path
    wb.entry.data.scale={x=scale.x,y=scale.y,z=scale.z}
    return {generated=true,room_kit=true,kit=kit,world_builder=wb}
end

function RoomKits.collision_metadata(scale,role)
    return {
        generated=true,room_kit=true,room_collision=true,role=role,
        world_builder={
            definition_key='collision_shape',category='Collision',variant='Collision Shape',
            class_module='modules/classes/spawn/collision/collider',module_path='collision/collider',apply_scale=true,
            resource_name='Box - Default',resource_path='',
            entry={name='Box - Default',fileName='Box - Default',data={
                shape=0,scale={x=scale.x,y=scale.y,z=scale.z},previewed=false,
                modulePath='collision/collider',dataType='Collision Shape',
            }},
        },
    }
end

return RoomKits
