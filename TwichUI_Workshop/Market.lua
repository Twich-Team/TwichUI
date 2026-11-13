-- TwichUI Workshop: the market data API (W.Market)
-- THE one place the rest of the Workshop (and anything later) asks "what does this item cost at the auction house": the Opportunities
-- view, the shopping list and the "What's it worth?" tooltip all come through here, so they cannot disagree. It reads the saved
-- markets (Prices.lua) and their history (History.lua); it changes nothing, calls no auction house function and returns copies, never
-- the saved tables. Every question that cannot be answered says WHY, in a short word, and never answers with a made-up zero.
--
-- WHAT EACH ANSWER IS (the words matter, they are never stretched):
--   Every figure carries a `basis` sentence saying what it is; none is a market value, a sale average or an expected selling price.
--   Price      the CHEAPEST BUYOUT LISTING per single item in the newest accepted scan of a market ("latest listing"). A listing, not a sale.
--   Stats      over a period: how many days the item was observed, the lowest and the highest of those days' cheapest listings, and
--              their MEAN ("average of observed lows"). It is not time-weighted, not volume-weighted, and not a sale price.
--   Trend      the change between the first and the last observed day of the period. Two observed days are needed.
--   Compare    the current price against the mean of the OBSERVED days BEFORE the day of the current scan.
--   Quote      what buying n of the item is expected to cost, and how much of that the scan proves (Prices.Quote).
--   Nothing here is a "market value", a sale rate, a demand figure or a confidence score: the scan sees listings only. A future
--   typical-value model gets its own function; these names stay what they say.
--
-- OPTIONS (every function takes an optional last table):
--   market  a market key ("Realm|Alliance"), a market from Market.Source(), or nil for the one the views use (Source)
--   now     the time to measure age against (default time())
--   variant true when the caller's item is a variant (suffix, bonus ids, item level): a full scan keeps one price per ITEM ID and cannot
--           tell variants apart, so such an item is refused ("variant") instead of being given the base item's price.
--
-- REASONS (the second return value when there is no answer):
--   baditem     the item id is not a whole number in range      badqty      the quantity is not
--   nomarket    nothing has been scanned for that market        variant     the item is a variant (above)
--   unlisted    the newest full scan of the market listed no buyout for the item (not the same as "worth nothing")
--   outofscope  the market's scan is from before full scans and holds only the items of the recipes known then: absence says nothing
--   nodata      the history holds nothing for the item in that period      insufficient   there is too little to compare or to see a trend
--   badperiod   the period is not one of "week", "retained" or a whole number of days

local R = TwichUI
local W = R.Workshop
local PR, H, SC, H2 = W.Prices, W.History, W.Scan, W.History2
local Int = W.Int
local MK = {}
W.Market = MK

MK.BASIS = {
    price = "The cheapest buyout listing per item in the newest scan. A listing, not a sale.",
    stats = "The mean, lowest and highest of the cheapest buyout listing on each day the item was observed. Not a sale price, a market value or an expected selling price.",
    trend = "The change in the cheapest buyout listing between the first and last observed day. Not a forecast.",
    compare = "The current cheapest listing against the mean of the cheapest listings on earlier observed days. Not a sale price.",
}

MK.PERIODS = { week = 7 }          -- named periods, in days; "retained" is everything the history holds
MK.REASONS = {
    baditem = "That isn't a valid item.", badqty = "That isn't a valid quantity.", nomarket = "No auction house has been scanned yet.",
    variant = "This is a variant of the item; a scan prices the item id, not its variants.",
    unlisted = "The newest scan saw no buyout listing for it.", outofscope = "The saved scan only covers items of known recipes.",
    nodata = "No saved history for it in that period.", insufficient = "Not enough saved history yet.", badperiod = "That isn't a supported period.",
}

---------------------------------------------------------------------------
-- Which market
---------------------------------------------------------------------------
-- The market the views use: with an auction house open only that one, otherwise the most recently scanned market of this realm.
-- Returns { open, key, market (checked saved scan or nil), label }.
function MK.Source()
    local open = SC.AuctionOpen()
    local key, market
    if open then
        key = SC.Market()
        market = key and PR.Market(key) or nil
    else
        local realm = SC.Realm()
        market = realm and PR.Newest(realm) or nil
    end
    return { open = open, key = key, market = market, label = market and PR.Label(market) or nil }
end

local function Resolve(opt)
    local m = opt and opt.market
    if type(m) == "table" then return m.items and m or m.market end
    if type(m) == "string" then return PR.Market(m) end
    return MK.Source().market
end

local function Now(opt) return opt and Int(opt.now, 1, 4102444800) or time() end

---------------------------------------------------------------------------
-- Markets
---------------------------------------------------------------------------
local function Summary(m, now)
    return { key = m.key, label = PR.Label(m), realm = m.realm, side = m.side, at = m.at, age = PR.Age(m.at, now), old = PR.Age(m.at, now) > PR.OLD_AFTER,
        scope = m.scope, complete = m.scope == "full" and m.complete, cut = m.cut == true, partial = m.partial or 0, legacy = m.legacy == true, items = m.n,
        read = m.read, used = m.used, scans = m.scanDays and #m.scanDays or 0,
        -- the saved format (A2): the market's format (2 = TwichUI 1.3's, 3 = market data foundation 2.0), the database version, where
        -- version-2 coverage begins, how many valid entries the scan log and the day log hold, and the budget guard's record (nil = none)
        format = m.format, dbVersion = PR.DbVersion(), v2from = m.v2from, scanLog = m.scanLog and #(PR.ScanLog(m)) or nil,
        dayLog = m.dayLog and #(PR.DayLog(m)) or nil, compact = m.compact,
        -- (A4) the version-2 history's own record: its format, the first day and newest scan recorded, its text size and entry counts;
        -- state "future" = a later build's format, never read here. compact (above) says when older detail was condensed and whether the
        -- budget could not be met (compact.over).
        history = m.h2info and m.h2info.state ~= "none" and { state = m.h2info.state, format = m.h2info.v, from = m.h2info.from, at = m.h2info.at,
            bytes = m.h2info.bytes, items = m.h2info.items, citems = m.h2info.citems } or nil }
end

-- What is known of one market: when it was scanned, how much of it was seen, how many scan days its history has. nil, "nomarket".
--   scope "full" (every listed item was kept) or "recipes" (a scan from before full scans: only the items of the recipes known then)
--   complete (a whole read with every record's information loaded), cut (listings may be missing), partial (records whose information
--   had not loaded when read; their prices were used), items (how many are priced), read/used (records read / used for a price)
function MK.Info(opt)
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    return Summary(m, Now(opt))
end

-- Every saved market, newest scan first
function MK.Markets(opt)
    local now, out = Now(opt), {}
    for _, key in ipairs(PR.Keys()) do
        local m = PR.Market(key)
        if m then out[#out + 1] = Summary(m, now) end
    end
    table.sort(out, function(a, b) if a.at ~= b.at then return a.at > b.at end return a.key < b.key end)
    return out
end

---------------------------------------------------------------------------
-- The current price
---------------------------------------------------------------------------
-- { item, price (copper each), qty (items at that price), listings, total (items listed), next (the next higher unit price, or nil),
--   at, age, old, complete, scope, cut, partial, market (key), label, notes }
-- notes is a list of plain facts that qualify the figure: "recipes" (from a scan of recipe items only), "partial" (some records'
-- information had not loaded), "cut" (listings may be missing), "old" (more than a day), "thin" (a single listing).
-- Or nil and a reason.
function MK.Price(item, opt)
    item = Int(item, 1, W.MAX_ID)
    if not item then return nil, "baditem" end
    if opt and opt.variant then return nil, "variant" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    local p = PR.Lookup(m, item)
    if not p then return nil, m.scope == "full" and "unlisted" or "outofscope" end
    local now = Now(opt)
    local age = PR.Age(m.at, now)
    local notes = {}
    if m.scope ~= "full" then notes[#notes + 1] = "recipes" end
    if m.partial and m.partial > 0 then notes[#notes + 1] = "partial" end
    if m.cut then notes[#notes + 1] = "cut" end
    if age > PR.OLD_AFTER then notes[#notes + 1] = "old" end
    if p.listings == 1 then notes[#notes + 1] = "thin" end
    return { item = item, price = p.price, qty = p.qty, listings = p.listings, total = p.total, next = p.next, at = m.at, age = age,
        old = age > PR.OLD_AFTER, complete = m.complete, scope = m.scope, cut = m.cut == true, partial = m.partial or 0, market = m.key,
        label = PR.Label(m), notes = notes, basis = MK.BASIS.price }
end

-- What buying `qty` of the item is expected to cost (Prices.Quote's states: exact, estimate, few, none), plus the price it came from.
-- Always a table: state "none" with a `why` when there is no usable price.
function MK.Quote(item, qty, opt)
    local n = Int(qty, 1, W.MAX_ID)
    if not n then return { state = "none", why = "badqty" } end
    local p, why = MK.Price(item, opt)
    if not p then return { state = "none", qty = n, why = why } end
    local q = PR.Quote(p, n)
    q.price, q.notes = p, p.notes
    return q
end

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------
local function Period(period)
    if period == nil or period == "week" then return MK.PERIODS.week, "week" end
    if period == "retained" then return nil, "retained" end
    local d = Int(period, 1, H.RETAIN_DAYS)
    if d then return d, d end
    return false
end

local function HistoryOf(m, item)
    if not (m.hist and m.scope == "full") then return nil end
    return m.hist[item]
end

local function ScansIn(m, from, to)
    if not m.scanDays then return nil end
    local n = 0
    for _, d in ipairs(m.scanDays) do if d >= from and d <= to then n = n + 1 end end
    return n
end

-- What the history holds for an item over a period ("week" = the last 7 days, a whole number of days up to H.RETAIN_DAYS, or
-- "retained" = everything kept), counting back from today (or opt.now):
--   n (days the item was observed), scans (scan days in that period that fed the history, nil when unknown), low, high (the lowest and
--   highest of those days' cheapest listings), average (their mean, whole copper), newest (the newest observed day and its price),
--   exact (every figure comes from exact days; false when older 28-day buckets contributed: their low, high and mean are real but
--   the days inside them are not kept), limited (observed days inside buckets that straddle the start of the period were NOT counted),
--   single (only one day: an average of one value is that value, not a history), days (the period's length, nil for "retained")
-- or nil and a reason (nomarket, baditem, badperiod, outofscope, nodata).
function MK.Stats(item, period, opt)
    item = Int(item, 1, W.MAX_ID)
    if not item then return nil, "baditem" end
    local days, name = Period(period)
    if days == false then return nil, "badperiod" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    if m.scope ~= "full" then return nil, "outofscope" end
    local s = HistoryOf(m, item)
    if not s then return nil, "nodata" end
    local today = H.Day(Now(opt))
    if not today then return nil, "nodata" end
    local from = days and (today - days + 1) or 1
    local w = H.Window(s, from, today)
    if not w then return nil, "nodata" end
    local newestDay, newestPrice = H.Newest(s)
    return { item = item, period = name, days = days, from = from, to = today, n = w.n, scans = ScansIn(m, from, today), low = w.lo, high = w.hi,
        average = math.floor(w.sum / w.n + 0.5), newest = newestDay and { day = newestDay, price = newestPrice } or nil, exact = w.exact,
        limited = w.skipped > 0, single = w.n == 1, market = m.key, label = PR.Label(m), basis = MK.BASIS.stats }
end

-- The price observed on one day (a time or a day number): { day, price } when that day's value is still kept exactly, else nil and
-- why: "nodata" (no history), "notobserved" (kept days exist but not this one: no scan listed it that day, or there was no scan), or
-- "notretained" (older than the exact days; only a bucket remains)
function MK.Observed(item, when, opt)
    item = Int(item, 1, W.MAX_ID)
    if not item then return nil, "baditem" end
    local day = Int(when, 1, 200000) or H.Day(when)
    if not day then return nil, "baditem" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    if m.scope ~= "full" then return nil, "outofscope" end
    local s = HistoryOf(m, item)
    local pts, bks = H.Decode(s)
    if not pts then return nil, "nodata" end
    for i = 1, #pts, 2 do
        if pts[i] == day then return { day = day, price = pts[i + 1] } end
    end
    if #pts >= 2 and day < pts[1] and #bks > 0 then return nil, "notretained" end
    return nil, "notobserved"
end

-- The history as it can be drawn: the exact observed days of an item and the older 28-day groups behind them, nothing in between made up.
--   points   { { day, price } ... } oldest first: the last observed days (at most H.POINTS), each one a day a full scan listed the item
--   groups   { { from, to, low, high, average, n } ... } oldest first: older observed days kept only as a low, a high and a mean per group
--   today    the day number of now (opt.now), so a caller can say how long ago a day was
-- A day on which no scan listed the item is simply not in the list: the picture has a gap there, not a line. nil and a reason (nomarket,
-- baditem, outofscope, nodata) when there is nothing to draw.
function MK.Series(item, opt)
    item = Int(item, 1, W.MAX_ID)
    if not item then return nil, "baditem" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    if m.scope ~= "full" then return nil, "outofscope" end
    local pts, bks = H.Decode(HistoryOf(m, item))
    if not pts then return nil, "nodata" end
    local points, groups = {}, {}
    for i = 1, #pts, 2 do points[#points + 1] = { day = pts[i], price = pts[i + 1] } end
    for i = 1, #bks, 5 do
        groups[#groups + 1] = { from = bks[i] * H.BUCKET_DAYS, to = bks[i] * H.BUCKET_DAYS + H.BUCKET_DAYS - 1, low = bks[i + 1], high = bks[i + 2],
            average = math.floor(bks[i + 3] / bks[i + 4] + 0.5), n = bks[i + 4] }
    end
    return { item = item, points = points, groups = groups, today = H.Day(Now(opt)), market = m.key, label = PR.Label(m), basis = MK.BASIS.stats }
end

---------------------------------------------------------------------------
-- (A4) The version-2 history as a chart can draw it
---------------------------------------------------------------------------
MK.HISTORY_UNITS = { min = "copper", recent = "copper", supply = "items", listings = "listings" }
MK.HISTORY_BASIS = {
    min = "The cheapest buyout listing per item: at each observation, the closing value of each listed day with that day's low and high, and the low, mean and high of older weeks. Listings, not sales.",
    recent = "The Recent Price, a representative listing price (the mean of the cheapest 30% of the listed items, very low outliers ignored), at each observation, each listed day and older weeks. Recorded since version-2 history began; never taken from the older minimum history. Not a sale price.",
    supply = "How many items were listed, at each observation, each listed day (with that day's fewest and most) and older weeks. Listed, never sold.",
    listings = "How many buyout listings there were, at each observation, each listed day and older weeks (their mean). Listed, never sold.",
}
MK.GAP_REASONS = {
    noscan = "No scan of this auction house on these days.", unlisted = "Scanned, and it was not listed.",
    incomplete = "Only incomplete scans these days.", notretained = "Older than the history keeps.",
    beforev2 = "Before this history began recording.", norecent = "Listed, but no Recent Price could be worked out.",
    unknown = "Scanned, but that scan was not recorded into the history.",
}

local function Pick(x, metric)
    if metric == "min" then return x.p, x.plo, x.phi end
    if metric == "recent" then return x.r, x.rlo, x.rhi end
    if metric == "supply" then return x.t, x.tlo, x.thi end
    return x.l, nil, nil
end
local function PickBucket(b, metric)
    if metric == "min" then return b.pm, b.plo, b.phi, b.n end
    if metric == "recent" then return b.rm, b.rlo, b.rhi, b.nr end
    if metric == "supply" then return b.tm, b.tlo, b.thi, b.n end
    return b.lm, nil, nil, b.n
end

-- History(item, metric, opt) -> chart-ready series, or nil and a reason (baditem, badmetric, variant, nomarket, outofscope, format).
--   metric   "min", "recent", "supply" or "listings"
--   opt      market, now, from / to (times; default: everything kept, up to now), sources (a list of "local" and "legacy"; default both;
--            legacy points exist for "min" only, before the version-2 history began)
-- Returns { item, metric, unit, basis, market, label, today, from, to (days), v2from, recordedFrom, compact, damaged, ringFull,
--   points = { oldest first: legacy, buckets, days, then observations } where a point is
--     obs            { kind, at (first sighting, seconds), last (last sighting, when seen again), v, partial, exact = true, provenance = "local" }
--     day            { kind, from = to = day, v (the closing value; nil for "recent" when only the day's range is known, then missing = "norecent"),
--                      lo, hi (the day's extremes; nil when condensed or for listings), n (scans), partial, condensed, exact = true }
--     week/fortnight { kind, from, to, v (mean), lo, hi, n (observed days with a value), partial, condensed, rangeDropped, exact = false }
--     legacy-day / legacy-bucket   the frozen minimum history (provenance = "legacy"), only for "min" and only before recordedFrom
--   gaps  = { { from, to, reason } } days with no point and why (MK.GAP_REASONS); nothing is ever interpolated or filled with zero
--   marks = { { at, reason } } scans of the scan log (48 h) the item's observations do not account for: unlisted / incomplete / unknown /
--           notretained (the ring keeps 8 observations: when it is full, older scans are "notretained", not "unlisted")
--   resolution = { { from, to, kind } } where each kind of point lies (days; obs also has fromAt / toAt) }
function MK.History(item, metric, opt)
    item = Int(item, 1, W.MAX_ID)
    if not item then return nil, "baditem" end
    if not MK.HISTORY_UNITS[metric] then return nil, "badmetric" end
    if opt and opt.variant then return nil, "variant" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    if m.scope ~= "full" then return nil, "outofscope" end
    local info = m.h2info
    if info and info.state == "future" then return nil, "format" end
    local now = Now(opt)
    local today = H.Day(now)
    local toAt = opt and Int(opt.to, 1, 4102444800) or now
    if toAt > now then toAt = now end
    local fromAt = opt and Int(opt.from, 1, 4102444800) or (now - (H2.RETAIN_DAYS + 14) * H2.DAY)
    local fromDay, toDay = H.Day(fromAt) or 1, H.Day(toAt) or today
    local src = { ["local"] = true, legacy = true }
    if opt and type(opt.sources) == "table" then
        src = {}
        for _, k in ipairs(opt.sources) do src[k] = true end
    end
    local recordedFrom = info and info.from or nil
    local ring, days, bks, bad
    if src["local"] then ring, days, bks, bad = H2.Read(m.h2 and m.h2[item], m.c2 and m.c2[item]) end
    ring, days, bks = ring or {}, days or {}, bks or {}

    local out = { item = item, metric = metric, unit = MK.HISTORY_UNITS[metric], basis = MK.HISTORY_BASIS[metric], market = m.key, label = PR.Label(m),
        today = today, from = fromDay, to = toDay, v2from = m.v2from, recordedFrom = recordedFrom, compact = m.compact, damaged = bad,
        ringFull = #ring >= H2.RING, points = {}, gaps = {}, marks = {}, resolution = {} }
    local pts, covered, norecent = out.points, {}, {}
    local spans = {}
    local function Span(kind, a, b)
        local sp = spans[kind]
        if not sp then sp = { from = a, to = b, kind = kind } spans[kind] = sp spans[#spans + 1] = sp
        else if a < sp.from then sp.from = a end if b > sp.to then sp.to = b end end
    end
    local function Cover(a, b) for d = math.max(a, fromDay), math.min(b, toDay) do covered[d] = true end end

    -- the frozen legacy minimum history: only "min", only days before version-2 recording began (never counted twice)
    if metric == "min" and src.legacy then
        local lp, lb = H.Decode(m.hist and m.hist[item])
        if lp then
            local limit = (recordedFrom or (today + 1)) - 1
            local firstExact = lp[1] or (limit + 1)
            for i = 1, #lb, 5 do
                local a, b = lb[i] * H.BUCKET_DAYS, math.min(lb[i] * H.BUCKET_DAYS + H.BUCKET_DAYS - 1, firstExact - 1, limit)
                if b >= a and b >= fromDay and a <= toDay then
                    pts[#pts + 1] = { kind = "legacy-bucket", from = a, to = b, v = math.floor(lb[i + 3] / lb[i + 4] + 0.5), lo = lb[i + 1], hi = lb[i + 2],
                        n = lb[i + 4], exact = false, provenance = "legacy" }
                    Cover(a, b) Span("legacy", a, b)
                end
            end
            for i = 1, #lp, 2 do
                local d = lp[i]
                if d <= limit and d >= fromDay and d <= toDay then
                    pts[#pts + 1] = { kind = "legacy-day", from = d, to = d, v = lp[i + 1], n = 1, exact = true, provenance = "legacy" }
                    Cover(d, d) Span("legacy", d, d)
                end
            end
        end
    end
    -- buckets: always aggregates
    for _, b in ipairs(bks) do
        local a, e = b.k * b.s, H2.BucketEnd(b)
        if e >= fromDay and a <= toDay then
            local v, lo, hi, n = PickBucket(b, metric)
            local kind = b.s == 7 and "week" or "fortnight"
            if v or lo then
                pts[#pts + 1] = { kind = kind, from = a, to = e, v = v, lo = lo, hi = hi, n = n, partial = b.pf, condensed = b.cf,
                    rangeDropped = metric == "supply" and b.tlo == nil or nil, missing = (not v) and "norecent" or nil, exact = false, provenance = "local" }
                Cover(a, e) Span(kind, a, e)
            else
                for d = a, e do norecent[d] = true end
            end
        end
    end
    -- daily points: exact days
    for _, x in ipairs(days) do
        if x.d >= fromDay and x.d <= toDay then
            local v, lo, hi = Pick(x, metric)
            if v or lo then
                pts[#pts + 1] = { kind = "day", from = x.d, to = x.d, v = v, lo = (not x.cf) and lo or nil, hi = (not x.cf) and hi or nil, n = x.n,
                    partial = x.pf, condensed = x.cf, missing = (not v) and "norecent" or nil, exact = true, provenance = "local" }
                Cover(x.d, x.d) Span("day", x.d, x.d)
            else
                norecent[x.d] = true
            end
        end
    end
    -- observations: real times
    local obsFrom, obsTo
    for _, x in ipairs(ring) do
        local at, last = x.m * 60, (x.m + x.dm) * 60
        local v = Pick(x, metric)
        if v and last >= fromAt and at <= toAt then
            pts[#pts + 1] = { kind = "obs", at = at, last = x.dm > 0 and last or nil, v = v, partial = x.pf, exact = true, provenance = "local" }
            obsFrom, obsTo = obsFrom or at, last
        end
    end

    -- why the other days have no point (the day log says what happened; it never says the item was there)
    local dayLog = {}
    local newestLog
    for _, e in ipairs(PR.DayLog(m) or {}) do dayLog[e.day] = e.flags newestLog = e.day end
    local DF = PR.DAY_FLAGS
    local function Bit(flags, bit) return math.floor(flags / bit) % 2 == 1 end
    local function Reason(d)
        if norecent[d] then return "norecent" end
        if not recordedFrom or d < recordedFrom then return "beforev2" end
        local f = dayLog[d]
        if f then
            if Bit(f, DF.FED) then return "unlisted" end
            if Bit(f, DF.WHOLE) then return "unknown" end
            return "incomplete"
        end
        if newestLog and d < newestLog - PR.DAY_LOG_DAYS + 1 then return "notretained" end
        if not newestLog then return "unknown" end
        return "noscan"
    end
    local gap
    for d = fromDay, math.min(toDay, today) do
        if not covered[d] then
            local why = Reason(d)
            if gap and gap.reason == why and gap.to == d - 1 then gap.to = d
            else gap = { from = d, to = d, reason = why } out.gaps[#out.gaps + 1] = gap end
        end
    end
    -- scans of the last 48 hours the observations do not account for
    if src["local"] then
        local SF = PR.SCAN_FLAGS
        local oldest = ring[1] and ring[1].m or nil
        for _, e in ipairs(PR.ScanLog(m) or {}) do
            if e.at >= fromAt and e.at <= toAt and e.at >= (m.at or 0) - H2.RING_MINUTES * 60 and (not recordedFrom or H.Day(e.at) >= recordedFrom) then
                local em, seen = math.floor(e.at / 60), false
                for _, x in ipairs(ring) do if em >= x.m and em <= x.m + x.dm then seen = true break end end
                if not seen then
                    local why
                    if not Bit(e.flags, SF.WHOLE) then why = "incomplete"
                    elseif not Bit(e.flags, SF.FED) then why = "unknown"
                    elseif out.ringFull and oldest and em < oldest then why = "notretained"
                    else why = "unlisted" end
                    out.marks[#out.marks + 1] = { at = e.at, reason = why }
                end
            end
        end
    end
    for _, sp in ipairs(spans) do out.resolution[#out.resolution + 1] = { from = sp.from, to = sp.to, kind = sp.kind } end
    if obsFrom then out.resolution[#out.resolution + 1] = { from = H.Day(obsFrom), to = H.Day(obsTo), fromAt = obsFrom, toAt = obsTo, kind = "obs" } end
    return out
end

-- The change from a to b as a percentage of a, in whole TENTHS of a percent, rounded to the nearest with a tie going AWAY from zero, the
-- same for a fall as for a rise (1000 -> 900 is exactly -100, never -101). Whole-number arithmetic only: prices are below 10^11, so every
-- intermediate value is exact and a tie is never decided by floating-point noise.
local function PercentTenths(a, b)
    local num, den = 1000 * math.abs(b - a), a
    local r = (2 * num + den) % (2 * den)
    local tenths = (2 * num + den - r) / (2 * den)
    if tenths == 0 then return 0 end
    return b < a and -tenths or tenths
end

-- The direction between the first and the last observed day of the last `days` days (default 7, exact days only):
--   direction "up", "down" or "flat", from / to (the two prices), change (copper, signed), percent (of the first, one decimal, a tie away
--   from zero), n (days)
-- Two observed days are needed: nil, "insufficient" otherwise. It says where the price went, not why, and not where it goes next.
function MK.Trend(item, days, opt)
    item = Int(item, 1, W.MAX_ID)
    if not item then return nil, "baditem" end
    local d = days == nil and MK.PERIODS.week or Int(days, 2, H.RETAIN_DAYS)
    if not d then return nil, "badperiod" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    if m.scope ~= "full" then return nil, "outofscope" end
    local pts = H.Decode(HistoryOf(m, item))
    if not pts then return nil, "nodata" end
    local from = H.Day(Now(opt)) - d + 1
    local first, last, n
    n = 0
    for i = 1, #pts, 2 do
        if pts[i] >= from then
            n = n + 1
            if not first then first = i end
            last = i
        end
    end
    if n < 2 then return nil, "insufficient" end
    local a, b = pts[first + 1], pts[last + 1]
    local dir = b > a and "up" or (b < a and "down" or "flat")
    return { item = item, direction = dir, from = a, to = b, change = b - a, percent = PercentTenths(a, b) / 10,
        n = n, fromDay = pts[first], toDay = pts[last], basis = MK.BASIS.trend }
end

-- The current price against the mean of the observed days BEFORE the day of the current scan (so the current scan does not vote on
-- its own reference):
--   current, reference (the mean), relation ("above", "below" or "same"), difference (copper, signed), ratio (current / reference), n
--   (days behind the reference), stats (Stats' answer for that window)
-- or nil and a reason (those of Price and Stats; "insufficient" when no earlier day exists).
function MK.Compare(item, period, opt)
    local days, name = Period(period)
    if days == false then return nil, "badperiod" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    local p, why = MK.Price(item, { market = m, now = opt and opt.now, variant = opt and opt.variant })
    if not p then return nil, why end
    local s = HistoryOf(m, p.item)
    if not s then return nil, m.scope ~= "full" and "outofscope" or "nodata" end
    local to = H.Day(p.at) - 1
    local w = H.Window(s, days and (to - days + 1) or 1, to)
    if not w then return nil, "insufficient" end
    local ref = math.floor(w.sum / w.n + 0.5)
    return { item = p.item, current = p.price, reference = ref, period = name, relation = p.price > ref and "above" or (p.price < ref and "below" or "same"),
        difference = p.price - ref, ratio = p.price / ref, n = w.n, exact = w.exact, limited = w.skipped > 0, price = p, basis = MK.BASIS.compare }
end

---------------------------------------------------------------------------
-- The status of the prices, for the window's footer chip
---------------------------------------------------------------------------
-- A presentation policy, read-only and deterministic: what the newest scan's age and coverage are, in a few words. FRESHNESS and
-- COMPLETENESS are two properties and are never merged: a partial scan can be a minute old, and a day-old scan can be whole.
--   freshness  "fresh"  scanned up to MK.FRESH_AFTER ago (2 hours)
--              "aging"  older than that, up to PR.OLD_AFTER (a day): usable
--              "old"    older than a day
--   complete   true only when the scan was a whole read (Summary.complete); false is "Partial scan" whatever its age
--   The scan in progress outranks both: "scanning" (with its progress) and "saving" (the scan's last phase, the prices being committed).
-- Nothing here runs on a timer: the age is worked out when the footer is drawn (on opening, navigation and a scan's changes).
-- Returns { state = "scanning" | "saving" | "none" | "ready", text, icon ("done" | "current"), tone ("good" | "warn" | "bad" | "quiet"),
--   freshness, complete, age (seconds), tip = { lines } (the whole market, when, how much was seen, and the limits) }.
MK.FRESH_AFTER = 2 * 3600

-- "32m ago", "5h ago", "3d ago"
function MK.AgeShort(seconds)
    if type(seconds) ~= "number" then return "at an unknown time" end
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return ("%dm ago"):format(math.floor(seconds / 60)) end
    if seconds < 86400 then return ("%dh ago"):format(math.floor(seconds / 3600)) end
    return ("%dd ago"):format(math.floor(seconds / 86400))
end

function MK.Freshness(age)
    if type(age) ~= "number" then return nil end
    if age <= MK.FRESH_AFTER then return "fresh" end
    if age <= PR.OLD_AFTER then return "aging" end
    return "old"
end

function MK.Status(opt)
    local src = MK.Source()
    local m = (opt and opt.market) or src.market
    local now = Now(opt)
    local tip = {}
    if SC.state == "scanning" then
        local saving = SC.phase == "saving"
        local pct = math.floor((SC.Progress() or 0) * 100 + 0.5)
        tip[1] = saving and "The prices of this scan are being saved." or "A scan of the open auction house is running."
        tip[2] = "It only reads: nothing is bought, bid or posted."
        return { state = saving and "saving" or "scanning", text = saving and "Saving prices" or ("Scanning prices \194\183 %d%%"):format(pct),
            icon = "current", tone = "warn", tip = tip }
    end
    if not m then
        tip[1] = src.open and "No prices are saved for this auction house yet." or "No auction house prices are saved for this realm yet."
        tip[2] = "Open the auction house and choose Scan prices."
        return { state = "none", text = "No prices yet", icon = "current", tone = "quiet", tip = tip }
    end
    local info = Summary(m, now)
    local age = info.age
    local fresh = MK.Freshness(age)
    local complete = info.complete == true
    local when = MK.AgeShort(age)
    local text, icon, tone
    if complete then
        if fresh == "fresh" then text, icon, tone = "Prices updated " .. when, "done", "good"
        elseif fresh == "aging" then text, icon, tone = "Prices updated " .. when, "current", "warn"
        else text, icon, tone = "Old prices \194\183 " .. when, "current", "bad" end
    else
        text = (fresh == "old" and "Old partial scan \194\183 " or "Partial scan \194\183 ") .. when
        icon, tone = "current", fresh == "old" and "bad" or "warn"
    end
    -- the whole market is here (and nowhere in the normal text): which realm and side, since two markets are never merged
    tip[#tip + 1] = (PR.Label(m) or "the auction house"):gsub("^%l", string.upper)
    tip[#tip + 1] = ("Scanned %s (%s)"):format(PR.AgeText(age), fresh == "fresh" and "fresh" or (fresh == "aging" and "getting old" or "old"))
    tip[#tip + 1] = complete and "Coverage: a complete scan." or "Coverage: partial. Some listings may be missing from this scan."
    if info.items then tip[#tip + 1] = ("%d items priced"):format(info.items) end
    if info.scans and info.scans > 1 then tip[#tip + 1] = ("%d scan days of history"):format(info.scans) end
    if info.scope ~= "full" then tip[#tip + 1] = "From an older scan that kept only the items of known recipes." end
    tip[#tip + 1] = "Cheapest buyout listings per item. A listing is not a sale."
    return { state = "ready", text = text, icon = icon, tone = tone, freshness = fresh, complete = complete, age = age, tip = tip }
end
