local Util=require('modules/util')
local RuntimeState=require('modules/runtime_state')

-- Layer manager: hide/show, lock, isolate, select-all, colour labels,
-- export-enable and assignment for project layers. Objects carry a layer id;
-- rooms, volumes and cameras are counted too. Hidden layers despawn their live
-- objects (placement already refuses to spawn them) and showing a layer
-- respawns exactly what was live when it was hidden. Locking marks every
-- object with `locked`, so every existing lock check applies.
local Layers={};Layers.__index=Layers

local LOCKED_BY='locked_by_layer'

function Layers.new(app,persistent)
    local state=persistent or RuntimeState.get()
    state.layer_hidden_live=state.layer_hidden_live or {}
    return setmetatable({app=app,state=state,isolation=nil},Layers)
end

function Layers:get(id)
    for i,layer in ipairs(self.app.model.data.layers or {}) do if layer.id==id then return layer,i end end
    return nil
end

local function color_ok(value) return type(value)=='string' and value:match('^#%x%x%x%x%x%x$')~=nil end

function Layers:color_rgb(id)
    local layer=self:get(id);local hex=layer and layer.color or '#FFFFFF'
    return tonumber(hex:sub(2,3),16)/255,tonumber(hex:sub(4,5),16)/255,tonumber(hex:sub(6,7),16)/255
end

function Layers:objects(id)
    local out={};for _,o in ipairs(self.app.model.data.objects or {}) do if o.layer==id then out[#out+1]=o end end;return out
end

function Layers:list()
    local model=self.app.model;local counts={}
    local function bump(id,field) counts[id]=counts[id] or {objects=0,live=0,locked=0,rooms=0,volumes=0,cameras=0};counts[id][field]=counts[id][field]+1 end
    for _,o in ipairs(model.data.objects or {}) do
        bump(o.layer,'objects')
        if o.runtime and o.runtime.spawned then bump(o.layer,'live') end
        if o.locked then bump(o.layer,'locked') end
    end
    for _,r in ipairs(model.data.rooms or {}) do bump(r.layer,'rooms') end
    for _,v in ipairs(model.data.volumes or {}) do bump(v.layer,'volumes') end
    for _,c in ipairs(model.data.cameras or {}) do bump(c.layer,'cameras') end
    local out,known={}, {}
    for _,layer in ipairs(model.data.layers or {}) do
        local row=Util.deepcopy(layer);row.counts=counts[layer.id] or {objects=0,live=0,locked=0,rooms=0,volumes=0,cameras=0}
        row.hidden_live=#(self.state.layer_hidden_live[layer.id] or {});row.isolated=self.isolation~=nil and self.isolation.layer_id==layer.id
        out[#out+1]=row;known[layer.id]=true
    end
    local unknown={};for id,c in pairs(counts) do if not known[id] then unknown[#unknown+1]={id=id,objects=c.objects} end end
    return {layers=out,unknown_layers=unknown,isolation=self.isolation and {layer_id=self.isolation.layer_id} or nil}
end

function Layers:_busy()
    local app=self.app
    if app.transform_session and app.transform_session:is_active() then return 'Finish or cancel the active transform edit first' end
    if app.stamp_session and app.stamp_session:is_active() then return 'Stop the active stamp session first' end
    if app.authoring_plans and app.authoring_plans:status().recovery_required then return 'Resolve authoring-plan recovery first' end
    return nil
end

function Layers:create(args)
    args=args or {}
    local name=Util.trim(args.name or '');if name=='' then return nil,'layer name is required' end
    for _,layer in ipairs(self.app.model.data.layers) do if string.lower(layer.name)==string.lower(name) then return nil,'a layer with this name already exists' end end
    local id=Util.trim(args.id or '')~='' and Util.trim(args.id) or ('layer_'..name:lower():gsub('[^%w]+','_'))
    if self:get(id) then return nil,'layer id already exists: '..id end
    if args.color~=nil and not color_ok(args.color) then return nil,'color must be #RRGGBB' end
    self.app.model:snapshot('Create layer')
    local layer={id=id,name=name,color=args.color or '#FFFFFF',visible=true,locked=false,export=args.export~=false,description=tostring(args.description or '')}
    table.insert(self.app.model.data.layers,layer);self.app.model:touch();self.app:mark_dirty()
    return Util.deepcopy(layer)
end

-- Name, colour, description and export flag. Visibility and locking have their
-- own operations because they act on objects.
function Layers:update(id,patch)
    patch=patch or {}
    local layer=self:get(id);if not layer then return nil,'layer not found' end
    if patch.color~=nil and not color_ok(patch.color) then return nil,'color must be #RRGGBB' end
    if patch.name~=nil then
        local name=Util.trim(patch.name);if name=='' then return nil,'layer name is required' end
        for _,other in ipairs(self.app.model.data.layers) do if other.id~=id and string.lower(other.name)==string.lower(name) then return nil,'a layer with this name already exists' end end
    end
    self.app.model:snapshot('Update layer')
    if patch.name~=nil then layer.name=Util.trim(patch.name) end
    if patch.color~=nil then layer.color=patch.color end
    if patch.description~=nil then layer.description=tostring(patch.description) end
    if patch.export~=nil then layer.export=patch.export==true end
    self.app.model:touch();self.app:mark_dirty()
    return Util.deepcopy(layer)
end

function Layers:set_visible(id,visible)
    local busy=self:_busy();if busy then return nil,busy end
    local layer=self:get(id);if not layer then return nil,'layer not found' end
    visible=visible~=false
    local result={layer_id=id,visible=visible,despawned=0,respawned=0,failed={}}
    if layer.visible==visible then return result end
    layer.visible=visible;self.app:mark_dirty()
    if not visible then
        local remembered={}
        for _,o in ipairs(self:objects(id)) do
            if self.app.placement:is_tracked(o) then
                local ok,err=self.app.placement:despawn(o)
                if ok then remembered[#remembered+1]=o.id;result.despawned=result.despawned+1 else result.failed[#result.failed+1]={object_id=o.id,error=tostring(err)} end
            end
        end
        self.state.layer_hidden_live[id]=remembered
    else
        for _,oid in ipairs(self.state.layer_hidden_live[id] or {}) do
            local o=self.app.model:get_object(oid)
            if o and o.layer==id and o.enabled~=false then
                local sid,err=self.app.placement:spawn(o)
                if sid then result.respawned=result.respawned+1 else result.failed[#result.failed+1]={object_id=oid,error=tostring(err)} end
            end
        end
        self.state.layer_hidden_live[id]=nil
    end
    return result
end

-- Show only this layer; remember every layer's previous visibility.
function Layers:isolate(id)
    local layer=self:get(id);if not layer then return nil,'layer not found' end
    local previous=self.isolation and self.isolation.previous or {}
    if not self.isolation then for _,l in ipairs(self.app.model.data.layers) do previous[l.id]=l.visible~=false end end
    local changes={}
    for _,l in ipairs(self.app.model.data.layers) do
        local r,err=self:set_visible(l.id,l.id==id);if not r then return nil,err end
        if r.despawned>0 or r.respawned>0 then changes[#changes+1]=r end
    end
    self.isolation={layer_id=id,previous=previous}
    return {isolated=id,changes=changes}
end

function Layers:unisolate()
    if not self.isolation then return nil,'no layer is isolated' end
    local previous=self.isolation.previous;self.isolation=nil
    local changes={}
    for _,l in ipairs(self.app.model.data.layers) do
        local want=previous[l.id];if want==nil then want=true end
        local r,err=self:set_visible(l.id,want);if not r then return nil,err end
        if r.despawned>0 or r.respawned>0 then changes[#changes+1]=r end
    end
    return {restored=true,changes=changes}
end

function Layers:set_locked(id,locked)
    local busy=self:_busy();if busy then return nil,busy end
    local layer=self:get(id);if not layer then return nil,'layer not found' end
    locked=locked==true
    self.app.model:snapshot(locked and 'Lock layer' or 'Unlock layer')
    local changed=0
    for _,o in ipairs(self:objects(id)) do
        o.metadata=o.metadata or {}
        if locked and not o.locked then o.locked=true;o.metadata[LOCKED_BY]=id;changed=changed+1
        elseif not locked and o.metadata[LOCKED_BY]==id then o.locked=false;o.metadata[LOCKED_BY]=nil;changed=changed+1 end
    end
    layer.locked=locked;self.app.model:touch();self.app:mark_dirty()
    return {layer_id=id,locked=locked,changed=changed}
end

function Layers:select_all(id,args)
    args=args or {}
    local layer=self:get(id);if not layer then return nil,'layer not found' end
    local ids={}
    for _,o in ipairs(self:objects(id)) do if not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id then ids[#ids+1]=o.id end end
    if #ids==0 then return nil,'layer has no objects'..(args.premise_id and ' in this premise' or '') end
    local selected,err=self.app.selection:set_object_group(ids,ids[1],'layer')
    if selected==nil and err then return nil,err end
    return {layer_id=id,selected=#ids,object_ids=ids}
end

-- Move objects to a layer. Locked objects (or a locked target layer) are
-- refused; moving into a hidden layer despawns, into a locked one locks.
function Layers:assign(object_ids,layer_id)
    local busy=self:_busy();if busy then return nil,busy end
    local target=self:get(layer_id);if not target then return nil,'target layer not found' end
    if target.locked then return nil,'target layer is locked; unlock it first' end
    if type(object_ids)~='table' or #object_ids==0 then return nil,'object_ids must be a non-empty list' end
    local objects={}
    for _,id in ipairs(object_ids) do
        local o=self.app.model:get_object(id);if not o then return nil,'object not found: '..tostring(id) end
        if o.locked then return nil,'object is locked: '..tostring(o.name) end
        objects[#objects+1]=o
    end
    self.app.model:snapshot('Assign layer')
    local despawned=0
    for _,o in ipairs(objects) do
        o.layer=layer_id
        if target.visible==false and self.app.placement:is_tracked(o) then
            local ok=self.app.placement:despawn(o)
            if ok then despawned=despawned+1;self.state.layer_hidden_live[layer_id]=self.state.layer_hidden_live[layer_id] or {};table.insert(self.state.layer_hidden_live[layer_id],o.id) end
        end
    end
    self.app.model:touch();self.app:mark_dirty()
    return {layer_id=layer_id,moved=#objects,despawned=despawned}
end

-- Suggested layer from what an object is. Only objects still on the generic
-- defaults (Props/Gameplay) move unless args.all is set.
local function suggest(object)
    local md=object.metadata or {}
    local wb=md.world_builder or {};local key=wb.definition_key or ''
    if md.room_kit or md.room_collision or md.generated then return 'shell' end
    if md.npc_population or key=='entity_record' or key=='ai_spot' or key=='ai_community' or md.workspot then return 'npc' end
    if key:find('^light_') or key=='fog' or md.lighting then return 'lighting' end
    if key=='audio' or key=='area_ambient' or md.ambient_audio or md.ambient_zone then return 'audio' end
    if md.quest or md.questforge or md.quest_fact then return 'quest' end
    if key=='static_marker' or key=='spline_point' or key=='area_outline' or md.debug==true then return 'debug' end
    if md.interactable or key=='device' or key:find('^area_') or key:find('^collision_') or key=='occluder' then return 'gameplay' end
    return 'decoration'
end

function Layers:auto_assign(args)
    args=args or {}
    local generic={decoration=true,gameplay=true}
    local moves={}
    for _,o in ipairs(self.app.model.data.objects or {}) do
        if (not args.premise_id or args.premise_id=='' or o.premise_id==args.premise_id) and (args.all==true or generic[o.layer]) and not o.locked then
            local want=suggest(o)
            if want~=o.layer and self:get(want) then moves[#moves+1]={object_id=o.id,name=o.name,from=o.layer,to=want} end
        end
    end
    if args.apply~=true then return {dry_run=true,moves=moves,count=#moves} end
    if #moves==0 then return {dry_run=false,moves={},count=0} end
    local busy=self:_busy();if busy then return nil,busy end
    self.app.model:snapshot('Auto-assign layers')
    for _,m in ipairs(moves) do local o=self.app.model:get_object(m.object_id);o.layer=m.to end
    self.app.model:touch();self.app:mark_dirty()
    return {dry_run=false,moves=moves,count=#moves}
end

function Layers:delete(id,move_to)
    local layer,index=self:get(id);if not layer then return nil,'layer not found' end
    move_to=move_to or 'decoration'
    if move_to==id then return nil,'choose a different layer to receive the objects' end
    local target=self:get(move_to);if not target then return nil,'target layer not found: '..tostring(move_to) end
    if #self.app.model.data.layers<=1 then return nil,'cannot delete the last layer' end
    if layer.locked then return nil,'unlock the layer before deleting it' end
    self.app.model:snapshot('Delete layer')
    local moved=0
    for _,collection in ipairs({'objects','rooms','volumes','cameras'}) do
        for _,item in ipairs(self.app.model.data[collection] or {}) do if item.layer==id then item.layer=move_to;moved=moved+1 end end
    end
    table.remove(self.app.model.data.layers,index);self.state.layer_hidden_live[id]=nil
    self.app.model:touch();self.app:mark_dirty()
    return {deleted=id,moved=moved,moved_to=move_to}
end

-- Objects excluded from export by their layer.
function Layers:export_enabled(object)
    local layer=object and self:get(object.layer)
    return not layer or layer.export~=false
end

return Layers
