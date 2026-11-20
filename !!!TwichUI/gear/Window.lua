-- TwichUI: stat weights page (TwichUI settings > Gear comparison > Stat weights; /twichui gear)
-- How each of your class's talent trees values stats: a stat priority you rank, as guides give them, or stat
-- weights you can change and reset.
-- A frame of its own, which the settings window shows as a page (TwichUI_Settings/pages/Gear.lua), since a
-- ranked list and a table of numbers don't fit the ordinary rows. It is built the first time it is shown, from
-- the settings window's controls (R.SettingsWidgets and R.SettingsMaterial, there whenever the window is), in
-- the same family as the Loot rules page and the Reminders When builder: your talent trees as cards on top,
-- and under them the chosen tree's editor.
--   Stat priority: your ranking as cards. Drag a card to move it (a gold line shows where it lands), drag a
--                  stat in from "Not ranked" to rank it, drag a card out onto "Not ranked" to take it off. A click
--                  on a stat adds it at the bottom, and the "..." menu on a card moves it without dragging.
--   Stat weights:  every stat's number, in a card per group, with a way back to the default for the ones you changed.
-- Which tree is used and how hints behave are ordinary settings on the Gear comparison page. Nothing here
-- changes equipment: every change goes through gear/Prefs.lua, which is also what the hints read.

local R = TwichUI
local W, E, D, P, H = R.GearWeights, R.GearEval, R.GearData, R.GearPrefs, R.GearHints
local GW = {}
R.GearWindow = GW

local PAD, GAP = 14, 8
local W_MIN = 644
local TREE_H = 56
local ROW_H, ROW_GAP = 34, 3
local WEIGHT_H = 30
local CHIP_H, CHIP_GAP = 24, 6
local HEAD_H = 24
local PAGE = "statWeights"

local f                        -- the page's frame
local built = false
local editTree                 -- skill line of the tree whose values are shown
local selectedGroup = "all"
local relayout = false
local treeCards, rankRows, chips, weightRows, groupBoxes = {}, {}, {}, {}, {}
local dragging                 -- { stat, from } while a stat is carried

local function Wg() return R.SettingsWidgets end
local function Mat() return R.SettingsMaterial end

local function Tone(fs, tone)
    local G = Wg()
    local pal = G.pal
    G.Color(fs, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or (tone == "quiet" and pal.stone or pal.textDim)))
end

local function Put(item, parent, x, y)
    item:ClearAllPoints()
    item:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    item:Show()
end

local function Tip(frame, title, text) R.Interact.Tip(frame, title, text) end

local function Confirm(key, text, onAccept, opts)
    return R.Interact.Confirm(key, text, onAccept, opts)
end

---------------------------------------------------------------------------
-- Words and numbers
---------------------------------------------------------------------------
local EDITOR_LABEL = {
    MAINHAND_DPS = "Main-hand weapon damage per second",
    OFFHAND_DPS = "Off-hand weapon damage per second",
    RANGED_DPS = "Ranged weapon damage per second",
}

local function Label(stat) return EDITOR_LABEL[stat] or E.Label(stat) end

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

local function ClassFile() return select(2, UnitClass("player")) end

local WEIGHTS_HELP = "A number for each stat, relative to the tree's main stat: per point, and for ratings per 1%. Changed numbers are marked in gold; clear a field, or press Reset, to go back to TwichUI's default."
local PRIORITY_HELP = "Rank the stats your guide lists, most important first. Each counts %d%% as much as the one above it, and stats you leave out count nothing. Weapon damage and armor keep this tree's weights."
local SOURCE = "Source: TwichUI defaults with your manual changes. Editing affects upgrade estimates, not your equipment."
-- Shown first: the defaults need nothing, a priority is the usual change, numbers are the advanced one.
local DEFAULTS_HELP = "Nothing to set up: TwichUI's own rough weights for this tree are used until you change something. To follow a guide, rank its stats under Stat priority. Advanced weights are for guides or simulators that give exact numbers."
local LIMITS = "Hints are estimates from an item's stats, not a simulation: \"Use:\" and \"Chance on hit:\" effects aren't weighed."

---------------------------------------------------------------------------
-- Stat priority: the list as data
---------------------------------------------------------------------------
-- The ranked list of the tree being edited, as a copy to change and save.
local function RankedCopy()
    local copy = {}
    for i, stat in ipairs(P.Priority(ClassFile(), editTree) or {}) do copy[i] = stat end
    return copy, ClassFile()
end

local function Save(list)
    P.SetPriority(ClassFile(), editTree, list)
end

local function MoveStat(from, to)
    local list = RankedCopy()
    if from < 1 or from > #list then return end
    to = math.max(1, math.min(#list, to))
    if to == from then return end
    local stat = table.remove(list, from)
    table.insert(list, to, stat)
    Save(list)
end

local function RemoveStat(index)
    local list = RankedCopy()
    if not list[index] then return end
    table.remove(list, index)
    Save(list)
end

-- Puts a stat in at a place (1 is the top, #list + 1 the bottom); a stat already ranked moves instead.
local function PlaceStat(stat, slot)
    local list = RankedCopy()
    for i, ranked in ipairs(list) do
        if ranked == stat then
            if i < slot then slot = slot - 1 end
            table.remove(list, i)
            break
        end
    end
    table.insert(list, math.max(1, math.min(#list + 1, slot)), stat)
    Save(list)
end

local function AddStat(stat) PlaceStat(stat, math.huge) end

-- Replaces the list with the stats this tree's weights value most.
local function StartFromWeights(skillLine)
    skillLine = skillLine or editTree
    local tree = TreeDef(skillLine)
    local who = D.Character()
    if not tree then return end
    P.SetPriority(ClassFile(), skillLine, W.PriorityFromWeights(D.BaseWeights(ClassFile(), tree.def), who and who.ratingScale))
end

-- Stats that can be ranked, in the weights editor's order and groups.
local function Rankable()
    local out = {}
    for _, group in ipairs(W.EDITOR) do
        local stats = {}
        for _, stat in ipairs(group[2]) do
            if W.ITEM_POINT[stat] then stats[#stats + 1] = stat end
        end
        if #stats > 0 then out[#out + 1] = { name = group[1], stats = stats } end
    end
    return out
end

---------------------------------------------------------------------------
-- Weights: committing a typed number
---------------------------------------------------------------------------
local function CommitWeight(row)
    local eb = row.edit
    if eb.revert then
        eb.revert = nil
        GW:Refresh()
        return
    end
    local tree = TreeDef(editTree)
    if not tree then return end
    local classFile = ClassFile()
    local text = (eb:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local default = tree.def.weights[row.stat] or 0
    local value = tonumber(text)
    if text == "" then
        P.SetWeight(classFile, editTree, row.stat, nil)
    elseif value and value >= 0 and value <= 1000 then
        P.SetWeight(classFile, editTree, row.stat, value ~= default and value or nil)
    else
        R.Print("%s needs a number from 0 to 1000; \"%s\" wasn't used.", Label(row.stat), text:sub(1, 20))
        GW:Refresh()
    end
end

-- A box still being typed in belongs to the tree it was typed for: let go of it (which keeps what
-- was typed, as leaving a box always does) before the tree, the way of valuing stats, or a reset
-- can change under it.
local function FinishEditing()
    for _, row in ipairs(weightRows) do
        if row.edit:HasFocus() then row.edit:ClearFocus() end
    end
end

---------------------------------------------------------------------------
-- Dragging: the virtual drag of the settings window (Magic Inventory's), with a gold line where a card will land
---------------------------------------------------------------------------
local marker, ghost

local function DragKit()
    local inventory = R.MagicInventoryPage
    return inventory and inventory.Drag
end

local function Bounds(frame)
    local l, r, b, t = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
    if not (l and r and b and t) then return end
    local scale = frame:GetEffectiveScale()
    return l * scale, r * scale, b * scale, t * scale
end

local function Over(frame, x, y)
    if not (frame and frame:IsVisible()) then return end
    local l, r, b, t = Bounds(frame)
    if l and x >= l and x <= r and y >= b and y <= t then return l, r, b, t end
end

local function DragParts()
    if marker then return end
    local G, M = Wg(), Mat()
    marker = CreateFrame("Frame", nil, UIParent)
    marker:SetFrameStrata("TOOLTIP")
    marker:SetSize(1, 2)
    marker:EnableMouse(false)
    G.Solid(marker, "ARTWORK", G.pal.bronzeText, 1):SetAllPoints()
    marker:Hide()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetSize(190, 30)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:EnableMouse(false)
    M.PanelFace(ghost, "walnut")
    M.Edge(ghost, "control", 8):SetBackdropBorderColor(0.72, 0.58, 0.36, 0.9)
    ghost.title = G.Text(ghost, "body")
    ghost.title:SetWidth(170)
    ghost.title:SetMaxLines(1)
    ghost.title:SetWordWrap(false)
    ghost.title:SetPoint("LEFT", 12, 0)
    ghost:Hide()
end

-- Where a carried stat would go: { slot } on the ranking (1 to #list + 1), { off = true } over "Not ranked" for a
-- ranked stat (taking it off), or nothing. A drop that would change nothing is not a target, so no line shows for it.
local function FindDrop()
    local src = dragging
    if not src then return end
    local x, y = GetCursorPosition()
    local list = RankedCopy()
    if Over(f.rankBox, x, y) then
        local slot = #list + 1
        for i = 1, #list do
            local row = rankRows[i]
            local _, _, b, t = Bounds(row)
            if b and y > (b + t) / 2 then slot = i; break end
        end
        if src.from and (slot == src.from or slot == src.from + 1) then return end
        return { slot = slot }
    end
    if src.from and Over(f.palette, x, y) then return { off = true } end
end

local function PaintDrop(drop)
    if not marker then return end
    f.paletteHot:SetShown(drop ~= nil and drop.off == true)
    if not (drop and drop.slot) then marker:Hide(); return end
    local list = RankedCopy()
    local l, r, b, t
    local cl, cr = Bounds(f.rankBox)
    if drop.slot <= #list then
        l, r, b, t = Bounds(rankRows[drop.slot])
    elseif #list > 0 then
        l, r, b, t = Bounds(rankRows[#list])
    end
    if not (cl and (l or #list == 0)) then marker:Hide(); return end
    local y
    if #list == 0 then
        local _, _, bb, tt = Bounds(f.rankBox)
        y = tt - 10 * f.rankBox:GetEffectiveScale()
    elseif drop.slot <= #list then
        y = t + (ROW_GAP / 2) * f.rankBox:GetEffectiveScale()
    else
        y = b - (ROW_GAP / 2) * f.rankBox:GetEffectiveScale()
    end
    local scale = UIParent:GetEffectiveScale()
    marker:ClearAllPoints()
    marker:SetWidth(math.max(1, (cr - cl) / scale - 8))
    marker:SetPoint("LEFT", UIParent, "BOTTOMLEFT", cl / scale + 4, y / scale)
    marker:Show()
end

local function EndDrag()
    dragging = nil
    if marker then marker:Hide() end
    if f and f.paletteHot then f.paletteHot:Hide() end
    for _, row in ipairs(rankRows) do row:SetAlpha(1) end
end

local function StartDrag(stat, from)
    local kit = DragKit()
    if not (kit and f and editTree) then return false end
    if P.UsesPriority(ClassFile(), editTree) ~= true then return false end
    DragParts()
    if kit.Active() then kit.Cancel() end
    dragging = { stat = stat, from = from }
    ghost:SetScale(f:GetEffectiveScale() / UIParent:GetEffectiveScale())
    ghost.title:SetText(Label(stat))
    if from and rankRows[from] then rankRows[from]:SetAlpha(0.45) end
    local source = dragging
    kit.Start({ src = source, ghost = ghost,
        find = FindDrop,
        hover = function(drop) if dragging == source then PaintDrop(drop) end end,
        drop = function(src, drop)
            EndDrag()
            if drop.off then RemoveStat(src.from) else PlaceStat(src.stat, drop.slot) end
        end,
        cancel = function() EndDrag() end,
    })
    return true
end

-- Bound to a frame that carries a stat when dragged.
local function Draggable(frame, source)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() local stat, from = source(); if stat then StartDrag(stat, from) end end)
    frame:SetScript("OnDragStop", function()
        local kit = DragKit()
        if kit and dragging and kit.Source() == dragging then kit.Stop() end
    end)
end

local function CancelDrag()
    local kit = DragKit()
    if kit and dragging and kit.Source() == dragging then kit.Cancel() end
    EndDrag()
end

---------------------------------------------------------------------------
-- The trees, as cards
---------------------------------------------------------------------------
local function TreeSummary(tree)
    local classFile = ClassFile()
    if P.UsesPriority(classFile, tree.skillLine) then
        local n = #(P.Priority(classFile, tree.skillLine) or {})
        return n > 0 and ("Stat priority  ·  %d stats ranked"):format(n) or "Stat priority  ·  nothing ranked yet", n > 0 and "ok" or "quiet"
    end
    local custom = P.CustomWeights(classFile, tree.skillLine)
    local changed = 0
    for _ in pairs(custom or {}) do changed = changed + 1 end
    if changed > 0 then return ("Stat weights  ·  %d changed"):format(changed), "ok" end
    return "Stat weights  ·  TwichUI's defaults", "quiet"
end

local function Select(skillLine)
    if skillLine == editTree then return end
    FinishEditing()
    CancelDrag()
    editTree = skillLine
    GW:Refresh()
end

local function TreeCard(i)
    if treeCards[i] then return treeCards[i] end
    local G, M = Wg(), Mat()
    local card = CreateFrame("Button", nil, f)
    M.PanelFace(card, "walnut")
    M.ReminderRow(card)          -- card.sel: the chosen card's raised sheet
    M.MaterialHover(card)
    card.name = G.Text(card, "body")
    card.name:SetPoint("TOPLEFT", 14, -11)
    card.name:SetWordWrap(false)
    card.use = G.Text(card, "meta")
    card.use:SetPoint("TOPRIGHT", -10, -12)
    card.use:SetText("In use")
    card.state = G.Text(card, "small")
    card.state:SetPoint("BOTTOMLEFT", 14, 10)
    card.state:SetWordWrap(false)
    card:SetScript("OnClick", function() if card.skillLine then Select(card.skillLine) end end)
    Tip(card, "Talent tree", function() return "Choose which tree's stat values to see and change. Each tree keeps its own." .. (card.using and "\n\nThis is the tree your gear is weighed for right now." or "") end)
    treeCards[i] = card
    return card
end

---------------------------------------------------------------------------
-- The ranking's cards, and the stats still to rank
---------------------------------------------------------------------------
local function Grip(parent)
    local G = Wg()
    local grip = CreateFrame("Frame", nil, parent)
    grip:SetSize(16, 24)
    for i = 1, 6 do
        local dot = G.Solid(grip, "ARTWORK", G.pal.bronzeText, 0.8)
        dot:SetTexture(R.PATH .. [[media\style-v2\switch-thumb.tga]])
        dot:SetVertexColor(0.64, 0.52, 0.34, 0.85)
        dot:SetSize(3, 3)
        dot:SetPoint("CENTER", i % 2 == 0 and 2 or -2, 5 - 5 * math.floor((i - 1) / 2))
    end
    return grip
end

local function RankRow(i)
    if rankRows[i] then return rankRows[i] end
    local G, M = Wg(), Mat()
    local row = CreateFrame("Button", nil, f.rankBox)
    row:SetHeight(ROW_H)
    M.PanelFace(row, "walnut")
    M.MaterialHover(row)
    row.grip = Grip(row)
    row.grip:SetPoint("LEFT", 8, 0)
    row.num = G.Text(row, "heading")
    row.num:SetPoint("LEFT", 32, 0)
    row.num:SetWidth(26)
    row.num:SetJustifyH("RIGHT")
    row.label = G.Text(row, "body")
    row.label:SetPoint("LEFT", 66, 0)
    row.label:SetWordWrap(false)
    row.share = G.Text(row, "small")
    row.share:SetJustifyH("RIGHT")
    row.share:SetWidth(42)
    row.more = G.Button(row, "···", 28, "secondary", function()
        local index = row.index
        if not index then return end
        local list = RankedCopy()
        local choices = {}
        if index > 1 then
            choices[#choices + 1] = { value = "top", label = "Move to the top" }
            choices[#choices + 1] = { value = "up", label = "Move up" }
        end
        if index < #list then
            choices[#choices + 1] = { value = "down", label = "Move down" }
            choices[#choices + 1] = { value = "bottom", label = "Move to the bottom" }
        end
        choices[#choices + 1] = { value = "remove", label = "Take off the list" }
        G.ContextMenu(row.more, choices, function(action)
            if action == "top" then MoveStat(index, 1)
            elseif action == "up" then MoveStat(index, index - 1)
            elseif action == "down" then MoveStat(index, index + 1)
            elseif action == "bottom" then MoveStat(index, #list)
            elseif action == "remove" then RemoveStat(index) end
        end)
    end)
    row.more:SetPoint("RIGHT", -6, 0)
    row.share:SetPoint("RIGHT", row.more, "LEFT", -10, 0)
    row.label:SetPoint("RIGHT", row.share, "LEFT", -8, 0)
    Tip(row.more, "Move or remove", "Move this stat without dragging it, or take it off the list.")
    Tip(row, "Drag to move", function() return "Counts " .. (row.shareText or "") .. " of the top stat. Drag it up or down, or drag it onto \"Not ranked\" to take it off the list." end)
    Draggable(row, function() if row.index then return row.stat, row.index end end)
    rankRows[i] = row
    return row
end

local function Chip(stat)
    if chips[stat] then return chips[stat] end
    local G = Wg()
    local chip = G.Button(f.palette, Label(stat), 80, "secondary", function() AddStat(stat) end)
    chip.stat = stat
    chip.measure = (chip.text and chip.text.GetStringWidth and chip.text:GetStringWidth()) or 60
    chip:SetWidth(math.max(54, math.ceil(chip.measure) + 24))
    Tip(chip, Label(stat), "Click to put it at the bottom of your list, or drag it to where you want it.")
    Draggable(chip, function() return stat, nil end)
    chips[stat] = chip
    return chip
end

---------------------------------------------------------------------------
-- Weights: a card per group
---------------------------------------------------------------------------
local function WeightRow(group, stat)
    local G = Wg()
    local row = CreateFrame("Frame", nil, group.box)
    row:SetHeight(WEIGHT_H)
    row.stat = stat
    row.group = group.name
    row.label = G.Text(row, "body")
    row.label:SetPoint("LEFT", 12, 0)
    row.label:SetWidth(250)
    row.label:SetWordWrap(false)
    row.label:SetText(Label(stat))
    row.unit = G.Text(row, "small")
    row.unit:SetPoint("LEFT", 270, 0)
    row.unit:SetText(Unit(stat))
    row.edit = G.EditBox(row, 62, 22)
    row.edit:SetPoint("RIGHT", -10, 0)
    row.edit:SetJustifyH("RIGHT")
    row.edit:SetScript("OnEnterPressed", row.edit.ClearFocus)
    row.edit:SetScript("OnEscapePressed", function(self) self.revert = true; self:ClearFocus() end)
    row.edit:SetScript("OnEditFocusLost", function() CommitWeight(row) end)
    row.undo = G.Button(row, "Reset", 52, "secondary", function()
        if not editTree then return end
        FinishEditing()
        P.SetWeight(ClassFile(), editTree, stat, nil)
    end)
    row.undo:SetPoint("RIGHT", row.edit, "LEFT", -8, 0)
    row.default = G.Text(row, "small")
    row.default:SetJustifyH("RIGHT")
    row.default:SetWidth(110)
    row.default:SetPoint("RIGHT", row.undo, "LEFT", -8, 0)
    Tip(row.undo, "Back to the default", function() return ("Puts %s back to TwichUI's number, %s."):format(Label(stat), row.defaultText or "its default") end)
    return row
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function LayoutTrees(trees, w)
    local count = #trees
    local using = D.Character()
    using = using and using.basis and using.basis.skillLine
    local cw = (w - GAP * (count - 1)) / count
    for i, tree in ipairs(trees) do
        local card = TreeCard(i)
        card.skillLine, card.using = tree.skillLine, tree.skillLine == using
        card:SetSize(cw, TREE_H)
        Put(card, f, (i - 1) * (cw + GAP), 0)
        card.name:SetText(tree.name)
        card.name:SetWidth(cw - 80)
        card.use:SetShown(card.using)
        local state, tone = TreeSummary(tree)
        card.state:SetText(state)
        card.state:SetWidth(cw - 24)
        Tone(card.state, tone)
        local isSel = tree.skillLine == editTree
        card.sel:SetShown(isSel)
        card.chosen = isSel
        Wg().Color(card.name, isSel and Wg().pal.text or Wg().pal.textDim)
    end
    for i = count + 1, #treeCards do treeCards[i]:Hide() end
    return TREE_H + GAP + 4
end

local function LayoutPriority(y, inner)
    local G = Wg()
    local list = P.Priority(ClassFile(), editTree) or {}
    local leftW = math.floor(inner * 0.55)
    local rightW = inner - leftW - 16
    local rightX = PAD + leftW + 16

    -- the ranking
    f.rankTitle:SetText("Your ranking")
    Put(f.rankTitle, f.editor, PAD, y)
    f.rankCount:SetText(#list == 0 and "" or ("%d of %d stats"):format(#list, f.rankable))
    f.rankCount:ClearAllPoints()
    f.rankCount:SetPoint("TOPRIGHT", f.editor, "TOPLEFT", PAD + leftW, -(y + 3))
    f.rankCount:Show()
    local top = y + HEAD_H + 2
    local share = 1
    local rowsH = 0
    for i, stat in ipairs(list) do
        local row = RankRow(i)
        row.index, row.stat = i, stat
        row:SetWidth(leftW - 12)
        Put(row, f.rankBox, 6, 6 + (i - 1) * (ROW_H + ROW_GAP))
        row.num:SetText(i .. ".")
        row.label:SetText(Label(stat))
        row.shareText = ("%d%%"):format(math.floor(share * 100 + 0.5))
        row.share:SetText(row.shareText)
        row:SetAlpha(1)
        share = share * W.PRIORITY_STEP
    end
    for i = #list + 1, #rankRows do rankRows[i].index = nil; rankRows[i]:Hide() end
    rowsH = #list * (ROW_H + ROW_GAP)
    local boxH = math.max(112, rowsH + 12)
    f.rankBox:SetSize(leftW, boxH)
    Put(f.rankBox, f.editor, PAD, top)
    f.rankEmpty:SetWidth(leftW - 28)
    f.rankEmpty:SetShown(#list == 0)
    if #list == 0 then
        f.rankEmpty:ClearAllPoints()
        f.rankEmpty:SetPoint("TOPLEFT", f.rankBox, "TOPLEFT", 14, -14)
    end
    local leftBottom = top + boxH + 10
    local bw = (leftW - GAP) / 2
    f.fill:SetWidth(bw); f.clear:SetWidth(bw)
    Put(f.fill, f.editor, PAD, leftBottom)
    Put(f.clear, f.editor, PAD + bw + GAP, leftBottom)
    f.clear:SetEnabled(#list > 0)
    leftBottom = leftBottom + 30

    -- the stats still to rank
    f.paletteTitle:SetText("Not ranked")
    Put(f.paletteTitle, f.editor, rightX, y)
    f.paletteHelp:SetWidth(rightW - 24)
    f.paletteHelp:SetText("Drag a stat into your ranking, or click it to put it at the bottom. Drag a ranked stat back here to take it off.")
    f.paletteHelp:ClearAllPoints()
    f.paletteHelp:SetPoint("TOPLEFT", f.palette, "TOPLEFT", 12, -10)
    f.paletteHelp:Show()
    local py = 10 + (f.paletteHelp:GetStringHeight() or 24) + 10
    local ranked = {}
    for _, stat in ipairs(list) do ranked[stat] = true end
    local used = 0
    for gi, group in ipairs(f.groups) do
        local shown = {}
        for _, stat in ipairs(group.stats) do if not ranked[stat] then shown[#shown + 1] = stat end end
        local title = f.groupTitles[gi]
        if #shown > 0 then
            title:SetText(group.name:upper())
            title:ClearAllPoints()
            title:SetPoint("TOPLEFT", f.palette, "TOPLEFT", 12, -py)
            title:Show()
            py = py + 16
            local x, rowY = 12, py
            for _, stat in ipairs(shown) do
                local chip = Chip(stat)
                used = used + 1
                local cwid = chip:GetWidth()
                if x > 12 and x + cwid > rightW - 12 then x = 12; rowY = rowY + CHIP_H + CHIP_GAP end
                chip:ClearAllPoints()
                chip:SetPoint("TOPLEFT", f.palette, "TOPLEFT", x, -rowY)
                chip:Show()
                x = x + cwid + CHIP_GAP
            end
            py = rowY + CHIP_H + 10
        else
            title:Hide()
        end
    end
    for stat, chip in pairs(chips) do if ranked[stat] then chip:Hide() end end
    f.paletteDone:SetShown(used == 0)
    if used == 0 then
        f.paletteDone:SetWidth(rightW - 24)
        f.paletteDone:ClearAllPoints()
        f.paletteDone:SetPoint("TOPLEFT", f.palette, "TOPLEFT", 12, -py)
        py = py + 30
    end
    local paletteH = math.max(boxH, py)
    f.palette:SetSize(rightW, paletteH)
    Put(f.palette, f.editor, rightX, top)
    return math.max(leftBottom, top + paletteH) + 10
end

local function LayoutWeights(y, inner, w)
    local G = Wg()
    local classFile = ClassFile()
    local tree = TreeDef(editTree)
    local custom = P.CustomWeights(classFile, editTree) or {}
    -- the group buttons
    local count = #f.filters
    local bw = (inner - (count - 1) * 6) / count
    for i, b in ipairs(f.filters) do
        b:SetWidth(bw)
        b:SetOn(selectedGroup == b.group)
        Put(b, f.editor, PAD + (i - 1) * (bw + 6), y)
    end
    y = y + 32
    for _, row in ipairs(weightRows) do
        local default = tree.def.weights[row.stat] or 0
        local value = custom[row.stat]
        if not row.edit:HasFocus() then row.edit:SetText(Number(value or default)) end
        row.defaultText = Number(default)
        if value then
            G.Color(row.label, G.pal.gold)
            row.default:SetText("default " .. Number(default))
        else
            G.Color(row.label, G.pal.text)
            row.default:SetText("")
        end
        row.undo:SetShown(value ~= nil)
    end
    for _, group in ipairs(groupBoxes) do
        local shown = selectedGroup == "all" or selectedGroup == group.name
        group.box:SetShown(shown)
        if shown then
            group.box:SetWidth(inner)
            local rowsY = HEAD_H + 12
            for _, row in ipairs(group.rows) do
                row:SetWidth(inner - 2)
                Put(row, group.box, 1, rowsY)
                rowsY = rowsY + WEIGHT_H
            end
            group.box:SetHeight(rowsY + 6)
            Put(group.box, f.editor, PAD, y)
            y = y + rowsY + 6 + 10
        else
            for _, row in ipairs(group.rows) do row:Hide() end
        end
    end
    return y
end

local function LayoutEditor(tree, w)
    local G = Wg()
    local classFile = ClassFile()
    local usesPriority = P.UsesPriority(classFile, editTree)
    local inner = w - PAD * 2
    local y = 14
    local className = UnitClass("player") or ""
    R.Icons.Apply(f.headIcon, "gearComparison", 32)
    Put(f.headIcon, f.editor, PAD, y)
    f.title:SetText(("%s %s"):format(tree.name, className))
    f.title:SetWidth(inner - 32 - 12 - 252)
    Put(f.title, f.editor, PAD + 42, y)
    local using = D.Character()
    using = using and using.basis and using.basis.skillLine
    f.subtitle:SetText(tree.skillLine == using and "The tree your gear is weighed for now" or "Not the tree your gear is weighed for now")
    f.subtitle:SetWidth(inner - 32 - 12 - 252)
    Put(f.subtitle, f.editor, PAD + 42, y + 20)
    f.modePriority:SetOn(usesPriority)
    f.modeWeights:SetOn(not usesPriority)
    Put(f.modeWeights, f.editor, w - PAD - 132, y + 4)
    Put(f.modePriority, f.editor, w - PAD - 132 - 118, y + 4)
    y = y + 46

    f.help:SetWidth(inner)
    local untouched = not usesPriority and next(P.CustomWeights(classFile, editTree) or {}) == nil
    f.help:SetText((untouched and (DEFAULTS_HELP .. "\n") or "") .. (usesPriority and PRIORITY_HELP:format(math.floor(W.PRIORITY_STEP * 100 + 0.5)) or WEIGHTS_HELP) .. "\n" .. SOURCE .. " " .. LIMITS)
    Put(f.help, f.editor, PAD, y)
    y = y + (f.help:GetStringHeight() or 28) + 12

    -- one mode's parts at a time
    for _, part in ipairs(f.priorityParts) do part:SetShown(usesPriority) end
    for _, part in ipairs(f.weightParts) do part:SetShown(not usesPriority) end
    if usesPriority then
        for _, group in ipairs(groupBoxes) do group.box:Hide() end
        y = LayoutPriority(y, inner)
    else
        f.rankBox:Hide(); f.palette:Hide()
        for _, row in ipairs(rankRows) do row:Hide() end
        for _, chip in pairs(chips) do chip:Hide() end
        y = LayoutWeights(y, inner, w)
    end

    -- the sentence
    local sentence, tone
    if usesPriority then
        local list = P.Priority(classFile, editTree) or {}
        if #list == 0 then
            sentence, tone = "Nothing is ranked yet, so this tree is still valued by its weights. Rank a stat, or start from the weights.", "quiet"
        else
            local names = {}
            for i = 1, math.min(#list, 5) do names[i] = Label(list[i]) end
            sentence = "Valued by your ranking: " .. table.concat(names, " > ") .. (#list > 5 and (" and %d more"):format(#list - 5) or "") .. "."
        end
    else
        local changed = 0
        for _ in pairs(P.CustomWeights(classFile, editTree) or {}) do changed = changed + 1 end
        if changed == 0 then sentence, tone = "Valued by TwichUI's own weights. Nothing here has been changed.", "quiet"
        else sentence = ("Valued by your weights: %d of them changed from TwichUI's defaults."):format(changed) end
    end
    f.bar:SetWidth(inner)
    f.barText:SetWidth(inner - 44 - (usesPriority and 0 or 140))
    f.barText:SetText(sentence)
    Tone(f.barText, tone)
    f.barIcon:SetTexture(R.PATH .. [[media\loot\autocheck]])
    local bh = math.max(36, (f.barText:GetStringHeight() or 14) + 20)
    f.bar:SetHeight(bh)
    Put(f.bar, f.editor, PAD, y)
    f.reset:SetShown(not usesPriority)
    f.reset:ClearAllPoints()
    f.reset:SetPoint("RIGHT", f.bar, "RIGHT", -8, 0)
    f.reset:SetEnabled(next(P.CustomWeights(classFile, editTree) or {}) ~= nil)
    y = y + bh + 8
    return y + 6
end

---------------------------------------------------------------------------
-- Redrawing
---------------------------------------------------------------------------
function GW:Refresh()
    if not (f and built and f:IsShown()) then return end
    local trees = D.Trees()
    local known = trees ~= nil
    f.noClass:SetShown(not known)
    f.editor:SetShown(known)
    if not known then
        for _, card in ipairs(treeCards) do card:Hide() end
        CancelDrag()
        self.height = 80
        f:SetHeight(80)
        return
    end
    if not TreeDef(editTree) then
        local who = D.Character()
        editTree = (who and who.basis.skillLine) or trees[1].skillLine
    end
    local w = math.max(W_MIN, f:GetWidth() or W_MIN)
    local top = LayoutTrees(trees, w)
    f.editor:SetWidth(w)
    Put(f.editor, f, 0, top)
    local h = LayoutEditor(TreeDef(editTree), w)
    f.editor:SetHeight(h)
    local total = top + h
    if self.height ~= total then
        self.height = total
        f:SetHeight(total)
        local UI = R.SettingsUI
        if UI and UI.Refresh and UI.IsPageActive and UI.IsPageActive(PAGE) then
            C_Timer.After(0, function() if UI.IsPageActive(PAGE) then UI.Refresh() end end)
        end
    end
end

function GW.Height() return GW.height or 640 end

local function TreeNote(skillLine)
    local tree = TreeDef(skillLine)
    local className = UnitClass("player")
    return tree and ("%s (%s)"):format(tree.name, className or "your class") or "this tree"
end

-- The tree is fixed when the question is asked: picking another tree while it is open must not change what is reset.
local function StillThere(skillLine)
    return function()
        if not TreeDef(skillLine) then return false, "That talent tree isn't available any more, so nothing was changed." end
        return true
    end
end

local function SetMode(mode)
    -- The first time, start the list from the tree's weights.
    FinishEditing()
    CancelDrag()
    if mode == "priority" and not P.Priority(ClassFile(), editTree) then StartFromWeights() end
    P.SetUsesPriority(ClassFile(), editTree, mode == "priority")
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build(p)
    local G, M = Wg(), Mat()
    built = true

    f.editor = CreateFrame("Frame", nil, p, "BackdropTemplate")
    M.PanelFace(f.editor, "card")
    local e = f.editor

    f.headIcon = e:CreateTexture(nil, "ARTWORK"); f.headIcon:SetSize(32, 32)
    f.title = G.Text(e, "heading"); f.title:SetWordWrap(false)
    f.subtitle = G.Text(e, "small"); f.subtitle:SetWordWrap(false)
    f.modePriority = R.FrameLook.Toggle(e, "Stat priority", 112, function() SetMode("priority") end)
    f.modeWeights = R.FrameLook.Toggle(e, "Advanced weights", 132, function() SetMode("weights") end)
    Tip(f.modePriority, "Stat priority", "Rank the stats your guide lists, like \"Strength > Hit > Critical Strike\". The usual way to follow a guide.")
    Tip(f.modeWeights, "Advanced weights", "Give each stat a number. Only needed if your guide or simulator gives exact stat weights; TwichUI's defaults are used for any you leave alone.")
    f.help = G.Text(e, "small"); f.help:SetWordWrap(true); f.help:SetJustifyV("TOP")

    -- stat priority
    f.priorityParts = {}
    local function PriorityPart(o) f.priorityParts[#f.priorityParts + 1] = o; return o end
    f.groups = Rankable()
    f.rankable = 0
    for _, group in ipairs(f.groups) do f.rankable = f.rankable + #group.stats end
    f.rankTitle = PriorityPart(G.Text(e, "heading"))
    f.rankCount = PriorityPart(G.Text(e, "meta")); f.rankCount:SetJustifyH("RIGHT")
    f.rankBox = PriorityPart(CreateFrame("Frame", nil, e, "BackdropTemplate"))
    M.PanelFace(f.rankBox, "canvas")
    f.rankEmpty = G.Text(f.rankBox, "small"); f.rankEmpty:SetWordWrap(true)
    f.rankEmpty:SetText("No stats ranked yet. Drag stats in from \"Not ranked\", or click them, most important first. Or start from this tree's weights. Until then, this tree is valued by its weights.")
    f.fill = PriorityPart(G.Button(e, "Start from weights", 130, "secondary", function()
        if #RankedCopy() == 0 then StartFromWeights() return end
        local tree = editTree
        Confirm("TWICHUI_GEAR_FILL", ("Replace your stat priority for %s with the stats its weights value most?\n\nThe list you ranked is lost. This can't be undone."):format(TreeNote(tree)),
            function() StartFromWeights(tree) end, { valid = StillThere(tree) })
    end))
    Tip(f.fill, "Start from weights", "Replaces the list with the stats this tree's weights value most, as a starting point.")
    f.clear = PriorityPart(G.Button(e, "Clear list", 130, "secondary", function()
        local tree = editTree
        Confirm("TWICHUI_GEAR_CLEAR", ("Clear your stat priority for %s?\n\nUntil you rank stats again, this tree is valued by its weights. This can't be undone."):format(TreeNote(tree)),
            function() P.SetPriority(ClassFile(), tree, nil) end, { valid = StillThere(tree) })
    end))
    Tip(f.clear, "Clear list", function()
        return "Removes every stat, to build the list from your guide.", #RankedCopy() == 0 and "The list is already empty." or nil
    end)
    f.paletteTitle = PriorityPart(G.Text(e, "heading"))
    f.palette = PriorityPart(CreateFrame("Frame", nil, e, "BackdropTemplate"))
    M.PanelFace(f.palette, "canvas")
    f.paletteHot = G.Solid(f.palette, "OVERLAY", G.pal.bronzeText, 0.14)
    f.paletteHot:SetAllPoints()
    f.paletteHot:Hide()
    f.paletteHelp = G.Text(f.palette, "small"); f.paletteHelp:SetWordWrap(true)
    f.groupTitles = {}
    for gi = 1, #f.groups do f.groupTitles[gi] = G.Text(f.palette, "meta") end
    f.paletteDone = G.Text(f.palette, "small"); f.paletteDone:SetWordWrap(true)
    f.paletteDone:SetText("Every stat is on your list.")

    -- stat weights
    f.weightParts = {}
    local function WeightPart(o) f.weightParts[#f.weightParts + 1] = o; return o end
    f.filters = {}
    local function Filter(label, group)
        local b = WeightPart(R.FrameLook.Toggle(e, label, 96, function()
            FinishEditing()
            selectedGroup = group
            GW:Refresh()
        end))
        b.group = group
        Tip(b, "Show " .. (group == "all" and "every stat group" or label), "Focus on one group without changing any weights. All groups remain available here.")
        f.filters[#f.filters + 1] = b
    end
    Filter("All", "all")
    for _, group in ipairs(W.EDITOR) do Filter(group[1], group[1]) end
    for _, group in ipairs(W.EDITOR) do
        local box = CreateFrame("Frame", nil, e, "BackdropTemplate")
        M.PanelFace(box, "canvas")
        local entry = { name = group[1], box = box, rows = {} }
        entry.title = G.Text(box, "meta")
        entry.title:SetPoint("TOPLEFT", 12, -10)
        entry.title:SetText(group[1]:upper())
        for _, stat in ipairs(group[2]) do
            local row = WeightRow(entry, stat)
            entry.rows[#entry.rows + 1] = row
            weightRows[#weightRows + 1] = row
        end
        groupBoxes[#groupBoxes + 1] = entry   -- shown by the group choice (LayoutWeights), not by the mode alone
    end
    f.reset = G.Button(e, "Reset weights", 120, "secondary", function()
        local tree = editTree
        if not tree then return end
        FinishEditing()
        Confirm("TWICHUI_GEAR_RESET", ("Put every stat weight for %s back to TwichUI's defaults?\n\nThe numbers you entered for this tree are lost. Other trees aren't changed. This can't be undone."):format(TreeNote(tree)),
            function()
                FinishEditing()
                P.ResetWeights(ClassFile(), tree)
            end, { valid = StillThere(tree) })
    end)
    Tip(f.reset, "Reset weights", function()
        local custom = editTree and P.CustomWeights(ClassFile(), editTree)
        return "Puts every stat weight of this tree back to TwichUI's defaults.", not (custom and next(custom)) and "No weight has been changed for this tree." or nil
    end)

    -- the sentence
    f.bar = CreateFrame("Frame", nil, e, "BackdropTemplate")
    M.PanelFace(f.bar, "canvas")
    f.barIcon = f.bar:CreateTexture(nil, "ARTWORK"); f.barIcon:SetSize(22, 22); f.barIcon:SetPoint("LEFT", 12, 0)
    f.barText = G.Text(f.bar, "body"); f.barText:SetPoint("LEFT", 44, 0); f.barText:SetWordWrap(true)
    f.reset:SetParent(f.bar)

    -- Shown instead of everything above for a class without weights.
    f.noClass = G.Text(p, "small")
    f.noClass:SetWordWrap(true)
    f.noClass:SetWidth(W_MIN - 8)
    f.noClass:SetPoint("TOPLEFT", 4, -4)
    f.noClass:SetText("TwichUI has no stat weights for your class, so upgrade hints are not shown.")
    f.noClass:Hide()
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
    f:SetScript("OnSizeChanged", function() if built and f:IsShown() and not relayout then relayout = true; C_Timer.After(0, function() relayout = false; GW:Refresh() end) end end)
    f:SetScript("OnHide", function()
        CancelDrag()
        local G = Wg()
        if G and G.CloseMenu then G.CloseMenu() end
    end)
    -- No reset of its own in "Reset this page": hand-entered weights are reset with the buttons on the page.
    H:OnChange(function() GW:Refresh() end)
    return f
end
GW.Frame = Frame

-- What has been built, read only (for the tests and the simulator).
function GW.Parts()
    return { frame = f, trees = treeCards, ranked = rankRows, chips = chips, weights = weightRows, groups = groupBoxes }
end

function GW:Show()
    if not D.Trees() then
        R.Print("upgrade hints have no weights for your class.")
        return
    end
    R:OpenSettings(PAGE)
end
