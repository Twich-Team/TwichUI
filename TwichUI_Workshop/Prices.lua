-- TwichUI Workshop: auction prices (the price service)
-- No frames and no auction house calls: Scan.lua reads the auction house and hands records to a batch here; this file keeps what a
-- finished scan found, answers "what did this cost / sell for" and works out what one craft costs and could earn.
--
-- THE PRICING BASIS (the only one in this version, "latest listing"):
--   * a price is the CHEAPEST BUYOUT among the listings the newest scan of that auction house saw, per single item (a stack's buyout
--     divided by its count, rounded UP to whole copper, never below 1 copper);
--   * it is a LISTING price, not a sale: nothing here knows what actually sold, how fast, or at what price;
--   * an auction without a buyout (bid only) is ignored; so is anything that is not a whole number in range;
--   * a missing, invalid or unreadable price is "unknown" (nil). It is never turned into 0, and any unknown input makes the whole
--     cost or profit unknown;
--   * one market per auction house: realm AND the auction house's side, never mixed (see Key).
--
--   TwichUIDB.workshop.prices = { v = 1, markets = { ["Realm|Side"] = market } }   account-wide, bounded, never in a profile,
--       a share or a backup (the same "workshop" key as the queue: Restore.OWN_LEFT_OUT, TwichConfig.LOCAL)
--   market = { realm, side, at (time of the scan), complete, read, used, n (items kept), items = { [itemID] = { p, q, l, t } } }
--       p  cheapest unit price (copper)          q  items listed at that exact price
--       l  buyout listings seen for the item     t  items in those listings
--   An older complete scan is never replaced by a scan that is not complete (Commit says "kept").

local R = TwichUI
local W = R.Workshop
local Q = W.Queue
local Int, Text, Plain = W.Int, W.Text, W.Plain
local PR = {}
W.Prices = PR

PR.SAVED_VERSION = 1
PR.MAX_COPPER = 99999999999   -- MAXIMUM_BID_PRICE in Blizzard_AuctionHouseUI
PR.MAX_COUNT = 10000          -- items in one auction (real stacks are far smaller)
PR.MAX_ITEMS = 2000           -- items kept per market
PR.MAX_MARKETS = 4            -- auction houses kept; the one scanned longest ago goes first
PR.OLD_AFTER = 86400          -- seconds after which the window calls prices old

-- The auction house's cut of a sale, as a fraction, by the auction house's side ("Alliance", "Horde", ...). EMPTY ON PURPOSE: nothing
-- in the Forever UI source states the cut, and it differs between auction houses in other versions of the game. A side is added here
-- only after the cut was confirmed in the game (the mailbox invoice of a sale shows it); until then profit is shown before the cut.
PR.CUT = {}

local MAX_TIME = 4102444800

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
-- Copper per single item for an auction: the buyout of the whole stack divided by its count, rounded up (whole copper, at least 1).
-- nil when either number is not a whole number in range.
function PR.Unit(buyout, count)
    buyout, count = Int(buyout, 1, PR.MAX_COPPER), Int(count, 1, PR.MAX_COUNT)
    if not buyout or not count then return nil end
    local q = math.floor(buyout / count)
    while q * count < buyout do q = q + 1 end
    while q > 1 and (q - 1) * count >= buyout do q = q - 1 end
    return math.max(q, 1)
end

-- The auction house's cut of one sale, whole copper
function PR.Cut(amount, rate) return math.floor(amount * rate + 0.5) end

-- The cut for an auction house side, or nil while it isn't confirmed
function PR.CutRate(side)
    local r = type(side) == "string" and PR.CUT[side] or nil
    if type(r) == "number" and r >= 0 and r < 1 then return r end
    return nil
end

function PR.Age(at, now)
    if type(at) ~= "number" then return nil end
    return math.max(0, (now or time()) - at)
end

function PR.AgeText(seconds)
    if type(seconds) ~= "number" then return "at an unknown time" end
    local function N(n, unit) return ("%d %s%s ago"):format(n, unit, n == 1 and "" or "s") end
    if seconds < 60 then return "just now" end
    if seconds < 3600 then return N(math.floor(seconds / 60), "minute") end
    if seconds < 86400 then return N(math.floor(seconds / 3600), "hour") end
    return N(math.floor(seconds / 86400), "day")
end

---------------------------------------------------------------------------
-- A batch: auction records in, the cheapest buyout per wanted item out
---------------------------------------------------------------------------
-- wanted: set [itemID] = true. Records of other items are only counted.
local Batch = {}
Batch.__index = Batch

function PR.NewBatch(wanted)
    return setmetatable({ wanted = wanted or {}, acc = {}, read = 0, used = 0, noBuyout = 0, invalid = 0, unwanted = 0, partialInfo = 0 }, Batch)
end

-- One auction record: the item, the items in the stack, the buyout of the whole stack (0 = bid only) and whether the game had all of the
-- record's information yet (an explicit false only). Returns true when it counted toward a price.
function Batch:Add(item, count, buyout, hasAllInfo)
    self.read = self.read + 1
    item = Int(item, 1, W.MAX_ID)
    if not item then self.invalid = self.invalid + 1 return false end
    if not self.wanted[item] then self.unwanted = self.unwanted + 1 return false end
    -- only a record of an item we keep a price for can make the scan "not complete": the other scanners ignore this flag altogether,
    -- and a listing nobody asked about says nothing about the prices that were
    if Plain(hasAllInfo) == false then self.partialInfo = self.partialInfo + 1 end
    count = Int(count, 1, PR.MAX_COUNT)
    if not count then self.invalid = self.invalid + 1 return false end
    local raw = Plain(buyout)
    if raw == nil then self.invalid = self.invalid + 1 return false end
    if raw == 0 then self.noBuyout = self.noBuyout + 1 return false end   -- bid only: no buyout to price from
    buyout = Int(raw, 1, PR.MAX_COPPER)
    if not buyout then self.invalid = self.invalid + 1 return false end
    self.used = self.used + 1
    local a = self.acc[item]
    if not a then
        self.acc[item] = { b = buyout, c = count, q = count, l = 1, t = count }
        return true
    end
    a.l, a.t = a.l + 1, a.t + count
    local lhs, rhs = buyout * a.c, a.b * count   -- compares the unit prices exactly, with no division
    if lhs < rhs then a.b, a.c, a.q = buyout, count, count
    elseif lhs == rhs then a.q = a.q + count end
    return true
end

-- { [itemID] = { p, q, l, t } }, how many items, and whether more than the limit were found (the highest item numbers are dropped)
function Batch:Items()
    local ids = {}
    for id in pairs(self.acc) do ids[#ids + 1] = id end
    table.sort(ids)
    local out, n, cut = {}, 0, false
    for _, id in ipairs(ids) do
        if n >= PR.MAX_ITEMS then cut = true break end
        local a = self.acc[id]
        out[id] = { PR.Unit(a.b, a.c), a.q, a.l, a.t }
        n = n + 1
    end
    return out, n, cut
end

---------------------------------------------------------------------------
-- Keeping a scan
---------------------------------------------------------------------------
-- The market of an auction house: its realm and its side. A side that couldn't be read is "unknown", which is a market of its own.
function PR.Key(realm, side)
    realm = Text(realm, 60)
    if not realm then return nil end
    return realm .. "|" .. (Text(side, 20) or "unknown")
end

local function Store(create)
    if type(TwichUIDB) ~= "table" then return nil end
    local ws = TwichUIDB.workshop
    if type(ws) ~= "table" then
        if not create then return nil end
        ws = { v = W.SAVED_VERSION }
        TwichUIDB.workshop = ws
    end
    local p = ws.prices
    if type(p) ~= "table" then
        if not create then return nil end
        p = { v = PR.SAVED_VERSION, markets = {} }
        ws.prices = p
    end
    if type(p.markets) ~= "table" then
        if not create then return nil end
        p.markets = {}
    end
    return p
end

-- True when a newer TwichUI wrote the saved prices (or the workshop data): they are read as far as understood and never changed
function PR.Held()
    if Q.Held() then return true end
    local p = Store(false)
    return p ~= nil and type(p.v) == "number" and p.v > PR.SAVED_VERSION
end

-- The saved scan of one market, checked, or nil
function PR.Market(key)
    local p = type(key) == "string" and Store(false)
    local m = p and p.markets[key]
    if type(m) ~= "table" or type(m.items) ~= "table" then return nil end
    local at = Int(m.at, 1, MAX_TIME)
    if not at then return nil end
    return { key = key, realm = Text(m.realm, 60), side = Text(m.side, 20) or "unknown", at = at, complete = m.complete == true,
        items = m.items, read = Int(m.read, 0, W.MAX_ID), used = Int(m.used, 0, W.MAX_ID), n = Int(m.n, 0, PR.MAX_ITEMS) or 0 }
end

-- Which auction house a market is, in words
function PR.Label(market)
    if type(market) ~= "table" then return nil end
    local realm = market.realm or "this realm"
    if market.side and market.side ~= "unknown" then return ("the %s auction house on %s"):format(market.side, realm) end
    return ("the auction house on %s"):format(realm)
end

-- The market of this realm that was scanned last, or nil
function PR.Newest(realm)
    local p = Store(false)
    if not (p and realm) then return nil end
    local bestKey, bestAt
    for key, m in pairs(p.markets) do
        if type(m) == "table" and m.realm == realm then
            local at = Int(m.at, 1, MAX_TIME)
            if at and (not bestAt or at > bestAt) then bestKey, bestAt = key, at end
        end
    end
    return bestKey and PR.Market(bestKey) or nil
end

-- Keeps a finished scan: scan = { realm, side, at, complete, read, used, items, n }. Returns true, or false and why:
--   "held" (a newer TwichUI wrote this), "bad", "unsaved", or "kept" (the scan is not complete and a complete one is already saved)
function PR.Commit(key, scan)
    if PR.Held() then return false, "held" end
    if type(key) ~= "string" or type(scan) ~= "table" or type(scan.items) ~= "table" then return false, "bad" end
    local at = Int(scan.at, 1, MAX_TIME)
    if not at then return false, "bad" end
    local p = Store(true)
    if not p then return false, "unsaved" end
    local old = PR.Market(key)
    if old and old.complete and scan.complete ~= true then return false, "kept" end
    if p.markets[key] == nil then
        local n, oldestKey, oldestAt = 0, nil, nil
        for k, m in pairs(p.markets) do
            n = n + 1
            local t = type(m) == "table" and Int(m.at, 0, MAX_TIME) or 0
            if not oldestAt or t < oldestAt then oldestKey, oldestAt = k, t end
        end
        if n >= PR.MAX_MARKETS and oldestKey then p.markets[oldestKey] = nil end
    end
    p.markets[key] = { realm = Text(scan.realm, 60), side = Text(scan.side, 20) or "unknown", at = at, complete = scan.complete == true,
        read = Int(scan.read, 0, W.MAX_ID), used = Int(scan.used, 0, W.MAX_ID), n = Int(scan.n, 0, PR.MAX_ITEMS) or 0, items = scan.items }
    return true
end

-- What a market saw of one item: { price (copper each), qty (items at that price), listings, total (items listed), at, complete },
-- or nil when it has nothing usable (never a zero price)
function PR.Lookup(market, item)
    if type(market) ~= "table" then return nil end
    local e = market.items[item]
    if type(e) ~= "table" then return nil end
    local price = Int(e[1], 1, PR.MAX_COPPER)
    if not price then return nil end
    return { price = price, qty = Int(e[2], 1, W.MAX_ID), listings = Int(e[3], 1, W.MAX_ID), total = Int(e[4], 1, W.MAX_ID),
        at = market.at, complete = market.complete }
end

-- What buying `qty` of an item at that auction house is expected to cost, from what the scan saw of it (Lookup's answer, or nil).
-- A scan keeps only the cheapest price, how many items are listed at exactly that price (`qty`) and how many are listed in all
-- (`total`), so only these can be said, and the answer says which one it is:
--   state "exact"     qty is no more than the items listed at the cheapest price: cost = price x qty, backed by listings
--   state "estimate"  more are listed than that (or the scan did not say): cost = price x qty is the LEAST it could cost, since the
--                     further items sell for more; it is a unit-price estimate, never proof the listings exist at that price
--   state "few"       fewer items are listed in all than asked for: it cannot be bought here in that quantity (cost nil)
--   state "none"      nothing usable was seen (cost nil; never 0)
-- unit, listed (items at the cheapest price), total, at (scan time) and complete come from the lookup.
function PR.Quote(p, qty)
    qty = Int(qty, 1, W.MAX_ID)
    if not qty or type(p) ~= "table" or not p.price then return { state = "none", qty = qty } end
    local q = { qty = qty, unit = p.price, listed = p.qty, total = p.total, at = p.at, complete = p.complete }
    if p.total and p.total < qty then
        q.state = "few"
    else
        q.state = (p.qty ~= nil and qty <= p.qty) and "exact" or "estimate"
        q.cost = p.price * qty
    end
    return q
end

---------------------------------------------------------------------------
-- One craft: cost, sell price, profit
---------------------------------------------------------------------------
-- rec: { outItem, outMin, outMax, mats = { { item, qty } } } (a recipe the window read). lookup(item) -> PR.Lookup's answer or nil.
-- rate: the auction house's cut when confirmed, else nil.
-- Everything is for ONE craft, with the materials the recipe needs in full (owning them does not make them free).
-- Returns e:
--   state     "ok" (cost and sell price both known, so the profit is) or "unknown"
--   why       when unknown: "nomats" (materials not known or not supported), "noitem" (makes no item), "noamount" (output not known),
--             "matprice" (a material has no usable price), "sellprice" (what it makes has no usable price)
--   cost      copper, nil unless every material is priced;  mats = { { item, qty, unit, total, at, cheapest, complete, unavailable } }
--   outMin, outMax, unit (sell price each), sellLow, sellHigh (all of one craft's output, at the fewest and the most items)
--   netLow, netHigh (after the cut), profitLow, profitHigh (net minus cost; a range when the output is a range, never the maximum alone)
--   oldest (the oldest observation used), incomplete (a price came from a scan that was not complete),
--   cheapest (a material needs more than the cheapest listing holds: buying that many costs more than shown)
function PR.Estimate(rec, lookup, rate)
    local e = { state = "unknown", mats = {}, missing = 0, cutRate = rate }
    local oldest, incomplete, cheapest = nil, false, false
    local function Seen(p)
        if not oldest or p.at < oldest then oldest = p.at end
        if p.complete ~= true then incomplete = true end
    end

    local outItem = Int(rec.outItem, 1, W.MAX_ID)
    local lo, hi = Int(rec.outMin, 1, W.MAX_QTY), Int(rec.outMax, 1, W.MAX_QTY)
    if lo and not hi then hi = lo elseif hi and not lo then lo = hi end
    if lo and hi < lo then lo, hi = nil, nil end
    e.outMin, e.outMax = lo, hi

    local hasMats = type(rec.mats) == "table" and #rec.mats > 0
    if hasMats then
        local cost = 0
        for _, m in ipairs(rec.mats) do
            local row = { item = m.item, qty = m.qty }
            local p = lookup(m.item)
            local quote = PR.Quote(p, m.qty)
            if quote.state == "few" or quote.state == "none" then
                row.unavailable = quote.state   -- "few": not enough is listed to buy what one craft needs
                p = nil
            end
            if p then
                row.unit, row.at, row.complete = p.price, p.at, p.complete
                row.total = quote.cost
                row.cheapest = p.qty ~= nil and m.qty > p.qty
                cost = cost + row.total
                Seen(p)
                if row.cheapest then cheapest = true end
            else
                e.missing = e.missing + 1
            end
            e.mats[#e.mats + 1] = row
        end
        if e.missing == 0 then e.cost = cost end
    end

    local sellMissing = false
    if outItem and lo then
        local p = lookup(outItem)
        if p then
            e.unit = p.price
            e.sellLow, e.sellHigh = p.price * lo, p.price * hi
            Seen(p)
            local cutLow = rate and PR.Cut(e.sellLow, rate) or 0
            local cutHigh = rate and PR.Cut(e.sellHigh, rate) or 0
            e.netLow, e.netHigh = e.sellLow - cutLow, e.sellHigh - cutHigh
        else
            sellMissing = true
        end
    end

    if not hasMats then e.why = "nomats"
    elseif not outItem then e.why = "noitem"
    elseif not lo then e.why = "noamount"
    elseif e.missing > 0 then e.why = "matprice"
    elseif sellMissing then e.why = "sellprice" end

    if e.cost and e.netLow then
        e.state = "ok"
        e.why = nil
        e.profitLow, e.profitHigh = e.netLow - e.cost, e.netHigh - e.cost
    end
    e.oldest, e.incomplete, e.cheapest = oldest, incomplete, cheapest
    return e
end
