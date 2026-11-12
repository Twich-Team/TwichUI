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

local function Whole(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi and v % 1 == 0 end

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
            elseif r.buyout == 0 then
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
function REF.EntryText(e) return ("%d,%d,%d,%d,%d"):format(e.p, e.q, e.l, e.t, e.x) end

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
