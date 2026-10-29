-- TwichUI Layout Setup: the shared controls
-- One visual grammar for every choice the wizard asks (layouts, helper presets, size, tooltip placement, friendly nameplates,
-- the update policy, the layout packages), and the two small pieces pages use to keep detail out of the way: a disclosure
-- button ("Layout details", "View included settings") and an info button. Nothing here decides anything: a card calls the
-- function it was given, and the page that owns it asks the model again.
--
--   Controls.Choice(parent, width, onClick, opts) -> card
--       opts = { pic = { w, h }   a picture at the left (card.pic, a texture the page fills),
--                label = true     "Selected" beside the indicator (for a card wide enough to hold it),
--                titleKind = "body" | "title" }
--       card:Fill(title, hint, extra) -> height, textBottom    writes the words and sizes the card; `extra` is the height of
--                                                              what the page puts under the text (a line of traits)
--       card:SetSelected(bool), card.selected
--       Selected: a check in a fixed square at the top right, a 2 px bronze outline all round, a warm fill. Hover: a lighter 1 px
--       edge and a wash, never the check or the outline. A card keeps its size when its state changes: the indicator, the outline
--       and the label sit where they sit whether or not they are lit.
--   Controls.Mark(parent) -> frame with :SetOn(bool)   the check square on its own (the accent swatches use it)
--   Controls.Tick(parent, color) -> a 14 x 10 check mark (the stepper's "done")
--   Controls.Disclosure(parent, label, width, onToggle) -> button, :SetOpen(bool), .open
--   Controls.Info(parent, title, text) -> a small "i" button whose tooltip holds the detail
--
-- The indicator is drawn from flat textures (a ring, a fill and seven 2 px squares for the check), never from artwork, so it
-- reads the same with every file refused and costs no frame beyond its own.

local R = TwichUI
local WZ = R.LayoutWizard
local C = {}
WZ.Controls = C

C.MARK = 18           -- the indicator's square
C.MARK_GAP = 10       -- its distance from the card's top and right edges
C.LABEL_W = 64        -- room the word "Selected" takes beside it
C.TEXT_PAD = 12

local function Look() return R.Look end

local function Height(obj)
    local h
    if obj.GetStringHeight then h = obj:GetStringHeight() else h = obj:GetHeight() end
    return (type(h) == "number" and h > 0) and h or 14
end
C.Height = Height

-- the check: (column, row) of each 2 px square, in a 7 x 5 grid
local CHECK = { { 0, 2 }, { 1, 3 }, { 2, 4 }, { 3, 3 }, { 4, 2 }, { 5, 1 }, { 6, 0 } }

-- A small check mark on its own (14 x 10), in the colour given: the Mark's check, and the stepper's "done".
function C.Tick(parent, color)
    local L = Look()
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(14, 10)
    t.px = {}
    for i, cell in ipairs(CHECK) do
        local px = L.Solid(t, "OVERLAY", color, 1)
        px:SetSize(2, 2)
        px:SetPoint("TOPLEFT", cell[1] * 2, -(cell[2] * 2))
        t.px[i] = px
    end
    return t
end

function C.Mark(parent)
    local L, pal = Look(), Look().pal
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(C.MARK, C.MARK)
    m.ring = {}
    for i, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }) do
        local t = L.Solid(m, "ARTWORK", pal.control, 1)
        t:SetPoint(spec[1], 0, 0)
        t:SetPoint(spec[2], 0, 0)
        if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
        m.ring[i] = t
    end
    m.well = L.Solid(m, "BACKGROUND", pal.well, 1)
    m.well:SetAllPoints()
    m.fill = L.Solid(m, "ARTWORK", pal.bronzeText, 1)
    m.fill:SetPoint("TOPLEFT", 1, -1)
    m.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    m.tick = C.Tick(m, pal.ink)
    m.tick:SetPoint("CENTER", 0, 0)
    function m:SetOn(on)
        on = on and true or false
        self.on = on
        self.fill:SetShown(on)
        self.tick:SetShown(on)
        local c = on and pal.bronzeText or pal.control
        for _, t in ipairs(self.ring) do t:SetColorTexture(c[1], c[2], c[3], 1) end
    end
    m:SetOn(false)
    return m
end

---------------------------------------------------------------------------
-- A choice card
---------------------------------------------------------------------------
function C.Choice(parent, width, onClick, opts)
    opts = opts or {}
    local L, pal = Look(), Look().pal
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetWidth(width)
    L.Surface(b, pal.surface, 0.85, pal.bronzeLo, 0.35)
    L.Hover(b, pal.text, 0.05)
    b.fill = L.Solid(b, "BACKGROUND", pal.bronzeText, 0.13)
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    b.fill:Hide()
    -- the selected outline: four 2 px bars just inside the edge (textures, so it costs no frame)
    b.outline = {}
    for i, spec in ipairs({
        { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil },
    }) do
        local t = L.Solid(b, "BORDER", pal.bronzeText, 1)
        t:SetPoint(spec[1], 0, 0)
        t:SetPoint(spec[2], 0, 0)
        if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
        t:Hide()
        b.outline[i] = t
    end

    local textX = C.TEXT_PAD
    if opts.pic then
        b.pic = b:CreateTexture(nil, "ARTWORK")
        b.pic:SetSize(opts.pic[1], opts.pic[2])
        b.pic:SetPoint("TOPLEFT", 10, -10)
        textX = 10 + opts.pic[1] + 12
    end
    b.textX = textX
    local reserve = C.MARK + C.MARK_GAP + 6 + (opts.label and C.LABEL_W or 0)
    b.title = L.Text(b, opts.titleKind or "body")
    b.title:SetWidth(width - textX - reserve)
    b.title:SetJustifyH("LEFT")
    if b.title.SetWordWrap then b.title:SetWordWrap(true) end
    b.title:SetPoint("TOPLEFT", textX, -10)
    b.hint = L.Text(b, "small")
    b.hint:SetWidth(width - textX - C.TEXT_PAD)
    b.hint:SetJustifyH("LEFT")
    if b.hint.SetWordWrap then b.hint:SetWordWrap(true) end

    b.mark = C.Mark(b)
    b.mark:SetPoint("TOPRIGHT", -C.MARK_GAP, -C.MARK_GAP)
    if opts.label then
        b.selText = L.Text(b, "meta")
        b.selText:SetText("Selected")
        b.selText:SetPoint("RIGHT", b.mark, "LEFT", -6, 0)
        b.selText:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
        b.selText:Hide()
    end

    local hot = false
    local function Paint()
        if b.selected then b:SetBackdropBorderColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3], 1)
        elseif hot then b:SetBackdropBorderColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3], 0.6)
        else b:SetBackdropBorderColor(pal.bronzeLo[1], pal.bronzeLo[2], pal.bronzeLo[3], 0.35) end
    end
    b:HookScript("OnEnter", function() hot = true Paint() end)
    b:HookScript("OnLeave", function() hot = false Paint() end)
    b:HookScript("OnHide", function() hot = false Paint() end)
    b:SetScript("OnClick", onClick)

    function b:Fill(title, hint, extra)
        self.title:SetText(title or "")
        local y = 10 + math.max(Height(self.title), 18)
        local has = hint ~= nil and hint ~= ""
        self.hint:SetText(has and hint or "")
        self.hint:SetShown(has)
        if has then
            self.hint:ClearAllPoints()
            self.hint:SetPoint("TOPLEFT", self.textX, -(y + 4))
            y = y + 4 + Height(self.hint)
        end
        self.textBottom = y
        local h = math.max(y + (extra or 0) + 12, opts.pic and (opts.pic[2] + 20) or 0)
        self:SetHeight(h)
        return h, y
    end
    function b:SetSelected(v)
        v = v and true or false
        self.selected = v
        self.fill:SetShown(v)
        for _, t in ipairs(self.outline) do t:SetShown(v) end
        self.mark:SetOn(v)
        if self.selText then self.selText:SetShown(v) end
        Paint()
    end
    Paint()
    return b
end

---------------------------------------------------------------------------
-- A disclosure button: a chevron, the label, and the open state. The detail it opens is the page's own, built the first
-- time it is asked for.
---------------------------------------------------------------------------
function C.Disclosure(parent, label, width, onToggle)
    local L, pal = Look(), Look().pal
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 200, 22)
    L.Hover(b, pal.text, 0.05)
    b.down = L.Chevron(b, b, "LEFT", 10, 0, true, pal.bronzeText)
    b.up = L.Chevron(b, b, "LEFT", 10, 0, false, pal.bronzeText)
    b.label = L.Text(b, "body")
    b.label:SetPoint("LEFT", 24, 0)
    b.label:SetText(label)
    b.label:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
    function b:SetOpen(v)
        v = v and true or false
        self.open = v
        for _, t in ipairs(self.down) do t:SetShown(not v) end
        for _, t in ipairs(self.up) do t:SetShown(v) end
    end
    b:SetOpen(false)
    b:SetScript("OnClick", function()
        b:SetOpen(not b.open)
        if onToggle then onToggle(b.open) end
    end)
    return b
end

-- A small "i" button: the detail is in its tooltip (and nothing critical is only there).
function C.Info(parent, title, text)
    local L, pal = Look(), Look().pal
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    L.Surface(b, pal.well, 1, pal.control, 1)
    L.Hover(b, pal.text, 0.08)
    b.glyph = L.Text(b, "meta")
    b.glyph:SetPoint("CENTER", 0, 0)
    b.glyph:SetText("i")
    b.glyph:SetTextColor(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3])
    R.Interact.Tip(b, title, text)
    return b
end
