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
-- synchronous and needs none. Simulated time has a resource limit (BUDGET) and nothing else: it is not a way to stay
-- clear of errors. Two things are known to fail once the clock passes a few seconds, and both are classified, not
-- avoided (tools/simlab/known_failures.py, docs/simulator-lab.md "Delayed failures"):
--   - the group hello (setup/Group.lua) is sent about 3 s after the sample party appears, and the simulator's
--     SendAddonMessage refuses its bytes. Only a grouped character reaches it, so scenarios that do not need a
--     party call Lab.Solo() and the grouped diagnostic keeps the party on purpose.
--   - Blizzard's own audio-settings ticker calls C_VoiceChat.CanAccessSettings every 5 s, which the simulator
--     deliberately refuses to answer. It happens with no addon loaded.
Lab.simSeconds, Lab.BUDGET = 0, 30
local function Advance(seconds)
    Lab.simSeconds = Lab.simSeconds + seconds
    if Lab.simSeconds > Lab.BUDGET then
        error(("simulated-time limit of %d s exceeded (a resource limit, see lib.lua)"):format(Lab.BUDGET))
    end
    for _ = 1, math.ceil(seconds / 0.05) do A_Admin.AdvanceTime(0.05) end
end
function Lab.Settle(seconds) Advance(seconds or 0.1) end

-- Runs the clock on until `total` simulated seconds have passed since the script began, printing a "tick" marker
-- every `every` seconds so the runner can say when in the window each error appeared. Errors raised by timers do not
-- stop it; they are read from the log afterwards.
function Lab.RunUntil(total, every)
    every = every or 0.5
    local steps = 0
    while Lab.simSeconds < total - 1e-9 do
        local chunk = math.min(every, total - Lab.simSeconds)
        Advance(chunk)
        steps = steps + math.ceil(chunk / 0.05)
        Say("tick", ("t=%.2f"):format(Lab.simSeconds), "steps=" .. steps)
    end
    return steps
end

-- Strict UTF-8 (what Rust's str::from_utf8 accepts): no overlong forms, no surrogates, nothing above U+10FFFF.
-- The sim's Lua has no utf8 library. tools/simlab/scenarios/message_contract.lua checks this against the simulator's
-- own verdict on a table of strings, so it is not taken on trust.
function Lab.Utf8Valid(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        if c < 0x80 then i = i + 1
        else
            local len, min
            if c >= 0xC2 and c <= 0xDF then len, min = 2, 0x80
            elseif c >= 0xE0 and c <= 0xEF then len, min = 3, 0x800
            elseif c >= 0xF0 and c <= 0xF4 then len, min = 4, 0x10000
            else return false, i end
            if i + len - 1 > n then return false, i end
            local cp = c % (len == 2 and 0x20 or len == 3 and 0x10 or 0x08)
            for k = 1, len - 1 do
                local b = s:byte(i + k)
                if b < 0x80 or b > 0xBF then return false, i end
                cp = cp * 64 + (b - 0x80)
            end
            if cp < min or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF) then return false, i end
            i = i + len
        end
    end
    return true
end

-- Bytes as hex, for diagnostics. Only ever given synthetic payloads (a version number and a protocol number).
function Lab.Hex(s, limit)
    limit = limit or 96
    local out = {}
    for i = 1, math.min(#s, limit) do out[i] = ("%02x"):format(s:byte(i)) end
    return table.concat(out) .. (#s > limit and ("..(+" .. (#s - limit) .. " bytes)") or "")
end

-- The character's group, as the game's API and TwichUI's own view of it report it.
function Lab.GroupState()
    local members = 0
    for i = 1, 4 do if UnitExists("party" .. i) then members = members + 1 end end
    local twich = TwichUI and TwichUI.Group and TwichUI.Group.Members and #TwichUI.Group.Members() or "n/a"
    return { inGroup = IsInGroup(), inRaid = IsInRaid(), count = GetNumGroupMembers(), partyUnits = members, twichMembers = twich }
end

-- Leaves the simulator's sample party and says what the state is afterwards (A_Admin.SetPartySize(0), which fires
-- GROUP_ROSTER_UPDATE like a real departure). The simulator is solo while addons load and adds its party after
-- PLAYER_ENTERING_WORLD, so TwichUI has already seen the party arrive: this is "left the party", not "never grouped".
function Lab.Solo()
    A_Admin.SetPartySize(0)
    return Lab.GroupState()
end

-- A pass-through observer on C_ChatInfo.SendAddonMessage: it records each call (argument types, the prefix, chat type,
-- target, byte count, whether the message is valid UTF-8, its hex) and then calls the simulator's own function and
-- returns or raises exactly what that did. It changes no behaviour and swallows nothing. Instrumentation only.
-- ChatThrottleLib reads C_ChatInfo.SendAddonMessage when it sends, so installing this after load is enough.
Lab.sends = {}
function Lab.WatchSends()
    if Lab.watching then return end
    Lab.watching = true
    local original = C_ChatInfo.SendAddonMessage
    C_ChatInfo.SendAddonMessage = function(...)
        local n = select("#", ...)
        local prefix, message, chatType, target = ...
        local entry = {
            argc = n, types = {}, prefix = prefix, chatType = chatType, target = target,
            len = type(message) == "string" and #message or nil,
            message = type(message) == "string" and message or nil,
        }
        for i = 1, n do entry.types[i] = type((select(i, ...))) end
        if entry.message then entry.valid = Lab.Utf8Valid(entry.message) end
        entry.at = Lab.simSeconds
        Lab.sends[#Lab.sends + 1] = entry
        local function Done(ok, ...)
            entry.ok, entry.result = ok, (...)
            if not ok then error((...), 0) end
            return ...
        end
        return Done(pcall(original, ...))
    end
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
