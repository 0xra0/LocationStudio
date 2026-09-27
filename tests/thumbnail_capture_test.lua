local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local thumb=app.thumbnails;local asset=app.model:get_asset('builtin_chair_poor')
local Util=require('modules/util')
local final_path=thumb:path(asset)
assert(Util.write_file(final_path,string.rep('old-image-',16)))
local old=Util.read_file(final_path)
thumb._capture_backend=function() return 'mock_capture','test-helper' end
local execute=os.execute
os.execute=function() return 127 end
local failed,err=thumb:capture(asset.id)
assert(not failed and err,'failed helper launch was reported as success')
assert(Util.read_file(final_path)==old,'failed capture destroyed old thumbnail')
assert(app.editor_visible)
os.execute=function() return 0 end
local pending=assert(thumb:capture(asset.id))
assert(not app.editor_visible and app.config.window_open,'capture must hide editor_visible, not obsolete config flag')
assert(Util.write_file(pending.path,string.rep('new-image-',16)))
local captured=assert(thumb:update(os.clock()))
assert(captured.path==final_path and app.editor_visible)
assert(Util.read_file(final_path)~=old and Util.read_file(final_path..'.bak')==old)
os.execute=nil
local blocked,message=thumb:capture(asset.id)
assert(not blocked and message:find('sandbox',1,true))
assert(app.editor_visible)
os.execute=execute
print('Thumbnail visibility, failed launch, safe replacement and sandbox guard: OK')
