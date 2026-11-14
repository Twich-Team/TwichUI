-- TwichUI Workshop: the multilevel crafting planner (P1; pure, not used by any window yet)
-- Plans the WHOLE crafting chain of the queue: for every material it decides whether it is bought (vendor or auction house) or made by a known
-- recipe, whose own reagents are decided the same way, several levels deep. No frames, no game calls, no timers and nothing saved: the caller
-- hands in the same functions Shopping.Plan takes, so the same inputs always give the same plan. docs/workshop/multilevel-crafting-planner.md is
-- the contract; Shopping.lua stays the planner the windows use until P2 adopts this one.
--
-- THE RULES
--   * Demand is combined BEFORE anything is decided. The queue's materials are added up (Materials.Combine, which also credits what queued crafts
--     make); a made material's reagents are added to the same per-item total, so an item needed by several branches is decided once, for its
--     whole quantity, and owned items are allocated once (W.Split: bags, then bank, then guild bank).
--   * Owned first. What is owned of an item covers its demand before anything of it is bought or made. Owned items are not free: the ECONOMIC
--     cost values them at the cheapest price per item known (a vendor's price over its stack, the auction house's lowest listing); the CASH is
--     only what is bought. Stored items are collected, not bought.
--   * Making uses only a recipe with a fixed positive output (outMin = outMax), countable materials, that the character can do (inp.available)
--     and that does not use its own output. Crafts are ceil(short / output); the rest of the last craft is a leftover, reported, never credited.
--   * A plan whose crafts depend on each other in a circle is never a plan: every evaluated choice is checked, and a circular route is refused
--     with the items of the circle, while the same item's other routes stay usable.
--   * Costs. Vendor: whole stacks at the price last seen. Auction house: Market.Cost (inp.cost) for the whole quantity, else the old unit quote.
--     The figure compared is the LOWER supported bound (as Shopping does since A7); the upper bound is carried beside it and becomes open
--     (nil) as soon as one figure is only "at least". An unknown cost is never zero: it is counted in `missing`, and a plan with fewer missing
--     costs always ranks first.
--   * The objective. Plans are ranked by (missing costs, economic low, cash low) (opt.objective "cash": cash missing, cash low, values missing,
--     economic low), then by a fixed order of choices (by item id: vendor, auction house, no source, then the recipes by id). Independent parts of
--     the graph (no shared item) are solved apart; each part is searched EXHAUSTIVELY by branch and bound while its states stay within the
--     limits (then the plan is the proven best of the options considered), otherwise its best plan found by the search, two seed plans and a
--     local improvement is returned and marked "bounded" (never called optimal).
--   * Bounded by construction: CP.LIMITS (graph depth, extra items, recipes, candidates per item, search states, improvement and alternative
--     evaluations). CP.Job runs the same work CP.STEP work units at a time for a caller that spreads it over frames (P2 must: a large queue
--     takes tens of milliseconds at once); CP.Plan runs it at once.

local R = TwichUI
local W = R.Workshop
local PR, V, M = W.Prices, W.Vendor, W.Materials
local Int, Finite, Split = W.Int, W.Finite, W.Split
local floor, ceil, min = math.floor, math.ceil, math.min
local CP = {}
W.CraftPlanner = CP

CP.VERSION = 1
-- depth: crafting levels below the queue's own materials; nodes: items beyond the queue's own materials; recipes: distinct usable recipes;
-- candidates: usable recipes per item; states: branch-and-bound nodes over the whole plan; improve: local-improvement evaluations;
-- alternatives: items whose alternatives are evaluated; memo: purchase quotes kept per plan
CP.LIMITS = { depth = 6, nodes = 64, recipes = 96, candidates = 4, states = 2000, improve = 300, alternatives = 24, memo = 4096 }
CP.RANK = { vendor = 1, auction = 2, none = 3 }
-- The job's work units (items touched, plus a fixed share for the bookkeeping around each piece of work), measured offline so that a step of
-- CP.STEP units stays near a millisecond however the plan is shaped (many small parts or one large one): see the doc's measurements
CP.BUILD_COST = 12     -- per item built or reported (each asks the vendor, auction and recipe services)
CP.EVAL_COST = 10      -- per evaluation, on top of its part's items
CP.PART_COST = 30      -- per independent part (its defaults, seeds and baseline)
CP.STEP = 300          -- the work units a P2 caller should give job:Step per frame (about 0.5 to 1.4 ms offline; see the doc)
local TWO53 = 9007199254740992

-- Plain sentences for the codes the result carries (P2 shows them; nothing here formats money)
CP.WHY = {
    invalid = "This recipe entry couldn't be read.",
    unavailable = "You don't know this recipe, so it isn't planned.",
    unsupported = "This recipe has materials TwichUI can't count.",
    noamount = "This recipe's output isn't known yet.",
    range = "This recipe makes a varying amount, so it isn't planned.",
    circular = "Making it this way would need the item itself, directly or through its materials.",
    toomany = "Making it this way would take more crafts than a queue entry holds.",
    graphlimit = "Not every material of this recipe could be planned (too many items).",
    candidatelimit = "Only the first recipes for this item are compared.",
    recipelimit = "Too many recipes in this plan; later ones aren't compared.",
    depthlimit = "Materials this deep aren't planned to be made; they are bought.",
    novendor = "No vendor that sells this has been seen.",
    noauction = "No auction price is saved for this.",
    norecipe = "No recipe you can use makes this.",
    noprice = "A vendor sells it, but its price hasn't been seen yet.",
    limited = "A vendor had too few when you last saw it.",
    few = "Not enough are listed at the auction house.",
    nosource = "No vendor, auction price or usable recipe is known for this.",
    counts = "Your bag count of this couldn't be read, so none is assumed owned.",
    unknownentries = "A queued recipe's materials aren't known yet.",
    states = "The search stopped at its limit: this is the best plan found, not a proven best.",
    picklost = "An earlier source choice is no longer possible.",
    estimate = "Part of the cost is an auction estimate: buying that many may cost more.",
    wholeauction = "Auctions may require buying larger stacks.",
    approximate = "A total is beyond what can be added exactly; it is approximate.",
    missingcost = "Some materials have no known price, so the cash total is incomplete.",
    missingvalue = "Some owned materials have no known price, so their value isn't counted.",
}

---------------------------------------------------------------------------
-- Small checks
---------------------------------------------------------------------------
local function Num(v)   -- a finite copper figure from 0, or nil (a secret, NaN, an infinity, a negative, a non-number)
    v = W.Plain(v)
    if not Finite(v) or v < 0 then return nil end
    return v
end

-- owned `o` valued at num/den copper each, rounded half up (exact for whole numbers below 2^53)
local function Value(o, num, den) return floor((2 * o * num + den) / (2 * den)) end

-- the merchant record as the planner can use it, or nil (V.Entry's records are already checked; a caller's stand-in may not be)
local function VendorRec(vr)
    if type(vr) ~= "table" then return nil end
    local p, s = Num(vr.p), Int(vr.s, 1, W.MAX_QTY)
    if not p or not s then return nil end
    local a = W.Plain(vr.a)
    if a ~= -1 and not Int(a, 0, W.MAX_ID) then return nil end
    return vr
end

---------------------------------------------------------------------------
-- Purchase quotes (memoised per plan, per item and quantity)
---------------------------------------------------------------------------
-- q = { source, state, low, high (nil: open), atMost, exact (low == high), at, quality, freshness, complete, approximate, surplus, purchases,
--   unit, why (when low is nil: noprice / limited / few / nosource) }
local function Memo(P, store, item, qty)
    local t = store[item]
    if not t then t = {} store[item] = t end
    return t, t[qty]
end
local function Keep(P, t, qty, q)
    if P.memoN < P.L.memo then t[qty] = q P.memoN = P.memoN + 1 end
    return q
end

local function VendorQuote(P, nd, qty)
    local t, q = Memo(P, P.memoV, nd.item, qty)
    if q then return q end
    if not nd.vendor then
        q = { source = "vendor", state = "noprice", why = "noprice" }
    else
        local vq = V.Quote(nd.vendor, qty)
        if vq and vq.state == "ok" and Num(vq.cost) then
            q = { source = "vendor", state = "exact", low = vq.cost, high = vq.cost, exact = true, at = vq.at, surplus = vq.surplus,
                purchases = vq.purchases, stack = vq.stack, npc = vq.npc }
        else
            q = { source = "vendor", state = "limited", why = "limited", at = vq and vq.at, avail = vq and vq.avail }
        end
    end
    return Keep(P, t, qty, q)
end

-- Market.Cost when given (A7's states), else Prices.Quote over the saved lookup; nil when the auction house has nothing for the item
local function AuctionQuote(P, nd, qty)
    local t, q = Memo(P, P.memoA, nd.item, qty)
    if q ~= nil then return q or nil end
    local inp = P.inp
    if inp.cost then
        local c = inp.cost(nd.item, qty)
        if type(c) == "table" and c.state ~= "none" then
            q = { source = "auction", state = c.state, at = c.at, quality = c.quality, freshness = c.freshness, complete = c.complete,
                approximate = c.approximate, info = c }
            if c.state == "exact" then
                q.low = Num(c.cost or c.low)
                q.high, q.exact = q.low, true
            elseif c.state == "range" then
                q.low, q.high = Num(c.low), Num(c.high)
                if not (q.low and q.high and q.high >= q.low) then q.high = nil end
            elseif c.state == "estimate" then
                q.low, q.atMost = Num(c.low), Num(c.high)   -- "at least low": the plan's upper bound is open (A7's rule)
            else
                q.state, q.why = "few", "few"
            end
            if q.low == nil and not q.why then q.state, q.why, q.high = "few", "few", nil end
            return Keep(P, t, qty, q)
        end
    end
    local p = inp.auction and inp.auction(nd.item) or nil
    local aq = PR.Quote(p, qty)
    if aq.state == "none" then Keep(P, t, qty, false) return nil end
    q = { source = "auction", at = aq.at, complete = aq.complete, unit = aq.unit }
    local cost = Num(aq.cost)
    if aq.state == "few" or not cost then
        q.state, q.why = "few", "few"
    elseif aq.state == "exact" then
        q.state, q.low, q.high, q.exact = "exact", cost, cost, true
    else
        q.state, q.low, q.legacy = "estimate", cost, true   -- the old unit-price estimate: price x quantity is the least it could cost
    end
    return Keep(P, t, qty, q)
end

-- The buying source for `qty`: the lower priced figure, a tie to the vendor; one with a price before one without; only = a player's choice
local function BuyBest(P, nd, qty, only)
    local v = (nd.hasVendor and only ~= "auction") and VendorQuote(P, nd, qty) or nil
    local a = (nd.hasAuction and only ~= "vendor") and AuctionQuote(P, nd, qty) or nil
    if v and v.low and (not (a and a.low) or v.low <= a.low) then return v end
    if a and a.low then return a end
    if v then return v end
    if a then return a end
    return P.NONE
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------
-- A recipe as the planner uses it: { id, name, per, mats = { { item, qty } } (merged, by item) }, or nil and why
-- (invalid / unavailable / unsupported / noamount / range / circular, in that order)
local function Normalize(rec, item, available)
    if type(rec) ~= "table" then return nil, "invalid" end
    local id = Int(rec.id, 1, W.MAX_ID)
    if not id or Int(rec.outItem, 1, W.MAX_ID) ~= item then return nil, "invalid" end
    if available then
        local ok = available(rec)
        if not ok then return nil, "unavailable" end
    end
    local mats = rec.mats
    if type(mats) ~= "table" or #mats == 0 then return nil, "unsupported" end
    local sum, items = {}, {}
    for _, m in ipairs(mats) do
        local mi = type(m) == "table" and Int(m.item, 1, W.MAX_ID) or nil
        local q = type(m) == "table" and Int(m.qty, 1, W.MAX_QTY) or nil
        if not mi or not q then return nil, "unsupported" end
        if not sum[mi] then sum[mi] = 0 items[#items + 1] = mi end
        sum[mi] = sum[mi] + q   -- a reagent listed twice counts twice
    end
    if #items > W.MAX_MATS then return nil, "unsupported" end
    local lo = Int(rec.outMin, 1, W.MAX_QTY)
    if not lo then return nil, "noamount" end
    if rec.outMax ~= nil then
        local hi = Int(rec.outMax, 1, W.MAX_QTY)
        if not hi then return nil, "noamount" end
        if hi ~= lo then return nil, "range" end
    end
    if sum[item] then return nil, "circular" end
    table.sort(items)
    local out = {}
    for i, mi in ipairs(items) do out[i] = { item = mi, qty = sum[mi] } end
    return { id = id, name = W.Text(rec.name, 80) or ("Recipe " .. id), per = lo, mats = out, rec = rec }
end

---------------------------------------------------------------------------
-- The graph
---------------------------------------------------------------------------
local PICK_WHY = { vendor = "novendor", auction = "noauction", make = "norecipe" }

local function NewNode(P, item, depth)
    local inp = P.inp
    local nd = { item = item, depth = depth, need = P.need[item] or 0, credit = P.made[item] or 0, rejected = {} }
    local h = W.Count(inp.have and inp.have(item))
    nd.unknown = h == nil
    nd.bags, nd.bank, nd.guild = h or 0, 0, 0
    if inp.stock and h ~= nil then
        local b, g = inp.stock(item)
        nd.bank, nd.guild = W.Count(b) or 0, W.Count(g) or 0
    end
    local vr = inp.vendor and VendorRec(inp.vendor(item)) or nil
    nd.vendor = vr
    nd.hasVendor = vr ~= nil or (inp.vendor ~= nil and inp.vendor(item) ~= nil) or (inp.sells ~= nil and inp.sells(item) == true)
    local look = inp.auction and inp.auction(item) or nil
    nd.hasAuction = look ~= nil or (inp.cost ~= nil and AuctionQuote(P, nd, 1) ~= nil)
    -- what one owned item is worth: the cheapest price per item known (Shopping's rule), as num / den
    if vr then nd.num, nd.den = vr.p, vr.s end
    local lp = type(look) == "table" and Num(look.price) or nil
    if lp and (not nd.num or lp * nd.den < nd.num) then nd.num, nd.den = lp, 1 end
    P.nodes[#P.nodes + 1] = nd
    P.index[item] = #P.nodes
    return nd
end

local function Build(P)
    local inp, L = P.inp, P.L
    local queue, head = {}, 1
    for _, item in ipairs(P.roots) do queue[#queue + 1] = NewNode(P, item, 0) end
    local extra, recipes = 0, 0
    while head <= #queue do
        local nd = queue[head]
        head = head + 1
        P:Tick(CP.BUILD_COST)
        nd.recipes = {}
        if nd.depth < L.depth then
            local list = inp.recipes and inp.recipes(nd.item) or nil
            local cands = {}
            if type(list) == "table" then
                for _, rec in ipairs(list) do cands[#cands + 1] = rec end
            end
            table.sort(cands, function(a, b)
                local ia = type(a) == "table" and Int(a.id, 1, W.MAX_ID) or 0
                local ib = type(b) == "table" and Int(b.id, 1, W.MAX_ID) or 0
                return ia < ib
            end)
            for _, rec in ipairs(cands) do
                local r, why = Normalize(rec, nd.item, inp.available)
                if r and #nd.recipes >= L.candidates then r, why = nil, "candidatelimit" end
                if r and recipes >= L.recipes then r, why = nil, "recipelimit" end
                if r then
                    local new = 0
                    for _, m in ipairs(r.mats) do if not P.index[m.item] then new = new + 1 end end
                    if extra + new > L.nodes then r, why = nil, "graphlimit" end
                end
                if r then
                    for _, m in ipairs(r.mats) do
                        local j = P.index[m.item]
                        if not j then
                            queue[#queue + 1] = NewNode(P, m.item, nd.depth + 1)
                            extra = extra + 1
                            j = #P.nodes
                        end
                        m.node = j
                    end
                    recipes = recipes + 1
                    r.pos = #nd.recipes + 1
                    nd.recipes[r.pos] = r
                else
                    nd.rejected[#nd.rejected + 1] = { id = type(rec) == "table" and Int(rec.id, 1, W.MAX_ID) or nil, why = why,
                        name = type(rec) == "table" and W.Text(rec.name, 80) or nil }
                    if why == "graphlimit" or why == "candidatelimit" or why == "recipelimit" then P.limits[why] = true end
                end
            end
        elseif inp.recipes then
            local list = inp.recipes(nd.item)
            if type(list) == "table" and #list > 0 then nd.deep = true P.limits.depthlimit = true end
        end
    end
    -- the canonical order: by depth, then item id (the order demand flows in and items are branched on)
    local n = #P.nodes
    local order = {}
    for i = 1, n do order[i] = i end
    table.sort(order, function(a, b)
        local x, y = P.nodes[a], P.nodes[b]
        if x.depth ~= y.depth then return x.depth < y.depth end
        return x.item < y.item
    end)
    P.order, P.pos = order, {}
    for p, i in ipairs(order) do P.pos[i] = p end
    -- the choices of each item, the player's choice first
    local picks = type(inp.picks) == "table" and inp.picks or {}
    for _, nd in ipairs(P.nodes) do
        local pick = picks[nd.item]
        local dom = {}
        if pick == "vendor" or pick == "auction" then
            if (pick == "vendor" and nd.hasVendor) or (pick == "auction" and nd.hasAuction) then
                nd.picked, dom[1] = pick, { kind = "buy", only = pick }
            else
                nd.pickLost, nd.pickWhy = pick, PICK_WHY[pick]
            end
        elseif pick == "make" then
            if #nd.recipes > 0 then
                nd.picked = "make"
                for _, r in ipairs(nd.recipes) do dom[#dom + 1] = { kind = "make", r = r } end
            else
                nd.pickLost = "make"
                nd.pickWhy = (nd.rejected[1] and nd.rejected[1].why) or "norecipe"
            end
        end
        if #dom == 0 then
            dom[1] = { kind = "buy" }
            for _, r in ipairs(nd.recipes) do dom[#dom + 1] = { kind = "make", r = r } end
        end
        nd.dom = dom
    end
end

-- Independent parts: items joined by the recipes that may be chosen (no shared item, no shared stock); each part in canonical order
local function Components(P)
    local parent = {}
    local function Find(x)
        while parent[x] ~= x do parent[x] = parent[parent[x]] x = parent[x] end
        return x
    end
    for i = 1, #P.nodes do parent[i] = i end
    for i, nd in ipairs(P.nodes) do
        for _, ch in ipairs(nd.dom) do
            if ch.kind == "make" then
                for _, m in ipairs(ch.r.mats) do
                    local a, b = Find(i), Find(m.node)
                    if a ~= b then if a < b then parent[b] = a else parent[a] = b end end
                end
            end
        end
    end
    local byRoot, comps = {}, {}
    for _, i in ipairs(P.order) do
        local r = Find(i)
        local c = byRoot[r]
        if not c then c = { list = {}, byId = {}, states = 0 } byRoot[r] = c comps[#comps + 1] = c end
        c.list[#c.list + 1] = i
        c.byId[#c.byId + 1] = i
    end
    for _, c in ipairs(comps) do
        table.sort(c.byId, function(a, b) return P.nodes[a].item < P.nodes[b].item end)
        c.first = P.nodes[c.byId[1]].item
        c.decide = 0
        for _, i in ipairs(c.list) do if #P.nodes[i].dom > 1 then c.decide = c.decide + 1 end end
    end
    table.sort(comps, function(a, b) return a.first < b.first end)
    return comps
end

---------------------------------------------------------------------------
-- Evaluating one choice of routes
---------------------------------------------------------------------------
-- a[k]: the choice index of node k (0: not decided yet, search only); def[k] (optional): the choice used where a[k] is 0.
-- Returns e = { ok, why, cycle, missing, cashMissing, valueMissing, cash, cashHigh, open, owned, econ, crafts, nextK } (nextK: the first
-- undecided item that still lacks something, in canonical order). Demand flows in canonical order; an item that gains demand after it was
-- passed is visited again in the next pass, so every item is decided on its whole demand. Every cost grows with demand, so the figures of an
-- undecided plan are a lower bound of every plan that completes it (the search relies on that).
local function Choice(P, k, a, def)
    local c = a[k]
    if (c == nil or c == 0) and def then c = def[k] end
    if c and c > 0 then return P.nodes[k].dom[c] end
end

local function Rest(nd, d)
    local net = d - min(d, nd.credit)
    if nd.unknown then return net end
    local owned = nd.bags + nd.bank + nd.guild
    return net > owned and (net - owned) or 0
end

-- a circle among the crafts that are done: nil, or the items of one circle
local function Circle(P, C)
    local nodes, crafted, color = P.nodes, P.crafted, P.color
    for _, k in ipairs(C.list) do color[k] = 0 end
    local path = {}
    local found
    local function Visit(k)
        color[k] = 1
        path[#path + 1] = k
        local ch = P.cur[k]
        for _, m in ipairs(ch.r.mats) do
            local j = m.node
            if crafted[j] > 0 then
                if color[j] == 1 then
                    found = {}
                    local from
                    for i, x in ipairs(path) do if x == j then from = i end end
                    for i = from, #path do found[#found + 1] = nodes[path[i]].item end
                    return true
                elseif color[j] == 0 and Visit(j) then
                    return true
                end
            end
        end
        path[#path] = nil
        color[k] = 2
        return false
    end
    for _, k in ipairs(C.list) do
        if crafted[k] > 0 and color[k] == 0 and Visit(k) then return found end
    end
end

local function Eval(P, C, a, def, detail)
    local nodes, D, crafted, dirty, pos, cur = P.nodes, P.D, P.crafted, P.dirty, P.pos, P.cur
    local list = C.list
    P.evals = P.evals + 1
    P:Tick(#list + CP.EVAL_COST)
    for _, k in ipairs(list) do
        local nd = nodes[k]
        D[k], crafted[k], dirty[k], P.rest[k], P.src[k] = nd.need, 0, nd.need > 0, 0, nil
        cur[k] = Choice(P, k, a, def)
    end
    local passes, again = 0, true
    while again do
        again = false
        passes = passes + 1
        -- demand that keeps growing pass after pass can only come from crafts that need each other: name them
        if passes > #list + 1 then return { ok = false, why = "circular", cycle = Circle(P, C) } end
        for _, k in ipairs(list) do
            if dirty[k] then
                dirty[k] = false
                local ch = cur[k]
                if ch and ch.kind == "make" then
                    local r = Rest(nodes[k], D[k])
                    if r > 0 then
                        local c = ceil(r / ch.r.per)
                        if c > crafted[k] then
                            if c > W.MAX_CRAFTS then return { ok = false, why = "toomany", item = nodes[k].item } end
                            local delta = c - crafted[k]
                            crafted[k] = c
                            for _, m in ipairs(ch.r.mats) do
                                local j = m.node
                                local nv = D[j] + m.qty * delta
                                if nv > W.MAX_ID then return { ok = false, why = "toomany", item = nodes[j].item } end
                                D[j], dirty[j] = nv, true
                                if pos[j] <= pos[k] then again = true end
                            end
                        end
                    end
                end
            end
        end
    end
    P.passes = P.passes + passes
    local circle = Circle(P, C)
    if circle then return { ok = false, why = "circular", cycle = circle } end
    local e = { ok = true, missing = 0, cashMissing = 0, valueMissing = 0, cash = 0, cashHigh = 0, open = false, owned = 0, crafts = 0 }
    for _, k in ipairs(list) do
        local d = D[k]
        if d > 0 then
            local nd = nodes[k]
            local cu = min(d, nd.credit)
            local net = d - cu
            local b, kk, g, r
            if nd.unknown then b, kk, g, r = 0, 0, 0, net else b, kk, g, r = Split(net, nd.bags, nd.bank, nd.guild) end
            P.rest[k] = r
            local o = b + kk + g
            local val
            if o > 0 then
                if nd.num then val = Value(o, nd.num, nd.den) e.owned = e.owned + val
                else e.valueMissing = e.valueMissing + 1 end
            end
            local ch, q = cur[k], nil
            if r > 0 then
                if not ch then
                    if not e.nextK then e.nextK = k end
                elseif ch.kind == "buy" then
                    q = BuyBest(P, nd, r, ch.only)
                    P.src[k] = q.source
                    if q.low then
                        e.cash = e.cash + q.low
                        if q.high and not e.open then e.cashHigh = e.cashHigh + q.high else e.open = true end
                    else
                        e.cashMissing = e.cashMissing + 1
                    end
                else
                    P.src[k] = "make"
                    e.crafts = e.crafts + crafted[k]
                end
            end
            if detail then
                detail[#detail + 1] = { k = k, d = d, credit = cu, bags = b, bank = kk, guild = g, rest = r, value = val, ch = r > 0 and ch or nil,
                    q = q, crafts = crafted[k] }
            end
        end
    end
    if e.open then e.cashHigh = nil end
    e.econ = e.cash + e.owned
    e.missing = e.cashMissing + e.valueMissing
    return e
end

---------------------------------------------------------------------------
-- Ranking
---------------------------------------------------------------------------
local function Cmp(x, y) if x < y then return -1 elseif x > y then return 1 end return 0 end
local function KeyCmp(P, e, f)
    local c
    if P.objective == "cash" then
        c = Cmp(e.cashMissing, f.cashMissing) if c ~= 0 then return c end
        c = Cmp(e.cash, f.cash) if c ~= 0 then return c end
        c = Cmp(e.valueMissing, f.valueMissing) if c ~= 0 then return c end
        return Cmp(e.econ, f.econ)
    end
    c = Cmp(e.missing, f.missing) if c ~= 0 then return c end
    c = Cmp(e.econ, f.econ) if c ~= 0 then return c end
    return Cmp(e.cash, f.cash)
end

-- the choice of every item that still lacks something after the last evaluation, as ranks by item id (0: nothing to decide)
local function Vector(P, C)
    local v = {}
    for i, k in ipairs(C.byId) do
        local s = P.src[k]
        if not s then v[i] = 0
        elseif s == "make" then v[i] = 3 + P.cur[k].r.pos
        else v[i] = CP.RANK[s] end
    end
    return v
end
local function VecCmp(v, w)
    for i = 1, #v do
        if v[i] ~= w[i] then return v[i] < w[i] and -1 or 1 end
    end
    return 0
end

-- keeps the plan just evaluated when it ranks before the best so far (its choices, normalised: 0 where nothing is lacking)
local function Consider(P, C, a, e)
    local v = Vector(P, C)
    local b = C.best
    if b then
        local c = KeyCmp(P, e, b.e)
        if c > 0 or (c == 0 and VecCmp(v, b.v) >= 0) then return false end
    end
    local keep = {}
    for _, k in ipairs(C.list) do keep[k] = P.src[k] and (a[k] ~= 0 and a[k] or (P.def and P.def[k]) or 1) or 0 end
    C.best = { a = keep, e = e, v = v }
    return true
end

---------------------------------------------------------------------------
-- The search
---------------------------------------------------------------------------
-- The default choice of each item (seed and local improvement): the cheapest per item by a rough unit cost (buying: the lowest price per
-- item known; making: its reagents' unit costs over the output), the first choice when nothing is known. Ignores stock and batches.
local function Defaults(P, C)
    local unit, busy, def = {}, {}, {}
    local function U(k)
        if unit[k] ~= nil then return unit[k] or nil end
        if busy[k] then return nil end
        busy[k] = true
        local nd = P.nodes[k]
        local best, bestI
        for i, ch in ipairs(nd.dom) do
            local u
            if ch.kind == "buy" then
                if nd.vendor and ch.only ~= "auction" then u = nd.vendor.p / nd.vendor.s end
                if ch.only ~= "vendor" and nd.hasAuction then
                    local q = AuctionQuote(P, nd, 1)
                    if q and q.low and (not u or q.low < u) then u = q.low end
                end
            else
                u = 0
                for _, m in ipairs(ch.r.mats) do
                    local x = U(m.node)
                    if not x then u = nil break end
                    u = u + m.qty * x
                end
                if u then u = u / ch.r.per end
            end
            if u and (not best or u < best) then best, bestI = u, i end
        end
        busy[k] = nil
        def[k] = bestI or 1
        unit[k] = best or false
        return best
    end
    for _, k in ipairs(C.list) do U(k) end
    return def
end

local function Search(P, C)
    local a, nodes = P.a, P.nodes
    local function Fresh() for _, k in ipairs(C.list) do a[k] = (#nodes[k].dom == 1) and 1 or 0 end end
    -- seeds: every item's first choice (buying, unless the player chose to make it), then the default choices
    for _, seed in ipairs({ "first", "default" }) do
        for _, k in ipairs(C.list) do a[k] = seed == "first" and 1 or P.def[k] end
        local e = Eval(P, C, a, nil)
        if e.ok then Consider(P, C, a, e) else C.lastWhy = C.lastWhy or e end
    end
    if C.decide == 0 then Fresh() return end
    -- branch and bound over the items that can be made, each decided when it first lacks something
    Fresh()
    local stack = {}
    local function Node()
        P.states, C.states = P.states + 1, C.states + 1
        local e = Eval(P, C, a, nil)
        if not e.ok then P.pruned = P.pruned + 1 C.lastWhy = C.lastWhy or e return nil end
        if C.best and KeyCmp(P, e, C.best.e) > 0 then P.pruned = P.pruned + 1 return nil end
        if e.nextK then return e.nextK end
        P.leaves = P.leaves + 1
        Consider(P, C, a, e)
        return nil
    end
    local k = Node()
    if k then stack[1] = { k = k, c = 0 } end
    while #stack > 0 do
        local f = stack[#stack]
        f.c = f.c + 1
        if f.c > #nodes[f.k].dom then
            a[f.k] = 0
            stack[#stack] = nil
        elseif C.states >= C.budget then
            C.limited = true
            break
        else
            a[f.k] = f.c
            k = Node()
            if k then stack[#stack + 1] = { k = k, c = 0 } end
        end
    end
    Fresh()
end

-- Local improvement of a limited part: change one item's choice at a time (the others as in the best plan, or their default), keep any change
-- that ranks first, until a sweep changes nothing or the budget is spent.
local function Improve(P, C)
    if not C.best then return end
    local F = {}
    for _, k in ipairs(C.list) do F[k] = C.best.a[k] ~= 0 and C.best.a[k] or P.def[k] end
    local improved = true
    while improved and P.improve < P.L.improve do
        improved = false
        for _, k in ipairs(C.list) do
            local nd = P.nodes[k]
            if #nd.dom > 1 then
                for c = 1, #nd.dom do
                    if c ~= F[k] and P.improve < P.L.improve then
                        local old = F[k]
                        F[k] = c
                        P.improve = P.improve + 1
                        local e = Eval(P, C, F, nil)
                        if e.ok and Consider(P, C, F, e) then improved = true else F[k] = old end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- The result
---------------------------------------------------------------------------
local function Range(low, high) return { low = low, high = high } end

-- one figure of an evaluated plan for the alternatives and the baseline
local function Figures(e)
    if not e.ok then return { ok = false, why = e.why, cycle = e.cycle, item = e.item } end
    return { ok = true, economic = Range(e.econ, e.cashHigh and (e.cashHigh + e.owned) or nil), cash = Range(e.cash, e.cashHigh),
        missing = e.missing, crafts = e.crafts }
end

-- how two figures compare: "lower" (certainly cheaper: its upper bound is below the other's lower bound), "higher", "equal", "overlap"
-- (the ranges overlap, so the order is not certain) or "unknown" (a cost is missing on either side)
function CP.Compare(x, y)
    if not (x and y and x.ok and y.ok) or x.missing > 0 or y.missing > 0 then return "unknown" end
    local a, b = x.economic, y.economic
    if a.high and a.high == a.low and b.high and b.high == b.low and a.low == b.low then return "equal" end
    if a.high and a.high < b.low then return "lower" end
    if b.high and b.high < a.low then return "higher" end
    return "overlap"
end

local function Alternatives(P, C, line, k)
    local nd = P.nodes[k]
    if #nd.dom < 2 or P.altItems >= P.L.alternatives then return end
    P.altItems = P.altItems + 1
    local F = {}
    for _, j in ipairs(C.list) do F[j] = C.best.a[j] ~= 0 and C.best.a[j] or C.defaults[j] end
    local chosen = F[k]
    local plan = Figures(C.best.e)
    line.alternatives = {}
    for c, ch in ipairs(nd.dom) do
        if c ~= chosen then
            F[k] = c
            local e = Eval(P, C, F, nil)
            local f = Figures(e)
            f.kind = ch.kind == "make" and "make" or "buy"
            if ch.kind == "make" then f.recipe, f.name = ch.r.id, ch.r.name
            elseif e.ok then f.source = P.src[k] end
            if e.ok then
                f.compare = CP.Compare(plan, f)   -- the chosen plan against this one
                if plan.missing == 0 and f.missing == 0 then f.difference = f.economic.low - plan.economic.low end
            end
            line.alternatives[#line.alternatives + 1] = f
        end
    end
    F[k] = chosen
end

local function Assemble(P, comps)
    local res = { version = CP.VERSION, objective = P.objective, items = {}, crafts = {}, buy = {}, collect = {}, leftovers = {}, warnings = {},
        rejected = {}, picks = {} }
    local s = { entries = P.entries, final = P.final, unknownEntries = P.unknownEntries, invalidEntries = P.invalidEntries,
        economic = { low = 0, high = 0 }, cash = { low = 0, high = 0 }, owned = 0, missing = 0, cashMissing = 0, valueMissing = 0, crafts = 0,
        parts = #comps, exhaustive = true, reasons = {}, limits = {} }
    res.summary = s
    local base = { ok = true, cash = 0, cashHigh = 0, owned = 0, missing = 0 }
    local reasons = {}
    local function Reason(code) if not reasons[code] then reasons[code] = true s.reasons[#s.reasons + 1] = code end end
    local stepOf, steps = {}, {}
    for _, C in ipairs(comps) do
        if C.limited then s.exhaustive = false end
        local e = C.best and C.best.e
        if not e then
            -- only a player's circular or impossible choice could leave a part without a plan; the picks were dropped and it was solved again
            s.unavailable = true
        else
            s.cash.low, s.owned = s.cash.low + e.cash, s.owned + e.owned
            if e.cashHigh and s.cash.high then s.cash.high = s.cash.high + e.cashHigh else s.cash.high = nil end
            s.cashMissing, s.valueMissing, s.crafts = s.cashMissing + e.cashMissing, s.valueMissing + e.valueMissing, s.crafts + e.crafts
            local f = C.base
            if f and f.ok then
                base.cash, base.owned, base.missing = base.cash + f.cash, base.owned + f.owned, base.missing + f.missing
                if f.cashHigh and base.cashHigh then base.cashHigh = base.cashHigh + f.cashHigh else base.cashHigh = nil end
            else
                base.ok = false
            end
            local detail = {}
            Eval(P, C, C.best.a, nil, detail)
            for _, d in ipairs(detail) do
                P:Tick(CP.BUILD_COST)
                local nd = P.nodes[d.k]
                local line = { item = nd.item, need = d.d, queue = nd.need, queued = d.credit, owned = { bags = d.bags, bank = d.bank, guild = d.guild },
                    value = d.value, rest = d.rest, depth = nd.depth, usedBy = {}, picked = nd.picked, pickLost = nd.pickLost, pickWhy = nd.pickWhy,
                    countsUnknown = nd.unknown or nil }
                if nd.unknown then Reason("counts") end
                if d.value == nil and d.bags + d.bank + d.guild > 0 then line.valueMissing = true end
                if nd.need > 0 then line.usedBy[1] = { queue = true, qty = nd.need } end
                if d.rest == 0 then
                    line.source = "owned"
                elseif d.ch.kind == "make" then
                    local r = d.ch.r
                    line.source = "make"
                    local step = { item = nd.item, recipe = r.id, name = r.name, crafts = d.crafts, perCraft = r.per, produced = d.crafts * r.per,
                        used = d.rest, leftover = d.crafts * r.per - d.rest, reagents = {}, after = {} }
                    for _, m in ipairs(r.mats) do step.reagents[#step.reagents + 1] = { item = m.item, qty = m.qty * d.crafts } end
                    line.make = step
                    steps[#steps + 1] = step
                    stepOf[nd.item] = step
                    if step.leftover > 0 then res.leftovers[#res.leftovers + 1] = { item = nd.item, qty = step.leftover, kind = "craft", recipe = r.id } end
                else
                    local q = d.q
                    line.source = q.source
                    line.buy = { source = q.source, qty = d.rest, state = q.state, low = q.low, high = q.high, atMost = q.atMost, exact = q.exact == true,
                        at = q.at, surplus = q.surplus, purchases = q.purchases, why = q.why, quality = q.quality, freshness = q.freshness,
                        complete = q.complete, legacy = q.legacy }
                    if q.low then
                        res.buy[#res.buy + 1] = line.buy
                        line.buy.item = nd.item
                        if q.state == "estimate" then Reason("estimate") elseif q.state == "range" then Reason("wholeauction") end
                        if q.approximate then Reason("approximate") end
                        if q.surplus and q.surplus > 0 then res.leftovers[#res.leftovers + 1] = { item = nd.item, qty = q.surplus, kind = "stack" } end
                        if q.source == "auction" and (q.complete == false or q.freshness == "old" or q.quality == "limited" or q.quality == "none") then
                            res.warnings[#res.warnings + 1] = { item = nd.item, complete = q.complete, freshness = q.freshness, quality = q.quality }
                        end
                    else
                        line.buy.item = nd.item
                        line.missing = q.why or "nosource"
                    end
                    -- what the two ways of buying would cost for this quantity, for the details
                    line.options = {}
                    if nd.hasVendor then line.options.vendor = VendorQuote(P, nd, d.rest) end
                    if nd.hasAuction then line.options.auction = AuctionQuote(P, nd, d.rest) end
                end
                for _, where in ipairs({ "bank", "guild" }) do
                    if d[where] > 0 then res.collect[#res.collect + 1] = { item = nd.item, where = where, qty = d[where] } end
                end
                if #nd.rejected > 0 then line.rejected = nd.rejected end
                if nd.deep then line.deep = true end
                if d.rest > 0 then Alternatives(P, C, line, d.k) end
                res.items[#res.items + 1] = line
            end
        end
    end
    -- who uses what: the queue, then each craft by recipe id
    local byItem = {}
    for _, line in ipairs(res.items) do byItem[line.item] = line end
    for _, st in ipairs(steps) do
        for _, rg in ipairs(st.reagents) do
            local l = byItem[rg.item]
            if l then l.usedBy[#l.usedBy + 1] = { recipe = st.recipe, item = st.item, qty = rg.qty } end
            local pre = stepOf[rg.item]
            if pre then st.after[#st.after + 1] = rg.item end
        end
    end
    -- the crafts in an order that can be done: a craft after the crafts that make its reagents; among those ready, by item id
    local done, left = {}, #steps
    table.sort(steps, function(a, b) return a.item < b.item end)
    while left > 0 do
        local moved = false
        for _, st in ipairs(steps) do
            if not done[st] then
                local ready = true
                for _, it in ipairs(st.after) do if not done[stepOf[it]] then ready = false break end end
                if ready then
                    done[st] = true
                    left = left - 1
                    st.order = #res.crafts + 1
                    res.crafts[st.order] = st
                    moved = true
                    break
                end
            end
        end
        if not moved then break end   -- cannot happen: every kept plan passed the circle check
    end
    table.sort(res.items, function(a, b) return a.item < b.item end)
    table.sort(res.buy, function(a, b) return a.item < b.item end)
    table.sort(res.collect, function(a, b) if a.item ~= b.item then return a.item < b.item end return a.where < b.where end)
    table.sort(res.leftovers, function(a, b) if a.item ~= b.item then return a.item < b.item end return a.kind < b.kind end)
    for _, nd in ipairs(P.nodes) do
        if nd.pickLost then
            res.picks[#res.picks + 1] = { item = nd.item, pick = nd.pickLost, why = nd.pickWhy }
            Reason("picklost")
        elseif nd.picked then
            res.picks[#res.picks + 1] = { item = nd.item, pick = nd.picked, kept = true }
        end
        for _, rj in ipairs(nd.rejected) do res.rejected[#res.rejected + 1] = { item = nd.item, recipe = rj.id, why = rj.why } end
    end
    for item, why in pairs(P.ignoredPicks) do res.picks[#res.picks + 1] = { item = item, pick = why, ignored = true } end
    table.sort(res.picks, function(a, b) return a.item < b.item end)
    s.missing = s.cashMissing + s.valueMissing
    s.economic.low = s.cash.low + s.owned
    s.economic.high = s.cash.high and (s.cash.high + s.owned) or nil
    if s.economic.low >= TWO53 or (s.economic.high and s.economic.high >= TWO53) then Reason("approximate") end
    if P.unknownEntries > 0 then Reason("unknownentries") end
    if s.cashMissing > 0 then Reason("missingcost") end
    if s.valueMissing > 0 then Reason("missingvalue") end
    if not s.exhaustive then Reason("states") end
    for code in pairs(P.limits) do s.limits[#s.limits + 1] = code end
    table.sort(s.limits)
    s.optimization = s.exhaustive and "exhaustive" or "bounded"
    s.proven = s.exhaustive and #s.limits == 0
    s.complete = not s.unavailable and s.missing == 0 and P.unknownEntries == 0 and P.invalidEntries == 0 and not reasons.counts
    if P.entries == 0 then s.status = "empty"
    elseif s.unavailable then s.status = "unavailable"
    elseif s.complete then s.status = "complete"
    else s.status = "incomplete" end
    -- the baseline: the same queue with nothing made beyond it (every material it lacks bought at its cheaper known price)
    if base.ok and not s.unavailable then
        local bl = { economic = Range(base.cash + base.owned, base.cashHigh and (base.cashHigh + base.owned) or nil),
            cash = Range(base.cash, base.cashHigh), missing = base.missing }
        s.baseline = bl
        local plan = { ok = true, economic = s.economic, missing = s.missing }
        local bf = { ok = true, economic = bl.economic, missing = bl.missing }
        bl.compare = CP.Compare(plan, bf)   -- the plan against the baseline: "lower" = certainly cheaper
        if s.missing == 0 and bl.missing == 0 then
            -- the saving lies between (baseline low - plan high) and (baseline high - plan low), each nil when that end is open; `lowerBounds`
            -- compares the lower bounds the plans are ranked by, and is never a promise
            s.savings = { lowerBounds = bl.economic.low - s.economic.low,
                low = s.economic.high and (bl.economic.low - s.economic.high) or nil,
                high = bl.economic.high and (bl.economic.high - s.economic.low) or nil }
            s.savings.confident = s.savings.low ~= nil and s.savings.low > 0
        end
    end
    s.work = { evals = P.evals, states = P.states, pruned = P.pruned, leaves = P.leaves, improve = P.improve, passes = P.passes,
        nodes = #P.nodes, memo = P.memoN, alternatives = P.altItems }
    return res
end

---------------------------------------------------------------------------
-- Running a plan
---------------------------------------------------------------------------
local function Prepare(inp, opt)
    opt = type(opt) == "table" and opt or {}
    local L = {}
    for k, v in pairs(CP.LIMITS) do L[k] = v end
    if type(opt.limits) == "table" then
        for k, v in pairs(opt.limits) do if CP.LIMITS[k] and Int(v, 0, W.MAX_ID) then L[k] = v end end
    end
    local P = { inp = inp, L = L, objective = opt.objective == "cash" and "cash" or "economic", nodes = {}, index = {}, limits = {},
        memoV = {}, memoA = {}, memoN = 0, evals = 0, states = 0, pruned = 0, leaves = 0, improve = 0, passes = 0, altItems = 0,
        D = {}, crafted = {}, dirty = {}, rest = {}, src = {}, cur = {}, color = {}, a = {}, ignoredPicks = {},
        NONE = { source = "none", state = "none", why = "nosource" } }
    -- the work done so far, in items touched: an evaluation costs its part's items, building the graph CP.BUILD_COST per item (it asks the
    -- price services), the result as much per item reported. A job yields when its step's share is spent.
    function P:Tick(units)
        if self.co then
            self.slice = self.slice - (units or 1)
            if self.slice <= 0 then coroutine.yield() end
        end
    end
    -- the queue: each entry checked; materials merged; an entry whose materials can't be counted adds nothing and is counted
    local entries, valid = type(inp.entries) == "table" and inp.entries or {}, {}
    P.entries, P.unknownEntries, P.invalidEntries, P.final = 0, 0, 0, {}
    for _, e in ipairs(entries) do
        P.entries = P.entries + 1
        local crafts = type(e) == "table" and Int(e.crafts, 1, W.MAX_CRAFTS) or nil
        if not crafts then
            P.invalidEntries = P.invalidEntries + 1
        else
            local mats
            if type(e.mats) == "table" and #e.mats > 0 then
                local sum, items = {}, {}
                for _, m in ipairs(e.mats) do
                    local mi = type(m) == "table" and Int(m.item, 1, W.MAX_ID) or nil
                    local q = type(m) == "table" and Int(m.qty, 1, W.MAX_QTY) or nil
                    if not mi or not q then sum = nil break end
                    if not sum[mi] then sum[mi] = 0 items[#items + 1] = mi end
                    sum[mi] = sum[mi] + q
                end
                if sum then
                    mats = {}
                    for i, mi in ipairs(items) do mats[i] = { item = mi, qty = sum[mi] } end
                end
            end
            if not mats then P.unknownEntries = P.unknownEntries + 1 end
            local lo = Int(e.outMin, 1, W.MAX_QTY)
            valid[#valid + 1] = { crafts = crafts, mats = mats, outItem = Int(e.outItem, 1, W.MAX_ID), outMin = lo, outMax = lo and (Int(e.outMax, 1, W.MAX_QTY) or lo) or nil }
            P.final[#P.final + 1] = { id = Int(e.id, 1, W.MAX_ID), name = W.Text(e.name, 80), crafts = crafts, outItem = Int(e.outItem, 1, W.MAX_ID) }
        end
    end
    local need, order, _, made = M.Combine(valid)
    P.need, P.made = need, made
    P.roots = {}
    for _, item in ipairs(order) do if need[item] > 0 then P.roots[#P.roots + 1] = item end end
    table.sort(P.roots)
    return P
end

local function Run(P)
    Build(P)
    for item, pick in pairs(type(P.inp.picks) == "table" and P.inp.picks or {}) do
        if not P.index[item] then P.ignoredPicks[item] = pick end
    end
    local n = #P.nodes
    for i = 1, n do P.D[i], P.crafted[i], P.rest[i], P.a[i] = 0, 0, 0, 0 end
    local comps = Components(P)
    local left = P.L.states
    local deciding = 0
    for _, C in ipairs(comps) do if C.decide > 0 then deciding = deciding + 1 end end
    for _, C in ipairs(comps) do
        P:Tick(#C.list + CP.PART_COST)
        P.def = Defaults(P, C)
        -- each part that still has choices to make after this one keeps a small share of the states (a part with none never branches)
        if C.decide > 0 then deciding = deciding - 1 end
        local reserve = 8 * deciding
        C.budget = math.max(8, left - reserve)
        Search(P, C)
        if not C.best then
            -- only a player's choice to make something can leave no plan (every circle or overlong chain of its recipes refused): forget those
            -- choices in this part, say why, and search again
            for _, k in ipairs(C.list) do
                local nd = P.nodes[k]
                if nd.picked == "make" then
                    nd.picked, nd.pickLost, nd.pickWhy = nil, "make", (C.lastWhy and C.lastWhy.why) or "circular"
                    nd.dom = { { kind = "buy" } }
                    for _, r in ipairs(nd.recipes) do nd.dom[#nd.dom + 1] = { kind = "make", r = r } end
                end
            end
            C.decide = 0
            for _, k in ipairs(C.list) do if #P.nodes[k].dom > 1 then C.decide = C.decide + 1 end end
            C.states, C.limited = 0, nil
            P.def = Defaults(P, C)
            Search(P, C)
        end
        left = math.max(0, left - C.states)
        if C.limited then Improve(P, C) end
        -- the baseline of this part: nothing made beyond the queue (every item's buying choice, where the player did not choose to make it)
        local base = {}
        for _, k in ipairs(C.list) do base[k] = P.nodes[k].dom[1].kind == "buy" and 1 or 0 end
        local ok = true
        for _, k in ipairs(C.list) do if base[k] == 0 then ok = false end end
        C.base = ok and Eval(P, C, base, nil) or { ok = false }
        if C.base.ok and C.base.nextK then C.base = { ok = false } end
        C.defaults = P.def
    end
    return Assemble(P, comps)
end

-- The plan, computed at once. inp: as Shopping.Plan's (entries instead of rows): entries (the queue as Materials.Combine reads it), have,
-- stock, auction, cost, vendor, sells, recipes, picks, and optionally available(rec) -> false for a recipe the character cannot do.
-- opt: { objective = "economic" | "cash", limits = { name = number } } (limits replaces entries of CP.LIMITS for this plan: the tests raise and
-- lower them; a caller that raises them owns the extra work). For a real queue use CP.Job: see the doc's measurements.
function CP.Plan(inp, opt)
    local P = Prepare(type(inp) == "table" and inp or {}, opt)
    return Run(P)
end

-- The same plan in steps: job:Step(n) does about n work units (items touched, see P:Tick; CP.STEP per frame) and returns true when the plan is
-- ready; job:Result() is the plan (nil before); job:Cancel() drops the work (Step then returns false). No timer, no frame: the caller steps it.
function CP.Job(inp, opt)
    local P = Prepare(type(inp) == "table" and inp or {}, opt)
    local job = { done = false }
    local co = coroutine.create(function() return Run(P) end)
    P.co = co
    function job:Step(n)
        if self.done then return true end
        if self.cancelled then return false end
        P.slice = Int(n, 1, W.MAX_ID) or 1
        local ok, r = coroutine.resume(co)
        if not ok then self.done, self.failed = true, r error(r, 0) end
        if coroutine.status(co) == "dead" then self.done, self.result = true, r end
        return self.done
    end
    function job:Result() return self.result end
    function job:Cancel() self.cancelled, co, P = true, nil, nil end
    function job:Work() return P and { evals = P.evals, states = P.states } or nil end
    return job
end
