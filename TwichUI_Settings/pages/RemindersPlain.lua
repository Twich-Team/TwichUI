-- TwichUI settings: Reminders, a rule in plain words
-- Everything the condition designer (RemindersDesigner.lua) says about a rule, made from the same tree the evaluator
-- reads (reminders/Config.lua's views, reminders/Evaluate.lua's decision) and from nothing else: a condition as a sentence,
-- what the "Add a condition" picker offers, the fields an editor needs for a condition, the rule as short lines, who it is
-- for, and why a rule would or would not show right now. Pure: no frames, no game calls but the reminders' own readers, and
-- the same words every time for the same rule. It decides nothing (the evaluator does) and writes nothing.
--
--   Pl.Words(match)                  "All of these must be true" / "At least one of these must be true", and short forms
--   Pl.Sentence(entry)               a condition as a sentence ("You are in combat"); an unreadable one says so
--   Pl.Capability(entry)             short, long: what this client can't report for it (nil when it can)
--   Pl.Entries()                     what the picker offers, from the registered kinds: { key, category, name, blurb, icon, note, make }
--   Pl.Subjects/SubjectOf/ValueChoices/ValueLabel/With*   the editor's fields and how a field changes a condition
--   Pl.SummaryLines(view)            the rule as { { text, depth, bullet }, ... }
--   Pl.Targeting(view, me)           who it is for
--   Pl.Explain(view, out, status, me)   why the rule would or would not show now, per condition and group

local R = TwichUI
local Pl = {}
R.RemindersPlain = Pl

local function C() return R.ReminderConditions end
local function E() return R.ReminderEval end
local function RM() return R.Reminders end

local function Upper1(s) return (tostring(s):gsub("^%l", string.upper)) end

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
local WORDS = {
    all = { heading = "All of these must be true", short = "All", technical = "All of these (AND)",
        tip = "Every item in this group has to be true for the group to count as true." },
    any = { heading = "At least one of these must be true", short = "Any", technical = "Any of these (OR)",
        tip = "One true item is enough for the group to count as true." },
}
function Pl.Words(match) return WORDS[match == "any" and "any" or "all"] end

---------------------------------------------------------------------------
-- A condition as a sentence
---------------------------------------------------------------------------
-- slots read as plural ("Your shoulders are")
local PLURAL = { shoulder = true, wrist = true, hands = true, legs = true, feet = true }
local WHAT = {
    empty = "empty", shield = "a shield", fishingPole = "a fishing pole", twoHand = "a two-handed weapon",
    weapon = "a weapon", holdable = "an item held in the off hand",
}

local function EquipmentSentence(cond)
    local CT = C()
    local s = CT.Slot(cond.slot)
    if not s then return nil end
    if cond.what == "item" and not s[2] then
        local name = CT.ItemWords(cond.item)
        return cond.negate and ("You don't have %s equipped"):format(name) or ("You have %s equipped"):format(name)
    end
    local what = cond.what == "item" and CT.ItemWords(cond.item) or WHAT[cond.what] or tostring(cond.what)
    local are = PLURAL[cond.slot] and (cond.negate and "are not" or "are") or (cond.negate and "is not" or "is")
    return ("Your %s %s %s"):format(s[3]:lower(), are, what)
end

local KIND = {}
local FIELDS = {}   -- the editor's fields of the kinds added with the condition library (below)

KIND.equipment = { sentence = EquipmentSentence }

KIND.player = {
    sentence = function(cond)
        local s = C().State(cond.state)
        if not s then return nil end
        return "You are " .. (cond.negate and s[4] or s[3])
    end,
}

KIND.class = {
    sentence = function(cond)
        local name = cond.class and RM().ClassName(cond.class)
        if not name then return "Your class (none chosen yet)" end
        return ("Your class %s %s"):format(cond.negate and "is not" or "is", name)
    end,
}

KIND.talent = {
    sentence = function(cond)
        local key = C().TalentValueKey(cond)
        local words = key and C().TalentWords(key)
        if not words then return "Talent specialization (none chosen yet)" end
        return ("Talent specialization %s %s"):format(cond.negate and "is not" or "is", words)
    end,
}

KIND.ammunition = {
    sentence = function(cond)
        local A = R.ReminderAmmo
        local c = A and A.Choice(cond.what)
        if not c then return nil end
        return "Ranged ammunition " .. (cond.what == "problem" and "needs attention" or c[3])
    end,
}

KIND.weaponEnchant = {
    sentence = function(cond)
        local CT = C()
        local h, c = CT.EnchantHand(cond.hand), CT.EnchantChoice(cond.what)
        if not (h and c) then return nil end
        if cond.what == "expiring" then
            return ("Your %s weapon enchant has less than %s left"):format(h[2]:lower(), cond.seconds and CT.Duration(cond.seconds) or "the time you choose")
        end
        return ("Your %s weapon %s"):format(h[2]:lower(), c[3])
    end,
}

local function AU() return R.ReminderAuras end
local function SU() return R.ReminderSupplies end
local function CH() return R.ReminderCharacter end
local function CX() return R.ReminderContext end
local function Fewer(compare) return compare == "below" and "fewer than" or "at least" end

KIND.aura = {
    sentence = function(cond)
        local names = AU().Names(cond.spells)
        local what = cond.harmful and "debuff" or "buff"
        if not names then return ("A %s on you (none chosen yet)"):format(what) end
        local w = cond.what
        if w == "present" then return cond.harmful and ("You are affected by " .. names) or ("You have " .. names) end
        if w == "missing" then return cond.harmful and ("You are not affected by " .. names) or ("You are missing " .. names) end
        if w == "expiring" then
            return ("%s %s less than %s left"):format(cond.harmful and names or ("Your " .. names), cond.harmful and "on you has" or "has",
                cond.seconds and C().Duration(cond.seconds) or "the time you choose")
        end
        return ("%s has %s %s stacks on you"):format(names, Fewer(cond.compare), tostring(cond.stacks or "?"))
    end,
}

KIND.itemCount = {
    sentence = function(cond)
        if not cond.item then return ("You carry %s %d of an item (none chosen yet)"):format(Fewer(cond.compare), cond.count or 0) end
        return ("You carry %s %d %s"):format(Fewer(cond.compare), cond.count or 0, C().ItemWords(cond.item))
    end,
}

KIND.bagSpace = {
    sentence = function(cond)
        if cond.compare == "below" and cond.count == 1 then return "Your bags are full" end
        return ("You have %s %d free bag slot%s"):format(Fewer(cond.compare), cond.count or 0, cond.count == 1 and "" or "s")
    end,
}

KIND.power = {
    sentence = function(cond)
        local p = CH().Power(cond.power)
        if not p then return nil end
        return ("Your %s is %s %d%%"):format(p[3]:lower(), cond.compare == "below" and "below" or "at least", cond.percent or 0)
    end,
}

KIND.spellKnown = {
    sentence = function(cond)
        if not cond.spell then return "A spell you know (none chosen yet)" end
        return ("You %s %s"):format(cond.negate and "don't know" or "know", C().SpellWords(cond.spell))
    end,
}

KIND.cooldown = {
    sentence = function(cond)
        if not cond.spell then return "A spell's cooldown (none chosen yet)" end
        return C().Get("cooldown").Summary(cond)
    end,
}

KIND.level = { sentence = function(cond) return C().Get("level").Summary(cond) end }
KIND.durability = { sentence = function(cond) return C().Get("durability").Summary(cond) end }
KIND.form = { sentence = function(cond) return C().Get("form").Summary(cond) end }
KIND.groupType = { sentence = function(cond) return C().Get("groupType").Summary(cond) end }
KIND.zone = { sentence = function(cond) return C().Get("zone").Summary(cond) end }
KIND.target = { sentence = function(cond) return C().Get("target").Summary(cond) end }

KIND.wellFed = {
    sentence = function(cond)
        local c = C().WellFedChoice(cond.what)
        if not c then return nil end
        return "You " .. c[3]:gsub("Well Fed", "well fed")
    end,
}

-- The words for a condition as stored (a clean copy, or any table with the provider's fields).
function Pl.CondSentence(cond)
    local meta = type(cond) == "table" and KIND[cond.type]
    if meta and meta.sentence then
        local ok, text = pcall(meta.sentence, cond)
        if ok and type(text) == "string" then return text end
    end
    return nil
end

local function KindOf(entry)
    local t = entry and entry.raw and entry.raw.type
    return (type(t) == "string" and t:match("^[%w_]+$") and #t <= 24) and t or "unknown"
end

-- The condition of an entry as a sentence. A kind this version doesn't know, and a condition whose data can't be read,
-- are said so (they are kept as saved).
function Pl.Sentence(entry)
    if Pl.LocationValues and Pl.LocationValues(entry) then
        local values = Pl.LocationValues(entry)
        local places = {}
        for _, value in ipairs(values) do places[#places + 1] = value == "dungeon" and "a dungeon" or "a raid" end
        local negative = entry.cond and entry.cond.negate
        return (negative and "You are outside " or "You are in ") .. table.concat(places, " or ")
    end
    if entry.group then return Pl.Words(entry.match).heading end
    if not entry.provider then return "Unsupported condition" end
    if not entry.cond then return "A condition TwichUI can't read" end
    return Pl.CondSentence(entry.cond) or E().Summary(entry)
end

-- The technical detail of a condition that can't be used, for a second line or a tooltip.
function Pl.Technical(entry)
    if entry.group or entry.cond then return nil end
    if not entry.provider then
        return ("Saved as the kind \"%s\", which this version of TwichUI doesn't know. It is kept exactly as saved, and the reminder can't run until it is removed."):format(KindOf(entry))
    end
    return entry.why and Upper1(entry.why) or nil
end

-- What this client can't report for a condition, as a short line and a longer one; nil when nothing is missing.
function Pl.Capability(entry)
    local cond = entry and entry.cond
    if type(cond) ~= "table" then return nil end
    if cond.type == "ammunition" and R.ReminderAmmo and not R.ReminderAmmo.Supported() then
        return "Cannot check ammunition on this client.", "The client does not report whether this ranged weapon uses ammunition."
    elseif cond.type == "player" and not C().StateSupported(cond.state) then
        local s = C().State(cond.state)
        local what = s and s[3] or "that"
        return ("Cannot check whether you are %s on this client."):format(what), ("The client does not report whether you are %s."):format(what)
    end
    local p = C().Get(cond.type)
    if p and p.Supported and not p.Supported() then
        return "Cannot check this on this client.", Upper1(p.unsupported or "the client does not report it.")
    end
    return nil
end

-- What is wrong with a condition, in a sentence: a limit of this client first, then what the model says.
function Pl.Problem(entry)
    if entry.group then return entry.why and Upper1(entry.why) or nil end
    local short = Pl.Capability(entry)
    if short then return short end
    if not entry.provider then return "Unsupported condition: it is kept as saved, and the reminder can't run until it is removed." end
    return entry.why and Upper1(entry.why) or nil
end

---------------------------------------------------------------------------
-- The picker: what can be added, from the kinds that are registered
---------------------------------------------------------------------------
Pl.CATEGORIES = { "Combat", "Character", "Buffs", "Equipment", "Supplies", "Places and group", "Other" }
-- the order the palette lists them in
Pl.PALETTE_ORDER = { "Equipment", "Character", "Buffs", "Supplies", "Combat", "Places and group", "Other" }

-- an icon (R.Icons id) for a kind of condition, drawn small beside it
local ICON = { equipment = "gearComparison", ammunition = "ammunition", class = "profiles", talent = "classResources", weaponEnchant = "reminders", wellFed = "foodAndDrink",
    aura = "mage", power = "healerWatch", cooldown = "diagTimeline", groupType = "profilesSharing", zone = "mapToolbar", target = "targetArt" }
local PLAYER_ICON = { combat = "hazardAlerts", dead = "resurrection", ghost = "releaseSpirit", mounted = "navigation", resting = "sleepingBag", dungeon = "mapsNavigation", raid = "mapsNavigation",
    moving = "navigation", taxi = "navigation" }
-- Condition identity never changes a reminder's selected art or a template illustration. The painted vendor and
-- trainer pictures (media/npcs, NK.ART) stand for the conditions whose subject they show.
local CONDITION_ART = {
    weaponEnchant = [[media\reminders\conditions\enchant]],
    combat = [[media\reminders\conditions\combat]],
    mounted = [[media\npcs\horse-head]],
    taxi = [[media\npcs\wing]],
    itemCount = [[media\npcs\reagent-pouch]],
    bagSpace = [[media\npcs\leather-backpack]],
    durability = [[media\npcs\hammer]],
    spellKnown = [[media\npcs\sealed-scroll]],
    form = [[media\npcs\paw]],
    level = [[media\npcs\hooded-winged-figure]],
}
function Pl.ArtFile(cond, size)
    local key = cond and (cond.type == "player" and cond.state or cond.type)
    local path = CONDITION_ART[key]
    return path and (R.PATH .. path .. ((size or 64) <= 26 and "-small.tga" or ".tga")) or nil
end
function Pl.Icon(cond)
    if type(cond) ~= "table" then return "reminderTest" end
    if cond.type == "player" then return PLAYER_ICON[cond.state] or "reminderTest" end
    if cond.type == "aura" and cond.harmful then return "hazardAlerts" end
    return ICON[cond.type] or "reminderTest"
end

function Pl.ApplyArt(texture, cond, size)
    local dedicated = Pl.ArtFile(cond, size)
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetSize(size, size)
    if dedicated and texture:SetTexture(dedicated) ~= false then
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end
    local art = cond and cond.type == "wellFed" and "wellfed"
    local file, l, r, t, b, aspect
    if art then file, l, r, t, b, aspect = RM().ArtTexture(art, size) end
    texture:SetVertexColor(1, 1, 1, 1)
    texture:SetSize(size, size)
    if file and texture:SetTexture(file) ~= false then
        texture:SetTexCoord(l, r, t, b)
        texture:SetSize(size * math.min(1, aspect), size / math.max(1, aspect))
        return
    end
    R.Icons.Apply(texture, Pl.Icon(cond), size)
end

local CARD_TITLE = { equipment = "Equipment slot", ammunition = "Ammunition", class = "Class",
    talent = "Specialization", weaponEnchant = "Weapon enchant", wellFed = "Well Fed",
    itemCount = "Item count", bagSpace = "Bag space", durability = "Durability", power = "Resource", spellKnown = "Spell known",
    form = "Form or stance", level = "Level", cooldown = "Cooldown", groupType = "Group", zone = "Place", target = "Target" }
local PLAYER_TITLE = { combat = "Combat", dead = "Alive or dead", ghost = "Ghost", mounted = "Mounted",
    resting = "Resting", dungeon = "Location", raid = "Location", moving = "Moving", taxi = "Flight path" }
local PLAYER_LABEL = { dungeon = "Dungeon", raid = "Raid" }

function Pl.CardTitle(cond)
    if cond.type == "aura" then return cond.harmful and "Debuff" or "Buff" end
    return cond.type == "player" and PLAYER_TITLE[cond.state] or CARD_TITLE[cond.type]
end

-- Only this lossless OR of supported positive location predicates has a chip presentation.
function Pl.LocationValues(entry)
    if not entry or entry.why then return nil end
    if not entry.group then
        local cond = entry.cond
        if cond and cond.type == "player" and PLAYER_LABEL[cond.state] then return { cond.state } end
        return nil
    end
    if entry.match ~= "any" or #entry.children == 0 then return nil end
    local seen, values = {}, {}
    for _, child in ipairs(entry.children) do
        local cond = child.cond
        if child.why or child.group or not cond or cond.type ~= "player" or not PLAYER_LABEL[cond.state]
            or cond.negate or seen[cond.state] then return nil end
        seen[cond.state] = true
        values[#values + 1] = cond.state
    end
    return values
end

-- A flat conjunction can show its first stored leaf as the trigger. The remaining leaves
-- are required restrictions. Presentation never changes the order, scope or operators.
function Pl.Basic(view)
    if view.match ~= "all" or view.broken then return false end
    for i, entry in ipairs(view.conditions) do
        if entry.group then
            if i == 1 or not Pl.LocationValues(entry) then return false end
        elseif not entry.cond or not Pl.CardTitle(entry.cond) then return false end
    end
    for _, problem in ipairs(view.problems) do
        if problem == RM().PROBLEM.tooMany or problem == RM().PROBLEM.tooManyGroups then return false end
    end
    return true
end

function Pl.CompactRule(view)
    if not Pl.Basic(view) then return "Uses Advanced logic" end
    local conditions = view.conditions
    if #conditions == 0 then return "Add a condition to start" end
    local trigger = Pl.Sentence(conditions[1])
    if #conditions == 1 then return trigger end
    local more = #conditions > 2 and (" +%d"):format(#conditions - 2) or ""
    return trigger, Pl.Sentence(conditions[2]) .. more
end

local VISIBILITY = {
    hidden = "Conditions not met", disabled = "Reminder off", off = "Reminders off",
    notApplicable = "Other character", invalid = "Needs attention", pending = "Waiting for delay",
    waiting = "Waiting for information", world = "Waiting to enter the world",
}

function Pl.Visibility(id)
    local ct = R.ReminderController
    if ct.Visible(id) then return "Visible in game", "ok" end
    local status = ct.Status(id)
    local reason = VISIBILITY[status]
    return reason and ("Hidden in game · " .. reason) or "Hidden in game", status == "invalid" and "warn" or "quiet"
end

function Pl.LiveFeedback(view)
    local controller = R.ReminderController
    local status = controller.Status(view.id)
    if controller.Visible(view.id) then return "Showing now", "met", status == "holding" and "Minimum display time" or "Conditions met", true end
    if status == "invalid" then return "Needs attention", "invalid", view.problems[1] or "Review this reminder." end
    if status == "waiting" or status == "world" then return "Unknown", "unknown", VISIBILITY[status] end
    if status == "hidden" then
        local out = controller.Inspect(view.id)
        if view.match == "all" and out and out.conditions then
            for _, row in ipairs(out.conditions) do
                local entry = row.entry
                if row.result == "nomatch" and entry and #entry.path == 1 then
                    local cond, observed = entry.cond, row.observed
                    if cond and cond.type == "player" and PLAYER_LABEL[cond.state] then
                        return "Hidden now", "unmet", "Your location does not match."
                    end
                    local reason = observed and observed ~= "" and ("Observed: " .. observed) or "A required condition is not met."
                    return "Hidden now", "unmet", reason
                end
            end
        end
    end
    return "Hidden now", "unmet", VISIBILITY[status] or "Waiting to show"
end

local PLAYER_BLURB = {
    combat = "Whether you are in combat.",
    dead = "Whether you are dead or a ghost (after releasing your spirit you stay dead until you are back in your body).",
    ghost = "Whether you are a ghost: your spirit has been released.",
    mounted = "Whether you are on a mount.",
    resting = "Whether you are resting: in an inn or a capital city.",
    dungeon = "Whether you are inside a dungeon (a five-player instance).",
    raid = "Whether you are inside a raid instance.",
    moving = "Whether you are moving. It changes with every step, so it suits \"only while standing still\" with a short wait before showing.",
    taxi = "Whether you are on a flight path.",
}

-- The kinds added with the condition library: key, category, palette name, blurb
local MORE = {
    aura = { "Buffs", "A buff or debuff on you", "Whether a buff or debuff you choose (by its spell ID) is on you, how long it has left or how many stacks it has. Each rank of a spell has an ID of its own: add each one you want to count. Not readable while the game hides your buffs from addons." },
    itemCount = { "Supplies", "How many of an item you carry", "Counts one item in your bags (not the bank) and compares it with a number: fewer than 10 candles, at least one hearthstone." },
    bagSpace = { "Supplies", "Free bag slots", "How many free slots your general bags have. Room in a quiver, soul bag or profession bag isn't counted: it can't take just anything." },
    durability = { "Equipment", "Equipment durability", "Whether something you wear is broken, or worn below a share you choose. Each item is judged on its own, never an average." },
    power = { "Character", "Your mana, rage or energy", "Your mana, rage or energy as a share of its maximum. A character with no such resource never matches. Not readable while the game hides it from addons." },
    spellKnown = { "Character", "A spell you know", "Whether you know a spell: drag it from your spellbook onto the card, or type its spell ID. A different rank is a different spell." },
    form = { "Character", "Your form or stance", "Whether you are in a form or stance (a druid form, a warrior stance, stealth), or in none." },
    level = { "Character", "Your level", "Your character's level compared with a number." },
    cooldown = { "Combat", "A spell's cooldown", "Whether a spell you know is ready, cooling down, or ready within a time you choose. The global cooldown after any spell doesn't count." },
    target = { "Combat", "Your target", "Whether you have a target, and whether it can be attacked, is friendly or is dead. With no target, only \"You have a target\" can be true or false." },
    groupType = { "Places and group", "Your group", "Whether you are solo, in a party or in a raid group: whom you are grouped with, not where you are." },
    zone = { "Places and group", "Where you are", "A zone, city or instance, chosen where you are now. A zone includes the towns, caves and buildings inside it." },
}

function Pl.Entries()
    local CT = C()
    local out = {}
    for _, p in ipairs(CT.List()) do
        if p.type == "equipment" then
            out[#out + 1] = { key = "equipment", kind = "equipment", category = "Equipment", name = "Something equipped, or not",
                blurb = "What is in an equipment slot: empty, a shield, a weapon, or a specific item.", icon = Pl.Icon({ type = "equipment" }),
                make = function() return p.New() end }
        elseif p.type == "player" then
            for _, st in ipairs(CT.STATES) do
                local make = function() return { type = "player", state = st[1], negate = false } end
                local supported = CT.StateSupported(st[1])
                local category = st[1] == "combat" and "Combat" or (PLAYER_LABEL[st[1]] and "Character" or "Other")
                out[#out + 1] = { key = "player:" .. st[1], kind = "player", category = category,
                    name = Pl.CondSentence(make()), blurb = PLAYER_BLURB[st[1]] or "Something about you.", icon = Pl.Icon(make()), make = make,
                    note = (not supported) and "This client doesn't report it, so a reminder using it can't be turned on here." or nil }
            end
        elseif p.type == "class" then
            out[#out + 1] = { key = "class", kind = "class", category = "Character", name = "Your class",
                blurb = "Which class you are. For several classes, add one for each in a group where at least one must be true.",
                icon = Pl.Icon({ type = "class" }), make = function() return p.New() end }
        elseif p.type == "talent" then
            out[#out + 1] = { key = "talent", kind = "talent", category = "Character", name = "Your talent specialization",
                blurb = "The talent tree with the most points spent. Equal highest totals count as tied.",
                icon = Pl.Icon({ type = "talent" }), make = function() return p.New() end }
        elseif p.type == "weaponEnchant" then
            out[#out + 1] = { key = "weaponEnchant", kind = "weaponEnchant", category = "Equipment", name = "Your weapon's temporary enchant",
                blurb = "Whether the weapon in a hand has a weapon oil, sharpening stone or poison on it. The game says whether one is on, not which.",
                icon = Pl.Icon({ type = "weaponEnchant" }), make = function() return p.New() end }
        elseif p.type == "wellFed" then
            out[#out + 1] = { key = "wellFed", kind = "wellFed", category = "Other", name = "Your Well Fed buff",
                blurb = "Whether you have a Well Fed buff from eating good food, so a reminder can appear when it runs out. Not readable while the game hides your buffs from addons.",
                icon = Pl.Icon({ type = "wellFed" }), make = function() return p.New() end }
        elseif p.type == "ammunition" then
            local A = R.ReminderAmmo
            out[#out + 1] = { key = "ammunition", kind = "ammunition", category = "Equipment", name = "Your ranged ammunition",
                blurb = "The ammunition for your ranged weapon: none selected, used up or the wrong kind. It never matches for a weapon that takes none.",
                icon = Pl.Icon({ type = "ammunition" }), make = function() return p.New() end,
                note = (A and not A.Supported()) and "This client doesn't say whether a weapon takes ammunition, so a reminder using it can't be turned on here." or nil }
        elseif MORE[p.type] then
            local m = MORE[p.type]
            local make = function() return p.New() end
            out[#out + 1] = { key = p.type, kind = p.type, category = m[1], name = m[2], blurb = m[3], icon = Pl.Icon(make()), make = make,
                note = (p.Supported and not p.Supported()) and "This client doesn't report it, so a reminder using it can't be turned on here." or nil }
            if p.type == "aura" then
                local debuff = function() local c = p.New(); c.harmful, c.what = true, "present" return c end
                out[#out + 1] = { key = "aura:harmful", kind = "aura", category = m[1], name = "A debuff on you",
                    blurb = "Whether a debuff you choose (by its spell ID) is on you. Not readable while the game hides your auras from addons.",
                    icon = Pl.Icon(debuff()), make = debuff }
            end
        else
            -- a kind added later: offered under Other until it has words of its own here
            out[#out + 1] = { key = "kind:" .. p.type, kind = p.type, category = "Other", name = p.label or p.type,
                blurb = "A condition of this kind.", icon = "reminderTest", make = function() return p.New() end }
        end
    end
    return out
end

-- Whether an entry matches what was typed (a few letters of its name, what it says or its category).
function Pl.Matches(entry, query)
    if not query or query == "" then return true end
    query = query:lower()
    local state = entry.kind == "player" and entry.key:match("^player:(.+)$")
    local title = CARD_TITLE[entry.kind] or PLAYER_TITLE[state] or (entry.kind == "aura" and "buff debuff aura") or ""
    return (entry.name:lower():find(query, 1, true) or entry.blurb:lower():find(query, 1, true)
        or entry.category:lower():find(query, 1, true) or title:lower():find(query, 1, true)) ~= nil
end

---------------------------------------------------------------------------
-- The editor's fields: which a condition has, and how a change makes a new condition (never edits the one it is given)
---------------------------------------------------------------------------
function Pl.Subjects()
    local CT = C()
    local out = {}
    for _, slot in ipairs(CT.SLOTS) do out[#out + 1] = { value = "slot:" .. slot[1], label = slot[3] } end
    for _, h in ipairs(CT.ENCHANT_HANDS) do out[#out + 1] = { value = "enchant:" .. h[1], label = h[2] .. " weapon enchant" } end
    out[#out + 1] = { value = "ammo", label = "Ranged ammunition" }
    out[#out + 1] = { value = "wellFed", label = "Well Fed buff" }
    out[#out + 1] = { value = "player", label = "You (the player)" }
    out[#out + 1] = { value = "class", label = "Player class" }
    out[#out + 1] = { value = "talent", label = "Talent specialization" }
    return out
end

-- the subject choice that makes a condition of a kind of its own (the others are equipment slots)
local SUBJECT_KIND = { player = "player", ammo = "ammunition", class = "class", talent = "talent", wellFed = "wellFed" }

function Pl.SubjectOf(cond)
    if type(cond) ~= "table" then return nil, "?" end
    local CT = C()
    if cond.type == "equipment" then
        local s = CT.Slot(cond.slot)
        return "slot:" .. tostring(cond.slot), s and s[3] or tostring(cond.slot)
    elseif cond.type == "player" then
        return "player", "You (the player)"
    elseif cond.type == "weaponEnchant" then
        local h = CT.EnchantHand(cond.hand)
        return "enchant:" .. tostring(cond.hand), (h and h[2] or tostring(cond.hand)) .. " weapon enchant"
    elseif cond.type == "ammunition" then
        return "ammo", "Ranged ammunition"
    elseif cond.type == "wellFed" then
        return "wellFed", "Well Fed buff"
    elseif cond.type == "class" then
        return "class", "Player class"
    elseif cond.type == "talent" then
        return "talent", "Talent specialization"
    end
    return nil, "Unknown kind"
end

function Pl.ValueChoices(cond)
    local CT = C()
    local out = {}
    if FIELDS[cond.type] then
        for _, f in ipairs(FIELDS[cond.type](cond)) do
            if f.key == "value" then return f.choices end
        end
        return out
    end
    if cond.type == "equipment" then
        for _, c in ipairs(CT.SlotChoices(cond.slot)) do out[#out + 1] = { value = c[1], label = c[2] } end
    elseif cond.type == "weaponEnchant" then
        for _, c in ipairs(CT.ENCHANT_CHOICES) do out[#out + 1] = { value = c[1], label = c[2], tooltip = c[4] } end
    elseif cond.type == "wellFed" then
        for _, c in ipairs(CT.WELLFED_CHOICES) do out[#out + 1] = { value = c[1], label = c[2], tooltip = c[4] } end
    elseif cond.type == "ammunition" then
        for _, c in ipairs(R.ReminderAmmo.CHOICES) do out[#out + 1] = { value = c[1], label = c[2], tooltip = c[4] } end
    elseif cond.type == "class" then
        for _, c in ipairs(CT.ClassChoices()) do out[#out + 1] = { value = c[1], label = c[2] } end
    elseif cond.type == "talent" then
        for _, c in ipairs(CT.TalentChoices()) do out[#out + 1] = { value = c[1], label = c[2] } end
    elseif cond.type == "player" then
        for _, st in ipairs(CT.STATES) do
            if CT.StateSupported(st[1]) or cond.state == st[1] then
                out[#out + 1] = { value = st[1], label = Upper1(st[3]) .. (CT.StateSupported(st[1]) and "" or " (not reported by this client)") }
            end
        end
    end
    return out
end

-- The key of the value a condition has chosen (what the value dropdown shows as selected).
function Pl.ValueKey(cond)
    if cond.type == "talent" then return C().TalentValueKey(cond) end
    if FIELDS[cond.type] then
        for _, f in ipairs(FIELDS[cond.type](cond)) do
            if f.key == "value" then return f.value end
        end
        return nil
    end
    return cond.what or cond.state or cond.class
end

function Pl.ValueLabel(cond)
    if cond.type == "class" and not cond.class then return "Choose a class" end
    if cond.type == "talent" and not Pl.ValueKey(cond) then return "Choose a specialization" end
    local key = Pl.ValueKey(cond)
    for _, c in ipairs(Pl.ValueChoices(cond)) do if c.value == key then return c.label end end
    return tostring(key)
end

-- Whether the operator ("is" / "is not") is a choice for this condition: the kinds stored with `negate`. The others read
-- as a sentence on their own, or compare a number ("below" / "at least" is their own field).
local NEGATES = { equipment = true, player = true, class = true, talent = true, spellKnown = true, form = true, groupType = true, zone = true, target = true }
function Pl.HasOperator(cond) return type(cond) == "table" and NEGATES[cond.type] == true end

-- What kind of ID a condition asks for: "item" (an item ID, link or dropped item), "spell" (a spell ID or link), nil.
local ID_KIND = { itemCount = "item", aura = "spell", spellKnown = "spell", cooldown = "spell" }
function Pl.NeedsId(cond)
    if type(cond) ~= "table" then return nil end
    if cond.type == "equipment" then return cond.what == "item" and "item" or nil end
    return ID_KIND[cond.type]
end
-- Whether the condition names a specific item (the editor then asks for it).
function Pl.NeedsItem(cond) return Pl.NeedsId(cond) == "item" end
-- Whether the ID it asks for is chosen.
function Pl.HasId(cond)
    if cond.type == "aura" then return type(cond.spells) == "table" and #cond.spells > 0 end
    if Pl.NeedsId(cond) == "spell" then return cond.spell ~= nil end
    return cond.item ~= nil
end
-- What the card's button says.
function Pl.IdButton(cond)
    local has = Pl.HasId(cond)
    if cond.type == "aura" then return (has and "Change " or "Choose ") .. (cond.harmful and "debuff" or "buff") end
    if Pl.NeedsId(cond) == "spell" then return has and "Change spell" or "Choose spell" end
    return has and "Change item" or "Choose item"
end
-- The IDs as the edit box shows them: "1459, 10156".
function Pl.IdText(cond)
    if cond.type == "aura" then
        local parts = {}
        for i, id in ipairs(cond.spells or {}) do parts[i] = tostring(id) end
        return table.concat(parts, ", ")
    end
    local id = Pl.NeedsId(cond) == "spell" and cond.spell or cond.item
    return id and tostring(id) or ""
end
-- Spell IDs from what was typed or pasted: numbers, or spell links ("spell:<id>"), up to `max`. nil when none, or a
-- second value "many" when there are more than max.
function Pl.ParseSpells(text, max)
    if type(text) ~= "string" then return nil end
    local out, seen = {}, {}
    local function Take(n)
        n = tonumber(n)
        if C().ValidSpell(n) and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    local linked = false
    for n in text:gmatch("spell:(%d+)") do linked = true; Take(n) end
    if not linked then
        if text:find("[^%d%s,;]") then return nil end
        for n in text:gmatch("%d+") do Take(n) end
    end
    if #out == 0 then return nil end
    if max and #out > max then return nil, "many" end
    return out
end
-- The condition with these IDs (a list for a buff; the first otherwise).
function Pl.WithIds(cond, ids)
    local new = RM().DeepCopy(cond)
    if new.type == "aura" then
        local list = {}
        for i, id in ipairs(ids) do list[i] = id end
        new.spells = list
    elseif Pl.NeedsId(new) == "spell" then new.spell = ids[1]
    else new.item = ids[1] end
    return new
end
-- What dropping what the cursor holds does to a condition that asks for an item or a spell. what, a, b, c are
-- GetCursorInfo's first four answers: "item", itemID, itemLink; "spell", spellIndex, bookType, spellID (the slot is not
-- the spell's ID: the fourth answer is). Returns the new condition and a line saying what was done, or nil and why
-- not (what is held is then left alone). A buff takes a list, so a spell is added to it (never twice, at most
-- MAX_SPELLS); everything else is replaced. Pure: nothing is written and the cursor isn't touched.
function Pl.Drop(cond, what, a, b, c)
    local need = Pl.NeedsId(cond)
    if not need then return nil, "This condition doesn't take an item or a spell." end
    local function Plain(v) if issecretvalue and issecretvalue(v) then return nil end return v end
    what = Plain(what)
    local askFor = need == "item" and "an item: drag one from your bags" or "a spell: drag one from your spellbook"
    if what ~= "item" and what ~= "spell" then
        return nil, ("This condition looks for %s."):format(askFor)
    end
    if what ~= need then
        return nil, ("That is %s. This condition looks for %s."):format(what == "item" and "an item" or "a spell", askFor)
    end
    if what == "item" then
        local id = Plain(a)
        if not RM().ValidItem(id) then return nil, "The game didn't say which item that is. Type its item ID instead." end
        return Pl.WithIds(cond, { id }), ("Now looks for %s."):format(C().ItemWords(id))
    end
    local id = Plain(c)
    if not C().ValidSpell(id) then return nil, "The game didn't say which spell that is. Type its spell ID instead." end
    if cond.type == "aura" then
        local list = {}
        for i, other in ipairs(cond.spells or {}) do
            if other == id then return nil, ("%s is already in the list."):format(C().SpellWords(id)) end
            list[i] = other
        end
        if #list >= AU().MAX_SPELLS then return nil, ("At most %d spells: remove one first."):format(AU().MAX_SPELLS) end
        list[#list + 1] = id
        return Pl.WithIds(cond, list), ("Added %s."):format(C().SpellWords(id))
    end
    return Pl.WithIds(cond, { id }), ("Now looks at %s."):format(C().SpellWords(id))
end

-- What the IDs are, for a line beside the box: "Arcane Intellect, Arcane Brilliance" (or the IDs, while the game has
-- no names for them). nil when nothing is chosen.
function Pl.SpellLine(cond)
    local list = cond.type == "aura" and cond.spells or { cond.spell }
    local names = {}
    for _, id in ipairs(list or {}) do names[#names + 1] = C().SpellWords(id) end
    if #names == 0 then return nil end
    return table.concat(names, ", ")
end

---------------------------------------------------------------------------
-- The fields of the kinds added with the condition library. Each is { key, value, label, choices, set } and, for a
-- number, kind = "number", field (the stored name), min, max and words: the card offers its quick choices and "Other
-- amount...", the editor a box for any whole number from min to max. `set(cond, value)` makes the new condition.
---------------------------------------------------------------------------
Pl.OTHER = "other"

local function Copy(cond) return RM().DeepCopy(cond) end

-- words: the editor's ("5 minutes"); short (optional): the card's dropdown, which has a third of a card ("5 min")
local function Amount(cond, field, presets, lo, hi, words, short)
    short = short or words
    local value = cond[field]
    local choices, have = {}, false
    for _, n in ipairs(presets) do
        choices[#choices + 1] = { value = n, label = short(n) }
        if n == value then have = true end
    end
    if value and not have then
        choices[#choices + 1] = { value = value, label = short(value) }
        table.sort(choices, function(a, b) return a.value < b.value end)
    end
    choices[#choices + 1] = { value = Pl.OTHER, label = "Other amount..." }
    return { key = "amount", kind = "number", field = field, value = value, label = value and short(value) or "Choose",
        choices = choices, min = lo, max = hi, words = words,
        set = function(c, v)
            if v == Pl.OTHER or type(v) ~= "number" then return nil end
            local new = Copy(c)
            new[field] = v
            return new
        end }
end

local function Choice(key, value, choices, set)
    local label
    for _, c in ipairs(choices) do if c.value == value then label = c.label end end
    return { key = key, value = value, label = label or "Choose", choices = choices, set = set }
end

local function CompareField(cond, below)
    return Choice("op", cond.compare, { { value = "below", label = below or "Below" }, { value = "atLeast", label = "At least" } },
        function(c, v) local new = Copy(c); new.compare = v; return new end)
end

local function NegateField(cond, yes, no)
    return Choice("op", cond.negate and "not" or "is", { { value = "is", label = yes }, { value = "not", label = no } },
        function(c, v) local new = Copy(c); new.negate = v == "not"; return new end)
end

local function Seconds(n) return C().Duration(n) end
-- "45 s", "5 min", "1 min 30 s"
local function ShortSeconds(n)
    local m, s = math.floor(n / 60), n % 60
    if m == 0 then return s .. " s" end
    if s == 0 then return m .. " min" end
    return ("%d min %d s"):format(m, s)
end
Pl.ShortSeconds = ShortSeconds
local function Percent(n) return n .. "%" end

FIELDS.aura = function(cond)
    local A = AU()
    local out = {}
    out[1] = Choice("subject", cond.harmful and "harmful" or "helpful", { { value = "helpful", label = "Buff" }, { value = "harmful", label = "Debuff" } },
        function(c, v) local new = Copy(c); new.harmful = v == "harmful"; return new end)
    local value = cond.what == "stacks" and ("stacks:" .. (cond.compare or "atLeast")) or cond.what
    local choices = {}
    for _, c in ipairs(A.CHOICES) do
        if c[1] == "stacks" then
            choices[#choices + 1] = { value = "stacks:atLeast", label = "Stacks at least", tooltip = c[3] }
            choices[#choices + 1] = { value = "stacks:below", label = "Stacks fewer than", tooltip = c[3] }
        else
            choices[#choices + 1] = { value = c[1], label = c[2], tooltip = c[3] }
        end
    end
    out[2] = Choice("value", value, choices, function(c, v)
        local new = Copy(c)
        local compare = tostring(v):match("^stacks:(.+)$")
        new.what = compare and "stacks" or v
        new.compare = compare
        if new.what == "expiring" then new.seconds = new.seconds or A.SECONDS_DEFAULT end
        if new.what == "stacks" then new.stacks = new.stacks or A.STACKS_DEFAULT end
        return new
    end)
    -- the card says the selected choice in short: the amount beside it says what it counts
    if cond.what == "stacks" then out[2].label = cond.compare == "below" and "Fewer than" or "At least" end
    if cond.what == "expiring" then out[3] = Amount(cond, "seconds", A.SECONDS, 1, A.SECONDS_MAX, Seconds, ShortSeconds) end
    if cond.what == "stacks" then out[3] = Amount(cond, "stacks", A.STACKS, 1, A.STACKS_MAX, function(n) return n == 1 and "1 stack" or (n .. " stacks") end) end
    return out
end

FIELDS.itemCount = function(cond)
    local S = SU()
    return { CompareField(cond, "Fewer than"), Amount(cond, "count", S.COUNTS, 1, S.COUNT_MAX, tostring) }
end

FIELDS.bagSpace = function(cond)
    local S = SU()
    return { CompareField(cond, "Fewer than"), Amount(cond, "count", S.FREE, 1, S.FREE_MAX, function(n) return n == 1 and "1 free slot" or (n .. " free slots") end) }
end

FIELDS.durability = function(cond)
    local S = SU()
    local choices = {}
    for _, c in ipairs(S.DURABILITY_CHOICES) do choices[#choices + 1] = { value = c[1], label = c[2], tooltip = c[3] } end
    local out = { Choice("value", cond.what, choices, function(c, v)
        local new = Copy(c); new.what = v
        if v == "below" then new.percent = new.percent or 20 end
        return new
    end) }
    if cond.what == "below" then out[2] = Amount(cond, "percent", S.PERCENTS, 1, 100, function(n) return "Below " .. n .. "%" end) end
    return out
end

FIELDS.power = function(cond)
    local H = CH()
    local choices = {}
    for _, p in ipairs(H.POWERS) do choices[#choices + 1] = { value = p[1], label = p[3] } end
    return {
        Choice("subject", cond.power, choices, function(c, v) local new = Copy(c); new.power = v; return new end),
        CompareField(cond),
        Amount(cond, "percent", H.PERCENTS, 1, 100, Percent),
    }
end

FIELDS.level = function(cond)
    local H = CH()
    return { CompareField(cond), Amount(cond, "level", H.LEVELS, 1, H.LEVEL_MAX, function(n) return "Level " .. n end) }
end

FIELDS.spellKnown = function(cond) return { NegateField(cond, "Know it", "Don't know it") } end

FIELDS.form = function(cond)
    local H = CH()
    local choices, seen = {}, {}
    local function Put(value, label) if not seen[value] then seen[value] = true; choices[#choices + 1] = { value = value, label = label } end end
    for _, f in ipairs(H.FormChoices()) do Put(f[1], f[2]) end
    if cond.form then Put(cond.form, C().SpellWords(cond.form)) end
    Put(H.FORM_NONE, "No form or stance")
    return {
        NegateField(cond, "In", "Not in"),
        Choice("value", cond.state or cond.form, choices, function(c, v)
            local new = Copy(c)
            if v == H.FORM_NONE then new.state, new.form = v, nil else new.state, new.form = nil, v end
            return new
        end),
    }
end

FIELDS.cooldown = function(cond)
    local H = CH()
    local choices = {}
    for _, c in ipairs(H.COOLDOWN_CHOICES) do choices[#choices + 1] = { value = c[1], label = c[2], tooltip = c[3] } end
    local out = { Choice("value", cond.what, choices, function(c, v)
        local new = Copy(c); new.what = v
        if v == "within" then new.seconds = new.seconds or 10 end
        return new
    end) }
    if cond.what == "within" then out[2] = Amount(cond, "seconds", H.COOLDOWN_SECONDS, 1, H.COOLDOWN_SECONDS_MAX, Seconds, ShortSeconds) end
    return out
end

FIELDS.groupType = function(cond)
    local X = CX()
    local choices = {}
    for _, g in ipairs(X.GROUP_CHOICES) do choices[#choices + 1] = { value = g[1], label = g[2] } end
    return { NegateField(cond, "Is", "Is not"), Choice("value", cond.what, choices, function(c, v) local new = Copy(c); new.what = v; return new end) }
end

FIELDS.zone = function(cond)
    local X = CX()
    return {
        NegateField(cond, "In", "Not in"),
        Choice("value", X.ZoneKey(cond), X.ZoneChoices(cond), function(c, v)
            local new = Copy(c)
            local kind, id = tostring(v):match("^(%a+):(%d+)$")
            if not kind then return nil end
            new.map, new.instance = nil, nil
            new[kind] = tonumber(id)
            return new
        end),
    }
end

FIELDS.target = function(cond)
    local X = CX()
    local choices = {}
    for _, t in ipairs(X.TARGET_CHOICES) do choices[#choices + 1] = { value = t[1], label = t[2] } end
    return { NegateField(cond, "Yes", "No"), Choice("value", cond.what, choices, function(c, v) local new = Copy(c); new.what = v; return new end) }
end

-- The amount a weapon enchant's "running out" compares with (the enchant's other fields are the original ones below).
local function EnchantAmount(cond)
    local CT = C()
    return Amount(cond, "seconds", CT.ENCHANT_SECONDS, 1, CT.ENCHANT_SECONDS_MAX, Seconds, ShortSeconds)
end

-- A condition with a number typed into the editor (nil when the field doesn't take one). The provider checks the range.
function Pl.WithNumber(cond, field, n)
    if type(n) ~= "number" then return nil end
    local new = Copy(cond)
    new[field] = n
    return new
end

-- A new condition: the subject chosen (keeping "is not", the item and a value that still fits).
function Pl.WithSubject(cond, value)
    local CT = C()
    local kind = SUBJECT_KIND[value]
    if kind then
        if type(cond) == "table" and cond.type == kind then return RM().DeepCopy(cond) end
        return CT.Get(kind).New()
    end
    local hand = type(value) == "string" and value:match("^enchant:(.+)$")
    if hand then
        if not CT.EnchantHand(hand) then return nil end
        local what = type(cond) == "table" and cond.type == "weaponEnchant" and cond.what or "missing"
        return { type = "weaponEnchant", hand = hand, what = what }
    end
    local key = type(value) == "string" and value:match("^slot:(.+)$")
    if not (key and CT.Slot(key)) then return nil end
    local new = { type = "equipment", slot = key, negate = type(cond) == "table" and cond.negate == true or false }
    local allowed = {}
    for _, c in ipairs(CT.SlotChoices(key)) do allowed[c[1]] = true end
    local what = type(cond) == "table" and cond.type == "equipment" and cond.what or nil
    new.what = allowed[what] and what or (key == "any" and "item" or "empty")
    if new.what == "item" and type(cond) == "table" then new.item = cond.item end
    return new
end

function Pl.WithNegate(cond, negate)
    local new = RM().DeepCopy(cond)
    new.negate = negate and true or false
    return new
end

function Pl.WithValue(cond, value)
    local new = RM().DeepCopy(cond)
    if new.type == "player" then new.state = value
    elseif new.type == "class" then new.class = value
    elseif new.type == "talent" then
        -- a tree ("SHAMAN:374") names its class and tree; a state ("tied", "none") names neither
        local class, line = tostring(value):match("^(%u+):(%d+)$")
        if class then new.class, new.tree, new.state = class, tonumber(line), nil
        else new.class, new.tree, new.state = nil, nil, value end
    else
        new.what = value
        if new.type == "weaponEnchant" and value == "expiring" then new.seconds = new.seconds or C().ENCHANT_SECONDS_DEFAULT end
    end
    return new
end

function Pl.WithItem(cond, id)
    local new = RM().DeepCopy(cond)
    new.item = id
    return new
end

function Pl.CardFields(cond)
    if FIELDS[cond.type] then return FIELDS[cond.type](cond) end
    local fields = {}
    if cond.type == "weaponEnchant" or cond.type == "equipment" then
        local value, label = Pl.SubjectOf(cond)
        local prefix = cond.type == "equipment" and "slot:" or "enchant:"
        local choices = {}
        for _, c in ipairs(Pl.Subjects()) do
            if c.value:sub(1, #prefix) == prefix then
                choices[#choices + 1] = { value = c.value, label = c.label:gsub(" weapon enchant$", "") }
            end
        end
        fields[#fields + 1] = { key = "subject", value = value, label = label:gsub(" weapon enchant$", ""), choices = choices }
    end
    if Pl.HasOperator(cond) then
        local location = cond.type == "player" and PLAYER_LABEL[cond.state]
        local yes, no = location and "In" or "Is", location and "Outside" or "Is not"
        local binary = cond.type == "player" and not location and C().State(cond.state)
        if binary then
            yes, no = Upper1(binary[3]), Upper1(binary[4])
            if cond.state == "mounted" then yes, no = "Is mounted", "Is not mounted" end
            if cond.state == "combat" then yes, no = "In combat", "Out of combat" end
        end
        fields[#fields + 1] = { key = "op", value = cond.negate and "not" or "is", label = cond.negate and no or yes,
            choices = { { value = "is", label = yes }, { value = "not", label = no } } }
        if binary then return fields end
    end
    local key, choices = Pl.ValueKey(cond), Pl.ValueChoices(cond)
    if cond.type == "player" then
        local locations = {}
        for _, choice in ipairs(choices) do
            local name = PLAYER_LABEL[choice.value]
            if name then locations[#locations + 1] = { value = choice.value, label = name } end
        end
        choices = locations
    elseif cond.type == "weaponEnchant" then
        local words = { missing = "Is missing", applied = "Is applied", expiring = "Expiring" }
        for _, choice in ipairs(choices) do choice.label = words[choice.value] or choice.label end
    elseif cond.type == "wellFed" then
        for _, choice in ipairs(choices) do choice.label = choice.value == "missing" and "Not well fed" or "Well fed" end
    end
    local label
    for _, choice in ipairs(choices) do if choice.value == key then label = choice.label end end
    fields[#fields + 1] = { key = "value", value = key, label = label or Pl.ValueLabel(cond), choices = choices }
    if cond.type == "weaponEnchant" and cond.what == "expiring" then fields[#fields + 1] = EnchantAmount(cond) end
    return fields
end

function Pl.EditField(cond, key)
    for _, field in ipairs(Pl.CardFields(cond)) do if field.key == key then return field end end
end

function Pl.WithCardField(cond, field, value)
    for _, option in ipairs(field.choices) do
        if option.value == value then
            if field.set then return field.set(cond, value) end
            if field.key == "subject" then return Pl.WithSubject(cond, value) end
            if field.key == "op" then return Pl.WithNegate(cond, value == "not") end
            return Pl.WithValue(cond, value)
        end
    end
end

-- A line of help for the editor, about what the condition looks at.
function Pl.Help(cond)
    if type(cond) ~= "table" then return "" end
    if cond.type == "equipment" then
        if cond.what == "item" then return "A specific item, by its ID or link. It doesn't need to be carried: only whether it is equipped is checked." end
        return "Looks at what is in one equipment slot."
    elseif cond.type == "player" then
        return "Looks at your own state: in combat, dead, a ghost, mounted, resting, or inside a dungeon or a raid."
    elseif cond.type == "class" then
        return "Your own class. For several classes, add one of these for each, in a group where at least one must be true."
    elseif cond.type == "talent" then
        return "Uses the talent tree with the most spent points. Equal highest totals count as tied."
    elseif cond.type == "weaponEnchant" then
        local c = C().EnchantChoice(cond.what)
        return (c and c[4] or "Whether the weapon in this hand has a temporary enchant.") .. " The game says whether one is on, not which."
    elseif cond.type == "wellFed" then
        local c = C().WellFedChoice(cond.what)
        return (c and c[4] or "Whether you have a Well Fed buff.") .. " It can't be read while the game hides your buffs from addons."
    elseif cond.type == "ammunition" then
        local c = R.ReminderAmmo and R.ReminderAmmo.Choice(cond.what)
        return c and c[4] or "The ammunition for your ranged weapon."
    elseif cond.type == "aura" then
        local c = AU().Choice(cond.what)
        return (c and c[3] or "") .. " Each rank of a spell has an ID of its own: list every one that should count."
    elseif cond.type == "durability" then
        local c = SU().DurabilityChoice(cond.what)
        return c and c[3] or ""
    elseif cond.type == "cooldown" then
        local c = CH().CooldownChoice(cond.what)
        return c and c[3] or ""
    elseif cond.type == "power" then
        return "A share of the resource's maximum: exactly the number counts as \"at least\", never as \"below\". A character with none of it never matches."
    elseif cond.type == "itemCount" then
        return "Counts what is in your bags; the bank is never counted. Exactly the number counts as \"at least\", never as \"fewer than\"."
    elseif cond.type == "bagSpace" then
        return "Free slots in your general bags only: room in a quiver, soul bag or profession bag isn't counted."
    elseif MORE[cond.type] then
        return MORE[cond.type][3]
    end
    return ""
end

---------------------------------------------------------------------------
-- The rule as short lines
---------------------------------------------------------------------------
-- A run of conditions of one kind that a provider says in one phrase (several classes) comes out once.
local function MergedWords(p, match, conds)
    local ok, words, used = pcall(p.Merge, match, conds)
    if not (ok and type(words) == "string" and type(used) == "table" and #used >= 2) then return nil end
    return (words:gsub("^Player class ", "Your class ")), used
end

-- The items of one list, each { text = "..." } or { group = entry }, in order, a merged run at its first member.
local function Items(entries, match)
    local merged, skip, byProvider = {}, {}, {}
    for i, entry in ipairs(entries) do
        local p = entry.provider
        if not entry.group and p and p.Merge and entry.cond then
            local g = byProvider[p]
            if not g then g = { at = {}, conds = {} }; byProvider[p] = g end
            g.at[#g.at + 1] = i
            g.conds[#g.conds + 1] = entry.cond
        end
    end
    for p, g in pairs(byProvider) do
        local words, used = MergedWords(p, match, g.conds)
        if words then
            local first
            for _, u in ipairs(used) do
                local at = g.at[u]
                if at then
                    skip[at] = true
                    if not first or at < first then first = at end
                end
            end
            if first then merged[first], skip[first] = words, nil end
        end
    end
    local items = {}
    for i, entry in ipairs(entries) do
        if merged[i] then items[#items + 1] = { text = merged[i] }
        elseif not skip[i] then
            if entry.group then items[#items + 1] = { group = entry } else items[#items + 1] = { text = Pl.Sentence(entry) } end
        end
    end
    return items
end

local function Emit(lines, entries, match, depth, top)
    local items = Items(entries, match)
    local header = top and (match == "any" and "Shows when at least one of these is true:" or "Shows when all of these are true:")
        or (match == "any" and "At least one of these is true:" or "All of these are true:")
    lines[#lines + 1] = { text = header, depth = depth }
    for _, item in ipairs(items) do
        if item.text then
            lines[#lines + 1] = { text = item.text, depth = depth + 1, bullet = true }
        else
            local g = item.group
            local inner = Items(g.children, g.match)
            if #inner == 0 then
                lines[#lines + 1] = { text = "A group with nothing in it yet", depth = depth + 1, bullet = true }
            elseif #inner == 1 and inner[1].text then
                lines[#lines + 1] = { text = inner[1].text, depth = depth + 1, bullet = true }
            else
                Emit(lines, g.children, g.match, depth + 1, false)
            end
        end
    end
end

local cache = setmetatable({}, { __mode = "k" })   -- view -> lines (a view is made again after any change)

local function HasItemName(view)
    for _, e in ipairs(view.leaves) do
        if e.cond and e.cond.type == "equipment" and e.cond.what == "item" then return true end
    end
    return false
end

-- The rule as lines of { text, depth, bullet }. One condition is one line; several are a heading line and an indented
-- line for each, a group inside a group a heading of its own. Nothing is left out: a group with one thing says that one
-- thing, and a run of classes is said once.
function Pl.SummaryLines(view)
    local hit = cache[view]
    if hit then return hit end
    local lines = {}
    local entries, match = view.conditions, view.match
    if #entries == 0 then
        lines[1] = { text = "Nothing to check yet: add a condition, or it can never show.", depth = 0 }
    else
        -- a top level that is only one group reads as that group
        while #entries == 1 and entries[1].group do entries, match = entries[1].children, entries[1].match end
        local items = Items(entries, match)
        if #items == 0 then
            lines[1] = { text = "A group with nothing in it: it can't show until you add a condition or remove the group.", depth = 0 }
        elseif #items == 1 and items[1].text then
            lines[1] = { text = "Shows when: " .. items[1].text .. ".", depth = 0 }
        else
            Emit(lines, entries, match, 0, true)
        end
    end
    if not HasItemName(view) then cache[view] = lines end
    return lines
end

function Pl.RuleSummary(view)
    local function Lower(text) return (text:gsub("^%u", string.lower)) end
    local function Join(entries, match)
        local words = {}
        for _, item in ipairs(Items(entries, match)) do
            if item.group then
                words[#words + 1] = "(" .. Join(item.group.children, item.group.match) .. ")"
            else
                words[#words + 1] = Lower(item.text)
            end
        end
        return table.concat(words, match == "any" and " or " or " and ")
    end
    local entries = view.conditions
    if #entries == 0 then return "Add a condition to decide when this reminder appears." end
    for _, group in ipairs(view.groups) do
        if #group.children == 0 then return "Complete or remove the empty condition group." end
    end
    if Pl.Basic(view) and #entries > 1 then
        local restrictions = {}
        for i = 2, #entries do
            local words = Lower(Pl.Sentence(entries[i]))
            if entries[i].group and #entries > 2 then words = "(" .. words .. ")" end
            restrictions[#restrictions + 1] = words
        end
        return "Shows when " .. Lower(Pl.Sentence(entries[1])) .. ", but only while " .. table.concat(restrictions, " and ") .. "."
    end
    return "Shows when " .. Join(entries, view.match) .. "."
end

-- A group's contents in one line, for a group that is folded away: what it holds, nothing left out.
function Pl.GroupLine(entry)
    local items = Items(entry.children, entry.match)
    if #items == 0 then return "Nothing in it yet" end
    local parts = {}
    for i, item in ipairs(items) do
        parts[i] = item.text or ("a group (%s of %d)"):format(Pl.Words(item.group.match).short:lower(), #item.group.children)
    end
    return table.concat(parts, entry.match == "any" and "; or " or "; and ")
end

---------------------------------------------------------------------------
-- Who it is for
---------------------------------------------------------------------------
function Pl.Targeting(view, me)
    local s = view.scope
    local who
    if s.who == "characters" then
        local n = #s.characters
        local mine = false
        for _, c in ipairs(s.characters) do if c == me then mine = true end end
        if n == 0 then who = "No character chosen yet"
        elseif n == 1 and mine then who = "This character only"
        elseif n == 1 then who = "Only " .. s.characters[1]
        else who = ("%d chosen characters%s"):format(n, mine and ", this one included" or "") end
    else
        who = "Every character"
    end
    if s.class then who = who .. (", only for %ss"):format(RM().ClassName(s.class)) end
    return who
end

---------------------------------------------------------------------------
-- Why it would or would not show right now
---------------------------------------------------------------------------
local STATE_WORDS = { met = "Met", unmet = "Not met", unknown = "Cannot check yet", invalid = "Needs attention" }
Pl.STATE_WORDS = STATE_WORDS
local OF_RESULT = { match = "met", nomatch = "unmet", unknown = "unknown", invalid = "invalid" }

local STATUS_LINE = {
    showing = "It is showing on screen.",
    holding = "It is showing, kept up for its minimum time.",
    pending = "The conditions match; it is waiting out its delay before it shows.",
    hidden = "It is hidden.",
    disabled = "It is turned off, so nothing appears. Turn it on to use it.",
    off = "Reminders are turned off, so nothing appears.",
    world = "It decides once you are in the world.",
    waiting = "It is waiting for the game to give enough information.",
    notApplicable = "It is not for this character, so it stays hidden.",
    invalid = "It can't run until what needs attention is fixed.",
}

local function Label(entry)
    if entry.group then
        return "the group where " .. (entry.match == "any" and "at least one" or "all") .. " must be true"
    end
    return Pl.Sentence(entry)
end

local function Some(list)
    if #list == 0 then return "" end
    if #list == 1 then return list[1] end
    if #list == 2 then return list[1] .. " and " .. list[2] end
    return ("%s and %d more"):format(list[1], #list - 1)
end

-- One group's outcome in words, from the answers of what is in it. Every condition was read (none is skipped because
-- another settled the answer), so a result that doesn't change the outcome is said not to.
local function GroupLine(match, result, children, byRaw)
    if #children == 0 then return "It is empty: add a condition or remove the group." end
    local met, unmet, unknown, invalid = {}, {}, {}, {}
    for _, child in ipairs(children) do
        local node = byRaw[child.raw]
        local state = node and OF_RESULT[node.result] or "invalid"
        local list = state == "met" and met or (state == "unmet" and unmet or (state == "unknown" and unknown or invalid))
        list[#list + 1] = Label(child)
    end
    if result == E().INVALID then return "Something in it needs attention before it can be checked." end
    local aside = ""
    if match == "any" then
        if result == "match" then
            if #unknown > 0 then aside = " Something else can't be checked yet, which doesn't change the outcome." end
            return ("Met: %s.%s"):format(Some(met), aside)
        elseif result == "unknown" then
            return ("None is met so far. Cannot check yet: %s. So this can't be decided yet."):format(Some(unknown))
        end
        return "None of them is met."
    end
    if result == "match" then return "Every item is met." end
    if result == "unknown" then
        return ("Nothing is unmet. Cannot check yet: %s. So this can't be decided yet."):format(Some(unknown))
    end
    if #unknown > 0 then aside = " Something else can't be checked yet, which doesn't change the outcome." end
    return ("Not met: %s.%s"):format(Some(unmet), aside)
end

-- ctx is { character, class } as reminders/State.lua gives it (nil: read it here). Returns nil without a decision.
-- {
--   state  "show" | "match" | "hidden" | "unknown" | "invalid"
--   head   "Would show now" | "Conditions match now" | "Would stay hidden" | "Cannot determine"
--   reason a sentence (or nil), scope the scope's sentence, status the live status's sentence,
--   cards  [entry.raw] = { state ("met" | "unmet" | "unknown" | "invalid"), word, seen, detail, capability, long }
--   groups [entry.raw] = a sentence; groups.top for the top level's list
-- Answers are found by an entry's stored table, not the entry: a decision made before an unrelated change (a look, a
-- name) still describes the same conditions in the views made since.
-- }
function Pl.Explain(view, out, status, ctx)
    if not (view and out) then return nil end
    local Ev = E()
    local ex = { cards = {}, groups = {} }
    local ST = R.ReminderState
    ctx = ctx or (ST and ST.Context and ST.Context()) or {}
    local byRaw = {}
    for _, node in ipairs(out.nodes or {}) do
        if node.entry then byRaw[node.entry.raw] = node end
    end

    for raw, node in pairs(byRaw) do
        local entry = node.entry
        if entry.group then
            ex.groups[raw] = GroupLine(entry.match, node.result, entry.children, byRaw)
            local state = OF_RESULT[node.result] or "invalid"
            ex.cards[raw] = { state = state, word = STATE_WORDS[state] }
        else
            local state = OF_RESULT[node.result] or "invalid"
            local card = { state = state, word = STATE_WORDS[state] }
            if node.observed and node.observed ~= "" then card.seen = node.observed end
            if state == "unknown" then card.detail = node.reason end
            if state == "invalid" then
                local short, long = Pl.Capability(entry)
                if short then card.capability, card.long, card.detail = short, long, nil
                else card.detail = Pl.Problem(entry) end
                card.word = short and "Cannot check" or STATE_WORDS.invalid
            end
            ex.cards[raw] = card
        end
    end
    ex.groups.top = GroupLine(view.match, out.result, view.conditions, byRaw)

    local applies, whyApplies = Ev.Applies(view, ctx)
    ex.scope = applies == "match" and "This character is one it is for."
        or (whyApplies or "It may not be for this character.")
    ex.status = STATUS_LINE[status] or tostring(status or "")

    local result = out.result
    if result == Ev.INVALID or not view.valid then
        ex.state, ex.head = "invalid", "Cannot determine"
        ex.reason = view.problems and view.problems[1] and Upper1(view.problems[1]) or "Something in the rule needs attention first."
        -- a limit of this client says so in its own words
        for _, e in ipairs(view.leaves) do
            local short = Pl.Capability(e)
            if short then ex.reason = short break end
        end
    elseif applies == "nomatch" then
        ex.state, ex.head, ex.reason = "hidden", "Would stay hidden", whyApplies
    elseif applies == "unknown" or result == "unknown" then
        ex.state, ex.head = "unknown", "Cannot determine"
        ex.reason = applies == "unknown" and whyApplies or "The game hasn't given enough yet to check every condition."
    elseif result == "match" then
        if status == "showing" or status == "holding" then
            ex.state, ex.head = "show", "Would show now"
        else
            ex.state, ex.head = "match", "Conditions match now"
        end
    else
        ex.state, ex.head = "hidden", "Would stay hidden"
        ex.reason = "The conditions don't all hold right now."
    end
    return ex
end


-- Lossless presentation rows over the existing normalized tree. Headings retain the
-- conjunction at every level; only a flat All rule gets trigger/restriction language.
function Pl.Explanation(view)
    local rows = {}
    local function Add(text, entry, depth, heading)
        rows[#rows + 1] = { text = text, entry = entry, depth = depth or 0, heading = heading }
    end
    if Pl.Basic(view) and #view.conditions > 0 then
        Add("Show when", nil, 0, true)
        Add(Pl.Sentence(view.conditions[1]), view.conditions[1])
        if #view.conditions > 1 then Add("Only while · all must match", nil, 0, true) end
        for i = 2, #view.conditions do Add(Pl.Sentence(view.conditions[i]), view.conditions[i]) end
    else
        local function Walk(entries, match, depth)
            Add(match == "any" and "Any of these" or "All of these", nil, depth, true)
            if #entries == 0 then Add("Empty group · needs attention", nil, depth + 1) end
            for _, entry in ipairs(entries) do
                if entry.group then Walk(entry.children, entry.match, depth + 1)
                else Add(Pl.Sentence(entry), entry, depth + 1) end
            end
        end
        Walk(view.conditions, view.match, 0)
    end
    return rows
end

function Pl.DrawExplanation(parent, pool, view, width, y, compact)
    local G, M = R.SettingsWidgets, R.SettingsMaterial
    local start, data = y, Pl.Explanation(view)
    if compact and Pl.Basic(view) and #view.conditions <= 2 then
        data = { { text = Pl.RuleSummary(view), depth = 0, plain = true } }
    end
    for i, item in ipairs(data) do
        local row = pool[i]
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(22, 22); row.icon:SetPoint("TOPLEFT", 0, -1)
            row.text = M.ReminderFont(G.Text(row, "body"), 13)
            pool[i] = row
        end
        local inset = math.min(4, item.depth) * 12
        row:SetWidth(width - inset)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -y)
        row.text:ClearAllPoints(); row.text:SetPoint("TOPLEFT", (item.heading or item.plain) and 0 or 29, -2)
        row.text:SetWidth(width - inset - ((item.heading or item.plain) and 0 or 29))
        row.text:SetText(item.text)
        M.ReminderFont(row.text, item.heading and 13 or 14, item.heading)
        G.Color(row.text, item.heading and G.pal.textDim or G.pal.text)
        row.icon:SetShown(not item.heading and not item.plain and item.entry ~= nil)
        if item.entry then
            local cond = item.entry.cond or (item.entry.children and item.entry.children[1] and item.entry.children[1].cond)
            Pl.ApplyArt(row.icon, cond, 22)
        end
        local h = math.max(item.heading and 19 or 27, (row.text:GetStringHeight() or 14) + 7)
        row:SetHeight(h); row:Show(); y = y + h + (item.heading and 2 or 4)
    end
    for i = #data + 1, #pool do pool[i]:Hide() end
    return y - start
end
