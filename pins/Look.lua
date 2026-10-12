-- TwichUI: Party pins, preferences and appearance
-- Saved choices, all account-wide in TwichUIDB.ui and only stored once changed:
--   partyPins       how pins are placed and shown: the map clicks for a local pin and a party pin, and
--                   whether names show on the map always or only on hover and for the selected pin;
--   pinsLook        the pin window's background and border (a MenuStyle look: textures from the game,
--                   LibSharedMedia and EllesmereUI while it is installed, with the same fallbacks);
--   pinsAppearance  its text and accents: font, text size, accent color and row spacing;
--   pinsMapText     the names drawn under pins on the world map and the minimap: font, size, color, outline
--                   and shadow (one look for both maps; the window's text is separate);
--   pinsBroker      the data bar entry: what its text says, whether it has its icon, its text color, and
--                   how a newly received pin is pointed out (on or off, for how long, in what color);
--   pinsBrokerMenu  the background and border of the menu a click on that entry opens (a MenuStyle look,
--                   separate from the Mage launchers' and from the window's);
--   pinsEditorLook  the background and border of the new pin window (the editor: a MenuStyle look, separate
--                   from the pin window's; its text follows the pin window's font, size and accent).
-- A value that can't be used is read as its default and kept as it was, so a font from a media pack that
-- is missing today is still chosen when the pack returns. Resetting the appearance never touches pins or
-- the click and label choices, and neither touches the map text. Frames, fonts and media paths are never saved.

local R = TwichUI
local S = R.ChronicleStyle
local PL = {}
R.PinsLook = PL

---------------------------------------------------------------------------
-- Placing: which click makes which pin. The map's own clicks are left alone: Ctrl-click is the game's
-- waypoint and Shift-click is ShortestPathForever's journey, so neither is offered. Modifiers must match
-- exactly (Alt-click is not Alt-Shift-click).
---------------------------------------------------------------------------
PL.CLICKS = {
    { "alt", "Alt-click", "LeftButton", true, false, false },
    { "altshift", "Alt-Shift-click", "LeftButton", true, true, false },
    { "altright", "Alt-right-click", "RightButton", true, false, false },
    { "none", "Off (use Place a pin in the pin window)" },
}
local CLICK = {}
for _, c in ipairs(PL.CLICKS) do CLICK[c[1]] = c end
PL.LABELS = { { "hover", "On hover, and for the selected pin" }, { "always", "Always" } }
local LABEL = { hover = true, always = true }
-- Names beside minimap pins: off keeps the minimap as it was (the tooltip has the name).
PL.MINIMAP_LABELS = { { "off", "Never (in the tooltip)" }, { "hover", "On hover, and for the selected pin" }, { "always", "Always" } }
local MINIMAP_LABEL = { off = true, hover = true, always = true }

-- wayAlso: when another addon has /way, also make a pin from what it was given (pins/Way.lua); off until chosen.
local PREF_DEFAULTS = { localClick = "alt", partyClick = "altshift", labels = "hover", minimap = true, minimapLabels = "off", wayAlso = false }
PL.PREF_DEFAULTS = PREF_DEFAULTS

local function Prefs()
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.partyPins
    return type(t) == "table" and t or nil
end

local function ValidPref(key, value)
    if key == "localClick" or key == "partyClick" then return type(value) == "string" and CLICK[value] ~= nil end
    if key == "labels" then return type(value) == "string" and LABEL[value] == true end
    if key == "minimapLabels" then return type(value) == "string" and MINIMAP_LABEL[value] == true end
    if key == "minimap" or key == "wayAlso" then return type(value) == "boolean" end
    if key == "position" then
        return type(value) == "table" and type(value.x) == "number" and type(value.y) == "number"
            and value.x == value.x and value.y == value.y and math.abs(value.x) < 10000 and math.abs(value.y) < 10000
    end
    return false
end

function PL.Pref(key)
    local t = Prefs()
    local value = t and t[key]
    if ValidPref(key, value) then return value end
    return PREF_DEFAULTS[key]
end

local prefListeners = {}
function PL.OnPrefChange(fn) prefListeners[#prefListeners + 1] = fn end

-- Saves one choice (an unusable one is refused). Picking the click the other kind of pin uses swaps
-- them, so the two never share a click. Returns whether it was kept.
function PL.SetPref(key, value)
    if not ValidPref(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.partyPins) ~= "table" then TwichUIDB.ui.partyPins = {} end
    local t = TwichUIDB.ui.partyPins
    if (key == "localClick" or key == "partyClick") and value ~= "none" then
        local other = key == "localClick" and "partyClick" or "localClick"
        if PL.Pref(other) == value then t[other] = PL.Pref(key) end
    end
    t[key] = value
    for _, fn in ipairs(prefListeners) do pcall(fn) end
    return true
end

function PL.ClickLabel(id) return CLICK[id] and CLICK[id][2] or CLICK.none[2] end

-- Whether a map click is the one chosen for `which` ("localClick" or "partyClick").
-- alt, shift, ctrl: whether each is held (asked of the game when left out).
function PL.Matches(which, button, alt, shift, ctrl)
    local c = CLICK[PL.Pref(which)]
    if not c or not c[3] then return false end
    if alt == nil then alt, shift, ctrl = IsAltKeyDown(), IsShiftKeyDown(), IsControlKeyDown() end
    return button == c[3] and (alt and true or false) == c[4] and (shift and true or false) == c[5]
        and (ctrl and true or false) == c[6]
end

-- Whether the keys held now are a placing click's (for the map's pin cursor). Left-button clicks only.
function PL.Held()
    local alt, shift, ctrl = IsAltKeyDown(), IsShiftKeyDown(), IsControlKeyDown()
    return PL.Matches("localClick", "LeftButton", alt, shift, ctrl) or PL.Matches("partyClick", "LeftButton", alt, shift, ctrl)
end

-- One line saying how to place pins, for the window and the settings.
function PL.HowToPlace()
    local l, p = PL.Pref("localClick"), PL.Pref("partyClick")
    local parts = {}
    if l ~= "none" then parts[#parts + 1] = PL.ClickLabel(l) .. " the map for a pin" end
    if p ~= "none" then parts[#parts + 1] = PL.ClickLabel(p) .. " for a party pin" end
    if #parts == 0 then return "Use Place a pin, then click the map." end
    return table.concat(parts, "; ") .. "."
end

---------------------------------------------------------------------------
-- The pin's shape: media/textures/map-pin.tga, TwichUI's own (64 x 64, a gray bevelled diamond with a see-through
-- middle; a pin's color tints it). The diamond is 60 x 60, centered, so a pin button is anchored by its CENTER.
-- PIN_BADGE is where a party pin's badge sits, as fractions of the texture (from the left, from the top): on
-- the diamond's upper-right edge, a little outside it.
---------------------------------------------------------------------------
PL.PIN_TEXTURE = R.PATH .. [[media\textures\map-pin]]
PL.PIN_BADGE = { 0.78, 0.22 }

-- Where the badge goes, in a button or icon `size` units square: { x from the left, y from the top }.
function PL.BadgePoint(size)
    return PL.PIN_BADGE[1] * size, -PL.PIN_BADGE[2] * size
end

---------------------------------------------------------------------------
-- The window's appearance
---------------------------------------------------------------------------
PL.Look = R.MenuStyle.New("pinsLook", {
    bgTexture = "solid", bgColor = "ff261d15", bgOpacity = 98,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 90, borderSize = 1,
}, { sources = true })

local DEFAULTS = { font = "default", textSize = 12, accentColor = "ffc9a34a", density = "comfortable" }
local LIMITS = { textSize = { 9, 16 } }
PL.DEFAULTS, PL.LIMITS = DEFAULTS, LIMITS
PL.DENSITY = { { "comfortable", "Comfortable" }, { "compact", "Compact" } }
local DENSITY = { comfortable = 34, compact = 26 }   -- row height

local function Valid(key, value)
    if key == "font" then return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]") end
    if key == "textSize" then
        return type(value) == "number" and value == value and value % 1 == 0 and value >= LIMITS.textSize[1] and value <= LIMITS.textSize[2]
    end
    if key == "accentColor" then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil end
    if key == "density" then return type(value) == "string" and DENSITY[value] ~= nil end
    return false
end
PL.Valid = Valid

function PL.Get(key)
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.pinsAppearance
    local value = type(t) == "table" and t[key] or nil
    if Valid(key, value) then return value end
    return DEFAULTS[key]
end

local subscribers = {}
function PL.Subscribe(fn) subscribers[#subscribers + 1] = fn end
local function Notify()
    PL.Sync()
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

function PL.Set(key, value)
    if DEFAULTS[key] == nil or not Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.pinsAppearance) ~= "table" then TwichUIDB.ui.pinsAppearance = {} end
    TwichUIDB.ui.pinsAppearance[key] = value
    Notify()
    return true
end

-- Draws `look` (a MenuStyle look: PL.Look, PL.MenuLook or PL.EditorLook) on a BackdropTemplate frame and
-- returns how far content must sit in from the frame's edge, in UI units. MenuStyle's own answer is the
-- border's thickness; an EllesmereUI texture's visible line is only a part of that (see Borders.Inside), so
-- for one the content is brought out to the line instead of leaving the whole thickness empty.
function PL.Surface(look, frame)
    local edge, drawn = look.Apply(frame)
    if drawn == "eui" then edge = math.min(edge, R.Borders.Inside(look.Get("borderTexture"), edge)) end
    return edge
end

-- The window's look back to its defaults: background, border, text and accent. Pins and the click and
-- label choices are not appearance and are not touched.
function PL.Reset()
    if type(TwichUIDB) == "table" and type(TwichUIDB.ui) == "table" then TwichUIDB.ui.pinsAppearance = nil end
    PL.Look.Reset()   -- notifies through its own subscription below
end

PL.Look.Subscribe(Notify)

function PL.RowHeight() return DENSITY[PL.Get("density")] end

-- The palette the window draws with: the Chronicle's, with the accent the player chose.
PL.palette = S.NewPalette()
local pal = PL.palette
local D = S.palette

local function Rgb(hex)
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255
end
PL.Rgb = Rgb

local function Scaled(dst, base, value, ref)
    for i = 1, 3 do
        local ratio = ref[i] > 0 and value[i] / ref[i] or 1
        dst[i] = math.min(1, base[i] * ratio)
    end
end

function PL.Sync()
    local hex = PL.Get("accentColor")
    if hex == DEFAULTS.accentColor then
        pal.gold[1], pal.gold[2], pal.gold[3] = D.gold[1], D.gold[2], D.gold[3]
    else
        pal.gold[1], pal.gold[2], pal.gold[3] = Rgb(hex)
    end
    local bg = PL.Look.Get("bgColor")
    if bg == "ff261d15" then
        pal.bg[1], pal.bg[2], pal.bg[3] = D.bg[1], D.bg[2], D.bg[3]
    else
        pal.bg[1], pal.bg[2], pal.bg[3] = Rgb(bg)
    end
    pal.bgAlpha = PL.Look.Get("bgOpacity") / 100
    local k = math.min(1, PL.Look.Get("bgOpacity") / 98)
    pal.bandAlpha, pal.wellAlpha = D.bandAlpha * k, D.wellAlpha * k
    local pr = pal.primary
    pr.border[1], pr.border[2], pr.border[3] = pal.gold[1], pal.gold[2], pal.gold[3]
    Scaled(pr.bg, D.primary.bg, pal.gold, D.gold)
    Scaled(pr.text, D.primary.text, pal.gold, D.gold)
    Scaled(pr.hotBorder, D.primary.hotBorder, pal.gold, D.gold)
    Scaled(pr.hotBg, D.primary.hotBg, pal.gold, D.gold)
    Scaled(pr.hotText, D.primary.hotText, pal.gold, D.gold)
end
PL.Sync()
R:OnInit(PL.Sync)   -- the saved choices are readable now

-- A FontString in the chosen face. role "name" uses the text size, "meta" two points smaller, "title" four
-- larger. The game's own font object is the base: a face that can't be drawn falls back to it and stays chosen.
local tracked = {}
local SIZE = { name = 0, meta = -2, title = 4, control = -1 }
PL.fallback = false

local function Style(e)
    local fs, template, role = e.fs, e.template, e.role
    local obj = rawget(_G, template)
    local basePath, baseSize, baseFlags
    if type(obj) == "table" and obj.GetFont then basePath, baseSize, baseFlags = obj:GetFont() end
    local MS = R.MenuStyle
    local path, state = basePath, "default"
    if MS and MS.Fonts then path, state = MS.Fonts.Resolve(PL.Get("font"), basePath) end
    if state == "missing" then PL.fallback = true end
    local size = PL.Get("textSize") + (SIZE[role] or 0)
    if path and fs:SetFont(path, size, baseFlags or "") == false and basePath then
        fs:SetFont(basePath, baseSize or size, baseFlags or "")
        PL.fallback = true
    end
end

function PL.Text(parent, template, role, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", template)
    fs:SetJustifyH("LEFT")
    local e = { fs = fs, template = template, role = role }
    tracked[#tracked + 1] = e
    Style(e)
    return fs
end

-- Edit boxes follow the face and the text size.
function PL.Edit(box)
    local path, size, flags = box:GetFont()
    local e = { box = box, path = path, size = size, flags = flags }
    tracked[#tracked + 1] = e
    e.edit = true
    local MS = R.MenuStyle
    local face = MS and MS.Fonts and MS.Fonts.Resolve(PL.Get("font"), path) or path
    if face then box:SetFont(face, PL.Get("textSize"), flags or "") end
end

function PL.Restyle()
    PL.fallback = false
    local MS = R.MenuStyle
    for _, e in ipairs(tracked) do
        if e.edit then
            local face = MS and MS.Fonts and MS.Fonts.Resolve(PL.Get("font"), e.path) or e.path
            if face then e.box:SetFont(face, PL.Get("textSize"), e.flags or "") end
        else
            Style(e)
        end
    end
end
PL.Subscribe(PL.Restyle)
if R.MenuStyle and R.MenuStyle.Fonts then R.MenuStyle.Fonts.Subscribe(PL.Restyle) end

---------------------------------------------------------------------------
-- The text on the maps: the names under pins on the world map and beside them on the minimap. One look for
-- both, kept apart from the window's: it is not reset with the window and resetting it leaves the window
-- alone. Strings are made from the game's GameFontHighlightSmallOutline (in this client that is the small
-- game font, white, with a 1 pixel shadow and no outline), so the defaults below are what was drawn before
-- there was a choice. A face that is gone, or can't be drawn, is drawn as the game's own and stays chosen.
---------------------------------------------------------------------------
local MT = {}
PL.MapText = MT
MT.DEFAULTS = { font = "default", size = 10, color = "ffffffff", outline = "none", shadow = true }
MT.LIMITS = { size = { 8, 20 } }
MT.OUTLINES = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" } }
local OUTLINE_FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local MAP_TEMPLATE = "GameFontHighlightSmallOutline"
MT.fallback = false

function MT.Valid(key, value)
    if key == "font" then return Valid("font", value) end
    if key == "size" then
        local l = MT.LIMITS.size
        return type(value) == "number" and value == value and value % 1 == 0 and value >= l[1] and value <= l[2]
    end
    if key == "color" then return Valid("accentColor", value) end
    if key == "outline" then return type(value) == "string" and OUTLINE_FLAGS[value] ~= nil end
    if key == "shadow" then return type(value) == "boolean" end
    return false
end

function MT.Get(key)
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.pinsMapText
    local value
    if type(t) == "table" then value = t[key] end   -- not "and ... or": a saved false is a value
    if MT.Valid(key, value) then return value end
    return MT.DEFAULTS[key]
end

local mapStrings = setmetatable({}, { __mode = "k" })   -- FontString -> the width it was given for size 10, or true
local mapSubscribers = {}
function MT.Subscribe(fn) mapSubscribers[#mapSubscribers + 1] = fn end

local function StyleMapString(fs, baseWidth)
    local obj = rawget(_G, MAP_TEMPLATE)
    local basePath, baseSize
    if type(obj) == "table" and obj.GetFont then basePath, baseSize = obj:GetFont() end
    local MS = R.MenuStyle
    local path, state = basePath, "default"
    if MS and MS.Fonts then path, state = MS.Fonts.Resolve(MT.Get("font"), basePath) end
    if state == "missing" then MT.fallback = true end
    local size, flags = MT.Get("size"), OUTLINE_FLAGS[MT.Get("outline")]
    if path and fs:SetFont(path, size, flags) == false and basePath then
        fs:SetFont(basePath, baseSize or size, flags)
        MT.fallback = true
    end
    fs:SetTextColor(Rgb(MT.Get("color")))
    if MT.Get("shadow") then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
    -- the room a name has grows with its size, so a larger face isn't cut short
    if baseWidth then fs:SetWidth(math.floor(baseWidth * size / MT.DEFAULTS.size + 0.5)) end
end

-- Dresses a FontString for a pin's name and keeps it in step with the choices. baseWidth: its width at the
-- default size, when it has one.
function MT.Apply(fs, baseWidth)
    mapStrings[fs] = baseWidth or true
    StyleMapString(fs, baseWidth)
end

local function RestyleMapText()
    MT.fallback = false
    for fs, baseWidth in pairs(mapStrings) do StyleMapString(fs, baseWidth ~= true and baseWidth or nil) end
    for _, fn in ipairs(mapSubscribers) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

function MT.Set(key, value)
    if MT.DEFAULTS[key] == nil or not MT.Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.pinsMapText) ~= "table" then TwichUIDB.ui.pinsMapText = {} end
    TwichUIDB.ui.pinsMapText[key] = value
    RestyleMapText()
    return true
end

-- The map text back to its defaults. Pins, the window and the label choices are not touched.
function MT.Reset()
    if type(TwichUIDB) == "table" and type(TwichUIDB.ui) == "table" then TwichUIDB.ui.pinsMapText = nil end
    RestyleMapText()
end
if R.MenuStyle and R.MenuStyle.Fonts then R.MenuStyle.Fonts.Subscribe(RestyleMapText) end

---------------------------------------------------------------------------
-- The data bar entry (pins/Broker.lua): what its text says, its icon and the color of its text. The color is
-- only applied when asked for: a data bar draws its text in its own color otherwise, and a bar can strip
-- the color codes TwichUI writes (EllesmereUI's Broker Plugin block does, until its Strip Colors is off).
-- flash, flashSeconds, flashColor: for that many seconds after a pin arrives from another player the text
-- says so, in that color, and then goes back.
---------------------------------------------------------------------------
local BR = {}
PL.Bar = BR
BR.TEXTS = {
    { "count", "Pin count (5 pins, 2 party)" },
    { "number", "Number only (5)" },
    { "label", "Map Pins" },
    { "none", "None (icon only)" },
}
BR.DEFAULTS = { text = "count", icon = true, customColor = false, color = "ffc9a34a",
    flash = true, flashSeconds = 8, flashColor = "ffe8b64a" }
BR.LIMITS = { flashSeconds = { 2, 30 } }
local BAR_TEXT = {}
for _, t in ipairs(BR.TEXTS) do BAR_TEXT[t[1]] = true end

function BR.Valid(key, value)
    if key == "text" then return type(value) == "string" and BAR_TEXT[value] == true end
    if key == "icon" or key == "customColor" or key == "flash" then return type(value) == "boolean" end
    if key == "color" or key == "flashColor" then return Valid("accentColor", value) end
    if key == "flashSeconds" then
        local l = BR.LIMITS.flashSeconds
        return type(value) == "number" and value == value and value % 1 == 0 and value >= l[1] and value <= l[2]
    end
    return false
end

function BR.Get(key)
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.pinsBroker
    local value
    if type(t) == "table" then value = t[key] end   -- not "and ... or": a saved false is a value
    if BR.Valid(key, value) then return value end
    return BR.DEFAULTS[key]
end

local barSubscribers = {}
function BR.Subscribe(fn) barSubscribers[#barSubscribers + 1] = fn end
local function BarChanged()
    for _, fn in ipairs(barSubscribers) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

function BR.Set(key, value)
    if BR.DEFAULTS[key] == nil or not BR.Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.pinsBroker) ~= "table" then TwichUIDB.ui.pinsBroker = {} end
    TwichUIDB.ui.pinsBroker[key] = value
    BarChanged()
    return true
end

function BR.Reset()
    if type(TwichUIDB) == "table" and type(TwichUIDB.ui) == "table" then TwichUIDB.ui.pinsBroker = nil end
    BarChanged()
end

---------------------------------------------------------------------------
-- The data bar menu's look: its own, saved apart from the Mage launchers' and the window's. Its defaults are
-- the launchers' (a copy, so the menus match until the player changes one).
---------------------------------------------------------------------------
local menuDefaults = {}
for k, v in pairs(R.MenuStyle.DEFAULTS) do menuDefaults[k] = v end
PL.MenuLook = R.MenuStyle.New("pinsBrokerMenu", menuDefaults, { sources = true })

---------------------------------------------------------------------------
-- The new pin window's look (pins/Editor.lua): its own, saved apart from the pin window's. Its defaults are the
-- pin window's (a copy), so the two match until the player changes one.
---------------------------------------------------------------------------
local editorDefaults = {}
for k, v in pairs(PL.Look.DEFAULTS) do editorDefaults[k] = v end
PL.EditorLook = R.MenuStyle.New("pinsEditorLook", editorDefaults, { sources = true })

-- Read only, for /tui diagnostics.
function PL.Snapshot()
    return {
        barText = BR.Get("text"), barIcon = BR.Get("icon"), barColor = BR.Get("customColor"),
        barFlash = BR.Get("flash"), barFlashSeconds = BR.Get("flashSeconds"),
        menuBg = PL.MenuLook.Get("bgTexture") == "solid" and "solid" or "textured", menuBorder = PL.MenuLook.Get("borderTexture"),
        editorBg = PL.EditorLook.Get("bgTexture") == "solid" and "solid" or "textured", editorBorder = PL.EditorLook.Get("borderTexture"),
        localClick = PL.Pref("localClick"), partyClick = PL.Pref("partyClick"), labels = PL.Pref("labels"),
        minimap = PL.Pref("minimap"), minimapLabels = PL.Pref("minimapLabels"),
        mapFont = MT.Get("font") == "default" and "default" or "chosen", mapFontFallback = MT.fallback,
        mapSize = MT.Get("size"), mapOutline = MT.Get("outline"), mapShadow = MT.Get("shadow"),
        font = PL.Get("font") == "default" and "default" or "chosen", fontFallback = PL.fallback,
        bg = PL.Look.Get("bgTexture") == "solid" and "solid" or "textured", border = PL.Look.Get("borderTexture"),
        density = PL.Get("density"),
    }
end
