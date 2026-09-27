local Widgets={}

-- Scalar fields avoid table/vector overload assumptions across CET ImGui builds.
-- All existing callers still receive {x,y,z}, changed (array-style values).
function Widgets.input3(label,values,format)
    local result={};local changed=false
    local axes={'X','Y','Z'}
    ImGui.Text((label:gsub('##.*$','')))
    for i=1,3 do
        local old=tonumber(values[i]) or 0
        local value=ImGui.InputFloat(axes[i]..'##'..label..'_'..i,old,0,0,format or '%.3f')
        if type(value)~='number' or value~=value or math.abs(value)==math.huge then value=old end
        result[i]=value;changed=changed or value~=old
    end
    return result,changed
end

return Widgets
