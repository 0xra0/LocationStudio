local Logger={}
Logger.__index=Logger

local LEVELS={TRACE=1,DEBUG=2,INFO=3,WARN=4,ERROR=5,FATAL=6}
local unpack_values=table.unpack or unpack
local function pack(...) return {n=select('#',...),...} end

local function timestamp()
    local ok,value=pcall(os.date,'!%Y-%m-%dT%H:%M:%SZ')
    return ok and value or tostring(os.time())
end

local function safe_text(value)
    local ok,result=pcall(tostring,value)
    return ok and result or '<unprintable>'
end

function Logger.new(path,options)
    options=options or {}
    local self=setmetatable({
        path=path or 'logs/locationstudio.log',level=LEVELS[options.level or 'DEBUG'] or LEVELS.DEBUG,
        max_bytes=tonumber(options.max_bytes) or 2097152,max_memory=tonumber(options.max_memory) or 600,
        lines={},last_error=nil,last_scope=nil,session=tostring(os.time())..'-'..tostring(math.floor((os.clock() or 0)*1000)),
        dropped=0,write_failed=nil,throttle={},
    },Logger)
    self:_rotate()
    self:info('logger','session_start',{session=self.session,path=self.path})
    return self
end

function Logger:_rotate()
    local file=io.open(self.path,'r')
    if not file then return end
    local size=file:seek('end') or 0;file:close()
    if size<self.max_bytes then return end
    pcall(os.remove,self.path..'.1')
    pcall(os.rename,self.path,self.path..'.1')
end

function Logger:_fields(fields)
    if type(fields)~='table' then return fields and (' | '..safe_text(fields)) or '' end
    local keys={};for key in pairs(fields) do table.insert(keys,safe_text(key)) end;table.sort(keys)
    local values={}
    for _,key in ipairs(keys) do
        local value=fields[key]
        if type(value)=='table' then
            local nested={};for k,v in pairs(value) do table.insert(nested,safe_text(k)..'='..safe_text(v)) end;table.sort(nested);value='{'..table.concat(nested,',')..'}'
        end
        table.insert(values,key..'='..safe_text(value))
    end
    return #values>0 and (' | '..table.concat(values,' ')) or ''
end

function Logger:write(level,scope,message,fields)
    level=string.upper(level or 'INFO')
    if (LEVELS[level] or LEVELS.INFO)<self.level then return true end
    local line=string.format('%s [%s] [%s] %s%s',timestamp(),level,safe_text(scope or 'app'),safe_text(message or ''),self:_fields(fields))
    table.insert(self.lines,line);if #self.lines>self.max_memory then table.remove(self.lines,1);self.dropped=self.dropped+1 end
    self:_rotate()
    local file,err=io.open(self.path,'a')
    if not file then self.write_failed=safe_text(err);return false,err end
    file:write(line,'\n');file:flush();file:close();self.write_failed=nil
    pcall(print,'[LocationStudio] '..line)
    return true
end

function Logger:trace(scope,message,fields) return self:write('TRACE',scope,message,fields) end
function Logger:debug(scope,message,fields) return self:write('DEBUG',scope,message,fields) end
function Logger:info(scope,message,fields) return self:write('INFO',scope,message,fields) end
function Logger:warn(scope,message,fields) return self:write('WARN',scope,message,fields) end
function Logger:error(scope,message,fields) self.last_error=safe_text(message);self.last_scope=scope;return self:write('ERROR',scope,message,fields) end
function Logger:fatal(scope,message,fields) self.last_error=safe_text(message);self.last_scope=scope;return self:write('FATAL',scope,message,fields) end

function Logger:exception(scope,err)
    local detail=safe_text(err)
    if debug and debug.traceback then detail=debug.traceback(detail,2) end
    self.last_error=detail;self.last_scope=scope
    local now=os.clock() or 0;local signature=safe_text(scope)..'|'..detail
    local previous=self.throttle[signature]
    if previous and now-previous<2 then return false,detail end
    self.throttle[signature]=now;self:write('ERROR',scope,'exception\n'..detail)
    return false,detail
end

function Logger:guard(scope,fn,...)
    local args=pack(...)
    local function call() return fn(unpack_values(args,1,args.n)) end
    local results=pack(xpcall(call,function(err)
        local detail=safe_text(err)
        if debug and debug.traceback then detail=debug.traceback(detail,2) end
        return detail
    end))
    local ok=results[1]
    if not ok then
        local detail=safe_text(results[2]);local now=os.clock() or 0;local signature=safe_text(scope)..'|'..detail;local previous=self.throttle[signature]
        self.last_error=detail;self.last_scope=scope
        if not previous or now-previous>=2 then self.throttle[signature]=now;self:write('ERROR',scope,'exception\n'..detail) end
        return false,results[2]
    end
    return true,unpack_values(results,2,results.n)
end

function Logger:tail(count)
    count=math.max(1,math.min(tonumber(count) or 200,self.max_memory));local out={}
    local first=math.max(1,#self.lines-count+1);for i=first,#self.lines do table.insert(out,self.lines[i]) end
    return out
end

function Logger:read_tail(count)
    local file=io.open(self.path,'r');if not file then return self:tail(count) end
    local values={};for line in file:lines() do table.insert(values,line);if #values>(tonumber(count) or 400) then table.remove(values,1) end end;file:close();return values
end

function Logger:clear()
    local file,err=io.open(self.path,'w');if not file then return false,err end;file:write('');file:flush();file:close();self.lines={};self.last_error=nil;self.last_scope=nil
    self:info('logger','log_cleared',{session=self.session});return true
end

function Logger:status()
    return {path=self.path,session=self.session,last_error=self.last_error,last_scope=self.last_scope,dropped=self.dropped,write_failed=self.write_failed,line_count=#self.lines}
end

return Logger
