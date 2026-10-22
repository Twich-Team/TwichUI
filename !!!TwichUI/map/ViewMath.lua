-- TwichUI: world map exploration, the arithmetic
-- Every conversion the map exploration uses, with no frames and no game calls, so each can be checked exactly
-- (tests/test_map_explore.lua). Three kinds of coordinates:
--   screen      the cursor in the map's own units (GetCursorPosition divided by the map's effective scale), as the
--               game's scroll container measures it
--   normalized  0..1 across the map being viewed (x east, y south), what pins, pings and the game's own pins use;
--               a point off the map is outside 0..1 and is never clamped here
--   world       yards on a continent (x north, y west), what the game's world-position functions use
-- The view is the scroll container's: the canvas (the map's art, canvasW x canvasH) drawn at `scale`, with the
-- normalized point (cx, cy) in the middle of a viewW x viewH window. Nothing here knows the game's internals: the
-- same rules are what the game's own scroll container follows (scroll limits that keep the map covering the
-- view, a cursor's normalized place from the canvas's left and top edges).

local R = TwichUI
local VM = {}
R.MapViewMath = VM

local function Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
VM.Clamp = Clamp

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
VM.Finite = Finite

---------------------------------------------------------------------------
-- The view
---------------------------------------------------------------------------
-- How far the middle of the view may go at `scale`: the map always covers the view along an axis where it is
-- larger, and stays centred along one where it is smaller. Returns minX, maxX, minY, maxY (normalized).
function VM.Extents(viewW, viewH, canvasW, canvasH, scale)
    local hx = math.min((viewW * 0.5 / scale) / canvasW, 0.5)
    local hy = math.min((viewH * 0.5 / scale) / canvasH, 0.5)
    return hx, 1 - hx, hy, 1 - hy
end

-- The middle (cx, cy) kept inside those limits.
function VM.ClampCenter(cx, cy, viewW, viewH, canvasW, canvasH, scale)
    local x0, x1, y0, y1 = VM.Extents(viewW, viewH, canvasW, canvasH, scale)
    return Clamp(cx, x0, x1), Clamp(cy, y0, y1)
end

-- The scale at which the whole map fits the view (the game's least zoom).
function VM.FitScale(viewW, viewH, canvasW, canvasH)
    return math.min(viewW / canvasW, viewH / canvasH)
end

-- Zooming from scale0 to scale1 about the normalized point (ax, ay) keeps that point where it is on screen: the
-- middle moves toward it by the change in scale. Returns the new middle (before any limits are applied).
function VM.Anchored(scale0, cx0, cy0, scale1, ax, ay)
    local k = scale0 / scale1
    return ax + (cx0 - ax) * k, ay + (cy0 - ay) * k
end

-- A screen point (the map's units) as a normalized point, given the canvas's left and top edges in its own
-- (scaled) units, as the game's scroll container reads the cursor. Not clamped: off the map is outside 0..1.
function VM.ToNormalized(sx, sy, left, top, scale, canvasW, canvasH)
    return (sx / scale - left) / canvasW, (top - sy / scale) / canvasH
end

-- ... and back.
function VM.ToScreen(nx, ny, left, top, scale, canvasW, canvasH)
    return (nx * canvasW + left) * scale, (top - ny * canvasH) * scale
end

-- The part of the map in view: left, right, top, bottom (normalized).
function VM.ViewRect(cx, cy, viewW, viewH, canvasW, canvasH, scale)
    local hx, hy = (viewW * 0.5 / scale) / canvasW, (viewH * 0.5 / scale) / canvasH
    return cx - hx, cx + hx, cy - hy, cy + hy
end

-- The scale and middle at which the normalized rectangle (u0, v0)-(u1, v1) fills `fill` (0..1) of the view.
function VM.RectView(u0, v0, u1, v1, viewW, viewH, canvasW, canvasH, fill)
    local w, h = math.abs(u1 - u0) * canvasW, math.abs(v1 - v0) * canvasH
    if w <= 0 or h <= 0 then return nil end
    local scale = math.min(viewW / w, viewH / h) * (fill or 1)
    return scale, (u0 + u1) / 2, (v0 + v1) / 2
end

-- The next scale for `notches` wheel notches of `step` percent each, within [lo, hi].
function VM.Step(scale, notches, step, lo, hi)
    return Clamp(scale * (1 + step / 100) ^ notches, lo, hi)
end

---------------------------------------------------------------------------
-- Easing (short and smooth; the caller decides whether to ease at all)
---------------------------------------------------------------------------
function VM.Ease(t)
    t = Clamp(t, 0, 1)
    local u = 1 - t
    return 1 - u * u * u
end

-- Scale is eased in proportion (a zoom looks even), position linearly.
function VM.LogLerp(a, b, t) return a * (b / a) ^ t end
function VM.Lerp(a, b, t) return a + (b - a) * t end

-- A value between 0 and 1 as v goes from a to b (smoothly, for fades).
function VM.Fade(v, a, b)
    if b <= a then return v >= b and 1 or 0 end
    local t = Clamp((v - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)
end

---------------------------------------------------------------------------
-- A map's place in the world
---------------------------------------------------------------------------
-- From the world positions of three of a map's corners (top left, top right, bottom left), the straight conversion
-- between world yards and the map's 0..1. Returns nil for a corner set that has no area (a map the game can't
-- place). The frame says whether the map is drawn north-up (axisAligned): tiles and art rectangles are only laid
-- on such maps.
function VM.MapFrame(tlx, tly, trx, try, blx, bly)
    if not (Finite(tlx) and Finite(tly) and Finite(trx) and Finite(try) and Finite(blx) and Finite(bly)) then return nil end
    local ax, ay = trx - tlx, try - tly        -- world per unit of map x
    local bx, by = blx - tlx, bly - tly        -- world per unit of map y
    local det = ax * by - ay * bx
    if math.abs(det) < 1e-9 then return nil end
    local f = { ox = tlx, oy = tly, ax = ax, ay = ay, bx = bx, by = by, det = det }
    local tol = 1e-6 * (math.abs(ax) + math.abs(ay) + math.abs(bx) + math.abs(by))
    f.axisAligned = math.abs(ax) <= tol and math.abs(by) <= tol
    return f
end

function VM.ToMap(f, wx, wy)
    local dx, dy = wx - f.ox, wy - f.oy
    return (dx * f.by - dy * f.bx) / f.det, (f.ax * dy - f.ay * dx) / f.det
end

function VM.ToWorld(f, u, v)
    return f.ox + u * f.ax + v * f.bx, f.oy + u * f.ay + v * f.by
end

-- A world rectangle (x north, y west: x0..x1, y0..y1 in any order) on the map: left, top, right, bottom (normalized).
function VM.WorldRectOnMap(f, x0, y0, x1, y1)
    local ua, va = VM.ToMap(f, math.max(x0, x1), math.max(y0, y1))   -- north-west corner
    local ub, vb = VM.ToMap(f, math.min(x0, x1), math.min(y0, y1))   -- south-east corner
    return math.min(ua, ub), math.min(va, vb), math.max(ua, ub), math.max(va, vb)
end

---------------------------------------------------------------------------
-- The game's terrain grid: 64 x 64 tiles of 533.33 yards a continent, column east, row south; one minimap
-- picture a tile.
---------------------------------------------------------------------------
VM.TILE = 1600 / 3
VM.ORIGIN = 32 * VM.TILE

-- A tile's world rectangle: north, west, south, east.
function VM.TileRect(col, row)
    local n, w = VM.ORIGIN - row * VM.TILE, VM.ORIGIN - col * VM.TILE
    return n, w, n - VM.TILE, w - VM.TILE
end

function VM.TileAt(wx, wy)
    return math.floor((VM.ORIGIN - wy) / VM.TILE), math.floor((VM.ORIGIN - wx) / VM.TILE)
end

-- The tiles a normalized rectangle of the map covers: col0, col1, row0, row1 (inside 0..63).
function VM.TilesIn(f, u0, v0, u1, v1)
    local c0, c1, r0, r1 = 63, 0, 63, 0
    for _, p in ipairs({ { u0, v0 }, { u1, v0 }, { u0, v1 }, { u1, v1 } }) do
        local col, row = VM.TileAt(VM.ToWorld(f, p[1], p[2]))
        if col < c0 then c0 = col end
        if col > c1 then c1 = col end
        if row < r0 then r0 = row end
        if row > r1 then r1 = row end
    end
    return Clamp(c0, 0, 63), Clamp(c1, 0, 63), Clamp(r0, 0, 63), Clamp(r1, 0, 63)
end

-- Yards across the map, east to west (its width in the world).
function VM.MapYards(f) return math.sqrt(f.ax * f.ax + f.ay * f.ay) end

---------------------------------------------------------------------------
-- Labels: whether two screen rectangles overlap (left, bottom, right, top)
---------------------------------------------------------------------------
function VM.Overlaps(a, b)
    return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end
