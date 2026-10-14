-- TwichUI: Journey Chronicle look
-- Colours and small drawing helpers for the Chronicle windows, kept apart from
-- chronicle/Window.lua so the look can be tuned without touching its behaviour.
-- Everything is drawn from flat WHITE8x8 colour textures: no image files, and no
-- dependency on any other addon. Nothing here runs per frame.
--
-- Other windows draw with these helpers too (the Welcome card, the refreshments panel, the Auction
-- House tab, ...), so the colours below are never changed. A window that wants its own look makes a
-- palette (S.NewPalette), changes that, and passes it as the last argument of the helpers it uses; it
-- repaints with the S.Paint* functions and each widget's Repaint. Without a palette every helper draws
-- exactly as it always has. chronicle/Appearance.lua does this for the Chronicle windows.

local R = TwichUI
local S = {}
R.ChronicleStyle = S

local WHITE = "Interface\\Buttons\\WHITE8x8"

-- Warm umber and aged bronze. Text stays parchment; metadata stays stone.
S.color = {
    bg       = { 0.150, 0.115, 0.082 },
    well     = { 0.112, 0.084, 0.060 },
    band     = { 0.200, 0.150, 0.100 },
    bronze   = { 0.55, 0.43, 0.22 },
    bronzeLo = { 0.30, 0.23, 0.13 },
    gold     = { 0.79, 0.64, 0.29 },
    text     = { 0.93, 0.88, 0.76 },
    textDim  = { 0.78, 0.74, 0.66 },
    stone    = { 0.62, 0.58, 0.51 },
    ember    = { 0.74, 0.40, 0.32 },
    emberHi  = { 0.92, 0.55, 0.44 },
}
local K = S.color

local function Copy(c) return { c[1], c[2], c[3] } end

-- The colours one window draws with. The literal colours the buttons used to carry are named here
-- (primary: the bronze-filled button, quiet: the outlined one), so a palette can change them.
-- Scalars: bgAlpha, wellAlpha and bandAlpha are how solid the window's surfaces are, edge scales the
-- frame's rim lines (1 is as drawn), hover is the strength of a row's hover tint, dividers and worn
-- turn the row and header lines and the speckle and shading on and off.
function S.NewPalette()
    return {
        bg = Copy(K.bg), well = Copy(K.well), band = Copy(K.band),
        bronze = Copy(K.bronze), bronzeLo = Copy(K.bronzeLo), gold = Copy(K.gold),
        text = Copy(K.text), textDim = Copy(K.textDim), stone = Copy(K.stone),
        ember = Copy(K.ember), emberHi = Copy(K.emberHi),
        divider = Copy(K.bronzeLo), thumb = Copy(K.bronze), track = { 0, 0, 0 },
        primary = {
            border = Copy(K.gold), bg = { 0.30, 0.205, 0.085 }, text = { 1, 0.91, 0.70 },
            hotBorder = { 0.92, 0.76, 0.38 }, hotBg = { 0.38, 0.265, 0.11 }, hotText = { 1, 0.96, 0.82 },
        },
        quiet = {
            border = Copy(K.bronzeLo), bg = { 0.115, 0.088, 0.066 }, text = Copy(K.textDim),
            hotBorder = Copy(K.bronze), hotBg = { 0.15, 0.115, 0.085 }, hotText = Copy(K.text),
        },
        bgAlpha = 0.98, wellAlpha = 0.92, bandAlpha = 1, edge = 1, hover = 0.06, dividers = true, worn = true,
    }
end
local DEFAULT = S.NewPalette()   -- what a helper draws with when it is given none; never changed
S.palette = DEFAULT

local function Paint(t, c, a) t:SetColorTexture(c[1], c[2], c[3], a) end
local function Capped(a) return a > 1 and 1 or a end

local function Solid(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- A 1px line along one edge of `parent`, `inset` pixels in.
local function Edge(parent, side, inset, c, a)
    local t = Solid(parent, "BORDER", c, a)
    if side == "TOP" or side == "BOTTOM" then
        t:SetHeight(1)
        t:SetPoint(side .. "LEFT", inset, side == "TOP" and -inset or inset)
        t:SetPoint(side .. "RIGHT", -inset, side == "TOP" and -inset or inset)
    else
        t:SetWidth(1)
        t:SetPoint("TOP" .. side, side == "LEFT" and inset or -inset, -inset)
        t:SetPoint("BOTTOM" .. side, side == "LEFT" and inset or -inset, inset)
    end
    return t
end

-- Four lines round `parent`; returns them (top, bottom, left, right).
local function Border(parent, inset, c, a)
    return {
        Edge(parent, "TOP", inset, c, a), Edge(parent, "BOTTOM", inset, c, a),
        Edge(parent, "LEFT", inset, c, a), Edge(parent, "RIGHT", inset, c, a),
    }
end

local function PaintAll(list, c, a)
    for _, t in ipairs(list) do Paint(t, c, a) end
end

local function ShowAll(list, shown)
    for _, t in ipairs(list) do t:SetShown(shown) end
end

-- Fixed scatter of faint pixels, so the surface reads as worn material rather than flat colour.
-- Returns the textures made.
function S.Speckle(frame, w, h, count)
    local made = {}
    local seed = 7919
    for i = 1, count do
        seed = (seed * 1103 + 12345) % 65536
        local x = seed % (w - 8) + 4
        seed = (seed * 1103 + 12345) % 65536
        local y = seed % (h - 8) + 4
        local light = i % 3 == 0
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        t:SetSize(i % 5 == 0 and 2 or 1, 1)
        t:SetColorTexture(light and 0.75 or 0, light and 0.6 or 0, light and 0.4 or 0, light and 0.10 or 0.20)
        t:SetPoint("TOPLEFT", x, -y)
        made[#made + 1] = t
    end
    return made
end

-- Outer frame: dark edge, bronze rim, inner shadow line, corner pixels, speckle,
-- and a stepped shade toward the bottom.
-- The pieces are kept on the frame (f.twichFrame) so S.PaintFrame can recolour, hide and show them.
function S.Frame(f, w, h, pal)
    pal = pal or DEFAULT
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], pal.bgAlpha)
    f:SetBackdropBorderColor(0.03, 0.02, 0.015, 1)
    local p = {}
    p.rim = Border(f, 1, pal.bronze, 0.9)
    p.shadow = Border(f, 2, { 0, 0, 0 }, 0.6)
    p.rimLo = Border(f, 3, pal.bronzeLo, 0.6)
    p.lit = {                                      -- faint lit edges under the rim
        top = Edge(f, "TOP", 4, pal.gold, 0.16), left = Edge(f, "LEFT", 4, pal.gold, 0.06),
        right = Edge(f, "RIGHT", 4, { 0, 0, 0 }, 0.18), bottom = Edge(f, "BOTTOM", 4, pal.gold, 0.08),
    }
    p.corners = {}
    for _, c in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local t = Solid(f, "ARTWORK", pal.gold, 0.9)
        t:SetSize(5, 5)
        t:SetPoint(c[1], c[2], c[3])
        p.corners[#p.corners + 1] = t
    end
    p.speckle = S.Speckle(f, w, h, math.floor(w * h / 2500))
    p.bands = {}
    for _, band in ipairs({ { 120, 0.03 }, { 70, 0.04 }, { 30, 0.05 } }) do
        local t = Solid(f, "BACKGROUND", { 0, 0, 0 }, band[2])
        t:SetHeight(band[1])
        t:SetPoint("BOTTOMLEFT", 4, 4)
        t:SetPoint("BOTTOMRIGHT", -4, 4)
        p.bands[#p.bands + 1] = t
    end
    f.twichFrame = p
end

-- Draws the frame's decoration in a palette. ledger: the bronze rim, its lines and the corner pixels
-- are shown (they are the Chronicle's own border; false hides them for a border drawn some other
-- way). outer: the dark outermost line is a pair of textures too (for a frame whose backdrop draws no
-- edge). The backdrop itself (the fill and any edge) belongs to whoever drew it.
function S.PaintFrame(f, pal, ledger, outer)
    pal = pal or DEFAULT
    local p = f.twichFrame
    if not p then return end
    local es = pal.edge
    if ledger == nil then ledger = true end
    PaintAll(p.rim, pal.bronze, Capped(0.9 * es))
    PaintAll(p.shadow, { 0, 0, 0 }, Capped(0.6 * es))
    PaintAll(p.rimLo, pal.bronzeLo, Capped(0.6 * es))
    Paint(p.lit.top, pal.gold, Capped(0.16 * es)); Paint(p.lit.left, pal.gold, Capped(0.06 * es))
    Paint(p.lit.right, { 0, 0, 0 }, Capped(0.18 * es)); Paint(p.lit.bottom, pal.gold, Capped(0.08 * es))
    PaintAll(p.corners, pal.gold, Capped(0.9 * es))
    ShowAll(p.rim, ledger); ShowAll(p.shadow, ledger); ShowAll(p.rimLo, ledger); ShowAll(p.corners, ledger)
    for _, t in pairs(p.lit) do t:SetShown(ledger) end
    if outer and not p.outer then p.outer = Border(f, 0, { 0.03, 0.02, 0.015 }, 1) end
    if p.outer then
        PaintAll(p.outer, { 0.03, 0.02, 0.015 }, Capped(es))
        ShowAll(p.outer, ledger and outer == true)
    end
    ShowAll(p.speckle, pal.worn)
    ShowAll(p.bands, pal.worn)
end

-- Title band across the top of the frame, with a bronze underline.
function S.Header(f, height, pal)
    pal = pal or DEFAULT
    local band = Solid(f, "BACKGROUND", pal.band, pal.bandAlpha)
    band:SetPoint("TOPLEFT", 4, -4)
    band:SetPoint("TOPRIGHT", -4, -4)
    band:SetHeight(height)
    local line = Solid(f, "BORDER", pal.divider)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    local lit = Solid(f, "BORDER", pal.gold, 0.07)    -- a warm sheen along the band's top
    lit:SetHeight(1)
    lit:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
    lit:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, 0)
    local shadow = Solid(f, "BORDER", { 0, 0, 0 }, 0.35)
    shadow:SetHeight(1)
    shadow:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, 0)
    shadow:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, 0)
    f.twichHeader = { band = band, line = line, lit = lit, shadow = shadow }
end

-- Colours the title band and its lines; moves and resizes it (inset from the frame's edge, height).
function S.PaintHeader(f, pal, inset, height)
    pal = pal or DEFAULT
    local h = f.twichHeader
    if not h then return end
    Paint(h.band, pal.band, pal.bandAlpha)
    Paint(h.line, pal.divider, pal.dividers and 1 or 0)
    Paint(h.lit, pal.gold, 0.07 * pal.edge)
    Paint(h.shadow, { 0, 0, 0 }, pal.dividers and 0.35 or 0)
    if inset and height then
        h.band:ClearAllPoints()
        h.band:SetPoint("TOPLEFT", inset, -inset)
        h.band:SetPoint("TOPRIGHT", -inset, -inset)
        h.band:SetHeight(height)
    end
end

-- Recessed well for the entry list.
function S.Well(box, w, h, pal)
    pal = pal or DEFAULT
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(pal.well[1], pal.well[2], pal.well[3], pal.wellAlpha)
    box:SetBackdropBorderColor(pal.bronze[1], pal.bronze[2], pal.bronze[3], 0.7)
    local p = {
        top = Edge(box, "TOP", 1, { 0, 0, 0 }, 0.4),
        left = Edge(box, "LEFT", 1, { 0, 0, 0 }, 0.25),
        bottom = Edge(box, "BOTTOM", 1, pal.gold, 0.10),   -- warm lip along the bottom of the inset
    }
    p.speckle = S.Speckle(box, w, h, math.floor(w * h / 4000))
    box.twichWell = p
end

function S.PaintWell(box, pal)
    pal = pal or DEFAULT
    local p = box.twichWell
    if not p then return end
    box:SetBackdropColor(pal.well[1], pal.well[2], pal.well[3], pal.wellAlpha)
    box:SetBackdropBorderColor(pal.bronze[1], pal.bronze[2], pal.bronze[3], Capped(0.7 * pal.edge))
    Paint(p.bottom, pal.gold, 0.10 * pal.edge)
    ShowAll(p.speckle, pal.worn)
end

-- Restyle a UIPanelScrollFrameTemplate's bar: flat bronze thumb, small flat
-- arrow buttons. Scrolling and the template's enable/disable logic are untouched.
-- Returns a function that paints it again from the palette (nil if there is no bar to restyle).
function S.ScrollBar(scroll, pal)
    pal = pal or DEFAULT
    local bar = scroll and scroll.ScrollBar
    if type(bar) ~= "table" then return end
    local track = Solid(bar, "BACKGROUND", pal.track, 0.35)
    track:SetWidth(3)
    track:SetPoint("TOP", 0, 0)
    track:SetPoint("BOTTOM", 0, 0)
    local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
    if thumb then
        thumb:SetColorTexture(pal.thumb[1], pal.thumb[2], pal.thumb[3], 0.85)
        thumb:SetSize(6, 28)
    end
    local arrows = {}
    local function Arrow(btn, up)
        if type(btn) ~= "table" then return end
        btn:SetSize(14, 14)
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
            local t = btn[get] and btn[get](btn)
            if t then t:SetTexCoord(0, 1, 0, 1) end
        end
        local pixels = {}
        for row = 1, 3 do                          -- a small stepped arrowhead
            local px = Solid(btn, "OVERLAY", pal.gold, 0.95)
            local width = up and (row * 2 - 1) or ((4 - row) * 2 - 1)
            px:SetSize(width, 1)
            px:SetPoint("CENTER", 0, up and (row - 2) * -1 or (row - 2) * -1)
            pixels[row] = px
        end
        local function Dim(self) for i = 1, 3 do pixels[i]:SetAlpha(self:IsEnabled() and 1 or 0.3) end end
        btn:HookScript("OnEnable", Dim)
        btn:HookScript("OnDisable", Dim)
        Dim(btn)
        arrows[#arrows + 1] = { btn = btn, pixels = pixels }
    end
    Arrow(bar.ScrollUpButton, true)
    Arrow(bar.ScrollDownButton, false)
    -- the colours, now and whenever the palette changes
    local function PaintBar()
        Paint(track, pal.track, 0.35)
        if thumb then thumb:SetColorTexture(pal.thumb[1], pal.thumb[2], pal.thumb[3], 0.85) end
        for _, a in ipairs(arrows) do
            local n, p, d, h = a.btn:GetNormalTexture(), a.btn:GetPushedTexture(), a.btn:GetDisabledTexture(), a.btn:GetHighlightTexture()
            if n then n:SetColorTexture(pal.band[1], pal.band[2], pal.band[3], 1) end
            if p then p:SetColorTexture(pal.well[1], pal.well[2], pal.well[3], 1) end
            if d then d:SetColorTexture(pal.well[1], pal.well[2], pal.well[3], 0.6) end
            if h then h:SetColorTexture(pal.gold[1], pal.gold[2], pal.gold[3], 0.18) end
            PaintAll(a.pixels, pal.gold, 0.95)
        end
    end
    PaintBar()
    return PaintBar
end

local function Tint(b, border, bg, text)
    b:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    b:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    b.text:SetTextColor(text[1], text[2], text[3])
end

-- kind: "primary" (warm bronze fill) or "secondary" (quiet outline).
-- b:Repaint() draws it again from the palette (after the palette's colours changed).
function S.Button(parent, label, w, kind, onClick, pal)
    pal = pal or DEFAULT
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 24)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    -- Resting, under the pointer, pressed (a little darker, the label a pixel lower) and disabled
    -- (muted, and the pointer does nothing to it).
    local over, down = false, false
    local function Paint_()
        if not b:IsEnabled() then
            Tint(b, pal.bronzeLo, pal.well, pal.stone)
            b.text:SetPoint("CENTER", 0, 0)
            return
        end
        local set = kind == "primary" and pal.primary or pal.quiet
        local border, bg, text = set.border, set.bg, set.text
        if over then border, bg, text = set.hotBorder, set.hotBg, set.hotText end
        Tint(b, border, bg, text)
        if down then b:SetBackdropColor(bg[1] * 0.7, bg[2] * 0.7, bg[3] * 0.7, 1) end
        b.text:SetPoint("CENTER", 0, down and -1 or 0)
    end
    b:SetScript("OnEnter", function() over = true; Paint_() end)
    b:SetScript("OnLeave", function() over, down = false, false; Paint_() end)
    b:SetScript("OnMouseDown", function() down = true; Paint_() end)
    b:SetScript("OnMouseUp", function() down = false; Paint_() end)
    b:SetScript("OnEnable", Paint_)
    b:SetScript("OnDisable", Paint_)
    b:SetScript("OnHide", function() over, down = false, false end)
    b:SetScript("OnClick", onClick)
    b.Repaint = Paint_
    Paint_()
    return b
end

-- Small text-only action; `tone` is a colour from S.color, `hot` its hover colour. Both are read
-- when the pointer enters and leaves, so a palette's own colour tables can be passed and changed.
function S.Link(parent, label, onClick, tone, hot)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(44, 14)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetAllPoints()
    b.text:SetJustifyH("RIGHT")
    b.text:SetText(label)
    b.text:SetTextColor(tone[1], tone[2], tone[3])
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self) self.text:SetTextColor(hot[1], hot[2], hot[3]) end)
    b:SetScript("OnLeave", function(self) self.text:SetTextColor(tone[1], tone[2], tone[3]) end)
    function b:Repaint() self.text:SetTextColor(tone[1], tone[2], tone[3]) end
    return b
end

-- Small bronze close box, quieter than the stock red-X button.
function S.Close(parent, onClick, pal)
    pal = pal or DEFAULT
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(20, 20)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("x")
    local function Rest() Tint(b, pal.bronzeLo, pal.well, pal.stone) end
    Rest()
    b:SetScript("OnEnter", function(self) Tint(self, pal.bronze, pal.band, pal.text) end)
    b:SetScript("OnLeave", Rest)
    b:SetScript("OnClick", onClick)
    b.Repaint = Rest
    return b
end

-- Row icons, one per kind of entry. These are Blizzard's own icon files,
-- all of them paths the Forever UI source itself uses.
local ICON = "Interface\\Icons\\"
S.icons = {
    level = ICON .. "XP_Icon",
    zone  = ICON .. "inv_misc_map02",
    boss  = ICON .. "Ability_DualWield",
    death = ICON .. "INV_Misc_Bone_Skull_02",
    note  = ICON .. "INV_Scroll_04",
    start = ICON .. "inv_misc_scrollunrolled01",
    gold  = ICON .. "inv_misc_coin_01",
    profession = ICON .. "inv_misc_scrollunrolled01",   -- fallback; entries carry the profession's own icon
}

-- A small framed icon in the row's left gutter. Your own notes get a gold frame,
-- everything else a bronze one; the "Note" label in the row says it in words too.
function S.Marker(row, pal)
    pal = pal or DEFAULT
    local frame = Solid(row, "ARTWORK", pal.bronzeLo)
    frame:SetSize(20, 20)
    frame:SetPoint("TOPLEFT", 4, -9)
    local m = row:CreateTexture(nil, "ARTWORK", nil, 1)
    m:SetSize(18, 18)
    m:SetPoint("CENTER", frame, "CENTER", 0, 0)
    m.frame = frame
    return m
end

function S.SetMarker(m, kind, icon, pal)
    pal = pal or DEFAULT
    m:SetTexture(icon or S.icons[kind] or S.icons.start)
    m:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local c = kind == "note" and pal.gold or pal.bronzeLo
    m.frame:SetColorTexture(c[1], c[2], c[3], 1)
end

-- Row divider and hover tint.
function S.RowArt(row, pal)
    pal = pal or DEFAULT
    row.hover = Solid(row, "BACKGROUND", pal.gold, pal.hover)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.line = Solid(row, "ARTWORK", pal.divider, 0.35)
    row.line:SetHeight(1)
    row.line:SetPoint("TOPLEFT", 4, 0)
    row.line:SetPoint("TOPRIGHT", -4, 0)
end

-- Colours a row's hover tint and divider again (and shows or hides the divider).
function S.PaintRow(row, pal)
    pal = pal or DEFAULT
    Paint(row.hover, pal.gold, pal.hover)
    Paint(row.line, pal.divider, 0.35)
    row.line:SetShown(pal.dividers)
end

-- Small floating panel (the date picker): a lit umber surface with a bronze edge.
function S.Popover(p, pal)
    pal = pal or DEFAULT
    p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    p:SetBackdropColor(pal.bg[1] * 1.12, pal.bg[2] * 1.12, pal.bg[3] * 1.12, 1)
    p:SetBackdropBorderColor(pal.bronze[1], pal.bronze[2], pal.bronze[3], 0.95)
    p.twichPopover = { top = Edge(p, "TOP", 1, pal.gold, 0.14), bottom = Edge(p, "BOTTOM", 1, { 0, 0, 0 }, 0.45) }
end

function S.PaintPopover(p, pal)
    pal = pal or DEFAULT
    local parts = p.twichPopover
    if not parts then return end
    p:SetBackdropColor(math.min(pal.bg[1] * 1.12, 1), math.min(pal.bg[2] * 1.12, 1), math.min(pal.bg[3] * 1.12, 1), 1)
    p:SetBackdropBorderColor(pal.bronze[1], pal.bronze[2], pal.bronze[3], Capped(0.95 * pal.edge))
    Paint(parts.top, pal.gold, Capped(0.14 * pal.edge))
end

-- Control that opens a popover: the current label and a small down arrow.
function S.DropButton(parent, w, onClick, pal)
    pal = pal or DEFAULT
    local b = S.Button(parent, "", w, "secondary", onClick, pal)
    b:SetHeight(22)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -22, 0)
    b.text:SetJustifyH("LEFT")
    local pixels = {}
    for row = 1, 3 do                              -- stepped arrowhead pointing down
        local px = Solid(b, "OVERLAY", pal.gold, 0.95)
        px:SetSize((4 - row) * 2 - 1, 1)
        px:SetPoint("CENTER", b, "RIGHT", -12, 2 - row)
        pixels[row] = px
    end
    local paint = b.Repaint
    function b:Repaint() paint(); PaintAll(pixels, pal.gold, 0.95) end
    return b
end

-- Two-state button for a choice between modes; SetOn(true) gives it the bronze fill.
function S.Toggle(parent, label, w, onClick, pal)
    pal = pal or DEFAULT
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    local on, over = false, false
    local function Paint_()
        local pr, q = pal.primary, pal.quiet
        if on then Tint(b, pr.border, pr.bg, pr.text)
        elseif over then Tint(b, q.hotBorder, q.hotBg, q.hotText)
        else Tint(b, q.border, q.bg, q.text) end
    end
    function b:SetOn(v) on = v and true or false; Paint_() end
    b:SetScript("OnEnter", function() over = true; Paint_() end)
    b:SetScript("OnLeave", function() over = false; Paint_() end)
    b:SetScript("OnClick", onClick)
    b.Repaint = Paint_
    Paint_()
    return b
end
