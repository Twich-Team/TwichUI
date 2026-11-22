-- TwichUI Fishing: the Fishing Journal window and the session-completion summary (Stage 3A)
-- Draws what Journal.lua answers, in the pack's walnut-and-bronze frames (journal_frame, recessed_frame, rows and buttons cut
-- with H.Slice), with the game's own item icons and names. A page draws and nothing more: it asks Journal.lua for its answer
-- (cached until the records change), keeps a fixed pool of rows however long a list is, and scrolls them with the wheel.
-- Nothing here reads or writes a saved variable, loads Workshop, or shows a price; every row and stat carries an `extra`
-- list that is simply not drawn yet, so Stage 3B can add figures without moving a layout (see Cell and Rows below).
--
--   U.Open(page)    open the Journal (page: "overview" | "sessions" | "collections" | "locations" | "treasures")
--   U.Close(), U.Toggle(page), U.Shown(), U.Page()
--   U.Select(page, id)   go to a page with a session / item / container selected
--   U.Summary(id)   the session-completion card for a finished session (U.CloseSummary())
--   U.Frame()       the window (tests, captures)
--
-- Layout is in units at scale 1 (config journal.scale 0.6-1.4): window 780 x 540; navigation left, the page right.

local R = TwichUI
local F = R.Fishing
local S = F.Store
local H = F.Hud
local J = F.Journal
local U = {}
F.JournalUI = U

U.W, U.H = 780, 540
U.PAGES = { "overview", "sessions", "collections", "locations", "treasures" }
U.LABEL = { overview = "Overview", sessions = "Sessions", collections = "Collections", locations = "Locations", treasures = "Treasures" }
U.GLYPH = { overview = "mark", sessions = "glyph-time", collections = "glyph-hook", locations = "glyph-lure", treasures = "glyph-treasure" }
U.GRID_COLS, U.GRID_ROWS = 7, 3
U.FRAME_CUT = 54     -- the frame's corner ornaments reach about 52 painted pixels along each edge

local win, pages, nav, current = nil, {}, {}, "overview"
local state = { session = nil, species = nil, container = nil, sort = "count", gridPage = 1 }
local SORTS = { "count", "recent", "first", "name" }
local SORT_LABEL = { count = "Most caught", recent = "Latest catch", first = "First caught", name = "Name" }

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
local function Num(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end
U.Num = Num

local function Day(t) return t and date("%b %d, %Y", t) or nil end
local function Clock(t) return t and date("%b %d, %H:%M", t) or nil end
local function Percent(p) return p and ("%.1f%%"):format(p) or "—" end
local function Plural(n, one, many) return ("%s %s"):format(Num(n), n == 1 and one or (many or one .. "s")) end
U.Day, U.Clock, U.Percent = Day, Clock, Percent

local function ItemName(id)
    local name = H.Item(id)
    return name or ("Item " .. id)
end

local function Text(parent, size, role, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    H.Font(fs, size, role)
    H.Color(fs, color or H.IVORY)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Place(obj, point, rel, relPoint, x, y)
    obj:ClearAllPoints()
    obj:SetPoint(point, rel, relPoint, x or 0, y or 0)
end

local function Tip(frame, id)
    frame:HookScript("OnEnter", function(self)
        if id and GameTooltip and GameTooltip.SetOwner and self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
            GameTooltip:Show()
        end
    end)
    frame:HookScript("OnLeave", function(self)
        if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    end)
end

local function Heading(parent, text, x, y, width)
    local fs = Text(parent, 16, "serif", H.GOLD)
    Place(fs, "TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    Place(rule, "TOPLEFT", parent, "TOPLEFT", x, y - 22)
    rule:SetSize(width or 200, 10)
    H.Texture(rule, "rule", { 0.62, 0.45, 0.24, 0.4 })
    rule:SetAlpha(0.8)
    fs.rule = rule
    return fs
end

-- A bronze button from the pack (j-btn), text centred.
local function Button(parent, label, width, height, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.bg = H.Slice(b, "j-btn", 12, "BACKGROUND")
    b.text = Text(b, 13, "strong", H.IVORY, "CENTER")
    b.text:SetAllPoints()
    b.text:SetText(label)
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.92, 0.7, 1) end)
    b:SetScript("OnLeave", function(self) H.Color(self.text, H.IVORY) end)
    b:SetScript("OnClick", function() if onClick then onClick() end end)
    return b
end

---------------------------------------------------------------------------
-- A scrolling list with a fixed pool of rows (the cost of a page doesn't grow with the history)
--   o.rows rows of o.h units, o.width wide; o.make(button) builds a row's parts once; o.fill(button, item, index) draws one;
--   o.click(item, index); L:SetItems(items), L:Select(match), L:Refresh(), L:Scroll(delta), L.items, L.offset, L.buttons
---------------------------------------------------------------------------
local function List(parent, o)
    local L = { items = {}, offset = 0, buttons = {}, o = o }
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(o.width, o.rows * o.h)
    frame:EnableMouse(true)
    frame:EnableMouseWheel(true)
    L.frame = frame
    local bar = o.rows > 1
    L.track = frame:CreateTexture(nil, "ARTWORK")
    L.thumb = frame:CreateTexture(nil, "OVERLAY")
    if bar then
        Place(L.track, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        L.track:SetSize(5, o.rows * o.h)
        L.track:SetColorTexture(0.05, 0.03, 0.02, 0.55)
        L.thumb:SetSize(5, 24)
        L.thumb:SetColorTexture(0.84, 0.62, 0.28, 0.9)
    end
    local function Look(btn)
        local on = btn.selected
        btn.bg:SetArt(on and (o.art and o.art .. "-on" or "j-row-on") or (btn.hovered and (o.art and o.art .. "-hover" or "j-row-hover") or (o.art or "j-row")))
        btn.bg:SetVertexColor(1, 1, 1, (on or btn.hovered) and 1 or (o.plain and 0.0 or 0.9))
    end
    for i = 1, o.rows do
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(o.width - (bar and 9 or 0), o.h - (o.gap or 3))
        Place(b, "TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * o.h)
        b.bg = H.Slice(b, "j-row", 10, "BACKGROUND")
        b.look = Look
        b:SetScript("OnEnter", function(self) self.hovered = true; Look(self) end)
        b:SetScript("OnLeave", function(self) self.hovered = false; Look(self) end)
        b:SetScript("OnClick", function(self) if self.item and o.click then o.click(self.item, self.index) end end)
        b:EnableMouseWheel(true)
        b:SetScript("OnMouseWheel", function(_, d) L:Scroll(-d) end)
        o.make(b)
        L.buttons[i] = b
    end
    function L:Max() return math.max(0, #self.items - o.rows) end
    function L:Refresh()
        local max = self:Max()
        if self.offset > max then self.offset = max end
        if self.offset < 0 then self.offset = 0 end
        for i, b in ipairs(self.buttons) do
            local item = self.items[self.offset + i]
            b.item, b.index = item, self.offset + i
            if item then
                b:Show()
                b.selected = o.selected and o.selected(item) or false
                Look(b)
                o.fill(b, item, self.offset + i)
            else
                b:Hide()
            end
        end
        if bar then
            local n = #self.items
            local show = n > o.rows
            self.thumb:SetShown(show)
            self.track:SetShown(show)
            if show then
                local h = math.max(18, o.rows * o.h * o.rows / n)
                self.thumb:SetHeight(h)
                local travel = o.rows * o.h - h
                Place(self.thumb, "TOPRIGHT", frame, "TOPRIGHT", 0, -travel * (max > 0 and self.offset / max or 0))
            end
        end
    end
    function L:SetItems(items, keep)
        self.items = items or {}
        if not keep then self.offset = 0 end
        self:Refresh()
    end
    function L:Scroll(d)
        local before = self.offset
        self.offset = math.max(0, math.min(self:Max(), self.offset + d))
        if self.offset ~= before then self:Refresh() end
    end
    function L:ShowIndex(i)
        if i < self.offset + 1 then self.offset = i - 1 elseif i > self.offset + o.rows then self.offset = i - o.rows end
        self:Refresh()
    end
    frame:SetScript("OnMouseWheel", function(_, d) L:Scroll(-d) end)
    return L
end

-- One stat: a glyph over a value over a label, in cells of equal width across `width`. cells = { { glyph, value, label } ... }
-- (Stage 3B appends its own cells to the list; the strip divides its width by however many there are.)
local function Strip(parent, y, width, height, count)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(width, height)
    Place(strip, "TOPLEFT", parent, "TOPLEFT", 0, y)
    strip.bg = H.Slice(strip, "j-row", 10, "BACKGROUND")
    strip.bg:SetVertexColor(1, 1, 1, 0.8)
    strip.cells, strip.seps = {}, {}
    function strip:SetCells(cells)
        local n = math.max(1, #cells)
        local w = width / n
        for i = 1, math.max(n, #self.cells) do
            local c = self.cells[i]
            if not c then
                c = {}
                c.glyph = self:CreateTexture(nil, "ARTWORK")
                c.glyph:SetSize(26, 26)
                c.value = Text(self, 18, "serif", H.IVORY, "CENTER")
                c.label = Text(self, 12, "body", H.MUTED, "CENTER")
                self.cells[i] = c
                c.sep = self:CreateTexture(nil, "ARTWORK")
                c.sep:SetColorTexture(0.62, 0.45, 0.24, 0.35)
            end
            local d = cells[i]
            c.glyph:SetShown(d ~= nil); c.value:SetShown(d ~= nil); c.label:SetShown(d ~= nil); c.sep:SetShown(d ~= nil and i > 1)
            if d then
                local cx = (i - 0.5) * w
                c.glyph:ClearAllPoints(); c.glyph:SetPoint("TOP", self, "TOPLEFT", cx, -7)
                if d.glyph and H.ART[d.glyph] then H.Texture(c.glyph, d.glyph) c.glyph:Show() else c.glyph:Hide() end
                c.value:ClearAllPoints(); c.value:SetPoint("TOP", self, "TOPLEFT", cx, -35)
                c.value:SetWidth(w - 8); c.value:SetText(d.value)
                c.label:ClearAllPoints(); c.label:SetPoint("TOP", self, "TOPLEFT", cx, -59)
                c.label:SetWidth(w - 8); c.label:SetText(d.label)
                c.sep:ClearAllPoints(); c.sep:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * w, -12)
                c.sep:SetSize(1, height - 24)
            end
        end
    end
    return strip
end

-- A framed game icon (the notification's bronze frame) with the quantity on its corner.
local function Icon(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.frame, f.icon = H.FramedIcon(f, size, "ARTWORK")
    f.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.qty = Text(f, math.max(10, math.floor(size * 0.2)), "strong", H.IVORY, "RIGHT")
    f.qty:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    f.qty:SetDrawLayer("OVERLAY", 7)
    function f:Set(id, qty)
        local _, tex = H.Item(id)
        self.icon:SetTexture(tex)
        self.itemID = id
        self.qty:SetText(qty and qty > 1 and Num(qty) or "")
    end
    return f
end

local function Empty(parent, title, body)
    local e = CreateFrame("Frame", nil, parent)
    e:SetAllPoints()
    e.mark = e:CreateTexture(nil, "ARTWORK")
    e.mark:SetSize(160, 124)
    e.mark:SetPoint("CENTER", e, "CENTER", 0, 36)
    H.Texture(e.mark, "j-mark")
    e.mark:SetAlpha(0.75)
    e.title = Text(e, 17, "serif", H.GOLD, "CENTER")
    e.title:SetPoint("TOP", e.mark, "BOTTOM", 0, -8)
    e.title:SetWidth(400); e.title:SetText(title)
    e.body = Text(e, 13, "body", H.MUTED, "CENTER")
    e.body:SetWordWrap(true)
    e.body:SetPoint("TOP", e.title, "BOTTOM", 0, -6)
    e.body:SetWidth(400); e.body:SetText(body)
    e:Hide()
    return e
end

local function Note(parent, y, width)
    local fs = Text(parent, 11, "body", H.MUTED, "LEFT")
    fs:SetWordWrap(true)
    Place(fs, "BOTTOMLEFT", parent, "BOTTOMLEFT", 0, y or 0)
    fs:SetWidth(width)
    return fs
end

local function RetentionNote(r)
    if not r then return "" end
    if r.held then return "Your fishing records were saved by a newer TwichUI and are kept unchanged: nothing can be shown." end
    local s = ("Per-session records are kept for your newest %s (up to %s)."):format(Plural(r.kept, "session"), Num(r.limit))
    if r.older > 0 then
        s = s .. (" %s earlier %s only in the totals."):format(Num(r.older), r.older == 1 and "session is" or "sessions are")
    end
    return s
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------
local function BuildOverview(page)
    local P = { frame = page }
    local W = U.W - 244
    P.title = Text(page, 19, "serif", H.IVORY)
    Place(P.title, "TOPLEFT", page, "TOPLEFT", 0, 0)
    P.title:SetText("Fishing Overview")
    P.scope = Text(page, 12, "body", H.MUTED, "RIGHT")
    Place(P.scope, "TOPRIGHT", page, "TOPRIGHT", 0, -4)
    P.strip = Strip(page, -32, W, 84)
    P.h1 = Heading(page, "Favorite Catches", 0, -124, W)
    P.fav = {}
    local cw = W / J.TOP
    for i = 1, J.TOP do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(cw - 8, 54)
        Place(b, "TOPLEFT", page, "TOPLEFT", (i - 1) * cw, -152)
        b.icon = Icon(b, 46)
        b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)
        b.name = Text(b, 13, "strong", H.IVORY)
        b.name:SetWordWrap(true)
        b.name:SetHeight(32)
        b.name:SetJustifyV("TOP")
        b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 54, -2)
        b.name:SetWidth(cw - 68)
        b.count = Text(b, 12, "body", H.AMBERTEXT)
        b.count:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 54, 2)
        b.count:SetWidth(cw - 68)
        b:SetScript("OnClick", function(self) if self.id then U.Select("collections", self.id) end end)
        Tip(b, true)
        P.fav[i] = b
    end
    P.h2 = Heading(page, "Recent Sessions", 0, -214, W)
    P.viewAll = Button(page, "View all", 76, 22, function() U.Show("sessions") end)
    Place(P.viewAll, "TOPRIGHT", page, "TOPRIGHT", 0, -212)
    P.rows = List(page, {
        rows = J.RECENT, h = 52, width = W, art = "j-row",
        make = function(b)
            b.zone = Text(b, 14, "strong", H.IVORY)
            b.zone:SetPoint("TOPLEFT", b, "TOPLEFT", 14, -8)
            b.zone:SetWidth(300)
            b.sub = Text(b, 12, "body", H.MUTED)
            b.sub:SetPoint("TOPLEFT", b.zone, "BOTTOMLEFT", 0, -2)
            b.sub:SetWidth(300)
            b.when = Text(b, 12, "body", H.AMBERTEXT, "RIGHT")
            b.when:SetPoint("RIGHT", b, "RIGHT", -14, 0)
            b.when:SetWidth(150)
        end,
        fill = function(b, r)
            b.zone:SetText(r.zoneName)
            b.sub:SetText(("%s · %s"):format(Plural(r.catches, "catch", "catches"), H.Duration(r.seconds)))
            b.when:SetText(Day(r.start) or "")
        end,
        click = function(r) U.Select("sessions", r.id) end,
    })
    Place(P.rows.frame, "TOPLEFT", page, "TOPLEFT", 0, -240)
    P.note = Note(page, 0, W)
    P.empty = Empty(page, "Nothing fished yet", "Cast a line with your Fishing key. Your catches, sessions and places will gather here.")
    function P.Refresh()
        local o = J.Overview()
        P.empty:SetShown(false)
        if not o.available then
            P.empty.title:SetText("No fishing records")
            P.empty.body:SetText(o.retention.held and "Your fishing records were saved by a newer TwichUI and are kept unchanged."
                or "The fishing records are not available yet.")
            P.empty:Show()
        elseif o.lifetime.casts == 0 and o.lifetime.catches == 0 then
            P.empty.title:SetText("Nothing fished yet")
            P.empty.body:SetText("Cast a line with your Fishing key. Your catches, sessions and places will gather here.")
            P.empty:Show()
        end
        local blank = P.empty:IsShown()
        for _, w in ipairs({ P.strip, P.viewAll, P.rows.frame, P.note, P.h1, P.h1.rule, P.h2, P.h2.rule, P.scope }) do w:SetShown(not blank) end
        for _, b in ipairs(P.fav) do b:SetShown(not blank) end
        if blank then return end
        local L = o.lifetime
        P.scope:SetText(("All time · %s%s"):format(Plural(L.sessions, "session"), L.first and (" · since " .. Day(L.first)) or ""))
        local cells = {
            { glyph = "mark", value = Num(L.items), label = "Fish caught" },
            { glyph = "glyph-lure", value = Num(L.casts), label = "Casts" },
            { glyph = "glyph-time", value = H.Duration(L.seconds), label = "Time fishing" },
            { glyph = "glyph-hook", value = Percent(o.rate), label = "Catch rate" },
        }
        for _, x in ipairs(o.extra) do cells[#cells + 1] = x end
        P.strip:SetCells(cells)
        for i, b in ipairs(P.fav) do
            local e = o.favorites[i]
            b.id = e and e.id
            b:SetShown(e ~= nil)
            if e then
                b.icon:Set(e.id, nil)
                b.itemID = e.id
                b.name:SetText(ItemName(e.id))
                b.count:SetText(("×%s caught"):format(Num(e.q)))
            end
        end
        P.rows:SetItems(o.recent)
        P.rows.frame:SetShown(#o.recent > 0)
        P.note:SetText(RetentionNote(o.retention))
    end
    return P
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
local function BuildSessions(page)
    local P = { frame = page }
    P.title = Text(page, 19, "serif", H.IVORY)
    Place(P.title, "TOPLEFT", page, "TOPLEFT", 0, 0)
    P.title:SetText("Sessions")
    P.count = Text(page, 12, "body", H.MUTED, "RIGHT")
    Place(P.count, "TOPLEFT", page, "TOPLEFT", 0, -6)
    P.count:SetWidth(232)
    P.list = List(page, {
        rows = 7, h = 50, width = 236,
        selected = function(r) return r.id == state.session end,
        make = function(b)
            b.zone = Text(b, 13, "strong", H.IVORY)
            b.zone:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -8)
            b.zone:SetWidth(150)
            b.sub = Text(b, 11, "body", H.MUTED)
            b.sub:SetPoint("TOPLEFT", b.zone, "BOTTOMLEFT", 0, -2)
            b.sub:SetWidth(170)
            b.catch = Text(b, 13, "strong", H.AMBERTEXT, "RIGHT")
            b.catch:SetPoint("TOPRIGHT", b, "TOPRIGHT", -14, -8)
            b.catch:SetWidth(60)
            b.live = Text(b, 10, "strong", H.GOLD, "RIGHT")
            b.live:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -14, 7)
            b.live:SetWidth(60)
        end,
        fill = function(b, r)
            b.zone:SetText(r.zoneName)
            b.sub:SetText(("%s · %s"):format(Clock(r.start) or "", H.Duration(r.seconds)))
            b.catch:SetText(Num(r.catches))
            b.live:SetText(r.current and "In progress" or "")
        end,
        click = function(r) state.session = r.id; P.Refresh() end,
    })
    Place(P.list.frame, "TOPLEFT", page, "TOPLEFT", 0, -30)
    local D = CreateFrame("Frame", nil, page)
    D:SetSize(284, 380)
    Place(D, "TOPLEFT", page, "TOPLEFT", 256, 0)
    P.D = D
    D.zone = Text(D, 18, "serif", H.IVORY)
    Place(D.zone, "TOPLEFT", D, "TOPLEFT", 0, 0)
    D.zone:SetWidth(284)
    D.when = Text(D, 12, "body", H.MUTED)
    Place(D.when, "TOPLEFT", D, "TOPLEFT", 0, -26)
    D.when:SetWidth(284)
    D.cells = {}
    local labels = { "Casts", "Catches", "Items", "Catch rate", "Time on the line", "Missed lines" }
    for i, label in ipairs(labels) do
        local c = CreateFrame("Frame", nil, D)
        c:SetSize(92, 38)
        Place(c, "TOPLEFT", D, "TOPLEFT", ((i - 1) % 3) * 96, -50 - math.floor((i - 1) / 3) * 42)
        c.bg = H.Slice(c, "j-row", 10, "BACKGROUND")
        c.bg:SetVertexColor(1, 1, 1, 0.8)
        c.value = Text(c, 15, "strong", H.IVORY, "CENTER")
        c.value:SetPoint("TOP", c, "TOP", 0, -5)
        c.value:SetWidth(88)
        c.label = Text(c, 10, "body", H.MUTED, "CENTER")
        c.label:SetPoint("BOTTOM", c, "BOTTOM", 0, 4)
        c.label:SetWidth(88)
        c.label:SetText(label)
        D.cells[i] = c
    end
    Heading(D, "Catches", 0, -140, 284)
    P.species = List(D, {
        rows = 5, h = 36, width = 284,
        make = function(b)
            b.icon = Icon(b, 28)
            b.icon:SetPoint("LEFT", b, "LEFT", 6, 0)
            b.name = Text(b, 13, "strong", H.IVORY)
            b.name:SetPoint("LEFT", b, "LEFT", 42, 0)
            b.name:SetWidth(170)
            b.q = Text(b, 14, "strong", H.AMBERTEXT, "RIGHT")
            b.q:SetPoint("RIGHT", b, "RIGHT", -16, 0)
            b.q:SetWidth(60)
            Tip(b, true)
        end,
        fill = function(b, e)
            b.icon:Set(e.id)
            b.itemID = e.id
            b.name:SetText(ItemName(e.id))
            b.q:SetText("×" .. Num(e.q))
        end,
    })
    Place(P.species.frame, "TOPLEFT", D, "TOPLEFT", 0, -168)
    D.treasure = Text(D, 12, "body", H.AMBERTEXT)
    D.treasure:SetWordWrap(true)
    Place(D.treasure, "TOPLEFT", D, "TOPLEFT", 0, -354)
    D.treasure:SetWidth(284)
    D.none = Text(D, 14, "body", H.MUTED, "CENTER")
    D.none:SetPoint("CENTER", D, "CENTER", 0, 0)
    D.none:SetWidth(240)
    D.none:SetWordWrap(true)
    P.note = Note(page, 0, 540)
    P.empty = Empty(page, "No sessions yet", "A session begins with your first cast and ends when you stop or fall idle.")
    function P.Refresh()
        local data = J.Sessions()
        local rows = data.rows
        P.empty:SetShown(#rows == 0)
        P.list.frame:SetShown(#rows > 0)
        D:SetShown(#rows > 0)
        P.note:SetText(RetentionNote(data.retention))
        P.count:SetText(Plural(#rows, "session") .. " kept")
        if #rows == 0 then return end
        local found
        for _, r in ipairs(rows) do if r.id == state.session then found = r break end end
        if not found then state.session = rows[1].id; found = rows[1] end
        P.list:SetItems(rows, true)
        for i, r in ipairs(rows) do if r.id == state.session then P.list:ShowIndex(i) break end end
        local d = J.Session(state.session)
        if not d then
            D.none:SetText("This session's record is no longer kept; its catches are in your totals.")
            D.none:Show()
            for _, c in ipairs(D.cells) do c:Hide() end
            D.zone:SetText(""); D.when:SetText(""); D.treasure:SetText("")
            P.species:SetItems({})
            return
        end
        D.none:Hide()
        local r = d.row
        D.zone:SetText(r.zoneName)
        local ended = r.current and "in progress" or (r.ended == "idle" and "ended when you went idle" or "ended by you")
        D.when:SetText(("%s · %s · %s"):format(Clock(r.start) or "", H.Duration(r.seconds), ended))
        local vals = { Num(r.casts), Num(r.catches), Num(r.items), Percent(r.rate), H.Duration(d.line), Num(r.missed) }
        for i, c in ipairs(D.cells) do c:Show(); c.value:SetText(vals[i]) end
        P.species:SetItems(d.species)
        local opened, took = 0, 0
        for _, t in ipairs(d.treasures) do opened = opened + t.opened end
        for _, q in pairs(d.contents) do took = took + q end
        D.treasure:SetText(opened > 0 and ("Opened %s and took %s from them."):format(Plural(opened, "container"), Plural(took, "item"))
            or (#d.treasures > 0 and "Containers caught: none opened this session." or ""))
        P.species.frame:SetShown(#d.species > 0)
        if #d.species == 0 then D.treasure:SetText("Nothing was caught in this session.") end
    end
    return P
end

---------------------------------------------------------------------------
-- Collections
---------------------------------------------------------------------------
local function BuildCollections(page)
    local P = { frame = page, cells = {} }
    local W = U.W - 244
    P.title = Text(page, 19, "serif", H.IVORY)
    Place(P.title, "TOPLEFT", page, "TOPLEFT", 0, 0)
    P.title:SetText("Collection")
    P.count = Text(page, 12, "body", H.MUTED)
    Place(P.count, "TOPLEFT", page, "TOPLEFT", 110, -6)
    P.count:SetWidth(240)
    P.sort = Button(page, SORT_LABEL.count, 132, 24, function()
        for i, s in ipairs(SORTS) do
            if s == state.sort then state.sort = SORTS[i % #SORTS + 1] break end
        end
        state.gridPage, state.jump = 1, nil
        P.Refresh()
    end)
    Place(P.sort, "TOPRIGHT", page, "TOPRIGHT", 0, -2)
    local cell = W / U.GRID_COLS
    for i = 1, U.GRID_COLS * U.GRID_ROWS do
        local b = CreateFrame("Button", nil, page)
        b:SetSize(cell - 6, cell - 6)
        Place(b, "TOPLEFT", page, "TOPLEFT", ((i - 1) % U.GRID_COLS) * cell, -34 - math.floor((i - 1) / U.GRID_COLS) * cell)
        b.icon = Icon(b, cell - 8)
        b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetPoint("TOPLEFT", b, "TOPLEFT", -2, 2)
        b.sel:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
        b.sel:SetColorTexture(0.96, 0.72, 0.30, 0.42)      -- the chosen kind: a warm plate behind its frame
        b.unknown = b:CreateTexture(nil, "ARTWORK", nil, 3)
        b.unknown:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
        b.unknown:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
        H.Texture(b.unknown, "j-unknown")
        b:SetScript("OnClick", function(self) if self.id then state.species = self.id; P.Refresh() end end)
        Tip(b, true)
        P.cells[i] = b
    end
    P.prev = Button(page, "‹", 28, 22, function() state.gridPage = state.gridPage - 1; P.Refresh() end)
    P.next = Button(page, "›", 28, 22, function() state.gridPage = state.gridPage + 1; P.Refresh() end)
    Place(P.prev, "TOPLEFT", page, "TOPLEFT", W / 2 - 80, -34 - U.GRID_ROWS * cell - 2)
    Place(P.next, "TOPLEFT", page, "TOPLEFT", W / 2 + 52, -34 - U.GRID_ROWS * cell - 2)
    P.pageText = Text(page, 12, "body", H.MUTED, "CENTER")
    Place(P.pageText, "TOPLEFT", page, "TOPLEFT", W / 2 - 50, -34 - U.GRID_ROWS * cell + 3)
    P.pageText:SetWidth(100)
    local D = CreateFrame("Frame", nil, page)
    D:SetSize(W, 118)
    Place(D, "BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    D.bg = H.Slice(D, "j-chest", 24, "BACKGROUND")
    D.bg:SetVertexColor(1, 1, 1, 0.95)
    D.icon = Icon(D, 64)
    D.icon:SetPoint("LEFT", D, "LEFT", 22, 0)
    D.name = Text(D, 17, "serif", H.IVORY)
    D.name:SetPoint("TOPLEFT", D, "TOPLEFT", 100, -16)
    D.name:SetWidth(W - 120)
    D.l1 = Text(D, 13, "body", H.SOFT)
    D.l1:SetPoint("TOPLEFT", D.name, "BOTTOMLEFT", 0, -5)
    D.l1:SetWidth(W - 120)
    D.l2 = Text(D, 12, "body", H.MUTED)
    D.l2:SetPoint("TOPLEFT", D.l1, "BOTTOMLEFT", 0, -3)
    D.l2:SetWidth(W - 120)
    D.l3 = Text(D, 12, "body", H.MUTED)
    D.l3:SetWordWrap(true)
    D.l3:SetHeight(30)
    D.l3:SetJustifyV("TOP")
    D.l3:SetPoint("TOPLEFT", D.l2, "BOTTOMLEFT", 0, -3)
    D.l3:SetWidth(W - 130)
    P.D = D
    P.empty = Empty(page, "No catches yet", "Fish you catch are listed here with the game's own icons, how many, and when you first and last caught them.")
    function P.Refresh()
        local c = J.Collection()
        local list = c.species
        J.Sort(list, state.sort, ItemName)
        P.empty:SetShown(#list == 0)
        P.sort.text:SetText(SORT_LABEL[state.sort])
        for _, w in ipairs({ P.sort, P.prev, P.next, P.pageText, D }) do w:SetShown(#list > 0) end
        P.count:SetText(("%s discovered"):format(Plural(#list, "kind")))
        P.count:SetShown(#list > 0)
        for _, b in ipairs(P.cells) do b:SetShown(#list > 0) end
        if #list == 0 then return end
        local per = U.GRID_COLS * U.GRID_ROWS
        local pagesN = math.max(1, math.ceil((#list + 1) / per))
        if state.species and state.jump then
            for i, e in ipairs(list) do if e.id == state.species then state.gridPage = math.ceil(i / per) break end end
        end
        state.jump = nil
        state.gridPage = math.max(1, math.min(pagesN, state.gridPage))
        if not state.species then state.species = list[1].id end
        local picked
        for i, b in ipairs(P.cells) do
            local e = list[(state.gridPage - 1) * per + i]
            b.id = e and e.id or nil
            b.icon:SetShown(e ~= nil)
            b.unknown:SetShown(e == nil and (state.gridPage - 1) * per + i == #list + 1)
            b:SetShown(e ~= nil or b.unknown:IsShown())
            b.sel:SetShown(e ~= nil and e.id == state.species)
            if e then
                b.icon:Set(e.id, e.q)
                b.itemID = e.id
                if e.id == state.species then picked = e end
            else
                b.itemID = nil
            end
        end
        P.pageText:SetText(("Page %d of %d"):format(state.gridPage, pagesN))
        P.prev:SetShown(state.gridPage > 1)
        P.next:SetShown(state.gridPage < pagesN)
        P.pageText:SetShown(pagesN > 1)
        if not picked then for _, e in ipairs(list) do if e.id == state.species then picked = e break end end end
        if picked then
            D.icon:Set(picked.id)
            D.name:SetText(ItemName(picked.id))
            D.l1:SetText(("Caught: %s in %s"):format(Num(picked.q), Plural(picked.c, "catch", "catches")))
            D.l2:SetText(("First caught: %s   ·   Latest: %s"):format(Day(picked.first) or "not recorded", Clock(picked.last) or "not recorded"))
            if #picked.zones > 0 then
                D.l3:SetText("In your recent sessions: " .. table.concat(picked.zones, ", ") .. (picked.moreZones > 0 and (" and " .. picked.moreZones .. " more") or ""))
            else
                D.l3:SetText("Where it was caught is only kept for your recent sessions.")
            end
        end
    end
    return P
end

---------------------------------------------------------------------------
-- Locations
---------------------------------------------------------------------------
local function BuildLocations(page)
    local P = { frame = page }
    local W = U.W - 244
    P.title = Text(page, 19, "serif", H.IVORY)
    Place(P.title, "TOPLEFT", page, "TOPLEFT", 0, 0)
    P.title:SetText("Locations")
    P.count = Text(page, 12, "body", H.MUTED, "RIGHT")
    Place(P.count, "TOPRIGHT", page, "TOPRIGHT", 0, -6)
    P.count:SetWidth(240)
    local cols = { { "Zone", 14, 200, "LEFT" }, { "Casts", 220, 62, "RIGHT" }, { "Catches", 288, 70, "RIGHT" }, { "Rate", 364, 58, "RIGHT" },
        { "On the line", 428, 84, "RIGHT" } }
    P.head = {}
    for i, c in ipairs(cols) do
        local fs = Text(page, 11, "strong", H.GOLD, c[4])
        Place(fs, "TOPLEFT", page, "TOPLEFT", c[2], -36)
        fs:SetWidth(c[3])
        fs:SetText(c[1])
        P.head[i] = fs
    end
    P.list = List(page, {
        rows = 7, h = 48, width = W,
        make = function(b)
            b.zone = Text(b, 14, "strong", H.IVORY)
            b.zone:SetPoint("TOPLEFT", b, "TOPLEFT", 14, -8)
            b.zone:SetWidth(200)
            b.sub = Text(b, 11, "body", H.MUTED)
            b.sub:SetPoint("TOPLEFT", b.zone, "BOTTOMLEFT", 0, -1)
            b.sub:SetWidth(200)
            b.cols = {}
            for i = 2, #cols do
                local fs = Text(b, 13, i == 3 and "strong" or "body", i == 3 and H.AMBERTEXT or H.SOFT, "RIGHT")
                fs:SetPoint("LEFT", b, "LEFT", cols[i][2], 0)
                fs:SetWidth(cols[i][3])
                b.cols[i] = fs
            end
        end,
        fill = function(b, r)
            b.zone:SetText(r.name)
            b.sub:SetText(r.sessions > 0 and Plural(r.sessions, "recent session") or "")
            b.cols[2]:SetText(Num(r.casts))
            b.cols[3]:SetText(Num(r.catches))
            b.cols[4]:SetText(Percent(r.rate))
            b.cols[5]:SetText(H.Duration(r.line))
        end,
    })
    Place(P.list.frame, "TOPLEFT", page, "TOPLEFT", 0, -56)
    P.note = Note(page, 0, W)
    P.note:SetText("Each zone's casts, catches and line time are exact totals. Which fish came from which zone is not recorded.")
    P.empty = Empty(page, "No places yet", "Each zone you fish in is listed with its casts, catches and the time your line was out.")
    function P.Refresh()
        local d = J.Locations()
        P.empty:SetShown(#d.rows == 0)
        P.list.frame:SetShown(#d.rows > 0)
        P.note:SetShown(#d.rows > 0)
        for _, h in ipairs(P.head) do h:SetShown(#d.rows > 0) end
        P.count:SetText(Plural(d.total, "zone"))
        P.list:SetItems(d.rows)
    end
    return P
end

---------------------------------------------------------------------------
-- Treasures
---------------------------------------------------------------------------
local function BuildTreasures(page)
    local P = { frame = page }
    local W = U.W - 244
    P.title = Text(page, 19, "serif", H.IVORY)
    Place(P.title, "TOPLEFT", page, "TOPLEFT", 0, 0)
    P.title:SetText("Treasures")
    P.strip = Strip(page, -32, W, 84)
    P.list = List(page, {
        rows = 4, h = 52, width = 256,
        selected = function(r) return r.id == state.container end,
        make = function(b)
            b.icon = Icon(b, 36)
            b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
            b.name = Text(b, 13, "strong", H.IVORY)
            b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 54, -9)
            b.name:SetWidth(190)
            b.sub = Text(b, 11, "body", H.MUTED)
            b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
            b.sub:SetWidth(190)
            Tip(b, true)
        end,
        fill = function(b, r)
            b.icon:Set(r.id, r.caught)
            b.itemID = r.id
            b.name:SetText(ItemName(r.id))
            b.sub:SetText(("Opened %s · waiting %s"):format(Num(r.opened), Num(r.unopened)))
        end,
        click = function(r) state.container = r.id; P.Refresh() end,
    })
    Place(P.list.frame, "TOPLEFT", page, "TOPLEFT", 0, -156)
    Heading(page, "Containers", 0, -128, 256)
    local D = CreateFrame("Frame", nil, page)
    D:SetSize(W - 274, 280)
    Place(D, "TOPLEFT", page, "TOPLEFT", 274, -128)
    P.D = D
    D.head = Heading(D, "Confirmed contents", 0, 0, W - 274)
    D.sub = Text(D, 12, "body", H.MUTED)
    D.sub:SetWordWrap(true)
    Place(D.sub, "TOPLEFT", D, "TOPLEFT", 0, -28)
    D.sub:SetWidth(W - 274)
    P.contents = List(D, {
        rows = 5, h = 34, width = W - 274,
        make = function(b)
            b.icon = Icon(b, 26)
            b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
            b.name = Text(b, 13, "strong", H.IVORY)
            b.name:SetPoint("LEFT", b, "LEFT", 42, 0)
            b.name:SetWidth(150)
            b.q = Text(b, 14, "strong", H.AMBERTEXT, "RIGHT")
            b.q:SetPoint("RIGHT", b, "RIGHT", -16, 0)
            b.q:SetWidth(50)
            Tip(b, true)
        end,
        fill = function(b, e) b.icon:Set(e.id); b.itemID = e.id; b.name:SetText(ItemName(e.id)); b.q:SetText("×" .. Num(e.q)) end,
    })
    Place(P.contents.frame, "TOPLEFT", D, "TOPLEFT", 0, -56)
    P.note = Note(page, 0, W)
    P.note:SetText("Only what was seen coming out of a container is listed; earlier openings show only their counts.")
    P.empty = Empty(page, "No treasures yet", "Clams and other containers you catch are counted here, with what they held once opened.")
    function P.Refresh()
        local d = J.Treasures()
        local has = #d.rows > 0
        P.empty:SetShown(not has)
        for _, w in ipairs({ P.strip, P.list.frame, D, P.note }) do w:SetShown(has) end
        if not has then return end
        local t = d.totals
        local cells = {
            { glyph = "glyph-treasure", value = Num(t.caught), label = "Containers caught" },
            { glyph = "glyph-clam", value = Num(t.opened), label = "Opened" },
            { glyph = "glyph-lure", value = Num(t.unopened), label = "Waiting to open" },
            { glyph = "mark", value = Num(t.items), label = "Items found" },
        }
        P.strip:SetCells(cells)
        local picked
        for _, r in ipairs(d.rows) do if r.id == state.container then picked = r break end end
        if not picked then picked = d.rows[1]; state.container = picked.id end
        P.list:SetItems(d.rows, true)
        P.contents:SetItems(picked.got)
        P.contents.frame:SetShown(#picked.got > 0)
        if #picked.got > 0 then
            D.sub:SetText(("From %s of %s that you opened."):format(Num(picked.opened), ItemName(picked.id)))
        elseif picked.opened > 0 then
            D.sub:SetText("Opened, but what they held was not recorded.")
        else
            D.sub:SetText("Not opened yet: nothing to show.")
        end
    end
    return P
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local BUILD = { overview = BuildOverview, sessions = BuildSessions, collections = BuildCollections, locations = BuildLocations,
    treasures = BuildTreasures }

local function Scale() return S.Get("journal.scale") or 1 end

local function Build()
    local f = CreateFrame("Frame", "TwichUIFishingJournal", UIParent)
    f:SetSize(U.W, U.H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    f.bg = H.Slice(f, "j-frame", U.FRAME_CUT, "BACKGROUND")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(30, 30)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -24)
    H.Texture(f.icon, "glyph-hook")
    f.title = Text(f, 21, "serif", H.IVORY)
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
    f.title:SetText("Fishing Journal")
    f.char = Text(f, 12, "body", H.MUTED, "RIGHT")
    f.char:SetPoint("TOPRIGHT", f, "TOPRIGHT", -64, -34)
    f.char:SetWidth(240)
    f.char:SetText(UnitName and UnitName("player") or "")
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -16)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -60, -16)
    drag:SetHeight(40)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(30, 30)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -24)
    f.close.tex = f.close:CreateTexture(nil, "ARTWORK")
    f.close.tex:SetAllPoints()
    H.Texture(f.close.tex, "j-close")
    f.close:SetScript("OnClick", function() U.Close() end)
    -- navigation
    for i, key in ipairs(U.PAGES) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(136, 38)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -74 - (i - 1) * 44)
        b.bg = H.Slice(b, "j-nav", 12, "BACKGROUND")
        b.glyph = b:CreateTexture(nil, "ARTWORK")
        b.glyph:SetSize(22, 22)
        b.glyph:SetPoint("LEFT", b, "LEFT", 12, 0)
        H.Texture(b.glyph, U.GLYPH[key])
        b.text = Text(b, 14, "strong", H.IVORY)
        b.text:SetPoint("LEFT", b, "LEFT", 42, 0)
        b.text:SetText(U.LABEL[key])
        b.key = key
        b:SetScript("OnClick", function() U.Show(key) end)
        b:SetScript("OnEnter", function(self) self.hovered = true; U.Look() end)
        b:SetScript("OnLeave", function(self) self.hovered = false; U.Look() end)
        nav[key] = b
    end
    f.mark = f:CreateTexture(nil, "ARTWORK")
    f.mark:SetSize(104, 81)
    f.mark:SetPoint("BOTTOM", f, "BOTTOMLEFT", 98, 40)
    H.Texture(f.mark, "j-mark")
    f.mark:SetAlpha(0.55)
    f.panel = CreateFrame("Frame", nil, f)
    f.panel:SetSize(U.W - 184, U.H - 86)
    f.panel:SetPoint("TOPLEFT", f, "TOPLEFT", 174, -66)
    f.panel.bg = H.Slice(f.panel, "j-recess", 24, "BACKGROUND")
    for _, key in ipairs(U.PAGES) do
        local page = CreateFrame("Frame", nil, f.panel)
        page:SetPoint("TOPLEFT", f.panel, "TOPLEFT", 22, -22)
        page:SetPoint("BOTTOMRIGHT", f.panel, "BOTTOMRIGHT", -22, 22)
        page:Hide()
        pages[key] = BUILD[key](page)
        pages[key].frame = page
    end
    f:SetScript("OnShow", function() U.Refresh() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "TwichUIFishingJournal") end
    return f
end

function U.Look()
    for key, b in pairs(nav) do
        local on = key == current
        b.bg:SetArt(on and "j-nav-on" or "j-nav")
        b.bg:SetVertexColor(1, 1, 1, (on or b.hovered) and 1 or 0.85)
        H.Color(b.text, on and { 0.12, 0.07, 0.03 } or (b.hovered and H.GOLD or H.IVORY))
    end
end

function U.Frame()
    if not win then
        local ok, f = pcall(Build)
        if not ok then
            F.Note("journal-build", tostring(f))
            return nil
        end
        win = f
    end
    return win
end

function U.Refresh()
    if not win then return end
    for key, p in pairs(pages) do
        local on = key == current
        p.frame:SetShown(on)
        if on and p.Refresh then
            local ok, err = pcall(p.Refresh)
            if not ok then F.Note("journal-page", key .. ": " .. tostring(err)); R.Fault("fishing journal " .. key, err) end
        end
    end
    U.Look()
end

function U.Show(page)
    if page and BUILD[page] then current = page end
    U.Refresh()
end

function U.Open(page)
    local f = U.Frame()
    if not f then return false end
    if page and BUILD[page] then current = page end
    f:SetScale(Scale())
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", S.Get("journal.x") or 0, S.Get("journal.y") or 0)
    f:Show()
    U.Refresh()
    return true
end

function U.Rescale()
    if win then win:SetScale(Scale()) end
    if sum then sum:SetScale(Scale()) end
end
function U.Close() if win then win:Hide() end end
function U.Shown() return win ~= nil and win:IsShown() end
function U.Page() return current end
function U.Toggle(page)
    if U.Shown() and (not page or page == current) then U.Close() return false end
    return U.Open(page)
end

-- Go to a page with something chosen on it: a session id, an item id (Collections) or a container id (Treasures).
function U.Select(page, id)
    if page == "sessions" then state.session = id
    elseif page == "collections" then state.species, state.jump = id, true
    elseif page == "treasures" then state.container = id end
    if not U.Shown() then return U.Open(page) end
    U.Show(page)
    return true
end

U.State = state
H.OnItem(function() if U.Shown() or (U.SummaryShown and U.SummaryShown()) then U.Refresh(); if U.RefreshSummary then U.RefreshSummary() end end end)
for _, e in ipairs({ "ITEM", "CONTAINER", "QUEUE", "CATCH", "SESSION_END" }) do
    F.Subscribe(e, function() if U.Shown() and U.Refresh then U.Refresh() end end)
end

---------------------------------------------------------------------------
-- The session-completion summary: a smaller window in the same frames, shown when a session you ended has catches
---------------------------------------------------------------------------
local sum
U.SUMMARY = { W = 420, H = 500, ROWS = 6 }
-- Columns after "Item" and "Quantity": Stage 3B adds its own here ({ label, width }) and fills each row's `extra`.
U.SUMMARY_COLUMNS = {}

local function BuildSummary()
    local f = CreateFrame("Frame", "TwichUIFishingSummary", UIParent)
    f:SetSize(U.SUMMARY.W, U.SUMMARY.H)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:Hide()
    f.bg = H.Slice(f, "j-frame", U.FRAME_CUT, "BACKGROUND")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -24)
    H.Texture(f.icon, "glyph-time")
    f.title = Text(f, 20, "serif", H.IVORY)
    f.title:SetPoint("LEFT", f.icon, "RIGHT", 10, 0)
    f.title:SetText("Session Summary")
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -16)
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -60, -16)
    drag:SetHeight(40)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.close = CreateFrame("Button", nil, f)
    f.close:SetSize(28, 28)
    f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -24)
    f.close.tex = f.close:CreateTexture(nil, "ARTWORK")
    f.close.tex:SetAllPoints()
    H.Texture(f.close.tex, "j-close")
    f.close:SetScript("OnClick", function() U.CloseSummary() end)
    f.zone = Text(f, 18, "serif", H.GOLD)
    f.zone:SetPoint("TOPLEFT", f, "TOPLEFT", 36, -74)
    f.zone:SetWidth(250)
    f.when = Text(f, 12, "body", H.MUTED)
    f.when:SetPoint("TOPLEFT", f.zone, "BOTTOMLEFT", 0, -3)
    f.when:SetWidth(250)
    f.time = Text(f, 18, "serif", H.IVORY, "RIGHT")
    f.time:SetPoint("TOPRIGHT", f, "TOPRIGHT", -38, -74)
    f.time:SetWidth(120)
    f.head = CreateFrame("Frame", nil, f)
    f.head:SetSize(U.SUMMARY.W - 76, 24)
    f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 38, -124)
    f.head.bg = H.Slice(f.head, "j-row", 8, "BACKGROUND")
    f.head.item = Text(f.head, 12, "strong", H.GOLD)
    f.head.item:SetPoint("LEFT", f.head, "LEFT", 20, 0)
    f.head.item:SetText("Item")
    f.head.qty = Text(f.head, 12, "strong", H.GOLD, "RIGHT")
    f.head.qty:SetPoint("RIGHT", f.head, "RIGHT", -22, 0)
    f.head.qty:SetWidth(80)
    f.head.qty:SetText("Quantity")
    f.list = List(f, {
        rows = U.SUMMARY.ROWS, h = 40, width = U.SUMMARY.W - 76,
        make = function(b)
            b.icon = Icon(b, 30)
            b.icon:SetPoint("LEFT", b, "LEFT", 8, 0)
            b.name = Text(b, 14, "strong", H.IVORY)
            b.name:SetPoint("LEFT", b, "LEFT", 46, 0)
            b.name:SetWidth(210)
            b.q = Text(b, 15, "strong", H.AMBERTEXT, "RIGHT")
            b.q:SetPoint("RIGHT", b, "RIGHT", -22, 0)
            b.q:SetWidth(80)
            Tip(b, true)
        end,
        fill = function(b, e) b.icon:Set(e.id); b.itemID = e.id; b.name:SetText(ItemName(e.id)); b.q:SetText(Num(e.q)) end,
    })
    Place(f.list.frame, "TOPLEFT", f, "TOPLEFT", 38, -152)
    f.rule = f:CreateTexture(nil, "ARTWORK")
    f.rule:SetSize(U.SUMMARY.W - 90, 12)
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", 45, -398)
    H.Texture(f.rule, "rule", { 0.62, 0.45, 0.24, 0.4 })
    f.foot = Text(f, 13, "body", H.SOFT, "CENTER")
    f.foot:SetPoint("TOP", f, "TOP", 0, -414)
    f.foot:SetWidth(U.SUMMARY.W - 80)
    f.treasure = Text(f, 12, "body", H.AMBERTEXT, "CENTER")
    f.treasure:SetPoint("TOP", f.foot, "BOTTOM", 0, -4)
    f.treasure:SetWidth(U.SUMMARY.W - 80)
    f.open = Button(f, "Open Journal", 130, 28, function() local id = f.id; U.CloseSummary(); U.Select("sessions", id) end)
    f.open:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 40, 30)
    f.done = Button(f, "Close", 100, 28, function() U.CloseSummary() end)
    f.done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -40, 30)
    return f
end

function U.RefreshSummary()
    if not (sum and sum:IsShown() and sum.id) then return end
    local d = J.Summary(sum.id)
    if not d then return end
    local h = d.headline
    sum.zone:SetText(h.zone)
    sum.when:SetText(Clock(d.row.start) or "")
    sum.time:SetText(H.Duration(h.seconds))
    sum.list:SetItems(d.species)
    sum.foot:SetText(("%s total %s  •  %s catch rate"):format(Num(h.catches), h.catches == 1 and "catch" or "catches", Percent(h.rate)))
    sum.treasure:SetText(h.treasuresOpened > 0 and ("Opened %s and took %s from them."):format(Plural(h.treasuresOpened, "container"),
        Plural(h.treasureItems, "item")) or "")
end

function U.SummaryShown() return sum ~= nil and sum:IsShown() end

function U.Summary(id)
    if not (sum or U.SummaryFrame()) then return false end
    local d = J.Summary(id)
    if not d then return false end
    sum.id = id
    sum:SetScale(Scale())
    sum:ClearAllPoints()
    sum:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    sum:Show()
    U.RefreshSummary()
    return true
end

function U.SummaryFrame()
    if not sum then
        local ok, f = pcall(BuildSummary)
        if not ok then F.Note("journal-build", "summary: " .. tostring(f)) return nil end
        sum = f
    end
    return sum
end
function U.CloseSummary() if sum then sum:Hide() end end

-- When a session ends with something caught, offer its summary (not in combat: it waits for the end of it).
local pending
local function Offer(id)
    if not S.Get("journal.summary") then return end
    if F.InCombat() then
        pending = id
        if R.On then R:On("PLAYER_REGEN_ENABLED", U.OnRegen) end
        return
    end
    U.Summary(id)
end
function U.OnRegen()
    if R.Off then R:Off("PLAYER_REGEN_ENABLED", U.OnRegen) end
    local id = pending
    pending = nil
    if id then Offer(id) end
end
F.Subscribe("SESSION_END", function(_, id, reason)
    if reason ~= "command" and reason ~= "idle" then return end
    local s = F.API.SessionByID(id)
    if not s or ((s.catches or 0) == 0 and (s.items or 0) == 0) then return end
    Offer(id)
end)
