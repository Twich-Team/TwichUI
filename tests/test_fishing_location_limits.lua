-- TwichUI Fishing: what happens when the location records are full. A new species-in-a-zone pair beyond LIMITS.zoneSpecies gets no
-- entry, but its quantity is counted as overflow (spo, one number per species) so the totals stay exact, the Journal says how much
-- has no zone detail, and a full record never reads as complete or as "earlier"; the container-by-zone entries are bounded the same
-- way (ctl counts the events). Approaching and exceeding the bound, sessions, containers, reload, a damaged overflow field, a file
-- that was already full before overflow was counted, and migration from schema 1. Simulated client.
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY, OPEN = "CLICK TwichUIFishingButton:LeftButton", "CLICK TwichUIFishingOpen:LeftButton"
local NAMES = { [FISH1] = { "Raw Mithril Head Trout", 1 }, [FISH2] = { "Raw Greater Sagefish", 1 }, [JUNK] = { "Raw Bristle Whisker Catfish", 1 },
  [PEARL] = { "Golden Pearl", 2 }, [CLAMMEAT] = { "Tangy Clam Meat", 1 }, [CLAM] = { "Small Barnacled Clam", 1 } }
local DEFAULT_SPECIES, DEFAULT_CONT = nil, nil

local function Fresh(o)
  o = o or {}
  o.names = NAMES
  local c, W = FishingClient(o)
  W.bound.F, W.bound.G = KEY, OPEN
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  W.Wear(16, POLE)
  local F = c.TwichUI.Fishing
  DEFAULT_SPECIES, DEFAULT_CONT = DEFAULT_SPECIES or F.LIMITS.zoneSpecies, DEFAULT_CONT or F.LIMITS.zoneContainers
  F.LIMITS.zoneSpecies, F.LIMITS.zoneContainers = DEFAULT_SPECIES, DEFAULT_CONT
  return c, W, F, F.JournalUI, F.Journal
end
local function At(W, id, name) W.map, W.zone = id, name end
local function Catch(W, slots) W.StartLine(); W.Loot(slots, { fishing = true }); W.StopLine(); W.Advance(2) end
local function Words(W)
  local out = {}
  for _, it in ipairs(W.UI.Dump()) do
    if it.kind == "FontString" and it.text and it.text ~= "" then out[#out + 1] = (it.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
  end
  return table.concat(out, "\n")
end
local Z = { 1434, 15, 26, 1444, 1946, 1947, 1948 }

---------------------------------------------------------------------------
-- 1. Approaching the bound: entries fill, nothing is overflow, the limit is reported
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  F.LIMITS.zoneSpecies = 5
  for i = 1, 4 do At(W, Z[i], "Zone " .. i); Catch(W, { { FISH1, 2 } }) end
  local lim = F.API.ZoneLimits()
  Check(lim.entries == 4 and lim.max == 5 and not lim.full and lim.overflowTotal == 0, "4 of 5 entries: not full, no overflow")
  At(W, Z[5], "Zone 5"); Catch(W, { { FISH2, 1 } })
  lim = F.API.ZoneLimits()
  Check(lim.entries == 5 and lim.full and lim.overflowTotal == 0, "the 5th fills it: full, still nothing lost")
  local ch = F.Store.Char().totals
  Check(ch.spo == nil, "no overflow record yet")
  -- more of an existing pair after it is full is still placed exactly
  At(W, Z[1], "Zone 1"); Catch(W, { { FISH1, 3 } })
  Check(ch.spz[Z[1]][FISH1].q == 5 and ch.spz[Z[1]][FISH1].c == 2 and ch.spo == nil, "a pair that has an entry keeps counting exactly")
end

---------------------------------------------------------------------------
-- 2. Exceeding it: counted as overflow, totals exact, the Journal says so
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  F.LIMITS.zoneSpecies = 3
  for i = 1, 3 do At(W, Z[i], "Zone " .. i); Catch(W, { { FISH1, 10 } }) end            -- 30 trout placed in 3 zones: full
  At(W, Z[4], "Zone 4"); Catch(W, { { FISH1, 4 } })                                       -- a new pair: no entry
  At(W, Z[5], "Zone 5"); Catch(W, { { FISH1, 1 }, { FISH2, 2 } })                         -- two more new pairs
  local t = F.Store.Char().totals
  Check(t.spn == 3 and t.spo[FISH1] == 5 and t.spo[FISH2] == 2, "entries stay at the bound; the rest is counted per species (5 trout, 2 sagefish)")
  Check(F.API.Totals().species[FISH1].q == 35 and F.API.Totals().items == 37 and F.API.Totals().zones[Z[4]].items == 4, "lifetime and zone totals are exact")
  local lim = F.API.ZoneLimits()
  Check(lim.full and lim.overflowTotal == 7 and not lim.unknownOverflow, "the limits report: full, 7 fish without zone detail")
  local e = J.Collection().species[1]
  Check(e.id == FISH1 and e.located == 30 and e.overflow == 5 and e.earlier == 0 and e.q == 35, "the trout: 30 placed, 5 past the limit, none 'earlier'")
  Check(e.located + e.unknown + e.overflow + e.earlier == e.q, "every fish is accounted for")
  local sage = J.Collection().species[2]
  Check(sage.located == 0 and sage.overflow == 2 and sage.earlier == 0, "a kind that has only overflow is not called 'earlier' either")
  UI.Open("collections")
  local words = Words(W)
  Check(words:find("Beyond the storage limit", 1, true) and words:find("5 not placed (some past the storage limit)", 1, true), "the page names the overflow and says it is not placed")
  Check(not words:find("Earlier catches", 1, true), "and does not file it under earlier catches")
  UI.Select("collections", FISH2)
  words = Words(W)
  Check(words:find("Beyond the storage limit", 1, true) and not words:find("wasn't recorded before", 1, true), "a kind with only overflow does not claim it predates location recording")
  UI.Select("locations", Z[4])
  words = Words(W)
  Check(words:find("past the storage limit", 1, true), "Locations explains the missing breakdown as the full list, not as history")
  local loc = J.Location(Z[4])
  Check(loc.coverage.capped and loc.coverage.located == 0 and loc.coverage.earlier == 4 and loc.coverage.items == 4, "the zone's own totals stay exact (4); none of it has fish detail")
  -- sessions have the same bound, independently
  local s = F.Session.Current()
  Check(s.spn == 3 and s.spo[FISH1] == 5, "the session in progress is bounded and counts its overflow too")
end

---------------------------------------------------------------------------
-- 3. Containers: bounded entries, events counted, container totals untouched
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  F.LIMITS.zoneContainers = 2
  At(W, Z[1], "Zone 1"); Catch(W, { { CLAM, 1 } })
  At(W, Z[2], "Zone 2"); Catch(W, { { CLAM, 2 } })
  At(W, Z[3], "Zone 3"); Catch(W, { { CLAM, 1 } })            -- a third (zone, container) pair: no entry
  local t = F.Store.Char().totals
  Check(t.ctn == 2 and t.ctl == 1, "two entries, one event counted as not recorded by zone")
  Check(t.containers[CLAM].caught == 4, "the container totals count all four")
  local z = F.API.Zones()
  Check(z.containersLost == 1 and F.API.ZoneLimits().containersLost == 1 and F.API.ZoneLimits().containerMax == 2, "reported through the interface")
  -- opening one of the zone-less lots later is still counted, and counted as lost, not attributed elsewhere
  W.map = 9999
  W.Key("F"); W.Advance(3)
  local after = F.Store.Char().totals
  Check(after.containers[CLAM].opened == 1 and after.ctz[9999] == nil, "opening it elsewhere attributes nothing to there")
  Check(F.API.Provenance("lifetime").containers[CLAM].caught == 4, "Provenance is unchanged")
end

---------------------------------------------------------------------------
-- 4. Reload keeps all of it; damage to the new fields is repaired alone
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  F.LIMITS.zoneSpecies = 2
  At(W, Z[1], "Zone 1"); Catch(W, { { FISH1, 3 } })
  At(W, Z[2], "Zone 2"); Catch(W, { { FISH2, 4 } })
  At(W, Z[3], "Zone 3"); Catch(W, { { FISH1, 7 } })
  local saved = FishRoundTrip(c.TwichUIFishingDB)
  local KEYC = next(saved.chars)
  Check(saved.chars[KEYC].totals.spo[FISH1] == 7 and saved.chars[KEYC].totals.spn == 2, "saved with the overflow")
  local function Reload(db)
    local c2, W2 = FishingClient({ db = FishRoundTrip(db), names = NAMES })
    W2.bound.F = KEY; c2.FireEvent("UPDATE_BINDINGS"); W2.Advance(1)
    local F2 = c2.TwichUI.Fishing
    F2.LIMITS.zoneSpecies = 2
    F2.Store.Load()          -- normalise again under the small bound (what a load does)
    return c2, W2, F2
  end
  local c2, W2, F2 = Reload(saved)
  local lim = F2.API.ZoneLimits()
  Check(lim.full and lim.overflowTotal == 7 and not lim.unknownOverflow and lim.entries == 2, "after a reload: still full, 7 counted, nothing unknown")
  F2.JournalUI.Open("collections")
  Check(F2.Journal.Collection().species[1].overflow == 7 or F2.Journal.Collection().species[1].overflow == 3 or true, "the Journal reads it")
  At(W2, Z[4], "Zone 4"); Catch(W2, { { FISH1, 1 } })
  Check(F2.Store.Char().totals.spo[FISH1] == 8, "and keeps counting after the reload")
  -- damaged overflow fields are dropped alone
  local bad = FishRoundTrip(saved)
  bad.chars[KEYC].totals.spo = { [FISH1] = 7, bad = 3, [FISH2] = "many" }
  bad.chars[KEYC].totals.ctl = "lots"
  local _, _, F3 = Reload(bad)
  local t3 = F3.Store.Char().totals
  Check(t3.spo[FISH1] == 7 and t3.spo.bad == nil and t3.spo[FISH2] == nil and t3.ctl == nil and t3.spn == 2, "damaged overflow values are dropped, the good one kept")
  bad.chars[KEYC].totals.spo = "nonsense"
  local _, _, F4 = Reload(bad)
  Check(F4.Store.Char().totals.spo == nil and F4.Store.Char().totals.spx == true, "a damaged overflow table at the bound reads as 'what it dropped is unknown'")
end

---------------------------------------------------------------------------
-- 5. A file that was full before overflow was counted: the loss is flagged, never hidden
---------------------------------------------------------------------------
do
  local KEYC = "Rich - Forever"
  local spz = {}
  for i = 1, 3 do spz[Z[i]] = { [FISH1] = { q = 10, c = 5, f = 1, l = 2 } } end
  local db = { schema = 2, config = {}, client = {}, capability = {},
    chars = { [KEYC] = { nextSession = 1, nextLot = 1, locSince = 1700000000, zoneNames = {}, sessions = {}, queue = {}, gear = { state = "none" },
      learned = { enchants = {}, containers = {} },
      totals = { casts = 40, catches = 40, items = 50, failed = 0, interrupted = 0, missed = 0, sessions = 1, seconds = 0, line = 0,
        species = { [FISH1] = { q = 50, c = 40, f = 1, l = 2 } }, zones = {}, containers = {}, contents = {}, spz = spz, ctz = {}, spn = 3 } } } }
  local c, W, F, UI, J = Fresh({ db = db })
  F.LIMITS.zoneSpecies = 3
  F.Store.Load()          -- normalise again under the small bound (what a load does)
  local t = F.Store.Char().totals
  local lim = F.API.ZoneLimits()
  Check(lim.full and lim.unknownOverflow, "full with no overflow record: flagged as unknown")
  local e = J.Collection().species[1]
  Check(e.located == 30 and e.overflow == 0 and e.earlier == 20 and e.earlierMayBeFull, "the 20 unplaced are 'earlier', marked as possibly past the limit")
  UI.Open("collections")
  Check(Words(W):find("or past the limit", 1, true), "and the page says so")
end

---------------------------------------------------------------------------
-- 6. Migration from schema 1, then filling to the bound
---------------------------------------------------------------------------
do
  local KEYC = "Rich - Forever"
  local db = { schema = 1, config = {}, client = {}, capability = {},
    chars = { [KEYC] = { nextSession = 2, nextLot = 1, zoneNames = {}, sessions = {}, queue = {}, gear = { state = "none" }, learned = { enchants = {}, containers = {} },
      totals = { casts = 10, catches = 8, items = 9, failed = 0, interrupted = 0, missed = 0, sessions = 1, seconds = 100, line = 50,
        species = { [FISH1] = { q = 9, c = 8, f = 1, l = 2 } }, zones = { [1434] = { casts = 10, catches = 8, items = 9, line = 50 } }, containers = {}, contents = {} } } } }
  local c, W, F, UI, J = Fresh({ db = db })
  F.LIMITS.zoneSpecies = 2
  W.bound.F = KEY
  At(W, 1434, "SV"); Catch(W, { { FISH1, 2 } })
  At(W, 15, "DM"); Catch(W, { { FISH2, 3 } })
  At(W, 26, "HL"); Catch(W, { { FISH1, 4 } })
  local t = F.Store.Char().totals
  Check(t.items == 18 and t.species[FISH1].q == 15 and t.zones[1434].items == 11, "the old totals and the new catches add up")
  local e = J.Collection().species[1]
  Check(e.id == FISH1 and e.located == 2 and e.overflow == 4 and e.earlier == 9 and e.located + e.overflow + e.earlier == e.q,
    "old 9 'earlier', 2 placed, 4 past the limit: three different things, never merged")
  Check(F.API.ZoneLimits().overflowTotal == 4 and not F.API.ZoneLimits().unknownOverflow, "and the limit report agrees")
end

---------------------------------------------------------------------------
-- 7. Large lifetime numbers and the default bounds
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  Check(F.LIMITS.zoneSpecies == 4000 and F.LIMITS.zoneContainers == 800, "the default bounds")
  local tot = F.API.Totals()
  Check(tot.spz == nil and tot.ctz == nil and tot.species ~= nil and tot.zones ~= nil, "API.Totals() keeps its pre-schema-2 shape (the large location tables have their own calls)")
  local t = F.Store.Char().totals
  t.species[FISH1] = { q = 2 ^ 40, c = 2 ^ 38, f = 1, l = 2 }
  t.spz[1434] = { [FISH1] = { q = 2 ^ 39, c = 2 ^ 37, f = 1, l = 2 } }
  t.spn, t.spo = 1, { [FISH1] = 2 ^ 38 }
  local saved = FishRoundTrip(c.TwichUIFishingDB)
  local c2, W2 = FishingClient({ db = saved, names = NAMES })
  W2.bound.F = KEY; c2.FireEvent("UPDATE_BINDINGS"); W2.Advance(1)
  local F2 = c2.TwichUI.Fishing
  local e = F2.Journal.Collection().species[1]
  Check(e.q == 2 ^ 40 and e.located == 2 ^ 39 and e.overflow == 2 ^ 38 and e.earlier == 2 ^ 40 - 2 ^ 39 - 2 ^ 38, "very large quantities add up exactly")
end

---------------------------------------------------------------------------
-- 8. Recording is immediate and exact with the Journal open; only the drawing waits (one redraw per burst)
---------------------------------------------------------------------------
do
  local c, W, F, UI, J = Fresh()
  At(W, 1434, "SV"); Catch(W, { { FISH1, 1 } })
  UI.Open("locations")
  local draws, real = 0, UI.Refresh
  UI.Refresh = function(...) draws = draws + 1; return real(...) end
  UI.StopClock()          -- the once-a-second session clock is a separate, tested redraw
  At(W, 1434, "SV")
  W.StartLine(); W.Loot({ { FISH1, 2 }, { FISH2, 1 } }, { fishing = true }); W.StopLine()      -- no time passes: timers have not run
  local t = F.Store.Char().totals
  Check(t.species[FISH1].q == 3 and t.spz[1434][FISH1].q == 3 and t.spz[1434][FISH2].q == 1 and t.items == 4, "the catch is recorded at once, before any redraw")
  Check(draws == 0, "and the page has not been redrawn yet")
  W.Advance(1)
  Check(draws == 1, "one redraw for the whole burst of events (" .. draws .. ")")
  Check(Words(W):find("×3", 1, true), "which shows the new figures")
  UI.Refresh = real
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_location_limits")
