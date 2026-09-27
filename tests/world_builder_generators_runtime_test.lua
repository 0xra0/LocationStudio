local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.58.0')
local premise=assert(app.model:add_premise({name='Generator Test'}))
local mesh=app.model:add_asset({name='Generator Mesh',kind='mesh',template='base\\environment\\architecture\\walls\\game_wall.mesh',size={x=1,y=1,z=1},metadata={
    asset_bounds={min={x=-1,y=-0.5,z=0},max={x=1,y=0.5,z=2},units='m'},
    world_builder={definition_key='mesh_static',category='Mesh',variant='Mesh',module_path='mesh/mesh',apply_scale=true,
        resource_name='game_wall',resource_path='base\\environment\\architecture\\walls\\game_wall.mesh',
        entry={name='base\\environment\\architecture\\walls\\game_wall.mesh',fileName='game_wall',data={spawnData='base\\environment\\architecture\\walls\\game_wall.mesh'}}},
}})
local points={{x=0,y=0,z=0},{x=5,y=0,z=0},{x=5,y=4,z=0}}
local cable=assert(app.bridge:handle({id='cable',op='wb_generate_cable',args={premise_id=premise.id,asset_id=mesh.id,points=points,segment_length=2,spawn=true}}))
assert(cable.generator=='cable' and cable.count==5 and #cable.spawned_ids==5)
local cable_first=assert(app.model:get_object(cable.object_ids[1]))
assert(cable_first.metadata.generator.generator=='cable' and math.abs(cable_first.size.x-(5/3/2))<0.001)
local fence=assert(app.bridge:handle({id='fence',op='wb_generate_fence',args={premise_id=premise.id,asset_id=mesh.id,points={{x=0,y=5,z=0},{x=4,y=5,z=0}},segment_length=2,spawn=false}}))
assert(fence.count==2 and #fence.spawned_ids==0)
local road=assert(app.bridge:handle({id='road',op='wb_generate_road',args={premise_id=premise.id,asset_id=mesh.id,points={{x=0,y=10,z=0},{x=10,y=10,z=0}},segment_length=5,width=8,height=0.2,spawn=true}}))
assert(road.count==2 and #road.spawned_ids==2)
local road_piece=assert(app.model:get_object(road.object_ids[1]))
assert(math.abs(road_piece.size.x-2.5)<0.001 and math.abs(road_piece.size.y-8)<0.001 and math.abs(road_piece.size.z-0.1)<0.001)
local market=assert(app.bridge:handle({id='market',op='wb_generate_market',args={premise_id=premise.id,asset_ids={mesh.id},origin={x=20,y=0,z=0},rows=2,columns=3,spacing_x=3,spacing_y=4,spawn=true}}))
assert(market.count==6 and #market.spawned_ids==6)
local marker=assert(app.bridge:handle({id='node-ref',op='wb_generate_noderef',args={node_ref='test.market.vendor.01',position={x=30,y=2,z=0}}}))
assert(marker.generator=='noderef' and marker.status=='authoring_only')
local loc=assert(app.model:get_location(marker.id));assert(loc.metadata.world_builder_node_ref=='test.market.vendor.01')
local duplicate,duplicate_err=app.bridge:handle({id='node-ref-duplicate',op='wb_generate_noderef',args={node_ref='test.market.vendor.01',position={x=30,y=2,z=0}}})
assert(not duplicate and duplicate_err:find('already exists',1,true))
local old_count=#app.model.data.objects;env.wb_enabled=false
local unavailable,unavailable_err=app.bridge:handle({id='unavailable',op='wb_generate_cable',args={premise_id=premise.id,asset_id=mesh.id,points={{x=0,y=0,z=0},{x=2,y=0,z=0}}}})
assert(not unavailable and unavailable_err:find('not ready',1,true) and #app.model.data.objects==old_count)
print('LocationStudio World Builder cable/fence/road/market/NodeRef generators: OK')
