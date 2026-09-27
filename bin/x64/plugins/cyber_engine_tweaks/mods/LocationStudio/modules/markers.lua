local Util=require('modules/util')

local Markers={}
Markers.__index=Markers

function Markers.new(app) return setmetatable({app=app,last_error=nil},Markers) end

local function marker_transform(transform,height)
    local out=Util.deepcopy(transform);out.position.z=out.position.z+(height or 0.15);return out
end

function Markers:refresh(premise_id)
    self.app.placement:clear_transients()
    local settings=self.app.model.data.settings.visuals or {}
    if settings.enabled==false then return {spawned=0,skipped='visuals disabled'} end
    if not settings.marker_template or settings.marker_template=='' then return {spawned=0,skipped='marker template not configured'} end
    local player=self.app.game:capture_transform();local max_distance=tonumber(settings.max_distance) or 80
    local spawned,failed=0,{}
    local function add(kind,item)
        if premise_id and item.premise_id and item.premise_id~=premise_id then return end
        if player and Util.distance3(player.position,item.transform.position)>max_distance then return end
        local _,err=self.app.placement:spawn_transient(kind..':'..item.id,settings.marker_template,settings.marker_appearance,marker_transform(item.transform,0.1))
        if err then table.insert(failed,{kind=kind,id=item.id,error=err}) else spawned=spawned+1 end
    end
    for _,item in ipairs(self.app.model.data.locations) do add('location',item) end
    for _,item in ipairs(self.app.model.data.volumes) do add('volume',item) end
    for _,item in ipairs(self.app.model.data.cameras) do add('camera',item) end
    for _,item in ipairs(self.app.model.data.cover_nodes or {}) do add('cover_node',item) end
    return {spawned=spawned,failed=failed}
end

function Markers:clear() return self.app.placement:clear_transients() end
function Markers:status() local settings=self.app.model.data.settings.visuals or {};return {enabled=settings.enabled~=false,template_configured=settings.marker_template~='',active=self.app.placement:status().markers} end

return Markers
