-- TwichUI: Navigation, what this character can use to get there
-- Read when a journey is planned (nav/Journey.lua), never polled. Everything but the Hearthstone's bind point is the game's to
-- say at that moment:
--   Flights    the flight points the character has learned: C_TaxiMap.GetTaxiNodesForMap's `isUndiscovered` is false. It needs
--              no flight master. Asked of the continents' maps and of the player's own map and its parents, whichever the
--              game gives nodes for.
--   Teleports  the Mage's teleports Forever teaches (modules/MageTravel.lua's list): the spell is known, and a Rune of
--              Teleportation is in the bags. The spell is never cast by TwichUI; the journey says to.
--   Hearthstone  the item is in the bags; its cooldown (what is left of it counts as time); and the bind point.
--   Faction    UnitFactionGroup.
-- The bind point: the game tells an addon only the bind place's name (GetBindLocation), so TwichUI keeps where the player
-- stood when the HEARTHSTONE_BOUND event fired (at the innkeeper), or where a Hearthstone journey landed. It is a record
-- of this character (TwichUIDB.ui.navTravel[guid].bind, account-wide, never in a profile or shared). Without one the
-- Hearthstone is not offered, and the settings say so. One listener, for that event, exists only while Navigation is on.
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
-- { [taxi node ID] = true } for the learned flight points, or nil when the game gives none.
function TV.Flights()
    if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then return nil end
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
    local set, any = {}, false
    for _, map in ipairs(maps) do
        local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, map)
        if ok and type(nodes) == "table" then
            for _, n in ipairs(nodes) do
                local node = Plain(n.nodeID)
                if node and n.isUndiscovered == false then set[node] = true any = true end
            end
        end
    end
    return any and set or nil
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
local function Record(create)
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
        listening = true
    elseif not want and listening then
        R:Off("HEARTHSTONE_BOUND", OnBound)
        listening = false
        cache = nil
    end
end
NV.Subscribe(function(event) if event == "prefs" then TV.Refresh() end end)
R:On("PLAYER_LOGIN", TV.Refresh)

function TV.Diagnostics()
    local b = TV.Bind()
    return { listening = listening, bindKnown = b ~= nil, hearthWhy = TV.HearthWhy() ~= nil }
end
