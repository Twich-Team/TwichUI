-- TwichUI: RestedXP guide, the data bar menu
-- What a click on the "TwichUI RestedXP Guide" data bar entry opens (modules/RestedXPBroker.lua): a small
-- menu in the same style as the Mage launchers' (modules/SpellMenu.lua): the same palette, fonts and
-- placement, and the player's own menu background and border (modules/MenuStyle.lua).
--   Choose guide  opens the list of guides RestedXP offers in this same menu: sections and groups to step into
--                 (a Back button returns), guides to load. The loaded guide, and the groups leading to it,
--                 carry a marker, and the list opens scrolled to it. A pick loads the guide and closes the menu.
--   Show guide    a switch for RestedXP's guide, like its minimap button. The row says On or Off.
--   Lock windows  a switch for RestedXP's "Lock Frames" option. The row says Locked or Unlocked.
--   Auto accept / turn in, Auto flight path
--                 switches for RestedXP's "Quest auto accept/turn in" and "Flight Path automation" options.
--                 Each row says On or Off.
--   Discard junk if full
--                 a switch for RestedXP's "Discard junk items if bag is full" option. Greyed out, with the reason
--                 in its row ("Inventory off", "Unavailable"), when RestedXP's own option page would hide it.
--   Import guides opens RestedXP's guide import window and closes this menu. Greyed out in combat, when
--                 RestedXP would only queue it.
-- The switches leave the menu open, so several can be set in one visit, and the rows follow RestedXP when
-- it changes (its own minimap button, a profile change). Nothing in it is secure, so it works in combat
-- too, and it listens for events only while it is open. A click anywhere else, Esc or a second click on the
-- data bar entry closes it. What the rows do is the broker's (R.RestedXPBroker); this file only draws.
-- Another addon may add a plain row below those with M.AddRow (see there); the menu closes when it is clicked.

local R = TwichUI
local SM = R.SpellMenu
local MenuStyle = R.MenuStyle
local M = {}
R.RestedXPBrokerMenu = M

local NAME = "TwichUIRestedXPMenu"
local WIDTH, BROWSE_WIDTH, PAD = 220, 290, 8
local TITLE_H, NOTE_H, ROW_H, HEAD_H, GAP = 26, 18, 24, 26, 6
local MAX_VIEW = 11 * ROW_H    -- the list scrolls beyond this
local BAR = 22                 -- room kept for the scroll bar
local BOX = 14
local ARROW = R.PATH .. [[media\textures\arrow-left]]   -- a bronze arrow pointing left; flipped, it points right
local ARROW_SIZE, ARROW_ROOM = 16, 24    -- and the room a row keeps at its right for one

local menu, title, current, divider
local rows = {}
local view = "main"            -- "main", or "browse" while the guide list is shown
local stack = {}               -- browse: { entries = {...}, label = "..." } for each level stepped into
local tree                     -- the guide list, read when browsing starts and kept until the menu closes
local back, scroll, content, empty
local entryRows = {}
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
        key = "choose", label = "Choose guide", plain = true, arrow = true,
        enabled = function() return Broker().CanChoose() end,
        why = "Unavailable",
        act = function() M.Browse() end,
    },
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
        key = "quests", label = "Auto quests",
        state = function() return Broker().QuestAutoOn() end,
        words = { [true] = "On", [false] = "Off" },
        act = function() local B = Broker(); B.SetQuestAuto(not B.QuestAutoOn()) end,
    },
    {
        key = "flight", label = "Auto flight path",
        state = function() return Broker().FlightAutoOn() end,
        words = { [true] = "On", [false] = "Off" },
        act = function() local B = Broker(); B.SetFlightAuto(not B.FlightAutoOn()) end,
    },
    {
        key = "discard", label = "Discard junk if full",
        state = function() return Broker().DiscardOn() end,
        words = { [true] = "On", [false] = "Off" },
        enabled = function() return Broker().DiscardBlocker() == nil end,
        why = function() return Broker().DiscardBlocker() end,
        act = function() local B = Broker(); B.SetDiscard(not B.DiscardOn()) end,
    },
    {
        key = "import", label = "Import guides...", plain = true,
        enabled = function() return Broker().CanImport() end,
        why = "In combat",
        act = function() M.Close(); Broker().OpenImport() end,
    },
}

-- The bronze arrow, pointing left (a Back button) or right (a row that leads somewhere).
local function ArrowTexture(parent, pointsRight)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(ARROW)
    t:SetSize(ARROW_SIZE, ARROW_SIZE)
    if pointsRight then t:SetTexCoord(1, 0, 0, 1) end
    return t
end

local function NewRow(spec)
    local K = Palette()
    local row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_H)
    row.spec = spec
    local hover = SM.Solid(row, "HIGHLIGHT", K.gold, 0.08)
    hover:SetAllPoints()
    row.note = SM.Text(row, SM.FONTS.note, 12, "GameFontNormalSmall")
    row.note:SetPoint("RIGHT", spec.arrow and -ARROW_ROOM or -6, 0)
    row.note:SetJustifyH("RIGHT")
    if spec.arrow then
        row.chev = ArrowTexture(row, true)
        row.chev:SetPoint("RIGHT", -5, 0)
    end
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
        if s.external then M.Close() end
        s.act()
        if menu and menu:IsShown() then M.Refresh() end
    end)
    return row
end

-- A row's reason for being greyed out: a string, or a function that returns one (nil when there is none).
local function Why(s)
    if type(s.why) == "function" then return s.why() end
    return s.why
end

local function Fill(row)
    local K = Palette()
    local s = row.spec
    local B = Broker()
    local usable = s.external or B.GuideOn() ~= nil   -- another addon's row doesn't depend on RestedXP being readable
    local enabled = usable and (not s.enabled or s.enabled())
    row.name:SetText(s.label)
    Paint(row.name, enabled and K.text or K.stone)
    if s.plain then
        row.note:SetText(enabled and "" or (usable and Why(s) or ""))
        if row.chev then row.chev:SetShown(enabled and true or false) end
    else
        local on = s.state()
        row.fill:SetShown(on == true)
        local rim = on and K.bronze or K.bronzeLo
        row.rim:SetColorTexture(rim[1], rim[2], rim[3])
        -- A greyed switch says why instead of its state; the box still shows the state.
        local why = usable and not enabled and Why(s)
        row.note:SetText(why or (on == nil and "" or s.words[on]))
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
        view, tree = "main", nil
        wipe(stack)
        local tipOwner = GameTooltip and GameTooltip:GetOwner()
        if tipOwner and content and tipOwner:GetParent() == content then GameTooltip:Hide() end
        M.Listen(false)
    end)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end
end

-- The player's background and border, and a margin that clears a thick one.
local function Restyle()
    pad = math.max(PAD, math.ceil(MenuStyle.Apply(menu)))
end

local function ShowBrowse(on)
    if back then back:SetShown(on) end
    if scroll then scroll:SetShown(on) end
    if empty then empty:SetShown(false) end
end

local function RenderMain()
    ShowBrowse(false)
    menu:SetWidth(WIDTH)
    title:SetText("RestedXP guide")
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", pad + 4, -pad - 2)
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
    divider:Show()
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
-- Choosing a guide: the list, stepped into level by level
---------------------------------------------------------------------------
local RenderBrowse

local function Level() return stack[#stack] end

local function OnEntry(self)
    local e = self.entry
    if not e or e.heading or e.disabled then return end
    if e.children then
        stack[#stack + 1] = { entries = e.children, label = e.text, focus = true }
        RenderBrowse()
    elseif Broker().LoadGuide(e) then
        M.Close()
    end
end

local function NewEntryRow()
    local K = Palette()
    local row = CreateFrame("Button", nil, content)
    local hover = SM.Solid(row, "HIGHLIGHT", K.gold, 0.08)
    hover:SetAllPoints()
    row.hover = hover
    row.mark = SM.Solid(row, "ARTWORK", K.gold)
    row.mark:SetWidth(2)
    row.mark:SetPoint("TOPLEFT", 0, -4)
    row.mark:SetPoint("BOTTOMLEFT", 0, 4)
    row.note = SM.Text(row, SM.FONTS.note, 12, "GameFontNormalSmall")
    row.note:SetJustifyH("RIGHT")
    row.chev = ArrowTexture(row, true)
    row.chev:SetPoint("RIGHT", -5, 0)
    row.name = SM.Text(row, SM.FONTS.row, 14, "GameFontNormal")
    row.name:SetPoint("LEFT", 8, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -6, 0)
    row.head = SM.Text(row, SM.FONTS.header, 12, "GameFontNormalSmall")
    row.head:SetPoint("BOTTOMLEFT", 8, 3)
    row.head:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:SetScript("OnClick", OnEntry)
    -- A name too long for the row is shown whole while the pointer is on it.
    row:SetScript("OnEnter", function(self)
        local name = self.name
        if self.entry and not self.entry.heading and GameTooltip and (name:GetStringWidth() or 0) > (name:GetWidth() or 0) + 1 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry.text, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return row
end

-- A heading, a group (an arrow at the right), a guide, or the loaded guide (marker and the word Current).
local function DressEntry(row, e, y)
    local K = Palette()
    row.entry = e
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    row:SetHeight(e.heading and HEAD_H or ROW_H)
    row.head:SetShown(e.heading == true)
    row.name:SetShown(not e.heading)
    row.note:SetShown(not e.heading)
    row.chev:SetShown(e.children ~= nil)
    row.note:ClearAllPoints()
    row.note:SetPoint("RIGHT", e.children and -ARROW_ROOM or -6, 0)
    row.mark:SetShown(e.current == true and not e.heading)
    row.hover:SetShown(not e.heading and not e.disabled)
    row:SetEnabled(not e.heading and not e.disabled)
    if e.heading then
        row.head:SetText(e.text)
        Paint(row.head, K.gold)
    else
        row.name:SetText(e.text)
        Paint(row.name, e.disabled and K.stone or (e.current and K.gold or K.text))
        row.note:SetText(not e.children and e.current and "Current" or "")
        Paint(row.note, K.stone)
    end
    row:Show()
end

function RenderBrowse()
    local K = Palette()
    local level = Level()
    if not level then
        view = "main"
        return M.Refresh()
    end
    ShowBrowse(true)
    menu:SetWidth(BROWSE_WIDTH)
    current:Hide()
    divider:Hide()
    for _, row in ipairs(rows) do row:Hide() end
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + 4, -pad - 2)
    title:SetText(level.label)
    title:ClearAllPoints()
    title:SetPoint("LEFT", back, "RIGHT", 12, 0)
    title:SetPoint("RIGHT", menu, "RIGHT", -pad - 4, 0)

    local entries = level.entries
    local y, focusAt = 0, nil
    for i, e in ipairs(entries) do
        local row = entryRows[i] or NewEntryRow()
        entryRows[i] = row
        if e.current and not focusAt then focusAt = y end
        DressEntry(row, e, y)
        y = y + (e.heading and HEAD_H or ROW_H)
    end
    for i = #entries + 1, #entryRows do entryRows[i]:Hide(); entryRows[i].entry = nil end

    local viewH = math.min(math.max(y, ROW_H), MAX_VIEW)
    local listW = BROWSE_WIDTH - pad * 2 - (y > MAX_VIEW and BAR or 0)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", menu, "TOPLEFT", pad, -(pad + TITLE_H))
    scroll:SetSize(listW, viewH)
    content:SetSize(listW, math.max(1, y))
    empty:SetShown(#entries == 0)
    empty:ClearAllPoints()
    empty:SetPoint("TOPLEFT", menu, "TOPLEFT", pad + 4, -(pad + TITLE_H + 4))
    empty:SetPoint("RIGHT", menu, "RIGHT", -pad - 4, 0)
    menu:SetHeight(pad + TITLE_H + viewH + pad)
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    if level.focus then
        -- Just stepped into this level: show the loaded guide (or the group leading to it) in the middle.
        level.focus = nil
        local range = math.max(0, y - viewH)
        scroll:SetVerticalScroll(focusAt and math.min(range, math.max(0, focusAt - (viewH - ROW_H) / 2)) or 0)
    end
    if scroll.paintBar then scroll.paintBar() end
end

local function Render()
    if view == "browse" then RenderBrowse() else RenderMain() end
end

local function BuildBrowse()
    if scroll then return end
    local K = Palette()
    back = CreateFrame("Button", nil, menu)
    back.icon = ArrowTexture(back, false)
    back.icon:SetPoint("LEFT")
    back.icon:SetAlpha(0.85)
    back.text = SM.Text(back, SM.FONTS.note, 13, "GameFontNormalSmall")
    back.text:SetPoint("LEFT", back.icon, "RIGHT", 3, 0)
    back.text:SetText("Back")
    Paint(back.text, K.gold)
    back:SetSize(ARROW_SIZE + 3 + 30, 18)
    back:SetScript("OnEnter", function(self) Paint(self.text, K.text); self.icon:SetAlpha(1) end)
    back:SetScript("OnLeave", function(self) Paint(self.text, K.gold); self.icon:SetAlpha(0.85) end)
    back:SetScript("OnClick", function()
        stack[#stack] = nil
        if #stack == 0 then view = "main" end
        Render()
    end)
    scroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    scroll.paintBar = R.ChronicleStyle.ScrollBar(scroll)
    -- Hidden until the list is long enough to scroll, as the party pins menu does.
    scroll.scrollBarHideable = true
    scroll.ScrollBar:Hide()
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local arrow = scroll.ScrollBar[key]
        if arrow then arrow:Hide() end
    end
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(BROWSE_WIDTH - PAD * 2, 1)
    scroll:SetScrollChild(content)
    empty = SM.Text(menu, SM.FONTS.note, 12, "GameFontNormalSmall")
    empty:SetWordWrap(true)
    empty:SetText("RestedXP has no guides for this character.")
    Paint(empty, K.stone)
    back:Hide(); scroll:Hide(); empty:Hide()
end

-- Reads the guide list and shows it. Read once per opening of the menu.
function M.Browse()
    if not (menu and Broker().CanChoose()) then return end
    tree = tree or Broker().GuideTree()
    BuildBrowse()
    stack = { { entries = tree or {}, label = "Choose guide", focus = true } }
    view = "browse"
    if tree == nil then empty:SetText("RestedXP's guide list can't be read.") else empty:SetText("RestedXP has no guides for this character.") end
    Render()
end

---------------------------------------------------------------------------
-- A row from another addon
---------------------------------------------------------------------------
-- spec = { key = "unique", label = "Text...", act = function, enabled = function (optional), why = "short
-- note shown while greyed out" (optional) }. A plain row, added once per key below the built-in ones: a
-- second call with the same key is ignored, and so is a spec that isn't valid. Returns whether it was added.
function M.AddRow(spec)
    if type(spec) ~= "table" or type(spec.key) ~= "string" or spec.key == ""
        or type(spec.label) ~= "string" or type(spec.act) ~= "function"
        or (spec.enabled ~= nil and type(spec.enabled) ~= "function") then
        return false
    end
    for _, s in ipairs(SPEC) do if s.key == spec.key then return false end end
    local row = {
        key = spec.key, label = spec.label, act = spec.act, enabled = spec.enabled,
        why = type(spec.why) == "string" and spec.why or nil,
        plain = true, external = true,
    }
    SPEC[#SPEC + 1] = row
    if menu then
        rows[#SPEC] = NewRow(row)
        M.Refresh()
    end
    return true
end

---------------------------------------------------------------------------
-- Opening, closing, following RestedXP
---------------------------------------------------------------------------
function M.IsOpen() return menu ~= nil and menu:IsShown() end

function M.Open(frame)
    Build()
    owner = frame
    view = "main"
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
