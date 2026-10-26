-- TwichUI: layout packages, the core's part
-- The layout engine (package checks, composing, both adapters, the install record's rules, the developer command) is
-- an addon of its own, TwichUI_Layouts, loaded only when asked for (load on demand, no saved variables of its own).
-- docs/layouts/ has the contract. Nothing of it is loaded, built or run in ordinary play. The core keeps only:
--
--   L.Load()          loads it if needed: true, or false and a reason code
--   L.Command(arg)    /tui layout ... : loads it and hands the words over (TwichUI_Layouts/Dev.lua says what they do)
--   L.Pending()       read only: the install record's state when it waits for something that happens at a load
--                     ("applying", "applied", "restoring"), else nil
--
-- And two things at a load, both only while an install record (TwichUIDB.layouts.install) says one is under way:
--   * at EllesmereUI's ADDON_LOADED, EllesmereUI.RegisterExternalInstaller("TwichUI"), so EllesmereUI's own first-run
--     picker (shown at PLAYER_LOGIN + 0.5 s on a new EllesmereUI installation) stays away while TwichUI's install is
--     being finished;
--   * after login, TwichUI_Layouts is loaded and finishes it: it checks what an install or a restore left after the
--     reload (TwichUILayouts' Continue). Nothing is applied or restored then; it only reads and reports.
-- With no record, or one that is finished, the only work here is reading one field at login.

local R = TwichUI
local L = { attempts = 0 }
R.LayoutsLauncher = L
L.ADDON = "TwichUI_Layouts"
L.CONTINUE_AFTER = 3   -- seconds after login: EllesmereUI finishes its own start-up (migrations, its picker at +0.5 s) first

local WHY = {
    MISSING = "its folder, TwichUI_Layouts, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Layouts is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Layouts needs TwichUI turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Layouts can't find TwichUI.",
    INTERFACE_VERSION = "TwichUI Layouts is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Layouts' files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Layouts loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "TwichUI Layouts ran into an error while loading. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
}

function L.Explain(code)
    return "couldn't load the layout tools: " .. (WHY[code] or ("the game says " .. tostring(code) .. "."))
end

function L.Loaded() return R.Layouts ~= nil and R.Layouts.ready == true end

local function LoadAddOn()
    return pcall(C_AddOns.LoadAddOn, L.ADDON)
end

-- Loads TwichUI_Layouts if it isn't loaded. Returns true, or false and a reason code.
function L.Load()
    if L.Loaded() then return true end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    L.attempts = L.attempts + 1
    local ok, loaded, reason = R.Perf.Call("layouts.load", LoadAddOn)
    if not ok then
        R.Fault("layouts", loaded)
        return false, "ERROR"
    end
    if not loaded then return false, reason or "UNKNOWN" end
    if not L.Loaded() then return false, "INCOMPLETE" end
    return true
end

-- The install record's state when a load has something to finish. Reads one field; checks only its type.
local WAITS = { applying = true, applied = true, restoring = true }
function L.Pending()
    local layouts = type(TwichUIDB) == "table" and TwichUIDB.layouts
    local install = type(layouts) == "table" and layouts.install
    local state = type(install) == "table" and install.state
    if type(state) == "string" and WAITS[state] then return state end
    return nil
end

function L.Command(arg)
    local ok, why = L.Load()
    if not ok then
        L.failed = why
        R.Print("%s", L.Explain(why))
        return
    end
    L.failed = nil
    local done, err = pcall(R.Layouts.Command, arg)
    if not done then
        R.Fault("layouts command", err)
        R.Print("%s", L.Explain("ERROR"))
    end
end

-- Read only, for /tui diagnostics.
function L.Snapshot()
    return { loaded = L.Loaded(), attempts = L.attempts, failed = L.failed, pending = L.Pending() }
end

---------------------------------------------------------------------------
-- At a load, only while an install is under way
---------------------------------------------------------------------------
local function Continue()
    if not L.Pending() then return end
    local ok, why = L.Load()
    if not ok then
        L.failed = why
        R.Print("a layout install waits to be checked, but %s", L.Explain(why))
        return
    end
    local done, err = pcall(R.Layouts.Continue)
    if not done then R.Fault("layouts continue", err) end
end

local function KeepPickerAway(name)
    if name ~= "EllesmereUI" then return end
    local state = L.Pending()
    if state ~= "applying" and state ~= "applied" then return end
    local E = rawget(_G, "EllesmereUI")
    if type(E) == "table" and type(E.RegisterExternalInstaller) == "function" then
        local ok, err = pcall(E.RegisterExternalInstaller, "TwichUI")
        if not ok then R.Fault("layouts EllesmereUI installer", err) end
        L.registered = ok
    end
end

R:On("ADDON_LOADED", KeepPickerAway)
R:On("PLAYER_LOGIN", function()
    if not L.Pending() then return end
    C_Timer.After(L.CONTINUE_AFTER, Continue)
end)
