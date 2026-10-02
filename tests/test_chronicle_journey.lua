dofile(TESTS .. "harness.lua")
local function boot(saved)
  local c = MakeClient("Alpha", {"!!!TwichUI"})
  c.print = function() end
  c.TwichUIDB = saved and saved.db or {}
  c.TwichUIChronicleDB = saved and saved.chron or nil
  c.ZONE = "Elwynn Forest"
  c.GetRealZoneText = function() return c.ZONE end
  c.GetZoneText = c.GetRealZoneText
  c.LEVEL, c.MONEY, c.TAXI, c.KNOWN = 12, 50 * 10000, false, (saved and saved.known) or {}
  c.UnitLevel = function() return c.LEVEL end
  c.GetMoney = function() return c.MONEY end
  c.UnitOnTaxi = function() return c.TAXI end
  c.IsSpellKnown = function(id) return c.KNOWN[id] == true end
  c.requests = 0
  c.RequestTimePlayed = function() c.requests = c.requests + 1 end
  c.LOADED["!!!TwichUI"] = true
  c.FireEvent("ADDON_LOADED", "!!!TwichUI")
  c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
  return c
end
local function find(C, kind, title)
  for _, e in ipairs(C.Entries()) do if e.kind == kind and (not title or e.title == title) then return e end end
end
local function count(C, kind) local n = 0 for _, e in ipairs(C.Entries()) do if e.kind == kind then n = n + 1 end end return n end

-- duration formatting
local a = boot()
local C, Rec = a.TwichUI.Chronicle, a.TwichUI.ChronicleRecorder
assert(C.FormatDuration(10) == "under a minute" and C.FormatDuration(45 * 60) == "45m")
assert(C.FormatDuration(2 * 3600 + 34 * 60 + 59) == "2h 34m")
assert(C.FormatDuration(86400 + 3 * 3600 + 12 * 60) == "1d 3h 12m")
assert(C.FormatDuration(-1) == nil and C.FormatDuration(nil) == nil)

-- baseline at login: one request, answered with total and this-level time
assert(a.requests == 1, "baseline requested once at login")
a.FireEvent("TIME_PLAYED_MSG", 100000, 4000)
assert(C.Record().journey.baseLevel == 12 and C.Record().journey.baseTotal == 96000)
assert(not a.TwichUI.frame.events.TIME_PLAYED_MSG, "played handler removed after the answer")

-- level-up: entry at once, details when the answer arrives; total is used, not "this level"
a.LEVEL = 13
a.FireEvent("PLAYER_LEVEL_UP", 13)
local e = find(C, "level", "Reached level 13")
assert(e and not e.note and a.requests == 2)
a.FireEvent("PLAYER_LEVEL_UP", 13)                 -- duplicate event
assert(count(C, "level") == 1 and a.requests == 2)
a.FireEvent("TIME_PLAYED_MSG", 96000 + 9240, 3)    -- 2h 34m after the baseline
assert(e.secsAtLevel == 9240 and e.secsTotal == 105240, "level time from baseline")
assert(e.note == "Level 12 to 13: 2h 34m  ·  Total journey: 1d 5h 14m", e.note)
assert(C.Record().journey.baseLevel == 13 and C.Record().journey.baseTotal == 105240)

-- no answer: entry stays as written, handler and state are cleaned up
a.FireEvent("PLAYER_LEVEL_UP", 14)
local e14 = find(C, "level", "Reached level 14")
RunLongTimers(60)
assert(not e14.note and not a.TwichUI.frame.events.TIME_PLAYED_MSG)
a.FireEvent("TIME_PLAYED_MSG", 999999, 1)          -- a late answer is ignored
assert(not e14.note)
-- baseline is for 13, so the next level (15) has no per-level time, only the total
a.FireEvent("PLAYER_LEVEL_UP", 15)
a.FireEvent("TIME_PLAYED_MSG", 200000, 5)
local e15 = find(C, "level", "Reached level 15")
assert(e15.secsAtLevel == nil and e15.secsTotal == 200000 and e15.note == "Total journey: 2d 7h 33m", tostring(e15.note))

-- gold: spending doesn't reduce, offline/starting balance isn't counted, steps once
local g = C.Record().journey.gold
assert(g and g.earned == 0 and g.last == 500000, "baseline from current wallet, nothing earned")
a.MONEY = 20 * 10000; a.FireEvent("PLAYER_MONEY")          -- spend 30g
assert(g.earned == 0 and count(C, "gold") == 0)
a.MONEY = 31 * 10000; a.FireEvent("PLAYER_MONEY")          -- +11g
assert(find(C, "gold", "Earned 10 gold") and count(C, "gold") == 1)
a.MONEY = 9 * 10000; a.FireEvent("PLAYER_MONEY")
a.MONEY = 9 * 10000 + 60 * 10000; a.FireEvent("PLAYER_MONEY")   -- +60g -> 71 earned
assert(find(C, "gold", "Earned 50 gold") and count(C, "gold") == 2)
a.FireEvent("PLAYER_MONEY")                                -- no change, no repeat
a.MONEY = a.MONEY + 2000 * 10000; a.FireEvent("PLAYER_MONEY")   -- crosses 100, 500, 1000 together
assert(find(C, "gold", "Earned 100 gold") and find(C, "gold", "Earned 500 gold") and find(C, "gold", "Earned 1,000 gold"))
assert(count(C, "gold") == 5 and not find(C, "gold", "Earned 5,000 gold"))
-- reload keeps the totals; a change while logged out isn't income
a.MONEY = a.MONEY + 99999 * 10000
local b = boot({ db = a.TwichUIDB, chron = a.TwichUIChronicleDB })
b.FireEvent("PLAYER_MONEY")
assert(b.TwichUI.Chronicle.Record().journey.gold.earned == g.earned, "offline gain not counted")
assert(count(b.TwichUI.Chronicle, "gold") == 5)
assert(Rec.AddEarned({ earned = 0, done = {} }, 100000 * 10000)[7] == 10000, "every step crossed at once")

-- riding: once per rank, silent for ranks already known, nothing for other spells
a.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 1234, 1, false)
assert(count(C, "riding") == 0)
a.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 33388, 1, false)
a.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 33388, 1, false)
assert(count(C, "riding") == 1 and find(C, "riding", "Learned Apprentice Riding"))

local r = boot({ db = a.TwichUIDB, chron = a.TwichUIChronicleDB, known = { [33391] = true } })
r.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 33391, 1, false)
r.FireEvent("LEARNED_SPELL_IN_SKILL_LINE", 33388, 1, false)
assert(count(r.TwichUI.Chronicle, "riding") == 1, "known or recorded ranks aren't written again")

-- flight: nothing recorded in flight; destination once on landing
a.FireEvent("PLAYER_ENTERING_WORLD", false, false)
local zones = count(C, "zone")
a.FireEvent("PLAYER_CONTROL_LOST")
a.ZONE = "Westfall"; a.FireEvent("ZONE_CHANGED_NEW_AREA")
a.ZONE = "Duskwood"; a.FireEvent("ZONE_CHANGED_NEW_AREA")
a.ZONE = "Stranglethorn Vale"; a.FireEvent("ZONE_CHANGED_NEW_AREA")
assert(count(C, "zone") == zones, "no zones recorded in flight")
a.FireEvent("PLAYER_CONTROL_GAINED")
assert(count(C, "zone") == zones + 1 and find(C, "zone", "Arrived in Stranglethorn Vale") and not find(C, "zone", "Arrived in Westfall"))
a.FireEvent("PLAYER_CONTROL_GAINED"); assert(count(C, "zone") == zones + 1)
a.TAXI = true; a.ZONE = "Duskwood"; a.FireEvent("ZONE_CHANGED_NEW_AREA")
assert(count(C, "zone") == zones + 1, "UnitOnTaxi alone also suppresses")
a.TAXI = false; a.FireEvent("ZONE_CHANGED_NEW_AREA")
assert(find(C, "zone", "Arrived in Duskwood"), "ordinary travel still recorded")

-- old data loads without losing entries; toggling off stops new ones, keeps old ones
local old = boot({ chron = { version = 1, chars = { ["Alpha - Forever"] = { entries = {
  { id = 1, t = 100, kind = "level", title = "Reached level 5", level = 5 }, { id = 2, t = 200, kind = "note", title = "Note", note = "hi" } },
  nextId = 3, tracking = true } } } })
local OC = old.TwichUI.Chronicle
assert(OC.Count() >= 2 and OC.Find(1) and OC.Find(2) and OC.Record().journey.riding, "old record kept and upgraded")
old.TwichUIDB.modules.chronicle = false; old.TwichUI.ChronicleRecorder.Refresh()
local before = OC.Count()
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_MONEY", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_CONTROL_LOST", "ZONE_CHANGED_NEW_AREA" }) do
  assert(not old.TwichUI.frame.events[ev], ev .. " unregistered when off")
end
assert(OC.Count() == before and OC.Find(1))
print("PASSED chronicle journey")
