-- Market data foundation 2.0, milestone A3 (docs/workshop/market-data-foundation-v2.md sections 3.3, 5, 12): the price distribution a full scan
-- keeps beside the minimum entries, and the Recent Price (the band mean) in it. Against INDEPENDENT second derivations:
--   * the 22 worked examples of section 5.2: the expected Recent Prices come from the document (worked out there by a throwaway prototype and
--     re-derived here by an exact-fraction Python script on expanded item lists, see docs/workshop/market-data-foundation-v2.md, A3 as built);
--   * TwichUI_TestLab/Reference.lua REF.ExpectDist: lines up every item and reads quartiles, anchor, band and near-price supply off ranks;
--   * the released 1.3 code (tests/fixtures/workshop_v13) for the unchanged minimum entries, byte for byte.
-- It also covers: the strict greater-than at the 25% boundary, conservation and ordering invariants, shuffle and duplicate properties, the
-- saved text and its strict reader, numeric limits, malformed records, the stepped finalization (work per step bounded, same answer at any step
-- size), failure of the build, and the whole scan against a fake auction house (replacement of the previous distribution, other markets, closing
-- the auction house at every phase, a dropped or failing commit, the 1.3 write protection).
-- Synthetic: logic proved offline; nothing here says what the real auction house returns or how fast the client runs it.
--
-- SEEDS (fixed): random houses 7700000+i, adversarial markets 7710000+i.  RERUN one:  DIST_SEED=7700042 (cd tests && lua5.1 -e '...' test_workshop_dist.lua)
-- STRESS (optional, not part of ./tests/run.sh's time budget):  DIST_SCENARIOS=3000
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local ONLY = tonumber(os.getenv("DIST_SEED") or "")
local N = tonumber(os.getenv("DIST_SCENARIOS") or "") or 150
local LAB = ROOT .. "../TwichUI_TestLab/"
local NOW = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua",
    "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }
local V13 = { "Data.lua", "Materials.lua", "Queue.lua", "History.lua", "Prices.lua", "Scan.lua", "Market.lua" }

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

-- a client with the Workshop (current files or the released 1.3 files), a fake auction house, a virtual clock and timers
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
  if which ~= "v13" then
    for _, f in ipairs({ "Fixtures.lua", "Reference.lua" }) do
      local chunk = assert(loadfile(LAB .. f)); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
    end
  end
  local t = { c = c, ah = ah, W = c.TwichUI.Workshop, TL = c.TwichUI.TestLab }
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
  function t.Tick()
    local best, bi
    for i, tm in ipairs(timers) do if not best or tm.at < best.at then best, bi = tm, i end end
    if not best then return false end
    table.remove(timers, bi)
    if best.at > clock then clock = best.at end
    best.fn()
    return true
  end
  function t.DB() return t.c.TwichUIWorkshopDB end
  return t
end

local T = Setup("now")
local W, TL = T.W, T.TL
local PR, D, FX, REF = W.Prices, W.Dist, TL.Fixtures, TL.Reference
local T13 = Setup("v13")

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
-- A listing of q items at u copper each (the buyout is u x q: the unit price is exact)
local function L(u, q) return { item = 1, count = q, buyout = u * q, info = true } end
local function BatchOf(Pr, records)
  local b = Pr.NewBatch()
  for _, r in ipairs(records) do b:Add(r.item, r.count, r.buyout, r.info) end
  return b
end
local function Build(records)
  local b = BatchOf(PR, records)
  local items, n, over, dropped, dist = b:Items()
  return items, dist, b, n
end
local function Show(records)
  local out = {}
  for i, r in ipairs(records) do out[i] = ("%s x%s for %s"):format(tostring(r.item), tostring(r.count), tostring(r.buyout)) end
  return table.concat(out, "; ")
end

---------------------------------------------------------------------------
-- 0. Constants and packing
---------------------------------------------------------------------------
do
  Same(D.ALG, 1); Same(D.TIERS, 6); Same(D.SHIFT, 2 ^ 18)
  Check(D.MAX_RECORDS < D.SHIFT and D.MAX_RECORDS >= 250000, "the packed listings field holds every record a scan reads (Scan.MAX_RECORDS is 250,000)")
  Same(D.MAX_COPPER, PR.MAX_COPPER, "the same copper limit in both files")
  -- the most a packed tier can hold: SHIFT-1 listings of the largest stacks, exactly
  local q, l = D.Unpack(D.MAX_RECORDS * PR.MAX_COUNT * D.SHIFT + D.MAX_RECORDS)
  Same(q, D.MAX_RECORDS * PR.MAX_COUNT); Same(l, D.MAX_RECORDS)
  Check(D.MAX_RECORDS * PR.MAX_COUNT * D.SHIFT + D.MAX_RECORDS < 2 ^ 53, "and it is exact in a double")
  for _, pair in ipairs({ { 1, 1 }, { 2, 262143 }, { 123456789, 7 }, { 2600000000, 262143 } }) do
    local a, b = D.Unpack(pair[1] * D.SHIFT + pair[2])
    Same(a, pair[1]); Same(b, pair[2])
  end
end

---------------------------------------------------------------------------
-- 1. The 22 worked examples (section 5.2): Recent Price, and the whole entry against the reference model
---------------------------------------------------------------------------
local CASES = {
  { "1 healthy spread", { { 9500, 5 }, { 9800, 5 }, { 10000, 10 }, { 10200, 10 }, { 10500, 10 }, { 11000, 5 } }, 9741 },
  { "2 one 1c listing, deep market", { { 1, 1 }, { 5000, 40 }, { 5200, 10 } }, 5000 },
  { "3 thin, one cheap unit", { { 1000, 1 }, { 5000, 3 } }, 5000 },
  { "4 one absurd high listing", { { 5000, 10 }, { 9990000, 1 } }, 5000 },
  { "5a large wall just below", { { 4900, 200 }, { 5200, 5 } }, 4900 },
  { "5b few cheap under a wall", { { 4500, 5 }, { 6000, 200 } }, 5878 },
  { "6 two clusters", { { 100000, 10 }, { 200000, 90 } }, 166667 },
  { "7 one listing", { { 300000, 1 } }, 300000 },
  { "8 100 listings 1c apart", (function() local t = {} for i = 0, 99 do t[#t + 1] = { 5000 + i, 1 } end return t end)(), 5015 },
  { "9 one 200-stack vs singles", { { 4000, 200 }, { 6000, 5 } }, 4000 },
  { "10 rare, far apart", { { 800000, 1 }, { 1500000, 1 }, { 4000000, 1 } }, 800000 },
  { "11 bait volume, 29% of supply", { { 2000, 8 }, { 5000, 20 } }, 2143 },
  { "12 bait volume, 20% of supply", { { 2000, 5 }, { 5000, 20 } }, 5000 },
  { "13 thin, two far apart", { { 10000, 1 }, { 40000, 1 } }, 10000 },
  { "14 thin, one 1c among three", { { 1, 1 }, { 9000, 1 }, { 9500, 1 } }, 1 },
  { "15 widely separated equal clusters", { { 10000, 50 }, { 1000000, 50 } }, 10000 },
  { "16 large cheap wall", { { 4000, 1000 }, { 5000, 20 } }, 4000 },
  { "17 large expensive wall", { { 5000, 20 }, { 9000, 1000 } }, 8739 },
  { "18 manipulator: 24% just over half", { { 2510, 12 }, { 5000, 38 } }, 3008 },
  { "19 manipulator: 26% just over half", { { 2510, 13 }, { 5000, 37 } }, 2842 },
  { "20 manipulator: 24% just under half", { { 2490, 12 }, { 5000, 38 } }, 5000 },
  { "21 one 1000-stack cheap, two singles", { { 3000, 1000 }, { 5000, 1 }, { 5100, 1 } }, 3000 },
  { "22 three singles under a 1000-stack", { { 5000, 3 }, { 9000, 1000 } }, 8960 },
}
do
  Same(#CASES, 23, "22 cases (5 has two parts)")
  for _, case in ipairs(CASES) do
    local name, tiers, expected = case[1], case[2], case[3]
    local records, ref = {}, {}
    for _, x in ipairs(tiers) do records[#records + 1] = L(x[1], x[2]); ref[#ref + 1] = { b = x[1] * x[2], c = x[2] } end
    local items, dist = Build(records)
    local e = REF.ExpectDist(ref)
    Same(e.r, expected, name .. ": the reference model reproduces the document's Recent Price")
    if #tiers == 1 then
      Same(dist[1], nil, name .. ": one price, no distribution entry")
    else
      local d, why = D.Decode(dist[1])
      Check(d, name .. ": the entry decodes: " .. tostring(why))
      Same(d.r, expected, name .. ": Recent Price")
      Same(dist[1], e.text, name .. ": the whole saved text equals the reference model's")
      Same(d.min, tiers[1][1], name .. ": the minimum")
    end
  end
  -- the rounding corner cases are not in the table: a hand-worked mean that is not whole
  -- 1000 2000 3000 4000 (one each): T = 4, a = 2000 (first running total strictly above 1), the band 1.2 items = 1000 + 0.2 x 2000, mean 3500/3 = 1166.67
  local items, dist = Build({ L(1000, 1), L(2000, 1), L(3000, 1), L(4000, 1) })
  local d = D.Decode(dist[1])
  Same(d.r, 1167); Same(d.a, 2000); Same(d.q25, 1000, "q25 is the nearest rank (running total 1 >= 1)"); Same(d.q50, 2000); Same(d.q75, 3000)
  Check(d.a ~= d.q25, "the anchor and q25 differ exactly when a running total is exactly a quarter")
  -- ten singles 100..109: a = 102 (the third), the band is exactly 3 items, (100 + 101 + 102) / 3 = 101
  local rec = {}
  for i = 0, 9 do rec[#rec + 1] = L(100 + i, 1) end
  d = D.Decode(select(2, Build(rec))[1])
  Same(d.r, 101); Same(d.a, 102); Same(d.q25, 102, "T = 10: rank ceil(2.5) = 3 is also the anchor"); Same(d.near, 10, "1.10 x 101 = 111.1: every price from 100 to 109 is near")
end

---------------------------------------------------------------------------
-- 2. The saved text: exact forms, and the strict reader
---------------------------------------------------------------------------
do
  -- case 1, worked out by hand and by the Python script: all single listings of a tier, no tail
  local _, dist = Build((function() local r = {} for _, x in ipairs(CASES[1][2]) do r[#r + 1] = L(x[1], x[2]) end return r end)())
  Same(dist[1], "1,9741,10000,10000,10200,10500,11000,40|9500:5:1;9800:5:1;10000:10:1;10200:10:1;10500:10:1;11000:5:1", "case 1, no tail, m omitted (one listing per tier)")
  -- tiers with several listings carry the largest one; eight prices give a tail
  local rec = { L(100, 3), L(100, 7), L(100, 2), L(200, 1) }
  for u = 300, 800, 100 do rec[#rec + 1] = L(u, 5) end
  local _, dist2 = Build(rec)
  local e = dist2[1]
  Check(e:find("|100:12:3:7;200:1:1;300:5:1;", 1, true), "the first tier: 12 items, 3 listings, largest 7; the others one listing each: " .. e)
  Check(e:match("|1[%d]*:1$") == nil and e:match("|10:2$") ~= nil, "the tail: the 7th and 8th tiers hold 10 items in 2 listings: " .. e)
  local d = D.Decode(e)
  Same(d.tq, 10); Same(d.tl, 2); Same(#d.tiers, 6); Same(d.t, 12 + 1 + 5 * 6); Same(d.l, 3 + 1 + 6)
  Same(d.tiers[1].m, 7); Same(d.tiers[2].m, 1, "a one-listing tier reads back with m = q")
  -- the canonical encoding round trip through the reference model's own writer
  local ref = {}
  for _, r in ipairs(rec) do ref[#ref + 1] = { b = r.buyout, c = r.count } end
  Same(e, REF.ExpectDist(ref).text)

  -- the reader refuses everything that is not exactly what the writer makes
  local good = e
  local function Bad(name, text)
    local d2, why = D.Decode(text)
    Check(d2 == nil, name .. " must be refused: " .. tostring(text))
    Check(type(why) == "string", name .. " says why")
  end
  Check(D.Decode(good), "the good one reads")
  Bad("not a string", 7); Bad("empty", ""); Bad("nil", nil); Bad("too long", good .. string.rep("1", 420))
  Bad("another algorithm", good:gsub("^1,", "2,"))
  Bad("no tiers", "1,100,100,100,100,100,100,1|")
  Bad("one tier only", "1,100,100,100,100,100,100,1|100:1:1")
  Bad("seven tiers", good:gsub("|10:2$", ";900:1:1"))
  Bad("tier order", (good:gsub("100:12:3:7;200:1:1", "200:1:1;100:12:3:7")))
  Bad("equal prices", (good:gsub("200:1:1", "100:1:1")))
  Bad("l = 1 with an m", (good:gsub("200:1:1", "200:1:1:1")))
  Bad("l > 1 without m", (good:gsub("100:12:3:7", "100:12:3")))
  Bad("m above q", (good:gsub("100:12:3:7", "100:12:3:13")))
  Bad("m too small for l", (good:gsub("100:12:3:7", "100:12:3:3")))
  Bad("more listings than items", (good:gsub("100:12:3:7", "100:12:13:7")))
  Bad("zero items", (good:gsub("200:1:1", "200:0:1")))
  Bad("a tail with only five tiers before it", (good:gsub(";600:5:1", "")))
  Bad("a tail of nothing", (good:gsub("|10:2$", "|0:0")))
  Bad("a tail with more listings than items", (good:gsub("|10:2$", "|2:10")))
  Bad("a text after the tail", good .. "|1:1")
  Bad("a leading zero", (good:gsub("^1,", "1,0")))
  Bad("a sign", (good:gsub("^1,", "1,-")))
  Bad("a fraction", (good:gsub("^1,", "1,1.")))
  Bad("a letter", (good:gsub("^1,", "1,x")))
  Bad("a hi that does not match the tiers", (good:gsub("^(1,%d+,%d+,%d+,%d+,%d+,)(%d+)", "%1" .. "9")))
  Bad("a Recent Price above the median", (good:gsub("^1,%d+", "1,99999")))
  Bad("a Recent Price below the minimum", (good:gsub("^1,%d+", "1,99")))
  Bad("a quartile out of order", (good:gsub("^(1,%d+,%d+,)%d+,%d+,%d+", "%1" .. "800,300,200")))
  Bad("a near above all items", (good:gsub(",(%d+)|", ",9999|", 1)))
  Bad("a quartile not matching its tier", (good:gsub("^(1,%d+,%d+,)%d+", "%1" .. "250")))
  -- a number beyond the copper limit
  Bad("copper over the limit", (good:gsub("^1,%d+", "1,100000000000")))
  -- no tail: the whole entry is worked out again from the tiers
  local _, d3 = Build({ L(100, 1), L(250, 4), L(400, 2) })
  Check(D.Decode(d3[1]))
  Bad("a wrong Recent Price when every tier is there", (d3[1]:gsub("^1,%d+", "1,101")))
  Bad("a wrong near when every tier is there", (d3[1]:gsub(",(%d+)|", ",7|", 1)))
end

---------------------------------------------------------------------------
-- 3. Numbers at the limits (expected values from exact fractions in Python, not from the code under test)
---------------------------------------------------------------------------
do
  local function Stats(tiers)
    local ps, qs, ls = {}, {}, {}
    for i, x in ipairs(tiers) do ps[i], qs[i], ls[i] = x[1], x[2], x[3] or 1 end
    return D.Stats(ps, qs, ls, #tiers)
  end
  local r, a, _, _, _, hi, _, t, _, exact = Stats({ { 99999999990, 3 }, { 99999999995, 5 }, { 99999999999, 2 } })
  Same(r, 99999999990); Same(a, 99999999990); Same(hi, 99999999999); Same(t, 10); Check(exact)
  r, a, _, _, _, _, _, t, _, exact = Stats({ { 99999999000, 600000000 }, { 99999999999, 1900000000 } })
  Same(r, 99999999200, "mean 99999999199.8: exact although the products would not be, thanks to working from the cheapest eligible price"); Same(a, 99999999999); Check(exact)
  r, a, _, _, _, _, _, t, _, exact = Stats({ { 50000000000, 600000000 }, { 99999999999, 1900000000 } })
  Check(not exact, "products beyond 2^53 are reported as not exact")
  Check(math.abs(r - 60000000000) <= 1, "and still within one copper of the exact 59999999999.8: " .. r)
  r, a, _, _, _, _, _, t, _, exact = Stats({ { 50000000001, 700000000 }, { 70000000007, 300000000 }, { 99999999999, 1500000000 } })
  Check(math.abs(r - 51333333335) <= 1 and a == 50000000001, "three tiers, mean 51333333334.73: " .. r)
  r = Stats({ { 1, 2500000000 }, { 2, 100 }, { 99999999999, 1 } })
  Same(r, 1, "2.5 billion items at one copper and a handful dear")
  r = Stats({ { 1, 10 }, { 99999999999, 90 } })
  Same(r, 99999999999, "a cheap bait of 10% under half the anchor is ignored")

  -- through the batch: the dearest allowed buyout, one item, and the largest stacks
  local items, dist = Build({ { item = 1, count = 1, buyout = 99999999999 }, { item = 1, count = 10000, buyout = 99999999999 }, { item = 1, count = 3, buyout = 99999999998 } })
  Same(items[1], "10000000,10000,3,10004,33333333333", "the legacy entry at the limits: 99999999999 / 10000 = 9999999.9999 is the cheapest, 99999999998 / 3 = 33333333332.67 the next")
  local d = D.Decode(dist[1])
  Check(d, "the entry reads"); Same(d.hi, 99999999999); Same(d.t, 10004); Same(d.l, 3); Same(d.tiers[1].p, 10000000, "99999999999 / 10000 rounds UP to 10000000")
  Check(not dist[1]:find("e%+"), "no exponent notation in the saved text")

  -- 6 tiers of the largest stack at a time keep exact counts
  local records = {}
  for u = 1, 8 do for _ = 1, 50 do records[#records + 1] = { item = 1, count = 10000, buyout = u * 10000 } end end
  local _, dist2 = Build(records)
  local d2 = D.Decode(dist2[1])
  Same(d2.t, 8 * 50 * 10000); Same(d2.l, 400); Same(d2.tiers[1].q, 500000); Same(d2.tiers[1].m, 10000); Same(d2.tq, 2 * 500000); Same(d2.tl, 100)
end

---------------------------------------------------------------------------
-- 4. Random houses against the reference model, the invariants, and the 1.3 minimum entries byte for byte
---------------------------------------------------------------------------
local failures = 0
local function Report(kind, seed, item, records, what, expected, actual)
  error(("%s MISMATCH seed=%s item=%s: %s\n  input:    %s\n  expected: %s\n  actual:   %s\n  rerun:    DIST_SEED=%s"):format(
    kind, tostring(seed), tostring(item), what, Show(records), tostring(expected), tostring(actual), tostring(seed)), 0)
end

-- check one item's records (priced listings, in the order given) against everything
local function CheckItem(kind, seed, item, listings, entry, dist1)
  local ref = {}
  for _, r in ipairs(listings) do ref[#ref + 1] = { b = r.buyout, c = r.count } end
  local e = REF.ExpectDist(ref)
  local p = tonumber(entry:match("^(%d+),"))
  if e.distinct < 2 then
    if dist1 ~= nil then Report(kind, seed, item, listings, "one price tier must have no distribution entry", "nil", dist1) end
    Same(p, e.min, "the minimum of a one-tier item")
    return
  end
  if dist1 ~= e.text then Report(kind, seed, item, listings, "the saved distribution text differs from the reference model's", e.text, dist1) end
  local d = D.Decode(dist1)
  if not d then Report(kind, seed, item, listings, "the entry does not read", "a distribution", "nil") end
  -- invariants
  local inv = "min <= q25 <= a <= q50 <= q75 <= hi, min <= r <= q50"
  if not (d.min <= d.q25 and d.q25 <= d.a and d.a <= d.q50 and d.q50 <= d.q75 and d.q75 <= d.hi and d.min <= d.r and d.r <= d.q50) then
    Report(kind, seed, item, listings, "ordering invariant: " .. inv, "ordered", dist1)
  end
  if p ~= d.min then Report(kind, seed, item, listings, "tier 1 is the legacy minimum entry's price", p, d.min) end
  local tq, tl = d.tq, d.tl
  for _, tr in ipairs(d.tiers) do tq, tl = tq + tr.q, tl + tr.l end
  if tq ~= e.t or tl ~= e.l then Report(kind, seed, item, listings, "conservation: tiers + tail = items and listings", e.t .. "/" .. e.l, tq .. "/" .. tl) end
  local lt, ll = entry:match("^%d+,%d+,(%d+),(%d+)")
  if tonumber(ll) ~= e.t or tonumber(lt) ~= e.l then Report(kind, seed, item, listings, "the minimum entry holds the same totals", e.l .. "/" .. e.t, lt .. "/" .. ll) end
  for i = 2, #d.tiers do
    if d.tiers[i].p <= d.tiers[i - 1].p then Report(kind, seed, item, listings, "tiers ascend", "ascending", dist1) end
  end
end

-- the released 1.3 batch on the same records: its entries must equal ours, byte for byte
local function Legacy(records)
  local b = BatchOf(T13.W.Prices, records)
  return (b:Items())
end

local function RunHouse(seed, kind, records, ids)
  -- priced listings per item, in order
  local priced = {}
  for _, r in ipairs(records) do
    if r.intent == nil or r.intent == "priced" then
      priced[r.item] = priced[r.item] or {}
      table.insert(priced[r.item], r)
    end
  end
  local items, dist, b = Build(records)
  local legacy = Legacy(records)
  for id, entry in pairs(legacy) do
    if items[id] ~= entry then Report(kind, seed, id, records, "the minimum entry is not byte for byte what 1.3 writes", entry, items[id]) end
  end
  for id in pairs(items) do if legacy[id] == nil then Report(kind, seed, id, records, "an item 1.3 would not price", "nil", items[id]) end end
  for id, listings in pairs(priced) do CheckItem(kind, seed, id, listings, items[id], dist[id]) end
  for id in pairs(dist) do if not priced[id] then Report(kind, seed, id, records, "a distribution for an item with no priced listing", "nil", dist[id]) end end
  -- shuffle invariance: the same records in another order give the same entries and distributions
  local rng = FX.Rng(seed + 99)
  local shuffled = {}
  for i, r in ipairs(records) do shuffled[i] = r end
  rng:Shuffle(shuffled)
  local items2, dist2 = Build(shuffled)
  for id, e in pairs(items) do
    if items2[id] ~= e then Report(kind, seed, id, shuffled, "shuffle changed the minimum entry", e, items2[id]) end
    if dist2[id] ~= dist[id] then Report(kind, seed, id, shuffled, "shuffle changed the distribution", tostring(dist[id]), tostring(dist2[id])) end
  end
  return items, dist, priced
end

do
  local count = 0
  local first, last = 1, N
  if ONLY then first, last = ONLY - 7700000, ONLY - 7700000 end
  for i = first, last do
    local seed = 7700000 + i
    local scn = FX.Listings(seed, { items = 1 + i % 4, records = 10 + (i * 7) % 40, tiers = 1 + i % 8, invalid = 0.1, noBuyout = 0.1 })
    RunHouse(seed, "house", scn.records, scn.ids)
    count = count + 1
  end
  io.write(("  random houses: %d scenarios\n"):format(count))
end

-- adversarial markets: walls, thin markets, one cheap or dear outlier, ties, fractional unit prices
do
  local function Gen(seed)
    local rng = FX.Rng(seed)
    local kind = rng:Pick({ "wall-cheap", "wall-dear", "thin", "low-bait", "high-outlier", "ties", "fractions", "clusters" })
    local base = rng:Pick({ 7, 90, 4000, 250000, 30000000 }) + rng:Int(0, 9)
    local recs = {}
    local function Add(u, q, extra) recs[#recs + 1] = { item = 1, count = q, buyout = u * q + (extra or 0), info = true } end
    if kind == "wall-cheap" then Add(base, rng:Int(300, 1500)); for _ = 1, rng:Int(2, 9) do Add(base + rng:Int(1, base), rng:Int(1, 20)) end
    elseif kind == "wall-dear" then for _ = 1, rng:Int(2, 9) do Add(base + rng:Int(0, math.floor(base / 3)), rng:Int(1, 20)) end; Add(base * 2, rng:Int(300, 1500))
    elseif kind == "thin" then for _ = 1, rng:Int(1, 3) do Add(base + rng:Int(0, base * 3), rng:Int(1, 3)) end
    elseif kind == "low-bait" then Add(math.max(1, math.floor(base / 2) + rng:Int(-2, 2)), rng:Int(1, 25)); for _ = 1, rng:Int(3, 8) do Add(base + rng:Int(0, 5), rng:Int(1, 10)) end
    elseif kind == "high-outlier" then for _ = 1, rng:Int(4, 12) do Add(base + rng:Int(0, 9), rng:Int(1, 10)) end; Add(base * rng:Int(50, 5000), 1)
    elseif kind == "ties" then for _ = 1, rng:Int(5, 30) do Add(base + rng:Pick({ 0, 0, 1, 2 }), rng:Pick({ 1, 5, 20 })) end
    elseif kind == "fractions" then
      for _ = 1, rng:Int(3, 12) do
        local q = rng:Pick({ 3, 7, 20 })
        Add(base + rng:Int(0, 40), q, rng:Int(-(q - 1), q - 1))
      end
    else
      for _ = 1, rng:Int(3, 8) do Add(base + rng:Int(0, 3), rng:Int(1, 15)) end
      for _ = 1, rng:Int(3, 8) do Add(base * 7 + rng:Int(0, 3), rng:Int(1, 15)) end
    end
    for _, r in ipairs(recs) do r.buyout = math.max(1, math.min(PR.MAX_COPPER, r.buyout)) end
    return kind, recs
  end
  local n = 0
  local first, last = 1, math.floor(N * 1.5)
  for i = first, last do
    local seed = 7710000 + i
    local kind, recs = Gen(seed)
    RunHouse(seed, "adversarial/" .. kind, recs)
    n = n + 1
  end
  io.write(("  adversarial markets: %d scenarios\n"):format(n))
end

-- doubling every listing doubles the items and listings and keeps the order of the statistics; scaling the prices scales Recent Price within rounding
do
  local rng = FX.Rng(7720001)
  for i = 1, 40 do
    local recs = {}
    for _ = 1, rng:Int(3, 12) do
      local u, q = rng:Int(10, 5000), rng:Pick({ 1, 2, 5, 20 })
      recs[#recs + 1] = L(u, q)
    end
    local items, dist = Build(recs)
    local doubled = {}
    for _, r in ipairs(recs) do doubled[#doubled + 1] = r; doubled[#doubled + 1] = r end
    local items2, dist2 = Build(doubled)
    local l1, t1 = items[1]:match("^%d+,%d+,(%d+),(%d+)")
    local l2, t2 = items2[1]:match("^%d+,%d+,(%d+),(%d+)")
    Same(tonumber(l2), 2 * tonumber(l1)); Same(tonumber(t2), 2 * tonumber(t1))
    if dist[1] then
      local d1, d2 = D.Decode(dist[1]), D.Decode(dist2[1])
      Same(d2.t, 2 * d1.t, "doubled items"); Same(d2.l, 2 * d1.l, "doubled listings"); Same(d2.r, d1.r, "the same market twice over has the same Recent Price")
      Same(d2.q25, d1.q25); Same(d2.q50, d1.q50); Same(d2.q75, d1.q75)
    end
    -- scaling: every unit price x 7 (exact buyouts): quantities unchanged, Recent Price within half the factor of 7 x r
    local scaled = {}
    for _, r in ipairs(recs) do scaled[#scaled + 1] = { item = 1, count = r.count, buyout = r.buyout * 7, info = true } end
    local _, dist3 = Build(scaled)
    if dist[1] then
      local d1, d3 = D.Decode(dist[1]), D.Decode(dist3[1])
      Check(math.abs(d3.r - 7 * d1.r) <= 3, ("scale invariance within rounding: %d vs 7 x %d"):format(d3.r, d1.r))
      Same(d3.t, d1.t); Same(d3.q50, 7 * d1.q50)
    end
  end
end

---------------------------------------------------------------------------
-- 5. Malformed and unusable records never reach the tiers
---------------------------------------------------------------------------
do
  local clean = { L(100, 5), L(150, 2), L(200, 1), L(400, 3) }
  local noisy = {}
  local garbage = { { item = 1, count = 0, buyout = 500 }, { item = 1, count = -3, buyout = 500 }, { item = 1, count = 2.5, buyout = 500 },
    { item = 1, count = 5, buyout = 0 / 0 }, { item = 1, count = 5, buyout = math.huge }, { item = 1, count = 5, buyout = -math.huge },
    { item = 1, count = 5, buyout = -4 }, { item = 1, count = 5, buyout = 100000000000 }, { item = 1, count = 10001, buyout = 5 },
    { item = 1, count = "5", buyout = 5 }, { item = 1, count = 5, buyout = "600" }, { item = 1, count = 5, buyout = false },
    { item = 0 / 0, count = 5, buyout = 600 }, { item = 1.5, count = 5, buyout = 600 }, { item = -1, count = 5, buyout = 600 }, { item = nil, count = 5, buyout = 600 },
    { item = 1, count = 5, buyout = 0 }, { item = 1, count = 5, buyout = nil } }
  for i, r in ipairs(clean) do noisy[#noisy + 1] = r; noisy[#noisy + 1] = garbage[(i * 5) % #garbage + 1] end
  for _, g in ipairs(garbage) do noisy[#noisy + 1] = g end
  local items, dist, b = Build(clean)
  local items2, dist2, b2 = Build(noisy)
  Same(items2[1], items[1], "garbage does not change the minimum entry"); Same(dist2[1], dist[1], "or the distribution")
  Same(b2.used, b.used); Check(b2.invalid > 0 and b2.noBuyout > 0)
  for id in pairs(items2) do Check(id == 1, "no item invented by a malformed id") end
  Same(b2.distBad, nil, "garbage does not count toward the packed record limit")
end

---------------------------------------------------------------------------
-- 6. The packed record limit: given up explicitly, never corrupted
---------------------------------------------------------------------------
do
  local saved = D.MAX_RECORDS
  D.MAX_RECORDS = 5
  local recs = { L(100, 2), L(100, 3), L(200, 1), L(200, 2), L(300, 1), L(300, 1) }
  local b = BatchOf(PR, recs)
  Same(b.distBad, "records", "the sixth priced record is more than a packed tier may hold")
  local items, n, over, dropped, dist = b:Items()
  Same(dist, nil, "no distribution at all (not a partial one)")
  D.MAX_RECORDS = saved
  local full = Build(recs)
  for id, e in pairs(full) do Same(items[id], e, "the minimum entries are untouched by the limit") end
  local job = b:ItemsJob(); Same(job.distWhy, "records")
  -- exactly at the limit is fine
  D.MAX_RECORDS = 6
  local b6 = BatchOf(PR, recs)
  Same(b6.distBad, nil); Check(select(5, b6:Items()))
  D.MAX_RECORDS = saved
end

---------------------------------------------------------------------------
-- 7. The stepped finalization: bounded work per step, the same answer at any step size
---------------------------------------------------------------------------
do
  local rng = FX.Rng(7730001)
  local recs = {}
  for item = 1, 60 do
    for k = 1, rng:Int(1, 40) do recs[#recs + 1] = { item = item, count = rng:Pick({ 1, 5, 20 }), buyout = rng:Int(5, 400) * 20, info = true } end
  end
  local b = BatchOf(PR, recs)
  local ref_items, _, _, _, ref_dist = b:Items()
  Check(next(ref_dist), "there are distributions")
  local totalTiers = 0
  for _, e in pairs(ref_dist) do totalTiers = totalTiers + #D.Decode(e).tiers end

  for _, limit in ipairs({ 400, 50, 7, 1, math.huge }) do
    local job = b:ItemsJob()
    local steps, worst = 0, 0
    repeat
      local done = job:Step(limit)
      steps = steps + 1
      if job.stepTiers > worst then worst = job.stepTiers end
      Check(job.stepTiers <= limit * (PR.TIERS_STEP / PR.ITEMS_STEP) + job.widest, "a step summarises no more tiers than its budget plus the one item that crossed it")
      Check(steps < 100000)
    until done
    local items, _, _, _, dist = job:Result()
    for id, e in pairs(ref_items) do Same(items[id], e, "step " .. tostring(limit)) end
    for id, e in pairs(ref_dist) do Same(dist[id], e, "distribution at step " .. tostring(limit)) end
    for id in pairs(dist) do Check(ref_dist[id]) end
    if limit == 400 then Check(steps > 1, "the work is split into several steps") end
    Check(job.sp == nil, "the scratch lists are released at the end")
  end
  -- a step budget counted in tiers: with a small TIERS_STEP the same market takes more steps and the same answer
  local saved = PR.TIERS_STEP
  PR.TIERS_STEP = 40
  local job, steps = b:ItemsJob(), 0
  repeat steps = steps + 1 until job:Step(400)
  PR.TIERS_STEP = saved
  local job2, steps2 = b:ItemsJob(), 0
  repeat steps2 = steps2 + 1 until job2:Step(400)
  Check(steps > steps2, "a smaller tier budget means more steps: " .. steps .. " against " .. steps2)
  local _, _, _, _, dist = job:Result()
  for id, e in pairs(ref_dist) do Same(dist[id], e) end
  -- the entry text is not built until the job runs: nothing is summarised in Add
  Same(next(b:ItemsJob().out), nil)
end

---------------------------------------------------------------------------
-- 8. A build that fails gives up the distribution and nothing else
---------------------------------------------------------------------------
do
  local recs = {}
  for item = 1, 10 do recs[#recs + 1] = L(100, 2); recs[#recs].item = item; recs[#recs + 1] = L(100 + item, 3); recs[#recs].item = item end
  local b = BatchOf(PR, recs)
  local good = select(5, b:Items())
  local entries = b:Items()
  local realEncode, calls = D.Encode, 0
  D.Encode = function(...) calls = calls + 1 if calls == 4 then error("boom") end return realEncode(...) end
  local job = b:ItemsJob()
  while not job:Step() do end
  D.Encode = realEncode
  local items, n, _, _, dist = job:Result()
  Same(dist, nil, "no distribution, not nine of ten"); Same(job.distWhy, "failed"); Same(n, 10)
  for id, e in pairs(entries) do Same(items[id], e, "every minimum entry was still built") end
  Same(calls, 4, "and nothing more was attempted after the failure")
  Check(good, "the same batch builds a distribution when nothing fails")
end

---------------------------------------------------------------------------
-- 9. Whole scans against a fake auction house
---------------------------------------------------------------------------
local function Records(list)
  local out = {}
  for _, x in ipairs(list) do out[#out + 1] = { item = x[1], count = x[2], buyout = x[3] } end
  return out
end
-- item 10: three tiers; 11: one tier (two listings); 12: two tiers; 13: one listing
local HOUSE1 = Records({ { 10, 1, 100 }, { 10, 5, 600 }, { 10, 5, 600 }, { 10, 2, 400 }, { 11, 3, 30 }, { 11, 1, 10 }, { 11, 2, 20 }, { 12, 1, 500 }, { 12, 1, 700 }, { 13, 1, 9 } })

local function RunScan(t, records, side)
  t.ah.records, t.ah.side = records, side or "Alliance"
  local SC = t.W.Scan
  Check(SC.Start({}))
  t.Fire("REPLICATE_ITEM_LIST_UPDATE")
  t.Advance(60)
  return SC
end
local KEY = "Realm|Alliance"

do
  local t = Setup("now")
  local SC, P, D = t.W.Scan, t.W.Prices, t.W.Dist   -- (this client's own Dist: a patch must be made on the copy the scan uses)
  RunScan(t, HOUSE1)
  Same(SC.state, "done", tostring(SC.why)); Same(SC.result.alg, 1, "the scan reports the algorithm of the distribution it kept")
  local m = t.DB().markets[KEY]
  Same(t.DB().v, 2); Same(m.f, 3)
  Same(m.snap.alg, 1, "a checked distribution: snap.alg = 1")
  local ids = {}
  for id in pairs(m.dist) do ids[#ids + 1] = id end
  table.sort(ids)
  Same(table.concat(ids, ","), "10,12", "entries only for items with two or more price tiers (11 has one price, 13 one listing)")
  Same(m.items[11], "10,6,3,6,0", "the minimum entries are the ones 1.3 writes (item 11: 10 copper each in all three listings: 6 items at it, 3 listings, 6 items)")
  Same(m.items[11], select(1, Legacy(HOUSE1))[11])
  for id, e in pairs(Legacy(HOUSE1)) do Same(m.items[id], e, "item " .. id .. " byte for byte") end

  local info = P.Market(KEY)
  local d10 = P.Distribution(info, 10)
  Check(d10 and not d10.single); Same(d10.min, 100); Same(d10.t, 13); Same(d10.l, 4)
  Same(d10.tiers[2].p, 120); Same(d10.tiers[2].q, 10); Same(d10.tiers[2].l, 2); Same(d10.tiers[2].m, 5); Same(d10.tiers[3].p, 200)
  local d11, why = P.Distribution(info, 11)
  Check(d11 and d11.single and d11.min == 10 and d11.t == 6 and d11.l == 3 and d11.r == 10, "an item with one price: derived from its minimum entry")
  Same(d11.tiers[1].m, nil, "its largest single listing is not known (3 listings, none stored)")
  Same(P.Distribution(info, 13).tiers[1].m, 1, "one listing: the listing is the tier")
  local nope, why2 = P.Distribution(info, 999); Same(nope, nil); Same(why2, "unlisted")

  -- the observation A4 will record from: one scan, one set of facts
  local o = P.Observation(info, 10)
  Check(o); Same(o.item, 10); Same(o.market, KEY); Same(o.seq, 1); Same(o.at, m.snap.at); Same(o.p, 100); Same(o.r, d10.r); Same(o.t, 13); Same(o.l, 4)
  Same(o.partial, false); Same(o.complete, true); Same(o.cut, false); Same(o.whole, true); Same(o.alg, 1)
  local o11 = P.Observation(info, 11); Same(o11.r, 10, "a one-price item: Recent Price is its price"); Same(o11.p, 10)
  local o0, w0 = P.Observation(info, 999); Same(o0, nil); Same(w0, "unlisted")
  local bad = {}
  for k, v in pairs(info) do bad[k] = v end
  bad.snap = { seq = 1, kind = "full", at = info.at + 5 }
  local ob, wb = P.Observation(bad, 10); Same(ob, nil); Same(wb, "inconsistent", "a snapshot that is not the market's newest scan")
  bad.snap = nil; local _, wn = P.Observation(bad, 10); Same(wn, "nosnapshot")
  bad = {}; for k, v in pairs(info) do bad[k] = v end; bad.format = 2
  local _, wf = P.Observation(bad, 10); Same(wf, "noformat")
  -- damage: an entry that does not decode is "malformed" (never repaired); a missing one for a two-price item is "missing"
  local copy = {}
  for k, v in pairs(info) do copy[k] = v end
  copy.dist = { [10] = "garbage" }
  local dm, wm = P.Distribution(copy, 10); Same(dm, nil); Same(wm, "malformed")
  local o2 = P.Observation(copy, 10); Same(o2.r, nil); Same(o2.noRecent, "malformed"); Same(o2.p, 100, "the minimum is still observed")
  local dx, wx = P.Distribution(copy, 12); Same(dx, nil); Same(wx, "missing", "item 12 has a second price in its minimum entry but no distribution entry")
  copy.dist = { [10] = (m.dist[10]:gsub("^1,%d+", "1,5000")) }
  Same(select(2, P.Distribution(copy, 10)), "malformed", "an entry that decodes but contradicts itself")
  copy.dist = {}; copy.snap = { seq = 1, kind = "full", at = info.at }
  Same(select(2, P.Distribution(copy, 10)), "noevidence", "no algorithm named: no evidence")
  Same(select(2, P.Distribution({ scope = "recipes" }, 10)), "noevidence")

  ------------------------------------------------------------------ the second scan replaces the distribution of the first
  local firstDist = {}
  for id, e in pairs(m.dist) do firstDist[id] = e end
  -- item 10 changes; 12 stops being listed; 14 appears with two tiers; 11 now has two prices
  local HOUSE2 = Records({ { 10, 1, 90 }, { 10, 1, 95 }, { 10, 4, 500 }, { 11, 1, 10 }, { 11, 1, 12 }, { 14, 2, 20 }, { 14, 1, 30 }, { 13, 1, 9 } })
  RunScan(t, HOUSE2)
  Same(SC.state, "done")
  local m2 = t.DB().markets[KEY]
  Same(m2.snap.seq, 2); Same(m2.snap.alg, 1)
  local ids2 = {}
  for id in pairs(m2.dist) do ids2[#ids2 + 1] = id end
  table.sort(ids2)
  Same(table.concat(ids2, ","), "10,11,14", "12 is gone from both tables; 11 and 14 are new")
  Same(m2.items[12], nil)
  Check(m2.dist[10] ~= firstDist[10], "item 10's distribution is the new scan's")
  Same(P.Distribution(P.Market(KEY), 10).min, 90)
  Same(P.Distribution(P.Market(KEY), 11).single, nil, "11 has two prices now")
  -- another market (Horde) does not touch the Alliance one
  local alliance = Ser(t.DB().markets[KEY])
  RunScan(t, HOUSE1, "Horde")
  Same(Ser(t.DB().markets[KEY]), alliance, "scanning another market leaves the first untouched, distribution included")
  Same(t.DB().markets["Realm|Horde"].snap.alg, 1); Same(t.DB().markets["Realm|Horde"].snap.seq, 1)
  Same(t.DB().v, 2)

  ------------------------------------------------------------------ a scan whose distribution cannot be built keeps no distribution and no algorithm
  local realEncode, n = D.Encode, 0
  D.Encode = function(...) n = n + 1 error("boom") end
  RunScan(t, HOUSE1)
  D.Encode = realEncode
  Same(SC.state, "done", "the prices are still saved"); Same(SC.result.alg, nil)
  local m3 = t.DB().markets[KEY]
  Same(m3.snap.seq, 3); Same(m3.snap.alg, nil, "no claim of algorithm 1 evidence"); Same(m3.dist, nil, "and the previous scan's distribution is not left behind")
  for id, e in pairs(Legacy(HOUSE1)) do Same(m3.items[id], e) end
  local _, wne = P.Distribution(P.Market(KEY), 10); Same(wne, "noevidence")
  local o3 = P.Observation(P.Market(KEY), 10); Same(o3.r, nil); Same(o3.noRecent, "noevidence"); Same(o3.p, 100)
end

---------------------------------------------------------------------------
-- 10. Interruption at every phase leaves the saved database as it was
---------------------------------------------------------------------------
do
  local t = Setup("now")
  local SC, P, D = t.W.Scan, t.W.Prices, t.W.Dist
  RunScan(t, HOUSE1)
  local saved = Ser(t.DB())
  -- a house big enough for several read steps and several build steps
  local big = {}
  for item = 1, 80 do for k = 1, 12 do big[#big + 1] = { item = item, count = 1 + k % 3, buyout = (50 + item + k * 7) * (1 + k % 3) } end end
  for item = 81, 400 do big[#big + 1] = { item = item, count = 1, buyout = 10 + item } end
  local stepCalls = 0
  local origNew = P.NewBatch
  P.NewBatch = function(pri)
    local b = origNew(pri)
    local own = b.ItemsJob
    b.ItemsJob = function(self)
      local j = own(self)
      local step = getmetatable(j).__index.Step
      j.Step = function(...) stepCalls = stepCalls + 1 return step(...) end
      return j
    end
    return b
  end
  local function Start()
    t.ah.records = big
    Check(SC.Start({})); t.Fire("REPLICATE_ITEM_LIST_UPDATE")
  end
  local function Settle() local g = 0 while SC.Busy() and SC.phase ~= "reading" and g < 20 do t.Tick() g = g + 1 end end

  -- (a) while listings are collected
  Start(); Settle(); Same(SC.phase, "reading"); Check(t.Tick())
  t.c.AuctionHouseFrame:Hide(); Check(t.Tick()); Same(SC.state, "interrupted")
  t.c.AuctionHouseFrame:Show(); t.Advance(10); Same(Ser(t.DB()), saved, "closed while reading: nothing written")
  -- (b) while the entries and distributions are built (between steps), then every later timer does nothing
  stepCalls = 0
  Start(); Settle()
  local g = 0
  while stepCalls == 0 and SC.Busy() and g < 50 do t.Tick() g = g + 1 end
  Same(SC.phase, "reading", "building has begun"); Check(stepCalls >= 1)
  t.c.AuctionHouseFrame:Hide(); Check(t.Tick()); Same(SC.state, "interrupted", "the next build step notices")
  local calls = stepCalls
  t.c.AuctionHouseFrame:Show(); t.Advance(10)
  Same(stepCalls, calls, "finalization does not continue after the end"); Same(Ser(t.DB()), saved, "closed while building: nothing written")
  -- (c) a new scan starts while an old one is half built: the old one's timers do nothing
  Start(); Settle(); g = 0
  while stepCalls == calls and SC.Busy() and g < 50 do t.Tick() g = g + 1 end
  Same(SC.phase, "reading", "half built: its next building timer is pending")
  t.Fire("AUCTION_HOUSE_CLOSED"); Same(SC.state, "interrupted")
  local atClose = stepCalls
  t.Advance(10)   -- the window is still shown: only the scan's own token stops the pending building timer
  Same(stepCalls, atClose, "the event ended the scan: no further finalization step runs"); Same(SC.state, "interrupted")
  -- the new scan reads a DIFFERENT house, so that old data saved for it would show
  t.ah.records = HOUSE1
  Check(SC.Start({})); t.Fire("REPLICATE_ITEM_LIST_UPDATE")
  t.Advance(60)
  Same(SC.state, "done", "the new scan is not disturbed by the old scan's pending timers")
  local m = t.DB().markets[KEY]
  Same(m.snap.seq, 2, "exactly one new scan was accepted"); Same(m.snap.alg, 1)
  local nItems = 0
  for _ in pairs(m.items) do nItems = nItems + 1 end
  Same(nItems, 4, "and it holds the NEW scan's four items, nothing of the interrupted one")
  Same(t.DB().markets[KEY].read, #HOUSE1)
  -- (d) during the commit (saving): the listings were read, so closing the auction house changes nothing
  saved = Ser(t.DB())
  Start(); Settle(); g = 0
  while SC.phase ~= "saving" and SC.Busy() and g < 400 do t.Tick() g = g + 1 end
  Same(SC.phase, "saving")
  t.Fire("AUCTION_HOUSE_CLOSED"); Same(SC.state, "scanning", "saving goes on after the auction house closes")
  t.Advance(60); Same(SC.state, "done"); Same(t.DB().markets[KEY].snap.seq, 3)
  -- (e) a failing commit step (the distribution check) writes nothing
  saved = Ser(t.DB())
  local realDecode = D.Decode
  D.Decode = function() error("boom") end
  Start(); t.Advance(60)
  D.Decode = realDecode
  Same(SC.state, "failed"); Same(SC.why, "unsaved"); Same(Ser(t.DB()), saved, "a failing step: the database is deep-equal")
  -- (f) a distribution that does not agree with its minimum entries is not saved, the scan still is
  local realBuild = P.BeginCommit
  P.BeginCommit = function(key, scan)
    if scan.dist then for id in pairs(scan.dist) do scan.dist[id] = scan.dist[id]:gsub("^1,%d+", "1,1") break end end   -- one entry now contradicts itself
    return realBuild(key, scan)
  end
  Start(); t.Advance(60)
  P.BeginCommit = realBuild
  Same(SC.state, "done"); Same(SC.result.alg, nil)
  m = t.DB().markets[KEY]
  Same(m.snap.alg, nil, "one bad entry: the whole distribution is refused"); Same(m.dist, nil)
  Same(m.snap.seq, 4)
  -- (f2) entries that read fine on their own but do not belong to their items are refused too: swapped between two items, or the right
  -- price with the wrong totals
  local function Tamper(fn)
    local realBegin = P.BeginCommit
    P.BeginCommit = function(key, scan) fn(scan) return realBegin(key, scan) end
    Start(); t.Advance(60)
    P.BeginCommit = realBegin
    Same(SC.state, "done"); Same(t.DB().markets[KEY].snap.alg, nil, "refused as a whole"); Same(t.DB().markets[KEY].dist, nil)
  end
  Tamper(function(scan)
    local ids = {}
    for id in pairs(scan.dist) do ids[#ids + 1] = id end
    table.sort(ids)
    scan.dist[ids[1]], scan.dist[ids[2]] = scan.dist[ids[2]], scan.dist[ids[1]]
  end)
  Tamper(function(scan)
    local id = next(scan.dist)
    local p = tonumber(scan.items[id]:match("^(%d+),"))
    scan.dist[id] = D.Encode({ p, p + 1000 }, { 5, 7 }, { 1, 1 }, {}, 2)   -- starts at the item's minimum, but holds 12 items in 2 listings
  end)
  P.NewBatch = origNew
  -- (g) an incomplete scan after a complete one is "kept": nothing changes
  saved = Ser(t.DB())
  RunScan(t, HOUSE1)
  saved = Ser(t.DB())
  t.ah.records = Records({ { 10, 1, 100 }, { 10, 2, 300 } })
  t.ah.records[1].hasAll = false
  Check(SC.Start({})); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(60)
  Same(SC.state, "failed"); Same(SC.why, "kept"); Same(Ser(t.DB()), saved, "kept: the complete scan and its distribution stand")
end

---------------------------------------------------------------------------
-- 11. Version 2 stays version 2, and TwichUI 1.3 still refuses to write
---------------------------------------------------------------------------
do
  local t = Setup("now")
  RunScan(t, HOUSE1)
  Same(t.DB().v, 2); Same(t.DB().markets[KEY].f, 3)
  local text = Ser(t.DB())
  local t13 = Setup("v13", assert(loadstring("return " .. text))())
  local P13 = t13.W.Prices
  Check(P13.Held(), "1.3 sees a database newer than itself")
  local ok, why = P13.Commit(KEY, { realm = "Realm", side = "Alliance", at = 5000000, complete = true, read = 1, used = 1, n = 1, items = { [10] = "1,1,1,1,0" } })
  Same(ok, false); Same(why, "held")
  ok, why = P13.BeginCommit(KEY, { realm = "Realm", side = "Alliance", at = 5000000, complete = true, read = 1, used = 1, n = 1, items = { [10] = "1,1,1,1,0" } })
  Same(ok, false); Same(why, "held")
  ok, why = t13.W.Scan.Start({}); Same(ok, false); Same(why, "held")
  Same(Ser(t13.DB()), text, "1.3 changed nothing: the distribution, the snapshot and the logs are all there")
  -- and it reads the same minimum prices
  local now = t.W.Prices.Market(KEY)
  local old = P13.Market(KEY)
  for _, id in ipairs({ 10, 11, 12, 13 }) do
    local a, b = t.W.Prices.Lookup(now, id), P13.Lookup(old, id)
    Same(a.price, b.price); Same(a.qty, b.qty); Same(a.listings, b.listings); Same(a.total, b.total); Same(a.next, b.next)
  end
end

print("PASSED test_workshop_dist")
