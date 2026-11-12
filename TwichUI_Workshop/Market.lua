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
local PR, H, SC = W.Prices, W.History, W.Scan
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
        read = m.read, used = m.used, scans = m.scanDays and #m.scanDays or 0 }
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

-- The direction between the first and the last observed day of the last `days` days (default 7, exact days only):
--   direction "up", "down" or "flat", from / to (the two prices), change (copper, signed), percent (of the first, one decimal), n (days)
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
    return { item = item, direction = dir, from = a, to = b, change = b - a, percent = math.floor((b - a) / a * 1000 + (b >= a and 0.5 or -0.5)) / 10,
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
