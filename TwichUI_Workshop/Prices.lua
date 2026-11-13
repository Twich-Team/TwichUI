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
--   TwichUIWorkshopDB = { v = 2, markets = { ["Realm|Side"] = market } }   (v 1 is read; the first accepted commit writes v 2)
--   market = { f = 3 (or 2, written by TwichUI 1.3), scope = "full", realm, side, at (time of the scan), complete, cut, read, used,
--              partial, n (items kept),
--              items = { [itemID] = "p,q,l,t,x" }   the newest accepted scan: what it saw of each item
--              hist  = { [itemID] = "..." }          the item's FROZEN legacy minimum-buyout history (History.lua): trimmed by expiry,
--                                                    never extended by a scan of format 3 (docs/workshop/market-data-foundation-v2.md)
--              sd    = { day, ... } }                the days of the scans that fed that legacy history (frozen with it)
--   Format 3 adds, beside those (section 3.2 of the foundation document): snap (the newest accepted scan's facts), scans (a bounded log
--   of accepted scans), days (a 120-day log of scan days), v2from (the first day of version-2 coverage) and the later milestones'
--   containers dist, h2, c2, which this version never fills and only carries forward untouched. Format 3 data is what makes TwichUI 1.3
--   hold the database (v 2 > its v 1): it reads, and refuses every write.
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

PR.SAVED_VERSION = 2          -- TwichUIWorkshopDB.v: written by the first accepted commit (1 = TwichUI 1.3, which holds a database above 1)
PR.MARKET_FORMAT = 3          -- market.f written by this version (2 = TwichUI 1.3's markets, still read)
PR.SCAN_LOG_MIN, PR.SCAN_LOG_MAX, PR.SCAN_LOG_HOURS = 64, 256, 48   -- scans kept in market.scans: all of the last 48 h, at least 64, at most 256
PR.DAY_LOG_DAYS = 120         -- scan days kept in market.days
-- The legacy minimum-buyout history is FROZEN (market data foundation 2.0): a scan expires what is too old and adds nothing to it. The
-- 1.3 feeding code below stays only so History.lua, the readers and the reference model are still exercised end to end; production never
-- turns this on (tests do, and tests/test_workshop_schema.lua proves the default). Version-2 history arrives with milestone A4.
PR.FEED_LEGACY_HISTORY = false
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
        db = { v = PR.SAVED_VERSION, markets = {} }   -- only ever created inside an Apply
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

---------------------------------------------------------------------------
-- Format 3 metadata: validated readers (a malformed field is absent, never repaired, and never makes the price entries unreadable)
---------------------------------------------------------------------------
-- Scan flags (market.scans, a decimal bit set). FED_HISTORY is reserved: version-2 history is written from A4 on.
local F_WHOLE, F_COMPLETE, F_CUT, F_CHANGED, F_PARTIAL, F_AUTO = 1, 2, 4, 8, 16, 32
local F_ALL = 1 + 2 + 4 + 8 + 16 + 32 + 64 + 128   -- including FED_HISTORY (64) and IMPORTED (128), reserved
-- Day flags (market.days): any whole read / any scan that was cut or changed / any scan with records lacking their information
local D_WHOLE, D_INCOMPLETE, D_PARTIAL = 1, 2, 4
PR.SCAN_FLAGS = { WHOLE = F_WHOLE, COMPLETE = F_COMPLETE, CUT = F_CUT, CHANGED = F_CHANGED, PARTIAL = F_PARTIAL, AUTO = F_AUTO }
PR.DAY_FLAGS = { WHOLE = D_WHOLE, INCOMPLETE = D_INCOMPLETE, PARTIAL = D_PARTIAL }

-- "seq,at,flags,items,records" -> { seq, at, flags, items, records }, or nil
local function ScanEntry(e)
    if type(e) ~= "string" or #e > 80 then return nil end
    local a, b, c, d, f = e:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$")
    if not a then return nil end
    local seq, at, flags = Int(tonumber(a), 1, W.MAX_ID), Int(tonumber(b), 1, MAX_TIME), Int(tonumber(c), 0, F_ALL)
    local items, records = Int(tonumber(d), 0, W.MAX_ID), Int(tonumber(f), 0, W.MAX_ID)
    if not (seq and at and flags and items and records) then return nil end
    return { seq = seq, at = at, flags = flags, items = items, records = records }
end

-- "day,scans,flags" -> { day, scans, flags }, or nil
local function DayEntry(e)
    if type(e) ~= "string" or #e > 40 then return nil end
    local a, b, c = e:match("^(%d+),(%d+),(%d+)$")
    if not a then return nil end
    local day, n, flags = H.Day(tonumber(a) * H.DAY), Int(tonumber(b), 1, W.MAX_ID), Int(tonumber(c), 0, 7)
    if not (day and n and flags) then return nil end
    return { day = day, scans = n, flags = flags }
end

-- The valid entries of a scan log or day log, in saved order (nil when the field is not a list). Parsed on demand only.
local function Entries(list, parse)
    if type(list) ~= "table" then return nil end
    local out = {}
    for i = 1, #list do local e = parse(list[i]) if e then out[#out + 1] = e end end
    return out
end

function PR.ScanLog(market) return market and Entries(market.scanLog, ScanEntry) or nil end
function PR.DayLog(market) return market and Entries(market.dayLog, DayEntry) or nil end

local function Snap(t)
    if type(t) ~= "table" then return nil end
    local seq, at = Int(t.seq, 1, W.MAX_ID), Int(t.at, 1, MAX_TIME)
    if not seq or not at or t.kind ~= "full" then return nil end
    local snap = { seq = seq, kind = "full", at = at, auto = t.auto == true }
    for _, k in ipairs({ "records", "used", "invalid", "noBuyout", "partial", "items" }) do snap[k] = Int(t[k], 0, W.MAX_ID) end
    snap.alg = Int(t.alg, 1, 99)
    snap.client = Text(t.client, 40)
    return snap
end

local function Compact(t)
    if type(t) ~= "table" then return nil end
    local level, at, items = Int(t.level, 1, 9), Int(t.at, 1, MAX_TIME), Int(t.items, 0, W.MAX_ID)
    if not (level and at and items) then return nil end
    return { level = level, at = at, items = items }
end

-- The saved database's version, or nil when there is none (1 = TwichUI 1.3, 2 = market data foundation 2.0)
function PR.DbVersion()
    local db = Store(false)
    return db and Int(db.v, 0, 1000) or nil
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
        -- format 3 (a format 2 market simply has none of it); only what is cheap to check is checked here, the logs are checked on demand
        info.format = m.f == 3 and 3 or 2
        if info.format == 3 then
            info.snap = Snap(m.snap)
            local from = Int(m.v2from, 1, 200000)
            info.v2from = from and H.Day(from * H.DAY) or nil
            info.compact = Compact(m.compact)
            info.scanLog = type(m.scans) == "table" and m.scans or nil
            info.dayLog = type(m.days) == "table" and m.days or nil
        end
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

local function WholeRead(scan) return scan.cut ~= true and scan.changed ~= true end

function PR.BeginCommit(key, scan)
    if PR.Held() then return false, "held" end
    if type(key) ~= "string" or type(scan) ~= "table" or type(scan.items) ~= "table" then return false, "bad" end
    local at = Int(scan.at, 1, MAX_TIME)
    if not at then return false, "bad" end
    local old = PR.Market(key)
    if old and old.complete and scan.complete ~= true and not old.legacy then return false, "kept" end
    -- the legacy minimum history is FROZEN (format 3): a scan never adds to it, it only expires what is too old (the "old" phase)
    local day = H.Day(at)
    local feed = PR.FEED_LEGACY_HISTORY == true and day ~= nil and WholeRead(scan)
    local job = setmetatable({ key = key, scan = scan, at = at, old = old, upd = {}, drop = {}, phase = feed and "scan" or "old", cursor = nil,
        done = 0, total = 0, added = 0, day = day, feed = feed }, Job)
    local oldHist = old and old.scope == "full" and old.hist or nil
    job.oldHist = oldHist
    job.oldCount = 0
    if oldHist then for _ in pairs(oldHist) do job.oldCount = job.oldCount + 1 end end
    local n = 0
    if feed then for _ in pairs(scan.items) do n = n + 1 end end
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
            if Int(id, 1, W.MAX_ID) then
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
        -- legacy history only expires (and, with FEED_LEGACY_HISTORY, an item the scan did not list keeps its history minus that): an item's history is dropped when nothing is left of it
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

-- The build string, when the game says it (nil in tests and when unreadable; never a guess)
local function ClientBuild()
    if type(GetBuildInfo) ~= "function" then return nil end
    local ok, version, build = pcall(GetBuildInfo)
    if not ok or type(version) ~= "string" then return nil end
    return Text(type(build) == "string" and (version .. "." .. build) or version, 40)
end

-- a bit set kept as a decimal number: the union of two sets of the small bits in `bits` (Lua 5.1 has no bitwise operators)
local function Union(a, b, bits)
    local out = 0
    for _, bit in ipairs(bits) do
        if floor(a / bit) % 2 == 1 or floor(b / bit) % 2 == 1 then out = out + bit end
    end
    return out
end

-- The scan log and day log after one more accepted scan, as saved strings. Pure: no saved table is touched. Only valid earlier entries
-- are carried forward; a malformed one is dropped, never repaired.
local function Logs(old, scan, at, day, seq)
    local whole, partial = WholeRead(scan), (Int(scan.partial, 0, W.MAX_ID) or 0) > 0
    local flags = (whole and F_WHOLE or 0) + (scan.complete == true and F_COMPLETE or 0) + (scan.cut == true and F_CUT or 0)
        + (scan.changed == true and F_CHANGED or 0) + (partial and F_PARTIAL or 0) + (scan.auto == true and F_AUTO or 0)
    local scans = {}
    for _, e in ipairs(Entries(old and old.scanLog, ScanEntry) or {}) do
        scans[#scans + 1] = ("%s,%s,%s,%s,%s"):format(N(e.seq), N(e.at), N(e.flags), N(e.items), N(e.records))
    end
    scans[#scans + 1] = ("%s,%s,%s,%s,%s"):format(N(seq), N(at), N(flags), N(Int(scan.n, 0, PR.MAX_ITEMS) or 0), N(Int(scan.read, 0, W.MAX_ID) or 0))
    -- every scan of the last 48 hours, never fewer than the newest 64, never more than the newest 256
    while #scans > PR.SCAN_LOG_MAX do table.remove(scans, 1) end
    local cutoff = at - PR.SCAN_LOG_HOURS * 3600
    while #scans > PR.SCAN_LOG_MIN do
        local e = ScanEntry(scans[1])
        if e and e.at >= cutoff then break end
        table.remove(scans, 1)
    end

    -- one entry per scan day; a scan dated before the newest logged day (the clock went back) is not added as a new entry
    local list = Entries(old and old.dayLog, DayEntry) or {}
    local newest = list[#list] and list[#list].day or nil
    if day then
        local dflags = (whole and D_WHOLE or D_INCOMPLETE) + (partial and D_PARTIAL or 0)
        local merged = false
        for _, e in ipairs(list) do
            if e.day == day then e.scans, e.flags, merged = e.scans + 1, Union(e.flags, dflags, { D_WHOLE, D_INCOMPLETE, D_PARTIAL }), true end
        end
        if not merged and (not newest or day > newest) then list[#list + 1] = { day = day, scans = 1, flags = dflags } end
        newest = newest and math.max(newest, day) or day
    end
    local days = {}
    local from = newest and newest - PR.DAY_LOG_DAYS + 1 or 0
    for _, e in ipairs(list) do
        if e.day >= from then days[#days + 1] = ("%s,%s,%s"):format(N(e.day), N(e.scans), N(e.flags)) end
    end
    return scans, days
end

-- The format 3 market for a commit, built from the old market and the scan WITHOUT changing any saved table (so a failure while
-- building leaves everything as it was). `hist` is the legacy history table, expired already.
local function BuildMarket(self, hist, sd)
    local scan, old, at, day = self.scan, self.old, self.at, self.day
    local oldFull = old and old.scope == "full" and old.format == 3
    -- sequence number: after the newest the old market proves (its snapshot, else its log)
    local seq = oldFull and old.snap and old.snap.seq or 0
    for _, e in ipairs(oldFull and Entries(old.scanLog, ScanEntry) or {}) do if e.seq > seq then seq = e.seq end end
    seq = seq + 1
    local scans, days = Logs(oldFull and old or nil, scan, at, day, seq)
    local read, used = Int(scan.read, 0, W.MAX_ID), Int(scan.used, 0, W.MAX_ID)
    local snap = { seq = seq, kind = "full", at = at, records = read, used = used, invalid = Int(scan.invalid, 0, W.MAX_ID),
        noBuyout = Int(scan.noBuyout, 0, W.MAX_ID), partial = Int(scan.partial, 0, W.MAX_ID) or 0,
        items = Int(scan.n, 0, PR.MAX_ITEMS) or 0, auto = scan.auto == true, client = ClientBuild() }
    local v2from = oldFull and old.v2from or day
    local m = { f = PR.MARKET_FORMAT, scope = "full", realm = Text(scan.realm, 60), side = Text(scan.side, 20) or "unknown", at = at,
        complete = scan.complete == true, cut = scan.cut == true or scan.changed == true or nil, read = read, used = used,
        partial = Int(scan.partial, 0, W.MAX_ID) or 0, n = Int(scan.n, 0, PR.MAX_ITEMS) or 0,
        hn = self.oldCount + self.added - (self.dropped or 0), items = scan.items, hist = hist, sd = sd,
        snap = snap, scans = scans, days = days, v2from = v2from }
    -- the later milestones' containers are never written here, only carried forward from a market that has them (a build that fills
    -- them must not lose them to this one); a market without them gets none
    local raw = oldFull and self.oldRaw or nil
    if raw then
        for _, k in ipairs({ "dist", "h2", "c2", "compact" }) do if type(raw[k]) == "table" then m[k] = raw[k] end end
    end
    return m
end

function Job:Apply()
    if self.phase ~= "ready" then return false, "bad" end
    if PR.Held() then return false, "held" end
    local key, scan, old = self.key, self.scan, self.old
    -- EVERYTHING that can fail is done first, on copies: the saved tables are touched only by the plain assignments below
    local sd = {}
    if old and old.scanDays then for _, d in ipairs(old.scanDays) do if type(d) == "number" then sd[#sd + 1] = d end end end
    if self.feed and self.day then
        if sd[#sd] == nil or sd[#sd] < self.day then sd[#sd + 1] = self.day end
        while #sd > H.MAX_SCAN_DAYS do table.remove(sd, 1) end
    end
    local raw = Store(false)
    self.oldRaw = raw and raw.markets[key]
    if type(self.oldRaw) ~= "table" then self.oldRaw = nil end
    local hist = self.oldHist or {}
    local market = BuildMarket(self, hist, sd)
    local lp = LegacyStore()
    local db = Store(true)
    if not db then return false, "unsaved" end
    -- from here on only assignments
    -- the history table is the old one changed in place (its items are the same strings), or a new one
    for id, s in pairs(self.upd) do hist[id] = s end
    for id in pairs(self.drop) do hist[id] = nil end
    if db.markets[key] == nil then
        local count, oldestKey, oldestAt = 0, nil, nil
        for k, m in pairs(db.markets) do
            count = count + 1
            local t = type(m) == "table" and Int(m.at, 0, MAX_TIME) or 0
            if not oldestAt or t < oldestAt then oldestKey, oldestAt = k, t end
        end
        if count >= PR.MAX_MARKETS and oldestKey then db.markets[oldestKey] = nil end
    end
    db.markets[key] = market
    if type(db.v) ~= "number" or db.v < PR.SAVED_VERSION then db.v = PR.SAVED_VERSION end
    -- the earlier recipe-only scan of this market is replaced by this one: it is not kept twice
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
