local Util=require('modules/util')

-- In-game view of the asset dependency report written by the MCP server
-- (`dependency_scan` or the Build Mod `dependencies` stage). The resolver runs
-- in Python because it reads mod source folders and the game's archive
-- indexes; this module reads the saved report, maps it to project objects and
-- selects the ones with missing dependencies.
local Dependencies={};Dependencies.__index=Dependencies

Dependencies.REPORT_PATH='exports/dependency-report.json'

function Dependencies.new(app) return setmetatable({app=app,report=nil,loaded_at=nil,last_error=nil},Dependencies) end

function Dependencies:load()
    if not Util.file_exists(Dependencies.REPORT_PATH) then
        self.report=nil;self.last_error='No dependency report yet. Run dependency_scan or Build Mod from MCP.'
        return nil,self.last_error
    end
    local report=Util.json_read(Dependencies.REPORT_PATH,nil)
    if type(report)~='table' or report.schema~='locationstudio-dependencies/1' then
        self.report=nil;self.last_error='Dependency report is unreadable or from an unsupported version.'
        return nil,self.last_error
    end
    self.report=report;self.loaded_at=Util.now_iso();self.last_error=nil
    return self:summary()
end

function Dependencies:summary()
    local r=self.report;if not r then return nil,self.last_error or 'no dependency report loaded' end
    local external=0;for _ in pairs(r.external_requirements or {}) do external=external+1 end
    return {ready=r.ready==true,counts=Util.deepcopy(r.counts or {}),objects_scanned=r.objects_scanned,missing=#(r.missing or {}),
        unknown=#(r.unknown or {}),unverified=#(r.unverified or {}),ship=#(r.ship or {}),external_mods=external,
        vanilla_index=r.vanilla_index==true,generated_at=r.generated_at,loaded_at=self.loaded_at}
end

-- Objects with missing (or unknown) dependencies, most affected first.
function Dependencies:objects(args)
    args=args or {}
    local r=self.report;if not r then return nil,self.last_error or 'no dependency report loaded' end
    local out={}
    for i,o in ipairs(r.objects or {}) do
        local missing=#(o.missing or {})
        if args.all==true or missing>0 or (args.include_unknown==true and (o.unknown or 0)>0) then
            local row=Util.deepcopy(o);row.index=i;row.object_exists=self.app.model:get_object(o.object_id)~=nil
            out[#out+1]=row
        end
    end
    table.sort(out,function(a,b) if #a.missing~=#b.missing then return #a.missing>#b.missing end;return tostring(a.name)<tostring(b.name) end)
    return {items=out,count=#out}
end

function Dependencies:missing()
    local r=self.report;if not r then return nil,self.last_error or 'no dependency report loaded' end
    return {items=Util.deepcopy(r.missing or {}),count=#(r.missing or {})}
end

function Dependencies:select(object_id)
    local r=self.report;if not r then return nil,self.last_error or 'no dependency report loaded' end
    local object=self.app.model:get_object(object_id);if not object then return nil,'the object no longer exists in the project' end
    self.app.selection:set('object',object.id)
    if self.app.runtime_shell and self.app.runtime_shell.handles[object.id] then pcall(function() self.app.runtime_shell:focus(object) end) end
    for _,o in ipairs(r.objects or {}) do if o.object_id==object_id then return {selected=object.id,name=object.name,missing=Util.deepcopy(o.missing)} end end
    return {selected=object.id,name=object.name,missing={}}
end

return Dependencies
