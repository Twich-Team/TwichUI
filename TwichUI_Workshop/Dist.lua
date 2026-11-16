-- TwichUI Workshop: the price distribution of one item (pure: no game calls, no frames, no saved data)
-- Market Data Foundation 2.0, milestone A3 (docs/workshop/market-data-foundation-v2.md, sections 3.3, 5 and 12). Prices.lua accumulates the
-- listings of a scan into price tiers; this file turns the tiers of ONE item into the numbers worth keeping and into the saved text, and reads
-- that text back with every check a reader needs.
--
-- A TIER is one distinct unit price in whole copper (a stack's buyout divided by its count, rounded UP: the price a buyer sees) with the items
-- and the buyout listings at it. Everything below works on the tiers of one item, cheapest first: ps[k] price, qs[k] items, ls[k] listings,
-- ms[k] the largest single listing's items (nil is allowed where ls[k] is 1: that listing is the whole tier).
--
-- WHAT IS COMPUTED (all of it listing evidence; none of it is a sale, a sale price or a price to post):
--   t, l      items and listings in all
--   q25 q50 q75   quantity-weighted quartiles, NEAREST RANK: the price of the item at rank ceil(p x t) when every item is lined up by price
--                 (the first tier whose running total is at least p x t). q25 <= q50 <= q75.
--   a         the ANCHOR: the price of the first tier whose running total is STRICTLY MORE than a quarter of the items (rank floor(t / 4) + 1).
--                 It differs from q25 only when a running total is exactly a quarter of the items: q25 <= a <= q50.
--   r         RECENT PRICE (the "band mean", owner decision D1, approved provisionally): ignore the items priced below half the anchor, take the
--                 cheapest 30% of the items that are left (a fraction of an item counts at the edge) and average their prices, rounded half up.
--                 A representative LISTING price. It cannot exceed q50 (the band ends at rank 0.475 t or earlier) or fall below the minimum.
--   hi        the highest unit price listed
--   near      the items listed at or below 1.10 x r (compared as price x 10 <= r x 11, whole numbers)
--
-- ARITHMETIC. The band mean is worked in tenths of an item so no fraction exists: with s the sum over the band of (tenths of an item x
-- (price - cheapest eligible price)) and w the tenths in the band (3 x the eligible items), r = cheapest eligible + floor((2s + w) / 2w). That
-- is EXACT while 2s + w < 2^53 (every product and every sum is then a whole number a double holds exactly, and the division cannot cross an
-- integer boundary); beyond that, which only absurd prices and quantities reach, the same formula runs in doubles and is within 1 copper (the
-- result says which with `exact`). Packed tiers (Prices.lua) are items x SHIFT + listings; SHIFT is 2^18, more than the most records one scan
-- reads, so the listings never carry into the items and items stay below 2^53 / SHIFT.
--
-- SAVED TEXT (3.3 of the foundation document; written only for an item with TWO OR MORE tiers):
--   "alg,r,a,q25,q50,q75,hi,near|p1:q1:l1:m1;...;p6:q6:l6:m6|tq:tl"
--   alg 1 (this algorithm); the cheapest SIX tiers with price, items, listings and the largest single listing (m is OMITTED when l is 1);
--   the last section is the items and listings beyond the sixth tier and is OMITTED when there are none (then 6 or fewer tiers hold everything).
--   Numbers are whole, canonical ("%.0f", no leading zeros). An item with one tier has no entry: everything about it is its minimum entry.
local R = TwichUI
local W = R.Workshop
local Int = W.Int
local floor = math.floor
local D = {}
W.Dist = D

D.ALG = 1                      -- the algorithm that makes r (snap.alg = 1 says a scan's dist entries came from it)
D.TIERS = 6                    -- tiers kept in an entry
D.SHIFT = 262144               -- 2^18: a packed tier is items * SHIFT + listings
D.MAX_RECORDS = D.SHIFT - 1    -- priced records one batch may take into tiers (a tier's listings must fit under SHIFT); beyond: no distribution
D.MAX_COPPER = 99999999999     -- the same limit as Prices.MAX_COPPER (tested to agree)
D.MAX_ITEMS = 4294967295       -- items in one item's listings, at most (SHIFT - 1 records of 10,000 items is 2.6e9)
local TWO53 = 9007199254740992

local function N(v) return ("%.0f"):format(v) end

-- packed tier -> items, listings
function D.Unpack(v)
    local l = v % D.SHIFT
    return (v - l) / D.SHIFT, l
end

---------------------------------------------------------------------------
-- The numbers
---------------------------------------------------------------------------
-- ps, qs, ls: the tiers, cheapest first, n >= 1 of them (ms is not needed here). Returns
--   r, a, q25, q50, q75, hi, near, t, l, exact
function D.Stats(ps, qs, ls, n)
    local t, l = 0, 0
    for k = 1, n do t, l = t + qs[k], l + ls[k] end

    -- quartiles and the anchor: one pass over the running total
    local q25, a, q50, q75
    local cum = 0
    for k = 1, n do
        cum = cum + qs[k]
        local p, c4 = ps[k], cum * 4
        if not q25 and c4 >= t then q25 = p end
        if not a and c4 > t then a = p end           -- STRICTLY more than a quarter
        if not q50 and cum * 2 >= t then q50 = p end
        if not q75 and c4 >= t * 3 then q75 = p break end
    end

    -- the band: the items priced at least half the anchor, then the cheapest 30% of them
    local first = 1
    while ps[first] * 2 < a do first = first + 1 end
    local eligible = 0
    for k = first, n do eligible = eligible + qs[k] end
    local base, want = ps[first], eligible * 3        -- want: tenths of an item
    local got, sum = 0, 0
    for k = first, n do
        local take = qs[k] * 10
        if take > want - got then take = want - got end
        sum = sum + take * (ps[k] - base)
        got = got + take
        if got >= want then break end
    end
    local r = base + floor((2 * sum + got) / (2 * got))
    local exact = (2 * sum + got) < TWO53

    local near, limit = 0, r * 11
    for k = 1, n do
        if ps[k] * 10 > limit then break end
        near = near + qs[k]
    end
    return r, a, q25, q50, q75, ps[n], near, t, l, exact
end

---------------------------------------------------------------------------
-- The text
---------------------------------------------------------------------------
-- The saved text of an item with n >= 2 tiers (ms[k] is read only where ls[k] > 1)
function D.Encode(ps, qs, ls, ms, n)
    local r, a, q25, q50, q75, hi, near = D.Stats(ps, qs, ls, n)
    local parts, tq, tl = {}, 0, 0
    local format = string.format
    for k = 1, n do
        if k <= D.TIERS then
            if ls[k] == 1 then parts[k] = format("%.0f:%.0f:1", ps[k], qs[k])
            else parts[k] = format("%.0f:%.0f:%.0f:%.0f", ps[k], qs[k], ls[k], ms[k]) end
        else
            tq, tl = tq + qs[k], tl + ls[k]
        end
    end
    local text = format("1,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f,%.0f|%s", r, a, q25, q50, q75, hi, near, table.concat(parts, ";"))
    if tq > 0 then text = format("%s|%.0f:%.0f", text, tq, tl) end
    return text
end

-- A canonical whole number from text ("0" or digits without a leading zero) within lo..hi, or nil
local function Num(s, lo, hi)
    if #s > 1 and s:byte(1) == 48 then return nil end
    return Int(tonumber(s), lo, hi)
end

-- Reads a saved entry. Returns the distribution, or nil and why:
--   { alg, r, a, q25, q50, q75, hi, near, t, l, min, tiers = { { p, q, l, m } ... (2 to 6, cheapest first, m always present) }, tq, tl, exact }
-- Nothing is repaired: an entry that is malformed, or that contradicts itself, is nil. With every tier present (no tail) the whole entry is
-- worked out again from the tiers and must match; with a tail the numbers the six tiers decide are checked and the rest is bounded.
function D.Decode(e)
    if type(e) ~= "string" or #e > 420 then return nil, "shape" end
    local head, tiers, tail = e:match("^([%d,]+)|([%d:;]+)|([%d:]+)$")
    if not head then
        head, tiers = e:match("^([%d,]+)|([%d:;]+)$")
        tail = nil
    end
    if not head then return nil, "shape" end
    local alg, r, a, q25, q50, q75, hi, near = head:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+)$")
    if not alg then return nil, "shape" end
    if alg ~= "1" then return nil, "algorithm" end
    local P = D.MAX_COPPER
    r, a, q25, q50, q75, hi = Num(r, 1, P), Num(a, 1, P), Num(q25, 1, P), Num(q50, 1, P), Num(q75, 1, P), Num(hi, 1, P)
    near = Num(near, 1, D.MAX_ITEMS)
    if not (r and a and q25 and q50 and q75 and hi and near) then return nil, "number" end

    local out = { alg = 1, r = r, a = a, q25 = q25, q50 = q50, q75 = q75, hi = hi, near = near, tiers = {}, tq = 0, tl = 0 }
    local ps, qs, ls, ms, n = {}, {}, {}, {}, 0
    local t, l = 0, 0
    for seg in (tiers .. ";"):gmatch("([^;]*);") do
        n = n + 1
        if n > D.TIERS then return nil, "tiers" end
        local sp, sq, sl, sm = seg:match("^(%d+):(%d+):(%d+):(%d+)$")
        if sp then
            if sl == "1" then return nil, "tier" end                 -- m is written only for tiers of two or more listings
        else
            sp, sq, sl = seg:match("^(%d+):(%d+):(%d+)$")
            if not sp or sl ~= "1" then return nil, "tier" end
            sm = sq
        end
        local p, q, li, m = Num(sp, 1, P), Num(sq, 1, D.MAX_ITEMS), Num(sl, 1, D.SHIFT - 1), Num(sm, 1, D.MAX_ITEMS)
        if not (p and q and li and m) then return nil, "number" end
        if li > q or m > q or m * li < q then return nil, "tier" end   -- every listing holds an item; the largest holds at most all of them
        if li == 1 and m ~= q then return nil, "tier" end
        if n > 1 and p <= ps[n - 1] then return nil, "order" end
        ps[n], qs[n], ls[n], ms[n] = p, q, li, m
        t, l = t + q, l + li
        out.tiers[n] = { p = p, q = q, l = li, m = m }
    end
    if n < 2 then return nil, "tiers" end

    local tq, tl = 0, 0
    if tail then
        local sq, sl = tail:match("^(%d+):(%d+)$")
        if not sq then return nil, "tail" end
        tq, tl = Num(sq, 1, D.MAX_ITEMS), Num(sl, 1, D.SHIFT - 1)
        if not (tq and tl) or tl > tq then return nil, "tail" end
        if n ~= D.TIERS then return nil, "tail" end        -- something is beyond the sixth tier only when six tiers exist
        if hi <= ps[n] then return nil, "order" end
    elseif hi ~= ps[n] then
        return nil, "order"
    end
    t, l = t + tq, l + tl
    out.tq, out.tl, out.t, out.l, out.min = tq, tl, t, l, ps[1]
    if t > D.MAX_ITEMS or near > t then return nil, "number" end

    -- ordering of the statistics: min <= q25 <= a <= q50 <= q75 <= hi, and min <= r <= q50
    if not (ps[1] <= q25 and q25 <= a and a <= q50 and q50 <= q75 and q75 <= hi and ps[1] <= r and r <= q50) then return nil, "order" end

    if tq == 0 then
        -- the whole distribution is here: everything must be what the tiers say
        local r2, a2, c25, c50, c75, hi2, near2, _, _, exact = D.Stats(ps, qs, ls, n)
        if r2 ~= r or a2 ~= a or c25 ~= q25 or c50 ~= q50 or c75 ~= q75 or hi2 ~= hi or near2 ~= near then return nil, "stats" end
        out.exact = exact
    else
        -- six tiers and a tail: a statistic whose running total is reached inside the six tiers is that tier's price, otherwise it lies beyond
        local cum = 0
        local want = { { q25, 4, 1, true }, { a, 4, 1, false }, { q50, 2, 1, true }, { q75, 4, 3, true } }
        local found = {}
        for k = 1, n do
            cum = cum + qs[k]
            for i, w in ipairs(want) do
                if found[i] == nil then
                    local c = cum * w[2]
                    local reached = w[4] and c >= t * w[3] or (not w[4] and c > t * w[3])
                    if reached then found[i] = ps[k] end
                end
            end
        end
        for i, w in ipairs(want) do
            if found[i] ~= nil then
                if w[1] ~= found[i] then return nil, "stats" end
            elseif w[1] <= ps[n] then
                return nil, "stats"
            end
        end
        -- near: counted exactly when a tier above 1.10 x r is among the six, at least the cheap tiers' items otherwise
        local below, cut = 0, false
        for k = 1, n do
            if ps[k] * 10 > r * 11 then cut = true break end
            below = below + qs[k]
        end
        if (cut and near ~= below) or (not cut and near < below) then return nil, "stats" end
    end
    return out
end
