-- TwichUI: Navigation, drawing a route
-- The one way a route is drawn, on the world map, on the minimap and in the settings preview: lines and dots from a
-- pool that grows only as far as a route needs and never past its cap, positioned in the parent frame's own units.
-- Nothing here decides what to draw; the map views do, after clipping to what they show (the helpers below).
--   painter = NavPaint.New(parent, frameLevelOffset)
--   painter:Begin(); painter:Line(x1, y1, x2, y2, r, g, b, a, thick); painter:Dot(x, y, size, r, g, b, a); painter:End()
--   Coordinates: x right, y up, from the parent's TOPLEFT (so y is negative inside it).
-- Ants: dots moving along the route (NavPaint.Ants) are placed by distance along the clipped line, from a phase the view
-- keeps; with reduced motion the phase never moves.

local R = TwichUI
local P = {}
R.NavPaint = P

local DOT = R.PATH .. [[media\textures\nav-dot]]
local MAX_LINES, MAX_DOTS = 400, 320
P.MAX_LINES, P.MAX_DOTS = MAX_LINES, MAX_DOTS

local Painter = {}
Painter.__index = Painter

function P.New(parent)
    local self = setmetatable({ parent = parent, lines = {}, dots = {}, nl = 0, nd = 0, usedL = 0, usedD = 0 }, Painter)
    return self
end

function Painter:Begin() self.usedL, self.usedD = 0, 0 end

function Painter:Line(x1, y1, x2, y2, r, g, b, a, thick)
    if self.usedL >= MAX_LINES then return false end
    self.usedL = self.usedL + 1
    local l = self.lines[self.usedL]
    if not l then
        l = self.parent:CreateLine(nil, "ARTWORK")
        l:SetTexture([[Interface\Buttons\WHITE8x8]])
        self.lines[self.usedL] = l
        self.nl = self.usedL
    end
    l:SetStartPoint("TOPLEFT", self.parent, x1, y1)
    l:SetEndPoint("TOPLEFT", self.parent, x2, y2)
    l:SetThickness(thick)
    l:SetVertexColor(r, g, b, a)
    l:Show()
    return true
end

function Painter:Dot(x, y, size, r, g, b, a)
    if self.usedD >= MAX_DOTS then return false end
    self.usedD = self.usedD + 1
    local d = self.dots[self.usedD]
    if not d then
        d = self.parent:CreateTexture(nil, "OVERLAY")
        d:SetTexture(DOT)
        self.dots[self.usedD] = d
        self.nd = self.usedD
    end
    d:ClearAllPoints()
    d:SetPoint("CENTER", self.parent, "TOPLEFT", x, y)
    d:SetSize(size, size)
    d:SetVertexColor(r, g, b, a)
    d:Show()
    return true
end

-- Hides everything not drawn since Begin. Nothing is destroyed: the pool stays for the next draw.
function Painter:End()
    for i = self.usedL + 1, self.nl do self.lines[i]:Hide() end
    for i = self.usedD + 1, self.nd do self.dots[i]:Hide() end
    self.nl = math.max(self.nl, self.usedL)
    self.nd = math.max(self.nd, self.usedD)
end

function Painter:Clear() self:Begin() self:End() end

function Painter:Counts() return self.usedL, self.usedD, #self.lines, #self.dots end

---------------------------------------------------------------------------
-- Geometry (no frames: tested offline)
---------------------------------------------------------------------------
-- Clips segment (x1, y1)-(x2, y2) to the box [x0, x1b] x [y0, y1b] (Liang-Barsky). Returns the clipped ends, or nil.
function P.ClipBox(ax, ay, bx, by, minX, minY, maxX, maxY)
    local dx, dy = bx - ax, by - ay
    local t0, t1 = 0, 1
    local function edge(p, q)
        if p == 0 then return q >= 0 end
        local r = q / p
        if p < 0 then
            if r > t1 then return false end
            if r > t0 then t0 = r end
        else
            if r < t0 then return false end
            if r < t1 then t1 = r end
        end
        return true
    end
    if not (edge(-dx, ax - minX) and edge(dx, maxX - ax) and edge(-dy, ay - minY) and edge(dy, maxY - ay)) then return nil end
    return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
end

-- Clips a segment to a circle of radius r around the origin. Returns the clipped ends, or nil.
function P.ClipCircle(ax, ay, bx, by, r)
    local dx, dy = bx - ax, by - ay
    local a = dx * dx + dy * dy
    local b = 2 * (ax * dx + ay * dy)
    local c = ax * ax + ay * ay - r * r
    if a == 0 then
        if c <= 0 then return ax, ay, bx, by end
        return nil
    end
    local disc = b * b - 4 * a * c
    if disc < 0 then return nil end
    local s = math.sqrt(disc)
    local t0, t1 = (-b - s) / (2 * a), (-b + s) / (2 * a)
    if t0 > 1 or t1 < 0 then return nil end
    if t0 < 0 then t0 = 0 end
    if t1 > 1 then t1 = 1 end
    return ax + dx * t0, ay + dy * t0, ax + dx * t1, ay + dy * t1
end

-- A world point (x north, y west) as minimap pixels from its centre (right, up), for a player at (px, py) facing f
-- (radians counter-clockwise from north) when the minimap rotates, else nil. scale: pixels per yard.
function P.MinimapOffset(x, y, px, py, scale, facing)
    local sx = -(y - py) * scale       -- east is right
    local sy = (x - px) * scale        -- north is up
    if facing then
        local c, s = math.cos(facing), math.sin(facing)
        sx, sy = sx * c + sy * s, -sx * s + sy * c
    end
    return sx, sy
end

-- Dots along a polyline of pixel points (flat xs, ys; n points) every `gap` pixels, starting `phase` pixels in, written
-- into outX, outY (reused by the caller: nothing is allocated). Returns how many (at most `max`).
function P.Ants(xs, ys, n, gap, phase, max, outX, outY)
    local placed = 0
    local carry = phase % gap
    for i = 1, n - 1 do
        local ax, ay, bx, by = xs[i], ys[i], xs[i + 1], ys[i + 1]
        local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
        local d = carry
        while d <= len do
            if placed >= max then return placed end
            local t = len > 0 and d / len or 0
            placed = placed + 1
            outX[placed], outY[placed] = ax + (bx - ax) * t, ay + (by - ay) * t
            d = d + gap
        end
        carry = d - len
    end
    return placed
end
