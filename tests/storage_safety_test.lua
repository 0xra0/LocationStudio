local env=dofile(arg[2]..'/support/cet_mock.lua')
local app=env.app
local Util=require('modules/util')
local Storage=require('modules/storage')
local p=assert(app.actions:create_premise_from_player('Original project'))
assert(app:save(true))
local original=assert(Util.read_file('data/project.json'))
app.model.data.project.name='New project'
assert(app:save(true));assert(Util.read_file('data/project.json.bak')==original)
local loaded=Storage.new():load_model();assert(loaded.data.project.name=='New project')
local before=Util.read_file('data/project.json')
local rename=os.rename
os.rename=function(a,b) if a=='data/project.json.tmp' then return nil,'injected disk failure' end;return rename(a,b) end
local saved,save_err=app:save(true)
assert(not saved and save_err);assert(Util.read_file('data/project.json')==before,'commit failure destroyed original')
os.rename=rename
assert(Util.write_file('data/project.json','{corrupted'))
local ok,err=pcall(function() Storage.new():load_model() end)
assert(not ok and tostring(err):find('preserved',1,true))
assert(Util.read_file('data/project.json')=='{corrupted','invalid project was silently overwritten')
local guarded,value,message,tail=app.logger:guard('test_nil',function() return nil,'expected error',37 end)
assert(guarded and value==nil and message=='expected error' and tail==37,'logger guard dropped nil-leading returns')
app.logger.max_bytes=300
for i=1,25 do app.logger:info('rotation',string.rep('x',80)) end
local f=assert(io.open('logs/locationstudio.log','r'));local size=f:seek('end');f:close()
assert(size<600 and Util.file_exists('logs/locationstudio.log.1'),'logs did not rotate during the session')
local ids={};bit32=nil
for i=1,1000 do local id=Util.make_id('stress');assert(not ids[id]);ids[id]=true end
print('Atomic save, corrupt input, logger rotation/returns, bit-free IDs: OK')
