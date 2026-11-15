-- Loot Rolls (loot/): Rules.lua decides (pure), Config.lua stores, Roll.lua watches the game's rolls and is the only place a choice is sent,
-- Auto.lua runs the visible countdown, Blizzard.lua lets the game's roll frames step aside, Cards.lua draws. A fake world stands in for the
-- game (rolls, items, a clock, timers, the roll history, the game's own frames), so this checks our logic, not the game: what the client
-- really does is in docs/loot-rolls-implementation.md (capability matrix and the in-game acceptance list).
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

---------------------------------------------------------------------------
-- A fake world
---------------------------------------------------------------------------
local Methods
local function Fake(kind)
  local o = { kind = kind, shown = false, scripts = {}, hooks = {}, points = {}, alpha = 1, mouse = true, w = 10, h = 10 }
  return setmetatable(o, { __index = function(_, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:find("^%u") then return function() end end
  end })
end
local function RunHooks(s, n, ...) for _, fn in ipairs(s.hooks[n] or {}) do fn(s, ...) end end
Methods = {
  Show = function(s) if not s.shown then s.shown = true; RunHooks(s, "OnShow") end end,
  Hide = function(s) if s.shown then s.shown = false; RunHooks(s, "OnHide") end end,
  IsShown = function(s) return s.shown end, SetShown = function(s, v) if v then s:Show() else s:Hide() end end,
  SetScript = function(s, n, fn) s.scripts[n] = fn end, GetScript = function(s, n) return s.scripts[n] end,
  HookScript = function(s, n, fn) s.hooks[n] = s.hooks[n] or {}; table.insert(s.hooks[n], fn) end,
  RegisterEvent = function(s, e) s.events = s.events or {}; s.events[e] = true end,
  UnregisterEvent = function(s, e) if s.events then s.events[e] = nil end end,
  UnregisterAllEvents = function(s) s.events = {} end,
  IsEventRegistered = function(s, e) return s.events ~= nil and s.events[e] == true end,
  CreateTexture = function(s) local t = Fake("texture"); t.parent = s; return t end,
  CreateFontString = function(s) local t = Fake("font"); t.parent = s; return t end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  GetStringWidth = function(s) return 40 end,
  SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  EnableMouse = function(s, v) s.mouse = v and true or false end, IsMouseEnabled = function(s) return s.mouse end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  ClearAllPoints = function(s) s.points = {} end, SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetScale = function(s, v) s.scale = v end, GetScale = function(s) return s.scale or 1 end,
  SetFont = function(s) return true end, SetDesaturated = function(s, v) s.desat = v end,
  GetParent = function(s) return s.parent end, GetFrameLevel = function() return 1 end,
}
local FRAMES = {}
c.CreateFrame = function(kind, name, parent) local f = Fake(kind); f.name, f.parent = name, parent; if name then c[name] = f end FRAMES[#FRAMES + 1] = f return f end
-- events reach the model's own frame as they do in the game (the core's frames are the harness's)
local function Fire(event, ...)
  c.FireEvent(event, ...)
  for _, f in ipairs(FRAMES) do
    if f.events and f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
c.UIParent = Fake("UIParent")
c.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
c.GameTooltip = Fake("tooltip")
c.GetCoinTextureString = function(n) return tostring(n) .. "c" end

-- a clock and timers we drive ourselves
local NOW = 1000
c.GetTime = function() return NOW end
local timers = {}
local function Timer(d, fn)
  local t = { due = NOW + d, fn = fn }
  function t:Cancel() self.cancelled = true end
  timers[#timers + 1] = t
  return t
end
c.C_Timer = { After = function(d, fn) return Timer(d, fn) end, NewTimer = function(d, fn) return Timer(d, fn) end }
local function Advance(seconds)
  local target = NOW + seconds
  while true do
    local best
    for _, t in ipairs(timers) do
      if not t.cancelled and not t.done and t.due <= target and (not best or t.due < best.due) then best = t end
    end
    if not best then break end
    NOW = math.max(NOW, best.due)
    best.done = true
    best.fn()
  end
  NOW = target
end
local function PendingTimers() local n = 0 for _, t in ipairs(timers) do if not t.cancelled and not t.done then n = n + 1 end end return n end

-- the items and the rolls
local TOOLTIP_KNOWN
c.ITEM_SPELL_KNOWN = "Already known"
c.LOOT_ROLL_INELIGIBLE_REASON1 = "This item is not for your class."
c.INVTYPE_HEAD = "Head"
c.INVTYPE_2HWEAPON = "Two-Hand"
c.GetItemClassInfo = function(id) return ({ [2] = "Weapon", [4] = "Armor", [9] = "Recipe", [7] = "Trade Goods" })[id] end
c.GetItemSubClassInfo = function(class, sub) if class == 9 then return ({ [6] = "Alchemy", [8] = "Enchanting" })[sub] end end
local ITEMS = {
  ["item:100"] = { id = 100, name = "Green Helm", quality = 2, class = 4, sub = 1, loc = "INVTYPE_HEAD", bind = 2, price = 1234, icon = 1001, type = "Armor", subType = "Plate" },
  ["item:101"] = { id = 101, name = "Epic Greatsword", quality = 4, class = 2, sub = 8, loc = "INVTYPE_2HWEAPON", bind = 1, price = 20612, icon = 1002, type = "Weapon", subType = "Two-Handed Swords" },
  ["item:102"] = { id = 102, name = "Recipe: Elixir", quality = 2, class = 9, sub = 6, loc = "", bind = 1, price = 80, icon = 1003, type = "Recipe", subType = "Alchemy" },
  ["item:103"] = { id = 103, name = "Recipe: Known", quality = 2, class = 9, sub = 6, loc = "", bind = 1, price = 80, icon = 1004, type = "Recipe", subType = "Alchemy", known = true },
  ["item:104"] = { id = 104, name = "Linen Cloth", quality = 1, class = 7, sub = 5, loc = "", bind = 0, price = 13, icon = 1005, type = "Trade Goods", subType = "Cloth" },
  ["item:105"] = { id = 105, name = "Recipe: Enchant", quality = 3, class = 9, sub = 8, loc = "", bind = 1, price = 80, icon = 1006, type = "Recipe", subType = "Enchanting" },
}
local MISSING = {}   -- links the game has not loaded
local rolls, rolled, active = {}, {}, {}
c.GetLootRollItemInfo = function(id)
  local r = rolls[id]
  if not r or MISSING[r.link] then return nil end
  local it = ITEMS[r.link]
  return it.icon, it.name, r.count or 1, it.quality, it.bind == 1, r.canNeed ~= false, r.canGreed ~= false, false, r.reasonNeed, nil, nil, nil, false
end
c.GetLootRollItemLink = function(id) local r = rolls[id]; if r then return r.link end end
c.GetLootRollTimeLeft = function(id) local r = rolls[id]; if r then return math.max(0, (r.ends - NOW) * 1000) end end
c.GetActiveLootRollIDs = function() local out = {} for id in pairs(active) do out[#out + 1] = id end table.sort(out) return out end
c.C_Item = {
  GetItemInfoInstant = function(link) local it = ITEMS[link]; if it then return it.id, it.type, it.subType, it.loc, it.icon, it.class, it.sub end end,
  GetItemInfo = function(link)
    local it = ITEMS[link]
    if not it or MISSING[link] then return nil end
    return it.name, link, it.quality, 10, 1, it.type, it.subType, 1, it.loc, it.icon, it.price, it.class, it.sub, it.bind
  end,
}
c.C_TooltipInfo = { GetLootRollItem = function(id)
  local r = rolls[id]
  if not r or r.noTooltip then return nil end
  local it = ITEMS[r.link]
  local lines = { { leftText = it.name } }
  if it.known then lines[#lines + 1] = { leftText = "Already known", leftColor = { r = 1, g = 0.1, b = 0.1 } } end
  return { lines = lines }
end }
c.C_SkillInfo = { GetNumSkillLines = function() return 2 end, GetSkillLineInfo = function(i)
  return ({ { isHeader = true, skillName = "Professions" }, { isHeader = false, skillName = "Alchemy", rank = 150 } })[i]
end }
local WORLD = { instance = "none", raid = false }
c.IsInInstance = function() return WORLD.instance ~= "none", WORLD.instance end
c.IsInRaid = function() return WORLD.raid end
c.StaticPopup_Visible = function() return false end
local sendFails, confirmOn = false, false
c.RollOnLoot = function(id, kind)
  if sendFails then error("refused") end
  rolled[#rolled + 1] = { id = id, kind = kind }
  if confirmOn and kind == 1 then Fire("CONFIRM_LOOT_ROLL", id, kind, "LOOT_BIND") end
end
-- the roll history
local HIST = { encounters = {}, drops = {} }
c.C_LootHistory = {
  GetAllEncounterInfos = function() return HIST.encounters end,
  GetSortedDropsForEncounter = function(e) return HIST.drops[e] end,
  GetSortedInfoForDrop = function(e, k) for _, d in ipairs(HIST.drops[e] or {}) do if d.lootListKey == k then return d end end end,
}

-- the game's own roll frames
local GROUP = {}
for i = 1, 4 do
  local f = Fake("GroupLootFrame")
  f.IconFrame = Fake("icon")
  f.LootButtonContainer = Fake("buttons")
  f.LootButtonContainer.LootButtons = { Fake("need"), Fake("pass"), Fake("greed") }
  GROUP[i] = f
  c["GroupLootFrame" .. i] = f
end

-- things TwichUI's other features provide, as they would answer
c.TwichUIDB = { modules = {} }
local JUDGED = {}
for _, f in ipairs({ "loot/Rules.lua", "loot/Config.lua", "loot/Roll.lua", "loot/Auto.lua",
  "loot/Blizzard.lua", "loot/Cards.lua", "loot/Main.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local Ru, LR, Ro, A, B, C = R.LootRules, R.LootRolls, R.LootRoll, R.LootAuto, R.LootBlizzard, R.LootCards
R.GearHints = { Judge = function(link) return JUDGED[link] end, Noteworthy = function(j) return j and j.up == true end }
R.FrameLook = { Shell = function() return Fake("shell") end }

---------------------------------------------------------------------------
-- 1. Rules (pure)
---------------------------------------------------------------------------
do
  local green = { quality = 2, classID = 4, equipLoc = "INVTYPE_HEAD", itemID = 100, bindType = 2, upgrade = false,
    recipe = { isRecipe = false }, context = { instanceType = "none" }, ready = true }
  local function Rule(extra)
    local r = { id = "lr1", name = "R", enabled = true, action = "greed", conditions = {} }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
  local q = { type = "quality", op = "is", value = 2 }
  Check(Ru.EvalCondition(q, green) == true, "quality is Uncommon matches an uncommon item")
  Check(Ru.EvalCondition({ type = "quality", op = "atLeast", value = 3 }, green) == false, "atLeast Rare does not match uncommon")
  Check(Ru.EvalCondition({ type = "quality", op = "atMost", value = 2 }, green) == true, "atMost Uncommon matches")
  Check(Ru.EvalCondition(q, {}) == nil, "a fact the client did not give is unknown, not a match")
  Check(Ru.EvalCondition({ type = "quality", op = "is", value = 2, negate = true }, {}) == nil, "a negated unknown stays unknown")
  Check(Ru.EvalCondition({ type = "quality", op = "is", value = 2, negate = true }, green) == false, "negation flips a known answer")
  Check(Ru.EvalCondition({ type = "quality", op = "is", value = 9 }, green) == nil, "an invalid condition never matches")
  Check(Ru.EvalCondition({ type = "class", value = "equipment" }, green) == true, "equipment is weapons and armor with a slot")
  Check(Ru.EvalCondition({ type = "class", value = "equipment" }, { classID = 4, equipLoc = "INVTYPE_NON_EQUIP" }) == false, "a shirt with no slot is not equipment")
  Check(Ru.EvalCondition({ type = "class", value = "equipment" }, { classID = 4 }) == nil, "equipment without a slot fact is unknown")
  Check(Ru.EvalCondition({ type = "class", value = 9 }, { classID = 9 }) == true, "the recipe class matches")
  Check(Ru.EvalCondition({ type = "equip", value = "INVTYPE_HEAD" }, green) == true, "a head slot matches")
  Check(Ru.EvalCondition({ type = "equip", value = "INVTYPE_CHEST" }, { equipLoc = "INVTYPE_ROBE" }) == true, "a robe is a chest piece")
  Check(Ru.EvalCondition({ type = "item", id = 100 }, green) == true and Ru.EvalCondition({ type = "item", id = 101 }, green) == false, "a specific item matches by id")
  Check(Ru.EvalCondition({ type = "bind", value = "equip" }, green) == true, "binds when equipped")
  Check(Ru.EvalCondition({ type = "context", value = "outsideRaid" }, green) == true, "outside a raid")
  Check(Ru.EvalCondition({ type = "context", value = "inRaid" }, { context = { instanceType = "raid" } }) == true, "in a raid")
  Check(Ru.EvalCondition({ type = "context", value = "inRaid" }, {}) == nil, "unknown place is unknown")
  -- recipes
  local mine = { recipe = { isRecipe = true, profession = true, known = false, canLearn = true } }
  Check(Ru.EvalCondition({ type = "recipe", mode = "profession" }, mine) == true, "a recipe for my profession")
  Check(Ru.EvalCondition({ type = "recipe", mode = "learnable" }, mine) == true, "a recipe I can learn")
  Check(Ru.EvalCondition({ type = "recipe", mode = "known" }, mine) == false, "not known")
  Check(Ru.EvalCondition({ type = "recipe", mode = "known" }, { recipe = { isRecipe = true, profession = true, known = true } }) == true, "already known is its own question")
  Check(Ru.EvalCondition({ type = "recipe", mode = "learnable" }, { recipe = { isRecipe = true, profession = true, known = true } }) == false, "a known recipe cannot be learned")
  Check(Ru.EvalCondition({ type = "recipe", mode = "learnable" }, { recipe = { isRecipe = true, profession = true, known = false } }) == nil, "learnable with no requirement data is unknown")
  Check(Ru.EvalCondition({ type = "recipe", mode = "profession" }, { recipe = { isRecipe = true } }) == nil, "an unread profession is unknown")
  Check(Ru.EvalCondition({ type = "recipe", mode = "any" }, { recipe = { isRecipe = false } }) == false, "an item that is no recipe")
  -- upgrades count only when allowed
  Check(Ru.EvalCondition({ type = "upgrade", value = true }, { upgrade = true }) == nil, "an upgrade hint alone decides nothing")
  Check(Ru.EvalCondition({ type = "upgrade", value = true }, { upgrade = true }, { allowUpgrade = true }) == true, "an allowed upgrade condition matches")
  Check(Ru.EvalCondition({ type = "upgrade", value = true }, {}, { allowUpgrade = true }) == nil, "an unknown upgrade is unknown")

  -- rules
  Check(Ru.Incomplete(Rule()) ~= nil, "a rule with no condition is incomplete (it would match everything)")
  Check(Ru.Incomplete(Rule({ conditions = { q }, action = "nope" })) ~= nil, "a rule needs a real action")
  Check(Ru.Incomplete(Rule({ conditions = { q, { type = "quality", op = "is", value = 99 } } })) ~= nil, "one bad condition makes the rule incomplete")
  Check(Ru.Incomplete(Rule({ conditions = { q } })) == nil, "a complete rule")
  local both = Rule({ conditions = { q, { type = "class", value = "equipment" } } })
  Check(Ru.EvalRule(both, green) == "match", "all conditions match")
  Check(Ru.EvalRule(both, { quality = 3, classID = 4, equipLoc = "INVTYPE_HEAD" }) == "no", "one no is a no")
  Check(Ru.EvalRule(both, { quality = 2 }) == "unknown", "a match plus an unknown is unknown")
  Check(Ru.EvalRule(both, { quality = 3 }) == "no", "a definite no wins over an unknown")
  local anyRule = Rule({ match = "any", conditions = { q, { type = "class", value = 9 } } })
  Check(Ru.EvalRule(anyRule, { quality = 2 }) == "match", "any: one match is enough")
  Check(Ru.EvalRule(anyRule, { quality = 3, classID = 4, equipLoc = "x" }) == "no", "any: no match and nothing unknown")
  Check(Ru.EvalRule(anyRule, { quality = 3 }) == "unknown", "any: no match but something unknown")

  -- priority: the first rule that is not a definite no decides; unknown blocks what is below it
  local first = Rule({ id = "lr1", name = "A", action = "pass", conditions = { { type = "recipe", mode = "known" } } })
  local second = Rule({ id = "lr2", name = "B", action = "greed", conditions = { q } })
  local d = Ru.Decide({ first, second }, { quality = 2, recipe = { isRecipe = false } })
  Check(d.status == "match" and d.rule.id == "lr2", "a no above lets the next rule decide")
  d = Ru.Decide({ first, second }, { quality = 2 })
  Check(d.status == "unknown" and d.rule.id == "lr1", "an unknown above stops the search: a lower rule must not speak for it")
  d = Ru.Decide({ second, first }, { quality = 2, recipe = { isRecipe = true, known = true, profession = true } })
  Check(d.status == "match" and d.rule.id == "lr2", "the first matching rule wins, whatever is below")
  second.enabled = false
  d = Ru.Decide({ second }, { quality = 2 })
  Check(d.status == "none", "a disabled rule says nothing")
  second.enabled = true
  Check(Ru.Decide({ Rule({ conditions = {} }) }, { quality = 2 }).status == "none", "an incomplete rule is skipped")
  Check(Ru.Decide(nil, {}).status == "none", "no rules, no decision")
  d = Ru.Decide({ Rule({ id = "lr1", action = "need", conditions = { q } }), Rule({ id = "lr2", action = "pass", conditions = { q } }) }, { quality = 2 })
  Check(d.rule.id == "lr1" and d.rule.action == "need", "two matching rules are never combined")

  Check(Ru.Summary(Rule({ conditions = { q, { type = "class", value = "equipment" } }, delay = 3 })):find("Greed") ~= nil, "a summary names the action")
  Check(Ru.Summary(Rule({ conditions = { q }, delay = 3 })):find("after 3 seconds") ~= nil, "a summary names the delay")
  Check(Ru.Summary(Rule({ conditions = {} })):find("once you add") ~= nil, "an empty rule says it needs a condition")
end

---------------------------------------------------------------------------
-- 2. Config
---------------------------------------------------------------------------
do
  Check(LR.Get("auto") == false and LR.Get("autoNeed") == false and LR.Get("autoUpgrade") == false and LR.Get("paused") == false, "every automation switch starts off")
  Check(LR.Get("scale") == 100 and LR.Get("growth") == "down", "defaults are read when nothing is saved")
  Check(LR.Set("scale", 120) and LR.Get("scale") == 120, "a valid setting is saved")
  Check(not LR.Set("scale", 9000) and LR.Get("scale") == 120, "an out-of-range setting is refused")
  Check(not LR.Set("growth", "sideways") and not LR.Set("nope", 1), "an unknown choice or key is refused")
  c.TwichUIDB.ui.lootRolls.scale = "wide"
  Check(LR.Get("scale") == 100, "an unusable saved value reads as its default")
  Check(c.TwichUIDB.ui.lootRolls.scale == "wide", "and is left as it is (no repair on read)")
  LR.Set("scale", 100)
  Check(LR.Set("auto", true) and LR.AutoOn(), "automation can be switched on")
  Check(LR.Set("paused", true) and not LR.AutoOn() and LR.Paused(), "pausing turns the automation off without touching the switch")
  LR.Set("paused", false); LR.Set("auto", false)
  LR.Set("afterResult", 20); LR.Set("scale", 130)
  LR.Set("auto", true)
  LR.ResetSettings()
  Check(LR.Get("afterResult") == 8 and LR.Get("scale") == 100, "reset restores the cards' settings")
  Check(LR.Get("auto") == true, "reset never changes the automation switch")
  LR.Set("auto", false)
  Check(LR.SetPlace(100.4, -50) and LR.Place() == 100 and select(2, LR.Place()) == -50, "a place is saved rounded")
  Check(not LR.SetPlace(1e9, 0) and not LR.SetPlace(0 / 0, 0), "an impossible place is refused")

  -- rules
  local ok, id = LR.Create("greenGear")
  Check(ok and id == "lr1" and LR.Count() == 1, "a rule is made from a starting point")
  local r = LR.Rule(id)
  Check(r.enabled == false and r.action == "greed" and #r.conditions == 2, "a new rule starts switched off")
  Check(r.delay == 3 and r.result == true and r.incomplete == nil, "with the default delay and complete")
  Check(LR.Create("nope") == false, "an unknown starting point is refused")
  local ok2, id2 = LR.Create("recipes")
  Check(id2 == "lr2", "ids count up")
  Check(LR.SetEnabled(id, true) and LR.Rule(id).enabled, "a rule is switched on")
  Check(LR.SetName(id, "  Green gear  ") and LR.Rule(id).name == "Green gear", "a name is trimmed")
  Check(not LR.SetName(id, "") and not LR.SetName(id, ("x"):rep(80)) and not LR.SetName(id, "bad|name"), "bad names are refused")
  Check(LR.SetAction(id, "pass") and LR.Rule(id).action == "pass" and not LR.SetAction(id, "roll"), "the action is one of three")
  LR.SetAction(id, "greed")
  Check(LR.SetDelay(id, 5.26) and LR.Rule(id).delay == 5.3, "a delay is rounded to a tenth")
  Check(not LR.SetDelay(id, 0) and not LR.SetDelay(id, 0.5) and not LR.SetDelay(id, 99), "a delay under a second, or over 15, is refused: the window to stop is not optional")
  Check(LR.SetMatch(id, "any") and LR.Rule(id).match == "any" and not LR.SetMatch(id, "some"), "all or any")
  LR.SetMatch(id, "all")
  Check(LR.SetShowResult(id, false) and LR.Rule(id).result == false, "show result afterward")
  local good, index = LR.AddCondition(id, "context")
  Check(good and index == 3 and LR.Rule(id).conditions[3].type == "context", "a condition is added with its starting values")
  Check(LR.SetCondition(id, 3, { value = "inRaid" }) and LR.Rule(id).conditions[3].value == "inRaid", "a condition is edited")
  Check(not LR.SetCondition(id, 3, { value = "nowhere" }) and LR.Rule(id).conditions[3].value == "inRaid", "an invalid edit changes nothing")
  Check(not LR.SetCondition(id, 3, { type = "quality" }) or LR.Rule(id).conditions[3].type == "context", "a condition's kind cannot be swapped")
  Check(LR.SetCondition(id, 3, { negate = true }) and LR.Rule(id).conditions[3].negate == true, "a condition can be negated")
  Check(not LR.AddCondition(id, "bogus"), "an unknown condition kind is refused")
  Check(LR.RemoveCondition(id, 3) and #LR.Rule(id).conditions == 2, "a condition is removed")
  for i = 1, 8 do LR.AddCondition(id, "bind") end
  Check(#LR.Rule(id).conditions == Ru.MAX_CONDITIONS, "a rule holds a bounded number of conditions")
  for i = #LR.Rule(id).conditions, 3, -1 do LR.RemoveCondition(id, i) end
  Check(LR.Move(id, 1) and LR.List()[2].id == id and LR.List()[1].id == id2, "a rule moves down")
  Check(not LR.Move(id, 1) and LR.Move(id, -1) and LR.List()[1].id == id, "and up, not past the ends")
  local dupOk, dupId = LR.Duplicate(id)
  Check(dupOk and dupId == "lr3" and LR.List()[2].id == dupId, "a copy sits under the rule")
  Check(LR.Rule(dupId).enabled == false and LR.Rule(dupId).name:find("copy") ~= nil, "a copy starts switched off")
  LR.SetName(dupId, "Copy edited")
  Check(LR.Rule(id).name == "Green gear" and #LR.Rule(dupId).conditions == #LR.Rule(id).conditions, "a copy shares nothing with the original")
  Check(LR.Delete(dupId) and not LR.Rule(dupId), "a rule is deleted")
  local ok4, id4 = LR.Create("blank")
  Check(id4 == "lr4", "a deleted rule's id is never reused")
  Check(#LR.Active() == 3, "the active list is the saved rules in order")
  for i = 1, 30 do LR.Create("blank") end
  Check(LR.Count() == LR.MAX_RULES and select(2, LR.Create("blank")):find("24") ~= nil, "the number of rules is bounded")
  Check(not LR.Create("blank"), "and refused with the reason")
  -- a profile change tells the cards
  local told
  LR.Subscribe(function(what) told = what end)
  R.Profiles.OnApply("layout", "x", function() end)
  LR.Invalidate("profile")
  Check(told == "profile", "subscribers hear about a profile change")
  -- broken saved rules are ignored, not fatal
  local saved = c.TwichUIDB.ui.lootRolls.rules
  saved[#saved + 1] = "junk"
  saved[#saved + 1] = { id = 7, name = 5 }
  local n = #LR.List()
  Check(n >= 1, "rules that are not rules are skipped when listing")
  table.remove(saved); table.remove(saved)
  -- a saved list longer than the limit is read only as far as the limit
  for i = 1, 40 do saved[#saved + 1] = { id = "lr" .. (100 + i), name = "x", action = "greed", conditions = { { type = "quality", op = "is", value = 2 } } } end
  Check(#LR.List() == LR.MAX_RULES and #LR.Active() == LR.MAX_RULES, "a hand-made list over the limit is read only as far as the limit")
  for i = 1, 40 do table.remove(saved) end
  -- clean up for the later sections
  for _, rule in ipairs(LR.List()) do LR.Delete(rule.id) end
  Check(LR.Count() == 0, "all rules removed")
end

---------------------------------------------------------------------------
-- The model: a helper to start a roll like the game does
---------------------------------------------------------------------------
local nextID = 100
local handle = 5000
local function StartRoll(link, opts)
  opts = opts or {}
  nextID = nextID + 1
  local id = opts.id or nextID
  rolls[id] = { link = link, ends = NOW + (opts.seconds or 30), canNeed = opts.canNeed, canGreed = opts.canGreed, reasonNeed = opts.reasonNeed, count = opts.count, noTooltip = opts.noTooltip }
  active[id] = true
  Fire("START_LOOT_ROLL", id, (opts.seconds or 30) * 1000, opts.handle or handle)
  return id
end
local function EndRoll(id) active[id] = nil; Fire("CANCEL_LOOT_ROLL", id) end

-- enable the feature the way the switch does
c.TwichUIDB.modules.lootRolls = true
LR.Refresh()
Check(LR.IsOn() and Ro.Listening() and C.Ready(), "the switch turns the model and the cards on")
Check(Ro.EventCount() == #Ro.EVENTS, "and listens for its events only then")

---------------------------------------------------------------------------
-- 3. Rolls
---------------------------------------------------------------------------
do
  local id = StartRoll("item:100")
  local roll = Ro.Find(id)
  Check(roll and roll.state == "pending" and roll.name == "Green Helm" and roll.quality == 2, "a started roll has its item")
  Check(roll.canNeed and roll.canGreed and roll.obs.ready and roll.obs.itemID == 100 and roll.obs.classID == 4, "and its facts")
  Check(roll.sellPrice == 1234 and roll.obs.bindType == 2, "and its price and binding")
  Check(math.abs(Ro.Remaining(roll) - 30) < 0.01, "the game's clock gives the time left")
  Fire("START_LOOT_ROLL", id, 30000, handle)
  Check(#Ro.Rolls() == 1, "a repeated start for the roll on screen adds no second record")
  Check(C.CardCount() == 1, "one card for one roll")
  Check(C.Has(id) and B.FrameCount() >= 1, "the card knows its roll")

  -- eligibility
  local id2 = StartRoll("item:101", { canNeed = false, reasonNeed = 1 })
  local r2 = Ro.Find(id2)
  local can, why = Ro.CanChoose(r2, "need")
  Check(not can and why == "This item is not for your class.", "Need is refused with the game's reason")
  Check(Ro.CanChoose(r2, "greed") and Ro.CanChoose(r2, "pass"), "Greed and Pass are open")
  Check(not Ro.Submit(r2, "need", "player") and #rolled == 0, "an ineligible choice is never sent")
  Check(not Ro.CanChoose(r2, "bogus"), "an unknown choice is refused")

  -- manual choice, sent once
  local ok = Ro.Submit(roll, "greed", "player")
  Check(ok and #rolled == 1 and rolled[1].id == id and rolled[1].kind == 2, "Greed is sent as roll type 2")
  Check(roll.state == "submitted" and roll.choice == "greed" and not roll.placed, "sent is not yet placed")
  Check(not Ro.Submit(roll, "need", "player") and not Ro.Submit(roll, "greed", "player") and #rolled == 1, "a second choice for the same roll is never sent")
  EndRoll(id)
  Check(roll.state == "submitted" and roll.placed, "the game closing the roll after a send means it was placed")

  -- results from the history
  HIST.encounters = { { encounterID = 9 } }
  HIST.drops[9] = { { lootListKey = 1, itemHyperlink = "item:100", playerRollState = 3, isTied = false, allPassed = false, rollInfos = {
    { playerName = "Arcanebloom", playerClass = "MAGE", isSelf = false, state = 3, isWinner = true, roll = 84 },
    { playerName = "Rich", playerClass = "MAGE", isSelf = true, state = 3, isWinner = false, roll = 42 },
    { playerName = "Briarfang", playerClass = "DRUID", isSelf = false, state = 5, isWinner = false } },
    winner = { playerName = "Arcanebloom", state = 3, roll = 84, isSelf = false } } }
  Fire("LOOT_HISTORY_UPDATE_DROP", 9, 1)
  Check(roll.result and roll.result.winner and roll.result.winner.name == "Arcanebloom" and roll.result.winner.roll == 84, "the history names the winner")
  Check(roll.result.rolls[1].name == "Arcanebloom" and roll.result.rolls[2].self and roll.result.rolls[3].choice == "pass", "rolls are sorted, mine marked")
  Check(roll.state == "resolved", "a placed roll with a winner is resolved")
  Check(roll.removeAt and roll.removeAt - NOW > 7 and roll.removeAt - NOW <= 8, "and leaves after the display time")
  Advance(9)
  Check(not Ro.ByKey(roll.key), "then the record is gone")

  -- a roll nobody chose on, expired
  local id3 = StartRoll("item:104", { seconds = 5 })
  local r3 = Ro.Find(id3)
  Advance(4.9)
  Check(not Ro.CanChoose(r3, "greed") and not Ro.Submit(r3, "greed", "player"), "a choice is not sent in the last moments")
  active[id3] = nil; Advance(0.2); Fire("CANCEL_LOOT_ROLL", id3)
  Check(r3.state == "ended" and r3.endReason == "expired" and #rolled == 1, "a roll that ran out with no choice ends as expired and sends nothing")
  Check(not Ro.Submit(r3, "pass", "player") and #rolled == 1, "an ended roll cannot be rolled on")

  -- a reused id with another item is another roll
  local first = StartRoll("item:104", { id = 777 })
  local firstRoll = Ro.Find(777)
  rolls[777] = { link = "item:100", ends = NOW + 30 }
  Fire("START_LOOT_ROLL", 777, 30000, handle)
  Check(firstRoll.state == "ended" and Ro.Find(777) ~= firstRoll and Ro.Find(777).name == "Green Helm", "a reused id with another item is a new roll, not a replaced one")
  EndRoll(777)
  Ro.Prune()

  -- needing a confirmation: nothing is placed until the player agrees
  confirmOn = true
  local idc = StartRoll("item:101")
  local rc = Ro.Find(idc)
  Check(Ro.Submit(rc, "need", "player"), "a send that the game asks to confirm")
  Check(rc.state == "pending" and rc.needsConfirm == 1, "stays open and says it is waiting for the game's dialog")
  Check(#rolled >= 1 and rolled[#rolled].kind == 1, "the call was made once")
  confirmOn = false
  Check(Ro.Submit(rc, "need", "player") and rc.state == "submitted", "after the dialog the player can send again")
  EndRoll(idc)

  -- an automatic Need the game wants confirmed is handed to the player, not counted down again
  do
    LR.Set("auto", true); LR.Set("autoNeed", true)
    local rid = select(2, LR.Create("blank")); LR.SetAction(rid, "need"); LR.SetEnabled(rid, true)
    confirmOn = true
    local ida = StartRoll("item:100")
    local ra = Ro.Find(ida)
    local before = #rolled
    Advance(3.2)
    Check(#rolled == before + 1 and rolled[#rolled].kind == 1, "the countdown sent Need once")
    Check(ra.state == "pending" and ra.needsConfirm and ra.autoStopped and not ra.auto, "and, with the game asking to confirm, the roll is the player's again")
    Advance(10)
    Check(#rolled == before + 1, "it is never sent again by itself")
    confirmOn = false
    EndRoll(ida)
    LR.Delete(rid); LR.Set("auto", false); LR.Set("autoNeed", false)
  end

  -- cancel all, complete
  local a1, a2 = StartRoll("item:104", { handle = 9001 }), StartRoll("item:104", { handle = 9002 })
  Ro.Submit(Ro.Find(a2), "pass", "player")
  Fire("LOOT_ROLLS_COMPLETE", 9001)
  Check(Ro.Find(a1).state == "ended" and Ro.Find(a2).state == "submitted", "a complete drop ends its own rolls only")
  Fire("CANCEL_ALL_LOOT_ROLLS")
  Check(Ro.Find(a2).state == "resolved" and Ro.Find(a2).placed, "cancel all resolves a sent roll as placed")

  -- the game has not loaded the item yet
  MISSING["item:100"] = true
  local idm = StartRoll("item:100")
  local rm = Ro.Find(idm)
  Check(not rm.obs.ready, "an item the game has not loaded is not ready")
  MISSING["item:100"] = nil
  Fire("GET_ITEM_INFO_RECEIVED", 100)
  Check(rm.obs.ready and rm.name == "Green Helm", "it is read again when the game has it")
  EndRoll(idm)

  -- no way to roll
  local RollOnLoot = c.RollOnLoot
  c.RollOnLoot = nil
  local idn = StartRoll("item:104")
  Check(not Ro.Submit(Ro.Find(idn), "pass", "player"), "no RollOnLoot, no choice, and no pretending")
  c.RollOnLoot = RollOnLoot
  sendFails = true
  local okf, reason = Ro.Submit(Ro.Find(idn), "pass", "player")
  Check(not okf and Ro.Find(idn).state == "pending" and Ro.Find(idn).choice == nil, "a refused call leaves the roll open for another try")
  sendFails = false
  EndRoll(idn)

  -- secret values are not read
  c.issecretvalue = function(v) return type(v) == "table" and v.secret == true end
  local secret = { secret = true }
  rolls[8888] = { link = "item:104", ends = NOW + 20 }; active[8888] = true
  local gi = c.GetLootRollItemInfo
  c.GetLootRollItemInfo = function() return 1, secret, 1, 1 end
  Fire("START_LOOT_ROLL", 8888, 20000, handle)
  Check(Ro.Find(8888) and Ro.Find(8888).name == nil, "a secret value is never used as a name")
  c.GetLootRollItemInfo = gi
  c.issecretvalue = nil
  EndRoll(8888)

  -- a reload in the middle of a roll
  Ro.Disable(); Ro.Enable()
  Check(#Ro.Rolls() >= 0, "the model restarts")
  local idr = StartRoll("item:100")
  Ro.Disable()
  Check(#Ro.Rolls() == 0 and not Ro.Listening(), "switching off forgets every record and stops listening")
  Ro.Enable()
  Check(Ro.Find(idr) and Ro.Find(idr).state == "pending", "and an open roll is taken in again, with the time it has left")
  EndRoll(idr)
  Advance(10)
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
end

---------------------------------------------------------------------------
-- 4. Automatic choices
---------------------------------------------------------------------------
do
  local function Fresh()
    for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
    rolled = {}
    for _, rule in ipairs(LR.List()) do LR.Delete(rule.id) end
    LR.Set("auto", false); LR.Set("autoNeed", false); LR.Set("autoUpgrade", false); LR.Set("paused", false)
  end
  local function Rule(kind, enabled)
    local ok, id = LR.Create(kind)
    if enabled ~= false then LR.SetEnabled(id, true) end
    return id
  end
  Fresh()
  local greedId = Rule("greenGear")
  -- off by default: a matching rule does nothing
  local id = StartRoll("item:100")
  local roll = Ro.Find(id)
  Check(roll.state == "pending" and not roll.auto, "with automation off a matching rule does nothing")
  LR.Set("auto", true)
  Check(roll.state == "scheduled" and roll.auto.action == "greed" and roll.auto.name == "Greed on green gear", "switched on, the countdown starts and names its rule")
  Check(#rolled == 0, "no choice is sent while counting down")
  Check(math.abs(roll.auto.fireAt - NOW - 3) < 0.01, "the delay is the rule's")
  Advance(2.9)
  Check(#rolled == 0 and roll.state == "scheduled", "nothing is sent before the countdown ends")
  Advance(0.2)
  Check(#rolled == 1 and rolled[1].kind == 2 and roll.state == "submitted" and roll.source == "auto", "at the end one Greed is sent, as an automatic choice")
  Advance(5)
  Check(#rolled == 1, "and never again")
  EndRoll(id)

  -- the player stops it
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Check(roll.state == "scheduled", "scheduled again")
  A.Stop(roll)
  Check(roll.state == "pending" and roll.autoStopped and not roll.auto, "stop hands the roll back to the player")
  Advance(10)
  Check(#rolled == 0, "stopping never sends Pass or anything else")
  A.Refresh()
  Check(roll.state == "pending", "and it is not scheduled again")
  Check(Ro.Submit(roll, "pass", "player") and #rolled == 1, "the player can still choose")
  EndRoll(id)

  -- a manual choice during the countdown wins
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Advance(1)
  Ro.Submit(roll, "pass", "player")
  Advance(5)
  Check(#rolled == 1 and rolled[1].kind == 0 and roll.source == "player", "a manual choice cancels the pending automatic one")
  EndRoll(id)

  -- Roll now
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Check(A.RollNow(roll) and #rolled == 1 and rolled[1].kind == 2, "Roll now sends the proposed choice at once")
  Advance(5)
  Check(#rolled == 1, "and the countdown does not send it again")
  EndRoll(id)

  -- no match: manual
  Fresh(); LR.Set("auto", true); Rule("greenGear")
  id = StartRoll("item:101"); roll = Ro.Find(id)
  Check(roll.state == "pending" and not roll.auto, "an item no rule matches stays manual")
  EndRoll(id)

  -- unknown: manual, with the reason
  Fresh(); LR.Set("auto", true)
  local rid = Rule("professionRecipes")
  id = StartRoll("item:102", { noTooltip = true }); roll = Ro.Find(id)
  Check(roll.obs.recipe.isRecipe and roll.obs.recipe.profession == true, "the recipe's profession is read from the game's words")
  Check(roll.state == "scheduled", "a recipe for my profession is known without its tooltip: the rule matches")
  EndRoll(id)
  Fresh(); LR.Set("auto", true)
  Rule("recipes")
  id = StartRoll("item:102", { noTooltip = true }); roll = Ro.Find(id)
  Check(roll.state == "pending" and roll.autoNote and roll.autoNote:find("could not be checked") ~= nil, "a rule that cannot be answered leaves the roll manual and says so")
  Advance(10)
  Check(#rolled == 0, "and sends nothing")
  EndRoll(id)
  -- the known recipe is told apart when the tooltip says so
  id = StartRoll("item:103"); roll = Ro.Find(id)
  Check(roll.state == "scheduled" and roll.auto.action == "pass", "an already-known recipe matches the pass rule")
  EndRoll(id)

  -- a recipe for a profession I do not have
  Fresh(); LR.Set("auto", true); Rule("professionRecipes")
  id = StartRoll("item:105"); roll = Ro.Find(id)
  Check(roll.obs.recipe.profession == false and roll.state == "pending", "another profession's recipe is not mine")
  EndRoll(id)

  -- Need is a separate opt-in
  Fresh(); LR.Set("auto", true)
  local needRule = Rule("blank"); LR.SetAction(needRule, "need")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Check(roll.state == "pending" and roll.autoNote and roll.autoNote:find("Need") ~= nil, "a Need rule does nothing until Need automation is allowed")
  LR.Set("autoNeed", true)
  Check(roll.state == "scheduled" and roll.auto.action == "need", "with Need allowed the countdown starts")
  EndRoll(id)
  -- ... and never when Need is not open to the player
  id = StartRoll("item:100", { canNeed = false, reasonNeed = 1 }); roll = Ro.Find(id)
  Check(roll.state == "pending" and roll.autoNote and roll.autoNote:find("matched") ~= nil, "Need is never chosen when it is not available")
  Advance(10)
  Check(#rolled == 0, "and nothing is sent")
  EndRoll(id)
  LR.Set("autoNeed", false)

  -- an upgrade rule needs its own permission
  Fresh(); LR.Set("auto", true)
  local up = Rule("blank")
  LR.RemoveCondition(up, 1); LR.AddCondition(up, "upgrade")
  JUDGED["item:100"] = { up = true }
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Check(roll.upgrade == true, "the existing upgrade judge is asked, not a calculation of ours")
  Check(roll.state == "pending", "an upgrade rule does nothing until upgrades are allowed")
  LR.Set("autoUpgrade", true)
  Check(roll.state == "scheduled", "then it counts")
  LR.Set("autoUpgrade", false)
  Check(roll.state == "pending", "and stops counting when the permission is withdrawn")
  EndRoll(id)
  JUDGED["item:100"] = nil

  -- pause cancels what is pending and keeps the rules
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Check(roll.state == "scheduled", "counting down")
  LR.Set("paused", true)
  Check(roll.state == "pending" and not roll.auto and not roll.autoStopped, "pausing cancels the countdown (and does not mark the roll as stopped)")
  Advance(10)
  Check(#rolled == 0 and LR.Count() == 1, "nothing is sent and the rule is untouched")
  Check(Ro.Submit(roll, "pass", "player"), "manual rolling works while paused")
  EndRoll(id)
  LR.Set("paused", false)

  -- the rule changes or goes mid-countdown
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Advance(1)
  LR.SetEnabled(greedId, false)
  Check(roll.state == "pending" and not roll.auto, "switching the rule off cancels its countdown")
  LR.SetEnabled(greedId, true)
  Check(roll.state == "scheduled", "switching it on again starts one")
  LR.SetAction(greedId, "pass")
  Check(roll.state == "scheduled" and roll.auto.action == "pass", "a changed action is a new countdown with the new action")
  Advance(1)
  LR.Delete(greedId)
  Check(roll.state == "pending" and not roll.auto, "deleting the rule cancels it")
  Advance(10)
  Check(#rolled == 0, "and sends nothing")
  EndRoll(id)

  -- the roll's own deadline wins over the rule's delay
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear"); LR.SetDelay(greedId, 10)
  id = StartRoll("item:100", { seconds = 6 }); roll = Ro.Find(id)
  Check(roll.state == "scheduled" and roll.auto.fireAt < roll.deadline - 0.9, "a countdown ends before the roll does")
  Advance(5.5)
  Check(#rolled == 1 and rolled[1].kind == 2, "and the choice goes out in time")
  EndRoll(id)
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100", { seconds = 1.5 }); roll = Ro.Find(id)
  Check(roll.state == "pending" and roll.autoNote and roll.autoNote:find("too little time") ~= nil, "with too little time left there is no countdown at all")
  Advance(3)
  Check(#rolled == 0, "and nothing is sent")
  EndRoll(id)

  -- a roll that ended while counting down is never sent
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  active[id] = nil; Fire("CANCEL_LOOT_ROLL", id)
  Advance(10)
  Check(#rolled == 0 and roll.state == "ended", "a roll cancelled during the countdown is not rolled on")

  -- a duplicate timer callback or event cannot send twice
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Fire("START_LOOT_ROLL", id, 30000, handle)
  Fire("START_LOOT_ROLL", id, 30000, handle)
  Advance(4)
  Check(#rolled == 1, "duplicate start events and a stale timer send exactly once")
  EndRoll(id)

  -- the cards must be there to count down on
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  local ready = C.Ready
  C.Ready = function() return false end
  id = StartRoll("item:100"); roll = Ro.Find(id)
  Check(roll.state == "pending", "no card to show the countdown on, no countdown")
  C.Ready = ready
  EndRoll(id)

  -- a profile change that removes the rules
  Fresh(); LR.Set("auto", true); greedId = Rule("greenGear")
  id = StartRoll("item:100"); roll = Ro.Find(id)
  c.TwichUIDB.ui.lootRolls.rules = {}
  LR.Invalidate("profile")
  Check(roll.state == "pending" and not roll.auto, "another profile's rules replace the countdown")
  EndRoll(id)
  Fresh()
  Advance(30)
  Check(PendingTimers() <= 2, "no timers pile up (" .. PendingTimers() .. " pending)")
end

---------------------------------------------------------------------------
-- 5. The game's own frames
---------------------------------------------------------------------------
do
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  local id = StartRoll("item:100")
  local frame = GROUP[1]
  frame.rollID = id
  frame:Show()
  Check(B.IsParked(frame) and frame.alpha == 0, "a game frame showing a roll that has a card is invisible")
  Check(frame.mouse == false and frame.IconFrame.mouse == false and frame.LootButtonContainer.LootButtons[1].mouse == false, "and cannot be clicked, nor can its buttons")
  frame.LootButtonContainer.LootButtons[1].mouse = true
  frame:Hide(); frame:Show()
  Check(B.IsParked(frame), "a frame shown again for the same roll is parked again")
  Fire("CANCEL_LOOT_ROLL", id)
  frame:Hide()
  Check(not B.IsParked(frame) and frame.alpha == 1 and frame.mouse == true, "a hidden frame is the game's again, as it was")
  -- a frame for a roll with no card keeps its controls
  frame.rollID = 424242
  frame:Show()
  Check(not B.IsParked(frame) and frame.alpha == 1, "a roll with no card of ours keeps the game's frame, so it can never be left with no controls")
  frame:Hide()
  -- the feature goes off with a roll open: the frame comes back
  local id2 = StartRoll("item:100")
  GROUP[2].rollID = id2
  GROUP[2]:Show()
  Check(B.IsParked(GROUP[2]), "parked while the card shows it")
  LR.Set("scale", 100)
  c.TwichUIDB.modules.lootRolls = false
  LR.Refresh()
  Check(not B.IsParked(GROUP[2]) and GROUP[2].alpha == 1 and GROUP[2].mouse == true, "switching the feature off gives the game's frame back at once")
  Check(not Ro.Listening() and C.CardCount() == 0 and B.ParkedCount() == 0, "and removes every card and listener")
  c.TwichUIDB.modules.lootRolls = true
  LR.Refresh()
  Check(Ro.Find(id2) and C.Has(id2), "switching on again takes the open roll in")
  Check(B.IsParked(GROUP[2]), "and parks its frame again")
  -- a card that is dismissed hands its roll back
  local card = C.Card(Ro.Find(id2).key)
  card.onDismiss(card)
  Check(not C.Has(id2) and not B.IsParked(GROUP[2]) and GROUP[2].alpha == 1, "dismissing a live card hands the roll back to the game's frame")
  Fire("CANCEL_LOOT_ROLL", id2)
  GROUP[2]:Hide()
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
end

---------------------------------------------------------------------------
-- 6. Cards
---------------------------------------------------------------------------
do
  rolled = {}
  local id = StartRoll("item:101", { canNeed = false, reasonNeed = 1 })
  local roll = Ro.Find(id)
  local card = C.Card(roll.key)
  Check(card and card:IsShown(), "a card is shown for a live roll")
  Check(card.name.text == "Epic Greatsword", "with the item's name")
  Check(card.buttons.need.state == "unavailable" and card.buttons.greed.state == "normal" and card.buttons.pass.state == "normal", "Need is shown unavailable, the others open")
  Check(card.buttons.greed:IsShown() and not card.buttons.now:IsShown(), "the choices are shown, the countdown's controls are not")
  -- a click is a choice
  card.buttons.need.scripts.OnClick(card.buttons.need)
  Check(#rolled == 0, "clicking an unavailable choice sends nothing")
  card.buttons.greed.scripts.OnClick(card.buttons.greed)
  Check(#rolled == 1 and rolled[1].kind == 2, "clicking Greed sends Greed")
  card.buttons.greed.scripts.OnClick(card.buttons.greed)
  Check(#rolled == 1, "a double click sends once")
  Check(card.status:IsShown() and not card.buttons.greed:IsShown(), "after the choice the buttons give way to the status")
  Check(card.status.text.text:find("Sending") ~= nil, "which says it is sending, not that it worked")
  EndRoll(id)
  Check(card.status.text.text:find("You chose") ~= nil, "and says chosen once the game closed the roll")
  HIST.encounters = { { encounterID = 11 } }
  HIST.drops[11] = { { lootListKey = 2, itemHyperlink = "item:101", playerRollState = 3, rollInfos = {
    { playerName = "Arcanebloom", isSelf = false, state = 3, isWinner = true, roll = 84 }, { playerName = "Rich", isSelf = true, state = 3, roll = 42 } },
    winner = { playerName = "Arcanebloom", state = 3, roll = 84 } } }
  Fire("LOOT_HISTORY_UPDATE_DROP", 11, 2)
  Check(card.banner:IsShown() and card.banner.text.text:find("Won by Arcanebloom") ~= nil, "a known winner is shown")
  Check(card.status.text.text:find("42") ~= nil and card.rows[1].frame:IsShown() and card.rows[1].name.text == "Arcanebloom", "with my roll and the rolls the game gave")
  Check(not card.rows[3].frame:IsShown(), "and only those")
  -- no result data: nothing is made up
  rolls[5551] = { link = "item:104", ends = NOW + 30 }; active[5551] = true
  Fire("START_LOOT_ROLL", 5551, 30000, handle)
  local r2 = Ro.Find(5551)
  Ro.Submit(r2, "pass", "player")
  active[5551] = nil; Fire("CANCEL_LOOT_ROLL", 5551)
  Fire("CANCEL_ALL_LOOT_ROLLS")
  local card2 = C.Card(r2.key)
  Check(card2 and r2.state == "resolved" and not card2.banner:IsShown() and not card2.rows[1].frame:IsShown(), "a roll with no history shows no winner and no list")
  -- the stack is bounded
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  LR.Set("maxCards", 2)
  local ids = {}
  for i = 1, 4 do ids[i] = StartRoll("item:104") end
  Check(C.CardCount() == 2 and C.Has(ids[1]) and C.Has(ids[2]) and not C.Has(ids[3]), "no more cards than the player allows, oldest first")
  Check(C.PoolSize() <= 6, "and a bounded pool")
  GROUP[3].rollID = ids[3]; GROUP[3]:Show()
  Check(not B.IsParked(GROUP[3]), "a roll without a card keeps the game's frame")
  GROUP[3]:Hide()
  for i = 1, 4 do EndRoll(ids[i]) end
  LR.Set("maxCards", 4)
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  Check(C.CardCount() == 0, "no orphaned cards")
  -- a card that lost its roll fades out and is free again
  local fadeId = StartRoll("item:104")
  local fadeCard = C.Card(Ro.Find(fadeId).key)
  Fire("CANCEL_LOOT_ROLL", fadeId)
  Ro.Remove(Ro.Find(fadeId))
  Check(fadeCard.leaving and fadeCard:IsShown() and not C.Has(fadeId), "a card that lost its roll fades out rather than vanishing, and is no longer the roll's card")
  c.GetTime = c.GetTime
  C.Tick(0.1)
  Check(fadeCard.alpha < 1 and fadeCard:IsShown(), "partway through the fade")
  C.Tick(0.2)
  Check(not fadeCard:IsShown() and not fadeCard.leaving and fadeCard.alpha == 1, "then hidden and free")
  LR.Set("animate", false)
  local fadeId2 = StartRoll("item:104")
  local card3 = C.Card(Ro.Find(fadeId2).key)
  Ro.Remove(Ro.Find(fadeId2))
  Check(not card3:IsShown() and not card3.leaving, "with animation off it goes at once")
  LR.Set("animate", true)
  -- a scheduled card
  LR.Set("auto", true)
  local rid = select(2, LR.Create("greenGear")); LR.SetEnabled(rid, true)
  local ida = StartRoll("item:100")
  local ra = Ro.Find(ida)
  local ca = C.Card(ra.key)
  Check(ra.state == "scheduled" and ca.buttons.now:IsShown() and ca.buttons.stop:IsShown() and not ca.buttons.greed:IsShown(), "a countdown shows Roll now and Stop auto roll")
  Check(ca.pillTop.text.text == "Auto Greed" and ca.line3.text:find("Greed on green gear") ~= nil, "and the proposed choice and the rule")
  ca.buttons.stop.scripts.OnClick(ca.buttons.stop)
  Check(ra.state == "pending" and ca.buttons.greed:IsShown(), "Stop returns the three choices")
  EndRoll(ida)
  -- a roll with no card (the player allows one at a time) is never counted down
  LR.Set("maxCards", 1)
  local idb, idc2 = StartRoll("item:100"), StartRoll("item:100")
  Check(Ro.Find(idb).state == "scheduled" and Ro.Find(idc2).state == "pending" and not C.Has(idc2), "a roll that has no card of its own gets no countdown")
  EndRoll(idb)
  Check(Ro.Find(idc2).state == "scheduled" and C.Has(idc2), "it is looked at again, and counted down, once it gets a card")
  EndRoll(idc2)
  LR.Set("maxCards", 4)
  LR.Delete(rid); LR.Set("auto", false)
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end

  -- a failure in drawing gives every roll back to the game
  local idf = StartRoll("item:100")
  GROUP[4].rollID = idf; GROUP[4]:Show()
  Check(B.IsParked(GROUP[4]), "parked while all is well")
  local draw, fault = C.Draw, R.Fault
  local faults = {}
  R.Fault = function(area, err) faults[#faults + 1] = err end
  C.Draw = function() error("boom") end
  local idg = StartRoll("item:104")
  Check(C.Failed() and not B.IsParked(GROUP[4]) and GROUP[4].alpha == 1, "an error while drawing gives the game's frames back at once")
  Check(not C.Ready(), "and automatic choices stop")
  Check(#faults == 1, "and the error is reported once")
  C.Draw, R.Fault = draw, fault
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  GROUP[4]:Hide()
  c.TwichUIDB.modules.lootRolls = false; LR.Refresh()
  c.TwichUIDB.modules.lootRolls = true; LR.Refresh()
  Check(not C.Failed() and C.Ready(), "switching it off and on is a fresh start")
end

---------------------------------------------------------------------------
-- 7. Off, and the snapshot
---------------------------------------------------------------------------
do
  c.TwichUIDB.modules.lootRolls = false
  LR.Refresh()
  local snap = LR.Snapshot()
  Check(snap.on == false and snap.listening == false and snap.events == 0 and snap.cards == 0 and snap.parked == 0, "off: no listener, no card, nothing parked")
  Check(PendingTimers() <= 1, "off: no timer left running")
end

if failures > 0 then print(failures .. " failure(s)") os.exit(1) end
print("PASSED")
