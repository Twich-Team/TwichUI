-- TwichUI: Navigation, what this character can use to get there
-- Read when a journey is planned (nav/Journey.lua), never polled. Everything but the Hearthstone's bind point is the game's to
-- say at that moment:
--   Flights    the flight points this character is known to have learned. The game does not say outside a flight master
--              (GetTaxiNodesForMap's `isUndiscovered` gave every point as learned, as the player saw), so TwichUI keeps a record:
--              each time a flight master's map opens, the points it offers (C_TaxiMap.GetAllTaxiNodes: state Current or
--              Reachable) are added. A learned point is never forgotten; one never seen on a flight map is not used. The
--              record is this character's (TwichUIDB.ui.navTravel[guid].flights, account-wide, never in a profile or shared).
--   Teleports  the Mage's teleports Forever teaches (modules/MageTravel.lua's list): the spell is known, and a Rune of
--              Teleportation is in the bags. The spell is never cast by TwichUI; the journey says to.
--   Hearthstone  the item is in the bags; its cooldown (what is left of it counts as time); and the bind point.
--   Faction    UnitFactionGroup.
-- The bind point: the game tells an addon only the bind place's name (GetBindLocation), so TwichUI keeps where the player
-- stood when the HEARTHSTONE_BOUND event fired (at the innkeeper), or where a Hearthstone journey landed. It is a record
-- of this character (TwichUIDB.ui.navTravel[guid].bind, account-wide, never in a profile or shared). Without one the
-- Hearthstone is not offered, and the settings say so. The listeners (that event and the flight map's) exist
-- only while Navigation is on, so flight points are learned only while it is.
-- In combat the last answer is used: cooldowns and spell reads may be secret then.

local R = TwichUI
local NV, NP = R.Nav, R.NavPrefs
local TV = {}
R.NavTravel = TV

-- UiMap IDs (UiMap.db2 of this client): Kalimdor, Eastern Kingdoms, Riverglades (in the Eastern Kingdoms), Zephras Isle
local MAPS = { 1414, 1415, 2548, 2521 }
local HEARTH_ITEM, HEARTH_CAST = 6948, 10
local RUNE = { teleport = 17031 }          -- Rune of Teleportation (modules/MageTravel.lua's M.REAGENTS)
local SPEEDS = { foot = 7, mount = 7 * 1.6, fast = 7 * 2 }
TV.SPEEDS = SPEEDS

local cache
local Record     -- defined with the Hearthstone's record below

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

function TV.Faction()
    local f = UnitFactionGroup and Plain((UnitFactionGroup("player")))
    if f == "Alliance" then return 1 end
    if f == "Horde" then return 2 end
    return nil
end

function TV.Speed() return SPEEDS[NP.Get("speed")] or SPEEDS.foot end

---------------------------------------------------------------------------
-- Flights
---------------------------------------------------------------------------
local MAX_FLIGHTS = 500       -- a bound on the record; the network has under a hundred

-- { [taxi node ID] = true } (a copy) for the flight points learned so far, or nil when none has been seen yet.
function TV.Flights()
    local r = Record(false)
    local known = r and r.flights
    if type(known) ~= "table" then return nil end
    local set, any = {}, false
    for node, v in pairs(known) do
        if v == true and type(node) == "number" then set[node] = true any = true end
    end
    return any and set or nil
end

-- How many flight points are known (for the settings).
function TV.FlightCount()
    local n = 0
    local set = TV.Flights()
    if set then for _ in pairs(set) do n = n + 1 end end
    return n
end

-- Adds node IDs to the record; returns how many were new.
function TV.LearnFlights(nodes)
    if type(nodes) ~= "table" then return 0 end
    local r = Record(true)
    if not r then return 0 end
    if type(r.flights) ~= "table" then r.flights = {} end
    local have = 0
    for _ in pairs(r.flights) do have = have + 1 end
    local new = 0
    for node in pairs(nodes) do
        if type(node) == "number" and node > 0 and not r.flights[node] and have < MAX_FLIGHTS then
            r.flights[node] = true
            have, new = have + 1, new + 1
        end
    end
    if new > 0 then cache = nil end
    return new
end

-- The points an open flight map offers: the maps the game may list them under (the continents, the player's own map and its
-- parents). A point you can fly to (Reachable) or stand at (Current) is learned. Unreachable is not counted: the game's
-- meaning of it for a point never learned is not known here.
local function NodesNow()
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return nil end
    local maps, seen = {}, {}
    local function Add(id)
        id = Plain(id)
        if id and id > 0 and not seen[id] then seen[id] = true maps[#maps + 1] = id end
    end
    for _, id in ipairs(MAPS) do Add(id) end
    local id = C_Map and C_Map.GetBestMapForUnit and Plain(C_Map.GetBestMapForUnit("player"))
    for _ = 1, 6 do
        if not id or id == 0 then break end
        Add(id)
        local ok, info = pcall(C_Map.GetMapInfo, id)
        id = ok and type(info) == "table" and Plain(info.parentMapID) or nil
    end
    local states = Enum and Enum.FlightPathState
    local CURRENT, REACHABLE = states and states.Current or 0, states and states.Reachable or 1
    local set, any = {}, false
    for _, map in ipairs(maps) do
        local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, map)
        if ok and type(nodes) == "table" then
            for _, n in ipairs(nodes) do
                local node, state = Plain(n.nodeID), Plain(n.state)
                if type(node) == "number" and (state == CURRENT or state == REACHABLE) then set[node] = true any = true end
            end
        end
    end
    return any and set or nil
end

-- A flight master's map opened (or a point's status changed while it is open).
local function OnTaxiMap()
    TV.LearnFlights(NodesNow())
end

---------------------------------------------------------------------------
-- Teleports
---------------------------------------------------------------------------
local function Known(id)
    local book = C_SpellBook
    if book and book.IsSpellKnown then
        local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        if bank then
            return book.IsSpellKnown(id, bank) or (book.IsSpellInSpellBook and book.IsSpellInSpellBook(id, bank, false)) or false
        end
        return book.IsSpellKnown(id) or false
    end
    return IsSpellKnown and IsSpellKnown(id) or false
end

local function Count(item)
    local n = C_Item and C_Item.GetItemCount and Plain(C_Item.GetItemCount(item))
    return type(n) == "number" and n or 0
end

-- The teleports (the network's list: { spell, place, cast }) this character knows and has a rune for.
function TV.Teleports(list)
    local out = {}
    if Count(RUNE.teleport) <= 0 then return out end
    for _, t in ipairs(list or {}) do
        if Known(t.spell) then out[#out + 1] = t end
    end
    return out
end

function TV.SpellName(id)
    local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
    return type(name) == "string" and name or nil
end

---------------------------------------------------------------------------
-- The Hearthstone and its bind point
---------------------------------------------------------------------------
function Record(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local guid = UnitGUID and Plain(UnitGUID("player"))
    if not guid then return nil end
    if create then
        TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
        if type(TwichUIDB.ui.navTravel) ~= "table" then TwichUIDB.ui.navTravel = {} end
        if type(TwichUIDB.ui.navTravel[guid]) ~= "table" then TwichUIDB.ui.navTravel[guid] = {} end
    end
    local all = TwichUIDB.ui and TwichUIDB.ui.navTravel
    return type(all) == "table" and type(all[guid]) == "table" and all[guid] or nil
end

-- { c = continent, x, y } or nil
function TV.Bind()
    local r = Record(false)
    local b = r and r.bind
    if type(b) == "table" and type(b.c) == "number" and type(b.x) == "number" and type(b.y) == "number" then return b end
    return nil
end

function TV.SetBind(cont, x, y)
    local r = Record(true)
    if not r or type(cont) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then return false end
    r.bind = { c = cont, x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    cache = nil
    return true
end

-- Seconds left on the Hearthstone's cooldown (0 when ready or unknown).
local function HearthCooldown()
    local f = C_Item and C_Item.GetItemCooldown
    if not f then return 0 end
    local ok, start, duration = pcall(f, HEARTH_ITEM)
    start, duration = ok and Plain(start), ok and Plain(duration)
    if type(start) ~= "number" or type(duration) ~= "number" or start <= 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- { cont, x, y, seconds } (the cast and what is left of the cooldown) or nil: no stone in the bags, or no bind point known.
function TV.Hearth()
    if Count(HEARTH_ITEM) <= 0 then return nil end
    local b = TV.Bind()
    if not b then return nil end
    return { cont = b.c, x = b.x, y = b.y, seconds = HEARTH_CAST + HearthCooldown() }
end

-- Why the Hearthstone isn't offered, in words (for the settings), or nil when it is.
function TV.HearthWhy()
    if not NP.Get("useHearth") then return "Turned off." end
    if Count(HEARTH_ITEM) <= 0 then return "No Hearthstone in your bags." end
    if not TV.Bind() then return "Your bind point isn't known to TwichUI yet. Talk to an innkeeper (bind again), or use the Hearthstone once during a journey." end
    return nil
end

-- The bind event: the player is at the innkeeper. Registered only while Navigation is on.
local function OnBound()
    local ok, cont, x, y = NV.PositionNow()
    if ok then TV.SetBind(cont, x, y) end
end

---------------------------------------------------------------------------
-- What a journey is planned with
---------------------------------------------------------------------------
-- The request's travel part for nav/Journey.lua; in combat the last answer.
function TV.Request()
    if InCombatLockdown and InCombatLockdown() and cache then return cache end
    local ND = R.NavData
    local tr = ND and ND.Transit()
    local req = { faction = TV.Faction() or 1, speed = TV.Speed(), ships = NP.Get("useShips"), teleports = {} }
    if NP.Get("useFlights") then req.flights = TV.Flights() end
    if NP.Get("useTeleports") and tr then req.teleports = TV.Teleports(tr.teleports) end
    if NP.Get("useHearth") then req.hearth = TV.Hearth() end
    cache = req
    return req
end

-- Whether any travel beyond walking is on offer at all (decides whether a short trip on one continent is just walked).
function TV.Any()
    local r = TV.Request()
    return (r.ships or r.flights ~= nil or #r.teleports > 0 or r.hearth ~= nil) and true or false
end

---------------------------------------------------------------------------
-- The listener
---------------------------------------------------------------------------
local listening = false
function TV.Refresh()
    local want = NV.Enabled()
    if want and not listening then
        R:On("HEARTHSTONE_BOUND", OnBound)
        R:On("TAXIMAP_OPENED", OnTaxiMap)
        R:On("TAXI_NODE_STATUS_CHANGED", OnTaxiMap)
        listening = true
    elseif not want and listening then
        R:Off("HEARTHSTONE_BOUND", OnBound)
        R:Off("TAXIMAP_OPENED", OnTaxiMap)
        R:Off("TAXI_NODE_STATUS_CHANGED", OnTaxiMap)
        listening = false
        cache = nil
    end
end
NV.Subscribe(function(event) if event == "prefs" then TV.Refresh() end end)
R:On("PLAYER_LOGIN", TV.Refresh)

function TV.Diagnostics()
    local b = TV.Bind()
    return { listening = listening, bindKnown = b ~= nil, flightPoints = TV.FlightCount(), hearthWhy = TV.HearthWhy() ~= nil }
end
