-- TwichUI: upgrade hints, weights
-- How much each stat is worth to each class and talent tree. These are rough,
-- hand-set values meant to separate "clearly better for you" from "clearly
-- not", not simulation results. Tune freely; nothing else needs to change.
--
-- Values are per point of the stat, relative to the tree's main stat (1.0).
-- Rating stats (listed in RATINGS) are weighed per 1% instead (per skill
-- point for defense and expertise); the game converts an item's rating into
-- that at your current level, so the same weights hold while you level.
-- Weapon damage per second is weighed by the slot it goes in.

local R = TwichUI
local W = {}
R.GearWeights = W

-- A change smaller than this (in main-stat points) is "about the same".
W.MIN_DIFFERENCE = 0.5
-- Improvement over what you wear needed to call it an upgrade. The upgrade
-- hints window can make these stricter or looser (Prefs.lua).
W.LIKELY = 0.10      -- "Likely upgrade"
W.POSSIBLE = 0.03    -- "Possible upgrade"

W.RATINGS = {
    HIT = true, SPELLHIT = true, CRIT = true, SPELLCRIT = true, HASTE = true,
    EXPERTISE = true, ARMORPEN = true, DEFENSE = true, DODGE = true, PARRY = true, BLOCK = true,
}
-- Ratings weighed per skill point rather than per 1%.
W.PER_SKILL_POINT = { DEFENSE = true, EXPERTISE = true }

-- Every stat the weights know, grouped and ordered for the weights editor.
W.EDITOR = {
    { "Attributes", { "STR", "AGI", "STA", "INT", "SPI" } },
    { "Attack", { "AP", "RAP", "FERALAP", "HIT", "CRIT", "HASTE", "EXPERTISE", "ARMORPEN" } },
    { "Spells", { "SP", "HEAL", "SPELLHIT", "SPELLCRIT", "SPELLPEN", "MP5", "MANA" } },
    { "Defense", { "ARMOR", "DEFENSE", "DODGE", "PARRY", "BLOCK", "BLOCKVALUE", "HEALTH", "HP5" } },
    { "Weapon damage", { "MAINHAND_DPS", "OFFHAND_DPS", "RANGED_DPS" } },
}

---------------------------------------------------------------------------
-- Stat priority: the other way to value stats, chosen per tree in
-- /twichui gear. You rank the stats a guide lists, most important first.
-- Each counts PRIORITY_STEP as much as the one above it, and stats you leave
-- out count nothing. Weapon damage, armor, health and mana can't be ranked
-- and keep the tree's weights.
---------------------------------------------------------------------------
W.PRIORITY_STEP = 0.8

-- Roughly what one point of each rankable stat costs on an item, next to a
-- point of a main stat (classic and TBC era itemization, approximate). It
-- lets a ranking compare stats as items carry them: "Strength > Attack
-- Power" means a point of strength beats the two attack power an item would
-- have in its place. Ratings count per point as printed on the item.
W.ITEM_POINT = {
    STR = 1, AGI = 1, STA = 1, INT = 1, SPI = 1,
    AP = 0.5, RAP = 0.4, FERALAP = 0.5,
    HIT = 1, CRIT = 1, HASTE = 1, EXPERTISE = 1, ARMORPEN = 1,
    SP = 0.85, HEAL = 0.45, SPELLHIT = 1, SPELLCRIT = 1, SPELLPEN = 0.8, MP5 = 2.5,
    DEFENSE = 1, DODGE = 1, PARRY = 1, BLOCK = 1, BLOCKVALUE = 0.65,
}

-- Weights from a ranked list of stats. `base` (the tree's weights) supplies
-- the stats that can't be ranked.
function W.FromPriority(list, base)
    local weights = { perRatingPoint = true }
    for stat, weight in pairs(base) do
        if not W.ITEM_POINT[stat] and stat ~= "perRatingPoint" then weights[stat] = weight end
    end
    local value = 1
    for _, stat in ipairs(list) do
        local cost = W.ITEM_POINT[stat]
        if cost and not weights[stat] then
            weights[stat] = value * cost
            value = value * W.PRIORITY_STEP
        end
    end
    return weights
end

-- A starting ranking from a tree's weights: the stats worth most for what
-- they cost on an item, down to a seventh of the best, at most eight.
-- ratingScale converts rating weights (per 1%) to per rating point; ratings
-- it can't convert are left out.
function W.PriorityFromWeights(weights, ratingScale)
    local ranked = {}
    for g, group in ipairs(W.EDITOR) do
        for s, stat in ipairs(group[2]) do
            local cost, weight = W.ITEM_POINT[stat], weights[stat] or 0
            if cost and weight > 0 and W.RATINGS[stat] then
                weight = weight * (ratingScale and ratingScale[stat] or 0)
            end
            if cost and weight > 0 then
                ranked[#ranked + 1] = { stat = stat, value = weight / cost, order = g * 100 + s }
            end
        end
    end
    table.sort(ranked, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.order < b.order
    end)
    local list = {}
    for _, entry in ipairs(ranked) do
        if #list == 8 or entry.value < ranked[1].value / 7 then break end
        list[#list + 1] = entry.stat
    end
    return list
end

local function With(base, changes)
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for k, v in pairs(changes) do t[k] = v end
    return t
end

local STRENGTH_MELEE = {
    STR = 1.0, AGI = 0.6, STA = 0.25, AP = 0.5,
    HIT = 12, CRIT = 11, HASTE = 7, EXPERTISE = 2.5, ARMORPEN = 2,
    ARMOR = 0.005,
    MAINHAND_DPS = 7, OFFHAND_DPS = 3.5, RANGED_DPS = 0.3,
}

local AGILITY_MELEE = {
    AGI = 1.0, STR = 0.5, STA = 0.25, AP = 0.5,
    HIT = 13, CRIT = 11, HASTE = 8, EXPERTISE = 3, ARMORPEN = 2,
    ARMOR = 0.005,
    MAINHAND_DPS = 7, OFFHAND_DPS = 5, RANGED_DPS = 0.3,
}

local RANGED = {
    AGI = 1.0, RAP = 0.45, AP = 0.05, STA = 0.25, INT = 0.25, SPI = 0.05, MP5 = 0.4,
    HIT = 12, CRIT = 11, HASTE = 6, ARMORPEN = 2,
    ARMOR = 0.005,
    MAINHAND_DPS = 0.5, OFFHAND_DPS = 0.3, RANGED_DPS = 7,
}

-- Cat and bear: weapon damage doesn't matter in forms, attack power does.
local FERAL = {
    STR = 1.0, AGI = 0.9, STA = 0.5, AP = 0.5, FERALAP = 0.5, INT = 0.1,
    HIT = 11, CRIT = 10, HASTE = 3, EXPERTISE = 2.5, ARMORPEN = 2,
    DEFENSE = 0.5, DODGE = 6, ARMOR = 0.02,
}

local PLATE_TANK = {
    STA = 1.0, STR = 0.5, AGI = 0.6, AP = 0.2, HEALTH = 0.1,
    DEFENSE = 1.5, DODGE = 12, PARRY = 10, BLOCK = 6, BLOCKVALUE = 0.3,
    HIT = 6, CRIT = 3, EXPERTISE = 2,
    ARMOR = 0.04,
    MAINHAND_DPS = 3, RANGED_DPS = 0.1,
}

-- Generic hit and crit rating on caster gear usually applies to spells, so
-- casters and healers count them like the spell versions.
local CASTER = {
    SP = 1.0, INT = 0.4, SPI = 0.15, STA = 0.25, MP5 = 0.6, SPELLPEN = 0.2,
    MANA = 0.03, HEALTH = 0.025,
    SPELLHIT = 12, HIT = 12, SPELLCRIT = 10, CRIT = 10, HASTE = 8,
    RANGED_DPS = 1.5,   -- wands, while levelling
}

-- Healing counts "+damage and healing" spell power too (see Evaluate.lua).
local HEALER = {
    HEAL = 1.0, SP = 0.1, INT = 0.6, SPI = 0.3, MP5 = 1.0, STA = 0.25,
    MANA = 0.04, HEALTH = 0.025,
    SPELLCRIT = 7, CRIT = 7, HASTE = 6,
}

-- Trees in the order the talent frame shows them. skillLine identifies the
-- tree; the order is the fallback if the game doesn't report it. `default` is
-- used before the first talent point, or when points are split evenly.
W.CLASSES = {
    WARRIOR = { default = 1, trees = {
        { skillLine = 26,  name = "Arms",          weights = STRENGTH_MELEE },
        { skillLine = 256, name = "Fury",          weights = STRENGTH_MELEE },
        { skillLine = 257, name = "Protection",    weights = PLATE_TANK },
    } },
    PALADIN = { default = 3, trees = {
        { skillLine = 594, name = "Holy",          weights = With(HEALER, { SPI = 0.1 }) },
        { skillLine = 267, name = "Protection",    weights = With(PLATE_TANK, { INT = 0.3, SP = 0.3, MP5 = 0.3 }) },
        { skillLine = 184, name = "Retribution",   weights = With(STRENGTH_MELEE, { AGI = 0.5, INT = 0.3, SP = 0.25, MP5 = 0.3 }) },
    } },
    HUNTER = { default = 1, trees = {
        { skillLine = 50,  name = "Beast Mastery", weights = RANGED },
        { skillLine = 163, name = "Marksmanship",  weights = RANGED },
        { skillLine = 51,  name = "Survival",      weights = RANGED },
    } },
    ROGUE = { default = 2, trees = {
        { skillLine = 253, name = "Assassination", weights = AGILITY_MELEE },
        { skillLine = 38,  name = "Combat",        weights = AGILITY_MELEE },
        { skillLine = 39,  name = "Subtlety",      weights = AGILITY_MELEE },
    } },
    PRIEST = { default = 3, trees = {
        { skillLine = 613, name = "Discipline",    weights = With(HEALER, { SPI = 0.4, RANGED_DPS = 0.8 }) },
        { skillLine = 56,  name = "Holy",          weights = With(HEALER, { SPI = 0.4, RANGED_DPS = 0.8 }) },
        { skillLine = 78,  name = "Shadow",        weights = With(CASTER, { SPI = 0.25, STA = 0.3 }) },
    } },
    SHAMAN = { default = 2, trees = {
        { skillLine = 375, name = "Elemental",     weights = With(CASTER, { SPI = 0.05, MP5 = 0.8, RANGED_DPS = 0 }) },
        { skillLine = 373, name = "Enhancement",   weights = With(STRENGTH_MELEE, { AGI = 0.7, INT = 0.3, SP = 0.2, MP5 = 0.2 }) },
        { skillLine = 374, name = "Restoration",   weights = With(HEALER, { SPI = 0.1 }) },
    } },
    MAGE = { default = 3, trees = {
        { skillLine = 237, name = "Arcane",        weights = With(CASTER, { SPI = 0.2 }) },
        { skillLine = 8,   name = "Fire",          weights = CASTER },
        { skillLine = 6,   name = "Frost",         weights = CASTER },
    } },
    WARLOCK = { default = 1, trees = {
        { skillLine = 355, name = "Affliction",    weights = With(CASTER, { STA = 0.35 }) },
        { skillLine = 354, name = "Demonology",    weights = With(CASTER, { STA = 0.4 }) },
        { skillLine = 593, name = "Destruction",   weights = With(CASTER, { STA = 0.3 }) },
    } },
    DRUID = { default = 2, trees = {
        { skillLine = 574, name = "Balance",       weights = With(CASTER, { SPI = 0.2, RANGED_DPS = 0 }) },
        { skillLine = 134, name = "Feral Combat",  weights = FERAL },
        { skillLine = 573, name = "Restoration",   weights = With(HEALER, { SPI = 0.4 }) },
    } },
}
