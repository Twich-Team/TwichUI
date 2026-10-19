-- TwichUI: Navigation, planning a walking route
-- A route from one point to another on the same continent, over the baked walking maps (nav/Data.lua). No frames.
--
-- What "best" means here. Moving through a polygon costs its 2D distance times its area's factor (ground 1, swimming 3,
-- ocean 5), measured between the midpoints of the edges a route passes through, the way Recast's Detour measures (and
-- the bake's own tools/navbake/pack.py, which precomputed the costs between tile crossings with the same model). The
-- planner finds the cheapest route under that model through the crossings between tiles, then the cheapest polygons
-- inside each tile between them, and pulls the result tight (the funnel algorithm) so it turns only at corners. It is the
-- lowest-cost route the walking map supports at that granularity, not a proof of the shortest or fastest path: a
-- crossing stands for up to 128 yards of tile edge, and midpoints are an estimate. Height, slopes, mounts, speed buffs and
-- creatures are not modelled. There is no travel time.
--
--   Searches run as a job (RT.Plan) a few milliseconds a frame (budget set by the caller), so a long route never stalls
--   the game. A job is dropped, not finished, when a newer request replaces it (Nav.lua keeps only the newest).
--   Failure reasons: "no-data" (this continent has no walking map), "start-off" (no walkable ground near you), "goal-off"
--   (none near the destination), "unreachable" (no walkable connection between them, e.g. an island or another floor the
--   map does not connect), "limit" (the search grew past its bound).

local R = TwichUI
local ND = R.NavData
local RT = {}
R.NavRoute = RT

local sqrt, huge, floor = math.sqrt, math.huge, math.floor
local yield, running = coroutine.yield, coroutine.running

RT.START_REACH = 12          -- yards: how far you may stand from walkable ground and still be put on it
RT.GOAL_REACH = 40           -- yards: how far a destination may be from walkable ground (a pin on a roof, in a lake's middle)
RT.TILE_LIMIT = 30000        -- polygons settled in one tile search
RT.GRAPH_LIMIT = 60000       -- crossings settled in one search

local FACTOR = ND.FACTOR

---------------------------------------------------------------------------
-- Budget: a search yields when the frame's share is used up (inside a job only)
---------------------------------------------------------------------------
local deadline = huge
local function Pause()
    if running() and debugprofilestop() > deadline then yield() end
end

---------------------------------------------------------------------------
-- A binary heap on parallel arrays, reused
---------------------------------------------------------------------------
local function NewHeap() return { k = {}, v = {}, n = 0 } end

local function Push(h, key, val)
    local n = h.n + 1
    h.n = n
    local K, V = h.k, h.v
    local i = n
    while i > 1 do
        local p = floor(i / 2)
        if K[p] <= key then break end
        K[i], V[i] = K[p], V[p]
        i = p
    end
    K[i], V[i] = key, val
end

local function Pop(h)
    local n = h.n
    if n == 0 then return nil end
    local K, V = h.k, h.v
    local topK, topV = K[1], V[1]
    local lastK, lastV = K[n], V[n]
    K[n], V[n] = nil, nil
    n = n - 1
    h.n = n
    if n > 0 then
        local i = 1
        while true do
            local l = i * 2
            if l > n then break end
            local r = l + 1
            local c = (r <= n and K[r] < K[l]) and r or l
            if K[c] >= lastK then break end
            K[i], V[i] = K[c], V[c]
            i = c
        end
        K[i], V[i] = lastK, lastV
    end
    return topV, topK
end

---------------------------------------------------------------------------
-- Inside one tile
---------------------------------------------------------------------------
local function EdgeMid(t, p, j)
    local n = t.pn[p]
    local a = t.ev[t.pk[p] + j]
    local b = t.ev[t.pk[p] + ((j + 1) % n)]
    return (t.X[a] + t.X[b]) / 2, (t.Y[a] + t.Y[b]) / 2
end

-- From a point in startPoly over tile t. With goalPoly: A* to it (returns the polygons, the edge each was entered by,
-- and the cost); without: every polygon's cost (Dijkstra), as tables g[p], gx[p], gy[p].
local function TileSearch(t, startPoly, sx, sy, goalPoly, gx, gy)
    local g, px, py, from, fromEdge, done = {}, {}, {}, {}, {}, {}
    local heap = NewHeap()
    g[startPoly], px[startPoly], py[startPoly] = 0, sx, sy
    Push(heap, 0, startPoly)
    local settled = 0
    local best, bestCost = nil, huge
    while true do
        local p, f = Pop(heap)
        if not p then break end
        if not done[p] then
            if goalPoly and f >= bestCost then break end
            done[p] = true
            settled = settled + 1
            if settled > RT.TILE_LIMIT then return nil, "limit" end
            if settled % 64 == 0 then Pause() end
            local gp = g[p]
            local fac = FACTOR[t.area[p]] or 1
            if goalPoly and p == goalPoly then
                local c = gp + sqrt((gx - px[p]) ^ 2 + (gy - py[p]) ^ 2) * fac
                if c < bestCost then best, bestCost = p, c end
            end
            local k0, n = t.pk[p], t.pn[p]
            for j = 0, n - 1 do
                local q = t.nb[k0 + j]
                if q ~= 0 and not done[q] then
                    local mx, my = EdgeMid(t, p, j)
                    local nd = gp + sqrt((mx - px[p]) ^ 2 + (my - py[p]) ^ 2) * fac
                    if nd < (g[q] or huge) then
                        g[q], px[q], py[q], from[q], fromEdge[q] = nd, mx, my, p, j
                        local h = 0
                        if goalPoly then h = sqrt((gx - mx) ^ 2 + (gy - my) ^ 2) end
                        Push(heap, nd + h, q)
                    end
                end
            end
        end
    end
    if not goalPoly then return g, px, py end
    if not best then return nil, "unreachable" end
    -- polygons from start to goal, and for each the edge of the previous one it was entered through
    local polys, edges = {}, {}
    local p = best
    while p do
        polys[#polys + 1] = p
        edges[#edges + 1] = fromEdge[p]
        p = from[p]
    end
    local n = #polys
    for i = 1, floor(n / 2) do
        polys[i], polys[n + 1 - i] = polys[n + 1 - i], polys[i]
        edges[i], edges[n + 1 - i] = edges[n + 1 - i], edges[i]
    end
    -- edges[i] is now the edge (of polys[i-1]) that polys[i] was entered by; edges[1] is nil
    return polys, edges, bestCost
end
RT.TileSearch = TileSearch

---------------------------------------------------------------------------
-- Across tiles
---------------------------------------------------------------------------
-- A crossing's polygon in tile id `tid`.
local function SideIn(gr, c, tid)
    if gr.ta[c] == tid then return gr.pa[c] end
    if gr.tb[c] == tid then return gr.pb[c] end
    return nil
end

-- Costs from a point to every crossing of its tile: { [c] = cost }.
local function Seeds(gr, t, poly, x, y)
    local out = {}
    local list = gr.byTile[t.id]
    if not list then return out end
    local g, px, py = TileSearch(t, poly, x, y)
    if not g then return out end
    for _, c in ipairs(list) do
        local p = SideIn(gr, c, t.id)
        if p and g[p] then
            out[c] = g[p] + sqrt((gr.cx[c] - px[p]) ^ 2 + (gr.cy[c] - py[p]) ^ 2) * (FACTOR[t.area[p]] or 1)
        end
    end
    return out
end

-- The cheapest chain of crossings: returns the list of crossings and the tile each step crossed, or nil.
local function GraphSearch(gr, seeds, goals, gx, gy, direct)
    local best, from, fromTile, done = {}, {}, {}, {}
    local heap = NewHeap()
    for c, cost in pairs(seeds) do
        best[c] = cost
        Push(heap, cost + sqrt((gr.cx[c] - gx) ^ 2 + (gr.cy[c] - gy) ^ 2), c)
    end
    local goalCost, goalVia = direct or huge, nil
    local settled = 0
    local first, nb, cost, via = gr.first, gr.nb, gr.cost, gr.via
    while true do
        local c, f = Pop(heap)
        if not c or f >= goalCost then break end
        if not done[c] then
            done[c] = true
            settled = settled + 1
            if settled > RT.GRAPH_LIMIT then return nil, "limit" end
            if settled % 128 == 0 then Pause() end
            local bc = best[c]
            local gl = goals[c]
            if gl and bc + gl < goalCost then goalCost, goalVia = bc + gl, c end
            for i = first[c], first[c + 1] - 1 do
                local d = nb[i]
                if not done[d] then
                    local nd = bc + cost[i]
                    if nd < (best[d] or huge) then
                        best[d], from[d], fromTile[d] = nd, c, via[i]
                        Push(heap, nd + sqrt((gr.cx[d] - gx) ^ 2 + (gr.cy[d] - gy) ^ 2), d)
                    end
                end
            end
        end
    end
    if not goalVia then return nil, nil, goalCost end
    local chain, tilesVia = {}, {}
    local c = goalVia
    while c do
        chain[#chain + 1] = c
        tilesVia[#tilesVia + 1] = fromTile[c]
        c = from[c]
    end
    local n = #chain
    for i = 1, floor(n / 2) do
        chain[i], chain[n + 1 - i] = chain[n + 1 - i], chain[i]
        tilesVia[i], tilesVia[n + 1 - i] = tilesVia[n + 1 - i], tilesVia[i]
    end
    -- tilesVia[i] is the tile the step into chain[i] crossed (nil for the first, which the start seeds reached)
    return chain, tilesVia, goalCost
end

---------------------------------------------------------------------------
-- The corridor: polygons in order and the portal between each pair
---------------------------------------------------------------------------
-- Portal of an edge inside a tile.
local function InnerPortal(t, p, j)
    local ax, ay, bx, by = ND.Edge(t, p, j)
    return ax, ay, bx, by
end

-- Portal between tile t's polygon p and the next tile's polygon q: the overlap of their two edges on the shared side.
local function LinkPortal(t, p, u, q)
    local k0, n = t.pk[p], t.pn[p]
    for j = 0, n - 1 do
        local k = k0 + j
        if t.lp[k] == q then
            local ax, ay, bx, by = ND.Edge(t, p, j)
            local qe = t.le[k] - 1
            local cx, cy, dx, dy = ND.Edge(u, q, qe)
            local d = t.ld[k]
            if d == 1 or d == 3 then         -- east or west side: the edge runs along x
                local lo = math.max(math.min(ax, bx), math.min(cx, dx))
                local hi = math.min(math.max(ax, bx), math.max(cx, dx))
                if hi < lo then lo, hi = (lo + hi) / 2, (lo + hi) / 2 end
                return lo, ay, hi, by
            else                             -- north or south: along y
                local lo = math.max(math.min(ay, by), math.min(cy, dy))
                local hi = math.min(math.max(ay, by), math.max(cy, dy))
                if hi < lo then lo, hi = (lo + hi) / 2, (lo + hi) / 2 end
                return ax, lo, bx, hi
            end
        end
    end
    return nil
end

-- Left and right of a portal for someone walking out of the polygon with centre (cx, cy). Planar frame: east = -y,
-- north = x, so a positive cross product is counter-clockwise.
local function Orient(cx, cy, ax, ay, bx, by)
    -- in (east, north): C = (-cy, cx), A = (-ay, ax), B = (-by, bx)
    local cr = ((-ay) - (-cy)) * (bx - cx) - (ax - cx) * ((-by) - (-cy))
    if cr > 0 then return bx, by, ax, ay end   -- counter-clockwise C -> A -> B: B is on the left
    return ax, ay, bx, by
end

-- Cross product in the planar frame (east, north) of (b - a) x (c - a): positive when c is left of a -> b.
local function Cross(ax, ay, bx, by, cx, cy)
    local ux, uy = -(by - ay), bx - ax
    local vx, vy = -(cy - ay), cx - ax
    return ux * vy - uy * vx
end
RT.Cross = Cross

-- The funnel: corners of the shortest line through the portals, from the start to the goal. portals: flat arrays of
-- left and right points (lx, ly, rx, ry), the start and goal as the first and last (degenerate) portals.
-- Returns xs, ys and, per corner, the portal it came from.
local function Funnel(lx, ly, rx, ry, n)
    local xs, ys, at = { lx[1] }, { ly[1] }, { 1 }
    local function Corner(x, y, k)
        local m = #xs
        if xs[m] == x and ys[m] == y then return end   -- a restart can reach the same apex again
        xs[m + 1], ys[m + 1], at[m + 1] = x, y, k
    end
    local apx, apy = lx[1], ly[1]
    local plx, ply, prx, pry = lx[1], ly[1], rx[1], ry[1]
    local apex, li, ri = 1, 1, 1
    local i = 2
    local guard = 0
    while i <= n do
        guard = guard + 1
        if guard > n * 4 + 16 then break end
        local nlx, nly, nrx, nry = lx[i], ly[i], rx[i], ry[i]
        local restart = false
        -- right side: narrows when the new right is left of (or on) apex -> right
        if Cross(apx, apy, prx, pry, nrx, nry) >= 0 then
            if (apx == prx and apy == pry) or Cross(apx, apy, plx, ply, nrx, nry) < 0 then
                prx, pry, ri = nrx, nry, i
            else
                Corner(plx, ply, li)
                apx, apy, apex = plx, ply, li
                plx, ply, prx, pry = apx, apy, apx, apy
                li, ri = apex, apex
                i = apex + 1
                restart = true
            end
        end
        if not restart then
            -- left side: narrows when the new left is right of (or on) apex -> left
            if Cross(apx, apy, plx, ply, nlx, nly) <= 0 then
                if (apx == plx and apy == ply) or Cross(apx, apy, prx, pry, nlx, nly) > 0 then
                    plx, ply, li = nlx, nly, i
                else
                    Corner(prx, pry, ri)
                    apx, apy, apex = prx, pry, ri
                    plx, ply, prx, pry = apx, apy, apx, apy
                    li, ri = apex, apex
                    i = apex + 1
                    restart = true
                end
            end
        end
        if not restart then i = i + 1 end
    end
    Corner(lx[n], ly[n], n)
    return xs, ys, at
end
RT.Funnel = Funnel

---------------------------------------------------------------------------
-- Planning
---------------------------------------------------------------------------
local function Plan(map, sx, sy, gx, gy, prefer)
    local gr = ND.Graph(map)
    if not gr then return nil, "no-data" end
    local st, sp, sx2, sy2 = ND.Locate(map, sx, sy, RT.START_REACH, prefer)
    if not st then return nil, "start-off" end
    local gt, gp, gx2, gy2 = ND.Locate(map, gx, gy, RT.GOAL_REACH)
    if not gt then return nil, "goal-off" end
    Pause()

    -- Same tile: the direct search first; the crossings may still be cheaper (out and back round an obstacle).
    local direct, directPolys, directEdges
    if st.id == gt.id then
        local polys, edges, cost = TileSearch(st, sp, sx2, sy2, gp, gx2, gy2)
        if polys then direct, directPolys, directEdges = cost, polys, edges end
    end

    local seeds = Seeds(gr, st, sp, sx2, sy2)
    local goals = Seeds(gr, gt, gp, gx2, gy2)
    Pause()
    -- Quick refusal: no component holds both a crossing you can reach and one the destination can.
    if not direct then
        local comps = {}
        for c in pairs(seeds) do comps[gr.comp[c] or 0] = true end
        local any = false
        for c in pairs(goals) do if comps[gr.comp[c] or 0] then any = true break end end
        if not any then return nil, "unreachable" end
    end
    local chain, tilesVia, cost = GraphSearch(gr, seeds, goals, gx2, gy2, direct)
    if chain == nil and tilesVia == "limit" then return nil, "limit" end
    if not chain and not direct then return nil, "unreachable" end

    -- The corridor: polygons in order (polyAt, tileAt) and, for the funnel, the portals between them, the start first
    -- and the goal last as points.
    local lx, ly, rx, ry = { sx2 }, { sy2 }, { sx2 }, { sy2 }
    local polyAt, tileAt = {}, {}
    local function AddPortal(t, fromPoly, ax, ay, bx, by)
        local l1, l2, r1, r2 = Orient(t.cxp[fromPoly], t.cyp[fromPoly], ax, ay, bx, by)
        lx[#lx + 1], ly[#ly + 1], rx[#rx + 1], ry[#ry + 1] = l1, l2, r1, r2
    end
    local function AddPoly(t, p)
        local n = #polyAt
        if n > 0 and polyAt[n] == p and tileAt[n] == t then return end
        polyAt[n + 1], tileAt[n + 1] = p, t
    end
    -- One tile's polygons from a leg search; the first is where the corridor already stands (or the start).
    local function AddLeg(t, polys, edges)
        AddPoly(t, polys[1])
        for i = 2, #polys do
            local ax, ay, bx, by = InnerPortal(t, polys[i - 1], edges[i])
            AddPortal(t, polys[i - 1], ax, ay, bx, by)
            AddPoly(t, polys[i])
        end
    end
    if not chain then
        AddLeg(st, directPolys, directEdges)
    else
        -- Legs between crossings. After a leg ends on a crossing you stand on it in that leg's tile; the next leg runs
        -- in the tile the graph step named, which is either the same tile or the crossing's other side (a crossing
        -- joins exactly two tiles). Only in the second case is the crossing walked over.
        local t, p, x, y = st, sp, sx2, sy2
        local standing                       -- the crossing the last leg ended on
        for i = 1, #chain + 1 do
            local c = chain[i]
            local legTile
            if c then legTile = (i == 1) and st.id or tilesVia[i] else legTile = gt.id end
            if t.id ~= legTile then
                if not standing then return nil, "unreachable" end
                local otherId = (gr.ta[standing] == t.id) and gr.tb[standing] or gr.ta[standing]
                if otherId ~= legTile then return nil, "unreachable" end
                local o = ND.TileById(map, otherId)
                local oq = o and SideIn(gr, standing, otherId)
                if not oq then return nil, "unreachable" end
                local ax, ay, bx, by = LinkPortal(t, p, o, oq)
                if not ax then ax, ay, bx, by = x, y, x, y end
                AddPortal(t, p, ax, ay, bx, by)
                AddPoly(o, oq)
                t, p = o, oq
            end
            local q, tx, ty
            if c then
                q, tx, ty = SideIn(gr, c, t.id), gr.cx[c], gr.cy[c]
                if not q then return nil, "unreachable" end
            else
                q, tx, ty = gp, gx2, gy2
            end
            local polys, edges = TileSearch(t, p, x, y, q, tx, ty)
            if not polys then return nil, edges == "limit" and "limit" or "unreachable" end
            AddLeg(t, polys, edges)
            p, x, y, standing = q, tx, ty, c
            Pause()
        end
    end
    lx[#lx + 1], ly[#ly + 1], rx[#rx + 1], ry[#ry + 1] = gx2, gy2, gx2, gy2
    local xs, ys, at = Funnel(lx, ly, rx, ry, #lx)

    -- Per segment: the yards of it in water. Funnel portal j (j >= 2) leads from polyAt[j - 1] into polyAt[j]; a segment
    -- between corners at portals a and b runs through polyAt[a] .. polyAt[b - 1], crossing portals a + 1 .. b - 1 in
    -- order, so where it crosses each one splits it into a piece per polygon.
    local swim, wet = {}, {}
    local length = 0
    local np = #polyAt
    for i = 1, #xs - 1 do
        local ax, ay, bx, by = xs[i], ys[i], xs[i + 1], ys[i + 1]
        local len = sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local a, b = math.max(1, at[i]), at[i + 1]
        local w, tPrev = 0, 0
        local dx, dy = bx - ax, by - ay
        for j = a + 1, b do
            local tj = 1
            if j < b then
                local ex, ey = rx[j] - lx[j], ry[j] - ly[j]
                local den = dx * ey - dy * ex
                if den ~= 0 then
                    tj = ((lx[j] - ax) * ey - (ly[j] - ay) * ex) / den
                    if tj < tPrev then tj = tPrev elseif tj > 1 then tj = 1 end
                else
                    tj = tPrev
                end
            end
            local k = math.min(np, j - 1)
            if k >= 1 and (tileAt[k].area[polyAt[k]] or 1) ~= 1 then w = w + (tj - tPrev) * len end
            tPrev = tj
        end
        wet[i] = w
        swim[i] = len > 0 and w * 2 > len
        length = length + len
    end
    return {
        map = map, xs = xs, ys = ys, swim = swim, wet = wet, n = #xs, length = length, cost = cost or direct,
        startX = sx2, startY = sy2, goalX = gx2, goalY = gy2,
        goalOffset = sqrt((gx2 - gx) ^ 2 + (gy2 - gy) ^ 2),
        startTile = st.id, startPoly = sp,
    }
end

-- A planning job. job:Step(ms) runs it for up to ms milliseconds: returns "running", or "done" and the route, or "failed"
-- and a reason. Dropping the job (not calling Step again) abandons it; nothing else holds its state.
function RT.Plan(map, sx, sy, gx, gy, prefer)
    local co = coroutine.create(function() return Plan(map, sx, sy, gx, gy, prefer) end)
    local job = { done = false }
    function job:Step(ms)
        if self.done then return self.status, self.result end
        deadline = debugprofilestop() + (ms or 4)
        local ok, route, why = coroutine.resume(co)
        deadline = huge
        if not ok then
            self.done, self.status, self.result = true, "failed", "error"
            R.Fault("navigation route", route)
            return self.status, self.result
        end
        if coroutine.status(co) == "dead" then
            self.done = true
            if route then self.status, self.result = "done", route
            else self.status, self.result = "failed", why or "unreachable" end
            return self.status, self.result
        end
        return "running"
    end
    return job
end

-- The same, at once (tests and tools; never from a game handler).
function RT.PlanNow(map, sx, sy, gx, gy, prefer)
    return Plan(map, sx, sy, gx, gy, prefer)
end
