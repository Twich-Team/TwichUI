-- TwichUI: Reminders, your resources, spells, form and level
-- Condition kinds (Conditions.lua says what a provider is) and their sources (State.lua says what a source is). Every
-- spell and form is named by the game's spell ID, never by a translated name; nothing here casts, cancels or uses
-- anything.
--
-- power      `power` (a resource named outright: "MANA", "RAGE" or "ENERGY", Enum.PowerType 0, 1, 3), `compare`, `percent`.
--            UnitPower / UnitPowerMax for that resource itself, never "whatever the character shows now" (a druid in
--            bear form still has mana). Documented as SecretWhenUnitPowerRestricted: a value that comes back secret is
--            unknown, never compared. A character with no such pool (a maximum of 0: a warrior's mana) never matches
--            either way; it is not "0%". Read on UNIT_POWER_UPDATE / UNIT_MAXPOWER for that resource and
--            UNIT_DISPLAYPOWER, the player only. Health is not offered: UnitHealth is documented SecretReturns (always
--            secret to an addon), so it could never be compared.
-- spellKnown `spell`, `negate`. C_SpellBook.IsSpellKnown, IsPlayerSpell or IsSpellKnown (the same reading as glows/State.lua,
--            without its match by name). A spell ID the game says doesn't exist (C_Spell.DoesSpellExist) is unknown, so a
--            mistyped ID never satisfies "you don't know it". Read on SPELLS_CHANGED.
-- form       `form` (the form's spell ID, as GetShapeshiftFormInfo gives it) or `state` = "none" (no form or stance),
--            `negate`. GetShapeshiftForm: 0 is no form; otherwise the active form's spell ID. Forms of another class are
--            never mapped to this one's: a stored form this character can't take is simply not the one it is in. Read on
--            UPDATE_SHAPESHIFT_FORM(S).
-- level      `compare`, `level`. UnitLevel("player"), and the level PLAYER_LEVEL_UP carries (UnitLevel can still answer
--            the old level inside that event). No level cap is assumed.
-- cooldown   `spell`, `what` ("ready" | "cooling" | "within" with `seconds`). C_Spell.GetSpellCooldown: isActive and isOnGCD
--            are documented NeverSecret, start and duration may be secret. The global cooldown is not a cooldown (ready).
--            A spell you don't know is neither ready nor cooling (no match either way); a cooldown on hold (isEnabled
--            false) is cooling with no known end. "within" is ready, or ready in less than `seconds`; an end that isn't
--            given plainly is unknown. Read on SPELL_UPDATE_COOLDOWN and SPELLS_CHANGED; its end is a time boundary
--            (NextChange), so no polling.

local R = TwichUI
local C = R.ReminderConditions
local ST = R.ReminderState

local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN
local Yes, Negate = C.Yes, C.Negate
local Plain, Number, Set = ST.Plain, ST.Number, ST.Set

local CH = {}
R.ReminderCharacter = CH
CH.PERCENTS = { 10, 20, 30, 50, 80, 100 }
CH.LEVELS = { 10, 20, 30, 40, 50, 60 }
CH.LEVEL_MAX = 999
CH.COOLDOWN_SECONDS = { 5, 10, 30, 60 }
CH.COOLDOWN_SECONDS_MAX = 3600

---------------------------------------------------------------------------
-- Resources
---------------------------------------------------------------------------
local PT = rawget(_G, "Enum") and Enum.PowerType or {}
-- token (stored), Enum.PowerType value, label
CH.POWERS = {
    { "MANA", PT.Mana or 0, "Mana" },
    { "RAGE", PT.Rage or 1, "Rage" },
    { "ENERGY", PT.Energy or 3, "Energy" },
}
local POWER = {}
for _, p in ipairs(CH.POWERS) do POWER[p[1]] = p end
function CH.Power(token) return POWER[token] end

local function PowerFacts(cond, obs)
    local t = obs and obs.power
    return type(t) == "table" and t[cond.power] or nil
end

C.Register({
    type = "power", label = "Your mana, rage or energy",
    Supported = function() return rawget(_G, "UnitPower") ~= nil and rawget(_G, "UnitPowerMax") ~= nil end,
    unsupported = "this game client doesn't say how much mana, rage or energy you have.",
    New = function() return { type = "power", power = "MANA", compare = "below", percent = 30 } end,

    Check = function(raw)
        if not POWER[raw.power] then return nil, "it names a resource this version of TwichUI doesn't know." end
        if not C.ValidCompare(raw.compare) then return nil, "it compares a resource in a way this version of TwichUI doesn't know." end
        local clean = { type = "power", power = raw.power, compare = raw.compare, percent = C.Whole(raw.percent, 1, 100) }
        if not clean.percent then return clean, "choose the share it compares with (1 to 100 percent)." end
        return clean
    end,

    Needs = function(cond, add) add("power:" .. cond.power) end,

    Evaluate = function(cond, obs)
        local f = PowerFacts(cond, obs)
        if f == nil then return UNKNOWN, "The game hasn't said, or doesn't let addons read it right now." end
        if f == "none" then return NOMATCH end
        if cond.compare == "below" then return Yes(f.cur * 100 < cond.percent * f.max) end
        return Yes(f.cur * 100 >= cond.percent * f.max)
    end,

    Summary = function(cond)
        local p = POWER[cond.power]
        return ("Your %s is %s %d%%"):format(p and p[3]:lower() or "resource", cond.compare == "below" and "below" or "at least", cond.percent or 0)
    end,

    Observed = function(cond, obs)
        local f = PowerFacts(cond, obs)
        local p = POWER[cond.power]
        if f == nil then return "Not read yet" end
        if f == "none" then return ("You have no %s"):format(p and p[3]:lower() or "such resource") end
        return ("%d%% (%d of %d)"):format(math.floor(f.cur * 100 / f.max), f.cur, f.max)
    end,

    Scenarios = function(cond)
        local pct = cond.percent or 30
        local list = {}
        local function Put(key, label, facts)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                obs.power = obs.power or {}
                obs.power[cond.power] = facts
            end }
        end
        local low, high = math.max(0, pct - 10), math.min(100, pct + 20)
        local first, second = { "low", low .. "%", { cur = low, max = 100 } }, { "high", high .. "%", { cur = high, max = 100 } }
        if cond.compare ~= "below" then first, second = second, first end
        Put(first[1], first[2], first[3])
        Put(second[1], second[2], second[3])
        Put("exact", pct .. "% exactly", { cur = pct, max = 100 })
        Put("none", "No such resource", "none")
        Put("unread", "Can't be read", nil)
        return list
    end,
})

local function ReadPower(token, into)
    local p = POWER[token]
    if not (p and UnitPower and UnitPowerMax) then return nil end
    local cur, max = UnitPower("player", p[2]), UnitPowerMax("player", p[2])
    if (issecretvalue and (issecretvalue(cur) or issecretvalue(max))) then return nil end
    cur, max = Number(cur), Number(max)
    if not (cur and max) then return nil end
    if max <= 0 then return "none" end
    return { cur = math.max(0, math.min(cur, max)), max = max }
end

local function PowerEvent(unit, token)
    if issecretvalue and (issecretvalue(unit) or issecretvalue(token)) then return true end
    if unit ~= "player" then return nil end
    if type(token) == "string" and POWER[token] then return token end
    return nil
end

ST.Source("power", {
    events = {
        UNIT_POWER_UPDATE = PowerEvent, UNIT_MAXPOWER = PowerEvent,
        UNIT_DISPLAYPOWER = function(unit) if unit == "player" or (issecretvalue and issecretvalue(unit)) then return true end end,
    },
    units = { UNIT_POWER_UPDATE = "player", UNIT_MAXPOWER = "player", UNIT_DISPLAYPOWER = "player" },
    Read = function(token, into)
        if not POWER[token] then return false end
        ST.Counted()
        into.power = into.power or {}
        local v, old = ReadPower(token, into), into.power[token]
        if type(v) == "table" and type(old) == "table" and v.cur == old.cur and v.max == old.max then return false end
        if v == old then return false end
        into.power[token] = v
        return true
    end,
    Forget = function(token, into) if into.power then into.power[token] = nil end end,
})

---------------------------------------------------------------------------
-- Knowing a spell
---------------------------------------------------------------------------
local function Known(id)
    local seen = false
    local SB = C_SpellBook
    for _, fn in ipairs({ SB and SB.IsSpellKnown, rawget(_G, "IsPlayerSpell"), rawget(_G, "IsSpellKnown") }) do
        if fn then
            local ok, v = pcall(fn, id)
            if ok then v = Plain(v) else v = nil end   -- (not "ok and Plain(v) or nil": that loses a false)
            if v == true then return true end
            if v == false then seen = true end
        end
    end
    if seen then return false end
    return nil
end

local function Exists(id)
    if not (C_Spell and C_Spell.DoesSpellExist) then return true end
    local ok, v = pcall(C_Spell.DoesSpellExist, id)
    if not ok then return true end   -- can't say: never called a mistake
    return Plain(v) ~= false
end

local function KnownFact(cond, obs)
    local t = obs and obs.spellKnown
    if type(t) ~= "table" or not cond.spell then return nil end
    return t[cond.spell]   -- false ("not known") stays false
end

C.Register({
    type = "spellKnown", label = "A spell you know",
    Supported = function() return (C_SpellBook ~= nil and C_SpellBook.IsSpellKnown ~= nil) or rawget(_G, "IsPlayerSpell") ~= nil or rawget(_G, "IsSpellKnown") ~= nil end,
    unsupported = "this game client doesn't say which spells you know.",
    New = function() return { type = "spellKnown", negate = false } end,

    Check = function(raw)
        local clean = { type = "spellKnown", negate = raw.negate == true }
        if raw.spell == nil then return clean, "choose the spell it looks for (its spell ID or link)." end
        if not C.ValidSpell(raw.spell) then return nil, "it names a spell by something that isn't a spell ID." end
        clean.spell = raw.spell
        return clean
    end,

    Needs = function(cond, add) if cond.spell then add("spellKnown:" .. cond.spell) end end,

    Evaluate = function(cond, obs)
        local v = KnownFact(cond, obs)
        if v == nil then return UNKNOWN, "The game hasn't said which spells you know yet." end
        if v == "invalid" then return UNKNOWN, "The game has no spell with this ID." end
        return Negate(Yes(v == true), cond.negate)
    end,

    Summary = function(cond)
        return ("You %s %s"):format(cond.negate and "don't know" or "know", C.SpellWords(cond.spell))
    end,

    Observed = function(cond, obs)
        local v = KnownFact(cond, obs)
        if v == nil then return "Not read yet" end
        if v == "invalid" then return "No such spell" end
        return v and "Known" or "Not known"
    end,

    Scenarios = function(cond)
        local list = {}
        local function Put(key, label, value)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                obs.spellKnown = obs.spellKnown or {}
                obs.spellKnown[cond.spell or 0] = value
            end }
        end
        if cond.negate then Put("unknown", "Not known", false); Put("known", "Known", true)
        else Put("known", "Known", true); Put("unknown", "Not known", false) end
        Put("invalid", "No such spell", "invalid")
        Put("unread", "Not read yet", nil)
        return list
    end,
})

ST.Source("spellKnown", {
    events = { SPELLS_CHANGED = true },
    Read = function(arg, into)
        local id = tonumber(arg)
        if not id then return false end
        ST.Counted()
        local v
        if not Exists(id) then v = "invalid" else v = Known(id) end
        into.spellKnown = into.spellKnown or {}
        if into.spellKnown[id] == v then return false end
        into.spellKnown[id] = v
        return true
    end,
    Forget = function(arg, into) if into.spellKnown then into.spellKnown[tonumber(arg) or 0] = nil end end,
})

---------------------------------------------------------------------------
-- Form, stance or presence
---------------------------------------------------------------------------
CH.FORM_NONE = "none"

-- The forms this character has now, for the editor: { { spellID, name }, ... } in the game's own order. Empty when the
-- game lists none (or can't say).
function CH.FormChoices()
    local out = {}
    if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return out end
    local n = Number(GetNumShapeshiftForms()) or 0
    for i = 1, math.min(n, 10) do
        local id = Number(select(4, GetShapeshiftFormInfo(i)))
        if id then out[#out + 1] = { id, C.SpellWords(id) } end
    end
    return out
end

local function FormKey(cond) return cond.state or cond.form end

C.Register({
    type = "form", label = "Your form or stance",
    Supported = function() return rawget(_G, "GetShapeshiftForm") ~= nil end,
    unsupported = "this game client doesn't say which form or stance you are in.",
    New = function()
        local first = CH.FormChoices()[1]
        return { type = "form", form = first and first[1] or nil, state = (not first) and CH.FORM_NONE or nil, negate = false }
    end,

    Check = function(raw)
        local clean = { type = "form", negate = raw.negate == true }
        if raw.state ~= nil then
            if raw.state ~= CH.FORM_NONE or raw.form ~= nil then return nil, "it names a form this version of TwichUI doesn't know." end
            clean.state = raw.state
            return clean
        end
        if raw.form == nil then return clean, "choose the form or stance it looks for." end
        if not C.ValidSpell(raw.form) then return nil, "it names a form by something that isn't a spell ID." end
        clean.form = raw.form
        return clean
    end,

    Needs = function(_, add) add("form") end,

    Evaluate = function(cond, obs)
        local v = obs and obs.form
        if v == nil then return UNKNOWN, "The game hasn't said which form you are in yet." end
        return Negate(Yes(v == FormKey(cond)), cond.negate)
    end,

    Summary = function(cond)
        if cond.state == CH.FORM_NONE then return cond.negate and "You are in a form or stance" or "You are in no form or stance" end
        return ("You are %sin %s"):format(cond.negate and "not " or "", cond.form and C.SpellWords(cond.form) or "(no form chosen)")
    end,

    Observed = function(_, obs)
        local v = obs and obs.form
        if v == nil then return "Not read yet" end
        if v == CH.FORM_NONE then return "No form or stance" end
        return C.SpellWords(v)
    end,

    Subject = function() return "form", "Form or stance" end,

    -- the character's own forms, then the chosen one if it isn't among them (another class's, or offline), no form and
    -- nothing read. Shared by every form condition in a rule (Subject), so one made-up form is in force for all of them.
    Scenarios = function(cond)
        local list, seen = {}, {}
        local function Put(key, label, value)
            if seen[key] then return end
            seen[key] = true
            list[#list + 1] = { key = tostring(key), label = label, Apply = function(obs) obs.form = value end }
        end
        for _, f in ipairs(CH.FormChoices()) do Put(f[1], f[2], f[1]) end
        if cond.form then Put(cond.form, C.SpellWords(cond.form), cond.form) end
        Put(CH.FORM_NONE, "No form or stance", CH.FORM_NONE)
        list[#list + 1] = { key = "unread", label = "Not read yet", Apply = function(obs) obs.form = nil end }
        return list
    end,
})

ST.Source("form", {
    events = { UPDATE_SHAPESHIFT_FORM = true, UPDATE_SHAPESHIFT_FORMS = true },
    Read = function(_, into)
        ST.Counted()
        local v
        if GetShapeshiftForm then
            local index = Number(GetShapeshiftForm())
            if index == 0 then v = CH.FORM_NONE
            elseif index and GetShapeshiftFormInfo then v = Number(select(4, GetShapeshiftFormInfo(index))) end
        end
        return Set(into, "form", v)
    end,
})

---------------------------------------------------------------------------
-- Level
---------------------------------------------------------------------------
C.Register({
    type = "level", label = "Your level",
    Supported = function() return rawget(_G, "UnitLevel") ~= nil end,
    unsupported = "this game client doesn't say your level.",
    New = function() return { type = "level", compare = "below", level = 60 } end,

    Check = function(raw)
        if not C.ValidCompare(raw.compare) then return nil, "it compares a level in a way this version of TwichUI doesn't know." end
        local clean = { type = "level", compare = raw.compare, level = C.Whole(raw.level, 1, CH.LEVEL_MAX) }
        if not clean.level then return clean, ("choose the level it compares with (1 to %d)."):format(CH.LEVEL_MAX) end
        return clean
    end,

    Needs = function(_, add) add("level") end,

    Evaluate = function(cond, obs)
        local v = obs and obs.level
        if v == nil then return UNKNOWN, "The game hasn't said your level yet." end
        return Yes(C.Compare(v, cond.compare, cond.level))
    end,

    Summary = function(cond)
        return ("Your level is %s %d"):format(cond.compare == "below" and "below" or "at least", cond.level or 0)
    end,

    Observed = function(_, obs)
        local v = obs and obs.level
        return v and ("Level %d"):format(v) or "Not read yet"
    end,

    Subject = function() return "level", "Your level" end,

    Scenarios = function()
        local list = {}
        for _, n in ipairs({ 10, 30, 59, 60, 70 }) do
            list[#list + 1] = { key = "level" .. n, label = "Level " .. n, Apply = function(obs) obs.level = n end }
        end
        list[#list + 1] = { key = "unread", label = "Not read yet", Apply = function(obs) obs.level = nil end }
        return list
    end,
})

local levelSaid   -- what PLAYER_LEVEL_UP last said (nil until one is heard)
ST.Source("level", {
    events = {
        PLAYER_LEVEL_UP = function(level) levelSaid = Number(level) return true end,
        PLAYER_LEVEL_CHANGED = function(_, new) levelSaid = Number(new) or levelSaid return true end,
    },
    Read = function(_, into)
        ST.Counted()
        local v = UnitLevel and Number(UnitLevel("player")) or nil
        if levelSaid and (not v or levelSaid > v) then v = levelSaid end
        if v and v < 1 then v = nil end
        return Set(into, "level", v)
    end,
    Reset = function() levelSaid = nil end,
})

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
-- key (stored), the editor's label, a tooltip
CH.COOLDOWN_CHOICES = {
    { "ready", "Is ready", "You know it and it isn't cooling down. The global cooldown after any spell doesn't count." },
    { "cooling", "Is cooling down", "You know it and it is cooling down (or waiting for something else to end first)." },
    { "within", "Is ready soon", "You know it, and it is ready or will be in less than the time you choose." },
}
local COOLDOWN = {}
for _, c in ipairs(CH.COOLDOWN_CHOICES) do COOLDOWN[c[1]] = c end
function CH.CooldownChoice(key) return COOLDOWN[key] end

local function CooldownFacts(cond, obs)
    local t = obs and obs.cooldown
    return type(t) == "table" and cond.spell and t[cond.spell] or nil
end

local function CooldownLeft(f, obs)
    if not (f.ends and type(obs.now) == "number") then return nil end
    return f.ends - obs.now
end

C.Register({
    type = "cooldown", label = "A spell's cooldown",
    Supported = function() return C_Spell ~= nil and C_Spell.GetSpellCooldown ~= nil end,
    unsupported = "this game client doesn't say about cooldowns.",
    New = function() return { type = "cooldown", what = "ready" } end,

    Check = function(raw)
        if not COOLDOWN[raw.what] then return nil, "it asks about a cooldown in a way this version of TwichUI doesn't know." end
        local clean = { type = "cooldown", what = raw.what }
        if raw.spell ~= nil then
            if not C.ValidSpell(raw.spell) then return nil, "it names a spell by something that isn't a spell ID." end
            clean.spell = raw.spell
        end
        if raw.what == "within" then
            clean.seconds = C.Whole(raw.seconds, 1, CH.COOLDOWN_SECONDS_MAX)
            if not clean.seconds then return clean, ("choose how soon counts (1 to %d seconds)."):format(CH.COOLDOWN_SECONDS_MAX) end
        end
        if not clean.spell then return clean, "choose the spell it looks at (its spell ID or link)." end
        return clean
    end,

    Needs = function(cond, add) if cond.spell then add("cooldown:" .. cond.spell) end end,

    Evaluate = function(cond, obs)
        local f = CooldownFacts(cond, obs)
        if f == nil then return UNKNOWN, "The game hasn't said about this spell's cooldown yet." end
        if f.known == false then return NOMATCH end
        if f.state == nil then return UNKNOWN, "The game hasn't said about this spell's cooldown yet." end
        if cond.what == "ready" then return Yes(f.state == "ready") end
        if cond.what == "cooling" then return Yes(f.state ~= "ready") end
        if f.state == "ready" then return MATCH end
        if f.state == "held" then return NOMATCH end
        local left = CooldownLeft(f, obs)
        if left == nil then return UNKNOWN, "The game hasn't said how long the cooldown has left." end
        return Yes(left < cond.seconds)
    end,

    NextChange = function(cond, obs)
        local f = CooldownFacts(cond, obs)
        if not (f and f.state == "cooling") then return nil end
        local left = CooldownLeft(f, obs)
        if not left or left <= 0 then return nil end
        if cond.what == "within" and cond.seconds and left >= cond.seconds then return left - cond.seconds end
        return left
    end,

    Summary = function(cond)
        local name = C.SpellWords(cond.spell)
        if cond.what == "ready" then return name .. " is ready" end
        if cond.what == "cooling" then return name .. " is cooling down" end
        return ("%s is ready within %s"):format(name, cond.seconds and C.Duration(cond.seconds) or "?")
    end,

    Observed = function(cond, obs)
        local f = CooldownFacts(cond, obs)
        if f == nil then return "Not read yet" end
        if f.known == false then return "You don't know it" end
        if f.state == "ready" then return "Ready" end
        if f.state == "held" then return "Waiting to start cooling down" end
        local left = CooldownLeft(f, obs)
        if left and left > 0 then return ("Cooling down (%s left)"):format(C.Duration(math.ceil(left))) end
        return f.state and "Cooling down" or "Not read yet"
    end,

    Scenarios = function(cond)
        local list = {}
        local function Put(key, label, facts)
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                obs.cooldown = obs.cooldown or {}
                if type(facts) == "table" and facts.left then
                    facts = { known = true, state = "cooling", ends = (obs.now or 0) + facts.left }
                end
                obs.cooldown[cond.spell or 0] = facts
            end }
        end
        local s = cond.seconds or 10
        local ready, long = { "ready", "Ready", { known = true, state = "ready" } }, { "long", ("Cooling down, %s left"):format(C.Duration(s * 4)), { left = s * 4 } }
        if cond.what == "cooling" then ready, long = long, ready end
        Put(ready[1], ready[2], ready[3])
        if cond.what == "within" then Put("soon", ("Cooling down, %s left"):format(C.Duration(math.max(1, math.floor(s / 2)))), { left = math.max(1, math.floor(s / 2)) }) end
        Put(long[1], long[2], long[3])
        Put("unknownSpell", "You don't know it", { known = false })
        Put("unread", "Not read yet", nil)
        return list
    end,
})

local function ReadCooldown(id)
    local known = Known(id)
    if not Exists(id) then return nil end
    if known == false then return { known = false } end
    if known == nil then return nil end
    if not (C_Spell and C_Spell.GetSpellCooldown) then return nil end
    local ok, info = pcall(C_Spell.GetSpellCooldown, id)
    if not ok or type(info) ~= "table" or (issecretvalue and issecretvalue(info)) then return nil end
    local f = { known = true }
    local enabled, activeNow, gcd = Plain(info.isEnabled), Plain(info.isActive), Plain(info.isOnGCD)
    if enabled == false then f.state = "held"
    elseif activeNow == false or gcd == true then f.state = "ready"
    elseif activeNow == true then
        f.state = "cooling"
        local start, duration = Number(info.startTime), Number(info.duration)
        if start and duration and duration > 0 then f.ends = start + duration end
    end
    return f
end

ST.Source("cooldown", {
    events = { SPELL_UPDATE_COOLDOWN = true, SPELLS_CHANGED = true },
    Read = function(arg, into)
        local id = tonumber(arg)
        if not id then return false end
        ST.Counted()
        into.cooldown = into.cooldown or {}
        local v, old = ReadCooldown(id), into.cooldown[id]
        if type(v) == "table" and type(old) == "table" and v.known == old.known and v.state == old.state and v.ends == old.ends then return false end
        if v == nil and old == nil then return false end
        into.cooldown[id] = v
        return true
    end,
    Forget = function(arg, into) if into.cooldown then into.cooldown[tonumber(arg) or 0] = nil end end,
})
