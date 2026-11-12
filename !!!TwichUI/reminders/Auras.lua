-- TwichUI: Reminders, buffs and debuffs on you
-- A condition kind (Conditions.lua says what a provider is) about an aura on the player, and the source that reads them
-- (State.lua says what a source is). Self only: no other unit's auras are read.
--
-- Identity: the aura's spell IDs, chosen by the player, never its name. Each rank of a spell has an ID of its own on
-- this client (C_SpellBook items carry a "Rank 3" subtext), so a condition holds a short list of IDs (up to MAX_SPELLS),
-- any of which counts; nothing is added to it by guessing from a name.
--
-- What it asks (`what`):
--   present   one of the auras is on you
--   missing   none of them is on you
--   expiring  one is on you and the longest-lasting of them has less than `seconds` left; exactly `seconds` left is not
--             yet "less than". An aura that never runs out (duration 0) never matches. Not on you: no match (that is
--             "missing", a choice of its own: put both in a group where at least one must be true for either).
--   stacks    one is on you and its stack count (the most of them) is below / at least `stacks` (`compare`). An aura
--             that doesn't stack counts as one stack. Not on you: no match.
-- Unknown, never "not there": the auras can't be read (hidden from addons, as in some fights; an aura whose spell ID
-- isn't given plainly; more than MAX_AURAS of them), or for expiring, a time that isn't given.
--
-- The observation obs.aura = { HELPFUL = set, HARMFUL = set }, each set nil (unknown) or { [spellID] = { ends, stacks } }:
-- ends a GetTime value, false for one that never runs out, nil when not given; stacks a number or nil. Read with
-- C_UnitAuras.GetAuraDataByIndex("player", i, filter) (called protected, as reminders' Well Fed and buffback/Watch.lua
-- do), after C_Secrets.ShouldAurasBeSecret; UNIT_AURA for the player only. Every update reads again, a timer refresh
-- too: renewing a buff moves its end. Only the lists a running reminder asks about are read.

local R = TwichUI
local C = R.ReminderConditions
local ST = R.ReminderState

local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN
local Yes = C.Yes

local AU = {}
R.ReminderAuras = AU
AU.MAX_SPELLS = 8
AU.MAX_AURAS = 40
AU.SECONDS = { 10, 30, 60, 120, 300, 600 }   -- the editor's quick choices
AU.SECONDS_MAX = 36000
AU.SECONDS_DEFAULT = 60
AU.STACKS = { 2, 3, 5, 10 }
AU.STACKS_MAX = 255
AU.STACKS_DEFAULT = 3

-- key (stored), the editor's label, a tooltip
AU.CHOICES = {
    { "present", "Is on you", "One of the chosen auras is on you." },
    { "missing", "Is missing", "None of the chosen auras is on you." },
    { "expiring", "Expiring", "One is on you with less than the time you choose left. Not on you at all is \"Is missing\": put both in a group where at least one must be true to be reminded either way." },
    { "stacks", "Stack count", "One is on you with a stack count below, or at least, the number you choose. An aura that doesn't stack counts as one." },
}
local CHOICE = {}
for _, c in ipairs(AU.CHOICES) do CHOICE[c[1]] = c end
function AU.Choice(key) return CHOICE[key] end

local function FilterOf(cond) return cond.harmful and "HARMFUL" or "HELPFUL" end

-- A clean list of spell IDs, or nil and why.
function AU.CleanSpells(raw)
    if raw == nil then return {} end
    if type(raw) ~= "table" then return nil, "its list of buffs can't be read." end
    local out, seen = {}, {}
    for i, id in ipairs(raw) do
        if i > AU.MAX_SPELLS then return nil, ("it names more than %d spells."):format(AU.MAX_SPELLS) end
        if not C.ValidSpell(id) then return nil, "it names a spell by something that isn't a spell ID." end
        if not seen[id] then seen[id] = true; out[#out + 1] = id end
    end
    return out
end

-- "Arcane Intellect", "Arcane Intellect or Mark of the Wild", "Arcane Intellect or 2 others"
function AU.Names(spells)
    local names, seen = {}, {}
    for _, id in ipairs(spells or {}) do
        local n = C.SpellWords(id)
        if not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    if #names == 0 then return nil end
    if #names == 1 then return names[1] end
    if #names == 2 then return names[1] .. " or " .. names[2] end
    return ("%s or %d others"):format(names[1], #names - 1)
end

-- What the chosen auras amount to in one list: nil (unknown) or { present, ends (GetTime, math.huge for never, nil not
-- given), stacks }. Of several instances, the one lasting longest and the most stacks count.
local function Look(cond, obs)
    local lists = obs and obs.aura
    local set = type(lists) == "table" and lists[FilterOf(cond)] or nil
    if type(set) ~= "table" then return nil end
    local present, ends, stacks, unknownEnds = false, nil, nil, false
    for _, id in ipairs(cond.spells) do
        local a = set[id]
        if type(a) == "table" then
            present = true
            local e = a.ends == false and math.huge or a.ends
            if type(e) == "number" then
                if not ends or e > ends then ends = e end
            else
                unknownEnds = true
            end
            local n = type(a.stacks) == "number" and math.max(1, a.stacks) or nil
            if n and (not stacks or n > stacks) then stacks = n end
        end
    end
    return { present = present, ends = ends, stacks = stacks, unknownEnds = unknownEnds }
end

local function Left(look, obs)
    if not (look.ends and type(obs.now) == "number") then return nil end
    return look.ends - obs.now
end

C.Register({
    type = "aura", label = "Buff or debuff on you",
    Supported = function() return C_UnitAuras ~= nil and C_UnitAuras.GetAuraDataByIndex ~= nil end,
    unsupported = "this game client doesn't let addons list the auras on you.",
    New = function() return { type = "aura", spells = {}, harmful = false, what = "missing" } end,

    Check = function(raw)
        if not CHOICE[raw.what] then return nil, "it asks about a buff in a way this version of TwichUI doesn't know." end
        local spells, why = AU.CleanSpells(raw.spells)
        if not spells then return nil, why end
        if raw.harmful ~= nil and type(raw.harmful) ~= "boolean" then return nil, "it can't say whether it looks for a buff or a debuff." end
        local clean = { type = "aura", spells = spells, harmful = raw.harmful == true, what = raw.what }
        if raw.what == "expiring" then
            clean.seconds = C.Whole(raw.seconds, 1, AU.SECONDS_MAX)
            if not clean.seconds then return clean, ("choose how little time left counts as running out (1 to %d seconds)."):format(AU.SECONDS_MAX) end
        elseif raw.what == "stacks" then
            clean.compare = C.ValidCompare(raw.compare) and raw.compare or "atLeast"
            clean.stacks = C.Whole(raw.stacks, 1, AU.STACKS_MAX)
            if not clean.stacks then return clean, ("choose the stack count it compares with (1 to %d)."):format(AU.STACKS_MAX) end
        end
        if #spells == 0 then return clean, ("choose the %s it looks for (drag it from your spellbook, or type its spell ID or paste its link)."):format(clean.harmful and "debuff" or "buff") end
        return clean
    end,

    Needs = function(cond, add) add("aura:" .. FilterOf(cond)) end,

    Evaluate = function(cond, obs)
        local look = Look(cond, obs)
        if not look then return UNKNOWN, "The game hasn't said which auras are on you, or they can't be read right now." end
        if cond.what == "present" then return Yes(look.present) end
        if cond.what == "missing" then return Yes(not look.present) end
        if not look.present then return NOMATCH end
        if cond.what == "stacks" then
            if not look.stacks then return UNKNOWN, "The game hasn't said how many stacks it has." end
            return Yes(C.Compare(look.stacks, cond.compare, cond.stacks))
        end
        -- expiring: one known to last long enough settles it, whatever the others say
        local left = Left(look, obs)
        if left and left >= cond.seconds then return NOMATCH end
        if look.unknownEnds or left == nil then return UNKNOWN, "The game hasn't said how long it has left." end
        return Yes(left < cond.seconds)
    end,

    NextChange = function(cond, obs)
        if cond.what ~= "expiring" then return nil end
        local look = Look(cond, obs)
        if not (look and look.present) then return nil end
        local left = Left(look, obs)
        if not left or left == math.huge or left <= 0 then return nil end
        if left >= cond.seconds then return left - cond.seconds end
        return left
    end,

    Summary = function(cond)
        local names = AU.Names(cond.spells) or (cond.harmful and "(no debuff chosen)" or "(no buff chosen)")
        local w = cond.what
        if w == "present" then return ("%s is on you"):format(names) end
        if w == "missing" then return ("%s is not on you"):format(names) end
        if w == "expiring" then return ("%s has less than %s left on you"):format(names, cond.seconds and C.Duration(cond.seconds) or "?") end
        return ("%s has %s %s stacks on you"):format(names, cond.compare == "below" and "fewer than" or "at least", tostring(cond.stacks or "?"))
    end,

    Observed = function(cond, obs)
        local look = Look(cond, obs)
        if not look then return "Not read yet" end
        if not look.present then return "Not on you" end
        local parts = {}
        local left = Left(look, obs)
        if look.ends == math.huge then parts[#parts + 1] = "doesn't run out"
        elseif left and left > 0 then parts[#parts + 1] = C.Duration(math.floor(left)) .. " left" end
        if look.stacks and look.stacks > 1 then parts[#parts + 1] = look.stacks .. " stacks" end
        if #parts == 0 then return "On you" end
        return "On you (" .. table.concat(parts, ", ") .. ")"
    end,

    -- What it looks for first; the made-up aura is the first spell chosen (a stand-in when none is chosen yet).
    Scenarios = function(cond)
        local filter, id = FilterOf(cond), cond.spells[1] or 0
        local list = {}
        local function Put(key, label, aura)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                obs.aura = obs.aura or {}
                if aura == "unread" then obs.aura[filter] = nil return end
                local set = obs.aura[filter] or {}
                obs.aura[filter] = set
                for _, other in ipairs(cond.spells) do set[other] = nil end
                set[id] = nil
                if aura then
                    local ends
                    if aura.left == false then ends = false else ends = (obs.now or 0) + aura.left end
                    set[id] = { ends = ends, stacks = aura.stacks }
                end
            end }
        end
        local w = cond.what
        if w == "expiring" then
            local s = cond.seconds or AU.SECONDS_DEFAULT
            local soon = math.max(1, math.floor(s / 2))
            Put("soon", ("On you, %s left"):format(C.Duration(soon)), { left = soon, stacks = 0 })
            Put("plenty", ("On you, %s left"):format(C.Duration(s * 3)), { left = s * 3, stacks = 0 })
            Put("forever", "On you, never runs out", { left = false, stacks = 0 })
            Put("absent", "Not on you", nil)
        elseif w == "stacks" then
            local n = cond.stacks or AU.STACKS_DEFAULT
            Put("more", ("On you, %d stacks"):format(n + 1), { left = 600, stacks = n + 1 })
            Put("exact", ("On you, %d stacks"):format(n), { left = 600, stacks = n })
            if n > 1 then Put("fewer", ("On you, %d stacks"):format(n - 1), { left = 600, stacks = n - 1 }) end
            Put("absent", "Not on you", nil)
        elseif w == "present" then
            Put("on", "On you", { left = 600, stacks = 0 })
            Put("absent", "Not on you", nil)
        else
            Put("absent", "Not on you", nil)
            Put("on", "On you", { left = 600, stacks = 0 })
        end
        Put("unread", "Auras can't be read", "unread")
        return list
    end,
})

---------------------------------------------------------------------------
-- The source: obs.aura[filter]
---------------------------------------------------------------------------
local Plain, Number = ST.Plain, ST.Number

-- One list of auras on the player as a set, or nil when it can't be read (see the header).
local function ReadList(filter)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return nil end
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and Plain(C_Secrets.ShouldAurasBeSecret()) == true then return nil end
    local set = {}
    for i = 1, AU.MAX_AURAS do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, filter)
        if not ok then return nil end
        if aura == nil then return set end
        if type(aura) ~= "table" or (issecretvalue and issecretvalue(aura)) then return nil end
        local id = Number(aura.spellId)
        if not id then return nil end   -- one we can't name could be the one asked about
        local expires, duration = Number(aura.expirationTime), Number(aura.duration)
        local ends
        if duration == 0 or expires == 0 then ends = false            -- the game's own buff frame: never runs out
        elseif expires and expires > 0 then ends = expires end
        local stacks = Number(aura.applications)
        local old = set[id]
        if not old then
            set[id] = { ends = ends, stacks = stacks }
        else   -- the same spell twice: the longest-lasting and the most stacks
            if ends == false or (type(ends) == "number" and type(old.ends) == "number" and ends > old.ends) then old.ends = ends end
            if old.ends == nil then old.ends = ends end
            if stacks and (not old.stacks or stacks > old.stacks) then old.stacks = stacks end
        end
    end
    return nil   -- more than are looked at: an answer of "not there" would be a guess
end

local function Same(a, b)
    if a == nil or b == nil then return a == b end
    for id, x in pairs(a) do
        local y = b[id]
        if not y or y.ends ~= x.ends or y.stacks ~= x.stacks then return false end
    end
    for id in pairs(b) do if not a[id] then return false end end
    return true
end

ST.Source("aura", {
    events = {
        UNIT_AURA = function(unit)
            if issecretvalue and issecretvalue(unit) then return true end
            if unit == "player" then return true end
        end,
    },
    units = { UNIT_AURA = "player" },
    Read = function(filter, into)
        if filter ~= "HELPFUL" and filter ~= "HARMFUL" then return false end
        ST.Counted()
        into.aura = into.aura or {}
        local set = ReadList(filter)
        if Same(set, into.aura[filter]) then return false end
        into.aura[filter] = set
        return true
    end,
    Forget = function(filter, into)
        if into.aura then into.aura[filter] = nil end
    end,
})
