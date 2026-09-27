local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.58.0')
local premise=assert(app.actions:create_premise_from_player('Array Types Test','exterior'))
local path='base\\array_types.mesh'
local meta={world_builder={definition_key='mesh_static',module_path='mesh/mesh',category='Mesh',variant='Static Mesh',resource_path=path,resource_name='array_types',entry={name=path,fileName='array_types',data={spawnData=path}}}}
local source=assert(app.builder:place_object({premise_id=premise.id,name='Array Source',kind='mesh',template=path,size={x=1,y=1,z=1},transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=25}},metadata=meta}))
assert(app.placement:spawn(source));assert(app:save(true));app.selection:set('object',source.id)

local before=#app.model.data.objects;local undo=#app.model.undo_stack
local path_result=assert(app.bridge:handle({id='path-array',op='wb_path_array',args={ids={source.id},count=2,path_points={{x=0,y=0,z=0},{x=10,y=0,z=0}},spawn=true}}))
assert(path_result.committed and path_result.operation=='path_array' and #path_result.created_ids==2)
local p1=assert(app.model:get_object(path_result.created_ids[1]));local p2=assert(app.model:get_object(path_result.created_ids[2]))
assert(math.abs(p1.transform.position.x-10/3)<0.001 and math.abs(p2.transform.position.x-20/3)<0.001)
assert(p1.transform.rotation.yaw==0 and app.placement:is_tracked(p1))
assert(#app.model.data.objects==before+2 and #app.model.undo_stack==undo+1)
assert(app.actions:history('undo'));assert(#app.model.data.objects==before)

local radial=assert(app.bridge:handle({id='radial-array',op='wb_radial_array',args={ids={source.id},center={x=20,y=30,z=5},radius=4,count=4,spawn=false}}))
assert(radial.operation=='radial_array' and #radial.created_ids==4)
local r1=assert(app.model:get_object(radial.created_ids[1]));local r2=assert(app.model:get_object(radial.created_ids[2]))
assert(math.abs(r1.transform.position.x-24)<0.001 and math.abs(r1.transform.position.y-30)<0.001)
assert(math.abs(r2.transform.position.x-20)<0.001 and math.abs(r2.transform.position.y-34)<0.001)
assert(r1.transform.rotation.yaw==25 and not app.placement:is_tracked(r1))
assert(app.actions:history('undo'))

local grid=assert(app.bridge:handle({id='grid-array',op='wb_grid',args={ids={source.id},origin={x=20,y=30,z=5},rows=2,columns=2,spacing_x=2,spacing_y=3,yaw=90,spawn=false}}))
assert(grid.operation=='grid' and #grid.created_ids==4)
local g1=assert(app.model:get_object(grid.created_ids[1]));local g2=assert(app.model:get_object(grid.created_ids[2]));local g3=assert(app.model:get_object(grid.created_ids[3]))
assert(math.abs(g1.transform.position.x-20)<0.001 and math.abs(g1.transform.position.y-30)<0.001)
assert(math.abs(g2.transform.position.x-20)<0.001 and math.abs(g2.transform.position.y-32)<0.001)
assert(math.abs(g3.transform.position.x-17)<0.001 and math.abs(g3.transform.position.y-30)<0.001)
assert(app.actions:history('undo'))

local invalid,invalid_err=app.bridge:handle({id='bad-path',op='wb_path_array',args={ids={source.id},count=2,path_points={{x=1,y=1,z=0},{x=1,y=1,z=0}}}})
assert(not invalid and invalid_err and invalid_err:find('repeated',1,true));assert(#app.model.data.objects==before)
local large,large_err=app.bridge:handle({id='large-grid',op='wb_grid',args={ids={source.id},origin={x=0,y=0,z=0},rows=11,columns=10}})
assert(not large and large_err and large_err:find('100 copies',1,true));assert(#app.model.data.objects==before)

local a=assert(app.builder:place_object({premise_id=premise.id,name='Align A',kind='prop',template='base\\align_a.ent',transform={position={x=0,y=2,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local b=assert(app.builder:place_object({premise_id=premise.id,name='Align B',kind='prop',template='base\\align_b.ent',transform={position={x=2,y=4,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local c=assert(app.builder:place_object({premise_id=premise.id,name='Align C',kind='prop',template='base\\align_c.ent',transform={position={x=8,y=8,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}}))
local aligned=assert(app.bridge:handle({id='alias-align',op='wb_align',args={ids={a.id,b.id,c.id},axis='y',mode='min'}}))
assert(aligned.operation=='align' and a.transform.position.y==2 and b.transform.position.y==2 and c.transform.position.y==2)
local distributed=assert(app.bridge:handle({id='alias-distribute',op='wb_distribute',args={ids={a.id,b.id,c.id},axis='x'}}))
assert(distributed.operation=='distribute' and a.transform.position.x==0 and b.transform.position.x==4 and c.transform.position.x==8)
print('LocationStudio Array Types and Layout Aliases: OK')
