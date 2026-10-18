-- TwichUI: RestedXP guide, the data bar menu
-- What a click on the "TwichUI RestedXP Guide" data bar entry opens (modules/RestedXPBroker.lua): a small
-- menu in the same style as the Mage launchers' (modules/SpellMenu.lua): the same palette, fonts and
-- placement, and the player's own menu background and border (modules/MenuStyle.lua).
--   Show guide    a switch for RestedXP's guide, like its minimap button. The row says On or Off.
--   Lock windows  a switch for RestedXP's "Lock Frames" option. The row says Locked or Unlocked.
--   Import guides opens RestedXP's guide import window and closes this menu. Greyed out in combat, when
--                 RestedXP would only queue it.
-- The two switches leave the menu open, so both can be set in one visit, and the rows follow RestedXP when
-- it changes (its own minimap button, a profile change). Nothing in it is secure, so it works in combat
-- too, and it listens for events only while it is open. A click anywhere else, Esc or a second click on the
-- data bar entry closes it. What the rows do is the broker's (R.RestedXPBroker); this file only draws.

local R = TwichUI
local SM = R.SpellMenu
local MenuStyle = R.MenuStyle
local M = {}
R.RestedXPBrokerMenu = M

local NAME = "TwichUIRestedXPMenu"
local WIDTH, PAD = 220, 8
local TITLE_H, NOTE_H, ROW_H, GAP = 26, 18, 24, 6
local BOX = 14

local menu, title, current, divider
local rows = {}
local owner                -- the data bar frame it was opened from
local pad = PAD
local listening = false

local function Broker() return R.RestedXPBroker end
local function Palette() return SM.Palette() end

local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

---------------------------------------------------------------------------
-- The rows. Each has a label, a box that is filled when it is on, and a note on the right that says it in
-- words, so the state never rests on color alone.
---------------------------------------------------------------------------
local SPEC = {
    {
        key = "guide", label = "Show guide",
        state = function() return Broker().GuideOn() end,
        words = { [true] = "On", [false] = "Off" },
        act = function() local B = Broker(); B.SetGuideOn(not B.GuideOn()) end,
    },
    {
        key = "lock", label = "Lock windows",
        state = function() return Broker().GuideLocked() end,
        words = { [true] = "Locked", [false] = "Unlocked" },
        act = function() local B = Broker(); B.SetLocked(not B.GuideLocked()) end,
    },
    {
        key = "import", label = "Import guides...", plain = true,
        enabled = function() return Broker().CanImport() end,
        why = "In combat",
        act = function() M.Close(); Broker().OpenImport() end,
    },
}

local function NewRow(spec)
    local K = Palette()
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_H)
    row.spec = spec
    local hover = SM.Solid(row, "HIGHLIGHT", K.gold, 0.08)
    hover:SetAllPoints()
    row.note = SM.Text(row, SM.FONTS.note, 12, "GameFontNormalSmall")
    row.note:SetPoint("RIGHT", -6, 0)
    row.note:SetJustifyH("RIGHT")
    row.name = SM.Text(row, SM.FONTS.row, 14, "GameFontNormal")
    if spec.plain then
        row.name:SetPoint("LEFT", 6, 0)
    else
        row.rim = SM.Solid(row, "ARTWORK", K.bronzeLo)
        row.rim:SetSize(BOX, BOX)
        row.rim:SetPoint("LEFT", 5, 0)
        row.well = SM.Solid(row, "ARTWORK", K.well)
        row.well:SetDrawLayer("ARTWORK", 1)
        row.well:SetPoint("TOPLEFT", row.rim, 1, -1)
        row.well:SetPoint("BOTTOMRIGHT", row.rim, -1, 1)
        row.fill = SM.Solid(row, "ARTWORK", K.gold)
        row.fill:SetDrawLayer("ARTWORK", 2)
        row.fill:SetPoint("TOPLEFT", row.rim, 3, -3)
        row.fill:SetPoint("BOTTOMRIGHT", row.rim, -3, 3)
        row.name:SetPoint("LEFT", row.rim, "RIGHT", 8, 0)
    end
    row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row:SetScript("OnClick", function(self)
        local s = self.spec
        if s.enabled and not s.enabled() then return end
        s.act()
        if menu and menu:IsShown() then M.Refresh() end
    end)
    return row
end

local function Fill(row)
    local K = Palette()
    local s = row.spec
    local B = Broker()
    local usable = B.GuideOn() ~= nil
    local enabled = usable and (not s.enabled or s.enabled())
    row.name:SetText(s.label)
    Paint(row.name, enabled and K.text or K.stone)
    if s.plain then
        row.note:SetText(enabled and "" or (usable and s.why or ""))
    else
        local on = s.state()
        row.fill:SetShown(on == true)
        local rim = on and K.bronze or K.bronzeLo
        row.rim:SetColorTexture(rim[1], rim[2], rim[3])
        row.note:SetText(on == nil and "" or s.words[on])
    end
    Paint(row.note, K.stone)
    row:SetEnabled(enabled and true or false)
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local function Build()
    if menu then return end
    local K = Palette()
    menu = CreateFrame("Frame", NAME, UIParent, "BackdropTemplate")
    menu:SetWidth(WIDTH)
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:Hide()
    title = SM.Text(menu, SM.FONTS.title, 13, "GameFontNormal")
    title:SetText("RestedXP guide")
    Paint(title, K.text)
    current = SM.Text(menu, SM.FONTS.note, 12, "GameFontNormalSmall")
    Paint(current, K.stone)
    divider = SM.Solid(menu, "ARTWORK", K.bronzeLo, 0.8)
    divider:SetHeight(1)
    for i, spec in ipairs(SPEC) do rows[i] = NewRow(spec) end
    menu:SetScript("OnHide", function()
        owner = nil
        M.Listen(false)
    end)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end
end

-- The player's background and border, and a margin that clears a thick one.
local function Restyle()
    pad = math.max(PAD, math.ceil(MenuStyle.Apply(menu)))
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", pad + 4, -pad - 2)
end

local function Render()
    local y = -(pad + TITLE_H)
    local name = Broker().GuideName()
    current:ClearAllPoints()
    current:SetShown(name ~= nil)
    if name then
        current:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + 4, y + 4)
        current:SetPoint("RIGHT", menu, "RIGHT", -pad - 4, 0)
        current:SetText(name)
        y = y - NOTE_H
    end
    for i, row in ipairs(rows) do
        if row.spec.key == "import" then
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + 4, y - GAP / 2)
            divider:SetPoint("RIGHT", menu, "RIGHT", -pad - 4, 0)
            y = y - GAP
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, y)
        row:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
        row:Show()
        Fill(row)
        y = y - ROW_H
    end
    menu:SetHeight(-y + pad)
end

---------------------------------------------------------------------------
-- Opening, closing, following RestedXP
---------------------------------------------------------------------------
function M.IsOpen() return menu ~= nil and menu:IsShown() end

function M.Open(frame)
    Build()
    owner = frame
    Restyle()
    Render()
    SM.PlaceNear(menu, frame)
    menu:Show()
    M.Listen(true)
end

function M.Close()
    if M.IsOpen() then menu:Hide() end
end

function M.Toggle(frame)
    if M.IsOpen() then M.Close() else M.Open(frame) end
end

-- The guide was toggled, the profile changed, or the player's menu look did: draw it again.
function M.Refresh()
    if M.IsOpen() then Render() end
end

local function OnLook()
    if not menu then return end
    Restyle()
    M.Refresh()
end

-- A click anywhere but the menu or the data bar entry closes it.
local function OnMouseDown()
    if not M.IsOpen() or menu:IsMouseOver() then return end
    if owner and owner.IsMouseOver and owner:IsMouseOver() then return end
    M.Close()
end

local HANDLERS = {
    PLAYER_REGEN_DISABLED = M.Refresh,   -- Import greys out
    PLAYER_REGEN_ENABLED = M.Refresh,
    GLOBAL_MOUSE_DOWN = OnMouseDown,
    UI_SCALE_CHANGED = OnLook,           -- a border is a whole number of screen pixels
    DISPLAY_SIZE_CHANGED = OnLook,
}

function M.Listen(on)
    if on == listening then return end
    listening = on
    for event, handler in pairs(HANDLERS) do
        if on then R:On(event, handler) else R:Off(event, handler) end
    end
end

MenuStyle.Subscribe(OnLook)
