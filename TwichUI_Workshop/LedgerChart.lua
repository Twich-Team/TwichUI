-- TwichUI Workshop: the Gold Flow chart (UI.GoldFlowChart)
-- Daily gold in (muted sage columns above the zero line), gold out (restrained rust columns below it) and the net change (an antique-gold
-- line with round markers), over the window the page chose. It belongs to the same chart family as the advanced Market chart
-- (auction/AdvancedChart.lua) and shares its presentation pieces through ChartKit.lua: the two-stroke line anchored to marker regions with
-- a portable raster fallback, the espresso inspection card, the pointer with a six-pixel drag threshold and right-click reset. It does not
-- share its price-line data model: this one is made of columns and a net line.
--
--   * The geometry is pure (C.Columns, C.Geometry: days in, rectangles and points out) and tested without frames.
--   * The frame pools its regions, draws only when its data, view or size changed, and has an OnUpdate only while the pointer is over it
--     or a drag is open (ChartKit.Pointer).
--   * Drag to zoom selects columns; right-click resets to the chosen 7D / 30D / 90D window, which always stays authoritative: a change of
--     window, character scope or source clears an old zoom. A window too long for its width is shown in 7-, 14- or 30-day columns
--     built by adding the exact recorded copper of their days; such a column says so, and a column with unrecorded days is marked as
--     partly recorded and is never joined into the net line.
--   * A day with no record is "outside recorded coverage": drawn as a faint empty column and named so on inspection, never as zero. A day
--     the recorder covered with no gold moving is a thin tick on the zero line ("recorded, nothing moved").

local R = TwichUI
local W = R.Workshop
local UI = W.UI
local LQ = W.LedgerQuery
local C = { MIN_BAR = 2, MIN_SLOT = 11 }
W.LedgerChart = C

local GREEN = { 0.32, 0.47, 0.31 }
local RED = { 0.58, 0.27, 0.22 }
C.GREEN, C.RED = GREEN, RED
local charts = setmetatable({}, { __mode = "k" })
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("ledger.chartPool", { label = "Gold Ledger chart pooled regions", unit = "count", kind = "pool", group = "workshop",
        read = function() local n = 0 for chart in pairs(charts) do n = n + chart:RegionCount() end return n end })
end

---------------------------------------------------------------------------
-- Pure geometry
---------------------------------------------------------------------------
-- A tidy step (1, 2 or 5 times a power of ten, in copper) for about `parts` divisions of `span`.
function C.NiceStep(span, parts)
    if not (span and span > 0) then return 10000 end
    local raw = span / (parts or 4)
    local pow = 10 ^ math.floor(math.log(raw) / math.log(10))
    local m = raw / pow
    local nice = m <= 1 and 1 or m <= 2 and 2 or m <= 5 and 5 or 10
    return math.max(1, nice * pow)
end

-- Compact axis text: "300g", "-50g", "12k", "40s", "0g". (The page draws the coin artwork version, UI.Coins.Axis; this is the plain form.)
function C.AxisText(v)
    if v == 0 then return "0g" end
    local neg = v < 0
    local n = neg and -v or v
    local text
    if n >= 100000000 then text = ("%dk"):format(math.floor(n / 10000 / 1000 + 0.5))
    elseif n >= 10000 then text = ("%dg"):format(math.floor(n / 10000 + 0.5))
    elseif n >= 100 then text = ("%ds"):format(math.floor(n / 100 + 0.5))
    else text = n .. "c" end
    return neg and ("-" .. text) or text
end

-- The columns of a view: days v1..v2 of `days` (LedgerQuery.Summary(...).days), added into columns of k days when they would be narrower
-- than C.MIN_SLOT pixels. Exact recorded copper only: a day outside coverage adds nothing and is not a zero.
--   { day, last (first and last day number), from, to (indexes into days), span, recorded (days with a record), inn, out, net, n,
--     covered (any day recorded), partial (some but not all) }
function C.Columns(days, v1, v2, pw)
    v1, v2 = v1 or 1, v2 or #days
    local n = v2 - v1 + 1
    if n <= 0 then return {}, 1 end
    local maxCols = math.max(4, math.floor((pw or 0) / C.MIN_SLOT))
    local k = 1
    for _, candidate in ipairs({ 1, 7, 14, 30 }) do
        k = candidate
        if math.ceil(n / candidate) <= maxCols then break end
    end
    local cols = {}
    for start = v1, v2, k do
        local stop = math.min(v2, start + k - 1)
        local col = { day = days[start].day, last = days[stop].day, from = start, to = stop, span = stop - start + 1, recorded = 0, inn = 0, out = 0, n = 0 }
        for i = start, stop do
            local d = days[i]
            if d.covered then
                col.recorded = col.recorded + 1
                col.inn, col.out, col.n = col.inn + d.inn, col.out + d.out, col.n + d.n
            end
        end
        col.net = col.inn - col.out
        col.covered = col.recorded > 0
        col.partial = col.recorded > 0 and col.recorded < col.span
        cols[#cols + 1] = col
    end
    return cols, k
end

-- "Thursday, November 19" (the day number is a local calendar day, so it is formatted without a zone shift)
function C.DayLong(day)
    return (date("!%A, %B %d", day * 86400):gsub(" 0(%d)$", " %1"))
end

-- The first and last index of `days` inside the absolute day numbers d1..d2 (nil when the view lies outside them)
function C.ViewRange(days, d1, d2)
    local v1, v2
    for i, d in ipairs(days) do
        if d.day >= d1 and not v1 then v1 = i end
        if d.day <= d2 then v2 = i end
    end
    if not (v1 and v2) or v2 < v1 then return nil end
    return v1, v2
end

-- days: LedgerQuery.Summary(...).days; show: { inn, out, net } booleans; pw, ph: the plot's size.
function C.Geometry(days, pw, ph, show, opts)
    show = show or { inn = true, out = true, net = true }
    opts = opts or {}
    local n = #days
    local g = { bars = {}, uncovered = {}, ticks = {}, points = {}, segments = {}, grid = {}, xlabels = {}, n = n, pw = pw, ph = ph }
    if n == 0 or pw <= 0 or ph <= 0 then g.scale = { top = 0, bottom = 0, step = 0 } return g end
    local top, bottom = 0, 0
    for _, d in ipairs(days) do
        if d.covered then
            if show.inn then top = math.max(top, d.inn) end
            if show.out then bottom = math.max(bottom, d.out) end
            if show.net then top, bottom = math.max(top, d.net), math.max(bottom, -d.net) end
        end
    end
    local step = C.NiceStep(top + bottom, 4)
    local yTop, yBottom = math.ceil(top / step) * step, math.ceil(bottom / step) * step
    if yTop + yBottom == 0 then yTop = step end   -- nothing to draw: a single band above the zero line
    local range = yTop + yBottom
    local function Y(v) return (v + yBottom) / range * ph end
    g.scale = { top = yTop, bottom = yBottom, step = step, range = range }
    g.zeroY = Y(0)
    for v = -yBottom, yTop, step do g.grid[#g.grid + 1] = { value = v, y = Y(v) } end
    local slot = pw / n
    local bw = math.max(3, math.min(opts.maxBar or 40, math.floor(slot * (opts.fill or 0.62))))
    g.slot, g.barW = slot, bw
    local prev
    for i, d in ipairs(days) do
        local x0, cx = (i - 1) * slot + (slot - bw) / 2, (i - 0.5) * slot
        if not d.covered then
            g.uncovered[#g.uncovered + 1] = { x = (i - 1) * slot, w = slot, index = i }
            prev = nil
        else
            if show.inn and d.inn > 0 then
                g.bars[#g.bars + 1] = { x = x0, y = g.zeroY, w = bw, h = math.max(C.MIN_BAR, Y(d.inn) - g.zeroY), kind = "in", index = i }
            end
            if show.out and d.out > 0 then
                local h = math.max(C.MIN_BAR, g.zeroY - Y(-d.out))
                g.bars[#g.bars + 1] = { x = x0, y = g.zeroY - h, w = bw, h = h, kind = "out", index = i }
            end
            if d.inn == 0 and d.out == 0 then g.ticks[#g.ticks + 1] = { x = x0, y = g.zeroY - 0.5, w = bw, h = 1, index = i } end
            if show.net then
                local p = { x = cx, y = Y(d.net), index = i, partial = d.partial }
                g.points[#g.points + 1] = p
                if prev and prev.index == i - 1 and not d.partial and not prev.partial then g.segments[#g.segments + 1] = { a = prev, b = p } end
                prev = p
            else
                prev = nil
            end
        end
    end
    local every = opts.labelEvery or (n <= 10 and 1 or (n <= 31 and 5 or 15))
    for i, d in ipairs(days) do
        if (n - i) % every == 0 then g.xlabels[#g.xlabels + 1] = { x = (i - 0.5) * slot, text = LQ.DayShort(d.day), index = i } end
    end
    return g
end

-- The inspection lines of one day: { title, { text, tone } ... }. The words of a day outside coverage never read as zero.
function C.TipLines(d)
    local lines = { LQ.Day(d.day) }
    if not d.covered then
        lines[#lines + 1] = { "Not recorded", "stone" }
        lines[#lines + 1] = { "The ledger was not recording on this day. Gold that moved while it was not recording is not counted.", "textDim" }
        return lines
    end
    if d.n == 0 then lines[#lines + 1] = { "Recorded: no gold moved", "textDim" } end
    lines[#lines + 1] = { "Gold in: " .. LQ.Money(d.inn, true), d.inn > 0 and "sage" or "textDim" }
    lines[#lines + 1] = { "Gold out: " .. (d.out > 0 and LQ.Money(-d.out) or LQ.Money(0)), d.out > 0 and "ember" or "textDim" }
    lines[#lines + 1] = { "Net change: " .. LQ.Money(d.net, true), d.net > 0 and "sage" or (d.net < 0 and "ember" or "text") }
    if d.n > 0 then lines[#lines + 1] = { ("%d recorded %s"):format(d.n, d.n == 1 and "change" or "changes"), "stone" } end
    return lines
end


---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------
local MARKER = "Interface\\AddOns\\TwichUI_Workshop\\media\\chart-marker"
local function Round(v) return math.floor(v + 0.5) end
local function Lighten(c, f) return { c[1] + (1 - c[1]) * f, c[2] + (1 - c[2]) * f, c[3] + (1 - c[3]) * f } end

-- opts.expanded: the large view (more room, larger type, the card sits inside the plot away from the pointer)
function UI.GoldFlowChart(parent, w, h, opts)
    opts = opts or {}
    local K, Co, Kit = UI.K, UI.Coins, W.ChartKit
    local big = opts.expanded == true
    local M = { left = big and 84 or 62, right = 14, top = big and 24 or 14, xrow = big and 26 or 18, legend = big and 30 or 24 }
    local AX = big and 12 or 10
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(w, h)
    charts[c] = true
    c.big = big
    c.show = { inn = true, out = true, net = true }
    c.pool = { body = {}, shade = {}, cap = {}, wash = {}, tick = {}, marker = {}, guide = {}, xlabel = {} }
    -- the plotting well: a dark recessed face with the axis labels inside it
    c.well = CreateFrame("Frame", nil, c)
    c.well:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
    c.well:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, M.legend)
    UI.Panel(c.well, "canvas")
    c.plot = CreateFrame("Frame", nil, c.well)
    c.plot:SetPoint("TOPLEFT", c.well, "TOPLEFT", M.left, -M.top)
    c.plot:SetPoint("BOTTOMRIGHT", c.well, "BOTTOMRIGHT", -M.right, M.xrow)
    local plot = c.plot
    local function Solid(color, alpha, sub, layer)
        local t = UI.L.Solid(plot, layer or "ARTWORK", color, alpha)
        if t.SetDrawLayer then t:SetDrawLayer(layer or "ARTWORK", sub or 0) end
        return t
    end
    local function Place(t, x, y, tw, th)
        t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x, y); t:SetSize(tw, th); t:Show()
    end
    local function Pooled(pool, make, i)
        local t = pool[i]
        if not t then t = make(); pool[i] = t end
        return t
    end
    local function HideFrom(pool, from) for i = from, #pool do pool[i]:Hide() end end

    -- a faint warm sheen from the top, so the well is leather rather than a flat fill
    c.sheen = plot:CreateTexture(nil, "BACKGROUND")
    c.sheen:SetAllPoints(plot)
    UI.L.Fade(c.sheen, K.bronzeLo, 0.12, 0.0)
    c.zero = Solid(K.bronzeHi, 0.62, 1)
    c.highlight = Solid(K.bronzeText, 0.11, 0, "BACKGROUND")
    c.cross = Solid(K.textDim, 0.55, 6, "OVERLAY")
    c.selection = Solid(K.bronzeText, 0.14, 1, "BACKGROUND")
    c.selEdgeA, c.selEdgeB = Solid(K.bronzeText, 0.6, 1, "BACKGROUND"), Solid(K.bronzeText, 0.6, 1, "BACKGROUND")
    c.halo = Solid(K.bronzeLo, 0.2, 7, "OVERLAY"); c.halo:SetTexture(MARKER); c.halo:SetVertexColor(K.bronzeText[1], K.bronzeText[2], K.bronzeText[3], 0.22)
    c.pick = Solid(K.bronzeText, 1, 8, "OVERLAY"); c.pick:SetTexture(MARKER); c.pick:SetVertexColor(K.bronzeText[1], K.bronzeText[2], K.bronzeText[3], 1)
    for _, t in ipairs({ c.highlight, c.cross, c.selection, c.selEdgeA, c.selEdgeB, c.halo, c.pick }) do t:Hide() end
    c.strokes = Kit.Strokes(plot, function(color, alpha, sub) return Solid(color, alpha, sub) end)

    c.msg = UI.Text(c.well, big and 15 or 13, K.textDim)
    c.msg:SetPoint("CENTER", plot, "CENTER")
    c.msg:SetWidth(math.max(120, w - 120))
    c.msg:SetJustifyH("CENTER")
    c.msg:SetWordWrap(true)
    c.hint = UI.Text(c.well, 10, K.stone)
    c.hint:SetPoint("TOPRIGHT", c.well, "TOPRIGHT", -M.right, -4)
    c.hint:SetJustifyH("RIGHT")

    ---------------------------------------------------------------------------
    -- The legend: three toggles with their totals in the visible interval
    ---------------------------------------------------------------------------
    c.legendButtons = {}
    local defs = { { "inn", "Gold in", GREEN }, { "out", "Gold out", RED }, { "net", "Net change", K.bronzeText } }
    for i, def in ipairs(defs) do
        local b = CreateFrame("Button", nil, c)
        b:SetHeight(M.legend - 2)
        b.swatch = UI.L.Solid(b, "ARTWORK", def[3], 0.9)
        b.swatch:SetSize(10, 10)
        b.swatch:SetPoint("LEFT", 4, 0)
        if def[1] == "net" then   -- the net line is drawn as a line with a round marker
            b.swatch:SetSize(14, 2)
            b.dot = b:CreateTexture(nil, "OVERLAY")
            b.dot:SetTexture(MARKER); b.dot:SetVertexColor(def[3][1], def[3][2], def[3][3], 1)
            b.dot:SetSize(7, 7); b.dot:SetPoint("CENTER", b.swatch, "CENTER", 0, 0)
        end
        b.name = UI.Text(b, big and 13 or 12, K.textDim)
        b.name:SetPoint("LEFT", b.swatch, "RIGHT", 6, 0)
        b.name:SetText(def[2])
        b.value = UI.Text(b, big and 13 or 12, K.text)
        b.value:SetPoint("LEFT", b.name, "RIGHT", 6, 0)
        b.key = def[1]
        b:SetScript("OnClick", function(self) c:SetShow(self.key, not c.show[self.key]) end)
        UI.TipFn(b, def[2], function(self)
            local exact = self.value.exact
            return (c.show[self.key] and "Click to hide this from the chart." or "Click to show this on the chart.")
                .. (exact and ("\n\nExact: " .. Co.Text(exact, { signed = self.key ~= "out", height = 12 })) or "")
        end)
        c.legendButtons[def[1]] = b
    end
    local function LayoutLegend()
        local total = math.max(60, (c:GetWidth() or w))
        local each = math.floor(total / 3)
        for i, def in ipairs(defs) do
            local b = c.legendButtons[def[1]]
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", (i - 1) * each, 0)
            b:SetWidth(each - 4)
            b.room = each - 4 - 4 - 10 - 6 - (b.name:GetStringWidth() or 60) - 6 - 4
        end
    end

    local function PaintLegend()
        local cols = c.cols or {}
        local inn, out = 0, 0
        for _, col in ipairs(cols) do inn, out = inn + col.inn, out + col.out end
        local sums = { inn = inn, out = -out, net = inn - out }
        for key, b in pairs(c.legendButtons) do
            local on = c.show[key]
            if c.model and c.model.recording then
                Co.Fit(b.value, sums[key], { size = big and 13 or 12, min = 10, width = math.max(30, b.room or 90), signed = key ~= "out" })
            else
                b.value.exact = nil; b.value:SetText("")
            end
            UI.Paint(b.name, on and K.text or K.stone)
            UI.Paint(b.value, on and (key == "inn" and K.sage or key == "out" and K.ember or K.bronzeText) or K.stone)
            b.swatch:SetAlpha(on and 0.9 or 0.25)
            if b.dot then b.dot:SetAlpha(on and 1 or 0.25) end
        end
    end

    ---------------------------------------------------------------------------
    -- The inspection card (made on first use; one for the chart, never one per hover)
    ---------------------------------------------------------------------------
    local card
    local CARD_W = big and 340 or 304
    local function EnsureCard()
        if card then return card end
        card = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        UI.Panel(card, "espresso")
        card:SetSize(CARD_W, 128)
        card:SetFrameStrata("TOOLTIP")
        card:SetClampedToScreen(true)
        card:EnableMouse(false)
        card:Hide()
        card.title = UI.Text(card, big and 13 or 12, K.bronzeText, "strong")
        card.title:SetPoint("TOPLEFT", 12, -9)
        card.title:SetWidth(CARD_W - 24)
        card.rows = {}
        for i, def in ipairs({ { "Gold In" }, { "Gold Out" }, { "Net Change" } }) do
            local label = UI.Text(card, big and 13 or 12, K.textDim)
            label:SetPoint("TOPLEFT", 12, -(30 + (i - 1) * 21))
            label:SetText(def[1])
            local value = UI.Text(card, big and 14 or 13, K.text, "strong")
            value:SetPoint("TOPRIGHT", -12, -(29 + (i - 1) * 21))
            value:SetWidth(CARD_W - 100)
            value:SetJustifyH("RIGHT")
            card.rows[i] = { label = label, value = value }
        end
        local rule = UI.Rule(card, 0.4)
        rule:SetPoint("TOPLEFT", 10, -94); rule:SetPoint("TOPRIGHT", -10, -94)
        card.rule = rule
        card.foot = UI.Text(card, 11, K.stone)
        card.foot:SetPoint("TOPLEFT", 12, -100)
        card.foot:SetWidth(CARD_W - 24)
        card.foot:SetWordWrap(true)
        card.note = UI.Text(card, 12, K.textDim)
        card.note:SetPoint("TOPLEFT", 12, -32)
        card.note:SetWidth(CARD_W - 24)
        card.note:SetWordWrap(true)
        card.note:SetJustifyV("TOP")
        return card
    end

    local function CardTitle(col)
        if col.span == 1 then return C.DayLong(col.day) end
        return ("%s \226\128\147 %s \194\183 %d days"):format(LQ.DayShort(col.day), LQ.DayShort(col.last), col.span)
    end

    local function FillCard(col)
        local t = EnsureCard()
        t.title:SetText(CardTitle(col))
        local hintLine = "Drag to zoom \194\183 Right-click to reset"
        if not col.covered then
            for _, r in ipairs(t.rows) do r.label:Hide(); r.value:Hide() end
            t.note:Show(); t.rule:Show()
            t.note:SetText(col.span == 1 and "Not recorded. The ledger was not recording on this day; gold that moved while it was not recording is not counted, and it is not shown as zero."
                or "Not recorded. The ledger was not recording on any of these days; this is not zero.")
            UI.Paint(t.note, K.textDim)
            t.rule:ClearAllPoints(); t.rule:SetPoint("TOPLEFT", 10, -86); t.rule:SetPoint("TOPRIGHT", -10, -86)
            t.foot:ClearAllPoints(); t.foot:SetPoint("TOPLEFT", 12, -92)
            t.foot:SetText(hintLine)
            t:SetHeight(112)
            return
        end
        t.note:Hide()
        local amounts = { col.inn, -col.out, col.net }
        local tones = { col.inn > 0 and K.sage or K.textDim, col.out > 0 and K.ember or K.textDim, col.net > 0 and K.sage or (col.net < 0 and K.ember or K.text) }
        for i, r in ipairs(t.rows) do
            r.label:Show(); r.value:Show()
            Co.Fit(r.value, amounts[i], { size = big and 14 or 13, min = 11, width = CARD_W - 100, signed = i ~= 2, role = "strong" })
            UI.Paint(r.value, tones[i])
        end
        local foot
        if col.n == 0 then foot = "Recorded: no gold moved"
        else foot = ("%d recorded %s"):format(col.n, col.n == 1 and "change" or "changes") end
        if col.span > 1 then
            foot = foot .. (col.partial and (" \194\183 %d of %d days recorded"):format(col.recorded, col.span) or (" \194\183 %d days"):format(col.span))
        end
        t.rule:ClearAllPoints(); t.rule:SetPoint("TOPLEFT", 10, -94); t.rule:SetPoint("TOPRIGHT", -10, -94); t.rule:Show()
        t.foot:ClearAllPoints(); t.foot:SetPoint("TOPLEFT", 12, -100)
        t.foot:SetText(foot .. "\n" .. hintLine)
        t:SetHeight(big and 134 or 132)
        if col.partial then UI.Paint(t.foot, K.bronzeText) else UI.Paint(t.foot, K.stone) end
    end

    ---------------------------------------------------------------------------
    -- Inspection
    ---------------------------------------------------------------------------
    local function HideMarks()
        c.highlight:Hide(); c.cross:Hide(); c.halo:Hide(); c.pick:Hide()
        if card then card:Hide() end
    end
    function c:ClearInspection()
        HideMarks()
        self.inspected = nil
    end

    -- Shows column i: the interval, the crosshair, the net marker and the card.
    function c:InspectIndex(i)
        local g, col = self.geometry, self.cols and self.cols[i]
        if not (g and col) then return end
        if self.inspected == i and card and card:IsShown() then return end
        self.inspected = i
        local cx = (i - 0.5) * g.slot
        Place(self.highlight, (i - 1) * g.slot, 0, g.slot, g.ph)
        Place(self.cross, Round(cx), 0, 1, g.ph)
        self.halo:Hide(); self.pick:Hide()
        local p
        for _, pt in ipairs(g.points) do if pt.index == i then p = pt break end end
        if p then
            self.halo:ClearAllPoints(); self.halo:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.y); self.halo:SetSize(big and 24 or 20, big and 24 or 20); self.halo:Show()
            self.pick:ClearAllPoints(); self.pick:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.y); self.pick:SetSize(big and 11 or 9, big and 11 or 9); self.pick:Show()
        end
        FillCard(col)
        Kit.Dock(card, self, { plot = plot, side = i <= #self.cols / 2 and "right" or "left", inside = big })
        card:Show()
    end

    function c:CursorX()
        local scale = plot:GetEffectiveScale() or 1
        return GetCursorPosition() / scale - (plot:GetLeft() or 0)
    end
    local function IndexAt(x)
        local g = c.geometry
        if not (g and g.slot and g.slot > 0 and c.cols) then return nil end
        return math.max(1, math.min(#c.cols, math.floor(x / g.slot) + 1))
    end

    -- the zoom: absolute day numbers, so a refresh that moves the window by a day keeps what was chosen
    function c:IsZoomed() return self.view ~= nil end
    function c:ResetZoom()
        if not self.view then return end
        self.view = nil
        self.drawn = nil
        if self.onView then self.onView(nil) end
        self:Render()
    end
    function c:Zoom(d1, d2)
        if not self.model or not d1 or not d2 then return end
        if d2 < d1 then d1, d2 = d2, d1 end
        local days = self.model.days
        if #days == 0 then return end
        local first, last = days[1].day, days[#days].day
        d1, d2 = math.max(first, d1), math.min(last, d2)
        if d2 <= d1 then   -- never a single day: the next one (or the one before, at the end)
            if d2 < last then d2 = d1 + 1 elseif d1 > first then d1 = d2 - 1 end
        end
        if d1 <= first and d2 >= last then return self:ResetZoom() end
        self.view = { d1, d2 }
        self.drawn = nil
        if self.onView then self.onView(self.view) end
        self:Render()
    end

    c.hit = CreateFrame("Button", nil, plot)
    c.hit:SetAllPoints(plot)
    c.hit:SetFrameLevel((plot:GetFrameLevel() or 1) + 12)
    c.hit:EnableMouse(true)
    c.hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.pointer = Kit.Pointer(c.hit, {
        ready = function() return c.model ~= nil and c.geometry ~= nil and c.cols ~= nil and #c.cols > 0 and not c.empty end,
        x = function() return c:CursorX() end,
        width = function() return c.geometry and c.geometry.pw or 1 end,
        hover = function(x) local i = IndexAt(x); if i then c:InspectIndex(i) end end,
        dragging = function(x0, x)
            if not x0 then c.selection:Hide(); c.selEdgeA:Hide(); c.selEdgeB:Hide(); return end
            local g = c.geometry
            local a, b = IndexAt(x0), IndexAt(x)
            if a > b then a, b = b, a end
            local left, width = (a - 1) * g.slot, (b - a + 1) * g.slot
            Place(c.selection, left, 0, width, g.ph)
            Place(c.selEdgeA, left, 0, 1, g.ph); Place(c.selEdgeB, left + width - 1, 0, 1, g.ph)
        end,
        leave = function() c:ClearInspection() end,
        commit = function(x0, x1)
            local a, b = IndexAt(x0), IndexAt(x1)
            if a > b then a, b = b, a end
            c:Zoom(c.cols[a].day, c.cols[b].last)
        end,
        reset = function() c:ResetZoom() end,
    })

    ---------------------------------------------------------------------------
    -- Drawing
    ---------------------------------------------------------------------------
    local function Draw()
        local model = c.model
        if not model then return end
        local pw, ph = plot:GetWidth() or 0, plot:GetHeight() or 0
        if pw < 40 then pw = w - M.left - M.right end
        if ph < 30 then ph = h - M.top - M.xrow - M.legend end
        pw, ph = Round(pw), Round(ph)
        local days = model.days
        local v1, v2 = 1, #days
        if c.view then
            local a, b = C.ViewRange(days, c.view[1], c.view[2])
            if a then v1, v2 = a, b else c.view = nil; if c.onView then c.onView(nil) end end
        end
        local show = c.show
        local key = table.concat({ tostring(model), v1, v2, pw, ph, show.inn and 1 or 0, show.out and 1 or 0, show.net and 1 or 0, c.strokes.mode or "-" }, ":")
        if key == c.drawn then return end
        c.drawn = key
        local cols = C.Columns(days, v1, v2, pw)
        local labelWidth = big and 78 or 58
        local every = math.max(1, math.ceil(#cols / math.max(1, math.floor(pw / labelWidth))))
        local g = C.Geometry(cols, pw, ph, show, { maxBar = big and 64 or 40, labelEvery = every })
        c.cols, c.geometry = cols, g
        c:ClearInspection()
        local empty = not model.recording or model.totals.n == 0
        if empty then g.grid, g.points, g.segments, g.zeroY = {}, {}, {}, nil end
        c.empty = empty
        c.msg:SetText(not model.recording and "Gold tracking hasn't started yet." or (empty and "No gold activity recorded in this period." or ""))
        c.hint:SetText(c.view and "Zoomed \194\183 Right-click to reset" or (big and "Drag to zoom \194\183 Right-click to reset" or ""))
        -- guides and axis labels (the zero line is its own stronger line)
        local n = 0
        for _, line in ipairs(g.grid) do
            n = n + 1
            local gl = Pooled(c.pool.guide, function()
                local fs = UI.Text(c.well, AX, K.bronzeText)
                fs:SetJustifyH("RIGHT"); fs:SetWidth(M.left - 12)
                return { line = Solid(K.bronzeLo, 0.30, 0), label = fs }
            end, n)
            if line.value == 0 then gl.line:Hide() else Place(gl.line, 0, Round(line.y), pw, 1) end
            gl.label:ClearAllPoints(); gl.label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -8, Round(line.y))
            gl.label:SetText(Co.Axis(line.value, AX))
            UI.Paint(gl.label, line.value == 0 and K.text or K.bronzeText)
            gl.label:Show()
        end
        for i = n + 1, #c.pool.guide do c.pool.guide[i].line:Hide(); c.pool.guide[i].label:Hide() end
        if g.zeroY then Place(c.zero, 0, Round(g.zeroY), pw, 1) else c.zero:Hide() end
        -- days outside coverage, recorded quiet days
        for i, u in ipairs(g.uncovered) do
            local t = Pooled(c.pool.wash, function() return Solid(K.bronzeLo, 0.07, 0, "BACKGROUND") end, i)
            Place(t, Round(u.x) + 1, 0, math.max(1, Round(u.w) - 2), ph)
        end
        HideFrom(c.pool.wash, #g.uncovered + 1)
        for i, tk in ipairs(g.ticks) do
            local t = Pooled(c.pool.tick, function() return Solid(K.bronzeText, 0.6, 3) end, i)
            Place(t, Round(tk.x), Round(tk.y + 0.5) - 1, Round(tk.w), 2)
        end
        HideFrom(c.pool.tick, #g.ticks + 1)
        -- the columns: a flat sage or rust body, a darker half toward the baseline and a lit end (three regions each; flat tones, no
        -- gradient, as the Workshop's own meters are drawn)
        for i, b in ipairs(g.bars) do
            local body = Pooled(c.pool.body, function() return Solid(GREEN, 0.92, 2) end, i)
            local shade = Pooled(c.pool.shade, function() return Solid({ 0, 0, 0 }, 0.26, 3) end, i)
            local cap = Pooled(c.pool.cap, function() return Solid(GREEN, 0.85, 4) end, i)
            local x, bw = Round(b.x), math.max(2, Round(b.w))
            local y, bh = Round(b.y), math.max(C.MIN_BAR, Round(b.h))
            Place(body, x, y, bw, bh)
            if body.kind ~= b.kind then
                body.kind = b.kind
                local col = b.kind == "in" and GREEN or RED
                body:SetColorTexture(col[1], col[2], col[3], 0.92)
                local light = Lighten(col, 0.30)
                cap:SetColorTexture(light[1], light[2], light[3], 0.9)
            end
            if bh >= 6 then
                local half = math.floor(bh * 0.4)
                Place(shade, x, b.kind == "in" and y or (y + bh - half), bw, half)
            else
                shade:Hide()
            end
            if bh >= 4 then Place(cap, x, b.kind == "in" and (y + bh - 1) or y, bw, 1) else cap:Hide() end
        end
        HideFrom(c.pool.body, #g.bars + 1); HideFrom(c.pool.shade, #g.bars + 1); HideFrom(c.pool.cap, #g.bars + 1)
        -- the net line: round markers, then two strokes anchored to them
        for i, p in ipairs(g.points) do
            local dot = Pooled(c.pool.marker, function()
                local t = Solid(K.bronzeText, 1, 6, "OVERLAY"); t:SetTexture(MARKER); return t
            end, i)
            local size = big and 8 or 7
            dot:SetVertexColor(K.bronzeText[1], K.bronzeText[2], K.bronzeText[3], p.partial and 0.55 or 1)
            dot:ClearAllPoints(); dot:SetPoint("CENTER", plot, "BOTTOMLEFT", p.x, p.y); dot:SetSize(size, size); dot:Show()
            p.dot = dot
        end
        HideFrom(c.pool.marker, #g.points + 1)
        local segs = {}
        for _, s in ipairs(g.segments) do segs[#segs + 1] = { x1 = s.a.x, y1 = s.a.y, x2 = s.b.x, y2 = s.b.y, a = s.a.dot, b = s.b.dot } end
        c.backend = c.strokes:Draw(segs, pw)
        -- day labels
        for i, xl in ipairs(g.xlabels) do
            local fs = Pooled(c.pool.xlabel, function() local t = UI.Text(c.well, AX, K.bronzeText); t:SetJustifyH("CENTER"); t:SetWidth(labelWidth + 6); return t end, i)
            fs:ClearAllPoints(); fs:SetPoint("TOP", plot, "BOTTOMLEFT", xl.x, -4); fs:SetText(xl.text); fs:Show()
        end
        HideFrom(c.pool.xlabel, #g.xlabels + 1)
        c.barCount, c.stepCount = #g.bars, c.strokes.backend == "raster" and c.strokes.used or 0
        LayoutLegend()
        PaintLegend()
    end

    function c:Render()
        if not self.model then return end
        if R.Perf and R.Perf.Call then R.Perf.Call("ledger.chartDraw", Draw) else Draw() end
    end

    function c:CardFrame() return card end   -- (the tests)
    function c:RegionCount()
        local n = 14 + self.strokes:Count()
        for _, pool in pairs(self.pool) do n = n + #pool end
        return n
    end

    -- regions in use right now (the pools keep hidden spares): textures, lines and font strings the plot is showing
    function c:VisibleRegions()
        local n = (self.strokes.used or 0)
        for _, pool in pairs(self.pool) do
            for _, t in ipairs(pool) do
                if t.IsShown then if t:IsShown() then n = n + 1 end
                else if t.line:IsShown() then n = n + 1 end; if t.label:IsShown() then n = n + 1 end end
            end
        end
        return n
    end

    function c:Clear()
        self.pointer:Cancel()
        self:ClearInspection()
        for _, pool in pairs(self.pool) do
            for _, t in ipairs(pool) do if t.Hide then t:Hide() else t.line:Hide(); t.label:Hide() end end
        end
        self.strokes:Hide()
        self.zero:Hide(); self.selection:Hide(); self.selEdgeA:Hide(); self.selEdgeB:Hide()
        self.msg:SetText(""); self.hint:SetText("")
        self.geometry, self.cols, self.drawn = nil, nil, nil
    end

    -- model: LedgerQuery.Summary(...) or nil
    function c:Set(model)
        local ctx = model and (model.filter.scope .. "|" .. tostring(model.filter.source) .. "|" .. model.filter.days) or nil
        if ctx ~= self.context then   -- another window, scope or source: an old zoom and any open input no longer apply
            if self.view and self.onView then self.onView(nil) end
            self.view = nil
            self.pointer:Cancel()
        end
        self.context, self.model = ctx, model
        if not model then self:Clear(); return end
        self:Render()
        self.pointer:Resume()
    end

    function c:SetShow(key, on)
        if self.show[key] == nil then return end
        self.show[key] = on and true or false
        if self.model then self:Render() end
    end
    function c:SetStrokeMode(mode) self.strokes:SetMode(mode); self.drawn = nil; self:Render() end

    c:SetScript("OnSizeChanged", function() if c.model and c:IsShown() then c.drawn = nil; c:Render() end end)
    c:SetScript("OnHide", function() c.pointer:Cancel() end)
    LayoutLegend()
    return c
end
