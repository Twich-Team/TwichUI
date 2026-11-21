-- TwichUI: loading TwichUI Fishing
-- TwichUI Fishing (one key that equips your pole, applies a lure, casts, reels in and opens the clams you catch, each on your
-- own press, and a record of your fishing) is an addon of its own, TwichUI_Fishing, loaded on demand (docs/fishing.md).
-- It is loaded:
--   * by /tui fish (any of its commands), and
--   * at login, or when the key bindings change, if one of its keys is bound (Key Bindings > TwichUI > Fishing): a bound key
--     is the player's choice to use it, and the key's secure button must exist before it is pressed.
-- Never in combat: a load asked for in combat waits until combat ends. Nothing else of it runs here; its names in the
-- Key Bindings list are set here so they read well before it has loaded.
--
--   L.Loaded()      read only: has it started this session
--   L.Load()        loads it if needed: true, or false and a reason code
--   L.Command(arg)  /tui fish
--   L.Snapshot()    read only: loaded, attempts, failed, waiting
--   L.Mode()        the "Fishing Mode" key (Bindings.xml): loads the addon if needed (never in combat), then turns Fishing Mode
--                   on or off
--   L.Reveal(state) the "reveal the interface" key, held: "down" shows the faded interface, "up" fades it again

local R = TwichUI
local L = { attempts = 0 }
R.FishingLauncher = L
L.ADDON = "TwichUI_Fishing"
L.BINDINGS = { "CLICK TwichUIFishingButton:LeftButton", "CLICK TwichUIFishingOpen:LeftButton", "TWICHUI_FISHING_MODE",
    "TWICHUI_FISHING_REVEAL" }

_G.BINDING_HEADER_TWICHUI = _G.BINDING_HEADER_TWICHUI or "TwichUI"
_G["BINDING_NAME_" .. L.BINDINGS[1]] = "Fishing: the next step (equip, lure, open a clam, cast; reel while the line is out)"
_G["BINDING_NAME_" .. L.BINDINGS[2]] = "Fishing: open the next fishing container"
_G["BINDING_NAME_" .. L.BINDINGS[3]] = "Fishing Mode: on or off"
_G["BINDING_NAME_" .. L.BINDINGS[4]] = "Fishing Mode: reveal the interface (hold)"

local WHY = {
    MISSING = "its folder, TwichUI_Fishing, is missing. Reinstall TwichUI to put it back.",
    DISABLED = "TwichUI Fishing is turned off in your AddOns list. Turn it on there, then reload.",
    DEP_DISABLED = "TwichUI Fishing needs TwichUI turned on in your AddOns list.",
    DEP_MISSING = "TwichUI Fishing can't find TwichUI.",
    INTERFACE_VERSION = "TwichUI Fishing is marked for another game version. Reinstall TwichUI, or allow out-of-date addons.",
    CORRUPT = "TwichUI Fishing's files are damaged. Reinstall TwichUI.",
    INCOMPLETE = "TwichUI Fishing loaded but didn't start. /tui diagnostics has the error.",
    ERROR = "TwichUI Fishing ran into an error while loading. /tui diagnostics has the details.",
    NO_API = "this game client can't load it.",
    COMBAT = "not during combat; it will load when combat ends.",
}

function L.Explain(code)
    return "couldn't start TwichUI Fishing: " .. (WHY[code] or ("the game says " .. tostring(code) .. "."))
end

function L.Loaded() return R.Fishing ~= nil and R.Fishing.ready == true end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

local OnRegen
local function WaitForCombat()
    if L.waiting then return end
    L.waiting = true
    if R.Life and R.Life.Note then R.Life.Note("deferred-combat") end
    R:On("PLAYER_REGEN_ENABLED", OnRegen)
end

local function LoadAddOn() return pcall(C_AddOns.LoadAddOn, L.ADDON) end

function L.Load()
    if L.Loaded() then return true end
    if InCombat() then WaitForCombat() return false, "COMBAT" end
    if not (C_AddOns and C_AddOns.LoadAddOn) then return false, "NO_API" end
    if L.failed and L.failed ~= "INCOMPLETE" and L.failed ~= "ERROR" and L.attempts >= 3 then return false, L.failed end
    L.attempts = L.attempts + 1
    local ok, loaded, reason = R.Perf.Call("fishing.load", LoadAddOn)
    if not ok then
        R.Fault("fishing", loaded)
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

-- A key bound to one of its actions (the player chose to use it).
function L.KeyBound()
    if not GetBindingKey then return false end
    for _, action in ipairs(L.BINDINGS) do
        local k = GetBindingKey(action)
        if type(k) == "string" and k ~= "" then return true end
    end
    return false
end

local function LoadIfBound()
    if L.Loaded() or not L.KeyBound() then return end
    L.Load()
end

function OnRegen()
    L.waiting = false
    R:Off("PLAYER_REGEN_ENABLED", OnRegen)
    if L.wanted or L.KeyBound() then L.wanted = nil; L.Load() end
end

R:On("PLAYER_LOGIN", LoadIfBound)
R:On("UPDATE_BINDINGS", function()
    if L.Loaded() then return end
    -- the binding list changes in bursts while the game starts and while the player edits keys: look once they settle
    if C_Timer and C_Timer.After then C_Timer.After(0.5, LoadIfBound) else LoadIfBound() end
end)

function L.Command(arg)
    local ok, why = L.Load()
    if not ok then
        if why == "COMBAT" then L.wanted = true end
        R.Print("%s", L.Explain(why))
        return
    end
    local F = R.Fishing
    if F and F.Main and F.Main.Command then
        local fine, err = pcall(F.Main.Command, arg)
        if not fine then R.Fault("fishing command", err) end
    end
end

function L.Mode()
    local ok, why = L.Load()
    if not ok then
        if why == "COMBAT" then L.wanted = true end
        R.Print("%s", L.Explain(why))
        return
    end
    local P = R.Fishing and R.Fishing.Present
    if P and P.Command then
        local fine, err = pcall(P.Command, "mode", "")
        if not fine then R.Fault("fishing mode key", err) end
    end
end

function L.Reveal(state)
    if not L.Loaded() then return end
    local P = R.Fishing.Present
    if P and P.Reveal then pcall(P.Reveal, state ~= "up") end
end

function L.Snapshot()
    return { loaded = L.Loaded(), attempts = L.attempts, failed = L.failed, waiting = L.waiting and true or false }
end
