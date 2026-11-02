-- NextId in hazard/Config.lua (local, exercised through HZ.Add): a new rule's id is "c" .. n, the smallest n above
-- the stored counter whose id is not already taken by a stored rule, and the counter is written back to t.next.
-- tests/test_hazard.lua only checks that two fresh adds differ; this seeds TwichUIDB.ui.hazardCustom with existing
-- rule ids and a stale or broken next counter so the repeat-until-free loop and its write-back are exercised.
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })

for _, f in ipairs({ "hazard/Config.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = {} }
local HZ = c.TwichUI.Hazard

local function Seed(rules, nextValue)   -- a stored rule as hazard/Config.lua stores it; nextValue = nil leaves next unset
  local t = { rules = rules }
  if nextValue ~= nil then t.next = nextValue end
  c.TwichUIDB.ui = { hazardCustom = t }
  return t
end
local function Rule(id, spell)
  return { id = id, enabled = true, name = "seed " .. id, spell = spell, trigger = "applied", category = "low", throttle = 2 }
end
local function Fields(spell)
  return { name = "New", spell = spell, trigger = "applied", category = "low", throttle = 2 }
end

---------------------------------------------------------------------------
-- 1. Stale counter: rules c1..c3, next = 1. The loop climbs past the taken c2 and c3 and lands on the first free id.
---------------------------------------------------------------------------
do
  local t = Seed({ Rule("c1", 101), Rule("c2", 102), Rule("c3", 103) }, 1)
  local ok, id = HZ.Add(Fields(104))
  assert(ok, "a rule is added on top of stored ones")
  assert(id == "c4", "c1..c3 are taken, so the counter (1) climbs to the first free number: 4")
  assert(t.next == 4, "the counter is written back for the next add")
  assert(HZ.Find(id) and HZ.Find(id).spell == 104, "the new rule is stored and findable")
  assert(not HZ.Find("c0") and #c.TwichUIDB.ui.hazardCustom.rules == 4, "the placeholder id c0 is not kept")
end

---------------------------------------------------------------------------
-- 2. Counter behind a gap: rule c5, next = 3. c4 is free, so the loop stops there; the taken c5 is never handed out.
---------------------------------------------------------------------------
do
  local t = Seed({ Rule("c5", 201) }, 3)
  local ok, id = HZ.Add(Fields(202))
  assert(ok, "a rule is added on top of stored ones")
  assert(id == "c4", "c4 is the first free number above 3; the taken c5 is skipped, not returned")
  assert(t.next == 4, "the counter is written back for the next add")
  assert(HZ.Find(id) and HZ.Find("c5").spell == 201, "the new rule is findable and the seeded rule is untouched")
end

---------------------------------------------------------------------------
-- 3. Counter pointing at a taken id: rule c4, next = 3. The loop must step over the taken c4.
---------------------------------------------------------------------------
do
  local t = Seed({ Rule("c4", 301) }, 3)
  local ok, id = HZ.Add(Fields(302))
  assert(ok, "a rule is added on top of stored ones")
  assert(id == "c5", "c4 is taken, so the counter steps over it to the next free number: 5")
  assert(t.next == 5, "the counter is written back for the next add")
  assert(HZ.Find(id) and HZ.Find(id).spell == 302, "the new rule is stored and findable")
end

---------------------------------------------------------------------------
-- 4. A broken stored counter (nil, then a string) reads as 0; a free id is still produced and persisted.
---------------------------------------------------------------------------
do
  local t = Seed({ Rule("c1", 401) })   -- no next at all
  local ok, id = HZ.Add(Fields(402))
  assert(ok and id == "c2", "a missing counter starts at 0 and climbs to the first free number: 2")
  assert(t.next == 2, "the counter is written back for the next add")
  assert(HZ.Find(id) and HZ.Find(id).spell == 402, "the new rule is stored and findable")

  local t2 = Seed({ Rule("c1", 403), Rule("c2", 404) }, "stale")
  local ok2, id2 = HZ.Add(Fields(405))
  assert(ok2 and id2 == "c3", "a non-number counter is ignored and the taken c1, c2 are skipped: 3")
  assert(t2.next == 3, "the counter is written back for the next add")
  assert(HZ.Find(id2) and HZ.Find(id2).spell == 405, "the new rule is stored and findable")
end

print("TEST_HAZARD_RULE_IDS PASSED")
