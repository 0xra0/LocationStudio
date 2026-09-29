local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.78.0')

local premise=assert(app.actions:create_premise_from_player('Placement Edit Test','exterior'))
local function wb_metadata(path,name)
    return {room_kit=true,generated=true,world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name=name,entry={name=path,fileName=name,data={spawnData=path}}}}
end
local wb_asset=app.model:add_asset({name='Placement WB Asset',kind='mesh',template='base\\placement.mesh',size={x=1,y=1,z=1},metadata=wb_metadata('base\\placement.mesh','placement')})
local cet_asset=app.model:add_asset({name='Placement CET Asset',kind='prop',template='base\\placement.ent',size={x=1,y=1,z=1}})
assert(app:save(true));app.selection:set('asset',wb_asset.id)
env.aim_x=40;env.aim_y=50;env.aim_z=8;env.aim_normal={x=1,y=0,z=0}

local object_count=#app.model.data.objects;local undo_before=#app.model.undo_stack
local started=assert(app.transform_session:start_placement({kind='asset',id=wb_asset.id,premise_id=premise.id,mode='aim',distance=20,surface_offset=0.1,align_surface=true,yaw=15}))
assert(started.operation=='placement' and started.count==1 and started.creation.source_kind=='asset' and started.creation.asset_id==wb_asset.id)
assert(started.creation.mode=='aim' and started.creation.placement_source=='camera_raycast' and started.creation.surface_aligned==true)
local placed=assert(app.model:get_object(started.created_ids[1]));assert(app.placement:is_tracked(placed))
assert(math.abs(placed.transform.position.x-40.1)<0.001 and placed.transform.position.y==50 and placed.transform.position.z==8)
assert(math.abs(placed.transform.rotation.pitch+90)<0.001 and placed.transform.rotation.yaw==15)
assert(placed.metadata.world_builder and placed.metadata.detached_from_room==true)
assert(#app.model.undo_stack==undo_before and app.dirty==false)
assert(app.transform_session:adjust({dx=0.5,dy=0.25,dyaw=5}))
assert(app.transform_session:cancel());assert(#app.model.data.objects==object_count and app.selection.kind=='asset' and app.selection.id==wb_asset.id and app.dirty==false)

started=assert(app.transform_session:start_placement({kind='asset',id=wb_asset.id,premise_id=premise.id,mode='aim'}))
env.wb_remove_error=true
local blocked,blocked_err=app.transform_session:cancel();assert(not blocked and blocked_err:find('retained the copies',1,true));assert(app.transform_session:is_active())
env.wb_remove_error=false;assert(app.transform_session:cancel())

app.selection:set('asset',cet_asset.id)
local preview=assert(app.placement:preview_asset(cet_asset.id,{mode='aim',distance=15,follow=false,surface_offset=0.02,align_surface=false}))
local preview_transform=preview.transform
started=assert(app.transform_session:start_placement({kind='asset',id=cet_asset.id,premise_id=premise.id,mode='preview'}))
assert(started.creation.mode=='preview' and app.placement:preview_status().active==false)
placed=assert(app.model:get_object(started.created_ids[1]));assert(app.placement:is_tracked(placed))
assert(math.abs(placed.transform.position.x-preview_transform.position.x)<0.001 and math.abs(placed.transform.position.z-preview_transform.position.z)<0.001)
assert(app.transform_session:cancel());assert(app.selection.kind=='asset' and app.selection.id==cet_asset.id)

local missing_preview,preview_err=app.transform_session:start_placement({kind='asset',id=cet_asset.id,premise_id=premise.id,mode='preview'})
assert(not missing_preview and preview_err:find('start a preview',1,true))
started=assert(app.transform_session:start_placement({kind='asset',id=cet_asset.id,premise_id=premise.id,mode='player'}))
placed=assert(app.model:get_object(started.created_ids[1]));assert(placed.transform.position.x==10 and placed.transform.position.y==20 and placed.transform.position.z==30)
assert(app.transform_session:cancel())

local wb=assert(app.builder:place_object({premise_id=premise.id,name='Placed WB',kind='mesh',template='base\\placed.mesh',size={x=1,y=1,z=1},transform={position={x=11,y=20,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata=wb_metadata('base\\placed.mesh','placed')}))
local cet=assert(app.builder:place_object({premise_id=premise.id,name='Placed CET',kind='prop',template='base\\placed.ent',size={x=1,y=1,z=1},transform={position={x=13,y=20,z=31,w=1},rotation={roll=0,pitch=0,yaw=10}}}))
assert(app.placement:spawn(wb));assert(app.placement:spawn(cet));assert(app:save(true));app.selection:set_object_group({wb.id,cet.id},cet.id,'locationstudio')
env.aim_x=60;env.aim_y=70;env.aim_z=12;env.aim_normal={x=0,y=0,z=1}
object_count=#app.model.data.objects;undo_before=#app.model.undo_stack
started=assert(app.transform_session:start_placement({kind='object',mode='aim',distance=15,surface_offset=0,yaw_delta=90}))
assert(started.count==2 and started.creation.source_kind=='object' and started.creation.source_count==2)
local copy_wb=app.model:get_object(started.created_ids[1]);local copy_cet=app.model:get_object(started.created_ids[2])
assert(app.placement:is_tracked(copy_wb) and app.placement:is_tracked(copy_cet))
assert(math.abs(copy_wb.transform.position.x-60)<0.001 and math.abs(copy_wb.transform.position.y-69)<0.001)
assert(math.abs(copy_cet.transform.position.x-60)<0.001 and math.abs(copy_cet.transform.position.y-71)<0.001)
assert(math.abs((copy_cet.transform.position.z-copy_wb.transform.position.z)-1)<0.001)
assert(copy_wb.transform.rotation.yaw==90 and copy_cet.transform.rotation.yaw==100)
assert(copy_wb.metadata.detached_from_room==true)
assert(app.transform_session:adjust({dx=0.25,dz=0.5,dyaw=5}))
local committed=assert(app.transform_session:commit());assert(committed.operation=='placement' and #committed.created_ids==2)
assert(#app.model.undo_stack==undo_before+1 and #app.model.data.objects==object_count+2)
assert(app.actions:history('undo'));assert(#app.model.data.objects==object_count)
assert(app.actions:history('redo'));assert(#app.model.data.objects==object_count+2)

app.selection:set('object',cet.id);undo_before=#app.model.undo_stack
local legacy=assert(app.ent_tools:duplicate_at_aim('object',cet.id,10,false))
assert(legacy.id~=cet.id and not app.placement:is_tracked(legacy) and #app.model.undo_stack==undo_before+1)
assert(app.actions:history('undo'))

local invalid,invalid_err=app.transform_session:start_placement({kind='asset',id=cet_asset.id,premise_id=premise.id,mode='bad'})
assert(not invalid and invalid_err:find('placement mode',1,true))
local bridge=assert(app.bridge:handle({id='placement-start',op='start_placement_transform_edit',args={kind='object',ids={cet.id},active_id=cet.id,mode='aim',distance=10}}))
assert(bridge.operation=='placement' and #bridge.created_ids==1);assert(app.bridge:handle({id='placement-cancel',op='cancel_transform_edit',args={}}))

events.onOverlayOpen();app.selection:set('object',cet.id);app.ui.tools:draw();assert(env.labels['PLACE / AIM COPY + EDIT'],'Advanced Tools placement entry missing')
assert(hotkeys.locationstudio_placement_edit,'placement hotkey missing')
app.selection:set('asset',cet_asset.id);app.ui.browser:draw_asset_card(cet_asset,246,100,true)
assert(env.labels['PLACE + EDIT##'..cet_asset.id],'Asset card Placement Edit entry missing')
local editor_source=assert(io.open('ui/editor.lua','r'));local editor_text=editor_source:read('*a');editor_source:close();assert(editor_text:find('PLACEMENT EDIT ACTIVE',1,true))

local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[transform:placement] started','[transform:placement] adjusted','[transform:placement] committed','[transform:placement] cancel_blocked','[transform:placement] cancelled','[ent_tools:duplicate_at_aim] complete'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio transactional Placement + Edit: OK')
