-- The multilevel crafting planner (P1, TwichUI_Workshop/CraftPlanner.lua; contract: docs/workshop/multilevel-crafting-planner.md)
--   A. hand-calculated chains (the arithmetic is in the comments): one, two and three levels, shared intermediates and raw materials, several
--      queued crafts, several recipes for one item, stock covering all or part, bank and guild-bank collection, overrides valid and invalid,
--      batches and leftovers, circles with and without another route, unknown prices, outputs and recipes, auction tier boundaries and whole
--      stacks (the real Market.Cost), vendor stacks, cash-best against economy-best, equal costs, the search limit, very large prices;
--   B. seeded scenarios (TwichUI_TestLab/Fixtures.lua FX.Chain) against the EXHAUSTIVE model (TwichUI_TestLab/Reference.lua section 8), for both
--      objectives: the same choices, quantities, crafts, collect rows and totals, or a report with seed, graph, stock, prices and both plans;
--   C. the feasibility invariants, checked independently on every plan of B, on larger graphs and on deliberately limited searches;
--   D. limits and malformed input (NaN, infinities, fractions, huge graphs, recipes and prices that are not numbers);
--   E. determinism, inputs never changed, the stepped job equal to the plan at once, cancelling;
--   F. compatibility: Shopping.Plan is unchanged by this file being loaded, and no window or session code calls the planner (P2 does).
-- SEEDS: chains 7540000+i (N = 200, CHAIN_SCENARIOS to change), chains with dear intermediates 7545000+i (N), larger graphs 7550000+i. RERUN: CHAIN_SEED=7540042 (cd tests && lua5.1 -e
-- 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_workshop_craftplanner.lua). Synthetic data only.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua",
  "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Scan.lua", "Market.lua", "Valuation.lua" }
local LAB = ROOT .. "../TwichUI_TestLab/"
local ONLY = tonumber(os.getenv("CHAIN_SEED") or "")
local N = tonumber(os.getenv("CHAIN_SCENARIOS") or "") or 200

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.GetRealmName = function() return "Realm" end
c.TwichUIWorkshopDB = { v = 2, markets = {} }
for _, f in ipairs(FILES) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
for _, f in ipairs({ "Fixtures.lua", "Reference.lua" }) do
  local chunk = assert(loadfile(LAB .. f)); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
end
local W = c.TwichUI.Workshop
local CP, MK, Sh = W.CraftPlanner, W.Market, W.Shopping
local FX, REF = c.TwichUI.TestLab.Fixtures, c.TwichUI.TestLab.Reference

local function Ser(v, seen)
  if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
  seen = seen or {}
  if seen[v] then return "<cycle>" end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k], seen) end
  seen[v] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

-- a saved market built from listings (as test_workshop_a7 does): listings[item] = { { unit, count } }
local MKEY, MNOW = "Realm|Alliance", FX.NOW
local function Market(listings)
  local PR = W.Prices
  local b = PR.NewBatch()
  local ids = {}
  for id in pairs(listings) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do for _, x in ipairs(listings[id]) do b:Add(id, x[2], x[1] * x[2], true) end end
  local items, n, _, _, dist = b:Items()
  local at = MNOW - 600
  c.TwichUIWorkshopDB.markets = {}
  c.TwichUIWorkshopDB.markets[MKEY] = { f = 3, scope = "full", realm = "Realm", side = "Alliance", at = at, complete = true, read = 1, used = 1, partial = 0,
    n = n, items = items, hist = {}, hn = 0, sd = {}, key = MKEY, snap = { seq = 1, kind = "full", at = at, alg = 1, records = 1, used = 1, partial = 0, items = n },
    dist = dist, h2 = {}, c2 = {}, scans = {}, days = {}, v2from = 1, h2info = { v = 1, from = 1, at = at } }
  if W.Valuation and W.Valuation.CacheClear then W.Valuation.CacheClear() end
end
local function MarketFns()
  return function(item, qty) return MK.Cost(item, qty, { market = MKEY, now = MNOW }) end,
    function(item) return MK.Price(item, { market = MKEY, now = MNOW }) end
end

---------------------------------------------------------------------------
-- The feasibility invariants (C): recomputed from the inputs, never read back from the planner's own numbers
---------------------------------------------------------------------------
-- t: { entries, bags, bank, guild, unknown, recipes = { [item] = list }, unavailable = { [id] = true } }
local function Invariants(t, r, tag)
  local function Fail(msg) error(("INVARIANT %s: %s\n  plan: %s"):format(tag, msg, Ser(r.summary)), 0) end
  if r.summary.status == "empty" then return end
  local valid = {}
  for _, e in ipairs(t.entries) do if type(e.crafts) == "number" and e.crafts >= 1 and e.crafts <= 999 and e.crafts % 1 == 0 then valid[#valid + 1] = e end end
  local need, _, _, made = REF.Combine(valid)
  local lines = {}
  for _, l in ipairs(r.items) do
    if lines[l.item] then Fail("item " .. l.item .. " has two lines (owned stock could be spent twice)") end
    lines[l.item] = l
  end
  local stepOf = {}
  for i, st in ipairs(r.crafts) do
    if stepOf[st.item] then Fail("two craft steps for " .. st.item) end
    stepOf[st.item] = st
    Same(st.order, i, tag .. ": the craft order")
  end
  -- demand: what the queue and the crafts consume of each item is what the line says is needed
  local consume = {}
  for item, n in pairs(need) do consume[item] = n end
  for _, st in ipairs(r.crafts) do
    local rec
    for _, x in ipairs(t.recipes[st.item] or {}) do if x.id == st.recipe then rec = x end end
    if not rec then Fail("craft of " .. st.item .. " by an unknown recipe " .. tostring(st.recipe)) end
    if t.unavailable and t.unavailable[rec.id] then Fail("an unavailable recipe is planned: " .. rec.id) end
    local ref = REF.ChainRecipe(rec, st.item, t.unavailable)
    if not ref then Fail("an unusable recipe is planned: " .. rec.id) end
    Same(st.perCraft, ref.per, tag .. ": output per craft")
    Same(st.produced, st.crafts * ref.per, tag .. ": produced")
    local mats = {}
    for _, rg in ipairs(st.reagents) do mats[rg.item] = rg.qty end
    for x, q in pairs(ref.mats) do
      if mats[x] ~= q * st.crafts then Fail(("craft %d: reagent %d is %s, should be %d"):format(st.recipe, x, tostring(mats[x]), q * st.crafts)) end
      consume[x] = (consume[x] or 0) + q * st.crafts
      if stepOf[x] then
        if stepOf[x].order >= st.order then Fail("craft of " .. st.item .. " comes before the craft of its reagent " .. x) end
      end
    end
  end
  for item, n in pairs(consume) do
    if n > 0 then
      local l = lines[item]
      if not l then Fail("item " .. item .. " is consumed (" .. n .. ") but has no line") end
      Same(l.need, n, tag .. ": the demand of " .. item)
    end
  end
  local cash, high, owned, missing = 0, 0, 0, 0
  for item, l in pairs(lines) do
    Check(consume[item] == l.need, tag .. ": a line for an item nothing consumes: " .. item)
    Same(l.queued, math.min(l.need, made[item] or 0), tag .. ": queued credit of " .. item)
    local net = l.need - l.queued
    local o = l.owned
    for _, x in ipairs({ o.bags, o.bank, o.guild, l.rest }) do Check(x >= 0 and x % 1 == 0, tag .. ": a negative or fractional quantity") end
    if t.unknown[item] then
      Check(o.bags + o.bank + o.guild == 0, tag .. ": an unreadable count was used")
    else
      local want = REF.Take(net, t.bags[item] or 0, t.bank[item] or 0, t.guild[item] or 0)
      if want.bags ~= o.bags or want.bank ~= o.bank or want.guild ~= o.guild then
        Fail(("owned of %d: bags/bank/guild %d/%d/%d, should be %d/%d/%d"):format(item, o.bags, o.bank, o.guild, want.bags, want.bank, want.guild))
      end
    end
    Same(l.rest, net - o.bags - o.bank - o.guild, tag .. ": what is still lacking of " .. item)
    if l.value then owned = owned + l.value elseif o.bags + o.bank + o.guild > 0 then missing = missing + 1 end
    if l.rest == 0 then
      Same(l.source, "owned", tag .. ": a covered item is neither bought nor made")
    elseif l.source == "make" then
      local st = stepOf[item]
      Check(st and st.used == l.rest, tag .. ": a made item's craft covers what is lacking")
      Check(st.produced >= l.rest and st.produced - l.rest < st.perCraft, tag .. ": crafts are the fewest that cover the need (ceil)")
      Same(st.leftover, st.produced - l.rest, tag .. ": the leftover")
    else
      Check(l.buy and l.buy.qty == l.rest, tag .. ": a bought item buys exactly what is lacking")
      if l.buy.low then
        cash = cash + l.buy.low
        if l.buy.high and high then
          Check(l.buy.high >= l.buy.low, tag .. ": a cost range runs upward")
          high = high + l.buy.high
        else high = nil end
      else
        missing = missing + 1
      end
    end
  end
  local s = r.summary
  Same(s.cash.low, cash, tag .. ": cash is the sum of what is bought")
  Same(s.cash.high, high, tag .. ": the cash upper bound is the sum of the upper bounds, open when one is open")
  Same(s.owned, owned, tag .. ": the owned value is the sum of the owned lines")
  Same(s.economic.low, cash + owned, tag .. ": economic = cash + owned value")
  Same(s.missing, missing, tag .. ": every unknown is counted")
  if missing > 0 then Check(not s.complete, tag .. ": a plan with an unknown is never complete") end
  -- the crafts that are done never depend on each other in a circle (the order above already proves it: every reagent's craft comes first)
  -- collect rows are exactly what the plan takes from storage
  local coll = {}
  for _, x in ipairs(r.collect) do coll[x.item .. ":" .. x.where] = x.qty end
  for item, l in pairs(lines) do
    Same(coll[item .. ":bank"], l.owned.bank > 0 and l.owned.bank or nil, tag .. ": collect from the bank")
    Same(coll[item .. ":guild"], l.owned.guild > 0 and l.owned.guild or nil, tag .. ": collect from the guild bank")
  end
end

---------------------------------------------------------------------------
-- B. Seeded scenarios against the exhaustive model
---------------------------------------------------------------------------
local function Seeds(base, n)
  local out = {}
  if ONLY then if ONLY > base and ONLY <= base + n then out[1] = ONLY end return out end
  for i = 1, n do out[i] = base + i end
  return out
end

local function Describe(scn)
  return ("entries=%s\n  recipes=%s\n  unavailable=%s\n  bags=%s bank=%s guild=%s unknown=%s\n  vendor=%s sells=%s\n  listings=%s\n  picks=%s"):format(
    Ser(scn.entries), Ser(scn.recipes), Ser(scn.unavailable), Ser(scn.bags), Ser(scn.bank), Ser(scn.guild), Ser(scn.unknown), Ser(scn.vendor),
    Ser(scn.sells), Ser(scn.listings), Ser(scn.picks))
end

-- production's plan in the model's terms: { [item] = "source|recipe:crafts|qty|low|high" } and the totals
local function ProdView(r)
  local per = {}
  for _, l in ipairs(r.items) do
    local x
    if l.rest == 0 then x = "covered"
    elseif l.source == "make" then x = ("make:%d:%d"):format(l.make.recipe, l.make.crafts)
    else x = ("%s:%d:%s:%s"):format(l.source, l.buy.qty, tostring(l.buy.low), tostring(l.buy.high)) end
    per[l.item] = ("%d/%d/%d/%d/%d/%s/%s"):format(l.need, l.queued, l.owned.bags, l.owned.bank, l.owned.guild, tostring(l.value), x)
  end
  local s = r.summary
  return per, ("missing=%d cashMissing=%d valueMissing=%d econ=%.0f cash=%.0f cashHigh=%s owned=%.0f crafts=%d"):format(s.missing, s.cashMissing,
    s.valueMissing, s.economic.low, s.cash.low, s.cash.high and ("%.0f"):format(s.cash.high) or "open", s.owned, s.crafts)
end
local function RefView(plan)
  local per = {}
  for item, p in pairs(plan.per) do
    local x
    if p.rest == 0 then x = "covered"
    elseif p.source == "make" then x = ("make:%d:%d"):format(plan.assign[item].r.id, p.crafts)
    else x = ("%s:%d:%s:%s"):format(p.source, p.rest, tostring(p.low), tostring(p.high)) end
    per[item] = ("%d/%d/%d/%d/%d/%s/%s"):format(p.d, p.credit, p.bags, p.bank, p.guild, tostring(p.value), x)
  end
  local k = plan.key
  return per, ("missing=%d cashMissing=%d valueMissing=%d econ=%.0f cash=%.0f cashHigh=%s owned=%.0f crafts=%d"):format(k.missing, k.cashMissing,
    k.valueMissing, k.econ, k.cash, k.cashHigh and ("%.0f"):format(k.cashHigh) or "open", k.owned, k.crafts)
end

---------------------------------------------------------------------------
-- A. Hand-calculated chains (copper; every figure worked out in the comment)
---------------------------------------------------------------------------
local function Hand(t)
  t.bags, t.bank, t.guild, t.unknown = t.bags or {}, t.bank or {}, t.guild or {}, t.unknown or {}
  t.vendor, t.sells, t.lookup, t.recipes, t.unavailable = t.vendor or {}, t.sells or {}, t.lookup or {}, t.recipes or {}, t.unavailable or {}
  local cost, price = t.cost, nil
  if t.listings then Market(t.listings) cost, price = MarketFns() end
  return {
    entries = t.entries, picks = t.picks,
    have = function(i) if t.unknown[i] then return t.unknownValue end return t.bags[i] or 0 end,
    stock = function(i) return t.bank[i] or 0, t.guild[i] or 0 end,
    auction = price or function(i) return t.lookup[i] end, cost = cost,
    vendor = function(i) return t.vendor[i] end, sells = function(i) return t.sells[i] == true end,
    recipes = function(i) return t.recipes[i] or {} end, available = function(rec) return not t.unavailable[rec.id] end,
  }, t
end
local function Go(t, opt)
  local inp, tt = Hand(t)
  local r = CP.Plan(inp, opt)
  Invariants(tt, r, "hand " .. (t.name or "?"))
  return r
end
local function Line(r, item) for _, l in ipairs(r.items) do if l.item == item then return l end end end
local function Step(r, item) for _, s in ipairs(r.crafts) do if s.item == item then return s end end end
local function E(item, qty, crafts, id) return { id = id or (900 + item), name = "Final", crafts = crafts or 1, mats = { { item = item, qty = qty } }, outItem = 9999, outMin = 1, outMax = 1 } end
local function Rec(id, out, per, mats)
  local m = {}
  for i = 1, #mats, 2 do m[#m + 1] = { item = mats[i], qty = mats[i + 1] } end
  return { id = id, name = "R" .. id, outItem = out, outMin = per, outMax = per, mats = m }
end
local function Look(price, qty) return { price = price, qty = qty or 1000, listings = 1, total = qty or 1000, at = MNOW - 60, complete = true } end
local function Vend(p, s, a) return { p = p, s = s or 1, a = a or -1, at = MNOW - 60, npc = 1 } end
local function HasReason(r, code) for _, x in ipairs(r.summary.reasons) do if x == code then return true end end return false end

do -- A1 one level. 4 X needed (2 crafts x 2). Buying: 4 x 10 = 40. Making (1 X from 2 R; R 3 each at a vendor): 4 crafts, 8 R = 24.
  local r = Go{ name = "one-level", entries = { E(100, 2, 2) }, lookup = { [100] = Look(10) }, vendor = { [200] = Vend(3) },
    recipes = { [100] = { Rec(501, 100, 1, { 200, 2 }) } } }
  local s = r.summary
  Same(s.status, "complete", "A1 status"); Same(s.optimization, "exhaustive", "A1 search"); Check(s.proven, "A1 proven")
  Same(s.economic.low, 24, "A1 economic"); Same(s.economic.high, 24, "A1 economic high (all exact)"); Same(s.cash.low, 24, "A1 cash")
  local st = Step(r, 100)
  Same(st.crafts, 4, "A1 crafts"); Same(st.leftover, 0, "A1 leftover"); Same(st.recipe, 501, "A1 recipe")
  Same(Line(r, 200).buy.qty, 8, "A1 reagents"); Same(Line(r, 200).source, "vendor", "A1 reagent source")
  -- the baseline buys the 4 X for 40: the saving of 16 is certain (both totals exact)
  Same(s.baseline.economic.low, 40, "A1 baseline"); Same(s.savings.lowerBounds, 16, "A1 saving"); Same(s.savings.low, 16, "A1 saving low")
  Check(s.savings.confident, "A1 the saving is certain"); Same(s.baseline.compare, "lower", "A1 the plan is certainly cheaper")
  local alt = Line(r, 100).alternatives[1]
  Same(alt.kind, "buy", "A1 the alternative is buying"); Same(alt.economic.low, 40, "A1 buying instead"); Same(alt.difference, 16, "A1 by 16")
  Same(alt.compare, "lower", "A1 certainly")
end

-- A2's graph: 2 A needed. A: 50 at auction, or 1 B + 1 R (r510, 1 each). B: 30 at auction, or 2 R make 2 (r520). R: 4 at a vendor.
local A2 = function(extra)
  local t = { name = "two-level", entries = { E(110, 2) }, lookup = { [110] = Look(50), [120] = Look(30) }, vendor = { [200] = Vend(4) },
    recipes = { [110] = { Rec(510, 110, 1, { 120, 1, 200, 1 }) }, [120] = { Rec(520, 120, 2, { 200, 2 }) } } }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
do -- A2 two levels: buy A 100; make A and buy B 2 x 30 + 2 x 4 = 68; make both: A 2 crafts (2 B, 2 R), B 1 craft (2 R): R 4 x 4 = 16
  local r = Go(A2())
  Same(r.summary.economic.low, 16, "A2 economic"); Same(#r.crafts, 2, "A2 two crafts")
  Same(r.crafts[1].item, 120, "A2 B is crafted first"); Same(r.crafts[2].item, 110, "A2 then A"); Same(r.crafts[2].after[1], 120, "A2 A waits for B")
  local rl = Line(r, 200)
  Same(rl.need, 4, "A2 R's demand is combined over both crafts"); Same(#rl.usedBy, 2, "A2 R is used by two crafts")
  Same(rl.buy.qty, 4, "A2 R bought once for both")
  Same(Step(r, 120).leftover, 0, "A2 no leftover B")
end
do -- A3 three levels: A from B, B from C, C from R (1 each); A 100, B 50, C 20 at auction; R 1 at a vendor: make all three, 1 copper
  local r = Go{ name = "three-level", entries = { E(130, 1) }, lookup = { [130] = Look(100), [131] = Look(50), [132] = Look(20) }, vendor = { [133] = Vend(1) },
    recipes = { [130] = { Rec(530, 130, 1, { 131, 1 }) }, [131] = { Rec(531, 131, 1, { 132, 1 }) }, [132] = { Rec(532, 132, 1, { 133, 1 }) } } }
  Same(r.summary.economic.low, 1, "A3 economic"); Same(r.summary.crafts, 3, "A3 three crafts")
  Same(r.crafts[1].item, 132, "A3 C first"); Same(r.crafts[2].item, 131, "A3 then B"); Same(r.crafts[3].item, 130, "A3 then A")
  Same(Line(r, 132).depth, 2, "A3 C is two levels below the queue's material")
end
do -- A4 combined demand: three queued crafts each need 1 I. I is 4 at auction, or 3 from 1 R (9 at a vendor). Alone each would buy (4 < 9);
   -- together 3 I are one craft for 9 < 12, with no leftover. With only two crafts: 2 I = 8 < 9, so buying wins.
  local function T(n)
    local entries = {}
    for i = 1, n do entries[i] = E(140, 1, 1, 700 + i) end
    return { name = "combined", entries = entries, lookup = { [140] = Look(4) }, vendor = { [141] = Vend(9) }, recipes = { [140] = { Rec(540, 140, 3, { 141, 1 }) } } }
  end
  local r = Go(T(3))
  Same(Line(r, 140).source, "make", "A4 three together are made"); Same(Step(r, 140).crafts, 1, "A4 in one craft"); Same(r.summary.economic.low, 9, "A4 9")
  Same(Line(r, 140).usedBy[1].qty, 3, "A4 the queue's three needs are one demand"); Same(r.summary.savings.lowerBounds, 3, "A4 saving 12 - 9")
  r = Go(T(2))
  Same(Line(r, 140).source, "auction", "A4 two are bought"); Same(r.summary.economic.low, 8, "A4 8")
end
do -- A5 owned materials: A2 with R 3 in bags, 2 in the bank, 4 in the guild bank. R's demand 4 is taken bags 3, bank 1; nothing is bought, but
   -- the 4 R are worth 4 each: economic 16 (owning them is not free), cash 0, one collect row (bank 1)
  local r = Go(A2{ bags = { [200] = 3 }, bank = { [200] = 2 }, guild = { [200] = 4 } })
  Same(r.summary.economic.low, 16, "A5 economic counts owned R"); Same(r.summary.cash.low, 0, "A5 no cash"); Same(r.summary.owned, 16, "A5 owned value")
  local o = Line(r, 200).owned
  Same(o.bags .. "/" .. o.bank .. "/" .. o.guild, "3/1/0", "A5 bags first, then the bank")
  Same(#r.collect, 1, "A5 one collect row"); Same(r.collect[1].where, "bank", "A5 from the bank"); Same(r.collect[1].qty, 1, "A5 one")
  Same(#r.buy, 0, "A5 nothing to buy")
  -- 2 A already in the bags: nothing to make or buy; the plan's economic cost is the 2 A at 50 = 100 (they could be sold instead)
  r = Go(A2{ bags = { [110] = 2 } })
  Same(Line(r, 110).source, "owned", "A5 covered"); Same(#r.crafts, 0, "A5 no crafts"); Same(r.summary.economic.low, 100, "A5 owned A valued"); Same(r.summary.cash.low, 0, "A5 cash 0")
  -- 1 A in the bags: 1 more A: 1 craft (1 B, 1 R); 1 B is 1 craft of 2 (1 left over, 2 R); R 3 x 4 = 12 cash; economic 12 + 50 = 62
  r = Go(A2{ bags = { [110] = 1 } })
  Same(Step(r, 110).crafts, 1, "A5 one A made"); Same(Step(r, 120).leftover, 1, "A5 one B left over"); Same(r.summary.cash.low, 12, "A5 cash 12")
  Same(r.summary.economic.low, 62, "A5 economic 62")
end
do -- A6 bank and guild bank: 10 R needed directly; bags 3, bank 2, guild 4 -> bags 3, bank 2, guild 4, 1 bought for 4; 9 owned at 4 = 36: economic 40
  local r = Go{ name = "storage", entries = { E(200, 10) }, vendor = { [200] = Vend(4) }, bags = { [200] = 3 }, bank = { [200] = 2 }, guild = { [200] = 4 } }
  Same(#r.collect, 2, "A6 two collect rows"); Same(r.collect[1].where .. r.collect[1].qty .. r.collect[2].where .. r.collect[2].qty, "bank2guild4", "A6 bank then guild bank")
  Same(r.summary.cash.low, 4, "A6 cash"); Same(r.summary.economic.low, 40, "A6 economic")
end
do -- A7 the player's choices
  local r = Go(A2{ picks = { [110] = "auction" } })
  Same(Line(r, 110).source, "auction", "A7 a valid choice is followed"); Same(r.summary.economic.low, 100, "A7 even when dearer"); Same(Line(r, 110).picked, "auction", "A7 and marked")
  Same(r.picks[1].kept, true, "A7 the choice is reported as kept")
  r = Go(A2{ picks = { [120] = "vendor" } })
  Same(r.summary.economic.low, 16, "A7 an impossible choice changes nothing else"); Same(r.picks[1].why, "novendor", "A7 and says why"); Check(HasReason(r, "picklost"), "A7 reason")
  Same(Line(r, 120).pickLost, "vendor", "A7 on its line")
  r = Go(A2{ picks = { [200] = "make" } })
  Same(r.picks[1].why, "norecipe", "A7 making with no recipe"); Same(r.summary.economic.low, 16, "A7 unchanged")
  r = Go(A2{ picks = { [120] = "make" }, unavailable = { [520] = true } })
  Same(r.picks[1].why, "unavailable", "A7 making by a recipe the character can't do"); Same(Line(r, 120).source, "auction", "A7 B is bought")
  -- making chosen while buying is cheaper: A at 5 would be bought (10), the choice makes it (16)
  r = Go(A2{ lookup = { [110] = Look(5), [120] = Look(30) }, picks = { [110] = "make" } })
  Same(Line(r, 110).source, "make", "A7 make chosen"); Same(r.summary.economic.low, 16, "A7 make cost"); Same(r.summary.baseline, nil, "A7 no buy-everything baseline beside a make choice")
  -- a choice to make with an unpriced vendor: kept (the vendor exists), the plan is incomplete, never zero-cost
  r = Go{ name = "pick-noprice", entries = { E(201, 1) }, sells = { [201] = true }, lookup = { [201] = Look(9) }, picks = { [201] = "vendor" } }
  Same(Line(r, 201).source, "vendor", "A7 unpriced vendor choice kept"); Same(r.summary.missing, 1, "A7 one unknown"); Same(r.summary.status, "incomplete", "A7 incomplete")
  -- both made in a circle by the player's choice: every such plan is refused, the two choices are dropped with the reason, and the plan buys Y
  r = Go{ name = "pick-circle", entries = { E(150, 1) }, lookup = { [150] = Look(50), [151] = Look(20) },
    recipes = { [150] = { Rec(550, 150, 1, { 151, 1 }) }, [151] = { Rec(551, 151, 1, { 150, 1 }) } }, picks = { [150] = "make", [151] = "make" } }
  Same(#r.picks, 2, "A7 both choices reported"); Same(r.picks[1].why, "circular", "A7 circular"); Same(r.summary.economic.low, 20, "A7 make X, buy Y")
  Same(Line(r, 151).source, "auction", "A7 Y bought")
end
do -- A8 batches: 5 I needed; 2 per craft from 1 R: 3 crafts, 1 I left over, 3 R; R comes in stacks of 5 for 80: 1 purchase, 2 R left over
  local r = Go{ name = "batches", entries = { E(160, 5) }, lookup = { [160] = Look(100) }, vendor = { [161] = Vend(80, 5) }, recipes = { [160] = { Rec(560, 160, 2, { 161, 1 }) } } }
  Same(Step(r, 160).crafts, 3, "A8 crafts rounded up"); Same(Step(r, 160).leftover, 1, "A8 leftover"); Same(r.summary.cash.low, 80, "A8 one stack")
  Same(#r.leftovers, 2, "A8 two leftovers"); Same(r.leftovers[1].kind .. r.leftovers[1].qty, "craft1", "A8 the craft's"); Same(r.leftovers[2].kind .. r.leftovers[2].qty, "stack2", "A8 the stack's")
  Same(Line(r, 161).buy.purchases, 1, "A8 purchases")
end
do -- A9 circles
  -- a recipe that uses its own output is refused; X is bought (2 x 10)
  local r = Go{ name = "self", entries = { E(170, 2) }, lookup = { [170] = Look(10) }, vendor = { [171] = Vend(1) }, recipes = { [170] = { Rec(570, 170, 3, { 170, 1, 171, 1 }) } } }
  Same(Line(r, 170).source, "auction", "A9 self: bought"); Same(r.rejected[1].why, "circular", "A9 self: refused as circular"); Same(Line(r, 170).rejected[1].id, 570, "A9 on its line")
  -- X from Y and Y from X: make X with Y bought (2 x 20 = 40); making Y too would be a circle, which its alternative says, naming both items
  r = Go{ name = "two", entries = { E(171, 2) }, lookup = { [171] = Look(50), [172] = Look(20) },
    recipes = { [171] = { Rec(571, 171, 1, { 172, 1 }) }, [172] = { Rec(572, 172, 1, { 171, 1 }) } } }
  Same(r.summary.economic.low, 40, "A9 two: 40"); Same(Line(r, 171).source, "make", "A9 X made"); Same(Line(r, 172).source, "auction", "A9 Y bought")
  local alt = Line(r, 172).alternatives[1]
  Same(alt.ok, false, "A9 two: making Y is refused"); Same(alt.why, "circular", "A9 as circular"); Same(#alt.cycle, 2, "A9 naming the two items")
  -- a circle whose demand settles: X makes 3 from 1 Y, Y makes 3 from 1 X. Making both settles at one craft each and would look FREE (0); it
  -- cannot be started from nothing, so it is refused: make X, buy Y (20)
  r = Go{ name = "settling", entries = { E(410, 1) }, lookup = { [410] = Look(50), [411] = Look(20) },
    recipes = { [410] = { Rec(710, 410, 3, { 411, 1 }) }, [411] = { Rec(711, 411, 3, { 410, 1 }) } } }
  Same(r.summary.economic.low, 20, "A9 settling circle: never free"); Same(Line(r, 411).source, "auction", "A9 Y bought")
  Same(Line(r, 411).alternatives[1].why, "circular", "A9 the circle is named")
  -- X <- Y <- Z <- X; X 100, Y 10, Z 1: make X and Y, buy Z: 1
  r = Go{ name = "longer", entries = { E(173, 1) }, lookup = { [173] = Look(100), [174] = Look(10), [175] = Look(1) },
    recipes = { [173] = { Rec(573, 173, 1, { 174, 1 }) }, [174] = { Rec(574, 174, 1, { 175, 1 }) }, [175] = { Rec(575, 175, 1, { 173, 1 }) } } }
  Same(r.summary.economic.low, 1, "A9 longer: 1"); Same(Line(r, 175).source, "auction", "A9 Z bought")
  Same(#Line(r, 175).alternatives[1].cycle, 3, "A9 making Z closes a circle of three")
  -- a circle with another route: Y also made from R (1): make X and Y from R: 1
  r = Go{ name = "alternate", entries = { E(176, 1) }, lookup = { [176] = Look(50), [177] = Look(20) }, vendor = { [178] = Vend(1) },
    recipes = { [176] = { Rec(576, 176, 1, { 177, 1 }) }, [177] = { Rec(577, 177, 1, { 176, 1 }), Rec(578, 177, 1, { 178, 1 }) } } }
  Same(r.summary.economic.low, 1, "A9 alternate: 1"); Same(Step(r, 177).recipe, 578, "A9 by the route that is not circular")
  -- a diamond is not a circle: A from B + C, B and C each from D (2): 2 A -> 2 B, 2 C -> 4 D = 8
  r = Go{ name = "diamond", entries = { E(180, 2) }, lookup = { [180] = Look(100), [181] = Look(50), [182] = Look(50) }, vendor = { [183] = Vend(2) },
    recipes = { [180] = { Rec(580, 180, 1, { 181, 1, 182, 1 }) }, [181] = { Rec(581, 181, 1, { 183, 1 }) }, [182] = { Rec(582, 182, 1, { 183, 1 }) } } }
  Same(r.summary.economic.low, 8, "A9 diamond: 8"); Same(Line(r, 183).need, 4, "A9 D combined"); Same(#r.crafts, 3, "A9 three crafts"); Same(r.crafts[3].item, 180, "A9 A last")
  -- two recipes for X: 2 R (5) = 10 or 1 S (6) = 6; X 100 at auction: the second recipe, the first 4 dearer
  r = Go{ name = "producers", entries = { E(185, 1) }, lookup = { [185] = Look(100) }, vendor = { [186] = Vend(5), [187] = Vend(6) },
    recipes = { [185] = { Rec(585, 185, 1, { 186, 2 }), Rec(586, 185, 1, { 187, 1 }) } } }
  Same(Step(r, 185).recipe, 586, "A9 the cheaper recipe"); Same(r.summary.economic.low, 6, "A9 6")
  local alts = Line(r, 185).alternatives
  Same(#alts, 2, "A9 buying and the other recipe"); Same(alts[2].recipe, 585, "A9 the other recipe"); Same(alts[2].difference, 4, "A9 4 dearer")
end
do -- A10 what isn't known
  -- a reagent with no price: making X has an unknown cost, so X is bought (50) and the alternative can't be compared
  local r = Go{ name = "unpriced-reagent", entries = { E(190, 1) }, lookup = { [190] = Look(50) }, recipes = { [190] = { Rec(590, 190, 1, { 191, 1 }) } } }
  Same(Line(r, 190).source, "auction", "A10 the priced way"); Same(Line(r, 190).alternatives[1].compare, "unknown", "A10 no comparison")
  -- nothing priced: the plan is incomplete with one unknown, never a zero total
  r = Go{ name = "nothing", entries = { E(192, 1) }, recipes = { [192] = { Rec(592, 192, 1, { 193, 1 }) } } }
  Same(r.summary.status, "incomplete", "A10 incomplete"); Same(r.summary.missing, 1, "A10 one unknown"); Check(not r.summary.complete, "A10 not complete")
  Same(Line(r, 192).missing, "nosource", "A10 says there is no source"); Check(HasReason(r, "missingcost"), "A10 reason")
  -- recipes that are not used, each for its reason
  local function Why(rec, extra)
    local t = { name = "why", entries = { E(194, 1) }, lookup = { [194] = Look(50) }, vendor = { [195] = Vend(1) }, recipes = { [194] = { rec } } }
    for k, v in pairs(extra or {}) do t[k] = v end
    local p = Go(t)
    Same(Line(p, 194).source, "auction", "A10 not made")
    return p.rejected[1] and p.rejected[1].why
  end
  local x = Rec(594, 194, 1, { 195, 1 }); x.outMin, x.outMax = nil, nil
  Same(Why(x), "noamount", "A10 unknown output")
  x = Rec(594, 194, 1, { 195, 1 }); x.outMax = 3
  Same(Why(x), "range", "A10 a varying output")
  x = Rec(594, 194, 1, { 195, 1 }); x.mats = nil
  Same(Why(x), "unsupported", "A10 materials not countable")
  Same(Why(Rec(594, 194, 1, { 195, 1 }), { unavailable = { [594] = true } }), "unavailable", "A10 not known by the character")
  -- an unreadable bag count: none assumed owned, the plan says so and is not complete
  r = Go{ name = "counts", entries = { E(196, 2) }, vendor = { [196] = Vend(3) }, unknown = { [196] = true } }
  Same(Line(r, 196).buy.qty, 2, "A10 none assumed owned"); Check(Line(r, 196).countsUnknown, "A10 flagged"); Check(HasReason(r, "counts"), "A10 reason")
  Same(r.summary.status, "incomplete", "A10 incomplete")
end
do -- A11 auction prices through the real Market.Cost
  -- 3 at 10 in one listing, then two single listings at 12: 3 cost exactly 30; 4 cost exactly 30 + 12 = 42
  local listings = { [300] = { { 10, 3 }, { 12, 1 }, { 12, 1 } }, [301] = { { 10, 5 } }, [302] = {} }
  for p = 10, 16 do listings[302][#listings[302] + 1] = { p, 1 } end
  local r = Go{ name = "tier", entries = { E(300, 3) }, listings = listings }
  Same(Line(r, 300).buy.state, "exact", "A11 within the first tier"); Same(r.summary.cash.low, 30, "A11 30")
  r = Go{ name = "tier+1", entries = { E(300, 4) }, listings = listings }
  Same(r.summary.cash.low, 42, "A11 one into the next tier"); Same(r.summary.cash.high, 42, "A11 exact")
  -- one listing of 5 at 10: 3 cost at least 30, at most 50 if the whole stack must be bought
  r = Go{ name = "stack", entries = { E(301, 3) }, listings = listings }
  Same(Line(r, 301).buy.state, "range", "A11 a range"); Same(r.summary.cash.low, 30, "A11 low"); Same(r.summary.cash.high, 50, "A11 high")
  Same(r.summary.economic.high, 50, "A11 economic high"); Check(HasReason(r, "wholeauction"), "A11 reason")
  -- seven single listings at 10..16: 7 are beyond the six kept tiers: at least 10+...+15 + 16 = 91, no upper bound (open)
  r = Go{ name = "beyond", entries = { E(302, 7) }, listings = listings }
  Same(Line(r, 302).buy.state, "estimate", "A11 an estimate"); Same(r.summary.cash.low, 91, "A11 at least 91"); Same(r.summary.cash.high, nil, "A11 open")
  Same(r.summary.economic.high, nil, "A11 economic open"); Check(HasReason(r, "estimate"), "A11 reason"); Check(Line(r, 302).buy.atMost ~= nil, "A11 the service's at-most is kept beside")
  -- ranges through a chain (a stand-in cost service): X from 1 A (8 to 11 each) + 1 B (exactly 2): X costs 10 to 13; with A only "at least 8": open
  local function Cost(spec)
    return function(item, qty)
      local s = spec[item]
      if not s then return { state = "none" } end
      if s.exact then return { state = "exact", cost = s.exact * qty, low = s.exact * qty, high = s.exact * qty } end
      if s.atLeast then return { state = "estimate", low = s.atLeast * qty, high = 99 * qty } end
      return { state = "range", low = s.low * qty, high = s.high * qty }
    end
  end
  local chain = { name = "range-chain", entries = { E(310, 1) }, recipes = { [310] = { Rec(610, 310, 1, { 311, 1, 312, 1 }) } } }
  chain.cost = Cost{ [311] = { low = 8, high = 11 }, [312] = { exact = 2 } }
  chain.lookup = { [311] = Look(8), [312] = Look(2) }
  r = Go(chain)
  Same(r.summary.economic.low, 10, "A11 chain low"); Same(r.summary.economic.high, 13, "A11 chain high"); Same(r.summary.status, "complete", "A11 complete")
  chain.cost = Cost{ [311] = { atLeast = 8 }, [312] = { exact = 2 } }
  r = Go(chain)
  Same(r.summary.economic.low, 10, "A11 at least 10"); Same(r.summary.economic.high, nil, "A11 open above")
  -- X also sold by a vendor for 12: the plan ranks by the lower bound (10 < 12), but 10..13 overlaps 12: the comparison is not certain
  chain.cost = Cost{ [311] = { low = 8, high = 11 }, [312] = { exact = 2 } }
  chain.vendor = { [310] = Vend(12) }
  r = Go(chain)
  Same(Line(r, 310).source, "make", "A11 the lower bound ranks first"); Same(Line(r, 310).alternatives[1].compare, "overlap", "A11 but not certainly cheaper")
  Same(r.summary.baseline.compare, "overlap", "A11 the baseline overlaps"); Check(not r.summary.savings.confident, "A11 no certain saving")
  Same(r.summary.savings.lowerBounds, 2, "A11 12 - 10 compares lower bounds only"); Same(r.summary.savings.low, -1, "A11 the saving may be -1")
end
do -- A13 cash-best is not economy-best: X 15 at auction, or from 2 R the player owns (R worth 10 each)
  local t = { name = "cash", entries = { E(320, 1) }, lookup = { [320] = Look(15), [321] = Look(10) }, bags = { [321] = 2 }, recipes = { [320] = { Rec(620, 320, 1, { 321, 2 }) } } }
  local r = Go(t)
  Same(Line(r, 320).source, "auction", "A13 economy: buy for 15 (making uses 20 worth of R)"); Same(r.summary.economic.low, 15, "A13 15")
  r = Go(t, { objective = "cash" })
  Same(Line(r, 320).source, "make", "A13 cash: make from owned R"); Same(r.summary.cash.low, 0, "A13 no cash"); Same(r.summary.economic.low, 20, "A13 but worth 20")
  Same(r.objective, "cash", "A13 the objective is reported")
end
do -- A14 equal costs: vendor before auction; the lower recipe id; buying before making
  local r = Go{ name = "tie-buy", entries = { E(330, 1) }, lookup = { [330] = Look(10) }, vendor = { [330] = Vend(10) } }
  Same(Line(r, 330).source, "vendor", "A14 vendor on a tie")
  r = Go{ name = "tie-recipe", entries = { E(331, 1) }, lookup = { [331] = Look(100) }, vendor = { [333] = Vend(3), [334] = Vend(6) },
    recipes = { [331] = { Rec(632, 331, 1, { 334, 1 }), Rec(631, 331, 1, { 333, 2 }) } } }
  Same(Step(r, 331).recipe, 631, "A14 the lower recipe id")
  r = Go{ name = "tie-make", entries = { E(335, 1) }, lookup = { [335] = Look(6) }, vendor = { [336] = Vend(3) }, recipes = { [335] = { Rec(635, 335, 1, { 336, 2 }) } } }
  Same(Line(r, 335).source, "auction", "A14 buying before making"); Same(Line(r, 335).alternatives[1].compare, "equal", "A14 equal")
end
-- A15's graph: eight intermediates each made from R or from S (shared), all needed: one part, 3^8 combinations
local function Wide()
  local t = { name = "wide", entries = {}, lookup = {}, vendor = { [349] = Vend(2), [350] = Vend(3) }, recipes = {} }
  for i = 1, 8 do
    local item = 340 + i
    t.entries[i] = E(item, i, 1, 800 + i)
    t.lookup[item] = Look(5 + i)
    t.recipes[item] = { Rec(640 + 2 * i, item, 1 + i % 2, { 349, 1 + i % 3 }), Rec(641 + 2 * i, item, 1, { 350, 1 }) }
  end
  return t
end
do -- A15 the search limit: with 10 states the plan is still feasible, but "bounded", never proven, and at least the exhaustive cost
  local full = Go(Wide(), { limits = { states = 1000000 } })
  Same(full.summary.optimization, "exhaustive", "A15 the full search finishes"); Check(full.summary.proven, "A15 proven")
  local r = Go(Wide(), { limits = { states = 10 } })
  Same(r.summary.optimization, "bounded", "A15 limited"); Check(not r.summary.proven, "A15 not proven"); Check(HasReason(r, "states"), "A15 says why")
  Check(r.summary.economic.low >= full.summary.economic.low, "A15 never cheaper than the proven best")
  Check(r.summary.work.states <= 10 + 8, "A15 the states stay within the limit")
  -- the same graph beside 300 materials that are only bought (300 parts with nothing to decide): those parts never branch, so they keep no share
  -- of the states and the graph is still searched to the end within 3,000 states (it needs about 2,700)
  local t = Wide()
  for i = 1, 300 do t.entries[#t.entries + 1] = E(5000 + i, 1, 1, 9000 + i) t.lookup[5000 + i] = Look(i) end
  r = Go(t, { limits = { states = 3000 } })
  Same(r.summary.parts, 301, "A15 301 independent parts"); Same(r.summary.optimization, "exhaustive", "A15 the parts with nothing to decide take no states")
  Same(r.summary.economic.low, full.summary.economic.low + 300 * 301 / 2, "A15 and the same plan for the graph, plus the bought materials")
end
do -- A16 very large prices: 99,999,999,999 each; 50 cost 4,999,999,999,950 exactly; 999 crafts x 9,999 = 9,989,001 items pass 2^53: approximate
  local r = Go{ name = "large", entries = { E(360, 50) }, vendor = { [360] = Vend(99999999999) } }
  Same(("%.0f"):format(r.summary.cash.low), "4999999999950", "A16 exact beyond 32 bits")
  r = Go{ name = "huge", entries = { E(360, 9999, 999) }, vendor = { [360] = Vend(99999999999) } }
  Check(HasReason(r, "approximate"), "A16 beyond 2^53 is approximate")
end

---------------------------------------------------------------------------
-- B. (continued) the seeded comparison
---------------------------------------------------------------------------
local stats = { compared = 0, skippedLarge = 0, skippedPicks = 0, made = 0, multi = 0, cycles = 0, cashDiffers = 0, levels = {} }
local function MarketListings(scn)
  local l = {}
  for item, recs in pairs(scn.listings) do
    l[item] = {}
    for _, x in ipairs(recs) do l[item][#l[item] + 1] = { x.b / x.c, x.c } end
  end
  return l
end

local family = {}
for _, seed in ipairs(Seeds(7540000, N)) do family[#family + 1] = { seed, 1 } end
for _, seed in ipairs(Seeds(7545000, N)) do family[#family + 1] = { seed, 6 } end   -- dear intermediates: deeper chains
for _, f in ipairs(family) do
  local seed = f[1]
  local scn = FX.Chain(seed, { markup = f[2], levels = f[2] > 1 and { 2, 2, 1 } or nil, top = f[2] > 1 })
  Market(MarketListings(scn))
  local cost, price = MarketFns()
  local inp = FX.ChainInput(scn, { cost = cost, auction = price })
  for _, objective in ipairs({ "economic", "cash" }) do
    local ref = REF.ChainPlan(scn, { objective = objective })
    if ref.skipped then
      if objective == "economic" then stats.skippedLarge = stats.skippedLarge + 1 end
      break
    end
    local r = CP.Plan(inp, { objective = objective })
    Invariants(scn, r, ("seed %d %s"):format(seed, objective))
    if not ref.best then
      -- only the player's choice can make every combination impossible: the planner forgets it (hand-tested in A) and plans the rest
      Check(#r.picks > 0 and r.picks[1].pick == "make", ("seed %d: no feasible plan in the model, so a make choice must have been dropped"):format(seed))
      if objective == "economic" then stats.skippedPicks = stats.skippedPicks + 1 end
      break
    end
    Same(#r.summary.limits, 0, ("seed %d: a small scenario hits no graph limit"):format(seed))
    Same(r.summary.optimization, "exhaustive", ("seed %d: a small scenario is searched exhaustively"):format(seed))
    Check(r.summary.proven, ("seed %d: and the plan is the proven best"):format(seed))
    local pp, pt = ProdView(r)
    local rp, rt = RefView(ref.best)
    local diff
    if pt ~= rt then diff = "totals: planner " .. pt .. "\n            model   " .. rt end
    if not diff then
      for item, x in pairs(rp) do if pp[item] ~= x then diff = ("item %d: planner %s, model %s"):format(item, tostring(pp[item]), x) break end end
      for item, x in pairs(pp) do if rp[item] ~= x then diff = diff or ("item %d: planner %s, model %s"):format(item, x, tostring(rp[item])) end end
    end
    if diff then
      error(("REFERENCE MISMATCH seed=%d objective=%s: %s\n  scenario: %s\n  planner plan: %s\n  model plan: %s\n  rerun: CHAIN_SEED=%d"):format(seed, objective, diff,
        Describe(scn), Ser(pp), Ser(rp), seed), 0)
    end
    if objective == "economic" then
      stats.compared = stats.compared + 1
      if #r.crafts > 0 then stats.made = stats.made + 1 end
      local deepest = 0
      for _, l in ipairs(r.items) do if l.source == "make" and l.depth > deepest then deepest = l.depth end end
      if #r.crafts > 0 then stats.levels[deepest + 1] = (stats.levels[deepest + 1] or 0) + 1 end
      if ref.why == "circular" then stats.cycles = stats.cycles + 1 end
      if ref.best and ref.bestCash and (ref.best.key.cash ~= ref.bestCash.key.cash) then stats.cashDiffers = stats.cashDiffers + 1 end
    end
  end
end
print(("B: %d seeds compared with the exhaustive model (x2 objectives), %d too large to enumerate, %d with an impossible choice; %d make something; deepest made level %s; %d with circles refused; %d where cash-best and economy-best differ"):format(
  stats.compared, stats.skippedLarge, stats.skippedPicks, stats.made, Ser(stats.levels), stats.cycles, stats.cashDiffers))
if not ONLY then
  Check(stats.compared >= #family * 0.85, ("most seeds are compared (%d of %d; %d too large, %d with impossible choices)"):format(stats.compared, #family, stats.skippedLarge, stats.skippedPicks))
  Check(stats.made >= N * 0.3, "many plans make something: " .. stats.made)
  Check((stats.levels[2] or 0) >= 20 and (stats.levels[3] or 0) >= 5, "some plans make materials two or three levels deep: " .. Ser(stats.levels))
  Check(stats.cycles >= 10, "some scenarios have circular combinations the model refused: " .. stats.cycles)
  Check(stats.cashDiffers >= 3, "some scenarios have a cash-best plan that is not the economy-best: " .. stats.cashDiffers)
end

---------------------------------------------------------------------------
-- C. Larger graphs: invariants, determinism and limited searches
---------------------------------------------------------------------------
local worst, bounded = 0, 0
for _, seed in ipairs(Seeds(7550000, 40)) do
  local scn = FX.Chain(seed, { size = "large" })
  Market(MarketListings(scn))
  local cost, price = MarketFns()
  local inp = FX.ChainInput(scn, { cost = cost, auction = price })
  local t0 = os.clock()
  local r = CP.Plan(inp)
  worst = math.max(worst, os.clock() - t0)
  Invariants(scn, r, "large seed " .. seed)
  Same(Ser(CP.Plan(inp)), Ser(r), "large seed " .. seed .. ": the same inputs give the same plan")
  local lim = CP.Plan(inp, { limits = { states = 12, improve = 20 } })
  Invariants(scn, lim, "large limited seed " .. seed)
  if lim.summary.optimization == "bounded" then
    bounded = bounded + 1
    Check(not lim.summary.proven, "a bounded plan is never proven")
    if r.summary.optimization == "exhaustive" then
      local a, b = lim.summary, r.summary
      Check(a.missing > b.missing or (a.missing == b.missing and a.economic.low >= b.economic.low), "large seed " .. seed .. ": a limited search never beats the full one")
    end
  end
end
if not ONLY then Check(bounded >= 10, "the limited searches are really limited: " .. bounded) end
print(("C: 40 larger graphs: invariants and determinism hold; %d limited searches; slowest plan %.1f ms (offline, this machine)"):format(bounded, worst * 1000))

---------------------------------------------------------------------------
-- D. Malformed input
---------------------------------------------------------------------------
do
  local zero = 0
  local nan = zero / zero
  for _, v in ipairs({ nan, math.huge, -math.huge, 2.5, -1, "3", true }) do
    local r = Go{ name = "held " .. tostring(v), entries = { E(400, 2) }, vendor = { [400] = Vend(3) }, unknown = { [400] = true }, unknownValue = v }
    Check(Line(r, 400).countsUnknown, "D a held count of " .. tostring(v) .. " is unknown"); Same(Line(r, 400).buy.qty, 2, "D none assumed owned")
  end
  -- a merchant record that is not a record: the vendor exists but has no usable price
  local r = Go{ name = "vendor-nan", entries = { E(401, 1) }, vendor = { [401] = { p = nan, s = 1, a = -1 } } }
  Same(Line(r, 401).source, "vendor", "D vendor kept"); Same(Line(r, 401).missing, "noprice", "D no price"); Same(r.summary.cash.low, 0, "D nothing counted")
  -- cost answers that are not numbers
  local function Cost(answer) return function() return answer end end
  r = Go{ name = "cost-nan", entries = { E(402, 1) }, cost = Cost{ state = "exact", cost = nan, low = nan, high = nan } }
  Same(Line(r, 402).missing, "few", "D a NaN cost is not a price"); Same(r.summary.missing, 1, "D counted unknown")
  r = Go{ name = "cost-inf", entries = { E(402, 1) }, cost = Cost{ state = "range", low = 5, high = math.huge } }
  Same(r.summary.cash.low, 5, "D an infinite upper bound"); Same(r.summary.cash.high, nil, "D is open, not infinite")
  -- recipes that are not recipes
  local bad = { "x", { id = nan, outItem = 403, outMin = 1, mats = { { item = 404, qty = 1 } } }, { id = 1, outItem = 403, outMin = 1, mats = { { item = 404, qty = 2.5 } } },
    { id = 2, outItem = 403, outMin = nan, mats = { { item = 404, qty = 1 } } }, { id = 3, outItem = 403, outMin = 1, outMax = math.huge, mats = { { item = 404, qty = 1 } } },
    { id = 4, outItem = 999, outMin = 1, mats = { { item = 404, qty = 1 } } } }
  r = Go{ name = "bad-recipes", entries = { E(403, 1) }, lookup = { [403] = Look(5) }, vendor = { [404] = Vend(1) }, recipes = { [403] = bad } }
  Same(Line(r, 403).source, "auction", "D no usable recipe"); Same(#r.rejected, 6, "D every bad recipe refused")
  local whys = {}
  for _, x in ipairs(r.rejected) do whys[#whys + 1] = x.why end
  table.sort(whys)
  Same(table.concat(whys, ","), "invalid,invalid,invalid,noamount,noamount,unsupported", "D each for its reason")
  -- entries that can't be read
  r = Go{ name = "bad-entries", entries = { { crafts = nan, mats = { { item = 405, qty = 1 } } }, { crafts = 1, mats = { { item = 405, qty = -1 } } }, E(406, 1) }, vendor = { [406] = Vend(1) } }
  Same(r.summary.invalidEntries, 1, "D crafts not a number"); Same(r.summary.unknownEntries, 1, "D a material not countable"); Same(r.summary.status, "incomplete", "D incomplete")
  Same(r.summary.cash.low, 1, "D the readable entry is planned")
  -- a long chain: 300 items each made from the next: only 6 levels are planned to be made, the rest bought; quick
  local t = { name = "deep", entries = { E(1000, 1) }, recipes = {}, lookup = {} }
  for i = 0, 299 do t.recipes[1000 + i] = { Rec(5000 + i, 1000 + i, 1, { 1001 + i, 1 }) } t.lookup[1000 + i] = Look(1000 - i) end
  local t0 = os.clock()
  r = Go(t)
  Check(os.clock() - t0 < 1, "D a deep chain is quick")
  Same(r.summary.limits[1], "depthlimit", "D the depth limit is reported"); Check(not r.summary.proven, "D not proven")
  local deepest = 0
  for _, l in ipairs(r.items) do if l.depth > deepest then deepest = l.depth end end
  Same(deepest, CP.LIMITS.depth, "D no item planned beyond the depth limit")
  -- a wide graph: 4 recipes of 16 new reagents each, each with 4 more: the item limit stops it
  t = { name = "wide-graph", entries = { E(2000, 1) }, recipes = {}, lookup = { [2000] = Look(1) } }
  local nextId = 2001
  local function Fan(item, depth)
    local list = {}
    for k = 1, 6 do
      local mats = {}
      for _ = 1, 16 do mats[#mats + 1] = nextId mats[#mats + 1] = 1 nextId = nextId + 1 end
      list[k] = Rec(item * 10 + k, item, 1, mats)
    end
    t.recipes[item] = list
  end
  Fan(2000)
  for i = 2001, 2100 do Fan(i) end
  r = Go(t)
  local codes = table.concat(r.summary.limits, ",")
  Check(codes:find("candidatelimit") and codes:find("graphlimit"), "D the candidate and item limits are reported: " .. codes)
  Check(r.summary.work.nodes <= 1 + CP.LIMITS.nodes, "D at most the item limit beyond the queue's own materials")
end

---------------------------------------------------------------------------
-- E. Determinism, unchanged inputs, the stepped job
---------------------------------------------------------------------------
do
  for _, seed in ipairs({ 7540003, 7540011, 7545002, 7550004 }) do
    local scn = FX.Chain(seed, { size = seed >= 7550000 and "large" or nil, markup = seed >= 7545000 and 6 or nil })
    Market(MarketListings(scn))
    local cost, price = MarketFns()
    local before = Ser(scn)
    local inp = FX.ChainInput(scn, { cost = cost, auction = price })
    local r = CP.Plan(inp)
    Same(Ser(scn), before, "E the planner changes none of its inputs (seed " .. seed .. ")")
    local job = CP.Job(FX.ChainInput(scn, { cost = cost, auction = price }))
    local steps = 0
    while not job:Step(1) do steps = steps + 1 Check(steps < 100000, "E the job ends") end
    Same(Ser(job:Result()), Ser(r), "E the stepped job gives the plan computed at once (seed " .. seed .. ")")
    Check(steps > 1, "E and it really stepped")
    local j2 = CP.Job(FX.ChainInput(scn, { cost = cost, auction = price }))
    j2:Step(1)
    j2:Cancel()
    Same(j2:Step(5), false, "E a cancelled job does nothing more"); Same(j2:Result(), nil, "E and has no result")
  end
  -- an empty queue
  local r = CP.Plan({ entries = {}, have = function() return 0 end })
  Same(r.summary.status, "empty", "E nothing queued")
end

---------------------------------------------------------------------------
-- F. Compatibility: Shopping is unchanged and nothing uses the planner yet
---------------------------------------------------------------------------
do
  -- Shopping.Plan gives the same plans with and without CraftPlanner.lua loaded
  local c2 = MIClient("Rich", { db = { modules = {} } })
  c2.TwichUIDB = c2.TwichUIDB or {}
  for _, f in ipairs(FILES) do
    if f ~= "CraftPlanner.lua" then local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c2); chunk("TwichUI_Workshop", {}) end
  end
  local W2 = c2.TwichUI.Workshop
  Check(W2.CraftPlanner == nil, "F the second copy has no planner")
  for i = 1, 30 do
    local scn = FX.Crafting(7510000 + i, { entries = 2 + i % 3 })
    local a = Sh.Plan(FX.PlanInput(scn, W.Materials.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))))
    local b = W2.Shopping.Plan(FX.PlanInput(scn, W2.Materials.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))))
    Same(Ser(a), Ser(b), "F Shopping.Plan unchanged (seed " .. (7510000 + i) .. ")")
  end
  -- no window, session or tooltip file calls the planner (P2 adopts it)
  local toc = assert(io.open(ROOT .. "../TwichUI_Workshop/TwichUI_Workshop.toc")):read("*a")
  for file in toc:gmatch("\n([%w_]+%.lua)") do
    if file ~= "CraftPlanner.lua" then
      local src = assert(io.open(ROOT .. "../TwichUI_Workshop/" .. file)):read("*a")
      Check(not src:find("CraftPlanner", 1, true), "F " .. file .. " does not use the planner yet")
    end
  end
  Check(toc:find("\nShopping.lua\n[^\n]*\nCraftPlanner.lua\n"), "F the planner loads right after Shopping.lua")
end

print("PASSED test_workshop_craftplanner")
