-- TwichUI: class resource bars, configuration
-- The one place that knows what the bars store and how a stored value becomes the style a bar is drawn with.
-- Nothing here touches a frame or the game's power APIs.
--
-- What is stored (all in the profile in use, TwichUIDB.ui; docs/class-bars.md has the details):
--   ui.classBars           the shared style: behavior (when to show), layout (sizes, spacing, placement), appearance
--                          (fill, text) and effects. DEFAULTS and LIMITS below; every value is checked on the way in
--                          and on the way out, and an invalid stored one reads as its default without being erased.
--   ui.classBarsLook       the bar's background and border: a MenuStyle look (modules/MenuStyle.lua), the same choices
--                          and media (LibSharedMedia, EllesmereUI's textures when it is installed) as the other frames
--   ui.classBarsOverrides  ["CLASS:RESOURCE"] = { colorSource, color, text, show }: what one resource of one class does
--                          differently from the shared style. A field that is not there is inherited. Keyed by the class
--                          token and the resource key, never a localized name, so a Mage's mana and a Priest's mana are
--                          separate and another class's entries are never touched by playing this one.
--   ui.classBarsPosition   { main = { x, y }, aux = { x, y } }: the centre of each bar group, in screen units from the
--                          centre of the screen. Kept on this computer (never shared); clamped to the screen on use.
-- The switch is TwichUIDB.modules.classBars (off until turned on).
--
-- Resolving: Style(slot, state, class) returns one table with everything a bar needs (colors, texture file, font
-- file, sizes, text mode, visibility rule), built from the shared style, then the override. It is cached per slot
-- and resource and thrown away by Invalidate(), which every setter, a profile change and a media registration
-- call; a bar compares style.rev to know whether to redraw. Nothing is resolved on a resource tick.

local R = TwichUI
local MS = R.MenuStyle
local CBR = R.ClassBarResources
local CB = {}
R.ClassBars = CB

local WHITE = [[Interface\Buttons\WHITE8x8]]

CB.DEFAULTS = {
    -- when to show
    show = "always", hideDead = true, hideMounted = false, hideVehicle = true,
    -- layout
    opacity = 100, scale = 100, placement = "below", gap = 2, segmentGap = 3,
    primaryOn = true, primaryWidth = 240, primaryHeight = 18,
    secondaryOn = true, secondaryWidth = 240, secondaryHeight = 12,
    tertiaryOn = true, tertiaryWidth = 240, tertiaryHeight = 8,
    -- fill
    texture = "solid", fillStyle = "solid", gradientDir = "horizontal", colorSource = "resource",
    color = "ffc9a24a", color2 = "ff7a5c1e", shade = 60, smoothing = false,
    -- text
    primaryText = "current", secondaryText = "current", tertiaryText = "none",
    font = "default", fontSize = 12, fontOutline = "outline", textColor = "fff0e8d2", textPlace = "center",
    -- effects (off until turned on)
    effects = false, effectsAccent = true, effectsClass = true, effectsThreshold = 100, effectsReducedMotion = false,
}

CB.LIMITS = {
    opacity = { 0, 100 }, scale = { 50, 200 }, gap = { 0, 40 }, segmentGap = { 0, 20 },
    primaryWidth = { 40, 800 }, primaryHeight = { 2, 80 },
    secondaryWidth = { 40, 800 }, secondaryHeight = { 2, 80 },
    tertiaryWidth = { 40, 800 }, tertiaryHeight = { 2, 80 },
    shade = { 20, 200 }, fontSize = { 6, 32 }, effectsThreshold = { 1, 100 },
}

local function Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

-- The choices of each text value, in the order settings lists them (also the sets a value is checked against).
CB.CHOICES = {
    show = { { "always", "Always" }, { "combat", "Only in combat" }, { "active", "In combat or when not at rest" } },
    placement = { { "below", "Below the main bar" }, { "above", "Above the main bar" }, { "separate", "Its own place" } },
    text = { { "current", "Current value" }, { "currentMax", "Current / maximum" }, { "percent", "Percentage" }, { "none", "Hidden" } },
    fillStyle = { { "solid", "Solid" }, { "gradient", "Gradient" } },
    gradientDir = { { "horizontal", "Left to right" }, { "vertical", "Bottom to top" } },
    colorSource = { { "resource", "The resource's color" }, { "class", "My class color" }, { "custom", "A color I choose" } },
    fontOutline = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" }, { "shadow", "Shadow" } },
    textPlace = { { "center", "Centered" }, { "left", "Left" }, { "right", "Right" } },
}
local ENUM = {}
for key, list in pairs(CB.CHOICES) do
    local values = {}
    for i, c in ipairs(list) do values[i] = c[1] end
    ENUM[key] = Set(values)
end
ENUM.primaryText, ENUM.secondaryText, ENUM.tertiaryText = ENUM.text, ENUM.text, ENUM.text
ENUM.overrideShow = Set({ "always", "combat", "active", "never" })
CB.ENUM = ENUM

-- Which keys belong to which part of the settings, for narrow resets.
CB.GROUPS = {
    behavior = { "show", "hideDead", "hideMounted", "hideVehicle" },
    layout = { "opacity", "scale", "placement", "gap", "segmentGap", "primaryOn", "primaryWidth", "primaryHeight",
        "secondaryOn", "secondaryWidth", "secondaryHeight", "tertiaryOn", "tertiaryWidth", "tertiaryHeight" },
    appearance = { "texture", "fillStyle", "gradientDir", "colorSource", "color", "color2", "shade", "smoothing",
        "primaryText", "secondaryText", "tertiaryText", "font", "fontSize", "fontOutline", "textColor", "textPlace" },
    effects = { "effects", "effectsAccent", "effectsClass", "effectsThreshold", "effectsReducedMotion" },
}

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil end
local function Name(v) return type(v) == "string" and #v > 0 and #v <= 100 and not v:find("[%c|]") end

local function Valid(key, value)
    local default = CB.DEFAULTS[key]
    if default == nil then return false end
    local kind = type(default)
    if kind == "boolean" then return type(value) == "boolean" end
    if kind == "number" then
        local lim = CB.LIMITS[key]
        return Whole(value) and lim ~= nil and value >= lim[1] and value <= lim[2]
    end
    if ENUM[key] then return type(value) == "string" and ENUM[key][value] == true end
    if Hex(default) then return Hex(value) end
    return Name(value)
end
CB.Valid = Valid

---------------------------------------------------------------------------
-- Change notices. Setters call Invalidate(); the controller listens.
---------------------------------------------------------------------------
local rev = 1
local cache = {}
local subscribers = {}
local moved = {}

function CB.Rev() return rev end

function CB.Subscribe(fn) subscribers[#subscribers + 1] = fn end
function CB.SubscribeMoved(fn) moved[#moved + 1] = fn end

local function Tell(list, ...)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then R.Fault("class bars", err) end
    end
end

-- Something a bar is drawn from changed: every resolved style is stale. Tells the controller once.
function CB.Invalidate()
    rev = rev + 1
    for k in pairs(cache) do cache[k] = nil end
    Tell(subscribers)
end

---------------------------------------------------------------------------
-- The shared style
---------------------------------------------------------------------------
local function Saved(create)
    local ui = TwichUIDB and TwichUIDB.ui
    if type(ui) ~= "table" then
        if not create or type(TwichUIDB) ~= "table" then return nil end
        TwichUIDB.ui = {}
        ui = TwichUIDB.ui
    end
    local t = ui.classBars
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        ui.classBars = t
    end
    return t
end

function CB.Get(key)
    local t = Saved(false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false or 0 is a value
    if Valid(key, value) then return value end
    return CB.DEFAULTS[key]
end

function CB.Set(key, value)
    if CB.DEFAULTS[key] == nil or not Valid(key, value) then return false end
    local t = Saved(true)
    if not t then return false end
    if t[key] == value then return true end   -- unchanged: nothing to redraw
    t[key] = value
    CB.Invalidate()
    return true
end

-- Puts the named shared values back to their defaults (they are forgotten, so a better default later still applies).
function CB.ResetKeys(keys)
    local t = Saved(false)
    if not t then return end
    local changed = false
    for _, key in ipairs(keys) do
        if t[key] ~= nil then t[key] = nil; changed = true end
    end
    if changed then CB.Invalidate() end
end

-- One part of the settings ("behavior", "layout", "appearance", "effects") back to its defaults. Nothing else changes.
function CB.ResetGroup(name)
    if CB.GROUPS[name] then CB.ResetKeys(CB.GROUPS[name]) end
end

---------------------------------------------------------------------------
-- The bar's background and border: a MenuStyle look, saved in TwichUIDB.ui.classBarsLook
---------------------------------------------------------------------------
CB.Look = MS.New("classBarsLook", {
    bgTexture = "solid", bgColor = "ff17130e", bgOpacity = 75,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 95, borderSize = 1,
})
CB.Look.Subscribe(function() CB.Invalidate() end)
MS.Fonts.Subscribe(function() CB.Invalidate() end)
MS.StatusBars.Subscribe(function() CB.Invalidate() end)

---------------------------------------------------------------------------
-- Overrides: what one resource of one class does differently
---------------------------------------------------------------------------
CB.MAX_OVERRIDES = 48
CB.OVERRIDE_FIELDS = { "colorSource", "color", "text", "show" }

local OV_VALID = {
    colorSource = function(v) return type(v) == "string" and ENUM.colorSource[v] == true end,
    color = Hex,
    text = function(v) return type(v) == "string" and ENUM.text[v] == true end,
    show = function(v) return type(v) == "string" and ENUM.overrideShow[v] == true end,
}

function CB.ValidOverrideKey(k)
    return type(k) == "string" and #k <= 48 and k:match("^%u[%u_]*:%u[%u_]*$") ~= nil
end

function CB.OverrideValid(field, value)
    local check = OV_VALID[field]
    return check ~= nil and check(value) == true
end

local function OverridesTable(create)
    local ui = TwichUIDB and TwichUIDB.ui
    if type(ui) ~= "table" then
        if not create or type(TwichUIDB) ~= "table" then return nil end
        TwichUIDB.ui = {}
        ui = TwichUIDB.ui
    end
    local t = ui.classBarsOverrides
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        ui.classBarsOverrides = t
    end
    return t
end

-- A field of an override, or nil when it is inherited (or the stored one is not usable).
function CB.GetOverride(ovKey, field)
    local t = OverridesTable(false)
    local entry = t and ovKey and t[ovKey]
    if type(entry) ~= "table" then return nil end
    local value = entry[field]
    if value ~= nil and CB.OverrideValid(field, value) then return value end
    return nil
end

-- Sets one field (value nil: inherit again). Returns false for a key or value that is not valid.
function CB.SetOverride(ovKey, field, value)
    if not CB.ValidOverrideKey(ovKey) or not OV_VALID[field] then return false end
    if value ~= nil and not CB.OverrideValid(field, value) then return false end
    local t = OverridesTable(value ~= nil)
    if not t then return true end
    local entry = t[ovKey]
    if value == nil then
        if type(entry) ~= "table" or entry[field] == nil then return true end
        entry[field] = nil
        if next(entry) == nil then t[ovKey] = nil end
    else
        if type(entry) ~= "table" then
            local n = 0
            for _ in pairs(t) do n = n + 1 end
            if n >= CB.MAX_OVERRIDES then return false end
            entry = {}
            t[ovKey] = entry
        end
        if entry[field] == value then return true end
        entry[field] = value
    end
    CB.Invalidate()
    return true
end

-- Whether an entry holds any usable field.
function CB.HasOverride(ovKey)
    for _, field in ipairs(CB.OVERRIDE_FIELDS) do
        if CB.GetOverride(ovKey, field) ~= nil then return true end
    end
    return false
end

-- Forgets one resource's override only.
function CB.ClearOverride(ovKey)
    local t = OverridesTable(false)
    if t and ovKey and t[ovKey] ~= nil then
        t[ovKey] = nil
        CB.Invalidate()
    end
end

-- Every stored override key, sorted (sharing and the reset plan read this).
function CB.OverrideKeys()
    local keys = {}
    local t = OverridesTable(false)
    for k in pairs(t or {}) do
        if CB.ValidOverrideKey(k) then keys[#keys + 1] = k end
    end
    table.sort(keys)
    return keys
end

---------------------------------------------------------------------------
-- Positions: the centre of each bar group from the centre of the screen. Kept per profile, never shared.
---------------------------------------------------------------------------
CB.DEFAULT_POSITION = { main = { 0, -180 }, aux = { 0, -236 } }
CB.POSITION_LIMIT = 8192

local function PositionTable(create)
    local ui = TwichUIDB and TwichUIDB.ui
    if type(ui) ~= "table" then
        if not create or type(TwichUIDB) ~= "table" then return nil end
        TwichUIDB.ui = {}
        ui = TwichUIDB.ui
    end
    local t = ui.classBarsPosition
    if type(t) ~= "table" then
        if not create then return nil end
        t = {}
        ui.classBarsPosition = t
    end
    return t
end

local function UsableOffset(v) return Finite(v) and math.abs(v) <= CB.POSITION_LIMIT end

-- x, y for "main" or "aux": the saved place, else the default. A saved place that is not two usable numbers is
-- ignored (and left as it is).
function CB.Position(group)
    local t = PositionTable(false)
    local saved = t and t[group]
    if type(saved) == "table" and UsableOffset(saved.x) and UsableOffset(saved.y) then return saved.x, saved.y end
    local d = CB.DEFAULT_POSITION[group] or CB.DEFAULT_POSITION.main
    return d[1], d[2]
end

function CB.HasPosition(group)
    local t = PositionTable(false)
    local saved = t and t[group]
    return type(saved) == "table" and UsableOffset(saved.x) and UsableOffset(saved.y)
end

-- Saves a place (x, y nil: back to the default). Tells the controller to move the bars.
function CB.SetPosition(group, x, y)
    if CB.DEFAULT_POSITION[group] == nil then return false end
    if x ~= nil and not (UsableOffset(x) and UsableOffset(y)) then return false end
    local t = PositionTable(x ~= nil)
    if not t then
        Tell(moved, group)
        return true
    end
    if x == nil then t[group] = nil else t[group] = { x = x, y = y } end
    Tell(moved, group)
    return true
end

-- A place kept on the screen: the centre stays within the screen's width and height less a margin, so the bar
-- can always be found and dragged, and Reset position always works. Pure. screenW and screenH are in the same
-- units as x and y.
function CB.ClampPosition(x, y, screenW, screenH)
    if not (Finite(x) and Finite(y) and Finite(screenW) and Finite(screenH) and screenW > 0 and screenH > 0) then
        return x, y
    end
    local maxX, maxY = screenW / 2 - 20, screenH / 2 - 10
    if maxX < 0 then maxX = 0 end
    if maxY < 0 then maxY = 0 end
    return math.max(-maxX, math.min(maxX, x)), math.max(-maxY, math.min(maxY, y))
end

-- A place in screen units (from the centre of the screen) for a frame centre read in the frame's own units, and
-- back. scale is the frame's effective scale, parentScale the screen's. Pure; the controller uses these to move a
-- bar with the pointer and to place it again at any scale.
function CB.ToOffset(cx, cy, scale, px, py, parentScale)
    if not (Finite(cx) and Finite(cy) and Finite(scale) and scale > 0 and Finite(px) and Finite(py) and Finite(parentScale) and parentScale > 0) then
        return nil
    end
    return (cx * scale - px * parentScale) / parentScale, (cy * scale - py * parentScale) / parentScale
end

-- The offset to hand SetPoint for a frame at group scale s so it sits x, y screen units from the centre.
function CB.FromOffset(x, y, s)
    if not (Finite(x) and Finite(y) and Finite(s) and s > 0) then return x, y end
    return x / s, y / s
end

---------------------------------------------------------------------------
-- Resolving a style
---------------------------------------------------------------------------
local function ParseColor(hex)
    local r, g, b = MS.ParseColor(hex)
    return r, g, b
end

local function Scale(r, g, b, percent)
    local f = percent / 100
    return math.min(1, r * f), math.min(1, g * f), math.min(1, b * f)
end

local FLAGS = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE", shadow = "" }

local function Build(slot, state, class, ovKey)
    local key = state.key
    local style = { rev = rev, slot = slot, key = key, ovKey = ovKey, kind = state.kind }

    -- size and placement
    style.width, style.height = CB.Get(slot .. "Width"), CB.Get(slot .. "Height")
    style.segGap = CB.Get("segmentGap")
    style.smoothing = CB.Get("smoothing")

    -- when to show, and what the text says: the override, else the shared value
    style.show = CB.GetOverride(ovKey, "show") or CB.Get("show")
    style.text = CB.GetOverride(ovKey, "text") or CB.Get(slot .. "Text")
    style.textPlace = CB.Get("textPlace")

    -- fill color: the override's source, else the shared one; a color the override chose means "a color I choose"
    local ovColor = CB.GetOverride(ovKey, "color")
    local source = CB.GetOverride(ovKey, "colorSource") or (ovColor and "custom") or CB.Get("colorSource")
    local r, g, b
    if source == "class" then r, g, b = CBR.ClassColor(class)
    elseif source == "custom" then r, g, b = ParseColor(ovColor or CB.Get("color"))
    else r, g, b = CBR.Color(key) end
    style.r, style.g, style.b = r, g, b
    style.gradient = CB.Get("fillStyle") == "gradient"
    if style.gradient then
        local r2, g2, b2
        if source == "custom" and not ovColor then r2, g2, b2 = ParseColor(CB.Get("color2"))
        else r2, g2, b2 = Scale(r, g, b, CB.Get("shade")) end
        style.r2, style.g2, style.b2 = r2, g2, b2
        style.dir = CB.Get("gradientDir") == "vertical" and "VERTICAL" or "HORIZONTAL"
        if CreateColor then
            style.c1, style.c2 = CreateColor(r, g, b, 1), CreateColor(r2, g2, b2, 1)
            if style.dir == "VERTICAL" then style.c1, style.c2 = style.c2, style.c1 end   -- the first color is the start: the bottom
        end
    end

    -- media: the texture file and the font file, resolved here so a tick never looks them up
    local file = MS.StatusBars.Resolve(CB.Get("texture"))
    style.texture = file or WHITE
    style.textureMissing = file == nil
    style.flatTexture = style.texture == WHITE
    local fallbackFont = rawget(_G, "STANDARD_TEXT_FONT") or [[Fonts\FRIZQT__.TTF]]
    style.font, style.fontState = MS.Fonts.Resolve(CB.Get("font"), fallbackFont)
    style.fontSize = CB.Get("fontSize")
    local outline = CB.Get("fontOutline")
    style.fontFlags, style.shadow = FLAGS[outline] or "", outline == "shadow"
    style.tr, style.tg, style.tb = ParseColor(CB.Get("textColor"))
    return style
end

-- The style a bar of this slot draws a resource with. state: { key, kind }. class: the player's class token.
-- The same table comes back until something is invalidated, so callers may keep it and compare style.rev.
function CB.Style(slot, state, class)
    local ovKey = CBR.OverrideKey(class, state.key)
    local ck = slot .. "|" .. tostring(ovKey or state.key) .. "|" .. tostring(state.kind)
    local style = cache[ck]
    if style then return style end
    style = Build(slot, state, class, ovKey)
    cache[ck] = style
    return style
end

-- The text a mode shows, for the settings page's sentence about it.
function CB.TextLabel(mode)
    for _, c in ipairs(CB.CHOICES.text) do if c[1] == mode then return c[2] end end
    return mode
end

-- Which slots a class can ever have, for settings (a page offers rows only for bars that exist for the player).
function CB.SlotsFor(class)
    local out = {}
    for _, slot in ipairs(CBR.SLOTS) do
        if CBR.HasSlot(slot, class) then out[#out + 1] = slot end
    end
    return out
end

R.Profiles.OnApply("look", "class-bars-style", function() CB.Invalidate() end)
