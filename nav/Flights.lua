-- TwichUI: navigation, flight paths
-- What the game says about flight paths, and what navigation learns from them while it is on.
--
--   * Where the flight points are and their faction: asked of the game (C_TaxiMap.GetTaxiNodesForMap)
--     when a route is planned, never stored.
--   * Which flight points this character has: only a flight master's map tells this reliably. The world
--     map's list marks undiscovered points too, but in this client that mark has been seen to call points
--     found that the character doesn't have, so it isn't used to plan. When a flight master's map opens,
--     the points it lists as current or reachable are noted as this character's (nav/Data.lua); points it
--     lists as unreachable are not (Blizzard's own flight map hides those). Until this character has opened
--     a flight master's map on a continent, no flights are planned there, and the route says why.
--   * Which stops a flight passes through: also only a flight master's map. When one opens, the route to
--     every destination it offers is noted.
--   * How long a flight takes: when you choose a destination at a flight master and then fly, the time
--     from take-off to landing is noted for that route.
--
-- A route not yet seen at a flight master is assumed to be a direct flight between the two points, and
-- its time is worked out from the flight speed your own measured flights show (an assumed speed until
-- you have flown once). The journey says so when it uses one. Nothing here takes a flight or talks to a
-- flight master for you.

local R = TwichUI
local F = {}
R.NavFlights = F

-- An assumed flight speed in yards a second, measured over the straight lines between a flight's stops,
-- used only until you have flown once. Real flights curve, so a measured speed replaces it at once.
F.PLACEHOLDER_SPEED = 30
F.MIN_SPEED, F.MAX_SPEED = 8, 120   -- a speed worked out from measured flights is kept within these
F.LANDED_NEAR = 120                 -- yards: landing this close to the chosen flight point counts as arriving
local PICK_TO_TAKEOFF = 30          -- seconds: a take-off this long after choosing a destination is that flight
local MEMO_SPAN = 65536             -- flight point IDs below this share one cost table without string keys

local stamp = 0           -- bumped when what the game says about flight points may have changed
local nodeCache = {}      -- [continent uiMapID] = { stamp, list, byId, usable }
local memo, memoKey = {}, nil
local taxi                -- while a flight master's map is open: { bySlot = { [slot] = nodeID }, current = nodeID }
local pending             -- the flight just chosen: { hops, to, chosenAt, startedAt }
local hooked = false
local active = {}         -- [event] = handler, while registered
local last = { scan = "none", scanRoutes = 0, scanKnown = 0, flight = "none" }   -- codes and counts for the report

local function W() return R.NavWorld end
local function ND() return R.NavData end

local function Text(v)
    if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) or v == "" then return nil end
    return v
end

-- Whether this character may use a flight point of this faction.
local function FactionOK(faction)
    local E = Enum and Enum.FlightPathFaction
    local neutral, horde, alliance = E and E.Neutral or 0, E and E.Horde or 1, E and E.Alliance or 2
    if faction == nil or faction == neutral then return true end
    local mine = UnitFactionGroup and UnitFactionGroup("player")
    if faction == horde then return mine == "Horde" end
    if faction == alliance then return mine == "Alliance" end
    return false
end

---------------------------------------------------------------------------
-- Flight points on a continent
---------------------------------------------------------------------------
local function AddNodes(list, byId, uiMapID)
    local found = C_TaxiMap.GetTaxiNodesForMap(uiMapID)
    if type(found) ~= "table" then return end
    local Plain = W().Plain
    for _, info in ipairs(found) do
        local id = type(info) == "table" and Plain(info.nodeID)
        local mx, my = W().XY(id and info.position)
        if id and not byId[id] and mx then
            local p = W().FromMap(uiMapID, mx, my)
            if p then
                local node = { id = id, name = Text(info.name), map = p.map, x = p.x, y = p.y,
                    undiscovered = info.isUndiscovered == true, usable = FactionOK(info.faction) }
                list[#list + 1] = node
                byId[id] = node
            end
        end
    end
end

-- Every flight point the game places on this continent, and the ones this character can fly from and
-- to (listed as theirs by a flight master's map, and of its faction or neutral). Asked of the game once,
-- then kept until something changes.
function F.Nodes(continent)
    local entry = nodeCache[continent or 0]
    local rev = ND().Revision()
    if entry and entry.stamp == stamp and entry.rev == rev then return entry.list, entry.byId, entry.usable end
    local list, byId, usable = {}, {}, {}
    if continent and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
        AddNodes(list, byId, continent)
        -- A continent map that shows no flight points: ask its zones instead.
        if #list == 0 and C_Map and C_Map.GetMapChildrenInfo then
            local zone = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
            for _, child in ipairs(C_Map.GetMapChildrenInfo(continent, zone, false) or {}) do
                if type(child) == "table" and W().Plain(child.mapID) then AddNodes(list, byId, child.mapID) end
            end
        end
    end
    local known = ND().Known()
    for _, node in ipairs(list) do
        node.known = known[node.id] ~= nil
        if node.usable and node.known then usable[#usable + 1] = node end
    end
    nodeCache[continent or 0] = { stamp = stamp, rev = rev, list = list, byId = byId, usable = usable }
    return list, byId, usable
end

---------------------------------------------------------------------------
-- How long a flight takes
---------------------------------------------------------------------------
-- Yards along a flight's stops, straight between them; nil when a stop isn't on this continent.
local function HopsLength(hops, byId)
    local total = 0
    for i = 2, #hops do
        local a, b = byId[hops[i - 1]], byId[hops[i]]
        if not (a and b) then return nil end
        total = total + W().Distance(a.x, a.y, b.x, b.y)
    end
    return total
end

-- The flight speed your measured flights on this continent show, or the assumed one.
local function Speed(byId)
    local yards, seconds = 0, 0
    ND().EachTime(function(hops, s)
        local length = HopsLength(hops, byId)
        if length and length > 0 then yards, seconds = yards + length, seconds + s end
    end)
    if seconds > 0 and yards > 0 then
        return math.min(F.MAX_SPEED, math.max(F.MIN_SPEED, yards / seconds)), true
    end
    return F.PLACEHOLDER_SPEED, false
end

-- What a plan needs about flights on a continent: { usable, byId, speed, speedLearned }. Costs worked
-- out for it are kept until the flight points or the learned data change, so planning again while
-- you walk costs little.
function F.Prepare(continent)
    local _, byId, usable = F.Nodes(continent)
    local key = stamp .. ":" .. ND().Revision() .. ":" .. tostring(continent)
    if key ~= memoKey then
        memo, memoKey = {}, key
        memo.speed, memo.speedLearned = Speed(byId)
    end
    -- No flight point of this character's known on this continent yet: flights can't be planned here.
    return { usable = usable, byId = byId, speed = memo.speed, speedLearned = memo.speedLearned, noneKnown = #usable == 0 }
end

-- One flight from a to b: seconds, whether the route was seen at a flight master with every stop known
-- to you (confirmed), whether its time was measured (learned), and its stops (nil when assumed direct).
local function Evaluate(ctx, a, b)
    local A, B = ctx.byId[a], ctx.byId[b]
    if not (A and B) or a == b then return nil end
    local hops = ND().Route(a, b)
    local confirmed = hops ~= nil
    if hops then
        for i = 1, #hops do
            local n = ctx.byId[hops[i]]
            if not (n and n.known) then confirmed = false break end
        end
    end
    if not confirmed then hops = nil end
    local length = hops and HopsLength(hops, ctx.byId) or W().Distance(A.x, A.y, B.x, B.y)
    local measured = hops and ND().Time(hops)
    return measured or (length / ctx.speed), confirmed, measured ~= nil, hops
end

-- Seconds for the flight from a to b, or nil. Kept, so asking again is cheap.
function F.Cost(ctx, a, b)
    if a < MEMO_SPAN and b < MEMO_SPAN then
        local k = a * MEMO_SPAN + b
        local v = memo[k]
        if v == nil then
            v = Evaluate(ctx, a, b) or false
            memo[k] = v
        end
        return v or nil
    end
    return (Evaluate(ctx, a, b))
end

-- The flight from a to b in full, for a plan's chosen route: { seconds, confirmed, learned, points }
-- where points is { x1, y1, x2, y2, ... } through each stop.
function F.Detail(ctx, a, b)
    local seconds, confirmed, learned, hops = Evaluate(ctx, a, b)
    if not seconds then return nil end
    local points = {}
    local ids = hops or { a, b }
    for i = 1, #ids do
        local n = ctx.byId[ids[i]]
        points[#points + 1], points[#points + 2] = n.x, n.y
    end
    return { seconds = seconds, confirmed = confirmed, learned = learned, points = points }
end

---------------------------------------------------------------------------
-- Learning at a flight master
---------------------------------------------------------------------------
-- The stops from the flight master you stand at to the destination in this slot, as flight point IDs.
local function HopsTo(slot, bySlot)
    local Plain = W().Plain
    local count = Plain(GetNumRoutes(slot))
    if not count or count < 1 or count > ND().MAX_HOPS - 1 then return nil end
    local hops = {}
    for r = 1, count do
        local src = bySlot[Plain(TaxiGetNodeSlot(slot, r, true)) or -1]
        local dst = bySlot[Plain(TaxiGetNodeSlot(slot, r, false)) or -1]
        if not (src and dst) then return nil end
        if r == 1 then hops[1] = src elseif hops[#hops] ~= src then return nil end
        hops[#hops + 1] = dst
    end
    return hops
end

local function TaxiMapID()
    local Plain = W().Plain
    local id = GetTaxiMapID and Plain(GetTaxiMapID())
    if id and id > 0 then return id end
    return W().PlayerContinent()   -- not every client says which map the flight master's map is
end

local function Scan()
    taxi = nil
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and GetNumRoutes and TaxiGetNodeSlot) then
        last.scan = "unavailable"
        return
    end
    local mapID = TaxiMapID()
    local nodes = mapID and C_TaxiMap.GetAllTaxiNodes(mapID)
    if type(nodes) ~= "table" or #nodes == 0 then last.scan = "no-nodes" return end
    local Plain = W().Plain
    local E = Enum and Enum.FlightPathState
    local CURRENT, REACHABLE = E and E.Current or 0, E and E.Reachable or 1
    local bySlot, current = {}, nil
    for _, n in ipairs(nodes) do
        local slot, id = type(n) == "table" and Plain(n.slotIndex), type(n) == "table" and Plain(n.nodeID)
        if slot and id then
            bySlot[slot] = id
            if n.state == CURRENT then current = id end
        end
    end
    if not current then last.scan = "no-current" return end
    -- The flight points this map lists as yours: the one you stand at, and every one you can fly to.
    local mine = {}
    for _, n in ipairs(nodes) do
        if type(n) == "table" and (n.state == CURRENT or n.state == REACHABLE) and bySlot[n.slotIndex] then
            mine[#mine + 1] = bySlot[n.slotIndex]
        end
    end
    last.scanKnown = #mine
    ND().AddKnown(mine)
    local learned = 0
    for _, n in ipairs(nodes) do
        if type(n) == "table" and n.state == REACHABLE and bySlot[n.slotIndex] then
            local hops = HopsTo(n.slotIndex, bySlot)
            if hops and hops[1] == current and hops[#hops] == bySlot[n.slotIndex] and ND().SetRoute(current, hops[#hops], hops) then
                learned = learned + 1
            end
        end
    end
    taxi = { bySlot = bySlot, current = current }
    last.scan, last.scanRoutes = learned > 0 and "learned" or "no-routes", learned
end

-- TakeTaxiNode is how both of the game's flight master windows start a flight. Watched (never changed)
-- to know which destination was chosen.
local function OnTakeTaxi(slot)
    if not (R:Enabled("navigation") and taxi) then return end
    local to = taxi.bySlot[slot]
    local hops = to and HopsTo(slot, taxi.bySlot)
    if hops and hops[#hops] == to then
        pending = { hops = hops, to = to, chosenAt = GetTime() }
    end
end

local function OnTakeoff()
    if pending and not pending.startedAt and GetTime() - pending.chosenAt <= PICK_TO_TAKEOFF then
        pending.startedAt = GetTime()
    end
end

local function OnLanding()
    if not (pending and pending.startedAt) then return end
    if UnitOnTaxi and UnitOnTaxi("player") then return end   -- control came back mid-flight: still flying
    local flight = pending
    pending = nil
    local seconds = GetTime() - flight.startedAt
    local x, y = W().Here()
    local _, byId = F.Nodes(W().PlayerContinent())
    local dest = byId[flight.to]
    if not (x and dest) or W().Distance(x, y, dest.x, dest.y) > F.LANDED_NEAR then
        last.flight = "landed-elsewhere"
        return
    end
    last.flight = ND().AddTime(flight.hops, seconds) and "timed" or "out-of-range"
end

local function Changed() stamp = stamp + 1 end
local function OnTaxiOpened() Changed(); Scan() end
local function OnTaxiClosed() taxi = nil; Changed() end
local function OnEnteringWorld()
    Changed()
    if pending and not (UnitOnTaxi and UnitOnTaxi("player")) then pending = nil end   -- a loading screen ends any watch
end

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

-- Listens only while navigation is on. Safe to call any number of times.
function F.Refresh()
    local on = R:Enabled("navigation")
    Want("TAXIMAP_OPENED", OnTaxiOpened, on)
    Want("TAXIMAP_CLOSED", OnTaxiClosed, on)
    Want("TAXI_NODE_STATUS_CHANGED", Changed, on)
    Want("PLAYER_CONTROL_LOST", OnTakeoff, on)
    Want("PLAYER_CONTROL_GAINED", OnLanding, on)
    Want("PLAYER_ENTERING_WORLD", OnEnteringWorld, on)
    if not on then taxi, pending = nil, nil end
    if not hooked and hooksecurefunc and TakeTaxiNode then
        hooked = true   -- a hook can't be removed: it checks the setting each time
        hooksecurefunc("TakeTaxiNode", OnTakeTaxi)
    end
    Changed()
end

-- On the player's continent: flight points the game places, how many the world map's list calls found,
-- and how many a flight master's map has listed as this character's. Counts only.
function F.Counts()
    local list = F.Nodes(W().PlayerContinent())
    local placed, gameFound, known = #list, 0, 0
    for _, node in ipairs(list) do
        if node.usable and not node.undiscovered then gameFound = gameFound + 1 end
        if node.usable and node.known then known = known + 1 end
    end
    return { placed = placed, gameFound = gameFound, known = known }
end

-- Codes and counts only, for the troubleshooting report.
function F.Snapshot()
    local events = {}
    for e in pairs(active) do events[#events + 1] = e end
    table.sort(events)
    return {
        events = events, hooked = hooked, taxiOpen = taxi ~= nil, watching = pending ~= nil,
        flying = pending ~= nil and pending.startedAt ~= nil, lastScan = last.scan, lastScanRoutes = last.scanRoutes,
        lastFlight = last.flight, speedLearned = memo.speedLearned == true, lastScanKnown = last.scanKnown,
        here = F.Counts(),
    }
end

R:OnInit(F.Refresh)
