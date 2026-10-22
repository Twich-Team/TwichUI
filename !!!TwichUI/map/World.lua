-- TwichUI: world map exploration, the world's geometry
-- The stitched map's coordinates: "world" is the game's map of Azeroth (uiMap 947), 0..1 across and down. Every
-- continent's and zone's map has its rectangle on it, from the game itself (C_Map.GetMapRectOnMap(map, 947), from its
-- own map tables), so every map's 0..1 converts to the world's and back without anything of TwichUI's in between.
-- World pixels are the world map's own art pixels (its art layer's size), what map/Art.lua lays everything out in.
-- No frames, no state but caches of what the game said; nothing here changes the map.

local R = TwichUI
local VM = R.MapViewMath
local MW = {}
R.MapWorld = MW

local WORLD = 947
MW.WORLD = WORLD
local T_WORLD, T_CONTINENT, T_ZONE = 1, 2, 3

local rects, arts, kinds = {}, {}, {}

local function Readable(v)
    local NV = R.Nav
    if NV and NV.Readable then return NV.Readable(v) end
    return type(v) == "number" and v == v and v
end

-- A map's rectangle on the world (normalized): left, right, top, bottom, or nil where the game doesn't place it there.
function MW.Rect(id)
    if type(id) ~= "number" then return nil end
    local r = rects[id]
    if r == nil then
        if id == WORLD then
            r = { 0, 1, 0, 1 }
        else
            local ok, l, rr, t, b = pcall(C_Map.GetMapRectOnMap, id, WORLD)
            l, rr, t, b = Readable(l), Readable(rr), Readable(t), Readable(b)
            r = (ok and l and rr and t and b and rr > l and b > t) and { l, rr, t, b } or false
        end
        rects[id] = r
    end
    if r then return r[1], r[2], r[3], r[4] end
    return nil
end

-- A map's art: width, height (its canvas units) and the layer's tile size.
function MW.Art(id)
    local a = arts[id]
    if a == nil then
        local ok, layers = pcall(C_Map.GetMapArtLayers, id)
        local layer = ok and type(layers) == "table" and layers[1]
        a = layer and layer.layerWidth and layer.layerWidth > 0 and { w = layer.layerWidth, h = layer.layerHeight,
            tw = layer.tileWidth or 256, th = layer.tileHeight or 256 } or false
        arts[id] = a
    end
    return a or nil
end

function MW.Kind(id)
    local k = kinds[id]
    if k == nil then
        local ok, info = pcall(C_Map.GetMapInfo, id)
        k = ok and type(info) == "table" and info.mapType or false
        kinds[id] = k
    end
    return k or nil
end

-- The world's size in world pixels (the world map's art).
function MW.Size()
    local a = MW.Art(WORLD)
    if a then return a.w, a.h end
    return 1002, 668
end

-- Whether a map is part of the stitched world: the world itself, a continent or a zone (cities are zones in this
-- client), with art and a rectangle on the world.
function MW.Stitchable(id)
    local k = MW.Kind(id)
    if k ~= T_WORLD and k ~= T_CONTINENT and k ~= T_ZONE then return false end
    return MW.Rect(id) ~= nil and MW.Art(id) ~= nil
end

function MW.ToWorld(id, x, y)
    local l, r, t, b = MW.Rect(id)
    if not l then return nil end
    return l + x * (r - l), t + y * (b - t)
end

function MW.FromWorld(id, u, v)
    local l, r, t, b = MW.Rect(id)
    if not l then return nil end
    return (u - l) / (r - l), (v - t) / (b - t)
end

-- The maps under a world point, from the world down: { 947, continent, zone }, as the game's own map lookup says
-- (GetMapInfoAtPosition: the game's own zone shapes, not rectangles).
function MW.ChainAt(u, v)
    local chain = { WORLD }
    local id, x, y = WORLD, u, v
    for _ = 1, 4 do
        local ok, info = pcall(C_Map.GetMapInfoAtPosition, id, x, y)
        if not (ok and type(info) == "table") or info.mapID == id then break end
        if not MW.Stitchable(info.mapID) then break end
        local cx, cy = MW.FromWorld(info.mapID, u, v)
        if not cx then break end
        id, x, y = info.mapID, cx, cy
        chain[#chain + 1] = id
    end
    return chain
end

-- The deepest map under a world point, and the point on it.
function MW.Deepest(u, v)
    local chain = MW.ChainAt(u, v)
    local id = chain[#chain]
    local x, y = MW.FromWorld(id, u, v)
    return id, x, y
end

-- Every map of the stitched world below the world map, in no set order: { id, kind }.
local all
function MW.Maps()
    if all then return all end
    all = {}
    local seen = {}
    local function Walk(id, depth)
        if depth > 4 then return end
        local ok, kids = pcall(C_Map.GetMapChildrenInfo, id)
        if not (ok and type(kids) == "table") then return end
        for _, info in ipairs(kids) do
            local kid = info.mapID
            if kid and not seen[kid] and MW.Stitchable(kid) then
                seen[kid] = true
                all[#all + 1] = { id = kid, kind = MW.Kind(kid) }
                Walk(kid, depth + 1)
            end
        end
    end
    Walk(WORLD, 1)
    return all
end

-- The continent's map for a continent (instance) id: the stitched continent whose world conversion is on it.
local continentOf = {}
function MW.Continent(cont)
    local c = continentOf[cont]
    if c ~= nil then return c or nil end
    c = false
    for _, m in ipairs(MW.Maps()) do
        if m.kind == T_CONTINENT then
            local f = R.MapView and R.MapView.MapFrame(m.id)
            if f and f.cont == cont then c = m.id break end
        end
    end
    continentOf[cont] = c
    return c or nil
end

-- World yards (continent `cont`, x north, y west) on the world map (normalized), or nil off the stitched world.
function MW.FromYards(cont, wx, wy)
    local id = MW.Continent(cont)
    local f = id and R.MapView and R.MapView.MapFrame(id)
    if not f then return nil end
    local x, y = VM.ToMap(f, wx, wy)
    return MW.ToWorld(id, x, y)
end

-- A world-yard rectangle on the world map: u0, v0, u1, v1 (normalized), or nil.
function MW.YardsRect(cont, x0, y0, x1, y1)
    local ua, va = MW.FromYards(cont, math.max(x0, x1), math.max(y0, y1))
    local ub, vb = MW.FromYards(cont, math.min(x0, x1), math.min(y0, y1))
    if not (ua and ub) then return nil end
    return math.min(ua, ub), math.min(va, vb), math.max(ua, ub), math.max(va, vb)
end

-- For tests: forget what the game said.
function MW.Forget()
    rects, arts, kinds, continentOf, all = {}, {}, {}, {}, nil
end
