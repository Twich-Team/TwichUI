-- TwichUI: refreshment shares page (Options > AddOns > TwichUI > Mage > Refreshment shares)
-- How many conjured water and food each class gets from the Mage, in a party and in a raid, and how
-- many the Mage keeps. A canvas page inside TwichUI's settings, since a table of numbers doesn't fit
-- Blizzard's standard controls. It sits in Blizzard's Options window, so it uses Blizzard's own look
-- (no EllesmereUI skinning), as the Stat weights page does. The numbers live in modules/Refreshments.lua.

local R = TwichUI
local RF = R.Refreshments
local RS = {}
R.RefreshmentShares = RS

local WIDTH = 620
local ROW_H = 24
local TOP = -62                -- below the page title and divider
local COLUMNS = {              -- { context, kind, label }
    { "party", "water", "Water" }, { "party", "food", "Food" },
    { "raid", "water", "Water" }, { "raid", "food", "Food" },
}
local COL_X, COL_W = 220, 84
local f
local built = false
local boxes = {}               -- every amount box, with .commit and .read

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    return fs
end

local function ClassName(class)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

-- A box for one amount. read() gives the value to show; write(value) saves it (false if refused).
local function AmountBox(parent, x, y, label, read, write)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(48, 20)
    eb:SetPoint("TOPLEFT", x, y)
    eb:SetAutoFocus(false)
    eb:SetNumeric(true)
    eb:SetMaxLetters(3)
    eb:SetJustifyH("RIGHT")
    eb.read = read
    eb.commit = function(self)
        if self.revert then
            self.revert = nil
            self:SetText(tostring(read()))
            return
        end
        local text = (self:GetText() or ""):gsub("%s+", "")
        local value = tonumber(text)
        if text == "" then value = nil end
        if value == nil or not write(value) then
            if text ~= "" then R.Print("%s needs a whole number from 0 to %d; \"%s\" wasn't used.", label, RF.MAX, text:sub(1, 8)) end
            self:SetText(tostring(read()))
        end
    end
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb:SetScript("OnEscapePressed", function(self) self.revert = true; self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) self:commit() end)
    R.Interact.Tip(eb, label, "Single items, not stacks. 0 gives none. Press Enter to save; Esc puts the old number back.")
    boxes[#boxes + 1] = eb
    return eb
end

function RS.Refresh()
    if not (f and built and f:IsShown()) then return end
    for _, eb in ipairs(boxes) do
        if not eb:HasFocus() then eb:SetText(tostring(eb.read())) end
    end
end

local function Build(p)
    built = true
    local help = Text(p, "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 16, TOP)
    help:SetWidth(WIDTH - 32)
    help:SetTextColor(0.72, 0.70, 0.66)
    help:SetText("How many conjured water and food the refreshments panel plans for each class, as single items. Your party and your raid each have their own column. These are only a starting point: change any number, and 0 gives none. Each person is planned the best rank you know that their level can use.")

    local y = TOP - 54
    local party = Text(p, "GameFontNormal")
    party:SetPoint("TOPLEFT", COL_X, y)
    party:SetText("Party")
    local raid = Text(p, "GameFontNormal")
    raid:SetPoint("TOPLEFT", COL_X + COL_W * 2, y)
    raid:SetText("Raid")
    y = y - 20
    for i, col in ipairs(COLUMNS) do
        local h = Text(p, "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", COL_X + (i - 1) * COL_W, y)
        h:SetText(col[3])
    end
    y = y - 18
    for _, class in ipairs(RF.CLASSES) do
        local name = Text(p, "GameFontHighlight")
        name:SetPoint("TOPLEFT", 24, y - 3)
        name:SetText(ClassName(class))
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then name:SetTextColor(c.r, c.g, c.b) end
        for i, col in ipairs(COLUMNS) do
            local context, kind = col[1], col[2]
            AmountBox(p, COL_X + (i - 1) * COL_W, y, ("%s, %s %s"):format(ClassName(class), context, kind),
                function() return RF.Share(context, class, kind) end,
                function(value) return RF.SetShare(context, class, kind, value) end)
        end
        y = y - ROW_H
    end

    y = y - 12
    local keep = Text(p, "GameFontNormal")
    keep:SetPoint("TOPLEFT", 24, y - 3)
    keep:SetText("You keep")
    for i, kind in ipairs(RF.KINDS) do
        local label = Text(p, "GameFontDisableSmall")
        label:SetPoint("TOPLEFT", COL_X + (i - 1) * COL_W, y + 14)
        label:SetText(RF.KIND_LABEL[kind])
        AmountBox(p, COL_X + (i - 1) * COL_W, y, "What you keep, " .. kind,
            function() return RF.Reserve(kind) end,
            function(value) return RF.SetReserve(kind, value) end)
    end
    local keepHelp = Text(p, "GameFontHighlightSmall")
    keepHelp:SetPoint("TOPLEFT", 24, y - 26)
    keepHelp:SetWidth(WIDTH - 48)
    keepHelp:SetTextColor(0.72, 0.70, 0.66)
    keepHelp:SetText("Planned at your own best rank, on top of the group's shares, in a group or on your own.")

    local reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetText("Reset shares")
    reset:SetPoint("TOPLEFT", 20, y - 56)
    reset:SetScript("OnClick", function()
        for _, eb in ipairs(boxes) do if eb:HasFocus() then eb.revert = true; eb:ClearFocus() end end
        R.Interact.Confirm("TWICHUI_REFRESHMENT_SHARES_RESET",
            "Put every class's share and what you keep back to TwichUI's starting amounts?",
            function()
                RF.ResetShares()
                RS.Refresh()
            end, { combat = true })
    end)
    R.Interact.Tip(reset, "Reset shares", "Puts the party and raid shares and what you keep back to TwichUI's starting amounts. Nothing else changes.")
end

-- The canvas frame Settings.lua registers under Mage. Built the first time it is shown.
local function Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    local title = Text(f, "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 7, -22)
    title:SetText("Refreshment shares")
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("Options_HorizontalDivider", true)
    divider:SetPoint("TOP", 0, -50)
    f:SetScript("OnShow", function()
        if not built then Build(f) end
        RS.Refresh()
    end)
    -- No OnDefault: the game's "Defaults" for every setting shouldn't wipe hand-entered amounts; the page
    -- has its own reset.
    f.OnRefresh = RS.Refresh
    return f
end

function RS.Register(parentCategory)
    if not (Settings and Settings.RegisterCanvasLayoutSubcategory) then return end
    RS.category = Settings.RegisterCanvasLayoutSubcategory(parentCategory, Frame(), "Refreshment shares")
end

function RS.Show()
    if RS.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(RS.category:GetID())
    end
end

RF.OnChange(RS.Refresh)
