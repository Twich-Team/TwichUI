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
FX.LIMITS = { records = 5000, items = 200, tiers = 8, scans = 400, markets = 6 }

local floor = math.floor

---------------------------------------------------------------------------
-- The generator
---------------------------------------------------------------------------
local Rng = {}
Rng.__index = Rng

function FX.Rng(seed)
    if type(seed) ~= "number" or seed ~= seed or seed == math.huge or seed == -math.huge then seed = 0 end
    seed = math.abs(floor(seed)) % 4503599627370496   -- 2^52
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
    if type(v) ~= "number" or v ~= v then return default end
    return math.max(lo, math.min(hi, floor(v)))
end

local function Rate(v, default)
    if type(v) ~= "number" or v ~= v then return default end
    return math.max(0, math.min(1, v))
end

---------------------------------------------------------------------------
-- Auction records for one house
---------------------------------------------------------------------------
local STACKS = { 1, 1, 1, 1, 2, 3, 4, 5, 5, 7, 10, 10, 15, 20, 20, 40, 200, 1000, 10000 }
local BAD_ITEM = { 0, -5, 1.5, "12", false, 2147483648, 0 / 0, math.huge }
local BAD_COUNT = { 0, -1, 2.5, "3", false, 10001, 0 / 0 }
local BAD_BUYOUT = { -1, 1.5, "900", 100000000000, math.huge, 0 / 0, false }

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
    return { seed = seed, key = ("Realm%d|%s"):format(seed % 1000, rng:Pick({ "Alliance", "Horde", "unknown" })), items = ids, scans = scans,
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
