-- One-time migration of a World Builder / cp77wb saved build
-- (entSpawner/data/objects/<name>.json) into LocationStudio records.
--
-- Each WB leaf keeps its complete saved `spawnable` blob as the World Builder
-- entry data. WB's spawnNew copies every key of that blob into the new
-- spawnable, so a respawn restores appearance, scale, node refs, ranges and
-- class-specific fields exactly; LS does not re-derive any of them. WB groups
-- become LS object groups with the same nesting, under one premise.
local Util=require('modules/util')

local WbImport={}
WbImport.__index=WbImport

local GROUP_MODULES={
    ['modules/classes/editor/positionableGroup']=true,
    ['modules/classes/editor/randomizedGroup']=true,
    ['modules/classes/editor/scatteredGroup']=true,
}
local LEAF_MODULE='modules/classes/editor/spawnableElement'

function WbImport.new(app)
    return setmetatable({app=app,last_result=nil},WbImport)
end

function WbImport:_log(level,message,fields)
    local logger=self.app and self.app.logger
    if logger and logger[level] then logger[level](logger,'wb_import',message,fields) end
end

local function vec(value)
    value=type(value)=='table' and value or {}
    return {x=tonumber(value.x) or 0,y=tonumber(value.y) or 0,z=tonumber(value.z) or 0}
end

local function rot(value)
    value=type(value)=='table' and value or {}
    return {roll=tonumber(value.roll) or 0,pitch=tonumber(value.pitch) or 0,yaw=tonumber(value.yaw) or 0}
end

-- Pure conversion: WB tree -> {groups=, objects=, skipped=}. No model access.
function WbImport:plan(build,source)
    if type(build)~='table' then return nil,'saved build must be a JSON object' end
    if build.modulePath==nil and (build.type~=nil or build.path~=nil) then
        return nil,'Legacy Object Spawner build. Load it once in World Builder and save it again to upgrade the format, then retry.'
    end
    if build.isUsingSpawnables==false then
        return nil,'Pre-spawnable World Builder build. Load it once in World Builder and save it again to upgrade the format, then retry.'
    end
    if not GROUP_MODULES[build.modulePath] then return nil,'saved build root must be a World Builder group, got '..tostring(build.modulePath) end
    local wb=self.app.world_builder
    local plan={source=source,groups={},objects={},skipped={}}
    local function walk(node,parent_key,path,hidden)
        path=path..'/'..tostring(node.name or '?')
        hidden=hidden or node.visible==false
        if node.modulePath==LEAF_MODULE or type(node.spawnable)=='table' then
            local spawnable=node.spawnable
            local definition=type(spawnable)=='table' and wb and wb:definition_for_module_path(spawnable.modulePath)
            if not definition then
                table.insert(plan.skipped,{path=path,module_path=type(spawnable)=='table' and spawnable.modulePath or nil,reason='no LocationStudio World Builder definition for this spawnable class'})
                return
            end
            local template=type(spawnable.spawnData)=='string' and spawnable.spawnData or ''
            table.insert(plan.objects,{
                group_key=parent_key,path=path,definition=definition,
                record={
                    name=node.name,kind=definition.kind,layer=definition.layer,template=template,
                    appearance=type(spawnable.app)=='string' and spawnable.app or '',
                    transform={position=vec(spawnable.position),rotation=rot(spawnable.rotation)},
                    size=spawnable.scale and vec(spawnable.scale) or nil,visible=not hidden,
                    tags={'world-builder-import',definition.key},
                    metadata={world_builder={
                        definition_key=definition.key,category=definition.category,variant=definition.variant,
                        class_module=definition.class_module,module_path=spawnable.modulePath,
                        entry={name=node.name,data=Util.deepcopy(spawnable)},
                        resource_name=node.name,resource_path=template,apply_scale=spawnable.scale~=nil,
                        imported_from={build=source,path=path},
                    }},
                },
            })
            return
        end
        if not GROUP_MODULES[node.modulePath] then
            table.insert(plan.skipped,{path=path,module_path=node.modulePath,reason='unsupported World Builder element type'})
            return
        end
        local key=#plan.groups+1
        table.insert(plan.groups,{key=key,parent_key=parent_key,name=node.name,path=path,visible=not hidden,
            origin=vec(node.origin or node.pos),rotation=rot(node.rotation),module_path=node.modulePath})
        for _,child in ipairs(type(node.childs)=='table' and node.childs or {}) do walk(child,key,path,hidden) end
    end
    walk(build,nil,'',false)
    return plan
end

function WbImport:_already_imported(source)
    for _,object in ipairs(self.app.model.data.objects or {}) do
        local from=object.metadata and object.metadata.world_builder and object.metadata.world_builder.imported_from
        if from and from.build==source then return true end
    end
    return false
end

local function summary(plan)
    local kinds={}
    for _,item in ipairs(plan.objects) do kinds[item.definition.key]=(kinds[item.definition.key] or 0)+1 end
    return {source=plan.source,groups=#plan.groups,objects=#plan.objects,skipped=plan.skipped,by_definition=kinds}
end

-- args: build (decoded saved build), source (name for duplicate detection),
-- premise_id (existing) or premise_name, dry_run, spawn, allow_skipped,
-- allow_duplicate.
function WbImport:import(args)
    args=args or {}
    local source=tostring(args.source or (type(args.build)=='table' and args.build.name) or '')
    if source=='' then return nil,'source name is required' end
    local plan,err=self:plan(args.build,source);if not plan then return nil,err end
    local result=summary(plan)
    if #plan.objects==0 then return nil,'Saved build contains no importable objects.' end
    if #plan.skipped>0 and args.allow_skipped~=true then
        local first=plan.skipped[1]
        return nil,#plan.skipped..' element(s) cannot be imported (first: '..first.path..', '..tostring(first.module_path)..': '..first.reason..'). Pass allow_skipped=true to import the rest.'
    end
    if args.allow_duplicate~=true and self:_already_imported(source) then
        return nil,'Saved build '..source..' was already imported into this project. Pass allow_duplicate=true to import another copy.'
    end
    local model=self.app.model
    if args.premise_id and not model:get_premise(args.premise_id) then return nil,'premise not found: '..tostring(args.premise_id) end
    if args.dry_run==true then result.dry_run=true;return result end

    local before={data=Util.deepcopy(model.data),undo=Util.deepcopy(model.undo_stack),redo=Util.deepcopy(model.redo_stack)}
    local ok,created=pcall(function()
        local premise=args.premise_id and model:get_premise(args.premise_id) or model:add_premise({
            name=args.premise_name or plan.groups[1].name,kind='world_builder_import',
            transform={position=plan.groups[1].origin,rotation=plan.groups[1].rotation},
            tags={'world-builder-import'},notes='Imported from World Builder saved build '..source..'.',
        })
        local values={};local ids_by_group={}
        for _,item in ipairs(plan.objects) do
            local record=item.record;record.premise_id=premise.id
            table.insert(values,record)
        end
        local objects=model:add_objects(values,true)
        for index,object in ipairs(objects) do
            local key=plan.objects[index].group_key
            ids_by_group[key]=ids_by_group[key] or {};table.insert(ids_by_group[key],object.id)
        end
        local group_ids={}
        for _,group in ipairs(plan.groups) do
            local value,group_err=model:create_object_group({
                name=group.name,premise_id=premise.id,parent_id=group.parent_key and group_ids[group.parent_key],
                object_ids=ids_by_group[group.key] or {},pivot_mode='custom',
                pivot={position=group.origin,rotation=group.rotation},visible=group.visible,
            },true)
            if not value then error(group_err) end
            group_ids[group.key]=value.id
        end
        return {premise=premise,objects=objects,group_ids=group_ids}
    end)
    if not ok then
        model.data=before.data;model.undo_stack=before.undo;model.redo_stack=before.redo
        self:_log('error','import_failed',{source=source,error=tostring(created)})
        return nil,'Import failed and was rolled back: '..tostring(created)
    end
    model.undo_stack=before.undo;model.redo_stack={};model:push_history(before.data,'Import World Builder build '..source);model:touch();self.app:mark_dirty()

    result.premise_id=created.premise.id
    result.object_ids={};for _,object in ipairs(created.objects) do table.insert(result.object_ids,object.id) end
    result.root_group_id=created.group_ids[1]
    if args.spawn==true then
        result.spawned=0;result.spawn_failed={}
        for _,object in ipairs(created.objects) do
            if object.visible~=false then
                local runtime_id,spawn_err=self.app.placement:spawn(object)
                if runtime_id then result.spawned=result.spawned+1 else table.insert(result.spawn_failed,{object_id=object.id,error=tostring(spawn_err)}) end
            end
        end
    end
    self.last_result=result
    self:_log('info','imported',{source=source,objects=#created.objects,groups=#plan.groups,skipped=#plan.skipped})
    return result
end

return WbImport
