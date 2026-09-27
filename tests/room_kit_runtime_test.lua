local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app

local created,err=app.quickstart:create_first_room({location_name='Kit Test',width=5,depth=4,height=3})
assert(created,err)
local room=created.room
local mesh_count,collision_count=0,0
for _,id in ipairs(room.shell_object_ids) do
    local object=assert(app.model:get_object(id))
    local wb=assert(object.metadata.world_builder,'shell object has no World Builder metadata')
    if object.metadata.room_collision then
        collision_count=collision_count+1;assert(wb.definition_key=='collision_shape');assert(wb.entry.data.previewed==false)
    else
        mesh_count=mesh_count+1;assert(wb.definition_key=='mesh_static');assert(wb.entry.data.spawnData:find('.mesh',1,true));assert(not wb.entry.data.spawnData:find('base\\spawner\\cube.mesh',1,true))
    end
end
assert(mesh_count>10 and collision_count==5,'expected tiled visuals and five base colliders')

local opening=assert(app.builder:add_opening({room_id=room.id,kind='door',wall='north',offset=0,width=1.2,height=2.2,sill=0}))
local door
for _,id in ipairs(opening.shell.object_ids) do local object=app.model:get_object(id);if object.kind=='door' then door=object end end
assert(door and door.metadata.world_builder.resource_path:find('wall_door_single',1,true),'door did not use the game door-wall module')

assert(app.builder:set_room_kit_preset('kitsch_apartment'))
local rebuilt=assert(app.builder:rebuild_room_shell(room.id))
assert(app.placement:spawn_room_shell(room.id))
local kitsch_wall
for _,id in ipairs(rebuilt.object_ids) do local object=app.model:get_object(id);if object.kind=='wall' then kitsch_wall=object;break end end
assert(kitsch_wall.metadata.world_builder.resource_path:find('int_kts_apartment_a',1,true),'preset did not replace room architecture')

local custom=app.model:add_asset({name='Custom Wall',kind='mesh',template='base\\custom\\custom_wall.mesh',metadata={world_builder={definition_key='mesh_static',category='Mesh',variant='Mesh',module_path='mesh/mesh',resource_name='custom_wall',resource_path='base\\custom\\custom_wall.mesh',apply_scale=true,entry={name='base\\custom\\custom_wall.mesh',fileName='custom_wall',data={spawnData='base\\custom\\custom_wall.mesh'}}}}})
assert(app.builder:assign_room_kit_role('wall',custom.id))
rebuilt=assert(app.builder:rebuild_room_shell(room.id))
for _,id in ipairs(rebuilt.object_ids) do local object=app.model:get_object(id);if object.kind=='wall' then assert(object.metadata.world_builder.resource_path==custom.template) end end

local legacy_object=app.model:get_object(rebuilt.object_ids[1]);legacy_object.metadata={generated=true}
local migration=app.builder:migrate_legacy_room_shells();assert(migration.migrated==1 and #migration.failed==0,'legacy room was not converted automatically')
for _,id in ipairs(room.shell_object_ids) do assert(app.model:get_object(id).metadata.world_builder,'legacy object survived room-kit migration') end

print('LocationStudio real game-asset room kit / collision / custom role: OK')
