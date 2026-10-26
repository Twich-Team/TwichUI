-- TwichUI: opening TwichUI Diagnostics, and its one start-up hand-off
-- TwichUI Diagnostics (profiling, inspecting a capture, exporting a report) is an addon of its own,
-- TwichUI_Diagnostics, loaded the first time it is asked for (load on demand). Nothing of it is loaded, built or
-- run in ordinary play, and nothing here runs unless asked: no events, no timers. docs/diagnostics.md has the whole.
--
--   L.Load()          loads it if needed: true, or false and a reason code (never in combat)
--   L.Open(tab)       loads it and shows its window ("overview", "timeline", ... ; nil: where it was)
--   L.Command(arg)    /tui perf [start [preset] [minutes]|stop|cancel|mark [note]|status|arm [preset]|disarm]
--   L.ArmedBoot()     Core.lua calls it as TwichUI's saved data arrives. Only when "Arm next reload" was chosen
--                     (TwichUIDB.diagnosticsArm, a one-shot hand-off cleared as it is read), it loads TwichUI_Diagnostics
--                     there and then so that start-up can be recorded. Otherwise it reads one field and returns.
--   L.Snapshot()      read only: loaded, recording, armed

local R = TwichUI
local L = { attempts = 0 }
R.DiagnosticsLauncher = L
L.ADDON = "TwichUI_Diagnostics"
L.ARM_FOR = 1800   -- seconds an arming is good for: a reload much later than that does not start a capture

local function Say(fmt, ...) R.Print("diagnostics: " .. fmt, ...) end

local WHY = {
    MISSING = "its folder, TwichUI_Diagnostics, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Diagnostics is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Diagnostics needs TwichUI turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Diagnostics can't find TwichUI.",
    INTERFACE_VERSION = "TwichUI Diagnostics is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Diagnostics' files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Diagnostics loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "TwichUI Diagnostics ran into an error while loading. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
    COMBAT = "not during combat. Try again when combat ends.",
}

function L.Explain(code)
    return "couldn't open TwichUI Diagnostics: " .. (WHY[code] or ("the game says " .. tostring(code) .. "."))
end

function L.Loaded() return R.Diagnostics ~= nil end

-- Loads TwichUI_Diagnostics if it isn't loaded. Returns true, or false and a reason code.
-- anyTime: also in combat (only the armed start-up uses it, before there can be any combat).
function L.Load(anyTime)
    if R.Diagnostics then return true end
    if not anyTime and InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    L.attempts = L.attempts + 1
    local ok, loaded, reason = pcall(C_AddOns.LoadAddOn, L.ADDON)
    if not ok then
        R.Fault("diagnostics", loaded)
        return false, "ERROR"
    end
    if not loaded then return false, reason or "UNKNOWN" end
    if not R.Diagnostics then return false, "INCOMPLETE" end
    return true
end

-- Loads it (saying why in chat when it can't) and hands back R.Diagnostics, or nil.
local function Ready()
    local ok, why = L.Load()
    if ok then return R.Diagnostics end
    L.failed = why
    Say("%s", L.Explain(why))
    return nil
end

function L.Open(tab)
    local DX = Ready()
    if not DX then return false end
    local ok, err = pcall(DX.Open, tab)
    if not ok then
        R.Fault("diagnostics window", err)
        Say("%s", L.Explain("ERROR"))
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Arm next reload: a one-shot hand-off between loads, in TwichUIDB (not part of a profile or a backup)
---------------------------------------------------------------------------
function L.Armed()
    local arm = type(TwichUIDB) == "table" and TwichUIDB.diagnosticsArm
    return type(arm) == "table" and arm or nil
end

-- preset: a preset key (TwichUI_Diagnostics checks it when the capture starts). Nothing reloads here.
function L.Arm(preset, seconds)
    if type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.diagnosticsArm = { preset = type(preset) == "string" and preset:sub(1, 24) or "startup",
        seconds = type(seconds) == "number" and seconds or nil, at = time and time() or 0 }
    return true
end

function L.Disarm()
    if type(TwichUIDB) == "table" then TwichUIDB.diagnosticsArm = nil end
end

-- What happened to an armed start-up that did not start, in chat once the world is there (chat is not ready at
-- ADDON_LOADED). Listened for only after such a start-up, and only once.
local function Tell()
    R:Off("PLAYER_ENTERING_WORLD", Tell)
    local boot = L.boot
    if not boot then return end
    if boot.state == "expired" then
        Say("the start-up capture armed more than %d minutes ago was not started (arm it again just before you reload).", L.ARM_FOR / 60)
    elseif boot.state == "failed" then
        Say("the armed start-up capture could not start: %s", L.Explain(boot.why or "ERROR"))
    end
end

-- At TwichUI's ADDON_LOADED, before its saved data is checked. The flag is cleared first, so a start-up that fails
-- (or a client that stops) never arms the next one too.
function L.ArmedBoot()
    local arm = L.Armed()
    if not arm then return end
    TwichUIDB.diagnosticsArm = nil
    local now = time and time() or 0
    local at = type(arm.at) == "number" and arm.at or 0
    L.boot = { at = at, preset = arm.preset, seconds = arm.seconds, state = "pending" }
    if now - at > L.ARM_FOR or now < at then
        L.boot.state = "expired"
        R:On("PLAYER_ENTERING_WORLD", Tell)
        return
    end
    local ok, why = L.Load(true)
    if not ok then
        L.boot.state, L.boot.why = "failed", why
        R:On("PLAYER_ENTERING_WORLD", Tell)
        return
    end
    local started, err = pcall(R.Diagnostics.StartBoot, L.boot)
    if not started then
        L.boot.state = "failed"
        R:On("PLAYER_ENTERING_WORLD", Tell)
        R.Fault("diagnostics start-up capture", err)
    end
end

---------------------------------------------------------------------------
-- /tui perf
---------------------------------------------------------------------------
local HELP = {
    "/tui perf: the TwichUI Diagnostics window (loads it the first time).",
    "/tui perf start [preset] [minutes]: start recording (presets: general, map, settings, group, memory, focused).",
    "/tui perf stop | cancel: stop and keep the capture | stop and discard it.",
    "/tui perf mark [note]: put a timestamped marker in the capture.",
    "/tui perf status: what is recording. /tui perf arm [preset]: record the next reload's start-up (you reload; nothing reloads by itself). /tui perf disarm.",
}

function L.Command(arg)
    local word, rest = (arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if word == "" then L.Open() return end
    if word == "help" then for _, line in ipairs(HELP) do print(R.GREY .. line .. "|r") end return end
    if word == "status" then
        if not R.Diagnostics then
            Say("not loaded this session, so nothing is recording%s.", L.Armed() and "; the next reload's start-up is armed" or "")
            return
        end
        R.Diagnostics.Command(word, rest)
        return
    end
    if word == "arm" then
        L.Arm(rest ~= "" and rest:lower() or "startup")
        Say("the next reload's start-up will be recorded (for %d minutes from now). Reload when you are ready: nothing reloads by itself. /tui perf disarm cancels it.", L.ARM_FOR / 60)
        return
    end
    if word == "disarm" then
        local was = L.Armed() ~= nil
        L.Disarm()
        Say(was and "the start-up capture is no longer armed." or "nothing was armed.")
        return
    end
    if (word == "stop" or word == "cancel" or word == "mark") and not R.Diagnostics then
        Say("nothing is recording (TwichUI Diagnostics isn't loaded this session).")
        return
    end
    local DX = Ready()
    if DX then DX.Command(word, rest) end
end

-- Read only, for the Troubleshooting page and /tui diagnostics.
function L.Snapshot()
    local DX = R.Diagnostics
    return { loaded = DX ~= nil, recording = DX ~= nil and DX.Recording() or false, armed = L.Armed() ~= nil,
        attempts = L.attempts, failed = L.failed }
end
