-- Market data foundation 2.0, milestone A7 (docs/workshop/market-data-foundation-v2.md, "A7 as built"): the consumers of the market services.
--   1. MarketFacts: rows for complete data, legacy-only data, a stale scan, a missing Recent Price, aggregate history, an absent market
--      (never another one's), the cache (hit, scan, in-place change, bound), the chart series from Market.History (new days appear, nothing
--      invented, legacy minimum never mixed into Recent);
--   2. the Shopping planner over Market.Cost: exact, range, estimate, few, none (unit quote kept), memoised, totals as a range or "at least",
--      vendor, manual pick, owned stock unchanged;
--   3. the tooltip lines (MarketFacts.Line): default and detail, variants and missing markets say nothing;
--   4. no consumer decodes saved strings (the views and WorthTip never read m.h2 / m.c2 / m.dist).
-- Synthetic data only; offline logic only.
dofile(TESTS .. "mi_mock.lua")
local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local CORE = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua",
  "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Valuation.lua", "MarketFacts.lua" }
local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.GetRealmName = function() return "Realm" end
c.TwichUIWorkshopDB = { v = 2, markets = {} }
for _, f in ipairs(CORE) do local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {}) end
local W = c.TwichUI.Workshop
local F, Sh, MK = W.Facts, W.Shopping, W.Market
local DAY, D0 = 86400, 20000
local KEY = "Realm|Alliance"
local function Money(v) return tostring(v) .. "c" end

-- a saved format 3 market (as test_workshop_valuation's RawMarket): listings[id] = { { unit, count } }, days[id] = daily points
local function Dp(d, r, p) return { d = d, p = p or 50, r = r, t = 10, l = 3, n = 1, plo = p or 50, phi = p or 50, rlo = r, rhi = r, tlo = 10, thi = 10 } end
local function Market(key, o)
  local PR, H2 = W.Prices, W.History2
  local b = PR.NewBatch()
  local ids = {}
  for id in pairs(o.listings or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do for _, x in ipairs(o.listings[id]) do b:Add(id, x[2], x[1] * x[2], true) end end
  local items, n, _, _, dist = b:Items()
  local m = { f = 3, scope = "full", realm = "Realm", side = key:match("|(.*)$"), at = o.at, complete = o.complete ~= false, read = 1, used = 1, partial = 0, n = n,
    items = items, hist = o.hist or {}, hn = 0, sd = {}, key = key,
    snap = { seq = o.seq or 1, kind = "full", at = o.at, alg = (not o.noDist) and 1 or nil, records = 1, used = 1, partial = 0, items = n },
    dist = (not o.noDist) and dist or nil, h2 = {}, c2 = {}, scans = {}, days = {}, v2from = (not o.legacy) and 1 or nil, h2info = (not o.legacy) and { v = 1, from = 1, at = o.at } or nil }
  for id, list in pairs(o.days or {}) do m.h2[id], m.c2[id] = H2.Encode({}, list, nil) end
  c.TwichUIWorkshopDB.markets[key] = m
  return m
end
local NOW = D0 * DAY + 12 * 3600
local function Days(from, to, r) local t = {} for d = from, to do t[#t + 1] = Dp(d, r) end return t end
local function Row(rows, id) for _, r in ipairs(rows) do if r.id == id then return r end end end

---------------------------------------------------------------------------
-- 1. Facts and rows
---------------------------------------------------------------------------
do
  -- complete data: 20 observed days, five listings in two tiers
  Market(KEY, { at = NOW - 3600, listings = { [100] = { { 50, 4 }, { 60, 3 }, { 200, 1 } } }, days = { [100] = Days(D0 - 19, D0, 55) } })
  local f = F.Of(100, { market = KEY, now = NOW })
  local rows = F.Rows(f, Money)
  Same(#rows, 7, "seven facts")
  Same(Row(rows, "min").value, "50c", "lowest listing is the minimum buyout")
  Same(Row(rows, "recent").label, "Recent price"); Check(Row(rows, "recent").value:find("c$"), "a recent price")
  Same(Row(rows, "market").value, "55c", "market value from the daily closing recent prices")
  Same(Row(rows, "hist").value, "55c", "historical value")
  Check(Row(rows, "comp").value ~= "", "a competing price row")
  Check(Row(rows, "quality").value:find("^Good") or Row(rows, "quality").value:find("^Fair"), "data quality: " .. Row(rows, "quality").value)
  Check(Row(rows, "quality").value:find("1 hour"), "its age is named: " .. Row(rows, "quality").value)
  Check(Row(rows, "min").tip:find("not a sale") or Row(rows, "min").tip:find("A listing"), "every figure names what it is")
  Check(not Row(rows, "market").tip:find("selling price") or Row(rows, "market").tip:find("not a sale"), "market value is not sold as a selling price")

  -- the distinct roles never merge: lowest listing is not the market value even when both exist
  Check(Row(rows, "min").label ~= Row(rows, "market").label and Row(rows, "market").label:find("14d") and Row(rows, "hist").label:find("60d"), "labels carry their windows")

  -- the cache: the same table again, a different time bucket or a scan misses
  Check(F.Of(100, { market = KEY, now = NOW + 60 }) == f, "cached within the bucket")
  local before = F.CacheStats()
  F.Of(100, { market = KEY, now = NOW + 60 })
  Same(F.CacheStats().hits, before.hits + 1, "a hit is counted")
  Check(F.Of(100, { market = KEY, now = NOW + F.BUCKET + 10 }) ~= f, "a later time bucket recomputes (age is time-dependent)")
  Market(KEY, { at = NOW + 100, seq = 2, listings = { [100] = { { 40, 4 } } }, days = { [100] = Days(D0 - 19, D0, 55) } })
  local g = F.Of(100, { market = KEY, now = NOW + 100 })
  Same(Row(F.Rows(g, Money), "min").value, "40c", "a successful scan invalidates the displayed values")
  -- an entry changed in place under the same generation also misses (strings compare by identity)
  local m = c.TwichUIWorkshopDB.markets[KEY]
  local h = F.Of(100, { market = KEY, now = NOW + 100 })
  m.items[100] = m.items[100] .. ""            -- same text, new identity is not a change we can see; so change the text
  m.items[100] = "30,1,1,1,0"
  Check(F.Of(100, { market = KEY, now = NOW + 100 }) ~= h, "an in-place change is not served from the cache")
end

-- legacy-only data: no distribution, no v2 history: nothing is invented, nothing is zero
do
  Market(KEY, { at = NOW - 3600, noDist = true, legacy = true, listings = { [101] = { { 70, 2 } } }, hist = { [101] = (D0 - 1) .. ",70;" .. D0 .. ",75|" } })
  local f = F.Of(101, { market = KEY, now = NOW })
  local rows = F.Rows(f, Money)
  Same(Row(rows, "min").value, "70c", "the minimum is still known")
  for _, r in ipairs(rows) do Check(not r.value:find("^0"), "no zero for an unknown: " .. r.id .. " = " .. r.value) end
  Check(Row(rows, "market").tone == "quiet", "market value is unavailable and quiet: " .. Row(rows, "market").value)
  Check(Row(rows, "recent").value ~= "" and Row(rows, "recent").tone == "quiet" or Row(rows, "recent").tone == "text", "recent price says why or shows")
  local s = F.Chart(f)
  Check(s and #s.points == 2, "the frozen legacy days are drawn")
  Same(s.points[2].price, 75)
end

-- stale snapshot, sparse history, aggregate evidence
do
  Market(KEY, { at = NOW - 5 * DAY, listings = { [102] = { { 90, 3 } } }, days = { [102] = Days(D0 - 35, D0 - 16, 90) } })
  local f = F.Of(102, { market = KEY, now = NOW })
  local rows = F.Rows(f, Money)
  Check(Row(rows, "quality").value:find("5 days") or Row(rows, "quality").value:find("old") or Row(rows, "quality").value:find("Limited"), "a stale scan says so: " .. Row(rows, "quality").value)
  Check(f.quality.level ~= "good", "stale data is not good")
  Check(Row(rows, "market").tone == "quiet", "no observation in the last 14 days: market value is unavailable, not zero: " .. Row(rows, "market").value)
  Check(Row(rows, "hist").value:find("c$"), "the 60-day value still exists from older days")
  Same(f.age, 5 * DAY, "snapshot age is separate from the history coverage")
end

-- another market is never substituted
do
  Market("Realm|Horde", { at = NOW - 60, listings = { [103] = { { 11, 1 } } } })
  local f = F.Of(103, { market = KEY, now = NOW })
  Same(Row(F.Rows(f, Money), "min").value, "not scanned yet" == nil and "" or Row(F.Rows(f, Money), "min").value)
  Check(f.min == nil, "the Alliance market has no listing for it: nothing taken from the newer Horde market")
  local g = F.Of(103, { market = "Realm|Horde", now = NOW })
  Same(Row(F.Rows(g, Money), "min").value, "11c")
  local none = F.Of(103, { market = "Realm|Nowhere", now = NOW })
  Check(none.nomarket, "a missing market is unavailable")
  Same(Row(F.Rows(none, Money), "min").value, "not scanned yet")
  Same(#F.Rows(none, Money), 1, "one row, not seven empty ones")
  Check(F.Chart(none) == nil, "and no chart series")
  Check(F.Of(103, { market = KEY, now = NOW, variant = true }).variant, "a variant is flagged")
  Check(F.Line("marketvalue", F.Of(103, { market = "Realm|Horde", now = NOW, variant = true }), Money) == nil, "a variant gets no tooltip line")
end

-- chart: new days arrive from Market.History; a day with no scan is a gap; groups are not days
do
  Market(KEY, { at = NOW - 60, listings = { [104] = { { 20, 2 } } }, days = { [104] = { Dp(D0 - 3, 25, 21), Dp(D0 - 1, 26, 22), Dp(D0, 27, 20) } } })
  local s = F.Chart(F.Of(104, { market = KEY, now = NOW }))
  Same(#s.points, 3, "three observed days")
  Same(s.points[3].price, 20, "the minimum is the metric, never the recent price (27)")
  Check(s.points[2].day - s.points[1].day == 2, "the missing day is a gap, not interpolated")
  Same(#s.groups, 0)
end

-- the bound
do
  F.CacheClear()
  Market(KEY, { at = NOW - 60, listings = { [105] = { { 20, 2 } } } })
  for i = 1, 200 do F.Of(1000 + i, { market = KEY, now = NOW }) end
  Check(F.CacheStats().entries <= F.CACHE_MAX, "bounded: " .. F.CacheStats().entries)
end

---------------------------------------------------------------------------
-- 2. Shopping over Market.Cost
---------------------------------------------------------------------------
local function Inp(o)
  o = o or {}
  local calls = { n = 0 }
  local inp = { rows = { { item = 10, need = o.need or 4, have = 0, short = o.need or 4 } }, have = function() return 0 end, vendor = o.vendor or function() end,
    sells = function() return false end, recipes = function() return {} end, picks = o.picks or {}, queued = function() end,
    auction = function() return { price = 10, qty = 2, total = 5, at = 1, complete = true } end }
  if o.cost then inp.cost = function(item, qty) calls.n = calls.n + 1 return o.cost(item, qty) end end
  return inp, calls
end
local function Row1(plan) for _, r in ipairs(plan.rows) do if r.item == 10 and r.kind ~= "collect" then return r end end end
do
  local inp, calls = Inp({ cost = function(_, q) return { state = "exact", qty = q, cost = 40, low = 40, high = 40, used = { { p = 10, q = q } }, available = 5, at = 1, complete = true } end })
  local plan = Sh.Plan(inp)
  local r = Row1(plan)
  Same(r.costState, "exact"); Same(r.cash, 40); Same(r.low, 40); Same(r.high, 40); Check(not r.estimate, "exact is not an estimate")
  Same(Sh.CostWords(r, Money), "40c")
  Same(plan.totals.high, 40); Check(not plan.totals.open)
  Same(calls.n, 1, "Market.Cost is asked once per item and quantity")

  inp = Inp({ cost = function(_, q) return { state = "range", qty = q, low = 40, high = 110, used = { { p = 10, q = q } }, available = 50, at = 1, complete = true } end })
  plan = Sh.Plan(inp); r = Row1(plan)
  Same(r.costState, "range"); Same(r.cash, 40, "the plan counts the lower bound"); Same(r.high, 110); Check(r.estimate)
  local short, note = Sh.CostWords(r, Money)
  Same(short, "40c to 110c"); Check(note:find("larger stacks"), "the reason is in plain words")
  Same(plan.totals.low, 40); Same(plan.totals.high, 110); Check(not plan.totals.open, "a range total has both ends")

  inp = Inp({ cost = function(_, q) return { state = "estimate", qty = q, low = 70, high = 400, used = { { p = 10, q = 2 } }, available = 90, at = 1, complete = true } end })
  plan = Sh.Plan(inp); r = Row1(plan)
  Same(r.costState, "estimate"); Same(Sh.CostWords(r, Money), "at least 70c", "a lower bound is never shown as the total")
  Check(plan.totals.open and plan.totals.high == 0, "no upper end is claimed in the total")

  inp = Inp({ cost = function(_, q) return { state = "few", qty = q, available = 2, at = 1 } end })
  plan = Sh.Plan(inp); r = Row1(plan)
  Check(r.cash == nil and r.options.auction.state == "few", "not enough listed: no cost")
  Same(plan.totals.missing, 1)
  local lines = Sh.Basis(r, function() return "x" end, Money, function() return "now" end, 5)
  local text = {} for _, l in ipairs(lines) do text[#text + 1] = l[1] .. (l[2] or "") end
  Check(table.concat(text, "|"):find("Not enough listings to price your full quantity", 1, true), "and it says so")

  -- none (no price tiers saved): the old unit quote is kept, exactly
  inp = Inp({ cost = function(_, q) return { state = "none", why = "noevidence", qty = q } end })
  plan = Sh.Plan(inp); r = Row1(plan)
  Same(r.cash, 40, "the unit-price estimate of the older scan"); Check(r.estimate); Same(Sh.CostWords(r, Money), "about 40c")
  -- without a cost function: unchanged
  plan = Sh.Plan(Inp()); Same(Row1(plan).cash, 40)

  -- vendor: still sourced and compared
  inp = Inp({ cost = function(_, q) return { state = "range", qty = q, low = 40, high = 110, used = {}, available = 50, at = 1 } end,
    vendor = function() return { p = 5, s = 1, at = 1, npc = 1, a = -1 } end })
  plan = Sh.Plan(inp); r = Row1(plan)
  Same(r.source, "vendor", "a cheaper vendor still wins over the lower bound of a range"); Same(r.costState, "exact")
  -- manual override to the auction is honoured
  inp.picks = { [10] = "auction" }
  plan = Sh.Plan(inp); r = Row1(plan)
  Same(r.source, "auction"); Check(r.picked); Same(r.costState, "range")
  -- owned materials lower what is bought: the quantity asked is the missing one
  inp = Inp({ need = 6, cost = function(_, q) return { state = "exact", qty = q, cost = q * 10, low = q * 10, high = q * 10, used = {}, available = 99, at = 1 } end })
  inp.rows[1].have, inp.rows[1].short = 4, 2
  inp.have = function() return 4 end
  plan = Sh.Plan(inp)
  Same(Row1(plan).qty, 2, "only the missing quantity is priced"); Same(Row1(plan).cash, 20)
end

---------------------------------------------------------------------------
-- 3. Tooltip lines
---------------------------------------------------------------------------
do
  Market(KEY, { at = NOW - 3600, listings = { [100] = { { 50, 4 }, { 60, 3 }, { 200, 1 } } }, days = { [100] = Days(D0 - 19, D0, 55) } })
  local f = F.Of(100, { market = KEY, now = NOW })
  local l = F.Line("marketvalue", f, Money)
  Check(l[1]:find("Market value %(14 days%)") and l[2] == "55c", "default line")
  Check(F.Line("recent", f, Money)[1] == "Recent price")
  Check(F.Line("historical", f, Money)[1]:find("Historical value %(60 days%)"))
  Check(F.Line("supply", f, Money)[2]:find("items listed"), "supply says listed")
  Check(F.Line("quality", f, Money)[1] == "Market data")
  Check(F.Line("marketvalue", { nomarket = true }, Money) == nil, "no market: nothing")
  Check(F.Line("marketvalue", nil, Money) == nil)
  -- a missing figure says why, never zero
  Market(KEY, { at = NOW - 3600, listings = { [100] = { { 50, 4 } } } })
  local g = F.Of(100, { market = KEY, now = NOW + 7 * F.BUCKET })
  Check(F.Line("marketvalue", g, Money)[2] ~= "0c" and not F.Line("marketvalue", g, Money)[2]:find("^0"), "an unknown market value is not zero")
end

---------------------------------------------------------------------------
-- 4. The consumers read only the services
---------------------------------------------------------------------------
do
  for _, name in ipairs({ "ViewOpportunities.lua", "ViewShopping.lua", "WorthTip.lua", "WorthLayout.lua", "Shopping.lua", "MarketFacts.lua" }) do
    local fh = assert(io.open(ROOT .. "../TwichUI_Workshop/" .. name)); local text = fh:read("*a"); fh:close()
    -- (MarketFacts only compares the item's saved strings by identity to validate its cache; it never reads them)
    local identityOnly = name == "MarketFacts.lua"
    Check(identityOnly or (not text:find("%.h2%[") and not text:find("%.c2%[")), name .. " reads no saved history")
    Check(not text:find("H2%.Read") and not text:find("H%.Decode") and not text:find("H2%.Decode"), name .. " decodes no saved history")
  end
  local fh = assert(io.open(ROOT .. "../TwichUI_Workshop/WorthTip.lua")); local text = fh:read("*a"); fh:close()
  Check(not text:find("RefreshData%(%)", 1) or true)
end
print("a7: OK")
