-- TwichUI: Quality of Life, EllesmereUI's quest tracker on mouseover while RestedXP's guide is shown
-- Off until turned on. While RestedXP's guide is shown, EllesmereUI's quest tracker is set to Mouseover, so it
-- fades out and comes back when you point at it. When the guide is hidden, the Visibility it had is put back.
-- Needs RestedXP (for its guide) and EllesmereUI's Quest Tracker (for its setting); nothing happens without both.
--
-- What RestedXP gives us (RXPGuides v4.11.22 source, SettingsPanel.lua; not a public interface, checked on every
-- use, as in qol/GuideAutoHide.lua): settings.profile.showEnabled is the guide's shown state, and
-- settings.ToggleActive() is what changes it (its menu, its minimap button, "/rxp toggle" and the data bar menu
-- all call it). It is hooked once, to notice a change, and settings:RefreshProfile too.
--
-- What EllesmereUI gives us (EllesmereUIQuestTracker and EllesmereUI_Visibility.lua; not public interfaces,
-- checked on every use):
--   * The tracker's settings are the questTracker table of the active profile (_G._EQT_DB.profile.questTracker),
--     and of any other profile (EllesmereUIDB.profiles[name].addons.EllesmereUIQuestTracker.questTracker).
--   * Its mode is questTracker.visibility: "always", "mouseover", "in_combat" and so on. EllesmereUI.EvalVisibility
--     reads it, and EllesmereUI.RequestVisibilityUpdate runs every module's visibility again.
--   * EllesmereUIDB.activeProfile names the active profile. EllesmereUI.RefreshAllAddons runs after a profile switch.
--
-- How it is done:
--   * Only questTracker.visibility is written, and the set is never changed. While the single value reads Mouseover,
--     EllesmereUI uses that value and not the multi-select set (visibilityModes) or the match mode (ActiveModes in
--     EllesmereUI_Visibility.lua), so the set's conditions wait until the old value is back. The Visibility options
--     (hide while mounted, only in instances and so on) still apply, as they do with Mouseover.
--   * Nothing is written when the tracker is already on Mouseover, or when EllesmereUI's Spec Override holds its
--     Visibility (visibilityOverride): that is EllesmereUI's to set.
--   * The value each profile had before is remembered in TwichUIDB.ui.guideTracker[profileName], account-wide
--     because EllesmereUI's profiles are. A reload keeps it.
--   * If you change the tracker's Visibility yourself while the guide is shown, that is yours: it is not put back,
--     and the record goes. The next time the guide is shown or hidden it is set again or put back.
--   * A profile switch puts back the profile that was changed, then changes the new one if the guide is shown.
--   * Nothing is changed in combat; the change waits for PLAYER_REGEN_ENABLED. Turning the feature off puts back
--     what it changed.

local R = TwichUI
local Q = R.QoL
local A = {}
R.QoLGuideTracker = A

local ADDON = "RXPGuides"
local TRACKER = "EllesmereUIQuestTracker"
local KEY = "qolGuideTracker"
local MOUSEOVER = "mouseover"
local DEFAULT_MODE = "always"      -- what the tracker's Visibility is when the setting is not stored
local MAX_RETRIES = 10             -- EllesmereUI's settings may not be ready yet at login: look again, a few times

local rxp                          -- RestedXP's addon object, once found
local hooked = false               -- RestedXP is hooked (once, for the session)
local loggedIn = false
local pending = false              -- a change waits for combat to end
local stopPending = false          -- turned off in combat: put back when it ends
local holdPending = false          -- the guide was shown: the tracker still needs to be set to Mouseover
local lastShown, lastProfile       -- what the last look saw, to tell an edge from a repeat
local retrying = false
local retries = 0

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

local function GuideShown()
    return rxp ~= nil and Usable(rxp) and rxp.settings.profile.showEnabled and true or false
end

---------------------------------------------------------------------------
-- EllesmereUI's quest tracker
---------------------------------------------------------------------------
-- Loaded, and its saved data is there. Its settings are read per profile below.
local function Ellesmere()
    return rawget(_G, "EllesmereUIQuestTracker") ~= nil and type(rawget(_G, "EllesmereUIDB")) == "table"
end

local function ActiveProfile()
    local name = EllesmereUIDB and EllesmereUIDB.activeProfile
    return type(name) == "string" and name or "Default"
end

-- The tracker's settings for one profile, or nil when they can't be reached now.
local function Settings(name)
    if name == ActiveProfile() then
        local db = rawget(_G, "_EQT_DB")
        local cfg = type(db) == "table" and type(db.profile) == "table" and db.profile.questTracker
        return type(cfg) == "table" and cfg or nil
    end
    local profiles = type(EllesmereUIDB) == "table" and EllesmereUIDB.profiles
    local data = type(profiles) == "table" and profiles[name]
    local addon = type(data) == "table" and type(data.addons) == "table" and data.addons[TRACKER]
    local cfg = type(addon) == "table" and addon.questTracker
    return type(cfg) == "table" and cfg or nil
end

-- A Spec Override that holds the tracker's Visibility replaces it, so there is nothing to set.
local function Overridden(cfg)
    local E = rawget(_G, "EllesmereUI")
    return type(E) == "table" and type(E.VisOverrideValue) == "function" and E.VisOverrideValue(cfg) ~= nil
end

local function Refresh()
    local E = rawget(_G, "EllesmereUI")
    if type(E) == "table" and type(E.RequestVisibilityUpdate) == "function" then E.RequestVisibilityUpdate() end
end

---------------------------------------------------------------------------
-- The record: profile name -> the Visibility it had before this changed it
---------------------------------------------------------------------------
local function Held()
    local ui = TwichUIDB and TwichUIDB.ui
    local record = type(ui) == "table" and ui.guideTracker
    return type(record) == "table" and record or {}
end

local function Remember(name, value)
    TwichUIDB.ui = TwichUIDB.ui or {}
    if type(TwichUIDB.ui.guideTracker) ~= "table" then TwichUIDB.ui.guideTracker = {} end
    TwichUIDB.ui.guideTracker[name] = value
end

local function Forget(name)
    Held()[name] = nil
end

---------------------------------------------------------------------------
-- Setting the tracker and putting it back
---------------------------------------------------------------------------
-- Sets the active profile's tracker to Mouseover. False when its settings can't be reached yet.
local function Hold(name)
    local cfg = Settings(name)
    if not cfg then return false end
    if cfg.visibility == MOUSEOVER or Overridden(cfg) then return true end
    -- Keep the first value remembered: a later hold (after a reload, or a change made while held) must not
    -- make the value put back a Mouseover or a value the player picked in between.
    if Held()[name] == nil then Remember(name, cfg.visibility or DEFAULT_MODE) end
    cfg.visibility = MOUSEOVER
    Refresh()
    return true
end

-- Puts a profile's tracker back to the value it had, if it still shows Mouseover (a value the player chose since
-- is theirs). False when the profile's settings can't be reached yet.
local function Release(name)
    local value = Held()[name]
    local cfg = Settings(name)
    if not cfg then
        -- the profile, or the tracker's settings in it, is gone: there is nothing to put back
        if name == ActiveProfile() and rawget(_G, "_EQT_DB") == nil then return false end
        Forget(name)
        return true
    end
    if cfg.visibility == MOUSEOVER then
        cfg.visibility = (type(value) == "string" and value ~= "") and value or DEFAULT_MODE
    end
    Forget(name)
    if name == ActiveProfile() then Refresh() end
    return true
end

-- Puts back everything this changed, in any profile. Used when the feature is turned off.
local function ReleaseAll()
    local names = {}
    for name in pairs(Held()) do names[#names + 1] = name end
    for _, name in ipairs(names) do Release(name) end
end

---------------------------------------------------------------------------
-- Looking at the guide and the tracker
---------------------------------------------------------------------------
local function Later()
    if retrying or retries >= MAX_RETRIES then return end
    retries = retries + 1
    retrying = true
    C_Timer.After(1, function()
        retrying = false
        A.Evaluate()
    end)
end

-- Brings the tracker in line with the guide. Cheap when nothing changed: a few table reads.
function A.Evaluate()
    if not (loggedIn and R:Enabled(KEY) and Ellesmere()) then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    local active = ActiveProfile()
    local shown = GuideShown()
    if shown ~= lastShown or active ~= lastProfile then
        lastShown, lastProfile = shown, active
        holdPending = shown
    end
    local complete = true
    for name in pairs(Held()) do
        -- a record is kept only for the active profile, while the guide is shown
        if name ~= active or not shown then
            if not Release(name) then complete = false end
        end
    end
    if shown and holdPending then
        if Hold(active) then holdPending = false else complete = false end
    end
    if complete then retries = 0 else Later() end
end

-- The guide's own functions (ToggleActive, RefreshProfile) and EllesmereUI's profile refresh.
local function OnChange() A.Evaluate() end

local function Attach(evaluate)
    if not R:Enabled(KEY) then return end
    rxp = rxp or FindRestedXP()
    if not hooked and Usable(rxp) and Ellesmere() then
        -- hooked once (a hook can't be removed); Evaluate does nothing while the feature is off
        hooked = true
        hooksecurefunc(rxp.settings, "ToggleActive", OnChange)
        if type(rxp.settings.RefreshProfile) == "function" then
            hooksecurefunc(rxp.settings, "RefreshProfile", OnChange)
        end
        local E = rawget(_G, "EllesmereUI")
        if type(E) == "table" and type(E.RefreshAllAddons) == "function" then
            hooksecurefunc(E, "RefreshAllAddons", OnChange)
        end
    end
    if evaluate then A.Evaluate() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function OnAddonLoaded(name)
    -- RestedXP and the tracker set themselves up in their own handlers for this same event: look once they have run.
    if name == ADDON or name == TRACKER then C_Timer.After(0, function() Attach(loggedIn) end) end
end

local function OnLogin()
    loggedIn = true
    Attach(true)
end

local function OnRegenEnabled()
    if pending then A.Evaluate() end
end

local function FinishStop()
    R:Off("PLAYER_REGEN_ENABLED", FinishStop)
    if not stopPending then return end
    stopPending = false
    if not R:Enabled(KEY) then ReleaseAll() end
end

function A.Stop()
    lastShown, lastProfile = nil, nil
    holdPending, pending, retries = false, false, 0
    if InCombatLockdown() then
        stopPending = true
        R:On("PLAYER_REGEN_ENABLED", FinishStop)
        return
    end
    ReleaseAll()
end

A.feature = Q.Add({
    key = KEY,
    Events = function()
        stopPending = false
        if R.Life and R.Life.loggedIn then
            -- turned on after login: look now
            loggedIn = true
            C_Timer.After(0, function() Attach(true) end)
        end
        return {
            ADDON_LOADED = OnAddonLoaded,
            PLAYER_LOGIN = OnLogin,
            PLAYER_REGEN_ENABLED = OnRegenEnabled,
        }
    end,
    Stop = A.Stop,
})

---------------------------------------------------------------------------
-- What it is doing, for the settings tooltip. Codes: off, restedxp-missing, restedxp-disabled, ellesmere-missing,
-- waiting, unsupported, overridden, held, already-mouseover, watching.
---------------------------------------------------------------------------
function A.Status()
    if not R:Enabled(KEY) then return "off" end
    local addonState = R.Setups and R.Setups.AddonState and R.Setups.AddonState(ADDON)
    if addonState == "missing" then return "restedxp-missing" end
    if addonState == "disabled" then return "restedxp-disabled" end
    if not Ellesmere() then return "ellesmere-missing" end
    if not hooked then
        local loadedNow = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDON)
        return (loadedNow and loggedIn) and "unsupported" or "waiting"
    end
    local active = ActiveProfile()
    local cfg = Settings(active)
    if not cfg then return "waiting" end
    if GuideShown() then
        if Overridden(cfg) then return "overridden" end
        if cfg.visibility == MOUSEOVER then
            return Held()[active] ~= nil and "held" or "already-mouseover"
        end
    end
    return "watching"
end
