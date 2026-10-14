-- TwichUI: Quality of Life, RestedXP destination waypoint
-- Puts the game's own waypoint (its map pin and in-world marker) on the place RestedXP's arrow is
-- leading you to, and moves it on when RestedXP does. Off until turned on. RestedXP's own arrow, map
-- pins, guide content and progress are never changed.
--
-- What RestedXP gives us (RXPGuides v4.11.22 source, not a public interface; checked on every use):
--   Its addon object is registered with AceAddon as "RXPGuides". arrowFrame.element is the guide
--   element its arrow points at, chosen across all active steps (map.lua updateArrowData): it skips
--   finished and lower-priority points and points at your corpse when you are dead. It is set inside
--   UpdateMap(true) and UpdateGotoSteps (about three times a second) and ResetArrowPosition, so those
--   three are hooked, once. The field is not cleared when the arrow hides, so an element is only used
--   when its step is still active and it isn't skipped, hidden or done. An element has zone (a uiMapID)
--   and x, y in percent.
--   A hidden routing point (hidePin: ".goto ...,radius,0" and ".waypoint") stands for the next marked
--   destination in the same step, so the waypoint doesn't hop along a route every few yards. Points
--   RestedXP makes up (generated: corpse, spirit healer, route lines) are never used.
--
-- What the game gives us (WoW: Forever UI source): one user waypoint, shared with the player and every
-- addon (C_Map.SetUserWaypoint / GetUserWaypoint / ClearUserWaypoint, USER_WAYPOINT_UPDATED), and
-- C_SuperTrack.SetSuperTrackedUserWaypoint for the in-world marker.
--
-- The waypoint is the player's first:
--   * It is only placed when the slot is empty or holds the one this placed. A waypoint you placed is
--     never moved or cleared; if you place or clear one while this runs, it is left as you made it and
--     this waits for the next destination with an empty slot.
--   * The in-world marker is pointed at a new destination when it is placed, and not taken back between
--     destinations (RestedXP tracks quests itself, and so may you).
--   * Turning it off, or a destination that is done with nothing after it, clears only its own point.
--   * The point it placed is remembered per character (TwichUIDB.ui.guideWaypoint[guid]), so after a
--     reload it is recognised as this one's and can be moved or cleared.
--   * Nothing is written in combat (the documentation shows no restriction; this is a precaution): a
--     change waits for combat to end.

local R = TwichUI
local Q = R.QoL
local W = {}
R.QoLGuideWaypoint = W

local ADDON = "RXPGuides"
local KEY = "qolGuideWaypoint"
local NEAR = 1e-4   -- in map units (0 to 1): what the game reads back for the same point

local rxp            -- RestedXP's addon object, once found
local hooked = false
local shown = false  -- the element last acted on (false: nothing yet, so the next look always acts)
local shownZone, shownX, shownY
local placedMap, placedX, placedY   -- the waypoint this placed and still owns
local loaded = false -- the remembered point has been read for this character
local writing = false
local pending = false        -- a change waits for combat to end
local stopPending = false    -- turned off in combat: our point is cleared when it ends
local state = "waiting"      -- what Status reports once RestedXP is usable

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
    return type(addon) == "table" and type(addon.UpdateMap) == "function" and type(addon.UpdateGotoSteps) == "function"
        and type(addon.arrowFrame) == "table"
end

local function ClientReady()
    return C_Map and C_Map.SetUserWaypoint and C_Map.GetUserWaypoint and C_Map.ClearUserWaypoint
        and C_Map.CanSetUserWaypointOnMap and UiMapPoint and UiMapPoint.CreateFromCoordinates and true or false
end

local function Done(e)
    local parent = e.parent
    return e.skip or e.hidden or (type(parent) == "table" and (parent.completed or parent.skip)) or false
end

local function HasPlace(e)
    return type(e.zone) == "number" and type(e.x) == "number" and type(e.y) == "number"
        and e.x >= 0 and e.x <= 100 and e.y >= 0 and e.y <= 100
end

-- A hidden routing point: the first marked destination after it in its step, if any.
local function NextMarked(e)
    local list = e.step.elements
    if type(list) ~= "table" then return nil end
    local after = false
    for _, other in ipairs(list) do
        if after then
            if type(other) == "table" and other.arrow and not other.hidePin and not Done(other) and HasPlace(other) then
                return other
            end
        elseif other == e then
            after = true
        end
    end
end

-- The element to mark, or nil and why not.
local function Destination()
    local guide = rxp.currentGuide
    if type(guide) ~= "table" or guide.empty then return nil, "no-guide" end
    local profile = type(rxp.settings) == "table" and rxp.settings.profile
    if type(profile) == "table" and profile.showEnabled == false then return nil, "no-guide" end
    local frame = rxp.arrowFrame
    local e = frame.element
    if type(e) ~= "table" or type(rxp.activeWaypoints) ~= "table" or #rxp.activeWaypoints == 0 then
        return nil, "no-destination"
    end
    -- RestedXP hides its arrow in instances and when nothing is left; on another continent it doesn't
    -- point, but the destination stands.
    if rxp.hideArrow and not frame.wrongContinent then return nil, "no-destination" end
    if type(e.step) ~= "table" or not e.step.active or not e.arrow or Done(e) then return nil, "no-destination" end
    if e.generated and e.generated ~= 0 then return nil, "no-destination" end
    if e.hidePin then
        e = NextMarked(e)
        if not e then return nil, "route" end
    end
    if not HasPlace(e) then return nil, "no-destination" end
    return e
end

---------------------------------------------------------------------------
-- The waypoint
---------------------------------------------------------------------------
local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    return type(ui) == "table" and type(ui.guideWaypoint) == "table" and ui.guideWaypoint or nil
end

local function Remember()
    local guid = UnitGUID and UnitGUID("player")
    if not guid then return end
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.guideWaypoint = Saved() or {}
    TwichUIDB.ui.guideWaypoint[guid] = placedMap and { map = placedMap, x = placedX, y = placedY } or nil
end

-- The point this placed before a reload, once per session.
local function LoadRemembered()
    if loaded then return end
    local guid = UnitGUID and UnitGUID("player")
    if not guid then return end
    loaded = true
    local saved = Saved()
    local p = saved and saved[guid]
    if type(p) == "table" and type(p.map) == "number" and type(p.x) == "number" and type(p.y) == "number" then
        placedMap, placedX, placedY = p.map, p.x, p.y
    end
end

local function Near(a, b) return math.abs(a - b) <= NEAR end

-- Is the waypoint in the slot the one this placed?
local function Ours()
    if not (placedMap and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return false end
    local point = C_Map.GetUserWaypoint()
    local pos = point and point.position
    if point and point.uiMapID == placedMap and pos and Near(pos.x, placedX) and Near(pos.y, placedY) then return true end
    -- the game may keep the point on another map than the one it was given
    pos = C_Map.GetUserWaypointPositionForMap and C_Map.GetUserWaypointPositionForMap(placedMap)
    return pos ~= nil and Near(pos.x, placedX) and Near(pos.y, placedY)
end

local function Forget()
    placedMap, placedX, placedY = nil, nil, nil
    Remember()
end

-- Clears the waypoint if it is still the one this placed.
local function ClearOurs()
    if Ours() then
        writing = true
        C_Map.ClearUserWaypoint()
        if C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint() then
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
        end
        writing = false
    end
    if placedMap then Forget() end
end

local function Place(map, x, y)
    if not C_Map.CanSetUserWaypointOnMap(map) then
        ClearOurs()
        return "map-refused"
    end
    local has = C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()
    if has and not Ours() then
        if placedMap then Forget() end
        return "yours"
    end
    writing = true
    local ok = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
    if ok then
        -- remember what the game kept, which is what it will read back
        local point = C_Map.GetUserWaypoint()
        if point and point.position then
            placedMap, placedX, placedY = point.uiMapID, point.position.x, point.position.y
        else
            placedMap, placedX, placedY = map, x, y
        end
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end
    writing = false
    if not ok then
        if placedMap then Forget() end
        return "map-refused"
    end
    Remember()
    return "shown"
end

---------------------------------------------------------------------------
-- Following RestedXP
---------------------------------------------------------------------------
-- Runs after RestedXP's map and arrow updates. Cheap when nothing changed: a few comparisons.
function W.Sync()
    if not (R:Enabled(KEY) and rxp and hooked) then return end
    local e, why = Destination()
    if e == shown and (e == nil or (e.zone == shownZone and e.x == shownX and e.y == shownY)) then return end
    if InCombatLockdown() then pending = true; return end
    pending = false
    LoadRemembered()
    -- without the character's remembered point, our own waypoint from before a reload would look like the player's
    if not loaded then return end
    shown = e
    if e then
        shownZone, shownX, shownY = e.zone, e.x, e.y
        state = Place(e.zone, e.x / 100, e.y / 100)
    else
        shownZone, shownX, shownY = nil, nil, nil
        ClearOurs()
        state = why
    end
end

local function Attach()
    if not R:Enabled(KEY) then return end
    rxp = rxp or FindRestedXP()
    if not hooked then
        if not (Usable(rxp) and ClientReady()) then return end
        hooked = true
        -- hooked once (a hook can't be removed); Sync does nothing while the feature is off
        hooksecurefunc(rxp, "UpdateMap", W.Sync)
        hooksecurefunc(rxp, "UpdateGotoSteps", W.Sync)
        if type(rxp.ResetArrowPosition) == "function" then hooksecurefunc(rxp, "ResetArrowPosition", W.Sync) end
    end
    W.Sync()
end

local function OnAddonLoaded(name)
    -- RestedXP sets itself up in its own handler for this same event: look once that has run.
    if name == ADDON then C_Timer.After(0, Attach) end
end

-- The slot changed. Our own writes are ignored; anything else is the player's (or another addon's).
local function OnWaypointUpdated()
    if writing or not placedMap then return end
    if not Ours() then
        Forget()
        state = (C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) and "yours" or "cleared"
    end
end

local function OnRegenEnabled()
    if pending then W.Sync() end
end

local function FinishStop()
    R:Off("PLAYER_REGEN_ENABLED", FinishStop)
    if not stopPending then return end
    stopPending = false
    if not R:Enabled(KEY) then ClearOurs() end
end

function W.Stop()
    shown, shownZone, shownX, shownY = false, nil, nil, nil
    pending = false
    if InCombatLockdown() then
        stopPending = true
        R:On("PLAYER_REGEN_ENABLED", FinishStop)
        return
    end
    LoadRemembered()
    ClearOurs()
end

W.feature = Q.Add({
    key = KEY,
    Events = function()
        stopPending = false
        shown = false   -- look again when turned (back) on
        if R.Life and R.Life.loggedIn then C_Timer.After(0, Attach) end
        return {
            ADDON_LOADED = OnAddonLoaded,
            PLAYER_LOGIN = Attach,
            USER_WAYPOINT_UPDATED = OnWaypointUpdated,
            PLAYER_REGEN_ENABLED = OnRegenEnabled,
        }
    end,
    Stop = W.Stop,
})

---------------------------------------------------------------------------
-- What it is doing, for the settings tooltip. Codes: off, restedxp-missing, restedxp-disabled, waiting,
-- unsupported, no-guide, no-destination, route, map-refused, yours, cleared, shown.
---------------------------------------------------------------------------
function W.Status()
    if not R:Enabled(KEY) then return "off" end
    local addonState = R.Setups and R.Setups.AddonState and R.Setups.AddonState(ADDON)
    if addonState == "missing" then return "restedxp-missing" end
    if addonState == "disabled" then return "restedxp-disabled" end
    if not hooked then
        local loggedIn = R.Life and R.Life.loggedIn
        local loadedNow = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ADDON)
        return (loadedNow and loggedIn) and "unsupported" or "waiting"
    end
    return state
end
