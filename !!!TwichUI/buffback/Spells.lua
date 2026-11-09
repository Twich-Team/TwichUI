-- TwichUI: Return the Favor, the buffs
-- Which buffs count as a favor another player did you, which of them each class can give back, and how a click
-- gives one back. Everything here is pure: it reads only what it is handed (and the client's spell names, through
-- SpellName), so the tests can drive it without a game.
--
-- The spell IDs are the game's own (WoW: Forever shares Classic Era's spell data for these). A family is one buff
-- with all its ranks, plus the group versions that put the same aura on you (Arcane Brilliance for Arcane
-- Intellect, Greater Blessings ...). A buff is recognized by its ID, or by the client's name for any of the family's
-- IDs (so a rank missing here still counts). Casting back uses the spell's name, so the game casts the highest rank
-- you know.
--
--   S.Family(spellId, name)       the family a buff on you belongs to, or nil (not a favor this list knows)
--   S.Gives(class)                the families a class can give, in its order of preference (a new list)
--   S.Known(family, known)        whether you know any rank of it; known(id) answers for one spell ID
--   S.Pick(class, entry, known, wearing)   what a click on entry gives back: the family, or nil and why
--   S.Macro(entry, family, spell, target)  the macro text a click runs, or nil

local R = TwichUI
local S = {}
R.BuffBackSpells = S

-- The classes whose resource is mana (a druid in cat form still benefits from Arcane Intellect later).
S.MANA = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, PALADIN = true, SHAMAN = true, HUNTER = true }

-- key -> { ranks (lowest first: the first is the spell named when casting), also (the same aura from a group
-- spell), class (who casts it), mana (only worth giving to a mana user), physical (better for those without
-- mana), selfCast (cast on yourself and reaches the party), partyOnly (only reaches your own party) }
local F = {
    intellect = { class = "MAGE", ranks = { 1459, 1460, 1461, 10156, 10157 }, also = { 23028 }, mana = true },
    fortitude = { class = "PRIEST", ranks = { 1243, 1244, 1245, 2791, 10937, 10938 }, also = { 21562, 21564 } },
    spirit = { class = "PRIEST", ranks = { 14752, 14818, 14819, 27841 }, also = { 27681 }, mana = true },
    shadow = { class = "PRIEST", ranks = { 976, 10957, 10958 }, also = { 27683 } },
    wild = { class = "DRUID", ranks = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 }, also = { 21849, 21850 } },
    thorns = { class = "DRUID", ranks = { 467, 782, 1075, 8914, 9756, 9910 } },
    wisdom = { class = "PALADIN", ranks = { 19742, 19850, 19852, 19853, 19854, 25290 }, also = { 25894, 25918 }, mana = true },
    might = { class = "PALADIN", ranks = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 }, also = { 25782, 25916 }, physical = true },
    kings = { class = "PALADIN", ranks = { 20217 }, also = { 25898 } },
    breath = { class = "WARLOCK", ranks = { 5697 } },
    shout = { class = "WARRIOR", ranks = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 }, selfCast = true, partyOnly = true, receivedNever = true },
    -- received only: a favor all the same, but nothing a class gives back from this list
    salvation = { class = "PALADIN", ranks = { 1038 }, also = { 25895 }, giveNever = true },
    light = { class = "PALADIN", ranks = { 19977, 19978, 19979 }, also = { 25890 }, giveNever = true },
    sanctuary = { class = "PALADIN", ranks = { 20911, 20912, 20913, 20914 }, also = { 25899 }, giveNever = true },
    amplify = { class = "MAGE", ranks = { 1008, 8455, 10169, 10170 }, giveNever = true },
    dampen = { class = "MAGE", ranks = { 604, 8450, 8451, 10173, 10174 }, giveNever = true },
    fearward = { class = "PRIEST", ranks = { 6346 }, giveNever = true },
    detect = { class = "WARLOCK", ranks = { 132, 2970, 11743 }, giveNever = true },
    waterBreathing = { class = "SHAMAN", ranks = { 131 }, giveNever = true },
    waterWalking = { class = "SHAMAN", ranks = { 546 }, giveNever = true },
}
S.FAMILIES = F
for key, fam in pairs(F) do fam.key = key end

-- What each class gives back, in its order of preference (Pick reorders for the player it is for).
S.GIVES = {
    MAGE = { "intellect" },
    PRIEST = { "fortitude", "spirit", "shadow" },
    DRUID = { "wild", "thorns" },
    PALADIN = { "wisdom", "kings", "might" },
    WARLOCK = { "breath" },
    WARRIOR = { "shout" },
}

-- Every ID of every family, to the family (built once).
local BY_ID = {}
for _, fam in pairs(F) do
    if not fam.receivedNever then
        for _, id in ipairs(fam.ranks) do BY_ID[id] = fam end
        for _, id in ipairs(fam.also or {}) do BY_ID[id] = fam end
    end
end
S.BY_ID = BY_ID

-- The client's name for a spell, or nil. Cached once it has given one; asked again until then.
local names = {}
function S.SpellName(id)
    if type(id) ~= "number" then return nil end
    local name = names[id]
    if name then return name end
    local get = C_Spell and C_Spell.GetSpellName
    if get then
        local ok, v = pcall(get, id)
        if ok then name = v end
    elseif GetSpellInfo then
        local ok, v = pcall(GetSpellInfo, id)
        if ok then name = v end
    end
    if type(name) ~= "string" or name == "" or (issecretvalue and issecretvalue(name)) then return nil end
    names[id] = name
    return name
end

-- Name -> family, built the first time a buff is not known by its ID (the client's names may not be there at load).
-- Tried at most NAME_TRIES times while some name is missing (an ID this client doesn't have never gets one).
local byName, byNameComplete
local nameTries, NAME_TRIES = 0, 5
local function NameIndex()
    if byNameComplete then return byName end
    byName = byName or {}
    local complete = true
    for id, fam in pairs(BY_ID) do
        local name = S.SpellName(id)
        if name then byName[name] = fam else complete = false end
    end
    nameTries = nameTries + 1
    byNameComplete = complete or nameTries >= NAME_TRIES
    return byName
end

function S.Family(spellId, name)
    if type(spellId) == "number" and BY_ID[spellId] then return BY_ID[spellId] end
    if type(name) == "string" and name ~= "" then return NameIndex()[name] end
    return nil
end

-- Whether a spell ID is one of a family's own (a rank or a group version), for telling a cast back.
function S.IsOf(fam, spellId)
    if not (fam and type(spellId) == "number") then return false end
    for _, id in ipairs(fam.ranks) do if id == spellId then return true end end
    for _, id in ipairs(fam.also or {}) do if id == spellId then return true end end
    return false
end

function S.Gives(class)
    local out = {}
    for _, key in ipairs(S.GIVES[class] or {}) do out[#out + 1] = F[key] end
    return out
end

function S.Known(fam, known)
    if not fam then return false end
    for _, id in ipairs(fam.ranks) do
        if known(id) then return true end
    end
    return false
end

-- What a click on entry gives back. entry: { class, inParty }; known(id): whether the player knows a spell;
-- wearing: { [family key] = true } of what they already have, or nil (it can't be read); it only reorders, since
-- giving what they wear refreshes it. Returns the family, or nil and a reason code: "nothing" (your class gives
-- nothing), "unknown" (you know none of it yet), "party" (a shout reaches only your party), "mana" (all you have
-- is for mana users).
function S.Pick(class, entry, known, wearing)
    local list = S.Gives(class)
    if #list == 0 then return nil, "nothing" end
    local mana = S.MANA[entry and entry.class or ""] == true
    local learned, why = {}, "unknown"
    for _, fam in ipairs(list) do
        if S.Known(fam, known) then learned[#learned + 1] = fam end
    end
    if #learned == 0 then return nil, "unknown" end
    local usable = {}
    for _, fam in ipairs(learned) do
        if fam.partyOnly and not (entry and entry.inParty) then
            why = "party"
        elseif fam.mana and entry and entry.class and not mana then
            why = "mana"
        else
            usable[#usable + 1] = fam
        end
    end
    if #usable == 0 then return nil, why end
    -- for someone without mana, what suits them (Might) comes before the rest; the order is otherwise the class's
    if entry and entry.class and not mana then
        table.sort(usable, function(a, b)
            local pa, pb = a.physical and 1 or 0, b.physical and 1 or 0
            if pa ~= pb then return pa > pb end
            local ia, ib
            for i, fam in ipairs(list) do
                if fam == a then ia = i end
                if fam == b then ib = i end
            end
            return ia < ib
        end)
    end
    -- what they don't wear yet comes first; if they wear it all, the usual first choice is given anyway, to refresh it
    if wearing then
        for _, fam in ipairs(usable) do
            if not wearing[fam.key] then return fam end
        end
    end
    return usable[1]
end

-- The macro a click runs to give fam to entry. spell: the spell's name; target: { has = you have a target,
-- isThem = it is them, token = their party or raid unit }. In your group the cast names their unit token
-- ([@party2]; a name can't go in a conditional, it holds a space on this client); otherwise they are targeted by
-- name, the spell cast, and your own target handed back (/targetlasttarget, or /cleartarget when you had none).
-- A shout is just cast. Nil without a spell or name.
function S.Macro(entry, fam, spell, target)
    if not (entry and fam and type(spell) == "string" and spell ~= "") then return nil end
    if spell:find("[%c\n;]") then return nil end
    if fam.selfCast then return "/cast " .. spell end
    local who = entry.name
    -- a full name is "Name" or "Name Surname": letters and one space, nothing that could end or add a macro line
    if type(who) ~= "string" or who == "" or who:find("[%c%[%];,|]") or who:find("^%s") or who:find("%s$") then return nil end
    target = target or {}
    local token = target.token
    if entry.inGroup and type(token) == "string" and (token:find("^party%d$") or token:find("^raid%d+$")) then
        return "/cast [@" .. token .. "] " .. spell
    end
    if target.isThem then return "/cast [@target] " .. spell end
    return table.concat({ "/target " .. who, "/cast " .. spell, target.has and "/targetlasttarget" or "/cleartarget" }, "\n")
end

-- The families a set of helpful aura spell IDs and names covers: { [key] = true }. auras: { { spellId, name }, ... }.
function S.Wearing(auras)
    local out = {}
    for _, a in ipairs(auras) do
        local fam = S.Family(a[1], a[2])
        if fam then out[fam.key] = true end
    end
    return out
end
