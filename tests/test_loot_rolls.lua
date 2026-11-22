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
  SetTexture = function(s, v) s.texture = v end,
  SetTexCoord = function(s, ...) s.uv = { ... } end, SetBlendMode = function(s, mode) s.blend = mode end,
  SetClipsChildren = function(s, value) s.clips = value end,
  SetText = function(s, v) s.text = v end, GetText = function(s) return s.text end,
  GetStringWidth = function(s) return 40 end,
  SetWordWrap = function(s, v) s.wordWrap = v end, SetMaxLines = function(s, v) s.maxLines = v end,
  SetTextColor = function(s, r, g, b) s.color = { r, g, b } end,
  SetAlpha = function(s, a) s.alpha = a end, GetAlpha = function(s) return s.alpha end,
  EnableMouse = function(s, v) s.mouse = v and true or false end, IsMouseEnabled = function(s) return s.mouse end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  ClearAllPoints = function(s) s.points = {} end, SetPoint = function(s, ...) s.points[#s.points + 1] = { ... } end,
  SetScale = function(s, v) s.scale = v end, GetScale = function(s) return s.scale or 1 end,
  SetFont = function(s) return true end, SetDesaturated = function(s, v) s.desat = v end,
  GetParent = function(s) return s.parent end, GetFrameLevel = function(s) return s.frameLevel or 1 end,
  SetFrameLevel = function(s, value) s.frameLevel = value end,
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
c.ITEM_MIN_LEVEL = "Requires Level %d"
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
  ["item:106"] = { id = 106, name = "Silk Robe", quality = 2, class = 4, sub = 1, loc = "INVTYPE_ROBE", bind = 2, price = 90, icon = 1007, type = "Armor", subType = "Cloth" },
  ["item:107"] = { id = 107, name = "Mail Hauberk", quality = 2, class = 4, sub = 3, loc = "INVTYPE_CHEST", bind = 2, price = 90, icon = 1008, type = "Armor", subType = "Mail", redLine = "Mail" },
  ["item:108"] = { id = 108, name = "Lofty Cowl", quality = 3, class = 4, sub = 1, loc = "INVTYPE_HEAD", bind = 2, price = 90, icon = 1009, type = "Armor", subType = "Cloth", redLine = "Requires Level 60" },
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
  if it.redLine then lines[#lines + 1] = { leftText = it.redLine, leftColor = { r = 1, g = 0.1, b = 0.1 } } end
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
  "loot/Blizzard.lua", "loot/Cards.lua", "loot/Victory.lua", "loot/Main.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
local R = c.TwichUI
local Ru, LR, Ro, A, B, C = R.LootRules, R.LootRolls, R.LootRoll, R.LootAuto, R.LootBlizzard, R.LootCards
-- the game's own red-line count (gear/Data.lua), as the real one counts it
R.GearData = { RedLines = function(lines)
  local n = 0
  for _, l in ipairs(lines) do local k = l.leftColor if k and k.r > 0.9 and k.g < 0.3 and k.b < 0.3 then n = n + 1 end end
  return n
end }
R.GearHints = { Judge = function(link) return JUDGED[link] end, Noteworthy = function(j) return j and j.up == true end,
  DetailLines = function(j) return j and j.lines end }
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
  -- armor type
  local silk, mail = { classID = 4, subClassID = 1 }, { classID = 4, subClassID = 3 }
  local cloth = { type = "armor", value = 1 }
  Check(Ru.EvalCondition(cloth, silk) == true, "cloth armor matches cloth")
  Check(Ru.EvalCondition(cloth, mail) == false, "mail is not cloth")
  Check(Ru.EvalCondition({ type = "armor", value = 3 }, mail) == true, "mail armor matches mail")
  Check(Ru.EvalCondition(cloth, { classID = 2, subClassID = 1 }) == false, "a weapon is no kind of armor, whatever its sub-type number")
  Check(Ru.EvalCondition(cloth, { classID = 9, subClassID = 1 }) == false, "a recipe is no kind of armor")
  Check(Ru.EvalCondition(cloth, {}) == nil, "an item the game has not described is unknown")
  Check(Ru.EvalCondition(cloth, { classID = 4 }) == nil, "armor without its sub-type is unknown")
  Check(Ru.EvalCondition({ type = "armor", value = 3, negate = true }, silk) == true, "not mail matches cloth")
  Check(Ru.EvalCondition({ type = "armor", value = 3, negate = true }, {}) == nil, "a negated unknown armor type stays unknown")
  Check(Ru.CheckCondition({ type = "armor", value = 5 }) ~= nil and Ru.CheckCondition({ type = "armor", value = "cloth" }) ~= nil, "only the armor types offered are valid")
  Check(Ru.CheckCondition({ type = "armor", value = 4 }) == nil and Ru.CheckCondition(Ru.NewCondition("armor")) == nil, "plate is valid and a new condition is complete")
  Check(Ru.TYPES.armor.phrase({ value = 1 }) == "is cloth armor", "its sentence")
  -- can I equip it
  local can = { type = "equippable", value = true }
  Check(Ru.EvalCondition(can, { equippable = true }) == true, "equippable matches an item the player can equip")
  Check(Ru.EvalCondition(can, { equippable = false }) == false, "and not one they can't")
  Check(Ru.EvalCondition({ type = "equippable", value = false }, { equippable = false }) == true, "can't-equip matches an unwearable item")
  Check(Ru.EvalCondition(can, {}) == nil, "no fact is unknown, never a match")
  Check(Ru.EvalCondition({ type = "equippable", value = true, negate = true }, {}) == nil, "a negated unknown stays unknown")
  Check(Ru.CheckCondition({ type = "equippable", value = "yes" }) ~= nil and Ru.CheckCondition(Ru.NewCondition("equippable")) == nil, "it needs a true or false")
  Check(Ru.TYPES.equippable.phrase(can) == "is something I can equip" and Ru.TYPES.equippable.phrase({ value = false }) == "is something I can't equip", "its sentence")
  Check(Ru.Summary({ action = "pass", conditions = { { type = "equippable", value = false } } }):find("when the item is something I can't equip", 1, true) ~= nil, "it reads in a rule's summary")
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

-- Independent rule channels: No change never blocks the other outcome.
do
  local q = { type = "quality", op = "is", value = 4 }
  local function Rule(id, action, display, conditions)
    return { id = id, enabled = true, action = action, display = display, conditions = conditions or { q } }
  end
  for _, pair in ipairs({ { "need", "collapsed" }, { "greed", "expanded" }, { "pass", "collapsed" },
    { "none", "collapsed" }, { "none", "expanded" }, { "need", "none" } }) do
    local rule = Rule("lr1", pair[1], pair[2])
    Check(not Ru.Incomplete(rule), "valid independent action combination: " .. pair[1] .. "/" .. pair[2])
    Check(Ru.Decide({ rule }, { quality = 4 }).status == (pair[1] == "none" and "none" or "match"), "roll channel skips No change")
    Check(Ru.DecideDisplay({ rule }, { quality = 4 }).status == (pair[2] == "none" and "none" or "match"), "display channel skips No change")
  end
  local need, mini, full = Rule("lr1", "need"), Rule("lr2", "none", "collapsed"), Rule("lr3", "none", "expanded")
  local rules = { need, mini, full }
  Check(Ru.Decide(rules, { quality = 4 }).rule == need and Ru.DecideDisplay(rules, { quality = 4 }).rule == mini,
    "a high-priority Need and lower display-only match both win their own channels")
  rules = { mini, need, full }
  Check(Ru.Decide(rules, { quality = 4 }).rule == need and Ru.DecideDisplay(rules, { quality = 4 }).rule == mini,
    "a high-priority display-only match cannot suppress lower Need")
  Check(Ru.DecideDisplay({ full, mini }, { quality = 4 }).rule == full, "explicit Expanded overrides general Collapse by order")
  Check(Ru.DecideDisplay({ Rule("lr4", "none", "collapsed", { { type = "upgrade", value = true } }), full }, { quality = 4 }).status == "unknown",
    "unknown display conditions block only display precedence rather than guessing")
  Check(Ru.Decide({ Rule("lr4", "none", "collapsed", { { type = "upgrade", value = true } }), need }, { quality = 4 }).rule == need,
    "unknown display-only conditions never block a legitimate roll decision")
  Check(Ru.Decide({ Rule("lr4", "greed", nil, { { type = "upgrade", value = true } }), need }, { quality = 4 }).status == "unknown",
    "existing roll unknown/conflict behavior stays conservative")
  Check(Ru.Incomplete(Rule("lr4", "none", "none")) ~= nil and Ru.Incomplete(Rule("lr4", "need", "bogus")) ~= nil,
    "no-op and invalid presentation actions are flagged")
  Check(Ru.Summary(mini):find("Collapse", 1, true) and not Ru.Summary(mini):find("Automatically", 1, true),
    "display-only summaries never describe an automatic roll")
  Check(Ru.ActionSummary(Rule("lr4", "greed", "collapsed")) == "Greed · Collapsed", "combined action summary is unambiguous")
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
  local up = Rule("blank"); LR.SetAction(up, "greed")
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

  -- equippable and armor type, read from the roll the way the game gives it
  Fresh(); LR.Set("auto", true)
  local function Facts(link)
    local rid = StartRoll(link); local r = Ro.Find(rid)
    local obs = r.obs
    EndRoll(rid)
    return obs
  end
  Check(Facts("item:106").equippable == true, "gear with a clean tooltip can be equipped (a robe included)")
  Check(Facts("item:107").equippable == false, "gear with a red armor-type line cannot")
  Check(Facts("item:108").equippable == true, "a red level requirement alone does not count: the level fixes itself")
  Check(Facts("item:102").equippable == false and Facts("item:104").equippable == false, "a recipe and a trade good are not gear")
  local noTip = StartRoll("item:107", { noTooltip = true })
  Check(Ro.Find(noTip).obs.equippable == nil, "without a tooltip it is unknown, not yes")
  EndRoll(noTip)
  local cloth = Rule("blank"); LR.SetAction(cloth, "greed")
  LR.RemoveCondition(cloth, 1); LR.AddCondition(cloth, "armor"); LR.SetCondition(cloth, 1, { value = 1 })
  id = StartRoll("item:106"); roll = Ro.Find(id)
  Check(roll.state == "scheduled", "a cloth rule takes a cloth robe")
  EndRoll(id)
  id = StartRoll("item:107"); roll = Ro.Find(id)
  Check(roll.state == "pending", "and leaves mail alone")
  EndRoll(id)
  LR.SetCondition(cloth, 1, { negate = true })
  id = StartRoll("item:107"); roll = Ro.Find(id)
  Check(roll.state == "scheduled", "'not cloth' takes mail")
  EndRoll(id)
  LR.RemoveCondition(cloth, 1); LR.AddCondition(cloth, "equippable"); LR.SetCondition(cloth, 1, { value = false })
  id = StartRoll("item:107"); roll = Ro.Find(id)
  Check(roll.state == "scheduled", "a rule for what I can't equip takes the mail piece")
  EndRoll(id)
  id = StartRoll("item:106"); roll = Ro.Find(id)
  Check(roll.state == "pending", "and not the robe")
  EndRoll(id)

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
  C.Tick(0.4)
  Check(not fadeCard:IsShown() and not fadeCard.leaving and fadeCard.alpha == 1, "then hidden and free")
  Check(not c.TwichUILootCards:IsShown(), "and with no card left the stack goes too")
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
-- 6b. The sample-roll preview (settings): a made-up roll that plays through and sends nothing
---------------------------------------------------------------------------
do
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  rolled = {}
  local function Tick(seconds) local f = c.TwichUILootCardsPreview; local n = math.floor(seconds / 0.1 + 0.5) for _ = 1, n do f.scripts.OnUpdate(f, 0.1) end end
  local ok = C.PreviewStart()
  local f, card = c.TwichUILootCardsPreview, C.PreviewCard()
  Check(ok and f:IsShown() and card.name.text == "Verdant Scholar's Mantle", "a sample roll is shown on a card")
  Check(card.buttons.need:IsShown() and card.buttons.greed:IsShown() and card.buttons.pass:IsShown() and card.live, "with Need, Greed and Pass")
  Check(f.scale == LR.Get("scale") / 100, "at the player's size")
  Tick(2)
  Check(card.time.text ~= nil and card.view.state == "pending", "it counts down")
  card.buttons.greed.scripts.OnClick(card.buttons.greed)
  Check(card.view.state == "submitted" and card.view.choice == "greed" and card.status:IsShown(), "choosing shows the choice")
  Tick(1.5)
  Check(card.view.state == "resolved" and card.view.result and card.view.result.winner ~= nil, "then made-up results")
  Check(#rolled == 0 and #Ro.Rolls() == 0, "and no roll was made, and no roll exists")
  Tick(LR.Get("afterResult") + 1)
  Check(not f:IsShown(), "the card goes after a while, as a real one does")

  C.PreviewStart()
  card.buttons.need.scripts.OnClick(card.buttons.need); Tick(1.5)
  Check(card.view.result.winner.self == true, "Need in the sample wins the made-up roll")
  card.close.scripts.OnClick(card.close)
  Tick(0.2)
  Check(f:IsShown() and f.alpha < 1 and f.alpha > 0, "the x fades it out")
  Tick(1)
  Check(not f:IsShown() and f.alpha == 1, "and then it is gone")

  C.PreviewStart({ name = "Greed on green gear", action = "greed", delay = 3 })
  Check(card.view.state == "scheduled" and card.buttons.now:IsShown() and card.buttons.stop:IsShown() and card.line3.text:find("Greed on green gear", 1, true), "a rule's preview shows its countdown")
  card.buttons.stop.scripts.OnClick(card.buttons.stop)
  Check(card.view.state == "pending" and card.buttons.greed:IsShown() and card.view.autoNote ~= nil, "Stop gives the choice back")
  Tick(5)
  Check(card.view.state == "pending", "and nothing is chosen afterwards")
  C.PreviewStart({ name = "Pass", action = "pass", delay = 3 }); Tick(2)
  Check(card.view.state == "scheduled", "the countdown runs its delay")
  Tick(1.2)
  Check(card.view.state == "submitted" and card.view.choice == "pass", "and then 'chooses' what the rule says")
  C.PreviewStart({ name = "Now", action = "greed", delay = 9 })
  card.buttons.now.scripts.OnClick(card.buttons.now)
  Check(card.view.state == "submitted" and card.view.choice == "greed", "Roll now does it at once")
  Check(#rolled == 0, "a rule's preview sends nothing either")

  C.PreviewStart(); Tick(21)
  Check(card.view.state == "ended" and card.view.endReason == "expired", "an ignored sample runs out")
  C.PreviewStop()

  -- a real roll is never hidden by it, and takes its place
  C.PreviewStart()
  local idp = StartRoll("item:100")
  Check(not f:IsShown() and C.Card(Ro.Find(idp).key):IsShown(), "a real roll that starts takes the preview's place")
  Check(select(1, C.PreviewStart()) == false, "and no preview is offered while one is open")
  EndRoll(idp)
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  rolled = {}
end

---------------------------------------------------------------------------
-- 6c. Appearance: fading, the countdown bar, the price
---------------------------------------------------------------------------
do
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  LR.Set("animate", true)
  -- settings are checked
  Check(LR.Get("fadeIn") == 250 and LR.Get("fadeOut") == 450 and LR.Get("barTexture") == "eui:sheer" and LR.Get("barHeight") == 14, "the appearance defaults: Sheer, 14 high, fading")
  Check(LR.Get("barShine") == false, "the highlight along the top is off by default")
  Check(LR.Get("barColorHigh") == "ff91ad78" and LR.Get("barColorMid") == "ffd0aa60" and LR.Get("barColorLow") == "ffd18450"
    and LR.Get("barColorExpired") == "ffba5d55" and LR.Get("barTrack") == "ff211a16", "the default colors: sage, gold, ember, crimson, espresso")
  Check(LR.Set("fadeIn", 600) and LR.Get("fadeIn") == 600, "a fade time can be set")
  Check(not LR.Set("fadeIn", 5000) and not LR.Set("fadeOut", -1) and not LR.Set("barHeight", 3), "and out-of-range values are refused")
  Check(LR.Set("barColorHigh", "ff112233") and LR.Get("barColorHigh") == "ff112233", "a bar color can be set")
  Check(not LR.Set("barColorHigh", "red") and not LR.Set("barColorHigh", "ff1122") and not LR.Set("barColorHigh", 5), "and only AARRGGBB is accepted")
  Check(LR.Set("barTexture", "Smooth") and LR.Get("barTexture") == "Smooth" and not LR.Set("barTexture", "") and not LR.Set("barTexture", "a|b"), "a texture id is a plain name")
  LR.Set("barColorHigh", LR.DEFAULTS.barColorHigh); LR.Set("barTexture", LR.DEFAULTS.barTexture); LR.Set("fadeIn", 250)

  -- fade in: a new card starts clear and rises to solid; no sudden appearance
  local id = StartRoll("item:100")
  local card = C.Card(Ro.Find(id).key)
  Check(card:IsShown() and card.alpha == 0, "a new card starts fully clear")
  C.Tick(0.1)
  Check(card.alpha > 0 and card.alpha < 1, "and fades in")
  C.Tick(0.4)
  Check(card.alpha == 1, "to solid in the time chosen")
  -- fade out: the last card's fade is drawn (the stack stays until it is gone)
  EndRoll(id); LR.Set("afterResult", 2)
  Ro.Remove(Ro.Find(id))
  Check(card.leaving and c.TwichUILootCards:IsShown(), "the stack stays while the last card fades")
  C.Tick(0.2)
  Check(card.alpha > 0 and card.alpha < 1 and c.TwichUILootCards:IsShown(), "partway through")
  C.Tick(0.5)
  Check(not card:IsShown() and not c.TwichUILootCards:IsShown(), "then both are gone")
  -- the times are the player's
  LR.Set("fadeIn", 1000); LR.Set("fadeOut", 1000)
  id = StartRoll("item:100"); card = C.Card(Ro.Find(id).key)
  C.Tick(0.5)
  Check(card.alpha > 0 and card.alpha < 1, "a longer fade is still going at half a second")
  C.Tick(0.6)
  Check(card.alpha == 1, "and done at the end of it")
  LR.Set("fadeIn", 0); LR.Set("fadeOut", 0)
  EndRoll(id); Ro.Remove(Ro.Find(id))
  Check(not card:IsShown() and not card.leaving, "no fade-out time: gone at once")
  id = StartRoll("item:100"); card = C.Card(Ro.Find(id).key)
  Check(card.alpha == 1, "no fade-in time: there at once")
  EndRoll(id); Ro.Remove(Ro.Find(id))
  LR.Set("fadeIn", 250); LR.Set("fadeOut", 450)
  LR.Set("animate", false)
  id = StartRoll("item:100"); card = C.Card(Ro.Find(id).key)
  Check(card.alpha == 1, "Animate off overrides the times: no fading")
  EndRoll(id); Ro.Remove(Ro.Find(id))
  LR.Set("animate", true)

  -- the countdown bar: colors by time, one color, the rule's own; the player's texture
  local function Rgb(hex) return tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, tonumber(hex:sub(7, 8), 16) / 255 end
  local function Same(a, b, c1, d, e, f2) return math.abs(a - d) < 0.002 and math.abs(b - e) < 0.002 and math.abs(c1 - f2) < 0.002 end
  local r, g, b = C.BarColor(0.9, false)
  Check(Same(r, g, b, Rgb("ff91ad78")), "plenty of time: the plenty color")
  r, g, b = C.BarColor(0.4, false)
  Check(Same(r, g, b, Rgb("ffd0aa60")), "about half gone: the middle color")
  r, g, b = C.BarColor(0.1, false)
  Check(Same(r, g, b, Rgb("ffd18450")), "nearly out: the last color")
  LR.Set("barColorLow", "ff0000ff"); LR.Set("barColorRule", "ff00ff00")
  r, g, b = C.BarColor(0.1, false)
  Check(Same(r, g, b, 0, 0, 1), "a color the player chose is used")
  r, g, b = C.BarColor(0.1, true)
  Check(Same(r, g, b, 0, 1, 0), "a rule's countdown has its own color, whatever the time left")
  LR.Set("barShift", false)
  r, g, b = C.BarColor(0.1, false)
  Check(Same(r, g, b, Rgb("ff91ad78")), "with 'change color' off one color is kept to the end")
  r, g, b = C.BarColor(0, false, true)
  Check(Same(r, g, b, Rgb("ffba5d55")), "a roll that ran out has the run-out color")
  LR.Set("barShift", true); LR.Set("barColorLow", LR.DEFAULTS.barColorLow); LR.Set("barColorRule", LR.DEFAULTS.barColorRule)
  LR.Set("barShine", LR.DEFAULTS.barShine)

  R.MenuStyle = { StatusBars = { Resolve = function(id) if id == "Smooth" then return [[Interface\Smooth]], "ok" end return nil, "missing" end } }
  C.PreviewStart(); local pc = C.PreviewCard()
  LR.Set("barTexture", "Smooth"); LR.Set("barHeight", 20)
  C.PaintTimer(pc, pc.view)
  Check(pc.timer.fill.texture == [[Interface\Smooth]] and pc.timer:GetHeight() == 20, "the bar is drawn with the player's texture and height")
  LR.Set("barTexture", "Gone")
  C.PaintTimer(pc, pc.view)
  Check(pc.timer.fill.texture == [[Interface\Buttons\WHITE8x8]], "a texture that has gone is drawn flat, not blank")
  LR.Set("barShine", false); C.PaintTimer(pc, pc.view)
  Check(not pc.timer.hi:IsShown(), "the shine can be turned off")
  LR.Set("barShine", true); LR.Set("barTexture", LR.DEFAULTS.barTexture); LR.Set("barHeight", 14)
  C.PreviewStop(true)
  R.MenuStyle = nil

  -- the price: gold, silver and copper, each with its coin
  local text = C.CoinText(123456)
  Check(text:find("12", 1, true) and text:find("UI%-GoldIcon") and text:find("UI%-SilverIcon") and text:find("UI%-CopperIcon"), "a price shows gold, silver and copper with the game's coin pictures")
  Check(text:find("34", 1, true) and text:find("56", 1, true), "with each amount")
  local t2 = C.CoinText(1850)
  Check(not t2:find("GoldIcon") and t2:find("18", 1, true) and t2:find("SilverIcon") and t2:find("50", 1, true) and t2:find("CopperIcon"), "no gold: silver and copper only")
  local t3 = C.CoinText(10000)
  Check(t3:find("GoldIcon") and t3:find("SilverIcon") and t3:find("CopperIcon"), "an even amount still shows the lower coins")
  Check(C.CoinText(7):find("CopperIcon") and not C.CoinText(7):find("SilverIcon"), "copper alone")
  Check(C.CoinText(0) == nil and C.CoinText(nil) == nil and C.CoinText(-5) == nil and C.CoinText("x") == nil, "no price, no line")
  rolled = {}
end

---------------------------------------------------------------------------
-- 6d. Hover: what each part of a card explains
---------------------------------------------------------------------------
do
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(r) end
  rolled = {}
  local tip = { lines = {} }
  function tip:SetOwner(o, a) self.owner, self.lines, self.shown, self.lootRoll, self.link = o, {}, false, nil, nil end
  function tip:SetText(t) self.lines[#self.lines + 1] = t end
  function tip:AddLine(t) self.lines[#self.lines + 1] = t end
  function tip:Show() self.shown = true end
  function tip:Hide() self.shown = false end
  function tip:NumLines() return #self.lines end
  function tip:SetLootRollItem(id) self.lootRoll = id; self.lines[#self.lines + 1] = "ITEM TOOLTIP" end
  function tip:SetHyperlink(l) self.link = l; self.lines[#self.lines + 1] = "LINK TOOLTIP" end
  local real = c.GameTooltip
  c.GameTooltip = tip
  local function Text() return table.concat(tip.lines, " | ") end
  local function Enter(f) f.scripts.OnEnter(f) end

  -- a live roll: the game's own item tooltip, on the icon and the name
  JUDGED["item:100"] = { up = true, lines = { { " ", 1, 1, 1 }, { "Likely upgrade for Fury", 0.5, 0.7, 0.3, false }, { "Compared with Old Helm", 0.6, 0.6, 0.6, true },
    { "+12 Strength", 0.5, 0.7, 0.3, false } } }
  local id = StartRoll("item:100"); local roll = Ro.Find(id); local card = C.Card(roll.key)
  Enter(card.iconHit)
  Check(tip.shown and tip.lootRoll == id, "hovering the item shows the game's tooltip for the roll")
  -- the whole header line, not just the icon
  Check(card.iconHit.points[2] and card.iconHit.points[2][2] == card.body, "the hover area reaches across the name, not only the icon")
  card.iconHit.scripts.OnLeave(card.iconHit)
  Check(not tip.shown, "and it goes when the pointer leaves")

  -- the upgrade chip says why, in the gear comparison's own words
  local chip = card.pillTop.tip == C.PillTips.upgrade and card.pillTop or (card.pillBottom.tip == C.PillTips.upgrade and card.pillBottom)
  Check(chip and chip:IsShown(), "a Potential upgrade chip is shown")
  Enter(chip)
  Check(tip.shown and Text():find("Potential upgrade", 1, true) and Text():find("Likely upgrade for Fury", 1, true)
    and Text():find("Compared with Old Helm", 1, true) and Text():find("+12 Strength", 1, true), "hovering it explains why, from the gear comparison")
  Check(not Text():find(" | %s*$") and Text():find("never a reason to roll Need", 1, true), "and says it is a hint")
  JUDGED["item:100"].lines = nil
  Enter(chip)
  Check(Text():find("may be better than what you wear", 1, true), "with no detail to give it still says what the chip means")

  -- the choices
  card.buttons.need.onTip(card.buttons.need)
  Check(Text():find("Need", 1, true) and Text():find("intend to use", 1, true), "Need explains itself")
  card.buttons.greed.onTip(card.buttons.greed)
  Check(Text():find("nobody rolls Need", 1, true), "Greed explains itself")
  card.buttons.pass.onTip(card.buttons.pass)
  Check(Text():find("Nothing is rolled for you", 1, true), "Pass explains itself")
  -- the bar and the price
  Enter(card.timer)
  Check(Text():find("Time to roll", 1, true) and Text():find("you pass", 1, true), "the bar says what it counts")
  Enter(card.line3Hit)
  Check(Text():find("Vendor price", 1, true) and Text():find("UI%-CopperIcon"), "the price line shows the price with its coins")
  -- a roll that is over: the item's link
  EndRoll(id)
  roll.state = "ended"; roll.endReason = "expired"; Ro.Tell("updated", roll)
  tip.lootRoll = nil
  Enter(card.iconHit)
  Check(tip.shown and tip.link == "item:100", "once the roll is over the item's link is shown instead")
  Check(card.timer:IsShown(), "a roll that ran out shows its bar, spent")
  Enter(card.timer)
  Check(Text():find("Ran out", 1, true), "and the bar says it ran out")
  Ro.Remove(roll)
  JUDGED["item:100"] = nil

  -- a rule's countdown
  LR.Set("auto", true)
  local _, rid = LR.Create("blank"); LR.SetAction(rid, "greed"); LR.RemoveCondition(rid, 1); LR.AddCondition(rid, "item"); LR.SetCondition(rid, 1, { id = 101 }); LR.SetEnabled(rid, true)
  local id2 = StartRoll("item:101"); local r2 = Ro.Find(id2); local c2 = C.Card(r2.key)
  Check(r2.state == "scheduled" and c2.buttons.now:IsShown(), "a rule is counting down")
  c2.buttons.now.onTip(c2.buttons.now)
  Check(Text():find("Roll now", 1, true), "Roll now explains itself")
  c2.buttons.stop.onTip(c2.buttons.stop)
  Check(Text():find("Cancels the automatic choice", 1, true), "Stop explains itself")
  Enter(c2.timer)
  Check(Text():find("Rule countdown", 1, true), "the bar says a rule is counting down")
  local autoPill = c2.pillTop.tip == C.PillTips.auto and c2.pillTop or c2.pillBottom
  Enter(autoPill)
  Check(Text():find("will choose it for you", 1, true), "the Auto chip explains the rule")
  EndRoll(id2); Ro.Remove(r2); LR.Delete(rid); LR.Set("auto", false)

  -- a sample card has a made-up item tooltip, and the made-up reasons
  C.PreviewStart(); local pc = C.PreviewCard()
  Enter(pc.iconHit)
  Check(Text():find("Verdant Scholar's Mantle", 1, true) and Text():find("made up for the preview", 1, true) and tip.lootRoll == nil and tip.link == nil,
    "a sample's item tooltip is made up and reads no roll")
  local pchip = pc.pillTop.tip == C.PillTips.upgrade and pc.pillTop or pc.pillBottom
  Enter(pchip)
  Check(Text():find("Likely upgrade for Arcane", 1, true), "and so is its upgrade explanation")
  C.PreviewStop(true)
  c.GameTooltip = real
  rolled = {}
end

-- Mini active cards use the same choices and timers; overrides belong to keys.
do
  for _, roll in ipairs({ unpack(Ro.Rolls()) }) do Ro.Remove(roll) end
  for _, rule in ipairs(LR.List()) do LR.Delete(rule.id) end
  LR.Set("auto", false); LR.Set("animate", false); LR.Set("maxCards", 4)
  local ok, display = LR.Create("blank")
  Check(ok and LR.Rule(display).action == "none" and LR.Rule(display).display == "none" and LR.Rule(display).incomplete,
    "new blank rule offers independent No change outcomes and flags no-op")
  LR.SetDisplay(display, "collapsed"); LR.SetEnabled(display, true)
  Check(not LR.Rule(display).incomplete and c.TwichUIDB.ui.lootRolls.rules[1].display == "collapsed",
    "display-only action saves and reads independently of roll actions")
  local _, copy = LR.Duplicate(display)
  Check(LR.Rule(copy).display == "collapsed" and LR.Rule(copy).action == "none", "copy/reload view preserves both action fields")
  LR.Delete(copy)
  local id = StartRoll("item:100"); local roll = Ro.Find(id); local card = C.Card(roll.key)
  local deadline = roll.deadline
  Check(card.compact and card.h == 90 and roll.state == "pending" and roll.choice == nil and not roll.auto,
    "display-only rule collapses with automation off, without making a choice")
  for _, key in ipairs({ "need", "greed", "pass" }) do
    Check(card.buttons[key].shown and card.buttons[key].w == 68 and card.buttons[key].h == 34, "Mini keeps safe labeled choice targets")
  end
  Check(card.timer.h == 6 and card.time.shown and not card.line3.shown and not card.close.shown,
    "Mini uses a thin authoritative countdown and omits full details")
  local fullWidth = card.timer.fill.w
  Advance(2); C.Tick(0.05)
  Check(card.timer.fill.w < fullWidth and card.name.w >= 250, "Mini timer visibly shrinks while the item has a wide name region")
  local before = #rolled
  card.toggle.scripts.OnClick(card.toggle)
  Check(not card.compact and card.h > 120 and Ro.Find(id) == roll and roll.manualDisplay == "expanded",
    "manual expansion reuses the same roll and card")
  card.toggle.scripts.OnClick(card.toggle)
  Check(card.compact and roll.deadline == deadline and #rolled == before and roll.choice == nil,
    "collapse changes no deadline, event, choice or rule")
  Check(LR.Rule(display).display == "collapsed", "manual override never writes saved rules")
  local id2 = StartRoll("item:101"); local other = Ro.Find(id2); local fullCard = C.Card(other.key)
  Check(not fullCard.compact and fullCard.baseY == card.h + LR.Get("spacing"), "mixed stack uses actual Mini height")
  Ro.SetDisplay(roll, "expanded")
  Check(fullCard.baseY == card.h + LR.Get("spacing"), "instant expansion reflows following cards without duplicate slots")
  Ro.SetDisplay(roll, "collapsed")
  local _, auto = LR.Create("greenGear"); LR.SetEnabled(auto, true); LR.Set("auto", true)
  Check(roll.state == "scheduled" and roll.auto.action == "greed", "lower roll rule acts independently of higher display-only match")
  local fireAt = roll.auto.fireAt
  LR.SetDisplay(display, "expanded"); Ro.SetDisplay(roll, "collapsed")
  Check(roll.auto.fireAt == fireAt and card.compact, "display edits and manual overrides do not restart automatic countdown")
  Check(card.buttons.now.shown and card.buttons.stop.shown, "Mini preserves auto countdown controls")
  card.buttons.stop.scripts.OnClick(card.buttons.stop)
  Check(roll.state == "pending" and card.buttons.need.shown, "Stop restores the normal manual controls in Mini")
  LR.Set("auto", false)
  for _, key in ipairs({ "need", "greed", "pass" }) do
    local rid = StartRoll("item:106"); local rr = Ro.Find(rid); Ro.SetDisplay(rr, "collapsed")
    local cc = C.Card(rr.key); local n = #rolled
    cc.buttons[key].scripts.OnClick(cc.buttons[key])
    Check(#rolled == n + 1 and rr.choice == key and rr.state == "submitted", "compact " .. key .. " uses the existing submission path")
    EndRoll(rid); Ro.Remove(rr)
  end
  local restricted = StartRoll("item:100", { canNeed = false, reasonNeed = 1 }); local rr = Ro.Find(restricted)
  Ro.SetDisplay(rr, "collapsed"); local cc = C.Card(rr.key); before = #rolled
  cc.buttons.need.scripts.OnClick(cc.buttons.need)
  Check(#rolled == before and rr.choice == nil and cc.buttons.need.state == "unavailable", "Mini cannot bypass a restricted Need")
  local remaining = Ro.Remaining(rr)
  Advance(0.5); C.Tick(0.05)
  Check(C.View(rr).remaining < remaining and cc.time.text == string.format("%ds", math.ceil(Ro.Remaining(rr))),
    "Mini reads the authoritative time after elapsed ticks")
  for _, r in ipairs({ unpack(Ro.Rolls()) }) do EndRoll(r.rollID); Ro.Remove(r) end
  for _, rule in ipairs(LR.List()) do LR.Delete(rule.id) end
  LR.Set("animate", true); LR.Set("auto", false)
end

---------------------------------------------------------------------------
-- Victory: actual relay event over synthetic client frames; no win inference.
---------------------------------------------------------------------------
do
  local V = R.LootVictory
  active = {}
  -- Clean the model/automation left by the preceding regression scenarios.
  c.TwichUIDB.modules.lootRolls = false; LR.Refresh()
  LR.Set("auto", false); LR.Set("maxCards", 4); LR.Set("afterResult", 8)
  local native, sounds = {}, {}
  c.AlertFrame = c.CreateFrame("Frame", "AlertFrame", c.UIParent)
  function c.AlertFrame:IsProtected() return false end
  c.AlertFrame:RegisterEvent("LOOT_ITEM_ROLL_WON")
  c.AlertFrame:RegisterEvent("SHOW_LOOT_TOAST")
  c.AlertFrame:RegisterEvent("ACHIEVEMENT_EARNED")
  c.AlertFrame:SetScript("OnEvent", function(_, event, ...) native[#native + 1] = { event, ... } end)
  c.PlaySoundFile = function(path, channel) sounds[#sounds + 1] = { path, channel } end
  c.GetCVarBool = function() return true end
  c.TwichUIDB.modules.lootRolls = true; LR.Refresh()
  LR.Set("victory", true); LR.Set("victoryIntensity", "subtle"); LR.Set("victorySound", true)
  Check(V.Listening() and not c.AlertFrame:IsEventRegistered("LOOT_ITEM_ROLL_WON"), "victory owns only the native winning event")
  Check(c.AlertFrame:IsEventRegistered("SHOW_LOOT_TOAST") and c.AlertFrame:IsEventRegistered("ACHIEVEMENT_EARNED"), "unrelated native alerts stay registered")
  local function Step(seconds)
    for _ = 1, math.ceil(seconds / 0.05) do
      Advance(0.05)
      for _, f in ipairs(FRAMES) do
        if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.05) end
      end
    end
  end
  local function Win(link, kind, value) Fire("LOOT_ITEM_ROLL_WON", link, 1, kind, value, false) end
  local function NewRoll(link, choice)
    local id = 700 + #rolled + #Ro.Rolls()
    rolls[id] = { link = link, ends = NOW + 30, canNeed = true, canGreed = true }
    active[id] = true; Fire("START_LOOT_ROLL", id, 30000, 9000 + id)
    local roll = Ro.Find(id)
    if choice then Check(Ro.Submit(roll, choice, "player"), "submit test choice") end
    return roll
  end
  local roll = NewRoll("item:100", "need")
  local same = C.Card(roll.key)
  Check(V.Count() == 0, "selecting Need never starts a victory")
  Win("item:100", 1, 87)
  local e = V.Entries()[1]
  Check(e and e.key == roll.key and C.Card(roll.key) == same, "confirmed Need reuses the existing card at its stack slot")
  local f = same.victory
  Check(not same.body.shown and not same.timer.shown, "old item text and roll controls cannot ghost through the new banner")
  Check(f and f.entry.value == 87 and f.emblem.texture:find("emblem_need.tga", 1, true), "Need value and approved emblem")
  Check(not C.Shows(roll) and not C.Has(roll.rollID), "victory cannot authorize another automatic choice or park live controls")
  Check(f.footer == nil, "victory has no redundant footer message or inventory claim")
  Fire("LOOT_ITEM_ROLL_WON", "item:100", 1, 1, 87, false)
  Check(V.Count() == 1, "duplicate native winner event creates no second card")
  Step(0.25); Check(f.phase == "burst" and f.header.alpha > 0 and f.header.alpha < 1, "resolution advances into a restrained title reveal")
  Step(0.3); Check(#sounds == 1 and sounds[1][2] == "SFX", "one reveal sound on SFX")
  Step(1.35)
  Check(f.phase == "static" and not f.scripts.OnUpdate and f.timer, "decorative updates stop at the static hold")
  Check(f.sweepCore.alpha == 0 and f.arrivalGlint.alpha == 0 and f.particles[1].alpha == 0, "effects end without loops")
  Step(0.8); Win("item:100", 1, 87)
  Check(V.Count() == 1 and #sounds == 1, "duplicate after the replay window still matches the completed roll")
  local started = e.started
  C.Refresh(); Check(e.started == started, "redraw never restarts the animation or sound")
  Step(3.6)
  Check(V.Count() == 0 and not f.shown and not f.timer and not f.scripts.OnUpdate, "timeout recycles all animation work")
  Check(not C.Card(roll.key), "old resolved roll does not reappear after its victory")
  Ro.Remove(roll)

  -- Losses and Pass remain ordinary results; history by itself does not race the native event.
  for _, choice in ipairs({ "need", "greed", "pass" }) do
    local r = NewRoll("item:101", choice)
    r.result = { rolls = {}, winner = { name = "Other", self = false, choice = "need", roll = 99 } }
    Ro.Resolve(r, "history"); Ro.Tell("updated", r)
    Check(V.Count() == 0, choice .. " loss/pass has no celebration")
    Ro.Remove(r)
  end
  local n = #native
  Win("item:101", 3, 42)
  Check(#native == n + 1 and V.Count() == 0, "unsupported roll type falls back to the saved native handler")
  Fire("ACHIEVEMENT_EARNED", 42); Fire("SHOW_LOOT_TOAST", "item", "item:101", 1)
  Check(#native == n + 3, "achievement and acquisition alerts pass untouched")

  -- No record and missing metadata: confirmed late result still has its own bounded entry.
  Win("item:999", 2, nil)
  e = V.Entries()[1]; f = e and e.card and e.card.victory
  Check(e and e.name == "Loot" and not e.value and f.method.text == "Greed roll", "late Greed win tolerates missing metadata and roll value")
  Check(f.emblem.texture:find("emblem_greed.tga", 1, true), "Greed uses its supplied emblem")
  Step(6.2)

  LR.Set("victoryIntensity", "off"); LR.Set("victorySound", false)
  local soundCount = #sounds
  for q = 0, 6 do
    Check(V.Preview(q % 2 == 0 and "need" or "greed", q), "preview works without real rolls")
    local pc = V.PreviewCard(); local pf = pc.victory
    Check(pf.header.alpha == 1 and not pf.scripts.OnUpdate, "animation off is static and readable")
    Check(q < 2 or q > 5 or pf.halo.texture:find("halo_", 1, true), "rarity art selected safely")
    Step(4.1)
    Check(not pf.shown and not pf.timer and not pf.scripts.OnUpdate, "preview playback cleans up")
  end
  Check(#sounds == soundCount, "sound off stays silent through repeated previews")
  Check(V.PoolSize() <= C.PoolSize() + 1, "artwork frames are pooled, including one preview")
  LR.Set("victoryIntensity", "subtle")
  LR.Set("victorySound", true)
  c.GetCVarBool = function() return false end
  V.Preview("need", 4); Step(0.6)
  Check(#sounds == soundCount, "global sound switch is respected")
  V.PreviewStop(); c.GetCVarBool = function() return true end
  c.PlaySoundFile = function() error("missing sound") end
  V.Preview("greed", 5); Step(1.9)
  Check(V.PreviewCard().victory.phase == "static", "unsupported audio cannot interrupt the renderer")
  V.PreviewStop()
  c.PlaySoundFile = function(path, channel) sounds[#sounds + 1] = { path, channel } end

  -- Production preview checks: layered lighting, one shared timeline, and resets.
  local fxNames = { "headerHaze", "iconHaze", "headerBloom", "emblemBurst", "iconBloom", "sweepHaze", "sweepCore", "sweepTail", "radiance", "arrivalGlint" }
  local function FXClear(pf, ambient)
    for _, name in ipairs(fxNames) do
      if (ambient or (name ~= "headerHaze" and name ~= "iconHaze")) and pf[name].alpha ~= 0 then return false end
    end
    for _, glint in ipairs(pf.trimGlints) do if glint.alpha ~= 0 then return false end end
    for _, particle in ipairs(pf.particles) do if particle.alpha ~= 0 then return false end end
    return true
  end
  LR.Set("victoryIntensity", "subtle")
  local soundBeforeSeek = #sounds
  Check(V.Preview("need", 2), "lighting preview starts")
  local pc = V.PreviewCard(); local pf = pc.victory
  Check(#pf.base.pieces == 15 and pf.h == 218 and pf.title.points[1][5] == -24 and pf.emblem.points[1][5] == -64,
    "lighting integration preserves approved frame and heading geometry")
  Check(pf.icon.points[1][3] == -93 and pf.name.points[1][3] == -84 and pf.method.points[1][3] == -134
    and pf.badge.h == 29 and pf.badge.points[1][4] == 230 and pf.footer == nil,
    "item and conditional footer composition remain unchanged")
  Check(pf.laurels[1].points[1][2] == pf.title and pf.laurels[2].points[1][2] == pf.title,
    "laurels still follow the centered measured title")
  Check(pf.atmosphere.frameLevel < pf.header.frameLevel and pf.atmosphere.frameLevel < pf.content.frameLevel
    and pf.railCanvas.frameLevel < pf.header.frameLevel and pf.rail.clips == false
    and pf.effects.frameLevel < pf.header.frameLevel and pf.effects.frameLevel < pf.content.frameLevel and not pf.effects.mouse,
    "feathered effects escape without scissoring, intercepting input or covering text")
  for _, name in ipairs(fxNames) do
    Check(pf[name].texture:find("victory\\fx\\fx_", 1, true) and pf[name].blend == "ADD" and pf[name].uv,
      "supplemental texture uses individual runtime file, additive blend and measured UV: " .. name)
  end
  for _, t in ipairs({ 0, 0.15, 0.40, 0.70, 1.00, 1.45, 1.85, 3.75, 5.95, 6.15 }) do
    Check(V.PreviewAt(t), "production celebration pose " .. t)
    if t == 0 then
      Check(pf.header.alpha == 0 and FXClear(pf, true), "time zero is intentionally transparent with all lighting reset")
    elseif t == 0.15 then
      Check(pf.headerHaze.alpha > 0.20 and pf.headerBloom.alpha == 0, "ignition precedes the title bloom")
    elseif t == 0.40 then
      Check(pf.headerBloom.alpha > 0.35 and pf.headerBloom.alpha < 0.40 and pf.radiance.alpha == 0,
        "Subtle keeps a quiet heading without the Full radiant burst")
    elseif t == 0.70 then
      local x = pf.sweepCore.points[1][4]
      Check(pf.sweepCore.alpha == 0.75 and pf.sweepHaze.alpha == 0.28 and math.abs(x - 230) < 0.0001
        and pf.sweepTail.points[1][4] == x - 48, "one bright center, soft base and short tail travel together")
    elseif t == 1.00 then
      Check(pf.iconBloom.alpha == 0.35 and pf.arrivalGlint.alpha > 0.40 and pf.sweepCore.alpha == 0
        and pf.halo.alpha > pf.haloRest, "item arrival shifts attention to the icon with its actual rarity accent")
      local visible = 0
      for _, particle in ipairs(pf.particles) do if particle.alpha > 0 then visible = visible + 1 end end
      Check(visible == 4, "Subtle has four controlled sparks/motes")
    elseif t == 1.45 then
      Check(pf.headerBloom.alpha == 0 and pf.radiance.alpha == 0 and pf.iconBloom.alpha > 0 and pf.iconBloom.alpha < 0.10,
        "afterglow decays smoothly rather than disappearing abruptly")
    elseif t == 1.85 or t == 3.75 then
      Check(FXClear(pf, false) and pf.headerHaze.alpha == 0.12 and pf.iconHaze.alpha == 0.09
        and pf.halo.alpha == pf.haloRest and pf.alpha == 1, "completed state retains only restrained static atmosphere")
    elseif t == 5.95 then
      Check(pf.phase == "fade" and pf.alpha > 0 and pf.alpha < 1, "configured hold ends with the existing fade")
    elseif t == 6.15 then
      Check(pf.alpha == 0, "Normal completes after the 1.85-second reveal and configured hold")
    end
  end
  Check(#sounds == soundBeforeSeek and not pf.scripts.OnUpdate, "paused captures remain silent and idle")
  Check(V.Preview("need", 2) and FXClear(pf, true) and pf.scripts.OnUpdate, "replay resets all layers at zero")
  Step(0.35)
  Check(#sounds == soundBeforeSeek + 1, "one sound at 0.30 seconds accompanies the radiant burst")
  Step(1.51)
  Check(not pf.scripts.OnUpdate and pf.timer and pf.phase == "static" and math.abs(pf.entry.total - 6.15) < 0.0001,
    "clock-driven motion stops after afterglow; idle hold has no updater")
  V.PreviewStop()
  LR.Set("victoryIntensity", "full")
  V.Preview("greed", 5); V.PreviewAt(0.40)
  Check(pf.headerBloom.alpha > 0.98 and pf.emblemBurst.alpha > 0.78 and pf.radiance.alpha > 0.93,
    "Full has a distinct synchronized white-gold climax")
  Check(pf.particles[5].alpha == 1 and pf.particles[6].alpha == 1 and pf.particles[7].alpha == 1,
    "three prominent stars peak with the radiant burst")
  Check(pf.particles[5].points[1][5] > 0 or pf.particles[6].points[1][5] > 0,
    "Full stars extend above the frame without clipping")
  V.PreviewAt(0.55)
  local visible = 0
  for _, particle in ipairs(pf.particles) do if particle.alpha > 0 then visible = visible + 1 end end
  Check(visible == 8 and #pf.particles == 12, "eight particles overlap the burst within a bounded twelve-slot pool")
  Check(pf.entry.sampleLines[1] == "Shoulder · Legendary" and pf.entry.sellPrice == nil,
    "sample metadata stays consistent with its selected item")
  V.PreviewAt(1.00)
  Check(pf.iconBloom.alpha == 0.85 and pf.halo.alpha == pf.haloRest + 0.22, "Full arrival reinforces the real rarity ring")
  V.PreviewStop()
  LR.Set("victoryIntensity", "off"); V.Preview("need", 2)
  Check(FXClear(pf, true) and pf.atmosphere.alpha == 0 and not pf.scripts.OnUpdate,
    "Off hides every supplemental FX texture with no animation updater")
  V.PreviewAt(3.85); Check(pf.alpha == 1 and FXClear(pf, true), "Off keeps the original clean card and static hold")
  V.PreviewAt(4); Check(pf.alpha == 0, "Off exits without a decorative fade")
  V.PreviewStop()

  -- All variants replay the same pooled renderer, including quick interruptions.
  local longName = "Stormrend Titanblade of the Unbroken Oath of the Eternal Watchers"
  local poolBefore = V.PoolSize()
  pf.name.GetStringWidth = function(self) return #self.text * 8 end
  for _, intensity in ipairs({ "off", "subtle", "full" }) do
    LR.Set("victoryIntensity", intensity)
    for _, choice in ipairs({ "need", "greed" }) do
      for quality = 2, 5 do
        local upgrade = quality % 2 == 0
        Check(V.Preview(choice, quality, { name = longName, upgrade = upgrade }) and FXClear(pf, true),
          "consecutive preview resets every layer before playback")
        Check(pf.name.text ~= longName and pf.name.text:sub(-3) == "..." and #pf.name.text * 8 <= pf.name.w
          and not pf.name.wordWrap and pf.name.maxLines == 1, "long names remain bounded with an ellipsis")
        pf.hit.scripts.OnEnter(pf.hit)
        Check(c.GameTooltip.text == longName, "hover preserves the complete item name")
        Check(pf.badge.shown == upgrade and pf.upgrade.shown == upgrade, "upgrade visibility follows sample state on reuse")
        Check(pf.emblem.texture:find("emblem_" .. choice, 1, true) and pf.entry.quality == quality,
          "both roll types and all rarities retain their artwork")
        Step(0.95)
        if intensity == "off" then Check(FXClear(pf, true), "Off stays free of supplemental effects")
        else Check(not FXClear(pf, true), "active preview has visible lighting") end
      end
    end
  end
  Check(V.PoolSize() == poolBefore and V.Count() == 0, "quick previews reuse one pool without real results")
  V.Preview("greed", 5, { name = string.rep("é", 50) })
  Check(pf.name.text:sub(-5) == "é...", "localized truncation preserves whole UTF-8 characters")
  pf.name.GetStringWidth = nil
  LR.Set("showUpgrade", false); V.Preview("greed", 5, { upgrade = true })
  Check(not pf.badge.shown and not pf.upgrade.shown, "global upgrade setting still hides the indicator")
  LR.Set("showUpgrade", true); V.Preview("need", 2)
  Check(pf.badge.shown and pf.name.text ~= longName, "fresh previews restore sample state")
  V.PreviewStop()

  -- Serialize excess wins while bounding active frames; each gets its full hold.
  LR.Set("maxCards", 1); LR.Set("victoryIntensity", "off")
  local before = V.PoolSize()
  for i = 1, 7 do Win("item:" .. (800 + i), i % 2 + 1, 40 + i) end
  Check(V.Count() == 7 and C.CardCount() == 1, "rapid wins queue without overlapping")
  for i = 1, 7 do Step(4.1) end
  Check(V.Count() == 0 and V.PoolSize() <= before + 1, "queued wins drain with a bounded pool (one retiring slot)")
  -- Overflow is delivered natively, never silently dropped.
  n = #native
  for i = 1, V.MAX_QUEUE + 1 do Win("item:" .. (900 + i), 1, 50) end
  Check(V.Count() == V.MAX_QUEUE and #native == n + 1, "bounded queue overflow keeps native result")
  LR.Set("victory", false)
  Check(not V.Listening() and V.Count() == 0 and c.AlertFrame:IsEventRegistered("LOOT_ITEM_ROLL_WON"), "disable restores native registration and clears queue")
  Check(#native == n + 1 + V.MAX_QUEUE, "disable replays every unfinished accepted result to native")
  n = #native; Win("item:100", 1, 99)
  Check(#native == n + 1 and V.Count() == 0, "disabled feature leaves original behavior")
  LR.Set("victory", true)
  Check(V.Listening(), "re-enable takes ownership once")
  c.InCombatLockdown = function() return true end
  Win("item:102", 2, 66); Step(4.1)
  Check(V.Count() == 0, "unprotected synthetic card completes in combat without protected actions")
  c.InCombatLockdown = function() return false end
  LR.Set("victory", false)
  function c.AlertFrame:IsProtected() return true end
  LR.Set("victory", true)
  Check(not V.Listening(), "protected native host is never modified")
  function c.AlertFrame:IsProtected() return false end
  c.AlertFrame:UnregisterEvent("LOOT_ITEM_ROLL_WON")
  V.Sync(); Check(not V.Listening(), "another replacement's event ownership is respected")
  c.AlertFrame:RegisterEvent("LOOT_ITEM_ROLL_WON"); V.Sync()
  Check(V.Listening(), "supported native path can resume")
  LR.Set("victoryIntensity", "subtle")
  LR.Set("maxCards", 2)
  Win("item:7101", 1, 77); Win("item:7102", 2, 88)
  Step(0.5)
  Check(not C.PlaceStart() and not C.PreviewStart(), "placement and sample rolls cannot cover a real celebration")
  LR.Set("victoryIntensity", "off")
  for _, result in ipairs(V.Entries()) do Check(not result.card.victory.scripts.OnUpdate and FXClear(result.card.victory, true), "turning animation off immediately clears lighting and updates") end
  LR.Set("maxCards", 1)
  Step(8.5)
  Check(V.Count() == 0, "reducing max cards suspends and resumes queued animation safely")
  local a, b = NewRoll("item:108", "need"), NewRoll("item:108", "need")
  n = #native; Win("item:108", 1, 99)
  Check(#native == n + 1 and V.Count() == 0, "ambiguous identical drops keep native results instead of guessing")
  Ro.Remove(a); Ro.Remove(b)
  n = #native
  local draw, fault, caught = V.Draw, R.Fault, nil
  R.Fault = function(_, err) caught = err end
  V.Draw = function() error("synthetic drawing failure") end
  Win("item:7199", 1, 70)
  Check(C.Failed() and not V.Listening() and #native == n + 1 and V.Count() == 0,
    "drawing failure delivers current result once and restores native registration")
  Check(caught and caught:find("synthetic drawing failure", 1, true), "render failure is reported")
  V.Draw, R.Fault = draw, fault
  c.TwichUIDB.modules.lootRolls = false; LR.Refresh(); active = {}
  c.TwichUIDB.modules.lootRolls = true; LR.Refresh()
  LR.Set("victoryIntensity", "off")
  Check(LR.Get("victory") and LR.Get("victoryIntensity") == "off" and c.TwichUIDB.ui.lootRolls.victoryIntensity == "off", "settings use existing persisted profile values")
  LR.Set("victoryIntensity", "subtle"); LR.Set("maxCards", 4)
end

---------------------------------------------------------------------------
-- Compact victories: per-instance attribution, toggles and pooled FX lifecycle.
---------------------------------------------------------------------------
do
  local V = R.LootVictory
  local native = 0
  local function Reset()
    V.Disable(false)
    for _, r in ipairs({ unpack(Ro.Rolls()) }) do EndRoll(r.rollID); Ro.Remove(r) end
    for _, rule in ipairs(LR.List()) do LR.Delete(rule.id) end
    c.AlertFrame:SetScript("OnEvent", function() native = native + 1 end)
    LR.Set("auto", false); LR.Set("animate", false); LR.Set("maxCards", 4)
    LR.Set("victoryIntensity", "full"); LR.Set("victorySound", false)
    V.Sync()
  end
  local function Step(seconds)
    for _ = 1, math.ceil(seconds / 0.05) do
      Advance(0.05)
      for _, f in ipairs(FRAMES) do if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.05) end end
    end
  end
  local function Win(link, value) Fire("LOOT_ITEM_ROLL_WON", link, 1, 1, value or 87, false) end
  Reset()
  local _, rule = LR.Create("blank"); LR.SetDisplay(rule, "collapsed"); LR.SetEnabled(rule, true)
  local id = StartRoll("item:100"); local roll = Ro.Find(id); local card = C.Card(roll.key)
  Check(card.compact and roll.choice == nil, "display-only rule leaves a compact manual roll")
  Ro.SetDisplay(roll, "expanded"); Win("item:100")
  local e = V.Entries()[1]; local f = e.card.victory
  Check(e.displayMode == "expanded" and e.manualDisplay == "expanded" and e.card == card and not f.compact,
    "manual expanded override carries to the same roll's confirmed victory")
  Step(0.55)
  local started, total, sounded = e.started, e.total, e.sounded
  card.toggle.scripts.OnClick(card.toggle)
  Check(f.compact and math.abs(card.h - 80 * 384 / 460) < 0.001 and e.displayMode == "collapsed",
    "victory toggle immediately reflows the existing card to Mini")
  Check(e.started == started and e.total == total and e.sounded == sounded and f.scripts.OnUpdate and V.Count() == 1,
    "mid-reveal toggle preserves timeline, sound state, result and instance")
  Step(1.4)
  local timer = f.timer
  card.toggle.scripts.OnClick(card.toggle)
  Check(not f.compact and f.timer == timer and not f.scripts.OnUpdate and e.started == started,
    "static toggle keeps its original dismissal timer and no idle updater")
  Step(4.4)
  Check(V.Count() == 0 and not f.shown and not f.timer and not f.scripts.OnUpdate and (not Ro.ByKey(roll.key) or roll.manualDisplay == nil),
    "finished victory clears the temporary override and all animation work")

  Reset(); LR.Set("victoryIntensity", "off")
  local a = Ro.Find(StartRoll("item:100")); Ro.SetDisplay(a, "collapsed")
  local b = Ro.Find(StartRoll("item:101")); Ro.SetDisplay(b, "expanded")
  EndRoll(a.rollID); Ro.Remove(a)
  Check(V.RetainedDisplays() == 1, "departed roll retains one bounded presentation snapshot")
  Win("item:101", 92); Win("item:100", 81)
  local modes = {}
  for _, entry in ipairs(V.Entries()) do modes[entry.link] = entry.displayMode end
  Check(V.Count() == 2 and modes["item:100"] == "collapsed" and modes["item:101"] == "expanded",
    "late compact and simultaneous expanded victories cannot exchange presentation")
  Check(V.RetainedDisplays() == 0, "accepted late winner consumes its matching presentation")
  local first, second = V.Entries()[1].card, V.Entries()[2].card
  if first.baseY > second.baseY then first, second = second, first end
  Check(second.baseY == first.baseY + first.h + LR.Get("spacing"), "mixed victory stack uses actual heights")
  Step(4.2)
  Check(V.Count() == 0, "both static victories expire without lingering animation")

  Reset()
  a = Ro.Find(StartRoll("item:100")); Ro.SetDisplay(a, "collapsed")
  EndRoll(a.rollID); Ro.Remove(a)
  b = Ro.Find(StartRoll("item:100")); Ro.SetDisplay(b, "expanded")
  local n = native; Win("item:100")
  Check(native == n + 1 and V.Count() == 0, "identical live and departed drops fall back natively rather than borrow a preference")
  Reset(); LR.Set("victoryIntensity", "off")
  a = Ro.Find(StartRoll("item:100")); Ro.SetDisplay(a, "collapsed")
  EndRoll(a.rollID); Ro.Remove(a); Advance(V.DISPLAY_RETENTION + 1)
  Win("item:100")
  Check(V.Entries()[1].displayMode == "expanded" and V.RetainedDisplays() == 0,
    "expired correlation safely falls back to Expanded without rule reevaluation")
  Reset(); LR.Set("victoryIntensity", "off"); Win("item:998")
  Check(V.Entries()[1].displayMode == "expanded", "missing roll state defaults to Expanded")

  Reset()
  for _, intensity in ipairs({ "off", "subtle", "full" }) do
    LR.Set("victoryIntensity", intensity)
    for q = 2, 5 do
      Check(V.Preview(q % 2 == 0 and "need" or "greed", q, { display = "collapsed", upgrade = q % 2 == 0,
        name = "A very long legendary item name with enough words to require careful fitting" }), "Mini preview starts repeatedly")
      local pc = V.PreviewCard(); local pf = pc.victory
      V.PreviewAt(0.7)
      Check(pf.compact and pf.miniBase.shown and not pf.base.shown and pc.h < 70 and pf.upgradeIcon.shown == (q % 2 == 0),
        "purpose-built Mini frame, quality and conditional upgrade survive pooling")
      Check(pf.sweepCore.blend == "ADD" and not pf.rail.clips and pf.halo.texture:find("halo_", 1, true),
        "compact effects reuse rarity art, proper blend and unclipped painted sweep")
      if intensity == "off" then Check(pf.sweepCore.alpha == 0, "Off remains static in Mini")
      else Check(pf.sweepCore.alpha > 0 and pf.headerHaze.alpha > 0, "compact reveal remains visible") end
      V.SetDisplay(pf.entry, "expanded")
      Check(not pf.compact and pf.paintTime == 0.7, "paused preview toggle retains its selected animation pose")
      V.SetDisplay(pf.entry, "collapsed"); V.PreviewAt(1.0)
      if intensity ~= "off" then Check(pf.iconBloom.alpha > 0, "compact item arrival has a visible bloom") end
      V.PreviewAt(1.85)
      Check(not pf.scripts.OnUpdate and pf.particles[1].alpha == 0 and pf.sweepCore.alpha == 0,
        "Mini settles with no decorative motion")
      V.PreviewStop()
      Check(not pf.shown and not pf.timer and not pf.scripts.OnUpdate, "Mini interruption cleans up all owned work")
    end
  end
  V.Disable(false)
  Check(V.RetainedDisplays() == 0, "disable releases retained presentation snapshots")
  LR.Set("animate", true); V.Sync()
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
