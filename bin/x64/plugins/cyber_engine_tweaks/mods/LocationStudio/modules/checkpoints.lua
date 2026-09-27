local Util=require('modules/util')
local Model=require('modules/model')

local Checkpoints={}
Checkpoints.__index=Checkpoints

local COLLECTIONS={'objects','rooms','locations','premises','volumes','cameras','scenes','routes','object_groups','object_prefabs'}
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for k,v in pairs(a) do
        if k~='runtime' and k~='created_at' and k~='updated_at' and not same(v,b[k]) then return false end
    end
    for k in pairs(b) do if k~='runtime' and k~='created_at' and k~='updated_at' and a[k]==nil then return false end end
    return true
end
local function position(item)
    local t=item and item.transform or {};return t.position or {}
end
local function rotation(item)
    local t=item and item.transform or {};return t.rotation or {}
end
local function moved(a,b)
    local p,q=position(a),position(b)
    for _,k in ipairs({'x','y','z'}) do if math.abs((tonumber(p[k]) or 0)-(tonumber(q[k]) or 0))>0.001 then return true end end
    local r,s=rotation(a),rotation(b)
    for _,k in ipairs({'roll','pitch','yaw'}) do if math.abs((tonumber(r[k]) or 0)-(tonumber(s[k]) or 0))>0.01 then return true end end
    return false
end
local function label(item) return tostring(item.name or item.asset_name or item.id or 'Unnamed') end

function Checkpoints.new(app)
    return setmetatable({app=app,index_path='data/checkpoints.json',prefix='data/checkpoint_'},Checkpoints)
end
function Checkpoints:_index()
    local data=Util.json_read(self.index_path,{schema_version=1,items={}})
    if type(data.items)~='table' then data={schema_version=1,items={}} end
    return data
end
function Checkpoints:_path(id)
    if type(id)~='string' or not id:match('^[%w_%-]+$') then return nil end
    return self.prefix..id..'.json'
end
function Checkpoints:_load(id)
    local path=self:_path(id);if not path then return nil,'invalid checkpoint id' end
    local data=Util.json_read(path,nil)
    if not data or type(data.checkpoint)~='table' or type(data.checkpoint.project)~='table' then return nil,'checkpoint file is missing or invalid: '..id end
    return data.checkpoint
end
function Checkpoints:list()
    local out={}
    for _,item in ipairs(self:_index().items) do
        if self:_path(item.id) and Util.file_exists(self:_path(item.id)) then out[#out+1]=Util.deepcopy(item) end
    end
    return {checkpoints=out,count=#out}
end
function Checkpoints:create(args)
    args=args or {};local name=Util.trim(args.name)
    if name=='' then return nil,'checkpoint name is required' end
    if #name>80 then return nil,'checkpoint name must be 80 characters or fewer' end
    local idx=self:_index()
    for _,item in ipairs(idx.items) do if string.lower(item.name)==string.lower(name) then return nil,'a checkpoint with this name already exists' end end
    local id=Util.make_id('checkpoint');local project=Util.deepcopy(self.app.model.data)
    for _,object in ipairs(project.objects or {}) do object.runtime=nil end
    local row={id=id,name=name,description=Util.trim(args.description),created_at=Util.now_iso(),object_count=#(project.objects or {}),room_count=#(project.rooms or {}),scene_count=#(project.scenes or {})}
    local ok,err=self.app.storage:atomic_write(self:_path(id),{checkpoint={schema_version=1,id=id,name=name,description=row.description,created_at=row.created_at,project=project}})
    if not ok then return nil,'could not write checkpoint: '..tostring(err) end
    idx.items[#idx.items+1]=row
    ok,err=self.app.storage:atomic_write(self.index_path,idx)
    if not ok then pcall(os.remove,self:_path(id));return nil,'could not update checkpoint index: '..tostring(err) end
    return row
end
function Checkpoints:diff(id_a,id_b)
    local a,err=self:_load(id_a);if not a then return nil,err end
    local b,err2=self:_load(id_b);if not b then return nil,err2 end
    local result={from={id=a.id,name=a.name},to={id=b.id,name=b.name},collections={}}
    for _,collection in ipairs(COLLECTIONS) do
        local old,new={},{}
        for _,item in ipairs((a.project[collection] or {})) do if item.id then old[item.id]=item end end
        for _,item in ipairs((b.project[collection] or {})) do if item.id then new[item.id]=item end end
        local row={added={},removed={},moved={},changed={}}
        for id,item in pairs(new) do
            local before=old[id]
            if not before then row.added[#row.added+1]={id=id,name=label(item)}
            elseif collection=='objects' and moved(before,item) then
                row.moved[#row.moved+1]={id=id,name=label(item),from=Util.deepcopy(position(before)),to=Util.deepcopy(position(item)),rotation_changed=not same(rotation(before),rotation(item))}
            elseif not same(before,item) then row.changed[#row.changed+1]={id=id,name=label(item)} end
        end
        for id,item in pairs(old) do if not new[id] then row.removed[#row.removed+1]={id=id,name=label(item)} end end
        table.sort(row.added,function(x,y)return x.id<y.id end);table.sort(row.removed,function(x,y)return x.id<y.id end);table.sort(row.moved,function(x,y)return x.id<y.id end);table.sort(row.changed,function(x,y)return x.id<y.id end)
        row.counts={added=#row.added,removed=#row.removed,moved=#row.moved,changed=#row.changed}
        result.collections[collection]=row
    end
    result.objects=result.collections.objects
    return result
end
function Checkpoints:restore(id)
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return nil,'commit or cancel the active transform session first' end
    if app.stamp_session and app.stamp_session:is_active() then return nil,'commit or cancel the active stamp stroke first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return nil,'resolve authoring-plan recovery before restoring a checkpoint' end
    local cp,err=self:_load(id);if not cp then return nil,err end
    local candidate_ok,candidate=pcall(Model.new,Util.deepcopy(cp.project))
    if not candidate_ok then return nil,'checkpoint project could not be normalized: '..tostring(candidate) end
    local issues=candidate:validate()
    for _,issue in ipairs(issues or {}) do if issue.severity=='error' then return nil,'checkpoint project failed validation: '..tostring(issue.message) end end
    app.model:push_history(Util.deepcopy(app.model.data),'Restore checkpoint '..cp.name)
    app.model.data=candidate.data
    if app.selection and app.selection.clear then app.selection:clear() end
    app.selected_object_id=nil;app.selected_room_id=nil;app.selected_premise_id=nil;app.selected_scene_id=nil
    app:mark_dirty()
    local sync=app.check_runtime_sync and app:check_runtime_sync(true) or nil
    return {restored=true,id=cp.id,name=cp.name,objects=#(candidate.data.objects or {}),runtime_sync=sync,warning='Project data restored. Review Runtime Sync and apply it to update currently tracked game entities.'}
end

return Checkpoints
