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

-- The painted hover and the chosen state of a row (the navigation's selection sheet at row scale): row.SetSelected(row, bool)
function UI.Hover(row, corner)
    local sel = CL.Sheet(row, "selection", { layer = "BACKGROUND", sub = 2, corner = corner or 8 })
    sel:SetShown(false)
    local hot = CL.Sheet(row, "selection-hot", { layer = "BACKGROUND", sub = 1, corner = corner or 8 })
    hot:SetAlpha(0)
    row.twichSel, row.twichHot = sel, hot
    row:HookScript("OnEnter", function() hot:SetAlpha(0.45) end)
    row:HookScript("OnLeave", function() hot:SetAlpha(0) end)
    row:HookScript("OnHide", function() hot:SetAlpha(0) end)
    function row:SetSelected(on) self.selected = on and true or false; sel:SetShown(self.selected) end
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

-- A small square button with one glyph (- + x): the same painted face, a larger label
function UI.Glyph(parent, glyph, onClick, size)
    local b = UI.Button(parent, glyph, size or 24, "secondary", onClick, size or 24)
    CL.Font(b.text, 16, false, "strong")
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
