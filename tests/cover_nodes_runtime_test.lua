local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.63.0')
Vector4.Distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end
local premise=assert(app.actions:create_premise_from_player('Cover Test Premise','interior'))
Game.GetSpatialQueriesSystem=function()
    return {SyncRaycastByCollisionGroup=function(_,from,to,group)
        if group~='Static' and group~='Dynamic' then return false end
        if math.abs(to.z-from.z)<0.001 and to.x>from.x and from.x<=2 and to.x>=2 then
            local t=(2-from.x)/(to.x-from.x);local y=from.y+(to.y-from.y)*t
            if math.abs(y)<=2 then return true,{position={x=2,y=y,z=from.z,w=1}} end
        end
        return false
    end}
end

local scan=assert(app.live_tools:scan_cover_candidates({center={x=0,y=0,z=0},radius=4,samples=24,spacing=0.5}))
assert(scan.candidate_count>=1 and scan.candidates[1].source=='live_collision_scan')
assert(scan.candidates[1].transform.rotation.yaw~=nil and scan.navmesh_available==false)
assert(scan.caveat:find('does not query',1,true))

local node=assert(app.actions:create_cover_node({premise_id=premise.id,name='Manual crouch',cover_type='crouch',exposure='low',spacing=1.25,
    transform={position={x=1,y=2,z=0},rotation={yaw=90}}}))
assert(node.cover_type=='crouch' and node.exposure=='low' and node.spacing==1.25)
assert(app.selection.kind=='cover_node' and app.selection:resolve().id==node.id)
local bridge_list=assert(app.bridge:handle({op='cover_node_list',args={premise_id=premise.id}}))
assert(bridge_list.count==1 and bridge_list.cover_nodes[1].id==node.id)
local bridge_scan=assert(app.bridge:handle({op='cover_scan',args={center={x=0,y=0,z=0},radius=4,samples=24,spacing=0.5}}))
assert(bridge_scan.candidate_count>=1)
local moved=assert(app.authoring:batch_transform('cover_node',{node.id},1,0,0,15,false))
assert(moved[1].transform.position.x==2 and moved[1].transform.rotation.yaw==105)
assert(app.actions:update_cover_node({id=node.id,patch={cover_type='standing',exposure='medium',spacing=2}}).cover_type=='standing')
local invalid,invalid_err=app.actions:update_cover_node({id=node.id,patch={cover_type='prone'}})
assert(not invalid and invalid_err:find('cover_type',1,true))

local imported=assert(app.actions:scan_cover_candidates({center={x=0,y=0,z=0},radius=4,samples=24,spacing=0.5,premise_id=premise.id,save_to_project=true,cover_type='standing'}))
assert(imported.saved_count>=1 and imported.saved[1].source=='live_collision_scan')
local listed={};for _,value in ipairs(app.model.data.cover_nodes) do if value.premise_id==premise.id then listed[#listed+1]=value end end
assert(#listed>=2)
local report=app.model:validate();for _,issue in ipairs(report) do assert(issue.id~=node.id or issue.severity~='error',issue.message) end

app.ui.spatial.cover_selected_id=node.id;app.ui.spatial.cover_name=node.name;app.ui.spatial.cover_position={2,2,0};app.ui.spatial.cover_yaw=105
app.ui.spatial:draw_cover_nodes(premise)
assert(env.labels['PLACE AT PLAYER##cover'] and env.labels['PLACE AT AIM##cover'] and env.labels['SCAN AROUND PLAYER##cover'])
assert(env.labels['ADD SCAN CANDIDATES TO PROJECT##cover'] or app.ui.spatial.cover_nodes_scan==nil)
local canvas=app.ui.viewport:draw_canvas(premise)
assert(env.labels['[C]  '..node.name..'##safe_view_cover_node_cover_node_'..node.id] or env.labels['[C]  '..node.name..'##safe_view_cover_node_'..node.id])

local out='exports/test_cover_nodes_handoff.json'
assert(app.storage:export_questforge(app.model,out))
local data=assert(json.decode(assert(app.util.read_file(out))))
assert(#data.cover_nodes>=2 and data.cover_nodes[1].posture~=nil and data.cover_nodes[1].yaw~=nil)
assert(app.actions:delete_cover_node(node.id).deleted)
local cascade_premise=assert(app.actions:create_premise_from_player('Cover Delete Cascade','interior'))
assert(app.actions:create_cover_node({premise_id=cascade_premise.id,transform={position={x=0,y=0,z=0},rotation={yaw=0}}}))
local before_cascade=#app.model.data.cover_nodes
assert(app.model:delete_premise(cascade_premise.id) and #app.model.data.cover_nodes==before_cascade-1)
print('LocationStudio persistent cover nodes, scan, editor and Quest Forge handoff: OK')
