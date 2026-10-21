-- TwichUI: Hazard alerts, the rules
-- What is registered, decided from plain values: the built-in definitions, the player's own rules, what is turned off.
-- No game calls and no frames; Alerts.lua turns the answer into aura sounds and Config.lua stores the choices.
--
-- A rule here is one aura event on the player: a spell ID and one of three triggers (applied, stacks grow, fades).
-- That is all the client lets an addon ask for (see Config.lua). It does not know damage, who caused it, or where the
-- player stands, so a rule says "this aura happened to me", never "this hit was avoidable".
--
-- Built-in definitions are data (HR.BUILTIN). Each carries the fields below. A definition is only shipped after its
-- spell ID has been confirmed on the Forever client by a person; the list is empty until then, on purpose:
--   id         stable internal name, never reused ("fire.example"); the player's "off" choices are kept by it
--   spell      the aura's spell ID on this client
--   name       what the player sees
--   trigger    "applied" | "stacks" | "removed"
--   category   "high" | "low" | "fail"
--   throttle   seconds the game waits between two plays (0 to 5)
--   why        one line: why this aura is a hazard
--   source     where the ID and the behavior were checked
--
-- Precedence, in one place: a player's rule that is switched on wins over a built-in rule with the same spell and
-- trigger (the player chose it), and only one sound is ever registered for a spell and trigger. A rule in a category
-- that is switched off or has no sound is not registered at all.

local R = TwichUI
local HZ = R.Hazard
local HR = {}
R.HazardRules = HR

HR.BUILTIN = {}

local ORDER = {}   -- ids of the loaded built-in rules, in the order given
local BY_ID = {}

local function Check(def)
    if type(def) ~= "table" then return nil, "shape" end
    if not HZ.ValidRuleId(def.id) then return nil, "id" end
    if not HZ.ValidSpell(def.spell) then return nil, "spell" end
    if type(def.name) ~= "string" or def.name == "" or def.name:find("[%c|]") then return nil, "name" end
    if not HZ.TRIGGER[def.trigger] then return nil, "trigger" end
    if not HZ.CATEGORY[def.category] then return nil, "category" end
    if type(def.throttle) ~= "number" or def.throttle < HZ.THROTTLE[1] or def.throttle > HZ.THROTTLE[2] or def.throttle % 1 ~= 0 then return nil, "throttle" end
    if type(def.why) ~= "string" or def.why == "" then return nil, "why" end
    if type(def.source) ~= "string" or def.source == "" then return nil, "source" end
    return def
end
HR.Check = Check

-- Replaces the built-in rules (at load with HR.BUILTIN; the tests give their own). A definition that fails is skipped
-- and counted; the rest still load. Returns how many loaded and how many were skipped.
function HR.Load(list)
    ORDER, BY_ID = {}, {}
    local skipped = 0
    for _, def in ipairs(list or {}) do
        if Check(def) and not BY_ID[def.id] then
            BY_ID[def.id] = def
            ORDER[#ORDER + 1] = def.id
        else
            skipped = skipped + 1
        end
    end
    return #ORDER, skipped
end

function HR.Builtin()
    local out = {}
    for i, id in ipairs(ORDER) do out[i] = BY_ID[id] end
    return out
end

function HR.BuiltinById(id) return BY_ID[id] end

local function Key(spell, trigger) return spell .. ":" .. trigger end
HR.Key = Key

-- The registrations to make: { { key, id, source = "builtin" | "custom", spell, trigger, category, throttle, name } }.
--   customRules  Config.List()'s rules
--   off          the built-in ids turned off
--   categoryOn   function(category) -> boolean
--   hasSound     function(category) -> boolean (a category set to "None" registers nothing)
function HR.Resolve(customRules, off, categoryOn, hasSound)
    local out, taken = {}, {}
    local function Live(category) return categoryOn(category) and hasSound(category) end
    -- the player's rules first, so they win a shared spell and trigger
    for _, rule in ipairs(customRules or {}) do
        if rule.enabled and Live(rule.category) then
            local key = Key(rule.spell, rule.trigger)
            if not taken[key] then
                taken[key] = true
                out[#out + 1] = { key = key, id = rule.id, source = "custom", spell = rule.spell, trigger = rule.trigger,
                    category = rule.category, throttle = rule.throttle, name = rule.name }
            end
        end
    end
    for _, id in ipairs(ORDER) do
        local def = BY_ID[id]
        if not (off and off[id]) and Live(def.category) then
            local key = Key(def.spell, def.trigger)
            if not taken[key] then
                taken[key] = true
                out[#out + 1] = { key = key, id = def.id, source = "builtin", spell = def.spell, trigger = def.trigger,
                    category = def.category, throttle = def.throttle, name = def.name }
            end
        end
    end
    return out
end

-- Which built-in rule a custom rule would stand in for, if any (for the editor's note).
function HR.Shadows(spell, trigger)
    for _, id in ipairs(ORDER) do
        local def = BY_ID[id]
        if def.spell == spell and def.trigger == trigger then return def end
    end
    return nil
end

HR.Load(HR.BUILTIN)
