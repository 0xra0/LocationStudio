local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local M=assert(app.material_library,'material library must be constructed')
local Lib=getmetatable(M).__index
local model=app.model
assert(model.data.schema_version==24 and type(model.data.material_defs)=='table')

-- Validation (pure).
assert(not Lib.normalize({}),'key required')
assert(not Lib.normalize({key='bad key'}))
assert(not Lib.normalize({key='a',preset='marble'}))
assert(not Lib.normalize({key='a',base='base\\x.mesh'}),'base must be a material')
assert(not Lib.normalize({key='a',path='mod\\a.mesh'}))
assert(not Lib.normalize({key='a',params={roughness=2}}))
assert(not Lib.normalize({key='a',params={tint={1,1}}}))
assert(not Lib.normalize({key='a',params={shininess=1}}),'unknown semantic parameter')
assert(not Lib.normalize({key='a',textures={base_color='base\\a.png'}}),'textures are .xbm')
assert(not Lib.normalize({key='a',textures={base_color={file='C:/t/a.bmp'}}}))
assert(not Lib.normalize({key='a',textures={base_color={solid={2,0,0}}}}))
assert(not Lib.normalize({key='a',preset='glass',textures={base_color='base\\a.xbm'}}),'glass has no base colour texture')
assert(not Lib.normalize({key='a',preset='glass',params={metallic=1}}))
assert(not Lib.normalize({key='a',overrides={Foo={type='Matrix',value=1}}}))
assert(not Lib.normalize({key='a',base='base\\custom.mt',params={roughness=0.5}}),'custom takes overrides only')
assert(not Lib.normalize({key='a',variants={{name='Dirty'}}}),'variant names are lowercase')
assert(not Lib.normalize({key='a',variants={{name='default'}}}))
assert(not Lib.normalize({key='a',variants={{name='x'},{name='x'}}}))
assert(not Lib.normalize({key='a',variants={{name='x',params={uv_scale=2}}}}),'UVs cannot vary per variant')

local d=assert(Lib.normalize({key='tile',params={roughness=0.6,tint={1,0.9,0.8},uv_scale=2,tiling={2,1}},
    textures={base_color={solid={0.5,0.5,0.5}},normal='base\\surfaces\\n.xbm'},overrides={Foo={type='Float',value=2}},
    variants={{name='dirty',params={roughness=0.9}}}}))
assert(d.preset=='metal_base' and d.base=='base\\materials\\metal_base.remt' and d.path=='mod\\locationstudio\\materials\\tile.mi')
assert(d.params.tint[4]==1 and d.params.uv_scale[1]==2 and d.params.uv_scale[2]==2 and d.params.tiling[2]==1)
assert(d.textures.base_color.solid[4]==1 and d.textures.base_color.size==4)
assert(d.variants[1].path=='mod\\locationstudio\\materials\\tile_dirty.mi')
local custom=assert(Lib.normalize({key='neon',base='base\\fx\\neon.mt',overrides={Glow={type='Color',value={1,0,1}}}}))
assert(custom.preset=='custom' and custom.overrides.Glow.value[4]==1)

-- Library CRUD: one undo each.
local premise=model:add_premise({name='Clinic',kind='interior',transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}})
app.selected_premise_id=premise.id
local h=#model.undo_stack
local tile=assert(M:create({key='tile',params={roughness=0.6},textures={base_color={solid={0.5,0.5,0.5}}},variants={{name='dirty',params={roughness=0.9}}}}))
assert(#model.undo_stack==h+1 and tile.id and M:get('@tile').key=='tile')
assert(not M:create({key='tile'}),'duplicate key')
assert(not M:create({key='other',path=tile.path}),'duplicate output path')
assert(M:create({key='glass',preset='glass',params={tint={0.8,0.9,1,0.3},roughness=0.05}}))
assert(M:list().count==2)

-- Resolution.
assert(M:resolve('@tile').path==tile.path)
assert(M:resolve('@tile:dirty').path=='mod\\locationstudio\\materials\\tile_dirty.mi')
assert(not M:resolve('@tile:rusty') and not M:resolve('@nope') and not M:resolve('base\\a.mi'))

-- Procedural objects accept library references; unknown ones are refused.
local T={position={x=1,y=2,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}}
assert(not app.procedural:create({generator='box',params={size={1,1,1}},transform=T,material={materials={main='@nope'}}}))
local win=assert(app.procedural:create({generator='window',params={},transform=T,material={materials={main='@tile',glass='@glass'}}}))
assert(win.object.metadata.procedural.material.materials.main=='@tile')
local box=assert(app.procedural:create({generator='box',params={size={1,1,1}},transform=T}))
assert(M:assign(box.object.id,'main','@tile:dirty'))
assert(model:get_object(box.object.id).metadata.procedural.material.materials.main=='@tile:dirty')
assert(not M:assign(box.object.id,'roof','@tile') and not M:assign(box.object.id,'main','@nope'))
assert(#M:users('tile')==2)

-- Preflight: resolved references pass; a dangling one is an error.
local function rp_issues(id) local out={};for _,c in ipairs(app.preflight:run({}).checks) do if c.id=='resource_paths' then for _,i in ipairs(c.issues) do if i.object_id==id then out[#out+1]=i.message end end end end;return out end
assert(#rp_issues(win.object.id)==0,table.concat(rp_issues(win.object.id),'; '))
model:get_object(box.object.id).metadata.procedural.material.materials.main='@gone'
local issues=rp_issues(box.object.id);assert(#issues==1 and issues[1]:find('unknown material @gone',1,true),table.concat(issues,' | '))
model:get_object(box.object.id).metadata.procedural.material.materials.main='@tile:dirty'

-- Update: variants in use are protected; patch replaces; failure changes nothing.
assert(not M:update('tile',{variants={}}),'dirty is used by the box')
assert(not M:update('tile',{params={roughness=5}}))
assert(M:get('tile').params.roughness==0.6)
h=#model.undo_stack
local up=assert(M:update('tile',{params={roughness=0.4,metallic=1},variants={{name='dirty',params={roughness=0.95}},{name='wet',params={roughness=0.1}}}}))
assert(#model.undo_stack==h+1 and up.params.metallic==1 and #up.variants==2 and up.path==tile.path)
assert(model:undo() and M:get('tile').params.roughness==0.6 and #M:get('tile').variants==1)

-- Delete is refused while geometry uses it.
assert(not M:delete('tile'))
assert(M:assign(box.object.id,'main','') and M:assign(win.object.id,'main','@glass'))
assert(app.procedural:update(win.object.id,{material={materials={main='base\\frame.mi'}}}))
h=#model.undo_stack
assert(M:delete('tile').deleted=='tile' and #model.undo_stack==h+1 and not M:get('tile'))
assert(model:undo() and M:get('tile'))

-- Settings.
assert(not M:set_settings({root='bad root!'}))
assert(M:set_settings({root='mod/clinic/mats/'}).root=='mod\\clinic\\mats')
assert(assert(M:create({key='floor'})).path=='mod\\clinic\\mats\\floor.mi')

-- Bridge.
assert(#assert(app.bridge:handle({id='m1',op='material_presets',args={}})).items==4)
local bc=assert(app.bridge:handle({id='m2',op='material_create',args={definition={key='steel',params={metallic=1,roughness=0.3},variants={{name='rusty',params={roughness=0.8}}}}}}))
assert(bc.key=='steel')
assert(assert(app.bridge:handle({id='m3',op='material_update',args={key='steel',patch={params={metallic=0.9}}}})).params.metallic==0.9)
assert(assert(app.bridge:handle({id='m4',op='material_list',args={}})).count==4)
assert(assert(app.bridge:handle({id='m5',op='material_assign',args={object_id=box.object.id,slot='main',material='@steel:rusty'}})).material=='@steel:rusty')
local got=assert(app.bridge:handle({id='m6',op='material_get',args={key='steel'}}))
assert(#got.users==1 and got.users[1].id==box.object.id)
assert(not app.bridge:handle({id='m7',op='material_delete',args={key='steel'}}))
assert(assert(app.bridge:handle({id='m8',op='material_delete',args={key='floor'}})).deleted=='floor')

-- Parametric rooms take @key materials.
local room=assert(app.room_generator:create({spec={name='Tiled',width=4,length=4,windows={{wall='north'}},materials={walls='@steel',floor='@tile:dirty',frame='@steel',glass='@glass'}},premise_id=premise.id,transform=T}))
local rec=app.room_generator:get(room.room.id)
assert(model:get_object(rec.piece_ids.walls).metadata.procedural.material.materials.main=='@steel')
assert(model:get_object(rec.piece_ids.windows).metadata.procedural.material.materials.glass=='@glass')
assert(not app.room_generator:create({spec={materials={walls='@missing'}},premise_id=premise.id,transform=T}),'unknown material fails the room')

-- Authoring plan v2 op (validated before running).
local plan={format='locationstudio-authoring-plan',version=2,origin={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},steps={
    {op='create_material',key='plan_mat',preset='glass',params={opacity=0.4}},
    {op='create_premise',as='p',name='Plan Premise'},
    {op='create_procedural',as='g',premise_id='$p',generator='box',params={size={1,1,1}},offset={x=0,y=0,z=0},material={materials={main='@plan_mat'}}}}}
assert(app.authoring_plans:execute(plan))
assert(M:get('plan_mat') and M:get('plan_mat').params.opacity==0.4)
assert(not app.authoring_plans:validate({format='locationstudio-authoring-plan',version=2,steps={{op='create_material',key='x',params={opacity=4}}}}).valid)
assert(not app.authoring_plans:validate({format='locationstudio-authoring-plan',version=1,steps={{op='create_material',key='y'}}}).valid,'v2 only')

-- UI: add, select, assign.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
app.ui.spatial.mat_def='{"key":"ui_mat","params":{"roughness":0.5},"variants":[{"name":"worn","params":{"roughness":0.8}}]}'
env.clicks['ADD MATERIAL##mat']=true;env:draw()
assert(M:get('ui_mat') and app.ui.spatial.mat_selected=='ui_mat')
app.selection:set('object',box.object.id)
env.clicks['ASSIGN TO MAIN##mat']=true;env:draw()
assert(model:get_object(box.object.id).metadata.procedural.material.materials.main=='@ui_mat')
env.clicks['@ui_mat:worn##matv_worn']=true;env:draw()
assert(model:get_object(box.object.id).metadata.procedural.material.materials.main=='@ui_mat:worn')

print('LocationStudio material library: OK')
