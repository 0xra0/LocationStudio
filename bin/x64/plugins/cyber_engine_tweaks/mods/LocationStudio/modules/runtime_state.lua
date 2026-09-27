-- Process-lifetime ownership for development reloads.
-- CET can reload a mod without restarting the game. Keep opaque runtime
-- handles outside the application instance so a new init.lua can reattach
-- to objects that are still alive in the engine.
local State={}

local KEY='__LocationStudioRuntimeState_v1'
-- CET sandboxes each mod without _G; fall back to this chunk's environment (or a module table)
-- so init never fails. State then survives a reload only where that table does.
local ENV=(type(_G)=='table' and _G) or (type(getfenv)=='function' and select(2,pcall(getfenv,1))) or nil
if type(ENV)~='table' then ENV={} end

local function fresh()
    return {
        version=1,
        preserved_at=nil,
        entities={records={},retired={}},
        entity_ids={},
        transient_ids={},
        handles={},
        expected_live={},
    }
end

function State.get()
    local value=rawget(ENV,KEY)
    if type(value)~='table' or value.version~=1 then
        value=fresh();rawset(ENV,KEY,value)
    end
    value.entities=value.entities or {records={},retired={}}
    value.entities.records=value.entities.records or {}
    value.entities.retired=value.entities.retired or {}
    value.entity_ids=value.entity_ids or {}
    value.transient_ids=value.transient_ids or {}
    value.handles=value.handles or {}
    value.expected_live=value.expected_live or {}
    return value
end

function State.preserve()
    local value=State.get();value.preserved_at=os.date('!%Y-%m-%dT%H:%M:%SZ');return value
end

function State.is_preserved()
    return State.get().preserved_at~=nil
end

function State.clear_if_empty()
    local value=State.get()
    if next(value.entities.records)==nil and next(value.entities.retired)==nil and next(value.handles)==nil and next(value.transient_ids)==nil then
        value.preserved_at=nil
    end
end

function State.reset()
    rawset(ENV,KEY,fresh())
end

return State
