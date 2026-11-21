-- TwichUI: the gold ledger's cost basis and realized results (docs/workshop/gold-ledger.md, "Cost basis and realized profit")
--
-- A SEPARATE economic interpretation of activity the cash ledger has already verified. It never records money, never reads a
-- balance and never creates, changes or reclassifies a cash entry: Ledger.lua (PLAYER_MONEY / GetMoney) stays the only authority
-- for cash flow. This module only listens when Ledger.lua attaches EVIDENCE to an existing journal entry (Lg.OnAttached) and then
-- remembers what that verified transaction cost or earned:
--
--   vendorBuy   -> a LOT: this item identity, this quantity, exactly this much gold (exact merchant price, exact bag increase).
--   ahBuy       -> a LOT in transit: exact reviewed total for the exact item. It joins the carried stock only when the mailbox
--                  attachment that delivers it is taken and the bags show exactly that increase (LedgerCostWatch.lua).
--   craft       -> a LOT whose cost is the allocated cost of the consumed materials (LedgerCostWatch.lua); unknown inputs make the
--                  cost UNKNOWN, never zero.
--   vendorSell  -> a RESULT: the exact payment against the cost of the exact units sold, when those units can be identified.
--   ahSale      -> a RESULT with no cost: a seller invoice names an item but proves no item identity, so no lot is ever matched
--                  to it (names and prices that look similar are not lineage). Collected, fee and gross are kept from the invoice.
--
-- THE IDENTIFIED-STOCK RULE. A sale is matched to cost only when the carried quantity of that exact item identity equals the
-- quantity of identified lots (so every carried unit is a known lot unit) and covers the sale. If anything else is in the bags
-- (older stock, loot, a trade), or an identified unit is elsewhere (bank, mail), the sold units cannot be told apart: the result
-- is "unavailable" and the pool's lots are DISCARDED (their units can no longer be separated from other stock). Unknown cost is
-- never treated as zero, and no FIFO guess is made across stock that is not identified.
--
-- Allocation inside a set of genuinely identified lots of one identity is FIFO (oldest lot first). Whole-copper apportionment:
-- the cost of the first u of a lot's q units is floor(cost * u / q), so the pieces always add up to exactly the lot's cost.
--
-- TwichUILedgerDB.cost = { v = 1, chars = { ["Name - Realm"] = {
--     nextLot, nextResult, nextCraft,
--     lots    = { { id, t, k (identity key), i (item id), q (acquired), r (remaining), c (total copper, nil = unknown),
--                   s ("vendor"|"ah"|"craft"), x (journal entry id), f (craft id), p (profession id), tq (units still in the mail) } },
--     results = { { id, t, src ("vendorSell"|"ahSale"), x (entry id), i, k, n (name), q, a (collected), c (verified cost), g, fee, d,
--                   st ("ok"|"incomplete"|"unknown"), w (why unavailable), pf (profession), al = { { l, q, c, s, f, p } } } },
--     crafts  = { { id, t, r (recipe), p (profession id), i, q, c (cost, nil = unknown), st ("ok"|"incomplete"), m = { { i, q, c } } } },
--     profs   = { [professionId] = "name" },
--     posts   = { { id, t, k, i, n (name from the link), q, u (unit price), dep (deposit), dur, a (auction id), ac (auction ids),
--                   st ("posted"|"sold"|"cancelled"|"ended"), cs ("ok"|"unknown"|"nolot"|"mixed"|"missing"|"short"|"nostock"),
--                   c (cost of the posted units, nil = unknown), al = { ... } } },      V5 posting provenance (below)
-- } } }
-- It lives inside TwichUILedgerDB (no new saved variable) and carries its own version: a newer component is left untouched.

local R = TwichUI
local P = R.Persist
local L = R.Ledger
local C = {}
R.LedgerCost = C

C.VERSION = 1
C.MAX_LOTS = 400          -- open lots per character; past this the oldest is forgotten (its units become unknown cost)
C.LOT_DAYS = 180          -- an open lot older than this is forgotten
C.TRANSIT_DAYS = 45       -- mail holds an Auction House delivery 30 days; a lot still in the mail after this is forgotten
C.MAX_RESULTS = 500
C.MAX_CRAFTS = 200
C.MAX_ALLOC = 6
C.MAX_QTY = 10000000      -- a lot's quantity bound: keeps every product below exact-integer range
C.MAX_PROFS = 24
C.MAX_POSTS = 200         -- remembered postings per character
C.POST_DAYS = 35          -- an auction lasts two days at most, and its mail thirty: a posting older than this is forgotten
C.MAX_POST_IDS = 8
local MAX = L.MAX_MONEY
local DAY = 86400
local MAX_ITEM = 2147483647

local blocked = false           -- a newer component, or no usable ledger: nothing is read or written
local cleaned = {}
local stats = { lots = 0, results = 0, crafts = 0, duplicate = 0, mixed = 0, unresolved = 0, refused = 0, expired = 0, errors = 0 }

---------------------------------------------------------------------------
-- Small checks
---------------------------------------------------------------------------
local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Whole(v, lo, hi)
    v = Plain(v)
    if type(v) ~= "number" or not tostring(v):find("^[%d%.eE%+%-]+$") or v < lo or v > hi or math.floor(v) ~= v then return nil end
    return v
end
local function Text(v, max)
    v = Plain(v)
    if type(v) ~= "string" or v == "" then return nil end
    v = v:gsub("[%c|]", " ")
    if #v > max then v = v:sub(1, max) end
    return v
end
local function Now()
    local f = GetServerTime or time
    local ok, t = pcall(f)
    return ok and Whole(t, 0, 4102444800) or nil
end

-- floor(cost * u / q) for 0 <= u <= q <= MAX_QTY without leaving exact-integer range.
local function Scaled(cost, u, q)
    local b = cost % q
    local a = (cost - b) / q
    return a * u + math.floor(b * u / q)
end
C.Scaled = Scaled

---------------------------------------------------------------------------
-- Item identity. An item id alone is not an identity for gear that varies: the supported variant fields are the enchant, the gems,
-- the random suffix and the bonus ids. Fields that do not change what the item is (unique id, level, spec) are ignored. A link
-- that cannot be read yields the plain id key, never a guess about variants.
---------------------------------------------------------------------------
function C.Key(link, id)
    link = Plain(link)
    local fields
    if type(link) == "string" then
        local body = link:match("item:([%-%d:]*)")
        if body then
            fields = {}
            for part in (body .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = tonumber(part) or 0 end
        end
    end
    local item = Whole(id, 1, MAX_ITEM) or (fields and Whole(fields[1], 1, MAX_ITEM))
    if not item then return nil end
    if fields and fields[1] == item then
        local parts = {}
        if (fields[2] or 0) ~= 0 then parts[#parts + 1] = "e" .. fields[2] end
        local gems = {}
        for g = 3, 6 do if (fields[g] or 0) ~= 0 then gems[#gems + 1] = fields[g] end end
        if #gems > 0 then parts[#parts + 1] = "g" .. table.concat(gems, ",") end
        if (fields[7] or 0) ~= 0 then parts[#parts + 1] = "s" .. fields[7] end
        local n = fields[13] or 0
        if n > 0 and n <= 16 then
            local bonus = {}
            for b = 1, n do if fields[13 + b] then bonus[#bonus + 1] = fields[13 + b] end end
            table.sort(bonus)
            if #bonus > 0 then parts[#parts + 1] = "b" .. table.concat(bonus, ",") end
        end
        if #parts > 0 then return "i" .. item .. ":" .. table.concat(parts, ":") end
    end
    return "i" .. item
end

---------------------------------------------------------------------------
-- The store
---------------------------------------------------------------------------
local function CleanLot(t)
    if type(t) ~= "table" then return nil end
    local id, q, r = Whole(t.id, 1, MAX), Whole(t.q, 1, C.MAX_QTY), Whole(t.r, 1, C.MAX_QTY)
    local i, at = Whole(t.i, 1, MAX_ITEM), Whole(t.t, 0, 4102444800)
    if not (id and q and r and i and at) or r > q then return nil end
    local s = (t.s == "vendor" or t.s == "ah" or t.s == "craft") and t.s or nil
    if not s then return nil end
    local tq = Whole(t.tq, 1, r)
    local k = Text(t.k, 160)
    if not k and not tq then return nil end   -- carried stock needs an identity; only a lot still in the mail may lack one
    local c = Whole(t.c, 0, MAX)
    return { id = id, t = at, k = k, i = i, q = q, r = r, c = c, s = s, x = Whole(t.x, 1, MAX), f = Whole(t.f, 1, MAX),
        p = Whole(t.p, 1, MAX_ITEM), tq = tq }
end

local function CleanAlloc(t)
    if type(t) ~= "table" then return nil end
    local l, q = Whole(t.l, 1, MAX), Whole(t.q, 1, C.MAX_QTY)
    if not (l and q) then return nil end
    local s = (t.s == "vendor" or t.s == "ah" or t.s == "craft") and t.s or nil
    return { l = l, q = q, c = Whole(t.c, 0, MAX), s = s, f = Whole(t.f, 1, MAX), p = Whole(t.p, 1, MAX_ITEM) }
end

local function CleanResult(t)
    if type(t) ~= "table" then return nil end
    local id, at, q, a = Whole(t.id, 1, MAX), Whole(t.t, 0, 4102444800), Whole(t.q, 1, C.MAX_QTY), Whole(t.a, 0, MAX)
    if not (id and at and q and a) or (t.src ~= "vendorSell" and t.src ~= "ahSale") then return nil end
    local st = (t.st == "ok" or t.st == "incomplete" or t.st == "unknown") and t.st or "unknown"
    local out = { id = id, t = at, src = t.src, x = Whole(t.x, 1, MAX), i = Whole(t.i, 1, MAX_ITEM), k = Text(t.k, 160),
        n = Text(t.n, 60), q = q, a = a, c = Whole(t.c, 0, MAX), g = Whole(t.g, 0, MAX), fee = Whole(t.fee, 0, MAX),
        d = Whole(t.d, 0, MAX), st = st, w = Text(t.w, 24), pf = Whole(t.pf, 1, MAX_ITEM), al = {} }
    if st == "ok" and not out.c then out.st = "incomplete" end
    if out.st ~= "ok" then out.c, out.pf = nil, nil end
    if type(t.al) == "table" then
        for _, row in ipairs(P.Sequence(t.al)) do
            local clean = CleanAlloc(row)
            if clean and #out.al < C.MAX_ALLOC then out.al[#out.al + 1] = clean end
        end
    end
    return out
end

local function CleanCraft(t)
    if type(t) ~= "table" then return nil end
    local id, at, r, i, q = Whole(t.id, 1, MAX), Whole(t.t, 0, 4102444800), Whole(t.r, 1, MAX), Whole(t.i, 1, MAX_ITEM), Whole(t.q, 1, C.MAX_QTY)
    if not (id and at and r and i and q) then return nil end
    local out = { id = id, t = at, r = r, p = Whole(t.p, 1, MAX_ITEM), i = i, q = q, c = Whole(t.c, 0, MAX), m = {} }
    out.st = (out.c and t.st == "ok") and "ok" or "incomplete"
    if type(t.m) == "table" then
        for _, row in ipairs(P.Sequence(t.m)) do
            local mi, mq = type(row) == "table" and Whole(row.i, 1, MAX_ITEM), type(row) == "table" and Whole(row.q, 1, C.MAX_QTY)
            if mi and mq and #out.m < 8 then out.m[#out.m + 1] = { i = mi, q = mq, c = Whole(row.c, 0, MAX) } end
        end
    end
    return out
end

local POST_STATES = { posted = true, sold = true, cancelled = true, ended = true }
local COST_STATES = { ok = true, unknown = true, nolot = true, mixed = true, missing = true, short = true, nostock = true }
local function CleanPost(t)
    if type(t) ~= "table" then return nil end
    local id, at, q, i = Whole(t.id, 1, MAX), Whole(t.t, 0, 4102444800), Whole(t.q, 1, C.MAX_QTY), Whole(t.i, 1, MAX_ITEM)
    local k = Text(t.k, 160)
    if not (id and at and q and i and k) then return nil end
    local out = { id = id, t = at, k = k, i = i, q = q, n = Text(t.n, 60), u = Whole(t.u, 1, MAX), dep = Whole(t.dep, 0, MAX),
        dur = Whole(t.dur, 1, 3), a = Whole(t.a, 1, MAX), st = POST_STATES[t.st] and t.st or "ended",
        cs = COST_STATES[t.cs] and t.cs or "unknown", c = Whole(t.c, 0, MAX), al = {}, ac = {} }
    if out.cs ~= "ok" then out.c = nil end
    if out.cs == "ok" and not out.c then out.cs = "unknown" end
    if type(t.ac) == "table" then
        for _, v in ipairs(P.Sequence(t.ac)) do
            local a = Whole(v, 1, MAX)
            if a and #out.ac < C.MAX_POST_IDS then out.ac[#out.ac + 1] = a end
        end
    end
    if type(t.al) == "table" then
        for _, row in ipairs(P.Sequence(t.al)) do
            local clean = CleanAlloc(row)
            if clean and #out.al < C.MAX_ALLOC then out.al[#out.al + 1] = clean end
        end
    end
    return out
end

local function CleanList(list, clean, counterKey, max)
    local out, top = {}, 0
    if type(list) == "table" then
        for _, row in ipairs(P.Sequence(list)) do
            local c = clean(row)
            if c then
                out[#out + 1] = c
                if c.id > top then top = c.id end
            else
                P.Repair("ledger-cost-dropped")
            end
        end
    end
    while #out > max do table.remove(out, 1) end
    return out, top
end

local function CleanRec(rec)
    local lots, topLot = CleanList(rec.lots, CleanLot, "lots", C.MAX_LOTS)
    local results, topResult = CleanList(rec.results, CleanResult, "results", C.MAX_RESULTS)
    local crafts, topCraft = CleanList(rec.crafts, CleanCraft, "crafts", C.MAX_CRAFTS)
    rec.lots, rec.results, rec.crafts = lots, results, crafts
    local posts, topPost = CleanList(rec.posts, CleanPost, "posts", C.MAX_POSTS)
    rec.posts = posts
    local np = Whole(rec.nextPost, 1, MAX)
    rec.nextPost = (np and np > topPost) and np or topPost + 1
    local n = Whole(rec.nextLot, 1, MAX)
    rec.nextLot = (n and n > topLot) and n or topLot + 1
    n = Whole(rec.nextResult, 1, MAX)
    rec.nextResult = (n and n > topResult) and n or topResult + 1
    n = Whole(rec.nextCraft, 1, MAX)
    rec.nextCraft = (n and n > topCraft) and n or topCraft + 1
    local profs, count = {}, 0
    if type(rec.profs) == "table" then
        for k, v in pairs(rec.profs) do
            local id, name = Whole(k, 1, MAX_ITEM), Text(v, 40)
            if id and name and count < C.MAX_PROFS then profs[id] = name; count = count + 1 end
        end
    end
    rec.profs = profs
end

-- Drops what has aged out: lots that stayed open too long, deliveries that never came, old results. Deterministic.
local function Compact(rec, now)
    local lotLimit, transitLimit = now - C.LOT_DAYS * DAY, now - C.TRANSIT_DAYS * DAY
    local kept = {}
    for _, lot in ipairs(rec.lots) do
        -- an old open lot, or a delivery that never came (even if part of it did), is forgotten whole: its units become unknown cost
        if lot.t < lotLimit or (lot.tq and lot.t < transitLimit) then stats.expired = stats.expired + 1
        else kept[#kept + 1] = lot end
    end
    rec.lots = kept
    while #rec.lots > C.MAX_LOTS do table.remove(rec.lots, 1); stats.expired = stats.expired + 1 end
    local limit = now - L.RETAIN_DAYS * DAY
    local out = {}
    for _, r in ipairs(rec.results) do if r.t >= limit then out[#out + 1] = r end end
    rec.results = out
    while #rec.results > C.MAX_RESULTS do table.remove(rec.results, 1) end
    out = {}
    for _, cr in ipairs(rec.crafts) do if cr.t >= limit then out[#out + 1] = cr end end
    rec.crafts = out
    while #rec.crafts > C.MAX_CRAFTS do table.remove(rec.crafts, 1) end
    if type(rec.posts) == "table" then
        local postLimit = now - C.POST_DAYS * DAY
        out = {}
        for _, post in ipairs(rec.posts) do if post.t >= postLimit then out[#out + 1] = post end end
        rec.posts = out
        while #rec.posts > C.MAX_POSTS do table.remove(rec.posts, 1) end
    end
end

function C.Init()
    blocked = false
    local db = TwichUILedgerDB
    if L.Held() or type(db) ~= "table" then blocked = true return end
    local c = db.cost
    if c == nil then return end
    if type(c) ~= "table" then db.cost = nil; P.Repair("ledger-cost-repaired") return end
    if c.v ~= nil and not P.IsCount(c.v) then c.v = nil; P.Repair("ledger-cost-repaired") end
    if c.v and c.v > C.VERSION then blocked = true; P.Repair("future-schema") end   -- left untouched, never read
end

-- The character's cost record. make: create it when missing. Reading never makes one.
local function Rec(key, make)
    if blocked or not key or L.Held() then return nil end
    local db = TwichUILedgerDB
    if type(db) ~= "table" then return nil end
    local root = db.cost
    if type(root) ~= "table" or type(root.chars) ~= "table" then
        if not make then return nil end
        root = { v = C.VERSION, chars = {} }
        db.cost = root
    end
    root.v = C.VERSION
    local rec = root.chars[key]
    if type(rec) ~= "table" then
        if not make then return nil end
        local count = 0
        for _ in pairs(root.chars) do count = count + 1 end
        if count >= L.MAX_CHARS then return nil end
        rec = {}
        root.chars[key] = rec
        cleaned[key] = nil
    end
    if not cleaned[key] then
        CleanRec(rec)
        cleaned[key] = true
        local now = Now()
        if now then Compact(rec, now) end
    end
    return rec
end
C.Rec = Rec

---------------------------------------------------------------------------
-- Pools: the identified stock of one identity
---------------------------------------------------------------------------
local function Delivered(lot) return lot.r - (lot.tq or 0) end

-- Units of `key` in identified lots that have reached the bags.
function C.Pool(rec, key)
    local n = 0
    for _, lot in ipairs(rec.lots) do
        if lot.k == key then n = n + Delivered(lot) end
    end
    return n
end

-- The units of this identity can no longer be separated from other stock: its lots are forgotten. Counted, never silent.
-- Units of such a lot that are still in the mail keep their own (separate) lot, with exactly their share of the cost (the last
-- units of a lot are the ones not yet delivered).
function C.Disturb(rec, key)
    local kept, lost = {}, 0
    for _, lot in ipairs(rec.lots) do
        if lot.k == key then
            lost = lost + 1
            if lot.tq then
                local share = lot.c and (lot.c - Scaled(lot.c, lot.q - lot.tq, lot.q)) or nil
                lot.k, lot.r, lot.q, lot.c = nil, lot.tq, lot.tq, share
                kept[#kept + 1] = lot
            end
        else kept[#kept + 1] = lot end
    end
    rec.lots = kept
    if lost > 0 then stats.unresolved = stats.unresolved + lost end
    return lost
end

local function Extend(rec, lot)
    lot.id = rec.nextLot
    rec.nextLot = rec.nextLot + 1
    rec.lots[#rec.lots + 1] = lot
    while #rec.lots > C.MAX_LOTS do table.remove(rec.lots, 1); stats.expired = stats.expired + 1 end
    stats.lots = stats.lots + 1
    return lot
end

-- Takes `qty` units of `key` out of the identified stock, FIFO among identified lots. carried = the units of this identity the bags
-- hold right now (before the units leave). Returns true, allocations, cost (nil when any allocated lot has an unknown cost)
-- or false, reason: "nolot" (no verified acquisition), "mixed" (more in the bags than identified lots), "missing" (fewer),
-- "short". A refusal other than "nolot" forgets the pool's lots.
function C.Take(rec, key, qty, carried)
    qty = Whole(qty, 1, C.MAX_QTY)
    local pool = C.Pool(rec, key)
    if pool == 0 then return false, "nolot" end
    carried = Whole(carried, 0, MAX)
    if not (qty and carried) then C.Disturb(rec, key) return false, "short" end
    if carried ~= pool then
        C.Disturb(rec, key)
        stats.mixed = stats.mixed + 1
        return false, carried > pool and "mixed" or "missing"
    end
    if qty > pool then C.Disturb(rec, key) return false, "short" end
    local left, allocs, total = qty, {}, 0
    local complete = true
    local kept = {}
    for _, lot in ipairs(rec.lots) do
        if lot.k == key and left > 0 and Delivered(lot) > 0 then
            local take = math.min(left, Delivered(lot))
            local used = lot.q - lot.r
            local share
            if lot.c then share = Scaled(lot.c, used + take, lot.q) - Scaled(lot.c, used, lot.q) end
            allocs[#allocs + 1] = { l = lot.id, q = take, c = share, s = lot.s, f = lot.f, p = lot.p }
            if share then total = total + share else complete = false end
            lot.r = lot.r - take
            left = left - take
        end
        if lot.r > 0 then kept[#kept + 1] = lot end
    end
    rec.lots = kept
    return true, allocs, complete and total or nil
end

-- Merges allocations of the same origin so a result stays small; { allocations, truncated }.
local function Compress(allocs)
    local out, index = {}, {}
    for _, a in ipairs(allocs) do
        local key = (a.s or "?") .. ":" .. (a.f or 0) .. ":" .. (a.p or 0)
        local row = index[key]
        if row then
            row.q = row.q + a.q
            if row.c and a.c then row.c = row.c + a.c else row.c = nil end
        else
            row = { l = a.l, q = a.q, c = a.c, s = a.s, f = a.f, p = a.p }
            index[key] = row
            out[#out + 1] = row
        end
    end
    if #out > C.MAX_ALLOC then
        local cut = {}
        for i = 1, C.MAX_ALLOC do cut[i] = out[i] end
        return cut, true
    end
    return out, false
end

local function HasResult(rec, entry, src, n)
    for i = #rec.results, 1, -1 do
        local r = rec.results[i]
        if r.x == entry and r.src == src and (not n or r.n == n) then return true end
    end
    return false
end

local function AddResult(rec, r)
    r.id = rec.nextResult
    rec.nextResult = rec.nextResult + 1
    rec.results[#rec.results + 1] = r
    while #rec.results > C.MAX_RESULTS do table.remove(rec.results, 1) end
    stats.results = stats.results + 1
    return r
end

-- The profession a set of allocations belongs to: only when every unit came from crafts of one profession.
local function Profession(allocs)
    local prof
    for _, a in ipairs(allocs) do
        if a.s ~= "craft" or not a.p then return nil end
        if prof and prof ~= a.p then return nil end
        prof = a.p
    end
    return prof
end

---------------------------------------------------------------------------
-- Evidence from the cash ledger: an exact, already-recorded transaction was verified
---------------------------------------------------------------------------
local function OnBuy(rec, e, ev)
    local st = ev.stock
    local qty, paid = Whole(ev.qty, 1, C.MAX_QTY), -ev.amount
    if not (st and qty and paid > 0) or st.after - st.before ~= qty then stats.refused = stats.refused + 1 return end
    for _, lot in ipairs(rec.lots) do if lot.x == e.id and lot.s == "vendor" then stats.duplicate = stats.duplicate + 1 return end end
    if C.Pool(rec, st.key) ~= st.before then   -- the bags held other stock of this identity: this lot could not be told from it
        C.Disturb(rec, st.key)
        stats.mixed = stats.mixed + 1
        return
    end
    Extend(rec, { t = e.t, k = st.key, i = ev.item, q = qty, r = qty, c = paid, s = "vendor", x = e.id })
end

local function OnSell(rec, e, ev)
    local qty, paid = Whole(ev.qty, 1, C.MAX_QTY), ev.amount
    if not qty or HasResult(rec, e.id, "vendorSell") then stats.duplicate = stats.duplicate + 1 return end
    local r = { t = e.t, src = "vendorSell", x = e.id, i = ev.item, q = qty, a = paid, st = "unknown", al = {} }
    local st = ev.stock
    if st and st.before - st.after == qty then
        r.k = st.key
        local ok, allocs, cost = C.Take(rec, st.key, qty, st.before)
        if ok then
            local rows, cut = Compress(allocs)
            r.al = rows
            if cost and not cut then
                r.st, r.c, r.pf = "ok", cost, Profession(rows)
            else
                r.st = "incomplete"
                r.w = cut and "manylots" or "unknowncost"
            end
        else
            r.w = allocs   -- the reason
        end
    else
        r.w = "nostock"
    end
    AddResult(rec, r)
end

local function OnAhBuy(rec, e, ev)
    local qty, paid = Whole(ev.qty, 1, C.MAX_QTY), -ev.amount
    if not (qty and paid > 0 and ev.item) then stats.refused = stats.refused + 1 return end
    for _, lot in ipairs(rec.lots) do if lot.x == e.id and lot.s == "ah" then stats.duplicate = stats.duplicate + 1 return end end
    Extend(rec, { t = e.t, i = ev.item, q = qty, r = qty, tq = qty, c = paid, s = "ah", x = e.id })
end

local function OnAhSale(rec, e, ev)
    -- one collected payment is attached once; its results are added together (two sales of the same item are two results)
    if HasResult(rec, e.id, "ahSale") then stats.duplicate = stats.duplicate + 1 return end
    local s = ev.settlement
    if s and type(s.invoices) == "table" then
        for _, inv in ipairs(s.invoices) do
            AddResult(rec, { t = e.t, src = "ahSale", x = e.id, n = inv.n or "Sold item", q = inv.q or 1, a = inv.c, g = inv.g, fee = inv.f, d = inv.d,
                st = "unknown", w = "auctionid", al = {} })
        end
    elseif type(ev.parts) == "table" and #ev.parts > 1 then
        -- One reconciled payment: results for seller portions only; other mail remains a cash remainder.
        for _, p in ipairs(ev.parts) do
            if p.sale == true then
                local inv = p.settlement
                AddResult(rec, { t = e.t, src = "ahSale", x = e.id, n = p.n or "Sold item", q = p.q or 1, a = p.c,
                    g = inv and inv.g, fee = inv and inv.f, d = inv and inv.d, st = "unknown", w = "auctionid", al = {} })
            end
        end
    elseif e.a > 0 then
        AddResult(rec, { t = e.t, src = "ahSale", x = e.id, n = ev.note, q = ev.qty or 1, a = e.a, st = "unknown", w = "auctionid", al = {} })
    end
end

-- The results one cash entry produced (its components, for the transaction details). Read only.
function C.ResultsFor(char, entry)
    local rec = Rec(char, false)
    local out = {}
    if not rec then return out end
    for _, r in ipairs(rec.results) do if r.x == entry then out[#out + 1] = r end end
    return out
end

local function Dispatch(key, e, ev)
    local rec = Rec(key, true)
    if not rec then return end
    local now = Now()
    if now then Compact(rec, now) end
    if ev.kind == "vendorBuy" then OnBuy(rec, e, ev)
    elseif ev.kind == "vendorSell" then OnSell(rec, e, ev)
    elseif ev.kind == "ahBuy" then OnAhBuy(rec, e, ev)
    elseif ev.kind == "ahSale" or ev.kind == "mail" and ev.parts then OnAhSale(rec, e, ev) end
end

local function Attached(key, e, ev)
    if blocked then return end
    local ok, err
    if R.Perf and R.Perf.Call then ok, err = pcall(R.Perf.Call, "ledger.cost", Dispatch, key, e, ev)
    else ok, err = pcall(Dispatch, key, e, ev) end
    if not ok then
        stats.errors = stats.errors + 1
        if R.Fault then R.Fault("gold ledger cost basis", err) end
    end
end

---------------------------------------------------------------------------
-- Deliveries and crafts (reported by LedgerCostWatch.lua once verified)
---------------------------------------------------------------------------
-- An Auction House purchase reached the bags: `count` units of item `item`, identity `key`, carried before = `before`.
-- Needs exactly one lot in transit that can supply it (or several of the same unit price). Returns true or false, reason.
function C.Deliver(char, item, key, count, before)
    local rec = Rec(char, false)
    count = Whole(count, 1, C.MAX_QTY)
    if not (rec and count and key) then return false, "nolot" end
    local candidates = {}
    for _, lot in ipairs(rec.lots) do
        if lot.s == "ah" and lot.tq and lot.i == item and (lot.k == nil or lot.k == key) and lot.tq >= count then candidates[#candidates + 1] = lot end
    end
    if #candidates == 0 then return false, "nolot" end
    local first = candidates[1]
    for i = 2, #candidates do
        local o = candidates[i]
        -- equal unit price (exact cross-multiplication) means the choice cannot change any cost
        if not (first.c and o.c and first.c * o.q == o.c * first.q) then return false, "ambiguous" end
    end
    if C.Pool(rec, key) ~= before then   -- other stock of this identity was in the bags: the delivery cannot be told from it
        C.Disturb(rec, key)
        first.tq, first.r = first.tq - count, first.r - count
        if first.r <= 0 then
            for i, lot in ipairs(rec.lots) do if lot == first then table.remove(rec.lots, i) break end end
        end
        stats.mixed = stats.mixed + 1
        return false, "mixed"
    end
    first.k = key
    first.tq = first.tq - count
    if first.tq == 0 then first.tq = nil end
    L.Touch()
    return true
end

-- A verified craft. craft = { recipe, profession, professionName, out = { key, item, qty, before }, mats = { { key, item, qty, before } } }
-- Consumes the materials from identified stock (cost known only for identified lots), records the craft and the output lot.
function C.Crafted(char, craft)
    local rec = Rec(char, true)
    if not (rec and type(craft) == "table" and type(craft.mats) == "table" and type(craft.out) == "table") then return false, "bad" end
    local now = Now()
    if not now then return false, "bad" end
    local out = craft.out
    local qty = Whole(out.qty, 1, C.MAX_QTY)
    local item = Whole(out.item, 1, MAX_ITEM)
    if not (qty and item and out.key and #craft.mats > 0 and #craft.mats <= 8) then stats.refused = stats.refused + 1 return false, "bad" end
    local total, complete, mats = 0, true, {}
    for _, m in ipairs(craft.mats) do
        local mq = Whole(m.qty, 1, C.MAX_QTY)
        if not (mq and Whole(m.item, 1, MAX_ITEM) and m.key) then stats.refused = stats.refused + 1 return false, "bad" end
        local ok, allocs, cost = C.Take(rec, m.key, mq, m.before)
        local row = { i = m.item, q = mq }
        if ok and cost then row.c = cost; total = total + cost else complete = false end
        mats[#mats + 1] = row
    end
    local prof = Whole(craft.profession, 1, MAX_ITEM)
    if prof then
        local name = Text(craft.professionName, 40)
        local count = 0
        for _ in pairs(rec.profs) do count = count + 1 end
        if name and (rec.profs[prof] or count < C.MAX_PROFS) then rec.profs[prof] = name end
    end
    local entry = { id = rec.nextCraft, t = now, r = Whole(craft.recipe, 1, MAX) or 1, p = prof, i = item, q = qty,
        c = complete and total or nil, st = complete and "ok" or "incomplete", m = mats }
    rec.nextCraft = rec.nextCraft + 1
    rec.crafts[#rec.crafts + 1] = entry
    while #rec.crafts > C.MAX_CRAFTS do table.remove(rec.crafts, 1) end
    stats.crafts = stats.crafts + 1
    if C.Pool(rec, out.key) == Whole(out.before, 0, MAX) then
        Extend(rec, { t = now, k = out.key, i = item, q = qty, r = qty, c = entry.c, s = "craft", f = entry.id, p = prof })
    else   -- the output joined other stock of this identity: it cannot be told from it
        C.Disturb(rec, out.key)
        stats.mixed = stats.mixed + 1
    end
    L.Touch()
    return true, entry
end

-- The materials of a craft that could not be verified are no longer reliably accounted for.
function C.Disturbed(char, keys)
    local rec = Rec(char, false)
    if not rec then return end
    for _, key in ipairs(keys) do C.Disturb(rec, key) end
end

---------------------------------------------------------------------------
-- Posting provenance (V5). What a TwichUI posting proves, and only that:
--   * the exact item identity (its bag link -> C.Key), the quantity, unit price, deposit and duration the player reviewed;
--   * that the game created the auction (AUCTION_HOUSE_AUCTION_CREATED with its native auction id; all of a multi-post through
--     AUCTION_MULTISELL_UPDATE), never the intent alone;
--   * the cost of the posted units, taken out of the identified stock under the same rule as a sale (every carried unit of that
--     identity must be an identified lot unit, and the bags must have lost exactly the posted units); otherwise the posted units'
--     cost is unknown and the pool is forgotten, never guessed;
--   * its later state by that native auction id only: "sold" when the owned-auction list shows it sold, "cancelled" on
--     AUCTION_CANCELED for it, "ended" when a complete owned-auction list no longer has it (expired, or sold and paid).
-- A seller invoice names an item and a count but no auction id and no item id, so a collected sale is never tied to a posting here:
-- the sale's Item Result keeps "Cost basis unavailable". Nothing here is a cash movement or a realized result.
---------------------------------------------------------------------------
local function LinkName(link)
    link = Plain(link)
    return type(link) == "string" and Text(link:match("|h%[(.-)%]|h"), 60) or nil
end

-- A reviewed posting is about to be sent: what it is and the bags before it. Intent only: nothing is kept unless the game creates it.
function C.PostIntent(p)
    if blocked or type(p) ~= "table" then return nil end
    local char = L.CharKey()
    local item, qty = Whole(p.item, 1, MAX_ITEM), Whole(p.quantity, 1, C.MAX_QTY)
    if not (char and item and qty and L.Active()) then return nil end
    local key = C.Key(p.link, item)
    local watch = R.LedgerCostWatch
    local bags = watch and watch.Carried and watch.Carried()
    return { char = char, key = key, item = item, qty = qty, name = LinkName(p.link), unit = Whole(p.unit, 1, MAX),
        deposit = Whole(p.deposit, 0, MAX), duration = Whole(p.duration, 1, 3), before = bags and (bags[key] or 0) or nil }
end

local function FindPost(rec, auction)
    for i = #rec.posts, 1, -1 do
        local post = rec.posts[i]
        if post.a == auction then return post end
        for _, a in ipairs(post.ac) do if a == auction then return post end end
    end
end

-- The game created the posting's auction(s). ids: the native auction ids seen ({ id, ... }, at least one for an item posting of
-- one unit or a commodity; possibly none for a multi-post the game confirmed as complete). Returns the post, or nil and why.
function C.Posted(token, ids)
    if blocked or type(token) ~= "table" or L.CharKey() ~= token.char then return nil, "context" end
    local rec = Rec(token.char, true)
    if not rec then return nil, "record" end
    if type(rec.posts) ~= "table" then rec.posts, rec.nextPost = {}, rec.nextPost or 1 end
    local list = {}
    for _, v in ipairs(type(ids) == "table" and ids or {}) do
        local a = Whole(v, 1, MAX)
        if a and #list < C.MAX_POST_IDS then list[#list + 1] = a end
        if a and FindPost(rec, a) then stats.duplicate = stats.duplicate + 1 return nil, "duplicate" end
    end
    local now = Now()
    if not now then return nil, "clock" end
    local post = { id = rec.nextPost or 1, t = now, k = token.key, i = token.item, n = token.name, q = token.qty, u = token.unit,
        dep = token.deposit, dur = token.duration, a = list[1], ac = list, st = "posted", cs = "unknown", al = {} }
    rec.nextPost = post.id + 1
    -- the posted units leave the identified stock exactly as a sale's would, or the pool is forgotten
    local watch = R.LedgerCostWatch
    local bags = watch and watch.Carried and watch.Carried()
    local after = bags and (bags[token.key] or 0) or nil
    if C.Pool(rec, token.key) == 0 then
        post.cs = "nolot"
    elseif not (token.before and after) or token.before - after ~= token.qty then
        post.cs = "nostock"
        C.Disturb(rec, token.key)
    else
        local ok, allocs, cost = C.Take(rec, token.key, token.qty, token.before)
        if ok then
            local rows, cut = Compress(allocs)
            post.al = rows
            if cost and not cut then post.cs, post.c = "ok", cost end
        else
            post.cs = allocs
        end
    end
    rec.posts[#rec.posts + 1] = post
    while #rec.posts > C.MAX_POSTS do table.remove(rec.posts, 1) end
    stats.posts = (stats.posts or 0) + 1
    L.Touch()
    return post
end

-- AUCTION_CANCELED for one of this character's postings. Its units come back by mail with no carried cost (they rejoin the bags as
-- unknown-cost stock): the reserved cost is kept on the posting for the record, never moved back to a lot.
function C.AuctionCancelled(auction)
    auction = Whole(auction, 1, MAX)
    local key = L.CharKey()
    local rec = auction and key and Rec(key, false)
    if not (rec and type(rec.posts) == "table") then return false end
    local post = FindPost(rec, auction)
    if not post or post.st == "cancelled" then return false end
    post.st = "cancelled"
    L.Touch()
    return true
end

-- An owned-auction list as read by the Auction House pages: rows { auctionID, status (0 active, 1 sold) }; complete = the list is the
-- whole of it. Only this character's postings, and only by their native auction ids, change state.
function C.Owned(rows, complete)
    local key = L.CharKey()
    local rec = key and Rec(key, false)
    if blocked or not (rec and type(rec.posts) == "table") or type(rows) ~= "table" then return 0 end
    local status = {}
    for _, row in ipairs(rows) do
        local a = type(row) == "table" and Whole(row.auctionID, 1, MAX)
        if a then status[a] = Whole(row.status, 0, 1) or 0 end
    end
    local changed = 0
    for _, post in ipairs(rec.posts) do
        if post.st == "posted" or post.st == "sold" then
            local ids = #post.ac > 0 and post.ac or { post.a }
            local seen, sold = false, false
            for _, a in ipairs(ids) do
                if status[a] ~= nil then seen = true; if status[a] == 1 then sold = true end end
            end
            local was = post.st
            if sold then post.st = "sold"
            elseif not seen and complete == true and #ids > 0 then post.st = "ended" end
            if post.st ~= was then changed = changed + 1 end
        end
    end
    if changed > 0 then L.Touch() end
    return changed
end

-- Postings of the window, newest first. { { ..post, char } }
function C.Posts(chars, firstTime, lastTime)
    local out = {}
    for _, key in ipairs(chars) do
        local rec = Rec(key, false)
        if rec and type(rec.posts) == "table" then
            for _, post in ipairs(rec.posts) do
                if post.t >= firstTime and post.t < lastTime then
                    local copy = { char = key }
                    for k, v in pairs(post) do copy[k] = v end
                    out[#out + 1] = copy
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.id > b.id end)
    return out
end

---------------------------------------------------------------------------
-- Reading (for the Workshop's Ledger page)
---------------------------------------------------------------------------
-- Results of the window, newest first, from one record or all. { { ..result, char } }
function C.Results(chars, firstTime, lastTime)
    local out = {}
    for _, key in ipairs(chars) do
        local rec = Rec(key, false)
        if rec then
            for i = #rec.results, 1, -1 do
                local r = rec.results[i]
                if r.t >= firstTime and r.t < lastTime then
                    local copy = { char = key }
                    for k, v in pairs(r) do copy[k] = v end
                    out[#out + 1] = copy
                end
            end
        end
    end
    table.sort(out, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.id > b.id end)
    return out
end

-- Per profession over the window: verified results (every unit from crafts of that profession and every cost known), results
-- that involved the profession but lack a cost, and crafts. { [id] = { name, profit, sales, partial, crafts } }
function C.Professions(chars, firstTime, lastTime)
    local out = {}
    local function Row(id, name)
        local r = out[id]
        if not r then r = { id = id, name = name or ("Profession " .. id), profit = 0, collected = 0, cost = 0, sales = 0, partial = 0, crafts = 0 }; out[id] = r end
        if name and (r.name:find("^Profession %d+$")) then r.name = name end
        return r
    end
    for _, key in ipairs(chars) do
        local rec = Rec(key, false)
        if rec then
            for _, cr in ipairs(rec.crafts) do
                if cr.p and cr.t >= firstTime and cr.t < lastTime then Row(cr.p, rec.profs[cr.p]).crafts = Row(cr.p).crafts + 1 end
            end
            for _, r in ipairs(rec.results) do
                if r.t >= firstTime and r.t < lastTime then
                    if r.st == "ok" and r.pf then
                        local row = Row(r.pf, rec.profs[r.pf])
                        row.sales, row.collected, row.cost = row.sales + 1, row.collected + r.a, row.cost + r.c
                        row.profit = row.profit + (r.a - r.c)
                    else
                        local prof
                        for _, a in ipairs(r.al) do if a.s == "craft" and a.p then prof = a.p break end end
                        if prof then local row = Row(prof, rec.profs[prof]); row.partial = row.partial + 1 end
                    end
                end
            end
        end
    end
    local list = {}
    for _, r in pairs(out) do list[#list + 1] = r end
    table.sort(list, function(a, b)
        if (a.sales > 0) ~= (b.sales > 0) then return a.sales > 0 end
        if a.profit ~= b.profit then return a.profit > b.profit end
        return a.name < b.name
    end)
    return list
end

-- Counts only (diagnostics gauges and tests). Read only.
function C.Snapshot()
    local key = L.CharKey()
    local rec = key and Rec(key, false)
    local copy = {}
    for k, v in pairs(stats) do copy[k] = v end
    local transit = 0
    if rec then for _, lot in ipairs(rec.lots) do if lot.tq then transit = transit + 1 end end end
    return { blocked = blocked, lots = rec and #rec.lots or 0, results = rec and #rec.results or 0, crafts = rec and #rec.crafts or 0,
        transit = transit, posts = rec and type(rec.posts) == "table" and #rec.posts or 0, stats = copy }
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
local subscribed = false
local function OnCancelled(auction)
    local ok, err = pcall(C.AuctionCancelled, auction)
    if not ok and R.Fault then R.Fault("gold ledger cost basis", err) end
end
function C.Refresh()
    if L.Active() and not blocked and not subscribed then
        subscribed = true
        L.OnAttached(Attached)
        R:On("AUCTION_CANCELED", OnCancelled)
    elseif not L.Active() and subscribed then
        subscribed = false
        L.OnAttached(nil, Attached)
        R:Off("AUCTION_CANCELED", OnCancelled)
    end
    if R.LedgerCostWatch then R.LedgerCostWatch.Refresh(L.Active() and not blocked) end
end

if R.Perf and R.Perf.Gauge then
    for _, field in ipairs({ "lots", "results", "crafts", "transit", "posts" }) do
        local name = field
        R.Perf.Gauge("ledger.cost." .. name, { label = "Gold ledger cost basis: " .. name .. " (bounded)", unit = "count", kind = "cache",
            group = "workshop", read = function() return C.Snapshot()[name] end })
    end
end

R:OnInit(function() C.Init(); C.Refresh() end)
