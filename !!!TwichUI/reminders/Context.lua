-- TwichUI: Reminders, your group, where you are and your target
-- Condition kinds (Conditions.lua says what a provider is) and their sources (State.lua says what a source is). They only
-- read: no invitation, no target change, no message.
--
-- groupType  `what` ("solo" | "party" | "raid" | "grouped"), `negate`. IsInRaid / IsInGroup (as healer/Watch.lua and
--            buffback/Watch.lua read them) on GROUP_ROSTER_UPDATE: whom you are grouped with, never where you are. A raid
--            group in the open world is a raid group; a party inside a raid instance is a party ("You are in a raid", the
--            place, is a separate condition). "party" is a group that isn't a raid group; "grouped" is either.
-- zone       `map` (a uiMapID) or `instance` (an instance ID), `negate`. A map matches where you are and every map inside
--            it, by the game's own parent links (C_Map.GetBestMapForUnit("player"), C_Map.GetMapInfo(id).parentMapID up to
--            the continent): choosing a zone covers its towns and caves. An instance matches only inside that instance
--            (IsInInstance, GetInstanceInfo's instanceID). Never by a name: the names here are only the game's labels,
--            looked up when shown. A map the game can't give just after a loading screen is unknown, not "elsewhere".
--            Read on ZONE_CHANGED_NEW_AREA, ZONE_CHANGED, ZONE_CHANGED_INDOORS and on entering the world.
-- target     `what` ("exists" | "attackable" | "friendly" | "dead"), `negate`. The current target only: UnitExists,
--            UnitCanAttack("player", "target"), UnitIsFriend("player", "target"), UnitIsDeadOrGhost. With no target,
--            only "You have a target" can be answered: "Your target is (not) friendly" and the others don't match, so a
--            missing target never satisfies "is not". Read on PLAYER_TARGET_CHANGED and UNIT_FLAGS for the target;
--            "dead" also on UNIT_HEALTH for the target (only while a reminder asks whether it is dead).

local R = TwichUI
local C = R.ReminderConditions
local ST = R.ReminderState

local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN
local Yes, Negate = C.Yes, C.Negate
local Plain, Number, Set = ST.Plain, ST.Number, ST.Set

local CX = {}
R.ReminderContext = CX

---------------------------------------------------------------------------
-- Group
---------------------------------------------------------------------------
-- key (stored), the editor's label, "You are ..." words, "You are not ..." words
CX.GROUP_CHOICES = {
    { "solo", "Solo", "solo", "in a group" },
    { "party", "In a party", "in a party", "not in a party" },
    { "raid", "In a raid group", "in a raid group", "not in a raid group" },
    { "grouped", "In any group", "in a group", "solo" },
}
local GROUP = {}
for _, g in ipairs(CX.GROUP_CHOICES) do GROUP[g[1]] = g end
function CX.GroupChoice(key) return GROUP[key] end

local function GroupMatches(what, v)
    if what == "grouped" then return v ~= "solo" end
    return v == what
end

C.Register({
    type = "groupType", label = "Your group",
    Supported = function() return rawget(_G, "IsInGroup") ~= nil end,
    unsupported = "this game client doesn't say whether you are in a group.",
    New = function() return { type = "groupType", what = "grouped", negate = false } end,

    Check = function(raw)
        if not GROUP[raw.what] then return nil, "it asks about your group in a way this version of TwichUI doesn't know." end
        return { type = "groupType", what = raw.what, negate = raw.negate == true }
    end,

    Needs = function(_, add) add("groupType") end,

    Evaluate = function(cond, obs)
        local v = obs and obs.groupType
        if v == nil then return UNKNOWN, "The game hasn't said whether you are in a group yet." end
        return Negate(Yes(GroupMatches(cond.what, v)), cond.negate)
    end,

    Summary = function(cond)
        local g = GROUP[cond.what]
        return "You are " .. (cond.negate and g[4] or g[3])
    end,

    Observed = function(_, obs)
        local v = obs and obs.groupType
        return ({ solo = "Solo", party = "In a party", raid = "In a raid group" })[v] or "Not read yet"
    end,

    Subject = function() return "groupType", "Your group" end,

    Scenarios = function()
        local list = {}
        for _, v in ipairs({ { "solo", "Solo" }, { "party", "In a party" }, { "raid", "In a raid group" } }) do
            list[#list + 1] = { key = v[1], label = v[2], Apply = function(obs) obs.groupType = v[1] end }
        end
        list[#list + 1] = { key = "unread", label = "Not read yet", Apply = function(obs) obs.groupType = nil end }
        return list
    end,
})

ST.Source("groupType", {
    events = { GROUP_ROSTER_UPDATE = true },
    Read = function(_, into)
        ST.Counted()
        local v
        if IsInGroup then
            local raid = IsInRaid and Plain(IsInRaid())
            local group = Plain(IsInGroup())
            if raid == true then v = "raid"
            elseif group == true then v = "party"
            elseif group == false then v = "solo" end
        end
        return Set(into, "groupType", v)
    end,
})

---------------------------------------------------------------------------
-- Zone or instance
---------------------------------------------------------------------------
local MAP_TYPE = rawget(_G, "Enum") and Enum.UIMapType or {}
local CONTINENT = MAP_TYPE.Continent or 2
local MAX_CHAIN = 12

local function MapInfo(id)
    if not (C_Map and C_Map.GetMapInfo) then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if ok and type(info) == "table" and not (issecretvalue and issecretvalue(info)) then return info end
    return nil
end

function CX.MapName(id)
    local info = id and MapInfo(id)
    local name = info and Plain(info.name)
    if type(name) == "string" and name ~= "" then return name end
    return ("map %d"):format(id or 0)
end

function CX.InstanceName(id)
    if id and GetRealZoneText then
        local ok, name = pcall(GetRealZoneText, id)
        name = ok and Plain(name) or nil
        if type(name) == "string" and name ~= "" then return name end
    end
    return ("instance %d"):format(id or 0)
end

-- The key of a stored choice ("map:1453", "instance:36"), or nil.
function CX.ZoneKey(cond)
    if cond.map then return "map:" .. cond.map end
    if cond.instance then return "instance:" .. cond.instance end
    return nil
end

function CX.ZoneWords(cond)
    if cond.map then return CX.MapName(cond.map) end
    if cond.instance then return CX.InstanceName(cond.instance) end
    return nil
end

-- Where you are as plain facts, or nil: { map, chain = { mapID, parent, ..., continent }, instance }.
local function ReadZone()
    local f = { chain = {} }
    if IsInInstance then
        local inside = Plain((IsInInstance()))
        if inside == true and GetInstanceInfo then f.instance = Number(select(8, GetInstanceInfo())) end
        if inside == nil then return nil end
    end
    local map = C_Map and C_Map.GetBestMapForUnit and Number(C_Map.GetBestMapForUnit("player")) or nil
    f.map = map
    local id, n = map, 0
    while id and n < MAX_CHAIN do
        n = n + 1
        f.chain[#f.chain + 1] = id
        local info = MapInfo(id)
        local kind = info and Number(info.mapType)
        if not info or (kind and kind <= CONTINENT) then break end
        local parent = Number(info.parentMapID)
        id = parent and parent > 0 and parent or nil
    end
    if not map and not f.instance then return nil end
    return f
end

-- The choices the editor offers here: where you are now (the map, the maps it lies in, the instance) and the stored one.
function CX.ZoneChoices(cond)
    local out, seen = {}, {}
    local function Put(key, label) if not seen[key] then seen[key] = true; out[#out + 1] = { value = key, label = label } end end
    local f = ReadZone()
    if f and f.instance then Put("instance:" .. f.instance, CX.InstanceName(f.instance) .. " (this instance)") end
    for i, id in ipairs(f and f.chain or {}) do Put("map:" .. id, CX.MapName(id) .. (i == 1 and " (where you are)" or "")) end
    local key = cond and CX.ZoneKey(cond)
    if key then Put(key, CX.ZoneWords(cond)) end
    return out
end

C.Register({
    type = "zone", label = "Where you are",
    Supported = function() return C_Map ~= nil and C_Map.GetBestMapForUnit ~= nil end,
    unsupported = "this game client doesn't say where you are.",
    New = function()
        local f = ReadZone()
        local cond = { type = "zone", negate = false }
        if f and f.instance then cond.instance = f.instance elseif f and f.map then cond.map = f.map end
        return cond
    end,

    Check = function(raw)
        local clean = { type = "zone", negate = raw.negate == true }
        if raw.map ~= nil and raw.instance ~= nil then return nil, "it names both a map and an instance." end
        if raw.map ~= nil then
            if not C.Whole(raw.map, 1, 2147483647) then return nil, "it names a map by something that isn't a map ID." end
            clean.map = raw.map
        elseif raw.instance ~= nil then
            if not C.Whole(raw.instance, 0, 2147483647) then return nil, "it names an instance by something that isn't an instance ID." end
            clean.instance = raw.instance
        else
            return clean, "choose the place it looks for (open the editor where you want it to apply)."
        end
        return clean
    end,

    Needs = function(_, add) add("zone") end,

    Evaluate = function(cond, obs)
        local f = obs and obs.zone
        if type(f) ~= "table" then return UNKNOWN, "The game hasn't said where you are yet." end
        if cond.instance then return Negate(Yes(f.instance == cond.instance), cond.negate) end
        if not f.map then
            if f.instance then return Negate(NOMATCH, cond.negate) end   -- inside an instance with no map of its own
            return UNKNOWN, "The game hasn't said where you are yet."
        end
        local inside = false
        for _, id in ipairs(f.chain) do if id == cond.map then inside = true end end
        return Negate(Yes(inside), cond.negate)
    end,

    Summary = function(cond)
        local words = CX.ZoneWords(cond) or "(no place chosen)"
        return ("You are %sin %s"):format(cond.negate and "not " or "", words)
    end,

    Observed = function(_, obs)
        local f = obs and obs.zone
        if type(f) ~= "table" then return "Not read yet" end
        if f.instance then return CX.InstanceName(f.instance) end
        return f.map and CX.MapName(f.map) or "Not read yet"
    end,

    Subject = function() return "zone", "Where you are" end,

    -- inside the chosen place, somewhere else, and nothing read (the same three whatever is chosen)
    Scenarios = function(cond)
        local list = {}
        local function Put(key, label, facts)
            list[#list + 1] = { key = key, label = label, Apply = function(obs) obs.zone = facts end }
        end
        if cond.instance then
            Put("inside", "Inside " .. CX.InstanceName(cond.instance), { instance = cond.instance, chain = {} })
        elseif cond.map then
            Put("inside", "In " .. CX.MapName(cond.map), { map = cond.map, chain = { cond.map } })
        end
        Put("elsewhere", "Somewhere else", { map = -1, chain = { -1 } })
        Put("unread", "Not read yet", nil)
        return list
    end,
})

local function SameZone(a, b)
    if a == nil or b == nil then return a == b end
    if a.map ~= b.map or a.instance ~= b.instance or #a.chain ~= #b.chain then return false end
    for i, id in ipairs(a.chain) do if b.chain[i] ~= id then return false end end
    return true
end

ST.Source("zone", {
    events = { ZONE_CHANGED_NEW_AREA = true, ZONE_CHANGED = true, ZONE_CHANGED_INDOORS = true },
    Read = function(_, into)
        ST.Counted()
        local f = ReadZone()
        if SameZone(f, into.zone) then return false end
        into.zone = f
        return true
    end,
})

---------------------------------------------------------------------------
-- Target
---------------------------------------------------------------------------
-- key (stored), the editor's label, "is" words, "is not" words
CX.TARGET_CHOICES = {
    { "exists", "Have a target", "You have a target", "You have no target" },
    { "attackable", "Can be attacked", "Your target can be attacked", "Your target can't be attacked" },
    { "friendly", "Is friendly", "Your target is friendly", "Your target is not friendly" },
    { "dead", "Is dead", "Your target is dead", "Your target is alive" },
}
local TARGET = {}
for _, t in ipairs(CX.TARGET_CHOICES) do TARGET[t[1]] = t end
function CX.TargetChoice(key) return TARGET[key] end

local function TargetFacts(cond, obs)
    local f = obs and obs.target
    if type(f) ~= "table" then return nil end
    if cond.what == "dead" then
        local life = obs.targetLife
        if f.exists and life == nil then return nil end
        return f, life
    end
    return f
end

C.Register({
    type = "target", label = "Your target",
    Supported = function() return rawget(_G, "UnitExists") ~= nil end,
    unsupported = "this game client doesn't say about your target.",
    New = function() return { type = "target", what = "attackable", negate = false } end,

    Check = function(raw)
        if not TARGET[raw.what] then return nil, "it asks about your target in a way this version of TwichUI doesn't know." end
        return { type = "target", what = raw.what, negate = raw.negate == true }
    end,

    Needs = function(cond, add)
        add("target")
        if cond.what == "dead" then add("targetLife") end
    end,

    Evaluate = function(cond, obs)
        local f, dead = TargetFacts(cond, obs)
        if f == nil then return UNKNOWN, "The game hasn't said about your target yet." end
        if cond.what == "exists" then return Negate(Yes(f.exists), cond.negate) end
        if not f.exists then return NOMATCH end   -- no target is neither friendly nor not
        local v
        if cond.what == "dead" then v = dead else v = f[cond.what] end
        if v == nil then return UNKNOWN, "The game hasn't said about your target yet." end
        return Negate(Yes(v == true), cond.negate)
    end,

    Summary = function(cond)
        local t = TARGET[cond.what]
        return cond.negate and t[4] or t[3]
    end,

    Observed = function(cond, obs)
        local f, dead = TargetFacts(cond, obs)
        if f == nil then return "Not read yet" end
        if not f.exists then return "No target" end
        local parts = {}
        if f.attackable then parts[#parts + 1] = "can be attacked" end
        if f.friendly then parts[#parts + 1] = "friendly" end
        if dead == true then parts[#parts + 1] = "dead" end
        return "A target" .. (#parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or "")
    end,

    Subject = function() return "target", "Your target" end,

    Scenarios = function()
        local list = {}
        local function Put(key, label, facts, dead)
            list[#list + 1] = { key = key, label = label, Apply = function(obs) obs.target, obs.targetLife = facts, dead end }
        end
        Put("enemy", "An enemy you can attack", { exists = true, attackable = true, friendly = false }, false)
        Put("ally", "A friendly player", { exists = true, attackable = false, friendly = true }, false)
        Put("corpse", "A dead enemy", { exists = true, attackable = true, friendly = false }, true)
        Put("none", "No target", { exists = false }, nil)
        Put("unread", "Not read yet", nil, nil)
        return list
    end,
})

local function ReadTarget()
    if not UnitExists then return nil end
    local exists = Plain(UnitExists("target"))
    if exists == nil then return nil end
    if not exists then return { exists = false } end
    local f = { exists = true }
    if UnitCanAttack then f.attackable = Plain(UnitCanAttack("player", "target")) end
    if UnitIsFriend then f.friendly = Plain(UnitIsFriend("player", "target")) end
    if type(f.attackable) ~= "boolean" then f.attackable = nil end
    if type(f.friendly) ~= "boolean" then f.friendly = nil end
    return f
end

local function TargetUnit(unit)
    if issecretvalue and issecretvalue(unit) then return true end
    if unit == "target" then return true end
end

ST.Source("target", {
    events = { PLAYER_TARGET_CHANGED = true, UNIT_FLAGS = TargetUnit, UNIT_FACTION = TargetUnit },
    units = { UNIT_FLAGS = "target", UNIT_FACTION = "target" },
    Read = function(_, into)
        ST.Counted()
        local f, old = ReadTarget(), into.target
        if f and old and f.exists == old.exists and f.attackable == old.attackable and f.friendly == old.friendly then return false end
        if f == nil and old == nil then return false end
        into.target = f
        return true
    end,
})

ST.Source("targetLife", {
    events = { PLAYER_TARGET_CHANGED = true, UNIT_HEALTH = TargetUnit, UNIT_FLAGS = TargetUnit },
    units = { UNIT_HEALTH = "target", UNIT_FLAGS = "target" },
    Read = function(_, into)
        ST.Counted()
        local v
        if UnitExists and Plain(UnitExists("target")) == true and UnitIsDeadOrGhost then
            v = Plain(UnitIsDeadOrGhost("target"))
            if type(v) ~= "boolean" then v = nil end
        end
        return Set(into, "targetLife", v)
    end,
})
