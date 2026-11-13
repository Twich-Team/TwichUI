-- Workshop market arithmetic against INDEPENDENT REFERENCE MODELS, on deterministic seeded scenarios (testing roadmap M2).
--   * the auction batch (Prices.NewBatch/Add/Items) against TwichUI_TestLab/Reference.lua: every valid listing kept, prices compared as mixed
--     numbers, 200 seeded houses, plus order, isolation and repetition properties;
--   * the history and the statistics (Prices.Commit, History, Market.Stats/Trend/Compare/Observed/Series) against a model that keeps every
--     observed day: 200 seeded calendars, then 60 seeds of three interleaved markets, compared after EVERY scan and at several query times;
--   * targeted regressions: the Trend window boundary (the first day of "the last N days" is included) and the sign-symmetric rounding of a
--     percentage change (the two mutants that survived the 2026-11-12 probe);
--   * the generator itself (Fixtures.lua): reproducible, bounded, different seeds give different scenarios.
-- Synthetic: it proves the logic against a second derivation, not what the real auction house returns.
--
-- SEEDS (fixed, so every machine runs the same scenarios): batch 7100000+i, history 7200000+i, markets 7300000+i, for i = 1..N.
-- RERUN one failing seed:   MARKET_SEED=7200042 (cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_workshop_market_reference.lua)
-- STRESS (optional, not part of ./tests/run.sh's time budget):  MARKET_SCENARIOS=3000   MARKET_ALL=1 reports every difference instead of the first.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")   -- string.format refuses what the client refuses (%d beyond 32 bits, NaN)

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "Prices.lua", "Opportunities.lua",
    "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }
local LAB = ROOT .. "../TwichUI_TestLab/"
local D = 86400

local ONLY = tonumber(os.getenv("MARKET_SEED") or "")
local N = tonumber(os.getenv("MARKET_SCENARIOS") or "") or 200
local COLLECT = os.getenv("MARKET_ALL") ~= nil

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.GetRealmName = function() return "Realm" end
for _, f in ipairs(FILES) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
for _, f in ipairs({ "Fixtures.lua", "Reference.lua" }) do
  local chunk = assert(loadfile(LAB .. f)); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
end
c.TwichUI.Workshop.Prices.FEED_LEGACY_HISTORY = true   -- these tests exercise the 1.3 history feed; production keeps it frozen (test_workshop_schema.lua)
local W = c.TwichUI.Workshop
local PR, MK, H = W.Prices, W.Market, W.History
local FX, REF = c.TwichUI.TestLab.Fixtures, c.TwichUI.TestLab.Reference

local function Ser(v)
  if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- differences: the first one stops the run (with the seed and what is needed to reproduce it), or all are collected under MARKET_ALL
local found = {}
local function Differ(model, seed, index, what, input, expected, actual)
  local msg = ("%s MISMATCH seed=%s scenario=%s: %s\n  input:    %s\n  expected: %s\n  actual:   %s\n  rerun:    MARKET_SEED=%s"):format(
    model, tostring(seed), tostring(index), what, input, expected, actual, tostring(seed))
  if not COLLECT then error(msg, 0) end
  found[#found + 1] = msg
end
local function Expect(model, seed, index, what, input, expected, actual)
  local e, a = type(expected) == "table" and Ser(expected) or tostring(expected), type(actual) == "table" and Ser(actual) or tostring(actual)
  if e ~= a then Differ(model, seed, index, what, input, e, a) return false end
  return true
end

local clock0 = os.clock()
local totals = { batchScenarios = 0, records = 0, calendars = 0, scans = 0, queries = 0, marketSets = 0 }

---------------------------------------------------------------------------
-- 0. The fixtures: reproducible, different, bounded
---------------------------------------------------------------------------
do
  -- a known-answer vector: the first draws of the generator, worked out independently (Wichmann-Hill in Python, doubles), so the generator
  -- cannot drift between machines or interpreters without this noticing
  local rng = FX.Rng(1)
  local got = {}
  for i = 1, 5 do got[i] = rng:Int(1, 1000) end
  Same(table.concat(got, ","), "181,710,535,808,811", "the seed-1 vector")

  -- identical seeds, identical scenarios; different seeds, different scenarios
  local a, b = FX.Listings(11, { records = 60 }), FX.Listings(11, { records = 60 })
  Same(Ser(a), Ser(b), "a seed reproduces its listings")
  Same(Ser(FX.Calendar(11, { scans = 30 })), Ser(FX.Calendar(11, { scans = 30 })), "a seed reproduces its calendar")
  local seen, collisions = {}, 0
  for seed = 1, 2000 do
    local r = FX.Rng(seed)
    local key = ("%.9f,%.9f,%.9f"):format(r:Next(), r:Next(), r:Next())
    if seen[key] then collisions = collisions + 1 end
    seen[key] = true
  end
  Same(collisions, 0, "seeds 1..2000 give distinct opening draws")
  Check(Ser(FX.Listings(12, { records = 60 })) ~= Ser(a), "a neighbouring seed gives another scenario")
  -- roughly uniform: ten bins over 20,000 draws
  local bins, r = {}, FX.Rng(99)
  for i = 1, 10 do bins[i] = 0 end
  for _ = 1, 20000 do local k = r:Int(1, 10); bins[k] = bins[k] + 1 end
  for i = 1, 10 do Check(bins[i] > 1800 and bins[i] < 2200, "bin " .. i .. " holds " .. bins[i]) end
  -- bounds: nothing asks for a pathological allocation
  Same(#FX.Listings(1, { records = 1e9 }).records, FX.LIMITS.records, "records are clamped")
  Same(#FX.Listings(1, { items = 1e9, records = 0 }).items, FX.LIMITS.items, "items are clamped")
  Same(#FX.Calendar(1, { scans = 1e9 }).scans, FX.LIMITS.scans, "scans are clamped")
  Same(#FX.Markets(1, 1e9), FX.LIMITS.markets, "markets are clamped")
  Same(#FX.Listings(1, { records = -5 }).records, 0, "a negative size is none")
  Same(#FX.Listings(1, { records = 0 / 0 }).records, 40, "a NaN size falls back to the default")
  Same(#FX.Calendar(0 / 0, {}).scans, 20, "a NaN seed still gives a scenario")
  -- the generator's records are game-shaped, and what is deliberately malformed says so
  local kinds = { priced = 0, nobuyout = 0, invalid = 0 }
  for seed = 1, 40 do
    for _, rec in ipairs(FX.Listings(seed, { records = 200 }).records) do
      kinds[rec.intent] = kinds[rec.intent] + 1
      if rec.intent == "priced" then
        Check(type(rec.item) == "number" and type(rec.count) == "number" and type(rec.buyout) == "number" and rec.buyout >= 1, "a priced record holds numbers")
        Check(rec.item % 1 == 0 and rec.count % 1 == 0 and rec.buyout % 1 == 0 and rec.buyout <= FX.MAX_COPPER and rec.count <= FX.MAX_COUNT, "...whole and in range")
      end
    end
  end
  Check(kinds.priced > 5000 and kinds.nobuyout > 400 and kinds.invalid > 300, "every kind of record occurs: " .. Ser(kinds))
  -- the model constants equal History's documented ones
  Same(REF.POINTS, H.POINTS); Same(REF.BUCKET, H.BUCKET_DAYS); Same(REF.MAX_BUCKETS, H.MAX_BUCKETS); Same(REF.RETAIN, H.RETAIN_DAYS)
  Same(REF.MAX_SCAN_DAYS, H.MAX_SCAN_DAYS); Same(REF.DAY, H.DAY); Same(FX.MAX_COPPER, PR.MAX_COPPER); Same(FX.MAX_COUNT, PR.MAX_COUNT); Same(FX.MAX_ID, W.MAX_ID)
end

---------------------------------------------------------------------------
-- 1. The reference model's own arithmetic, by hand (so the model is trusted before it judges anything)
---------------------------------------------------------------------------
do
  local F = REF.CompareFractions
  Same(F(1, 3, 1, 3), 0); Same(F(1, 3, 2, 6), 0, "1/3 equals 2/6"); Same(F(299, 3, 100, 1), -1, "99.67 is below 100")
  Same(F(7, 7, 3, 3), 0, "1 equals 1"); Same(F(10001, 10000, 1, 1), 1, "1.0001 is above 1")
  Same(F(99999999999, 9999, 99999999999, 10000), 1, "the same buyout over fewer items costs more each")
  Same(F(99999999998, 10000, 9999999999, 1000), 1, "9999999.9998 is above 9999999.9990")
  Same(F(9999999999, 1000, 99999999998, 10000), -1, "...and 9999999.9990 is below 9999999.9998")
  Same(REF.RoundHalfUp(5, 2), 3, "2.5 rounds up"); Same(REF.RoundHalfUp(7, 3), 2, "2.33 rounds down"); Same(REF.RoundHalfUp(0, 5), 0)
  -- tenths of a percent, ties away from zero
  local T = REF.PercentTenths
  Same(T(1000, 900), -100, "-10.0 %"); Same(T(300, 200), -333, "-33.33 % is -33.3"); Same(T(2000, 1999), -1, "-0.05 % ties away from zero");
  Same(T(2000, 2001), 1, "+0.05 %"); Same(T(1000, 1100), 100); Same(T(7, 8), 143, "+14.2857 %"); Same(T(7, 6), -143, "-14.2857 %")
  Same(T(3, 5), 667, "+66.67 %"); Same(T(3, 1), -667); Same(T(5, 5), 0); Same(T(99999999999, 1), -1000, "-100.0 %")
  -- the item model, a few days by hand
  local it = REF.Item()
  for d = 100, 107 do Check(it:Observe(d, 1000 + d)) end
  Same(Ser(it:Buckets()), Ser({ { b = 3, lo = 1100, hi = 1100, sum = 1100, n = 1 } }), "day 100 folded into bucket 3 (days 84..111)")
  Same(#it:Points(), 7)
  local ok, why = it:Observe(105, 5); Check(not ok and why == "stale")
end

---------------------------------------------------------------------------
-- 2. TARGETED REGRESSIONS: the two Trend mutants that survived
---------------------------------------------------------------------------
do
  -- A synthetic market table is the boundary Market.* accepts through opt.market (no saved data is touched).
  local function Hist(str) return { key = "Synthetic|x", scope = "full", items = {}, at = 200 * D, hist = { [10] = str } } end
  local function Trend(str, days, nowDay) return MK.Trend(10, days, { market = Hist(str), now = nowDay * D + 900 }) end

  -- "the last 7 days" counted back from day 200 are days 194..200: the FIRST day (194) is in, day 193 is out
  local tr = Trend("193,100;194,110;200,120|", 7, 200)
  Check(tr, "194 and 200 are two days of the last seven")
  Same(tr.n, 2); Same(tr.fromDay, 194, "the window starts on day 194, not 195, and not before 194"); Same(tr.from, 110, "day 193 is outside the window"); Same(tr.to, 120)
  Same(tr.change, 10); Same(tr.percent, 9.1, "10 / 110 = 9.09 %")
  -- with ONLY day 194 and day 200 inside the window, excluding the first day leaves one day and no trend
  tr = Trend("194,110;200,120|", 7, 200)
  Check(tr and tr.n == 2 and tr.fromDay == 194, "a window of 7 days holds its first day")
  -- the same edge for other lengths: 2 days = 199..200, 28 days = 173..200
  tr = Trend("198,50;199,60;200,70|", 2, 200); Same(tr.fromDay, 199); Same(tr.n, 2); Same(tr.from, 60)
  tr = Trend("172,5;173,8;200,9|", 28, 200); Same(tr.fromDay, 173, "28 days back from 200 starts on 173"); Same(tr.from, 8)
  Same(select(2, Trend("193,100;200,120|", 7, 200)), "insufficient", "day 193 is the eighth day back: one day in the window is no trend")

  -- a percentage change is the change over the FIRST price to one decimal, ties rounded away from zero, the same for falls as for rises
  local cases = {
    -- {first, last, percent, direction}, each worked out by hand
    { 1000, 900, -10, "down" },            -- -100 / 1000 = -10 % exactly (it must not be shown as -10.1)
    { 1000, 1100, 10, "up" },
    { 300, 200, -33.3, "down" },           -- -33.333...
    { 200, 300, 50, "up" },
    { 7, 6, -14.3, "down" },               -- -14.2857
    { 7, 8, 14.3, "up" },                  -- +14.2857
    { 3, 1, -66.7, "down" },               -- -66.666...
    { 3, 5, 66.7, "up" },                  -- +66.666...
    { 2000, 1999, -0.1, "down" },          -- -0.05 %: the tie goes away from zero
    { 2000, 2001, 0.1, "up" },             -- +0.05 %
    { 1000, 1000, 0, "flat" },
    { 99999999999, 1, -100, "down" },      -- the largest fall
    { 1, 99999999999, 9999999999800, "up" }, -- the largest rise: (99999999999 - 1) / 1 = 99999999998 = 9,999,999,999,800 %
  }
  for _, k in ipairs(cases) do
    local t = Trend(("150,%.0f;200,%.0f|"):format(k[1], k[2]), 60, 200)
    Check(t, "a trend for " .. k[1] .. " -> " .. k[2])
    Same(t.percent, k[3], ("%.0f -> %.0f"):format(k[1], k[2])); Same(t.direction, k[4], ("%.0f -> %.0f direction"):format(k[1], k[2]))
    Same(t.change, k[2] - k[1])
  end
  -- fall and rise are mirror images: for any first price a and difference d, a -> a-d is exactly the negative of a -> a+d
  local rng = FX.Rng(7400000)
  for i = 1, 300 do
    local a = rng:Pick({ rng:Int(2, 50), rng:Int(2, 5000), rng:Int(2, 900000) })
    local d = rng:Int(1, a - 1)
    local down = Trend(("150,%d;200,%d|"):format(a, a - d), 60, 200)
    local up = Trend(("150,%d;200,%d|"):format(a, a + d), 60, 200)
    if down.percent ~= -up.percent then
      error(("a fall of %d from %d reads %s but a rise of %d reads %s (seed 7400000, case %d)"):format(d, a, tostring(down.percent), d, tostring(up.percent), i), 0)
    end
    Same(down.percent, -REF.PercentTenths(a, a + d) / 10, "a mirror image of the reference")
  end
end

---------------------------------------------------------------------------
-- 3. The auction batch against the reference
---------------------------------------------------------------------------
local function ShowRecord(r)
  return ("{item=%s,count=%s,buyout=%s,info=%s}"):format(tostring(r.item), tostring(r.count), tostring(r.buyout), tostring(r.info))
end
local function RecordsOf(records, item)
  local out = {}
  for _, r in ipairs(records) do
    if r.item == item then out[#out + 1] = ShowRecord(r) end
    if #out >= 14 then out[#out + 1] = "..." break end
  end
  return table.concat(out, " ")
end

local function Parse(entry)
  local p, q, l, t, x = entry:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$")
  return tonumber(p), tonumber(q), tonumber(l), tonumber(t), tonumber(x)
end

local strictDiffers, batchChecks = 0, 0
local function BatchOf(records, priority)
  local b = PR.NewBatch(priority)
  local returns = {}
  for i, r in ipairs(records) do returns[i] = b:Add(r.item, r.count, r.buyout, r.info) end
  return b, returns
end

local function CheckBatch(seed, index)
  local rng = FX.Rng(seed * 3 + 1)
  local medium = index % 10 == 0
  local gen = FX.Listings(seed, { items = medium and rng:Int(20, 60) or rng:Int(1, 4), records = medium and rng:Int(200, 600) or rng:Int(0, 40),
    tiers = rng:Int(1, 4), invalid = rng:Pick({ 0, 0.08, 0.3 }), noBuyout = rng:Pick({ 0, 0.1, 0.4 }), partial = rng:Pick({ 0, 0.1, 0.5 }) })
  local records = gen.records
  totals.records = totals.records + #records
  local exp = REF.ExpectBatch(records)
  local b, returns = BatchOf(records)
  local items, n, over, dropped = b:Items()
  local label = ("%d records, %d items"):format(#records, #gen.items)

  -- the generator's intent agrees with the model's reading of each record (a cross-check of both)
  local intent = { priced = 0, nobuyout = 0, invalid = 0 }
  for i, r in ipairs(records) do
    intent[r.intent] = intent[r.intent] + 1
    local single = REF.ExpectBatch({ r })
    if (single.used == 1) ~= (returns[i] == true) then
      Differ("batch", seed, index, "whether record " .. i .. " counted toward a price", ShowRecord(r), single.used == 1, returns[i])
    end
  end
  Expect("batch", seed, index, "records by intent", label, { exp.used, exp.noBuyout, exp.invalid }, { intent.priced, intent.nobuyout, intent.invalid })

  -- batch accounting
  Expect("batch", seed, index, "counters read/used/noBuyout/invalid/partial", label,
    { exp.read, exp.used, exp.noBuyout, exp.invalid, exp.partial }, { b.read, b.used, b.noBuyout, b.invalid, b.partialInfo })
  Expect("batch", seed, index, "read = used + noBuyout + invalid", label, b.read, b.used + b.noBuyout + b.invalid)
  Expect("batch", seed, index, "items kept", label, exp.n, n)
  Expect("batch", seed, index, "not over the limit", label, false, over)

  local sumL, sumT, expT = 0, 0, 0
  for item, e in pairs(exp.items) do
    local got = items[item]
    if not got then Differ("batch", seed, index, "item " .. item .. " is missing", RecordsOf(records, item), REF.EntryText(e), "nil")
    else
      Expect("batch", seed, index, "item " .. item .. " p,q,l,t,x", RecordsOf(records, item), REF.EntryText(e), got)
      local p, q, l, t, x = Parse(got)
      if p then
        -- invariants of the saved entry, from the entry alone
        local ok = p >= 1 and q >= 1 and q <= t and l >= 1 and l <= t and (x == 0 or x > p)
        if not ok then Differ("batch", seed, index, "item " .. item .. " entry invariants (p>=1, 1<=q<=t, 1<=l<=t, x==0 or x>p)", RecordsOf(records, item), "holds", got) end
        sumL, sumT = sumL + l, sumT + t
      end
      expT = expT + e.t
      if e.x ~= e.xStrict then strictDiffers = strictDiffers + 1 end
      if got ~= nil and e.x ~= 0 and e.x ~= e.xStrict then
        Differ("batch", seed, index, "x is either 0 or the literal next higher price", RecordsOf(records, item), e.xStrict, e.x)
      end
    end
  end
  for item in pairs(items) do
    if not exp.items[item] then Differ("batch", seed, index, "item " .. tostring(item) .. " should not be priced", RecordsOf(records, item), "no entry", items[item]) end
  end
  -- nothing counted twice: the listings of all entries are the used records, the items the sum of the counts
  Expect("batch", seed, index, "sum of listings = records used", label, b.used, sumL)
  Expect("batch", seed, index, "sum of items = items in the used records", label, expT, sumT)
  batchChecks = batchChecks + 1

  -- ORDER does not matter
  local shuffled = {}
  for i, r in ipairs(records) do shuffled[i] = r end
  FX.Rng(seed + 5):Shuffle(shuffled)
  local items2 = BatchOf(shuffled):Items()
  for item, entry in pairs(items) do
    if items2[item] ~= entry then Differ("batch", seed, index, "order-independence of item " .. item, RecordsOf(records, item), entry, items2[item]) end
  end
  -- ISOLATION: an item priced from its own records only gives the same entry
  local checked = 0
  for item, entry in pairs(items) do
    if checked >= 2 then break end
    checked = checked + 1
    local own = {}
    for _, r in ipairs(records) do if r.item == item then own[#own + 1] = r end end
    local alone = BatchOf(own):Items()[item]
    if alone ~= entry then Differ("batch", seed, index, "item " .. item .. " priced alone differs from priced among others", RecordsOf(records, item), entry, alone) end
  end
  -- REPETITION: the same records twice keep p and x, and double q, l and t
  if #records <= 60 then
    local twice = {}
    for _, r in ipairs(records) do twice[#twice + 1] = r end
    for _, r in ipairs(records) do twice[#twice + 1] = r end
    local items3 = BatchOf(twice):Items()
    for item, entry in pairs(items) do
      local p, q, l, t, x = Parse(entry)
      local want = ("%.0f,%.0f,%.0f,%.0f,%.0f"):format(p, q * 2, l * 2, t * 2, x)
      if items3[item] ~= want then Differ("batch", seed, index, "item " .. item .. " with every record added twice", RecordsOf(records, item), want, items3[item]) end
    end
  end

  -- the item limit: priority items first, then the most listings, then the lowest item number (limit lowered for the scenario)
  if index % 4 == 0 and exp.n >= 3 then
    local limit = rng:Int(1, exp.n - 1)
    local priority = {}
    for _, id in ipairs(gen.items) do if rng:Chance(0.3) then priority[id] = true end end
    local was = PR.MAX_ITEMS
    PR.MAX_ITEMS = limit
    local ok, kept, kn, kover, kdropped = pcall(function() local o, nn, ov, dr = BatchOf(records, priority):Items() return o, nn, ov, dr end)
    PR.MAX_ITEMS = was
    if not ok then error(kept, 0) end
    local want, wantDropped = REF.Keep(exp.items, limit, priority)
    local gotIds, wantIds = {}, {}
    for id in pairs(kept) do gotIds[#gotIds + 1] = id end
    for id in pairs(want) do wantIds[#wantIds + 1] = id end
    table.sort(gotIds); table.sort(wantIds)
    Expect("batch", seed, index, ("items kept with a limit of %d (priority %s)"):format(limit, Ser(priority)), label, wantIds, gotIds)
    Expect("batch", seed, index, "over the limit / dropped", label, { true, wantDropped }, { kover, kdropped })
  end
end

local first, last = 1, N
if ONLY then
  -- one seed reruns exactly that scenario of whichever model it belongs to
  if ONLY >= 7100000 and ONLY < 7200000 then first, last = ONLY - 7100000, ONLY - 7100000 else first, last = 0, -1 end
end
for i = first, last do
  totals.batchScenarios = totals.batchScenarios + 1
  CheckBatch(7100000 + i, i)
end

-- deterministic batch cases by hand
do
  -- a fractional tie: 7 for 700 and 3 for 300 are both exactly 100 each; 299 for 3 is 99.67 and rounds up to 100 but is the cheapest
  local b = BatchOf({ { item = 5, count = 7, buyout = 700 }, { item = 5, count = 3, buyout = 300 }, { item = 5, count = 3, buyout = 299 } })
  Same(b:Items()[5], "100,3,3,13,0", "99.67 is cheapest (3 items); 100 each is a higher exact price that rounds to the same copper: no next price")
  -- ...and with a dearer listing behind it, production still says 0 for the next price (a documented limitation, reported in the roadmap):
  -- the literal next higher copper price would be 150
  b = BatchOf({ { item = 5, count = 3, buyout = 299 }, { item = 5, count = 1, buyout = 100 }, { item = 5, count = 1, buyout = 150 } })
  Same(b:Items()[5], "100,3,3,5,0", "x is 0 when the next exact price rounds to the cheapest copper, even if a dearer listing exists")
  local e = REF.ExpectBatch({ { item = 5, count = 3, buyout = 299 }, { item = 5, count = 1, buyout = 100 }, { item = 5, count = 1, buyout = 150 } }).items[5]
  Same(e.x, 0, "the model describes production's meaning"); Same(e.xStrict, 150, "...and the literal one")
  -- cents of difference at the largest numbers: 99999999999 / 10000 = 9999999.9999 and 99999999998 / 10000 = 9999999.9998
  b = BatchOf({ { item = 6, count = 10000, buyout = 99999999999 }, { item = 6, count = 10000, buyout = 99999999998 } })
  Same(b:Items()[6], "10000000,10000,2,20000,0", "both round up to 10,000,000 copper; the second is cheaper by an exact fraction")
  -- many repeated records
  local rec = {}
  for i = 1, 5000 do rec[i] = { item = 9, count = 7, buyout = 701 } end
  Same(BatchOf(rec):Items()[9], "101,35000,5000,35000,0", "5000 identical listings: 701 / 7 = 100.14 rounds up to 101")
  -- no valid record, nothing priced
  b = BatchOf({ { item = 1, count = 1, buyout = 0 }, { item = 0, count = 1, buyout = 5 }, { item = 2, count = 0, buyout = 0 } })
  local items, n = b:Items()
  Same(n, 0); Same(next(items), nil); Same(b.noBuyout, 1); Same(b.invalid, 2, "a malformed bid-only record is malformed")
end

---------------------------------------------------------------------------
-- 4. The history and the statistics against the full-history model
---------------------------------------------------------------------------
local function EntryOf(p) return ("%.0f,1,1,1,0"):format(p) end
local function ScanFor(cal, s)
  local items = {}
  for id, p in pairs(s.items) do items[id] = EntryOf(p) end
  local n = 0
  for _ in pairs(s.items) do n = n + 1 end
  return { realm = cal.key:match("^(.-)|"), side = cal.key:match("|(.*)$"), at = s.at, complete = s.complete, cut = s.cut, changed = s.changed,
    read = n, used = n, n = n, items = items }
end

local function Trace(cal, id, upTo)
  local out = {}
  for i = 1, upTo do
    local s = cal.scans[i]
    local mark = (s.cut and "c") or (s.changed and "h") or ""
    local p = s.items[id]
    out[#out + 1] = ("%d%s:%s"):format(s.day, mark, p and tostring(p) or "-")
  end
  local from = math.max(1, #out - 30)
  return (from > 1 and "... " or "") .. table.concat(out, " ", from)
end

-- the model's state as production's decoded string should look
local function ModelView(item)
  local pts, bks = {}, {}
  for _, pt in ipairs(item:Points()) do pts[#pts + 1] = pt.day pts[#pts + 1] = pt.price end
  for _, k in ipairs(item:Buckets()) do
    bks[#bks + 1] = k.b bks[#bks + 1] = k.lo bks[#bks + 1] = k.hi bks[#bks + 1] = k.sum bks[#bks + 1] = k.n
  end
  return { pts, bks }
end

-- every item of the market, production against model, and the invariants of production's strings
local function CompareState(seed, index, cal, upTo, model, lastOp)
  local m = PR.Market(cal.key)
  if not m then Differ("history", seed, index, "the market exists after scan " .. upTo, "", "a market", "nil") return false end
  local ids = {}
  for id in pairs(m.hist or {}) do ids[#ids + 1] = id end
  for id in pairs(model.items) do if not (m.hist and m.hist[id]) then ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local s = m.hist and m.hist[id]
    local it = model.items[id]
    local input = ("market %s item %d, scans 1..%d: %s"):format(cal.key, id, upTo, Trace(cal, id, upTo))
    if not s or not it then
      Differ("history", seed, index, "item " .. id .. " has a history in one and not the other (after scan " .. upTo .. ")", input, it and Ser(ModelView(it)) or "none", s or "none")
      return false
    end
    local pts, bks = H.Decode(s)
    if not pts then Differ("history", seed, index, "a stored history string decodes", input, "decodable", s) return false end
    local want = ModelView(it)
    if not Expect("history", seed, index, ("item %d tiers after scan %d (day %d)"):format(id, upTo, cal.scans[upTo].day), input, want, { pts, bks }) then return false end
    -- invariants of the stored string, from the string and the plain list of what happened
    local bad
    if #pts > H.POINTS * 2 then bad = "more than 7 exact days" end
    if #bks > H.MAX_BUCKETS * 5 then bad = "more than 3 buckets" end
    for i = 1, #pts, 2 do
      if lastOp and pts[i] < lastOp - H.RETAIN_DAYS then bad = "an exact day older than the retention" end
      if it.truth[pts[i]] ~= pts[i + 1] then bad = "an exact day that is not the observed value" end
    end
    local folded = 0
    for i = 1, #bks, 5 do
      if bks[i + 1] > bks[i + 2] then bad = "a bucket with low above high" end
      if bks[i + 3] < bks[i + 1] * bks[i + 4] or bks[i + 3] > bks[i + 2] * bks[i + 4] then bad = "a bucket whose sum is outside n x low .. n x high" end
      folded = folded + bks[i + 4]
      -- a bucket is made of observed days: its low and high are values observed inside its span
      local lo, hi, cnt = nil, nil, 0
      for d, p in pairs(it.truth) do
        if math.floor(d / H.BUCKET_DAYS) == bks[i] then
          cnt = cnt + 1
          if not lo or p < lo then lo = p end
          if not hi or p > hi then hi = p end
        end
      end
      if cnt < bks[i + 4] or not lo or bks[i + 1] < lo or bks[i + 2] > hi then bad = "a bucket that holds more than the days observed in its span" end
    end
    local distinct = 0
    for _ in pairs(it.truth) do distinct = distinct + 1 end
    if #pts / 2 + folded > distinct then bad = "more days kept than were ever observed" end
    if bad then Differ("history", seed, index, "stored string invariant: " .. bad .. " (item " .. id .. ")", input, "holds", s) return false end
  end
  Expect("history", seed, index, "scan days after scan " .. upTo, cal.key, model.scanDays, m.scanDays or {})
  return true
end

local function NowList(cal)
  local d = cal.last
  return { d * D + 900, (d + 1) * D + 5, (d + 3) * D, (d + 7) * D + 86399, (d + 29) * D, (d + 70) * D, (d + 125) * D, math.max(1, d - 3) * D + 40 }
end

local PERIODS = { false, "week", 1, 14, 28, 100, 120, "retained", 0, 121, "month" }
local TRENDS = { false, 2, 3, 7, 14, 28, 120, 1, 0, 121 }
local COMPARES = { "week", 7, 28, "retained", 3 }

local function DropFalse(v) if v == false then return nil end return v end
local function ReasonOf(a, why) if a then return "ok" end return why end

-- the answers of Market.*, production against model, for one item at one time
local function CompareQueries(seed, index, cal, model, key, id, now)
  local input = ("market %s item %d at day %d (+%ds): %s"):format(key, id, math.floor(now / D), now % D, Trace(cal, id, #cal.scans))
  local opt = { market = key, now = now }
  local it = model.items[id]
  local n = 0

  for _, period in ipairs(PERIODS) do
    n = n + 1
    local p = DropFalse(period)
    local got, why = MK.Stats(id, p, opt)
    local want, wwhy = model:Stats(id, p, now)
    local tag = "Stats(" .. tostring(p) .. ")"
    if Expect("stats", seed, index, tag .. " answers or refuses", input, ReasonOf(want, wwhy), ReasonOf(got, why)) and got then
      Expect("stats", seed, index, tag .. " figures", input,
        { want.n, want.scans, want.low, want.high, want.average, want.newest.day, want.newest.price, want.exact, want.limited, want.single, want.from, want.to },
        { got.n, got.scans, got.low, got.high, got.average, got.newest and got.newest.day, got.newest and got.newest.price, got.exact, got.limited, got.single, got.from, got.to })
      -- the raw window behind Stats (History.Window), including `skipped`: how many observed days the buckets that overhang the window hide.
      -- Stats shows that only as the boolean `limited`, so the count itself needs its own comparison (the mutation catalog's
      -- market.history.window-skipped survived until this was added)
      local win, mwin = H.Window(PR.Market(key).hist[id], got.from, got.to), it:Window(got.from, got.to)
      if win and mwin then
        Expect("stats", seed, index, tag .. " raw window", input, { mwin.n, mwin.sum, mwin.lo, mwin.hi, mwin.exact, mwin.skipped },
          { win.n, win.sum, win.lo, win.hi, win.exact, win.skipped })
      else
        Expect("stats", seed, index, tag .. " raw window exists", input, mwin ~= nil, win ~= nil)
      end
      -- where the window begins at or after the oldest exact day nothing was compacted: the answer is the full history's
      local pts = it:Points()
      if pts[1] and got.from >= pts[1].day then
        local truth = it:TruthWindow(got.from, got.to)
        Expect("stats", seed, index, tag .. " equals the full history where nothing was compacted", input,
          { truth.n, truth.lo, truth.hi, math.floor(truth.sum / truth.n + 0.5) }, { got.n, got.low, got.high, got.average })
        Expect("stats", seed, index, tag .. " exact and not limited there", input, { true, false }, { got.exact, got.limited })
      end
      if got.low and got.high and got.low > got.high then Differ("stats", seed, index, tag .. " low is not above high", input, "low <= high", got.low .. ">" .. got.high) end
      if got.average < got.low or got.average > got.high then Differ("stats", seed, index, tag .. " the mean lies between low and high", input, "between", got.average) end
      -- never more days than were observed in the window
      local truth = it:TruthWindow(got.from, got.to)
      if got.n > truth.n then Differ("stats", seed, index, tag .. " counts more days than were observed", input, "<= " .. truth.n, got.n) end
      if not got.basis:find("Not a sale price", 1, true) then Differ("stats", seed, index, tag .. " says what it is", input, "a basis sentence", got.basis) end
    end
  end

  for _, days in ipairs(TRENDS) do
    n = n + 1
    local d = DropFalse(days)
    local got, why = MK.Trend(id, d, opt)
    local want, wwhy = model:Trend(id, d, now)
    local tag = "Trend(" .. tostring(d) .. ")"
    if Expect("trend", seed, index, tag .. " answers or refuses", input, ReasonOf(want, wwhy), ReasonOf(got, why)) and got then
      Expect("trend", seed, index, tag .. " figures", input, { want.direction, want.from, want.to, want.change, want.tenths / 10, want.n, want.fromDay, want.toDay },
        { got.direction, got.from, got.to, got.change, got.percent, got.n, got.fromDay, got.toDay })
      if got.toDay < got.fromDay then Differ("trend", seed, index, tag .. " first day is not after last", input, "ordered", got.fromDay .. ">" .. got.toDay) end
    end
  end

  for _, period in ipairs(COMPARES) do
    n = n + 1
    local got, why = MK.Compare(id, period, opt)
    local want, wwhy = model:Compare(id, period, now)
    local tag = "Compare(" .. tostring(period) .. ")"
    if Expect("compare", seed, index, tag .. " answers or refuses", input, ReasonOf(want, wwhy), ReasonOf(got, why)) and got then
      Expect("compare", seed, index, tag .. " figures", input, { want.current, want.reference, want.relation, want.difference, want.n, want.exact, want.limited },
        { got.current, got.reference, got.relation, got.difference, got.n, got.exact, got.limited })
      Expect("compare", seed, index, tag .. " ratio", input, want.current / want.reference, got.ratio)
    end
  end

  -- the price: the newest scan's cheapest listing, or "unlisted"; the answer holds nothing that looks like a sale
  n = n + 1
  local price, why = MK.Price(id, opt)
  local cur = model.current[id]
  Expect("price", seed, index, "Price answers or refuses", input, cur and "ok" or "unlisted", ReasonOf(price, why))
  if price then
    Expect("price", seed, index, "Price figure", input, cur, price.price)
    for _, k in ipairs({ "sold", "sales", "sale", "volume", "demand", "marketValue" }) do
      if price[k] ~= nil then Differ("price", seed, index, "a listing is never presented as a sale (" .. k .. ")", input, "no such field", tostring(price[k])) end
    end
    if not price.basis:find("not a sale", 1, true) then Differ("price", seed, index, "Price says it is a listing", input, "a basis sentence", price.basis) end
  end

  -- one day at a time: an exact day is returned with its value; nothing is invented for the others
  local days = { math.floor(now / D), model.items[id] and model.items[id]:Newest() or 0 }
  local firstOld = cal.scans[1].day
  local span = math.max(1, math.floor(cal.last - firstOld))
  for k = 0, 6 do days[#days + 1] = cal.last - k * math.max(1, math.floor(span / 7)) end
  for _, day in ipairs(days) do
    if day >= 1 then
      n = n + 1
      local got, owhy = MK.Observed(id, day, opt)
      local want, wwhy = model:Observed(id, day)
      Expect("observed", seed, index, "Observed(" .. day .. ")", input, want and (want.day .. ":" .. want.price) or wwhy, got and (got.day .. ":" .. got.price) or owhy)
      if got and it.truth[day] ~= got.price then Differ("observed", seed, index, "an observed day holds the value observed that day", input, it.truth[day], got.price) end
    end
  end

  n = n + 1
  local series, swhy = MK.Series(id, opt)
  local wantSeries, wswhy = model:Series(id)
  if Expect("series", seed, index, "Series answers or refuses", input, ReasonOf(wantSeries, wswhy), ReasonOf(series, swhy)) and series then
    local gotPoints, gotGroups = {}, {}
    for i, pt in ipairs(series.points) do gotPoints[i] = pt.day .. ":" .. pt.price end
    for i, g in ipairs(series.groups) do gotGroups[i] = Ser(g) end
    local wp, wg = {}, {}
    for i, pt in ipairs(wantSeries.points) do wp[i] = pt.day .. ":" .. pt.price end
    for i, g in ipairs(wantSeries.groups) do
      wg[i] = Ser({ from = g.from, to = g.to, low = g.low, high = g.high, average = g.average, n = g.n })
    end
    Expect("series", seed, index, "Series points", input, wp, gotPoints)
    Expect("series", seed, index, "Series groups", input, wg, gotGroups)
    -- nothing fabricated: every drawn day was observed with that value
    for _, pt in ipairs(series.points) do
      if it.truth[pt.day] ~= pt.price then Differ("series", seed, index, "a drawn point was observed", input, tostring(it.truth[pt.day]), tostring(pt.price)) end
    end
  end
  totals.queries = totals.queries + n
end

local function RunCalendar(seed, index, opt)
  local cal = FX.Calendar(seed, opt)
  c.TwichUIWorkshopDB = nil
  local model = REF.NewMarket(cal.key)
  local lastOp
  for i, s in ipairs(cal.scans) do
    local ok, why = PR.Commit(cal.key, ScanFor(cal, s))
    local mok, mwhy = model:Ingest(s)
    if not Expect("history", seed, index, "scan " .. i .. " (day " .. s.day .. ") accepted or refused", cal.key, mok and "ok" or mwhy, ok and "ok" or why) then return end
    if ok then
      lastOp = math.floor(s.at / D)
      if not CompareState(seed, index, cal, i, model, lastOp) then return end
    end
    totals.scans = totals.scans + 1
  end
  for _, now in ipairs(NowList(cal)) do
    for _, id in ipairs(cal.items) do CompareQueries(seed, index, cal, model, cal.key, id, now) end
    CompareQueries(seed, index, cal, model, cal.key, 999999, now)   -- an item no scan listed
  end
  return cal, model
end

local STYLES = { "mixed", "boundary", "dense", "sparse" }
local hfirst, hlast = 1, N
if ONLY then
  if ONLY >= 7200000 and ONLY < 7300000 then hfirst, hlast = ONLY - 7200000, ONLY - 7200000 else hfirst, hlast = 0, -1 end
end
for i = hfirst, hlast do
  local rng = FX.Rng(7200000 + i)
  totals.calendars = totals.calendars + 1
  RunCalendar(7200000 + i, i, { scans = rng:Int(1, 60), items = rng:Int(1, 5), style = STYLES[i % #STYLES + 1],
    same = rng:Pick({ 0, 0.12, 0.4 }), back = rng:Pick({ 0, 0.04, 0.15 }), cut = rng:Pick({ 0, 0.04, 0.2 }), listed = rng:Pick({ 0.3, 0.85, 1 }) })
end

---------------------------------------------------------------------------
-- 5. Several markets in one saved table never mix
---------------------------------------------------------------------------
local mfirst, mlast = 1, math.max(1, math.floor(N * 0.3))
if ONLY then
  if ONLY >= 7300000 and ONLY < 7400000 then mfirst, mlast = ONLY - 7300000, ONLY - 7300000 else mfirst, mlast = 0, -1 end
end
for i = mfirst, mlast do
  local seed = 7300000 + i
  local cals = FX.Markets(seed, 3, { scans = 14 + i % 14, items = 3, style = STYLES[i % #STYLES + 1] })
  totals.marketSets = totals.marketSets + 1
  c.TwichUIWorkshopDB = nil
  local models = {}
  for k, cal in ipairs(cals) do models[k] = REF.NewMarket(cal.key) end
  local longest = 0
  for _, cal in ipairs(cals) do longest = math.max(longest, #cal.scans) end
  local lastOp = {}
  for s = 1, longest do
    for k, cal in ipairs(cals) do
      local sc = cal.scans[s]
      if sc then
        local ok = PR.Commit(cal.key, ScanFor(cal, sc))
        local mok = models[k]:Ingest(sc)
        Expect("markets", seed, i, "market " .. cal.key .. " scan " .. s .. " accepted", cal.key, mok, ok)
        if ok then lastOp[k] = math.floor(sc.at / D) end
        totals.scans = totals.scans + 1
      end
    end
  end
  -- the saved table holds exactly the three markets, each equal to its own model
  local keys = PR.Keys()
  Expect("markets", seed, i, "three markets saved", "", 3, #keys)
  for k, cal in ipairs(cals) do
    CompareState(seed, i, cal, #cal.scans, models[k], lastOp[k])
    for _, id in ipairs(cal.items) do CompareQueries(seed, i, cal, models[k], cal.key, id, cal.last * D + 900) end
  end
  -- adding scans to market 2 changes nothing in market 1
  local before = Ser(PR.Market(cals[1].key).hist) .. Ser(PR.Market(cals[1].key).scanDays) .. tostring(PR.Market(cals[1].key).at)
  local extra = FX.Calendar(seed + 1, { scans = 6, items = 3, start = cals[2].last + 1 })
  for _, sc in ipairs(extra.scans) do PR.Commit(cals[2].key, ScanFor({ key = cals[2].key }, sc)) end
  local after = Ser(PR.Market(cals[1].key).hist) .. Ser(PR.Market(cals[1].key).scanDays) .. tostring(PR.Market(cals[1].key).at)
  Expect("markets", seed, i, "another market's scans leave this market unchanged", cals[1].key, before, after)
end

---------------------------------------------------------------------------
-- 6. Boundaries and invalid input, by hand
---------------------------------------------------------------------------
do
  -- retention: an exact day exactly 120 days before the newest is kept, 121 is dropped
  local s = H.Add(nil, 100, 5)
  Same(H.Add(s, 220, 6), "100,5;220,6|", "day 100 is 120 days before day 220: kept")
  Same(H.Add(s, 221, 6), "221,6|", "day 100 is 121 days before day 221: dropped")
  -- days 100..107 leave exact days 101..107 and day 100 folded into bucket 3 (days 84..111)
  local fill = nil
  for d = 100, 107 do fill = H.Add(fill, d, 1000 + d) end
  -- an exact day goes when it is older than today - 120: 107 stays on day 227 and goes on day 228
  Same(H.Trim(fill, 227), "107,1107|3,1100,1100,1100,1", "day 107 is exactly 120 days before 227: kept, the six earlier days are older")
  Same(H.Trim(fill, 228), "|3,1100,1100,1100,1", "day 107 is 121 days before 228: dropped")
  -- a bucket goes when its LAST day (111) is older than that: kept on day 231, gone on day 232
  Same(H.Trim(fill, 231), "|3,1100,1100,1100,1", "the bucket's last day (111) is exactly 120 days before 231: kept")
  Same(H.Trim(fill, 232), nil, "...and 121 days before 232: gone, and nothing is left")
  -- unknown prices never become entries
  for _, bad in ipairs({ 0, -1, 1.5, "5", 0 / 0, math.huge, 100000000000, false }) do
    local r, why = H.Add(nil, 100, bad)
    Same(r, nil, "price " .. tostring(bad)); Same(why, "bad")
  end
  c.TwichUIWorkshopDB = nil
  local scan = { realm = "Realm", side = "Alliance", at = 100 * D + 5, complete = true, read = 9, used = 9, n = 9, items = {
    [1] = "0,1,1,1,0", [2] = "x", [3] = 5, [4] = "99999999999999,1,1,1,0", [5] = "-5,1,1,1,0", [6] = "7,1,1,1,0", [0] = "9,1,1,1,0", [-3] = "9,1,1,1,0",
    [1.5] = "9,1,1,1,0", [2147483648] = "9,1,1,1,0" } }
  Check(PR.Commit("Realm|Alliance", scan))
  local m = PR.Market("Realm|Alliance")
  local ids = {}
  for id in pairs(m.hist) do ids[#ids + 1] = id end
  Same(table.concat(ids, ","), "6", "only the one well-formed price became a history entry")
  -- a clock that moves backwards is ignored, and an empty market has no answers
  c.TwichUIWorkshopDB = nil
  Check(PR.Commit("Realm|Alliance", { realm = "Realm", side = "Alliance", at = 200 * D, complete = true, items = { [6] = "50,1,1,1,0" } }))
  Check(PR.Commit("Realm|Alliance", { realm = "Realm", side = "Alliance", at = 190 * D, complete = true, items = { [6] = "10,1,1,1,0" } }))
  Same(PR.Market("Realm|Alliance").hist[6], "200,50|", "a scan dated earlier changes no history")
  Same(select(2, MK.Stats(6, "week", { market = "Realm|Nowhere", now = 200 * D })), "nomarket", "an unknown market has no statistics")
  Same(select(2, MK.Trend(6, 7, { market = "Realm|Alliance", now = 200 * D })), "insufficient", "one day is no trend")
  Same(select(2, MK.Compare(6, "week", { market = "Realm|Alliance", now = 200 * D })), "insufficient", "no earlier day, no reference")
  c.TwichUIWorkshopDB = nil
end

---------------------------------------------------------------------------
-- 6b. NaN and infinity in a record (testing roadmap M5.1). The first real-client Test Lab run (2026-11-12) found the REFERENCE MODEL counting a
--     NaN count as valid for seeds 7100008 and 7100012, because it decided NaN by comparing (`v == v ...`) and the client's comparisons do not
--     reject a NaN the way desktop Lua 5.1 does. The model now decides finiteness without a comparison (REF.Finite). Desktop Lua cannot
--     reproduce the client's NaN comparisons, so these tests pin the CONTRACT (what each value must be read as) and that the two failing seeds
--     still draw NaN fields, so the regression keeps its teeth.
---------------------------------------------------------------------------
do
  local nan, inf = 0 / 0, math.huge
  -- finiteness: numbers that print as digits only
  for _, v in ipairs({ 0, 1, -1, 1.5, 99999999999, 2 ^ 53, 1e300, -1e300, 4102444800 }) do Check(REF.Finite(v), "finite: " .. tostring(v)) end
  for _, v in ipairs({ nan, -nan, nan * -1, inf, -inf }) do Check(not REF.Finite(v), "not finite: " .. tostring(v)) end
  for _, v in ipairs({ "5", false, true, {} }) do Check(not REF.Finite(v), "not a number: " .. type(v)) end
  Check(not REF.Finite(nil), "nil is not finite")
  -- whole numbers in range: the limits are in, one past is out, fractions and the non-finite are out
  Check(REF.Whole(1, 1, 10000) and REF.Whole(10000, 1, 10000) and not REF.Whole(0, 1, 10000) and not REF.Whole(10001, 1, 10000), "count limits")
  Check(not REF.Whole(2.5, 1, 10000) and not REF.Whole(nan, 1, 10000) and not REF.Whole(inf, 1, 10000) and not REF.Whole(-inf, 0, 99999999999), "fraction, NaN, infinity")
  Check(REF.Whole(99999999999, 0, 99999999999) and not REF.Whole(100000000000, 0, 99999999999), "buyout limit")
  -- the probe prints primitives and the decision, for a NaN too, and never raises
  local probe = REF.NumberProbe(nan, 1, 10000)
  Check(probe:find("finite=F", 1, true) and probe:find("whole=F", 1, true) and probe:find("eq_self=", 1, true), "the probe reports a NaN: " .. probe)
  Same(REF.NumberProbe("x", 1, 2), "type string", "and says what a non-number is")

  -- by hand: records of ONE item. 5 at 10 (2 each), a NaN count at 5 (invalid, NOT priced: it would be the cheapest), 3 with no buyout.
  local recs = { { item = 7, count = 2, buyout = 10 }, { item = 7, count = nan, buyout = 5 }, { item = 7, count = 3, buyout = 0 },
    { item = 7, count = 4, buyout = nan }, { item = nan, count = 4, buyout = 0 }, { item = 7, count = inf, buyout = 0 } }
  local e = REF.ExpectBatch(recs)
  Same(e.used, 1, "one record is priced"); Same(e.noBuyout, 1, "one is bid-only"); Same(e.invalid, 4, "the NaN count, the NaN buyout, the NaN item and the infinite count are invalid")
  Same(REF.EntryText(e.items[7]), "5,2,1,2,0", "the NaN record is not the cheapest: 10 for 2 is 5 each, one listing of two items")
  local b = PR.NewBatch()
  for _, r in ipairs(recs) do b:Add(r.item, r.count, r.buyout, r.info) end
  Same(b.used, 1); Same(b.noBuyout, 1); Same(b.invalid, 4)
  Same(select(1, b:Items())[7], "5,2,1,2,0", "production reads the same record the same way")

  -- the two seeds that failed in the client still draw a NaN where it matters (a count, with a buyout of 0 in one and above 0 in the other)
  for _, k in ipairs({ { 8, 0 }, { 12, 1 } }) do
    local seed = 7100000 + k[1]
    local gen = FX.Listings(seed, { items = 3, records = 30 + k[1], tiers = 1 + k[1] % 3 })
    local hit = 0
    for _, r in ipairs(gen.records) do
      if type(r.count) == "number" and r.count ~= r.count and (r.buyout == 0) == (k[2] == 0) then hit = hit + 1 end
    end
    Check(hit >= 1, "seed " .. seed .. " draws a NaN count " .. (k[2] == 0 and "with no buyout" or "with a buyout"))
    local m, got = REF.ExpectBatch(gen.records), PR.NewBatch()
    for _, r in ipairs(gen.records) do got:Add(r.item, r.count, r.buyout, r.info) end
    Same(got.used, m.used, "seed " .. seed .. " used"); Same(got.noBuyout, m.noBuyout, "seed " .. seed .. " bid-only"); Same(got.invalid, m.invalid, "seed " .. seed .. " invalid")
  end
  -- and the client's own numbers for them, from the report: seed 7100008 has 4 bid-only and 6 invalid records, seed 7100012 has 33 used and 2 invalid
  local g8 = REF.ExpectBatch(FX.Listings(7100008, { items = 3, records = 38, tiers = 3 }).records)
  Same(g8.noBuyout, 4); Same(g8.invalid, 6)
  local g12 = REF.ExpectBatch(FX.Listings(7100012, { items = 3, records = 42, tiers = 1 }).records)
  Same(g12.used, 33); Same(g12.invalid, 2)
end

---------------------------------------------------------------------------
-- 6c. NON-FINITE AUCTION DATA IN PRODUCTION (Test Lab run 2026-11-12, WoW: Forever 1.60.1 build 70888; seeds 7100001, 7100013, 7100014).
--     FOUND: `market.reference.batch` and `market.reference.invalid-values` failed because Batch:Add tested `raw == 0` (bid-only) BEFORE any
--     finiteness check, and in that client a NaN equals 0, equals itself, and is both less and greater than ordinary numbers; so a NaN buyout
--     was counted as bid-only instead of invalid. FIX: W.Finite (Data.lua) decides finiteness from the printed form, without a comparison,
--     and runs first in W.Int, Batch:Add and History.
--     Desktop Lua 5.1 cannot reproduce those comparisons (its NaN is never == 0), so a plain NaN test proves only the CONTRACT. The EMULATION
--     below proves the DECISION ORDER: while `tostring` is made to print "nan" for every number, a value whose comparisons look ordinary (0,
--     a good count, a good item) must still be read as invalid, because production may consult only the printed form of a number it has not
--     yet shown to be finite. That is what a NaN that compares equal to 0 looks like to the code. The client run (Test Lab) is the final proof.
---------------------------------------------------------------------------
do
  local nan, inf = 0 / 0, math.huge
  local realToString = c.tostring or tostring
  local function AsNaN(which, fn)   -- run fn while the numbers in `which` (a set) print as a NaN; every comparison stays ordinary
    c.tostring = function(v) if type(v) == "number" and which[v] then return "nan" end return realToString(v) end
    local ok, err = pcall(fn)
    c.tostring = nil
    if not ok then error(err, 0) end
  end
  local function Run(recs)
    local b = PR.NewBatch()
    for _, r in ipairs(recs) do b:Add(r.item, r.count, r.buyout, r.info) end
    return b
  end
  local function One(item, count, buyout)
    local b = Run({ { item = item, count = count, buyout = buyout } })
    return (b.used == 1 and "priced") or (b.noBuyout == 1 and "bid-only") or (b.invalid == 1 and "invalid") or "unaccounted"
  end

  -- W.Finite: the contract
  for _, v in ipairs({ 0, -0, 1, -1, 0.5, 99999999999, 2 ^ 53, 1e300, -1e300, 4102444800 }) do Check(W.Finite(v), "finite: " .. tostring(v)) end
  for _, v in ipairs({ nan, -nan, nan * -1, 0 / 0 * -1, inf, -inf, inf - inf, inf * 0 }) do Check(not W.Finite(v), "not finite: " .. tostring(v)) end
  for _, v in ipairs({ "5", "nan", "inf", false, true, {}, print }) do Check(not W.Finite(v), "not a number: " .. type(v)) end
  Check(not W.Finite(nil), "nil is not finite")
  Check(W.Int(nan, 1, 10) == nil and W.Int(inf, 1, 10) == nil and W.Int(-inf, -10, 10) == nil and W.Int(0 / 0 * -1, 0, 10) == nil, "Int refuses NaN and infinities")
  Check(W.Int(0, 0, 10) == 0 and W.Int(10, 0, 10) == 10 and W.Int(2.5, 0, 10) == nil and W.Int("3", 0, 10) == nil, "Int still reads ordinary numbers as before")

  -- the batch, one field at a time (real values)
  Same(One(7, 5, 0), "bid-only", "a finite zero buyout is bid-only"); Same(One(7, 5, -0), "bid-only", "negative zero is a finite zero")
  Same(One(7, 5, nan), "invalid", "a NaN buyout is invalid"); Same(One(7, 5, -nan), "invalid", "a negated NaN buyout is invalid")
  Same(One(7, 5, 0 / 0 * -1), "invalid", "a NaN made negative is invalid")
  Same(One(7, 5, inf), "invalid", "a positive infinite buyout is invalid"); Same(One(7, 5, -inf), "invalid", "a negative infinite buyout is invalid")
  Same(One(7, 5, -1), "invalid", "a negative buyout is invalid"); Same(One(7, 5, "100"), "invalid", "a string buyout is invalid")
  Same(One(7, 5, 100.5), "invalid", "a fractional buyout is invalid"); Same(One(7, 5, nil), "invalid", "a missing buyout is invalid")
  Same(One(7, 5, 100000000000), "invalid", "a buyout past the limit is invalid"); Same(One(7, 5, 99999999999), "priced", "the limit itself is priced")
  Same(One(7, nan, 100), "invalid", "a NaN count is invalid"); Same(One(7, nan, 0), "invalid", "a NaN count with no buyout is invalid, not bid-only")
  Same(One(7, inf, 100), "invalid", "an infinite count is invalid"); Same(One(7, 0, 0), "invalid", "a zero count is invalid, not bid-only")
  Same(One(nan, 5, 100), "invalid", "a NaN item is invalid"); Same(One(nan, 5, 0), "invalid", "a NaN item with no buyout is invalid, not bid-only")
  Same(One(-inf, 5, 100), "invalid", "an infinite item is invalid"); Same(One(0, 5, 100), "invalid", "item 0 is invalid")

  -- the emulation: ONE field is a "NaN" (prints as one, compares as an ordinary number, e.g. equal to 0); the other fields are good
  AsNaN({ [0] = true }, function()
    Same(One(7, 5, 0), "invalid", "a buyout that prints as NaN is invalid, NOT bid-only, whatever it compares equal to")
  end)
  AsNaN({ [4242] = true }, function()
    Same(One(7, 5, 4242), "invalid", "a buyout that prints as NaN is not priced even if it compares as a good number")
    Same(One(7, 5, 4243), "priced", "(its neighbour is)")
  end)
  AsNaN({ [99999999999] = true }, function() Same(One(7, 5, 99999999999), "invalid", "...at the limit too") end)
  AsNaN({ [5] = true }, function()
    Same(One(7, 5, 100), "invalid", "a good count that prints as NaN is invalid")
    Same(One(7, 5, 0), "invalid", "...with no buyout it is invalid, not bid-only")
  end)
  AsNaN({ [7] = true }, function()
    Same(One(7, 5, 100), "invalid", "a good item that prints as NaN is invalid")
    Same(One(7, 5, 0), "invalid", "...with no buyout it is invalid, not bid-only")
    local b = Run({ { item = 7, count = 5, buyout = 100 }, { item = 7, count = 5, buyout = 0 } })
    Same(b.read, 2); Same(b.invalid, 2); Same(b.used, 0); Same(b.noBuyout, 0)
    Check(next((b:Items())) == nil, "nothing is priced")
  end)
  AsNaN({ [150] = true }, function() Check(H.Add(nil, 150, 1000) == nil, "History refuses a day that prints as NaN") end)
  AsNaN({ [1000] = true }, function() Check(H.Add(nil, 150, 1000) == nil, "History refuses a price that prints as NaN") end)
  AsNaN({ [1000000] = true }, function() Check(H.Day(1000000) == nil, "History.Day refuses a time that prints as NaN") end)
  Same(One(7, 5, 0), "bid-only", "with real printing restored, a zero buyout is bid-only again")

  -- accounting: valid, bid-only and invalid records add up, and only the valid ones are priced
  local recs = {
    { item = 7, count = 2, buyout = 10 }, { item = 7, count = 4, buyout = 12 },     -- priced: 5 and 3 each, so 3 is the cheapest
    { item = 7, count = 3, buyout = 0 }, { item = 8, count = 1, buyout = 0 },       -- bid-only
    { item = 7, count = 1, buyout = nan }, { item = 7, count = 1, buyout = -nan }, { item = 7, count = 1, buyout = inf },
    { item = 7, count = 1, buyout = -inf }, { item = 7, count = nan, buyout = 1 }, { item = nan, count = 1, buyout = 1 },
    { item = 7, count = 1, buyout = -5 }, { item = 7, count = 1, buyout = "9" },   -- invalid
    { item = 8, count = 2, buyout = 50 },                                           -- priced
  }
  local b = Run(recs)
  Same(b.read, 13); Same(b.used, 3); Same(b.noBuyout, 2); Same(b.invalid, 8)
  Same(b.read, b.used + b.noBuyout + b.invalid, "every record is accounted for exactly once")
  local items, n = b:Items()
  Same(n, 2); Same(items[7], "3,4,2,6,5", "item 7: 12 for 4 is 3 each (4 items), one other listing at 5; the invalid records changed nothing")
  Same(items[8], "25,2,1,2,0", "item 8: 50 for 2 is 25 each; its bid-only record is not a price")
  -- the same valid listings alone give identical results
  local only = Run({ recs[1], recs[2], recs[13] })
  local i2 = only:Items()
  Same(i2[7], items[7]); Same(i2[8], items[8])
end

---------------------------------------------------------------------------
-- 7. KNOWN GAPS: what production does today in three corners the contract does not settle (docs/workshop/testing-roadmap.md, "M2 findings").
--    These are CHARACTERIZATION tests: they pin the current behaviour so a change is a conscious one, not a statement that it is right.
---------------------------------------------------------------------------
do
  local KEY = "Realm|Alliance"
  local function Sc(day, map)
    local items = {}
    for id, p in pairs(map) do items[id] = EntryOf(p) end
    return { realm = "Realm", side = "Alliance", at = day * D + 10, complete = true, items = items }
  end
  c.TwichUIWorkshopDB = nil
  local model = REF.NewMarket(KEY)
  for d = 100, 107 do PR.Commit(KEY, Sc(d, { [1] = 1000 + d, [2] = 5 })) model:Ingest({ at = d * D + 10, complete = true, items = { [1] = 1000 + d, [2] = 5 } }) end
  PR.Commit(KEY, Sc(228, { [2] = 5 })); model:Ingest({ at = 228 * D + 10, complete = true, items = { [2] = 5 } })
  Same(PR.Market(KEY).hist[1], "|3,1100,1100,1100,1", "item 1 was not listed for 121 days: the exact days expired, the bucket (day 100) stayed")
  Same(Ser(ModelView(model.items[1])), Ser({ {}, { 3, 1100, 1100, 1100, 1 } }), "the model agrees about that state")

  -- GAP 1 (stale): a scan dated BEFORE the observation the bucket holds. History.lua says an observation older than the newest one kept is
  -- ignored; with no exact day left, production has nothing to compare with and accepts day 90 beside a bucket holding day 100.
  PR.Commit(KEY, Sc(90, { [1] = 77, [2] = 5 }))
  Same(PR.Market(KEY).hist[1], "90,77|3,1100,1100,1100,1", "CURRENT BEHAVIOUR: day 90 is accepted although day 100 was observed (the reference model refuses it as stale)")
  Same(select(2, model.items[1]:Observe(90, 77)), "stale", "the contract's reading")

  -- GAP 2 (newest in a bucket): with only buckets left, the "newest" day is the last day of the newest bucket's 28-day span (111), which no
  -- scan observed (the observed day was 100), and it has no price.
  c.TwichUIWorkshopDB = nil
  for d = 100, 107 do PR.Commit(KEY, Sc(d, { [1] = 1000 + d, [2] = 5 })) end
  PR.Commit(KEY, Sc(228, { [2] = 5 }))
  local st = MK.Stats(1, "retained", { market = KEY, now = 228 * D })
  Same(st.newest.day, 111, "CURRENT BEHAVIOUR: the newest day reported is the bucket's last calendar day, not an observed one"); Same(st.newest.price, nil)

  -- GAP 3 (Trend has no upper bound): Stats counts the days up to now; Trend counts every exact day from the window's first day on, so with
  -- a clock (or an opt.now) set before the newest observation it also counts days AFTER now.
  c.TwichUIWorkshopDB = nil
  for d = 100, 110 do PR.Commit(KEY, Sc(d, { [1] = 1000 + d })) end
  local tr = MK.Trend(1, 3, { market = KEY, now = 102 * D })
  Check(tr and tr.n == 7 and tr.fromDay == 104 and tr.toDay == 110, "CURRENT BEHAVIOUR: a 3-day trend 'as of day 102' covers days 104..110")
  Same(select(2, MK.Stats(1, 3, { market = KEY, now = 102 * D })), "nodata", "...while Stats for the same window finds no day")
  c.TwichUIWorkshopDB = nil
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
if #found > 0 then
  print(("%d difference(s) found:"):format(#found))
  for i = 1, math.min(#found, 12) do print(found[i]) end
  error(("%d differences between the reference models and the production code (MARKET_ALL listed them)"):format(#found), 0)
end
print(("market reference models: %d batch houses (%d records; %d with a next price the literal reading would fill), %d calendars, %d market sets, %d scans compared, %d queries compared, %.1f s"):format(
  totals.batchScenarios, totals.records, strictDiffers, totals.calendars, totals.marketSets, totals.scans, totals.queries, os.clock() - clock0))
print("PASSED")
