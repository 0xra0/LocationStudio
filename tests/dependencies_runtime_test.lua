local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local D=assert(app.dependencies,'dependency report viewer must be constructed')

os.remove('exports/dependency-report.json')
assert(not D:load() and D.last_error:find('dependency_scan',1,true))

local chair=app.model:add_object({name='Chair',kind='mesh',template='',transform={position={x=1,y=2,z=3,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},
    metadata={world_builder={definition_key='mesh_static',resource_path='mymod\\props\\chair.mesh',entry={data={}}}}})
local lamp=app.model:add_object({name='Lamp',kind='mesh',template='',transform={position={x=1,y=2,z=3,w=1},rotation={roll=0,pitch=0,yaw=0}},size={x=1,y=1,z=1},metadata={}})
local report={schema='locationstudio-dependencies/1',ready=false,counts={project=3,vanilla=4,missing=2,unknown=1},objects_scanned=3,vanilla_index=true,
    missing={{path='mymod\\textures\\chair_d.xbm',chain={'object:'..chair.id,'mymod\\props\\chair.mesh','mymod\\textures\\chair_d.xbm'}},{path='#0000000000001234'}},
    unknown={{path='x'}},unverified={{reference='record:Character.base'}},ship={{path='mymod\\props\\chair.mesh'}},external_requirements={['othermod.archive']={'othermod\\a.mesh'}},
    objects={{object_id=chair.id,name='Chair',missing={'mymod\\textures\\chair_d.xbm'},unknown=0},
             {object_id=lamp.id,name='Lamp',missing={},unknown=1},
             {object_id='obj_gone',name='Deleted',missing={'#0000000000001234','a','b'},unknown=0}}}
local f=assert(io.open('exports/dependency-report.json','w'));f:write(json.encode(report));f:close()

local s=assert(D:load())
assert(s.ready==false and s.missing==2 and s.ship==1 and s.external_mods==1 and s.unverified==1)
local rows=assert(D:objects({}))
assert(rows.count==2 and rows.items[1].name=='Deleted' and rows.items[1].object_exists==false,'most missing first; deleted objects reported')
assert(D:objects({include_unknown=true}).count==3 and D:objects({all=true}).count==3)
local sel=assert(D:select(chair.id));assert(app.selected_object_id==chair.id and sel.missing[1]=='mymod\\textures\\chair_d.xbm')
assert(not D:select('obj_gone'))
assert(D:missing().count==2)

-- Bridge.
assert(assert(app.bridge:handle({id='d1',op='dependency_report_load',args={}})).missing==2)
assert(assert(app.bridge:handle({id='d2',op='dependency_report_objects',args={}})).count==2)
assert(assert(app.bridge:handle({id='d3',op='dependency_report_select',args={object_id=lamp.id}})).selected==lamp.id)

-- Wrong schema is rejected.
f=assert(io.open('exports/dependency-report.json','w'));f:write(json.encode({schema='other'}));f:close()
assert(not D:load() and D.report==nil)
f=assert(io.open('exports/dependency-report.json','w'));f:write(json.encode(report));f:close()

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['LOAD LATEST REPORT##deps']=true;env:draw()
assert(D.report,'report loaded from the tab')
app.selection:set('object',nil)
env.clicks['SELECT##depobj_2']=true;env:draw()
assert(app.selected_object_id==chair.id)
os.remove('exports/dependency-report.json')
print('dependencies_runtime_test: OK')
