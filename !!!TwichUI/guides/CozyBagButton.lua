-- TwichUI: Cozy Sleeping Bag guide, the launcher button
-- A small button that opens the guide while the bag is available to this character and not yet got (guides/CozyBagOffer.lua
-- decides that). The sleeping-bag artwork on a dark ground with a thin bronze outline, optionally with a short name; it does
-- not glow, pulse or move. Left-click opens the guide (CozyBagOffer.OpenGuide); right-click offers Open guide, Move and
-- Hide button. Opening the guide neither completes nor dismisses anything: the button steps aside while the guide is open and
-- returns when it closes.
--
-- Moving: only in move mode (the menu's Move, or the settings page). In move mode the button can be dragged and a click
-- does nothing, so a drag can never be taken for a click; leave it with Done in the menu or the settings page, in combat, or
-- by hiding it. Out of move mode the button cannot be dragged at all. The place is kept as an offset from the screen's
-- centre (TwichUIDB.ui.cozyBagButton.x/.y, in the profile, kept on this computer when sharing), held on screen, and
-- placed again when the UI scale or the display changes.
--
-- Appearance (TwichUIDB.ui.cozyBagButton: label, size, opacity) is the profile's. Nothing here is a protected action: a plain
-- Button, so it can be clicked and moved out of combat or in. The frame is made once, the first time it is wanted.

local R = TwichUI
local D = R.CozyBagData
local O = R.CozyBagOffer
local B = {}
R.CozyBagButton = B

B.DEFAULTS = { label = "icon", size = 36, opacity = 100 }
B.LIMITS = { size = { 24, 64 }, opacity = { 30, 100 } }
B.ENUM = { label = { icon = true, name = true } }
B.CHOICES = { { "icon", "Icon only" }, { "name", "Icon and name" } }

local NAME = "Sleeping Bag"
local EDGE_PAD = 3                   -- ground between the outline and the artwork
local PREVIEW_SECONDS = 30
local POSITION_LIMIT = 8192
local FALLBACK = {
    text = { 0.93, 0.88, 0.76 }, stone = { 0.62, 0.58, 0.51 }, bronze = { 0.55, 0.43, 0.22 },
    gold = { 0.79, 0.64, 0.29 }, bg = { 0.150, 0.115, 0.082 },
}

local f                              -- the one frame, made on first use
local moving, previewing = false, false
local previewToken = 0
local listening = false
local placeQueued = false

local function Palette()
    local S = R.ChronicleStyle
    return S and S.color or FALLBACK
end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Saved look and place (the profile's; read without being written)
---------------------------------------------------------------------------
local function Ui(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    local t = db.ui.cozyBagButton
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        db.ui.cozyBagButton = t
    end
    return t
end

local function ValidValue(key, value)
    local limit = B.LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2] and math.floor(value) == value
    end
    return type(value) == "string" and B.ENUM[key] ~= nil and B.ENUM[key][value] == true
end

-- A saved value that can't be used reads as the default and is left as it is.
function B.Get(key)
    local t = Ui(false)
    local v = t and t[key]
    if ValidValue(key, v) then return v end
    return B.DEFAULTS[key]
end

function B.Set(key, value)
    if B.DEFAULTS[key] == nil then return false end
    if type(value) == "number" then value = math.floor(value + 0.5) end
    if not ValidValue(key, value) then return false end
    local t = Ui(true)
    if not t then return false end
    t[key] = value
    B.Refresh()
    return true
end

local function Finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end
local function Usable(v) return Finite(v) and math.abs(v) <= POSITION_LIMIT end

local function ScreenSize()
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    if not (Finite(w) and Finite(h) and w > 0 and h > 0) then return nil end
    return w, h
end

-- The default place: against the left edge, a little above the middle (clear of the character and the middle bars).
local function DefaultPosition()
    local w = ScreenSize()
    return -((w or 1024) / 2) + 60, 140
end

function B.Position()
    local t = Ui(false)
    if t and Usable(t.x) and Usable(t.y) then return t.x, t.y, true end
    local x, y = DefaultPosition()
    return x, y, false
end

function B.SetPosition(x, y)
    if x == nil then
        local t = Ui(false)
        if t then t.x, t.y = nil, nil end
        B.Place()
        return true
    end
    if not (Usable(x) and Usable(y)) then return false end
    local t = Ui(true)
    if not t then return false end
    t.x, t.y = x, y
    B.Place()
    return true
end

function B.ResetPosition() return B.SetPosition(nil, nil) end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function SetEdge(color)
    for _, e in ipairs(f.edges) do e:SetColorTexture(color[1], color[2], color[3], 0.9) end
end

local function Rest()
    local K = Palette()
    SetEdge(moving and K.gold or K.bronze)
end

local function Tooltip()
    if previewing then return "A preview of the button. Clicking it does nothing." end
    if moving then return "Drag to move the button. Right-click for Done." end
    return "Opens the Cozy Sleeping Bag guide. Right-click for more."
end

local function MenuItems(owner, root)
    root:CreateTitle(NAME)
    if moving then
        root:CreateButton("Done moving", function() B.StopMove() end)
        root:CreateButton("Reset position", function() B.ResetPosition() end)
        return
    end
    root:CreateButton("Open guide", function() B.Open() end)
    root:CreateButton("Move", function()
        local ok, why = B.StartMove()
        if not ok and why == "combat" then R.Print("the button can't be moved in combat.") end
    end)
    root:CreateButton("Hide button", function() B.HideForever() end)
end

local function OnClick(self, button)
    if previewing or moving then
        if button == "RightButton" then B.Menu() end
        return
    end
    if button == "RightButton" then B.Menu() else B.Open() end
end

local function Build()
    local K = Palette()
    f = CreateFrame("Button", "TwichUICozyBagButton", UIParent)
    f:Hide()
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end   -- TwichUI keeps the place, not the game's layout cache

    f.ground = f:CreateTexture(nil, "BACKGROUND")
    f.ground:SetAllPoints()
    f.ground:SetColorTexture(K.bg[1], K.bg[2], K.bg[3], 0.88)
    f.edges = {}
    for i, anchors in ipairs({
        { "TOPLEFT", "TOPRIGHT", height = 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", height = 1 },
        { "TOPLEFT", "BOTTOMLEFT", width = 1 }, { "TOPRIGHT", "BOTTOMRIGHT", width = 1 },
    }) do
        local e = f:CreateTexture(nil, "BORDER")
        e:SetPoint(anchors[1])
        e:SetPoint(anchors[2])
        if anchors.height then e:SetHeight(anchors.height) end
        if anchors.width then e:SetWidth(anchors.width) end
        f.edges[i] = e
    end
    f.icon = f:CreateTexture(nil, "ARTWORK")
    if R.Icons and R.Icons.Apply then R.Icons.Apply(f.icon, "sleepingBag", B.Get("size")) end
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.label:SetText(NAME)
    f.label:SetTextColor(K.text[1], K.text[2], K.text[3])
    f.label:SetJustifyH("LEFT")
    f.label:SetWordWrap(false)
    f.move = f:CreateTexture(nil, "OVERLAY")        -- the quiet tint that says it can be dragged
    f.move:SetAllPoints()
    f.move:SetColorTexture(K.bronze[1], K.bronze[2], K.bronze[3], 0.30)
    f.move:Hide()

    R.Interact.Tip(f, NAME, Tooltip, "ANCHOR_RIGHT")
    f:HookScript("OnEnter", function() SetEdge(Palette().gold) end)
    f:HookScript("OnLeave", Rest)
    f:SetScript("OnClick", OnClick)
    f:SetScript("OnDragStart", function(self)
        if moving and not InCombat() then self.dragging = true self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        if not self.dragging then return end
        self.dragging = nil
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        if cx and cy and px and py then B.SetPosition(math.floor(cx - px + 0.5), math.floor(cy - py + 0.5)) else B.Place() end
    end)
    f:HookScript("OnHide", function(self)
        if self.dragging then self.dragging = nil self:StopMovingOrSizing() end
    end)
    return f
end

-- Size, label, opacity and the pieces' places, for the look as it is now. Safe to call as often as needed.
local function Apply()
    local size = B.Get("size")
    local named = B.Get("label") == "name"
    f.icon:ClearAllPoints()
    f.icon:SetSize(size - EDGE_PAD * 2, size - EDGE_PAD * 2)
    f.icon:SetPoint("LEFT", EDGE_PAD, 0)
    f.label:SetShown(named)
    local width = size
    if named then
        f.label:ClearAllPoints()
        f.label:SetPoint("LEFT", f.icon, "RIGHT", 6, 0)
        local text = f.label:GetStringWidth()
        width = size + 6 + math.ceil(type(text) == "number" and text or 64) + 8
    end
    f:SetSize(width, size)
    f:SetAlpha(B.Get("opacity") / 100)
    f.move:SetShown(moving)
    Rest()
end

-- Puts the button at its place, held on screen. Called on every change of place, scale or display.
function B.Place()
    if not f then return end
    local x, y = B.Position()
    local w, h = ScreenSize()
    if w then
        local mx, my = math.max(0, w / 2 - f:GetWidth() / 2), math.max(0, h / 2 - f:GetHeight() / 2)
        x, y = math.max(-mx, math.min(mx, x)), math.max(-my, math.min(my, y))
    end
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

---------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------
local function OnDisplay()
    if placeQueued then return end
    placeQueued = true
    C_Timer.After(0.1, function()    -- the screen's size follows these events a moment later
        placeQueued = false
        B.Place()
    end)
end

local function OnCombat()
    if moving then B.StopMove() end
    if previewing then B.Preview(false) end
end

local function Listen(on)
    if on and not listening then
        listening = true
        R:On("UI_SCALE_CHANGED", OnDisplay)
        R:On("DISPLAY_SIZE_CHANGED", OnDisplay)
        R:On("PLAYER_REGEN_DISABLED", OnCombat)
    elseif not on and listening then
        listening = false
        R:Off("UI_SCALE_CHANGED", OnDisplay)
        R:Off("DISPLAY_SIZE_CHANGED", OnDisplay)
        R:Off("PLAYER_REGEN_DISABLED", OnCombat)
    end
end

-- Shows or hides the button as things stand: the offer, the player's choices, a preview or a move.
function B.Refresh()
    local want = previewing or moving or (O and O.ButtonWanted()) or false
    if want then
        if not f then Build() end
        Apply()
        B.Place()
        f:Show()
        Listen(true)
    else
        if f then f:Hide() end
        Listen(false)
    end
end

function B.IsShown() return f ~= nil and f:IsShown() end
function B.Moving() return moving end
function B.Previewing() return previewing end

---------------------------------------------------------------------------
-- What the player can do with it
---------------------------------------------------------------------------
-- Opens the guide. Says briefly why when it can't; the button stays.
function B.Open()
    if previewing or moving then return false end
    local ok, why = O.OpenGuide()
    if not ok then R.Print("%s", why) end
    return ok
end

function B.Menu()
    if not (MenuUtil and MenuUtil.CreateContextMenu and f) then
        if moving then B.StopMove() end   -- without a menu, right-click is how to finish moving
        return false
    end
    MenuUtil.CreateContextMenu(f, MenuItems)
    return true
end

-- Move mode: shows the button wherever the offer stands (so it can be placed before the bag is available). Not in combat.
function B.StartMove()
    if InCombat() then return false, "combat" end
    moving = true
    B.Refresh()
    return true
end

function B.StopMove()
    if not moving then return end
    moving = false
    if f and f.dragging then f.dragging = nil f:StopMovingOrSizing() end
    B.Refresh()
end

-- A look at the button as it is set, on any character, for PREVIEW_SECONDS (or until it is turned off, combat, or the settings
-- close). Clicking it does nothing. Records nothing and changes no choice.
function B.Preview(on)
    previewToken = previewToken + 1
    previewing = on == true
    if previewing then
        local mine = previewToken
        C_Timer.After(PREVIEW_SECONDS, function()
            if mine == previewToken and previewing then B.Preview(false) end
        end)
    end
    B.Refresh()
end

-- Takes the button away for this character, until it is brought back in the settings. Says how, once, in the player's own chat.
function B.HideForever()
    if moving then B.StopMove() end
    if not O.SetHidden(true) then return false end
    R.Print("the Sleeping Bag button is hidden. Bring it back in Settings > Cozy Sleeping Bag, or open the guide with /tui bag.")
    return true
end

-- The settings closing: ends a preview and a move so nothing is left on screen.
function B.Settle()
    if moving then B.StopMove() end
    if previewing then B.Preview(false) end
end

function B.Snapshot()
    return { built = f ~= nil, shown = B.IsShown(), moving = moving, previewing = previewing, listening = listening }
end

O.OnChange(B.Refresh)
if R.OnSettingsClosed then R.OnSettingsClosed(B.Settle) end   -- a preview or a move never outlives the settings window
if R.Profiles and R.Profiles.OnApply then
    R.Profiles.OnApply("layout", "cozy-bag-button", function() B.Refresh() end)   -- another profile may size or place it otherwise
end
