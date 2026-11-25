-- Loot Rolls rule engine (loot/Rules.lua): the safety contract, checked on the pure engine alone.
--
-- A rule that rolls on the wrong item is the expensive bug, so this file pins what the engine must never do rather than what one
-- example does: an unknown is never a match, forgetting a fact never creates or changes a decision, the first rule that is not a
-- definite "no" speaks for everything below it, and nothing the saved data can contain (junk, NaN, a missing field) can make a rule
-- act that the editor shows as off or unfinished. Condition by condition tables come first, then rule logic against an independent
-- model, then a seeded random sweep of the invariants. The wiring around the engine (saved rules, countdown, Need gate, eligibility,
-- rules edited mid-countdown) is exercised end to end in test_loot_rolls.lua sections 4 and 4b.
local failures, checks = 0, 0
local function Check(cond, msg)
  checks = checks + 1
  if not cond then failures = failures + 1; print("FAIL: " .. msg) end
end
local function Is(got, want, msg)
  Check(got == want, msg .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

-- The engine alone: it needs the shared table, the families helper and the game's global strings; nothing else.
local env = setmetatable({}, { __index = _G })
env.TwichUI = {}
for _, f in ipairs({ "ForeverItemFamilies.lua", "loot/Rules.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, env); chunk("!!!TwichUI", {})
end
local Ru = env.TwichUI.LootRules
local MATCH, NO, UNKNOWN = Ru.MATCH, Ru.NO, Ru.UNKNOWN

local function Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Copy(x) end
  return out
end
local function Same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b or (a ~= a and b ~= b) end
  for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local NAN, INF = 0 / 0, math.huge

---------------------------------------------------------------------------
-- 1. Quality: every operator against every pair of qualities
---------------------------------------------------------------------------
for have = 0, 5 do
  for want = 0, 5 do
    local obs = { quality = have }
    Is(Ru.EvalCondition({ type = "quality", op = "is", value = want }, obs), have == want, "quality is " .. want .. " on " .. have)
    Is(Ru.EvalCondition({ type = "quality", op = "atLeast", value = want }, obs), have >= want, "quality atLeast " .. want .. " on " .. have)
    Is(Ru.EvalCondition({ type = "quality", op = "atMost", value = want }, obs), have <= want, "quality atMost " .. want .. " on " .. have)
    Is(Ru.EvalCondition({ type = "quality", op = "is", value = want, negate = true }, obs), have ~= want, "quality is-not " .. want .. " on " .. have)
  end
end
for _, bad in ipairs({ -1, 6, 2.5, NAN, INF, -INF, "2", true, {} }) do
  Check(Ru.CheckCondition({ type = "quality", op = "is", value = bad }) ~= nil, "quality value " .. tostring(bad) .. " is incomplete")
  Is(Ru.EvalCondition({ type = "quality", op = "atLeast", value = bad }, { quality = 5 }), nil, "an incomplete quality never matches " .. tostring(bad))
end
Check(Ru.CheckCondition({ type = "quality", op = "roughly", value = 2 }) ~= nil, "an unknown quality operator is incomplete")
Is(Ru.EvalCondition({ type = "quality", op = "roughly", value = 2 }, { quality = 2 }), nil, "and never matches")
Check(Ru.CheckCondition({ type = "quality", value = 2 }) ~= nil, "a quality with no operator is incomplete")
-- a quality the client reports oddly is unknown, not a guess
for _, odd in ipairs({ "4", 4.5, NAN, INF, true, {} }) do
  Is(Ru.EvalCondition({ type = "quality", op = "atLeast", value = 0 }, { quality = odd }), nil, "a reported quality of " .. tostring(odd) .. " is unknown")
end

---------------------------------------------------------------------------
-- 2. Item type, armor type, slot, equippable
---------------------------------------------------------------------------
for _, choice in ipairs(Ru.CLASS_CHOICES) do
  local value = choice[1]
  Check(Ru.CheckCondition({ type = "class", value = value }) == nil, "class choice " .. tostring(value) .. " is complete")
  if value ~= "equipment" then
    for id = 0, 18 do
      Is(Ru.EvalCondition({ type = "class", value = value }, { classID = id }), id == value, "class " .. tostring(value) .. " vs item class " .. id)
    end
  end
end
Check(Ru.CheckCondition({ type = "class", value = 99 }) ~= nil and Ru.CheckCondition({ type = "class", value = "gear" }) ~= nil
  and Ru.CheckCondition({ type = "class", value = 2.5 }) ~= nil and Ru.CheckCondition({ type = "class" }) ~= nil, "only offered item types are valid")
local equipment = { type = "class", value = "equipment" }
for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_TRINKET", "INVTYPE_ROBE", "INVTYPE_BODY", "INVTYPE_SHIELD", "INVTYPE_CLOAK" }) do
  Is(Ru.EvalCondition(equipment, { classID = 4, equipLoc = loc }), true, "armor in " .. loc .. " is equipment")
  Is(Ru.EvalCondition(equipment, { classID = 2, equipLoc = loc }), true, "a weapon in " .. loc .. " is equipment")
  Is(Ru.EvalCondition(equipment, { classID = 0, equipLoc = loc }), false, "a consumable is never equipment, whatever slot is reported")
  Is(Ru.EvalCondition(equipment, { classID = 9, equipLoc = loc }), false, "a recipe is never equipment")
end
for _, loc in ipairs({ "", "INVTYPE_NON_EQUIP", "INVTYPE_BAG" }) do
  Is(Ru.EvalCondition(equipment, { classID = 4, equipLoc = loc }), false, "armor with slot '" .. loc .. "' goes nowhere, so it is not equipment")
  Is(Ru.EvalCondition(equipment, { classID = 2, equipLoc = loc }), false, "a weapon with slot '" .. loc .. "' is not equipment")
end
Is(Ru.EvalCondition(equipment, { classID = 0 }), false, "a non-gear class is a definite no even before the slot is known")
Is(Ru.EvalCondition(equipment, { classID = 4 }), nil, "gear whose slot is not known yet is unknown")
Is(Ru.EvalCondition(equipment, { classID = 4, equipLoc = 5 }), nil, "a slot that is not text is unknown")
Is(Ru.EvalCondition(equipment, { equipLoc = "INVTYPE_HEAD" }), nil, "a slot with no class is unknown")

for _, choice in ipairs(Ru.ARMOR_CHOICES) do
  for sub = 0, 7 do
    Is(Ru.EvalCondition({ type = "armor", value = choice[1] }, { classID = 4, subClassID = sub }), sub == choice[1], choice[2] .. " vs armor sub-class " .. sub)
  end
end
for _, bad in ipairs({ 0, 5, 7, "cloth", 1.5, NAN }) do
  Check(Ru.CheckCondition({ type = "armor", value = bad }) ~= nil, "armor value " .. tostring(bad) .. " is incomplete")
end

for _, loc in ipairs({ "INVTYPE_HEAD", "INVTYPE_ROBE", "INVTYPE_CHEST", "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "" }) do
  for _, choice in ipairs(Ru.EQUIP_CHOICES) do
    local want = loc == choice[1] or (choice[1] == "INVTYPE_CHEST" and loc == "INVTYPE_ROBE")
    Is(Ru.EvalCondition({ type = "equip", value = choice[1] }, { equipLoc = loc }), want, choice[1] .. " vs reported slot '" .. loc .. "'")
  end
end
Check(Ru.CheckCondition({ type = "equip", value = "INVTYPE_ROBE" }) ~= nil and Ru.CheckCondition({ type = "equip", value = "head" }) ~= nil,
  "only offered slots are valid (a robe is reached through Chest)")
Is(Ru.EvalCondition({ type = "equip", value = "INVTYPE_HEAD" }, {}), nil, "a slot nobody reported is unknown")

for _, want in ipairs({ true, false }) do
  for _, have in ipairs({ true, false }) do
    Is(Ru.EvalCondition({ type = "equippable", value = want }, { equippable = have }), want == have, "equippable " .. tostring(want) .. " vs " .. tostring(have))
  end
  for _, odd in ipairs({ "true", 1, 0, {} }) do
    Is(Ru.EvalCondition({ type = "equippable", value = want }, { equippable = odd }), nil, "equippable fact of " .. tostring(odd) .. " is unknown, not true")
  end
end

---------------------------------------------------------------------------
-- 3. Recipes: every combination of what the client may or may not have said
---------------------------------------------------------------------------
do
  local T3 = { true, false, "unset" }
  local function V(x) if x ~= "unset" then return x end end
  local function Expect(mode, r)
    -- written from the documented meaning, not from the implementation
    if r.isRecipe == nil then return nil end
    if r.isRecipe == false then return false end
    if mode == "any" then return true end
    if mode == "profession" then return r.profession end
    if mode == "known" then return r.known end
    if r.profession == false or r.known == true then return false end   -- learnable
    if r.profession == nil or r.known == nil then return nil end
    return r.canLearn
  end
  for _, isRecipe in ipairs(T3) do for _, profession in ipairs(T3) do for _, known in ipairs(T3) do for _, canLearn in ipairs(T3) do
    local r = { isRecipe = V(isRecipe), profession = V(profession), known = V(known), canLearn = V(canLearn) }
    for _, choice in ipairs(Ru.RECIPE_CHOICES) do
      local label = ("recipe %s with %s/%s/%s/%s"):format(choice[1], tostring(isRecipe), tostring(profession), tostring(known), tostring(canLearn))
      Is(Ru.EvalCondition({ type = "recipe", mode = choice[1] }, { recipe = r }), Expect(choice[1], r), label)
    end
  end end end end
  Is(Ru.EvalCondition({ type = "recipe", mode = "any" }, {}), nil, "no recipe facts at all is unknown")
  Is(Ru.EvalCondition({ type = "recipe", mode = "any" }, { recipe = "yes" }), nil, "a recipe fact that is not a table is unknown")
  Check(Ru.CheckCondition({ type = "recipe", mode = "all" }) ~= nil and Ru.CheckCondition({ type = "recipe" }) ~= nil, "only offered recipe modes are valid")
  -- the case that matters most: never learn-then-lose. A recipe the player cannot learn is not "learnable".
  Is(Ru.EvalCondition({ type = "recipe", mode = "learnable" }, { recipe = { isRecipe = true, profession = true, known = false, canLearn = false } }), false,
    "a recipe in my profession that the game says I cannot learn is not learnable")
  Is(Ru.EvalCondition({ type = "recipe", mode = "learnable", negate = true }, { recipe = { isRecipe = true, profession = true } }), nil,
    "negating a learnable that could not be judged stays unknown (a Pass rule cannot fire on a recipe that might be mine)")
end

---------------------------------------------------------------------------
-- 4. Specific item, family, binding, upgrade, place
---------------------------------------------------------------------------
for _, id in ipairs({ 1, 100, 9999999 }) do
  Check(Ru.CheckCondition({ type = "item", id = id }) == nil, "item " .. id .. " is a valid item")
  Is(Ru.EvalCondition({ type = "item", id = id }, { itemID = id }), true, "item " .. id .. " matches itself")
  Is(Ru.EvalCondition({ type = "item", id = id }, { itemID = id + 1 }), false, "and not its neighbour")
end
for _, bad in ipairs({ 0, -5, 10000000, 1.5, NAN, INF, "100", true }) do
  Check(Ru.CheckCondition({ type = "item", id = bad }) ~= nil, "item id " .. tostring(bad) .. " is incomplete")
end
Is(Ru.EvalCondition({ type = "item", id = 100 }, {}), nil, "an item the client did not name is unknown")
Is(Ru.EvalCondition({ type = "item", id = 100 }, { itemID = "100" }), nil, "an item id that is text is unknown")
Is(Ru.EvalCondition({ type = "item", id = 100 }, { itemID = NAN }), nil, "an item id that is NaN is unknown")
Is(Ru.EvalCondition({ type = "item", id = 100, name = "Other name" }, { itemID = 101, name = "Other name" }), false, "an item is its number, never its name")

do
  local crate, writ = { type = "family", value = "waylaid-crates" }, { type = "family", value = "craftsmans-writs" }
  local function Edges(c, inside, outside, label)
    for _, id in ipairs(inside) do Is(Ru.EvalCondition(c, { itemID = id }), true, label .. " includes " .. id) end
    for _, id in ipairs(outside) do Is(Ru.EvalCondition(c, { itemID = id }), false, label .. " excludes " .. id) end
  end
  Edges(crate, { 248549, 248682, 248699, 248702, 248713, 248765, 248779 },
    { 248548, 248550, 248681, 248700, 248701, 248714, 248764, 248780, 248206, 264011 }, "crates")
  Edges(writ, { 248206, 262887, 262890, 264011, 264160 },
    { 248205, 248207, 262886, 262891, 264010, 264161, 248549, 248682 }, "writs")
  for _, odd in ipairs({ 0, -1, 1.5, "248549", NAN }) do
    Is(Ru.EvalCondition(crate, { itemID = odd }), nil, "a crate rule cannot judge item id " .. tostring(odd))
  end
  Check(Ru.CheckCondition({ type = "family", value = "everything" }) ~= nil and Ru.CheckCondition({ type = "family" }) ~= nil, "unknown families are incomplete")
end

for b = 0, 4 do
  Is(Ru.EvalCondition({ type = "bind", value = "pickup" }, { bindType = b }), b == 1, "binds when picked up vs bind type " .. b)
  Is(Ru.EvalCondition({ type = "bind", value = "equip" }, { bindType = b }), b == 2, "binds when equipped vs bind type " .. b)
end
Is(Ru.EvalCondition({ type = "bind", value = "pickup" }, { bindType = "1" }), nil, "a bind type that is text is unknown")
Is(Ru.EvalCondition({ type = "bind", value = "pickup" }, {}), nil, "no bind type is unknown")
Check(Ru.CheckCondition({ type = "bind", value = "account" }) ~= nil, "only offered bindings are valid")

for _, want in ipairs({ true, false }) do
  for _, have in ipairs({ true, false }) do
    Is(Ru.EvalCondition({ type = "upgrade", value = want }, { upgrade = have }, { allowUpgrade = true }), want == have, "upgrade " .. tostring(want) .. " vs " .. tostring(have) .. " when allowed")
    for _, opts in ipairs({ false, {}, { allowUpgrade = false }, { allowUpgrade = "yes" }, { allowUpgrade = 1 } }) do
      Is(Ru.EvalCondition({ type = "upgrade", value = want }, { upgrade = have }, opts or nil), nil, "an upgrade is a hint: unknown unless allowed (" .. tostring(opts) .. ")")
    end
  end
end
Is(Ru.EvalCondition({ type = "upgrade", value = false, negate = true }, { upgrade = false }, { allowUpgrade = true }), false, "negated upgrade flips when allowed")

do
  local kinds = { "none", "party", "raid", "pvp", "arena", "scenario" }
  for _, kind in ipairs(kinds) do
    local obs = { context = { instanceType = kind } }
    Is(Ru.EvalCondition({ type = "context", value = "inRaid" }, obs), kind == "raid", "in a raid while in '" .. kind .. "'")
    Is(Ru.EvalCondition({ type = "context", value = "outsideRaid" }, obs), kind ~= "raid", "outside a raid while in '" .. kind .. "'")
    Is(Ru.EvalCondition({ type = "context", value = "inDungeon" }, obs), kind == "party", "in a dungeon while in '" .. kind .. "'")
    Is(Ru.EvalCondition({ type = "context", value = "outsideDungeon" }, obs), kind ~= "party", "outside a dungeon while in '" .. kind .. "'")
  end
  for _, obs in ipairs({ {}, { context = {} }, { context = { instanceType = 5 } }, { context = "raid" }, { context = { inRaidGroup = true } } }) do
    Is(Ru.EvalCondition({ type = "context", value = "outsideRaid" }, obs), nil, "an unreadable place is unknown, so 'outside a raid' never fires on a guess")
  end
end

---------------------------------------------------------------------------
-- 5. Garbage in: nothing the saved data holds may throw or match
---------------------------------------------------------------------------
do
  local full = { quality = 2, classID = 4, subClassID = 1, equipLoc = "INVTYPE_HEAD", itemID = 100, bindType = 1, equippable = true, upgrade = true,
    recipe = { isRecipe = true, profession = true, known = false, canLearn = true }, context = { instanceType = "none" } }
  local junk = { nil, false, true, 0, 7, "text", {}, { type = "nope" }, { type = 5 }, { type = "quality" }, { type = "quality", op = "is", value = 2, negate = "yes" },
    { type = "quality", op = "is", value = 2, negate = 1 }, { type = "class", value = {} }, { type = "item", id = {} }, { type = "family", value = {} } }
  for i = 1, 15 do
    local c = junk[i]
    local ok, v = pcall(Ru.EvalCondition, c, full, { allowUpgrade = true })
    Check(ok and v == nil, "junk condition #" .. i .. " is unknown and never throws")
    ok = pcall(Ru.CheckCondition, c)
    Check(ok, "CheckCondition survives junk condition #" .. i)
  end
  for _, obs in ipairs({ false, 0, 5, "text", {}, true }) do
    local ok, v = pcall(Ru.EvalCondition, { type = "quality", op = "is", value = 2 }, obs)
    Check(ok and v == nil, "a facts value of " .. tostring(obs) .. " is unknown and never throws")
  end
  Is(Ru.EvalCondition({ type = "quality", op = "is", value = 2 }, nil), nil, "no facts at all is unknown")
  -- negate must be a real boolean: a string would otherwise read as true and flip a match
  Check(Ru.CheckCondition({ type = "quality", op = "is", value = 2, negate = "false" }) ~= nil, "a negate that is not a boolean is incomplete")
  Is(Ru.EvalCondition({ type = "quality", op = "is", value = 2, negate = "false" }, { quality = 2 }), nil, "and never matches")
  -- an eval that raises is contained
  local original = Ru.TYPES.quality.eval
  Ru.TYPES.quality.eval = function() error("boom") end
  Is(Ru.EvalCondition({ type = "quality", op = "is", value = 2 }, { quality = 2 }), nil, "a condition that raises is unknown, not a match")
  Ru.TYPES.quality.eval = function() return "yes" end
  Is(Ru.EvalCondition({ type = "quality", op = "is", value = 2 }, { quality = 2 }), nil, "a condition that answers with a non-boolean is unknown")
  Ru.TYPES.quality.eval = original
end

---------------------------------------------------------------------------
-- 6. Rules: all / any against an independent three-valued model
---------------------------------------------------------------------------
do
  -- conditions with a fixed answer: quality 2 is true, quality 3 is false, upgrade (not allowed) is unknown
  local Y, N, U = { type = "quality", op = "is", value = 2 }, { type = "quality", op = "is", value = 3 }, { type = "upgrade", value = true }
  local obs = { quality = 2 }
  local V = { [Y] = true, [N] = false, [U] = nil }
  local function Model(mode, list)
    local yes, no, unk = false, false, false
    for _, c in ipairs(list) do
      local v = V[c]
      if c == U then unk = true elseif v then yes = true else no = true end
    end
    if mode == "any" then return yes and MATCH or (unk and UNKNOWN or NO) end
    return no and NO or (unk and UNKNOWN or MATCH)
  end
  local pool = { Y, N, U }
  local n = 0
  for a = 1, 3 do for b = 0, 3 do for d = 0, 3 do
    local list = { pool[a] }
    if b > 0 then list[#list + 1] = pool[b] end
    if d > 0 then list[#list + 1] = pool[d] end
    for _, mode in ipairs({ "all", "any" }) do
      n = n + 1
      local rule = { id = "lr1", enabled = true, action = "greed", match = mode, conditions = list }
      Is(Ru.EvalRule(rule, obs), Model(mode, list), "model " .. mode .. " of " .. #list .. " conditions #" .. n)
    end
  end end end
  Check(n == 2 * 3 * 4 * 4, "the sweep covered every combination of one to three conditions")
  local base = { id = "lr1", enabled = true, action = "greed", conditions = { Y } }
  Is(Ru.EvalRule(base, obs), MATCH, "a rule with no 'match' is an all-rule")
  base.match = "some"; Is(Ru.EvalRule(base, obs), MATCH, "an unrecognised 'match' reads as all, the stricter reading")
  base.conditions = { Y, N }
  Is(Ru.EvalRule(base, obs), NO, "and so does not turn into any")
  base.match = { "any" }; Is(Ru.EvalRule(base, obs), NO, "a 'match' that is not text reads as all")
  -- an incomplete rule is never evaluated into a match, even when its complete part would match
  local half = { id = "lr1", enabled = true, action = "greed", conditions = { Y, { type = "quality", op = "is", value = 99 } } }
  Is(Ru.EvalRule(half, obs), UNKNOWN, "one unfinished condition makes the whole rule unknown")
  half.match = "any"; Is(Ru.EvalRule(half, obs), UNKNOWN, "even for an any-rule whose other condition matches")
  Is(Ru.Decide({ half }, obs).status, "none", "and an incomplete rule is skipped by Decide, not allowed to block or decide")
end

---------------------------------------------------------------------------
-- 7. What makes a rule complete
---------------------------------------------------------------------------
do
  local q = { type = "quality", op = "is", value = 2 }
  local function Rule(over)
    local r = { id = "lr1", enabled = true, action = "greed", conditions = { q } }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
  end
  Is(Ru.Incomplete(Rule()), nil, "a plain rule is complete")
  for _, action in ipairs({ "need", "greed", "pass" }) do Is(Ru.Incomplete(Rule({ action = action })), nil, action .. " is a complete roll action") end
  for _, action in ipairs({ "Need", "roll", "", 1, true, {}, "nil" }) do
    Check(Ru.Incomplete(Rule({ action = action })) ~= nil, "action " .. tostring(action) .. " is incomplete")
  end
  Check(Ru.Incomplete({ id = "lr1", enabled = true, conditions = { q } }) ~= nil, "a rule with no action is incomplete")
  Is(Ru.Incomplete(Rule({ action = "none", display = "collapsed" })), nil, "display-only is complete")
  Check(Ru.Incomplete(Rule({ action = "none" })) ~= nil and Ru.Incomplete(Rule({ action = "none", display = "none" })) ~= nil, "a rule that does nothing at all is incomplete")
  Check(Ru.Incomplete(Rule({ display = "bogus" })) ~= nil and Ru.Incomplete(Rule({ display = 5 })) ~= nil, "an unknown display is incomplete")
  Check(Ru.Incomplete(Rule({ conditions = {} })) ~= nil and Ru.Incomplete(Rule({ conditions = "x" })) ~= nil and Ru.Incomplete(Rule({ conditions = false })) ~= nil
    and Ru.Incomplete({ id = "lr1", action = "greed" }) ~= nil, "a rule with no conditions would match every item and is incomplete")
  local many = {}
  for i = 1, Ru.MAX_CONDITIONS do many[i] = q end
  Is(Ru.Incomplete(Rule({ conditions = many })), nil, "the most conditions allowed is complete")
  many[#many + 1] = q
  Check(Ru.Incomplete(Rule({ conditions = many })) ~= nil, "one more is not")
  Check(Ru.Incomplete(Rule({ conditions = { q, "junk" } })) ~= nil and Ru.Incomplete(Rule({ conditions = { 7 } })) ~= nil, "a condition that is not a table is incomplete")
  for _, nonRule in ipairs({ false, 0, "rule", true }) do Check(Ru.Incomplete(nonRule) ~= nil, "a rule that is " .. tostring(nonRule) .. " is incomplete") end
  Check(Ru.Incomplete(nil) ~= nil, "no rule is incomplete")
  -- the reason names the offending condition
  Check((Ru.Incomplete(Rule({ conditions = { q, q, { type = "item", id = 0 } } })) or ""):find("Condition 3", 1, true), "the editor is told which condition is unfinished")
  -- every condition the picker can add starts complete, so a fresh rule never fails on its own default
  for _, kind in ipairs(Ru.ORDER) do
    local c = Ru.NewCondition(kind)
    Check(c and c.type == kind, "the picker can make a " .. kind)
    if kind ~= "item" then Is(Ru.CheckCondition(c), nil, "a new " .. kind .. " condition is complete") else Check(Ru.CheckCondition(c) ~= nil, "a new item condition waits for an item") end
  end
  Is(Ru.NewCondition("nonsense"), nil, "an unknown kind makes nothing")
end

---------------------------------------------------------------------------
-- 8. Decide / DecideDisplay: order, enabled, unknown, no-op
---------------------------------------------------------------------------
do
  local q2, q3 = { type = "quality", op = "is", value = 2 }, { type = "quality", op = "is", value = 3 }
  local unknownCond = { type = "recipe", mode = "known" }   -- no recipe fact in these observations
  local NEVER = {}   -- an override of "the field is absent" (a nil in a table constructor says nothing)
  local function Rule(id, action, conditions, over)
    local r = { id = id, enabled = true, action = action, conditions = conditions or { q2 } }
    for k, v in pairs(over or {}) do if v == NEVER then r[k] = nil else r[k] = v end end
    return r
  end
  local obs = { quality = 2 }
  -- an item every enabled rule matches: the top one wins and nothing below is consulted
  local rules = { Rule("lr1", "pass"), Rule("lr2", "need"), Rule("lr3", "greed") }
  local d = Ru.Decide(rules, obs)
  Check(d.status == "match" and d.index == 1 and d.rule.id == "lr1" and d.rule.action == "pass", "the rule at the top decides")
  Check(Ru.Decide({ rules[2], rules[1] }, obs).rule.action == "need", "reordering changes the decision")
  -- a higher "no" passes through; a higher unknown stops everything
  Check(Ru.Decide({ Rule("lr9", "pass", { q3 }), rules[2] }, obs).rule.id == "lr2", "a rule that does not apply is skipped")
  d = Ru.Decide({ Rule("lr9", "pass", { unknownCond }), rules[2] }, obs)
  Check(d.status == "unknown" and d.rule.id == "lr9" and d.index == 1, "a rule that cannot be judged keeps the roll manual")
  d = Ru.Decide({ Rule("lr8", "pass", { q3 }), Rule("lr9", "pass", { unknownCond }), rules[2] }, obs)
  Check(d.status == "unknown" and d.index == 2, "no matter how far down the unknown is, the rules below it stay silent")
  -- an unknown that is also a "no" elsewhere in an all-rule is a no, and lets lower rules speak
  d = Ru.Decide({ Rule("lr9", "pass", { unknownCond, q3 }), rules[2] }, obs)
  Check(d.status == "match" and d.rule.id == "lr2", "an all-rule with a definite no is a no even with an unknown condition")
  -- an any-rule with a definite match decides despite an unknown condition
  d = Ru.Decide({ Rule("lr9", "pass", { unknownCond, q2 }, { match = "any" }), rules[2] }, obs)
  Check(d.status == "match" and d.rule.id == "lr9", "an any-rule with a match decides despite an unknown condition")

  -- switched-off and unfinished rules say nothing and block nothing
  d = Ru.Decide({ Rule("lr1", "pass", nil, { enabled = false }), rules[2] }, obs)
  Check(d.rule.id == "lr2", "a switched-off rule is invisible to Decide")
  d = Ru.Decide({ Rule("lr1", "pass", { unknownCond }, { enabled = false }), rules[2] }, obs)
  Check(d.status == "match" and d.rule.id == "lr2", "and a switched-off rule that could not be judged does not block")
  d = Ru.Decide({ Rule("lr1", "pass", {}), rules[2] }, obs)
  Check(d.rule.id == "lr2", "an unfinished rule is skipped")
  d = Ru.Decide({ Rule("lr1", "none", nil, { display = "collapsed" }), rules[2] }, obs)
  Check(d.rule.id == "lr2", "a display-only rule never rolls and never blocks the roll channel")
  d = Ru.Decide({ Rule("lr1", "none", { unknownCond }, { display = "collapsed" }), rules[2] }, obs)
  Check(d.status == "match" and d.rule.id == "lr2", "even a display-only rule that could not be judged")

  -- an enabled flag that is not exactly true must not switch a rule on
  for _, flag in ipairs({ "yes", 1, 0, "false", {}, "true" }) do
    d = Ru.Decide({ Rule("lr1", "pass", nil, { enabled = flag }) }, obs)
    Check(d.status == "none", "enabled = " .. tostring(flag) .. " does not switch a rule on")
  end
  d = Ru.Decide({ Rule("lr1", "pass", nil, { enabled = NEVER }) }, obs)
  Check(d.status == "none", "a rule that never said it was on is off, as the editor shows it")

  -- nothing to decide with
  Check(Ru.Decide({}, obs).status == "none" and Ru.Decide(nil, obs).status == "none" and Ru.Decide("rules", obs).status == "none", "no rules, no decision")
  Check(Ru.Decide({ "junk", 5, false, {} }, obs).status == "none", "entries that are not rules are skipped")
  Check(Ru.Decide({ rules[1] }, nil).status == "unknown" or Ru.Decide({ rules[1] }, nil).status == "none", "no facts at all never decides")
  Check(Ru.Decide({ rules[1] }, {}).status == "unknown", "an empty observation is unknown for a rule that needs a fact")
  Check(Ru.Decide({ rules[1] }, 5).status == "unknown", "a facts value that is not a table is unknown")

  -- decisions never alter the rules or the facts
  local before, factsBefore = Copy(rules), Copy(obs)
  Ru.Decide(rules, obs); Ru.DecideDisplay(rules, obs); Ru.Summary(rules[1])
  Check(Same(before, rules) and Same(factsBefore, obs), "deciding changes nothing it was given")

  -- display channel
  local function Disp(id, display, conditions, over)
    return Rule(id, "none", conditions, (function() local o = { display = display }; for k, v in pairs(over or {}) do o[k] = v end return o end)())
  end
  d = Ru.DecideDisplay({ Disp("lr1", "collapsed"), Disp("lr2", "expanded") }, obs)
  Check(d.status == "match" and d.rule.display == "collapsed", "the first display rule decides the card")
  d = Ru.DecideDisplay({ Disp("lr1", "collapsed", { q3 }), Disp("lr2", "expanded") }, obs)
  Check(d.rule.display == "expanded", "a display rule that does not apply is skipped")
  d = Ru.DecideDisplay({ Disp("lr1", "collapsed", { unknownCond }), Disp("lr2", "expanded") }, obs)
  Check(d.status == "unknown" and d.rule.id == "lr1", "a display rule that cannot be judged stops the display search")
  d = Ru.DecideDisplay({ Disp("lr1", "collapsed", nil, { enabled = false }), Disp("lr2", "expanded") }, obs)
  Check(d.rule.id == "lr2", "a switched-off display rule is skipped")
  d = Ru.DecideDisplay({ Disp("lr1", "collapsed", nil, { enabled = NEVER }), Disp("lr2", "expanded") }, obs)
  Check(d.rule.id == "lr2", "a display rule that never said it was on is off")
  d = Ru.DecideDisplay({ Rule("lr1", "greed") }, obs)
  Check(d.status == "none", "a rule with no display never takes part in the display channel")
  d = Ru.DecideDisplay({ Disp("lr1", "none", nil, { action = "greed" }) }, obs)
  Check(d.status == "none", "an explicit 'No change' display is not a display decision")
  d = Ru.DecideDisplay({ Disp("lr1", "sideways") }, obs)
  Check(d.status == "none", "an unknown display value is not a display decision")
  Check(Ru.DecideDisplay(nil, obs).status == "none" and Ru.DecideDisplay({ "junk" }, obs).status == "none", "display with nothing to read is none")
  -- display reads upgrades even when roll automation may not (a card can be reshaped by a hint; it cannot be rolled by one)
  local up = Disp("lr1", "collapsed", { { type = "upgrade", value = true } })
  Check(Ru.DecideDisplay({ up }, { upgrade = true }).status == "match", "a display rule may use the upgrade hint")
  Check(Ru.Decide({ Rule("lr1", "greed", { { type = "upgrade", value = true } }) }, { upgrade = true }).status == "unknown", "but a roll rule may not unless it was allowed")
  Check(Ru.Decide({ Rule("lr1", "greed", { { type = "upgrade", value = true } }) }, { upgrade = true }, { allowUpgrade = true }).status == "match", "and may when it is")
end

---------------------------------------------------------------------------
-- 9. Seeded random sweep of the invariants
---------------------------------------------------------------------------
do
  local seed = 20260125
  local function Rand(n) seed = (seed * 1103515245 + 12345) % 2147483648; return math.floor(seed / 65536) % n + 1 end
  local function Pick(list) return list[Rand(#list)] end
  local CONDS = {
    { type = "quality", op = "is", value = 2 }, { type = "quality", op = "atLeast", value = 3 }, { type = "quality", op = "atMost", value = 1 },
    { type = "class", value = "equipment" }, { type = "class", value = 9 }, { type = "class", value = 0 },
    { type = "armor", value = 1 }, { type = "armor", value = 4 }, { type = "equippable", value = true }, { type = "equippable", value = false },
    { type = "equip", value = "INVTYPE_HEAD" }, { type = "equip", value = "INVTYPE_CHEST" },
    { type = "recipe", mode = "profession" }, { type = "recipe", mode = "learnable" }, { type = "recipe", mode = "known" }, { type = "recipe", mode = "any" },
    { type = "item", id = 100 }, { type = "item", id = 101 }, { type = "family", value = "waylaid-crates" }, { type = "family", value = "craftsmans-writs" },
    { type = "bind", value = "pickup" }, { type = "bind", value = "equip" }, { type = "upgrade", value = true }, { type = "upgrade", value = false },
    { type = "context", value = "inRaid" }, { type = "context", value = "outsideRaid" }, { type = "context", value = "inDungeon" }, { type = "context", value = "outsideDungeon" },
  }
  local function Obs()
    local o = {}
    if Rand(5) > 1 then o.quality = Rand(6) - 1 end
    if Rand(5) > 1 then o.classID = Pick({ 0, 2, 4, 7, 9 }) end
    if Rand(5) > 1 then o.subClassID = Rand(6) end
    if Rand(5) > 1 then o.equipLoc = Pick({ "", "INVTYPE_HEAD", "INVTYPE_CHEST", "INVTYPE_ROBE", "INVTYPE_NON_EQUIP" }) end
    if Rand(5) > 1 then o.itemID = Pick({ 100, 101, 248549, 248700, 262887 }) end
    if Rand(5) > 1 then o.bindType = Rand(5) - 1 end
    if Rand(3) > 1 then o.equippable = Rand(2) == 1 end
    if Rand(3) > 1 then o.upgrade = Rand(2) == 1 end
    if Rand(3) > 1 then
      o.recipe = { isRecipe = Rand(2) == 1 }
      if Rand(2) == 1 then o.recipe.profession = Rand(2) == 1 end
      if Rand(2) == 1 then o.recipe.known = Rand(2) == 1 end
      if Rand(2) == 1 then o.recipe.canLearn = Rand(2) == 1 end
    end
    if Rand(3) > 1 then o.context = { instanceType = Pick({ "none", "party", "raid", "pvp" }) } end
    return o
  end
  local function Rules()
    local list = {}
    for i = 1, Rand(6) do
      local conds = {}
      for j = 1, Rand(4) do
        local c = Copy(Pick(CONDS))
        if Rand(5) == 1 then c.negate = true end
        conds[j] = c
      end
      list[i] = { id = "lr" .. i, enabled = Rand(5) > 1, action = Pick({ "need", "greed", "pass", "none" }), display = Pick({ "none", "none", "expanded", "collapsed" }),
        match = Pick({ "all", "all", "any" }), conditions = conds }
    end
    return list
  end
  -- Forget one fact (top level, or a field of recipe/context)
  local function Forget(obs)
    local keys = {}
    for k in pairs(obs) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then return obs end
    local out = Copy(obs)
    local k = Pick(keys)
    if type(out[k]) == "table" and Rand(2) == 1 then
      local inner = {}
      for ik in pairs(out[k]) do inner[#inner + 1] = ik end
      table.sort(inner)
      if #inner > 0 then out[k][Pick(inner)] = nil; return out end
    end
    out[k] = nil
    return out
  end
  local counts = { match = 0, unknown = 0, none = 0 }
  for iter = 1, 4000 do
    local rules, obs = Rules(), Obs()
    local allow = Rand(2) == 1
    local opts = { allowUpgrade = allow }
    local snapshot = Copy(rules)
    local d = Ru.Decide(rules, obs, opts)
    counts[d.status] = (counts[d.status] or 0) + 1
    Check(Same(snapshot, rules), "sweep " .. iter .. ": the rules are untouched")
    -- every rule the roll channel may consult, in order
    local seenNo = true
    local expected = { status = "none" }
    for i, rule in ipairs(rules) do
      if rule.enabled == true and rule.action ~= "none" and not Ru.Incomplete(rule) then
        local v = Ru.EvalRule(rule, obs, opts)
        if v ~= NO then expected = { status = v, index = i }; break end
      end
    end
    Check(d.status == expected.status and d.index == expected.index, ("sweep %d: Decide agrees with reading the rules top to bottom (%s/%s vs %s/%s)")
      :format(iter, d.status, tostring(d.index), expected.status, tostring(expected.index)))
    if d.status == "match" then
      local rule = rules[d.index]
      Check(rule.enabled == true and rule.action ~= "none" and not Ru.Incomplete(rule), "sweep " .. iter .. ": a decision comes from an enabled, finished rule that rolls")
      Check(Ru.EvalRule(rule, obs, opts) == MATCH, "sweep " .. iter .. ": and one that really matches")
      -- the safety property: less knowledge never creates or changes a decision
      for _ = 1, 4 do
        local less = Forget(obs)
        local s = Ru.Decide(rules, less, opts)
        Check(s.status ~= "match" or (s.index == d.index), "sweep " .. iter .. ": forgetting a fact never changes which rule rolls")
      end
    end
    for _ = 1, 4 do
      local less = Forget(obs)
      local s = Ru.Decide(rules, less, opts)
      if s.status == "match" then
        Check(d.status == "match" and d.index == s.index, ("sweep %d: a decision made with less knowledge (rule %d) is the one made with more (%s/%s)")
          :format(iter, s.index, d.status, tostring(d.index)))
      end
    end
    -- the allowance only ever removes decisions that depend on the hint, never adds a different roll
    if not allow then
      local withAllow = Ru.Decide(rules, obs, { allowUpgrade = true })
      if d.status == "match" then
        Check(withAllow.status == "match" and withAllow.index == d.index, "sweep " .. iter .. ": allowing upgrades never moves a decision that did not need them")
      end
    end
    -- display channel obeys the same laws
    local dd = Ru.DecideDisplay(rules, obs)
    if dd.status == "match" then
      local rule = rules[dd.index]
      Check(rule.enabled == true and (rule.display == "expanded" or rule.display == "collapsed") and not Ru.Incomplete(rule)
        and Ru.EvalRule(rule, obs, { allowUpgrade = true }) == MATCH, "sweep " .. iter .. ": a display decision is an enabled, finished, matching display rule")
      for i = 1, dd.index - 1 do
        local above = rules[i]
        if above.enabled == true and (above.display == "expanded" or above.display == "collapsed") and not Ru.Incomplete(above) then
          Check(Ru.EvalRule(above, obs, { allowUpgrade = true }) == NO, "sweep " .. iter .. ": every display rule above the winner said no")
        end
      end
    end
    -- negation never turns unknown into an answer, and always flips a known one
    local c = Copy(Pick(CONDS))
    local plain = Ru.EvalCondition(c, obs, opts)
    c.negate = true
    local flipped = Ru.EvalCondition(c, obs, opts)
    Check((plain == nil and flipped == nil) or (plain ~= nil and flipped == not plain), "sweep " .. iter .. ": negation flips a known answer and leaves an unknown alone")
  end
  Check(counts.match > 200 and counts.unknown > 200 and counts.none > 200,
    ("the sweep exercised every kind of outcome (%d match, %d unknown, %d none)"):format(counts.match, counts.unknown, counts.none))
end

---------------------------------------------------------------------------
-- 10. Words: summaries read like the rule and survive anything
---------------------------------------------------------------------------
do
  local function S(rule) local ok, text = pcall(Ru.Summary, rule); Check(ok, "Summary does not throw: " .. tostring(text)); return text end
  local function Rule(over)
    local r = { action = "greed", conditions = { { type = "quality", op = "is", value = 2 } } }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
  end
  Is(S(Rule()), "Automatically choose Greed when the item is Uncommon.", "the plainest rule")
  Is(S(Rule({ action = "need" })), "Automatically choose Need when the item is Uncommon.", "Need is named plainly, never softened")
  Is(S(Rule({ action = "pass" })), "Automatically choose Pass when the item is Uncommon.", "Pass is named plainly")
  Check(S(Rule({ delay = 1 })):find("after 1 second.", 1, true) and S(Rule({ delay = 2.5 })):find("after 2.5 seconds", 1, true), "delays read in singular and decimals")
  Check(not S(Rule({ delay = 0 })):find("after", 1, true) and not S(Rule({ delay = "soon" })):find("after", 1, true) and not S(Rule({ delay = -3 })):find("after", 1, true), "a delay that is not a positive number is left out")
  Check(S(Rule({ match = "any", conditions = { { type = "quality", op = "is", value = 2 }, { type = "class", value = 9 } } })):find(" or ", 1, true), "an any-rule reads with 'or'")
  Check(S(Rule({ conditions = { { type = "quality", op = "is", value = 2 }, { type = "class", value = 9 } } })):find(" and ", 1, true), "an all-rule reads with 'and'")
  Check(S(Rule({ conditions = { { type = "class", value = 9, negate = true } } })):find("not (is recipe)", 1, true), "negation is spoken")
  Check(S(Rule({ conditions = { { type = "context", value = "inRaid" } } })):find("when you are in a raid", 1, true), "a place leads the sentence without 'the item'")
  Check(S(Rule({ conditions = { { type = "item", id = 17, name = "Some Item" } } })):find("is Some Item", 1, true) and S(Rule({ conditions = { { type = "item", id = 17 } } })):find("item #17", 1, true), "a specific item is named, or numbered")
  Check(S(Rule({ conditions = { { type = "quality", op = "is", value = 99 } } })):find("once you add a condition", 1, true), "a rule with only unfinished conditions says so rather than describing nothing")
  Check(S(Rule({ action = "bogus" })):find("Choose a roll action", 1, true), "an unfinished action says so")
  Is(S(nil), "", "no rule, no sentence")
  Is(S("rule"), "", "a rule that is not a table, no sentence")
  Check(S(Rule({ action = "none", display = "collapsed" })):find("Collapse the card", 1, true) and not S(Rule({ action = "none", display = "collapsed" })):find("Automatically", 1, true),
    "a display-only rule never claims to roll")
  Check(S(Rule({ display = "expanded" })):find("; expand the card", 1, true), "a rule that rolls and reshapes says both")
  Check(S(Rule({ conditions = { "junk", { type = "quality", op = "is", value = 3 } } })) ~= nil, "junk beside a good condition does not break the sentence")
  Is(Ru.ActionSummary({ action = "need" }), "Need", "action summary names a roll")
  Is(Ru.ActionSummary({ action = "none" }), "No action", "and a rule that does nothing")
  -- a summary never claims a different action than the rule's
  for _, action in ipairs({ "need", "greed", "pass" }) do
    local text = S(Rule({ action = action }))
    for _, other in ipairs({ "Need", "Greed", "Pass" }) do
      Check((text:find(other, 1, true) ~= nil) == (other:lower() == action), "the summary of a " .. action .. " rule names " .. other .. " only if it is that action")
    end
  end
end

if failures > 0 then print(failures .. " failure(s) in " .. checks .. " checks") os.exit(1) end
print("PASSED")
