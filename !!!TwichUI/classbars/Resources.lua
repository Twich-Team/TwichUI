-- TwichUI: class resource bars, resource providers
-- A provider knows one resource: when it applies to the player, how to read it, and which game events change it.
-- It hands the rest of the feature one normalized state { key, token, label, kind, cur, max, ok } and nothing
-- else: how it is drawn (Bar.lua), what it is called in settings (Config.lua) and what decorates it (Effects.lua)
-- are none of its business, and none of them reads the game's power APIs.
--
-- What is covered, and why (read from the Forever branch of the UI source, game type "camelot", never assumed
-- from Retail; docs/class-bars.md has the full capability matrix with file references):
--   * Forever has no specializations (its Personal Resource Display says so, Blizzard_PersonalResourceDisplay/
--     Camelot), so nothing here reads a specialization.
--   * The primary bar shows the power the client says the player is using now, UnitPowerType("player"): a Warrior's
--     rage, a Rogue's energy, a Druid's mana, energy in Cat Form and rage in Bear Form. No table of "what each
--     class uses" decides it. Any continuous power the client reports is drawn; nothing is substituted for one it
--     does not report.
--   * Combo points are the only class resource Forever's UI ships (Blizzard_UnitFrame/Camelot/TargetBoundComboPointBar:
--     Rogues, and Druids while their power is energy). They belong to the target: the count is
--     GetComboPoints("player", "target"), and it changes with PLAYER_TARGET_CHANGED and COMBO_TARGET_CHANGED as well
--     as with the power events.
--   * A Druid whose power is not mana (Cat, Bear) also gets a mana bar (Camelot's own Personal Resource Display adds
--     one in exactly that case).
--   * Not covered, because the Forever client loads none of their bars (Blizzard_UnitFrame.toc excludes them for
--     camelot): runes, soul shards, holy power, arcane charges, chi, essence, insanity, stagger, soul fragments;
--     and anything that would have to be inferred from auras. Nothing here recharges, so there is no cooldown
--     display. A resource the client does not report is never drawn as another one.
--
-- A game value that is "secret" (restricted) cannot be compared, computed with or formatted by addon code. Every read
-- goes through Plain(), and a secret value makes the state not ok (the bar hides), never a guess, with one exception:
-- the current value of a continuous power (a Mage's mana is secret in Forever; its maximum is not). That state is ok
-- with secret = true, cur holds the restricted value untouched (pct, when the game supplies it, is the game's own
-- 0 to 100 of the same), and the only things that may touch them are a StatusBar's SetValue and a FontString's
-- SetText (Bar.lua). Nothing compares it, adds it or tests it for rest.
--
-- Adding a resource: R.ClassBarResources.Register{ id, slot, kind, classes (optional set), keys (optional list, what
-- settings offers an override for), unitEvents, events, Applies(ctx), Read(provider, ctx) } and, if it has a
-- resting state or a color, REST[key] and COLORS[key] below. docs/class-bars.md walks through it.

local R = TwichUI
local CBR = {}
R.ClassBarResources = CBR

-- Enum.PowerType in the Forever API documentation (PowerTypeConstantsDocumentation.lua).
local POWER_MANA, POWER_ENERGY, POWER_COMBO = 0, 3, 4

CBR.SLOTS = { "primary", "secondary", "tertiary" }
CBR.COMBO_CAP = 5        -- the most combo points shown (Blizzard's own cap, MAX_COMBO_POINTS in ComboFrame.lua)
CBR.MAX_SEGMENTS = 10    -- the most segments a bar draws

local SLOT_OK = {}
for _, slot in ipairs(CBR.SLOTS) do SLOT_OK[slot] = true end

---------------------------------------------------------------------------
-- Reading the game
---------------------------------------------------------------------------
local function Plain(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end
CBR.Plain = Plain

local function PlainNumber(v)
    v = Plain(v)
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return v end
    return nil
end

local function PlainString(v)
    v = Plain(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

-- What the player is, and the power the client says is shown now. One table, rewritten in place.
local ctx = { class = nil, powerType = nil, token = nil, r = nil, g = nil, b = nil }

function CBR.Context() return ctx end

function CBR.Sense()
    local _, class = UnitClass("player")
    ctx.class = PlainString(class)
    local powerType, token, r, g, b = UnitPowerType("player")
    powerType, token = PlainNumber(powerType), PlainString(token)
    if powerType and token then
        ctx.powerType, ctx.token = powerType, token
        ctx.r, ctx.g, ctx.b = PlainNumber(r), PlainNumber(g), PlainNumber(b)
    else
        ctx.powerType, ctx.token, ctx.r, ctx.g, ctx.b = nil, nil, nil, nil, nil
    end
    return ctx
end

-- The player's own word for a resource: the game's global string of that name ("MANA" is "Mana"), else the token
-- lower-cased with spaces.
local labels = {}
function CBR.Label(token)
    local label = labels[token]
    if label then return label end
    local g = rawget(_G, token)
    if type(g) == "string" and g ~= "" and not (issecretvalue and issecretvalue(g)) then
        label = g
    else
        label = token:lower():gsub("_", " "):gsub("(%a)(%w*)", function(a, b) return a:upper() .. b end)
    end
    labels[token] = label
    return label
end

---------------------------------------------------------------------------
-- Resting state: the value a resource sits at when nothing is happening, for the "Show when active" rule.
-- "full": mana, energy and focus refill. "empty": rage, runic power and combo points decay or are spent. A
-- resource without an entry has no resting state we know, so it is never called "at rest" (it stays shown).
---------------------------------------------------------------------------
CBR.REST = { MANA = "full", ENERGY = "full", FOCUS = "full", RAGE = "empty", RUNIC_POWER = "empty", COMBO_POINTS = "empty" }

-- Default fill colors, our own muted palette. A resource not listed takes the color the client gives its power.
CBR.COLORS = {
    MANA = { 0.30, 0.52, 0.90 }, RAGE = { 0.78, 0.25, 0.20 }, FOCUS = { 0.85, 0.55, 0.30 },
    ENERGY = { 0.92, 0.80, 0.28 }, RUNIC_POWER = { 0.20, 0.72, 0.90 }, COMBO_POINTS = { 0.95, 0.75, 0.25 },
}
local IVORY = { 0.94, 0.91, 0.82 }

-- r, g, b for a resource key: ours, else the client's color for the power it reports now, else ivory.
function CBR.Color(key, c)
    local mine = CBR.COLORS[key]
    if mine then return mine[1], mine[2], mine[3] end
    c = c or ctx
    if c.token == key and c.r and c.g and c.b then return c.r, c.g, c.b end
    return IVORY[1], IVORY[2], IVORY[3]
end

-- r, g, b of a class, ivory when the game gives none.
function CBR.ClassColor(class)
    local t = rawget(_G, "RAID_CLASS_COLORS")
    local c = type(class) == "string" and type(t) == "table" and t[class]
    if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
        return c.r, c.g, c.b
    end
    return IVORY[1], IVORY[2], IVORY[3]
end

-- True when a state is at its resting value. A state without a resting value is never at rest.
function CBR.AtRest(key, cur, max)
    local rest = CBR.REST[key]
    if rest == "full" then return cur >= max end
    if rest == "empty" then return cur <= 0 end
    return false
end

---------------------------------------------------------------------------
-- The registry
---------------------------------------------------------------------------
local providers, byId, bySlot = {}, {}, {}
for _, slot in ipairs(CBR.SLOTS) do bySlot[slot] = {} end

local function List(t) return type(t) == "table" and t or {} end

-- Adds a provider. Returns true, or false and a reason. A malformed one is refused, never half added.
function CBR.Register(def)
    if type(def) ~= "table" then return false, "shape" end
    if type(def.id) ~= "string" or def.id == "" or byId[def.id] then return false, "id" end
    if not SLOT_OK[def.slot] then return false, "slot" end
    if def.kind ~= "continuous" and def.kind ~= "segmented" then return false, "kind" end
    if type(def.Applies) ~= "function" or type(def.Read) ~= "function" then return false, "functions" end
    if def.classes ~= nil and type(def.classes) ~= "table" then return false, "classes" end
    def.keys, def.unitEvents, def.events = List(def.keys), List(def.unitEvents), List(def.events)
    def.state = { id = def.id, slot = def.slot, kind = def.kind, key = nil, token = nil, label = nil, cur = 0, max = 0, ok = false, secret = false, pct = nil }
    providers[#providers + 1] = def
    byId[def.id] = def
    local list = bySlot[def.slot]
    list[#list + 1] = def
    return true
end

function CBR.Get(id) return byId[id] end
function CBR.Providers() return providers end

local function ForClass(p, class)
    return p.classes == nil or (class ~= nil and p.classes[class] == true)
end

-- The provider that supplies a slot right now: the first one registered whose class fits and that applies.
function CBR.Resolve(slot, c)
    c = c or ctx
    local list = bySlot[slot]
    if not list then return nil end
    for _, p in ipairs(list) do
        if ForClass(p, c.class) and p.Applies(c) then return p end
    end
    return nil
end

-- Reads a provider into its state (rewritten in place) and returns the state.
function CBR.Read(p, c)
    p.Read(p, c or ctx)
    return p.state
end

-- The events every provider that could apply to a class needs, as two sorted lists: unit events (for "player"
-- only) and global ones. Includes providers that are not active this minute (a Druid changes form), so a form
-- change does not need new registrations.
function CBR.EventsFor(class)
    local unit, global, seenU, seenG = {}, {}, {}, {}
    for _, p in ipairs(providers) do
        if ForClass(p, class) then
            for _, e in ipairs(p.unitEvents) do if not seenU[e] then seenU[e] = true; unit[#unit + 1] = e end end
            for _, e in ipairs(p.events) do if not seenG[e] then seenG[e] = true; global[#global + 1] = e end end
        end
    end
    table.sort(unit)
    table.sort(global)
    return unit, global
end

-- Whether any provider that could apply to this class supplies a slot (for settings: a page names only what exists).
function CBR.HasSlot(slot, class)
    for _, p in ipairs(bySlot[slot] or {}) do
        if ForClass(p, class) then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- What settings offers an override for, by class: the powers each class commonly runs on in Forever, listed so a
-- player can set one before meeting it, plus the combo points where a provider has them. Not a claim about what the
-- client reports (the primary bar always follows the client); the power in use right now is always added.
---------------------------------------------------------------------------
CBR.CLASS_POWERS = {
    WARRIOR = { "RAGE" }, PALADIN = { "MANA" }, HUNTER = { "MANA", "FOCUS" }, ROGUE = { "ENERGY" }, PRIEST = { "MANA" },
    SHAMAN = { "MANA" }, MAGE = { "MANA" }, WARLOCK = { "MANA" }, DRUID = { "MANA", "RAGE", "ENERGY" },
}

-- { { key, label, kind }, ... } for a class, in a steady order.
function CBR.Offered(class)
    local out, seen = {}, {}
    local function Add(key, kind)
        if key and not seen[key] then
            seen[key] = true
            out[#out + 1] = { key = key, label = CBR.Label(key), kind = kind }
        end
    end
    for _, key in ipairs(CBR.CLASS_POWERS[class] or {}) do Add(key, "continuous") end
    if ctx.class == class then Add(ctx.token, "continuous") end
    for _, p in ipairs(providers) do
        if p.kind == "segmented" and ForClass(p, class) and p.classes ~= nil then
            for _, key in ipairs(p.keys) do Add(key, "segmented") end
        end
    end
    return out
end

-- The stable name an override is saved under: the class token and the resource key, never a localized name.
function CBR.OverrideKey(class, key)
    if type(class) ~= "string" or type(key) ~= "string" then return nil end
    return class .. ":" .. key
end

---------------------------------------------------------------------------
-- The providers
---------------------------------------------------------------------------
local function Clamp(cur, max)
    if cur < 0 then return 0 end
    if cur > max then return max end
    return cur
end

local function Unavailable(s)
    s.ok, s.cur, s.max, s.secret, s.pct = false, 0, 0, false, nil
end

-- Reads a continuous power into a state. A plain current value is clamped; a restricted one (the maximum must still be
-- plain, or there is nothing to fill against) is kept as it came, flagged secret, and never looked at.
local function ReadContinuous(s, powerType)
    local raw = UnitPower("player", powerType)
    local max = PlainNumber(UnitPowerMax("player", powerType))
    if not max or max <= 0 then Unavailable(s) return end
    if issecretvalue and issecretvalue(raw) then
        s.cur, s.max, s.ok, s.secret = raw, max, true, true
        -- The percentage needs arithmetic we may not do, so the game does it: 0 to 100, itself restricted (text only).
        local curve = rawget(_G, "CurveConstants")
        s.pct = nil
        if UnitPowerPercent and curve and curve.ScaleTo100 then s.pct = UnitPowerPercent("player", powerType, false, curve.ScaleTo100) end   -- never tested for truth
        return
    end
    local cur = PlainNumber(raw)
    if not cur then Unavailable(s) return end
    s.cur, s.max, s.ok, s.secret, s.pct = Clamp(cur, max), max, true, false, nil
end

-- The power the client reports for the player.
CBR.Register({
    id = "power", slot = "primary", kind = "continuous",
    unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
    Applies = function(c) return c.powerType ~= nil and c.token ~= nil end,
    Read = function(p, c)
        local s = p.state
        s.key, s.token, s.label = c.token, c.token, c.token and CBR.Label(c.token) or nil
        if not c.powerType then Unavailable(s) return end
        ReadContinuous(s, c.powerType)
    end,
})

-- Combo points, on the target. Rogues; Druids while their power is energy (Cat Form).
CBR.Register({
    id = "combo", slot = "secondary", kind = "segmented", classes = { ROGUE = true, DRUID = true }, keys = { "COMBO_POINTS" },
    unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
    events = { "PLAYER_TARGET_CHANGED", "COMBO_TARGET_CHANGED" },
    Applies = function(c)
        if c.class == "ROGUE" then return true end
        return c.class == "DRUID" and c.powerType == POWER_ENERGY
    end,
    Read = function(p)
        local s = p.state
        s.key, s.token, s.label = "COMBO_POINTS", "COMBO_POINTS", CBR.Label("COMBO_POINTS")
        if not GetComboPoints then Unavailable(s) return end
        local max, cur = PlainNumber(UnitPowerMax("player", POWER_COMBO)), PlainNumber(GetComboPoints("player", "target"))
        if not max or max < 1 or not cur then Unavailable(s) return end
        if max > CBR.COMBO_CAP then max = CBR.COMBO_CAP end
        max = math.floor(max)
        s.cur, s.max, s.ok, s.secret = math.floor(Clamp(cur, max)), max, true, false
    end,
})

-- A Druid's mana while another power is shown (Cat, Bear).
CBR.Register({
    id = "druidMana", slot = "tertiary", kind = "continuous", classes = { DRUID = true },
    unitEvents = { "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" },
    Applies = function(c) return c.class == "DRUID" and c.powerType ~= nil and c.powerType ~= POWER_MANA end,
    Read = function(p)
        local s = p.state
        s.key, s.token, s.label = "MANA", "MANA", CBR.Label("MANA")
        ReadContinuous(s, POWER_MANA)
    end,
})
