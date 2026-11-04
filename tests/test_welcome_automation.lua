dofile(TESTS .. "harness.lua")
-- WelcomeAutomation: On, IsMage, Wait and Summary, checked directly where they are exported and
-- through the summary's own scope text where they are not (Wait is local to the module).
-- Expected values are the contract's, from the module's own comments (only an explicit true is on;
-- a saved false stays false; nil/non-number/<=0 waits are "at once"; pages in order, once each),
-- not copied out of a run.

local c = MakeClient("Rich", { "!!!TwichUI" })
c.LOADED["!!!TwichUI"] = true
c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_LOGIN")
local chunk = assert(loadfile(ROOT .. "modules/WelcomeAutomation.lua"))
setfenv(chunk, c)
chunk("!!!TwichUI", {})
local A = c.TwichUI.WelcomeAutomation
assert(type(A) == "table" and type(A.On) == "function" and type(A.IsMage) == "function" and type(A.Summary) == "function",
  "the module exports On, IsMage and Summary")

local function Item(sum, key)
  for _, it in ipairs(sum.on) do if it.key == key then return it end end
  for _, it in ipairs(sum.off) do if it.key == key then return it end end
  return nil
end

---------------------------------------------------------------------------
-- On: the feature's own reading of its switch. Only an explicit true is on, so a damaged value
-- never reads as on; a saved false stays false (the `and ... or` trap); no saved value falls back
-- to DEFAULT_MODULES.
---------------------------------------------------------------------------
c.TwichUIDB.modules.qolDuels = true
assert(A.On("qolDuels") == true, "a saved true is on")
c.TwichUIDB.modules.qolDuels = false
assert(A.On("qolDuels") == false, "a saved false is off even though the default is true")
c.TwichUIDB.modules.qolDuels = "true"
assert(A.On("qolDuels") == false, "a damaged (string) value is not on")
c.TwichUIDB.modules.qolDuels = 1
assert(A.On("qolDuels") == false, "a damaged (number) value is not on")
c.TwichUIDB.modules.qolDuels = nil
assert(A.On("qolDuels") == false, "no saved value: the default for qolDuels is false")
assert(A.On("quietLogin") == true, "no saved value: the default for quietLogin is true")

---------------------------------------------------------------------------
-- IsMage: true for a Mage only. The MageSell feature's own ForPlayer reading wins over the class;
-- without it, UnitClass("player") decides; without either, false.
---------------------------------------------------------------------------
c.TwichUI.MageSell = { ForPlayer = function() return true end }
assert(A.IsMage() == true, "MageSell.ForPlayer true says Mage even for a non-Mage class")
c.TwichUI.MageSell = { ForPlayer = function() return false end }
c.UnitClass = function() return "Rich", "MAGE" end
assert(A.IsMage() == false, "MageSell.ForPlayer false wins over a Mage class")
c.TwichUI.MageSell = nil
assert(A.IsMage() == true, "no ForPlayer: a Mage class is a Mage")
c.UnitClass = function() return "Rich", "WARRIOR" end
assert(A.IsMage() == false, "no ForPlayer: a non-Mage class is not a Mage")
c.UnitClass = nil
assert(A.IsMage() == false, "no ForPlayer and no UnitClass: false")

---------------------------------------------------------------------------
-- Wait is local to the module, so it is checked through the one scope that renders it: the
-- "Accept summons" line (summonsFrom left at its default "friends, guild members and group members").
---------------------------------------------------------------------------
c.TwichUI.QoL = { Get = function(k) if k == "summonsWait" then return c.summonsWait end return nil end }
c.TwichUIDB.modules.qolSummons = true
local function SummonsText()
  local it = Item(A.Summary(), "qolSummons")
  assert(it and it.text ~= nil, "the summons entry is listed")
  return it.text
end
local base = "Accepts a summons from friends, guild members and group members, "
c.summonsWait = nil
assert(SummonsText() == base .. "at once. Other kinds of summons are left to you.", "a nil wait is at once")
c.summonsWait = "soon"
assert(SummonsText() == base .. "at once. Other kinds of summons are left to you.", "a non-number wait is at once")
c.summonsWait = 0
assert(SummonsText() == base .. "at once. Other kinds of summons are left to you.", "a zero wait is at once")
c.summonsWait = -5
assert(SummonsText() == base .. "at once. Other kinds of summons are left to you.", "a negative wait is at once")
c.summonsWait = 1
assert(SummonsText() == base .. "after 1 second. Other kinds of summons are left to you.", "one second, singular")
c.summonsWait = 5
assert(SummonsText() == base .. "after 5 seconds. Other kinds of summons are left to you.", "five seconds, plural")

---------------------------------------------------------------------------
-- Summary: each available feature once, in order; pages deduped in first-seen order; a scope() that
-- errors yields an on-item with empty text, not a crash; off items carry the entry's off phrase.
---------------------------------------------------------------------------
c.summonsWait = nil
c.TwichUIDB.modules.qolSummons = nil
c.TwichUIDB.modules.qolDuels = nil
c.TwichUI.QoL = { Get = function() return nil end }
local sum = A.Summary()
assert(#sum.on == 2 and sum.on[1].key == "groupCheck" and sum.on[2].key == "quietLogin",
  "only the entries whose files are present are listed, in entry order")
assert(#sum.off == 4 and sum.off[1].key == "qolSummons" and sum.off[4].key == "qolDuels",
  "the four QoL switches are listed off, in entry order")
assert(sum.off[4].text == "declining duel requests", "an off item carries the entry's off phrase")
assert(sum.pages[1] == "qol" and sum.pages[2] == "sharing" and sum.pages[3] == "overview" and #sum.pages == 3,
  "pages are deduped in first-seen order")

-- A scope() that errors: the entry is still listed on, with empty text.
c.TwichUI.QoL = { Get = function() error("boom") end }
c.TwichUIDB.modules.qolSummons = true
local bad = A.Summary()
local it = Item(bad, "qolSummons")
assert(it and it.text == "", "a scope that errors is an on-item with empty text, not a crash")

print("TEST_WELCOME_AUTOMATION PASSED")
