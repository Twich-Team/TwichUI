-- TwichUI: upgrade hints, tooltip
-- Adds one quiet line to an item's tooltip when it looks like an upgrade for
-- you. Holding the reveal key (Shift, your compare-items key, unless you pick
-- another in /twichui gear) shows why: what it's compared with, the stat
-- changes that mattered most, which weights were used and what wasn't
-- counted. Items that aren't upgrades, or that you can't use, get nothing
-- unless you ask.
--
-- The wording is worked out once per item (Hints.lua keeps the judgement).
-- Bag and character-pane tooltips rebuild several times a second while
-- hovered; those rebuilds only re-add the kept lines.
--
-- Toggle: /twichui > "Upgrade hints in item tooltips".

local R = TwichUI
local E, P, H = R.GearEval, R.GearPrefs, R.GearHints

-- Muted colours; the words always carry the meaning on their own.
local GREEN = { 0.56, 0.70, 0.35 }
local GOLD = { 0.79, 0.64, 0.29 }
local QUIET = { 0.62, 0.60, 0.56 }
local LOSS = { 0.80, 0.42, 0.38 }
local INDENT = 8
local MAX_CHANGES = 4

local VERDICT = {
    likely    = { text = "Likely upgrade", color = GREEN, glance = true },
    possible  = { text = "Possible upgrade", color = GOLD, glance = true },
    empty     = { text = "Fills an empty slot", color = GREEN, glance = true },
    similar   = { text = "Similar to what you wear", color = QUIET },
    worse     = { text = "Probably not an upgrade", color = QUIET },
    unknown   = { text = "Nothing here the estimate can weigh", color = QUIET },
    twoHander = { text = "Not compared while you wield a two-handed weapon", color = QUIET },
}

local BASIS = {
    auto       = "Rough estimate, weighed for %s",
    chosen     = "Rough estimate, weighed for %s (your choice)",
    noPoints   = "Rough estimate, weighed for %s until you spend talent points",
    split      = "Rough estimate, weighed for %s while your talents are split evenly",
    unreadable = "Rough estimate, weighed for %s (your talents couldn't be read)",
}

local comparisonTooltips = {}

local function Line(text, color, wrap, indent)
    return { text, color[1], color[2], color[3], wrap or false, indent }
end

local function Amount(family, value)
    if family:find("_DPS$") or value ~= math.floor(value) then
        return ("%+.1f"):format(value)
    end
    return ("%+d"):format(value)
end

local function ItemName(item)
    local color = ITEM_QUALITY_COLORS and item.quality and ITEM_QUALITY_COLORS[item.quality]
    if color and color.hex then return color.hex .. item.name .. "|r" end
    return item.name
end

local function Present(judged)
    local result, basis = judged.result, judged.who.basis
    local verdict = VERDICT[result.verdict]
    local title = verdict.text
    if verdict.glance and result.verdict ~= "empty" and basis.tree then
        title = title .. " for " .. basis.label
    end
    if judged.level then
        title = ("%s at level %d"):format(title, judged.level)
    end
    local head = Line(title, verdict.color)
    local detail = { Line(" ", QUIET), head }

    if result.verdict ~= "twoHander" then
        if #result.against > 0 then
            local names = {}
            for i, item in ipairs(result.against) do names[i] = ItemName(item) end
            detail[#detail + 1] = Line("Compared with " .. table.concat(names, " and "), QUIET, true)
        end
        local changes = result.changes
        for i = 1, math.min(#changes, MAX_CHANGES) do
            local change = changes[i]
            detail[#detail + 1] = Line(Amount(change.family, change.delta) .. " " .. E.Label(change.family),
                change.weight > 0 and GREEN or LOSS, false, INDENT)
        end
        local more = #changes - MAX_CHANGES
        if more > 0 then
            detail[#detail + 1] = Line(more == 1 and "and 1 smaller change" or ("and %d smaller changes"):format(more), QUIET, false, INDENT)
        end
        detail[#detail + 1] = Line(BASIS[basis.reason]:format(basis.label), QUIET, true)
        if judged.level then
            detail[#detail + 1] = Line(("You can wear it from level %d"):format(judged.level), QUIET, true)
        end
        if result.freesOffHand then
            detail[#detail + 1] = Line("Leaves your off hand empty", QUIET, true)
        end
        if result.effects then
            detail[#detail + 1] = Line("Use and chance-on-hit effects aren't weighed", QUIET, true)
        end
        if #result.unweighted > 0 then
            detail[#detail + 1] = Line("Not weighed for " .. basis.label .. ": " .. table.concat(result.unweighted, ", "), QUIET, true)
        end
        if #result.notCounted > 0 then
            detail[#detail + 1] = Line("Not counted: " .. table.concat(result.notCounted, ", "), QUIET, true)
        end
    end
    return { glance = { head }, detail = detail }
end

local function Plain(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

local function LinkFor(data)
    local link
    local guid = Plain(data.guid)
    if guid and C_Item.GetItemLinkByGUID then link = C_Item.GetItemLinkByGUID(guid) end
    link = link or Plain(data.hyperlink)
    local id = Plain(data.id)
    if not link and id then link = select(2, C_Item.GetItemInfo(id)) end
    link = Plain(link)
    return type(link) == "string" and link or nil
end

local function Revealed()
    local reveal = P.Get("reveal")
    if reveal == "always" then return true
    elseif reveal == "alt" then return IsAltKeyDown()
    elseif reveal == "ctrl" then return IsControlKeyDown()
    end
    return IsModifiedClick("COMPAREITEMS")
end

local function AddLines(tooltip, lines)
    for i = 1, #lines do
        local l = lines[i]
        tooltip:AddLine(l[1], l[2], l[3], l[4], l[5], l[6])
    end
end

local function OnItemTooltip(tooltip, data)
    if not R:Enabled("gearHints") or comparisonTooltips[tooltip] or type(data) ~= "table" then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local link = LinkFor(data)
    local judged = link and H.Judge(link, data.lines, tooltip)
    if not judged then return end
    judged.lines = judged.lines or Present(judged)
    if Revealed() then
        AddLines(tooltip, judged.lines.detail)
    elseif H.Noteworthy(judged) then
        AddLines(tooltip, judged.lines.glance)
    end
end

R:OnInit(function()
    if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType) then return end
    -- The side-by-side "Currently Equipped" tooltips show your own gear.
    for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" }) do
        if _G[name] then comparisonTooltips[_G[name]] = true end
    end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
end)
