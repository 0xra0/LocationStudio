local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local P=assert(app.procedural,'procedural geometry must be constructed')
local model=app.model
local G=P.generate
local function close(a,b) return math.abs(a-b)<1e-6 end

-- Generators.
local names={};for _,g in ipairs(P:generators().items) do names[#names+1]=g.id end
assert(table.concat(names,',')=='box,ceiling,column,door_frame,duct,floor,pipe,railing,ramp,stairs,wall,window')

local wall=assert(G('wall',{length=6,height=3,thickness=0.2,openings={{offset=-1,width=1,height=2.1,sill=0},{offset=1.5,width=1.2,height=1.2,sill=1}}}))
-- left solid, above door, right-of-door solid, above window, below window, right solid
assert(#wall.parts==6,#wall.parts)
assert(close(wall.bounds.min.x,-3) and close(wall.bounds.max.x,3) and close(wall.bounds.max.z,3) and close(wall.bounds.min.y,-0.1))
local vol=0;for _,p in ipairs(wall.parts) do vol=vol+p.size.x*p.size.y*p.size.z end
assert(close(vol,(6*3-1*2.1-1.2*1.2)*0.2),'wall volume excludes the openings')
assert(not G('wall',{length=4,openings={{offset=0,width=5}}}),'opening past the ends')
assert(not G('wall',{length=4,openings={{offset=0,width=1},{offset=0.3,width=1}}}),'overlapping openings')
assert(not G('wall',{length=4,height=3,openings={{width=1,height=2.5,sill=1}}}),'too tall')
assert(not G('nope',{}))

local stairs=assert(G('stairs',{width=1.2,height=1.8,length=2.7,landing=1,stringers=true}))
assert(#stairs.parts==10+1+2,'10 steps (0.18 risers) + landing + 2 stringers')
local plain_stairs=assert(G('stairs',{width=1.2,height=1.8,length=2.7,landing=1}))
assert(close(plain_stairs.bounds.max.z,1.8) and close(plain_stairs.bounds.max.y,3.7) and stairs.bounds.max.z>1.8,'stringers rise above the treads')
local ramp=assert(G('ramp',{width=2,length=4,height=1}))
assert(ramp.parts[1].shape=='wedge' and close(ramp.bounds.max.z,1))
local slab=assert(G('ramp',{width=2,length=4,height=1,solid=false,thickness=0.1}))
assert(close(slab.parts[1].rotation.pitch,math.deg(math.atan(1/4))))

local col=assert(G('column',{shape='round',radius=0.25,height=3,base={height=0.2},cap={height=0.2}}))
assert(#col.parts==3 and col.parts[2].shape=='cylinder' and close(col.bounds.max.z,3) and close(col.parts[2].length,2.6))
local flr=assert(G('floor',{points={{0,0},{4,0},{4,3},{0,3}},thickness=0.25}))
assert(flr.parts[1].shape=='prism' and close(flr.bounds.min.z,-0.25) and close(flr.bounds.max.x,4))
local ceil=assert(G('ceiling',{width=4,depth=3,height=2.8,thickness=0.2}));assert(close(ceil.bounds.min.z,2.8) and close(ceil.bounds.max.z,3.0))

-- Segments follow the polyline in 3D.
local pipe=assert(G('pipe',{points={{0,0,0},{0,4,0},{0,4,3}},radius=0.1}))
assert(#pipe.parts==3 and pipe.parts[3].shape=='sphere')
assert(close(pipe.parts[1].rotation.yaw,0) and close(pipe.parts[2].rotation.pitch,90))
assert(close(pipe.bounds.max.z,3) and close(pipe.bounds.max.y,4.1),"the elbow sphere pads the bend, not the ends")
local duct=assert(G('duct',{points={{0,0,0},{4,0,0}},width=0.6,height=0.4}))
assert(close(duct.parts[1].rotation.yaw,-90) and close(duct.bounds.max.x,4) and close(duct.bounds.max.y,0.3))
local rail=assert(G('railing',{points={{0,0,0},{2.4,0,0},{2.4,2.4,0}},height=1,post_spacing=1.2,rails=2}))
local posts,rails=0,0;for _,p in ipairs(rail.parts) do if close(p.size.z,1) then posts=posts+1 else rails=rails+1 end end
assert(posts==5 and rails==4,posts..' posts '..rails..' rails')
local win=assert(G('window',{width=1.6,height=1.2,sill=1,mullions_x=1,mullions_y=1}))
local glass=0;for _,p in ipairs(win.parts) do if p.material=='glass' then glass=glass+1 end end
assert(#win.parts==7 and glass==1)
assert(#assert(G('door_frame',{width=1,height=2.1,threshold=true})).parts==4)

-- Rotation convention matches R = Rz(yaw) Rx(pitch) Ry(roll).
local v=P.rotate({x=0,y=1,z=0},{roll=0,pitch=30,yaw=90})
assert(close(v.x,-math.cos(math.rad(30))) and close(v.y,0) and close(v.z,0.5))

-- Create: one undo, collision, preview, bounds.
local premise=model:add_premise({name='Loft',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
local history=#model.undo_stack
local T={position={x=100,y=50,z=10,w=1},rotation={roll=0,pitch=0,yaw=90}}
local made=assert(P:create({generator='wall',params={length=6,height=3,thickness=0.2,openings={{offset=0,width=1,height=2.1}}},name='North wall',
    transform=T,collision=true,material={template='base\\environment\\architecture\\wall_plaster.mesh',appearance='white'}}))
assert(#model.undo_stack==history+1,'create is one undo step')
local o=made.object
assert(o.kind=='procedural' and o.metadata.procedural.parts and made.parts==3 and made.colliders==3)
assert(made.mesh_path:match('^mod\\locationstudio\\procedural\\loft\\north_wall_') and made.mesh_path:match('%.mesh$'))
assert(o.metadata.asset_bounds.source=='procedural' and close(o.metadata.asset_bounds.max.x,3))
assert(made.proxies==3 and P:is_shown(o) and app.placement:is_tracked(o),'preview shapes are spawned')
local collider=model:get_object(o.metadata.procedural.collider_ids[1])
assert(collider.metadata.collision and collider.metadata.procedural_owner==o.id)
-- Collider placed in world: the object's yaw 90 turns local x into world y.
assert(close(collider.transform.position.x,100) and collider.transform.rotation.yaw==90)
local ab=assert(app.asset_bounds:world_aabb(o.id));assert(close(ab.aabb.min.y,47) and close(ab.aabb.max.y,53),'bounds rotate with the object')

-- Update regenerates and replaces colliders; failure leaves everything unchanged.
history=#model.undo_stack
local up=assert(P:update(o.id,{params={openings={}}}))
assert(up.parts==1 and #model.undo_stack==history+1 and #model:get_object(o.id).metadata.procedural.collider_ids==1)
assert(not model:get_object(collider.id),'old colliders removed')
local count=#model.data.objects
assert(not P:update(o.id,{params={length=500}}))
assert(#model.data.objects==count and #model:get_object(o.id).metadata.procedural.parts==1)
assert(model:undo() and #model:get_object(o.id).metadata.procedural.parts==3,'undo restores the previous geometry')
o=model:get_object(o.id)

-- Too many colliders is refused before anything changes.
local objects=#model.data.objects
assert(not P:create({generator='stairs',params={height=20,length=30,steps=200,width=2,landing=1,stringers=true},transform=T,collision=true}))
assert(#model.data.objects==objects)

-- Placement delegates to the preview; runtime comparison ignores preview shapes.
assert(app.placement:despawn(o) and not P:is_shown(o))
assert(app.placement:spawn(o) and P:is_shown(o))
local cmp=app.placement:compare_runtime();for _,item in ipairs(cmp.items) do assert(item.id:sub(1,7)~='__proc_') end

-- Export scope: procedural objects are left to Build Mod.
local scoped=app.build_export:_objects({premise_id=premise.id})
for _,s in ipairs(scoped) do assert(not s.metadata.procedural) end
assert(#app.build_export.last_procedural==1 and app.build_export.last_procedural[1].mesh_path==made.mesh_path)

-- Preflight: a missing material template blocks.
local plain=assert(P:create({generator='box',params={size={2,2,0.3}},transform=T}))
local rp;for _,c in ipairs(app.preflight:run({}).checks) do if c.id=='resource_paths' then rp=c end end
local found=false;for _,i in ipairs(rp.issues) do if i.object_id==plain.object.id and i.message:find('material.template',1,true) then found=true end;assert(i.object_id~=o.id,'a complete procedural object passes') end
assert(found)
for _,c in ipairs(app.preflight:run({}).checks) do if c.id=='cet_entities' then for _,i in ipairs(c.issues) do assert(i.object_id~=o.id) end end end

-- Native mesh materials: slot -> .mi, validated; preflight wants glass mapped when the geometry has glass.
assert(not P:create({generator='box',params={size={1,1,1}},transform=T,material={materials={main='base\\a.png'}}}))
assert(not P:create({generator='box',params={size={1,1,1}},transform=T,material={materials={roof='base\\a.mi'}}}))
assert(not P:create({generator='box',params={size={1,1,1}},transform=T,material={materials={glass='base\\g.mi'}}}))
local native=assert(P:create({generator='window',params={},transform=T,material={materials={main='base\\frame.mi'}}}))
local rp2;for _,c in ipairs(app.preflight:run({}).checks) do if c.id=='resource_paths' then rp2=c end end
local glass_issue=false;for _,i in ipairs(rp2.issues) do if i.object_id==native.object.id then assert(i.message:find('materials.glass',1,true));glass_issue=true end end
assert(glass_issue)
assert(P:update(native.object.id,{material={materials={main='base\\frame.mi',glass='base\\glass.mi'}}}))
for _,c in ipairs(app.preflight:run({}).checks) do if c.id=='resource_paths' then for _,i in ipairs(c.issues) do assert(i.object_id~=native.object.id) end end end

-- Settings.
assert(not P:set_settings({proxy='fog'}) and not P:set_settings({mesh_root='bad root!'}))
assert(P:set_settings({mesh_root='mod/mymod/geo/'}).mesh_root=='mod\\mymod\\geo')
assert(P:set_settings({proxy='none'}));assert(P:show(o).proxies==0);assert(P:set_settings({proxy='collision'}))

-- Delete removes colliders; undo brings them back.
local ids=model:get_object(o.id).metadata.procedural.collider_ids
assert(P:delete(o.id).colliders==#ids and not model:get_object(o.id) and not model:get_object(ids[1]))
assert(model:undo() and model:get_object(o.id) and model:get_object(ids[1]))

-- Bridge.
assert(assert(app.bridge:handle({id='g1',op='procedural_generators',args={}})).count==12)
assert(#assert(app.bridge:handle({id='g2',op='procedural_preview_parts',args={generator='door_frame',params={}}})).parts==3)
local bc=assert(app.bridge:handle({id='g3',op='procedural_create',args={generator='column',params={height=3},transform=T,material={template='base\\a.mesh'}}}))
assert(assert(app.bridge:handle({id='g4',op='procedural_update',args={id=bc.object.id,params={height=4}}})).bounds.max.z==4)
assert(assert(app.bridge:handle({id='g5',op='procedural_list',args={}})).count>=3)
assert(assert(app.bridge:handle({id='g6',op='procedural_show',args={id=bc.object.id,visible=false}})).hidden)
assert(assert(app.bridge:handle({id='g7',op='procedural_delete',args={id=bc.object.id}})).deleted)

-- Authoring plan v2 op.
local plan={format='locationstudio-authoring-plan',version=2,origin={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},steps={
    {op='create_premise',as='p',name='Plan geo'},
    {op='create_procedural',as='s',premise_id='$p',generator='stairs',params={height=1.8,length=2.7},offset={x=2,y=0,z=0},material={template='base\\a.mesh'}}}}
local res=assert(app.authoring_plans:execute(plan))
local st=model:get_object(res.aliases.s);assert(st.metadata.procedural.generator=='stairs' and close(st.transform.position.x,2))

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.ui.spatial.pg_gen='ramp';app.ui.spatial.pg_params='{"width": 2, "length": 3, "height": 0.5}';app.ui.spatial.pg_template='base\\a.mesh'
local before=#model.data.objects
env.clicks['CREATE AT V##pg']=true;env:draw()
assert(#model.data.objects>before,'UI created the ramp')
local sel=model:get_object(app.ui.spatial.pg_selected);assert(sel.metadata.procedural.generator=='ramp')
app.ui.spatial.pg_params='{"width": 2, "length": 6, "height": 0.5}'
env.clicks['APPLY PARAMETERS##pg']=true;env:draw()
assert(close(model:get_object(sel.id).metadata.procedural.bounds.max.y,6))
print('procedural_runtime_test: OK')
