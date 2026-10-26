-- TwichUI Diagnostics: charts
-- Two small primitives drawn with textures (nothing here runs while a chart is idle or hidden):
--   Chart.Line   one metric over capture time, on one axis (never two scales on one chart). The plot has a column
--                every 2 pixels; each column covers the buckets under it and shows their lowest to highest as a
--                faint band and their mean as a tick, so a single bad second is never averaged away. A column with a
--                discontinuity (loading, a pause) is shaded; markers are thin neutral lines (yours a little brighter,
--                with a flag). Hover shows the column's numbers and nearby markers (the tooltip follows the pointer
--                only while it is over the plot); drag selects a window, a click selects one column, right-click
--                clears it.
--   Chart.Bars   a ranked list of horizontal bars with their label and value in text colors; click selects a row.
-- Metric colors (Chart.COLOR) are a fixed order checked with the data-viz palette validator against the window's
-- stone surface (lightness band, chroma, colour-blind separation of neighbours, contrast): teal, rust, blue, bronze,
-- violet. Text never takes a series' color.

local R = TwichUI
local DX = R.DiagnosticsKit
local Chart = {}
DX.Chart = Chart

local function Hex(h) return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 } end
Chart.COLOR = {
    cpu = Hex("#20A89B"),      -- TwichUI's time by the client's count
    diag = Hex("#B1563F"),     -- the diagnostics' own
    events = Hex("#5D94DA"),   -- events and callbacks
    work = Hex("#9B690B"),     -- instrumented work
    memory = Hex("#AE7BC5"),   -- memory
    frames = { 0.79, 0.76, 0.69 },   -- frame interval: a neutral (shown alone)
    a = Hex("#5D94DA"), b = Hex("#9B690B"),   -- comparison: A and B (validated as a pair)
}
local MARK = { 0.62, 0.60, 0.56 }   -- markers: neutral; yours brighter and flagged
local MARK_MINE = { 0.94, 0.91, 0.82 }

local function L() return R.Look end
local function Pal() return R.Look.pal end

-- 1, 2 or 5 times a power of ten, at or over v
local function Nice(v)
    if not v or v <= 0 then return 1 end
    local p = 10 ^ math.floor(math.log10 and math.log10(v) or (math.log(v) / math.log(10)))
    for _, m in ipairs({ 1, 2, 5, 10 }) do if v <= m * p then return m * p end end
    return 10 * p
end
Chart.Nice = Nice

local function Fmt(v, unit)
    if v == nil then return "n/a" end
    if unit == "ms" then return DX.Ms(v) end
    if math.abs(v) >= 100 then return ("%.0f %s"):format(v, unit or "") end
    return ("%.1f %s"):format(v, unit or "")
end
Chart.Fmt = Fmt

---------------------------------------------------------------------------
-- Line (envelope) chart
---------------------------------------------------------------------------
local Line = {}
Line.__index = Line

function Chart.Line(parent, width, height)
    local Look, pal = L(), Pal()
    local self = setmetatable({ w = width, h = height, cols = {}, ticks = {}, marks = {}, flags = {}, shades = {}, grid = {}, labels = {} }, Line)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(width, height)
    Look.Well(f, 0.6)
    self.frame = f
    self.left, self.bottom, self.top, self.right = 52, 18, 8, 8
    self.pw = width - self.left - self.right
    self.ph = height - self.top - self.bottom
    local plot = CreateFrame("Frame", nil, f)
    plot:SetPoint("BOTTOMLEFT", self.left, self.bottom)
    plot:SetSize(self.pw, self.ph)
    self.plot = plot
    for i = 1, 3 do
        local g = Look.Solid(plot, "BACKGROUND", pal.divider, i == 1 and 0.6 or 0.25)
        g:SetHeight(1)
        self.grid[i] = g
        local t = Look.Text(f, "meta")
        t:SetJustifyH("RIGHT")
        t:SetWidth(self.left - 6)
        self.labels[i] = t
    end
    self.tStart, self.tMid, self.tEnd = Look.Text(f, "meta"), Look.Text(f, "meta"), Look.Text(f, "meta")
    self.tStart:SetPoint("TOPLEFT", plot, "BOTTOMLEFT", 0, -3)
    self.tMid:SetPoint("TOP", plot, "BOTTOM", 0, -3)
    self.tEnd:SetPoint("TOPRIGHT", plot, "BOTTOMRIGHT", 0, -3)
    self.empty = Look.Text(f, "small")
    self.empty:SetPoint("CENTER", plot, "CENTER")
    self.empty:SetWidth(self.pw - 40)
    self.empty:SetJustifyH("CENTER")
    self.sel = Look.Solid(plot, "BORDER", pal.text, 0.08)
    self.sel:Hide()
    -- the pointer layer: hover, drag and click
    local hit = CreateFrame("Button", nil, plot)
    hit:SetAllPoints()
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnEnter", function() self:Hover(true) end)
    hit:SetScript("OnLeave", function() self:Hover(false) end)
    hit:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then self.dragFrom = self:CursorT() end end)
    hit:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then self.dragFrom = nil; self:Select(nil) return end
        local from, to = self.dragFrom, self:CursorT()
        self.dragFrom = nil
        if not (from and to) then return end
        if math.abs(to - from) < self.span / self.pw * 3 then   -- a click: the column under the pointer
            local c = self:ColumnAt(to)
            if c then from, to = c.t0, c.t1 end
        end
        if from > to then from, to = to, from end
        self:Select({ from, to })
    end)
    self.hit = hit
    return self
end

-- capture time under the pointer, or nil
function Line:CursorT()
    if not (self.plot and GetCursorPosition) then return nil end
    local x = GetCursorPosition() / (self.plot:GetEffectiveScale() or 1)
    local left = self.plot:GetLeft()
    if not left then return nil end
    local frac = math.max(0, math.min(1, (x - left) / self.pw))
    return self.t0 + frac * self.span
end

function Line:ColumnAt(t)
    for _, c in ipairs(self.data or {}) do if t >= c.t0 and t <= c.t1 then return c end end
    return nil
end

local function Tex(pool, i, parent, layer)
    local t = pool[i]
    if not t then
        t = parent:CreateTexture(nil, layer)
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        pool[i] = t
    end
    return t
end

-- spec: { t = {bucket start s}, v = {mean per bucket}, hi = {worst per bucket} (optional), lo = (optional), n,
--         gap = {per bucket: >0 = discontinuity}, unit, label, color, duration, markers = { {t, kind, label, mine} },
--         empty = text shown when nothing can be drawn }
function Line:Draw(spec)
    self.spec = spec
    local n = spec.n or 0
    local pal = Pal()
    local hasValue = false
    for i = 1, n do if spec.v[i] ~= nil then hasValue = true break end end
    for _, t in ipairs(self.cols) do t:Hide() end
    for _, t in ipairs(self.ticks) do t:Hide() end
    for _, t in ipairs(self.shades) do t:Hide() end
    for _, t in ipairs(self.marks) do t:Hide() end
    for _, t in ipairs(self.flags) do t:Hide() end
    self.data = {}
    self.t0, self.span = 0, math.max(1, spec.duration or n)
    if not hasValue then
        self.empty:SetText(spec.empty or "Nothing was recorded for this metric.")
        self.empty:Show()
        for i = 1, 3 do self.grid[i]:Hide(); self.labels[i]:SetText("") end
        self.tStart:SetText(""); self.tMid:SetText(""); self.tEnd:SetText("")
        return
    end
    self.empty:Hide()
    -- columns of 2 px, each covering the buckets whose start falls under it
    local ncol = math.max(1, math.floor(self.pw / 2))
    local cols = {}
    local ymax = 0
    for i = 1, n do
        local t = spec.t[i] or (i - 1)
        local c = math.min(ncol, math.floor(t / self.span * ncol) + 1)
        local col = cols[c]
        if not col then
            col = { sum = 0, count = 0, lo = math.huge, hi = -math.huge, gap = false, t0 = t, t1 = t + (spec.step or 1) }
            cols[c] = col
        end
        col.t1 = math.max(col.t1, t + (spec.step or 1))
        local v = spec.v[i]
        if v ~= nil then
            local hi = spec.hi and spec.hi[i] or v
            local lo = spec.lo and spec.lo[i] or v
            col.sum, col.count = col.sum + v, col.count + 1
            if hi > col.hi then col.hi = hi end
            if lo < col.lo then col.lo = lo end
            if hi > ymax then ymax = hi end
        end
        if spec.gap and (spec.gap[i] or 0) > 0 then col.gap = true end
    end
    ymax = Nice(ymax * 1.05)
    self.ymax = ymax
    local color = spec.color or pal.text
    local k = 0
    for c = 1, ncol do
        local col = cols[c]
        if col then
            local x = (c - 1) * 2
            if col.gap then
                local s = Tex(self.shades, #self.data + 1, self.plot, "BACKGROUND")
                s:SetVertexColor(pal.stone[1], pal.stone[2], pal.stone[3], 0.18)
                s:ClearAllPoints(); s:SetPoint("BOTTOMLEFT", x, 0); s:SetSize(2, self.ph); s:Show()
            end
            if col.count > 0 then
                k = k + 1
                col.mean = col.sum / col.count
                local y0 = col.lo / ymax * self.ph
                local y1 = math.max(y0 + 1, col.hi / ymax * self.ph)
                local band = Tex(self.cols, k, self.plot, "ARTWORK")
                band:SetVertexColor(color[1], color[2], color[3], 0.38)
                band:ClearAllPoints(); band:SetPoint("BOTTOMLEFT", x, y0); band:SetSize(2, y1 - y0); band:Show()
                local tick = Tex(self.ticks, k, self.plot, "OVERLAY")
                tick:SetVertexColor(color[1], color[2], color[3], 1)
                tick:ClearAllPoints(); tick:SetPoint("BOTTOMLEFT", x, math.max(0, col.mean / ymax * self.ph - 1)); tick:SetSize(2, 2); tick:Show()
            end
            self.data[#self.data + 1] = col
        end
    end
    for i = 1, 3 do
        local frac = (i - 1) / 2
        local g = self.grid[i]
        g:ClearAllPoints(); g:SetPoint("BOTTOMLEFT", 0, frac * self.ph); g:SetPoint("BOTTOMRIGHT", 0, frac * self.ph); g:Show()
        self.labels[i]:ClearAllPoints()
        self.labels[i]:SetPoint("RIGHT", self.plot, "BOTTOMLEFT", -6, frac * self.ph)
        self.labels[i]:SetText(Fmt(ymax * frac, spec.unit))
    end
    self.tStart:SetText("0:00")
    self.tMid:SetText(DX.Clock2(self.span / 2))
    self.tEnd:SetText(DX.Clock2(self.span))
    local m = 0
    for _, mk in ipairs(spec.markers or {}) do
        if mk.t >= 0 and mk.t <= self.span then
            m = m + 1
            local line = Tex(self.marks, m, self.plot, "OVERLAY")
            local c = mk.mine and MARK_MINE or MARK
            line:SetVertexColor(c[1], c[2], c[3], mk.mine and 0.9 or 0.45)
            local x = mk.t / self.span * self.pw
            line:ClearAllPoints(); line:SetPoint("BOTTOMLEFT", x, 0); line:SetSize(1, self.ph); line:Show()
            if mk.mine then
                local flag = Tex(self.flags, m, self.plot, "OVERLAY")
                flag:SetVertexColor(c[1], c[2], c[3], 0.9)
                flag:ClearAllPoints(); flag:SetPoint("TOPLEFT", x, 0); flag:SetSize(5, 4); flag:Show()
            end
        end
    end
    self:Select(self.window, true)
end

function Line:Select(window, quiet)
    self.window = window
    if window and self.span then
        local x0 = math.max(0, window[1] / self.span * self.pw)
        local x1 = math.min(self.pw, window[2] / self.span * self.pw)
        self.sel:ClearAllPoints()
        self.sel:SetPoint("BOTTOMLEFT", x0, 0)
        self.sel:SetSize(math.max(2, x1 - x0), self.ph)
        self.sel:Show()
    else
        self.sel:Hide()
    end
    if not quiet and self.onSelect then self.onSelect(window) end
end

function Line:Hover(on)
    if not on then
        self.hit:SetScript("OnUpdate", nil)
        if GameTooltip:IsOwned(self.hit) then GameTooltip:Hide() end
        return
    end
    local last
    self.hit:SetScript("OnUpdate", function()
        local t = self:CursorT()
        local col = t and self:ColumnAt(t)
        if col == last then return end
        last = col
        GameTooltip:SetOwner(self.hit, "ANCHOR_CURSOR")
        local spec = self.spec or {}
        if not col then GameTooltip:SetText(spec.label or "", 1, 1, 1) GameTooltip:Show() return end
        GameTooltip:SetText(("%s  %s to %s"):format(spec.label or "", DX.Clock2(col.t0), DX.Clock2(col.t1)), 1, 1, 1)
        if col.count > 0 then
            GameTooltip:AddLine(("mean %s, lowest %s, highest %s"):format(Fmt(col.mean, spec.unit), Fmt(col.lo, spec.unit), Fmt(col.hi, spec.unit)), 0.9, 0.87, 0.78)
            GameTooltip:AddLine(("%d bucket(s) of %s each in this column"):format(col.count, spec.step and spec.step > 1 and (spec.step .. " s") or "1 s"), 0.62, 0.60, 0.56)
        end
        if col.gap then GameTooltip:AddLine("A discontinuity (loading or a pause) is in this column.", 0.62, 0.60, 0.56) end
        for _, mk in ipairs(spec.markers or {}) do
            if mk.t >= col.t0 - 1 and mk.t <= col.t1 + 1 then
                GameTooltip:AddLine(("%s %s%s"):format(DX.Clock2(mk.t), mk.kind, mk.label and (": " .. mk.label) or ""), 0.62, 0.78, 0.76)
            end
        end
        if spec.hint then GameTooltip:AddLine(spec.hint, 0.62, 0.60, 0.56, true) end
        GameTooltip:Show()
    end)
end

---------------------------------------------------------------------------
-- Ranked bars
---------------------------------------------------------------------------
local Bars = {}
Bars.__index = Bars

function Chart.Bars(parent, width, labelW)
    return setmetatable({ parent = parent, w = width, labelW = labelW or 230, rows = {} }, Bars)
end

-- list: { { key, label, value, text, tip } }; color: the bars' one color. Returns the height used.
function Bars:Draw(list, color, maxValue, y)
    local Look, pal = L(), Pal()
    y = y or 0
    maxValue = maxValue or 0
    for _, item in ipairs(list) do if (item.value or 0) > maxValue then maxValue = item.value end end
    local barW = self.w - self.labelW - 110
    for i, item in ipairs(list) do
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Button", nil, self.parent)
            row:SetSize(self.w, 18)
            row.label = Look.Text(row, "small")
            row.label:SetPoint("LEFT", 2, 0)
            row.label:SetWidth(self.labelW - 8)
            row.label:SetWordWrap(false)
            row.bar = Look.Solid(row, "ARTWORK", pal.text, 1)
            row.bar:SetHeight(10)
            row.value = Look.Text(row, "meta")
            row.sel = Look.Solid(row, "BACKGROUND", pal.bronzeText, 0.10)
            row.sel:SetAllPoints()
            row:SetScript("OnEnter", function(b)
                if not b.item then return end
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                GameTooltip:SetText(b.item.label, 1, 1, 1)
                if b.item.tip then GameTooltip:AddLine(b.item.tip, 0.9, 0.87, 0.78, true) end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(b) if GameTooltip:IsOwned(b) then GameTooltip:Hide() end end)
            row:SetScript("OnClick", function(b) if self.onClick and b.item then self.onClick(b.item) end end)
            self.rows[i] = row
        end
        row.item = item
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, -y)
        row.label:SetText(item.label)
        local frac = maxValue > 0 and (item.value or 0) / maxValue or 0
        row.bar:ClearAllPoints()
        row.bar:SetPoint("LEFT", row, "LEFT", self.labelW, 0)
        row.bar:SetWidth(math.max(1, frac * barW))
        row.bar:SetVertexColor(color[1], color[2], color[3], 1)
        row.value:ClearAllPoints()
        row.value:SetPoint("LEFT", row.bar, "RIGHT", 6, 0)
        row.value:SetText(item.text or "")
        row.sel:SetShown(self.selected ~= nil and self.selected == item.key)
        row:Show()
        y = y + 20
    end
    for i = #list + 1, #self.rows do self.rows[i]:Hide() end
    return y
end

function Bars:Hide() for _, r in ipairs(self.rows) do r:Hide() end end
