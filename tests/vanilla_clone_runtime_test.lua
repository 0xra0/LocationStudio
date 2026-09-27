local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local V=assert(app.vanilla_clone,'vanilla clone importer must be constructed')
local model=app.model

-- World Builder catalog: meshes and templates known; one mesh is missing.
local known={['base\\clinic\\bed.mesh']=true,['base\\clinic\\decal_blood.mi']=true,['base\\clinic\\monitor.ent']=true}
function app.world_builder:prepare_favorite_record(record,name)
    if not known[record.spawn_data] then return nil,'Not found in the loaded World Builder catalog: '..tostring(record.spawn_data) end
    return {name=name,data={spawnable={spawnData=record.spawn_data,modulePath=record.variant,app='default'}}}
end

-- RedHotTools: describe() data is camelCase.
local hidden={}
local crosshair_targets={
    {nodeID='1001',nodeRef='$/clinic/#bed',nodeType='worldMeshNode',isNode=true,sectorPath='base\\worlds\\clinic_1.streamingsector',nodeIndex=4,instanceIndex=0,
     debugName='[Mesh] clinic_bed_a',meshPath='base\\clinic\\bed.mesh',meshAppearance='dirty',position={x=10,y=20,z=30},distance=2},
    {nodeID='1002',nodeType='worldStaticLightNode',isNode=true,position={x=10,y=20,z=31},distance=3},
}
local scan_targets={
    crosshair_targets[1],
    {nodeID='1003',nodeType='worldStaticDecalNode',isNode=true,sectorPath='base\\worlds\\clinic_1.streamingsector',nodeIndex=7,materialPath='base\\clinic\\decal_blood.mi',position={x=11,y=20,z=30}},
    {entityID='77',isEntity=true,templatePath='base\\clinic\\monitor.ent',appearanceName='monitor_on',position={x=12,y=21,z=31},rotation={roll=0,pitch=0,yaw=90}},
    {nodeID='1004',nodeType='worldMeshNode',isNode=true,meshPath='base\\clinic\\missing.mesh',position={x=13,y=20,z=30},rotation={roll=0,pitch=0,yaw=0}},
    {nodeID='1005',nodeType='worldFoliageNode',isNode=true,position={x=14,y=20,z=30}},
}
app.rht_inspector={
    status=function() return {ready=true,plugin=true} end,
    crosshair=function() return {targets=crosshair_targets} end,
    scan=function(_,args) return {targets=scan_targets,radius=args.radius,note='frustum'} end,
    removal_target=function(_,args) local t={nodeInstance={},is_visible_node=true,id=args.node_id};return {node_id=args.node_id},t end,
    toggle_node=function(_,t) hidden[t.id]=not hidden[t.id];return true end,
}

-- Crosshair pick stages the nearest cloneable node.
local picked=assert(V:pick_crosshair({}))
assert(picked.count==1 and picked.items[1].definition_key=='mesh_static' and picked.items[1].appearance=='dirty')
assert(picked.items[1].confidence=='position_only' and picked.items[1].name=='clinic_bed_a')
assert(assert(V:pick_crosshair({all=true,append=true})).count==2,'the light is staged too, deduped bed')
local light=V:candidates().items[2];assert(not light.supported and light.reason:find('lighting tools',1,true))
assert(not V:set_selected(2,true),'unsupported candidates cannot be selected')

-- Position-only picks need explicit approval.
local ok,err=V:import({})
assert(not ok and err:find('allow_approximate',1,true))

-- Area scan.
local scan=assert(V:scan({radius=8}))
assert(scan.count==5 and scan.supported==4,'bed, decal, monitor, and a mesh missing from the catalog (fails at import)')
local rows={};for _,r in ipairs(scan.items) do rows[r.resource_path or r.node_type]=r end
assert(rows['base\\clinic\\monitor.ent'].confidence=='exact' and rows['base\\clinic\\monitor.ent'].definition_key=='entity_template')
assert(not rows.worldFoliageNode.supported)
local history=#model.undo_stack
local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
history=#model.undo_stack
local res=assert(V:import({allow_approximate=true,hide_originals=true,group_name='Clinic set'}))
assert(res.imported==3 and #res.skipped==1 and res.skipped[1].reason:find('Not found',1,true))
assert(#model.undo_stack==history+1,'one undo step')
assert(res.hidden==2 and #res.hide_errors==1,'nodes hidden; the entity has no node id')
assert(hidden['1001'] and hidden['1003'] and res.group_id and res.approximate==2)
local bed=model:get_object(res.object_ids[1])
assert(bed.metadata.world_builder.definition_key=='mesh_static' and bed.metadata.world_builder.resource_path=='base\\clinic\\bed.mesh')
assert(bed.metadata.world_builder.entry.data.app=='dirty' and bed.metadata.world_builder.apply_scale==true)
assert(bed.transform.position.x==10 and bed.metadata.vanilla_source.node_ref=='$/clinic/#bed' and bed.metadata.vanilla_source.removal_id)
local monitor;for _,id in ipairs(res.object_ids) do local o=model:get_object(id);if o.metadata.vanilla_source.entity_id=='77' then monitor=o end end
assert(monitor.transform.rotation.yaw==90 and monitor.metadata.world_builder.entry.data.app=='monitor_on')
assert(app.selection:object_count()==3)

-- Already cloned candidates are refused unless allowed.
V:set_selected(1,true)
ok,err=V:import({indices={1},allow_approximate=true});assert(not ok and err:find('already cloned',1,true))

-- Offline sector candidates carry exact rotation/scale and a CET fallback for unknown templates.
local offline=assert(V:import({candidates={
    {node_type='worldMeshNode',sector_path='clinic_1',node_index=9,instance_index=0,node_id='2001',mesh_path='base\\clinic\\bed.mesh',mesh_appearance='clean',
     position={x=1,y=2,z=3},rotation={roll=0,pitch=0,yaw=45},scale={x=2,y=2,z=1},source_kind='sector_json'},
    {node_type='worldEntityNode',node_index=10,template_path='base\\clinic\\door_custom.ent',appearance='closed',position={x=4,y=5,z=6},rotation={roll=0,pitch=0,yaw=180},scale={x=1,y=1,z=1}},
}}))
assert(offline.imported==2 and offline.approximate==0)
local exact=model:get_object(offline.object_ids[1]);assert(exact.size.x==2 and exact.transform.rotation.yaw==45 and exact.metadata.vanilla_source.confidence=='exact')
local door=model:get_object(offline.object_ids[2]);assert(door.template=='base\\clinic\\door_custom.ent' and door.appearance=='closed' and not door.metadata.world_builder,'CET template fallback')

-- List reports edits since import.
bed.transform.position.x=10.5
local listed=assert(V:list({}));local brow;for _,r in ipairs(listed.items) do if r.id==bed.id then brow=r end end
assert(listed.count==5 and brow.modified and brow.changes[1]=='position' and brow.original_hidden)

-- Revert shows the original and deletes the clone.
local rev=assert(V:revert(bed.id,{}));assert(rev.restored and rev.deleted and not hidden['1001'] and not model:get_object(bed.id))
assert(not V:revert('missing'))

local count=#model.data.objects

-- Bridge.
assert(assert(app.bridge:handle({id='v1',op='vanilla_clone_status',args={}})).rht.ready)
assert(assert(app.bridge:handle({id='v2',op='vanilla_clone_scan',args={radius=5}})).count==5)
assert(assert(app.bridge:handle({id='v3',op='vanilla_clone_select',args={index='none'}})).selected==0)
assert(assert(app.bridge:handle({id='v4',op='vanilla_clone_stage',args={candidates={{node_type='worldMeshNode',mesh_path='base\\clinic\\bed.mesh',position={x=0,y=0,z=0},rotation={roll=0,pitch=0,yaw=0}}}}})).count==1)
assert(assert(app.bridge:handle({id='v5',op='vanilla_clone_import',args={}})).imported==1)
assert(#model.data.objects==count+1)
assert(assert(app.bridge:handle({id='v6',op='vanilla_clone_list',args={}})).count==5)
assert(assert(app.bridge:handle({id='v7',op='vanilla_clone_clear',args={}})).cleared)

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['SCAN AREA##vc']=true;env:draw()
assert(V:candidates().count==5)
app.ui.spatial.vc_approx=true;app.ui.spatial.vc_hide=false
V:set_selected('none');assert(V:candidates().items[2].already_cloned,'the decal is still cloned');V:set_selected(1,true)
env.clicks['IMPORT SELECTED']=true;env:draw()
assert(#model.data.objects==count+2,'UI re-imported the reverted bed')
print('vanilla_clone_runtime_test: OK')
