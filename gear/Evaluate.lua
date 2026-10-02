-- TwichUI: upgrade hints, evaluation
-- Pure comparison logic with no game API calls, so the tests can run it
-- offline. Data.lua gathers the inputs and Tooltip.lua words the result.
--
-- An item's score is its stats times the weights for your class and main
-- talent tree (Weights.lua). It's compared with what it would replace:
--   * rings and trinkets: whichever of your two it improves on most
--   * a two-hander: your main hand and off hand together
--   * a one-hander: your main hand, or your off hand if you can dual wield
--     and aren't carrying a shield or off-hand item there
--   * an off-hand item while you wield a two-hander: not compared

local R = TwichUI
local W = R.GearWeights
local E = {}
R.GearEval = E

local abs = math.abs

-- C_Item.GetItemStats keys, grouped into the stat families the weights use.
local FAMILY = {
    ITEM_MOD_STRENGTH_SHORT = "STR",
    ITEM_MOD_AGILITY_SHORT = "AGI",
    ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT",
    ITEM_MOD_SPIRIT_SHORT = "SPI",
    ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_MELEE_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "RAP",
    ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "FERALAP",
    ITEM_MOD_SPELL_POWER_SHORT = "SP",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
    ITEM_MOD_HIT_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_RANGED_RATING_SHORT = "HIT",
    ITEM_MOD_HIT_SPELL_RATING_SHORT = "SPELLHIT",
    ITEM_MOD_CRIT_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "CRIT",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "SPELLCRIT",
    ITEM_MOD_HASTE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_MELEE_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_RANGED_RATING_SHORT = "HASTE",
    ITEM_MOD_HASTE_SPELL_RATING_SHORT = "HASTE",
    ITEM_MOD_EXPERTISE_RATING_SHORT = "EXPERTISE",
    ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT = "ARMORPEN",
    ITEM_MOD_SPELL_PENETRATION_SHORT = "SPELLPEN",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEFENSE",
    ITEM_MOD_DODGE_RATING_SHORT = "DODGE",
    ITEM_MOD_PARRY_RATING_SHORT = "PARRY",
    ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
    ITEM_MOD_BLOCK_VALUE_SHORT = "BLOCKVALUE",
    ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
    ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
    ITEM_MOD_HEALTH_REGEN_SHORT = "HP5",
    ITEM_MOD_HEALTH_REGENERATION_SHORT = "HP5",
    ITEM_MOD_HEALTH_SHORT = "HEALTH",
    ITEM_MOD_MANA_SHORT = "MANA",
    RESISTANCE0_NAME = "ARMOR",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
}

local DPS_FAMILY = { [16] = "MAINHAND_DPS", [17] = "OFFHAND_DPS", [18] = "RANGED_DPS" }

-- Name shown for each family: the game's own (localized) string, else English.
local LABEL = {
    STR = { "ITEM_MOD_STRENGTH_SHORT", "Strength" },
    AGI = { "ITEM_MOD_AGILITY_SHORT", "Agility" },
    STA = { "ITEM_MOD_STAMINA_SHORT", "Stamina" },
    INT = { "ITEM_MOD_INTELLECT_SHORT", "Intellect" },
    SPI = { "ITEM_MOD_SPIRIT_SHORT", "Spirit" },
    AP = { "ITEM_MOD_ATTACK_POWER_SHORT", "Attack Power" },
    RAP = { "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", "Ranged Attack Power" },
    FERALAP = { "ITEM_MOD_FERAL_ATTACK_POWER_SHORT", "Attack Power in Forms" },
    SP = { "ITEM_MOD_SPELL_POWER_SHORT", "Spell Power" },
    HEAL = { "ITEM_MOD_SPELL_HEALING_DONE_SHORT", "Bonus Healing" },
    HIT = { "ITEM_MOD_HIT_RATING_SHORT", "Hit Rating" },
    SPELLHIT = { "ITEM_MOD_HIT_SPELL_RATING_SHORT", "Spell Hit Rating" },
    CRIT = { "ITEM_MOD_CRIT_RATING_SHORT", "Critical Strike Rating" },
    SPELLCRIT = { "ITEM_MOD_CRIT_SPELL_RATING_SHORT", "Spell Critical Strike Rating" },
    HASTE = { "ITEM_MOD_HASTE_RATING_SHORT", "Haste Rating" },
    EXPERTISE = { "ITEM_MOD_EXPERTISE_RATING_SHORT", "Expertise Rating" },
    ARMORPEN = { "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", "Armor Penetration Rating" },
    SPELLPEN = { "ITEM_MOD_SPELL_PENETRATION_SHORT", "Spell Penetration" },
    DEFENSE = { "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "Defense Rating" },
    DODGE = { "ITEM_MOD_DODGE_RATING_SHORT", "Dodge Rating" },
    PARRY = { "ITEM_MOD_PARRY_RATING_SHORT", "Parry Rating" },
    BLOCK = { "ITEM_MOD_BLOCK_RATING_SHORT", "Block Rating" },
    BLOCKVALUE = { "ITEM_MOD_BLOCK_VALUE_SHORT", "Block Value" },
    MP5 = { "ITEM_MOD_MANA_REGENERATION_SHORT", "Mana Regeneration" },
    HP5 = { "ITEM_MOD_HEALTH_REGENERATION_SHORT", "Health Regeneration" },
    HEALTH = { "ITEM_MOD_HEALTH_SHORT", "Health" },
    MANA = { "ITEM_MOD_MANA_SHORT", "Mana" },
    ARMOR = { "RESISTANCE0_NAME", "Armor" },
    MAINHAND_DPS = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "Damage Per Second" },
    OFFHAND_DPS = { nil, "Off-hand Damage Per Second" },
    RANGED_DPS = { "ITEM_MOD_DAMAGE_PER_SECOND_SHORT", "Damage Per Second" },
}

local function GameString(name)
    local text = name and _G[name]
    if type(text) == "string" and text ~= "" and not text:find("%", 1, true) then return text end
end

-- Display name for a stat family, or for a stat key we don't use.
function E.Label(familyOrKey)
    local label = LABEL[familyOrKey]
    if label then return GameString(label[1]) or label[2] end
    return GameString(familyOrKey) or GameString(familyOrKey .. "_SHORT")
        or (familyOrKey:gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_", " "):lower():gsub("^%l", string.upper))
end

-- Some clients return a stat under its translated name instead of its key.
local localized
local function FamilyOf(key)
    local family = FAMILY[key] or FAMILY[key .. "_SHORT"]
    if family then return family end
    if not localized then
        localized = {}
        for token, fam in pairs(FAMILY) do
            local text = GameString(token)
            if text then localized[text] = fam end
        end
    end
    return localized[key]
end

-- Item stats as { family = value }, with weapon damage per second filed under
-- the slot it would be used in. Also returns the stat keys we don't weigh.
function E.Normalize(raw, slot)
    local stats, unknown = {}, nil
    if type(raw) ~= "table" then return stats end
    for key, value in pairs(raw) do
        if type(key) == "string" and type(value) == "number" and value ~= 0 then
            local family = FamilyOf(key)
            if family == "DPS" then family = DPS_FAMILY[slot] or false end
            if family then
                -- The same stat can come back under two keys; count it once.
                if not stats[family] or abs(value) > abs(stats[family]) then stats[family] = value end
            elseif family == nil then
                unknown = unknown or {}
                unknown[key] = true
            end
        end
    end
    return stats, unknown
end

-- Weighted value of a set of stats: the total, each family's share, the
-- values used, and rating stats that couldn't be converted (not counted).
-- Rating weights are per 1% unless weights.perRatingPoint (stat priority).
function E.Score(stats, weights, ratingScale)
    local total, parts, values, uncounted = 0, {}, {}, nil
    for family, value in pairs(stats) do values[family] = value end
    -- Items list "+damage and healing" as spell power, as healing, or both.
    -- Where healing matters, count whichever is larger, once, as healing.
    if (weights.HEAL or 0) > 0 and values.SP then
        values.HEAL = math.max(values.HEAL or 0, values.SP)
    end
    for family, value in pairs(values) do
        local weight = weights[family] or 0
        if weight ~= 0 and W.RATINGS[family] and not weights.perRatingPoint then
            local perPoint = ratingScale and ratingScale[family]
            if perPoint then
                weight = weight * perPoint
            else
                uncounted = uncounted or {}
                uncounted[family] = true
                weight = 0
            end
        end
        if weight ~= 0 then
            parts[family] = weight * value
            total = total + parts[family]
        end
    end
    return { total = total, parts = parts, values = values, uncounted = uncounted }
end

local function Rate(raw, slot, who)
    local stats, unknown = E.Normalize(raw, slot)
    local score = E.Score(stats, who.weights, who.ratingScale)
    score.unknown = unknown
    return score
end

local function Merge(into, from)
    if not from then return into end
    into = into or {}
    for k in pairs(from) do into[k] = true end
    return into
end

-- Several worn items taken together (a main hand and off hand).
local function Combine(scores)
    local sum = { total = 0, parts = {}, values = {} }
    for _, s in ipairs(scores) do
        sum.total = sum.total + s.total
        for f, v in pairs(s.parts) do sum.parts[f] = (sum.parts[f] or 0) + v end
        for f, v in pairs(s.values) do sum.values[f] = (sum.values[f] or 0) + v end
        sum.uncounted = Merge(sum.uncounted, s.uncounted)
        sum.unknown = Merge(sum.unknown, s.unknown)
    end
    return sum
end

local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16, 17 },
    INVTYPE_WEAPONOFFHAND = { 16, 17 }, INVTYPE_SHIELD = { 16, 17 }, INVTYPE_HOLDABLE = { 16, 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Equipped slots needed to judge an item; nil for things we don't compare
-- (shirts, tabards, bags, ammo, anything that isn't worn).
function E.SlotsFor(equipLoc)
    return SLOTS[equipLoc]
end

-- True when this exact item is already worn where it would go.
function E.IsWorn(link, equipLoc, equipped)
    for _, slot in ipairs(SLOTS[equipLoc] or {}) do
        local worn = equipped[slot]
        if worn and worn.link == link then return true end
    end
    return false
end

local OFF_HAND_ONLY = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true, INVTYPE_WEAPONOFFHAND = true }

local function IsTwoHander(worn)
    return worn and worn.equipLoc == "INVTYPE_2HWEAPON"
end

local function IsWeapon(worn)
    return worn and (worn.equipLoc == "INVTYPE_WEAPON" or worn.equipLoc == "INVTYPE_WEAPONOFFHAND")
end

-- The ways an item could be worn: the slot it goes in and what it replaces.
-- Returns nil (plus a reason, if worth telling) when it can't be compared.
local function Options(equipLoc, equipped, canDualWield)
    local mainHand, offHand = equipped[16], equipped[17]
    if equipLoc == "INVTYPE_2HWEAPON" then
        return { { slot = 16, replaces = { 16, 17 } } }
    elseif equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" then
        local list = { { slot = 16, replaces = { 16 }, freesOffHand = IsTwoHander(mainHand) } }
        if equipLoc == "INVTYPE_WEAPON" and canDualWield and not IsTwoHander(mainHand)
            and (not offHand or IsWeapon(offHand)) then
            list[2] = { slot = 17, replaces = { 17 } }
        end
        return list
    elseif OFF_HAND_ONLY[equipLoc] then
        if equipLoc == "INVTYPE_WEAPONOFFHAND" and not canDualWield then return nil end
        if IsTwoHander(mainHand) then return nil, "twoHander" end
        return { { slot = 17, replaces = { 17 } } }
    end
    local list = {}
    for i, slot in ipairs(SLOTS[equipLoc]) do list[i] = { slot = slot, replaces = { slot } } end
    return list
end

local function HasUnweighedEffects(item)
    local fx = item.effects
    return fx and ((fx.use or 0) + (fx.proc or 0)) > 0 or false
end

-- Stat differences that moved the score, biggest effect first.
local function Changes(new, old)
    local list, seen = {}, {}
    local function Add(family)
        if seen[family] then return end
        seen[family] = true
        local weight = (new.parts[family] or 0) - (old.parts[family] or 0)
        if abs(weight) > 0.001 then
            list[#list + 1] = { family = family, delta = (new.values[family] or 0) - (old.values[family] or 0), weight = weight }
        end
    end
    for family in pairs(new.values) do Add(family) end
    for family in pairs(old.values) do Add(family) end
    table.sort(list, function(a, b)
        if abs(a.weight) ~= abs(b.weight) then return abs(a.weight) > abs(b.weight) end
        return a.family < b.family
    end)
    return list
end

-- Stats that differ but carry no weight for you, so the tooltip can say they
-- were left out on purpose. Armor is skipped: nearly every comparison has it.
local function Unweighted(new, old)
    local labels, seen = {}, {}
    local function Add(family)
        if seen[family] or family == "ARMOR" then return end
        seen[family] = true
        local counted = new.parts[family] or old.parts[family]
        local skipped = (new.uncounted and new.uncounted[family]) or (old.uncounted and old.uncounted[family])
        if not counted and not skipped and abs((new.values[family] or 0) - (old.values[family] or 0)) > 0.001 then
            labels[#labels + 1] = E.Label(family)
        end
    end
    for family in pairs(new.values) do Add(family) end
    for family in pairs(old.values) do Add(family) end
    table.sort(labels)
    return labels
end

local function NotCounted(new, old)
    local labels, seen = {}, {}
    local function Add(set)
        for key in pairs(set or {}) do
            local label = E.Label(key)
            if not seen[label] then seen[label] = true; labels[#labels + 1] = label end
        end
    end
    Add(new.uncounted); Add(old.uncounted); Add(new.unknown); Add(old.unknown)
    table.sort(labels)
    return labels
end

-- item:     { link, equipLoc, raw = GetItemStats table, effects = { use, proc } }
-- equipped: [slot] = item like the above, or false when the slot is empty
-- who:      { weights, ratingScale, canDualWield, likely, possible }
-- Returns nil for items that aren't compared at all, else a result with
-- verdict = "likely" | "possible" | "empty" | "similar" | "worse" | "unknown" | "twoHander".
function E.Compare(item, equipped, who)
    local options, reason = Options(item.equipLoc, equipped, who.canDualWield)
    if not options then
        return reason and { verdict = reason } or nil
    end

    local best
    for _, option in ipairs(options) do
        local new = Rate(item.raw, option.slot, who)
        local worn, scores = {}, {}
        for _, slot in ipairs(option.replaces) do
            local w = equipped[slot]
            if w then
                worn[#worn + 1] = w
                scores[#scores + 1] = Rate(w.raw, slot, who)
            end
        end
        local old = Combine(scores)
        local delta = new.total - old.total
        if not best or delta > best.delta then
            best = { option = option, new = new, old = old, worn = worn, delta = delta }
        end
    end

    local new, old, delta = best.new, best.old, best.delta
    local effects = HasUnweighedEffects(item)
    for _, w in ipairs(best.worn) do effects = effects or HasUnweighedEffects(w) end

    local result = {
        against = best.worn,
        freesOffHand = best.option.freesOffHand or nil,
        effects = effects,
        changes = Changes(new, old),
        unweighted = Unweighted(new, old),
        notCounted = NotCounted(new, old),
    }
    local floor = W.MIN_DIFFERENCE
    if #best.worn == 0 then
        result.verdict = new.total >= floor and "empty" or "unknown"
    elseif abs(new.total) < floor and abs(old.total) < floor then
        result.verdict = "unknown"
    elseif abs(delta) < floor then
        result.verdict = "similar"
    else
        local likely, possible = who.likely or W.LIKELY, who.possible or W.POSSIBLE
        local ratio = old.total > 0 and delta / old.total or (delta > 0 and math.huge or -math.huge)
        if ratio >= likely and not effects then
            result.verdict = "likely"
        elseif ratio >= possible then
            result.verdict = "possible"
        elseif ratio > -possible then
            result.verdict = "similar"
        else
            result.verdict = "worse"
        end
    end
    return result
end
