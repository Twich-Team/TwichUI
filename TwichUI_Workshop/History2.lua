-- TwichUI Workshop: version-2 market history of one item in one market (pure: no game calls, no frames, no saved variables)
-- Market Data Foundation 2.0, milestone A4 (docs/workshop/market-data-foundation-v2.md sections 3.3, 3.4, 6, 7.4 and "A4 as built").
-- Prices.lua keeps two strings per item (market.h2[id] and market.c2[id]) and calls this file to change them; Market.lua calls it to read
-- them. Nothing else knows their shape. The frozen legacy minimum history (History.lua) is a different thing and is never touched here.
--
-- WHAT IS KEPT, per item, from the WHOLE-READ scans that listed it (cut, changed, interrupted and refused scans add nothing):
--   ring     the last observations, at most RING (8), none whose last sighting is more than 48 hours before the scan being saved. Real times
--            (minute resolution). A point is "seen at m, and again at m + dm with identical values"; it is extended only when the values are
--            the same AND the previous history-feeding scan of the market saw it (so an observed absence is never hidden inside a flat line).
--   daily    one point per UTC day the item was listed: the CLOSING values (the last such scan that day), the scan count n, and the day's
--            lowest and highest minimum, Recent Price and items listed. Every listed day of the last 30 days is a daily point.
--   buckets  older days: whole calendar weeks (day // 7, weeks start on a Thursday because day 0 was one) folded once the whole week is 30 or
--            more days old; pairs of weeks (week // 2) merged into two-week buckets once the pair ends more than 60 days back; nothing whose
--            bucket ends more than 120 days back is kept. 7, 14 and the legacy 28 divide 28, so every tier falls on the same boundaries.
-- An observation is p (minimum buyout, copper per item), r (Recent Price, A3's band mean; nil = NOT KNOWN, never 0 and never p in disguise),
-- t (items listed), l (buyout listings) and pf (the scan had records lacking their information).
--
-- SAVED TEXT (format 1; market.h2info.v = 1):
--   h2[id] = "<ring>|<newest day>:<daily>"            ring: points ";"-separated, oldest first; daily: points ";"-separated, oldest first
--     ring point   "m,dm,p,dr,t,l[!]"   m: minute (time // 60) of the first sighting, ABSOLUTE for the first point and the minutes after the
--                                       previous point's m for later ones; dm: minutes to the last sighting; dr = r - p, EMPTY when r is unknown
--     daily point  "dd,p,dr,t,l[!]"                              one qualifying scan (n = 1)
--                  "dd,p,dr,t,l,n[!]"                            n >= 2 scans and nothing moved (every range is the closing value)
--                  "dd,p,dr,t,l,n[!]~"                           n >= 2, the ranges were CONDENSED away by the budget guard (closing kept)
--                  "dd,p,dr,t,l,n,dpl,dph,drl,drh,dtl,dth[!]"    n >= 2 and something moved: closing minus the day's lowest minimum, highest
--                                       minimum minus closing, the same for Recent Price and for items. When the closing r is unknown, drl and
--                                       drh are the day's lowest and highest KNOWN r as absolute values (both empty when no scan had one).
--                  dd: the day number for the first point, the days after the previous point for later ones; newest day = the last point's day.
--   c2[id] = "<bucket>;<bucket>..."   oldest first
--     bucket "k,s,n,nr,plo,dpm,dph,rm,drl,drh,tm,dtl,dth,lm[!][~]"   s = 7 or 14, days k*s .. k*s+s-1; n observed days, nr of them with a known
--            closing r; minimum: lowest day low, mean of closings (plo + dpm), highest day high (mean + dph); Recent: mean of the known closings
--            rm (over nr days), rm - drl, rm + drh (rm EMPTY when nr = 0, then drl/drh are the absolute low/high or empty); items: mean tm,
--            tm - dtl, tm + dth (dtl/dth EMPTY once the budget guard dropped the supply range); lm mean listings; "!" a scan behind it lacked
--            information; "~" a day inside had condensed ranges (its closing values stood in for its range).
--   Numbers are whole and canonical (%.0f, no leading zeros). Means round half up; a two-week mean merged from two weekly means is
--   round((m1 x n1 + m2 x n2) / (n1 + n2)) with each metric's own count (nr for Recent Price), so it is within 1 copper (1 item) of the exact
--   mean of its days. Every reader here refuses anything this writer never makes; a refused string is ABSENT (never repaired, never guessed).
--
-- UPDATES: Update() appends to the newest daily point or adds one, and rewrites the ring, WITHOUT decoding the daily points in between (the
-- append path, section 7.2); it decodes everything only when a fold, a merge or an expiry is due, or when the fast checks fail. Both paths give
-- the same text (tests/test_workshop_history2.lua compares them with an independent encoder).

local R = TwichUI
local W = R.Workshop
local floor = math.floor
local H2 = {}
W.History2 = H2

H2.FORMAT = 1               -- market.h2info.v this file writes and reads (a higher one is a later build's: never read or written here)
H2.RING = 8                 -- observations kept in the ring
H2.RING_MINUTES = 48 * 60   -- the ring's reach before the newest saved scan
H2.DAILY_DAYS = 30          -- every listed day this recent is a daily point
H2.WEEKLY_DAYS = 60         -- a pair of weeks ending more than this far back becomes a two-week bucket
H2.RETAIN_DAYS = 120        -- a bucket ending more than this far back is dropped
H2.WEEK, H2.FORTNIGHT = 7, 14
H2.PROTECT_DAYS = 14        -- the budget guard never touches daily points of the last 14 days (ages 0 to 13)
H2.SPARSE_DAYS = 4          -- budget step 2 folds early only items listed on fewer than this many of the last 30 days
H2.DAY = 86400

local MAX_DAY = 200000
local MAX_MINUTE = MAX_DAY * 1440
local MAX_COPPER = 99999999999
local MAX_ITEMS = 4294967295
local MAX_LISTINGS = 4294967295

local function N(v) return ("%.0f"):format(v) end

-- a canonical whole number ("0" or no leading zero, at most 12 digits) or nil; "" gives false (an empty field)
local function Num(s)
    if s == "" then return false end
    local n = #s
    if n > 12 or (n > 1 and s:byte(1) == 48) then return nil end
    return tonumber(s)
end

-- half up, exact for the sums here (at most 14 values below 10^11)
local function Mean(sum, n) return floor((2 * sum + n) / (2 * n)) end
H2.Mean = Mean

function H2.Day(at) return floor(at / H2.DAY) end
-- days before this are folded (a week whose last day is 30 or more days before `today`)
function H2.FoldBefore(today) return 7 * floor((today - 29) / 7) end
local FoldBefore = H2.FoldBefore
local function BucketEnd(b) return b.k * b.s + b.s - 1 end
H2.BucketEnd = BucketEnd

---------------------------------------------------------------------------
-- One observation (validated): { at, p, r, t, l, pf } or nil
---------------------------------------------------------------------------
function H2.Obs(at, p, r, t, l, pf)
    if not (W.Finite(at) and at >= 60 and at < MAX_MINUTE * 60) then return nil end
    p, t, l = W.Int(p, 1, MAX_COPPER), W.Int(t, 1, MAX_ITEMS), W.Int(l, 1, MAX_LISTINGS)
    if not (p and t and l) then return nil end
    if r ~= nil then
        r = W.Int(r, 1, MAX_COPPER)
        if not r or r < p then return nil end   -- a Recent Price below the minimum of the same scan is not an A3 value: refuse, never write it
    end
    return { at = floor(at), p = p, r = r, t = t, l = l, pf = pf == true }
end

---------------------------------------------------------------------------
-- Reading the text
---------------------------------------------------------------------------
-- a daily point's fields; d is as written (absolute or a delta)
local function DayPoint(seg)
    local d, p, dr, t, l, rest = seg:match("^(%d+),(%d+),(%d*),(%d+),(%d+)(.*)$")
    if not d then return nil end
    d, p, dr, t, l = Num(d), Num(p), Num(dr), Num(t), Num(l)
    if not (d and p and t and l) or dr == nil or p < 1 or t < 1 or l < 1 or p > MAX_COPPER then return nil end
    local r = nil
    if dr then r = p + dr if r > MAX_COPPER then return nil end end
    local x = { d = d, p = p, r = r, t = t, l = l, n = 1, plo = p, phi = p, rlo = r, rhi = r, tlo = t, thi = t }
    if rest == "" or rest == "!" then x.pf = rest == "!" return x end
    local n, fl = rest:match("^,(%d+)([!~]*)$")
    if n then
        n = Num(n)
        if not n or n < 2 then return nil end
        x.n = n
        if fl == "" or fl == "!" then x.pf = fl == "!" return x end
        if fl == "~" or fl == "!~" then
            x.pf, x.cf = fl == "!~", true
            x.plo, x.phi, x.rlo, x.rhi, x.tlo, x.thi = nil, nil, nil, nil, nil, nil
            return x
        end
        return nil
    end
    local n2, dpl, dph, drl, drh, dtl, dth, f2 = rest:match("^,(%d+),(%d+),(%d+),(%d*),(%d*),(%d+),(%d+)(!?)$")
    if not n2 then return nil end
    n2, dpl, dph, drl, drh, dtl, dth = Num(n2), Num(dpl), Num(dph), Num(drl), Num(drh), Num(dtl), Num(dth)
    if not (n2 and dpl and dph and dtl and dth) or drl == nil or drh == nil or n2 < 2 then return nil end
    x.n, x.pf = n2, f2 == "!"
    x.plo, x.phi, x.tlo, x.thi = p - dpl, p + dph, t - dtl, t + dth
    if x.plo < 1 or x.tlo < 1 or x.phi > MAX_COPPER then return nil end
    if r then
        if not (drl and drh) then return nil end
        x.rlo, x.rhi = r - drl, r + drh
        if x.rlo < 1 or x.rhi > MAX_COPPER then return nil end
        if dpl == 0 and dph == 0 and drl == 0 and drh == 0 and dtl == 0 and dth == 0 then return nil end   -- the short form says that
    else
        if (drl and not drh) or (drh and not drl) then return nil end
        if drl then
            if drl < 1 or drh < drl or drh > MAX_COPPER then return nil end
            x.rlo, x.rhi = drl, drh
        elseif dpl == 0 and dph == 0 and dtl == 0 and dth == 0 then
            return nil
        end
    end
    return x
end

local function Segments(s)
    local out, pos = {}, 1
    while true do
        local e = s:find(";", pos, true)
        if not e then out[#out + 1] = s:sub(pos) return out end
        out[#out + 1] = s:sub(pos, e - 1)
        pos = e + 1
    end
end

-- the ring text -> list of points with absolute minutes, or nil
local function DecodeRing(s)
    local ring = {}
    if s == "" then return ring end
    local prev, len = nil, 0
    -- one pass; the lengths of what matched must add up to the whole text, so nothing between the points went unread
    for m, dm, p, dr, t, l, fl, sep in s:gmatch("(%d+),(%d+),(%d+),(%d*),(%d+),(%d+)(!?)(;?)") do
        len = len + #m + #dm + #p + #dr + #t + #l + #fl + #sep + 5
        if sep == "" and len ~= #s then return nil end
        m, dm, p, dr, t, l = Num(m), Num(dm), Num(p), Num(dr), Num(t), Num(l)
        if not (m and dm and p and t and l) or dr == nil or p < 1 or t < 1 or l < 1 or p > MAX_COPPER then return nil end
        local x = { m = m, dm = dm, p = p, t = t, l = l, pf = fl == "!" }
        if dr then x.r = p + dr if x.r > MAX_COPPER then return nil end end
        if prev then
            if x.m < prev.dm then return nil end   -- a point starts where the previous one's last sighting is or later
            x.m = prev.m + x.m
        end
        if x.m < 1 or x.m + x.dm > MAX_MINUTE then return nil end
        ring[#ring + 1] = x
        prev = x
        if #ring > H2.RING then return nil end
    end
    if len ~= #s or s:byte(#s) == 59 then return nil end
    return ring
end

-- the daily text -> list of points with absolute days, or nil
local function DecodeDaily(s)
    if s == "" then return nil end
    local days, prev = {}, nil
    for _, seg in ipairs(Segments(s)) do
        local x = DayPoint(seg)
        if not x then return nil end
        if prev then
            if x.d < 1 then return nil end
            x.d = prev.d + x.d
        end
        if x.d < 1 or x.d > MAX_DAY then return nil end
        days[#days + 1] = x
        prev = x
    end
    return days
end

-- h2 text -> ring, days, or nil and why ("malformed")
function H2.DecodeH2(s)
    if type(s) ~= "string" or #s > 65536 then return nil, "malformed" end
    local bar = s:find("|", 1, true)
    if not bar then return nil, "malformed" end
    local colon = s:find(":", bar + 1, true)
    if not colon then return nil, "malformed" end
    local ring = DecodeRing(s:sub(1, bar - 1))
    local newest = Num(s:sub(bar + 1, colon - 1))
    local days = DecodeDaily(s:sub(colon + 1))
    if not (ring and newest and days) or days[#days].d ~= newest then return nil, "malformed" end
    -- the ring belongs to the daily points: its newest observation is on the newest day or earlier
    local last = ring[#ring]
    if last and floor((last.m + last.dm) / 1440) > newest then return nil, "malformed" end
    return ring, days
end

local function BucketPoint(seg)
    local k, s, n, nr, plo, dpm, dph, rm, drl, drh, tm, dtl, dth, lm, fl =
        seg:match("^(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d*),(%d*),(%d*),(%d+),(%d*),(%d*),(%d+)(!?~?)$")
    if not k then return nil end
    k, s, n, nr, plo, dpm, dph = Num(k), Num(s), Num(n), Num(nr), Num(plo), Num(dpm), Num(dph)
    rm, drl, drh, tm, dtl, dth, lm = Num(rm), Num(drl), Num(drh), Num(tm), Num(dtl), Num(dth), Num(lm)
    if not (k and s and n and nr and plo and dpm and dph and tm and lm) or rm == nil or drl == nil or drh == nil or dtl == nil or dth == nil then return nil end
    if (s ~= 7 and s ~= 14) or n < 1 or n > s or nr > n or plo < 1 or tm < 1 or lm < 1 then return nil end
    local b = { k = k, s = s, n = n, nr = nr, plo = plo, pm = plo + dpm, phi = plo + dpm + dph, tm = tm, lm = lm,
        pf = fl:find("!", 1, true) ~= nil, cf = fl:find("~", 1, true) ~= nil }
    if b.phi > MAX_COPPER or k * s + s - 1 > MAX_DAY then return nil end
    if nr > 0 then
        if not (rm and drl and drh) then return nil end
        b.rm, b.rlo, b.rhi = rm, rm - drl, rm + drh
        if b.rlo < 1 or b.rhi > MAX_COPPER then return nil end
    else
        if rm or (drl and not drh) or (drh and not drl) then return nil end
        if drl then
            if drl < 1 or drh < drl or drh > MAX_COPPER then return nil end
            b.rlo, b.rhi = drl, drh
        end
    end
    if (dtl and not dth) or (dth and not dtl) then return nil end
    if dtl then
        b.tlo, b.thi = tm - dtl, tm + dth
        if b.tlo < 1 then return nil end
    end
    return b
end

-- c2 text -> list of buckets, or nil and why
function H2.DecodeC2(s)
    if type(s) ~= "string" or s == "" or #s > 65536 then return nil, "malformed" end
    local bks, prev = {}, nil
    for _, seg in ipairs(Segments(s)) do
        local b = BucketPoint(seg)
        if not b then return nil, "malformed" end
        if prev then
            if b.k * b.s <= BucketEnd(prev) then return nil, "malformed" end   -- ascending, never overlapping
            if prev.s == 7 and b.s == 14 then return nil, "malformed" end      -- two-week buckets are always older than weekly ones
        end
        bks[#bks + 1] = b
        prev = b
        if #bks > 40 then return nil, "malformed" end
    end
    return bks
end

-- Both strings of one item, checked against each other: ring, days (nil when h2 is absent), buckets (nil when c2 is absent), and whether
-- one of them was refused (`bad` = "h2", "c2" or "both"). A bucket overlapping the daily points refuses c2 (the newer evidence wins).
function H2.Read(h2s, c2s)
    local ring, days, bks, bad
    if h2s ~= nil then
        ring, days = H2.DecodeH2(h2s)
        if not ring then ring, days, bad = nil, nil, "h2" end
    end
    if c2s ~= nil then
        bks = H2.DecodeC2(c2s)
        if not bks then bad = bad and "both" or "c2"
        elseif days and BucketEnd(bks[#bks]) >= days[1].d then bks, bad = nil, bad and "both" or "c2" end
    end
    return ring, days, bks, bad
end

---------------------------------------------------------------------------
-- Writing the text
---------------------------------------------------------------------------
local function RingSeg(m, x)
    return N(m) .. "," .. N(x.dm) .. "," .. N(x.p) .. "," .. (x.r and N(x.r - x.p) or "") .. "," .. N(x.t) .. "," .. N(x.l) .. (x.pf and "!" or "")
end

local function Moved(x)
    return x.plo ~= x.p or x.phi ~= x.p or x.tlo ~= x.t or x.thi ~= x.t or x.rlo ~= x.r or x.rhi ~= x.r
end

local function DaySeg(dd, x)
    local base = N(dd) .. "," .. N(x.p) .. "," .. (x.r and N(x.r - x.p) or "") .. "," .. N(x.t) .. "," .. N(x.l)
    local fl = x.pf and "!" or ""
    if x.n == 1 then return base .. fl end
    if x.cf then return base .. "," .. N(x.n) .. fl .. "~" end
    if not Moved(x) then return base .. "," .. N(x.n) .. fl end
    local rl, rh = "", ""
    if x.r then rl, rh = N(x.r - x.rlo), N(x.rhi - x.r) elseif x.rlo then rl, rh = N(x.rlo), N(x.rhi) end
    return base .. "," .. N(x.n) .. "," .. N(x.p - x.plo) .. "," .. N(x.phi - x.p) .. "," .. rl .. "," .. rh .. "," .. N(x.t - x.tlo) .. "," .. N(x.thi - x.t) .. fl
end
H2.DaySeg = DaySeg

local function BucketSeg(b)
    local rpart
    if b.rm then rpart = N(b.rm) .. "," .. N(b.rm - b.rlo) .. "," .. N(b.rhi - b.rm)
    elseif b.rlo then rpart = "," .. N(b.rlo) .. "," .. N(b.rhi)
    else rpart = ",," end
    local tpart = b.tlo and (N(b.tm - b.tlo) .. "," .. N(b.thi - b.tm)) or ","
    return N(b.k) .. "," .. N(b.s) .. "," .. N(b.n) .. "," .. N(b.nr) .. "," .. N(b.plo) .. "," .. N(b.pm - b.plo) .. "," .. N(b.phi - b.pm) .. "," ..
        rpart .. "," .. N(b.tm) .. "," .. tpart .. "," .. N(b.lm) .. (b.pf and "!" or "") .. (b.cf and "~" or "")
end

local function EncodeRing(ring)
    local out, prev = {}, nil
    for i, x in ipairs(ring) do
        out[i] = RingSeg(prev and (x.m - prev.m) or x.m, x)
        prev = x
    end
    return table.concat(out, ";")
end

-- ring, days, buckets -> h2 text (nil when there is no daily point), c2 text (nil when there is no bucket)
function H2.Encode(ring, days, bks)
    local h2s, c2s
    if days and #days > 0 then
        local out, prev = {}, nil
        for i, x in ipairs(days) do
            out[i] = DaySeg(prev and (x.d - prev.d) or x.d, x)
            prev = x
        end
        h2s = EncodeRing(ring or {}) .. "|" .. N(days[#days].d) .. ":" .. table.concat(out, ";")
    end
    if bks and #bks > 0 then
        local out = {}
        for i, b in ipairs(bks) do out[i] = BucketSeg(b) end
        c2s = table.concat(out, ";")
    end
    return h2s, c2s
end

---------------------------------------------------------------------------
-- The rules, on decoded lists
---------------------------------------------------------------------------
local function NewDay(day, o)
    return { d = day, p = o.p, r = o.r, t = o.t, l = o.l, n = 1, plo = o.p, phi = o.p, rlo = o.r, rhi = o.r, tlo = o.t, thi = o.t, pf = o.pf }
end

-- one more qualifying scan on the day of x: its values close the day, the ranges keep every earlier extreme
local function AddToDay(x, o)
    x.n = x.n + 1
    x.p, x.r, x.t, x.l = o.p, o.r, o.t, o.l
    if o.pf then x.pf = true end
    if x.cf then return end
    if o.p < x.plo then x.plo = o.p end
    if o.p > x.phi then x.phi = o.p end
    if o.t < x.tlo then x.tlo = o.t end
    if o.t > x.thi then x.thi = o.t end
    if o.r then
        if not x.rlo or o.r < x.rlo then x.rlo = o.r end
        if not x.rhi or o.r > x.rhi then x.rhi = o.r end
    end
end
H2.AddToDay, H2.NewDay = AddToDay, NewDay

local function ExpireRing(ring, M)
    local cutoff = M - H2.RING_MINUTES
    while ring[1] and ring[1].m + ring[1].dm < cutoff do table.remove(ring, 1) end
end

-- the observation o (minute om) after the ring's points; prevM is the minute of the market's previous history-feeding scan (nil when not known)
local function RingAdd(ring, o, om, prevM)
    local last = ring[#ring]
    if last and prevM and last.m + last.dm == prevM and last.p == o.p and last.r == o.r and last.t == o.t and last.l == o.l and last.pf == o.pf then
        last.dm = om - last.m
        return
    end
    ring[#ring + 1] = { m = om, dm = 0, p = o.p, r = o.r, t = o.t, l = o.l, pf = o.pf }
    while #ring > H2.RING do table.remove(ring, 1) end
end

-- the days of one week (or of the early fold) -> one weekly bucket
local function BucketOf(k, s, list)
    local b = { k = k, s = s, n = #list, nr = 0 }
    local sp, sr, st, sl = 0, 0, 0, 0
    for _, x in ipairs(list) do
        local plo, phi = x.plo or x.p, x.phi or x.p
        local tlo, thi = x.tlo or x.t, x.thi or x.t
        local rlo, rhi = x.rlo, x.rhi
        if x.cf then rlo, rhi = x.r, x.r b.cf = true end
        if x.pf then b.pf = true end
        if not b.plo or plo < b.plo then b.plo = plo end
        if not b.phi or phi > b.phi then b.phi = phi end
        if not b.tlo or tlo < b.tlo then b.tlo = tlo end
        if not b.thi or thi > b.thi then b.thi = thi end
        if rlo and (not b.rlo or rlo < b.rlo) then b.rlo = rlo end
        if rhi and (not b.rhi or rhi > b.rhi) then b.rhi = rhi end
        sp, st, sl = sp + x.p, st + x.t, sl + x.l
        if x.r then sr, b.nr = sr + x.r, b.nr + 1 end
    end
    b.pm, b.tm, b.lm = Mean(sp, b.n), Mean(st, b.n), Mean(sl, b.n)
    if b.nr > 0 then b.rm = Mean(sr, b.nr) end
    return b
end

-- a weekly bucket into the two-week bucket `into` (or a new one when `into` is nil); returns the two-week bucket
local function MergeInto(into, w)
    if not into then
        return { k = floor(w.k / 2), s = 14, n = w.n, nr = w.nr, plo = w.plo, pm = w.pm, phi = w.phi, rm = w.rm, rlo = w.rlo, rhi = w.rhi,
            tm = w.tm, tlo = w.tlo, thi = w.thi, lm = w.lm, pf = w.pf, cf = w.cf }
    end
    local n = into.n + w.n
    into.pm = Mean(into.pm * into.n + w.pm * w.n, n)
    into.tm = Mean(into.tm * into.n + w.tm * w.n, n)
    into.lm = Mean(into.lm * into.n + w.lm * w.n, n)
    if w.nr > 0 then into.rm = into.nr > 0 and Mean(into.rm * into.nr + w.rm * w.nr, into.nr + w.nr) or w.rm end
    into.n, into.nr = n, into.nr + w.nr
    if w.plo < into.plo then into.plo = w.plo end
    if w.phi > into.phi then into.phi = w.phi end
    if w.rlo and (not into.rlo or w.rlo < into.rlo) then into.rlo = w.rlo end
    if w.rhi and (not into.rhi or w.rhi > into.rhi) then into.rhi = w.rhi end
    if into.tlo and w.tlo then
        if w.tlo < into.tlo then into.tlo = w.tlo end
        if w.thi > into.thi then into.thi = w.thi end
    else
        into.tlo, into.thi = nil, nil   -- one side's supply range is gone: the merged one cannot claim one
    end
    into.pf, into.cf = into.pf or w.pf, into.cf or w.cf
    return into
end

-- folds the daily points before `before` (whole weeks) into weekly buckets after the existing ones
local function FoldDays(days, bks, before)
    local i = 1
    while days[i] and days[i].d < before do
        local w = floor(days[i].d / 7)
        local list = {}
        while days[i] and days[i].d < before and floor(days[i].d / 7) == w do list[#list + 1] = days[i] i = i + 1 end
        bks[#bks + 1] = BucketOf(w, 7, list)
    end
    for _ = 1, i - 1 do table.remove(days, 1) end
    return i > 1
end

-- what is due as of today/minute: the ring's reach, the fold, the two-week merge, the expiry. Changes the lists in place; true when anything changed.
local function Retain(ring, days, bks, T, M)
    local nr, nd, nb = #ring, #days, #bks
    ExpireRing(ring, M)
    local changed = FoldDays(days, bks, FoldBefore(T))
    -- merge weekly buckets whose pair of weeks ends more than WEEKLY_DAYS back
    local out = {}
    for _, b in ipairs(bks) do
        if b.s == 7 and 14 * floor(b.k / 2) + 13 < T - H2.WEEKLY_DAYS then
            local last = out[#out]
            if last and last.s == 14 and last.k == floor(b.k / 2) then MergeInto(last, b) else out[#out + 1] = MergeInto(nil, b) end
            changed = true
        else
            out[#out + 1] = b
        end
    end
    for i = 1, math.max(#out, #bks) do bks[i] = out[i] end
    while bks[1] and BucketEnd(bks[1]) < T - H2.RETAIN_DAYS do table.remove(bks, 1) changed = true end
    while days[1] and days[1].d < T - H2.RETAIN_DAYS do table.remove(days, 1) changed = true end
    return changed or #ring ~= nr or #days ~= nd or #bks ~= nb
end

-- everything due, decoded: is anything due as of today? (cheap tests, reading only the first fields of the texts)
local function H2Due(h2s, T, M)
    -- the first ring point's last sighting (absolute), and the first daily day (absolute)
    local m, dm = h2s:match("^(%d+),(%d+),")
    if m and tonumber(m) + tonumber(dm) < M - H2.RING_MINUTES then return true end
    local d = h2s:match(":(%d+)")
    return d ~= nil and tonumber(d) < FoldBefore(T)
end
local function C2Due(c2s, T)
    local k, s = c2s:match("^(%d+),(%d+),")
    if not k then return true end
    if tonumber(k) * tonumber(s) + tonumber(s) - 1 < T - H2.RETAIN_DAYS then return true end
    -- the first weekly bucket (they follow the two-week ones) is the oldest one that could be due for a merge
    local pos = 1
    while true do
        local bk, bs = c2s:match("^(%d+),(%d+),", pos)
        if not bk then return true end
        if bs == "7" then return 14 * floor(tonumber(bk) / 2) + 13 < T - H2.WEEKLY_DAYS end
        local e = c2s:find(";", pos, true)
        if not e then return false end
        pos = e + 1
    end
end
H2.H2Due, H2.C2Due = H2Due, C2Due

---------------------------------------------------------------------------
-- The append path: the newest daily point and the ring, without decoding the daily points in between
---------------------------------------------------------------------------
-- Checks done here before anything is appended: one "|" and one ":", the whole ring field by field, the FIRST and the NEWEST daily point
-- field by field, and the day sequence (every point starts with its day step, each at least 1, and they add up to the header's newest day,
-- so a truncated, reordered or spliced string is refused). The daily points in between are NOT read field by field here (that scan alone
-- cost more than the rest of the append, measured): the full decoder reads them at every fold (once a week for an item with history) and on
-- every read, and a string it refuses is absent to readers and replaced by the item's next observation that takes the full path.
local function FastSplit(s)
    if #s > 65536 then return nil end
    local bar = s:find("|", 1, true)
    if not bar or s:find("|", bar + 1, true) then return nil end
    local colon = s:find(":", bar + 1, true)
    if not colon or s:find(":", colon + 1, true) or s:find(":", 1, true) < bar then return nil end
    local newest = Num(s:sub(bar + 1, colon - 1))
    local first = s:match("^%d+", colon + 1)
    if not (newest and first) then return nil end
    local sum, count = Num(first), 1
    if not sum or sum < 1 then return nil end
    -- every ";" must be followed by a day step (positions in s: no copy of the daily text is made)
    local lastStart, firstEnd, pos = colon + 1, nil, colon + 1
    while true do
        local e = s:find(";", pos, true)
        if not e then break end
        local dd = s:match("^%d+", e + 1)
        local v = dd and Num(dd)
        if not v or v < 1 then return nil end
        sum, count, lastStart, pos = sum + v, count + 1, e + 1, e + 1
        firstEnd = firstEnd or e
        if count > 40 then return nil end
    end
    if sum ~= newest then return nil end
    return bar, colon, newest, lastStart, firstEnd, count
end

-- the new h2 text with o appended, or nil when the fast path does not apply (the caller then takes the full path)
local function FastAppend(s, o, om, day, prevM)
    local bar, colon, newest, lastStart, firstEnd, count = FastSplit(s)
    if not bar then return nil end
    local ring = DecodeRing(s:sub(1, bar - 1))
    if not ring then return nil end
    local last = DayPoint(s:sub(lastStart))
    if not last then return nil end
    if firstEnd then
        if not DayPoint(s:sub(colon + 1, firstEnd - 1)) then return nil end
    elseif last.d ~= newest then
        return nil
    end
    local lr = ring[#ring]
    if lr and (om < lr.m + lr.dm or floor((lr.m + lr.dm) / 1440) > newest) then return nil end   -- stale or inconsistent: decided by the full path
    if day < newest then return nil end
    ExpireRing(ring, om)
    RingAdd(ring, o, om, prevM)
    local head = EncodeRing(ring) .. "|" .. N(day) .. ":"
    if day == newest then
        local dd = last.d   -- as written: absolute when it is the only point, else the step from the previous one
        AddToDay(last, o)
        return head .. s:sub(colon + 1, lastStart - 1) .. DaySeg(dd, last)
    end
    return head .. s:sub(colon + 1) .. ";" .. DaySeg(day - newest, NewDay(day, o))
end

---------------------------------------------------------------------------
-- The calls Prices.lua makes
---------------------------------------------------------------------------
-- ctx = { T = the day being saved, M = its minute (time // 60), prevM = the minute of the market's previous history-feeding scan or nil }.
--
-- Update(h2s, c2s, o, ctx) -> h2s, c2s, path. The item was listed in the scan being saved with observation o (H2.Obs). path is
--   "fast"      the append path (c2 unchanged)
--   "full"      everything decoded and re-encoded (a fold, a merge or an expiry was due)
--   "new"       the item had no history (or only buckets)
--   "replaced"  the saved h2 was refused by the reader: it is replaced by this observation (a refused c2 is dropped the same way)
--   "stale"     o is older than what the item already holds (the clock moved back): nothing changes
function H2.Update(h2s, c2s, o, ctx)
    local T, M, prevM = ctx.T, ctx.M, ctx.prevM
    local om, day = floor(o.at / 60), floor(o.at / H2.DAY)
    if h2s ~= nil and type(h2s) == "string" and not (c2s ~= nil and C2Due(c2s, T)) and not H2Due(h2s, T, M) then
        local out = FastAppend(h2s, o, om, day, prevM)
        if out then return out, c2s, "fast" end
    end
    local ring, days, bks, bad = H2.Read(h2s, c2s)
    local path = "full"
    if h2s == nil or bad == "h2" or bad == "both" then
        ring, days, path = {}, {}, (h2s == nil) and "new" or "replaced"
    end
    if c2s ~= nil and not bks then bks = {} if path ~= "replaced" then path = "replaced" end end
    bks = bks or {}
    local lr, ld = ring[#ring], days[#days]
    if (lr and om < lr.m + lr.dm) or (ld and day < ld.d) then return h2s, c2s, "stale" end
    ExpireRing(ring, M)
    RingAdd(ring, o, om, prevM)
    if ld and ld.d == day then AddToDay(ld, o) else days[#days + 1] = NewDay(day, o) end
    -- a bucket can only be older than the daily points; an observation inside a bucket's days is refused like a stale one
    local lb = bks[#bks]
    if lb and BucketEnd(lb) >= day then return h2s, c2s, "stale" end
    Retain(ring, days, bks, T, M)
    local a, b = H2.Encode(ring, days, bks)
    return a, b, path
end

-- Retain(h2s, c2s, ctx) -> h2s, c2s, path for an item the scan being saved did NOT list: "same" (nothing due; the very same strings),
-- "full" (something expired, folded or merged), "malformed" (a string the reader refuses is left exactly as it is: absent to every reader,
-- replaced by the item's next observation). Either string may come back nil (nothing left).
function H2.Retain(h2s, c2s, ctx)
    local T, M = ctx.T, ctx.M
    local dueH = h2s ~= nil and (type(h2s) ~= "string" or H2Due(h2s, T, M))
    local dueC = c2s ~= nil and (type(c2s) ~= "string" or C2Due(c2s, T))
    if not dueH and not dueC then return h2s, c2s, "same" end
    local ring, days, bks, bad = H2.Read(h2s, c2s)
    if bad then return h2s, c2s, "malformed" end
    ring, days, bks = ring or {}, days or {}, bks or {}
    if not Retain(ring, days, bks, T, M) then return h2s, c2s, "same" end
    local a, b = H2.Encode(ring, days, bks)
    return a, b, "full"
end

-- The budget guard's steps (section 7.4), for one item: Compact(step, h2s, c2s, ctx) -> h2s, c2s, changed. Never touches the ring, the daily
-- points of the last PROTECT_DAYS days, closing values or price ranges of buckets. A string the reader refuses is left as it is.
--   1  condense the day ranges of daily points PROTECT_DAYS or more days old (closing values and the scan count stay)
--   2  for an item listed on fewer than SPARSE_DAYS of the last DAILY_DAYS days: fold its whole weeks that are entirely PROTECT_DAYS or more
--      days old into weekly buckets early
--   3  drop the supply range (fewest / most items) of buckets ending more than WEEKLY_DAYS back
-- Is a step of the guard due for this item at all? Read from the text without decoding it (the guard runs over every item of a market
-- at every commit while the market is over budget, and most items have nothing left to condense): the daily points' days from their day
-- steps, a full-form point by its field count (12 fields, so 11 commas; the short forms have 4 or 5), the buckets by DecodeC2 (a few).
-- True also when the text does not look like this format (the step then reads it properly, and leaves a refused string as it is).
local function CompactDue(step, h2s, c2s, T)
    if step == 3 then
        local bks = c2s and H2.DecodeC2(c2s)
        if not bks then return c2s ~= nil end
        for _, b in ipairs(bks) do if b.tlo and BucketEnd(b) < T - H2.WEEKLY_DAYS then return true end end
        return false
    end
    if type(h2s) ~= "string" then return false end
    local colon = h2s:find(":", 1, true)
    if not colon then return true end
    local pos, d, recent, first = colon + 1, nil, 0, nil
    while true do
        local dd = h2s:match("^%d+", pos)
        if not dd then return true end
        d = d and (d + tonumber(dd)) or tonumber(dd)
        first = first or d
        if d >= T - H2.DAILY_DAYS + 1 then recent = recent + 1 end
        local e = h2s:find(";", pos, true)
        if step == 1 and T - d >= H2.PROTECT_DAYS then
            local commas, c = 0, pos
            while commas < 6 do
                c = h2s:find(",", c, true)
                if not c or (e and c > e) then break end
                commas, c = commas + 1, c + 1
            end
            if commas >= 6 then return true end
        end
        if not e then break end
        pos = e + 1
    end
    if step == 2 then return recent < H2.SPARSE_DAYS and first < 7 * floor((T - H2.PROTECT_DAYS + 1) / 7) end
    return false
end
H2.CompactDue = CompactDue

function H2.Compact(step, h2s, c2s, ctx)
    local T = ctx.T
    if not CompactDue(step, h2s, c2s, T) then return h2s, c2s, false end
    local ring, days, bks, bad = H2.Read(h2s, c2s)
    if bad then return h2s, c2s, false end
    ring, days, bks = ring or {}, days or {}, bks or {}
    local changed = false
    if step == 1 then
        for _, x in ipairs(days) do
            if T - x.d >= H2.PROTECT_DAYS and x.n >= 2 and not x.cf and Moved(x) then
                x.cf, x.plo, x.phi, x.rlo, x.rhi, x.tlo, x.thi = true, nil, nil, nil, nil, nil, nil
                changed = true
            end
        end
    elseif step == 2 then
        local recent = 0
        for _, x in ipairs(days) do if x.d >= T - H2.DAILY_DAYS + 1 then recent = recent + 1 end end
        if recent < H2.SPARSE_DAYS then
            -- whole weeks whose last day is PROTECT_DAYS or more days old: days before the start of the week holding day T - PROTECT_DAYS + 1
            changed = FoldDays(days, bks, 7 * floor((T - H2.PROTECT_DAYS + 1) / 7))
        end
    elseif step == 3 then
        for _, b in ipairs(bks) do
            if b.tlo and BucketEnd(b) < T - H2.WEEKLY_DAYS then b.tlo, b.thi, changed = nil, nil, true end
        end
    end
    if not changed then return h2s, c2s, false end
    local a, b = H2.Encode(ring, days, bks)
    return a, b, true
end
