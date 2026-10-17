-- TwichUI: what turning a feature's switch on or off does
-- Every on/off switch lives in TwichUIDB.modules (defaults: Core.lua's DEFAULT_MODULES). This file says what a
-- change means for each feature: the update to run, and whether it takes effect only after a reload. It is
-- part of the core addon, so a switch flipped anywhere (the settings window, R:SetEnabled, a profile change)
-- does the same thing whether or not the settings window was ever opened.
--
--   W.Set(key, on, alreadyApplied)  the one way to change a switch: saves it, and runs the feature's update
--                                   only when the value differs from the one last acted on
--   W.Sync()                        after a profile change put other values in TwichUIDB.modules: each switch
--                                   in turn, as a click would (a feature whose switch didn't change does nothing)
--   W.IsPending(key)                whether one switch waits for a reload (differs from the value the UI loaded with)
--   W.ReloadPending()               whether any switch does
--   W.PendingReloads()              which, as sorted keys (W.ReloadName(key): in words)
--   W.OnChange(fn)                  fn(key, on) after every Set and Sync (the settings window follows)
--
-- A switch whose feature isn't there this session (not a Mage, no RestedXP skin module) has `when`, and is
-- left alone by Sync, as it was when its options were not built.

local R = TwichUI
local W = { defs = {}, order = {}, applied = {}, atLoad = {}, listeners = {}, wantsReload = {} }
R.Switches = W

---------------------------------------------------------------------------
-- Asking for a reload. With the settings window open it shows a quiet notice there instead of a question;
-- otherwise the question, as before.
---------------------------------------------------------------------------
function W.RequestReload()
    local UI = R.SettingsUI
    if UI and UI.IsShown and UI.IsShown() then
        UI.ReloadNotice()
        return
    end
    StaticPopupDialogs.TWICHUI_RELOAD = {
        text = "TwichUI: this change takes effect after reloading your UI. Reload now?",
        button1 = RELOADUI or "Reload", button2 = "Later",
        OnAccept = ReloadUI,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_RELOAD")
end

---------------------------------------------------------------------------
-- Definitions. def: { apply = function(on) (optional), reload = true (optional), when = function (optional) }.
-- The order here is the order Sync goes in: a parent switch before the ones under it.
---------------------------------------------------------------------------
local function Define(key, def)
    def = def or {}
    if not W.defs[key] then W.order[#W.order + 1] = key end
    W.defs[key] = def
end
W.Define = Define

-- Calls R[module].method() if the module is there (a dot call, as the features define them).
local function Refresh(module, method)
    method = method or "Refresh"
    return function()
        local m = R[module]
        if m and m[method] then m[method]() end
    end
end

-- Gear comparison
Define("gearHints")
Define("gearBagIcons", { apply = Refresh("GearBags") })

-- Notifications
Define("arrivalReducedMotion")
Define("arrival", { apply = Refresh("Arrival") })
Define("arrivalSubzones", { apply = Refresh("Arrival") })
Define("arrivalDungeons", { apply = Refresh("Arrival") })
Define("trainingNotice", { apply = Refresh("Training") })
Define("friendLogin", { apply = Refresh("FriendLogin") })
Define("friendLoginSound")

-- Quality of life: each runs its own feature's Apply
local function QoL(module)
    return {
        when = function() return R.QoL ~= nil end,
        apply = function()
            local feature = R[module] and R[module].feature
            if feature and R.QoL then R.QoL.Apply(feature) end
        end,
    }
end
Define("qolSummons", QoL("QoLSummons"))
Define("qolResurrect", QoL("QoLResurrect"))
Define("qolResurrectCombat", QoL("QoLResurrect"))
Define("qolReleasePvP", QoL("QoLRelease"))
Define("qolDuels", QoL("QoLDuels"))
Define("qolDuelsToDeath", QoL("QoLDuels"))
Define("qolQuickKeybind", QoL("QoLQuickKeybind"))
Define("qolEasyFishing", QoL("QoLEasyFishing"))
do
    local def = QoL("QoLGuideWaypoint")
    def.when = function() return R.QoL ~= nil and R.QoLGuideWaypoint ~= nil end
    Define("qolGuideWaypoint", def)
end

-- Food and drink
Define("foodDrink", { apply = Refresh("FoodDrink") })
Define("qolMageConjureFoodDrink", { apply = Refresh("FoodDrink") })   -- read by modules/FoodDrink.lua
Define("foodDrinkFood", { apply = Refresh("FoodDrink") })
Define("foodDrinkDrink", { apply = Refresh("FoodDrink") })
Define("foodDrinkUnlock", {
    when = function() return R.FoodDrink ~= nil and R.FoodDrink.Unlock ~= nil end,
    apply = Refresh("FoodDrink"),
})

-- Mage (Mages only)
local function IsMage() return R.MageTravel ~= nil and R.MageTravel.ForPlayer() end
-- A launcher turned off leaves the data bar only after a reload.
local function Launcher(module, key)
    return {
        when = IsMage,
        apply = function()
            local m = R[module]
            if not m then return end
            m.Refresh()
            if not R:Enabled(key) and m.Available() then
                W.wantsReload[key] = true
                W.RequestReload()
            else
                W.wantsReload[key] = nil   -- on again before a reload: it never left the data bar
            end
        end,
    }
end
Define("mageTravel", Launcher("MageTravel", "mageTravel"))
Define("mageConjure", Launcher("MageConjure", "mageConjure"))
Define("mageRefreshments", { when = function() return IsMage() and R.Refreshments ~= nil end, apply = Refresh("Refreshments") })
Define("mageRefreshmentsTrade", {
    when = function() return IsMage() and R.Refreshments ~= nil and R.RefreshmentsTrade ~= nil end,
    apply = Refresh("RefreshmentsTrade"),
})
Define("mageRefreshmentsAutoFill", { when = function() return IsMage() and R.Refreshments ~= nil and R.RefreshmentsTrade ~= nil end })
local function SellWhen() return IsMage() and R.MageSell ~= nil end
Define("mageSell", {
    when = SellWhen,
    apply = function()
        local MSL = R.MageSell
        MSL.Refresh()
        if MSL.Enabled() and MSL.Mode() == "ellesmere" then
            R.Print("ordinary food and drink will be marked as junk in EllesmereUI's bags" .. (MSL.DryRun() and " once Dry run is turned off (for now it only reports). /tui sell shows what would be marked." or ". /tui sell shows what is kept."))
        elseif MSL.Enabled() then
            R.Print("ordinary food and drink will be sold at merchants" .. (MSL.DryRun() and " once Dry run is turned off (for now it only reports). /tui sell shows what would go." or ". /tui sell shows what is kept."))
        end
    end,
})
Define("mageSellFood", { when = SellWhen, apply = Refresh("MageSell") })
Define("mageSellDrink", { when = SellWhen, apply = Refresh("MageSell") })
Define("mageSellDryRun", { when = SellWhen, apply = Refresh("MageSell") })

-- Journey Chronicle
Define("chronicle", { apply = Refresh("ChronicleRecorder") })
for _, key in ipairs({ "chronicleLevels", "chronicleZones", "chronicleBosses", "chronicleDeaths", "chronicleGold",
    "chronicleRiding", "chronicleProfessions", "chronicleChat" }) do
    Define(key, { apply = Refresh("ChronicleRecorder") })
end
Define("chronicleSound")
Define("welcomeBack", { apply = Refresh("WelcomeBack") })

-- Party pins
Define("partyPins", {
    when = function() return R.Pins ~= nil and R.PinsLook ~= nil end,
    apply = function(on)
        for _, module in ipairs({ "PinSync", "PinsMap", "PinsMinimap", "PinsBroker", "PinsWay" }) do
            if R[module] then R[module].Refresh() end
        end
        if not on then
            if R.PinsWindow then R.PinsWindow.Hide(); R.PinsWindow.CloseMenu() end
            if R.PinsEditor then R.PinsEditor.Close() end
            if R.PinsBrokerMenu then R.PinsBrokerMenu.Close() end
        end
    end,
})

-- Auction House
Define("auctionPosting", { apply = Refresh("AuctionWindow") })

-- Addon skins: through EllesmereUI, after a reload
for _, key in ipairs({ "attuneSkin", "auctionatorSkin", "foreverDungeonJournalSkin", "whatsTrainingSkin" }) do
    Define(key, { reload = true })
end
Define("restedxpSkin", { when = function() return R.RestedXPSkin ~= nil end, apply = Refresh("RestedXPSkin", "OnSwitch") })
Define("speakstoneSkin", { when = function() return R.SpeakStoneSkin ~= nil end, apply = Refresh("SpeakStoneSkin", "OnSwitch") })

-- Configuration sharing (the sharing window shows these switches' state)
local function RefreshWindow() if R.Window then R.Window:Refresh() end end
Define("setupSharing", {
    reload = true,
    apply = function(on)
        if not on and R.Share then R.Share:Settle("module-off") end
        RefreshWindow()
    end,
})
Define("acceptSetups", {
    apply = function(on)
        if not on and R.Share then R.Share:Settle("module-off", true) end
        RefreshWindow()
    end,
})
Define("groupCheck", { reload = true, apply = RefreshWindow })

-- TwichUI as a whole
Define("media", { reload = true })
Define("quietLogin", { reload = true })

---------------------------------------------------------------------------
-- Changing a switch
---------------------------------------------------------------------------
function W.NeedsReload(key) return W.defs[key] ~= nil and W.defs[key].reload == true end

function W.Available(key)
    local def = W.defs[key]
    if not (def and def.when) then return true end
    return def.when() and true or false
end

local function Notify(key, on)
    for _, fn in ipairs(W.listeners) do
        local ok, err = pcall(fn, key, on)
        if not ok then R.Fault("switch listener", err) end
    end
end

function W.OnChange(fn)
    for _, existing in ipairs(W.listeners) do if existing == fn then return end end
    W.listeners[#W.listeners + 1] = fn
end

-- The value last acted on (the one the UI loaded with until something changed it).
local function Applied(key)
    local v = W.applied[key]
    if v == nil then v = W.atLoad[key] end
    if v == nil then v = R:Enabled(key) end
    return v
end

-- The value in TwichUIDB.modules is already the new one: act on it if it differs from the last one acted on.
local function Follow(key)
    local on = R:Enabled(key)
    if on ~= Applied(key) then
        W.applied[key] = on
        local def = W.defs[key]
        if def and W.Available(key) then
            local atLoad = W.atLoad[key]
            if def.reload and atLoad ~= nil and on ~= atLoad then W.RequestReload() end
            if def.apply then def.apply(on) end
        end
    end
    return on
end

-- The one way to turn a switch on or off. alreadyApplied: the caller has done what the change needs; only the
-- record (and anything showing it) follows.
function W.Set(key, on, alreadyApplied)
    on = on and true or false
    if not (TwichUIDB and type(TwichUIDB.modules) == "table") then return end
    TwichUIDB.modules[key] = on
    if alreadyApplied then W.applied[key] = on end
    Follow(key)
    Notify(key, on)
end

-- After a profile change: every switch follows its new value, in order. Returns the keys whose update failed
-- (each reported); the rest are still told.
function W.Sync()
    local failed = {}
    for _, key in ipairs(W.order) do
        if W.Available(key) then
            local ok, err = pcall(Follow, key)
            if not ok then
                failed[#failed + 1] = key
                R.Fault("switch " .. key, err)
            end
        end
    end
    Notify(nil, nil)
    return failed
end

-- Whether one switch waits for a reload: it takes effect only after one and now differs from the value the UI
-- loaded with (so turning it back before a reload clears it), or its feature is waiting for one (a Mage
-- launcher turned off leaves the data bar only after a reload). Nothing here is set by a click alone.
function W.IsPending(key)
    if W.wantsReload[key] then return true end
    local def = W.defs[key]
    return def ~= nil and def.reload == true and W.atLoad[key] ~= nil and R:Enabled(key) ~= W.atLoad[key]
end

-- Whether any switch waits for a reload.
function W.ReloadPending()
    if next(W.wantsReload) then return true end
    for key in pairs(W.defs) do
        if W.IsPending(key) then return true end
    end
    return false
end

-- The switches ReloadPending is waiting on, as sorted keys (the troubleshooting status and the settings window
-- name them). Read only.
function W.PendingReloads()
    local seen, list = {}, {}
    for key in pairs(W.wantsReload) do seen[key] = true; list[#list + 1] = key end
    for key in pairs(W.defs) do
        if not seen[key] and W.IsPending(key) then list[#list + 1] = key end
    end
    table.sort(list)
    return list
end

-- A pending switch's name in words (the one the troubleshooting status uses), or nil.
function W.ReloadName(key)
    local S = R.DiagStatus
    return S and S.RELOAD_NAMES and S.RELOAD_NAMES[key] or nil
end

-- The values the UI loaded with: noted once the saved variables (and this character's profile) are in.
R:OnInit(function()
    for key in pairs(R.DEFAULT_MODULES) do
        local on = R:Enabled(key)
        W.atLoad[key], W.applied[key] = on, on
    end
end)
