-- TwichUI Test Lab: the window's controls (R.TestLab.Kit)
-- The Workshop's presentation helpers (TwichUI_Workshop/Style.lua) drawn through the core's shared pieces (R.CraftLook, R.Look, R.FrameLook).
-- They are copied in small, not required, because the Lab loads on its own: it never depends on the Workshop being loaded. Every texture is
-- made once, when the window is built; nothing here runs per frame, polls, reads or writes saved data, or knows a case.
--
--   K.Init()                          looks up the shared looks (called when the window is first built)
--   K.Text(parent, size, color, role) a native font string in the crafted fonts ("serif" / "strong")
--   K.Panel(frame, kind)              a card ("card"), well ("canvas"), editor ("editor") or dark ("espresso") surface
--   K.Glyph(parent, kind, size, color) a small drawn shape: stack skip shield warn hourglass play stop doc; :SetColor(c, a)
--   K.Status(texture, status)         the status picture of a result (the shared guide status art, or a drawn mark)
--   K.Button(parent, label, w, kind, onClick, h, glyph)   a painted button with an optional glyph before its label
--   K.Segment(parent, label, w, onClick)   a filter chip (b:SetOn(bool))
--   K.Search(parent, w, h, placeholder)    a search field
--   K.Check(parent, size, onToggle)   a square check (b:SetChecked, b:GetChecked, b:SetActive)
--   K.Hover(row)                      a row's painted hover and chosen state (row:SetSelected, row:SetStripe, row.hovered)
--   K.List(parent, rowH, make, minH)  a pooled scrolling list: only the rows that can show exist (:SetData, :ScrollTo, :RowCount)
--   K.Meter(parent, w, h)             a recessed progress bar (:SetFraction, :SetTone)
--   K.Card(parent, w, h, glyph, label) a summary card (:Set(value, tone, note))
--   K.Tip(frame, title, body)         the core's tooltip when it is there

local R = TwichUI
local TL = R.TestLab
local K = {}
TL.Kit = K

local L, P, CL, F   -- Look, its palette, CraftLook, FrameLook
function K.Init()
    L, P, CL, F = R.Look, R.Look.pal, R.CraftLook, R.FrameLook
    K.L, K.P, K.CL, K.F = L, P, CL, F
end

-- Result tones: a word and a mark always go with them, so none is colour alone
K.TONE = {
    pass = { 0.60, 0.74, 0.55 },       -- muted green
    fail = { 0.86, 0.43, 0.37 },       -- subdued red
    error = { 0.92, 0.58, 0.30 },      -- warm amber-red
    timeout = { 0.90, 0.72, 0.32 },    -- amber
    skipped = { 0.70, 0.66, 0.60 },    -- neutral
    stopped = { 0.70, 0.66, 0.60 },
    pending = { 0.60, 0.565, 0.51 },
    running = { 0.804, 0.651, 0.365 }, -- antique gold
}

function K.Paint(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

function K.Text(parent, size, color, role, layer)
    local fs = L.Text(parent, "body", layer)
    CL.Font(fs, size or 14, false, role)
    K.Paint(fs, color or P.text)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function K.Panel(frame, kind) return CL.PanelFace(frame, kind or "card") end

function K.Rule(parent, alpha)
    local t = L.Solid(parent, "ARTWORK", P.bronzeLo, alpha or 0.55)
    t:SetHeight(1)
    return t
end

function K.Tip(frame, title, body)
    if R.Interact and R.Interact.Tip then R.Interact.Tip(frame, title, body) end
end

---------------------------------------------------------------------------
-- Drawn shapes (rows of solid pixels: no texture file, the same in every font and size)
---------------------------------------------------------------------------
function K.Glyph(parent, kind, size, color)
    local g = CreateFrame("Frame", nil, parent)
    g:SetSize(size, size)
    g:EnableMouse(false)
    g.parts, g.knock = {}, {}
    local function Bit(x, y, w, h, hole)
        local c = hole and { 0.10, 0.075, 0.06 } or (color or P.text)
        local t = L.Solid(g, "OVERLAY", c, 1)
        if hole then t:SetDrawLayer("OVERLAY", 2) end
        t:SetPoint("TOPLEFT", g, "TOPLEFT", x, -y)
        t:SetSize(math.max(1, w), math.max(1, h))
        local list = hole and g.knock or g.parts
        list[#list + 1] = t
    end
    local s = size
    if kind == "stack" then
        local h = math.max(2, math.floor(s / 6))
        for i = 0, 2 do Bit(math.floor(i * s * 0.09), math.floor(s * 0.12) + i * (h + 2) * 1, s - math.floor(i * s * 0.18), h) end
        Bit(math.floor(s * 0.18), math.floor(s * 0.12) + 3 * (h + 2), s - math.floor(s * 0.36), h)
    elseif kind == "play" or kind == "skip" then
        local n = math.floor(s * 0.62)
        local x0 = math.floor(s * 0.2)
        for i = 0, n - 1 do
            local half = math.floor((n - i) / 2 + 0.5)
            Bit(x0 + i, math.floor(s / 2) - half, 1, math.max(1, half * 2))
        end
        if kind == "skip" then Bit(x0 + n + 1, math.floor(s / 2) - math.floor(n / 2), 2, n) end
    elseif kind == "stop" then
        local n = math.floor(s * 0.55)
        Bit(math.floor((s - n) / 2), math.floor((s - n) / 2), n, n)
    elseif kind == "warn" or kind == "hourglass" then
        local n = s
        local rows = math.floor(n * 0.8)
        local top = math.floor((n - rows) / 2)
        if kind == "warn" then
            for i = 0, rows - 1 do
                local w = math.max(1, math.floor(i * (n - 2) / rows) + 1)
                Bit(math.floor((n - w) / 2), top + i, w, 1)
            end
            Bit(math.floor(n / 2) - 1, top + math.floor(rows * 0.42), 2, math.max(2, math.floor(rows * 0.28)), true)
            Bit(math.floor(n / 2) - 1, top + math.floor(rows * 0.8), 2, 2, true)
        else
            local half = math.floor(rows / 2)
            for i = 0, half - 1 do
                local w = math.max(1, (n - 6) - math.floor(i * (n - 6) / half) + 1)
                Bit(math.floor((n - w) / 2), top + 2 + i, w, 1)
                Bit(math.floor((n - w) / 2), top + 2 + rows - 4 - i, w, 1)
            end
            Bit(math.floor(n * 0.14), top, math.floor(n * 0.72), 2)
            Bit(math.floor(n * 0.14), top + rows - 2, math.floor(n * 0.72), 2)
        end
    elseif kind == "shield" then
        local rows = math.floor(s * 0.88)
        local top = math.floor((s - rows) / 2)
        local w0 = math.floor(s * 0.78)
        for i = 0, rows - 1 do
            local w = i < rows * 0.5 and w0 or math.max(2, math.floor(w0 * (1 - (i - rows * 0.5) / (rows * 0.55))))
            Bit(math.floor((s - w) / 2), top + i, w, 1)
        end
        Bit(math.floor(s / 2) - 1, top + math.floor(rows * 0.2), 2, math.max(2, math.floor(rows * 0.34)), true)
        Bit(math.floor(s / 2) - 1, top + math.floor(rows * 0.62), 2, 2, true)
    elseif kind == "doc" then
        local w, h = math.floor(s * 0.62), math.floor(s * 0.82)
        local x, y = math.floor((s - w) / 2), math.floor((s - h) / 2)
        Bit(x, y, w, 1); Bit(x, y + h - 1, w, 1); Bit(x, y, 1, h); Bit(x + w - 1, y, 1, h)
        for i = 1, 3 do Bit(x + 3, y + 2 + i * math.max(2, math.floor(h / 5)), w - 6, 1) end
    end
    function g:SetColor(c, a)
        for _, t in ipairs(self.parts) do t:SetColorTexture(c[1], c[2], c[3], a or 1) end
    end
    if color then g:SetColor(color, 1) end
    return g
end

-- The picture of a result's status: the shared guide status art where there is one (check, cross, arrow), the same cross tinted for an error
-- or a timeout, and a small drawn mark for the rest. Always beside a word.
local ART = R.PATH .. [[media\guides\status-]]
function K.Status(texture, status, small)
    local suffix = small and "-small" or ""
    local tone = K.TONE[status] or K.TONE.pending
    texture:SetTexCoord(0, 1, 0, 1)
    if status == "pass" then texture:SetTexture(ART .. "done" .. suffix); texture:SetVertexColor(1, 1, 1, 1)
    elseif status == "fail" then texture:SetTexture(ART .. "failed" .. suffix); texture:SetVertexColor(1, 1, 1, 1)
    elseif status == "error" or status == "timeout" then texture:SetTexture(ART .. "failed" .. suffix); texture:SetVertexColor(tone[1] + 0.1, tone[2] + 0.1, tone[3], 1)
    elseif status == "running" then texture:SetTexture(ART .. "current" .. suffix); texture:SetVertexColor(1, 1, 1, 1)
    else texture:SetColorTexture(tone[1], tone[2], tone[3], 0.9) end   -- skipped, stopped, pending: a small neutral mark (sized by the caller)
end

---------------------------------------------------------------------------
-- Buttons, chips, fields
---------------------------------------------------------------------------
local KIND = { secondary = nil, primary = "confirmation", danger = "danger" }

function K.Button(parent, label, w, kind, onClick, h, glyph)
    h = h or 30
    local b = F.Button(parent, label, w, kind == "danger" and "danger" or (kind == "primary" and "primary" or "secondary"), onClick)
    b:SetHeight(h)
    CL.Control(b, KIND[kind or "secondary"])
    CL.Font(b.text, h <= 24 and 13 or 15)
    if glyph then
        local size = math.min(20, h - 8)
        b.glyph = K.Glyph(b, glyph, size, P.text)
        b.glyph:SetPoint("LEFT", 14, 0)
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b.glyph, "RIGHT", 8, 0)
        b.text:SetJustifyH("LEFT")
        local set = b.SetEnabled
        b.SetEnabled = function(self, on)
            set(self, on)
            self.glyph:SetAlpha(on == false and 0.4 or 1)
        end
    end
    return b
end

function K.Segment(parent, label, w, onClick)
    local b = CL.Segment(parent, label, w, onClick)
    b:SetHeight(28)
    CL.Font(b.text, 13)
    function b:SetOn(on) self.on = on and true or false; self:SetSelected(self.on) end
    function b:SetLabel(text) self.text:SetText(text) end
    return b
end

function K.Search(parent, w, h, placeholder)
    local box = L.EditBox(parent, w, h or 28)
    CL.Dress(box, "field")
    box.hint = CL.SearchDecoration(box, placeholder)
    return box
end

function K.Check(parent, size, onToggle)
    local b = CL.Pill(parent, onToggle)
    b:SetSize(size, size)   -- under 26 units wide the shared pill draws a recessed square and a native check
    return b
end

---------------------------------------------------------------------------
-- A row's look: a faint stripe on every other row, a painted hover (eased through Look.Motion, so it is bounded and honours the reduced-motion
-- choice) and the chosen state (the selection sheet and a gold bar at the left edge). The row OWNS its OnEnter and OnLeave. Made once, with the row.
---------------------------------------------------------------------------
function K.Hover(row, corner)
    local c = corner or 8
    local stripe = L.Solid(row, "BACKGROUND", P.text, 0.03)
    stripe:SetDrawLayer("BACKGROUND", 0)
    stripe:SetPoint("TOPLEFT", 2, 0); stripe:SetPoint("BOTTOMRIGHT", -2, 0)
    stripe:Hide()
    local sel = CL.Sheet(row, "selection", { layer = "BACKGROUND", sub = 3, corner = c })
    sel:SetShown(false)
    local hot = CL.Sheet(row, "selection-hot", { layer = "BACKGROUND", sub = 2, corner = c })
    hot:SetAlpha(0)
    local rim = CL.Sheet(row, "hover-rim", { layer = "OVERLAY", sub = 2, corner = c })
    rim:SetAlpha(0)
    local bar = L.Solid(row, "ARTWORK", P.bronzeText, 0.95)
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", 3, -5); bar:SetPoint("BOTTOMLEFT", 3, 5)
    bar:Hide()
    local M = L.Motion
    local function Lit(v)   -- v: how lit the row is, 0 to 1
        hot:SetAlpha(v * (row.selected and 0.4 or 1))
        rim:SetAlpha(v * (row.selected and 0.6 or 1))
    end
    local fade = M and M.Fader(Lit, 0) or nil
    row.hovered = false
    function row:SetHot(on)
        on = on and true or false
        if self.hovered == on then return end
        self.hovered = on
        if fade then fade:To(on and 1 or 0, M.TIME.hover) else Lit(on and 1 or 0) end
    end
    row:SetScript("OnEnter", function(self) self:SetHot(true); if self.TipEnter then self:TipEnter() end end)
    row:SetScript("OnLeave", function(self) if self.TipLeave then self:TipLeave() end; self:SetHot(false) end)
    row:HookScript("OnHide", function(self)
        self.hovered = false
        if fade then fade:Set(0) else Lit(0) end
    end)
    function row:SyncHover()   -- a recycled row that scrolled under the pointer
        local over = self.IsMouseOver and self:IsMouseOver() and true or false
        if over ~= self.hovered then self:SetHot(over) end
    end
    function row:SetSelected(on)
        self.selected = on and true or false
        sel:SetShown(self.selected); bar:SetShown(self.selected)
        Lit(fade and fade.value or (self.hovered and 1 or 0))
    end
    function row:SetStripe(on) stripe:SetShown(on and not self.selected and true or false); self.striped = on and true or false end
end

---------------------------------------------------------------------------
-- A scrolling list that makes only the rows it can show. The caller places list.box. minH is the height assumed until the game has laid the
-- list out (and in the tests, which have no layout); afterwards the real height decides how many rows exist.
---------------------------------------------------------------------------
function K.List(parent, rowH, make, minH, surface)
    local box = CreateFrame("Frame", nil, parent)
    if surface ~= false then K.Panel(box, surface or "canvas") end
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -16, 4)
    local bar = sf.ScrollBar
    if type(bar) == "table" and bar.ClearAllPoints then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 3, -16)
        bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 3, 16)
    end
    local fit = CL.ScrollRail(sf)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(math.max(1, (sf:GetWidth() or 0)), 1)
    sf:SetScrollChild(content)
    local list = { box = box, scroll = sf, content = content, rows = {}, data = {}, rowH = rowH, fit = fit, minH = minH or rowH * 4 }
    list.empty = K.Text(box, 14, P.textDim)
    list.empty:SetPoint("TOPLEFT", 18, -18)
    list.empty:SetPoint("RIGHT", box, "RIGHT", -18, 0)
    list.empty:SetWordWrap(true)
    list.empty:SetJustifyV("TOP")
    local function Height()
        local h = sf:GetHeight() or 0
        return h > rowH and h or list.minH
    end
    function list:Layout()
        local data, rows = self.data, self.rows
        content:SetHeight(math.max(#data * rowH, 1))
        local w = sf:GetWidth() or 0
        if w > 1 then content:SetWidth(w) end
        if w > 60 then self.empty:SetWidth(w - 36) end   -- an explicit width, so the sentence wraps wherever two anchors do not
        local first = math.floor((sf:GetVerticalScroll() or 0) / rowH)
        local count = math.ceil(Height() / rowH) + 1
        for i = 1, count do
            local idx = first + i
            local row = rows[i]
            if idx <= #data then
                if not row then
                    row = make(content)
                    row:SetHeight(rowH)
                    rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(idx - 1) * rowH)
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(idx - 1) * rowH)
                row:Show()
                row.fill(row, data[idx], idx)
                if row.SetStripe then row:SetStripe(idx % 2 == 0) end
                if row.SyncHover then row:SyncHover() end
            elseif row then
                row:Hide()
            end
        end
        for i = count + 1, #rows do rows[i]:Hide() end
        if self.fit then self.fit(#data * rowH) end
    end
    sf:HookScript("OnVerticalScroll", function() list:Layout() end)
    sf:HookScript("OnSizeChanged", function() list:Layout() end)
    function list:SetData(d, emptyText)
        self.data = d
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#d == 0 and emptyText ~= nil)
        local most = math.max(0, #d * rowH - Height())
        if (sf:GetVerticalScroll() or 0) > most then sf:SetVerticalScroll(most) end
        self:Layout()
    end
    -- scrolls just far enough that data row idx is wholly in view
    -- (a row that has to be scrolled to is put near the middle, on a whole row, so no row is cut at the top)
    function list:ScrollTo(idx)
        local top, view = (idx - 1) * rowH, Height()
        local at = sf:GetVerticalScroll() or 0
        if top >= at and top + rowH <= at + view then return end
        local most = math.max(0, #self.data * rowH - view)
        local want = math.max(0, math.min(most, top - math.floor((view - rowH) / 2)))
        sf:SetVerticalScroll(math.floor(want / rowH + 0.5) * rowH)
    end
    function list:ScrollTop() sf:SetVerticalScroll(0) end
    function list:RowCount() local n = 0 for _, r in ipairs(self.rows) do if r:IsShown() then n = n + 1 end end return n end
    return list
end

---------------------------------------------------------------------------
-- A recessed progress bar. frac 0..1. Every texture is made once; :SetFraction only moves the fill's width.
---------------------------------------------------------------------------
function K.Meter(parent, w, h)
    local m = CreateFrame("Frame", nil, parent)
    h = h or 12
    m:SetSize(w, h)
    local track = L.Solid(m, "BACKGROUND", P.ink, 1)
    track:SetAllPoints()
    local floor = L.Solid(m, "BACKGROUND", P.bronzeLo, 0.10)
    floor:SetDrawLayer("BACKGROUND", 1)
    floor:SetPoint("TOPLEFT", 2, -3); floor:SetPoint("BOTTOMRIGHT", -2, 2)
    local function Edge(p1, p2, wd, ht, c, a)
        local e = L.Solid(m, "BORDER", c, a)
        e:SetPoint(p1); e:SetPoint(p2)
        if wd then e:SetWidth(wd) else e:SetHeight(ht) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1, P.bronze, 0.6)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1, P.bronzeHi, 0.5)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil, P.bronze, 0.6)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil, P.bronze, 0.6)
    local inner = L.Solid(m, "BORDER", P.ink, 0.9)
    inner:SetPoint("TOPLEFT", 1, -1); inner:SetPoint("TOPRIGHT", -1, -1); inner:SetHeight(1)
    m.fill = L.Solid(m, "ARTWORK", P.sage, 1)
    m.fill:SetPoint("TOPLEFT", 2, -2); m.fill:SetPoint("BOTTOMLEFT", 2, 2)
    m.shade = L.Solid(m, "OVERLAY", { 0, 0, 0 }, 0.26)
    m.shade:SetDrawLayer("OVERLAY", 1)
    m.shade:SetPoint("BOTTOMLEFT", m.fill, "BOTTOMLEFT", 0, 0); m.shade:SetPoint("BOTTOMRIGHT", m.fill, "BOTTOMRIGHT", 0, 0)
    m.shade:SetHeight(math.max(1, math.floor((h - 4) * 0.45)))
    m.shine = L.Solid(m, "OVERLAY", { 1, 1, 1 }, 0.30)
    m.shine:SetDrawLayer("OVERLAY", 2)
    m.shine:SetPoint("TOPLEFT", m.fill, "TOPLEFT", 0, 0); m.shine:SetPoint("TOPRIGHT", m.fill, "TOPRIGHT", 0, 0); m.shine:SetHeight(1)
    m.cap = L.Solid(m, "OVERLAY", { 1, 1, 1 }, 0.38)
    m.cap:SetDrawLayer("OVERLAY", 2)
    m.cap:SetPoint("TOPRIGHT", m.fill, "TOPRIGHT", 0, 0); m.cap:SetPoint("BOTTOMRIGHT", m.fill, "BOTTOMRIGHT", 0, 0); m.cap:SetWidth(1)
    m.parts = { m.fill, m.shade, m.shine, m.cap }
    m.frac = 0
    function m:SetFraction(f)
        f = math.max(0, math.min(1, tonumber(f) or 0))
        self.frac = f
        local room = math.max(1, (self:GetWidth() or w) - 4)
        local px = math.floor(room * f + 0.5)
        if f > 0 and px < 3 then px = 3 end
        self.px = px
        for _, t in ipairs(self.parts) do t:SetShown(px > 0) end
        if px > 0 then self.fill:SetWidth(px) end
    end
    function m:SetTone(c) self.fill:SetColorTexture(c[1], c[2], c[3], 1) end
    m:HookScript("OnSizeChanged", function(self) self:SetFraction(self.frac) end)
    m:SetFraction(0)
    return m
end

---------------------------------------------------------------------------
-- A summary card: a drawn mark, a small label and a large value, on a leather face with a tint and a thin accent line in the result's tone.
-- :Set(value, tone, note) paints it (note: a short line under the label; empty for none).
---------------------------------------------------------------------------
function K.Card(parent, w, h, glyph, label)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(w, h)
    K.Panel(card, "card")
    card.tint = L.Solid(card, "ARTWORK", P.text, 0)
    card.tint:SetDrawLayer("ARTWORK", 2)
    card.tint:SetPoint("TOPLEFT", 3, -3); card.tint:SetPoint("BOTTOMRIGHT", -3, 3)
    card.accent = L.Solid(card, "OVERLAY", P.text, 0)
    card.accent:SetHeight(2)
    card.accent:SetPoint("BOTTOMLEFT", 6, 4); card.accent:SetPoint("BOTTOMRIGHT", -6, 4)
    card.glyph = K.Glyph(card, glyph, 26, P.text)
    card.glyph:SetPoint("LEFT", 14, 0)
    card.label = K.Text(card, 14, P.textDim)
    card.label:SetPoint("TOPLEFT", card.glyph, "TOPRIGHT", 12, 5)
    card.label:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.label:SetText(label)
    card.value = K.Text(card, 28, P.text, "serif")
    card.value:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -1)
    card.value:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.baseLabel, card.longLabel = label, label
    -- a narrow card (a small window) drops its mark and uses the short label, so nothing is cut
    function card:SetCompact(on, short)
        on = on and true or false
        if self.compact == on then return end
        self.compact = on
        self.baseLabel = on and (short or self.longLabel) or self.longLabel
        self.glyph:SetShown(not on and not self.art)   -- a card with painted art (Passed, Failed) draws that instead of the shape
        if self.art then self.art:SetShown(not on) end
        self.label:ClearAllPoints()
        if on then self.label:SetPoint("TOPLEFT", self, "TOPLEFT", 12, -12) else self.label:SetPoint("TOPLEFT", self.glyph, "TOPRIGHT", 12, 5) end
        self.label:SetPoint("RIGHT", self, "RIGHT", -6, 0)
        self.sigNote = nil
        self.label:SetText(self.baseLabel)
    end
    function card:Set(value, tone, note, lit)
        local c = tone or P.stone
        self.value:SetText(value)
        K.Paint(self.value, lit and c or P.text)
        K.Paint(self.label, P.textDim)
        self.label:SetText(note and note ~= "" and (self.baseLabel .. " (" .. note .. ")") or self.baseLabel)
        self.glyph:SetColor(c, lit and 1 or 0.7)
        self.tint:SetColorTexture(c[1], c[2], c[3], lit and 0.10 or 0)
        self.accent:SetColorTexture(c[1], c[2], c[3], lit and 0.55 or 0)
    end
    card:Set("-", P.stone, nil, false)
    return card
end
