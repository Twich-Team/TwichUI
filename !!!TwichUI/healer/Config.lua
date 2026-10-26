-- TwichUI: Healer Watch, what is stored
-- The settings of Healer Watch (one healer's mana, confirmed drinking and recent mana-related chat, shown in a small
-- panel) and how each stored value is read. Nothing here touches a frame, an event or a unit: it keeps the saved data,
-- checks it on the way in and on the way out, and says when something changed. Logic.lua decides (pure), Drinks.lua
-- knows what drinking looks like, Watch.lua reads the game, Display.lua draws. docs/healer-watch.md has the design.
--
-- What is stored (the profile in use, TwichUIDB.ui.healerWatch; switch: TwichUIDB.modules.healerWatch, off by default):
--   the settings in DEFAULTS (each checked against LIMITS or CHOICES; an unusable stored value reads as its default and
--   is left as it is), phrases = { { text, mode }, ... } (the chat phrases; missing: the default three; an empty list
--   is kept as the player's choice), and the place: point, x, y.
-- Never stored: who is being watched (a choice lasts for the session), any reading of mana, drinking or chat, any
-- preview or simulation, any timer. Who heals is not something TwichUI remembers about a player.

local R = TwichUI
local HW = {}
R.HealerWatch = HW

HW.POSITION_LIMIT = 4096
HW.MAX_PHRASES, HW.PHRASE_MAX = 12, 32   -- phrases, and characters in one

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil end
local function Name(v) return type(v) == "string" and #v > 0 and #v <= 100 and not v:find("[%c|]") end
HW.Finite, HW.Whole = Finite, Whole

---------------------------------------------------------------------------
-- Artwork (media\healerwatch\, made by tools/make_healer_watch_art.py from assets/healer-watch-source.png): square
-- textures with the painting centred, in three sizes. Adding one: a name in that tool's NAMES, run it, a line here.
---------------------------------------------------------------------------
local ART_PATH = R.PATH .. [[media\healerwatch\]]
HW.ART = {
    vessel = { label = "Mana flask" },     -- the panel's emblem (its painted liquid is decoration, never a gauge)
    cup = { label = "Drinking cup" },      -- confirmed drinking
    speech = { label = "Speech bubble" },  -- a mana-related message in chat
}

-- The file for artwork drawn `drawn` UI units square: 256 px over 64 units, 64 px down to 33, 32 px at 32 and under.
function HW.ArtFile(id, drawn)
    if not HW.ART[id] then return nil end
    drawn = drawn or 64
    if drawn > 64 then return ART_PATH .. id .. "-large" end
    if drawn <= 32 then return ART_PATH .. id .. "-small" end
    return ART_PATH .. id
end

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------
HW.DEFAULTS = {
    preset = "compact",
    -- who and where
    scope = "dungeon",
    -- what to show
    showName = true, manaFormat = "percent", showBar = true, showArt = true, showDrinking = true,
    chatDisplay = "text", showElapsed = false, showManaState = true, statusPlace = "below",
    -- mana thresholds, in percent: a state begins below its threshold and ends at or above its clear point
    lowAt = 30, lowClear = 35, criticalAt = 15, criticalClear = 20,
    -- chat
    chatParty = true, chatInstance = true, chatSay = false, chatWhisper = false, chatExpiry = 10,
    chatSound = false, chatSoundName = "TwichUI Notification",
    -- when to show
    visibility = "always", attnLow = true, attnCritical = true, attnDrinking = true, attnChat = true,
    showInCombat = true, showOutOfCombat = true, showSetup = false,
    -- appearance
    scale = 100, opacity = 100, width = 190, barHeight = 8, artSize = 34, font = "default", textSize = 13,
    outline = "shadow", colorMana = "ff4a78ad", colorLow = "ffc29a48", colorCritical = "ffb85a4a",
    colorText = "fff0e8d2", colorDim = "ffaaa192", barTexture = "solid", barBorder = true, panelBg = 0, panelBorder = false,
    fade = false, pulse = false, flashChat = false, flashCritical = false, flashDrinking = false,
    -- where it sits: a point of the screen and an offset from it, in screen units
    point = "CENTER", x = -300, y = -140,
}

HW.LIMITS = {
    lowAt = { 1, 99 }, lowClear = { 1, 100 }, criticalAt = { 0, 98 }, criticalClear = { 1, 100 }, chatExpiry = { 3, 60 },
    scale = { 50, 200 }, opacity = { 20, 100 }, width = { 100, 400 }, barHeight = { 3, 24 }, artSize = { 16, 128 },
    textSize = { 8, 24 }, panelBg = { 0, 90 }, x = { -HW.POSITION_LIMIT, HW.POSITION_LIMIT }, y = { -HW.POSITION_LIMIT, HW.POSITION_LIMIT },
}

HW.CHOICES = {
    preset = {
        { "compact", "Compact", "A small flask, the healer's name and mana, a mana bar and one line of status." },
        { "minimal", "Minimal", "The mana value with small drinking and chat marks; the name if you want it. No bar or artwork unless you turn them on." },
        { "artwork", "Artwork", "A larger flask with the mana beneath it, and the marks beside it." },
    },
    scope = {
        { "dungeon", "5-player dungeons", "Only inside a five-player dungeon, which the game reports as a party instance." },
        { "instance", "Dungeons and raids", "Inside any dungeon or raid instance." },
        { "group", "Anywhere in a group (for other group content)", "Wherever you are in a party or raid, inside an instance or not." },
        { "anywhere", "Anywhere, even alone (for testing)", "At all times, so you can try it on yourself. Meant for testing." },
    },
    manaFormat = {
        { "percent", "Percent", "34%" },
        { "current", "Current / maximum", "1450 / 4200" },
        { "both", "Both", "34%  1450 / 4200" },
        { "none", "No number", "Only the bar (or nothing, with the bar off)." },
    },
    chatDisplay = {
        { "text", "Mark and words", "The speech-bubble mark and a short excerpt of what was said." },
        { "icon", "Mark only", "The speech-bubble mark, with \"Mana message\" in the status line." },
        { "off", "Nothing", "Chat is not listened to at all." },
    },
    statusPlace = { { "below", "Below the bar" }, { "above", "Above the bar" } },
    visibility = {
        { "always", "Always (while it applies)", "Shown whenever you are where it applies, so you can glance at the healer's mana at any time." },
        { "attention", "Only when something needs attention", "Hidden until any of the conditions you tick below is true." },
    },
    outline = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" }, { "shadow", "Shadow" } },
    point = {
        { "CENTER", "Centre" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "LEFT", "Left" }, { "RIGHT", "Right" },
        { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" }, { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" },
    },
}
HW.ENUM = {}
for key, list in pairs(HW.CHOICES) do
    local set = {}
    for _, c in ipairs(list) do set[c[1]] = true end
    HW.ENUM[key] = set
end

-- What a preset sets. Choosing one writes these (they stay yours to change afterwards); nothing else is touched.
HW.PRESETS = {
    compact = { showName = true, manaFormat = "percent", showBar = true, showArt = true, chatDisplay = "text", artSize = 34, width = 190 },
    minimal = { showName = false, manaFormat = "percent", showBar = false, showArt = false, chatDisplay = "icon", width = 120 },
    artwork = { showName = true, manaFormat = "percent", showBar = true, showArt = true, chatDisplay = "icon", artSize = 72, width = 150 },
}

function HW.Valid(key, value)
    local default = HW.DEFAULTS[key]
    if default == nil then return false end
    if type(default) == "boolean" then return type(value) == "boolean" end
    if type(default) == "number" then
        local lim = HW.LIMITS[key]
        return Whole(value) and lim ~= nil and value >= lim[1] and value <= lim[2]
    end
    if HW.ENUM[key] then return type(value) == "string" and HW.ENUM[key][value] == true end
    if Hex(default) then return Hex(value) end
    return Name(value)
end

---------------------------------------------------------------------------
-- The mana bar's border: a MenuStyle look (modules/MenuStyle.lua), saved in TwichUIDB.ui.healerWatchBarLook, so its
-- texture, thickness, color and opacity are the same choices every other TwichUI frame offers (the game's and
-- LibSharedMedia's borders, EllesmereUI's while it is installed). Only the border is used: the bar draws its own track.
-- Whether it is drawn at all is the "barBorder" setting above. The default is the thin blackened-bronze line.
-- The bar's fill texture is "barTexture": MenuStyle.StatusBars' ids ("solid", "eui:<key>" or a LibSharedMedia name).
---------------------------------------------------------------------------
HW.BarLook = R.MenuStyle.New("healerWatchBarLook", {
    bgTexture = "none", bgColor = "ff17130e", bgOpacity = 80,
    borderTexture = "solid", borderColor = "ff332817", borderOpacity = 95, borderSize = 1,
})
HW.BAR_BORDER_KEYS = { "BorderTexture", "BorderSize", "BorderColor", "BorderOpacity" }

---------------------------------------------------------------------------
-- Change notices
---------------------------------------------------------------------------
local subscribers = {}
local rev = 0

function HW.Subscribe(fn) subscribers[#subscribers + 1] = fn end
function HW.Rev() return rev end

-- Something Healer Watch is drawn or decided from changed (a setting, the phrases, a profile): told once.
function HW.Invalidate(what)
    rev = rev + 1
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("healer watch", err) end
    end
end

HW.BarLook.Subscribe(function() HW.Invalidate("settings") end)
R.MenuStyle.StatusBars.Subscribe(function() HW.Invalidate("settings") end)

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
    if type(db.ui.healerWatch) ~= "table" then
        if not create then return nil end
        db.ui.healerWatch = {}
    end
    return db.ui.healerWatch
end

function HW.Get(key)
    local t = Saved(false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false is a value
    if HW.Valid(key, value) then return value end
    return HW.DEFAULTS[key]
end

-- what: "place" for the position (the frame moves; nothing else is drawn again), else "settings".
function HW.Set(key, value)
    if HW.DEFAULTS[key] == nil or not HW.Valid(key, value) then return false end
    local t = Saved(true)
    if not t then return false end
    if t[key] == value then return true end
    t[key] = value
    HW.Invalidate((key == "point" or key == "x" or key == "y") and "place" or "settings")
    return true
end

-- A preset writes its values together, then tells once.
function HW.ApplyPreset(id)
    local p = HW.PRESETS[id]
    if not p then return false end
    local t = Saved(true)
    if not t then return false end
    t.preset = id
    for key, value in pairs(p) do t[key] = value end
    HW.Invalidate("settings")
    return true
end

-- Every setting back to its default (forgotten, so a better default later still applies). The phrases and the place
-- are kept: they have resets of their own.
function HW.ResetSettings()
    local t = Saved(false)
    if not t then return end
    local changed = false
    for key in pairs(HW.DEFAULTS) do
        if key ~= "point" and key ~= "x" and key ~= "y" and t[key] ~= nil then t[key] = nil; changed = true end
    end
    if changed then HW.Invalidate("settings") end
    HW.BarLook.Reset()
end

---------------------------------------------------------------------------
-- The place: a point of the screen and an offset from it. Clamped to the screen when drawn (Display.lua).
---------------------------------------------------------------------------
function HW.Place() return HW.Get("point"), HW.Get("x"), HW.Get("y") end

function HW.SetPlace(point, x, y)
    if not (HW.ENUM.point[point] and Finite(x) and Finite(y)) then return false end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local lim = HW.POSITION_LIMIT
    if math.abs(x) > lim or math.abs(y) > lim then return false end
    local t = Saved(true)
    if not t then return false end
    if t.point == point and t.x == x and t.y == y then return true end
    t.point, t.x, t.y = point, x, y
    HW.Invalidate("place")
    return true
end

function HW.ResetPlace()
    local t = Saved(false)
    if not t or (t.point == nil and t.x == nil and t.y == nil) then return end
    t.point, t.x, t.y = nil, nil, nil
    HW.Invalidate("place")
end

---------------------------------------------------------------------------
-- Mana thresholds, made consistent: critical never above low, each clear point at or above its threshold, and the
-- critical clear point never above the low one. Pure (reads the settings, returns a new table); the stored values are
-- left as they are, so moving one slider never silently rewrites another.
--   A band begins when mana is below its threshold (strictly) and ends when mana is at or above its clear point, so a
--   healer hovering at the threshold doesn't flicker between states.
---------------------------------------------------------------------------
function HW.NormalizeThresholds(lowAt, lowClear, criticalAt, criticalClear)
    local low = math.max(1, math.min(99, lowAt))
    local lowC = math.max(low, math.min(100, lowClear))
    local crit = math.max(0, math.min(low, criticalAt))
    local critC = math.max(crit, math.min(lowC, criticalClear))
    return { low = low, lowClear = lowC, critical = crit, criticalClear = critC }
end

function HW.Thresholds()
    return HW.NormalizeThresholds(HW.Get("lowAt"), HW.Get("lowClear"), HW.Get("criticalAt"), HW.Get("criticalClear"))
end

---------------------------------------------------------------------------
-- Chat phrases: literal text (never a pattern), matched as a whole message ("exact") or as whole words ("word").
---------------------------------------------------------------------------
HW.PHRASE_MODES = {
    { "word", "Whole words", "Found anywhere in the message as whole words: \"oom\" matches \"oom!\" and \"going oom\" but not \"boom\"." },
    { "exact", "Whole message", "The message must be exactly the phrase, apart from case, spaces and punctuation at either end." },
}
local MODE = { word = true, exact = true }
HW.DEFAULT_PHRASES = { { text = "oom", mode = "word" }, { text = "out of mana", mode = "word" }, { text = "need mana", mode = "word" } }
-- A broad keyword offered (never on by default): it also matches "mana potion", "no mana issues" and the like.
HW.BROAD_PHRASE = { text = "mana", mode = "word" }

-- A phrase as the player typed it: trimmed, spaces collapsed, lowercase, no "|" or control characters, 1..PHRASE_MAX
-- characters. Returns it, or nil and a sentence.
function HW.CleanPhrase(raw)
    if type(raw) ~= "string" then return nil, "Type a phrase first." end
    local text = raw:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""):lower()
    if text == "" then return nil, "Type a phrase first." end
    if text:find("[%c|]") then return nil, "A phrase can't contain | or control characters." end
    local n = 0
    for _ in text:gmatch("[^\128-\191]") do n = n + 1 end
    if n > HW.PHRASE_MAX then return nil, ("A phrase can be up to %d characters."):format(HW.PHRASE_MAX) end
    return text
end

local function CopyDefaults()
    local out = {}
    for i, p in ipairs(HW.DEFAULT_PHRASES) do out[i] = { text = p.text, mode = p.mode } end
    return out
end

-- The phrases in use, checked: a new list of { text, mode }. Never the stored table.
function HW.Phrases()
    local t = Saved(false)
    local raw = t and t.phrases
    if type(raw) ~= "table" then return CopyDefaults() end
    local out, seen = {}, {}
    for _, p in ipairs(raw) do
        if #out >= HW.MAX_PHRASES then break end
        local text = type(p) == "table" and HW.CleanPhrase(p.text) or nil
        local mode = type(p) == "table" and MODE[p.mode] and p.mode or "word"
        if text and not seen[text .. "\0" .. mode] then
            seen[text .. "\0" .. mode] = true
            out[#out + 1] = { text = text, mode = mode }
        end
    end
    return out
end

local function Store(list)
    local t = Saved(true)
    if not t then return false end
    local copy = {}
    for i, p in ipairs(list) do copy[i] = { text = p.text, mode = p.mode } end
    t.phrases = copy
    HW.Invalidate("phrases")
    return true
end

-- Each returns true, or false and a sentence.
function HW.AddPhrase(raw, mode)
    local text, why = HW.CleanPhrase(raw)
    if not text then return false, why end
    mode = MODE[mode] and mode or "word"
    local list = HW.Phrases()
    for _, p in ipairs(list) do
        if p.text == text and p.mode == mode then return false, "That phrase is already in the list." end
    end
    if #list >= HW.MAX_PHRASES then return false, ("The list holds %d phrases. Remove one first."):format(HW.MAX_PHRASES) end
    list[#list + 1] = { text = text, mode = mode }
    return Store(list)
end

function HW.RemovePhrase(i)
    local list = HW.Phrases()
    if not (Whole(i) and list[i]) then return false, "That phrase isn't in the list any more." end
    table.remove(list, i)
    return Store(list)
end

function HW.SetPhraseMode(i, mode)
    local list = HW.Phrases()
    if not (Whole(i) and list[i] and MODE[mode]) then return false, "That can't be changed." end
    if list[i].mode == mode then return true end
    list[i].mode = mode
    return Store(list)
end

-- Back to the default three (forgotten, so the defaults apply).
function HW.ResetPhrases()
    local t = Saved(false)
    if not t or t.phrases == nil then return end
    t.phrases = nil
    HW.Invalidate("phrases")
end

---------------------------------------------------------------------------
-- A profile change puts another profile's settings in place: everything is read again.
---------------------------------------------------------------------------
R.Profiles.OnApply("layout", "healerWatch", function() HW.Invalidate("profile") end)
