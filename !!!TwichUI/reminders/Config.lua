-- TwichUI: Reminders, what is stored
-- The player's reminders, each a name, who it is for, its conditions, what it shows and where. Nothing here touches a
-- frame, an event or the game's equipment: it keeps the saved data, checks it, and says what changed. Conditions.lua
-- knows each kind of condition, Evaluate.lua decides (pure), State.lua reads the game, Display.lua draws, and
-- Controller.lua puts them together. docs/reminders.md has the design.
--
-- What is stored (the profile in use, TwichUIDB.ui.reminders; switch: TwichUIDB.modules.reminders):
--   { version = 1,        the shape of this table (RM.VERSION); not the addon's version or TwichUIDB.schema
--     nextId = n,         the next id to give out, so an id is never reused within a profile
--     list = { reminder, ... } }   in the order the settings list shows them
--   reminder = { id = "r<n>", name, enabled (true only when the player turned it on),
--     scope = { who = "all" | "characters", characters = { "Name - Realm", ... }, class = nil | a class token },
--     match = "all" | "any",
--     conditions = { { type = "<provider>", ... } | { type = "group", match = "all" | "any", conditions = { ... } }, ... }
--         each kind's fields are its provider's (Conditions.lua). `match` + `conditions` are the top level of a tree; a
--         group is a condition of type "group" holding a list of the same shape, so (A or B or C) and D is
--         match "all", conditions { { type = "group", match = "any", conditions = { A, B, C } }, D }.
--     display = { mode, art, iconSource, icon, item, text, size, keepAspect, width, height, opacity, textSize,
--                 textPlace, font, outline, textColor, panel, strata, fade, pulse, delay, minShow },
--     place = { preset, point, x, y } }
-- Nothing else: no result, no observation, no preview state, no frame. Who a reminder is for (scope) is kept apart
-- from how it looks (display) and where it sits (place).
--
-- Groups need no migration: a list of conditions that has none is read exactly as it always was, and `version` stays 1.
-- A build from before groups reads a group as a condition of an unknown kind (it is kept, listed as a problem, and the
-- reminder can't run until it is removed); it never rewrites it. Limits: RM.MAX_DEPTH levels of group counting the top
-- level as the first, RM.MAX_GROUPS groups and RM.MAX_CONDITIONS conditions (groups not counted) in one reminder.
--
-- Reading never writes. A stored value that is not usable reads as its default and is left as it is; a condition of a
-- kind this version doesn't know, or one not finished (no item chosen yet), is kept and flagged, and the reminder can't
-- be turned on (or, already on, doesn't show) until it is fixed. A table made by a newer TwichUI (version above
-- RM.VERSION) is read but never written. Every change is checked first, written with plain assignments, and then told
-- once (RM.Subscribe).

local R = TwichUI
local RM = {}
R.Reminders = RM

RM.VERSION = 1
RM.MAX = 24               -- reminders in one profile
RM.MAX_CONDITIONS = 16    -- conditions in one reminder, in all its groups together (a group is not a condition)
RM.MAX_GROUPS = 6         -- groups in one reminder, at any depth (the top level is not one)
RM.MAX_DEPTH = 3          -- levels of conditions: the top level is 1, a group in it 2, a group in that 3
RM.MAX_CHARACTERS = 20    -- characters one reminder can be limited to
RM.NAME_MAX, RM.TEXT_MAX = 40, 120   -- characters
RM.POSITION_LIMIT = 4096
RM.SMALL_AT = 64          -- drawn at or under this many units, artwork uses its small file

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil end
RM.Finite, RM.Whole = Finite, Whole

-- Plain text the player typed: trimmed, no control characters and no "|" (the game reads "|" as markup, so it would
-- change how the text is drawn), at most max characters (whole characters, never part of one). Returns the text, or
-- nil and a reason code.
function RM.PlainText(raw, max, allowEmpty)
    if type(raw) ~= "string" then return nil, "empty" end
    local text = raw:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        if allowEmpty then return "" end
        return nil, "empty"
    end
    if text:find("[%c|]") then return nil, "characters" end
    local n = 0
    for _ in text:gmatch("[^\128-\191]") do n = n + 1 end
    if n > max then return nil, "long" end
    return text
end

function RM.ValidItem(v) return Whole(v) and v >= 1 and v <= 2147483647 end

-- An item ID from what the player typed or pasted: the number, or an item link (its "item:<id>"). nil when neither.
function RM.ParseItem(value)
    if type(value) == "string" then
        value = tonumber(value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$"))
    end
    if RM.ValidItem(value) then return value end
end

---------------------------------------------------------------------------
-- Artwork: the pictures a reminder can show, made by tools/make_reminder_art.py from assets/. Adding one: its line in
-- that tool's ART table, run it, then its line here (the numbers are what the tool prints) and a label.
---------------------------------------------------------------------------
local ART_PATH = R.PATH .. [[media\reminders\]]
RM.ART = {
    shield = { label = "Shield", size = 256, width = 182, height = 256, smallSize = 64, smallWidth = 46, smallHeight = 64 },
    ammo = { label = "Arrows", size = 256, width = 217, height = 256, smallSize = 64, smallWidth = 54, smallHeight = 64 },
}
RM.ART_ORDER = { "shield", "ammo" }

function RM.Art(id) return type(id) == "string" and RM.ART[id] or nil end

-- The file and texcoords for artwork drawn `drawn` units on its longer side, and its width / height ratio.
function RM.ArtTexture(id, drawn)
    local a = RM.Art(id)
    if not a then return nil end
    local small = drawn and drawn <= RM.SMALL_AT
    local side, w, h = a.size, a.width, a.height
    local file = ART_PATH .. id
    if small then side, w, h, file = a.smallSize, a.smallWidth, a.smallHeight, file .. "-small" end
    -- the used part less its 1 px clear margin on each side
    return file, 1 / side, (w - 1) / side, 1 / side, (h - 1) / side, (a.width - 2) / (a.height - 2)
end

-- TwichUI's own icons a reminder can show (R.Icons ids), for an icon that doesn't come from an item.
RM.ICONS = {
    { "reminderShow", "Framed shield" }, { "reminders", "Bell" }, { "reminderTest", "Checklist" },
    { "hazardAlerts", "Warning shield" }, { "ammunition", "Quiver" }, { "foodAndDrink", "Bread and cup" },
    { "gearComparison", "Breastplate" }, { "mage", "Arcane staff" },
}
local ICON_SET = {}
for _, i in ipairs(RM.ICONS) do ICON_SET[i[1]] = true end
function RM.ValidIcon(id) return ICON_SET[id] == true and R.Icons ~= nil and R.Icons.Get(id) ~= nil end

---------------------------------------------------------------------------
-- How a reminder looks: defaults, ranges and choices. Values are checked on the way in and on the way out.
---------------------------------------------------------------------------
RM.DISPLAY_DEFAULTS = {
    mode = "artworkText", art = "shield", iconSource = "bundled", icon = "reminderShow", text = "",
    size = 64, keepAspect = true, width = 64, height = 64, opacity = 100,
    textSize = 18, textPlace = "below", font = "default", outline = "outline", textColor = "fff0e8d2",
    panel = "none", strata = "MEDIUM", fade = false, pulse = false, delay = 0, minShow = 0,
}
RM.LIMITS = {
    size = { 16, 256 }, width = { 16, 256 }, height = { 16, 256 }, opacity = { 10, 100 }, textSize = { 10, 48 },
    delay = { 0, 30 }, minShow = { 0, 60 },
}
RM.CHOICES = {
    mode = {
        { "artworkText", "Artwork with text", "A picture from TwichUI's gallery with your words beside it." },
        { "artwork", "Artwork", "A picture from TwichUI's gallery, nothing else." },
        { "iconText", "Icon with text", "A small square icon with your words beside it." },
        { "icon", "Icon", "A small square icon, nothing else." },
        { "text", "Text only", "Your words, nothing else." },
    },
    iconSource = {
        { "bundled", "A TwichUI icon", "One of TwichUI's own icons." },
        { "item", "An item's icon", "The icon of an item you choose by its ID or link. It doesn't need to be equipped or carried." },
    },
    textPlace = { { "below", "Below" }, { "above", "Above" }, { "right", "Right" }, { "left", "Left" } },
    outline = { { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" }, { "shadow", "Shadow" } },
    panel = {
        { "none", "None", "Nothing behind it: the reminder sits over the world." },
        { "shade", "Soft shade", "A faint dark wash behind it, for reading over bright scenery." },
        { "framed", "Framed panel", "A dark panel with a thin bronze edge." },
    },
    strata = {
        { "LOW", "Low", "Under most windows and the game's frames." },
        { "MEDIUM", "Medium", "Where most of the game's own frames are." },
        { "HIGH", "High", "Over most windows (not over dialogs)." },
    },
}
RM.CHOICES.art = {}
for _, id in ipairs(RM.ART_ORDER) do RM.CHOICES.art[#RM.CHOICES.art + 1] = { id, RM.ART[id].label } end
RM.CHOICES.icon = {}
for i, e in ipairs(RM.ICONS) do RM.CHOICES.icon[i] = { e[1], e[2] } end

local ENUM = {}
for key, list in pairs(RM.CHOICES) do
    local set = {}
    for _, c in ipairs(list) do set[c[1]] = true end
    ENUM[key] = set
end

-- Whether a display value is usable. art and icon are checked against what exists in their own place (an unknown one
-- is a problem the reminder reports, not a value quietly changed).
function RM.ValidDisplay(key, value)
    local default = RM.DISPLAY_DEFAULTS[key]
    if default == nil then return false end
    if key == "art" or key == "icon" then return type(value) == "string" and #value > 0 and #value <= 40 and not value:find("[%c|]") end
    if key == "text" then return RM.PlainText(value, RM.TEXT_MAX, true) == value end
    if key == "font" then return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]") end
    if type(default) == "boolean" then return type(value) == "boolean" end
    if type(default) == "number" then
        local lim = RM.LIMITS[key]
        return Whole(value) and value >= lim[1] and value <= lim[2]
    end
    if key == "textColor" then return Hex(value) end
    return type(value) == "string" and ENUM[key] ~= nil and ENUM[key][value] == true
end

---------------------------------------------------------------------------
-- Where a reminder sits: a point of the screen, and an offset from it. The presets set all three.
---------------------------------------------------------------------------
RM.POINTS = {
    { "CENTER", "Centre" }, { "TOP", "Top" }, { "BOTTOM", "Bottom" }, { "LEFT", "Left" }, { "RIGHT", "Right" },
    { "TOPLEFT", "Top left" }, { "TOPRIGHT", "Top right" }, { "BOTTOMLEFT", "Bottom left" }, { "BOTTOMRIGHT", "Bottom right" },
}
local POINT = {}
for _, p in ipairs(RM.POINTS) do POINT[p[1]] = true end

RM.PRESETS = {
    { "belowCenter", "Below the middle", "CENTER", 0, -200, "Under your character and above the action bars, where a glance down finds it." },
    { "aboveCenter", "Above the middle", "CENTER", 0, 200, "Over your character's head, clear of the zone text at the top." },
    { "center", "Middle of the screen", "CENTER", 0, 0, "Right in the middle. Hard to miss, and it covers your character." },
    { "top", "Top of the screen", "TOP", 0, -160, "Near the top edge, under the minimap's height." },
    { "bottom", "Bottom of the screen", "BOTTOM", 0, 240, "Low on the screen, over the action bars' usual height." },
    { "custom", "Where I put it", nil, nil, nil, "The place you moved it to, or typed in." },
}
local PRESET = {}
for _, p in ipairs(RM.PRESETS) do PRESET[p[1]] = p end
RM.PLACE_DEFAULTS = { preset = "belowCenter", point = "CENTER", x = 0, y = -200 }

local function UsableOffset(v) return Finite(v) and math.abs(v) <= RM.POSITION_LIMIT end

---------------------------------------------------------------------------
-- Who a reminder is for
---------------------------------------------------------------------------
RM.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS = {}
for _, c in ipairs(RM.CLASSES) do CLASS[c] = true end
function RM.ValidClass(token) return type(token) == "string" and CLASS[token] == true end

-- A class token in words: the game's own name for it where it has one.
function RM.ClassName(token)
    local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
    local name = type(names) == "table" and names[token]
    if type(name) == "string" and name ~= "" then return name end
    return tostring(token):sub(1, 1) .. tostring(token):sub(2):lower()
end

-- "Name - Realm", as profiles name a character (Profiles.lua), or nil while the game hasn't said who this is.
function RM.CharacterKey()
    local P = R.Profiles
    local me = P and P.Character and P.Character()
    if me then return me end
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    if type(name) ~= "string" or name == "" or name == rawget(_G, "UNKNOWNOBJECT") then return nil end
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. " - " .. realm
end

local function ValidCharacter(v) return type(v) == "string" and #v >= 3 and #v <= 80 and not v:find("[%c|]") end

---------------------------------------------------------------------------
-- Change notices: fn(id, what) after every change; id nil for "everything" (a profile change, a reset).
-- what: "list" (added or removed), "rule", "display", "place", "enabled", "name".
---------------------------------------------------------------------------
local subscribers = {}
local rev = 0

function RM.Subscribe(fn) subscribers[#subscribers + 1] = fn end
function RM.Rev() return rev end

local function Tell(id, what)
    rev = rev + 1
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, id, what)
        if not ok then R.Fault("reminders", err) end
    end
end

-- Everything may be different (a profile change): read again and tell everyone.
function RM.Invalidate() Tell(nil, "list") end

---------------------------------------------------------------------------
-- The stored table
---------------------------------------------------------------------------
local function Store(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    local t = db.ui.reminders
    if type(t) ~= "table" then
        if not create then return nil end
        t = { version = RM.VERSION, nextId = 1, list = {} }
        db.ui.reminders = t
    end
    return t
end

-- Whether this table can be changed by this version (one made by a newer TwichUI is only read).
local function Writable(t)
    if not t then return true end
    local v = t.version
    return v == nil or (Whole(v) and v <= RM.VERSION)
end

function RM.Writable() return Writable(Store(false)) end

local function DeepCopy(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return v end
    if depth > 8 then return nil end
    local out = {}
    for k, x in pairs(v) do
        local tk = type(k)
        if tk == "string" or tk == "number" then out[k] = DeepCopy(x, depth + 1) end
    end
    return out
end
RM.DeepCopy = DeepCopy

---------------------------------------------------------------------------
-- Views: each stored reminder read through the checks, with what is wrong with it. Made again only after a change.
---------------------------------------------------------------------------
local cache = { src = nil, rev = -1, list = {}, byId = {} }

local PROBLEM = {
    newer = "These reminders were made by a newer version of TwichUI. They are kept as they are, and are not shown or changed here.",
    noConditions = "Add a condition first: a reminder with none would never know when to show.",
    tooMany = "Only the first " .. RM.MAX_CONDITIONS .. " conditions are used.",
    tooManyGroups = "Only the first " .. RM.MAX_GROUPS .. " groups are used.",
    noArt = "The artwork it uses isn't in this version of TwichUI. Choose another, or another kind of display.",
    noIcon = "The icon it uses isn't in this version of TwichUI. Choose another.",
    noItem = "Choose the item whose icon it shows, or another kind of display.",
    noText = "Type the words it shows, or choose a display without text.",
    noCharacters = "Choose at least one character, or let it apply to every character.",
}
RM.PROBLEM = PROBLEM

local function ReadDisplay(raw)
    local d = {}
    raw = type(raw) == "table" and raw or {}
    for key, default in pairs(RM.DISPLAY_DEFAULTS) do
        local v = raw[key]
        if v ~= nil and RM.ValidDisplay(key, v) then d[key] = v else d[key] = default end
    end
    d.item = RM.ValidItem(raw.item) and raw.item or nil
    return d
end

local function ReadPlace(raw)
    raw = type(raw) == "table" and raw or {}
    local p = { preset = PRESET[raw.preset] and raw.preset or RM.PLACE_DEFAULTS.preset }
    local preset = PRESET[p.preset]
    if preset[3] then
        p.point, p.x, p.y = preset[3], preset[4], preset[5]
    else
        p.point = POINT[raw.point] and raw.point or "CENTER"
        p.x = UsableOffset(raw.x) and raw.x or 0
        p.y = UsableOffset(raw.y) and raw.y or 0
    end
    return p
end

local function ReadScope(raw)
    raw = type(raw) == "table" and raw or {}
    local s = { who = raw.who == "characters" and "characters" or "all", characters = {}, class = CLASS[raw.class] and raw.class or nil }
    if type(raw.characters) == "table" then
        local seen = {}
        for _, c in ipairs(raw.characters) do
            if ValidCharacter(c) and not seen[c] and #s.characters < RM.MAX_CHARACTERS then
                seen[c] = true
                s.characters[#s.characters + 1] = c
            end
        end
    end
    return s
end

local function DisplayProblems(d, problems)
    local m = d.mode
    if (m == "artwork" or m == "artworkText") and not RM.Art(d.art) then problems[#problems + 1] = PROBLEM.noArt end
    if m == "icon" or m == "iconText" then
        if d.iconSource == "item" then
            if not d.item then problems[#problems + 1] = PROBLEM.noItem end
        elseif not RM.ValidIcon(d.icon) then
            problems[#problems + 1] = PROBLEM.noIcon
        end
    end
    if (m == "text" or m == "artworkText" or m == "iconText") and d.text == "" then problems[#problems + 1] = PROBLEM.noText end
end

-- One list of stored conditions (the top level's, or a group's) read into entries. depth is the level of this list (the
-- top level is 1); path the indexes that lead to it. A leaf is { raw, cond, provider, why, path, depth }; a group is
-- { raw, group = true, match, children, why, path, depth }. Reading is bounded by the limits and never follows a table
-- already being read (a loop in memory is a problem, not a hang). Problems are added to v.problems.
local function ReadList(v, list, depth, path, seen, counts)
    local C = R.ReminderConditions
    local out = {}
    for i, c in ipairs(list) do
        local at = { unpack(path) }
        at[#at + 1] = i
        local label = table.concat(at, ".")
        local entry
        if type(c) == "table" and c.type == "group" then
            if counts.groups >= RM.MAX_GROUPS then
                v.problems[#v.problems + 1] = PROBLEM.tooManyGroups
                counts.stop = true
                break
            end
            counts.groups = counts.groups + 1
            entry = { raw = c, group = true, path = at, depth = depth, children = {} }
            entry.match = (c.match == "all" or c.match == "any") and c.match or "all"
            local why
            if seen[c] then
                why = "it contains itself, so it can't be read."
            elseif depth + 1 > RM.MAX_DEPTH then
                why = ("groups can go only %d levels deep, counting the top level. Remove it."):format(RM.MAX_DEPTH)
            elseif c.match ~= "all" and c.match ~= "any" then
                why = "whether all or any of its conditions must match can't be read. Choose one."
            end
            v.flat[#v.flat + 1] = entry
            v.groups[#v.groups + 1] = entry
            if seen[c] == nil and depth + 1 <= RM.MAX_DEPTH then
                seen[c] = true
                entry.children = ReadList(v, type(c.conditions) == "table" and c.conditions or {}, depth + 1, at, seen, counts)
                seen[c] = nil
                if #entry.children == 0 and not counts.stop and not why then
                    why = "it has no conditions in it. Add one, or remove the group."
                end
            end
            entry.why = why
            if why then v.problems[#v.problems + 1] = ("Group %s: %s"):format(label, why) end
        else
            if counts.conditions >= RM.MAX_CONDITIONS then
                v.problems[#v.problems + 1] = PROBLEM.tooMany
                counts.stop = true
                break
            end
            counts.conditions = counts.conditions + 1
            entry = { raw = c, path = at, depth = depth }
            local clean, why, provider
            if C then clean, why, provider = C.Check(c) end
            entry.cond, entry.provider = clean, provider
            if why then
                entry.why = why
                v.problems[#v.problems + 1] = ("Condition %s: %s"):format(label, why)
            end
            v.flat[#v.flat + 1] = entry
            v.leaves[#v.leaves + 1] = entry
        end
        out[#out + 1] = entry
        if counts.stop then break end
    end
    return out
end

local function MakeView(raw, index, t, newer)
    local v = { raw = raw, index = index, problems = {} }
    v.id = (type(raw.id) == "string" and raw.id:match("^r%d+$")) and raw.id or nil
    local name = RM.PlainText(raw.name, RM.NAME_MAX)
    v.name = name or "Unnamed reminder"
    v.enabled = raw.enabled == true
    v.match = raw.match == "any" and "any" or "all"
    v.scope = ReadScope(raw.scope)
    v.display = ReadDisplay(raw.display)
    v.place = ReadPlace(raw.place)
    if newer then v.problems[#v.problems + 1] = PROBLEM.newer end

    -- the tree: v.conditions are the top level's entries (leaf or group); v.flat every entry in reading order (a group
    -- before what is in it), v.leaves the conditions alone and v.groups the groups alone, each in that order
    v.flat, v.leaves, v.groups, v.counts = {}, {}, {}, { conditions = 0, groups = 0 }
    v.conditions = ReadList(v, type(raw.conditions) == "table" and raw.conditions or {}, 1, {}, {}, v.counts)
    if #v.conditions == 0 then v.problems[#v.problems + 1] = PROBLEM.noConditions end
    DisplayProblems(v.display, v.problems)
    if v.scope.who == "characters" and #v.scope.characters == 0 then v.problems[#v.problems + 1] = PROBLEM.noCharacters end
    v.valid = #v.problems == 0
    v.rev = rev
    return v
end

local function Views()
    local t = Store(false)
    if cache.src == t and cache.rev == rev then return cache.list, cache.byId end
    local list, byId = {}, {}
    local newer = not Writable(t)
    if t and type(t.list) == "table" then
        for i, raw in ipairs(t.list) do
            if type(raw) == "table" then
                local v = MakeView(raw, i, t, newer)
                if not v.id or byId[v.id] then
                    -- no usable id (or a repeat): shown and flagged with one of its own for this session, so it can be removed
                    v.id = "x" .. i
                    v.problems[#v.problems + 1] = "It was saved without a usable id, so it can only be removed."
                    v.valid, v.broken = false, true
                end
                byId[v.id] = v
                list[#list + 1] = v
            end
        end
    end
    cache.src, cache.rev, cache.list, cache.byId = t, rev, list, byId
    return list, byId
end

-- Every reminder, in order, as views (read only: change them through the functions below).
function RM.List() return (Views()) end

function RM.Get(id)
    local _, byId = Views()
    return id and byId[id] or nil
end

function RM.Count() return #Views() end

---------------------------------------------------------------------------
-- Changing reminders. Each returns true (and what it made), or false and a sentence saying why not.
---------------------------------------------------------------------------
local REFUSE = {
    newer = PROBLEM.newer,
    missing = "That reminder doesn't exist any more.",
    full = ("A profile can hold %d reminders. Delete one first."):format(RM.MAX),
    conditionsFull = ("A reminder can have %d conditions, counting those in its groups."):format(RM.MAX_CONDITIONS),
    groupsFull = ("A reminder can have %d groups."):format(RM.MAX_GROUPS),
    tooDeep = ("Groups can go %d levels deep, counting the top level. Put this condition in a group above, or in this one."):format(RM.MAX_DEPTH),
    charactersFull = ("A reminder can be limited to %d characters."):format(RM.MAX_CHARACTERS),
    name = ("A name can be 1 to %d characters, without | or control characters."):format(RM.NAME_MAX),
    text = ("The words can be up to %d characters, without | or control characters."):format(RM.TEXT_MAX),
    value = "That value can't be used here.",
    broken = "This reminder can only be removed.",
}
RM.REFUSE = REFUSE

-- Finds the stored table of a reminder by its view: the same table, wherever it now is in the list.
local function Locate(id)
    local t = Store(false)
    if not Writable(t) then return nil, REFUSE.newer end
    local v = RM.Get(id)
    if not (t and v and type(t.list) == "table") then return nil, REFUSE.missing end
    for i, raw in ipairs(t.list) do
        if raw == v.raw then return raw, nil, i, t, v end
    end
    return nil, REFUSE.missing
end

local function Sub(raw, key)
    if type(raw[key]) ~= "table" then raw[key] = {} end
    return raw[key]
end

local function NextId(t)
    local n = Whole(t.nextId) and t.nextId >= 1 and t.nextId or 1
    local taken = {}
    for _, raw in ipairs(t.list) do
        if type(raw) == "table" and type(raw.id) == "string" then taken[raw.id] = true end
    end
    while taken["r" .. n] do n = n + 1 end
    t.nextId = n + 1
    return "r" .. n
end

-- Templates: editable starting points. Nothing about them is remembered once a reminder is made from one.
RM.TEMPLATES = {
    { "shield", "Missing shield", "Shows the shield artwork and \"Equip your shield\" whenever your off hand doesn't hold a shield. For this character only, until you change that." },
    { "ammo", "Ammunition", "Shows the arrows artwork and \"Check your ammunition\" while your ranged weapon takes ammunition and none is selected, none is left or the wrong kind is selected. Does nothing for a weapon that takes none. For this character only, until you change that." },
    { "item", "Missing equipment or item", "Shows an item's icon while that item isn't equipped. Choose the item first." },
    { "custom", "Custom reminder", "Your own words, shown when the conditions you add are true." },
}
RM.SHIELD_NOTE = "This reminder appears whenever you are not using a shield. Add a condition to limit when it appears."

local function Template(kind)
    local me = RM.CharacterKey()
    local mine = me and { who = "characters", characters = { me } } or { who = "all", characters = {} }
    if kind == "shield" then
        return {
            name = "Shield reminder", match = "all", scope = mine,
            conditions = { { type = "equipment", slot = "offHand", what = "shield", negate = true } },
            display = { mode = "artworkText", art = "shield", text = "Equip your shield" },
            place = { preset = "belowCenter" },
        }
    elseif kind == "ammo" then
        return {
            name = "Ammunition reminder", match = "all", scope = mine,
            conditions = { { type = "ammunition", what = "problem" } },
            display = { mode = "artworkText", art = "ammo", text = "Check your ammunition" },
            place = { preset = "belowCenter" },
        }
    elseif kind == "item" then
        return {
            name = "Missing item", match = "all", scope = mine,
            conditions = { { type = "equipment", slot = "any", what = "item", negate = true } },
            display = { mode = "iconText", iconSource = "item", text = "Equip it" },
            place = { preset = "belowCenter" },
        }
    elseif kind == "custom" then
        return {
            name = "New reminder", match = "all", scope = { who = "all", characters = {} },
            conditions = {},
            display = { mode = "text", text = "Reminder" },
            place = { preset = "belowCenter" },
        }
    end
end

-- A new reminder from a template. It starts turned off (a draft), whatever it is, so nothing appears in the world
-- until the player turns it on. Returns true, id.
function RM.Create(kind)
    local raw = Template(kind)
    if not raw then return false, REFUSE.value end
    local t = Store(true)
    if not t or not Writable(t) then return false, REFUSE.newer end
    if type(t.list) ~= "table" then t.list = {} end
    if #t.list >= RM.MAX then return false, REFUSE.full end
    t.version = t.version or RM.VERSION
    raw.id = NextId(t)
    raw.enabled = false
    t.list[#t.list + 1] = raw
    Tell(raw.id, "list")
    return true, raw.id
end

-- A copy with a fresh id, turned off, right after the one it was made from. The original is not touched.
function RM.Duplicate(id)
    local raw, why, i, t, v = Locate(id)
    if not raw then return false, why end
    if v.broken then return false, REFUSE.broken end
    if #t.list >= RM.MAX then return false, REFUSE.full end
    local copy = DeepCopy(raw)
    copy.id = NextId(t)
    copy.enabled = false
    local base = v.name
    local name = base .. " (copy)"
    while not RM.PlainText(name, RM.NAME_MAX) and #base > 1 do
        base = base:sub(1, -2):gsub("[\192-\255][\128-\191]*$", "")
        name = base .. " (copy)"
    end
    copy.name = name
    table.insert(t.list, i + 1, copy)
    Tell(copy.id, "list")
    return true, copy.id
end

-- Removes a reminder. Its frame is put away by the controller (it hears "list").
function RM.Delete(id)
    local raw, why, i, t = Locate(id)
    if not raw then return false, why end
    table.remove(t.list, i)
    Tell(id, "list")
    return true
end

-- Turning on is refused while anything is wrong with it (the views' problems say what). Turning off always works.
function RM.SetEnabled(id, on)
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    on = on and true or false
    if on and not v.valid then return false, v.problems[1] end
    if (raw.enabled == true) == on then return true end
    raw.enabled = on
    Tell(id, "enabled")
    return true
end

function RM.SetName(id, text)
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    if v.broken then return false, REFUSE.broken end
    local name = RM.PlainText(text, RM.NAME_MAX)
    if not name then return false, REFUSE.name end
    if raw.name == name then return true end
    raw.name = name
    Tell(id, "name")
    return true
end

---------------------------------------------------------------------------
-- Conditions and groups. A node is addressed by its path: the indexes from the top level down ({ 2, 1 } is the first
-- item of the second item, which is a group). nil or {} is the top level itself where a group is wanted. A plain number
-- is a path of one. The fields of a condition are its provider's: Conditions.lua checks them.
---------------------------------------------------------------------------
local function ReadPath(path)
    if path == nil then return {} end
    if Whole(path) then path = { path } end
    if type(path) ~= "table" or #path > RM.MAX_DEPTH then return nil end
    local out = {}
    for i, n in ipairs(path) do
        if not (Whole(n) and n >= 1) then return nil end
        out[i] = n
    end
    return out
end

-- The stored list of the group at `groupPath` (the top level's for {}). nil when the path doesn't lead to a group.
local function ListAt(raw, groupPath)
    local list = Sub(raw, "conditions")
    for _, i in ipairs(groupPath) do
        local g = list[i]
        if type(g) ~= "table" or g.type ~= "group" then return nil end
        if type(g.conditions) ~= "table" then g.conditions = {} end
        list = g.conditions
    end
    return list
end

-- The entry of a view at a path (nil for the top level, or a path that leads nowhere).
function RM.Node(v, path)
    path = ReadPath(path)
    if not (v and path) or #path == 0 then return nil end
    local list, entry = v.conditions, nil
    for _, i in ipairs(path) do
        entry = list and list[i]
        if not entry then return nil end
        list = entry.children
    end
    return entry
end

-- Whether the top level (no path) or the group at the path matches on all or on any of what it holds.
function RM.SetMatch(id, match, groupPath)
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    if match ~= "all" and match ~= "any" then return false, REFUSE.value end
    local path = ReadPath(groupPath)
    if not path then return false, REFUSE.value end
    local target = raw
    if #path > 0 then
        local node = RM.Node(v, path)
        if not (node and node.group) then return false, REFUSE.value end
        target = node.raw
    end
    local current = target.match
    if #path == 0 then current = current == "any" and "any" or "all" end   -- the top level reads anything else as all
    if current == match then return true end
    target.match = match
    Tell(id, "rule")
    return true
end

-- Adds a new condition of a kind at the end of the group at groupPath (the top level when nil).
function RM.AddCondition(id, kind, groupPath)
    local C = R.ReminderConditions
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    local p = C and C.Get(kind)
    local path = ReadPath(groupPath)
    if not (p and path) then return false, REFUSE.value end
    if #path + 1 > RM.MAX_DEPTH then return false, REFUSE.tooDeep end
    if #path > 0 and not (RM.Node(v, path) or {}).group then return false, REFUSE.value end
    if v.counts.conditions >= RM.MAX_CONDITIONS then return false, REFUSE.conditionsFull end
    local list = ListAt(raw, path)
    if not list then return false, REFUSE.value end
    list[#list + 1] = p.New()
    Tell(id, "rule")
    return true, #list
end

-- Adds an empty group at the end of the group at groupPath (the top level when nil). It starts with the opposite
-- operator of the group it is in, so a group in an "all" list reads as "any"; an empty group is reported as a problem
-- until a condition is put in it. Returns true and the new group's path.
function RM.AddGroup(id, groupPath)
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    local path = ReadPath(groupPath)
    if not path then return false, REFUSE.value end
    if #path + 2 > RM.MAX_DEPTH then return false, REFUSE.tooDeep end
    local parentMatch = v.match
    if #path > 0 then
        local node = RM.Node(v, path)
        if not (node and node.group) then return false, REFUSE.value end
        parentMatch = node.match
    end
    if v.counts.groups >= RM.MAX_GROUPS then return false, REFUSE.groupsFull end
    local list = ListAt(raw, path)
    if not list then return false, REFUSE.value end
    list[#list + 1] = { type = "group", match = parentMatch == "any" and "all" or "any", conditions = {} }
    local at = { unpack(path) }
    at[#at + 1] = #list
    Tell(id, "rule")
    return true, at
end

-- Replaces the condition at a path with cond, checked by its provider. An unfinished one (no item yet) is kept; the
-- view says what it still needs. One that isn't a condition of a known kind, or a path that leads to a group, is refused.
function RM.SetCondition(id, path, cond)
    local C = R.ReminderConditions
    local raw, why = Locate(id)
    if not raw then return false, why end
    path = ReadPath(path)
    if not path or #path == 0 then return false, REFUSE.value end
    local last = table.remove(path)
    local list = ListAt(raw, path)
    local old = list and list[last]
    if not old or (type(old) == "table" and old.type == "group") then return false, REFUSE.value end
    local clean, problem = C.Check(cond)
    if not clean then return false, problem or REFUSE.value end
    list[last] = clean
    Tell(id, "rule")
    return true, problem
end

-- Removes the condition or the group (with everything in it) at a path.
function RM.RemoveCondition(id, path)
    local raw, why = Locate(id)
    if not raw then return false, why end
    path = ReadPath(path)
    if not path or #path == 0 then return false, REFUSE.value end
    local last = table.remove(path)
    local list = ListAt(raw, path)
    if not (list and list[last] ~= nil) then return false, REFUSE.value end
    table.remove(list, last)
    Tell(id, "rule")
    return true
end
RM.RemoveNode = RM.RemoveCondition

---------------------------------------------------------------------------
-- Display, place and scope
---------------------------------------------------------------------------
function RM.SetDisplay(id, key, value)
    local raw, why = Locate(id)
    if not raw then return false, why end
    if key == "item" then
        if value ~= nil and not RM.ValidItem(value) then return false, REFUSE.value end
    elseif key == "text" then
        local text = RM.PlainText(value, RM.TEXT_MAX, true)
        if not text then return false, REFUSE.text end
        value = text
    elseif not RM.ValidDisplay(key, value) then
        return false, REFUSE.value
    end
    local d = Sub(raw, "display")
    if d[key] == value then return true end
    d[key] = value
    Tell(id, "display")
    return true
end

-- A preset sets the point and offsets with it; "custom" keeps the place it is at now.
function RM.SetPreset(id, preset)
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    if not PRESET[preset] then return false, REFUSE.value end
    local p = Sub(raw, "place")
    if preset == "custom" then
        p.point, p.x, p.y = v.place.point, v.place.x, v.place.y
    else
        p.point, p.x, p.y = nil, nil, nil
    end
    p.preset = preset
    Tell(id, "place")
    return true
end

-- A place of its own (dragged, or typed in): the preset becomes "custom".
function RM.SetPosition(id, point, x, y)
    local raw, why = Locate(id)
    if not raw then return false, why end
    if not (POINT[point] and UsableOffset(x) and UsableOffset(y)) then return false, REFUSE.value end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local p = Sub(raw, "place")
    if p.preset == "custom" and p.point == point and p.x == x and p.y == y then return true end
    p.preset, p.point, p.x, p.y = "custom", point, x, y
    Tell(id, "place")
    return true
end

-- who: "all" or "characters"; class: nil (any class) or a class token.
function RM.SetScope(id, key, value)
    local raw, why = Locate(id)
    if not raw then return false, why end
    local s = Sub(raw, "scope")
    if key == "who" then
        if value ~= "all" and value ~= "characters" then return false, REFUSE.value end
        if s.who == value then return true end
        s.who = value
    elseif key == "class" then
        if value ~= nil and not CLASS[value] then return false, REFUSE.value end
        if s.class == value then return true end
        s.class = value
    else
        return false, REFUSE.value
    end
    Tell(id, "rule")
    return true
end

function RM.AddCharacter(id, who)
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    if not ValidCharacter(who) then return false, REFUSE.value end
    for _, c in ipairs(v.scope.characters) do if c == who then return true end end
    if #v.scope.characters >= RM.MAX_CHARACTERS then return false, REFUSE.charactersFull end
    local s = Sub(raw, "scope")
    local list = {}
    for i, c in ipairs(v.scope.characters) do list[i] = c end
    list[#list + 1] = who
    s.characters = list
    Tell(id, "rule")
    return true
end

function RM.RemoveCharacter(id, who)
    local raw, why, _, _, v = Locate(id)
    if not raw then return false, why end
    local list, found = {}, false
    for _, c in ipairs(v.scope.characters) do
        if c == who then found = true else list[#list + 1] = c end
    end
    if not found then return true end
    Sub(raw, "scope").characters = list
    Tell(id, "rule")
    return true
end

-- A profile change puts another profile's reminders in place: everything is read again.
R.Profiles.OnApply("layout", "reminders", function() RM.Invalidate() end)
