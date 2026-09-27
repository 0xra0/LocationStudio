local Theme=require('ui/theme')

local Director={}
Director.__index=Director

function Director.new(app,notify)
    return setmetatable({app=app,notify=notify,new_name='New Scene',include_construction=false},Director)
end

function Director:toast(value) if self.notify then self.notify(value) end end

function Director:current()
    local app=self.app
    return app.model:get_scene(app.editing_scene_id) or (app.selected_scene_id and app.model:get_scene(app.selected_scene_id))
end

function Director:create_from_selection()
    local app=self.app;local members,err=app.scenes:selection_members();if not members then self:toast(err);return end
    local premise_id=app.selected_premise_id
    if not premise_id then self:toast('Select an object or room inside a location first.');return end
    local args={name=self.new_name,premise_id=premise_id,kind='gameplay'};for field,values in pairs(members) do args[field]=values end
    local scene;scene,err=app.scenes:create(args);self:toast(scene and ('Created '..scene.name..' from the current selection.') or err)
end

function Director:draw()
    local app=self.app;local status=app.scenes:status();local scene=self:current()
    Theme.section('SCENE DIRECTOR','real membership and runtime lifecycle')
    if status.editing_scene_id then Theme.pill('EDIT  '..tostring(status.editing_scene_name),'info') else Theme.pill('NO EDITING SCENE','warn') end
    ImGui.SameLine();if status.live_scene_id then Theme.pill('LIVE  '..tostring(status.live_scene_name),'good') else Theme.pill('NO LIVE SCENE','warn') end
    ImGui.SameLine();Theme.muted(tostring(status.scene_count or 0)..' scene collection(s)')

    self.new_name=select(1,ImGui.InputTextWithHint('##scene_director_name','Scene name',self.new_name,96))
    if Theme.primary_button('NEW FROM LOCATION',175,30) then
        local result,err=app.scenes:capture_premise({name=self.new_name,premise_id=app.selected_premise_id,include_construction=self.include_construction})
        self:toast(result and ('Captured '..result.scene.name..'.') or err)
    end
    ImGui.SameLine();if Theme.action_button('NEW FROM SELECTED',175,30) then self:create_from_selection() end
    ImGui.SameLine();self.include_construction=select(1,ImGui.Checkbox('Include construction pieces',self.include_construction))
    Theme.muted('Location capture includes rooms, placed props, volumes and cameras. Room shells are owned through their rooms; construction pieces are optional.')

    if not scene then ImGui.Separator();ImGui.TextWrapped('Choose a scene in the hierarchy, or create one from the active location/current selection. The editing scene remains remembered while you select objects.') return end
    ImGui.Separator();Theme.accent(scene.name);ImGui.SameLine();Theme.muted(scene.kind..' / '..scene.id)
    ImGui.TextWrapped(string.format('%d rooms  |  %d objects  |  %d points  |  %d volumes  |  %d cameras  |  %d routes',#(scene.room_ids or {}),#(scene.object_ids or {}),#(scene.location_ids or {}),#(scene.volume_ids or {}),#(scene.camera_ids or {}),#(scene.route_ids or {})))

    if Theme.primary_button('ACTIVATE',105,30) then local result,err=app.scenes:activate(scene.id,true);self:toast(result and (err or ('Activated '..scene.name..'.')) or err) end
    ImGui.SameLine();if Theme.action_button('ISOLATE',95,30) then local result,err=app.scenes:isolate(scene.id);self:toast(result and (err or ('Isolated '..scene.name..'.')) or err) end
    ImGui.SameLine();if Theme.action_button('DEACTIVATE',120,30) then local result,err=app.scenes:deactivate(scene.id);self:toast(result and (err or ('Deactivated '..scene.name..'.')) or err) end
    ImGui.SameLine();if Theme.action_button('SELECT OBJECTS',140,30) then local result,err=app.scenes:select_objects(scene.id);self:toast(result and ('Selected '..result.selected..' explicit scene object(s).') or err) end

    if Theme.action_button('ADD CURRENT SELECTION',190,30) then local result,err=app.scenes:edit_current_selection(scene.id,'add');self:toast(result and 'Selection added to scene.' or err) end
    ImGui.SameLine();if Theme.action_button('REMOVE CURRENT SELECTION',210,30) then local result,err=app.scenes:edit_current_selection(scene.id,'remove');self:toast(result and 'Selection removed from scene.' or err) end
    ImGui.SameLine();if Theme.action_button('SYNC LOCATION CONTENT',190,30) then
        local result,err=app.scenes:capture_premise({scene_id=scene.id,premise_id=scene.premise_id,mode='replace',include_construction=self.include_construction})
        self:toast(result and 'Scene membership synchronized with the location.' or err)
    end
    Theme.muted('Activate spawns only this scene. Isolate first despawns other tracked project objects. Deactivate removes the scene runtime objects but preserves every saved member.')
    if status.last_error then Theme.warning(tostring(status.last_error)) end
end

return Director
