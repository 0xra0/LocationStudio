local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local function call(op,args) return app.bridge:handle({id=op,op=op,args=args or {}}) end

-- Paths match case-insensitively, as WB depot paths do.
local record={category='Mesh',variant='Mesh',module_path='mesh/mesh',spawn_data='BASE\\environment\\architecture\\walls\\game_wall.mesh',name='x',file_name='game_wall.mesh'}
local result,err=call('import_catalog_asset',{record=record})
assert(result,err)
local asset=result.asset
assert(result.definition_key=='mesh_static' and result.already_registered==false)
local wb=asset.metadata.world_builder
assert(wb.definition_key=='mesh_static' and wb.resource_path=='base\\environment\\architecture\\walls\\game_wall.mesh','asset must carry the live WB catalog path, not the record text')
assert(type(wb.entry)=='table' and wb.entry.data.spawnData==wb.resource_path,'asset must keep the live WB entry')

local again=assert(call('import_catalog_asset',{record=record}))
assert(again.already_registered and again.asset.id==asset.id,'re-import must return the existing asset')

result,err=call('import_catalog_asset',{record={category='Mesh',variant='Mesh',spawn_data='base\\invented\\thing.mesh'}})
assert(not result and err:find('Not found in the loaded World Builder'),'unknown path must not become an asset: '..tostring(err))
result,err=call('import_catalog_asset',{record={category='Mesh',variant='Nope',spawn_data='x'}})
assert(not result and err:find('No LocationStudio World Builder definition'))

-- The imported asset is placeable through World Builder.
local premise=assert(app.actions:create_premise_from_player('Catalog premise'))
local object=assert(app.actions:place_asset(asset.id,'player',{premise_id=premise.id,spawn=true}))
assert(object.runtime and object.runtime.backend=='world_builder','catalog asset must spawn through World Builder')

print('catalog_import_runtime_test: OK')
