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
local CITY_FADE = { 0.2, 0.4 }     -- city plan takes over before enlarged zone banners cover its streets
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
local stats = { zonesBuilt = 0, textures = 0, loads = 0, unloads = 0, layouts = 0, cityLoads = 0, cityUnloads = 0 }
local nativeHidden = {}

-- Only the painting we replace: never hide player/quest/third-party pins or the quest log.
-- Native exploration pins otherwise sit thousands of levels above our close detail.
function MA.SyncNative(replace)
    if InCombatLockdown and InCombatLockdown() then return end
    local map = WorldMapFrame
    if not map then return end
    local live = {}
    if map.detailLayerPool then
        for frame in map.detailLayerPool:EnumerateActive() do live[frame] = true end
    end
    if map.EnumeratePinsByTemplate then
        for pin in map:EnumeratePinsByTemplate("MapExplorationPinTemplate") do live[pin] = true end
    end
    if not replace then
        for frame, wasShown in pairs(nativeHidden) do
            if live[frame] then frame:SetShown(wasShown) end
            nativeHidden[frame] = nil
        end
        return
    end
    for frame in pairs(nativeHidden) do
        if not live[frame] then nativeHidden[frame] = nil end
    end
    for frame in pairs(live) do
        if nativeHidden[frame] == nil then nativeHidden[frame] = frame:IsShown() and true or false end
        frame:Hide()
    end
end

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

-- City plans used to bind every city's files at the first map opening, even
-- with all their frames hidden. Keep geometry/owned masks, bind only a visible
-- plan, and release files when it leaves the view or the map closes.
local function LoadCity(c, on)
    if c.loaded == on then return end
    c.loaded = on
    for _, tex in ipairs(c.tex) do tex:SetTexture(on and tex.twFile or nil) end
    if on then stats.cityLoads = stats.cityLoads + 1 else stats.cityUnloads = stats.cityUnloads + 1 end
end

-- Reviewed on Forever 1.60.1.71037: Tirisfal's explored overlay carries an
-- Undercity scroll outside the city's plan. Its native base has intact terrain
-- beneath it. Reveal only that base ROI, through our existing owned wide mask,
-- as the city takes over. No edited game pixels, invented geography or mask UVs.
-- The exact build/art/carrier checks fail back to the original artwork.
local function CityCover(c)
    if c.id ~= 1458 or c.coverAttempted then return end
    c.coverAttempted = true
    local ok, version, build = pcall(GetBuildInfo)
    if not ok or version ~= "1.60.1" or tostring(build) ~= "71037" then c.coverReason = "unreviewed-client"; return end
    local z, p = zones[1420], Place(1420)
    local artOK, artID = pcall(C_Map.GetMapArtID, 1420)
    if not (z and z.built and p and artOK and artID == 2126 and p.art.w == 1002 and p.art.h == 668
        and p.art.tw == 256 and p.art.th == 256) then c.coverReason = "unreviewed-art"; return end
    local piece
    for _, e in ipairs(z.tex) do
        if e.tex.twFile == 7958244 then piece = e.piece; break end
    end
    local filesOK, files = pcall(C_Map.GetMapArtLayerTextures, 1420, 1)
    if not (piece and piece.x == 463 and piece.y == 361 and piece.w == 320 and piece.h == 256
        and piece.files[2] == 7958245 and filesOK and type(files) == "table" and #files == 12) then
        c.coverReason = "source-unavailable"; return
    end
    local x0, y0, x1, y1 = 480, 470, 758, 558
    local expected = { 7958258, 7958259, 7958251, 7958252 }
    local regions = {}
    for row = 1, 2 do
        for col = 1, 2 do
            local x, y = math.max(x0, col * 256), math.max(y0, row * 256)
            local right, bottom = math.min(x1, (col + 1) * 256), math.min(y1, (row + 1) * 256)
            local file = files[row * 4 + col + 1]
            if file ~= expected[#regions + 1] then c.coverReason = "source-unavailable"; return end
            regions[#regions + 1] = { x, y, right, bottom, col * 256, row * 256, file }
        end
    end
    local mask = frames.zone:CreateMaskTexture()
    mask:SetTexture(WIDE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    Put(mask, p.left + x0 * p.sx, p.top + y0 * p.sy, (x1 - x0) * p.sx, (y1 - y0) * p.sy)
    c.cover = { tex = {}, piece = piece, loaded = false, alpha = 0 }
    for _, box in ipairs(regions) do
        local tex = frames.zone:CreateTexture(nil, "ARTWORK", nil, 2)
        tex.twFile = box[7]
        tex:SetTexCoord((box[1] - box[5]) / 256, (box[3] - box[5]) / 256,
            (box[2] - box[6]) / 256, (box[4] - box[6]) / 256)
        Put(tex, p.left + box[1] * p.sx, p.top + box[2] * p.sy, (box[3] - box[1]) * p.sx, (box[4] - box[2]) * p.sy)
        tex:AddMaskTexture(mask)
        tex:Hide()
        c.cover.tex[#c.cover.tex + 1] = tex
        stats.textures = stats.textures + 1
    end
    c.coverReason = "native-base-roi"
end

local function UpdateCityCover(c, alpha)
    if alpha > 0 then CityCover(c) end
    local cover = c.cover
    if not cover then return end
    local mode = Mode()
    if cover.failed or (not cover.piece.explored and mode == "hide") then alpha = 0 end
    local on = alpha > 0.01
    if cover.loaded ~= on then
        cover.loaded = on
        for _, tex in ipairs(cover.tex) do
            if tex:SetTexture(on and tex.twFile or nil) == false and on then
                cover.failed = true
                c.coverReason = "texture-rejected"
                if R.MapTrace then R.MapTrace("texture-failure", tex.twFile, "city-cover-rejected") end
            end
        end
        if cover.failed and on then
            cover.loaded, alpha, on = false, 0, false
            for _, tex in ipairs(cover.tex) do tex:SetTexture(nil) end
        end
    end
    local k = not cover.piece.explored and mode == "dim" and DIM or 1
    alpha = on and alpha or 0
    if cover.alpha == alpha and cover.tint == k then return end
    cover.alpha, cover.tint = alpha, k
    for _, tex in ipairs(cover.tex) do
        tex:SetAlpha(cover.alpha)
        tex:SetVertexColor(k, k, k)
        tex:SetShown(on)
    end
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
            if hasPieces and not MW.IsCity(m.id) then
                zones[m.id] = z
                zoneList[#zoneList + 1] = z
            else
                -- a city (or a zone drawn whole): its own map, round-feathered, on a frame of its own to fade
                z.frame = CreateFrame("Frame", nil, root)
                z.frame:SetAllPoints(root)
                z.frame:EnableMouse(false)
                z.tex = BaseArt(z.frame, m.id, ROUND, true) or {}
                local localData = R.MapExploreLocalData
                local interior = localData and localData.cities[m.id]
                if interior and R.MapPictures then
                    z.interior = CreateFrame("Frame", nil, z.frame)
                    z.interior:SetAllPoints(z.frame)
                    z.interior:EnableMouse(false)
                    z.pictures = R.MapPictures.Create(z.interior)
                    R.MapPictures.Set(z.pictures, interior)
                end
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
    for _, c in ipairs(cityList) do
        -- The underground city plan must cover the surface terrain, including at its feathered edges.
        c.frame:SetFrameLevel(base + (c.interior and 7 or LEVEL.city))
        if c.interior then c.interior:SetFrameLevel(c.frame:GetFrameLevel() + 1) end
    end
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
    if not on then
        host = nil
        for _, z in ipairs(zoneList) do
            if z.built then Load(z, false) end
        end
        for _, c in ipairs(cityList) do
            LoadCity(c, false)
            UpdateCityCover(c, 0)
            if c.pictures then R.MapPictures.Clear(c.pictures) end
        end
    end
end

-- The view: u0..u1, v0..v1 (world, normalized) and the zoom (1: the whole world fits). fitZoom(id): a map's whole-map zoom.
local function CityAlpha(c, zoom, fitZoom)
    local fit = fitZoom(c.id)
    return fit and VM.Fade(zoom, fit * CITY_FADE[1], fit * CITY_FADE[2]) or 0
end

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
        local a = CityAlpha(c, zoom, fitZoom)
        local inView = c.r >= u0 and c.l <= u1 and c.b >= v0 and c.t <= v1
        local visible = a > 0.01 and inView
        LoadCity(c, visible)
        UpdateCityCover(c, visible and a or 0)
        c.frame:SetShown(visible)
        c.frame:SetAlpha(a)
        if c.pictures then
            local prefs = R.MapExplorePrefs
            local mix = prefs.Get("detail") and VM.Fade(zoom, 20, 36) * math.min(0.5, prefs.Get("detailStrength") / 100) or 0
            R.MapPictures.Update(c.pictures, u0, v0, u1, v1, inView and a > 0.01 and mix or 0)
        end
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
    for _, c in ipairs(cityList) do
        if c.cover then
            UpdateCityCover(c, root:IsShown() and c.frame:IsShown() and c.frame:GetAlpha() or 0)
        end
    end
end

-- Whether a world point is over a city drawn here (the deepest zoom goes a little further there).
function MA.CityAt(u, v, navigation)
    local best
    for _, c in ipairs(cityList) do
        local inset = navigation and MW.IsCity(c.id) and 0.2 or 0
        local du, dv = (c.r - c.l) * inset, (c.b - c.t) * inset
        if u >= c.l + du and u <= c.r - du and v >= c.t + dv and v <= c.b - dv and (not best or c.area < best.area
            or c.area == best.area and c.id < best.id) then best = c end
    end
    return best and best.id or nil
end

-- Surface-city plans stay legible while outdoor terrain takes over at deep
-- zoom. A spatial fade avoids an opacity jump when the view center leaves a
-- city's rectangle. Derive intro from this view, independent of listener order.
function MA.SurfaceCityCover(u, v, zoom)
    local id = MA.CityAt(u, v)
    local c = id and cities[id]
    if not c or c.interior or not MW.IsCity(c.id) then return 0 end
    local edge = math.min((u - c.l) / (c.r - c.l), (c.r - u) / (c.r - c.l),
        (v - c.t) / (c.b - c.t), (c.b - v) / (c.b - c.t))
    return VM.Fade(edge, 0, 0.15) * CityAlpha(c, zoom, R.MapView.FitZoom)
end

-- Read only, for /tui diagnostics and the tests.
function MA.Snapshot()
    local out = { built = built, zones = #zoneList, cities = #cityList, shown = 0, loaded = 0, host = host and host.id,
        citiesLoaded = 0, cityTexturesBound = 0, cityCoverTexturesBound = 0 }
    for _, z in ipairs(zoneList) do
        if z.shown then out.shown = out.shown + 1 end
        if z.loaded then out.loaded = out.loaded + 1 end
    end
    for _, c in ipairs(cityList) do
        if c.loaded then out.citiesLoaded = out.citiesLoaded + 1; out.cityTexturesBound = out.cityTexturesBound + #c.tex end
        if c.cover and c.cover.loaded then out.cityCoverTexturesBound = out.cityCoverTexturesBound + #c.cover.tex end
    end
    for k, v in pairs(stats) do out[k] = v end
    return out
end
function MA.Zone(id) return zones[id] end
function MA.City(id) return cities[id] end

function MA.Diagnostic()
    local out = MA.Snapshot()
    out.unexploredMode, out.unexploredDimMultiplier = Mode(), DIM
    out.layers, out.cityLayers, out.zoneLayers = {}, {}, {}
    for _, key in ipairs({ "world", "cont", "zone" }) do
        local f = frames and frames[key]
        out.layers[#out.layers + 1] = { kind = key, shown = f and f:IsShown() or false,
            alpha = f and f:GetAlpha() or 0, level = f and f:GetFrameLevel() or false }
    end
    for _, c in ipairs(cityList) do
        if c.frame:IsShown() then out.cityLayers[#out.cityLayers + 1] = { mapId = c.id, alpha = c.frame:GetAlpha(),
            level = c.frame:GetFrameLevel(), interior = c.pictures ~= nil, loaded = c.loaded, textures = #c.tex,
            nativeBaseCover = { status = c.coverReason or "not-needed", textures = c.cover and #c.cover.tex or 0,
                alpha = c.cover and c.cover.alpha or 0, failed = c.cover and c.cover.failed or false } } end
    end
    table.sort(out.cityLayers, function(a, b) return a.mapId < b.mapId end)
    for _, z in ipairs(zoneList) do
        if z.shown then
            local explored, unexplored = 0, 0
            for _, e in ipairs(z.tex or {}) do
                if e.piece.explored then explored = explored + 1 else unexplored = unexplored + 1 end
            end
            out.zoneLayers[#out.zoneLayers + 1] = { mapId = z.id, loaded = z.loaded, built = z.built,
                alpha = frames.zone:GetAlpha(), level = frames.zone:GetFrameLevel(),
                exploredTextures = explored, unexploredTextures = unexplored,
                dimmedTextures = Mode() == "dim" and unexplored or 0,
                hiddenTextures = Mode() == "hide" and unexplored or 0 }
        end
    end
    table.sort(out.zoneLayers, function(a, b) return a.mapId < b.mapId end)
    out.zoneLayersOmitted = math.max(0, #out.zoneLayers - 32)
    while #out.zoneLayers > 32 do table.remove(out.zoneLayers) end
    out.masks = { zone = "thin feather", continent = "wide feather", city = "round feather", territory = false }
    return out
end

-- the unexplored-areas choice changed (or its scope was reset): every built zone dressed again
R.MapExplorePrefs.Subscribe(function(key)
    if key == "unexplored" or key == "behavior" or key == "all" then MA.RefreshExplored() end
end)

-- follows the view: which zones are in it and how far in (once a frame at most, after it moved)
MA.SetView = R.Perf and R.Perf.Wrap("map.art.update", MA.SetView) or MA.SetView
R.MapView.Subscribe(function(event)
    local MV = R.MapView
    if (event == "view" or event == "attach") and MV.Ready() then
        local u0, v0, u1, v1 = MV.ViewRect()
        local _, _, zoom = MV.View()
        MA.SetView(u0, v0, u1, v1, zoom, MV.FitZoom)
    end
end)
