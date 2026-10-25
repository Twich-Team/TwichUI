-- TwichUI: Target dragon artwork, configuration
-- What the artwork stores, which artwork a target gets, and where it goes. Nothing here touches a frame or the game.
--
-- What is stored (in the profile in use, TwichUIDB.ui.targetArt; flat, every value checked on the way in and out, an
-- invalid stored one reads as its default without being erased):
--   map<Kind>     the artwork for each kind of enemy (KINDS below): "none" or an ART id; the Boss row may also say
--                 "class" (use the row of the unit's classification)
--   opacity       percent
--   scale         percent of the base size (BaseHeight: at 100% a dragon's tail reaches the frame's bottom edge)
--   framePoint    the point on the target frame the artwork is placed at
--   artPoint      the point on the artwork placed there: "crook" (the inside corner of the dragon's curve) or a
--                 corner, edge or the centre
--   x, y          offsets in the target frame's own units (they grow and shrink with it)
--   mirror        drawn facing the other way
--   layer         "front" (over the frame) or "behind" (under it)
--   hideEllesmere while TwichUI's dragon shows, EllesmereUI's own dragon on the target is made invisible (Ellesmere.lua)
--   <id>X, <id>Y, <id>Scale   one artwork's own adjustment on top of the above (rareX, bossScale, ...)
-- The switch is TwichUIDB.modules.targetArt (off until turned on).

local R = TwichUI
local TA = {}
R.TargetArt = TA

local MEDIA = [[Interface\AddOns\!!!TwichUI\media\targetart\]]

-- The artwork. Made by tools/make_target_art.py from assets/target-art-*-source.png: each painting cropped to what is
-- visible and scaled so its longer side is 254 px, at the top left of a 256 x 256 texture with a 1 px clear margin. width/height: the
-- part of the texture used (texcoords), so the aspect ratio is the painting's own. crookX/crookY: where the inside
-- corner of the dragon's curve is, as fractions of that part from its top left. Placing every dragon by its crook is
-- what makes the three line up the same way on the frame, whatever empty space their paintings had.
-- restX/restY: how far each dragon rests into the frame from its crook, as fractions of its own width and height (in
-- towards the frame, and down). The crook alone keeps every pixel off the frame; these let the jaw rest on the frame's
-- top edge and the neck over its right edge, clear of the health text, judged by eye on rendered samples
-- (EllesmereUI's default 181 x 52 frame). They scale with the dragon, and apply only with the crook as the anchor.
TA.ART = {
    rare = { label = "Rare spawn", path = MEDIA .. "rare", width = 182, height = 256, crookX = 0.752, crookY = 0.404,
        restX = 0.08, restY = 0.06 },
    boss = { label = "Boss dragon", path = MEDIA .. "boss", width = 183, height = 256, crookX = 0.700, crookY = 0.310,
        restX = 0.07, restY = 0.05 },
    elite = { label = "Elite dragon", path = MEDIA .. "elite", width = 198, height = 256, crookX = 0.624, crookY = 0.280,
        restX = 0.05, restY = 0.03 },
    -- the wide set: the same dragons with a longer spear arm and wings, wider than tall (so 256 wide, less tall)
    rareWide = { label = "Rare spawn (wide)", path = MEDIA .. "rare-wide", width = 256, height = 187, crookX = 0.674,
        crookY = 0.423, restX = 0.04, restY = 0.05 },
    bossWide = { label = "Boss dragon (wide)", path = MEDIA .. "boss-wide", width = 256, height = 187, crookX = 0.665,
        crookY = 0.411, restX = 0.04, restY = 0.05 },
    eliteWide = { label = "Elite dragon (wide)", path = MEDIA .. "elite-wide", width = 256, height = 207, crookX = 0.656,
        crookY = 0.388, restX = 0.04, restY = 0.05 },
}
TA.ART_ORDER = { "rare", "boss", "elite", "rareWide", "bossWide", "eliteWide" }
TA.TEXTURE_SIZE = 256

-- The kinds of enemy a mapping is kept for, in the order settings lists them. "boss" is the game's own boss flag
-- (UnitIsBossMob, what the Forever target frame uses for its winged boss dragon); it is checked first. The others
-- are UnitClassification's values. "normal", "trivial" and "minus" have no row and never get artwork.
TA.KINDS = {
    { "boss", "Boss", "Units the game marks as a boss (dungeon and raid bosses, and others it flags). Checked first: \"Same as its classification\" uses the row below that matches the unit instead." },
    { "worldboss", "World boss", "The game's world boss classification (a skull level on the target frame)." },
    { "rareelite", "Rare elite", "The game's rare elite classification." },
    { "elite", "Elite", "The game's elite classification. Many friendly guards and most dungeon enemies are elite too." },
    { "rare", "Rare", "The game's rare classification (not elite)." },
}

TA.DEFAULTS = {
    mapBoss = "boss", mapWorldboss = "boss", mapRareelite = "boss", mapElite = "elite", mapRare = "rare",
    opacity = 100, scale = 100,
    framePoint = "TOPRIGHT", artPoint = "crook", x = 0, y = 0,
    mirror = false, layer = "front", hideEllesmere = false,
}

TA.LIMITS = { opacity = { 5, 100 }, scale = { 25, 300 }, x = { -200, 200 }, y = { -200, 200 } }

-- Each artwork's own adjustment, on top of the shared placement: <id>X, <id>Y (the frame's units) and <id>Scale
-- (percent of the shared size). 0, 0 and 100 change nothing.
TA.TUNE_LIMITS = { X = { -100, 100 }, Y = { -100, 100 }, Scale = { 50, 200 } }
TA.TUNE_DEFAULTS = { X = 0, Y = 0, Scale = 100 }
for _, id in ipairs(TA.ART_ORDER) do
    for part, default in pairs(TA.TUNE_DEFAULTS) do
        TA.DEFAULTS[id .. part] = default
        TA.LIMITS[id .. part] = TA.TUNE_LIMITS[part]
    end
end
function TA.TuneKey(id, part) return id .. part end

local POINTS = {
    { "TOPLEFT", "Top left" }, { "TOP", "Top" }, { "TOPRIGHT", "Top right" },
    { "LEFT", "Left" }, { "CENTER", "Centre" }, { "RIGHT", "Right" },
    { "BOTTOMLEFT", "Bottom left" }, { "BOTTOM", "Bottom" }, { "BOTTOMRIGHT", "Bottom right" },
}

local function ArtChoices(withClass)
    local list = {}
    if withClass then
        list[#list + 1] = { "class", "Same as its classification", "The row for the unit's classification decides." }
    end
    list[#list + 1] = { "none", "None", "No artwork." }
    for _, id in ipairs(TA.ART_ORDER) do list[#list + 1] = { id, TA.ART[id].label } end
    return list
end

local artPoints = { { "crook", "The dragon's crook", "The inside corner of the dragon's curve, between its head and its tail. Each artwork has its own, so all three sit the same way." } }
for _, p in ipairs(POINTS) do artPoints[#artPoints + 1] = p end

TA.CHOICES = {
    map = ArtChoices(false),
    mapBoss = ArtChoices(true),
    framePoint = POINTS,
    artPoint = artPoints,
    layer = {
        { "front", "In front of the frame", "Over the frame's bars and text. At the default place the dragon sits outside the frame, so nothing is covered." },
        { "behind", "Behind the frame", "Under the whole frame: only the parts outside it show." },
    },
}

-- The saved key of a kind's mapping ("boss" -> "mapBoss").
function TA.MapKey(kind) return "map" .. kind:sub(1, 1):upper() .. kind:sub(2) end

local function Set(list)
    local s = {}
    for _, c in ipairs(list) do s[c[1]] = true end
    return s
end

TA.ENUM = { framePoint = Set(TA.CHOICES.framePoint), artPoint = Set(TA.CHOICES.artPoint), layer = Set(TA.CHOICES.layer) }
for _, k in ipairs(TA.KINDS) do
    local key = TA.MapKey(k[1])
    TA.ENUM[key] = Set(k[1] == "boss" and TA.CHOICES.mapBoss or TA.CHOICES.map)
end

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end

function TA.Valid(key, value)
    local default = TA.DEFAULTS[key]
    if default == nil then return false end
    if type(default) == "boolean" then return type(value) == "boolean" end
    if type(default) == "number" then
        local lim = TA.LIMITS[key]
        return Whole(value) and value >= lim[1] and value <= lim[2]
    end
    return type(value) == "string" and TA.ENUM[key] ~= nil and TA.ENUM[key][value] == true
end

---------------------------------------------------------------------------
-- Change notices
---------------------------------------------------------------------------
local subscribers = {}

-- fn(key): key is the setting that changed, or nil for "everything" (a reset, a profile change).
function TA.Subscribe(fn) subscribers[#subscribers + 1] = fn end

function TA.Invalidate(key)
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, key)
        if not ok then R.Fault("target dragon artwork", err) end
    end
end

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------
local function Saved(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    if type(db.ui.targetArt) ~= "table" then
        if not create then return nil end
        db.ui.targetArt = {}
    end
    return db.ui.targetArt
end

function TA.Get(key)
    local t = Saved(false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false is a value
    if TA.Valid(key, value) then return value end
    return TA.DEFAULTS[key]
end

function TA.Set(key, value)
    if TA.DEFAULTS[key] == nil or not TA.Valid(key, value) then return false end
    local t = Saved(true)
    if not t then return false end
    if t[key] == value then return true end   -- unchanged: nothing to redraw
    t[key] = value
    TA.Invalidate(key)
    return true
end

-- Every setting back to its default (forgotten, so a better default later still applies). The switch stays.
function TA.ResetSettings()
    local t = Saved(false)
    if not t then return end
    local changed = false
    for key in pairs(TA.DEFAULTS) do
        if t[key] ~= nil then t[key] = nil; changed = true end
    end
    if changed then TA.Invalidate(nil) end
end

---------------------------------------------------------------------------
-- Which artwork. Pure: classification is UnitClassification's answer (or nil when unreadable), isBoss
-- UnitIsBossMob's (true, false or nil). Returns an ART id or nil.
---------------------------------------------------------------------------
local CLASSIFIED = { worldboss = true, rareelite = true, elite = true, rare = true }

function TA.Pick(classification, isBoss, get)
    get = get or TA.Get
    if isBoss == true then
        local v = get("mapBoss")
        if v ~= "class" then return TA.ART[v] and v or nil end
    end
    if type(classification) ~= "string" or not CLASSIFIED[classification] then return nil end
    local v = get(TA.MapKey(classification))
    return TA.ART[v] and v or nil
end

---------------------------------------------------------------------------
-- Where it goes. Pure.
---------------------------------------------------------------------------
TA.FALLBACK_FRAME_HEIGHT = 52   -- EllesmereUI's default target frame (46 health + 6 power), when a height can't be read

-- The artwork's height at 100%, for a frame frameH tall: with its crook on the frame's top corner, its tail reaches
-- the frame's bottom edge. So the size follows the frame (a taller frame, a longer dragon), and each painting keeps its
-- own proportions.
function TA.BaseHeight(id, frameH)
    local art = TA.ART[id]
    if not (Finite(frameH) and frameH >= 1) then frameH = TA.FALLBACK_FRAME_HEIGHT end
    return frameH / (1 - art.crookY)
end

-- The layout of artwork id on a frame frameH tall, with settings read through get: a table (out, reused) with
-- w, h (size), point, relPoint, x, y (for SetPoint against the frame), and l, r, t, b (texcoords).
function TA.Placement(id, frameH, get, out)
    get = get or TA.Get
    out = out or {}
    local art = TA.ART[id]
    local h = TA.BaseHeight(id, frameH) * get("scale") / 100 * get(id .. "Scale") / 100
    local w = h * art.width / art.height
    local mirror = get("mirror")
    out.w, out.h = w, h
    out.relPoint = get("framePoint")
    local x, y = get("x") + get(id .. "X"), get("y") + get(id .. "Y")
    local ap = get("artPoint")
    if ap == "crook" then
        -- the texture's top left is placed so the crook falls on the frame's point, then the dragon rests in by its own
        -- amount (towards the frame: left, or right when mirrored, and down)
        local cx = mirror and (1 - art.crookX) or art.crookX
        local inward = mirror and 1 or -1
        out.point = "TOPLEFT"
        out.x = x - cx * w + inward * art.restX * w
        out.y = y + art.crookY * h - art.restY * h
    else
        out.point, out.x, out.y = ap, x, y
    end
    local right = art.width / TA.TEXTURE_SIZE
    local bottom = art.height / TA.TEXTURE_SIZE
    if mirror then out.l, out.r = right, 0 else out.l, out.r = 0, right end
    out.t, out.b = 0, bottom
    return out
end
