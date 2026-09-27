local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local P=app.procedural
local Csg=require('modules/csg')
local model=app.model
local function close(a,b,eps) return math.abs(a-b)<(eps or 1e-6) end
local function volume(parts,material) local v=0;for _,p in ipairs(parts) do if not material or p.material==material then v=v+p.size.x*p.size.y*p.size.z end end;return v end
local function B(c,s,extra) local b={shape='box',center=c,size=s};for k,v in pairs(extra or {}) do b[k]=v end;return b end
local function gen(tree,res) return P.generate('csg',{tree=tree,resolution=res}) end

-- Wall - doorway - window: exact for axis-aligned boxes.
local wall=assert(gen({op='subtract',children={B({0,0,1.5},{5,0.2,3}),B({-1.2,0,1.05},{1,0.4,2.1}),B({1.1,0,1.6},{1.4,0.4,1.2})}}))
assert(close(volume(wall.parts),(15-2.1-1.68)*0.2),'exact volume '..volume(wall.parts))
assert(wall.stats.csg.approximate==false and wall.stats.csg.boxes==#wall.parts and #wall.parts<=8,#wall.parts)
assert(close(wall.bounds.min.x,-2.5) and close(wall.bounds.max.z,3) and close(wall.bounds.min.y,-0.1))
assert(wall.csg.tree.op=='subtract' and #wall.csg.tree.children==3 and wall.csg.tree.children[2].center.x==-1.2)
assert(wall.parts.csg==nil,'the csg info is not left on the parts list')

-- Union and intersect.
local l=assert(gen({op='union',children={B({0,0,0.5},{4,2,1}),B({1,2,0.5},{2,4,1})}}))
assert(close(volume(l.parts),8+8-2),'overlap counted once')
local i=assert(gen({op='intersect',children={B({0,0,0.5},{4,2,1}),B({1,2,0.5},{2,4,1})}}))
assert(close(volume(i.parts),2) and close(i.bounds.min.x,0) and close(i.bounds.max.y,1))
assert(not gen({op='intersect',children={B({0,0,0},{1,1,1}),B({5,0,0},{1,1,1})}}),'empty intersection')
assert(not gen({op='subtract',children={B({0,0,0},{1,1,1}),B({0,0,0},{2,2,2})}}),'nothing left')

-- Curved cutters are approximated on the grid; finer resolution converges.
local tunnel={op='subtract',children={B({0,0,2},{6,4,4}),{shape='cylinder',center={0,0,2},radius=1.5,length=4.2}}}
local coarse=assert(gen(tunnel,0.5));local fine=assert(gen(tunnel,0.1))
local exact=6*4*4-math.pi*1.5^2*4
assert(coarse.stats.csg.approximate and fine.stats.csg.resolution==0.1)
assert(math.abs(volume(fine.parts)-exact)<math.abs(volume(coarse.parts)-exact)+1e-9 and math.abs(volume(fine.parts)-exact)/exact<0.02,
    'fine '..volume(fine.parts)..' vs '..exact)
local sphere=assert(gen({op='union',children={{shape='sphere',center={0,0,0},radius=1}}},0.05))
assert(math.abs(volume(sphere.parts)-4/3*math.pi)/(4/3*math.pi)<0.05)
-- Too many cells: the grid coarsens instead of failing.
local big=assert(gen({op='subtract',children={B({0,0,0},{40,40,4}),{shape='sphere',center={0,0,0},radius=15}}},0.02))
assert(big.stats.csg.resolution>0.02)

-- Wedge (slope rises towards +y) and axis-aligned rotated boxes stay exact.
local w=assert(gen({op='union',children={{shape='wedge',center={0,0,0.5},size={1,2,1}}}},0.05))
assert(math.abs(volume(w.parts)-1)<0.06)
local turned=assert(gen({op='subtract',children={B({0,0,0.5},{4,1,1},{rotation={yaw=90}}),B({0,1,0.5},{2,0.5,2})}}))
assert(turned.stats.csg.approximate==false and close(volume(turned.parts),4-0.5))

-- Prisms: axis-aligned L exact; oblique edges approximate.
local lp=assert(gen({op='union',children={{shape='prism',points={{0,0},{3,0},{3,1},{1,1},{1,3},{0,3}},z0=0,z1=2}}}))
assert(lp.stats.csg.approximate==false and close(volume(lp.parts),(3+2)*2))
local tri=assert(gen({op='union',children={{shape='prism',points={{0,0},{2,0},{0,2}},z0=0,z1=1}}},0.05))
assert(tri.stats.csg.approximate and math.abs(volume(tri.parts)-2)<0.1)

-- Repeat (vents) and generator leaves.
local vents=assert(gen({op='subtract',children={B({0,0,1},{1.2,0.05,0.6}),B({-0.45,0,1},{0.06,0.2,0.4},{['repeat']={count=8,step={0.12,0,0}}})}}))
assert(close(volume(vents.parts),1.2*0.05*0.6-8*0.06*0.05*0.4))
assert(#vents.csg.tree.children[2].children==8)
local stairs_cut=assert(gen({op='subtract',children={{generator='box',params={size={4,4,3}}},{generator='wall',params={length=2,height=1,thickness=0.5},offset={0,2,0},rotation={yaw=0}}}}))
assert(close(volume(stairs_cut.parts),4*4*3-2*1*0.25),'generator leaves are placed and cut: '..volume(stairs_cut.parts))
-- Glass keeps its material; cut faces default to the solid's.
local rw=assert(gen({op='union',children={{op='subtract',children={B({0,0,1.5},{3,0.2,3}),B({0,0,1.6},{1,0.4,1})}},B({0,0,1.6},{1,0.02,1},{material='glass'})}}))
assert(close(volume(rw.parts,'glass'),0.02) and close(volume(rw.parts,'main'),(9-1)*0.2))

-- Validation.
assert(not gen({op='xor',children={B({0,0,0},{1,1,1})}}))
assert(not gen({op='subtract',children={B({0,0,0},{1,1,1})}}),'subtract needs two')
assert(not gen({op='union',children={{shape='cone',center={0,0,0}}}}))
assert(not gen({op='union',children={B({0,0,0},{0,1,1})}}))
assert(not gen({op='union',children={{generator='csg',params={}}}}),'no nested csg generator')
assert(not gen({op='union',children={{generator='nope'}}}))
assert(not gen({op='union',children={{generator='wall',params={length=-1}}}}))
assert(not gen({op='union',children={B({0,0,0},{1,1,1},{['repeat']={count=500,step={1,0,0}}})}}))
assert(not P.generate('csg',{tree={op='union',children={B({0,0,0},{1,1,1})}},resolution=5}))
assert(not P.generate('csg',{}))
local deep={shape='box',center={0,0,0},size={1,1,1}};for _=1,20 do deep={op='union',children={deep}} end
assert(not gen(deep),'depth limit')

-- Procedural objects: saved tree, colliders from the boxes, one undo, update.
local premise=model:add_premise({name='Bunker',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
local T={position={x=10,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}
local h=#model.undo_stack
local made=assert(P:create({generator='csg',params={tree={op='subtract',children={B({0,0,1.5},{5,0.2,3}),B({-1.2,0,1.05},{1,0.4,2.1})}}},transform=T,collision=true,material={materials={main='base\\wall.mi'}}}))
assert(#model.undo_stack==h+1)
local cfg=made.object.metadata.procedural
assert(cfg.csg and cfg.csg.tree.op=='subtract' and cfg.csg.approximate==false and cfg.stats.csg.boxes==#cfg.parts)
assert(#cfg.collider_ids==#cfg.parts and made.colliders==#cfg.parts)
assert(made.object.metadata.asset_bounds.max.x==2.5)
local up=assert(P:update(made.object.id,{params={tree={op='subtract',children={B({0,0,1.5},{5,0.2,3}),B({1,0,1.05},{1,0.4,2.1}),B({-1,0,1.6},{1,0.4,1})}}},replace_params=true}))
assert(#model:get_object(made.object.id).metadata.procedural.csg.tree.children==3 and up.parts>=#cfg.parts)
assert(P:update(made.object.id,{generator='box',params={size={1,1,1}},replace_params=true}))
assert(model:get_object(made.object.id).metadata.procedural.csg==nil,'switching generator drops the tree')
assert(not P:update(made.object.id,{generator='csg',params={tree={op='xor'}},replace_params=true}))
-- JSON round trip of the saved object (no mixed tables).
local enc=json.encode(model:get_object(made.object.id));assert(enc and #enc>0)

-- Examples file.
local examples=Csg.examples()
local ids={};for _,e in ipairs(examples) do ids[#ids+1]=e.id end
assert(#examples==9,table.concat(ids,','))
for _,e in ipairs(examples) do local r,err=gen(e.tree,0.1);assert(r,e.id..': '..tostring(err)) end

-- Bridge and plan.
local pv=assert(app.bridge:handle({id='c1',op='procedural_preview_parts',args={generator='csg',params={tree={op='subtract',children={B({0,0,0.5},{2,2,1}),B({0,0,0.5},{1,1,2})}}}}}))
assert(close(volume(pv.parts),3) and pv.stats.csg.boxes==#pv.parts)
local plan={format='locationstudio-authoring-plan',version=2,origin={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},steps={
    {op='create_premise',as='p',name='CSG plan'},
    {op='create_procedural',as='g',premise_id='$p',generator='csg',params={tree={op='subtract',children={B({0,0,2},{6,6,4}),B({0,0,2},{5.6,5.6,3.6})}}},offset={x=0,y=0,z=0},material={template='base\\a.mesh'}}}}
assert(app.authoring_plans:execute(plan))

-- UI: example button fills the parameters; create.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.ui.spatial.pg_gen='csg';app.ui.spatial.pg_template='base\\a.mesh'
env:draw()
env.clicks['wall_door_window##csgex_wall_door_window']=true;env:draw()
assert(app.ui.spatial.pg_params:find('subtract',1,true))
local before=#model.data.objects
env.clicks['CREATE AT V##pg']=true;env:draw()
assert(#model.data.objects>before and model:get_object(app.ui.spatial.pg_selected).metadata.procedural.generator=='csg')

print('LocationStudio CSG: OK')
