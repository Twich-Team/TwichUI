-- TwichUI: the look of TwichUI's own windows
-- Built on chronicle/Style.lua's helpers and a copy of its palette (Style.lua's own colors are never changed),
-- so a window looks complete with no other addon. Flat textures only; nothing here runs per frame. The
-- settings window (TwichUI_Settings/Widgets.lua, a load-on-demand addon) and the sharing window
-- (setup/Window.lua, in the core) both draw with this, so they are one family. It sits in the core so neither
-- needs the other loaded.
--
--   Look.pal                    the palette, by role: bronze (structure), charcoal (list, header), stone (page,
--                               cards, fields), ivory (text), teal (what is active), rust (danger)
--   Look.Text(parent, kind)     a font string: "brand", "title", "heading", "body", "small", "meta"
--   Look.Surface(frame, ...)    a flat fill with a 1px edge
--   Look.Button(parent, label, w, kind, onClick)    kind: "primary", "secondary" or "danger"; a raised face
--   Look.Recess(frame), Look.Raise(button), Look.Panel(frame), Look.Tag(parent, text)   the depth controls share
--   Look.Frame(f, w, h, headerH), Look.Header(f, height), Look.Fade(texture, ...)   the rim and tonal layers
--   Look.ShellParts(f, rim, tone)   shows or hides the rim and the tonal layers Look.Frame drew (a window whose
--                               border the player sets); Look.Header leaves the band at f.twichBand
--   Look.Motion                 the one place motion lives: timings, Fader objects, one driver that only runs
--                               while something is easing, and Settle() (everything to its resting state)
--   Look.Hover(frame, ...)      an eased wash under the pointer, for buttons and fields
--   Look.Checkbox, Look.EditBox, Look.ArrowButton, Look.ScrollBar(scroll)

local R = TwichUI
local S = R.ChronicleStyle
local Wg = {}
local Look = Wg
R.Look = Wg

local WHITE = "Interface\\Buttons\\WHITE8x8"
local FONT_TITLE = R.PATH .. [[media\fonts\Cinzel-SemiBold.ttf]]
-- The bundled fonts only have Western letters; these clients use the game's own fonts instead.
local NON_WESTERN = { koKR = true, zhCN = true, zhTW = true, ruRU = true }

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------
local pal = S.NewPalette()
-- Roles (Style.lua's own colors are never changed; this is the window's copy):
--   bronze (gold, bronze, bronzeHi, rimLo)  crafted structure: the rim, the brackets, the brand, section headings
--   charcoal (nav, band)                    the list and the header
--   stone (bg, surface, well)               the page, the section cards on it, the fields pressed into them
--   ivory (text, textDim, stone)            text, from primary to quiet
--   teal (teal, tealHi, tealLo)             one muted accent for what is active: selected, checked, focused
--   rust (danger)                           putting things back
pal.bg = { 0.137, 0.135, 0.130 }          -- the page: neutral dark stone
pal.nav = { 0.090, 0.087, 0.084 }         -- the left-hand list: deep charcoal
pal.band = { 0.108, 0.103, 0.097 }        -- the header (and a selected row's base): charcoal, a touch warmer
pal.well = { 0.072, 0.071, 0.069 }        -- fields, the checkbox, slider tracks: pressed in, not black
pal.surface = { 0.178, 0.170, 0.158 }     -- a section's card: desaturated taupe stone, a gentle step above the page
pal.text = { 0.94, 0.91, 0.82 }           -- warm ivory
pal.textDim = { 0.80, 0.78, 0.72 }        -- descriptions: gray-beige, quieter than a label but easy to read
pal.stone = { 0.62, 0.60, 0.56 }          -- category labels, hints, disabled
pal.bronzeText = { 0.76, 0.63, 0.38 }     -- a bronze readable as text: section headings and the selection marker
pal.bronzeLo = { 0.34, 0.33, 0.31 }       -- quiet interior edges and dividers (neutral; the rim has rimLo)
pal.rimLo = { 0.30, 0.23, 0.13 }          -- the old bronzeLo: the window rim's shaded side
pal.control = { 0.47, 0.46, 0.43 }        -- a button's or field's boundary: clearer than a container's edge
pal.divider = { 0.34, 0.33, 0.31 }
pal.thumb = { 0.46, 0.45, 0.42 }          -- scroll bar
pal.teal = { 0.36, 0.58, 0.57 }           -- the accent: muted, slightly gray
pal.tealHi = { 0.58, 0.78, 0.76 }         -- the accent as text, and under the pointer
pal.tealLo = { 0.18, 0.33, 0.33 }         -- the accent as a fill: a checked box, a slider's filled run
pal.ink = { 0.03, 0.02, 0.015 }           -- the outermost line, and the darkest shade
pal.bronzeHi = { 0.70, 0.56, 0.30 }       -- the lit edge of the window's rim
pal.primary = {                           -- the one affirming action (Reload now): teal, not bronze
    border = { 0.40, 0.64, 0.62 }, bg = { 0.17, 0.30, 0.30 }, text = { 0.96, 0.94, 0.88 },
    hotBorder = { 0.58, 0.78, 0.76 }, hotBg = { 0.17, 0.30, 0.30 }, hotText = { 1, 0.98, 0.92 },
}
pal.quiet = {                             -- an ordinary button: a darker stone face, a soft edge, a bronze lift on hover
    border = { 0.38, 0.36, 0.32 }, bg = { 0.200, 0.191, 0.177 }, text = { 0.90, 0.87, 0.79 },
    hotBorder = { 0.58, 0.52, 0.42 }, hotBg = { 0.200, 0.191, 0.177 }, hotText = { 0.98, 0.95, 0.88 },
}
pal.danger = {                            -- Reset and other actions that put things back: subdued rust
    border = { 0.50, 0.28, 0.23 }, bg = { 0.18, 0.125, 0.11 }, text = { 0.90, 0.64, 0.56 },
    hotBorder = { 0.72, 0.40, 0.32 }, hotBg = { 0.18, 0.125, 0.11 }, hotText = { 1, 0.78, 0.68 },
}
Wg.pal = pal

-- Style.lua's buttons read pal.primary or pal.quiet; a danger button is a quiet one in rust. A dropdown shows a
-- value, so it is a field's color (not a button's face); its arrowhead and the scroll bar's are quiet ivory.
local dangerPal = setmetatable({ quiet = pal.danger }, { __index = pal })
local fieldPal = setmetatable({
    quiet = {
        border = pal.control, bg = pal.well, text = pal.text,
        hotBorder = pal.tealHi, hotBg = pal.well, hotText = pal.text,
    },
    gold = pal.textDim,
}, { __index = pal })
local barPal = setmetatable({ gold = pal.textDim }, { __index = pal })
Wg.fieldPal, Wg.barPal = fieldPal, barPal

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------
local KINDS = {
    brand = { "GameFontNormalLarge", 20, FONT_TITLE, pal.gold },
    title = { "GameFontNormalLarge", 17, FONT_TITLE, pal.text },
    heading = { "GameFontNormal", nil, nil, pal.bronzeText },
    body = { "GameFontHighlight", nil, nil, pal.text },
    small = { "GameFontHighlightSmall2", nil, nil, pal.textDim },   -- 11px: descriptions, a step under the 12px label
    meta = { "GameFontHighlightSmall", nil, nil, pal.stone },
}

function Wg.Text(parent, kind, layer)
    local k = KINDS[kind] or KINDS.body
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", k[1])
    if k[3] then
        local locale = GetLocale and GetLocale()
        if NON_WESTERN[locale] or not fs:SetFont(k[3], k[2], "") then
            local font = _G[k[1]]
            local file = font and font.GetFont and font:GetFont()
            if file then fs:SetFont(file, k[2], "") end
        end
    end
    fs:SetTextColor(k[4][1], k[4][2], k[4][3])
    fs:SetJustifyH("LEFT")
    return fs
end

function Wg.Color(fs, c, a) fs:SetTextColor(c[1], c[2], c[3], a or 1) end

---------------------------------------------------------------------------
-- Motion. Everything the window eases goes through here, so the timings are one table and the work is one
-- driver. A Fader eases one number from 0 to 1 and back (a wash's strength, a page's opacity) at a constant
-- rate and hands each value to an apply function that sets an alpha: no geometry, no text, no colors.
-- The driver is a frame whose OnUpdate is set only while a Fader is running and removed when the last one
-- arrives, so nothing runs while the window is idle or shut; steps allocate nothing.
-- "Reduce settings motion" (TwichUIDB.ui.reduceSettingsMotion, the settings window's own; not the
-- notifications' Reduced motion) makes every To() a plain Set(): the state is shown at once.
---------------------------------------------------------------------------
local Motion = {}
Wg.Motion = Motion
Motion.TIME = {             -- seconds
    hover = 0.09,           -- a wash easing in or out under the pointer
    check = 0.09,           -- a checkbox's accent fill
    page = 0.12,            -- the page's content as it arrives
    window = 0.16,          -- the window as it opens
}
Motion.MAX_STEP = 0.1       -- a long frame (a hitch) moves an effect no further than this

function Motion.Enabled()
    local db = TwichUIDB
    return not (type(db) == "table" and type(db.ui) == "table" and db.ui.reduceSettingsMotion == true)
end

local running, runCount, driver = {}, 0, nil
local Fader = {}
Fader.__index = Fader

local function Detach(f)
    if not f.running then return end
    f.running = false
    for i = 1, runCount do
        if running[i] == f then
            running[i] = running[runCount]
            running[runCount] = nil
            runCount = runCount - 1
            break
        end
    end
    if runCount == 0 and driver then driver:SetScript("OnUpdate", nil) end
end

local function Step(_, elapsed)
    if elapsed > Motion.MAX_STEP then elapsed = Motion.MAX_STEP end
    local i = 1
    while i <= runCount do
        local f = running[i]
        local v, goal = f.value, f.goal
        local d = f.rate * elapsed
        if v < goal then v = v + d; if v > goal then v = goal end
        else v = v - d; if v < goal then v = goal end end
        f.value = v
        local ok, err = pcall(f.apply, v)
        if not ok then   -- an effect that fails stops where it is rather than failing every frame
            f.value = goal
            v = goal
            if R.Fault then R.Fault("settings motion", err) end
        end
        if v == goal then
            f.running = false
            running[i] = running[runCount]
            running[runCount] = nil
            runCount = runCount - 1
        else
            i = i + 1
        end
    end
    if runCount == 0 then driver:SetScript("OnUpdate", nil) end
end

-- apply(v) draws value v (0..1). initial: where it starts (default 0), applied at once.
function Motion.Fader(apply, initial)
    initial = initial or 0
    local f = setmetatable({ value = initial, goal = initial, rate = 0, apply = apply, running = false }, Fader)
    apply(initial)
    return f
end

function Fader:Active() return self.running end

-- Puts it at v now, cancelling any easing.
function Fader:Set(v)
    Detach(self)
    self.value, self.goal = v, v
    self.apply(v)
end

-- Eases to goal over `seconds` (the whole 0..1 run; a part of it takes a part of the time). Shown at once
-- where motion is reduced or the time is 0.
function Fader:To(goal, seconds)
    if self.goal == goal and (self.running or self.value == goal) then return end
    if not seconds or seconds <= 0 or not Motion.Enabled() then return self:Set(goal) end
    self.goal = goal
    self.rate = 1 / seconds
    if not self.running then
        self.running = true
        runCount = runCount + 1
        running[runCount] = self
        if runCount == 1 then
            driver = driver or CreateFrame("Frame")
            driver:SetScript("OnUpdate", Step)
        end
    end
end

-- Every effect to where it was going, and the driver off. Called when the window closes and when the
-- preference changes, so nothing is left half-way, dimmed or offset.
function Motion.Settle()
    for i = runCount, 1, -1 do
        local f = running[i]
        running[i] = nil
        f.running = false
        f.value = f.goal
        pcall(f.apply, f.goal)
    end
    runCount = 0
    if driver then driver:SetScript("OnUpdate", nil) end
end

-- For tests: how many effects are easing, and a step of the driver by hand.
function Motion.Count() return runCount end
function Motion.Advance(seconds)
    while seconds > 0 and runCount > 0 do
        local dt = math.min(seconds, Motion.MAX_STEP)
        Step(nil, dt)
        seconds = seconds - dt
    end
end

---------------------------------------------------------------------------
-- Surfaces
---------------------------------------------------------------------------
function Wg.Surface(frame, fill, fillAlpha, edge, edgeAlpha)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(fill[1], fill[2], fill[3], fillAlpha or 1)
    edge = edge or pal.bronzeLo
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edgeAlpha or 1)
end

function Wg.Solid(parent, layer, c, a)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetColorTexture(c[1], c[2], c[3], a or 1)
    return t
end

-- A tonal fade across a texture: color c from alpha `from` at the top (left, for "HORIZONTAL") to alpha `to` at
-- the bottom (right). Gradients are in the client's texture API; where one is refused it is a flat fill of the
-- mean alpha instead, so nothing here depends on it.
function Wg.Fade(tex, c, from, to, orientation)
    tex:SetColorTexture(1, 1, 1, 1)
    if tex.SetGradient and CreateColor then
        local a, b = from, to
        if orientation ~= "HORIZONTAL" then
            orientation = "VERTICAL"
            a, b = to, from      -- vertical gradients run from the bottom color to the top one
        end
        if pcall(tex.SetGradient, tex, orientation, CreateColor(c[1], c[2], c[3], a), CreateColor(c[1], c[2], c[3], b)) then
            return true
        end
    end
    tex:SetColorTexture(c[1], c[2], c[3], (from + to) / 2)
    return false
end

-- 1px lines just inside a frame's edge, each side { color, alpha } or nil. Returns them by side name. Lines
-- are textures: they never take the mouse, and they cost no frame.
function Wg.Shade(frame, top, left, bottom, right, inset, layer)
    inset, layer = inset or 1, layer or "BORDER"
    local lines = {}
    local function Line(side, spec)
        if not spec then return end
        local t = Wg.Solid(frame, layer, spec[1], spec[2])
        if side == "top" or side == "bottom" then
            local edge = side == "top" and "TOP" or "BOTTOM"
            t:SetHeight(1)
            t:SetPoint(edge .. "LEFT", inset, side == "top" and -inset or inset)
            t:SetPoint(edge .. "RIGHT", -inset, side == "top" and -inset or inset)
        else
            local edge = side == "left" and "LEFT" or "RIGHT"
            t:SetWidth(1)
            t:SetPoint("TOP" .. edge, side == "left" and inset or -inset, -(inset + 1))
            t:SetPoint("BOTTOM" .. edge, side == "left" and inset or -inset, inset + 1)
        end
        lines[side] = t
    end
    Line("top", top); Line("left", left); Line("bottom", bottom); Line("right", right)
    return lines
end

-- Pressed into the surface: a shadow along the top and left inside edge, a warm lip along the bottom. For
-- inputs, the checkbox and the section panels; `k` scales it (a panel is gentler than a field).
function Wg.Recess(frame, k)
    k = k or 1
    return Wg.Shade(frame, { pal.ink, 0.42 * k }, { pal.ink, 0.24 * k }, { pal.text, 0.07 * k }, nil, 1)
end

-- A section's card: a surface a step lighter than the window, gently pressed in at its edge.
function Wg.Panel(frame)
    Wg.Surface(frame, pal.surface, 0.85, pal.bronzeLo, 0.20)
    return Wg.Recess(frame, 0.4)
end

-- A flat information tag: a darker chip and quiet text. Not a button: no edge, no raised face, no hover.
function Wg.Tag(parent, text)
    local tag = CreateFrame("Frame", nil, parent)
    tag.bg = Wg.Solid(tag, "BACKGROUND", pal.ink, 0.30)
    tag.bg:SetAllPoints()
    tag.text = Wg.Text(tag, "meta")
    tag.text:SetPoint("CENTER", 0, 0)
    tag.text:SetText(text)
    tag:SetSize(tag.text:GetStringWidth() + 12, 15)
    return tag
end

-- A small down- or up-pointing stepped arrowhead of 1px lines, centred on (x, y) of anchor.
function Wg.Chevron(parent, anchor, point, x, y, down, c)
    local px = {}
    for i = 1, 3 do
        local t = Wg.Solid(parent, "OVERLAY", c or pal.teal, 0.95)
        local width = down and ((4 - i) * 2 - 1) or (i * 2 - 1)
        t:SetSize(width, 1)
        t:SetPoint("CENTER", anchor, point, x, y + (2 - i))
        px[i] = t
    end
    return px
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
function Wg.Button(parent, label, w, kind, onClick)
    local b
    if kind == "danger" then
        b = S.Button(parent, label, w, "secondary", onClick, dangerPal)
    else
        b = S.Button(parent, label, w, kind == "primary" and "primary" or "secondary", onClick, pal)
    end
    b:SetMotionScriptsWhileDisabled(true)
    Wg.Raise(b, kind == "primary" and { 0.96, 0.94, 0.89 } or nil)
    return b
end

-- A wash that eases in under the pointer and out when it leaves: one texture in `c` at `alpha`, faded through
-- Motion. Decorative only (a texture takes no mouse). A disabled control gets none; a press drops it at once
-- and a release returns it to whichever state the pointer is in. Existing scripts are hooked, never replaced.
-- Returns the Fader.
function Wg.Hover(frame, c, alpha, inset)
    inset = inset or 1
    local tex = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    tex:SetColorTexture(c[1], c[2], c[3], alpha)
    tex:SetPoint("TOPLEFT", inset, -inset)
    tex:SetPoint("BOTTOMRIGHT", -inset, inset)
    local fader = Motion.Fader(function(v) tex:SetAlpha(v) end, 0)
    local over = false
    local function Lit() return over and frame:IsEnabled() end
    frame:HookScript("OnEnter", function()
        over = true
        if frame:IsEnabled() then fader:To(1, Motion.TIME.hover) end
    end)
    frame:HookScript("OnLeave", function()
        over = false
        fader:To(0, Motion.TIME.hover)
    end)
    frame:HookScript("OnMouseDown", function() fader:Set(0) end)
    frame:HookScript("OnMouseUp", function() if Lit() then fader:To(1, Motion.TIME.hover) end end)
    frame:HookScript("OnDisable", function() fader:Set(0) end)
    frame:HookScript("OnHide", function() over = false; fader:Set(0) end)
    return fader
end

-- Gives a button a raised face: a lit upper edge (bronze, or `tone`), a darker lower edge and a faint sheen over
-- its top half. It follows the button's own states: lit a little more under the pointer, sunk (the edges swap,
-- the sheen goes) while pressed, flat when disabled. Works on any BackdropTemplate button; the button keeps its
-- own colors.
function Wg.Raise(b, tone)
    local warm = tone or pal.bronzeText
    local sheen = b:CreateTexture(nil, "ARTWORK")
    sheen:SetPoint("TOPLEFT", 1, -1)
    sheen:SetPoint("TOPRIGHT", -1, -1)
    sheen:SetHeight(11)
    Wg.Fade(sheen, pal.text, 0.05, 0)
    local lit = Wg.Solid(b, "ARTWORK", warm, 0.30)
    lit:SetHeight(1)
    lit:SetPoint("TOPLEFT", 1, -1)
    lit:SetPoint("TOPRIGHT", -1, -1)
    local dark = Wg.Solid(b, "ARTWORK", pal.ink, 0.40)
    dark:SetHeight(1)
    dark:SetPoint("BOTTOMLEFT", 1, 1)
    dark:SetPoint("BOTTOMRIGHT", -1, 1)
    local over, down = false, false
    local function Paint()
        local on = b:IsEnabled()
        if not on then
            sheen:Hide()
            lit:SetColorTexture(warm[1], warm[2], warm[3], 0.08)
            dark:SetColorTexture(pal.ink[1], pal.ink[2], pal.ink[3], 0.20)
        elseif down then
            sheen:Hide()
            lit:SetColorTexture(pal.ink[1], pal.ink[2], pal.ink[3], 0.40)
            dark:SetColorTexture(warm[1], warm[2], warm[3], 0.10)
        else
            sheen:Show()
            lit:SetColorTexture(warm[1], warm[2], warm[3], over and 0.42 or 0.30)
            dark:SetColorTexture(pal.ink[1], pal.ink[2], pal.ink[3], 0.40)
        end
    end
    Wg.Hover(b, pal.text, 0.07)
    b:HookScript("OnEnter", function() over = true; Paint() end)
    b:HookScript("OnLeave", function() over, down = false, false; Paint() end)
    b:HookScript("OnMouseDown", function() down = true; Paint() end)
    b:HookScript("OnMouseUp", function() down = false; Paint() end)
    b:HookScript("OnEnable", Paint)
    b:HookScript("OnDisable", Paint)
    b:HookScript("OnHide", function() over, down = false, false end)
    Paint()
    return b
end

-- A small square button with an arrowhead (move up / move down in a ranked list).
function Wg.ArrowButton(parent, dir, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    Wg.Surface(b, pal.well, 1, pal.control, 1)
    local px = Wg.Chevron(b, b, "CENTER", 0, 0, dir == "down")
    local function Paint()
        local on = b:IsEnabled()
        for _, t in ipairs(px) do t:SetAlpha(on and 1 or 0.3) end
        local edge = (on and b:IsMouseOver()) and pal.tealHi or pal.control
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end
    b:SetScript("OnEnable", Paint)
    b:SetScript("OnDisable", Paint)
    b:HookScript("OnEnter", Paint)
    b:HookScript("OnLeave", Paint)
    b:SetScript("OnClick", onClick)
    b:SetMotionScriptsWhileDisabled(true)
    Paint()
    return b
end

---------------------------------------------------------------------------
-- Checkbox: an inset square with a gold mark. SetChecked / GetChecked / SetActive(enabled).
---------------------------------------------------------------------------
function Wg.Checkbox(parent, onToggle)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(18, 18)
    Wg.Surface(b, pal.well, 1, pal.control, 0.95)
    Wg.Recess(b, 1.2)
    local fill = Wg.Solid(b, "ARTWORK", pal.tealLo, 1)           -- checked: a muted teal interior
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    local mark = b:CreateTexture(nil, "OVERLAY")
    mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    if mark.SetDesaturated then mark:SetDesaturated(true) end   -- so the tint below is a clean ivory
    mark:SetPoint("CENTER", 0, 0)
    mark:SetSize(20, 20)
    local checked, active, over = false, true, false
    -- The mark and the setting change at once. The teal interior eases in or out over a moment when the box is
    -- on screen (a change you make), and is simply there when a page is drawn.
    local glow = Motion.Fader(function(v) fill:SetAlpha(v) end, 0)
    local function Paint()
        mark:SetShown(checked)
        fill:SetShown(true)
        fill:SetColorTexture(pal.tealLo[1], pal.tealLo[2], pal.tealLo[3], active and 1 or 0.55)
        local c = active and pal.text or pal.stone
        mark:SetVertexColor(c[1], c[2], c[3], active and 1 or 0.6)
        local edge = not active and pal.bronzeLo or ((over or checked) and pal.teal or pal.control)
        if over and active then edge = pal.tealHi end
        b:SetBackdropBorderColor(edge[1], edge[2], edge[3], active and 0.95 or 0.6)
    end
    function b:SetChecked(v)
        v = v and true or false
        local changed = v ~= checked
        checked = v
        Paint()
        if changed and b:IsVisible() then glow:To(v and 1 or 0, Motion.TIME.check) else glow:Set(v and 1 or 0) end
    end
    function b:GetChecked() return checked end
    function b:SetActive(v) active = v and true or false; Paint() end
    function b:SetHot(v) over = v and true or false; Paint() end
    b:SetScript("OnEnter", function() over = true; Paint() end)
    b:SetScript("OnLeave", function() over = false; Paint() end)
    b:SetScript("OnClick", function()
        if not active then return end
        if onToggle then onToggle(not checked) end
    end)
    Paint()
    return b
end

---------------------------------------------------------------------------
-- Edit box: an inset field. Plain text in and out.
---------------------------------------------------------------------------
function Wg.EditBox(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(w, h or 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject("GameFontHighlightSmall")
    eb:SetTextInsets(6, 6, 0, 0)
    Wg.Surface(eb, pal.well, 1, pal.control, 1)
    Wg.Recess(eb)
    -- keyboard focus: a teal edge and a faint inner ring (the only thing in the window that takes the keys)
    local ring = Wg.Shade(eb, { pal.teal, 0.35 }, { pal.teal, 0.35 }, { pal.teal, 0.35 }, { pal.teal, 0.35 }, 1, "OVERLAY")
    local function Edge()
        local focused = eb:HasFocus()
        local c = focused and pal.teal or (eb:IsMouseOver() and pal.tealHi or pal.control)
        eb:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        for _, line in pairs(ring) do line:SetShown(focused) end
    end
    eb:HookScript("OnEditFocusGained", Edge)
    eb:HookScript("OnEditFocusLost", Edge)
    eb:HookScript("OnEnter", Edge)
    eb:HookScript("OnLeave", Edge)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnEnterPressed", eb.ClearFocus)
    eb.PaintEdge = Edge
    Edge()
    return eb
end

---------------------------------------------------------------------------
-- The window's own frame: a two-pixel bronze rim, lit along the top and left and shaded along the bottom and
-- right, a dark line and a faint lit line inside it, small L-shaped brackets in the corners, and tonal layers
-- (a warm light at the top, a settling shade at the bottom) over a very light speckle. Textures only; nothing
-- here runs per frame or takes the mouse. (chronicle/Style.lua's S.Frame is the Chronicle's and stays as it is.)
---------------------------------------------------------------------------
local function Bracket(f, corner, inset, len, c, a)
    local right, top = corner:find("RIGHT") ~= nil, corner:find("TOP") ~= nil
    local x = right and -inset or inset
    local y = top and -inset or inset
    local h = Wg.Solid(f, "ARTWORK", c, a)
    h:SetSize(len, 1)
    h:SetPoint(corner, x, y)
    local v = Wg.Solid(f, "ARTWORK", c, a)
    v:SetSize(1, len)
    v:SetPoint(corner, x, y)
    return h, v
end

function Wg.Frame(f, w, h, headerH)
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    f:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], 0.98)
    f:SetBackdropBorderColor(pal.ink[1], pal.ink[2], pal.ink[3], 1)
    -- the pieces are kept (f.twichShell) so a window whose look the player sets can hide the rim, or the grain
    local rim, tone = {}, {}
    local function Keep(into, lines) for _, t in pairs(lines) do into[#into + 1] = t end end
    Keep(rim, Wg.Shade(f, { pal.bronzeHi, 0.95 }, { pal.bronzeHi, 0.80 }, { pal.bronze, 0.90 }, { pal.bronze, 0.90 }, 1))
    Keep(rim, Wg.Shade(f, { pal.bronze, 0.90 }, { pal.bronze, 0.80 }, { pal.rimLo, 0.95 }, { pal.rimLo, 0.95 }, 2))
    Keep(rim, Wg.Shade(f, { pal.ink, 0.60 }, { pal.ink, 0.50 }, { pal.ink, 0.40 }, { pal.ink, 0.45 }, 3))
    Keep(rim, Wg.Shade(f, { pal.gold, 0.12 }, { pal.gold, 0.05 }, { pal.ink, 0.22 }, { pal.ink, 0.22 }, 4))
    for _, corner in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local a, b = Bracket(f, corner, 6, 8, pal.gold, 0.5)
        rim[#rim + 1], rim[#rim + 2] = a, b
    end
    -- tonal layers: light falls from the top, the bottom settles
    local top = f:CreateTexture(nil, "BACKGROUND")
    top:SetPoint("TOPLEFT", 5, -(headerH + 5))
    top:SetPoint("TOPRIGHT", -5, -(headerH + 5))
    top:SetHeight(170)
    Wg.Fade(top, pal.text, 0.04, 0)
    local bottom = f:CreateTexture(nil, "BACKGROUND")
    bottom:SetPoint("BOTTOMLEFT", 5, 5)
    bottom:SetPoint("BOTTOMRIGHT", -5, 5)
    bottom:SetHeight(120)
    Wg.Fade(bottom, pal.ink, 0, 0.30)
    tone[1], tone[2] = top, bottom
    -- a light grain, a third of the Chronicle's
    Keep(tone, S.Speckle(f, w, h, math.floor(w * h / 7500)))
    f.twichShell = { rim = rim, tone = tone }
end

-- Shows or hides the rim (the bronze edge and its corner brackets) and the tonal layers and grain that
-- Wg.Frame drew. For a window whose background and border the player sets; nothing else of the frame changes.
function Wg.ShellParts(f, rim, tone)
    local shell = f and f.twichShell
    if not shell then return end
    for _, t in ipairs(shell.rim) do t:SetShown(rim and true or false) end
    for _, t in ipairs(shell.tone) do t:SetShown(tone and true or false) end
end

-- The title band: a surface a step above the window with a warm sheen along its top, a slight settling toward
-- its bottom, and a fine separator (a bronze line over a dark one) below.
function Wg.Header(f, height)
    local band = Wg.Solid(f, "BACKGROUND", pal.band, 1)
    band:SetPoint("TOPLEFT", 4, -4)
    band:SetPoint("TOPRIGHT", -4, -4)
    band:SetHeight(height)
    local settle = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    settle:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
    settle:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", 0, 0)
    Wg.Fade(settle, pal.ink, 0, 0.22)
    local sheen = Wg.Solid(f, "BORDER", pal.text, 0.06)
    sheen:SetHeight(1)
    sheen:SetPoint("TOPLEFT", band, "TOPLEFT", 0, 0)
    sheen:SetPoint("TOPRIGHT", band, "TOPRIGHT", 0, 0)
    local line = Wg.Solid(f, "BORDER", pal.bronze, 0.85)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    local shadow = Wg.Solid(f, "BORDER", pal.ink, 0.45)
    shadow:SetHeight(1)
    shadow:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, 0)
    shadow:SetPoint("TOPRIGHT", line, "BOTTOMRIGHT", 0, 0)
    f.twichBand = band   -- the rest of the band is anchored to it: moving it moves the band
    return band
end


-- The game's MinimalScrollBar (a ScrollBox's bar), tinted into the palette: its track a quiet neutral and its
-- thumb ivory. Its own art and behavior are untouched; only vertex colors change. Nothing happens if the bar
-- isn't the shape expected.
function Wg.MinimalScrollBar(bar)
    local track = type(bar) == "table" and bar.Track
    if type(track) ~= "table" then return end
    local function Tint(parts, c, a)
        for _, key in ipairs({ "Begin", "Middle", "End" }) do
            local t = parts[key]
            if type(t) == "table" and t.SetVertexColor then t:SetVertexColor(c[1], c[2], c[3], a) end
        end
    end
    Tint(track, pal.control, 0.65)
    if type(track.Thumb) == "table" then Tint(track.Thumb, pal.text, 0.85) end
end

---------------------------------------------------------------------------
-- Pieces for a window's own chrome (the sharing window and its popups).
---------------------------------------------------------------------------
-- A recessed list or text area: a field's dark interior, pressed in.
function Wg.Well(frame, alpha)
    Wg.Surface(frame, pal.well, alpha or 0.9, pal.bronzeLo, 0.8)
    return Wg.Recess(frame, 0.8)
end

-- A card drawn as textures on `parent`, behind whatever else the parent holds (a frame would cover the parent's
-- own text): the section card's surface with a faint edge and a pressed-in lip. x1,y1 and x2,y2 are the
-- corners measured from the parent's top left (y runs negative downward).
function Wg.Card(parent, x1, y1, x2, y2)
    local function Piece(layer, c, a, ax, ay, bx, by)
        local t = Wg.Solid(parent, layer, c, a)
        t:SetPoint("TOPLEFT", parent, "TOPLEFT", ax, ay)
        t:SetPoint("BOTTOMRIGHT", parent, "TOPLEFT", bx, by)
        return t
    end
    Piece("BACKGROUND", pal.surface, 0.85, x1, y1, x2, y2)
    Piece("BORDER", pal.bronzeLo, 0.20, x1, y1, x2, y1 - 1)       -- edge
    Piece("BORDER", pal.bronzeLo, 0.20, x1, y2 + 1, x2, y2)
    Piece("BORDER", pal.bronzeLo, 0.20, x1, y1, x1 + 1, y2)
    Piece("BORDER", pal.bronzeLo, 0.20, x2 - 1, y1, x2, y2)
    Piece("BORDER", pal.ink, 0.21, x1 + 1, y1 - 1, x2 - 1, y1 - 2)   -- pressed in: shadow above and left,
    Piece("BORDER", pal.ink, 0.12, x1 + 1, y1 - 2, x1 + 2, y2 + 2)  -- a faint lip below
    Piece("BORDER", pal.text, 0.035, x1 + 1, y2 + 2, x2 - 1, y2 + 1)
end

-- A window or popup's shell: the rim, brackets and tonal layers, an optional title band of headerH pixels, and
-- a fade-in as it opens (opacity only; a window that is shown again after closing starts the fade again).
function Wg.Shell(frame, headerH)
    local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
    Wg.Frame(frame, w, h, headerH or 0)
    if headerH and headerH > 0 then Wg.Header(frame, headerH) end
    local fade = Motion.Fader(function(a) frame:SetAlpha(a) end, 1)
    frame:HookScript("OnShow", function()
        if Motion.Enabled() then
            fade:Set(0)
            fade:To(1, Motion.TIME.window)
        else
            fade:Set(1)
        end
    end)
    frame:HookScript("OnHide", function() fade:Set(1) end)
    return frame
end

-- The small bronze-edged close box, raised, in the top right corner of `frame`.
function Wg.CloseBox(frame, onClick)
    local b = S.Close(frame, onClick or function() frame:Hide() end, pal)
    b:SetPoint("TOPRIGHT", -10, -11)
    Wg.Raise(b)
    return b
end

-- A tab: quiet text with a wash under the pointer; the selected one is ivory with a faint bronze fill and a
-- bronze bar on its bottom edge (the label never moves). b:SetSelected(bool). It is a plain button (no
-- Blizzard template, whose art repaints on every click).
function Wg.Tab(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 130, 26)
    b.text = Wg.Text(b, "body")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    local washTex = Wg.Solid(b, "BACKGROUND", pal.text, 0.05)
    washTex:SetAllPoints()
    local wash = Motion.Fader(function(v) washTex:SetAlpha(v) end, 0)
    b.fill = Wg.Solid(b, "BACKGROUND", pal.bronzeText, 0.11)   -- the shown tab: a warm tint, not a box
    b.fill:SetAllPoints()
    b.bar = Wg.Solid(b, "ARTWORK", pal.bronzeText, 1)
    b.bar:SetHeight(2)
    b.bar:SetPoint("BOTTOMLEFT", 0, 0)
    b.bar:SetPoint("BOTTOMRIGHT", 0, 0)
    local selected = false
    local function Paint()
        b.bar:SetShown(selected)
        b.fill:SetShown(selected)
        Wg.Color(b.text, selected and pal.text or pal.textDim)
    end
    function b:SetSelected(on) selected = on and true or false; Paint() end
    b:SetScript("OnEnter", function()
        if not selected then wash:To(1, Motion.TIME.hover) end
        Wg.Color(b.text, pal.text)
    end)
    b:SetScript("OnLeave", function() wash:To(0, Motion.TIME.hover); Paint() end)
    b:SetScript("OnHide", function() wash:Set(0); Paint() end)
    b:SetScript("OnClick", onClick)
    Paint()
    return b
end

---------------------------------------------------------------------------
-- A scroll bar in this look: Style.lua's slim bar with quiet arrowheads, and a thumb that answers the pointer
-- (lighter under it, teal while dragged). The scrolling is the template's own.
---------------------------------------------------------------------------
function Wg.ScrollBar(scroll)
    S.ScrollBar(scroll, barPal)
    local bar = scroll and scroll.ScrollBar
    local thumb = type(bar) == "table" and (bar.ThumbTexture or (bar.GetThumbTexture and bar:GetThumbTexture()))
    if thumb and bar.HookScript then
        local over, drag = false, false
        local function Paint()
            local c, a = pal.thumb, 0.85
            if drag then c, a = pal.teal, 0.95 elseif over then c, a = pal.control, 0.95 end
            thumb:SetColorTexture(c[1], c[2], c[3], a)
        end
        bar:HookScript("OnEnter", function() over = true; Paint() end)
        bar:HookScript("OnLeave", function() over = false; Paint() end)
        bar:HookScript("OnMouseDown", function() drag = true; Paint() end)
        bar:HookScript("OnMouseUp", function() drag = false; Paint() end)
    end
end
