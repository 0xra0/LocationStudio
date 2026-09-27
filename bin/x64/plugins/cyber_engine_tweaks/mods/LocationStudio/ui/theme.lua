local Theme={}

-- Night-City-inspired editor palette: near-black panels, warm signal yellow,
-- electric cyan for runtime state, and magenta only for destructive/error state.
Theme.colors={
    bg={0.018,0.024,0.030,1}, panel={0.030,0.040,0.050,1}, panel_alt={0.040,0.055,0.065,1},
    yellow={0.95,0.82,0.16,1}, cyan={0.05,0.78,0.92,1}, green={0.22,0.84,0.52,1},
    magenta={0.95,0.18,0.38,1}, amber={0.98,0.61,0.12,1}, muted={0.48,0.56,0.60,1},
}

local function push_color(slot,c)
    if slot==nil or type(ImGui.PushStyleColor)~='function' then return 0 end
    ImGui.PushStyleColor(slot,c[1],c[2],c[3],c[4]);return 1
end

local function push_var(slot,...)
    if not ImGuiStyleVar or slot==nil or type(ImGui.PushStyleVar)~='function' then return 0 end
    ImGui.PushStyleVar(slot,...);return 1
end

function Theme.push()
    local c,v=0,0
    c=c+push_color(ImGuiCol and ImGuiCol.WindowBg,Theme.colors.bg)
    c=c+push_color(ImGuiCol and ImGuiCol.ChildBg,Theme.colors.panel)
    c=c+push_color(ImGuiCol and ImGuiCol.PopupBg,Theme.colors.panel_alt)
    c=c+push_color(ImGuiCol and ImGuiCol.Button,{0.055,0.075,0.085,1})
    c=c+push_color(ImGuiCol and ImGuiCol.ButtonHovered,{0.10,0.22,0.25,1})
    c=c+push_color(ImGuiCol and ImGuiCol.ButtonActive,{0.12,0.36,0.40,1})
    c=c+push_color(ImGuiCol and ImGuiCol.Header,{0.06,0.14,0.16,0.95})
    c=c+push_color(ImGuiCol and ImGuiCol.HeaderHovered,{0.10,0.26,0.30,0.98})
    c=c+push_color(ImGuiCol and ImGuiCol.Tab,{0.04,0.07,0.08,1})
    c=c+push_color(ImGuiCol and ImGuiCol.TabHovered,{0.08,0.24,0.28,1})
    c=c+push_color(ImGuiCol and ImGuiCol.Border,{0.13,0.28,0.31,0.82})
    c=c+push_color(ImGuiCol and ImGuiCol.Separator,{0.12,0.30,0.33,0.70})
    c=c+push_color(ImGuiCol and ImGuiCol.FrameBg,{0.035,0.060,0.070,1})
    c=c+push_color(ImGuiCol and ImGuiCol.FrameBgHovered,{0.06,0.13,0.15,1})
    c=c+push_color(ImGuiCol and ImGuiCol.CheckMark,Theme.colors.yellow)
    v=v+push_var(ImGuiStyleVar and ImGuiStyleVar.WindowRounding,8)
    v=v+push_var(ImGuiStyleVar and ImGuiStyleVar.ChildRounding,7)
    v=v+push_var(ImGuiStyleVar and ImGuiStyleVar.FrameRounding,5)
    v=v+push_var(ImGuiStyleVar and ImGuiStyleVar.PopupRounding,6)
    return c,v
end

function Theme.pop(colors,vars)
    if (vars or 0)>0 and type(ImGui.PopStyleVar)=='function' then ImGui.PopStyleVar(vars) end
    if (colors or 0)>0 and type(ImGui.PopStyleColor)=='function' then ImGui.PopStyleColor(colors) end
end

local function colored(c,text)
    if type(ImGui.TextColored)=='function' then ImGui.TextColored(c[1],c[2],c[3],c[4],tostring(text or '')) else ImGui.Text(tostring(text or '')) end
end

function Theme.accent(text) colored(Theme.colors.yellow,text) end
function Theme.info(text) colored(Theme.colors.cyan,text) end
function Theme.warning(text) colored(Theme.colors.amber,text) end
function Theme.good(text) colored(Theme.colors.green,text) end
function Theme.bad(text) colored(Theme.colors.magenta,text) end
function Theme.muted(text) if type(ImGui.TextDisabled)=='function' then ImGui.TextDisabled(text) else ImGui.Text(text) end end

function Theme.section(title,subtitle)
    Theme.accent(string.upper(title));if subtitle and subtitle~='' then ImGui.SameLine();Theme.muted(subtitle) end
    ImGui.Separator()
end

function Theme.kicker(text) Theme.info(string.upper(text)) end
function Theme.status(label,ok)
    if ok then Theme.good(label) else Theme.bad(label) end
end

local function styled_button(label,w,h,base,hover,active)
    local n=0
    n=n+push_color(ImGuiCol and ImGuiCol.Button,base)
    n=n+push_color(ImGuiCol and ImGuiCol.ButtonHovered,hover)
    n=n+push_color(ImGuiCol and ImGuiCol.ButtonActive,active)
    local clicked=ImGui.Button(label,w or 0,h or 0)
    if n>0 then ImGui.PopStyleColor(n) end
    return clicked
end

function Theme.primary_button(label,w,h)
    return styled_button(label,w,h,{0.62,0.51,0.04,1},{0.86,0.70,0.05,1},{0.98,0.82,0.10,1})
end

function Theme.action_button(label,w,h)
    return styled_button(label,w,h,{0.04,0.28,0.33,1},{0.05,0.46,0.53,1},{0.06,0.62,0.70,1})
end

function Theme.danger_button(label,w,h)
    return styled_button(label,w,h,{0.32,0.05,0.10,1},{0.55,0.06,0.16,1},{0.74,0.08,0.20,1})
end

function Theme.nav_button(label,selected,w,h)
    if selected then return styled_button(label,w,h,{0.45,0.38,0.04,1},{0.68,0.56,0.05,1},{0.82,0.68,0.06,1}) end
    return styled_button(label,w,h,{0.035,0.055,0.065,1},{0.07,0.18,0.21,1},{0.08,0.28,0.31,1})
end

function Theme.pill(text,kind)
    if kind=='good' then Theme.good(text) elseif kind=='bad' then Theme.bad(text) elseif kind=='warn' then Theme.warning(text) else Theme.info(text) end
end

return Theme
