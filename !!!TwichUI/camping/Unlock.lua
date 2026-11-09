-- TwichUI: the camping bar in EllesmereUI's Unlock Mode (optional)
-- With the player's choice on ("Use EllesmereUI Unlock Mode", ui.campingBar.unlockMode, off by default) and EllesmereUI
-- installed, one mover named "TwichUI Camping bar" appears in its Unlock Mode. Dragging, snapping, arrow-key nudging, the X
-- and Y boxes and anchoring to other elements are EllesmereUI's own; nothing is drawn or implemented here. Without it, or
-- with the choice off, the bar is moved in Edit Mode and nothing here does anything.
--
-- How it is wired (EllesmereUI's public registration API, as buffback/Unlock.lua, modules/FoodDrinkUnlock.lua and
-- nav/Unlock.lua use it: EllesmereUI:RegisterUnlockElements, EllesmereUI.MakeUnlockElement and RegisterUnlockModeListener;
-- none of its private tables is touched):
-- * EllesmereUI moves a small plain stand-in frame as big as the bar, never the bar itself: the bar's buttons are secure,
--   so nothing protected is anchored to the stand-in. The bar follows it out of combat only (Bar.lua's C.Reposition, from a
--   hook on the stand-in's SetPoint); in combat it waits and goes to wherever the stand-in is when combat ends.
-- * The place is still ui.campingBarPosition: the bar's centre as an offset from the screen's centre. EllesmereUI hands over
--   CENTER/CENTER offsets in screen units (how it saves every element), the same units, so they are stored as they are.
--   Save & Exit saves through Save, a discard puts the old place back through it, and the stand-in is placed from the
--   record, so dragging here, Reset position and EllesmereUI's boxes agree.
-- * Registered once per session and never unregistered: that would delete the player's anchor links in EllesmereUI. The
--   mover is hidden from Unlock Mode (isHidden) while the bar or the choice is off.
-- Nothing runs per frame.
--
-- The same machinery serves two elements, made by Make(spec): the camping bar ("TwichUI Camping bar") and the Cozy Sleeping
-- Bag's progress bar ("TwichUI Sleeping bag bar", camping/Rest.lua; a plain frame, so it follows its stand-in in combat too).
-- Both follow the one choice, ui.campingBar.unlockMode. spec = { key, label, order, note, wanted(), position(), setPosition(x, y),
-- footprint(), reposition() }.

local R = TwichUI
local C = R.Camping
local GROUP = "TwichUI"

local function Make(spec)
local U = {}
local KEY, LABEL, ORDER = spec.key, spec.label, spec.order

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

-- The player's choice, with the bar itself on. Explicitly true only.
local function Wanted() return R:Enabled("campingBar") and C.Get("unlockMode") == true and spec.wanted() end

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
    if C.ValidOffset(x) and C.ValidOffset(y) then return x, y end
    return nil
end

local function Footprint()
    local w, h = spec.footprint()
    return math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
end

local function PlaceStand()
    if not stand then return end
    local x, y = spec.position()
    placed = { x = x, y = y }   -- before SetPoint: its hook may read it
    stand:ClearAllPoints()
    stand:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

local function OnStandMoved()
    if U.Drives() then spec.reposition() end
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

-- The stand-in follows the bar's size (it changes with what is on the bar).
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
    if not U.Drives() then R.Life.Note(spec.note .. "-save-ignored") return end
    if point ~= "CENTER" or (relPoint or point) ~= "CENTER" or not (C.ValidOffset(x) and C.ValidOffset(y)) then
        R.Life.Note(spec.note .. "-save-refused")
        return
    end
    spec.setPosition(x, y)
    if not session then PlaceStand() end
end

local function Load()
    local x, y = spec.position()
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
end

local function Apply()
    if session or not U.Drives() then return end
    PlaceStand()
end

local function Clear()
    if not U.Drives() then return end
    spec.setPosition(nil)
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
        R.Life.Note(spec.note .. "-register-failed")
        if R.Diag and R.Diag.Error then R.Diag.Error(spec.note, err) end
        return
    end
    registered = true
    if not listening and type(e.RegisterUnlockModeListener) == "function" then
        listening = true
        pcall(e.RegisterUnlockModeListener, e, KEY, OnSession)
    end
end

-- A setting changed, the bar was switched, or EllesmereUI may have appeared. Safe to call any time.
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
        local x, y = spec.position()
        if not placed or placed.x ~= x or placed.y ~= y then PlaceStand() end
    end
    local changed = now ~= wasDriving
    wasDriving = now
    if changed then spec.reposition() end
end

-- The saved place was cleared (Reset position): the stand-in goes back to the default one.
function U.Reset()
    if U.Drives() and not session then PlaceStand() end
end

R:On("ADDON_LOADED", function(name) if name == "EllesmereUI" and Wanted() then U.Refresh() end end)
R:On("PLAYER_LOGIN", function() if Wanted() then U.Refresh() end end)
R:On("PLAYER_ENTERING_WORLD", function() if Wanted() and not registered then U.Refresh() end end)

---------------------------------------------------------------------------
-- For the options page. Read only.
---------------------------------------------------------------------------
-- One stable code: off, no-eui, no-api, waiting, register-failed, module-off, active.
function U.Status()
    if C.Get("unlockMode") ~= true then return "off" end
    local e, code = Api()
    if not e then return code end
    if failed then return "register-failed" end
    if not R:Enabled("campingBar") then return "module-off" end
    if not registered then return "waiting" end
    return "active"
end

return U
end

-- The camping bar's own element (the original: R.CampingUnlock, C.Unlock).
local U = Make({
    key = "TwichUI_CampingBar", label = "TwichUI Camping bar", order = 906, note = "camping-unlock",
    wanted = function() return true end,
    position = function() return C.Position() end,
    setPosition = function(x, y) C.SetPosition(x, y) end,
    footprint = function() return C.Footprint() end,
    reposition = function() return C.Reposition() end,
})
R.CampingUnlock = U
C.Unlock = U

-- The sleeping bag bar's element: wanted while that bar is on.
local RB = R.CampingRest
if RB then
    local UR = Make({
        key = "TwichUI_CampingRest", label = "TwichUI Sleeping bag bar", order = 907, note = "camping-rest-unlock",
        wanted = function() return C.Get("restShow") end,
        position = function() return RB.Position() end,
        setPosition = function(x, y) RB.SetPosition(x, y) end,
        footprint = function() return RB.Footprint() end,
        reposition = function() return RB.Reposition() end,
    })
    R.CampingRestUnlock = UR
    RB.Unlock = UR
end
