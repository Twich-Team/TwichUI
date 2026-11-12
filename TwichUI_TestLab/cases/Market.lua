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
