local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.70.0')

local premise=assert(app.actions:create_premise_from_player('Viewport Tools','exterior'))

local function wb_metadata(path,name)
    return {world_builder={
        definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',
        resource_path=path,resource_name=name,
        entry={name=path,fileName=name,data={spawnData=path}},
    }}
end

local near=assert(app.builder:place_object({
    premise_id=premise.id,name='Near Crosshair',kind='mesh',template='base\\near.mesh',size={x=0.1,y=0.1,z=0.1},
    transform={position={x=10.20,y=25,z=31,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata=wb_metadata('base\\near.mesh','near'),
}))
local far=assert(app.builder:place_object({
    premise_id=premise.id,name='Outside Radius',kind='mesh',template='base\\far.mesh',size={x=0.1,y=0.1,z=0.1},
    transform={position={x=11.80,y=25,z=31,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata=wb_metadata('base\\far.mesh','far'),
}))
assert(app.placement:spawn(near));assert(app.placement:spawn(far))

local picked,pick_warning=app.viewport_tools:pick_aimed_object({premise_id=premise.id,radius=0.5,max_distance=20})
assert(picked,pick_warning);assert(picked.object.id==near.id);assert(app.selected_object_id==near.id)
assert(picked.pick.perpendicular_distance<0.21);assert(picked.pick.candidate_count==1)
assert(env.wb_selected==app.runtime_shell.handles[near.id],'picked World Builder handle was not focused')

local miss,miss_err=app.viewport_tools:pick_aimed_object({premise_id=premise.id,radius=0.05,max_distance=4})
assert(not miss and miss_err:find('No project object',1,true))

local asset=app.model:add_asset({name='Surface Prop',category='Props',kind='prop',template='base\\surface_prop.ent',layer='decoration'})
env.aim_normal={x=0,y=0,z=1}
local preview,preview_warning=app.placement:preview_asset(asset.id,{mode='aim',distance=8,follow=true,align_surface=true})
assert(preview,preview_warning);assert(math.abs(preview.transform.rotation.roll)<0.001);assert(math.abs(preview.transform.rotation.pitch)<0.001)

env.aim_normal={x=1,y=0,z=0}
preview=assert(app.placement:update_preview(true))
assert(math.abs(preview.transform.rotation.pitch+90)<0.001,'wall normal did not produce a surface-aligned pitch')

assert(app.placement:clear_preview())
env.aim_normal={x=0,y=0,z=1};env.aim_x=15
local stamp=assert(app.placement:start_stamp(asset.id,{mode='aim',distance=8,align_surface=true,stamp_spacing=0.5}))
assert(stamp.stamp_mode and stamp.follow)
local first=assert(app.placement:stamp_once(premise.id,nil));assert(app.model:get_object(first.id))
local after_first=app.placement:preview_status();assert(after_first.active and after_first.placed_count==1)
local blocked,blocked_err=app.placement:stamp_once(premise.id,nil)
assert(not blocked and blocked_err:find('Move the preview',1,true))
env.aim_x=16;assert(app.placement:update_preview(true))
local second=assert(app.placement:stamp_once(premise.id,nil));assert(second.id~=first.id)
local after_second=app.placement:preview_status();assert(after_second.active and after_second.placed_count==2)
assert(app.placement:stop_stamp());assert(app.placement:preview_status().active==false)

app.selection:set('premise',premise.id)
app.selection:set('asset',asset.id)
app.model.data.settings.workspace.panel='SCENE'
app.model.data.settings.workspace.bottom_panel='ASSETS'
app.model.data.settings.asset_preview.stamp_mode=true
app.ui.compact_scene='overview'
app.ui.browser.asset_source='PROJECT'
events.onOverlayOpen();env:draw()
app.model.data.settings.workspace.panel='LIBRARY';env:draw()
for _,label in ipairs({'PICK AIMED OBJECT##scene_pick','START STROKE','STAMP NOW'}) do assert(env.labels[label],label..' missing from UI') end
assert(hotkeys.locationstudio_pick_aimed_object and hotkeys.locationstudio_stamp_preview and hotkeys.locationstudio_stop_stamp and hotkeys.locationstudio_cancel_stamp)

local report=app.diagnostics:run()
assert(report.modules.viewport_tools and report.runtime.viewport_tools)
local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[viewport:pick]','[stamp:stroke]'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio aim picker, surface alignment, and stamp placement: OK')
