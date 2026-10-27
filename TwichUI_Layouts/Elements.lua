-- TwichUI Layouts: the pieces inside the components, placed for the preview (Phase 5, docs/layouts/wizard.md)
-- The preview shows more than the component boxes: the player and target frames, the action bars, the cast bars, the
-- party frames and TwichUI's own pieces, each where the install would put it on this screen. Pure, like the composer:
-- the same package and the same resolved screen always give the same pieces, and nothing here calls the game.
--
--   LY.Elements(pkg, variant, geo) -> list, notes
--     geo = Geometry.Resolve's result for the screen (the one the plan is built from). list = { { id, adapter, label,
--     kind, comp, rect }, ... } sorted by id; rect = { x, y, w, h, l, r, b, t } as Geometry's rects (centre offsets from
--     the middle of the screen, in UIParent units). notes = { { code, id } } for an attached position that could not be shown.
--
-- Where a piece goes is not worked out here: it is the same call the install makes (the ellesmereui adapter's `Resolved`
-- and the twichui adapter's `PlaceOne`, which `Adapt` and `Places` use to write the payload), applied to the same
-- stored record, so the preview and the install cannot disagree about a position. What is new here is only each piece's
-- SIZE, which the install never needs (EllesmereUI sizes its own frames): read from the layout's own captured data, by
-- a few plain rules (a unit frame is its frame width by its health and power heights; a bar is its buttons in rows and
-- columns), and marked as sample sizes: EllesmereUI draws them, snaps them to the pixel grid and can differ by a few
-- units. A piece whose size the data does not give is left out (listed in notes), never guessed. TwichUI's own pieces
-- (class bars, marker bar, navigation arrow, food and drink, Healer Watch) have no size TwichUI knows from outside their
-- features, so each is a small marker at its place.
--
-- Nothing is copied from EllesmereUI: the rules are arithmetic on its saved keys (read in the reference source, 9.6.8).

local R = TwichUI
local LY = R.Layouts
local EA, TA = LY.EllesmereAdapter, LY.TwichUIAdapter
local G = LY.Geometry

local MARKER = 26   -- the side of a TwichUI marker, in UIParent units

local function Num(v, max) return type(v) == "number" and v == v and v > 0 and v < (max or 6000) and v or nil end

---------------------------------------------------------------------------
-- Sizes, from a module's blob (EllesmereUI 9.6.8's saved keys). Each returns w, h | nil.
---------------------------------------------------------------------------
local function UnitFrame(unit)
    return function(blob)
        local t = blob[unit]
        if type(t) ~= "table" then return nil end
        local w, h = Num(t.frameWidth), Num(t.healthHeight)
        if not (w and h) then return nil end
        return w, h + (Num(t.powerHeight) or 0)
    end
end

local function CastBar(unit, widthKey, heightKey, shownKey)
    return function(blob)
        local t = blob[unit]
        if type(t) ~= "table" or (shownKey and t[shownKey] ~= true) then return nil end
        local w, h = Num(t[widthKey]), Num(t[heightKey])
        if not (w and h) then return nil end
        return w, h
    end
end

-- An action bar: numIcons buttons (overrideNumIcons, else numIcons, else the bar's default count) in rows (overrideNumRows,
-- else numRows, else 1), a button's width and height with the padding between. A vertical bar has its rows as columns.
local BAR_COUNT = { Bar2 = 12, Bar3 = 12, Bar4 = 12, Bar5 = 12, Bar6 = 12, Bar7 = 12, MainBar = 12, StanceBar = 10, PetBar = 10 }
local function Bar(key)
    return function(blob)
        local s = type(blob.bars) == "table" and blob.bars[key]
        if type(s) ~= "table" or s.enabled == false then return nil end
        local n = Num(s.overrideNumIcons, 40) or Num(s.numIcons, 40) or BAR_COUNT[key]
        local rows = Num(s.overrideNumRows, 40) or Num(s.numRows, 40) or 1
        local bw, bh = Num(s.buttonWidth, 200), Num(s.buttonHeight, 200)
        local pad = type(s.buttonPadding) == "number" and s.buttonPadding >= 0 and s.buttonPadding < 100 and s.buttonPadding or 2
        if not (n and bw and bh) then return nil end
        local stride = math.ceil(n / rows)
        rows = math.ceil(n / stride)
        local cols = stride
        if s.orientation == "vertical" then cols, rows = rows, stride end
        return cols * bw + (cols - 1) * pad, rows * bh + (rows - 1) * pad
    end
end

-- The party frames as one block: frameWidth by frameHeight for five members, in a column (or a row with partyHorizontal).
-- How EllesmereUI lays the members out beyond that is its own; the preview says the arrangement is a sample.
local function Party(blob)
    local w, h = Num(blob.partyFrameWidth), Num(blob.partyFrameHeight)
    if not (w and h) then return nil end
    local gap = Num(blob.defSpacing, 100) or 1
    if blob.partyHorizontal == true then return 5 * w + 4 * gap, h end
    return w, 5 * h + 4 * gap
end

-- [position id] = { kind, size(blob of the position's own module) }. Positions the install moves but that have no size here are not drawn.
local SIZES = {
    ["uf-player"] = { "unit", UnitFrame("player") },
    ["uf-target"] = { "unit", UnitFrame("target") },
    ["uf-targettarget"] = { "unit", UnitFrame("targettarget") },
    ["uf-pet"] = { "unit", UnitFrame("pet") },
    ["uf-focus"] = { "unit", UnitFrame("focus") },
    ["uf-target-cast"] = { "cast", CastBar("target", "castbarWidth", "castbarHeight") },
    ["uf-focus-cast"] = { "cast", CastBar("focus", "castbarWidth", "castbarHeight") },
    ["uf-player-cast"] = { "cast", CastBar("player", "playerCastbarWidth", "playerCastbarHeight", "showPlayerCastbar") },
    ["rb-cast"] = { "cast", function(blob)
        local t = blob.castBar
        if type(t) ~= "table" or t.enabled == false then return nil end
        local w, h = Num(t.width), Num(t.height)
        if w and h then return w, h end
    end },
    ["bar-main"] = { "bar", Bar("MainBar") },
    ["bar-2"] = { "bar", Bar("Bar2") },
    ["bar-3"] = { "bar", Bar("Bar3") },
    ["bar-4"] = { "bar", Bar("Bar4") },
    ["bar-5"] = { "bar", Bar("Bar5") },
    ["bar-6"] = { "bar", Bar("Bar6") },
    ["bar-7"] = { "bar", Bar("Bar7") },
    ["bar-stance"] = { "bar", Bar("StanceBar") },
    ["bar-pet"] = { "bar", Bar("PetBar") },
    ["party-frames"] = { "party", Party },
}
local MARKERS = { ["class-bars"] = true, ["marker-bar"] = true, ["nav-arrow"] = true, ["food-drink"] = true, ["healer-watch"] = true }

---------------------------------------------------------------------------
-- The layers, read by reference (no validation and no copy: LY.Plan does those; this runs on every redraw)
---------------------------------------------------------------------------
local function Pick(pkg, variant, adapter, getter)
    local layers = type(pkg) == "table" and pkg.layers
    if type(layers) ~= "table" then return nil end
    local function From(layer)
        local f = type(layer) == "table" and layer[adapter]
        if type(f) == "table" then return getter(f) end
    end
    local x = From(type(layers.variants) == "table" and layers.variants[variant])
    if x == nil then x = From(layers.base) end
    if x == LY.REMOVE then return nil end
    return x
end

local function Module(pkg, variant, m)
    local x = Pick(pkg, variant, "ellesmereui", function(f) return type(f.modules) == "table" and f.modules[m] or nil end)
    return type(x) == "table" and x or nil
end

local function PlaceValue(pkg, variant, id)
    local x = Pick(pkg, variant, "twichui", function(f) return type(f.places) == "table" and f.places[id] or nil end)
    return type(x) == "table" and x or nil
end

local function RectAt(geo, point, rel, x, y, w, h)
    local sx, sy = G.Point(geo.screen, rel)
    return G.Place(point, sx + x, sy + y, w, h)
end

function LY.Elements(pkg, variant, geo)
    local list, notes = {}, {}
    if not (type(geo) == "table" and geo.components and geo.screen) then return list, notes end
    local attach = G.Attach(pkg.geometry, variant) or {}
    local eui = attach.ellesmereui or {}
    for _, id in ipairs(LY.SortedKeys(eui)) do
        local size = SIZES[id]
        local p = EA.POSITIONS[id]
        local compId, pt = tostring(eui[id]):match("^([%w%-]+):?(%u*)$")
        local comp = compId and geo.components[compId]
        if size and p and comp then
            local blob = Module(pkg, variant, p.module)
            local rec = blob and EA.Read(blob, p.path)
            local w, h
            if blob and EA.PosOk(rec) and not (p.check and EA.Read(blob, p.check.path) ~= p.check.value) then
                w, h = size[2](blob)
                if w then
                    local new = EA.Resolved(p, rec, comp, pt, geo)
                    list[#list + 1] = { id = id, adapter = "ellesmereui", label = p.label, kind = size[1], comp = compId,
                        rect = RectAt(geo, new.point, new.relPoint, new.x, new.y, w, h) }
                else
                    notes[#notes + 1] = { code = "no-size", id = id }
                end
            else
                notes[#notes + 1] = { code = "not-stored", id = id }
            end
        end
    end
    for _, id in ipairs(LY.SortedKeys(attach.twichui or {})) do
        local p = TA.PLACES[id]
        local compId, pt = tostring(attach.twichui[id]):match("^([%w%-]+):?(%u*)$")
        local comp = compId and geo.components[compId]
        local v = MARKERS[id] and p and comp and PlaceValue(pkg, variant, id)
        if v and type(v.x) == "number" and type(v.y) == "number" then
            local new, point = TA.PlaceOne(p, v, comp, pt, geo)
            local sx, sy = G.Point(geo.screen, point)
            list[#list + 1] = { id = id, adapter = "twichui", label = p.label, kind = "marker", comp = compId,
                rect = G.Rect(sx + new.x, sy + new.y, MARKER, MARKER) }
        elseif MARKERS[id] and p and comp then
            notes[#notes + 1] = { code = "not-stored", id = id }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list, notes
end
