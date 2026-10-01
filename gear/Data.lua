-- TwichUI: upgrade hints, game data
-- Everything the upgrade hints read from the game: your class, level and
-- main talent tree, what you have equipped, an item's stats and effects,
-- and whether you can use it. Answers are cached until something changes
-- (Tooltip.lua clears them on equipment, talent, level and skill events).
--
-- Forever has no retail specializations. Talents are classic-style trees on
-- top of C_Traits, so "your spec" here is the tree you've put the most points
-- into, in your active talent group (dual spec aware), unless you've chosen
-- one in the upgrade hints window.

local R = TwichUI
local W, P = R.GearWeights, R.GearPrefs
local D = {}
R.GearData = D

local character          -- cached answer of D.Character()
local equipped = {}      -- [slot] = item, or false for an empty slot

-- Rating stats the weights use, and the game's combat rating index for each.
-- The numbers are the values Forever's PaperDollFrame.lua defines, used only
-- if its globals aren't there.
local RATING_INDEX = {
    HIT = { "CR_HIT_MELEE", 6 },
    SPELLHIT = { "CR_HIT_SPELL", 8 },
    CRIT = { "CR_CRIT_MELEE", 9 },
    SPELLCRIT = { "CR_CRIT_SPELL", 11 },
    HASTE = { "CR_HASTE_MELEE", 18 },
    EXPERTISE = { "CR_EXPERTISE", 24 },
    ARMORPEN = { "CR_ARMOR_PENETRATION", 25 },
    DEFENSE = { "CR_DEFENSE_SKILL", 2 },
    DODGE = { "CR_DODGE", 3 },
    PARRY = { "CR_PARRY", 4 },
    BLOCK = { "CR_BLOCK", 5 },
}

local function Usable(value)
    if issecretvalue and issecretvalue(value) then return false end
    return value ~= nil
end

-- Percent (or skill points) one point of each rating gives at your level,
-- from the game's own conversion. A rating it can't convert is left out, and
-- the tooltip lists it as not counted.
local function RatingScale()
    local convert = GetCombatRatingBonusForCombatRatingValue
    if not convert then return nil end
    local scale = {}
    for family, index in pairs(RATING_INDEX) do
        local ok, bonus = pcall(convert, _G[index[1]] or index[2], 100)
        if ok and Usable(bonus) and type(bonus) == "number" and bonus > 0 then
            scale[family] = bonus / 100
        end
    end
    return scale
end

-- Points spent in each talent tree of the active talent group, in the order
-- the talent frame shows them. Mirrors Forever's ClassTalentsFrame headers.
local function TalentTrees()
    local group = C_SpecializationInfo.GetActiveSpecGroup()
    local configID = group and C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group)
    if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        configID = C_ClassTalents.GetActiveConfigID()
    end
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end

    local trees, groupIDs = {}, {}
    for _, info in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
        trees[#trees + 1] = { groupID = info.groupID, name = info.displayName, skillLine = info.skillLineID, order = info.orderIndex or 0, spent = 0 }
        groupIDs[#groupIDs + 1] = info.groupID
    end
    if #trees == 0 then return nil end
    for _, info in ipairs(C_Traits.GetGroupCurrencyInfo(configID, groupIDs) or {}) do
        local currency = info.currencyInfos and info.currencyInfos[1]
        for _, tree in ipairs(trees) do
            if tree.groupID == info.traitNodeGroupID and currency then tree.spent = currency.spent or 0 end
        end
    end
    table.sort(trees, function(a, b) return a.order < b.order end)
    return trees
end

-- Your class's trees in talent frame order: { def, skillLine, name, spent },
-- with the game's (localized) names and your points where it reports them.
-- Also returns false if the talent data couldn't be read at all.
local function ClassTrees(classInfo)
    local ok, trees = pcall(TalentTrees)
    local list = {}
    for i, def in ipairs(classInfo.trees) do
        local game
        for _, tree in ipairs(ok and trees or {}) do
            if tree.skillLine == def.skillLine then game = tree end
        end
        game = game or (ok and trees and trees[i])
        list[i] = { def = def, skillLine = def.skillLine, name = game and game.name or def.name, spent = game and game.spent or 0 }
    end
    return list, ok
end

-- The tree with the most points, if one has strictly more than the others.
local function Leading(trees)
    local best, second = nil, 0
    for _, tree in ipairs(trees) do
        if not best or tree.spent > best.spent then
            second = best and best.spent or 0
            best = tree
        elseif tree.spent > second then
            second = tree.spent
        end
    end
    if best and best.spent > 0 and best.spent > second then return best end
    return nil, best and best.spent > 0
end

-- A tree's default weights with your changes from the upgrade hints window.
local function Weights(classFile, def)
    local custom = P.CustomWeights(classFile, def.skillLine)
    if not custom then return def.weights end
    local merged = {}
    for stat, weight in pairs(def.weights) do merged[stat] = weight end
    for stat, weight in pairs(custom) do merged[stat] = weight end
    return merged
end

-- Which weights to use, and why, for the tooltip to explain: the tree you
-- chose, else your main tree, else the class's usual levelling tree.
local function Basis(classFile, classInfo)
    local trees, readable = ClassTrees(classInfo)
    local tree, reason
    local chosen = P.TreeChoice()
    for _, t in ipairs(trees) do
        if chosen and t.skillLine == chosen then tree, reason = t, "chosen" end
    end
    if not tree then
        local leading, split = Leading(trees)
        if leading then
            tree, reason = leading, "auto"
        else
            tree = trees[classInfo.default]
            reason = not readable and "unreadable" or split and "split" or "noPoints"
        end
    end
    return {
        weights = Weights(classFile, tree.def),
        skillLine = tree.skillLine,
        label = tree.name,
        reason = reason,
        tree = reason == "auto" or reason == "chosen",
    }
end

-- Your class, weights and what affects them; nil for a class we have no
-- weights for (no hints are shown then).
function D.Character()
    if character ~= nil then return character or nil end
    local _, classFile = UnitClass("player")
    local classInfo = classFile and W.CLASSES[classFile]
    if not classInfo then
        character = false
        return nil
    end
    local basis = Basis(classFile, classInfo)
    local strictness = P.STRICTNESS[P.Get("strictness")] or P.STRICTNESS.balanced
    character = {
        classFile = classFile,
        basis = basis,
        weights = basis.weights,
        ratingScale = RatingScale(),
        canDualWield = CanDualWield and CanDualWield() or false,
        likely = strictness.likely,
        possible = strictness.possible,
    }
    return character
end

-- For the upgrade hints window: your class's trees ({ skillLine, name, spent,
-- def }), your class, and the tree automatic mode would pick (or nil).
function D.Trees()
    local _, classFile = UnitClass("player")
    local classInfo = classFile and W.CLASSES[classFile]
    if not classInfo then return nil end
    local trees = ClassTrees(classInfo)
    return trees, classFile, (Leading(trees))
end

-- Counts of "Use:" and "Chance on hit:" lines in item tooltip data. Those
-- effects never show up as stats, so the estimate can't weigh them.
function D.Effects(lines)
    local types = Enum and Enum.TooltipDataLineType
    if type(lines) ~= "table" or not types then return nil end
    local fx = { use = 0, proc = 0 }
    for _, line in ipairs(lines) do
        local t = line.type
        if t == types.ItemSpellTriggerOnUse then fx.use = fx.use + 1
        elseif t == types.ItemSpellTriggerOnProc then fx.proc = fx.proc + 1 end
    end
    return fx
end

-- An item's name, slot, level requirement and stats; nil while the game
-- hasn't loaded it yet.
function D.Item(link)
    local name, _, quality, _, minLevel, _, _, _, equipLoc = C_Item.GetItemInfo(link)
    if not name then return nil end
    local getStats = C_Item.GetItemStats or GetItemStats
    local ok, raw = pcall(getStats, link)
    return {
        link = link,
        name = name,
        quality = quality,
        minLevel = minLevel,
        equipLoc = equipLoc,
        raw = (ok and type(raw) == "table") and raw or {},
    }
end

-- What's in an equipment slot: an item, false when empty, nil if not loaded yet.
function D.Equipped(slot)
    local cached = equipped[slot]
    if cached ~= nil then return cached end
    local link = GetInventoryItemLink("player", slot)
    if not link then
        equipped[slot] = false
        return false
    end
    local item = D.Item(link)
    if not item then return nil end
    local data = C_TooltipInfo and C_TooltipInfo.GetInventoryItem and C_TooltipInfo.GetInventoryItem("player", slot)
    item.effects = D.Effects(data and data.lines)
    equipped[slot] = item
    return item
end

-- Red text on an item tooltip is the game saying you can't use it (level,
-- class, armor or weapon skill, reputation...). Counts red lines in the
-- tooltip data or, if it reports none and the tooltip has named lines, in
-- what the tooltip actually shows.
local function IsRed(r, g, b)
    return type(r) == "number" and type(g) == "number" and type(b) == "number"
        and r > 0.9 and g < 0.3 and b < 0.3
end

local function IsRedColor(color)
    return type(color) == "table" and IsRed(color.r, color.g, color.b)
end

local SIDES = { "TextLeft", "TextRight" }

local function IsRedText(text)
    if not (text and text:IsShown()) then return false end
    local s = text:GetText()
    return Usable(s) and s ~= "" and IsRed(text:GetTextColor())
end

function D.RedLines(lines, tooltip)
    local count = 0
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            if IsRedColor(line.leftColor) or IsRedColor(line.rightColor) then count = count + 1 end
        end
    end
    local name = count == 0 and tooltip and tooltip.GetName and tooltip:GetName()
    if name then
        for i = 1, tooltip:NumLines() do
            for _, side in ipairs(SIDES) do
                if IsRedText(_G[name .. side .. i]) then
                    count = count + 1
                    break
                end
            end
        end
    end
    return count
end

function D.ForgetCharacter()
    character = nil
end

function D.ForgetEquipment()
    wipe(equipped)
end
