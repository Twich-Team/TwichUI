-- TwichUI: Ammunition warning, deciding what is wrong
-- Pure: it reads a table of plain facts (Warning.lua fills it from the game) and answers with one state. It touches
-- no frame, no event and no game API, so the tests run the same code the game does.
--
-- What the client gives us (all of it read from the Forever UI source; docs/ammo-warning.md has the references):
--   * UnitUsesAmmo("player") says whether the character's ranged weapon takes ammunition. The character sheet uses it
--     to show or hide the ammo slot, so it is the client's own word and no table of weapons is consulted for "needs
--     ammunition". A ranged weapon that does not take it (a wand, a thrown weapon) is "inactive".
--   * The ammunition is a slot of its own (INVSLOT_AMMO, 0). GetInventoryItemID gives what is selected and
--     GetInventoryItemCount the count the character sheet prints on that slot, which covers every carried stack of that
--     item (a second stack in another bag is not added to it again).
--   * An empty slot is all the client shows when the ammunition runs out: there is no separate "depleted" slot state.
--     So "nothing is selected" is split by what the bags hold: compatible ammunition that could be selected is
--     NO AMMO EQUIPPED, and none at all is OUT OF AMMO. A selected item with a count of zero is OUT OF AMMO too.
--
-- States:
--   inactive   no ranged weapon, or the client says it takes no ammunition. Nothing is shown.
--   unknown    the data needed to decide is not there (yet). Nothing is concluded; the controller keeps what it shows
--              and looks again shortly.
--   ok         compatible ammunition is selected and some is left. Nothing is shown.
--   noAmmo     NO AMMO EQUIPPED   nothing is selected, but compatible ammunition is carried
--   outOfAmmo  OUT OF AMMO        nothing is selected and no compatible ammunition is carried, or the count is zero
--   wrong      WRONG AMMO EQUIPPED  what is selected is arrows for a gun or bullets for a bow, both known for certain
-- "Compatible" is judged only when the weapon's type is known (a Bow or Crossbow takes arrows, a Gun bullets). When it
-- is not, any recognized ammunition counts and "wrong" is never concluded.

local R = TwichUI
local AS = {}
R.AmmoState = AS

AS.MESSAGES = {
    noAmmo = "NO AMMO EQUIPPED",
    outOfAmmo = "OUT OF AMMO",
    wrong = "WRONG AMMO EQUIPPED",
}
-- A short line under the warning in the RPG Notification style: only what the state itself establishes. NO AMMO
-- EQUIPPED means compatible ammunition is carried (so it says so); OUT OF AMMO is not tied to the bags because a selected
-- stack that is empty gets it too.
AS.DETAIL = {
    noAmmo = "Ammunition that fits is in your bags.",
    outOfAmmo = "No usable ammunition left.",
    wrong = "It does not match your ranged weapon.",
}
AS.ORDER = { "noAmmo", "outOfAmmo", "wrong" }   -- the order the preview shows them in

function AS.IsProblem(state) return AS.MESSAGES[state] ~= nil end

-- Which ammunition a ranged weapon takes, from its item class and subclass: "arrow" for a Bow or Crossbow, "bullet"
-- for a Gun, nil for anything else (unknown is not a reason to call ammunition wrong). The enumerations are the
-- Forever API documentation's (ItemConstantsDocumentation.lua: Weapon 2; Bows 2, Guns 3, Crossbow 18).
function AS.NeedsFor(classID, subClassID)
    local items = Enum and Enum.ItemClass
    local weapons = Enum and Enum.ItemWeaponSubclass
    local weaponClass = items and items.Weapon or 2
    local bows, guns, crossbow = weapons and weapons.Bows or 2, weapons and weapons.Guns or 3, weapons and weapons.Crossbow or 18
    if classID ~= weaponClass then return nil end
    if subClassID == bows or subClassID == crossbow then return "arrow" end
    if subClassID == guns then return "bullet" end
    return nil
end

-- Whether a state is shown under a policy ("equipped": always while it is a problem; "combat": only in combat).
function AS.Visible(state, policy, inCombat)
    if not AS.IsProblem(state) then return false end
    if policy == "combat" then return inCombat == true end
    return true
end

-- input:  { usesAmmo = true|false|nil, hasRanged = bool, needs = "arrow"|"bullet"|nil,
--           equippedId = number|nil, equippedKind = "arrow"|"bullet"|"other"|nil, equippedCount = number|nil,
--           carries = function(needs) -> found (true|false|nil), itemID }
-- carries is called only when nothing is selected, so the bags are read only when they matter. found == nil means
-- the bags could not be read.
-- out (optional, reused): receives .state and .iconItem (an item ID to draw the icon of, when there is one).
-- Returns out.
function AS.Evaluate(input, out)
    out = out or {}
    out.state, out.iconItem = "unknown", nil
    if input.usesAmmo == nil then return out end
    if input.usesAmmo == false then out.state = "inactive" return out end
    if not input.hasRanged then return out end   -- the client says ammunition is used but shows no weapon: not settled

    if input.equippedId == nil then
        local found, itemID = input.carries(input.needs)
        if found == nil then return out end
        out.state = found and "noAmmo" or "outOfAmmo"
        out.iconItem = found and itemID or nil
        return out
    end

    local count = input.equippedCount
    out.iconItem = input.equippedId
    if count == nil then return out end
    if count <= 0 then out.state = "outOfAmmo" return out end
    local kind = input.equippedKind
    if input.needs and (kind == "arrow" or kind == "bullet") and kind ~= input.needs then
        out.state = "wrong"
        return out
    end
    out.state = "ok"
    return out
end
