dofile(TESTS .. "harness.lua")
-- H.Judge and H.Noteworthy, the judgement layer of the upgrade hints:
-- memoization, invalidation, the nil/false cases, and what counts as
-- noteworthy at a glance. Offline only: real item data still needs checking
-- in game.
local c = MakeClient("Rich", {"!!!TwichUI"})

-- Game strings the labels use.
c.ITEM_MOD_STRENGTH_SHORT = "Strength"
c.ITEM_MOD_AGILITY_SHORT = "Agility"
c.ITEM_MOD_STAMINA_SHORT = "Stamina"
c.ITEM_MOD_INTELLECT_SHORT = "Intellect"
c.RESISTANCE0_NAME = "Armor"

-- name, quality, equip slot, stats, required level
local ITEMS = {
  ["chest:old"]    = { "Old Chest", 2, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 300 } },
  ["chest:better"] = { "Better Chest", 3, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 10, RESISTANCE0_NAME = 320 } },
  ["chest:slight"] = { "Slightly Better Chest", 2, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 11, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 300 } },
  ["chest:caster"] = { "Robe", 3, "INVTYPE_ROBE", { ITEM_MOD_INTELLECT_SHORT = 12, RESISTANCE0_NAME = 100 } },
  ["head:new"]     = { "Helm", 2, "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 10 } },
  ["ring:str"]     = { "Strong Ring", 2, "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 5 } },
  ["ring:agi"]     = { "Quick Ring", 2, "INVTYPE_FINGER", { ITEM_MOD_AGILITY_SHORT = 5 } },
  ["mh:axe"]       = { "Axe", 2, "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20, ITEM_MOD_STRENGTH_SHORT = 5 } },
  ["oh:sword"]     = { "Sword", 2, "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 } },
}
local EQUIPPED = { [5] = "chest:old", [11] = "ring:str", [12] = "ring:agi", [16] = "mh:axe", [17] = "oh:sword" }
local SPENT = { 5, 21, 0 }
local TREES = {
  { groupID = 1, displayName = "Arms", skillLineID = 26, orderIndex = 0 },
  { groupID = 2, displayName = "Fury", skillLineID = 256, orderIndex = 1 },
  { groupID = 3, displayName = "Protection", skillLineID = 257, orderIndex = 2 },
}
local RED = { r = 1, g = 0.125, b = 0.125 }
local CLASS = { "Warrior", "WARRIOR" }

c.C_Item = {
  GetItemInfo = function(link) local i = ITEMS[link]; if i then return i[1], link, i[2], 50, i[5] or 1, "Armor", "Misc", 1, i[3] end end,
  GetItemStats = function(link) return ITEMS[link] and ITEMS[link][4] end,
}
c.GetInventoryItemLink = function(_, slot) return EQUIPPED[slot] end
c.UnitClass = function() return CLASS[1], CLASS[2] end
c.UnitLevel = function() return 40 end
c.CanDualWield = function() return true end
c.GetCombatRatingBonusForCombatRatingValue = function(_, value) return value / 10 end
c.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetCombatConfigIDForSpecGroup = function() return 99 end }
c.C_Traits = {
  GetConfigInfo = function(id) assert(id == 99); return { treeIDs = { 500 } } end,
  GetGroupDisplayInfoByTreeID = function(id) assert(id == 500); return TREES end,
  GetGroupCurrencyInfo = function(_, ids)
    local out = {}
    for _, id in ipairs(ids) do out[#out + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = SPENT[id] } } } end
    return out
  end,
}
c.Enum = { TooltipDataType = { Item = 0 } }

for _, f in ipairs({ "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
  "gear/Hints.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local H, P = R.GearHints, R.GearPrefs
local function Changed(event) c.FireEvent(event) end

-- The game hasn't loaded the item yet: nil, and not kept, so it's re-checked
-- on the next call.
assert(H.Judge("unknown:item") == nil, "item the game lacks: nil")
-- The equipped slot's item isn't known to the game either: nil.
EQUIPPED[5] = "chest:unknown"
assert(H.Judge("chest:better") == nil, "equipped item the game lacks: nil")
EQUIPPED[5] = "chest:old"
Changed("PLAYER_EQUIPMENT_CHANGED")

-- A red requirement line (not just level) means it can't be compared: false.
local redLine = { leftText = "Requires a profession", rightColor = RED }
assert(H.Judge("chest:better", { redLine }) == false, "can't be compared: false")

-- Judgements are kept: the same table comes back until something invalidates.
local slight = H.Judge("chest:slight")
assert(slight and slight.result and slight.result.verdict == "possible", "slight gain: possible")
local before = ITEMS["chest:slight"][4]
ITEMS["chest:slight"][4] = { ITEM_MOD_STRENGTH_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 10, RESISTANCE0_NAME = 320 }
assert(H.Judge("chest:slight") == slight, "no invalidating event: judgement kept")
assert(H.Noteworthy(H.Judge("chest:slight")) == H.Noteworthy(slight), "kept: same at a glance")
ITEMS["chest:slight"][4] = before

-- PLAYER_EQUIPMENT_CHANGED re-evaluates with the new gear.
EQUIPPED[5] = "chest:better"
Changed("PLAYER_EQUIPMENT_CHANGED")
local now = H.Judge("chest:better")
assert(now == false, "wearing it now: no hint")
EQUIPPED[5] = "chest:old"
Changed("PLAYER_EQUIPMENT_CHANGED")
assert(H.Judge("chest:better") ~= now, "re-evaluated after equipment change")

-- SKILL_LINES_CHANGED re-evaluates with the new talent points.
SPENT = { 21, 5, 0 }
Changed("SKILL_LINES_CHANGED")
local arms = H.Judge("chest:slight")
assert(arms ~= slight, "re-evaluated after skill line change")
assert(arms.who.basis.label == "Arms", "weighed for the new leading tree")
SPENT = { 5, 21, 0 }
Changed("SKILL_LINES_CHANGED")

-- Changing an option re-evaluates too (P.Set fires the hints' listener).
P.Set("strictness", "eager")
local eager = H.Judge("chest:slight")
assert(eager ~= arms and eager.result.verdict == "likely", "re-evaluated with the new option")
P.Set("strictness", "balanced")

-- Noteworthy: what gets a glance line and a bag icon.
assert(H.Noteworthy(H.Judge("chest:better")) == true, "likely: noteworthy")
assert(H.Noteworthy(H.Judge("head:new")) == true, "empty: noteworthy")
assert(H.Noteworthy(H.Judge("chest:slight")) == true, "possible with the option on: noteworthy")
P.Set("glancePossible", false)
assert(H.Noteworthy(H.Judge("chest:slight")) == false, "possible with the option off: not noteworthy")
P.Set("glancePossible", true)
assert(H.Noteworthy(H.Judge("chest:caster")) == false, "not an upgrade: not noteworthy")
assert(H.Noteworthy(false) == false, "false judgement: not noteworthy")
assert(H.Noteworthy(nil) == false, "nil judgement: not noteworthy")

print("TEST_GEAR_HINTS PASSED")
