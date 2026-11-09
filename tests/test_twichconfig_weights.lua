-- Stat weights sharing (setup/TwichConfig.lua, the Weights group): what arrives is validated and cleaned
-- (Weights.clean), the diff against the live TwichUIDB.gear tables is planned (Weights.plan), and applying
-- rewrites only the changed units with an undo record (Weights.apply / Weights.restore). The stat vocabulary
-- comes from gear/Weights.lua (EDITOR for known stats, ITEM_POINT for rankable ones), so it is loaded here.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })

for _, f in ipairs({ "gear/Weights.lua", "setup/TwichConfig.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { gear = {} }
local R = c.TwichUI
local TC = R.TwichConfig
local W = R.GearWeights

-- The stat-weights group (id "gearWeights") is the one group that is not flat; its module carries
-- clean/plan/apply/restore and is hung on the group descriptor as .custom
-- (setup/TwichConfig.lua: g = Group("gearWeights", ...); g.custom = Weights).
local g = TC.Group("gearWeights")
assert(type(g) == "table" and type(g.custom) == "table", "the gearWeights group is not reachable from R.TwichConfig")
local WT = g.custom
assert(type(WT.clean) == "function" and type(WT.plan) == "function"
  and type(WT.apply) == "function" and type(WT.restore) == "function",
  "the gearWeights group module lacks clean/plan/apply/restore")
local Gear = c.TwichUIDB.gear

local function Set(t) local s = {} for _, v in ipairs(t) do s[v] = true end return s end
local function DeepEq(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not DeepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local function Clean(raw)
  local out, reason = WT.clean(raw)
  return out, reason
end

---------------------------------------------------------------------------
-- 0. The stat vocabulary the validators draw from (gear/Weights.lua)
---------------------------------------------------------------------------
do
  -- EDITOR lists every stat a weight may name; ITEM_POINT lists the rankable ones.
  local all, ranked = {}, {}
  for _, group in ipairs(W.EDITOR) do for _, stat in ipairs(group[2]) do all[stat] = true end end
  for stat in pairs(W.ITEM_POINT) do ranked[stat] = true end
  assert(all.STR and all.ARMOR and all.MAINHAND_DPS, "EDITOR stats are known weights")
  assert(ranked.STR and ranked.CRIT and ranked.SPELLCRIT, "ITEM_POINT stats are rankable")
  assert(not ranked.ARMOR and not ranked.MAINHAND_DPS, "armor and weapon damage are not rankable")
end

---------------------------------------------------------------------------
-- 1. Weights.clean: shape
---------------------------------------------------------------------------
do
  assert(select(2, Clean("nope")) == "shape", "a non-table raw is a shape error")
  assert(select(2, Clean({})) == "shape", "raw without units is a shape error")
  assert(select(2, Clean({ units = "nope" })) == "shape", "non-table units is a shape error")
  local raw = { units = { [1] = { class = "WARRIOR", line = 1, use = true }, ["x"] = nil } }
  raw.units["x"] = { class = "WARRIOR", line = 2, use = true }
  assert(select(2, Clean(raw)) == "shape", "a non-numeric key in units is a shape error")
end

---------------------------------------------------------------------------
-- 2. Weights.clean: too-large (more than TC.LIMITS.units = 96 units)
---------------------------------------------------------------------------
do
  local units = {}
  for i = 1, TC.LIMITS.units + 1 do
    units[i] = { class = "WARRIOR", line = i, use = true }
  end
  local ok, reason = Clean({ units = units })
  assert(ok == nil and reason == "too-large", "97th unit is refused as too-large")
  units[TC.LIMITS.units + 1] = nil
  ok = Clean({ units = units })
  assert(ok ~= nil, "exactly the limit of units is accepted (the second return is the value count)")
end

---------------------------------------------------------------------------
-- 3. Weights.clean: invalid
---------------------------------------------------------------------------
do
  local function bad(mutate)
    local raw = { units = { { class = "WARRIOR", line = 1, weights = { STR = 1 }, priority = { "STR", "CRIT" }, use = true } } }
    mutate(raw.units[1])
    local ok, reason = Clean(raw)
    assert(ok == nil and reason == "invalid", "invalid: " .. tostring(reason))
  end
  bad(function(u) u.class = "warrior" end)        -- class must be uppercase
  bad(function(u) u.class = "" end)               -- class must not be empty
  bad(function(u) u.class = ("W"):rep(25) end)    -- class beyond the 24-char limit
  bad(function(u) u.line = 0 end)                 -- line below 1
  bad(function(u) u.line = 1.5 end)               -- line must be a whole number
  bad(function(u) u.line = TC.LIMITS.line + 1 end) -- line beyond the limit
  do
    local raw = { units = {
      { class = "WARRIOR", line = 1, use = true },
      { class = "WARRIOR", line = 1, use = true },
    } }
    local ok, reason = Clean(raw)
    assert(ok == nil and reason == "invalid", "a duplicate class:line is refused")
  end
  bad(function(u) u.weights = { BOGUS = 1 } end)          -- unknown stat in weights
  bad(function(u) u.weights = { STR = -1 } end)           -- weight below 0
  bad(function(u) u.weights = { STR = TC.LIMITS.weight + 1 } end) -- weight above the limit
  bad(function(u) u.weights = { STR = math.huge } end)    -- weight not finite
  bad(function(u) u.weights = "nope" end)                 -- weights not a table
  bad(function(u) u.priority = { "ARMOR" } end)           -- armor cannot be ranked
  bad(function(u) u.priority = { "STR", "STR" } end)      -- a repeated stat
  bad(function(u) u.priority = { "STR", 1 } end)          -- a non-string entry
  bad(function(u) u.use = "yes" end)                      -- use must be a boolean
  local ok, reason = Clean({ units = { { class = "WARRIOR", line = 1, weights = { STR = 0 } } } })
  assert(ok ~= nil, "a zero weight is accepted (0 is in the allowed range)")
  -- An empty weights/priority part is dropped, not fatal, as long as another part is usable.
  do
    local raw = { units = { { class = "WARRIOR", line = 1, weights = {}, priority = { "STR", "CRIT" }, use = true } } }
    local out, values = Clean(raw)
    assert(out ~= nil and out.units[1].weights == nil, "an empty weights part is dropped")
    assert(values == 1 + 2, "one value per unit plus its priority entries; the dropped weights and use add none")
  end
  do
    local raw = { units = { { class = "WARRIOR", line = 1, weights = { STR = 1 }, priority = {}, use = true } } }
    local out, values = Clean(raw)
    assert(out ~= nil and out.units[1].priority == nil, "an empty priority part is dropped")
    assert(values == 1 + 1, "one value per unit plus its weight entries; the dropped priority and use add none")
  end
  do
    local raw = { units = { { class = "WARRIOR", line = 1 } } }
    local ok, reason = Clean(raw)
    assert(ok == nil and reason == "invalid", "a unit with no usable part is refused")
  end
end

---------------------------------------------------------------------------
-- 4. Weights.clean: empty
---------------------------------------------------------------------------
do
  local ok, reason = Clean({ units = {} })
  assert(ok == nil and reason == "empty", "no units at all is empty")
end

---------------------------------------------------------------------------
-- 5. Weights.clean: accepted units come back with class/line; the value count
---------------------------------------------------------------------------
do
  local raw = { units = {
    { class = "WARRIOR", line = 1, weights = { STR = 1, CRIT = 11 }, priority = { "STR", "CRIT" }, use = true },
    { class = "ROGUE", line = 2, weights = { AGI = 1 }, use = false },
  } }
  local out, values = Clean(raw)
  assert(type(out) == "table" and type(out.units) == "table", "the cleaned group is returned")
  assert(values == 1 + 2 + 2 + 1 + 1, "one value per unit plus its weight and priority entries")
  local u1, u2 = out.units[1], out.units[2]
  assert(u1.class == "WARRIOR" and u1.line == 1, "class and line are attached")
  assert(u1.weights.STR == 1 and u1.weights.CRIT == 11, "weights survive")
  assert(u1.priority[1] == "STR" and u1.priority[2] == "CRIT" and #u1.priority == 2, "priority order survives")
  assert(u1.use == true, "use true survives")
  assert(u2.class == "ROGUE" and u2.line == 2, "second unit keeps its class and line")
  assert(u2.use == nil, "use false is dropped, the ranking alone is the part")
  assert(u2.priority == nil and type(u2.weights) == "table" and u2.weights.AGI == 1, "only the parts sent are kept")
end

---------------------------------------------------------------------------
-- 6. Weights.plan: rows only for the units that would change, with their labels
---------------------------------------------------------------------------
do
  -- Live tables hold WARRIOR:1 exactly as the share says, and WARRIOR:2 with different weights.
  Gear.weights = { WARRIOR = { [1] = { STR = 1, CRIT = 11 }, [2] = { STR = 0.5 } } }
  Gear.priority = { WARRIOR = { [1] = { "STR", "CRIT" } } }
  Gear.usePriority = { WARRIOR = { [1] = true } }
  local clean = { units = {
    { class = "WARRIOR", line = 1, weights = { STR = 1, CRIT = 11 }, priority = { "STR", "CRIT" }, use = true },
    { class = "WARRIOR", line = 2, weights = { STR = 1 } },
    { class = "PALADIN", line = 1, use = true },
  } }
  local rows = WT.plan(clean)
  assert(#rows == 2, "only the two changed units are planned")
  assert(rows[1].class == "WARRIOR" and rows[1].line == 2 and rows[1].what == "stat weights",
    "changed weights are named stat weights")
  assert(rows[2].class == "PALADIN" and rows[2].line == 1 and rows[2].what == "weighing by ranking",
    "a new use flag is named weighing by ranking")
  -- Same weights, different ranking, same use.
  Gear.usePriority = { WARRIOR = { [2] = true } }
  clean = { units = { { class = "WARRIOR", line = 2, weights = { STR = 0.5 }, priority = { "CRIT" }, use = true } } }
  rows = WT.plan(clean)
  assert(#rows == 1 and rows[1].what == "stat ranking", "a changed ranking is named stat ranking")
  -- Nothing differs: no rows.
  Gear.priority = { WARRIOR = { [2] = { "CRIT" } } }
  rows = WT.plan(clean)
  assert(#rows == 0, "a matching share plans nothing")
  Gear.weights, Gear.priority, Gear.usePriority = {}, {}, {}
end

---------------------------------------------------------------------------
-- 7. Weights.apply / restore: only the planned units are rewritten, undo puts them back
---------------------------------------------------------------------------
do
  -- Before: WARRIOR:1 has its own weights, ranking and use; WARRIOR:2 has only weights; ROGUE:3 is untouched.
  Gear.weights = { WARRIOR = { [1] = { STR = 1 }, [2] = { AGI = 0.9 } }, ROGUE = { [3] = { AGI = 1 } } }
  Gear.priority = { WARRIOR = { [1] = { "STR" } } }
  Gear.usePriority = { WARRIOR = { [1] = true } }
  local before = {}
  for name, byClass in pairs({ weights = Gear.weights, priority = Gear.priority, usePriority = Gear.usePriority }) do
    before[name] = {}
    for class, byLine in pairs(byClass) do before[name][class] = {} for line, v in pairs(byLine) do before[name][class][line] = v end end
  end
  local clean = { units = {
    { class = "WARRIOR", line = 1, weights = { STR = 2 }, priority = { "STR", "CRIT" }, use = true },
    { class = "WARRIOR", line = 2, weights = { AGI = 1 } },
    { class = "ROGUE", line = 3, weights = { AGI = 1 } },
  } }
  local plan = WT.plan(clean)
  assert(#plan == 2, "WARRIOR:1 and WARRIOR:2 change, ROGUE:3 does not")
  local undo = WT.apply(clean, plan)
  assert(#undo == 2, "one undo record per changed unit")
  assert(DeepEq(Gear.weights.WARRIOR[1], { STR = 2 }), "the shared weights are written")
  assert(DeepEq(Gear.priority.WARRIOR[1], { "STR", "CRIT" }), "the shared ranking is written")
  assert(Gear.usePriority.WARRIOR[1] == true, "the shared use flag is written")
  assert(DeepEq(Gear.weights.WARRIOR[2], { AGI = 1 }), "the second changed unit is written")
  assert(DeepEq(Gear.weights.ROGUE[3], { AGI = 1 }) and Gear.priority.ROGUE == nil and Gear.usePriority.ROGUE == nil,
    "the unplanned unit is left exactly as it was")
  assert(DeepEq(undo[1].w, { STR = 1 }) and DeepEq(undo[1].p, { "STR" }) and undo[1].u == true,
    "the undo record holds the previous values")
  local n = WT.restore(undo)
  assert(n == 2, "both records are put back")
  assert(DeepEq(Gear.weights, before.weights), "weights are back to what they held")
  assert(DeepEq(Gear.priority, before.priority), "rankings are back to what they held")
  assert(DeepEq(Gear.usePriority, before.usePriority), "use flags are back to what they held")
  Gear.weights, Gear.priority, Gear.usePriority = {}, {}, {}
end

print("TEST_TWICHCONFIG_WEIGHTS PASSED")
