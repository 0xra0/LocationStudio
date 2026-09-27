local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
assert(app.version=='0.63.0')
local asset=assert(app.model:get_asset('builtin_chair_poor'))
local premise=assert(app.model:add_premise({name='Bounds Test'}))
local base={min={x=-1,y=-0.5,z=-0.5},max={x=1,y=0.5,z=0.5},units='m'}

local dry=assert(app.asset_bounds:import_manifest({dry_run=true,manifest={
    format='locationstudio-asset-bounds/1',source='unit-test',assets={{asset_id=asset.id,bounds=base}},
}}))
assert(dry.dry_run and dry.count==1 and not asset.metadata.asset_bounds)
local history_before=#app.model.undo_stack
local imported=assert(app.asset_bounds:import_manifest({manifest={
    format='locationstudio-asset-bounds/1',source='unit-test',assets={{asset_id=asset.id,bounds=base}},
}}))
assert(imported.count==1 and imported.assets[1].bounds.dimensions.x==2)
assert(asset.metadata.asset_bounds.source=='unit-test' and #app.model.undo_stack==history_before+1)

local object=assert(app.model:add_object({name='Bounded Chair',kind='prop',template=asset.template,size={x=1,y=1,z=1},
    transform={position={x=0,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=90}},
    metadata={locationstudio_asset_id=asset.id,asset_bounds=asset.metadata.asset_bounds}}))
app.dirty=false
local edited=assert(app.asset_bounds:set(asset.id,{min={x=-2,y=-1,z=-0.5},max={x=2,y=1,z=0.5},units='m'},'manual-test'))
assert(edited.has_bounds and edited.propagated_objects==1)
assert(object.metadata.asset_bounds.source=='manual-test' and object.metadata.asset_bounds.max.x==2)
local world=assert(app.asset_bounds:world_aabb(object.id)).aabb
assert(math.abs(world.min.x+1)<0.0001 and math.abs(world.max.x-1)<0.0001)
assert(math.abs(world.min.y+2)<0.0001 and math.abs(world.max.y-2)<0.0001)
local cet_hint=assert(app.model:add_object({name='Unscaled CET Hint',kind='prop',template=asset.template,size={x=10,y=10,z=10},
    transform={position={x=30,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},metadata={asset_bounds=asset.metadata.asset_bounds}}))
local cet_aabb=assert(app.asset_bounds:world_aabb(cet_hint.id)).aabb
assert(cet_aabb.max.x-cet_aabb.min.x==4,'CET size hint must not be mistaken for live scale')
local wb_scaled=assert(app.model:add_object({name='Scaled WB Bound',kind='mesh',template='base\\scaled.mesh',size={x=2,y=2,z=2},
    transform={position={x=40,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
    metadata={asset_bounds=asset.metadata.asset_bounds,world_builder={apply_scale=true}}}))
local wb_aabb=assert(app.asset_bounds:world_aabb(wb_scaled.id)).aabb
assert(wb_aabb.max.x-wb_aabb.min.x==8,'verified World Builder scale must affect bounds')

local other=assert(app.model:add_object({name='Second Bound',kind='prop',template=asset.template,size={x=1,y=1,z=1},
    transform={position={x=0.9,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
    metadata={asset_bounds=asset.metadata.asset_bounds}}))
local overlap=assert(app.asset_bounds:overlap({object.id,other.id}))
assert(overlap.tested==2 and overlap.overlap_count==1)
local invalid_margin,margin_err=app.asset_bounds:overlap({object.id,other.id},-0.1)
assert(not invalid_margin and margin_err:find('>= 0',1,true))
local far=assert(app.model:add_object({name='Far Bound',kind='prop',template=asset.template,size={x=1,y=1,z=1},
    transform={position={x=10,y=0,z=0,w=1},rotation={roll=0,pitch=0,yaw=0}},
    metadata={asset_bounds=asset.metadata.asset_bounds}}))
local no_overlap=assert(app.asset_bounds:overlap({object.id,far.id}))
assert(no_overlap.overlap_count==0)

local fit=assert(app.asset_bounds:fit(asset.id,{x=8,y=4,z=2},'stretch'))
assert(fit.suggested_asset_size.x==2 and fit.suggested_asset_size.y==2 and fit.suggested_asset_size.z==2)
assert(fit.scale_supported_by_backend==false and fit.warning)
local contain=assert(app.asset_bounds:fit(asset.id,{x=8,y=4,z=1},'contain'))
assert(math.abs(contain.suggested_asset_size.x-0.6363636)<0.001 and math.abs(contain.suggested_asset_size.y-0.6363636)<0.001 and contain.suggested_asset_size.z==1)

local bad,bad_err=app.asset_bounds:set(asset.id,{min={x=1,y=0,z=0},max={x=0,y=1,z=1}})
assert(not bad and bad_err:find('greater than',1,true))
local bad_import,bad_import_err=app.asset_bounds:import_manifest({manifest={format='locationstudio-asset-bounds/1',assets={
    {asset_id=asset.id,bounds=base},{asset_id=asset.id,bounds=base},
}}})
assert(not bad_import and bad_import_err:find('duplicate asset',1,true))

local info=assert(app.bridge:handle({id='bounds-info',op='wb_bounds_info',args={asset_id=asset.id}}))
assert(info.has_bounds and info.dimensions.x==4)
local bridge_fit=assert(app.bridge:handle({id='bounds-fit',op='wb_bounds_fit',args={asset_id=asset.id,target_size={x=4,y=2,z=1},mode='stretch'}}))
assert(bridge_fit.suggested_asset_size.x==1)
local bridge_aabb=assert(app.bridge:handle({id='bounds-aabb',op='wb_bounds_world_aabb',args={object_id=object.id}}))
assert(bridge_aabb.aabb.max.y==2)
local bridge_overlap=assert(app.bridge:handle({id='bounds-overlap',op='wb_bounds_overlap',args={object_ids={object.id,other.id}}}))
assert(bridge_overlap.overlap_count==1)
local bridge_import=assert(app.bridge:handle({id='bounds-import',op='wb_bounds_import',args={dry_run=true,manifest={format='locationstudio-asset-bounds/1',assets={{asset_id=asset.id,bounds=base}}}}}))
assert(bridge_import.dry_run)
local bridge_set=assert(app.bridge:handle({id='bounds-set',op='wb_bounds_set',args={asset_id=asset.id,bounds=base,source='bridge-test'}}))
assert(bridge_set.bounds.source=='bridge-test')

print('LocationStudio asset bounds import, editing, fit, and collision math: OK')
