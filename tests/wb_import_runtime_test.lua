local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app

local function leaf(name,module_path,extra)
    local spawnable={modulePath=module_path,position={x=1,y=2,z=3,w=0},rotation={roll=0,pitch=0,yaw=90},nodeRef='',primaryRange=100}
    for k,v in pairs(extra or {}) do spawnable[k]=v end
    return {name=name,modulePath='modules/classes/editor/spawnableElement',visible=true,childs={},spawnable=spawnable}
end
local function group(name,childs,extra)
    local g={name=name,modulePath='modules/classes/editor/positionableGroup',visible=true,isUsingSpawnables=true,
        origin={x=10,y=20,z=30},rotation={roll=0,pitch=0,yaw=45},childs=childs}
    for k,v in pairs(extra or {}) do g[k]=v end
    return g
end
local wall=leaf('Wall','mesh/mesh',{spawnData='base\\walls\\wall_a.mesh',scale={x=2,y=1,z=3},app='dirty',castShadows=1})
local chair=leaf('Chair','entity/entityTemplate',{spawnData='base\\chairs\\chair_a.ent',app='default'})
local hidden=leaf('Hidden','mesh/mesh',{spawnData='base\\walls\\wall_a.mesh'})
local unknown=leaf('Mystery','meta/notARealClass')
local build=group('Bar',{wall,group('Furniture',{chair,group('Stash',{hidden},{visible=false})}),unknown})

local importer=app.wb_import
local undo_depth=#app.model.undo_stack
local objects_before=#app.model.data.objects

-- Legacy and malformed builds are refused before any mutation.
local result,err=importer:import({source='old',build={name='Old',type='group',childs={}}})
assert(not result and err:find('Legacy'),'legacy build must be refused: '..tostring(err))
result,err=importer:import({source='x',build={name='X',modulePath='modules/classes/editor/spawnableElement'}})
assert(not result and err:find('root'),'non-group root must be refused')

-- Unsupported elements block the import unless explicitly allowed.
result,err=importer:import({source='bar',build=build})
assert(not result and err:find('Mystery') and err:find('allow_skipped'),'unknown class must be named: '..tostring(err))

-- Dry run reports the plan and changes nothing.
result,err=importer:import({source='bar',build=build,allow_skipped=true,dry_run=true})
assert(result and result.dry_run and result.objects==3 and result.groups==3 and #result.skipped==1,'dry run summary wrong: '..tostring(err))
assert(result.by_definition.mesh_static==2 and result.by_definition.entity_template==1)
assert(#app.model.data.objects==objects_before and #app.model.undo_stack==undo_depth,'dry run must not mutate')

result,err=importer:import({source='bar',build=build,allow_skipped=true,spawn=true})
assert(result,err)
assert(#result.object_ids==3 and #app.model.undo_stack==undo_depth+1,'import must be exactly one undo step')
local premise=app.model:get_premise(result.premise_id)
assert(premise and premise.name=='Bar' and premise.transform.position.x==10 and premise.transform.rotation.yaw==45,'premise not created from root group')

local by_name={}
for _,id in ipairs(result.object_ids) do local o=app.model:get_object(id);by_name[o.name]=o;assert(o.premise_id==premise.id) end
local w=by_name.Wall
assert(w.kind=='mesh' and w.template=='base\\walls\\wall_a.mesh' and w.appearance=='dirty','mesh fields not mapped')
assert(w.size.x==2 and w.size.z==3 and w.metadata.world_builder.apply_scale==true,'WB scale must become LS size')
assert(w.transform.position.z==3 and w.transform.rotation.yaw==90,'transform not taken from spawnable')
local entry=w.metadata.world_builder.entry
assert(entry.data.castShadows==1 and entry.data.modulePath=='mesh/mesh' and entry.name=='Wall','full WB spawnable must be kept as entry data')
assert(w.metadata.world_builder.imported_from.path=='/Bar/Wall')
assert(by_name.Chair.kind=='entity' and by_name.Chair.metadata.world_builder.apply_scale==false)
assert(by_name.Hidden.visible==false,'objects under a hidden WB group must import hidden')

-- Nesting: Bar > Furniture > Stash, each object in its immediate group.
local groups={}
for _,g in ipairs(app.model.data.object_groups) do if g.premise_id==premise.id then groups[g.name]=g end end
assert(groups.Bar and groups.Furniture and groups.Stash,'WB groups must become LS object groups')
assert(groups.Furniture.parent_id==groups.Bar.id and groups.Stash.parent_id==groups.Furniture.id,'group nesting lost')
assert(groups.Bar.object_ids[1]==w.id and groups.Furniture.object_ids[1]==by_name.Chair.id and groups.Stash.object_ids[1]==by_name.Hidden.id)
assert(groups.Stash.visible==false and groups.Bar.pivot.position.x==10)

-- Visible objects spawn through World Builder; hidden ones stay unspawned.
assert(result.spawned==2 and #result.spawn_failed==0,'spawn result wrong')
assert(w.runtime.backend=='world_builder' and not (by_name.Hidden.runtime and by_name.Hidden.runtime.spawned))

-- A second import of the same build is refused.
result,err=importer:import({source='bar',build=build,allow_skipped=true})
assert(not result and err:find('already imported'),'duplicate import must be refused')

-- Undo removes the whole import.
assert(app.model:undo())
assert(#app.model.data.objects==objects_before and app.model:get_premise(premise.id)==nil,'undo must remove the complete import')

-- A failure midway rolls back model and history.
local create=app.model.create_object_group
app.model.create_object_group=function() return nil,'injected group failure' end
local depth=#app.model.undo_stack
result,err=importer:import({source='bar2',build=build,allow_skipped=true})
app.model.create_object_group=create
assert(not result and err:find('rolled back'),'failure must report rollback')
assert(#app.model.data.objects==objects_before and #app.model.undo_stack==depth,'failed import must leave no trace')

print('wb_import_runtime_test: OK')
