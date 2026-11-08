-- TwichUI: Return the Favor in EllesmereUI's Unlock Mode (optional)
-- With the player's choice on ("Use EllesmereUI Unlock Mode", ui.buffBack.unlockMode, off by default) and EllesmereUI
-- installed, one mover named "TwichUI Return the Favor" appears in its Unlock Mode. Dragging, snapping, arrow-key
-- nudging, the X and Y boxes and anchoring to other elements are EllesmereUI's own; nothing is drawn or implemented
-- here. Without it, or with the choice off, the list is moved by dragging its sample (Preview) and nothing here
-- does anything.
--
-- How it is wired (EllesmereUI's public registration API, as FoodDrinkUnlock.lua and nav/Unlock.lua use it:
-- EllesmereUI:RegisterUnlockElements, EllesmereUI.MakeUnlockElement and RegisterUnlockModeListener; none of its
-- private tables is touched):
-- * EllesmereUI moves a small plain stand-in frame as big as the list at its most rows, never the list itself: the
--   list's rows are secure buttons, so nothing protected is anchored to the stand-in. The list follows it out of
--   combat only (List.lua's L.Reposition, from a hook on the stand-in's SetPoint); in combat it waits and goes to
--   wherever the stand-in is when combat ends.
-- * The place is still ui.buffBack.x / y: the list's centre as an offset from the screen's centre. EllesmereUI hands
--   over CENTER/CENTER offsets in screen units (how it saves every element), the same units, so they are stored as
--   they are. Save & Exit saves through Save, a discard puts the old place back through it, and the stand-in is
--   placed from the record, so dragging here, Reset position and EllesmereUI's boxes agree.
-- * Registered once per session and never unregistered: that would delete the player's anchor links in EllesmereUI.
--   The mover is hidden from Unlock Mode (isHidden) while Return the Favor or the choice is off.
-- Nothing runs per frame.

local R = TwichUI
local BB, W = R.BuffBack, R.BuffBackWatch
local U = {}
R.BuffBackUnlock = U

local KEY = "TwichUI_ReturnTheFavor"
local LABEL = "TwichUI Return the Favor"
local GROUP = "TwichUI"
local ORDER = 905

local stand                -- the stand-in EllesmereUI moves: a plain frame with no look of its own
local registered = false
local failed = false
local listening = false
local session = false      -- Unlock Mode is open
local sizeW, sizeH
local placed               -- { x, y } the stand-in was last put at by us
local wasDriving = false

local function Api()
    local e = EllesmereUI
    if type(e) ~= "table" then return nil, "no-eui" end
    if type(e.RegisterUnlockElements) ~= "function" or type(e.MakeUnlockElement) ~= "function" then return nil, "no-api" end
    return e
end

-- The player's choice, with the feature itself on. Explicitly true only.
local function Wanted() return W.Enabled() and BB.Get("unlockMode") == true end

function U.Drives() return registered and stand ~= nil and Wanted() and Api() ~= nil end

-- The stand-in's centre as an offset from the screen's centre, or nil when it isn't in charge.
function U.Offset()
    if not U.Drives() then return nil end
    local cx, cy = stand:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s, us = stand:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (type(cx) == "number" and type(cy) == "number" and type(ux) == "number" and type(uy) == "number"
        and type(s) == "number" and type(us) == "number" and s > 0 and us > 0) then return nil end
    local x, y = (cx * s - ux * us) / us, (cy * s - uy * us) / us
    if BB.ValidOffset(x) and BB.ValidOffset(y) then return x, y end
    return nil
end

local function Footprint()
    local w, h = BB.Footprint()
    local scale = BB.Get("scale") / 100
    return math.max(1, math.floor(w * scale + 0.5)), math.max(1, math.floor(h * scale + 0.5))
end

local function PlaceStand()
    if not stand then return end
    local x, y = BB.Place()
    placed = { x = x, y = y }   -- before SetPoint: its hook may read it
    stand:ClearAllPoints()
    stand:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function OnStandMoved()
    if U.Drives() then
        local L = R.BuffBackList
        if L then L.Reposition() end
    end
end

local function Build()
    if stand then return end
    stand = CreateFrame("Frame", nil, UIParent)
    stand:SetFrameStrata("MEDIUM")
    sizeW, sizeH = Footprint()
    stand:SetSize(sizeW, sizeH)
    PlaceStand()
    hooksecurefunc(stand, "SetPoint", OnStandMoved)
end

function U.Sync()
    if not stand then return end
    local w, h = Footprint()
    if w ~= sizeW or h ~= sizeH then
        sizeW, sizeH = w, h
        stand:SetSize(w, h)
    end
end

---------------------------------------------------------------------------
-- What EllesmereUI calls
---------------------------------------------------------------------------
local function Save(_, point, relPoint, x, y)
    if not U.Drives() then R.Life.Note("buffback-unlock-save-ignored") return end
    if point ~= "CENTER" or (relPoint or point) ~= "CENTER" or not (BB.ValidOffset(x) and BB.ValidOffset(y)) then
        R.Life.Note("buffback-unlock-save-refused")
        return
    end
    BB.SetPlace(x, y)
    if not session then PlaceStand() end
end

local function Load()
    local x, y = BB.Place()
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
end

local function Apply()
    if session or not U.Drives() then return end
    PlaceStand()
end

local function Clear()
    if not U.Drives() then return end
    BB.ResetPlace()
    PlaceStand()
end

local function OnSession(active)
    session = active == true
    U.Sync()
    OnStandMoved()
end

local function Register()
    if registered or failed then return end
    local e = Api()
    if not e then return end
    Build()
    local ok, err = pcall(function()
        e:RegisterUnlockElements({ e.MakeUnlockElement({
            key = KEY, label = LABEL, group = GROUP, order = ORDER,
            noResize = true,
            getFrame = function() return stand end,
            getSize = function() return Footprint() end,
            isHidden = function() return not Wanted() end,
            savePos = Save, loadPos = Load, clearPos = Clear, applyPos = Apply,
        }) })
    end)
    if not ok then
        failed = true
        R.Life.Note("buffback-unlock-register-failed")
        if R.Diag and R.Diag.Error then R.Diag.Error("return the favor unlock", err) end
        return
    end
    registered = true
    if not listening and type(e.RegisterUnlockModeListener) == "function" then
        listening = true
        pcall(e.RegisterUnlockModeListener, e, KEY, OnSession)
    end
end

-- A setting changed, the feature was switched, or EllesmereUI may have appeared. Safe to call any time.
function U.Refresh()
    if Wanted() then Register() end
    U.Sync()
    local now = U.Drives()
    if now and not wasDriving then
        -- just taken over: the stand-in goes to the saved place, then to its own anchor link if it has one
        PlaceStand()
        local e = Api()
        if e and type(e.ReapplyOwnAnchor) == "function" then pcall(e.ReapplyOwnAnchor, KEY) end
    elseif now and not session then
        -- the saved place changed (a profile, Reset position): the stand-in goes there too
        local x, y = BB.Place()
        if not placed or placed.x ~= x or placed.y ~= y then PlaceStand() end
    end
    local changed = now ~= wasDriving
    wasDriving = now
    if changed then
        local L = R.BuffBackList
        if L then L.Reposition() end
    end
end

R:On("ADDON_LOADED", function(name) if name == "EllesmereUI" and Wanted() then U.Refresh() end end)
R:On("PLAYER_LOGIN", function() if Wanted() then U.Refresh() end end)
R:On("PLAYER_ENTERING_WORLD", function() if Wanted() and not registered then U.Refresh() end end)

---------------------------------------------------------------------------
-- For the options page. Read only.
---------------------------------------------------------------------------
-- One stable code: off, no-eui, no-api, waiting, register-failed, module-off, active.
function U.Status()
    if BB.Get("unlockMode") ~= true then return "off" end
    local e, code = Api()
    if not e then return code end
    if failed then return "register-failed" end
    if not W.Enabled() then return "module-off" end
    if not registered then return "waiting" end
    return "active"
end
