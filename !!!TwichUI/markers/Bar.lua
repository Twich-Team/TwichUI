-- TwichUI: marker cycling, the marker bar
-- Holding a modifier key (Shift, Ctrl or Alt, your choice) while you have a target shows a small bar of target
-- markers: click one to mark your target with it, click Remove (or right-click any marker) to take the marker off.
-- Off until turned on. It does what a click on it says and nothing else: nothing is marked by showing it, moving
-- it or opening its settings.
--
-- What the game gives (WoW: Forever UI source) and so how this is built:
--   * SetRaidTarget is restricted; the one way a click marks is Blizzard's secure "raidtarget" button action
--     (SecureTemplates.lua), so each icon is a SecureActionButtonTemplate button: *type1 = raidtarget, action
--     "set", this marker, unit "target"; *type2 and the Remove button use action "clear". A click marks as the
--     button comes up, as the game's own secure buttons do for the mouse.
--   * A protected frame can only be shown, hidden, moved or resized from insecure code out of combat. Showing it
--     in combat is the secure state driver's job (SecureStateDriver.lua: RegisterStateDriver "visibility" with a
--     macro condition, re-evaluated when a modifier key changes and every 0.2 seconds), so the modifier key
--     shows and hides the bar in combat too. Everything else about a bar (its markers, size, look and place) is
--     set out of combat; a change made in combat is saved at once and given to the bar when combat ends, only the
--     latest. B.Pending says so meanwhile.
--   * Two secure bars, so a bar never has to move in combat: "near" follows the target's nameplate and is only
--     allowed to show out of combat; "fixed" sits at the place you choose (draggable) and is the one that shows in
--     combat, always (placement "fixed"), or only if you ask for it. Which of them may show, and when, is just the
--     condition each is driven by (B.Conditions); that is what the "Where" and "In combat" choices are.
--   * The near bar is anchored to the target's nameplate (C_NamePlate.GetNamePlateForUnit("target"); nothing for a
--     nameplate the game forbids addons to touch), so the game moves it with the plate and nothing runs per frame.
--     A nameplate's position may not be something addons can read on this client (the API docs mark GetCenter as secret
--     when a frame's anchoring is), so the bar anchors instead of computing a place from a position it was refused. The anchor is made only while the
--     near bar is shown, which is only ever out of combat, redone when the target or its plate changes, and let go
--     of (back to the fixed place) as the bar hides, so nothing stays attached to a frame the game reuses. With no
--     usable nameplate (nameplates turned off, the target off screen or behind you, a forbidden one, or the game
--     refusing the anchor) the bar is at the fixed place; B.LastPlacement says which, and why, for the settings.
--
-- Saved (the profile's): TwichUIDB.ui.markerBar (B.DEFAULTS), the look TwichUIDB.ui.markerBarStyle (the same choices
-- as the other TwichUI frames: markers/ uses modules/MenuStyle.lua), and the fixed place TwichUIDB.ui.markerBarPosition
-- { x, y } from the middle of the screen (a place; kept on this computer by configuration sharing). Which markers
-- show is a tick per marker (show1 ... show8, by target marker number); their order is the target cycle's order
-- (markers/Markers.lua). Nothing about what is shown right now is saved.

local R = TwichUI
local M = R.Markers
local B = {}
R.MarkerBar = B

local REMOVE_ICON = [[Interface\Buttons\UI-GroupLoot-Pass-Up]]   -- the red cross Blizzard's own pass/remove buttons use
local STRATA = "HIGH"

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
B.MODIFIERS = { { "shift", "Shift" }, { "ctrl", "Ctrl" }, { "alt", "Alt" } }
B.ENUMS = {
    modifier = { shift = true, ctrl = true, alt = true },
    where = { nameplate = true, fixed = true },
    combat = { show = true, hide = true },
    side = { above = true, below = true },
}
B.DEFAULTS = {
    modifier = "shift",     -- the key to hold
    where = "nameplate",    -- "nameplate": near the target's nameplate; "fixed": always at the fixed place
    combat = "show",        -- in combat: "show" it at the fixed place, or "hide" it
    side = "above",         -- above or below the nameplate
    offsetX = 0,            -- from the nameplate's middle, in screen pixels
    offsetY = 24,           -- from its top (above) or bottom (below)
    iconSize = 28,
    spacing = 4,
    scale = 100,            -- percent
    remove = true,          -- a Remove button at the end
}
for id = 1, M.COUNT do B.DEFAULTS["show" .. id] = true end
B.LIMITS = {
    offsetX = { -300, 300 }, offsetY = { -100, 300 },
    iconSize = { 16, 64 }, spacing = { 0, 16 }, scale = { 50, 200 },
}
B.POSITION_DEFAULT = { x = 0, y = 160 }

local function Whole(v) return type(v) == "number" and v == v and v % 1 == 0 and v > -math.huge and v < math.huge end

function B.Valid(key, value)
    local enum = B.ENUMS[key]
    if enum then return type(value) == "string" and enum[value] == true end
    local lim = B.LIMITS[key]
    if lim then return Whole(value) and value >= lim[1] and value <= lim[2] end
    if key == "remove" or (type(key) == "string" and key:find("^show%d$") and B.DEFAULTS[key] ~= nil) then
        return type(value) == "boolean"
    end
    return false
end

-- The look: the same choices as TwichUI's other frames (modules/MenuStyle.lua), saved apart.
B.Style = R.MenuStyle.New("markerBarStyle", {
    bgTexture = "solid", bgColor = "ff1f1812", bgOpacity = 92,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
})

local listeners = {}
-- fn(what): what = "config" (settings or look changed), "position" or "state" (applied, pending or previewing changed).
function B.OnState(fn)
    for _, existing in ipairs(listeners) do if existing == fn then return end end
    listeners[#listeners + 1] = fn
end
local function Notify(what)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("marker bar", err) end
    end
end

function B.Get(key)
    local ui = TwichUIDB and TwichUIDB.ui
    local t = type(ui) == "table" and ui.markerBar
    local value
    if type(t) == "table" then value = t[key] end   -- not "and ... or": a saved false is a value
    if B.Valid(key, value) then return value end
    return B.DEFAULTS[key]
end

local Apply   -- (below)

function B.Set(key, value)
    if B.DEFAULTS[key] == nil or not B.Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.markerBar) ~= "table" then TwichUIDB.ui.markerBar = {} end
    if TwichUIDB.ui.markerBar[key] == value then return true end   -- unchanged: nothing to redo
    TwichUIDB.ui.markerBar[key] = value
    Apply()
    return true
end

-- Puts back every bar setting (not the look, not the fixed place).
function B.ResetSettings()
    if TwichUIDB and type(TwichUIDB.ui) == "table" and TwichUIDB.ui.markerBar ~= nil then
        TwichUIDB.ui.markerBar = nil
        Apply()
    end
end

function B.Position()
    local ui = TwichUIDB and TwichUIDB.ui
    local p = type(ui) == "table" and ui.markerBarPosition
    local function Offset(n) return type(n) == "number" and n == n and n > -5000 and n < 5000 end
    if type(p) == "table" and Offset(p.x) and Offset(p.y) then return p.x, p.y end
    return B.POSITION_DEFAULT.x, B.POSITION_DEFAULT.y
end

function B.SetPosition(x, y)
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y or math.abs(x) >= 5000 or math.abs(y) >= 5000 then return false end
    if type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local old = TwichUIDB.ui.markerBarPosition
    if type(old) == "table" and old.x == x and old.y == y then return true end
    TwichUIDB.ui.markerBarPosition = { x = x, y = y }
    Apply()
    Notify("position")
    return true
end

function B.ResetPosition()
    if TwichUIDB and type(TwichUIDB.ui) == "table" and TwichUIDB.ui.markerBarPosition ~= nil then
        TwichUIDB.ui.markerBarPosition = nil
        Apply()
        Notify("position")
    end
    return true
end

-- What is on the bar, in order: target marker numbers, then 0 for the Remove button. The order is the target
-- cycle's; a marker you turned off for the cycle can still be on the bar, and the other way round.
function B.Items()
    local list = {}
    for _, id in ipairs(M.Order("target")) do
        if B.Get("show" .. id) then list[#list + 1] = id end
    end
    if B.Get("remove") then list[#list + 1] = 0 end
    return list
end

-- The macro conditions the two bars are shown by (a driver "visibility" string), or "hide": the whole of what
-- "Where" and "In combat" mean.
function B.Conditions()
    local base = "@target,exists,mod:" .. B.Get("modifier")
    local near, fixed = "hide", "hide"
    if B.Get("where") == "nameplate" then
        near = "[nocombat," .. base .. "] show; hide"
        if B.Get("combat") == "show" then fixed = "[combat," .. base .. "] show; hide" end
    elseif B.Get("combat") == "show" then
        fixed = "[" .. base .. "] show; hide"
    else
        fixed = "[nocombat," .. base .. "] show; hide"
    end
    return near, fixed
end

---------------------------------------------------------------------------
-- The frames
---------------------------------------------------------------------------
local function InCombat() return InCombatLockdown and InCombatLockdown() end

local function Readable(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
local function Num(v)
    v = Readable(v)
    if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    return v
end

local bars = {}        -- near, fixed (secure), preview (not)
local built = false
local pending = false

local function Tip(button, id)
    R.Interact.Tip(button, id == 0 and "Remove marker" or M.Name("target", id), function()
        if id == 0 then return "Click to take the marker off your target." end
        return "Click to mark your target with the " .. M.Name("target", id) .. ". Right-click to remove your target's marker."
    end)
end

local function NewButton(bar, id)
    local secure = bar.secure
    local b = CreateFrame("Button", secure and (bar.name .. "Marker" .. id) or nil, bar.root,
        secure and "SecureActionButtonTemplate" or nil)
    b.id = id
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(id == 0 and REMOVE_ICON or M.Texture("target", id))
    local hot = b:CreateTexture(nil, "HIGHLIGHT")
    hot:SetAllPoints()
    hot:SetColorTexture(1, 1, 1, 0.16)
    -- the marker your target wears now: a thin ring (a color and a shape, so it isn't color alone)
    local c = R.Look.pal.tealHi
    b.ring = R.Look.Shade(b, { c, 1 }, { c, 1 }, { c, 1 }, { c, 1 }, 0, "OVERLAY")
    for _, line in pairs(b.ring) do line:Hide() end
    if secure then
        b:RegisterForClicks("AnyUp")
        -- Act as the mouse button comes up, whatever the game's "cast on key down" setting: SecureActionButton_OnClick acts
        -- on the press edge when that setting is on (and a mouse click on an addon's button is treated as a key press),
        -- so without this a button registered for the release does nothing (as the refreshments panel's buttons do).
        b:SetAttribute("useOnKeyDown", false)
        b:SetAttribute("unit", "target")
        b:SetAttribute("*type1", "raidtarget")
        b:SetAttribute("*type2", "raidtarget")
        b:SetAttribute("*action2", "clear")
        if id == 0 then
            b:SetAttribute("*action1", "clear")
        else
            b:SetAttribute("*action1", "set")
            b:SetAttribute("*marker1", id)
        end
        Tip(b, id)
    else
        b:EnableMouse(false)   -- the preview's buttons do nothing; the bar behind them takes the drag
    end
    return b
end

local function NewBar(name, secure)
    local root = CreateFrame("Frame", name, UIParent, (secure and "SecureHandlerStateTemplate," or "") .. "BackdropTemplate")
    root:SetFrameStrata(STRATA)
    root:EnableMouse(true)   -- the bar's own padding doesn't pass a click through to the world behind it
    root:Hide()
    local bar = { root = root, name = name, secure = secure, buttons = {} }
    for id = 0, M.COUNT do bar.buttons[id] = NewButton(bar, id) end
    return bar
end

-- Sizes, places and fills a bar from the settings and the look. Secure bars: out of combat only (the caller checks).
local function Layout(bar)
    local items = B.Items()
    local size, gap = B.Get("iconSize"), B.Get("spacing")
    -- The scale first: the look is drawn at the frame's scale as it is when this runs (an EllesmereUI border and the
    -- pixel sizes are worked out from it), so a scale set afterwards leaves the border drawn for the old one. The
    -- padding clears the border's line, not its whole cell (MenuStyle.ApplyInset).
    bar.root:SetScale(B.Get("scale") / 100)
    local edge = B.Style.ApplyInset(bar.root)
    local pad = math.max(6, math.ceil(edge) + 3)
    local used = {}
    for i, id in ipairs(items) do
        local b = bar.buttons[id]
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("LEFT", bar.root, "LEFT", pad + (i - 1) * (size + gap), 0)
        b:Show()
        used[id] = true
    end
    for id = 0, M.COUNT do
        if not used[id] then bar.buttons[id]:Hide() end
    end
    local n = #items
    bar.width = pad * 2 + n * size + math.max(0, n - 1) * gap
    bar.height = pad * 2 + size
    bar.root:SetSize(bar.width, bar.height)
    bar.count = n
    bar.placed = nil
end

-- The ring on the marker the target wears. Only readable values are used (the game may keep the answer secret).
local function Highlight(bar)
    local current
    local ok, index = pcall(GetRaidTargetIndex, "target")
    if ok then current = Num(index) end
    for id = 1, M.COUNT do
        local on = current == id
        for _, line in pairs(bar.buttons[id].ring) do line:SetShown(on) end
    end
end

local function PlaceFixed(bar)
    local x, y = B.Position()
    local s = bar.root:GetScale()
    if not s or s <= 0 then s = 1 end
    bar.root:ClearAllPoints()
    bar.root:SetPoint("CENTER", UIParent, "CENTER", x / s, y / s)
    bar.placed = "fixed"
end

---------------------------------------------------------------------------
-- Sitting on the nameplate (the near bar, shown and out of combat only)
---------------------------------------------------------------------------
-- Why the near bar was at the fixed place instead (shown in the settings, so a bar in the wrong place can be explained).
B.WHY = {
    none = "your target has no nameplate (nameplates turned off, or it is out of range or off screen)",
    forbidden = "the game doesn't let addons use that nameplate",
    lookup = "the game refused the nameplate lookup for your target",
    refused = "the game wouldn't attach the bar to that nameplate",
    api = "this client has no nameplate calls",
    combat = "you were in combat",
    chosen = "you chose the fixed place",
}
local last   -- where the bar was the last time it appeared this session: { where = "nameplate" | "fixed", why = code }

-- Remembers it, and tells whatever shows it only when it changed.
local function Remember(where, why)
    if last and last.where == where and last.why == why then return end
    last = { where = where, why = why }
    Notify("state")
end
function B.LastPlacement()
    if not last then return nil end
    return last.where, last.why
end

-- The nameplate of your target, or nil and why.
local function TargetPlate()
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil, "api" end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
    if not ok then return nil, "lookup" end
    if not plate then return nil, "none" end
    local good, forbidden = pcall(function() return plate.IsForbidden and plate:IsForbidden() end)
    if not good or forbidden then return nil, "forbidden" end
    return plate
end

-- Anchors the near bar to your target's nameplate (the game moves the plate, so nothing follows it per frame; a
-- nameplate's position may not be readable by addons here: the API docs mark GetCenter as secret when a frame's
-- anchoring is), or puts it at the fixed place when there is none. Out of combat only: a protected frame's
-- anchors can't change in combat, and the near bar is never shown then.
local function PlaceNear(bar)
    if InCombat() then return end
    local plate, why = TargetPlate()
    if not plate then
        if bar.placed ~= "fixed" then PlaceFixed(bar) end
        Remember("fixed", why)
        return
    end
    local s = bar.root:GetScale()
    if not s or s <= 0 then s = 1 end
    local above = B.Get("side") == "above"
    local x, y = B.Get("offsetX"), B.Get("offsetY")
    local key = table.concat({ tostring(plate), above and "a" or "b", x, y, s }, ":")
    if bar.placed ~= key then
        bar.root:ClearAllPoints()
        local ok = pcall(bar.root.SetPoint, bar.root, above and "BOTTOM" or "TOP", plate, above and "TOP" or "BOTTOM", x / s, (above and y or -y) / s)
        if not ok then
            PlaceFixed(bar)
            Remember("fixed", "refused")
            return
        end
        bar.placed = key
    end
    Remember("nameplate")
end

-- Events run only while a bar is shown.
local function OnMarkersChanged()
    for _, key in ipairs({ "near", "fixed" }) do
        local bar = bars[key]
        if bar and bar.root:IsShown() then Highlight(bar) end
    end
end
local function OnTargetChanged()
    OnMarkersChanged()
    if bars.near and bars.near.root:IsShown() then PlaceNear(bars.near) end
end
-- A nameplate that goes away may still be the target's for the rest of the event, so look again a moment later.
local function OnPlateRemoved()
    OnTargetChanged()
    C_Timer.After(0.1, function()
        if bars.near and bars.near.root:IsShown() then PlaceNear(bars.near) end
    end)
end

local watching = false
local function Watch()
    local any = false
    for _, key in ipairs({ "near", "fixed" }) do
        local bar = bars[key]
        if bar and bar.root:IsShown() then any = true end
    end
    if any and not watching then
        watching = true
        R:On("PLAYER_TARGET_CHANGED", OnTargetChanged)
        R:On("RAID_TARGET_UPDATE", OnMarkersChanged)
        R:On("NAME_PLATE_UNIT_ADDED", OnTargetChanged)
        R:On("NAME_PLATE_UNIT_REMOVED", OnPlateRemoved)
    elseif not any and watching then
        watching = false
        R:Off("PLAYER_TARGET_CHANGED", OnTargetChanged)
        R:Off("RAID_TARGET_UPDATE", OnMarkersChanged)
        R:Off("NAME_PLATE_UNIT_ADDED", OnTargetChanged)
        R:Off("NAME_PLATE_UNIT_REMOVED", OnPlateRemoved)
    end
end

local function OnShown(bar)
    Highlight(bar)
    if bar == bars.near then
        PlaceNear(bar)
    else
        Remember("fixed", B.Get("where") == "nameplate" and "combat" or "chosen")
    end
    Watch()
end

-- Hidden: the near bar lets go of the nameplate (out of combat), so nothing stays attached to a frame the game reuses.
local function OnHidden(bar)
    if bar == bars.near and not InCombat() and bar.placed ~= "fixed" then PlaceFixed(bar) end
    Watch()
end

function B.Build()
    if built then return true end
    if InCombat() or not (CreateFrame and RegisterStateDriver) then return false end
    for _, spec in ipairs({ { "near", "TwichUIMarkerBarNear" }, { "fixed", "TwichUIMarkerBarFixed" } }) do
        local bar = NewBar(spec[2], true)
        bars[spec[1]] = bar
        bar.root:HookScript("OnShow", function() OnShown(bar) end)
        bar.root:HookScript("OnHide", function() OnHidden(bar) end)
    end
    built = true
    return true
end

---------------------------------------------------------------------------
-- Applying the settings (out of combat; in combat the latest waits)
---------------------------------------------------------------------------
local function Drive(bar, cond)
    if bar.cond == cond then return end
    bar.cond = cond
    if cond == "hide" then
        if bar.driven then UnregisterStateDriver(bar.root, "visibility") end
        bar.driven = false
        bar.root:Hide()
    else
        RegisterStateDriver(bar.root, "visibility", cond)
        bar.driven = true
    end
end

local preview
local function RefreshPreview()
    if preview and preview.root:IsShown() then
        Layout(preview)
        PlaceFixed(preview)
    end
end

local waiting = false
local OnRegenEnabled
local function WaitForCombat()
    if waiting then return end
    waiting = true
    R.Life.Note("deferred-combat")
    R:On("PLAYER_REGEN_ENABLED", OnRegenEnabled)
end

function Apply()
    local on = R:Enabled("markersBar")
    if not on and not built then
        RefreshPreview()
        Notify("config")
        return
    end
    if InCombat() then
        pending = true
        WaitForCombat()
        Notify("state")
        return
    end
    pending = false
    if on and not B.Build() then return end
    if built then
        local near, fixed = "hide", "hide"
        if on then near, fixed = B.Conditions() end
        for _, key in ipairs({ "near", "fixed" }) do
            local bar = bars[key]
            Layout(bar)
            PlaceFixed(bar)
            if bar.root:IsShown() then OnShown(bar) end
        end
        Drive(bars.near, near)
        Drive(bars.fixed, fixed)
    end
    RefreshPreview()
    Notify("config")
end

function OnRegenEnabled()
    waiting = false
    R:Off("PLAYER_REGEN_ENABLED", OnRegenEnabled)
    Apply()
end

function B.Refresh() Apply() end   -- Switches.lua
B.Apply = Apply

function B.Built() return built end
-- A change made in combat is saved but the bar still has what it had.
function B.Pending() return pending end
function B.Bars() return bars, preview end

---------------------------------------------------------------------------
-- The preview: an ordinary copy of the bar at the fixed place, drawn from the settings and the look, which can
-- be dragged to move the fixed place. It marks and removes nothing. Out of combat only (it closes as combat starts).
---------------------------------------------------------------------------
local function SavePreviewPosition()
    local root = preview.root
    local cx, cy = root:GetCenter()
    local px, py = UIParent:GetCenter()
    local es, ues = root:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not (cx and cy and px and py and es and ues and ues > 0) then return end
    B.SetPosition(cx * es / ues - px, cy * es / ues - py)
    PlaceFixed(preview)
end

function B.Previewing() return preview ~= nil and preview.root:IsShown() end

local function HidePreviewForCombat() B.ShowPreview(false) end

function B.ShowPreview(on)
    if on then
        if InCombat() then return false, "combat" end
        if not preview then
            preview = NewBar("TwichUIMarkerBarPreview", false)
            local root = preview.root
            root:SetMovable(true)
            root:SetClampedToScreen(true)
            root:RegisterForDrag("LeftButton")
            root:SetScript("OnDragStart", function(self) if not InCombat() then self:StartMoving() end end)
            root:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                SavePreviewPosition()
            end)
        end
        Layout(preview)
        PlaceFixed(preview)
        preview.root:Show()
        R:On("PLAYER_REGEN_DISABLED", HidePreviewForCombat)
    elseif preview and preview.root:IsShown() then
        preview.root:StopMovingOrSizing()
        preview.root:Hide()
        R:Off("PLAYER_REGEN_DISABLED", HidePreviewForCombat)
    else
        return true
    end
    Notify("state")
    return true
end

function B.TogglePreview() return B.ShowPreview(not B.Previewing()) end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
B.Style.Subscribe(function() Apply() end)
M.OnChange(function(kind) if kind == nil or kind == "target" then Apply() end end)   -- the cycle's order is the bar's
R:OnInit(function() Apply() end)
-- TwichUI loads before the other addons, so at that first draw an EllesmereUI border in the saved look (or a
-- LibSharedMedia one another addon registers) can't be found yet and the look falls back to a plain line at the saved
-- thickness: a thick white one. Draw the bar again once every addon has loaded.
R:On("PLAYER_LOGIN", function() if built or R:Enabled("markersBar") then Apply() end end)
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("views", "markerBar", function() Apply() end)
end
