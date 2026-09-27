local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local R=assert(app.reference_areas,'reference areas must be constructed')
local model=app.model
assert(model.data.schema_version==20 and type(model.data.reference_areas)=='table')

local known={['base\\clinic\\bed.mesh']=true,['base\\clinic\\cabinet.mesh']=true,['base\\clinic\\monitor.ent']=true}
function app.world_builder:prepare_favorite_record(record,name)
    if not known[record.spawn_data] then return nil,'Not found in the loaded World Builder catalog: '..tostring(record.spawn_data) end
    return {name=name,data={spawnable={spawnData=record.spawn_data,modulePath=record.variant,app='default'}}}
end
local scan_args
local targets={
    {nodeID='1',nodeType='worldMeshNode',isNode=true,sectorPath='clinic_1',nodeIndex=1,meshPath='base\\clinic\\bed.mesh',meshAppearance='dirty',position={x=12,y=22,z=30},rotation={roll=0,pitch=0,yaw=90}},
    {nodeID='2',nodeType='worldMeshNode',isNode=true,sectorPath='clinic_1',nodeIndex=2,meshPath='base\\clinic\\cabinet.mesh',position={x=14,y=24,z=30},rotation={roll=0,pitch=0,yaw=0}},
    {nodeID='3',nodeType='worldMeshNode',isNode=true,meshPath='base\\clinic\\cabinet.mesh',position={x=13,y=21,z=30}},
    {nodeID='4',nodeType='worldStaticLightNode',isNode=true,position={x=13,y=23,z=32}},
    {nodeID='5',nodeType='worldMeshNode',isNode=true,meshPath='base\\clinic\\bed.mesh',position={x=40,y=40,z=30},rotation={roll=0,pitch=0,yaw=0}},
}
app.rht_inspector={status=function() return {ready=true} end,scan=function(_,a) scan_args=a;return {targets=targets} end,crosshair=function() return {targets={}} end}

-- Box selection.
assert(not R:capture({name='x'}),'no box yet')
assert(R:set_corner('a',{position={x=10,y=20,z=29}}))
assert(not R:set_corner('c',{}))
local st=assert(R:set_corner('b',{position={x=16,y=26,z=33}}))
assert(st.ready and st.size.x==6)
local room=model:add_room({name='Ward',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=90}},size={width=4,depth=2,height=3}})
local rb=assert(R:box_from_room(room.id,0)).bounds
assert(math.abs(rb.max.x-1)<1e-6 and math.abs(rb.max.y-2)<1e-6 and rb.max.z==3,'rotated room fits an AABB')
assert(R:set_corner('a',{position={x=10,y=20,z=29}}) and R:set_corner('b',{position={x=16,y=26,z=33}}))
assert(not R:capture({name='huge',min={0,0,0},max={500,1,1}}),'oversized boxes are refused')

local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id

-- Live capture: position-only node skipped by default; light recorded as a marker; outside node ignored.
local history=#model.undo_stack
local cap=assert(R:capture({name='Original clinic'}))
assert(#model.undo_stack==history+1,'one undo step')
assert(scan_args.center.x==13 and scan_args.radius>5)
assert(cap.captured==2 and cap.unsupported==1 and cap.skipped==1 and cap.approximate==0)
local area=R:get(cap.area.id)
assert(area.unsupported[1].node_type=='worldStaticLightNode' and area.skipped[1].reason:find('allow_approximate',1,true))
local layer=app.layers:get(cap.layer_id)
assert(layer.reference==area.id and layer.locked and layer.export==false and layer.visible==false)
local refs=R:objects(area.id);assert(#refs==2)
for _,o in ipairs(refs) do assert(o.locked and o.layer==cap.layer_id and o.name:find('^%[REF%]') and not app.placement:is_tracked(o)) end

-- Read-only: layer operations are refused.
assert(not app.layers:set_locked(cap.layer_id,false))
assert(not app.layers:update(cap.layer_id,{export=true}))
assert(not app.layers:delete(cap.layer_id,'decoration'))
assert(not app.layers:delete('lighting',cap.layer_id),'cannot move objects onto a reference layer')
assert(not app.layers:assign({refs[1].id},'decoration'),'reference items are locked')
assert(not R:capture({name='original clinic'}),'duplicate names are refused')

-- Reference items are not clones, not exported, not in performance counts.
assert(app.vanilla_clone:list({}).count==0)
assert(app.performance:analyze({}).analyzed_objects==0,'reference items are left out of performance estimates')
local scoped=app.build_export:_objects({})
for _,o in ipairs(scoped) do assert(not o.metadata.reference_area_id,'reference items never export') end

-- Show/hide.
local shown=assert(R:show(area.id,true));assert(shown.spawned==2 and app.placement:is_tracked(refs[1]))
assert(R:list({}).items[1].shown and R:list({}).items[1].live==2)
local hidden=assert(R:show(area.id,false));assert(hidden.despawned==2)

-- Rebuild: copy to editable, then modify and compare.
local copies=assert(R:copy_to_editable(area.id,{}))
assert(copies.copied==2)
local bed,cabinet
for _,id in ipairs(copies.object_ids) do local o=model:get_object(id);assert(not o.locked and o.layer=='decoration' and not o.metadata.reference_area_id and o.premise_id==premise.id)
    if o.name=='bed' then bed=o else cabinet=o end end
assert(bed and cabinet,'names lose the [REF] prefix')
bed.transform.position.x=bed.transform.position.x+1
cabinet.metadata.world_builder.entry.data.app='clean'
local extra=model:add_object({premise_id=premise.id,name='New desk',kind='prop',template='base\\desk.ent',transform={position={x=11,y=21,z=30,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},metadata={}})
local cmp=assert(R:compare(area.id,{}))
assert(cmp.counts.moved==1 and cmp.counts.changed==1 and cmp.counts.added==1 and cmp.counts.missing==0 and cmp.counts.not_captured==1,'compare '..json.encode(cmp.counts))
-- Removing the copy makes it missing; align snaps a hand-built object back.
assert(model:delete_object(cabinet.id))
cmp=assert(R:compare(area.id,{}));assert(cmp.counts.missing==1)
local ref_bed;for _,o in ipairs(R:objects(area.id)) do if o.name=='[REF] bed' then ref_bed=o end end
assert(not R:align(ref_bed.id,bed.id),'reference items cannot be moved')
local aligned=assert(R:align(bed.id,ref_bed.id,{}));assert(aligned.transform.position.x==12 and aligned.scaled)
cmp=assert(R:compare(area.id,{}));assert(cmp.counts.unchanged==1)

-- Offline capture: exact candidates, including a node the sector marks as not cloneable.
local off=assert(R:capture({name='Sector ref',min={x=0,y=0,z=0},max={x=5,y=5,z=5},candidates={
    {node_type='worldMeshNode',sector_path='clinic_1',node_index=5,instance_index=0,mesh_path='base\\clinic\\bed.mesh',position={x=1,y=1,z=1},rotation={roll=0,pitch=0,yaw=30},scale={x=1,y=2,z=1}},
    {node_type='worldInstancedMeshNode',node_index=6,mesh_path='base\\clinic\\tile.mesh',position={x=2,y=2,z=1},rotation={roll=0,pitch=0,yaw=0},cloneable=false,reason='instance buffer'},
    {node_type='worldMeshNode',node_index=7,mesh_path='base\\clinic\\bed.mesh',position={x=9,y=9,z=1},rotation={roll=0,pitch=0,yaw=0}},
}}))
assert(off.captured==1 and off.unsupported==1 and off.area.source=='sector_json' and off.area.sectors[1]=='clinic_1')
local oref=R:objects(off.area.id)[1];assert(oref.size.y==2 and oref.transform.rotation.yaw==30)

-- Delete removes items and layer; undo brings them back.
local del=assert(R:delete(off.area.id));assert(del.removed_items==1 and not app.layers:get(off.layer_id) and not R:get(off.area.id))
assert(model:undo() and R:get(off.area.id) and app.layers:get(off.layer_id))

-- Bridge.
assert(assert(app.bridge:handle({id='r1',op='reference_area_list',args={}})).count==2)
assert(#assert(app.bridge:handle({id='r2',op='reference_area_get',args={id=area.id}})).objects==2)
assert(assert(app.bridge:handle({id='r3',op='reference_area_box',args={corner='a',position={x=0,y=0,z=0}}})).a.x==0)
assert(assert(app.bridge:handle({id='r4',op='reference_area_compare',args={id=area.id}})).counts)
assert(assert(app.bridge:handle({id='r5',op='reference_area_show',args={id=area.id,visible=true}})).spawned==2)
assert(assert(app.bridge:handle({id='r6',op='reference_area_show',args={id=area.id,visible=false}})).despawned==2)

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['CORNER A AT V']=true;env:draw()
assert(R:box_status().a.x==10)
R:set_corner('b',{position={x=16,y=26,z=33}})
app.ui.spatial.ref_name='UI ref';app.ui.spatial.ref_approx=true
env.clicks['CAPTURE REFERENCE']=true;env:draw()
local ui_area=R:get(app.ui.spatial.ref_area_id);assert(ui_area and ui_area.item_count==3,'approximate node included')
env.clicks['SHOW REFERENCE##ref']=true;env:draw();assert(R:list({}).items[3].shown)
env.clicks['COMPARE##ref']=true;env:draw();assert(app.ui.spatial.ref_compare)
print('reference_areas_runtime_test: OK')
