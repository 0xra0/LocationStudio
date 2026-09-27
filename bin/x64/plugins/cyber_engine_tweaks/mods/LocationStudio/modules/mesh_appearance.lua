local Util=require('modules/util')
local MeshAppearance={};MeshAppearance.__index=MeshAppearance

local function get_component(handle)
    if not handle then return nil end
    local candidates={handle.spawnable,handle,handle.element,handle.object}
    for _,value in ipairs(candidates) do
        if value then
            local ok,entity=pcall(function()
                if type(value.getEntity)=='function' then return value:getEntity() end
                if type(value.GetEntity)=='function' then return value:GetEntity() end
                return nil
            end)
            if ok and entity then
                local found,component=pcall(function() return entity:FindComponentByName('mesh') end)
                if found and component then return component,value end
            end
        end
    end
    return nil
end

function MeshAppearance.new(app) return setmetatable({app=app,preview_state={},last_error=nil},MeshAppearance) end
function MeshAppearance:_object(id)
    id=id or self.app.selected_object_id
    local object=id and self.app.model:get_object(id) or nil
    if not object then return nil,'select a placed mesh object first' end
    local wb=object.metadata and object.metadata.world_builder
    if not wb or wb.definition_key~='mesh_static' then return nil,'selected object is not a World Builder static mesh' end
    return object
end
function MeshAppearance:list(id)
    local object,err=self:_object(id);if not object then return nil,err end
    local handle=self.app.runtime_shell.handles[object.id]
    if not handle then return nil,'spawn this mesh through LocationStudio or World Builder before listing its appearances' end
    local component,spawnable=get_component(handle)
    local apps=(spawnable and spawnable.apps) or handle.apps
    if type(apps)~='table' then return nil,'World Builder has not exposed this mesh appearance list yet; wait for its mesh resource to load and retry' end
    local out={};for _,name in ipairs(apps) do if type(name)=='string' and name~='' then out[#out+1]=name end end
    local current=(spawnable and spawnable.app) or (component and tostring(component.meshAppearance)) or ''
    return {object_id=object.id,resource=object.metadata.world_builder.resource_path,appearances=out,current=current,live=component~=nil}
end
function MeshAppearance:_apply_live(object,appearance)
    local handle=self.app.runtime_shell.handles[object.id];local component,spawnable=get_component(handle)
    if not component then return nil,'live World Builder mesh component is unavailable; spawn the object first' end
    local ok,err=pcall(function()
        component.meshAppearance=CName.new(appearance)
        component:LoadAppearance()
    end)
    if not ok then return nil,'World Builder could not apply mesh appearance: '..tostring(err) end
    if spawnable then
        spawnable.app=appearance
        if type(spawnable.apps)=='table' then for index,name in ipairs(spawnable.apps) do if name==appearance then spawnable.appIndex=index-1;break end end end
    end
    return true
end
function MeshAppearance:preview(args)
    args=args or {};local object,err=self:_object(args.object_id);if not object then return nil,err end
    if type(args.appearance)~='string' or args.appearance=='' then return nil,'appearance name is required' end
    local list;list,err=self:list(object.id);if not list then return nil,err end
    local valid=false;for _,name in ipairs(list.appearances) do if name==args.appearance then valid=true;break end end
    if not valid then return nil,'appearance is not in the World Builder mesh variant list' end
    local state=self.preview_state[object.id]
    if not state then state={original=(object.metadata.world_builder.entry.data or {}).app or list.current};self.preview_state[object.id]=state end
    local ok;ok,err=self:_apply_live(object,args.appearance);if not ok then return nil,err end
    state.current=args.appearance
    return {object_id=object.id,appearance=args.appearance,preview=true,original=state.original}
end
function MeshAppearance:cancel(args)
    local object,err=self:_object(args and args.object_id);if not object then return nil,err end
    local state=self.preview_state[object.id];if not state then return {object_id=object.id,cancelled=false} end
    local ok;ok,err=self:_apply_live(object,state.original);if not ok then return nil,err end
    self.preview_state[object.id]=nil
    return {object_id=object.id,cancelled=true,appearance=state.original}
end
function MeshAppearance:apply(args)
    args=args or {};local object,err=self:_object(args.object_id);if not object then return nil,err end
    local appearance=args.appearance
    if type(appearance)~='string' or appearance=='' then return nil,'appearance name is required' end
    local list;list,err=self:list(object.id);if not list then return nil,err end
    local valid=false;for _,name in ipairs(list.appearances) do if name==appearance then valid=true;break end end
    if not valid then return nil,'appearance is not in the World Builder mesh variant list' end
    local ok;ok,err=self:_apply_live(object,appearance);if not ok then return nil,err end
    local metadata=Util.deepcopy(object.metadata or {});local wb=metadata.world_builder
    wb.entry.data=wb.entry.data or {};wb.entry.data.app=appearance
    wb.appearance=appearance
    local updated;updated,err=self.app.model:update_object(object.id,{metadata=metadata});if not updated then return nil,err end
    self.preview_state[object.id]=nil;self.app:mark_dirty()
    return {object_id=object.id,appearance=appearance,saved=true,spawned=true}
end

local function xyz(p) return {x=tonumber(p.x) or 0,y=tonumber(p.y) or 0,z=tonumber(p.z) or 0,w=1} end
function MeshAppearance:create_decal(args)
    args=args or {};local query=args.resource_name or args.query or ''
    local results,err=self.app.world_builder:search('decal',query,40,true);if not results then return nil,err end
    local resource
    for _,item in ipairs(results.items or {}) do if args.resource_path and item.path==args.resource_path then resource=item;break end end
    if args.resource_path and not resource then return nil,'World Builder Decals catalog did not contain the requested material path' end
    resource=resource or (results.items and results.items[1])
    if not resource then return nil,'World Builder Decals catalog returned no matching .mi resource' end
    local hit,transform
    if args.transform then transform=Util.deepcopy(args.transform)
    elseif args.source=='player' then transform,err=self.app.game:capture_transform();if not transform then return nil,err end
    else hit,err=self.app.game:aim_point(args.distance or 10);if not hit then return nil,err end
        transform={position=hit.position,rotation={roll=0,pitch=0,yaw=tonumber(args.yaw) or 0}}
    end
    local name=Util.trim(args.name or '')~='' and Util.trim(args.name) or resource.name..' Decal'
    local payload;payload,err=self.app.world_builder:prepare_favorite_record({category='Deco',variant='Decals',spawn_data=resource.path,name=resource.name},name)
    if not payload then return nil,err end
    local saved=payload.data and payload.data.spawnable
    if type(saved)~='table' or saved.spawnData~=resource.path then return nil,'World Builder decal serializer returned an invalid material entry' end
    saved.alpha=math.max(0,math.min(1,tonumber(args.alpha) or 1))
    saved.autoHideDistance=math.max(0,tonumber(args.auto_hide_distance) or tonumber(saved.autoHideDistance) or 150)
    saved.horizontalFlip=args.horizontal_flip==true;saved.verticalFlip=args.vertical_flip==true
    local sx=math.max(0.05,tonumber(args.width) or 1);local sy=math.max(0.05,tonumber(args.height) or sx)
    saved.scale={x=sx,y=sy,z=tonumber(args.depth) or 1}
    local entry={name=payload.name,fileName=payload.name,data=saved}
    local premise_id=args.premise_id or self.app.selected_premise_id
    local object=self.app.model:add_object({premise_id=premise_id,room_id=args.room_id or self.app.selected_room_id,
        name=name,kind='decal',template='',layer='decoration',transform=transform,size={x=sx,y=sy,z=0.025},enabled=true,
        metadata={source='LocationStudio World Builder Decal',world_builder={definition_key='decal',category='Deco',variant='Decals',class_module='modules/classes/spawn/visual/decal',module_path='visual/decal',resource_name=resource.name,resource_path=resource.path,entry=entry,apply_scale=false},decal={alpha=saved.alpha,width=sx,height=sy,horizontal_flip=saved.horizontalFlip,vertical_flip=saved.verticalFlip}}})
    if not object then return nil,'project model rejected the World Builder decal' end
    self.app.selection:set('object',object.id);self.app:mark_dirty()
    if args.spawn~=false then local id,spawn_err=self.app.placement:spawn(object);if not id then return {object=object,spawned=false,spawn_error=tostring(spawn_err)} end end
    return {object=object,spawned=args.spawn~=false,resource_path=resource.path,aim_source=hit and hit.source or nil}
end
return MeshAppearance
