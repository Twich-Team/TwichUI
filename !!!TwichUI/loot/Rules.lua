-- TwichUI: Loot Rolls, the rule engine
-- Pure: no frame, no event, no saved data, no game call except for words (item class and slot names come from the
-- game's own strings so nothing is guessed from a translation). A rule says "when an item matches these conditions,
-- optionally roll Need, Greed or Pass and/or change card display". This file knows what a condition is, whether a rule is complete, and what a rule says about one
-- item. loot/Config.lua keeps the rules, loot/Roll.lua observes the roll and builds the item's facts, loot/Auto.lua acts.
--
-- Three answers, never two. A condition about an item answers "match", "no" or "unknown" (the fact is not there yet, or this client
-- does not say). Unknown is not a match, and negating a condition ("not a recipe") leaves it unknown. A rule's answer is built from
-- its conditions' (all: one "no" is a "no", otherwise one unknown is unknown; any: one match is a match, otherwise one unknown is unknown).
--
-- Groups: a condition of type "group" ({ type = "group", match = "all" | "any", conditions = { ... } }) holds a list of conditions of its
-- own, answered by the same three-valued rule, so (A or B) and C is match "all" over { group any { A, B }, C }. A group is not a
-- condition the picker offers: it is made by Config.lua's AddGroup. Limits: Ru.MAX_CONDITIONS conditions in all (groups not counted),
-- Ru.MAX_GROUPS groups, Ru.MAX_DEPTH levels counting the top as the first. An empty or over-deep group makes the rule incomplete. No
-- migration: a build from before groups reads a group as a condition of an unknown kind, so the rule is incomplete there and never acts.
--
-- Priority: the rules are read from the top. The first enabled (exactly true: a rule that never said it was on is off, as the editor shows it), complete rule that is not a definite "no" decides:
-- "match" is a decision; "unknown" stops the search with no decision (a rule above may have matched, so a rule below must not speak
-- for it). Roll and display decisions use this order independently; No change is skipped per channel. A rule with nothing in it, or a condition that is not valid, is incomplete:
-- it is skipped, and the editor says why.
--
-- The facts (an "observation") are a plain table; a missing field is unknown:
--   link, itemID, name, quality (0-5), classID, subClassID, equipLoc ("INVTYPE_..." or ""), bindType (0 none, 1 pickup, 2 equip, 3 use, 4 quest),
--   equippable (true: the player can equip it now; false: it is not gear, or the game marks something about it as unusable; the level
--   requirement does not count, since level fixes itself), upgrade (true / false), recipe = { isRecipe, profession (the player has this recipe's profession), known, canLearn },
--   context = { instanceType ("none", "party", "raid", ...), inRaidGroup }

local R = TwichUI
local Families = R.ForeverItemFamilies
local Ru = {}
R.LootRules = Ru

Ru.MATCH, Ru.NO, Ru.UNKNOWN = "match", "no", "unknown"
Ru.ACTIONS = { "need", "greed", "pass" }
Ru.ACTION_LABEL = { need = "Need", greed = "Greed", pass = "Pass", none = "No change" }
Ru.DISPLAY_LABEL = { none = "No change", expanded = "Expanded", collapsed = "Collapsed (Mini)" }
Ru.MAX_CONDITIONS = 8   -- conditions in one rule, in all its groups together (a group is not a condition)
Ru.MAX_GROUPS = 4       -- groups in one rule, at any depth (the top level is not one)
Ru.MAX_DEPTH = 3        -- levels of conditions: the top level is 1, a group in it 2, a group in that 3
Ru.MAX_NAME = 40

local function Whole(v) return type(v) == "number" and v == v and v % 1 == 0 and v ~= math.huge and v ~= -math.huge end

local function GameString(name, fallback)
    local v = _G[name]
    if type(v) == "string" and v ~= "" then return v end
    return fallback
end

---------------------------------------------------------------------------
-- Words the conditions use
---------------------------------------------------------------------------
Ru.QUALITY_NAME = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" }
function Ru.QualityName(q)
    return GameString("ITEM_QUALITY" .. tostring(q) .. "_DESC", Ru.QUALITY_NAME[q] or "?")
end
-- The quality colors the game uses (also what a card draws its name with), as r, g, b.
Ru.QUALITY_COLOR = {
    [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 },
}

-- Item classes a rule can name. "equipment" is weapons and armor taken together.
Ru.CLASS_CHOICES = {
    { "equipment", "Equipment" }, { 2, "Weapon" }, { 4, "Armor" }, { 9, "Recipe" }, { 0, "Consumable" }, { 7, "Trade goods" },
    { 5, "Reagent" }, { 3, "Gem" }, { 1, "Container" }, { 12, "Quest item" }, { 15, "Miscellaneous" },
}
local CLASS_NAME = {}
for _, c in ipairs(Ru.CLASS_CHOICES) do CLASS_NAME[c[1]] = c[2] end
function Ru.ClassName(value)
    if value == "equipment" then return "Equipment" end
    local name = Whole(value) and GetItemClassInfo and GetItemClassInfo(value)
    if type(name) == "string" and name ~= "" then return name end
    return CLASS_NAME[value] or "?"
end

-- Slots, by the game's own equip location (INVTYPE_*); each one's words are the game's global string of the same name.
Ru.EQUIP_CHOICES = {
    { "INVTYPE_HEAD", "Head" }, { "INVTYPE_NECK", "Neck" }, { "INVTYPE_SHOULDER", "Shoulder" }, { "INVTYPE_CLOAK", "Back" },
    { "INVTYPE_CHEST", "Chest" }, { "INVTYPE_WRIST", "Wrist" }, { "INVTYPE_HAND", "Hands" }, { "INVTYPE_WAIST", "Waist" },
    { "INVTYPE_LEGS", "Legs" }, { "INVTYPE_FEET", "Feet" }, { "INVTYPE_FINGER", "Finger" }, { "INVTYPE_TRINKET", "Trinket" },
    { "INVTYPE_WEAPON", "One-hand" }, { "INVTYPE_2HWEAPON", "Two-hand" }, { "INVTYPE_WEAPONMAINHAND", "Main hand" },
    { "INVTYPE_WEAPONOFFHAND", "Off hand" }, { "INVTYPE_HOLDABLE", "Held in off-hand" }, { "INVTYPE_SHIELD", "Shield" },
    { "INVTYPE_RANGED", "Ranged" }, { "INVTYPE_RANGEDRIGHT", "Ranged (wand, gun, crossbow)" }, { "INVTYPE_THROWN", "Thrown" },
    { "INVTYPE_RELIC", "Relic" },
}
local EQUIP_NAME = {}
for _, c in ipairs(Ru.EQUIP_CHOICES) do EQUIP_NAME[c[1]] = c[2] end
function Ru.EquipName(loc)
    return GameString(loc, EQUIP_NAME[loc] or "?")
end

-- Armor types (item class 4). The sub-class numbers are the game's; the words come from the game's own item strings when it has them.
Ru.ARMOR_CHOICES = { { 1, "Cloth" }, { 2, "Leather" }, { 3, "Mail" }, { 4, "Plate" }, { 6, "Shield" } }
local ARMOR_NAME = {}
for _, c in ipairs(Ru.ARMOR_CHOICES) do ARMOR_NAME[c[1]] = c[2] end
function Ru.ArmorName(sub)
    local name = Whole(sub) and GetItemSubClassInfo and GetItemSubClassInfo(4, sub)
    if type(name) == "string" and name ~= "" then return name end
    return ARMOR_NAME[sub] or "?"
end

Ru.RECIPE_CHOICES = {
    { "profession", "A recipe for one of my professions" },
    { "learnable", "A recipe I can learn now" },
    { "known", "A recipe I already know" },
    { "any", "Any recipe" },
}
Ru.CONTEXT_CHOICES = {
    { "outsideRaid", "Only outside raids" }, { "inRaid", "Only in raids" },
    { "inDungeon", "Only in dungeons" }, { "outsideDungeon", "Only outside dungeons" },
}
Ru.FAMILY_CHOICES = { { "waylaid-crates", "Waylaid crate" }, { "craftsmans-writs", "Craftsman's Writ" } }
local FAMILY_MATCH = {
    ["waylaid-crates"] = Families.IsWaylaidCrate,
    ["craftsmans-writs"] = Families.IsCraftsmansWrit,
}
local FAMILY_LABEL = {}
for _, choice in ipairs(Ru.FAMILY_CHOICES) do FAMILY_LABEL[choice[1]] = choice[2] end

Ru.BIND_CHOICES = { { "pickup", "Binds when picked up" }, { "equip", "Binds when equipped" } }
Ru.QUALITY_OPS = { { "is", "is" }, { "atLeast", "is at least" }, { "atMost", "is at most" } }

local function InList(list, value)
    for _, c in ipairs(list) do if c[1] == value then return true end end
    return false
end

---------------------------------------------------------------------------
-- The conditions. Each: label (the picker), icon (an R.Icons id, optional), new() (a fresh one), check(c) (nil when complete,
-- else why not), eval(c, obs, opts) -> true / false / nil (nil: unknown), phrase(c) (what it says in a sentence).
-- A condition's `negate` turns a true into a false and back, and leaves unknown as it is.
---------------------------------------------------------------------------
local T = {}
Ru.TYPES = T
Ru.ORDER = { "quality", "class", "armor", "equippable", "equip", "recipe", "item", "family", "bind", "upgrade", "context" }

T.quality = {
    label = "Item quality", icon = "lootQuality",
    new = function() return { type = "quality", op = "is", value = 2 } end,
    check = function(c)
        if not InList(Ru.QUALITY_OPS, c.op) then return "Choose how to compare the quality." end
        if not (Whole(c.value) and c.value >= 0 and c.value <= 5) then return "Choose a quality." end
    end,
    eval = function(c, obs)
        local q = obs.quality
        if not Whole(q) then return nil end
        if c.op == "is" then return q == c.value end
        if c.op == "atLeast" then return q >= c.value end
        return q <= c.value
    end,
    phrase = function(c)
        local name = Ru.QualityName(c.value)
        if c.op == "atLeast" then return "is " .. name .. " or better" end
        if c.op == "atMost" then return "is " .. name .. " or worse" end
        return "is " .. name
    end,
}

T.class = {
    label = "Item type", icon = "lootType",
    new = function() return { type = "class", value = "equipment" } end,
    check = function(c)
        if c.value == "equipment" or (Whole(c.value) and CLASS_NAME[c.value] ~= nil) then return nil end
        return "Choose an item type."
    end,
    eval = function(c, obs)
        local id = obs.classID
        if not Whole(id) then return nil end
        if c.value == "equipment" then
            if id ~= 2 and id ~= 4 then return false end
            -- shirts and the like are armor that goes nowhere: equipment is what has a slot
            local loc = obs.equipLoc
            if type(loc) ~= "string" then return nil end
            return loc ~= "" and loc ~= "INVTYPE_NON_EQUIP" and loc ~= "INVTYPE_BAG"
        end
        return id == c.value
    end,
    phrase = function(c) return "is " .. (c.value == "equipment" and "equipment" or Ru.ClassName(c.value):lower()) end,
}

T.armor = {
    label = "Armor type", icon = "lootType",
    new = function() return { type = "armor", value = 1 } end,
    check = function(c) if not (Whole(c.value) and ARMOR_NAME[c.value] ~= nil) then return "Choose an armor type." end end,
    eval = function(c, obs)
        local id = obs.classID
        if not Whole(id) then return nil end
        if id ~= 4 then return false end   -- a weapon, a potion or a recipe is no kind of armor
        local sub = obs.subClassID
        if not Whole(sub) then return nil end
        return sub == c.value
    end,
    phrase = function(c) return "is " .. Ru.ArmorName(c.value):lower() .. " armor" end,
}

T.equippable = {
    label = "Can I equip it", icon = "lootSlot",
    new = function() return { type = "equippable", value = true } end,
    check = function(c) if type(c.value) ~= "boolean" then return "Choose whether you can equip it." end end,
    eval = function(c, obs)
        local e = obs.equippable
        if type(e) ~= "boolean" then return nil end
        return e == c.value
    end,
    phrase = function(c) return c.value and "is something I can equip" or "is something I can't equip" end,
}

T.equip = {
    label = "Equipment slot", icon = "lootSlot",
    new = function() return { type = "equip", value = "INVTYPE_HEAD" } end,
    check = function(c) if not InList(Ru.EQUIP_CHOICES, c.value) then return "Choose a slot." end end,
    eval = function(c, obs)
        local loc = obs.equipLoc
        if type(loc) ~= "string" then return nil end
        -- the game reports a chest piece two ways, and a one-hand weapon that can go either hand as INVTYPE_WEAPON
        if c.value == "INVTYPE_CHEST" and loc == "INVTYPE_ROBE" then return true end
        return loc == c.value
    end,
    phrase = function(c) return "goes in the " .. Ru.EquipName(c.value):lower() .. " slot" end,
}

T.recipe = {
    label = "Profession recipe", icon = "lootRecipe",
    new = function() return { type = "recipe", mode = "profession" } end,
    check = function(c) if not InList(Ru.RECIPE_CHOICES, c.mode) then return "Choose which recipes." end end,
    eval = function(c, obs)
        local r = obs.recipe
        if type(r) ~= "table" or r.isRecipe == nil then return nil end
        if r.isRecipe == false then return false end
        if c.mode == "any" then return true end
        if c.mode == "profession" then return r.profession end
        if c.mode == "known" then return r.known end
        -- learnable: yours (the profession), not known, and nothing the game says stands in the way
        if r.profession == false or r.known == true then return false end
        if r.profession == nil or r.known == nil then return nil end
        return r.canLearn
    end,
    phrase = function(c)
        if c.mode == "learnable" then return "is a recipe I can learn" end
        if c.mode == "known" then return "is a recipe I already know" end
        if c.mode == "any" then return "is a recipe" end
        return "is a recipe for one of my professions"
    end,
}

T.item = {
    label = "Specific item", icon = "lootItem",
    new = function() return { type = "item", id = 0 } end,
    check = function(c) if not (Whole(c.id) and c.id > 0 and c.id < 10000000) then return "Name an item (its link or number)." end end,
    eval = function(c, obs)
        if not Whole(obs.itemID) then return nil end
        return obs.itemID == c.id
    end,
    phrase = function(c)
        local name = c.name
        if type(name) == "string" and name ~= "" then return "is " .. name end
        return "is item #" .. tostring(c.id)
    end,
}

T.family = {
    label = "Item family", icon = "lootItem",
    new = function() return { type = "family", value = "waylaid-crates" } end,
    check = function(c) if not FAMILY_MATCH[c.value] then return "Choose an item family." end end,
    eval = function(c, obs)
        local id = obs.itemID
        if not Whole(id) or id <= 0 then return nil end
        return FAMILY_MATCH[c.value](id)
    end,
    phrase = function(c) return "is a " .. FAMILY_LABEL[c.value] end,
}

T.bind = {
    label = "Binding", icon = "lootBind",
    new = function() return { type = "bind", value = "equip" } end,
    check = function(c) if not InList(Ru.BIND_CHOICES, c.value) then return "Choose a binding." end end,
    eval = function(c, obs)
        local b = obs.bindType
        if not Whole(b) then return nil end
        return b == (c.value == "pickup" and 1 or 2)
    end,
    phrase = function(c) return c.value == "pickup" and "binds when picked up" or "binds when equipped" end,
}

T.upgrade = {
    label = "Potential upgrade", icon = "lootUpgrade", usesUpgrade = true,
    new = function() return { type = "upgrade", value = true } end,
    check = function(c) if type(c.value) ~= "boolean" then return "Choose whether it is an upgrade." end end,
    eval = function(c, obs, opts)
        -- an upgrade is a hint, never a reason to roll by itself: it counts only when the player allowed rolls to use it
        if not (opts and opts.allowUpgrade == true) then return nil end
        local u = obs.upgrade
        if u == nil then return nil end
        return u == c.value
    end,
    phrase = function(c) return c.value and "is a potential upgrade" or "is not a potential upgrade" end,
}

T.context = {
    label = "Where you are", icon = "lootWhere",
    new = function() return { type = "context", value = "outsideRaid" } end,
    check = function(c) if not InList(Ru.CONTEXT_CHOICES, c.value) then return "Choose where this applies." end end,
    eval = function(c, obs)
        local x = obs.context
        if type(x) ~= "table" or type(x.instanceType) ~= "string" then return nil end
        local raid = x.instanceType == "raid"
        local dungeon = x.instanceType == "party"
        if c.value == "inRaid" then return raid end
        if c.value == "outsideRaid" then return not raid end
        if c.value == "inDungeon" then return dungeon end
        return not dungeon
    end,
    phrase = function(c)
        return ({ outsideRaid = "you are outside a raid", inRaid = "you are in a raid", inDungeon = "you are in a dungeon",
            outsideDungeon = "you are outside a dungeon" })[c.value]
    end,
}

---------------------------------------------------------------------------
-- Conditions and rules
---------------------------------------------------------------------------
local function IsGroup(c) return type(c) == "table" and c.type == "group" end
Ru.IsGroup = IsGroup

-- What a list of conditions holds (groups counted, and how deep it goes), reading no further than the limits allow, so a table that
-- loops or nests absurdly is only ever read a few levels. depth is the level of this list (the top is 1).
local function Measure(list, depth, st)
    st = st or { conditions = 0, groups = 0, depth = depth }
    if depth > st.depth then st.depth = depth end
    if depth > Ru.MAX_DEPTH + 1 then return st end
    for _, c in ipairs(list) do
        if IsGroup(c) then
            st.groups = st.groups + 1
            if type(c.conditions) == "table" then Measure(c.conditions, depth + 1, st) end
        else
            st.conditions = st.conditions + 1
        end
    end
    return st
end
function Ru.Measure(list) return Measure(type(list) == "table" and list or {}, 1) end

-- Why a list of conditions (the top level's, or a group's) is not usable: nil when it is. path is where the list sits, for the words.
local function ListProblem(list, depth, path)
    if type(list) ~= "table" or #list == 0 then
        if depth == 1 then return "Add at least one condition: a rule with none would match every item." end
        return ("Group %s: add a condition or remove the group."):format(table.concat(path, "."))
    end
    for i, c in ipairs(list) do
        local at = { unpack(path) }
        at[#at + 1] = i
        local label = table.concat(at, ".")
        if IsGroup(c) then
            if depth + 1 > Ru.MAX_DEPTH then return ("Group %s: groups can go only %d levels deep."):format(label, Ru.MAX_DEPTH) end
            if c.match ~= "all" and c.match ~= "any" then return ("Group %s: choose all or any."):format(label) end
            if c.negate ~= nil then return ("Group %s: invalid."):format(label) end
            local why = ListProblem(c.conditions, depth + 1, at)
            if why then return why end
        else
            local why = Ru.CheckCondition(c)
            if why then return ("Condition %s: %s"):format(label, why) end
        end
    end
end

-- nil when the condition is complete, else why not. A group is complete when everything in it is.
function Ru.CheckCondition(c)
    if type(c) ~= "table" then return "Not a condition." end
    if IsGroup(c) then
        if c.match ~= "all" and c.match ~= "any" then return "Choose all or any." end
        if c.negate ~= nil then return "Invalid." end
        return ListProblem(c.conditions, 2, {})   -- its own list is level 2 from here: a group in it may go on one level, no more (Incomplete reads the whole rule)
    end
    local t = T[c.type]
    if not t then return "Unknown kind of condition." end
    if c.negate ~= nil and type(c.negate) ~= "boolean" then return "Invalid." end
    return t.check(c)
end

function Ru.NewCondition(kind)
    local t = T[kind]
    return t and t.new() or nil
end

-- One list of conditions about one item, "all" or "any": match, Ru.NO or Unknown.
local function EvalList(match, list, obs, opts)
    local sawNo, sawYes, sawUnknown = false, false, false
    for _, c in ipairs(list) do
        local v = Ru.EvalCondition(c, obs, opts)
        if v == nil then sawUnknown = true elseif v then sawYes = true else sawNo = true end
    end
    if match == "any" then
        if sawYes then return Ru.MATCH end
        return sawUnknown and Ru.UNKNOWN or Ru.NO
    end
    if sawNo then return Ru.NO end
    return sawUnknown and Ru.UNKNOWN or Ru.MATCH
end

local ANSWER = { match = true, no = false }

-- true, false or nil for one condition about one item. A group answers as its own list does.
function Ru.EvalCondition(c, obs, opts)
    if type(c) ~= "table" then return nil end
    if IsGroup(c) then
        if Ru.CheckCondition(c) ~= nil then return nil end
        return ANSWER[EvalList(c.match, c.conditions, obs or {}, opts)]   -- unknown has no entry: nil
    end
    local t = T[c.type]
    -- the same completeness the editor reports (a negate that is not a real boolean included): an unfinished condition never answers
    if not t or Ru.CheckCondition(c) ~= nil then return nil end
    local ok, value = pcall(t.eval, c, obs or {}, opts)
    if not ok or type(value) ~= "boolean" then return nil end
    if c.negate then return not value end
    return value
end

-- nil when the rule can run, else why not (words for the editor).
function Ru.Incomplete(rule)
    if type(rule) ~= "table" then return "Not a rule." end
    if not Ru.ACTION_LABEL[rule.action] then return "Choose a roll action (or No change)." end
    if not Ru.DISPLAY_LABEL[rule.display or "none"] then return "Choose a valid card display." end
    if rule.action == "none" and (rule.display == nil or rule.display == "none") then return "Choose a roll or card display action; both are No change." end
    local list = rule.conditions
    if type(list) ~= "table" or #list == 0 then return "Add at least one condition: a rule with none would match every item." end
    local m = Measure(list, 1)
    if m.depth > Ru.MAX_DEPTH or m.conditions > Ru.MAX_CONDITIONS or m.groups > Ru.MAX_GROUPS then
        if m.depth > Ru.MAX_DEPTH then return ("Groups can go only %d levels deep."):format(Ru.MAX_DEPTH) end
        if m.groups > Ru.MAX_GROUPS then return "Too many groups." end
        return "Too many conditions."
    end
    return ListProblem(list, 1, {})
end

-- Match, Ru.NO or Unknown for one rule about one item (ignores whether it is switched on).
function Ru.EvalRule(rule, obs, opts)
    if Ru.Incomplete(rule) then return Ru.UNKNOWN end
    return EvalList(rule.match, rule.conditions, obs, opts)
end

-- What the rules say about one item. Returns { status = "match" | "unknown" | "none", rule, index }:
--   match: rule (the first one that matched, and no rule above it was unknown) is the decision;
--   unknown: rule is the one above that could not be answered: nobody decides (the roll stays manual);
--   none: no rule had anything to say.
function Ru.Decide(rules, obs, opts)
    if type(rules) ~= "table" then return { status = "none" } end
    for i, rule in ipairs(rules) do
        if type(rule) == "table" and rule.enabled == true and rule.action ~= "none" and not Ru.Incomplete(rule) then
            local v = Ru.EvalRule(rule, obs, opts)
            if v == Ru.MATCH then return { status = "match", rule = rule, index = i } end
            if v == Ru.UNKNOWN then return { status = "unknown", rule = rule, index = i } end
        end
    end
    return { status = "none" }
end

-- Display has its own ordered decision. Unknown blocks only this channel;
-- rules with no explicit display never participate, even when their roll wins.
function Ru.DecideDisplay(rules, obs)
    if type(rules) ~= "table" then return { status = "none" } end
    for i, rule in ipairs(rules) do
        if type(rule) == "table" and rule.enabled == true and (rule.display == "expanded" or rule.display == "collapsed")
            and not Ru.Incomplete(rule) then
            local v = Ru.EvalRule(rule, obs, { allowUpgrade = true })
            if v ~= Ru.NO then return { status = v, rule = rule, index = i } end
        end
    end
    return { status = "none" }
end

function Ru.ActionSummary(rule)
    local action = rule.action ~= "none" and Ru.ACTION_LABEL[rule.action] or nil
    local display = rule.display == "collapsed" and "Collapsed" or rule.display == "expanded" and "Expanded" or nil
    if action and display then return action .. " · " .. display end
    return action or (display and (rule.display == "collapsed" and "Collapse card" or "Expand card")) or "No action"
end

-- What one condition (or a block, in parentheses) says in a sentence; nil when it is not finished.
function Ru.Phrase(c)
    if not IsGroup(c) then
        local t = type(c) == "table" and T[c.type]
        if not (t and t.check(c) == nil) then return nil end
        local text = t.phrase(c)
        if c.negate then text = "not (" .. text .. ")" end
        return text
    end
    if Ru.CheckCondition(c) ~= nil then return nil end
    local inner = {}
    for _, child in ipairs(c.conditions) do inner[#inner + 1] = Ru.Phrase(child) end
    if #inner == 0 then return nil end
    return "(" .. table.concat(inner, c.match == "any" and " or " or " and ") .. ")"
end

-- A sentence for a rule: "Automatically choose Greed when the item is Uncommon and is equipment, after 3 seconds."
function Ru.Summary(rule)
    if type(rule) ~= "table" then return "" end
    local action = Ru.ACTION_LABEL[rule.action]
    if not action then return "Choose a roll action or card display to finish this rule." end
    local parts = {}
    for _, c in ipairs(rule.conditions or {}) do
        local text = Ru.Phrase(c)
        if text then parts[#parts + 1] = text end
    end
    if #parts == 0 then return ("Choose %s once you add a condition."):format(action) end
    local joiner = rule.match == "any" and " or " or " and "
    local subject
    local first = type(rule.conditions[1]) == "table" and rule.conditions[1].type
    if first == "context" then subject = "when " .. table.concat(parts, joiner) else subject = "when the item " .. table.concat(parts, joiner) end
    local delay = tonumber(rule.delay) or 0
    local after = delay > 0 and (", after %s second%s"):format(delay % 1 == 0 and tostring(math.floor(delay)) or ("%.1f"):format(delay), delay == 1 and "" or "s") or ""
    local display = rule.display == "collapsed" and "collapse the card" or rule.display == "expanded" and "expand the card" or nil
    if rule.action == "none" then
        return display and (display:gsub("^%l", string.upper) .. " " .. subject .. ".") or "Choose a roll or card display action."
    end
    return ("Automatically choose %s %s%s%s."):format(action, subject, after, display and ("; " .. display) or "")
end
