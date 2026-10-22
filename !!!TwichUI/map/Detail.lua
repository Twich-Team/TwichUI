-- TwichUI: world map exploration, terrain detail
-- Close in, the paintings run out of pixels. Where the game has a minimap picture of the ground (every terrain tile of
-- Eastern Kingdoms and Kalimdor: map/Data.lua, read from the game's own map files), those pictures are laid on the
-- stitched map in their real places and faded in as you zoom past the zones' paintings, so trees, rocks, roads and
-- buildings appear. They are the game's own textures, drawn by the game; TwichUI ships no map art.
--   Not over Ironforge or the Undercity, whose minimap pictures are the ground above them, nor under a cave's map that has
--   surfaced (map/Caves.lua).
--   Cost: a continent's list is decoded the first time it is needed; only the tiles in view (and a margin) have textures,
--   at most MAX_TILES, reused from a pool and let go as they leave the view or the map closes. Nothing runs between view
--   changes.

local R = TwichUI
local VM, MXP, MV, MW = R.MapViewMath, R.MapExplorePrefs, R.MapView, R.MapWorld
local MD = {}
R.MapDetail = MD

local FADE = { 24, 36 }               -- zoom (1: the whole world) where the detail comes in
local MAX_TILES = 80
local MARGIN = 0.1
local LEVEL = 6                       -- over the canvas's own level (the stitched painting is 2 to 5)
local WARM = { 1, 0.95, 0.86 }        -- a little toward the paintings' parchment
local UNDERGROUND = { 1455, 1458 }    -- Ironforge, the Undercity

local decoded = {}
local layer
local free, used = {}, {}
local wanted = {}
local showing, alpha = false, 0
local stats = { decoded = 0, updates = 0, tooMany = 0, made = 0 }

local function Tiles(cont)
    local t = decoded[cont]
    if t ~= nil then return t or nil end
    local D = R.MapExploreData
    local s = D and D.minimap and D.minimap[cont]
    if type(s) ~= "string" then
        decoded[cont] = false
        return nil
    end
    t = {}
    for col, row, fd in s:gmatch("(%d+),(%d+),(%d+)") do t[tonumber(col) * 64 + tonumber(row)] = tonumber(fd) end
    decoded[cont] = t
    stats.decoded = stats.decoded + 1
    return t
end
MD.Tiles = Tiles

function MD.Showing() return showing end

local function Release(key)
    local tex = used[key]
    used[key] = nil
    tex:Hide()
    tex:SetTexture(nil)
    free[#free + 1] = tex
end

local function Clear()
    for key in pairs(used) do Release(key) end
    showing, alpha = false, 0
end
MD.Clear = Clear

local function Layer()
    if layer then return layer end
    local root = R.MapArt.Root()
    layer = CreateFrame("Frame", nil, root)
    layer:SetAllPoints(root)
    layer:EnableMouse(false)
    return layer
end

-- whether a world rectangle overlaps an underground city's map
local function Underground(u0, v0, u1, v1)
    for _, id in ipairs(UNDERGROUND) do
        local l, r, t, b = MW.Rect(id)
        if l and u1 > l and u0 < r and v1 > t and v0 < b then return true end
    end
    return false
end

-- The continents in view with minimap data: { cont, frame (its map's yards), id (its map) }
local function InView(u0, v0, u1, v1)
    local out = {}
    local D = R.MapExploreData
    for cont in pairs(D and D.minimap or {}) do
        local id = MW.Continent(cont)
        local l, r, t, b = MW.Rect(id)
        local f = id and MV.MapFrame(id)
        if l and f and f.axisAligned and r > u0 and l < u1 and b > v0 and t < v1 then
            out[#out + 1] = { cont = cont, id = id, f = f, l = l, r = r, t = t, b = b }
        end
    end
    return out
end

local function Update()
    stats.updates = stats.updates + 1
    if not (MV.Ready() and MXP.Get("detail")) or (R.MapCaves and R.MapCaves.Surfaced()) then Clear() return end
    local _, _, zoom = MV.View()
    local a = VM.Fade(zoom, FADE[1], FADE[2]) * MXP.Get("detailStrength") / 100
    if a <= 0.01 then Clear() return end
    local u0, v0, u1, v1 = MV.ViewRect()
    local mu, mv = (u1 - u0) * MARGIN, (v1 - v0) * MARGIN
    u0, v0, u1, v1 = u0 - mu, v0 - mv, u1 + mu, v1 + mv
    for k in pairs(wanted) do wanted[k] = nil end
    local count = 0
    local W, H = MW.Size()
    for _, c in ipairs(InView(u0, v0, u1, v1)) do
        local tiles = Tiles(c.cont)
        if tiles then
            -- the view on this continent's map, then its tiles
            local x0, y0 = (u0 - c.l) / (c.r - c.l), (v0 - c.t) / (c.b - c.t)
            local x1, y1 = (u1 - c.l) / (c.r - c.l), (v1 - c.t) / (c.b - c.t)
            local c0, c1, r0, r1 = VM.TilesIn(c.f, x0, y0, x1, y1)
            count = count + (c1 - c0 + 1) * (r1 - r0 + 1)
            if count > MAX_TILES then
                stats.tooMany = stats.tooMany + 1
                Clear()
                return
            end
            for col = c0, c1 do
                for row = r0, r1 do
                    local fd = tiles[col * 64 + row]
                    if fd then wanted[c.cont * 4096 + col * 64 + row] = { fd = fd, c = c, col = col, row = row } end
                end
            end
        end
    end
    for key in pairs(used) do
        if not wanted[key] then Release(key) end
    end
    local L = Layer()
    L:SetFrameLevel(MV.ArtLevel(LEVEL))
    for key, w in pairs(wanted) do
        local tex = used[key]
        if not tex then
            local n, west, s, e = VM.TileRect(w.col, w.row)
            local ua, va = MW.FromYards(w.c.cont, n, west)
            local ub, vb = MW.FromYards(w.c.cont, s, e)
            if ua and ub and not Underground(ua, va, ub, vb) then
                tex = table.remove(free)
                if not tex then
                    tex = L:CreateTexture(nil, "ARTWORK")
                    stats.made = stats.made + 1
                end
                tex:SetTexture(w.fd)
                tex:SetVertexColor(WARM[1], WARM[2], WARM[3])
                tex:ClearAllPoints()
                tex:SetPoint("TOPLEFT", R.MapArt.Root(), "TOPLEFT", ua * W, -va * H)
                tex:SetSize((ub - ua) * W, (vb - va) * H)
                used[key] = tex
            end
        end
        if tex and (alpha ~= a or not tex:IsShown()) then
            tex:SetAlpha(a)
            tex:Show()
        end
    end
    alpha = a
    showing = next(used) ~= nil
end
MD.Update = Update

MV.Subscribe(function(event)
    if event == "view" then Update()
    elseif event == "hide" or event == "off" or event == "attach" and not MV.Active() then Clear() end
end)

-- Read only, for /tui diagnostics and the tests.
function MD.TextureFor(cont, col, row) return used[cont * 4096 + col * 64 + row] end
function MD.Snapshot()
    local n = 0
    for _ in pairs(used) do n = n + 1 end
    local conts = 0
    for _, v in pairs(decoded) do if v then conts = conts + 1 end end
    return { showing = showing, alpha = alpha, tiles = n, pooled = #free, made = stats.made, continents = conts,
        updates = stats.updates, tooMany = stats.tooMany }
end
