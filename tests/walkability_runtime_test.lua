local root=... or '.'
local function V(x,y,z) return {x=x,y=y,z=z,w=1} end
Vector4={new=V,Distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end}
local wall=false
local npc={}
function npc:IsNPC() return true end
function npc:GetEntityID() return {hash=812} end
function npc:GetWorldPosition() return V(0,0,0) end
function npc:GetWorldOrientation() return {ToEulerAngles=function() return {yaw=0} end} end
local player={GetWorldPosition=function() return V(0,0,0) end}
Game={
    GetPlayer=function() return player end,
    GetTargetingSystem=function() return {GetLookAtObject=function() return npc end} end,
    GetSpatialQueriesSystem=function() return {SyncRaycastByCollisionGroup=function(_,from,to,group)
        if to.z<from.z then
            if group=='Static' and to.z<=0 then return true,{position=V(from.x,from.y,0)} end
            return false
        end
        if wall and group=='Dynamic' and from.x>=1.4 and from.x<=2.6 and math.abs(from.y)<=2.2 then
            return true,{position=V(from.x,from.y,0.8)}
        end
        return false
    end} end,
}
local Live=assert(loadfile(root..'/modules/live_tools.lua'))()
local lt=Live.new({})
local result=assert(lt:walkability_check({goal={x=4,y=0,z=0},actor='player',grid_step=1,margin=1}))
assert(result.status=='candidate' and result.geometric_path_candidate and result.path_cells==5,'clear floor should yield a sampled route')
assert(result.navmesh_available==false and result.navmesh_status:find('does not expose',1,true),'must not claim engine navmesh access')
local npc_route=assert(lt:walkability_check({goal={x=3,y=0,z=0},actor='npc',grid_step=1,margin=1}))
assert(npc_route.status=='candidate' and npc_route.actor_key=='812','NPC start must use its live transform')
local explicit=assert(lt:walkability_check({start={x=0,y=0,z=0},goal={x=3,y=0,z=0},actor='npc',grid_step=1,margin=1}))
assert(explicit.status=='candidate' and explicit.actor_key==nil,'explicit NPC-design route should not need a live NPC handle')
wall=true
local blocked=assert(lt:walkability_check({goal={x=4,y=0,z=0},actor='player',grid_step=1,margin=1}))
assert(blocked.status=='no_route_in_sampled_grid' and not blocked.geometric_path_candidate,'a full blocked corridor should have no route')
assert(blocked.blocker_count>0 and #blocked.blockers>0 and blocked.blockers[1].group=='Dynamic','dynamic prop hits should be reported as blocker positions: '..tostring(blocked.blocker_count)..'/'..tostring(#blocked.blockers)..'/'..tostring(blocked.blockers[1] and blocked.blockers[1].group))
local capped=assert(lt:walkability_check({goal={x=30,y=0,z=0},grid_step=0.5,margin=6}))
assert(capped.status=='inconclusive' and capped.cells>180,'oversized scan must stop with an explicit inconclusive result')
print('walkability_runtime_test: OK')
