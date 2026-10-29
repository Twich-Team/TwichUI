-- TwichUI: Reminders, the kinds of condition
-- One provider per kind. A provider knows its stored fields and checks them, says which observations it reads, decides
-- from them (pure: it reads a table of plain facts, never the game), and puts a condition, what it saw and a set of
-- made-up situations for the Test section into words. The live facts are State.lua's; a simulation hands the same
-- functions a table of its own.
--
-- A provider (C.Register):
--   type        its stable id, stored in each condition as `type` (never a label)
--   label       its name in the editor's "Add a condition" choices
--   New()       a new condition of this kind, as stored
--   Check(raw)  -> clean copy (nil: not usable at all), problem (a sentence, nil when it is complete)
--   Needs(cond, add)      calls add(key) for each observation it reads: "slot:17", "combat", ... (State.lua's sources)
--   Evaluate(cond, obs)   -> C.MATCH | C.NOMATCH | C.UNKNOWN, and for UNKNOWN a short reason
--   Summary(cond)         -> "Off hand is not Shield"
--   Observed(cond, obs)   -> "Empty", "Out of combat", "Not read yet"
--   Scenarios(cond)       -> { { key, label, Apply = function(obs) end }, ... } for the Test section, first one default
-- Optional:
--   Subject(cond)         -> key, label of what in the world it asks about, when several conditions in one rule can ask
--                            the same thing ("class"): a simulation offers one choice for all of them, so the made-up
--                            facts can't contradict each other. Their Scenarios must not depend on the condition's value.
--   Merge(match, conds)   -> words, used: for the rule's sentence. conds are this kind's conditions that sit directly in
--                            one group matching on `match` ("all" | "any"); words say a run of them in one phrase and
--                            used lists the indexes of conds it covers (nil: nothing to merge).
-- Adding a kind: register it here (or in a file of its own loaded after this one), give State.lua a source for each
-- observation key it names, and give the editor (TwichUI_Settings/pages/RemindersEditor.lua) its fields.
--
-- What the game provides (read from the Forever UI source; docs/reminders.md has the references):
--   * equipment slots INVSLOT_HEAD (1) .. INVSLOT_TABARD (19) (Blizzard_FrameXMLBase/Constants.lua);
--   * an item's class, subclass and equip location from C_Item.GetItemInfoInstant, without waiting for the item cache:
--     a shield is Enum.ItemClass.Armor (4) with Enum.ItemArmorSubclass.Shield (6); a weapon is Enum.ItemClass.Weapon (2),
--     a fishing pole its subclass Fishingpole (20) (ItemConstantsDocumentation.lua); two-handed and held-in-off-hand are
--     the equip locations INVTYPE_2HWEAPON and INVTYPE_HOLDABLE (the game's own DressUpModelFrameMixin reads them);
--   * UnitAffectingCombat and the combat events, UnitIsDeadOrGhost / UnitIsGhost, IsMounted (UnitDocumentation.lua,
--     PlayerScriptDocumentation.lua). None of it is used by name or by localized text.

local R = TwichUI
local C = { providers = {}, order = {} }
R.ReminderConditions = C

C.MATCH, C.NOMATCH, C.UNKNOWN = "match", "nomatch", "unknown"
local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN

-- An item's name when the game has it ready (State.lua sets this to the game's lookup; it never asks for one to be
-- loaded). Offline, and before it is set, items are named by their ID.
C.ItemName = function() return nil end

local function ItemWords(id)
    if not id then return "an item" end
    local name = C.ItemName(id)
    if type(name) == "string" and name ~= "" then return name end
    return ("item %d"):format(id)
end
C.ItemWords = ItemWords

function C.Register(def)
    assert(type(def.type) == "string" and def.type:match("^[%w_]+$"), "a provider needs a type id")
    for _, f in ipairs({ "New", "Check", "Needs", "Evaluate", "Summary", "Observed", "Scenarios" }) do
        assert(type(def[f]) == "function", "a provider needs " .. f)
    end
    if not C.providers[def.type] then C.order[#C.order + 1] = def.type end
    C.providers[def.type] = def
end

function C.Get(kind) return type(kind) == "string" and C.providers[kind] or nil end

-- The providers in the order the editor offers them.
function C.List()
    local out = {}
    for i, kind in ipairs(C.order) do out[i] = C.providers[kind] end
    return out
end

-- A stored condition checked by its provider: clean copy (or nil), problem, provider.
function C.Check(raw)
    if type(raw) ~= "table" then return nil, "it isn't a condition TwichUI can read. Remove it." end
    local p = C.Get(raw.type)
    if not p then
        local kind = type(raw.type) == "string" and raw.type:match("^[%w_]+$") and #raw.type <= 24 and raw.type or "unknown"
        return nil, ("it is of a kind this version of TwichUI doesn't know (%s). It is kept, but the reminder can't run until it is removed."):format(kind), nil
    end
    local clean, problem = p.Check(raw)
    if not clean then return nil, problem or "its settings can't be read. Remove it and add it again.", p end
    return clean, problem, p
end

local function Negate(result, negate)
    if not negate or result == UNKNOWN then return result end
    return result == MATCH and NOMATCH or MATCH
end
C.Negate = Negate

local function Yes(v) return v and MATCH or NOMATCH end

---------------------------------------------------------------------------
-- Equipment
---------------------------------------------------------------------------
local E = Enum or {}
local CLASS = E.ItemClass or {}
local ARMOR_SUB = E.ItemArmorSubclass or {}
local WEAPON_SUB = E.ItemWeaponSubclass or {}
local ARMOR, WEAPON = CLASS.Armor or 4, CLASS.Weapon or 2
local SHIELD, FISHING = ARMOR_SUB.Shield or 6, WEAPON_SUB.Fishingpole or 20

-- key (stored), label, the facts an example of it has (for the Test section)
C.CATEGORIES = {
    { "shield", "Shield", function(f) return f.classID == ARMOR and f.subClassID == SHIELD end,
        { classID = ARMOR, subClassID = SHIELD, equipLoc = "INVTYPE_SHIELD", label = "A shield" } },
    { "fishingPole", "Fishing pole", function(f) return f.classID == WEAPON and f.subClassID == FISHING end,
        { classID = WEAPON, subClassID = FISHING, equipLoc = "INVTYPE_2HWEAPON", label = "A fishing pole" } },
    { "twoHand", "Two-handed weapon", function(f) return f.equipLoc == "INVTYPE_2HWEAPON" end,
        { classID = WEAPON, subClassID = 8, equipLoc = "INVTYPE_2HWEAPON", label = "A two-handed weapon" } },
    { "weapon", "Weapon", function(f) return f.classID == WEAPON end,
        { classID = WEAPON, subClassID = 7, equipLoc = "INVTYPE_WEAPON", label = "A one-handed weapon" } },
    { "holdable", "Held in off hand", function(f) return f.equipLoc == "INVTYPE_HOLDABLE" end,
        { classID = ARMOR, subClassID = 0, equipLoc = "INVTYPE_HOLDABLE", label = "An item held in the off hand" } },
}
local CATEGORY = {}
for _, c in ipairs(C.CATEGORIES) do CATEGORY[c[1]] = c end
-- What stands in for "something else" in a slot, beside each category's own example.
local OTHER = {
    shield = { classID = WEAPON, subClassID = 7, equipLoc = "INVTYPE_WEAPONOFFHAND", label = "An off-hand weapon" },
    weapon = { classID = ARMOR, subClassID = SHIELD, equipLoc = "INVTYPE_SHIELD", label = "A shield" },
    twoHand = { classID = WEAPON, subClassID = 7, equipLoc = "INVTYPE_WEAPON", label = "A one-handed weapon" },
    holdable = { classID = ARMOR, subClassID = SHIELD, equipLoc = "INVTYPE_SHIELD", label = "A shield" },
    fishingPole = { classID = WEAPON, subClassID = 8, equipLoc = "INVTYPE_2HWEAPON", label = "A two-handed weapon" },
}

local function G(name, fallback) local v = rawget(_G, name) return type(v) == "number" and v or fallback end

-- key (stored, never a number), slot number, label, the categories it can be judged by
C.SLOTS = {
    { "offHand", G("INVSLOT_OFFHAND", 17), "Off hand", { "shield", "weapon", "holdable" } },
    { "mainHand", G("INVSLOT_MAINHAND", 16), "Main hand", { "weapon", "twoHand", "fishingPole" } },
    { "ranged", G("INVSLOT_RANGED", 18), "Ranged", { "weapon" } },
    { "head", G("INVSLOT_HEAD", 1), "Head", {} },
    { "neck", G("INVSLOT_NECK", 2), "Neck", {} },
    { "shoulder", G("INVSLOT_SHOULDER", 3), "Shoulders", {} },
    { "back", G("INVSLOT_BACK", 15), "Back", {} },
    { "chest", G("INVSLOT_CHEST", 5), "Chest", {} },
    { "shirt", G("INVSLOT_BODY", 4), "Shirt", {} },
    { "tabard", G("INVSLOT_TABARD", 19), "Tabard", {} },
    { "wrist", G("INVSLOT_WRIST", 9), "Wrists", {} },
    { "hands", G("INVSLOT_HAND", 10), "Hands", {} },
    { "waist", G("INVSLOT_WAIST", 6), "Waist", {} },
    { "legs", G("INVSLOT_LEGS", 7), "Legs", {} },
    { "feet", G("INVSLOT_FEET", 8), "Feet", {} },
    { "finger1", G("INVSLOT_FINGER1", 11), "First ring", {} },
    { "finger2", G("INVSLOT_FINGER2", 12), "Second ring", {} },
    { "trinket1", G("INVSLOT_TRINKET1", 13), "First trinket", {} },
    { "trinket2", G("INVSLOT_TRINKET2", 14), "Second trinket", {} },
    { "any", nil, "Any equipment slot", {} },
}
local SLOT = {}
C.EQUIPPED_SLOTS = {}   -- every slot number, for "any"
for _, s in ipairs(C.SLOTS) do
    SLOT[s[1]] = s
    if s[2] then C.EQUIPPED_SLOTS[#C.EQUIPPED_SLOTS + 1] = s[2] end
end
function C.Slot(key) return SLOT[key] end
function C.Category(key) return CATEGORY[key] end

-- What a slot can be compared with: { { what, label }, ... } (the editor's third choice).
function C.SlotChoices(key)
    local s = SLOT[key]
    if not s then return {} end
    local out = {}
    if s[2] then out[#out + 1] = { "empty", "Empty" } end
    for _, cat in ipairs(s[4]) do out[#out + 1] = { cat, CATEGORY[cat][2] } end
    out[#out + 1] = { "item", "A specific item" }
    return out
end

local function Allowed(slot, what)
    for _, c in ipairs(C.SlotChoices(slot)) do if c[1] == what then return true end end
    return false
end

-- The first category the facts fit, in the order above (a fishing pole is also two-handed and a weapon).
local function Describe(f)
    if f.label then return f.label end
    if f.classID == nil then return "An item the game has no details for yet" end
    for _, c in ipairs(C.CATEGORIES) do
        if c[3](f) then return c[2] end
    end
    return "Other equipment"
end

local function SlotFacts(obs, n) return obs and obs.slots and obs.slots[n] end

C.Register({
    type = "equipment", label = "Equipment",
    New = function() return { type = "equipment", slot = "offHand", what = "empty", negate = false } end,

    Check = function(raw)
        if not SLOT[raw.slot] then return nil, "it names an equipment slot this version of TwichUI doesn't know." end
        if not Allowed(raw.slot, raw.what) then return nil, "it compares the slot with something it can't be compared with." end
        local clean = { type = "equipment", slot = raw.slot, what = raw.what, negate = raw.negate == true }
        if raw.what == "item" then
            if R.Reminders.ValidItem(raw.item) then
                clean.item = raw.item
            else
                return clean, "choose the item it looks for (its ID or link)."
            end
        end
        return clean
    end,

    Needs = function(cond, add)
        local s = SLOT[cond.slot]
        if s and s[2] then
            add("slot:" .. s[2])
        elseif s then
            for _, n in ipairs(C.EQUIPPED_SLOTS) do add("slot:" .. n) end
        end
    end,

    Evaluate = function(cond, obs)
        local s = SLOT[cond.slot]
        if cond.what == "item" and not s[2] then
            local unknown = false
            for _, n in ipairs(C.EQUIPPED_SLOTS) do
                local f = SlotFacts(obs, n)
                if f == nil then unknown = true
                elseif f.id == cond.item then return Negate(MATCH, cond.negate) end
            end
            if unknown then return UNKNOWN, "The game hasn't said what is equipped yet." end
            return Negate(NOMATCH, cond.negate)
        end
        local f = SlotFacts(obs, s[2])
        if f == nil then return UNKNOWN, "The game hasn't said what is in this slot yet." end
        if cond.what == "empty" then return Negate(Yes(f.empty), cond.negate) end
        if cond.what == "item" then return Negate(Yes(not f.empty and f.id == cond.item), cond.negate) end
        if f.empty then return Negate(NOMATCH, cond.negate) end
        if f.classID == nil then return UNKNOWN, "The game hasn't given this item's details yet." end
        return Negate(Yes(CATEGORY[cond.what][3](f)), cond.negate)
    end,

    Summary = function(cond)
        local s = SLOT[cond.slot]
        local is = cond.negate and "is not" or "is"
        if cond.what == "item" and not s[2] then
            return ("%s %s equipped"):format(ItemWords(cond.item):gsub("^%l", string.upper), is)
        end
        local what
        if cond.what == "empty" then what = "empty"
        elseif cond.what == "item" then what = ItemWords(cond.item)
        else what = CATEGORY[cond.what][2] end
        return ("%s %s %s"):format(s[3], is, what)
    end,

    Observed = function(cond, obs)
        local s = SLOT[cond.slot]
        if not s[2] then
            local unknown = false
            for _, x in ipairs(C.SLOTS) do
                local f = x[2] and SlotFacts(obs, x[2])
                if x[2] and f == nil then unknown = true
                elseif f and f.id == cond.item then return ("Equipped (%s)"):format(x[3]) end
            end
            return unknown and "Not read yet" or "Not equipped"
        end
        local f = SlotFacts(obs, s[2])
        if f == nil then return "Not read yet" end
        if f.empty then return "Empty" end
        local words = Describe(f)
        if f.id and f.id > 0 then words = ("%s (%s)"):format(words, ItemWords(f.id)) end
        return words
    end,

    -- The situations worth trying for this condition: what it looks for, something else, nothing, and no details.
    Scenarios = function(cond)
        local s = SLOT[cond.slot]
        local list = {}
        local function Put(key, label, facts)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                obs.slots = obs.slots or {}
                if s[2] then
                    obs.slots[s[2]] = facts
                else
                    -- any slot: every slot empty (or all unread), and what it looks for in the first one
                    for _, n in ipairs(C.EQUIPPED_SLOTS) do
                        if facts == nil then obs.slots[n] = nil else obs.slots[n] = { empty = true } end
                    end
                    if facts and not facts.empty then obs.slots[C.EQUIPPED_SLOTS[1]] = facts end
                end
            end }
        end
        local slotWords = s[2] and s[3]:lower() or "equipment"
        if cond.what == "item" then
            local item = cond.item or 0
            Put("item", ("%s equipped"):format(ItemWords(cond.item):gsub("^%l", string.upper)), { id = item, classID = ARMOR, subClassID = 0, label = "The item it looks for" })
            Put("other", "Something else equipped", { id = 0, classID = ARMOR, subClassID = 0, label = "Another item" })
            Put("empty", s[2] and ("Empty %s"):format(slotWords) or "Nothing equipped", { empty = true })
            Put("unread", "Equipment not read yet", nil)
        elseif cond.what == "empty" then
            Put("empty", ("Empty %s"):format(slotWords), { empty = true })
            Put("item", "Something equipped", { id = 0, classID = ARMOR, subClassID = 0, label = "An item" })
            Put("unread", "Equipment not read yet", nil)
        else
            local cat = CATEGORY[cond.what]
            local sample, other = {}, {}
            for k, v in pairs(cat[4]) do sample[k] = v end
            for k, v in pairs(OTHER[cond.what]) do other[k] = v end
            sample.id, other.id = 0, 0
            Put("match", ("%s equipped"):format(cat[2]), sample)
            Put("empty", ("Empty %s"):format(slotWords), { empty = true })
            Put("other", ("%s equipped"):format(other.label:gsub("^An? ", ""):gsub("^%l", string.upper)), other)
            Put("unknown", "Equipment information unavailable", { id = 0, label = "An item the game has no details for yet" })
        end
        return list
    end,
})

---------------------------------------------------------------------------
-- The player: combat, alive or dead, mounted
---------------------------------------------------------------------------
-- key (stored), what it reads, "is" words, "is not" words, whether this client reports it
C.STATES = {
    { "combat", "combat", "in combat", "not in combat" },
    { "dead", "life", "dead or a ghost", "alive" },
    { "ghost", "life", "a ghost", "not a ghost" },
    { "mounted", "mounted", "mounted", "not mounted", function() return rawget(_G, "IsMounted") ~= nil end },
}
local STATE = {}
for _, s in ipairs(C.STATES) do STATE[s[1]] = s end
function C.State(key) return STATE[key] end
function C.StateSupported(key)
    local s = STATE[key]
    return s ~= nil and (s[5] == nil or s[5]())
end

-- Dead includes a ghost: after releasing your spirit you are still dead until you are back in your body. "A ghost"
-- is only the released spirit.
local function Life(cond, life)
    if cond.state == "dead" then return life ~= "alive" end
    return life == "ghost"
end

C.Register({
    type = "player", label = "You (combat, alive, mounted)",
    New = function() return { type = "player", state = "combat", negate = false } end,

    Check = function(raw)
        if not STATE[raw.state] then return nil, "it looks at something about you this version of TwichUI doesn't know." end
        local clean = { type = "player", state = raw.state, negate = raw.negate == true }
        if not C.StateSupported(raw.state) then return clean, "this game client doesn't report whether you are mounted." end
        return clean
    end,

    Needs = function(cond, add) add(STATE[cond.state][2]) end,

    -- combat, being dead, being a ghost and being mounted are each one fact about the player
    Subject = function(cond)
        local key = STATE[cond.state][2]
        return key, ({ combat = "Combat", life = "Alive or dead", mounted = "Mounted" })[key]
    end,

    Evaluate = function(cond, obs)
        local s = STATE[cond.state]
        local v = obs and obs[s[2]]
        if v == nil then return UNKNOWN, "The game hasn't said yet." end
        if s[2] == "life" then return Negate(Yes(Life(cond, v)), cond.negate) end
        return Negate(Yes(v == true), cond.negate)
    end,

    Summary = function(cond)
        local s = STATE[cond.state]
        return "Player is " .. (cond.negate and s[4] or s[3])
    end,

    Observed = function(cond, obs)
        local s = STATE[cond.state]
        local v = obs and obs[s[2]]
        if v == nil then return "Not read yet" end
        if s[2] == "combat" then return v and "In combat" or "Out of combat" end
        if s[2] == "mounted" then return v and "Mounted" or "Not mounted" end
        return ({ alive = "Alive", dead = "Dead", ghost = "A ghost" })[v] or "Not read yet"
    end,

    Scenarios = function(cond)
        local s = STATE[cond.state]
        local list = {}
        local function Put(key, label, value)
            list[#list + 1] = { key = key, label = label, Apply = function(obs) obs[s[2]] = value end }
        end
        if s[2] == "combat" then
            Put("on", "In combat", true)
            Put("off", "Out of combat", false)
        elseif s[2] == "life" then
            Put("alive", "Alive", "alive")
            Put("dead", "Dead", "dead")
            Put("ghost", "A ghost (spirit released)", "ghost")
        else
            Put("on", "Mounted", true)
            Put("off", "Not mounted", false)
        end
        Put("unread", "Not read yet", nil)
        return list
    end,
})

---------------------------------------------------------------------------
-- The player's class: a condition like any other. Who a reminder is *for* (RM.SetScope's class) is a separate setting:
-- that decides whether the reminder runs at all, this decides whether it matches. Class tokens are the game's own
-- (UnitClassBase's classFilename, "WARRIOR"), never a translated name.
---------------------------------------------------------------------------
-- { { token, label }, ... } of the classes this client has, in the game's own order when it gives one
-- (CLASS_SORT_ORDER, Blizzard_FrameXMLBase/Camelot/Constants.lua) and the order TwichUI lists them in otherwise.
function C.ClassChoices()
    local RM = R.Reminders
    local out, have = {}, {}
    local order = rawget(_G, "CLASS_SORT_ORDER")
    if type(order) == "table" then
        for _, token in ipairs(order) do
            if RM.ValidClass(token) and not have[token] then
                have[token] = true
                out[#out + 1] = { token, RM.ClassName(token) }
            end
        end
    end
    if #out == 0 then
        for _, token in ipairs(RM.CLASSES) do out[#out + 1] = { token, RM.ClassName(token) } end
    end
    return out
end

-- "A", "A or B", "A, B or C"
local function OrList(names)
    if #names <= 1 then return names[1] or "" end
    return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
end

C.Register({
    type = "class", label = "Player class",
    New = function() return { type = "class", negate = false } end,

    Check = function(raw)
        local clean = { type = "class", negate = raw.negate == true }
        if raw.class == nil then return clean, "choose the class it looks for." end
        if not R.Reminders.ValidClass(raw.class) then return nil, "it names a class this version of TwichUI doesn't know." end
        clean.class = raw.class
        return clean
    end,

    Needs = function(_, add) add("class") end,

    Evaluate = function(cond, obs)
        local v = obs and obs.class
        if v == nil then return UNKNOWN, "The game hasn't said which class you are yet." end
        return Negate(Yes(v == cond.class), cond.negate)
    end,

    Summary = function(cond)
        local name = cond.class and R.Reminders.ClassName(cond.class) or "(none chosen)"
        return ("Player class %s %s"):format(cond.negate and "is not" or "is", name)
    end,

    Observed = function(_, obs)
        local v = obs and obs.class
        if v == nil then return "Not read yet" end
        return R.Reminders.ClassName(v)
    end,

    Subject = function() return "class", "Player class" end,

    -- Every class this client has, the one the condition names first; a simulation sets the one class the character is.
    Scenarios = function(cond)
        local list = {}
        local function Put(key, label)
            list[#list + 1] = { key = key, label = label, Apply = function(obs) obs.class = key end }
        end
        local RM = R.Reminders
        if RM.ValidClass(cond.class) then Put(cond.class, RM.ClassName(cond.class)) end
        for _, ch in ipairs(C.ClassChoices()) do
            if ch[1] ~= cond.class then Put(ch[1], ch[2]) end
        end
        list[#list + 1] = { key = "unread", label = "Class not read yet", Apply = function(obs) obs.class = nil end }
        return list
    end,

    -- (Warrior or Hunter) in a group matching any, none of (Warrior, Hunter) in a group matching all: said once.
    Merge = function(match, conds)
        local negated = match == "all"
        local names, used, seen = {}, {}, {}
        for i, cond in ipairs(conds) do
            if cond.class and (cond.negate == true) == negated then
                used[#used + 1] = i
                if not seen[cond.class] then
                    seen[cond.class] = true
                    names[#names + 1] = R.Reminders.ClassName(cond.class)
                end
            end
        end
        if #used < 2 then return nil end
        if negated then return "Player class is none of " .. OrList(names), used end
        return "Player class is " .. OrList(names), used
    end,
})
