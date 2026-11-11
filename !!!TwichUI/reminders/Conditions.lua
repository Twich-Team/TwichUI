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
--   Supported()           -> false when this client lacks what it reads; `unsupported` then says so (C.Check reports it)
--   NextChange(cond, obs) -> seconds from obs.now until its answer can change with time alone (a buff running down
--                            past a threshold, a cooldown ending), or nil. The controller looks again then, so no
--                            condition needs a timer of its own and nothing is polled. obs.now is the GetTime of the
--                            decision; a time-based answer without it is unknown.
-- Adding a kind: register it here (or in a file of its own loaded after this one), give State.lua a source for each
-- observation key it names, and give the editor (TwichUI_Settings/pages/RemindersEditor.lua) its fields.
--
-- What the game provides (read from the Forever UI source; docs/reminders.md has the references):
--   * equipment slots INVSLOT_HEAD (1) .. INVSLOT_TABARD (19) (Blizzard_FrameXMLBase/Constants.lua);
--   * an item's class, subclass and equip location from C_Item.GetItemInfoInstant, without waiting for the item cache:
--     a shield is Enum.ItemClass.Armor (4) with Enum.ItemArmorSubclass.Shield (6); a weapon is Enum.ItemClass.Weapon (2),
--     a fishing pole its subclass Fishingpole (20) (ItemConstantsDocumentation.lua); two-handed and held-in-off-hand are
--     the equip locations INVTYPE_2HWEAPON and INVTYPE_HOLDABLE (the game's own DressUpModelFrameMixin reads them);
--   * whether a weapon has a temporary enchant (oil, stone, poison): C_Item.GetWeaponEnchantInfo(Enum.WeaponSlot) and the
--     events WEAPON_ENCHANT_CHANGED / WEAPON_SLOT_CHANGED (ItemDocumentation.lua, PaperDollInfoDocumentation.lua; the
--     game's own BuffFrame.lua reads them the same way);
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
    -- a kind this client can't report is kept, and said so (a reminder using it can't be turned on here)
    if not problem and p.Supported and not p.Supported() then problem = p.unsupported or "this game client doesn't report it." end
    return clean, problem, p
end

local function Negate(result, negate)
    if not negate or result == UNKNOWN then return result end
    return result == MATCH and NOMATCH or MATCH
end
C.Negate = Negate

local function Yes(v) return v and MATCH or NOMATCH end
C.Yes = Yes

---------------------------------------------------------------------------
-- Amounts: a whole number compared with a threshold, said the same way by every kind that has one. "below" is strictly
-- less than; "atLeast" is greater than or equal to, so the two never both hold and never both fail for a known value
-- (exactly 30 is "at least 30", never "below 30").
---------------------------------------------------------------------------
C.COMPARE = { { "below", "Below" }, { "atLeast", "At least" } }
local COMPARE = { below = true, atLeast = true }
function C.ValidCompare(v) return COMPARE[v] == true end
function C.Compare(value, compare, n)
    if compare == "below" then return value < n end
    return value >= n
end
-- A whole number from lo to hi, or nil.
function C.Whole(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v % 1 ~= 0 or v < lo or v > hi then return nil end
    return v
end
-- A spell ID (the game's own number for a spell: a buff, an ability, a form), or nil.
function C.ValidSpell(v) return C.Whole(v, 1, 2147483647) ~= nil end
-- A spell's name when the game has it ready, nil otherwise (State.lua sets this to the game's lookup).
C.SpellName = function() return nil end
function C.SpellWords(id)
    if not id then return "a spell" end
    local name = C.SpellName(id)
    if type(name) == "string" and name ~= "" then return name end
    return ("spell %d"):format(id)
end
-- "45 seconds", "2 minutes", "1 minute 30 seconds"
function C.Duration(seconds)
    if type(seconds) ~= "number" then return "?" end
    local m, s = math.floor(seconds / 60), seconds % 60
    local function Unit(n, one) return ("%d %s%s"):format(n, one, n == 1 and "" or "s") end
    if m == 0 then return Unit(s, "second") end
    if s == 0 then return Unit(m, "minute") end
    return Unit(m, "minute") .. " " .. Unit(s, "second")
end

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
-- Temporary weapon enchants: a weapon oil, a sharpening stone, a poison, a shaman's imbue. The game's own buff frame
-- lists these as "temporary enchantments" (Blizzard_BuffFrame/BuffFrame.lua, C_Item.GetWeaponEnchantInfo); all that the
-- client tells an addon is whether a hand has one, not which, so this condition cannot tell one oil from another.
-- The observation obs.enchant = { mainHand = state, offHand = state }, each state one of
--   "enchanted"  a weapon with a temporary enchant on it
--   "bare"       a weapon with none
--   "noWeapon"   nothing there that can take one (an empty hand, a shield, a held item, a fishing pole)
--   nil          the game hasn't said
-- and obs.enchant.ends[hand] = the GetTime its enchant runs out (nil: not said). "expiring" asks for an enchant with less
-- than `seconds` left: an enchanted hand whose end isn't known is unknown, a bare or empty hand never matches (that is
-- "missing", or nothing to enchant), and exactly `seconds` left is not yet "less than". Charges are not read (see State.lua).
-- State.lua reads it; a simulation hands the same shape in.
---------------------------------------------------------------------------
C.ENCHANT_SECONDS = { 30, 60, 120, 300, 600, 900 }   -- the editor's quick choices; any whole number of seconds is kept
C.ENCHANT_SECONDS_MAX = 7200
C.ENCHANT_SECONDS_DEFAULT = 300
C.ENCHANT_HANDS = {
    { "mainHand", "Main hand" },
    { "offHand", "Off hand" },
}
local ENCHANT_HAND = {}
for _, h in ipairs(C.ENCHANT_HANDS) do ENCHANT_HAND[h[1]] = h end

-- key (stored), what the editor's value choice says, the words after "Main hand weapon", a tooltip
C.ENCHANT_CHOICES = {
    { "missing", "Has no temporary enchant", "has no temporary enchant",
        "A weapon is held in this hand and nothing like a weapon oil, sharpening stone or poison is on it. Never true for an empty hand, a shield or a fishing pole." },
    { "applied", "Has a temporary enchant", "has a temporary enchant",
        "A weapon in this hand has a temporary enchant on it." },
    { "expiring", "Has a temporary enchant running out", "has a temporary enchant with less than %s left",
        "A weapon in this hand has a temporary enchant with less than the time you choose left on it. A weapon with none is \"Has no temporary enchant\" instead: add both in a group where at least one must be true to be reminded either way." },
}
local ENCHANT_CHOICE = {}
for _, c in ipairs(C.ENCHANT_CHOICES) do ENCHANT_CHOICE[c[1]] = c end
function C.EnchantChoice(key) return ENCHANT_CHOICE[key] end
function C.EnchantHand(key) return ENCHANT_HAND[key] end

local function EnchantState(obs, hand)
    local e = obs and obs.enchant
    return type(e) == "table" and e[hand] or nil
end

-- Seconds left on a hand's enchant at obs.now, or nil when that isn't known.
local function EnchantLeft(obs, hand)
    local e = obs and obs.enchant
    local ends = type(e) == "table" and type(e.ends) == "table" and e.ends[hand] or nil
    if type(ends) ~= "number" or type(obs.now) ~= "number" then return nil end
    return ends - obs.now
end

-- The words after "Main hand weapon" for a stored condition.
function C.EnchantWords(cond)
    local c = ENCHANT_CHOICE[cond.what]
    if not c then return tostring(cond.what) end
    if cond.what == "expiring" then return c[3]:format(cond.seconds and C.Duration(cond.seconds) or "(a time not chosen yet)") end
    return c[3]
end

C.Register({
    type = "weaponEnchant", label = "Weapon enchant (oil, stone, poison)",
    New = function() return { type = "weaponEnchant", hand = "mainHand", what = "missing" } end,

    Check = function(raw)
        if not ENCHANT_HAND[raw.hand] then return nil, "it names a hand this version of TwichUI doesn't know." end
        if not ENCHANT_CHOICE[raw.what] then return nil, "it asks about a weapon enchant this version of TwichUI doesn't know." end
        local clean = { type = "weaponEnchant", hand = raw.hand, what = raw.what }
        if raw.what == "expiring" then
            clean.seconds = C.Whole(raw.seconds, 1, C.ENCHANT_SECONDS_MAX)
            if not clean.seconds then return clean, ("choose how little time left counts as running out (1 to %d seconds)."):format(C.ENCHANT_SECONDS_MAX) end
        end
        return clean
    end,

    Needs = function(_, add) add("enchant") end,

    Evaluate = function(cond, obs)
        local state = EnchantState(obs, cond.hand)
        if state == nil then return UNKNOWN, "The game hasn't said whether this weapon has a temporary enchant yet." end
        if cond.what == "missing" then return Yes(state == "bare") end
        if cond.what == "expiring" then
            if state ~= "enchanted" then return NOMATCH end
            local left = EnchantLeft(obs, cond.hand)
            if left == nil then return UNKNOWN, "The game hasn't said how long this weapon's enchant has left." end
            return Yes(left < cond.seconds)
        end
        return Yes(state == "enchanted")
    end,

    -- running out is only a matter of time: the moment it crosses the threshold, and the moment it ends (read again then)
    NextChange = function(cond, obs)
        if cond.what ~= "expiring" or EnchantState(obs, cond.hand) ~= "enchanted" then return nil end
        local left = EnchantLeft(obs, cond.hand)
        if not left or left <= 0 then return nil end
        if left >= cond.seconds then return left - cond.seconds end
        return left
    end,

    Summary = function(cond)
        local h = ENCHANT_HAND[cond.hand]
        return ("%s weapon %s"):format(h and h[2] or "Weapon", C.EnchantWords(cond))
    end,

    Observed = function(cond, obs)
        local state = EnchantState(obs, cond.hand)
        if state == "enchanted" then
            local left = EnchantLeft(obs, cond.hand)
            if left and left > 0 then return ("Has a temporary enchant (%s left)"):format(C.Duration(math.floor(left))) end
            return "Has a temporary enchant"
        end
        return ({
            bare = "No temporary enchant",
            noWeapon = "No weapon that can take one",
        })[state] or "Not read yet"
    end,

    -- the one it looks for first (the Test section starts on the first), the other, no weapon, and nothing read
    Scenarios = function(cond)
        local list = {}
        local function Put(key, label, state, left)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                obs.enchant = obs.enchant or {}
                obs.enchant.ends = obs.enchant.ends or {}
                obs.enchant[cond.hand] = state
                obs.enchant.ends[cond.hand] = left and (obs.now or 0) + left or nil
            end }
        end
        if cond.what == "expiring" then
            local seconds = cond.seconds or C.ENCHANT_SECONDS_DEFAULT
            local soon = math.max(1, math.floor(seconds / 2))
            Put("soon", ("An enchant with %s left"):format(C.Duration(soon)), "enchanted", soon)
            Put("plenty", ("An enchant with %s left"):format(C.Duration(seconds * 3)), "enchanted", seconds * 3)
            Put("noTime", "An enchant whose time isn't given", "enchanted", nil)
            Put("bare", "A weapon with no temporary enchant", "bare")
            Put("noWeapon", "No weapon that can take one", "noWeapon")
            Put("unread", "Not read yet", nil)
            return list
        end
        local bare = { "bare", "A weapon with no temporary enchant" }
        local on = { "enchanted", "A weapon with a temporary enchant" }
        local first, second = bare, on
        if cond.what == "applied" then first, second = on, bare end
        Put(first[1], first[2], first[1], first[1] == "enchanted" and 1800 or nil)
        Put(second[1], second[2], second[1], second[1] == "enchanted" and 1800 or nil)
        Put("noWeapon", "No weapon that can take one", "noWeapon")
        Put("unread", "Not read yet", nil)
        return list
    end,
})

---------------------------------------------------------------------------
-- The Well Fed buff: what good food gives you after you have eaten it. Every food has a buff spell of its own, so the
-- buff is told by its name, the one the client gives the Well Fed spell (C.WELL_FED_SPELL; State.lua asks the game),
-- or by that spell's ID. The observation obs.wellFed is true (a helpful aura on you is Well Fed), false (the game listed
-- your helpful auras and none is), or nil (it hasn't said, or the auras are hidden from addons, as in some fights).
-- State.lua reads it; a simulation hands the same shape in.
---------------------------------------------------------------------------
C.WELL_FED_SPELL, C.WELL_FED_NAME = 19705, "Well Fed"

-- Whether an aura (spell ID and name as the game gave them, either may be nil) is Well Fed. knownName is what the client
-- calls the Well Fed spell (nil: it doesn't say, the English name stands in). Pure.
function C.IsWellFed(spellId, name, knownName)
    if spellId == C.WELL_FED_SPELL then return true end
    if type(name) ~= "string" or name == "" then return false end
    local want = type(knownName) == "string" and knownName ~= "" and knownName or C.WELL_FED_NAME
    return name:lower() == want:lower()
end

-- key (stored), what the editor's value choice says, the words after "You", a tooltip
C.WELLFED_CHOICES = {
    { "missing", "Is not Well Fed", "are not Well Fed",
        "You have no Well Fed buff: you have not eaten food that gives one, or it has run out." },
    { "applied", "Is Well Fed", "are Well Fed",
        "You have a Well Fed buff." },
}
local WELLFED_CHOICE = {}
for _, c in ipairs(C.WELLFED_CHOICES) do WELLFED_CHOICE[c[1]] = c end
function C.WellFedChoice(key) return WELLFED_CHOICE[key] end

C.Register({
    type = "wellFed", label = "Well Fed buff",
    New = function() return { type = "wellFed", what = "missing" } end,

    Check = function(raw)
        if not WELLFED_CHOICE[raw.what] then return nil, "it asks about the Well Fed buff in a way this version of TwichUI doesn't know." end
        return { type = "wellFed", what = raw.what }
    end,

    Needs = function(_, add) add("wellFed") end,

    Evaluate = function(cond, obs)
        local v = obs and obs.wellFed
        if v == nil then return UNKNOWN, "The game hasn't said whether you have the Well Fed buff yet, or your buffs can't be read right now." end
        if cond.what == "missing" then return Yes(v == false) end
        return Yes(v == true)
    end,

    Summary = function(cond)
        local c = WELLFED_CHOICE[cond.what]
        return ("You %s"):format(c and c[3] or tostring(cond.what))
    end,

    Observed = function(_, obs)
        local v = obs and obs.wellFed
        if v == nil then return "Not read yet" end
        return v and "Well Fed" or "Not Well Fed"
    end,

    -- the one it looks for first (the Test section starts on the first), the other, and nothing read
    Scenarios = function(cond)
        local list = {}
        local function Put(key, label, value)
            list[#list + 1] = { key = key, label = label, Apply = function(obs) obs.wellFed = value end }
        end
        local fed, hungry = { "fed", "Well Fed", true }, { "hungry", "Not Well Fed", false }
        local first, second = hungry, fed
        if cond.what == "applied" then first, second = fed, hungry end
        Put(first[1], first[2], first[3])
        Put(second[1], second[2], second[3])
        Put("unread", "Not read yet", nil)
        return list
    end,
})

---------------------------------------------------------------------------
-- The player: combat, alive or dead, mounted, resting, in a dungeon or a raid
---------------------------------------------------------------------------
-- key (stored), what it reads, "is" words, "is not" words, whether this client reports it
-- Resting is the game's own IsResting (an inn or a capital city). Dungeon and raid read the kind of place from
-- IsInInstance (WoW: Forever UI source, InstanceDocumentation.lua): "party" is a dungeon, "raid" a raid; a battleground,
-- an arena or a scenario is neither. obs.place is "none" | "dungeon" | "raid" | "other".
C.STATES = {
    { "combat", "combat", "in combat", "not in combat" },
    { "dead", "life", "dead or a ghost", "alive" },
    { "ghost", "life", "a ghost", "not a ghost" },
    { "mounted", "mounted", "mounted", "not mounted", function() return rawget(_G, "IsMounted") ~= nil end },
    { "resting", "resting", "resting", "not resting", function() return rawget(_G, "IsResting") ~= nil end },
    { "dungeon", "place", "in a dungeon", "not in a dungeon", function() return rawget(_G, "IsInInstance") ~= nil end },
    { "raid", "place", "in a raid", "not in a raid", function() return rawget(_G, "IsInInstance") ~= nil end },
    -- Moving is the game's own IsPlayerMoving and its start / stop events (the fader that hides frames while you move
    -- reads the same); it turns on and off with every step, so it suits "only while standing still" with a short wait
    -- before showing. On a flight path is UnitOnTaxi (the guide's auto hide reads it the same way).
    { "moving", "moving", "moving", "standing still", function() return rawget(_G, "IsPlayerMoving") ~= nil end },
    { "taxi", "taxi", "on a flight path", "not on a flight path", function() return rawget(_G, "UnitOnTaxi") ~= nil end },
}
-- the kind of place each place-state is
local PLACE_OF = { dungeon = "dungeon", raid = "raid" }
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
    type = "player", label = "You (combat, alive, mounted, resting, dungeon, raid, moving, flight path)",
    New = function() return { type = "player", state = "combat", negate = false } end,

    Check = function(raw)
        if not STATE[raw.state] then return nil, "it looks at something about you this version of TwichUI doesn't know." end
        local clean = { type = "player", state = raw.state, negate = raw.negate == true }
        if not C.StateSupported(raw.state) then return clean, ("this game client doesn't report whether you are %s."):format(STATE[raw.state][3]) end
        return clean
    end,

    Needs = function(cond, add) add(STATE[cond.state][2]) end,

    -- combat, being dead, being a ghost, being mounted, resting and where you are (dungeon, raid) are each one fact about the player
    Subject = function(cond)
        local key = STATE[cond.state][2]
        return key, ({ combat = "Combat", life = "Alive or dead", mounted = "Mounted", resting = "Resting", place = "Dungeon or raid",
            moving = "Moving", taxi = "On a flight path" })[key]
    end,

    Evaluate = function(cond, obs)
        local s = STATE[cond.state]
        local v = obs and obs[s[2]]
        if v == nil then return UNKNOWN, "The game hasn't said yet." end
        if s[2] == "life" then return Negate(Yes(Life(cond, v)), cond.negate) end
        if s[2] == "place" then return Negate(Yes(v == PLACE_OF[cond.state]), cond.negate) end
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
        if s[2] == "resting" then return v and "Resting" or "Not resting" end
        if s[2] == "moving" then return v and "Moving" or "Standing still" end
        if s[2] == "taxi" then return v and "On a flight path" or "Not on a flight path" end
        if s[2] == "place" then return ({ dungeon = "In a dungeon", raid = "In a raid", other = "Somewhere else", none = "Not in an instance" })[v] or "Not read yet" end
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
        elseif s[2] == "resting" then
            Put("on", "Resting", true)
            Put("off", "Not resting", false)
        elseif s[2] == "moving" then
            Put("on", "Moving", true)
            Put("off", "Standing still", false)
        elseif s[2] == "taxi" then
            Put("on", "On a flight path", true)
            Put("off", "Not on a flight path", false)
        elseif s[2] == "place" then
            -- the same choices whichever of dungeon / raid the condition names (they share one input)
            Put("dungeon", "In a dungeon", "dungeon")
            Put("raid", "In a raid", "raid")
            Put("none", "Not in an instance", "none")
            Put("other", "In a battleground, arena or scenario", "other")
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

---------------------------------------------------------------------------
-- Talent specialization. Forever has no chosen specialization: it is the talent tree with the most points spent (the
-- same reading the upgrade hints use, gear/Data.lua). Trees are identified by class token + skillLine (gear/Weights.lua's
-- W.CLASSES, the same ids the game's talent frame reports), never by a translated name. The observation obs.talent is
-- "<CLASS>:<skillLine>" for a unique leader, "tied" for equal highest positive totals, "none" when nothing is spent, and
-- nil when the game hasn't said. Unspent points never count: only points spent in a tree are read.
---------------------------------------------------------------------------
C.TALENT_TIED, C.TALENT_NONE = "tied", "none"
local TALENT_STATES = {
    tied = "Tied talent trees",
    none = "No talent points spent",
}

local function TalentTrees(class)
    local W = R.GearWeights
    local info = type(class) == "string" and W and W.CLASSES[class]
    return info and info.trees or nil
end

-- The tree of a class by skillLine: { skillLine, name, ... } or nil.
function C.TalentTree(class, skillLine)
    for _, tree in ipairs(TalentTrees(class) or {}) do
        if tree.skillLine == skillLine then return tree end
    end
    return nil
end

function C.TalentKey(class, skillLine) return ("%s:%d"):format(class, skillLine) end

-- The key of the choice a stored condition makes ("SHAMAN:374", "tied", "none"), nil when it has made none.
function C.TalentValueKey(cond)
    if cond.state then return cond.state end
    if cond.class and cond.tree then return C.TalentKey(cond.class, cond.tree) end
    return nil
end

-- Words for a key: "Restoration (Shaman)", "Tied talent trees".
function C.TalentWords(key)
    if TALENT_STATES[key] then return TALENT_STATES[key] end
    local class, line = tostring(key):match("^(%u+):(%d+)$")
    local tree = class and C.TalentTree(class, tonumber(line))
    if not tree then return nil end
    return ("%s (%s)"):format(tree.name, R.Reminders.ClassName(class))
end

-- { { key, label }, ... }: the two states, then every tree of every class this client has (the class order of Player class).
function C.TalentChoices()
    local out = { { "tied", TALENT_STATES.tied }, { "none", TALENT_STATES.none } }
    for _, ch in ipairs(C.ClassChoices()) do
        for _, tree in ipairs(TalentTrees(ch[1]) or {}) do
            out[#out + 1] = { C.TalentKey(ch[1], tree.skillLine), C.TalentWords(C.TalentKey(ch[1], tree.skillLine)) }
        end
    end
    return out
end

-- What the points say. spent = { { skillLine, points }, ... } for the class's trees (State.lua reads them from the game);
-- anything that isn't a clean list of numbers is unknown, never "no points".
function C.TalentLeader(class, spent)
    if type(class) ~= "string" or type(spent) ~= "table" or #spent == 0 then return nil end
    local best, bestLine, ties = 0, nil, 0
    for _, row in ipairs(spent) do
        local line, points = row[1], row[2]
        if type(line) ~= "number" or type(points) ~= "number" or points ~= points or points < 0 then return nil end
        if points > best then best, bestLine, ties = points, line, 1
        elseif points == best and points > 0 then ties = ties + 1 end
    end
    if best <= 0 then return "none" end
    if ties > 1 then return "tied" end
    return C.TalentKey(class, bestLine)
end

C.Register({
    type = "talent", label = "Talent specialization",

    -- A new one names the current player's class (its first tree); nothing else is ever changed by who edits it later.
    New = function()
        local class = rawget(_G, "UnitClassBase") and UnitClassBase("player")
        if type(class) == "string" and issecretvalue and issecretvalue(class) then class = nil end
        local trees = TalentTrees(class)
        local cond = { type = "talent", negate = false }
        if trees and trees[1] then cond.class, cond.tree = class, trees[1].skillLine end
        return cond
    end,

    Check = function(raw)
        local clean = { type = "talent", negate = raw.negate == true }
        if raw.state ~= nil then
            if not TALENT_STATES[raw.state] or raw.class ~= nil or raw.tree ~= nil then
                return nil, "it names a talent state this version of TwichUI doesn't know."
            end
            clean.state = raw.state
            return clean
        end
        if raw.class == nil and raw.tree == nil then return clean, "choose the talent specialization it looks for." end
        if not C.TalentTree(raw.class, raw.tree) then return nil, "it names a talent tree this version of TwichUI doesn't know." end
        clean.class, clean.tree = raw.class, raw.tree
        return clean
    end,

    Needs = function(_, add) add("talent") end,

    Evaluate = function(cond, obs)
        local v = obs and obs.talent
        if v == nil then return UNKNOWN, "The game hasn't said where your talent points are yet." end
        return Negate(Yes(v == C.TalentValueKey(cond)), cond.negate)
    end,

    Summary = function(cond)
        local words = C.TalentValueKey(cond) and C.TalentWords(C.TalentValueKey(cond)) or "(none chosen)"
        return ("Talent specialization %s %s"):format(cond.negate and "is not" or "is", words)
    end,

    Observed = function(_, obs)
        local v = obs and obs.talent
        if v == nil then return "Not read yet" end
        return C.TalentWords(v) or "Unknown"
    end,

    Subject = function() return "talent", "Talent specialization" end,

    Scenarios = function()
        local list = {}
        for _, ch in ipairs(C.TalentChoices()) do
            local key = ch[1]
            list[#list + 1] = { key = key, label = ch[2], Apply = function(obs) obs.talent = key end }
        end
        list[#list + 1] = { key = "unread", label = "Talents not read yet", Apply = function(obs) obs.talent = nil end }
        return list
    end,
})
