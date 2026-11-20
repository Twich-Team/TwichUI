-- The planning estimate (TwichUI_Workshop/Estimate.lua), the fees (Fees.lua) and what Opportunities.lua does with them: depth-aware,
-- vendor-aware materials, the competition-based sell price and its cap, the fallbacks, the vendor floor, the cut and the deposit, confidence,
-- the typical profit, many crafts at once, cooldowns, the margin sort, the low-confidence filter and the words. docs/workshop/pricing-realism-
-- proposal.md section 5. Every input is a FAKE context or a fake Ledger: this proves the arithmetic and the rules, not the real market.
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function Has(lines, text)
  for _, l in ipairs(lines) do
    local s = l[1] .. (l[2] and (" | " .. l[2]) or "")
    if s:find(text, 1, true) then return true end
  end
  return false
end
local function Dump(lines)
  local out = {}
  for _, l in ipairs(lines) do out[#out + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end
  return table.concat(out, "\n")
end

local NOW = 1800000000
local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.time = function() return NOW end
for _, f in ipairs({ "Data.lua", "Materials.lua", "Queue.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Fees.lua", "Estimate.lua" }) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = c.TwichUI.Workshop
local E, F, Op, PR = W.Estimate, W.Fees, W.Opps, W.Prices
local function Money(v) return tostring(v) .. "c" end
local function Name(id) return "item" .. tostring(id) end

-- A walk over listings of single items (price list, cheapest first): Market.Cost's shape for the quantities it can serve
local function Walk(prices, extra)
  return function(qty)
    if qty > #prices then return { state = "few", available = #prices } end
    local low = 0
    for i = 1, qty do low = low + prices[i] end
    local r = { state = "exact", cost = low, low = low, high = low, at = NOW - 60, complete = true, quality = "good" }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
  end
end
local GOOD = { level = "good", reasons = {}, facts = { listings = 20, observedDays = 20 } }
-- a context over tables: price, cost, comp, value ({ market, historical }), quality, supply, vendor, vsell, ref, cut, deposit
local function Ctx(o)
  return {
    now = NOW, cut = o.cut, cutWhy = o.cutWhy,
    price = function(item) return o.price and o.price[item] end,
    cost = o.cost and function(item, qty) local f = o.cost[item]; return f and f(qty) or { state = "none" } end or nil,
    competition = function(item) return o.comp and o.comp[item] end,
    value = function(item, kind) local v = o.value and o.value[item]; return v and v[kind] and { value = v[kind] } or nil end,
    quality = function(item) return o.quality and o.quality[item] or GOOD end,
    supply = function(item) return o.supply and o.supply[item] end,
    reference = function(item) return o.ref and o.ref[item] end,
    vendor = function(item) return o.vendor and o.vendor[item] end,
    vendorSell = function(item) return o.vsell and o.vsell[item] end,
    deposit = o.deposit and function(item, qty) return o.deposit(item, qty) end or nil,
  }
end
local function Comp(competing, ahead, extra)
  local r = { competing = competing, ahead = ahead or 50, total = { items = ahead or 50 }, below = { items = 0, listings = 0 }, cheapest = competing, at = NOW - 60, complete = true }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end
-- the worked examples' recipe: 1 Flask (300) from 4 Herb (100) and 2 Crystal (200)
local REC = { id = 1, name = "Flask", prof = 1, outItem = 300, outMin = 1, outMax = 1, mats = { { item = 100, qty = 4 }, { item = 200, qty = 2 } } }
-- Herb is listed 1 at 20 (bait: Market.Cost with fromCompeting leaves it out, test_workshop_valuation.lua), 30 at 60 and 200 at 62: the walk the
-- estimate receives starts at the competing tier
local HERB = {}
for i = 1, 30 do HERB[#HERB + 1] = 60 end
for i = 1, 200 do HERB[#HERB + 1] = 62 end
local CRYSTAL = {}
for i = 1, 50 do CRYSTAL[i] = 15 end

---------------------------------------------------------------------------
-- 1. Worked case A (docs section 4): the cheap single listing on a material is not the cost
---------------------------------------------------------------------------
do
  local est = E.New(Ctx({ cost = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }, comp = { [300] = Comp(300, 25) },
    value = { [300] = { market = 295, historical = 290 } } }))
  local e = est:Craft(REC, 1)
  Same(e.state, "ok") Same(e.role, "estimate")
  Same(e.mats[1].total, 240, "4 herbs at 60 (the 20 bait is left out)") Same(e.mats[2].total, 30) Same(e.cost, 270)
  Same(e.unit, 300, "the competing price, under the cap (ceil(1.15 x 295) = 340)") Same(e.sellBasis, "competing")
  Same(e.profitLow, 30, "300 - 270, before fees") Same(e.outlet, "auction") Same(e.confidence, "high")
  -- the queue example: 10 crafts walk 40 herbs and sell 10 against the 25 listed at 300 (40%: under the 50% line)
  e = est:Craft(REC, 10)
  Same(e.mats[1].qty, 40) Same(e.mats[1].total, 30 * 60 + 10 * 62, "2420") Same(e.mats[2].total, 300) Same(e.cost, 2720)
  Same(e.sellLow, 3000) Same(e.profitLow, 280) Same(e.absorb, nil, "10 against 25: under the absorption line")
  e = est:Craft(REC, 13)
  Check(e.absorb and e.absorb.selling == 13 and e.absorb.against == 25, "13 against 25 is more than half: flagged")
  local thin = E.New(Ctx({ cost = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }, comp = { [300] = Comp(300, 1) } })):Craft(REC, 1)
  Same(thin.absorb, nil, "selling one item is never flooding the market (thinness is its own reason)")
  Same(e.confidence, "medium", "absorption lowers confidence one step")
  Same(est:Craft(REC, 1).cost, 270, "the memo gives the same answer again")
  local before = est:Stats().asked
  est:Craft(REC, 1)
  Same(est:Stats().asked, before, "an item and quantity already asked about are answered from the memo")
end

---------------------------------------------------------------------------
-- 2. Worked case B: one dumped listing on the product is bait; case C: an emptied market is capped
---------------------------------------------------------------------------
do
  local comp = Comp(300, 27, { below = { items = 2, listings = 2 }, cheapest = 90 })
  local est = E.New(Ctx({ cost = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }, comp = { [300] = comp }, value = { [300] = { market = 295 } } }))
  local e = est:Craft(REC, 1)
  Same(e.unit, 300, "the 2 listed at 90 are bait: the competing 300 is the price") Same(e.bait.items, 2) Same(e.bait.price, 90) Same(e.profitLow, 30)
  est = E.New(Ctx({ cost = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }, comp = { [300] = Comp(900, 1) },
    value = { [300] = { market = 295, historical = 290 } }, quality = { [300] = { level = "limited", reasons = { { code = "listings", text = "Only 1 listing." } }, facts = { listings = 1, observedDays = 20 } } } }))
  e = est:Craft(REC, 1)
  Same(e.unit, 340, "ceil(1.15 x 295) = 340") Check(e.capped) Same(e.listed, 900) Same(e.profitLow, 70) Same(e.confidence, "low")
  Same(e.reasons[1].text, "Only 1 listing.", "Quality's own reason first; no duplicate 'few listings' line")
  local codes = {}
  for _, r in ipairs(e.reasons) do codes[r.code] = true end
  Check(codes.capped and not codes.thin, "the cap is a reason; thinness is not said twice")
  -- the cap's edge, in whole copper: exactly 115% is not capped, one copper above is
  local function Sell(competing, mv)
    return E.New(Ctx({ cost = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }, comp = { [300] = Comp(competing) }, value = { [300] = { market = mv } } })):Craft(REC, 1)
  end
  Same(Sell(115, 100).unit, 115) Same(Sell(115, 100).capped, nil, "115% of 100 is not over the cap")
  Same(Sell(116, 100).unit, 115) Check(Sell(116, 100).capped, "116 > 115: capped")
  Same(Sell(5000, 1).unit, 2, "ceil(1.15) = 2, never 0")
end

---------------------------------------------------------------------------
-- 3. The sell fallbacks: lowest listing (no spread saved), Market Value, Historical Value, a reference, unknown
---------------------------------------------------------------------------
do
  local mats = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }
  local e = E.New(Ctx({ cost = mats, price = { [300] = { price = 280, at = NOW - 60, complete = true } } })):Craft(REC, 1)
  Same(e.sellBasis, "lowest", "no competition answer (no tiers saved): the lowest listing") Same(e.unit, 280)
  Check(e.confidence ~= "high", "a scan without a price spread is not High")
  e = E.New(Ctx({ cost = mats, comp = { [300] = { beyond = true, below = { items = 6, listings = 6 } } }, value = { [300] = { market = 250, historical = 240 } } })):Craft(REC, 1)
  Same(e.sellBasis, "market", "every kept price is bait: its Market Value") Same(e.unit, 250)
  e = E.New(Ctx({ cost = mats, value = { [300] = { historical = 240 } } })):Craft(REC, 1)
  Same(e.sellBasis, "historical") Same(e.unit, 240)
  e = E.New(Ctx({ cost = mats, price = { [300] = { price = 400, reference = true, at = NOW - 3600 } }, ref = { [300] = { market = 300 } } })):Craft(REC, 1)
  Same(e.sellBasis, "reference") Same(e.unit, 345, "the reference's Recent Price is capped by the reference's Market Value") Check(e.reference)
  Same(e.confidence, "low", "a reference is at most Low")
  e = E.New(Ctx({ cost = mats })):Craft(REC, 1)
  Same(e.state, "unknown") Same(e.why, "sellprice") Same(e.profitLow, nil, "never a made-up profit")
end

---------------------------------------------------------------------------
-- 4. Materials: vendor against auction, a tie, too few listed, the unit quote, an old scan
---------------------------------------------------------------------------
do
  local one = { id = 2, name = "Thread craft", outItem = 300, outMin = 1, mats = { { item = 400, qty = 5 } } }
  local base = { comp = { [300] = Comp(1000) } }
  local function Run(o) for k, v in pairs(base) do if o[k] == nil then o[k] = v end end return E.New(Ctx(o)):Craft(one, 1) end
  -- a vendor sells stacks of 5 for 40: buying 5 costs 40
  local vendor = { [400] = { p = 40, s = 5, a = -1, at = NOW - 100 } }
  local e = Run({ vendor = vendor, cost = { [400] = Walk({ 9, 9, 9, 9, 9 }) } })
  Same(e.mats[1].source, "vendor", "40 against 45 at the auction house") Same(e.mats[1].total, 40) Same(e.mats[1].auctionLow, 45)
  e = Run({ vendor = vendor, cost = { [400] = Walk({ 8, 8, 8, 8, 8 }) } })
  Same(e.mats[1].source, "vendor", "a tie goes to the vendor (40 = 40)")
  e = Run({ vendor = vendor, cost = { [400] = Walk({ 7, 7, 7, 7, 7 }) } })
  Same(e.mats[1].source, "auction") Same(e.mats[1].total, 35) Same(e.mats[1].vendorCost, 40)
  e = Run({ vendor = vendor })
  Same(e.mats[1].source, "vendor", "no auction price: the vendor") Same(e.state, "ok")
  e = Run({ cost = { [400] = Walk({ 7, 7 }) } })
  Same(e.state, "unknown") Same(e.mats[1].unavailable, "few") Same(e.why, "matprice")
  -- no tiers saved: the old unit quote over the lowest listing, flagged when more are needed than are listed at that price
  e = Run({ price = { [400] = { price = 7, qty = 2, total = 10, at = NOW - 60, complete = true } } })
  Same(e.mats[1].total, 35) Check(e.mats[1].cheapest, "5 needed, 2 at the cheapest price") Check(e.cheapest)
  -- an old scan (over a day) is not trusted below the item's Market Value
  e = Run({ cost = { [400] = Walk({ 7, 7, 7, 7, 7 }, { at = NOW - 2 * 86400 }) }, value = { [400] = { market = 10 } } })
  Same(e.mats[1].total, 50, "5 x 10, the usual value") Same(e.mats[1].typical, "local") Same(e.mats[1].listedLow, 35)
  e = Run({ cost = { [400] = Walk({ 7, 7, 7, 7, 7 }, { at = NOW - 2 * 86400 }) }, value = { [400] = { market = 6 } } })
  Same(e.mats[1].total, 35, "the listings are dearer than usual: they stand") Same(e.mats[1].typical, nil)
  e = Run({ cost = { [400] = Walk({ 7, 7, 7, 7, 7 }, { quality = "limited" }) }, value = { [400] = { market = 10 } } })
  Same(e.mats[1].total, 35, "a fresh scan's listings are walked as they are, even when thin") Same(e.confidence, "low", "but a limited material makes the estimate Low")
end

---------------------------------------------------------------------------
-- 5. The vendor floor, the cut and the deposit
---------------------------------------------------------------------------
do
  local mats = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }
  -- a merchant pays 290; the auction house leaves 300 - 15 (5%) = 285: the vendor is the outlet
  local cut = { rate = 0.05, kind = "faction", source = "assumed", label = "5%, assumed" }
  local e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, vsell = { [300] = 290 }, cut = cut })):Craft(REC, 1)
  Same(e.outlet, "vendor") Same(e.sellLow, 290) Same(e.netLow, 290, "no cut on a vendor sale") Same(e.auctionNetLow, 285) Same(e.profitLow, 20)
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, vsell = { [300] = 284 }, cut = cut })):Craft(REC, 1)
  Same(e.outlet, "auction", "284 < 285") Same(e.cutLow, 15) Same(e.netLow, 285) Same(e.profitLow, 15) Same(e.cutRate, 0.05)
  e = E.New(Ctx({ cost = mats, vsell = { [300] = 100 } })):Craft(REC, 1)
  Same(e.outlet, "vendor", "nothing to sell at the auction house: the merchant's price") Same(e.state, "ok") Same(e.profitLow, -170)
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, vsell = { [300] = 0 } })):Craft(REC, 1)
  Same(e.outlet, "auction", "a vendor value of 0 is no vendor outlet")
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, cutWhy = "off" })):Craft(REC, 1)
  Same(e.cutRate, nil) Same(e.cutWhy, "off") Same(e.netLow, 300)
  -- the deposit: 9 per listing covers floor(30 / 9) = 3 failed listings; 31 is more than the profit
  local asked
  local dep = function(item, qty) asked = { item, qty } return { amount = 9, perItem = 9, n = 2, source = "ledger", durationKnown = true } end
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, deposit = dep })):Craft(REC, 1)
  Same(e.depositTotal, 9) Same(e.covers, 3) Same(asked[1], 300) Same(asked[2], 1, "one craft's output is one listing")
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, deposit = dep })):Craft(REC, 3)
  Same(e.depositTotal, 27, "three crafts are three listings") Same(e.profitLow, 900 - 720 - 90) Same(e.covers, 3, "floor(90 / 27)")
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, deposit = function() return { amount = 31 } end })):Craft(REC, 1)
  Same(e.covers, 0, "one expiry loses more than the profit")
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(260) }, deposit = function() return { amount = 5 } end })):Craft(REC, 1)
  Same(e.profitLow, -10) Same(e.covers, nil, "no profit: nothing to cover")
  e = E.New(Ctx({ cost = mats, vsell = { [300] = 400 }, comp = { [300] = Comp(300) }, deposit = dep })):Craft(REC, 1)
  Same(e.depositTotal, nil, "a vendor sale has no deposit")
end

---------------------------------------------------------------------------
-- 6. Confidence, rising supply, the typical profit, cooldowns
---------------------------------------------------------------------------
do
  local mats = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }
  local e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, quality = { [300] = { level = "fair", reasons = { { code = "age", text = "Last scanned 2 days ago." } }, facts = { listings = 8, observedDays = 10 } } } })):Craft(REC, 1)
  Same(e.confidence, "medium") Same(e.reasons[1].text, "Last scanned 2 days ago.")
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, quality = { [300] = { level = "good", reasons = {}, facts = { listings = 8, observedDays = 3 } } } })):Craft(REC, 1)
  Same(e.confidence, "medium", "listed on few days") Same(e.reasons[1].code, "rare")
  local supplyAsked = false
  local x = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) } }))
  x.ctx.supply = function() supplyAsked = true return nil end
  x:Craft(REC, 1)
  Same(supplyAsked, false, "selling one: the item's history is not read for absorption")
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300, 1000) }, supply = { [300] = { history = { median = 10 } } } })):Craft(REC, 6)
  Check(e.absorb and e.absorb.against == 10, "6 against a usual 10 listed is over half")
  -- the typical profit: herbs usually 80 and crystals 15, the flask usually 295: the materials are cheap now (270 against 350)
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, value = { [100] = { market = 80 }, [200] = { market = 15 }, [300] = { market = 295 } } })):Craft(REC, 1)
  Same(e.typical, nil, "worked out only when shown") Check(E.Typical(e)) Same(E.Typical(e), e.typical, "once")
  Same(e.typical.cost, 350) Same(e.typical.net, 295) Same(e.typical.profit, -55) Check(e.nowOnly, "profitable now only") Same(e.usually, nil)
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, value = { [100] = { market = 80 } } })):Craft(REC, 1)
  Same(E.Typical(e), nil, "a material or the product without a usual value: no typical profit")
  e = E.New(Ctx({ cost = { [100] = Walk(HERB) }, vendor = { [200] = { p = 10, s = 1, a = -1, at = NOW } }, comp = { [300] = Comp(300) },
    value = { [100] = { market = 50 }, [300] = { market = 295 } } })):Craft(REC, 1)
  Same(e.mats[2].source, "vendor") Same(E.Typical(e).cost, 4 * 50 + 20, "a vendor's price stays the vendor's")
  local cd = { id = 9, name = "Transmute", outItem = 300, outMin = 1, mats = { { item = 200, qty = 1 } }, cd = { left = 3600, at = NOW - 600 } }
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) } })):Craft(cd, 1)
  Same(e.cooldown.left, 3000) Same(Op.CooldownText(e), "On cooldown, 50 min left")
  cd.cd = { left = 3600, at = NOW - 600, charges = 1, max = 2 }
  Same(E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) } })):Craft(cd, 1).cooldown, nil, "a charge left: it can be made now")
  cd.cd = { left = 600, at = NOW - 600 }
  Same(E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) } })):Craft(cd, 1).cooldown, nil, "the cooldown has run out")
  Same(Op.Span(90000), "1 d 1 h") Same(Op.Span(7200), "2 h") Same(Op.Span(30), "1 min")
end

---------------------------------------------------------------------------
-- 7. The list: margin sort, equal profits by confidence, hiding Low, the Overview's best
---------------------------------------------------------------------------
do
  local function Row(id, name, profit, cost, conf)
    return { rec = { id = id, name = name, prof = 1 }, est = { state = "ok", profitLow = profit, profitHigh = profit, cost = cost, sellLow = cost + profit, confidence = conf } }
  end
  local rows = { Row(1, "A", 100, 1000, "high"), Row(2, "B", 80, 100, "medium"), Row(3, "C", 100, 500, "low"), Row(4, "D", 500, 50, "low"),
    { rec = { id = 5, name = "E", prof = 1 }, est = { state = "unknown", why = "sellprice" } } }
  local order = {}
  for _, r in ipairs(Op.Select(rows, { sort = "profit", desc = true })) do order[#order + 1] = r.rec.name end
  Same(table.concat(order), "DACBE", "equal profit (A, C): the surer estimate first; unknown last")
  order = {}
  for _, r in ipairs(Op.Select(rows, { sort = "margin", desc = true })) do order[#order + 1] = r.rec.name end
  Same(table.concat(order), "DBCAE", "profit per copper: 10, 0.8, 0.2, 0.1")
  order = {}
  for _, r in ipairs(Op.Select(rows, { sort = "profit", desc = true, hideLow = true })) do order[#order + 1] = r.rec.name end
  Same(table.concat(order), "ABE", "Low-confidence rows hidden; unknown rows stay (they say why)")
  local opts = { sort = "profit", desc = true }
  Op.SetSort(opts, "margin") Same(opts.sort, "margin") Same(opts.desc, true, "margin starts highest first")
  local best, low = Op.Best(rows)
  Same(best.rec.name, "A", "D is Low confidence: the Overview headlines A") Same(low.rec.name, "D")
  best, low = Op.Best({ Row(4, "D", 500, 50, "low") })
  Same(best, nil) Same(low.rec.name, "D")
end

---------------------------------------------------------------------------
-- 8. Fees: the choice, the house kind, the cut against the Ledger, the deposit from the player's postings
---------------------------------------------------------------------------
do
  Same(F.Mode(), "assumed", "the default")
  Check(F.SetMode("off")) Same(F.Mode(), "off") Same(c.TwichUIDB.workshop.view.cut, "off")
  Same(select(2, F.Cut("Alliance")), "off")
  Check(F.SetMode("assumed")) Same(c.TwichUIDB.workshop.view.cut, nil, "the default is stored as nothing")
  Same(F.SetMode("sometimes"), false)
  Same(F.HouseKind("Alliance"), "faction") Same(F.HouseKind("horde"), "faction") Same(F.HouseKind("Neutral"), "neutral") Same(F.HouseKind("Blackwater"), "neutral", "Companion's name for the neutral house") Same(F.HouseKind("unknown"), nil) Same(F.HouseKind(nil), nil)
  local cut = assert(F.Cut("Horde"))
  Same(cut.rate, 0.05) Same(cut.source, "assumed") Same(cut.label, "5%, assumed")
  Same(F.Cut("Neutral").rate, 0.15) Same(select(2, F.Cut(nil)), "house", "an unknown side is never given a rate")
  Same(F.CutOf(1000, cut), 50) Same(F.CutOf(1000, nil), 0) Same(F.RateText(0.125), "12.5%")
  PR.CUT.unknown = 0.03
  cut = assert(F.Cut("unknown"))
  Same(cut.rate, 0.03) Same(cut.source, "confirmed", "a rate confirmed in the code comes first") Same(cut.label, "3%, confirmed")
  PR.CUT.Horde = 0.04 Same(F.Cut("Horde").rate, 0.04, "even over the assumed rate")
  PR.CUT.unknown, PR.CUT.Horde = nil, nil
  -- a fake Ledger: three 5% invoices, one 15%, deposits of item 300 at two durations
  local entries = {
    { t = NOW - 100, k = "ahSale", s = { invoices = { { g = 1000, f = 50 }, { g = 2000, f = 100 } } } },
    { t = NOW - 200, k = "ahSale", s = { invoices = { { g = 999, f = 50 }, { g = 400, f = 60 } } } },
    { t = NOW - 100 * 86400, k = "ahSale", s = { invoices = { { g = 1000, f = 50 } } } },   -- older than the 90 days read
    { t = NOW - 50, k = "ahDeposit", a = -40, i = 300, q = 4, r = 1 },
    { t = NOW - 60, k = "ahDeposit", a = -60, i = 300, q = 2, r = 3 },
    { t = NOW - 70, k = "ahDeposit", a = -24, i = 300, q = 2, r = 1 },
    { t = NOW - 80, k = "ahDeposit", a = -7, i = 301, q = 1 },
  }
  local rev = 1
  c.TwichUI.Ledger = { Revision = function() return rev end, Characters = function() return { { key = "Rich - Realm" } } end,
    Record = function() return { entries = entries } end }
  F.ClearCache()
  local ev = F.Evidence(NOW)
  Same(ev.invoices, 4) Same(ev.match.faction, 3, "50 of 999 is within a copper of 5%") Same(ev.match.neutral, 1)
  Same(ev.rates[1].tenths, 50) Same(ev.rates[1].n, 3)
  cut = F.Cut("Alliance", NOW)
  Same(cut.source, "ledger") Same(cut.label, "5%, matches your sales") Same(F.Cut("Neutral", NOW).source, "assumed", "one 15% invoice is not enough")
  Check(F.EvidenceText():find("4 verified sales", 1, true), F.EvidenceText())
  -- deposits: the shortest duration's postings of item 300 are 10 and 12 per item: the median 11
  local d = assert(F.Deposit(300, 3, 1, NOW))
  Same(d.perItem, 11) Same(d.amount, 33) Check(d.durationKnown) Same(d.n, 2)
  d = assert(F.Deposit(300, 1, 3, NOW)) Same(d.perItem, 30, "the long duration's posting")
  d = assert(F.Deposit(300, 1, 2, NOW)) Check(not d.durationKnown, "no posting at that duration: every posting, labelled") Same(d.perItem, 12)
  d = assert(F.Deposit(301, 2, 1, NOW)) Same(d.amount, 14) Check(not d.durationKnown, "an entry without a duration")
  Same(select(2, F.Deposit(999, 1, 1, NOW)), "none") Same(select(2, F.Deposit(300, 0, 1, NOW)), "badqty")
  Same(F.Covers(30, 9), 3) Same(F.Covers(-1, 9), nil) Same(F.Covers(30, 0), nil)
  -- a new Ledger revision is read again
  entries[#entries + 1] = { t = NOW - 10, k = "ahSale", s = { invoices = { { g = 100, f = 15 }, { g = 200, f = 30 } } } }
  Same(F.Evidence(NOW).invoices, 4, "the same revision is cached")
  rev = 2
  Same(F.Evidence(NOW).match.neutral, 3) Same(F.Cut("Neutral", NOW).source, "ledger")
  c.TwichUI.Ledger = nil
  F.ClearCache()
  Same(F.Evidence(NOW).invoices, 0, "no Ledger: no evidence, and nothing fails")
  Same(F.Duration(), 1, "no Auction House settings: the shortest duration")
  c.TwichUI.WorkshopLauncher = { AuctionSettings = function() return { duration = 3 } end }
  Same(F.Duration(), 3) Same(F.DurationLabel(3), "Long")
  c.TwichUI.WorkshopLauncher = nil
end

---------------------------------------------------------------------------
-- 9. The words: the tooltip and the details of a planning estimate
---------------------------------------------------------------------------
do
  local mats = { [100] = Walk(HERB), [200] = Walk(CRYSTAL) }
  local cut = { rate = 0.05, kind = "faction", source = "assumed", label = "5%, assumed" }
  local e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(900, 1) }, value = { [300] = { market = 295 } }, cut = cut,
    deposit = function() return { amount = 9, durationKnown = false } end,
    quality = { [300] = { level = "limited", reasons = { { code = "listings", text = "Only 1 listing." } }, facts = { listings = 1, observedDays = 20 } } } })):Craft(REC, 1)
  local row = { rec = REC, est = e }
  local tip = Op.Tip(row, { label = "Alliance auction house", at = NOW - 60, complete = true }, Money, NOW)
  Check(Has(tip, "Cost to make | 270c") and Has(tip, "Sell price | 340c") and Has(tip, "Estimated profit | 53c"), Dump(tip))
  Check(Has(tip, "!Confidence: Low (Only 1 listing)"), Dump(tip))
  Check(#tip <= 6, "short: " .. #tip)
  local basis = Op.Basis(row, { label = "Alliance auction house", at = NOW - 60, complete = true }, Name, Money, NOW)
  Check(Has(basis, "4 x item100 | 60c each = 240c"), Dump(basis))
  Check(Has(basis, "Makes 1, sold at 340c each") and Has(basis, "Listed at 900c; counted at 115% of its Market Value."), Dump(basis))
  Check(Has(basis, "Auction house cut (5%, assumed) | -17c"), Dump(basis))
  Check(Has(basis, "Deposit, refunded on a sale | 9c") and Has(basis, "Covers 5 failed listings.") and Has(basis, "duration wasn't recorded"), Dump(basis))
  Check(Has(basis, "Confidence: Low") and Has(basis, "Only 1 listing.") and Has(basis, "not sales"), Dump(basis))
  -- the vendor outlet and the cut that isn't taken
  e = E.New(Ctx({ cost = mats, vsell = { [300] = 500 }, comp = { [300] = Comp(300) }, cutWhy = "house" })):Craft(REC, 1)
  basis = Op.Basis({ rec = REC, est = e }, nil, Name, Money, NOW)
  Check(Has(basis, "Makes 1; a merchant pays 500c each") and Has(basis, "The auction house would leave 300c"), Dump(basis))
  Check(not Has(basis, "Deposit |") and not Has(basis, "Deposit, refunded"), "a vendor sale has no deposit line")
  tip = Op.Tip({ rec = REC, est = e }, nil, Money, NOW)
  Check(Has(tip, "Sell to a vendor | 500c"), Dump(tip))
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) }, cutWhy = "house" })):Craft(REC, 1)
  basis = Op.Basis({ rec = REC, est = e }, nil, Name, Money, NOW)
  Check(Has(basis, "Auction house cut | not deducted (not confirmed)") and Has(basis, "Deposit | not known yet"), Dump(basis))
  Same(Op.ProfitLabel({ est = e }), "Profit before fees")
  -- many crafts say so
  e = E.New(Ctx({ cost = mats, comp = { [300] = Comp(300) } })):Craft(REC, 4)
  Check(Has(Op.Basis({ rec = REC, est = e }, nil, Name, Money, NOW), "For 4 crafts"))
end

---------------------------------------------------------------------------
-- 10. What an item is worth (the tooltip and the Disenchant estimate): the competing price, not one cheap listing
---------------------------------------------------------------------------
do
  local seen
  W.Market = { Competition = function(item, qty, opt) seen = opt.market return item == 1 and { competing = 500 } or (item == 2 and { competing = 90 } or nil) end }
  local q = { item = 1, price = 90, at = NOW, basis = "lowest" }
  local v = E.AtCompeting(q, 1, { market = "Realm|Alliance" })
  Same(v.price, 500) Same(v.lowest, 90) Check(v.competing) Same(v.basis, E.COMPETING_BASIS) Same(q.price, 90, "the caller's table is never changed")
  Same(seen, "Realm|Alliance")
  E.AtCompeting(q, 1, { market = { pricing = true, localMarket = "LOCAL" } })
  Same(seen, "LOCAL", "a reference source is asked about its local scan")
  Same(E.AtCompeting(q, 2, {}), q, "the same price: unchanged")
  Same(E.AtCompeting(q, 3, {}), q, "no competing price: unchanged")
  local ref = { price = 90, reference = true }
  Same(E.AtCompeting(ref, 1, {}), ref, "a reference keeps its Recent Price")
  Same(E.AtCompeting(q, 1, { variant = true }), q, "a variant is never given the base item's competition")
  Same(E.AtCompeting(nil, 1, {}), nil)
  W.Market = { Competition = function() error("unreadable") end }
  Same(E.AtCompeting(q, 1, {}), q, "a failing service leaves the quote as it was")
  W.Market = nil
end

print("PASSED")
