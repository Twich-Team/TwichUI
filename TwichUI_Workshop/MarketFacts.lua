-- TwichUI Workshop: market facts for display (A7; pure: no frames, no game calls except through W.Market)
-- ONE place that asks Market.Value / Quality / Supply / Competition about one item and words the answers, for the Opportunities details and
-- the item tooltip, so no view calculates or phrases a market figure itself and the two cannot disagree.
--
-- WHAT EACH FIGURE MEANS (they are never merged; the labels below are the only names the windows use):
--   Lowest listing   Market.Value "min": the cheapest buyout listing in the newest scan. A listing, not a sale.
--   Competing price  Market.Competition: the cheapest tier a seller would really compete with now (a far-below "bait" tier is skipped).
--   Recent price     Market.Value "recent": a representative LISTING price of the newest scan.
--   Market value     Market.Value "market": a 14-day reference of observed listing prices. Not a selling price.
--   Historical value Market.Value "historical": a 60-day reference. Not a selling price, not a promise.
--   Supply           Market.Supply: items and listings in the newest scan. Listed, never demand.
--   Data quality     Market.Quality: good / fair / limited / none, and why.
-- Nothing here reads saved strings (only Market services do), and a missing figure is nil with a reason, never zero.
--
-- THE CACHE: Facts(item) asks about eight services, several of which decode the item's saved entry, so one answer is kept per (market, item):
-- valid for the same market generation (Valuation.Generation: a scan, a compaction or a retention pass changes it, so every successful scan
-- invalidates every answer), the same game minute-bucket (age and freshness are time-dependent), the same variant flag. At most F.CACHE_MAX
-- answers (the oldest half goes when it is full). Selecting a recipe or redrawing the same one reads the cache; nothing runs per frame.

local R = TwichUI
local W = R.Workshop
local PR, MK = W.Prices, W.Market
local floor = math.floor
local F = {}
W.Facts = F

F.CACHE_MAX = 48
F.BUCKET = 300          -- seconds an answer may be reused (ages are shown in minutes and hours)

local young, old, nYoung = {}, {}, 0
local stats = { hits = 0, misses = 0, wipes = 0 }
function F.CacheStats()
    local n = nYoung
    for _ in pairs(old) do n = n + 1 end
    return { entries = n, hits = stats.hits, misses = stats.misses, wipes = stats.wipes, max = F.CACHE_MAX }
end
function F.CacheClear() young, old, nYoung = {}, {}, 0; stats.wipes = stats.wipes + 1 end
function F.CacheSize() return F.CacheStats().entries end

---------------------------------------------------------------------------
-- Asking
---------------------------------------------------------------------------
local function ResolveMarket(opt)
    local m = opt and opt.market
    if m == nil then return MK.Source().market end
    if type(m) == "string" then return PR.Market(m) end
    if type(m) == "table" then
        if type(m.items) == "table" then return m end
        if type(m.market) == "table" and type(m.market.items) == "table" then return m.market end
    end
    return nil
end

-- The saved strings behind one item (a price entry, its distribution, its two histories and the frozen legacy one). Strings compare by identity,
-- so "the same data" is a pointer comparison; an entry changed in place (a test fixture, never a scan: a scan changes the generation too) misses.
local function Srcs(m, item)
    return m.items and m.items[item], m.dist and m.dist[item], m.h2 and m.h2[item], m.c2 and m.c2[item], m.hist and m.hist[item]
end
local function SameSrcs(a, m, item)
    local i, d, h, c, l = Srcs(m, item)
    return a[1] == i and a[2] == d and a[3] == h and a[4] == c and a[5] == l
end

local function Ask(item, m, variant, now)
    local o = { market = m, variant = variant or nil, now = now }
    local f = { item = item, now = now, variant = variant or nil, srcs = m and { Srcs(m, item) } or nil, key = m and m.key or nil, label = m and PR.Label(m) or nil, nomarket = m == nil or nil }
    if not MK.Value then f.unsupported = true return f end   -- Valuation.lua not loaded (the A5 services are absent)
    f.min, f.minWhy = MK.Value(item, "min", o)
    f.recent, f.recentWhy = MK.Value(item, "recent", o)
    f.mval, f.mvalWhy, f.mvalDetail = MK.Value(item, "market", o)
    f.hist, f.histWhy, f.histDetail = MK.Value(item, "historical", o)
    f.quality = MK.Quality(item, o)
    f.supply, f.supplyWhy = MK.Supply(item, o)
    f.comp, f.compWhy = MK.Competition(item, nil, o)
    local s = f.supply or f.min or f.recent or f.comp
    f.at, f.age, f.freshness = s and s.at, s and s.age, s and s.freshness
    return f
end

-- The facts of one item. opt: { market = a key, a market table or a Market.Source() answer (nil: the market the views use), variant = true for an
-- item that is a variant (never priced from the base item's listings), now }. Always a table; a market that is absent says `nomarket`.
function F.Of(item, opt)
    local now = opt and opt.now or time()
    local variant = opt and opt.variant == true
    local m = ResolveMarket(opt)
    local key = m and type(m.key) == "string" and m.key or nil
    if not (key and W.Valuation and W.Valuation.Generation) then   -- no key or no generation: nothing to validate against, so nothing is kept
        stats.misses = stats.misses + 1
        return Ask(item, m, variant, now)
    end
    local stamp = W.Valuation.Generation(m) .. "|" .. floor(now / F.BUCKET)
    local ck = key .. "\0" .. item .. (variant and "\0v" or "")
    local e = young[ck]
    if not e then
        e = old[ck]
        if e then old[ck] = nil end
    end
    if e and e.stamp == stamp and (not e.facts.srcs or SameSrcs(e.facts.srcs, m, item)) then
        stats.hits = stats.hits + 1
        if not young[ck] then young[ck], nYoung = e, nYoung + 1 end
        return e.facts
    end
    stats.misses = stats.misses + 1
    local pt = R.Perf and R.Perf.on and R.Perf.Start("workshop.market")
    local facts = Ask(item, m, variant, now)
    if pt then R.Perf.Stop(pt) end
    if not young[ck] then nYoung = nYoung + 1 end
    young[ck] = { stamp = stamp, facts = facts }
    if nYoung >= F.CACHE_MAX / 2 then old, young, nYoung = young, {}, 0 end
    return facts
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------
-- One short sentence for a missing figure (Market.VALUE_REASONS has the long ones)
local WHY = {
    nomarket = "not scanned yet", variant = "variant not priced", unlisted = "not listed now", outofscope = "not in the last scan",
    noevidence = "no price spread saved", missing = "no price saved", malformed = "can't be read", format = "saved by a newer version",
    nohistory = "no history yet", stale = "not seen in 14 days", norecent = "no recent price", insufficient = "too few observed days",
    nodata = "no observations", baditem = "unknown item",
}
F.WHY = WHY

local QUALITY = { good = "Good", fair = "Fair", limited = "Limited", none = "None" }
F.QUALITY = QUALITY

-- "4 hours ago" style age of a snapshot, in the product's own words
local function Age(age) return age and PR.AgeText(age) or nil end

local function Has(list, code)
    if type(list) ~= "table" then return false end
    for _, c in ipairs(list) do if c == code then return true end end
    return false
end

-- Qualifications that belong to a figure, in a few words (never alarming: a thin market is normal)
local function Tags(v)
    local t = {}
    if not v then return t end
    if v.aggregate or Has(v.notes, "aggregate") then t[#t + 1] = "approximate" end
    if Has(v.notes, "singleday") then t[#t + 1] = "one day" end
    if Has(v.notes, "sparse") then t[#t + 1] = "sparse" end
    return t
end

-- The rows of the Opportunities market block: { { id, label, value (text), tone ("text"|"dim"|"quiet"), tip (nil or a sentence) } }. Order: what the
-- player meets first (what is listed now), then the references from history, then how far to trust them.
-- f: F.Of's answer; money(copper) -> text; the rows exist whatever the data: a missing figure says why in the value column.
function F.Rows(f, money)
    local rows = {}
    local function Add(id, label, value, tone, tip) rows[#rows + 1] = { id = id, label = label, value = value, tone = tone or "text", tip = tip } end
    local function Miss(why) return WHY[why] or "unknown" end
    if f.nomarket then
        Add("min", "Lowest listing", "not scanned yet", "quiet")
        return rows
    end
    -- what is listed now
    if f.min then
        local n = f.min.listings
        Add("min", "Lowest listing", money(f.min.value), "text", f.min.basis)
    else
        Add("min", "Lowest listing", Miss(f.minWhy), "quiet")
    end
    local c = f.comp
    if c and c.competing then
        Add("comp", "Competing price", money(c.competing), "text",
            ("The cheapest price a seller would really compete with now: %d %s listed at or below it%s. Listings, not sales."):format(
                c.ahead or 0, (c.ahead or 0) == 1 and "item is" or "items are", c.below.items > 0 and "; a few much cheaper listings are skipped" or ""))
    elseif c and c.beyond then
        Add("comp", "Competing price", "beyond the cheapest six", "quiet", c.basis)
    else
        Add("comp", "Competing price", Miss(f.compWhy), "quiet")
    end
    -- references from observed listings
    if f.recent then
        Add("recent", "Recent price", money(f.recent.value), "text", f.recent.basis)
    else
        Add("recent", "Recent price", Miss(f.recentWhy), "quiet")
    end
    local function Ref(id, label, v, why, detail, days)
        if v then
            local tags = Tags(v)
            local text = money(v.value)
            Add(id, label, text, "text", v.basis .. (#tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or ""))
        else
            local w = Miss(why)
            if why == "insufficient" and detail and detail.n then w = ("%d of 3 observed days"):format(detail.n) end
            Add(id, label, w, "quiet")
        end
    end
    Ref("market", "Market value (14d)", f.mval, f.mvalWhy, f.mvalDetail)
    Ref("hist", "Historical value (60d)", f.hist, f.histWhy, f.histDetail)
    -- supply and the trust in all of it
    if f.supply then
        Add("supply", "Supply", ("%s %s"):format(tostring(f.supply.items), f.supply.items == 1 and "item" or "items"), "text", f.supply.basis)
    else
        Add("supply", "Supply", Miss(f.supplyWhy), "quiet")
    end
    local q = f.quality
    if q then
        local text = QUALITY[q.level] or "Unknown"
        local when = Age(f.age)
        if q.level ~= "none" and when then text = text .. " \194\183 " .. when end
        local lines = { q.basis }
        for _, r in ipairs(q.reasons or {}) do lines[#lines + 1] = r.text end
        if q.n then lines[#lines + 1] = ("Observed on %d of the last 30 days."):format(q.n) end
        Add("quality", "Data quality", text, (q.level == "good" or q.level == "fair") and "text" or "dim", table.concat(lines, " "))
    end
    return rows
end

-- The words under the market block's heading: when the current listings were scanned, apart from how far back the history reaches
function F.Freshness(f)
    if f.nomarket then return "no scan of this auction house yet" end
    if f.age == nil then return nil end
    local t = "listings scanned " .. PR.AgeText(f.age)
    if f.freshness == "old" or f.freshness == "stale" then t = t .. " (old)" end
    return t
end

-- Tooltip lines (A7), for WorthLayout: each is { text } or { left, right } and uses WorthLayout's "~" quiet marker. money(copper) -> text.
-- id: "marketvalue" (the default line), "recent", "historical", "supply" (supply and competition), "quality".
function F.Line(id, f, money)
    if not f or f.unsupported then return nil end
    if f.variant then return nil end
    local function Money(v) return money(v.value) end
    if f.nomarket then return nil end
    if id == "marketvalue" then
        if f.mval then
            local tags = Tags(f.mval)
            return { "Market value (14 days)" .. (#tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or ""), Money(f.mval) }
        end
        if f.mvalWhy == "unlisted" or f.mvalWhy == "nomarket" or f.mvalWhy == "variant" then return nil end
        return { "Market value (14 days)", WHY[f.mvalWhy] or "unknown" }
    elseif id == "recent" then
        if f.recent then return { "Recent price", Money(f.recent) } end
        if f.recentWhy == "unlisted" then return nil end
        return { "Recent price", WHY[f.recentWhy] or "unknown" }
    elseif id == "historical" then
        if f.hist then
            local tags = Tags(f.hist)
            return { "Historical value (60 days)" .. (#tags > 0 and (" (" .. table.concat(tags, ", ") .. ")") or ""), Money(f.hist) }
        end
        if f.histWhy == "nohistory" then return nil end
        return { "Historical value (60 days)", WHY[f.histWhy] or "unknown" }
    elseif id == "supply" then
        local s, c = f.supply, f.comp
        if not s then return nil end
        local text = ("%d %s listed"):format(s.items, s.items == 1 and "item" or "items")
        if c and c.competing and c.ahead then text = text .. (", %d at or below %s"):format(c.ahead, money(c.competing)) end
        return { "Supply", text }
    elseif id == "quality" then
        local q = f.quality
        if not q or q.level == "none" then return nil end
        local text = QUALITY[q.level]
        if f.age then text = text .. ", scanned " .. PR.AgeText(f.age) end
        return { "Market data", text }
    end
end

-- The reasons behind the data quality, as quiet lines (Shift): one sentence each, at most `max`
function F.QualityNotes(f, max)
    local out = {}
    local q = f and f.quality
    if not q or q.level == "good" or q.level == "none" then return out end
    for _, r in ipairs(q.reasons or {}) do
        out[#out + 1] = r.text
        if #out >= (max or 3) then break end
    end
    return out
end

---------------------------------------------------------------------------
-- The chart's series (A7)
---------------------------------------------------------------------------
-- The Opportunities chart draws one dot per observed day and the older ranges behind them: the shape Market.Series has always returned
-- ({ points = { { day, price } }, groups = { { from, to, low, high, average, n } }, today, label }). Market.Series reads only the FROZEN
-- minimum history of version 1.3 (it is no longer recorded: Prices.FEED_LEGACY_HISTORY is false), so a market scanned since would show no new
-- day. This builds the same shape from Market.History(item, "min"), which joins that frozen history (only days before version-2 recording
-- began, never twice) with every day recorded since, so each new scan adds its day. The metric stays the MINIMUM (the chart says "Cheapest seen"):
-- the Recent Price is never mixed with it. Exact days are dots; week, fortnight and legacy buckets are groups (never drawn as days); the
-- 48-hour observations only stand in for a day that has no daily point yet (the day's last observation). Nothing is interpolated.
-- Returns series or nil and a reason; memoised on the facts while the item's saved strings are the same ones (a scan replaces the facts).
function F.Chart(f)
    if f.nomarket or f.variant or not f.key then return nil, f.variant and "variant" or "nomarket" end
    local m = ResolveMarket({ market = f.key })
    if not m then return nil, "nomarket" end
    if f.chart ~= nil and f.chartSrcs and SameSrcs(f.chartSrcs, m, f.item) then return f.chart or nil, f.chartWhy end
    local function Done(s, why) f.chart, f.chartWhy, f.chartSrcs = s or false, why, { Srcs(m, f.item) } return s, why end
    if not MK.History then
        local s, why = MK.Series(f.item, { market = m, now = f.now })
        return Done(s, why)
    end
    local h, why = MK.History(f.item, "min", { market = m, now = f.now })
    if not h then return Done(nil, why) end
    local days, groups, order = {}, {}, {}
    for _, p in ipairs(h.points) do
        if (p.kind == "day" or p.kind == "legacy-day") and p.v then
            days[p.from] = p.v
        elseif (p.kind == "week" or p.kind == "fortnight" or p.kind == "legacy-bucket") and p.v then
            groups[#groups + 1] = { from = p.from, to = p.to, low = p.lo or p.v, high = p.hi or p.v, average = p.v, n = p.n or 0 }
        end
    end
    for _, p in ipairs(h.points) do
        if p.kind == "obs" and p.v then
            local d = floor((p.last or p.at) / 86400)
            if days[d] == nil then days[d] = p.v end
        end
    end
    for d in pairs(days) do order[#order + 1] = d end
    table.sort(order)
    local points = {}
    for _, d in ipairs(order) do points[#points + 1] = { day = d, price = days[d] } end
    if #points == 0 and #groups == 0 then return Done(nil, "nodata") end
    return Done({ item = f.item, points = points, groups = groups, today = h.today, market = h.market, label = h.label, basis = h.basis,
        recordedFrom = h.recordedFrom, v2from = h.v2from })
end
