-- TwichUI: upgrade hints window (/twichui gear)
-- Two pages:
--   * Weights: which talent tree this character's gear is weighed for
--     (automatic, or your choice) and the stat weights of each of your
--     class's trees, which you can change and reset.
--   * Behaviour: what shows at a glance, how big a gain counts, how to reveal
--     the reasoning, and the optional bag icons.
-- Styled by EllesmereUI's skin toolkit when it's available, like /pack.

local R = TwichUI
local W, E, D, P, H = R.GearWeights, R.GearEval, R.GearData, R.GearPrefs, R.GearHints
local GW = {}
R.GearWindow = GW

local WIDTH, HEIGHT = 580, 560
local ROW_H = 22
local f
local page = "weights"
local editTree              -- skill line of the tree whose weights are shown
local fontStrings = {}
local weights, behaviour = {}, {}

---------------------------------------------------------------------------
-- Skin helpers: EllesmereUI's primitives when present, else a plain look
-- (the same approach as the /pack window).
---------------------------------------------------------------------------
local function Skin(kind, obj, ...)
    local S = R.S
    if not (S and S[kind] and obj) then return end
    pcall(S[kind], obj, ...)
end

local function Accent()
    local S = R.S
    if S and S.GetAccentColor then
        local ok, r, g, b = pcall(S.GetAccentColor)
        if ok and r then return r, g, b end
    end
    return 0.79, 0.64, 0.29
end

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fontStrings[#fontStrings + 1] = fs
    return fs
end

local function Help(parent, text, y, x)
    local fs = Text(parent, "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", x or 16, y)
    fs:SetWidth(WIDTH - 32 - ((x or 16) - 16))
    fs:SetTextColor(0.72, 0.70, 0.66)
    fs:SetText(text)
    return fs
end

local function Tip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(type(text) == "function" and text() or text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)
end

local function Btn(parent, label, w, onClick, tooltip)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if tooltip then Tip(b, label, tooltip) end
    Skin("Button", b)
    Skin("StateButtonLabel", b)
    return b
end

local function Check(parent, label, tooltip, onClick)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    c.label = Text(parent, "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 4, 0)
    c.label:SetText(label)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    if tooltip then Tip(c, label, tooltip) end
    Skin("Checkbox", c)
    return c
end

local function Section(parent, num, title, y)
    local n = Text(parent, "GameFontNormalLarge")
    n:SetPoint("TOPLEFT", 16, y)
    n:SetText(num)
    n:SetTextColor(Accent())
    local t = Text(parent, "GameFontNormal")
    t:SetPoint("LEFT", n, "RIGHT", 8, 0)
    t:SetText(title)
    t:SetTextColor(1, 1, 1)
    return n, t
end

-- Tab-look buttons, used for the page tabs and every "pick one" row.
local function TabBtn(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 24)
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontHighlight")
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if R.S then
        Skin("Tab", b)
    else
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(1, 1, 1, 0.04)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT")
        b.line:SetPoint("BOTTOMRIGHT")
        b.line:SetColorTexture(Accent())
        b.line:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
    end
    return b
end

local function Select(b, selected)
    if R.S and R.S.SetTabSelection then
        pcall(R.S.SetTabSelection, b, selected)
    elseif b.line then
        b.line:SetShown(selected)
        b:SetEnabled(not selected)
    end
end

-- A row of choices; options = { { value, label, width, tooltip } }.
local function Choices(parent, x, y, options, onPick)
    local row = { buttons = {} }
    local prev
    for i, option in ipairs(options) do
        local b = TabBtn(parent, option[2], option[3] or 110, function() onPick(option[1]) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", x, y) end
        if option[4] then
            b:SetMotionScriptsWhileDisabled(true)
            Tip(b, option[2], option[4])
        end
        b.value = option[1]
        row.buttons[i] = b
        prev = b
    end
    function row:Show(selected)
        for _, b in ipairs(self.buttons) do Select(b, b.value == selected) end
    end
    return row
end

---------------------------------------------------------------------------
-- Page: Weights
---------------------------------------------------------------------------
local EDITOR_LABEL = {
    MAINHAND_DPS = "Main-hand weapon damage per second",
    OFFHAND_DPS = "Off-hand weapon damage per second",
    RANGED_DPS = "Ranged weapon damage per second",
}

local function Unit(stat)
    if stat:find("_DPS$") then return "per 1 DPS" end
    if W.PER_SKILL_POINT[stat] then return "per skill point" end
    if W.RATINGS[stat] then return "per 1%" end
    return "per point"
end

local function Number(value)
    return ("%g"):format(value)
end

local function TreeDef(skillLine)
    local trees = D.Trees()
    for _, tree in ipairs(trees or {}) do
        if tree.skillLine == skillLine then return tree end
    end
end

local function CommitWeight(row)
    local eb = row.edit
    if eb.revert then
        eb.revert = nil
        GW:Refresh()
        return
    end
    local tree = TreeDef(editTree)
    local _, classFile = UnitClass("player")
    if not tree then return end
    local text = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local default = tree.def.weights[row.stat] or 0
    local value = tonumber(text)
    if text == "" then
        P.SetWeight(classFile, editTree, row.stat, nil)
    elseif value and value >= 0 and value <= 1000 then
        P.SetWeight(classFile, editTree, row.stat, value ~= default and value or nil)
    else
        R.Print("stat weights are numbers from 0 to 1000.")
        GW:Refresh()
    end
end

local function WeightRow(content, i, stat)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(WIDTH - 70, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.stat = stat
    row.label = Text(row, "GameFontHighlight")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetWidth(250)
    row.label:SetWordWrap(false)
    row.label:SetText(EDITOR_LABEL[stat] or E.Label(stat))
    row.unit = Text(row, "GameFontDisableSmall")
    row.unit:SetPoint("LEFT", 264, 0)
    row.unit:SetText(Unit(stat))
    row.edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row.edit:SetSize(56, 20)
    row.edit:SetPoint("RIGHT", -10, 0)
    row.edit:SetAutoFocus(false)
    row.edit:SetJustifyH("RIGHT")
    row.edit:SetScript("OnEnterPressed", row.edit.ClearFocus)
    row.edit:SetScript("OnEscapePressed", function(self) self.revert = true; self:ClearFocus() end)
    row.edit:SetScript("OnEditFocusLost", function() CommitWeight(row) end)
    Skin("EditBox", row.edit)
    row.default = Text(row, "GameFontDisableSmall")
    row.default:SetPoint("RIGHT", row.edit, "LEFT", -10, 0)
    row.default:SetJustifyH("RIGHT")
    return row
end

local function GroupRow(content, i, title)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(WIDTH - 70, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    local t = Text(row, "GameFontNormalSmall")
    t:SetPoint("BOTTOMLEFT", 4, 3)
    t:SetText(title:upper())
    t:SetTextColor(Accent())
    return row
end

local function BuildWeights(p)
    Section(p, "1", "Weigh gear for", -4)
    Help(p, "Automatic follows the talent tree you've put the most points into. Pick a tree to weigh this character's gear for it, whatever your points say.", -28)
    -- The tree buttons are made on first show, once your class is known.
    weights.choiceY = -62

    Section(p, "2", "Stat weights", -104)
    weights.reset = Btn(p, "Reset these weights", 150, function()
        local _, classFile = UnitClass("player")
        if editTree then P.ResetWeights(classFile, editTree) end
    end, "Puts every stat weight of this tree back to TwichUI's defaults.")
    weights.reset:SetPoint("TOPRIGHT", -16, -100)
    Help(p, "What one point of each stat is worth, next to the tree's main stat at 1. Ratings count per 1% at your level. Your changes show in gold; clear a box to put its default back.", -128)
    weights.editY = -164

    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, -196)
    box:SetPoint("BOTTOMRIGHT", -16, 14)
    if R.S then
        Skin("Panel", box, { inset = true })
    else
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    Skin("ScrollBar", scroll.ScrollBar)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(WIDTH - 70)
    scroll:SetScrollChild(content)

    weights.rows = {}
    local i = 0
    for _, group in ipairs(W.EDITOR) do
        i = i + 1
        GroupRow(content, i, group[1])
        for _, stat in ipairs(group[2]) do
            i = i + 1
            weights.rows[#weights.rows + 1] = WeightRow(content, i, stat)
        end
    end
    content:SetHeight(i * ROW_H)
end

-- Tree buttons for "Weigh gear for" and the weights editor.
local function BuildTreeChoices(p, trees)
    local choose = { { "auto", "Automatic", 176, "Weigh for the tree with the most talent points in your active talents." } }
    local edit = {}
    for _, tree in ipairs(trees) do
        choose[#choose + 1] = { tree.skillLine, tree.name, 118 }
        edit[#edit + 1] = { tree.skillLine, tree.name, 118 }
    end
    weights.choose = Choices(p, 16, weights.choiceY, choose, function(value)
        local skillLine = value ~= "auto" and value or nil
        if skillLine then editTree = skillLine end
        P.SetTreeChoice(skillLine)
    end)
    weights.edit = Choices(p, 16, weights.editY, edit, function(value)
        editTree = value
        GW:Refresh()
    end)
end

local function RefreshWeights()
    local trees, classFile, auto = D.Trees()
    if not trees then return end
    if not weights.choose then BuildTreeChoices(f.pageWeights, trees) end
    local who = D.Character()
    editTree = editTree or (who and who.basis.skillLine) or trees[1].skillLine

    weights.choose.buttons[1]:SetText(auto and ("Automatic (" .. auto.name .. ")") or "Automatic")
    weights.choose:Show(P.TreeChoice() or "auto")
    weights.edit:Show(editTree)

    local tree = TreeDef(editTree)
    local custom = P.CustomWeights(classFile, editTree) or {}
    local r, g, b = Accent()
    for _, row in ipairs(weights.rows) do
        local default = tree.def.weights[row.stat] or 0
        local value = custom[row.stat]
        if not row.edit:HasFocus() then row.edit:SetText(Number(value or default)) end
        if value then
            row.label:SetTextColor(r, g, b)
            row.default:SetText("default " .. Number(default))
        else
            row.label:SetTextColor(1, 1, 1)
            row.default:SetText("")
        end
    end
    weights.reset:SetEnabled(next(custom) ~= nil)
end

---------------------------------------------------------------------------
-- Page: Behaviour
---------------------------------------------------------------------------
local STRICTNESS_TEXT = {
    cautious = "Only clear gains: likely from %d%% better, possible from %d%%.",
    balanced = "Likely from %d%% better than what you wear, possible from %d%%.",
    eager = "Point out small gains too: likely from %d%% better, possible from %d%%.",
}

local REVEAL_TEXT = {
    compare = "Hold Shift (your compare-items key) over an item to see why.",
    alt = "Hold Alt over an item to see why.",
    ctrl = "Hold Ctrl over an item to see why.",
    always = "The reasoning shows under every item you could wear.",
}

local function BuildBehaviour(p)
    Section(p, "1", "Tooltips", -4)
    behaviour.hints = Check(p, "Show upgrade hints in item tooltips",
        "A quiet line such as \"Likely upgrade for Fury\" on gear that looks better than what you wear.",
        function(on) TwichUIDB.modules.gearHints = on end)
    behaviour.hints:SetPoint("TOPLEFT", 18, -28)
    behaviour.possible = Check(p, "Show possible upgrades too",
        "Also mark gear that looks a little better, or better apart from effects the estimate can't weigh. Off: only likely upgrades and empty slots.",
        function(on) P.Set("glancePossible", on) end)
    behaviour.possible:SetPoint("TOPLEFT", 18, -54)
    behaviour.future = Check(p, "Hint at gear for higher levels",
        "Gear you can't wear yet only because of its level gets a hint with that level, such as \"Likely upgrade at level 32\". Handy at the auction house.",
        function(on) P.Set("futureLevels", on) end)
    behaviour.future:SetPoint("TOPLEFT", 18, -80)

    Section(p, "2", "How big a gain counts", -118)
    behaviour.strict = Choices(p, 16, -144, {
        { "cautious", "Cautious", 110 },
        { "balanced", "Balanced", 110 },
        { "eager", "Eager", 110 },
    }, function(value) P.Set("strictness", value) end)
    behaviour.strictText = Help(p, "", -174)

    Section(p, "3", "Show the reasoning", -206)
    behaviour.reveal = Choices(p, 16, -232, {
        { "compare", "Hold Shift", 110 },
        { "alt", "Hold Alt", 110 },
        { "ctrl", "Hold Ctrl", 110 },
        { "always", "Always", 110 },
    }, function(value) P.Set("reveal", value) end)
    behaviour.revealText = Help(p, "", -262)

    Section(p, "4", "Bags", -294)
    behaviour.bags = Check(p, "Mark upgrades in my bags",
        "A small mark in the corner of bag slots holding gear the tooltip would call an upgrade. Fainter for possible upgrades.",
        function(on)
            TwichUIDB.modules.gearBagIcons = on
            R.GearBags.Refresh()
            GW:Refresh()
        end)
    behaviour.bags:SetPoint("TOPLEFT", 18, -318)
    local styles = {}
    for i, style in ipairs(R.GearBags.STYLES) do styles[i] = { style.key, style.label, 120 } end
    behaviour.style = Choices(p, 16, -350, styles, function(value) P.Set("bagStyle", value) end)
    behaviour.preview = p:CreateTexture(nil, "ARTWORK")
    behaviour.preview:SetPoint("LEFT", behaviour.style.buttons[#styles], "RIGHT", 16, 0)
    Help(p, "The marks use the game's own art. They show in Blizzard's bags, separate or combined; bag addons draw their own slots.", -382)
end

local function RefreshBehaviour()
    local modules = TwichUIDB.modules
    behaviour.hints:SetChecked(modules.gearHints ~= false)
    behaviour.possible:SetChecked(P.Get("glancePossible"))
    behaviour.future:SetChecked(P.Get("futureLevels"))

    local strictness = P.Get("strictness")
    local numbers = P.STRICTNESS[strictness] or P.STRICTNESS.balanced
    behaviour.strict:Show(strictness)
    behaviour.strictText:SetText((STRICTNESS_TEXT[strictness] or STRICTNESS_TEXT.balanced)
        :format(math.floor(numbers.likely * 100 + 0.5), math.floor(numbers.possible * 100 + 0.5)))

    local reveal = P.Get("reveal")
    behaviour.reveal:Show(reveal)
    behaviour.revealText:SetText(REVEAL_TEXT[reveal] or REVEAL_TEXT.compare)

    local bags = modules.gearBagIcons == true
    behaviour.bags:SetChecked(bags)
    behaviour.style:Show(P.Get("bagStyle"))
    R.GearBags.ApplyStyle(behaviour.preview, P.Get("bagStyle"))
    behaviour.preview:SetAlpha(bags and 1 or 0.4)
    for _, b in ipairs(behaviour.style.buttons) do b:SetAlpha(bags and 1 or 0.5) end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SetPage(which)
    page = which
    f.pageWeights:SetShown(which == "weights")
    f.pageBehaviour:SetShown(which == "behaviour")
    Select(f.tabWeights, which == "weights")
    Select(f.tabBehaviour, which == "behaviour")
    GW:Refresh()
end

local function Build()
    f = CreateFrame("Frame", "TwichUIGearWindow", UIParent, "BackdropTemplate")
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "TwichUIGearWindow")

    if R.S then
        Skin("Shell", f)
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.07, 0.065, 0.06, 0.97)
        f:SetBackdropBorderColor(0.25, 0.23, 0.2, 1)
    end

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 12, -8)
    logo:SetTexture(R.ICON)
    local title = Text(f, "GameFontNormalLarge")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetText("TwichUI")
    title:SetTextColor(1, 1, 1)
    local sub = Text(f, "GameFontDisableSmall")
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText("upgrade hints")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    Skin("CloseButton", close)

    f.tabWeights = TabBtn(f, "Weights", 130, function() SetPage("weights") end)
    f.tabWeights:SetPoint("TOPLEFT", 14, -40)
    f.tabBehaviour = TabBtn(f, "Behaviour", 130, function() SetPage("behaviour") end)
    f.tabBehaviour:SetPoint("LEFT", f.tabWeights, "RIGHT", 4, 0)

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 12, -66)
    line:SetPoint("TOPRIGHT", -12, -66)

    f.pageWeights = CreateFrame("Frame", nil, f)
    f.pageWeights:SetPoint("TOPLEFT", 0, -74)
    f.pageWeights:SetPoint("BOTTOMRIGHT")
    f.pageBehaviour = CreateFrame("Frame", nil, f)
    f.pageBehaviour:SetPoint("TOPLEFT", 0, -74)
    f.pageBehaviour:SetPoint("BOTTOMRIGHT")
    BuildWeights(f.pageWeights)
    BuildBehaviour(f.pageBehaviour)

    if R.S then for _, fs in ipairs(fontStrings) do Skin("Font", fs) end end

    f:SetScript("OnShow", function() GW:Refresh() end)
    H:OnChange(function() GW:Refresh() end)
end

function GW:Refresh()
    if not f or not f:IsShown() then return end
    if page == "weights" then RefreshWeights() else RefreshBehaviour() end
end

function GW:Show(which)
    if not D.Trees() then
        R.Print("upgrade hints have no weights for your class.")
        return
    end
    if not f then Build() end
    f:Show()
    SetPage(which or page)
end

function GW:Toggle()
    if f and f:IsShown() then f:Hide() else GW:Show() end
end
