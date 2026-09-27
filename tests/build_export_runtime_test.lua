-- World Builder export contract: LS must hand WB its own serialized elements,
-- save them through WB's element.save, run WB's exporter, and restore the
-- user's Export-tab state. The fake mirrors WB 1.0.81 exportUI semantics.
local root=... or '.'
local Util=assert(loadfile(root..'/modules/util.lua'))()

local wb_files={}
local sectorCategory=nil
local function make_export_ui()
    local ui={projectName='user_project',xlFormat=1,groups={{name='user_group'}},exportIssues={nodeRefDuplicated={}}}
    function ui.exportGroup(group) return sectorCategory[group.category+1] end
    function ui.addGroup(name)
        local data={name=name,category=1,level=1,streamingX=150,streamingY=150,streamingZ=100}
        table.insert(ui.groups,data)
    end
    function ui.export()
        local group=ui.groups[1]
        assert(wb_files['data/objects/'..group.name..'.json'],'WB group file was not saved before export')
        wb_files['export/'..ui.projectName..'_exported.json']={name=ui.projectName,xlFormat=ui.xlFormat,category=ui.exportGroup(group),group=Util.deepcopy(group)}
    end
    return ui
end
local export_ui=make_export_ui()

local saved_list_reloads=0
local sUI={spawner={baseUI={savedUI={reload=function() saved_list_reloads=saved_list_reloads+1 end}}}}
-- element.save as written by WB: serialize, then write data/objects/<fileName>.json.
local function wb_element_save(self)
    local data=self:serialize()
    if self.fileName~=self.name then self.fileName=self.name end
    wb_files['data/objects/'..self.fileName..'.json']=data
    self.sUI.spawner.baseUI.savedUI.reload()
end
local function handle(name,x)
    return {sUI=sUI,save=wb_element_save,
        getPosition=function() return {x=x,y=0,z=0} end,
        serialize=function() return {name=name,modulePath='modules/classes/editor/spawnableElement',spawnable={modulePath='mesh/mesh',spawnData='base\\a.mesh'}} end}
end

local objects={
    {id='o1',name='Wall',premise_id='p1',runtime={backend='world_builder'}},
    {id='o2',name='Lamp',premise_id='p1',runtime={backend='world_builder'}},
    {id='o3',name='Chair',premise_id='p1',runtime={backend='cet'}},
    {id='o4',name='Other',premise_id='p2',runtime={backend='world_builder'}},
}
local app={
    model={data={objects=objects}},
    runtime_shell={handles={o1=handle('wall_wb',2),o2=handle('lamp_wb',4),o4=handle('other',100)}},
    scenes={member_object_ids=function(_,id) if id=='s1' then return {'o2'} end;return nil,'scene not found' end},
    world_builder={_mod=function() return {baseUI={exportUI=export_ui}} end},
}
local BuildExport=assert(loadfile(root..'/modules/build_export.lua'))()
local exporter=BuildExport.new(app)
local original_handles=app.runtime_shell.handles

local result,err=exporter:export({name='Bad Name'})
assert(not result and err:find('%[a%-z0%-9_%]'),'invalid name must be rejected')

-- WB builds sectorCategory only when its Export tab is drawn.
if type(debug)=='table' and type(debug.getupvalue)=='function' then
    result,err=exporter:export({name='demo',premise_id='p1',allow_skipped=true})
    assert(not result and err:find('Export tab'),'uninitialized WB sector categories must be reported: '..tostring(err))
end
sectorCategory={'Exterior','Interior'}

-- A CET-backed object in scope blocks the build unless explicitly allowed.
result,err=exporter:export({name='demo',premise_id='p1'})
assert(not result and err:find('Chair') and err:find('allow_skipped'),'skipped objects must be named: '..tostring(err))
assert(next(wb_files)==nil,'a refused export must not write WB files')

result,err=exporter:export({name='demo',premise_id='p1',allow_skipped=true,category=0,level=3,streaming={x=40}})
assert(result,err)
assert(result.exported==2 and #result.skipped==1 and result.skipped[1].id=='o3','wrong export/skip split')
local group=wb_files['data/objects/ls_demo.json']
assert(group and group.modulePath=='modules/classes/editor/positionableGroup','WB group blob missing')
assert(#group.childs==2 and group.childs[1].name=='Wall' and group.childs[2].name=='Lamp','children must be WB-serialized LS objects in model order')
assert(group.origin.x==3,'group origin should be the handle centroid')
assert(saved_list_reloads==1,'WB saved list should refresh once')
local exported=wb_files['export/demo_exported.json']
assert(exported and exported.xlFormat==0 and exported.category=='Exterior','WB exporter did not run with LS settings')
assert(exported.group.level==3 and exported.group.streamingX==40 and exported.group.streamingY==150,'group streaming overrides not applied')
assert(export_ui.projectName=='user_project' and export_ui.xlFormat==1 and export_ui.groups[1].name=='user_group' and #export_ui.groups==1,'user Export-tab state must be restored')
assert(result.world_builder_export_file=='export/demo_exported.json')

-- Scene scope.
result,err=exporter:export({name='scene_only',scene_id='s1'})
assert(result and result.exported==1 and #wb_files['data/objects/ls_scene_only.json'].childs==1,'scene scope failed: '..tostring(err))

-- Ambient reverb requires its area plus the complete outline-marker subgroup.
local zone_objects,zone_handles={},{}
local points={{x=0,y=0,z=0},{x=4,y=0,z=0},{x=4,y=3,z=0},{x=0,y=3,z=0}}
local zone_id='amb_zone'
local function add_zone_object(object,saved,x)
    table.insert(zone_objects,object)
    local h=handle(object.name,x);h.serialize=function() return {name=object.name,modulePath='modules/classes/editor/spawnableElement',spawnable=saved} end
    zone_handles[object.id]=h
end
for i,p in ipairs(points) do
    add_zone_object({id='m'..i,name='Outline '..i,premise_id='p1',transform={position=p},size={z=3},metadata={ambient_zone={id=zone_id,role='outline_marker',outline_group='ls_ambient_zone_outline'}},runtime={backend='world_builder'}},
        {modulePath='area/outlineMarker',position=p,height=3},i)
end
add_zone_object({id='a1',name='Room Reverb',premise_id='p1',transform={position={x=2,y=1.5,z=0}},size={z=3},metadata={ambient_zone={id=zone_id,role='area',outline_group='ls_ambient_zone_outline',height=3}},runtime={backend='world_builder'}},
    {modulePath='area/ambientArea',outlinePath='ls_ambient_zone_outline',markers={},height=0,trigger={}},5)
app.model.data.objects=zone_objects;app.runtime_shell.handles=zone_handles
result,err=exporter:export({name='reverb_room',premise_id='p1'})
assert(result,err)
local reverb_group=wb_files['data/objects/ls_reverb_room.json']
assert(#reverb_group.childs==2,'marker points should be nested under one positionable group')
local outline_group=reverb_group.childs[2]
assert(outline_group.modulePath=='modules/classes/editor/positionableGroup' and #outline_group.childs==4)
assert(reverb_group.childs[1].spawnable.outlinePath=='/ls_reverb_room/ls_ambient_zone_outline')
app.model.data.objects={zone_objects[5]};app.runtime_shell.handles={a1=zone_handles.a1}
result,err=exporter:export({name='broken_reverb',premise_id='p1'})
assert(not result and err:find('all four live World Builder outline markers',1,true),'incomplete ambient outline should block export')
app.model.data.objects=objects;app.runtime_shell.handles=original_handles

result,err=exporter:export({name='x',scene_id='missing'})
assert(not result and err:find('scene not found'),'missing scene must fail')

-- Nothing exportable.
result,err=exporter:export({name='none',object_ids={'o3'},allow_skipped=true})
assert(not result and err:find('No exportable'),'empty export must fail')

-- A WB exporter failure is surfaced and still restores Export-tab state.
export_ui.export=function() error('boom') end
result,err=exporter:export({name='fails',premise_id='p2'})
assert(not result and err:find('boom'),'exporter failure must surface')
assert(export_ui.projectName=='user_project' and #export_ui.groups==1,'state must be restored after failure')

-- Without World Builder.
app.world_builder={_mod=function() return nil end}
result,err=exporter:export({name='demo'})
assert(not result and err:find('World Builder'),'missing WB must be reported')
assert(exporter:status().available==false)

print('build_export_runtime_test: OK')
