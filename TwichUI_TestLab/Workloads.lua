-- TwichUI Test Lab: the benchmark workloads (TL.Workloads). Milestone M7. ONE definition for every interpreter: tests/bench_workshop.lua runs
-- these offline, cases/Perf.lua runs them in the game, tests/test_testlab_bench.lua runs the cheap ones under a scripted clock.
--
-- A workload is  { id, v, fixture, seed, size, unit, work, offline (true: too large for the game's time budget), setup, begin, signature,
--   verify, fingerprint }  (see Bench.lua). It calls PRODUCTION functions (Prices.NewBatch, History.Add/Trim, Market.*, Materials.Rows,
--   Shopping.Plan) on made-up data from Fixtures.lua with explicit inputs, never through the saved markets. setup builds the input and is not
--   timed; begin starts one repetition and returns step() (true when finished) and finish() (the output). A step is a bounded unit: a batch of
--   400 records, 500 history updates, 1,000 lookups, one crafting scenario. verify checks the output against what the FIXTURE knows or a
--   second derivation (the reference model, a replay of the observations), NOT against the code under test, and may yield (ctx.yield).
--
-- Bumping a workload's v (or its seed or size) makes older baselines incomparable on purpose: change the work, change the number.
-- Nothing here creates a frame, a timer or an event, reads the game, or writes a saved variable.

local R = TwichUI
local TL = R.TestLab or {}
R.TestLab = TL
local WL = { list = {}, byId = {} }
TL.Workloads = WL

local floor, max, min = math.floor, math.max, math.min
local DAY = 86400

local function Add(def)
    def.v = def.v or 1
    WL.list[#WL.list + 1] = def
    WL.byId[def.id] = def
    return def
end

local function Ctx(ctx)
    ctx = ctx or {}
    return ctx.W, TL.Fixtures, TL.Reference
end

-- A function to call between pieces of Lab-owned work: it yields once about 4 ms have passed since the last yield (M7.1: a long unyielded
-- fingerprint or check is a frame hitch the Lab itself caused, and the report would blame the workload for it)
local function Budget(ctx)
    local clock = ctx and ctx.clock
    local t0 = clock and clock()
    return function()
        if clock and ctx.yield and clock() - t0 >= 0.004 then
            ctx.yield()
            t0 = clock()
        end
    end
end

-- yields every `every` items of a loop that has no other yield: a verification must not hold a frame
local function Pace(ctx, i, every)
    if not (ctx and ctx.yield) then return end
    if ctx.clock then
        -- by time when the harness gives a clock (M7.1): about 4 ms of Lab-owned work per frame whatever one item costs
        if i % 4 ~= 0 then return end
        local now = ctx.clock()
        if not ctx.paceAt then ctx.paceAt = now return end
        if now - ctx.paceAt >= 0.004 then
            ctx.yield()
            ctx.paceAt = ctx.clock()
        end
    elseif i % every == 0 then
        ctx.yield()
    end
end

---------------------------------------------------------------------------
-- 1. The auction batch (Prices.NewBatch / Add / Items)
---------------------------------------------------------------------------
-- seed 7600001; records 1,000 / 10,000 / 50,000 (and 250,000, the scan's own boundary, offline only); distinct items 300 / 3,000 / 12,000 / 30,000
-- VERSION 3 (A3): the entries are built together with the price distribution (Prices.lua, Dist.lua), so the work per item, the memory and the
-- longest step include the per-item tier sort and summary. v2 figures are the minimum-only aggregation and are not comparable by Compare.
-- Variants (same seed, other price spreads, ids with a tag): "wide" (up to 4,001 prices per item: many tiers), "narrow" (2 prices: concentrated),
-- "deep" (60 items with thousands of tiers each: the longest per-item sort).
local BATCH_STEP = 400   -- the step is the size the scan itself reads at a time

local function Aggregate(size, items, offline, spread, tag)
    local name = size >= 1000 and (floor(size / 1000) .. "k") or tostring(size)
    return Add({
        id = "market.aggregate." .. (tag and (tag .. ".") or "") .. name, fixture = "bulk.listings", seed = 7600001, size = size, unit = "records",
        work = size, offline = offline, v = 3,
        setup = function(ctx)
            local W, FX = Ctx(ctx)
            local b = FX.Bulk(7600001, size, items, spread)
            while not b:Done() do b:Fill(1000) ctx.yield() end
            return { W = W, bulk = b, work = b.n }
        end,
        fingerprint = function(st)
            local b, sum = st.bulk, 0
            for i = 1, b.n, 97 do sum = (sum * 31 + b.item[i] + b.count[i] + b.buyout[i]) % 2147483629 end
            return ("%d:%d:%d"):format(b.n, #b.item, sum)
        end,
        begin = function(st)
            local b = st.bulk
            local batch = st.W.Prices.NewBatch()
            local at, entries, n, dist, job = 0, nil, nil, nil, nil
            local item, count, buyout = b.item, b.count, b.buyout
            local PR = st.W.Prices
            -- the scan's own sequence (Scan.lua): records BATCH_STEP at a time, then the entries and distributions PR.ITEMS_STEP items (at most
            -- PR.TIERS_STEP tiers) at a time. v1 called Items() in one step; v2 built the minimum entries only
            return function()
                if at < b.n then
                    local last = min(b.n, at + BATCH_STEP)
                    for i = at + 1, last do batch:Add(item[i], count[i], buyout[i], true) end
                    at = last
                    return false
                end
                job = job or batch:ItemsJob()
                if not job:Step(PR.ITEMS_STEP) then return false end
                local _, _, _, _, d
                entries, n, _, _, d = job:Result()
                dist = d
                return true
            end, function() return { batch = batch, entries = entries, n = n, dist = dist } end
        end,
        signature = function(out)
            local b = out.batch
            local nd = 0
            if out.dist then for _ in pairs(out.dist) do nd = nd + 1 end end
            return ("%d/%d/%d/%d/%d/%d"):format(b.read, b.used, b.noBuyout, b.invalid, out.n, nd)
        end,
        verify = function(st, out, ctx)
            local b, tr = out.batch, st.bulk.truth
            if b.read ~= tr.read or b.used ~= tr.used or b.noBuyout ~= tr.noBuyout or b.invalid ~= tr.invalid then
                return false, ("counts read/used/bid-only/invalid are %d/%d/%d/%d, the fixture made %d/%d/%d/%d"):format(
                    b.read, b.used, b.noBuyout, b.invalid, tr.read, tr.used, tr.noBuyout, tr.invalid)
            end
            local distinct = 0
            for _ in pairs(tr.l) do distinct = distinct + 1 end
            if out.n ~= distinct then return false, ("%d items priced, the fixture listed %d"):format(out.n, distinct) end
            if not out.dist then return false, "no distribution was built" end
            local i = 0
            for id, e in pairs(out.entries) do
                i = i + 1
                Pace(ctx, i, 500)
                local p, _, l, t = e:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$")
                p, l, t = tonumber(p), tonumber(l), tonumber(t)
                local m = tr.m[id]
                if not (p and m) then return false, "item " .. tostring(id) .. " is not one the fixture listed" end
                if l ~= tr.l[id] or t ~= tr.t[id] then return false, ("item %d: %s listings and %s items, the fixture made %d and %d"):format(id, tostring(l), tostring(t), tr.l[id], tr.t[id]) end
                if p < m - 1e-6 or p >= m + 1 then return false, ("item %d: cheapest unit %.0f, the fixture's cheapest is %.3f"):format(id, p, m) end
            end
            -- the distribution: an entry only for an item with 2 or more listings; each one reads, starts at the item's price, holds exactly the
            -- items and listings the fixture counted, and is ordered (minimum <= quartiles <= highest, minimum <= Recent Price <= median)
            local Dist = st.W.Dist
            i = 0
            for id, text in pairs(out.dist) do
                i = i + 1
                Pace(ctx, i, 500)
                local d = Dist.Decode(text)
                if not d then return false, "item " .. tostring(id) .. ": the distribution does not read" end
                if tr.l[id] == nil or tr.l[id] < 2 then return false, ("item %d has %s listings and a distribution"):format(id, tostring(tr.l[id])) end
                if d.t ~= tr.t[id] or d.l ~= tr.l[id] then return false, ("item %d: distribution holds %d items in %d listings, the fixture made %d in %d"):format(id, d.t, d.l, tr.t[id], tr.l[id]) end
                local p = tonumber(out.entries[id]:match("^(%d+),"))
                if d.min ~= p then return false, ("item %d: distribution starts at %d, the minimum entry says %d"):format(id, d.min, p) end
            end
            -- the small tier is also compared with the independent reference models, record by record
            local W, FX, REF = Ctx(ctx)
            if REF and st.bulk.n <= 2000 then
                local records, listings = {}, {}
                for k = 1, st.bulk.n do
                    records[k] = { item = st.bulk.item[k], count = st.bulk.count[k], buyout = st.bulk.buyout[k], info = true }
                    local c, bo = st.bulk.count[k], st.bulk.buyout[k]
                    if c >= 1 and bo >= 1 then
                        local list = listings[st.bulk.item[k]]
                        if not list then list = {} listings[st.bulk.item[k]] = list end
                        list[#list + 1] = { b = bo, c = c }
                    end
                end
                local exp = REF.ExpectBatch(records)
                if exp.used ~= b.used or exp.n ~= out.n then return false, "the reference model counts differently" end
                for id, e in pairs(exp.items) do
                    if out.entries[id] ~= REF.EntryText(e) then return false, "item " .. id .. " differs from the reference model" end
                    local x = REF.ExpectDist(listings[id])
                    if out.dist[id] ~= x.text then return false, ("item %d: distribution %s, the reference model says %s"):format(id, tostring(out.dist[id]), tostring(x.text)) end
                end
            end
            return true
        end,
    })
end
Aggregate(1000, 300)
Aggregate(10000, 3000)
Aggregate(50000, 12000)
Aggregate(10000, 300, false, 4000, "wide")
Aggregate(10000, 3000, false, 1, "narrow")
Aggregate(250000, 30000, true)
Aggregate(50000, 1500, true, 4000, "wide")
Aggregate(250000, 30000, true, 4000, "wide")
Aggregate(250000, 60, true, 20000, "deep")

---------------------------------------------------------------------------
-- 2. History: replaying observations (insert, fold, retention) and the queries
---------------------------------------------------------------------------
-- 200 items, scans over N days (seed 7610001 mixed, 7611001 dense). The observations are flattened into parallel arrays outside the timed section.
local HIST_STEP = 500

local function CalendarOps(seed, scans, dense, ctx)
    local FX = TL.Fixtures
    local cal = FX.Calendar(seed, { scans = scans, items = 200, style = dense and "dense" or "mixed", start = 20000,
        listed = dense and 1 or nil, same = dense and 0 or nil, back = dense and 0 or nil, cut = dense and 0 or nil,
        tick = function(i) Pace(ctx, i, 1) end })
    local ops = { item = {}, day = {}, price = {}, n = 0, ids = cal.items, top = 0 }
    for si, sc in ipairs(cal.scans) do
        Pace(ctx, si, 1)
        if sc.complete and not sc.cut and not sc.changed then   -- a cut scan adds no history (Prices.lua)
            for _, id in ipairs(cal.items) do
                local p = sc.items[id]
                if p then
                    local k = ops.n + 1
                    ops.n = k
                    ops.item[k], ops.day[k], ops.price[k] = id, sc.day, p
                    if sc.day > ops.top then ops.top = sc.day end
                end
            end
        end
    end
    return ops
end

-- what the observations say, kept by a replay that knows nothing of strings or buckets: per item the observed days, oldest first, the same
-- day replaced, a day before the newest ignored
local function Replay(ops, upto, ctx)
    local days = {}
    for k = 1, upto do
        Pace(ctx, k, 500)
        local id, day, p = ops.item[k], ops.day[k], ops.price[k]
        local list = days[id]
        if not list then list = {} days[id] = list end
        local last = list[#list]
        if not last or day > last[1] then list[#list + 1] = { day, p }
        elseif day == last[1] then last[2] = p end
    end
    return days
end

-- the exact days a history string must hold: the newest seven observed days, none older than 120 days before the newest
local function ExpectedRecent(list)
    if not list or #list == 0 then return {} end
    local newest = list[#list][1]
    local out = {}
    for i = max(1, #list - 6), #list do
        if list[i][1] >= newest - 120 then out[#out + 1] = list[i] end
    end
    return out
end

local function CheckRecent(W, strings, days, ids, ctx)
    local H = W.History
    for n, id in ipairs(ids) do
        Pace(ctx, n, 40)
        local want = ExpectedRecent(days[id])
        local pts, bks = H.Decode(strings[id])
        if #want == 0 then
            if strings[id] ~= nil then return false, "item " .. id .. " has a history, no observation was made" end
        else
            if not pts then return false, "item " .. id .. " has no history" end
            if #pts ~= #want * 2 then return false, ("item %d holds %d exact days, expected %d"):format(id, #pts / 2, #want) end
            for i, d in ipairs(want) do
                if pts[2 * i - 1] ~= d[1] or pts[2 * i] ~= d[2] then return false, ("item %d day %d: %s,%s expected %.0f,%.0f"):format(id, i, tostring(pts[2 * i - 1]), tostring(pts[2 * i]), d[1], d[2]) end
            end
            if #bks > H.MAX_BUCKETS * 5 then return false, "item " .. id .. " keeps more buckets than the limit" end
        end
    end
    return true
end

local function HistorySignature(out)
    local len, n = 0, 0
    for _, s in pairs(out.strings) do len = len + #s n = n + 1 end
    return ("%d/%d/%d/%d"):format(out.ops, out.stale, n, len)
end

local function Insert(scans, name)
    return Add({
        id = "history.insert." .. name, fixture = "calendar.mixed", seed = 7610001, size = scans, unit = "updates",
        setup = function(ctx)
            local W = Ctx(ctx)
            local ops = CalendarOps(7610001, scans, false, ctx)
            return { W = W, ops = ops, work = ops.n }
        end,
        fingerprint = function(st) local o = st.ops return ("%d:%d:%d"):format(o.n, o.top, #o.ids) end,
        begin = function(st)
            local H, ops = st.W.History, st.ops
            local strings, stale, at = {}, 0, 0
            return function()
                local last = min(ops.n, at + HIST_STEP)
                for k = at + 1, last do
                    local id = ops.item[k]
                    local s = H.Add(strings[id], ops.day[k], ops.price[k])
                    if s then strings[id] = s else stale = stale + 1 end
                end
                at = last
                return at >= ops.n
            end, function() return { strings = strings, stale = stale, ops = ops.n } end
        end,
        signature = HistorySignature,
        verify = function(st, out, ctx)
            return CheckRecent(st.W, out.strings, Replay(st.ops, st.ops.n, ctx), st.ops.ids, ctx)
        end,
    })
end
Insert(30, "30d")
Insert(120, "120d")
Insert(400, "400d")

-- Folding: every update lands on a history whose seven exact days are full, so each one folds the oldest into a 28-day bucket
Add({
    id = "history.fold.dense", fixture = "calendar.dense", seed = 7611001, size = 90, unit = "updates",
    setup = function(ctx)
        local W = Ctx(ctx)
        local ops = CalendarOps(7611001, 90, true, ctx)
        local prefix = 0
        for k = 1, ops.n do if ops.day[k] <= ops.day[1] + 29 then prefix = k end end   -- the first 30 scan days are laid down before timing
        local base = {}
        for k = 1, prefix do
            local id = ops.item[k]
            base[id] = W.History.Add(base[id], ops.day[k], ops.price[k])
            Pace(ctx, k, 500)
        end
        return { W = W, ops = ops, prefix = prefix, base = base, work = ops.n - prefix }
    end,
    fingerprint = function(st) local o = st.ops return ("%d:%d:%d"):format(o.n, o.top, st.prefix) end,
    begin = function(st)
        local H, ops = st.W.History, st.ops
        local strings = {}
        for id, s in pairs(st.base) do strings[id] = s end
        local stale, at = 0, st.prefix
        return function()
            local last = min(ops.n, at + HIST_STEP)
            for k = at + 1, last do
                local id = ops.item[k]
                local s = H.Add(strings[id], ops.day[k], ops.price[k])
                if s then strings[id] = s else stale = stale + 1 end
            end
            at = last
            return at >= ops.n
        end, function() return { strings = strings, stale = stale, ops = ops.n - st.prefix } end
    end,
    signature = HistorySignature,
    verify = function(st, out, ctx)
        local ok, why = CheckRecent(st.W, out.strings, Replay(st.ops, st.ops.n, ctx), st.ops.ids, ctx)
        if not ok then return ok, why end
        local buckets = 0
        for _, s in pairs(out.strings) do
            local _, bks = st.W.History.Decode(s)
            buckets = buckets + #bks / 5
        end
        if buckets == 0 then return false, "nothing was folded into a bucket" end
        return true
    end,
})

-- Retention: H.Trim at several later dates over histories built from 400 days of observations
Add({
    id = "history.trim.400d", fixture = "calendar.mixed", seed = 7610001, size = 400, unit = "trims",
    setup = function(ctx)
        local W = Ctx(ctx)
        local ops = CalendarOps(7610001, 400, false, ctx)
        local strings, ids = {}, {}
        for k = 1, ops.n do
            local id = ops.item[k]
            local s = W.History.Add(strings[id], ops.day[k], ops.price[k])
            if s then strings[id] = s end
            Pace(ctx, k, 500)
        end
        for _, id in ipairs(ops.ids) do if strings[id] then ids[#ids + 1] = id end end
        local offsets = { 0, 30, 90, 150, 250, 500 }
        return { W = W, ops = ops, strings = strings, ids = ids, offsets = offsets, work = #ids * #offsets }
    end,
    fingerprint = function(st) return TL.Bench.Ser(st.strings) end,
    begin = function(st)
        local H = st.W.History
        local total, at = #st.ids * #st.offsets, 0
        local kept = {}
        for i = 1, #st.offsets do kept[i] = 0 end
        local len = 0
        return function()
            local last = min(total, at + 300)
            for k = at + 1, last do
                local oi = floor((k - 1) / #st.ids) + 1
                local id = st.ids[(k - 1) % #st.ids + 1]
                local s = H.Trim(st.strings[id], st.ops.top + st.offsets[oi])
                if s then kept[oi] = kept[oi] + 1 len = len + #s end
            end
            at = last
            return at >= total
        end, function() return { kept = kept, len = len } end
    end,
    signature = function(out) return table.concat(out.kept, ",") .. "/" .. out.len end,
    verify = function(st, out)
        -- later dates keep no more than earlier ones; far enough ahead nothing is left; at the newest day every item with a recent observation is kept
        for i = 2, #out.kept do
            if out.kept[i] > out.kept[i - 1] then return false, "a later date kept more histories than an earlier one" end
        end
        if out.kept[#out.kept] ~= 0 then return false, "histories survive 500 days past the newest scan" end
        local days = Replay(st.ops, st.ops.n, ctx)
        local recent = 0
        for _, id in ipairs(st.ids) do
            local list = days[id]
            if list and list[#list][1] >= st.ops.top - 120 then recent = recent + 1 end
        end
        if out.kept[1] < recent then return false, ("%d histories kept at the newest day, at least %d have an observation within 120 days"):format(out.kept[1], recent) end
        return true
    end,
})

---------------------------------------------------------------------------
-- 3. Statistics, trend, comparison, series (Market.Stats / Trend / Compare / Series / Observed) on a market with history
---------------------------------------------------------------------------
local QUERY_STEP = 250

local function HistoryMarket(W, ops, strings, ctx)
    local items, n = {}, 0
    local days = Replay(ops, ops.n, ctx)
    for id, list in pairs(days) do items[id] = ("%.0f,1,1,1,0"):format(list[#list][2]) n = n + 1 end
    -- items with a single observed day: a sparse history
    local sparse = {}
    for k = 1, 40 do
        local id = 900000 + k
        strings[id] = ("%d,%d|"):format(ops.top, 100 + k * 13)
        items[id] = ("%d,1,1,1,0"):format(100 + k * 13)
        sparse[k] = id
        n = n + 1
    end
    local scanDays, seen = {}, {}
    for k = 1, ops.n do
        local d = ops.day[k]
        if not seen[d] then seen[d] = true scanDays[#scanDays + 1] = d end
    end
    table.sort(scanDays)
    while #scanDays > W.History.MAX_SCAN_DAYS do table.remove(scanDays, 1) end
    return { key = "Bench|Alliance", realm = "Bench", side = "Alliance", scope = "full", complete = true, cut = false, partial = 0,
        at = ops.top * DAY + 3600, n = n, items = items, hist = strings, scanDays = scanDays }, days, sparse
end

Add({
    id = "market.stats.6k", fixture = "calendar.mixed+sparse", seed = 7610001, size = 400, unit = "queries", work = 6000,
    setup = function(ctx)
        local W = Ctx(ctx)
        local ops = CalendarOps(7610001, 400, false, ctx)
        local strings = {}
        for k = 1, ops.n do
            local id = ops.item[k]
            local s = W.History.Add(strings[id], ops.day[k], ops.price[k])
            if s then strings[id] = s end
            Pace(ctx, k, 500)
        end
        local m, days, sparse = HistoryMarket(W, ops, strings, ctx)
        local ids = {}
        for _, id in ipairs(ops.ids) do if strings[id] then ids[#ids + 1] = id end end
        for _, id in ipairs(sparse) do ids[#ids + 1] = id end
        return { W = W, ops = ops, market = m, days = days, ids = ids, opt = { market = m, now = ops.top * DAY + 3600 }, work = 6000 }
    end,
    fingerprint = function(st) return TL.Bench.Ser(st.market.hist) .. TL.Bench.Ser(st.market.items) end,
    begin = function(st)
        local MK, ids, opt, today = st.W.Market, st.ids, st.opt, st.ops.top
        local at, got, chk = 0, { 0, 0, 0, 0, 0, 0, 0 }, 0
        return function()
            local last = min(6000, at + QUERY_STEP)
            for i = at + 1, last do
                local id = ids[1 + (i * 7919) % #ids]
                local kind = i % 7
                local r
                if kind == 0 then r = MK.Stats(id, "week", opt)
                elseif kind == 1 then r = MK.Stats(id, 30, opt)
                elseif kind == 2 then r = MK.Stats(id, "retained", opt)
                elseif kind == 3 then r = MK.Trend(id, 7, opt)
                elseif kind == 4 then r = MK.Compare(id, "week", opt)
                elseif kind == 5 then r = MK.Series(id, opt)
                else r = MK.Observed(id, today - 1, opt) end
                if r then
                    got[kind + 1] = got[kind + 1] + 1
                    chk = (chk * 31 + (r.n or 0) + (r.low or 0) + (r.high or 0) + (r.average or 0) + (r.change or 0) + (r.reference or 0) + #(r.points or {})) % 2147483629
                end
            end
            at = last
            return at >= 6000
        end, function() return { got = got, chk = chk } end
    end,
    signature = function(out) return table.concat(out.got, ",") .. "/" .. out.chk end,
    verify = function(st, out, ctx)
        -- the week's statistics of every item with history, against the replay of the observations
        local MK, today = st.W.Market, st.ops.top
        for n, id in ipairs(st.ids) do
            Pace(ctx, n, 20)
            local list = st.days[id]
            local cnt, sum, lo, hi = 0, 0, nil, nil
            if list then
                for _, d in ipairs(list) do
                    if d[1] >= today - 6 and d[1] <= today then
                        cnt, sum = cnt + 1, sum + d[2]
                        if not lo or d[2] < lo then lo = d[2] end
                        if not hi or d[2] > hi then hi = d[2] end
                    end
                end
            else
                cnt, sum, lo, hi = 1, 100 + (id - 900000) * 13, 100 + (id - 900000) * 13, 100 + (id - 900000) * 13
            end
            local s = MK.Stats(id, "week", st.opt)
            if cnt == 0 then
                if s then return false, "item " .. id .. " has statistics but no observation this week" end
            else
                if not s then return false, "item " .. id .. " has no statistics, " .. cnt .. " days were observed this week" end
                local avg = floor(sum / cnt + 0.5)
                if s.n ~= cnt or s.low ~= lo or s.high ~= hi or s.average ~= avg then
                    return false, ("item %d week: n %s low %s high %s avg %s, expected %.0f %.0f %.0f %.0f"):format(id, tostring(s.n), tostring(s.low), tostring(s.high), tostring(s.average), cnt, lo, hi, avg)
                end
            end
        end
        return true
    end,
})

---------------------------------------------------------------------------
-- 4. Price lookups (Market.Price) over several markets and every kind of answer
---------------------------------------------------------------------------
-- A: full, fresh, 3,000 items.  B: the same items, 3 days old.  C: a scan of recipe items only (a third of them).  N: no market.
-- The mix is fixed: 8 kinds in turn, so the expected answers are known from the construction alone.
local LOOKUPS, LOOK_STEP, KINDS, NITEMS = 24000, 1000, 8, 3000
local function ItemOf(k) return 2000 + 3 * k end
local function PriceOf(k) return 50 + (k * 37) % 9000 end

Add({
    id = "market.lookup.24k", fixture = "market.synthetic", seed = 0, size = NITEMS, unit = "lookups", work = LOOKUPS,
    setup = function(ctx)
        local W = Ctx(ctx)
        local function Make(scope, at, member)
            local items, n = {}, 0
            for k = 1, NITEMS do
                if member(k) then
                    items[ItemOf(k)] = ("%d,%d,%d,%d,0"):format(PriceOf(k), 1 + k % 3, 1 + k % 5, 4 + k % 9)
                    n = n + 1
                end
            end
            return { key = "Bench|" .. scope .. at, realm = "Bench", side = "Alliance", scope = scope, complete = scope == "full", cut = false, partial = 0, at = at, n = n, items = items }
        end
        local now = 20000 * DAY
        local mk = { A = Make("full", now - 600, function() return true end), B = Make("full", now - 3 * DAY, function() return true end),
            C = Make("recipes", now - 600, function(k) return k % 3 == 0 end), N = {} }
        -- the answers the construction implies (not asked of the Workshop)
        local want = { hits = 0, unlisted = 0, outofscope = 0, nomarket = 0, baditem = 0, variant = 0, sum = 0 }
        for i = 1, LOOKUPS do
            local k = 1 + (i * 7919) % NITEMS
            local kind = (i - 1) % KINDS + 1
            if kind == 1 or kind == 3 then want.hits, want.sum = want.hits + 1, want.sum + PriceOf(k)
            elseif kind == 2 then want.unlisted = want.unlisted + 1
            elseif kind == 4 then
                if k % 3 == 0 then want.hits, want.sum = want.hits + 1, want.sum + PriceOf(k) else want.outofscope = want.outofscope + 1 end
            elseif kind == 5 then want.nomarket = want.nomarket + 1
            elseif kind == 6 then want.baditem = want.baditem + 1
            elseif kind == 7 then want.variant = want.variant + 1
            else want.hits, want.sum = want.hits + 1, want.sum + PriceOf(k) end   -- kind 8: item in A again, a different path through the table
            Pace(ctx, i, 4000)
        end
        return { W = W, mk = mk, now = now, want = want, work = LOOKUPS }
    end,
    fingerprint = function(st) local a = st.mk.A return ("%d:%d:%d"):format(a.n, st.mk.B.n, st.mk.C.n) end,
    begin = function(st)
        local MK, mk, now = st.W.Market, st.mk, st.now
        local optA, optB, optC, optN = { market = mk.A, now = now }, { market = mk.B, now = now }, { market = mk.C, now = now }, { market = mk.N, now = now }
        local optV = { market = mk.A, now = now, variant = true }
        local at, got = 0, { hits = 0, unlisted = 0, outofscope = 0, nomarket = 0, baditem = 0, variant = 0, sum = 0 }
        return function()
            local last = min(LOOKUPS, at + LOOK_STEP)
            for i = at + 1, last do
                local k = 1 + (i * 7919) % NITEMS
                local kind = (i - 1) % KINDS + 1
                local p, why
                if kind == 1 or kind == 8 then p, why = MK.Price(ItemOf(k), optA)
                elseif kind == 2 then p, why = MK.Price(ItemOf(k) + 1, optA)
                elseif kind == 3 then p, why = MK.Price(ItemOf(k), optB)
                elseif kind == 4 then p, why = MK.Price(ItemOf(k), optC)
                elseif kind == 5 then p, why = MK.Price(ItemOf(k), optN)
                elseif kind == 6 then p, why = MK.Price(0, optA)
                else p, why = MK.Price(ItemOf(k), optV) end
                if p then got.hits, got.sum = got.hits + 1, got.sum + p.price
                else got[why] = (got[why] or 0) + 1 end
            end
            at = last
            return at >= LOOKUPS
        end, function() return got end
    end,
    signature = function(g) return ("%d/%d/%d/%d/%d/%d/%d"):format(g.hits, g.unlisted, g.outofscope, g.nomarket, g.baditem, g.variant, g.sum) end,
    verify = function(st, g)
        local w = st.want
        for _, k in ipairs({ "hits", "unlisted", "outofscope", "nomarket", "baditem", "variant", "sum" }) do
            if g[k] ~= w[k] then return false, ("%s: %s, the construction implies %s"):format(k, tostring(g[k]), tostring(w[k])) end
        end
        return true
    end,
})

---------------------------------------------------------------------------
-- 5. Crafting: combined materials, stock allocation, the shopping plan (Materials.Rows, Shopping.Plan), current implemented planner only
---------------------------------------------------------------------------
-- Each step is ONE scenario (FX.Crafting with opt.bulk): its queue's rows (bags, bank and guild bank applied) and its one-level plan.
-- Partial stock, unknown bag counts, unknown source prices, vendors, repeated materials and Make options all occur, as the generator draws them.
local CRAFT_FIELDS = { "item", "need", "made", "madeRange", "have", "short", "bank", "guild", "fromBank", "fromGuild" }
local function RowsText(rows)
    local out = {}
    for _, r in ipairs(rows) do
        local one = {}
        for _, f in ipairs(CRAFT_FIELDS) do one[#one + 1] = tostring(r[f]) end
        out[#out + 1] = table.concat(one, " ")
    end
    return table.concat(out, "\n")
end
local function PlanTotals(t) return ("%s/%s/%s/%s/%s/%s"):format(tostring(t.cash), tostring(t.priced), tostring(t.missing), tostring(t.estimate), tostring(t.incomplete), tostring(t.makes)) end

local function Crafting(name, count, entries, pool, guild)
    return Add({
        id = "crafting.plan." .. name, fixture = "crafting.bulk", seed = 7620001, size = entries, unit = "scenarios", work = count, v = 1,
        setup = function(ctx)
            local W, FX = Ctx(ctx)
            local scns = {}
            for i = 1, count do
                local scn = FX.Crafting(7620000 + i, { bulk = true, entries = entries, items = pool })
                if not guild then scn.guild = {} end
                scns[i] = scn
                ctx.yield()
            end
            return { W = W, FX = FX, scns = scns, work = count }
        end,
        fingerprint = function(st, ctx)
            local parts, between = {}, Budget(ctx)
            for i, scn in ipairs(st.scns) do parts[i] = TL.Bench.Ser(scn) between() end   -- the planner must not change the scenarios it is given
            return table.concat(parts, "|")
        end,
        begin = function(st)
            local W, FX, scns = st.W, st.FX, st.scns
            local at, results, chk = 0, {}, 0
            return function()
                at = at + 1
                local scn = scns[at]
                local rows, sum = W.Materials.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))
                local plan = W.Shopping.Plan(FX.PlanInput(scn, rows))
                results[at] = { rows = rows, plan = plan }
                chk = (chk * 31 + #rows + #plan.rows + (plan.totals.cash or 0) % 1000003) % 2147483629
                return at >= #scns
            end, function() return { results = results, chk = chk } end
        end,
        signature = function(out)
            local cash = {}
            for i, r in ipairs(out.results) do cash[i] = PlanTotals(r.plan.totals) end
            return out.chk .. "/" .. table.concat(cash, ";")
        end,
        verify = function(st, out, ctx)
            local W, FX, REF = Ctx(ctx)
            -- rows and totals agree with the reference model (the input being untouched is the fingerprint's check)
            if not REF then return true end
            local priced, infeasible = 0, 0
            for i, scn in ipairs(st.scns) do
                local r = out.results[i]
                local mrows = REF.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))
                if RowsText(r.rows) ~= RowsText(mrows) then return false, "scenario " .. i .. ": the rows differ from the reference model" end
                local ref = REF.Plan(scn, r.rows, REF.AssignmentOf(r.plan, r.rows))
                if ref.feasible then
                    local a = PlanTotals(r.plan.totals)
                    local b = PlanTotals({ cash = ref.cash, priced = ref.priced, missing = ref.missing, estimate = ref.estimate, incomplete = ref.incomplete, makes = ref.makes })
                    if a ~= b then return false, ("scenario %d: plan totals %s, the reference model %s"):format(i, a, b) end
                    priced = priced + 1
                else
                    infeasible = infeasible + 1
                end
                ctx.yield()
            end
            if priced == 0 then return false, "no scenario could be compared with the reference model" end
            return true
        end,
    })
end
Crafting("small", 200, 3, 8, true)
Crafting("medium", 80, 10, 24, true)
Crafting("large", 30, 30, 64, true)
Crafting("large-noguild", 30, 30, 64, false)

---------------------------------------------------------------------------
-- 6. What is deliberately NOT here
---------------------------------------------------------------------------
-- Workshop page redraws (overview, opportunities, crafting, shopping lists) and open/close cycles: they read the player's real queue and saved
-- markets and build real frames, so a benchmark of them would either touch player data or time a stand-in. They are deferred (docs/testlab.md,
-- "Benchmarks"); real play is measured by R.Perf scopes and TwichUI_Diagnostics captures.
WL.DEFERRED = { "Workshop page redraw (overview, opportunities, crafting queue, shopping list)", "open/close and navigation cycles of the Workshop window" }

-- the workloads that run in the game (the others are offline only)
function WL.InGame()
    local out = {}
    for _, w in ipairs(WL.list) do if not w.offline then out[#out + 1] = w end end
    return out
end
