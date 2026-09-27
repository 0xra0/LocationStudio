-- Produces a real World Builder `*_exported.json` from LocationStudio objects.
--
-- The export is written by World Builder itself: live WB element handles are
-- serialized with their own `serialize()`, saved as a WB root group through
-- WB's own `element.save`, and exported through `baseUI.exportUI`. Nothing here
-- re-implements WB's node export, so sector/node data stays exactly what the
-- WB Export tab would write. The headless .archive/.xl build is done by
-- mcp_server/lsbuild from the resulting file.
local Util=require('modules/util')

local BuildExport={}
BuildExport.__index=BuildExport

local GROUP_PREFIX='ls_'

function BuildExport.new(app)
    return setmetatable({app=app,last_result=nil,last_error=nil},BuildExport)
end

function BuildExport:_log(level,message,fields)
    local logger=self.app and self.app.logger
    if logger and logger[level] then logger[level](logger,'build_export',message,fields) end
end

function BuildExport:_export_ui()
    local wb=self.app.world_builder and self.app.world_builder:_mod()
    local ui=wb and wb.baseUI and wb.baseUI.exportUI
    if not ui then return nil,'World Builder is not loaded, or its Export UI is not initialized.' end
    if type(ui.addGroup)~='function' or type(ui.export)~='function' then return nil,'World Builder Export UI API (addGroup/export) is unavailable in this WB version.' end
    return ui
end

function BuildExport:status()
    local ui,err=self:_export_ui()
    return {available=ui~=nil,reason=err,last_result=self.last_result,last_error=self.last_error}
end

-- Object records in scope, in model order.
function BuildExport:_objects(args)
    local model=self.app.model
    local wanted
    if args.scene_id then
        local ids,err=self.app.scenes:member_object_ids(args.scene_id)
        if not ids then return nil,tostring(err)..': '..tostring(args.scene_id) end
        wanted={};for _,id in ipairs(ids) do wanted[id]=true end
    elseif type(args.object_ids)=='table' then
        wanted={};for _,id in ipairs(args.object_ids) do wanted[id]=true end
    end
    local out={};self.last_excluded_by_layer={};self.last_procedural={};self.last_disabled_collision={}
    for _,object in ipairs(model.data.objects or {}) do
        local in_scope=(wanted==nil or wanted[object.id]) and (args.premise_id==nil or object.premise_id==args.premise_id)
        -- Layers with export disabled (e.g. Debug) are left out on purpose;
        -- they are reported separately and never count as skipped.
        if in_scope and self.app.layers and not self.app.layers:export_enabled(object) then
            table.insert(self.last_excluded_by_layer,{id=object.id,name=object.name,layer=object.layer})
        elseif in_scope and object.enabled==false and object.metadata and object.metadata.collision_gen then
            -- Generated colliders of a room whose collision is switched off (collision_gen:set_room_enabled).
            table.insert(self.last_disabled_collision,{id=object.id,name=object.name,room_id=object.room_id})
        elseif in_scope and object.metadata and object.metadata.procedural then
            -- Generated meshes are written by the Build Mod `procedural` stage, not by World Builder.
            table.insert(self.last_procedural,{id=object.id,name=object.name,mesh_path=object.metadata.procedural.mesh_path})
        elseif in_scope then table.insert(out,object) end
    end
    return out
end

-- Why an in-scope object cannot be exported, or nil when it can.
local function skip_reason(object,handle)
    if object.runtime==nil or object.runtime.backend~='world_builder' then return 'not a World Builder object (CET entity spawner or never spawned)' end
    if not handle then return 'World Builder handle is not live; spawn or reload runtime first' end
    if type(handle.serialize)~='function' then return 'World Builder handle cannot serialize' end
    return nil
end

-- Decide whether an export that skips some in-scope objects may proceed.
-- `skipped` is a list of {id=,name=,reason=}; `exported` is the number of
-- objects that will be written. Return true to continue, or nil plus a message
-- that the MCP caller will see.
function BuildExport:_accept_skipped(skipped,exported,args)
    if exported==0 then return nil,'No exportable World Builder objects in scope.'..((#(self.last_procedural or {})>0) and ' Procedural geometry is added to an exported sector by Build Mod, so the scope needs at least one World Builder object (a light, collision or prop).' or '') end
    if #skipped==0 or args.allow_skipped==true then return true end
    local names={}
    for i=1,math.min(#skipped,5) do table.insert(names,tostring(skipped[i].name or skipped[i].id)..' ('..skipped[i].reason..')') end
    return nil,#skipped..' object(s) in scope would be missing from the built mod: '..table.concat(names,'; ')..(#skipped>5 and '; ...' or '')..'. Pass allow_skipped=true to build without them.'
end

local function centroid(handles)
    local sum={x=0,y=0,z=0};local count=0
    for _,handle in ipairs(handles) do
        local ok,p=pcall(function() return handle:getPosition() end)
        if ok and p then sum.x=sum.x+p.x;sum.y=sum.y+p.y;sum.z=sum.z+p.z;count=count+1 end
    end
    if count==0 then return {x=0,y=0,z=0} end
    return {x=sum.x/count,y=sum.y/count,z=sum.z/count}
end

-- WB initializes exportUI's `sectorCategory` enum table only when its Export
-- tab is drawn. Exporting before that indexes nil, so detect it up front.
local function sector_category_ready(ui)
    if type(debug)~='table' or type(debug.getupvalue)~='function' then return nil end
    for i=1,64 do
        local name,value=debug.getupvalue(ui.exportGroup,i)
        if name==nil then return nil end
        if name=='sectorCategory' then return value~=nil end
    end
    return nil
end

function BuildExport:export(args)
    args=args or {}
    local name=tostring(args.name or '')
    if not name:match('^[a-z0-9_]+$') then return nil,'name must match [a-z0-9_]+ (it becomes the .archive, .xl and sector name).' end
    local ui,ui_err=self:_export_ui();if not ui then return nil,ui_err end
    if sector_category_ready(ui)==false then
        return nil,'Open World Builder > Export tab once this session (WB builds its sector-category table only when that tab is drawn), then retry.'
    end

    local objects,err=self:_objects(args);if not objects then return nil,err end
    local handles,skipped,children={}, {}, {}
    local marker_groups,zone_records={},{}
    for _,object in ipairs(objects) do
        local handle=self.app.runtime_shell and self.app.runtime_shell.handles[object.id]
        local reason=skip_reason(object,handle)
        if not reason then
            local ok,data=pcall(function() return handle:serialize() end)
            if ok and type(data)=='table' then
                data.name=object.name or data.name
                local population=object.metadata and object.metadata.npc_population
                if population then
                    local saved=data.spawnable
                    if type(saved)~='table' then
                        reason='NPC population point did not serialize as a World Builder Entity Record'
                    else
                        -- World Builder's entityRecord exporter maps these exact saved
                        -- fields into worldPopulationSpawnerNode (record, appearance,
                        -- spawnOnStart, alwaysSpawned, and streaming ranges).
                        saved.spawnData=population.record;saved.app=population.appearance or ''
                        saved.spawnOnStart=population.spawn_on_start~=false;saved.alwaysSpawned=population.always_spawned==true
                        saved.primaryRange=tonumber(population.primary_range) or 100
                        saved.secondaryRange=tonumber(population.secondary_range) or 120
                    end
                end
                if reason then
                    -- Keep this object in the ordinary skipped report; do not output
                    -- an entityRecord node with missing or mismatched native fields.
                else
                local zone=object.metadata and object.metadata.ambient_zone
                if zone and zone.role=='outline_marker' then
                    local key=zone.id
                    marker_groups[key]=marker_groups[key] or {name=zone.outline_group,children={},objects={},handles={}}
                    table.insert(marker_groups[key].children,data);table.insert(marker_groups[key].objects,object);table.insert(marker_groups[key].handles,handle)
                elseif zone and zone.role=='area' then
                    zone_records[zone.id]={data=data,object=object,zone=zone}
                    table.insert(children,data);table.insert(handles,handle)
                else
                    table.insert(children,data);table.insert(handles,handle)
                end
                end
            else
                reason='World Builder serialize failed: '..tostring(data)
            end
        end
        if reason then table.insert(skipped,{id=object.id,name=object.name,reason=reason}) end
    end
    for zone_id,record in pairs(zone_records) do
        local markers=marker_groups[zone_id]
        if not markers or #markers.children~=4 then
            return nil,'Ambient reverb zone "'..tostring(record.object.name)..'" needs all four live World Builder outline markers in the same export scope.'
        end
        local saved=record.data.spawnable
        if type(saved)~='table' then return nil,'Ambient reverb zone has no serialized World Builder spawn data.' end
        saved.outlinePath='/'..GROUP_PREFIX..name..'/'..markers.name
        saved.markers={}
        for _,marker in ipairs(markers.objects) do
            local p=marker.transform.position
            saved.markers[#saved.markers+1]={x=p.x,y=p.y,z=p.z,w=1}
        end
        saved.height=record.zone.height or record.object.size.z
        local center=record.object.transform.position
        local group={name=markers.name,fileName=markers.name,modulePath='modules/classes/editor/positionableGroup',
            headerOpen=false,propertyHeaderStates={},visible=true,hiddenByParent=false,expandable=true,selected=false,
            isUsingSpawnables=true,childs=markers.children,origin={x=center.x,y=center.y,z=center.z,w=0},originInitialized=true,
            rotation={roll=0,pitch=0,yaw=0},pos={x=center.x,y=center.y,z=center.z,w=0},applyRotationWhenDropped=false}
        table.insert(children,group)
        for _,h in ipairs(markers.handles or {}) do table.insert(handles,h) end
    end
    local accepted,accept_err=self:_accept_skipped(skipped,#children,args)
    if not accepted then self.last_error=accept_err;return nil,accept_err end

    local group_name=GROUP_PREFIX..name
    local origin=centroid(handles)
    local blob={
        name=group_name,modulePath='modules/classes/editor/positionableGroup',
        headerOpen=false,propertyHeaderStates={},visible=true,hiddenByParent=false,expandable=true,selected=false,
        isUsingSpawnables=true,childs=children,
        origin=origin,originInitialized=true,rotation={roll=0,pitch=0,yaw=0},pos=origin,
    }
    -- WB's element.save writes data/objects/<fileName>.json relative to WB's own
    -- mod folder and refreshes its Saved list; CET does not let LS write there.
    local save=handles[1].save
    if type(save)~='function' then return nil,'World Builder element.save is unavailable in this WB version.' end
    local saved,save_err=pcall(save,{name=group_name,fileName=group_name,sUI=handles[1].sUI,serialize=function() return blob end})
    if not saved then self.last_error=tostring(save_err);return nil,'World Builder could not save group '..group_name..': '..tostring(save_err) end

    local previous={projectName=ui.projectName,xlFormat=ui.xlFormat,groups=ui.groups}
    local streaming=args.streaming or {}
    local exported,export_err=pcall(function()
        ui.projectName=name;ui.xlFormat=args.xl_format==1 and 1 or 0;ui.groups={}
        ui.addGroup(group_name)
        local group=ui.groups[1];if not group then error('World Builder did not register group '..group_name) end
        if args.category~=nil then group.category=tonumber(args.category) end
        if args.level~=nil then group.level=tonumber(args.level) end
        group.streamingX=tonumber(streaming.x) or group.streamingX
        group.streamingY=tonumber(streaming.y) or group.streamingY
        group.streamingZ=tonumber(streaming.z) or group.streamingZ
        ui.export()
    end)
    ui.projectName,ui.xlFormat,ui.groups=previous.projectName,previous.xlFormat,previous.groups
    if not exported then
        self.last_error=tostring(export_err)
        self:_log('error','export_failed',{name=name,error=self.last_error})
        return nil,'World Builder export failed: '..self.last_error
    end

    local issues={}
    for kind,list in pairs(ui.exportIssues or {}) do if type(list)=='table' and #list>0 then issues[kind]=Util.deepcopy(list) end end
    self.last_result={
        name=name,group=group_name,
        world_builder_group_file='data/objects/'..group_name..'.json',
        world_builder_export_file='export/'..name..'_exported.json',
        exported=#children,skipped=skipped,excluded_by_layer=Util.deepcopy(self.last_excluded_by_layer or {}),disabled_collision=Util.deepcopy(self.last_disabled_collision or {}),procedural=Util.deepcopy(self.last_procedural or {}),export_issues=issues,origin=origin,
    }
    self.last_error=nil
    self:_log('info','exported',{name=name,exported=#children,skipped=#skipped})
    return self.last_result
end

return BuildExport
