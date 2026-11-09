-- Camping bar (camping/): the data's shape, the rules (State.lua, pure), and the controller (Bar.lua) against a fake
-- client: what each button does, nothing changed in combat and caught up after it, the listeners only while on, and the
-- settings. Checks our logic, not the game: the in-game checks are in docs/camping-bar.md.
dofile(TESTS .. "harness.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end

---------------------------------------------------------------------------
-- A fake game
---------------------------------------------------------------------------
local c = MakeClient("Rich", {"!!!TwichUI"})
local frames = {}
local function Fake(o)
  o = o or {}
  o.shown, o.scripts, o.hooks, o.attrs = false, {}, {}, {}
  table.insert(frames, o)
  return setmetatable(o, {__index = function(t, k)
    if k == "recipe" or k == "entry" then return nil end   -- fields the bar owns: a real frame has none until it sets one
    if k == "Show" then return function(s) s.shown = true end end
    if k == "Hide" then return function(s) s.shown = false end end
    if k == "IsShown" then return function(s) return s.shown end end
    if k == "SetShown" then return function(s, v) s.shown = v and true or false end end
    if k == "SetScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "HookScript" then return function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end end
    if k == "SetAttribute" then return function(s, n, v) s.attrs[n] = v end end
    if k == "GetAttribute" then return function(s, n) return s.attrs[n] end end
    if k == "SetText" then return function(s, v) s.text = v end end
    if k == "SetTexture" then return function(s, v) s.texture = v end end
    if k == "SetDesaturated" then return function(s, v) s.desaturated = v end end
    if k == "SetAlpha" then return function(s, v) s.alpha = v end end
    if k == "SetCooldown" then return function(s, a, b) s.cd = { a, b } end end
    if k == "SetPoint" then return function(s, ...) s.point = {...} end end
    if k == "ClearAllPoints" then return function(s) s.point = nil end end
    if k == "SetSize" then return function(s, w, h) if w then s.w, s.h = w, h end end end
    if k == "GetSize" then return function(s) return s.w or 0, s.h or 0 end end
    if k == "GetCenter" then return function(s) return s.cx, s.cy end end
    if k == "CreateAnimationGroup" then return function()
      local g = Fake()
      g.Play, g.Stop = function() end, function() end
      g.CreateAnimation = function() local a = Fake(); a.SetFromAlpha, a.SetToAlpha, a.SetDuration, a.SetSmoothing = function() end, function() end, function() end, function() end return a end
      return g
    end end
    if k == "CreateFontString" or k == "CreateTexture" then return function() return Fake() end end
    return function() end
  end})
end
c.CreateFrame = function(kind, name, parent, template) return Fake({ kind = kind, name = name, parent = parent, template = template }) end
c.hooksecurefunc = function(obj, method, fn)   -- as the game: runs fn after the original, with the same arguments
  local orig = obj[method]
  rawset(obj, method, function(self, ...) local r = orig(self, ...); fn(...); return r end)
end
c.UIParent = Fake(); c.UIParent.cx, c.UIParent.cy = 512, 384
c.EventRegistry = { RegisterCallback = function() end }
c.EditModeManagerFrame = { IsEditModeActive = function() return false end }
c.GameTooltip = Fake()
c.UnitClass = function() return "Warrior", "WARRIOR" end

c.COMBAT, c.INSTANCE, c.RESTING, c.NEARBY = false, "none", false, false
c.InCombatLockdown = function() return c.COMBAT end
c.IsInInstance = function() return c.INSTANCE ~= "none", c.INSTANCE end
c.IsResting = function() return c.RESTING end
c.COUNTS, c.NAMES, c.KNOWN, c.SKILL, c.FIRE_SPELL = {}, {}, {}, {}, false
c.REQUESTED, c.OPENED = {}, {}
c.C_Item = {
  GetItemCount = function(id) return c.COUNTS[id] or 0 end,
  GetItemNameByID = function(id) return c.NAMES[id] end,
  GetItemIconByID = function(id) return c.NAMES[id] and 5000 + id or nil end,
  RequestLoadItemDataByID = function(id) c.REQUESTED[id] = (c.REQUESTED[id] or 0) + 1 end,
}
c.C_SpellBook = { IsSpellKnown = function(id) if id == 818 then return c.FIRE_SPELL end return c.KNOWN[id] == true end }
c.C_TradeSkillUI = {
  GetRecipeInfo = function(id) if c.KNOWN[id] ~= nil then return { learned = c.KNOWN[id] } end end,
  OpenRecipe = function(id) table.insert(c.OPENED, id) end,
}
c.C_SkillInfo = {
  GetNumSkillLines = function() local n = 0 for _ in pairs(c.SKILL) do n = n + 1 end return n end,
  GetSkillLineInfo = function(i) local ids = {} for id in pairs(c.SKILL) do ids[#ids + 1] = id end table.sort(ids)
    local id = ids[i]; return id and { skillID = id, rank = c.SKILL[id], isHeader = false } end,
  GetSkillLineInfoByID = function(id) return c.SKILL[id] and { skillID = id, rank = c.SKILL[id] } or nil end,
}
c.C_Spell = { GetSpellName = function(id) return id == 818 and "Basic Campfire" or nil end, GetSpellTexture = function() return 135805 end }
c.BAG, c.FOODS = {}, {}
c.UnitLevel = function() return 60 end
c.C_Container = { GetItemCooldown = function() return 0, 0, 1 end,
  GetContainerNumSlots = function(bag) return bag == 0 and #c.BAG or 0 end,
  GetContainerItemInfo = function(bag, slot) local id = bag == 0 and c.BAG[slot]; return id and { itemID = id } end }
c.C_UnitAuras = { GetPlayerAuraBySpellID = function(id) if id == 1283391 and c.NEARBY then return { spellId = id } end end }

for _, f in ipairs({ "chronicle/Style.lua", "modules/Interact.lua", "modules/Borders.lua", "camping/Data.lua", "camping/State.lua", "camping/Bar.lua", "camping/Unlock.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {}, ui = {} }
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local D, S, C = R.CampingData, R.CampingState, R.Camping
-- The Food button's classifier is FoodDrink's; a stand-in answers what it is asked (it reads item text in the game).
R.FoodDrink = {
  Vocabulary = function() return {}, {} end,
  Inspect = function(id) local f = c.FOODS[id]; if not f then return nil, false, "not-food" end
    return { name = f.name, icon = 7000 + id, kinds = { food = true }, buff = f.buff, amount = f.amount } end,
}
local events = R.frame.events

---------------------------------------------------------------------------
-- The data's shape
---------------------------------------------------------------------------
do
  Check(#D.GROUPS == 12, "twelve professions")
  local items, spells, keys, lines = {}, {}, {}, {}
  local function Unique(set, id, what) Check(type(id) == "number" and not set[id], what .. " " .. tostring(id) .. " is a number used once"); set[id] = true end
  for _, f in ipairs(D.FIRES) do Unique(items, f.item, "fire item"); Unique(spells, f.spell, "fire spell") end
  for i = 2, #D.FIRES do Check(D.FIRES[i].slots > D.FIRES[i - 1].slots and D.FIRES[i].skill > D.FIRES[i - 1].skill, "fires grow") end
  for _, g in ipairs(D.GROUPS) do
    Check(not keys[g.key] and not lines[g.line], g.key .. " has its own key and skill line"); keys[g.key], lines[g.line] = true, true
    Check(#g.objects >= 2 and #g.objects <= 4, g.key .. " has two to four objects")
    local last = 0
    for _, o in ipairs(g.objects) do
      Unique(items, o.item, "item"); Unique(spells, o.spell, "spell")
      Check(o.tier >= last and o.tier >= 1 and o.tier <= 3, g.key .. " tiers don't go down"); last = o.tier
      Check(type(o.name) == "string" and o.skill >= 1, g.key .. " object has a name and a skill")
    end
  end
  Check(not items[D.SLEEPING_BAG], "the sleeping bag is not a camp object")
  Check(#D.ITEMS == 40, "3 kits + 36 objects + the bag: " .. #D.ITEMS)
  local seen = {}
  for _, id in ipairs(D.ITEMS) do Check(not seen[id], "no item listed twice"); seen[id] = true end
  Check(seen[D.SLEEPING_BAG] and seen[279981], "the bag and a kit are asked about")
end

---------------------------------------------------------------------------
-- State.Plan
---------------------------------------------------------------------------
local function Names(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.name .. ":" .. e.state end
  return table.concat(out, ",")
end
local MANA, FERM, LAB = 279956, 279970, 279990
local MANA_S, FERM_S, LAB_S = 1230564, 1263005, 1263078
do
  Check(#S.Plan({}, {}) == 0, "nothing known, nothing shown")
  Check(#S.Plan(nil, nil) == 0, "no arguments at all")

  -- in the bags
  local plan = S.Plan({ count = { [MANA] = 2, [FERM] = 1 } }, {})
  Check(Names(plan) == "Mana Well:have,Fermenter:have", Names(plan))
  Check(plan[1].count == 2 and plan[1].group == "alchemy" and plan[1].tier == 1, "count, group and tier are carried")

  -- a recipe known with none made is offered, dimmed
  plan = S.Plan({ known = { [MANA_S] = true } }, {})
  Check(Names(plan) == "Mana Well:craft", Names(plan))
  -- only a true counts: false and no answer are not offers
  Check(#S.Plan({ known = { [MANA_S] = false } }, {}) == 0, "an unlearned recipe is not offered")
  Check(#S.Plan({ known = {} }, {}) == 0, "no answer is not an offer")
  -- skill: a readable rank below the recipe's rules it out; an unreadable one doesn't
  Check(#S.Plan({ known = { [FERM_S] = true }, rank = { [171] = 100 } }, {}) == 0, "skill 100 is not enough for a 140 recipe")
  Check(#S.Plan({ known = { [FERM_S] = true }, rank = { [171] = 140 } }, {}) == 1, "skill 140 is")
  Check(#S.Plan({ known = { [FERM_S] = true } }, {}) == 1, "skill unreadable: the known recipe decides")
  -- what you hold is shown whatever the skill says
  Check(#S.Plan({ count = { [FERM] = 1 }, rank = { [171] = 5 } }, {}) == 1, "held objects don't need the skill")

  -- only what is in the bags
  plan = S.Plan({ count = { [MANA] = 1 }, known = { [MANA_S] = true, [FERM_S] = true } }, { onlyBags = true })
  Check(Names(plan) == "Mana Well:have", Names(plan))

  -- best: what you hold beats what you could make; then the higher tier
  local facts = { count = { [MANA] = 1 }, known = { [MANA_S] = true, [FERM_S] = true, [LAB_S] = true } }
  Check(Names(S.Plan(facts, { best = true })) == "Mana Well:have", "the held one is best")
  Check(Names(S.Plan(facts, {})) == "Mana Well:have,Fermenter:craft,Alchemy Laboratory:craft", "off: all three: " .. Names(S.Plan(facts, {})))
  facts.count = { [MANA] = 1, [FERM] = 1 }
  Check(Names(S.Plan(facts, { best = true })) == "Fermenter:have", "of two held, the higher tier")
  facts.count = {}
  Check(Names(S.Plan(facts, { best = true })) == "Alchemy Laboratory:craft", "of recipes only, the highest")

  -- a profession can be left out
  Check(#S.Plan({ count = { [MANA] = 1 } }, { grp_alchemy = false }) == 0, "profession off")
  Check(#S.Plan({ count = { [MANA] = 1 } }, { grp_mining = false }) == 1, "another profession off changes nothing")

  -- two tier-1 banners: both held, both stay under "best"
  plan = S.Plan({ count = { [279972] = 1, [279973] = 1, [279943] = 0 } }, { best = true })
  Check(#plan == 2, "tied banners both stay")

  -- order: the fire, then professions in the list's order, then the bag
  plan = S.Plan({ count = { [279981] = 1, [279944] = 1, [MANA] = 1, [D.SLEEPING_BAG] = 1 } }, {})
  Check(Names(plan) == "Basic Campfire Kit:have,Mana Well:have,Sharpening Wheel:have,Cozy Sleeping Bag:have", Names(plan))
end

do -- left off, and the eat entry
  local facts = { count = { [MANA] = 1, [FERM] = 1 } }
  Check(Names(S.Plan(facts, { ["obj_" .. MANA] = false })) == "Fermenter:have", "one object left off")
  Check(#S.Plan({ count = { [MANA] = 1 }, known = { [FERM_S] = true } }, { ["obj_" .. FERM] = false }) == 1, "and a recipe left off too")
  Check(#S.Plan({ count = { [MANA] = 1 } }, { ["obj_" .. MANA] = true }) == 1, "true is on")
  local plan = S.Plan({ eat = { item = 5001, name = "Feast", count = 3 } }, { eat = true })
  Check(#plan == 1 and plan[1].kind == "eat" and plan[1].item == 5001 and plan[1].count == 3, "the eat entry")
  Check(#S.Plan({ eat = { item = 5001, count = 3 } }, {}) == 0, "off: no eat entry")
  Check(#S.Plan({ eat = { item = 5001, count = 0 } }, { eat = true }) == 0 and #S.Plan({}, { eat = true }) == 0, "no food, no entry")
  plan = S.Plan({ count = { [D.SLEEPING_BAG] = 1, [MANA] = 1 }, eat = { item = 5001, count = 1 } }, { eat = true })
  Check(plan[#plan].kind == "eat", "the eat button is last")

  local foods = { { id = 3, amount = 100, count = 5 }, { id = 1, amount = 300, count = 20 }, { id = 2, amount = 300, count = 4 }, { id = 4, amount = 300, count = 4 } }
  Check(S.ChooseFood(foods, "auto").id == 2, "auto: the most restored, then the smaller stack, then the lower ID")
  Check(S.ChooseFood(foods, "choose", 3).id == 3, "choose: the one picked")
  Check(S.ChooseFood(foods, "choose", 99) == nil and S.ChooseFood(foods, "choose", 0) == nil, "choose: not in the bags, nothing (no guess)")
  Check(S.ChooseFood({ { id = 1, amount = 5, count = 0 } }, "auto") == nil and S.ChooseFood({}, "auto") == nil and S.ChooseFood(nil, "auto") == nil, "an empty stack or no food")
  Check(S.EatMacro("Roasted Boar", true) == "/use Roasted Boar\n/sit" and S.EatMacro("Roasted Boar", false) == "/use Roasted Boar", "the macro")
  Check(S.EatMacro("Bad\n/run x", true) == nil and S.EatMacro("", true) == nil and S.EatMacro(nil, true) == nil and S.EatMacro("A|cffff0000B", true) == nil,
    "a name that could carry a second command is refused")
end

do -- the campfire
  Check(#S.Plan({}, {}) == 0, "no fire without a kit, spell or recipe")
  local plan = S.Plan({ count = { [279981] = 1, [279961] = 1 } }, {})
  Check(#plan == 1 and plan[1].item == 279961 and plan[1].slots == 5, "the largest kit held")
  plan = S.Plan({ fireSpell = true }, {})
  Check(#plan == 1 and plan[1].state == "cast" and plan[1].spell == 818, "no kit: the spell")
  plan = S.Plan({ count = { [279974] = 1 }, fireSpell = true }, {})
  Check(plan[1].state == "have" and plan[1].item == 279974, "a kit beats the spell")
  plan = S.Plan({ known = { [1229737] = true, [1283400] = true }, rank = { [185] = 120 } }, {})
  Check(#plan == 1 and plan[1].state == "craft" and plan[1].item == 279961, "the best kit recipe the skill allows")
  Check(#S.Plan({ known = { [1229737] = true } }, { onlyBags = true }) == 0, "only bags: no craft button for a kit")
  Check(#S.Plan({ fireSpell = true }, { onlyBags = true }) == 1, "only bags: the spell stays, it needs no kit")
  Check(#S.Plan({ count = { [279981] = 1 } }, { showFire = false }) == 0, "fire off")
  Check(#S.Plan({ count = { [D.SLEEPING_BAG] = 1 } }, {}) == 1 and #S.Plan({ count = { [D.SLEEPING_BAG] = 1 } }, { showBag = false }) == 0, "bag on and off")
  Check(#S.Plan({ count = { [D.SLEEPING_BAG] = 0 } }, {}) == 0, "no bag, no button")
end

---------------------------------------------------------------------------
-- State.Visible, Cell, Footprint
---------------------------------------------------------------------------
do
  Check(S.Visible({}, {}) == true and S.Visible(nil, nil) == true, "nothing chosen: shown")
  local v, why = S.Visible({ hideParty = true }, { instanceType = "party" }); Check(v == false and why == "dungeon", "dungeon")
  Check(S.Visible({ hideParty = true }, { instanceType = "raid" }) == true, "a dungeon rule leaves raids alone")
  Check(S.Visible({ hideRaid = true }, { instanceType = "raid" }) == false, "raid")
  Check(S.Visible({ hidePvp = true }, { instanceType = "pvp" }) == false and S.Visible({ hidePvp = true }, { instanceType = "arena" }) == false, "pvp and arena")
  Check(S.Visible({ hideResting = true }, { resting = true }) == false and S.Visible({ hideResting = true }, { resting = false }) == true, "resting")
  Check(S.Visible({ hideCombat = true }, { combat = true }) == false, "combat")
  Check(S.Visible({ hideParty = false, hideRaid = false }, { instanceType = "party", combat = true, resting = true }) == true, "off means off")
  Check(S.Visible({ onlyNearFire = true }, { nearFire = false }) == false, "no fire near: hidden")
  Check(S.Visible({ onlyNearFire = true }, { nearFire = true }) == true, "a fire near: shown")
  Check(S.Visible({ onlyNearFire = true }, { nearFire = nil }) == true, "not knowing never hides")
  Check(S.Visible({ onlyNearFire = false }, { nearFire = false }) == true, "the choice is off")

  local col, row = S.Cell(1, 4, false); Check(col == 0 and row == 0)
  col, row = S.Cell(4, 4, false); Check(col == 3 and row == 0)
  col, row = S.Cell(5, 4, false); Check(col == 0 and row == 1, "wraps to the next row")
  col, row = S.Cell(5, 4, true); Check(col == 1 and row == 0, "stacked: wraps to the next column")
  col, row = S.Cell(3, 4, true); Check(col == 0 and row == 2)
  col, row = S.Cell(3, 0, false); Check(col == 0 and row == 2, "a bad perLine is one")
  local w, h = S.Footprint(0, 36, 4, 12, false); Check(w == 36 and h == 36, "empty is one cell")
  w, h = S.Footprint(3, 36, 4, 12, false); Check(w == 3 * 36 + 8 and h == 36)
  w, h = S.Footprint(5, 36, 4, 4, false); Check(w == 4 * 36 + 12 and h == 2 * 36 + 4, "two rows")
  w, h = S.Footprint(5, 36, 4, 4, true); Check(w == 2 * 36 + 4 and h == 4 * 36 + 12, "two columns")
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
do
  Check(C.Get("size") == 36 and C.Get("best") == false and C.Get("showFire") == true and C.Get("grp_mining") == true, "defaults")
  Check(C.Set("size", 40) and C.Get("size") == 40, "a valid value is kept")
  Check(not C.Set("size", 5) and not C.Set("size", 40.5) and not C.Set("size", "40") and C.Get("size") == 40, "invalid numbers are refused")
  Check(not C.Set("layout", "diagonal") and C.Set("layout", "vertical") and C.Get("layout") == "vertical", "layout is an enum")
  Check(not C.Set("borderColor", "red") and C.Set("borderColor", "ff112233") and C.Get("borderColor") == "ff112233", "colour is AARRGGBB")
  Check(not C.Set("showFire", "yes") and C.Set("showFire", false) and C.Get("showFire") == false, "a saved false is a value, not a missing one")
  Check(not C.Set("nonsense", true), "unknown key refused")
  c.TwichUIDB.ui.campingBar.size = 9999
  Check(C.Get("size") == 36, "a bad saved value falls back to the default, not to something broken")
  c.TwichUIDB.ui.campingBar.size = 40
  C.Set("best", true)
  C.ResetLook()
  Check(C.Get("size") == 36 and C.Get("layout") == "horizontal" and C.Get("borderColor") == "ff8c6e38", "reset look puts the look back")
  Check(C.Get("best") == true and C.Get("showFire") == false, "reset look keeps what is on the bar")
  C.Set("best", false); C.Set("showFire", true)
  local x, y = C.Position(); Check(x == 0 and y == -170, "default place")
  C.SetPosition(10, -20); x, y = C.Position(); Check(x == 10 and y == -20 and c.TwichUIDB.ui.campingBarPosition.x == 10, "place saved")
  C.ResetPosition(); x, y = C.Position(); Check(x == 0 and y == -170 and c.TwichUIDB.ui.campingBarPosition == nil, "place reset")
end

---------------------------------------------------------------------------
-- The controller
---------------------------------------------------------------------------
local function Look() FlushTimers() end
local function Buttons()
  local out = {}
  for _, f in ipairs(frames) do if f.template == "SecureActionButtonTemplate" then out[#out + 1] = f end end
  return out
end
local function Container()
  local b = Buttons()[1]
  return b and b.parent
end
local function Shown()
  local out = {}
  for _, b in ipairs(Buttons()) do if b.shown and rawget(b, "entry") then out[#out + 1] = b end end
  return out
end
local MODULES = c.TwichUIDB.modules

-- Off: nothing is listened for and nothing is built. Other modules share some events, so what the bar adds is judged by
-- its own count (C.Snapshot().events) and by the events nothing else registered before it was turned on.
local base = {}
for e in pairs(events) do base[e] = true end
local function Mine(e) return events[e] and not base[e] end
Check(#Buttons() == 0 and Container() == nil, "off: nothing built")
Check(C.Snapshot().events == 0 and C.Snapshot().enabled == false, "off: the snapshot says so")

c.NAMES = { [MANA] = "Mana Well", [FERM] = "Fermenter", [279981] = "Basic Campfire Kit", [D.SLEEPING_BAG] = "Cozy Sleeping Bag", [LAB] = "Alchemy Laboratory" }
c.COUNTS = { [MANA] = 1, [279981] = 1 }
c.KNOWN = { [FERM_S] = true }
c.SKILL = { [171] = 150 }
R.Switches.Set("campingBar", true)
Check(events.BAG_UPDATE_DELAYED and events.SKILL_LINES_CHANGED and events.SPELLS_CHANGED and events.NEW_RECIPE_LEARNED
  and events.PLAYER_ENTERING_WORLD and events.PLAYER_REGEN_ENABLED and events.BAG_UPDATE_COOLDOWN, "on: listening")
Check(C.Snapshot().events == 8, "on: eight listeners and no more: " .. C.Snapshot().events)
Check(not events.UNIT_AURA and not events.PLAYER_UPDATE_RESTING, "the visibility events only when a choice needs them")

Look()
Check(#Buttons() == 0, "no world yet: nothing built")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false); Look()
local shown = Shown()
Check(#shown == 3, "kit, held object, known recipe: " .. #shown)
local kit, mana, ferm = shown[1], shown[2], shown[3]
Check(kit.attrs.type == "item" and kit.attrs.item == "Basic Campfire Kit", "a held kit is used by name")
Check(mana.attrs.type == "item" and mana.attrs.item == "Mana Well" and rawget(mana, "recipe") == nil, "a held object is used by name")
Check(ferm.attrs.type == nil and ferm.attrs.item == nil and ferm.attrs.spell == nil and rawget(ferm, "recipe") == FERM_S, "a recipe only: no secure action, a recipe to open")
Check(ferm.icon.desaturated == true and mana.icon.desaturated == false, "the recipe is dimmed")
Check(kit.attrs.useOnKeyDown == false, "acts as the mouse comes up")
Check(Container().shown == true, "the bar shows")
local ctr = Container()
Check(ctr.w == 3 * 36 + 8 and ctr.h == 36, "sized for three: " .. tostring(ctr.w))
Check(ferm.point[1] == "TOPLEFT" and ferm.point[4] == 2 * 40, "the third button sits two steps along")

-- Clicking the recipe button opens the recipe and crafts nothing.
for _, h in ipairs(ferm.hooks.OnClick or {}) do h(ferm) end
Check(#c.OPENED == 1 and c.OPENED[1] == FERM_S, "opens the recipe")
for _, h in ipairs(mana.hooks.OnClick or {}) do h(mana) end
Check(#c.OPENED == 1, "a held object's click opens no recipe")

-- A bag change in combat changes no button; the combat ending does.
c.COMBAT = true
c.COUNTS[FERM] = 1; c.NAMES[FERM] = "Fermenter"
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
Check(ferm.attrs.type == nil and rawget(ferm, "recipe") == FERM_S, "nothing secure changes in combat")
Check(C.Snapshot().deferred == true, "the change is waiting")
c.COMBAT = false
c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
Check(ferm.attrs.type == "item" and ferm.attrs.item == "Fermenter" and rawget(ferm, "recipe") == nil, "caught up after combat")

-- Best only
C.Set("best", true); Look()
shown = Shown()
Check(#shown == 2 and shown[2].attrs.item == "Fermenter", "best: one per profession, the higher tier held")
C.Set("best", false); Look()
Check(#Shown() == 3, "best off: all again")
-- The extra button is hidden and inert, not left behind
c.COUNTS[FERM] = 0; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
C.Set("onlyBags", true); Look()
Check(#Shown() == 2, "only bags: the recipe button goes")
local all = Buttons()
Check(all[3].shown == false and all[3].attrs.type == nil and all[3].attrs.item == nil, "a spare button is hidden and inert")
C.Set("onlyBags", false); Look()

-- The fire spell and the sleeping bag
c.COUNTS[279981] = 0; c.FIRE_SPELL = true; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
shown = Shown()
Check(shown[1].attrs.type == "spell" and shown[1].attrs.spell == 818 and shown[1].attrs.item == nil, "no kit: the spell is cast")
c.COUNTS[D.SLEEPING_BAG] = 1; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
shown = Shown()
Check(shown[#shown].attrs.item == "Cozy Sleeping Bag", "the bag is last")

-- An item the game has not loaded yet: no guess at its name, a request, and a look again when it arrives
c.NAMES[MANA] = nil; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
Check(mana.attrs.type == nil, "unknown name: no secure item action")
Check(c.REQUESTED[MANA] and c.REQUESTED[MANA] >= 1, "the game is asked for the item")
local before = c.REQUESTED[MANA]
c.FireEvent("GET_ITEM_INFO_RECEIVED", MANA, false); Look()
Check(c.REQUESTED[MANA] == before, "a failed load is not asked for again")
c.NAMES[MANA] = "Mana Well"
c.FireEvent("GET_ITEM_INFO_RECEIVED", MANA, true); Look()
Check(mana.attrs.item == "Mana Well", "it arrived: the button is made")

-- Profession left out
C.Set("grp_alchemy", false); Look()
Check(#Shown() == 2, "alchemy left out")
C.Set("grp_alchemy", true); Look()

-- An object left off the bar
C.Set("obj_" .. MANA, false); Look()
Check(#Shown() == 3, "an object left off disappears")
for _, b in ipairs(Shown()) do Check(b.attrs.item ~= "Mana Well", "and it is the right one") end
C.Set("obj_" .. MANA, true); Look()
Check(#Shown() == 4, "and comes back")

-- The eat button
do
  Check(not events.SPELL_TEXT_UPDATE or base.SPELL_TEXT_UPDATE, "no spell text listener while the eat button is off")
  c.BAG = { 5001, 5002, 5003, 5004 }
  c.FOODS = { [5001] = { name = "Roasted Boar", amount = 300, buff = true }, [5002] = { name = "Spiced Wolf", amount = 500, buff = true },
    [5003] = { name = "Plain Bread", amount = 900, buff = false } }   -- 5004 is not food at all
  c.COUNTS[5001], c.COUNTS[5002], c.COUNTS[5003] = 10, 2, 40
  c.NAMES[5001], c.NAMES[5002], c.NAMES[5003] = "Roasted Boar", "Spiced Wolf", "Plain Bread"
  Look()
  Check(#Shown() == 4, "the eat button is off by default")
  C.Set("eat", true); Look()
  Check(C.Snapshot().events == 9 and events.SPELL_TEXT_UPDATE, "while on it listens for spell text (item text is read)")
  local list = C.Entries()
  local eatEntry = list[#list]
  Check(eatEntry.kind == "eat" and eatEntry.item == 5002, "auto: the buff food that restores the most, not the plain bread")
  local named
  for _, f in ipairs(frames) do if f.name == "TwichUICampingEat" then named = f end end
  Check(named and named.template == "SecureActionButtonTemplate", "a named secure button, so a key can click it")
  Check(named.shown and named.attrs.type == "macro" and named.attrs.macrotext == "/use Spiced Wolf\n/sit" and named.attrs.item == nil,
    "it eats, then sits: " .. tostring(named.attrs.macrotext))
  Check(c["BINDING_NAME_CLICK TwichUICampingEat:LeftButton"], "the key binding has a name")
  C.Set("eatSit", false); Look()
  Check(named.attrs.type == "item" and named.attrs.item == "Spiced Wolf" and named.attrs.macrotext == nil, "sitting off: a plain item use")
  C.Set("eatSit", true)
  C.Set("eatMode", "choose"); Look()
  Check(not named.shown, "choose with nothing chosen: no button")
  C.Set("eatItem", 5001); Look()
  Check(named.shown and named.attrs.macrotext == "/use Roasted Boar\n/sit", "choose: that food")
  c.COUNTS[5001] = 0; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
  Check(not named.shown and named.attrs.type == nil and named.attrs.macrotext == nil, "gone from the bags: hidden and inert")
  c.COUNTS[5001] = 10; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
  Check(named.shown and named.attrs.macrotext == "/use Roasted Boar\n/sit", "back in the bags: the button returns")
  Check(#C.BuffFoods(true) == 2, "the settings list: the two buff foods in the bags")
  c.COMBAT = true; c.COUNTS[5001] = 0; c.FireEvent("BAG_UPDATE_DELAYED"); Look()
  Check(named.attrs.macrotext == "/use Roasted Boar\n/sit", "nothing secure changes in combat")
  c.COMBAT = false; c.COUNTS[5001] = 10; c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
  C.Set("eat", false); C.Set("eatMode", "auto"); Look()
  Check(not named.shown and C.Snapshot().events == 8, "turned off: hidden, and the spell text listener is let go")
end

-- An EllesmereUI border (Pixels Textured): the icon runs up to the line instead of stopping a quarter of the thickness short.
-- The stand-in draws the line outside the button's edge, 0.179 of the cell past it (EllesmereUI_PixelPerfect.lua, _borderInk).
do
  local draws = {}
  local eui = {
    PP = { mult = 1 },
    ApplyBorderStyle = function(_, _, _, _, _, _, key, _, _, _, _, _, _, _, edgePx) draws[#draws + 1] = { key = key, edgePx = edgePx } end,
    GetBorderTextureList = function() return {} end,
    ResolveBorderTexture = function(key) return key == "pixels-textured" end,
    BorderPxStep = function() return 2 end,
    BorderLegacyPx = function() return 12 end,
    BorderReach = function(_, _, _, _, _, _, _, _, edgePx) return 0.179 * edgePx end,
  }
  c.EllesmereUI = eui
  C.Set("borderTexture", "eui:pixels-textured"); Look()
  Check(C.Get("borderSize") == 12, "choosing Pixels Textured seeds a thickness that suits it: " .. C.Get("borderSize"))
  Check(#draws > 0 and draws[#draws].key == "pixels-textured" and draws[#draws].edgePx == 12, "drawn by EllesmereUI at the exact size")
  local function Inset() return -mana.icon.point[2] end
  Check(Inset() == 0, "a 12 pixel cell, the line outside the edge: the icon meets it, no gap (inset " .. Inset() .. ")")
  C.Set("borderSize", 24); Look()
  Check(Inset() == 0, "and a thicker cell doesn't widen the gap (inset " .. Inset() .. ")")
  eui.BorderReach = function() return -3 end   -- a texture whose line is inside the edge: the icon stays clear of it
  C.Set("borderSize", 16); Look()
  Check(Inset() == 3, "a line inside the edge keeps the icon clear of it: " .. Inset())
  eui.BorderReach = function() error("EllesmereUI changed") end
  C.Set("borderSize", 12); Look()
  Check(Inset() == 0, "a failing BorderReach falls back to no inset, not an error")
  c.EllesmereUI = nil
  C.Set("borderTexture", "solid"); C.ResetLook(); Look()
end

-- Visibility, in and out of combat
C.Set("hideRaid", true)
Check(C.Snapshot().events == 8, "hide in raids needs no extra event")
c.INSTANCE = "raid"; c.FireEvent("PLAYER_ENTERING_WORLD", false, false); Look()
Check(Container().shown == false and C.HiddenBy() == "raid", "hidden in a raid")
c.INSTANCE = "none"; c.FireEvent("PLAYER_ENTERING_WORLD", false, false); Look()
Check(Container().shown == true and C.HiddenBy() == nil, "back outside")
C.Set("hideRaid", false)

C.Set("hideCombat", true)
Check(C.Snapshot().events == 9 and events.PLAYER_REGEN_DISABLED, "hide in combat listens for combat starting")
c.COMBAT = true; c.FireEvent("PLAYER_REGEN_DISABLED")
Check(Container().shown == false, "hidden at once as combat starts (a plain frame)")
c.COMBAT = false; c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
Check(Container().shown == true, "back when it ends")
C.Set("hideCombat", false)
Check(C.Snapshot().events == 8, "and the event is let go")

C.Set("hideResting", true)
Check(C.Snapshot().events == 9 and events.PLAYER_UPDATE_RESTING, "resting listens for resting")
c.RESTING = true; c.FireEvent("PLAYER_UPDATE_RESTING")
Check(Container().shown == false, "hidden while resting")
c.RESTING = false; c.FireEvent("PLAYER_UPDATE_RESTING")
Check(Container().shown == true, "shown again")
C.Set("hideResting", false)

C.Set("onlyNearFire", true)
Check(C.Snapshot().events == 9 and events.UNIT_AURA, "near a fire listens for auras")
c.NEARBY = false; c.FireEvent("UNIT_AURA", "player")
Check(Container().shown == false and C.HiddenBy() == "no-fire", "no fire near: hidden")
c.NEARBY = true; c.FireEvent("UNIT_AURA", "player")
Check(Container().shown == true, "fire near: shown")
c.NEARBY = false; c.FireEvent("UNIT_AURA", "target")
Check(Container().shown == true, "another unit's aura changes nothing")
c.COMBAT = true; c.FireEvent("UNIT_AURA", "player")
Check(Container().shown == true, "in combat the game may not say: the bar stays as it was")
c.COMBAT = false
C.Set("onlyNearFire", false)
Check(C.Snapshot().events == 8, "and the aura event is let go")

-- Nothing to show: the bar hides itself
c.COUNTS, c.KNOWN, c.FIRE_SPELL = {}, {}, false
c.FireEvent("BAG_UPDATE_DELAYED"); Look()
Check(#Shown() == 0 and Container().shown == false, "nothing to put on it: the bar is hidden")

-- The look: opacity at once, the rest through a look
C.Set("buttonOpacity", 50)
Check(Container().alpha == 0.5, "opacity applies at once")
C.Set("mouseover", true)
Check(Container().alpha == 0.3, "faded while the mouse is away")
C.Set("mouseover", false)
Check(Container().alpha == 0.5, "and back")

-- EllesmereUI's Unlock Mode
do
  local U = R.CampingUnlock
  Check(U and C.Unlock == U and U.Status() == "off" and not U.Drives(), "off by default")
  Check(select(1, U.Offset()) == nil, "no offset while it isn't in charge")
  C.Set("unlockMode", true)
  Check(U.Status() == "no-eui", "wanted but EllesmereUI isn't there")
  local element, listener
  c.EllesmereUI = {
    RegisterUnlockElements = function(_, list) element = list[1] end,
    MakeUnlockElement = function(def) return def end,
    RegisterUnlockModeListener = function(_, key, fn) listener = { key = key, fn = fn } end,
  }
  U.Refresh()
  Check(U.Status() == "active" and U.Drives() and element and element.key == "TwichUI_CampingBar" and element.label == "TwichUI Camping bar",
    "registered once EllesmereUI is there: " .. U.Status())
  local standFrame = element.getFrame()
  Check(standFrame and element.noResize and element.isHidden() == false, "a stand-in frame, not resizable, shown in Unlock Mode")
  Check(select(1, element.getSize()) >= 1, "sized for the bar")
  local count = 0
  U.Refresh(); U.Refresh()
  Check(element.getFrame() == standFrame and listener.key == "TwichUI_CampingBar", "registered once, not again")

  -- Save & Exit: the place is saved as given; a wrong anchor or a wild number is refused
  element.savePos(nil, "CENTER", "CENTER", 120, -80)
  local x, y = C.Position(); Check(x == 120 and y == -80, "saved")
  element.savePos(nil, "TOPLEFT", "TOPLEFT", 5, 5)
  element.savePos(nil, "CENTER", "CENTER", 1e9, 0)
  x, y = C.Position(); Check(x == 120 and y == -80, "a refused save changes nothing")
  local loaded = element.loadPos(); Check(loaded.point == "CENTER" and loaded.x == 120 and loaded.y == -80, "loads the saved place")

  -- The bar follows the stand-in out of combat, and waits in combat
  standFrame.cx, standFrame.cy = 600, 300
  standFrame.GetEffectiveScale = function() return 1 end
  c.UIParent.GetEffectiveScale = function() return 1 end
  local ox, oy = U.Offset(); Check(ox == 88 and oy == -84, "the stand-in's place as an offset: " .. tostring(ox) .. "," .. tostring(oy))
  standFrame:SetPoint("CENTER", c.UIParent, "CENTER", 88, -84)
  Check(Container().point[4] == 88 and Container().point[5] == -84, "the bar moved to the stand-in's place")
  c.COMBAT = true
  standFrame.cx = 700
  standFrame:SetPoint("CENTER", c.UIParent, "CENTER", 188, -84)
  Check(Container().point[4] == 88, "in combat the bar stays")
  c.COMBAT = false; c.FireEvent("PLAYER_REGEN_ENABLED"); Look()
  Check(Container().point[4] == 188, "and catches up when it ends")

  -- Reset position and the choice turned off
  C.ResetPosition()
  x, y = C.Position(); Check(x == 0 and y == -170, "reset puts the place back")
  element.clearPos()
  C.Set("unlockMode", false)
  Check(U.Status() == "off" and not U.Drives() and element.isHidden() == true, "off: not in charge, and hidden from Unlock Mode")
  c.EllesmereUI = nil
end

-- Snapshot, then off again: the events go and the bar hides
local snap = C.Snapshot()
Check(snap.enabled and snap.built and snap.events == 8 and snap.buttons >= 3, "the snapshot counts events and buttons")
R.Switches.Set("campingBar", false)
Check(C.Snapshot().events == 0 and not Mine("SKILL_LINES_CHANGED") and not Mine("NEW_RECIPE_LEARNED"), "off again: every listener is let go")
Check(Container().shown == false and C.Snapshot().events == 0, "and the bar is hidden")
R.Switches.Set("campingBar", true)
local n = 0
for _, f in ipairs(frames) do if f.template == "SecureActionButtonTemplate" then n = n + 1 end end
c.FireEvent("PLAYER_ENTERING_WORLD", false, false); Look()
local m = 0
for _, f in ipairs(frames) do if f.template == "SecureActionButtonTemplate" then m = m + 1 end end
Check(m == n, "turning it on again makes no new buttons: " .. n .. " then " .. m)

print("CAMPING TEST PASSED")
