-- TwichUI: Navigation, the route on the minimap
-- The part of the route near you, on the minimap: a line (or dots) and the optional ant trail, on a frame over the minimap
-- that takes no mouse input and sits under the pins' buttons.
--   Where: as the minimap's party pins are placed (pins/Minimap.lua's Gather: the view radius from the client, or from the
--     zoom when it won't say; the minimap's width; its rotation and your facing when the rotateMinimap setting is on),
--     so the trail turns and zooms with the minimap. A point is (its distance north and west of you) x (half the minimap's
--     width / the view radius) pixels from the centre, turned by your facing when the minimap rotates.
--   Clipping: to the minimap's circle, or its square when GetMinimapShape (the convention minimap addons share) says
--     "SQUARE". EllesmereUI's square minimap doesn't publish that, so there the circle inside it is used: less of the
--     route is shown near the corners, never a line past the edge.
--   Only the local part: legs reaching within the view are drawn; the rest are skipped before any drawing.
--   When: a ticker while a route is followed and the minimap is shown, 20 times a second while the minimap rotates and
--     10 otherwise, and drawn again only when you moved, turned, the zoom or size changed, or the ants moved. With reduced
--     motion the ants keep still (the trail still follows you: that is direction, not decoration).

local R = TwichUI
local NV, NP, NPaint = R.Nav, R.NavPrefs, R.NavPaint
local MM = {}
R.NavMinimapTrail = MM

local FAST, SLOW = 0.05, 0.10
local INSET = 2
local ANT_GAP, DOT_GAP = 14, 9

local holder, painter
local ticking = false
local wait, phase = 0, 0
local view = {}
local last = {}               -- dirty check: x, y, facing, radius, half, phase, seg, routeId
local xs, ys = {}, {}
local antX, antY = {}, {}
local stats = { draws = 0, skipped = 0, why = "none" }

local function Want()
    return NV.Enabled() and NP.Get("minimapTrail") and Minimap ~= nil
end

local function Holder()
    if holder then return holder end
    holder = CreateFrame("Frame", nil, Minimap)
    holder:SetAllPoints(Minimap)
    holder:EnableMouse(false)
    holder:SetFrameLevel(Minimap:GetFrameLevel() + 4)   -- under the pins' buttons (+6)
    painter = NPaint.New(holder)
    return holder
end

local function Square()
    return type(GetMinimapShape) == "function" and GetMinimapShape() == "SQUARE"
end

-- What one draw uses (module-level, so a draw allocates nothing)
local dr, dg, db, da, dthick, ddots, dants, cx, cy = 1, 1, 1, 1, 2, false, false, 0, 0
local n = 0

local function Flush()
    if n < 2 then n = 0 return end
    if ddots then
        local nd = NPaint.Ants(xs, ys, n, DOT_GAP, dants and phase or 0, 120, antX, antY)
        for i = 1, nd do painter:Dot(cx + antX[i], cy + antY[i], dthick + 3, dr, dg, db, da) end
    else
        for i = 1, n - 1 do painter:Line(cx + xs[i], cy + ys[i], cx + xs[i + 1], cy + ys[i + 1], dr, dg, db, da, dthick) end
        if dants then
            local nd = NPaint.Ants(xs, ys, n, ANT_GAP, phase, 60, antX, antY)
            local ar, ag, ab = math.min(1, dr + 0.35), math.min(1, dg + 0.35), math.min(1, db + 0.35)
            for i = 1, nd do painter:Dot(cx + antX[i], cy + antY[i], dthick + 2, ar, ag, ab, math.min(1, da + 0.1)) end
        end
    end
    n = 0
end

local function Draw(force)
    local snap = NV.Snapshot()
    local route = snap.route
    if not (route and (snap.state == "navigating" or snap.state == "recalculating")) then
        if painter then painter:Clear() end
        stats.why = "no-route"
        return
    end
    local ok, cont, px, py = NV.Position()
    if not ok or cont ~= route.map then
        if painter then painter:Clear() end
        stats.why = "no-position"
        return
    end
    local why = R.PinsMinimap.Gather(view)
    if why then
        if painter then painter:Clear() end
        stats.why = why
        return
    end
    local facing = view.rotating and view.facing or nil
    local half = view.halfWidth
    if not force and last.x == px and last.y == py and last.f == facing and last.r == view.radius and last.h == half
        and last.p == phase and last.seg == snap.seg and last.route == route and last.state == snap.state then
        stats.skipped = stats.skipped + 1
        return
    end
    last.x, last.y, last.f, last.r, last.h, last.p, last.seg, last.route, last.state = px, py, facing, view.radius, half, phase, snap.seg, route, snap.state
    Holder()
    stats.draws = stats.draws + 1
    stats.why = "drawn"
    local scale = half / view.radius
    local limit = half - INSET
    local square = Square()
    dr, dg, db = NP.Rgb(NP.Get("trailColor"))
    da = NP.Get("trailOpacity") / 100
    if snap.state == "recalculating" then da = da * 0.45 end
    dthick = math.max(1, NP.Get("trailWidth") - 1)
    ddots = NP.Get("trailStyle") == "dots"
    dants = NP.Get("ants") and not NP.ReducedMotion()
    cx, cy = half, -(holder:GetHeight() / 2)
    local reachYards = view.radius * 1.5
    painter:Begin()
    n = 0
    for i = snap.seg, route.n - 1 do
        local ax, ay = route.xs[i], route.ys[i]
        if i == snap.seg then ax, ay = px, py end
        local bx, by = route.xs[i + 1], route.ys[i + 1]
        -- legs nowhere near the view are skipped before anything is projected
        if NV.SegDist(px, py, ax, ay, bx, by) <= reachYards then
            local x1, y1 = NPaint.MinimapOffset(ax, ay, px, py, scale, facing)
            local x2, y2 = NPaint.MinimapOffset(bx, by, px, py, scale, facing)
            local c1, c2, c3, c4
            if square then c1, c2, c3, c4 = NPaint.ClipBox(x1, y1, x2, y2, -limit, -limit, limit, limit)
            else c1, c2, c3, c4 = NPaint.ClipCircle(x1, y1, x2, y2, limit) end
            if c1 then
                if n == 0 or xs[n] ~= c1 or ys[n] ~= c2 then
                    Flush()
                    n = 1
                    xs[1], ys[1] = c1, c2
                end
                n = n + 1
                xs[n], ys[n] = c3, c4
                if c3 ~= x2 or c4 ~= y2 then Flush() end
            else
                Flush()
            end
        else
            Flush()
        end
    end
    Flush()
    painter:End()
end
MM.Draw = Draw

local function Tick(elapsed)
    wait = wait + elapsed
    local every = (view.rotating and FAST) or SLOW
    if wait < every then return end
    if NP.Get("ants") and not NP.ReducedMotion() then phase = (phase + wait * NP.Get("antSpeed") * 10) % 10000 end
    wait = 0
    if Minimap:IsVisible() then Draw(false) elseif painter then painter:Clear() end
end

local function OnZoom() if ticking then Draw(true) end end

local function Update()
    local snap = NV.Snapshot()
    local want = Want() and snap.route ~= nil and (snap.state == "navigating" or snap.state == "recalculating")
    if want and not ticking then
        NV.AddTicker(Tick)
        R:On("MINIMAP_UPDATE_ZOOM", OnZoom)   -- zoom: drawn at once rather than at the next tick
        ticking = true
        Draw(true)
    elseif not want then
        if ticking then
            NV.RemoveTicker(Tick)
            R:Off("MINIMAP_UPDATE_ZOOM", OnZoom)
            ticking = false
        end
        if painter then painter:Clear() end
    else
        Draw(true)
    end
end
MM.Update = Update

NV.Subscribe(function(event)
    if event == "route" or event == "state" or event == "prefs" then Update() end
end)

function MM.Diagnostics()
    local l, d, pl, pd = 0, 0, 0, 0
    if painter then l, d, pl, pd = painter:Counts() end
    return { ticking = ticking, lines = l, dots = d, pooledLines = pl, pooledDots = pd, draws = stats.draws,
        skipped = stats.skipped, why = stats.why, square = Square() }
end
