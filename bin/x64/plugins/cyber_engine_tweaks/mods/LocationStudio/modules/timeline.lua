local Util=require('modules/util')

-- Cinematic timeline editor. A timeline holds typed tracks of time-ordered
-- keys:
--   camera    cut to / move to a saved camera (moves blend over `duration`)
--   npc       NPC placement (position/yaw) and AMM-style workspot animation
--   look_at   a subject (NPC/camera) looks at an object or point
--   dialogue  timed dialogue markers: speaker, line, duration, optional loc key
--   event     show / hide / toggle a placed object (lights, VFX, audio, props)
--   fact      quest fact values expected at a time
--   marker    free labels (beats, sync points)
-- It evaluates the state at any time, previews playback in game (camera by
-- teleporting V, object events through the normal spawn path, animations
-- through live tools; quest facts are never written), restores everything on
-- stop, and exports a structured handoff for .scene authoring. No native
-- .scene resource is generated.
local Timeline={};Timeline.__index=Timeline

local KINDS={camera=true,npc=true,look_at=true,dialogue=true,event=true,fact=true,marker=true}
local TRANSITIONS={cut=true,move=true}
local EVENT_ACTIONS={show=true,hide=true,toggle=true}

local function num(v,f) v=tonumber(v);if v==nil or v~=v or v==math.huge or v==-math.huge then return f end;return v end
local function point(v) return type(v)=='table' and num(v.x)~=nil and num(v.y)~=nil and num(v.z)~=nil end
local function lerp(a,b,f) return a+(b-a)*f end
local function lerp_angle(a,b,f) local d=((b-a+180)%360)-180;return a+d*f end
local function slug(s) return (tostring(s or 'timeline'):lower():gsub('[^%w]+','_'):gsub('^_+',''):gsub('_+$','')) end

function Timeline.new(app) return setmetatable({app=app,playback=nil,last_error=nil},Timeline) end

function Timeline:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

function Timeline:get(id) return self.app.model:get_timeline(id) end

local function find_track(timeline,track_id)
    for i,t in ipairs(timeline.tracks) do if t.id==track_id then return t,i end end
    return nil
end
local function find_key(track,key_id)
    for i,k in ipairs(track.keys) do if k.id==key_id then return k,i end end
    return nil
end
local function sort_keys(track) table.sort(track.keys,function(a,b) if a.time==b.time then return tostring(a.id)<tostring(b.id) end;return a.time<b.time end) end

function Timeline:_touch(timeline) timeline.updated_at=Util.now_iso();self.app.model:touch();self.app:mark_dirty() end

-- CRUD ------------------------------------------------------------------------

function Timeline:list(args)
    args=args or {};local out={}
    for _,t in ipairs(self.app.model.data.timelines or {}) do
        if not args.premise_id or args.premise_id=='' or t.premise_id==args.premise_id then
            local keys=0;for _,tr in ipairs(t.tracks) do keys=keys+#tr.keys end
            out[#out+1]={id=t.id,name=t.name,duration=t.duration,tracks=#t.tracks,keys=keys,premise_id=t.premise_id,scene_id=t.scene_id}
        end
    end
    return {items=out,count=#out,playing=self.playback and self.playback.timeline_id or nil}
end

function Timeline:create(args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local timeline=self.app.model:add_timeline({name=args.name,premise_id=args.premise_id or self.app.selected_premise_id,scene_id=args.scene_id,duration=args.duration,fps=args.fps,notes=args.notes})
    if args.default_tracks~=false then
        for _,kind in ipairs({'camera','dialogue','event','marker'}) do timeline.tracks[#timeline.tracks+1]={id=Util.make_id('track'),kind=kind,name=kind,enabled=true,muted=false,keys={}} end
    end
    self.app:mark_dirty()
    return timeline
end

function Timeline:update(id,patch)
    patch=patch or {}
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    if patch.duration~=nil then local d=num(patch.duration);if not d or d<0.1 or d>3600 then return nil,'duration must be between 0.1 and 3600 seconds' end end
    self.app.model:snapshot('Update timeline')
    if patch.name and Util.trim(patch.name)~='' then timeline.name=Util.trim(patch.name) end
    if patch.duration~=nil then timeline.duration=num(patch.duration) end
    if patch.fps~=nil then timeline.fps=math.max(1,math.min(120,math.floor(num(patch.fps,30)))) end
    if patch.scene_id~=nil then timeline.scene_id=patch.scene_id~='' and patch.scene_id or nil end
    if patch.notes~=nil then timeline.notes=tostring(patch.notes) end
    self:_touch(timeline);return timeline
end

function Timeline:delete(id)
    local timeline,index=self:get(id);if not timeline then return nil,'timeline not found' end
    if self.playback and self.playback.timeline_id==id then local ok,err=self:stop();if not ok then return nil,'stop the preview first: '..tostring(err) end end
    self.app.model:snapshot('Delete timeline');table.remove(self.app.model.data.timelines,index);self.app.model:touch();self.app:mark_dirty()
    return {deleted=id}
end

function Timeline:add_track(id,args)
    args=args or {}
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    if not KINDS[args.kind] then return nil,'kind must be camera, npc, look_at, dialogue, event, fact or marker' end
    if args.kind=='npc' and not (args.target_id or args.npc_key) then return nil,'an npc track needs target_id (saved NPC population point) or npc_key (live NPC)' end
    if args.target_id and args.kind=='npc' then
        local o=self.app.model:get_object(args.target_id);if not o then return nil,'target_id does not reference a saved object' end
    end
    self.app.model:snapshot('Add timeline track')
    local track={id=Util.make_id('track'),kind=args.kind,name=Util.trim(args.name or '')~='' and Util.trim(args.name) or args.kind,target_id=args.target_id,npc_key=args.npc_key,enabled=true,muted=false,keys={}}
    timeline.tracks[#timeline.tracks+1]=track;self:_touch(timeline)
    return track
end

function Timeline:update_track(id,track_id,patch)
    patch=patch or {}
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    local track=find_track(timeline,track_id);if not track then return nil,'track not found' end
    self.app.model:snapshot('Update timeline track')
    for _,field in ipairs({'name','target_id','npc_key'}) do if patch[field]~=nil then track[field]=patch[field]~='' and patch[field] or nil end end
    if patch.enabled~=nil then track.enabled=patch.enabled==true end
    if patch.muted~=nil then track.muted=patch.muted==true end
    self:_touch(timeline);return track
end

function Timeline:delete_track(id,track_id)
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    local _,index=find_track(timeline,track_id);if not index then return nil,'track not found' end
    self.app.model:snapshot('Delete timeline track');table.remove(timeline.tracks,index);self:_touch(timeline)
    return {deleted=track_id}
end

-- Validate one key's payload for its track kind; returns a clean key.
function Timeline:_clean_key(track,input,base)
    local k=Util.deepcopy(base or {});for key,v in pairs(input or {}) do k[key]=Util.deepcopy(v) end
    k.time=num(k.time,nil);if not k.time or k.time<0 then return nil,'key time must be a number >= 0' end
    if k.duration~=nil then k.duration=num(k.duration,nil);if not k.duration or k.duration<0 then return nil,'duration must be >= 0' end end
    local kind=track.kind
    if kind=='camera' then
        if not k.camera_id or not self.app.model:get_camera(k.camera_id) then return nil,'camera key needs camera_id of a saved camera' end
        k.transition=k.transition or 'cut';if not TRANSITIONS[k.transition] then return nil,'transition must be cut or move' end
        if k.transition=='move' then k.duration=k.duration or 2 end
    elseif kind=='npc' then
        if k.position~=nil and not point(k.position) then return nil,'npc position must be {x,y,z}' end
        if k.anim~=nil and (type(k.anim)~='table' or not k.anim.name or not k.anim.comp or not k.anim.ent) then return nil,'npc anim must be {name, comp, ent} (AMM workspot data)' end
        if k.position==nil and k.anim==nil and k.action~='stop' then return nil,'npc key needs a position, an anim, or action=stop' end
        if k.yaw~=nil then k.yaw=num(k.yaw,0) end
    elseif kind=='look_at' then
        if not k.subject_id then return nil,'look_at key needs subject_id (NPC object or camera id)' end
        if not k.target_object_id and not point(k.target) then return nil,'look_at key needs target_object_id or target {x,y,z}' end
    elseif kind=='dialogue' then
        if Util.trim(k.speaker or '')=='' or Util.trim(k.line or '')=='' then return nil,'dialogue key needs speaker and line' end
        k.duration=k.duration or math.max(1.5,#tostring(k.line)/15)
    elseif kind=='event' then
        if not k.object_id or not self.app.model:get_object(k.object_id) then return nil,'event key needs object_id of a placed object' end
        k.action=k.action or 'toggle';if not EVENT_ACTIONS[k.action] then return nil,'event action must be show, hide or toggle' end
    elseif kind=='fact' then
        if not tostring(k.fact or ''):match('^[%w_%.%-]+$') then return nil,'fact key needs a fact name ([A-Za-z0-9_.-])' end
        k.value=math.floor(num(k.value,1))
    elseif kind=='marker' then
        if Util.trim(k.label or '')=='' then return nil,'marker key needs a label' end
    end
    return k
end

function Timeline:add_key(id,track_id,input)
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    local track=find_track(timeline,track_id);if not track then return nil,'track not found' end
    local key,err=self:_clean_key(track,input);if not key then return nil,err end
    if key.time>timeline.duration then return nil,'key time is beyond the timeline duration ('..timeline.duration..' s)' end
    self.app.model:snapshot('Add timeline key')
    key.id=Util.make_id('key');track.keys[#track.keys+1]=key;sort_keys(track);self:_touch(timeline)
    return key
end

function Timeline:update_key(id,track_id,key_id,patch)
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    local track=find_track(timeline,track_id);if not track then return nil,'track not found' end
    local old,index=find_key(track,key_id);if not old then return nil,'key not found' end
    local key,err=self:_clean_key(track,patch,old);if not key then return nil,err end
    if key.time>timeline.duration then return nil,'key time is beyond the timeline duration' end
    self.app.model:snapshot('Edit timeline key')
    key.id=old.id;track.keys[index]=key;sort_keys(track);self:_touch(timeline)
    return key
end

function Timeline:delete_key(id,track_id,key_id)
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    local track=find_track(timeline,track_id);if not track then return nil,'track not found' end
    local _,index=find_key(track,key_id);if not index then return nil,'key not found' end
    self.app.model:snapshot('Delete timeline key');table.remove(track.keys,index);self:_touch(timeline)
    return {deleted=key_id}
end

-- Evaluation --------------------------------------------------------------------

function Timeline:_camera_transform(camera_id)
    local c=self.app.model:get_camera(camera_id);return c and Util.deepcopy(c.transform) or nil,c
end

-- State of every track at time t.
function Timeline:evaluate(id,t)
    local timeline=type(id)=='table' and id or self:get(id);if not timeline then return nil,'timeline not found' end
    t=math.max(0,math.min(timeline.duration,num(t,0)))
    local state={time=t,camera=nil,npcs={},look_ats={},dialogue={},objects={},facts={},markers={},next_key_time=nil}
    for _,track in ipairs(timeline.tracks) do
        if track.enabled and not track.muted then
            local last,prev_camera=nil,nil
            for _,k in ipairs(track.keys) do
                if k.time<=t then
                    if track.kind=='camera' then prev_camera=last end
                    last=k
                    if track.kind=='event' then
                        local o=self.app.model:get_object(k.object_id)
                        if o then
                            local current=state.objects[k.object_id];if current==nil then current=(o.enabled~=false) end
                            if k.action=='show' then current=true elseif k.action=='hide' then current=false else current=not current end
                            state.objects[k.object_id]=current
                        end
                    elseif track.kind=='fact' then state.facts[k.fact]={value=k.value,time=k.time}
                    elseif track.kind=='marker' then state.markers[#state.markers+1]={label=k.label,time=k.time}
                    elseif track.kind=='look_at' then state.look_ats[k.subject_id]={target_object_id=k.target_object_id,target=k.target,time=k.time}
                    elseif track.kind=='dialogue' and t<k.time+(k.duration or 0) then state.dialogue[#state.dialogue+1]={speaker=k.speaker,line=k.line,line_id=k.line_id,time=k.time,duration=k.duration}
                    end
                elseif not state.next_key_time or k.time<state.next_key_time then state.next_key_time=k.time end
            end
            if track.kind=='camera' and last then
                local to,camera=self:_camera_transform(last.camera_id)
                local cam={camera_id=last.camera_id,name=camera and camera.name,transition=last.transition,fov=last.fov or (camera and camera.fov),transform=to,blend=1}
                if last.transition=='move' and prev_camera and last.duration and last.duration>0 and t<last.time+last.duration then
                    local from=self:_camera_transform(prev_camera.camera_id)
                    if from and to then
                        local f=(t-last.time)/last.duration;f=f*f*(3-2*f)
                        cam.transform={position={x=lerp(from.position.x,to.position.x,f),y=lerp(from.position.y,to.position.y,f),z=lerp(from.position.z,to.position.z,f),w=1},
                            rotation={roll=lerp_angle(from.rotation.roll or 0,to.rotation.roll or 0,f),pitch=lerp_angle(from.rotation.pitch or 0,to.rotation.pitch or 0,f),yaw=lerp_angle(from.rotation.yaw or 0,to.rotation.yaw or 0,f)}}
                        cam.blend=f;cam.from_camera_id=prev_camera.camera_id
                    end
                end
                state.camera=cam
            elseif track.kind=='npc' and last then
                -- Latest position and latest animation are tracked separately.
                local pos,anim=nil,nil
                for _,k in ipairs(track.keys) do if k.time<=t then if k.position then pos=k end;if k.anim then anim=k elseif k.action=='stop' then anim=nil end end end
                state.npcs[track.id]={target_id=track.target_id,npc_key=track.npc_key,position=pos and pos.position,yaw=pos and pos.yaw,anim=anim and anim.anim,anim_since=anim and anim.time}
            end
        end
    end
    return state
end

-- Validation ------------------------------------------------------------------

function Timeline:validate(id)
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    local issues={}
    local function issue(sev,track,key,msg) issues[#issues+1]={severity=sev,track_id=track and track.id,track=track and track.name,key_id=key and key.id,time=key and key.time,message=msg} end
    local cameras=0
    for _,track in ipairs(timeline.tracks) do
        local speaking={}
        for i,k in ipairs(track.keys) do
            if k.time>timeline.duration then issue('error',track,k,'key is beyond the timeline duration') end
            if track.kind=='camera' then
                cameras=cameras+1
                if not self.app.model:get_camera(k.camera_id) then issue('error',track,k,'camera '..tostring(k.camera_id)..' no longer exists') end
                if k.transition=='move' and i==1 then issue('warning',track,k,'first camera key is a move with nothing to move from; it behaves as a cut') end
            elseif track.kind=='event' and not self.app.model:get_object(k.object_id) then issue('error',track,k,'event object '..tostring(k.object_id)..' no longer exists')
            elseif track.kind=='look_at' and k.target_object_id and not self.app.model:get_object(k.target_object_id) then issue('error',track,k,'look-at target object no longer exists')
            elseif track.kind=='dialogue' then
                local last=speaking[k.speaker]
                if last and last.time+(last.duration or 0)>k.time then issue('warning',track,k,tostring(k.speaker)..' starts a line before the previous one ends') end
                speaking[k.speaker]=k
                if k.time+(k.duration or 0)>timeline.duration then issue('warning',track,k,'dialogue runs past the end of the timeline') end
            elseif track.kind=='npc' and k.anim and not track.npc_key then issue('info',track,k,'animation preview needs a live npc_key on the track; the handoff still records it') end
        end
        if track.kind=='npc' and track.target_id and not self.app.model:get_object(track.target_id) then issue('error',track,nil,'npc target object no longer exists') end
    end
    if cameras==0 then issue('warning',nil,nil,'no camera keys; the scene has no shots') end
    local errors=0;for _,i in ipairs(issues) do if i.severity=='error' then errors=errors+1 end end
    return {timeline_id=id,issues=issues,errors=errors,valid=errors==0}
end

-- Preview playback --------------------------------------------------------------

function Timeline:status()
    local p=self.playback
    if not p then return {playing=false,active=false,last_error=self.last_error} end
    local timeline=self:get(p.timeline_id)
    local state=timeline and self:evaluate(timeline,p.time) or {}
    return {active=true,playing=p.running,timeline_id=p.timeline_id,time=p.time,duration=timeline and timeline.duration,speed=p.speed,
        camera=state.camera and {camera_id=state.camera.camera_id,name=state.camera.name,blend=state.camera.blend} or nil,
        dialogue=state.dialogue,facts_not_written=p.facts,warnings=p.warnings,markers=state.markers}
end

function Timeline:play(id,args)
    args=args or {}
    local busy=self:_busy();if busy then return nil,busy end
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    if self.playback and self.playback.timeline_id~=id then local ok,err=self:stop();if not ok then return nil,err end end
    if not self.playback then
        local start=self.app.game:capture_transform()
        self.playback={timeline_id=id,time=0,speed=1,running=false,start_transform=start,object_baseline={},started_anims={},fired={},facts={},warnings={},apply_camera=args.apply_camera~=false,apply_events=args.apply_events~=false,apply_npcs=args.apply_npcs~=false}
    end
    local p=self.playback
    p.speed=math.max(0.1,math.min(4,num(args.speed,p.speed)));p.loop=args.loop==true
    if args.from~=nil then local ok,err=self:seek(num(args.from,0));if not ok then return nil,err end end
    p.running=true
    return self:status()
end

function Timeline:pause() if not self.playback then return nil,'no timeline preview is active' end;self.playback.running=false;return self:status() end

function Timeline:_apply_objects(state)
    local p=self.playback
    for object_id,visible in pairs(state.objects) do
        local o=self.app.model:get_object(object_id)
        if o then
            if p.object_baseline[object_id]==nil then p.object_baseline[object_id]=self.app.placement:is_tracked(o) end
            local live=self.app.placement:is_tracked(o)
            if visible and not live then local ok,err=self.app.placement:spawn(o);if not ok then p.warnings[#p.warnings+1]='could not show '..tostring(o.name)..': '..tostring(err) end
            elseif not visible and live then local ok,err=self.app.placement:despawn(o);if not ok then p.warnings[#p.warnings+1]='could not hide '..tostring(o.name)..': '..tostring(err) end end
        end
    end
end

function Timeline:_apply_camera(state)
    local p=self.playback
    if not p.apply_camera or not state.camera or not state.camera.transform then return end
    local sig=state.camera.camera_id..':'..string.format('%.2f',state.camera.blend or 1)
    if sig==p.last_camera_sig then return end
    p.last_camera_sig=sig
    local ok,err=self.app.game:teleport(state.camera.transform)
    if not ok then p.warnings[#p.warnings+1]='camera preview failed: '..tostring(err) end
end

-- Keys crossed between two times fire once: animations and fact notes.
function Timeline:_fire(timeline,from,to)
    local p=self.playback
    for _,track in ipairs(timeline.tracks) do
        if track.enabled and not track.muted then
            for _,k in ipairs(track.keys) do
                if k.time>from and k.time<=to and not p.fired[k.id] then
                    p.fired[k.id]=true
                    if track.kind=='fact' then p.facts[#p.facts+1]={fact=k.fact,value=k.value,time=k.time,written=false}
                    elseif track.kind=='npc' and p.apply_npcs and self.app.live_tools and track.npc_key then
                        if k.anim then
                            local ok,err=self.app.live_tools:play({key=track.npc_key,anim=k.anim})
                            if ok then p.started_anims[track.npc_key]=true else p.warnings[#p.warnings+1]='animation '..tostring(k.anim.name)..': '..tostring(err) end
                        elseif k.action=='stop' then self.app.live_tools:stop({key=track.npc_key});p.started_anims[track.npc_key]=nil end
                    end
                end
            end
        end
    end
end

function Timeline:seek(t)
    local p=self.playback;if not p then return nil,'no timeline preview is active; call play first' end
    local timeline=self:get(p.timeline_id);if not timeline then return nil,'timeline not found' end
    t=math.max(0,math.min(timeline.duration,num(t,0)))
    -- Jumping re-arms keys after the new time; keys before it count as fired.
    p.fired={}
    for _,track in ipairs(timeline.tracks) do for _,k in ipairs(track.keys) do if k.time<=t then p.fired[k.id]=true end end end
    p.time=t;p.last_camera_sig=nil
    local state=self:evaluate(timeline,t)
    if p.apply_events then self:_apply_objects(state) end
    self:_apply_camera(state)
    return self:status()
end

function Timeline:update_tick(delta)
    local p=self.playback;if not p or not p.running then return end
    local timeline=self:get(p.timeline_id);if not timeline then self.playback=nil;return end
    local from=p.time;local to=from+num(delta,0)*p.speed
    if to>=timeline.duration then
        to=timeline.duration
        if not p.loop then p.running=false end
    end
    if from==0 and not p.fired.__start then p.fired.__start=true;self:_fire(timeline,-1,to) else self:_fire(timeline,from,to) end
    p.time=to
    local state=self:evaluate(timeline,to)
    if p.apply_events then self:_apply_objects(state) end
    self:_apply_camera(state)
    if p.loop and to>=timeline.duration then p.fired={};p.time=0 end
end

-- End the preview and restore objects, animations and V's position.
function Timeline:stop()
    local p=self.playback;if not p then return nil,'no timeline preview is active' end
    local errors={}
    for object_id,was_live in pairs(p.object_baseline) do
        local o=self.app.model:get_object(object_id)
        if o then
            local live=self.app.placement:is_tracked(o)
            if was_live and not live then local ok,err=self.app.placement:spawn(o);if not ok then errors[#errors+1]=tostring(o.name)..': '..tostring(err) end
            elseif not was_live and live then local ok,err=self.app.placement:despawn(o);if not ok then errors[#errors+1]=tostring(o.name)..': '..tostring(err) end end
        end
    end
    if self.app.live_tools then for key in pairs(p.started_anims) do pcall(function() self.app.live_tools:stop({key=key}) end) end end
    if p.start_transform then local ok,err=self.app.game:teleport(p.start_transform);if not ok then errors[#errors+1]='return V: '..tostring(err) end end
    if #errors>0 then
        self.last_error=table.concat(errors,'; ')
        p.running=false;p.object_baseline={}
        self.playback=nil
        return nil,'preview stopped with restore errors: '..self.last_error
    end
    self.playback=nil;self.last_error=nil
    return {stopped=true,facts_not_written=p.facts}
end

-- Handoff export ------------------------------------------------------------------

function Timeline:_resolve(timeline)
    local model=self.app.model;local refs={cameras={},objects={},npcs={}}
    local function object_ref(id)
        if not id or refs.objects[id] then return end
        local o=model:get_object(id);if not o then return end
        local wb=o.metadata and o.metadata.world_builder or {}
        refs.objects[id]={id=o.id,name=o.name,kind=o.kind,layer=o.layer,template=o.template~='' and o.template or nil,resource_path=wb.resource_path,
            world_builder_class=wb.definition_key,node_ref=o.metadata and (o.metadata.node_ref or (o.metadata.questforge and o.metadata.questforge.node_ref)) or nil,
            transform=Util.deepcopy(o.transform)}
    end
    for _,track in ipairs(timeline.tracks) do
        if track.kind=='npc' and track.target_id then
            local o=model:get_object(track.target_id)
            if o then refs.npcs[o.id]={id=o.id,name=o.name,record=o.metadata and o.metadata.npc_population and o.metadata.npc_population.record,
                appearance=o.metadata and o.metadata.npc_population and o.metadata.npc_population.appearance,transform=Util.deepcopy(o.transform)} end
        end
        for _,k in ipairs(track.keys) do
            if k.camera_id and not refs.cameras[k.camera_id] then local c=model:get_camera(k.camera_id);if c then refs.cameras[c.id]={id=c.id,name=c.name,transform=Util.deepcopy(c.transform),look_at=Util.deepcopy(c.look_at),fov=c.fov} end end
            object_ref(k.object_id);object_ref(k.target_object_id)
            if k.subject_id and model:get_object(k.subject_id) then object_ref(k.subject_id) end
        end
    end
    return refs
end

function Timeline:export(id,args)
    args=args or {}
    local timeline=self:get(id);if not timeline then return nil,'timeline not found' end
    local validation=self:validate(id)
    local cues={}
    for _,track in ipairs(timeline.tracks) do
        if track.enabled then
            for _,k in ipairs(track.keys) do
                local cue=Util.deepcopy(k);cue.track=track.name;cue.track_kind=track.kind;cue.track_id=track.id;cue.muted=track.muted or nil
                if track.kind=='npc' then cue.npc_target_id=track.target_id;cue.npc_key=track.npc_key end
                cues[#cues+1]=cue
            end
        end
    end
    table.sort(cues,function(a,b) if a.time==b.time then return tostring(a.track)<tostring(b.track) end;return a.time<b.time end)
    local dialogue,facts,shots={}, {}, {}
    for _,c in ipairs(cues) do
        if c.track_kind=='dialogue' then dialogue[#dialogue+1]={time=c.time,duration=c.duration,speaker=c.speaker,line=c.line,line_id=c.line_id}
        elseif c.track_kind=='fact' then facts[#facts+1]={time=c.time,fact=c.fact,value=c.value}
        elseif c.track_kind=='camera' then shots[#shots+1]={start=c.time,camera_id=c.camera_id,transition=c.transition,blend=c.duration,fov=c.fov} end
    end
    for i,s in ipairs(shots) do s['end']=shots[i+1] and shots[i+1].start or timeline.duration;s.length=s['end']-s.start end
    local handoff={schema='locationstudio-timeline-handoff/1',exported_at=Util.now_iso(),mod_version=self.app.version,
        timeline={id=timeline.id,name=timeline.name,duration=timeline.duration,fps=timeline.fps,premise_id=timeline.premise_id,scene_id=timeline.scene_id,notes=timeline.notes},
        tracks=Util.deepcopy(timeline.tracks),cues=cues,shot_list=shots,dialogue_script=dialogue,quest_facts=facts,references=self:_resolve(timeline),validation=validation,
        note='Structured handoff for .scene / quest authoring (for example WolvenKit scene editing or Quest Forge). LocationStudio does not generate native .scene resources; timings are seconds from the start.'}
    local base=args.path or ('exports/timeline_'..slug(timeline.name))
    local ok=Util.json_write(base..'.json',handoff)
    if ok==false then return nil,'could not write '..base..'.json' end
    local lines={'time_s,duration_s,speaker,line_id,line'}
    for _,d in ipairs(dialogue) do
        local line=tostring(d.line):gsub('"','""')
        lines[#lines+1]=string.format('%.3f,%.3f,"%s","%s","%s"',d.time,d.duration or 0,tostring(d.speaker):gsub('"','""'),tostring(d.line_id or ''):gsub('"','""'),line)
    end
    Util.write_file(base..'_dialogue.csv',table.concat(lines,'\n')..'\n')
    return {json=base..'.json',dialogue_csv=base..'_dialogue.csv',cues=#cues,shots=#shots,dialogue_lines=#dialogue,facts=#facts,valid=validation.valid,issues=#validation.issues}
end

return Timeline
