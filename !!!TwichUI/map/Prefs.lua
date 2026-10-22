-- TwichUI: world map exploration, saved choices
-- Kept in TwichUIDB.ui.mapExplore (in the profile; only stored once changed). Whether the feature is on at all is the
-- switch modules.mapExplore (Core.lua; off until turned on). Nothing about where you looked is ever saved: the view,
-- the way back, an open cave or dungeon map are this session's only. Nothing here is read per frame: the map's parts
-- ask when they lay out and follow MXP.Subscribe.
-- A saved value that can't be used is read as its default and left as it was.

local R = TwichUI
local MXP = {}
R.MapExplorePrefs = MXP

local DEFAULTS = {
    -- zoom and panning
    maxZoom = 48,            -- the deepest zoom, in times the whole world (more over a city, as far as a cave needs)
    wheelStep = 25,          -- percent a wheel notch zooms
    smooth = true,           -- zoom and moves ease over a fraction of a second (off: at once)
    controls = true,         -- the zoom buttons on the map
    unexplored = "dim",      -- the zones' areas you haven't explored: "show", "dim" or "hide"
    -- detail
    detail = true,           -- the game's own minimap pictures over the map when zoomed in close
    detailStrength = 70,     -- how strongly, in percent
    -- places
    caves = true, dungeons = true, travel = true,
    labels = true,           -- names beside places when zoomed in (never where they would overlap)
    iconSize = 100, iconOpacity = 100,
}
local LIMITS = {
    maxZoom = { 16, 192 }, wheelStep = { 10, 50 }, detailStrength = { 20, 100 }, iconSize = { 70, 150 }, iconOpacity = { 40, 100 },
}
local ENUM = { unexplored = { show = true, dim = true, hide = true } }
MXP.DEFAULTS, MXP.LIMITS, MXP.ENUM = DEFAULTS, LIMITS, ENUM
MXP.UNEXPLORED = { { "show", "Shown" }, { "dim", "Dimmed" }, { "hide", "Hidden" } }

-- What each reset puts back
MXP.GROUPS = {
    behavior = { "maxZoom", "wheelStep", "smooth", "controls", "unexplored" },
    detail = { "detail", "detailStrength" },
    places = { "caves", "dungeons", "travel", "labels", "iconSize", "iconOpacity" },
}

local function Valid(key, value)
    local d = DEFAULTS[key]
    if d == nil then return false end
    if type(d) == "boolean" then return type(value) == "boolean" end
    if ENUM[key] then return type(value) == "string" and ENUM[key][value] == true end
    local lim = LIMITS[key]
    return type(value) == "number" and value == value and value % 1 == 0 and value >= lim[1] and value <= lim[2]
end
MXP.Valid = Valid

local function Saved()
    local ui = TwichUIDB and TwichUIDB.ui
    local t = ui and ui.mapExplore
    return type(t) == "table" and t or nil
end

function MXP.Get(key)
    local t = Saved()
    local v = t and t[key]
    if Valid(key, v) then return v end
    return DEFAULTS[key]
end

local subscribers = {}
function MXP.Subscribe(fn) subscribers[#subscribers + 1] = fn end
local function Notify(key)
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, key)
        if not ok then geterrorhandler()(err) end
    end
end
MXP.Notify = Notify

-- Saves one choice (an unusable one is refused). Returns whether it was kept.
function MXP.Set(key, value)
    if not Valid(key, value) or type(TwichUIDB) ~= "table" then return false end
    TwichUIDB.ui = type(TwichUIDB.ui) == "table" and TwichUIDB.ui or {}
    if type(TwichUIDB.ui.mapExplore) ~= "table" then TwichUIDB.ui.mapExplore = {} end
    local t = TwichUIDB.ui.mapExplore
    if t[key] == value then return true end
    t[key] = value
    Notify(key)
    return true
end

-- Puts one scope back ("behavior", "detail", "places", or "all"). Pins, pings, routes and the switch are not touched.
function MXP.Reset(scope)
    local t = Saved()
    local groups = scope == "all" and { "behavior", "detail", "places" } or { scope }
    for _, g in ipairs(groups) do
        for _, k in ipairs(MXP.GROUPS[g] or {}) do
            if t then t[k] = nil end
        end
    end
    Notify(scope)
end
