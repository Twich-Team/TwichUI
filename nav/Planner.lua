-- TwichUI: navigation, choosing a route
-- The fastest estimated way from one place to another on the same continent, using what navigation
-- supports: walking, and flights between the flight points you know. No game calls happen here, so it
-- can be checked offline; the journey (nav/Journey.lua) gathers what it needs and passes it in.
--
-- How it estimates:
--   * Walking is measured in a straight line at your current run speed. The game gives no walking paths,
--     so a walking time is a minimum: hills, walls and water can only make it longer.
--   * A flight costs what nav/Flights.lua says, plus BOARDING for talking to the flight master and taking
--     off. You walk to a flight point, fly, then walk on; one flight per route (the flight master already
--     chains the stops of a longer flight).
-- The search is Dijkstra's, over "standing at a place, having walked or flown there". Flight costs are
-- asked for only as the search reaches a flight point, and kept by Flights.lua between plans.

local R = TwichUI
local NP = {}
R.NavPlanner = NP

NP.BOARDING = 10   -- seconds: an allowance (assumed, not measured) for the flight master and take-off

local WALKED, FLEW = 0, 1

local function Distance(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

-- q = {
--   fromX, fromY, toX, toY,          -- world yards on one continent
--   runSpeed,                         -- yards a second, > 0
--   nodes = { { id, x, y, name }, ... },   -- flight points you can use
--   flightCost = function(a, b) -> seconds or nil,
--   flightDetail = function(a, b) -> { seconds, confirmed, learned, points } or nil,
-- }
-- Returns { seconds, legs, minimum } or nil when q can't be planned. Each leg:
--   walk:   { mode = "walk", fromX, fromY, toX, toY, seconds, minimum = true, toNode (a node, or nil for the goal) }
--   flight: { mode = "flight", fromX, fromY, toX, toY, seconds, fromNode, toNode, confirmed, learned, points }
function NP.Plan(q)
    if type(q) ~= "table" then return nil end
    for _, k in ipairs({ "fromX", "fromY", "toX", "toY", "runSpeed" }) do
        local v = q[k]
        if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
    end
    if q.runSpeed <= 0 then return nil end
    local nodes = q.nodes or {}
    local speed = q.runSpeed
    local n = #nodes
    -- States: 1 = start, 2 = goal, then each node twice (walked there, flew there).
    local GOAL = 2
    local function State(i, how) return 2 + (i - 1) * 2 + how + 1 end
    local count = 2 + n * 2
    local cost, prev, via, done = {}, {}, {}, {}
    for s = 1, count do cost[s] = math.huge end
    cost[1] = 0
    local function Relax(from, to, c, edge)
        local total = cost[from] + c
        if total < cost[to] then cost[to], prev[to], via[to] = total, from, edge end
    end
    for _ = 1, count do
        local s, best = nil, math.huge
        for i = 1, count do
            if not done[i] and cost[i] < best then s, best = i, cost[i] end
        end
        if not s or s == GOAL then break end
        done[s] = true
        if s == 1 then
            Relax(1, GOAL, Distance(q.fromX, q.fromY, q.toX, q.toY) / speed, "walk")
            for i = 1, n do
                Relax(1, State(i, WALKED), Distance(q.fromX, q.fromY, nodes[i].x, nodes[i].y) / speed, "walk")
            end
        else
            local i = math.floor((s - 3) / 2) + 1
            local how = (s - 3) % 2
            local node = nodes[i]
            if how == WALKED then
                for j = 1, n do
                    if j ~= i and not done[State(j, FLEW)] then
                        local c = q.flightCost and q.flightCost(node.id, nodes[j].id)
                        if c then Relax(s, State(j, FLEW), c + NP.BOARDING, "flight") end
                    end
                end
            else
                Relax(s, GOAL, Distance(node.x, node.y, q.toX, q.toY) / speed, "walk")
            end
        end
    end
    if cost[GOAL] == math.huge then return nil end

    -- Back from the goal to the start, then the legs in travel order.
    local chain = {}
    local s = GOAL
    while s and s ~= 1 do
        table.insert(chain, 1, s)
        s = prev[s]
    end
    local function Place(st)
        if st == 1 then return q.fromX, q.fromY, nil end
        if st == GOAL then return q.toX, q.toY, nil end
        local node = nodes[math.floor((st - 3) / 2) + 1]
        return node.x, node.y, node
    end
    local legs, from = {}, 1
    for _, st in ipairs(chain) do
        local fx, fy, fromNode = Place(from)
        local tx, ty, toNode = Place(st)
        local leg
        if via[st] == "flight" then
            local detail = q.flightDetail and q.flightDetail(fromNode.id, toNode.id)
            if not detail then return nil end
            leg = { mode = "flight", fromX = fx, fromY = fy, toX = tx, toY = ty, seconds = detail.seconds + NP.BOARDING,
                fromNode = fromNode, toNode = toNode, confirmed = detail.confirmed, learned = detail.learned,
                points = detail.points }
        else
            leg = { mode = "walk", fromX = fx, fromY = fy, toX = tx, toY = ty, minimum = true, toNode = toNode,
                seconds = Distance(fx, fy, tx, ty) / speed }
        end
        legs[#legs + 1] = leg
        from = st
    end
    local total, minimum = 0, false
    for _, leg in ipairs(legs) do
        total = total + leg.seconds
        if leg.minimum then minimum = true end
    end
    return { seconds = total, legs = legs, minimum = minimum }
end
