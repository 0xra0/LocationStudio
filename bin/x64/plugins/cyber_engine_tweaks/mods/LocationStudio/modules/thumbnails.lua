local Util=require('modules/util')

local Thumbnails={}
Thumbnails.__index=Thumbnails

local MOD_REL='bin\\x64\\plugins\\cyber_engine_tweaks\\mods\\LocationStudio'
local prefab_image_path

local function shell_quote_posix(s)
    s=tostring(s or '')
    return "'"..string.gsub(s,"'","'\\''").."'"
end

local function shell_quote_win(s)
    s=tostring(s or '')
    return '"'..string.gsub(s,'"','\\"')..'"'
end

local function trim_line(s)
    return tostring(s or ''):gsub('[\r\n]+$','')
end

local function file_size(path)
    local f=io.open(path,'rb')
    if not f then return 0 end
    local ok,size=pcall(function() return f:seek('end') end)
    f:close()
    if not ok then return 0 end
    return tonumber(size) or 0
end

local function normalize_unix_env_path(path)
    path=trim_line(path)
    if path=='' then return nil end
    if path:match('^[Zz]:[\\/]') then
        path=path:sub(3):gsub('\\','/')
        if path:sub(1,1)~='/' then path='/'..path end
        return path
    end
    if path:sub(1,1)=='/' then return path end
    return nil
end

function Thumbnails.new(app)
    return setmetatable({
        app=app,textures={},texture_errors={},pending=nil,last_result=nil,last_error=nil,
        restore_window=nil,restore_at=0,mod_root_windows=nil,mod_root_unix=nil,
    },Thumbnails)
end

function Thumbnails:path(asset_or_id)
    local asset=type(asset_or_id)=='table' and asset_or_id or self.app.model:get_asset(asset_or_id)
    if not asset then return nil end
    local path=Util.trim(asset.thumbnail_path):gsub('\\','/')
    if not path:match('^thumbnails/[%w_-]+%.png$') then path='thumbnails/'..tostring(asset.id):gsub('[^%w_-]','_')..'.png' end
    return path
end

function Thumbnails:prefab_path(prefab)
    prefab=type(prefab)=='table' and prefab or self.app.model:get_object_prefab(prefab)
    if not prefab then return nil end
    local path=Util.trim(prefab.thumbnail_path):gsub('\\','/')
    if not path:match('^thumbnails/prefab_[%w_-]+%.png$') then path=prefab_image_path(prefab) end
    return path
end

function Thumbnails:has_prefab(prefab)
    local path=self:prefab_path(prefab)
    return path~=nil and Util.file_exists(path) and file_size(path)>64
end

function Thumbnails:draw_prefab(prefab,width,height)
    prefab=type(prefab)=='table' and prefab or self.app.model:get_object_prefab(prefab)
    if not prefab then return false,'prefab not found' end
    local path=self:prefab_path(prefab)
    if not self:has_prefab(prefab) then return false,'prefab thumbnail not rendered' end
    local key='prefab:'..prefab.id;local texture=self.textures[key]
    if not texture then
        if not ImGui or type(ImGui.LoadTexture)~='function' then return false,'CET ImGui.LoadTexture is unavailable' end
        local err;texture,err=ImGui.LoadTexture(path)
        if not texture then self.texture_errors[key]=tostring(err or 'texture load failed');return false,self.texture_errors[key] end
        self.textures[key]=texture;self.texture_errors[key]=nil
    end
    local size=(ImVec2 and ImVec2(tonumber(width) or 100,tonumber(height) or 72)) or {x=width or 100,y=height or 72}
    local ok,err=pcall(function() ImGui.Image(texture,size) end)
    if not ok then return false,tostring(err) end
    return true
end

function Thumbnails:has(asset_or_id)
    local path=self:path(asset_or_id)
    return path~=nil and Util.file_exists(path) and file_size(path)>64
end

function Thumbnails:_release_texture(asset_id)
    local texture=self.textures[asset_id]
    if texture then pcall(function() texture:Release() end) end
    self.textures[asset_id]=nil;self.texture_errors[asset_id]=nil
end

function Thumbnails:invalidate(asset_id)
    self:_release_texture(asset_id)
end

function Thumbnails:texture(asset_or_id)
    local asset=type(asset_or_id)=='table' and asset_or_id or self.app.model:get_asset(asset_or_id)
    if not asset then return nil,'asset not found' end
    if not self:has(asset) then return nil,'thumbnail not captured' end
    if self.textures[asset.id] then return self.textures[asset.id] end
    if not ImGui or type(ImGui.LoadTexture)~='function' then return nil,'CET ImGui.LoadTexture is unavailable' end
    local texture,err=ImGui.LoadTexture(self:path(asset))
    if not texture then
        self.texture_errors[asset.id]=tostring(err or 'texture load failed')
        return nil,self.texture_errors[asset.id]
    end
    self.textures[asset.id]=texture;self.texture_errors[asset.id]=nil
    return texture
end

function Thumbnails:draw(asset_or_id,width,height)
    local texture,err=self:texture(asset_or_id)
    if not texture then return false,err end
    width=tonumber(width) or 220;height=tonumber(height) or 132
    local size=(ImVec2 and ImVec2(width,height)) or {x=width,y=height}
    local ok,image_err=pcall(function() ImGui.Image(texture,size) end)
    if not ok then return false,tostring(image_err) end
    return true
end

function Thumbnails:_discover_mod_root_windows()
    if self.mod_root_windows then return self.mod_root_windows end
    -- CET starts with the game directory as its process working directory in normal installs.
    -- The command also tolerates a caller already inside the mod directory.
    local command='cmd /c "(if exist '..MOD_REL..'\\init.lua (cd /d '..MOD_REL..') else (cd /d .)) & cd > data\\_runtime_mod_root.txt"'
    pcall(os.execute,command)
    local text=Util.read_file('data/_runtime_mod_root.txt')
    text=trim_line(text)
    if text=='' then return nil,'could not resolve LocationStudio runtime path' end
    self.mod_root_windows=text
    return text
end

function Thumbnails:_windows_to_unix(path)
    path=trim_line(path)
    if path:match('^[Zz]:[\\/]') then
        local p=path:sub(3):gsub('\\','/')
        if p:sub(1,1)~='/' then p='/'..p end
        return p
    end
    if path:match('^[Cc]:[\\/]') then
        local tail=path:sub(4):gsub('\\','/')
        local wineprefix=normalize_unix_env_path(os.getenv('WINEPREFIX'))
        if wineprefix then return wineprefix..'/drive_c/'..tail end
        local compat=normalize_unix_env_path(os.getenv('STEAM_COMPAT_DATA_PATH'))
        if compat then return compat..'/pfx/drive_c/'..tail end
    end
    return nil
end

function Thumbnails:_capture_backend(output_path,delay_seconds)
    local root,err=self:_discover_mod_root_windows();if not root then return nil,err end
    local is_wine=os.getenv('WINEPREFIX')~=nil or os.getenv('STEAM_COMPAT_DATA_PATH')~=nil or root:match('^[Zz]:[\\/]')~=nil
    if is_wine then
        local unix_root=self.mod_root_unix or self:_windows_to_unix(root)
        if not unix_root then return nil,'Proton/Wine detected but LocationStudio path could not be converted to a Unix path' end
        self.mod_root_unix=unix_root
        local script=unix_root..'/tools/capture_thumbnail.sh'
        local output=unix_root..'/'..output_path:gsub('\\','/')
        local cmd='cmd /c start "" /b /unix /bin/sh '..shell_quote_win(script)..' '..shell_quote_win(output)..' '..tostring(tonumber(delay_seconds) or 0.45)
        return cmd,'proton-linux'
    end
    local script=root..'\\tools\\capture_thumbnail.ps1'
    local output=root..'\\'..output_path:gsub('/','\\')
    local cmd='cmd /c start "" /b powershell.exe -NoProfile -ExecutionPolicy Bypass -File '..shell_quote_win(script)..' -Output '..shell_quote_win(output)..' -Delay '..tostring(tonumber(delay_seconds) or 0.45)
    return cmd,'windows-powershell'
end

function Thumbnails:capture(asset_or_id,options)
    options=options or {}
    if self.pending then return nil,'another thumbnail capture is already running' end
    local asset=type(asset_or_id)=='table' and asset_or_id or self.app.model:get_asset(asset_or_id)
    if not asset then return nil,'asset not found' end
    if Util.trim(asset.template)=='' then return nil,'asset has no .ent template' end
    if type(os.execute)~='function' then return nil,'Automatic screenshots are unavailable in this CET sandbox. Use tools/capture_thumbnail.sh from Linux, or copy a PNG to '..self:path(asset) end
    if type(os.getenv)~='function' or type(os.rename)~='function' then return nil,'Screenshot helper support is unavailable. Copy a PNG to '..self:path(asset) end

    local final_path=self:path(asset)
    local path=final_path:gsub('%.png$','_capture.png')
    local command,backend=self:_capture_backend(path)
    if not command then return nil,backend end

    local settings=self.app.model.data.settings.asset_preview or {}
    local preview,warning=self.app.placement:preview_asset(asset.id,{mode='aim',distance=options.distance or settings.distance or 10,follow=false,surface_offset=settings.surface_offset})
    if not preview then return nil,warning end
    self.app.model:mark_asset_used(asset.id);self.app:mark_dirty()

    pcall(os.remove,path);pcall(os.remove,path..'.error')

    self.restore_window=self.app.editor_visible~=false
    self.app.editor_visible=false
    self.restore_at=os.clock()+1.15
    self.pending={asset_id=asset.id,path=path,final_path=final_path,backend=backend,started=os.clock(),deadline=os.clock()+12.0,warning=warning}
    self.last_error=nil;self.last_result=nil
    if self.app.logger then self.app.logger:info('thumbnail:capture','started',{asset_id=asset.id,name=asset.name,backend=backend,path=path}) end

    local ok,result,why,code=pcall(os.execute,command)
    if not ok or result==false or result==nil or (type(result)=='number' and result~=0) then
        self.app.editor_visible=self.restore_window;self.restore_window=nil;self.app.placement:clear_preview();self.pending=nil
        self.last_error='Screenshot helper launch failed: '..tostring(result)..' '..tostring(why or code or '');return nil,self.last_error
    end
    return {pending=true,asset_id=asset.id,backend=backend,path=path},warning
end

prefab_image_path=function(prefab)
    local id=tostring(prefab.id or ''):gsub('[^%w_-]','_')
    return 'thumbnails/prefab_'..id..'.png'
end

function Thumbnails:_cleanup_prefab(pending)
    local failures={}
    for index=#(pending.spawned or {}),1,-1 do
        local item=pending.spawned[index]
        if not item.cleaned then
            local ok,result,err=pcall(function() return self.app.runtime_shell:despawn(item.object) end)
            if not ok or result==false then table.insert(failures,{id=item.object.id,error=tostring(ok and (err or 'World Builder refused removal') or result)})
            else item.cleaned=true end
        end
    end
    for index=#(pending.transients or {}),1,-1 do
        local item=pending.transients[index]
        if not item.cleaned then
            local ok,result,err=pcall(function() return self.app.placement:despawn_transient(item.key) end)
            if not ok or result==false then table.insert(failures,{key=item.key,error=tostring(ok and (err or 'CET entity removal failed') or result)})
            else item.cleaned=true end
        end
    end
    if #failures>0 then return nil,failures end
    return true
end

function Thumbnails:_finish_prefab(pending)
    local cleaned,cleanup_errors=self:_cleanup_prefab(pending)
    if not cleaned then
        pending.cleanup_error=cleanup_errors
        self.last_error='Thumbnail captured, but temporary prefab objects could not all be removed; cleanup will retry.'
        if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
        if self.app.logger then self.app.logger:error('thumbnail:prefab_render','cleanup_retry',{prefab_id=pending.prefab_id,failures=cleanup_errors}) end
        return {pending=true,stage='cleanup',prefab_id=pending.prefab_id,cleanup_errors=cleanup_errors},self.last_error
    end
    local prefab=self.app.model:get_object_prefab(pending.prefab_id)
    if not prefab then self.pending=nil;self.last_error='Prefab was deleted while its thumbnail was rendering';if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end;return nil,self.last_error end
    local final_path=pending.final_path;local backup=final_path..'.bak';local had_original=Util.file_exists(final_path)
    if had_original then
        pcall(os.remove,backup)
        local backed,backup_err=os.rename(final_path,backup)
        if not backed then self.pending=nil;self.last_error='Cannot preserve previous prefab thumbnail: '..tostring(backup_err);if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end;return nil,self.last_error end
    end
    local moved,move_err=os.rename(pending.path,final_path)
    if not moved then
        if had_original and Util.file_exists(backup) then os.rename(backup,final_path) end
        self.pending=nil;self.last_error='Cannot install prefab thumbnail: '..tostring(move_err);if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end;return nil,self.last_error
    end
    prefab.thumbnail_path=final_path;prefab.thumbnail_captured_at=Util.now_iso();prefab.thumbnail_source=pending.backend;prefab.updated_at=Util.now_iso()
    self:invalidate('prefab:'..prefab.id)
    self.app.model:touch();self.app:mark_dirty();self.pending=nil;self.last_error=nil
    self.last_result={prefab_id=prefab.id,path=final_path,backend=pending.backend,object_count=pending.object_count}
    if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
    if self.app.logger then self.app.logger:info('thumbnail:prefab_render','complete',self.last_result) end
    return self.last_result
end

function Thumbnails:render_prefab(prefab_id,options)
    options=options or {}
    if self.pending then return nil,'another thumbnail capture is already running' end
    local prefab=self.app.model:get_object_prefab(prefab_id)
    if not prefab then return nil,'saved object prefab not found' end
    local sources={}
    for _,source in ipairs(prefab.objects or {}) do
        if source.enabled~=false and source.visible~=false then table.insert(sources,source) end
    end
    if #sources==0 then return nil,'prefab has no visible, enabled objects to render' end
    if type(os.execute)~='function' or type(os.rename)~='function' then return nil,'Automatic screenshots are unavailable in this CET sandbox' end

    local hit,hit_err=self.app.game:aim_point(tonumber(options.distance) or 12)
    if not hit or type(hit.position)~='table' then return nil,hit_err or 'could not find a preview point in front of the camera' end
    local camera,camera_err=self.app.game:capture_camera_transform()
    if not camera then return nil,camera_err or 'camera transform is unavailable' end
    local yaw=tonumber(camera.rotation and camera.rotation.yaw) or 0
    local target=hit.position
    local pending={kind='prefab',prefab_id=prefab.id,final_path=prefab_image_path(prefab),spawned={},transients={},
        object_count=#sources,started=os.clock(),deadline=os.clock()+25.0}
    local function abort(message)
        local _,cleanup_errors=self:_cleanup_prefab(pending)
        if #cleanup_errors>0 then
            pending.cleanup_only=true;pending.cleanup_error=cleanup_errors;self.pending=pending
            return nil,tostring(message)..'; temporary preview cleanup is retrying'
        end
        return nil,message
    end
    for index,source in ipairs(sources) do
        local local_p=(source.transform and source.transform.position) or {};local local_r=(source.transform and source.transform.rotation) or {}
        local ox,oy=Util.rotate_xy(tonumber(local_p.x) or 0,tonumber(local_p.y) or 0,yaw)
        local transform={position={x=target.x+ox,y=target.y+oy,z=target.z+(tonumber(local_p.z) or 0),w=1},
            rotation={roll=tonumber(local_r.roll) or 0,pitch=tonumber(local_r.pitch) or 0,yaw=yaw+(tonumber(local_r.yaw) or 0)}}
        if source.metadata and type(source.metadata.world_builder)=='table' then
            if not self.app.runtime_shell then return abort('World Builder runtime is unavailable for prefab rendering') end
            local object=Util.deepcopy(source);object.id=Util.make_id('prefab_preview');object.transform=transform;object.runtime=nil
            local spawned,spawn_err=self.app.runtime_shell:spawn(object)
            if not spawned then return abort('Prefab object '..tostring(source.name)..' failed to spawn: '..tostring(spawn_err)) end
            table.insert(pending.spawned,{object=object})
        else
            if Util.trim(source.template)=='' then return abort('Prefab object '..tostring(source.name)..' has no supported World Builder resource or .ent template') end
            local key='prefab_render_'..tostring(prefab.id)..'_'..tostring(index)
            local spawned,spawn_err=self.app.placement:spawn_transient(key,source.template,source.appearance,transform)
            if not spawned then return abort('Prefab object '..tostring(source.name)..' failed to spawn: '..tostring(spawn_err)) end
            table.insert(pending.transients,{key=key})
        end
    end

    local capture_path=pending.final_path:gsub('%.png$','_capture.png')
    local command,backend=self:_capture_backend(capture_path,1.25)
    if not command then return abort(backend) end
    pcall(os.remove,capture_path);pcall(os.remove,capture_path..'.error')
    pending.path=capture_path;pending.backend=backend
    self.restore_window=self.app.editor_visible~=false;self.app.editor_visible=false;self.restore_at=os.clock()+1.15
    self.pending=pending;self.last_error=nil;self.last_result=nil
    if self.app.logger then self.app.logger:info('thumbnail:prefab_render','started',{prefab_id=prefab.id,name=prefab.name,object_count=#sources,backend=backend}) end
    local ok,result,why,code=pcall(os.execute,command)
    if not ok or result==false or result==nil or (type(result)=='number' and result~=0) then
        self.last_error='Prefab screenshot helper launch failed: '..tostring(result)..' '..tostring(why or code or '')
        local _,cleanup_errors=self:_cleanup_prefab(pending)
        if #cleanup_errors==0 then self.pending=nil else pending.cleanup_only=true;pending.cleanup_error=cleanup_errors end
        if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
        return nil,self.last_error
    end
    return {pending=true,prefab_id=prefab.id,object_count=#sources,backend=backend,path=capture_path},'Prefab preview is temporary; it will be removed when capture completes.'
end

function Thumbnails:update(now)
    now=now or os.clock()
    local pending=self.pending
    if not pending then return nil end
    if pending.kind=='prefab' then
        if pending.cleanup_only then
            local cleaned,cleanup_errors=self:_cleanup_prefab(pending)
            if not cleaned then pending.cleanup_error=cleanup_errors;return {pending=true,stage='cleanup',prefab_id=pending.prefab_id,cleanup_errors=cleanup_errors} end
            self.pending=nil
            return {cleanup=true,prefab_id=pending.prefab_id}
        end
        local helper_error=Util.read_file(pending.path..'.error')
        if helper_error and Util.trim(helper_error)~='' then
            self.last_error='prefab thumbnail capture failed: '..Util.trim(helper_error)
            if self.app.logger then self.app.logger:error('thumbnail:prefab_render','helper_failed',{prefab_id=pending.prefab_id,backend=pending.backend,error=self.last_error}) end
            pcall(os.remove,pending.path..'.error')
            local cleaned,cleanup_errors=self:_cleanup_prefab(pending)
            if cleaned then self.pending=nil else pending.cleanup_only=true;pending.cleanup_error=cleanup_errors end
            if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
            return nil,self.last_error
        end
        if file_size(pending.path)>64 then return self:_finish_prefab(pending) end
        if now>=pending.deadline then
            self.last_error='prefab thumbnail helper produced no image; see DEBUG LOG'
            if self.app.logger then self.app.logger:error('thumbnail:prefab_render','timeout',{prefab_id=pending.prefab_id,backend=pending.backend,path=pending.path}) end
            local cleaned,cleanup_errors=self:_cleanup_prefab(pending)
            if cleaned then self.pending=nil else pending.cleanup_only=true;pending.cleanup_error=cleanup_errors end
            if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
            return nil,self.last_error
        end
        return {pending=true,prefab_id=pending.prefab_id}
    end
    local helper_error=Util.read_file(pending.path..'.error')
    if helper_error and Util.trim(helper_error)~='' then
        self.last_error='thumbnail capture failed: '..Util.trim(helper_error)
        if self.app.logger then self.app.logger:error('thumbnail:capture','helper_failed',{asset_id=pending.asset_id,backend=pending.backend,error=self.last_error}) end
        pcall(os.remove,pending.path..'.error');self.pending=nil
        if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
        self.app.placement:clear_preview()
        return nil,self.last_error
    end
    if file_size(pending.path)>64 then
        local final_path=pending.final_path
        local backup=final_path..'.bak'
        local had_original=Util.file_exists(final_path)
        if had_original then
            pcall(os.remove,backup)
            local moved,move_err=os.rename(final_path,backup)
            if not moved then self.last_error='Cannot preserve previous thumbnail: '..tostring(move_err) end
        end
        local moved,move_err
        if not self.last_error then moved,move_err=os.rename(pending.path,final_path) end
        if not moved then
            if had_original and Util.file_exists(backup) then os.rename(backup,final_path) end
            self.last_error=self.last_error or 'Cannot install captured thumbnail: '..tostring(move_err)
            self.pending=nil
            if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
            self.app.placement:clear_preview();return nil,self.last_error
        end
        local asset=self.app.model:get_asset(pending.asset_id)
        if asset then
            asset.thumbnail_path=final_path;asset.thumbnail_captured_at=Util.now_iso();asset.thumbnail_source=pending.backend;asset.updated_at=Util.now_iso()
            self.app.model:touch();self.app:mark_dirty();self:invalidate(asset.id)
        end
        self.last_result={asset_id=pending.asset_id,path=final_path,backend=pending.backend};self.pending=nil;self.last_error=nil
        if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
        self.app.placement:clear_preview()
        if self.app.logger then self.app.logger:info('thumbnail:capture','complete',self.last_result) end
        return self.last_result
    end
    if now>=pending.deadline then
        self.last_error='thumbnail helper did not produce an image; see DEBUG LOG or place a PNG manually at '..pending.path
        if self.app.logger then self.app.logger:error('thumbnail:capture','timeout',{asset_id=pending.asset_id,backend=pending.backend,path=pending.path}) end
        self.pending=nil
        if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
        self.app.placement:clear_preview()
        return nil,self.last_error
    end
    return {pending=true,asset_id=pending.asset_id}
end

function Thumbnails:status()
    return {pending=self.pending~=nil,request=self.pending,last_result=self.last_result,last_error=self.last_error,backend=self.pending and self.pending.backend or nil}
end

function Thumbnails:shutdown()
    for id in pairs(self.textures) do self:_release_texture(id) end
    if self.restore_window~=nil then self.app.editor_visible=self.restore_window;self.restore_window=nil end
end

return Thumbnails
