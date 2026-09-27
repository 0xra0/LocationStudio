local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.72.0' and app.navigation)

local graph=assert(app.navigation:import_graph({name='Navigation test',source_format='test-json',source='test fixture',
    nodes={{id='a',name='Lobby',position={x=0,y=0,z=0}},{id='b',name='Landing',position={x=5,y=0,z=0}},{id='c',name='Upper floor',position={x=5,y=0,z=3}},{id='d',name='Disconnected',position={x=20,y=0,z=0}}},
    polygons={{id='floor',surface='walkable',vertices={{x=0,y=0,z=0},{x=1,y=0,z=0},{x=1,y=1,z=0}}}},
    edges={{id='door-1',from='a',to='b',kind='door'},{id='stairs-1',from='b',to='c',kind='stairs'},{id='service-link',from='c',to='b',kind='off_mesh',one_way=true}}}))
assert(graph.node_count==4 and graph.edge_count==3 and graph.polygon_count==1 and graph.native_redengine==false)
local stored=app.model.data.navigation_graphs[1]
local reachable=assert(app.navigation:query({graph_id=graph.id,start={x=0,y=0,z=0},goal={x=5,y=0,z=3}}))
assert(reachable.status=='reachable_in_imported_graph' and #reachable.path==3 and #reachable.transitions==2)
assert(reachable.transitions[1].kind=='door' and reachable.transitions[2].kind=='stairs')
local disconnected=assert(app.navigation:query({graph_id=graph.id,start={x=0,y=0,z=0},goal={x=20,y=0,z=0}}))
assert(disconnected.status=='unreachable_in_imported_graph')
local unmapped=assert(app.navigation:query({graph_id=graph.id,start={x=0,y=0,z=0},goal={x=100,y=0,z=0}}))
assert(unmapped.status=='unmapped')

local bad,bad_err=app.navigation:import_graph({nodes={{id='a',position={x=0,y=0,z=0}}},edges={{from='a',to='missing',kind='walk'}}})
assert(not bad and bad_err:find('references missing',1,true))
local badpoly,polyerr=app.navigation:import_graph({nodes={{id='a',position={x=0,y=0,z=0}}},edges={},polygons={{id='bad',vertices={{x=0,y=0,z=0},{x=1,y=0,z=0}}}}})
assert(not badpoly and polyerr:find('3 to 64',1,true))

local loc=app.model:add_location({id='workspot_test',name='Landing seat',type='workspot',transform={position={x=5,y=0,z=3}},metadata={workspot={kind='sit'}}})
assert(loc)
local report=assert(app.navigation:workspot_report({graph_id=graph.id,start={x=0,y=0,z=0}}))
assert(report.count==1 and report.workspots[1].status=='reachable_in_imported_graph' and not report.native_redengine)
local via_bridge=assert(app.bridge:handle({op='navigation_graph_list',args={}}))
assert(#via_bridge.graphs==1 and via_bridge.native_redengine_query==false)
local via_check=assert(app.bridge:handle({op='navigation_graph_check',args={graph_id=graph.id,start={x=0,y=0,z=0},goal={x=20,y=0,z=0}}}))
assert(via_check.status=='unreachable_in_imported_graph')
local supplemented=assert(app.live_tools:walkability_check({navigation_graph_id=graph.id,start={x=0,y=0,z=0},goal={x=5,y=0,z=3}}))
assert(supplemented.status=='reachable_in_imported_graph' and supplemented.native_redengine==false)

app.ui.spatial.nav_graph_id=graph.id
app.ui.spatial:draw_navigation()
assert(env.labels['CHECK WORKSPOTS FROM PLAYER'])
print('LocationStudio imported navigation graphs, transitions, graph path checks and workspot reporting: OK')
