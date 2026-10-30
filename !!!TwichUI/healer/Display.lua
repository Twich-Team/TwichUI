-- TwichUI: Healer Watch, drawing
-- One panel frame, made the first time it is shown, and the same layout code for the settings window's inline preview.
-- It draws what Logic.Present returns and nothing else: it never reads a unit, except to hand the game's own restricted
-- mana value straight to the bar and the number (D.UpdateSecret), which it never compares, formats or keeps.
--
--   D.Render(view, cfg, mode)   mode: "live", "preview" (labelled "Preview") or "position" (with a handle to drag);
--                               drawn again only when the view or the settings changed (a signature of both)
--   D.Hide(immediate)           put away (with the short fade if chosen, unless immediate)
--   D.UpdateSecret(unit, cfg)   restricted mana: the game's value into the bar and the number, as it arrives
--   D.NewSurface(parent), D.DrawSurface(surface, view, cfg, maxW, maxH)   the settings window's inline preview
--
-- The panel takes no clicks (EnableMouse false) so it never gets in the way of the world; only the move handle does,
-- and only while you are moving it. Motion is optional and short: a 0.2 s fade in and 0.25 s fade out, and a pulse of
-- three slow breaths when mana becomes critical, each only when chosen and neither with Notifications' Reduced motion
-- on. Both are animation groups the game runs; nothing here has an OnUpdate. The same goes for the attention effect
-- of each trigger (chat, critical mana, drinking): None, a Flash (D.Flash) or Magical particles (Particles.lua), one of
-- them for a trigger, never both. D.Attention picks by the setting.
-- The decorative flask is the emblem only: its painted liquid never moves and is not a gauge. The bar and the number
-- carry the measured mana.

local R = TwichUI
local HW = R.HealerWatch
local MS = R.MenuStyle
local D = {}
R.HealerDisplay = D

local WHITE = [[Interface\Buttons\WHITE8x8]]
local FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", shadow = "" }
local FADE_IN, FADE_OUT = 0.2, 0.25
local PULSE_HALF, PULSE_BREATHS = 0.7, 3
local FLASH_UP, FLASH_DOWN, FLASHES, FLASH_GAP = 0.12, 0.55, 2, 2   -- seconds; how many times; least gap between two
local FLASH_COLOR = { chat = "colorText", critical = "colorCritical", drinking = "colorMana" }
local EFFECT_KEY = { chat = "effectChat", critical = "effectCritical", drinking = "effectDrinking" }
local GAP = 8
local EDGE = { 0.20, 0.155, 0.09 }          -- blackened bronze: the bar's frame
local TRACK = { 0.055, 0.047, 0.04 }        -- the empty part of the bar: warm near-black
local PANEL = { 0.08, 0.065, 0.05 }         -- warm charcoal, for the optional panel
local PANEL_EDGE = { 0.36, 0.28, 0.15 }
local MARK = { 0.58, 0.78, 0.76 }           -- the preview outline: the settings window's accent

local frame, handle
local layoutRev = 1
local drawnSig
local shownMode
local curve, secretFailed
local fxSig                                 -- the effect settings the running effects were started under
local surfaceFx = setmetatable({}, { __mode = "k" })   -- the sample surfaces that have played particles
local stats = { draws = 0, secretDraws = 0, secretRefused = 0, built = false }

local function Reduced() return R:Enabled("arrivalReducedMotion") end

local function Color(hex, fallback)
    local r, g, b = MS.ParseColor(hex)
    if not r then return fallback[1], fallback[2], fallback[3] end
    return r, g, b
end

---------------------------------------------------------------------------
-- The parts (a live panel and the inline preview alike)
---------------------------------------------------------------------------
local function Line(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer)
    t:SetColorTexture(c[1], c[2], c[3], a)
    return t
end

local function Edges(parent, target, c, a, layer)
    local list = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = Line(parent, layer or "BORDER", c, a)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1)
            t:SetPoint(side .. "LEFT", target, side .. "LEFT", 0, 0)
            t:SetPoint(side .. "RIGHT", target, side .. "RIGHT", 0, 0)
        else
            t:SetWidth(1)
            t:SetPoint("TOP" .. side, target, "TOP" .. side, 0, 0)
            t:SetPoint("BOTTOM" .. side, target, "BOTTOM" .. side, 0, 0)
        end
        list[i] = t
    end
    return list
end

local function Parts(f)
    f.body = CreateFrame("Frame", nil, f)
    f.body:SetAllPoints(f)
    f.body:EnableMouse(false)
    local b = f.body
    f.bg = Line(b, "BACKGROUND", PANEL, 0)
    f.bg:SetAllPoints(b)
    f.edges = Edges(b, b, PANEL_EDGE, 0.9)
    f.art = b:CreateTexture(nil, "ARTWORK")
    f.name = b:CreateFontString(nil, "OVERLAY")
    f.name:SetWordWrap(false)
    f.value = b:CreateFontString(nil, "OVERLAY")
    f.value:SetWordWrap(false)
    f.valueSecret = b:CreateFontString(nil, "OVERLAY")   -- only ever given the game's restricted value; never measured
    f.valueSecret:SetWordWrap(false)
    f.status = b:CreateFontString(nil, "OVERLAY")
    f.status:SetWordWrap(false)
    f.drink = b:CreateTexture(nil, "ARTWORK", nil, 2)
    f.chat = b:CreateTexture(nil, "ARTWORK", nil, 2)

    -- the bar: an outer frame that carries the border (a MenuStyle look), and the status bar inside it, inset by however
    -- far the border reaches in (BarBorder below)
    local bar = CreateFrame("Frame", nil, b, "BackdropTemplate")
    bar:EnableMouse(false)
    bar.track = Line(bar, "BACKGROUND", TRACK, 0.8)
    bar.track:SetAllPoints(bar)
    local sb = CreateFrame("StatusBar", nil, bar)
    sb:EnableMouse(false)
    sb:SetStatusBarTexture(WHITE)
    sb:SetMinMaxValues(0, 100)
    sb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    bar.sb = sb
    bar.shade = Line(sb, "OVERLAY", { 0, 0, 0 }, 0.35)   -- a faint inner shadow along the top, the same all along
    bar.shade:SetHeight(1)
    bar.shade:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, 0)
    bar.shade:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, 0)
    f.bar = bar
end

local function Font(fs, cfg, size)
    local fallback = rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
    local file = MS.Fonts.Resolve(cfg.font, fallback)
    local flags = FLAGS[cfg.outline] or ""
    if fs:SetFont(file, size, flags) == false then fs:SetFont(fallback, size, flags) end
    if cfg.outline == "shadow" then
        fs:SetShadowColor(0, 0, 0, 0.85)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function Width(fs, text)
    if not text or text == "" then return 0 end
    return math.ceil(fs:GetStringWidth() or 0)
end

-- The bar's border and fill texture, for the frame's scale as it is now (a textured border is drawn for it, so this runs
-- again after any scale change). The border is the shared MenuStyle look; its padding is how far the line reaches in
-- (ApplyInset, not the whole thickness), so the fill stays clear of it and a thin bar is never eaten.
local function BarBorder(f, cfg)
    local bar = f.bar
    if not bar:IsShown() then return end
    local edge = 0
    if cfg.barBorder then
        local look = HW.BarLook
        local e = look.ApplyInset(bar)
        edge = e or 0
    else
        bar:SetBackdrop(nil)
        if bar.twichBorders then R.Borders.Hide(bar.twichBorders) end
    end
    local w, h = bar:GetWidth() or 0, bar:GetHeight() or 0
    local cap = math.max(0, math.min(w, h) * 0.35)   -- a thick border can't make the fill vanish
    if edge > cap then edge = cap end
    local sb = bar.sb
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", bar, "TOPLEFT", edge, -edge)
    sb:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -edge, edge)
end

local TONE_KEY = { ok = "colorMana", low = "colorLow", critical = "colorCritical" }

-- The status words a layout without a line of its own for drinking and chat still needs (they have marks there).
local function CoreStatus(v)
    local out = {}
    for _, item in ipairs(v.items or {}) do
        if item ~= "Drinking" and item ~= v.chatText then out[#out + 1] = item end
    end
    return table.concat(out, " \194\183 ")
end

-- Draws view v with settings cfg into f (made by Parts). Returns its width and height.
function D.Layout(f, v, cfg)
    local preset = cfg.preset
    local ts = cfg.textSize
    local small = math.max(8, ts - 2)
    local tr, tg, tb = Color(cfg.colorText, { 0.94, 0.91, 0.82 })
    local dr, dg, db = Color(cfg.colorDim, { 0.67, 0.63, 0.57 })
    local problem = v.problem ~= nil

    -- text
    Font(f.name, cfg, ts)
    f.name:SetTextColor(tr, tg, tb)
    local nameText = cfg.showName and (problem and "Healer Watch" or (v.name or "")) or ""
    f.name:SetText(nameText)
    f.name:SetShown(nameText ~= "")

    local valueSize = preset == "artwork" and ts + 2 or ts
    Font(f.value, cfg, valueSize)
    Font(f.valueSecret, cfg, valueSize)
    local tone = v.barTone or "unknown"
    local vr, vg, vb = tr, tg, tb
    if tone == "low" or tone == "critical" then vr, vg, vb = Color(cfg[TONE_KEY[tone]], { tr, tg, tb })
    elseif tone == "unknown" then vr, vg, vb = dr, dg, db end
    f.value:SetTextColor(vr, vg, vb)
    f.valueSecret:SetTextColor(tr, tg, tb)
    f.value:SetText(v.manaText or "")
    f.value:SetShown(v.manaText ~= nil and not v.manaSecret)
    f.valueSecret:SetShown(v.manaSecret == true)

    Font(f.status, cfg, small)
    local statusText = v.status or ""
    if preset == "minimal" then statusText = CoreStatus(v) end
    f.status:SetText(statusText)
    local sr, sg, sb = dr, dg, db
    if v.statusTone == "warn" or v.statusTone == "low" then sr, sg, sb = Color(cfg.colorLow, { dr, dg, db })
    elseif v.statusTone == "critical" then sr, sg, sb = Color(cfg.colorCritical, { dr, dg, db }) end
    f.status:SetTextColor(sr, sg, sb)
    f.status:SetShown(statusText ~= "")

    -- the bar
    local bar = f.bar
    local showBar = cfg.showBar and not problem
    bar:SetShown(showBar)
    if showBar then
        local br, bgc, bb = dr, dg, db
        if TONE_KEY[tone] then br, bgc, bb = Color(cfg[TONE_KEY[tone]], { 0.29, 0.47, 0.68 }) end
        local file = MS.StatusBars.Resolve(cfg.barTexture)
        bar.sb:SetStatusBarTexture(file or WHITE)   -- a texture that has gone is drawn flat, and stays chosen
        bar.sb:SetStatusBarColor(br, bgc, bb, 1)
        if not v.secretBar then bar.sb:SetValue(v.barValue or 0) end
    end

    -- artwork and marks
    local showArt = cfg.showArt
    local artSize = math.floor(cfg.artSize)
    f.art:SetShown(showArt)
    if showArt then
        f.art:SetTexture(HW.ArtFile("vessel", artSize))
        f.art:SetSize(artSize, artSize)
        if f.art.SetDesaturated then f.art:SetDesaturated(problem) end
        f.art:SetAlpha(problem and 0.6 or 1)
    end
    local markSize = preset == "artwork" and math.max(14, math.min(32, math.floor(artSize * 0.4))) or (ts + 4)
    local showDrink = cfg.showDrinking and not problem and (v.drinking or v.drinkHidden)
    f.drink:SetShown(showDrink and true or false)
    if showDrink then
        f.drink:SetTexture(HW.ArtFile("cup", markSize))
        f.drink:SetSize(markSize, markSize)
        -- faded and grey: drinking can't be seen right now (not "not drinking")
        if f.drink.SetDesaturated then f.drink:SetDesaturated(not v.drinking) end
        f.drink:SetAlpha(v.drinking and 1 or 0.3)
    end
    local showChat = v.chat == true
    f.chat:SetShown(showChat)
    if showChat then
        f.chat:SetTexture(HW.ArtFile("speech", markSize))
        f.chat:SetSize(markSize, markSize)
    end

    -- placing
    for _, part in ipairs({ f.art, f.name, f.value, f.valueSecret, f.status, f.drink, f.chat, bar }) do part:ClearAllPoints() end
    local body = f.body
    local pad = (cfg.panelBg > 0 or cfg.panelBorder) and 6 or 1
    local barH = math.floor(cfg.barHeight)
    local nameH = math.ceil(f.name:GetStringHeight() or ts)
    local rowH = math.max(nameH, valueSize, (showDrink or showChat) and markSize or 0)
    local statusH = f.status:IsShown() and math.ceil(f.status:GetStringHeight() or small) or 0
    local secretW = math.ceil(valueSize * 2.6)   -- room for "100%": the restricted number is never measured
    local valueW = v.manaSecret and secretW or Width(f.value, v.manaText)
    local w, h

    local function Marks(anchor, point, relPoint, x, y, dir)
        local last = anchor
        local first = true
        for _, m in ipairs({ f.drink, f.chat }) do
            if m:IsShown() then
                if first then m:SetPoint(point, anchor, relPoint, x, y) else m:SetPoint(dir == "left" and "RIGHT" or "LEFT", last, dir == "left" and "LEFT" or "RIGHT", dir == "left" and -3 or 3, 0) end
                last, first = m, false
            end
        end
    end
    local function MarksWidth()
        local n = (showDrink and 1 or 0) + (showChat and 1 or 0)
        return n > 0 and (n * markSize + (n - 1) * 3) or 0
    end

    if preset == "artwork" then
        local colW = math.max(artSize, cfg.width)
        local y = pad
        if showArt then
            f.art:SetPoint("TOP", body, "TOP", 0, -y)
            Marks(f.art, "BOTTOMLEFT", "BOTTOMRIGHT", 2, 0, "right")
            y = y + artSize + 4
        else
            Marks(body, "TOPRIGHT", "TOPRIGHT", -pad, -y, "left")
            if showDrink or showChat then y = y + markSize + 2 end
        end
        if f.name:IsShown() then
            f.name:SetPoint("TOP", body, "TOP", 0, -y)
            f.name:SetWidth(colW)
            f.name:SetJustifyH("CENTER")
            y = y + nameH + 2
        end
        local valueFs = v.manaSecret and f.valueSecret or f.value
        if valueFs:IsShown() then
            valueFs:SetPoint("TOP", body, "TOP", 0, -y)
            valueFs:SetWidth(colW)
            valueFs:SetJustifyH("CENTER")
            y = y + valueSize + 3
        end
        if showBar then
            bar:SetPoint("TOP", body, "TOP", 0, -(y + 1))
            bar:SetSize(colW - 2, barH)
            y = y + barH + 5
        end
        if f.status:IsShown() then
            f.status:SetPoint("TOP", body, "TOP", 0, -y)
            f.status:SetWidth(colW)
            f.status:SetJustifyH("CENTER")
            y = y + statusH + 2
        end
        w, h = colW + pad * 2, y + pad
    elseif preset == "minimal" then
        local x = pad
        if showArt then
            f.art:SetPoint("TOPLEFT", body, "TOPLEFT", x, -pad)
            x = x + artSize + 6
        end
        local nameW = f.name:IsShown() and math.min(Width(f.name, nameText), 140) or 0
        if f.name:IsShown() then
            f.name:SetWidth(nameW + 2)
            f.name:SetJustifyH("LEFT")
            f.name:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(pad + (rowH - nameH) / 2))
            x = x + nameW + 6
        end
        local valueFs = v.manaSecret and f.valueSecret or f.value
        if valueFs:IsShown() then
            valueFs:SetWidth(valueW + 2)
            valueFs:SetJustifyH("LEFT")
            valueFs:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(pad + (rowH - valueSize) / 2))
            x = x + valueW + 6
        end
        if showDrink or showChat then
            Marks(body, "TOPLEFT", "TOPLEFT", x, -(pad + (rowH - markSize) / 2), "right")
            x = x + MarksWidth() + 4
        end
        local rowW = x - pad
        local y = pad + math.max(rowH, showArt and artSize or 0)
        local textX = showArt and (pad + artSize + 6) or pad
        local textW = math.max(rowW - (textX - pad), 60)
        if showBar then
            bar:SetPoint("TOPLEFT", body, "TOPLEFT", textX + 1, -(y + 3))
            bar:SetSize(textW - 2, barH)
            y = y + barH + 5
        end
        if f.status:IsShown() then
            f.status:SetWidth(math.max(textW, Width(f.status, statusText) + 2))
            f.status:SetJustifyH("LEFT")
            f.status:SetPoint("TOPLEFT", body, "TOPLEFT", textX, -(y + 2))
            textW = math.max(textW, Width(f.status, statusText) + 2)
            y = y + statusH + 2
        end
        w, h = math.max(rowW, (textX - pad) + textW) + pad * 2, y + pad
    else   -- compact
        local total = cfg.width
        local x = pad
        if showArt then
            f.art:SetPoint("TOPLEFT", body, "TOPLEFT", x, -pad)
            x = x + artSize + GAP
        end
        local colW = math.max(60, total - x - pad)
        local y = pad
        local function StatusLine()
            f.status:SetWidth(colW)
            f.status:SetJustifyH("LEFT")
            f.status:SetPoint("TOPLEFT", body, "TOPLEFT", x, -y)
            y = y + statusH + 3
        end
        -- the first row: name at the left; the marks and the number at the right
        local valueFs = v.manaSecret and f.valueSecret or f.value
        local right = colW
        if valueFs:IsShown() then
            valueFs:SetWidth(valueW + 2)
            valueFs:SetJustifyH("RIGHT")
            valueFs:SetPoint("TOPRIGHT", body, "TOPLEFT", x + colW, -(y + (rowH - valueSize) / 2))
            right = right - valueW - 6
        end
        if showDrink or showChat then
            Marks(body, "TOPRIGHT", "TOPLEFT", x + right, -(y + (rowH - markSize) / 2), "left")
            right = right - MarksWidth() - 6
        end
        if f.name:IsShown() then
            f.name:SetWidth(math.max(20, right))
            f.name:SetJustifyH("LEFT")
            f.name:SetPoint("TOPLEFT", body, "TOPLEFT", x, -(y + (rowH - nameH) / 2))
        end
        y = y + rowH + 3
        if f.status:IsShown() and cfg.statusPlace == "above" then StatusLine() end
        if showBar then
            bar:SetPoint("TOPLEFT", body, "TOPLEFT", x + 1, -(y + 1))
            bar:SetSize(colW - 2, barH)
            y = y + barH + 5
        end
        if f.status:IsShown() and cfg.statusPlace ~= "above" then StatusLine() end
        w, h = total, math.max(y - 3 + pad, (showArt and artSize or 0) + pad * 2)
    end

    BarBorder(f, cfg)

    -- the optional panel behind it
    f.bg:SetShown(cfg.panelBg > 0)
    if cfg.panelBg > 0 then f.bg:SetColorTexture(PANEL[1], PANEL[2], PANEL[3], cfg.panelBg / 100) end
    for _, e in ipairs(f.edges) do e:SetShown(cfg.panelBorder) end

    w, h = math.max(1, math.ceil(w)), math.max(1, math.ceil(h))
    f:SetSize(w, h)
    return w, h
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------
local function Place(f, cfg)
    local scale = cfg.scale / 100
    f:SetScale(scale)
    f:SetAlpha(cfg.opacity / 100)
    f:ClearAllPoints()
    f:SetPoint(cfg.point, UIParent, cfg.point, cfg.x / scale, cfg.y / scale)   -- the offset is in screen units
end

-- The offset, in screen units, from a point of the screen to the same point of f.
local function OffsetFor(f, point)
    local s = f:GetScale() or 1
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    if not (l and r and t and b and W and H) then return nil end
    l, r, t, b = l * s, r * s, t * s, b * s
    local x, y
    if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = r - W else x = (l + r) / 2 - W / 2 end
    if point:find("TOP") then y = t - H elseif point:find("BOTTOM") then y = b else y = (t + b) / 2 - H / 2 end
    return x, y
end
D.OffsetFor = OffsetFor

-- The particle pool a panel or sample surface has, if it has made one.
local function PoolIfAny(owner)
    local pool = owner.particles
    return type(pool) == "table" and pool or nil
end

-- Whatever an attention effect has put on the panel: the flash's wash and the particles, both gone.
local function StopEffects()
    if not frame then return end
    frame.flash.group:Stop()
    frame.flash:SetAlpha(0)
    local pool = PoolIfAny(frame)
    if pool then pool:Stop() end
end

D.StopEffects = StopEffects

local function StopMotion()
    frame.fadeIn:Stop()
    frame.fadeOut:Stop()
    frame.pulse:Stop()
    StopEffects()
    frame.leaving = false
    frame.body:SetAlpha(1)   -- a stopped fade must not leave the panel half-transparent for its next showing
end

local function Build()
    if frame then return end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(10, 10)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)   -- click-through: only the move handle, while moving, takes the mouse
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end   -- TwichUI keeps the place, not the game's layout cache
    f:Hide()
    Parts(f)

    local g = f.body:CreateAnimationGroup()
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(FADE_IN)
    a:SetSmoothing("OUT")
    g:SetToFinalAlpha(true)
    f.fadeIn = g

    g = f.body:CreateAnimationGroup()
    a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0)
    a:SetDuration(FADE_OUT)
    a:SetSmoothing("IN")
    g:SetToFinalAlpha(true)
    g:SetScript("OnFinished", function()
        if not f.leaving then return end
        f.leaving = false
        f.body:SetAlpha(1)
        f:Hide()
    end)
    f.fadeOut = g

    -- a few slow breaths, then still: never a loop that runs for as long as mana is critical
    g = f.body:CreateAnimationGroup()
    a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.55)
    a:SetDuration(PULSE_HALF)
    a:SetSmoothing("IN_OUT")
    g:SetLooping("BOUNCE")
    g:SetScript("OnLoop", function(self)
        self.breaths = (self.breaths or 0) + 1
        if self.breaths >= PULSE_BREATHS * 2 then
            self:Stop()
            f.body:SetAlpha(1)
        end
    end)
    f.pulse = g

    -- the flash: a bright wash and outline over the panel, twice, then gone (D.Flash). Alpha only; no OnUpdate.
    local fl = CreateFrame("Frame", nil, f.body)
    fl:SetAllPoints(f.body)
    fl:EnableMouse(false)
    fl:SetAlpha(0)
    fl.wash = Line(fl, "OVERLAY", { 1, 1, 1 }, 1)
    fl.wash:SetAllPoints(fl)
    fl.edges = Edges(fl, fl, { 1, 1, 1 }, 1, "OVERLAY")
    g = fl:CreateAnimationGroup()
    local up = g:CreateAnimation("Alpha")
    up:SetFromAlpha(0)
    up:SetToAlpha(1)
    up:SetDuration(FLASH_UP)
    up:SetOrder(1)
    local down = g:CreateAnimation("Alpha")
    down:SetFromAlpha(1)
    down:SetToAlpha(0)
    down:SetDuration(FLASH_DOWN)
    down:SetOrder(2)
    g:SetLooping("REPEAT")
    g:SetScript("OnLoop", function(self)
        self.flashes = (self.flashes or 0) + 1
        if self.flashes >= FLASHES then
            self:Stop()
            fl:SetAlpha(0)
        end
    end)
    fl.group = g
    f.flash = fl

    -- the preview's outline and label
    local m = CreateFrame("Frame", nil, f)
    m:SetPoint("TOPLEFT", f, "TOPLEFT", -3, 3)
    m:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 3, -3)
    m:EnableMouse(false)
    Edges(m, m, MARK, 0.9, "OVERLAY")
    m.label = m:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 3)
    m:Hide()
    f.mark = m

    -- the picker: over the panel, taking the mouse only while it shows "Choose a healer" (D.SetClickable), so a click
    -- opens the quick-select menu (D.onPick). Never while the panel shows a healer's readings.
    local pick = CreateFrame("Button", nil, f)
    pick:SetAllPoints(f)
    pick:SetFrameStrata("HIGH")
    pick:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    pick:EnableMouse(false)
    pick:SetScript("OnClick", function(self) if D.onPick then D.onPick(self) end end)
    pick:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Choose a healer", 1, 1, 1)
        GameTooltip:AddLine("Click to pick who Healer Watch shows.", 0.8, 0.78, 0.72, true)
        GameTooltip:Show()
    end)
    pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.pick = pick

    -- the move handle: over the panel, taking the mouse only while moving
    local h = CreateFrame("Frame", nil, f, "BackdropTemplate")
    h:SetFrameStrata("DIALOG")
    h:SetAllPoints(f)
    h:SetBackdrop({ bgFile = WHITE })
    h:SetBackdropColor(0.18, 0.33, 0.33, 0.35)
    h:RegisterForDrag("LeftButton")
    h:EnableMouse(false)
    h:Hide()
    h:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        f:StartMoving()
    end)
    h:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point = HW.Get("point")
        local x, y = OffsetFor(f, point)
        if x then HW.SetPlace(point, x, y) end
        if D.onMoved then D.onMoved() end   -- StartMoving re-anchored the frame: the owner puts it back on the saved place
    end)
    h:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" and D.onPositionEnd then D.onPositionEnd() end
    end)
    frame, handle = f, h
    stats.built = true
end

local function Signature(v, cfg, mode)
    return table.concat({ layoutRev, HW.Rev(), mode, cfg.preset, v.name or "", v.manaText or "", v.manaSecret and 1 or 0,
        v.barValue and math.floor(v.barValue * 2) or -1, v.barTone or "", v.drinking and 1 or 0, v.drinkHidden and 1 or 0,
        v.chat and 1 or 0, v.status or "", v.problem or "" }, "\31")
end

-- Shows view v (made by Logic.Present) in the panel. mode: "live", "preview" or "position".
-- A change to the effect settings (a trigger's effect, the color, the strength, a profile) ends what is playing, so
-- a flash is never left over after switching to particles, nor particles in the old color after a new one is chosen.
local function EffectSig(cfg)
    return table.concat({ cfg.effectChat, cfg.effectCritical, cfg.effectDrinking, cfg.particleColor, cfg.particleIntensity }, "\31")
end

function D.Render(v, cfg, mode)
    Build()
    local f = frame
    local fsig = EffectSig(cfg)
    if fsig ~= fxSig then
        fxSig = fsig
        StopEffects()
    end
    local sig = Signature(v, cfg, mode)
    if sig ~= drawnSig then
        Place(f, cfg)   -- the scale first, then the layout
        D.Layout(f, v, cfg)
        drawnSig = sig
        stats.draws = stats.draws + 1
    end
    local previewing = mode ~= "live"
    f.mark:SetShown(previewing)
    if previewing then
        f.mark.label:SetText(mode == "position" and "Healer Watch preview: drag to move, right-click to finish" or "Healer Watch preview")
    end
    handle:SetShown(mode == "position")
    handle:EnableMouse(mode == "position")
    local clickable = mode == "live" and v.problem ~= nil
    f.pick:EnableMouse(clickable)
    if not clickable and R.HealerPicker then R.HealerPicker.Close() end   -- the menu is for the "Choose a healer" panel only

    local was = f:IsShown() and not f.leaving
    f.leaving = false
    f.fadeOut:Stop()
    f:Show()
    if not was then
        if cfg.fade and not Reduced() and not previewing then
            f.body:SetAlpha(0)
            f.fadeIn:Play()
        else
            f.body:SetAlpha(1)
        end
    end
    shownMode = mode
end

function D.Hide(immediate, cfg)
    shownMode = nil
    if not frame or not frame:IsShown() then return end
    frame.mark:Hide()
    handle:Hide()
    handle:EnableMouse(false)
    D.SetClickable(false)
    if frame.leaving then return end
    frame.fadeIn:Stop()
    frame.pulse:Stop()
    StopEffects()
    if not immediate and cfg and cfg.fade and not Reduced() then
        frame.leaving = true
        frame.body:SetAlpha(1)
        frame.fadeOut:Play()
    else
        StopMotion()
        frame:Hide()
    end
end

-- An attention flash for `kind` ("chat", "critical" or "drinking"): twice, short, in that kind's color, over the live panel,
-- and only if that kind's effect is Flash (force: the settings' "Try the flash", on a preview too). Never with
-- Notifications' Reduced motion, and never twice within FLASH_GAP seconds. Returns whether it flashed.
local lastFlash = -math.huge
function D.Flash(kind, cfg, force)
    if not (frame and frame:IsShown() and EFFECT_KEY[kind]) or Reduced() then return false end
    if not force and (shownMode ~= "live" or cfg[EFFECT_KEY[kind]] ~= "flash") then return false end
    local now = GetTime()
    if not force and now - lastFlash < FLASH_GAP then return false end
    lastFlash = now
    local r, g, b = Color(cfg[FLASH_COLOR[kind]], { 0.94, 0.91, 0.82 })
    local fl = frame.flash
    fl.wash:SetColorTexture(r, g, b, 0.28)
    for _, e in ipairs(fl.edges) do e:SetColorTexture(r, g, b, 0.95) end
    fl.group:Stop()
    fl.group.flashes = 0
    fl:SetAlpha(0)
    fl.group:Play()
    return true
end

---------------------------------------------------------------------------
-- Magical particles (Particles.lua): one pool on the live panel and one on each sample surface, made when first played
---------------------------------------------------------------------------
local function PoolOf(owner)
    local pool = PoolIfAny(owner)
    if not pool then
        pool = R.HealerParticles.New(owner)
        owner.particles = pool
    end
    return pool
end

local function PlayParticles(owner, cfg, force)
    local r, g, b = Color(cfg.particleColor, { 0.25, 0.79, 0.74 })
    return PoolOf(owner):Play(r, g, b, cfg.particleIntensity, force)
end

-- The attention effect for `kind` ("chat", "critical" or "drinking") as that trigger's setting says: nothing, the
-- flash or the particles. The live panel only, never under Reduced motion. Returns whether anything played.
function D.Attention(kind, cfg)
    local effect = EFFECT_KEY[kind] and cfg[EFFECT_KEY[kind]]
    if effect == "flash" then return D.Flash(kind, cfg) end
    if effect ~= "particles" then return false end
    if not (frame and frame:IsShown()) or shownMode ~= "live" or Reduced() then return false end
    return PlayParticles(frame, cfg)
end

-- "Preview effect" in the settings: one burst on a sample surface (D.NewSurface) in the chosen color and strength,
-- whatever the triggers are set to. It touches no healer state and starts no trigger; playing it again restarts it, never
-- layers it. Returns whether it played (false, "motion" under Reduced motion).
function D.PreviewParticles(surface, cfg)
    if Reduced() then return false, "motion" end
    surfaceFx[surface] = true
    return PlayParticles(surface, cfg, true)
end

-- Stops the sample surface's particles (the settings closed, or the effect settings changed under them).
function D.StopSurfaceEffects(surface)
    local pool = PoolIfAny(surface)
    if pool then pool:Stop() end
end

local function StopAllSurfaces()
    for s in pairs(surfaceFx) do D.StopSurfaceEffects(s) end
end
R.OnSettingsClosed(StopAllSurfaces)
HW.Subscribe(function(what)
    if what == "settings" or what == "profile" then StopAllSurfaces() end
end)

-- Whether a click on the panel opens the picker. Only for the "Choose a healer" state, live; otherwise it takes none.
function D.SetClickable(on)
    if not frame then return end
    on = on and true or false
    frame.pick:EnableMouse(on)
    if not on and R.HealerPicker then R.HealerPicker.Close() end   -- the menu is for the "Choose a healer" panel only
    if not on and GameTooltip and GameTooltip:GetOwner() == frame.pick then GameTooltip:Hide() end
end

-- Mana just became critical (live only): a short, optional pulse.
function D.Pulse(cfg)
    if not (frame and frame:IsShown() and cfg.pulse) or Reduced() or shownMode ~= "live" then return end
    frame.pulse.breaths = 0
    frame.pulse:Play()
end

-- Moves the panel to the saved place, keeping what it shows.
function D.Place(cfg) if frame then Place(frame, cfg) end end

-- The game's restricted mana for `unit`, straight into the bar and the number. The FontString and StatusBar accept
-- such values (SimpleFontStringAPIDocumentation.lua: SetFormattedText; SimpleStatusBarAPIDocumentation.lua: SetValue,
-- both "AllowedWhenTainted"); UnitPowerPercent evaluates the percentage against a 0..1 to 0..100 curve
-- (UnitDocumentation.lua, CurveUtilDocumentation.lua). Nothing here reads the value back. If the client refuses, the
-- number shows "--" and the bar stays empty for the rest of the session.
function D.UpdateSecret(unit, cfg)
    if not (frame and frame:IsShown() and unit) or secretFailed then return end
    local ok = pcall(function()
        if not curve then
            curve = C_CurveUtil.CreateCurve()
            curve:SetType(Enum.LuaCurveType.Linear)
            curve:AddPoint(0, 0)
            curve:AddPoint(1, 100)
        end
        local MANA = Enum.PowerType and Enum.PowerType.Mana or 0
        local pct = UnitPowerPercent(unit, MANA, false, curve)
        if cfg.showBar then frame.bar.sb:SetValue(pct) end
        if cfg.manaFormat ~= "none" then frame.valueSecret:SetFormattedText("%.0f%%", pct) end
    end)
    if ok then
        stats.secretDraws = stats.secretDraws + 1
    else
        secretFailed = true
        stats.secretRefused = stats.secretRefused + 1
        frame.valueSecret:SetText("--")
        frame.bar.sb:SetValue(0)
    end
end

function D.SecretRefused() return secretFailed == true end

-- Something every drawing depends on changed (a font arrived, the screen's scale): drawn again next time.
function D.Invalidate() layoutRev = layoutRev + 1 end
MS.Fonts.Subscribe(function()
    D.Invalidate()
    if D.onInvalidate then D.onInvalidate() end
end)

function D.Frame() return frame end
function D.Mode() return shownMode end

---------------------------------------------------------------------------
-- The settings window's inline preview: the same parts and layout on a frame of its own, scaled to fit its box
---------------------------------------------------------------------------
function D.NewSurface(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(10, 10)
    s:EnableMouse(false)
    Parts(s)
    return s
end

function D.DrawSurface(s, v, cfg, maxW, maxH)
    local scale = cfg.scale / 100
    local w, h = D.Layout(s, v, cfg)
    local fit = math.min(scale, maxW / w, maxH / h)
    s:SetScale(math.max(0.25, fit))
    s:SetAlpha(cfg.opacity / 100)
    BarBorder(s, cfg)   -- the border is drawn for the scale it has now
    return w, h, fit
end

function D.Snapshot()
    local fx = R.HealerParticles and R.HealerParticles.Stats() or {}
    return { built = stats.built, fxPools = fx.pools, fxMotes = fx.motes, fxBursts = fx.bursts, fxCoalesced = fx.coalesced, shown = frame ~= nil and frame:IsShown() or false, mode = shownMode, draws = stats.draws,
        secretDraws = stats.secretDraws, secretRefused = stats.secretRefused }
end
