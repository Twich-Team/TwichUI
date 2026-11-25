-- TwichUI: world map exploration, caves
-- Zoom in on a cave and its own map (the game's art for it, map/Data.lua) surfaces at its real place, the land round it
-- dimming as it comes; zoom back out and it sinks. A cave lies in its zone's own world yards, so its map is placed through
-- the same conversion as everything else: your arrow (the game's, on the zone map underneath), TwichUI's pins, pings and
-- the navigation trail stay where they belong over it, and a pin placed there is placed on the zone at that spot. Which
-- floor you are on isn't known (Forever's map tables have no floors for its caves), so the arrow shows whichever floor is
-- up. A cave of several floors shows its first; the bar at the top switches them (remembered this session).
-- One cave at a time: visible artwork is retained until it leaves the view. Only its twelve painted textures are set,
-- and let go as it sinks. Framed source art is presented deliberately as a local chart, without moving/cropping geography.
-- Over a cave the deepest zoom reaches as far as its map needs (map/View.lua asks FillZoomAt).

local R = TwichUI
local VM, MXP, MV, MW = R.MapViewMath, R.MapExplorePrefs, R.MapView, R.MapWorld
local MCV = {}
R.MapCaves = MCV

local ART_W, ART_H, TILE = 1002, 668, 256
local SURFACE = { 0.18, 0.45 }   -- share of the view's width a cave's map takes as it surfaces
local OVERLAP = { 0.05, 0.5 }   -- visible share on each axis; readable at the center boundary, gone when offscreen
local BAR_FROM = 0.6             -- how far surfaced before its bar shows
local VEIL = 0.65
local FILL = 0.9
local LEVEL = 9                  -- above underground city artwork/interiors (7/8), below native markers
local ENTRY_SECONDS = 0.15       -- new chart entries/handoffs; no updater after this short transition

local groups                     -- the caves: { id, name, cont, floors, u0, v0, u1, v1 }
local layer, veil, tiles = nil, nil, {}
local current, strength, drawn = nil, 0, nil
local targetStrength, entryAge = 0, nil
local viewU0, viewV0, viewU1, viewV1
local barKey                     -- what the bar shows now (redrawn only when that changes)
local floorOf = {}               -- [cave id] = the floor chosen this session
local stats = { surfaced = 0, floorChanges = 0 }
local pictures
local chartShadow, chartEdges
local tilePlacements            -- at most twelve actual Draw placements; released on exit

local function ValidRect(u0, v0, u1, v1)
    return VM.Finite(u0) and VM.Finite(v0) and VM.Finite(u1) and VM.Finite(v1) and u1 > u0 and v1 > v0
end

local function Groups()
    if groups then return groups end
    -- (built once the map can place things: before it has loaded, nothing would convert, and an empty list would stay)
    if not MV.Ready() then return {} end
    local D = R.MapExploreData
    local byKey = {}
    groups = {}
    for _, c in ipairs(D and D.caves or {}) do
        local u0, v0, u1, v1 = MW.YardsRect(c[3], c[4], c[5], c[6], c[7])
        if ValidRect(u0, v0, u1, v1) then
            local key = c[9] and ("g" .. c[9]) or ("c" .. c[1])
            local g = byKey[key]
            if not g then
                g = { id = "cave:" .. c[1], name = c[2], cont = c[3], floors = {}, u0 = u0, v0 = v0, u1 = u1, v1 = v1 }
                byKey[key] = g
                groups[#groups + 1] = g
            end
            g.floors[#g.floors + 1] = { id = c[1], name = c[11] or c[2], order = c[10] or 0, tiles = c[8],
                u0 = u0, v0 = v0, u1 = u1, v1 = v1 }
            g.u0, g.v0 = math.min(g.u0, u0), math.min(g.v0, v0)
            g.u1, g.v1 = math.max(g.u1, u1), math.max(g.v1, v1)
        end
    end
    for _, g in ipairs(groups) do
        table.sort(g.floors, function(a, b) return a.order < b.order or (a.order == b.order and a.id < b.id) end)
    end
    -- WMO minimap pictures cover mines/tunnels with no verified painted micro map.
    local data = R.MapExploreLocalData
    for i, c in ipairs(data and data.caves or {}) do
        local u0, v0, u1, v1 = MW.YardsRect(c[1], c[2], c[3], c[4], c[5])
        if ValidRect(u0, v0, u1, v1) then
            groups[#groups + 1] = { id = "wmo:" .. i, name = "Underground area", cont = c[1],
                floors = { { name = "Interior", pictures = c } }, u0 = u0, v0 = v0, u1 = u1, v1 = v1 }
        end
    end
    -- Prefer a dedicated micro map, then the smallest interior on overlapping bounds.
    table.sort(groups, function(a, b)
        local ap, bp = a.floors[1].pictures ~= nil, b.floors[1].pictures ~= nil
        if ap ~= bp then return not ap end
        local aa, ba = (a.u1 - a.u0) * (a.v1 - a.v0), (b.u1 - b.u0) * (b.v1 - b.v0)
        return aa < ba or aa == ba and a.id < b.id
    end)
    return groups
end
MCV.Groups = Groups

local function At(u, v)
    if not (VM.Finite(u) and VM.Finite(v)) then return nil end
    for _, g in ipairs(Groups()) do
        if u >= g.u0 and u <= g.u1 and v >= g.v0 and v <= g.v1 then return g end
    end
    return nil
end
MCV.At = At

function MCV.Get(id)
    for _, g in ipairs(Groups()) do if g.id == id then return g end end
end

-- The zoom a cave's map needs to fill the view, over a cave (else nil).
function MCV.FillZoomAt(u, v)
    if not MXP.Get("caves") then return nil end
    local g = At(u, v)
    if not g then return nil end
    local zoom = MV.RectZoom(g.u0, g.v0, g.u1, g.v1)
    return zoom and zoom * FILL or nil
end

function MCV.Surfaced() return current ~= nil and strength >= 0.5 end
function MCV.Current() return current, current and (floorOf[current.id] or 1) or nil, strength end

local function VisibleStrength(g, u0, v0, u1, v1)
    local w, h, vw, vh = g.u1 - g.u0, g.v1 - g.v0, u1 - u0, v1 - v0
    local ow = math.min(g.u1, u1) - math.max(g.u0, u0)
    local oh = math.min(g.v1, v1) - math.max(g.v0, v0)
    if ow <= 0 or oh <= 0 then return 0 end
    -- The old fixed cave-edge band could leave a fully visible close-up chart
    -- almost transparent: anchored zoom need not put its center in that band.
    -- Measure visibility against the smaller view/art extent instead. A chart
    -- remains readable when the center crosses its edge, then fades as its
    -- actual artwork leaves the viewport. Both axes handle tall/narrow views.
    local focus = math.min(ow / math.min(w, vw), oh / math.min(h, vh))
    local zoom = math.min(w / vw, h / vh)
    return VM.Fade(zoom, SURFACE[1], SURFACE[2]) * VM.Fade(focus, OVERLAP[1], OVERLAP[2])
end

-- Geometric target strength; the incumbent is retained while visible to avoid
-- choosing alternating overlapping rectangles during small pans. Terrain uses
-- this same selection before/after our view listener, without duplicate math.
function MCV.StrengthAt(u0, v0, u1, v1)
    if not MXP.Get("caves") or (R.MapDungeonView and R.MapDungeonView.IsOpen()) then return nil, 0 end
    if not ValidRect(u0, v0, u1, v1) then return nil, 0 end
    if current then
        local s = VisibleStrength(current, u0, v0, u1, v1)
        if s > 0.005 then return current, s end
    end
    -- On entry prefer the chart actually under the camera. A tiny unrelated
    -- sliver at the viewport edge must not win merely because its area sorts
    -- first, then hide a much more readable central cave.
    local central = At((u0 + u1) / 2, (v0 + v1) / 2)
    if central then
        local s = VisibleStrength(central, u0, v0, u1, v1)
        if s > 0.02 then return central, s end
    end
    -- Start a local chart only when the user actually looks into it. Merely
    -- passing another cave in the corner must not dim an outdoor region.
    -- Once entered, the incumbent above survives panning beyond its center.
    return nil, 0
end

local function Layer()
    if layer then return layer end
    local root = R.MapArt.Root()
    layer = CreateFrame("Frame", nil, root)
    layer:SetAllPoints(root)
    layer:EnableMouse(false)
    veil = layer:CreateTexture(nil, "BACKGROUND")
    veil:SetAllPoints(root)
    veil:SetColorTexture(0.04, 0.03, 0.02, 1)
    chartShadow = layer:CreateTexture(nil, "BORDER", nil, -1)
    chartShadow:SetColorTexture(0.025, 0.018, 0.01, 0.7)
    chartEdges = {}
    for i = 1, 4 do
        chartEdges[i] = layer:CreateTexture(nil, "BORDER")
        chartEdges[i]:SetColorTexture(0.51, 0.35, 0.17, 1)
    end
    for i = 1, 12 do tiles[i] = layer:CreateTexture(nil, "ARTWORK") end
    if R.MapPictures then pictures = R.MapPictures.Create(layer) end
    return layer
end

local function HideChart()
    chartShadow:Hide()
    for _, edge in ipairs(chartEdges) do edge:Hide() end
end

local function PutChart(tex, root, x, y, w, h, alpha)
    tex:ClearAllPoints(); tex:SetPoint("TOPLEFT", root, "TOPLEFT", x, -y)
    tex:SetSize(w, h); tex:SetAlpha(alpha); tex:Show()
end

local function Chart(fl, s, u0, v0, u1, v1)
    if fl.pictures then
        tilePlacements = nil
        HideChart()
        return
    end
    local W, H = MW.Size()
    local vw, vh = MV.ViewSize()
    if not (VM.Finite(vw) and VM.Finite(vh)) or vw <= 0 or vh <= 0 then HideChart(); return end
    local px, py = (u1 - u0) * W / vw, (v1 - v0) * H / vh
    local l, t, r, b = fl.u0 * W, fl.v0 * H, fl.u1 * W, fl.v1 * H
    local root = R.MapArt.Root()
    PutChart(chartShadow, root, l - px * 3, t - py * 3, r - l + px * 6, b - t + py * 6, s)
    PutChart(chartEdges[1], root, l - px, t - py, r - l + px * 2, py, s * 0.75)
    PutChart(chartEdges[2], root, l - px, b, r - l + px * 2, py, s * 0.75)
    PutChart(chartEdges[3], root, l - px, t, px, b - t, s * 0.75)
    PutChart(chartEdges[4], root, r, t, px, b - t, s * 0.75)
end

-- One floor's picture (1002 x 668 in a 4 x 3 grid of 256-pixel tiles) over its world rectangle.
local function Draw(g, n)
    local L = Layer()
    local fl = g.floors[n]
    if fl.pictures then
        for _, tex in ipairs(tiles) do R.MapPictures.Forget(tex); tex:SetTexture(nil); tex:Hide() end
        R.MapPictures.Set(pictures, fl.pictures)
        drawn = g.id .. ":" .. n
        return
    end
    if pictures then R.MapPictures.Set(pictures, nil) end
    local W, H = MW.Size()
    local root = R.MapArt.Root()
    local ux, vy = (fl.u1 - fl.u0) * W / ART_W, (fl.v1 - fl.v0) * H / ART_H   -- world pixels per art pixel
    tilePlacements = {}
    for i = 1, 12 do
        local row, col = math.floor((i - 1) / 4), (i - 1) % 4
        local px0, py0 = col * TILE, row * TILE
        local pw, ph = math.min(TILE, ART_W - px0), math.min(TILE, ART_H - py0)
        local tex = tiles[i]
        if R.MapPictures then R.MapPictures.Forget(tex) end
        tex:SetTexture(fl.tiles[i])
        if R.MapPictures then R.MapPictures.BindIdentity(tex, fl.tiles[i]) end
        tex:SetTexCoord(0, pw / TILE, 0, ph / TILE)
        tex:ClearAllPoints()
        local left, top, width, height = fl.u0 * W + px0 * ux, fl.v0 * H + py0 * vy, pw * ux, ph * vy
        tex:SetPoint("TOPLEFT", root, "TOPLEFT", left, -top)
        tex:SetSize(width, height)
        tilePlacements[i] = { fileId = fl.tiles[i], bounds = { left / W, top / H, (left + width) / W, (top + height) / H },
            texCoord = { 0, pw / TILE, 0, ph / TILE } }
        tex:Show()
    end
    drawn = g.id .. ":" .. n
end

local function Sink()
    if current and R.MapTrace then R.MapTrace("cave-transition", "sink", current.id, strength, targetStrength) end
    if layer then
        layer:SetScript("OnUpdate", nil)
        layer:Hide()
        for _, t in ipairs(tiles) do
            if R.MapPictures then R.MapPictures.Forget(t) end
            t:SetTexture(nil); t:Hide()
        end
    end
    current, strength, drawn, barKey = nil, 0, nil, nil
    targetStrength, entryAge = 0, nil
    viewU0, viewV0, viewU1, viewV1 = nil, nil, nil, nil
    tilePlacements = nil
    if pictures then R.MapPictures.Set(pictures, nil) end
    if R.MapControls then R.MapControls.HideContext("cave") end
end
MCV.Sink = Sink

local function Bar(g)
    local MC = R.MapControls
    if not MC then return end
    local n = floorOf[g.id] or 1
    MC.ShowContext("cave", {
        title = g.name, sub = g.floors[1].pictures and "Cave map" or "Local cave chart",
        note = g.floors[1].pictures and "Interior minimap artwork; overlapping rooms are shown together."
            or "Your cave floor isn't detected automatically. Use the floor controls when available.",
        floors = #g.floors, floor = n, floorName = g.floors[n].name,
        onPrev = function() MCV.SetFloor(n - 1) end,
        onNext = function() MCV.SetFloor(n + 1) end,
        onLeave = function()
            local zone = MW.Deepest((g.u0 + g.u1) / 2, (g.v0 + g.v1) / 2)
            MV.FrameMap(zone)
        end,
        leaveTitle = "Leave the cave", leaveTip = "Zooms back out to the zone. Zooming out with the wheel does the same.",
    })
end

local function Apply(s, layout)
    local g = current
    strength = s
    local n = floorOf[g.id] or 1
    veil:SetAlpha(VEIL * s)
    if layout then
        Chart(g.floors[n], s, viewU0, viewV0, viewU1, viewV1)
    elseif not g.floors[n].pictures then
        chartShadow:SetAlpha(s)
        for _, edge in ipairs(chartEdges) do edge:SetAlpha(s * 0.75) end
    end
    if not g.floors[n].pictures then
        for _, t in ipairs(tiles) do
            if R.MapPictures then R.MapPictures.Show(t, s) else t:SetAlpha(s) end
        end
    end
    if pictures then R.MapPictures.Update(pictures, viewU0, viewV0, viewU1, viewV1, s) end
    if s >= BAR_FROM then
        if barKey ~= g.id .. ":" .. n then
            barKey = g.id .. ":" .. n
            Bar(g)
        end
    elseif barKey then
        barKey = nil
        if R.MapControls then R.MapControls.HideContext("cave") end
    end
end

local function FadeStep(_, elapsed)
    if not current or entryAge == nil then
        if layer then layer:SetScript("OnUpdate", nil) end
        return
    end
    if not (MV.Ready() and MXP.Get("caves")) or (MV.Active and not MV.Active())
        or (R.MapDungeonView and R.MapDungeonView.IsOpen()) then Sink(); return end
    if not VM.Finite(elapsed) or elapsed <= 0 then return end
    entryAge = math.min(ENTRY_SECONDS, entryAge + elapsed)
    Apply(targetStrength * VM.Fade(entryAge, 0, ENTRY_SECONDS), false)
    if entryAge >= ENTRY_SECONDS then
        entryAge = nil
        layer:SetScript("OnUpdate", nil)
        if R.MapTrace then R.MapTrace("cave-transition", "entry-end", current.id, strength, targetStrength) end
        -- Terrain remains beneath the new chart during entry. Once its actual
        -- displayed strength is complete, release fully covered terrain even
        -- if the user stops moving immediately after entering the cave.
        if R.MapDetail and R.MapDetail.Update then R.MapDetail.Update() end
    end
end
local fadeTick = R.Perf and R.Perf.Wrap("map.cave.fade", FadeStep) or FadeStep

function MCV.Update()
    if not (MV.Ready() and MXP.Get("caves")) or (R.MapDungeonView and R.MapDungeonView.IsOpen()) then Sink() return end
    local u0, v0, u1, v1 = MV.ViewRect()
    local g, s = MCV.StrengthAt(u0, v0, u1, v1)
    if s <= 0.02 then Sink() return end
    local entering = current ~= g
    if entering then
        Sink()
        current, entryAge = g, 0
        stats.surfaced = stats.surfaced + 1
    end
    targetStrength = s
    viewU0, viewV0, viewU1, viewV1 = u0, v0, u1, v1
    local n = floorOf[g.id] or 1
    if drawn ~= g.id .. ":" .. n then Draw(g, n) end
    local L = Layer()
    L:SetFrameLevel(MV.ArtLevel(LEVEL))
    L:Show()
    Apply(s * (entryAge and VM.Fade(entryAge, 0, ENTRY_SECONDS) or 1), true)
    if entering and R.MapTrace then R.MapTrace("cave-transition", "entry-start", current.id, strength, targetStrength) end
    if entryAge ~= nil then L:SetScript("OnUpdate", fadeTick) end
end

function MCV.SetFloor(n)
    if not current or not VM.Finite(n) or n % 1 ~= 0 or n < 1 or n > #current.floors then return false end
    floorOf[current.id] = n
    stats.floorChanges = stats.floorChanges + 1
    MCV.Update()
    return true
end

MCV.Update = R.Perf and R.Perf.Wrap("map.cave.update", MCV.Update) or MCV.Update
MV.Subscribe(function(event)
    if event == "view" then MCV.Update()
    elseif event == "hide" or event == "off" or (event == "attach" and not MV.Active()) then Sink() end
end)
MXP.Subscribe(function() if MV.Ready() then MCV.Update() end end)

-- Read only, for /tui diagnostics and the tests.
function MCV.Snapshot(coordinates)
    local out = { caves = groups and #groups or 0, surfaced = current and current.id or nil, strength = strength,
        targetStrength = targetStrength, entryFading = entryAge ~= nil, entryElapsedSeconds = entryAge or 0,
        entryDurationSeconds = ENTRY_SECONDS,
        floor = current and (floorOf[current.id] or 1) or nil, times = stats.surfaced, floorChanges = stats.floorChanges,
        selection = "center-entry-visible-exit", presentation = current and
            (current.floors[floorOf[current.id] or 1].pictures and "interior" or "local-chart") or nil,
        textures = {}, coordinates = coordinates == true and "owned artwork placements; not player position" or "withheld" }
    if coordinates == true and tilePlacements then
        for i, p in ipairs(tilePlacements) do
            local tex = tiles[i]
            out.textures[#out.textures + 1] = { fileId = p.fileId,
                bounds = { unpack(p.bounds) }, texCoord = { unpack(p.texCoord) }, alpha = tex:GetAlpha(),
                shown = layer:IsShown() and tex:IsShown(), level = layer.GetFrameLevel and layer:GetFrameLevel() or nil,
                alphaSource = "texture-local; native ancestor alpha not captured" }
        end
    end
    return out
end
function MCV.Tile(i) return tiles[i] end
function MCV.Veil() return veil end
