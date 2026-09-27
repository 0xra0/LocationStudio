local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.64.0')
local premise=assert(app.actions:create_premise_from_player('Collision Compat','exterior'))
local path='base\\collision_compat.mesh'
local wb={world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Mesh',resource_path=path,resource_name='collision_compat',entry={name=path,fileName='collision_compat',data={spawnData=path}}}}
local bounds={min={x=-0.5,y=-0.5,z=-0.5},max={x=0.5,y=0.5,z=0.5},units='m',source='collision-test'}
local function place(name,x,with_bounds)
    local metadata={world_builder=wb.world_builder}
    if with_bounds then metadata.asset_bounds=bounds end
    return assert(app.builder:place_object({premise_id=premise.id,name=name,kind='mesh',template=path,
        transform={position={x=x,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata=metadata}))
end
local a=place('Collision A',0,true);local b=place('Collision B',0.75,true);local unknown=place('No Bounds',10,false)
local scan=assert(app.bridge:handle({id='collision-scan',op='wb_collisions',args={premise_id=premise.id}}))
assert(scan.scope=='premise' and scan.selected==3 and scan.tested==2 and scan.skipped_count==1)
assert(scan.collision_count==1 and scan.collisions[1].a==a.id and scan.collisions[1].b==b.id)
assert(scan.collisions[1].approximate and scan.warning:find('does not query',1,true))
local selected=assert(app.bridge:handle({id='collision-selected',op='wb_collisions',args={object_ids={a.id,b.id},margin=0.2}}))
assert(selected.scope=='selection' and selected.collision_count==1 and selected.margin==0.2)
local insufficient,insufficient_err=app.bridge:handle({id='collision-invalid',op='wb_collisions',args={object_ids={a.id}}})
assert(not insufficient and insufficient_err:find('at least two',1,true))
local out_of_scope,out_of_scope_err=app.bridge:handle({id='collision-scope',op='wb_collisions',args={object_ids={a.id,b.id},premise_id='wrong'}})
assert(not out_of_scope and out_of_scope_err:find('outside the requested premise',1,true))

env.wb_enabled=false
local compat=assert(app.bridge:handle({id='compat-scan',op='wb_compat_scan',args={}}))
assert(compat.read_only and compat.project.objects==3 and compat.project.world_builder==3)
assert(compat.project.missing_bounds==1 and compat.loaded_integrations.WorldBuilder==false)
local has_wb_warning=false
for _,finding in ipairs(compat.findings) do if finding.code=='world_builder_not_loaded' then has_wb_warning=true end end
assert(has_wb_warning and #compat.limits>=2)
env.wb_enabled=true
local live=assert(app.bridge:handle({id='compat-scan-live',op='wb_compat_scan',args={}}))
assert(live.loaded_integrations.WorldBuilder==true)
print('LocationStudio Collision and Compatibility Scan: OK')
