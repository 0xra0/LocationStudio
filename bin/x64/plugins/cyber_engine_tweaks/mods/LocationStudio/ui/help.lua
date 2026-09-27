local Theme=require('ui/theme')

local Help={}
Help.__index=Help

function Help.new(app,notify)
    return setmetatable({app=app,notify=notify,last_validation=nil},Help)
end

function Help:toast(message) if self.notify then self.notify(message) end end

function Help:run_plan(plan,label)
    local result,err=self.app.authoring_plans:execute(plan,{save=false})
    if result then self:toast(label..' created. One Undo removes the entire plan.') else self:toast(tostring(err)) end
end

function Help:draw_readiness()
    local app=self.app;local placement=app.placement:status();local shell=app.runtime_shell:status(false)
    Theme.kicker('LIVE READINESS')
    Theme.pill(app.game:is_ready() and '1  GAME READY' or '1  GAME OFFLINE',app.game:is_ready() and 'good' or 'bad');ImGui.SameLine()
    Theme.pill(placement.supported and '2  ENTITY SPAWNER READY' or '2  ENTITY SPAWNER OFF',placement.supported and 'good' or 'bad');ImGui.SameLine()
    Theme.pill(shell.available and '3  ROOM ASSETS READY' or '3  ROOM BACKEND OFF',shell.available and 'good' or 'bad')
    if not shell.available then ImGui.TextWrapped('Rooms require a supported World Builder runtime. '..tostring(shell.reason or '')) end
    Theme.muted('LocationStudio checks the actual game adapters before mutating a multi-step plan. Direct .ent assets use CET; room/static-mesh pieces use World Builder.')
    if Theme.action_button('SPAWN TEST CHAIR',158,30) then local result,err=app.placement:spawn_test_asset('builtin_chair_poor');self:toast(result and 'Spawn requested; watch the entity status in the header.' or err) end
    ImGui.SameLine();if Theme.action_button('REMOVE TEST CHAIR',170,30) then local result,err=app.placement:clear_test_asset();self:toast(result and 'Test chair removed.' or err) end
    ImGui.Separator()
end

function Help:draw_plan_recovery()
    local status=self.app.authoring_plans:status();if not status.recovery_required then return end
    Theme.bad('AUTHORING PLAN RECOVERY REQUIRED')
    ImGui.TextWrapped('A plan failed and at least one live object could not be removed. Saving, exporting, history, and new plans are paused so the partial result cannot be silently committed.')
    if Theme.primary_button('RETRY SAFE ROLLBACK',190,32) then local result,err=self.app.authoring_plans:retry_rollback();self:toast(result and 'Rollback completed; the project was restored.' or err) end
    ImGui.SameLine();if Theme.danger_button('KEEP PARTIAL RESULT',190,32) then local result,err=self.app.authoring_plans:keep_partial();self:toast(result and 'Partial result kept as one undoable change.' or err) end
    ImGui.Separator()
end

function Help:draw()
    local app=self.app;local examples=app.authoring_plans:examples()
    Theme.section('FIRST-TIME HELP','a short path from empty project to editable game assets')
    self:draw_plan_recovery();self:draw_readiness()

    Theme.kicker('START HERE')
    ImGui.BulletText('Stand where the new location origin should be and open CET.')
    ImGui.BulletText('Run the spawn test. If the chair does not appear, create a debug report before building.')
    ImGui.BulletText('Build a starter workspace or open ASSETS, preview a game asset, then place it.')
    ImGui.BulletText('Open SCENE, select one or more objects, and use Grab Move / Transform Edit.')
    ImGui.BulletText('Save the project. Your data/project.json and config.json remain untouched by upgrades.')
    ImGui.Spacing()
    if Theme.primary_button('BUILD STARTER WORKSPACE',226,36) then self:run_plan(examples.starter_workspace,'Starter workspace') end
    ImGui.SameLine();if Theme.action_button('BUILD FURNISHED ROOM',210,36) then self:run_plan(examples.furnished_room,'Furnished room') end
    ImGui.SameLine();if Theme.action_button('BUILD GAMEPLAY ROUTE',205,36) then self:run_plan(examples.gameplay_route,'Gameplay route') end
    if Theme.action_button('BUILD CAPTURED SCENE',210,36) then self:run_plan(examples.captured_scene,'Captured scene') end
    Theme.muted('Each button calls the same validated authoring-plan engine exposed to MCP. A successful plan is exactly one undo step.')
    ImGui.Separator()

    Theme.kicker('USER JSON PLAN')
    ImGui.TextWrapped('Copy an example to data/authoring-plan.json, edit it, validate it, then run it. Aliases such as $room connect later steps to objects created earlier in the same plan.')
    if Theme.action_button('VALIDATE PLAN FILE',170,30) then
        local plan,err=app.authoring_plans:load_file('data/authoring-plan.json')
        self.last_validation=plan and app.authoring_plans:validate(plan) or {valid=false,errors={err}}
        self:toast(self.last_validation.valid and ('Valid plan: '..tostring(self.last_validation.step_count)..' steps') or table.concat(self.last_validation.errors or {},'; '))
    end
    ImGui.SameLine();if Theme.primary_button('RUN PLAN FILE',150,30) then local result,err=app.authoring_plans:execute_file('data/authoring-plan.json',{save=false});self:toast(result and ('Built '..tostring(result.step_count)..' steps; save when satisfied.') or err) end
    if self.last_validation then
        if self.last_validation.valid then Theme.good('VALID / '..tostring(self.last_validation.step_count)..' STEPS')
        else for _,err in ipairs(self.last_validation.errors or {}) do ImGui.BulletText(tostring(err)) end end
    end
    Theme.muted('Files: FIRST-RUN.md / AUTHORING-PLANS.md / MCP-EXAMPLES.md / TROUBLESHOOTING.md / examples/*.json')
    ImGui.Separator()

    Theme.kicker('SUPPORT')
    ImGui.TextWrapped('If anything fails, do not guess. Save a support report, then send the versioned text file. It contains capabilities, adapter status, plan recovery state, module state, and the recent structured log; it does not include your project JSON.')
    if Theme.action_button('RUN DIAGNOSTICS',160,30) then local report=app.diagnostics and app.diagnostics:run();self:toast(report and 'Diagnostics refreshed.' or 'Diagnostics unavailable.') end
    ImGui.SameLine();if Theme.primary_button('SAVE DEBUG REPORT',180,30) then local path,err=app.diagnostics and app.diagnostics:write_support_report();self:toast(path and ('Send this file: '..path) or err) end
    Theme.muted('Log: logs/locationstudio.log  |  Diagnostics: logs/locationstudio-diagnostics.json')
end

return Help
