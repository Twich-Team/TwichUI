-- The Workshop's market data foundation (TwichUI_Workshop/History.lua, Prices.lua commit, Market.lua, Scan.lua saving):
-- the price history of one item (first observation, same-day scans, missing days, buckets, retention, malformed strings), the stepped commit
-- (nothing is written before the last step, a dropped or failing job changes nothing, items a scan did not list keep their history, cut scans
-- never feed it), legacy recipe-only prices (read, classified "recipes", replaced by the first full scan), the API (current price and its notes,
-- quote, statistics, trend, comparison, markets, reasons, invalid arguments, read-only, consistency with the views) and full scans against a FAKE
-- auction house (no professions, loot items, more than 2000 distinct items, stacks, stale callbacks, a failing save).
-- Synthetic: this proves our logic, not what the real auction house returns (docs/workshop.md lists the live-client checks).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Prices.lua", "Opportunities.lua",
    "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }
local D = 86400

-- a stable text of any saved data, to prove nothing changed
local function Ser(v)
    if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local function Setup()
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = c.TwichUIDB or {}
  local clock, timers, base = 0, {}, 100 * D + 43200   -- day 100, midday
  c.GetTime = function() return clock end
  c.time = function() return base + math.floor(clock) end
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
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  c.TwichUI.Workshop.Prices.FEED_LEGACY_HISTORY = true   -- these tests exercise the 1.3 history feed; production keeps it frozen (test_workshop_schema.lua)
  local t = { c = c, ah = ah, W = c.TwichUI.Workshop }
  function t.Fire(event)
    for _, fr in ipairs(made) do if fr.events[event] and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, event) end end
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
  function t.Tick()
    local best, bi
    for i, tm in ipairs(timers) do if not best or tm.at < best.at then best, bi = tm, i end end
    if not best then return false end
    table.remove(timers, bi)
    if best.at > clock then clock = best.at end
    best.fn()
    return true
  end
  function t.Listening() local n = 0 for _, fr in ipairs(made) do for _ in pairs(fr.events) do n = n + 1 end end return n end
  function t.SetDay(day) base = day * D + 43200 - math.floor(clock) end
  function t.Pending() return #timers end
  return t
end

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

---------------------------------------------------------------------------
-- History strings
---------------------------------------------------------------------------
do
  local t = Setup()
  local H = t.W.History
  Same(H.Day(5 * D + 3), 5); Same(H.Day(-1), nil); Same(H.Day("x"), nil); Same(H.Day(0), nil, "day 0 is not a day"); Same(H.Day(0 / 0), nil)
  -- a first observation, a second scan on the same day (the later one wins), a later day
  local s = H.Add(nil, 100, 5000)
  Same(s, "100,5000|", "the first observation: one exact day, nothing older")
  Same(H.Add(s, 100, 4000), "100,4000|", "a second scan the same day replaces that day's value")
  s = H.Add(H.Add(s, 100, 4000), 103, 6000)
  Same(s, "100,4000;103,6000|", "days with no scan (101, 102) have no value and never get one")
  local x, why = H.Add(s, 99, 1); Same(x, nil); Same(why, "stale", "an observation older than the newest kept is ignored, never reordered")
  for _, bad in ipairs({ { 0, 5 }, { 100, 0 }, { 100, 1.5 }, { 100, -1 }, { 100, 100000000000 }, { "x", 5 }, { 100, "5" }, { 300000, 5 }, { 0 / 0, 5 }, { 100, 0 / 0 } }) do
    local r, w = H.Add(nil, bad[1], bad[2]); Same(r, nil, tostring(bad[1]) .. "," .. tostring(bad[2])); Same(w, "bad")
  end
  -- seven days stay exact; the eighth folds the oldest into its 28-day bucket (days 84..111 are bucket 3)
  s = nil
  for d = 100, 107 do s = H.Add(s, d, 1000 + d) end
  Same(s, "101,1101;102,1102;103,1103;104,1104;105,1105;106,1106;107,1107|3,1100,1100,1100,1", s)
  s = H.Add(s, 108, 1108)
  Same(s, "102,1102;103,1103;104,1104;105,1105;106,1106;107,1107;108,1108|3,1100,1101,2201,2", "the bucket keeps low, high, the sum and the number of days")
  -- a long run: bounded buckets and retention
  s = nil
  for d = 1, 400 do s = H.Add(s, d, d) end
  Same(s, "394,394;395,395;396,396;397,397;398,398;399,399;400,400|12,336,363,9786,28;13,364,391,10570,28;14,392,393,785,2", s)
  local pts, bks = H.Decode(s)
  Same(#pts, 14); Same(#bks, 15, "three buckets, no more")
  Check(#s < 200, "a year of daily scans of one item is still a short string: " .. #s)
  -- queries over the string
  local w = H.Window(s, 394, 400)
  Same(w.n, 7); Same(w.lo, 394); Same(w.hi, 400); Same(w.sum, 2779); Check(w.exact); Same(w.first, 394); Same(w.last, 400)
  w = H.Window(s, 364, 400)
  Same(w.n, 35, "7 exact days plus the bucket that lies entirely inside"); Check(not w.exact); Same(w.skipped, 2, "the bucket that overhangs the window is not counted, and says so")
  Same(w.lo, 364); Same(w.hi, 400)
  Same(H.Window(s, 1, 100), nil, "nothing that old is kept")
  Same(H.Window(s, 401, 500), nil, "nothing in the future")
  local nd, np = H.Newest(s); Same(nd, 400); Same(np, 400)
  -- expiry by age: an item not seen for longer than the retention is trimmed away
  Same(H.Trim(s, 400), s, "nothing expired: the same string")
  Same(H.Trim("100,500|", 300), nil, "nothing is left after 120 days")
  Same(H.Trim("100,500;250,700|", 300), "250,700|", "only the old day went")
  -- malformed saved strings are no history at all, never guessed at
  for _, bad in ipairs({ "", "junk", "100,500", "|", "100,500|x", "100,0|", "100,5;100,6|", "100,5;99,6|", "100,5;|", ";100,5|", "100,5|1,2,3,4", "100,5|1,5,4,5,1", "100,5|1,5,9,3,1", "-1,5|" }) do
    Same(H.Decode(bad), nil, "malformed: " .. bad)
  end
  Same(H.Add("junk", 105, 77), "105,77|", "a malformed string is replaced by a fresh observation")
  Same(H.Decode(nil), nil); Same(H.Decode(12), nil)
end

---------------------------------------------------------------------------
-- The commit: stepped, atomic, history only from whole reads
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR, MK, H = t.W.Prices, t.W.Market, t.W.History
  local KEY = "Realm|Alliance"
  local function Commit(day, map, extra) return PR.Commit(KEY, ScanOf(day * D + 600, map, extra)) end
  local function Stats(item, day, period) return MK.Stats(item, period or "week", { market = KEY, now = day * D + 900 }) end

  Check(Commit(100, { [10] = 500, [11] = 900 }), "first scan")
  local st = Stats(10, 100)
  Check(st.basis:find("Not a sale price", 1, true) and st.basis:find("market value", 1, true), "the statistics say what they are")
  Check(MK.Price(10, { market = KEY }).basis:find("not a sale", 1, true))
  Same(st.n, 1); Check(st.single, "one day is not a history"); Same(st.low, 500); Same(st.high, 500); Same(st.average, 500); Same(st.newest.day, 100); Same(st.scans, 1)
  Same(PR.Market(KEY).histItems, 2)
  -- a second scan the same day with a lower price: the day's value is the later scan's
  Check(Commit(100, { [10] = 400 }))
  st = Stats(10, 100); Same(st.n, 1); Same(st.low, 400, "the later scan of the day wins")
  Same(Stats(11, 100).n, 1, "item 11 was not listed in the second scan; it keeps the day it was seen")
  Same(MK.Price(11, { market = KEY }), nil, "...but it has no CURRENT price: the newest scan did not list it")
  Same(select(2, MK.Price(11, { market = KEY })), "unlisted")
  Same(PR.Market(KEY).scanDays[1], 100); Same(#PR.Market(KEY).scanDays, 1, "two scans on one day are one scan day")
  -- day 101 has no scan; day 102 has
  Check(Commit(102, { [10] = 600 }))
  st = Stats(10, 102); Same(st.n, 2); Same(st.low, 400); Same(st.high, 600); Same(st.average, 500, "mean of the two observed days"); Same(st.scans, 2)
  Same(select(2, MK.Observed(10, 101, { market = KEY })), "notobserved", "no scan on 101: no value, none invented")
  Same(MK.Observed(10, 102 * D + 5, { market = KEY }).price, 600, "by time as well as by day number")
  Same(MK.Observed(10, 100, { market = KEY }).price, 400)
  local tr = MK.Trend(10, 7, { market = KEY, now = 102 * D + 900 })
  Same(tr.direction, "up"); Same(tr.change, 200); Same(tr.percent, 50); Same(tr.n, 2); Same(tr.from, 400); Same(tr.to, 600)
  local cmp = MK.Compare(10, "week", { market = KEY, now = 102 * D + 900 })
  Same(cmp.current, 600); Same(cmp.reference, 400, "the reference is the observed days BEFORE the current scan's day"); Same(cmp.relation, "above"); Same(cmp.difference, 200); Same(cmp.n, 1)
  Check(cmp.ratio == 1.5)
  -- item 11 has one day only: no trend, no comparison
  Same(select(2, MK.Trend(11, 7, { market = KEY, now = 102 * D + 900 })), "insufficient")
  -- a window with no observation is "nodata", not an average of nothing
  Same(select(2, MK.Stats(10, "week", { market = KEY, now = 150 * D })), "nodata")

  -- a scan that was cut off updates what is current but never the history, and a complete scan is never replaced by it
  local before = Ser(t.c.TwichUIWorkshopDB)
  local ok, why = Commit(103, { [10] = 100 }, { complete = false, cut = true })
  Check(not ok and why == "kept"); Same(Ser(t.c.TwichUIWorkshopDB), before, "kept: nothing changed")
  -- a market whose last scan was not complete takes a cut scan as the current prices, and still adds no history
  local cutKey = "Realm|Horde"
  Check(PR.Commit(cutKey, ScanOf(100 * D, { [10] = 800 }, { side = "Horde", complete = false, cut = true })))
  Same(MK.Price(10, { market = cutKey }).price, 800); Check(MK.Price(10, { market = cutKey }).cut)
  Check(table.concat(MK.Price(10, { market = cutKey }).notes, ","):find("cut", 1, true))
  Same(select(2, MK.Stats(10, "week", { market = cutKey, now = 100 * D })), "nodata", "a cut scan feeds no history")
  Check(PR.Commit(cutKey, ScanOf(101 * D, { [10] = 700 }, { side = "Horde", complete = false, changed = true })))
  Same(select(2, MK.Stats(10, "week", { market = cutKey, now = 101 * D })), "nodata", "nor does a scan whose listing count kept changing")
  Check(PR.Commit(cutKey, ScanOf(102 * D, { [10] = 600 }, { side = "Horde", complete = false, partial = 3 })))
  Same(MK.Stats(10, "week", { market = cutKey, now = 102 * D }).n, 1, "a whole read whose records lacked some item information IS valid evidence of that day's cheapest listing")

  -- a job dropped half way, or one that fails, changes nothing
  before = Ser(t.c.TwichUIWorkshopDB)
  local map = {}
  for i = 1, 3000 do map[1000 + i] = 100 + i end
  local job = assert(PR.BeginCommit(KEY, ScanOf(104 * D, map)))
  Check(not job:Step(1000), "1000 of 3000 items merged"); Check(job:Progress() > 0 and job:Progress() < 1)
  job = nil
  Same(Ser(t.c.TwichUIWorkshopDB), before, "a job that is dropped before Apply has written nothing")
  local realAdd = H.Add
  H.Add = function() error("boom") end
  local good = pcall(PR.Commit, KEY, ScanOf(104 * D, { [10] = 55 }))
  H.Add = realAdd
  Check(not good, "the failure is raised"); Same(Ser(t.c.TwichUIWorkshopDB), before, "and the saved market and its history are exactly as they were")
  -- steps are bounded
  job = assert(PR.BeginCommit(KEY, ScanOf(104 * D, map)))
  local steps = 0
  while not job:Step(1000) do steps = steps + 1 end
  Check(steps >= 2 and steps <= 5, "3000 new items plus the old ones take a few steps of 1000: " .. steps)
  Check(job:Apply()); Same(PR.Market(KEY).histItems, 3002 + 0, "history items: 10, 11 and the 3000 new ones")
  -- the item numbers of one scan that are not whole numbers are skipped, never saved
  local weird = ScanOf(105 * D, { [10] = 90 }); weird.items[1.5] = "5,1,1,1,0"; weird.items[0] = "5,1,1,1,0"; weird.items[77] = "junk"
  Check(PR.Commit(KEY, weird)); Same(PR.Market(KEY).hist[77], nil, "no history from an entry that is not a price"); Same(PR.Market(KEY).hist[0], nil)

  -- items a scan did not list keep their history until it expires; the history of an item that has nothing left is dropped
  Check(Commit(250, { [10] = 450 }))
  Same(MK.Stats(11, "retained", { market = KEY, now = 250 * D }), nil, "item 11 was last seen on day 100: more than 120 days: gone")
  Same(PR.Market(KEY).hist[11], nil)
  st = MK.Stats(10, "retained", { market = KEY, now = 250 * D })
  Same(st.n, 1, "10's old days expired as well; today's is all that is left (bucket days 100-105 are older than the 120 days)")
  Same(st.low, 450)
  Same(PR.Market(KEY).histItems, 1, "the count follows: only item 10 is left (the 3000 scanned on day 104 expired too)")
end

---------------------------------------------------------------------------
-- Retention is bounded however long it runs
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR, MK = t.W.Prices, t.W.Market
  local KEY = "Realm|Alliance"
  for day = 1, 300 do
    local map = {}
    for i = 1, 20 do map[i] = 1000 + (day * 7 + i * 13) % 500 end
    Check(PR.Commit(KEY, ScanOf(day * D + 100, map)), "scan " .. day)
  end
  local m = PR.Market(KEY)
  Same(m.n, 20); Same(m.histItems, 20); Check(#m.scanDays <= t.W.History.MAX_SCAN_DAYS, "scan days are bounded: " .. #m.scanDays)
  local pts, bks = t.W.History.Decode(m.hist[5])
  Check(#pts <= 14 and #bks <= 15, "per item: at most 7 exact days and 3 buckets")
  local st = MK.Stats(5, "retained", { market = KEY, now = 300 * D + 5 })
  Check(st.n <= 7 + 3 * 28 and st.n > 7, "retained history reaches back months, no further: " .. st.n); Check(not st.exact)
  local wk = MK.Stats(5, "week", { market = KEY, now = 300 * D + 5 })
  Same(wk.n, 7); Check(wk.exact and not wk.limited); Same(wk.scans, 7)
  local d14 = MK.Stats(5, 14, { market = KEY, now = 300 * D + 5 })
  Check(d14.limited and d14.n == 7, "14 days reaches into a bucket that straddles the start: only what lies entirely inside is counted, and it says so: " .. d14.n)
end

-- Series: what the chart may draw (the exact observed days, in order, with their real day numbers; older days only as groups; nothing between)
do
  local t = Setup()
  local PR, MK = t.W.Prices, t.W.Market
  local KEY = "Realm|Alliance"
  for _, day in ipairs({ 100, 102, 103 }) do Check(PR.Commit(KEY, ScanOf(day * D + 100, { [7] = 400 + day })), "scan " .. day) end
  local sr = MK.Series(7, { market = KEY, now = 103 * D + 5 })
  Same(#sr.points, 3, "three observed days, no more"); Same(sr.points[1].day, 100); Same(sr.points[2].day, 102); Same(sr.points[3].day, 103)
  Same(sr.points[1].price, 500); Same(sr.points[3].price, 503); Same(sr.today, 103)
  Check(not sr.points[4] and #sr.groups == 0, "day 101 has no value and gets none; no older group yet")
  Check(sr.basis:find("Not a sale price", 1, true), "it says what it is")
  -- the older days become groups (low, high, mean, how many), the exact days stay exact
  for day = 104, 135 do Check(PR.Commit(KEY, ScanOf(day * D + 100, { [7] = 400 + day })), "scan " .. day) end
  sr = MK.Series(7, { market = KEY, now = 135 * D + 5 })
  Same(#sr.points, 7, "the newest seven observed days"); Same(sr.points[7].day, 135); Same(sr.points[1].day, 129)
  Check(#sr.groups >= 1 and sr.groups[1].n >= 1 and sr.groups[1].low <= sr.groups[1].average and sr.groups[1].average <= sr.groups[1].high, "older days are a low, a high and a mean")
  for i = 2, #sr.groups do Check(sr.groups[i].from > sr.groups[i - 1].to, "groups are in order and do not overlap") end
  Check(sr.groups[#sr.groups].to < sr.points[1].day + 28, "groups lie behind the exact days' start")
  -- the reasons
  Same(select(2, MK.Series("x", { market = KEY })), "baditem"); Same(select(2, MK.Series(8, { market = KEY, now = 135 * D })), "nodata", "an item never observed")
  Same(select(2, MK.Series(7, { market = "Nowhere|Alliance" })), "nomarket")
  -- a cut scan feeds no history, so nothing is drawn for an item only it listed
  Same(select(2, MK.Series(7, { market = "Realm|Alliance", now = 135 * D })) == nil, true)
  local before = Ser(PR.Market(KEY))
  MK.Series(7, { market = KEY, now = 135 * D }); MK.Series(7, { market = KEY, now = 136 * D })
  Same(Ser(PR.Market(KEY)), before, "reading the series changes nothing")
end

---------------------------------------------------------------------------
-- Prices saved before the market data foundation
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR, MK = t.W.Prices, t.W.Market
  local legacy = { realm = "Realm", side = "Alliance", at = 99 * D, complete = true, read = 3, used = 3, n = 2, items = { [10] = { 100, 2, 3, 4 } } }
  t.c.TwichUIDB.workshop = { v = 1, prices = { v = 1, markets = { ["Realm|Alliance"] = legacy } } }
  local info = MK.Info({ market = "Realm|Alliance" })
  Same(info.scope, "recipes", "a scan from before full scans holds only recipe items, whatever it says"); Check(info.legacy and not info.complete, "a recipe-only scan is never reported as a complete market")
  local p = MK.Price(10, { market = "Realm|Alliance", now = 99 * D + 60 })
  Same(p.price, 100); Same(p.notes[1], "recipes")
  local none, why = MK.Price(55, { market = "Realm|Alliance" })
  Same(none, nil); Same(why, "outofscope", "absence from a recipe-only scan says nothing about the auction house")
  Same(select(2, MK.Stats(10, "week", { market = "Realm|Alliance" })), "outofscope")
  Same(MK.Source().market.key, "Realm|Alliance", "the views still find it")
  Same(#MK.Markets(), 1)
  -- a newer TwichUI's legacy prices are not read at all
  t.c.TwichUIDB.workshop.prices.v = 9
  Same(select(2, MK.Price(10, { market = "Realm|Alliance" })), "nomarket")
  t.c.TwichUIDB.workshop.prices.v = 1
  -- an incomplete full scan is not blocked by a legacy "complete" one, and replaces it (it is not saved twice)
  Check(PR.Commit("Realm|Alliance", ScanOf(100 * D, { [10] = 90, [55] = 5 }, { complete = false, partial = 4 })))
  Same(t.c.TwichUIDB.workshop.prices.markets["Realm|Alliance"], nil, "the recipe-only copy is gone")
  info = MK.Info({ market = "Realm|Alliance" })
  Same(info.scope, "full"); Check(not info.legacy and not info.complete); Same(info.partial, 4); Same(info.items, 2)
  Same(MK.Price(55, { market = "Realm|Alliance" }).price, 5)
  Same(#MK.Markets(), 1, "listed once")
  -- the other saved data is untouched
  Check(t.c.TwichUIDB.workshop.v == 1)
end

---------------------------------------------------------------------------
-- The API: prices, quotes, notes, reasons, markets, read-only
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR, MK = t.W.Prices, t.W.Market
  local A, Hd = "Realm|Alliance", "Realm|Horde"
  Check(PR.Commit(A, ScanOf(100 * D, { [10] = "100,3,5,20,150", [11] = "50,1,1,1,0", [12] = "7,2,2,4,0" })))
  Check(PR.Commit(Hd, ScanOf(99 * D, { [10] = "900,1,1,1,0" }, { side = "Horde" })))
  local now = 100 * D + 120
  local p = MK.Price(10, { market = A, now = now })
  Same(p.price, 100); Same(p.qty, 3); Same(p.listings, 5); Same(p.total, 20); Same(p.next, 150); Same(p.at, 100 * D); Same(p.age, 120); Check(not p.old)
  Check(p.complete); Same(p.scope, "full"); Same(p.market, A); Check(p.label:find("Alliance auction house on Realm", 1, true)); Same(#p.notes, 0)
  Same(MK.Price(10, { market = Hd, now = now }).price, 900, "the Horde market is its own")
  Same(MK.Price(11, { market = A, now = now }).notes[1], "thin", "a single listing is stated as a fact")
  local old = MK.Price(10, { market = A, now = now + 2 * D }); Check(old.old); Same(old.notes[1], "old")
  -- reasons
  Same(select(2, MK.Price("x", { market = A })), "baditem"); Same(select(2, MK.Price(0, { market = A })), "baditem"); Same(select(2, MK.Price(1.5, { market = A })), "baditem")
  Same(select(2, MK.Price(nil, { market = A })), "baditem"); Same(select(2, MK.Price(99, { market = A })), "unlisted")
  Same(select(2, MK.Price(10, { market = "Nowhere|Alliance" })), "nomarket")
  Same(select(2, MK.Price(10, { market = A, variant = true })), "variant", "a variant is never given the base item's price")
  Same(select(2, MK.Stats(10, "month", { market = A })), "badperiod"); Same(select(2, MK.Stats(10, 0, { market = A })), "badperiod"); Same(select(2, MK.Stats(10, 9999, { market = A })), "badperiod")
  Same(select(2, MK.Stats(10, 2.5, { market = A })), "badperiod"); Same(select(2, MK.Stats("x", "week", { market = A })), "baditem")
  Same(select(2, MK.Trend(10, 1, { market = A })), "badperiod", "a trend needs at least two days")
  for _, r in pairs({ "baditem", "badqty", "nomarket", "variant", "unlisted", "outofscope", "nodata", "insufficient", "badperiod" }) do Check(MK.REASONS[r], "a sentence for " .. r) end
  -- quotes: exact up to the items at the cheapest price, an estimate beyond it, "few" past what is listed
  local q = MK.Quote(10, 2, { market = A, now = now }); Same(q.state, "exact"); Same(q.cost, 200); Same(q.price.price, 100)
  q = MK.Quote(10, 3, { market = A, now = now }); Same(q.state, "exact"); Same(q.cost, 300)
  q = MK.Quote(10, 10, { market = A, now = now }); Same(q.state, "estimate"); Same(q.cost, 1000, "the least it could cost"); Same(q.total, 20)
  q = MK.Quote(10, 21, { market = A, now = now }); Same(q.state, "few"); Same(q.cost, nil, "never a cost for what is not listed")
  q = MK.Quote(99, 1, { market = A }); Same(q.state, "none"); Same(q.why, "unlisted"); Same(q.cost, nil)
  q = MK.Quote(10, 0, { market = A }); Same(q.state, "none"); Same(q.why, "badqty")
  q = MK.Quote(10, "3", { market = A }); Same(q.state, "none"); Same(q.why, "badqty")
  -- markets and sources
  local ms = MK.Markets({ now = now })
  Same(#ms, 2); Same(ms[1].key, A, "newest scan first"); Same(ms[2].key, Hd); Same(ms[1].items, 3); Same(ms[1].scans, 1); Check(ms[1].complete and ms[1].scope == "full")
  Same(MK.Info({ market = Hd }).side, "Horde"); Same(select(2, MK.Info({ market = "x" })), "nomarket")
  t.c.AuctionHouseFrame:Show()
  Same(MK.Source().key, A, "with the auction house open: only its own market"); Check(MK.Source().open)
  t.ah.side = "Horde"; Same(MK.Source().key, Hd, "the other side's house is another market"); t.ah.side = "Alliance"
  t.c.AuctionHouseFrame:Hide()
  Same(MK.Source().market.key, A, "closed: the most recently scanned market of this realm")
  Same(MK.Price(10).price, 100, "no option: the market the views use")
  -- read-only: no call changes the saved data, and the answers are copies
  local before = Ser(t.c.TwichUIWorkshopDB)
  for _, o in ipairs({ { market = A, now = now }, { market = Hd }, {} }) do
    MK.Price(10, o); MK.Quote(10, 5, o); MK.Stats(10, "week", o); MK.Stats(10, "retained", o); MK.Trend(10, 7, o); MK.Compare(10, "week", o)
    MK.Observed(10, 100, o); MK.Info(o)
  end
  MK.Markets()
  Same(Ser(t.c.TwichUIWorkshopDB), before, "asking changes nothing")
  p = MK.Price(10, { market = A }); p.price = 1; p.notes[1] = "x"
  Same(MK.Price(10, { market = A }).price, 100); Same(#MK.Price(10, { market = A }).notes, 0)
  ms[1].items = 0; Same(MK.Markets()[1].items, 3)
  -- the same figures reach every consumer
  local S = t.W.Session
  local opps = S.Opportunities()
  Same(opps.lookup(10).price, MK.Price(10).price, "Opportunities")
  Same(S.PriceSource().market.key, MK.Source().market.key, "the views and the API choose the same market")
end

---------------------------------------------------------------------------
-- Full scans against a fake auction house
---------------------------------------------------------------------------
local function Run(t, records)
  t.ah.records = records
  local SC = t.W.Scan
  Check(SC.Start()); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(120)
  return SC
end
do
  -- no professions, no recipes, ordinary loot: the whole house is priced
  local t = Setup()
  local PR, MK, S = t.W.Prices, t.W.Market, t.W.Session
  local recs = {}
  for i = 1, 5000 do recs[#recs + 1] = { item = 20000 + i, count = 1 + i % 5, buyout = (100 + i) * (1 + i % 5) } end   -- 5000 distinct items, stacks of 1-5
  recs[#recs + 1] = { item = 20001, count = 1, buyout = 50 }           -- a second, cheaper listing
  recs[#recs + 1] = { item = 20002, count = 3, buyout = 0 }            -- bid only
  recs[#recs + 1] = { item = 20003, count = 1, buyout = 0 / 0 }        -- not a number
  recs[#recs + 1] = { item = "junk", count = 1, buyout = 10 }
  Same(#S.Professions(), 0, "no profession has been read")
  t.ah.records = recs
  Check(S.StartScan(), "the player's click starts a scan with no professions and no recipes")
  t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(120)
  local SC = t.W.Scan
  Same(SC.state, "done", SC.why); Check(SC.result.complete, "a whole read"); Same(SC.result.items, 5000, "all 5000 distinct items, 2000 was the old limit")
  Same(SC.result.read, 5004); Same(SC.result.used, 5001)
  local m = PR.Market("Realm|Alliance")
  Same(m.scope, "full"); Same(m.n, 5000); Same(m.histItems, 5000)
  Same(MK.Price(20001, { market = "Realm|Alliance" }).price, 50, "the cheapest of an item's listings"); Same(MK.Price(20001, { market = "Realm|Alliance" }).listings, 2)
  Same(MK.Price(20001, { market = "Realm|Alliance" }).next, 101 + 0 * 1, "the next higher price")
  Same(MK.Price(20002, { market = "Realm|Alliance" }).price, 102, "3 for 306, and the bid-only listing was ignored")
  Same(MK.Price(20004, { market = "Realm|Alliance" }).price, 104, "a stack of 5 at 520 is 104 each")
  Same(select(2, MK.Price(1, { market = "Realm|Alliance" })), "unlisted")
  Check(SC.Message():find("Prices found for 5000 items", 1, true))
  Same(MK.Stats(20010, "week", { market = "Realm|Alliance" }).n, 1)
  Same(t.Pending(), 0, "no timer is left running")
  -- the saving took several steps (5000 items, 1000 per step) and the interface was handed back between them
  Same(m.hist[20010], "100,110|", "day 100, 110 copper")
end

do
  -- the saving: steps between frames, the auction house closing meanwhile, updates meanwhile, a second click meanwhile
  local t = Setup()
  local SC, PR = t.W.Scan, t.W.Prices
  local recs = {}
  for i = 1, 4500 do recs[#recs + 1] = { item = i, count = 1, buyout = 10 + i } end
  t.ah.records = recs
  Check(SC.Start()); t.Fire("REPLICATE_ITEM_LIST_UPDATE")
  local n = 0
  while SC.phase ~= "saving" and SC.state == "scanning" and n < 100 do t.Tick(); n = n + 1 end
  Same(SC.phase, "saving", "the listings are read; the saving is in steps"); Check(SC.Progress() > 0.88 and SC.Progress() < 1)
  Same(SC.Message(), "Saving prices...")
  Same(PR.Market("Realm|Alliance"), nil, "nothing is written before the last step")
  local ok, why = SC.Start(); Check(not ok and why == "busy", "a click meanwhile does nothing")
  t.Fire("REPLICATE_ITEM_LIST_UPDATE"); Same(SC.phase, "saving", "an update meanwhile does not start a new read")
  t.Fire("AUCTION_HOUSE_CLOSED"); Same(SC.state, "scanning", "the listings were read already: closing the window does not throw them away")
  t.c.AuctionHouseFrame:Hide()
  t.Advance(30)
  Same(SC.state, "done"); Same(PR.Market("Realm|Alliance").n, 4500); Same(t.Listening(), 0, "and it stops listening")
  t.c.AuctionHouseFrame:Show()
end

do
  -- a failing save leaves the earlier prices and history as they were
  local t = Setup()
  local SC, PR, MK, H = t.W.Scan, t.W.Prices, t.W.Market, t.W.History
  Run(t, { { item = 10, count = 1, buyout = 500 }, { item = 11, count = 1, buyout = 900 } })
  Same(SC.state, "done")
  local before = Ser(t.c.TwichUIWorkshopDB)
  t.SetDay(101)
  local realAdd = H.Add
  H.Add = function() error("boom") end
  Run(t, { { item = 10, count = 1, buyout = 400 } })
  H.Add = realAdd
  Same(SC.state, "failed"); Same(SC.why, "unsaved"); Same(Ser(t.c.TwichUIWorkshopDB), before, "price, history and scan days exactly as before")
  Check(SC.Message():find("couldn't be saved", 1, true))
  Same(MK.Price(10, { market = "Realm|Alliance" }).price, 500)
  -- the next scan works
  Run(t, { { item = 10, count = 1, buyout = 400 } })
  Same(SC.state, "done"); Same(MK.Stats(10, "week", { market = "Realm|Alliance", now = 101 * D + 900 }).n, 2)
  -- a newer TwichUI's data is held: a scan is refused and nothing is changed
  t.c.TwichUIWorkshopDB.v = 3
  local ok, why = SC.Start(); Check(not ok and why == "held")
  t.c.TwichUIWorkshopDB.v = 1
end

do
  -- changing listing counts (restart), stale callbacks, history across days and a partial scan
  local t = Setup()
  local SC, PR, MK = t.W.Scan, t.W.Prices, t.W.Market
  local function Recs(price) local r = {} for i = 1, 900 do r[i] = { item = i, count = 1, buyout = price + i } end return r end
  Run(t, Recs(1000)); Same(SC.state, "done"); Check(SC.result.complete)
  t.SetDay(101); Run(t, Recs(900)); Same(SC.state, "done")
  t.SetDay(103); Run(t, Recs(1100)); Same(SC.state, "done")
  local st = MK.Stats(5, "week", { market = "Realm|Alliance", now = 103 * D + 900 })
  Same(st.n, 3); Same(st.low, 905); Same(st.high, 1105); Same(st.average, math.floor((1005 + 905 + 1105) / 3 + 0.5)); Same(st.scans, 3)
  Same(MK.Trend(5, 7, { market = "Realm|Alliance", now = 103 * D + 900 }).direction, "up")
  -- an item that disappears from the house keeps its history but loses its current price
  local r = Recs(1000); table.remove(r, 5)
  t.SetDay(104); Run(t, r)
  Same(select(2, MK.Price(5, { market = "Realm|Alliance" })), "unlisted"); Same(MK.Stats(5, "week", { market = "Realm|Alliance", now = 104 * D + 900 }).n, 3)
  -- the old response timer of an earlier scan does nothing to a new one
  t.ah.records = Recs(1000)
  Check(SC.Start()); t.Advance(1); t.Fire("AUCTION_HOUSE_CLOSED"); Same(SC.state, "interrupted")
  Check(SC.Start()); t.Advance(80); Same(SC.state, "scanning"); t.Advance(30); Same(SC.why, "noResponse")
  Same(MK.Info({ market = "Realm|Alliance" }).items, 899, "the interrupted and the failed scans wrote nothing")
end

---------------------------------------------------------------------------
-- A reload: the saved data goes to a fresh client and answers the same
---------------------------------------------------------------------------
do
  local a = Setup()
  local KEY = "Realm|Alliance"
  for day = 100, 104 do Check(a.W.Prices.Commit(KEY, ScanOf(day * D + 5, { [10] = 500 + day, [11] = 900 }))) end
  Check(a.W.Prices.Commit(KEY, ScanOf(105 * D + 5, { [10] = 700 }, { complete = false, cut = true })) == false, "kept")
  local function Copy(v) if type(v) ~= "table" then return v end local o = {} for k, x in pairs(v) do o[k] = Copy(x) end return o end
  local b = Setup()
  b.c.TwichUIWorkshopDB = Copy(a.c.TwichUIWorkshopDB)   -- what the game hands back after /reload
  local o = { market = KEY, now = 104 * D + 900 }
  local pa, pb = a.W.Market.Price(10, o), b.W.Market.Price(10, o)
  Same(pb.price, pa.price); Same(pb.listings, pa.listings)
  local sa, sb = a.W.Market.Stats(10, "week", o), b.W.Market.Stats(10, "week", o)
  Same(sb.n, 5); Same(sb.average, sa.average); Same(sb.low, sa.low); Same(sb.scans, sa.scans)
  Same(Ser(b.c.TwichUIWorkshopDB), Ser(a.c.TwichUIWorkshopDB), "nothing changed by loading")
  -- and a scan on the reloaded client extends the same history
  b.SetDay(106); b.ah.records = { { item = 10, count = 1, buyout = 321 } }
  Check(b.W.Scan.Start()); b.Fire("REPLICATE_ITEM_LIST_UPDATE"); b.Advance(60)
  Same(b.W.Market.Stats(10, "week", { market = KEY, now = 106 * D + 900 }).n, 6)
  -- a damaged flag cannot make a cut scan complete
  b.c.TwichUIWorkshopDB.markets[KEY].cut = true; b.c.TwichUIWorkshopDB.markets[KEY].complete = true
  Check(not b.W.Prices.Market(KEY).complete)
  -- before the game has filled the global in: nothing is read, nothing is made
  b.c.TwichUIWorkshopDB = nil
  Same(select(2, b.W.Market.Price(10, { market = KEY })), "nomarket"); Same(b.c.TwichUIWorkshopDB, nil, "reading never creates it")
end

print("PASSED")
