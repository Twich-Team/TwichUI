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
Pl.CATEGORIES = { "Combat", "Character", "Equipment", "Other" }

-- an icon (R.Icons id) for a kind of condition, drawn small beside it
local ICON = { equipment = "gearComparison", ammunition = "ammunition", class = "profiles", talent = "profiles" }
local PLAYER_ICON = { combat = "hazardAlerts", dead = "resurrection", ghost = "resurrection", mounted = "navigation" }
function Pl.Icon(cond)
    if type(cond) ~= "table" then return "reminderTest" end
    if cond.type == "player" then return PLAYER_ICON[cond.state] or "reminderTest" end
    return ICON[cond.type] or "reminderTest"
end

local PLAYER_BLURB = {
    combat = "Whether you are in combat.",
    dead = "Whether you are dead or a ghost (after releasing your spirit you stay dead until you are back in your body).",
    ghost = "Whether you are a ghost: your spirit has been released.",
    mounted = "Whether you are on a mount.",
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
                out[#out + 1] = { key = "player:" .. st[1], kind = "player", category = st[1] == "combat" and "Combat" or "Character",
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
        elseif p.type == "ammunition" then
            local A = R.ReminderAmmo
            out[#out + 1] = { key = "ammunition", kind = "ammunition", category = "Equipment", name = "Your ranged ammunition",
                blurb = "The ammunition for your ranged weapon: none selected, used up or the wrong kind. It never matches for a weapon that takes none.",
                icon = Pl.Icon({ type = "ammunition" }), make = function() return p.New() end,
                note = (A and not A.Supported()) and "This client doesn't say whether a weapon takes ammunition, so a reminder using it can't be turned on here." or nil }
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
    return (entry.name:lower():find(query, 1, true) or entry.blurb:lower():find(query, 1, true)
        or entry.category:lower():find(query, 1, true)) ~= nil
end

---------------------------------------------------------------------------
-- The editor's fields: which a condition has, and how a change makes a new condition (never edits the one it is given)
---------------------------------------------------------------------------
function Pl.Subjects()
    local CT = C()
    local out = {}
    for _, slot in ipairs(CT.SLOTS) do out[#out + 1] = { value = "slot:" .. slot[1], label = slot[3] } end
    out[#out + 1] = { value = "ammo", label = "Ranged ammunition" }
    out[#out + 1] = { value = "player", label = "You (the player)" }
    out[#out + 1] = { value = "class", label = "Player class" }
    out[#out + 1] = { value = "talent", label = "Talent specialization" }
    return out
end

-- the subject choice that makes a condition of a kind of its own (the others are equipment slots)
local SUBJECT_KIND = { player = "player", ammo = "ammunition", class = "class", talent = "talent" }

function Pl.SubjectOf(cond)
    if type(cond) ~= "table" then return nil, "?" end
    local CT = C()
    if cond.type == "equipment" then
        local s = CT.Slot(cond.slot)
        return "slot:" .. tostring(cond.slot), s and s[3] or tostring(cond.slot)
    elseif cond.type == "player" then
        return "player", "You (the player)"
    elseif cond.type == "ammunition" then
        return "ammo", "Ranged ammunition"
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
    if cond.type == "equipment" then
        for _, c in ipairs(CT.SlotChoices(cond.slot)) do out[#out + 1] = { value = c[1], label = c[2] } end
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
    return cond.what or cond.state or cond.class
end

function Pl.ValueLabel(cond)
    if cond.type == "class" and not cond.class then return "Choose a class" end
    if cond.type == "talent" and not Pl.ValueKey(cond) then return "Choose a specialization" end
    local key = Pl.ValueKey(cond)
    for _, c in ipairs(Pl.ValueChoices(cond)) do if c.value == key then return c.label end end
    return tostring(key)
end

-- Whether the operator ("is" / "is not") is a choice for this condition (ammunition reads as a sentence on its own).
function Pl.HasOperator(cond) return type(cond) == "table" and cond.type ~= "ammunition" end
-- Whether the condition names a specific item (the editor then asks for it).
function Pl.NeedsItem(cond) return type(cond) == "table" and cond.type == "equipment" and cond.what == "item" end

-- A new condition: the subject chosen (keeping "is not", the item and a value that still fits).
function Pl.WithSubject(cond, value)
    local CT = C()
    local kind = SUBJECT_KIND[value]
    if kind then
        if type(cond) == "table" and cond.type == kind then return RM().DeepCopy(cond) end
        return CT.Get(kind).New()
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
    else new.what = value end
    return new
end

function Pl.WithItem(cond, id)
    local new = RM().DeepCopy(cond)
    new.item = id
    return new
end

-- A line of help for the editor, about what the condition looks at.
function Pl.Help(cond)
    if type(cond) ~= "table" then return "" end
    if cond.type == "equipment" then
        if cond.what == "item" then return "A specific item, by its ID or link. It doesn't need to be carried: only whether it is equipped is checked." end
        return "Looks at what is in one equipment slot."
    elseif cond.type == "player" then
        return "Looks at your own state: in combat, dead, a ghost or mounted."
    elseif cond.type == "class" then
        return "Your own class. For several classes, add one of these for each, in a group where at least one must be true."
    elseif cond.type == "talent" then
        return "Uses the talent tree with the most spent points. Equal highest totals count as tied."
    elseif cond.type == "ammunition" then
        local c = R.ReminderAmmo and R.ReminderAmmo.Choice(cond.what)
        return c and c[4] or "The ammunition for your ranged weapon."
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
