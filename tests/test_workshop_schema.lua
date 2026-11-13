-- Market data foundation 2.0, milestone A2 (docs/workshop/market-data-foundation-v2.md sections 3, 11, 12): the version-2 saved schema of the
-- Workshop's market database (TwichUIWorkshopDB v 2, markets f 3) and what protects existing player data:
--   * a version-1 database is read in place, never rewritten by loading or reading; the first ACCEPTED commit writes v 2 / f 3 atomically;
--   * the legacy minimum-buyout history is frozen (a scan only expires it), the 1.3 price entries keep their format and meaning;
--   * snapshot / scan log / day log / coverage boundary are written from what the scan pipeline really knows, bounded, validated on read;
--   * a rejected, dropped, cancelled or failing commit leaves the database deep-equal to what it was (no partial version bump, no orphans);
--   * a database newer than this version is held, and the RELEASED 1.3 code (tests/fixtures/workshop_v13, byte-for-byte from the v1.3.0 tag)
--     refuses every write to a version-2 database, before and after a save-and-reload round trip.
-- Synthetic: this proves our logic and the released code's behaviour offline; it proves nothing about the real client's saved-variables
-- loader or about /reload (docs/workshop/market-data-foundation-v2.md section 14 lists the real-client steps).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

---------------------------------------------------------------------------
-- A deterministic serializer (the test's stand-in for what the client writes to SavedVariables and reads back), deep copy and compare
---------------------------------------------------------------------------
local function Ser(v)
  local t = type(v)
  if t == "number" then return ("%.17g"):format(v) end
  if t == "string" then return ("%q"):format(v) end
  if t == "boolean" or t == "nil" then return tostring(v) end
  if t ~= "table" then error("cannot serialize a " .. t) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) < type(b) end
    return a < b
  end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = "[" .. Ser(k) .. "]=" .. Ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function Reload(text) return assert(loadstring("return " .. text))() end   -- test-only: the text is this file's own output
local function Clone(v) return Reload(Ser(v)) end

---------------------------------------------------------------------------
-- A client with the Workshop loaded: the current files, or the released 1.3 files; a fake auction house; a virtual clock
---------------------------------------------------------------------------
local NOW = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }
local V13 = { "Data.lua", "Materials.lua", "Queue.lua", "History.lua", "Prices.lua", "Scan.lua", "Market.lua" }

local function Setup(which, db)
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = c.TwichUIDB or {}
  local clock, timers = 0, {}
  c.GetTime = function() return clock end
  c.time = function() return 1000000 + math.floor(clock) end
  c.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end }
  local made = {}
  c.CreateFrame = function(kind) local fr = MIFake(kind); made[#made + 1] = fr; return fr end
  c.GetRealmName = function() return "Realm" end
  local ah = { ready = true, sent = 0, records = {}, side = "Alliance" }
  c.C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return ah.ready end,
    ReplicateItems = function() ah.sent = ah.sent + 1 end,
    GetNumReplicateItems = function() return #ah.records end,
    GetReplicateItemInfo = function(i)
      local r = ah.records[i + 1]
      if not r then return end
      return "n", 1, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, nil, nil, "o", "o", 0, r.item, r.hasAll ~= false
    end,
  }
  c.AuctionHouseFrame = MIFake("Frame")
  c.UnitFactionGroup = function() return ah.side end
  c.TwichUIWorkshopDB = db
  local files, dir = NOW, ROOT .. "../TwichUI_Workshop/"
  if which == "v13" then files, dir = V13, TESTS .. "fixtures/workshop_v13/" end
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(dir .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  local t = { c = c, ah = ah, W = c.TwichUI.Workshop }
  function t.Fire(event)
    for _, fr in ipairs(made) do
      if fr.events[event] and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, event) end
    end
  end
  function t.Advance(sec)
    local target = clock + sec
    while true do
      local best, bi
      for i, tm in ipairs(timers) do if tm.at <= target and (not best or tm.at < best.at) then best, bi = tm, i end end
      if not best then break end
      table.remove(timers, bi)
      if best.at > clock then clock = best.at end
      best.fn()
    end
    clock = target
  end
  function t.DB() return t.c.TwichUIWorkshopDB end
  return t
end

local D = 86400
local KEY = "Realm|Alliance"
local function Items(map)
  local o = {}
  for id, p in pairs(map) do o[id] = type(p) == "string" and p or ("%d,1,1,1,0"):format(p) end
  return o
end
local function ScanOf(at, map, extra)
  local n = 0
  for _ in pairs(map) do n = n + 1 end
  local sc = { realm = "Realm", side = "Alliance", at = at, complete = true, read = n, used = n, n = n, items = Items(map) }
  for k, v in pairs(extra or {}) do sc[k] = v end
  return sc
end
local function Commit(t, key, day, map, extra, secs) return t.W.Prices.Commit(key or KEY, ScanOf(day * D + (secs or 600), map, extra)) end

-- A version-1 database exactly as the RELEASED 1.3 code writes it: two scan days, so item 10 has a two-day legacy history
local function V1Database()
  local old = Setup("v13")
  Check(Commit(old, KEY, 100, { [10] = 500, [11] = 900 }))
  Check(Commit(old, KEY, 101, { [10] = 480, [11] = 950, [12] = 70 }))
  local db = old.DB()
  Same(db.v, 1, "1.3 writes version 1"); Same(db.markets[KEY].f, 2)
  return Clone(db)
end
local V1 = V1Database()

local function Stats(t, item, key, day) return t.W.Market.Stats(item, "week", { market = key or KEY, now = (day or 101) * D + 900 }) end
local function Series(t, item, key, day) return t.W.Market.Series(item, { market = key or KEY, now = (day or 101) * D + 900 }) end

---------------------------------------------------------------------------
-- 1. A version-1 database is read in place; loading and reading change nothing
---------------------------------------------------------------------------
do
  local t = Setup("now", Clone(V1))
  local PR, MK = t.W.Prices, t.W.Market
  local before = Ser(t.DB())
  Same(PR.Held(), false, "version 1 is this version's to write")
  local m = PR.Market(KEY)
  Same(m.format, 2, "a market of 1.3 is format 2"); Same(m.scope, "full"); Same(m.snap, nil); Same(m.v2from, nil)
  Same(PR.Lookup(m, 10).price, 480); Same(PR.Lookup(m, 12).price, 70)
  local info = MK.Info({ market = KEY, now = 101 * D + 900 })
  Same(info.format, 2); Same(info.dbVersion, 1); Same(info.v2from, nil); Same(info.scanLog, nil); Same(info.dayLog, nil); Same(info.compact, nil)
  Same(info.scans, 2, "the existing field keeps its meaning: the scan days of the legacy history")
  Same(MK.Price(11, { market = KEY, now = 101 * D + 900 }).price, 950)
  Check(Stats(t, 10).n == 2 and Stats(t, 10).low == 480 and Stats(t, 10).high == 500, "the legacy history reads as before")
  Same(#MK.Markets({ now = 101 * D + 900 }), 1)
  for _ = 1, 3 do Stats(t, 10); Series(t, 10); MK.Info({ market = KEY }); MK.Markets(); PR.Newest("Realm") end
  Same(Ser(t.DB()), before, "loading and reading never rewrite the saved data")
  Same(t.DB().v, 1); Same(t.DB().markets[KEY].f, 2)
end

---------------------------------------------------------------------------
-- 2. The first accepted commit writes version 2 / format 3, and only what the scan pipeline knows
---------------------------------------------------------------------------
local V2, V2Hist
do
  local t = Setup("now", Clone(V1))
  local PR, MK = t.W.Prices, t.W.Market
  local legacy = V1.markets[KEY]
  local statsBefore, seriesBefore = Ser(Stats(t, 10)), Ser(Series(t, 10))
  Check(Commit(t, KEY, 102, { [10] = 470, [12] = 300 }, { invalid = 1, noBuyout = 2, partial = 0, read = 5, used = 2 }, 700), "the first commit of the new code is accepted")
  local db = t.DB()
  Same(db.v, 2, "the database version is bumped by the accepted commit"); Same(PR.DbVersion(), 2)
  local m = db.markets[KEY]
  Same(m.f, 3); Same(m.scope, "full"); Same(m.realm, "Realm"); Same(m.side, "Alliance"); Same(m.at, 102 * D + 700); Same(m.complete, true)
  Same(m.read, 5); Same(m.used, 2); Same(m.partial, 0); Same(m.n, 2)
  Same(Ser(m.items), Ser(Items({ [10] = 470, [12] = 300 })), "items keep their format and meaning: the newest scan, p,q,l,t,x")
  Same(PR.Lookup(PR.Market(KEY), 10).price, 470); Same(MK.Price(11, { market = KEY, now = 102 * D + 900 }), nil, "item 11 was not in the newest scan")
  -- the legacy history is frozen: this scan added nothing to it
  Same(Ser(m.hist), Ser(legacy.hist), "legacy history identical"); Same(Ser(m.sd), Ser(legacy.sd), "scan days of the legacy history identical")
  Same(m.hn, legacy.hn, "items with legacy history unchanged")
  Same(Ser(Stats(t, 10)), statsBefore, "Stats unchanged"); Same(Ser(Series(t, 10)), seriesBefore, "Series unchanged")
  -- the snapshot: only facts the pipeline has; absent otherwise
  local s = m.snap
  Same(s.seq, 1); Same(s.kind, "full"); Same(s.at, 102 * D + 700); Same(s.records, 5); Same(s.used, 2); Same(s.invalid, 1); Same(s.noBuyout, 2)
  Same(s.partial, 0); Same(s.items, 2); Same(s.auto, false); Same(s.alg, nil, "no distribution algorithm yet: nothing to name"); Same(s.client, "1.60.1.70009", "the build string the client reports (the mock's)")
  Same(#m.scans, 1); Same(m.scans[1], ("1,%d,%d,2,5"):format(102 * D + 700, 1 + 2 + 64), "seq,at,flags(whole+complete+recorded into history, A4),items,records")
  Same(#m.days, 1); Same(m.days[1], "102,1,9", "day,scans,flags(whole read + recorded into history, A4)")
  Same(m.v2from, 102, "version-2 coverage begins on the first accepted scan's day")
  Same(m.dist, nil); Same(m.compact, nil); Same(m.ring, nil, "containers no milestone writes are not created")
  -- (A4) the version-2 history of the two listed items: one ring point and one daily point each, r unknown (no distribution in this scan)
  local minute = math.floor((102 * D + 700) / 60)
  Same(m.h2[10], ("%d,0,470,,1,1|102:102,470,,1,1"):format(minute)); Same(m.h2[12], ("%d,0,300,,1,1|102:102,300,,1,1"):format(minute))
  Same(m.h2[11], nil, "no history for an item this scan did not list"); Same(next(m.c2), nil, "no buckets yet")
  Same(m.h2info.v, 1); Same(m.h2info.from, 102); Same(m.h2info.at, 102 * D + 700); Same(m.h2info.items, 2); Same(m.h2info.citems, 0)
  Same(m.h2info.bytes, #m.h2[10] + #m.h2[12])
  -- the other 1.3 market fields still carry the meaning they had
  for _, k in ipairs({ "f", "scope", "realm", "side", "at", "complete", "read", "used", "partial", "n", "hn", "sd", "items", "hist" }) do
    Check(m[k] ~= nil, "legacy field " .. k .. " is kept in a format 3 market")
  end
  local info = MK.Info({ market = KEY, now = 102 * D + 900 })
  Same(info.format, 3); Same(info.dbVersion, 2); Same(info.v2from, 102); Same(info.scanLog, 1); Same(info.dayLog, 1); Same(info.compact, nil)
  Same(info.scans, 2, "'scans' still counts the legacy history's scan days")
  V2, V2Hist = Clone(db), Clone(m.hist)
  -- reading the new database changes nothing
  local snapshot = Ser(db)
  for _ = 1, 3 do Stats(t, 10); MK.Info({ market = KEY }); MK.Markets(); PR.Market(KEY) end
  Same(Ser(db), snapshot, "repeated reads do not mutate")
end

---------------------------------------------------------------------------
-- 3. Repeated commits, flags, the logs and their bounds
---------------------------------------------------------------------------
do
  local t = Setup("now", Clone(V1))
  local PR = t.W.Prices
  Check(Commit(t, KEY, 102, { [10] = 470 }, nil, 100))
  Check(Commit(t, KEY, 102, { [10] = 460 }, nil, 200))
  Check(Commit(t, KEY, 103, { [10] = 450 }, nil, 300))
  local m = t.DB().markets[KEY]
  Same(m.snap.seq, 3); Same(#m.scans, 3); Same(m.v2from, 102, "the coverage boundary never moves")
  Same(m.days[1], "102,2,9", "two scans on one day are one entry with a count (9: whole read, recorded into history)"); Same(m.days[2], "103,1,9")
  Same(Ser(m.hist), Ser(V1.markets[KEY].hist), "history is untouched by repeated commits")
  Same(PR.Lookup(PR.Market(KEY), 10).price, 450)

  -- flags: cut, changed, partial, automatic; an incomplete scan may replace an incomplete one but never a complete one
  local B = "Realm|Horde"
  Check(Commit(t, B, 110, { [1] = 5 }, { complete = false, cut = true }, 10))
  Check(Commit(t, B, 110, { [1] = 5 }, { complete = false, cut = true, changed = true }, 20))
  Check(Commit(t, B, 110, { [1] = 5 }, { complete = false, partial = 3 }, 30))
  Check(Commit(t, B, 111, { [1] = 5 }, { auto = true }, 40))
  local b = t.DB().markets[B]
  Same(b.scans[1], ("1,%d,4,1,1"):format(110 * D + 10), "cut: not whole, not complete")
  Same(b.scans[2], ("2,%d,12,1,1"):format(110 * D + 20), "cut and count changed")
  Same(b.scans[3], ("3,%d,81,1,1"):format(110 * D + 30), "whole read (1) with partial information (16) but not complete, recorded into history (64)")
  Same(b.scans[4], ("4,%d,99,1,1"):format(111 * D + 40), "whole, complete, automatic, recorded")
  Same(b.days[1], "110,3,15", "any whole read, any incomplete scan, any partial information, any scan recorded"); Same(b.days[2], "111,1,9")
  Same(b.snap.auto, true); Same(b.cut, nil, "the newest scan was whole")
  local ok, why = Commit(t, B, 112, { [1] = 5 }, { complete = false, cut = true })
  Same(ok, false); Same(why, "kept", "a complete scan is never replaced by an incomplete one")
  Same(#t.DB().markets[B].scans, 4, "a refused scan is not logged")

  -- bounds: the newest 256 at most
  local C = "Realm|Neutral"
  for i = 1, 300 do Check(Commit(t, C, 120, { [1] = 5 }, nil, i)) end
  local c = t.DB().markets[C]
  Same(#c.scans, 256, "at most 256 scans"); Same(c.scans[1]:match("^(%d+),"), "45"); Same(c.scans[256]:match("^(%d+),"), "300"); Same(c.snap.seq, 300)
  Same(c.days[1], "120,300,9", "the day log keeps counting")
  -- every scan of the last 48 hours: 70 scans ten minutes apart (under 12 hours) are all kept
  local E = "Realm|E"
  for i = 1, 70 do Check(Commit(t, E, 130, { [1] = 5 }, nil, i * 600)) end
  Same(#t.DB().markets[E].scans, 70, "all scans of the last 48 h are kept (more than 64)")
  -- at least the newest 64, even when they are old: 100 scans a day apart keep 64
  local F = "Realm|F"
  for i = 1, 100 do Check(Commit(t, F, 200 + i, { [1] = 5 }, nil, 5)) end
  Same(#t.DB().markets[F].scans, 64, "at least 64 scans are kept although they are older than 48 h")
  Same(#t.DB().markets[F].days, 100)
  -- and only 120 days of day log
  local G = "Realm|G"
  for i = 1, 130 do Check(Commit(t, G, 300 + i, { [1] = 5 }, nil, 5)) end
  local g = t.DB().markets[G]
  Same(#g.days, 120, "120 scan days at most"); Same(g.days[1], "311,1,9"); Same(g.days[120], "430,1,9")
  -- a scan dated before the newest logged day (the clock went back) is logged as a scan but opens no earlier day
  Check(Commit(t, G, 350, { [1] = 5 }, nil, 6))
  g = t.DB().markets[G]
  Same(#g.days, 120); Same(g.days[120], "430,1,9"); Same(g.snap.seq, 131)
  Same(g.scans[#g.scans]:match(",(%d+),%d+,%d+$"), "3", "(A4) a scan dated before the newest recorded one is not recorded into the history")
  Same(g.v2from, 301, "coverage began with the first scan")
end

---------------------------------------------------------------------------
-- 4. The legacy history is frozen, and still expires
---------------------------------------------------------------------------
do
  local t = Setup("now", Clone(V1))
  local PR, H = t.W.Prices, t.W.History
  Same(PR.FEED_LEGACY_HISTORY, false, "production never feeds the legacy history")
  for d = 102, 108 do Check(Commit(t, KEY, d, { [10] = 400 + d, [13] = 50 }, nil, 60)) end
  local m = t.DB().markets[KEY]
  Same(Ser(m.hist), Ser(V1.markets[KEY].hist), "seven more scans add nothing to the legacy history")
  Same(m.hist[13], nil, "an item first seen by a format 3 scan has no legacy history")
  Same(Ser(m.sd), Ser(V1.markets[KEY].sd))
  -- expiry still applies (what Trim says is too old goes, an item with nothing left is dropped)
  local d = 101 + H.RETAIN_DAYS + 5
  Check(Commit(t, KEY, d, { [10] = 400 }, nil, 60))
  m = t.DB().markets[KEY]
  local want, gone = {}, 0
  for id, s in pairs(V1.markets[KEY].hist) do
    local trimmed = H.Trim(s, d)
    if trimmed == nil then gone = gone + 1 else want[id] = trimmed end
  end
  Same(Ser(m.hist), Ser(want), "legacy history trimmed by expiry exactly as History.Trim says")
  Check(gone > 0, "this fixture does expire something")
  Same(m.hn, V1.markets[KEY].hn - gone, "hn follows the expiry")
end

---------------------------------------------------------------------------
-- 5. Reading every combination of formats; malformed optional fields never touch the price entries
---------------------------------------------------------------------------
do
  -- mixed: a 1.3 market (f 2) and a format 3 market in one version-2 database
  local mixed = Clone(V2)
  mixed.markets["Realm|Horde"] = Clone(V1.markets[KEY])
  mixed.markets["Realm|Horde"].side = "Horde"
  local t = Setup("now", mixed)
  local PR, MK = t.W.Prices, t.W.Market
  Same(PR.Market("Realm|Horde").format, 2); Same(PR.Market(KEY).format, 3)
  local list = MK.Markets({ now = 102 * D + 900 })
  Same(#list, 2); Same(list[1].key, KEY); Same(list[1].format, 3); Same(list[2].format, 2)
  Same(PR.Lookup(PR.Market("Realm|Horde"), 10).price, 480); Same(PR.Lookup(PR.Market(KEY), 10).price, 470)
  Same(Stats(t, 10, "Realm|Horde").n, 2, "legacy history of the old-format market reads")
  -- a commit on one market leaves the other deep-equal (isolation)
  local hordeBefore = Ser(t.DB().markets["Realm|Horde"])
  Check(Commit(t, KEY, 104, { [10] = 460 }, nil, 5))
  Same(Ser(t.DB().markets["Realm|Horde"]), hordeBefore, "another market is untouched")
  Same(t.DB().markets[KEY].snap.seq, 2)
  -- converting the old-format market keeps its history and prices of the legacy fields, and starts coverage today
  Check(Commit(t, "Realm|Horde", 105, { [10] = 450 }, { side = "Horde" }, 5))
  local h = t.DB().markets["Realm|Horde"]
  Same(h.f, 3); Same(h.v2from, 105); Same(h.snap.seq, 1); Same(Ser(h.hist), Ser(V1.markets[KEY].hist))

  -- malformed optional fields: the entries still read, the logs count only valid entries, the next commit drops what is junk
  local junk = Clone(V2)
  local m = junk.markets[KEY]
  m.snap = { seq = "x", kind = 7 }
  m.scans = { "garbage", 5, "1,2", ("3,%d,3,2,5"):format(102 * D + 1), "4,-1,3,2,5", "5,1e9,3,2,5", "6,0,0,0,0", "7,1000,256,1,1", ("8,%d,3,2,5"):format(102 * D + 2) }
  m.days = { "102,x,1", "nope", "103,2,3", "104,2,9", "105,0,1", "106,1,7" }
  m.v2from = "never"; m.compact = { level = "x" }
  m.dist = "junk"; m.h2 = 5; m.c2 = { ["10"] = "kept as it is" }
  local t2 = Setup("now", junk)
  local PR2, MK2 = t2.W.Prices, t2.W.Market
  Same(PR2.Lookup(PR2.Market(KEY), 10).price, 470, "price entries read although the optional fields are junk")
  local info = MK2.Info({ market = KEY, now = 103 * D })
  Same(info.format, 3); Same(info.v2from, nil); Same(info.compact, nil); Same(PR2.Market(KEY).snap, nil)
  Same(info.scanLog, 2, "only the two well-formed scan entries count"); Same(info.dayLog, 3, "103,2,3, 104,2,9 (A4: flag 8, recorded into history) and 106,1,7")
  Check(t2.W.Prices.ScanLog(PR2.Market(KEY))[1].seq == 3, "a valid entry decodes")
  local junkBefore = Ser(t2.DB())
  MK2.Info(); MK2.Markets()
  Same(Ser(t2.DB()), junkBefore, "reading junk does not repair it")
  Check(Commit(t2, KEY, 107, { [10] = 440 }, nil, 9))
  local n = t2.DB().markets[KEY]
  Same(n.snap.seq, 9, "numbered after the highest valid entry"); Same(#n.scans, 3, "the two valid entries (seq 3 and 8) plus the new one; flags 256 and a zero time are out of range")
  for _, e in ipairs(n.scans) do Check(e:match("^%d+,%d+,%d+,%d+,%d+$"), "only well-formed entries are written") end
  Same(n.days[1], "103,2,3"); Same(n.days[#n.days], "107,1,9")
  Same(n.v2from, 107, "no valid boundary: it starts at this scan's day")
  Same(n.dist, nil, "a container that is not a table is not carried")
  -- (A4) this commit recorded history: the scan's item has its first point, and an entry whose key is not an item id cannot be this
  -- format's and is not carried (a commit that records nothing carries a table container forward untouched: section 5b)
  Check(type(n.h2[10]) == "string" and n.h2[10]:find("|107:", 1, true), "the listed item's history starts"); Same(n.c2["10"], nil)
end

---------------------------------------------------------------------------
-- 6. Eviction and isolation across markets
---------------------------------------------------------------------------
do
  local t = Setup("now", Clone(V1))
  Check(Commit(t, "Realm|A", 100, { [1] = 5 }, nil, 1))
  Check(Commit(t, "Realm|B", 101, { [1] = 5 }, nil, 1))
  local before = {}
  for k, m in pairs(t.DB().markets) do before[k] = Ser(m) end
  Same(t.DB().markets[KEY].f, 2, "the 1.3 market is untouched so far")
  -- the database now holds Alliance (f 2, day 101), A, B: a fourth key evicts the one scanned longest ago (A)
  Check(Commit(t, "Realm|C", 120, { [1] = 5 }, nil, 1))
  local keys = {}
  for k in pairs(t.DB().markets) do keys[#keys + 1] = k end
  table.sort(keys)
  Same(table.concat(keys, ","), "Realm|Alliance,Realm|B,Realm|C", "the market scanned longest ago went")
  Same(Ser(t.DB().markets[KEY]), before[KEY], "the 1.3 market is byte-for-byte what it was")
  Same(Ser(t.DB().markets["Realm|B"]), before["Realm|B"])
  Same(t.DB().v, 2)
end

---------------------------------------------------------------------------
-- 7. Held: a newer database is never written
---------------------------------------------------------------------------
do
  local newer = Clone(V2)
  newer.v = 3
  newer.markets[KEY].zzz = { future = "data" }
  local t = Setup("now", newer)
  local PR, SC = t.W.Prices, t.W.Scan
  local before = Ser(t.DB())
  Same(PR.Held(), true)
  local ok, why = Commit(t, KEY, 105, { [10] = 1 }); Same(ok, false); Same(why, "held")
  ok, why = PR.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1 })); Same(ok, false); Same(why, "held")
  ok, why = Commit(t, "Realm|New", 105, { [10] = 1 }); Same(ok, false); Same(why, "held")
  t.ah.records = { { item = 10, count = 1, buyout = 100 } }
  ok, why = SC.Start(); Same(ok, false); Same(why, "held")
  Same(Ser(t.DB()), before, "a newer database is not changed")
  Same(PR.Lookup(PR.Market(KEY), 10).price, 470, "but it is still read")
  -- a job begun before the database changed under it is refused at Apply
  local t2 = Setup("now", Clone(V1))
  local job = t2.W.Prices.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1 }))
  Check(job); while not job:Step(1) do end
  t2.c.TwichUIWorkshopDB.v = 3
  local snap = Ser(t2.DB())
  local applied, awhy = job:Apply(); Same(applied, false); Same(awhy, "held"); Same(Ser(t2.DB()), snap)
end

---------------------------------------------------------------------------
-- 8. Atomicity: rejected, dropped, cancelled and failing commits leave the database deep-equal
---------------------------------------------------------------------------
do
  local function Unchanged(t, before, what) Same(Ser(t.DB()), before, what .. ": the saved database is exactly as it was") end
  local function NoOrphans(db, what)
    Same(db.v, 1, what .. ": no partial version bump")
    for k, m in pairs(db.markets) do
      Same(m.f, 2, what .. ": market " .. k); Same(m.snap, nil); Same(m.scans, nil); Same(m.days, nil); Same(m.v2from, nil); Same(m.dist, nil)
    end
  end

  -- a refused scan (an incomplete one over a complete one) and a scan that is not a scan
  local t = Setup("now", Clone(V1))
  local before = Ser(t.DB())
  local ok, why = Commit(t, KEY, 105, { [10] = 1 }, { complete = false }); Same(ok, false); Same(why, "kept")
  Unchanged(t, before, "kept")
  ok, why = t.W.Prices.BeginCommit(KEY, { at = 5 }); Same(ok, false); Same(why, "bad"); Unchanged(t, before, "bad")
  ok, why = t.W.Prices.BeginCommit(KEY, ScanOf("x", { [10] = 1 })); Same(ok, false); Same(why, "bad"); Unchanged(t, before, "bad time")

  -- a job dropped after some steps, and one finished but never applied (the scan never reached Apply)
  local job = t.W.Prices.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1, [11] = 2 }))
  Check(job); job:Step(1)
  Unchanged(t, before, "dropped job"); NoOrphans(t.DB(), "dropped job")
  job = t.W.Prices.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1, [11] = 2 }))
  while not job:Step(1) do end
  Unchanged(t, before, "job ready but not applied"); NoOrphans(t.DB(), "job ready but not applied")

  -- a failing commit step
  local H = t.W.History
  local trim = H.Trim
  H.Trim = function() error("step failed") end
  job = t.W.Prices.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1 }))
  Check(not pcall(function() while not job:Step(1) do end end), "the step fails (A4: the legacy expiry runs after the history phases)")
  H.Trim = trim
  Unchanged(t, before, "failing step"); NoOrphans(t.DB(), "failing step")

  -- a failure while the metadata is built (inside Apply, before anything is written)
  job = t.W.Prices.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1 }))
  while not job:Step(1) do end
  local format = string.format
  string.format = function() error("metadata failed") end
  local good = pcall(job.Apply, job)
  string.format = format
  Check(not good, "building the metadata fails")
  Unchanged(t, before, "failing metadata"); NoOrphans(t.DB(), "failing metadata")
  -- and the same job could not leave a half-written format 3 market behind on a database that is already version 2
  local t3 = Setup("now", Clone(V2))
  local before3 = Ser(t3.DB())
  job = t3.W.Prices.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1 }))
  while not job:Step(1) do end
  local day = t3.W.History.Day
  t3.W.History.Day = function() error("day log failed") end
  good = pcall(job.Apply, job)
  t3.W.History.Day = day
  Check(not good); Same(Ser(t3.DB()), before3, "failing day log on a version 2 database")

  -- a scan cancelled by closing the auction house, and a scan whose save step fails: through the real scan lifecycle
  local t4 = Setup("now", Clone(V1))
  local before4 = Ser(t4.DB())
  t4.ah.records = { { item = 10, count = 1, buyout = 100 }, { item = 11, count = 2, buyout = 300 } }
  Check(t4.W.Scan.Start()); t4.Advance(1); t4.Fire("AUCTION_HOUSE_CLOSED")
  Same(t4.W.Scan.state, "interrupted"); Unchanged(t4, before4, "cancelled scan"); NoOrphans(t4.DB(), "cancelled scan")
  local t5 = Setup("now", Clone(V1))
  local before5 = Ser(t5.DB())
  t5.ah.records = { { item = 10, count = 1, buyout = 100 } }
  local trim5 = t5.W.History.Trim
  t5.W.History.Trim = function() error("step failed") end
  Check(t5.W.Scan.Start()); t5.Fire("REPLICATE_ITEM_LIST_UPDATE"); t5.Advance(120)
  t5.W.History.Trim = trim5
  Same(t5.W.Scan.state, "failed"); Same(t5.W.Scan.why, "unsaved"); Unchanged(t5, before5, "failing save step"); NoOrphans(t5.DB(), "failing save step")
  -- and then a good scan on the same database upgrades it, with the scan's own numbers
  t5.ah.records = { { item = 10, count = 1, buyout = 100 }, { item = 10, count = 1, buyout = 0 }, { item = "x", count = 1, buyout = 5 }, { item = 11, count = 2, buyout = 300 } }
  Check(t5.W.Scan.Start()); t5.Fire("REPLICATE_ITEM_LIST_UPDATE"); t5.Advance(120)
  Same(t5.W.Scan.state, "done")
  local m = t5.DB().markets[KEY]
  Same(t5.DB().v, 2); Same(m.f, 3); Same(m.snap.records, 4); Same(m.snap.used, 2); Same(m.snap.invalid, 1); Same(m.snap.noBuyout, 1); Same(m.snap.items, 2)
  Same(m.snap.partial, 0); Same(m.snap.auto, false)
end

---------------------------------------------------------------------------
-- 9. The released 1.3 code against a version-2 database (the five-step old-client protection test)
---------------------------------------------------------------------------
-- A complete version-2 shape, populated by hand with synthetic strings for everything later milestones will write, in two format 3
-- markets and one 1.3 market, so a single dropped field anywhere shows up as a difference.
local Seeded
do
  local db = Clone(V2)
  local m = db.markets[KEY]
  m.dist = { [10] = "1,470,470,470,470,480,520,2|470:1:1;480:2:1:2;520:1:1|0:0", [12] = "1,300,300,300,300,300,300,1|300:1:1|0:0" }
  m.h2 = { [10] = "2880000,5,470,0,3,1;120,0,480,10,2,1!|102:100,470,10,3,1,2,0,5,10,0,1;1,465,12,2,1" }
  m.c2 = { [10] = "14,14,5,400,10,20,450,5,5,3,1,1,2;15,7,4,380,20,30,440,6,6,2,1,1,3" }
  m.compact = { level = 2, at = 102 * D, items = 40 }
  -- (A4) these strings are a LATER build's history format (h2info.v = 2): this build reads none of them and carries them forward untouched
  m.h2info = { v = 2, from = 102, at = 102 * D + 800, bytes = 300, items = 1, citems = 1 }
  m.scans[#m.scans + 1] = ("2,%d,35,2,2"):format(102 * D + 800)
  m.days[#m.days + 1] = "103,4,3"
  m.snap.alg = 1
  local other = Clone(m)
  other.side = "Horde"; other.realm = "Realm"
  other.snap.seq = 9; other.v2from = 90
  db.markets["Realm|Horde"] = other
  local legacy = Clone(V1.markets[KEY])
  legacy.side = "Neutral"
  db.markets["Realm|Neutral"] = legacy
  Check(db.v == 2 and db.markets[KEY].f == 3 and legacy.f == 2)
  Seeded = db
end

local function Answers(t, key)
  local PR, MK = t.W.Prices, t.W.Market
  return Ser({ stats = MK.Stats(10, "week", { market = key, now = 102 * D + 900 }), series = MK.Series(10, { market = key, now = 102 * D + 900 }),
    price = MK.Price(10, { market = key, now = 102 * D + 900 }), lookup = PR.Lookup(PR.Market(key), 12) })
end

-- every write path the released 1.3 code has: each must be refused, and a refusal leaves the table alone
local function Attempts(t13, label)
  local PR, SC = t13.W.Prices, t13.W.Scan
  Same(PR.Held(), true, label .. ": 1.3 holds a database newer than its own")
  local ok, why = PR.Commit(KEY, ScanOf(105 * D, { [10] = 1 })); Same(ok, false, label .. " Commit"); Same(why, "held", label .. " Commit")
  ok, why = PR.Commit("Realm|Brand new", ScanOf(105 * D, { [10] = 1 })); Same(ok, false); Same(why, "held", label .. " Commit of a new market")
  ok, why = PR.Commit(KEY, ScanOf(105 * D, { [10] = 1 }, { complete = false })); Same(ok, false, label .. " Commit incomplete")
  ok, why = PR.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1 })); Same(ok, false); Same(why, "held", label .. " BeginCommit")
  t13.ah.records = { { item = 10, count = 1, buyout = 100 } }
  ok, why = SC.Start(); Same(ok, false, label .. " Scan.Start"); Same(why, "held", label .. " Scan.Start")
  Same(t13.ah.sent, 0, label .. ": nothing was even requested from the auction house")
end

do
  -- 1.3 reads what it understands, with the same answers it gave before the upgrade
  local t13 = Setup("v13", Clone(Seeded))
  local before = Ser(t13.DB())
  local pr = t13.W.Prices
  Same(pr.Lookup(pr.Market(KEY), 10).price, 470, "1.3 reads the format 3 market's price entries")
  Same(pr.Lookup(pr.Market("Realm|Horde"), 12).price, 300)
  Same(t13.W.Market.Stats(10, "week", { market = KEY, now = 101 * D + 900 }).n, Setup("v13", Clone(V1)).W.Market.Stats(10, "week", { market = KEY, now = 101 * D + 900 }).n)
  Same(Ser(t13.W.Market.Series(10, { market = KEY, now = 101 * D + 900 })), Ser(Setup("v13", Clone(V1)).W.Market.Series(10, { market = KEY, now = 101 * D + 900 })),
    "the legacy days read as they did before the upgrade")
  Same(Ser(t13.W.Market.Stats(10, "week", { market = KEY, now = 101 * D + 900 })), Ser(Setup("v13", Clone(V1)).W.Market.Stats(10, "week", { market = KEY, now = 101 * D + 900 })))
  Attempts(t13, "1.3")
  Same(Ser(t13.DB()), before, "1.3 changed nothing: dist, h2, c2, compact, snapshot, scan log and day log are all still there")
  Check(t13.DB().markets[KEY].dist and t13.DB().markets[KEY].h2 and t13.DB().markets[KEY].c2 and t13.DB().markets[KEY].scans and t13.DB().markets["Realm|Horde"].compact)

  -- a 1.3 job begun while the database was still version 1 meets the new database at Apply
  local early = Setup("v13", Clone(V1))
  local job = early.W.Prices.BeginCommit(KEY, ScanOf(105 * D, { [10] = 1 }))
  Check(job); while not job:Step(1) do end
  early.c.TwichUIWorkshopDB = Clone(Seeded)
  local snap = Ser(early.DB())
  local ok, why = job:Apply(); Same(ok, false); Same(why, "held", "1.3 Apply"); Same(Ser(early.DB()), snap, "1.3 Apply wrote nothing")

  -- save and reload: the text a client would write at logout, read by a fresh 1.3 and by the current code
  local text = Ser(Seeded)
  local reloaded = Setup("v13", Reload(text))
  Attempts(reloaded, "1.3 after reload")
  Same(Ser(reloaded.DB()), text, "after a save-and-reload round trip the database is the same")
  Same(Answers(reloaded, KEY), Answers(Setup("v13", Clone(Seeded)), KEY))
  local now = Setup("now", Reload(text))
  local roundTrip = Ser(now.DB())
  now.W.Market.Info(); now.W.Market.Markets(); Stats(now, 10)
  Same(roundTrip, text, "the current code reads the reloaded database without rewriting it")

  -- the current code carries later milestones' containers forward through a commit instead of dropping them
  Check(Commit(now, KEY, 106, { [10] = 440, [14] = 77 }, nil, 3))
  local m = now.DB().markets[KEY]
  -- A3: dist describes ONE scan, so it is not carried (an old scan's would describe listings that are gone); the later containers still are
  Same(m.dist, nil, "dist is replaced by the scan's own (this scan had none): not carried"); Same(m.snap.alg, nil)
  Same(Ser(m.h2), Ser(Seeded.markets[KEY].h2), "h2 carried")
  Same(Ser(m.c2), Ser(Seeded.markets[KEY].c2), "c2 carried"); Same(Ser(m.compact), Ser(Seeded.markets[KEY].compact), "compact carried")
  Same(Ser(m.h2info), Ser(Seeded.markets[KEY].h2info), "(A4) the later format's record carried: nothing was recorded into a history this build cannot read")
  Same(m.scans[#m.scans]:match("^%d+,%d+,(%d+),"), "3", "and the scan log says this scan was not recorded (no flag 64)")
  Same(m.snap.seq, 3, "numbered after the logged scans"); Same(#m.scans, 3); Same(m.v2from, 102)
  Same(Ser(now.DB().markets["Realm|Horde"]), Ser(Seeded.markets["Realm|Horde"]), "another market untouched")
  Same(Ser(now.DB().markets["Realm|Neutral"]), Ser(Seeded.markets["Realm|Neutral"]))
  -- and 1.3 holds that one too
  Attempts(Setup("v13", Reload(Ser(now.DB()))), "1.3 after the new code's commit")
end

---------------------------------------------------------------------------
-- 10. Scope guards: the public Market API grew only by A4's History (read-only); only Prices.lua writes the market database
---------------------------------------------------------------------------
do
  local t = Setup("now", Clone(V1))
  local names = {}
  for k, v in pairs(t.W.Market) do if type(v) == "function" then names[#names + 1] = k end end
  table.sort(names)
  Same(table.concat(names, ","), "AgeShort,Compare,Freshness,History,Info,Markets,Observed,Price,Quote,Series,Source,Stats,Status,Trend", "")
end

do
  -- only Prices.lua may name the market database (the old-client argument rests on every writer sitting behind its held check); a new
  -- file that touches it must be added to this list on purpose, with a held check of its own
  local toc = assert(io.open(ROOT .. "../TwichUI_Workshop/TwichUI_Workshop.toc")):read("*a")
  local names = {}
  for file in toc:gmatch("\n([%w_]+%.lua)") do
    local src = assert(io.open(ROOT .. "../TwichUI_Workshop/" .. file)):read("*a")
    if src:find("TwichUIWorkshopDB", 1, true) then names[#names + 1] = file end
  end
  Same(table.concat(names, ","), "Prices.lua", "the files of the Workshop that name TwichUIWorkshopDB")
end

print("PASSED test_workshop_schema")
