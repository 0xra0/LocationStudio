#!/usr/bin/env python3
"""Load LocationStudio in a small mocked CET/Lua runtime.

This does not validate REDengine behavior. It validates boot ordering, module
loading, event registration, initialization, the complete UI draw control flow,
update, overlay close, shutdown, and logger output.
"""
from __future__ import annotations

import os
import tempfile
from pathlib import Path

try:
    from lupa import LuaRuntime
except ImportError as exc:  # pragma: no cover - optional developer dependency
    raise SystemExit("test_runtime_smoke.py requires lupa") from exc


MOD = Path(__file__).resolve().parents[1]


MOCKS = r'''
events={};hotkeys={}
function registerForEvent(name,fn) events[name]=fn end
function registerHotkey(id,label,fn) hotkeys[id]=fn end
function GetMod(name) return nil end
Game={}
function Game.GetPlayer() return nil end
json={}
function json.decode(text) return {} end
function json.encode(value) return '{}' end
ImGuiCond={FirstUseEver=1}
ImGuiCol={Button=1,ButtonHovered=2,ButtonActive=3,Header=4,HeaderHovered=5,Tab=6,TabHovered=7,Border=8}
ImGui={}
function ImGui.Begin(name,open) return open,true end
function ImGui.End() end
function ImGui.BeginChild(...) return true end
function ImGui.EndChild() end
function ImGui.BeginTabBar(...) return true end
function ImGui.EndTabBar() end
function ImGui.BeginTabItem(...) return true end
function ImGui.EndTabItem() end
function ImGui.BeginPopup(...) return false end
function ImGui.BeginCombo(...) return false end
function ImGui.EndCombo() end
function ImGui.EndPopup() end
function ImGui.OpenPopup(...) end
function ImGui.CloseCurrentPopup() end
function ImGui.Text(...) end
function ImGui.TextDisabled(...) end
function ImGui.TextWrapped(...) end
function ImGui.TextColored(...) end
function ImGui.Separator() end
function ImGui.SameLine(...) end
function ImGui.Spacing() end
function ImGui.NewLine() end
function ImGui.BulletText(...) end
function ImGui.SetTooltip(...) end
function ImGui.SetNextWindowSize(...) end
function ImGui.PushStyleColor(...) end
function ImGui.PopStyleColor(...) end
function ImGui.PushItemWidth(...) end
function ImGui.PopItemWidth(...) end
function ImGui.Button(...) return false end
function ImGui.SmallButton(...) return false end
function ImGui.Selectable(...) return false end
function ImGui.InvisibleButton(...) return false end
function ImGui.IsItemHovered() return false end
function ImGui.IsItemClicked(...) return false end
function ImGui.InputText(label,value,...) return value,false end
function ImGui.InputTextWithHint(label,hint,value,...) return value,false end
function ImGui.InputTextMultiline(label,value,...) return value,false end
function ImGui.InputFloat(label,value,...) return value,false end
function ImGui.InputInt(label,value,...) return value,false end
function ImGui.InputFloat3(label,value,...) return value,false end
function ImGui.Checkbox(label,value) return value,false end
function ImGui.SliderFloat(label,value,...) return value,false end
function ImGui.GetContentRegionAvail() return 1200,700 end
function ImGui.GetCursorScreenPos() return 0,0 end
function ImGui.GetMousePos() return 0,0 end
-- Regression guard: v0.4.1 crashed because viewport.lua treated this CET
-- userdata API like a Lua object. The repaired UI must never call it.
function ImGui.GetWindowDrawList() error('raw draw list must not be used') end
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="locationstudio-smoke-") as temp:
        root = Path(temp)
        for name in ("logs", "data", "bridge", "exports"):
            (root / name).mkdir()
        old = Path.cwd()
        os.chdir(root)
        try:
            lua = LuaRuntime(unpack_returned_tuples=True)
            lua.execute(f"package.path={str(MOD / '?.lua')!r}..';'..{str(MOD / '?/init.lua')!r}..';'..package.path")
            lua.execute(MOCKS)
            lua.execute(f"dofile({str(MOD / 'init.lua')!r})")
            for event in ("onInit", "onOverlayOpen", "onDraw", "onUpdate"):
                callback = lua.globals().events[event]
                assert callback is not None, f"missing event: {event}"
                callback(0.016) if event == "onUpdate" else callback()
            # Force one full-editor draw failure. onDraw must log it, disable the
            # full editor, and render the minimal fallback without propagating.
            lua.execute("saved_GetContentRegionAvail=ImGui.GetContentRegionAvail; ImGui.GetContentRegionAvail=function() error('forced ui failure') end")
            lua.globals().events["onDraw"]()
            lua.execute("ImGui.GetContentRegionAvail=saved_GetContentRegionAvail")
            lua.globals().events["onDraw"]()
            lua.globals().events["onOverlayClose"]()
            lua.globals().events["onShutdown"]()
            log = (root / "logs" / "locationstudio.log")
            assert log.is_file(), "logger did not create its output"
            text = log.read_text(encoding="utf-8")
            assert "core_ready" in text, text
            assert "shutdown" in text, text
            assert "forced ui failure" in text, text
            assert "full_editor_disabled_after_error" in text, text
            assert "[ERROR] [ui:fallback]" not in text, text
            print("LocationStudio mocked CET runtime smoke test: OK")
        finally:
            os.chdir(old)


if __name__ == "__main__":
    main()
