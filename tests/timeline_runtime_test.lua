local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local T=assert(app.timeline,'timeline editor must be constructed')
local model=app.model

local teleports={}
local real_teleport=app.game.teleport
app.game.teleport=function(self,transform) teleports[#teleports+1]=transform;return real_teleport(self,transform) end
local anims={played={},stopped={}}
app.live_tools.play=function(_,a) anims.played[#anims.played+1]=a;return {key=a.key,anim=a.anim.name} end
app.live_tools.stop=function(_,a) anims.stopped[#anims.stopped+1]=a.key;return {key=a.key} end

local premise=model:add_premise({name='Bar',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
local cam_a=model:add_camera({premise_id=premise.id,name='Wide',transform={position={x=0,y=0,z=2,w=1},rotation={roll=0,pitch=0,yaw=0}}})
local cam_b=model:add_camera({premise_id=premise.id,name='Close',transform={position={x=10,y=0,z=2,w=1},rotation={roll=0,pitch=0,yaw=90}}})
local lamp=model:add_object({premise_id=premise.id,name='Neon',kind='prop',layer='lighting',template='base\\neon.ent',
    transform={position={x=1,y=1,z=1,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},metadata={}})
local npc=model:add_object({premise_id=premise.id,name='Bartender',kind='npc',template='',transform={position={x=3,y=3,z=0,w=1},rotation={roll=0,pitch=0,yaw=45}},
    size={x=1,y=1,z=1},metadata={npc_population={record='Character.bartender'}}})

-- Create with default tracks; schema.
local tl=assert(T:create({name='Bar Intro',duration=20}))
assert(#tl.tracks==4 and tl.tracks[1].kind=='camera' and tl.premise_id==premise.id)
local function track(kind) for _,t in ipairs(T:get(tl.id).tracks) do if t.kind==kind then return t end end end
local cam,dlg,ev,mk=track('camera'),track('dialogue'),track('event'),track('marker')

-- Validation of key payloads.
assert(not T:add_key(tl.id,cam.id,{time=1,camera_id='missing'}))
assert(not T:add_key(tl.id,cam.id,{time=1,camera_id=cam_a.id,transition='dolly'}))
assert(not T:add_key(tl.id,cam.id,{time=25,camera_id=cam_a.id}),'past the duration')
assert(not T:add_key(tl.id,dlg.id,{time=1,speaker='V'}))
assert(not T:add_key(tl.id,ev.id,{time=1,object_id='missing'}))
assert(not T:add_track(tl.id,{kind='sound'}) and not T:add_track(tl.id,{kind='npc'}))

-- Build a scene.
assert(T:add_key(tl.id,cam.id,{time=0,camera_id=cam_a.id}))
assert(T:add_key(tl.id,cam.id,{time=4,camera_id=cam_b.id,transition='move',duration=2}))
assert(T:add_key(tl.id,dlg.id,{time=1,speaker='Bartender',line='What will it be?',duration=2}))
assert(T:add_key(tl.id,dlg.id,{time=2,speaker='Bartender',line='Overlapping line',duration=1}))
local d3=assert(T:add_key(tl.id,dlg.id,{time=6,speaker='V',line='Whiskey, neat.'}))
assert(d3.duration>=1.5,'dialogue duration defaults from line length')
assert(T:add_key(tl.id,ev.id,{time=3,object_id=lamp.id,action='show'}))
assert(T:add_key(tl.id,ev.id,{time=8,object_id=lamp.id,action='hide'}))
assert(T:add_key(tl.id,mk.id,{time=5,label='Beat 2'}))
local facts=assert(T:add_track(tl.id,{kind='fact',name='Quest'}))
assert(not T:add_key(tl.id,facts.id,{time=7,fact='bad name!'}))
assert(T:add_key(tl.id,facts.id,{time=7,fact='sq_bar_intro_done',value=1}))
local nt=assert(T:add_track(tl.id,{kind='npc',target_id=npc.id,npc_key='12345'}))
assert(T:add_key(tl.id,nt.id,{time=0,position={x=3,y=3,z=0},yaw=45}))
assert(not T:add_key(tl.id,nt.id,{time=1,anim={name='x'}}),'anim needs name/comp/ent')
assert(T:add_key(tl.id,nt.id,{time=1.5,anim={name='bar_wipe',comp='workspot',ent='base\\amm_workspots\\bar.ent'}}))
local stop_key=assert(T:add_key(tl.id,nt.id,{time=9,action='stop'}))
local la=assert(T:add_track(tl.id,{kind='look_at'}))
assert(T:add_key(tl.id,la.id,{time=2,subject_id=npc.id,target_object_id=lamp.id}))

-- Keys stay sorted; update re-validates; undo is one step per edit.
local keys=track('camera').keys;assert(keys[1].time==0 and keys[2].time==4)
local moved=assert(T:update_key(tl.id,mk.id,track('marker').keys[1].id,{time=5.5}));assert(moved.time==5.5)
assert(not T:update_key(tl.id,mk.id,moved.id,{label=''}))
local before=#track('marker').keys
assert(T:add_key(tl.id,mk.id,{time=10,label='temp'}));assert(model:undo());assert(#track('marker').keys==before,'add key undoes as one step')

-- Evaluate.
local s=assert(T:evaluate(tl.id,1.5))
assert(s.camera.camera_id==cam_a.id and s.camera.blend==1)
assert(#s.dialogue==1 and s.dialogue[1].line=='What will it be?')
assert(s.objects[lamp.id]==nil and s.facts.sq_bar_intro_done==nil)
s=assert(T:evaluate(tl.id,5))
assert(s.camera.camera_id==cam_b.id and s.camera.blend>0.4 and s.camera.blend<0.6,'mid-move blend')
assert(s.camera.transform.position.x>3 and s.camera.transform.position.x<7)
assert(s.objects[lamp.id]==true and s.look_ats[npc.id].target_object_id==lamp.id)
local ns=s.npcs[nt.id];assert(ns.anim.name=='bar_wipe' and ns.position.x==3)
s=assert(T:evaluate(tl.id,9.5))
assert(s.camera.blend==1 and s.camera.transform.position.x==10)
assert(s.objects[lamp.id]==false and s.facts.sq_bar_intro_done.value==1 and s.npcs[nt.id].anim==nil)
assert(#s.markers==1)

-- Validate reports the overlap.
local v=assert(T:validate(tl.id))
local overlap=false;for _,i in ipairs(v.issues) do if i.message:find('before the previous one ends',1,true) then overlap=true end end
assert(v.valid and overlap)

-- Preview playback.
local ok_spawnless=not app.placement:is_tracked(lamp)
assert(ok_spawnless)
assert(T:play(tl.id,{}))
app.timeline:update_tick(0.5)
assert(#teleports>=1 and teleports[#teleports].position.x==0,'cut to the first camera')
app.timeline:update_tick(1.5)
assert(#anims.played==1 and anims.played[1].key=='12345' and anims.played[1].anim.name=='bar_wipe')
app.timeline:update_tick(1.5)
assert(app.placement:is_tracked(model:get_object(lamp.id)),'show event spawned the lamp')
app.timeline:update_tick(2)
assert(teleports[#teleports].position.x>0 and teleports[#teleports].position.x<10,'camera moves in between')
app.timeline:update_tick(3)
local st=T:status();assert(st.active and #st.facts_not_written==1 and st.facts_not_written[1].written==false)
assert(not app.placement:is_tracked(model:get_object(lamp.id)),'hide event despawned it')
assert(T:seek(3.5));assert(app.placement:is_tracked(model:get_object(lamp.id)),'seeking applies state')
-- Bridge: read-only status while previewing; stop restores.
assert(assert(app.bridge:handle({id='t0',op='timeline_status',args={}})).active)
local stopped=assert(T:stop())
assert(stopped.stopped and not app.placement:is_tracked(model:get_object(lamp.id)),'the lamp returns to its original unspawned state')
assert(anims.stopped[#anims.stopped]=='12345','started animations are stopped')
assert(teleports[#teleports].position.x==10 and teleports[#teleports].position.y==20,'V returns to the start position')
assert(not T:stop(),'nothing to stop')

-- Play to the end stops running.
assert(T:play(tl.id,{speed=4}));app.timeline:update_tick(10);assert(T:status().playing==false and T:status().time==20);assert(T:stop())

-- Export handoff.
local out=assert(T:export(tl.id))
assert(out.shots==2 and out.dialogue_lines==3 and out.facts==1 and out.valid)
local f=assert(io.open(out.json,'r'));local handoff=json.decode(f:read('*a'));f:close()
assert(handoff.schema=='locationstudio-timeline-handoff/1' and handoff.timeline.duration==20)
assert(handoff.shot_list[1]['end']==4 and handoff.shot_list[2].length==16)
assert(handoff.references.cameras[cam_b.id].name=='Close' and handoff.references.objects[lamp.id].name=='Neon')
assert(handoff.references.npcs[npc.id].record=='Character.bartender')
for i=2,#handoff.cues do assert(handoff.cues[i-1].time<=handoff.cues[i].time,'cues are chronological') end
assert(handoff.note:find('does not generate native .scene',1,true))
f=assert(io.open(out.dialogue_csv,'r'));local csv=f:read('*a');f:close()
assert(csv:find('time_s,duration_s,speaker',1,true) and csv:find('"Whiskey, neat."',1,true))
os.remove(out.json);os.remove(out.dialogue_csv)

-- A deleted camera is an error; deleting the premise unlinks.
model:delete_camera(cam_b.id)
v=T:validate(tl.id);assert(not v.valid and v.errors>=1)

-- Bridge CRUD.
local created=assert(app.bridge:handle({id='t1',op='timeline_create',args={name='Bridge',duration=10,default_tracks=false}})).timeline
local tr=assert(app.bridge:handle({id='t2',op='timeline_add_track',args={id=created.id,kind='marker'}})).track
local key=assert(app.bridge:handle({id='t3',op='timeline_add_key',args={id=created.id,track_id=tr.id,key={time=2,label='go'}}})).key
assert(assert(app.bridge:handle({id='t4',op='timeline_evaluate',args={id=created.id,time=3}})).markers[1].label=='go')
assert(assert(app.bridge:handle({id='t5',op='timeline_list',args={}})).count==2)
assert(assert(app.bridge:handle({id='t6',op='timeline_delete_key',args={id=created.id,track_id=tr.id,key_id=key.id}})).deleted==key.id)
assert(assert(app.bridge:handle({id='t7',op='timeline_delete',args={id=created.id}})).deleted==created.id)

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.ui.spatial.tl_name='UI Timeline'
env.clicks['NEW TIMELINE']=true;env:draw()
local ui_tl=T:get(app.ui.spatial.tl_id);assert(ui_tl and ui_tl.name=='UI Timeline')
app.selected_camera_id=cam_a.id
env.clicks['CUT TO SELECTED CAMERA']=true;env:draw()
assert(#T:get(ui_tl.id).tracks[1].keys==1,'camera cut added at the playhead')
env.clicks['PLAY##tl']=true;env:draw();assert(T:status().active)
env.clicks['STOP & RESTORE##tl']=true;env:draw();assert(not T:status().active)
env.clicks['EXPORT HANDOFF']=true;env:draw()
os.remove('exports/timeline_ui_timeline.json');os.remove('exports/timeline_ui_timeline_dialogue.csv')
print('timeline_runtime_test: OK')
