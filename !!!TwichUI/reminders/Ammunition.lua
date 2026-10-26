-- TwichUI: Reminders, the ammunition condition
-- A condition kind (Conditions.lua says what a provider is) about the ammunition for the equipped ranged weapon, and
-- the judgement behind it. Pure: it reads a table of plain facts (State.lua's "ammo" source fills it from the game)
-- and answers with one state. It touches no frame, no event and no game API, so the tests run the same code the game
-- does.
--
-- What the client gives us (read from the Forever UI source; docs/reminders.md has the references):
--   * UnitUsesAmmo("player") says whether the character's ranged weapon takes ammunition. The character sheet uses it
--     to show or hide the ammo slot, so it is the client's own word and no table of weapons is consulted for "needs
--     ammunition". A ranged weapon that does not take it (a wand, a thrown weapon) is "inactive".
--   * The ammunition is a slot of its own (INVSLOT_AMMO, 0). GetInventoryItemID gives what is selected and
--     GetInventoryItemCount the count the character sheet prints on that slot, which covers every carried stack of that
--     item (a second stack in another bag is not added to it again).
--   * An empty slot is all the client shows when the ammunition runs out: there is no separate "depleted" slot state.
--     So "nothing is selected" is split by what the bags hold: compatible ammunition that could be selected is
--     noAmmo, and none at all is outOfAmmo. A selected item with a count of zero is outOfAmmo too.
--
-- The facts (obs.ammo): { uses = true|false|nil, ranged = bool, needs = "arrow"|"bullet"|nil, id = item|nil,
--   kind = "arrow"|"bullet"|"other"|nil (what the selected item is), count = n|nil, carries = true|false|nil }.
--   carries is read only when nothing is selected: whether the bags hold ammunition the weapon can use.
--
-- States:
--   inactive   no ranged weapon, or the client says it takes no ammunition. Never a match.
--   unknown    the data needed to decide is not there (yet). Nothing is concluded.
--   ok         compatible ammunition is selected and some is left.
--   noAmmo     nothing is selected, but compatible ammunition is carried
--   outOfAmmo  nothing is selected and no compatible ammunition is carried, or the count is zero
--   wrong      what is selected is arrows for a gun or bullets for a bow, both known for certain
-- "Compatible" is judged only when the weapon's type is known (a Bow or Crossbow takes arrows, a Gun bullets). When it
-- is not, any recognized ammunition counts and "wrong" is never concluded.

local R = TwichUI
local C = R.ReminderConditions
local A = {}
R.ReminderAmmo = A

local MATCH, NOMATCH, UNKNOWN = C.MATCH, C.NOMATCH, C.UNKNOWN

A.AMMO_SLOT = rawget(_G, "INVSLOT_AMMO") or 0
A.RANGED_SLOT = rawget(_G, "INVSLOT_RANGED") or 18

-- Which ammunition a ranged weapon takes, from its item class and subclass: "arrow" for a Bow or Crossbow, "bullet"
-- for a Gun, nil for anything else (unknown is not a reason to call ammunition wrong). The enumerations are the
-- Forever API documentation's (ItemConstantsDocumentation.lua: Weapon 2; Bows 2, Guns 3, Crossbow 18).
function A.NeedsFor(classID, subClassID)
    local items = Enum and Enum.ItemClass
    local weapons = Enum and Enum.ItemWeaponSubclass
    local weaponClass = items and items.Weapon or 2
    local bows, guns, crossbow = weapons and weapons.Bows or 2, weapons and weapons.Guns or 3, weapons and weapons.Crossbow or 18
    if classID ~= weaponClass then return nil end
    if subClassID == bows or subClassID == crossbow then return "arrow" end
    if subClassID == guns then return "bullet" end
    return nil
end

-- The state of a table of facts, and for "unknown" a short reason. A nil table is unknown.
function A.Judge(f)
    if f == nil or f.uses == nil then
        return "unknown", f and "The game hasn't said whether your ranged weapon takes ammunition yet." or "The game hasn't said yet."
    end
    if f.uses == false then return "inactive" end
    if not f.ranged then return "unknown", "The game says your weapon takes ammunition, but hasn't shown the weapon yet." end
    if f.id == nil then
        if f.carries == nil then return "unknown", "Your bags couldn't be read yet." end
        return f.carries and "noAmmo" or "outOfAmmo"
    end
    if f.count == nil then return "unknown", "The game hasn't given the ammunition count yet." end
    if f.count <= 0 then return "outOfAmmo" end
    if f.needs and (f.kind == "arrow" or f.kind == "bullet") and f.kind ~= f.needs then return "wrong" end
    return "ok"
end

-- key (stored), what the editor's value choice says after "Ranged ammunition", the sentence's words, a tooltip
A.CHOICES = {
    { "problem", "has a problem", "has a problem",
        "Any of the three below: none selected, none left, or the wrong kind." },
    { "noAmmo", "is not equipped", "is not equipped, though some is carried",
        "Nothing is selected in the ammunition slot, but ammunition your weapon can use is in your bags." },
    { "outOfAmmo", "is used up", "is used up",
        "Nothing is selected and none your weapon can use is carried, or the selected stack is empty. The game shows an empty slot for both, so this is judged from your bags." },
    { "wrong", "is the wrong kind", "is the wrong kind for the weapon",
        "Arrows are selected for a gun, or bullets for a bow. Judged only when the game says what kind of weapon it is." },
}
local CHOICE = {}
for _, c in ipairs(A.CHOICES) do CHOICE[c[1]] = c end
function A.Choice(key) return CHOICE[key] end

-- Whether this client can say if the weapon takes ammunition at all.
function A.Supported() return rawget(_G, "UnitUsesAmmo") ~= nil end

local PROBLEM = { noAmmo = true, outOfAmmo = true, wrong = true }

C.Register({
    type = "ammunition", label = "Ranged ammunition",
    New = function() return { type = "ammunition", what = "problem" } end,

    Check = function(raw)
        if not CHOICE[raw.what] then return nil, "it looks at something about ammunition this version of TwichUI doesn't know." end
        local clean = { type = "ammunition", what = raw.what }
        if not A.Supported() then return clean, "this game client doesn't say whether your ranged weapon takes ammunition." end
        return clean
    end,

    Needs = function(_, add) add("ammo") end,

    Evaluate = function(cond, obs)
        local state, reason = A.Judge(obs and obs.ammo)
        if state == "unknown" then return UNKNOWN, reason end
        if cond.what == "problem" then return PROBLEM[state] and MATCH or NOMATCH end
        return state == cond.what and MATCH or NOMATCH
    end,

    Summary = function(cond)
        local c = CHOICE[cond.what]
        return "Ranged ammunition " .. (c and c[3] or tostring(cond.what))
    end,

    Observed = function(_, obs)
        local state = A.Judge(obs and obs.ammo)
        return ({
            unknown = "Not read yet",
            inactive = "Your ranged weapon takes no ammunition",
            ok = "Ammunition selected and some left",
            noAmmo = "Nothing selected, some carried",
            outOfAmmo = "Used up",
            wrong = "The wrong kind is selected",
        })[state] or "Not read yet"
    end,

    -- The situations worth trying: each state, the weapon that takes none, and nothing read. The one this condition
    -- looks for comes first (the Test section starts on the first).
    Scenarios = function(cond)
        local base = { uses = true, ranged = true, needs = "arrow" }
        local function Facts(extra)
            local f = {}
            for k, v in pairs(base) do f[k] = v end
            for k, v in pairs(extra) do f[k] = v end
            return f
        end
        local all = {
            outOfAmmo = { "Nothing selected and none carried", Facts({ carries = false }) },
            noAmmo = { "Nothing selected, ammunition in the bags", Facts({ carries = true }) },
            wrong = { "Bullets selected for a bow", Facts({ id = 0, kind = "bullet", count = 100 }) },
            ok = { "Arrows selected for a bow, plenty left", Facts({ id = 0, kind = "arrow", count = 100 }) },
            inactive = { "A ranged weapon that takes no ammunition", { uses = false, ranged = true } },
        }
        local order = { "outOfAmmo", "noAmmo", "wrong", "ok", "inactive" }
        if cond.what ~= "problem" then
            for i, k in ipairs(order) do
                if k == cond.what then table.remove(order, i) break end
            end
            table.insert(order, 1, cond.what)
        end
        local list = {}
        for _, key in ipairs(order) do
            local label, facts = all[key][1], all[key][2]
            list[#list + 1] = { key = key, label = label, Apply = function(obs)
                local copy = {}
                for k, v in pairs(facts) do copy[k] = v end
                obs.ammo = copy
            end }
        end
        list[#list + 1] = { key = "unread", label = "Not read yet", Apply = function(obs) obs.ammo = nil end }
        return list
    end,
})
