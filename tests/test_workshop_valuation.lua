-- Market data foundation 2.0, milestone A5 (docs/workshop/market-data-foundation-v2.md, "A5 as built"): the valuation services.
--   1. the arithmetic on its own (weighted median and its half boundary, bucket shares, spread classes, percentages);
--   2. hand-worked cases for every example of the brief: Market Value, Historical Value (buckets, nr weights, window edges), Range (legacy join),
--      Distribution, Data Quality, Supply, TrendOf, Posture (85% / 115% with large copper), Competition, Cost (every edge case);
--   3. layouts of days and buckets queried at many different times, against the independent models (TwichUI_TestLab/Reference.lua section 7);
--   4. the cache: hits, a scan, a day rollover, time-dependent quality, a replaced database, a second market, the bound;
--   5. read-only: the saved data is deep-equal after every call, and a caller changing a result changes nothing;
--   6. the old minimum-based API answers exactly as without Valuation.lua;
--   7. seeded markets through the real commit pipeline (two markets interleaved), every service against the models.
-- Synthetic data only; offline logic only.
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local function Ser(v)
  local t = type(v)
  if t == "number" then return ("%.17g"):format(v) end
  if t == "string" then return ("%q"):format(v) end
  if t == "boolean" or t == "nil" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) if type(a) ~= type(b) then return type(a) < type(b) end return a < b end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = "[" .. Ser(k) .. "]=" .. Ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
local function Clone(v) return assert(loadstring("return " .. Ser(v)))() end   -- test-only: the text is this file's own output

local CORE = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua",
  "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua" }
local LAB = ROOT .. "../TwichUI_TestLab/"

local function Setup(db, without)
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = c.TwichUIDB or {}
  c.GetRealmName = function() return "Realm" end
  c.TwichUIWorkshopDB = db
  local files = {}
  for _, f in ipairs(CORE) do files[#files + 1] = f end
  if not without then files[#files + 1] = "Valuation.lua" end
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  for _, f in ipairs({ "Fixtures.lua", "Reference.lua" }) do
    local chunk = assert(loadfile(LAB .. f), f); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
  end
  return { c = c, W = c.TwichUI.Workshop, TL = c.TwichUI.TestLab, DB = function() return c.TwichUIWorkshopDB end }
end

local base = Setup(nil)
local W, V, H2, REF, FX = base.W, base.W.Valuation, base.W.History2, base.TL.Reference, base.TL.Fixtures
local DAY = 86400
local D0 = 20000
local KEY, KEY2 = "Realm|Alliance", "Realm|Horde"
local function At(day, hour, min) return day * DAY + (hour or 0) * 3600 + (min or 0) * 60 end

-- a daily point (closing values; ranges equal to them unless given) and a bucket, as History2.Encode takes them
local function Dp(d, r, o)
  o = o or {}
  local p = o.p or (r and math.min(r, 50) or 50)
  local t, l = o.t or 10, o.l or 3
  return { d = d, p = p, r = r, t = t, l = l, n = o.n or 1, plo = o.plo or p, phi = o.phi or p, rlo = o.rlo or r, rhi = o.rhi or r, tlo = o.tlo or t, thi = o.thi or t, pf = o.pf }
end
local function Bk(k, s, n, nr, rm, o)
  o = o or {}
  local pm = o.pm or 50
  return { k = k, s = s, n = n, nr = nr, plo = o.plo or pm, pm = pm, phi = o.phi or pm, rm = nr > 0 and rm or nil, rlo = nr > 0 and (o.rlo or rm) or nil,
    rhi = nr > 0 and (o.rhi or rm) or nil, tm = o.tm or 10, tlo = o.tlo or (o.tm or 10), thi = o.thi or (o.tm or 10), lm = 3 }
end

-- A saved format 3 market written straight into the database (the snapshot built by the real batch from listings { { unit, count } ... })
local function RawMarket(t, key, o)
  local PR, H2t = t.W.Prices, t.W.History2
  local b = PR.NewBatch()
  local ids = {}
  for id in pairs(o.listings or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do for _, x in ipairs(o.listings[id]) do b:Add(id, x[2], x[1] * x[2], true) end end
  local items, n, _, _, dist = b:Items()
  local m = { f = 3, scope = "full", realm = "Realm", side = key:match("|(.*)$"), at = o.at, complete = o.complete ~= false, cut = o.cut,
    read = 1, used = 1, partial = o.partial or 0, n = n, items = items, hist = o.hist or {}, hn = 0, sd = {},
    snap = { seq = o.seq or 1, kind = "full", at = o.snapAt or o.at, alg = (not o.noDist) and 1 or nil, records = 1, used = 1, partial = o.partial or 0, items = n },
    dist = (not o.noDist) and dist or nil, h2 = {}, c2 = {}, scans = {}, days = {}, v2from = o.from or 1,
    h2info = o.h2info or { v = 1, from = o.from or 1, at = o.at } }
  for id, list in pairs(o.days or {}) do
    local h, c = H2t.Encode(o.ring and o.ring[id] or {}, list, o.buckets and o.buckets[id])
    m.h2[id], m.c2[id] = h, c
  end
  for id, bl in pairs(o.buckets or {}) do
    if not (o.days and o.days[id]) then local _, c = H2t.Encode(nil, nil, bl) m.c2[id] = c end
  end
  for id, s in pairs(o.rawh2 or {}) do m.h2[id] = s end
  for id, s in pairs(o.rawdist or {}) do m.dist[id] = s end
  t.c.TwichUIWorkshopDB = t.c.TwichUIWorkshopDB or { v = 2, markets = {} }
  t.c.TwichUIWorkshopDB.markets[key] = m
  return m
end

local function Fresh() local t = Setup(nil) t.c.TwichUIWorkshopDB = { v = 2, markets = {} } return t end
local function Opt(now, extra) local o = { market = KEY, now = now } for k, v in pairs(extra or {}) do o[k] = v end return o end
local function Has(list, code) for _, c in ipairs(list or {}) do if c == code then return true end end return false end

---------------------------------------------------------------------------
-- 1. The arithmetic
---------------------------------------------------------------------------
do
  local function WM(pairsList)
    local vs, ws = {}, {}
    for i, p in ipairs(pairsList) do vs[i], ws[i] = p[1], p[2] end
    return V.WeightedMedian(vs, ws, #pairsList)
  end
  Same(WM({ { 100, 4 }, { 200, 2 }, { 300, 2 } }), 100, "cumulative weight exactly half the total reaches the median (4 of 8)")
  Same(WM({ { 100, 3 }, { 200, 2 }, { 300, 2 } }), 200, "3 of 7 does not reach half")
  Same(WM({ { 300, 1 }, { 100, 1 }, { 200, 1 }, { 400, 1 } }), 200, "an even count gives the lower median")
  Same(WM({ { 500, 4 }, { 500, 1 }, { 700, 2 } }), 500, "equal values with different weights")
  Same(WM({ { 99999999999, 1 }, { 99999999998, 1 }, { 99999999997, 1 } }), 99999999998, "large copper")
  Same(V.MarketWeight(0), 4) Same(V.MarketWeight(2), 4) Same(V.MarketWeight(3), 2) Same(V.MarketWeight(6), 2) Same(V.MarketWeight(7), 1) Same(V.MarketWeight(13), 1)
  local ov, used = V.BucketUse(100, 106, 103, 200) Same(ov, 4) Same(used, true, "4 of 7 days inside")
  ov, used = V.BucketUse(100, 106, 104, 200) Same(ov, 3) Same(used, false, "3 of 7 days inside")
  ov, used = V.BucketUse(100, 113, 107, 200) Same(ov, 7) Same(used, true, "7 of 14: half")
  ov, used = V.BucketUse(100, 113, 108, 200) Same(used, false, "6 of 14")
  ov, used = V.BucketUse(100, 106, 107, 200) Same(ov, 0) Same(used, false)
  ov, used = V.BucketUse(100, 106, 90, 103) Same(ov, 4) Same(used, true, "the upper edge counts the same way")
  Same(V.SpreadClass(1000, 1000, 1099), "tight") Same(V.SpreadClass(1000, 1000, 1100), "moderate", "10% is moderate")
  Same(V.SpreadClass(1000, 1000, 1299), "moderate") Same(V.SpreadClass(1000, 1000, 1300), "wide", "30% is wide")
  for _, c in ipairs({ { 1000, 900 }, { 2000, 1999 }, { 2000, 2001 }, { 1, 99999999999 }, { 99999999999, 1 }, { 3, 7 } }) do
    Same(V.PercentTenths(c[1], c[2]), REF.PercentTenths(c[1], c[2]), "percent " .. c[1] .. " -> " .. c[2])
  end
end

---------------------------------------------------------------------------
-- 2a. Market Value: the 14-day recency-weighted median, by hand
---------------------------------------------------------------------------
do
  local T = D0 + 20
  local now = At(T, 12)
  local t = Fresh()
  local MK = t.W.Market
  local function Ages(list) local out = {} for _, a in ipairs(list) do out[#out + 1] = Dp(T - a[1], a[2]) end return out end   -- oldest first
  local cases = {
    { "one observed day", { { 0, 1200 } }, 1200, 1, 4 },
    { "two days, the newer weighs more", { { 5, 2000 }, { 0, 1000 } }, 1000, 2, 6 },
    { "two days, a newer high value", { { 10, 1000 }, { 0, 2000 } }, 2000, 2, 5 },
    -- seven days: ages 0..2 weigh 4, 3..6 weigh 2: 100(2) 200(2) 300(2) 400(2) 500(4): 12 of 20 at 500 (the plain median would be 400)
    { "seven days", { { 6, 100 }, { 5, 200 }, { 4, 300 }, { 3, 400 }, { 2, 500 }, { 1, 600 }, { 0, 700 } }, 500, 7, 20 },
    -- fourteen days r = 1000 + 10 x age: weights 12 + 8 + 7 = 27, cumulative 4, 8, 12, 14 >= 13.5 at 1030
    { "fourteen days", (function() local l = {} for a = 13, 0, -1 do l[#l + 1] = { a, 1000 + 10 * a } end return l end)(), 1030, 14, 27 },
    { "gaps in the newest three days", { { 13, 900 }, { 10, 900 }, { 8, 900 }, { 7, 900 }, { 6, 500 }, { 5, 500 }, { 4, 500 }, { 3, 500 } }, 500, 8, 12 },
    { "a one-day spike", (function() local l = {} for a = 13, 1, -1 do l[#l + 1] = { a, 1000 } end l[#l + 1] = { 0, 100000 } return l end)(), 1000, 14, 27 },
    { "a one-day crash", (function() local l = {} for a = 13, 1, -1 do l[#l + 1] = { a, 1000 } end l[#l + 1] = { 0, 10 } return l end)(), 1000, 14, 27 },
    { "equal values, different weights", { { 10, 500 }, { 4, 700 }, { 0, 500 } }, 500, 3, 7 },
    { "an exact half-weight boundary", { { 5, 300 }, { 3, 200 }, { 0, 100 } }, 100, 3, 8 },
    { "large copper", { { 1, 99999999999 }, { 0, 99999999998 } }, 99999999998, 2, 8 },
  }
  local days = {}
  for i, cs in ipairs(cases) do days[i] = Ages(cs[2]) end
  -- 20: three scans on day T (closing 1100, the day's low 600): the closing value votes, nothing else
  local h = H2.Update(nil, nil, H2.Obs(At(T, 8), 900, 1000, 100, 10), { T = T, M = math.floor(At(T, 8) / 60) })
  h = H2.Update(h, nil, H2.Obs(At(T, 9), 500, 600, 70, 8), { T = T, M = math.floor(At(T, 9) / 60), prevM = math.floor(At(T, 8) / 60) })
  h = H2.Update(h, nil, H2.Obs(At(T, 10), 1000, 1100, 120, 12), { T = T, M = math.floor(At(T, 10) / 60), prevM = math.floor(At(T, 9) / 60) })
  RawMarket(t, KEY, { at = At(T, 10), days = days, from = T - 40,
    rawh2 = { [20] = h, [21] = "garbage", [22] = H2.Encode({}, { Dp(T - 3, nil), Dp(T - 1, nil) }), [23] = H2.Encode({}, { Dp(T - 20, 500), Dp(T - 15, 500) }) },
    hist = { [24] = "19990,300;19991,310" } })
  for i, cs in ipairs(cases) do
    local v = assert(MK.Value(i, "market", Opt(now)), cs[1])
    Same(v.value, cs[3], cs[1] .. ": value") Same(v.n, cs[4], cs[1] .. ": observed days") Same(v.weight, cs[5], cs[1] .. ": total weight")
    Same(v.role, "valuation") Same(v.kind, "market") Same(v.aggregate, false) Same(v.evidence, "daily") Same(v.window.days, 14) Same(v.window.from, T - 13)
    Check(v.basis:find("observed auction house listings", 1, true) and v.basis:find("not a sale price", 1, true), "basis: listings, not sales")
    -- the reference model reads the same days off an expanded list
    local ref = REF.VMarketValue({ days = days[i], buckets = {} }, T)
    Same(ref.v, cs[3], cs[1] .. ": the model agrees") Same(ref.weight, cs[5])
  end
  local one = MK.Value(1, "market", Opt(now))
  Same(one.quality, "limited", "a single observed day is at most limited") Check(Has(one.notes, "singleday"))
  Same(MK.Value(20, "market", Opt(now)).value, 1100, "several scans in a day: only the day's closing Recent Price votes")
  Same(select(2, MK.Value(21, "market", Opt(now))), "malformed")
  local _, why, detail = MK.Value(22, "market", Opt(now))
  Same(why, "norecent", "observed days without a Recent Price vote nothing (never the minimum)") Same(detail.listed, 2)
  Same(select(2, MK.Value(23, "market", Opt(now))), "stale", "nothing in the last 14 days")
  Same(select(2, MK.Value(24, "market", Opt(now))), "nohistory", "legacy minimum history never feeds Market Value")
  Same(select(2, MK.Value(99, "market", Opt(now))), "nohistory")
  -- UTC day boundaries: one second before midnight of day T the day-T point is in the future (not counted) and ages shift by one
  local before = assert(MK.Value(2, "market", Opt(At(T, 0) - 1)))
  Same(before.n, 1, "the day-T observation is after 'now'") Same(before.value, 2000)
  Same(MK.Value(2, "market", Opt(At(T, 0))).n, 2)
  -- 14 days exactly: age 13 counts, age 14 does not
  Same(MK.Value(5, "market", Opt(At(T + 1, 0))).n, 13, "a day later the oldest of the fourteen leaves the window")
  Same(select(2, MK.Value(1, "nonsense", Opt(now))), "badkind")
  Same(select(2, MK.Value(1, "market", Opt(now, { variant = true }))), "variant")
  Same(select(2, MK.Value(1, "market", { market = "Realm|Nowhere", now = now })), "nomarket")
  Same(select(2, MK.Value(1, "market", Opt(now, { sources = { "legacy" } }))), "badsource")
  Same(select(2, MK.Value(0, "market", Opt(now))), "baditem")
  -- a later history format is never read
  t.c.TwichUIWorkshopDB.markets[KEY].h2info = { v = 2, from = T - 40, at = At(T, 10) }
  Same(select(2, MK.Value(1, "market", Opt(now))), "format")
end

---------------------------------------------------------------------------
-- 2b. Historical Value: the 60-day median, buckets by their mean weighted by nr, window edges
---------------------------------------------------------------------------
do
  -- T chosen so the weekly bucket k = 2860 (days 20020..20026) has 3 of its days inside the 60-day window at T and 4 at T - 1
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  local days = {
    [1] = { Dp(T - 9, 100), Dp(T - 5, 300), Dp(T - 1, 200) },                                -- exactly three days: median 200
    [2] = { Dp(T - 9, 100), Dp(T - 5, 300) },                                                -- two: insufficient
    [3] = { Dp(T - 20, 400), Dp(T - 15, 100), Dp(T - 12, 300), Dp(T - 9, 200), Dp(T - 5, 500), Dp(T - 1, 600) },   -- daily only: lower median 300
    [4] = { Dp(T - 25, 1000), Dp(T - 20, 1000), Dp(T - 10, 1000) },                          -- mixed with weekly buckets (nr weights)
    [5] = { Dp(T - 23, 1000), Dp(T - 17, 1000), Dp(T - 13, 1000) },                          -- the window edge bucket
    [6] = { Dp(T - 30, 1000), Dp(T - 22, 1010), Dp(T - 18, 990), Dp(T - 12, 1005), Dp(T - 8, 1000), Dp(T - 3, 995) },   -- an aggregate outlier
    [7] = { Dp(T - 20, nil), Dp(T - 15, 700), Dp(T - 10, nil), Dp(T - 5, 800), Dp(T - 2, nil) },   -- missing Recent Price days
    [8] = { Dp(T - 2, 400), Dp(T - 1, 450) },                                                -- legacy never helps
  }
  local bks = {
    -- bucket A: 7 observed days but only ONE with a Recent Price (9000); bucket B: 2 days, both 2000. By nr: 1000 x3, 2000 x2, 9000 x1 -> 1000.
    -- (weighted by n instead: 9000 x7 would move the median to 2000)
    [4] = { Bk(2861, 7, 7, 1, 9000), Bk(2862, 7, 2, 2, 2000) },
    [5] = { Bk(2860, 7, 7, 7, 9000) },
    [6] = { Bk(2861, 7, 2, 2, 1000000000), Bk(2863, 7, 3, 3, 1000) },
  }
  RawMarket(t, KEY, { at = At(T, 12), days = days, buckets = bks, from = T - 80, hist = { [8] = "20000,10;20001,11;20002,12;20003,13;20004,14" } })
  local function HV(id, day) return MK.Value(id, "historical", Opt(At(day or T, 13))) end
  local v = assert(HV(1)) Same(v.value, 200) Same(v.n, 3) Same(v.aggregate, false) Same(v.evidence, "daily") Same(v.window.from, T - 59)
  Check(v.basis:find("not a sale price or a promise", 1, true))
  local _, why, detail = HV(2) Same(why, "insufficient") Same(detail.n, 2)
  Same(HV(3).value, 300, "daily only: the lower median of six days")
  v = assert(HV(4))
  Same(v.value, 1000, "a bucket weighs its days WITH a Recent Price (nr), not every observed day") Same(v.n, 6) Same(v.daily, 3) Same(v.bucketDays, 3)
  Same(v.aggregate, true) Same(v.approximate, true) Same(v.evidence, "daily+buckets") Check(Has(v.notes, "aggregate"))
  -- the window edge: at T the bucket has 3 of 7 days inside (left out); at T - 1, 4 (counted). Either way it is disclosed.
  v = assert(HV(5, T))
  Same(v.value, 1000, "3 of 7 days inside: the bucket is left out") Same(v.n, 3) Same(#v.edges, 1) Same(v.edges[1].inside, 3) Same(v.edges[1].used, false)
  Check(Has(v.notes, "edge"))
  v = assert(HV(5, T - 1))
  Same(v.value, 9000, "4 of 7 days inside: counted whole, marked") Same(v.n, 10) Same(v.edges[1].inside, 4) Same(v.edges[1].used, true) Same(v.aggregate, true)
  Same(HV(6).value, 1000, "a large outlier inside a bucket does not move the median")
end
do
  -- the item-7 check properly: two valid days are insufficient, a third valid day makes a value
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  RawMarket(t, KEY, { at = At(T, 12), from = T - 80, days = {
    [7] = { Dp(T - 20, nil), Dp(T - 15, 700), Dp(T - 10, nil), Dp(T - 5, 800), Dp(T - 2, nil) },
    [9] = { Dp(T - 20, nil), Dp(T - 15, 700), Dp(T - 10, 650), Dp(T - 5, 800), Dp(T - 2, nil) } }, hist = { [8] = "20000,10;20001,11;20002,12;20003,13;20004,14" },
    rawh2 = { [8] = H2.Encode({}, { Dp(T - 2, 400), Dp(T - 1, 450) }) } })
  local _, why, detail = MK.Value(7, "historical", Opt(At(T, 13)))
  Same(why, "insufficient", "two valid days, three unknown: unknown Recent Prices never count") Same(detail.n, 2)
  Same(MK.Value(9, "historical", Opt(At(T, 13))).value, 700)
  Same(select(2, MK.Value(8, "historical", Opt(At(T, 13)))), "insufficient", "five legacy minimum days add nothing to Historical Value")
end

---------------------------------------------------------------------------
-- 3. Layouts of days and buckets queried at many times, against the models (the same calendar history at different current times)
---------------------------------------------------------------------------
do
  local MK = base.W.Market
  local checked, aggregates, edges = 0, 0, 0
  for seed = 1, 120 do
    local rng = FX.Rng(9500000 + seed)
    local T = 20090 + rng:Int(0, 30)
    -- buckets: a few two-week ones, then weekly ones, then daily points (oldest first, never overlapping)
    local bks, k = {}, math.floor((T - 125) / 14)
    for _ = 1, rng:Int(0, 3) do
      k = k + rng:Int(1, 2)
      local n = rng:Int(1, 14)
      bks[#bks + 1] = Bk(k, 14, n, rng:Int(0, n), rng:Int(500, 3000), { pm = rng:Int(10, 400) })
    end
    local w = math.max(2 * (k + 1), math.floor((T - 70) / 7))
    for _ = 1, rng:Int(0, 5) do
      w = w + rng:Int(1, 2)
      if w * 7 + 6 >= T - 36 then break end
      local n = rng:Int(1, 7)
      bks[#bks + 1] = Bk(w, 7, n, rng:Int(0, n), rng:Pick({ rng:Int(500, 3000), 99999999999 - rng:Int(0, 9) }), { pm = rng:Int(10, 400) })
    end
    local first = (#bks > 0 and (bks[#bks].k * bks[#bks].s + bks[#bks].s) or (T - 36))
    local days = {}
    for d = math.max(first, T - 36), T do
      if rng:Chance(0.45) then
        local r = rng:Chance(0.15) and nil or rng:Pick({ rng:Int(400, 3000), rng:Int(1, 5), 99999999999 - rng:Int(0, 99) })
        days[#days + 1] = Dp(d, r, { p = r and math.min(r, rng:Int(1, 400)) or rng:Int(1, 400), t = rng:Int(1, 500) })
      end
    end
    if #days == 0 then days[1] = Dp(T, 1000) end
    local m = { key = "Lab|Layout" .. seed, realm = "Lab", side = "Layout", scope = "full", format = 3, at = At(T, 12), items = { [1] = "50,1,1,1,0" },
      h2 = {}, c2 = {}, h2info = { state = "ok", v = 1, from = T - 130, at = At(T, 12) } }
    m.h2[1], m.c2[1] = H2.Encode({}, days, bks)
    local _, rd, rb = H2.Read(m.h2[1], m.c2[1])
    Check(rd, "the layout reads back")
    local e = { days = rd, buckets = rb or {} }
    for _, off in ipairs({ -40, -20, -7, -1, 0, 1, 5, 13, 30 }) do
      local today = T + off
      local opt = { market = m, now = At(today, 6) }
      local function Ctx() return ("seed %d T %d today %d"):format(9500000 + seed, T, today) end
      local mv, why = MK.Value(1, "market", opt)
      local rmv, rwhy = REF.VMarketValue(e, today)
      if rmv then Check(mv and mv.value == rmv.v and mv.n == rmv.n and mv.weight == rmv.weight, Ctx() .. " Market Value " .. Ser(mv) .. " want " .. Ser(rmv))
      else Same(why, rwhy, Ctx() .. " Market Value reason") end
      local hv, hwhy = MK.Value(1, "historical", opt)
      local rhv, rh = REF.VHistorical(e, today)
      if rhv then
        Check(hv and hv.value == rhv.v and hv.n == rhv.n and hv.aggregate == rhv.aggregate, Ctx() .. " Historical " .. Ser(hv) .. " want " .. Ser(rhv))
        if hv.aggregate then aggregates = aggregates + 1 end
        if hv.edges then edges = edges + 1 end
      else Same(hwhy, rh, Ctx() .. " Historical reason") end
      for _, d in ipairs({ 120, 60, 30, 7, 1 }) do
        local rg, gwhy = MK.Range(1, d, opt)
        local rr, rwhy2 = REF.VRange(e, today, d)
        if rr then
          for _, f in ipairs({ "min", "recent", "supply" }) do
            Check(rg and rg[f].lo == rr[f].lo and rg[f].hi == rr[f].hi and rg[f].n == rr[f].n, Ctx() .. " Range " .. d .. " " .. f .. ": " .. Ser(rg and rg[f]) .. " want " .. Ser(rr[f]))
          end
          Same(rg.aggregate == true, rr.aggregate, Ctx() .. " Range aggregate")
        else Same(gwhy, rwhy2, Ctx() .. " Range reason " .. d) end
      end
      for _, metric in ipairs({ "recent", "min", "supply" }) do
        for _, d in ipairs({ 14, 4, 9, 30 }) do
          local tr = assert(MK.TrendOf(1, metric, d, opt))
          local rt = REF.VTrend(e, today, MK.TREND_METRICS[metric], d)
          Same(tr.direction, rt.direction, Ctx() .. " trend " .. metric .. " " .. d)
          Same(tr.older.n, rt.no) Same(tr.newer.n, rt.nn)
          if rt.direction ~= "insufficient" then Same(tr.older.median, rt.older) Same(tr.newer.median, rt.newer) end
        end
      end
      checked = checked + 1
    end
  end
  Check(aggregates > 50 and edges > 10, ("bucket cases exercised: %d aggregate, %d with an edge"):format(aggregates, edges))
  print(("  layouts against the models: %d queries (Market Value, Historical Value, Range x5, TrendOf x12); %d aggregate, %d at a window edge"):format(checked, aggregates, edges))
end

---------------------------------------------------------------------------
-- 2c. Range: day ranges, buckets, the legacy join (minimum only, before recording began)
---------------------------------------------------------------------------
do
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  -- legacy days 20010..20012 (minimum 300..320) and a legacy bucket; version-2 recording began on day 20040; on day 20040 the legacy history also
  -- holds a value (it must not be counted twice)
  RawMarket(t, KEY, { at = At(T, 12), from = 20040, hist = { [1] = "20010,300;20011,280;20012,320;20040,999|713,250,400,1950,6" },
    days = { [1] = { Dp(20040, 1500, { n = 2, p = 900, plo = 800, phi = 950, rlo = 1400, rhi = 1700, tlo = 5, thi = 40 }), Dp(T - 1, 1200, { p = 1000, t = 12 }) } } })
  local rg = assert(MK.Range(1, 120, Opt(At(T, 13))))
  Same(rg.min.lo, 250, "the legacy bucket's low (days before recording began) counts for the minimum")
  Same(rg.min.hi, 1000) Same(rg.recent.lo, 1200) Same(rg.recent.hi, 1700, "the day's high Recent Price, not just the close")
  Same(rg.supply.lo, 5) Same(rg.supply.hi, 40) Same(rg.recent.n, 2, "Recent Price only from version-2 days") Same(rg.min.legacy, 3 + 6, "3 legacy days and a 6-day legacy bucket")
  Same(rg.provenance, "local+legacy") Check(Has(rg.notes, "legacy")) Same(rg.recordedFrom, 20040)
  Check(rg.min.lo ~= 999 and rg.min.hi ~= 999, "a legacy day after recording began is never counted (no double count)")
  local loc = assert(MK.Range(1, 120, Opt(At(T, 13), { sources = { "local" } })))
  Same(loc.min.lo, 800) Same(loc.min.legacy, 0) Same(loc.provenance, "local")
  local leg = assert(MK.Range(1, 120, Opt(At(T, 13), { sources = { "legacy" } })))
  Same(leg.min.lo, 250) Same(leg.recent.lo, nil, "legacy never has a Recent Price") Same(leg.supply.lo, nil)
  Same(select(2, MK.Range(1, 120, Opt(At(T, 13), { sources = { "import:x" } }))), "badsource")
  local short = assert(MK.Range(1, 7, Opt(At(T, 13))))
  Same(short.min.lo, 1000) Same(short.min.n, 1) Same(short.window.from, T - 6)
  Same(select(2, MK.Range(1, 121, Opt(At(T, 13)))), "baddays") Same(select(2, MK.Range(1, 0, Opt(At(T, 13)))), "baddays")
  Same(select(2, MK.Range(2, 120, Opt(At(T, 13)))), "nohistory")
  Same(select(2, MK.Range(1, 1, Opt(At(T + 30, 13)))), "nodata", "history exists, nothing in the window")
end

---------------------------------------------------------------------------
-- 2d. Distribution, Data Quality, Supply
---------------------------------------------------------------------------
do
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  t.c.ITEMS[30] = { name = "Blade", class = 2, quality = 3 }        -- a rare weapon: variants may be mixed
  t.c.ITEMS[31] = { name = "Club", class = 2, quality = 1 }         -- a common weapon: no random suffixes
  t.c.ITEMS[32] = { name = "Helm", class = 4, quality = 2 } t.c.UNLOADED[32] = true   -- armor, quality not loaded: the cautious answer
  local healthy = { { 9500, 5 }, { 9800, 5 }, { 10000, 10 }, { 10200, 10 }, { 10500, 10 }, { 11000, 5 } }   -- case 1 of 5.2: Recent 9741
  local week = {}
  for a = 9, 0, -1 do week[#week + 1] = Dp(T - a, 9700) end
  RawMarket(t, KEY, { at = At(T, 10), from = T - 40,
    listings = { [1] = healthy, [2] = { { 1, 1 }, { 9000, 1 }, { 9500, 1 } }, [3] = { { 10000, 50 }, { 1000000, 50 } }, [8] = { { 100000, 10 }, { 200000, 90 } }, [4] = { { 300000, 1 } },
      [5] = { { 700, 3 }, { 700, 3 }, { 700, 3 } }, [6] = { { 1, 1 }, { 5000, 40 }, { 5200, 10 } }, [30] = healthy, [31] = healthy, [32] = healthy,
      [7] = (function() local l = {} for i = 1, 9 do l[i] = { 100 + i, 2 } end return l end)() },
    days = { [1] = week, [30] = week, [31] = week, [32] = week, [2] = week } })
  local now = At(T, 11)
  local d = assert(MK.Distribution(1, Opt(now)))
  Same(d.recent, 9741) Same(d.min, 9500) Same(d.anchor, 10000) Same(d.q25, 10000) Same(d.q50, 10200) Same(d.q75, 10500) Same(d.hi, 11000)
  Same(d.items, 45) Same(d.listings, 6) Same(#d.tiers, 6) Same(d.tail.items, 0) Same(d.next, 9800) Same(d.spreadClass, "tight") Same(d.flags.farbelow, false)
  Check(math.abs(d.spread - 500 / 10200) < 1e-12) Same(d.role, "valuation") Check(d.basis:find("not how much sale prices move", 1, true))
  local d2 = assert(MK.Distribution(2, Opt(now)))
  Same(d2.recent, 1, "case 14: the 1-copper listing defeats the band mean...") Same(d2.flags.farbelow, true, "...and farbelow says so")
  Same(MK.Distribution(3, Opt(now)).spreadClass, "wide", "case 15: two far, equal clusters")
  Same(MK.Distribution(8, Opt(now)).spreadClass, "tight", "case 6: the quartiles all fall in the 90-item cluster (section 5.3 says wide; it is not)")
  local d4 = assert(MK.Distribution(4, Opt(now))) Same(d4.single, true) Same(d4.recent, 300000) Same(d4.spreadClass, "tight") Same(#d4.tiers, 1) Same(d4.tiers[1].m, 1)
  local d5 = assert(MK.Distribution(5, Opt(now))) Same(d5.single, true) Same(d5.tiers[1].l, 3) Same(d5.tiers[1].m, nil, "one price, three listings: the largest is not known")
  Same(MK.Distribution(6, Opt(now)).flags.cheapoutlier, true, "1 copper under half the Recent Price")
  local d7 = assert(MK.Distribution(7, Opt(now))) Same(d7.tail.items, 6) Same(d7.tail.listings, 3) Check(Has(d7.notes, "tail"))
  -- the result is the caller's: changing it changes nothing
  d.tiers[1].p, d.tiers[1].q = 1, 1
  Same(MK.Distribution(1, Opt(now)).tiers[1].p, 9500, "a caller's change to a result never reaches the next answer")

  -- Data Quality, policy 1
  Same(MK.QUALITY_POLICY, 1)
  local q = assert(MK.Quality(1, Opt(now)))
  Same(q.level, "good", "complete, fresh, 6 listings, tight, 10 observed days") Same(#q.reasons, 0) Same(q.policy, 1) Same(q.facts.observedDays, 10)
  q = MK.Quality(1, Opt(At(T, 10) + 86401)) Same(q.level, "fair") Same(q.reasons[1].code, "age") Same(q.reasons[1].text, "Last scanned 1 day ago.")
  Same(MK.Quality(1, Opt(At(T, 10) + 3 * 86400)).level, "fair", "exactly three days old is still fair")
  q = MK.Quality(1, Opt(At(T, 10) + 4 * 86400)) Same(q.level, "limited") Same(q.reasons[1].text, "Last scanned 4 days ago.") Same(q.reasons[1].blocks, "fair")
  q = MK.Quality(4, Opt(now)) Same(q.level, "limited", "one listing: limited, never none") Same(q.reasons[1].text, "Only 1 listing.")
  q = MK.Quality(2, Opt(now)) Same(q.level, "fair", "three listings, fresh: fair (farbelow only keeps it from good)")
  local codes = {} for _, r in ipairs(q.reasons) do codes[r.code] = r.text end
  Same(codes.farbelow, "One unusually cheap listing differs sharply from the others.") Same(codes.listings, "Only 3 listings.")
  q = MK.Quality(3, Opt(now)) Same(q.level, "limited") codes = {} for _, r in ipairs(q.reasons) do codes[r.code] = r.text end
  Same(codes.spread, "Prices vary widely.") Same(codes.listings, "Only 2 listings.") Same(codes.days, "No observed days in the last 30.")
  q = MK.Quality(30, Opt(now)) Same(q.level, "limited", "a rare weapon may mix variants: never above limited") Same(q.facts.mixedvariants, true)
  Same(q.reasons[1].text, "Several economically distinct item variants may be mixed.")
  Same(MK.Quality(31, Opt(now)).level, "good", "a common weapon has no random suffixes")
  Same(MK.Quality(32, Opt(now)).level, "limited", "armor whose quality is not known yet: the cautious answer")
  Same(MK.Quality(1, Opt(now, { mixedvariants = true })).level, "limited", "a caller can say the variants are mixed")
  Same(MK.Quality(99, Opt(now)).level, "none") Same(MK.Quality(99, Opt(now)).reasons[1].code, "unlisted")
  Same(MK.Quality(1, { market = "Realm|Nowhere", now = now }).level, "none") Same(MK.Quality(1, Opt(now, { variant = true })).reasons[1].code, "variant")
  Same(select(2, MK.Quality(-1, Opt(now))), "baditem")
  local v30 = MK.Value(30, "min", Opt(now)) Check(Has(v30.notes, "mixedvariants")) Same(v30.quality, "limited")
  -- the snapshot state: a cut scan is never above limited; a whole read with records lacking information is not good
  local mk = t.c.TwichUIWorkshopDB.markets[KEY]
  mk.cut, mk.complete = true, false
  q = MK.Quality(1, Opt(now)) Same(q.level, "limited") Same(q.reasons[1].text, "Some listings may be missing from the newest scan.")
  mk.cut, mk.partial = nil, 3
  q = MK.Quality(1, Opt(now)) Same(q.level, "fair") Same(q.reasons[1].text, "Current market data is incomplete.")
  mk.complete, mk.partial = true, 0

  -- Value min / recent from the snapshot
  local vmin, vrec = assert(MK.Value(6, "min", Opt(now))), assert(MK.Value(6, "recent", Opt(now)))
  Same(vmin.value, 1) Same(vrec.value, 5000, "the Recent Price ignores the 1-copper bait") Same(vrec.rsrc, "dist") Same(vmin.evidence, "snapshot") Same(vmin.age, 3600)
  Same(vmin.freshness, "fresh") Same(vmin.complete, true) Same(vmin.listings, 3) Same(vmin.items, 51) Check(Has(vmin.notes, "cheapoutlier"))
  Check(vmin.basis:find("not a sale", 1, true) and vrec.basis:find("not a sale price", 1, true))
  Same(MK.Value(4, "recent", Opt(now)).value, 300000, "a genuinely one-price item: Recent Price = minimum") Same(MK.Value(4, "recent", Opt(now)).rsrc, "single")
  Same(MK.Value(1, "min", Opt(now)).value, t.W.Market.Price(1, Opt(now)).price, "Minimum Buyout is exactly Market.Price's figure")
  Same(select(2, MK.Value(99, "min", Opt(now))), "unlisted")

  -- Supply
  local s = assert(MK.Supply(1, Opt(now)))
  Same(s.items, 45) Same(s.listings, 6) Same(s.atMin, 5) Same(s.nearRecent, 40, "items at or below 1.10 x 9741 = 10715: not the 5 at 11000") Same(s.history.median, 10) Same(s.history.n, 10)
  Same(s.trend.direction, "flat") Check(s.basis:find("Listed, never sold", 1, true)) Same(s.role, "valuation")
  Same(MK.Supply(7, Opt(now)).tail.items, 6) Same(select(2, MK.Supply(99, Opt(now))), "unlisted")
end
do
  -- missing distribution evidence: a multi-price item never borrows the minimum as its Recent Price
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  RawMarket(t, KEY, { at = At(T, 10), noDist = true, listings = { [1] = { { 100, 2 }, { 200, 3 } }, [2] = { { 50, 1 } } } })
  local now = At(T, 11)
  Same(select(2, MK.Value(1, "recent", Opt(now))), "noevidence") Same(select(2, MK.Value(2, "recent", Opt(now))), "noevidence", "without checked evidence even a one-price item")
  Same(MK.Value(1, "min", Opt(now)).value, 100) Same(select(2, MK.Distribution(1, Opt(now))), "noevidence")
  Same(MK.Quality(1, Opt(now)).facts.distribution, "noevidence")
  local s = assert(MK.Supply(1, Opt(now))) Same(s.atMin, 2) Same(s.nearRecent, nil) Check(Has(s.notes, "noevidence"))
  RawMarket(t, KEY2, { at = At(T, 10), listings = { [1] = { { 100, 2 }, { 200, 3 } }, [2] = { { 100, 2 }, { 200, 3 } } }, rawdist = { [2] = "1,150,200,100,200,200,200,5|100:2:1;200:3:1" } })
  t.c.TwichUIWorkshopDB.markets[KEY2].dist[1] = nil
  Same(select(2, MK.Value(1, "recent", { market = KEY2, now = now })), "missing")
  Same(select(2, MK.Value(2, "recent", { market = KEY2, now = now })), "malformed")
  t.c.TwichUIWorkshopDB.markets[KEY2].snap.at = At(T, 9)
  Same(select(2, MK.Value(1, "recent", { market = KEY2, now = now })), "malformed", "a snapshot record that is not the newest scan's is not trusted")
end

---------------------------------------------------------------------------
-- 2e. TrendOf
---------------------------------------------------------------------------
do
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  local function Series(list) local out = {} for _, x in ipairs(list) do out[#out + 1] = Dp(T - x[1], x[2], { p = x[3], t = x[4] }) end return out end
  RawMarket(t, KEY, { at = At(T, 10), from = T - 40, days = {
    [1] = Series({ { 12, 1000 }, { 9, 1000 }, { 8, 1000 }, { 5, 1200 }, { 3, 1200 }, { 0, 1200 } }),                   -- rising 20%
    [2] = Series({ { 12, 1000 }, { 9, 1000 }, { 5, 1049 }, { 0, 1049 } }),                                             -- 4.9%: flat
    [3] = Series({ { 12, 1000 }, { 9, 1000 }, { 5, 1050 }, { 0, 1050 } }),                                             -- 5.0%: rising
    [4] = Series({ { 12, 1000 }, { 9, 1000 }, { 5, 951 }, { 0, 951 } }),                                               -- -4.9%: flat
    [5] = Series({ { 12, 1000 }, { 9, 1000 }, { 5, 950 }, { 0, 950 } }),                                               -- -5.0%: falling
    [6] = Series({ { 12, 1000 }, { 5, 2000 }, { 0, 2000 } }),                                                          -- one day in the older half
    -- min falls while Recent rises: the metrics are never mixed
    [7] = Series({ { 12, 1000, 900 }, { 10, 1000, 900 }, { 4, 1300, 400 }, { 1, 1300, 400 } }),
    [8] = Series({ { 13, 1 }, { 10, 1 }, { 3, 99999999999 }, { 2, 99999999999 } }),                                   -- a huge rise
    [9] = Series({ { 12, 1000, nil, 5 }, { 11, 900, nil, 6 }, { 4, 50000, nil, 300 }, { 3, 20, nil, 280 }, { 2, 70000, nil, 320 }, { 1, 30, nil, 290 } }),   -- irregular
  } })
  local now = At(T, 11)
  local tr = assert(MK.TrendOf(1, "recent", nil, Opt(now)))
  Same(tr.direction, "rising") Same(tr.percent, 20) Same(tr.change, 200) Same(tr.days, 14) Same(tr.older.n, 3) Same(tr.newer.n, 3) Same(tr.older.from, T - 13) Same(tr.newer.to, T)
  Check(tr.basis:find("not where it goes next", 1, true))
  Same(MK.TrendOf(2, "recent", 14, Opt(now)).direction, "flat") Same(MK.TrendOf(3, "recent", 14, Opt(now)).direction, "rising", "exactly 5% is not flat")
  Same(MK.TrendOf(4, "recent", 14, Opt(now)).direction, "flat") Same(MK.TrendOf(5, "recent", 14, Opt(now)).direction, "falling")
  local ins = MK.TrendOf(6, "recent", 14, Opt(now)) Same(ins.direction, "insufficient") Same(ins.older.n, 1) Same(ins.change, nil)
  Same(MK.TrendOf(7, "recent", 14, Opt(now)).direction, "rising") Same(MK.TrendOf(7, "min", 14, Opt(now)).direction, "falling", "the minimum is its own metric")
  local big = MK.TrendOf(8, "recent", 14, Opt(now)) Same(big.direction, "rising") Same(big.percent, REF.PercentTenths(1, 99999999999) / 10)
  local irr = MK.TrendOf(9, "recent", 14, Opt(now)) Same(irr.older.median, 900) Same(irr.newer.median, 30) Same(irr.direction, "falling")
  Same(MK.TrendOf(9, "supply", 14, Opt(now)).direction, "rising")
  Same(select(2, MK.TrendOf(1, "price", 14, Opt(now))), "badmetric") Same(select(2, MK.TrendOf(1, "recent", 3, Opt(now))), "baddays")
  Same(select(2, MK.TrendOf(1, "recent", 31, Opt(now))), "baddays") Same(select(2, MK.TrendOf(99, "recent", 14, Opt(now))), "nohistory")
  Same(MK.TrendOf(1, "recent", 14, Opt(At(T + 20, 1))).direction, "insufficient", "unlisted days later on are not zeros: nothing to compare")
end

---------------------------------------------------------------------------
-- 2f. Posture: cheap / normal / expensive at exactly 85% and 115%, and every requirement
---------------------------------------------------------------------------
do
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  local H = 80000000000                                    -- 0.85 x H = 68000000000 and 1.15 x H = 92000000000 exactly
  local hist = {}
  for a = 5, 1, -1 do hist[#hist + 1] = Dp(T - a, H, { p = 1 }) end
  local function Three(u) return { { u, 1 }, { u, 1 }, { u, 1 } } end
  t.c.ITEMS[40] = { name = "Sword", class = 2, quality = 4 }
  RawMarket(t, KEY, { at = At(T, 10), from = T - 40,
    listings = { [1] = Three(68000000000), [2] = Three(67999999999), [3] = Three(92000000000), [4] = Three(92000000001), [5] = Three(80000000000),
      [6] = { { 80000000000, 1 }, { 80000000000, 1 } }, [7] = Three(1000), [8] = { { 1, 1 }, { 9000, 1 }, { 9500, 1 } }, [9] = { { 100, 1 }, { 5000, 10 }, { 5000, 10 }, { 5100, 10 }, { 5100, 10 } },
      [40] = Three(1000), [11] = Three(1000) },
    days = { [1] = hist, [2] = hist, [3] = hist, [4] = hist, [5] = hist, [6] = hist, [7] = { Dp(T - 4, 5000), Dp(T - 3, 5000), Dp(T - 2, 5000), Dp(T - 1, 5000) },
      [8] = { Dp(T - 5, 9000), Dp(T - 4, 9000), Dp(T - 3, 9000), Dp(T - 2, 9000), Dp(T - 1, 9000) }, [9] = { Dp(T - 5, 5000), Dp(T - 4, 5000), Dp(T - 3, 5000), Dp(T - 2, 5000), Dp(T - 1, 5000) },
      [40] = { Dp(T - 5, 5000), Dp(T - 4, 5000), Dp(T - 3, 5000), Dp(T - 2, 5000), Dp(T - 1, 5000) }, [11] = { Dp(T - 5, 5000), Dp(T - 4, 5000), Dp(T - 3, 5000), Dp(T - 2, 5000), Dp(T - 1, 5000) } } })
  local now = At(T, 11)
  local function P(id, o) return assert(MK.Posture(id, Opt(o or now))) end
  Same(P(1).posture, "normal", "exactly 85% is normal") Same(P(2).posture, "cheap", "a copper under 85% is cheap")
  Same(P(3).posture, "normal", "exactly 115% is normal") Same(P(4).posture, "expensive", "a copper over 115% is expensive")
  local p5 = P(5) Same(p5.posture, "normal") Same(p5.reference, H) Same(p5.current, H) Same(p5.n, 5) Same(p5.role, "valuation") Check(p5.basis:find("Not a guarantee of profit", 1, true))
  local p = P(6) Same(p.posture, "unknown") Same(p.why, "thin", "two listings")
  p = P(7) Same(p.posture, "unknown") Same(p.why, "insufficient", "four observed days")
  p = P(8) Same(p.posture, "unknown") Same(p.why, "farbelow", "a thin market whose cheapest listing is an outlier is never a bargain") Same(p.quality, "fair")
  p = P(9) Same(p.posture, "normal", "a cheap bait listing (minimum 100) does not make a bargain: the Recent Price is compared") Check(Has(p.notes, "cheapoutlier"))
  p = P(40) Same(p.posture, "unknown") Same(p.why, "quality", "mixed variants keep quality limited")
  Same(P(11).posture, "cheap", "1000 against 5000")
  p = P(11, At(T, 10) + 4 * 86400) Same(p.posture, "unknown") Same(p.why, "quality", "an old scan")
  p = P(99) Same(p.posture, "unknown") Same(p.why, "unlisted")
  Same(MK.Posture(1, { market = "Realm|Nowhere", now = now }).why, "nomarket")
end

---------------------------------------------------------------------------
-- 2g. Competition and Cost
---------------------------------------------------------------------------
do
  local T = 20083
  local t = Fresh()
  local MK = t.W.Market
  local eight = {}
  for i = 0, 7 do eight[#eight + 1] = { 10 + i, 1 } end
  local beyond = {}
  for i = 0, 5 do beyond[#beyond + 1] = { 10 + i, 1 } end
  beyond[#beyond + 1] = { 1000, 100 }
  RawMarket(t, KEY, { at = At(T, 10), listings = {
    [1] = { { 1, 1 }, { 5000, 40 }, { 5200, 10 } },                        -- case 2: a 1-copper bait under a deep market
    [2] = beyond,                                                         -- every kept price under half the anchor (1000)
    [3] = { { 100, 1 }, { 100, 1 } },                                     -- two single-item listings at one price
    [4] = { { 300, 1 } },                                                 -- one listing of one item
    [5] = { { 50, 4 }, { 50, 4 }, { 50, 4 }, { 60, 1 } },               -- several listings at one price (a tier with its largest listing)
    [6] = { { 10, 2 }, { 20, 1 }, { 20, 1 }, { 20, 1 }, { 30, 5 } },      -- crossing tiers
    [7] = { { 4000, 200 } },                                              -- one large stack
    [8] = eight,                                                          -- beyond the six kept tiers
    [9] = (function() local l = {} for i = 1, 10 do l[i] = { 99999999999, 1 } end return l end)(),   -- large copper (a stack's buyout is capped there)
    [10] = { { 50, 2 }, { 50, 2 }, { 50, 2 } },                           -- one price, three listings: the largest is not stored
    [11] = { { 5000, 1 }, { 6000, 3 }, { 6000, 2 }, { 7000, 1 } },
    [12] = { { 4700, 5 }, { 4800, 10 }, { 4800, 10 } },                  -- two equal stacks: their sizes are known (20 items, 2 listings, largest 10)
  } })
  local now = At(T, 11)
  local c = assert(MK.Competition(1, 10, Opt(now)))
  Same(c.role, "competition") Same(c.cheapest, 1) Same(c.competing, 5000) Same(c.competingTier, 2) Same(c.anchor, 5000) Same(c.ahead, 41)
  Same(c.below.items, 1) Same(c.tiers[1].below, true) Same(c.tiers[2].below, false) Check(Has(c.notes, "bait")) Same(c.depth.qty, 10) Same(c.depth.coveredBy, 2)
  Same(c.suggestion, nil) Same(c.price, nil) Check(c.basis:find("not a suggested price", 1, true))
  c = assert(MK.Competition(2, nil, Opt(now)))
  Same(c.competing, nil) Same(c.beyond, true, "the qualifying price is above the six kept prices") Same(c.below.items, 6) Same(c.tail.items, 100) Check(Has(c.notes, "beyondtiers"))
  c = assert(MK.Competition(8, 7, Opt(now, { price = 13 })))
  Same(c.atPrice.items, 4) Same(c.atPrice.atLeast, nil) Same(c.depth.coveredBy, nil) Same(c.depth.beyond, true)
  Same(MK.Competition(8, 1, Opt(now, { price = 20 })).atPrice.atLeast, true, "the tail may hold more at or below 20")
  Same(select(2, MK.Competition(1, 0, Opt(now))), "badqty") Same(select(2, MK.Competition(99, 1, Opt(now))), "unlisted")

  local function C(id, q, o) return MK.Cost(id, q, Opt(o or now)) end
  local x = C(3, 1) Same(x.state, "exact") Same(x.cost, 100) Same(x.low, 100) Same(x.high, 100) Same(x.role, "purchase")
  x = C(4, 1) Same(x.state, "exact") Same(x.cost, 300)
  x = C(4, 2) Same(x.state, "few") Same(x.available, 1) Same(x.cost, nil)
  x = C(5, 5) Same(x.state, "range") Same(x.low, 250) Same(x.high, 400, "listings of 4: buying 5 takes two whole listings") Same(x.last.largest, 4) Same(x.last.overbuy, 3)
  Same(x.cost, nil, "a range is never presented as the total") Check(Has(x.notes, "wholeauction"))
  x = C(6, 6) Same(x.state, "range") Same(x.low, 110) Same(x.high, 230) Same(#x.used, 3) Same(x.used[3].q, 1)
  x = C(6, 5) Same(x.state, "exact", "an exact tier boundary") Same(x.cost, 80)
  x = C(7, 5) Same(x.state, "range") Same(x.low, 20000) Same(x.high, 800000, "one 200-stack: whole-auction buying takes all of it") Same(x.last.overbuy, 195)
  x = C(7, 200) Same(x.state, "exact") Same(x.cost, 800000)
  x = C(8, 7) Same(x.state, "estimate") Same(x.low, 91, "six prices whole and the seventh item at least one copper above the sixth") Same(x.high, 92) Same(x.cost, nil)
  Check(Has(x.notes, "beyondtiers"))
  x = C(8, 8) Same(x.state, "estimate") Same(x.low, 75 + 16 + 16) Same(x.high, 75 + 17 + 17)
  x = C(8, 9) Same(x.state, "few") Same(x.available, 8)
  x = C(9, 10) Same(x.state, "exact") Same(x.cost, 999999999990, "large copper totals stay exact")
  x = C(10, 1) Same(x.state, "range") Same(x.high, 200, "the largest listing is at most what the other listings leave (6 - 3 + 1 = 4)")
  -- listings of 3 and 2 at 6000, 2 more needed: the worst real purchase is 23000 (the 3-listing), the bound (largest listing - 1 = 2 over) says
  -- 29000: an upper bound, never a claim that it costs that much (the random test checks every real order lies inside low..high)
  x = C(11, 3) Same(x.state, "range") Same(x.low, 5000 + 12000) Same(x.high, 5000 + 24000)
  x = C(12, 15) Same(x.state, "exact", "5 + one whole stack of 10: nothing over-bought") Same(x.cost, 5 * 4700 + 10 * 4800)
  x = C(12, 16) Same(x.state, "range") Same(x.low, 5 * 4700 + 11 * 4800) Same(x.high, 5 * 4700 + 20 * 4800, "11 of them need both 10-stacks")
  for _, bad in ipairs({ 0, -1, 1.5, "3", 0 / 0, 1 / 0 }) do
    local r = MK.Cost(3, bad, Opt(now)) Same(r.state, "none") Same(r.why, "badqty")
  end
  Same(MK.Cost(99, 1, Opt(now)).why, "unlisted") Same(MK.Cost(3, 1, { market = "Realm|Nowhere", now = now }).why, "nomarket")
  RawMarket(t, KEY2, { at = At(T, 10), noDist = true, listings = { [3] = { { 100, 1 } } } })
  Same(MK.Cost(3, 1, { market = KEY2, now = now }).state, "none") Same(MK.Cost(3, 1, { market = KEY2, now = now }).why, "noevidence")
  Same(MK.Cost(3, 1, Opt(now)).unit, 100)
end

---------------------------------------------------------------------------
-- 4. The cache
---------------------------------------------------------------------------
do
  local t = Fresh()
  local MK, PR, Vt = t.W.Market, t.W.Prices, t.W.Valuation
  local T = 20083
  -- each scan: five listings per item (four of 2 items at u, one of 1 at u + 10), so every item has a distribution and a Recent Price
  local function Scan(at, k, first)
    local b = PR.NewBatch()
    for id = 1, 9 do
      local u = (id == 1 and first) or (1000 + id * 10 + k)
      for _ = 1, 4 do b:Add(id, 2, u * 2, true) end
      b:Add(id, 1, u + 10, true)
    end
    local items, n, _, _, dist = b:Items()
    return assert(PR.Commit(KEY, { realm = "Realm", side = "Alliance", at = at, complete = true, read = b.read, used = b.used, n = n, items = items, dist = dist, alg = 1 }))
  end
  for d = 0, 9 do Scan(At(T - 9 + d, 8), d) end
  Vt.CacheClear()
  local s0 = Vt.CacheStats()
  local now = At(T, 9)
  local a = assert(MK.Value(1, "market", Opt(now)))
  Same(Vt.CacheStats().misses - s0.misses, 1, "first question: a miss")
  local b = assert(MK.Value(1, "market", Opt(now)))
  Same(Vt.CacheStats().hits - s0.hits, 1, "the same question again: a hit") Same(a.value, b.value) Check(a ~= b, "a hit still answers with a new table")
  MK.Value(1, "historical", Opt(now)) MK.Quality(1, Opt(now))
  Same(Vt.CacheStats().hits - s0.hits, 3, "Historical Value and Quality reuse the same digest")
  -- a scan: the next answer reflects it (the cache is never stale after a commit)
  -- ten days, closing Recent Prices 1010..1019 (newest highest); weights 23: the median is 1017. A second scan today closes day T at 1 instead
  -- of 1019: 1 (4), 1010, 1011, 1012, 1013 (2), 1014 (2), 1015 (2) reaches 13 >= 11.5, so 1015
  Same(a.value, 1017, "by hand")
  Scan(At(T, 20), 50, 1)
  local m2 = assert(MK.Value(1, "market", Opt(At(T, 21))))
  Same(m2.value, 1015, "after a scan the answer is the new one, never the cached one")
  Same(Vt.CacheStats().wipes - s0.wipes >= 1, true, "a new generation of the market wipes the cache")
  -- a day rollover: the weights move, so the digest is recomputed
  local h0 = Vt.CacheStats()
  local r1 = assert(MK.Value(1, "market", Opt(At(T + 1, 1))))
  Same(Vt.CacheStats().misses - h0.misses, 1, "another day: a miss")
  Same(r1.window.from, T + 1 - 13, "the window moved with the day")
  -- time-dependent answers are never cached: within one day the digest is a hit while the freshness moves on; a day later the level drops
  local q1 = assert(MK.Quality(1, Opt(At(T, 21))))
  local h1 = Vt.CacheStats().hits
  local f2 = assert(MK.Value(1, "min", Opt(At(T, 23, 30))))
  Same(q1.level, "good") Same(q1.freshness, "fresh") Same(f2.freshness, "aging", "3.5 hours old, from a cached digest") Same(Vt.CacheStats().hits, h1 + 1)
  local q2 = assert(MK.Quality(1, Opt(At(T, 20) + 86401)))
  Same(q2.level, "fair", "a cached good never outlives the 24 hours that made it good") Same(q2.reasons[1].code, "age")
  -- a database replaced under the same key and generation: other strings, so a miss
  local saved = Clone(t.DB())
  local hit0 = Vt.CacheStats()
  MK.Value(2, "market", Opt(At(T, 21)))
  local snap = Clone(saved)
  snap.markets[KEY].h2[2] = H2.Encode({}, { Dp(T, 7777) })
  t.c.TwichUIWorkshopDB = snap
  Same(MK.Value(2, "market", Opt(At(T, 21))).value, 7777, "a replaced string is never answered from the cache")
  Check(Vt.CacheStats().misses > hit0.misses + 1)
  -- the snapshot facts the same way: item 4's distribution entry removed under the same generation (it has a second price: "missing")
  Same(MK.Value(4, "recent", Opt(At(T, 21))).rsrc, "dist")
  local snap2 = Clone(t.DB())
  snap2.markets[KEY].dist[4] = nil
  t.c.TwichUIWorkshopDB = snap2
  Same(select(2, MK.Value(4, "recent", Opt(At(T, 21)))), "missing", "cached snapshot facts are never used for another entry")
  -- a second market: its own entries
  t.c.TwichUIWorkshopDB = Clone(saved)
  t.c.TwichUIWorkshopDB.markets[KEY2] = Clone(saved.markets[KEY])
  t.c.TwichUIWorkshopDB.markets[KEY2].h2[3] = H2.Encode({}, { Dp(T, 4242) })
  Same(MK.Value(3, "market", { market = KEY2, now = At(T, 21) }).value, 4242)
  Check(MK.Value(3, "market", Opt(At(T, 21))).value ~= 4242, "markets are never mixed")
  -- the bound: 2,500 distinct items never hold more than CACHE_MAX entries
  local big = { key = "Lab|Bound", realm = "Lab", side = "Bound", scope = "full", format = 3, at = At(T, 12), items = {}, h2 = {}, c2 = {}, h2info = { state = "ok", v = 1, from = T - 10, at = At(T, 12) } }
  for id = 1, 2500 do big.h2[id] = H2.Encode({}, { Dp(T, 100 + id) }) end
  for id = 1, 2500 do MK.Value(id, "market", { market = big, now = At(T, 13) }) end
  local st = Vt.CacheStats()
  Check(st.entries <= Vt.CACHE_MAX and st.entries > 0, "bounded: " .. st.entries)
  Same(MK.Value(2500, "market", { market = big, now = At(T, 13) }).value, 2600)
  -- a market table without a key is never cached (nothing to tell it apart by)
  local u0 = st.uncached
  big.key = nil
  MK.Value(1, "market", { market = big, now = At(T, 13) })
  Same(Vt.CacheStats().uncached, u0 + 1)
end

---------------------------------------------------------------------------
-- 5. Read-only and 6. the old API unchanged
---------------------------------------------------------------------------
local function Build(t, seed)
  -- a market built through the real pipeline: listings -> batch -> distribution -> stepped commit -> history
  local PR = t.W.Prices
  local rng = FX.Rng(seed)
  for d = 0, 40, rng:Int(1, 3) do
    for k = 1, rng:Int(1, 3) do
      local b = PR.NewBatch()
      for id = 1, 8 do
        if rng:Chance(0.8) then
          for _ = 1, rng:Int(1, 7) do local c = rng:Int(1, 9) b:Add(id, c, (100 * id + rng:Int(0, 60)) * c, true) end
        end
      end
      local items, n, _, _, dist = b:Items()
      PR.Commit(KEY, { realm = "Realm", side = "Alliance", at = At(D0 + d, 4 * k), complete = true, read = b.read, used = b.used, n = n, items = items, dist = dist, alg = dist and 1 or nil })
    end
  end
end
local ALL = function(MK, id, opt)
  local out = {}
  for _, k in ipairs({ "min", "recent", "market", "historical" }) do out[#out + 1] = MK.Value(id, k, opt) or false end
  out[#out + 1] = MK.Range(id, nil, opt) or false
  out[#out + 1] = MK.Distribution(id, opt) or false
  out[#out + 1] = MK.Supply(id, opt) or false
  for _, mt in ipairs({ "recent", "min", "supply" }) do out[#out + 1] = MK.TrendOf(id, mt, nil, opt) or false end
  out[#out + 1] = MK.Posture(id, opt) or false
  out[#out + 1] = MK.Quality(id, opt) or false
  out[#out + 1] = MK.Competition(id, 5, opt) or false
  out[#out + 1] = MK.Cost(id, 5, opt) or false
  return out
end
do
  local t = Setup(nil)
  Build(t, 9600001)
  local before = Ser(t.DB())
  local opt = { market = KEY, now = At(D0 + 40, 20) }
  local first = {}
  for id = 1, 9 do first[id] = Ser(ALL(t.W.Market, id, opt)) end
  Same(Ser(t.DB()), before, "every A5 call leaves the saved database deep-equal")
  -- a caller scribbling over every answer changes neither the saved data nor the next answers
  for id = 1, 9 do
    for _, r in ipairs(ALL(t.W.Market, id, opt)) do
      if type(r) == "table" then
        for k, v in pairs(r) do
          if type(v) == "table" then for kk in pairs(v) do v[kk] = "x" end end
          r[k] = "x"
        end
      end
    end
  end
  Same(Ser(t.DB()), before, "changing the answers changes nothing saved")
  for id = 1, 9 do Same(Ser(ALL(t.W.Market, id, opt)), first[id], "the next answers are the same (item " .. id .. ")") end
  -- 6. the same database read by the old functions, with and without Valuation.lua: identical answers
  local old = Setup(Clone(t.DB()), true)
  Same(old.W.Market.Value, nil, "the comparison build has no A5 services")
  for id = 1, 9 do
    for _, call in ipairs({
      function(MK) return { MK.Price(id, opt) } end, function(MK) return { MK.Quote(id, 3, opt) } end, function(MK) return { MK.Stats(id, "week", opt) } end,
      function(MK) return { MK.Stats(id, "retained", opt) } end, function(MK) return { MK.Series(id, opt) } end, function(MK) return { MK.Trend(id, 7, opt) } end,
      function(MK) return { MK.Compare(id, "week", opt) } end, function(MK) return { MK.Observed(id, D0 + 40, opt) } end,
      function(MK) return { MK.History(id, "min", opt) } end, function(MK) return { MK.History(id, "recent", opt) } end, function(MK) return { MK.Info(opt) } end }) do
      Same(Ser(call(t.W.Market)), Ser(call(old.W.Market)), "the old API answers as before (item " .. id .. ")")
    end
  end
  Same(Ser(t.DB()), Ser(old.DB()), "and both databases are still the same")
end

---------------------------------------------------------------------------
-- 7. Seeded markets through the real pipeline, every service against the models
---------------------------------------------------------------------------
local KINDS = { "normal", "normal", "thin", "single", "bait", "wall", "huge", "deep" }
local MAXC = 99999999999
local function NewItem(rng)
  local kind = rng:Pick(KINDS)
  local base = kind == "huge" and rng:Int(50000000000, 99000000000) or rng:Int(20, 60000)
  return { kind = kind, base = base, live = rng:Chance(0.8) }
end
local function ListingsOf(rng, it)
  local P, out = it.base, {}
  local function U(u) if u < 1 then u = 1 end if u > MAXC then u = MAXC end return math.floor(u) end
  local k = it.kind
  if k == "normal" or k == "bait" then
    for _ = 1, rng:Int(3, 12) do out[#out + 1] = { U(P + rng:Int(-math.floor(P / 5), math.floor(P / 5))), rng:Int(1, 20) } end
    if k == "bait" then out[#out + 1] = { U(P / 10), 1 } end
  elseif k == "thin" then
    for _ = 1, rng:Int(1, 3) do out[#out + 1] = { U(P + rng:Int(-math.floor(P / 2), P)), rng:Int(1, 3) } end
  elseif k == "single" then
    for _ = 1, rng:Int(1, 6) do out[#out + 1] = { U(P), rng:Int(1, 5) } end
  elseif k == "wall" then
    out[#out + 1] = { U(P), rng:Int(100, 500) }
    for _ = 1, rng:Int(1, 3) do out[#out + 1] = { U(P * 1.2 + rng:Int(0, 50)), rng:Int(1, 5) } end
  elseif k == "huge" then
    for _ = 1, rng:Int(1, 5) do out[#out + 1] = { U(P + rng:Int(-1000000000, 1000000000)), rng:Int(1, 3) } end
  else
    for i = 1, rng:Int(8, 14) do out[#out + 1] = { U(P + i * rng:Int(1, 30)), rng:Int(1, 4) } end
  end
  return out
end

local function Calendar(rng, nItems)
  local items = {}
  for id = 1, nItems do items[id] = NewItem(rng) end
  local scans, day = {}, D0 + rng:Int(0, 6)
  for _ = 1, rng:Int(15, 70) do
    day = day + rng:Pick({ 0, 0, 1, 1, 1, 2, 3, 6, 9, 25, 40 })
    local minute = rng:Int(0, 300)
    for _ = 1, rng:Pick({ 1, 1, 2, 3 }) do
      minute = minute + rng:Pick({ 1, 30, 240 })
      if minute >= 1440 then break end
      local sc = { at = day * DAY + minute * 60, whole = not rng:Chance(0.1), partial = rng:Chance(0.1) and rng:Int(1, 4) or 0, noDist = rng:Chance(0.06), recs = {} }
      for id, it in ipairs(items) do
        if rng:Chance(0.1) then it.live = not it.live end
        if it.live then
          -- prices drift, with an occasional one-day spike or crash
          local f = rng:Pick({ 1, 1, 1, 1.03, 0.97, 1.1, 0.9 })
          it.base = math.max(2, math.min(MAXC - 2000000000, math.floor(it.base * f)))
          local saved = it.base
          if rng:Chance(0.04) then it.base = math.min(MAXC - 2000000000, it.base * 5) elseif rng:Chance(0.04) then it.base = math.max(2, math.floor(it.base / 5)) end
          local recs = {}
          for _, x in ipairs(ListingsOf(rng, it)) do
            local c = x[2]
            while c > 1 and x[1] * c > MAXC do c = c - 1 end   -- a stack's buyout is capped at MAXC (the batch refuses more)
            recs[#recs + 1] = { b = x[1] * c, c = c }
          end
          sc.recs[id] = recs
          it.base = saved
        end
      end
      scans[#scans + 1] = sc
    end
  end
  return scans
end

local function Commit(t, key, sc, rng)
  local PR = t.W.Prices
  local b = PR.NewBatch()
  local ids = {}
  for id in pairs(sc.recs) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do for _, r in ipairs(sc.recs[id]) do b:Add(id, r.c, r.b, true) end end
  local items, n, _, _, dist = b:Items()
  if sc.noDist then dist = nil end
  local scan = { realm = "Realm", side = key:match("|(.*)$"), at = sc.at, complete = sc.whole and sc.partial == 0, cut = not sc.whole or nil, read = b.read, used = b.used,
    partial = sc.partial, n = n, items = items, dist = dist, alg = dist and 1 or nil }
  local job = PR.BeginCommit(key, scan)
  if not job then return false end
  local limit = rng:Pick({ 3, 17, 120, math.huge })
  while not job:Step(limit) do end
  return job:Apply()
end

-- the expected answers for one item from the models alone
local function Expect(model, cur, id, now, mixed)
  local today = math.floor(now / DAY)
  local x = { today = today }
  local recs = cur.recs[id]
  local e = REF.H2Expect(model, id)
  x.state = e
  if recs then
    local lst, de = REF.VListings(recs), REF.ExpectDist(recs)
    x.lst, x.de = lst, de
    x.min = lst.p
    x.recent = not cur.noDist and de.r or nil
    local observed, seen = 0, {}
    for _, sc in ipairs(model.rec) do
      local d = math.floor(sc.at / DAY)
      if sc.items[id] and d >= today - 29 and d <= today and not seen[d] then seen[d] = true observed = observed + 1 end
    end
    x.qlevel, x.qcodes = REF.VQuality({ priced = true, complete = cur.complete and not cur.cut, cut = cur.cut, age = math.max(0, now - cur.at), listings = lst.l,
      spreadClass = (not cur.noDist) and REF.VSpreadClass(de.q25, de.q50, de.q75) or nil, observed = observed, mixed = mixed, farbelow = (not cur.noDist) and lst.farbelow })
  else
    x.qlevel, x.qcodes = "none", {}
  end
  x.mv, x.mvWhy = REF.VMarketValue(e, today)
  x.hv, x.hvWhy = REF.VHistorical(e, today)
  return x
end

do
  local t = Setup(nil)
  local MK, PR = t.W.Market, t.W.Prices
  local SEEDS = tonumber(os.getenv("VALUE_SEEDS") or "") or 30
  local seen = { queries = 0, mv = 0, hv = 0, agg = 0, posture = {}, quality = {}, cost = {}, trend = {} }
  for seed = 1, SEEDS do
    t.c.TwichUIWorkshopDB = nil
    local rng = FX.Rng(9700000 + seed)
    local nItems = rng:Int(3, 7)
    for id = 1, nItems do t.c.ITEMS[id] = nil end
    local mixedOf = {}
    for id = 1, nItems do
      if rng:Chance(0.15) then t.c.ITEMS[id] = { name = "Gear" .. id, class = 4, quality = 3 } mixedOf[id] = true end
    end
    local keys = { KEY, KEY2 }
    local models, curs = { REF.H2New(), REF.H2New() }, { {}, {} }
    local all = {}
    for mi = 1, 2 do for _, sc in ipairs(Calendar(rng, nItems)) do all[#all + 1] = { mi = mi, sc = sc } end end
    table.sort(all, function(a, b) if a.sc.at ~= b.sc.at then return a.sc.at < b.sc.at end return a.mi < b.mi end)

    local function Query(mi, now)
      local key, model, cur = keys[mi], models[mi], curs[mi]
      local opt = { market = key, now = now }
      for id = 1, nItems do
        local x = Expect(model, cur, id, now, mixedOf[id] == true)
        local function Ctx(what) return ("seed %d market %s item %d now %d (day %d) %s"):format(9700000 + seed, key, id, now, x.today, what) end
        local vmin, wmin = MK.Value(id, "min", opt)
        if x.min then Same(vmin and vmin.value, x.min, Ctx("Minimum Buyout")) else Same(wmin, "unlisted", Ctx("unlisted")) end
        local vr, wr = MK.Value(id, "recent", opt)
        if x.recent then Same(vr and vr.value, x.recent, Ctx("Recent Price")) elseif x.min then Same(wr, "noevidence", Ctx("Recent Price reason")) end
        local mv, mvw = MK.Value(id, "market", opt)
        if x.mv then
          Check(mv and mv.value == x.mv.v and mv.n == x.mv.n and mv.weight == x.mv.weight, Ctx("Market Value " .. Ser(mv and { mv.value, mv.n, mv.weight }) .. " want " .. Ser(x.mv)))
          seen.mv = seen.mv + 1
        else Same(mvw, x.mvWhy, Ctx("Market Value reason")) end
        local hv, hvw = MK.Value(id, "historical", opt)
        if x.hv then
          Check(hv and hv.value == x.hv.v and hv.n == x.hv.n and hv.aggregate == x.hv.aggregate, Ctx("Historical Value " .. Ser(hv and { hv.value, hv.n, hv.aggregate }) .. " want " .. Ser(x.hv)))
          seen.hv = seen.hv + 1
          if hv.aggregate then seen.agg = seen.agg + 1 end
        else Same(hvw, x.hvWhy, Ctx("Historical Value reason")) end
        local q = assert(MK.Quality(id, opt))
        Same(q.level, x.qlevel, Ctx("quality"))
        local codes = {}
        for _, r in ipairs(q.reasons) do codes[r.code] = true end
        if x.min then
          for code in pairs(codes) do Check(x.qcodes[code], Ctx("quality reason " .. code .. " not expected")) end
          for code in pairs(x.qcodes) do Check(codes[code], Ctx("quality reason " .. code .. " missing")) end
        end
        seen.quality[q.level] = (seen.quality[q.level] or 0) + 1
        for _, metric in ipairs({ "recent", "min", "supply" }) do
          local tr, twhy = MK.TrendOf(id, metric, 14, opt)
          if x.state and (#x.state.days > 0 or #x.state.buckets > 0) then
            local rt = REF.VTrend(x.state, x.today, MK.TREND_METRICS[metric], 14)
            Same(tr and tr.direction, rt.direction, Ctx("trend " .. metric))
            if rt.direction ~= "insufficient" then Same(tr.older.median, rt.older, Ctx("trend older")) Same(tr.newer.median, rt.newer, Ctx("trend newer")) end
            seen.trend[rt.direction] = (seen.trend[rt.direction] or 0) + 1
          else Same(twhy, "nohistory", Ctx("trend reason")) end
        end
        for _, d in ipairs({ 120, 30 }) do
          local rg = MK.Range(id, d, opt)
          local rr = REF.VRange(x.state, x.today, d)
          if rr then
            for _, f in ipairs({ "min", "recent", "supply" }) do
              Check(rg and rg[f].lo == rr[f].lo and rg[f].hi == rr[f].hi and rg[f].n == rr[f].n, Ctx("Range " .. d .. " " .. f .. " " .. Ser(rg and rg[f]) .. " want " .. Ser(rr[f])))
            end
          else Same(rg, nil, Ctx("Range")) end
        end
        -- Posture from the expected pieces
        local pos = assert(MK.Posture(id, opt))
        local reasons = {}
        if not x.min then reasons[#reasons + 1] = "unlisted" elseif not x.recent then reasons[#reasons + 1] = "noevidence" end
        if x.lst and x.lst.l < 3 then reasons[#reasons + 1] = "thin" end
        if REF.V and ({ none = 0, limited = 1, fair = 2, good = 3 })[x.qlevel] < 2 then reasons[#reasons + 1] = "quality" end
        if x.lst and not cur.noDist and x.lst.farbelow then reasons[#reasons + 1] = "farbelow" end
        if not x.hv then reasons[#reasons + 1] = x.hvWhy elseif x.hv.n < 5 then reasons[#reasons + 1] = "insufficient" end
        if #reasons > 0 then
          Same(pos.posture, "unknown", Ctx("posture")) Same(table.concat(pos.reasons, ","), table.concat(reasons, ","), Ctx("posture reasons"))
        else
          local c, h = x.recent, x.hv.v
          local want = (100 * c < 85 * h) and "cheap" or ((100 * c > 115 * h) and "expensive" or "normal")
          Same(pos.posture, want, Ctx("posture " .. c .. " vs " .. h))
        end
        seen.posture[pos.posture] = (seen.posture[pos.posture] or 0) + 1
        -- Competition, Cost and Supply against the plain listings
        if x.lst and x.recent then
          local comp = assert(MK.Competition(id, 3, opt))
          local rc = REF.VCompetition(x.lst, x.de.a)
          Same(comp.cheapest, rc.cheapest, Ctx("cheapest")) Same(comp.competing, rc.competing, Ctx("competing")) Same(comp.ahead, rc.ahead, Ctx("ahead"))
          local six = 0
          for i = 1, math.min(6, #x.lst.groups) do six = six + x.lst.groups[i].q end
          for _, qty in ipairs({ 1, rng:Int(1, x.lst.t), x.lst.t, x.lst.t + 1, six, six + 1 }) do
            local cost = MK.Cost(id, qty, opt)
            local rcost = REF.VCost(x.lst, qty)
            Same(cost.state, rcost.state, Ctx("cost state of " .. qty))
            if rcost.state ~= "few" then
              Same(cost.low, rcost.low, Ctx("cost low of " .. qty)) Same(cost.high, rcost.high, Ctx("cost high of " .. qty))
              Check(cost.low <= cost.high, Ctx("low <= high"))
              if cost.state == "exact" then Same(cost.cost, cost.low) else Same(cost.cost, nil, Ctx("a range or an estimate is never a total")) end
              if rcost.actual then Check(rcost.actual >= cost.low and rcost.actual <= cost.high, Ctx("the real cost of the cheapest items lies inside the estimate")) end
              -- every order of buying the last tier's whole listings costs between low and high
              if rcost.group and #rcost.group.sizes <= 6 then
                local sizes = rcost.group.sizes
                local function Perm(k, used, got, spent)
                  if got >= rcost.rem then
                    local total = rcost.beforeCost + spent
                    Check(total >= cost.low and total <= cost.high, Ctx(("a whole-listing purchase of %d costs %d, outside %d..%d"):format(qty, total, cost.low, cost.high)))
                    return
                  end
                  for i = 1, #sizes do if not used[i] then used[i] = true Perm(k + 1, used, got + sizes[i], spent + sizes[i] * rcost.group.p) used[i] = false end end
                end
                Perm(0, {}, 0, 0)
              end
            end
            seen.cost[cost.state] = (seen.cost[cost.state] or 0) + 1
          end
          local sup = assert(MK.Supply(id, opt))
          Same(sup.atMin, x.lst.groups[1].q, Ctx("supply at the minimum")) Same(sup.nearRecent, x.de.near, Ctx("near")) Same(sup.items, x.lst.t)
        end
        seen.queries = seen.queries + 1
      end
    end

    for _, ev in ipairs(all) do
      local mi = ev.mi
      local otherBefore = Ser(t.DB() and t.DB().markets[keys[3 - mi]])
      if Commit(t, keys[mi], ev.sc, rng) then
        local sc = ev.sc
        local obs = { at = sc.at, whole = sc.whole, partial = sc.partial, items = {} }
        for id, recs in pairs(sc.recs) do
          local lst = REF.VListings(recs)
          local r = nil
          if not sc.noDist then r = REF.ExpectDist(recs).r end
          obs.items[id] = { p = lst.p, r = r, t = lst.t, l = lst.l }
        end
        REF.H2Scan(models[mi], obs)
        curs[mi] = { at = sc.at, recs = sc.recs, noDist = sc.noDist, cut = not sc.whole, complete = sc.whole and sc.partial == 0 }
        if rng:Chance(0.2) then Query(mi, sc.at + rng:Pick({ 60, 3600, 30000 })) end
      end
      Same(Ser(t.DB() and t.DB().markets[keys[3 - mi]]), otherBefore, "the other market is untouched")
    end
    for mi = 1, 2 do
      if curs[mi].at then
        for _, off in ipairs({ 600, 23 * 3600, 86400 + 60, 2 * 86400, 4 * 86400, 10 * 86400 }) do Query(mi, curs[mi].at + off) end
      end
    end
  end
  local function List(tb) local o = {} for k, v in pairs(tb) do o[#o + 1] = k .. " " .. v end table.sort(o) return table.concat(o, ", ") end
  print(("  pipeline markets against the models: %d seeds, %d item queries; Market Value %d, Historical %d (%d with buckets)"):format(SEEDS, seen.queries, seen.mv, seen.hv, seen.agg))
  print("    quality: " .. List(seen.quality) .. " | posture: " .. List(seen.posture))
  print("    cost: " .. List(seen.cost) .. " | trend: " .. List(seen.trend))
  for _, lv in ipairs({ "good", "fair", "limited", "none" }) do Check((seen.quality[lv] or 0) > 20, "quality level exercised: " .. lv) end
  for _, st in ipairs({ "exact", "range", "estimate", "few" }) do Check((seen.cost[st] or 0) > 20, "cost state exercised: " .. st) end
  for _, p in ipairs({ "cheap", "normal", "expensive", "unknown" }) do Check((seen.posture[p] or 0) > 3, "posture exercised: " .. p .. " " .. tostring(seen.posture[p])) end
  Check(seen.mv > 200 and seen.hv > 100 and seen.agg > 5, "history values exercised")
end

print("PASSED test_workshop_valuation")
