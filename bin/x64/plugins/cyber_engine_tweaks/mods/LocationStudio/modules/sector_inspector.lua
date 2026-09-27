local Util=require('modules/util')

-- In-game view of the streaming-sector report written by the MCP server
-- (`sector_inspect` or the Build Mod `sectors` stage). CET cannot read World
-- Builder's export folder, so the Python inspector saves its result under this
-- mod's exports/ directory and this module only reads and navigates it.
local SectorInspector={};SectorInspector.__index=SectorInspector

SectorInspector.REPORT_PATH='exports/sector-inspection.json'

function SectorInspector.new(app)
    return setmetatable({app=app,report=nil,loaded_at=nil,last_error=nil},SectorInspector)
end

function SectorInspector:load()
    if not Util.file_exists(SectorInspector.REPORT_PATH) then
        self.report=nil;self.last_error='No sector report yet. Run sector_inspect(export_file) or Build Mod from MCP.'
        return nil,self.last_error
    end
    local report=Util.json_read(SectorInspector.REPORT_PATH,nil)
    if type(report)~='table' or report.schema~='locationstudio-sector-inspection/1' then
        self.report=nil;self.last_error='Sector report is unreadable or from an unsupported version.'
        return nil,self.last_error
    end
    self.report=report;self.loaded_at=Util.now_iso();self.last_error=nil
    return self:summary()
end

function SectorInspector:summary()
    local r=self.report;if not r then return nil,self.last_error or 'no sector report loaded' end
    return {export_name=r.export_name,sector_count=r.sector_count,node_count=r.node_count,device_count=r.device_count,
        flag_counts=Util.deepcopy(r.flag_counts or {}),likely_wrong_sector=#(r.likely_wrong_sector or {}),
        cross_sector_references=#(r.cross_sector_references or {}),matched_objects=r.matched_objects,loaded_at=self.loaded_at}
end

-- Flags, optionally narrowed to one sector or severity, annotated with whether
-- the flagged node maps to a project object that still exists.
function SectorInspector:flags(args)
    args=args or {}
    local r=self.report;if not r then return nil,self.last_error or 'no sector report loaded' end
    local out={}
    for _,f in ipairs(r.flags or {}) do
        if (not args.sector or args.sector=='' or f.sector==args.sector) and (not args.severity or args.severity=='' or f.severity==args.severity) then
            local row=Util.deepcopy(f)
            row.object_exists=f.object_id~=nil and self.app.model:get_object(f.object_id)~=nil or false
            out[#out+1]=row
        end
    end
    return {items=out,count=#out}
end

function SectorInspector:nodes_for_object(object_id)
    local r=self.report;if not r then return nil,self.last_error or 'no sector report loaded' end
    local out={}
    for _,n in ipairs(r.nodes or {}) do if n.object_id==object_id then out[#out+1]=Util.deepcopy(n) end end
    return {items=out,count=#out}
end

-- Select (and focus in World Builder when live) the object behind a flag.
function SectorInspector:select_flagged(index)
    local r=self.report;if not r then return nil,self.last_error or 'no sector report loaded' end
    local f=(r.flags or {})[tonumber(index) or 0];if not f then return nil,'flag not found' end
    if not f.object_id then return nil,'this flag has no matching LocationStudio object (vanilla or unmatched node)' end
    local object=self.app.model:get_object(f.object_id);if not object then return nil,'the flagged object no longer exists in the project' end
    self.app.selection:set('object',object.id)
    if self.app.runtime_shell and self.app.runtime_shell.handles[object.id] then pcall(function() self.app.runtime_shell:focus(object) end) end
    return {selected=object.id,name=object.name,flag=Util.deepcopy(f)}
end

return SectorInspector
