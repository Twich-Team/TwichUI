-- TwichUI: Navigation, the route on the world map
-- The route being followed, drawn on the map you are looking at: a line (or dots) from where you are along the route to
-- the destination, with an optional restrained ant trail moving along it. A world map data provider (as the pins'), so
-- it pans and zooms with the map.
--   What is drawn: only a route (navigating or being replaced, the latter dimmed). Never a direct bearing, never a
--     preview: a straight line on the map would read as a way to walk.
--   Where: the map shown, when it is on the route's continent. A map's world corners (C_Map.GetWorldPosFromMapPos at its
--     top left and bottom right, through Nav.lua's checked frame) give a straight conversion from world yards to the map;
--     each segment is clipped to the map's square, so nothing is drawn off its edge or on a map of another continent
--     (a dungeon, a floor of a city with its own map number on another continent). Maps of one continent share its
--     ground; where a city's map stacks floors the route is drawn on whichever is shown (the walking map's floors are
--     not the client's map floors).
--   How: on a frame over the map's canvas, so it moves and scales with the canvas; the line's thickness and the dots'
--     size are divided by the canvas's scale, so they stay the same on screen at every zoom. Drawn again when the route,
--     the map, the canvas size or the zoom changes, and the part behind you trimmed four times a second while you move.
--     The ants are the only moving part: a ticker while the map is shown and the setting is on (none with reduced
--     motion), at most 30 updates a second, at most NavPaint.MAX_DOTS dots.
--   Below the map's own pins (the canvas frame sits under the pin frame levels), so it never covers a pin, a label or a
--     button; it takes no mouse input.

local R = TwichUI
local NV, NP, NPaint = R.Nav, R.NavPrefs, R.NavPaint
local MT = {}
R.NavMapTrail = MT

local ANT_EVERY = 1 / 30
local ANT_GAP = 22            -- pixels on screen between ants
local DOT_GAP = 12            -- pixels between dots in the dots style

local provider, holder, painter
local installed = false
local corners = {}            -- [map] = { cont, x0, y0, x1, y1 } (world at the map's top left and bottom right), or false
local phase, antWait = 0, 0
local ticking = false
local stats = { draws = 0, segments = 0, clipped = 0, ants = 0 }

local function Shown() return WorldMapFrame and WorldMapFrame:IsShown() end

local function Corners(map)
    local c = corners[map]
    if c ~= nil then return c or nil end
    local cont, x0, y0 = NV.World(map, 0, 0)
    local cont2, x1, y1 = NV.World(map, 1, 1)
    if cont and cont2 == cont and x0 ~= x1 and y0 ~= y1 then
        c = { cont = cont, x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
    else
        c = false
    end
    corners[map] = c
    return c or nil
end

-- A world point as the map's 0..1 (x east, y south), possibly outside 0..1.
local function ToMap(c, wx, wy)
    return (c.y0 - wy) / (c.y0 - c.y1), (c.x0 - wx) / (c.x0 - c.x1)
end
MT.ToMap = ToMap

local function Want()
    return NV.Enabled() and NP.Get("worldTrail")
end

local function Holder()
    if holder then return holder end
    local canvas = WorldMapFrame:GetCanvas()
    holder = CreateFrame("Frame", nil, canvas)
    holder:SetAllPoints(canvas)
    holder:EnableMouse(false)
    -- over the map's explored-area art (and map exploration's terrain detail and cave maps, map/View.lua's ArtLevel 1
    -- and 2), under every pin
    local ok, level = pcall(function()
        return WorldMapFrame:GetPinFrameLevelsManager():GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION")
    end)
    holder:SetFrameLevel((ok and type(level) == "number") and level + 3 or math.max(1, canvas:GetFrameLevel() + 1))
    painter = NPaint.New(holder)
    return holder
end

local function Scale()
    local s = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    if type(s) ~= "number" or s <= 0 then s = 1 end
    return s
end

-- The route's points in canvas pixels, clipped to the map. Returns runs of points (each a flat xs, ys) or nil.
local runsX, runsY = {}, {}
local antX, antY = {}, {}
local function Project(route, c, w, h, fromSeg, fromX, fromY)
    local nRuns = 0
    local curX, curY
    local function Close() curX, curY = nil, nil end
    for i = fromSeg, route.n - 1 do
        local ax, ay = route.xs[i], route.ys[i]
        if i == fromSeg and fromX then ax, ay = fromX, fromY end
        local mx1, my1 = ToMap(c, ax, ay)
        local mx2, my2 = ToMap(c, route.xs[i + 1], route.ys[i + 1])
        local cx1, cy1, cx2, cy2 = NPaint.ClipBox(mx1, my1, mx2, my2, 0, 0, 1, 1)
        if not cx1 then
            stats.clipped = stats.clipped + 1
            Close()
        else
            local px1, py1, px2, py2 = cx1 * w, -cy1 * h, cx2 * w, -cy2 * h
            if not curX or curX[#curX] ~= px1 or curY[#curY] ~= py1 then
                nRuns = nRuns + 1
                curX, curY = runsX[nRuns] or {}, runsY[nRuns] or {}
                runsX[nRuns], runsY[nRuns] = curX, curY
                for k = #curX, 1, -1 do curX[k] = nil; curY[k] = nil end
                curX[1], curY[1] = px1, py1
            end
            curX[#curX + 1], curY[#curY + 1] = px2, py2
            if cx2 ~= mx2 or cy2 ~= my2 then Close() end
        end
    end
    return nRuns
end

-- One walking leg's route on the map shown (the part from startSeg on, from where you are when it is the current leg).
local function DrawRoute(route, c, w, h, startSeg, fromX, fromY, last, scale, r, g, b, a, thick, dots, antsOn)
    local nRuns = Project(route, c, w, h, startSeg, fromX, fromY)
    stats.draws = stats.draws + 1
    for k = 1, nRuns do
        local xs, ys = runsX[k], runsY[k]
        if dots then
            local size = (NP.Get("trailWidth") + 3) / scale
            local nd = NPaint.Ants(xs, ys, #xs, DOT_GAP / scale, antsOn and phase / scale or 0, NPaint.MAX_DOTS, antX, antY)
            for i = 1, nd do painter:Dot(antX[i], antY[i], size, r, g, b, a) end
        else
            for i = 1, #xs - 1 do
                painter:Line(xs[i], ys[i], xs[i + 1], ys[i + 1], r, g, b, a, thick)
                stats.segments = stats.segments + 1
            end
            if antsOn then
                local size = (NP.Get("trailWidth") + 2) / scale
                local ar, ag, ab = math.min(1, r + 0.35), math.min(1, g + 0.35), math.min(1, b + 0.35)
                local nd = NPaint.Ants(xs, ys, #xs, ANT_GAP / scale, phase / scale, 120, antX, antY)
                for i = 1, nd do painter:Dot(antX[i], antY[i], size, ar, ag, ab, math.min(1, a + 0.1)) end
                stats.ants = nd
            end
        end
    end
    -- where the leg ends: a dot a little larger than the trail (largest at the destination)
    local gx, gy = ToMap(c, route.goalX, route.goalY)
    if gx >= 0 and gx <= 1 and gy >= 0 and gy <= 1 then
        painter:Dot(gx * w, -gy * h, ((last and 2 or 1.4) * NP.Get("trailWidth") + 5) / scale, r, g, b, math.min(1, a + 0.15))
    end
end

local function Draw()
    if not (installed and Shown()) then return end
    Holder()
    local snap = NV.Snapshot()
    local legs = snap.legs
    local live = legs and (snap.state == "navigating" or snap.state == "recalculating" or snap.state == "riding")
    local map = WorldMapFrame:GetMapID()
    local c = live and map and Corners(map)
    painter:Begin()
    local w, h = holder:GetWidth(), holder:GetHeight()
    if not (live and c and w and h and w > 0 and h > 0) then
        painter:End()
        return
    end
    local scale = Scale()
    local r, g, b = NP.Rgb(NP.Get("trailColor"))
    local a = NP.Get("trailOpacity") / 100
    if snap.state == "recalculating" then a = a * 0.45 end
    local thick = NP.Get("trailWidth") / scale
    local dots = NP.Get("trailStyle") == "dots"
    local antsOn = NP.Get("ants") and not NP.ReducedMotion()
    local ok, cont, px, py = NV.Position()
    -- every walk still to do on this continent: the current one from where you are, the later ones whole
    for i = snap.leg or 1, #legs do
        local L = legs[i]
        local route = L.kind == "walk" and L.route or nil
        if route and c.cont == route.map then
            local current = i == snap.leg
            local fromX, fromY
            if current and ok and cont == route.map then fromX, fromY = px, py end
            DrawRoute(route, c, w, h, current and snap.seg or 1, fromX, fromY, i == #legs, scale, r, g, b, a, thick, dots, antsOn)
        end
    end
    painter:End()
end
MT.Draw = Draw

local function Tick(elapsed)
    antWait = antWait + elapsed
    if antWait < ANT_EVERY then return end
    local step = antWait
    antWait = 0
    phase = (phase + step * NP.Get("antSpeed") * 12) % 10000
    Draw()
end

-- The ants run only while the map is shown and they are wanted; otherwise nothing ticks for the map.
local function UpdateTicking()
    local snap = NV.Snapshot()
    local want = installed and Shown() and NP.Get("ants") and not NP.ReducedMotion()
        and snap.legs ~= nil and (snap.state == "navigating" or snap.state == "recalculating" or snap.state == "riding")
    if want and not ticking then NV.AddTicker(Tick) ticking = true
    elseif not want and ticking then NV.RemoveTicker(Tick) ticking = false end
end

local function Build()
    if provider or not WorldMapFrame or not MapCanvasDataProviderMixin then return provider ~= nil end
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:RemoveAllData() if painter then painter:Clear() end end
    function provider:RefreshAllData() Draw() UpdateTicking() end
    function provider:OnShow() Draw() UpdateTicking() end
    function provider:OnHide()
        if painter then painter:Clear() end
        UpdateTicking()
    end
    function provider:OnMapChanged() Draw() end
    function provider:OnCanvasScaleChanged() Draw() end
    function provider:OnCanvasSizeChanged() Draw() end
    return true
end

function MT.Refresh()
    if not WorldMapFrame then return end
    local want = Want()
    if not Build() then return end
    if want and not installed then
        WorldMapFrame:AddDataProvider(provider)
        installed = true
    elseif not want and installed then
        if painter then painter:Clear() end
        WorldMapFrame:RemoveDataProvider(provider)
        installed = false
    end
    UpdateTicking()
    if installed and Shown() then Draw() end
end

NV.Subscribe(function(event)
    if event == "prefs" then MT.Refresh() return end
    if not installed then return end
    if event == "route" or event == "state" then
        UpdateTicking()
        Draw()
    elseif event == "progress" and Shown() and not ticking then
        Draw()   -- trims the part behind you (the ants redraw on their own)
    end
end)
R:On("PLAYER_LOGIN", MT.Refresh)
R:On("ADDON_LOADED", function(name) if name == "Blizzard_WorldMap" then MT.Refresh() end end)

-- Read only, for /tui diagnostics and the tests.
function MT.Diagnostics()
    local l, d, pl, pd = 0, 0, 0, 0
    if painter then l, d, pl, pd = painter:Counts() end
    return { installed = installed, ticking = ticking, lines = l, dots = d, pooledLines = pl, pooledDots = pd,
        draws = stats.draws, clipped = stats.clipped }
end
