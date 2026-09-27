local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local perf=assert(app.performance,'performance module must be constructed')
local model=app.model

local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local quiet=model:add_room({name='Storage',premise_id=premise.id,transform={position={x=-40,y=0,z=0},rotation={yaw=0}},size={width=6,depth=6,height=3}})
local busy=model:add_room({name='Lobby',premise_id=premise.id,transform={position={x=40,y=0,z=0},rotation={yaw=0}},size={width=10,depth=10,height=4}})
local function obj(room,key,x,y,extra)
    local md={world_builder={definition_key=key,entry={data={}}}}
    for k,v in pairs(extra or {}) do md[k]=v end
    return model:add_object({premise_id=premise.id,room_id=room and room.id,name=key..' '..x..','..y,kind='prop',template='',
        transform={position={x=x,y=y,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},metadata=md})
end
-- Quiet room: a few static meshes spread out.
for i=1,4 do obj(quiet,'mesh_static',-44+i*2,0) end
-- Busy room: a dense pile of lights, VFX, decals and cloth in one 5 m cell.
for i=1,6 do obj(busy,'light_static',41+i*0.3,1,{lighting={color={1,0.8,0.6},intensity=100,radius=20,flickerStrength=0.2,flickerPeriod=0.2,flickerOffset=0}}) end
for i=1,5 do obj(busy,'particle',42,1+i*0.2,{vfx={emission_rate=10}}) end
for i=1,4 do obj(busy,'decal',43,2+i*0.1) end
obj(busy,'mesh_cloth',44,3)
obj(busy,'audio',42,2)
local npc=model:add_object({premise_id=premise.id,room_id=busy.id,name='Guard',kind='entity',template='',transform={position={x=38,y=-3,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
    size={x=1,y=1,z=1},metadata={npc_population={record='Character.guard'},world_builder={definition_key='entity_record',entry={data={}}}}})
local cet=model:add_object({premise_id=premise.id,name='Loose crate',kind='prop',template='base\\crate.ent',transform={position={x=0,y=30,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1}})
obj(nil,'static_marker',0,31)

perf:set_budget('room',{lights=4,vfx=3})
local report=perf:analyze({premise_id=premise.id})
assert(report.analyzed_objects==24,'analyzed '..report.analyzed_objects)
assert(report.totals.lights==6 and report.totals.vfx==5 and report.totals.decals==4 and report.totals.audio==1)
assert(report.totals.dynamic==3,'cloth, NPC record and direct CET .ent entity are dynamic')
assert(report.totals.static==4 and report.totals.meta==1)
assert(report.totals.expensive>=12,'large flickering lights, high-emission particles, cloth and NPC are expensive')

local lobby,storage,loose
for _,room in ipairs(report.rooms) do if room.room_id==busy.id then lobby=room elseif room.room_id==quiet.id then storage=room elseif room.kind=='unassigned' then loose=room end end
assert(report.rooms[1]==lobby,'rooms are sorted by cost')
assert(lobby.counts.cost>storage.counts.cost*10)
assert(storage.counts.nodes==4 and #storage.over_budget==0)
local over={};for _,o in ipairs(lobby.over_budget) do over[o.metric]=o end
assert(over.lights and over.lights.value==6 and over.lights.limit==4 and over.vfx)
assert(loose and loose.counts.nodes==2 and loose.counts.dynamic==1)
local reasons={};for _,e in ipairs(lobby.expensive) do reasons[e.reason:match('^%a+')]=true end
assert(reasons.light and reasons.particle and reasons.cloth and reasons['NPC'])
assert(#report.warnings>=2)

-- Distance from V (mock player at 10,20,30).
assert(report.player_position and math.abs(lobby.distance_from_player-math.sqrt(30^2+20^2+30^2))<0.2)

-- Dense cluster: the lobby pile is flagged, the storage room is not.
assert(#report.clusters==1,'one dense cluster, got '..#report.clusters)
local cluster=report.clusters[1]
assert(cluster.center.x>40 and cluster.center.x<45 and cluster.counts.lights==6 and cluster.room_ids[1]==busy.id)
assert(cluster.top_contributors[1].cost>=8 and cluster.distance_from_player)
assert(report.cluster_stats.threshold>=40)

-- Overlapping lights.
assert(#report.light_overlaps==6 and report.light_overlaps[1].overlapping==5)

-- Select the cluster's objects.
local selected=assert(perf:select_cluster(1));assert(selected.selected>=16)
assert(app.selection:object_count()==selected.selected)
assert(not perf:select_cluster(9),'unknown cluster must fail')

-- Budgets validate.
assert(not perf:set_budget('room',{frames=1}) and not perf:set_budget('room',{lights=-1}))
assert(perf:set_budget('premise',{cost=100}).cost==100)
local premise_row=perf:analyze({premise_id=premise.id}).premises[1];assert(premise_row.over_budget[1] and premise_row.distance_from_player)

-- Whole project without a player: distances omitted.
env.offline=true
local offline=perf:analyze({});assert(offline.player_position==nil and offline.rooms[1].distance_from_player==nil)
env.offline=false
assert(perf:analyze({include_meta=false}).totals.meta==0)

-- Bridge.
assert(assert(app.bridge:handle({id='p1',op='performance_analyze',args={premise_id=premise.id}})).totals.lights==6)
assert(assert(app.bridge:handle({id='p2',op='performance_set_budget',args={scope='room',values={lights=10}}})).budget.lights==10)
assert(assert(app.bridge:handle({id='p3',op='performance_select_cluster',args={index=1}})).selected>=16)

-- UI tab, including exported-sector costs from a loaded sector report.
app.sector_inspector.report={schema='locationstudio-sector-inspection/1',export_name='demo',sector_count=1,node_count=10,device_count=0,ps_entry_count=0,flag_counts={},sectors={},flags={},likely_wrong_sector={},cross_sector_references={},performance={sectors={{name='demo_a',counts={nodes=10,lights=2,audio=0,decals=0,vfx=0,dynamic=1,expensive=0,cost=20},over_budget={},long_streaming_total=1}}}}
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.selected_premise_id=premise.id
env.clicks['ANALYZE STREAMING COST']=true;env:draw()
assert(app.ui.spatial.perf_report and app.ui.spatial.perf_report.totals.lights==6)
app.selection:clear()
env.clicks['SELECT##perfcluster_1']=true;env:draw()
assert(app.selection:object_count()>=16)
print('performance_runtime_test: OK')
