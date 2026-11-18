-- TwichUI: opening the Workshop
-- The Workshop (browse your professions' recipes, queue crafts, see the combined materials still needed) is an addon of its
-- own, TwichUI_Workshop, loaded the first time it is asked for (load on demand), like TwichUI Diagnostics. Nothing of it is loaded,
-- built at login unless the active profile opts in. Only that opt-in schedules a delayed load; it opens no window. docs/workshop.md has the whole.
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
    EXPERIMENTAL_OFF = "Workshop is experimental and turned off. Enable Workshop — Experimental in TwichUI Settings > Workshop.",
    SAVED_NEWER = "your settings were saved by a newer TwichUI and are being kept unchanged. Use a compatible version before enabling Workshop.",
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
    if not L.Enabled() then return false, "EXPERIMENTAL_OFF" end
    if L.Loaded() then
        if R.Workshop.Resume then R.Workshop.Resume() end
        return true
    end
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
    if R.Workshop.Resume then R.Workshop.Resume() end
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

-- Shared guarded service load for both AH contexts; never attaches native scan
-- controls merely to change presentation. Existing Load owns consent/diagnostics.
function L.LoadAuctionUI()
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    local previous = L.previewLoading
    L.previewLoading = true
    local ok, loaded, why = pcall(L.Load)
    L.previewLoading = previous
    if not ok then R.Fault("auction UI load", loaded); return false, "ERROR" end
    return loaded, why
end

-- Explicit standalone preview; never touches the native Auction House or Host.
function L.AuctionPreview()
    if InCombatLockdown and InCombatLockdown() then Say("%s", L.Explain("COMBAT")); return false end
    -- Workshop's optional native scan-button integration is deferred for this
    -- load path: previewing must not add children or hooks to Blizzard's frame.
    L.previewLoading = true
    local loaded, WS = pcall(Ready)
    L.previewLoading = nil
    if not loaded then R.Fault("auction preview load", WS); Say("%s", L.Explain("ERROR")); return false end
    if not WS then return false end
    if not (WS.AuctionUI and WS.AuctionUI.Show) then Say("%s", L.Explain("INCOMPLETE")); return false end
    local ok, result, why = pcall(WS.AuctionUI.Show)
    if not ok then
        WS.AuctionUI.Hide()
        R.Fault("auction preview", result)
        Say("%s", L.Explain("ERROR"))
        return false
    end
    if result ~= true then Say("%s", L.Explain(why or "INCOMPLETE")); return false end
    return true
end

function L.Command(arg)
    local word = (arg or ""):match("^%s*(%S*)"):lower()
    if word == "" or word == "open" then L.Toggle() return end
    print(R.GREY .. "/tui workshop: open or close the Workshop (loads it the first time)." .. "|r")
end

local loginState, loginMS = "waiting", nil
function L.Snapshot()
    return { enabled = L.Enabled(), loaded = L.Loaded(), attempts = L.attempts, failed = L.failed, login = loginState, loginMS = loginMS }
end

-- Profile-scoped opt-in. Only the old explicit login preference establishes
-- prior intent; stored recipes/queues/history are never used to infer consent.
function L.Enabled()
    local ui = type(TwichUIDB) == "table" and TwichUIDB.ui
    if type(ui) ~= "table" then return false end
    if type(ui.workshopEnabled) == "boolean" then return ui.workshopEnabled end
    return ui.workshopEnabled == nil and ui.workshopLoadOnLogin == true
end
function L.Migrate()
    if type(TwichUIDB) ~= "table" or (R.Persist and R.Persist.IsHeld("TwichUIDB")) then return end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    if TwichUIDB.ui.workshopEnabled == nil then
        TwichUIDB.ui.workshopEnabled = TwichUIDB.ui.workshopLoadOnLogin == true
    end
end
function L.Apply()
    L.Migrate()
    if not L.Enabled() and R.AuctionHost then R.AuctionHost.SetTestEnabled(false) end
    local w = L.Loaded() and R.Workshop
    if w then
        if L.Enabled() then if w.Resume then w.Resume() end
        elseif w.Suspend then w.Suspend() end
    end
end
function L.SetEnabled(on)
    if type(on) ~= "boolean" or type(TwichUIDB) ~= "table" then return false, "ERROR" end
    if R.Persist and R.Persist.IsHeld("TwichUIDB") then return false, "SAVED_NEWER" end
    if on and InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    L.Migrate()
    TwichUIDB.ui.workshopEnabled = on
    L.Apply()
    -- Enabling permits the normal explicit Load/Open path. It does not eagerly
    -- deserialize a large saved market database or attach native AH controls.
    return true
end
R:OnInit(L.Migrate)
if R.Profiles and R.Profiles.OnApply then R.Profiles.OnApply("views", "workshop-opt-in", L.Apply) end

-- Lightweight settings access. Reading this never loads the Workshop or its
-- separate market database. Presentation keys keep their established scope.
function L.LoadOnLogin()
    local ui = type(TwichUIDB) == "table" and TwichUIDB.ui
    return type(ui) == "table" and ui.workshopLoadOnLogin == true or false
end
function L.SetLoadOnLogin(on)
    if type(on) ~= "boolean" or type(TwichUIDB) ~= "table" then return false end
    if on == L.LoadOnLogin() then return true end
    if type(TwichUIDB.ui) ~= "table" then TwichUIDB.ui = {} end
    TwichUIDB.ui.workshopLoadOnLogin = on or nil
    return true
end
function L.SettingsState()
    local ws = type(TwichUIDB) == "table" and TwichUIDB.workshop
    local view = type(ws) == "table" and type(ws.view) == "table" and ws.view or {}
    local stock = type(ws) == "table" and type(ws.storage) == "table" and ws.storage or {}
    local w = L.Enabled() and L.Loaded() and R.Workshop
    if w then return { prices = w.Session.PriceDetail(), guild = w.Storage.UseGuild(), notices = w.Notice.On(),
        advisorGain = tostring(w.Advisor and w.Advisor.Gain() or 0), objective = w.Session.Objective(), compact = w.Session.CompactMode() } end
    return { prices = view.prices == "detailed", guild = stock.useGuild == true, notices = view.notices ~= false,
        advisorGain = tostring(type(view.advisorGain)=="number" and view.advisorGain or 0), objective = view.objective == "cash" and "cash" or "economic", compact = view.compactMode == "craft" and "craft" or "travel" }
end
function L.SetOption(key, on)
    if type(on) ~= "boolean" or not L.Loaded() then return false end
    local w = R.Workshop
    local ok
    if key == "prices" then ok = w.Session.SetPriceDetail(on)
    elseif key == "guild" then ok = w.Session.SetUseGuild(on)
    elseif key == "notices" then ok = w.Notice.SetOn(on)
    else return false end
    if ok and w.Window and w.Window.IsShown() then w.Window.Render() end
    if ok and w.Compact and w.Compact.IsShown() then w.Compact.Schedule() end
    return ok
end

function L.SetChoice(key, value)
    if not L.Loaded() then return false end
    local w, ok = R.Workshop
    if key == "objective" then ok = w.Session.SetObjective(value)
    elseif key == "compact" then ok = w.Compact.SetMode(value)
    elseif key == "advisorGain" and w.Advisor then ok = w.Advisor.SetGain(tonumber(value))
    else return false end
    if ok and w.Window and w.Window.IsShown() then w.Window.Render() end
    if ok and w.Compact and w.Compact.IsShown() then w.Compact.Schedule() end
    return ok
end

-- A session's first world entry latches the login choice, after profile loading.
-- Off means no timer and no Workshop initialization. Opting in later takes effect
-- next login/reload. Deserialization is synchronous even though the load is delayed.
local entered, pending, waiting, attempted = false, false, false, false
local generation
local function CurrentProfile()
    return R.Profiles and R.Profiles.Generation and R.Profiles.Generation() or 0
end
local function ScheduleLogin()
    if pending or attempted then return end
    pending, waiting, loginState = true, false, "scheduled"
    C_Timer.After(2, function()
        pending = false
        if generation ~= CurrentProfile() or not L.Enabled() or not L.LoadOnLogin() then loginState = "cancelled"; return end
        if not R.Life.InWorld() then loginState = "world"; return end
        if L.Loaded() then attempted, loginState = true, "already-loaded"; return end
        if InCombatLockdown and InCombatLockdown() then waiting, loginState = true, "combat"; return end
        attempted = true
        local start = debugprofilestop and debugprofilestop()
        local ok, why = L.Load()
        if start then loginMS = math.max(0, debugprofilestop() - start) end
        loginState = ok and "loaded" or (why or "failed")
        if not ok and R.Life then R.Life.Note("workshop-login-failed") end
    end)
end
R:On("PLAYER_ENTERING_WORLD", function()
    if not (R.Life and R.Life.configReady) then return end
    if entered then
        if loginState == "world" then ScheduleLogin() end
        return
    end
    entered = true
    if not L.Enabled() or not L.LoadOnLogin() then loginState = "off"; return end
    generation = CurrentProfile()
    ScheduleLogin()
end)
R:On("PLAYER_REGEN_ENABLED", function()
    if waiting and not attempted then ScheduleLogin() end
end)
