-- TwichUI Workshop: the window's presentation helpers (W.UI)
-- The approved settings look, drawn through the core's shared pieces (R.CraftLook, R.Look, R.FrameLook), so the Workshop looks like the
-- settings window's family without that addon being loaded. Nothing here reads or writes saved data, registers an event or runs per frame;
-- every helper makes its textures once, when the window is built. The views (View*.lua) register themselves in UI.pages; Window.lua builds
-- the shell and calls them.
--
--   UI.Text(parent, size, color, role)      a native font string in the crafted fonts (role "serif" / "strong"; see CraftLook.Font)
--   UI.Panel(frame, kind)                   a card ("card"), editor ("editor"), well ("canvas") or dark ("espresso") surface
--   UI.Button(parent, label, w, kind, onClick, h)   a painted button: kind "secondary", "primary" (the gold confirmation) or "danger"
--   UI.Switch(parent, label, onClick)       the switch with its label on the left (b:SetOn(bool); b.on); the label is part of its hit area
--   UI.Segment(parent, label, w, onClick)   a tab / filter segment (b:SetOn(bool), b.on)
--   UI.Search(parent, w, h, placeholder)    a search field (box.hint)
--   UI.List(parent, rowH, make, minH)       a pooled scrolling list: only the rows that can show exist; :SetData(rows, emptyText)
--   UI.ItemIcon(parent, size)               an item picture in a thin bronze frame (.tex)
--   UI.Art(texture, id, size)               feature artwork (an Icons id, or "npc:<name>" for the vendor/trainer paintings)
--   UI.Rule(parent)                         a quiet divider line
--   UI.Hover(row)                           a row's painted hover and selection (row:SetSelected(bool))
--   UI.Chevron(parent)                      a "›" in the heading font
--   UI.Triangle(parent, w)                  a small solid triangle (:SetDirection("up"|"down"), :SetColor(c, a)); no texture file
--   UI.SortHead(parent, text, w, onClick)   a sortable column heading: :SetSort(active, desc) draws the direction, gold when it is the sort
--   UI.ArtButton(parent, label, art, w, kind, onClick, h)   a button with painted artwork ("npc:hammer", an Icons id) or "plus" before its label
--   UI.Glyph(parent, "+"|"-", onClick, size)               a square button drawn with a plus or a minus (no font character)
--   UI.Meter(parent, w, h)                  a recessed progress bar (:SetFraction(0..1), :SetTone(color))
--   UI.PriceChart(parent, w, h)             a lightweight chart of observed daily prices (:Set(series, formatMoney)); only real days are drawn
--   UI.Ago(at), UI.Shorten(text, n)         "5h ago"; text cut to n characters with an ellipsis
--   UI.TipFn(frame, title, fn)              a tooltip whose text is worked out when it opens

local R = TwichUI
local W = R.Workshop
local UI = { pages = {}, order = {}, lists = {}, heads = {} }   -- lists: recipes, queue, mats, shop, opps; heads: the sortable headings
W.UI = UI

local L, K, CL, F   -- Look, its palette, CraftLook, FrameLook: looked up when the window is first built
function UI.Init()
    L, K, CL, F = R.Look, R.Look.pal, R.CraftLook, R.FrameLook
    UI.L, UI.K, UI.CL, UI.F = L, K, CL, F
end

-- The views register here in the order the navigation shows them: { key, nav, icon, title, sub, Build(page), Render(page) }
function UI.Register(def)
    UI.pages[def.key] = def
    UI.order[#UI.order + 1] = def
end

UI.ICON_BLANK = 134400   -- the game's question-mark icon, for a recipe or item whose icon isn't known yet

---------------------------------------------------------------------------
-- Text and colour
---------------------------------------------------------------------------
function UI.Paint(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

function UI.Text(parent, size, color, role, layer)
    local fs = L.Text(parent, "body", layer)
    CL.Font(fs, size or 14, false, role)
    UI.Paint(fs, color or K.text)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    return fs
end

function UI.Money(copper)
    if type(copper) ~= "number" then return "" end
    local neg = copper < 0
    local n = neg and -copper or copper
    local text = type(GetMoneyString) == "function" and GetMoneyString(n, true, nil, true) or (tostring(n) .. "c")
    return neg and ("-" .. text) or text
end

function UI.Plural(n, one, many) return n == 1 and one or many end

-- 23439 -> "23,439"
function UI.Num(n)
    if type(n) ~= "number" then return "" end
    local text = ("%d"):format(n)
    local k
    repeat text, k = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2") until k == 0
    return text
end

---------------------------------------------------------------------------
-- Surfaces
---------------------------------------------------------------------------
function UI.Panel(frame, kind)
    return CL.PanelFace(frame, kind or "card")
end

function UI.Rule(parent, alpha)
    local t = L.Solid(parent, "ARTWORK", K.bronzeLo, alpha or 0.55)
    t:SetHeight(1)
    return t
end

-- The look of a row: a faint stripe on every other row (row:SetStripe(bool), set by the list), the painted hover with a lit rim, and the chosen
-- state (the selection sheet and a gold bar at the left edge): row:SetSelected(bool). Textures are made once, with the row.
function UI.Hover(row, corner)
    local c = corner or 8
    local stripe = L.Solid(row, "BACKGROUND", K.text, 0.028)
    stripe:SetDrawLayer("BACKGROUND", 0)
    stripe:SetPoint("TOPLEFT", 2, 0); stripe:SetPoint("BOTTOMRIGHT", -2, 0)
    stripe:Hide()
    local sel = CL.Sheet(row, "selection", { layer = "BACKGROUND", sub = 3, corner = c })
    sel:SetShown(false)
    local hot = CL.Sheet(row, "selection-hot", { layer = "BACKGROUND", sub = 2, corner = c })
    hot:SetAlpha(0)
    local rim = CL.Sheet(row, "hover-rim", { layer = "OVERLAY", sub = 2, corner = c })
    rim:SetAlpha(0)
    local bar = L.Solid(row, "ARTWORK", K.bronzeText, 0.95)
    bar:SetWidth(3)
    bar:SetPoint("TOPLEFT", 3, -6); bar:SetPoint("BOTTOMLEFT", 3, 6)
    bar:Hide()
    row.twichSel, row.twichHot, row.twichStripe = sel, hot, stripe
    row:HookScript("OnEnter", function(self) hot:SetAlpha(0.8); rim:SetAlpha(self.selected and 0.3 or 0.7) end)
    row:HookScript("OnLeave", function() hot:SetAlpha(0); rim:SetAlpha(0) end)
    row:HookScript("OnHide", function() hot:SetAlpha(0); rim:SetAlpha(0) end)
    function row:SetSelected(on) self.selected = on and true or false; sel:SetShown(self.selected); bar:SetShown(self.selected) end
    function row:SetStripe(on) stripe:SetShown(on and not self.selected and true or false); self.striped = on and true or false end
end

function UI.ItemIcon(parent, size)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetSize(size, size)
    local back = L.Solid(holder, "BACKGROUND", K.ink, 1)
    back:SetAllPoints()
    holder.tex = holder:CreateTexture(nil, "ARTWORK")
    holder.tex:SetPoint("TOPLEFT", 1, -1)
    holder.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    holder.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    -- a thin aged-bronze frame, lit along the top
    local function Edge(p1, p2, w, h, c, a)
        local e = L.Solid(holder, "OVERLAY", c, a)
        e:SetPoint(p1); e:SetPoint(p2)
        if w then e:SetWidth(w) else e:SetHeight(h) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1, K.bronzeHi, 0.85)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1, K.bronzeLo, 0.95)
    Edge("TOPLEFT", "BOTTOMLEFT", 1, nil, K.bronze, 0.9)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1, nil, K.bronze, 0.9)
    return holder
end

-- Feature artwork: an Icons id ("home", "auctionHouse", ...) or one of the vendor/trainer paintings ("npc:coins")
function UI.Art(texture, id, size)
    local npc = id:match("^npc:(.+)$")
    if npc then
        texture:SetTexture(R.PATH .. [[media\npcs\]] .. npc .. ((size or 64) <= 26 and "-small" or ""))
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end
    if R.Icons then R.Icons.Apply(texture, id, size) else texture:SetTexture(R.ICON) end
end

-- A status picture (the shared guide status icons): "done", "failed" or "current"
function UI.Status(texture, which, size)
    texture:SetTexture(R.PATH .. [[media\guides\status-]] .. which .. ((size or 16) <= 26 and "-small" or ""))
end

function UI.Chevron(parent, size)
    local t = UI.Text(parent, size or 20, K.bronzeText, "serif")
    t:SetText("\226\128\186")   -- "›"
    return t
end

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
local KIND = { secondary = nil, primary = "confirmation", danger = "danger" }

function UI.Button(parent, label, w, kind, onClick, h)
    local b = F.Button(parent, label, w, kind == "danger" and "danger" or (kind == "primary" and "primary" or "secondary"), onClick)
    b:SetHeight(h or 28)
    CL.Control(b, KIND[kind or "secondary"])
    CL.Font(b.text, (h or 28) <= 24 and 13 or 14)
    return b
end

-- A small square button drawn with a plus or a minus (bars, not a font character, so it reads the same in every font and size)
local function Bars(b, kind, size)
    local len, thick = math.max(8, math.floor(size * 0.46)), 2
    local parts = {}
    local function Bar(w, h)
        local t = L.Solid(b, "OVERLAY", K.text, 1)
        t:SetSize(w, h)
        t:SetPoint("CENTER", 0, 0)
        parts[#parts + 1] = t
    end
    if kind == "plus" then Bar(len, thick); Bar(thick, len)
    else Bar(len, thick) end
    local function Paint(on)
        local c = on and K.text or K.stone
        for _, t in ipairs(parts) do t:SetColorTexture(c[1], c[2], c[3], on and 1 or 0.55) end
    end
    local orig = b.SetEnabled
    b.SetEnabled = function(self, on) orig(self, on); Paint(on ~= false) end
    Paint(true)
    b.bars = parts
end

function UI.Glyph(parent, glyph, onClick, size)
    local b = UI.Button(parent, "", size or 24, "secondary", onClick, size or 24)
    Bars(b, glyph == "+" and "plus" or glyph == "-" and "minus" or glyph, size or 24)
    return b
end

-- A button with artwork before its label: art is an Icons id, "npc:<name>" (the painted vendor art) or "plus" (drawn with two bars)
function UI.ArtButton(parent, label, art, w, kind, onClick, h)
    local b = UI.Button(parent, label, w, kind, onClick, h)
    local hh = h or 28
    local size = math.min(24, hh - 6)
    local holder = CreateFrame("Frame", nil, b)
    holder:SetSize(size, size)
    holder:SetPoint("LEFT", 12, 0)
    holder:EnableMouse(false)
    if art == "plus" then
        local len = math.floor(size * 0.55)
        local a = L.Solid(holder, "OVERLAY", K.text, 1); a:SetSize(len, 2); a:SetPoint("CENTER")
        local v = L.Solid(holder, "OVERLAY", K.text, 1); v:SetSize(2, len); v:SetPoint("CENTER")
        b.artParts = { a, v }
    else
        local t = holder:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        UI.Art(t, art, size)
        b.art = t
    end
    b.artHolder = holder
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", holder, "RIGHT", 8, 0)   -- one horizontal anchor: the control's own painting sets the text's width
    b.text:SetJustifyH("LEFT")
    local orig = b.SetEnabled
    b.SetEnabled = function(self, on)
        orig(self, on)
        holder:SetAlpha(on == false and 0.45 or 1)
    end
    return b
end

function UI.Segment(parent, label, w, onClick)
    local b = CL.Segment(parent, label, w, onClick)
    b:SetHeight(26)
    CL.Font(b.text, 13)
    function b:SetOn(on) self.on = on and true or false; self:SetSelected(self.on) end
    return b
end

-- A switch with its label on its left; the label is inside the hit area. The caller keeps the state (b:SetOn). Clicking calls onClick(b).
function UI.Switch(parent, label, onClick)
    local b
    b = CL.Pill(parent, function() if onClick then onClick(b) end end)
    b.label = UI.Text(parent, 14, K.textDim)
    b.label:SetPoint("RIGHT", b, "LEFT", -8, 0)
    b.label:SetText(label)
    local lw = math.ceil((b.label:GetStringWidth() or 0) + 10)
    if b.SetHitRectInsets then b:SetHitRectInsets(-lw, 0, -3, -3) end
    b:HookScript("OnShow", function() b.label:Show() end)
    b:HookScript("OnHide", function() b.label:Hide() end)
    function b:SetOn(on)
        self.on = on and true or false
        self:SetChecked(self.on)
        UI.Paint(self.label, self.on and K.text or K.textDim)
    end
    b:SetOn(false)
    return b
end

function UI.Search(parent, w, h, placeholder)
    local box = L.EditBox(parent, w, h or 28)
    CL.Dress(box, "field")
    box.hint = CL.SearchDecoration(box, placeholder)
    return box
end

---------------------------------------------------------------------------
-- A scrolling list that makes only the rows it can show. The caller places list.box. minH is the height assumed until the game has
-- laid the list out (and in the tests, which have no layout); afterwards the real height decides how many rows exist.
---------------------------------------------------------------------------
function UI.List(parent, rowH, make, minH, surface)
    local box = CreateFrame("Frame", nil, parent)
    if surface ~= false then UI.Panel(box, surface or "canvas") end
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
    list.empty = UI.Text(box, 14, K.textDim)
    list.empty:SetPoint("TOPLEFT", 14, -14)
    list.empty:SetPoint("RIGHT", box, "RIGHT", -14, 0)
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
    function list:ScrollTop() sf:SetVerticalScroll(0) end
    function list:RowCount() local n = 0 for _, r in ipairs(self.rows) do if r:IsShown() then n = n + 1 end end return n end
    return list
end

-- A column heading over a list (meta text, right-aligned by default)
function UI.Head(parent, text, w, justify)
    local h = UI.Text(parent, 12, K.stone)
    h:SetWidth(w)
    h:SetJustifyH(justify or "RIGHT")
    h:SetText(text)
    return h
end

-- An item's tooltip on a button-like frame (Shift-click puts its link in the open chat box, like other item pictures)
function UI.ItemTip(btn, getItem)
    btn:SetScript("OnEnter", function(self)
        local item = getItem()
        if GameTooltip and item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, item) then GameTooltip:Hide() end
        end
    end)
    btn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    btn:SetScript("OnClick", function()
        local item = getItem()
        if not (item and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink) then return end
        local ok, _, link = pcall(C_Item.GetItemInfo, item)
        if ok and type(link) == "string" then pcall(ChatEdit_InsertLink, link) end
    end)
end

function UI.Tip(frame, title, body) R.Interact.Tip(frame, title, body) end
function UI.TipFn(frame, title, fn) R.Interact.Tip(frame, title, fn) end

---------------------------------------------------------------------------
-- Small drawn things: a triangle, sortable headings, a meter, the price chart. Every texture is made once, with its owner.
---------------------------------------------------------------------------
-- A solid triangle w units wide (odd), one texture per row; :SetDirection("up"|"down") only moves them
function UI.Triangle(parent, w, color)
    w = (w or 9) % 2 == 1 and (w or 9) or (w or 9) + 1
    local n = (w + 1) / 2
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(w, n)
    t:EnableMouse(false)
    t.rows = {}
    for i = 1, n do t.rows[i] = L.Solid(t, "OVERLAY", color or K.bronzeText, 1) end
    function t:SetDirection(dir)
        self.dir = dir
        for i, r in ipairs(self.rows) do
            local width = dir == "up" and (1 + 2 * (i - 1)) or (w - 2 * (i - 1))
            r:ClearAllPoints()
            r:SetPoint("TOP", self, "TOP", 0, -(i - 1))
            r:SetSize(width, 1)
        end
    end
    function t:SetColor(c, a)
        for _, r in ipairs(self.rows) do r:SetColorTexture(c[1], c[2], c[3], a or 1) end
    end
    t:SetDirection("down")
    return t
end

-- A column heading that sorts. Not the sort: a quiet pair of small triangles says "this can be sorted"; the sort shows one gold triangle,
-- pointing down for highest first and up for lowest first, so the state is a shape as well as a colour. h.text is the label.
function UI.SortHead(parent, text, w, onClick)
    local h = CreateFrame("Button", nil, parent)
    h:SetSize(w, 30)
    h.text = UI.Text(h, 12, K.stone)
    h.text:SetPoint("TOPLEFT", 0, 0)
    h.text:SetPoint("TOPRIGHT", 0, 0)
    h.text:SetHeight(16)
    h.text:SetJustifyH("RIGHT")
    h.text:SetText(text)
    -- an optional second line under the label (a qualification that must stay with the figure: "before fees")
    h.sub = UI.Text(h, 11, K.stone)
    h.sub:SetPoint("TOPLEFT", h.text, "BOTTOMLEFT", 0, -1)
    h.sub:SetPoint("TOPRIGHT", h.text, "BOTTOMRIGHT", 0, -1)
    h.sub:SetJustifyH("RIGHT")
    h.tri = UI.Triangle(h, 7, K.bronzeText)
    h.hintUp = UI.Triangle(h, 5, K.stone)
    h.hintDown = UI.Triangle(h, 5, K.stone)
    h.hintUp:SetDirection("up"); h.hintDown:SetDirection("down")
    h.hintUp:SetColor(K.stone, 0.5); h.hintDown:SetColor(K.stone, 0.5)
    h.label = text
    function h:SetLabel(t, sub) self.label = t; self.text:SetText(t); self.sub:SetText(sub or "") end
    -- active: this heading is the sort; desc: highest first
    function h:SetSort(active, desc)
        self.active, self.desc = active and true or false, desc and true or false
        local width = math.ceil((self.text:GetStringWidth() or 0))
        local at = -(width + 8)
        self.tri:ClearAllPoints(); self.hintUp:ClearAllPoints(); self.hintDown:ClearAllPoints()
        if self.active then
            self.tri:SetDirection(self.desc and "down" or "up")
            self.tri:SetPoint("TOPRIGHT", self, "TOPRIGHT", at, -6)
            self.tri:Show(); self.hintUp:Hide(); self.hintDown:Hide()
            UI.Paint(self.text, K.bronzeText)
        else
            self.hintUp:SetPoint("TOPRIGHT", self, "TOPRIGHT", at, -3)
            self.hintDown:SetPoint("TOPRIGHT", self, "TOPRIGHT", at, -9)
            self.tri:Hide(); self.hintUp:Show(); self.hintDown:Show()
            UI.Paint(self.text, K.stone)
        end
    end
    h:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    h:SetScript("OnEnter", function(self) if not self.active then UI.Paint(self.text, K.text) end end)
    h:HookScript("OnLeave", function(self) UI.Paint(self.text, self.active and K.bronzeText or K.stone) end)
    h:SetSort(false, true)
    return h
end

-- A recessed progress bar. frac 0..1; the fill is a flat tone with a lit top line (a gradient is not relied on)
function UI.Meter(parent, w, h)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(w, h or 8)
    local track = L.Solid(m, "BACKGROUND", K.ink, 0.9)
    track:SetAllPoints()
    local lo = L.Solid(m, "BORDER", K.bronzeLo, 0.8); lo:SetPoint("BOTTOMLEFT"); lo:SetPoint("BOTTOMRIGHT"); lo:SetHeight(1)
    local top = L.Solid(m, "BORDER", K.ink, 1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    m.fill = L.Solid(m, "ARTWORK", K.sage, 1)
    m.fill:SetPoint("TOPLEFT", 1, -1); m.fill:SetPoint("BOTTOMLEFT", 1, 1)
    m.shine = L.Solid(m, "OVERLAY", { 1, 1, 1 }, 0.22)
    m.shine:SetPoint("TOPLEFT", m.fill, "TOPLEFT", 0, 0); m.shine:SetPoint("TOPRIGHT", m.fill, "TOPRIGHT", 0, 0); m.shine:SetHeight(1)
    m.frac = 0
    function m:SetFraction(f)
        f = math.max(0, math.min(1, tonumber(f) or 0))
        self.frac = f
        local inner = math.max(1, (self:GetWidth() or w) - 2)
        local px = math.floor(inner * f + 0.5)
        self.fill:SetShown(px > 0)
        self.shine:SetShown(px > 0)
        if px > 0 then self.fill:SetWidth(px) end
    end
    function m:SetTone(c) self.fill:SetColorTexture(c[1], c[2], c[3], 1) end
    m:HookScript("OnSizeChanged", function(self) self:SetFraction(self.frac) end)
    m:SetFraction(0)
    return m
end

function UI.Ago(at)
    local age = W.Prices.Age(at)
    if not age then return "" end
    if age < 60 then return "just now" end
    if age < 3600 then return ("%dm ago"):format(math.floor(age / 60)) end
    if age < 86400 then return ("%dh ago"):format(math.floor(age / 3600)) end
    return ("%dd ago"):format(math.floor(age / 86400))
end

-- Cuts text to n characters (never inside a multi-byte character) and adds an ellipsis; the whole text belongs in a tooltip
function UI.Shorten(text, n)
    if type(text) ~= "string" or #text <= n then return text end
    local cut = text:sub(1, n - 1)
    local i = #cut
    while i > 0 and cut:byte(i) >= 0x80 and cut:byte(i) < 0xC0 do i = i - 1 end
    if i > 0 and cut:byte(i) >= 0xC0 then cut = cut:sub(1, i - 1) end
    return cut:gsub("%s+$", "") .. "\226\128\166"
end

-- The price chart: the observed days of one item as dots (a stem to the floor of the plot), placed by their real day number, so a day with
-- no scan is a gap and nothing joins two days. Draws only what Market.Series holds (the last observed days; older groups are named in the
-- caption, not drawn). chart:Set(series, money) where series is Market.Series' answer or nil. Textures are made once (MAX dots).
local MAX_DOTS = 8
function UI.PriceChart(parent, w, h)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(w, h)
    UI.Panel(c, "canvas")
    c.plot = CreateFrame("Frame", nil, c)
    c.plot:SetPoint("TOPLEFT", 10, -10)
    c.plot:SetPoint("BOTTOMRIGHT", -74, 10)
    c.guides = {}
    for i = 1, 3 do
        local g = L.Solid(c.plot, "BACKGROUND", K.bronzeLo, 0.30)
        g:SetHeight(1)
        g:SetPoint("LEFT", c.plot, "BOTTOMLEFT", 0, 0); g:SetPoint("RIGHT", c.plot, "BOTTOMRIGHT", 0, 0)
        c.guides[i] = g
    end
    c.dots, c.stems = {}, {}
    for i = 1, MAX_DOTS do
        c.stems[i] = L.Solid(c.plot, "ARTWORK", K.tealLo, 0.9)
        c.stems[i]:SetWidth(2)
        c.dots[i] = L.Solid(c.plot, "OVERLAY", K.bronzeText, 1)
        c.dots[i]:SetSize(7, 7)
    end
    c.hi = UI.Text(c, 11, K.textDim)
    c.hi:SetPoint("TOPRIGHT", -8, -8); c.hi:SetWidth(62); c.hi:SetJustifyH("RIGHT")
    c.lo = UI.Text(c, 11, K.textDim)
    c.lo:SetPoint("BOTTOMRIGHT", -8, 8); c.lo:SetWidth(62); c.lo:SetJustifyH("RIGHT")
    c.msg = UI.Text(c, 12, K.textDim)
    c.msg:SetPoint("TOPLEFT", 12, -10); c.msg:SetPoint("BOTTOMRIGHT", -12, 10)
    c.msg:SetWordWrap(true); c.msg:SetJustifyH("CENTER"); c.msg:SetJustifyV("MIDDLE")
    function c:Set(series, money)
        local pts = series and series.points or {}
        local n = math.min(#pts, MAX_DOTS)
        local first = #pts - n + 1
        for i = 1, MAX_DOTS do self.dots[i]:Hide(); self.stems[i]:Hide() end
        for _, g in ipairs(self.guides) do g:Hide() end
        self.shown = n
        if n == 0 then
            self.hi:SetText(""); self.lo:SetText("")
            self.msg:SetText(series and "Older prices are kept only as ranges, so there is no recent day to draw." or "No price history for this item yet.")
            self.msg:Show()
            return
        end
        if n == 1 then
            local d = self.dots[1]
            d:ClearAllPoints(); d:SetPoint("CENTER", self.plot, "CENTER", 0, 8); d:Show()
            self.hi:SetText(money(pts[first].price)); self.lo:SetText("")
            self.msg:SetText("One day observed")
            self.msg:ClearAllPoints()
            self.msg:SetPoint("BOTTOMLEFT", 10, 5); self.msg:SetPoint("BOTTOMRIGHT", -74, 5); self.msg:SetHeight(14)
            self.msg:SetWordWrap(false)
            self.msg:Show()
            return
        end
        self.msg:Hide()
        self.msg:ClearAllPoints()
        self.msg:SetPoint("TOPLEFT", 12, -10); self.msg:SetPoint("BOTTOMRIGHT", -12, 10)
        self.msg:SetWordWrap(true)
        local lo, hi, day0, day1
        for i = first, #pts do
            local p = pts[i]
            if not lo or p.price < lo then lo = p.price end
            if not hi or p.price > hi then hi = p.price end
        end
        day0, day1 = pts[first].day, pts[#pts].day
        local span = math.max(1, day1 - day0)
        local pw, ph = (self.plot:GetWidth() or 0), (self.plot:GetHeight() or 0)
        if pw < 20 then pw = (w or 260) - 84 end
        if ph < 10 then ph = (h or 70) - 20 end
        local pad = (hi - lo) * 0.12
        local floorV, ceil = math.max(0, lo - pad), hi + pad
        if hi == lo then floorV, ceil = lo * 0.9, lo * 1.1 end
        for i = 0, n - 1 do
            local p = pts[first + i]
            local x = 4 + (pw - 8) * ((p.day - day0) / span)
            local y = 3 + (ph - 8) * ((p.price - floorV) / math.max(1, ceil - floorV))
            local d, st = self.dots[i + 1], self.stems[i + 1]
            d:ClearAllPoints(); d:SetPoint("CENTER", self.plot, "BOTTOMLEFT", x, y)
            st:ClearAllPoints(); st:SetPoint("BOTTOM", self.plot, "BOTTOMLEFT", x, 0); st:SetHeight(math.max(1, y - 3))
            local newest = i == n - 1
            d:SetSize(newest and 9 or 7, newest and 9 or 7)
            d:SetColorTexture((newest and K.tealHi or K.bronzeText)[1], (newest and K.tealHi or K.bronzeText)[2], (newest and K.tealHi or K.bronzeText)[3], 1)
            d:Show(); st:Show()
        end
        for i, g in ipairs(self.guides) do
            g:ClearAllPoints()
            g:SetPoint("LEFT", self.plot, "BOTTOMLEFT", 0, (i) * ph / 4); g:SetPoint("RIGHT", self.plot, "BOTTOMRIGHT", 0, (i) * ph / 4)
            g:Show()
        end
        self.hi:SetText(money(hi)); self.lo:SetText(money(lo))
    end
    return c
end
