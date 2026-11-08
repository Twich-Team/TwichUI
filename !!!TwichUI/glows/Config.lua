-- TwichUI: Action bar glows, what is stored
-- The player's choices for the glows on their action bars, and how each stored value is read. Nothing here touches a
-- frame, an event or a unit: it keeps the saved data, checks it on the way in and on the way out, and says when
-- something changed. Catalog.lua is the built-in list, docs/bar-glows.md the design.
--
-- Stored (the profile in use, TwichUIDB.ui.barGlows; switch: TwichUIDB.modules.barGlows):
--   the settings in DEFAULTS (checked against LIMITS / CHOICES; an unusable stored value reads as its default and is left)
--   bars[bar] = false        a bar whose buttons never glow (bar1 ... bar10, stance)
--   faded[bar] = true        a bar whose buttons are faded until one glows
--   types[kind]              { enabled, and any style field }: the look of every entry of that kind
--   spells["kind:key"]       { enabled, below, and any style field }: one entry's own changes
--   added = { { kind, spell | item, slot } }   spells and items the player added (at most MAX_ADDED)
--   weapon = { mainHand, offHand }             which weapon buff to keep up ("auto" or an entry key)
-- Per character, never in a profile (TwichUIDB.ui.barGlowsMemory["Name - Realm"]): what was used last in each exclusive
-- group (an aspect, an armor, a seal, a tracking) and which blessing was given to each class. A record, not a choice.
-- Defaults are read, never written: a value is stored only when the player changes it.

local R = TwichUI
local C = R.BarGlowCatalog
local BG = {}
R.BarGlows = BG

BG.MAX_ADDED = 60

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function Hex(v) return type(v) == "string" and v:match("^%x%x%x%x%x%x%x%x$") ~= nil end
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end
BG.Whole = Whole

---------------------------------------------------------------------------
-- General settings
---------------------------------------------------------------------------
BG.DEFAULTS = {
    quietInTowns = true,          -- no glows, messages or sounds while resting out of combat (low reagents and stock may still alert)
    partyBuffs = true,            -- out of combat in a party: members in range missing your buffs
    raidBuffs = true,             -- ... in a raid
    partyGroupFrom = 2,           -- how many missing it before the group version glows instead (party)
    raidGroupFrom = 1,            -- ... (raid)
    cooldownsAtFightStart = false, -- every ready cooldown glows as a fight starts
    reagentBelow = 10,            -- a reagent is low below this (an entry may have its own)
    stockBelow = 20,              -- an added item is low below this
    fadedOpacity = 50,            -- how visible a faded bar's buttons are while they don't glow (percent)
    noticeIcon = true,            -- the message card shows the spell's or item's icon beside its title
    noticeFade = true,            -- a message card fades out after noticeSeconds (off: it stays until its reminder is done)
    noticeSeconds = 5,            -- how long a message card stays before it fades
}
BG.LIMITS = {
    partyGroupFrom = { 1, 5 }, raidGroupFrom = { 1, 5 }, reagentBelow = { 0, 200 }, stockBelow = { 0, 1000 },
    fadedOpacity = { 0, 90 }, noticeSeconds = { 2, 30 },
}

-- The bars: Blizzard's (and EllesmereUI's, which keep the same slots) 1 to 10, and the stance bar.
BG.BARS = { "bar1", "bar2", "bar3", "bar4", "bar5", "bar6", "bar7", "bar8", "bar9", "bar10", "stance" }
BG.BAR_SET = {}
for _, b in ipairs(BG.BARS) do BG.BAR_SET[b] = true end
function BG.BarLabel(bar)
    if bar == "stance" then return "Stance bar" end
    return "Action Bar " .. (bar:match("%d+") or "?")
end

---------------------------------------------------------------------------
-- The look of a glow (a kind's defaults, or one entry's own)
---------------------------------------------------------------------------
BG.LOOKS = {
    { "proc", "Spell alert", "The game's own spell alert: a bright loop around the button." },
    { "ants", "Marching ants", "A thin line that runs around the button." },
    { "soft", "Soft frame", "A soft, glowing square frame. Calm, and easy on the eyes." },
    { "pixel", "Pixel border", "A crisp line of your chosen thickness on the button's edge." },
}
BG.MOTIONS = {
    { "moving", "Moving", "The glow runs around the button (the soft frame and pixel border breathe instead)." },
    { "breathing", "Breathing", "It stands still and slowly fades out and in." },
    { "still", "Still", "It stands still and does not move at all." },
}
BG.WHENS = {
    { "always", "Always" }, { "inCombat", "In combat" }, { "outOfCombat", "Out of combat" },
    { "enemyTargeted", "Enemy targeted", "Only while a living enemy is your target." },
    { "townAlert", "Alert in town", "The button glows anywhere; the message and sound come only in a town or an inn." },
}
BG.GLOW_TIMES = { 0, 1, 2, 3, 5, 10, 15, 30 }
BG.REPEATS = { 0, 5, 10, 15, 30, 60 }

local function Set(list, at)
    local s = {}
    for _, v in ipairs(list) do s[at and v[at] or v] = true end
    return s
end
local LOOK_SET, MOTION_SET, WHEN_SET = Set(BG.LOOKS, 1), Set(BG.MOTIONS, 1), Set(BG.WHENS, 1)
local GLOW_TIME_SET, REPEAT_SET = Set(BG.GLOW_TIMES), Set(BG.REPEATS)

-- The fields of a look, each with its check.
BG.STYLE_FIELDS = {
    look = function(v) return LOOK_SET[v] == true end,
    color = Hex,
    opacity = function(v) return Whole(v) and v >= 10 and v <= 100 end,
    size = function(v) return Whole(v) and v >= 70 and v <= 170 end,
    speed = function(v) return Whole(v) and v >= 25 and v <= 300 end,
    motion = function(v) return MOTION_SET[v] == true end,
    thickness = function(v) return Whole(v) and v >= 1 and v <= 6 end,
    when = function(v) return WHEN_SET[v] == true end,
    glowTime = function(v) return GLOW_TIME_SET[v] == true end,
    ["repeat"] = function(v) return REPEAT_SET[v] == true end,
    message = function(v) return type(v) == "boolean" end,
    sound = function(v) return type(v) == "string" and #v >= 1 and #v <= 64 and not v:find("[%c|]") end,
}
BG.STYLE_ORDER = { "look", "color", "opacity", "size", "speed", "motion", "thickness", "when", "glowTime", "repeat", "message", "sound" }
BG.NO_SOUND = "none"

local function Base(color, extra)
    local s = { look = "proc", color = color, opacity = 100, size = 100, speed = 100, motion = "moving", thickness = 2,
        when = "always", glowTime = 0, ["repeat"] = 0, message = false, sound = BG.NO_SOUND }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end
-- Each kind's look as it ships. Colors chosen to tell the kinds apart at a glance.
BG.TYPE_DEFAULTS = {
    missingBuff = Base("ff4fa3e6"),
    weaponBuff = Base("ffe08a2c"),
    missingSeal = Base("ffe8c547", { when = "inCombat" }),
    missingTracking = Base("ff3fb8b0", { look = "soft", motion = "breathing" }),
    lowReagent = Base("ffd9a53f", { look = "soft", motion = "breathing", opacity = 60, when = "townAlert", message = true }),
    lowStock = Base("ffd05040", { look = "soft", motion = "breathing", opacity = 60, message = true }),
    readyCooldown = Base("fff2ead8", { look = "ants", when = "inCombat", glowTime = 3 }),
    proc = Base("ffff5a2a"),
    oldRank = Base("ffc9a24a", { look = "pixel", motion = "still", opacity = 70, message = true }),
}

-- Whether a "when" fits a kind: Alert in town only for what you buy in a town.
function BG.WhenFits(kind, when)
    if when == "townAlert" then return kind == "lowReagent" or kind == "lowStock" end
    return WHEN_SET[when] == true
end

function BG.ValidStyleField(kind, field, v)
    local check = BG.STYLE_FIELDS[field]
    if not (check and check(v)) then return false end
    if field == "when" and not BG.WhenFits(kind, v) then return false end
    return true
end

---------------------------------------------------------------------------
-- Change notices
---------------------------------------------------------------------------
local subscribers = {}
local resolved = {}        -- [kind:key] = the resolved look (rebuilt after any change)
local generation = 0

function BG.Subscribe(fn) subscribers[#subscribers + 1] = fn end

-- what: "settings", "style", "spells", "bars", "added", "memory" or "profile".
function BG.Invalidate(what)
    generation = generation + 1
    for k in pairs(resolved) do resolved[k] = nil end
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("bar glows", err) end
    end
end
function BG.Generation() return generation end

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
    if type(db.ui.barGlows) ~= "table" then
        if not create then return nil end
        db.ui.barGlows = {}
    end
    return db.ui.barGlows
end
-- A table inside the saved settings (bars, faded, types, spells, added, weapon).
local function Sub(name, create)
    local t = Saved(create)
    if not t then return nil end
    if type(t[name]) ~= "table" then
        if not create then return nil end
        t[name] = {}
    end
    return t[name]
end

function BG.Valid(key, value)
    local default = BG.DEFAULTS[key]
    if default == nil then return false end
    if type(default) == "boolean" then return type(value) == "boolean" end
    local lim = BG.LIMITS[key]
    return Whole(value) and lim ~= nil and value >= lim[1] and value <= lim[2]
end

function BG.Get(key)
    local t = Saved(false)
    local value
    if t then value = t[key] end
    if BG.Valid(key, value) then return value end
    return BG.DEFAULTS[key]
end

function BG.Set(key, value)
    if BG.DEFAULTS[key] == nil or not BG.Valid(key, value) then return false end
    local t = Saved(true)
    if not t then return false end
    if t[key] == value then return true end
    t[key] = value
    BG.Invalidate("settings")
    return true
end

-- Bars
function BG.BarOn(bar)
    local t = Sub("bars", false)
    return not (t and t[bar] == false)
end
function BG.SetBar(bar, on)
    if not BG.BAR_SET[bar] or type(on) ~= "boolean" then return false end
    local t = Sub("bars", true)
    if not t then return false end
    local stored = nil
    if not on then stored = false end   -- only "off" is stored ("x and false or nil" would always be nil)
    if t[bar] == stored then return true end
    t[bar] = stored
    BG.Invalidate("bars")
    return true
end
function BG.BarFaded(bar)
    local t = Sub("faded", false)
    return t ~= nil and t[bar] == true
end
function BG.SetFaded(bar, on)
    if not BG.BAR_SET[bar] or type(on) ~= "boolean" then return false end
    local t = Sub("faded", true)
    if not t then return false end
    local stored = on and true or nil
    if t[bar] == stored then return true end
    t[bar] = stored
    BG.Invalidate("bars")
    return true
end
function BG.AnyFaded()
    local t = Sub("faded", false)
    if not t then return false end
    for _, b in ipairs(BG.BARS) do if t[b] == true then return true end end
    return false
end

---------------------------------------------------------------------------
-- Kinds and entries: on/off and their looks
---------------------------------------------------------------------------
local function TypeTable(kind, create)
    if not C.TYPES[kind] then return nil end
    local t = Sub("types", create)
    if not t then return nil end
    if type(t[kind]) ~= "table" then
        if not create then return nil end
        t[kind] = {}
    end
    return t[kind]
end
local function SpellTable(kind, key, create)
    if not C.TYPES[kind] or type(key) ~= "string" or #key < 1 or #key > 64 then return nil end
    local t = Sub("spells", create)
    if not t then return nil end
    local id = kind .. ":" .. key
    if type(t[id]) ~= "table" then
        if not create then return nil end
        t[id] = {}
    end
    return t[id]
end
-- An empty table left behind by a reset is removed, so nothing is stored that says nothing.
local function Prune(kind, key)
    local spells = Sub("spells", false)
    if key and spells then
        local id = kind .. ":" .. key
        if type(spells[id]) == "table" and next(spells[id]) == nil then spells[id] = nil end
    end
    local types = Sub("types", false)
    if not key and types and type(types[kind]) == "table" and next(types[kind]) == nil then types[kind] = nil end
end

function BG.TypeEnabled(kind)
    local t = TypeTable(kind, false)
    return not (t and t.enabled == false)
end
function BG.SetTypeEnabled(kind, on)
    if type(on) ~= "boolean" then return false end
    local t = TypeTable(kind, true)
    if not t then return false end
    local stored = nil
    if not on then stored = false end   -- only "off" is stored ("x and false or nil" would always be nil)
    if t.enabled == stored then return true end
    t.enabled = stored
    Prune(kind)
    BG.Invalidate("spells")
    return true
end

-- An entry: a built-in one (Catalog) or one the player added. Its default on/off is the built-in one's.
function BG.EntryDefaultOn(kind, key)
    local e = C.Find(kind, key)
    return not (e and e.default == false)
end
function BG.SpellEnabled(kind, key)
    local t = SpellTable(kind, key, false)
    if t and type(t.enabled) == "boolean" then return t.enabled end
    return BG.EntryDefaultOn(kind, key)
end
function BG.SetSpellEnabled(kind, key, on)
    if type(on) ~= "boolean" then return false end
    local t = SpellTable(kind, key, true)
    if not t then return false end
    local stored = on
    if on == BG.EntryDefaultOn(kind, key) then stored = nil end
    if t.enabled == stored then return true end
    t.enabled = stored
    Prune(kind, key)
    BG.Invalidate("spells")
    return true
end
-- Both the kind and the entry are on.
function BG.On(kind, key) return BG.TypeEnabled(kind) and BG.SpellEnabled(kind, key) end

-- A kind's look: its shipped defaults with the player's changes (each field checked).
function BG.TypeField(kind, field)
    local t = TypeTable(kind, false)
    local v = t and t[field]
    if v ~= nil and BG.ValidStyleField(kind, field, v) then return v end
    local d = BG.TYPE_DEFAULTS[kind]
    return d and d[field]
end
-- Whether the player changed this field of the kind's look.
function BG.TypeChanged(kind, field)
    local t = TypeTable(kind, false)
    return t ~= nil and t[field] ~= nil and BG.ValidStyleField(kind, field, t[field])
end
function BG.SetTypeField(kind, field, v)
    if not BG.STYLE_FIELDS[field] then return false end
    if v ~= nil and not BG.ValidStyleField(kind, field, v) then return false end
    local t = TypeTable(kind, true)
    if not t then return false end
    local d = BG.TYPE_DEFAULTS[kind]
    if v ~= nil and d and d[field] == v then v = nil end   -- the default itself is not stored
    if t[field] == v then return true end
    t[field] = v
    Prune(kind)
    BG.Invalidate("style")
    return true
end
-- The kind's look back to as it ships (its on/off is kept).
function BG.ResetType(kind)
    local t = TypeTable(kind, false)
    if not t then return end
    local enabled = t.enabled
    for k in pairs(t) do t[k] = nil end
    t.enabled = enabled
    Prune(kind)
    BG.Invalidate("style")
end

-- One entry's own value for a field (nil: it follows its kind).
function BG.SpellField(kind, key, field)
    local t = SpellTable(kind, key, false)
    local v = t and t[field]
    if v ~= nil and BG.ValidStyleField(kind, field, v) then return v end
    return nil
end
function BG.SetSpellField(kind, key, field, v)
    if not BG.STYLE_FIELDS[field] then return false end
    if v ~= nil and not BG.ValidStyleField(kind, field, v) then return false end
    local t = SpellTable(kind, key, v ~= nil)
    if not t then return v == nil end
    if t[field] == v then return true end
    t[field] = v
    Prune(kind, key)
    BG.Invalidate("style")
    return true
end
-- Whether the entry has a look of its own (any field).
function BG.SpellHasOwnLook(kind, key)
    local t = SpellTable(kind, key, false)
    if not t then return false end
    for _, f in ipairs(BG.STYLE_ORDER) do if t[f] ~= nil then return true end end
    return t.below ~= nil
end
-- The keys of one kind with anything stored for them (for entries found in play, such as old ranks, so one turned
-- off stays listed). A new, sorted list.
function BG.StoredKeys(kind)
    local out = {}
    local spells = Sub("spells", false)
    if not spells then return out end
    local prefix = kind .. ":"
    for id, t in pairs(spells) do
        if type(id) == "string" and type(t) == "table" and id:sub(1, #prefix) == prefix then out[#out + 1] = id:sub(#prefix + 1) end
    end
    table.sort(out)
    return out
end

-- The entry's own look and limit forgotten (its on/off is kept).
function BG.ResetSpell(kind, key)
    local t = SpellTable(kind, key, false)
    if not t then return end
    local enabled = t.enabled
    for k in pairs(t) do t[k] = nil end
    t.enabled = enabled
    Prune(kind, key)
    BG.Invalidate("style")
end

-- The look an entry is drawn with: its kind's look, the built-in entry's own "when", then the entry's own changes.
-- Cached until anything changes (the result must not be changed by the caller).
function BG.Style(kind, key)
    local id = kind .. ":" .. tostring(key)
    local cached = resolved[id]
    if cached then return cached end
    local s = {}
    for _, f in ipairs(BG.STYLE_ORDER) do s[f] = BG.TypeField(kind, f) end
    local e = key and C.Find(kind, key)
    if e and e.when and not BG.TypeChanged(kind, "when") and BG.WhenFits(kind, e.when) then s.when = e.when end
    if key then
        for _, f in ipairs(BG.STYLE_ORDER) do
            local own = BG.SpellField(kind, key, f)
            if own ~= nil then s[f] = own end
        end
    end
    resolved[id] = s
    return s
end

-- How few is low for a reagent or a stock item: the entry's own, the built-in entry's, else the setting.
function BG.Below(kind, key)
    local t = SpellTable(kind, key, false)
    if t and Whole(t.below) and t.below >= 0 and t.below <= 1000 then return t.below end
    local e = C.Find(kind, key)
    if e and Whole(e.below) then return e.below end
    return kind == "lowStock" and BG.Get("stockBelow") or BG.Get("reagentBelow")
end
function BG.SetBelow(kind, key, n)
    if n ~= nil and not (Whole(n) and n >= 0 and n <= 1000) then return false end
    if kind ~= "lowReagent" and kind ~= "lowStock" then return false end
    local t = SpellTable(kind, key, n ~= nil)
    if not t then return n == nil end
    if t.below == n then return true end
    t.below = n
    Prune(kind, key)
    BG.Invalidate("style")
    return true
end
function BG.BelowOwn(kind, key)
    local t = SpellTable(kind, key, false)
    return t ~= nil and Whole(t.below)
end

---------------------------------------------------------------------------
-- What the player added: spells (by ID) as a missing buff, ready cooldown, proc, weapon buff, seal or tracking;
-- items (by ID) as low stock, a weapon buff (a stone or oil) or a missing buff (an elixir or food: its buff is
-- the item's own spell, or one you name). Stored as { kind, spell | item, aura, slot }; the key is "s<id>" or "i<id>".
---------------------------------------------------------------------------
BG.ADDABLE = {
    missingBuff = { spell = true, item = true }, weaponBuff = { spell = true, item = true },
    missingSeal = { spell = true }, missingTracking = { spell = true },
    readyCooldown = { spell = true }, proc = { spell = true }, lowStock = { item = true },
}
BG.ADDABLE_ORDER = { "readyCooldown", "proc", "missingBuff", "weaponBuff", "lowStock", "missingSeal", "missingTracking" }
local SLOT_SET = { mainHand = true, offHand = true, both = true }

local function ValidAdded(a)
    if type(a) ~= "table" or not BG.ADDABLE[a.kind] then return false end
    local can = BG.ADDABLE[a.kind]
    local spell, item = a.spell, a.item
    if spell ~= nil and not (can.spell and Whole(spell) and spell >= 1 and spell <= 9999999) then return false end
    if item ~= nil and not (can.item and Whole(item) and item >= 1 and item <= 9999999) then return false end
    if (spell == nil) == (item == nil) then return false end
    if a.aura ~= nil and not (Whole(a.aura) and a.aura >= 1 and a.aura <= 9999999) then return false end
    if a.slot ~= nil and not (a.kind == "weaponBuff" and SLOT_SET[a.slot]) then return false end
    return true
end
BG.ValidAdded = ValidAdded

function BG.AddedKey(a) return (a.spell and ("s" .. a.spell)) or ("i" .. tostring(a.item)) end

-- The usable entries the player added, in the order added (a new list; unusable ones are skipped, not removed).
function BG.Added()
    local out = {}
    local list = Sub("added", false)
    if not list then return out end
    for _, a in ipairs(list) do
        if ValidAdded(a) then out[#out + 1] = a end
    end
    return out
end

function BG.FindAdded(kind, key)
    for _, a in ipairs(BG.Added()) do
        if a.kind == kind and BG.AddedKey(a) == key then return a end
    end
    return nil
end

-- Adds one. Returns true and its key, or false and why ("invalid", "duplicate", "full", "builtin").
function BG.Add(a)
    local entry = { kind = a and a.kind, spell = a and a.spell, item = a and a.item, aura = a and a.aura, slot = a and a.slot }
    if entry.kind == "weaponBuff" and entry.slot == nil then entry.slot = "both" end
    if not ValidAdded(entry) then return false, "invalid" end
    local key = BG.AddedKey(entry)
    if BG.FindAdded(entry.kind, key) then return false, "duplicate" end
    for _, e in ipairs(C.For(entry.kind)) do
        if entry.spell and e.spell == entry.spell then return false, "builtin", e end
        if entry.item and e.items then
            for _, id in ipairs(e.items) do if id == entry.item then return false, "builtin", e end end
        end
    end
    local list = Sub("added", true)
    if not list then return false, "invalid" end
    local n = 0
    for _, x in ipairs(list) do if ValidAdded(x) then n = n + 1 end end
    if n >= BG.MAX_ADDED then return false, "full" end
    list[#list + 1] = entry
    BG.Invalidate("added")
    return true, key
end

-- Removes one the player added, with its own look and on/off. Built-in entries can only be turned off.
function BG.Remove(kind, key)
    local list = Sub("added", false)
    if not list then return false end
    for i = #list, 1, -1 do
        local a = list[i]
        if ValidAdded(a) and a.kind == kind and BG.AddedKey(a) == key then
            table.remove(list, i)
            local spells = Sub("spells", false)
            if spells then spells[kind .. ":" .. key] = nil end
            BG.Invalidate("added")
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Which weapon buff to keep up, per hand: "auto" (the one you used last, else the first you have) or an entry key.
---------------------------------------------------------------------------
BG.HANDS = { "mainHand", "offHand" }
function BG.Weapon(hand)
    local t = Sub("weapon", false)
    local v = t and t[hand]
    if type(v) == "string" and #v >= 1 and #v <= 64 then return v end
    return "auto"
end
function BG.SetWeapon(hand, v)
    if hand ~= "mainHand" and hand ~= "offHand" then return false end
    if type(v) ~= "string" or #v < 1 or #v > 64 then return false end
    local t = Sub("weapon", true)
    if not t then return false end
    local stored = v ~= "auto" and v or nil
    if t[hand] == stored then return true end
    t[hand] = stored
    BG.Invalidate("settings")
    return true
end

---------------------------------------------------------------------------
-- Every setting back to how it ships: the general settings, bars, faded bars, every look and on/off, the weapon
-- choice. What you added is kept (remove it from its row), and so is the per-character memory.
---------------------------------------------------------------------------
function BG.ResetAll()
    local t = Saved(false)
    if not t then return end
    for key in pairs(BG.DEFAULTS) do t[key] = nil end
    t.bars, t.faded, t.types, t.spells, t.weapon = nil, nil, nil, nil, nil
    BG.Invalidate("settings")
end

---------------------------------------------------------------------------
-- Per-character memory: a record of what you did, never a choice, and never in a profile.
---------------------------------------------------------------------------
local MAX_MEMORY_CHARS = 60
local function MyKey()
    local name = Plain(UnitName and UnitName("player"))
    local realm = Plain(GetRealmName and GetRealmName())
    if type(name) ~= "string" or name == "" then return nil end
    return name .. " - " .. (type(realm) == "string" and realm or "?")
end
local function Memory(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    local all = db.ui.barGlowsMemory
    if type(all) ~= "table" then
        if not create then return nil end
        all = {}
        db.ui.barGlowsMemory = all
    end
    local me = MyKey()
    if not me then return nil end
    if type(all[me]) ~= "table" then
        if not create then return nil end
        local n = 0
        for _ in pairs(all) do n = n + 1 end
        if n >= MAX_MEMORY_CHARS then return nil end   -- bounded: a record is simply not kept past this
        all[me] = {}
    end
    return all[me]
end
local function ValidKey(v) return type(v) == "string" and #v >= 1 and #v <= 64 and v:match("^[%w]+$") ~= nil end

-- The entry used last in an exclusive group (nil: none yet).
function BG.Remembered(category)
    local m = Memory(false)
    local v = m and type(m.last) == "table" and m.last[category]
    return ValidKey(v) and v or nil
end
function BG.Remember(category, key)
    if not (ValidKey(category) and ValidKey(key)) then return false end
    local m = Memory(true)
    if not m then return false end
    if type(m.last) ~= "table" then m.last = {} end
    if m.last[category] == key then return true end
    m.last[category] = key
    BG.Invalidate("memory")
    return true
end
-- The blessing you last gave a class (an entry key), for the group check.
function BG.Blessing(class)
    local m = Memory(false)
    local v = m and type(m.blessings) == "table" and m.blessings[class]
    return ValidKey(v) and v or nil
end
function BG.SetBlessing(class, key)
    if not (type(class) == "string" and class:match("^%u+$") and #class <= 24) then return false end
    if key ~= nil and not ValidKey(key) then return false end
    local m = Memory(key ~= nil)
    if not m then return key == nil end
    if type(m.blessings) ~= "table" then m.blessings = {} end
    if m.blessings[class] == key then return true end
    m.blessings[class] = key
    BG.Invalidate("memory")
    return true
end

---------------------------------------------------------------------------
-- A profile change puts another profile's choices in place: everything is read again.
---------------------------------------------------------------------------
R.Profiles.OnApply("layout", "barGlows", function() BG.Invalidate("profile") end)
