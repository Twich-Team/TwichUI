-- TwichUI: world map exploration, caves
-- Zoom in on a cave and its own map (the game's art for it, map/Data.lua) surfaces at its real place, the land round it
-- dimming as it comes; zoom back out and it sinks. A cave lies in its zone's own world yards, so its map is placed through
-- the same conversion as everything else: your arrow (the game's, on the zone map underneath), TwichUI's pins, pings and
-- the navigation trail stay where they belong over it, and a pin placed there is placed on the zone at that spot. Which
-- floor you are on isn't known (Forever's map tables have no floors for its caves), so the arrow shows whichever floor is
-- up. A cave of several floors shows its first; the bar at the top switches them (remembered this session).
-- One cave at a time: the one under the middle of the view. Only its twelve textures are set, and let go as it sinks.
-- Over a cave the deepest zoom reaches as far as its map needs (map/View.lua asks FillZoomAt).

local R = TwichUI
local VM, MXP, MV, MW = R.MapViewMath, R.MapExplorePrefs, R.MapView, R.MapWorld
local MCV = {}
R.MapCaves = MCV

local ART_W, ART_H, TILE = 1002, 668, 256
local SURFACE = { 0.18, 0.45 }   -- share of the view's width a cave's map takes as it surfaces
local BAR_FROM = 0.6             -- how far surfaced before its bar shows
local VEIL = 0.65
local FILL = 0.9
local LEVEL = 7                  -- over the canvas's own level (the painting 2 to 5, terrain detail 6)

local groups                     -- the caves: { id, name, cont, floors, u0, v0, u1, v1 }
local layer, veil, tiles = nil, nil, {}
local current, strength, drawn = nil, 0, nil
local barKey                     -- what the bar shows now (redrawn only when that changes)
local floorOf = {}               -- [cave id] = the floor chosen this session
local stats = { surfaced = 0, floorChanges = 0 }

local function Groups()
    if groups then return groups end
    -- (built once the map can place things: before it has loaded, nothing would convert, and an empty list would stay)
    if not MV.Ready() then return {} end
    local D = R.MapExploreData
    local byKey = {}
    groups = {}
    for _, c in ipairs(D and D.caves or {}) do
        local u0, v0, u1, v1 = MW.YardsRect(c[3], c[4], c[5], c[6], c[7])
        if u0 then
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
    return groups
end
MCV.Groups = Groups

local function At(u, v)
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
    return MV.RectZoom(g.u0, g.v0, g.u1, g.v1) * FILL
end

function MCV.Surfaced() return current ~= nil and strength >= 0.5 end
function MCV.Current() return current, current and (floorOf[current.id] or 1) or nil, strength end

local function Layer()
    if layer then return layer end
    local root = R.MapArt.Root()
    layer = CreateFrame("Frame", nil, root)
    layer:SetAllPoints(root)
    layer:EnableMouse(false)
    veil = layer:CreateTexture(nil, "BACKGROUND")
    veil:SetAllPoints(root)
    veil:SetColorTexture(0.04, 0.03, 0.02, 1)
    for i = 1, 12 do tiles[i] = layer:CreateTexture(nil, "ARTWORK") end
    return layer
end

-- One floor's picture (1002 x 668 in a 4 x 3 grid of 256-pixel tiles) over its world rectangle.
local function Draw(g, n)
    local L = Layer()
    local fl = g.floors[n]
    local W, H = MW.Size()
    local root = R.MapArt.Root()
    local ux, vy = (fl.u1 - fl.u0) * W / ART_W, (fl.v1 - fl.v0) * H / ART_H   -- world pixels per art pixel
    for i = 1, 12 do
        local row, col = math.floor((i - 1) / 4), (i - 1) % 4
        local px0, py0 = col * TILE, row * TILE
        local pw, ph = math.min(TILE, ART_W - px0), math.min(TILE, ART_H - py0)
        local tex = tiles[i]
        tex:SetTexture(fl.tiles[i])
        tex:SetTexCoord(0, pw / TILE, 0, ph / TILE)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", root, "TOPLEFT", fl.u0 * W + px0 * ux, -(fl.v0 * H + py0 * vy))
        tex:SetSize(pw * ux, ph * vy)
        tex:Show()
    end
    drawn = g.id .. ":" .. n
end

local function Sink()
    if layer then
        layer:Hide()
        for _, t in ipairs(tiles) do t:SetTexture(nil) t:Hide() end
    end
    current, strength, drawn, barKey = nil, 0, nil, nil
    if R.MapControls then R.MapControls.HideContext("cave") end
end
MCV.Sink = Sink

local function Bar(g)
    local MC = R.MapControls
    if not MC then return end
    local n = floorOf[g.id] or 1
    MC.ShowContext("cave", {
        title = g.name, sub = "Cave map",
        note = "Your arrow is the game's own; which floor you are on isn't known.",
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

function MCV.Update()
    if not (MV.Ready() and MXP.Get("caves")) or (R.MapDungeonView and R.MapDungeonView.IsOpen()) then Sink() return end
    local u0, v0, u1, v1 = MV.ViewRect()
    local g = At((u0 + u1) / 2, (v0 + v1) / 2)
    local s = g and VM.Fade((g.u1 - g.u0) / (u1 - u0), SURFACE[1], SURFACE[2]) or 0
    if s <= 0.02 then Sink() return end
    if current ~= g then
        Sink()
        current = g
        stats.surfaced = stats.surfaced + 1
    end
    strength = s
    local n = floorOf[g.id] or 1
    if drawn ~= g.id .. ":" .. n then Draw(g, n) end
    local L = Layer()
    L:SetFrameLevel(MV.ArtLevel(LEVEL))
    L:Show()
    veil:SetAlpha(VEIL * s)
    for _, t in ipairs(tiles) do t:SetAlpha(s) end
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

function MCV.SetFloor(n)
    if not current or not n or n < 1 or n > #current.floors then return false end
    floorOf[current.id] = n
    stats.floorChanges = stats.floorChanges + 1
    MCV.Update()
    return true
end

MV.Subscribe(function(event)
    if event == "view" then MCV.Update()
    elseif event == "hide" or event == "off" or (event == "attach" and not MV.Active()) then Sink() end
end)
MXP.Subscribe(function() if MV.Ready() then MCV.Update() end end)

-- Read only, for /tui diagnostics and the tests.
function MCV.Snapshot()
    return { caves = groups and #groups or 0, surfaced = current and current.id or nil, strength = strength,
        floor = current and (floorOf[current.id] or 1) or nil, times = stats.surfaced, floorChanges = stats.floorChanges }
end
function MCV.Tile(i) return tiles[i] end
function MCV.Veil() return veil end
