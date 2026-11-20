-- TwichUI Workshop: the Gold Flow chart (UI.GoldFlowChart)
-- Daily gold in (muted green, above the zero line), gold out (restrained red, below it) and the net change (an antique-gold line), over the
-- window the page chose. The geometry is pure (C.Geometry: days in, rectangles and points out) so it is tested without frames; the frame
-- pools its textures, draws only when its data or size changed, and listens to nothing: the pointer is read through one small button per
-- day (enter and leave), never an OnUpdate. It shares the Workshop chart family's materials (UI.Panel, UI.L.Solid, the bronze guide
-- lines, native lines with a drawn fallback) but not its price-line renderer: this one is made of bars and a line, with no zoom.
--
-- A day with no record is "outside recorded coverage": drawn as a faint empty column and named so on inspection, never as zero. A day the
-- recorder covered with no gold moving is a thin tick on the zero line ("recorded, nothing moved"). The net line is never drawn through
-- a day that was not recorded.

local R = TwichUI
local W = R.Workshop
local UI = W.UI
local LQ = W.LedgerQuery
local C = { MIN_BAR = 1 }
W.LedgerChart = C

local GREEN = { 0.40, 0.58, 0.34 }
local RED = { 0.68, 0.28, 0.25 }
C.GREEN, C.RED = GREEN, RED
local charts = setmetatable({}, { __mode = "k" })
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("ledger.chartPool", { label = "Gold Ledger chart pooled regions", unit = "count", kind = "pool", group = "workshop",
        read = function() local n = 0 for chart in pairs(charts) do n = n + #chart.bars + #chart.dots + #chart.lines + #chart.hits + #chart.labels end return n end })
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

-- Compact axis text: "300g", "-50g", "12k", "40s", "0g".
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

-- days: LedgerQuery.Summary(...).days; show: { inn, out, net } booleans; pw, ph: the plot's size.
function C.Geometry(days, pw, ph, show)
    show = show or { inn = true, out = true, net = true }
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
    local bw = math.max(3, math.min(34, math.floor(slot * 0.6)))
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
                local p = { x = cx, y = Y(d.net), index = i }
                g.points[#g.points + 1] = p
                if prev and prev.index == i - 1 then g.segments[#g.segments + 1] = { a = prev, b = p } end
                prev = p
            else
                prev = nil
            end
        end
    end
    local every = n <= 10 and 1 or (n <= 31 and 5 or 15)
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
local LEFT, RIGHT, TOP, XROW, LEGEND = 50, 10, 8, 16, 24

function UI.GoldFlowChart(parent, w, h)
    local K = UI.K
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(w, h)
    charts[c] = true
    c.bars, c.dots, c.lines, c.hits, c.labels, c.guides, c.cols = {}, {}, {}, {}, {}, {}, {}
    c.show = { inn = true, out = true, net = true }
    c.plot = CreateFrame("Frame", nil, c)
    c.plot:SetPoint("TOPLEFT", LEFT, -TOP)
    c.plot:SetPoint("BOTTOMRIGHT", -RIGHT, XROW + LEGEND)
    local function Solid(color, alpha, layer) return UI.L.Solid(c.plot, layer or "ARTWORK", color, alpha) end
    c.zero = Solid(K.bronzeHi, 0.55, "ARTWORK")
    c.highlight = Solid(K.bronzeText, 0.10, "BACKGROUND")
    c.highlight:Hide()
    c.msg = UI.Text(c, 13, K.textDim)
    c.msg:SetPoint("CENTER", c.plot, "CENTER")
    c.msg:SetWidth(w - 120)
    c.msg:SetJustifyH("CENTER")
    c.msg:SetWordWrap(true)

    local function Pooled(pool, make, i)
        local t = pool[i]
        if not t then t = make(); pool[i] = t end
        return t
    end
    local function Hide(pool, from) for i = from or 1, #pool do pool[i]:Hide() end end

    -- the legend: three toggles (a swatch and the words); the page fills the totals
    c.legendButtons = {}
    local lx = LEFT
    for _, def in ipairs({ { "inn", "Gold in", GREEN }, { "out", "Gold out", RED }, { "net", "Net change", K.bronzeText } }) do
        local b = CreateFrame("Button", nil, c)
        b:SetSize(150, 20)
        b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", lx, 0)
        lx = lx + 156
        b.swatch = UI.L.Solid(b, "ARTWORK", def[3], 0.9)
        b.swatch:SetSize(11, 11)
        b.swatch:SetPoint("LEFT", 0, 0)
        b.text = UI.Text(b, 12, K.textDim)
        b.text:SetPoint("LEFT", b.swatch, "RIGHT", 6, 0)
        b.key, b.name = def[1], def[2]
        b:SetScript("OnClick", function(self) c:SetShow(self.key, not c.show[self.key]) end)
        UI.TipFn(b, def[2], function(self) return c.show[self.key] and "Click to hide this from the chart." or "Click to show this on the chart." end)
        c.legendButtons[def[1]] = b
    end

    local function PaintLegend()
        local d = c.model
        local totals = d and d.totals
        for key, b in pairs(c.legendButtons) do
            local on = c.show[key]
            local value = totals and (key == "inn" and LQ.Money(totals.inn) or key == "out" and LQ.Money(-totals.out) or LQ.Money(totals.net, true)) or nil
            b.text:SetText(b.name .. (value and (" (" .. value .. ")") or ""))
            UI.Paint(b.text, on and K.text or K.stone)
            b.swatch:SetAlpha(on and 0.9 or 0.25)
        end
    end

    local function Inspect(i)
        local d = c.model and c.model.days[i]
        if not d or not GameTooltip then return end
        local g = c.geometry
        c.highlight:ClearAllPoints()
        c.highlight:SetPoint("BOTTOMLEFT", c.plot, "BOTTOMLEFT", (i - 1) * g.slot, 0)
        c.highlight:SetSize(g.slot, c.plot:GetHeight() or g.ph)
        c.highlight:Show()
        GameTooltip:SetOwner(c.hits[i], "ANCHOR_RIGHT")
        local lines = C.TipLines(d)
        GameTooltip:AddLine(lines[1], 1, 0.82, 0)
        for k = 2, #lines do
            local line = lines[k]
            local col = K[line[2]] or K.text
            GameTooltip:AddLine(line[1], col[1], col[2], col[3], true)
        end
        GameTooltip:Show()
        c.inspected = i
    end
    function c:ClearInspection()
        self.highlight:Hide()
        self.inspected = nil
        if GameTooltip then GameTooltip:Hide() end
    end

    function c:Render()
        local d = self.model
        if not d then return end
        local pw, ph = self.plot:GetWidth() or 0, self.plot:GetHeight() or 0
        if pw < 20 then pw = w - LEFT - RIGHT end
        if ph < 20 then ph = h - TOP - XROW - LEGEND end
        local g = C.Geometry(d.days, pw, ph, self.show)
        self.geometry = g
        self:ClearInspection()
        -- nothing to show: no axis, line or scale (an arbitrary band would read as a real amount), only the words; recorded quiet days
        -- and days outside coverage keep their marks
        local empty = not d.recording or d.totals.n == 0
        if empty then g.grid, g.points, g.segments, g.zeroY = {}, {}, {}, nil end
        self.empty = empty
        self.msg:SetText(not d.recording and "Gold tracking hasn't started yet." or (empty and "No gold activity recorded in this period." or ""))
        -- zero line and guides
        local n = 0
        for _, line in ipairs(g.grid) do
            n = n + 1
            local gl = Pooled(self.guides, function() return { line = Solid(K.bronzeLo, 0.28), label = UI.Text(c, 10, K.bronzeText) } end, n)
            gl.line:ClearAllPoints(); gl.line:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, line.y); gl.line:SetSize(pw, 1); gl.line:Show()
            gl.label:ClearAllPoints(); gl.label:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -8, line.y)
            gl.label:SetWidth(LEFT - 12); gl.label:SetJustifyH("RIGHT")
            gl.label:SetText(C.AxisText(line.value)); gl.label:Show()
        end
        for i = n + 1, #self.guides do self.guides[i].line:Hide(); self.guides[i].label:Hide() end
        if g.zeroY then
            self.zero:ClearAllPoints(); self.zero:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", 0, g.zeroY - 0.5)
            self.zero:SetSize(pw, 1); self.zero:Show()
        else
            self.zero:Hide()
        end
        -- columns outside coverage, bars and ticks share one pool of solids
        local used = 0
        local function Rect(r, color, alpha)
            used = used + 1
            local t = Pooled(self.bars, function() return Solid(color, alpha) end, used)
            t:ClearAllPoints(); t:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", r.x, r.y)
            t:SetSize(r.w, r.h); t:SetColorTexture(color[1], color[2], color[3], alpha); t:Show()
            return t
        end
        for _, u in ipairs(g.uncovered) do Rect({ x = u.x + 1, y = 0, w = math.max(1, u.w - 2), h = ph }, K.bronzeLo, 0.07) end
        for _, t in ipairs(g.ticks) do Rect(t, K.bronzeText, 0.55) end
        for _, b in ipairs(g.bars) do Rect(b, b.kind == "in" and GREEN or RED, 0.86) end
        Hide(self.bars, used + 1)
        self.barCount = #g.bars
        -- the net line: dots, and native lines anchored to them (or a drawn fallback)
        for i, p in ipairs(g.points) do
            local dot = Pooled(self.dots, function() local t = Solid(K.bronzeText, 1, "OVERLAY"); t:SetSize(5, 5); return t end, i)
            dot:ClearAllPoints(); dot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", p.x, p.y); dot:SetColorTexture(K.bronzeText[1], K.bronzeText[2], K.bronzeText[3], 1); dot:Show()
            p.dot = dot
        end
        Hide(self.dots, #g.points + 1)
        local native = type(self.plot.CreateLine) == "function"
        local drawn = 0
        for i, s in ipairs(g.segments) do
            local ok = native and pcall(function()
                local line = Pooled(self.lines, function()
                    local l = self.plot:CreateLine(nil, "ARTWORK", nil, 1)
                    assert(l and l.SetStartPoint and l.SetEndPoint and l.SetThickness)
                    return l
                end, i)
                line:SetColorTexture(K.bronzeText[1], K.bronzeText[2], K.bronzeText[3], 0.95)
                line:SetThickness(1.6)
                line:SetStartPoint("CENTER", s.a.dot, 0, 0); line:SetEndPoint("CENTER", s.b.dot, 0, 0); line:Show()
            end)
            if ok then drawn = drawn + 1 else native = false end
        end
        if native then Hide(self.lines, drawn + 1) else Hide(self.lines) end
        -- a drawn fallback: small steps along each segment (bounded), when the client offers no line object
        self.stepCount = 0
        if not native then
            local used2 = #g.points
            for _, s in ipairs(g.segments) do
                local dx, dy = s.b.x - s.a.x, s.b.y - s.a.y
                local steps = math.min(24, math.floor(math.sqrt(dx * dx + dy * dy) / 4))
                for k = 1, steps - 1 do
                    used2 = used2 + 1
                    local dot = Pooled(self.dots, function() local t = Solid(K.bronzeText, 1, "OVERLAY"); t:SetSize(5, 5); return t end, used2)
                    dot:ClearAllPoints(); dot:SetPoint("CENTER", self.plot, "BOTTOMLEFT", s.a.x + dx * k / steps, s.a.y + dy * k / steps)
                    dot:SetSize(2, 2); dot:Show()
                    self.stepCount = self.stepCount + 1
                end
            end
            Hide(self.dots, used2 + 1)
        end
        -- day labels under the plot
        for i, xl in ipairs(g.xlabels) do
            local fs = Pooled(self.labels, function() local t = UI.Text(c, 10, K.bronzeText); t:SetJustifyH("CENTER"); t:SetWidth(54); return t end, i)
            fs:ClearAllPoints(); fs:SetPoint("TOP", self.plot, "BOTTOMLEFT", xl.x, -3); fs:SetText(xl.text); fs:Show()
        end
        Hide(self.labels, #g.xlabels + 1)
        -- one pointer region for each day (enter and leave only)
        for i = 1, g.n do
            local hit = Pooled(self.hits, function()
                local b = CreateFrame("Button", nil, self.plot)
                b:SetFrameLevel((self.plot:GetFrameLevel() or 1) + 6)
                b:SetScript("OnEnter", function(s) Inspect(s.index) end)
                b:SetScript("OnLeave", function() c:ClearInspection() end)
                return b
            end, i)
            hit.index = i
            hit:ClearAllPoints(); hit:SetPoint("BOTTOMLEFT", self.plot, "BOTTOMLEFT", (i - 1) * g.slot, 0)
            hit:SetSize(math.max(1, g.slot), ph); hit:Show()
        end
        Hide(self.hits, g.n + 1)
        PaintLegend()
    end

    -- model: LedgerQuery.Summary(...) or nil
    function c:Set(model)
        self.model = model
        if not model then
            self:ClearInspection()
            for _, pool in ipairs({ self.bars, self.dots, self.lines, self.hits, self.labels }) do Hide(pool) end
            for _, gl in ipairs(self.guides) do gl.line:Hide(); gl.label:Hide() end
            self.zero:Hide()
            self.msg:SetText("")
            self.geometry = nil
            return
        end
        self:Render()
    end
    function c:SetShow(key, on)
        if self.show[key] == nil then return end
        self.show[key] = on and true or false
        if self.model then self:Render() end
    end
    c:SetScript("OnSizeChanged", function() if c.model and c:IsShown() then c:Render() end end)
    c:SetScript("OnHide", function() c:ClearInspection() end)
    return c
end
