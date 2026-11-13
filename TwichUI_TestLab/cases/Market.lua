-- TwichUI Test Lab: market reference cases (category "core", class pure, they need the Workshop)
-- A SMALL, BOUNDED selection of the reference-model comparisons that tests/test_workshop_market_reference.lua runs by the hundred offline:
-- here a handful of fixed seeds, so the client's Lua and the plain Lua 5.1 of the tests can be compared on the same scenarios. Everything is
-- made-up data (TL.Fixtures, seeds typed below); production functions are called with explicit inputs only (History.Add/Trim for the
-- history, Market.* through an opt.market table), never through the saved markets, and nothing is saved. To reproduce a failure offline,
-- run the test with MARKET_SEED=<the seed in the message>.
--
-- Seeds: batch 7100001..7100016, history 7200001..7200006, mirror 7400001..7400040.
--
-- WHEN THE MODEL AND PRODUCTION DISAGREE the case names the FIRST record they classify differently (its fields, both answers, and the
-- number primitives of the field that differs), instead of only counting: the first real-client run (2026-11-12) found the model counting a
-- NaN count as valid, and counts alone could not say which record or why. A report holds at most a handful of records, never the batch.

local R = TwichUI
local TL = R.TestLab
local FX, REF = TL.Fixtures, TL.Reference

local DAY = 86400

local function Pure(id, run) TL.Case{ id = id, cat = "core", class = "pure", needs = { "workshop" }, budget = 5, run = run } end

local function EntryOf(p) return ("%.0f,1,1,1,0"):format(p) end   -- %.0f for money: the client's %d refuses numbers beyond 32 bits

-- How one record is read, by the model and by production, each on a batch of its own: "priced", "bid-only" or "invalid"
local function ModelClass(r)
    local e = REF.ExpectBatch({ r })
    return e.used == 1 and "priced" or (e.noBuyout == 1 and "bid-only" or (e.invalid == 1 and "invalid" or "unclassified"))
end
local function ProductionClass(PR, r)
    local b = PR.NewBatch()
    b:Add(r.item, r.count, r.buyout, r.info)
    return b.used == 1 and "priced" or (b.noBuyout == 1 and "bid-only" or (b.invalid == 1 and "invalid" or "unclassified"))
end

-- a field for a report: its type and value, whole numbers in full, anything else by %.14g or tostring (a NaN prints as the client writes it)
local function Show(v)
    if type(v) == "number" then return ("number %s"):format(tostring(v)) end
    if type(v) == "string" then return ("string %q"):format(v):sub(1, 30) end
    return type(v) .. " " .. tostring(v)
end

local FIELDS = { { "item", 1, 2147483647 }, { "count", 1, 10000 }, { "buyout", 0, 99999999999 } }

-- The first record the model and production read differently: its index and fields, both answers, and the primitives of its numeric
-- fields. nil when every record is read the same way. Bounded: it looks at the records handed in, reports one.
local function FirstDivergence(PR, records)
    for i, r in ipairs(records) do
        local m, p = ModelClass(r), ProductionClass(PR, r)
        if m ~= p then
            local parts = { ("record %d (%s): item %s, count %s, buyout %s, model %s, production %s"):format(
                i, tostring(r.intent), Show(r.item), Show(r.count), Show(r.buyout), m, p) }
            for _, f in ipairs(FIELDS) do
                local v = r[f[1]]
                if type(v) == "number" and not REF.Whole(v, f[2], f[3]) then
                    parts[#parts + 1] = ("%s: %s"):format(f[1], REF.NumberProbe(v, f[2], f[3]))
                end
            end
            return table.concat(parts, " | "), i
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- The auction batch against the model
---------------------------------------------------------------------------
Pure("market.reference.batch", function(t)
    local PR = t.W.Prices
    if not (FX and REF) then t:Skip("the fixtures or the reference model are not loaded") end
    for i = 1, 16 do
        local seed = 7100000 + i
        local gen = FX.Listings(seed, { items = 3, records = 30 + i, tiers = 1 + i % 3 })
        local exp = REF.ExpectBatch(gen.records)
        local b = PR.NewBatch()
        for _, r in ipairs(gen.records) do b:Add(r.item, r.count, r.buyout, r.info) end
        local items, n = b:Items()
        local tag = "seed " .. seed
        local first, at = FirstDivergence(PR, gen.records)
        if first then
            t:Check(false, tag .. ": first differing record: " .. first:sub(1, 200))
            t:Note(tag .. " " .. first)
        end
        t:Same(n, exp.n, tag .. ": items priced")
        t:Same(b.used, exp.used, tag .. ": records used")
        t:Same(b.noBuyout, exp.noBuyout, tag .. ": bid-only records")
        t:Same(b.invalid, exp.invalid, tag .. ": invalid records")
        t:Same(b.read, b.used + b.noBuyout + b.invalid, tag .. ": every record is accounted for")
        for item, e in pairs(exp.items) do
            t:Same(items[item], REF.EntryText(e), ("%s item %d: p,q,l,t,x"):format(tag, item))
        end
        t:Yield()
    end
end)

---------------------------------------------------------------------------
-- Every malformed value the generator draws, one at a time, in each field of an otherwise valid record
---------------------------------------------------------------------------
-- The contract (Prices.lua): an item, a count and a buyout that are not whole numbers in range are INVALID records; a valid item and count
-- with a buyout of exactly 0 is bid-only. This case puts each malformed value (a NaN, an infinity, a fraction, a string, a boolean, a number
-- past a limit, no value at all) in one field of a good record and asks the model and production, each on its own: both must say invalid, and
-- the limits themselves must be priced. A disagreement names the field and the value and prints the number primitives (REF.NumberProbe).
Pure("market.reference.invalid-values", function(t)
    local PR = t.W.Prices
    if not (FX and REF and FX.BAD) then t:Skip("the fixtures or the reference model are not loaded") end
    local good = { item = 4000, count = 5, buyout = 1000, info = true }
    local function With(field, value)
        local r = { item = good.item, count = good.count, buyout = good.buyout, info = true }
        r[field] = value
        return r
    end
    local function Both(r, want, what)
        local m, p = ModelClass(r), ProductionClass(PR, r)
        if m ~= want or p ~= want then
            t:Check(false, ("%s: model %s, production %s, expected %s"):format(what, m, p, want))
            local f = what:match("^(%a+) ")
            for _, spec in ipairs(FIELDS) do
                if spec[1] == f and type(r[f]) == "number" then t:Note(what .. " " .. REF.NumberProbe(r[f], spec[2], spec[3])) end
            end
        else
            t:Check(true)
        end
    end
    for _, spec in ipairs(FIELDS) do
        local field, lo, hi = spec[1], spec[2], spec[3]
        for i = 1, #FX.BAD[field] do
            Both(With(field, FX.BAD[field][i]), "invalid", ("%s %s"):format(field, Show(FX.BAD[field][i])))
        end
        Both(With(field, nil), "invalid", field .. " missing")
        Both(With(field, math.huge * -1), "invalid", field .. " -inf")
        Both(With(field, 0 / 0 * -1), "invalid", field .. " negated NaN")
        if field ~= "buyout" then
            Both(With(field, lo), "priced", field .. " at its lowest, " .. lo)
            Both(With(field, hi), "priced", field .. " at its highest, " .. hi)
            Both(With(field, hi + 1), "invalid", field .. " one past its highest")
            Both(With(field, lo - 1), "invalid", field .. " one below its lowest")
        else
            Both(With(field, 1), "priced", "buyout at its lowest, 1")
            Both(With(field, hi), "priced", "buyout at its highest, " .. hi)
            Both(With(field, hi + 1), "invalid", "buyout one past its highest")
            Both(With(field, 0), "bid-only", "buyout exactly 0")
        end
    end
    -- a bad count or item beats a buyout of 0: malformed comes first
    Both({ item = 4000, count = 0 / 0, buyout = 0 }, "invalid", "count NaN with buyout 0")
    Both({ item = 4000, count = 0, buyout = 0 }, "invalid", "count 0 with buyout 0")
    Both({ item = 0 / 0, count = 5, buyout = 0 }, "invalid", "item NaN with buyout 0")
    Both({ item = 4000, count = 5, buyout = 0 / 0 }, "invalid", "buyout NaN is not bid-only")
    t:Yield()
end)

---------------------------------------------------------------------------
-- Non-finite numbers and the bid-only test, in this client (found 2026-11-12: a NaN buyout was read as bid-only, because in Forever a NaN
-- equals 0). Production decides finiteness with W.Finite, from the printed form, before any comparison. This case asks the client directly:
-- the finiteness answers for every NaN/infinity form, each field of a record, the accounting of a mixed batch, and that a finite zero is
-- still bid-only. (Which comparisons this client's NaN passes is reported by client.lua.nan-comparisons.)
---------------------------------------------------------------------------
Pure("market.finite.records", function(t)
    local W, PR = t.W, t.W.Prices
    local nan = 0 / 0
    local inf = math.huge
    local forms = { { "runtime NaN", nan }, { "negated NaN", -nan }, { "NaN times -1", nan * -1 }, { "+inf", inf }, { "-inf", -inf },
        { "inf - inf", inf - inf }, { "inf * 0", inf * 0 } }
    for _, f in ipairs(forms) do t:Check(W.Finite(f[2]) == false, f[1] .. " is not finite (prints " .. tostring(f[2]) .. ")") end
    for _, v in ipairs({ 0, -0, 1, 99999999999, 2 ^ 53, 1e300 }) do t:Check(W.Finite(v) == true, "finite: " .. tostring(v)) end
    local function Class(item, count, buyout)
        local b = PR.NewBatch()
        b:Add(item, count, buyout, true)
        return b.used == 1 and "priced" or (b.noBuyout == 1 and "bid-only" or (b.invalid == 1 and "invalid" or "unclassified"))
    end
    t:Same(Class(7, 5, 0), "bid-only", "finite zero buyout")
    t:Same(Class(7, 5, -0), "bid-only", "negative zero buyout")
    for _, f in ipairs(forms) do
        t:Same(Class(7, 5, f[2]), "invalid", "buyout " .. f[1])
        t:Same(Class(7, f[2], 0), "invalid", "count " .. f[1] .. " with no buyout")
        t:Same(Class(f[2], 5, 0), "invalid", "item " .. f[1] .. " with no buyout")
    end
    t:Same(Class(7, 5, -1), "invalid", "negative buyout"); t:Same(Class(7, 5, "100"), "invalid", "string buyout")
    t:Same(Class(7, 5, 100), "priced", "ordinary buyout")
    local b = PR.NewBatch()
    local recs = { { 7, 2, 10 }, { 7, 4, 12 }, { 7, 3, 0 }, { 8, 1, 0 }, { 7, 1, nan }, { 7, 1, -nan }, { 7, 1, inf }, { 7, 1, -inf },
        { 7, nan, 1 }, { nan, 1, 1 }, { 7, 1, -5 }, { 8, 2, 50 } }
    for _, r in ipairs(recs) do b:Add(r[1], r[2], r[3], true) end
    t:Same(b.read, 12, "read"); t:Same(b.used, 3, "priced"); t:Same(b.noBuyout, 2, "bid-only"); t:Same(b.invalid, 7, "invalid")
    t:Same(b.read, b.used + b.noBuyout + b.invalid, "every record is accounted for once")
    local items = b:Items()
    t:Same(items[7], "3,4,2,6,5", "item 7"); t:Same(items[8], "25,2,1,2,0", "item 8")
    t:Yield()
end)

---------------------------------------------------------------------------
-- The history and the statistics against the full-history model
---------------------------------------------------------------------------
-- What production keeps for the model's item, in History's own flat arrays
local function View(item)
    local pts, bks = {}, {}
    for _, pt in ipairs(item:Points()) do pts[#pts + 1] = pt.day pts[#pts + 1] = pt.price end
    for _, k in ipairs(item:Buckets()) do
        bks[#bks + 1] = k.b bks[#bks + 1] = k.lo bks[#bks + 1] = k.hi bks[#bks + 1] = k.sum bks[#bks + 1] = k.n
    end
    return table.concat(pts, ",") .. "|" .. table.concat(bks, ",")
end

local function Flat(s, H)
    local pts, bks = H.Decode(s)
    if not pts then return "undecodable" end
    return table.concat(pts, ",") .. "|" .. table.concat(bks, ",")
end

Pure("market.reference.history", function(t)
    local H, MK = t.W.History, t.W.Market
    if not (FX and REF) then t:Skip("the fixtures or the reference model are not loaded") end
    for i = 1, 6 do
        local seed = 7200000 + i
        local cal = FX.Calendar(seed, { scans = 24, items = 3, cut = 0, style = i % 2 == 0 and "boundary" or "mixed" })
        local model = REF.NewMarket(cal.key)
        local hist, sd = {}, {}
        local last
        for n, s in ipairs(cal.scans) do
            -- what a whole-read scan does to the histories, with History's own functions (no saved market is read or written)
            local touched = {}
            for id, p in pairs(s.items) do
                local str = H.Add(hist[id], s.day, p)
                if str then hist[id] = str touched[id] = true end
            end
            for id, str in pairs(hist) do
                if not touched[id] then hist[id] = H.Trim(str, s.day) end
            end
            if sd[#sd] ~= s.day and (sd[#sd] == nil or sd[#sd] < s.day) then sd[#sd + 1] = s.day end
            while #sd > H.MAX_SCAN_DAYS do table.remove(sd, 1) end
            model:Ingest({ at = s.at, complete = true, items = s.items })
            last = s
            for _, id in ipairs(cal.items) do
                local want = model.items[id] and View(model.items[id]) or nil
                local got = hist[id] and Flat(hist[id], H) or nil
                if got ~= want then t:Same(got, want, ("seed %d item %d after scan %d (day %d)"):format(seed, id, n, s.day)) end
            end
        end
        -- the answers, through a market table handed in (the boundary Market.* accepts for data that is not saved)
        local items = {}
        for id, p in pairs(last.items) do items[id] = EntryOf(p) end
        local market = { key = cal.key, scope = "full", realm = "Synthetic", side = "Alliance", at = last.at, complete = true, partial = 0, items = items,
            hist = hist, scanDays = sd }
        for _, now in ipairs({ last.day * DAY + 900, (last.day + 3) * DAY }) do
            local opt = { market = market, now = now }
            for _, id in ipairs(cal.items) do
                local tag = ("seed %d item %d now day %d"):format(seed, id, math.floor(now / DAY))
                for _, period in ipairs({ "week", 28, "retained" }) do
                    local got, want = MK.Stats(id, period, opt), model:Stats(id, period, now)
                    t:Same(got ~= nil, want ~= nil, tag .. " Stats(" .. tostring(period) .. ") answers")
                    if got and want then
                        t:Same(table.concat({ got.n, got.low, got.high, got.average, tostring(got.exact) }, ","),
                            table.concat({ want.n, want.low, want.high, want.average, tostring(want.exact) }, ","), tag .. " Stats(" .. tostring(period) .. ")")
                    end
                end
                local tr, wtr = MK.Trend(id, 28, opt), model:Trend(id, 28, now)
                t:Same(tr ~= nil, wtr ~= nil, tag .. " Trend answers")
                if tr and wtr then t:Same(tr.percent, wtr.tenths / 10, tag .. " Trend percent") end
                local cmp, wcmp = MK.Compare(id, "week", opt), model:Compare(id, "week", now)
                t:Same(cmp ~= nil, wcmp ~= nil, tag .. " Compare answers")
                if cmp and wcmp then t:Same(cmp.reference, wcmp.reference, tag .. " Compare reference") end
            end
        end
        t:Yield()
    end
end)

---------------------------------------------------------------------------
-- The two Trend rules the first mutation probe found untested (hand arithmetic)
---------------------------------------------------------------------------
Pure("market.trend.window-and-percent", function(t)
    local MK = t.W.Market
    local function Trend(str, days, nowDay)
        return MK.Trend(10, days, { market = { key = "Synthetic|x", scope = "full", items = {}, at = 200 * DAY, hist = { [10] = str } }, now = nowDay * DAY + 900 })
    end
    -- the last 7 days counted back from day 200 are 194..200: the first day is in, day 193 is out
    local tr = Trend("193,100;194,110;200,120|", 7, 200)
    t:Check(tr ~= nil, "days 194 and 200 are two days of the last seven")
    if tr then t:Same(tr.fromDay, 194, "the window starts on day 194"); t:Same(tr.from, 110, "day 193 is outside it") end
    t:Same(select(2, Trend("193,100;200,120|", 7, 200)), "insufficient", "day 193 is the eighth day back: one day is no trend")
    -- percent of the first price to one decimal, ties away from zero, the same for falls as for rises
    for _, k in ipairs({ { 1000, 900, -10 }, { 1000, 1100, 10 }, { 300, 200, -33.3 }, { 7, 6, -14.3 }, { 7, 8, 14.3 }, { 3, 1, -66.7 }, { 2000, 1999, -0.1 },
        { 2000, 2001, 0.1 }, { 99999999999, 1, -100 } }) do
        local r = Trend(("150,%.0f;200,%.0f|"):format(k[1], k[2]), 60, 200)
        t:Same(r and r.percent, k[3], ("%.0f -> %.0f"):format(k[1], k[2]))
    end
    -- a fall of d from a is exactly the negative of a rise of d
    local rng = FX.Rng(7400000)
    for i = 1, 40 do
        local a = rng:Pick({ rng:Int(2, 50), rng:Int(2, 5000), rng:Int(2, 900000) })
        local d = rng:Int(1, a - 1)
        local down, up = Trend(("150,%d;200,%d|"):format(a, a - d), 60, 200), Trend(("150,%d;200,%d|"):format(a, a + d), 60, 200)
        t:Same(down.percent, -up.percent, ("mirror: %d from %d (seed 7400000, draw %d)"):format(d, a, i))
    end
end)

---------------------------------------------------------------------------
-- The price distribution (A3): Recent Price, quartiles, the saved text, the stepped build
---------------------------------------------------------------------------
-- Pure data in, production functions with explicit inputs (Prices.NewBatch / ItemsJob, Dist.*), nothing saved, nothing read from the player's
-- market. Seeds: 7700001..7700012. The expected Recent Prices below are the document's (docs/workshop/market-data-foundation-v2.md, 5.2); the
-- reference model (REF.ExpectDist) lines every item up and reads ranks, a second derivation that shares no code with Dist.lua.

local function Listing(u, q) return { item = 1, count = q, buyout = u * q, info = true } end
local function DistOf(PR, records)
    local b = PR.NewBatch()
    for _, r in ipairs(records) do b:Add(r.item, r.count, r.buyout, r.info) end
    local items, _, _, _, dist = b:Items()
    return items, dist
end
local function RefOf(records)
    local ref = {}
    for _, r in ipairs(records) do ref[#ref + 1] = { b = r.buyout, c = r.count } end
    return REF.ExpectDist(ref)
end

-- a representative Recent Price: the cases whose answer depends on a boundary
Pure("market.dist.recent", function(t)
    local PR, D = t.W.Prices, t.W.Dist
    if not (D and REF and REF.ExpectDist) then t:Skip("the distribution or its reference model is not loaded") end
    local cases = {
        { "1 healthy spread", { { 9500, 5 }, { 9800, 5 }, { 10000, 10 }, { 10200, 10 }, { 10500, 10 }, { 11000, 5 } }, 9741 },
        { "3 thin, one cheap unit (the strict 25% boundary)", { { 1000, 1 }, { 5000, 3 } }, 5000 },
        { "5b few cheap under a wall", { { 4500, 5 }, { 6000, 200 } }, 5878 },
        { "11 bait volume 29%", { { 2000, 8 }, { 5000, 20 } }, 2143 },
        { "12 bait volume 20%", { { 2000, 5 }, { 5000, 20 } }, 5000 },
        { "17 large expensive wall", { { 5000, 20 }, { 9000, 1000 } }, 8739 },
        { "18 manipulator just over half", { { 2510, 12 }, { 5000, 38 } }, 3008 },
        { "20 manipulator just under half", { { 2490, 12 }, { 5000, 38 } }, 5000 },
    }
    for _, c in ipairs(cases) do
        local records = {}
        for _, x in ipairs(c[2]) do records[#records + 1] = Listing(x[1], x[2]) end
        local _, dist = DistOf(PR, records)
        local d = dist and dist[1] and D.Decode(dist[1])
        t:Check(d ~= nil, c[1] .. ": the entry reads")
        if d then
            t:Same(d.r, c[3], c[1] .. ": Recent Price")
            t:Same(dist[1], RefOf(records).text, c[1] .. ": the saved text equals the reference model's")
        end
    end
    local _, one = DistOf(PR, { Listing(300000, 1) })
    t:Same(one[1], nil, "one price: no distribution entry")
end)

-- quartiles, anchor, supply near the price, tiers and tail: seeded houses against the reference model
Pure("market.dist.quartiles", function(t)
    local PR, D = t.W.Prices, t.W.Dist
    if not (D and FX and REF and REF.ExpectDist) then t:Skip("the distribution or its reference model is not loaded") end
    for i = 1, 12 do
        local seed = 7700000 + i
        local gen = FX.Listings(seed, { items = 2, records = 24 + i, tiers = 2 + i % 7, invalid = 0.1, noBuyout = 0.1 })
        local b = PR.NewBatch()
        for _, r in ipairs(gen.records) do b:Add(r.item, r.count, r.buyout, r.info) end
        local items, _, _, _, dist = b:Items()
        local priced = {}
        for _, r in ipairs(gen.records) do
            if r.intent == "priced" then priced[r.item] = priced[r.item] or {}; table.insert(priced[r.item], { b = r.buyout, c = r.count }) end
        end
        for item, list in pairs(priced) do
            local e = REF.ExpectDist(list)
            local tag = ("seed %d item %d"):format(seed, item)
            if e.distinct < 2 then
                t:Same(dist[item], nil, tag .. ": one price tier, no entry")
            else
                t:Same(dist[item], e.text, tag .. ": the saved text")
                local d = dist[item] and D.Decode(dist[item])
                if d then
                    t:Check(d.min <= d.q25 and d.q25 <= d.a and d.a <= d.q50 and d.q50 <= d.q75 and d.q75 <= d.hi and d.min <= d.r and d.r <= d.q50, tag .. ": ordering of the statistics")
                    local q, l = d.tq, d.tl
                    for _, tr in ipairs(d.tiers) do q, l = q + tr.q, l + tr.l end
                    t:Check(q == e.t and l == e.l, tag .. ": tiers and tail hold every item and listing")
                end
            end
        end
        t:Yield()
    end
end)

-- numbers: malformed records do not reach the tiers, the numeric limits, and a text that is not exactly what the writer makes
Pure("market.dist.numbers", function(t)
    local PR, D = t.W.Prices, t.W.Dist
    if not (D and FX and FX.BAD) then t:Skip("the distribution or the fixtures are not loaded") end
    local clean = { Listing(100, 5), Listing(150, 2), Listing(200, 1), Listing(400, 3) }
    local _, want = DistOf(PR, clean)
    local noisy = {}
    for _, r in ipairs(clean) do noisy[#noisy + 1] = r end
    for _, field in ipairs({ "item", "count", "buyout" }) do
        for _, bad in ipairs(FX.BAD[field]) do
            local r = { item = 1, count = 5, buyout = 600, info = true }
            r[field] = bad
            noisy[#noisy + 1] = r
        end
    end
    local items2, dist2 = DistOf(PR, noisy)
    t:Same(dist2[1], want[1], "malformed records (a NaN, an infinity, fractions, strings, limits) leave the distribution as it was")
    for id in pairs(items2) do t:Check(id == 1, "no item invented by a malformed record") end

    -- limits: the dearest allowed price and the largest quantities, exact (expected values worked out in exact fractions, not by this code)
    local function Stats(tiers)
        local ps, qs, ls = {}, {}, {}
        for i, x in ipairs(tiers) do ps[i], qs[i], ls[i] = x[1], x[2], 1 end
        return D.Stats(ps, qs, ls, #tiers)
    end
    t:Same((Stats({ { 99999999990, 3 }, { 99999999995, 5 }, { 99999999999, 2 } })), 99999999990, "Recent Price near the copper limit")
    t:Same((Stats({ { 99999999000, 600000000 }, { 99999999999, 1900000000 } })), 99999999200, "a mean of 99999999199.8")
    t:Same((Stats({ { 1, 2500000000 }, { 2, 100 }, { 99999999999, 1 } })), 1, "2.5 billion items at one copper")
    local r, _, _, _, _, _, _, _, _, exact = Stats({ { 50000000000, 600000000 }, { 99999999999, 1900000000 } })
    t:Check(not exact and math.abs(r - 60000000000) <= 1 and t.W.Finite(r), "beyond 2^53 the result is flagged inexact and within a copper")

    -- the reader refuses what the writer never makes
    local good = want[1]
    t:Check(D.Decode(good) ~= nil, "the good entry reads")
    for name, text in pairs({
        ["a NaN"] = (good:gsub("^1,%d+", "1,nan")), ["an infinity"] = (good:gsub("^1,%d+", "1,inf")), ["an exponent"] = (good:gsub("^1,%d+", "1,1e3")),
        ["a negative"] = (good:gsub("^1,%d+", "1,-5")), ["a leading zero"] = (good:gsub("^1,", "1,0")), ["a fraction"] = (good:gsub("^1,%d+", "1,10.5")),
        ["another algorithm"] = (good:gsub("^1,", "2,")), ["copper over the limit"] = (good:gsub("^1,%d+", "1,100000000000")),
    }) do
        t:Check(D.Decode(text) == nil, name .. " is refused")
    end
    t:Check(D.Decode(nil) == nil and D.Decode(12) == nil and D.Decode("") == nil, "a missing, numeric or empty value is refused")
end)

-- the stepped build and the saved text: bounded work per step, the same entries at any step size, every entry reads back
Pure("market.dist.finalize", function(t)
    local PR, D = t.W.Prices, t.W.Dist
    if not (D and FX and FX.Bulk) then t:Skip("the distribution or the fixtures are not loaded") end
    local bulk = FX.Bulk(7700101, 1500, 150, 400)
    while not bulk:Done() do bulk:Fill(500) t:Yield() end
    local batch = PR.NewBatch()
    for i = 1, bulk.n do batch:Add(bulk.item[i], bulk.count[i], bulk.buyout[i], true) end
    local whole = { batch:Items() }
    t:Check(whole[5] ~= nil, "a distribution was built")
    local sizes = { PR.ITEMS_STEP, 25, 3 }
    for _, limit in ipairs(sizes) do
        local job = batch:ItemsJob()
        local steps, worst = 0, 0
        repeat
            local done = job:Step(limit)
            steps = steps + 1
            if job.stepTiers > worst then worst = job.stepTiers end
            t:Yield()
        until done or steps > 100000
        t:Check(worst <= limit * (PR.TIERS_STEP / PR.ITEMS_STEP) + job.widest, ("step %d: no step summarised more tiers than its budget plus one item (%d)"):format(limit, worst))
        local items, _, _, _, dist = job:Result()
        local same = true
        for id, e in pairs(whole[1]) do if items[id] ~= e then same = false end end
        for id, e in pairs(whole[5]) do if dist[id] ~= e then same = false end end
        t:Check(same, ("step %d: the same entries and distributions as one pass (%d steps)"):format(limit, steps))
    end
    -- every entry reads, holds the items and listings the fixture counted, and starts at the item's price
    local bad, n = 0, 0
    for id, text in pairs(whole[5]) do
        n = n + 1
        local d = D.Decode(text)
        local tr = bulk.truth
        if not d or d.t ~= tr.t[id] or d.l ~= tr.l[id] or d.min ~= tonumber(whole[1][id]:match("^(%d+),")) then bad = bad + 1 end
        if n % 20 == 0 then t:Yield() end
    end
    t:Same(bad, 0, ("%d distribution entries read back and conserve items, listings and the minimum"):format(n))
    t:Note(("%d items, %d with a distribution"):format(whole[2], n))
end)

---------------------------------------------------------------------------
-- (A4) Version-2 history: History2's ring, daily points and buckets against the independent model (Reference.lua section 5), byte for
-- byte, on a few seeded calendars; and the brief's three-scan day by hand. Pure: History2.Update/Retain on strings held by the case only.
-- Seeds 7650001..7650004. The offline suite runs hundreds (tests/test_workshop_history2.lua).
---------------------------------------------------------------------------
local function H2Calendar(rng, nItems)
    local scans, day, state = {}, 20000 + rng:Int(0, 6), {}
    for id = 1, nItems do state[id] = { p = rng:Int(10, 5000), t = rng:Int(1, 40), l = rng:Int(1, 6), live = rng:Chance(0.7) } end
    for _ = 1, rng:Int(20, 60) do
        day = day + rng:Pick({ 0, 1, 1, 2, 6, 25, 70 })
        local minute = rng:Int(0, 200)
        for _ = 1, rng:Pick({ 1, 2, 3 }) do
            minute = minute + rng:Pick({ 1, 60, 240 })
            if minute >= 1440 then break end
            local sc = { at = day * DAY + minute * 60, whole = not rng:Chance(0.1), partial = rng:Chance(0.15) and 1 or 0, items = {} }
            for id, s in pairs(state) do
                if rng:Chance(0.12) then s.live = not s.live end
                if s.live then
                    if rng:Chance(0.4) then s.p = math.max(1, s.p + rng:Int(-50, 50)) end
                    if rng:Chance(0.4) then s.t = math.max(1, s.t + rng:Int(-5, 5)) end
                    local r = s.p + rng:Pick({ 0, 3, 200 })
                    if rng:Chance(0.15) then r = nil end
                    sc.items[id] = { p = s.p, r = r, t = s.t, l = s.l }
                end
            end
            scans[#scans + 1] = sc
        end
    end
    return scans
end

Pure("market.history2.model", function(t)
    local H2 = t.W.History2
    local compared = 0
    for seed = 7650001, 7650004 do
        local rng = FX.Rng(seed)
        local nItems = rng:Int(2, 5)
        local model = REF.H2New()
        local h2, c2, lastAt = {}, {}, nil
        for _, sc in ipairs(H2Calendar(rng, nItems)) do
            if REF.H2Scan(model, sc) then
                local ctx = { T = math.floor(sc.at / DAY), M = math.floor(sc.at / 60), prevM = lastAt and math.floor(lastAt / 60) or nil }
                for id = 1, nItems do
                    local o = sc.items[id]
                    if o then
                        local obs = H2.Obs(sc.at, o.p, o.r, o.t, o.l, sc.partial > 0)
                        h2[id], c2[id] = H2.Update(h2[id], c2[id], obs, ctx)
                    elseif h2[id] or c2[id] then
                        h2[id], c2[id] = H2.Retain(h2[id], c2[id], ctx)
                    end
                end
                lastAt = sc.at
                for id = 1, nItems do
                    local eh, ec = REF.H2Text(REF.H2Expect(model, id))
                    if eh ~= h2[id] or ec ~= c2[id] then
                        t:Check(false, ("seed %d item %d at %d: h2 %s, the model says %s"):format(seed, id, sc.at, tostring(h2[id]), tostring(eh)))
                        return
                    end
                    compared = compared + 1
                end
                t:Yield()
            end
        end
    end
    t:Check(compared > 50, "item states compared: " .. compared)
    t:Note(("%d item states equal to the model, byte for byte (4 seeds)"):format(compared))
end)

Pure("market.history2.day", function(t)
    local H2 = t.W.History2
    local D0 = 20000
    local function Ctx(at, prev) return { T = math.floor(at / DAY), M = math.floor(at / 60), prevM = prev and math.floor(prev / 60) or nil } end
    local a1, a2, a3 = D0 * DAY + 8 * 3600, D0 * DAY + 14 * 3600, D0 * DAY + 20 * 3600
    local h = H2.Update(nil, nil, H2.Obs(a1, 900, 1000, 100, 10), Ctx(a1))
    h = H2.Update(h, nil, H2.Obs(a2, 500, 600, 70, 8), Ctx(a2, a1))
    h = H2.Update(h, nil, H2.Obs(a3, 1000, 1100, 120, 12), Ctx(a3, a2))
    local m0 = math.floor(a1 / 60)
    -- worked by hand: closing 1000 / 1100 / 120 / 12, three scans; lows 500 (min), 600 (Recent), 70 (items); nothing above the close
    t:Same(h, ("%.0f,0,900,100,100,10;360,0,500,100,70,8;360,0,1000,100,120,12|%.0f:%.0f,1000,100,120,12,3,500,0,500,0,50,0"):format(m0, D0, D0), "the brief's day")
    -- missing Recent Price: an empty field, never 0
    local x = H2.Update(nil, nil, H2.Obs(a1, 700, nil, 4, 2), Ctx(a1))
    t:Same(x, ("%.0f,0,700,,4,2|%.0f:%.0f,700,,4,2"):format(m0, D0, D0), "unknown Recent Price")
    t:Same(H2.DecodeH2("|20000:20000,5,0,1,1,2,0,0,0,0,0,0"), nil, "a non-canonical spelling is refused")
end)
