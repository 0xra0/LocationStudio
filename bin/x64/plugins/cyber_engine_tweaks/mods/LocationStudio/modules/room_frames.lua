-- Persistent orthonormal local coordinate frames for room/site authoring.
local Util=require('modules/util')
local RoomFrames={}
RoomFrames.__index=RoomFrames

local function finite(v,label)
    v=tonumber(v)
    if not v or v~=v or v==math.huge or v==-math.huge then return nil,(label or 'value')..' must be a finite number' end
    return v
end
local function vec2(v,label)
    if type(v)~='table' then return nil,(label or 'axis')..' must have x and y' end
    local x,err=finite(v.x,(label or 'axis')..'.x');if not x then return nil,err end
    local y;y,err=finite(v.y,(label or 'axis')..'.y');if not y then return nil,err end
    return {x=x,y=y}
end
local function atan2(y,x)
    if math.atan2 then return math.atan2(y,x) end
    if x>0 then return math.atan(y/x) end
    if x<0 and y>=0 then return math.atan(y/x)+math.pi end
    if x<0 and y<0 then return math.atan(y/x)-math.pi end
    if x==0 and y>0 then return math.pi/2 end
    if x==0 and y<0 then return -math.pi/2 end
    return 0
end
local function normalize_frame(value,existing)
    value=value or {};existing=existing or {}
    local name=Util.trim(value.name~=nil and value.name or existing.name or '')
    if name=='' then return nil,'frame name is required' end
    local origin=value.origin or existing.origin or {}
    if type(origin)~='table' then return nil,'origin must have x, y, z' end
    local x,err=finite(origin.x,'origin.x');if not x then return nil,err end
    local y;y,err=finite(origin.y,'origin.y');if not y then return nil,err end
    local z;z,err=finite(origin.z or 0,'origin.z');if not z then return nil,err end
    local u,v
    if value.u_axis or value.v_axis then
        u,err=vec2(value.u_axis or existing.u_axis,'u_axis');if not u then return nil,err end
        v,err=vec2(value.v_axis or existing.v_axis,'v_axis');if not v then return nil,err end
        local ul,vl=math.sqrt(u.x*u.x+u.y*u.y),math.sqrt(v.x*v.x+v.y*v.y)
        local dot=u.x*v.x+u.y*v.y;local det=u.x*v.y-u.y*v.x
        if math.abs(ul-1)>0.001 or math.abs(vl-1)>0.001 then return nil,'u_axis and v_axis must be unit length' end
        if math.abs(dot)>0.001 or math.abs(det-1)>0.001 then return nil,'axes must be perpendicular and right-handed (u cross v = +z)' end
    else
        local yaw; yaw,err=finite(value.yaw~=nil and value.yaw or existing.yaw or 0,'yaw');if not yaw then return nil,err end
        local r=math.rad(yaw);u={x=math.cos(r),y=math.sin(r)};v={x=-math.sin(r),y=math.cos(r)}
    end
    local yaw=math.deg(atan2(u.y,u.x))
    return {id=existing.id or value.id or Util.make_id('frame'),name=name,
        origin={x=x,y=y,z=z},u_axis=u,v_axis=v,yaw=yaw,
        created_at=existing.created_at or Util.now_iso(),updated_at=Util.now_iso(),
        notes=tostring(value.notes~=nil and value.notes or existing.notes or '')}
end
local function row_index(rows,id)
    for i,row in ipairs(rows) do if row.id==id then return i,row end end
end
function RoomFrames.new(app)
    app.model.data.room_frames=type(app.model.data.room_frames)=='table' and app.model.data.room_frames or {}
    local self=setmetatable({app=app},RoomFrames)
    local clean={}
    for _,row in ipairs(app.model.data.room_frames) do
        local ok,frame=pcall(normalize_frame,row,row)
        if ok and frame then clean[#clean+1]=frame end
    end
    app.model.data.room_frames=clean
    return self
end
function RoomFrames:list()
    return {count=#self.app.model.data.room_frames,frames=Util.deepcopy(self.app.model.data.room_frames),
        axes='u and v are unit-length, perpendicular, right-handed XY axes; local z maps to world +Z'}
end
function RoomFrames:get(id)
    local _,row=row_index(self.app.model.data.room_frames,tostring(id or ''))
    if not row then return nil,'room frame not found: '..tostring(id) end
    return Util.deepcopy(row)
end
function RoomFrames:create(args)
    args=args or {};local frame,err=normalize_frame(args);if not frame then return nil,err end
    for _,row in ipairs(self.app.model.data.room_frames) do if string.lower(row.name)==string.lower(frame.name) then return nil,'a room frame with this name already exists' end end
    self.app.model:snapshot('Create room frame');table.insert(self.app.model.data.room_frames,frame);self.app.model:touch();self.app:mark_dirty()
    if self.app.logger then self.app.logger:info('room_frames','created',{id=frame.id,name=frame.name,yaw=frame.yaw}) end
    return Util.deepcopy(frame)
end
function RoomFrames:update(id,patch)
    local index,current=row_index(self.app.model.data.room_frames,tostring(id or ''))
    if not current then return nil,'room frame not found: '..tostring(id) end
    patch=patch or {};local candidate,err=normalize_frame(patch,current);if not candidate then return nil,err end
    for i,row in ipairs(self.app.model.data.room_frames) do if i~=index and string.lower(row.name)==string.lower(candidate.name) then return nil,'a room frame with this name already exists' end end
    self.app.model:snapshot('Update room frame');self.app.model.data.room_frames[index]=candidate;self.app.model:touch();self.app:mark_dirty()
    return Util.deepcopy(candidate)
end
function RoomFrames:delete(id)
    local index,row=row_index(self.app.model.data.room_frames,tostring(id or ''))
    if not row then return nil,'room frame not found: '..tostring(id) end
    self.app.model:snapshot('Delete room frame');table.remove(self.app.model.data.room_frames,index);self.app.model:touch();self.app:mark_dirty()
    return {deleted=true,id=row.id,name=row.name}
end
function RoomFrames:to_world(id,local_value)
    local frame,err=self:get(id);if not frame then return nil,err end
    local_value=local_value or {}
    local p=local_value and (local_value.position or local_value) or {}
    local u;u,err=finite(p.u or p.x,'u');if not u then return nil,err end
    local v;v,err=finite(p.v or p.y,'v');if not v then return nil,err end
    local z;z,err=finite(p.z or 0,'z');if not z then return nil,err end
    local rotation=local_value.rotation or {}
    local yaw; yaw,err=finite(rotation.yaw~=nil and rotation.yaw or local_value.yaw or 0,'yaw');if not yaw then return nil,err end
    local roll;roll,err=finite(rotation.roll or 0,'roll');if not roll then return nil,err end
    local pitch;pitch,err=finite(rotation.pitch or 0,'pitch');if not pitch then return nil,err end
    local o,ua,va=frame.origin,frame.u_axis,frame.v_axis
    return {frame_id=frame.id,frame_name=frame.name,local_position={u=u,v=v,z=z},
        transform={position={x=o.x+u*ua.x+v*va.x,y=o.y+u*ua.y+v*va.y,z=o.z+z,w=1},
            rotation={roll=roll,pitch=pitch,yaw=yaw+frame.yaw}}}
end
function RoomFrames:to_local(id,transform)
    local frame,err=self:get(id);if not frame then return nil,err end
    if type(transform)~='table' or type(transform.position)~='table' then return nil,'transform.position is required' end
    local p=transform.position
    local x;x,err=finite(p.x,'position.x');if not x then return nil,err end
    local y;y,err=finite(p.y,'position.y');if not y then return nil,err end
    local z;z,err=finite(p.z,'position.z');if not z then return nil,err end
    local dx,dy=x-frame.origin.x,y-frame.origin.y;local r=transform.rotation or {}
    return {frame_id=frame.id,frame_name=frame.name,position={u=dx*frame.u_axis.x+dy*frame.u_axis.y,
        v=dx*frame.v_axis.x+dy*frame.v_axis.y,z=z-frame.origin.z},
        rotation={roll=tonumber(r.roll) or 0,pitch=tonumber(r.pitch) or 0,yaw=(tonumber(r.yaw) or 0)-frame.yaw}}
end
return RoomFrames
