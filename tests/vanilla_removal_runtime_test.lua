local root=... or '.'
local app={util={make_id=function(_,p) return p..'-1' end,now_iso=function() return '2026-01-01T00:00:00Z' end},model={data={vanilla_removals={}},touch=function() end},mark_dirty=function() end,logger={info=function() end}}
local visible=true
local target={resolved=true,nodeInstance={},nodeID=123,nodeDefinition={}}
local rht={
    status=function() return {plugin=true,ready=true} end,
    crosshair=function() return {targets={{node_id='123',nodeID='123',node_ref='$/node',node_type='worldMeshNode',is_node=true,is_visible_node=true,position={x=0,y=0,z=0},mesh_path='base/mesh.mesh'}}} end,
    scan=function(_,args) return {targets={{node_id='123',nodeID='123',node_ref='$/node',node_type='worldMeshNode',is_node=true,is_visible_node=true,position={x=0,y=0,z=0},mesh_path='base/mesh.mesh'}},radius=args.radius} end,
    removal_target=function() return {nodeID='123'},target end,
    toggle_node=function() visible=not visible;return true end,
}
app.rht_inspector=rht
local Removal=assert(loadfile(root..'/modules/vanilla_removal.lua'))()
local removal=Removal.new(app)
local one,err=removal:remove_crosshair({distance=10})
assert(one and not err and one.permanent==false,'crosshair removal should be reversible')
assert(#app.model.data.vanilla_removals==1,'removal record missing')
local restored=removal:restore(one.record.id)
assert(restored and visible==true,'restore did not toggle node back')
local many=removal:remove_nearby({radius=4})
assert(many and many.removed==1,'nearby removal failed')
local all=removal:restore_all()
assert(all.restored==1,'restore all failed')
print('vanilla_removal_runtime_test: OK')
