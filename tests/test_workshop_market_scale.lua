-- Scale and cost of the Workshop's market data (Prices.lua batch and commit, History.lua, Market.lua), on SYNTHETIC auction houses:
-- up to the scan's own 250,000-record boundary, tens of thousands of distinct items, repeated scans over simulated days and several
-- markets. It measures CPU time (os.clock) and Lua memory (collectgarbage) of plain Lua 5.1 on this machine and PRINTS them; the limits it
-- asserts are deliberately loose, so a slow machine does not fail it but an accidental quadratic step or unbounded growth does.
-- WoW's own Lua is slower and its memory is shared with the interface: these are relative figures, not promises (docs/workshop.md).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Prices.lua", "Opportunities.lua",
    "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }
local D = 86400

local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.GetRealmName = function() return "Realm" end
for _, f in ipairs(FILES) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
local W = c.TwichUI.Workshop
local PR, MK, H = W.Prices, W.Market, W.History

local function Mem() collectgarbage() collectgarbage() return collectgarbage("count") end
local function Clock() return os.clock() end
local function Out(...) print("  " .. ("%s"):rep(select("#", ...), " "):format(...)) end

-- the size of a saved-variables file for a value, as the game writes it (one line per entry)
local function Size(v, depth)
  depth = depth or 0
  if type(v) == "string" then return #v + 2 end
  if type(v) ~= "table" then return #tostring(v) end
  local n = 4
  for k, x in pairs(v) do n = n + (type(k) == "number" and #tostring(k) + 4 or #k + 6) + Size(x, depth + 1) + 2 + depth end
  return n
end

math.randomseed(20261111)
local function Listings(records, distinct)
  -- more listings for cheap common items, one for most, like a real house
  local r = {}
  for i = 1, records do
    local item = 1 + math.floor(distinct * (math.random() ^ 2))
    local count = 1 + math.random(0, 4)
    r[i] = { item, count, count * (50 + (item * 37) % 9000 + math.random(0, 40)) }
  end
  return r
end

---------------------------------------------------------------------------
-- 1. Reading a house of 250,000 listings and 30,000 items
---------------------------------------------------------------------------
print("scale:")
local records = Listings(250000, 30000)
local base = Mem()
local batch = PR.NewBatch()
local t0, worst, slice = Clock(), 0, Clock()
for i, r in ipairs(records) do
  batch:Add(r[1], r[2], r[3], true)
  if i % 400 == 0 then
    local now = Clock()
    if now - slice > worst then worst = now - slice end
    slice = now
  end
end
local readTime = Clock() - t0
local peak = Mem() - base
t0 = Clock()
local items, n, over = batch:Items()
local itemsTime = Clock() - t0
Out(("read %d records: %.2f s (worst 400-record step %.1f ms; the game adds its own cost per record); %d distinct items; transient %.1f MB"):format(#records, readTime, worst * 1000, n, peak / 1024))
Out(("turning them into saved entries: %.2f s"):format(itemsTime))
Check(n > 20000 and not over, "tens of thousands of distinct items are kept: " .. n)
Check(n == (function() local k = 0 for _ in pairs(batch.acc) do k = k + 1 end return k end)(), "every distinct item is kept")
Check(worst < 0.25, "a step stays small: " .. worst)
batch = nil

---------------------------------------------------------------------------
-- 2. Merging into the history: steps, cost, saved size
---------------------------------------------------------------------------
local KEY = "Realm|Alliance"
local stepEver = 0
local function Commit(day, its, count, key)
  local job = assert(PR.BeginCommit(key or KEY, { realm = "Realm", side = "Alliance", at = day * D + 600, complete = true, read = 250000, used = 249000, n = count, items = its }))
  local steps, worstStep, total = 0, 0, Clock()
  repeat
    local s = Clock()
    local done = job:Step()
    local e = Clock() - s
    if e > worstStep then worstStep = e end
    if e > stepEver then stepEver = e end
    steps = steps + 1
  until done
  local tw = Clock()
  Check(job:Apply())
  return steps, worstStep, Clock() - total, Clock() - tw
end
local before = Mem()
local steps, worstStep, total, apply = Commit(100, items, n)
Out(("first commit of %d items: %d steps, worst step %.1f ms, total %.2f s, the final write %.1f ms"):format(n, steps, worstStep * 1000, total, apply * 1000))
Check(worstStep < 0.5, "a step of 1000 items: " .. worstStep)
Same(PR.Market(KEY).histItems, n)

-- repeated scans on later days: prices drift, some items come and go
local function NextDay(its)
  local out = {}
  for id, e in pairs(its) do
    if math.random() < 0.97 then
      local p, q, l, t, x = e:match("^(%d+),(%d+),(%d+),(%d+),(%d+)$")
      local np = math.max(1, math.floor(tonumber(p) * (0.9 + math.random() * 0.2)))
      out[id] = ("%d,%s,%s,%s,%s"):format(np, q, l, t, x)
    end
  end
  return out
end
local cur, days, worstDay = items, 0, 0
for day = 101, 108 do
  cur = NextDay(cur)
  local cnt = 0
  for _ in pairs(cur) do cnt = cnt + 1 end
  local _, _, tot = Commit(day, cur, cnt)
  if tot > worstDay then worstDay = tot end
  days = days + 1
end
Out(("%d more daily scans of ~%d items: worst commit %.2f s, worst single step (%d items) %.1f ms"):format(days, n, worstDay, PR.COMMIT_STEP, stepEver * 1000))
Check(stepEver < 0.5, "no step holds the interface for half a second: " .. stepEver)
Check(worstDay < 20, "a commit of tens of thousands of items takes seconds of CPU, not minutes: " .. worstDay)

local m = PR.Market(KEY)
local mem1 = Mem() - base
local sv = Size(c.TwichUIWorkshopDB)
local hist = 0
for _, s in pairs(m.hist) do hist = hist + #s end
Out(("one market, %d items, 9 scan days: Lua memory %.1f MB, saved-variables text about %.1f MB; history strings average %.0f bytes"):format(m.n, mem1 / 1024, sv / 1048576, hist / m.histItems))
Check(sv < 12 * 1048576, "one full market stays under about 12 MB of saved text: " .. sv)

-- the history stays bounded by retention however many days follow (a smaller market, so the test stays quick)
do
  local small, k = {}, 0
  for id, e in pairs(cur) do k = k + 1 if k > 3000 then break end small[id] = e end
  local LONG = "Realm|Long"
  for day = 109, 260 do
    if day % 7 == 0 or day > 250 then
      small = NextDay(small)
      local cnt = 0
      for _ in pairs(small) do cnt = cnt + 1 end
      Commit(day, small, cnt, LONG)
    end
  end
  local lm = PR.Market(LONG)
  local longest = 0
  for _, str in pairs(lm.hist) do if #str > longest then longest = #str end end
  Out(("after ~150 more days (weekly, then daily scans): longest history string %d bytes, %d items with history, %d scan days"):format(longest, lm.histItems, #lm.scanDays))
  Check(longest < 260, "a history string stays short: " .. longest)
  Check(#lm.scanDays <= H.MAX_SCAN_DAYS)
  Check(lm.histItems <= 3000, "history never outgrows what scans listed")
  c.TwichUIWorkshopDB.markets[LONG] = nil
end
m = PR.Market(KEY)

---------------------------------------------------------------------------
-- 3. Lookups
---------------------------------------------------------------------------
local ids = {}
for id in pairs(m.items) do ids[#ids + 1] = id end
local now = 260 * D + 700
t0 = Clock()
local hits = 0
for i = 1, 100000 do
  local p = MK.Price(ids[1 + (i * 7919) % #ids], { market = m, now = now })
  if p then hits = hits + 1 end
end
local priceTime = Clock() - t0
t0 = Clock()
for i = 1, 10000 do MK.Stats(ids[1 + (i * 104729) % #ids], "week", { market = m, now = now }) end
local statsTime = Clock() - t0
Out(("100,000 current-price lookups: %.2f s (%.1f us each); 10,000 week statistics: %.2f s (%.1f us each)"):format(priceTime, priceTime * 10, statsTime, statsTime * 100))
Check(hits == 100000, "every listed item answers")
Check(priceTime / 100000 < 0.0005, "a tooltip lookup costs microseconds")

---------------------------------------------------------------------------
-- 4. Several markets, and a house bigger than a market holds
---------------------------------------------------------------------------
local mem2 = Mem()
for i, side in ipairs({ "Horde", "Neutral" }) do
  local key = "Realm|" .. side
  local cnt = 0
  for _ in pairs(cur) do cnt = cnt + 1 end
  Check(PR.Commit(key, { realm = "Realm", side = side, at = (260 + i) * D, complete = true, read = 1, used = 1, n = cnt, items = cur }))
end
local mem3 = Mem()
Out(("two more markets sharing the same strings (a synthetic shortcut: real markets differ): +%.1f MB"):format((mem3 - mem2) / 1024))
local count = 0
for _ in pairs(c.TwichUIWorkshopDB.markets) do count = count + 1 end
Same(count, PR.MAX_MARKETS, "no more markets than the limit")
Check(PR.Commit("Realm|Fourth", { realm = "Realm", side = "Fourth", at = 270 * D, complete = true, read = 1, used = 1, n = 1, items = { [1] = "5,1,1,1,0" } }))
count = 0
for _ in pairs(c.TwichUIWorkshopDB.markets) do count = count + 1 end
Same(count, PR.MAX_MARKETS, "a fourth pushes the oldest out")
Same(PR.Market(KEY), nil, "the one scanned longest ago went")

local big = PR.NewBatch()
for i = 1, PR.MAX_ITEMS + 20000 do big:Add(i, 1, 1000 + i) end
t0 = Clock()
local kept, kn, cut, dropped = big:Items()
Out(("a house of %d distinct items: the %d most useful are kept in %.2f s, %d dropped"):format(PR.MAX_ITEMS + 20000, kn, Clock() - t0, dropped))
Check(cut and kn == PR.MAX_ITEMS and dropped == 20000)

print("PASSED")
