-- TwichUI Fishing: catches and sessions (TwichUI_Fishing/Loot.lua, Session.lua). Attribution from loot events only, duplicate
-- events, several items in one catch, auto-loot without slot events (confirmed by the client's loot line), items left behind,
-- unrelated loot, session start/end/idle, duration, per-species and per-zone totals. Simulated client (tests/fishing_mock.lua).
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c, W = FishingClient()
c.TwichUI.RunCommand("fish")
local F = c.TwichUI.Fishing
local Ses = F.Session
local function T() return F.API.Totals() end
local function Cur() return Ses.Current() end

---------------------------------------------------------------------------
-- Nothing counts without fishing loot
---------------------------------------------------------------------------
W.Give(FISH1, 3); W.Settle()
Check(Cur() == nil and T().items == 0, "bags changing alone is never a catch")
W.Loot({ { JUNK, 1 } }, { fishing = false })
Check(Cur() == nil and T().catches == 0 and T().items == 0, "a mob's loot is not a catch")

---------------------------------------------------------------------------
-- A catch: one interaction, items counted as they reach the bags
---------------------------------------------------------------------------
W.StartLine()
Check(Cur() and Cur().casts == 1, "the first cast begins a session")
local items = {}
F.Subscribe("ITEM", function(_, id, q, how) items[#items + 1] = { id, q, how } end)
local catches = 0
F.Subscribe("CATCH", function() catches = catches + 1 end)
W.Loot({ { FISH1, 1 }, { FISH2, 2 } }, { fishing = true })
W.StopLine()
local s = Cur()
Check(s.catches == 1 and s.items == 3 and catches == 1, "two kinds of fish in one catch: one catch, three items")
Check(s.species[FISH1].q == 1 and s.species[FISH2].q == 2 and s.species[FISH2].c == 1, "per species: quantity and times caught")
Check(items[2][1] == FISH2 and items[2][2] == 2 and items[2][3] == "direct", "notified as direct catches")
Check(T().catches == 1 and T().items == 3 and T().species[FISH2].q == 2, "lifetime totals follow at once")
Check(s.first and s.last and s.zones[1429].catches == 1 and s.zones[1429].items == 3, "timestamps and the zone")
Check(F.API.ZoneName(1429) == "Elwynn Forest", "the zone's name is kept once")
W.Advance(2)

---------------------------------------------------------------------------
-- Duplicate events: every event twice is still one catch and the same items
---------------------------------------------------------------------------
W.StartLine()
W.Loot({ { FISH1, 1 } }, { fishing = true, twice = true })
W.StopLine()
s = Cur()
Check(s.catches == 2 and s.items == 4, "every loot event delivered twice: counted once")
Check(F.Loot.Status().duplicates >= 3, "and the duplicates were seen and ignored")
W.Advance(2)

---------------------------------------------------------------------------
-- Auto-loot with no slot events: the client's own loot line confirms them; nothing else does
---------------------------------------------------------------------------
W.StartLine()
W.Loot({ { FISH1, 1 }, { FISH2, 3 } }, { fishing = true, noClearEvents = true, chat = true })
W.StopLine()
s = Cur()
Check(s.catches == 3 and s.items == 8, "loot lines confirmed both slots (1 + 3)")
W.Advance(3)
W.StartLine()
W.Loot({ { FISH1, 1 } }, { fishing = true, noClearEvents = true })
W.StopLine()
W.Advance(3)
s = Cur()
Check(s.catches == 4 and s.items == 8, "no clear event and no loot line: the catch counts, the item does not")
Check(F.noteCounts["left-in-loot"] == 1, "and it is noted as left")
-- a loot line arriving after the wait is too late to count
c.FireEvent("CHAT_MSG_LOOT", c.LOOT_ITEM_SELF:format(FISH_LINK(FISH1)), "")
Check(Cur().items == 8, "a late loot line is not attached to anything")
-- someone else's loot line (no window held) changes nothing
W.StartLine()
W.Loot({ { FISH1, 1 } }, { fishing = true })
W.StopLine()
c.FireEvent("CHAT_MSG_LOOT", c.LOOT_ITEM_SELF:format(FISH_LINK(FISH1)), "")
Check(Cur().items == 9, "a loot line never adds to a slot already counted")
W.Advance(3)

---------------------------------------------------------------------------
-- Full bags: what stays in the window is not counted
---------------------------------------------------------------------------
W.StartLine()
W.Loot({ { FISH1, 1 }, { FISH2, 1 } }, { fishing = true, take = function(i) return i == 1 end })
W.StopLine(); W.Advance(3)
Check(Cur().catches == 6 and Cur().items == 10, "only what reached the bags")

---------------------------------------------------------------------------
-- Unrelated loot in the middle of a session; money
---------------------------------------------------------------------------
W.Loot({ { JUNK, 5 } }, { fishing = false })
W.Loot({ { JUNK, 5 } }, { fishing = false, fromItem = true })
Check(Cur().items == 10 and Cur().catches == 6 and T().species[JUNK] == nil, "other loot during a session is not fishing")
W.StartLine()
W.Loot({ { 0, money = true }, { FISH1, 1 } }, { fishing = true })
W.StopLine(); W.Advance(3)
Check(Cur().items == 11, "a money slot is not an item")

---------------------------------------------------------------------------
-- Delayed order: loot arrives just after the channel stops (still the same line, not missed)
---------------------------------------------------------------------------
local missed = Cur().missed
W.StartLine()
W.StopLine()
W.Advance(0.3)
W.Loot({ { FISH2, 1 } }, { fishing = true })
W.Advance(3)
Check(Cur().missed == missed and Cur().catches == 8, "loot just after the line ended is that line's catch")

---------------------------------------------------------------------------
-- Session: duration, the history, idle end, lifetime totals kept
---------------------------------------------------------------------------
local id = Cur().id
local start = Cur().start
W.Advance(100)
c.TwichUI.RunCommand("fish stop")
Check(Cur() == nil, "ended")
local last = F.API.Sessions(1)[1]
Check(last.id == id and last.seconds == last.stop - start and last.seconds >= 100 and last.recent == nil, "duration kept; recent catches dropped")
Check(T().seconds == last.seconds and T().sessions == 1, "lifetime time and session count")
Check(last.catches == 8 and T().catches == 8, "a session's counts survive in the history")
-- a new session, then idle
W.StartLine(); W.Loot({ { FISH1, 1 } }, { fishing = true }); W.StopLine()
Check(Cur().id == id + 1, "the next session")
local lastActivity = Cur().last
W.Advance(9 * 60)
Check(Cur() ~= nil, "nine idle minutes: still fishing")
W.Advance(2 * 60)
Check(Cur() == nil, "ten minutes without fishing ends it")
last = F.API.Sessions(1)[1]
Check(last.ended == "idle" and last.stop == lastActivity, "at its last activity " .. tostring(last.ended) .. " " .. tostring(last.stop) .. " " .. tostring(lastActivity))
Check(T().sessions == 2 and T().catches == 9, "lifetime totals kept across sessions")
c.TwichUI.RunCommand("fish idle 30")
Check(F.Store.Get("session.idleMinutes") == 30, "idle time is configurable")
-- retention: only the configured number of summaries is kept, totals are not reduced
F.Store.Set("session.keep", 10)
for i = 1, 14 do Ses.Start("test"); Ses.End("test") end
Check(#F.API.Sessions() == 10, "at most the configured number of summaries")
Check(F.API.Sessions(1)[1].id == id + 15 and T().sessions == 16 and T().catches == 9, "the newest are kept; lifetime totals are whole")

---------------------------------------------------------------------------
-- Per zone
---------------------------------------------------------------------------
W.map, W.zone = 1411, "Durotar"
W.StartLine(); W.Loot({ { FISH2, 2 } }, { fishing = true }); W.StopLine()
Check(T().zones[1411].catches == 1 and T().zones[1411].items == 2 and T().zones[1429].catches == 9, "each zone counted on its own")
Check(F.API.ZoneName(1411) == "Durotar", "and named")

-- the API returns copies
local copy = F.API.Totals()
copy.catches = 9999
Check(T().catches == 10, "changing what the API returned changes nothing saved")

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_loot")
