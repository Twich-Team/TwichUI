-- TwichUI Test Lab: the core calculation cases (category "core", class pure, they need the Workshop)
-- ONE definition, TWO interpreters: tests/test_testlab.lua loads this very file under the offline mock and runs every case through the
-- real Runner, and the Lab runs it in the game client. Each case calls production functions with EXPLICIT inputs on made-up data. Nothing
-- here reads or writes saved variables; markets are tables built below and handed in through opt.market / a lookup function.
--
-- Every expected value was worked out by hand (the arithmetic is in the comment above it), never copied from a run of the code. If a
-- case fails, first decide whether the hand arithmetic or the code is wrong; do not change one to match the other without that.

local R = TwichUI
local TL = R.TestLab

TL.Category{ id = "core", label = "Core calculations", blurb = "Prices, quotes, history and statistics on made-up data (the same cases run offline)" }

local DAY = 86400

local function Pure(id, run) TL.Case{ id = id, cat = "core", class = "pure", needs = { "workshop" }, budget = 2, run = run } end

-- A market table as Market.* accepts through opt.market, built fresh each time (no shared mutable data between cases). Day 108 is the
-- day of the scan; every hist string is typed out, in History's own format (recent days "day,price;...", then "|", then 28-day buckets
-- "b,lo,hi,sum,n;...").
local SCAN_AT = 108 * DAY + 7200            -- 02:00 UTC on day 108
local function Market(extra)
    local m = {
        realm = "Synthetic", side = "Alliance", scope = "full", complete = true, cut = false, partial = 0, at = SCAN_AT, n = 6,
        items = {
            [10] = "80,15,4,39,100",    -- cheapest 80 each, 15 items at 80, 4 listings, 39 items listed, next price 100
            [11] = "150,2,1,2,0",       -- one listing of 2 items at 150 each
            [20] = "1002,4,3,9,1100",
            [30] = "1800,3,2,5,1900",
            [31] = "2000,1,1,1,0",      -- a single listing
        },
        hist = {
            -- days 102..108 exact (1200 .. 1800, +100 a day), and a bucket 3 (days 84..111) holding days 100 and 101 (1000, 1100)
            [30] = "102,1200;103,1300;104,1400;105,1500;106,1600;107,1700;108,1800|3,1000,1100,2100,2",
            [41] = "103,3000;106,2000|",
            [42] = "105,300;107,401|",
            [43] = "107,500|",
        },
        scanDays = { 100, 101, 102, 103, 104, 105, 106, 107, 108 },
    }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
end

local function LookupIn(PR, m)
    return function(item) return PR.Lookup(m, item) end
end

---------------------------------------------------------------------------
-- Stack and unit prices
---------------------------------------------------------------------------
Pure("price.unit.round-up", function(t)
    local PR = t.W.Prices
    t:Same(PR.Unit(300, 3), 100, "300 for 3 divides exactly")
    t:Same(PR.Unit(301, 3), 101, "301 for 3 is 100.33, rounded UP to whole copper")
    t:Same(PR.Unit(1, 50), 1, "never below one copper")
    t:Same(PR.Unit(99999999999, 1), 99999999999, "the largest buyout the game allows")
    -- 99999999999 / 7 = 14285714285.571..., rounded up
    t:Same(PR.Unit(99999999999, 7), 14285714286, "the largest buyout over 7 items")
end)

Pure("price.unit.refusals", function(t)
    local PR = t.W.Prices
    t:Same(PR.Unit(0, 1), nil, "no buyout is not a price")
    t:Same(PR.Unit(100, 0), nil, "no items is not a stack")
    t:Same(PR.Unit(1.5, 1), nil, "a fractional copper")
    t:Same(PR.Unit(100, 2.5), nil, "a fractional count")
    t:Same(PR.Unit(-5, 1), nil, "a negative buyout")
    t:Same(PR.Unit("100", 1), nil, "text is not a number")
    t:Same(PR.Unit(100000000000, 1), nil, "one copper above the game's maximum")
    t:Same(PR.Unit(100, 10001), nil, "more items than one auction holds")
    t:Same(PR.Unit(math.huge - math.huge, 1), nil, "not a number (NaN)")
end)

---------------------------------------------------------------------------
-- A batch of auction records
---------------------------------------------------------------------------
Pure("price.batch.cheapest", function(t)
    local PR = t.W.Prices
    local b = PR.NewBatch()
    -- unit prices: 2000/20 = 100, 400/5 = 80, 800/10 = 80, 1000/4 = 250
    t:Check(b:Add(10, 20, 2000), "20 items for 2000 counts")
    t:Check(b:Add(10, 5, 400), "5 items for 400 counts")
    t:Check(b:Add(10, 10, 800), "10 items for 800 counts")
    t:Check(b:Add(10, 4, 1000), "4 items for 1000 counts")
    t:Check(not b:Add(10, 1, 0), "a bid-only auction does not count")
    t:Check(not b:Add(10, 0, 100), "a stack of none does not count")
    t:Same(b.noBuyout, 1, "one bid-only record")
    t:Same(b.invalid, 1, "one invalid record")
    t:Same(b.read, 6, "six records read")
    t:Same(b.used, 4, "four records priced")
    local items, n, over, dropped = b:Items()
    -- cheapest 80; items at exactly 80: 5 + 10 = 15; buyout listings 4; items in them 20 + 5 + 10 + 4 = 39; next higher unit price 100
    t:Same(items[10], "80,15,4,39,100", "the saved entry of item 10")
    t:Same(n, 1, "one item kept")
    t:Same(over, false, "not over the item limit")
    t:Same(dropped, 0, "none dropped")
end)

Pure("price.batch.next-price", function(t)
    local PR = t.W.Prices
    local b = PR.NewBatch()
    for _, buyout in ipairs({ 500, 300, 400, 300, 900 }) do b:Add(6, 1, buyout) end
    -- cheapest 300, two items at it, five listings, five items, the next higher price is 400 whatever the arrival order
    t:Same(b:Items()[6], "300,2,5,5,400", "the next higher price is the lowest above the cheapest")
    -- 7 for 700 is 100 each; 3 for 299 is 99.67 each, rounded up to 100: the same copper, so no "next" price
    b = PR.NewBatch()
    b:Add(5, 7, 700); b:Add(5, 3, 299)
    t:Same(b:Items()[5], "100,3,2,10,0", "99.67 each is the cheaper listing, and it rounds to the same copper")
end)

---------------------------------------------------------------------------
-- Lookups and quotes
---------------------------------------------------------------------------
Pure("price.lookup.fields", function(t)
    local PR = t.W.Prices
    local m = Market()
    local p = PR.Lookup(m, 10)
    t:Check(p ~= nil, "item 10 is priced")
    if not p then return end
    t:Same(p.price, 80, "price")
    t:Same(p.qty, 15, "items at that price")
    t:Same(p.listings, 4, "listings")
    t:Same(p.total, 39, "items listed")
    t:Same(p.next, 100, "next higher price")
    t:Same(p.at, SCAN_AT, "scan time")
    t:Same(p.complete, true, "complete")
    t:Same(PR.Lookup(m, 11).next, nil, "a next price of 0 is none")
    t:Same(PR.Lookup(m, 55), nil, "an item the scan did not list")
    t:Same(PR.Lookup({ items = { [7] = "0,1,1,1,0" } }, 7), nil, "a price of 0 is never a price")
    t:Same(PR.Lookup({ items = { [7] = "90,2,3,9" } }, 7).price, 90, "an older four-field entry still reads")
    t:Same(PR.Lookup({ items = { [7] = { 70, 2, 1, 3 } } }, 7).total, 3, "an entry from before full scans (a table)")
end)

Pure("price.quote.states", function(t)
    local PR = t.W.Prices
    local p = PR.Lookup(Market(), 10)   -- 80 each, 15 at that price, 39 listed
    local q = PR.Quote(p, 10)
    t:Same(q.state, "exact", "10 is within the 15 at the cheapest price"); t:Same(q.cost, 800, "10 x 80")
    q = PR.Quote(p, 15)
    t:Same(q.state, "exact", "exactly the 15 at the cheapest price"); t:Same(q.cost, 1200, "15 x 80")
    q = PR.Quote(p, 16)
    t:Same(q.state, "estimate", "16 is more than the 15 at the cheapest price"); t:Same(q.cost, 1280, "16 x 80, the least it could cost")
    q = PR.Quote(p, 39)
    t:Same(q.state, "estimate", "all 39 listed"); t:Same(q.cost, 3120, "39 x 80")
    q = PR.Quote(p, 40)
    t:Same(q.state, "few", "more than are listed"); t:Same(q.cost, nil, "no cost")
    t:Same(PR.Quote(nil, 3).state, "none", "no price seen")
    t:Same(PR.Quote(p, 0).state, "none", "a quantity of 0")
end)

---------------------------------------------------------------------------
-- What one craft costs and earns
---------------------------------------------------------------------------
Pure("price.estimate.range-cut", function(t)
    local PR = t.W.Prices
    local lookup = LookupIn(PR, Market())
    -- two materials: 5 of item 10 at 80 = 400 and 2 of item 11 at 150 = 300, cost 700. It makes 1 to 3 of item 20 at 1002 each:
    -- sells for 1002 to 3006. With a cut of 0.25 passed as the ARGUMENT: 1002 x .25 = 250.5, +.5 = 251 whole; 3006 x .25 = 751.5, +.5 = 752.
    -- net 751 to 2254, profit 51 to 1554.
    local rec = { outItem = 20, outMin = 1, outMax = 3, mats = { { item = 10, qty = 5 }, { item = 11, qty = 2 } } }
    local e = PR.Estimate(rec, lookup, 0.25)
    t:Same(e.state, "ok", "state")
    t:Same(e.cost, 700, "cost")
    t:Same(e.mats[1].total, 400, "item 10 row"); t:Same(e.mats[2].total, 300, "item 11 row")
    t:Same(e.sellLow, 1002, "sells for at least"); t:Same(e.sellHigh, 3006, "sells for at most")
    t:Same(e.netLow, 751, "net at the fewest"); t:Same(e.netHigh, 2254, "net at the most")
    t:Same(e.profitLow, 51, "profit at the fewest"); t:Same(e.profitHigh, 1554, "profit at the most")
    t:Same(e.cheapest, false, "every material is within the cheapest listing")
    t:Same(e.incomplete, false, "the scan was complete")
    -- with no confirmed cut the profit is before the cut: 1002 - 700 = 302 and 3006 - 700 = 2306
    e = PR.Estimate(rec, lookup, nil)
    t:Same(e.profitLow, 302, "profit before a cut, fewest"); t:Same(e.profitHigh, 2306, "profit before a cut, most")
end)

Pure("price.estimate.minimum-flag", function(t)
    local PR = t.W.Prices
    local lookup = LookupIn(PR, Market())
    -- 20 of item 10 when only 15 are listed at 80 (39 listed in all): 20 x 80 = 1600 is the LEAST it could cost, and the flag says so.
    -- It makes one item 20 at 1002, no cut: profit 1002 - 1600 = -598.
    local e = PR.Estimate({ outItem = 20, outMin = 1, outMax = 1, mats = { { item = 10, qty = 20 } } }, lookup, nil)
    t:Same(e.state, "ok", "state"); t:Same(e.cost, 1600, "cost is the minimum")
    t:Same(e.cheapest, true, "flagged: more than the cheapest listing holds")
    t:Same(e.mats[1].cheapest, true, "the row is flagged")
    t:Same(e.profitLow, -598, "profit"); t:Same(e.profitHigh, -598, "a single output has no range")
    -- 40 of item 10 when only 39 are listed: it cannot be bought in that quantity, so the cost is unknown, never a guess
    e = PR.Estimate({ outItem = 20, outMin = 1, outMax = 1, mats = { { item = 10, qty = 40 } } }, lookup, nil)
    t:Same(e.state, "unknown", "state"); t:Same(e.why, "matprice", "why"); t:Same(e.cost, nil, "no cost")
    t:Same(e.mats[1].unavailable, "few", "the row says why"); t:Same(e.profitLow, nil, "no profit")
end)

Pure("price.estimate.unknown", function(t)
    local PR = t.W.Prices
    local lookup = LookupIn(PR, Market())
    local function Why(rec) local e = PR.Estimate(rec, lookup, nil); return e.state, e.why end
    local mats = { { item = 10, qty = 5 } }
    local state, why = Why({ outItem = 20, outMin = 1, outMax = 1, mats = {} })
    t:Same(state, "unknown", "no materials: state"); t:Same(why, "nomats", "no materials: why")
    state, why = Why({ outMin = 1, outMax = 1, mats = mats })
    t:Same(why, "noitem", "no output item")
    state, why = Why({ outItem = 20, mats = mats })
    t:Same(why, "noamount", "no output amount")
    state, why = Why({ outItem = 20, outMin = 1, outMax = 1, mats = { { item = 77, qty = 1 } } })
    t:Same(why, "matprice", "a material nobody listed")
    local e = PR.Estimate({ outItem = 99, outMin = 1, outMax = 1, mats = mats }, lookup, nil)
    t:Same(e.why, "sellprice", "what it makes has no price")
    t:Same(e.cost, 400, "the materials' cost is still known: 5 x 80")
    t:Same(e.profitLow, nil, "but there is no profit")
end)

---------------------------------------------------------------------------
-- Owned items
---------------------------------------------------------------------------
Pure("stock.split.order", function(t)
    local W = t.W
    local function Split(...) local b, k, g, rest = W.Split(...); return b .. "/" .. k .. "/" .. g .. "/" .. rest end
    t:Same(Split(10, 4, 3, 5), "4/3/3/0", "bags first (4), then the bank (3), then the guild bank takes the last 3")
    t:Same(Split(10, 4, 3, 2), "4/3/2/1", "all of it, and 1 still missing")
    t:Same(Split(5, 9, 9, 9), "5/0/0/0", "the bags cover it, the rest is not touched")
    t:Same(Split(4, nil, -1, 6), "0/0/4/0", "an unknown or negative amount counts as none")
    t:Same(Split(nil, 5, 5, 5), "0/0/0/0", "nothing wanted")
end)

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------
Pure("history.add.fold", function(t)
    local H = t.W.History
    local s
    for i = 0, 6 do s = H.Add(s, 100 + i, 1000 + 100 * i) end
    t:Same(s, "100,1000;101,1100;102,1200;103,1300;104,1400;105,1500;106,1600|", "seven days are kept exactly, nothing is folded")
    -- an eighth day folds the oldest (day 100, 1000) into bucket 100 // 28 = 3 (days 84..111)
    s = H.Add(s, 107, 1700)
    t:Same(s, "101,1100;102,1200;103,1300;104,1400;105,1500;106,1600;107,1700|3,1000,1000,1000,1", "day 100 folds into bucket 3")
    -- a ninth folds day 101 (1100) into the same bucket: low 1000, high 1100, sum 2100, 2 days
    s = H.Add(s, 108, 1800)
    t:Same(s, "102,1200;103,1300;104,1400;105,1500;106,1600;107,1700;108,1800|3,1000,1100,2100,2", "day 101 joins bucket 3")
end)

Pure("history.add.rules", function(t)
    local H = t.W.History
    t:Same(H.Add("100,1000|", 100, 900), "100,900|", "a second scan on the same day replaces that day's value")
    local s, why = H.Add("100,1000|", 99, 5)
    t:Same(s, nil, "an older day is refused"); t:Same(why, "stale", "and called stale")
    s, why = H.Add(nil, 0, 5); t:Same(why, "bad", "day 0 is not a day")
    s, why = H.Add(nil, 5, 0); t:Same(why, "bad", "a price of 0 is not a price")
    s, why = H.Add(nil, 5, 1.5); t:Same(why, "bad", "a fractional price")
    -- day 250 is 142 days after day 108: more than the 120 days kept. The eighth point folds day 102 first, then everything older than
    -- day 250 - 120 = 130 expires, bucket 3 (it ends on day 111) with it.
    local old = "102,1200;103,1300;104,1400;105,1500;106,1600;107,1700;108,1800|3,1000,1100,2100,2"
    t:Same(H.Add(old, 250, 5000), "250,5000|", "nothing older than 120 days survives")
    t:Same(H.Decode("garbage"), nil, "a malformed string is no history")
end)

---------------------------------------------------------------------------
-- The market API, on a table handed in (never the saved markets)
---------------------------------------------------------------------------
local NOW = SCAN_AT + 3600   -- 03:00 on day 108

Pure("market.price.latest", function(t)
    local MK = t.W.Market
    local p = MK.Price(30, { market = Market(), now = NOW })
    t:Check(p ~= nil, "item 30 is priced")
    if not p then return end
    t:Same(p.price, 1800, "price"); t:Same(p.qty, 3, "items at it"); t:Same(p.listings, 2, "listings")
    t:Same(p.total, 5, "items listed"); t:Same(p.next, 1900, "next price")
    t:Same(p.age, 3600, "scanned an hour ago"); t:Same(p.old, false, "not old")
    t:Same(#p.notes, 0, "no qualifying notes")
    t:Same(p.label, "the Alliance auction house on Synthetic", "which auction house")
end)

Pure("market.price.refusals-notes", function(t)
    local MK = t.W.Market
    local m = Market()
    local function Why(item, opt) local p, why = MK.Price(item, opt); return p and "priced" or why end
    t:Same(Why(99, { market = m, now = NOW }), "unlisted", "a full scan listed no buyout for it")
    t:Same(Why(0, { market = m, now = NOW }), "baditem", "not an item")
    t:Same(Why(30, { market = m, now = NOW, variant = true }), "variant", "a variant is never given the base item's price")
    t:Same(Why(99, { market = Market({ scope = "recipes" }), now = NOW }), "outofscope", "an older scan of recipe items says nothing of absence")
    t:Same(MK.Price(31, { market = m, now = NOW }).notes[1], "thin", "a single listing is noted")
    -- 90000 s after the scan is more than a day (86400): old
    local old = MK.Price(30, { market = m, now = SCAN_AT + 90000 })
    t:Same(old.old, true, "more than a day"); t:Same(old.notes[1], "old", "and noted")
    local cut = MK.Price(30, { market = Market({ cut = true, partial = 3 }), now = NOW })
    t:Same(cut.notes[1], "partial", "partial records are noted"); t:Same(cut.notes[2], "cut", "a cut scan is noted")
end)

Pure("market.stats.week", function(t)
    local MK = t.W.Market
    local s = MK.Stats(30, "week", { market = Market(), now = NOW })
    t:Check(s ~= nil, "item 30 has a week")
    if not s then return end
    -- the 7 days 102..108 hold 1200 .. 1800: sum 10500, mean 1500
    t:Same(s.n, 7, "days observed"); t:Same(s.low, 1200, "lowest"); t:Same(s.high, 1800, "highest"); t:Same(s.average, 1500, "mean of the days")
    t:Same(s.from, 102, "window start"); t:Same(s.to, 108, "window end")
    t:Same(s.scans, 7, "scan days in the window")
    t:Same(s.exact, true, "only exact days"); t:Same(s.limited, false, "nothing straddles the start")
    t:Same(s.newest.day, 108, "newest day"); t:Same(s.newest.price, 1800, "newest price")
    t:Same(MK.Stats(99, "week", { market = Market(), now = NOW }), nil, "no history for an unseen item")
end)

Pure("market.stats.retained", function(t)
    local MK = t.W.Market
    -- on day 111 bucket 3 (days 84..111) lies wholly inside everything kept: 7 exact days (sum 10500) + 2 bucket days (sum 2100)
    -- = 9 days, sum 12600, mean 1400; lowest 1000 (the bucket's), highest 1800
    local s = MK.Stats(30, "retained", { market = Market(), now = 111 * DAY + 3600 })
    t:Check(s ~= nil, "retained history")
    if not s then return end
    t:Same(s.n, 9, "days"); t:Same(s.low, 1000, "lowest"); t:Same(s.high, 1800, "highest"); t:Same(s.average, 1400, "mean")
    t:Same(s.exact, false, "a bucket contributed"); t:Same(s.limited, false, "none left out")
    t:Same(s.scans, 9, "scan days")
end)

Pure("market.trend.percent", function(t)
    local MK = t.W.Market
    local m = Market()
    local function Trend(item) return MK.Trend(item, 7, { market = m, now = NOW }) end
    -- item 30: 1200 on day 102 to 1800 on day 108, +600: 600 / 1200 = 50.0%
    local up = Trend(30)
    t:Same(up.direction, "up", "direction"); t:Same(up.change, 600, "change"); t:Same(up.percent, 50, "percent"); t:Same(up.n, 7, "days")
    -- item 41: 3000 on day 103 to 2000 on day 106: -1000 / 3000 = -33.33%, to one decimal -33.3. (M1 expected -33.4 here, "the way the
    -- code states": the value was copied from the code, whose negative rounding was wrong by one tenth; fixed in M2, see the roadmap.)
    local down = Trend(41)
    t:Same(down.direction, "down", "direction"); t:Same(down.change, -1000, "change"); t:Same(down.percent, -33.3, "negative percent")
    t:Same(down.fromDay, 103, "first day"); t:Same(down.toDay, 106, "last day")
    -- item 42: 300 to 401: +101 / 300 = 33.67%, floor(336.67 + 0.5) = 337, / 10 = 33.7
    t:Same(Trend(42).percent, 33.7, "positive percent")
    local none, why = Trend(43)
    t:Same(none, nil, "one observed day is not a trend"); t:Same(why, "insufficient", "and says so")
end)

Pure("market.compare.earlier-days", function(t)
    local MK = t.W.Market
    -- the current price (1800, scanned on day 108) is compared with the week of days BEFORE day 108, 101..107: the exact days 102..107
    -- (1200 .. 1700, sum 8700 over 6 days, mean 1450); bucket 3 straddles the start of that window so its 2 days are left out and said so
    local c = MK.Compare(30, "week", { market = Market(), now = NOW })
    t:Check(c ~= nil, "a comparison")
    if not c then return end
    t:Same(c.current, 1800, "current"); t:Same(c.reference, 1450, "reference mean"); t:Same(c.relation, "above", "relation")
    t:Same(c.difference, 350, "difference"); t:Same(c.n, 6, "days behind the reference")
    t:Same(c.limited, true, "a straddling bucket was left out")
    t:Check(math.abs(c.ratio - 1.2413793) < 0.000001, "ratio is 1800 / 1450 = 1.24138")
end)
