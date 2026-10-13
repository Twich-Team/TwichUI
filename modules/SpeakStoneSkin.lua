-- TwichUI: SpeakStone skin
-- An optional look for SpeakStone's speech frame (the bar that shows who is speaking, the text, a progress
-- line and Pause / Stop / Replay): TwichUI's warm background and bronze border, fonts and colours of your
-- choosing, quieter controls and a ringed portrait. Written against SpeakStone Forever - Main 3.1.6
-- (SpeechFrame.lua). Off by default; needs SpeakStone; works with or without EllesmereUI.
--
-- What it is, in short:
--   * A visual finish only. SpeakStone keeps its playback, queue, timer, text, dragging, position, size and
--     visibility; nothing is read of what is being said and no click handler, tooltip or script is replaced.
--   * SpeakStone builds the frame lazily (the first line it speaks, the /ss frame sample, the right-click menu)
--     and keeps no global to hook. Its one distinctive act while building is CreateFont("SpeakStoneSpeechTextFont"),
--     so a post-hook on CreateFont (the name compared, nothing else) finds the frame. The frame is then hooked
--     twice, on SetScale (the last call of its Build, before any text is laid out) and on SetHeight (its Fill,
--     once per line or setting change). Both are installed once and gated by the switch.
--   * Nothing runs by itself: no OnUpdate, no ticker, no polling, no work per progress tick. Settings changes
--     become one coalesced pass; a pass that changes nothing about the layout does not make SpeakStone lay the
--     text out again.
--   * What is drawn is kept off SpeakStone's frames wherever it can be: the background, border, portrait ring
--     and progress track live on one child frame of ours. SpeakStone's own pieces are only re-coloured,
--     re-anchored or re-fonted, and what they were is recorded first and put back when the skin is turned off.
--
-- What it touches, and how it finds it (verified against SpeechFrame.lua; a different SpeakStone may differ, in
-- which case the frame is left alone and the status says "unsupported"):
--   frame.portrait / portraitMask   anchor, size, alpha; the mask's file for a square portrait
--   frame.name, frame.text          font file and size, colour, anchors; text spacing; frame.lineHeight (the number
--                                   its Fill multiplies by) so the four-line text area fits the font
--   frame.controls.time             font file and size, colour
--   frame.controls.pause/stop/replay/next
--                                   the template's Left/Middle/Right art and highlight faded, a flat fill and a thin
--                                   border drawn instead, label fonts through three Font objects of ours
--   frame.close, frame.controls.gear  tinted (the art is kept, so clicks, tooltips and states are the game's own);
--                                   with "Close with a right-click" on (the default) the close button is made
--                                   invisible and click-through, and the frame's OnMouseUp (SpeakStone's: a
--                                   right-click opens its menu) is replaced by one that clicks that button, so
--                                   SpeakStone's own Dismiss runs; the script is put back when it is turned off
--   frame.progress                  height, fill colour, anchors; its track is the one BACKGROUND texture of the
--                                   bar (not found: left, and ours is drawn under it)
--   the frame's own Texture regions (the dark band and two hairlines) are faded and hidden: every Texture of the
--   frame itself except the portrait and the captured portraits, never by position or by draw layer
--
-- Saved: TwichUIDB.modules.speakstoneSkin (the switch, off by default), TwichUIDB.ui.speakstoneSkin (the
-- background and border; MenuStyle's) and TwichUIDB.ui.speakstoneSkinStyle (fonts, colours, sizes, portrait,
-- progress, spacing; only values the player changed are saved). Frames, fonts and records are never saved.

local R = TwichUI
local Skin = {}
R.SpeakStoneSkin = Skin

local ADDON = "SpeakStone_Forever_Main"
local FRAME_NAME = "SpeakStoneSpeechFrame"
local FONT_NAME = "SpeakStoneSpeechTextFont"       -- the Font object SpeakStone's Build makes
local SWITCH = "speakstoneSkin"
local WHITE = [[Interface\Buttons\WHITE8x8]]
local PORTRAIT_MASK = [[Interface\CharacterFrame\TempPortraitAlphaMask]]   -- the file SpeakStone's own mask uses
local WRAP = "CLAMPTOBLACKADDITIVE"
local DEBOUNCE = 0.15

-- Layout tokens, in the frame's own units. At a padding of 12 they are the numbers SpeakStone's own layout has.
local CONTROLS_GAP = 4      -- the controls row to the speaker name
local NAME_GAP = 6          -- the speaker name to the text
local PROGRESS_GAP = 6      -- the text to the progress line (SpeakStone's own is 4)
local PORTRAIT_GAP = 14     -- the portrait to the text
local CLOSE_SIZE = 22       -- SpeakStone's close button
local ROW_MIN = 20          -- SpeakStone's button height
local FILL_ALPHA = 0.9      -- SpeakStone's own progress fill strength
local BUTTON_PAD = 16       -- room a label keeps inside its button

local LOOK_DEFAULTS = {
    bgTexture = "solid", bgColor = "ff241b13", bgOpacity = 90,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
}
local STYLE_DEFAULTS = {
    -- the speaker's name: TwichUI's title face (it is only registered for Western clients, and a client that
    -- doesn't have it draws SpeakStone's own), a little larger than the text, in a muted gold
    nameFont = "Cinzel", nameSize = 16, nameColor = "ffd4b05c",
    -- the dialogue: SpeakStone's own face, warm ivory, a little more air between lines than its 2
    textFont = "default", textSize = 13, textColor = "ffeee3c4", lineSpacing = 3,
    -- the time and queue position: quieter and smaller than the text
    timeFont = "default", timeSize = 11, timeColor = "ff9e9482",
    -- Pause, Stop, Replay, Next (and the close and settings icons): one fill, one edge, one label, one accent
    buttonFont = "default", buttonSize = 11, buttonText = "ffe3d6b4", buttonFill = "ff2c2218",
    buttonBorder = "ff6f5a30", accentColor = "ffd4b05c",
    -- the portrait
    showPortrait = true, portraitSize = 72, portraitShape = "round",
    portraitBorderColor = "ff8c6e38", portraitBorderSize = 2,
    -- the thin line that follows the voice
    showProgress = true, progressHeight = 2, progressColor = "ffc9a24a", trackColor = "ff4a3a22",
    -- the close button is hidden and a right-click on the frame does what it does (the gear still opens SpeakStone's
    -- menu, which SpeakStone's own right-click opens otherwise)
    rightClickClose = true,
    -- room between the border and the content
    padding = 12,
}
local STYLE_LIMITS = {
    nameSize = { 10, 28 }, textSize = { 10, 24 }, timeSize = { 8, 18 }, buttonSize = { 8, 14 },
    lineSpacing = { 0, 8 }, padding = { 6, 24 },
    portraitSize = { 48, 96 }, portraitBorderSize = { 0, 4 }, progressHeight = { 1, 6 },
}
local COLOR_KEYS = {
    nameColor = true, textColor = true, timeColor = true, buttonText = true, buttonFill = true,
    buttonBorder = true, accentColor = true, portraitBorderColor = true, progressColor = true, trackColor = true,
}
local FONT_KEYS = { nameFont = true, textFont = true, timeFont = true, buttonFont = true }
local FLAG_KEYS = { showPortrait = true, showProgress = true, rightClickClose = true }
local SHAPES = { round = true, square = true }
Skin.SHAPE_CHOICES = { { "round", "Round" }, { "square", "Square" } }
Skin.SWITCH = SWITCH

local Look = R.MenuStyle.New("speakstoneSkin", LOOK_DEFAULTS)
Skin.Look = Look

---------------------------------------------------------------------------
-- Runtime state. Nothing here is saved.
---------------------------------------------------------------------------
local enabled = false      -- the switch is on and Start has run
local frame                -- SpeakStone's speech frame, once it exists
local applied = false      -- the skin is drawn on it right now
local origin               -- what SpeakStone's pieces were before, recorded when a draw starts
local own                  -- our objects, made once: the child frame, ring, track, button chrome, fonts
local hookedFrame          -- the frame whose SetScale and SetHeight are hooked
local createHooked = false -- the CreateFont post-hook is installed (it cannot be removed; it is gated)
local scheduled = false    -- a coalesced pass is waiting on its timer
local failure              -- nil, or a short code for why nothing is drawn ("unsupported", "error")
local inHeight = false     -- re-entry guard for our own SetHeight inside the SetHeight hook
local fallbacks = {}       -- role -> true while a saved font had to be replaced by SpeakStone's own
local stats = { draws = 0, passes = 0, restores = 0, layouts = 0, refills = 0, heights = 0, unmatched = 0 }

---------------------------------------------------------------------------
-- Settings: the look is MenuStyle's; the rest are here.
---------------------------------------------------------------------------
local function ValidStyle(key, value)
    local limit = STYLE_LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif COLOR_KEYS[key] then
        return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif FONT_KEYS[key] then return R.Borders.ValidName(value)
    elseif FLAG_KEYS[key] then return type(value) == "boolean"
    elseif key == "portraitShape" then return type(value) == "string" and SHAPES[value] == true end
    return false
end

local function SavedStyle()
    local ui = TwichUIDB and TwichUIDB.ui
    local saved = ui and ui.speakstoneSkinStyle
    return type(saved) == "table" and saved or nil
end

local Style = { DEFAULTS = STYLE_DEFAULTS, LIMITS = STYLE_LIMITS }
Skin.Style = Style

function Style.Get(key)
    local saved = SavedStyle()
    local value = saved and saved[key]
    if ValidStyle(key, value) then return value end
    return STYLE_DEFAULTS[key]
end

-- Redraws once, after the last of a burst of changes, and only a skin that is drawn: a frame that has not been
-- built yet reads the settings as they are when it is.
local Flush
local function Changed()
    if not (enabled and applied) or scheduled then return end
    scheduled = true
    C_Timer.After(DEBOUNCE, Flush)
end

function Style.Set(key, value)
    if STYLE_DEFAULTS[key] == nil or not ValidStyle(key, value) then return false end
    TwichUIDB.ui = TwichUIDB.ui or {}
    if type(TwichUIDB.ui.speakstoneSkinStyle) ~= "table" then TwichUIDB.ui.speakstoneSkinStyle = {} end
    if TwichUIDB.ui.speakstoneSkinStyle[key] == value then return true end   -- unchanged: nothing to redraw
    TwichUIDB.ui.speakstoneSkinStyle[key] = value
    Changed()
    return true
end

function Style.Reset()
    if TwichUIDB and TwichUIDB.ui then TwichUIDB.ui.speakstoneSkinStyle = nil end
    Changed()
end

Look.Subscribe(Changed)
R.Profiles.OnApply("look", "speakstone-skin", Changed)   -- a profile change: one redraw, if it is drawn

-- Puts the whole look (background, border, text, controls, portrait, progress, spacing) back to the defaults.
-- The switch, SpeakStone's own settings and everything else of TwichUI's are not touched.
function Skin.Reset()
    Look.Reset()
    Style.Reset()
end

-- { { id, label }, ... } from LibSharedMedia (and TwichUI's and EllesmereUI's own); the saved choice stays
-- listed, marked, if it has gone.
function Skin.FontChoices(current)
    return R.MenuStyle.Fonts.Choices(current, { { "default", "SpeakStone's own font" } })
end

-- A font that was waiting for its media pack can be drawn now.
R.MenuStyle.Fonts.Subscribe(function()
    if next(fallbacks) ~= nil then Changed() end
end)

---------------------------------------------------------------------------
-- SpeakStone, as far as the skin can see it
---------------------------------------------------------------------------
local function AddonLoaded(name)
    return C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name) and true or false
end

local function AddonState()
    if R.Setups and R.Setups.AddonState then return R.Setups.AddonState(ADDON) end
    return AddonLoaded(ADDON) and "ready" or "unknown"
end

local function IsType(object, kind)
    return type(object) == "table" and type(object.GetObjectType) == "function" and object:GetObjectType() == kind
end

-- Whether the frame is the one this was written for: the pieces the layout needs are there and are what they
-- should be. Optional pieces (close, gear, Next, the mask) are styled when they are there.
local function Usable(f)
    if not IsType(f, "Frame") then return false end
    local c = f.controls
    return IsType(f.portrait, "Texture") and IsType(f.name, "FontString") and IsType(f.text, "FontString")
        and IsType(f.scroll, "ScrollFrame") and IsType(f.progress, "StatusBar")
        and type(c) == "table" and IsType(c.time, "FontString") and IsType(c.pause, "Button")
        and IsType(c.stop, "Button") and IsType(c.replay, "Button") and type(f.lineHeight) == "number"
end

local function Buttons(f)
    local c = f.controls
    return { c.pause, c.stop, c.replay, c.next }   -- c.next may be nil: the table just ends there
end

---------------------------------------------------------------------------
-- Recording and putting back
---------------------------------------------------------------------------
local function Points(region)
    local list = {}
    for i = 1, region:GetNumPoints() do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(i)
        list[i] = { point, relativeTo, relativePoint, x, y }
    end
    return list
end

local function Place(region, list)
    region:ClearAllPoints()
    for _, p in ipairs(list) do region:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
end

local function FontRecord(fs)
    local file, size, flags = fs:GetFont()
    local r, g, b, a = fs:GetTextColor()
    return {
        file = file, size = size, flags = flags, r = r, g = g, b = b, a = a,
        object = fs.GetFontObject and fs:GetFontObject() or nil,
        spacing = fs.GetSpacing and fs:GetSpacing() or nil,
    }
end

-- Back to the Font object the string used (so it follows that object again), or to the file it had; the colour
-- is set only where it was set by hand (it differs from the object's).
local function RestoreFont(fs, rec)
    if rec.object then
        fs:SetFontObject(rec.object)
    elseif rec.file then
        fs:SetFont(rec.file, rec.size, rec.flags or "")
    end
    local differs = true
    if rec.object and rec.object.GetTextColor then
        local r, g, b = rec.object:GetTextColor()
        differs = r ~= rec.r or g ~= rec.g or b ~= rec.b
    end
    if differs and rec.r then fs:SetTextColor(rec.r, rec.g, rec.b, rec.a or 1) end
    if rec.spacing then fs:SetSpacing(rec.spacing) end
end

local STATE_TEXTURES = { "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }

local function TextureRecord(texture)
    local r, g, b, a = texture:GetVertexColor()
    return {
        texture = texture, r = r, g = g, b = b, a = a,
        desaturated = texture.IsDesaturated and texture:IsDesaturated() or false,
    }
end

-- The frame's own decoration: every Texture region of the frame itself except the portrait and the portraits
-- SpeakStone captures (the dark band and two hairlines; they are locals of its Build, so there is no field to
-- ask for). The mask is not a Texture. No draw layer is relied on: what the layer of a region reports is one
-- more thing that could differ, and TwichUI's other skins fade a frame's textures the same way.
local function NativeBackdrop(f)
    local skip = { [f.portrait] = true }
    if type(f.captured) == "table" then
        for _, texture in ipairs(f.captured) do skip[texture] = true end
    end
    local list = {}
    for _, region in ipairs({ f:GetRegions() }) do
        if IsType(region, "Texture") and not skip[region] then list[#list + 1] = region end
    end
    return list
end

-- The progress bar's track: the one BACKGROUND texture of the bar besides its fill. More or fewer than one is
-- not what was written against, so nothing is chosen.
local function NativeTrack(bar)
    local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local found
    for _, region in ipairs({ bar:GetRegions() }) do
        if region ~= fill and IsType(region, "Texture") and region:GetDrawLayer() == "BACKGROUND" then
            if found then return nil end
            found = region
        end
    end
    return found
end

local function Capture(f)
    local c = f.controls
    local o = { lineHeight = f.lineHeight, hidden = {}, buttons = {}, tints = {} }
    for _, region in ipairs(NativeBackdrop(f)) do
        o.hidden[#o.hidden + 1] = { region, region:GetAlpha(), region:IsShown() }
    end
    o.portrait = {
        points = Points(f.portrait), width = f.portrait:GetWidth(), height = f.portrait:GetHeight(),
        alpha = f.portrait:GetAlpha(),
    }
    if f.portraitMask and f.portraitMask.GetTexture then o.mask = f.portraitMask:GetTexture() end
    o.name = { points = Points(f.name), font = FontRecord(f.name) }
    o.text = { font = FontRecord(f.text) }
    o.time = { font = FontRecord(c.time) }
    o.scroll = { points = Points(f.scroll) }
    o.controls = { points = Points(c), height = c:GetHeight() }
    if IsType(f.close, "Button") then
        o.close = { points = Points(f.close), alpha = f.close:GetAlpha(),
            mouse = f.close.IsMouseEnabled and f.close:IsMouseEnabled() }
    end
    o.mouseUp = f:GetScript("OnMouseUp")   -- SpeakStone's: a right-click opens its menu
    local r, g, b, a = f.progress:GetStatusBarColor()
    o.progress = {
        points = Points(f.progress), height = f.progress:GetHeight(), shown = f.progress:IsShown(),
        r = r, g = g, b = b, a = a,
    }
    local track = NativeTrack(f.progress)
    if track then o.track = { track, track:GetAlpha() } else stats.unmatched = stats.unmatched + 1 end
    for _, button in ipairs(Buttons(f)) do
        local rec = { button = button, width = button:GetWidth(), height = button:GetHeight(), parts = {} }
        rec.normalFont = button.GetNormalFontObject and button:GetNormalFontObject() or nil
        rec.highlightFont = button.GetHighlightFontObject and button:GetHighlightFontObject() or nil
        rec.disabledFont = button.GetDisabledFontObject and button:GetDisabledFontObject() or nil
        for _, key in ipairs({ "Left", "Middle", "Right" }) do
            local part = button[key]
            if IsType(part, "Texture") then rec.parts[#rec.parts + 1] = { part, part:GetAlpha() } end
        end
        local highlight = button.GetHighlightTexture and button:GetHighlightTexture()
        if highlight then rec.highlight = { highlight, highlight:GetAlpha() } end
        o.buttons[#o.buttons + 1] = rec
    end
    -- the close and settings icons keep their art; only a tint is put on it
    for _, button in ipairs({ f.close or false, c.gear or false }) do
        if IsType(button, "Button") then
            local rec = { button = button, textures = {} }
            for _, getter in ipairs(STATE_TEXTURES) do
                local texture = button[getter] and button[getter](button)
                if texture then rec.textures[getter] = TextureRecord(texture) end
            end
            o.tints[#o.tints + 1] = rec
        end
    end
    return o
end

---------------------------------------------------------------------------
-- Our own objects: made once, hidden when the skin is taken off
---------------------------------------------------------------------------
local function MakeOwn(f)
    local o = { frame = f, buttons = {}, fontState = setmetatable({}, { __mode = "k" }) }
    -- one child frame behind everything: background, border, portrait ring, progress track. One level under the
    -- frame, so the frame's own pieces and its children draw over it; it takes no mouse, so the frame's drag and
    -- right-click are SpeakStone's.
    local bg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bg:SetAllPoints(f)
    bg:SetFrameLevel(math.max(0, (f:GetFrameLevel() or 1) - 1))
    o.bg = bg
    o.ring = bg:CreateTexture(nil, "ARTWORK")
    o.ringMask = bg:CreateMaskTexture()
    o.ringMask:SetTexture(PORTRAIT_MASK, WRAP, WRAP)
    o.ringMask:SetAllPoints(o.ring)
    o.ring:AddMaskTexture(o.ringMask)
    o.track = bg:CreateTexture(nil, "ARTWORK")
    -- three Font objects for the buttons' labels: a button swaps between them with its state, so the colours
    -- belong to them rather than to the string
    local function Font(name)
        return rawget(_G, name) or CreateFont(name)
    end
    o.fonts = { normal = Font("TwichUISpeakStoneButton"), hot = Font("TwichUISpeakStoneButtonHot"),
        off = Font("TwichUISpeakStoneButtonOff") }
    o.probe = bg:CreateFontString(nil, "ARTWORK")
    o.probe:Hide()
    return o
end

-- A flat fill under the label (the button's own state textures, so pressed and disabled follow the game's
-- state with no script of ours), a thin edge above that fill (the OVERLAY layer: the state textures draw in
-- ARTWORK and would cover an edge under them), and a hover tint on the highlight layer.
local function ButtonChrome(button)
    local rec = own.buttons[button]
    if rec then return rec end
    rec = { edges = {} }
    rec.hover = button:CreateTexture(nil, "HIGHLIGHT")
    rec.hover:SetAllPoints(button)
    for i = 1, 4 do rec.edges[i] = button:CreateTexture(nil, "OVERLAY") end
    local top, bottom, left, right = rec.edges[1], rec.edges[2], rec.edges[3], rec.edges[4]
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT")
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT")
    own.buttons[button] = rec
    return rec
end

---------------------------------------------------------------------------
-- Measuring: every number and colour a pass will use, from the settings
---------------------------------------------------------------------------
local function Resolve(role, key, fallback)
    local path, state = R.MenuStyle.Fonts.Resolve(Style.Get(key), fallback)
    fallbacks[role] = (state == "missing") or nil
    return path or fallback
end

local function Color(key)
    local r, g, b = Look.ParseColor(Style.Get(key))
    return r or 1, g or 1, b or 1
end

local function Measure(edge)
    local o = origin
    local m = { edge = edge }
    m.pad = math.max(Style.Get("padding"), math.ceil(edge) + 4)
    m.showPortrait = Style.Get("showPortrait")
    m.showProgress = Style.Get("showProgress")
    m.square = Style.Get("portraitShape") == "square"
    m.portraitSize = Style.Get("portraitSize")
    m.ring = m.showPortrait and Style.Get("portraitBorderSize") or 0
    m.progressHeight = Style.Get("progressHeight")
    m.nameSize, m.textSize, m.timeSize = Style.Get("nameSize"), Style.Get("textSize"), Style.Get("timeSize")
    m.buttonSize = Style.Get("buttonSize")
    m.spacing = Style.Get("lineSpacing")
    m.nameFile = Resolve("name", "nameFont", o.name.font.file)
    m.textFile = Resolve("text", "textFont", o.text.font.file)
    m.timeFile = Resolve("time", "timeFont", o.time.font.file)
    local buttonNative = o.buttons[1] and o.buttons[1].normalFont and select(1, o.buttons[1].normalFont:GetFont())
    m.buttonFile = Resolve("button", "buttonFont", buttonNative or o.time.font.file)
    -- the controls row is as tall as SpeakStone's buttons, or the label needs
    m.rowHeight = math.max(ROW_MIN, m.buttonSize + 8)
    m.controlsTop = math.max(4, m.pad - 4)
    m.closeInset = math.max(2, m.pad - 10, math.ceil(edge) + 1)
    m.rightClose = Style.Get("rightClickClose") and o.close ~= nil
    -- with no close button the controls take its place
    m.controlsRight = m.rightClose and m.pad or (m.closeInset + CLOSE_SIZE + 4)
    m.nameTop = m.controlsTop + m.rowHeight + CONTROLS_GAP
    m.portraitOuter = m.pad
    m.textX = m.pad + (m.showPortrait and (m.ring * 2 + m.portraitSize + PORTRAIT_GAP) or 0)
    m.rightInset = m.pad + 4
    m.lineHeight = m.textSize + m.spacing   -- SpeakStone's own sum (its 13 + 2)
    return m
end

-- The frame's height for a text area of scrollHeight: the rows above and below it, or the portrait's column.
local function FrameHeight(f, m, scrollHeight)
    local nameHeight = math.max(1, math.ceil(f.name:GetStringHeight() or m.nameSize))
    local column = m.nameTop + nameHeight + NAME_GAP + scrollHeight + m.pad
    if m.showProgress then column = column + PROGRESS_GAP + m.progressHeight end
    local portrait = m.showPortrait and (m.pad + m.ring * 2 + m.portraitSize + m.pad) or 0
    return math.max(column, portrait)
end

local lastMeasure   -- the numbers the layout was last made for

-- Whether a layout depending on these numbers needs doing again (nothing allocated).
local LAYOUT_FIELDS = { "pad", "showPortrait", "showProgress", "square", "portraitSize", "ring", "progressHeight", "rightClose",
    "nameSize", "textSize", "spacing", "nameFile", "textFile", "buttonSize", "rowHeight", "edge" }
local function LayoutChanged(m)
    local l = lastMeasure
    if not l then return true end
    for _, key in ipairs(LAYOUT_FIELDS) do
        if l[key] ~= m[key] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Pixel(region)
    if PixelUtil and PixelUtil.ConvertPixelsToUIForRegion and GetPhysicalScreenSize then
        return PixelUtil.ConvertPixelsToUIForRegion(1, region)
    end
    return 1
end

-- Font file, size and colour on a string, SetFont only when the file or size really changed.
local function PaintText(fs, file, size, native, r, g, b)
    local state = own.fontState[fs]
    if not state then
        state = {}
        own.fontState[fs] = state
    end
    if state.file ~= file or state.size ~= size then
        local ok = fs:SetFont(file, size, native.flags or "")
        if ok == false then fs:SetFont(native.file, size, native.flags or "") end
        state.file, state.size = file, size
    end
    fs:SetTextColor(r, g, b, 1)
end

local function PaintFont(font, file, native, size, r, g, b)
    if font:SetFont(file, size, "") == false and native then font:SetFont(native, size, "") end
    font:SetTextColor(r, g, b, 1)
end

-- Anchors and sizes: only when a number the layout depends on changed.
local function Layout(f, m)
    stats.layouts = stats.layouts + 1
    local c = f.controls
    local portrait = f.portrait
    portrait:ClearAllPoints()
    portrait:SetPoint("TOPLEFT", f, "TOPLEFT", m.portraitOuter + m.ring, -(m.portraitOuter + m.ring))
    if m.showPortrait then
        portrait:SetSize(m.portraitSize, m.portraitSize)
        portrait:SetAlpha(origin.portrait.alpha)
    else
        -- SpeakStone shows and hides the portrait itself on every clip, so it is made too small to see rather than
        -- hidden; the captured portraits are anchored to it and follow
        portrait:SetSize(1, 1)
        portrait:SetAlpha(0)
    end
    own.ring:ClearAllPoints()
    own.ring:SetPoint("TOPLEFT", portrait, "TOPLEFT", -m.ring, m.ring)
    own.ring:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", m.ring, -m.ring)
    -- a square portrait is the same texture without the circle: SpeakStone's mask (shared by every portrait it
    -- makes, later ones too) is given a plain white file, which clips nothing
    if f.portraitMask and f.portraitMask.SetTexture then
        if m.square then f.portraitMask:SetTexture(WHITE, WRAP, WRAP)
        elseif own.maskChanged then f.portraitMask:SetTexture(origin.mask or PORTRAIT_MASK, WRAP, WRAP) end
        own.maskChanged = m.square
    end
    if m.square then
        if own.ring.RemoveMaskTexture then own.ring:RemoveMaskTexture(own.ringMask) end
    else
        own.ring:AddMaskTexture(own.ringMask)
    end

    f.name:ClearAllPoints()
    f.name:SetPoint("TOPLEFT", f, "TOPLEFT", m.textX, -m.nameTop)
    f.name:SetPoint("TOPRIGHT", f, "TOPRIGHT", -m.rightInset, -m.nameTop)
    f.scroll:ClearAllPoints()
    f.scroll:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -NAME_GAP)
    f.scroll:SetPoint("TOPRIGHT", f.name, "BOTTOMRIGHT", 0, -NAME_GAP)
    f.progress:ClearAllPoints()
    f.progress:SetPoint("TOPLEFT", f.scroll, "BOTTOMLEFT", 0, -PROGRESS_GAP)
    f.progress:SetPoint("TOPRIGHT", f.scroll, "BOTTOMRIGHT", 0, -PROGRESS_GAP)
    f.progress:SetHeight(m.progressHeight)
    f.progress:SetShown(m.showProgress)
    c:ClearAllPoints()
    c:SetPoint("TOPRIGHT", f, "TOPRIGHT", -m.controlsRight, -m.controlsTop)
    c:SetHeight(m.rowHeight)
    if f.close then
        f.close:ClearAllPoints()
        f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -m.closeInset, -m.closeInset)
    end
    -- the number SpeakStone's Fill multiplies by; Fill sets the text area and (through our hook) the frame
    f.lineHeight = m.lineHeight
    f.filledFor = nil
    stats.refills = stats.refills + 1
end

-- A button: fill, edge, hover and label fonts; its width kept clear of its longest label.
local function PaintButton(f, rec, m, fill, edge, accent)
    local button = rec.button
    local chrome = ButtonChrome(button)
    for _, part in ipairs(rec.parts) do part[1]:SetAlpha(0) end
    if rec.highlight then rec.highlight[1]:SetAlpha(0) end
    if not chrome.states then
        chrome.states = true
        button:SetNormalTexture(WHITE)
        button:SetPushedTexture(WHITE)
        button:SetDisabledTexture(WHITE)
    end
    local function Tint(texture, r, g, b, a)
        if texture then
            texture:SetVertexColor(r, g, b, a)
            texture:SetAllPoints(button)
        end
    end
    Tint(button:GetNormalTexture(), fill[1], fill[2], fill[3], 1)
    Tint(button:GetPushedTexture(), fill[1] * 0.7, fill[2] * 0.7, fill[3] * 0.7, 1)
    Tint(button:GetDisabledTexture(), fill[1] * 0.8, fill[2] * 0.8, fill[3] * 0.8, 0.7)
    chrome.hover:SetColorTexture(accent[1], accent[2], accent[3], 0.16)
    chrome.hover:Show()
    local hair = Pixel(button)
    for i, line in ipairs(chrome.edges) do
        line:SetColorTexture(edge[1], edge[2], edge[3], 1)
        if i <= 2 then line:SetHeight(hair) else line:SetWidth(hair) end
        line:Show()
    end
    button:SetNormalFontObject(own.fonts.normal)
    button:SetHighlightFontObject(own.fonts.hot)
    button:SetDisabledFontObject(own.fonts.off)
    button:SetHeight(m.rowHeight)
    -- width: SpeakStone's own, unless the label (the two a Pause button shows) needs more at this size
    own.probe:SetFontObject(own.fonts.normal)
    local widest = 0
    local labels = { button:GetText() }
    if button == f.controls.pause then labels[#labels + 1] = "Pause"; labels[#labels + 1] = "Resume" end
    for _, label in ipairs(labels) do
        if type(label) == "string" and label ~= "" then
            own.probe:SetText(label)
            widest = math.max(widest, own.probe:GetStringWidth() or 0)
        end
    end
    button:SetWidth(math.max(rec.width, math.ceil(widest) + BUTTON_PAD))
end

local function PaintTint(rec, text, accent, isGear)
    for getter, texture in pairs(rec.textures) do
        local t = texture.texture
        if getter == "GetHighlightTexture" then
            if t.SetDesaturated then t:SetDesaturated(true) end
            t:SetVertexColor(accent[1], accent[2], accent[3], 0.6)
        else
            if t.SetDesaturated and not isGear then t:SetDesaturated(true) end
            t:SetVertexColor(text[1] * 0.8, text[2] * 0.8, text[3] * 0.8, 1)
        end
    end
end

-- A right-click on the frame is SpeakStone's own close button being clicked, so Dismiss does exactly what it does
-- (a playing line carries on without the frame; a paused line or the sample is stopped). Anything else is passed on
-- to the script SpeakStone had.
local function OnMouseUp(self, button)
    if not (enabled and applied and origin) then
        return
    end
    if button == "RightButton" and self.close and self.close.Click then
        self.close:Click()
    elseif origin.mouseUp then
        origin.mouseUp(self, button)
    end
end

-- The close button out of the way, and the frame's right-click closing it; or both as SpeakStone had them.
local function PaintClose(f, m)
    local o = origin
    if m.rightClose and f.close then
        if not own.rightClosing then
            own.rightClosing = true
            f:SetScript("OnMouseUp", OnMouseUp)
        end
        -- invisible and out of the hit test, but still SpeakStone's button: it is clicked from the frame
        f.close:SetAlpha(0)
        if f.close.EnableMouse then f.close:EnableMouse(false) end
    elseif own.rightClosing then
        own.rightClosing = false
        f:SetScript("OnMouseUp", o.mouseUp)
        if f.close and o.close then
            f.close:SetAlpha(o.close.alpha)
            if f.close.EnableMouse and o.close.mouse ~= nil then f.close:EnableMouse(o.close.mouse) end
        end
    end
end

local function Paint(f, m)
    local o = origin
    local c = f.controls
    -- text
    PaintText(f.name, m.nameFile, m.nameSize, o.name.font, Color("nameColor"))
    PaintText(f.text, m.textFile, m.textSize, o.text.font, Color("textColor"))
    f.text:SetSpacing(m.spacing)
    PaintText(c.time, m.timeFile, m.timeSize, o.time.font, Color("timeColor"))
    -- our child frame: the look, then the portrait ring and the progress track on it
    own.bg:Show()
    Look.Apply(own.bg)
    local rr, rg, rb = Color("portraitBorderColor")
    own.ring:SetColorTexture(rr, rg, rb, 1)
    own.ring:SetShown(m.showPortrait and m.ring > 0)
    -- the frame's own band and hairlines, and the bar's own track, give way to ours
    -- faded and hidden both: SpeakStone never shows or restyles them again, and neither alone is relied on
    for _, hidden in ipairs(o.hidden) do
        hidden[1]:SetAlpha(0)
        hidden[1]:Hide()
    end
    if o.track then o.track[1]:SetAlpha(0) end
    local tr, tg, tb = Color("trackColor")
    own.track:ClearAllPoints()
    own.track:SetPoint("TOPLEFT", f.progress, "TOPLEFT")
    own.track:SetPoint("BOTTOMRIGHT", f.progress, "BOTTOMRIGHT")
    own.track:SetColorTexture(tr, tg, tb, 1)
    own.track:SetShown(m.showProgress)
    local pr, pg, pb = Color("progressColor")
    f.progress:SetStatusBarColor(pr, pg, pb, FILL_ALPHA)
    -- controls
    local text = { Color("buttonText") }
    local fill = { Color("buttonFill") }
    local edge = { Color("buttonBorder") }
    local accent = { Color("accentColor") }
    local timeColor = { Color("timeColor") }
    PaintFont(own.fonts.normal, m.buttonFile, o.time.font.file, m.buttonSize, text[1], text[2], text[3])
    PaintFont(own.fonts.hot, m.buttonFile, o.time.font.file, m.buttonSize, accent[1], accent[2], accent[3])
    PaintFont(own.fonts.off, m.buttonFile, o.time.font.file, m.buttonSize, timeColor[1], timeColor[2], timeColor[3])
    for _, rec in ipairs(o.buttons) do PaintButton(f, rec, m, fill, edge, accent) end
    for i, rec in ipairs(o.tints) do PaintTint(rec, text, accent, rec.button == c.gear) end
    PaintClose(f, m)
end

local function DoApply()
    local f = frame
    if not Usable(f) then
        failure = "unsupported"
        return false
    end
    failure = nil
    own = (own and own.frame == f) and own or MakeOwn(f)
    if not origin then
        origin = Capture(f)
        lastMeasure = nil
    end
    -- the background first: its border says how far in the content must stay
    local edge = Look.Apply(own.bg)
    local m = Measure(edge)
    if LayoutChanged(m) then
        Layout(f, m)
        lastMeasure = m
    end
    Paint(f, m)
    applied = true
    stats.draws = stats.draws + 1
    return true
end

-- Puts every piece SpeakStone made back as it was recorded, and hides what is ours.
local function DoRestore()
    local f, o = frame, origin
    applied = false
    if not (f and o and own) then
        origin = nil
        return
    end
    own.bg:Hide()
    for _, hidden in ipairs(o.hidden) do
        hidden[1]:SetAlpha(hidden[2])
        hidden[1]:SetShown(hidden[3])
    end
    if o.track then o.track[1]:SetAlpha(o.track[2]) end
    Place(f.portrait, o.portrait.points)
    f.portrait:SetSize(o.portrait.width, o.portrait.height)
    f.portrait:SetAlpha(o.portrait.alpha)
    if own.maskChanged and f.portraitMask then f.portraitMask:SetTexture(o.mask or PORTRAIT_MASK, WRAP, WRAP) end
    own.maskChanged = false
    Place(f.name, o.name.points)
    RestoreFont(f.name, o.name.font)
    RestoreFont(f.text, o.text.font)
    RestoreFont(f.controls.time, o.time.font)
    own.fontState = setmetatable({}, { __mode = "k" })
    Place(f.scroll, o.scroll.points)
    Place(f.controls, o.controls.points)
    f.controls:SetHeight(o.controls.height)
    if o.close and f.close then
        Place(f.close, o.close.points)
        f.close:SetAlpha(o.close.alpha)
        if f.close.EnableMouse and o.close.mouse ~= nil then f.close:EnableMouse(o.close.mouse) end
    end
    if own.rightClosing then
        f:SetScript("OnMouseUp", o.mouseUp)
        own.rightClosing = false
    end
    Place(f.progress, o.progress.points)
    f.progress:SetHeight(o.progress.height)
    f.progress:SetShown(o.progress.shown)
    f.progress:SetStatusBarColor(o.progress.r, o.progress.g, o.progress.b, o.progress.a)
    for _, rec in ipairs(o.buttons) do
        local button = rec.button
        for _, part in ipairs(rec.parts) do part[1]:SetAlpha(part[2]) end
        if rec.highlight then rec.highlight[1]:SetAlpha(rec.highlight[2]) end
        if rec.normalFont then button:SetNormalFontObject(rec.normalFont) end
        if rec.highlightFont then button:SetHighlightFontObject(rec.highlightFont) end
        if rec.disabledFont then button:SetDisabledFontObject(rec.disabledFont) end
        button:SetWidth(rec.width)
        button:SetHeight(rec.height)
        local chrome = own.buttons[button]
        if chrome then
            chrome.hover:Hide()
            for _, line in ipairs(chrome.edges) do line:Hide() end
            if chrome.states then
                button:SetNormalTexture("")
                button:SetPushedTexture("")
                button:SetDisabledTexture("")
                chrome.states = false
            end
        end
    end
    for _, rec in ipairs(o.tints) do
        for _, texture in pairs(rec.textures) do
            local t = texture.texture
            if t.SetDesaturated then t:SetDesaturated(texture.desaturated) end
            t:SetVertexColor(texture.r, texture.g, texture.b, texture.a)
        end
    end
    -- SpeakStone lays its own text area and height out again with its own numbers, on its next tick
    f.lineHeight = o.lineHeight
    f.filledFor = nil
    origin, lastMeasure = nil, nil
    stats.restores = stats.restores + 1
end

local function Guarded(fn)
    local ok, result = pcall(fn)
    if not ok then
        failure = "error"
        R.Fault("SpeakStone skin", result)
        -- what was changed on the way is put back; nothing is drawn until the switch is turned off and on
        pcall(DoRestore)
        applied = false
        return false
    end
    return result
end

local function ApplyNow()
    if failure == "error" then return false end
    return Guarded(DoApply)
end

function Flush()
    scheduled = false
    if enabled and applied then
        stats.passes = stats.passes + 1
        ApplyNow()
    end
end

---------------------------------------------------------------------------
-- Hooks: each installed once, each gated by the switch
---------------------------------------------------------------------------
-- SpeakStone's Build ends with ApplyPosition, whose first act is SetScale: the pieces all exist and no text has
-- been laid out. Later SetScale calls are the player's size choice or a reset of its place.
local function OnScale()
    if not enabled then return end
    if applied then
        Changed()   -- the pixel size of the thin lines depends on the scale
    elseif frame then
        ApplyNow()
    end
end

-- SpeakStone's Fill has just set the frame's height as its own base height plus the text area's growth. Ours
-- is the rows above and below the text area, however tall the name and the progress line are.
local function OnHeight(self)
    if not (enabled and applied) or inHeight or not lastMeasure then return end
    inHeight = true
    local want = FrameHeight(self, lastMeasure, self.scroll:GetHeight())
    if math.abs((self:GetHeight() or 0) - want) > 0.01 then
        self:SetHeight(want)
        stats.heights = stats.heights + 1
    end
    inHeight = false
end

-- Takes f as the speech frame: hooks it (once) and forgets anything recorded of another one.
local function Bind(f)
    if frame ~= f then
        frame, origin, own, lastMeasure, applied = f, nil, nil, nil, false
    end
    if hookedFrame ~= f then
        hookedFrame = f
        hooksecurefunc(f, "SetScale", OnScale)
        hooksecurefunc(f, "SetHeight", OnHeight)
    end
end

-- Looks for the frame and, once found, hooks it and draws on it.
local function Attach()
    if not enabled then return end
    local f = rawget(_G, FRAME_NAME)
    if not f then return end
    Bind(f)
    if not applied and failure ~= "error" then ApplyNow() end
end

-- CreateFont is called a few dozen times a session, and only SpeakStone's Build makes this name.
local function OnCreateFont(name)
    if not enabled or name ~= FONT_NAME then return end
    local f = rawget(_G, FRAME_NAME)   -- made at the top of Build, so it exists by now
    if f then Bind(f) end
    -- in case Build's own last call is not where it was: one look once it has finished
    C_Timer.After(0, Attach)
end

local function InstallCreateHook()
    if createHooked or type(CreateFont) ~= "function" then return end
    createHooked = true
    hooksecurefunc("CreateFont", OnCreateFont)
end

---------------------------------------------------------------------------
-- Turning it on and off
---------------------------------------------------------------------------
local function Start()
    if enabled then return end
    enabled = true
    failure = nil
    local state = AddonState()
    if state == "missing" or state == "disabled" then return end
    InstallCreateHook()
    Attach()   -- the frame may exist already (turned on while playing)
end

local function Stop()
    if not enabled then return end
    enabled = false
    scheduled = false
    if applied then Guarded(DoRestore) end
    failure = nil
end

-- The switch changed in Settings (or its value should be read again).
function Skin.OnSwitch()
    if R:Enabled(SWITCH) then Start() else Stop() end
end

R:OnInit(function()
    if R:Enabled(SWITCH) then Start() end
end)

---------------------------------------------------------------------------
-- Preview: SpeakStone's own sample line, the one /ss frame shows (no sound, no playback)
---------------------------------------------------------------------------
-- Calls SpeakStone's slash command exactly as typing "/ss frame" does. While a line is being spoken
-- SpeakStone says so in chat and shows nothing. Returns false when the command isn't there.
function Skin.TogglePreview()
    local fn = SlashCmdList and SlashCmdList.SPEAKSTONE
    if type(fn) ~= "function" then return false end
    local ok, err = pcall(fn, "frame")
    if not ok then R.Fault("SpeakStone preview", err) end
    return ok
end

---------------------------------------------------------------------------
-- What it is doing, for the settings page and the troubleshooting report. Words and counts only.
---------------------------------------------------------------------------
-- Status codes: off, speakstone-missing, speakstone-disabled, waiting (SpeakStone has not built its frame yet:
-- it does so the first time it has something to show), unsupported, error, active.
function Skin.Status()
    local state = AddonState()
    local s = {
        switchOn = R:Enabled(SWITCH) and true or false, enabled = enabled, addon = state,
        loaded = AddonLoaded(ADDON), frameBuilt = rawget(_G, FRAME_NAME) ~= nil, applied = applied,
        failure = failure,
    }
    local code
    if not s.switchOn then code = "off"
    elseif state == "missing" then code = "speakstone-missing"
    elseif state == "disabled" then code = "speakstone-disabled"
    elseif failure == "error" then code = "error"
    elseif failure == "unsupported" then code = "unsupported"
    elseif applied then code = "active"
    else code = "waiting" end
    s.code = code
    return s
end

-- Counts and flags only: no frames, text or settings values.
function Skin.Snapshot()
    local s = Skin.Status()
    s.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or nil
    s.createHook, s.frameHooked = createHooked, hookedFrame ~= nil
    s.scheduled = scheduled
    s.draws, s.passes, s.restores = stats.draws, stats.passes, stats.restores
    s.layouts, s.refills, s.heights, s.unmatched = stats.layouts, stats.refills, stats.heights, stats.unmatched
    s.hidden = origin and #origin.hidden or 0
    s.trackFound = origin and origin.track ~= nil or false
    s.fallbackName, s.fallbackText = fallbacks.name == true, fallbacks.text == true
    s.fallbackTime, s.fallbackButton = fallbacks.time == true, fallbacks.button == true
    s.sharedMedia = (LibStub and LibStub("LibSharedMedia-3.0", true)) ~= nil
    return s
end
