-- TwichUI: Journey Chronicle appearance
-- What a player can change about how the Chronicle window looks: its background and border, its
-- text, and its accents. Only the Chronicle window and its note editor and date picker are drawn
-- from this; the zone arrival card, the Welcome Back card and every other window that shares
-- chronicle/Style.lua are not (they keep Style.lua's own colours, which this never changes).
--
-- Saved account-wide, like TwichUI's other looks (TwichUI has no profiles; the Chronicle's own
-- entries are per character and are never read or copied here):
--   TwichUIDB.ui.chronicleLook        background and border: a MenuStyle look (modules/MenuStyle.lua),
--                                     so textures, EllesmereUI's and LibSharedMedia's included, resolve
--                                     and fall back the way the broker menus' and RestedXP's do;
--   TwichUIDB.ui.chronicleAppearance  the rest (below).
-- Only values the player changed are saved, so a default can still be improved later, and a value
-- that can't be used is read as its default without being erased. Frames, fonts and media paths are
-- never saved.
--
-- This file owns the settings, the palette the window draws with, the typography, and when a change
-- reaches the window. chronicle/Window.lua owns the surfaces: it registers its text and controls here
-- and repaints itself when it is told (Subscribe). A change is applied at once when the window is
-- closed (nothing is built for it) and in one coalesced pass when it is open. Nothing runs per frame.

local R = TwichUI
local A = {}
R.ChronicleAppearance = A

local S = R.ChronicleStyle
local D = S.palette          -- Style.lua's own palette: the defaults, never changed

local LOOK_DEFAULTS = {
    bgTexture = "solid", bgColor = "ff261d15", bgOpacity = 98,
    borderTexture = "ledger", borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
    bgTiling = "auto", bgTileSize = 64, bgInset = 0,
}

local DEFAULTS = {
    -- surfaces and accents
    worn = true,                       -- the speckle and the shade toward the bottom
    headerColor = "ff33261a", listColor = "ff1d150f", accentColor = "ffc9a34a",
    dividerColor = "ff4d3b21", showDividers = true, hoverOpacity = 6,
    buttonStyle = "filled",
    scrollThumbColor = "ff8c6e38", scrollTrackColor = "ff000000",
    -- text: one face for the text (and the controls' labels), one for the title and headings
    -- ("inherit" follows the first), one outline for all of it
    font = "default", headingFont = "inherit", outline = "none",
    customSizes = false, titleSize = 16, headingSize = 12, bodySize = 10, metaSize = 10,
    titleColor = "ffede0c2", headingColor = "ffede0c2", bodyColor = "ffc7bda8", metaColor = "ff9e9482",
    textOpacity = 100, lineSpacing = 0,
    -- layout
    padding = 0, windowOpacity = 100,
}
local LIMITS = {
    hoverOpacity = { 0, 40 },
    titleSize = { 10, 28 }, headingSize = { 9, 22 }, bodySize = { 8, 18 }, metaSize = { 8, 16 },
    textOpacity = { 30, 100 }, lineSpacing = { 0, 8 },
    padding = { 0, 12 }, windowOpacity = { 40, 100 },
}
local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local BUTTON_STYLES = { filled = true, outline = true }
local COLORS = {
    headerColor = true, listColor = true, accentColor = true, dividerColor = true,
    scrollThumbColor = true, scrollTrackColor = true,
    titleColor = true, headingColor = true, bodyColor = true, metaColor = true,
}
local FLAGS = { worn = true, showDividers = true, customSizes = true }
-- Settings that change a font or a size (the text is styled again), and the ones that only recolour.
local TYPE_KEYS = {
    font = true, headingFont = true, outline = true, customSizes = true,
    titleSize = true, headingSize = true, bodySize = true, metaSize = true,
    textOpacity = true, lineSpacing = true,
}

A.DEFAULTS, A.LIMITS, A.LOOK_DEFAULTS = DEFAULTS, LIMITS, LOOK_DEFAULTS
A.OUTLINE_CHOICES = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" } }
A.BUTTON_CHOICES = { { "filled", "Filled" }, { "outline", "Outline" } }
A.TILING_CHOICES = { { "auto", "Automatic" }, { "tile", "Repeat" }, { "stretch", "Stretch" } }
A.LEDGER = "ledger"          -- the border id for the Chronicle's own layered rim
A.MIN_INSET = 4              -- the rim's depth; content never sits closer to the edge than this

local function ValidName(value)
    return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]")
end

local function Valid(key, value)
    local limit = LIMITS[key]
    if limit then
        return type(value) == "number" and value == value and value >= limit[1] and value <= limit[2]
            and math.floor(value) == value
    elseif COLORS[key] then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif FLAGS[key] then return type(value) == "boolean"
    elseif key == "font" or key == "headingFont" then return ValidName(value)
    elseif key == "outline" then return type(value) == "string" and OUTLINES[value] ~= nil
    elseif key == "buttonStyle" then return type(value) == "string" and BUTTON_STYLES[value] == true end
    return false
end
A.Valid = Valid

---------------------------------------------------------------------------
-- State. Nothing here is saved.
---------------------------------------------------------------------------
local rev = 0                -- bumped whenever a setting or what it resolves to may have changed
local appliedRev = -1        -- the rev the window was last drawn for
local fontRev = 0            -- bumped when text must be styled again
local scheduled = false      -- a coalesced pass is waiting on its timer
local token = 0              -- a waiting timer that finds a different token does nothing
local running = false        -- re-entry guard: a pass never starts another
local subscribers = {}
local entries = {}           -- every FontString the Chronicle windows registered
local edits = {}             -- the edit boxes that follow the body font
local widgets = {}           -- buttons and links that repaint from the palette
local fallbacks = {}         -- role -> true while its font could not be used
local stats = { applies = 0, requests = 0, coalesced = 0, cancelled = 0, styled = 0 }
local visible = function() return false end

A.palette = S.NewPalette()
local pal = A.palette

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------
local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    local saved = ui and ui.chronicleAppearance
    return type(saved) == "table" and saved or nil
end

function A.Get(key)
    local saved = Saved()
    local value = saved and saved[key]
    if Valid(key, value) then return value end
    return DEFAULTS[key]
end

local Request   -- below

local function Changed(typeToo)
    rev = rev + 1
    if typeToo then fontRev = fontRev + 1 end
    Request()
end

-- Saves one setting (a value that can't be used is refused) and redraws. Returns whether it was kept.
function A.Set(key, value)
    if DEFAULTS[key] == nil or not Valid(key, value) then return false end
    TwichUIDB.ui = TwichUIDB.ui or {}
    if type(TwichUIDB.ui.chronicleAppearance) ~= "table" then TwichUIDB.ui.chronicleAppearance = {} end
    if TwichUIDB.ui.chronicleAppearance[key] == value then return true end   -- unchanged: nothing to redraw
    TwichUIDB.ui.chronicleAppearance[key] = value
    Changed(TYPE_KEYS[key])
    return true
end

-- Puts the whole Chronicle appearance back to its defaults: background and border, text, accents and
-- layout. Entries, notes, filters, the clock, sounds, the recording switches and the window's place
-- are not appearance and are not touched.
function A.Reset()
    if TwichUIDB and TwichUIDB.ui then
        TwichUIDB.ui.chronicleAppearance = nil
        TwichUIDB.ui.chronicleLook = nil
    end
    Changed(true)
end

-- The background and border look (A.Look, a MenuStyle look) is made once the saved data is loaded.
R:OnInit(function()
    local MS = R.MenuStyle
    if not (MS and MS.New) then return end
    A.Look = MS.New("chronicleLook", LOOK_DEFAULTS, {
        extraBorders = { { A.LEDGER, "Chronicle ledger (default)" } },
        sources = true,
    })
    A.Look.Subscribe(function() Changed(false) end)
    if MS.Fonts then
        MS.Fonts.Subscribe(function()
            -- a font a saved choice was waiting for may be there now
            if next(fallbacks) then Changed(true) end
        end)
    end
    Changed(true)   -- the saved choices are now readable
end)

-- EllesmereUI loads after TwichUI: what a saved choice names may exist now.
R:On("ADDON_LOADED", function(name)
    if name == "EllesmereUI" then Changed(true) end
end)

-- Border thickness is in screen pixels, so a different scale is a different size in UI units.
local function ScaleChanged() Changed(false) end
R:On("UI_SCALE_CHANGED", ScaleChanged)
R:On("DISPLAY_SIZE_CHANGED", ScaleChanged)

---------------------------------------------------------------------------
-- The palette: Style.lua's, changed in place from the settings, so every widget that holds one of its
-- colour tables sees the change. A choice equal to the default is the exact colour Style.lua has.
---------------------------------------------------------------------------
local function Rgb(hex)
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end

-- Writes a saved "AARRGGBB" into a colour table; the default's own hex gives the default's own numbers.
local function Put(dst, hex, defaultHex, defaultColor)
    if hex == defaultHex then
        dst[1], dst[2], dst[3] = defaultColor[1], defaultColor[2], defaultColor[3]
    else
        dst[1], dst[2], dst[3] = Rgb(hex)
    end
end

-- dst = base scaled by how far `value` is from `ref`, channel by channel, never above 1: the colours
-- the controls derive from a surface or the accent move with it, and are exactly base at the default.
local function Mul(dst, base, value, ref)
    for i = 1, 3 do
        local ratio = ref[i] > 0 and value[i] / ref[i] or 1
        local x = base[i] * ratio
        dst[i] = x > 1 and 1 or x
    end
end

local function Copy(dst, src) dst[1], dst[2], dst[3] = src[1], src[2], src[3] end

pal.titleText = { D.text[1], D.text[2], D.text[3] }

local function SyncPalette()
    local Look = A.Look
    local function Get(key) return A.Get(key) end
    local bgHex = Look and Look.Get("bgColor") or LOOK_DEFAULTS.bgColor
    local borderHex = Look and Look.Get("borderColor") or LOOK_DEFAULTS.borderColor
    local bgOpacity = Look and Look.Get("bgOpacity") or LOOK_DEFAULTS.bgOpacity
    local borderOpacity = Look and Look.Get("borderOpacity") or LOOK_DEFAULTS.borderOpacity

    Put(pal.bg, bgHex, LOOK_DEFAULTS.bgColor, D.bg)
    Put(pal.bronze, borderHex, LOOK_DEFAULTS.borderColor, D.bronze)
    Mul(pal.bronzeLo, D.bronzeLo, pal.bronze, D.bronze)
    Put(pal.band, Get("headerColor"), DEFAULTS.headerColor, D.band)
    Put(pal.well, Get("listColor"), DEFAULTS.listColor, D.well)
    Put(pal.gold, Get("accentColor"), DEFAULTS.accentColor, D.gold)
    Put(pal.divider, Get("dividerColor"), DEFAULTS.dividerColor, D.divider)
    Put(pal.thumb, Get("scrollThumbColor"), DEFAULTS.scrollThumbColor, D.thumb)
    Put(pal.track, Get("scrollTrackColor"), DEFAULTS.scrollTrackColor, D.track)
    Put(pal.titleText, Get("titleColor"), DEFAULTS.titleColor, D.text)
    Put(pal.text, Get("headingColor"), DEFAULTS.headingColor, D.text)
    Put(pal.textDim, Get("bodyColor"), DEFAULTS.bodyColor, D.textDim)
    Put(pal.stone, Get("metaColor"), DEFAULTS.metaColor, D.stone)

    -- how solid the surfaces are: the window's own background sets how solid its header band and
    -- list well are, so a faint window is faint all through (text, icons and border stay as chosen)
    pal.bgAlpha = bgOpacity / 100
    local k = math.min(1, bgOpacity / (LOOK_DEFAULTS.bgOpacity))
    pal.bandAlpha = D.bandAlpha * k
    pal.wellAlpha = D.wellAlpha * k
    pal.edge = borderOpacity / LOOK_DEFAULTS.borderOpacity
    pal.hover = Get("hoverOpacity") / 100
    pal.dividers = Get("showDividers")
    pal.worn = Get("worn")

    -- the controls: the filled button follows the accent, the quiet one the surfaces
    local pr, q = pal.primary, pal.quiet
    Copy(pr.border, pal.gold)
    Mul(pr.bg, D.primary.bg, pal.gold, D.gold)
    Mul(pr.text, D.primary.text, pal.gold, D.gold)
    Mul(pr.hotBorder, D.primary.hotBorder, pal.gold, D.gold)
    Mul(pr.hotBg, D.primary.hotBg, pal.gold, D.gold)
    Mul(pr.hotText, D.primary.hotText, pal.gold, D.gold)
    Copy(q.border, pal.bronzeLo)
    Mul(q.bg, D.quiet.bg, pal.well, D.well)
    Copy(q.text, pal.textDim)
    Copy(q.hotBorder, pal.bronze)
    Mul(q.hotBg, D.quiet.hotBg, pal.bg, D.bg)
    Copy(q.hotText, pal.text)
    if Get("buttonStyle") == "outline" then
        Copy(pr.bg, q.bg); Copy(pr.hotBg, q.hotBg)
        Copy(pr.text, pal.gold); Copy(pr.hotText, pal.text)
    end
end

---------------------------------------------------------------------------
-- Text. Every FontString of the Chronicle windows is made through A.Text (or registered with
-- A.Track), with the game's font object it started from and a role:
--   title    the window's title                 heading  an entry's headline, the date picker's month
--   body     an entry's note, labels            meta     dates, counts, hints, the empty message
--   control  button and link labels (the face and outline follow the text; the size is the control's own)
-- The font object stays the base: a role with nothing chosen is given back to it, so the game's own
-- fonts (and their locale variants) keep applying. A font that can't be drawn is drawn as the base,
-- stays chosen, and is listed in the troubleshooting report.
---------------------------------------------------------------------------
local SIZE_KEY = { title = "titleSize", heading = "headingSize", body = "bodySize", meta = "metaSize" }

local function Face(role)
    if role == "title" or role == "heading" then
        local heading = A.Get("headingFont")
        if heading ~= "inherit" then return heading end
    end
    return A.Get("font")
end

local function StyleEntry(e)
    local fs, role = e.fs, e.role
    local obj = e.template and rawget(_G, e.template)
    local basePath, baseSize
    if type(obj) == "table" and obj.GetFont then basePath, baseSize = obj:GetFont() end
    local MS = R.MenuStyle
    local path, state = basePath, "default"
    if MS and MS.Fonts then path, state = MS.Fonts.Resolve(Face(role), basePath) end
    fallbacks[role] = state == "missing" or nil
    local size = baseSize
    local key = SIZE_KEY[role]
    if key and A.Get("customSizes") then size = A.Get(key) end
    local flags = OUTLINES[A.Get("outline")] or ""
    local plain = (path == nil or path == basePath) and (size == nil or size == baseSize) and flags == ""
    if plain then
        if e.styled and e.template then fs:SetFontObject(e.template) end
        e.styled = false
    elseif path and size then
        if fs:SetFont(path, size, flags) == false then   -- the game refused it: the base stays
            if e.template then fs:SetFontObject(e.template) end
            e.styled = false
            fallbacks[role] = true
        else
            e.styled = true
            stats.styled = stats.styled + 1
        end
    end
    local spacing = role ~= "control" and A.Get("lineSpacing") or 0
    if spacing ~= (e.spacing or 0) then fs:SetSpacing(spacing) end
    e.spacing = spacing
    local alpha = role ~= "control" and A.Get("textOpacity") / 100 or 1
    if alpha ~= (e.alpha or 1) then fs:SetAlpha(alpha) end
    e.alpha = alpha
end

-- Registers a FontString made elsewhere. color: one of the palette's colour tables the text is drawn
-- in (repainted when the palette changes); leave it out for text whose colour means something and is
-- set by the caller (a warning, a day's tone, an unavailable control).
function A.Track(fs, template, role, color)
    local e = { fs = fs, template = template, role = role, color = color }
    entries[#entries + 1] = e
    StyleEntry(e)
    e.rev = fontRev
    if color then fs:SetTextColor(color[1], color[2], color[3]) end
    return fs
end

function A.Text(parent, template, role, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    return A.Track(fs, template, role, color)
end

-- A button or link that draws itself from the palette (its Repaint is called after a change).
function A.Widget(w)
    widgets[#widgets + 1] = w
    return w
end

-- How much larger than its base size a FontString is drawn now (0 for the base or smaller): what the
-- window adds to a fixed height so bigger text has room.
function A.Grow(fs, baseSize)
    local _, size, flags = fs:GetFont()
    if type(size) ~= "number" then return 0 end
    local grow = math.max(0, size - baseSize)
    if flags and flags:find("THICK") then grow = grow + 2 elseif flags and flags:find("OUTLINE") then grow = grow + 1 end
    return math.ceil(grow)
end

-- Makes an edit box's text follow the body face, size and outline (never its colour: what you type
-- stays as readable as the game draws it). Remembers the game's own to give back.
function A.TrackEdit(box)
    local path, size, flags = box:GetFont()
    local e = { box = box, path = path, size = size, flags = flags }
    edits[#edits + 1] = e
    local function Style()
        local MS = R.MenuStyle
        local resolved = path
        if MS and MS.Fonts then resolved = MS.Fonts.Resolve(Face("body"), path) end
        local want = size
        if A.Get("customSizes") then want = A.Get("bodySize") end
        local outline = OUTLINES[A.Get("outline")] or ""
        if not (resolved and want) then return end
        local plain = resolved == path and want == size and outline == ""
        if plain then
            if e.styled then box:SetFont(path, size, flags or ""); e.styled = false end
        else
            box:SetFont(resolved, want, outline)
            e.styled = true
        end
    end
    e.style = Style
    Style()
end

---------------------------------------------------------------------------
-- The surfaces: the background and border of a window (a BackdropTemplate frame).
-- Returns how far content has to sit in from the frame's edge (UI units), and what was drawn for the
-- border ("custom" is the ledger rim). The frame's size and position are not touched.
---------------------------------------------------------------------------
function A.Surface(frame)
    local Look = A.Look
    local ledger = Look == nil or Look.Get("borderTexture") == A.LEDGER
    local edge, drawn = 0, "custom"
    if Look then edge, drawn = Look.Apply(frame) end
    -- the fill's color, exactly: the default is the ledger's own umber, not its nearest 8-bit neighbour
    frame:SetBackdropColor(pal.bg[1], pal.bg[2], pal.bg[3], pal.bgAlpha)
    S.PaintFrame(frame, pal, ledger, true)
    frame:SetAlpha(A.Get("windowOpacity") / 100)
    frame.paintScale = frame:GetScale() or 1     -- the scale the border's pixels were worked out at
    local inset = ledger and A.MIN_INSET or math.max(A.MIN_INSET, math.ceil(edge or 0))
    return inset + A.Get("padding"), drawn
end

-- Whether the background chosen is an image (tiling, tile size and inset mean something for it) and
-- whether the border chosen has a width of its own the thickness setting can change.
function A.BackgroundIsImage()
    return A.Look ~= nil and A.Look.BackgroundIsImage()
end

function A.BorderHasWidth()
    local Look = A.Look
    if not Look then return false end
    local name = Look.Get("borderTexture")
    return name ~= A.LEDGER and name ~= "none"
end

function A.BorderIsShown()
    local Look = A.Look
    return Look ~= nil and Look.Get("borderTexture") ~= "none"
end

---------------------------------------------------------------------------
-- When a change reaches the window
---------------------------------------------------------------------------
local function Run()
    if running then return end
    running = true
    appliedRev = rev
    SyncPalette()
    for i = 1, #entries do
        local e = entries[i]
        if e.rev ~= fontRev then
            StyleEntry(e)
            e.rev = fontRev
        end
        if e.color then e.fs:SetTextColor(e.color[1], e.color[2], e.color[3]) end
    end
    for _, e in ipairs(edits) do e.style() end
    for i = 1, #widgets do
        local w = widgets[i]
        if w.Repaint then w:Repaint() end
    end
    stats.applies = stats.applies + 1
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
    running = false
end

-- Draws again if anything changed since the last time. Called as a window opens, and by the timer.
function A.Sync()
    if appliedRev ~= rev then Run() end
end

function Request()
    stats.requests = stats.requests + 1
    if not visible() then return end              -- nothing is open: it is drawn as a window opens
    if scheduled or running then stats.coalesced = stats.coalesced + 1 return end
    scheduled = true
    local mine = token
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if mine ~= token then return end       -- cancelled (the window closed) or superseded
            scheduled = false
            A.Sync()
        end)
    else
        scheduled = false
        A.Sync()
    end
end

-- Forgets a waiting pass (the window closed, or the settings changed under it); the next time a window
-- opens it is drawn for whatever is saved then.
function A.Cancel()
    if scheduled then stats.cancelled = stats.cancelled + 1 end
    token = token + 1
    scheduled = false
end

-- fn() is called after a pass: the window recolours and lays itself out again. It must not change a
-- setting.
function A.Subscribe(fn) subscribers[#subscribers + 1] = fn end

-- visibleFn() says whether any Chronicle window is open (so a change with none open costs nothing).
function A.SetVisibility(fn) visible = fn end

-- Draws now, for tests.
function A.Apply() Run() end

-- A window about to be built reads the palette for what is saved now (a pass may not have run yet).
function A.Prepare() SyncPalette() end

-- Read only: what is held, for the troubleshooting report.
function A.Snapshot()
    local roles = {}
    for role in pairs(fallbacks) do roles[#roles + 1] = role end
    table.sort(roles)
    local MS = R.MenuStyle
    return {
        applies = stats.applies, requests = stats.requests, coalesced = stats.coalesced,
        cancelled = stats.cancelled, styled = stats.styled,
        texts = #entries, widgets = #widgets, edits = #edits,
        subscribers = #subscribers, waiting = scheduled, fallbacks = roles,
        font = A.Get("font"), look = A.Look ~= nil,
        fonts = MS and MS.Fonts and MS.Fonts.Stats() or nil,
    }
end
