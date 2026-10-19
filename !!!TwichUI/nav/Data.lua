-- TwichUI: Navigation, the walking maps
-- The walkable ground TwichUI's navigation plans on, baked offline from this client's own terrain, buildings and liquids by
-- tools/navbake (Recast, zlib licence; see tools/navbake/README.md) and shipped in TwichUI_NavData, a load-on-demand addon.
-- Nothing here guesses where you can walk: a place with no baked ground has no route.
--   Loading. TwichUI_NavData is loaded the first time a route is asked for, never in combat (ND.Load says "combat" and
--     the caller waits), never at login. Its files fill R.NavDataStore (created here, so the data addon needs no global
--     of its own) with Base64 strings: zlib-compressed CBOR, decoded by the client (C_EncodingUtil) only when needed.
--   A map's graph (the crossings between tiles, their costs and which crossings connect) is decoded once per map and
--     kept while navigation runs. A tile is decoded when a search or a locate first touches it; at most MAX_TILES stay
--     decoded (least recently used goes first). ND.Release drops every decoded table (navigation stopped, or turned off).
--   Frames: world yards on a continent, x north and y west, as the bake (tools/navbake/wowfiles.py). Nav.lua checks the
--     client gives positions in this frame before anything is planned (Nav.AxisCheck).
--   A tile's polygons are convex; their neighbours inside the tile are rebuilt here from shared edges (Recast's own
--     adjacency, which the bake does not store), and their links to the next tile come from the data (`x`).
-- No frame, no event, no timer. Runtime-only: nothing here is ever saved.

local R = TwichUI
local ND = {}
R.NavData = ND

ND.ADDON = "TwichUI_NavData"
ND.FORMAT = 2
ND.TILE = 1600 / 3
ND.ORIGIN = 32 * ND.TILE
ND.MAX_TILES = 16
ND.FACTOR = { [1] = 1, [2] = 3, [3] = 5 }    -- ground, water (swimming), ocean: as tools/navbake/pack.py

R.NavDataStore = R.NavDataStore or { graph = {}, tiles = {}, places = {} }
local Store = R.NavDataStore
Store.places = Store.places or {}

local TILE, ORIGIN = ND.TILE, ND.ORIGIN
local floor, sqrt, huge = math.floor, math.sqrt, math.huge
local BUCKETS = 8                             -- a tile's polygons are bucketed 8 x 8 for locating

local loadState = "no"                        -- "no" | "loaded" | "missing" | "disabled" | "failed" | "format"
local graphs = {}                             -- [map] = decoded graph
local tiles = {}                              -- ["m:x_y"] = decoded tile, or false (no tile there)
local lru, lruN = {}, 0                       -- keys of decoded tiles, oldest first
local stats = { decoded = 0, released = 0, failures = 0 }

---------------------------------------------------------------------------
-- Loading the data addon
---------------------------------------------------------------------------
local function AddOnState()
    local C = C_AddOns
    local exists, enabled
    if C and C.DoesAddOnExist then exists = C.DoesAddOnExist(ND.ADDON) end
    if exists == false then return "missing" end
    if C and C.GetAddOnEnableState then
        local st = C.GetAddOnEnableState(ND.ADDON, UnitName and UnitName("player") or nil)
        enabled = st == nil or st > 0
        if not enabled then return "disabled" end
    end
    return "ok"
end

-- true, or false and a reason: "combat", "missing", "disabled", "failed", "format".
function ND.Load()
    if loadState == "loaded" then return true end
    if loadState == "format" then return false, "format" end
    if InCombatLockdown and InCombatLockdown() then return false, "combat" end
    local st = AddOnState()
    if st ~= "ok" then loadState = st return false, st end
    local loaded, why
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(ND.ADDON) then
        loaded = true
    else
        loaded, why = C_AddOns.LoadAddOn(ND.ADDON)
    end
    if not loaded then
        loadState = (why == "MISSING" and "missing") or (why == "DISABLED" and "disabled") or "failed"
        return false, loadState
    end
    loadState = "loaded"
    return true
end

function ND.LoadState() return loadState end

function ND.HasMap(map)
    return loadState == "loaded" and type(Store.graph[map]) == "string"
end

---------------------------------------------------------------------------
-- Decoding
---------------------------------------------------------------------------
local function Decode(s)
    local U = C_EncodingUtil
    if not (U and U.DecodeBase64 and U.DecompressString and U.DeserializeCBOR) then return nil end
    local ok, out = pcall(function()
        local raw = U.DecompressString(U.DecodeBase64(s), Enum.CompressionMethod.Zlib)
        return raw and U.DeserializeCBOR(raw)
    end)
    if ok and type(out) == "table" then return out end
    stats.failures = stats.failures + 1
    return nil
end

local function TileId(tx, ty) return tx * 64 + ty end
ND.TileId = TileId

-- The tile a world point is in.
function ND.TileOf(x, y)
    return floor((ORIGIN - y) / TILE), floor((ORIGIN - x) / TILE)
end

-- Packed edges (tools/navbake/pack.py's CROSS_BASE and COST_BASE): neighbour, cost (weighted yards) and tile ID of an edge.
ND.CROSS_BASE, ND.COST_BASE = 16384, 8192
function ND.Edge(v)
    local nb = v % 16384
    local q = (v - nb) / 16384
    local cost = q % 8192
    return nb, cost, (q - cost) / 8192
end

-- A map's graph:
--   cells, cs (yards per cell)
--   per crossing c: ta[c], pa[c] (tile id and polygon on one side), tb[c], pb[c] (the other), cx[c], cy[c], cz[c],
--     comp[c] (connected component)
--   compArea[k]: component k's walkable area in square yards (water included); compGround[k]: its ground (not water) alone
--   adjacency: first[c] .. first[c + 1] - 1 index adj (packed edges: ND.Edge gives neighbour, cost, the tile it runs through)
--   byTile[tileId] = { crossing ids }
function ND.Graph(map)
    local g = graphs[map]
    if g ~= nil then return g or nil end
    local s = Store.graph[map]
    local d = type(s) == "string" and Decode(s)
    if not d or d.f ~= ND.FORMAT or type(d.n) ~= "table" or type(d.ad) ~= "table" or type(d.af) ~= "table" then
        if d and d.f ~= ND.FORMAT then loadState = "format" end
        graphs[map] = false
        return nil
    end
    g = { cells = d.cells, cs = TILE / d.cells, ta = {}, pa = {}, tb = {}, pb = {}, cx = {}, cy = {}, cz = {},
        comp = d.k or {}, compArea = d.ca or {}, compGround = d.cg or {}, byTile = {}, n = 0 }
    local n = d.n
    local c = 0
    for i = 1, #n - 8, 9 do
        c = c + 1
        g.ta[c], g.pa[c] = TileId(n[i], n[i + 1]), n[i + 2]
        g.tb[c], g.pb[c] = TileId(n[i + 3], n[i + 4]), n[i + 5]
        g.cx[c], g.cy[c], g.cz[c] = n[i + 6] / 10, n[i + 7] / 10, n[i + 8]
        for _, t in ipairs({ g.ta[c], g.tb[c] }) do
            local list = g.byTile[t]
            if not list then list = {} g.byTile[t] = list end
            list[#list + 1] = c
        end
    end
    g.n = c
    -- The adjacency is the file's own, kept as it came: first[c] .. first[c + 1] - 1 index adj, and an edge is one number,
    -- neighbour + ND.CROSS_BASE * (cost + ND.COST_BASE * tile it runs through) (ND.Edge unpacks it). One array of numbers
    -- is a third of the memory the three it replaces were, and nothing is copied at load.
    g.first, g.adj = d.af, d.ad
    graphs[map] = g
    return g
end

---------------------------------------------------------------------------
-- The places joined to a map (tools/navbake/places.py), a record of their own so that a journey passing through a map needs
-- not decode its crossing graph:
--   pl.place[id] = { tid, poly, x, y, ca = { crossing ... }, cc = { cost ... } }: the place's stand point and its attachment
--                  to the crossings of its tile (what a start or goal is joined with at plan time)
--   pl.walk[a][b] = weighted yards between two places on the map
local placeSets = {}
function ND.Places(map)
    local p = placeSets[map]
    if p ~= nil then return p or nil end
    local d = type(Store.places[map]) == "string" and Decode(Store.places[map])
    if not d or d.f ~= ND.FORMAT then
        placeSets[map] = false
        return nil
    end
    p = { place = {}, walk = {} }
    local pl = d.pl or {}
    local i = 1
    while i <= #pl do
        local id, tid, poly, x10, y10, cnt = pl[i], pl[i + 1], pl[i + 2], pl[i + 3], pl[i + 4], pl[i + 5]
        local ca, cc = {}, {}
        for k = 1, cnt do
            ca[k], cc[k] = pl[i + 4 + 2 * k], pl[i + 5 + 2 * k]
        end
        p.place[id] = { tid = tid, poly = poly, x = x10 / 10, y = y10 / 10, ca = ca, cc = cc }
        i = i + 6 + 2 * cnt
    end
    local pw = d.pw or {}
    for j = 1, #pw - 2, 3 do
        local a, b, yards = pw[j], pw[j + 1], pw[j + 2]
        local wa, wb = p.walk[a], p.walk[b]
        if not wa then wa = {} p.walk[a] = wa end
        if not wb then wb = {} p.walk[b] = wb end
        wa[b], wb[a] = yards, yards
    end
    placeSets[map] = p
    return p
end

---------------------------------------------------------------------------
-- The travel network (flights, boats and zeppelins, teleports): tools/navbake/transit.py
---------------------------------------------------------------------------
--   tr.place[id] = { id, kind (1 flight point, 2 dock, 3 teleport arrival), cont, faction (1 Alliance, 2 Horde, 3 both),
--                    node (the game's taxi node ID, 0 for a dock), name, town }
--   tr.flights   = { { a, b, seconds }, ... } (directed)      tr.flightsFrom[a] = the same, by start
--   tr.ferries   = { { a, b, travel, dwell, cycle, kind (1 boat, 2 zeppelin) }, ... }   tr.ferriesFrom[a]
--   tr.teleports = { { spell, place, cast }, ... }            tr.speed = { flight, ship, zeppelin } yards a second
local transit
function ND.Transit()
    if transit ~= nil then return transit or nil end
    local d = type(Store.transit) == "string" and Decode(Store.transit)
    if not d or d.f ~= ND.FORMAT then
        transit = false
        return nil
    end
    local tr = { place = {}, flights = {}, flightsFrom = {}, ferries = {}, ferriesFrom = {}, teleports = {}, byNode = {} }
    local p, names, towns = d.p or {}, d.n or {}, d.t or {}
    for i = 1, #p - 4, 5 do
        local k = (i - 1) / 5 + 1
        local pl = { id = p[i], kind = p[i + 1], cont = p[i + 2], faction = p[i + 3], node = p[i + 4], name = names[k], town = towns[k] }
        tr.place[pl.id] = pl
        if pl.node ~= 0 then tr.byNode[pl.node] = pl.id end
    end
    local fl = d.fl or {}
    for i = 1, #fl - 2, 3 do
        local f = { a = fl[i], b = fl[i + 1], seconds = fl[i + 2] }
        tr.flights[#tr.flights + 1] = f
        local list = tr.flightsFrom[f.a]
        if not list then list = {} tr.flightsFrom[f.a] = list end
        list[#list + 1] = f
    end
    local fe = d.fe or {}
    for i = 1, #fe - 5, 6 do
        local f = { a = fe[i], b = fe[i + 1], travel = fe[i + 2], dwell = fe[i + 3], cycle = fe[i + 4], kind = fe[i + 5] }
        tr.ferries[#tr.ferries + 1] = f
        local list = tr.ferriesFrom[f.a]
        if not list then list = {} tr.ferriesFrom[f.a] = list end
        list[#list + 1] = f
    end
    local tp = d.tp or {}
    for i = 1, #tp - 2, 3 do tr.teleports[#tr.teleports + 1] = { spell = tp[i], place = tp[i + 1], cast = tp[i + 2] } end
    local sp = d.sp or {}
    tr.speed = { flight = sp[1] or 32, ship = sp[2] or 16, zeppelin = sp[3] or 20 }
    transit = tr
    return tr
end

-- A place's stand point on its continent's walking map: continent, x, y, and its entry in that map's graph; or nil
-- (the place isn't on a map this data holds).
function ND.Stand(id)
    local tr = ND.Transit()
    local pl = tr and tr.place[id]
    if not pl then return nil end
    local g = ND.Places(pl.cont)
    local e = g and g.place[id]
    if not e then return nil end
    return pl.cont, e.x, e.y, e, pl
end

-- A decoded tile:
--   tx, ty, id, cs, x0, y0 (world x and y of its south-east corner, where cells count from)
--   X, Y, Z: vertex world positions
--   np: polygons; for polygon p: pn[p] vertices, pk[p] the index of its first edge in the edge arrays, area[p]
--   per edge k: ev[k] its first vertex (the edge runs to the next vertex of the polygon), nb[k] the polygon across it in
--     this tile (0: none), ld[k], lp[k], le[k] its link to the next tile (direction 1 east, 2 north, 3 west, 4 south;
--     polygon and edge there), for edges on the tile's side
--   cxp[p], cyp[p]: polygon centres; zmin[p], zmax[p]; comp[p]: its connected component (graph.compArea)
--   buckets[b] = { polygons whose box reaches bucket b }
local function BuildTile(map, tx, ty, d)
    local g = ND.Graph(map)
    local cells = g and g.cells or 500
    local cs = TILE / cells
    local t = { tx = tx, ty = ty, id = TileId(tx, ty), cs = cs, X = {}, Y = {}, Z = {},
        pn = {}, pk = {}, area = {}, ev = {}, nb = {}, ld = {}, lp = {}, le = {}, cxp = {}, cyp = {}, zmin = {}, zmax = {},
        buckets = {} }
    t.x0 = ORIGIN - ty * TILE - TILE
    t.y0 = ORIGIN - tx * TILE - TILE
    -- vertices are stored as differences from the one before (cells, cells, whole yards)
    local v = d.v or {}
    local X, Y, Z = t.X, t.Y, t.Z
    local nv, u, w, z = 0, 0, 0, 0
    for i = 1, #v - 2, 3 do
        nv = nv + 1
        u, w, z = u + v[i], w + v[i + 1], z + v[i + 2]
        X[nv], Y[nv], Z[nv] = t.x0 + u * cs, t.y0 + w * cs, z
    end
    -- per polygon: vertex count, area, then its vertex indices, each the difference from the index before it
    local raw = d.p or {}
    local p = {}
    do
        local j, last = 1, 0
        while j <= #raw do
            local n = raw[j]
            p[j], p[j + 1] = n, raw[j + 1]
            for q = 1, n do
                last = last + raw[j + 1 + q]
                p[j + 1 + q] = last
            end
            j = j + 2 + n
        end
    end
    local i, np, k = 1, 0, 0
    local pn, pk, area, ev, nb = t.pn, t.pk, t.area, t.ev, t.nb
    local open = {}                            -- edge key -> edge index, while its twin is not yet seen
    local bucket = t.buckets
    local bs = TILE / BUCKETS
    while i <= #p do
        local n, a = p[i], p[i + 1]
        np = np + 1
        pn[np], pk[np], area[np] = n, k + 1, a
        local sx, sy, zl, zh = 0, 0, huge, -huge
        local xl, xh, yl, yh = huge, -huge, huge, -huge
        for j = 1, n do
            local vi = p[i + 1 + j]
            k = k + 1
            ev[k], nb[k] = vi, 0
            local vx, vy, vz = X[vi], Y[vi], Z[vi]
            sx, sy = sx + vx, sy + vy
            if vz < zl then zl = vz end
            if vz > zh then zh = vz end
            if vx < xl then xl = vx end
            if vx > xh then xh = vx end
            if vy < yl then yl = vy end
            if vy > yh then yh = vy end
        end
        -- neighbours by shared edge
        for j = 1, n do
            local a1 = p[i + 1 + j]
            local b1 = p[i + 1 + (j % n) + 1]
            local key = a1 < b1 and a1 * 65536 + b1 or b1 * 65536 + a1
            local other = open[key]
            local here = pk[np] + j - 1
            if other then
                nb[here] = other.p
                nb[other.k] = np
                open[key] = nil
            else
                open[key] = { p = np, k = here }
            end
        end
        t.cxp[np], t.cyp[np], t.zmin[np], t.zmax[np] = sx / n, sy / n, zl, zh
        local b0x = math.max(0, math.min(BUCKETS - 1, floor((xl - t.x0) / bs)))
        local b1x = math.max(0, math.min(BUCKETS - 1, floor((xh - t.x0) / bs)))
        local b0y = math.max(0, math.min(BUCKETS - 1, floor((yl - t.y0) / bs)))
        local b1y = math.max(0, math.min(BUCKETS - 1, floor((yh - t.y0) / bs)))
        for bx = b0x, b1x do
            for by = b0y, b1y do
                local b = bx * BUCKETS + by + 1
                local list = bucket[b]
                if not list then list = {} bucket[b] = list end
                list[#list + 1] = np
            end
        end
        i = i + 2 + n
    end
    t.np = np
    t.comp = d.c or {}
    t.compArea = g and g.compArea or {}
    t.compGround = g and g.compGround or {}
    local x = d.x or {}
    for j = 1, #x - 4, 5 do
        local kk = pk[x[j]] and (pk[x[j]] + x[j + 1] - 1)
        if kk then t.ld[kk], t.lp[kk], t.le[kk] = x[j + 2], x[j + 3], x[j + 4] end
    end
    return t
end

local function Touch(key)
    for i = 1, lruN do
        if lru[i] == key then
            table.remove(lru, i)
            lru[lruN] = key
            return
        end
    end
    lruN = lruN + 1
    lru[lruN] = key
    while lruN > ND.MAX_TILES do
        local old = table.remove(lru, 1)
        lruN = lruN - 1
        tiles[old] = nil
        stats.released = stats.released + 1
    end
end

-- The decoded tile, or nil when the map has none there.
function ND.Tile(map, tx, ty)
    local key = map .. ":" .. tx .. "_" .. ty
    local t = tiles[key]
    if t then Touch(key) return t end
    if t == false then return nil end
    local list = Store.tiles[map]
    local s = list and list[tx .. "_" .. ty]
    local d = type(s) == "string" and Decode(s)
    if not d then
        tiles[key] = false
        return nil
    end
    t = BuildTile(map, tx, ty, d)
    tiles[key] = t
    stats.decoded = stats.decoded + 1
    Touch(key)
    return t
end

function ND.TileById(map, id) return ND.Tile(map, floor(id / 64), id % 64) end

-- Everything decoded goes; the loaded strings stay (the game cannot unload an addon).
function ND.Release()
    transit = nil
    wipe(graphs)
    wipe(placeSets)
    wipe(tiles)
    wipe(lru)
    lruN = 0
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
-- Whether (x, y) is inside convex polygon p of tile t (either winding; on an edge counts).
local function Inside(t, p, x, y)
    local X, Y, ev = t.X, t.Y, t.ev
    local k0, n = t.pk[p], t.pn[p]
    local sign = 0
    for j = 0, n - 1 do
        local a = ev[k0 + j]
        local b = ev[k0 + ((j + 1) % n)]
        local cr = (X[b] - X[a]) * (y - Y[a]) - (Y[b] - Y[a]) * (x - X[a])
        if cr > 1e-6 then
            if sign < 0 then return false end
            sign = 1
        elseif cr < -1e-6 then
            if sign > 0 then return false end
            sign = -1
        end
    end
    return true
end
ND.Inside = Inside

-- Distance squared from (x, y) to segment a-b, and the closest point.
local function SegDist2(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    local s = 0
    if len2 > 0 then
        s = ((x - ax) * dx + (y - ay) * dy) / len2
        if s < 0 then s = 0 elseif s > 1 then s = 1 end
    end
    local px, py = ax + dx * s, ay + dy * s
    return (x - px) * (x - px) + (y - py) * (y - py), px, py
end
ND.SegDist2 = SegDist2

-- Distance squared from (x, y) to polygon p's boundary, and the closest point on it.
local function PolyDist2(t, p, x, y)
    local X, Y, ev = t.X, t.Y, t.ev
    local k0, n = t.pk[p], t.pn[p]
    local best, bx, by = huge, nil, nil
    for j = 0, n - 1 do
        local a = ev[k0 + j]
        local b = ev[k0 + ((j + 1) % n)]
        local d2, px, py = SegDist2(x, y, X[a], Y[a], X[b], Y[b])
        if d2 < best then best, bx, by = d2, px, py end
    end
    return best, bx, by
end

local function BucketOf(t, x, y)
    local bs = TILE / BUCKETS
    local bx, by = floor((x - t.x0) / bs), floor((y - t.y0) / bs)
    if bx < 0 or by < 0 or bx >= BUCKETS or by >= BUCKETS then return nil end
    return bx * BUCKETS + by + 1, bx, by
end

local function Better(t, p, best, prefer)
    if not best then return true end
    if prefer and p == prefer then return true end
    if prefer and best == prefer then return false end
    -- the floor in the larger connected area: a city's street, not sealed ground under it or a roof above it
    local ap = t.compGround[t.comp[p] or 0] or t.compArea[t.comp[p] or 0] or 0
    local ab = t.compGround[t.comp[best] or 0] or t.compArea[t.comp[best] or 0] or 0
    if ap > ab * 1.5 then return true end
    if ab > ap * 1.5 then return false end
    local wa, wb = t.area[p] ~= 1, t.area[best] ~= 1
    if wa ~= wb then return not wa end           -- ground before water: standing on a bridge over a canal
    return t.zmin[p] < t.zmin[best]              -- else the lowest floor: the client gives no height to tell them apart
end

-- The polygon under a world point: tile, polygon, and the point itself (moved onto the nearest polygon when it was within
-- `reach` yards of one but on none). nil when there is no walkable ground within reach.
--   prefer: { tileId, poly } to keep (the one the player was on), when it still contains the point.
-- The client gives no usable height, so where floors stack the one in the larger connected area is taken (a city's street
-- over sealed ground under it), then ground over water, then the lowest, unless `prefer` says otherwise. Recorded as a
-- limitation in docs/navigation.md.
-- The nearest polygon within `reach` yards of (x, y), in the tile there or a neighbour; with `land`, only ground (not
-- water) in a connected area of ND.LAND_AREA square yards of ground or more. Returns tile, polygon and the point on it.
local function Nearest(map, x, y, reach, land)
    local tx, ty = ND.TileOf(x, y)
    local bestD, bestT, bestP, bx, by = reach * reach, nil, nil, nil, nil
    for dx = -1, 1 do
        for dy = -1, 1 do
            local u = ND.Tile(map, tx + dx, ty + dy)
            if u then
                local bs = TILE / BUCKETS
                local x0, x1 = floor((x - reach - u.x0) / bs), floor((x + reach - u.x0) / bs)
                local y0, y1 = floor((y - reach - u.y0) / bs), floor((y + reach - u.y0) / bs)
                local seen = {}
                for ix = math.max(0, x0), math.min(BUCKETS - 1, x1) do
                    for iy = math.max(0, y0), math.min(BUCKETS - 1, y1) do
                        local list = u.buckets[ix * BUCKETS + iy + 1]
                        if list then
                            for i = 1, #list do
                                local p = list[i]
                                if not seen[p] then
                                    seen[p] = true
                                    if not land or (u.area[p] == 1 and (u.compGround[u.comp[p] or 0] or 0) >= ND.LAND_AREA) then
                                        local d2, px, py = PolyDist2(u, p, x, y)
                                        if d2 < bestD or (d2 == bestD and bestT == u and Better(u, p, bestP)) then
                                            bestD, bestT, bestP, bx, by = d2, u, p, px, py
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not bestT then return nil end
    -- a hair inside, so the point is on the polygon and not just on its edge
    local cxp, cyp = bestT.cxp[bestP], bestT.cyp[bestP]
    local dx, dy = cxp - bx, cyp - by
    local len = sqrt(dx * dx + dy * dy)
    if len > 0.05 then bx, by = bx + dx / len * 0.05, by + dy / len * 0.05 end
    return bestT, bestP, bx, by
end

ND.LAND_AREA = 50000        -- square yards of connected ground that count as land (the bake's tools/navbake/places.py too)

function ND.Locate(map, x, y, reach, prefer, landReach)
    local tx, ty = ND.TileOf(x, y)
    local t = ND.Tile(map, tx, ty)
    local found, fp
    if t then
        local b = BucketOf(t, x, y)
        local list = b and t.buckets[b]
        local pick
        local pp = prefer and prefer.tile == t.id and prefer.poly or nil
        if list then
            for i = 1, #list do
                local p = list[i]
                if Inside(t, p, x, y) and Better(t, p, pick, pp) then pick = p end
            end
        end
        if pick then found, fp = t, pick end
    end
    if found then
        -- landReach: standing on a scrap of ground the map doesn't join to the land (a pier's planks, a boat's deck by one)
        -- counts as standing on the nearest land, when there is some within that many yards
        if landReach and landReach > 0 and not ((found.compGround[found.comp[fp] or 0] or 0) >= ND.LAND_AREA and found.area[fp] == 1) then
            local lt, lp, lx, ly = Nearest(map, x, y, landReach, true)
            if lt then return lt, lp, lx, ly end
        end
        return found, fp, x, y
    end
    -- nothing under it: the nearest polygon within reach, in this tile or a neighbour
    reach = reach or 0
    if reach <= 0 then return nil end
    return Nearest(map, x, y, reach, false)
end

-- The two ends of polygon p's edge j (0-based within the polygon), world x and y.
function ND.Edge(t, p, j)
    local n = t.pn[p]
    local a = t.ev[t.pk[p] + j]
    local b = t.ev[t.pk[p] + ((j + 1) % n)]
    return t.X[a], t.Y[a], t.X[b], t.Y[b], t.Z[a], t.Z[b]
end

-- Read only, for /tui diagnostics: counts, never a place.
function ND.Snapshot()
    local maps = 0
    for _ in pairs(Store.graph) do maps = maps + 1 end
    return { load = loadState, maps = maps, decodedTiles = lruN, graphs = (function()
        local n = 0 for _, g in pairs(graphs) do if g then n = n + 1 end end return n end)(),
        decoded = stats.decoded, released = stats.released, failures = stats.failures }
end
