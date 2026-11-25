-- TwichUI Fishing: where fish were caught (Session.lua spz/ctz, Loot.lua, Containers.lua, Store.lua schema 2, Api.lua Zones).
-- A catch is attributed to the zone read at the confirmed fishing loot window, however late its items reach the bags; a
-- session may span zones; an unreadable zone is 0, never a guess; containers keep the zone they were caught in through the
-- queue, a reload and a late opening; nothing is counted twice; older records are kept as they were and never given a
-- location; the records stay compact. Simulated client (tests/fishing_mock.lua).
dofile(TESTS .. "fishing_mock.lua")
local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local KEY, OPEN = "CLICK TwichUIFishingButton:LeftButton", "CLICK TwichUIFishingOpen:LeftButton"
local SV, DM, HL = 1434, 15, 26      -- Stranglethorn Vale, Dustwallow Marsh, The Hinterlands (map ids as the scene says)
local STORM = 1453

local function Fresh(opts)
  local c, W = FishingClient(opts)
  W.bound.F, W.bound.G = KEY, OPEN
  c.FireEvent("UPDATE_BINDINGS"); W.Advance(1)
  W.Wear(16, POLE)
  return c, W, c.TwichUI.Fishing
end
local function Catch(W, slots, o)
  o = o or {}
  o.fishing = true
  W.StartLine(); W.Loot(slots, o); W.StopLine(); W.Advance(2)
end
local function Zones(F, scope) return F.API.Zones(scope) end
local function Sum(t) local n = 0 for _, e in pairs(t or {}) do n = n + e.q end return n end

---------------------------------------------------------------------------
-- 1. One species in one zone, several in one zone, one in several zones
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV
  Catch(W, { { FISH1, 2 } })
  Catch(W, { { FISH1, 1 }, { FISH2, 3 } })
  local z = Zones(F)
  Check(z.species[SV][FISH1].q == 3 and z.species[SV][FISH1].c == 2, "one species, one zone: quantity 3 in 2 catches")
  Check(z.species[SV][FISH2].q == 3 and z.species[SV][FISH2].c == 1, "several species in one zone")
  Check(z.species[SV][FISH1].f and z.species[SV][FISH1].l and z.species[SV][FISH1].f <= z.species[SV][FISH1].l, "first and most recent catch times")
  W.map = DM
  Catch(W, { { FISH1, 4 } })
  z = Zones(F)
  Check(z.species[DM][FISH1].q == 4 and z.species[SV][FISH1].q == 3, "the same species in another zone is kept apart")
  local t = F.API.Totals()
  Check(t.species[FISH1].q == 7 and t.items == 10 and t.catches == 3, "lifetime totals are unchanged by the zone records")
  Check(Sum({ [FISH1] = z.species[SV][FISH1], [FISH2] = z.species[SV][FISH2] }) + Sum({ [FISH1] = z.species[DM][FISH1] }) == t.items, "the zone records add up to the items caught")
  Check(t.zones[SV].items == 6 and t.zones[DM].items == 4, "zone item totals agree with them")
end

---------------------------------------------------------------------------
-- 2. A session that spans zones: each catch in the zone it happened in
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV; Catch(W, { { FISH1, 2 } })
  W.map = HL; Catch(W, { { FISH2, 5 } })
  W.map = SV; Catch(W, { { FISH2, 1 } })
  local s = F.Session.Current()
  Check(s.spz[SV][FISH1].q == 2 and s.spz[SV][FISH2].q == 1 and s.spz[HL][FISH2].q == 5, "the session's own species-by-zone")
  Check(s.zone == SV, "the session's start zone is only where it began")
  Check(s.zones[SV].catches == 2 and s.zones[HL].catches == 1, "catches counted in their zones")
  c.TwichUI.RunCommand("fish stop")
  local old = F.API.Sessions(1)[1]
  Check(old.spz[HL][FISH2].q == 5 and F.API.Zones(old.id).species[HL][FISH2].q == 5, "kept with the finished session, and through the API")
end

---------------------------------------------------------------------------
-- 3. The zone is read at the loot window, not when the items reach the bags
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV
  -- the player has moved on by the time the item is taken (slot cleared)
  Catch(W, { { FISH1, 1 }, { FISH2, 2 } }, { take = function() W.map = STORM; return true end })
  local z = Zones(F)
  Check(z.species[SV] and z.species[SV][FISH1].q == 1 and z.species[SV][FISH2].q == 2 and z.species[STORM] == nil,
    "items taken after the zone changed still belong to where the line was")
  Check(F.API.Totals().zones[SV].items == 3, "and so do the zone item totals")
  -- confirmed late by the client's own loot line, after the window closed and the zone changed
  W.map = DM
  local sess = F.Session.Current()
  Catch(W, { { FISH1, 1 } }, { noClearEvents = true, chat = true, afterClose = function() W.map = STORM end })
  z = Zones(F)
  Check(z.species[DM] and z.species[DM][FISH1].q == 1 and z.species[STORM] == nil, "a catch confirmed by the loot line later is attributed to the window's zone")
  Check(F.API.Totals().species[FISH1].q == 2, "and counted once")
end

---------------------------------------------------------------------------
-- 4. Duplicate loot events, auto-loot, and nothing counted twice
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV
  Catch(W, { { FISH1, 2 } }, { twice = true })
  local z = Zones(F)
  Check(z.species[SV][FISH1].q == 2 and z.species[SV][FISH1].c == 1, "every loot event delivered twice: one catch")
  Catch(W, { { FISH2, 1 } }, { auto = false })
  Catch(W, { { FISH2, 1 } }, { auto = true })
  z = Zones(F)
  Check(z.species[SV][FISH2].q == 2 and z.species[SV][FISH2].c == 2, "with and without auto-loot")
  local t = F.API.Totals()
  Check(t.items == 4 and Sum(z.species[SV]) == 4, "the zone records and the totals agree")
  -- loot that is not fishing loot records nothing
  W.StartLine(); W.Loot({ { FISH1, 1 } }, { fishing = false }); W.StopLine(); W.Advance(2)
  Check(Sum(Zones(F).species[SV]) == 4, "an unrelated loot window records nothing")
end

---------------------------------------------------------------------------
-- 5. A zone that cannot be read is 0, not a guess
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV; Catch(W, { { FISH1, 1 } })
  c.C_Map.GetBestMapForUnit = function() return nil end
  Catch(W, { { FISH1, 2 } })
  c.C_Map.GetBestMapForUnit = function() return 1434 end
  W.map = SV
  local z = Zones(F)
  Check(z.species[0] and z.species[0][FISH1].q == 2 and z.species[SV][FISH1].q == 1, "an unreadable zone is recorded as unknown (0)")
  Check(F.API.Totals().species[FISH1].q == 3, "the lifetime quantity still counts it")
end

---------------------------------------------------------------------------
-- 6. Containers: caught in one zone, opened elsewhere, later, after a reload
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV
  Catch(W, { { FISH1, 1 }, { CLAM, 2 } })
  local lot = F.API.Queue()
  Check(#lot == 1 and lot[1].n == 2, "queued")
  local ctz = Zones(F).containers
  Check(ctz[SV][CLAM].caught == 2 and ctz[SV][CLAM].opened == 0, "the container is recorded in the zone it was caught in")
  W.map = DM; Catch(W, { { CLAM, 1 } })
  Check(#F.API.Queue() == 2 and F.API.Queue()[1].n == 2, "a clam from another zone is another lot (a lot has one zone)")
  -- go to the city and open one
  W.map = STORM
  W.Key("F"); W.Advance(3)
  ctz = Zones(F).containers
  Check(ctz[SV][CLAM].opened == 1 and ctz[SV][CLAM].got[PEARL] == 1 and ctz[SV][CLAM].got[CLAMMEAT] == 1, "contents stay with the catch zone")
  Check(ctz[STORM] == nil, "nothing is attributed to where it was opened")
  Check(Sum(Zones(F).species[STORM]) == 0, "and the city has no direct catches")
  local s = F.Session.Current()
  Check(s.items == 4 and s.catches == 2 and s.species[PEARL] == nil, "contents are not catches or items of the session")
  -- end the session, reload, open the others (the oldest lot is from SV again)
  c.TwichUI.RunCommand("fish stop")
  local saved = FishRoundTrip(c.TwichUIFishingDB)
  local c2, W2 = FishingClient({ db = saved, epoch = W.epoch + 90 })
  W2.bound.G = OPEN; W2.bags = W.bags; W2.equipped = W.equipped; W2.map = HL
  c2.FireEvent("UPDATE_BINDINGS"); W2.Advance(1)
  local F2 = c2.TwichUI.Fishing
  local q = F2.API.Queue()
  Check(#q == 2, "the queue survives a reload")
  W2.Key("G"); W2.Advance(3)
  local z2 = Zones(F2).containers
  Check(z2[SV][CLAM].opened == 2 and z2[HL] == nil, "opened after the session ended and after a reload: still the zone it was caught in")
  local old = F2.API.Sessions(1)[1]
  Check(old.ctz[SV][CLAM].opened == 2 and F2.Session.Current() == nil, "credited to the finished session, which did not restart")
  -- provenance for valuation is unchanged: containers and contents apart, direct catches never include containers
  local p = F2.API.Provenance("lifetime")
  Check(p.direct[CLAM] == nil and p.containers[CLAM].caught == 3 and p.contents[PEARL] == 2, "Provenance keeps its contract")
  local t = F2.API.Totals()
  Check(t.items == 4 and t.species[PEARL] == nil, "no double counting: items are fish and the containers caught")
end

---------------------------------------------------------------------------
-- 7. A container from before schema 2 has no zone, and stays that way
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV
  Catch(W, { { CLAM, 1 } })
  local ch = F.Store.Char()
  ch.queue[1].zone = nil      -- as a lot saved before schema 2 reads
  W.map = DM
  W.Key("F"); W.Advance(3)
  local z = Zones(F)
  Check(F.API.Totals().containers[CLAM].opened == 1 and F.API.Totals().containers[CLAM].got[PEARL] == 1, "its contents are still recorded, as before")
  Check(z.containers[DM] == nil, "but not attributed to the zone it was opened in")
  Check(z.containers[SV].opened == nil or z.containers[SV][CLAM].opened == 0, "nor to a zone guessed from anything else")
end

---------------------------------------------------------------------------
-- 8. Migration from schema 1: nothing lost, nothing invented
---------------------------------------------------------------------------
do
  local KEYC = "Rich - Forever"
  local db = { schema = 1, config = { present = { mode = "compact" } }, client = {}, capability = {},
    chars = { [KEYC] = { nextSession = 3, nextLot = 2, zoneNames = { [1434] = "Stranglethorn Vale" },
      totals = { casts = 10, catches = 8, items = 9, failed = 1, interrupted = 0, missed = 1, sessions = 2, seconds = 900, line = 400, first = 1700000000, last = 1700001000,
        species = { [FISH1] = { q = 9, c = 8, f = 1700000000, l = 1700001000 } }, zones = { [1434] = { casts = 10, catches = 8, items = 9, line = 400 } },
        containers = { [CLAM] = { caught = 1, opened = 0, failed = 0, got = {} } }, contents = {} },
      sessions = { { id = 1, start = 1700000000, stop = 1700000900, seconds = 900, ended = "command", zone = 1434, casts = 10, catches = 8, items = 9,
        failed = 1, interrupted = 0, missed = 1, sessions = 0, line = 400, species = { [FISH1] = { q = 9, c = 8, f = 1, l = 2 } },
        zones = { [1434] = { casts = 10, catches = 8, items = 9, line = 400 } }, containers = {}, contents = {} } },
      queue = { { id = 1, item = CLAM, n = 1, sid = 1, t = 1700000500 } },
      gear = { state = "pending", snapshot = { slots = { [16] = { id = 6256 } }, at = 1700000100 } } } } }
  local before = FishRoundTrip(db)
  local c, W, F = Fresh({ db = db, epoch = 1800000000 })
  local ch = c.TwichUIFishingDB.chars[KEYC]
  Check(c.TwichUIFishingDB.schema == 2, "migrated to schema 2")
  Check(ch.totals.items == 9 and ch.totals.species[FISH1].q == 9 and ch.totals.zones[1434].items == 9 and ch.totals.casts == 10, "lifetime catches and zone totals are kept")
  Check(ch.sessions[1].id == 1 and ch.sessions[1].species[FISH1].q == 9 and ch.sessions[1].zones[1434].catches == 8, "existing sessions are kept")
  Check(ch.queue[1].item == CLAM and ch.queue[1].zone == nil, "the queued container is kept, with no zone invented")
  Check(ch.totals.containers[CLAM].caught == 1, "container records are kept")
  Check(ch.gear.state == "pending" and ch.gear.snapshot.slots[16].id == 6256, "equipment recovery information is kept")
  Check(c.TwichUIFishingDB.config.present.mode == "compact", "settings are kept")
  Check(next(ch.totals.spz) == nil and ch.sessions[1].spz == nil, "no species-by-zone history is invented for older catches")
  Check(type(ch.locSince) == "number" and ch.locSince >= 1800000000, "when location recording began is stamped")
  Check(F.API.Zones("lifetime").since == ch.locSince, "and available to the Journal")
  -- repeatable: loading the migrated file again changes nothing
  local once = FishRoundTrip(c.TwichUIFishingDB)
  local c2 = FishingClient({ db = FishRoundTrip(once), epoch = 1800005000 })
  c2.TwichUI.RunCommand("fish")
  local twice = FishRoundTrip(c2.TwichUIFishingDB)
  Check(twice.chars[KEYC].locSince == once.chars[KEYC].locSince and twice.chars[KEYC].totals.items == 9 and twice.schema == 2, "a second load changes nothing (locSince keeps its first value)")
  -- new catches after the migration have locations; the old ones remain the difference
  local live = FishRoundTrip(once)
  live.chars[KEYC].gear = { state = "none" }
  local c3, W3, F3 = Fresh({ db = live, epoch = 1800009000 })
  W3.map = 1434; Catch(W3, { { FISH1, 2 } })
  local z = F3.API.Zones("lifetime")
  Check(z.species[1434][FISH1].q == 2 and F3.API.Totals().species[FISH1].q == 11, "after migration: 2 with a location, 9 older (11 in all)")
  Check(F3.API.Totals().zones[1434].items == 11, "the zone's own totals still count all 11")
end

---------------------------------------------------------------------------
-- 9. Damaged new fields are repaired on their own
---------------------------------------------------------------------------
do
  local KEYC = "Rich - Forever"
  local db = { schema = 2, config = {}, client = {}, capability = {},
    chars = { [KEYC] = { nextSession = 1, nextLot = 1, locSince = "yesterday",
      totals = { casts = 1, catches = 1, items = 1, failed = 0, interrupted = 0, missed = 0, sessions = 1, seconds = 0, line = 0,
        species = {}, zones = {}, containers = {}, contents = {},
        spz = { [1434] = { [FISH1] = { q = 4, c = 2, f = "x", l = 5 }, [FISH2] = { q = "many", c = 1 }, bad = { q = 1, c = 1 } }, ["north"] = { [FISH1] = { q = 1, c = 1 } }, [15] = "nonsense" },
        ctz = { [1434] = { [CLAM] = { caught = 2, got = { [PEARL] = 1, [1] = "x" } } }, [20] = 5 } },
      sessions = {}, queue = { { id = 1, item = CLAM, n = 1, sid = 1, t = 1, zone = "far" } }, gear = { state = "none" }, learned = { enchants = {}, containers = {} } } } }
  local c = FishingClient({ db = db })
  c.TwichUI.RunCommand("fish")
  local F = c.TwichUI.Fishing
  local ch = c.TwichUIFishingDB.chars[KEYC]
  Check(ch.totals.spz[1434][FISH1].q == 4 and ch.totals.spz[1434][FISH1].f == nil and ch.totals.spz[1434][FISH1].l == 5, "a good entry is kept, its damaged time dropped")
  Check(ch.totals.spz[1434][FISH2] == nil and ch.totals.spz[1434].bad == nil and ch.totals.spz.north == nil and ch.totals.spz[15] == nil, "damaged entries are dropped")
  Check(ch.totals.spn == 1, "the entry count is rebuilt")
  Check(ch.totals.ctz[1434][CLAM].caught == 2 and ch.totals.ctz[1434][CLAM].opened == 0 and ch.totals.ctz[1434][CLAM].got[PEARL] == 1 and ch.totals.ctz[1434][CLAM].got[1] == nil and ch.totals.ctz[20] == nil, "container zone records are repaired in place")
  Check(ch.locSince == nil or type(ch.locSince) == "number", "a damaged locSince is not kept")
  Check(ch.queue[1].zone == nil, "a damaged lot zone reads as not known")
end

---------------------------------------------------------------------------
-- 10. Bounded: a zone-species entry per pair, never per catch
---------------------------------------------------------------------------
do
  local c, W, F = Fresh()
  W.map = SV
  for _ = 1, 40 do Catch(W, { { FISH1, 1 } }) end
  local t = F.Store.Char().totals
  Check(t.spn == 1 and t.spz[SV][FISH1].c == 40 and t.spz[SV][FISH1].q == 40, "forty catches of one species in one zone are one entry")
  F.LIMITS.zoneSpecies = 3
  for i = 1, 6 do W.map = 100 + i; Catch(W, { { FISH2, 1 } }) end
  Check(t.spn == 3, "the number of entries is capped (" .. tostring(t.spn) .. ")")
  Check(t.species[FISH2].q == 6 and t.items == 46, "a capped entry never loses the catch itself")
  F.LIMITS.zoneSpecies = 4000
  local n = 0
  for _, zt in pairs(t.spz) do for _ in pairs(zt) do n = n + 1 end end
  Check(n == t.spn, "the counter matches the entries")
end

if failures > 0 then error(failures .. " check(s) failed") end
print("PASSED test_fishing_zones")
