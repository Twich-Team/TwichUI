-- TwichUI Layouts: screen geometry, the layer that fits a layout to this screen (architecture.md §7, §12)
-- Pure, like the composer: the same rules and the same screen always give the same places, and nothing here reads
-- saved variables or calls the game (LY.Screen at the end is the one function that reads the screen, and it only reads).
--
-- Coordinates are UIParent units with the origin at the centre of the screen, x to the right and y up, which is how
-- TwichUI and EllesmereUI store most positions. A rect is { x, y, w, h } (its centre and size) with l, r, b, t filled in.
--
-- What it does, in order, for one screen (w × h, the UIParent size the player's own UI scale gives):
--   1. The composition area: centred, as tall as the screen and at most maxAspect times as wide. On a screen wider
--      than that (super-ultrawide), the edge components sit at the area's edges, not the far edges of the glass.
--   2. Each component, in dependency order (what it is anchored to first; ties by id): its size (its reference size,
--      times the density factor if it scales with density, held within its bounds and never under its readable
--      minimum), then its place: one of its points on one point of the area, the screen or another component, with the
--      offset it has in the author's own layout. Below the narrow width, a component's narrow rule replaces both.
--   3. Two small rules, each applied once and in that order, with no searching: room (shrink toward a neighbour so as
--      not to overlap it, but not under the minimum) and above (move up clear of a neighbour). Then clamping on screen.
--   4. Diagnostics for the managed components: overlaps, anything still off screen, clamping, a minimum that won.
-- There is no general constraint solving: a layout that can't fit says so, and nothing is shrunk to make it fit.
--
-- The author's reference screen (canvas) reproduces the author's layout exactly: every offset is measured from it.
--
-- Variants (Phase 5). A package's geometry is the rules the layouts share. `variants[id]` may add components and
-- attachments to them, or replace ones of the same id, for that variant only (G.Spec): Compact Adventure shares the
-- minimap, chat, meter and the rest with Classic and gives the unit frames and bars block its own box. A variant is
-- checked as the whole spec it makes, so each layout is complete by itself; a variant that names nothing here (Classic)
-- uses the shared rules as they are.

local R = TwichUI
local LY = R.Layouts
local G = {}
LY.Geometry = G

G.POINTS = LY.Set({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })
G.TOLERANCE = 1          -- overlaps and moves smaller than this many units are not reported
G.MAX_COMPONENTS = 24
G.MAX_DIM = 20000        -- no screen, size or offset is larger than this

local FIELDS = LY.Set({ "canvas", "margin", "area", "densities", "narrow", "components", "attach" })
local VARIANT_FIELDS = LY.Set({ "components", "attach", "narrow", "area" })   -- what a variant may add or replace
local COMPONENT = LY.Set({ "label", "managed", "ref", "size", "anchor", "min", "max", "share", "density", "room", "above",
    "narrow", "applied" })
local ANCHOR = LY.Set({ "point", "to", "rel", "x", "y" })
local SIDES = { right = "x", left = "x", up = "y", down = "y" }

local function Finite(n) return type(n) == "number" and n == n and n > -G.MAX_DIM and n < G.MAX_DIM end

---------------------------------------------------------------------------
-- Rects and points
---------------------------------------------------------------------------
function G.Rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h, l = x - w / 2, r = x + w / 2, b = y - h / 2, t = y + h / 2 }
end

-- The x, y of one of a rect's nine points.
function G.Point(rect, point)
    local x, y = rect.x, rect.y
    if point:find("LEFT") then x = rect.l elseif point:find("RIGHT") then x = rect.r end
    if point:find("TOP") then y = rect.t elseif point:find("BOTTOM") then y = rect.b end
    return x, y
end

-- The rect that has its point at (px, py).
local function Place(point, px, py, w, h)
    local x, y = px, py
    if point:find("LEFT") then x = px + w / 2 elseif point:find("RIGHT") then x = px - w / 2 end
    if point:find("TOP") then y = py - h / 2 elseif point:find("BOTTOM") then y = py + h / 2 end
    return G.Rect(x, y, w, h)
end

G.Place = Place   -- Elements.lua places a piece by one of its points

local function Overlap(a, b)
    return math.min(a.r, b.r) - math.max(a.l, b.l), math.min(a.t, b.t) - math.max(a.b, b.b)
end

function G.Screen(w, h) return G.Rect(0, 0, w, h) end

-- The composition area of a screen: centred, full height, at most maxAspect × h wide.
function G.Area(spec, w, h)
    local max = spec.area and spec.area.maxAspect
    local aw = (max and w > h * max) and h * max or w
    return G.Rect(0, 0, aw, h)
end

---------------------------------------------------------------------------
-- Checking a geometry spec (Package.lua calls this). Adds problems; returns the components' resolve order or nil.
---------------------------------------------------------------------------
local function CheckSize(t, where, P, allowZero)
    if type(t) ~= "table" then P.add("not-table", where) return end
    for k, v in pairs(t) do
        if k ~= "w" and k ~= "h" then P.add("unknown-field", where .. "." .. tostring(k))
        elseif not Finite(v) or v < 0 or (v == 0 and not allowZero) then P.add("bad-value", where .. "." .. k) end
    end
end

local function CheckAnchor(a, where, P, ids, explicit)
    if type(a) ~= "table" then P.add("not-table", where) return end
    for k in pairs(a) do if not ANCHOR[k] then P.add("unknown-field", where .. "." .. tostring(k)) end end
    if not G.POINTS[a.point] then P.add("bad-value", where .. ".point") end
    if not G.POINTS[a.rel] then P.add("bad-value", where .. ".rel") end
    if not (a.to == "area" or a.to == "screen" or (type(a.to) == "string" and ids[a.to])) then P.add("bad-target", where .. ".to") end
    if (a.x ~= nil and not Finite(a.x)) or (a.y ~= nil and not Finite(a.y)) then P.add("bad-value", where) end
    if explicit and (a.x == nil or a.y == nil) then P.add("no-offset", where) end
end

-- room needs the component anchored on the far side (a right room needs a left anchor), so shrinking keeps it in place
local ROOM_ANCHOR = { right = "LEFT", left = "RIGHT", up = "BOTTOM", down = "TOP" }

local function CheckRule(rule, where, P, ids, anchor, kind)
    if type(rule) ~= "table" then P.add("not-table", where) return end
    for k in pairs(rule) do
        if k ~= "of" and k ~= "gap" and k ~= "side" then P.add("unknown-field", where .. "." .. tostring(k)) end
    end
    if not (type(rule.of) == "string" and ids[rule.of]) then P.add("bad-target", where .. ".of") end
    if rule.gap ~= nil and (not Finite(rule.gap) or rule.gap < 0) then P.add("bad-value", where .. ".gap") end
    if kind == "room" then
        if not SIDES[rule.side] then P.add("bad-value", where .. ".side")
        elseif anchor and type(anchor.point) == "string" and not anchor.point:find(ROOM_ANCHOR[rule.side]) then
            P.add("room-needs-anchor", where)
        end
    elseif rule.side ~= nil then P.add("unknown-field", where .. ".side") end
end

-- The order components resolve in: each after what it is anchored to and what its rules look at. nil on a cycle.
local function Order(comps, ids)
    local deps, n = {}, 0
    for id in pairs(ids) do
        n = n + 1
        local c, d = comps[id], {}
        local function Need(other) if type(other) == "string" and ids[other] and other ~= id then d[other] = true end end
        if type(c.anchor) == "table" then Need(c.anchor.to) end
        if type(c.narrow) == "table" then
            if type(c.narrow.anchor) == "table" then Need(c.narrow.anchor.to) end
            if type(c.narrow.room) == "table" then Need(c.narrow.room.of) end
        end
        if type(c.room) == "table" then Need(c.room.of) end
        if type(c.above) == "table" then Need(c.above.of) end
        deps[id] = d
    end
    local order, done = {}, {}
    while #order < n do
        local ready = {}
        for id in pairs(ids) do
            if not done[id] then
                local ok = true
                for d in pairs(deps[id]) do if not done[d] then ok = false break end end
                if ok then ready[#ready + 1] = id end
            end
        end
        if #ready == 0 then return nil end
        table.sort(ready)
        for _, id in ipairs(ready) do done[id] = true; order[#order + 1] = id end
    end
    return order
end

-- One whole spec (a variant already merged in). Returns the components' resolve order or nil; problems go to P.
local function CheckSpec(spec, P, where)
    where = where or "geometry"
    if type(spec) ~= "table" then P.add("not-table", where) return nil end
    for k in pairs(spec) do if not FIELDS[k] then P.add("unknown-field", where .. "." .. tostring(k)) end end
    local cv = spec.canvas
    if type(cv) ~= "table" or not (Finite(cv.w) and Finite(cv.h) and cv.w > 0 and cv.h > 0) then P.add("bad-value", where .. ".canvas") end
    if type(cv) == "table" then
        for k in pairs(cv) do if k ~= "w" and k ~= "h" and k ~= "note" then P.add("unknown-field", where .. ".canvas." .. tostring(k)) end end
        if cv.note ~= nil and not LY.Plain(cv.note, 80) then P.add("bad-value", where .. ".canvas.note") end
    end
    if spec.margin ~= nil and (not Finite(spec.margin) or spec.margin < 0) then P.add("bad-value", where .. ".margin") end
    if spec.narrow ~= nil and (not Finite(spec.narrow) or spec.narrow <= 0) then P.add("bad-value", where .. ".narrow") end
    if spec.area ~= nil then
        local a = spec.area
        if type(a) ~= "table" or not (Finite(a.maxAspect) and a.maxAspect >= 1) then P.add("bad-value", where .. ".area")
        else for k in pairs(a) do if k ~= "maxAspect" then P.add("unknown-field", where .. ".area." .. tostring(k)) end end end
    end
    local dens = spec.densities
    if type(dens) ~= "table" or dens.standard ~= 1 then P.add("bad-value", where .. ".densities")
    else
        local n = 0
        for id, f in pairs(dens) do
            n = n + 1
            if not LY.IsId(id, 24) or not (Finite(f) and f >= 0.5 and f <= 2) then P.add("bad-value", where .. ".densities." .. tostring(id)) end
        end
        if n > 6 then P.add("too-many", where .. ".densities") end
    end
    local comps = spec.components
    if type(comps) ~= "table" or next(comps) == nil then P.add("no-components", where .. ".components") return nil end
    local ids, n = {}, 0
    for id in pairs(comps) do
        n = n + 1
        if LY.IsId(id, 32) then ids[id] = true else P.add("bad-id", where .. ".components." .. tostring(id)) end
    end
    if n > G.MAX_COMPONENTS then P.add("too-many", where .. ".components") end
    for id in pairs(ids) do
        local c, w = comps[id], where .. ".components." .. id
        if type(c) ~= "table" then P.add("not-table", w)
        else
            for k in pairs(c) do if not COMPONENT[k] then P.add("unknown-field", w .. "." .. tostring(k)) end end
            if c.label ~= nil and not LY.Plain(c.label, 40) then P.add("bad-value", w .. ".label") end
            for _, k in ipairs({ "managed", "density" }) do
                if c[k] ~= nil and type(c[k]) ~= "boolean" then P.add("bad-value", w .. "." .. k) end
            end
            if c.applied ~= nil and not LY.Plain(c.applied, 48) then P.add("bad-value", w .. ".applied") end
            if c.ref ~= nil then
                local rf = c.ref
                if type(rf) ~= "table" or not (Finite(rf.x) and Finite(rf.y)) then P.add("bad-value", w .. ".ref")
                else
                    for k in pairs(rf) do if k ~= "x" and k ~= "y" and k ~= "w" and k ~= "h" then P.add("unknown-field", w .. ".ref." .. tostring(k)) end end
                    CheckSize({ w = rf.w, h = rf.h }, w .. ".ref", P, true)
                end
                if c.size ~= nil then P.add("ref-and-size", w) end
            elseif c.size ~= nil then CheckSize(c.size, w .. ".size", P)
            else P.add("no-size", w) end
            if c.anchor == nil then P.add("no-anchor", w) else CheckAnchor(c.anchor, w .. ".anchor", P, ids, c.ref == nil) end
            if c.min ~= nil then CheckSize(c.min, w .. ".min", P) end
            if c.max ~= nil then CheckSize(c.max, w .. ".max", P) end
            if c.share ~= nil then
                CheckSize(c.share, w .. ".share", P)
                if type(c.share) == "table" and ((c.share.w or 0) > 1 or (c.share.h or 0) > 1) then P.add("bad-value", w .. ".share") end
            end
            if c.room ~= nil then CheckRule(c.room, w .. ".room", P, ids, c.anchor, "room") end
            if c.above ~= nil then CheckRule(c.above, w .. ".above", P, ids, nil, "above") end
            if c.narrow ~= nil then
                local nw = c.narrow
                if type(nw) ~= "table" then P.add("not-table", w .. ".narrow")
                else
                    for k in pairs(nw) do
                        if k ~= "anchor" and k ~= "w" and k ~= "h" and k ~= "room" then P.add("unknown-field", w .. ".narrow." .. tostring(k)) end
                    end
                    if spec.narrow == nil then P.add("narrow-without-width", w .. ".narrow") end
                    if nw.anchor ~= nil then CheckAnchor(nw.anchor, w .. ".narrow.anchor", P, ids, true) end
                    for _, k in ipairs({ "w", "h" }) do
                        if nw[k] ~= nil and not (Finite(nw[k]) and nw[k] > 0 and nw[k] <= 2) then P.add("bad-value", w .. ".narrow." .. k) end
                    end
                    if nw.room ~= nil then CheckRule(nw.room, w .. ".narrow.room", P, ids, nw.anchor or c.anchor, "room") end
                end
            end
        end
    end
    local order = Order(comps, ids)
    if not order then P.add("anchor-cycle", where .. ".components") end
    if spec.attach ~= nil then
        if type(spec.attach) ~= "table" then P.add("not-table", where .. ".attach")
        else
            for adapterId, map in pairs(spec.attach) do
                local a = LY.ADAPTERS[adapterId]
                local positions = a and a.Positions and a.Positions()
                local aw = where .. ".attach." .. tostring(adapterId)
                if not positions then P.add("unknown-adapter", aw)
                elseif type(map) ~= "table" then P.add("not-table", aw)
                else
                    for posId, to in pairs(map) do
                        local comp, pt
                        if type(to) == "string" then comp, pt = to:match("^([%w%-]+):?(%u*)$") end
                        if not positions[posId] then P.add("unknown-position", aw .. "." .. tostring(posId))
                        elseif not (comp and ids[comp]) or (pt ~= "" and not G.POINTS[pt]) then P.add("bad-target", aw .. "." .. posId) end
                    end
                end
            end
        end
    end
    return order
end

---------------------------------------------------------------------------
-- Variants: the shared rules with one variant's own components and attachments
---------------------------------------------------------------------------
local specs = setmetatable({}, { __mode = "k" })   -- spec -> { [variant] = merged }; the merge shares the package's tables

-- The whole spec of one variant: the shared rules, with the variant's components and attachments added or replacing
-- those of the same id (an attachment replaces by position), and its narrow width or area if it gives one. Without
-- variants, or for a variant that names nothing, it is the spec itself. Never changes its arguments. A malformed
-- `variants` is left for G.Check to refuse: here it is read as nothing.
function G.Spec(spec, variant)
    local v = type(spec) == "table" and type(variant) == "string" and type(spec.variants) == "table" and spec.variants[variant]
    if type(v) ~= "table" then return spec end
    local cache = specs[spec]
    if not cache then cache = {}; specs[spec] = cache end
    if cache[variant] then return cache[variant] end
    local out = {}
    for k, x in pairs(spec) do if k ~= "variants" then out[k] = x end end
    if type(v.components) == "table" then
        local comps = {}
        for id, c in pairs(type(spec.components) == "table" and spec.components or {}) do comps[id] = c end
        for id, c in pairs(v.components) do comps[id] = c end
        out.components = comps
    end
    if type(v.attach) == "table" then
        local attach = {}
        for adapterId, map in pairs(type(spec.attach) == "table" and spec.attach or {}) do attach[adapterId] = map end
        for adapterId, map in pairs(v.attach) do
            if type(map) == "table" and type(attach[adapterId]) == "table" then
                local m = {}
                for posId, to in pairs(attach[adapterId]) do m[posId] = to end
                for posId, to in pairs(map) do m[posId] = to end
                attach[adapterId] = m
            else attach[adapterId] = map end
        end
        out.attach = attach
    end
    if v.narrow ~= nil then out.narrow = v.narrow end
    if v.area ~= nil then out.area = v.area end
    cache[variant] = out
    return out
end

-- spec: the package's geometry (the shared rules and, if it has them, `variants`). The shared rules and every variant's
-- whole spec are checked, each as complete by itself. Returns the shared rules' resolve order or nil; problems go to P.
-- (Package.lua also checks that each variant named here is one of the package's.)
function G.Check(spec, P, where)
    where = where or "geometry"
    if type(spec) ~= "table" then P.add("not-table", where) return nil end
    local shared = spec
    if spec.variants ~= nil then
        shared = {}
        for k, x in pairs(spec) do if k ~= "variants" then shared[k] = x end end
    end
    local order = CheckSpec(shared, P, where)
    local variants = spec.variants
    if variants ~= nil then
        if type(variants) ~= "table" then P.add("not-table", where .. ".variants") return order end
        local n = 0
        for id, v in pairs(variants) do
            n = n + 1
            local at = where .. ".variants." .. tostring(id)
            if not LY.IsId(id) then P.add("bad-id", at)
            elseif type(v) ~= "table" then P.add("not-table", at)
            else
                local ok = true
                for k, x in pairs(v) do
                    if not VARIANT_FIELDS[k] then P.add("unknown-field", at .. "." .. tostring(k)); ok = false
                    elseif (k == "components" or k == "attach" or k == "area") and type(x) ~= "table" then P.add("not-table", at .. "." .. k); ok = false
                    elseif k == "attach" then
                        for adapterId, map in pairs(x) do
                            if type(map) ~= "table" then P.add("not-table", at .. ".attach." .. tostring(adapterId)); ok = false end
                        end
                    end
                end
                if ok then CheckSpec(G.Spec(spec, id), P, at) end
            end
        end
        if n > LY.MAX_VARIANTS then P.add("too-many", where .. ".variants") end
    end
    return order
end

-- The attach maps of one variant ({ [adapter] = { [position id] = "component[:POINT]" } }).
function G.Attach(spec, variant)
    local s = G.Spec(spec, variant)
    return type(s) == "table" and s.attach or nil
end

---------------------------------------------------------------------------
-- Resolving
---------------------------------------------------------------------------
local function Size(c, f, narrow, area)
    local w, h
    if c.ref then w, h = c.ref.w or 0, c.ref.h or 0 else w, h = c.size.w, c.size.h end
    if c.density then w, h = w * f, h * f end
    if narrow and c.narrow then w, h = w * (c.narrow.w or 1), h * (c.narrow.h or 1) end
    local notes = {}
    local maxW, maxH = c.max and c.max.w, c.max and c.max.h
    if c.share and c.share.w then maxW = math.min(maxW or math.huge, area.w * c.share.w) end
    if c.share and c.share.h then maxH = math.min(maxH or math.huge, area.h * c.share.h) end
    if maxW and w > maxW then w = maxW; notes[#notes + 1] = "max-w" end
    if maxH and h > maxH then h = maxH; notes[#notes + 1] = "max-h" end
    if c.min and c.min.w and w < c.min.w then w = c.min.w; notes[#notes + 1] = "min-w" end
    if c.min and c.min.h and h < c.min.h then h = c.min.h; notes[#notes + 1] = "min-h" end
    return w, h, notes
end

local function Target(to, area, screen, rects)
    if to == "area" then return area end
    if to == "screen" then return screen end
    return rects[to]
end

-- The anchor offset: given, or what the author's own layout has between the two points.
local function Offset(a, c, refs, canvasArea, canvasScreen)
    if a.x ~= nil then return a.x, a.y end
    local px, py = G.Point(refs.own[c], a.point)
    local tx, ty = G.Point(Target(a.to, canvasArea, canvasScreen, refs.rects), a.rel)
    return px - tx, py - ty
end

-- Room: shrink along one axis so the far edge stays clear of a neighbour (only where the two overlap on the other axis).
local function Room(rect, c, rule, other, anchorPoint)
    if not other or other.w == 0 or other.h == 0 then return rect end
    local gap = rule.gap or 0
    local ox, oy = Overlap(rect, other)
    local axis = SIDES[rule.side]
    if (axis == "x" and oy <= 0) or (axis == "y" and ox <= 0) then return rect end
    local w, h = rect.w, rect.h
    if rule.side == "right" then w = math.min(w, other.l - gap - rect.l)
    elseif rule.side == "left" then w = math.min(w, rect.r - (other.r + gap))
    elseif rule.side == "up" then h = math.min(h, other.b - gap - rect.b)
    else h = math.min(h, rect.t - (other.t + gap)) end
    local floored = false
    if c.min and c.min.w and w < c.min.w then w = c.min.w; floored = true end
    if c.min and c.min.h and h < c.min.h then h = c.min.h; floored = true end
    if w <= 0 then w = rect.w end
    if h <= 0 then h = rect.h end
    if w == rect.w and h == rect.h then return rect, floored end
    local px, py = G.Point(rect, anchorPoint)
    return Place(anchorPoint, px, py, w, h), floored
end

local function Clamp(rect, screen, margin)
    local dx, dy = 0, 0
    local l, r, b, t = screen.l + margin, screen.r - margin, screen.b + margin, screen.t - margin
    local fitsX, fitsY = rect.w <= r - l, rect.h <= t - b
    if fitsX then
        if rect.l < l then dx = l - rect.l elseif rect.r > r then dx = r - rect.r end
    end
    if fitsY then
        if rect.b < b then dy = b - rect.b elseif rect.t > t then dy = t - rect.t end
    end
    if dx == 0 and dy == 0 then return rect, 0, fitsX and fitsY end
    return G.Rect(rect.x + dx, rect.y + dy, rect.w, rect.h), math.max(math.abs(dx), math.abs(dy)), fitsX and fitsY
end

local function One(spec, order, screenW, screenH, f, refs)
    local comps = spec.components
    local screen = G.Screen(screenW, screenH)
    local area = G.Area(spec, screenW, screenH)
    local narrow = spec.narrow ~= nil and area.w < spec.narrow
    local canvasScreen = refs and refs.screen or screen
    local canvasArea = refs and refs.area or area
    local rects, notes, diags = {}, {}, {}
    local margin = spec.margin or 0
    local function Diag(d) diags[#diags + 1] = d end
    for _, id in ipairs(order) do
        local c = comps[id]
        local n = {}
        local w, h, sn = Size(c, f, narrow, area)
        for _, s in ipairs(sn) do n[#n + 1] = s end
        local a = (narrow and c.narrow and c.narrow.anchor) or c.anchor
        local ox, oy
        if refs then ox, oy = Offset(a, id, refs, canvasArea, canvasScreen)
        else ox, oy = a.x or 0, a.y or 0 end   -- the canvas pass of a refless component: its explicit offset
        local tx, ty = G.Point(Target(a.to, area, screen, rects), a.rel)
        local rect
        if refs == nil and c.ref then
            rect = G.Rect(c.ref.x, c.ref.y, c.ref.w or 0, c.ref.h or 0)   -- the canvas pass: where the author put it
        else
            rect = Place(a.point, tx + ox, ty + oy, w, h)
        end
        local room = (narrow and c.narrow and c.narrow.room) or c.room
        if room and refs then
            local floored
            rect, floored = Room(rect, c, room, rects[room.of], a.point)
            if floored then n[#n + 1] = "room-min" end
            if rect.w < w or rect.h < h then n[#n + 1] = "room" end
        end
        if c.above and refs then
            local o = rects[c.above.of]
            local ox2 = o and Overlap(rect, o) or 0
            local want = o and (o.t + (c.above.gap or 0)) or nil
            if want and ox2 > 0 and rect.b < want then
                rect = G.Rect(rect.x, rect.y + (want - rect.b), rect.w, rect.h)
                n[#n + 1] = "above"
            end
        end
        if refs and rect.w > 0 and rect.h > 0 then
            local moved, fits
            rect, moved, fits = Clamp(rect, screen, margin)
            if moved > G.TOLERANCE / 2 then n[#n + 1] = "clamped"; Diag({ code = "clamped", id = id, by = moved }) end
            if not fits then Diag({ code = "offscreen", id = id }) end
        end
        if refs then
            for _, s in ipairs(n) do
                if s == "min-w" or s == "min-h" or s == "room-min" then Diag({ code = "minimum", id = id, rule = s }) break end
            end
        end
        rects[id], notes[id] = rect, n
    end
    return { screen = screen, area = area, narrow = narrow, rects = rects, notes = notes, diags = diags }
end

-- opts: { density = id, variant = id }. screen: { w, h } in UIParent units.
-- Returns result | nil, why. result = { variant, screen, area, density, factor, narrow, order, components = { [id] = { id, label,
--   managed, rect, ref (the same component on the canvas), dx, dy (centre moved by), notes, applied } },
--   diagnostics = { { code, id, other, by, w, h } } (sorted), fits }
function G.Resolve(spec, screen, opts)
    opts = opts or {}
    local P = LY.Problems()
    local order = G.Check(spec, P)
    if not order or P.n > 0 then return nil, "invalid", P end
    spec = G.Spec(spec, opts.variant)      -- this variant's whole rules (the shared ones if it has none of its own)
    local ids = {}
    for id in pairs(spec.components) do ids[id] = true end
    order = Order(spec.components, ids)
    if type(screen) ~= "table" or not (Finite(screen.w) and Finite(screen.h) and screen.w >= 200 and screen.h >= 200) then
        return nil, "screen"
    end
    local density = opts.density or "standard"
    local f = spec.densities[density]
    if not f then return nil, "density" end
    -- The canvas pass gives every component its reference rect (refless ones from their explicit rules).
    local cv = spec.canvas
    local canvas = One(spec, order, cv.w, cv.h, 1, nil)
    local refs = { own = canvas.rects, rects = canvas.rects, screen = canvas.screen, area = canvas.area }
    local live = One(spec, order, screen.w, screen.h, f, refs)
    local out = { variant = opts.variant, screen = live.screen, area = live.area, density = density, factor = f, narrow = live.narrow,
        order = order, components = {}, diagnostics = live.diags, canvas = canvas.screen }
    local managed = {}
    for _, id in ipairs(order) do
        local c, rect, ref = spec.components[id], live.rects[id], canvas.rects[id]
        out.components[id] = { id = id, label = c.label, managed = c.managed == true, rect = rect, ref = ref,
            dx = rect.x - ref.x, dy = rect.y - ref.y, notes = live.notes[id], applied = c.applied }
        if c.managed and rect.w > 0 and rect.h > 0 then managed[#managed + 1] = id end
    end
    for i = 1, #managed do
        for k = i + 1, #managed do
            local a, b = live.rects[managed[i]], live.rects[managed[k]]
            local ow, oh = Overlap(a, b)
            if ow > G.TOLERANCE and oh > G.TOLERANCE then
                out.diagnostics[#out.diagnostics + 1] = { code = "overlap", id = managed[i], other = managed[k], w = ow, h = oh }
            end
        end
    end
    table.sort(out.diagnostics, function(a, b)
        if a.code ~= b.code then return a.code < b.code end
        if a.id ~= b.id then return a.id < b.id end
        return (a.other or "") < (b.other or "")
    end)
    out.fits = true
    for _, d in ipairs(out.diagnostics) do
        if d.code == "overlap" or d.code == "offscreen" then out.fits = false end
    end
    return out
end

---------------------------------------------------------------------------
-- Converting a resolved place to how an addon stores it (adapters call these)
---------------------------------------------------------------------------
-- Rounded to 1/100 of a unit, so the same input always stores the same number.
function G.Round(n) return math.floor(n * 100 + 0.5) / 100 end

-- SetPoint(point, UIParent, rel, x, y): the x, y that puts rect's point there.
function G.Stored(rect, point, rel, screen)
    local px, py = G.Point(rect, point)
    local sx, sy = G.Point(screen, rel)
    return G.Round(px - sx), G.Round(py - sy)
end

-- A position stored for something whose size TwichUI doesn't know, moved with its component:
-- record = { point, rel, x, y } on the canvas; d = { dx, dy } (how far the component's point moved).
function G.Follow(record, d, canvas, screen)
    local cx, cy = G.Point(canvas, record.rel)
    local sx, sy = G.Point(screen, record.rel)
    local px, py = cx + record.x + d.dx, cy + record.y + d.dy
    return G.Round(px - sx), G.Round(py - sy)
end

-- How far one of a component's points moved between the canvas and this screen.
function G.Moved(comp, point)
    local ax, ay = G.Point(comp.ref, point or "CENTER")
    local bx, by = G.Point(comp.rect, point or "CENTER")
    return { dx = bx - ax, dy = by - ay }
end

---------------------------------------------------------------------------
-- Reading this screen (the one game call in this file; read only)
---------------------------------------------------------------------------
-- { w, h } of UIParent in its own units (what positions are measured in), and for showing only: the physical size
-- and the effective scale. nil when UIParent can't be read.
function G.Live()
    local UI = rawget(_G, "UIParent")
    if not UI then return nil end
    local ok, w, h = pcall(function() return UI:GetWidth(), UI:GetHeight() end)
    if not ok or not (Finite(w) and Finite(h)) then return nil end
    local s = { w = w, h = h }
    local fn = rawget(_G, "GetPhysicalScreenSize")
    if fn then
        local okP, pw, ph = pcall(fn)
        if okP and Finite(pw) and Finite(ph) then s.physW, s.physH = pw, ph end
    end
    local okS, es = pcall(function() return UI:GetEffectiveScale() end)
    if okS and Finite(es) then s.scale = es end
    return s
end
