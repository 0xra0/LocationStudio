local Util=require('modules/util')
local Theme=require('ui/theme')

local Browser={}
Browser.__index=Browser

local function lower(v) return string.lower(tostring(v or '')) end

local function content_width()
    local ok,a,b=pcall(ImGui.GetContentRegionAvail)
    if not ok then return 1100 end
    if (type(a)=='table' or type(a)=='userdata') and a.x then return tonumber(a.x) or 1100 end
    return tonumber(a) or 1100
end

function Browser.new(app,notify)
    return setmetatable({
        app=app,notify=notify,search='',asset_name='New Asset',asset_category='Props',asset_kind='prop',asset_template='',asset_appearance='',validation=nil,last_preview_selection_revision=-1,
        asset_source='GAME',bulk_paths='',game_type='entity_template',game_query='',game_results=nil,game_auto_search_attempted=false,
        edit_asset_id=nil,edit_name='',edit_category='',edit_kind='',edit_template='',edit_appearance='',edit_layer='decoration',edit_tags='',edit_notes=''
    },Browser)
end

function Browser:log_action(action,fields)
    fields=fields or {};fields.action=action
    if self.app.logger then self.app.logger:info('ui:asset_action','clicked',fields) end
end

local function asset_name_from_path(path)
    local clean=tostring(path or ''):gsub('\\','/');local name=clean:match('([^/]+)$') or clean
    return name:gsub('%.[^%.]+$','')
end

function Browser:sync_asset_editor(asset)
    if not asset then return end
    self.edit_asset_id=asset.id;self.edit_name=asset.name or '';self.edit_category=asset.category or '';self.edit_kind=asset.kind or ''
    self.edit_template=asset.template or '';self.edit_appearance=asset.appearance or '';self.edit_layer=asset.layer or 'decoration'
    self.edit_tags=Util.join_csv(asset.tags or {});self.edit_notes=asset.notes or ''
end

function Browser:save_asset_editor()
    local id=self.edit_asset_id;local asset=id and self.app.model:get_asset(id)
    if not asset then return nil,'asset no longer exists' end
    local metadata=Util.deepcopy(asset.metadata or {})
    if metadata.world_builder then
        metadata.world_builder.resource_name=self.edit_name;metadata.world_builder.resource_path=self.edit_template
        if metadata.world_builder.entry and type(metadata.world_builder.entry.data)=='table' and metadata.world_builder.entry.data.spawnData~=nil then metadata.world_builder.entry.data.spawnData=self.edit_template end
    end
    local updated,err=self.app.model:update_asset(id,{name=self.edit_name,category=self.edit_category,kind=self.edit_kind,template=self.edit_template,appearance=self.edit_appearance,layer=self.edit_layer,tags=Util.split_csv(self.edit_tags),notes=self.edit_notes,metadata=metadata})
    if updated then self.app:mark_dirty();self.app.selection:set('asset',updated.id);self:log_action('save_asset',{asset_id=updated.id}) end
    return updated,err
end

function Browser:import_paths()
    local values,seen={},{}
    for line in tostring(self.bulk_paths or ''):gmatch('[^\r\n]+') do
        local path=Util.trim(line)
        if path~='' and string.sub(path,1,1)~='#' then
            local normalized=string.lower(path:gsub('/','\\'))
            if not seen[normalized] then
                seen[normalized]=true
                local extension=normalized:match('%.([^%.\\]+)$') or ''
                local value={name=asset_name_from_path(path),category=extension=='mesh' and 'Game / Mesh' or 'Imported',kind=extension=='mesh' and 'mesh' or 'entity',template=path:gsub('/','\\'),layer='decoration',tags={'imported'}}
                if extension=='mesh' then
                    value.metadata={world_builder={definition_key='mesh_static',category='Mesh',variant='Mesh',class_module='modules/classes/spawn/mesh/mesh',module_path='mesh/mesh',resource_name=value.name,resource_path=value.template,apply_scale=true,entry={name=path,fileName=value.name,data={spawnData=value.template}}}}
                end
                table.insert(values,value)
            end
        end
    end
    if #values==0 then return nil,'Paste one .ent or .mesh path per line.' end
    local existing={}
    for _,asset in ipairs(self.app.model.data.assets or {}) do existing[string.lower(tostring(asset.template or ''))]=true end
    local unique={};local skipped=0
    for _,value in ipairs(values) do local key=string.lower(value.template);if existing[key] then skipped=skipped+1 else existing[key]=true;table.insert(unique,value) end end
    local added=self.app.model:add_assets(unique);if #added>0 then self.app:mark_dirty();self.app.selection:set('asset',added[#added].id) end
    self:log_action('bulk_import',{added=#added,skipped=skipped})
    return {added=#added,skipped=skipped,assets=added}
end

function Browser:mark_used(asset)
    if not asset then return end
    self.app.model:mark_asset_used(asset.id);self.app:mark_dirty()
end

function Browser:select_asset(asset)
    self.app.selection:set('asset',asset.id);self:mark_used(asset)
end

function Browser:toggle_favorite(asset)
    local updated,err=self.app.model:set_asset_favorite(asset.id,not asset.favorite)
    if not updated then self.notify(err or 'Favorite update failed');return end
    self.app:mark_dirty();self.notify(updated.favorite and ('Favorited '..updated.name) or ('Removed favorite '..updated.name))
end

function Browser:auto_preview(asset)
    if not asset then return end
    local settings=self.app.model.data.settings.asset_preview or {}
    if settings.enabled==false or settings.auto_on_select==false then return end
    if self.last_preview_selection_revision==self.app.selection.revision then return end
    self.last_preview_selection_revision=self.app.selection.revision
    local status=self.app.placement:preview_status()
    if status.active and status.asset_id==asset.id then return end
    local _,err=self.app.placement:preview_asset(asset.id,{mode=settings.mode or 'aim',distance=settings.distance or 10,follow=settings.auto_follow~=false,surface_offset=settings.surface_offset,align_surface=settings.align_surface,stamp_mode=false,stamp_spacing=settings.stamp_spacing})
    if err and self.app.logger then self.app.logger:warn('ui:asset_preview','auto_preview_failed',{asset_id=asset.id,error=err}) end
end

function Browser:categories()
    local seen,out={},{}
    for _,asset in ipairs(self.app.model.data.assets or {}) do
        local c=Util.trim(asset.category);if c=='' then c='Uncategorized' end
        local key=lower(c)
        if not seen[key] then seen[key]=true;table.insert(out,c) end
    end
    table.sort(out,function(a,b) return lower(a)<lower(b) end)
    return out
end

function Browser:set_view(view)
    self.app.model.data.settings.asset_browser.view=view;self.app:mark_dirty()
end

function Browser:draw_view_button(label,view)
    local current=self.app.model.data.settings.asset_browser.view or 'ALL'
    if current==view then ImGui.PushStyleColor(ImGuiCol.Button,0.10,0.46,0.52,1) end
    if ImGui.Button(label..'##asset_view_'..view,96,26) then self:set_view(view) end
    if current==view then ImGui.PopStyleColor() end
end

function Browser:draw_filters(simple)
    local settings=self.app.model.data.settings.asset_browser
    self:draw_view_button('ALL','ALL');ImGui.SameLine();self:draw_view_button('FAVORITES','FAVORITES');ImGui.SameLine();self:draw_view_button('RECENT','RECENT')
    if simple then
        local current=settings.view or 'ALL';local preview='CATEGORY'
        if string.sub(current,1,9)=='CATEGORY:' then preview=string.sub(current,10) end
        ImGui.SameLine()
        if ImGui.BeginCombo('##asset_category_filter',preview) then
            for _,category in ipairs(self:categories()) do
                local view='CATEGORY:'..category
                if ImGui.Selectable(category,current==view) then self:set_view(view) end
            end
            ImGui.EndCombo()
        end
    else
        ImGui.SameLine();self:draw_view_button('MISSING','MISSING')
        for _,category in ipairs(self:categories()) do ImGui.SameLine();self:draw_view_button(category,'CATEGORY:'..category) end
    end
    ImGui.Separator()
end

function Browser:filtered_assets()
    local view=self.app.model.data.settings.asset_browser.view or 'ALL'
    local out={}
    for _,asset in ipairs(self.app.model.data.assets or {}) do
        local blob=asset.name..' '..asset.category..' '..asset.kind..' '..Util.join_csv(asset.tags)
        local match=Util.contains_ci(blob,self.search)
        if match then
            if view=='FAVORITES' then match=asset.favorite==true
            elseif view=='RECENT' then match=Util.trim(asset.last_used_at)~=''
            elseif view=='MISSING' then match=not self.app.thumbnails:has(asset)
            elseif string.sub(view,1,9)=='CATEGORY:' then match=lower(asset.category)==lower(string.sub(view,10)) end
        end
        if match then table.insert(out,asset) end
    end
    table.sort(out,function(a,b)
        if view=='RECENT' then
            local ar,br=tostring(a.last_used_at or ''),tostring(b.last_used_at or '')
            if ar~=br then return ar>br end
        end
        if a.favorite~=b.favorite then return a.favorite==true end
        if lower(a.category)~=lower(b.category) then return lower(a.category)<lower(b.category) end
        return lower(a.name)<lower(b.name)
    end)
    return out
end

function Browser:preview(asset,mode,follow)
    local settings=self.app.model.data.settings.asset_preview
    local options={mode=mode or 'aim',distance=settings.distance or 10,follow=follow==nil and settings.auto_follow~=false or follow,surface_offset=settings.surface_offset,align_surface=settings.align_surface,stamp_mode=settings.stamp_mode,stamp_spacing=settings.stamp_spacing}
    local _,err
    if settings.stamp_mode then _,err=self.app.placement:start_stamp(asset.id,options) else _,err=self.app.placement:preview_asset(asset.id,options) end
    self.notify(err or ('Previewing '..asset.name))
end


function Browser:place(asset)
    if not asset then return nil,'asset not found' end
    local settings=self.app.model.data.settings.asset_preview
    local status=self.app.placement:preview_status()
    local object,err
    if settings.stamp_mode and (not status.active or status.asset_id~=asset.id) then
        local started,start_err=self.app.placement:start_stamp(asset.id,{mode='aim',distance=settings.distance or 10,follow=true,surface_offset=settings.surface_offset,align_surface=settings.align_surface,stamp_spacing=settings.stamp_spacing})
        if not started then self.notify(start_err or 'Stamp preview failed');return nil,start_err end
        status=started
    end
    if status.active and status.asset_id==asset.id then
        object,err=self.app.placement:place_previewed(self.app.selected_premise_id,self.app.selected_room_id)
    else
        object,err=self.app.actions:place_asset(asset.id,'aim',{spawn=true})
    end
    if object then self:mark_used(asset);self.notify(err or ('Placed '..asset.name..'; runtime status: '..tostring((object.runtime or {}).status or 'not requested'))) else self.notify(err or 'Place failed') end
    return object,err
end

function Browser:place_and_edit(asset,mode)
    if not asset then return nil,'asset not found' end
    local settings=self.app.model.data.settings.asset_preview or {}
    if settings.stamp_mode==true then return self:place(asset) end
    self:select_asset(asset)
    local status=self.app.placement:preview_status()
    if not mode then mode=(status.active and status.asset_id==asset.id) and 'preview' or 'aim' end
    local result,err=self.app.transform_session:start_placement({
        kind='asset',id=asset.id,mode=mode,premise_id=self.app.selected_premise_id,room_id=self.app.selected_room_id,
        distance=settings.distance or 10,surface_offset=settings.surface_offset,align_surface=settings.align_surface==true,
    })
    self.notify(err or (result and ('Placement Edit started for '..asset.name) or 'Placement failed'))
    return result,err
end

function Browser:capture_thumbnail(asset)
    local result,err=self.app.thumbnails:capture(asset.id)
    if result then self.notify('Capturing real thumbnail for '..asset.name..'...') else self.notify(err or 'Thumbnail capture failed') end
end

function Browser:draw_thumbnail(asset,width,height)
    local ok,err=self.app.thumbnails:draw(asset,width,height)
    if ok then
        if ImGui.IsItemHovered and ImGui.IsItemHovered() and ImGui.IsItemClicked and ImGui.IsItemClicked(0) then self:select_asset(asset) end
        return true
    end
    ImGui.BeginChild('##thumb_placeholder_'..asset.id,width,height,true)
    ImGui.Spacing();ImGui.Spacing();Theme.warning('NO SNAPSHOT')
    ImGui.TextDisabled('Preview the real asset, then CAPTURE to cache a thumbnail.')
    if err and err~='thumbnail not captured' then ImGui.TextDisabled(tostring(err)) end
    ImGui.EndChild()
    return false
end

function Browser:draw_asset_card(asset,card_w,thumb_h,simple)
    local selected=self.app.selection:is('asset',asset.id)
    ImGui.BeginChild('##asset_grid_card_'..asset.id,card_w,thumb_h+(simple and 78 or 105),true)
    self:draw_thumbnail(asset,card_w-16,thumb_h)
    if ImGui.Selectable((selected and '> ' or '')..asset.name..'##asset_name_'..asset.id,selected) then self:select_asset(asset) end
    ImGui.SameLine();if ImGui.SmallButton((asset.favorite and '*' or '+')..'##fav_'..asset.id) then self:toggle_favorite(asset) end
    ImGui.TextDisabled(asset.category)
    if simple then
        if ImGui.SmallButton('PREVIEW##'..asset.id) then self:select_asset(asset);self:preview(asset,'aim') end
        ImGui.SameLine();if ImGui.SmallButton(((self.app.model.data.settings.asset_preview.stamp_mode and 'STAMP') or 'PLACE + EDIT')..'##'..asset.id) then self:place_and_edit(asset) end
    else
        if ImGui.SmallButton('PREVIEW##'..asset.id) then self:preview(asset,'aim') end
        ImGui.SameLine();if ImGui.SmallButton(((self.app.model.data.settings.asset_preview.stamp_mode and 'STAMP') or 'PLACE + EDIT')..'##'..asset.id) then self:place_and_edit(asset) end
        ImGui.SameLine();if ImGui.SmallButton('SNAP##'..asset.id) then self:capture_thumbnail(asset) end
        ImGui.SameLine();if ImGui.SmallButton('HERE + EDIT##'..asset.id) then self:place_and_edit(asset,'player') end
    end
    ImGui.EndChild()
end

function Browser:draw_asset_grid(simple)
    local list=self:filtered_assets()
    if #list==0 then
        Theme.warning('NO ASSETS IN THIS VIEW');ImGui.SameLine();ImGui.TextDisabled('Try ALL, another category, or clear the search.')
        return
    end
    local settings=self.app.model.data.settings.asset_browser
    local card_w=math.max(210,tonumber(settings.card_width) or 246)
    local thumb_h=math.max(110,tonumber(settings.thumbnail_height) or 138)
    local columns=math.max(1,math.floor(content_width()/(card_w+8)))
    for i,asset in ipairs(list) do
        self:draw_asset_card(asset,card_w,thumb_h,simple)
        if i%columns~=0 then ImGui.SameLine() end
    end
end

function Browser:draw_asset_preview_panel(selected_asset)
    local app=self.app
    local simple=app.model.data.settings.workspace.beginner_mode~=false
    local settings=app.model.data.settings.asset_preview
    local status=app.placement:preview_status()
    local thumb_status=app.thumbnails:status()
    Theme.section('SELECTED ASSET',simple and 'preview -> place' or 'snapshot + temporary live preview')
    if not selected_asset then
        ImGui.TextDisabled('Select an asset card to inspect it.');return
    end

    self:auto_preview(selected_asset)
    ImGui.BeginChild('##selected_asset_thumb',220,300,true)
    local shown=app.thumbnails:draw(selected_asset,204,204)
    if not shown then ImGui.Spacing();ImGui.Spacing();Theme.warning('NO THUMBNAIL');ImGui.TextWrapped('Capture one real in-game snapshot for this asset.') end
    ImGui.EndChild();ImGui.SameLine()
    ImGui.BeginChild('##selected_asset_info',0,300,false)
    Theme.accent(selected_asset.name);ImGui.SameLine();ImGui.TextDisabled(selected_asset.category..' / '..selected_asset.kind)
    if not simple then
        ImGui.TextWrapped(selected_asset.template or '')
        if selected_asset.appearance and selected_asset.appearance~='' then ImGui.TextDisabled('Appearance: '..selected_asset.appearance) end
        ImGui.TextDisabled(string.format('Approx size %.2f x %.2f x %.2f',selected_asset.size.x or 0,selected_asset.size.y or 0,selected_asset.size.z or 0))
        local changed
        settings.enabled,changed=ImGui.Checkbox('Enable live preview',settings.enabled~=false);if changed then app:mark_dirty();if settings.enabled==false then app.placement:clear_preview() end end
        ImGui.SameLine();settings.auto_on_select,changed=ImGui.Checkbox('Auto-preview on select',settings.auto_on_select==true);if changed then app:mark_dirty() end
        ImGui.SameLine();settings.auto_follow,changed=ImGui.Checkbox('Follow aim',settings.auto_follow~=false);if changed then app:mark_dirty() end
        settings.distance,changed=ImGui.InputFloat('Preview distance',settings.distance or 10,0.25,1,'%.2f');if changed then app:mark_dirty() end
    else
        ImGui.TextWrapped('Preview is temporary. PLACE commits the asset at the preview position, or at your crosshair when no preview is active.')
    end

    local changed
    settings.align_surface,changed=ImGui.Checkbox('Align preview to surface',settings.align_surface==true);if changed then app:mark_dirty();if status.active and status.asset_id==selected_asset.id then self:preview(selected_asset,'aim',true) end end
    ImGui.SameLine();local next_stamp;next_stamp,changed=ImGui.Checkbox('Stamp placement',settings.stamp_mode==true)
    if changed then
        if app.stamp_session and app.stamp_session:is_active() then settings.stamp_mode=true;self.notify('Commit or cancel the active stamp stroke first.')
        else settings.stamp_mode=next_stamp;app:mark_dirty() end
    end
    if settings.stamp_mode then
        ImGui.SameLine();ImGui.PushItemWidth(105);settings.stamp_spacing,changed=ImGui.InputFloat('Min spacing',tonumber(settings.stamp_spacing) or 0.5,0.05,0.25,'%.2f');ImGui.PopItemWidth();if changed then settings.stamp_spacing=math.max(0,settings.stamp_spacing);app:mark_dirty() end
    end

    if Theme.action_button(settings.stamp_mode and 'START STROKE' or 'PREVIEW',settings.stamp_mode and 140 or 120,32) then self:preview(selected_asset,'aim') end
    ImGui.SameLine();if Theme.primary_button(settings.stamp_mode and 'STAMP NOW' or 'PLACE',settings.stamp_mode and 140 or 120,32) then self:place(selected_asset) end
    ImGui.SameLine();if Theme.action_button('EDIT ASSET',120,32) then self:sync_asset_editor(selected_asset);ImGui.OpenPopup('Edit Asset##ls') end
    if not shown then ImGui.SameLine();if Theme.action_button('MAKE THUMBNAIL',155,32) then self:capture_thumbnail(selected_asset) end end
    if status.active and status.asset_id==selected_asset.id then
        if status.stroke_active then
            ImGui.SameLine();if Theme.primary_button('COMMIT STROKE',140,32) then local result,err=app.stamp_session:commit();self.notify(err or (result and 'Stamp stroke committed' or 'Commit failed')) end
            ImGui.SameLine();if Theme.danger_button('CANCEL STROKE',135,32) then local result,err=app.stamp_session:cancel();self.notify(err or (result and 'Stamp stroke cancelled' or 'Cancel failed')) end
        else
            ImGui.SameLine();if ImGui.Button('CLEAR PREVIEW',130,32) then local _,err=app.placement:clear_preview();self.notify(err or 'Preview cleared') end
        end
    end
    if not simple and shown then ImGui.SameLine();if ImGui.Button('REFRESH THUMB',135,32) then self:capture_thumbnail(selected_asset) end end

    if thumb_status.pending then Theme.warning('CAPTURING THUMBNAIL...')
    elseif thumb_status.last_error then Theme.warning(thumb_status.last_error) end
    if status.asset_id==selected_asset.id then
        Theme.info((status.stroke_active and ('STROKE: '..tostring(status.placed_count or 0)..' OBJECT(S) / ') or 'PREVIEW: ')..string.upper(status.status or 'idle'))
        if status.last_error then ImGui.TextWrapped(status.last_error) end
    end
    ImGui.EndChild()
end

function Browser:draw_asset_popups()
    if ImGui.BeginPopup('Register Asset##ls') then
        Theme.section('Register Game Entity','.ent path saved to Project Assets')
        self.asset_name=select(1,ImGui.InputText('Name',self.asset_name,128));self.asset_category=select(1,ImGui.InputText('Category',self.asset_category,64));self.asset_kind=select(1,ImGui.InputText('Kind',self.asset_kind,64));self.asset_template=select(1,ImGui.InputText('Entity template',self.asset_template,512));self.asset_appearance=select(1,ImGui.InputText('Appearance',self.asset_appearance,128))
        if ImGui.Button('ADD TO PROJECT ASSETS',205,30) then
            if Util.trim(self.asset_template)=='' then self.notify('Enter a valid .ent template path.') else
                local asset=self.app.model:add_asset({name=self.asset_name,category=self.asset_category,kind=self.asset_kind,template=self.asset_template,appearance=self.asset_appearance})
                self:select_asset(asset);self.app:mark_dirty();self.asset_name='New Asset';self.asset_template='';self.asset_appearance='';self:log_action('register_asset',{asset_id=asset.id});ImGui.CloseCurrentPopup();self.notify('Asset registered')
            end
        end
        ImGui.EndPopup()
    end
    if ImGui.BeginPopup('Bulk Import##ls') then
        Theme.section('Bulk Import','one .ent or .mesh depot path per line')
        ImGui.TextWrapped('Entity paths use CET spawning. Mesh paths use the World Builder 1.0.81 adapter.')
        self.bulk_paths=select(1,ImGui.InputTextMultiline('##bulk_asset_paths',self.bulk_paths,32768,640,230))
        if ImGui.Button('IMPORT PATHS',155,30) then local result,err=self:import_paths();if result then self.notify(string.format('Imported %d; skipped %d existing.',result.added,result.skipped));self.bulk_paths='';ImGui.CloseCurrentPopup() else self.notify(err) end end
        ImGui.EndPopup()
    end
    if ImGui.BeginPopup('Edit Asset##ls') then
        local asset=self.edit_asset_id and self.app.model:get_asset(self.edit_asset_id)
        if not asset then ImGui.TextDisabled('Asset no longer exists.') else
            Theme.section('Edit Project Asset',asset.id)
            self.edit_name=select(1,ImGui.InputText('Name##edit_asset',self.edit_name,160));self.edit_category=select(1,ImGui.InputText('Category##edit_asset',self.edit_category,96));self.edit_kind=select(1,ImGui.InputText('Kind##edit_asset',self.edit_kind,64))
            self.edit_template=select(1,ImGui.InputText('Template / resource##edit_asset',self.edit_template,512));self.edit_appearance=select(1,ImGui.InputText('Appearance##edit_asset',self.edit_appearance,128));self.edit_layer=select(1,ImGui.InputText('Layer##edit_asset',self.edit_layer,64))
            self.edit_tags=select(1,ImGui.InputText('Tags##edit_asset',self.edit_tags,256));self.edit_notes=select(1,ImGui.InputTextMultiline('Notes##edit_asset',self.edit_notes,1024,520,70))
            if Theme.primary_button('SAVE CHANGES',145,30) then local updated,err=self:save_asset_editor();if updated then ImGui.CloseCurrentPopup();self.notify('Saved '..updated.name) else self.notify(err) end end
            ImGui.SameLine();if ImGui.Button('DUPLICATE',110,30) then self.app.selection:set('asset',asset.id);local copy,err=self.app.actions:duplicate_selected();if copy then self:sync_asset_editor(copy);self.notify('Duplicated '..copy.name) else self.notify(err) end end
            ImGui.SameLine();if Theme.danger_button('DELETE',90,30) then self.app.selection:set('asset',asset.id);local ok,err=self.app.actions:delete_selected();if ok then self.edit_asset_id=nil;ImGui.CloseCurrentPopup();self.notify('Asset deleted') else self.notify(err) end end
        end
        ImGui.EndPopup()
    end
end

function Browser:run_game_search(force)
    if not self.app.world_builder then return nil,'World Builder integration is unavailable' end
    local result,err=self.app.world_builder:search(self.game_type,self.game_query,60,force)
    if result then self.game_results=result;self:log_action('search_game_resources',{type=self.game_type,query=self.game_query,total=result.total}) end
    return result,err
end

function Browser:draw_game_resources()
    local wb=self.app.world_builder;local status=wb and wb:status() or {available=false,reason='World Builder integration is unavailable'}
    if not status.catalog_available then Theme.bad('GAME RESOURCE CATALOG OFFLINE');ImGui.TextWrapped(tostring(status.reason));ImGui.TextDisabled('Install/start World Builder 1.0.81, then reopen the CET overlay.');return end
    Theme.good('WORLD BUILDER GAME DATABASE CONNECTED');ImGui.SameLine();ImGui.TextDisabled('Searches the full loaded resource lists; results are paged to keep CET responsive.')
    local definitions=wb:definitions();local current=wb:definition(self.game_type) or definitions[1]
    ImGui.PushItemWidth(235)
    if ImGui.BeginCombo('Resource type',current.label) then for _,definition in ipairs(definitions) do if ImGui.Selectable(definition.label,definition.key==self.game_type) then self.game_type=definition.key;self.game_results=nil;self.game_auto_search_attempted=false end end;ImGui.EndCombo() end
    ImGui.PopItemWidth();ImGui.SameLine();ImGui.PushItemWidth(360);self.game_query=select(1,ImGui.InputTextWithHint('##game_asset_query','Search names or depot paths...',self.game_query,256));ImGui.PopItemWidth()
    ImGui.SameLine();if Theme.primary_button('SEARCH GAME',130,28) then local _,err=self:run_game_search(false);if err then self.notify(err) end end
    ImGui.SameLine();if ImGui.Button('RELOAD INDEX',125,28) then local _,err=self:run_game_search(true);if err then self.notify(err) end end
    if not self.game_results and not self.game_auto_search_attempted then
        self.game_auto_search_attempted=true
        local _,err=self:run_game_search(false);if err then self.notify(err) end
    end
    if not self.game_results then ImGui.Separator();ImGui.TextWrapped('The game database could not be indexed. Press RELOAD INDEX after opening World Builder once.');return end
    local result=self.game_results
    ImGui.Separator();Theme.info(string.format('%d matching resources / showing %d',result.total or 0,result.shown or 0))
    if result.shown>0 and ImGui.Button('ADD SHOWN TO PROJECT ASSETS',235,28) then local imported=wb:import_many(result.items);self.notify(string.format('Added %d; skipped %d existing.',imported.added,imported.skipped)) end
    ImGui.BeginChild('##game_resource_results',0,430,true)
    for _,resource in ipairs(result.items or {}) do
        local rid=tostring(resource.definition.key)..'_'..tostring(resource.index)
        Theme.accent(resource.name);ImGui.SameLine();ImGui.TextDisabled(resource.definition.label)
        if resource.path~='' then ImGui.TextWrapped(resource.path) else ImGui.TextDisabled('Configured World Builder resource') end
        local existing=wb:find_project_asset(resource)
        if ImGui.Button((existing and 'IN PROJECT' or 'ADD')..'##resource_'..rid,105,26) and not existing then local asset,err=wb:import_resource(resource);if asset then self:select_asset(asset);self.notify(err or ('Added '..asset.name)) else self.notify(err) end end
        ImGui.SameLine();if ImGui.Button('PREVIEW##resource_'..rid,105,26) then local asset=existing or select(1,wb:import_resource(resource));if asset then self:select_asset(asset);self:preview(asset,'aim',false) end end
        ImGui.SameLine();if Theme.primary_button('PLACE NOW##resource_'..rid,115,26) then local asset=existing or select(1,wb:import_resource(resource));if asset then self:select_asset(asset);self:place(asset) end end
        ImGui.Separator()
    end
    ImGui.EndChild()
end

function Browser:assets()
    local app=self.app;local simple=app.model.data.settings.workspace.beginner_mode~=false
    if Theme.nav_button('GAME DATABASE',self.asset_source=='GAME',155,30) then self.asset_source='GAME' end
    ImGui.SameLine();if Theme.nav_button('MY ASSETS ('..tostring(#(app.model.data.assets or {}))..')',self.asset_source=='PROJECT',155,30) then self.asset_source='PROJECT' end
    ImGui.SameLine();Theme.muted(string.format('%d saved / unlimited game catalog',#(app.model.data.assets or {})))
    ImGui.Separator()
    if self.asset_source=='GAME' then self:draw_game_resources();self:draw_asset_popups();return end
    ImGui.PushItemWidth(280);self.search=select(1,ImGui.InputTextWithHint('##asset_search',simple and 'Search project assets...' or 'Search project asset catalog...',self.search,128));ImGui.PopItemWidth()
    ImGui.SameLine();if ImGui.Button('+ REGISTER .ENT') then ImGui.OpenPopup('Register Asset##ls') end
    ImGui.SameLine();if ImGui.Button('BULK IMPORT') then ImGui.OpenPopup('Bulk Import##ls') end
    ImGui.SameLine();ImGui.TextDisabled('Select, preview, place, edit, duplicate, or delete.')
    ImGui.Separator()
    if #app.model.data.assets==0 then
        Theme.warning('OBJECT LIBRARY EMPTY');ImGui.SameLine();ImGui.TextDisabled(simple and 'That is OK - continue building rooms. Advanced mode adds custom .ent registration.' or 'Register a real .ent path to start the visual asset library.')
        self:draw_asset_popups();return
    end
    self:draw_filters(simple);self:draw_asset_grid(simple);ImGui.Separator()
    self:draw_asset_preview_panel(app.model:get_asset(app.selected_asset_id or app.last_asset_id))
    self:draw_asset_popups()
end

function Browser:prefabs()
    ImGui.TextWrapped('Prefabs create editable room structures. They do not hide generated pieces: every room and shell object appears in the scene tree.')
    ImGui.Spacing()
    for _,p in ipairs({{'CLINIC','clinic','Reception + corridor + treatment room'}, {'APARTMENT','apartment','Living, bedroom, and bathroom'}, {'WAREHOUSE','warehouse','Large bay with an office'}}) do
        ImGui.BeginChild('##prefab_'..p[2],250,105,true);Theme.accent(p[1]);ImGui.TextWrapped(p[3])
        if ImGui.Button('BUILD##'..p[2],100,28) then
            self:log_action('build_prefab',{kind=p[2]})
            if not self.app.selected_premise_id then self.notify('Select a premise first') else local result,err=self.app.quickstart:create_prefab_here(p[2],{});if result then self.notify(err or (p[1]..' prefab built and spawned')) else self.notify(err) end end
        end
        ImGui.EndChild();ImGui.SameLine()
    end
    ImGui.NewLine()
end

function Browser:diagnostics()
    if ImGui.Button('RUN VALIDATION',160,30) then self.validation=self.app.model:validate() end
    ImGui.SameLine();local status=self.app.placement:status();ImGui.TextDisabled(string.format('Runtime: %d spawned / %d markers',status.spawned,status.markers))
    ImGui.Separator();local issues=self.validation or {}
    if not self.validation then ImGui.TextDisabled('Run validation before build/export.') elseif #issues==0 then Theme.good('NO ISSUES') else
        for i,v in ipairs(issues) do
            if v.severity=='error' then Theme.bad('[ERROR] '..v.message) elseif v.severity=='warning' then Theme.warning('[WARN] '..v.message) else ImGui.TextDisabled('[INFO] '..v.message) end
            if i>=20 then ImGui.TextDisabled('Showing first 20 issues');break end
        end
    end
end

function Browser:export()
    ImGui.Text('Save once, then hand the same project to runtime, World Builder, QuestForge, or Claude MCP.')
    if ImGui.Button('SAVE PROJECT',150,30) then local ok,err=self.app:save(true);self.notify(ok and 'Project saved' or err) end
    for _,v in ipairs({{'JSON','json'},{'CSV','csv'},{'CET LUA','lua'},{'WORLD BUILDER','worldbuilder'},{'QUESTFORGE','questforge'}}) do
        ImGui.SameLine();if ImGui.Button(v[1]..'##export',140,30) then local ok,path=self.app:export(v[2]);self.notify(ok and ('Exported '..path) or path) end
    end
    ImGui.Separator();ImGui.TextDisabled('MCP bridge: ready | semantic commands only | no arbitrary Lua execution')
end

function Browser:logs()
    local logger=self.app.logger;local status=logger:status()
    ImGui.TextWrapped('Runtime log: '..status.path)
    ImGui.TextWrapped('Diagnostic report: logs/locationstudio-diagnostics.json')
    if ImGui.Button('RUN DIAGNOSTICS',170,30) then if self.app.diagnostics then self.app.diagnostics:run();self.notify('Diagnostic report written') else self.notify('Diagnostics unavailable') end end
    ImGui.SameLine();if ImGui.Button('CLEAR LOG',120,30) then local ok,err=logger:clear();self.notify(ok and 'Log cleared' or err) end
    ImGui.Separator()
    for _,line in ipairs(logger:read_tail(80)) do ImGui.TextWrapped(line) end
end

function Browser:draw()
    local simple=self.app.model.data.settings.workspace.beginner_mode~=false
    if ImGui.BeginTabBar('##bottom_browser') then
        if ImGui.BeginTabItem(simple and 'OBJECTS' or 'ASSET BROWSER') then self:assets();ImGui.EndTabItem() end
        if simple then
            if ImGui.BeginTabItem('READY LAYOUTS') then self:prefabs();ImGui.EndTabItem() end
        else
            if ImGui.BeginTabItem('PREMISES PREFABS') then self:prefabs();ImGui.EndTabItem() end
            if ImGui.BeginTabItem('VALIDATION') then self:diagnostics();ImGui.EndTabItem() end
            if ImGui.BeginTabItem('BUILD + EXPORT') then self:export();ImGui.EndTabItem() end
            if ImGui.BeginTabItem('DEBUG LOG') then self:logs();ImGui.EndTabItem() end
        end
        ImGui.EndTabBar()
    end
end

return Browser
