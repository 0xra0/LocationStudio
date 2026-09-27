local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local si=assert(app.sector_inspector,'sector inspector module must be constructed')

os.remove('exports/sector-inspection.json')
assert(not si:load() and si.last_error:find('sector_inspect',1,true),'missing report explains how to create one')

local object=app.model:add_object({name='Stray lamp',kind='mesh',template='',transform={position={x=105,y=5,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
    size={x=1,y=1,z=1},metadata={world_builder={definition_key='mesh_static',entry={data={}}}}})
local report={schema='locationstudio-sector-inspection/1',export_name='demo',sector_count=2,node_count=3,device_count=1,ps_entry_count=1,matched_objects=1,
    flag_counts={error=1,warning=1,info=0},
    sectors={{name='demo_a',index=0,category='Interior',level=1,node_count=2,node_refs=1,devices=1,ps_entries=1,bounds={min={x=0,y=0,z=-5},max={x=10,y=10,z=5}}},
             {name='demo_b',index=1,category='Exterior',level=1,node_count=1,node_refs=0,devices=0,ps_entries=0,bounds={min={x=100,y=0,z=-5},max={x=110,y=10,z=5}}}},
    flags={{code='outside_sector_inside_other',severity='error',sector='demo_a',node_index=1,node_name='[Mesh] Stray lamp',suggested_sector='demo_b',object_id=object.id,message='likely wrong sector'},
           {code='duplicate_psid',severity='warning',sector=nil,psid='9001',message='PSID reused'},
           {code='outside_sector_bounds',severity='warning',sector='demo_b',node_index=0,node_name='[Mesh] Deleted',object_id='obj_gone',message='outside'}},
    likely_wrong_sector={{code='outside_sector_inside_other'}},
    cross_sector_references={{kind='node_ref',from_sector='demo_a',target_sector='demo_b',status='cross_sector',target_ref='$/demo/#terminal'}},
    nodes={{sector='demo_a',index=1,name='[Mesh] Stray lamp',object_id=object.id,flags={'outside_sector_inside_other'}}}}
local f=assert(io.open('exports/sector-inspection.json','w'));f:write(json.encode(report));f:close()

local summary=assert(si:load())
assert(summary.sector_count==2 and summary.flag_counts.error==1 and summary.likely_wrong_sector==1 and summary.cross_sector_references==1)
assert(si:flags({}).count==3)
assert(si:flags({severity='error'}).count==1 and si:flags({sector='demo_b'}).count==1)
local rows=si:flags({});assert(rows.items[1].object_exists==true and rows.items[3].object_exists==false)
assert(si:nodes_for_object(object.id).count==1)
local selected=assert(si:select_flagged(1));assert(selected.selected==object.id and app.selected_object_id==object.id)
assert(not si:select_flagged(2),'flags without an object cannot be selected')
assert(not si:select_flagged(3),'a deleted object is reported, not selected')

-- Bridge.
assert(assert(app.bridge:handle({id='s1',op='sector_report_load',args={}})).node_count==3)
assert(assert(app.bridge:handle({id='s2',op='sector_report_flags',args={severity='warning'}})).count==2)
assert(assert(app.bridge:handle({id='s3',op='sector_report_select',args={index=1}})).selected==object.id)

-- Wrong schema is rejected.
f=assert(io.open('exports/sector-inspection.json','w'));f:write(json.encode({schema='other'}));f:close()
assert(not si:load() and si.report==nil)
f=assert(io.open('exports/sector-inspection.json','w'));f:write(json.encode(report));f:close()

-- UI tab.
events.onOverlayOpen()
app.model.data.settings.workspace.beginner_mode=false;app.model.data.settings.workspace.panel='SPATIAL'
env.clicks['LOAD LATEST REPORT']=true;env:draw()
assert(si.report and env.labels['SELECT##secflag_1'],'flagged objects get a SELECT button')
app.selection:set('object',nil)
env.clicks['SELECT##secflag_1']=true;env:draw()
assert(app.selected_object_id==object.id)
os.remove('exports/sector-inspection.json')
print('sector_inspector_runtime_test: OK')
