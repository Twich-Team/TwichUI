-- TwichUI Workshop: auction prices (the storage and collection half of the price service)
-- No frames and no auction house calls: Scan.lua reads the auction house and hands records to a batch here; this file keeps what a
-- finished scan found and merges it into the price history (History.lua). Market.lua is the API every other feature asks; this file
-- also works out what one craft costs and could earn (Estimate) and what buying n of an item costs (Quote).
--
-- THE PRICING BASIS ("latest listing"):
--   * a price is the CHEAPEST BUYOUT among the listings the newest scan of that auction house saw, per single item (a stack's buyout
--     divided by its count, rounded UP to whole copper, never below 1 copper);
--   * it is a LISTING price, not a sale: nothing here knows what actually sold, how fast, or at what price;
--   * an auction without a buyout (bid only, a finite 0) is ignored; so is anything that is not a whole number in range, and a NaN or an
--     infinity is INVALID, never bid-only (W.Finite is checked before the zero test);
--   * a missing, invalid or unreadable price is "unknown" (nil). It is never turned into 0, and any unknown input makes the whole
--     cost or profit unknown;
--   * one market per auction house: realm AND the auction house's side, never mixed (see Key);
--   * one price per ITEM ID. A full scan cannot tell variants of an item id apart (suffix, bonus ids, item level), so the cheapest
--     variant sets the price; Market.Price refuses a price for an item the caller says is a variant.
--
-- WHAT IS SAVED (account-wide, NOT in TwichUIDB: a market holds up to MAX_ITEMS items and a history, so it lives in the Workshop's
-- own saved variables, which the game loads only when the Workshop is loaded; never in a profile, a share or a backup):
--   TwichUIWorkshopDB = { v = 1, markets = { ["Realm|Side"] = market } }
--   market = { f = 2, scope = "full", realm, side, at (time of the scan), complete, cut, read, used, partial, n (items kept),
--              items = { [itemID] = "p,q,l,t,x" }   the newest accepted scan: what it saw of each item
--              hist  = { [itemID] = "..." }          the item's history (History.lua), kept across scans
--              sd    = { day, ... } }                the days of the scans that fed the history (newest last, MAX_SCAN_DAYS)
--       p  cheapest unit price (copper)           q  items listed at that exact price
--       l  buyout listings seen for the item      t  items in those listings
--       x  the next higher unit price listed (0 = every listing was at p, or it could not be told)
--   scope "full": every item the auction house listed was kept. cut: listings may be missing (the read was cut off, or the number of
--   listings kept changing); partial: records whose item information had not all loaded when read (their prices were used).
--   LEGACY (before the market data foundation): TwichUIDB.workshop.prices.markets[key] = { realm, side, at, complete, read, used, n,
--   items = { [itemID] = { p, q, l, t } } } holding ONLY the items of the recipes known at scan time. It is read, never rewritten, and
--   always reported as scope "recipes" (whatever its `complete` says: complete meant "of those items"); the first full scan of the
--   same market replaces it.
--   An older complete scan is never replaced by a scan that is not complete (Commit says "kept").

local R = TwichUI
local W = R.Workshop
local Q = W.Queue
local Int, Text, Plain = W.Int, W.Text, W.Plain
local H = W.History
local PR = {}
W.Prices = PR

PR.SAVED_VERSION = 1
PR.MAX_COPPER = 99999999999   -- MAXIMUM_BID_PRICE in Blizzard_AuctionHouseUI
PR.MAX_COUNT = 10000          -- items in one auction (real stacks are far smaller)
PR.MAX_ITEMS = 40000          -- items kept per market (see "Item limit" in docs/workshop.md)
PR.MAX_MARKETS = 3            -- auction houses kept; the one scanned longest ago goes first
PR.OLD_AFTER = 86400          -- seconds after which the window calls prices old
PR.COMMIT_STEP = 120          -- items merged into the history per step of a commit

-- The auction house's cut of a sale, as a fraction, by the auction house's side ("Alliance", "Horde", ...). EMPTY ON PURPOSE: nothing
-- in the Forever UI source states the cut, and it differs between auction houses in other versions of the game. A side is added here
-- only after the cut was confirmed in the game (the mailbox invoice of a sale shows it); until then profit is shown before the cut.
PR.CUT = {}

local MAX_TIME = 4102444800
local floor = math.floor

local function N(v) return ("%.0f"):format(v) end

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
-- A batch: auction records in, the cheapest buyout per item out
---------------------------------------------------------------------------
-- priority: optional set [itemID] = true of items to keep first should a market hold more than MAX_ITEMS (the recipes' items). It limits
-- nothing: every valid item is counted. Passing a function-less nil is the normal case.
local Batch = {}
Batch.__index = Batch

function PR.NewBatch(priority)
    return setmetatable({ priority = priority, acc = {}, read = 0, used = 0, noBuyout = 0, invalid = 0, partialInfo = 0 }, Batch)
end

-- One auction record: the item, the items in the stack, the buyout of the whole stack (0 = bid only) and whether the game had all of the
-- record's information yet (an explicit false only). Returns true when it counted toward a price.
function Batch:Add(item, count, buyout, hasAllInfo)
    self.read = self.read + 1
    item = Int(item, 1, W.MAX_ID)
    if not item then self.invalid = self.invalid + 1 return false end
    if Plain(hasAllInfo) == false then self.partialInfo = self.partialInfo + 1 end
    count = Int(count, 1, PR.MAX_COUNT)
    if not count then self.invalid = self.invalid + 1 return false end
    -- finite first: in the client a NaN equals 0, so the bid-only test below must never see one (see W.Finite)
    local raw = Plain(buyout)
    if not W.Finite(raw) then self.invalid = self.invalid + 1 return false end
    if raw == 0 then self.noBuyout = self.noBuyout + 1 return false end   -- bid only: no buyout to price from
    buyout = Int(raw, 1, PR.MAX_COPPER)
    if not buyout then self.invalid = self.invalid + 1 return false end
    self.used = self.used + 1
    local a = self.acc[item]
    if not a then
        -- b/c: the cheapest unit price as a fraction (buyout / count); q: items at it; l, t: listings and items; b2/c2: the next higher
        self.acc[item] = { b = buyout, c = count, q = count, l = 1, t = count }
        return true
    end
    a.l, a.t = a.l + 1, a.t + count
    local lhs, rhs = buyout * a.c, a.b * count   -- compares the unit prices exactly, with no division
    if lhs < rhs then
        a.b2, a.c2 = a.b, a.c
        a.b, a.c, a.q = buyout, count, count
    elseif lhs == rhs then
        a.q = a.q + count
    elseif not a.b2 or buyout * a.c2 < a.b2 * count then
        a.b2, a.c2 = buyout, count
    end
    return true
end

local function Entry(a)
    local p = PR.Unit(a.b, a.c)
    local x = a.b2 and PR.Unit(a.b2, a.c2) or 0
    if x <= p then x = 0 end   -- the next price rounds to the same copper: not a different price in whole copper
    return ("%s,%s,%s,%s,%s"):format(N(p), N(a.q), N(a.l), N(a.t), N(x))
end

-- { [itemID] = "p,q,l,t,x" }, how many items, whether more than MAX_ITEMS were found, and how many were dropped. Over the limit the
-- kept items are the priority items first, then those with the most listings, then the lowest item numbers (a fixed, explainable
-- order, never a cut by item number alone); `dropped` says how many valid items did not fit.
--
-- It is built by an ItemsJob so the scan can do it a few hundred items at a time (M7.1: at 40,000 items the single call was a visible
-- hitch, 40 ms at 12,000 items and over 100 ms at the limit, offline). Items() runs the same job to the end, so both give one answer.
local ItemsJob = {}
ItemsJob.__index = ItemsJob

PR.ITEMS_STEP = 400          -- items turned into saved entries per step of an ItemsJob (the size of a scan's read step)

function Batch:ItemsJob()
    return setmetatable({ acc = self.acc, priority = self.priority, out = {}, n = 0, phase = "count", cursor = nil }, ItemsJob)
end

-- Does up to `limit` items of work (counting and listing an item cost a tenth of building its entry). Returns true when finished.
-- The batch's table must not change meanwhile (a scan's batch is complete when this starts). The one piece that cannot be split is
-- the sort of a market over MAX_ITEMS, which is rare; it happens in one step.
function ItemsJob:Step(limit)
    limit = limit or PR.ITEMS_STEP
    local acc, out = self.acc, self.out
    local light = limit * 10
    if self.phase == "count" then
        local id = self.cursor
        while light > 0 do
            id = next(acc, id)
            if id == nil then
                self.cursor = nil
                if self.n <= PR.MAX_ITEMS then self.phase = "build" else self.phase, self.ids = "collect", {} end
                break
            end
            self.n = self.n + 1
            self.cursor = id
            light = light - 1
        end
        if self.phase == "count" then return false end
    end
    if self.phase == "build" then
        local id, left = self.cursor, limit
        while left > 0 do
            id = next(acc, id)
            if id == nil then self.phase = "done" self.cursor = nil return true end
            out[id] = Entry(acc[id])
            self.cursor = id
            left = left - 1
        end
        return false
    end
    if self.phase == "collect" then
        local ids, id = self.ids, self.cursor
        while light > 0 do
            id = next(acc, id)
            if id == nil then
                self.cursor = nil
                local pri = self.priority or {}
                table.sort(ids, function(x, y)
                    local px, py = pri[x] and 1 or 0, pri[y] and 1 or 0
                    if px ~= py then return px > py end
                    local lx, ly = acc[x].l, acc[y].l
                    if lx ~= ly then return lx > ly end
                    return x < y
                end)
                self.phase, self.at = "sorted", 0
                return false
            end
            ids[#ids + 1] = id
            self.cursor = id
            light = light - 1
        end
        return false
    end
    if self.phase == "sorted" then
        local ids, left = self.ids, limit
        while left > 0 and self.at < PR.MAX_ITEMS do
            self.at = self.at + 1
            local id = ids[self.at]
            out[id] = Entry(acc[id])
            left = left - 1
        end
        if self.at >= PR.MAX_ITEMS then self.phase = "done" return true end
        return false
    end
    return self.phase == "done"
end

-- items, how many, whether over the limit, how many dropped; only once Step has returned true
function ItemsJob:Result()
    if self.phase ~= "done" then return nil end
    if self.n <= PR.MAX_ITEMS then return self.out, self.n, false, 0 end
    return self.out, PR.MAX_ITEMS, true, self.n - PR.MAX_ITEMS
end

function Batch:Items()
    local job = self:ItemsJob()
    while not job:Step(math.huge) do end
    return job:Result()
end

---------------------------------------------------------------------------
-- The saved markets
---------------------------------------------------------------------------
-- The market of an auction house: its realm and its side. A side that couldn't be read is "unknown", which is a market of its own.
function PR.Key(realm, side)
    realm = Text(realm, 60)
    if not realm then return nil end
    return realm .. "|" .. (Text(side, 20) or "unknown")
end

-- The Workshop's own saved variables. They are read when asked, never captured: the game fills the global in only after the addon's
-- files have run.
local function Store(create)
    local db = TwichUIWorkshopDB
    if type(db) ~= "table" then
        if not create then return nil end
        db = { v = PR.SAVED_VERSION, markets = {} }
        TwichUIWorkshopDB = db
    end
    if type(db.markets) ~= "table" then
        if not create then return nil end
        db.markets = {}
    end
    return db
end

-- The earlier saved prices (recipe items only), or nil. Read only; ignored when a newer TwichUI wrote them.
local function LegacyStore()
    if type(TwichUIDB) ~= "table" then return nil end
    local ws = TwichUIDB.workshop
    local p = type(ws) == "table" and ws.prices or nil
    if type(p) ~= "table" or type(p.markets) ~= "table" then return nil end
    if type(p.v) == "number" and p.v > 1 then return nil end
    return p
end

-- True when a newer TwichUI wrote the saved prices (or the workshop data): they are read as far as understood and never changed
function PR.Held()
    if Q.Held() then return true end
    local p = Store(false)
    return p ~= nil and type(p.v) == "number" and p.v > PR.SAVED_VERSION
end

local function Checked(key, m, legacy)
    if type(m) ~= "table" or type(m.items) ~= "table" then return nil end
    local at = Int(m.at, 1, MAX_TIME)
    if not at then return nil end
    local info = { key = key, realm = Text(m.realm, 60), side = Text(m.side, 20) or "unknown", at = at, complete = m.complete == true,
        items = m.items, read = Int(m.read, 0, W.MAX_ID), used = Int(m.used, 0, W.MAX_ID), n = Int(m.n, 0, PR.MAX_ITEMS) or 0 }
    if legacy or m.scope ~= "full" then
        -- Whatever it called itself, a scan from before the full scan holds only the recipes' items: "complete" meant "of those"
        info.scope, info.legacy = "recipes", true
    else
        info.scope = "full"
        info.cut = m.cut == true
        if info.cut then info.complete = false end   -- a cut scan is never complete, whatever a damaged flag says
        info.partial = Int(m.partial, 0, W.MAX_ID) or 0
        info.hist = type(m.hist) == "table" and m.hist or nil
        info.histItems = Int(m.hn, 0, W.MAX_ID) or 0
        info.scanDays = type(m.sd) == "table" and m.sd or nil
    end
    return info
end

-- The saved scan of one market, checked, or nil
function PR.Market(key)
    if type(key) ~= "string" then return nil end
    local db = Store(false)
    local m = db and db.markets[key]
    if m ~= nil then return Checked(key, m, false) end
    local lp = LegacyStore()
    m = lp and lp.markets[key]
    if m ~= nil then return Checked(key, m, true) end
    return nil
end

-- Which auction house a market is, in words
function PR.Label(market)
    if type(market) ~= "table" then return nil end
    local realm = market.realm or "this realm"
    if market.side and market.side ~= "unknown" then return ("the %s auction house on %s"):format(market.side, realm) end
    return ("the auction house on %s"):format(realm)
end

-- Every saved market key (new and legacy; a legacy market a new one replaced is not listed twice), in no particular order
function PR.Keys()
    local keys, seen = {}, {}
    local db = Store(false)
    if db then for k, m in pairs(db.markets) do if type(k) == "string" and type(m) == "table" then seen[k] = true keys[#keys + 1] = k end end end
    local lp = LegacyStore()
    if lp then for k, m in pairs(lp.markets) do if type(k) == "string" and type(m) == "table" and not seen[k] then keys[#keys + 1] = k end end end
    return keys
end

-- The market of this realm that was scanned last, or nil
function PR.Newest(realm)
    if not realm then return nil end
    local bestKey, bestAt
    for _, key in ipairs(PR.Keys()) do
        local m = PR.Market(key)
        if m and m.realm == realm and (not bestAt or m.at > bestAt) then bestKey, bestAt = key, m.at end
    end
    return bestKey and PR.Market(bestKey) or nil
end

---------------------------------------------------------------------------
-- Keeping a scan: a commit is a job that works in steps and changes nothing until its last one
---------------------------------------------------------------------------
-- scan = { realm, side, at, complete, cut, changed, read, used, partial, items = { [id] = "p,q,l,t,x" }, n }. A history observation is
-- added for every item of a scan that is a whole read (not cut, not changed while read): it is valid evidence of that day's cheapest
-- listing whether or not every record's item information had loaded (its prices were used all the same).
--
-- PR.BeginCommit(key, scan) -> job, or false and why: "held" (a newer TwichUI wrote this), "bad", "kept" (the scan is not complete and a
-- complete one is saved). job:Step() merges up to COMMIT_STEP items and returns true when all are merged; job:Apply() then writes everything
-- at once and returns true, or false and why ("held", "unsaved"). Nothing is written before Apply, so a job that is dropped, or a step
-- that fails, leaves the saved market and its history exactly as they were.
local Job = {}
Job.__index = Job

local function HistoryUsable(scan) return scan.cut ~= true and scan.changed ~= true end

function PR.BeginCommit(key, scan)
    if PR.Held() then return false, "held" end
    if type(key) ~= "string" or type(scan) ~= "table" or type(scan.items) ~= "table" then return false, "bad" end
    local at = Int(scan.at, 1, MAX_TIME)
    if not at then return false, "bad" end
    local old = PR.Market(key)
    if old and old.complete and scan.complete ~= true and not old.legacy then return false, "kept" end
    local day = H.Day(at)
    local job = setmetatable({ key = key, scan = scan, at = at, old = old, upd = {}, drop = {}, phase = "scan", cursor = nil, done = 0,
        total = 0, added = 0, day = day, feed = day ~= nil and HistoryUsable(scan) }, Job)
    local oldHist = old and old.scope == "full" and old.hist or nil
    job.oldHist = oldHist
    job.oldCount = 0
    if oldHist then for _ in pairs(oldHist) do job.oldCount = job.oldCount + 1 end end
    local n = 0
    for _ in pairs(scan.items) do n = n + 1 end
    job.total = n + job.oldCount
    return job
end

-- Merges up to `limit` more items. Returns true when every item has been merged.
function Job:Step(limit)
    limit = limit or PR.COMMIT_STEP
    local oldHist, upd, drop, day = self.oldHist, self.upd, self.drop, self.day
    local left = limit
    if self.phase == "scan" then
        local id, entry = self.cursor, nil
        while left > 0 do
            id, entry = next(self.scan.items, id)
            if id == nil then self.phase = "old" self.cursor = nil break end
            left = left - 1
            self.done = self.done + 1
            if self.feed and Int(id, 1, W.MAX_ID) then
                local p = type(entry) == "string" and tonumber(entry:match("^(%d+),")) or nil
                if p and p >= 1 and p <= PR.MAX_COPPER then
                    local s = H.Add(oldHist and oldHist[id] or nil, day, p)
                    if s then
                        upd[id] = s
                        if not (oldHist and oldHist[id] ~= nil) then self.added = self.added + 1 end
                    end
                end
            end
            self.cursor = id
        end
    end
    if self.phase == "old" then
        -- items this scan did not list keep their history, minus what expired; the history of an item is dropped when nothing is left
        local id, s = self.cursor, nil
        local source = oldHist or {}
        while left > 0 do
            id, s = next(source, id)
            if id == nil then self.phase = "ready" self.cursor = nil break end
            left = left - 1
            self.done = self.done + 1
            if upd[id] == nil and day then
                local t = H.Trim(s, day)
                if t == nil then drop[id] = true self.dropped = (self.dropped or 0) + 1 elseif t ~= s then upd[id] = t end
            end
            self.cursor = id
        end
    end
    return self.phase == "ready"
end

function Job:Progress() return self.total > 0 and math.min(1, self.done / self.total) or 1 end

function Job:Apply()
    if self.phase ~= "ready" then return false, "bad" end
    if PR.Held() then return false, "held" end
    local db = Store(true)
    if not db then return false, "unsaved" end
    local key, scan, old = self.key, self.scan, self.old
    -- the history table is the old one changed in place (its items are the same strings), or a new one for a first scan
    local hist = self.oldHist
    if not hist then hist = {} end
    for id, s in pairs(self.upd) do hist[id] = s end
    for id in pairs(self.drop) do hist[id] = nil end
    local sd = {}
    if old and old.scanDays then for _, d in ipairs(old.scanDays) do if type(d) == "number" then sd[#sd + 1] = d end end end
    if self.feed and self.day then
        if sd[#sd] ~= self.day then
            if sd[#sd] == nil or sd[#sd] < self.day then sd[#sd + 1] = self.day end
        end
        while #sd > H.MAX_SCAN_DAYS do table.remove(sd, 1) end
    end
    if db.markets[key] == nil then
        local count, oldestKey, oldestAt = 0, nil, nil
        for k, m in pairs(db.markets) do
            count = count + 1
            local t = type(m) == "table" and Int(m.at, 0, MAX_TIME) or 0
            if not oldestAt or t < oldestAt then oldestKey, oldestAt = k, t end
        end
        if count >= PR.MAX_MARKETS and oldestKey then db.markets[oldestKey] = nil end
    end
    db.markets[key] = { f = 2, scope = "full", realm = Text(scan.realm, 60), side = Text(scan.side, 20) or "unknown", at = self.at,
        complete = scan.complete == true, cut = scan.cut == true or scan.changed == true or nil, read = Int(scan.read, 0, W.MAX_ID),
        used = Int(scan.used, 0, W.MAX_ID), partial = Int(scan.partial, 0, W.MAX_ID) or 0, n = Int(scan.n, 0, PR.MAX_ITEMS) or 0,
        hn = self.oldCount + self.added - (self.dropped or 0), items = scan.items, hist = hist, sd = sd }
    -- the earlier recipe-only scan of this market is replaced by this one: it is not kept twice
    local lp = LegacyStore()
    if lp and lp.markets[key] ~= nil then lp.markets[key] = nil end
    return true
end

-- All of it at once (used by tests and callers that need no steps). Returns true, or false and why.
function PR.Commit(key, scan)
    local job, why = PR.BeginCommit(key, scan)
    if not job then return false, why end
    while not job:Step(math.huge) do end
    return job:Apply()
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
local function Entry5(e)
    if type(e) == "string" then
        local p, q, l, t, x = e:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$")
        if not p then
            p, q, l, t = e:match("^(%d+),(%d+),(%d+),(%d+)$")
            x = "0"
        end
        if not p then return nil end
        return tonumber(p), tonumber(q), tonumber(l), tonumber(t), tonumber(x)
    elseif type(e) == "table" then
        return e[1], e[2], e[3], e[4], 0
    end
    return nil
end

-- What a market saw of one item: { price (copper each), qty (items at that price), listings, total (items listed), next (the next
-- higher unit price, or nil), at, complete, scope },
-- or nil when it has nothing usable (never a zero price)
function PR.Lookup(market, item)
    if type(market) ~= "table" or type(market.items) ~= "table" then return nil end
    local p, q, l, t, x = Entry5(market.items[item])
    local price = Int(p, 1, PR.MAX_COPPER)
    if not price then return nil end
    x = Int(x, 1, PR.MAX_COPPER)
    return { price = price, qty = Int(q, 1, W.MAX_ID), listings = Int(l, 1, W.MAX_ID), total = Int(t, 1, W.MAX_ID),
        next = x and x > price and x or nil, at = market.at, complete = market.complete, scope = market.scope }
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
