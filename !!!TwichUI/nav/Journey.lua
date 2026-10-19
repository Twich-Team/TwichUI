-- TwichUI: Navigation, planning a journey across continents
-- The cheapest way, by estimated seconds, from where you are to a destination, using what you have: walking, the flights you
-- have learned, boats and zeppelins, Mage teleports you know (and have a rune for), and your Hearthstone. No frames. The
-- result is a list of legs: walk, flight, ferry (boat or zeppelin), teleport, hearth. Nothing here moves, casts or
-- interacts; a leg is words and places, and what the player does with it is theirs.
--
-- The model (all of it estimates, and the interface says so):
--   * Walking: nav/Route.lua's weighted yards (water costs more), divided by a ground speed (7 yd/s on foot; a mount setting
--     scales it). Walking between places on one map is the precomputed cost from the bake; from your position, the
--     destination and the Hearthstone's bind point it is searched at plan time from each, over the crossing graph.
--   * Flights: the sum of the taxi paths' lengths at the bake's flight speed, plus BOARD seconds. Only between flight points
--     the game says you have learned (the caller passes the set), and only for your faction.
--   * Boats and zeppelins: the ride's length at the bake's ship or zeppelin speed, plus the expected wait for the next one:
--     a transport visits a dock once a cycle and stays `dwell` seconds, so someone arriving at a random moment waits
--     (cycle - dwell)^2 / (2 cycle) on average. Where the transport is now is not known; ride times seen by the player
--     replace the estimate when the caller passes them (req.ride).
--   * Teleports: the cast time plus RUNE_BIAS (it costs a reagent: not worth it to save a few seconds). A teleport can be cast
--     anywhere, so it is an edge from every place. It lands at the city's flight point (Darnassus: the middle of its map
--     region); the real spot may differ by some yards, and it is learned nowhere.
--   * Hearthstone: the cast time plus whatever is left of its cooldown, from anywhere, to the bind point the player's own
--     bind (or a use of it) taught TwichUI; with no known bind point it is not offered.
-- It is the cheapest under this model, not a proof of the fastest way: waits are averages, speeds are estimates, and nothing
-- about mounts, buffs or the flight master's queue is known.
--
-- req = { start = { cont, x, y }, goal = { cont, x, y }, prefer, speed, faction (1 Alliance, 2 Horde),
--         flights = { [taxi node ID] = true } or nil, ships = bool, teleports = { { spell, place, cast } ... },
--         hearth = { cont, x, y, seconds } or nil, ride = { [ "a>b" ] = seconds } or nil }
-- Result (via the job): { legs, seconds }. A leg is { kind, seconds, from, to, cont, fx, fy, tx, ty, fromName, toName, ... }
-- where from and to are place IDs, or "S" (your position), "G" (the destination) or "H" (the bind point).

local R = TwichUI
local ND, RT = R.NavData, R.NavRoute
local J = {}
R.NavJourney = J

J.BOARD = 12            -- seconds to reach a flight master's or a dock's boarding spot and get aboard
J.RUNE_BIAS = 20        -- seconds a teleport counts for beyond its cast: it uses a reagent
J.MULTI_YARDS = 700     -- a trip on one continent shorter than this in a straight line is simply walked
J.GROUND_SPEED = 7      -- yards a second on foot

local huge = math.huge

-- Whether a place's faction mask (1 Alliance, 2 Horde, 3 both) lets a player of `faction` use it (Lua 5.1 has no bit operators).
local function Allows(mask, faction) return mask == 3 or mask == faction end
J.Allows = Allows

function J.WaitSeconds(f)
    return (f.cycle - f.dwell) ^ 2 / (2 * f.cycle)
end

-- "about 3 min" / "under a minute" for an estimate in seconds
function J.Minutes(seconds)
    if seconds < 45 then return "under a minute" end
    local m = math.floor(seconds / 60 + 0.5)
    if m < 60 then return ("about %d min"):format(math.max(1, m)) end
    return ("about %dh %02d min"):format(math.floor(m / 60), m % 60)
end

local function Plan(req)
    local tr = ND.Transit()
    local S, G = req.start, req.goal
    local speed = req.speed or J.GROUND_SPEED
    local graphs = {}
    local function Graph(c)
        if graphs[c] == nil then graphs[c] = (ND.HasMap(c) and ND.Graph(c)) or false end
        return graphs[c] or nil
    end

    -- Where you are, the destination and the bind point, joined to their maps
    local aS = Graph(S.cont) and RT.AttachOf(S.cont, S.x, S.y, req.prefer, RT.START_REACH, RT.LAND_REACH) or nil
    local aG = Graph(G.cont) and RT.AttachOf(G.cont, G.x, G.y, nil, RT.GOAL_REACH) or nil
    local H = req.hearth
    local aH = H and Graph(H.cont) and RT.AttachOf(H.cont, H.x, H.y, nil, RT.GOAL_REACH) or nil
    if H and not aH then H = nil end
    RT.Pause()
    if not aG then return nil, Graph(G.cont) and "goal-off" or "no-data" end

    local function Targets(cont, extra)
        local t = {}
        local g = Graph(cont)
        if g then for id, e in pairs(g.place) do t[id] = e end end
        for k, v in pairs(extra) do t[k] = v end
        return t
    end
    local costS, costH = {}, {}
    if aS then
        costS = RT.CostsFrom(S.cont, aS, Targets(S.cont, (G.cont == S.cont) and { G = aG } or {}))
        RT.Pause()
    end
    local costG = RT.CostsFrom(G.cont, aG, Targets(G.cont, {}))
    RT.Pause()
    if aH then
        costH = RT.CostsFrom(H.cont, aH, Targets(H.cont, (G.cont == H.cont) and { G = aG } or {}))
        RT.Pause()
    end

    -- The search: nodes are place IDs and "S", "G", "H"
    local dist, prev, done = { S = 0 }, {}, {}
    local order = { "S" }
    local function Visit(u)
        done[u] = true
        local du = dist[u]
        local function Try(v, cost, kind, info)
            local nd = du + cost
            if nd < (dist[v] or huge) then
                if dist[v] == nil then order[#order + 1] = v end
                dist[v] = nd
                prev[v] = { u = u, kind = kind, info = info, seconds = cost }
            end
        end
        -- walking
        local from = (u == "S" and costS) or (u == "H" and costH) or nil
        if from then
            for v, c in pairs(from) do Try(v, c / speed, "walk") end
        elseif u ~= "G" then
            local pl = tr and tr.place[u]
            local g = pl and Graph(pl.cont)
            local w = g and g.walk[u]
            if w then for v, c in pairs(w) do Try(v, c / speed, "walk") end end
            if pl and pl.cont == G.cont and costG[u] then Try("G", costG[u] / speed, "walk") end
        end
        if not tr then return end
        -- rides, from a place
        if type(u) == "number" then
            local pl = tr.place[u]
            if req.flights and Allows(pl.faction, req.faction) and req.flights[pl.node] then
                for _, f in ipairs(tr.flightsFrom[u] or {}) do
                    local to = tr.place[f.b]
                    if Allows(to.faction, req.faction) and req.flights[to.node] then
                        Try(f.b, f.seconds + J.BOARD, "flight", f)
                    end
                end
            end
            if req.ships then
                for _, f in ipairs(tr.ferriesFrom[u] or {}) do
                    local to = tr.place[f.b]
                    if Allows(pl.faction, req.faction) and Allows(to.faction, req.faction) then
                        local travel = req.ride and req.ride[f.a .. ">" .. f.b] or f.travel
                        Try(f.b, J.WaitSeconds(f) + travel + J.BOARD, "ferry", f)
                    end
                end
            end
        end
        -- teleports and the Hearthstone can be used anywhere
        if u ~= "G" then
            for _, t in ipairs(req.teleports or {}) do
                if tr.place[t.place] then Try(t.place, t.cast + J.RUNE_BIAS, "teleport", t) end   -- a landing the data doesn't know is skipped
            end
            if H and u ~= "H" then Try("H", H.seconds, "hearth", H) end
        end
    end
    -- Dijkstra over a few hundred nodes: the cheapest unvisited one each time
    local steps = 0
    while true do
        local best, bu = huge, nil
        for i = 1, #order do
            local u = order[i]
            if not done[u] and dist[u] < best then best, bu = dist[u], u end
        end
        if not bu or bu == "G" then break end
        Visit(bu)
        steps = steps + 1
        if steps % 16 == 0 then RT.Pause() end
    end
    if not dist.G then
        if not aS and not (req.teleports and #req.teleports > 0) and not H then return nil, "start-off" end
        return nil, (S.cont ~= G.cont) and "other-continent" or "unreachable"
    end

    -- The legs, in order
    local edges, v = {}, "G"
    while v ~= "S" do
        local e = prev[v]
        e.to = v
        table.insert(edges, 1, e)
        v = e.u
    end
    local function Point(n)
        if n == "S" then return S.cont, S.x, S.y end
        if n == "G" then return G.cont, G.x, G.y end
        if n == "H" then return H.cont, H.x, H.y end
        local cont, x, y = ND.Stand(n)
        return cont, x, y
    end
    local function Name(n)
        if n == "S" then return "where you are" end
        if n == "G" then return "the destination" end
        if n == "H" then return "your bind point" end
        local pl = tr.place[n]
        return pl and pl.town or "?"
    end
    local legs = {}
    for _, e in ipairs(edges) do
        local last = legs[#legs]
        if e.kind == "walk" then
            if last and last.kind == "walk" then
                last.seconds, last.to = last.seconds + e.seconds, e.to
            else
                legs[#legs + 1] = { kind = "walk", seconds = e.seconds, from = e.u, to = e.to }
            end
        elseif e.kind == "flight" then
            if last and last.kind == "flight" then
                last.via[#last.via + 1] = Name(last.to)
                last.seconds, last.to = last.seconds + e.seconds, e.to
            else
                legs[#legs + 1] = { kind = "flight", seconds = e.seconds, from = e.u, to = e.to, via = {} }
            end
        elseif e.kind == "ferry" then
            local f = e.info
            legs[#legs + 1] = { kind = "ferry", seconds = e.seconds, from = e.u, to = e.to,
                transport = f.kind == 2 and "zeppelin" or "boat", travel = req.ride and req.ride[f.a .. ">" .. f.b] or f.travel,
                wait = J.WaitSeconds(f) }
        elseif e.kind == "teleport" then
            legs[#legs + 1] = { kind = "teleport", seconds = e.info.cast, from = e.u, to = e.to, spell = e.info.spell }
        else
            legs[#legs + 1] = { kind = "hearth", seconds = e.seconds, from = e.u, to = e.to }
        end
    end
    for _, leg in ipairs(legs) do
        local fc, fx, fy = Point(leg.from)
        local tc, tx, ty = Point(leg.to)
        leg.cont, leg.fcont, leg.fx, leg.fy, leg.tcont, leg.tx, leg.ty = tc, fc, fx, fy, tc, tx, ty
        if leg.kind == "walk" then leg.cont = fc end
        leg.fromName, leg.toName = Name(leg.from), Name(leg.to)
    end
    -- what a walk ends at, in words: the boat's dock, the zeppelin's tower, the flight master
    for i, leg in ipairs(legs) do
        local nxt = legs[i + 1]
        leg.toLabel = leg.toName
        if leg.kind == "walk" and nxt then
            if nxt.kind == "ferry" then
                leg.toLabel = leg.toName .. (nxt.transport == "zeppelin" and " zeppelin tower" or " dock")
            elseif nxt.kind == "flight" then
                leg.toLabel = leg.toName .. " flight master"
            end
        end
    end
    return { legs = legs, seconds = dist.G, walkOnly = (#legs == 1 and legs[1].kind == "walk") }
end

-- A planning job (nav/Route.lua's RT.Job): job:Step(ms) -> "running" | "done", journey | "failed", reason
function J.Plan(req)
    return RT.Job(function() return Plan(req) end)
end

-- At once (tests and tools; never from a game handler).
function J.PlanNow(req)
    return Plan(req)
end
