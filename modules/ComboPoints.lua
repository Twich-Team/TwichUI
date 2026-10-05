-- TwichUI: Combo points
-- The combo points on your target, for Rogues: pips, a thin segmented bar or a number, in a
-- place of the player's choosing. It only shows what the game reports and never acts.
-- The count is the game's own read, GetComboPoints("player", "target"), the one the game's
-- target-frame combo points (ComboFrame) use in WoW: Forever; the number of points is
-- UnitPowerMax("player", ComboPoints), with the last good value (or 5, before there is one) when
-- the game gives nothing usable. Both are marked as possibly secret in the client's API docs.
-- A secret count is never compared in Lua: each point is a one-point StatusBar
-- (SetMinMaxValues(i - 1, i), then SetValue(count)), so the game itself fills the right ones, the
-- number is SetText as given, "When I have points" shows whenever there is an enemy targeted, and
-- the gain and full-points touches are skipped.
-- Updated by events only: the target changing, the player's combo points and their cap, the
-- target dying, combat and death. No OnUpdate.
-- Touches, all optional (Animation; Reduced motion keeps them subtle and drops the mist, which
-- moves): a light on a point gained, spent points fading out, a rule under the points when they're
-- full, a short fade when the display hides, and a poison mist (media\textures\mist, TwichUI's own
-- art, from tools/make_mist_texture.py): a puff when the points are full, or a faint drift behind
-- them while you have any. Animation groups only, so the game runs them; the drift loops only
-- while it is wanted.
-- Moved in Edit Mode, with an outline as for the Food and Drink buttons. EllesmereUI's Unlock
-- Mode has no documented API for other addons' frames (its Plugin API covers options pages only),
-- so it isn't used. Optionally hides the game's own combo points beside the target portrait by
-- parking ComboFrame under a hidden frame of ours, out of combat, and gives it back when turned off.
-- Saved in TwichUIDB.ui.comboPoints and TwichUIDB.ui.comboPointsPosition (for all characters).

local R = TwichUI
local C = {}
R.ComboPoints = C

local DEFAULT_X, DEFAULT_Y = 0, -170   -- from the centre of the screen
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- the game's own circle mask
local MOVER_ATLAS = "editmode-actionbar-highlight-NineSlice-Center"
local COMBO_POWER = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4   -- 4 in the client's PowerType docs
local MAX_POINTS = 10        -- the most points laid out (the game's own frame has nine)
local FALLBACK_MAX = 5       -- only until the game gives a cap it can read
local PAD = 4                -- room round the points for the backing and the full-points rule
local PREVIEW_STEP, PREVIEW_HOLD = 0.35, 2.5   -- seconds
local FLASH = 0.25           -- seconds: the light on a point gained
local FULL_IN, FULL_OUT = 0.1, 0.45   -- seconds: the rule under the points when they're full
local SPEND = 0.35           -- seconds: a spent point fading
local FADE_OUT = 0.3         -- seconds: the display going away
local SAMPLE = 3             -- points shown in Edit Mode
local MIST = R.PATH .. [[media\textures\mist]]
local WISPS = 5              -- wisps of mist
local MIST_TIME = { 2.8, 3.4, 3.0, 3.7, 3.2 }   -- seconds each wisp takes; unequal, so they drift apart
local MIST_DELAY = { 0, 0.9, 0.4, 1.4, 0.7 }    -- and start apart

-- Each look is a set of colours ("AARRGGBB"). background is a backing behind the points; a look
-- with a clear one has none. accent is the full-points rule. sheen: the etched top edge's strength.
C.THEMES = {
    { key = "bronze", label = "Bronze", tooltip = "Warm gold points in dark bronze wells. The default.",
      active = "fff0c76b", inactive = "ff3b3020", border = "ff15100a", background = "001c150e", accent = "ffd7b45a", sheen = 0.22 },
    { key = "brass", label = "Etched brass", tooltip = "Brass points with a brighter etched edge, each in a bronze rim.",
      active = "ffe6c178", inactive = "ff362b1c", border = "ff8c6e38", background = "001c150e", accent = "ffd7b45a", sheen = 0.45 },
    { key = "leather", label = "Leather and bronze", tooltip = "The points on a strip of dark leather edged in bronze.",
      active = "fff0c76b", inactive = "ff3b3020", border = "ff15100a", background = "f2302216", accent = "ffd7b45a", sheen = 0.22 },
    { key = "poison", label = "Poison", tooltip = "Muted poison-green points; wells and rims stay bronze.",
      active = "ff8fb35a", inactive = "ff27301d", border = "ff15100a", background = "001c150e", accent = "ffb3cf7c", sheen = 0.2 },
}
local THEME = {}
for _, theme in ipairs(C.THEMES) do THEME[theme.key] = theme end

C.DEFAULTS = {
    style = "pips", theme = "bronze", visibility = "points",
    orientation = "horizontal", direction = "forward", shape = "square",
    pipSize = 14, barLength = 150, barHeight = 6, numberSize = 28, spacing = 3,
    scale = 100, opacity = 100, animation = "full",
    -- border textures: "solid", a LibSharedMedia border or "eui:<key>" (see modules/Borders.lua)
    pointBorder = true, pointBorderSize = 1, pointBorderTexture = "solid",
    frameBorder = false, frameBorderSize = 1, frameBorderColor = "ff8c6e38", frameBorderTexture = "solid",   -- the Chronicle's bronze
    mist = "off", mistColor = "ff7fa857",
    customColors = false,
    font = "Cinzel", outline = "OUTLINE", shadow = true,
}
C.LIMITS = { pipSize = { 6, 40 }, barLength = { 40, 400 }, barHeight = { 2, 24 }, numberSize = { 10, 64 },
    spacing = { 0, 20 }, scale = { 50, 200 }, opacity = { 10, 100 }, pointBorderSize = { 1, 32 }, frameBorderSize = { 1, 32 } }
C.CHOICES = {
    style = { pips = true, bar = true, number = true },
    visibility = { points = true, target = true, combat = true, always = true },
    mist = { off = true, full = true, points = true },
    orientation = { horizontal = true, vertical = true },
    direction = { forward = true, reverse = true },
    shape = { square = true, round = true },
    animation = { full = true, subtle = true, off = true },
    outline = { NONE = true, OUTLINE = true, THICKOUTLINE = true },
}
-- The colour settings that start as the look's, and the part of the look each one replaces. The
-- point border's is used whenever it is set; the rest only with Use my own colors.
C.COLORS = { activeColor = "active", inactiveColor = "inactive", borderColor = "border", backgroundColor = "background" }
local HEX = { frameBorderColor = true, mistColor = true }   -- colours with a fixed default
local BOOLEANS = { customColors = true, shadow = true, pointBorder = true, frameBorder = true }
local TEXTURES = { pointBorderTexture = true, frameBorderTexture = true }
local Borders = R.Borders   -- the border textures, shared with the Food and Drink buttons

local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function InCombat() return InCombatLockdown and InCombatLockdown() end

---------------------------------------------------------------------------
-- Settings. Read through C.Get, which falls back to the default (or, for a colour, the look's)
-- for anything missing or invalid, so a bad saved value can't break the display.
---------------------------------------------------------------------------
local function Valid(key, value)
    local limit = C.LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif C.CHOICES[key] then return type(value) == "string" and C.CHOICES[key][value] == true
    elseif key == "theme" then return type(value) == "string" and THEME[value] ~= nil
    elseif C.COLORS[key] or HEX[key] then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif BOOLEANS[key] then return type(value) == "boolean"
    elseif TEXTURES[key] then return Borders.ValidName(value)
    elseif key == "font" then return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]") end
    return false
end

local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    return type(ui) == "table" and type(ui.comboPoints) == "table" and ui.comboPoints or nil
end

function C.Get(key)
    local saved = Saved()
    local value = saved and saved[key]
    if Valid(key, value) then return value end
    if C.COLORS[key] then return THEME[C.Get("theme")][C.COLORS[key]] end
    return C.DEFAULTS[key]
end

local Redraw   -- below

-- How a new border texture is given a thickness and colour that suit it (Borders.Reseed), for
-- each border: its size and colour settings, and what a texture needs on a point or round it all.
local RESEED = {
    pointBorderTexture = { size = "pointBorderSize", color = "borderColor",
        rules = { defaultSize = 1, solidMax = 6, texturedMin = 6, texturedSeed = 8, maxSize = 32 } },
    frameBorderTexture = { size = "frameBorderSize", color = "frameBorderColor",
        rules = { defaultSize = 1, solidMax = 6, texturedMin = 8, texturedSeed = 12, maxSize = 32 } },
}

-- Saves one setting (an invalid value is refused) and redraws.
function C.Set(key, value)
    if not Valid(key, value) then return false end
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.comboPoints = TwichUIDB.ui.comboPoints or {}
    local saved = TwichUIDB.ui.comboPoints
    local reseed = RESEED[key]
    if reseed then
        -- the colour a plain line starts with: the look's for the points, bronze round it all
        local default = key == "pointBorderTexture" and THEME[C.Get("theme")].border or C.DEFAULTS.frameBorderColor
        reseed.rules.defaultColor = default
        local size, color = C.Get(reseed.size), C.Get(reseed.color)
        local newSize, newColor = Borders.Reseed(C.Get(key), value, size, color, reseed.rules)
        if newSize ~= size then saved[reseed.size] = newSize end
        if newColor ~= color then saved[reseed.color] = newColor ~= default and newColor or nil end
    end
    saved[key] = value
    Redraw()
    return true
end

-- { { value, label }, ... } for a border texture choice (key: pointBorderTexture or frameBorderTexture).
function C.TextureChoices(key) return Borders.Choices(C.Get(key)) end

-- Forgets the colours chosen, so they follow the look again.
function C.ClearColors()
    local saved = Saved()
    if not saved then return end
    for key in pairs(C.COLORS) do saved[key] = nil end
    Redraw()
end

-- "AARRGGBB" as r, g, b, a in 0-1.
function C.ParseColor(hex)
    if not Valid("activeColor", hex) then return nil end
    local function part(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
    return part(3), part(5), part(7), part(1)
end

-- The colours in use: the look's, or the player's own with Use my own colors on.
local function Colors()
    local theme = THEME[C.Get("theme")]
    local custom = C.Get("customColors")
    local out = { sheen = theme.sheen }
    local function Put(part, hex) local r, g, b, a = C.ParseColor(hex); out[part] = { r, g, b, a } end
    for key, part in pairs(C.COLORS) do Put(part, custom and C.Get(key) or theme[part]) end
    Put("border", C.Get("borderColor"))   -- the look's, or the one chosen for it
    Put("accent", theme.accent)
    Put("frame", C.Get("frameBorderColor"))
    Put("mist", C.Get("mistColor"))
    return out
end

local function SharedMedia() return LibStub and LibStub("LibSharedMedia-3.0", true) end

-- The number's font file: LibSharedMedia's, else one of TwichUI's own (registered or not), else the game's.
local function FontPath()
    local name = C.Get("font")
    local LSM = SharedMedia()
    local path = LSM and LSM:Fetch("font", name, true)
    if type(path) == "string" and path ~= "" then return path end
    local file = R.MediaFonts and R.MediaFonts[name]
    if file then return R.PATH .. [[media\fonts\]] .. file end
    return STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]]
end

-- { { value, label }, ... } for the font choice: every LibSharedMedia font, sorted, with TwichUI's
-- own always there; the current choice stays listed if it has gone.
function C.FontChoices()
    local names, seen = {}, {}
    local LSM = SharedMedia()
    for name in pairs(LSM and LSM:HashTable("font") or {}) do
        if Valid("font", name) then names[#names + 1] = name; seen[name] = true end
    end
    for name in pairs(R.MediaFonts or {}) do
        if not seen[name] then names[#names + 1] = name; seen[name] = true end
    end
    table.sort(names)
    local list = {}
    for _, name in ipairs(names) do list[#list + 1] = { name, name } end
    local current = C.Get("font")
    if not seen[current] then list[#list + 1] = { current, current .. " (not available)" } end
    return list
end

---------------------------------------------------------------------------
-- Where it goes: the centre's offset from the centre of the screen, as moved in Edit Mode.
---------------------------------------------------------------------------
local function Offset(n) return type(n) == "number" and n == n and n > -10000 and n < 10000 end

function C.Position()
    local saved = TwichUIDB and TwichUIDB.ui and TwichUIDB.ui.comboPointsPosition
    if type(saved) == "table" and Offset(saved.x) and Offset(saved.y) then return saved.x, saved.y end
    return DEFAULT_X, DEFAULT_Y
end

-- scale: the frame's own scale; its offsets are in its own units.
local function Place(frame, scale)
    local x, y = C.Position()
    scale = scale or 1
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
end

---------------------------------------------------------------------------
-- The display. A plain frame that takes no clicks; nothing here is protected, so it can be
-- shown, hidden and redrawn in combat.
---------------------------------------------------------------------------
local container, number, numberPulse, numberFade, full, fullIn, fullOut
local backing, ruleA, ruleB
local edges = {}               -- the border round the whole display as a plain line: top, bottom, left, right
local frameBorders = {}        -- ... or as a texture (Borders.Draw's frames)
local wisps = {}               -- the poison mist
local mistLooping = false
local outro, outroFade         -- the display fading away
local fadingOut = false
local segments = {}
local mover
local events
local active = false           -- on, for a Rogue, with the game's API present
local maxPoints                -- points laid out
local last                     -- the count last drawn, when it was plain; nil after a secret one
local quietNext = false        -- the next draw is a new target or a fresh start: no gain touches
local maxDirty = true          -- read the cap again on the next draw
local targetDead = false
local editing = false
local previewCount, previewToken = nil, 0
local paint                    -- Colors(), as of the last layout
local editHooked = false

local function IsRogue()
    local _, class = UnitClass("player")
    return class == "ROGUE"
end

-- Whether this character gets the display at all (the options page asks).
function C.ForPlayer() return IsRogue() end

local function NewSegment()
    local seg = CreateFrame("Frame", nil, container)
    -- The point's border: a plate behind it, drawn by the display itself so a thick one can
    -- never cover a neighbouring point (a frame's own textures sit under its children).
    seg.rim = container:CreateTexture(nil, "BACKGROUND", nil, 2)
    seg.well = seg:CreateTexture(nil, "BACKGROUND", nil, 3)
    seg.well:SetAllPoints()
    seg.bar = CreateFrame("StatusBar", nil, seg)
    seg.bar:SetAllPoints()
    seg.bar:SetStatusBarTexture(WHITE)
    seg.fill = seg.bar:GetStatusBarTexture()
    seg.sheen = seg.bar:CreateTexture(nil, "OVERLAY", nil, 1)
    seg.flash = seg.bar:CreateTexture(nil, "OVERLAY", nil, 2)
    seg.flash:SetAllPoints()
    seg.flash:SetBlendMode("ADD")
    seg.flash:SetAlpha(0)
    seg.flashGroup = seg.flash:CreateAnimationGroup()
    seg.flashFade = seg.flashGroup:CreateAnimation("Alpha")
    seg.flashFade:SetToAlpha(0)
    seg.flashFade:SetDuration(FLASH)
    seg.flashFade:SetSmoothing("OUT")
    -- a spent point: its colour lingers over the empty well and fades
    seg.ghost = seg.bar:CreateTexture(nil, "ARTWORK", nil, 1)
    seg.ghost:SetAllPoints(seg)
    seg.ghost:SetAlpha(0)
    seg.ghostGroup = seg.ghost:CreateAnimationGroup()
    seg.ghostFade = seg.ghostGroup:CreateAnimation("Alpha")
    seg.ghostFade:SetToAlpha(0)
    seg.ghostFade:SetDuration(SPEND)
    seg.ghostFade:SetSmoothing("IN")
    seg.inner = { seg.well, seg.fill, seg.sheen, seg.flash, seg.ghost }
    return seg
end

-- Round points: the game's circle mask over the point and its rim. Made on first use.
local function Round(seg, on)
    on = on and true or false
    if on == (seg.round or false) then return end
    if on and not seg.mask then
        seg.mask = seg.bar:CreateMaskTexture()
        seg.mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        seg.mask:SetAllPoints(seg)
        seg.rimMask = container:CreateMaskTexture()   -- with the rim, on the display
        seg.rimMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        seg.rimMask:SetAllPoints(seg.rim)
    end
    for _, t in ipairs(seg.inner) do
        if on then t:AddMaskTexture(seg.mask) else t:RemoveMaskTexture(seg.mask) end
    end
    if on then seg.rim:AddMaskTexture(seg.rimMask) else seg.rim:RemoveMaskTexture(seg.rimMask) end
    seg.round = on
end

-- edge: the point border's thickness, 0 for none.
local function Paint(seg, vertical, round, edge)
    local k = paint
    seg.rim:SetColorTexture(k.border[1], k.border[2], k.border[3], k.border[4])
    seg.rim:ClearAllPoints()
    seg.rim:SetPoint("TOPLEFT", seg, "TOPLEFT", -edge, edge)
    seg.rim:SetPoint("BOTTOMRIGHT", seg, "BOTTOMRIGHT", edge, -edge)
    seg.rim:SetShown(edge > 0)
    seg.ghost:SetColorTexture(k.active[1], k.active[2], k.active[3], 1)
    seg.well:SetColorTexture(k.inactive[1], k.inactive[2], k.inactive[3], k.inactive[4])
    seg.bar:SetStatusBarColor(k.active[1], k.active[2], k.active[3], k.active[4])
    -- the etched edge rides the fill, so an empty point has none
    seg.sheen:SetColorTexture(1, 0.96, 0.82, k.sheen)
    seg.sheen:ClearAllPoints()
    if vertical then
        seg.sheen:SetPoint("TOPLEFT", seg.fill, "TOPLEFT")
        seg.sheen:SetPoint("BOTTOMLEFT", seg.fill, "BOTTOMLEFT")
        seg.sheen:SetWidth(1)
    else
        seg.sheen:SetPoint("TOPLEFT", seg.fill, "TOPLEFT")
        seg.sheen:SetPoint("TOPRIGHT", seg.fill, "TOPRIGHT")
        seg.sheen:SetHeight(1)
    end
    seg.flash:SetColorTexture(k.accent[1], k.accent[2], k.accent[3], 1)
    Round(seg, round)
end

-- One half of the full-points rule: clear at its outer end, the accent at the middle.
local function Taper(t, orientation, outerFirst)
    local c = paint.accent
    t:SetTexture(WHITE)
    if t.SetGradient and CreateColor then
        local clear, solid = CreateColor(c[1], c[2], c[3], 0), CreateColor(c[1], c[2], c[3], 1)
        if outerFirst then t:SetGradient(orientation, clear, solid) else t:SetGradient(orientation, solid, clear) end
    else
        t:SetVertexColor(c[1], c[2], c[3], 0.6)
    end
end

local function Build()
    if container then return end
    container = CreateFrame("Frame", nil, UIParent)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)
    container:Hide()
    backing = container:CreateTexture(nil, "BACKGROUND", nil, -2)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        edges[side] = container:CreateTexture(nil, "BACKGROUND", nil, -1)
    end
    edges.top:SetPoint("TOPLEFT"); edges.top:SetPoint("TOPRIGHT")
    edges.bottom:SetPoint("BOTTOMLEFT"); edges.bottom:SetPoint("BOTTOMRIGHT")
    edges.left:SetPoint("TOPLEFT"); edges.left:SetPoint("BOTTOMLEFT")
    edges.right:SetPoint("TOPRIGHT"); edges.right:SetPoint("BOTTOMRIGHT")
    -- Poison mist: soft wisps behind the points (over the backing, under the point borders) that
    -- swell, rise a little and thin away. Invisible unless playing.
    for i = 1, WISPS do
        local wisp = container:CreateTexture(nil, "BACKGROUND", nil, 0)
        wisp:SetTexture(MIST)
        if i % 2 == 0 then wisp:SetTexCoord(1, 0, 0, 1) end   -- mirrored, so neighbours differ
        wisp:SetAlpha(0)
        local group = wisp:CreateAnimationGroup()
        local time, delay = MIST_TIME[i], MIST_DELAY[i]
        wisp.drift = group:CreateAnimation("Translation")
        wisp.drift:SetDuration(time); wisp.drift:SetStartDelay(delay); wisp.drift:SetSmoothing("OUT")
        wisp.swell = group:CreateAnimation("Scale")
        wisp.swell:SetScaleFrom(0.8, 0.8); wisp.swell:SetScaleTo(1.3, 1.3)
        wisp.swell:SetDuration(time); wisp.swell:SetStartDelay(delay)
        wisp.rise = group:CreateAnimation("Alpha")
        wisp.rise:SetFromAlpha(0); wisp.rise:SetDuration(time * 0.35); wisp.rise:SetStartDelay(delay)
        wisp.rise:SetSmoothing("OUT")
        wisp.thin = group:CreateAnimation("Alpha")
        wisp.thin:SetToAlpha(0); wisp.thin:SetDuration(time * 0.65); wisp.thin:SetStartDelay(delay + time * 0.35)
        wisp.thin:SetSmoothing("IN")
        wisp.group = group
        wisps[i] = wisp
    end
    outro = container:CreateAnimationGroup()
    outroFade = outro:CreateAnimation("Alpha")
    outroFade:SetToAlpha(0)
    outroFade:SetDuration(FADE_OUT)
    outroFade:SetSmoothing("IN")
    outro:SetScript("OnFinished", function()
        fadingOut = false
        container:Hide()
    end)
    number = container:CreateFontString(nil, "OVERLAY")
    number:SetPoint("CENTER")
    numberPulse = number:CreateAnimationGroup()
    numberFade = numberPulse:CreateAnimation("Alpha")
    numberFade:SetToAlpha(1)
    numberFade:SetDuration(FLASH)
    numberFade:SetSmoothing("OUT")
    -- The full-points rule: a thin line under the points (beside them when stacked), tapered at
    -- both ends, that brightens once and fades.
    full = CreateFrame("Frame", nil, container)
    full:SetAlpha(0)
    ruleA = full:CreateTexture(nil, "OVERLAY")
    ruleB = full:CreateTexture(nil, "OVERLAY")
    local group = full:CreateAnimationGroup()
    fullIn = group:CreateAnimation("Alpha")
    fullIn:SetFromAlpha(0)
    fullIn:SetDuration(FULL_IN)
    fullIn:SetOrder(1)
    fullOut = group:CreateAnimation("Alpha")
    fullOut:SetToAlpha(0)
    fullOut:SetDuration(FULL_OUT)
    fullOut:SetSmoothing("IN")
    fullOut:SetOrder(2)
    full.group = group
end

local function StopMist()
    for _, wisp in ipairs(wisps) do wisp.group:Stop() end
    mistLooping = false
end

-- loop: the steady drift (left running until stopped), else one puff.
local function PlayMist(loop, peak)
    for _, wisp in ipairs(wisps) do
        wisp:SetVertexColor(paint.mist[1], paint.mist[2], paint.mist[3])
        wisp.rise:SetToAlpha(peak)
        wisp.thin:SetFromAlpha(peak)
        wisp.group:SetLooping(loop and "REPEAT" or "NONE")
        wisp.group:Stop()
        wisp.group:Play()
    end
    mistLooping = loop
end

local function StopTouches()
    for _, seg in ipairs(segments) do seg.flashGroup:Stop(); seg.ghostGroup:Stop() end
    if numberPulse then numberPulse:Stop() end
    if full then full.group:Stop() end
    StopMist()
end

-- Size, colours, shape and place, from the settings and the cap. Not on every point change.
local function Layout()
    if not (container and maxPoints) then return end
    paint = Colors()
    local style, max = C.Get("style"), maxPoints
    local vertical = C.Get("orientation") == "vertical"
    local reverse = C.Get("direction") == "reverse"
    local spacing = C.Get("spacing")
    local along, across = C.Get("pipSize"), C.Get("pipSize")
    if style == "bar" then
        across = C.Get("barHeight")
        along = math.max(2, (C.Get("barLength") - spacing * (max - 1)) / max)
    end
    local round = style == "pips" and C.Get("shape") == "round"
    -- Borders: one on each point, and one round the whole display. Without the latter, a look
    -- with a backing still edges it with a 1 px bronze line. Thicker ones get room of their own.
    local bg = paint.background
    local pointEdge = C.Get("pointBorder") and C.Get("pointBorderSize") or 0
    local frameEdge, frameColor = 0, nil
    if C.Get("frameBorder") then
        frameEdge, frameColor = C.Get("frameBorderSize"), paint.frame
    elseif bg[4] > 0 then
        local bronze = R.ChronicleStyle and R.ChronicleStyle.color and R.ChronicleStyle.color.bronze or { 0.55, 0.43, 0.22 }
        frameEdge, frameColor = 1, { bronze[1], bronze[2], bronze[3], 0.9 }
    end
    -- A point border texture straddles the point's edge, so only half of it reaches out.
    local pointTexture = C.Get("pointBorderTexture")
    local pointReach = pointEdge
    if pointEdge > 0 and pointTexture ~= "solid" and (Borders.TexturePath(pointTexture)
        or (Borders.EllesmereKey(pointTexture) and Borders.Ellesmere())) then
        pointReach = math.ceil(pointEdge / 2)
    end
    local pad = PAD + math.max(0, frameEdge - 1) + math.max(0, pointReach - 1)
    StopTouches()
    for i = 1, MAX_POINTS do
        local seg = segments[i]
        if style ~= "number" and i <= max then
            if not seg then seg = NewSegment(); segments[i] = seg end
            local offset = pad + (reverse and (max - i) or (i - 1)) * (along + spacing)
            seg:ClearAllPoints()
            if vertical then
                seg:SetSize(across, along)
                seg:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", pad, offset)
            else
                seg:SetSize(along, across)
                seg:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", offset, pad)
            end
            seg.bar:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
            seg.bar:SetMinMaxValues(i - 1, i)
            Paint(seg, vertical, round, pointEdge)
            -- a texture, drawn over the point's edge on frames of its own; else the plain line
            seg.borders = seg.borders or {}
            local mode = "line"
            if pointEdge > 0 then
                local c = paint.border
                mode = Borders.Draw(seg.borders, seg, pointTexture, pointEdge, c[1], c[2], c[3], c[4], math.floor(pointEdge / 2))
            else
                Borders.Hide(seg.borders)
            end
            seg.rim:SetShown(pointEdge > 0 and mode == "line")
            seg:Show()
        elseif seg then
            seg:Hide()
            seg.rim:Hide()   -- the display's own texture, so hidden by hand
        end
    end

    local length, thick
    if style == "number" then
        local size = C.Get("numberSize")
        local outline = C.Get("outline")
        if not number:SetFont(FontPath(), size, outline ~= "NONE" and outline or "") then
            number:SetFont(STANDARD_TEXT_FONT or [[Fonts\FRIZQT__.TTF]], size, outline ~= "NONE" and outline or "")
        end
        if C.Get("shadow") then
            number:SetShadowOffset(1, -1)
            number:SetShadowColor(0, 0, 0, 0.85)
        else
            number:SetShadowOffset(0, 0)
        end
        length, thick = math.ceil(size * 1.4), math.ceil(size * 1.15)
        vertical = false
        number:Show()
    else
        length, thick = max * along + (max - 1) * spacing, across
        number:Hide()
    end
    if vertical then container:SetSize(thick + pad * 2, length + pad * 2)
    else container:SetSize(length + pad * 2, thick + pad * 2) end

    -- the border round the whole display: a texture, or the plain line
    local frameMode = "line"
    if C.Get("frameBorder") then
        frameMode = Borders.Draw(frameBorders, container, C.Get("frameBorderTexture"), frameEdge,
            frameColor[1], frameColor[2], frameColor[3], frameColor[4], 0)
    else
        Borders.Hide(frameBorders)
    end
    local line = frameEdge > 0 and frameMode == "line"
    for side, t in pairs(edges) do
        if line then
            t:SetColorTexture(frameColor[1], frameColor[2], frameColor[3], frameColor[4])
            if side == "top" or side == "bottom" then t:SetHeight(frameEdge) else t:SetWidth(frameEdge) end
        end
        t:SetShown(line)
    end
    -- the backing, when the colours have one, inside that border (a texture overlaps it a little)
    local inset = line and frameEdge or (frameEdge > 0 and math.max(1, math.floor(frameEdge / 4)) or 0)
    backing:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    backing:ClearAllPoints()
    backing:SetPoint("TOPLEFT", inset, -inset)
    backing:SetPoint("BOTTOMRIGHT", -inset, inset)
    backing:SetShown(bg[4] > 0)

    -- the mist: wisps spread along the points, about twice their height, drifting up and apart
    local size = math.min(72, math.max(20, thick * 2.4))
    for i, wisp in ipairs(wisps) do
        local at = pad + (i - 0.5) / WISPS * length
        wisp:SetSize(size, size)
        wisp:ClearAllPoints()
        if vertical then wisp:SetPoint("CENTER", container, "BOTTOMLEFT", pad + thick / 2, at)
        else wisp:SetPoint("CENTER", container, "BOTTOMLEFT", at, pad + thick / 2) end
        wisp.drift:SetOffset((i % 2 == 0 and 1 or -1) * size * 0.15, size * 0.3)
    end

    -- the full-points rule, split in two so each half can taper outward
    full:ClearAllPoints()
    ruleA:ClearAllPoints(); ruleB:ClearAllPoints()
    if vertical then
        full:SetSize(1, length + pad * 2)
        full:SetPoint("RIGHT", container, "RIGHT", -(frameEdge + 1), 0)
        ruleA:SetPoint("BOTTOMLEFT"); ruleA:SetPoint("BOTTOMRIGHT"); ruleA:SetPoint("TOP", full, "CENTER")
        ruleB:SetPoint("TOPLEFT"); ruleB:SetPoint("TOPRIGHT"); ruleB:SetPoint("BOTTOM", full, "CENTER")
        Taper(ruleA, "VERTICAL", true); Taper(ruleB, "VERTICAL", false)
    else
        full:SetSize(length + pad * 2, 1)
        full:SetPoint("BOTTOM", container, "BOTTOM", 0, frameEdge + 1)
        ruleA:SetPoint("TOPLEFT"); ruleA:SetPoint("BOTTOMLEFT"); ruleA:SetPoint("RIGHT", full, "CENTER")
        ruleB:SetPoint("TOPRIGHT"); ruleB:SetPoint("BOTTOMRIGHT"); ruleB:SetPoint("LEFT", full, "CENTER")
        Taper(ruleA, "HORIZONTAL", true); Taper(ruleB, "HORIZONTAL", false)
    end

    local scale = C.Get("scale") / 100
    container:SetScale(scale)
    container:SetAlpha(C.Get("opacity") / 100)
    Place(container, scale)
    if mover and mover:IsShown() then
        local w, h = container:GetSize()
        mover:SetSize(w * scale, h * scale)
        Place(mover)
    end
end

-- How strong the touches are: nil for none. Reduced motion (Notifications page) keeps them subtle
-- and drops the mist (it drifts); mist is nil then.
local PEAKS = {
    full = { flash = 0.6, rule = 0.9, dip = 0.45, spend = 0.7, puff = 0.55, drift = 0.3 },
    subtle = { flash = 0.3, rule = 0.5, dip = 0.75, spend = 0.4, puff = 0.35, drift = 0.18 },
}
local function Peaks()
    local choice = C.Get("animation")
    if choice == "off" then return nil end
    local reduced = R:Enabled("arrivalReducedMotion")
    if choice == "full" and reduced then choice = "subtle" end
    return PEAKS[choice], not reduced and C.Get("mist") or "off"
end

-- Draws a count (plain or secret). quiet: a new target or a fresh start, so no gain touches.
local function Render(n, secret, quiet)
    local max = maxPoints
    if C.Get("style") == "number" then
        number:SetText(n)   -- a secret count is drawn by the game as it is
        local c = paint.active
        if not secret then
            if n <= 0 then c = paint.inactive elseif n >= max then c = paint.accent end
        end
        number:SetTextColor(c[1], c[2], c[3], 1)
    else
        for i = 1, max do segments[i].bar:SetValue(n) end
    end
    if secret then
        last = nil
        StopTouches()
        return
    end
    local before = last
    last = n
    if quiet or before == nil or n == before then return end
    local peaks, mist = Peaks()
    if not peaks then return end
    if n < before then
        -- spent: the points that went fade out where they were
        if C.Get("style") ~= "number" then
            for i = n + 1, math.min(before, max) do
                local seg = segments[i]
                seg.flashGroup:Stop()
                seg.ghostFade:SetFromAlpha(peaks.spend)
                seg.ghostGroup:Stop(); seg.ghostGroup:Play()
            end
        end
        return
    end
    if C.Get("style") == "number" then
        numberFade:SetFromAlpha(peaks.dip)
        numberPulse:Stop(); numberPulse:Play()
    else
        for i = before + 1, math.min(n, max) do
            local seg = segments[i]
            seg.flashFade:SetFromAlpha(peaks.flash)
            seg.flashGroup:Stop(); seg.flashGroup:Play()
        end
    end
    if n >= max and before < max then
        fullIn:SetToAlpha(peaks.rule)
        fullOut:SetFromAlpha(peaks.rule)
        full.group:Stop(); full.group:Play()
        if mist == "full" then PlayMist(false, peaks.puff) end
    end
end

-- The steady mist: on while it's chosen, the display is up and there are points (or samples).
local function SteadyMist(shown, n, secret)
    local peaks, mist = Peaks()
    local want = shown and peaks ~= nil and mist == "points" and not secret and n > 0
    if want and not mistLooping then PlayMist(true, peaks.drift)
    elseif not want and mistLooping then StopMist() end
end

local function ReadMax()
    local mx = UnitPowerMax("player", COMBO_POWER)
    if type(mx) ~= "number" or Secret(mx) or mx < 1 then return nil end
    return math.min(math.floor(mx), MAX_POINTS)
end

local function ReadCount()
    local n = GetComboPoints("player", "target")
    if Secret(n) then return n, true end
    if type(n) ~= "number" then return 0, false end
    return n, false
end

local function HostileTarget()
    return Plain(UnitExists("target")) == true and Plain(UnitCanAttack("player", "target")) == true and not targetDead
end

local function ShouldShow(n, secret)
    if previewCount or editing then return true end
    if Plain(UnitIsDeadOrGhost("player")) == true then return false end
    local rule = C.Get("visibility")
    if rule == "always" then return true end
    if rule == "combat" then return Plain(UnitAffectingCombat("player")) == true end
    local target = HostileTarget()
    if rule == "target" or secret then return target end
    return target and n > 0
end

local function Update()
    if not (active and container) then return end
    if maxDirty or not maxPoints then
        maxDirty = false
        local mx = ReadMax() or maxPoints or FALLBACK_MAX
        if mx ~= maxPoints then
            maxPoints = mx
            Layout()
            quietNext = true
        end
    end
    targetDead = Plain(UnitIsDead("target")) == true
    local n, secret
    if previewCount then n, secret = math.min(previewCount, maxPoints), false
    elseif editing then n, secret = math.min(SAMPLE, maxPoints), false
    else n, secret = ReadCount() end
    local quiet = quietNext or (editing and not previewCount)
    quietNext = false
    Render(n, secret, quiet)
    local show = ShouldShow(n, secret)
    if show then
        if fadingOut then outro:Stop(); fadingOut = false end
        container:Show()
    elseif container:IsShown() and not fadingOut then
        if Peaks() then
            -- a short fade rather than a blink, so a finisher's spent points can be seen to go
            outroFade:SetFromAlpha(C.Get("opacity") / 100)
            fadingOut = true
            outro:Play()
        else
            container:Hide()
        end
    end
    SteadyMist(show, n, secret)
end

Redraw = function()
    if not (active and container) then return end
    Layout()
    quietNext = true
    Update()
end

---------------------------------------------------------------------------
-- The game's own combo points beside the target portrait (ComboFrame): parked under a hidden
-- frame of ours while asked, and given back to the parent it had. Never in combat: a change
-- then waits for it to end. Left alone if it is protected, or if something else has taken it.
---------------------------------------------------------------------------
local parking, owner
local gamePending = false

local function ApplyGameFrame()
    local frame = _G.ComboFrame
    if type(frame) ~= "table" or not (frame.GetParent and frame.SetParent) then gamePending = false return end
    if (frame.IsForbidden and frame:IsForbidden()) or (frame.IsProtected and frame:IsProtected()) then gamePending = false return end
    local want = active and R:Enabled("comboPointsHideGame")
    local parked = parking ~= nil and frame:GetParent() == parking
    if want == parked then gamePending = false return end
    if InCombat() then gamePending = true return end
    gamePending = false
    if want then
        if not parking then
            parking = CreateFrame("Frame")
            parking:Hide()
        end
        owner = frame:GetParent()
        frame:SetParent(parking)
    else
        frame:SetParent(owner or TargetFrame or UIParent)
        owner = nil
    end
end

-- Whether the game's own combo points are parked by TwichUI right now.
function C.GameFrameHidden()
    local frame = _G.ComboFrame
    return parking ~= nil and type(frame) == "table" and frame.GetParent ~= nil and frame:GetParent() == parking
end

---------------------------------------------------------------------------
-- Edit Mode: an outline over the display (shown with sample points); drag it to move it,
-- right-click to put it back. Edit Mode can't be opened in combat.
---------------------------------------------------------------------------
local function SavePosition(x, y)
    TwichUIDB.ui = TwichUIDB.ui or {}
    TwichUIDB.ui.comboPointsPosition = x and { x = x, y = y } or nil
    if container then Place(container, C.Get("scale") / 100) end
    if mover then Place(mover) end
end

local function BuildMover()
    mover = CreateFrame("Frame", nil, UIParent)
    mover:SetFrameStrata("HIGH")
    mover:SetFrameLevel(1000)
    mover:SetClampedToScreen(true)
    mover:SetMovable(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    if mover.SetDontSavePosition then mover:SetDontSavePosition(true) end
    mover:Hide()
    local fill = mover:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MOVER_ATLAS) then
        fill:SetAtlas(MOVER_ATLAS)
    else
        local c = R.ChronicleStyle and R.ChronicleStyle.color and R.ChronicleStyle.color.bronze or { 0.55, 0.43, 0.22 }
        fill:SetColorTexture(c[1], c[2], c[3], 0.35)
    end
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText("Combo Points")
    mover:SetScript("OnDragStart", function(self)
        if not InCombat() then self:StartMoving() end
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local px, py = UIParent:GetCenter()
        if not (cx and cy and px and py) then Place(self) return end
        SavePosition(math.floor(cx - px + 0.5), math.floor(cy - py + 0.5))
    end)
    mover:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then SavePosition(nil) end
    end)
    mover:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText("TwichUI: Combo Points", 1, 1, 1)
        GameTooltip:AddLine("Where your combo points show. Drag to move them; right-click to put them back.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function EditModeActive()
    local manager = EditModeManagerFrame
    return manager and manager.IsEditModeActive and manager:IsEditModeActive() and true or false
end

local function ShowMover(shown)
    editing = shown and active and container ~= nil
    if editing then
        if not mover then BuildMover() end
        local scale = C.Get("scale") / 100
        local w, h = container:GetSize()
        mover:SetSize(w * scale, h * scale)
        Place(mover)
        mover:Show()
    elseif mover then
        mover:StopMovingOrSizing()
        mover:Hide()
    end
    quietNext = true
    Update()
end

local function HookEditMode()
    if editHooked or not (EventRegistry and EventRegistry.RegisterCallback) then return end
    editHooked = true
    EventRegistry:RegisterCallback("EditMode.Enter", function() ShowMover(true) end, C)
    EventRegistry:RegisterCallback("EditMode.Exit", function() ShowMover(false) end, C)
end

---------------------------------------------------------------------------
-- Preview (/tui combo): the points fill one by one to full, hold, and the display goes back to
-- what the game says. Ignored while off.
---------------------------------------------------------------------------
function C.Preview()
    if not IsRogue() then return false, "Combo points are shown for Rogues only." end
    if not R:Enabled("comboPoints") then return false, "Turn on Show TwichUI combo points first (/tui options)." end
    if not active then return false, "The game doesn't report combo points here." end
    previewToken = previewToken + 1
    local token = previewToken
    local function Step(i)
        if token ~= previewToken then return end
        if i > maxPoints then
            C_Timer.After(PREVIEW_HOLD, function()
                if token ~= previewToken then return end
                previewCount = nil
                quietNext = true
                Update()
            end)
            return
        end
        previewCount = i
        Update()
        C_Timer.After(PREVIEW_STEP, function() Step(i + 1) end)
    end
    last = 0
    previewCount = 0
    quietNext = true
    Update()
    C_Timer.After(PREVIEW_STEP, function() Step(1) end)
    return true
end

---------------------------------------------------------------------------
-- Events: one frame of its own, so the player's power and the target's health can be asked for
-- by unit. Registered only while on (and, after turning off in combat, until the game's frame
-- has been given back).
---------------------------------------------------------------------------
local function IsCombo(powerType) return Secret(powerType) or powerType == "COMBO_POINTS" end

local function OnEvent(_, event, _, powerType)
    if event == "PLAYER_REGEN_ENABLED" and gamePending then ApplyGameFrame() end
    if not active then
        if not gamePending then events:UnregisterAllEvents() end
        return
    end
    if event == "UNIT_POWER_FREQUENT" then
        if not IsCombo(powerType) then return end
    elseif event == "UNIT_MAXPOWER" then
        if not IsCombo(powerType) then return end
        maxDirty = true
    elseif event == "UNIT_HEALTH" then
        -- only the target dying or coming back matters
        if (Plain(UnitIsDead("target")) == true) == targetDead then return end
    elseif event == "PLAYER_TARGET_CHANGED" then
        quietNext = true
    elseif event == "PLAYER_ENTERING_WORLD" then
        maxDirty, quietNext = true, true
        ApplyGameFrame()
    end
    Update()
end

local function Listen()
    if not events then
        if not (active or gamePending) then return end
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    events:UnregisterAllEvents()
    if active then
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("PLAYER_ENTERING_WORLD")
        events:RegisterEvent("PLAYER_REGEN_DISABLED")
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        events:RegisterEvent("PLAYER_DEAD")
        events:RegisterEvent("PLAYER_ALIVE")
        events:RegisterEvent("PLAYER_UNGHOST")
        events:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        events:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        events:RegisterUnitEvent("UNIT_HEALTH", "target")
    elseif gamePending then
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end

-- On or off, from the options. Safe to call any time.
function C.Refresh()
    active = R:Enabled("comboPoints") and IsRogue() and GetComboPoints ~= nil and UnitPowerMax ~= nil
    if active then
        Build()
        HookEditMode()
        maxDirty, quietNext = true, true
        if maxPoints then Layout() end
        editing = EditModeActive()
        if editing then ShowMover(true) else Update() end
    else
        previewCount, previewToken = nil, previewToken + 1
        last = nil
        if container then
            StopTouches()
            outro:Stop(); fadingOut = false
            container:Hide()
        end
        if mover then ShowMover(false) end
    end
    ApplyGameFrame()
    Listen()
end

R:OnInit(C.Refresh)
R:On("PLAYER_LOGIN", C.Refresh)   -- again once the character and Edit Mode are surely there
