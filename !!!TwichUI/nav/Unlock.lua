-- TwichUI: Navigation in EllesmereUI's Unlock Mode (optional)
-- With the player's choice on ("Use EllesmereUI Unlock Mode", ui.navigation.unlockMode, off by default) and EllesmereUI
-- installed, two movers appear in its Unlock Mode: "TwichUI Navigation" (the frame) and "TwichUI Navigation Arrow" (the
-- arrow on its own). Dragging, snapping, arrow-key nudging, the X and Y boxes and anchoring to other elements are
-- EllesmereUI's own; nothing is drawn or implemented here. Without it, or with the choice off, the frame and arrow are
-- dragged while unlocked as before and nothing here does anything.
--
-- How it is wired (EllesmereUI's public registration API, as FoodDrinkUnlock.lua uses it: EllesmereUI:RegisterUnlockElements,
-- EllesmereUI.MakeUnlockElement and RegisterUnlockModeListener; none of its private tables is touched):
-- * EllesmereUI moves a small plain stand-in frame for each, never the frame or arrow themselves: those are built only while
--   a route is followed, so there would be nothing to move the rest of the time. While the stand-in is in charge, the frame
--   (or the arrow) is centred on it, so they follow it at once with no hook and no per-frame work. Nothing here is secure.
-- * The place is still ui.navigation.position / arrowPosition: the centre's offset from the screen's centre. EllesmereUI
--   hands over CENTER/CENTER offsets in screen units (this is how it saves every element), the same units, so they are
--   stored as they are. Save & Exit saves through Save, a discard puts the old place back through it, and the stand-in is
--   placed from the record, so dragging here, Reset position in the settings and EllesmereUI's boxes agree.
-- * The stand-in is as big as the thing it stands for (scale applied). The arrow's is a fixed shape; the frame's height is the
--   frame's own once it has been laid out, else a typical three-line frame's, so its outline can be a little off until a
--   route has been followed once.
-- * Registered once per session and never unregistered: that would delete the player's anchor links in EllesmereUI. A mover
--   is hidden from Unlock Mode (isHidden) while navigation, the frame or the arrow is off, or the arrow sits in the frame.
-- * While EllesmereUI is in charge, dragging the frame or arrow in the game is off, so there is one owner of the place.
-- Nothing runs per frame: the stand-ins' sizes are read when the frame lays out or a preference changes.

local R = TwichUI
local NV, NP = R.Nav, R.NavPrefs
local NU = {}
R.NavUnlock = NU

local GROUP = "TwichUI"
local OWNER = "TwichUI_Navigation"
local KINDS = { "frame", "arrow" }
local INFO = {
    frame = { key = "TwichUI_NavFrame", label = "TwichUI Navigation", order = 910, pref = "position" },
    arrow = { key = "TwichUI_NavArrow", label = "TwichUI Navigation Arrow", order = 911, pref = "arrowPosition" },
}
local FRAME_TOP, ARROW_UP = 140, 220    -- the default places (Frame.lua, Arrow.lua), in screen units from the top / centre

local stand = {}               -- kind -> the stand-in EllesmereUI moves: a plain frame with no look of its own
local placed = {}              -- kind -> { x, y } the stand-in was last put at by us
local sized = {}               -- kind -> { w, h } it was last given
local driving = {}             -- kind -> whether it was in charge at the last Refresh
local registered = false       -- registered with EllesmereUI (once per session)
local failed = false           -- EllesmereUI refused or errored on registration
local listening = false
local session = false          -- Unlock Mode is open (combat suspension does not close it)

-- The EllesmereUI table when it has what is used here; else nil and a stable code.
local function Api()
    local e = EllesmereUI
    if type(e) ~= "table" then return nil, "no-eui" end
    if type(e.RegisterUnlockElements) ~= "function" or type(e.MakeUnlockElement) ~= "function" then return nil, "no-api" end
    return e
end

-- The player's choice, with navigation itself on. Explicitly true only.
local function Wanted() return NV.Enabled() and NP.Get("unlockMode") == true end

-- Whether a mover is worth showing: the thing it moves is shown somewhere of its own.
local function Shown(kind)
    if kind == "frame" then return NP.Get("frame") end
    return NP.Get("arrow") and not (NP.Get("arrowAttached") and NP.Get("frame"))
end

-- Whether the stand-in is what places the frame / arrow now. Everything that follows it asks this first.
function NU.Drives(kind)
    return registered and stand[kind] ~= nil and Wanted() and Api() ~= nil
end

-- The stand-in to centre on, or nil when EllesmereUI is not in charge (the saved place is used).
function NU.Anchor(kind)
    if NU.Drives(kind) then return stand[kind] end
    return nil
end

---------------------------------------------------------------------------
-- Size and place
---------------------------------------------------------------------------
local function Footprint(kind)
    local m = kind == "frame" and R.NavFrame or R.NavArrow
    local w, h = 100, 60
    if m and m.Footprint then w, h = m.Footprint() end
    return math.max(1, math.floor(w + 0.5)), math.max(1, math.floor(h + 0.5))
end

-- The place as the centre's offset from the screen's centre: the saved one, else the default's.
local function Position(kind)
    local p = NP.Get(INFO[kind].pref)
    if p then return p.x, p.y, true end
    if kind == "arrow" then return 0, ARROW_UP, false end
    local _, h = Footprint("frame")
    return 0, (UIParent:GetHeight() or 0) / 2 - FRAME_TOP - h / 2, false
end

local function PlaceStand(kind)
    local s = stand[kind]
    if not s then return end
    local x, y = Position(kind)
    s:ClearAllPoints()
    s:SetPoint("CENTER", UIParent, "CENTER", x, y)
    placed[kind] = { x = x, y = y }
end

local function Build(kind)
    if stand[kind] then return stand[kind] end
    local s = CreateFrame("Frame", nil, UIParent)
    s:SetFrameStrata("MEDIUM")
    stand[kind] = s
    local w, h = Footprint(kind)
    sized[kind] = { w = w, h = h }
    s:SetSize(w, h)
    PlaceStand(kind)
    return s
end

-- The stand-ins are as big as what they stand for. Called when the frame lays out and when a preference changes; does
-- nothing when the size is the same. A frame with no saved place keeps its top at the default height as it grows.
function NU.Sync()
    for _, kind in ipairs(KINDS) do
        local s = stand[kind]
        if s then
            local w, h = Footprint(kind)
            local was = sized[kind]
            if not was or was.w ~= w or was.h ~= h then
                sized[kind] = { w = w, h = h }
                s:SetSize(w, h)
                local _, _, saved = Position(kind)
                if not saved and not session then PlaceStand(kind) end
            end
        end
    end
end

---------------------------------------------------------------------------
-- What EllesmereUI calls. The element table is the one MakeUnlockElement documents (only those fields reach Unlock
-- Mode). No setWidth or setHeight: the size is the player's frame and arrow scale, so there are no size boxes.
---------------------------------------------------------------------------
local function Same(a, b) return math.abs(a - b) < 0.01 end

-- EllesmereUI saves one position per element as CENTER/CENTER offsets in screen units. The one record is written, but
-- not when it would not change anything (so a place that was never set stays unset).
local function Save(kind, point, relPoint, x, y)
    if not NU.Drives(kind) then
        R.Life.Note("nav-unlock-save-ignored")
        return
    end
    if point ~= "CENTER" or (relPoint or point) ~= "CENTER" or not NP.Valid("position", { x = x, y = y }) then
        R.Life.Note("nav-unlock-save-refused")
        return
    end
    local sx, sy = Position(kind)
    placed[kind] = { x = x, y = y }       -- before the write: the preference's announcement then finds nothing to move
    if not (Same(sx, x) and Same(sy, y)) then NP.Set(INFO[kind].pref, { x = x, y = y }) end
    -- "persist + apply": outside a session (a profile or layout change) the stand-in goes there too. In one, it is
    -- already where the player put it (Save & Exit) or is put back by EllesmereUI (a discard).
    if not session then PlaceStand(kind) end
end

-- The place, as EllesmereUI wants it: always one (the default when none is saved), so a discarded session has
-- something to go back to.
local function Load(kind)
    local x, y = Position(kind)
    return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
end

-- EllesmereUI asks for the saved place to be applied to the live frame (login, a profile or layout change). Not during a
-- session, which has unsaved moves of its own.
local function Apply(kind)
    if session or not NU.Drives(kind) then return end
    PlaceStand(kind)
end

-- Clearing the record puts the frame / arrow back at the default place.
local function Clear(kind)
    if not NU.Drives(kind) then return end
    NP.Clear(INFO[kind].pref)
    PlaceStand(kind)
end

local function OnSession(active)
    session = active == true
    NU.Sync()
end

---------------------------------------------------------------------------
-- Registration: once, whenever the pieces are all there. Safe to call any time.
---------------------------------------------------------------------------
local function Element(e, kind)
    local info = INFO[kind]
    return e.MakeUnlockElement({
        key = info.key, label = info.label, group = GROUP, order = info.order,
        noResize = true,
        getFrame = function() return stand[kind] end,
        getSize = function() return Footprint(kind) end,
        isHidden = function() return not (Wanted() and Shown(kind)) end,
        savePos = function(_, ...) return Save(kind, ...) end,
        loadPos = function() return Load(kind) end,
        clearPos = function() return Clear(kind) end,
        applyPos = function() return Apply(kind) end,
    })
end

local function Register()
    if registered or failed then return end
    local e = Api()
    if not e then return end
    for _, kind in ipairs(KINDS) do Build(kind) end
    local ok, err = pcall(function()
        e:RegisterUnlockElements({ Element(e, "frame"), Element(e, "arrow") })
    end)
    if not ok then
        failed = true
        R.Life.Note("nav-unlock-register-failed")
        if R.Diag and R.Diag.Error then R.Diag.Error("navigation unlock", err) end
        return
    end
    registered = true
    if not listening and type(e.RegisterUnlockModeListener) == "function" then
        listening = true
        pcall(e.RegisterUnlockModeListener, e, OWNER, OnSession)
    end
end

-- Called when a preference changed or EllesmereUI may have appeared. announce: tell the views to place themselves again
-- (not needed from a preference change: they are told by the same announcement, after this).
function NU.Refresh(announce)
    if Wanted() then Register() end
    NU.Sync()
    local e = Api()
    local changed = false
    for _, kind in ipairs(KINDS) do
        local now = NU.Drives(kind)
        if now and not driving[kind] then
            -- Just taken over (turned on, or EllesmereUI came): the stand-in goes to the saved place first, then to its own
            -- anchor link if it has one, so the frame and arrow do not move.
            PlaceStand(kind)
            if e and type(e.ReapplyOwnAnchor) == "function" then pcall(e.ReapplyOwnAnchor, INFO[kind].key) end
        elseif now and not session then
            -- the saved place changed (a profile, Reset position): the stand-in goes there too
            local x, y = Position(kind)
            local was = placed[kind]
            if not was or not (Same(was.x, x) and Same(was.y, y)) then PlaceStand(kind) end
        end
        if now ~= (driving[kind] or false) then changed = true end
        driving[kind] = now
    end
    if changed and announce then NP.Notify("unlockMode") end
end

NV.Subscribe(function(event)
    if event == "prefs" then NU.Refresh(false) end
end)
R:On("ADDON_LOADED", function(name) if name == "EllesmereUI" and Wanted() then NU.Refresh(true) end end)
R:On("PLAYER_LOGIN", function() if Wanted() then NU.Refresh(true) end end)
R:On("PLAYER_ENTERING_WORLD", function() if Wanted() and not registered then NU.Refresh(true) end end)

---------------------------------------------------------------------------
-- For the options page. Read only.
---------------------------------------------------------------------------

-- One stable code: off, no-eui, no-api, waiting, register-failed, module-off, active.
function NU.Status()
    if NP.Get("unlockMode") ~= true then return "off" end
    local e, code = Api()
    if not e then return code end
    if failed then return "register-failed" end
    if not NV.Enabled() then return "module-off" end
    if not registered then return "waiting" end
    return "active"
end
