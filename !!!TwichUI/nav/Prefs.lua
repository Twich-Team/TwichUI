-- TwichUI: Navigation, preferences and appearance
-- Saved choices, all in TwichUIDB.ui (in the profile, only stored once changed):
--   navigation      what navigation shows and how it behaves: the frame, the arrow, the world map and minimap trails, how
--                   near counts as arrived and how far off the route counts as off it, the arrival sound, reduced motion,
--                   and the appearance of its text, arrow and trail; where the frame and the arrow sit (`position`,
--                   `arrowPosition`, kept on this screen when settings are shared: TwichConfig's "place"; `unlockMode`, whether
--                   EllesmereUI's Unlock Mode moves them, nav/Unlock.lua: opt-in, local to this computer, in no reset scope)
--   navigationLook  the frame's background and border (a MenuStyle look)
-- Never saved: the destination, the route, progress, the search, anything about where you are. Nothing here is read per
-- frame: views ask when they are drawn and keep what they need until a change is announced (NP.Subscribe).
-- A value that can't be used is read as its default and kept as it was (a font from a media pack missing today).

local R = TwichUI
local NP = {}
R.NavPrefs = NP

local DEFAULTS = {
    -- what is shown
    frame = true, arrow = true, worldTrail = true, minimapTrail = true,
    -- behaviour
    arrivalYards = 8, offRouteYards = 20, arrivalSound = true, reducedMotion = false,
    -- getting there (nav/Journey.lua): what a journey may use, and how fast you move on the ground
    useFlights = true, useShips = true, useTeleports = true, useHearth = true, speed = "foot",
    -- the frame
    locked = true, unlockMode = false, frameScale = 100, font = "default", textSize = 12,
    titleColor = "ffefe6d0", textColor = "ffd6cfbd", accentColor = "ff5c9491",
    -- the arrow
    arrowAttached = false, arrowScale = 100, arrowColor = "ffffffff",
    -- the trail
    trailColor = "ff6cc0b8", trailOpacity = 85, trailWidth = 3, trailStyle = "line", ants = true, antSpeed = 2,
}
local LIMITS = {
    arrivalYards = { 3, 30 }, offRouteYards = { 10, 60 }, frameScale = { 60, 160 }, textSize = { 9, 18 },
    arrowScale = { 50, 200 }, trailOpacity = { 20, 100 }, trailWidth = { 2, 8 }, antSpeed = { 1, 4 },
}
local ENUM = { trailStyle = { line = true, dots = true }, speed = { foot = true, mount = true, fast = true } }
NP.DEFAULTS, NP.LIMITS, NP.ENUM = DEFAULTS, LIMITS, ENUM
NP.TRAIL_STYLES = { { "line", "Line" }, { "dots", "Dots" } }
NP.SPEEDS = { { "foot", "On foot" }, { "mount", "Mounted (60% faster)" }, { "fast", "Fast mount (100% faster)" } }

-- The scopes a reset covers (positions are their own: resetting the look never moves anything)
NP.GROUPS = {
    behavior = { "frame", "arrow", "worldTrail", "minimapTrail", "arrivalYards", "offRouteYards", "arrivalSound", "reducedMotion",
        "useFlights", "useShips", "useTeleports", "useHearth", "speed" },
    appearance = { "locked", "frameScale", "font", "textSize", "titleColor", "textColor", "accentColor", "arrowAttached",
        "arrowScale", "arrowColor", "trailColor", "trailOpacity", "trailWidth", "trailStyle", "ants", "antSpeed" },
}

local function Valid(key, value)
    local d = DEFAULTS[key]
    if d == nil then
        if key == "position" or key == "arrowPosition" then
            return type(value) == "table" and type(value.x) == "number" and type(value.y) == "number"
                and value.x == value.x and value.y == value.y and math.abs(value.x) < 10000 and math.abs(value.y) < 10000
        end
        return false
    end
    if type(d) == "boolean" then return type(value) == "boolean" end
    if type(d) == "number" then
        local lim = LIMITS[key]
        return type(value) == "number" and value == value and value % 1 == 0 and value >= lim[1] and value <= lim[2]
    end
    if ENUM[key] then return type(value) == "string" and ENUM[key][value] == true end
    if key == "font" then return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]") end
    return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil
end
NP.Valid = Valid

local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.navigation
    return type(t) == "table" and t or nil
end

function NP.Get(key)
    local t = Saved()
    local v = t and t[key]
    if Valid(key, v) then return v end
    return DEFAULTS[key]
end

local subscribers = {}
function NP.Subscribe(fn) subscribers[#subscribers + 1] = fn end
local function Notify(key)
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, key)
        if not ok then geterrorhandler()(err) end
    end
end
NP.Notify = Notify

-- Saves one choice (an unusable one is refused). Returns whether it was kept.
function NP.Set(key, value)
    if not Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.navigation) ~= "table" then TwichUIDB.ui.navigation = {} end
    local t = TwichUIDB.ui.navigation
    if t[key] == value then return true end
    t[key] = value
    Notify(key)
    return true
end

-- Forgets one saved place ("position" or "arrowPosition") so the default applies. Nothing else changes.
function NP.Clear(key)
    if key ~= "position" and key ~= "arrowPosition" then return end
    local t = Saved()
    if t and t[key] ~= nil then
        t[key] = nil
        Notify(key)
    end
end

-- Puts one scope back: "behavior", "appearance" (with the frame's background and border), or "position" (the frame and
-- the arrow back to their default places). Nothing else of TwichUI's is touched; navigation keeps running.
function NP.Reset(scope)
    local t = Saved()
    if scope == "position" then
        if t then t.position, t.arrowPosition = nil, nil end
        Notify("position")
        return
    end
    local keys = NP.GROUPS[scope]
    if not keys then return end
    if t then for _, k in ipairs(keys) do t[k] = nil end end
    if scope == "appearance" then NP.Look.Reset() end   -- notifies through its own subscription
    Notify(scope)
end

-- The frame's background and border
NP.Look = R.MenuStyle.New("navigationLook", {
    bgTexture = "solid", bgColor = "ff1e1b18", bgOpacity = 92,
    borderTexture = "solid", borderColor = "ff8c6e38", borderOpacity = 80, borderSize = 1,
}, { sources = true })
NP.Look.Subscribe(function() Notify("look") end)

function NP.Rgb(hex)
    return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255,
        tonumber(hex:sub(1, 2), 16) / 255
end

-- The font file for the frame's text (the game's when "default" or a pack is missing).
function NP.Font()
    local fallback = (GameFontNormal and GameFontNormal:GetFont()) or [[Fonts\FRIZQT__.TTF]]
    local path = R.MenuStyle.Fonts.Resolve(NP.Get("font"), fallback)
    return path or fallback
end

-- Whether navigation's own visuals keep still: its own setting. Directional updates are essential and never paused.
function NP.ReducedMotion() return NP.Get("reducedMotion") == true end
