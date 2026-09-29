local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local S=assert(app.sector_partition,'the sector partitioner must be constructed')
local SP=getmetatable(S).__index
local model=app.model
model.max_history=100000 -- the test adds hundreds of objects; keep every step countable
local T=function(x,y,z,yaw) return {position={x=x,y=y,z=z,w=1},rotation={roll=0,pitch=0,yaw=yaw or 0}} end
local function fails(needle,res,err) assert(res==nil,'expected a failure: '..tostring(needle));assert(tostring(err):find(needle,1,true),'expected "'..needle..'" in: '..tostring(err)) end
assert(app.version=='0.83.0')

-- Parameters.
local P=assert(SP.normalize_params(nil))
assert(P.max_nodes==600 and P.max_extent==128 and P.w_connectivity==10)
fails('unknown partition parameter',SP.normalize_params({nodes=1}))
fails('max_nodes must be a number from 10 to 20000',SP.normalize_params({max_nodes=5}))
fails('min_nodes must be smaller than max_nodes',SP.normalize_params({max_nodes=20,min_nodes=20}))
assert(#S:parameters()==11)

-- Scope.
fails('give premise_id, room_ids, build_id or all=true',S:generate({}))
fails('premise not found',S:generate({premise_id='nope'}))
fails('no grammar build',S:generate({build_id='nope'}))
local empty=assert(model:add_premise({name='Empty',kind='interior',transform=T(0,0,0)}))
fails('nothing to partition',S:generate({premise_id=empty.id}))
fails('pin label',S:generate({premise_id=empty.id,pins={x='bad label'}}))
fails('base_name must match',S:generate({premise_id=empty.id,base_name='Bad Name'}))

-- A corridor of six rooms joined by doors; the first opens outside. 30 props each.
local premise=assert(model:add_premise({name='Wing',kind='interior',transform=T(0,0,0)}))
local rg=app.room_generator
local rooms={}
for i=1,6 do
    local doors={}
    if i>1 then doors[#doors+1]={wall='south',width=1} end
    if i<6 then doors[#doors+1]={wall='north',width=1} end
    if i==1 then doors[#doors+1]={wall='south',width=1} end
    rooms[i]=assert(rg:create({spec={name='Room '..i,width=6,length=4,doors=doors},premise_id=premise.id,transform=T(0,(i-1)*4.2,0)})).room
end
local room_index={};for i,r in ipairs(rooms) do room_index[r.id]=i end
local props={}
for i,r in ipairs(rooms) do
    for k=1,30 do
        local o=assert(model:add_object({premise_id=premise.id,room_id=r.id,name='Prop '..i..'.'..k,kind='prop',template='',transform=T(-2+(k%5)*0.8,(i-1)*4.2-1.2+math.floor(k/5)*0.4,0)}))
        props[#props+1]=o
    end
end
local in_scope=0;for _,o in ipairs(model.data.objects) do if o.premise_id==premise.id and o.enabled~=false then in_scope=in_scope+1 end end

-- Preview changes nothing and is deterministic.
local undo=#model.undo_stack
local params={max_nodes=90,min_nodes=10}
local pv=assert(S:generate({premise_id=premise.id,params=params,base_name='wing',dry_run=true}))
assert(pv.dry_run and pv.partition_id==nil and #model.undo_stack==undo and #model.data.sector_partitions==0,'a preview is a dry run')
local pv2=assert(S:generate({premise_id=premise.id,params=params,base_name='wing',dry_run=true}))
assert(#pv.sectors==#pv2.sectors)
for i,s in ipairs(pv.sectors) do
    assert(s.name==pv2.sectors[i].name and #s.object_ids==#pv2.sectors[i].object_ids,'partitioning is deterministic')
    for j,id in ipairs(s.object_ids) do assert(pv2.sectors[i].object_ids[j]==id) end
end

-- Budgets, completeness and contiguity along the doors.
assert(pv.stats.rooms==6 and pv.stats.cells==0,'every prop is in a room')
assert(#pv.sectors>=3,'180+ nodes at 90 per sector need at least 3 sectors: '..#pv.sectors)
local seen,total={},0
for i,s in ipairs(pv.sectors) do
    assert(s.name==string.format('wing_%02d',i))
    assert(s.node_count<=90,'sector over budget: '..s.node_count)
    assert(s.category=='interior')
    total=total+s.node_count
    for _,id in ipairs(s.object_ids) do assert(not seen[id],'object in two sectors');seen[id]=true end
    local idx={};for _,r in ipairs(s.rooms) do idx[#idx+1]=room_index[r.id] end;table.sort(idx)
    for k=2,#idx do assert(idx[k]==idx[k-1]+1,'sector rooms follow the doors: '..table.concat(idx,',')) end
    assert(s.streaming.x>=20 and s.streaming.y>=20,'streaming covers at least the preload distance')
end
assert(total==in_scope,'every object in scope is assigned once: '..total..' / '..in_scope)
-- The entry is the room with the outside door; sectors are in traversal order.
local first={};for _,r in ipairs(pv.sectors[1].rooms) do first[r.id]=true end
assert(first[rooms[1].id],'the first sector holds the entry room')
assert(pv.report.entry=='Room 1' and #pv.report.traversal==#pv.sectors)
-- Transitions: the doors a border cuts, on the traversal path.
assert(#pv.transitions==#pv.sectors-1,'a chain of sectors has one door transition per border')
for _,t in ipairs(pv.transitions) do assert(t.kind=='door' and t.on_traversal) end
local nb=pv.sectors[1].neighbours[1];assert(nb and nb.sector=='wing_02' and nb.reasons.door and nb.reasons.traversal)
-- Sectors see each other through the doors, so streaming reaches into the next one.
assert(#pv.sectors[1].visible_from>=1 and pv.sectors[1].visible_from[1]=='wing_02','adjacent sectors see through the door')

-- Bigger budget: one sector. Small sectors merge.
local one=assert(S:generate({premise_id=premise.id,params={max_nodes=1000},dry_run=true}))
assert(#one.sectors==1 and one.sectors[1].node_count==in_scope)
local merged=assert(S:generate({premise_id=premise.id,params={max_nodes=90,min_nodes=80},dry_run=true}))
for _,s in ipairs(merged.sectors) do assert(s.node_count<=90) end

-- Pins keep rooms together whatever the links.
local pinned=assert(S:generate({premise_id=premise.id,params=params,pins={[rooms[1].id]='ends',[rooms[6].id]='ends'},dry_run=true}))
local together=false
for _,s in ipairs(pinned.sectors) do local ids={};for _,r in ipairs(s.rooms) do ids[r.id]=true end;if ids[rooms[1].id] and ids[rooms[6].id] then together=(s.pin=='ends') end end
assert(together,'pinned rooms share a sector')
local warn=assert(S:generate({premise_id=premise.id,pins={missing='x'},dry_run=true}))
local found=false;for _,w in ipairs(warn.report.warnings) do if w:find('matches no room or object',1,true) then found=true end end;assert(found)

-- A room above the budget stays whole and is reported.
local big=assert(S:generate({room_ids={rooms[1].id},params={max_nodes=10,min_nodes=0},dry_run=true}))
local r1n=0;for _,o in ipairs(model.data.objects) do if o.room_id==rooms[1].id and o.enabled~=false then r1n=r1n+1 end end
assert(#big.sectors==1 and big.sectors[1].node_count==r1n,'big: '..#big.sectors..' '..tostring(big.sectors[1].node_count))
found=false;for _,w in ipairs(big.report.warnings) do if w:find('rooms are never split',1,true) then found=true end end;assert(found)

-- Generate: one undo step, a record, a report.
local r=assert(S:generate({premise_id=premise.id,params=params,base_name='wing'}))
assert(#model.undo_stack==undo+1 and r.partition_id,'generating is one undo step')
local rec=assert(S:get(r.partition_id))
assert(rec.format=='locationstudio.sector-partition.v1' and rec.base_name=='wing' and rec.scope.premise_id==premise.id and #rec.sectors==#pv.sectors)
local rep=assert(S:report(rec.id));assert(rep.stale==false and #rep.unassigned==0)
assert(S:summaries().count==1)
local where=assert(S:sector_of(rec.id,props[1].id));assert(where.sector=='wing_01')
fails('is not in partition',S:sector_of(rec.id,'nope'))
-- Changes make it stale; new objects are reported unassigned.
props[1].transform.position.x=props[1].transform.position.x+1
local extra=assert(model:add_object({premise_id=premise.id,room_id=rooms[3].id,name='Late prop',kind='prop',template='',transform=T(0,8.4,0)}))
rep=assert(S:report(rec.id));assert(rep.stale==true and rep.stale_hint and #rep.unassigned==1 and rep.unassigned[1]==extra.id)
local rr=assert(S:regenerate(rec.id,{params={max_nodes=100}}))
assert(rr.replaced and rr.partition_id==rec.id and S:get(rec.id).params.max_nodes==100 and S:get(rec.id).params.min_nodes==10,'params merge on regenerate')
assert(S:report(rec.id).stale==false)
assert(S:regenerate(rec.id,{pins={[rooms[2].id]='solo'}}));assert(S:get(rec.id).pins[rooms[2].id]=='solo')
assert(S:regenerate(rec.id,{pins={[rooms[2].id]=''}}));assert(S:get(rec.id).pins[rooms[2].id]==nil,'an empty pin removes it')

-- Busy: a transform edit blocks writes, not previews.
local ts=app.transform_session;local active=ts.is_active;ts.is_active=function() return true end
fails('Finish or cancel the active transform edit',S:generate({premise_id=premise.id}))
assert(S:generate({premise_id=premise.id,dry_run=true}),'a preview works during an edit')
ts.is_active=active

-- Export: one World Builder group per sector, through WB's own exporter.
local wb_files={};local sectorCategory={'Exterior','Interior'} -- named like WB's upvalue, which LS reads
local ui={projectName='user',xlFormat=1,groups={{name='user_group'}},exportIssues={}}
function ui.exportGroup(group) return sectorCategory[group.category+1] end
function ui.addGroup(name) table.insert(ui.groups,{name=name,category=0,level=1,streamingX=150,streamingY=150,streamingZ=100}) end
function ui.export() wb_files.export={name=ui.projectName,groups={}};for _,g in ipairs(ui.groups) do table.insert(wb_files.export.groups,{name=g.name,category=ui.exportGroup(g),streamingX=g.streamingX,streamingZ=g.streamingZ}) end end
local saved_wb,saved_handles=app.world_builder,app.runtime_shell.handles
local handles={}
local function handle(o)
    return {sUI={},getPosition=function() return o.transform.position end,
        save=function(self) wb_files[self.fileName]=self:serialize() end,
        serialize=function() return {name=o.name,modulePath='modules/classes/editor/spawnableElement',spawnable={modulePath='mesh/mesh'}} end}
end
for _,o in ipairs(model.data.objects) do if o.premise_id==premise.id then o.runtime={backend='world_builder'};handles[o.id]=handle(o) end end
app.world_builder={_mod=function() return {baseUI={exportUI=ui}} end};app.runtime_shell.handles=handles
rec=S:get(rec.id)
props[2].transform.position.x=props[2].transform.position.x+1
fails('regenerate it first',S:export({partition_id=rec.id}))
props[2].transform.position.x=props[2].transform.position.x-1
fails('name must match',S:export({partition_id=rec.id,name='Bad'}))
local ex=assert(S:export({partition_id=rec.id}))
assert(ex.name=='wing' and #ex.groups==#rec.sectors and ex.exported+#ex.procedural==rec.stats.nodes,'every node exported: '..ex.exported..' + '..#ex.procedural..' procedural / '..rec.stats.nodes)
local proc={};for _,x in ipairs(ex.procedural) do proc[x.id]=true end
assert(#wb_files.export.groups==#rec.sectors and wb_files.export.name=='wing')
for i,g in ipairs(wb_files.export.groups) do
    local s=rec.sectors[i]
    assert(g.name=='ls_'..s.name and g.category=='Interior','interior sectors use WB\'s Interior category')
    assert(g.streamingX==s.streaming.x and g.streamingZ==s.streaming.z,'streaming extents come from the partition')
    local want=0;for _,id in ipairs(s.object_ids) do if not proc[id] then want=want+1 end end
    assert(#wb_files['ls_'..s.name].childs==want,'each WB group holds its sector')
end
assert(ui.projectName=='user' and #ui.groups==1,'the user\'s Export-tab state is restored')
assert(S:get(rec.id).last_export.sectors==#rec.sectors)
local part=assert(S:export({partition_id=rec.id,name='wing_part',sectors={'wing_01'}}));assert(#part.groups==1)
fails('no sectors selected',S:export({partition_id=rec.id,sectors={'nope'}}))
app.world_builder,app.runtime_shell.handles=saved_wb,saved_handles

-- Thousands of loose generated nodes: spatial cells, within budget and size.
local yard=assert(model:add_premise({name='Yard',kind='exterior',transform=T(0,0,0)}))
local batch={}
for i=0,59 do for j=0,39 do batch[#batch+1]={premise_id=yard.id,name='Crate',kind='prop',template='',transform=T(1000+i*4,j*5,0)} end end
local added=assert(model:add_objects(batch,true))
local t0=os.clock()
local yr=assert(S:generate({premise_id=yard.id,params={max_nodes=400,max_extent=128,view_distance=40},dry_run=true}))
local secs=os.clock()-t0
assert(yr.stats.nodes==2400 and yr.stats.rooms==0 and yr.stats.cells>=8,'2400 loose nodes in cells: '..yr.stats.cells)
seen={}
for _,s in ipairs(yr.sectors) do
    assert(s.node_count<=400 and s.size.horizontal<=128,'sector within budget: '..s.node_count..' / '..s.size.horizontal)
    assert(s.category=='exterior')
    for _,id in ipairs(s.object_ids) do assert(not seen[id]);seen[id]=true end
end
assert(#yr.sectors>=6 and secs<60,'partitioning thousands of nodes stays fast: '..secs..' s')

-- Grammar builds: sectors in the same undo step, kept up to date, removed with the build.
local Gr=app.env_grammar
local doc={id='sec_test',start='Root',size={6,5,3},rules={Root={{room={}},{walls={sides={'south'},depth=0.5,['do']={{door={width=1}}}}}}}}
local u0=#model.undo_stack
local built=assert(Gr:generate({doc=doc,transform=T(0,300,0),build_id='secb',sectors=true}))
assert(built.sectors and built.sectors.partition_id,'sectors=true partitions the build: '..tostring(built.sectors and built.sectors.error))
assert(#model.undo_stack==u0+1,'the partition joins the build undo step')
local bp=S:get(built.sectors.partition_id);assert(bp.scope.build_id=='secb' and bp.stats.sectors==1)
local again=assert(Gr:regenerate('secb',{seed=5}))
assert(again.sectors and again.sectors.partition_id==bp.id and again.sectors.replaced,'regenerating the build regenerates its partition')
assert(model:undo());assert(S:get(bp.id),'undo returns to the first generation')
assert(model:undo());assert(not S:get(bp.id),'undo removes the build and its partition together')
assert(model:redo())
local off=assert(Gr:generate({doc=doc,transform=T(0,320,0),build_id='secc'}));assert(off.sectors==nil,'no partition unless asked')
local rm=assert(Gr:remove('secb'));assert(rm.sectors_removed==1 and not S:get(bp.id),'removing the build removes its partition')
assert(Gr:remove('secc'))

-- Delete.
local plain=assert(S:generate({room_ids={rooms[2].id}}));assert(S:get(plain.partition_id).base_name=='sector' and plain.sectors[1].name=='sector_01','a default base name is stored for export')
assert(S:delete(plain.partition_id))
local d=assert(S:delete(rec.id));assert(d.deleted==rec.id and not S:get(rec.id))
assert(model:undo() and S:get(rec.id),'deleting is undoable')

print('LocationStudio sector partitioner: rooms, cells, doors, visibility, traversal, budgets, pins, export and grammar builds: OK')
