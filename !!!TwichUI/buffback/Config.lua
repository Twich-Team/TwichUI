-- TwichUI: Return the Favor, what is stored
-- The settings of Return the Favor (a short list of the players who just buffed you; click one to buff them back)
-- and how each stored value is read. Nothing here touches a frame, an event or a unit: it keeps the saved data,
-- checks it on the way in and on the way out, and says when something changed. Spells.lua knows the buffs (pure),
-- Watch.lua reads the game, List.lua draws, Unlock.lua is EllesmereUI's mover. docs/return-the-favor.md has the design.
--
-- What is stored (the profile in use, TwichUIDB.ui.buffBack; switch: TwichUIDB.modules.buffBack, off by default):
--   the settings in DEFAULTS (each checked against LIMITS or CHOICES; an unusable stored value reads as its default
--   and is left as it is) and the place: x, y, the list's centre as an offset from the screen's centre. The rows'
--   look (background and border) is a MenuStyle look in TwichUIDB.ui.buffBackLook.
-- Never stored: who buffed you, what with, when, or whom you thanked. The list lasts for the session only.

local R = TwichUI
local BB = {}
R.BuffBack = BB

BB.POSITION_LIMIT = 4096

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil end
local function Name(v) return type(v) == "string" and #v > 0 and #v <= 100 and not v:find("[%c|]") end
BB.Finite, BB.Whole = Finite, Whole

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------
BB.DEFAULTS = {
    -- what is listed
    duration = 60, maxRows = 5, anyBuff = false,
    -- where it pauses (nothing is listed and nobody is thanked there)
    hideDungeon = false, hideRaid = true, hidePvP = true, hideResting = false, hideCombat = false,
    -- thanking them
    thank = false, thankEmote = "THANK", thankDelay = 3, thankAfterReturn = false,
    -- layout
    growth = "down", width = 200, rowHeight = 28, spacing = 3, iconSize = 22, scale = 100, opacity = 100,
    -- text
    font = "default", textSize = 12, outline = "shadow", classColor = true, nameColor = "fff0e8d2",
    textColor = "ffaaa192", showSpellName = true, showReturn = true,
    -- where it sits: the centre as an offset from the screen's centre, in screen units
    unlockMode = false, x = -420, y = 180,
}

BB.LIMITS = {
    duration = { 10, 600 }, maxRows = { 1, 10 }, thankDelay = { 0, 30 },
    width = { 120, 400 }, rowHeight = { 18, 48 }, spacing = { 0, 12 }, iconSize = { 12, 44 },
    scale = { 50, 200 }, opacity = { 20, 100 }, textSize = { 8, 20 },
    x = { -BB.POSITION_LIMIT, BB.POSITION_LIMIT }, y = { -BB.POSITION_LIMIT, BB.POSITION_LIMIT },
}

BB.CHOICES = {
    growth = {
        { "down", "Downwards", "The newest name is at the top and the list grows down from there." },
        { "up", "Upwards", "The newest name is at the bottom and the list grows up from there." },
    },
    outline = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" }, { "shadow", "Shadow" } },
    -- the game's emote tokens (its own /thank, /bow ... commands); each names the player it is aimed at
    thankEmote = {
        { "THANK", "Thank (/thank)", "\"You thank Anna.\"" },
        { "BOW", "Bow (/bow)", "\"You bow before Anna.\"" },
        { "SALUTE", "Salute (/salute)", "\"You salute Anna with respect.\"" },
        { "SMILE", "Smile (/smile)", "\"You smile at Anna.\"" },
        { "WAVE", "Wave (/wave)", "\"You wave at Anna.\"" },
        { "CHEER", "Cheer (/cheer)", "\"You cheer at Anna.\"" },
    },
}
BB.ENUM = {}
for key, list in pairs(BB.CHOICES) do
    local set = {}
    for _, c in ipairs(list) do set[c[1]] = true end
    BB.ENUM[key] = set
end

function BB.Valid(key, value)
    local default = BB.DEFAULTS[key]
    if default == nil then return false end
    if type(default) == "boolean" then return type(value) == "boolean" end
    if type(default) == "number" then
        local lim = BB.LIMITS[key]
        return Whole(value) and lim ~= nil and value >= lim[1] and value <= lim[2]
    end
    if BB.ENUM[key] then return type(value) == "string" and BB.ENUM[key][value] == true end
    if Hex(default) then return Hex(value) end
    return Name(value)
end

---------------------------------------------------------------------------
-- The rows' look: a MenuStyle look (modules/MenuStyle.lua), saved in TwichUIDB.ui.buffBackLook, so the background
-- and border are the same choices every other TwichUI frame offers (the game's and LibSharedMedia's textures,
-- EllesmereUI's while it is installed). Each row is drawn with it. The default is a warm umber with a bronze line.
---------------------------------------------------------------------------
BB.Look = R.MenuStyle.New("buffBackLook", {
    bgTexture = "solid", bgColor = "ff1d1711", bgOpacity = 88,
    borderTexture = "solid", borderColor = "ff6e5630", borderOpacity = 90, borderSize = 1,
})

---------------------------------------------------------------------------
-- Change notices
---------------------------------------------------------------------------
local subscribers = {}

function BB.Subscribe(fn) subscribers[#subscribers + 1] = fn end

-- Something the list is drawn or decided from changed (a setting, its look, a profile): told once.
-- what: "place" (only the place changed), "settings", "look" or "profile".
function BB.Invalidate(what)
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("return the favor", err) end
    end
end

BB.Look.Subscribe(function() BB.Invalidate("look") end)
R.MenuStyle.Fonts.Subscribe(function() BB.Invalidate("look") end)

---------------------------------------------------------------------------
-- Reading and writing
---------------------------------------------------------------------------
local function Saved(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    if type(db.ui.buffBack) ~= "table" then
        if not create then return nil end
        db.ui.buffBack = {}
    end
    return db.ui.buffBack
end

function BB.Get(key)
    local t = Saved(false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false is a value
    if BB.Valid(key, value) then return value end
    return BB.DEFAULTS[key]
end

function BB.Set(key, value)
    if BB.DEFAULTS[key] == nil or not BB.Valid(key, value) then return false end
    local t = Saved(true)
    if not t then return false end
    if t[key] == value then return true end
    t[key] = value
    BB.Invalidate((key == "x" or key == "y") and "place" or "settings")
    return true
end

-- Every setting back to its default (forgotten, so a better default later still applies), and the rows' look.
-- The place and the Unlock Mode choice are kept: the place has a reset of its own.
function BB.ResetSettings()
    local t = Saved(false)
    if t then
        for key in pairs(BB.DEFAULTS) do
            if key ~= "x" and key ~= "y" and key ~= "unlockMode" then t[key] = nil end
        end
    end
    BB.Look.Reset()
    BB.Invalidate("settings")
end

---------------------------------------------------------------------------
-- The place: the list's centre as an offset from the screen's centre (the list is always as tall as its most
-- rows, so it does not move as names come and go).
---------------------------------------------------------------------------
function BB.Place() return BB.Get("x"), BB.Get("y") end

function BB.ValidOffset(v) return Finite(v) and math.abs(v) <= BB.POSITION_LIMIT end

function BB.SetPlace(x, y)
    if not (BB.ValidOffset(x) and BB.ValidOffset(y)) then return false end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local t = Saved(true)
    if not t then return false end
    if t.x == x and t.y == y then return true end
    t.x, t.y = x, y
    BB.Invalidate("place")
    return true
end

function BB.ResetPlace()
    local t = Saved(false)
    if not t or (t.x == nil and t.y == nil) then return end
    t.x, t.y = nil, nil
    BB.Invalidate("place")
end

-- The list's size in its own (unscaled) units: as wide as a row and as tall as its most rows.
function BB.Footprint()
    local rows, h, gap = BB.Get("maxRows"), BB.Get("rowHeight"), BB.Get("spacing")
    return BB.Get("width"), rows * h + (rows - 1) * gap
end

---------------------------------------------------------------------------
-- A profile change puts another profile's settings in place: everything is read again.
---------------------------------------------------------------------------
R.Profiles.OnApply("layout", "buffBack", function() BB.Invalidate("profile") end)
