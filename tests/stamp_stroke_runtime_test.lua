local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.61.0')

local premise=assert(app.actions:create_premise_from_player('Stamp Stroke Test','exterior'))
local function wb_metadata(path,name)
    return {world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name=name,entry={name=path,fileName=name,data={spawnData=path}}}}
end
local wb_asset=app.model:add_asset({name='Stroke Wall',kind='mesh',template='base\\stroke_wall.mesh',layer='decoration',size={x=1,y=0.2,z=2},metadata=wb_metadata('base\\stroke_wall.mesh','stroke_wall')})
local cet_asset=app.model:add_asset({name='Stroke Prop',kind='prop',template='base\\stroke_prop.ent',layer='decoration',size={x=1,y=1,z=1}})

assert(app:save(true));app.selection:set('asset',wb_asset.id)
local object_before=#app.model.data.objects;local history_before=#app.model.undo_stack
env.aim_x=20;env.aim_y=30;env.aim_z=5
local preview=assert(app.placement:start_stamp(wb_asset.id,{premise_id=premise.id,mode='aim',distance=12,stamp_spacing=0.75,align_surface=true}))
assert(preview.stroke_active and app.stamp_session:is_active() and app.dirty==false)
assert(#app.model.undo_stack==history_before and #app.model.data.objects==object_before)

local first=assert(app.placement:stamp_once(premise.id,nil));assert(app.placement:is_tracked(first))
assert(#app.model.undo_stack==history_before and app.dirty==false)
local blocked,spacing_err=app.placement:stamp_once(premise.id,nil);assert(not blocked and spacing_err:find('Move the preview',1,true))
env.aim_x=21;assert(app.placement:update_preview(true))
local second=assert(app.placement:stamp_once(premise.id,nil));assert(second.id~=first.id and app.placement:is_tracked(second))
local stroke=app.stamp_session:status();assert(stroke.active and stroke.count==2 and #stroke.created_ids==2)
assert(#app.model.undo_stack==history_before and app.dirty==false)
local save_ok,save_err=app:save(true);assert(not save_ok and save_err:find('stamp stroke',1,true))
local export_ok,export_err=app:export('json');assert(not export_ok and export_err:find('stamp stroke',1,true))
local denied,denied_err=app.bridge:handle({id='stamp-denied',op='create_volume',args={premise_id=premise.id}});assert(not denied and denied_err:find('stamp stroke',1,true))
local transform,transform_err=app.transform_session:start_placement({kind='asset',id=cet_asset.id,premise_id=premise.id,mode='aim'});assert(not transform and transform_err:find('stamp stroke',1,true))

local committed=assert(app.bridge:handle({id='stamp-commit',op='commit_stamp_stroke',args={}}))
assert(committed.committed and committed.count==2 and not app.stamp_session:is_active())
assert(#app.model.undo_stack==history_before+1 and app.dirty==true and app.selection:object_count()==2)
assert(app.placement:preview_status().active==false)
assert(app.actions:history('undo'));assert(#app.model.data.objects==object_before)
assert(app.actions:history('redo'));assert(#app.model.data.objects==object_before+2)

assert(app:save(true));app.selection:set('asset',cet_asset.id)
local cancel_count=#app.model.data.objects;history_before=#app.model.undo_stack
env.aim_x=24;assert(app.placement:start_stamp(cet_asset.id,{premise_id=premise.id,stamp_spacing=0.1}))
local cet_stamp=assert(app.placement:stamp_once(premise.id,nil));assert(app.placement:is_tracked(cet_stamp))
local clear,clear_err=app.placement:clear_preview();assert(not clear and clear_err:find('stamp stroke',1,true))
local cancelled=assert(app.bridge:handle({id='stamp-cancel',op='cancel_stamp_stroke',args={}}))
assert(cancelled.cancelled and cancelled.count==1 and #app.model.data.objects==cancel_count)
assert(#app.model.undo_stack==history_before and app.dirty==false and app.selection.kind=='asset' and app.selection.id==cet_asset.id)

app.selection:set('asset',wb_asset.id);env.aim_x=27
assert(app.placement:start_stamp(wb_asset.id,{premise_id=premise.id,stamp_spacing=0.1}));local guarded=assert(app.placement:stamp_once(premise.id,nil))
env.wb_remove_error=true
local refused,refused_err=app.stamp_session:cancel();assert(not refused and refused_err:find('retained the stroke',1,true));assert(app.stamp_session:is_active() and app.model:get_object(guarded.id))
env.wb_remove_error=false;assert(app.stamp_session:cancel());assert(not app.model:get_object(guarded.id))

app.selection:set('asset',cet_asset.id);env.aim_x=29
assert(app.placement:start_stamp(cet_asset.id,{premise_id=premise.id,stamp_spacing=0.1}));assert(app.placement:stamp_once(premise.id,nil))
events.onOverlayOpen();app.ui:draw_header()
for _,label in ipairs({'STAMP NOW##stroke_header','COMMIT STROKE##stroke_header','CANCEL STROKE##stroke_header'}) do assert(env.labels[label],label..' missing from stroke header') end
events.onOverlayClose();assert(not app.stamp_session:is_active() and #app.model.data.objects==cancel_count)

assert(app:save(true));local dirty_before=app.dirty
assert(app.placement:preview_asset(cet_asset.id,{mode='aim',follow=false}));assert(app.dirty==dirty_before,'temporary preview must not dirty the project');assert(app.placement:clear_preview())

local mcp=assert(io.open('mcp_server/server.py','r'));local mcp_text=mcp:read('*a');mcp:close()
for _,needle in ipairs({'def get_stamp_stroke_status','def commit_stamp_stroke','def cancel_stamp_stroke'}) do assert(mcp_text:find(needle,1,true),needle..' missing from MCP server') end
local log=assert(io.open('logs/locationstudio.log','r'));local text=log:read('*a');log:close()
for _,needle in ipairs({'[stamp:stroke] started','[stamp:stroke] stamped','[stamp:stroke] committed','[stamp:stroke] cancel_blocked','[stamp:stroke] cancelled'}) do assert(text:find(needle,1,true),needle..' missing from log') end

print('LocationStudio transactional Stamp Stroke: OK')
