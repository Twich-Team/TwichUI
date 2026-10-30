-- Simulator lab fixture (docs/simulator-lab.md): opens one real settings page through TwichUI's one entry point,
-- R:OpenSettings, and says what it found. Run by tools/simlab/smoke.sh with --exec-lua; never packaged or loaded by
-- the game. It reads state and opens the window, the same way /tui does; it builds nothing of its own.
local PAGE = SIMLAB_PAGE or "qol"

-- The simulator's A_Print reaches stdout; plain print goes to the chat frame in the screenshot command.
local Out = rawget(_G, "A_Print") or print
local function Say(...)
    local parts = { "SIMLAB" }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    Out(table.concat(parts, " "))
end

local R = rawget(_G, "TwichUI")
Say("core", R ~= nil)
if not R then return end

local life = R.Life and R.Life.Snapshot() or {}
Say("life", "savedVariables=" .. tostring(life.savedVariables), "configReady=" .. tostring(life.configReady),
    "hooksRun=" .. tostring(life.hooksRun), "hookFailures=" .. tostring(life.hookFailures),
    "loggedIn=" .. tostring(life.loggedIn), "inWorld=" .. tostring(life.inWorld))
for code, count in pairs(life.notes or {}) do Say("note", code, count) end

local ok, why = R:OpenSettings(PAGE)
Say("open", PAGE, ok, why)

local UI = R.SettingsUI
Say("companion", UI ~= nil, "loaded=" .. tostring(C_AddOns.IsAddOnLoaded("TwichUI_Settings")))
if not UI then return end

local win = UI.Frame()
local function Window(label)
    Say(label, win ~= nil, win and win:GetName(), "shown=" .. tostring(win and win:IsShown()),
        "alpha=" .. tostring(win and win:GetAlpha()),
        "size=" .. tostring(win and win:GetWidth()) .. "x" .. tostring(win and win:GetHeight()))
end
Window("window-opening")

-- The window fades in on OnUpdate, and the screenshot command runs only a few ticks after this script. Upstream's
-- manual clock lets that same fade finish, in steps the size of frames (one long step is cut short by the fader).
A_Admin.SetManualClock(GetTime())
for _ = 1, 40 do A_Admin.AdvanceTime(0.05) end
Window("window-settled")

local stats = UI.Stats()
Say("stats", "described=" .. tostring(stats.described), "drawn=" .. tostring(stats.drawn),
    "searchIndex=" .. tostring(stats.searchIndex))
Say("page", (UI.Selected()))
local view = UI.View(PAGE)
local rows = 0
for _ in pairs(view and view.rows or {}) do rows = rows + 1 end
Say("view", view ~= nil, "rows=" .. rows)
