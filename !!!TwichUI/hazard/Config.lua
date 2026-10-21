-- TwichUI: Hazard alerts, configuration
-- What the feature stores and how a stored value is read. Nothing here touches a frame or the game's aura sounds.
--
-- What this feature is. The Forever client gives addons no combat-log payload (C_CombatLogSecure.GetCurrentEventInfo is
-- SecureOnly, and COMBAT_LOG_EVENT_UNFILTERED carries no arguments to addons), so damage amounts, sources and friendly
-- fire cannot be read. What it does offer is C_UnitAuras.AddAuraSound: the game itself plays a sound file when an aura
-- is added to, grows on, or leaves a unit. Hazard alerts are therefore aura sounds for a list of spell IDs, registered
-- for the player only, with a sound chosen per alert category. docs/hazard-alerts.md has the reasoning.
--
-- What is stored (all in the profile in use, TwichUIDB.ui):
--   ui.hazard          the settings: per category on/off and sound, and the volume channel. DEFAULTS and LIMITS below;
--                      every value is checked on the way in and on the way out, and an invalid stored one reads as its
--                      default without being erased.
--   ui.hazardCustom    { rules = { { id, enabled, name, spell, trigger, category, throttle }, ... }, next = n }
--   ui.hazardBuiltin   { off = { [ruleId] = true } }: the built-in rules the player turned off. Shipped definitions are
--                      never copied here, so an update can change them without touching the player's choices.
-- The switch is TwichUIDB.modules.hazardAlerts (off until turned on). Nothing runtime is saved: no handles, no timers.
--
-- Every setter calls Invalidate(); the controller (Alerts.lua) listens and registers again once.

local R = TwichUI
local HZ = {}
R.Hazard = HZ

-- The alert categories. They say how urgent a rule is and which sound it uses; they say nothing about damage. "Friendly
-- fire" is not offered: telling it apart needs the source of a hit, which the client does not give addons.
HZ.CATEGORIES = {
    { "high", "Urgent danger", "Something that hurts a lot or ends in a death if you stay in it. The strongest sound." },
    { "low", "Warning", "Something worth stepping out of, but not an emergency. A softer sound." },
    { "fail", "Failed mechanic", "A debuff that only lands when a mechanic was missed, so the sound means: that one was missed." },
}
HZ.CATEGORY = {}
for _, c in ipairs(HZ.CATEGORIES) do HZ.CATEGORY[c[1]] = c end

-- What a rule listens for on you. The game's trigger names are Enum.UnitAuraSoundTrigger.Added, ApplicationsIncreased and
-- Removed (Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraConstantsDocumentation.lua).
HZ.TRIGGERS = {
    { "applied", "Aura applied to me", "Added", "Plays when the aura is put on you." },
    { "stacks", "Aura stacks grow", "ApplicationsIncreased", "Plays each time the aura's stack count goes up. The game gives no way to wait for a particular stack count." },
    { "removed", "Aura fades from me", "Removed", "Plays when the aura leaves you." },
}
HZ.TRIGGER = {}
for _, t in ipairs(HZ.TRIGGERS) do HZ.TRIGGER[t[1]] = t end

HZ.DEFAULTS = {
    highOn = true, lowOn = true, failOn = true,
    highSound = "TwichUI Drums", lowSound = "TwichUI Notification", failSound = "Single Knell",
    channel = "SFX",
}
HZ.NONE = "None"   -- the "no sound" choice; a category set to it registers nothing

-- The game allows 0 to 5 seconds between two plays of one registered sound, and nothing longer.
HZ.THROTTLE = { 0, 5 }
HZ.THROTTLE_DEFAULT = 2
HZ.MAX_CUSTOM = 40
HZ.MAX_BUILTIN_OFF = 200
HZ.MAX_NAME = 60

HZ.CHOICES = {
    channel = {
        { "SFX", "Sound effects", "Follows the Sound Effects volume." },
        { "Master", "Master", "Follows only the Master volume, so it is heard even with sound effects turned down." },
        { "Dialog", "Dialog", "Follows the Dialog volume." },
        { "Ambience", "Ambience", "Follows the Ambience volume." },
    },
}
HZ.ENUM = {}
for key, list in pairs(HZ.CHOICES) do
    local values = {}
    for _, c in ipairs(list) do values[c[1]] = true end
    HZ.ENUM[key] = values
end

local function Finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function Whole(v) return Finite(v) and v % 1 == 0 end
local function Name(v, max) return type(v) == "string" and #v > 0 and #v <= (max or 100) and not v:find("[%c|]") end
local function SpellId(v) return Whole(v) and v >= 1 and v <= 2147483647 end

HZ.ValidSpell = SpellId

-- The keys of the stored settings that are sound names.
local SOUND_KEY = { highSound = true, lowSound = true, failSound = true }

function HZ.Valid(key, value)
    local default = HZ.DEFAULTS[key]
    if default == nil then return false end
    if type(default) == "boolean" then return type(value) == "boolean" end
    if HZ.ENUM[key] then return type(value) == "string" and HZ.ENUM[key][value] == true end
    if SOUND_KEY[key] then return Name(value, 64) end
    return false
end

---------------------------------------------------------------------------
-- Change notices
---------------------------------------------------------------------------
local subscribers = {}

function HZ.Subscribe(fn) subscribers[#subscribers + 1] = fn end

-- Something the registrations are made from changed (a setting, a rule, a profile): the controller registers once.
function HZ.Invalidate()
    for _, fn in ipairs(subscribers) do
        local ok, err = pcall(fn)
        if not ok then R.Fault("hazard alerts", err) end
    end
end

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

local function Group(name, create)
    local ui = Ui(create)
    if not ui then return nil end
    if type(ui[name]) ~= "table" then
        if not create then return nil end
        ui[name] = {}
    end
    return ui[name]
end

function HZ.Get(key)
    local t = Group("hazard", false)
    local value
    if t then value = t[key] end   -- not "and ... or": a saved false is a value
    if HZ.Valid(key, value) then return value end
    return HZ.DEFAULTS[key]
end

function HZ.Set(key, value)
    if HZ.DEFAULTS[key] == nil or not HZ.Valid(key, value) then return false end
    local t = Group("hazard", true)
    if not t then return false end
    if t[key] == value then return true end
    t[key] = value
    HZ.Invalidate()
    return true
end

-- Every setting back to its default (forgotten, so a better default later still applies). The rules stay.
function HZ.ResetSettings()
    local t = Group("hazard", false)
    if not t then return end
    local changed = false
    for key in pairs(HZ.DEFAULTS) do
        if t[key] ~= nil then t[key] = nil; changed = true end
    end
    if changed then HZ.Invalidate() end
end

-- Per category views of the settings, for the controller and the page.
function HZ.CategoryOn(category) return HZ.Get(category .. "On") end
function HZ.CategorySound(category) return HZ.Get(category .. "Sound") end

---------------------------------------------------------------------------
-- Built-in rules the player turned off
---------------------------------------------------------------------------
local ID_PATTERN = "^[%w%._%-]+$"
function HZ.ValidRuleId(id) return type(id) == "string" and #id >= 1 and #id <= 40 and id:match(ID_PATTERN) ~= nil end

function HZ.BuiltinOff()
    local t = Group("hazardBuiltin", false)
    local off = t and t.off
    return type(off) == "table" and off or {}
end

function HZ.IsBuiltinOff(id) return HZ.BuiltinOff()[id] == true end

function HZ.SetBuiltinEnabled(id, enabled)
    if not HZ.ValidRuleId(id) then return false end
    local t = Group("hazardBuiltin", true)
    if not t then return false end
    if type(t.off) ~= "table" then t.off = {} end
    if enabled then
        if t.off[id] == nil then return true end
        t.off[id] = nil
    else
        if t.off[id] == true then return true end
        local n = 0
        for _ in pairs(t.off) do n = n + 1 end
        if n >= HZ.MAX_BUILTIN_OFF then return false end
        t.off[id] = true
    end
    HZ.Invalidate()
    return true
end

-- Every built-in rule back on.
function HZ.ResetBuiltin()
    local t = Group("hazardBuiltin", false)
    if not t or type(t.off) ~= "table" or next(t.off) == nil then return end
    t.off = {}
    HZ.Invalidate()
end

---------------------------------------------------------------------------
-- The player's own rules
---------------------------------------------------------------------------
-- A rule as stored. Returns the clean copy, or nil and why. Unknown fields are dropped.
function HZ.CleanRule(raw)
    if type(raw) ~= "table" then return nil, "shape" end
    if not HZ.ValidRuleId(raw.id) then return nil, "id" end
    if not SpellId(raw.spell) then return nil, "spell" end
    if not HZ.TRIGGER[raw.trigger] then return nil, "trigger" end
    if not HZ.CATEGORY[raw.category] then return nil, "category" end
    local t = raw.throttle
    if not (Whole(t) and t >= HZ.THROTTLE[1] and t <= HZ.THROTTLE[2]) then return nil, "throttle" end
    local name = raw.name
    if not Name(name, HZ.MAX_NAME) then return nil, "name" end
    local enabled = raw.enabled
    if enabled ~= nil and type(enabled) ~= "boolean" then return nil, "enabled" end
    return { id = raw.id, enabled = enabled ~= false, name = name, spell = raw.spell, trigger = raw.trigger,
        category = raw.category, throttle = t }
end

local function Rules(create)
    local t = Group("hazardCustom", create)
    if not t then return nil end
    if type(t.rules) ~= "table" then
        if not create then return nil end
        t.rules = {}
    end
    return t.rules, t
end

-- The stored rules that read as valid, in order. Entries that do not are left alone and not listed. Not copies: do not
-- change them (the setters below do).
function HZ.List()
    local rules = Rules(false)
    local out = {}
    if not rules then return out end
    for _, raw in ipairs(rules) do
        if HZ.CleanRule(raw) then out[#out + 1] = raw end
    end
    return out
end

function HZ.Count() return #HZ.List() end

function HZ.Find(id)
    for _, rule in ipairs(HZ.List()) do if rule.id == id then return rule end end
    return nil
end

-- Another enabled or disabled custom rule with the same spell and trigger (the one a new rule would double).
function HZ.Duplicate(spell, trigger, exceptId)
    for _, rule in ipairs(HZ.List()) do
        if rule.spell == spell and rule.trigger == trigger and rule.id ~= exceptId then return rule end
    end
    return nil
end

local function NextId(t)
    local n = Whole(t.next) and t.next or 0
    local taken = {}
    for _, r in ipairs(t.rules) do if type(r) == "table" then taken[r.id] = true end end
    repeat n = n + 1 until not taken["c" .. n]
    t.next = n
    return "c" .. n
end

-- Fields the editor offers, with the checks above. spell may arrive as text (a number typed or pasted).
function HZ.Normalize(fields)
    local spell = fields.spell
    if type(spell) == "string" then spell = tonumber(spell:match("^%s*(%d+)%s*$")) end
    local name = fields.name
    if type(name) == "string" then name = name:gsub("^%s+", ""):gsub("%s+$", "") end
    return { enabled = fields.enabled ~= false, name = name, spell = spell, trigger = fields.trigger or "applied",
        category = fields.category or "low", throttle = fields.throttle == nil and HZ.THROTTLE_DEFAULT or fields.throttle }
end

-- Adds a rule. Returns true, id, or false, why ("full", "duplicate" with the existing rule, or a field name).
function HZ.Add(fields)
    local f = HZ.Normalize(fields)
    f.id = "c0"   -- checked now, given its real id below
    local rule, why = HZ.CleanRule(f)
    if not rule then return false, why end
    local twin = HZ.Duplicate(rule.spell, rule.trigger)
    if twin then return false, "duplicate", twin end
    local rules, t = Rules(true)
    if not rules then return false, "unavailable" end
    if #HZ.List() >= HZ.MAX_CUSTOM or #rules >= HZ.MAX_CUSTOM * 2 then return false, "full" end
    rule.id = NextId(t)
    rules[#rules + 1] = rule
    HZ.Invalidate()
    return true, rule.id
end

local EDITABLE = { "enabled", "name", "spell", "trigger", "category", "throttle" }

-- Changes the named fields of a rule. Returns true, or false, why.
function HZ.Update(id, fields)
    local rules = Rules(false)
    if not rules then return false, "missing" end
    for i, stored in ipairs(rules) do
        if type(stored) == "table" and stored.id == id and HZ.CleanRule(stored) then
            local f = {}
            for _, k in ipairs(EDITABLE) do
                if fields[k] ~= nil then f[k] = fields[k] else f[k] = stored[k] end
            end
            f = HZ.Normalize(f)
            f.id = id
            local rule, why = HZ.CleanRule(f)
            if not rule then return false, why end
            local twin = HZ.Duplicate(rule.spell, rule.trigger, id)
            if twin then return false, "duplicate", twin end
            rules[i] = rule
            HZ.Invalidate()
            return true
        end
    end
    return false, "missing"
end

function HZ.SetRuleEnabled(id, enabled) return HZ.Update(id, { enabled = enabled and true or false }) end

function HZ.Remove(id)
    local rules = Rules(false)
    if not rules then return false end
    for i, stored in ipairs(rules) do
        if type(stored) == "table" and stored.id == id then
            table.remove(rules, i)
            HZ.Invalidate()
            return true
        end
    end
    return false
end

-- A copy of a rule, switched off so it can be changed before it plays. Returns true, id or false, why.
function HZ.DuplicateRule(id)
    local rule = HZ.Find(id)
    if not rule then return false, "missing" end
    -- the same spell and trigger would be a duplicate, so the copy starts on the next trigger that is free
    for _, t in ipairs(HZ.TRIGGERS) do
        if t[1] ~= rule.trigger and not HZ.Duplicate(rule.spell, t[1]) then
            return HZ.Add({ enabled = false, name = (rule.name .. " (copy)"):sub(1, HZ.MAX_NAME), spell = rule.spell, trigger = t[1],
                category = rule.category, throttle = rule.throttle })
        end
    end
    return false, "duplicate"
end

-- Every custom rule removed (the settings and the built-in choices stay).
function HZ.ClearCustom()
    local rules = Rules(false)
    if not rules or #rules == 0 then return end
    local t = Group("hazardCustom", false)
    t.rules = {}
    HZ.Invalidate()
end
