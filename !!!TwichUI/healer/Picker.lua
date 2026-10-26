-- TwichUI: Healer Watch, the quick-select menu
-- The menu a click on the panel opens while it asks you to "Choose a healer": Automatic first, then you and each group
-- member, the one with the Healer role marked. It is drawn in the look of TwichUI's data bar menus (modules/SpellMenu.lua's
-- fonts and palette, and the background and border the player set for them in modules/MenuStyle.lua), not the game's
-- context menu. It only reports the row clicked (onPick(value)); Watch.lua decides what choosing means.
--
--   P.Open(owner, list, chosen, onPick)   list: { { value, label, name = , role = true }, ... } (Watch.PickerChoices);
--                                          a second call while it is open closes it. Returns true.
--   P.Close()                             put it away
--
-- One frame and a small pool of rows, made the first time it opens and reused. It listens only while open: a click anywhere
-- else closes it, as does Esc (the game's own list of frames Esc closes) and a change of group. Nothing is saved.

local R = TwichUI
local MenuStyle = R.MenuStyle
local SM = R.SpellMenu
local P = {}
R.HealerPicker = P

local MIN_WIDTH, MAX_WIDTH = 210, 340
local PAD = 8
local TITLE_HEIGHT = 26
local ROW_HEIGHT = 24
local RULE_GAP = 6          -- the space around the rule under Automatic
local MARK = 10             -- the round-ish choice marker, in pixels
local GAP = 4               -- between the panel and the menu

local menu, title
local rows = {}
local owner, pickFn
local listening = false

local function Pal() return SM.Palette() end

local function Row(i)
    if rows[i] then return rows[i] end
    local K = Pal()
    local b = CreateFrame("Button", nil, menu)
    b:SetHeight(ROW_HEIGHT)
    b:RegisterForClicks("LeftButtonUp")
    b.hover = SM.Solid(b, "HIGHLIGHT", K.gold, 0.10)
    b.hover:SetAllPoints()
    b.accent = SM.Solid(b, "ARTWORK", K.gold, 0.9)   -- a short bar at the left edge of the row being watched
    b.accent:SetWidth(2)
    b.accent:SetPoint("TOPLEFT", 0, -3)
    b.accent:SetPoint("BOTTOMLEFT", 0, 3)
    b.ring = SM.Solid(b, "ARTWORK", K.bronze, 1)
    b.ring:SetSize(MARK + 2, MARK + 2)
    b.ring:SetPoint("LEFT", 8, 0)
    b.well = SM.Solid(b, "ARTWORK", K.well, 1)
    b.well:SetDrawLayer("ARTWORK", 1)
    b.well:SetSize(MARK, MARK)
    b.well:SetPoint("CENTER", b.ring, "CENTER")
    b.dot = SM.Solid(b, "ARTWORK", K.gold, 1)
    b.dot:SetDrawLayer("ARTWORK", 2)
    b.dot:SetSize(MARK - 4, MARK - 4)
    b.dot:SetPoint("CENTER", b.ring, "CENTER")
    b.note = SM.Text(b, SM.FONTS.note, 12, "GameFontNormalSmall")
    b.note:SetPoint("RIGHT", -8, 0)
    b.note:SetJustifyH("RIGHT")
    b.name = SM.Text(b, SM.FONTS.row, 14, "GameFontNormal")
    b.name:SetPoint("LEFT", b.ring, "RIGHT", 8, 0)
    b.name:SetPoint("RIGHT", b.note, "LEFT", -8, 0)
    b:SetScript("OnClick", function(self)
        local fn, value = pickFn, self.value
        P.Close()
        if fn then fn(value) end
    end)
    rows[i] = b
    return b
end

local function Rule(y)
    if not menu.rule then
        local K = Pal()
        menu.rule = SM.Solid(menu, "ARTWORK", K.bronzeLo, 0.8)
        menu.rule:SetHeight(1)
    end
    menu.rule:ClearAllPoints()
    menu.rule:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD + 4, y)
    menu.rule:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD - 4, y)
    menu.rule:Show()
end

local function OnMouseDown()
    if not (menu and menu:IsShown()) or menu:IsMouseOver() then return end
    if owner and owner.IsMouseOver and owner:IsMouseOver() then return end   -- the panel's own click toggles it
    P.Close()
end

local function Listen(on)
    if on == listening then return end
    listening = on
    local f = on and R.On or R.Off
    f(R, "GLOBAL_MOUSE_DOWN", OnMouseDown)
    f(R, "GROUP_ROSTER_UPDATE", P.Close)
    f(R, "PLAYER_ENTERING_WORLD", P.Close)
end

local function Build()
    if menu then return end
    local K = Pal()
    menu = CreateFrame("Frame", "TwichUIHealerPicker", UIParent, "BackdropTemplate")
    menu:SetFrameStrata("DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)   -- a click on the menu is not a click on the world
    menu:Hide()
    title = SM.Text(menu, SM.FONTS.title, 13, "GameFontNormal")
    title:SetText("Watch which healer?")
    title:SetTextColor(K.text[1], K.text[2], K.text[3])
    menu:SetScript("OnHide", function() Listen(false) end)
    MenuStyle.Subscribe(function() if menu:IsShown() and P.last then P.Layout() end end)
    if UISpecialFrames then tinsert(UISpecialFrames, "TwichUIHealerPicker") end   -- Esc (never the game menu's handler list)
end

-- The look and the rows from P.last = { list, chosen }.
function P.Layout()
    local K = Pal()
    local list, chosen = P.last.list, P.last.chosen
    local pad = math.max(PAD, math.ceil(MenuStyle.ApplyInset(menu)))
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", pad + 4, -pad - 2)

    local wide = MIN_WIDTH
    for i, entry in ipairs(list) do
        local b = Row(i)
        b.value = entry[1]
        b.name:SetText(entry.name or entry[2])
        b.note:SetText(entry.role and "Healer" or "")
        b.note:SetTextColor(K.gold[1], K.gold[2], K.gold[3])
        local selected = entry[1] == chosen
        local c = selected and K.text or K.textDim
        b.name:SetTextColor(c[1], c[2], c[3])
        b.dot:SetShown(selected)
        b.accent:SetShown(selected)
        local need = (b.name:GetStringWidth() or 0) + (b.note:GetStringWidth() or 0) + MARK + 2 + 8 + 8 + 8 + 8 + 8
        if need > wide then wide = need end
    end
    wide = math.min(MAX_WIDTH, math.ceil(wide)) + (pad - PAD) * 2
    menu:SetWidth(wide)

    local y = -(pad + TITLE_HEIGHT)
    if menu.rule then menu.rule:Hide() end
    for i, entry in ipairs(list) do
        local b = rows[i]
        if i == 2 then   -- under Automatic, a rule, then the people
            Rule(y - RULE_GAP / 2)
            y = y - RULE_GAP
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, y)
        b:SetPoint("RIGHT", menu, "RIGHT", -pad, 0)
        b:Show()
        y = y - ROW_HEIGHT
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    menu:SetHeight(-y + pad)
end

-- Below the panel, or above it when there isn't room below.
local function Place()
    menu:ClearAllPoints()
    local bottom, scale = owner:GetBottom(), owner:GetEffectiveScale()
    local mscale = menu:GetEffectiveScale()
    local need = (menu:GetHeight() or 0) * (mscale or 1) + GAP * (scale or 1)
    if bottom and scale and bottom * scale < need then
        menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, GAP)
    else
        menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -GAP)
    end
end

function P.IsOpen() return menu ~= nil and menu:IsShown() end

function P.Close()
    if menu and menu:IsShown() then menu:Hide() end
end

function P.Open(anchor, list, chosen, onPick)
    if P.IsOpen() and owner == anchor then P.Close() return true end
    Build()
    owner, pickFn = anchor, onPick
    P.last = { list = list, chosen = chosen }
    P.Layout()
    Place()
    menu:Show()
    menu:Raise()
    Listen(true)
    return true
end
