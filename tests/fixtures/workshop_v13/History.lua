-- TwichUI Workshop: price history of one item in one market (pure: no game calls, no frames, no saved variables)
-- Prices.lua keeps one history string per item; this file is the only code that knows its shape.
--
-- WHAT A HISTORY IS: the item's CHEAPEST BUYOUT LISTING (per single item) as the full scans of one auction house saw it, at most ONE
-- value per calendar day (UTC): a second scan on the same day replaces that day's value. A day on which no scan happened has no value
-- and never gets one; a day on which a scan happened but did not list the item has no value for it either. It is a record of LISTINGS,
-- never of sales: nothing here knows what sold, how fast or for how much.
--
-- TWO TIERS, both bounded:
--   recent   the last POINTS observed days, one exact value each            "d,p;d,p;..."  oldest first (d = day number, p = copper)
--   older    when a seventh-plus day arrives the oldest point is folded into a 28-day bucket that keeps only its lowest value, highest
--            value, the sum of its values and how many days it holds       "b,lo,hi,sum,n;..."   (b = day // 28)
--   at most MAX_BUCKETS buckets, nothing older than RETAIN_DAYS. The string is  recent .. "|" .. older  (either side may be empty).
-- So an exact value, and so an exact average, exists for the last POINTS observed days; further back there is the low, the high and the
-- mean of the observed days of each 28-day bucket, nothing more (not the days, not the trend inside a bucket).
-- An observation dated before the newest one kept is ignored (the clock went backwards or an old scan arrived late): history never
-- reorders and never invents.
--
-- Everything is plain digits, commas, semicolons and one bar: nothing in it needs escaping in a saved-variables file.

local R = TwichUI
local W = R.Workshop
local H = {}
W.History = H

H.DAY = 86400
H.POINTS = 7          -- recent days kept exactly
H.BUCKET_DAYS = 28    -- the days one older bucket covers
H.MAX_BUCKETS = 3     -- older buckets kept (so up to 3 x 28 days of coarse history behind the exact days)
H.RETAIN_DAYS = 120   -- nothing older than this many days before the newest scan is kept
H.MAX_SCAN_DAYS = 32  -- scan days remembered per market (Prices.lua): how many scans an item could have been seen in

local MAX_DAY = 200000    -- day numbers up to the year 2517
local MAX_COPPER = 99999999999
local floor = math.floor

local function N(v) return ("%.0f"):format(v) end

-- The day number (days since 1970-01-01, UTC) of a time, or nil
function H.Day(at)
    if type(at) ~= "number" or at ~= at or at < 0 then return nil end
    local d = floor(at / H.DAY)
    if d < 1 or d > MAX_DAY then return nil end
    return d
end

-- Parses a history string into flat arrays: pts = { d1, p1, d2, p2, ... } (oldest first, days strictly rising) and bks = { b1, lo1, hi1,
-- sum1, n1, ... } (oldest first). A malformed string gives nil: it is treated as no history, never repaired by guessing.
function H.Decode(s)
    if type(s) ~= "string" then return nil end
    local recent, older = s:match("^([%d,;]*)|([%d,;]*)$")
    if not recent then return nil end
    local pts, bks = {}, {}
    local lastDay, len = 0, 0
    for d, p in recent:gmatch("(%d+),(%d+);?") do
        len = len + #d + #p + 2
        d, p = tonumber(d), tonumber(p)
        if d <= lastDay or d > MAX_DAY or p < 1 or p > MAX_COPPER then return nil end
        lastDay = d
        pts[#pts + 1] = d
        pts[#pts + 1] = p
    end
    if len ~= (#recent > 0 and #recent + 1 or 0) then return nil end   -- something in it was not a "day,price" pair
    local lastB, olen = -1, 0
    for b, lo, hi, sum, n in older:gmatch("(%d+),(%d+),(%d+),(%d+),(%d+);?") do
        olen = olen + #b + #lo + #hi + #sum + #n + 5
        b, lo, hi, sum, n = tonumber(b), tonumber(lo), tonumber(hi), tonumber(sum), tonumber(n)
        if b <= lastB or lo < 1 or hi < lo or hi > MAX_COPPER or n < 1 or sum < lo * n or sum > hi * n then return nil end
        lastB = b
        local at = #bks
        bks[at + 1], bks[at + 2], bks[at + 3], bks[at + 4], bks[at + 5] = b, lo, hi, sum, n
    end
    if olen ~= (#older > 0 and #older + 1 or 0) then return nil end
    if #pts == 0 and #bks == 0 then return nil end
    return pts, bks
end

function H.Encode(pts, bks)
    local r, o = {}, {}
    for i = 1, #pts, 2 do r[#r + 1] = N(pts[i]) .. "," .. N(pts[i + 1]) end
    for i = 1, #bks, 5 do
        o[#o + 1] = N(bks[i]) .. "," .. N(bks[i + 1]) .. "," .. N(bks[i + 2]) .. "," .. N(bks[i + 3]) .. "," .. N(bks[i + 4])
    end
    return table.concat(r, ";") .. "|" .. table.concat(o, ";")
end

-- Folds the oldest recent point into its bucket
local function Fold(pts, bks)
    local d, p = table.remove(pts, 1), table.remove(pts, 1)
    local b = floor(d / H.BUCKET_DAYS)
    local at = #bks - 4
    if at >= 1 and bks[at] == b then
        if p < bks[at + 1] then bks[at + 1] = p end
        if p > bks[at + 2] then bks[at + 2] = p end
        bks[at + 3] = bks[at + 3] + p
        bks[at + 4] = bks[at + 4] + 1
    else
        local n = #bks
        bks[n + 1], bks[n + 2], bks[n + 3], bks[n + 4], bks[n + 5] = b, p, p, p, 1
    end
end

-- Drops what is older than RETAIN_DAYS before `today`
local function Expire(pts, bks, today)
    local cutoff = today - H.RETAIN_DAYS
    while #pts >= 2 and pts[1] < cutoff do table.remove(pts, 1) table.remove(pts, 1) end
    while #bks >= 5 and (bks[1] + 1) * H.BUCKET_DAYS - 1 < cutoff do
        for _ = 1, 5 do table.remove(bks, 1) end
    end
    while #bks > H.MAX_BUCKETS * 5 do for _ = 1, 5 do table.remove(bks, 1) end end
end

-- The history string after observing `price` (whole copper) on `day`; `old` is the item's current string or nil. Returns the new
-- string, or nil and why: "bad" (day or price not a whole number in range), "stale" (older than the newest day kept).
function H.Add(old, day, price)
    if type(day) ~= "number" or day ~= floor(day) or day < 1 or day > MAX_DAY then return nil, "bad" end
    if type(price) ~= "number" or price ~= floor(price) or price < 1 or price > MAX_COPPER then return nil, "bad" end
    local pts, bks = H.Decode(old)
    if not pts then pts, bks = {}, {} end
    local n = #pts
    if n >= 2 then
        local last = pts[n - 1]
        if day < last then return nil, "stale" end
        if day == last then pts[n] = price else pts[n + 1], pts[n + 2] = day, price end
    else
        pts[1], pts[2] = day, price
    end
    while #pts > H.POINTS * 2 do Fold(pts, bks) end
    Expire(pts, bks, day)
    if #pts == 0 and #bks == 0 then return nil, "bad" end
    return H.Encode(pts, bks)
end

-- The string with what expired as of `today` removed: the same string when nothing did, nil when nothing is left (or it was malformed)
function H.Trim(s, today)
    local pts, bks = H.Decode(s)
    if not pts then return nil end
    local np, nb = #pts, #bks
    Expire(pts, bks, today)
    if #pts == 0 and #bks == 0 then return nil end
    if #pts == np and #bks == nb then return s end
    return H.Encode(pts, bks)
end

-- The newest day with a value, or nil
function H.Newest(s)
    local pts, bks = H.Decode(s)
    if not pts then return nil end
    if #pts >= 2 then return pts[#pts - 1], pts[#pts] end
    if #bks >= 5 then return (bks[#bks - 4] + 1) * H.BUCKET_DAYS - 1 end
    return nil
end

-- What the days from `fromDay` to `toDay` (both included) hold, from the exact days and the older buckets that lie ENTIRELY inside:
--   n (days with a value), lo, hi, sum (so mean = sum / n), first, last (the oldest and newest EXACT day counted; nil when only buckets
--   were), exact (every value counted is an exact day), skipped (observed days inside the older buckets that overlap the window only partly and so were not counted)
-- nil when the string holds nothing for the window.
function H.Window(s, fromDay, toDay)
    local pts, bks = H.Decode(s)
    if not pts then return nil end
    local r = { n = 0, sum = 0, exact = true, skipped = 0 }
    for i = 1, #pts, 2 do
        local d, p = pts[i], pts[i + 1]
        if d >= fromDay and d <= toDay then
            r.n, r.sum = r.n + 1, r.sum + p
            if not r.lo or p < r.lo then r.lo = p end
            if not r.hi or p > r.hi then r.hi = p end
            r.first = r.first or d
            r.last = d
        end
    end
    for i = 1, #bks, 5 do
        local b0 = bks[i] * H.BUCKET_DAYS
        local b1 = b0 + H.BUCKET_DAYS - 1
        if b1 >= fromDay and b0 <= toDay then
            if b0 >= fromDay and b1 <= toDay then
                r.n, r.sum, r.exact = r.n + bks[i + 4], r.sum + bks[i + 3], false
                if not r.lo or bks[i + 1] < r.lo then r.lo = bks[i + 1] end
                if not r.hi or bks[i + 2] > r.hi then r.hi = bks[i + 2] end
            elseif not pts[1] or fromDay < pts[1] then
                -- (when the exact days reach back to the start of the window, everything older is outside it: nothing was missed)
                r.skipped = r.skipped + bks[i + 4]
            end
        end
    end
    if r.n == 0 then return nil end
    return r
end
