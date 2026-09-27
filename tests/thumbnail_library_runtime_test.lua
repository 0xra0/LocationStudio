local mod=arg[1]
package.path=mod..'/?.lua;'..mod..'/?/init.lua;'..package.path

bit32=bit32 or {}
if not bit32.bxor then
    function bit32.bxor(a,b)
        local r,p=0,1
        a=math.floor(a or 0);b=math.floor(b or 0)
        while a>0 or b>0 do
            local aa=a%2;local bb=b%2
            if aa~=bb then r=r+p end
            a=math.floor(a/2);b=math.floor(b/2);p=p*2
        end
        return r
    end
end

json={};function json.decode(text) return {} end;function json.encode(value) return '{}' end
ImVec2=function(x,y) return {x=x,y=y} end
local loaded_path=nil;local image_size=nil
ImGui={}
function ImGui.LoadTexture(path)
    loaded_path=path
    return {Release=function() end}
end
function ImGui.Image(texture,size) image_size=size end

local Model=require('modules/model')
local Thumbnails=require('modules/thumbnails')
local Browser=require('ui/browser')

local blank=Model.blank();blank.settings.starter_assets_seeded=true
local model=Model.new(blank)
local app={model=model,config={window_open=true}}
function app:mark_dirty() self.dirty=true end
app.selection={revision=0,kind=nil,id=nil}
function app.selection:is(kind,id) return self.kind==kind and self.id==id end
function app.selection:set(kind,id) self.kind=kind;self.id=id;self.revision=self.revision+1;app.selected_asset_id=(kind=='asset') and id or app.selected_asset_id end
app.placement={preview_status=function() return {active=false} end}
app.logger=nil

local a=model:add_asset({id='asset_chair',name='Chair',category='Furniture',kind='prop',template='base\\chair.ent',favorite=true,last_used_at='2026-09-18T12:00:00Z'})
local b=model:add_asset({id='asset_lamp',name='Lamp',category='Lighting',kind='prop',template='base\\lamp.ent',last_used_at='2026-09-18T13:00:00Z'})
local c=model:add_asset({id='asset_table',name='Table',category='Furniture',kind='prop',template='base\\table.ent'})

-- Model helpers drive Favorites + Recent views.
assert(model:set_asset_favorite(c.id,true));assert(model:get_asset(c.id).favorite==true)
model:mark_asset_used(a.id);model:mark_asset_used(a.id);assert(model:get_asset(a.id).use_count>=2)

-- Cached PNG texture path and ImGui image size.
os.execute('mkdir -p '..mod..'/thumbnails')
local oldcwd=nil
local thumb_path=mod..'/thumbnails/'..a.id..'.png'
local f=assert(io.open(thumb_path,'wb'));f:write(string.rep('P',128));f:close()
a.thumbnail_path='thumbnails/'..a.id..'.png'
-- Thumbnails expects paths relative to the mod root, matching CET sandbox behavior.
local cwd_file=assert(io.open(thumb_path,'rb'));cwd_file:close()
local thumb=Thumbnails.new(app)
-- Temporarily point asset path at absolute-like test path because this test executes outside CET sandbox.
a.thumbnail_path='thumbnails/'..a.id..'.png'
assert(thumb:has(a))
local drawn,err=thumb:draw(a,180,100);assert(drawn,err);assert(loaded_path==a.thumbnail_path);assert(image_size.x==180 and image_size.y==100)

-- Grid filters: Favorites, category and Recent ordering.
app.thumbnails=thumb
local browser=Browser.new(app,function() end)
model.data.settings.asset_browser.view='FAVORITES'
local fav=browser:filtered_assets();assert(#fav==2,'expected two favorites')
model.data.settings.asset_browser.view='CATEGORY:Furniture'
local furniture=browser:filtered_assets();assert(#furniture==2,'expected two furniture assets')
model.data.settings.asset_browser.view='RECENT'
local recent=browser:filtered_assets();assert(#recent>=2);assert(recent[1].last_used_at>=recent[2].last_used_at)

os.remove(thumb_path)
print('LocationStudio thumbnail/category library runtime mock: OK')
