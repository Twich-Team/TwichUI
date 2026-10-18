-- TwichUI: class resource bars, the bar
-- One bar draws one resource, continuous (a fill that is a fraction of the bar: mana, rage, energy) or segmented
-- (n cells, the first k lit: combo points), from the numbers it is given. It knows nothing about the game's
-- power APIs, classes or settings storage: the controller hands it a resolved style (Config.lua's Style) and
-- states (cur, max).
--
-- Parts, all made once and reused for every resource the bar ever shows:
--   frame     a BackdropTemplate frame: the background and border are the shared MenuStyle look, drawn by its Apply
--   fill      the continuous fill (a texture whose width is the fraction), hidden while the bar is segmented
--   status    a StatusBar, made only when a current value first arrives restricted ("secret": a Mage's mana in Forever).
--             Addon code may not compute with such a value, but SetValue and SetText accept it, so the game does the
--             drawing. Plain values never use it; the fill texture above stays the one path for them.
--   cells     up to MAX_SEGMENTS pairs (a dim slot, a lit fill), made as the largest max seen needs them
--   fx        a frame above the fill for effects (Effects.lua); text sits above it, so an effect never covers it
--   text      the value, drawn only when its displayed number changes
-- Smoothing eases the displayed fraction toward the real one (a continuous bar only) on the shared driver
-- (Anim.lua). The real value, the text and anything that decides from the value (visibility, effects) use the raw
-- number, never the eased one.
-- Mouse: nothing here takes input (no frame enables the mouse), so clicks pass through to the world.

local R = TwichUI
local CB = R.ClassBars
local CBR = R.ClassBarResources
local A = R.ClassBarAnim
local BF = {}
R.ClassBarFrame = BF

local WHITE = [[Interface\Buttons\WHITE8x8]]
local MAX_CELLS = CBR.MAX_SEGMENTS
local EASE = 14          -- per second: the displayed fraction closes this share of the distance each second
local SNAP = 0.004       -- closer than this to the target: arrived

local Bar = {}
Bar.__index = Bar
BF.Bar = Bar

local white   -- a white color object, to put a texture's gradient back to plain

local function PaintTint(tex, style)
    if style.gradient and style.c1 and style.c2 and tex.SetGradient then
        tex:SetVertexColor(1, 1, 1, 1)
        tex:SetGradient(style.dir, style.c1, style.c2)
        tex.twichGradient = true
        return
    end
    if tex.twichGradient and tex.SetGradient and CreateColor then
        white = white or CreateColor(1, 1, 1, 1)
        tex:SetGradient("HORIZONTAL", white, white)
    end
    tex.twichGradient = nil
    tex:SetVertexColor(style.r, style.g, style.b, 1)
end

local function PaintTexture(tex, style)
    tex:SetTexture(style.texture)
    PaintTint(tex, style)
end

function BF.New(parent, slot)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:Hide()
    local self = setmetatable({ slot = slot, frame = f, cells = {}, cellsN = 0, lit = 0 }, Bar)
    self.fill = f:CreateTexture(nil, "ARTWORK", nil, 0)
    self.fill:Hide()
    local level = f:GetFrameLevel()
    self.fx = CreateFrame("Frame", nil, f)
    self.fx:SetAllPoints(f)
    self.fx:SetFrameLevel(level + 2)
    self.textHolder = CreateFrame("Frame", nil, f)
    self.textHolder:SetAllPoints(f)
    self.textHolder:SetFrameLevel(level + 4)
    self.text = self.textHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.text:SetWordWrap(false)
    return self
end

local function Cell(self, i)
    local c = self.cells[i]
    if c then return c end
    c = { slot = self.frame:CreateTexture(nil, "ARTWORK", nil, -1), fill = self.frame:CreateTexture(nil, "ARTWORK", nil, 0) }
    c.slot:SetColorTexture(0, 0, 0, 0.35)
    self.cells[i] = c
    return c
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function PlaceText(self, s)
    local text = self.text
    text:ClearAllPoints()
    local pad = self.edge + 4
    if s.textPlace == "left" then
        text:SetPoint("LEFT", self.textHolder, "LEFT", pad, 0)
        text:SetJustifyH("LEFT")
    elseif s.textPlace == "right" then
        text:SetPoint("RIGHT", self.textHolder, "RIGHT", -pad, 0)
        text:SetJustifyH("RIGHT")
    else
        text:SetPoint("CENTER", self.textHolder, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
    end
end

local function ApplyFont(self, s)
    local text = self.text
    local ok, result = pcall(text.SetFont, text, s.font, s.fontSize, s.fontFlags)
    if not ok or result == false then
        local fallback = rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
        pcall(text.SetFont, text, fallback, s.fontSize, s.fontFlags)
    end
    text:SetTextColor(s.tr, s.tg, s.tb, 1)
    if s.shadow then
        text:SetShadowColor(0, 0, 0, 0.9)
        text:SetShadowOffset(1, -1)
    else
        text:SetShadowOffset(0, 0)
    end
end

-- The cells for a segmented bar of n segments: positions, sizes and fills. Done when n, the size or the style changes.
local function LayoutCells(self, n)
    local s = self.style
    local gap = s.segGap
    if n > 1 then
        local room = (self.innerW - n) / (n - 1)   -- keep every cell at least a pixel wide
        if gap > room then gap = math.max(0, room) end
    else
        gap = 0
    end
    local cw = math.max(1, (self.innerW - (n - 1) * gap) / n)
    local f = self.frame
    for i = 1, MAX_CELLS do
        local c = self.cells[i]
        if i <= n then
            c = c or Cell(self, i)
            local x = self.edge + (i - 1) * (cw + gap)
            c.slot:ClearAllPoints()
            c.slot:SetPoint("TOPLEFT", f, "TOPLEFT", x, -self.edge)
            c.slot:SetSize(cw, self.innerH)
            c.slot:Show()
            c.fill:ClearAllPoints()
            c.fill:SetPoint("TOPLEFT", f, "TOPLEFT", x, -self.edge)
            c.fill:SetSize(cw, self.innerH)
            PaintTexture(c.fill, s)
            c.fill:SetShown(i <= self.lit)
        elseif c then
            c.slot:Hide()
            c.fill:Hide()
        end
    end
    self.cellsN = n
    self.geometry = "cells"
end

local function PlaceFill(self)
    local fill, f = self.fill, self.frame
    fill:ClearAllPoints()
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", self.edge, -self.edge)
    fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", self.edge, self.edge)
    PaintTexture(fill, self.style)
    self.geometry = "fill"
end

-- The StatusBar for restricted values, placed and painted like the fill. Only touched once it exists.
local function PlaceStatus(self)
    local sb, f = self.status, self.frame
    if not sb then return end
    sb:ClearAllPoints()
    sb:SetPoint("TOPLEFT", f, "TOPLEFT", self.edge, -self.edge)
    sb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -self.edge, self.edge)
    sb:SetStatusBarTexture(self.style.texture)
    local tex = sb:GetStatusBarTexture()
    if tex then PaintTint(tex, self.style) end
end

local function EnsureStatus(self)
    if self.status then return self.status end
    local sb = CreateFrame("StatusBar", nil, self.frame)
    sb:SetFrameLevel(self.frame:GetFrameLevel() + 1)   -- above the background, below the effects and the text
    sb:Hide()
    self.status = sb
    PlaceStatus(self)
    return sb
end

-- Leaves restricted mode: the status bar goes away and the fill texture is drawn from scratch.
local function LeaveSecret(self)
    if not self.secretMode then return end
    self.secretMode = false
    if self.status then self.status:Hide() end
    self.display = nil
end

local function PaintFill(self)
    local d = self.display or 0
    local fill = self.fill
    if d <= 0.0005 then
        if self.fillShown then fill:Hide(); self.fillShown = false end
        return
    end
    if not self.fillShown then fill:Show(); self.fillShown = true end
    fill:SetWidth(math.max(0.01, self.innerW * d))
    if not self.style.flatTexture then fill:SetTexCoord(0, d, 0, 1) end   -- the texture keeps its proportions
end

local function PaintCells(self)
    local max = math.floor(self.max or 0)
    if max < 1 then max = 1 elseif max > MAX_CELLS then max = MAX_CELLS end
    local lit = math.floor((self.cur or 0) + 0.0001)
    if lit < 0 then lit = 0 elseif lit > max then lit = max end
    if max ~= self.cellsN or self.geometry ~= "cells" then
        self.lit = lit
        LayoutCells(self, max)
        return
    end
    if lit == self.lit then return end
    local from, to = math.min(lit, self.lit) + 1, math.max(lit, self.lit)
    for i = from, to do
        self.cells[i].fill:SetShown(i <= lit)
    end
    self.lit = lit
end

-- The words for a restricted current value. The text is built by the game's own formatter and handed straight to
-- SetText; if the client refuses either step the bar shows no words, never a wrong number. A percentage needs
-- arithmetic, which a restricted value does not allow, so it is the game's own (the provider's pct), or nothing.
local function SecretWords(fs, mode, cur, max, pct)
    if mode == "percent" then fs:SetText(("%.0f%%"):format(pct))
    elseif mode == "currentMax" then fs:SetText(("%d / %d"):format(cur, max))
    else fs:SetText(("%d"):format(cur)) end
end

local function UpdateText(self)
    local s = self.style
    local mode = s.text
    if mode == "none" then
        if self.textShown ~= false then
            self.textHolder:Hide()
            self.textShown = false
        end
        return
    end
    if self.textShown ~= true then
        self.textHolder:Show()
        self.textShown = true
    end
    if self.secretMode then
        self.textMode, self.textA, self.textB = nil, nil, nil   -- nothing to compare with: set it again when plain
        if not pcall(SecretWords, self.text, mode, self.cur, self.max, self.pct) then self.text:SetText("") end   -- no pct: blank
        return
    end
    local cur, max = math.floor((self.cur or 0) + 0.0001), math.floor(self.max or 0)
    local b = max
    if mode == "percent" and s.kind == "continuous" then b = max > 0 and math.floor((self.cur or 0) / max * 100 + 0.5) or 0 end
    if self.textMode == mode and self.textA == cur and self.textB == b then return end   -- the same words: nothing to set
    self.textMode, self.textA, self.textB = mode, cur, b
    local str
    if mode == "currentMax" then str = ("%d / %d"):format(cur, max)
    elseif mode == "percent" and s.kind == "continuous" then str = ("%d%%"):format(b)
    else str = ("%d"):format(cur) end
    self.text:SetText(str)
end

---------------------------------------------------------------------------
-- The controller's calls
---------------------------------------------------------------------------

-- Draws with a resolved style. Nothing is done when it is the one already drawn.
function Bar:Configure(style)
    if self.style == style and self.styleRev == style.rev then return false end
    self.style, self.styleRev = style, style.rev
    local f = self.frame
    f:SetSize(style.width, style.height)
    local edge, drawn = CB.Look.Apply(f)
    -- How far the border reaches in, so the fill stays clear of it. EllesmereUI's textures are drawn centred on the
    -- frame's edge in a cell as thick as the setting, and only part of that cell is line (Borders.Inside), so
    -- clearing the whole thickness would eat a thin bar. Whatever the border, it never takes more than about a
    -- third of the bar's smaller side, so a thick border can't make the fill vanish.
    if drawn == "eui" then
        local size = CB.Look.Get("borderSize")
        if size > 0 then edge = edge * (R.Borders.Inside(CB.Look.Get("borderTexture"), size) / size) end
    end
    local cap = math.min(style.width, style.height) * 0.35
    if edge > cap then edge = cap end
    self.edge = edge
    self.innerW = math.max(1, style.width - 2 * self.edge)
    self.innerH = math.max(1, style.height - 2 * self.edge)
    ApplyFont(self, style)
    PlaceText(self, style)
    if style.kind == "continuous" then
        for i = 1, self.cellsN do
            local c = self.cells[i]
            c.slot:Hide()
            c.fill:Hide()
        end
        self.cellsN = 0
        PlaceFill(self)
        PlaceStatus(self)
        self.display = nil
    else
        self.fill:Hide()
        self.fillShown = false
        A.Remove(self)
        self.geometry = nil
        self.secretMode = false
        if self.status then self.status:Hide() end
    end
    self.textMode = nil
    if self.hasState then self:SetState(self.cur, self.max, true, self.secretMode, self.pct) end
    return true
end

-- The numbers to show. snap: no easing (a first value, a new resource). secret: cur is a restricted value; it is only
-- ever handed to the StatusBar and the text, never compared or computed with (a continuous bar only). pct: the game's
-- own 0 to 100 for it, for the percentage text.
function Bar:SetState(cur, max, snap, secret, pct)
    self.cur, self.max, self.hasState, self.pct = cur, max, true, pct
    local s = self.style
    if not s then return end
    if secret and s.kind == "continuous" then
        local sb = EnsureStatus(self)
        local fresh = not self.secretMode
        self.secretMode = true
        A.Remove(self)
        self.display, self.target = nil, nil
        self.fill:Hide()
        self.fillShown = false
        sb:SetMinMaxValues(0, max)
        local ease = s.smoothing and not snap and not fresh and rawget(_G, "Enum") and Enum.StatusBarInterpolation
        if ease and ease.ExponentialEaseOut then sb:SetValue(cur, ease.ExponentialEaseOut) else sb:SetValue(cur) end
        if not sb:IsShown() then sb:Show() end
        UpdateText(self)
        return
    end
    LeaveSecret(self)
    if s.kind == "continuous" then
        local frac = max > 0 and cur / max or 0
        if frac > 1 then frac = 1 elseif frac < 0 then frac = 0 end
        self.target = frac
        if s.smoothing and not snap and self.display ~= nil and self.frame:IsShown() then
            if self.display ~= frac and not A.Add(self) then
                self.display = frac
                PaintFill(self)
            end
        else
            A.Remove(self)
            if self.display ~= frac then
                self.display = frac
                PaintFill(self)
            end
        end
    else
        PaintCells(self)
    end
    UpdateText(self)
end

-- One easing step on the shared driver.
function Bar:Step(dt)
    local d, t = self.display or 0, self.target or 0
    local diff = t - d
    if diff < SNAP and diff > -SNAP then
        self.display = t
        PaintFill(self)
        return true
    end
    local k = dt * EASE
    if k > 1 then k = 1 end
    self.display = d + diff * k
    PaintFill(self)
    return false
end

-- Forgets what was drawn (a different resource is coming): no stale fill, segments or words.
function Bar:Clear()
    A.Remove(self)
    self.cur, self.max, self.display, self.target, self.hasState, self.pct = nil, nil, nil, nil, false, nil
    self.secretMode = false
    if self.status then self.status:Hide() end
    self.fill:Hide()
    self.fillShown = false
    for i = 1, self.cellsN do self.cells[i].fill:Hide() end
    self.lit = 0
    self.textMode = nil
    self.text:SetText("")
end

function Bar:SetShown(shown)
    local f = self.frame
    if shown then
        if not f:IsShown() then f:Show() end
    elseif f:IsShown() then
        f:Hide()
        A.Remove(self)
    end
end

function Bar:IsShown() return self.frame:IsShown() end
