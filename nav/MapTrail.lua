-- TwichUI: navigation, the world map
-- Two things on Blizzard's world map, both only while navigation is on:
--   * The route, drawn on the map: small gold dots for walking (a straight line: the game gives no
--     walking paths, and the steps say so), bronze dashes for a flight through its stops, a small square
--     at each flight point the route uses and a diamond at the destination. Nothing moves; only what is
--     still ahead is drawn, from where you stand.
--   * "Route to your map pin" in the map's filter menu (the magnifying glass). While a route is active the
--     menu also recalculates or stops it, and choosing the pin again plans a new route in its place. The pin itself is Blizzard's: Ctrl-click the map to place it. No click
--     on the map is taken over.
-- Drawn with plain colour textures and lines on one frame of ours over the map's canvas, so map pins
-- keep working as they do. Sizes are kept the same on screen at every zoom.

local R = TwichUI
local M = {}
R.NavMap = M

local DOT_SPACING, DOT_SIZE = 9, 3        -- screen pixels
local DASH, GAP, DASH_WIDTH = 7, 5, 2
local MARK_SIZE, GOAL_SIZE = 6, 9
local MAX_DOTS, MAX_DASHES, MAX_MARKS = 500, 300, 24
local REDRAW_MOVED, REDRAW_EVERY = 15, 1  -- yards moved, and seconds, before the map is drawn again on its own
local EDGE = 0.02                         -- map fractions drawn beyond the map's edge

local WALK = { 0.86, 0.70, 0.33 }         -- gold, a little brighter than the Chronicle's to read on map art
local FLIGHT = { 0.72, 0.55, 0.28 }       -- aged bronze
local SHADOW = { 0.08, 0.05, 0.03 }

local provider, added = nil, false
local frame
local pools = { dots = {}, unders = {}, dashes = {}, dashUnders = {}, marks = {}, markUnders = {} }
local used = { dots = 0, dashes = 0, marks = 0 }
local lastX, lastY, lastAt = nil, nil, 0
local menuHooked, waiting = false, false
local stats = { layouts = 0, clipped = 0 }

local function Nav() return R.Nav end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Texture(pool, i, layer, sub, color, alpha)
    local t = pool[i]
    if not t then
        t = frame:CreateTexture(nil, layer, nil, sub)
        t:SetColorTexture(color[1], color[2], color[3], alpha)
        pool[i] = t
    end
    t:Show()
    return t
end

local function Line(pool, i, sub, color, alpha)
    local l = pool[i]
    if not l then
        l = frame:CreateLine(nil, "ARTWORK", nil, sub)
        l:SetColorTexture(color[1], color[2], color[3], alpha)
        pool[i] = l
    end
    l:Show()
    return l
end

local function HideFrom(pool, from)
    for i = from, #pool do pool[i]:Hide() end
end

local function HideAll()
    used.dots, used.dashes, used.marks = 0, 0, 0
    for _, pool in pairs(pools) do HideFrom(pool, 1) end
end

local function Dot(x, y, size)
    if used.dots >= MAX_DOTS then stats.clipped = stats.clipped + 1 return end
    used.dots = used.dots + 1
    local i = used.dots
    local under = Texture(pools.unders, i, "ARTWORK", 0, SHADOW, 0.6)
    under:SetSize(size + 2 * size / DOT_SIZE, size + 2 * size / DOT_SIZE)
    under:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
    local dot = Texture(pools.dots, i, "ARTWORK", 1, WALK, 1)
    dot:SetSize(size, size)
    dot:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
end

local function Dash(x1, y1, x2, y2, width)
    if used.dashes >= MAX_DASHES then stats.clipped = stats.clipped + 1 return end
    used.dashes = used.dashes + 1
    local i = used.dashes
    local under = Line(pools.dashUnders, i, 0, SHADOW, 0.6)
    under:SetThickness(width * 2)
    under:SetStartPoint("TOPLEFT", frame, x1, -y1)
    under:SetEndPoint("TOPLEFT", frame, x2, -y2)
    local dash = Line(pools.dashes, i, 1, FLIGHT, 1)
    dash:SetThickness(width)
    dash:SetStartPoint("TOPLEFT", frame, x1, -y1)
    dash:SetEndPoint("TOPLEFT", frame, x2, -y2)
end

local function Mark(x, y, size, color, diamond)
    if used.marks >= MAX_MARKS then return end
    used.marks = used.marks + 1
    local i = used.marks
    local under = Texture(pools.markUnders, i, "OVERLAY", 0, SHADOW, 0.8)
    under:SetSize(size * 1.5, size * 1.5)
    under:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
    under:SetRotation(diamond and math.pi / 4 or 0)
    local mark = Texture(pools.marks, i, "OVERLAY", 1, color, 1)
    mark:SetColorTexture(color[1], color[2], color[3], 1)
    mark:SetSize(size, size)
    mark:SetPoint("CENTER", frame, "TOPLEFT", x, -y)
    mark:SetRotation(diamond and math.pi / 4 or 0)
end

local function Inside(mx, my)
    return mx >= -EDGE and mx <= 1 + EDGE and my >= -EDGE and my <= 1 + EDGE
end

-- Walking: evenly spaced dots from a to b (canvas units), skipping any beyond the map's edge.
local function Dotted(ax, ay, bx, by, w, h, scale)
    local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local step = DOT_SPACING / scale
    local count = math.floor(length / step)
    local size = DOT_SIZE / scale
    for k = 0, count do
        local t = count > 0 and (k * step + step / 2) / length or 0.5
        if t <= 1 then
            local x, y = ax + (bx - ax) * t, ay + (by - ay) * t
            if Inside(x / w, y / h) then Dot(x, y, size) end
        end
    end
end

-- A flight: dashes from a to b (canvas units).
local function Dashed(ax, ay, bx, by, scale)
    local length = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    if length <= 0 then return end
    local dash, period = DASH / scale, (DASH + GAP) / scale
    local width = DASH_WIDTH / scale
    local s = 0
    while s < length do
        local e = math.min(length, s + dash)
        Dash(ax + (bx - ax) * s / length, ay + (by - ay) * s / length, ax + (bx - ax) * e / length, ay + (by - ay) * e / length, width)
        s = s + period
    end
end

local function EnsureFrame(map)
    local canvas = map:GetCanvas()
    if not frame then
        frame = CreateFrame("Frame", nil, canvas)
        frame:EnableMouse(false)
    end
    frame:SetParent(canvas)
    frame:ClearAllPoints()
    frame:SetAllPoints(canvas)
    local levels = map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    if levels and levels.GetValidFrameLevel then
        frame:SetFrameLevel(levels:GetValidFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT"))   -- over the map art, under its icons
    end
    frame:Show()
    return canvas
end

local function Layout()
    HideAll()
    lastAt = GetTime()
    local N = Nav()
    local j = N and N.Current()
    local map = provider and provider.GetMap and provider:GetMap()
    if not (j and map and R:Enabled("navigation")) then
        if frame then frame:Hide() end
        return
    end
    local mapID = map:GetMapID()
    if not mapID then return end
    local canvas = EnsureFrame(map)
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
    if not (w and h and w > 0 and h > 0 and scale and scale > 0) then return end
    local W = R.NavWorld
    local continent = j.goal.map
    local function Canvas(x, y)
        local mx, my = W.ToMap(continent, x, y, mapID)
        if mx then return mx * w, my * h end
    end
    local px, py = W.Here()
    lastX, lastY = px, py
    stats.layouts = stats.layouts + 1
    local legs = j.plan.legs
    for i = j.index, #legs do
        local leg = legs[i]
        if leg.mode == "walk" then
            local fx, fy = leg.fromX, leg.fromY
            if i == j.index and px then fx, fy = px, py end
            local ax, ay = Canvas(fx, fy)
            local bx, by = Canvas(leg.toX, leg.toY)
            if ax and bx then Dotted(ax, ay, bx, by, w, h, scale) end
        else
            local pts = leg.points
            for k = 3, #pts, 2 do
                local ax, ay = Canvas(pts[k - 2], pts[k - 1])
                local bx, by = Canvas(pts[k], pts[k + 1])
                if ax and bx then Dashed(ax, ay, bx, by, scale) end
            end
        end
        if leg.toNode then
            local mx, my = Canvas(leg.toX, leg.toY)
            if mx and Inside(mx / w, my / h) then Mark(mx, my, MARK_SIZE / scale, FLIGHT, false) end
        end
    end
    local gx, gy = Canvas(j.goal.x, j.goal.y)
    if gx and Inside(gx / w, gy / h) then Mark(gx, gy, GOAL_SIZE / scale, WALK, true) end
end
M.Layout = Layout

local function MapShown() return WorldMapFrame and WorldMapFrame.IsShown and WorldMapFrame:IsShown() end

local function OnJourney(event)
    if not (added and MapShown()) then return end
    if event ~= "tick" then Layout() return end
    local x, y = R.NavWorld.Here()
    if x and lastX and GetTime() - lastAt >= REDRAW_EVERY and R.NavWorld.Distance(x, y, lastX, lastY) >= REDRAW_MOVED then
        Layout()
    end
end

---------------------------------------------------------------------------
-- The world map's data provider: told when the map opens, changes map, zooms or closes.
---------------------------------------------------------------------------
local function MakeProvider()
    local p = CreateFromMixins(MapCanvasDataProviderMixin)
    function p:RefreshAllData() Layout() end
    function p:RemoveAllData() HideAll() end
    function p:OnCanvasScaleChanged() Layout() end
    function p:OnCanvasSizeChanged() Layout() end
    return p
end

---------------------------------------------------------------------------
-- The filter menu
---------------------------------------------------------------------------
local function Add(tooltip, text, r, g, b)
    tooltip:AddLine(text, r or 1, g or 1, b or 1, true)
end

-- The route to the pin as it would be planned now, or why there is none.
function M.PinTooltip(tooltip)
    local N = Nav()
    tooltip:SetText("Route to your map pin", 1, 1, 1)
    local plan, goal = N.Preview()
    if not plan then
        Add(tooltip, N.MESSAGES[goal] or N.MESSAGES["no-route"], 1, 0.45, 0.4)
        return
    end
    Add(tooltip, "Fastest estimated route using supported, known travel options:", 0.8, 0.8, 0.8)
    for i, leg in ipairs(plan.legs) do
        Add(tooltip, ("%d. %s"):format(i, N.Instruction(leg, goal)))
        Add(tooltip, "    " .. N.TimeNote(leg, nil, plan.speedLearned), 0.7, 0.7, 0.7)
    end
    Add(tooltip, (plan.minimum and "In all: at least " or "In all: about ") .. N.Duration(plan.seconds), 1, 0.82, 0)
    if plan.flightsUnknown then
        Add(tooltip, N.FLIGHTS_UNKNOWN, 1, 0.82, 0)
    end
    Add(tooltip, "Walking and known flight paths only. Boats, zeppelins, portals and the Hearthstone aren't used yet. TwichUI suggests the way; you travel it.", 0.6, 0.6, 0.6)
end

local function AddMenu(_, root)
    if not (R:Enabled("navigation") and Nav() and root and root.CreateButton) then return end
    local N = Nav()
    if root.CreateDivider then root:CreateDivider() end
    if root.CreateTitle then root:CreateTitle("TwichUI navigation") end
    -- With a route active this plans a new one to wherever the pin is now, in its place.
    local start = root:CreateButton("Route to your map pin", function() N.StartToPin() end)
    if start and start.SetTooltip then start:SetTooltip(M.PinTooltip) end
    if N.Current() then
        local recalc = root:CreateButton("Recalculate the route", function() N.Recalculate() end)
        if recalc and recalc.SetTooltip then
            recalc:SetTooltip(function(tooltip)
                tooltip:SetText("Recalculate the route", 1, 1, 1)
                Add(tooltip, "Plans again from where you stand, to the same destination.", 0.8, 0.8, 0.8)
            end)
        end
        root:CreateButton("Stop the route", function() N.Stop() end)
    end
end

---------------------------------------------------------------------------
-- On and off
---------------------------------------------------------------------------
local function Install()
    if not (WorldMapFrame and WorldMapFrame.AddDataProvider and CreateFromMixins and MapCanvasDataProviderMixin) then return false end
    provider = provider or MakeProvider()
    return true
end

-- Puts the route on the map (and its menu entry) while navigation is on. Safe to call any number of times.
function M.Refresh()
    local on = R:Enabled("navigation")
    if not menuHooked and Menu and Menu.ModifyMenu then
        menuHooked = true   -- can't be undone: AddMenu checks the setting each time the menu opens
        Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", AddMenu)
    end
    if on and not provider and not Install() and not waiting then
        waiting = true      -- the world map loads later on some clients
        R:On("ADDON_LOADED", function(name)
            if name == "Blizzard_WorldMap" then M.Refresh() end
        end)
    end
    if on and provider and not added then
        WorldMapFrame:AddDataProvider(provider)
        added = true
    elseif not on and added then
        WorldMapFrame:RemoveDataProvider(provider)
        added = false
        HideAll()
        if frame then frame:Hide() end
    end
end

function M.Snapshot()
    return { provider = provider ~= nil, added = added, menu = menuHooked, layouts = stats.layouts, clipped = stats.clipped,
        dots = used.dots, dashes = used.dashes, marks = used.marks }
end

if R.Nav then R.Nav.OnChange(OnJourney) end
