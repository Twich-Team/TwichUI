dofile(TESTS .. "harness.lua")
-- Upgrade hints: comparisons, wording, options and bag icons, against a
-- stubbed level 40 Fury warrior. Offline only: real item stat keys, tooltip
-- data, talent data and bag frames still need checking in game.
local c = MakeClient("Rich", {"!!!TwichUI"})

-- Game strings the labels use.
c.ITEM_MOD_STRENGTH_SHORT = "Strength"
c.ITEM_MOD_AGILITY_SHORT = "Agility"
c.ITEM_MOD_STAMINA_SHORT = "Stamina"
c.ITEM_MOD_INTELLECT_SHORT = "Intellect"
c.ITEM_MOD_HIT_RATING_SHORT = "Hit Rating"
c.ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "Damage Per Second"
c.RESISTANCE0_NAME = "Armor"
c.RESISTANCE2_NAME = "Fire Resistance"

-- name, quality, equip slot, stats, required level
local ITEMS = {
  ["chest:old"]    = { "Old Chest", 2, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 300 } },
  ["chest:better"] = { "Better Chest", 3, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 14, ITEM_MOD_STAMINA_SHORT = 10, RESISTANCE0_NAME = 320 } },
  ["chest:slight"] = { "Slightly Better Chest", 2, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 11, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 300 } },
  ["chest:caster"] = { "Robe", 3, "INVTYPE_ROBE", { ITEM_MOD_INTELLECT_SHORT = 12, RESISTANCE0_NAME = 100 } },
  ["chest:hit"]    = { "Hit Chest", 3, "INVTYPE_CHEST", { ITEM_MOD_HIT_RATING_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 300 } },
  ["chest:fire"]   = { "Fire Chest", 2, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 14, RESISTANCE0_NAME = 300, RESISTANCE2_NAME = 10 } },
  ["chest:use"]    = { "Use Chest", 3, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 300 } },
  ["chest:future"] = { "Future Chest", 3, "INVTYPE_CHEST", { ITEM_MOD_STRENGTH_SHORT = 20, ITEM_MOD_STAMINA_SHORT = 12, RESISTANCE0_NAME = 400 }, 50 },
  ["ring:str"]     = { "Strong Ring", 2, "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 5 } },
  ["ring:agi"]     = { "Quick Ring", 2, "INVTYPE_FINGER", { ITEM_MOD_AGILITY_SHORT = 5 } },
  ["ring:new"]     = { "New Ring", 2, "INVTYPE_FINGER", { ITEM_MOD_STRENGTH_SHORT = 2, ITEM_MOD_STAMINA_SHORT = 8 } },
  ["mh:axe"]       = { "Axe", 2, "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 20, ITEM_MOD_STRENGTH_SHORT = 5 } },
  ["oh:sword"]     = { "Sword", 2, "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 15 } },
  ["2h:big"]       = { "Greataxe", 3, "INVTYPE_2HWEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 40, ITEM_MOD_STRENGTH_SHORT = 10 } },
  ["oh:shield"]    = { "Shield", 2, "INVTYPE_SHIELD", { RESISTANCE0_NAME = 900, ITEM_MOD_STAMINA_SHORT = 5 } },
  ["head:new"]     = { "Helm", 2, "INVTYPE_HEAD", { ITEM_MOD_STAMINA_SHORT = 10 } },
  ["shirt"]        = { "Shirt", 1, "INVTYPE_BODY", {} },
}
local EQUIPPED = { [5] = "chest:old", [11] = "ring:str", [12] = "ring:agi", [16] = "mh:axe", [17] = "oh:sword" }
local SPENT = { 5, 21, 0 }
local TREES = {
  { groupID = 1, displayName = "Arms", skillLineID = 26, orderIndex = 0 },
  { groupID = 2, displayName = "Fury", skillLineID = 256, orderIndex = 1 },
  { groupID = 3, displayName = "Protection", skillLineID = 257, orderIndex = 2 },
}
local RED = { r = 1, g = 0.125, b = 0.125 }
local LEVEL_LOCK = { { leftText = "Requires Level 50", leftColor = RED } }
local CLASS = { "Warrior", "WARRIOR" }
local modifier, alt = false, false
local postCall

c.C_Item = {
  GetItemInfo = function(link) local i = ITEMS[link]; if i then return i[1], link, i[2], 50, i[5] or 1, "Armor", "Misc", 1, i[3] end end,
  GetItemStats = function(link) return ITEMS[link] and ITEMS[link][4] end,
}
c.GetInventoryItemLink = function(_, slot) return EQUIPPED[slot] end
c.UnitClass = function() return CLASS[1], CLASS[2] end
c.UnitLevel = function() return 40 end
c.CanDualWield = function() return true end
c.IsModifiedClick = function(what) assert(what == "COMPAREITEMS"); return modifier end
c.IsAltKeyDown = function() return alt end
c.IsControlKeyDown = function() return false end
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
c.Enum = { TooltipDataType = { Item = 0 }, TooltipDataLineType = { ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnProc = 46 } }
c.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) assert(kind == 0); postCall = fn end }
c.ITEM_QUALITY_COLORS = { [2] = { hex = "|cff1eff00" }, [3] = { hex = "|cff0070dd" } }

-- Bags: one container frame with four slots.
local BAG = { [1] = "chest:better", [2] = "chest:caster", [3] = "chest:future", [4] = "chest:slight" }
local BAG_LINES = { [3] = LEVEL_LOCK }
c.C_Container = { GetContainerItemLink = function(bag, slot) assert(bag == 0); return BAG[slot] end }
c.C_TooltipInfo = {
  GetInventoryItem = function() return { lines = {} } end,
  GetBagItem = function(_, slot) return { lines = BAG_LINES[slot] or {} } end,
}
local function Texture()
  local t = { shown = false, alpha = 1 }
  for _, m in ipairs({ "SetPoint", "SetAtlas", "SetTexture", "SetTexCoord", "SetSize", "SetDesaturated", "SetVertexColor" }) do t[m] = function() end end
  function t:Show() self.shown = true end
  function t:Hide() self.shown = false end
  function t:SetAlpha(a) self.alpha = a end
  return t
end
local buttons = {}
for slot = 1, 4 do
  buttons[slot] = { GetBagID = function() return 0 end, GetID = function() return slot end, CreateTexture = function() return Texture() end }
end
local bagFrame = { shown = true }
function bagFrame:IsShown() return self.shown end
function bagFrame:EnumerateValidItems() local i = 0; return function() i = i + 1; if buttons[i] then return i, buttons[i] end end end
function bagFrame:UpdateItems() end
c.ContainerFrameContainer = { ContainerFrames = { bagFrame } }
c.hooksecurefunc = function(t, key, fn) local orig = t[key]; t[key] = function(...) orig(...); return fn(...) end end

-- EllesmereUI Bags: only its overlay registration API, as a stand-in.
local ellePainters, elleRefreshes = {}, 0
c.EUI_Bags = {
  RegisterItemOverlayIcon = function(name, fn) ellePainters[name] = fn end,
  IsVisible = function() return true end,
  RefreshInventory = function() elleRefreshes = elleRefreshes + 1 end,
}

for _, f in ipairs({ "gear/Weights.lua", "gear/Evaluate.lua", "gear/Prefs.lua", "gear/Data.lua",
  "gear/Hints.lua", "gear/Tooltip.lua", "gear/Bags.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local P = R.GearPrefs
assert(postCall, "item tooltip post-call registered")
assert(c.TwichUIDB.modules.gearHints == true and c.TwichUIDB.modules.gearBagIcons == false, "defaults: hints on, bag icons off")
assert(P.Get("reveal") == "compare" and P.Get("glancePossible") == true and P.Get("futureLevels") == true, "behaviour defaults")

local function Hover(link, lines)
  local tip = { out = {} }
  function tip:AddLine(text) self.out[#self.out + 1] = text end
  function tip:IsForbidden() return false end
  function tip:GetName() return nil end
  postCall(tip, { type = 0, hyperlink = link, lines = lines or {} })
  return tip.out
end
local function Has(out, text)
  for _, line in ipairs(out) do if line:find(text, 1, true) then return true end end
  return false
end
local function Changed(event) c.FireEvent(event) end

-- The glance line: one line, only for upgrades.
local out = Hover("chest:better")
assert(#out == 1 and out[1] == "Likely upgrade for Fury", "glance line: " .. table.concat(out, " | "))
assert(#Hover("chest:caster") == 0, "not an upgrade: nothing by default")
assert(#Hover("chest:old") == 0, "the chest you wear: nothing")
assert(#Hover("shirt") == 0, "shirts aren't compared")
assert(#Hover("unknown:item") == 0, "items the game hasn't loaded: nothing yet")

-- Holding the compare key shows the reasoning.
modifier = true
out = Hover("chest:better")
assert(out[1] == " " and out[2] == "Likely upgrade for Fury", "reasoning follows a spacer")
assert(Has(out, "Compared with |cff1eff00Old Chest|r"), "names what it replaces")
assert(out[4] == "+4 Strength", "biggest change first: " .. tostring(out[4]))
assert(Has(out, "+2 Stamina") and Has(out, "+20 Armor"), "other changes listed")
assert(Has(out, "Rough estimate, weighed for Fury"), "says which weights")
out = Hover("chest:caster")
assert(Has(out, "Probably not an upgrade") and Has(out, "-10 Strength"), "explains a downgrade on request")
assert(Has(out, "Not weighed for Fury: Intellect") and not Has(out, "Not weighed for Fury: Armor"), "says which stats it ignored")

-- Can't use it (red requirement text other than level): nothing, even on request.
Changed("SKILL_LINES_CHANGED")
assert(#Hover("chest:better", { { leftText = "Chest", rightText = "Plate", rightColor = RED } }) == 0, "unusable: nothing")
Changed("SKILL_LINES_CHANGED")

-- Gear for a higher level: compared, with the level.
out = Hover("chest:future", LEVEL_LOCK)
assert(out[2] == "Likely upgrade for Fury at level 50" and Has(out, "You can wear it from level 50"), "level-locked gear: " .. tostring(out[2]))
Changed("SKILL_LINES_CHANGED")
assert(#Hover("chest:future", { LEVEL_LOCK[1], { rightText = "Plate", rightColor = RED } }) == 0, "level plus another requirement: nothing")
P.Set("futureLevels", false)
assert(#Hover("chest:future", LEVEL_LOCK) == 0, "higher-level gear off: nothing")
P.Set("futureLevels", true)

-- Use/proc effects aren't weighed, so a big gain is only "possible".
out = Hover("chest:use", { { type = 44, leftText = "Use: something" } })
assert(Has(out, "Possible upgrade for Fury") and Has(out, "Use and chance-on-hit effects aren't weighed"), "effects cap confidence")

-- Stats we don't weigh are named.
assert(Has(Hover("chest:fire"), "Not counted: Fire Resistance"), "unweighed stats named")

-- Rings: compared with the one it improves on most (the weaker one).
out = Hover("ring:new")
assert(Has(out, "Likely upgrade") and Has(out, "Compared with |cff1eff00Quick Ring|r"), "ring vs weaker ring")

-- A two-hander replaces both hands.
out = Hover("2h:big")
assert(Has(out, "Likely upgrade") and Has(out, "Compared with |cff1eff00Axe|r and |cff1eff00Sword|r"), "2H vs main and off hand")
assert(Has(out, "Damage Per Second"), "weapon DPS counted")

-- Empty slot.
assert(Has(Hover("head:new"), "Fills an empty slot"), "empty slot")

-- Rating stats use the game's conversion; without it they're not counted.
assert(Has(Hover("chest:hit"), "+20 Hit Rating"), "hit rating weighed with conversion")
c.GetCombatRatingBonusForCombatRatingValue = nil
Changed("PLAYER_LEVEL_UP")
out = Hover("chest:hit")
assert(Has(out, "Not counted: Hit Rating") and not Has(out, "+20 Hit Rating"), "no conversion: not counted")
c.GetCombatRatingBonusForCombatRatingValue = function(_, value) return value / 10 end
Changed("PLAYER_LEVEL_UP")

-- How big a gain counts (Slightly Better Chest is about 7% better).
assert(Has(Hover("chest:slight"), "Possible upgrade for Fury"), "balanced: 7% is possible")
P.Set("strictness", "eager")
assert(Has(Hover("chest:slight"), "Likely upgrade for Fury"), "eager: 7% is likely")
P.Set("strictness", "cautious")
assert(Has(Hover("chest:slight"), "Possible upgrade for Fury"), "cautious: 7% is still possible")
P.Set("strictness", "balanced")
modifier = false
P.Set("glancePossible", false)
assert(#Hover("chest:slight") == 0, "possible upgrades can be left out at a glance")
P.Set("glancePossible", true)
assert(Hover("chest:slight")[1] == "Possible upgrade for Fury", "possible upgrades at a glance by default")

-- The reveal key can be Alt, or always.
P.Set("reveal", "alt")
modifier = true
assert(#Hover("chest:caster") == 0, "Shift no longer reveals once Alt is chosen")
alt = true
assert(Has(Hover("chest:caster"), "Probably not an upgrade"), "Alt reveals")
alt, modifier = false, false
P.Set("reveal", "always")
assert(Has(Hover("chest:caster"), "Probably not an upgrade"), "always shows the reasoning")
P.Set("reveal", "compare")

-- Choosing a tree overrides the talent points, per character.
modifier = true
P.SetTreeChoice(257)
out = Hover("chest:better")
assert(Has(out, "Likely upgrade for Protection") and Has(out, "weighed for Protection (your choice)"), "chosen tree")
assert(out[4] == "+2 Stamina", "chosen tree's weights: " .. tostring(out[4]))
assert(next(c.TwichUIDB.gear.trees) == "Rich-Forever", "choice saved per character")
P.SetTreeChoice(nil)
assert(Has(Hover("chest:better"), "weighed for Fury"), "back to automatic")

-- Your own stat weights.
P.SetWeight("WARRIOR", 256, "INT", 2)
out = Hover("chest:caster")
assert(Has(out, "Likely upgrade for Fury") and Has(out, "+12 Intellect"), "custom weight counts: " .. tostring(out[2]))
assert(c.TwichUIDB.gear.weights.WARRIOR[256].INT == 2, "custom weight saved")
P.ResetWeights("WARRIOR", 256)
assert(c.TwichUIDB.gear.weights.WARRIOR == nil, "reset leaves nothing behind")
assert(Has(Hover("chest:caster"), "Probably not an upgrade"), "defaults back")
modifier = false

-- Stat priority instead of weights: ranked stats, each 80% of the one above,
-- scaled by what a point costs on an item; unranked stats count nothing.
local W = R.GearWeights
local fromList = W.FromPriority({ "STR", "AP", "HIT", "STR" }, W.CLASSES.WARRIOR.trees[2].weights)
assert(fromList.STR == 1 and math.abs(fromList.AP - 0.4) < 1e-9 and math.abs(fromList.HIT - 0.64) < 1e-9, "ranks to weights")
assert(fromList.AGI == nil and fromList.STA == nil, "unranked stats count nothing")
assert(fromList.MAINHAND_DPS == 7 and fromList.ARMOR == 0.005 and fromList.perRatingPoint, "weapon damage and armor keep the tree's weights")
modifier = true
P.SetPriority("WARRIOR", 256, { "INT", "STR" })
assert(Has(Hover("chest:caster"), "Probably not an upgrade"), "a priority list does nothing until the tree uses it")
P.SetUsesPriority("WARRIOR", 256, true)
out = Hover("chest:caster")
assert(Has(out, "Likely upgrade for Fury") and Has(out, "Rough estimate from your Fury stat priority"), "priority used: " .. tostring(out[2]))
assert(Has(out, "Not weighed for Fury: Stamina"), "stats left off the list are named")
P.SetPriority("WARRIOR", 256, { "HIT", "STR" })
c.GetCombatRatingBonusForCombatRatingValue = nil
Changed("PLAYER_LEVEL_UP")
out = Hover("chest:hit")
assert(Has(out, "+20 Hit Rating") and not Has(out, "Not counted"), "ratings count per point in a priority, no conversion needed")
c.GetCombatRatingBonusForCombatRatingValue = function(_, value) return value / 10 end
Changed("PLAYER_LEVEL_UP")
P.SetUsesPriority("WARRIOR", 256, false)
assert(Has(Hover("chest:hit"), "weighed for Fury"), "back to weights")
assert(c.TwichUIDB.gear.priority.WARRIOR[256][1] == "HIT", "the list is kept for next time")
P.SetPriority("WARRIOR", 256, nil)
assert(c.TwichUIDB.gear.priority.WARRIOR == nil and c.TwichUIDB.gear.usePriority.WARRIOR == nil, "nothing left behind")
local scale = {}
for stat in pairs(W.RATINGS) do scale[stat] = 0.1 end
local start = W.PriorityFromWeights(W.CLASSES.WARRIOR.trees[2].weights, scale)
assert(start[1] == "HIT" and start[2] == "CRIT" and start[3] == "STR" and start[4] == "AP" and #start == 8, "starting list: " .. table.concat(start, ","))
start = W.PriorityFromWeights(W.CLASSES.WARRIOR.trees[2].weights, nil)
assert(table.concat(start, ",") == "STR,AP,AGI,STA", "without rating conversion, ratings are left out: " .. table.concat(start, ","))
for stat in pairs(W.ITEM_POINT) do assert(W.RATINGS[stat] or not stat:find("RATING"), stat) end
modifier = false

-- Bag icons: off by default; on, upgrades are marked (fainter for possible).
bagFrame:UpdateItems()
assert(not buttons[1].TwichUIUpgradeIcon, "bag icons off: nothing drawn")
c.TwichUIDB.modules.gearBagIcons = true
bagFrame:UpdateItems()
assert(buttons[1].TwichUIUpgradeIcon.shown and buttons[1].TwichUIUpgradeIcon.alpha == 1, "likely upgrade marked")
assert(not buttons[2].TwichUIUpgradeIcon, "not an upgrade: no mark")
assert(not buttons[3].TwichUIUpgradeIcon, "can't wear it yet: no mark")
assert(buttons[4].TwichUIUpgradeIcon.shown and buttons[4].TwichUIUpgradeIcon.alpha == 0.6, "possible upgrade marked faintly")
EQUIPPED[5] = "chest:better"
Changed("PLAYER_EQUIPMENT_CHANGED")
FlushTimers()
assert(not buttons[1].TwichUIUpgradeIcon.shown, "marks follow what you wear")
EQUIPPED[5] = "chest:old"
Changed("PLAYER_EQUIPMENT_CHANGED")
c.TwichUIDB.modules.gearBagIcons = false
R.GearBags.Refresh(); FlushTimers()
assert(not buttons[1].TwichUIUpgradeIcon.shown, "turning bag icons off clears them")

-- EllesmereUI Bags: the same marks through its overlay painter, kept off the button.
local paint = assert(ellePainters.TwichUI, "painter registered with EllesmereUI Bags")
local elleButton = { CreateTexture = function() return Texture() end }
local function Mark(data) paint(elleButton, data) end
Mark({ bag = 0, slot = 1, itemLink = "chest:better" })
assert(not elleButton.TwichUIUpgradeIcon, "no state written to the Ellesmere button")
c.TwichUIDB.modules.gearBagIcons = true
local before = elleRefreshes
R.GearBags.Refresh(); FlushTimers()
assert(elleRefreshes == before + 1, "Ellesmere bags asked to repaint")
local created
local shown = 0
local counting = { CreateTexture = function() local t = Texture(); shown = shown + 1; created = t; return t end }
paint(counting, { bag = 0, slot = 1, itemLink = "chest:better" })
assert(created.shown and created.alpha == 1, "upgrade marked on Ellesmere slot")
paint(counting, { bag = 0, slot = 1, itemLink = "chest:better" })
assert(shown == 1, "one icon per button")
paint(counting, { bag = 0, slot = 4, itemLink = "chest:slight" })
assert(created.shown and created.alpha == 0.6, "possible upgrade is faint")
paint(counting, { bag = 0, slot = 2, itemLink = "chest:caster" })
assert(not created.shown, "reused button for a non-upgrade clears the mark")
paint(counting, { bag = 0, slot = 1, itemLink = "chest:better" })
paint(counting, { bag = 0, slot = 0 })
assert(not created.shown, "empty slot clears the mark")
paint(counting, { bag = 0, slot = 1, itemLink = "chest:better" })
c.TwichUIDB.modules.gearBagIcons = false
paint(counting, { bag = 0, slot = 1, itemLink = "chest:better" })
assert(not created.shown, "feature off clears the mark")
c.TwichUIDB.modules.gearBagIcons = false

-- Equipment changes are picked up.
modifier = true
EQUIPPED[16], EQUIPPED[17] = "2h:big", nil
Changed("PLAYER_EQUIPMENT_CHANGED")
assert(Has(Hover("oh:shield"), "Not compared while you wield a two-handed weapon"), "off hand vs two-hander")
modifier = false
assert(#Hover("oh:shield") == 0, "off hand vs two-hander: nothing by default")
assert(#Hover("mh:axe") == 0, "a one-hander is well short of the two-hander")
modifier = true
assert(Has(Hover("mh:axe"), "Leaves your off hand empty"), "one-hander over a two-hander frees the off hand")

-- No talent points yet: the class's usual tree, and no tree named at a glance.
SPENT = { 0, 0, 0 }
Changed("PLAYER_TALENT_UPDATE")
modifier = false
assert(Hover("chest:better")[1] == "Likely upgrade", "no tree named without talents")
modifier = true
assert(Has(Hover("chest:better"), "weighed for Arms until you spend talent points"), "explains the fallback")
SPENT = { 10, 10, 0 }
Changed("TRAIT_CONFIG_UPDATED")
assert(Has(Hover("chest:better"), "while your talents are split evenly"), "split talents")

-- Protection weighs stamina and armor, not strength.
SPENT = { 5, 0, 31 }
Changed("ACTIVE_TALENT_GROUP_CHANGED")
out = Hover("chest:better")
assert(Has(out, "for Protection") and out[4] == "+2 Stamina", "tank weights: " .. tostring(out[4]))
local trees, classFile, auto = R.GearData.Trees()
assert(#trees == 3 and classFile == "WARRIOR" and auto.skillLine == 257 and trees[3].spent == 31, "trees for the window")

-- Turned off: nothing at all.
c.TwichUIDB.modules.gearHints = false
assert(#Hover("chest:better") == 0, "off: nothing")
c.TwichUIDB.modules.gearHints = true

-- A class without weights gets nothing.
CLASS = { "Death Knight", "DEATHKNIGHT" }
Changed("PLAYER_LEVEL_UP")
assert(#Hover("chest:better") == 0, "unknown class: nothing")

-- Evaluation details.
local E = R.GearEval
local stats = E.Normalize({ RESISTANCE0_NAME = 300, Armor = 300, ITEM_MOD_STRENGTH = 4 }, 5)
assert(stats.ARMOR == 300 and stats.STR == 4, "a stat reported twice counts once; keys without _SHORT work")
local healer = W.CLASSES.PRIEST.trees[2].weights
local score = E.Score({ SP = 20 }, healer, {})
assert(score.values.HEAL == 20 and math.abs(score.total - 22) < 1e-9, "healers count spell power as healing, once")
score = E.Score({ SP = 20, HEAL = 20 }, healer, {})
assert(math.abs(score.total - 22) < 1e-9, "damage-and-healing listed twice isn't double counted")
assert(E.Compare({ equipLoc = "INVTYPE_WEAPONOFFHAND", raw = {} }, {}, { weights = {}, canDualWield = false }) == nil, "off-hand weapons need dual wield")
local editor = {}
for _, group in ipairs(W.EDITOR) do for _, stat in ipairs(group[2]) do editor[stat] = true end end
for _, cls in pairs(W.CLASSES) do
  for _, tree in ipairs(cls.trees) do
    for stat in pairs(tree.weights) do assert(editor[stat], stat .. " is editable") end
  end
end

print("GEAR TESTS PASSED")
