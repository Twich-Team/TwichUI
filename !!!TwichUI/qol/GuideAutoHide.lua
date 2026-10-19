-- TwichUI: Quality of Life, RestedXP guide shown and hidden by situation
-- Hides RestedXP's guide while one of the situations the player chose is on (in a dungeon, in a raid, in a
-- battleground or arena, in a group, resting, on a flight path) and shows it again when none is. Off until
-- turned on. RestedXP's guide content, progress and settings are never changed: the only thing done is what
-- RestedXP's own Show/Hide does.
--
-- What RestedXP gives us (RXPGuides v4.11.22 source, SettingsPanel.lua; not a public interface, checked on
-- every use): its addon object is registered with AceAddon as "RXPGuides". settings.ToggleActive() flips
-- settings.profile.showEnabled and shows or hides every RestedXP frame; it is what its minimap button, its
-- menu's Show/Hide and "/rxp toggle" call, and what the data bar menu (modules/RestedXPBroker.lua) calls.
-- It is hooked once, to notice a toggle the player made. settings:RefreshProfile (a RestedXP profile change)
-- is hooked once too. RestedXP leaves its secure frames alone in combat, so a change waits for combat to end.
--
-- What the game gives us (WoW: Forever UI source): IsInInstance() (the type: "party", "raid", "pvp",
-- "arena"), IsInGroup(), IsResting() and UnitOnTaxi("player"), and the events PLAYER_ENTERING_WORLD,
-- ZONE_CHANGED_NEW_AREA, GROUP_ROSTER_UPDATE, PLAYER_UPDATE_RESTING, PLAYER_CONTROL_LOST and
-- PLAYER_CONTROL_GAINED. Only the events the chosen situations need are listened to.
--
-- The player's choice comes first:
--   * It acts when a situation begins (nothing wanted, then something wanted) and when the last one ends.
--     Between those it leaves the guide alone, so showing the guide yourself in a dungeon keeps it shown
--     until you leave, and hiding it yourself elsewhere is never undone.
--   * It only shows the guide again if it was the one that hid it. A guide you had hidden before the
--     situation began stays hidden. A toggle you make while it has the guide hidden is yours: it is not
--     put back.
--   * That it hid the guide is remembered per character (TwichUIDB.ui.guideAuto[guid]), so after a reload
--     in a dungeon the guide still comes back when you leave it.
--   * Turning the feature off shows the guide again if this had hidden it.
--   * Nothing is changed in combat; the change waits for PLAYER_REGEN_ENABLED.

local R = TwichUI
local Q = R.QoL
local A = {}
R.QoLGuideAuto = A

local ADDON = "RXPGuides"
local KEY = "qolGuideAuto"

-- The situations, in the order they are listed: the switch that chooses each, and its words for the tooltip.
A.SITUATIONS = {
    { key = "qolGuideAutoDungeon", id = "dungeon", label = "In a dungeon" },
    { key = "qolGuideAutoRaid", id = "raid", label = "In a raid" },
    { key = "qolGuideAutoPvP", id = "pvp", label = "In a battleground or arena" },
    { key = "qolGuideAutoGroup", id = "group", label = "In a group" },
    { key = "qolGuideAutoResting", id = "resting", label = "Resting" },
    { key = "qolGuideAutoFlight", id = "flight", label = "On a flight path" },
}

local rxp                    -- RestedXP's addon object, once found
local hooked = false
local loaded = false         -- the remembered record has been read for this character
local ours = false           -- this hid the guide, and it hasn't been shown since
local wasWanted = false      -- a chosen situation was on at the last look
local writing = false        -- our own ToggleActive is running
local pending = false        -- a change waits for combat to end
local stopPending = false    -- turned off in combat: the guide comes back when it ends
local rechecking = false     -- a delayed look at the flight state is on its way
local shownWhy               -- the situation that has the guide hidden (for the tooltip), or nil

---------------------------------------------------------------------------
-- RestedXP
---------------------------------------------------------------------------
local function FindRestedXP()
    local ace = LibStub and LibStub("AceAddon-3.0", true)
    if not (ace and type(ace.GetAddon) == "function") then return nil end
    local ok, addon = pcall(ace.GetAddon, ace, ADDON, true)
    if ok and type(addon) == "table" then return addon end
end

local function Usable(addon)
    local settings = type(addon) == "table" and addon.settings
    return type(settings) == "table" and type(settings.ToggleActive) == "function" and type(settings.profile) == "table"
end

local function GuideOn()
    return rxp.settings.profile.showEnabled and true or false
end

---------------------------------------------------------------------------
-- The record of what this hid
---------------------------------------------------------------------------
local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    return type(ui) == "table" and type(ui.guideAuto) == "table" and ui.guideAuto or nil
end

local function Remember()
    local guid = UnitGUID and UnitGUID("player")
    if not guid then return end
    local saved = Saved()
    if not saved then
        if not ours then return end   -- nothing to say, nothing to create
        TwichUIDB.ui = TwichUIDB.ui or {}
        TwichUIDB.ui.guideAuto = {}
        saved = TwichUIDB.ui.guideAuto
    end
    saved[guid] = ours or nil
end

-- Once per session, once the character is known.
local function LoadRemembered()
    if loaded then return end
    local guid = UnitGUID and UnitGUID("player")
    if not guid then return end
    loaded = true
    local saved = Saved()
    ours = saved ~= nil and saved[guid] == true
end

---------------------------------------------------------------------------
-- The situations
---------------------------------------------------------------------------
local function InInstance(kind)
    if not IsInInstance then return false end
    local inside, kindNow = IsInInstance()
    if not inside then return false end
    if kind == "pvp" then return kindNow == "pvp" or kindNow == "arena" end
    return kindNow == kind
end

local CHECK = {
    dungeon = function() return InInstance("party") end,
    raid = function() return InInstance("raid") end,
    pvp = function() return InInstance("pvp") end,
    group = function() return IsInGroup and IsInGroup() and true or false end,
    resting = function() return IsResting and IsResting() and true or false end,
    flight = function() return UnitOnTaxi and UnitOnTaxi("player") and true or false end,
}

-- The id of the first chosen situation that is on right now, or nil.
local function Wanted()
    for _, s in ipairs(A.SITUATIONS) do
        if R:Enabled(s.key) and CHECK[s.id]() then return s.id end
    end
end

---------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------
local function Toggle()
    writing = true
    local ok, err = pcall(rxp.settings.ToggleActive)
    writing = false
    if not ok then R.Fault("RestedXP guide toggle", err) end
    return ok
end

local function Hide()
    if GuideOn() and Toggle() then
        ours = true
        Remember()
    end
end

local function Show()
    if not GuideOn() then Toggle() end
    ours = false
    Remember()
end

-- Looks at the situations and acts on a change. Cheap when nothing changed: a few API calls.
function A.Evaluate()
    if not (R:Enabled(KEY) and hooked and Usable(rxp)) then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    LoadRemembered()
    if not loaded then return end
    local why = Wanted()
    local want = why ~= nil
    if want then
        shownWhy = why
        if not wasWanted then Hide() end
    else
        shownWhy = nil
        if ours then Show() end
    end
    wasWanted = want
end

-- The player (or RestedXP) toggled the guide. If this had hidden it, the guide is the player's now.
local function OnToggled()
    if writing or not ours then return end
    ours = false
    Remember()
end

-- A RestedXP profile change: the new profile has its own idea of shown or hidden.
local function OnProfileChanged()
    if writing then return end
    ours = false
    wasWanted = false
    Remember()
    A.Evaluate()
end

local function Attach()
    if not R:Enabled(KEY) then return end
    rxp = rxp or FindRestedXP()
    if not hooked then
        if not Usable(rxp) then return end
        hooked = true
        -- hooked once (a hook can't be removed); Evaluate does nothing while the feature is off
        hooksecurefunc(rxp.settings, "ToggleActive", OnToggled)
        if type(rxp.settings.RefreshProfile) == "function" then
            hooksecurefunc(rxp.settings, "RefreshProfile", OnProfileChanged)
        end
    end
    A.Evaluate()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnAddonLoaded(name)
    -- RestedXP sets itself up in its own handler for this same event: look once that has run.
    if name == ADDON then C_Timer.After(0, Attach) end
end

local function OnChange() A.Evaluate() end

-- The taxi flag can lag the control events by a moment: look again shortly after, once.
local function Recheck()
    rechecking = false
    A.Evaluate()
end

local function OnControl()
    A.Evaluate()
    if not rechecking then
        rechecking = true
        C_Timer.After(1, Recheck)
    end
end

local function OnRegenEnabled()
    if pending then A.Evaluate() end
end

local function FinishStop()
    R:Off("PLAYER_REGEN_ENABLED", FinishStop)
    if not stopPending then return end
    stopPending = false
    if not R:Enabled(KEY) and Usable(rxp) and ours then Show() end
end

function A.Stop()
    wasWanted = false
    shownWhy = nil
    pending = false
    if not (ours and Usable(rxp)) then return end
    if InCombatLockdown() then
        stopPending = true
        R:On("PLAYER_REGEN_ENABLED", FinishStop)
        return
    end
    Show()
end

A.feature = Q.Add({
    key = KEY,
    Events = function()
        stopPending = false
        local events = {
            ADDON_LOADED = OnAddonLoaded,
            PLAYER_LOGIN = Attach,
            PLAYER_REGEN_ENABLED = OnRegenEnabled,
        }
        if R:Enabled("qolGuideAutoDungeon") or R:Enabled("qolGuideAutoRaid") or R:Enabled("qolGuideAutoPvP") then
            events.PLAYER_ENTERING_WORLD = OnChange
            events.ZONE_CHANGED_NEW_AREA = OnChange
        end
        if R:Enabled("qolGuideAutoGroup") then events.GROUP_ROSTER_UPDATE = OnChange end
        if R:Enabled("qolGuideAutoResting") then events.PLAYER_UPDATE_RESTING = OnChange end
        if R:Enabled("qolGuideAutoFlight") then
            events.PLAYER_CONTROL_LOST = OnControl
            events.PLAYER_CONTROL_GAINED = OnControl
        end
        -- turned on, or a situation chosen or dropped, after login: look again
        if R.Life and R.Life.loggedIn then C_Timer.After(0, Attach) end
        return events
    end,
    Stop = A.Stop,
})

---------------------------------------------------------------------------
-- What it is doing, for the settings tooltip. Codes: off, restedxp-missing, restedxp-disabled, waiting,
-- unsupported, none-chosen, hidden, watching.
---------------------------------------------------------------------------
function A.Status()
    if not R:Enabled(KEY) then return "off" end
    local addonState = R.Setups and R.Setups.AddonState and R.Setups.AddonState(ADDON)
    if addonState == "missing" then return "restedxp-missing" end
    if addonState == "disabled" then return "restedxp-disabled" end
    if not hooked then
        local loggedIn = R.Life and R.Life.loggedIn
        local loadedNow = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDON)
        return (loadedNow and loggedIn) and "unsupported" or "waiting"
    end
    local any = false
    for _, s in ipairs(A.SITUATIONS) do any = any or R:Enabled(s.key) end
    if not any then return "none-chosen" end
    if ours and shownWhy then return "hidden", shownWhy end
    return "watching"
end
