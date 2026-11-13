-- The Workshop's prices (TwichUI_Workshop/Prices.lua, Opportunities.lua, Scan.lua): stack-to-unit conversion, invalid auction records,
-- the saved scans (markets kept apart, bounded, an older complete scan kept), what one craft costs and earns (full materials, output
-- ranges, the auction house cut only when confirmed, unknown never zero), sorting and filtering, and the scan itself against a FAKE
-- auction house with a virtual clock: refusals, repeated clicks, throttling, bounded batches, failures, interruption, stale callbacks.
-- Synthetic: this proves our logic, not what the real auction house does (docs/workshop.md lists the live-client checks).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

-- an item entry "p,q,l,t,x" as numbers
local function Parse(e) local p, q, l, t, x = e:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$"); return { tonumber(p), tonumber(q), tonumber(l), tonumber(t), tonumber(x) } end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }

-- a virtual clock and timers, a fake auction house
local function Setup()
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = c.TwichUIDB or {}
  local clock, timers = 0, {}
  c.GetTime = function() return clock end
  c.time = function() return 1000000 + math.floor(clock) end
  c.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = clock + d, fn = fn } end }
  local made = {}
  c.CreateFrame = function(kind) local fr = MIFake(kind); made[#made + 1] = fr; return fr end
  c.GetRealmName = function() return "Realm" end
  local ah = { ready = true, sent = 0, infoCalls = 0, records = {}, side = "Alliance" }
  c.C_AuctionHouse = {
    IsThrottledMessageSystemReady = function() return ah.ready end,
    ReplicateItems = function() ah.sent = ah.sent + 1; if ah.sendFails then error("no") end end,
    GetNumReplicateItems = function() return #ah.records end,
    -- the game's own index is 0-based (records 0 .. n-1); anything outside is counted so a test can tell
    GetReplicateItemInfo = function(i)
      ah.infoCalls = ah.infoCalls + 1
      local r = ah.records[i + 1]
      if i < 0 or i >= #ah.records then ah.outOfRange = (ah.outOfRange or 0) + 1 end
      if not r then return end
      return "n", 1, r.count, 1, true, 1, "", 0, 0, r.buyout, 0, nil, nil, "o", "o", 0, r.item, r.hasAll ~= false
    end,
  }
  c.AuctionHouseFrame = MIFake("Frame")
  c.UnitFactionGroup = function() return ah.side end
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  c.TwichUI.Workshop.Prices.FEED_LEGACY_HISTORY = true   -- these tests exercise the 1.3 history feed; production keeps it frozen (test_workshop_schema.lua)
  local t = { c = c, ah = ah, W = c.TwichUI.Workshop }
  function t.Fire(event)
    for _, fr in ipairs(made) do
      if fr.events[event] and fr.scripts.OnEvent then fr.scripts.OnEvent(fr, event) end
    end
  end
  function t.Listening() local n = 0 for _, fr in ipairs(made) do for _ in pairs(fr.events) do n = n + 1 end end return n end
  -- runs every timer due within `sec` seconds (zero-delay chains included)
  function t.Advance(sec)
    local target = clock + sec
    while true do
      local best, bi
      for i, tm in ipairs(timers) do if tm.at <= target and (not best or tm.at < best.at) then best, bi = tm, i end end
      if not best then break end
      table.remove(timers, bi)
      if best.at > clock then clock = best.at end
      best.fn()
    end
    clock = target
  end
  -- runs exactly the earliest timer
  function t.Tick()
    local best, bi
    for i, tm in ipairs(timers) do if not best or tm.at < best.at then best, bi = tm, i end end
    if not best then return false end
    table.remove(timers, bi)
    if best.at > clock then clock = best.at end
    best.fn()
    return true
  end
  function t.Pending() return #timers end
  function t.Clock() return clock end
  return t
end

---------------------------------------------------------------------------
-- Stack and unit prices; invalid auction records
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR = t.W.Prices
  Same(PR.Unit(300, 3), 100, "an exact division")
  Same(PR.Unit(301, 3), 101, "a stack that doesn't divide is rounded UP to whole copper")
  Same(PR.Unit(1, 50), 1, "never below one copper")
  Same(PR.Unit(99999999999, 1), 99999999999, "the largest price the game allows")
  Same(PR.Unit(99999999999, 7), 14285714286)
  Same(PR.Unit(0, 1), nil, "no buyout is not a price"); Same(PR.Unit(100, 0), nil, "no items is not a stack")
  Same(PR.Unit(1.5, 1), nil); Same(PR.Unit(100, 2.5), nil); Same(PR.Unit(-5, 1), nil); Same(PR.Unit("100", 1), nil)
  Same(PR.Unit(100000000000, 1), nil, "above the game's maximum"); Same(PR.Unit(100, 10001), nil)
  Same(PR.Unit(0 / 0, 1), nil, "NaN")

  local b = PR.NewBatch()
  Check(b:Add(10, 20, 2000), "20 for 20 silver: 100 each")
  Check(b:Add(10, 5, 400), "5 for 4 silver: 80 each, the cheaper unit price")
  Check(b:Add(10, 10, 800), "another at exactly 80 each")
  Check(b:Add(10, 4, 1000), "250 each")
  Check(not b:Add(10, 1, 0), "bid only: no buyout"); Same(b.noBuyout, 1)
  Check(not b:Add(10, 0, 100), "a stack of none"); Check(not b:Add(10, 1, -5)); Check(not b:Add(10, 1, 1.5)); Check(not b:Add("x", 1, 1))
  Check(not b:Add(nil)); Check(not b:Add(10, 1, nil), "an unreadable price is invalid, not free")
  Check(b:Add(99, 1, 1), "every item counts, whether or not a recipe uses it")
  Check(b:Add(11, 3, 1), "1 copper for 3: rounds up to 1, never 0")
  Same(b.invalid, 6); Same(b.used, 6); Same(b.read, 13)
  local items, n, over, dropped = b:Items()
  Same(n, 3); Same(over, false); Same(dropped, 0)
  local e10 = Parse(items[10])
  Same(e10[1], 80, "cheapest unit price"); Same(e10[2], 15, "items at that exact price (5 + 10)")
  Same(e10[3], 4, "buyout listings seen"); Same(e10[4], 39, "items in those listings")
  Same(e10[5], 100, "the next higher unit price listed (100, then 250)")
  Same(Parse(items[11])[1], 1); Same(Parse(items[99])[1], 1); Same(items[98], nil)
  Same(Parse(items[11])[5], 0, "a single listing has no next price")
  -- a price that is only cheaper per item is found without division error: 7 for 700 (100 each) vs 3 for 299 (99.67 each)
  b = PR.NewBatch(); b:Add(5, 7, 700); b:Add(5, 3, 299)
  local it = Parse(b:Items()[5])
  Same(it[1], 100, "299/3 = 99.67 rounds up to 100"); Same(it[2], 3, "the 3-stack is the cheaper one (99.67 < 100) so it holds the lowest")
  Same(it[5], 0, "the next price rounds to the same copper: not a different price")
  -- the next higher price is the lowest ABOVE the cheapest, however the listings arrive
  b = PR.NewBatch(); b:Add(6, 1, 500); b:Add(6, 1, 300); b:Add(6, 1, 400); b:Add(6, 1, 300); b:Add(6, 1, 900)
  it = Parse(b:Items()[6]); Same(it[1], 300); Same(it[2], 2); Same(it[3], 5); Same(it[5], 400)
  -- explicit false means the game had not loaded the record
  b = PR.NewBatch(); b:Add(5, 1, 10, false); b:Add(5, 1, 10, true); b:Add(5, 1, 10, nil)
  Same(b.partialInfo, 1, "only an explicit false counts")
  b = PR.NewBatch(); b:Add(77, 1, 10, false); b:Add(5, 1, 10, true)
  Same(b.partialInfo, 1, "a record of ANY item can say it lacked information: every item is kept now")
  -- secret values are dropped, never compared
  t.c.issecretvalue = function(v) return v == "SECRET" end
  b = PR.NewBatch()
  Check(not b:Add(5, 1, "SECRET")); Check(not b:Add("SECRET", 1, 5)); Same(b.invalid, 2)
  -- more than the limit: the recipe items first, then the items with the most listings, then the lowest item numbers
  b = PR.NewBatch({ [PR.MAX_ITEMS + 3] = true })
  for i = 1, PR.MAX_ITEMS + 3 do b:Add(i, 1, 10) end
  b:Add(PR.MAX_ITEMS + 2, 1, 10)   -- a second listing: more listings than the rest
  local kept, count, cut, lost = b:Items()
  Same(count, PR.MAX_ITEMS); Check(cut, "cut off"); Same(lost, 3)
  Check(kept[PR.MAX_ITEMS + 3], "a recipe item is kept first"); Check(kept[PR.MAX_ITEMS + 2], "then the item with most listings")
  Check(kept[1] and kept[PR.MAX_ITEMS - 2], "then the lowest item numbers"); Check(not kept[PR.MAX_ITEMS - 1] and not kept[PR.MAX_ITEMS] and not kept[PR.MAX_ITEMS + 1], "and these three did not fit")
  -- M7.1: the stepped job gives exactly the answer Items() gives, whatever the step size, under the limit and over it (with a small limit
  -- so the over-limit case is cheap); a job that is not finished has no result; and no step does more than its share
  local was = PR.MAX_ITEMS
  for _, lim in ipairs({ 1000, 7 }) do
    PR.MAX_ITEMS = lim
    for _, size in ipairs({ 0, 1, 6, 7, 8, 25, 400 }) do
      local pri = { [size] = true, [3] = true }
      local function Fill() local x = PR.NewBatch(pri) for i = 1, size do x:Add(i * 3 + 1, 1 + i % 4, 10 + i % 17) if i % 5 == 0 then x:Add(i * 3 + 1, 2, 500) end end return x end
      local whole = { Fill():Items() }
      for _, step in ipairs({ 1, 3, 400 }) do
        local job, steps = Fill():ItemsJob(), 0
        Check(job:Result() == nil, "no result before the job is finished")
        while not job:Step(step) do
          steps = steps + 1
          Check(steps < 100000, "the job finishes")
          Check(job:Result() == nil, "and has no result while unfinished")
        end
        local part = { job:Result() }
        Same(part[2], whole[2], ("count, size %d limit %d step %d"):format(size, lim, step)); Same(part[3], whole[3], "over the limit"); Same(part[4], whole[4], "dropped")
        for id, e in pairs(whole[1]) do Same(part[1][id], e, ("entry %d, size %d limit %d step %d"):format(id, size, lim, step)) end
        for id in pairs(part[1]) do Check(whole[1][id] ~= nil, "no extra entry") end
        if lim == 1000 and size >= 25 and step == 1 then Check(steps >= size, "a one-item step does not do the whole batch at once (" .. steps .. " steps)") end
      end
    end
  end
  PR.MAX_ITEMS = was
end

---------------------------------------------------------------------------
-- Saved scans: markets, age, bounds, an older complete scan kept
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR, Q = t.W.Prices, t.W.Queue
  local function Scan(at, complete, price, side) return { realm = "Realm", side = side or "Alliance", at = at, complete = complete, read = 5, used = 5, n = 1, items = { [10] = ("%d,3,2,8,0"):format(price) } } end
  Same(PR.MAX_MARKETS, 3, "three auction houses are kept by default"); PR.MAX_MARKETS = 4   -- (the cases below use four)
  Same(PR.Key("Realm", "Alliance"), "Realm|Alliance"); Same(PR.Key("Realm", nil), "Realm|unknown", "a side the game didn't give is its own market")
  Same(PR.Key(nil, "Alliance"), nil)
  Same(PR.Market("Realm|Alliance"), nil, "nothing saved yet")
  Check(PR.Commit("Realm|Alliance", Scan(5000, true, 100)))
  Check(PR.Commit("Realm|Horde", Scan(6000, true, 900, "Horde")))
  Check(PR.Commit("Other|Alliance", { realm = "Other", side = "Alliance", at = 9000, complete = true, n = 1, items = { [10] = "7,1,1,1,0" } }))
  local a, h = PR.Market("Realm|Alliance"), PR.Market("Realm|Horde")
  Same(PR.Lookup(a, 10).price, 100, "the Alliance market"); Same(PR.Lookup(h, 10).price, 900, "the Horde market is separate, never merged")
  Same(PR.Lookup(a, 11), nil)
  local look = PR.Lookup(a, 10)
  Same(look.qty, 3); Same(look.listings, 2); Same(look.total, 8); Same(look.at, 5000); Same(look.complete, true)
  Same(PR.Newest("Realm").side, "Horde", "the most recently scanned market of THIS realm"); Same(PR.Newest("Other").key, "Other|Alliance")
  Same(PR.Newest("Nowhere"), nil)
  Check(PR.Label(a):find("Alliance auction house on Realm", 1, true)); Check(PR.Label({ realm = "R", side = "unknown" }):find("auction house on R", 1, true))
  -- age
  Same(PR.Age(5000, 5000 + 90), 90); Same(PR.Age(5000, 4000), 0, "a clock that moved back never gives a negative age"); Same(PR.Age("x", 1), nil)
  Same(PR.AgeText(5), "just now"); Same(PR.AgeText(60), "1 minute ago"); Same(PR.AgeText(14 * 60), "14 minutes ago"); Same(PR.AgeText(3600), "1 hour ago")
  Same(PR.AgeText(5 * 3600), "5 hours ago"); Same(PR.AgeText(86400 * 2), "2 days ago"); Same(PR.AgeText(nil), "at an unknown time")
  -- a complete scan is never replaced by one that is not complete
  local ok, why = PR.Commit("Realm|Alliance", Scan(7000, false, 5))
  Check(not ok and why == "kept", "kept"); Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).price, 100, "the earlier complete prices stand"); Same(PR.Market("Realm|Alliance").at, 5000)
  Check(PR.Commit("Realm|Alliance", Scan(8000, true, 50)), "a newer complete scan replaces it"); Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).price, 50)
  -- not complete over nothing or over not complete is kept as not complete
  Check(PR.Commit("Realm|Neutral", Scan(100, false, 5))); Same(PR.Market("Realm|Neutral").complete, false)
  Check(PR.Commit("Realm|Neutral", Scan(200, false, 6))); Same(PR.Lookup(PR.Market("Realm|Neutral"), 10).price, 6)
  Check(PR.Commit("Realm|Neutral", Scan(300, true, 7))); Same(PR.Market("Realm|Neutral").complete, true)
  -- bounded: a fifth market pushes out the one scanned longest ago
  local keys = 0
  for k in pairs(t.c.TwichUIWorkshopDB.markets) do keys = keys + 1 end
  Check(keys <= PR.MAX_MARKETS, "at most " .. PR.MAX_MARKETS .. " markets: " .. keys)
  Check(PR.Commit("Realm|New", Scan(99999, true, 1)))
  Same(PR.Market("Realm|Horde") ~= nil, true, "a recent market stays")
  keys = 0
  for k in pairs(t.c.TwichUIWorkshopDB.markets) do keys = keys + 1 end
  Same(keys, PR.MAX_MARKETS); Same(PR.Market("Realm|Neutral"), nil, "the one scanned longest ago went")
  -- bad input and bad saved entries are not prices
  Check(not PR.Commit("k", { items = {} })); Check(not PR.Commit(nil, Scan(1, true, 1))); Check(not PR.Commit("k", { at = 0, items = {} }))
  local m = t.c.TwichUIWorkshopDB.markets["Realm|Alliance"]
  m.items[20] = "bad"; m.items[21] = "0,1,1,1,0"; m.items[22] = "-5,1,1,1,0"; m.items[23] = "1.5,1,1,1,0"; m.items[24] = "100,x,1,1"; m.items[25] = ""; m.items[26] = { 0, 1, 1, 1 }; m.items[27] = 12
  local mk = PR.Market("Realm|Alliance")
  for _, id in ipairs({ 20, 21, 22, 23, 25, 26, 27 }) do Same(PR.Lookup(mk, id), nil, "item " .. id .. ": a bad saved entry is missing, never a zero price") end
  Same(PR.Lookup(mk, 24), nil, "an entry that does not parse is missing")
  m.items[28] = "100,2,1,5"; Same(PR.Lookup(mk, 28).price, 100, "an entry without the next price still reads"); Same(PR.Lookup(mk, 28).next, nil)
  t.c.TwichUIWorkshopDB.markets["Realm|Alliance"] = "junk"
  Same(PR.Market("Realm|Alliance"), nil, "a market that isn't a table is not read")
  t.c.TwichUIWorkshopDB.markets["Realm|Alliance"] = { at = "yesterday", items = {} }
  Same(PR.Market("Realm|Alliance"), nil, "no usable scan time: not used")
  -- a newer TwichUI wrote this: read, never changed
  t.c.TwichUIWorkshopDB.v = 3   -- (v 2 is this version's own database)
  local ok2, why2 = PR.Commit("Realm|Horde", Scan(123456, true, 1))
  Check(not ok2 and why2 == "held", "held"); Same(PR.Lookup(PR.Market("Realm|Horde"), 10).price, 900)
  t.c.TwichUIWorkshopDB.v = 1
  t.c.TwichUIDB.workshop = { v = 2 }
  Check(Q.Held() and PR.Held(), "the workshop data being newer holds the prices too")
  -- prices share the workshop key, so they are never in a profile, share or backup, and do not disturb the queue
  t.c.TwichUIDB.workshop.v = 1
  Check(Q.Add({ id = 1, name = "R", mats = { { item = 10, qty = 1 } } })); Same(#Q.Entries(), 1)
  Q.Unload(); Same(#Q.Entries(), 1, "the queue still loads beside the prices")
  Check(t.c.TwichUIWorkshopDB ~= nil and t.c.TwichUIDB.workshop.chars ~= nil and t.c.TwichUIDB.workshop.prices == nil, "the market data is not in TwichUIDB")
end

---------------------------------------------------------------------------
-- One craft: cost, sell price, profit
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR = t.W.Prices
  local function Lookup(map, at, complete)
    return function(item)
      local p = map[item]
      if not p then return nil end
      if type(p) == "number" then p = { price = p } end
      return { price = p.price, qty = p.qty, total = p.total, at = at or 1000, complete = complete ~= false }
    end
  end
  local rec = { outItem = 500, outMin = 1, outMax = 1, mats = { { item = 10, qty = 2 }, { item = 11, qty = 1 } } }
  local e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 500 }))
  Same(e.state, "ok"); Same(e.cost, 250, "2 x 100 + 1 x 50: the FULL materials, whatever is in the bags")
  Same(e.sellLow, 500); Same(e.sellHigh, 500); Same(e.profitLow, 250); Same(e.profitHigh, 250); Same(e.unit, 500)
  Same(e.cutRate, nil, "no cut known, none taken off")
  -- output quantity: two made per craft sell for two
  rec.outMin, rec.outMax = 2, 2
  e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 300 }))
  Same(e.sellLow, 600); Same(e.sellHigh, 600); Same(e.profitLow, 350, "the cost is for ONE craft, the sale for what ONE craft makes")
  -- an uncertain output is a range, never the maximum alone
  rec.outMin, rec.outMax = 1, 3
  e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 300 }))
  Same(e.sellLow, 300); Same(e.sellHigh, 900); Same(e.profitLow, 50); Same(e.profitHigh, 650)
  Check(e.profitLow ~= e.profitHigh, "a range is reported as a range")
  -- the output amount isn't known: unavailable, not assumed
  rec.outMin, rec.outMax = nil, nil
  e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 300 }))
  Same(e.state, "unknown"); Same(e.why, "noamount"); Same(e.profitLow, nil); Same(e.cost, 250, "the cost is still known")
  rec.outMin, rec.outMax = 2, 1
  Same(PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 300 })).why, "noamount", "an impossible range is not used")
  rec.outMin, rec.outMax = 1, 1
  -- the cut, only when confirmed
  Same(PR.CutRate("Alliance"), nil, "no side has a confirmed cut yet"); Same(PR.CutRate(nil), nil)
  Same(PR.Cut(1000, 0.05), 50); Same(PR.Cut(333, 0.05), 17, "rounded to whole copper")
  e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 1000 }), 0.05)
  Same(e.sellLow, 1000); Same(e.netLow, 950); Same(e.profitLow, 700, "950 - 250"); Same(e.cutRate, 0.05)
  rec.outMin, rec.outMax = 1, 2
  e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 333 }), 0.05)
  Same(e.netLow, 333 - 17); Same(e.netHigh, 666 - 33); Same(e.profitLow, 333 - 17 - 250); Same(e.profitHigh, 666 - 33 - 250)
  rec.outMin, rec.outMax = 1, 1
  PR.CUT.Alliance = 0.15
  Same(PR.CutRate("Alliance"), 0.15, "a confirmed side is used"); Same(PR.CutRate("Horde"), nil, "and only that side")
  PR.CUT.Alliance = 1; Same(PR.CutRate("Alliance"), nil, "a cut of everything is not a cut"); PR.CUT.Alliance = -0.1; Same(PR.CutRate("Alliance"), nil)
  PR.CUT.Alliance = "5%"; Same(PR.CutRate("Alliance"), nil); PR.CUT.Alliance = nil
  -- a loss is a negative profit, not unknown
  e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50, [500] = 100 }))
  Same(e.state, "ok"); Same(e.profitLow, -150)
  -- a missing price makes the whole cost, and so the profit, unknown (never zero)
  e = PR.Estimate(rec, Lookup({ [10] = 100, [500] = 500 }))
  Same(e.state, "unknown"); Same(e.why, "matprice"); Same(e.cost, nil, "no cost from part of the materials"); Same(e.profitLow, nil)
  Same(e.missing, 1); Same(e.sellLow, 500, "the sell price is still shown"); Check(e.mats[2].unavailable == "none" and e.mats[1].unit == 100)
  e = PR.Estimate(rec, Lookup({ [10] = 100, [11] = 50 }))
  Same(e.why, "sellprice"); Same(e.cost, 250); Same(e.sellLow, nil); Same(e.profitLow, nil)
  e = PR.Estimate(rec, Lookup({}))
  Same(e.why, "matprice"); Same(e.missing, 2)
  -- recipes the Workshop can't price
  Same(PR.Estimate({ outItem = 500, outMin = 1, outMax = 1 }, Lookup({ [500] = 1 })).why, "nomats", "materials not known or not supported")
  Same(PR.Estimate({ outItem = 500, outMin = 1, outMax = 1, mats = {} }, Lookup({ [500] = 1 })).why, "nomats", "an empty list is unknown, not free")
  Same(PR.Estimate({ outMin = 1, outMax = 1, mats = rec.mats }, Lookup({ [10] = 1, [11] = 1 })).why, "noitem", "an enchant makes no item")
  -- not enough listed to buy what one craft needs
  e = PR.Estimate(rec, Lookup({ [10] = { price = 100, qty = 1, total = 1 }, [11] = 50, [500] = 500 }))
  Same(e.why, "matprice"); Same(e.mats[1].unavailable, "few", "needs 2, only 1 listed")
  -- more than the cheapest listing holds: priced, but flagged
  e = PR.Estimate(rec, Lookup({ [10] = { price = 100, qty = 1, total = 9 }, [11] = 50, [500] = 500 }))
  Same(e.state, "ok"); Same(e.cheapest, true); Check(e.mats[1].cheapest)
  -- age and completeness of what was used
  local function Mixed(item)
    if item == 10 then return { price = 100, at = 500, complete = true } end
    if item == 11 then return { price = 50, at = 300, complete = false } end
    return { price = 500, at = 900, complete = true }
  end
  e = PR.Estimate(rec, Mixed)
  Same(e.oldest, 300, "the oldest observation used"); Same(e.incomplete, true, "one price came from a scan that wasn't complete")
  e = PR.Estimate(rec, Lookup({ [10] = 1, [11] = 1, [500] = 5 }, 1000, true))
  Same(e.incomplete, false)
end

---------------------------------------------------------------------------
-- The Opportunities list: sort, filter, unknown last
---------------------------------------------------------------------------
do
  local t = Setup()
  local PR, Op = t.W.Prices, t.W.Opps
  local prices = { [10] = 100, [20] = 10, [501] = 1000, [502] = 400, [503] = 200, [504] = 90, [506] = 50 }
  local function Lookup(item) local p = prices[item]; return p and { price = p, at = 1, complete = true } or nil end
  local function R_(id, name, prof, out, mats, lo, hi) return { id = id, name = name, prof = prof, outItem = out, outMin = lo or 1, outMax = hi or lo or 1, mats = mats } end
  local recipes = {
    R_(1, "Alpha", 171, 501, { { item = 10, qty = 2 } }),            -- 1000 - 200 = +800
    R_(2, "Bravo", 171, 502, { { item = 10, qty = 1 } }),            -- 400 - 100 = +300
    R_(3, "Charlie", 164, 503, { { item = 10, qty = 5 } }),          -- 200 - 500 = -300
    R_(4, "Delta", 164, 504, { { item = 10, qty = 1 } }, 1, 3),      -- low 90-100 = -10, high 270-100 = +170
    R_(5, "Echo", 171, 505, { { item = 10, qty = 1 } }),             -- no price for what it makes: unknown
    R_(6, "Foxtrot", 164, 506, { { item = 99, qty = 1 } }),          -- no price for a material: unknown
    R_(7, "Golf", 164, 507, nil),                                    -- materials unknown
    R_(8, "Hotel", 171, 502, { { item = 20, qty = 1 } }),            -- 400 - 10 = +390
  }
  local rows = Op.Rows(recipes, Lookup, nil)
  local sum = Op.Summary(rows)
  Same(sum.total, 8); Same(sum.priced, 5); Same(sum.profitable, 3, "Alpha, Bravo and Hotel; Delta is only profitable at its best case")
  local function Names(list) local out = {} for _, r in ipairs(list) do out[#out + 1] = r.rec.name end return table.concat(out, ",") end
  local opts = { sort = "profit", desc = true }
  Same(Names(Op.Select(rows, opts)), "Alpha,Hotel,Bravo,Delta,Charlie,Echo,Foxtrot,Golf", "highest profit first, unknown ones last by name; a range sorts by its low end")
  opts.desc = false
  Same(Names(Op.Select(rows, opts)), "Charlie,Delta,Bravo,Hotel,Alpha,Echo,Foxtrot,Golf", "ascending still keeps the unknown below the known")
  Op.SetSort(opts, "cost")
  Same(opts.sort, "cost"); Same(opts.desc, false, "cost starts cheapest first")
  Same(Names(Op.Select(rows, opts)), "Hotel,Bravo,Delta,Alpha,Charlie,Echo,Foxtrot,Golf", "cheapest first; ties by name")
  Op.SetSort(opts, "cost"); Same(opts.desc, true, "clicking the same column flips it")
  Op.SetSort(opts, "sell"); Same(opts.sort, "sell"); Same(opts.desc, true)
  Same(Names(Op.Select(rows, opts)), "Alpha,Bravo,Hotel,Charlie,Delta,Echo,Foxtrot,Golf", "by sell price, highest first (Bravo and Hotel tie, then by name)")
  Op.SetSort(opts, "name"); Same(opts.sort, "sell", "only the numeric columns sort")
  -- filters
  opts = { sort = "profit", desc = true, prof = 164 }
  Same(Names(Op.Select(rows, opts)), "Delta,Charlie,Foxtrot,Golf", "one profession")
  opts = { sort = "profit", desc = true, profitOnly = true }
  Same(Names(Op.Select(rows, opts)), "Alpha,Hotel,Bravo", "profitable only drops losses and unknowns")
  opts.prof = 164
  Same(#Op.Select(rows, opts), 0, "no profitable result in that profession")
  Same(Names(Op.Select(rows, nil)), "Alpha,Hotel,Bravo,Delta,Charlie,Echo,Foxtrot,Golf", "the defaults")
  -- why an estimate is unknown, in words
  Check(Op.WhyText(rows[5].est):find("no price", 1, true)); Same(Op.WhyText(rows[6].est), "1 material has no price")
  Check(Op.WhyText(rows[7].est):find("materials", 1, true)); Same(Op.WhyText(rows[1].est), nil)
  -- the basis, on demand
  local function Money(n) return n .. "c" end
  local function Name(i) return "item" .. i end
  local lines = Op.Basis(rows[4], { label = "the Alliance auction house on Realm", at = 1000, complete = false }, Name, Money, 1000 + 600)
  local text = {}
  for _, l in ipairs(lines) do text[#text + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end
  text = table.concat(text, "\n")
  Check(text:find("scanned 10 minutes ago", 1, true) and text:find("not a complete scan", 1, true), text)
  Check(text:find("1 x item10 | 100c each = 100c", 1, true), text)
  Check(text:find("Cost to make | 100c", 1, true) and text:find("90c to 270c", 1, true), text)
  Check(text:find("Auction house cut | not deducted", 1, true), "the cut is said to be unapplied")
  Check(text:find("Profit before fees | -10c to 170c", 1, true) and not text:find("Estimated profit", 1, true), "never called profit after fees when no fee was taken: " .. text)
  Check(text:find("not sales", 1, true) and text:find("Deposits", 1, true), "the limits are stated once, briefly")
  -- the short tooltip: few lines, an unknown price stays visible, and "before fees" is never called profit after fees
  local function Flat(ls) local t = {} for _, l in ipairs(ls) do t[#t + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end return table.concat(t, "\n"), #ls end
  local short, n = Flat(Op.Tip(rows[1], { label = "x", at = 1000, complete = false }, Money, 1000 + 4 * 3600))
  Check(n <= 6 and short:find("Cost to make | ", 1, true) and short:find("Sell price | ", 1, true), short)
  Check(short:find("Profit before fees | ", 1, true) and not short:find("Estimated profit", 1, true), short)
  Check(short:find("4 hours ago", 1, true) and short:find("Partial scan", 1, true) and short:find("Hold Shift for details", 1, true), short)
  Check(not short:find("item10", 1, true), "no reagent breakdown by default")
  local unknown = Op.Tip(rows[6], nil, Money, 1)
  local utext = Flat(unknown)
  Check(utext:find("!1 material has no price", 1, true), "an unknown price is a visible warning line: " .. utext)
  Check(not utext:find("Profit before fees |", 1, true), "and no profit is invented")
  local after = Op.Tip(Op.Rows(recipes, Lookup, 0.05)[1], nil, Money, 1)
  Check(Flat(after):find("Estimated profit | ", 1, true), "with the cut taken off it is the estimated profit")
  lines = Op.Basis(rows[1], nil, Name, Money, 1)
  rows = Op.Rows(recipes, Lookup, 0.05)
  lines = Op.Basis(rows[1], nil, Name, Money, 1)
  text = {}
  for _, l in ipairs(lines) do text[#text + 1] = l[1] .. (l[2] and (" | " .. l[2]) or "") end
  text = table.concat(text, "\n")
  Check(text:find("Auction house cut (5%) | -50c", 1, true), text)
  Same(Op.Summary(rows).profitable, 3)
end

---------------------------------------------------------------------------
-- The scan: refusals
---------------------------------------------------------------------------
local function Records(n, item) local r = {} for i = 1, n do r[i] = { item = item or 10, count = 1, buyout = 100 + i } end return r end
do
  local t = Setup()
  local SC, PR = t.W.Scan, t.W.Prices
  local want = { [10] = true }
  -- closed
  t.c.AuctionHouseFrame:Hide()
  local ok, why = SC.Start(want)
  Check(not ok and why == "closed" and SC.state == "unavailable"); Same(t.ah.sent, 0, "nothing is sent while the auction house is closed")
  Check(SC.Message():find("Open the auction house", 1, true))
  t.c.AuctionHouseFrame:Show()
  -- the posting page's search is running
  t.c.TwichUI.AuctionScan = { Busy = function() return true end }
  ok, why = SC.Start(want); Check(not ok and why == "posting"); Same(t.ah.sent, 0, "never competes with the posting page's search")
  t.c.TwichUI.AuctionScan = nil
  -- no realm
  t.c.GetRealmName = function() return "" end
  ok, why = SC.Start(want); Check(not ok and why == "market"); t.c.GetRealmName = function() return "Realm" end
  -- the API isn't there
  local api = t.c.C_AuctionHouse.ReplicateItems
  t.c.C_AuctionHouse.ReplicateItems = nil
  ok, why = SC.Start(want); Check(not ok and why == "api"); Check(SC.Message():find("doesn't offer", 1, true))
  t.c.C_AuctionHouse.ReplicateItems = api
  -- saved prices written by a newer TwichUI
  t.c.TwichUIWorkshopDB = { v = 5, markets = {} }
  ok, why = SC.Start(want); Check(not ok and why == "held"); Same(t.ah.sent, 0)
  t.c.TwichUIWorkshopDB = nil
  Same(t.Listening(), 0, "no event is listened to while no scan runs")
  -- the request itself errors
  t.ah.sendFails = true
  ok = SC.Start(want)
  Check(ok); Same(SC.state, "failed"); Same(SC.why, "api"); Same(t.Listening(), 0, "and it stops listening")
  t.ah.sendFails = false
  Same(t.W.Prices.Market("Realm|Alliance"), nil, "a refusal or failure saves nothing")
end

---------------------------------------------------------------------------
-- The scan: a full run, in bounded batches, with repeated clicks
---------------------------------------------------------------------------
do
  local t = Setup()
  local SC, PR = t.W.Scan, t.W.Prices
  local want = { [10] = true, [11] = true }
  t.ah.records = Records(1000, 10)
  t.ah.records[#t.ah.records + 1] = { item = 11, count = 20, buyout = 2000 }   -- 100 each
  t.ah.records[#t.ah.records + 1] = { item = 11, count = 5, buyout = 0 }       -- bid only
  t.ah.records[#t.ah.records + 1] = { item = 77, count = 5, buyout = 5 }       -- not asked for
  local changes = 0
  SC.OnChange = function() changes = changes + 1 end
  Check(SC.Start(want)); Same(SC.state, "scanning"); Same(SC.phase, "awaiting"); Same(t.ah.sent, 1)
  Check(t.Listening() > 0)
  local ok, why = SC.Start(want)
  Check(not ok and why == "busy", "a second click while scanning does nothing"); Same(t.ah.sent, 1, "the request is not sent twice")
  Check(SC.Message():find("Asking the auction house", 1, true))
  -- the listing event: nothing is read until it has been quiet
  t.Fire("REPLICATE_ITEM_LIST_UPDATE")
  Same(SC.phase, "settling"); Same(t.ah.infoCalls, 0)
  t.Advance(1); t.Fire("REPLICATE_ITEM_LIST_UPDATE")   -- more arrived: the wait starts over
  t.Advance(1.5); Same(t.ah.infoCalls, 0, "still waiting: the last update was only 1.5 s ago")
  -- bounded batches: each timer step reads at most 400 records
  Check(t.Tick()); Same(SC.phase, "reading"); Same(t.ah.infoCalls, 400, "the first batch")
  Same(SC.Message(), "Reading listings...")
  local pr = SC.Progress()
  Check(pr > 0.08 and pr < 0.5, "a third of the way through the reading: " .. tostring(pr))
  Check(t.Tick()); Same(t.ah.infoCalls, 800)
  Check(t.Tick()); Same(t.ah.infoCalls, 1003, "the last, smaller batch (records past the end aren't asked for)")
  -- M7.1: the saved entries are built on the next timer tick(s), not in the last read step
  Same(SC.state, "scanning"); Same(SC.phase, "reading", "the entries are still to be built")
  Check(t.Tick()); Same(t.ah.infoCalls, 1003, "building the entries reads no more records")
  -- A3: the distribution is summarised in steps of at most Prices.TIERS_STEP price tiers, and this item has about that many: a tick or two more
  for _ = 1, 3 do if SC.state == "scanning" then Check(t.Tick()) end end
  Same(t.ah.infoCalls, 1003, "and still no more records")
  Same(SC.state, "done"); Check(SC.result.complete); Same(SC.result.items, 3, "every item, wanted or not"); Same(SC.result.used, 1002)
  Same(t.ah.outOfRange, nil, "records 0 .. n-1 are read, nothing outside them")
  Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).qty, 1, "the record at index 0 (101 copper) counts")
  Same(t.Listening(), 0, "listening ends with the scan")
  local m = PR.Market("Realm|Alliance")
  Check(m and m.complete and m.n == 3 and m.scope == "full", "saved as a complete full scan of the Alliance market")
  Same(PR.Lookup(m, 10).price, 101); Same(PR.Lookup(m, 11).price, 100); Same(PR.Lookup(m, 77).price, 1, "an item no recipe uses is priced too")
  Same(PR.Lookup(m, 11).total, 20, "the bid-only listing is not counted")
  Check(SC.Message():find("Prices found for 3 items", 1, true), SC.Message()); Check(changes > 5, "the window is told as it goes")
  Same(m.at, t.c.time())
  -- the old response timeout does nothing
  t.Advance(200); Same(SC.state, "done")
  -- a later scan can run again; an update with no scan running is ignored
  t.Fire("REPLICATE_ITEM_LIST_UPDATE"); Same(SC.state, "done")
  Check(SC.Start(want)); Same(t.ah.sent, 2)
end

---------------------------------------------------------------------------
-- The scan: failure, interruption, stale callbacks, the earlier scan kept
---------------------------------------------------------------------------
do
  local t = Setup()
  local SC, PR = t.W.Scan, t.W.Prices
  local want = { [10] = true }
  -- an earlier complete scan
  t.ah.records = Records(3, 10)
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(3)
  Same(SC.state, "done")
  local before = PR.Market("Realm|Alliance")
  Same(PR.Lookup(before, 10).price, 101)

  -- no answer: failed, and the earlier prices stand
  t.ah.records = Records(3, 10); for _, r in ipairs(t.ah.records) do r.buyout = 5 end
  Check(SC.Start(want)); t.Advance(100)
  Same(SC.state, "failed"); Same(SC.why, "noResponse")
  Check(SC.Message():find("didn't send its listings", 1, true) and SC.Message():find("earlier prices were kept", 1, true), SC.Message())
  Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).price, 101, "the earlier scan is kept"); Same(PR.Market("Realm|Alliance").at, before.at)
  Same(t.Listening(), 0)

  -- dropped by the throttle
  Check(SC.Start(want)); t.Advance(1); t.Fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED")
  Same(SC.state, "failed"); Same(SC.why, "dropped")
  -- a drop long after the request isn't ours
  Check(SC.Start(want)); t.Advance(30); t.Fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED"); Same(SC.state, "scanning", "not ours")
  t.Advance(100); Same(SC.why, "noResponse")

  -- not ready: waits, then goes when told, or gives up
  t.ah.ready = false
  local sent = t.ah.sent
  Check(SC.Start(want)); Same(SC.phase, "waiting"); Same(t.ah.sent, sent, "nothing is sent while the game says it isn't ready")
  t.Fire("REPLICATE_ITEM_LIST_UPDATE"); Same(SC.phase, "waiting", "an update before we asked is not our answer")
  t.ah.ready = true; t.Fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
  Same(SC.phase, "awaiting"); Same(t.ah.sent, sent + 1)
  t.Fire("AUCTION_HOUSE_CLOSED")
  t.ah.ready = false
  Check(SC.Start(want)); t.Advance(31)
  Same(SC.state, "failed"); Same(SC.why, "throttled"); Same(t.ah.sent, sent + 1, "never sent")
  t.ah.ready = true

  -- the auction house closes mid-scan: interrupted, the earlier prices stand, old callbacks do nothing
  local start = t.Clock()
  Check(SC.Start(want)); local firstSent = t.ah.sent
  t.Advance(1); t.Fire("AUCTION_HOUSE_CLOSED")
  Same(SC.state, "interrupted"); Same(SC.why, "closed"); Same(t.Listening(), 0)
  Check(SC.Message():find("closed", 1, true) and SC.Message():find("earlier prices were kept", 1, true))
  t.Fire("REPLICATE_ITEM_LIST_UPDATE"); Same(SC.state, "interrupted", "an event after the end is ignored")
  t.Advance(5)
  Check(SC.Start(want)); Same(t.ah.sent, firstSent + 1)
  t.Advance(80)   -- the FIRST scan's 90 s response timer fires inside this window: it must not touch the second scan
  Same(SC.state, "scanning", "a timer from the interrupted scan does nothing to the new one")
  t.Advance(30); Same(SC.why, "noResponse", "the new scan's own timer still works")
  Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).price, 101, "still the first scan's prices")

  -- closed during the reading, with or without the event
  t.ah.records = Records(1000, 10)
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); Check(t.Tick()); Same(SC.phase, "reading")
  t.c.AuctionHouseFrame:Hide()
  Check(t.Tick()); Same(SC.state, "interrupted", "the next step notices the window is gone"); Same(t.ah.infoCalls > 0, true)
  local calls = t.ah.infoCalls
  t.Advance(10); Same(t.ah.infoCalls, calls, "no further reading")
  t.c.AuctionHouseFrame:Show()
  Same(PR.Market("Realm|Alliance").n, before.n, "nothing was written")
  -- M7.1: closed after the last record was read, while the entries are still being built: interrupted, nothing written, no result
  do
    local mk = PR.Market("Realm|Alliance")
    t.ah.records = Records(1000, 10)
    local base = t.ah.infoCalls
    Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE")
    local guard = 0
    while SC.state == "scanning" and guard < 20 do
      -- the first reading tick reads 400 of the 1000 records; go on until the last record was asked for
      if t.ah.infoCalls - base >= 1000 then break end
      t.Tick() guard = guard + 1
    end
    Same(SC.state, "scanning"); Same(SC.phase, "reading", "all records read, the entries not built yet")
    t.c.AuctionHouseFrame:Hide()
    Check(t.Tick()); Same(SC.state, "interrupted", "the build step notices the window is gone"); Same(SC.why, "closed")
    t.Advance(10); Same(SC.state, "interrupted")
    t.c.AuctionHouseFrame:Show()
    Same(PR.Market("Realm|Alliance").at, mk.at, "the saved market was not rewritten"); Same(PR.Market("Realm|Alliance").n, mk.n)
  end
  -- the same, ended by the event
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); Check(t.Tick()); t.Fire("AUCTION_HOUSE_DISABLED")
  Same(SC.state, "interrupted"); t.Advance(10); Same(SC.state, "interrupted")

  -- more updates while the listings are read are item data arriving: the read goes on, it doesn't start over or fail
  local function ToReading() local n = 0 while SC.Busy() and SC.phase ~= "reading" and n < 20 do t.Tick(); n = n + 1 end end
  t.ah.records = Records(1000, 10)
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); ToReading(); Same(SC.phase, "reading")
  for i = 1, 8 do t.Fire("REPLICATE_ITEM_LIST_UPDATE"); Same(SC.phase, "reading", "an update during the read does not stop it") end
  t.Advance(10)
  Same(SC.state, "done"); Check(SC.result.complete, "the same number of listings: a complete scan")
  Same(SC.result.updates, 9); Same(SC.result.restarts, 0)

  -- the NUMBER of listings changed during the read: start over (a few times), then keep it as a scan that is not complete
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); ToReading()
  t.ah.records[#t.ah.records + 1] = { item = 10, count = 1, buyout = 50 }   -- one more listing appeared mid-read
  t.Advance(10)   -- the read ends, sees 1001 against 1000, reads again once
  Same(SC.state, "done"); Check(SC.result.complete); Same(SC.result.restarts, 1); Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).price, 50)
  t.c.TwichUIWorkshopDB = nil   -- (an incomplete scan never replaces a complete one: that is "kept", tested below)
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); ToReading()
  local grow = 0
  local numOf = t.c.C_AuctionHouse.GetNumReplicateItems
  t.c.C_AuctionHouse.GetNumReplicateItems = function() grow = grow + 1; return numOf() + grow end   -- never holds still
  t.Advance(60)
  Same(SC.state, "done", "it never fails for this"); Check(not SC.result.complete); Check(SC.result.changed); Same(SC.result.restarts, 3)
  Check(SC.Message():find("kept changing", 1, true) and SC.Message():find("may be incomplete", 1, true), SC.Message())
  t.c.C_AuctionHouse.GetNumReplicateItems = numOf
  t.ah.outOfRange = nil   -- (the invented count above asked past the end on purpose)

  -- a steady stream of updates can't hold the read back for ever
  t.ah.records = Records(10, 10)
  Check(SC.Start(want))
  for i = 1, 30 do t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(1) end   -- one a second, longer than the 2 s quiet it asks for
  Check(SC.state == "done" or SC.phase == "reading", "after at most 10 s of waiting the listings are read")
  t.Advance(5); Same(SC.state, "done")

  -- no listings at all
  t.ah.records = {}
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(3)
  Same(SC.state, "failed"); Same(SC.why, "empty"); Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).price, 101)
end

---------------------------------------------------------------------------
-- The scan: completeness
---------------------------------------------------------------------------
do
  local t = Setup()
  local SC, PR = t.W.Scan, t.W.Prices
  local want = { [10] = true }
  -- records the game hadn't fully loaded: wait a little, read again, and if they never load the scan is saved as NOT complete
  t.ah.records = Records(5, 10); t.ah.records[2].hasAll = false
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(2.5)
  Same(SC.phase, "settling", "waiting for more item data"); Same(SC.state, "scanning")
  t.Advance(5); t.Advance(5); t.Advance(5)   -- nothing else arrives
  Same(SC.state, "done"); Check(not SC.result.complete); Same(SC.result.partialInfo, 1)
  Check(SC.Message():find("may be incomplete", 1, true))
  Same(PR.Market("Realm|Alliance").complete, false, "saved, marked not complete")
  Check(PR.Lookup(PR.Market("Realm|Alliance"), 10), "usable, but flagged")
  -- the data loads while waiting: read again, now complete
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(2.5)
  Same(SC.phase, "settling")
  t.ah.records[2].hasAll = true; t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(10)
  Same(SC.state, "done"); Check(SC.result.complete); Same(PR.Market("Realm|Alliance").complete, true, "a complete scan replaces the incomplete one")
  -- an incomplete scan never replaces a complete one
  t.ah.records[3].hasAll = false; t.ah.records[3].buyout = 1
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(30)
  Same(SC.state, "failed"); Same(SC.why, "kept"); Check(SC.Message():find("earlier complete prices were kept", 1, true))
  Same(PR.Lookup(PR.Market("Realm|Alliance"), 10).price, 101, "the complete scan stands")
  -- more items than a market holds: the scan is saved as cut, never complete
  t.ah.records = Records(3, 10)
  t.c.TwichUIWorkshopDB = nil
  local was = PR.MAX_ITEMS
  PR.MAX_ITEMS = 2
  t.ah.records[2].item = 11; t.ah.records[3].item = 12
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(3)
  PR.MAX_ITEMS = was
  Same(SC.state, "done"); Check(not SC.result.complete and SC.result.cut and SC.result.dropped == 1); Check(SC.Message():find("lists more than TwichUI keeps", 1, true), SC.Message())
  Check(PR.Market("Realm|Alliance").cut, "saved as cut")
  -- the market follows the auctioneer; an unreadable side is its own market
  t.ah.side = nil
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(3)
  Check(PR.Market("Realm|unknown") and PR.Market("Realm|unknown").complete, "an unreadable side is its own market")
  Same(PR.Market("Realm|Alliance").complete, false, "and doesn't touch the other")
  t.ah.side = "Horde"
  Check(SC.Start(want)); t.Fire("REPLICATE_ITEM_LIST_UPDATE"); t.Advance(3)
  Check(PR.Market("Realm|Horde")); Same(SC.Market(), "Realm|Horde")
  -- the cut is unconfirmed for every side
  Same(PR.CutRate(PR.Market("Realm|Horde").side), nil)
end

print("PASSED")
