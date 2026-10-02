-- TwichUI: upgrade hints window (/twichui gear)
-- Two pages:
--   * Weights: which talent tree this character's gear is weighed for
--     (automatic, or your choice), and how each of your class's trees values
--     stats: a stat priority you rank, as guides give them, or stat weights
--     you can change and reset.
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

-- UIPanelScrollFrameTemplate uses the old UIPanelScrollBarTemplate (Slider with
-- ScrollUp/ScrollDownButton and a ThumbTexture), which S.ScrollBar doesn't
-- recognise. Flatten it to the same thin white thumb by hand.
local function SkinLegacyScrollBar(scroll)
    if not R.S then return end
    local bar = scroll.ScrollBar
    if not bar then return end
    for _, key in ipairs({ "ScrollUpButton", "ScrollDownButton" }) do
        local button = bar[key]
        if button then
            for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
                local texture = button[getter] and button[getter](button)
                if texture then texture:SetAlpha(0) end
            end
            button:EnableMouse(false)
            button:SetAlpha(0)
        end
    end
    for i = 1, select("#", bar:GetRegions()) do
        local region = select(i, bar:GetRegions())
        if region and region ~= bar.ThumbTexture and region:GetObjectType() == "Texture" then region:SetAlpha(0) end
    end
    local thumb = bar.ThumbTexture
    if thumb then
        thumb:SetTexCoord(0, 1, 0, 1)
        thumb:SetColorTexture(1, 1, 1, 0.3)
        thumb:SetSize(4, 24)
    end
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

local WEIGHTS_HELP = "What one point of each stat is worth, next to the tree's main stat at 1. Ratings count per 1% at your level. Your changes show in gold; clear a box to put its default back."
local PRIORITY_HELP = "Rank the stats your guide lists, most important first. Each counts %d%% as much as the one above it, and stats you leave out count nothing. Weapon damage and armor keep this tree's weights."
local PRIORITY_SIDE = 166      -- room for the buttons beside the ranked list
local priority = {}

local function Confirm(key, text, onAccept)
    StaticPopupDialogs[key] = {
        text = text, button1 = ACCEPT, button2 = CANCEL, OnAccept = onAccept,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show(key)
end

local function Panel(p, y)
    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 16, y)
    box:SetPoint("BOTTOMRIGHT", -16, 14)
    if R.S then
        Skin("Panel", box, { inset = true })
    else
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        box:SetBackdropColor(0, 0, 0, 0.35)
        box:SetBackdropBorderColor(1, 1, 1, 0.08)
    end
    return box
end

local function ScrollContent(box, rightInset)
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26 - rightInset, 6)
    SkinLegacyScrollBar(scroll)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 70 - rightInset, 1)
    scroll:SetScrollChild(content)
    return content
end

-- The ranked list of the tree being edited, as a copy to change and save.
local function RankedCopy()
    local _, classFile = UnitClass("player")
    local copy = {}
    for i, stat in ipairs(P.Priority(classFile, editTree) or {}) do copy[i] = stat end
    return copy, classFile
end

local function MoveStat(from, to)
    local list, classFile = RankedCopy()
    if to < 1 or to > #list then return end
    list[from], list[to] = list[to], list[from]
    P.SetPriority(classFile, editTree, list)
end

local function RemoveStat(index)
    local list, classFile = RankedCopy()
    table.remove(list, index)
    P.SetPriority(classFile, editTree, list)
end

local function AddStat(stat)
    local list, classFile = RankedCopy()
    list[#list + 1] = stat
    P.SetPriority(classFile, editTree, list)
end

-- Replaces the list with the stats this tree's weights value most.
local function StartFromWeights()
    local tree = TreeDef(editTree)
    local who = D.Character()
    local _, classFile = UnitClass("player")
    if not tree then return end
    P.SetPriority(classFile, editTree, W.PriorityFromWeights(D.BaseWeights(classFile, tree.def), who and who.ratingScale))
end

-- A menu of the stats not ranked yet, grouped like the weights editor.
local function AddMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    local ranked = {}
    for _, stat in ipairs(RankedCopy()) do ranked[stat] = true end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Add to the bottom of the list")
        for _, group in ipairs(W.EDITOR) do
            local submenu
            for _, stat in ipairs(group[2]) do
                if W.ITEM_POINT[stat] and not ranked[stat] then
                    submenu = submenu or root:CreateButton(group[1])
                    submenu:CreateButton(E.Label(stat), function() AddStat(stat) end)
                end
            end
        end
    end)
end

-- Move-up / move-down button: EllesmereUI's flat page button turned to point
-- up or down, else the stock scroll arrows.
local function ArrowButton(parent, dir)
    local S = R.S
    if S and S.PageButton then
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(18, 18)
        Skin("PageButton", b, "<", 12)
        -- PageButton adds its arrow last; it points left, so turn it.
        local arrow
        for i = 1, select("#", b:GetRegions()) do
            local region = select(i, b:GetRegions())
            if region and region:GetObjectType() == "Texture" and region:GetDrawLayer() == "OVERLAY" then arrow = region end
        end
        if arrow then arrow:SetRotation(dir == "up" and -math.pi / 2 or math.pi / 2) end
        return b
    end
    local b = CreateFrame("Button", nil, parent,
        dir == "up" and "UIPanelScrollUpButtonTemplate" or "UIPanelScrollDownButtonTemplate")
    b:SetMotionScriptsWhileDisabled(true)
    return b
end

local function PriorityRow(content, i)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(WIDTH - 70 - PRIORITY_SIDE, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.num = Text(row, "GameFontNormal")
    row.num:SetPoint("LEFT", 6, 0)
    row.num:SetTextColor(Accent())
    row.label = Text(row, "GameFontHighlight")
    row.label:SetPoint("LEFT", 30, 0)
    row.label:SetWidth(WIDTH - 70 - PRIORITY_SIDE - 140)
    row.label:SetWordWrap(false)
    row.share = Text(row, "GameFontDisableSmall")
    row.share:SetPoint("RIGHT", -68, 0)
    row.share:SetJustifyH("RIGHT")
    row.up = ArrowButton(row, "up")
    row.up:SetPoint("RIGHT", -44, 0)
    row.up:SetScript("OnClick", function() MoveStat(row.index, row.index - 1) end)
    Tip(row.up, "Move up", "Counts more.")
    row.down = ArrowButton(row, "down")
    row.down:SetPoint("RIGHT", -24, 0)
    row.down:SetScript("OnClick", function() MoveStat(row.index, row.index + 1) end)
    Tip(row.down, "Move down", "Counts less.")
    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(14, 14)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.remove:SetNormalTexture([[Interface\Buttons\UI-GroupLoot-Pass-Up]])
    row.remove:SetHighlightTexture([[Interface\Buttons\UI-GroupLoot-Pass-Up]], "ADD")
    row.remove:SetScript("OnClick", function() RemoveStat(row.index) end)
    Tip(row.remove, "Remove", "Take it off the list; it then counts nothing.")
    return row
end

local function BuildWeights(p)
    Section(p, "1", "Weigh gear for", -4)
    Help(p, "Automatic follows the talent tree you've put the most points into. Pick a tree to weigh this character's gear for it, whatever your points say.", -28)
    -- The tree buttons are made on first show, once your class is known.
    weights.choiceY = -62

    Section(p, "2", "How stats are valued", -104)
    weights.editY = -130
    local modeLabel = Text(p, "GameFontHighlightSmall")
    modeLabel:SetPoint("TOPLEFT", 16, -168)
    modeLabel:SetText("Value stats by")
    weights.mode = Choices(p, 110, -162, {
        { "priority", "Stat priority", 120, "Rank the stats your guide lists, like \"Strength > Hit > Critical Strike\". The simplest way to follow a guide." },
        { "weights", "Stat weights", 120, "Give each stat a number. More exact, if your guide or simulator gives stat weights." },
    }, function(mode)
        local _, classFile = UnitClass("player")
        -- The first time, start the list from the tree's weights.
        if mode == "priority" and not P.Priority(classFile, editTree) then StartFromWeights() end
        P.SetUsesPriority(classFile, editTree, mode == "priority")
    end)
    weights.reset = Btn(p, "Reset these weights", 150, function()
        local _, classFile = UnitClass("player")
        if editTree then P.ResetWeights(classFile, editTree) end
    end, "Puts every stat weight of this tree back to TwichUI's defaults.")
    weights.reset:SetPoint("TOPRIGHT", -16, -162)
    weights.help = Help(p, "", -194)

    -- Stat weights: every stat with an editable number.
    weights.box = Panel(p, -226)
    local content = ScrollContent(weights.box, 0)
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

    -- Stat priority: the ranked list, and buttons to change it.
    priority.box = Panel(p, -226)
    priority.content = ScrollContent(priority.box, PRIORITY_SIDE)
    priority.rows = {}
    for _ in pairs(W.ITEM_POINT) do
        priority.rows[#priority.rows + 1] = PriorityRow(priority.content, #priority.rows + 1)
    end
    priority.empty = Text(priority.box, "GameFontDisableSmall")
    priority.empty:SetPoint("TOPLEFT", 14, -14)
    priority.empty:SetWidth(WIDTH - 70 - PRIORITY_SIDE - 16)
    priority.empty:SetText("No stats ranked yet. Add the stats your guide lists, most important first, or start from this tree's weights. Until then, this tree is valued by its weights.")
    priority.add = Btn(priority.box, "Add a stat", 150, function(self) AddMenu(self) end,
        "Pick a stat to add at the bottom of the list.")
    priority.add:SetPoint("TOPRIGHT", -8, -8)
    priority.fill = Btn(priority.box, "Start from weights", 150, function()
        if #RankedCopy() == 0 then StartFromWeights() return end
        Confirm("TWICHUI_GEAR_FILL", "Replace your stat priority for this tree with the stats its weights value most?", StartFromWeights)
    end, "Replaces the list with the stats this tree's weights value most, as a starting point.")
    priority.fill:SetPoint("TOP", priority.add, "BOTTOM", 0, -6)
    priority.clear = Btn(priority.box, "Clear list", 150, function()
        Confirm("TWICHUI_GEAR_CLEAR", "Clear your stat priority for this tree?", function()
            local _, classFile = UnitClass("player")
            P.SetPriority(classFile, editTree, nil)
        end)
    end, "Removes every stat, to build the list from your guide.")
    priority.clear:SetPoint("TOP", priority.fill, "BOTTOM", 0, -6)
end

-- Tree buttons for "Weigh gear for" and the tree being edited.
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

local function RefreshWeightRows(classFile, tree)
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

local function RefreshPriority(classFile)
    local list = P.Priority(classFile, editTree) or {}
    local share = 1
    for i, row in ipairs(priority.rows) do
        local stat = list[i]
        if stat then
            row.index = i
            row.num:SetText(i .. ".")
            row.label:SetText(E.Label(stat))
            row.share:SetText(("%d%%"):format(math.floor(share * 100 + 0.5)))
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #list)
            row:Show()
            share = share * W.PRIORITY_STEP
        else
            row:Hide()
        end
    end
    priority.content:SetHeight(math.max(1, #list * ROW_H))
    priority.empty:SetShown(#list == 0)
    priority.add:SetEnabled(#list < #priority.rows)
    priority.clear:SetEnabled(#list > 0)
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

    local usesPriority = P.UsesPriority(classFile, editTree)
    weights.mode:Show(usesPriority and "priority" or "weights")
    weights.box:SetShown(not usesPriority)
    weights.reset:SetShown(not usesPriority)
    priority.box:SetShown(usesPriority)
    if usesPriority then
        weights.help:SetText(PRIORITY_HELP:format(math.floor(W.PRIORITY_STEP * 100 + 0.5)))
        RefreshPriority(classFile)
    else
        weights.help:SetText(WEIGHTS_HELP)
        RefreshWeightRows(classFile, TreeDef(editTree))
    end
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
