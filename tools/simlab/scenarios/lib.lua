-- Simulator lab helpers (docs/simulator-lab.md) for scenarios that use a real settings page. interact.sh puts this
-- file in front of the scenario and runs both with --exec-lua; the game never loads it. It builds no control of its
-- own: it finds the rows TwichUI_Settings drew (UI.View(page).rows[id], ids from the page's settings) and drives
-- them the way the game's own API lets a script drive a widget.
--
-- What "interaction" means here (the simulator has no input injection in headless mode):
--   click   Button:Click(), which runs the button's OnClick script. No pointer, no hit test, no focus.
--   drag    Slider:SetValue(), which runs OnValueChanged. No pointer.
--   type    EditBox:SetText() then the box's own OnEnterPressed script. No keyboard, no focus.
-- These are handler-level. They show a control's handler does what it says; not that a player can reach the control.
--
-- Output: "SIMLAB ..." lines (A_Print reaches stderr), read by interact_verdict.py. SIMLAB_PARAMS is set by the runner.
local P = rawget(_G, "SIMLAB_PARAMS") or {}
local Out = rawget(_G, "A_Print") or print
local Lab = { passed = 0, failed = 0, steps = 0 }

local function Say(...)
    local parts = { "SIMLAB" }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    Out(table.concat(parts, " "))
end
Lab.Say = Say

-- layer: init | construct | interact | state. What the check proves is named by the layer, so a pass is never
-- read as more than it is. P.wrongAt names one check whose expectation is deliberately made wrong (the runner's
-- negative control: the scenario must then fail, on that check and no other).
function Lab.Check(layer, name, expected, actual)
    if P.wrongAt == name then expected = tostring(expected) .. " (deliberately wrong)" end
    local ok = expected == actual
    if ok then Lab.passed = Lab.passed + 1 else Lab.failed = Lab.failed + 1 end
    Say("check", ok and "PASS" or "FAIL", "[" .. layer .. "]", name, "|", "expected=" .. tostring(expected), "|",
        "actual=" .. tostring(actual))
    return ok
end

-- The simulator's manual clock lets the window's fades finish, in frame-sized steps. A control's change itself is
-- synchronous and needs none. Time is budgeted: the simulator's sample character is in a party, so TwichUI sets its
-- own 3 second "hello" timer at startup, and when the clock passes it the hello goes out through the simulator's
-- addon-message path and fails ("string at argument 2 is not valid UTF-8" in Blizzard_ScriptErrors, cause unverified).
-- Other Blizzard timers then fail on API the simulator does not supply (C_VoiceChat.CanAccessSettings). Those are
-- gaps in the lab, not in the page; the budget keeps the scenario clear of them, and exceeding it fails the scenario.
Lab.simSeconds, Lab.BUDGET = 0, 2.5
function Lab.Settle(seconds)
    seconds = seconds or 0.1
    Lab.simSeconds = Lab.simSeconds + seconds
    if Lab.simSeconds > Lab.BUDGET then
        error(("simulated-time budget of %.1f s exceeded (see lib.lua): the lab's own timers would start to fail"):format(Lab.BUDGET))
    end
    for _ = 1, math.ceil(seconds / 0.05) do A_Admin.AdvanceTime(0.05) end
end

-- Runs fn(); a Lua error is a failed check and ends the scenario (later steps would be judged on a broken state).
function Lab.Step(name, fn)
    if Lab.aborted or Lab.stopped then return end
    Lab.steps = Lab.steps + 1
    Say("step", name)
    local ok, err = xpcall(fn, function(e) return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "") end)
    if not ok then
        Lab.failed = Lab.failed + 1
        Lab.aborted = true
        Say("check", "FAIL", "[error]", name, "|", "expected=no Lua error", "|", "actual=" .. tostring(err):gsub("\n.*", ""))
        Out("Lua error: " .. tostring(err))
        return
    end
    Lab.Settle(0.1)
    if P.stopAfter == name then
        Lab.stopped = true
        Say("stopped-after", name)
    end
end

-- The settings window's shared drop-down list (Widgets.lua names its frame).
local function Menu() return rawget(_G, "TwichUISettingsMenu") end

function Lab.Open(page)
    local R = TwichUI
    local ok, why = R:OpenSettings(page)
    Lab.Settle(0.6)   -- the window fades in
    return ok, why, R.SettingsUI.View(page)
end

-- Scrolls the open page to a row with the window's own Navigate (what a search result or a link does), so a
-- screenshot taken afterwards shows it. Changes nothing but the scroll position and a brief highlight.
function Lab.Reveal(page, id) TwichUI.SettingsUI.Navigate(page, id) end

-- The drawn row for a setting id: { row, frame, control }. Errors, rather than returning nil, so a renamed id
-- fails the scenario where it happens.
function Lab.Row(page, id)
    local view = TwichUI.SettingsUI.View(page)
    local v = view and view.rows[id]
    if not v then error(("no drawn row %q on page %q"):format(id, page)) end
    return v
end

function Lab.RowShown(v) return v.frame:IsShown() end

-- A checkbox row: click the checkbox itself.
function Lab.ClickCheckbox(v) v.control:Click() end

-- A slider row, as a drag ends: the slider's value is set and its OnValueChanged runs.
function Lab.SetSlider(v, value) v.control.slider:SetValue(value) end

-- A slider row's number box: text, then Enter (OnEnterPressed clamps to the slider's range).
function Lab.TypeInBox(v, text)
    local box = v.control.box
    box:SetText(text)
    local script = box:GetScript("OnEnterPressed")
    if not script then error("the number box has no OnEnterPressed script") end
    script(box)
end

-- A drop-down row: click it, check the list opened for it, click the entry whose value is `value`.
-- Returns whether the list opened and the entry was found (the checks that matter are on the resulting state).
function Lab.PickChoice(v, value)
    v.control:Click()
    local menu = Menu()
    if not (menu and menu:IsShown() and menu.owner == v.control) then return false, "list did not open for this control" end
    for _, entry in ipairs(menu.rows) do
        if entry:IsShown() and entry.choice and entry.choice.value == value then
            entry:Click()
            return true
        end
    end
    return false, "no entry with value " .. tostring(value)
end

function Lab.MenuShown() local m = Menu(); return m ~= nil and m:IsShown() end

-- A plain, sorted text of one saved table, for comparing two runs of the same scenario.
function Lab.Digest(t)
    if type(t) ~= "table" then return tostring(t) end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(t[k]) end
    return table.concat(parts, ",")
end

function Lab.Finish()
    Say("done", "steps=" .. Lab.steps, "simSeconds=" .. Lab.simSeconds, "passed=" .. Lab.passed, "failed=" .. Lab.failed,
        "aborted=" .. tostring(Lab.aborted == true), "stopped=" .. tostring(Lab.stopped == true))
end
