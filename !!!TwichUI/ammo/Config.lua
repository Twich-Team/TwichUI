-- TwichUI: Ammunition warning, configuration
-- What the warning stores and how a stored value is read. Nothing here touches a frame or the game's inventory.
--
-- What is stored (all in the profile in use, TwichUIDB.ui; docs/ammo-warning.md has the details):
--   ui.ammo          the warning's settings: when it shows, the icon, size and opacity, the text (font, size, outline,
--                    color) and the optional sound. DEFAULTS and LIMITS below; every value is checked on the way in and
--                    on the way out, and an invalid stored one reads as its default without being erased.
--   ui.ammoLook      the optional background and border behind the text: a MenuStyle look (modules/MenuStyle.lua).
--                    Both start as "none": the warning is text over the world until the player draws a panel.
--   ui.ammoPosition  { x, y }: the centre of the warning in screen units from the centre of the screen. Kept on this
--                    computer (never shared); clamped to the screen on use.
--   ui.ammoCustom    the ammunition the player registered (ammo/Items.lua).
-- The switch is TwichUIDB.modules.ammoWarning (off until turned on).
--
-- Every setter calls Invalidate(); the controller (Warning.lua) listens and does one refresh.

local R = TwichUI
local MS = R.MenuStyle
local AM = {}
R.Ammo = AM

AM.DEFAULTS = {
    style = "standard",
    show = "equipped",
    icon = true,
    scale = 100, opacity = 100,
    font = "default", fontSize = 28, fontOutline = "outline", textColor = "fff0e8d2",
    sound = false, soundName = "TwichUI Notification", soundChannel = "SFX",
}

AM.LIMITS = { scale = { 50, 300 }, opacity = { 20, 100 }, fontSize = { 12, 72 } }

local function Set(list)
    local s = {}
    for _, v in ipairs(list) do s[v] = true end
    return s
end

-- The choices of each text value, in the order settings lists them (also the sets a value is checked against).
AM.CHOICES = {
    style = {
        { "standard", "Standard", "The warning as one line of text, with the optional icon, background and border." },
        { "rpg", "RPG Notification", "A small heading, a bronze rule and the warning in the same type as the zone arrival card. It stays up until the problem is fixed." },
    },
    show = {
        { "equipped", "Whenever my ranged weapon needs ammunition", "Shown as soon as a problem is found, in or out of combat, so you can fix it before you pull." },
        { "combat", "Only in combat", "Shown only while you are in combat. A problem found out of combat appears when combat starts." },
    },
    fontOutline = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" }, { "shadow", "Shadow" } },
    soundChannel = {
        { "SFX", "Sound effects", "Follows the Sound Effects volume." },
        { "Master", "Master", "Follows only the Master volume, so it is heard even with sound effects turned down." },
        { "Dialog", "Dialog", "Follows the Dialog volume." },
        { "Ambience", "Ambience", "Follows the Ambience volume." },
    },
}
AM.ENUM = {}
for key, list in pairs(AM.CHOICES) do
    local values = {}
    for i, c in ipairs(list) do values[i] = c[1] end
    AM.ENUM[key] = Set(values)
end

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil end
local function Name(v) return type(v) == "string" and #v > 0 and #v <= 100 and not v:find("[%c|]") end

function AM.Valid(key, value)
    local default = AM.DEFAULTS[key]
    if default == nil then return false end
    if type(default) == "boolean" then return type(value) == "boolean" end
    if type(default) == "number" then
        local lim = AM.LIMITS[key]
        return Whole(value) and lim ~= nil and value >= lim[1] and value <= lim[2]
    end
    if AM.ENUM[key] then return type(value) == "string" and AM.ENUM[key][value] == true end
    if Hex(default) then return Hex(value) end
    return Name(value)
end

---------------------------------------------------------------------------
-- Change notices
---------------------------------------------------------------------------
local subscribers, moved = {}, {}

function AM.Subscribe(fn) subscribers[#subscribers + 1] = fn end
function AM.SubscribeMoved(fn) moved[#moved + 1] = fn end

local function Tell(list, ...)
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then R.Fault("ammunition warning", err) end
    end
end

-- Something the warning is drawn or decided from changed (a setting, the custom list, a profile): the controller
-- refreshes once.
function AM.Invalidate() Tell(subscribers) end

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------
local function Ui(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    return db.ui
end

local function Saved(create)
    local ui = Ui(create)
    if not ui then return nil end
    if type(ui.ammo) ~= "table" then
        if not create then return nil end
        ui.ammo = {}
    end
    return ui.ammo
end

function AM.Get(key)
    local t = Saved(false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false is a value
    if AM.Valid(key, value) then return value end
    return AM.DEFAULTS[key]
end

function AM.Set(key, value)
    if AM.DEFAULTS[key] == nil or not AM.Valid(key, value) then return false end
    local t = Saved(true)
    if not t then return false end
    if t[key] == value then return true end   -- unchanged: nothing to redraw
    t[key] = value
    AM.Invalidate()
    return true
end

-- Every setting back to its default (forgotten, so a better default later still applies). The look, the place and the
-- custom ammunition are separate and stay.
function AM.ResetSettings()
    local t = Saved(false)
    if not t then return end
    local changed = false
    for key in pairs(AM.DEFAULTS) do
        if t[key] ~= nil then t[key] = nil; changed = true end
    end
    if changed then AM.Invalidate() end
end

---------------------------------------------------------------------------
-- The background and border: a MenuStyle look, saved in TwichUIDB.ui.ammoLook. Nothing is drawn until chosen.
---------------------------------------------------------------------------
AM.Look = MS.New("ammoLook", {
    bgTexture = "none", bgColor = "ff17130e", bgOpacity = 80,
    borderTexture = "none", borderColor = "ff8c6e38", borderOpacity = 95, borderSize = 1,
})
AM.Look.Subscribe(function() AM.Invalidate() end)
MS.Fonts.Subscribe(function() AM.Invalidate() end)

---------------------------------------------------------------------------
-- The place: the centre of the warning from the centre of the screen. Kept per profile, never shared.
---------------------------------------------------------------------------
AM.DEFAULT_POSITION = { 0, 140 }
AM.POSITION_LIMIT = 8192

local function UsableOffset(v) return Finite(v) and math.abs(v) <= AM.POSITION_LIMIT end

-- x, y: the saved place, else the default. A saved place that is not two usable numbers is ignored (and left alone).
function AM.Position()
    local ui = Ui(false)
    local saved = ui and ui.ammoPosition
    if type(saved) == "table" and UsableOffset(saved.x) and UsableOffset(saved.y) then return saved.x, saved.y end
    return AM.DEFAULT_POSITION[1], AM.DEFAULT_POSITION[2]
end

function AM.HasPosition()
    local ui = Ui(false)
    local saved = ui and ui.ammoPosition
    return type(saved) == "table" and UsableOffset(saved.x) and UsableOffset(saved.y)
end

-- Saves a place (x nil: back to the default) and tells the controller to move the frame.
function AM.SetPosition(x, y)
    if x ~= nil and not (UsableOffset(x) and UsableOffset(y)) then return false end
    local ui = Ui(x ~= nil)
    if ui then
        if x == nil then ui.ammoPosition = nil else ui.ammoPosition = { x = x, y = y } end
    end
    Tell(moved)
    return true
end

-- A place kept on the screen: the centre stays within the screen less a margin, so the warning can always be found
-- and dragged, and Reset position always works. Pure; screenW and screenH are in the same units as x and y.
function AM.ClampPosition(x, y, screenW, screenH)
    if not (Finite(x) and Finite(y) and Finite(screenW) and Finite(screenH) and screenW > 0 and screenH > 0) then
        return x, y
    end
    local maxX, maxY = math.max(0, screenW / 2 - 20), math.max(0, screenH / 2 - 10)
    return math.max(-maxX, math.min(maxX, x)), math.max(-maxY, math.min(maxY, y))
end

-- A place in screen units (from the centre of the screen) for a frame centre read in the frame's own units. scale is
-- the frame's effective scale, parentScale the screen's. Pure.
function AM.ToOffset(cx, cy, scale, px, py, parentScale)
    if not (Finite(cx) and Finite(cy) and Finite(scale) and scale > 0 and Finite(px) and Finite(py) and Finite(parentScale) and parentScale > 0) then
        return nil
    end
    return (cx * scale - px * parentScale) / parentScale, (cy * scale - py * parentScale) / parentScale
end

-- The offset to hand SetPoint for a frame at scale s so it sits x, y screen units from the centre.
function AM.FromOffset(x, y, s)
    if not (Finite(x) and Finite(y) and Finite(s) and s > 0) then return x, y end
    return x / s, y / s
end
