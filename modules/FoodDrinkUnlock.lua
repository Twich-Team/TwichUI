-- TwichUI: Food and Drink in EllesmereUI's Unlock Mode (optional)
-- With the player's choice on ("Use EllesmereUI Unlock Mode") and EllesmereUI installed, one anchor
-- named "TwichUI Food & Drink" appears in its Unlock Mode and moves the Food and Drink buttons as a
-- set: its dragging, snapping, arrow-key nudging, X and Y boxes and anchoring to other elements are
-- EllesmereUI's own (nothing is drawn or implemented here). Without it, or with the choice off, the
-- buttons are moved in Edit Mode as before and nothing here does anything.
--
-- How it is wired (all of it in EllesmereUI's public registration API, read from its source:
-- EllesmereUI:RegisterUnlockElements and EllesmereUI.MakeUnlockElement, and its Unlock Mode session
-- listener; nothing of its private tables is touched):
-- * EllesmereUI moves a small plain frame (the anchor), never the secure buttons' parent. Nothing
--   protected is anchored to it, so it can be moved at any time. The buttons' parent follows it, out of
--   combat only (F.Reposition in FoodDrink.lua), so no secure button is changed or moved in combat.
-- * The place is still TwichUIDB.ui.foodDrinkPosition, the centre's offset from the screen centre, the
--   same record Edit Mode writes. EllesmereUI hands over CENTER/CENTER offsets in screen units (this is
--   how it saves every element), which are the same units, so they are stored as they are. Its Save &
--   Exit saves through U.Save, a discard puts the old place back through it, and the anchor is placed
--   from the record, so dragging, the X and Y boxes and Edit Mode's old place agree and nothing
--   accumulates from one session to the next.
-- * While the anchor is in charge, the buttons sit where it is, which is also what makes an anchor
--   made to another element in Unlock Mode work. That anchor link is EllesmereUI's record (in its own
--   saved data), not ours; without EllesmereUI the buttons sit at the last place that was saved.
-- * Registered once per session and never unregistered: unregistering would delete the player's anchor
--   links in EllesmereUI. It is hidden from Unlock Mode instead (isHidden) while the buttons are off.
-- * Combat: Unlock Mode cannot be opened in combat and suspends itself when combat starts, so nothing is
--   dragged then. If the anchor moves in combat anyway (a saved layout applied at a reload, an anchor
--   following its target) the buttons wait and then go to wherever the anchor is when combat ends.
-- Nothing here runs per frame: the anchor's SetPoint is hooked (our own frame), a session's open and
-- close are listened for, and EllesmereUI's callbacks are used for the rest.

local R = TwichUI
local F = R.FoodDrink
local U = {}
F.Unlock = U

local KEY = "TwichUI_FoodDrink"
local LABEL = "TwichUI Food & Drink"
local GROUP = "TwichUI"
local ORDER = 900          -- after the suite's own elements; EllesmereUI sorts by this, then by key

local proxy                -- the anchor EllesmereUI moves: a plain frame, shown, with no look of its own
local registered = false   -- registered with EllesmereUI (once per session)
local failed = false       -- EllesmereUI refused or errored on registration
local listening = false
local session = false      -- Unlock Mode is open (combat suspension does not close it)
local sizeW, sizeH         -- the size the anchor was last given
local wasDriving = false   -- whether the anchor was in charge at the last Refresh

-- The EllesmereUI table when it has what is used here; else nil and a stable code.
local function Api()
    local e = EllesmereUI
    if type(e) ~= "table" then return nil, "no-eui" end
    if type(e.RegisterUnlockElements) ~= "function" or type(e.MakeUnlockElement) ~= "function" then
        return nil, "no-api"
    end
    return e
end

-- The player's choice. Explicitly true only, so a missing value is off.
local function Wanted()
    return TwichUIDB and TwichUIDB.modules and TwichUIDB.modules.foodDrinkUnlock == true
end

-- Whether the anchor is what places the buttons now: chosen, registered, the buttons themselves on,
-- and EllesmereUI still there. Everything that follows the anchor asks this first.
function U.Drives()
    return registered and proxy ~= nil and Wanted() and R:Enabled("foodDrink") and Api() ~= nil
end

-- Whether Unlock Mode should show the anchor: the buttons on and at least one of the two shown. Read
-- live by EllesmereUI each time it builds or syncs its overlays.
local function Visible()
    if not (Wanted() and R:Enabled("foodDrink")) then return false end
    local _, _, shown = F.Footprint()
    return shown > 0
end

---------------------------------------------------------------------------
-- Coordinates. Pure.
---------------------------------------------------------------------------

-- A frame's centre as an offset from the screen's centre, in the screen's units. cx, cy are
-- GetCenter() of the frame, in the frame's own scale; ux, uy are the screen's, in its own.
-- Returns nil for anything unusable, so the saved place is used instead.
function U.OffsetFrom(cx, cy, scale, ux, uy, uscale)
    if not (type(cx) == "number" and type(cy) == "number" and type(ux) == "number" and type(uy) == "number"
        and type(scale) == "number" and type(uscale) == "number" and scale > 0 and uscale > 0) then return nil end
    local x, y = (cx * scale - ux * uscale) / uscale, (cy * scale - uy * uscale) / uscale
    if F.ValidOffset(x) and F.ValidOffset(y) then return x, y end
    return nil
end

-- Where the anchor is, as the offset the buttons' parent is placed at; nil when it is not in charge
-- or has no place yet (FoodDrink.lua then uses the saved place).
function U.Offset()
    if not U.Drives() then return nil end
    local cx, cy = proxy:GetCenter()
    local ux, uy = UIParent:GetCenter()
    return U.OffsetFrom(cx, cy, proxy:GetEffectiveScale(), ux, uy, UIParent:GetEffectiveScale())
end

---------------------------------------------------------------------------
-- The anchor.
---------------------------------------------------------------------------
local function PlaceProxy()
    if not proxy then return end
    local x, y = F.Position()
    proxy:ClearAllPoints()
    proxy:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

-- The buttons' parent follows the anchor. Runs after every SetPoint EllesmereUI makes on it (a drag, a
-- nudge, a typed value, a saved layout, an anchor to another element), so it is small: two GetCenters
-- and, out of combat, one SetPoint.
local function OnProxyMoved()
    if U.Drives() then F.Reposition() end
end

local function BuildProxy()
    if proxy then return proxy end
    proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetFrameStrata("MEDIUM")
    local w, h = F.Footprint()
    sizeW, sizeH = w, h
    proxy:SetSize(w, h)
    PlaceProxy()
    hooksecurefunc(proxy, "SetPoint", OnProxyMoved)
    return proxy
end

-- The anchor is the size of the set, so the outline EllesmereUI draws is the buttons' footprint (from
-- the settings, so it is right with the bags empty or before they have been looked at).
function U.Sync()
    if not proxy then return end
    local w, h = F.Footprint()
    if w ~= sizeW or h ~= sizeH then
        sizeW, sizeH = w, h
        proxy:SetSize(w, h)
    end
end

---------------------------------------------------------------------------
-- What EllesmereUI calls. The element table is the one MakeUnlockElement documents (only those
-- fields reach Unlock Mode). No setWidth or setHeight: the size is the player's look settings, so
-- EllesmereUI shows no size boxes for it.
---------------------------------------------------------------------------

-- EllesmereUI saves one position per element as CENTER/CENTER offsets in screen units. The one record
-- is written, but not when it would not change anything (so a place that was never set stays unset).
function U.Save(_, point, relPoint, x, y)
    if not U.Drives() then
        R.Life.Note("unlock-save-ignored")
        return
    end
    if point ~= "CENTER" or (relPoint or point) ~= "CENTER" or not (F.ValidOffset(x) and F.ValidOffset(y)) then
        R.Life.Note("unlock-save-refused")
        return
    end
    local sx, sy = F.Position()
    if sx ~= x or sy ~= y then F.SetPosition(x, y) end
    -- "persist + apply": outside a session (a profile or layout change) the anchor goes there too. In
    -- one, it is already where the player put it (Save & Exit) or is put back by EllesmereUI (a discard).
    if not session then PlaceProxy() end
end

-- The place, as EllesmereUI wants it: always one (the default when none is saved), so a discarded
-- session has something to go back to.
function U.Load()
    local x, y = F.Position()
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
end

-- EllesmereUI asks for the saved place to be applied to the live frame (login, a profile or layout
-- change). Not during a session, which has unsaved moves of its own.
function U.Apply()
    if session or not U.Drives() then return end
    PlaceProxy()
end

-- Clearing the record puts the buttons back to the default place.
function U.Clear()
    if not U.Drives() then return end
    F.SetPosition(nil)
    PlaceProxy()
end

-- The record was just cleared (F.ResetPosition): the anchor goes back to the default place too.
function U.Reset()
    if U.Drives() then PlaceProxy() end
end

local function OnSession(active)
    session = active == true
    U.Sync()
    OnProxyMoved()   -- once more after a save or discard has finished, whatever was placed last
end

---------------------------------------------------------------------------
-- Registration: once, whenever the pieces are all there. Safe to call any time.
---------------------------------------------------------------------------
local function Register()
    if registered or failed then return end
    local e = Api()
    if not e then return end
    BuildProxy()
    local ok, err = pcall(function()
        e:RegisterUnlockElements({ e.MakeUnlockElement({
            key = KEY, label = LABEL, group = GROUP, order = ORDER,
            noResize = true,
            getFrame = function() return proxy end,
            getSize = function() local w, h = F.Footprint(); return w, h end,
            isHidden = function() return not Visible() end,
            savePos = U.Save, loadPos = U.Load, clearPos = U.Clear, applyPos = U.Apply,
        }) })
    end)
    if not ok then
        failed = true
        R.Life.Note("unlock-register-failed")
        if R.Diag and R.Diag.Error then R.Diag.Error("food unlock", err) end
        return
    end
    registered = true
    if not listening and type(e.RegisterUnlockModeListener) == "function" then
        listening = true
        pcall(e.RegisterUnlockModeListener, e, KEY, OnSession)
    end
end

-- Called by F.Refresh (start-up, a setting changed) and when EllesmereUI may have appeared.
function U.Refresh()
    if Wanted() then Register() end
    U.Sync()
    local now = U.Drives()
    if now and not wasDriving then
        -- Just taken over (turned on, or the buttons came back): the anchor goes to the saved place
        -- first, then to its own anchor link if it has one, so the buttons do not move.
        PlaceProxy()
        local e = Api()
        if e and type(e.ReapplyOwnAnchor) == "function" then pcall(e.ReapplyOwnAnchor, KEY) end
    end
    wasDriving = now
    F.RefreshMover()
    if now then F.Reposition() end
end

local function OnLoaded(name)
    if name == "EllesmereUI" and Wanted() then U.Refresh() end
end
R:On("ADDON_LOADED", OnLoaded)
R:On("PLAYER_LOGIN", function() if Wanted() then U.Refresh() end end)
R:On("PLAYER_ENTERING_WORLD", function() if Wanted() and not registered then U.Refresh() end end)

---------------------------------------------------------------------------
-- For the options page and /tui diagnostics. Read only.
---------------------------------------------------------------------------

-- One stable code: off, no-eui, no-api, waiting, register-failed, module-off, active.
function U.Status()
    if not Wanted() then return "off" end
    local e, code = Api()
    if not e then return code end
    if failed then return "register-failed" end
    if not registered then return "waiting" end
    if not Visible() then return "module-off" end
    return "active"
end

function U.Snapshot()
    local _, apiCode = Api()
    return {
        wanted = Wanted() and true or false, status = U.Status(), api = apiCode or "present",
        registered = registered, failed = failed, built = proxy ~= nil, drives = U.Drives() and true or false,
        visible = Visible() and true or false, session = session, key = KEY,
        owner = U.Drives() and "EllesmereUI anchor" or "TwichUI",
    }
end
