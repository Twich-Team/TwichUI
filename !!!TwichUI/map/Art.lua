-- TwichUI: world map exploration, the stitched painting
-- Every map's painting on one canvas, each at its place on the world (map/World.lua), so zooming goes from the whole
-- world into any zone without the map jumping. Every texture is the game's own, by file ID; the soft edges are TwichUI's
-- own generated masks (media/textures/map-feather-*.tga, shapes only). Bottom to top:
--   the world      the world map's painting, always
--   continents     each continent's painting, its edge feathered wide into the world's, fading in as you zoom in
--   zones          each zone's painted pieces (the explored-area pieces the game's zone maps are made of: in this client a
--                  zone's own base art is mostly blank parchment): the explored ones from the game, the rest from
--                  map/Data.lua's list (Forever's own tables), shown as the "Unexplored areas" choice says (shown, dimmed
--                  or hidden); a thin feather at the zone's frame where neighbours meet
--   cities         a city's own map (cities have no pieces), its frame dropped away by a round feather, fading in close
-- One root frame on the game's canvas holds it all in world pixels; Layout scales and places the root for the map the game
-- has underneath, so a switch of that map moves nothing else. The layers sit just above the map's own art and under its
-- explored-area pieces and every pin.
-- Cost: the world's and continents' textures are made when the map is first shown; a zone's when it first comes into
-- view close enough to show, and its files are set only while it is in view (at most LOADED zones keep theirs).

local R = TwichUI
local VM, MW = R.MapViewMath, R.MapWorld
local MA = {}
R.MapArt = MA

local TEX = R.PATH .. [[media\textures\]]
local THIN, WIDE, ROUND = TEX .. "map-feather-thin", TEX .. "map-feather-wide", TEX .. "map-feather-round"
local CONT_FADE = { 1.4, 2.4 }     -- zoom (1: the whole world fits) where continents come in over the world
local ZONE_FADE = { 2.6, 4.5 }     -- ... and the zones' pieces over the continents
local CITY_FADE = { 0.35, 0.7 }    -- share of a city's own whole-map zoom where it comes in
local LOADED = 16                  -- zones that keep their files while out of view
local MARGIN = 0.15                -- of the view, beyond each edge, where zones are made ready
local DIM = 0.55                   -- an unexplored piece's brightness with "dimmed"
local LEVEL = { world = 2, cont = 3, zone = 4, city = 5 }   -- over the canvas's own level (its art); pins start at 2000
MA.LEVEL = LEVEL

local root, frames
local W, H
local host                         -- { id, k }: the map the root is laid out for
local zones, cities = {}, {}       -- [id] = { id, l, r, t, b, area, built, loaded, tex, used }
local zoneList, cityList = {}, {}
local built = false
local clock = 0
local stats = { zonesBuilt = 0, textures = 0, loads = 0, unloads = 0, layouts = 0 }

local function Pow2(n)
    local p = 16
    while p < n do p = p * 2 end
    return p
end

local function Put(region, x, y, w, h)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    region:SetSize(w, h)
end

-- A map's art laid on the world: left, top (world pixels) and world pixels per art pixel.
local function Place(id)
    local a = MW.Art(id)
    local l, r, t, b = MW.Rect(id)
    if not (a and l) then return nil end
    return { left = l * W, top = t * H, sx = (r - l) * W / a.w, sy = (b - t) * H / a.h, art = a }
end

local function Mask(frame, p, file)
    local m = frame:CreateMaskTexture()
    m:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    Put(m, p.left, p.top, p.art.w * p.sx, p.art.h * p.sy)
    return m
end

-- Tiles of an image w x h at (x, y) of a map's art, cut row by row into tiles of tw x th (an overlay's last column and
-- row are files of the next power of two; a base layer's are whole tiles). Returns the textures made.
local function Tiles(frame, p, files, x, y, w, h, sub, overlay, mask, lazy)
    local tw, th = p.art.tw, p.art.th
    local cols, rows = math.ceil(w / tw), math.ceil(h / th)
    local out = {}
    for j = 1, rows do
        local ph = (j < rows) and th or (h - (rows - 1) * th)
        local fh = (j < rows or not overlay) and th or Pow2(ph)
        for k = 1, cols do
            local file = tonumber(files[(j - 1) * cols + k])
            local pw = (k < cols) and tw or (w - (cols - 1) * tw)
            local fw = (k < cols or not overlay) and tw or Pow2(pw)
            if file and pw > 0 and ph > 0 then
                local tex = frame:CreateTexture(nil, "ARTWORK", nil, sub)
                if lazy then tex.twFile = file else tex:SetTexture(file) end
                tex:SetTexCoord(0, pw / fw, 0, ph / fh)
                Put(tex, p.left + (x + (k - 1) * tw) * p.sx, p.top + (y + (j - 1) * th) * p.sy, pw * p.sx, ph * p.sy)
                if mask then tex:AddMaskTexture(mask) end
                out[#out + 1] = tex
                stats.textures = stats.textures + 1
            end
        end
    end
    return out
end

local function BaseArt(frame, id, maskFile, lazy)
    local p = Place(id)
    if not p then return nil end
    local ok, files = pcall(C_Map.GetMapArtLayerTextures, id, 1)
    if not (ok and type(files) == "table" and #files > 0) then return nil end
    local mask = maskFile and Mask(frame, p, maskFile)
    return Tiles(frame, p, files, 0, 0, p.art.w, p.art.h, 0, false, mask, lazy)
end

---------------------------------------------------------------------------
-- A zone's pieces: the explored ones from the game, the rest from the data
---------------------------------------------------------------------------
local revealCache = {}
local function Reveal(artID)
    local list = revealCache[artID]
    if list ~= nil then return list end
    list = {}
    local D = R.MapExploreData
    local s = D and D.reveal and D.reveal[artID]
    if type(s) == "string" then
        for w, h, x, y, files in s:gmatch("(%d+):(%d+):(%d+):(%d+):([%d,]+)") do
            local f = {}
            for id in files:gmatch("%d+") do f[#f + 1] = tonumber(id) end
            list[#list + 1] = { w = tonumber(w), h = tonumber(h), x = tonumber(x), y = tonumber(y), files = f }
        end
    end
    revealCache[artID] = list
    return list
end
MA.Reveal = Reveal

local function Key(w, h, x, y) return w .. ":" .. h .. ":" .. x .. ":" .. y end

-- The pieces of a zone: { w, h, x, y, files, explored, key }
local function Pieces(id)
    local out, seen = {}, {}
    local ok, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, id)
    for _, info in ipairs(ok and type(explored) == "table" and explored or {}) do
        if not info.isShownByMouseOver then
            local key = Key(info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)
            seen[key] = true
            out[#out + 1] = { w = info.textureWidth, h = info.textureHeight, x = info.offsetX, y = info.offsetY,
                files = info.fileDataIDs, explored = true, key = key }
        end
    end
    local okArt, art = pcall(C_Map.GetMapArtID, id)
    for _, p in ipairs(okArt and Reveal(art) or {}) do
        local key = Key(p.w, p.h, p.x, p.y)
        if not seen[key] then
            out[#out + 1] = { w = p.w, h = p.h, x = p.x, y = p.y, files = p.files, explored = false, key = key }
        end
    end
    return out
end

local function Mode()
    local MXP = R.MapExplorePrefs
    return MXP and MXP.Get("unexplored") or "dim"
end

-- How a zone's textures look for the unexplored-areas choice and what has been explored.
local function Dress(z)
    local mode = Mode()
    for _, e in ipairs(z.tex) do
        local unexplored = not e.piece.explored
        local show = not (unexplored and mode == "hide")
        local k = (unexplored and mode == "dim") and DIM or 1
        e.tex:SetVertexColor(k, k, k)
        e.tex:SetShown(show and z.shown)
    end
end

local function BuildZone(z)
    local p = Place(z.id)
    if not p then return end
    local mask = Mask(frames.zone, p, THIN)
    z.tex = {}
    for _, piece in ipairs(Pieces(z.id)) do
        local sub = piece.explored and 1 or 0
        for _, tex in ipairs(Tiles(frames.zone, p, piece.files, piece.x, piece.y, piece.w, piece.h, sub, true, mask, true)) do
            z.tex[#z.tex + 1] = { tex = tex, piece = piece }
        end
    end
    z.built = true
    stats.zonesBuilt = stats.zonesBuilt + 1
end

local function Load(z, on)
    if z.loaded == on then return end
    z.loaded = on
    for _, e in ipairs(z.tex) do e.tex:SetTexture(on and e.tex.twFile or nil) end
    if on then stats.loads = stats.loads + 1 else stats.unloads = stats.unloads + 1 end
end

---------------------------------------------------------------------------
-- Building, laying out, following the view
---------------------------------------------------------------------------
function MA.Built() return built end
function MA.Root() return root end
function MA.WorldPixels() return W, H end

function MA.Build()
    if built then return true end
    local MV = R.MapView
    local canvas = MV and MV.Canvas()
    if not (canvas and MW.Rect(MW.WORLD) and MW.Art(MW.WORLD)) then return false end
    W, H = MW.Size()
    root = CreateFrame("Frame", nil, canvas)
    root:SetSize(W, H)
    root:EnableMouse(false)
    frames = {}
    for _, key in ipairs({ "world", "cont", "zone" }) do
        local f = CreateFrame("Frame", nil, root)
        f:SetAllPoints(root)
        f:EnableMouse(false)
        frames[key] = f
    end
    BaseArt(frames.world, MW.WORLD, nil, false)
    for _, m in ipairs(MW.Maps()) do
        if m.kind == 2 then
            BaseArt(frames.cont, m.id, WIDE, false)
        elseif m.kind == 3 then
            local l, r, t, b = MW.Rect(m.id)
            local z = { id = m.id, l = l, r = r, t = t, b = b, area = (r - l) * (b - t), shown = false, loaded = false }
            local okArt, art = pcall(C_Map.GetMapArtID, m.id)
            local okExp, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, m.id)
            local hasPieces = (okArt and #Reveal(art) > 0) or (okExp and type(explored) == "table" and #explored > 0)
            if hasPieces then
                zones[m.id] = z
                zoneList[#zoneList + 1] = z
            else
                -- a city (or a zone drawn whole): its own map, round-feathered, on a frame of its own to fade
                z.frame = CreateFrame("Frame", nil, root)
                z.frame:SetAllPoints(root)
                z.frame:EnableMouse(false)
                z.tex = BaseArt(z.frame, m.id, ROUND, false) or {}
                z.frame:Hide()
                cities[m.id] = z
                cityList[#cityList + 1] = z
            end
        end
    end
    table.sort(zoneList, function(a, b) return a.area > b.area end)
    built = true
    MA.SetLevels()
    return true
end

-- The layers' frame levels: over the canvas's own art, under the map's explored-area pieces and pins.
function MA.SetLevels()
    if not built then return end
    local base = R.MapView.Canvas():GetFrameLevel()
    root:SetFrameLevel(base + LEVEL.world)
    frames.world:SetFrameLevel(base + LEVEL.world)
    frames.cont:SetFrameLevel(base + LEVEL.cont)
    frames.zone:SetFrameLevel(base + LEVEL.zone)
    for _, c in ipairs(cityList) do c.frame:SetFrameLevel(base + LEVEL.city) end
end

-- Lays the root out for the map underneath: world pixels to its canvas units. Returns whether it could.
function MA.Layout(id)
    if not built then return false end
    local a = MW.Art(id)
    local l, r, t = MW.Rect(id)
    if not (a and l) then return false end
    local k = a.w / ((r - l) * W)
    if host and host.id == id and host.k == k then return true end
    host = { id = id, k = k }
    stats.layouts = stats.layouts + 1
    root:SetScale(k)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", R.MapView.Canvas(), "TOPLEFT", -l * W, t * H)
    return true
end

function MA.Host() return host and host.id or nil end

function MA.SetShown(on)
    if root then root:SetShown(on and true or false) end
    if not on then host = nil end
end

-- The view: u0..u1, v0..v1 (world, normalized) and the zoom (1: the whole world fits). fitZoom(id): a map's whole-map zoom.
function MA.SetView(u0, v0, u1, v1, zoom, fitZoom)
    if not built then return end
    frames.cont:SetAlpha(VM.Fade(zoom, CONT_FADE[1], CONT_FADE[2]))
    local zoneAlpha = VM.Fade(zoom, ZONE_FADE[1], ZONE_FADE[2])
    frames.zone:SetAlpha(zoneAlpha)
    local mu, mv = (u1 - u0) * MARGIN, (v1 - v0) * MARGIN
    clock = clock + 1
    local loaded = 0
    for _, z in ipairs(zoneList) do
        local near = zoneAlpha > 0 and z.r >= u0 - mu and z.l <= u1 + mu and z.b >= v0 - mv and z.t <= v1 + mv
        if near then
            if not z.built then BuildZone(z) end
            Load(z, true)
            z.used = clock
        end
        if near ~= z.shown then
            z.shown = near
            Dress(z)
        end
        if z.loaded then loaded = loaded + 1 end
    end
    -- the zones that have been out of view longest let their files go, keeping LOADED
    if loaded > LOADED then
        local idle = {}
        for _, z in ipairs(zoneList) do if z.loaded and not z.shown then idle[#idle + 1] = z end end
        table.sort(idle, function(a, b) return (a.used or 0) < (b.used or 0) end)
        for i = 1, math.min(#idle, loaded - LOADED) do Load(idle[i], false) end
    end
    for _, c in ipairs(cityList) do
        local fit = fitZoom(c.id)
        local a = fit and VM.Fade(zoom, fit * CITY_FADE[1], fit * CITY_FADE[2]) or 0
        local inView = c.r >= u0 and c.l <= u1 and c.b >= v0 and c.t <= v1
        c.frame:SetShown(a > 0.01 and inView)
        c.frame:SetAlpha(a)
    end
end

-- The game says more has been explored, or the unexplored-areas choice changed: each built zone again.
function MA.RefreshExplored()
    for _, z in ipairs(zoneList) do
        if z.built then
            local now = {}
            local ok, explored = pcall(C_MapExplorationInfo.GetExploredMapTextures, z.id)
            for _, info in ipairs(ok and type(explored) == "table" and explored or {}) do
                now[Key(info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)] = true
            end
            for _, e in ipairs(z.tex) do
                if now[e.piece.key] then e.piece.explored = true end
            end
            Dress(z)
        end
    end
end

-- Whether a world point is over a city drawn here (the deepest zoom goes a little further there).
function MA.CityAt(u, v)
    for _, c in ipairs(cityList) do
        if u >= c.l and u <= c.r and v >= c.t and v <= c.b then return c.id end
    end
    return nil
end

-- Read only, for /tui diagnostics and the tests.
function MA.Snapshot()
    local out = { built = built, zones = #zoneList, cities = #cityList, shown = 0, loaded = 0, host = host and host.id }
    for _, z in ipairs(zoneList) do
        if z.shown then out.shown = out.shown + 1 end
        if z.loaded then out.loaded = out.loaded + 1 end
    end
    for k, v in pairs(stats) do out[k] = v end
    return out
end
function MA.Zone(id) return zones[id] end
function MA.City(id) return cities[id] end

-- the unexplored-areas choice changed (or its scope was reset): every built zone dressed again
R.MapExplorePrefs.Subscribe(function(key)
    if key == "unexplored" or key == "behavior" or key == "all" then MA.RefreshExplored() end
end)

-- follows the view: which zones are in it and how far in (once a frame at most, after it moved)
R.MapView.Subscribe(function(event)
    local MV = R.MapView
    if (event == "view" or event == "attach") and MV.Ready() then
        local u0, v0, u1, v1 = MV.ViewRect()
        local _, _, zoom = MV.View()
        MA.SetView(u0, v0, u1, v1, zoom, MV.FitZoom)
    end
end)
