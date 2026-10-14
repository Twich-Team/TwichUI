-- TwichUI: stat weights page (TwichUI settings > Gear comparison > Stat weights; /twichui gear)
-- How each of your class's talent trees values stats: a stat priority you
-- rank, as guides give them, or stat weights you can change and reset.
-- A frame of its own, which the settings window shows as a page (TwichUI_Settings/pages/Gear.lua), since a
-- ranked list and a table of numbers don't fit the ordinary rows. It is built the first time it is shown, from
-- the settings window's controls (R.SettingsWidgets, there whenever the window is). Which tree is used and how
-- hints behave are ordinary settings on the Gear comparison page.

local R = TwichUI
local W, E, D, P, H = R.GearWeights, R.GearEval, R.GearData, R.GearPrefs, R.GearHints
local GW = {}
R.GearWindow = GW

local WIDTH = 640
local ROW_H = 22
local TOP = -2                 -- the settings window draws the page's title above
local f                        -- the page's frame
local built = false
local editTree                 -- skill line of the tree whose values are shown
local weights, priority = {}, {}

local ACCENT = { 0.79, 0.64, 0.29 }
local INK = { 0.93, 0.88, 0.76 }   -- the settings window's text

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if template == nil or template == "GameFontHighlight" then fs:SetTextColor(INK[1], INK[2], INK[3]) end
    return fs
end

local function Help(parent, text, y)
    local fs = Text(parent, "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 4, y)
    fs:SetWidth(WIDTH - 8)
    fs:SetTextColor(0.78, 0.74, 0.66)
    fs:SetText(text)
    return fs
end

-- Tooltips come from modules/Interact.lua; text may be a function giving the text and a reason the
-- control is unavailable.
local function Tip(frame, title, text) R.Interact.Tip(frame, title, text) end

local function Btn(parent, label, w, onClick, tooltip)
    local b = R.SettingsWidgets.Button(parent, label, w, "secondary", onClick)
    if tooltip then Tip(b, label, tooltip) end
    return b
end

-- The settings window's dropdown. choices(): { { value, label, tooltip }, ... }; onPick(value).
local function Dropdown(parent, width, choices, onPick)
    local dd = R.SettingsWidgets.Dropdown(parent, width, onPick)
    dd:SetChoices(choices)
    return dd
end

-- Shows a dropdown's current value by its label.
local function ShowChoice(dd, value)
    for _, choice in ipairs(dd.choices()) do
        if choice.value == value then dd:SetValue(value, choice.label) return end
    end
    dd:SetValue(value, "")
end

---------------------------------------------------------------------------
-- Stat weights
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
        R.Print("%s needs a number from 0 to 1000; \"%s\" wasn't used.", EDITOR_LABEL[row.stat] or E.Label(row.stat), text:sub(1, 20))
        GW:Refresh()
    end
end

-- A box still being typed in belongs to the tree it was typed for: let go of it (which keeps what
-- was typed, as leaving a box always does) before the tree, the way of valuing stats, or a reset
-- can change under it.
local function FinishEditing()
    for _, row in ipairs(weights.rows or {}) do
        if row.edit:HasFocus() then row.edit:ClearFocus() end
    end
end

local function WeightRow(content, i, stat)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(WIDTH - 70, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.stat = stat
    row.label = Text(row, "GameFontHighlight")
    row.label:SetPoint("LEFT", 8, 0)
    row.label:SetWidth(260)
    row.label:SetWordWrap(false)
    row.label:SetText(EDITOR_LABEL[stat] or E.Label(stat))
    row.unit = Text(row, "GameFontDisableSmall")
    row.unit:SetPoint("LEFT", 274, 0)
    row.unit:SetText(Unit(stat))
    row.edit = R.SettingsWidgets.EditBox(row, 56, 20)
    row.edit:SetPoint("RIGHT", -10, 0)
    row.edit:SetJustifyH("RIGHT")
    row.edit:SetScript("OnEnterPressed", row.edit.ClearFocus)
    row.edit:SetScript("OnEscapePressed", function(self) self.revert = true; self:ClearFocus() end)
    row.edit:SetScript("OnEditFocusLost", function() CommitWeight(row) end)
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
    return row
end

local WEIGHTS_HELP = "What one point of each stat is worth, next to the tree's main stat at 1. Ratings count per 1% at your level. Your changes show in gold; clear a box to put its default back."
local PRIORITY_HELP = "Rank the stats your guide lists, most important first. Each counts %d%% as much as the one above it, and stats you leave out count nothing. Weapon damage and armor keep this tree's weights."
local PRIORITY_SIDE = 166      -- room for the buttons beside the ranked list

local function Confirm(key, text, onAccept, opts)
    return R.Interact.Confirm(key, text, onAccept, opts)
end

local function Panel(p, y)
    local Wg = R.SettingsWidgets
    local box = CreateFrame("Frame", nil, p, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 0, y)
    box:SetPoint("BOTTOMRIGHT", 0, 6)
    Wg.Surface(box, Wg.pal.well, 0.9, Wg.pal.bronzeLo, 0.8)
    return box
end

local function ScrollContent(box, rightInset)
    local scroll, content = R.SettingsWidgets.Scroll(box, WIDTH - 70 - rightInset)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26 - rightInset, 6)
    return content
end

---------------------------------------------------------------------------
-- Stat priority
---------------------------------------------------------------------------
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
local function StartFromWeights(skillLine)
    skillLine = skillLine or editTree
    local tree = TreeDef(skillLine)
    local who = D.Character()
    local _, classFile = UnitClass("player")
    if not tree then return end
    P.SetPriority(classFile, skillLine, W.PriorityFromWeights(D.BaseWeights(classFile, tree.def), who and who.ratingScale))
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

local function ArrowButton(parent, dir)
    return R.SettingsWidgets.ArrowButton(parent, dir)
end

local function PriorityRow(content, i)
    local row = CreateFrame("Frame", nil, content)
    row:SetSize(WIDTH - 70 - PRIORITY_SIDE, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.num = Text(row, "GameFontNormal")
    row.num:SetPoint("LEFT", 6, 0)
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

---------------------------------------------------------------------------
-- Page
---------------------------------------------------------------------------
local function SetMode(mode)
    local _, classFile = UnitClass("player")
    -- The first time, start the list from the tree's weights.
    FinishEditing()
    if mode == "priority" and not P.Priority(classFile, editTree) then StartFromWeights() end
    P.SetUsesPriority(classFile, editTree, mode == "priority")
end

local function Build(p)
    built = true
    Help(p, "Each tree starts from TwichUI's rough weights, so nothing here has to be filled in; change them only to follow a guide. Which tree is used is chosen on the Gear comparison page.", TOP)

    local treeLabel = Text(p, "GameFontNormal")
    treeLabel:SetPoint("TOPLEFT", 4, TOP - 40)
    treeLabel:SetText("Talent tree")
    weights.tree = Dropdown(p, 180, function()
        local list = {}
        local who = D.Character()
        local using = who and who.basis and who.basis.skillLine
        for _, tree in ipairs(D.Trees() or {}) do
            list[#list + 1] = { value = tree.skillLine, label = tree.skillLine == using and (tree.name .. " (in use)") or tree.name }
        end
        return list
    end, function(skillLine)
        FinishEditing()
        editTree = skillLine
        GW:Refresh()
    end)
    weights.tree:SetPoint("LEFT", treeLabel, "RIGHT", 10, 0)

    local modeLabel = Text(p, "GameFontNormal")
    modeLabel:SetPoint("LEFT", weights.tree, "RIGHT", 24, 0)
    modeLabel:SetText("Value stats by")
    weights.mode = Dropdown(p, 150, function()
        return {
            { value = "priority", label = "Stat priority", tooltip = "Rank the stats your guide lists, like \"Strength > Hit > Critical Strike\". The simplest way to follow a guide." },
            { value = "weights", label = "Stat weights", tooltip = "Give each stat a number. More exact, if your guide or simulator gives stat weights." },
        }
    end, function(mode) SetMode(mode) end)
    weights.mode:SetPoint("LEFT", modeLabel, "RIGHT", 10, 0)

    -- The tree is fixed when the question is asked: picking another tree while it is open must not
    -- change what is reset.
    local function TreeNote(skillLine)
        local tree = TreeDef(skillLine)
        local className = UnitClass("player")
        return tree and ("%s (%s)"):format(tree.name, className or "your class") or "this tree"
    end
    local function StillThere(skillLine)
        return function()
            if not TreeDef(skillLine) then return false, "That talent tree isn't available any more, so nothing was changed." end
            return true
        end
    end
    weights.reset = Btn(p, "Reset weights", 120, function()
        local _, classFile = UnitClass("player")
        local tree = editTree
        if not tree then return end
        FinishEditing()
        Confirm("TWICHUI_GEAR_RESET", ("Put every stat weight for %s back to TwichUI's defaults?\n\nThe numbers you entered for this tree are lost. Other trees aren't changed. This can't be undone."):format(TreeNote(tree)),
            function()
                FinishEditing()
                P.ResetWeights(classFile, tree)
            end, { valid = StillThere(tree) })
    end, function()
        local custom = editTree and P.CustomWeights(select(2, UnitClass("player")), editTree)
        return "Puts every stat weight of this tree back to TwichUI's defaults.", not (custom and next(custom)) and "No weight has been changed for this tree." or nil
    end)
    weights.reset:SetPoint("TOPRIGHT", 0, TOP - 76)
    weights.help = Help(p, "", TOP - 76)
    weights.help:SetWidth(WIDTH - 8 - 140)

    -- Stat weights: every stat with an editable number.
    weights.box = Panel(p, TOP - 120)
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
    priority.box = Panel(p, TOP - 120)
    priority.content = ScrollContent(priority.box, PRIORITY_SIDE)
    priority.rows = {}
    for _ in pairs(W.ITEM_POINT) do
        priority.rows[#priority.rows + 1] = PriorityRow(priority.content, #priority.rows + 1)
    end
    priority.empty = Text(priority.box, "GameFontDisableSmall")
    priority.empty:SetPoint("TOPLEFT", 14, -14)
    priority.empty:SetWidth(WIDTH - 70 - PRIORITY_SIDE - 16)
    priority.empty:SetText("No stats ranked yet. Add the stats your guide lists, most important first, or start from this tree's weights. Until then, this tree is valued by its weights.")
    priority.add = Btn(priority.box, "Add a stat", 150, function(self) AddMenu(self) end, function()
        return "Pick a stat to add at the bottom of the list.", #RankedCopy() >= #priority.rows and "Every stat is already on the list." or nil
    end)
    priority.add:SetPoint("TOPRIGHT", -8, -8)
    priority.fill = Btn(priority.box, "Start from weights", 150, function()
        if #RankedCopy() == 0 then StartFromWeights() return end
        local tree = editTree
        Confirm("TWICHUI_GEAR_FILL", ("Replace your stat priority for %s with the stats its weights value most?\n\nThe list you ranked is lost. This can't be undone."):format(TreeNote(tree)),
            function() StartFromWeights(tree) end, { valid = StillThere(tree) })
    end, "Replaces the list with the stats this tree's weights value most, as a starting point.")
    priority.fill:SetPoint("TOP", priority.add, "BOTTOM", 0, -6)
    priority.clear = Btn(priority.box, "Clear list", 150, function()
        local tree = editTree
        Confirm("TWICHUI_GEAR_CLEAR", ("Clear your stat priority for %s?\n\nUntil you rank stats again, this tree is valued by its weights. This can't be undone."):format(TreeNote(tree)),
            function()
                local _, classFile = UnitClass("player")
                P.SetPriority(classFile, tree, nil)
            end, { valid = StillThere(tree) })
    end, function()
        return "Removes every stat, to build the list from your guide.", #RankedCopy() == 0 and "The list is already empty." or nil
    end)
    priority.clear:SetPoint("TOP", priority.fill, "BOTTOM", 0, -6)

    -- Shown instead of everything above for a class without weights.
    f.noClass = Help(p, "TwichUI has no stat weights for your class, so upgrade hints are not shown.", TOP - 40)
    f.noClass:Hide()
end

local function RefreshWeightRows(classFile, tree)
    local custom = P.CustomWeights(classFile, editTree) or {}
    for _, row in ipairs(weights.rows) do
        local default = tree.def.weights[row.stat] or 0
        local value = custom[row.stat]
        if not row.edit:HasFocus() then row.edit:SetText(Number(value or default)) end
        if value then
            row.label:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            row.default:SetText("default " .. Number(default))
        else
            row.label:SetTextColor(INK[1], INK[2], INK[3])
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

function GW:Refresh()
    if not (f and built and f:IsShown()) then return end
    local trees, classFile = D.Trees()
    local known = trees ~= nil
    f.noClass:SetShown(not known)
    weights.tree:SetShown(known)
    weights.mode:SetShown(known)
    if not known then
        weights.box:Hide(); priority.box:Hide(); weights.reset:Hide(); weights.help:SetText("")
        return
    end
    if not TreeDef(editTree) then
        local who = D.Character()
        editTree = (who and who.basis.skillLine) or trees[1].skillLine
    end
    local usesPriority = P.UsesPriority(classFile, editTree)
    ShowChoice(weights.tree, editTree)
    ShowChoice(weights.mode, usesPriority and "priority" or "weights")
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

-- The page's frame (the settings window shows it on the Stat weights page). Its contents are built the first
-- time it's shown, once your class is known.
local function Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build(f) end
        GW:Refresh()
    end)
    -- No reset of its own in "Reset this page": hand-entered weights are reset with the buttons on the page.
    H:OnChange(function() GW:Refresh() end)
    return f
end
GW.Frame = Frame

function GW:Show()
    if not D.Trees() then
        R.Print("upgrade hints have no weights for your class.")
        return
    end
    R:OpenSettings("statWeights")
end
