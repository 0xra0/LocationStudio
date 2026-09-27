local Util = {}

function Util.deepcopy(value, seen)
    if type(value) ~= 'table' then return value end
    if seen and seen[value] then return seen[value] end
    local s = seen or {}
    local out = {}
    s[value] = out
    for k, v in pairs(value) do
        out[Util.deepcopy(k, s)] = Util.deepcopy(v, s)
    end
    return out
end

function Util.trim(s)
    if s == nil then return '' end
    return tostring(s):match('^%s*(.-)%s*$')
end

function Util.split_csv(s)
    local out = {}
    s = Util.trim(s)
    if s == '' then return out end
    for part in string.gmatch(s, '([^,]+)') do
        local v = Util.trim(part)
        if v ~= '' then table.insert(out, v) end
    end
    return out
end

function Util.join_csv(t)
    if type(t) ~= 'table' then return '' end
    return table.concat(t, ', ')
end

function Util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Util.round(v, precision)
    local p = 10 ^ (precision or 3)
    return math.floor(v * p + 0.5) / p
end

function Util.now_iso()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local id_sequence=0
function Util.make_id(prefix)
    -- Lua 5.1/LuaJIT need not expose Lua 5.2's bit32. The counter also avoids
    -- floating-point FNV multiplication collisions during rapid shell creation.
    id_sequence=id_sequence+1
    return string.format('%s_%x_%x_%06x',prefix or 'id',os.time(),id_sequence,math.random(0,16777215))
end

function Util.contains_ci(haystack, needle)
    if needle == nil or needle == '' then return true end
    haystack = string.lower(tostring(haystack or ''))
    needle = string.lower(tostring(needle))
    return string.find(haystack, needle, 1, true) ~= nil
end

function Util.table_index_by_id(items, id)
    if type(items) ~= 'table' then return nil end
    for i, item in ipairs(items) do
        if item.id == id then return i end
    end
    return nil
end

function Util.file_exists(path)
    local f = io.open(path, 'r')
    if f then f:close() return true end
    return false
end

function Util.read_file(path)
    local f, err = io.open(path, 'r')
    if not f then return nil, err end
    local text = f:read('*a')
    f:close()
    return text
end

function Util.write_file(path, text)
    local f, err = io.open(path, 'w')
    if not f then return false, err end
    local ok,write_err=f:write(text or '')
    local flushed,flush_err=f:flush()
    local closed,close_err=f:close()
    if not ok or not flushed or not closed then return false,write_err or flush_err or close_err or 'file write failed' end
    return true
end

function Util.json_read(path, fallback)
    local text = Util.read_file(path)
    if not text or text == '' then return Util.deepcopy(fallback) end
    local ok, data = pcall(json.decode, text)
    if not ok or type(data) ~= 'table' then
        return Util.deepcopy(fallback)
    end
    return data
end

function Util.json_write(path, data)
    local ok, encoded = pcall(json.encode, data)
    if not ok then return false, encoded end
    return Util.write_file(path, encoded)
end

function Util.distance3(a, b)
    local dx = (a.x or 0) - (b.x or 0)
    local dy = (a.y or 0) - (b.y or 0)
    local dz = (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Util.snap(value, step)
    step=math.abs(tonumber(step) or 0)
    if step==0 then return tonumber(value) or 0 end
    return math.floor(((tonumber(value) or 0)/step)+0.5)*step
end

function Util.snap_transform(transform, grid, angle)
    local out=Util.deepcopy(transform or {})
    out.position=out.position or {}; out.rotation=out.rotation or {}
    out.position.x=Util.snap(out.position.x,grid);out.position.y=Util.snap(out.position.y,grid);out.position.z=Util.snap(out.position.z,grid);out.position.w=out.position.w or 1
    out.rotation.roll=Util.snap(out.rotation.roll,angle);out.rotation.pitch=Util.snap(out.rotation.pitch,angle);out.rotation.yaw=Util.snap(out.rotation.yaw,angle)
    return out
end

function Util.look_at_rotation(from,to)
    local dx=(to.x or 0)-(from.x or 0);local dy=(to.y or 0)-(from.y or 0);local dz=(to.z or 0)-(from.z or 0)
    local horizontal=math.sqrt(dx*dx+dy*dy)
    return {roll=0,pitch=-math.deg(math.atan2(dz,horizontal)),yaw=math.deg(math.atan2(dy,dx))}
end

function Util.rotate_xy(dx,dy,yaw)
    local r=(tonumber(yaw) or 0)*math.pi/180;local c,s=math.cos(r),math.sin(r)
    return dx*c-dy*s,dx*s+dy*c
end

return Util
