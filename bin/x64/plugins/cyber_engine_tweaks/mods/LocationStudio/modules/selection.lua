local Selection={}
Selection.__index=Selection

local FIELDS={
    location='selected_location_id',route='selected_route_id',premise='selected_premise_id',
    room='selected_room_id',object='selected_object_id',volume='selected_volume_id',cover_node='selected_cover_node_id',
    camera='selected_camera_id',scene='selected_scene_id',asset='selected_asset_id',
}

local ITEM_FIELDS={'selected_location_id','selected_route_id','selected_object_id','selected_volume_id','selected_cover_node_id','selected_camera_id','selected_scene_id','selected_asset_id'}

function Selection.new(app)
    return setmetatable({app=app,kind=nil,id=nil,revision=0,object_ids={},object_lookup={},group_source=nil,_group_update=false},Selection)
end

function Selection:_clear_item_fields()
    for _,field in ipairs(ITEM_FIELDS) do self.app[field]=nil end
end

function Selection:set(kind,id)
    if not FIELDS[kind] then return nil,'unsupported selection kind: '..tostring(kind) end
    if not id then return nil,'selection id is required' end

    local item=self:resolve(kind,id)
    if not item then return nil,kind..' not found' end

    -- Keep the most recently chosen catalog asset available while an object is
    -- selected.  Replacement is a two-selection workflow: choose an asset,
    -- then choose the construction piece that should receive it.
    if kind=='asset' then self.app.last_asset_id=id end

    if kind=='object' and not self._group_update then
        self.object_ids={id};self.object_lookup={[id]=true};self.group_source='locationstudio'
        self.app.active_object_group_id=nil
    elseif kind~='object' and kind~='asset' and not self._group_update then
        self.object_ids={};self.object_lookup={};self.group_source=nil
        self.app.active_object_group_id=nil
    end

    self:_clear_item_fields()
    self.kind=kind;self.id=id;self.revision=self.revision+1
    self.app.selected_item_kind=kind

    if kind=='premise' then
        self.app.selected_premise_id=id;self.app.selected_room_id=nil
    elseif kind=='room' then
        self.app.selected_premise_id=item.premise_id;self.app.selected_room_id=id
    elseif kind=='object' or kind=='volume' or kind=='camera' or kind=='cover_node' then
        self.app[FIELDS[kind]]=id
        self.app.selected_premise_id=item.premise_id
        self.app.selected_room_id=item.room_id
    elseif kind=='scene' then
        self.app.selected_scene_id=id
        self.app.editing_scene_id=id
        if item.premise_id then self.app.selected_premise_id=item.premise_id end
    else
        -- Locations/routes/assets are global authoring selections. Keep the active
        -- premise/room context so an asset can still be placed into the current scene.
        self.app[FIELDS[kind]]=id
    end
    return item
end

function Selection:contains_object(id) return self.object_lookup[id]==true end

function Selection:object_count()
    local count=0;for _,id in ipairs(self.object_ids) do if self.app.model:get_object(id) then count=count+1 end end
    return count
end

function Selection:selected_objects()
    local values={};local ids={};local lookup={}
    for _,id in ipairs(self.object_ids) do
        local object=self.app.model:get_object(id)
        if object and not lookup[id] then table.insert(values,object);table.insert(ids,id);lookup[id]=true end
    end
    self.object_ids=ids;self.object_lookup=lookup
    return values
end

function Selection:set_object_group(ids,active_id,source)
    if type(ids)~='table' then return nil,'object IDs must be a list' end
    local values,lookup={},{ }
    for _,id in ipairs(ids) do
        if not lookup[id] and self.app.model:get_object(id) then table.insert(values,id);lookup[id]=true end
    end
    self.object_ids=values;self.object_lookup=lookup;self.group_source=source or 'locationstudio'
    if source~='saved_group' then self.app.active_object_group_id=nil end
    if #values==0 then
        if self.kind=='object' then self:_clear_item_fields();self.kind=nil;self.id=nil;self.app.selected_item_kind=nil end
        self.revision=self.revision+1;return {}
    end
    if not lookup[active_id] then active_id=values[#values] end
    self._group_update=true;local item,err=self:set('object',active_id);self._group_update=false
    return item and self:selected_objects() or nil,err
end

function Selection:toggle_object(id)
    local object=self.app.model:get_object(id);if not object then return nil,'object not found' end
    local ids={};for _,value in ipairs(self.object_ids) do if value~=id then table.insert(ids,value) end end
    if not self.object_lookup[id] then table.insert(ids,id) end
    return self:set_object_group(ids,self.object_lookup[id] and ids[#ids] or id,'locationstudio')
end

function Selection:clear_object_group()
    return self:set_object_group({},nil,'locationstudio')
end

function Selection:clear()
    local old_kind=self.kind
    self:_clear_item_fields()
    if old_kind=='premise' then self.app.selected_premise_id=nil;self.app.selected_room_id=nil
    elseif old_kind=='room' then self.app.selected_room_id=nil end
    self.kind=nil;self.id=nil;self.object_ids={};self.object_lookup={};self.group_source=nil;self.revision=self.revision+1;self.app.selected_item_kind=nil;self.app.active_object_group_id=nil
end

function Selection:resolve(kind,id)
    kind=kind or self.kind;id=id or self.id
    if not kind or not id then return nil end
    local model=self.app.model
    if kind=='location' then return model:get_location(id)
    elseif kind=='route' then return model:get_route(id)
    elseif kind=='premise' then return model:get_premise(id)
    elseif kind=='room' then return model:get_room(id)
    elseif kind=='object' then return model:get_object(id)
    elseif kind=='volume' then return model:get_volume(id)
    elseif kind=='cover_node' then return model:get_cover_node(id)
    elseif kind=='camera' then return model:get_camera(id)
    elseif kind=='scene' then return model:get_scene(id)
    elseif kind=='asset' then return model:get_asset(id) end
end

function Selection:is(kind,id) return self.kind==kind and self.id==id end

return Selection
