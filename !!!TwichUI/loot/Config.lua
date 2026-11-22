-- TwichUI: Loot Rolls, what is stored
-- The settings of Loot Rolls (loot cards that replace the game's group-loot roll frames, and rules that can pick Need, Greed or Pass for
-- you, visibly, after a delay you can cancel) and the rules themselves. Nothing here touches a frame, an event or an item: it keeps
-- the saved data, checks it on the way in and on the way out, and says when something changed. Rules.lua decides (pure), Roll.lua
-- watches the game's rolls, Auto.lua acts on a decision, Cards.lua draws, Blizzard.lua lets the default frames step aside.
-- docs/loot-rolls-implementation.md has the design and what has and has not been proved in the client.
--
-- What is stored (the profile in use, TwichUIDB.ui.lootRolls; switch: TwichUIDB.modules.lootRolls, off by default):
--   the settings in DEFAULTS (each checked against LIMITS or CHOICES; an unusable stored value reads as its default and is left as
--   it is), the place (x, y), and `rules`: a list of { id, name, enabled, action, match, delay, result, conditions = { ... } } with
--   `seq`, the number the last rule's id was made from (ids are never reused).
-- Never stored: which items dropped, what you rolled, what anyone else rolled, who won. The cards last for the session only.
--
-- Automation defaults: off. `auto` is the master switch, `autoNeed` separately allows a rule to choose Need, `autoUpgrade` separately
-- allows a rule that asks whether an item is an upgrade to count, `paused` stops everything without touching a rule.

local R = TwichUI
local Ru = R.LootRules
local LR = {}
R.LootRolls = LR

LR.POSITION_LIMIT = 4096
LR.MAX_RULES = 24

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
LR.Finite, LR.Whole = Finite, Whole

---------------------------------------------------------------------------
-- The settings
---------------------------------------------------------------------------
LR.DEFAULTS = {
    -- the cards
    scale = 100, spacing = 8, growth = "down", maxCards = 4, afterResult = 8,
    showUpgrade = true, showValue = true, showResults = true, timer = "both", animate = true,
    -- fading (milliseconds; "animate" is the master switch) and the countdown bar
    fadeIn = 250, fadeOut = 450,
    -- Sheer (EllesmereUI's bar texture; drawn flat where it is not installed), and the colors: weathered sage, antique gold, burnished ember,
    -- muted crimson (a roll that ran out), and a deep espresso track. A rule's countdown starts from the sage.
    barTexture = "eui:sheer", barHeight = 14, barShine = false, barShift = true,
    barColorHigh = "ff91ad78", barColorMid = "ffd0aa60", barColorLow = "ffd18450", barColorExpired = "ffba5d55", barColorRule = "ff91ad78",
    barTrack = "ff211a16",
    -- confirmed loot-win celebration (independent from rule evaluation)
    victory = true, victoryIntensity = "subtle", victorySound = false, victoryDuration = "normal",
    -- automation (everything starts off)
    auto = false, autoNeed = false, autoUpgrade = false, paused = false, autoDelay = 3,
    -- where the stack sits: its top centre as an offset from the screen's centre, in screen units
    x = 420, y = 300,
}

LR.LIMITS = {
    scale = { 50, 160 }, spacing = { 0, 30 }, maxCards = { 1, 6 }, afterResult = { 2, 60 }, autoDelay = { 1, 15 },
    fadeIn = { 0, 1000 }, fadeOut = { 0, 2000 }, barHeight = { 8, 24 },
    x = { -LR.POSITION_LIMIT, LR.POSITION_LIMIT }, y = { -LR.POSITION_LIMIT, LR.POSITION_LIMIT },
}

LR.CHOICES = {
    victoryIntensity = { { "off", "Off" }, { "subtle", "Subtle" }, { "full", "Full" } },
    victoryDuration = { { "short", "Short" }, { "normal", "Normal" }, { "long", "Long" } },
    growth = {
        { "down", "Downwards", "The first roll is at the top and the stack grows down from there." },
        { "up", "Upwards", "The first roll is at the bottom and the stack grows up from there." },
    },
    timer = {
        { "both", "Bar and seconds", "A bar that empties and the time left, as in the settings preview." },
        { "bar", "Bar only", "Only the bar." },
        { "number", "Seconds only", "Only the time left." },
    },
}
-- Settings that are text and not a choice: a bar texture's id (MenuStyle.StatusBars: "solid", "eui:<key>" or a LibSharedMedia name) and
-- colors ("AARRGGBB", as the swatches save them).
LR.TEXT = { barTexture = "texture", barColorHigh = "color", barColorMid = "color", barColorLow = "color", barColorExpired = "color", barColorRule = "color", barTrack = "color" }
LR.COLOR_KEYS = { "barColorHigh", "barColorMid", "barColorLow", "barColorExpired", "barColorRule", "barTrack" }
LR.ENUM = {}
for key, list in pairs(LR.CHOICES) do
    local set = {}
    for _, c in ipairs(list) do set[c[1]] = true end
    LR.ENUM[key] = set
end

function LR.Valid(key, value)
    local default = LR.DEFAULTS[key]
    if default == nil then return false end
    if type(default) == "boolean" then return type(value) == "boolean" end
    local text = LR.TEXT[key]
    if text == "color" then return type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") ~= nil end
    if text == "texture" then return type(value) == "string" and #value > 0 and #value <= 100 and not value:find("[%c|]") end
    if type(default) == "number" then
        local lim = LR.LIMITS[key]
        return Whole(value) and lim ~= nil and value >= lim[1] and value <= lim[2]
    end
    if LR.ENUM[key] then return type(value) == "string" and LR.ENUM[key][value] == true end
    return false
end

---------------------------------------------------------------------------
-- Change notices
---------------------------------------------------------------------------
local subscribers = {}
local rev = 0

function LR.Subscribe(fn) subscribers[#subscribers + 1] = fn end
function LR.Rev() return rev end

-- Something the cards are drawn or decided from changed: told once. what: "place", "settings", "rules" or "profile".
function LR.Invalidate(what)
    rev = rev + 1
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("loot rolls", err) end
    end
end

---------------------------------------------------------------------------
-- Reading and writing the settings
---------------------------------------------------------------------------
local function Saved(create)
    local db = TwichUIDB
    if type(db) ~= "table" then return nil end
    if type(db.ui) ~= "table" then
        if not create then return nil end
        db.ui = {}
    end
    if type(db.ui.lootRolls) ~= "table" then
        if not create then return nil end
        db.ui.lootRolls = {}
    end
    return db.ui.lootRolls
end

function LR.Get(key)
    local t = Saved(false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false is a value
    if LR.Valid(key, value) then return value end
    return LR.DEFAULTS[key]
end

function LR.Set(key, value)
    if LR.DEFAULTS[key] == nil or not LR.Valid(key, value) then return false end
    local t = Saved(true)
    if not t then return false end
    if t[key] == value then return true end
    t[key] = value
    LR.Invalidate((key == "x" or key == "y") and "place" or "settings")
    return true
end

-- Every setting back to its default (forgotten, so a better default later still applies). The rules and the place are kept (each
-- has a reset of its own) and so is the automation switch: a reset never turns automation on or off.
function LR.ResetSettings()
    local t = Saved(false)
    if t then
        for key in pairs(LR.DEFAULTS) do
            if key ~= "x" and key ~= "y" and key ~= "auto" and key ~= "autoNeed"
                and key ~= "autoUpgrade" and key ~= "paused" then t[key] = nil end
        end
    end
    LR.Invalidate("settings")
end

function LR.Place() return LR.Get("x"), LR.Get("y") end
function LR.ValidOffset(v) return Finite(v) and math.abs(v) <= LR.POSITION_LIMIT end

function LR.SetPlace(x, y)
    if not (LR.ValidOffset(x) and LR.ValidOffset(y)) then return false end
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    local t = Saved(true)
    if not t then return false end
    if t.x == x and t.y == y then return true end
    t.x, t.y = x, y
    LR.Invalidate("place")
    return true
end

function LR.ResetPlace()
    local t = Saved(false)
    if not t or (t.x == nil and t.y == nil) then return end
    t.x, t.y = nil, nil
    LR.Invalidate("place")
end

---------------------------------------------------------------------------
-- Automation, in the words the cards use
---------------------------------------------------------------------------
-- Whether rules may act at all right now (the switches only; the roll itself is checked by Auto.lua).
function LR.AutoOn() return LR.Get("auto") == true and LR.Get("paused") ~= true end
function LR.Paused() return LR.Get("paused") == true end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
local function List(create)
    local t = Saved(create)
    if not t then return nil end
    if type(t.rules) ~= "table" then
        if not create then return nil end
        t.rules = {}
    end
    return t.rules
end

local function ValidName(v) return type(v) == "string" and #v > 0 and #v <= Ru.MAX_NAME and not v:find("[%c|]") end
-- a rule always waits at least a second: the window to stop it is not optional
local function ValidDelay(v) return Finite(v) and v >= 1 and v <= 15 end
local function ValidId(v) return type(v) == "string" and v:match("^lr%d+$") ~= nil and #v <= 12 end

local function Find(id)
    local list = List(false)
    if not list then return nil end
    for i, rule in ipairs(list) do
        if type(rule) == "table" and rule.id == id then return rule, i, list end
    end
end

-- A rule as the editor and the list read it: a plain copy with what is missing filled in, never the saved table itself.
local function View(rule, index)
    local v = {
        id = rule.id, index = index,
        name = ValidName(rule.name) and rule.name or "Loot rule",
        enabled = rule.enabled == true,
        action = rule.action, display = rule.display or "none",
        match = rule.match == "any" and "any" or "all",
        delay = ValidDelay(rule.delay) and rule.delay or LR.Get("autoDelay"),
        result = rule.result ~= false,
        conditions = {},
    }
    for i, c in ipairs(type(rule.conditions) == "table" and rule.conditions or {}) do
        if type(c) == "table" then
            local copy = {}
            for k, val in pairs(c) do copy[k] = val end
            v.conditions[i] = copy
        end
    end
    v.incomplete = Ru.Incomplete(v)
    v.usesUpgrade = false
    for _, c in ipairs(v.conditions) do
        if c.type == "upgrade" then v.usesUpgrade = true end
    end
    v.summary = Ru.Summary(v)
    return v
end

function LR.List()
    local out = {}
    for i, rule in ipairs(List(false) or {}) do
        if #out >= LR.MAX_RULES then break end   -- a saved list longer than the limit (hand-edited, or from elsewhere) is read only this far
        if type(rule) == "table" and ValidId(rule.id) then out[#out + 1] = View(rule, i) end
    end
    return out
end

function LR.Count() return #LR.List() end

function LR.Rule(id)
    local rule, index = Find(id)
    if rule then return View(rule, index) end
end

-- The saved rules in order, for Rules.Decide (it reads them and checks each; it never changes one).
function LR.Active()
    local out = {}
    for _, rule in ipairs(List(false) or {}) do
        if #out >= LR.MAX_RULES then break end
        if type(rule) == "table" and ValidId(rule.id) then out[#out + 1] = rule end
    end
    return out
end

local function NextId(t)
    local n = Whole(t.seq) and t.seq or 0
    for _, rule in ipairs(t.rules or {}) do
        local k = type(rule) == "table" and type(rule.id) == "string" and tonumber(rule.id:match("^lr(%d+)$"))
        if k and k > n then n = k end
    end
    n = n + 1
    t.seq = n
    return "lr" .. n
end

-- Starting points offered by "New rule". Each starts switched off: turn it on once it says what you mean.
LR.TEMPLATES = {
    { key = "blank", label = "Start from nothing", name = "New rule", action = "none", conditions = { { type = "quality", op = "is", value = 2 } } },
    { key = "greenGear", label = "Greed on green gear", name = "Greed on green gear", action = "greed",
        conditions = { { type = "quality", op = "is", value = 2 }, { type = "class", value = "equipment" } } },
    { key = "recipes", label = "Pass on recipes I already know", name = "Pass known recipes", action = "pass",
        conditions = { { type = "recipe", mode = "known" } } },
    { key = "professionRecipes", label = "Greed on my profession recipes", name = "Greed on profession recipes", action = "greed",
        conditions = { { type = "recipe", mode = "profession" } } },
}

function LR.Create(kind)
    local list = List(true)
    if not list then return false, "Settings are not ready." end
    if #list >= LR.MAX_RULES then return false, ("You can keep up to %d rules."):format(LR.MAX_RULES) end
    local template
    for _, t in ipairs(LR.TEMPLATES) do if t.key == (kind or "blank") then template = t end end
    if not template then return false, "No such starting point." end
    local t = Saved(true)
    local rule = {
        id = NextId(t), name = template.name, enabled = false, action = template.action, display = "none", match = "all",
        delay = LR.Get("autoDelay"), result = true, conditions = {},
    }
    for i, c in ipairs(template.conditions) do
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        rule.conditions[i] = copy
    end
    list[#list + 1] = rule
    LR.Invalidate("rules")
    return true, rule.id
end

function LR.Duplicate(id)
    local rule, index, list = Find(id)
    if not rule then return false, "That rule is gone." end
    if #list >= LR.MAX_RULES then return false, ("You can keep up to %d rules."):format(LR.MAX_RULES) end
    local t = Saved(true)
    local copy = { id = NextId(t), enabled = false, conditions = {} }
    for k, v in pairs(rule) do
        if k ~= "id" and k ~= "enabled" and k ~= "conditions" then copy[k] = v end
    end
    local name = ValidName(rule.name) and rule.name or "Loot rule"
    copy.name = (name .. " (copy)"):sub(1, Ru.MAX_NAME)
    for i, c in ipairs(type(rule.conditions) == "table" and rule.conditions or {}) do
        local cc = {}
        for k, v in pairs(c) do cc[k] = v end
        copy.conditions[i] = cc
    end
    table.insert(list, index + 1, copy)
    LR.Invalidate("rules")
    return true, copy.id
end

function LR.Delete(id)
    local rule, index, list = Find(id)
    if not rule then return false end
    table.remove(list, index)
    LR.Invalidate("rules")
    return true
end

-- delta -1 moves it up (it is read earlier), +1 down.
function LR.Move(id, delta)
    local rule, index, list = Find(id)
    if not rule or (delta ~= -1 and delta ~= 1) then return false end
    local to = index + delta
    if to < 1 or to > #list then return false end
    list[index], list[to] = list[to], list[index]
    LR.Invalidate("rules")
    return true
end

local function Edit(id, fn)
    local rule = Find(id)
    if not rule then return false, "That rule is gone." end
    local changed = fn(rule)
    if changed == false then return false end
    if changed then LR.Invalidate("rules") end
    return true
end

function LR.SetName(id, name)
    if type(name) == "string" then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
    if not ValidName(name) then return false, ("A name is 1 to %d characters."):format(Ru.MAX_NAME) end
    return Edit(id, function(r) if r.name == name then return nil end r.name = name return true end)
end

function LR.SetEnabled(id, on)
    if type(on) ~= "boolean" then return false end
    return Edit(id, function(r) if (r.enabled == true) == on then return nil end r.enabled = on return true end)
end

function LR.SetAction(id, action)
    if not Ru.ACTION_LABEL[action] then return false end
    return Edit(id, function(r) if r.action == action then return nil end r.action = action return true end)
end

function LR.SetDisplay(id, display)
    if not Ru.DISPLAY_LABEL[display] then return false end
    return Edit(id, function(r) if (r.display or "none") == display then return nil end r.display = display return true end)
end

function LR.SetMatch(id, mode)
    if mode ~= "all" and mode ~= "any" then return false end
    return Edit(id, function(r) if (r.match or "all") == mode then return nil end r.match = mode return true end)
end

function LR.SetDelay(id, seconds)
    if not ValidDelay(seconds) then return false end
    seconds = math.floor(seconds * 10 + 0.5) / 10
    return Edit(id, function(r) if r.delay == seconds then return nil end r.delay = seconds return true end)
end

function LR.SetShowResult(id, on)
    if type(on) ~= "boolean" then return false end
    return Edit(id, function(r) if (r.result ~= false) == on then return nil end r.result = on return true end)
end

-- Adds a condition of a kind (see Rules.ORDER) with its starting values; returns its place in the list.
function LR.AddCondition(id, kind)
    local fresh = Ru.NewCondition(kind)
    if not fresh then return false, "No such condition." end
    local index
    local ok, why = Edit(id, function(r)
        if type(r.conditions) ~= "table" then r.conditions = {} end
        if #r.conditions >= Ru.MAX_CONDITIONS then return false end
        r.conditions[#r.conditions + 1] = fresh
        index = #r.conditions
        return true
    end)
    if not ok then return false, why or ("A rule can have up to %d conditions."):format(Ru.MAX_CONDITIONS) end
    return true, index
end

-- Changes fields of one condition (a table of the fields to set); the result must still be a complete condition.
function LR.SetCondition(id, index, fields)
    if type(fields) ~= "table" then return false end
    return Edit(id, function(r)
        local c = type(r.conditions) == "table" and r.conditions[index]
        if type(c) ~= "table" then return false end
        local copy = {}
        for k, v in pairs(c) do copy[k] = v end
        for k, v in pairs(fields) do
            if k ~= "type" then copy[k] = v end
        end
        if Ru.CheckCondition(copy) ~= nil then return false end
        local same = true
        for k, v in pairs(copy) do if c[k] ~= v then same = false end end
        for k in pairs(c) do if copy[k] == nil then same = false end end
        if same then return nil end
        r.conditions[index] = copy
        return true
    end)
end

function LR.RemoveCondition(id, index)
    return Edit(id, function(r)
        if type(r.conditions) ~= "table" or not r.conditions[index] then return false end
        table.remove(r.conditions, index)
        return true
    end)
end

---------------------------------------------------------------------------
-- A profile change puts another profile's settings and rules in place: everything is read again.
---------------------------------------------------------------------------
R.Profiles.OnApply("layout", "lootRolls", function() LR.Invalidate("profile") end)
