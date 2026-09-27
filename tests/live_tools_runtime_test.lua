local root=... or '.'
-- Minimal CET/game doubles: one NPC at the origin, a floor at z 0 and a box whose top is at z 1
-- for x > 5, a workspot system that records calls, and an entity spawner that resolves on the next tick.
local function V(x,y,z) return {x=x,y=y,z=z,w=1} end
Vector4={new=V,Distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2) end}
EulerAngles={new=function(r,p,y) return {roll=r,pitch=p,yaw=y} end}
CName={new=function(s) return s end}
TDBID={ToStringDEBUG=function() return 'Character.test_npc' end}
TweakDBID={new=function(s) return s end}
EulerAngles.ToQuat=function(e) return e end
local spec_made
DynamicEntitySpec={new=function() spec_made={};return spec_made end}
local deleted_tag
local calls={}
local npc={}
function npc:IsNPC() return true end
function npc:GetEntityID() return {hash=42} end
function npc:GetRecordID() return 1 end
function npc:GetWorldPosition() return V(0,0,0) end
function npc:GetWorldOrientation() return {ToEulerAngles=function() return {yaw=30} end} end
function npc:GetWorldTransform() return {SetPosition=function() end,SetOrientationEuler=function(_,e) calls.device_yaw=e.yaw end} end
local device={}
local spawned=false
exEntitySpawner={Spawn=function(ent) calls.spawned=ent;return 7 end,Despawn=function(e) calls.despawned=e;return true end}
local camera={pitchMin=-80,pitchMax=80}
local player={GetWorldPosition=function() return V(0,0,0) end,GetFPPCameraComponent=function() return camera end}
Game={
    GetPlayer=function() return player end,
    FindEntityByID=function(id) if id==7 and spawned then return device end;if type(id)=='table' and id.hash==99 then return npc end end,
    GetTargetingSystem=function() return {
        GetLookAtObject=function() return npc end,
        GetTargetParts=function() return true,{{GetComponent=function() return {GetEntity=function() return npc end} end}} end} end,
    ['TSQ_NPC;']=function() return {} end,
    GetDynamicEntitySystem=function() return {CreateEntity=function() return {hash=99} end,GetTagged=function() return {npc} end,DeleteTagged=function(_,t) deleted_tag=t end} end,
    GetWorkspotSystem=function() return {
        PlayInDeviceSimple=function(_,d,n,_,comp) calls.play={device=d,npc=n,comp=comp} end,
        SendJumpToAnimEnt=function(_,n,name) calls.jump=name end,
        StopInDevice=function(_,n) calls.stopped=n end} end,
    GetSpatialQueriesSystem=function() return {SyncRaycastByCollisionGroup=function(_,from,to,group)
        if group~='Static' then return false end
        local top=from.x>5 and 1 or 0
        if from.z<top then return true,{position=V(from.x,from.y,from.z)} end
        if to.z<=top then return true,{position=V(from.x,from.y,top)} end
        return false end} end,
}

local Live=assert(loadfile(root..'/modules/live_tools.lua'))()
local lt=Live.new({})

local anim={name='stand__lh_tablet__01',comp='amm_workspot_base',ent='base\\amm_workspots\\entity\\workspot_anim.ent'}
assert(not lt:play({}),'play without anim must fail')
local res=assert(lt:play({anim=anim}))
assert(res.key=='42' and res.state=='pending','play should return the NPC key and pending')
assert(calls.spawned==anim.ent and calls.device_yaw==210,'device must be spawned on the NPC turned 180')
lt:update(0.1)
assert(lt:status().animations[1].state=='pending','must stay pending until the device resolves')
spawned=true;lt:update(0.1)
assert(calls.play.device==device and calls.play.npc==npc and calls.play.comp==anim.comp,'workspot must play in the device')
assert(calls.jump==anim.name and lt:status().animations[1].state=='playing','animation must be jumped to and playing')
local near=assert(lt:find_npc({target='nearest',position={x=1,y=0,z=0},radius=3}))
assert(near==npc,'nearest NPC lookup failed')
assert(lt:find_npc({key='42'})==npc,'an animated NPC resolves by key')
assert(lt:find_npc({key='nope'})==nil,'unknown key must fail')
assert(not lt:find_npc({target='nearest',position={x=10,y=0,z=0},radius=3}),'radius must be enforced')
assert(lt:stop({key='42'}).stopped==anim.name and calls.stopped==npc and calls.despawned==device,'stop must release the workspot and device')
assert(#lt:status().animations==0,'stopped animation must be forgotten')

assert(lt:find_npc({key='42'})==npc,'a not-yet-animated NPC must resolve by key from the nearby search')
spawned=false
assert(lt:play({anim=anim}));lt:update(6)
assert(lt:status().animations[1].state=='failed','an unresolved device must time out')
assert(lt:stop_all().stopped==1)

local fp=assert(lt:floor_probe({points={{x=0,y=0},{x=6,y=0}},z_from=0.5,z_to=-1}))
assert(fp.points[1].floor_z==0 and not fp.points[1].inside_solid,'floor under an open spot')
assert(fp.points[2].inside_solid,'a ray starting inside the box must be flagged')
local rb=assert(lt:raycast_batch({rays={{from={x=0,y=0,z=2},to={x=0,y=0,z=-1}}}}))
assert(rb.hits[1].hit and rb.hits[1].z==0 and math.abs(rb.hits[1].distance-2)<1e-9,'batch ray hit')

assert(lt:camera_pitch({pitch=-12}).pitchMin==-12 and camera.pitchMax==-12)
assert(lt:camera_pitch({restore=true}).pitchMax>79)
assert(not lt:spawn_record({}),'record is required')
local sp=assert(lt:spawn_record({record='Character.ashcache_mara',position={x=1,y=2,z=3},yaw=90,tag='aud'}))
assert(sp.key=='99' and spec_made.recordID=='Character.ashcache_mara' and spec_made.tags[1]=='aud' and spec_made.orientation.yaw==90,'spawn spec')
local preview=assert(lt:preview_workspot({record='Character.ashcache_mara',position={x=2,y=0,z=0},anim=anim,tag='preview'}))
assert(preview.state=='spawning' and preview.position.x==2,'preview must spawn at saved workspot position')
lt:update(0.1);assert(#lt.preview_pending==0 and lt:status().animations[1].state=='pending','preview should start on the spawned NPC and wait for its workspot device')
local approach=assert(lt:workspot_approach({position={x=0,y=0,z=0},target='crosshair'}))
assert(approach.status=='candidate' and approach.method=='collision_rays' and approach.caveat:find('navmesh',1,true),'approach result must report its limits')
lt.app.model={get_location=function(_,id) if id=='saved' then return {transform={position={x=3,y=4,z=0},rotation={yaw=20}},metadata={workspot={record='Character.saved',animation=anim}}} end end}
local saved_preview=assert(lt:preview_workspot({location_id='saved'}))
assert(saved_preview.position.x==3 and saved_preview.position.y==4,'MCP preview must resolve unsaved live project data by location id')
local saved_approach=assert(lt:workspot_approach({location_id='saved',target='crosshair'}))
assert(saved_approach.distance>0,'approach check must resolve the live saved workspot point')
spawned=true;assert(lt:play({anim=anim}));lt:update(0.1)
assert(lt:despawn_tag({tag='aud'}).deleted=='aud' and deleted_tag=='aud' and #lt:status().animations==0,'despawn must stop the NPC animation and delete the tag')
print('live_tools_runtime_test: OK')
