-- TwichUI Test Lab: deterministic synthetic market data (TL.Fixtures). PURE: no game calls, no frames, no saved variables, no clock.
-- Loaded by the Lab in the game and by the offline tests (tests/test_workshop_market_reference.lua), so a seed gives the same scenario in
-- every interpreter. Nothing here reads TwichUIDB, TwichUIWorkshopDB or the player's characters.
--
-- THE GENERATOR: Wichmann-Hill (1982), three small multiplicative congruential generators summed modulo 1. Every product stays below 2^23, so
-- plain doubles compute it exactly and the sequence does not depend on math.random or on the platform's libc. It is a test-data generator,
-- not a statistical or cryptographic one. A seed is any whole number; seeds that differ by one give unrelated scenarios (checked by the test).
--
--   local rng = FX.Rng(seed)       rng:Next() in [0,1)   rng:Int(lo, hi) inclusive   rng:Pick(list)   rng:Chance(p)   rng:Shuffle(list)
--   FX.Listings(seed, opt)         auction records for one house: { seed, items = { ids }, records = { {item,count,buyout,info,intent} } }
--   FX.Calendar(seed, opt)         one market's scans over days: { seed, key, items, scans = { {day, at, items = {[id]=unit price}, ...} } }
--   FX.Markets(seed, n, opt)       n independent calendars with different keys
--   FX.Crafting(seed, opt)         a craft queue, what is owned, prices, vendor offers and make recipes (M3, below)
--   FX.Economy(seed, opt)          recipes as the window may read them (some malformed), a price lookup, an auction house cut
--   FX.StockObs(seed, opt)         what the bank and the guild bank were last seen to hold (the observations Stock.lua judges)
--
-- Every size is clamped to FX.LIMITS, so no option can ask for a pathological allocation. Records and scans are made-up game-shaped data;
-- the only unrealistic values are the ones the generator makes ON PURPOSE to test validation, and those records say so: record.intent is
-- "priced" (a valid buyout), "nobuyout" (bid only) or "invalid" (a field a real auction record would not hold). The reference model in
-- Reference.lua classifies records on its own; the intent is only a cross-check of the generator.

local R = TwichUI
local TL = R.TestLab or {}
R.TestLab = TL
local FX = {}
TL.Fixtures = FX

-- the game's documented ranges (Blizzard_AuctionHouseUI: MAXIMUM_BID_PRICE; one auction holds at most 10000 items); typed here, not read from the Workshop
FX.MAX_COPPER, FX.MAX_COUNT, FX.MAX_ID = 99999999999, 10000, 2147483647
FX.LIMITS = { records = 5000, items = 200, tiers = 8, scans = 400, markets = 6,
    -- crafting (M3): far below the planner's own bounds (30 recipes, 16 materials, 4 candidates), so every scenario stays easy to inspect
    pool = 8, entries = 8, candidates = 4, tabs = 8 }
-- Benchmarks only (M7): sizes the correctness fixtures above never use. A caller must ask for them (FX.Bulk, or opt.bulk in FX.Crafting).
-- 250,000 records and 30,000 items are the scan's own boundaries; the crafting numbers are the planner's (30 recipes) and a pool of items.
FX.BULK = { records = 250000, items = 30000, pool = 64, entries = 30 }

local floor = math.floor

-- Is v a finite number? Decided from the printed form, WITHOUT comparing it (a NaN compares as equal to itself and to 0 in the client, so
-- `v ~= v` accepts one there; same rule as W.Finite and REF.Finite, written here because this file loads first).
local function Finite(v)
    if type(v) ~= "number" then return false end
    return tostring(v):find("^[%d%.eE%+%-]+$") ~= nil
end

---------------------------------------------------------------------------
-- The generator
---------------------------------------------------------------------------
local Rng = {}
Rng.__index = Rng

-- a seed as a whole number below 2^52 (a NaN, infinity or non-number is 0); the same rule for the generator and for anything printed from a seed
local function Whole(seed)
    if not Finite(seed) then seed = 0 end
    return math.abs(floor(seed)) % 4503599627370496   -- 2^52
end

function FX.Rng(seed)
    seed = Whole(seed)
    local self = setmetatable({}, Rng)
    -- three states, each in 1 .. modulus-1, from different linear maps of the seed; twelve draws are thrown away
    self.a = (seed * 7919 + 11) % 30268 + 1
    self.b = (seed * 104729 + 23) % 30306 + 1
    self.c = (seed * 1299709 + 37) % 30322 + 1
    for _ = 1, 12 do self:Next() end
    return self
end

function Rng:Next()
    self.a = (171 * self.a) % 30269
    self.b = (172 * self.b) % 30307
    self.c = (170 * self.c) % 30323
    return (self.a / 30269 + self.b / 30307 + self.c / 30323) % 1
end

function Rng:Int(lo, hi)
    if hi < lo then lo, hi = hi, lo end
    return lo + floor(self:Next() * (hi - lo + 1))
end

function Rng:Pick(list) return list[self:Int(1, #list)] end
function Rng:Chance(p) return self:Next() < p end

function Rng:Shuffle(list)
    for i = #list, 2, -1 do
        local j = self:Int(1, i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

local function Clamp(v, lo, hi, default)
    if not Finite(v) then return default end
    return math.max(lo, math.min(hi, floor(v)))
end

local function Rate(v, default)
    if not Finite(v) then return default end
    return math.max(0, math.min(1, v))
end

---------------------------------------------------------------------------
-- Auction records for one house
---------------------------------------------------------------------------
local STACKS = { 1, 1, 1, 1, 2, 3, 4, 5, 5, 7, 10, 10, 15, 20, 20, 40, 200, 1000, 10000 }
local BAD_ITEM = { 0, -5, 1.5, "12", false, 2147483648, 0 / 0, math.huge }
local BAD_COUNT = { 0, -1, 2.5, "3", false, 10001, 0 / 0 }
local BAD_BUYOUT = { -1, 1.5, "900", 100000000000, math.huge, 0 / 0, false }
-- the malformed values the generator draws from, for a test or the Lab to try one by one (a NaN and an infinity among them)
FX.BAD = { item = BAD_ITEM, count = BAD_COUNT, buyout = BAD_BUYOUT }

-- opt: items (distinct item ids, default 5), records (default 40), tiers (distinct unit prices per item, default 3), invalid, noBuyout, partial
-- (the chance of each kind of record, defaults 0.08, 0.10, 0.10). Prices come in tiers so that several stacks tie EXACTLY, and some stacks sit
-- a copper or less under or over a tier, so that exact fractions and rounded coppers disagree.
function FX.Listings(seed, opt)
    opt = opt or {}
    local rng = FX.Rng(seed)
    local nItems = Clamp(opt.items, 1, FX.LIMITS.items, 5)
    local nRecords = Clamp(opt.records, 0, FX.LIMITS.records, 40)
    local nTiers = Clamp(opt.tiers, 1, FX.LIMITS.tiers, 3)
    local invalid, noBuyout, partial = Rate(opt.invalid, 0.08), Rate(opt.noBuyout, 0.10), Rate(opt.partial, 0.10)

    local ids, seen, tiers = {}, {}, {}
    while #ids < nItems do
        local id = rng:Chance(0.1) and rng:Int(1, FX.MAX_ID) or rng:Int(1, 60000)
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
            local scale = rng:Pick({ 3, 40, 2000, 90000, 3000000 })
            local t, base = {}, rng:Int(1, scale)
            for k = 1, nTiers do t[k] = base + (k - 1) * rng:Int(1, math.max(1, floor(scale / 3))) end
            tiers[id] = t
        end
    end

    local records = {}
    for i = 1, nRecords do
        local item = rng:Pick(ids)
        local unit = rng:Pick(tiers[item])
        local count = rng:Pick(STACKS)
        local style = rng:Pick({ "exact", "exact", "under", "over", "any" })
        if unit * count > FX.MAX_COPPER then count = 1 end
        local buyout = unit * count
        if style == "under" and count > 1 then buyout = buyout - rng:Int(1, count - 1)
        elseif style == "over" and count > 1 then buyout = buyout + rng:Int(1, count - 1)
        elseif style == "any" then buyout = rng:Int(1, math.min(FX.MAX_COPPER, 3 * unit * count)) end
        buyout = math.max(1, math.min(FX.MAX_COPPER, buyout))
        local info = ({ yes = true, no = false })[rng:Pick({ "yes", "yes", "unset", "no" })]   -- true, false or absent
        if rng:Chance(partial) then info = false end
        local rec = { item = item, count = count, buyout = buyout, info = info, intent = "priced" }
        local roll = rng:Next()
        if roll < invalid then
            rec.intent = "invalid"
            local field = rng:Pick({ "item", "count", "buyout", "count0" })
            if field == "item" then rec.item = rng:Pick(BAD_ITEM)
            elseif field == "count" then rec.count = rng:Pick(BAD_COUNT)
            elseif field == "buyout" then rec.buyout = rng:Chance(0.25) and nil or rng:Pick(BAD_BUYOUT)
            else rec.count, rec.buyout = rng:Pick(BAD_COUNT), 0 end   -- a bid-only record that is also malformed: malformed comes first
        elseif roll < invalid + noBuyout then
            rec.intent, rec.buyout = "nobuyout", 0
        end
        records[i] = rec
    end
    return { seed = seed, items = ids, records = records }
end

---------------------------------------------------------------------------
-- Bulk auction records for benchmarks (M7): flat parallel arrays, generated in chunks
---------------------------------------------------------------------------
-- FX.Bulk(seed, n, items) -> b. b.item[i], b.count[i], b.buyout[i] hold record i (no table per record: 50,000 records stay small). Fill(k)
-- makes the next k records, so a caller in the game can spread the work over frames; one generator is consumed in order, so the records do not
-- depend on the chunk size. About 2% of records are invalid (a count of 0) and 5% are bid-only (buyout 0). b.truth is what the generator
-- KNOWS: read / used / noBuyout / invalid, and per item the listings (l), the items listed (t) and the cheapest unit price as a float (m),
-- worked out here from the made-up numbers, not by the Workshop. Item ids are distinct and fixed: 1000 + 7 * k.
-- spread (A3, default 40): how many copper above its base an item's unit price may be, so how many distinct price tiers an item can have. It
-- changes only the value drawn, never the number of draws, so a given seed makes the same records at the default spread as before.
function FX.Bulk(seed, n, items, spread)
    n = Clamp(n, 0, FX.BULK.records, 1000)
    items = Clamp(items, 1, FX.BULK.items, 300)
    spread = Clamp(spread, 0, 30000, 40)
    local rng = FX.Rng(seed)
    local b = { seed = seed, n = n, nItems = items, filled = 0, item = {}, count = {}, buyout = {},
        truth = { read = 0, used = 0, noBuyout = 0, invalid = 0, l = {}, t = {}, m = {} } }
    local STACK = { 1, 1, 1, 1, 5, 5, 20, 200 }
    function b:Done() return self.filled >= self.n end
    function b:Fill(k)
        local last = math.min(self.n, self.filled + (tonumber(k) or 0))
        local tr = self.truth
        for i = self.filled + 1, last do
            local idx = 1 + floor(items * rng:Next() ^ 2)
            local id = 1000 + 7 * idx
            local count = STACK[rng:Int(1, #STACK)]
            local base = 20 + (idx * 37) % 9000
            local buyout = count * (base + rng:Int(0, spread))
            local roll = rng:Next()
            self.item[i], self.count[i], self.buyout[i] = id, count, buyout
            tr.read = tr.read + 1
            if roll < 0.02 then
                self.count[i] = 0
                tr.invalid = tr.invalid + 1
            elseif roll < 0.07 then
                self.buyout[i] = 0
                tr.noBuyout = tr.noBuyout + 1
            else
                tr.used = tr.used + 1
                tr.l[id] = (tr.l[id] or 0) + 1
                tr.t[id] = (tr.t[id] or 0) + count
                local unit = buyout / count
                if not tr.m[id] or unit < tr.m[id] then tr.m[id] = unit end
            end
        end
        self.filled = last
    end
    return b
end

---------------------------------------------------------------------------
-- A market's scans over days (for the history and the statistics)
---------------------------------------------------------------------------
local GAPS = {
    dense = { 1 },
    sparse = { 1, 1, 2, 3, 5, 9 },
    -- around the edges of the 7 exact days, the 28-day buckets and the 120-day retention
    boundary = { 1, 1, 2, 6, 7, 8, 27, 28, 29, 119, 120, 121, 122 },
}
GAPS.mixed = { 1, 1, 1, 1, 2, 3, 5, 9, 28, 29, 100, 120, 121 }

-- opt: scans (default 20), items (default 4), style ("dense", "sparse", "boundary", "mixed"; default "mixed"), start (first day, default
-- random), listed (chance an item is listed in a scan, default 0.85), same (chance of a second scan the same day, default 0.12), back (chance
-- of a scan dated EARLIER than the last, the clock having moved back, default 0.04), cut (chance of a scan that was cut off or changed while
-- read: current prices, no history, default 0.04), jump (chance of a big price move, default 0.08).
-- scan = { day, at (seconds), items = { [id] = unit price in whole copper }, complete, cut, changed }. A scan that is not whole read
-- (cut / changed) is never complete. calendar.key is "Realm<seed>|Side".
function FX.Calendar(seed, opt)
    opt = opt or {}
    local rng = FX.Rng(seed)
    local nScans = Clamp(opt.scans, 1, FX.LIMITS.scans, 20)
    local nItems = Clamp(opt.items, 1, FX.LIMITS.items, 4)
    local gaps = GAPS[opt.style] or GAPS.mixed
    local listed, same, back, cutp, jump = Rate(opt.listed, 0.85), Rate(opt.same, 0.12), Rate(opt.back, 0.04), Rate(opt.cut, 0.04), Rate(opt.jump, 0.08)
    local day = Clamp(opt.start, 1, 150000, rng:Int(130, 20000))

    local ids, price = {}, {}
    for i = 1, nItems do
        ids[i] = 1000 + i * 37 + rng:Int(0, 30)
        price[ids[i]] = rng:Pick({ 1, 5, 80, 1200, 45000, 3000000 }) + rng:Int(0, 40)
    end
    local scans = {}
    for i = 1, nScans do
        if opt.tick then opt.tick(i) end   -- the caller may yield between scans (M7.1); nothing is drawn from the generator here
        if i > 1 then
            if rng:Chance(same) then
                -- the same day again
            elseif rng:Chance(back) then
                day = math.max(1, day - rng:Int(1, 6))
            else
                day = math.min(190000, day + rng:Pick(gaps))
            end
        end
        local items = {}
        for _, id in ipairs(ids) do
            local p = price[id]
            if rng:Chance(jump) then p = rng:Pick({ 1, math.max(1, floor(p / 7)), p * 5, 99999999 }) else p = p + floor((rng:Next() - 0.5) * p * 0.3) end
            p = math.max(1, math.min(FX.MAX_COPPER, p))
            price[id] = p
            if rng:Chance(listed) then items[id] = p end
        end
        local cut = rng:Chance(cutp)
        scans[i] = { day = day, at = day * 86400 + rng:Int(0, 86399), items = items, complete = not cut }
        if cut then
            if rng:Chance(0.5) then scans[i].cut = true else scans[i].changed = true end
        end
    end
    return { seed = seed, key = ("Realm%d|%s"):format(Whole(seed) % 1000, rng:Pick({ "Alliance", "Horde", "unknown" })), items = ids, scans = scans,
        last = scans[#scans].day }
end

-- n independent markets from one seed: each has its own seed, items, prices, calendar and key (the keys differ)
function FX.Markets(seed, n, opt)
    n = Clamp(n, 1, FX.LIMITS.markets, 2)
    local out = {}
    for i = 1, n do
        local cal = FX.Calendar(seed * 31 + i * 7919, opt)
        cal.key = ("Realm%d|%s"):format(i, ({ "Alliance", "Horde", "unknown" })[(i - 1) % 3 + 1])
        out[i] = cal
    end
    return out
end

---------------------------------------------------------------------------
-- Crafting: a queue, what is owned, what things cost, what can be made (testing roadmap M3)
---------------------------------------------------------------------------
-- SEEDS used by the tests and the Lab: allocation and materials 7500000+i, shopping 7510000+i, economics 7520000+i, stock 7530000+i.
-- Everything is small on purpose (3 to 6 materials, 1 to 3 queued recipes, quantities below 50, prices below 3000 copper) so a scenario can be
-- read, worked out by hand and enumerated completely. Nothing here is a real recipe, item or price.
FX.NOW = 1700000000

local TIERS = { 1, 2, 3, 5, 8, 13, 40, 150, 700, 2500 }   -- unit prices: small ones tie often
local VSTACKS = { 1, 1, 5, 5, 10, 20 }
local VAVAIL = { -1, -1, -1, 0, 3, 12, 100 }               -- -1: the merchant has no limit; 0: sold out when seen
local AGES = { 300, 7200, 90000, 700000 }                  -- seconds before FX.NOW: fresh, hours, a day, a week and more (stale)

local function Mats(rng, pool, k, maxQty)
    local copy = {}
    for i, id in ipairs(pool) do copy[i] = id end
    rng:Shuffle(copy)
    local out = {}
    for i = 1, math.min(k, #copy) do out[i] = { item = copy[i], qty = rng:Int(1, maxQty) } end
    return out
end

-- the price list of one item as the Workshop's lookup gives it: { price, qty (items at the cheapest price), listings, total (items listed in all),
-- at, complete, scope }; nil (nothing saved) with the chance 1 - present
local function Offer(rng, present)
    if not rng:Chance(present) then return nil end
    local qty = rng:Int(1, 12)
    local total = qty + (rng:Chance(0.35) and 0 or rng:Int(0, 25))
    return { price = rng:Pick(TIERS), qty = qty, listings = rng:Int(1, qty), total = total, at = FX.NOW - rng:Pick(AGES),
        complete = rng:Chance(0.85), scope = "full" }
end

local function Output(rng, e, unknownChance)
    local roll = rng:Next()
    if roll < 1 - unknownChance - 0.12 then
        e.outMin = rng:Int(1, 3)
        e.outMax = e.outMin
    elseif roll < 1 - unknownChance then
        e.outMin = rng:Int(1, 2)
        e.outMax = e.outMin + rng:Int(1, 2)   -- a range
    end   -- otherwise the amount made is not known
end

-- opt: items (distinct materials, default 3 to 6), entries (queued recipes, default 1 to 3).
-- Returns a scenario:
--   seed, now, pool (the materials' item ids), products (item ids that are only ever made, never needed),
--   entries  { { id, name, crafts, mats = { { item, qty } } | nil (not known), outItem | nil, outMin, outMax } }  (as Materials.Combine reads them)
--   bags     { [item] = count }      unknown { [item] = true } when the bag count cannot be read (then bags has no entry)
--   bank, guild   { [item] = count } the counts that MAY BE PLANNED WITH (what Stock.Fn answers), already judged
--   auction  { [item] = Prices.Lookup-shaped table }    vendor { [item] = { p, s, a, at, npc } }    sells { [item] = true } (a merchant is known)
--   recipes  { [item] = { { id, name, outItem, outMin, outMax, mats | nil | {} } } }  the known recipes that make an item (some unusable on purpose)
--   cut      the auction house's cut in tenths of a percent, or nil (not known)
function FX.Crafting(seed, opt)
    opt = opt or {}
    local rng = FX.Rng(seed)
    local nPool = Clamp(opt.items, 2, opt.bulk and FX.BULK.pool or FX.LIMITS.pool, rng:Int(3, 6))
    local nEntries = Clamp(opt.entries, 0, opt.bulk and FX.BULK.entries or FX.LIMITS.entries, rng:Int(1, 3))
    local used, pool, products = {}, {}, {}
    local function NewId()
        local id
        repeat id = rng:Int(100, 9000) until not used[id]
        used[id] = true
        return id
    end
    for i = 1, nPool do pool[i] = NewId() end
    for i = 1, 2 do products[i] = NewId() end

    local entries = {}
    for i = 1, nEntries do
        local e = { id = 5000 + i, name = "Recipe " .. i, crafts = rng:Int(1, 4) }
        if not rng:Chance(0.06) then e.mats = Mats(rng, pool, rng:Int(1, 3), 6) end
        if not rng:Chance(0.05) then e.outItem = rng:Chance(0.3) and rng:Pick(pool) or rng:Pick(products) end
        Output(rng, e, 0.08)
        entries[i] = e
    end

    local bags, bank, guild, unknown = {}, {}, {}, {}
    for _, id in ipairs(pool) do
        if rng:Chance(0.06) then unknown[id] = true else bags[id] = rng:Chance(0.5) and 0 or rng:Int(1, 15) end
        bank[id] = rng:Chance(0.6) and 0 or rng:Int(1, 12)
        guild[id] = rng:Chance(0.7) and 0 or rng:Int(1, 12)
    end

    -- which materials can be made (a made material's reagents are mostly ones that are not made, so that a one-level plan is usually possible)
    local makers, raw = {}, {}
    for _, id in ipairs(pool) do
        makers[id] = rng:Chance(0.5)
        if not makers[id] then raw[#raw + 1] = id end
    end
    local auction, vendor, sells, recipes = {}, {}, {}, {}
    for _, id in ipairs(pool) do
        auction[id] = Offer(rng, 0.8)
        if rng:Chance(0.35) then
            vendor[id] = { p = rng:Pick(TIERS) * rng:Pick({ 1, 1, 3 }), s = rng:Pick(VSTACKS), a = rng:Pick(VAVAIL), at = FX.NOW - rng:Pick(AGES), npc = 900 + id % 50 }
            sells[id] = true
        elseif rng:Chance(0.08) then
            sells[id] = true   -- a merchant is known to sell it, but its price was never seen
        end
        if makers[id] then
            local list = {}
            for k = 1, rng:Int(1, FX.LIMITS.candidates - 1) do
                local r = { id = 20000 + id * 10 + k, name = ("Make %d/%d"):format(id, k), outItem = id }
                local roll = rng:Next()
                local source = (#raw > 0 and rng:Chance(0.75)) and raw or pool
                if roll < 0.04 then r.mats = nil
                elseif roll < 0.07 then r.mats = {}
                else
                    r.mats = Mats(rng, source, rng:Int(1, 3), 5)
                    if roll < 0.11 then r.mats[1] = { item = id, qty = rng:Int(1, 3) } end   -- a recipe that uses what it makes
                end
                Output(rng, r, 0.05)
                list[k] = r
            end
            recipes[id] = list
        end
    end
    for _, id in ipairs(products) do auction[id] = Offer(rng, 0.8) end
    local cut = nil
    if rng:Chance(0.5) then cut = rng:Pick({ 5, 50, 75, 100, 150, 333 }) end
    return { seed = seed, now = FX.NOW, pool = pool, products = products, entries = entries, bags = bags, unknown = unknown, bank = bank,
        guild = guild, auction = auction, vendor = vendor, sells = sells, recipes = recipes, cut = cut }
end

-- the scenario's answers in the shapes Materials.Rows and Shopping.Plan take
function FX.CraftHave(scn) return function(item) if scn.unknown[item] then return nil end return scn.bags[item] or 0 end end
function FX.CraftStock(scn) return function(item) return scn.bank[item] or 0, scn.guild[item] or 0 end end

-- Shopping.Plan's input for a scenario and Materials.Rows' rows. opt.picks = { [item] = "vendor" | "auction" | "make" }; opt.recipes = function(item) -> list
-- replaces the scenario's recipes (to offer one candidate at a time).
function FX.PlanInput(scn, rows, opt)
    opt = opt or {}
    return {
        rows = rows, picks = opt.picks, have = FX.CraftHave(scn), stock = FX.CraftStock(scn),
        auction = function(item) return scn.auction[item] end,
        vendor = function(item) return scn.vendor[item] end,
        sells = function(item) return scn.sells[item] == true end,
        recipes = opt.recipes or function(item) return scn.recipes[item] or {} end,
        queued = function() return nil end,
    }
end

---------------------------------------------------------------------------
-- Multilevel crafting chains (P1, the multilevel planner: docs/workshop/multilevel-crafting-planner.md)
---------------------------------------------------------------------------
-- SEEDS used by the tests and the Lab: chains 7540000+i; larger graphs 7550000+i; benchmarks 7640000+i.
-- A layered graph: raw materials (level 0), intermediates (levels 1 to 3) made from lower levels, sometimes by two recipes, sometimes with a
-- recipe that reaches UP a level or uses its own output (a circle), a varying or unknown output, uncountable materials or a recipe the
-- character does not know (scn.unavailable). The queue's crafts use intermediates and raw materials; one may make an intermediate (a queued
-- credit). Everything is small unless opt.size asks otherwise, so the reference can enumerate every choice. Nothing is a real item or price.
-- opt: raw (2..), levels ({ n1, n2, n3 } intermediates per level), entries, cycles (chance of a circular recipe, default 0.12), size
-- ("small" default, "large": more of everything, for invariant and bounded-search tests and benchmarks), markup (a whole-number factor on the
-- prices of intermediates, default 1: a larger one makes making them, and so deeper chains, the cheaper choice more often), top (the queue uses
-- only the highest level's items).
-- Returns { seed, now, items (all ids, ascending), level = { [item] = 0..3 }, entries, bags, bank, guild, unknown, vendor, sells, listings =
--   { [item] = { { b, c } } } (b = buyout of a stack of c, whole-copper units), auction = { [item] = Prices.Lookup-shaped }, recipes =
--   { [item] = { recipe } }, unavailable = { [recipeId] = true }, picks = { [item] = kind } }
local CHAIN_UNITS = { 1, 2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 30, 45, 60, 90, 150 }
function FX.Chain(seed, opt)
    opt = opt or {}
    local rng = FX.Rng(seed)
    local large = opt.size == "large"
    local nRaw = Clamp(opt.raw, 1, 40, large and rng:Int(6, 14) or rng:Int(2, 4))
    local levels = opt.levels or (large and { rng:Int(4, 8), rng:Int(3, 6), rng:Int(2, 4) } or { rng:Int(1, 3), rng:Int(0, 2), rng:Chance(0.3) and 1 or 0 })
    local cycleChance = opt.cycles or 0.12
    local used, items, level, byLevel = {}, {}, {}, { [0] = {} }
    local function NewId()
        local id
        repeat id = rng:Int(100, 9000) until not used[id]
        used[id] = true
        items[#items + 1] = id
        return id
    end
    for _ = 1, nRaw do local id = NewId() level[id] = 0 byLevel[0][#byLevel[0] + 1] = id end
    for L = 1, 3 do
        byLevel[L] = {}
        for _ = 1, Clamp(levels[L], 0, 20, 0) do local id = NewId() level[id] = L byLevel[L][#byLevel[L] + 1] = id end
    end
    local below = {}   -- the items of levels lower than L
    local recipes, unavailable, nextRecipe = {}, {}, 30000
    local function Recipe(out, from, must)
        nextRecipe = nextRecipe + rng:Int(1, 9)
        local r = { id = nextRecipe, name = "Make " .. out .. "/" .. nextRecipe, outItem = out }
        local k = rng:Int(1, math.min(3, #from))
        local copy = {}
        for i, id in ipairs(from) do copy[i] = id end
        rng:Shuffle(copy)
        r.mats = {}
        for i = 1, k do r.mats[i] = { item = copy[i], qty = rng:Int(1, 4) } end
        if must and not (function() for _, m in ipairs(r.mats) do if m.item == must then return true end end end)() then
            r.mats[#r.mats + 1] = { item = must, qty = rng:Int(1, 3) }
        end
        if rng:Chance(0.08) then r.mats[#r.mats + 1] = { item = r.mats[1].item, qty = rng:Int(1, 2) } end   -- the same reagent listed twice
        local roll = rng:Next()
        if roll < 0.80 then r.outMin = rng:Pick({ 1, 1, 2, 3, 5 }) r.outMax = r.outMin
        elseif roll < 0.86 then r.outMin = rng:Int(1, 2) r.outMax = r.outMin + 1   -- a range
        elseif roll < 0.90 then r.outMin = nil                                        -- the output is not known
        elseif roll < 0.93 then r.mats = nil                                          -- materials not countable
        else r.outMin = rng:Int(1, 3) end                                             -- outMax not given: a fixed output
        if rng:Chance(0.06) then unavailable[r.id] = true end
        return r
    end
    for L = 1, 3 do
        for _, id in ipairs(byLevel[L - 1]) do below[#below + 1] = id end
        for _, id in ipairs(byLevel[L]) do
            local list = {}
            local lower = byLevel[L - 1]
            for _ = 1, rng:Chance(0.35) and 2 or 1 do list[#list + 1] = Recipe(id, below, #lower > 0 and rng:Pick(lower) or nil) end
            recipes[id] = list
        end
    end
    -- circles: a lower item made from a higher one, or an item that uses itself
    for _, id in ipairs(items) do
        if level[id] < 3 and rng:Chance(cycleChance) then
            local higher = {}
            for _, x in ipairs(items) do if level[x] > level[id] then higher[#higher + 1] = x end end
            if #higher > 0 then
                local r = Recipe(id, higher)
                recipes[id] = recipes[id] or {}
                table.insert(recipes[id], r)
            end
        end
        if recipes[id] and rng:Chance(cycleChance / 3) then
            local r = Recipe(id, { id })
            table.insert(recipes[id], r)
        end
    end
    -- the queue
    local entries = {}
    local nEntries = Clamp(opt.entries, 1, large and 30 or 4, large and rng:Int(4, 12) or rng:Int(1, 3))
    local top = {}
    for L = 3, 1, -1 do for _, id in ipairs(byLevel[L]) do top[#top + 1] = id end end
    for i = 1, nEntries do
        local e = { id = 5000 + i, name = "Final " .. i, crafts = rng:Int(1, large and 6 or 3) }
        local from = {}
        for _, id in ipairs(top) do from[#from + 1] = id end
        if opt.top then   -- only the highest level the graph has: every chain starts at its top
            from = {}
            for L = 3, 1, -1 do if #byLevel[L] > 0 and #from == 0 then for _, id in ipairs(byLevel[L]) do from[#from + 1] = id end end end
        end
        for _, id in ipairs(byLevel[0]) do if not opt.top and rng:Chance(0.4) then from[#from + 1] = id end end
        if #from == 0 then from = byLevel[0] end
        rng:Shuffle(from)
        e.mats = {}
        for k = 1, math.min(#from, rng:Int(1, 3)) do e.mats[k] = { item = from[k], qty = rng:Int(1, 4) } end
        if rng:Chance(0.02) then e.mats = nil end
        if rng:Chance(0.12) and #byLevel[1] > 0 then
            e.outItem = rng:Pick(byLevel[1]) e.outMin = rng:Int(1, 2) e.outMax = e.outMin   -- a queued craft makes an intermediate
            e.mats = { { item = rng:Pick(byLevel[0]), qty = rng:Int(1, 3) } }
        else
            e.outItem = 9500 + i e.outMin = 1 e.outMax = 1
        end
        entries[i] = e
    end
    -- stock, merchants, auctions
    local bags, bank, guild, unknown, vendor, sells, listings, auction = {}, {}, {}, {}, {}, {}, {}, {}
    for _, id in ipairs(items) do
        if rng:Chance(0.04) then unknown[id] = true else bags[id] = rng:Chance(0.55) and 0 or rng:Int(1, 8) end
        bank[id] = rng:Chance(0.7) and 0 or rng:Int(1, 6)
        guild[id] = rng:Chance(0.8) and 0 or rng:Int(1, 6)
        local base = rng:Pick(CHAIN_UNITS) * (level[id] + 1) * (level[id] > 0 and Clamp(opt.markup, 1, 20, 1) or 1)
        if rng:Chance(level[id] == 0 and 0.5 or 0.15) then
            vendor[id] = { p = base * rng:Pick({ 1, 1, 2, 5 }), s = rng:Pick({ 1, 1, 5, 10 }), a = rng:Pick({ -1, -1, -1, 4, 40 }), at = FX.NOW - rng:Pick(AGES), npc = 900 + id % 50 }
            sells[id] = true
        elseif rng:Chance(0.05) then
            sells[id] = true
        end
        if rng:Chance(0.8) then
            local recs, unit = {}, base + rng:Int(0, 3)
            for _ = 1, rng:Int(1, 4) do
                local c = rng:Pick({ 1, 1, 2, 3, 5, 10 })
                recs[#recs + 1] = { b = unit * c, c = c }
                if rng:Chance(0.5) then unit = unit + rng:Int(1, 6) end
            end
            listings[id] = recs
            local cheapest, qty, total, n = nil, 0, 0, #recs
            for _, r in ipairs(recs) do
                local u = r.b / r.c
                total = total + r.c
                if not cheapest or u < cheapest then cheapest, qty = u, r.c elseif u == cheapest then qty = qty + r.c end
            end
            auction[id] = { price = cheapest, qty = qty, listings = n, total = total, at = FX.NOW - 600, complete = true, scope = "full" }
        end
    end
    -- the player's choices, now and then (some of them impossible on purpose)
    local picks = {}
    if opt.picks ~= false and rng:Chance(0.3) then
        local id = rng:Pick(items)
        picks[id] = rng:Pick({ "vendor", "auction", "make" })
    end
    table.sort(items)
    return { seed = seed, now = FX.NOW, items = items, level = level, entries = entries, bags = bags, bank = bank, guild = guild, unknown = unknown,
        vendor = vendor, sells = sells, listings = listings, auction = auction, recipes = recipes, unavailable = unavailable, picks = picks }
end

-- The multilevel planner's input for a chain scenario. opt.cost(item, qty) is the purchase-cost service (Market.Cost-shaped; the offline test gives
-- the real Market.Cost over a market built from scn.listings, the Lab a stand-in); opt.auction overrides the price lookup; opt.picks overrides
-- scn.picks; opt.limits is passed by the caller to the planner, not here.
function FX.ChainInput(scn, opt)
    opt = opt or {}
    return {
        entries = scn.entries, picks = opt.picks or scn.picks, have = FX.CraftHave(scn), stock = FX.CraftStock(scn),
        auction = opt.auction or function(item) return scn.auction[item] end,
        cost = opt.cost,
        vendor = function(item) return scn.vendor[item] end,
        sells = function(item) return scn.sells[item] == true end,
        recipes = function(item) return scn.recipes[item] or {} end,
        available = function(rec) return not scn.unavailable[rec.id] end,
    }
end

-- Recipes as the window may read them, with a price lookup and an optional cut: for the craft estimate and the Opportunities list.
-- Some recipes are deliberately incomplete (no materials, no output item, an output the game gave only as a maximum, a maximum below the
-- minimum), because those are the shapes Prices.Estimate has to refuse or repair. recipes[i] = { id, name, prof, outItem, outMin, outMax, mats }.
function FX.Economy(seed, opt)
    opt = opt or {}
    local scn = FX.Crafting(seed, { items = Clamp(opt.items, 2, FX.LIMITS.pool, 5), entries = 0 })
    local rng = FX.Rng(seed * 3 + 1)
    -- better stocked houses than the shopping scenarios, and dearer products, so that most recipes can be priced and some lose money
    local lookup = {}
    for _, id in ipairs(scn.pool) do
        local p = Offer(rng, 0.92)
        if p then p.total = p.qty + rng:Int(10, 60) end
        lookup[id] = p
    end
    for _, id in ipairs(scn.products) do
        local p = Offer(rng, 0.92)
        if p then p.price, p.total = rng:Pick({ 50, 150, 700, 2500, 9000, 30000 }), p.qty + rng:Int(0, 30) end
        lookup[id] = p
    end
    local n = Clamp(opt.recipes, 1, FX.LIMITS.entries, rng:Int(2, 6))
    local names = { "Alpha", "alpha", "Beta", "beta", "Gamma", "Delta" }
    local recipes = {}
    for i = 1, n do
        local r = { id = 6000 + i, name = rng:Pick(names), prof = rng:Pick({ 171, 164, 333 }) }
        if not rng:Chance(0.06) then
            r.mats = Mats(rng, scn.pool, rng:Int(1, 4), 14)
            -- the output can be a product, or a material that other recipes use
        elseif rng:Chance(0.5) then r.mats = {} end
        if not rng:Chance(0.05) then r.outItem = rng:Chance(0.25) and rng:Pick(scn.pool) or rng:Pick(scn.products) end
        local roll = rng:Next()
        if roll < 0.62 then r.outMin = rng:Int(1, 5) r.outMax = r.outMin
        elseif roll < 0.74 then r.outMin = rng:Int(1, 3) r.outMax = r.outMin + rng:Int(1, 3)
        elseif roll < 0.80 then r.outMax = rng:Int(1, 4)                    -- only a maximum
        elseif roll < 0.86 then r.outMin = rng:Int(3, 6) r.outMax = r.outMin - rng:Int(1, 2)   -- a maximum below the minimum
        elseif roll < 0.92 then r.outMin = rng:Int(1, 4)                    -- only a minimum
        end                                                                  -- else: not known
        recipes[i] = r
    end
    return { seed = seed, now = FX.NOW, pool = scn.pool, products = scn.products, recipes = recipes, lookup = lookup, cut = scn.cut }
end

-- What the bank and the guild bank were last seen to hold, the way Stock.lua is told: bank = nil (never seen) or { tabs = { [bagID] = { at, n } },
-- uncertain }; guild = nil or { nt, tabs = { [index] = { at, n, by = "me" | "other", w = 1 | 0 | nil, rem = -1 | 0 | count | nil, u } } } (an index
-- up to nt with no entry is a tab that was never read). char is "me"; now is when the allowance of a tab is judged; live says a bag change was just
-- seen at the bank. rem = 0 was seen at the tab's own time (the tab is stored with that time).
function FX.StockObs(seed, opt)
    opt = opt or {}
    local rng = FX.Rng(seed)
    local ids = {}
    for i = 1, 4 do ids[i] = 10 * i + rng:Int(0, 9) end
    local function Counts()
        local n = {}
        for _, id in ipairs(ids) do if rng:Chance(0.6) then n[id] = rng:Int(1, 20) end end
        return n
    end
    local obs = { seed = seed, char = "me", items = ids, useGuild = rng:Chance(0.7), inGuild = rng:Chance(0.85),
        live = { bankPending = rng:Chance(0.1), guildPending = rng:Chance(0.1) } }
    obs.now = FX.NOW + rng:Pick({ 0, 100, 3600, 21599 })
    if rng:Chance(0.85) then
        local bank = { tabs = {}, uncertain = rng:Chance(0.2) }
        local bags = { 6, 7, 8, 9 }
        rng:Shuffle(bags)
        for i = 1, rng:Int(1, 3) do bank.tabs[bags[i]] = { at = obs.now - rng:Pick({ 60, 3600, 90000 }), n = Counts() } end
        obs.bank = bank
    end
    if rng:Chance(0.85) then
        local nt = rng:Int(2, 4)
        local guild, any = { nt = nt, tabs = {} }, false
        for i = 1, nt do
            if rng:Chance(0.8) then
                any = true
                -- ages around the allowance rule (6 hours = 21600 s, believed while younger)
                guild.tabs[i] = { at = obs.now - rng:Pick({ 60, 21599, 21600, 21601, 50000 }), n = Counts(), by = rng:Chance(0.75) and "me" or "other",
                    w = rng:Pick({ 1, 1, 1, 0, false }) or nil, rem = rng:Pick({ -1, -1, 0, 0, 5, false }) or nil, u = rng:Chance(0.12) or nil }
            end
        end
        if any then obs.guild = guild end
    end
    return obs
end
