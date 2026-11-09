-- TwichUI: opening the Workshop
-- The Workshop (browse your professions' recipes, queue crafts, see the combined materials still needed) is an addon of its
-- own, TwichUI_Workshop, loaded the first time it is asked for (load on demand), like TwichUI Diagnostics. Nothing of it is loaded,
-- built or run at login or in ordinary play, and nothing here runs unless asked: no events, no timers. docs/workshop.md has the whole.
--
--   L.Loaded()      read only: has the addon started this session
--   L.Load()        loads it if needed: true, or false and a reason code (never in combat)
--   L.Open()        loads it and shows its window; true, or false and a reason (said in chat)
--   L.Toggle()      the same, but closes the window when it is open (the command, the menu and the settings page use this)
--   L.Command(arg)  /tui workshop
--   L.Snapshot()    read only: loaded, attempts, failed

local R = TwichUI
local L = { attempts = 0 }
R.WorkshopLauncher = L
L.ADDON = "TwichUI_Workshop"

local function Say(fmt, ...) R.Print("workshop: " .. fmt, ...) end

local WHY = {
    MISSING = "its folder, TwichUI_Workshop, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Workshop is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Workshop needs TwichUI turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Workshop can't find TwichUI.",
    INTERFACE_VERSION = "TwichUI Workshop is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Workshop's files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Workshop loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "TwichUI Workshop ran into an error while loading. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
    COMBAT = "not during combat. Try again when combat ends.",
}

function L.Explain(code)
    return "couldn't open the Workshop: " .. (WHY[code] or ("the game says " .. tostring(code) .. "."))
end

function L.Loaded() return R.Workshop ~= nil and R.Workshop.ready == true end

local function LoadAddOn() return pcall(C_AddOns.LoadAddOn, L.ADDON) end

function L.Load()
    if L.Loaded() then return true end
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    L.attempts = L.attempts + 1
    local ok, loaded, reason = R.Perf.Call("workshop.load", LoadAddOn)
    if not ok then
        R.Fault("workshop", loaded)
        L.failed = "ERROR"
        return false, "ERROR"
    end
    if not loaded then
        L.failed = reason or "UNKNOWN"
        return false, L.failed
    end
    if not L.Loaded() then
        L.failed = "INCOMPLETE"
        return false, "INCOMPLETE"
    end
    L.failed = nil
    return true
end

local function Ready()
    local ok, why = L.Load()
    if ok then return R.Workshop end
    Say("%s", L.Explain(why))
    return nil
end

local function Run(method)
    local WS = Ready()
    if not WS then return false end
    local ok, err = pcall(WS[method])
    if not ok then
        R.Fault("workshop window", err)
        Say("%s", L.Explain("ERROR"))
        return false
    end
    return true
end

function L.Open() return Run("Open") end
function L.Toggle() return Run("Toggle") end

function L.Command(arg)
    local word = (arg or ""):match("^%s*(%S*)"):lower()
    if word == "" or word == "open" then L.Toggle() return end
    print(R.GREY .. "/tui workshop: open or close the Workshop (loads it the first time)." .. "|r")
end

function L.Snapshot()
    return { loaded = L.Loaded(), attempts = L.attempts, failed = L.failed }
end
