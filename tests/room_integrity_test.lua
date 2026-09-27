local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
env.wb_enabled=false;app.integrations:refresh()
local denied,err=app.quickstart:create_first_room({width=5,depth=5,height=3})
assert(not denied and err);assert(#app.model.data.rooms==0 and #app.model.data.premises==0,'missing backend must not create duplicate invisible rooms')
env.wb_enabled=true;app.integrations:refresh()
local first=assert(app.quickstart:create_first_room({width=5,depth=5,height=3}))
local second=assert(app.quickstart:add_adjacent_room({width=5,depth=5,height=3,direction='north'}))
assert(#second.openings==2)
for _,room in ipairs({first.room,second.room}) do
    for _,id in ipairs(room.shell_object_ids) do
        local object=app.model:get_object(id)
        assert(object.metadata.world_builder,'room shell piece is not a World Builder game resource')
        local path=object.metadata.world_builder.resource_path or ''
        assert(not path:find('base\\spawner\\cube.mesh',1,true),'room shell fell back to the white primitive cube')
        if object.metadata.opening_id then assert(object.kind=='door' or object.kind=='window','opening was filled by an unrelated primitive') end
    end
end
local old_count=#app.model.data.rooms
local invalid=app.quickstart:create_room_here({width=-3,depth=5,height=3})
assert(not invalid and #app.model.data.rooms==old_count)
app.selection:set('room',second.room.id)
local changed=assert(app.actions:update_selected({size={width=9,depth=7,height=4}}))
local floor;local floor_area=0
for _,id in ipairs(changed.shell_object_ids) do
    local object=app.model:get_object(id)
    if object.kind=='floor' then floor=floor or object;local dimensions=object.metadata.dimensions;floor_area=floor_area+dimensions.x*dimensions.y end
end
assert(floor and math.abs(floor_area-63)<0.001,'room resize did not retile the complete 9x7 floor')
assert(floor.metadata.world_builder.resource_path:find('.mesh',1,true),'floor is not backed by a game mesh')
assert(app.runtime_shell.handles[floor.id].entry.data.spawnData==floor.metadata.world_builder.resource_path)
env.wb_remove_error=true
local removed,remove_err=app.builder:clear_room_shell(second.room.id)
assert(not removed and remove_err);assert(app.model:get_object(floor.id),'failed shell cleanup lost authored reference')
env.wb_remove_error=false

local asset=app.model:get_asset('builtin_chair_poor')
local placed=assert(app.actions:place_asset(asset.id,'player',{spawn=false}))
assert(not placed.runtime.spawned,'explicit spawn=false was ignored')
assert(app.placement:spawn(placed))
app.selection:set('object',placed.id)
assert(app.actions:update_selected({name='Safe edit',runtime={spawned=false}}))
assert(placed.runtime.spawned,'inspector cache replaced runtime ownership')
print('Room preflight, doorway gaps, resizing, cleanup ownership: OK')
