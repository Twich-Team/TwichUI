-- TwichUI: Journey Chronicle look
-- Colours and small drawing helpers for the Chronicle windows, kept apart from
-- chronicle/Window.lua so the look can be tuned without touching its behaviour.
-- Everything is drawn from flat WHITE8x8 colour textures: no image files, and no
-- dependency on any other addon. Nothing here runs per frame.

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

local function Border(parent, inset, c, a)
    Edge(parent, "TOP", inset, c, a); Edge(parent, "BOTTOM", inset, c, a)
    Edge(parent, "LEFT", inset, c, a); Edge(parent, "RIGHT", inset, c, a)
end

-- Fixed scatter of faint pixels, so the surface reads as worn material rather than flat colour.
function S.Speckle(frame, w, h, count)
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
    end
end

-- Outer frame: dark edge, bronze rim, inner shadow line, corner pixels, speckle,
-- and a stepped shade toward the bottom.
function S.Frame(f, w, h)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(K.bg[1], K.bg[2], K.bg[3], 0.98)
    f:SetBackdropBorderColor(0.03, 0.02, 0.015, 1)
    Border(f, 1, K.bronze, 0.9)
    Border(f, 2, { 0, 0, 0 }, 0.6)
    Border(f, 3, K.bronzeLo, 0.6)
    Edge(f, "TOP", 4, K.gold, 0.16)            -- faint lit edge under the rim
    Edge(f, "LEFT", 4, K.gold, 0.06)
    Edge(f, "RIGHT", 4, { 0, 0, 0 }, 0.18)
    Edge(f, "BOTTOM", 4, K.gold, 0.08)
    for _, p in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
        local t = Solid(f, "ARTWORK", K.gold, 0.9)
        t:SetSize(5, 5)
        t:SetPoint(p[1], p[2], p[3])
    end
    S.Speckle(f, w, h, math.floor(w * h / 2500))
    for _, band in ipairs({ { 120, 0.03 }, { 70, 0.04 }, { 30, 0.05 } }) do
        local t = Solid(f, "BACKGROUND", { 0, 0, 0 }, band[2])
        t:SetHeight(band[1])
        t:SetPoint("BOTTOMLEFT", 4, 4)
        t:SetPoint("BOTTOMRIGHT", -4, 4)
    end
end

-- Title band across the top of the frame, with a bronze underline.
function S.Header(f, height)
    local band = Solid(f, "BACKGROUND", K.band)
    band:SetPoint("TOPLEFT", 4, -4)
    band:SetPoint("TOPRIGHT", -4, -4)
    band:SetHeight(height)
    local line = Solid(f, "BORDER", K.bronzeLo)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    local lit = Solid(f, "BORDER", K.gold, 0.07)    -- a warm sheen along the band's top
    lit:SetHeight(1)
    lit:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
    lit:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, 0)
    local shadow = Solid(f, "BORDER", { 0, 0, 0 }, 0.35)
    shadow:SetHeight(1)
    shadow:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, 0)
    shadow:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, 0)
end

-- Recessed well for the entry list.
function S.Well(box, w, h)
    box:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    box:SetBackdropColor(K.well[1], K.well[2], K.well[3], 0.92)
    box:SetBackdropBorderColor(K.bronze[1], K.bronze[2], K.bronze[3], 0.7)
    Edge(box, "TOP", 1, { 0, 0, 0 }, 0.4)
    Edge(box, "LEFT", 1, { 0, 0, 0 }, 0.25)
    Edge(box, "BOTTOM", 1, K.gold, 0.10)           -- warm lip along the bottom of the inset
    S.Speckle(box, w, h, math.floor(w * h / 4000))
end

-- Restyle a UIPanelScrollFrameTemplate's bar: flat bronze thumb, small flat
-- arrow buttons. Scrolling and the template's enable/disable logic are untouched.
function S.ScrollBar(scroll)
    local bar = scroll and scroll.ScrollBar
    if type(bar) ~= "table" then return end
    local track = Solid(bar, "BACKGROUND", { 0, 0, 0 }, 0.35)
    track:SetWidth(3)
    track:SetPoint("TOP", 0, 0)
    track:SetPoint("BOTTOM", 0, 0)
    local thumb = bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture())
    if thumb then
        thumb:SetColorTexture(K.bronze[1], K.bronze[2], K.bronze[3], 0.85)
        thumb:SetSize(6, 28)
    end
    local function Arrow(btn, up)
        if type(btn) ~= "table" then return end
        btn:SetSize(14, 14)
        for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
            local t = btn[get] and btn[get](btn)
            if t then t:SetTexCoord(0, 1, 0, 1) end
        end
        local n, p, d, h = btn:GetNormalTexture(), btn:GetPushedTexture(), btn:GetDisabledTexture(), btn:GetHighlightTexture()
        if n then n:SetColorTexture(K.band[1], K.band[2], K.band[3], 1) end
        if p then p:SetColorTexture(K.well[1], K.well[2], K.well[3], 1) end
        if d then d:SetColorTexture(K.well[1], K.well[2], K.well[3], 0.6) end
        if h then h:SetColorTexture(K.gold[1], K.gold[2], K.gold[3], 0.18) end
        local pixels = {}
        for row = 1, 3 do                          -- a small stepped arrowhead
            local px = Solid(btn, "OVERLAY", K.gold, 0.95)
            local width = up and (row * 2 - 1) or ((4 - row) * 2 - 1)
            px:SetSize(width, 1)
            px:SetPoint("CENTER", 0, up and (row - 2) * -1 or (row - 2) * -1)
            pixels[row] = px
        end
        local function Dim(self) for i = 1, 3 do pixels[i]:SetAlpha(self:IsEnabled() and 1 or 0.3) end end
        btn:HookScript("OnEnable", Dim)
        btn:HookScript("OnDisable", Dim)
        Dim(btn)
    end
    Arrow(bar.ScrollUpButton, true)
    Arrow(bar.ScrollDownButton, false)
end

local function Tint(b, border, bg, text)
    b:SetBackdropColor(bg[1], bg[2], bg[3], 1)
    b:SetBackdropBorderColor(border[1], border[2], border[3], 1)
    b.text:SetTextColor(text[1], text[2], text[3])
end

-- kind: "primary" (warm bronze fill) or "secondary" (quiet outline).
function S.Button(parent, label, w, kind, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 24)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    local idle, hot
    if kind == "primary" then
        idle = { { 0.79, 0.64, 0.29 }, { 0.30, 0.205, 0.085 }, { 1, 0.91, 0.70 } }
        hot  = { { 0.92, 0.76, 0.38 }, { 0.38, 0.265, 0.11 }, { 1, 0.96, 0.82 } }
    else
        idle = { K.bronzeLo, { 0.115, 0.088, 0.066 }, K.textDim }
        hot  = { K.bronze, { 0.15, 0.115, 0.085 }, K.text }
    end
    Tint(b, idle[1], idle[2], idle[3])
    b:SetScript("OnEnter", function(self) Tint(self, hot[1], hot[2], hot[3]) end)
    b:SetScript("OnLeave", function(self) Tint(self, idle[1], idle[2], idle[3]) end)
    b:SetScript("OnClick", onClick)
    return b
end

-- Small text-only action; `tone` is a colour from S.color, `hot` its hover colour.
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
    return b
end

-- Small bronze close box, quieter than the stock red-X button.
function S.Close(parent, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(20, 20)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER", 0, 1)
    b.text:SetText("x")
    Tint(b, K.bronzeLo, K.well, K.stone)
    b:SetScript("OnEnter", function(self) Tint(self, K.bronze, K.band, K.text) end)
    b:SetScript("OnLeave", function(self) Tint(self, K.bronzeLo, K.well, K.stone) end)
    b:SetScript("OnClick", onClick)
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
function S.Marker(row)
    local frame = Solid(row, "ARTWORK", K.bronzeLo)
    frame:SetSize(20, 20)
    frame:SetPoint("TOPLEFT", 4, -9)
    local m = row:CreateTexture(nil, "ARTWORK", nil, 1)
    m:SetSize(18, 18)
    m:SetPoint("CENTER", frame, "CENTER", 0, 0)
    m.frame = frame
    return m
end

function S.SetMarker(m, kind, icon)
    m:SetTexture(icon or S.icons[kind] or S.icons.start)
    m:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local c = kind == "note" and K.gold or K.bronzeLo
    m.frame:SetColorTexture(c[1], c[2], c[3], 1)
end

-- Row divider and hover tint.
function S.RowArt(row)
    row.hover = Solid(row, "BACKGROUND", K.gold, 0.06)
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.line = Solid(row, "ARTWORK", K.bronzeLo, 0.35)
    row.line:SetHeight(1)
    row.line:SetPoint("TOPLEFT", 4, 0)
    row.line:SetPoint("TOPRIGHT", -4, 0)
end

-- Small floating panel (the date picker): a lit umber surface with a bronze edge.
function S.Popover(p)
    p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    p:SetBackdropColor(K.bg[1] * 1.12, K.bg[2] * 1.12, K.bg[3] * 1.12, 1)
    p:SetBackdropBorderColor(K.bronze[1], K.bronze[2], K.bronze[3], 0.95)
    Edge(p, "TOP", 1, K.gold, 0.14)
    Edge(p, "BOTTOM", 1, { 0, 0, 0 }, 0.45)
end

-- Control that opens a popover: the current label and a small down arrow.
function S.DropButton(parent, w, onClick)
    local b = S.Button(parent, "", w, "secondary", onClick)
    b:SetHeight(22)
    b.text:ClearAllPoints()
    b.text:SetPoint("LEFT", 8, 0)
    b.text:SetPoint("RIGHT", -22, 0)
    b.text:SetJustifyH("LEFT")
    for row = 1, 3 do                              -- stepped arrowhead pointing down
        local px = Solid(b, "OVERLAY", K.gold, 0.95)
        px:SetSize((4 - row) * 2 - 1, 1)
        px:SetPoint("CENTER", b, "RIGHT", -12, 2 - row)
    end
    return b
end

-- Two-state button for a choice between modes; SetOn(true) gives it the bronze fill.
function S.Toggle(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    local on, over = false, false
    local function Paint()
        if on then Tint(b, { 0.79, 0.64, 0.29 }, { 0.30, 0.205, 0.085 }, { 1, 0.91, 0.70 })
        elseif over then Tint(b, K.bronze, { 0.15, 0.115, 0.085 }, K.text)
        else Tint(b, K.bronzeLo, { 0.115, 0.088, 0.066 }, K.textDim) end
    end
    function b:SetOn(v) on = v and true or false; Paint() end
    b:SetScript("OnEnter", function() over = true; Paint() end)
    b:SetScript("OnLeave", function() over = false; Paint() end)
    b:SetScript("OnClick", onClick)
    Paint()
    return b
end
