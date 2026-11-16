-- TwichUI Workshop: market valuation and intelligence (Market Data Foundation 2.0, milestone A5)
-- docs/workshop/market-data-foundation-v2.md sections 4A, 4B, 4F, 10 and "A5 as built". READ-ONLY: this file adds services to W.Market that
-- interpret what the scans saved (Prices.lua's snapshot and distribution, History2.lua's version-2 history). It writes nothing, calls no auction
-- house function, decodes the saved strings only through Dist.Decode / History2.Read, and every table it returns is new (never a saved table).
-- The existing Market.Price / Stats / Trend / Compare / Observed / Series / History keep their meanings; nothing here changes them.
--
-- ROLES (every result says which; no function of one role returns another):
--   valuation    what something has been LISTED for (Value, Range, Distribution, Supply, TrendOf, Posture, Quality). A reference, never a sale
--                price, an expected sale price or a price to post.
--   competition  what is listed NOW that a seller would compete with (Competition). Evidence, never a suggested price (A8 builds that).
--   purchase     what buying a quantity would have cost at the newest scan's listings, cheapest first (Cost). An estimate from listings that
--                may have sold or expired since; never a completed purchase.
--
-- OPTIONS (every function takes an optional last table): market (a key, a checked market from Prices.Market or Market.Source(); a key with no
-- saved market is "nomarket": no other market is ever substituted; nil = Market.Source(), the market the views show), now (the time to measure
-- against; default time()), variant (the caller's item is a variant: refused), sources (a list; the valuations read only "local" data and refuse
-- a list without it; Range also accepts "legacy"), mixedvariants (true: the caller knows the item's variants are mixed).
--
-- REASONS (the second return value of nil; Cost and Posture carry them in `why` instead): MK.VALUE_REASONS.
local R = TwichUI
local W = R.Workshop
local PR, H2, MK = W.Prices, W.History2, W.Market
local Int = W.Int
local floor = math.floor
local V = {}
W.Valuation = V

MK.API = 2                 -- section 10: the Market API with the A4 history and the A5 services
MK.QUALITY_POLICY = 1      -- the Data Quality rules below (owner decision D7); a later policy changes thresholds, never saved data

V.DAY = 86400
V.MV_DAYS = 14             -- Market Value: daily closing Recent Prices of the last 14 UTC days (ages 0 to 13)
V.HV_DAYS = 60             -- Historical Value: the last 60 days
V.HV_MIN_DAYS = 3          -- Historical Value needs this many observed days with a Recent Price
V.RANGE_DAYS = 120         -- the longest Range window
V.TREND_DAYS = 14          -- TrendOf's default window; 4 to 30 days (the daily points' guarantee), two observed days in each half
V.TREND_MAX_DAYS = 30
V.FLAT_PERCENT = 5         -- |change| below 5% of the older median is flat
V.POSTURE_LOW, V.POSTURE_HIGH = 85, 115   -- percent of Historical Value (owner decision D8)
V.POSTURE_DAYS, V.POSTURE_LISTINGS = 5, 3
V.GOOD_AGE, V.FAIR_AGE = 86400, 3 * 86400
V.GOOD_LISTINGS, V.FAIR_LISTINGS = 5, 3
V.GOOD_DAYS, V.QUALITY_DAYS = 7, 30
V.THIN_LISTINGS = 3        -- "thin": fewer listings than this
V.CACHE_MAX = 2000         -- digests kept at most (two generations of half each)
local TWO53 = 9007199254740992

MK.VALUE_KINDS = { min = true, recent = true, market = true, historical = true }
MK.VALUE_BASIS = {
    min = "Minimum Buyout: the cheapest buyout listing per item in the newest scan. A listing, not a sale; only that listing's items are known to be at this price.",
    recent = "Recent Price: a representative listing price from the newest scan (the mean of the cheapest 30% of the listed items, very low outliers ignored). A listing price, not a sale price.",
    market = "Market Value: a recency-weighted median of the daily closing Recent Prices of the last 14 days of observed auction house listings. A historical reference from listings, not a sale price.",
    historical = "Historical Value: the median of the daily closing Recent Prices of the last 60 days of observed auction house listings, older weeks counted by their mean. A historical reference from listings, not a sale price or a promise.",
    range = "The lowest and highest observed listing prices and supply over the period. Observed listings only; days without a scan say nothing.",
    distribution = "How the newest scan's buyout listings are spread over prices. Listings, not sales; spread is not how much sale prices move.",
    supply = "How many items were listed. Listed, never sold: supply says nothing about demand or what sells.",
    trend = "The median of the newer half of the period against the older half, one metric on both sides. Where it went, not where it goes next.",
    posture = "The Recent Price against the Historical Value of observed listings. Not a guarantee of profit or of a sale.",
    quality = "How much the market data behind a price can be trusted, and why. Policy 1.",
    competition = "The newest scan's listings a seller would compete with. Evidence, not a suggested price; listings may have sold or expired since.",
    cost = "What buying this many would have cost at the newest scan's listings, cheapest first. Listings may have sold or expired since; not a completed purchase.",
}
MK.VALUE_REASONS = {
    baditem = "That isn't a valid item.", badqty = "That isn't a valid quantity.", badkind = "That isn't a supported value.",
    badmetric = "That isn't a supported measure.", baddays = "That isn't a supported period.", badsource = "That data source isn't supported here.",
    nomarket = "No saved scan of that auction house.", variant = "This is a variant of the item; a scan prices the item id, not its variants.",
    unlisted = "The newest scan saw no buyout listing for it.", outofscope = "The saved scan only covers items of known recipes.",
    noevidence = "The newest scan has no price distribution.", missing = "The newest scan should hold this item's price distribution and does not.",
    malformed = "The saved data for this item cannot be read.", format = "The history was saved by a newer TwichUI.",
    nohistory = "No price history is recorded for it yet.", stale = "Not observed in the last 14 days.",
    norecent = "Observed, but without a Recent Price in that period.", insufficient = "Not enough observed days yet.",
    nodata = "No observations in that period.",
}

---------------------------------------------------------------------------
-- Which market, and the common arguments
---------------------------------------------------------------------------
local function Resolve(opt)
    local m = opt and opt.market
    if m == nil then return MK.Source().market end
    if type(m) == "string" then return PR.Market(m) end
    if type(m) == "table" then
        if type(m.items) == "table" then return m end
        if type(m.market) == "table" and type(m.market.items) == "table" then return m.market end   -- a Market.Source() answer
    end
    return nil
end

local function HasSource(list, name)
    if type(list) ~= "table" then return false end
    for _, s in ipairs(list) do if s == name then return true end end
    return false
end

-- cx = { item, m, now, today, opt } or nil and why. The rest of a call's pieces (snapshot, digest, quality, variants) are worked out once, when needed.
local function Context(item, opt)
    if type(opt) ~= "table" then opt = nil end
    item = Int(item, 1, W.MAX_ID)
    if not item then return nil, "baditem" end
    if opt and opt.variant then return nil, "variant" end
    if opt and opt.sources ~= nil and not HasSource(opt.sources, "local") then return nil, "badsource" end
    local m = Resolve(opt)
    if not m then return nil, "nomarket" end
    local now = opt and Int(opt.now, 1, 4102444800) or time()
    return { item = item, m = m, now = now, today = floor(now / V.DAY), opt = opt }
end

local function Base(role, kind, cx)
    return { role = role, kind = kind, item = cx.item, market = cx.m.key, label = PR.Label(cx.m), basis = MK.VALUE_BASIS[kind], provenance = "local", notes = {} }
end
local function Note(r, code) r.notes[#r.notes + 1] = code end

---------------------------------------------------------------------------
-- Item variants (owner decision D6): weapons and armor of uncommon or better quality can carry random suffixes, and a scan keeps one price per
-- item id. Those items MAY mix economically distinct variants. Verified: C_Item.GetItemInfoInstant returns classID (Enum.ItemClass Weapon 2,
-- Armor 4) and C_Item.GetItemQualityByID the quality (Uncommon 2), wow-ui-source forever ItemDocumentation.lua / ItemConstantsDocumentation.lua.
-- An unknown quality of a weapon or armor counts as "may be mixed" (the cautious answer).
---------------------------------------------------------------------------
function V.MixedVariants(item, opt)
    if opt and opt.mixedvariants == true then return true end
    local CI = C_Item
    local instant = CI and CI.GetItemInfoInstant or GetItemInfoInstant
    if type(instant) ~= "function" then return false end
    local ok, _, _, _, _, _, classID = pcall(instant, item)
    classID = ok and Int(classID, 0, 1000) or nil
    if classID ~= 2 and classID ~= 4 then return false end
    local q
    if CI and type(CI.GetItemQualityByID) == "function" then
        local ok2, v = pcall(CI.GetItemQualityByID, item)
        if ok2 then q = Int(v, 0, 100) end
    end
    if q == nil then
        local info = CI and CI.GetItemInfo or GetItemInfo
        if type(info) == "function" then
            local ok3, _, _, v = pcall(info, item)
            if ok3 then q = Int(v, 0, 100) end
        end
    end
    if q ~= nil and q < 2 then return false end
    return true
end

local function Mixed(cx)
    if cx.mixed == nil then cx.mixed = V.MixedVariants(cx.item, cx.opt) end
    return cx.mixed
end

---------------------------------------------------------------------------
-- The newest scan of one item: its minimum entry and its distribution (Prices.Distribution, the A3 reader; nothing is recomputed)
---------------------------------------------------------------------------
-- spread = (q75 - q25) / q50; tight below 10%, moderate below 30%, wide from 30% (compared in whole numbers)
function V.SpreadClass(q25, q50, q75)
    local w = (q75 - q25) * 10
    if w < q50 then return "tight" end
    if w < 3 * q50 then return "moderate" end
    return "wide"
end

---------------------------------------------------------------------------
-- The cache: one entry per (market key, item) holding what is costly to work out again, never anything time-dependent:
--   g    the history digest (below): valid only for the very h2 / c2 strings it was computed from and the same UTC day
--   f    the snapshot facts (Recent Price, spread, flags): valid only for the very items / dist entries they were read from
-- Lua strings compare by identity, so each check is a pointer comparison. A market's generation (snapshot seq and time, the distribution
-- algorithm, the history record) changing empties the whole cache (a scan, a compaction, a retention pass: they are all commits). A replaced
-- database, another day or another market therefore never answer from a stale entry. Age, freshness and the quality levels that depend on them are
-- worked out at every call. Two generations of CACHE_MAX / 2 entries: when the young one fills it becomes the old one (the old one is dropped); an
-- entry found in the old one moves back. At most CACHE_MAX entries. A market table without a key (a caller's synthetic market) is never cached.
---------------------------------------------------------------------------
local young, old, nYoung = {}, {}, 0
local gens = {}
local stats = { hits = 0, misses = 0, snapHits = 0, snapMisses = 0, wipes = 0, uncached = 0 }

function V.CacheClear()
    young, old, nYoung, gens = {}, {}, 0, {}
    stats.wipes = stats.wipes + 1
end
function V.CacheStats()
    local n = nYoung
    for _ in pairs(old) do n = n + 1 end
    return { entries = n, hits = stats.hits, misses = stats.misses, snapHits = stats.snapHits, snapMisses = stats.snapMisses, wipes = stats.wipes,
        uncached = stats.uncached, max = V.CACHE_MAX }
end

local function Generation(m)
    local s, hi = m.snap, m.h2info
    return ("%s:%s:%s:%s:%s:%s:%s"):format(tostring(s and s.seq), tostring(m.at), tostring(s and s.at), tostring(s and s.alg), tostring(m.scope),
        tostring(hi and hi.at), tostring(hi and hi.bytes))
end
V.Generation = Generation   -- (A7) consumers that keep answers (MarketFacts.lua) validate them against the same stamp

-- the call's cache entry (created empty when there is none), or nil for a market without a key
local function Slot(cx)
    if cx.slot ~= nil then return cx.slot or nil end
    local m = cx.m
    local key = type(m.key) == "string" and m.key or nil
    if not key then stats.uncached = stats.uncached + 1 cx.slot = false return nil end
    local gen = Generation(m)
    if gens[key] ~= gen then
        if gens[key] ~= nil then V.CacheClear() end
        gens[key] = gen
    end
    local ck = key .. "\0" .. cx.item
    local e = young[ck]
    if not e then
        e = old[ck]
        if e then old[ck] = nil else e = {} end
        young[ck], nYoung = e, nYoung + 1
        if nYoung >= V.CACHE_MAX / 2 then old, young, nYoung = young, {}, 0 end
    end
    cx.slot = e
    return e
end

---------------------------------------------------------------------------
-- The newest scan of one item: its minimum entry (Prices.Lookup, read at every call: cheap) and its distribution (Prices.Distribution, the A3
-- reader; nothing is recomputed). The few facts the valuations need are cached; the services that hand out tiers decode afresh (SnapDist).
---------------------------------------------------------------------------
local function DistOf(m, item)
    if m.scope ~= "full" then return nil, "noevidence" end
    if m.snap and m.snap.at ~= m.at then return nil, "malformed" end   -- the snapshot record is not the newest scan's: its distribution claim is not trusted
    return PR.Distribution(m, item)
end

local function Facts(d, why)
    if not d then return { dwhy = why } end
    return { has = true, r = d.r, single = d.single == true, exact = d.exact ~= false, spread = (d.q75 - d.q25) / d.q50, spreadClass = V.SpreadClass(d.q25, d.q50, d.q75),
        cheapoutlier = 2 * d.min < d.r,                                          -- the minimum is under half the Recent Price
        farbelow = d.l < 5 and d.tiers[2] ~= nil and 2 * d.min < d.tiers[2].p }   -- few listings, the lowest under half the second price
end

local function Snap(cx)
    if cx.snapDone then return cx.snap, cx.snapWhy end
    cx.snapDone = true
    local m = cx.m
    local lk = PR.Lookup(m, cx.item)
    if not lk then cx.snapWhy = m.scope == "full" and "unlisted" or "outofscope" return nil, cx.snapWhy end
    local age = PR.Age(m.at, cx.now)
    local s = { lk = lk, at = m.at, age = age, freshness = MK.Freshness(age), complete = m.complete == true, cut = m.cut == true, partial = m.partial or 0,
        scope = m.scope }
    local ie, de = m.items[cx.item], m.dist and m.dist[cx.item]
    local e = Slot(cx)
    local f = e and e.f and e.ie == ie and e.de == de and e.f or nil
    if f then
        stats.snapHits = stats.snapHits + 1
    else
        if e then stats.snapMisses = stats.snapMisses + 1 end
        local d, why = DistOf(m, cx.item)
        cx.d, cx.dwhy, cx.dDone = d, why, true
        f = Facts(d, why)
        if e then e.ie, e.de, e.f = ie, de, f end
    end
    s.hasDist, s.dwhy, s.r, s.single, s.exact = f.has == true, f.dwhy, f.r, f.single, f.exact
    s.spread, s.spreadClass, s.cheapoutlier, s.farbelow = f.spread, f.spreadClass, f.cheapoutlier, f.farbelow
    cx.snap = s
    return s
end

-- the decoded distribution of this call (a new table: nothing in it is shared with the saved data or the cache), or nil and why
local function SnapDist(cx)
    if not cx.dDone then
        cx.d, cx.dwhy = DistOf(cx.m, cx.item)
        cx.dDone = true
    end
    return cx.d, cx.dwhy
end

local function SnapNotes(r, s, mixed)
    if s.scope ~= "full" then Note(r, "recipes") end
    if s.partial > 0 then Note(r, "partial") end
    if s.cut then Note(r, "cut") elseif not s.complete then Note(r, "incomplete") end
    if s.age > PR.OLD_AFTER then Note(r, "old") end
    if s.lk.listings and s.lk.listings < V.THIN_LISTINGS then Note(r, "thin") end
    if s.hasDist then
        if s.single then Note(r, "single") end
        if s.cheapoutlier then Note(r, "cheapoutlier") end
        if s.farbelow then Note(r, "farbelow") end
    end
    if mixed then Note(r, "mixedvariants") end
end

---------------------------------------------------------------------------
-- Pure arithmetic (tested on its own)
---------------------------------------------------------------------------
-- The weighted LOWER median: the smallest value whose cumulative weight reaches half the total (2 x cumulative >= total, whole numbers).
-- vs, ws: parallel lists of n values and whole positive weights; SORTED IN PLACE. Returns value, total weight.
function V.WeightedMedian(vs, ws, n)
    for i = 2, n do
        local v, w, j = vs[i], ws[i], i - 1
        while j >= 1 and vs[j] > v do vs[j + 1], ws[j + 1] = vs[j], ws[j] j = j - 1 end
        vs[j + 1], ws[j + 1] = v, w
    end
    local total = 0
    for i = 1, n do total = total + ws[i] end
    local cum = 0
    for i = 1, n do
        cum = cum + ws[i]
        if 2 * cum >= total then return vs[i], total end
    end
    return nil, total
end

-- the Market Value weight of a day `age` days old: 4 (0 to 2), 2 (3 to 6), 1 (7 to 13)
function V.MarketWeight(age) if age <= 2 then return 4 end if age <= 6 then return 2 end return 1 end

-- How a bucket of days a .. e meets the window from .. to: overlap (days of the bucket inside), used (counted: all of it inside, or at least half
-- of its days inside; a bucket cannot be split, so a window edge is rounded to the nearer bucket boundary and the result says so)
function V.BucketUse(a, e, from, to)
    local lo, hi = a > from and a or from, e < to and e or to
    local ov = hi - lo + 1
    if ov <= 0 then return 0, false end
    local span = e - a + 1
    return ov, ov == span or 2 * ov >= span
end

-- the change from a to b in whole tenths of a percent of a, a tie away from zero (exact: a and b are whole numbers below 10^13)
function V.PercentTenths(a, b)
    local num, den = 1000 * math.abs(b - a), a
    local r = (2 * num + den) % (2 * den)
    local tenths = (2 * num + den - r) / (2 * den)
    if tenths == 0 then return 0 end
    return b < a and -tenths or tenths
end

---------------------------------------------------------------------------
-- The history digest: what one item's version-2 history says as of one day (one decode; cached, see below)
---------------------------------------------------------------------------
local VS, WS = {}, {}   -- scratch for the medians (reused; only the first n entries are meaningful)
local EMPTY = {}

local function Compute(days, bks, today)
    days, bks = days or EMPTY, bks or EMPTY
    local g = {}
    -- Market Value: days of ages 0 to 13 with a known closing Recent Price, weighted by age
    local n, listed, newest, oldest, pf = 0, 0, nil, nil, false
    for _, x in ipairs(days) do
        local age = today - x.d
        if age >= 0 and age < V.MV_DAYS then
            listed = listed + 1
            if x.r then
                n = n + 1
                VS[n], WS[n] = x.r, V.MarketWeight(age)
                if not newest or x.d > newest then newest = x.d end
                if not oldest or x.d < oldest then oldest = x.d end
                if x.pf then pf = true end
            end
        end
    end
    local hidden = false   -- part of the 14 days is only in buckets (asked about a day before the newest scan)
    for _, b in ipairs(bks) do
        if V.BucketUse(b.k * b.s, b.k * b.s + b.s - 1, today - V.MV_DAYS + 1, today) > 0 then hidden = true end
    end
    g.mvListed, g.mvHidden = listed, hidden
    if n > 0 then
        local v, w = V.WeightedMedian(VS, WS, n)
        g.mv = { v = v, n = n, weight = w, newest = newest, oldest = oldest, partial = pf }
    end

    -- Historical Value: exact days of the last 60 with a Recent Price (weight 1), and buckets inside the window by their mean weighted by nr
    local from = today - V.HV_DAYS + 1
    n = 0
    local dayCount, bucketDays, edges, agg = 0, 0, nil, false
    newest, oldest, pf = nil, nil, false
    for _, x in ipairs(days) do
        if x.r and x.d >= from and x.d <= today then
            n = n + 1
            VS[n], WS[n] = x.r, 1
            dayCount = dayCount + 1
            if not newest or x.d > newest then newest = x.d end
            if not oldest or x.d < oldest then oldest = x.d end
            if x.pf then pf = true end
        end
    end
    for _, b in ipairs(bks) do
        local a, e = b.k * b.s, b.k * b.s + b.s - 1
        local ov, used = V.BucketUse(a, e, from, today)
        if ov > 0 and ov < b.s then
            edges = edges or {}
            edges[#edges + 1] = { from = a, to = e, inside = ov, used = used and b.nr > 0, days = b.nr }
        end
        if used and b.nr > 0 then
            n = n + 1
            VS[n], WS[n] = b.rm, b.nr
            bucketDays, agg = bucketDays + b.nr, true
            if not newest or e > newest then newest = e end
            if not oldest or a < oldest then oldest = a end
            if b.pf then pf = true end
        end
    end
    local hvDays = dayCount + bucketDays
    g.hvDays = hvDays
    if n > 0 and hvDays >= V.HV_MIN_DAYS then
        local v = V.WeightedMedian(VS, WS, n)
        g.hv = { v = v, n = hvDays, daily = dayCount, bucketDays = bucketDays, aggregate = agg, edges = edges, newest = newest, oldest = oldest, partial = pf }
    elseif edges then
        g.hvEdges = edges
    end

    -- Data Quality's observed days: days the item was listed in the last 30 (daily points, and buckets wholly inside the window)
    local qfrom, obs = today - V.QUALITY_DAYS + 1, 0
    for _, x in ipairs(days) do if x.d >= qfrom and x.d <= today then obs = obs + 1 end end
    for _, b in ipairs(bks) do if b.k * b.s >= qfrom and b.k * b.s + b.s - 1 <= today then obs = obs + b.n end end
    g.obs30 = obs

    -- Supply: the lower median of the closing items of the listed days of the last 14
    n = 0
    for _, x in ipairs(days) do
        local age = today - x.d
        if age >= 0 and age < V.MV_DAYS then n = n + 1 VS[n], WS[n] = x.t, 1 end
    end
    if n > 0 then g.sup = { v = (V.WeightedMedian(VS, WS, n)), n = n } end
    return g
end

-- the history digest of the call (cached: see "The cache" above)
local function Dig(cx)
    if cx.dig then return cx.dig end
    local m, item, today = cx.m, cx.item, cx.today
    if m.scope ~= "full" then cx.dig = { scope = true } return cx.dig end
    if m.h2info and m.h2info.state == "future" then cx.dig = { future = true } return cx.dig end
    local h2s, c2s = m.h2 and m.h2[item], m.c2 and m.c2[item]
    if h2s == nil and c2s == nil then cx.dig = { none = true } return cx.dig end
    local e = Slot(cx)
    if e and e.g and e.h2s == h2s and e.c2s == c2s and e.today == today then
        stats.hits = stats.hits + 1
        cx.dig = e.g
        return e.g
    end
    if e then stats.misses = stats.misses + 1 end
    local _, days, bks, bad = H2.Read(h2s, c2s)
    local g = Compute(days, bks, today)
    g.bad, g.has = bad, days ~= nil or bks ~= nil
    if e then e.h2s, e.c2s, e.today, e.g = h2s, c2s, today, g end
    cx.dig = g
    return g
end

-- why a history value is unavailable before looking at the window: "outofscope", "format", "nohistory", "malformed", or nil
local function HistoryWhy(g)
    if g.scope then return "outofscope" end
    if g.future then return "format" end
    if g.none then return "nohistory" end
    if not g.has then return "malformed" end
    return nil
end

---------------------------------------------------------------------------
-- Data Quality, policy 1 (owner decision D7)
---------------------------------------------------------------------------
--   good     snapshot complete, age <= 24 h, >= 5 listings, spread not wide, >= 7 observed days in the last 30, no mixed variants, no farbelow
--   fair     age <= 3 days, >= 3 listings, not cut, no mixed variants
--   limited  anything else WITH a price (a thin, genuine market is limited, never none)
--   none     no price (nomarket, variant, unlisted, outofscope)
-- reasons: every requirement of `good` that is not met, as { code, text, blocks = "good" or "fair" (it also keeps the data from fair) }.
local RANK = { none = 0, limited = 1, fair = 2, good = 3 }
V.QUALITY_RANK = RANK

local function Ago(age)
    local d = floor(age / 86400)
    if d >= 1 then return d == 1 and "1 day ago" or (d .. " days ago") end
    local h = floor(age / 3600)
    return h <= 1 and "1 hour ago" or (h .. " hours ago")
end

local function QualityOf(cx)
    if cx.quality then return cx.quality end
    local s, why = Snap(cx)
    local q = { role = "valuation", kind = "quality", item = cx.item, market = cx.m.key, label = PR.Label(cx.m), policy = MK.QUALITY_POLICY,
        basis = MK.VALUE_BASIS.quality, reasons = {}, facts = {} }
    if not s then
        q.level = "none"
        q.reasons[1] = { code = why, text = MK.VALUE_REASONS[why], blocks = "limited" }
        cx.quality = q
        return q
    end
    local g = Dig(cx)
    local mixed = Mixed(cx)
    local f = q.facts
    f.complete, f.cut, f.age, f.listings, f.items, f.partial = s.complete, s.cut, s.age, s.lk.listings, s.lk.total, s.partial
    f.spread, f.spreadClass, f.distribution = s.spread, s.spreadClass, s.hasDist or s.dwhy
    f.observedDays, f.mixedvariants, f.farbelow, f.cheapoutlier, f.single = g.obs30 or 0, mixed, s.farbelow == true, s.cheapoutlier == true, s.single == true
    f.recipes = s.scope ~= "full"
    q.at, q.age, q.freshness, q.n = s.at, s.age, s.freshness, f.observedDays

    local good, fair = true, true
    local function Fail(code, text, alsoFair)
        q.reasons[#q.reasons + 1] = { code = code, text = text, blocks = alsoFair and "fair" or "good" }
        good = false
        if alsoFair then fair = false end
    end
    if f.recipes then Fail("recipes", "From an older scan that kept only the items of known recipes.", true) end
    if s.cut then Fail("cut", "Some listings may be missing from the newest scan.", true)
    elseif not s.complete then Fail("incomplete", "Current market data is incomplete.", false) end
    if s.age > V.FAIR_AGE then Fail("age", "Last scanned " .. Ago(s.age) .. ".", true)
    elseif s.age > V.GOOD_AGE then Fail("age", "Last scanned " .. Ago(s.age) .. ".", false) end
    local l = s.lk.listings or 0
    if l < V.GOOD_LISTINGS then Fail("listings", l == 1 and "Only 1 listing." or ("Only " .. l .. " listings."), l < V.FAIR_LISTINGS) end
    if not s.hasDist then Fail("nodistribution", "How the prices are spread is not known for this scan.", false)
    elseif s.spreadClass == "wide" then Fail("spread", "Prices vary widely.", false) end
    if f.observedDays < V.GOOD_DAYS then
        Fail("days", f.observedDays == 0 and "No observed days in the last 30." or (f.observedDays == 1 and "Only 1 observed day in the last 30." or
            ("Only " .. f.observedDays .. " observed days in the last 30.")), false)
    end
    if mixed then Fail("mixedvariants", "Several economically distinct item variants may be mixed.", true) end
    if s.farbelow then Fail("farbelow", "One unusually cheap listing differs sharply from the others.", false) end
    q.level = good and "good" or (fair and "fair" or "limited")
    cx.quality = q
    return q
end

local function Codes(q)
    local out = {}
    for i, r in ipairs(q.reasons) do out[i] = r.code end
    return out
end

-- Data Quality of one item: { role, kind = "quality", level, reasons = { { code, text, blocks } }, facts, policy, at, age, freshness, n (observed
-- days in 30), market, label, basis }. Level "none" (with the reason) when there is no price; nil only for baditem / badsource.
function MK.Quality(item, opt)
    local cx, why = Context(item, opt)
    if not cx then
        if why == "baditem" or why == "badsource" then return nil, why end
        return { role = "valuation", kind = "quality", level = "none", policy = MK.QUALITY_POLICY, basis = MK.VALUE_BASIS.quality,
            reasons = { { code = why, text = MK.VALUE_REASONS[why], blocks = "limited" } }, facts = {} }
    end
    return QualityOf(cx)
end

-- the quality of a value from history: the item's quality, never below "limited" (the history value IS a usable price, even when the item is
-- not listed now), and at most `cap`
local function HistoryQuality(cx, cap)
    local lv = QualityOf(cx).level
    if RANK[lv] < RANK.limited then lv = "limited" end
    if cap and RANK[lv] > RANK[cap] then lv = cap end
    return lv
end

---------------------------------------------------------------------------
-- Market.Value(item, kind, opt): one valuation
---------------------------------------------------------------------------
-- kind "min"         Minimum Buyout (Prices.Lookup: exactly Market.Price's figure)
--      "recent"      Recent Price (A3's band mean from the distribution; a one-price item's is its minimum; a multi-price item without a usable
--                    distribution is nil and the reason: noevidence / missing / malformed, NEVER the minimum)
--      "market"      Market Value (14 days, recency-weighted median of daily closing Recent Prices)
--      "historical"  Historical Value (60 days, median; weekly buckets by their mean weighted by nr)
-- Returns { role = "valuation", kind, value (whole copper), basis, provenance = "local", evidence ("snapshot" | "daily" | "daily+buckets"), n,
--   aggregate, approximate, complete, quality (level), qualityReasons (codes), notes, market, label, and
--   snapshot kinds: at, age, freshness, window = "snapshot", listings, items, single, rsrc (recent: "dist" | "single")
--   history kinds:  window = { days, from, to }, coverage = { from, to, ageDays } (the observed days used), weight (market), daily / bucketDays /
--                   edges (historical) }
-- or nil, reason, detail (detail: { listed, n } for stale / norecent / insufficient).
local function SnapshotValue(cx, kind)
    local s, why = Snap(cx)
    if not s then return nil, why end
    if kind == "recent" and not s.hasDist then return nil, s.dwhy end
    local q = QualityOf(cx)
    local r = Base("valuation", kind, cx)
    r.value = kind == "min" and s.lk.price or s.r
    r.evidence, r.window, r.n = "snapshot", "snapshot", 1
    r.at, r.age, r.freshness = s.at, s.age, s.freshness
    r.complete, r.cut, r.partial = s.complete, s.cut, s.partial
    r.listings, r.items = s.lk.listings, s.lk.total
    r.aggregate, r.approximate = false, false
    if kind == "recent" then
        r.single, r.rsrc = s.single, s.single and "single" or "dist"
        if not s.exact then r.approximate = true Note(r, "arithmetic") end
    end
    r.quality, r.qualityReasons = q.level, Codes(q)
    SnapNotes(r, s, Mixed(cx))
    return r
end

local function HistoryValue(cx, kind)
    local g = Dig(cx)
    local hw = HistoryWhy(g)
    if hw then return nil, hw end
    local today = cx.today
    local r
    if kind == "market" then
        local v = g.mv
        if not v then return nil, g.mvListed > 0 and "norecent" or "stale", { listed = g.mvListed, n = 0 } end
        r = Base("valuation", "market", cx)
        r.value, r.n, r.weight = v.v, v.n, v.weight
        r.window = { days = V.MV_DAYS, from = today - V.MV_DAYS + 1, to = today }
        r.coverage = { from = v.oldest, to = v.newest, ageDays = today - v.newest }
        r.evidence, r.aggregate, r.approximate, r.complete = "daily", false, false, not v.partial
        r.quality = HistoryQuality(cx, v.n == 1 and "limited" or nil)
        if v.n == 1 then Note(r, "singleday") elseif 2 * v.n < V.MV_DAYS then Note(r, "sparse") end
        if g.mvHidden then Note(r, "notretained") end
    else
        local v = g.hv
        if not v then return nil, "insufficient", { n = g.hvDays or 0 } end
        r = Base("valuation", "historical", cx)
        r.value, r.n, r.daily, r.bucketDays = v.v, v.n, v.daily, v.bucketDays
        r.window = { days = V.HV_DAYS, from = today - V.HV_DAYS + 1, to = today }
        r.coverage = { from = v.oldest, to = v.newest, ageDays = today - v.newest }
        r.evidence = v.aggregate and "daily+buckets" or "daily"
        r.aggregate, r.approximate, r.complete = v.aggregate, v.aggregate, not v.partial
        if v.edges then
            r.edges = {}
            for i, e in ipairs(v.edges) do r.edges[i] = { from = e.from, to = e.to, inside = e.inside, used = e.used, days = e.days } end
            Note(r, "edge")
        end
        if v.aggregate then Note(r, "aggregate") end
        r.quality = HistoryQuality(cx, nil)
        if 2 * v.n < V.HV_DAYS then Note(r, "sparse") end
    end
    if r.complete == false then Note(r, "partial") end
    if g.bad then Note(r, "damaged") end
    if Mixed(cx) then Note(r, "mixedvariants") end
    r.qualityReasons = Codes(QualityOf(cx))
    return r
end

function MK.Value(item, kind, opt)
    if not MK.VALUE_KINDS[kind] then return nil, "badkind" end
    local cx, why = Context(item, opt)
    if not cx then return nil, why end
    if kind == "min" or kind == "recent" then return SnapshotValue(cx, kind) end
    return HistoryValue(cx, kind)
end

---------------------------------------------------------------------------
-- Market.Distribution(item, opt): the newest scan's distribution, checked (Prices.Distribution) and freshly decoded for this call
---------------------------------------------------------------------------
-- { role = "valuation", kind = "distribution", min, recent, anchor, q25, q50, q75, hi, next, near (items at or below 1.10 x recent), items,
--   listings, tiers = { { p, q, l, m } x 1..6, cheapest first; m the largest single listing, nil when not known }, tail = { items, listings }
--   (beyond the sixth price, counted but not priced), spread ((q75 - q25) / q50), spreadClass, flags = { cheapoutlier, farbelow }, single, exact,
--   at, age, freshness, complete, cut, partial, quality, notes, ... } or nil and unlisted / outofscope / noevidence / missing / malformed
function MK.Distribution(item, opt)
    local cx, why = Context(item, opt)
    if not cx then return nil, why end
    local s, swhy = Snap(cx)
    if not s then return nil, swhy end
    local d, dwhy = SnapDist(cx)
    if not d then return nil, dwhy end
    local r = Base("valuation", "distribution", cx)
    r.min, r.recent, r.anchor, r.q25, r.q50, r.q75, r.hi, r.near = d.min, d.r, d.a, d.q25, d.q50, d.q75, d.hi, d.near
    r.items, r.listings, r.tiers = d.t, d.l, d.tiers          -- d is this call's own decode: nothing here is shared with the saved data
    r.next = d.tiers[2] and d.tiers[2].p or nil
    r.tail = { items = d.tq, listings = d.tl }
    r.spread, r.spreadClass = s.spread, s.spreadClass
    r.flags = { cheapoutlier = s.cheapoutlier, farbelow = s.farbelow }
    r.single, r.exact = d.single == true, d.exact ~= false
    r.at, r.age, r.freshness, r.complete, r.cut, r.partial = s.at, s.age, s.freshness, s.complete, s.cut, s.partial
    r.quality = QualityOf(cx).level
    SnapNotes(r, s, Mixed(cx))
    if d.tq > 0 then Note(r, "tail") end
    return r
end

---------------------------------------------------------------------------
-- Market.TrendOf(item, metric, days, opt): one metric, newer half against older half
---------------------------------------------------------------------------
-- metric "recent" (closing Recent Price), "min" (closing Minimum Buyout), "supply" (closing items listed); days 4 to 30 (default 14), counted
-- back from today: the newer half is ages 0 .. floor(days / 2) - 1, the older half the rest. Only exact daily points (version-2 history; the
-- legacy minimum history never). A missing day, an unlisted day or a day without the metric adds nothing (never a zero).
-- { role = "valuation", kind = "trend", metric, days, direction ("rising" | "falling" | "flat" | "insufficient"), older = { median, n, from, to },
--   newer = { ... }, change (copper or items, signed), percent (of the older median, one decimal, a tie away from zero), basis, notes }
-- or nil and baditem / badmetric / baddays / nomarket / variant / outofscope / format / nohistory / malformed.
MK.TREND_METRICS = { recent = "r", min = "p", supply = "t" }

local function TrendCore(cx, metric, days)
    local g = Dig(cx)
    local hw = HistoryWhy(g)
    if hw then return nil, hw end
    local m = cx.m
    local _, list, bks = H2.Read(m.h2 and m.h2[cx.item], m.c2 and m.c2[cx.item])
    local field, today, half = MK.TREND_METRICS[metric], cx.today, floor(days / 2)
    local r = Base("valuation", "trend", cx)
    r.metric, r.days = metric, days
    local sides = { { n = 0, vals = {}, from = today - days + 1, to = today - half }, { n = 0, vals = {}, from = today - half + 1, to = today } }
    for _, x in ipairs(list or EMPTY) do
        local v, age = x[field], today - x.d
        if v and age >= 0 and age < days then
            local sd = age < half and sides[2] or sides[1]
            sd.n = sd.n + 1
            sd.vals[sd.n] = v
        end
    end
    for _, b in ipairs(bks or EMPTY) do
        if V.BucketUse(b.k * b.s, b.k * b.s + b.s - 1, today - days + 1, today) > 0 then Note(r, "notretained") break end
    end
    local med = {}
    for i, sd in ipairs(sides) do
        local ws = {}
        for k = 1, sd.n do ws[k] = 1 end
        med[i] = sd.n > 0 and (V.WeightedMedian(sd.vals, ws, sd.n)) or nil
    end
    r.older = { median = med[1], n = sides[1].n, from = sides[1].from, to = sides[1].to }
    r.newer = { median = med[2], n = sides[2].n, from = sides[2].from, to = sides[2].to }
    if sides[1].n < 2 or sides[2].n < 2 then
        r.direction = "insufficient"
        return r
    end
    local a, b = med[1], med[2]
    r.change = b - a
    r.percent = V.PercentTenths(a, b) / 10
    if 100 * math.abs(b - a) < V.FLAT_PERCENT * a then r.direction = "flat"
    elseif b > a then r.direction = "rising" else r.direction = "falling" end
    return r
end

function MK.TrendOf(item, metric, days, opt)
    if not MK.TREND_METRICS[metric] then return nil, "badmetric" end
    local d = days == nil and V.TREND_DAYS or Int(days, 4, V.TREND_MAX_DAYS)
    if not d then return nil, "baddays" end
    local cx, why = Context(item, opt)
    if not cx then return nil, why end
    return TrendCore(cx, metric, d)
end

---------------------------------------------------------------------------
-- Market.Supply(item, opt): what is listed now, and what was listed lately
---------------------------------------------------------------------------
-- { role = "valuation", kind = "supply", items, listings, atMin (items at the minimum price: the first tier; without a distribution, the
--   minimum entry's items at exactly the cheapest price), atMinListings, nearRecent (items at or below 1.10 x Recent Price), tiers = { { p, q, l } },
--   tail = { items, listings }, history = { median (closing items, lower median), n, days, from, to } or nil, trend (TrendOf supply, 14 days) or
--   nil, at, age, freshness, complete, quality, notes } or nil and a reason (unlisted: nothing to count; the history alone is in TrendOf / Range).
-- Supply is what was LISTED: never demand, sales, sell-through or what will still be there.
function MK.Supply(item, opt)
    local cx, why = Context(item, opt)
    if not cx then return nil, why end
    local s, swhy = Snap(cx)
    if not s then return nil, swhy end
    local r = Base("valuation", "supply", cx)
    r.items, r.listings = s.lk.total, s.lk.listings
    local d = SnapDist(cx)
    if d then
        r.atMin, r.atMinListings, r.nearRecent = d.tiers[1].q, d.tiers[1].l, d.near
        r.tiers = {}
        for k, t in ipairs(d.tiers) do r.tiers[k] = { p = t.p, q = t.q, l = t.l } end
        r.tail = { items = d.tq, listings = d.tl }
    else
        r.atMin = s.lk.qty
        Note(r, s.dwhy)
    end
    r.at, r.age, r.freshness, r.complete = s.at, s.age, s.freshness, s.complete
    local g = Dig(cx)
    if g.sup then r.history = { median = g.sup.v, n = g.sup.n, days = V.MV_DAYS, from = cx.today - V.MV_DAYS + 1, to = cx.today } end
    if not HistoryWhy(g) then r.trend = TrendCore(cx, "supply", V.TREND_DAYS) end
    r.quality = QualityOf(cx).level
    SnapNotes(r, s, Mixed(cx))
    return r
end

---------------------------------------------------------------------------
-- Market.Posture(item, opt): Recent Price against Historical Value (owner decision D8)
---------------------------------------------------------------------------
-- cheap (Recent below 85% of Historical), normal (85% to 115%), expensive (above 115%), compared in whole numbers. Needs: a Recent Price, at
-- least 3 listings, Data Quality at least fair, no farbelow (a thin market whose cheapest listing is far below the rest is never called a
-- bargain), and a Historical Value from at least 5 observed days. Otherwise posture "unknown" and `why` (the first unmet requirement; `reasons`
-- all of them). The minimum is never the compared value.
-- { role = "valuation", kind = "posture", posture, why, reasons, ratio (Recent / Historical), percent (tenths of a percent of Historical, the
--   difference), current, reference, n (observed days behind the reference), quality, notes, basis } or nil and baditem / badsource.
function MK.Posture(item, opt)
    local cx, why = Context(item, opt)
    if not cx then
        if why == "baditem" or why == "badsource" then return nil, why end
        return { role = "valuation", kind = "posture", item = Int(item, 1, W.MAX_ID), posture = "unknown", why = why, reasons = { why }, basis = MK.VALUE_BASIS.posture, notes = {} }
    end
    local r = Base("valuation", "posture", cx)
    r.reasons = {}
    local function Miss(code) r.reasons[#r.reasons + 1] = code end
    local cur, cwhy = SnapshotValue(cx, "recent")
    local q = QualityOf(cx)
    r.quality = q.level
    if not cur then Miss(cwhy) else r.current = cur.value end
    local s = Snap(cx)
    if s and (s.lk.listings or 0) < V.POSTURE_LISTINGS then Miss("thin") end
    if RANK[q.level] < RANK.fair then Miss("quality") end
    if s and s.farbelow then Miss("farbelow") end
    local hist, hwhy = HistoryValue(cx, "historical")
    if not hist then Miss(hwhy)
    else
        r.reference, r.n = hist.value, hist.n
        if hist.n < V.POSTURE_DAYS then Miss("insufficient") end
        if hist.aggregate then Note(r, "aggregate") end
    end
    if #r.reasons > 0 then
        r.posture, r.why = "unknown", r.reasons[1]
        return r
    end
    local c, h = r.current, r.reference
    r.ratio = c / h
    r.percent = V.PercentTenths(h, c) / 10
    if 100 * c < V.POSTURE_LOW * h then r.posture = "cheap"
    elseif 100 * c > V.POSTURE_HIGH * h then r.posture = "expensive"
    else r.posture = "normal" end
    if s.cheapoutlier then Note(r, "cheapoutlier") end
    return r
end

---------------------------------------------------------------------------
-- Market.Range(item, days, opt): long-term lows and highs (days 1 to 120, default 120)
---------------------------------------------------------------------------
-- From the daily points (their day lows and highs; a condensed day counts its closing values), the buckets that meet the window (V.BucketUse: a
-- bucket whose days are mostly outside is left out, every edge bucket is listed in `edges`), and, for the minimum ONLY, the frozen legacy history
-- before version-2 recording began (opt.sources: default both; "local" alone leaves it out). Recent Price is recorded since `recordedFrom`.
-- { role = "valuation", kind = "range", days, window = { from, to }, min = { lo, hi, n, legacy (days from the legacy history) },
--   recent = { lo, hi, n (days with a known closing Recent Price) }, supply = { lo, hi, n }, coverage = { from, to }, aggregate (a bucket
--   contributed: its days are not individually known), edges, recordedFrom, notes } or nil and nohistory / nodata / ... .
function MK.Range(item, days, opt)
    local d = days == nil and V.RANGE_DAYS or Int(days, 1, V.RANGE_DAYS)
    if not d then return nil, "baddays" end
    -- sources: default both; a list names the ones to read ("local", "legacy"); a list with neither is refused
    local useLocal, useLegacy = true, true
    if type(opt) == "table" and opt.sources ~= nil then
        useLocal, useLegacy = HasSource(opt.sources, "local"), HasSource(opt.sources, "legacy")
        if not (useLocal or useLegacy) then return nil, "badsource" end
        local o = {}
        for k, v in pairs(opt) do o[k] = v end
        o.sources = nil
        opt = o
    end
    local cx, why = Context(item, opt)
    if not cx then return nil, why end
    local m = cx.m
    if m.scope ~= "full" then return nil, "outofscope" end
    local future = m.h2info and m.h2info.state == "future"
    if future then useLocal = false end
    local today = cx.today
    local from, to = today - d + 1, today
    local r = Base("valuation", "range", cx)
    r.days, r.window, r.recordedFrom = d, { from = from, to = to }, m.h2info and m.h2info.from or nil
    local mn, rc, sp = { n = 0, legacy = 0 }, { n = 0 }, { n = 0 }
    local cfrom, cto, any = nil, nil, false
    local function Seen(a, b)
        any = true
        if not cfrom or a < cfrom then cfrom = a end
        if not cto or b > cto then cto = b end
    end
    local function Lo(t, v) if v and (not t.lo or v < t.lo) then t.lo = v end end
    local function Hi(t, v) if v and (not t.hi or v > t.hi) then t.hi = v end end
    local hasHistory = false
    if useLocal then
        local _, list, bks, bad = H2.Read(m.h2 and m.h2[cx.item], m.c2 and m.c2[cx.item])
        if bad then Note(r, "damaged") end
        hasHistory = list ~= nil or bks ~= nil
        for _, x in ipairs(list or EMPTY) do
            if x.d >= from and x.d <= to then
                Seen(x.d, x.d)
                mn.n, sp.n = mn.n + 1, sp.n + 1
                Lo(mn, x.plo or x.p) Hi(mn, x.phi or x.p)
                Lo(sp, x.tlo or x.t) Hi(sp, x.thi or x.t)
                if x.r then rc.n = rc.n + 1 end
                Lo(rc, x.rlo or x.r) Hi(rc, x.rhi or x.r)
                if x.cf then r.condensed = true end
            end
        end
        for _, b in ipairs(bks or EMPTY) do
            local a, e = b.k * b.s, b.k * b.s + b.s - 1
            local ov, used = V.BucketUse(a, e, from, to)
            if ov > 0 and ov < b.s then
                r.edges = r.edges or {}
                r.edges[#r.edges + 1] = { from = a, to = e, inside = ov, used = used }
            end
            if used then
                Seen(a, e)
                r.aggregate = true
                mn.n, sp.n, rc.n = mn.n + b.n, sp.n + b.n, rc.n + b.nr
                Lo(mn, b.plo) Hi(mn, b.phi)
                Lo(rc, b.rlo) Hi(rc, b.rhi)
                if b.tlo then Lo(sp, b.tlo) Hi(sp, b.thi) else r.supplyRangeDropped = true end
                if b.cf then r.condensed = true end
            end
        end
    end
    if useLegacy then
        local H = W.History
        local lp, lb = H.Decode(m.hist and m.hist[cx.item])
        if lp then
            hasHistory = true
            local limit = (r.recordedFrom or (today + 1)) - 1      -- legacy days only before version-2 recording began: never counted twice
            local firstExact = lp[1] or (limit + 1)
            for i = 1, #lb, 5 do
                local a = lb[i] * H.BUCKET_DAYS
                local e = math.min(a + H.BUCKET_DAYS - 1, firstExact - 1, limit)
                if e >= a then
                    local ov, used = V.BucketUse(a, e, from, to)
                    if ov > 0 and ov < e - a + 1 then
                        r.edges = r.edges or {}
                        r.edges[#r.edges + 1] = { from = a, to = e, inside = ov, used = used, legacy = true }
                    end
                    if used then
                        Seen(a, e)
                        r.aggregate = true
                        mn.n, mn.legacy = mn.n + lb[i + 4], mn.legacy + lb[i + 4]
                        Lo(mn, lb[i + 1]) Hi(mn, lb[i + 2])
                    end
                end
            end
            for i = 1, #lp, 2 do
                local day = lp[i]
                if day <= limit and day >= from and day <= to then
                    Seen(day, day)
                    mn.n, mn.legacy = mn.n + 1, mn.legacy + 1
                    Lo(mn, lp[i + 1]) Hi(mn, lp[i + 1])
                end
            end
        end
    end
    if not hasHistory then return nil, future and "format" or "nohistory" end
    if not any then return nil, "nodata" end
    r.min, r.recent, r.supply = mn, rc, sp
    r.coverage = { from = cfrom, to = cto }
    r.provenance = mn.legacy > 0 and "local+legacy" or "local"
    if mn.legacy > 0 then Note(r, "legacy") end
    if r.aggregate then Note(r, "aggregate") end
    if r.edges then Note(r, "edge") end
    if rc.lo == nil then Note(r, "norecent") end
    if Mixed(cx) then Note(r, "mixedvariants") end
    return r
end

---------------------------------------------------------------------------
-- Market.Competition(item, qty, opt): the listings a seller of `qty` would compete with now (section 4B)
---------------------------------------------------------------------------
-- The six kept tiers with running totals; the cheapest price; the lowest COMPETING price: the cheapest tier at or above half the Recent Price's
-- anchor (2 x price >= anchor), so a bait listing under the band filter is shown (`below`) but not taken as the competition; when every kept tier
-- is below that line the competing price is beyond the six kept prices (`competing` nil, `beyond` true). ahead: items and listings at or below the
-- competing price. opt.price: items listed at or below that price (`atLeast` when the tail may hold more). qty (optional, 1 or more): depth =
-- { qty, ahead, coveredBy (the tier whose running total first reaches qty, nil beyond the six) }. Never a suggested price.
-- { role = "competition", kind = "competition", cheapest, competing, competingTier, anchor, beyond, tiers = { { p, q, l, m, cumItems, cumListings,
--   below } }, below = { items, listings } (under the competing line), ahead, aheadListings, atPrice, depth, tail, total = { items, listings },
--   at, age, freshness, complete, quality, qualityReasons, notes } or nil and badqty / unlisted / noevidence / missing / malformed / ...
function MK.Competition(item, qty, opt)
    local n
    if qty ~= nil then
        n = Int(qty, 1, W.MAX_ID)
        if not n then return nil, "badqty" end
    end
    local cx, why = Context(item, opt)
    if not cx then return nil, why end
    local s, swhy = Snap(cx)
    if not s then return nil, swhy end
    local d, dwhy = SnapDist(cx)
    if not d then return nil, dwhy end
    local r = Base("competition", "competition", cx)
    r.provenance = "local"
    r.cheapest, r.anchor = d.tiers[1].p, d.a
    r.tiers, r.below = {}, { items = 0, listings = 0 }
    local cq, cl = 0, 0
    for k, t in ipairs(d.tiers) do
        cq, cl = cq + t.q, cl + t.l
        local under = 2 * t.p < d.a
        r.tiers[k] = { p = t.p, q = t.q, l = t.l, m = t.m, cumItems = cq, cumListings = cl, below = under }
        if under then r.below.items, r.below.listings = r.below.items + t.q, r.below.listings + t.l
        elseif not r.competingTier then r.competingTier, r.competing, r.ahead, r.aheadListings = k, t.p, cq, cl end
    end
    if not r.competingTier then r.beyond = true Note(r, "beyondtiers") end
    if r.below.items > 0 then Note(r, "bait") end
    r.tail, r.total = { items = d.tq, listings = d.tl }, { items = d.t, listings = d.l }
    local price = cx.opt and Int(cx.opt.price, 1, PR.MAX_COPPER) or nil
    if price then
        local at, last = 0, d.tiers[#d.tiers]
        for _, t in ipairs(d.tiers) do if t.p <= price then at = at + t.q end end
        r.atPrice = { price = price, items = at, atLeast = d.tq > 0 and price > last.p or nil }
    end
    if n then
        local cover
        for k, t in ipairs(r.tiers) do if t.cumItems >= n then cover = k break end end
        r.depth = { qty = n, ahead = r.ahead, coveredBy = cover, beyond = cover == nil and d.tq > 0 or nil }
    end
    r.at, r.age, r.freshness, r.complete, r.cut, r.partial = s.at, s.age, s.freshness, s.complete, s.cut, s.partial
    local q = QualityOf(cx)
    r.quality, r.qualityReasons = q.level, Codes(q)
    SnapNotes(r, s, Mixed(cx))
    if d.tq > 0 then Note(r, "tail") end
    return r
end

---------------------------------------------------------------------------
-- Market.Cost(item, qty, opt): what buying qty would have cost at the newest scan's listings (section 4F). ALWAYS a table (like Market.Quote).
---------------------------------------------------------------------------
-- Walks the six kept tiers cheapest first. low: buying exactly qty items (the cheapest qty items listed). high: buying WHOLE listings, cheapest
-- tier first: the last tier used may be over-bought by up to its largest listing minus one item (never more than the tier holds); when the tier's
-- items are its listings times its largest listing, every listing holds that many and the number needed is exact. Every earlier tier is bought
-- whole either way. Whether part of a stack can be bought in Forever is not known (section 15), so both ends are given:
--   state "exact"     low = high: the walk ends on a tier boundary, or the last tier's listings hold one item each
--   state "range"     low < high (cost nil): the whole-listing over-buy
--   state "estimate"  more than the six tiers hold: low = AT LEAST (each further item costs more than the sixth price), high = at most (the highest
--                     listed price, whole listings of the tail); cost nil; a lower bound is never a total
--   state "few"       fewer items listed in all than qty (available says how many); cost nil
--   state "none"      why: badqty / baditem / nomarket / variant / unlisted / outofscope / noevidence / missing / malformed
-- { role = "purchase", kind = "cost", state, qty, cost (exact only), low, high, unit (low / qty, copper, rounded half up), used = { { p, q } } (the
--   exact-quantity walk), last = { tier, price, need, items, listings, largest, overbuy }, available, at, age, freshness, complete, quality,
--   approximate (a total beyond 2^53 copper: doubles, within rounding), notes, basis }
function MK.Cost(item, qty, opt)
    local n = Int(qty, 1, W.MAX_ID)
    local function None(why, cx)
        return { role = "purchase", kind = "cost", state = "none", why = why, qty = n, item = cx and cx.item or Int(item, 1, W.MAX_ID),
            market = cx and cx.m.key or nil, basis = MK.VALUE_BASIS.cost, notes = {} }
    end
    if not n then return None("badqty") end
    local cx, why = Context(item, opt)
    if not cx then return None(why) end
    local s, swhy = Snap(cx)
    if not s then return None(swhy, cx) end
    local d, dwhy = SnapDist(cx)
    if not d then return None(dwhy, cx) end
    local r = Base("purchase", "cost", cx)
    r.qty, r.available = n, d.t
    r.at, r.age, r.freshness, r.complete, r.cut, r.partial = s.at, s.age, s.freshness, s.complete, s.cut, s.partial
    r.quality = QualityOf(cx).level
    SnapNotes(r, s, Mixed(cx))
    if d.t < n then
        r.state = "few"
        Note(r, "few")
        return r
    end
    local rem, low, base, used = n, 0, 0, {}
    for k, t in ipairs(d.tiers) do
        if rem <= t.q then
            low = base + rem * t.p
            local largest = t.m or (t.q - t.l + 1)              -- the largest listing is at most what the other listings leave
            local whole
            if largest * t.l == t.q then
                whole = largest * floor((rem + largest - 1) / largest)   -- every listing holds `largest` items: exactly this many listings
            else
                whole = rem + largest - 1
                if whole > t.q then whole = t.q end
            end
            r.high = base + whole * t.p
            used[#used + 1] = { p = t.p, q = rem }
            r.last = { tier = k, price = t.p, need = rem, items = t.q, listings = t.l, largest = largest, overbuy = whole - rem }
            rem = 0
            break
        end
        used[#used + 1] = { p = t.p, q = t.q }
        base = base + t.q * t.p
        rem = rem - t.q
    end
    r.used = used
    if rem > 0 then
        -- beyond the six kept prices: the tail holds rem or more items, each priced above the sixth price and at most hi
        local p6 = d.tiers[#d.tiers].p
        low = base + rem * (p6 + 1)
        local whole = rem + (d.tq - d.tl)                       -- whole listings: at most the tail's largest listing minus one over
        if whole > d.tq then whole = d.tq end
        r.high = base + whole * d.hi
        r.state = "estimate"
        Note(r, "beyondtiers")
    elseif r.high == low then
        r.state, r.cost = "exact", low
    else
        r.state = "range"
        Note(r, "wholeauction")
    end
    r.low = low
    r.unit = floor((2 * low + n) / (2 * n))
    if r.high >= TWO53 then r.approximate = true Note(r, "arithmetic") end
    return r
end
