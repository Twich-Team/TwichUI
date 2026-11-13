-- TwichUI Test Lab: independent REFERENCE MODELS of the Workshop's market arithmetic (TL.Reference). PURE: plain tables and whole-number
-- arithmetic, no game calls, no saved variables, no clock, and no call into TwichUI_Workshop. They exist so a test can compare what the
-- production code answers with an answer reached a different way. A model that borrowed the production algorithm's structure would agree
-- with its mistakes, so each one below is built from the DOCUMENTED CONTRACT (the header comments of Prices.lua, History.lua, Market.lua)
-- and from simpler data:
--
--  1. AUCTION BATCH (REF.ExpectBatch). Production compares unit prices by cross-multiplying (buyout1 * count2 against buyout2 * count1)
--     and keeps one running record per item. The model keeps EVERY valid listing of an item and compares two prices as MIXED NUMBERS: the
--     whole part first (buyout // count), then the remainders (r1 * count2 against r2 * count1, each below 10^8). Both are exact; neither
--     uses division or floating point, so the model does not depend on 53-bit products or on rounding. A unit price is then rounded UP to
--     whole copper (at least 1) by the same integer division. The model states what production's "next price" x means (xModel) and what a
--     literal reading of "the next higher price listed" would be (xStrict); they differ in one documented corner (see REF.ExpectBatch).
--  1b. PRICE DISTRIBUTION (REF.ExpectDist, A3). Production walks a running total over sorted price tiers; the model lines up every item
--     one by one and reads quartiles, the anchor, the Recent Price band and the near-price supply off ranks (see the section's comment).
--  2. HISTORY (REF.NewMarket / Item). Production keeps, per item, a compact string: seven exact days and up to three 28-day buckets that
--     hold only low, high, sum and count. The model keeps EVERY observed day in a plain map (`truth`, never compacted) and the same
--     two tiers as SETS of days (`exact`, `coarse`); a bucket's low, high, sum and count are computed from its days when asked. So what
--     compaction may and may not lose is visible: the exact tier must equal the truth day for day; a bucket must be made of truth days.
--  3. STATISTICS. Stats, Trend, Compare, Observed and Series are computed from the model's sets with whole-number arithmetic: means are
--     rounded half up by integer division, a percentage change is rounded half away from zero to one decimal by integer division
--     (no floating point), so ties and signs are exact.
--
-- THE DOCUMENTED RULES the model encodes (History.lua): one value per calendar day (a later observation the same day replaces it); an
-- observation dated before the newest day kept is ignored; the SEVENTH-plus day folds the oldest exact day into its 28-day bucket
-- (day // 28); nothing older than 120 days before the day of the operation is kept (an exact day by its own date, a bucket when its whole
-- span is older); at most three buckets; the order inside one operation is: add, fold, expire.

local R = TwichUI
local TL = R.TestLab or {}
R.TestLab = TL
local REF = {}
TL.Reference = REF

-- the documented constants, typed here on purpose: a test checks they equal History's, so changing one is a conscious step
REF.DAY, REF.POINTS, REF.BUCKET, REF.MAX_BUCKETS, REF.RETAIN, REF.MAX_SCAN_DAYS = 86400, 7, 28, 3, 120, 32
local MAX_COPPER, MAX_COUNT, MAX_ID, MAX_DAY = 99999999999, 10000, 2147483647, 200000
local floor = math.floor

-- Is v a finite number? Decided WITHOUT comparing v with anything: a finite number prints as digits, a point, an exponent and signs only; a
-- NaN or an infinity prints with letters (nan, inf, and the client's own spellings). OBSERVED (Test Lab run, client 1.60.1 build 70888,
-- 2026-11-12, seeds 7100008 and 7100012): the plain test `v == v and v >= lo and v <= hi and v % 1 == 0` ACCEPTED a NaN count in the
-- client (desktop Lua 5.1 rejects it at `v == v`), so a model that decides NaN by comparison disagrees with itself between interpreters.
-- Comparisons below run only on numbers this has shown to be finite.
local function Finite(v)
    if type(v) ~= "number" then return false end
    local s = tostring(v)
    return s ~= "" and s:find("^[%d%.eE%+%-]+$") ~= nil
end
REF.Finite = Finite

local function Whole(v, lo, hi) return Finite(v) and v >= lo and v <= hi and v % 1 == 0 end
REF.Whole = Whole

-- v is exactly zero (a bid-only buyout). Never true for a NaN, whatever the interpreter says NaN == 0 is.
local function Zero(v) return Finite(v) and v == 0 end

-- What this interpreter answers for a number, as one short line: the primitives the model could depend on, then what Whole decides.
-- For the Test Lab's divergence report; a pure function of v, lo and hi.
function REF.NumberProbe(v, lo, hi)
    if type(v) ~= "number" then return "type " .. type(v) end
    local function B(x) return x and "T" or "F" end
    local ok, mod = pcall(function() return v % 1 end)
    local okF, fl = pcall(math.floor, v)
    return ("tostring=%s eq_self=%s ne_self=%s lt_lo=%s gt_hi=%s le_hi=%s ge_lo=%s eq_0=%s mod1=%s floor=%s floor_eq=%s | finite=%s whole=%s"):format(
        tostring(v), B(v == v), B(v ~= v), B(v < lo), B(v > hi), B(v <= hi), B(v >= lo), B(v == 0), ok and tostring(mod) or "raised",
        okF and tostring(fl) or "raised", B(okF and fl == v), B(Finite(v)), B(Whole(v, lo, hi)))
end

-- whole-number division with a remainder (a >= 0, b >= 1)
local function DivMod(a, b)
    local r = a % b
    return (a - r) / b, r
end
REF.DivMod = DivMod

-- ceil(a / b) as a unit price: whole copper, at least 1
local function CeilCopper(a, b)
    local q, r = DivMod(a, b)
    if r > 0 then q = q + 1 end
    return math.max(q, 1)
end

-- -1, 0 or 1: is a1/b1 below, equal to or above a2/b2? Compared as mixed numbers: the whole parts, then the remainders.
local function CompareFractions(a1, b1, a2, b2)
    local q1, r1 = DivMod(a1, b1)
    local q2, r2 = DivMod(a2, b2)
    if q1 ~= q2 then return q1 < q2 and -1 or 1 end
    local x, y = r1 * b2, r2 * b1
    if x == y then return 0 end
    return x < y and -1 or 1
end
REF.CompareFractions = CompareFractions

-- round(num / den) with ties going up, for whole num >= 0 and den >= 1
local function RoundHalfUp(num, den)
    return (DivMod(2 * num + den, 2 * den))
end
REF.RoundHalfUp = RoundHalfUp

-- The change from a to b as a percentage of a, to ONE decimal, as a whole number of TENTHS of a percent, ties rounded AWAY from zero:
-- 1000 -> 900 is -100 (-10.0 %), 2000 -> 1999 is the tie -0.05 % and rounds to -1 (-0.1 %), exactly as 2000 -> 2001 rounds to +1.
function REF.PercentTenths(a, b)
    local diff = b - a
    local tenths = RoundHalfUp(1000 * math.abs(diff), a)
    if tenths == 0 then return 0 end   -- a fall too small to show is 0, not negative zero
    return diff < 0 and -tenths or tenths
end

---------------------------------------------------------------------------
-- 1. The auction batch
---------------------------------------------------------------------------
-- records: { {item, count, buyout, info} ... } as FX.Listings makes them. The model's reading of a record (Prices.lua, "an auction without a
-- buyout (bid only) is ignored; so is anything that is not a whole number in range"):
--   invalid   the item is not a whole number 1..2147483647, or the count is not 1..10000, or the buyout is missing or not a whole number
--             0..99999999999. A record malformed in item or count is invalid even when its buyout is 0 (malformed first).
--             A NaN or an infinity is never a whole number (decided by REF.Finite, not by comparing it).
--   nobuyout  a valid item and count with a buyout of 0 (bid only)
--   priced    everything else
--   partial   a record with a valid item whose `info` is exactly false (the game had not loaded all of its information)
-- Returns { items = { [id] = {p,q,l,t,x, xStrict} }, read, used, noBuyout, invalid, partial, n }:
--   p  the cheapest unit price, rounded up to whole copper     q  items listed at EXACTLY that price (the exact fraction)
--   l  priced listings     t  items in them
--   x  the next higher price per production's meaning (xModel): the least unit price ABOVE the cheapest one, rounded up, or 0 when that
--      rounds to the same copper as p or when there is none
--   xStrict  the least ROUNDED unit price that is above p among all listings, or 0 (the literal reading). x and xStrict differ only when
--      the next higher exact price rounds to p's copper but a dearer listing exists: production then saves 0 ("could not be told").
function REF.ExpectBatch(records)
    local out = { items = {}, read = 0, used = 0, noBuyout = 0, invalid = 0, partial = 0, n = 0 }
    local listings = {}
    for _, r in ipairs(records) do
        out.read = out.read + 1
        if not Whole(r.item, 1, MAX_ID) then
            out.invalid = out.invalid + 1
        else
            if r.info == false then out.partial = out.partial + 1 end
            if not Whole(r.count, 1, MAX_COUNT) then
                out.invalid = out.invalid + 1
            elseif Zero(r.buyout) then
                out.noBuyout = out.noBuyout + 1
            elseif not Whole(r.buyout, 1, MAX_COPPER) then
                out.invalid = out.invalid + 1
            else
                out.used = out.used + 1
                local list = listings[r.item]
                if not list then list = {} listings[r.item] = list end
                list[#list + 1] = { b = r.buyout, c = r.count }
            end
        end
    end
    for item, list in pairs(listings) do
        local cheapest = list[1]
        for _, l in ipairs(list) do
            if CompareFractions(l.b, l.c, cheapest.b, cheapest.c) < 0 then cheapest = l end
        end
        local p = CeilCopper(cheapest.b, cheapest.c)
        local q, t, nextAbove = 0, 0, nil
        local strict = 0
        for _, l in ipairs(list) do
            t = t + l.c
            local rel = CompareFractions(l.b, l.c, cheapest.b, cheapest.c)
            if rel == 0 then q = q + l.c
            elseif not nextAbove or CompareFractions(l.b, l.c, nextAbove.b, nextAbove.c) < 0 then nextAbove = l end
            local rounded = CeilCopper(l.b, l.c)
            if rounded > p and (strict == 0 or rounded < strict) then strict = rounded end
        end
        local x = 0
        if nextAbove then
            local rounded = CeilCopper(nextAbove.b, nextAbove.c)
            if rounded > p then x = rounded end
        end
        out.items[item] = { p = p, q = q, l = #list, t = t, x = x, xStrict = strict }
        out.n = out.n + 1
    end
    return out
end

-- The text production saves for an item: "p,q,l,t,x"
function REF.EntryText(e) return ("%.0f,%.0f,%.0f,%.0f,%.0f"):format(e.p, e.q, e.l, e.t, e.x) end   -- %.0f, not %d: the client's %d refuses numbers beyond 32 bits (copper reaches 99999999999)

-- Which items a market keeps when more than `limit` were found: the priority items first, then the most listings, then the lowest item
-- number. Picked one at a time (not sorted). Returns { [id] = true }, how many were dropped.
function REF.Keep(items, limit, priority)
    priority = priority or {}
    local left, n = {}, 0
    for id in pairs(items) do left[id] = true n = n + 1 end
    local kept, count = {}, 0
    local function Better(a, b)
        local pa, pb = priority[a] and 1 or 0, priority[b] and 1 or 0
        if pa ~= pb then return pa > pb end
        if items[a].l ~= items[b].l then return items[a].l > items[b].l end
        return a < b
    end
    while count < limit and next(left) do
        local best
        for id in pairs(left) do if best == nil or Better(id, best) then best = id end end
        left[best] = nil
        kept[best] = true
        count = count + 1
    end
    return kept, n - count
end

---------------------------------------------------------------------------
-- 1b. The price distribution of one item (A3)
---------------------------------------------------------------------------
-- Production keeps TIERS (a distinct unit price with its items and listings), adds up a running total and walks it. The model never forms a
-- tier to compute with: it lines up EVERY ITEM of every priced listing by unit price (a stack of 5 is five entries, so the list is as long as
-- the items listed: keep the scenarios small) and reads each answer off a RANK in that list:
--   q25 q50 q75  the entry at rank ceil(T/4), ceil(T/2), ceil(3T/4)                       (nearest rank)
--   a            the entry at rank floor(T/4) + 1: the first rank STRICTLY above a quarter of the items
--   r            keep the entries priced at least half of a; E of them are left; the band is the cheapest 3E/10 entries: the first floor(3E/10)
--                whole ones and (3E mod 10)/10 of the next, so the sum in tenths of an entry is 10 x (their prices) + (3E mod 10) x (the next price)
--                and the mean is that over 3E, rounded half up (whole numbers only, no fractions, no floating point)
--   near         the entries priced at most 1.10 x r, counted one by one (price x 10 <= r x 11)
-- The tiers of the saved text, its tail and the text itself are then written from the model's own grouping. `records` are { b, c } valid
-- priced listings (the buyout of the whole stack and its count) of ONE item.
function REF.ExpectDist(records)
    local entries, byUnit, order = {}, {}, {}
    local listings = 0
    for _, rec in ipairs(records) do
        local u = CeilCopper(rec.b, rec.c)
        listings = listings + 1
        for _ = 1, rec.c do entries[#entries + 1] = u end
        local g = byUnit[u]
        if not g then g = { p = u, q = 0, l = 0, m = 0 } byUnit[u] = g order[#order + 1] = g end
        g.q, g.l = g.q + rec.c, g.l + 1
        if rec.c > g.m then g.m = rec.c end
    end
    table.sort(entries)
    table.sort(order, function(x, y) return x.p < y.p end)
    local T = #entries
    local e = { t = T, l = listings, min = entries[1], hi = entries[T], tiers = {}, tq = 0, tl = 0 }
    local function Rank(num, den) return entries[(DivMod(T * num + den - 1, den))] end
    e.q25, e.q50, e.q75 = Rank(1, 4), Rank(1, 2), Rank(3, 4)
    e.a = entries[(DivMod(T, 4)) + 1]
    local eligible = {}
    for _, x in ipairs(entries) do if 2 * x >= e.a then eligible[#eligible + 1] = x end end
    local E = #eligible
    local whole, tenths = DivMod(3 * E, 10)
    local sum = 0
    for i = 1, whole do sum = sum + 10 * eligible[i] end
    if tenths > 0 then sum = sum + tenths * eligible[whole + 1] end
    e.r = RoundHalfUp(sum, 3 * E)
    e.near = 0
    for _, x in ipairs(entries) do if x * 10 <= e.r * 11 then e.near = e.near + 1 end end
    for i, g in ipairs(order) do
        if i <= 6 then e.tiers[i] = g else e.tq, e.tl = e.tq + g.q, e.tl + g.l end
    end
    e.distinct = #order
    if #order >= 2 then
        local function N(v) return ("%.0f"):format(v) end
        local segs = {}
        for i, g in ipairs(e.tiers) do
            segs[i] = N(g.p) .. ":" .. N(g.q) .. ":" .. N(g.l) .. (g.l > 1 and (":" .. N(g.m)) or "")
        end
        e.text = ("1,%s,%s,%s,%s,%s,%s,%s|%s"):format(N(e.r), N(e.a), N(e.q25), N(e.q50), N(e.q75), N(e.hi), N(e.near), table.concat(segs, ";"))
        if e.tq > 0 then e.text = e.text .. "|" .. N(e.tq) .. ":" .. N(e.tl) end
    end
    return e
end

---------------------------------------------------------------------------
-- 2. The history of one item
---------------------------------------------------------------------------
local Item = {}
Item.__index = Item

local function NewItem() return setmetatable({ truth = {}, exact = {}, coarse = {} }, Item) end

local function Count(set) local n = 0 for _ in pairs(set) do n = n + 1 end return n end

local function BucketOf(day) return floor(day / REF.BUCKET) end

-- the newest / oldest day of a set of days, or nil
local function Extreme(set, newest)
    local best
    for d in pairs(set) do if best == nil or (newest and d > best) or (not newest and d < best) then best = d end end
    return best
end

function Item:Newest()
    local a, b = Extreme(self.exact, true), Extreme(self.coarse, true)
    if a and b then return math.max(a, b) end
    return a or b
end

function Item:Alive() return next(self.exact) ~= nil or next(self.coarse) ~= nil end

-- nothing older than RETAIN days before `today` is kept: an exact day by its own date, a bucket when its whole span is older; then only
-- the newest MAX_BUCKETS buckets stay
function Item:Expire(today)
    local cutoff = today - REF.RETAIN
    for d in pairs(self.exact) do if d < cutoff then self.exact[d] = nil end end
    for d in pairs(self.coarse) do
        if (BucketOf(d) + 1) * REF.BUCKET - 1 < cutoff then self.coarse[d] = nil end
    end
    local buckets = {}
    for d in pairs(self.coarse) do buckets[BucketOf(d)] = true end
    local list = {}
    for b in pairs(buckets) do list[#list + 1] = b end
    table.sort(list)
    for i = 1, #list - REF.MAX_BUCKETS do
        for d in pairs(self.coarse) do if BucketOf(d) == list[i] then self.coarse[d] = nil end end
    end
end

-- One observation: the cheapest listing of the item on `day`. Returns true, or false and why ("bad", "stale").
function Item:Observe(day, price)
    if not Whole(day, 1, MAX_DAY) or not Whole(price, 1, MAX_COPPER) then return false, "bad" end
    local newest = self:Newest()
    if newest and day < newest then return false, "stale" end
    self.truth[day] = price
    self.exact[day] = price
    while Count(self.exact) > REF.POINTS do
        local oldest = Extreme(self.exact, false)
        self.coarse[oldest] = self.exact[oldest]
        self.exact[oldest] = nil
    end
    self:Expire(day)
    return true
end

-- A scan on `today` that did not list the item (or whose observation was refused): only expiry happens. Returns false when nothing is left.
function Item:Quiet(today)
    self:Expire(today)
    return self:Alive()
end

-- the exact days, oldest first: { {day, price} ... }
function Item:Points()
    local days = {}
    for d in pairs(self.exact) do days[#days + 1] = d end
    table.sort(days)
    local out = {}
    for i, d in ipairs(days) do out[i] = { day = d, price = self.exact[d] } end
    return out
end

-- the buckets, oldest first: { {b, lo, hi, sum, n} ... }, made of the coarse days
function Item:Buckets()
    local by = {}
    for d, p in pairs(self.coarse) do
        local b = BucketOf(d)
        local k = by[b]
        if not k then k = { b = b, lo = p, hi = p, sum = 0, n = 0 } by[b] = k end
        if p < k.lo then k.lo = p end
        if p > k.hi then k.hi = p end
        k.sum, k.n = k.sum + p, k.n + 1
    end
    local out = {}
    for _, k in pairs(by) do out[#out + 1] = k end
    table.sort(out, function(a, b) return a.b < b.b end)
    return out
end

-- What the days from..to (both included) hold, from the exact days and from the buckets whose WHOLE 28-day span lies inside; observed days
-- inside buckets that overhang the window are not counted (`skipped` says how many days such buckets hold) unless the exact days reach back
-- to the start of the window, in which case nothing older matters.
function Item:Window(from, to)
    local r = { n = 0, sum = 0, exact = true, skipped = 0 }
    local oldestExact = Extreme(self.exact, false)
    for d, p in pairs(self.exact) do
        if d >= from and d <= to then
            r.n, r.sum = r.n + 1, r.sum + p
            if not r.lo or p < r.lo then r.lo = p end
            if not r.hi or p > r.hi then r.hi = p end
        end
    end
    for _, k in ipairs(self:Buckets()) do
        local first, last = k.b * REF.BUCKET, k.b * REF.BUCKET + REF.BUCKET - 1
        if last >= from and first <= to then
            if first >= from and last <= to then
                r.n, r.sum, r.exact = r.n + k.n, r.sum + k.sum, false
                if not r.lo or k.lo < r.lo then r.lo = k.lo end
                if not r.hi or k.hi > r.hi then r.hi = k.hi end
            elseif oldestExact == nil or from < oldestExact then
                r.skipped = r.skipped + k.n
            end
        end
    end
    if r.n == 0 then return nil end
    return r
end

-- the same window computed straight from the full history (`truth`): only meaningful where nothing was compacted away
function Item:TruthWindow(from, to)
    local r = { n = 0, sum = 0 }
    for d, p in pairs(self.truth) do
        if d >= from and d <= to then
            r.n, r.sum = r.n + 1, r.sum + p
            if not r.lo or p < r.lo then r.lo = p end
            if not r.hi or p > r.hi then r.hi = p end
        end
    end
    return r
end

---------------------------------------------------------------------------
-- 3. A market: scans in, answers out
---------------------------------------------------------------------------
local Market = {}
Market.__index = Market

function REF.NewMarket(key)
    return setmetatable({ key = key, items = {}, scanDays = {}, current = {}, complete = false, at = nil }, Market)
end

REF.Item = NewItem

-- scan = { at, complete, cut, changed, items = { [id] = unit price } }. Production's rules for keeping a scan:
--   * a scan that is not complete is refused ("kept") while the market's saved scan is complete;
--   * a cut scan, or one whose listing count kept changing, adds no history (but still replaces the current prices);
--   * every item the scan did not list (or whose observation was refused) is expired as of the scan's day;
--   * the scan's day joins the market's scan days when it is later than the last one (32 kept).
function Market:Ingest(scan)
    if self.complete and scan.complete ~= true then return false, "kept" end
    local day = Whole(scan.at, 1, 4102444800) and floor(scan.at / REF.DAY) or nil
    if day and (day < 1 or day > MAX_DAY) then day = nil end
    local feed = day ~= nil and not scan.cut and not scan.changed
    local touched = {}
    if feed then
        for id, price in pairs(scan.items) do
            local item = self.items[id] or NewItem()
            if item:Observe(day, price) then
                touched[id] = true
                self.items[id] = item
            end
        end
        local last = self.scanDays[#self.scanDays]
        if last ~= day and (last == nil or last < day) then self.scanDays[#self.scanDays + 1] = day end
        while #self.scanDays > REF.MAX_SCAN_DAYS do table.remove(self.scanDays, 1) end
    end
    if day then
        for id, item in pairs(self.items) do
            if not touched[id] and not item:Quiet(day) then self.items[id] = nil end
        end
    end
    self.at = scan.at
    self.complete = scan.complete == true and not scan.cut and not scan.changed
    self.current = {}
    for id, price in pairs(scan.items) do self.current[id] = price end
    return true
end

local function Today(now) return Whole(now, 1, 4102444800) and floor(now / REF.DAY) or nil end

-- "week" (default) = 7 days, "retained" = everything, or a whole number of days 1..120: returns the days (nil for retained) and true,
-- or nil and false when the period is not supported
local function PeriodDays(period)
    if period == nil or period == "week" then return 7, true end
    if period == "retained" then return nil, true end
    if Whole(period, 1, REF.RETAIN) then return period, true end
    return nil, false
end

-- Market.Stats: { n, scans, low, high, average, newest = {day, price}, exact, limited, single, from, to } or nil and a reason
function Market:Stats(item, period, now)
    local days, ok = PeriodDays(period)
    if not ok then return nil, "badperiod" end
    local it = self.items[item]
    if not it then return nil, "nodata" end
    local today = Today(now)
    if not today then return nil, "nodata" end
    local from = days and (today - days + 1) or 1
    local w = it:Window(from, today)
    if not w then return nil, "nodata" end
    local scans = 0
    for _, d in ipairs(self.scanDays) do if d >= from and d <= today then scans = scans + 1 end end
    local points = it:Points()
    local newest
    if #points > 0 then newest = { day = points[#points].day, price = points[#points].price }
    else
        -- only buckets are left: the newest day known is the last day of the newest bucket's span (no price)
        local buckets = it:Buckets()
        newest = { day = (buckets[#buckets].b + 1) * REF.BUCKET - 1 }
    end
    return { n = w.n, scans = scans, low = w.lo, high = w.hi, average = RoundHalfUp(w.sum, w.n), newest = newest, exact = w.exact,
        limited = w.skipped > 0, single = w.n == 1, from = from, to = today }
end

-- Market.Trend: the first and the last EXACT observed day of the last `days` days (default 7, at least 2)
--   { direction, from, to, change, tenths (percent x 10, a whole number), n, fromDay, toDay } or nil and a reason
function Market:Trend(item, days, now)
    local d = days
    if d == nil then d = 7 elseif not Whole(d, 2, REF.RETAIN) then return nil, "badperiod" end
    local it = self.items[item]
    if not it then return nil, "nodata" end
    local today = Today(now)
    local from = today - d + 1
    local first, last, n = nil, nil, 0
    for _, pt in ipairs(it:Points()) do
        if pt.day >= from then
            n = n + 1
            first = first or pt
            last = pt
        end
    end
    if n < 2 then return nil, "insufficient" end
    local a, b = first.price, last.price
    return { direction = b > a and "up" or (b < a and "down" or "flat"), from = a, to = b, change = b - a, tenths = REF.PercentTenths(a, b), n = n,
        fromDay = first.day, toDay = last.day }
end

-- Market.Compare: the current price against the mean of the observed days BEFORE the day of the current scan
--   { current, reference, relation, difference, n, exact, limited } or nil and a reason
function Market:Compare(item, period, now)
    local days, ok = PeriodDays(period)
    if not ok then return nil, "badperiod" end
    local price = self.current[item]
    if not price then return nil, "unlisted" end
    local it = self.items[item]
    if not it then return nil, "nodata" end
    local to = floor(self.at / REF.DAY) - 1
    local w = it:Window(days and (to - days + 1) or 1, to)
    if not w then return nil, "insufficient" end
    local ref = RoundHalfUp(w.sum, w.n)
    return { current = price, reference = ref, relation = price > ref and "above" or (price < ref and "below" or "same"), difference = price - ref,
        n = w.n, exact = w.exact, limited = w.skipped > 0 }
end

-- Market.Observed: { day, price } while the day is an exact day, else nil and "nodata" / "notobserved" / "notretained"
function Market:Observed(item, day)
    local it = self.items[item]
    if not it then return nil, "nodata" end
    if it.exact[day] then return { day = day, price = it.exact[day] } end
    local oldest = Extreme(it.exact, false)
    if oldest and day < oldest and next(it.coarse) then return nil, "notretained" end
    return nil, "notobserved"
end

-- Market.Series: { points = { {day, price} }, groups = { {from, to, low, high, average, n} } } or nil and "nodata"
function Market:Series(item)
    local it = self.items[item]
    if not it then return nil, "nodata" end
    local groups = {}
    for _, k in ipairs(it:Buckets()) do
        groups[#groups + 1] = { from = k.b * REF.BUCKET, to = k.b * REF.BUCKET + REF.BUCKET - 1, low = k.lo, high = k.hi,
            average = RoundHalfUp(k.sum, k.n), n = k.n }
    end
    return { points = it:Points(), groups = groups }
end

---------------------------------------------------------------------------
-- 4. Crafting (testing roadmap M3): allocation, combined materials, what storage may supply, shopping, the craft estimate, the list order
---------------------------------------------------------------------------
-- Built from the DOCUMENTED CONTRACT (the header comments of Materials.lua, Stock.lua, Shopping.lua, Prices.lua and Opportunities.lua), and
-- deliberately simpler than the production code:
--   * allocation takes items ONE AT A TIME from the next layer that still holds one (production uses min/subtraction);
--   * a crafting cycle is found by walking who-supplies-whom (production closes a matrix);
--   * a vendor purchase is found by counting stacks (production divides); money is whole copper, exact integer arithmetic only;
--   * the shopping plan is judged by ENUMERATING every sourcing choice (REF.Enumerate) instead of deciding one material at a time.
-- Where a rule is a pure transcription of the documented policy (the order of the three sources, the six reasons a recipe may not be made, the
-- tie rule) it is written down again here rather than imported, so changing it in production is a conscious step: a test compares.

local MAX_GRAPH, MAX_CRAFTS, MAX_CANDIDATES = 60, 999, 4
REF.MAX_GRAPH, REF.MAX_CRAFTS, REF.MAX_CANDIDATES = MAX_GRAPH, MAX_CRAFTS, MAX_CANDIDATES

-- nil, negative, NaN and infinity count as none (Finite first, no comparison of a malformed number: in the client a NaN compares as both less and
-- greater, and an infinite `want` would never end the loop in REF.Take)
local function Qty(v) return (Finite(v) and v > 0) and v or 0 end

-- A held bag count as production reads it (W.Count): a whole number from 0, or nil (unknown). Written again here, not imported.
local MAX_HELD = 2147483647
local function Held(v) if Whole(v, 0, MAX_HELD) then return v end return nil end
REF.Held = Held

-- Takes `want` items one at a time from the bags, then the bank, then the guild bank (whole numbers). Returns
-- { bags, bank, guild (taken from each), missing (what none holds), left = { bags, bank, guild left } }.
function REF.Take(want, bags, bank, guild)
    local left = { Qty(bags), Qty(bank), Qty(guild) }
    local took, missing = { 0, 0, 0 }, 0
    for _ = 1, Qty(want) do
        local placed = false
        for layer = 1, 3 do
            if left[layer] > 0 then
                left[layer], took[layer], placed = left[layer] - 1, took[layer] + 1, true
                break
            end
        end
        if not placed then missing = missing + 1 end
    end
    return { bags = took[1], bank = took[2], guild = took[3], missing = missing, left = left }
end

-- Materials.Combine: need per item (materials per craft x crafts, summed over the queue), the order the items were first seen, how many entries
-- have no usable materials, what the queued crafts make (the LEAST one craft makes, only of an item some entry needs, never for entries that
-- depend on each other), which of those are a range, and how many entries were left out for depending on each other.
function REF.Combine(entries)
    local need, order, unknown = {}, {}, 0
    for _, e in ipairs(entries) do
        if type(e.mats) == "table" and #e.mats > 0 then
            for _, m in ipairs(e.mats) do
                if need[m.item] == nil then need[m.item] = 0 order[#order + 1] = m.item end
                need[m.item] = need[m.item] + m.qty * e.crafts
            end
        else
            unknown = unknown + 1
        end
    end
    local function Uses(e, item)
        if type(e.mats) ~= "table" then return false end
        for _, m in ipairs(e.mats) do if m.item == item then return true end end
        return false
    end
    -- an entry is in a circle when following "this one makes what that one uses" leads back to it
    local function InCircle(i)
        local seen, todo = {}, { i }
        while #todo > 0 do
            local cur = table.remove(todo)
            local out = entries[cur].outItem
            if out ~= nil then
                for j, e in ipairs(entries) do
                    if Uses(e, out) then
                        if j == i then return true end
                        if not seen[j] then seen[j] = true todo[#todo + 1] = j end
                    end
                end
            end
        end
        return false
    end
    local made, range, cycle = {}, {}, 0
    if #entries <= MAX_GRAPH then
        for i, e in ipairs(entries) do
            if e.outItem and e.outMin and need[e.outItem] ~= nil and type(e.mats) == "table" then
                if InCircle(i) then
                    cycle = cycle + 1
                else
                    made[e.outItem] = (made[e.outItem] or 0) + e.outMin * e.crafts
                    if (e.outMax or e.outMin) ~= e.outMin then range[e.outItem] = true end
                end
            end
        end
    end
    return need, order, unknown, made, range, cycle
end

-- Materials.Rows: the rows (item, need, made, madeRange, have, short, bank, guild, fromBank, fromGuild) in the documented order (short items,
-- then unknown, then those to collect, then the rest; each by item number) and the summary. have(item), stock(item) as in production.
function REF.Rows(entries, have, stock)
    local need, order, unknown, made, range, cycle = REF.Combine(entries)
    local rows = {}
    local s = { entries = #entries, unknown = unknown, items = #order, shortItems = 0, unknownItems = 0, cycle = cycle, collectItems = 0, bankItems = 0, guildItems = 0 }
    for _, item in ipairs(order) do
        local h = Held(have(item))
        local row = { item = item, need = need[item], made = made[item], madeRange = made[item] and range[item] or nil, have = h }
        if h ~= nil then
            local bank, guild = 0, 0
            if stock then bank, guild = stock(item) end
            local t = REF.Take(math.max(0, need[item] - (made[item] or 0)), h, bank, guild)
            row.short, row.bank, row.guild, row.fromBank, row.fromGuild = t.missing, bank, guild, t.bank, t.guild
            if t.bank + t.guild > 0 then s.collectItems = s.collectItems + 1 end
            if t.bank > 0 then s.bankItems = s.bankItems + 1 end
            if t.guild > 0 then s.guildItems = s.guildItems + 1 end
        end
        if row.short == nil then s.unknownItems = s.unknownItems + 1 elseif row.short > 0 then s.shortItems = s.shortItems + 1 end
        rows[#rows + 1] = row
    end
    local function Group(r)
        if r.short == nil then return 2 end
        if r.short > 0 then return 1 end
        if (r.fromBank or 0) + (r.fromGuild or 0) > 0 then return 3 end
        return 4
    end
    -- insertion sort by (group, item)
    for i = 2, #rows do
        local r, j = rows[i], i - 1
        while j >= 1 and (Group(rows[j]) > Group(r) or (Group(rows[j]) == Group(r) and rows[j].item > r.item)) do
            rows[j + 1] = rows[j]
            j = j - 1
        end
        rows[j + 1] = r
    end
    if s.entries == 0 then s.state = "empty"
    elseif s.unknown > 0 or s.unknownItems > 0 or s.items == 0 then s.state = "partial"
    elseif s.shortItems > 0 then s.state = "short"
    elseif s.collectItems > 0 then s.state = "collect"
    else s.state = "ready" end
    return rows, s
end

-- What the bank and the guild bank may be PLANNED WITH, from the observations (FX.StockObs), by the rules in Stock.lua's header. Returns an
-- object with Bank(item), Guild(item) (numbers, never nil), Scope() and TabState(index).
function REF.StockView(obs)
    local FRESH = 6 * 3600
    local v = {}
    local bankCounted = obs.bank ~= nil and not obs.bank.uncertain and not obs.live.bankPending
    local guildOn = obs.useGuild and obs.inGuild and obs.guild ~= nil
    function v.TabState(tab)
        if tab.u or obs.live.guildPending then return "uncertain" end
        if obs.char == nil or tab.by ~= obs.char then return "rights" end   -- another character's rights are not yours
        if tab.w == 0 then return "nowithdraw" end
        if tab.w ~= 1 then return "rights" end                              -- unknown is not permission
        if tab.rem == 0 and obs.now - tab.at < FRESH then return "limit" end   -- the allowance was used up and that is still believed
        return "count"
    end
    function v.Bank(item)
        if not bankCounted then return 0 end
        local n = 0
        for _, tab in pairs(obs.bank.tabs) do n = n + (tab.n[item] or 0) end
        return n
    end
    function v.Guild(item)
        if not guildOn then return 0 end
        local n = 0
        for _, tab in pairs(obs.guild.tabs) do
            if v.TabState(tab) == "count" then n = n + (tab.n[item] or 0) end
        end
        return n
    end
    function v.Scope()
        if guildOn then return bankCounted and "bags, bank and guild bank" or "bags and guild bank" end
        if bankCounted then return "bags and bank" end
        return "bags only"
    end
    return v
end

-- Stock.Craft: one craft's materials judged alone against everything held. Returns { state, bags, bank, guild, missing }.
function REF.CraftState(mats, have, bank, guild)
    local out = { state = "ready", bags = 0, bank = 0, guild = 0, missing = 0 }
    if type(mats) ~= "table" or #mats == 0 then out.state = "unknown" return out end
    local collect = false
    for _, m in ipairs(mats) do
        local h = Held(have(m.item))
        if h == nil then out.state = "unknown" return out end
        local t = REF.Take(m.qty, h, bank(m.item), guild(m.item))
        out.bags, out.bank, out.guild = out.bags + t.bags, out.bank + t.bank, out.guild + t.guild
        if t.missing > 0 then out.missing = out.missing + 1 end
        if t.bank + t.guild > 0 then collect = true end
    end
    if out.missing > 0 then out.state = "short" elseif collect then out.state = "collect" end
    return out
end

---------------------------------------------------------------------------
-- 5. Shopping: the cost of every sourcing choice, and the choices as a list
---------------------------------------------------------------------------
-- A scenario is FX.Crafting's. Costs are whole copper; every figure is an exact integer. The rules (Shopping.lua's header): each missing
-- material is bought from the vendor or the auction house, or made by ONE known recipe (one level: a made material's reagents are bought, never
-- made in turn); owned items are one shared pool (bags, bank, guild bank) that is spent once; what is taken from storage is collected, not bought;
-- the cash is each bought item priced ONCE for its whole quantity; making is valued at what its reagents would cost, owned ones included.

-- the smallest whole number k with k * d >= n, found by counting
local function Ceil(n, d)
    local k = 0
    while k * d < n do k = k + 1 end
    return k
end

-- The ways to buy `qty` of an item: { vendor = { state, cost }, auction = { state, cost, complete } } (a source with no entry does not exist).
-- vendor states: ok (whole stacks, ceil(qty / stack) purchases), limited (the merchant had fewer when seen), noprice (a merchant is known, no price).
-- auction states: exact (qty is within what is listed at the cheapest price), estimate (more than that: price x qty is the least it could cost),
-- few (fewer listed in all than asked for). The auction scan's own price list is the lookup.
function REF.BuyOptions(scn, item, qty)
    local o = {}
    local v = scn.vendor[item]
    if v then
        local purchases = Ceil(qty, v.s)
        local items = purchases * v.s
        if v.a >= 0 and items > v.a then
            o.vendor = { state = "limited", purchases = purchases, items = items }
        else
            o.vendor = { state = "ok", cost = purchases * v.p, purchases = purchases, items = items, surplus = items - qty }
        end
    elseif scn.sells[item] then
        o.vendor = { state = "noprice" }
    end
    local a = scn.auction[item]
    if a then
        if a.total < qty then
            o.auction = { state = "few", complete = a.complete }
        else
            o.auction = { state = qty <= a.qty and "exact" or "estimate", cost = a.price * qty, complete = a.complete }
        end
    end
    return o
end

-- the cheapest priced way to buy: { source, cost, estimate, complete } or nil. A tie goes to the vendor.
local function BestBuy(o)
    local best
    if o.vendor and o.vendor.cost then best = { source = "vendor", cost = o.vendor.cost } end
    if o.auction and o.auction.cost and (not best or o.auction.cost < best.cost) then
        best = { source = "auction", cost = o.auction.cost, estimate = o.auction.state == "estimate" }
    end
    return best
end
REF.BestBuy = BestBuy

-- what one owned item is worth: the lowest price per item known, as a fraction num/den (a vendor's price over its stack, the auction price), or nil
local function UnitValue(scn, item)
    local num, den
    local v = scn.vendor[item]
    if v then num, den = v.p, v.s end
    local a = scn.auction[item]
    if a and (not num or a.price * den < num) then num, den = a.price, 1 end
    return num, den
end

-- A context is the state of a plan being made: which materials are made, which are reagents of those, how much of each layer they took.
function REF.NewContext(scn, rows)
    local ctx = { scn = scn, rowsBy = {}, made = {}, reagent = {}, used = {} }
    for _, r in ipairs(rows) do ctx.rowsBy[r.item] = r end
    return ctx
end

-- what of an item is still free in the bags, the bank and the guild bank after the queue's own crafts and the made materials so far; nil when its
-- bag count is unknown
local function Free(ctx, item)
    local base
    local r = ctx.rowsBy[item]
    if r then
        if r.have == nil then return nil end
        base = REF.Take(math.max(0, r.need - (r.made or 0)), r.have, r.bank, r.guild).left
    else
        local scn = ctx.scn
        if scn.unknown[item] then return nil end
        base = { scn.bags[item] or 0, scn.bank[item] or 0, scn.guild[item] or 0 }
    end
    local u = ctx.used[item] or { 0, 0, 0 }
    return { math.max(0, base[1] - u[1]), math.max(0, base[2] - u[2]), math.max(0, base[3] - u[3]) }
end

-- Making `short` of an item by one recipe. state "ok", or why not: unsupported (materials unknown or empty), noamount, range (the output varies),
-- circular (it uses the item), chain (a reagent is being made, or the item is a reagent of something being made), toomany (more than 999 crafts).
-- When ok: crafts, made, surplus, lines (item, qty, bags, bank, guild, owned, buy, source, cost, value), cash (nil unless every bought line is priced),
-- cost (the economic cost: cash plus the value of the owned reagents; nil unless both are known), estimate, ownedUnknown.
function REF.MakeOption(scn, ctx, item, short, rec)
    local opt = { state = "ok", rec = rec }
    local mats = rec.mats
    if type(mats) ~= "table" or #mats == 0 then opt.state = "unsupported" return opt end
    local lo = rec.outMin
    if not lo then opt.state = "noamount" return opt end
    if (rec.outMax or lo) ~= lo then opt.state = "range" return opt end
    for _, m in ipairs(mats) do if m.item == item then opt.state = "circular" return opt end end
    if ctx.reagent[item] then opt.state = "chain" return opt end
    for _, m in ipairs(mats) do if ctx.made[m.item] then opt.state = "chain" return opt end end
    local crafts = Ceil(short, lo)
    if crafts > MAX_CRAFTS then opt.state = "toomany" return opt end
    opt.crafts, opt.made, opt.surplus, opt.lines = crafts, crafts * lo, crafts * lo - short, {}
    local cash, cashKnown, value, valueKnown = 0, true, 0, true
    for _, m in ipairs(mats) do
        local total = m.qty * crafts
        local free = Free(ctx, m.item)
        local t = free and REF.Take(total, free[1], free[2], free[3]) or { bags = 0, bank = 0, guild = 0, missing = total }
        if not free then opt.ownedUnknown = true end
        local line = { item = m.item, qty = total, bags = t.bags, bank = t.bank, guild = t.guild, owned = t.bags + t.bank + t.guild, buy = t.missing }
        if line.buy > 0 then
            local b = BestBuy(REF.BuyOptions(scn, m.item, line.buy))
            if b then
                line.source, line.cost = b.source, b.cost
                cash = cash + b.cost
                if b.estimate then opt.estimate = true end
            else
                cashKnown = false
            end
        end
        if line.owned > 0 then
            local num, den = UnitValue(scn, m.item)
            if num then
                line.value = RoundHalfUp(line.owned * num, den)
                value = value + line.value
            else
                valueKnown = false
            end
        end
        opt.lines[#opt.lines + 1] = line
    end
    if cashKnown then opt.cash = cash end
    if cashKnown and valueKnown then opt.cost = cash + value end
    return opt
end

-- the material is now made: its reagents are spent from the pool and can no longer be made themselves
function REF.Spend(ctx, item, opt)
    ctx.made[item] = opt.rec
    for _, line in ipairs(opt.lines) do
        ctx.reagent[line.item] = true
        local u = ctx.used[line.item] or { 0, 0, 0 }
        ctx.used[line.item] = { u[1] + line.bags, u[2] + line.bank, u[3] + line.guild }
    end
end

-- the best recipe for an item: the cheapest that can be done, else the first that can be done, else the first one (to say why not)
function REF.BestMake(scn, ctx, item, short)
    local best, firstOk, any
    for i, rec in ipairs(scn.recipes[item] or {}) do
        if i > MAX_CANDIDATES then break end
        local o = REF.MakeOption(scn, ctx, item, short, rec)
        any = any or o
        if o.state == "ok" then
            firstOk = firstOk or o
            if o.cost and (not best or o.cost < best.cost) then best = o end
        end
    end
    return best or firstOk or any
end

-- The suggestion for one material: the cheapest option whose cost is known; a tie goes to vendor, then auction, then making.
function REF.Suggest(buy, make)
    local best, bestCost
    local function Consider(kind, o)
        if o and o.cost and (kind ~= "make" or o.state == "ok") and (not bestCost or o.cost < bestCost) then best, bestCost = kind, o.cost end
    end
    Consider("vendor", buy.vendor)
    Consider("auction", buy.auction)
    Consider("make", make)
    return best
end

-- The shopping plan the player's choices (or the planner's) amount to, for rows made by REF.Rows. assign[item] = "vendor" | "auction" |
-- { make = recipe } | nil (no source: nothing is bought or made of it). Choices are applied in item order. Returns
--   { feasible = false, why } when a choice cannot be done (a source that does not exist, a recipe that may not be used, two made materials that depend
--   on each other), else { feasible = true, cash, priced, missing, estimate, incomplete, makes, collect = { ["item:bank"|"item:guild"] = qty },
--   acquire = { [item] = { qty, source, cost, state } }, makeInfo = { [item] = option } }.
-- Every bought item is priced once for its whole quantity (what it needs for itself plus what made materials need of it). cash adds only priced
-- items; `missing` counts the items bought with no price (an unsourced one, a source with no price, a quantity the source cannot supply).
function REF.Plan(scn, rows, assign, reverse)
    local ctx = REF.NewContext(scn, rows)
    local shorts, items = {}, {}
    for _, r in ipairs(rows) do
        if r.short and r.short > 0 then shorts[r.item] = r.short items[#items + 1] = r.item end
    end
    table.sort(items, function(a, b) if reverse then return a > b end return a < b end)
    local res = { feasible = true, makeInfo = {}, acquire = {}, collect = {} }
    for _, item in ipairs(items) do
        local a = assign[item]
        if a == "vendor" or a == "auction" then
            if not REF.BuyOptions(scn, item, shorts[item])[a] then return { feasible = false, why = "no " .. a .. " option", item = item } end
        elseif type(a) == "table" then
            local opt = REF.MakeOption(scn, ctx, item, shorts[item], a.make)
            if opt.state ~= "ok" then return { feasible = false, why = opt.state, item = item } end
            res.makeInfo[item] = opt
            REF.Spend(ctx, item, opt)
        end
    end
    local qty = {}
    for _, item in ipairs(items) do
        if type(assign[item]) ~= "table" then qty[item] = shorts[item] end
    end
    res.makes = 0
    for _, opt in pairs(res.makeInfo) do
        res.makes = res.makes + 1
        for _, line in ipairs(opt.lines) do
            if line.buy > 0 then qty[line.item] = (qty[line.item] or 0) + line.buy end
        end
    end
    local bought = {}
    for item in pairs(qty) do bought[#bought + 1] = item end
    table.sort(bought)
    res.cash, res.priced, res.missing, res.estimate, res.incomplete = 0, 0, 0, false, false
    for _, item in ipairs(bought) do
        local o = REF.BuyOptions(scn, item, qty[item])
        local a = assign[item]
        local src
        if (a == "vendor" or a == "auction") and o[a] then
            src = a
        else
            local b = BestBuy(o)
            src = b and b.source
        end
        local pick = src and o[src]
        local info = { qty = qty[item], source = src, state = pick and pick.state, cost = pick and pick.cost }
        res.acquire[item] = info
        if info.cost then
            res.cash, res.priced = res.cash + info.cost, res.priced + 1
            if src == "auction" and pick.state == "estimate" then res.estimate = true end
            if src == "auction" and pick.complete == false then res.incomplete = true end
        else
            res.missing = res.missing + 1
        end
    end
    -- what is collected from storage: the queue's own needs and the made materials' reagents, one figure per item and store
    for _, r in ipairs(rows) do
        if (r.fromBank or 0) > 0 then res.collect[r.item .. ":bank"] = r.fromBank end
        if (r.fromGuild or 0) > 0 then res.collect[r.item .. ":guild"] = r.fromGuild end
    end
    for _, opt in pairs(res.makeInfo) do
        for _, line in ipairs(opt.lines) do
            if line.bank > 0 then res.collect[line.item .. ":bank"] = (res.collect[line.item .. ":bank"] or 0) + line.bank end
            if line.guild > 0 then res.collect[line.item .. ":guild"] = (res.collect[line.item .. ":guild"] or 0) + line.guild end
        end
    end
    return res
end

-- the choices open for one material: vendor and auction when they exist, then each of the first four known recipes (usable or not)
function REF.Domain(scn, item, short)
    local d = {}
    local o = REF.BuyOptions(scn, item, short)
    if o.vendor then d[#d + 1] = "vendor" end
    if o.auction then d[#d + 1] = "auction" end
    for i, rec in ipairs(scn.recipes[item] or {}) do
        if i > MAX_CANDIDATES then break end
        d[#d + 1] = { make = rec }
    end
    return d
end

-- Calls fn(assign, result) for every combination of choices over the short materials (a material with no choice at all stays unsourced).
-- Returns how many combinations there were, or nil (and calls nothing) when there would be more than `limit`.
function REF.Enumerate(scn, rows, limit, fn)
    local items, domains = {}, {}
    for _, r in ipairs(rows) do
        if r.short and r.short > 0 then
            items[#items + 1] = r.item
        end
    end
    table.sort(items)
    local total = 1
    for i, item in ipairs(items) do
        local short
        for _, r in ipairs(rows) do if r.item == item then short = r.short end end
        local d = REF.Domain(scn, item, short)
        if #d == 0 then d = { false } end
        domains[i] = d
        total = total * #d
        if total > limit then return nil end
    end
    local assign = {}
    local count = 0
    local function Walk(i)
        if i > #items then
            count = count + 1
            local copy = {}
            for k, v in pairs(assign) do copy[k] = v end
            fn(copy, REF.Plan(scn, rows, copy))
            return
        end
        for _, choice in ipairs(domains[i]) do
            assign[items[i]] = choice or nil
            Walk(i + 1)
        end
        assign[items[i]] = nil
    end
    Walk(1)
    return count
end

-- The choices a production plan made, read from its rows: { [item] = "vendor" | "auction" | { make = recipe } | nil } for the short materials.
function REF.AssignmentOf(plan, rows)
    local assign = {}
    for _, r in ipairs(rows) do
        if r.short and r.short > 0 then
            for _, row in ipairs(plan.rows) do
                if row.item == r.item then
                    if row.kind == "make" then assign[r.item] = { make = row.make.rec }
                    elseif row.kind == "buy" and not row.reagentOnly then assign[r.item] = row.source end
                end
            end
        end
    end
    return assign
end

-- The economic total of a result: the cash plus the value of every owned reagent the made materials use (what the plan would cost if nothing
-- were owned, apart from what the queue itself takes)
function REF.Economic(res)
    local total = res.cash
    for _, opt in pairs(res.makeInfo) do
        for _, line in ipairs(opt.lines) do total = total + (line.value or 0) end
    end
    return total
end

-- The decisions a plan with no player choices makes, material by material in item order, as the contract describes them: for each short material the
-- options (vendor, auction, the best recipe), the suggestion, and the made materials committed before the next. Returns { [item] = { buy, make,
-- suggested } } and the context.
function REF.Decisions(scn, rows)
    local ctx = REF.NewContext(scn, rows)
    local items, out = {}, {}
    for _, r in ipairs(rows) do if r.short and r.short > 0 then items[#items + 1] = r end end
    table.sort(items, function(a, b) return a.item < b.item end)
    for _, r in ipairs(items) do
        local buy = REF.BuyOptions(scn, r.item, r.short)
        local make = REF.BestMake(scn, ctx, r.item, r.short)
        local suggested = REF.Suggest(buy, make)
        out[r.item] = { buy = buy, make = make, suggested = suggested }
        if suggested == "make" then REF.Spend(ctx, r.item, make) end
    end
    return out, ctx
end

---------------------------------------------------------------------------
-- 6. The craft estimate and the Opportunities list
---------------------------------------------------------------------------
-- Prices.Estimate for ONE craft, in whole numbers. rec: { outItem, outMin, outMax, mats }; lookup: { [item] = price list or nil }; cut: the auction
-- house's cut in tenths of a percent (50 = 5 %) or nil when it is not confirmed (then profit is before fees). The cut of a sale is rounded to the
-- nearest copper, half up, on the whole sale of one craft's output.
function REF.Estimate(rec, lookup, cut)
    local e = { state = "unknown", mats = {}, missing = 0, cutRate = cut }
    local oldest, incomplete, cheapest = nil, false, false
    local function Seen(p)
        if not oldest or p.at < oldest then oldest = p.at end
        if p.complete ~= true then incomplete = true end
    end
    local function CutOf(amount) return cut and RoundHalfUp(amount * cut, 1000) or 0 end
    local lo, hi = rec.outMin, rec.outMax
    if lo and not hi then hi = lo elseif hi and not lo then lo = hi end   -- an output given only as one number is fixed
    if lo and hi < lo then lo, hi = nil, nil end                          -- a maximum below the minimum is not an output
    e.outMin, e.outMax = lo, hi
    local hasMats = type(rec.mats) == "table" and #rec.mats > 0
    if hasMats then
        local cost = 0
        for _, m in ipairs(rec.mats) do
            local row = { item = m.item, qty = m.qty }
            local p = lookup[m.item]
            if p and p.total < m.qty then row.unavailable = "few" p = nil end   -- not enough listed to buy what one craft needs
            if p then
                row.unit, row.at, row.complete = p.price, p.at, p.complete
                row.total = p.price * m.qty
                row.cheapest = m.qty > p.qty
                cost = cost + row.total
                Seen(p)
                if row.cheapest then cheapest = true end
            else
                if not row.unavailable then row.unavailable = "none" end
                e.missing = e.missing + 1
            end
            e.mats[#e.mats + 1] = row
        end
        if e.missing == 0 then e.cost = cost end
    end
    local sellMissing = false
    if rec.outItem and lo then
        local p = lookup[rec.outItem]
        if p then
            e.unit = p.price
            e.sellLow, e.sellHigh = p.price * lo, p.price * hi
            Seen(p)
            e.netLow, e.netHigh = e.sellLow - CutOf(e.sellLow), e.sellHigh - CutOf(e.sellHigh)
        else
            sellMissing = true
        end
    end
    if not hasMats then e.why = "nomats"
    elseif not rec.outItem then e.why = "noitem"
    elseif not lo then e.why = "noamount"
    elseif e.missing > 0 then e.why = "matprice"
    elseif sellMissing then e.why = "sellprice" end
    if e.cost and e.netLow then
        e.state, e.why = "ok", nil
        e.profitLow, e.profitHigh = e.netLow - e.cost, e.netHigh - e.cost
    end
    e.oldest, e.incomplete, e.cheapest = oldest, incomplete, cheapest
    return e
end

-- The Opportunities order. rows = { { rec = { id, name, prof }, est = estimate } }; opts = { sort = "profit" | "cost" | "sell", desc, prof, profitOnly }.
-- Rows whose estimate is known come first; among them by the chosen figure (the LOW end of a range), then by name without case, then by id.
-- Unknown rows follow, by name then id. Returns the kept rows in order.
function REF.Order(rows, opts)
    local sort, desc = opts.sort or "profit", opts.desc ~= false
    local function Figure(e)
        if sort == "cost" then return e.cost end
        if sort == "sell" then return e.sellLow end
        return e.profitLow
    end
    local kept = {}
    for _, r in ipairs(rows) do
        local keep = opts.prof == nil or r.rec.prof == opts.prof
        if keep and opts.profitOnly then keep = r.est.state == "ok" and r.est.profitLow > 0 end
        if keep then kept[#kept + 1] = r end
    end
    local function Before(a, b)
        local ka, kb = a.est.state == "ok", b.est.state == "ok"
        if ka ~= kb then return ka end
        if ka then
            local va, vb = Figure(a.est), Figure(b.est)
            if va ~= vb then if desc then return va > vb end return va < vb end
        end
        local na, nb = a.rec.name:lower(), b.rec.name:lower()
        if na ~= nb then return na < nb end
        return a.rec.id < b.rec.id
    end
    for i = 2, #kept do
        local r, j = kept[i], i - 1
        while j >= 1 and Before(r, kept[j]) do kept[j + 1] = kept[j] j = j - 1 end
        kept[j + 1] = r
    end
    return kept
end

---------------------------------------------------------------------------
-- 5. VERSION-2 HISTORY (market data foundation 2.0, A4): a deliberately naive model of History2.lua
---------------------------------------------------------------------------
-- The model keeps EVERY accepted scan in full (its time, whether it was a whole read, which items it listed and their p, r, t, l) and derives
-- the expected ring, daily points and buckets of an item from that full record at the end, in one pass per tier, the way the foundation
-- document states the rules (section 3.3 and "A4 as built"): it never folds incrementally, never decodes a string and shares no code with
-- History2.lua. Its own writer (REF.H2Text) builds the saved text from field lists, so a byte comparison with production is a real check of
-- the append path. What it does NOT model: the budget guard (compaction is tested on its own), malformed saved strings, and the per-item
-- "stale" rule (the commit refuses a whole scan dated before the newest recorded one, so a stale item cannot occur in a real market).
local H2REF = { RING = 8, RING_MIN = 2880, DAY = 86400 }
REF.H2 = H2REF

function REF.H2New() return { all = {}, rec = {} } end

-- One ACCEPTED scan: { at, whole (not cut, not changed), partial (records lacking information), items = { [id] = { p, r, t, l } } }.
-- Returns whether it is recorded into the history: a whole read dated no earlier than the newest recorded scan.
function REF.H2Scan(model, scan)
    model.all[#model.all + 1] = scan
    local last = model.rec[#model.rec]
    local fed = scan.whole == true and (not last or scan.at >= last.at)
    scan.fed = fed
    if fed then model.rec[#model.rec + 1] = scan end
    return fed
end

local function Half(sum, n) return math.floor((2 * sum + n) / (2 * n)) end   -- half up (sums here are whole numbers below 2^53)
REF.H2Half = Half

-- The expected decoded state of item `id`: ring (list of { first, last, p, r, t, l, pf } in minutes), days (list of { d, p, r, t, l, n, plo, phi,
-- rlo, rhi, tlo, thi, pf }), buckets (list of { k, s, n, nr, plo, pm, phi, rm, rlo, rhi, tm, tlo, thi, lm, pf, exact = { pm, rm, tm, lm } }),
-- as of the newest recorded scan. nil when nothing is recorded.
function REF.H2Expect(model, id)
    local newest = model.rec[#model.rec]
    if not newest then return nil end
    local M, T = math.floor(newest.at / 60), math.floor(newest.at / H2REF.DAY)
    -- the ring: an observation extends the newest point only when the values (and the partial flag) are the same, that point was seen by
    -- the previous recorded scan (same minute), and it is still within 48 hours of this one; else it is a new point
    local pts, prevMin = {}, nil
    for _, sc in ipairs(model.rec) do
        local sm = math.floor(sc.at / 60)
        local o = sc.items[id]
        if o then
            local pf = (sc.partial or 0) > 0
            local lp = pts[#pts]
            if lp and prevMin and lp.last == prevMin and lp.last >= sm - H2REF.RING_MIN and lp.p == o.p and lp.r == o.r and lp.t == o.t and lp.l == o.l and lp.pf == pf then
                lp.last = sm
            else
                pts[#pts + 1] = { first = sm, last = sm, p = o.p, r = o.r, t = o.t, l = o.l, pf = pf }
            end
        end
        prevMin = sm
    end
    local ring = {}
    for _, x in ipairs(pts) do if x.last >= M - H2REF.RING_MIN then ring[#ring + 1] = x end end
    while #ring > H2REF.RING do table.remove(ring, 1) end
    -- every listed day: the closing values are the day's last recorded scan; the ranges every scan of it
    local byDay, order = {}, {}
    for _, sc in ipairs(model.rec) do
        local o = sc.items[id]
        if o then
            local d = math.floor(sc.at / H2REF.DAY)
            local x = byDay[d]
            if not x then x = { d = d, n = 0, obs = {} } byDay[d] = x order[#order + 1] = d end
            x.n = x.n + 1
            x.obs[#x.obs + 1] = o
            x.p, x.r, x.t, x.l = o.p, o.r, o.t, o.l
            if (sc.partial or 0) > 0 then x.pf = true end
        end
    end
    table.sort(order)
    local allDays = {}
    for _, d in ipairs(order) do
        local x = byDay[d]
        for _, o in ipairs(x.obs) do
            x.plo, x.phi = math.min(x.plo or o.p, o.p), math.max(x.phi or o.p, o.p)
            x.tlo, x.thi = math.min(x.tlo or o.t, o.t), math.max(x.thi or o.t, o.t)
            if o.r then x.rlo, x.rhi = math.min(x.rlo or o.r, o.r), math.max(x.rhi or o.r, o.r) end
        end
        allDays[#allDays + 1] = x
    end
    -- tiers by the newest day T: daily from the start of the calendar week holding T - 29; weekly to a pair of weeks ending 60 days back;
    -- two-week to 120 days back
    local dailyFrom = 7 * math.floor((T - 29) / 7)
    local days, weeks, wlist = {}, {}, {}
    for _, x in ipairs(allDays) do
        if x.d >= dailyFrom then days[#days + 1] = x
        else
            local w = math.floor(x.d / 7)
            if not weeks[w] then weeks[w] = {} wlist[#wlist + 1] = w end
            table.insert(weeks[w], x)
        end
    end
    local function Bucket(k, s, list)
        local b = { k = k, s = s, n = #list, nr = 0, exact = {} }
        local sp, sr, st, sl = 0, 0, 0, 0
        for _, x in ipairs(list) do
            b.plo, b.phi = math.min(b.plo or x.plo, x.plo), math.max(b.phi or x.phi, x.phi)
            b.tlo, b.thi = math.min(b.tlo or x.tlo, x.tlo), math.max(b.thi or x.thi, x.thi)
            if x.rlo then b.rlo, b.rhi = math.min(b.rlo or x.rlo, x.rlo), math.max(b.rhi or x.rhi, x.rhi) end
            sp, st, sl = sp + x.p, st + x.t, sl + x.l
            if x.r then sr, b.nr = sr + x.r, b.nr + 1 end
            if x.pf then b.pf = true end
        end
        b.pm, b.tm, b.lm = Half(sp, b.n), Half(st, b.n), Half(sl, b.n)
        b.exact = { pm = sp / b.n, tm = st / b.n, lm = sl / b.n, rm = b.nr > 0 and sr / b.nr or nil }
        if b.nr > 0 then b.rm = Half(sr, b.nr) end
        return b
    end
    local bks, pairsOf, plist = {}, {}, {}
    for _, w in ipairs(wlist) do
        local wb = Bucket(w, 7, weeks[w])
        if 14 * math.floor(w / 2) + 13 < T - 60 then
            local k = math.floor(w / 2)
            if not pairsOf[k] then pairsOf[k] = {} plist[#plist + 1] = k end
            table.insert(pairsOf[k], wb)
        else
            bks[#bks + 1] = wb
        end
    end
    -- a two-week bucket: the documented merge of its (rounded) weekly buckets, each metric weighted by its own count; and the exact means
    local merged = {}
    for _, k in ipairs(plist) do
        local ws = pairsOf[k]
        local f = { k = k, s = 14, n = 0, nr = 0, exact = {} }
        local ep, et, el, er, tlok = 0, 0, 0, 0, true
        for _, wb in ipairs(ws) do
            f.plo, f.phi = math.min(f.plo or wb.plo, wb.plo), math.max(f.phi or wb.phi, wb.phi)
            f.tlo, f.thi = math.min(f.tlo or wb.tlo, wb.tlo), math.max(f.thi or wb.thi, wb.thi)
            if wb.rlo then f.rlo, f.rhi = math.min(f.rlo or wb.rlo, wb.rlo), math.max(f.rhi or wb.rhi, wb.rhi) end
            if wb.pf then f.pf = true end
            ep, et, el = ep + wb.exact.pm * wb.n, et + wb.exact.tm * wb.n, el + wb.exact.lm * wb.n
            if wb.nr > 0 then er = er + wb.exact.rm * wb.nr end
        end
        local a, b = ws[1], ws[2]
        if not b then
            f.n, f.nr, f.pm, f.rm, f.tm, f.lm = a.n, a.nr, a.pm, a.rm, a.tm, a.lm
        else
            f.n, f.nr = a.n + b.n, a.nr + b.nr
            f.pm, f.tm, f.lm = Half(a.pm * a.n + b.pm * b.n, f.n), Half(a.tm * a.n + b.tm * b.n, f.n), Half(a.lm * a.n + b.lm * b.n, f.n)
            if a.nr > 0 and b.nr > 0 then f.rm = Half(a.rm * a.nr + b.rm * b.nr, f.nr) else f.rm = a.rm or b.rm end
        end
        f.exact = { pm = ep / f.n, tm = et / f.n, lm = el / f.n, rm = f.nr > 0 and er / f.nr or nil }
        merged[#merged + 1] = f
    end
    local all = {}
    for _, f in ipairs(merged) do all[#all + 1] = f end
    for _, b in ipairs(bks) do all[#all + 1] = b end
    local kept = {}
    for _, b in ipairs(all) do if b.k * b.s + b.s - 1 >= T - 120 then kept[#kept + 1] = b end end
    return { ring = ring, days = days, buckets = kept, T = T, M = M }
end

-- The saved text of an expected state, written from the document's field lists (not from History2.lua): h2 text or nil, c2 text or nil
local function F(v) return ("%.0f"):format(v) end
function REF.H2Text(e)
    if not e then return nil, nil end
    local h2, c2
    if #e.days > 0 then
        local rs, prev = {}, nil
        for _, x in ipairs(e.ring) do
            local f = { F(prev and x.first - prev.first or x.first), F(x.last - x.first), F(x.p), x.r and F(x.r - x.p) or "", F(x.t), F(x.l) }
            rs[#rs + 1] = table.concat(f, ",") .. (x.pf and "!" or "")
            prev = x
        end
        local ds, pd = {}, nil
        for _, x in ipairs(e.days) do
            local f = { F(pd and x.d - pd or x.d), F(x.p), x.r and F(x.r - x.p) or "", F(x.t), F(x.l) }
            if x.n > 1 then
                f[#f + 1] = F(x.n)
                local flat = x.plo == x.p and x.phi == x.p and x.tlo == x.t and x.thi == x.t and x.rlo == x.r and x.rhi == x.r
                if not flat then
                    f[#f + 1] = F(x.p - x.plo) f[#f + 1] = F(x.phi - x.p)
                    if x.r then f[#f + 1] = F(x.r - x.rlo) f[#f + 1] = F(x.rhi - x.r)
                    elseif x.rlo then f[#f + 1] = F(x.rlo) f[#f + 1] = F(x.rhi)
                    else f[#f + 1] = "" f[#f + 1] = "" end
                    f[#f + 1] = F(x.t - x.tlo) f[#f + 1] = F(x.thi - x.t)
                end
            end
            ds[#ds + 1] = table.concat(f, ",") .. (x.pf and "!" or "")
            pd = x.d
        end
        h2 = table.concat(rs, ";") .. "|" .. F(e.days[#e.days].d) .. ":" .. table.concat(ds, ";")
    end
    if #e.buckets > 0 then
        local bs = {}
        for _, b in ipairs(e.buckets) do
            local f = { F(b.k), F(b.s), F(b.n), F(b.nr), F(b.plo), F(b.pm - b.plo), F(b.phi - b.pm) }
            if b.rm then f[#f + 1] = F(b.rm) f[#f + 1] = F(b.rm - b.rlo) f[#f + 1] = F(b.rhi - b.rm)
            elseif b.rlo then f[#f + 1] = "" f[#f + 1] = F(b.rlo) f[#f + 1] = F(b.rhi)
            else f[#f + 1] = "" f[#f + 1] = "" f[#f + 1] = "" end
            f[#f + 1] = F(b.tm) f[#f + 1] = F(b.tm - b.tlo) f[#f + 1] = F(b.thi - b.tm) f[#f + 1] = F(b.lm)
            bs[#bs + 1] = table.concat(f, ",") .. (b.pf and "!" or "")
        end
        c2 = table.concat(bs, ";")
    end
    return h2, c2
end

-- Why a day has no point for an item, from the full scan record: "noscan", "incomplete" (only cut or changed scans), "unlisted" (a recorded
-- scan that day did not list it), "unknown" (a whole read that day was not recorded and no recorded scan was); nil when the item was listed
function REF.H2DayReason(model, id, d)
    local any, whole, fed, listed = false, false, false, false
    for _, sc in ipairs(model.all) do
        if math.floor(sc.at / H2REF.DAY) == d then
            any = true
            if sc.whole then whole = true end
            if sc.fed then fed = true if sc.items[id] then listed = true end end
        end
    end
    if listed then return nil end
    if fed then return "unlisted" end
    if whole then return "unknown" end
    if any then return "incomplete" end
    return "noscan"
end

---------------------------------------------------------------------------
-- 7. VALUATION (market data foundation 2.0, A5): deliberately naive models of Valuation.lua
---------------------------------------------------------------------------
-- These never call Valuation.lua, Market.lua, History2.lua or Dist.lua. A weighted median is read off an EXPANDED, sorted list (a value of weight
-- w written w times; the median is the entry at rank ceil(W / 2)), a window is tested day by day, a bucket's share of a window is counted day by
-- day, a cost is the sum of the cheapest entries of the expanded item list, and the history comes from the history model (section 5: REF.H2Expect,
-- every scan kept in full). Policy constants are restated here from the foundation document (section 4A, D7, D8), not read from production.
local VREF = { MV = 14, HV = 60, HV_MIN = 3, Q_DAYS = 30 }
REF.V = VREF

local function Expanded(list)
    table.sort(list)
    return list[math.ceil(#list / 2)], #list
end
REF.VLowerMedian = function(list) local copy = {} for i, v in ipairs(list) do copy[i] = v end return (Expanded(copy)) end

-- a bucket's days inside from .. to, counted one by one; it is used when all of it, or at least half of its days, lie inside
local function BucketShare(a, e, from, to)
    local inside = 0
    for d = a, e do if d >= from and d <= to then inside = inside + 1 end end
    return inside, inside > 0 and 2 * inside >= (e - a + 1)
end
REF.VBucketShare = BucketShare

-- Market Value from an expected history state (REF.H2Expect) as of `today`: { v, n, weight } or nil and "nohistory" / "stale" / "norecent"
function REF.VMarketValue(e, today)
    if not e or (#e.days == 0 and #e.buckets == 0) then return nil, "nohistory" end
    local list, n, listed = {}, 0, 0
    for _, x in ipairs(e.days) do
        local age = today - x.d
        if age >= 0 and age <= VREF.MV - 1 then
            listed = listed + 1
            if x.r then
                n = n + 1
                local w = 1
                if age < 3 then w = 4 elseif age < 7 then w = 2 end
                for _ = 1, w do list[#list + 1] = x.r end
            end
        end
    end
    if n == 0 then return nil, listed > 0 and "norecent" or "stale" end
    local v, weight = Expanded(list)
    return { v = v, n = n, weight = weight }
end

-- Historical Value: { v, n (observed days), aggregate } or nil and "nohistory" / "insufficient"
function REF.VHistorical(e, today)
    if not e or (#e.days == 0 and #e.buckets == 0) then return nil, "nohistory" end
    local from, list, agg = today - VREF.HV + 1, {}, false
    for _, x in ipairs(e.days) do if x.r and x.d >= from and x.d <= today then list[#list + 1] = x.r end end
    for _, b in ipairs(e.buckets) do
        local _, used = BucketShare(b.k * b.s, b.k * b.s + b.s - 1, from, today)
        if used and b.nr > 0 then
            for _ = 1, b.nr do list[#list + 1] = b.rm end
            agg = true
        end
    end
    if #list < VREF.HV_MIN then return nil, "insufficient", #list end
    local v, n = Expanded(list)
    return { v = v, n = n, aggregate = agg }
end

-- TrendOf: field "r", "p" or "t"; { direction, older, newer (medians), no, nn } (direction "insufficient" when a half has fewer than 2 days)
function REF.VTrend(e, today, field, days)
    local half = math.floor(days / 2)
    local older, newer = {}, {}
    for _, x in ipairs(e and e.days or {}) do
        local age = today - x.d
        if x[field] and age >= 0 and age < days then
            if age < half then newer[#newer + 1] = x[field] else older[#older + 1] = x[field] end
        end
    end
    local out = { no = #older, nn = #newer }
    if #older > 0 then out.older = Expanded(older) end
    if #newer > 0 then out.newer = Expanded(newer) end
    if #older < 2 or #newer < 2 then out.direction = "insufficient" return out end
    local a, b = out.older, out.newer
    -- flat: the change is under 5% of the older median (as a fraction: |b - a| / a < 1 / 20)
    if math.abs(b - a) * 20 < a then out.direction = "flat" elseif b > a then out.direction = "rising" else out.direction = "falling" end
    return out
end

-- Range from the expected state: { min = { lo, hi, n }, recent = { lo, hi, n }, supply = { lo, hi, n }, aggregate } or nil and "nohistory" / "nodata"
function REF.VRange(e, today, days)
    if not e or (#e.days == 0 and #e.buckets == 0) then return nil, "nohistory" end
    local from = today - days + 1
    local mn, rc, sp, any, agg = { n = 0 }, { n = 0 }, { n = 0 }, false, false
    local function Put(t, lo, hi) if lo then t.lo = math.min(t.lo or lo, lo) t.hi = math.max(t.hi or hi, hi) end end
    for _, x in ipairs(e.days) do
        if x.d >= from and x.d <= today then
            any = true
            mn.n, sp.n = mn.n + 1, sp.n + 1
            if x.r then rc.n = rc.n + 1 end
            Put(mn, x.plo, x.phi) Put(sp, x.tlo, x.thi) Put(rc, x.rlo, x.rhi)
        end
    end
    for _, b in ipairs(e.buckets) do
        local _, used = BucketShare(b.k * b.s, b.k * b.s + b.s - 1, from, today)
        if used then
            any, agg = true, true
            mn.n, sp.n, rc.n = mn.n + b.n, sp.n + b.n, rc.n + b.nr
            Put(mn, b.plo, b.phi) Put(sp, b.tlo, b.thi) Put(rc, b.rlo, b.rhi)
        end
    end
    if not any then return nil, "nodata" end
    return { min = mn, recent = rc, supply = sp, aggregate = agg }
end

-- Data Quality, policy 1, from plain facts: { priced, complete, cut, age, listings, spreadClass (nil = no distribution), observed, mixed,
-- farbelow }. Returns the level and the set of reason codes (every requirement of "good" that is not met).
function REF.VQuality(f)
    if not f.priced then return "none", {} end
    local codes, good, fair = {}, true, true
    local function Fail(code, alsoFair) codes[code] = true good = false if alsoFair then fair = false end end
    if f.cut then Fail("cut", true) elseif not f.complete then Fail("incomplete") end
    if f.age > 3 * 86400 then Fail("age", true) elseif f.age > 86400 then Fail("age") end
    if f.listings < 5 then Fail("listings", f.listings < 3) end
    if f.spreadClass == nil then Fail("nodistribution") elseif f.spreadClass == "wide" then Fail("spread") end
    if f.observed < 7 then Fail("days") end
    if f.mixed then Fail("mixedvariants", true) end
    if f.farbelow then Fail("farbelow") end
    return good and "good" or (fair and "fair" or "limited"), codes
end

-- spread class of three quartiles: (q75 - q25) / q50 below 1/10 tight, below 3/10 moderate, else wide (as exact fractions)
function REF.VSpreadClass(q25, q50, q75)
    local num, den = q75 - q25, q50
    if num * 10 < den then return "tight" end
    if num * 10 < den * 3 then return "moderate" end
    return "wide"
end

-- the plain facts of one item's listings: records = { { b, c } } (whole-copper unit prices: b = unit x c). Returns { p, t, l, groups (by unit,
-- cheapest first: { p, q, l, sizes = { counts } }), entries (every item's unit price, sorted), farbelow, cheapoutlier (needs r) }
function REF.VListings(records)
    local by, groups, entries = {}, {}, {}
    for _, rec in ipairs(records) do
        local u = CeilCopper(rec.b, rec.c)
        local g = by[u]
        if not g then g = { p = u, q = 0, l = 0, sizes = {} } by[u] = g groups[#groups + 1] = g end
        g.q, g.l = g.q + rec.c, g.l + 1
        g.sizes[#g.sizes + 1] = rec.c
        for _ = 1, rec.c do entries[#entries + 1] = u end
    end
    table.sort(groups, function(a, b) return a.p < b.p end)
    table.sort(entries)
    local out = { groups = groups, entries = entries, t = #entries, l = #records, p = entries[1] }
    out.farbelow = #records < 5 and groups[2] ~= nil and 2 * groups[1].p < groups[2].p
    return out
end

-- Competition: the first of the six cheapest prices at or above half the anchor `a`, and the items priced at or below it
function REF.VCompetition(lst, a)
    local competing
    for i = 1, math.min(6, #lst.groups) do
        if 2 * lst.groups[i].p >= a then competing = lst.groups[i].p break end
    end
    local ahead
    if competing then ahead = 0 for _, u in ipairs(lst.entries) do if u <= competing then ahead = ahead + 1 end end end
    return { cheapest = lst.groups[1].p, competing = competing, ahead = ahead }
end

-- Cost of qty: { state, low, high } from the plain listings. Within the six cheapest prices: low = the cheapest qty entries added up; high = whole
-- listings at the last price used (at most its largest listing minus one item over, never more than it holds). Beyond: low = the six prices
-- whole and every further item at one copper above the sixth price, high = every further item at the highest price, whole listings of the rest.
function REF.VCost(lst, qty)
    if lst.t < qty then return { state = "few" } end
    local six, sixItems, sixCost = math.min(6, #lst.groups), 0, 0
    for i = 1, six do sixItems, sixCost = sixItems + lst.groups[i].q, sixCost + lst.groups[i].q * lst.groups[i].p end
    if qty <= sixItems then
        local low = 0
        for i = 1, qty do low = low + lst.entries[i] end
        local before, beforeCost = 0, 0
        for i = 1, six do
            local g = lst.groups[i]
            if before + g.q >= qty then
                local rem, largest = qty - before, 0
                for _, c in ipairs(g.sizes) do if c > largest then largest = c end end
                -- a one-price item is saved without a distribution entry: its largest listing is not kept, only that it is at most what the
                -- other listings leave (each holds at least one item)
                if #lst.groups == 1 and g.l > 1 then largest = g.q - g.l + 1 end
                local whole = math.min(rem + largest - 1, g.q)
                -- listings all of one size (the tier's items are its listings times the largest): the number of listings needed, exactly
                if largest * g.l == g.q then whole = largest * math.ceil(rem / largest) end
                local high = beforeCost + whole * g.p
                return { state = high == low and "exact" or "range", low = low, high = high, group = g, rem = rem, beforeCost = beforeCost }
            end
            before, beforeCost = before + g.q, beforeCost + g.q * g.p
        end
    end
    local tq, tl = 0, 0
    for i = 7, #lst.groups do tq, tl = tq + lst.groups[i].q, tl + lst.groups[i].l end
    local rem = qty - sixItems
    local low = sixCost + rem * (lst.groups[six].p + 1)
    local high = sixCost + math.min(rem + tq - tl, tq) * lst.entries[#lst.entries]
    local actual = 0
    for i = 1, qty do actual = actual + lst.entries[i] end
    return { state = "estimate", low = low, high = high, actual = actual }
end
