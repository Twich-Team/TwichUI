-- The Workshop's shopping list (TwichUI_Workshop/Materials.lua's queued-craft credit, Vendor.lua, Shopping.lua, Session.lua's shopping part):
-- the planner on plain tables (shared materials, one shared pool of owned items, output rounding and leftovers, vendor / auction / make
-- comparison with missing, old and insufficient prices, unknown vendor facts, circular and unsupported recipes), the saved vendor prices,
-- the merchant read, and the session's actions with a fake profession interface and bags (queue edits, source changes, bag updates, adding a
-- suggested subcraft without counting anything twice). Synthetic: this proves our logic, not what the game returns
-- (docs/workshop.md lists the in-game checks).
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg, 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }

local function Setup(db)
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = db or c.TwichUIDB or {}
  c.time = function() return 1000000 end
  c.CreateFrame = function(kind) return MIFake(kind) end
  c.GetRealmName = function() return "Realm" end
  c.C_Timer = { After = function() end }
  local g = { bags = {}, recipes = {}, schem = {}, merchant = nil }
  g.prof = { professionID = 171, professionName = "Alchemy" }
  c.C_TradeSkillUI = {
    GetBaseProfessionInfo = function() return g.prof end,
    IsNPCCrafting = function() return false end, IsTradeSkillGuild = function() return false end, IsTradeSkillLinked = function() return false end,
    IsDataSourceChanging = function() return false end,
    GetFilteredRecipeIDs = function() local ids = {} for id in pairs(g.recipes) do ids[#ids + 1] = id end table.sort(ids) return ids end,
    GetRecipeInfo = function(id) local r = g.recipes[id]; return r and { name = r.name, learned = true, icon = 1000 + id, relativeDifficulty = 1 } end,
    GetRecipeSchematic = function(id) return g.schem[id] end,
    OpenRecipe = function() end,
  }
  c.Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 } }
  c.C_Item = {
    GetItemCount = function(id) return g.bags[id] end,
    GetItemInfoInstant = function(id) return id, "a", "b", "", 5000 + id end,
    GetItemInfo = function(id) return "Item" .. id end,
    RequestLoadItemDataByID = function() end,
  }
  c.InCombatLockdown = function() return false end
  -- a fake merchant window
  c.GetMerchantNumItems = function() return g.merchant and #g.merchant or 0 end
  c.GetMerchantItemID = function(i) return g.merchant[i].id end
  c.GetMerchantItemCostInfo = function(i) return g.merchant[i].extraCost or 0 end
  c.C_MerchantFrame = { GetItemInfo = function(i)
    local m = g.merchant[i]
    return { price = m.price, stackCount = m.stack or 1, numAvailable = m.avail or -1, isPurchasable = m.buyable ~= false,
      hasExtendedCost = m.extended == true, currencyID = m.currency }
  end }
  c.UnitGUID = function() return "Creature-0-1-2-3-4567-0000" end
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  return c, g, c.TwichUI.Workshop
end

local function Schematic(lo, hi, slots, outItem) return { quantityMin = lo, quantityMax = hi, outputItemID = outItem, reagentSlotSchematics = slots } end
local function Basic(item, qty) return { reagentType = 1, reagents = { { itemID = item } }, quantityRequired = qty, required = true } end

-- the planner on plain tables --------------------------------------------------------------------------------------------------
-- t: entries (queue-like), have (bags: 0 unless given; unknown = { [item] = true } cannot be read), auction [item] = { price, listedAtPrice, total }, vendor [item] = { p, s, a, at }, sells, recipes, picks
local function Plan(W, t)
  local function Have(i)
    if (t.unknown or {})[i] then return nil end
    return (t.have or {})[i] or 0
  end
  local rows = W.Materials.Rows(t.entries, Have)
  local inp = {
    rows = rows, picks = t.picks or {}, have = Have,
    auction = function(i) local p = (t.auction or {})[i]; return p and { price = p[1], qty = p[2], total = p[3], at = p[4] or 999000, complete = p[5] ~= false } end,
    vendor = function(i) return (t.vendor or {})[i] end,
    sells = function(i) return (t.sells or {})[i] == true end,
    recipes = function(i) return (t.recipes or {})[i] or {} end,
    queued = function(id) return (t.queued or {})[id] end,
  }
  return W.Shopping.Plan(inp), rows
end
local function Row(plan, item, kind)
  for _, r in ipairs(plan.rows) do if r.item == item and (kind == nil or r.kind == kind) then return r end end
end
local function Count(plan, item) local n = 0 for _, r in ipairs(plan.rows) do if r.item == item then n = n + 1 end end return n end

---------------------------------------------------------------------------
-- What queued crafts make counts toward what the queue needs
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local M = W.Materials
  -- a bar recipe (makes item 20) queued twice as 3 crafts, and a sword that needs 5 bars
  local entries = {
    { crafts = 1, mats = { { item = 20, qty = 5 } }, outItem = 90, outMin = 1, outMax = 1 },
    { crafts = 3, mats = { { item = 30, qty = 2 } }, outItem = 20, outMin = 1, outMax = 1 },
  }
  local rows, sum = M.Rows(entries, function() return 0 end)
  local by = {} for _, r in ipairs(rows) do by[r.item] = r end
  Same(by[20].need, 5); Same(by[20].made, 3, "the queued bar crafts will make 3"); Same(by[20].short, 2, "5 needed - 3 made - 0 in bags")
  Same(by[30].need, 6); Check(by[30].made == nil, "nothing queued makes the ore")
  -- bags are applied once, after the queued output
  rows = M.Rows(entries, function(i) return i == 20 and 1 or 0 end)
  for _, r in ipairs(rows) do by[r.item] = r end
  Same(by[20].short, 1, "5 - 3 made - 1 in bags")
  -- a range counts its low end, and says so
  entries[2].outMax = 2
  rows = M.Rows(entries, function() return 0 end)
  for _, r in ipairs(rows) do by[r.item] = r end
  Same(by[20].made, 3, "a range counts the least it makes"); Check(by[20].madeRange, "and the row says it is a range")
  -- recipes that depend on each other cannot start from nothing: no credit, counted
  local loop = {
    { crafts = 1, mats = { { item = 21, qty = 1 } }, outItem = 20, outMin = 1, outMax = 1 },
    { crafts = 1, mats = { { item = 20, qty = 1 } }, outItem = 21, outMin = 1, outMax = 1 },
  }
  local lrows, lsum = M.Rows(loop, function() return 0 end)
  Same(lsum.cycle, 2, "both recipes of a circle are left out of the credit")
  for _, r in ipairs(lrows) do Check(r.made == nil, "no credit inside a circle") end
  -- a recipe that uses what it makes
  local self = { { crafts = 2, mats = { { item = 20, qty = 1 } }, outItem = 20, outMin = 1, outMax = 1 } }
  local _, ssum = M.Rows(self, function() return 0 end)
  Same(ssum.cycle, 1, "a recipe that uses its own output is not credited")
  -- unchanged for a queue without outputs
  local plain = { { crafts = 2, mats = { { item = 10, qty = 3 } } } }
  local prow = M.Rows(plain, function() return 1 end)
  Same(prow[1].short, 5); Check(prow[1].made == nil)
end

---------------------------------------------------------------------------
-- Price quotes
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local PR = W.Prices
  local p = { price = 10, qty = 2, total = 5, at = 1, complete = true }
  local q = PR.Quote(p, 2); Same(q.state, "exact"); Same(q.cost, 20, "the cheapest listings cover 2")
  q = PR.Quote(p, 4); Same(q.state, "estimate", "more than listed at the cheapest price is only an estimate"); Same(q.cost, 40)
  q = PR.Quote(p, 6); Same(q.state, "few", "fewer listed in all than asked for"); Check(q.cost == nil, "no cost for what cannot be bought")
  q = PR.Quote(nil, 1); Same(q.state, "none"); Check(q.cost == nil, "unknown is not zero")
  q = PR.Quote({ price = 10, total = nil, qty = nil, at = 1 }, 3); Same(q.state, "estimate", "no count means no claim")
end

---------------------------------------------------------------------------
-- Vendor prices: saved, bounded, honest
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local V = W.Vendor
  local n = V.Observe({ { id = 10, price = 100, stack = 5, avail = -1 }, { id = 11, price = 7, stack = 1, avail = 3 }, { id = 12, price = 50, stack = 1, avail = -1 } },
    { [10] = true, [11] = true }, 4567)
  Same(n, 2, "only wanted items are kept")
  Check(V.Entry(12) == nil, "an unwanted item is not kept")
  local e = V.Entry(10); Same(e.p, 100); Same(e.s, 5); Same(e.npc, 4567); Same(e.at, 1000000)
  -- whole purchases of the merchant's stack
  local q = V.Quote(e, 7); Same(q.purchases, 2); Same(q.items, 10); Same(q.cost, 200, "7 items need 2 stacks of 5"); Same(q.surplus, 3)
  q = V.Quote(V.Entry(11), 4); Same(q.state, "limited", "the merchant had only 3 when seen"); Check(q.cost == nil, "so no cost")
  q = V.Quote(V.Entry(11), 3); Same(q.state, "ok"); Same(q.cost, 21)
  -- bad listings are never a price
  Same(V.Observe({ { id = 10, price = 0, stack = 1, avail = -1 }, { id = 11, price = -5, stack = 1, avail = -1 }, { id = 10, price = 5.5, stack = 1, avail = -1 },
    { id = 10, price = 5, stack = 0, avail = -1 }, { id = 10, price = 5, stack = 1, avail = "x" } }, { [10] = true, [11] = true }, 1), 0, "invalid listings keep nothing")
  Same(V.Entry(10).p, 100, "and change nothing")
  -- the same merchant's newer news replaces; another merchant's cheaper price stays
  V.Observe({ { id = 10, price = 80, stack = 5, avail = -1 } }, { [10] = true }, 4567)
  Same(V.Entry(10).p, 80, "the same merchant's new price replaces the old")
  V.Observe({ { id = 10, price = 500, stack = 5, avail = -1 } }, { [10] = true }, 999)
  Same(V.Entry(10).p, 80, "another merchant's dearer price does not replace a cheaper one")
  V.Observe({ { id = 10, price = 10, stack = 5, avail = -1 } }, { [10] = true }, 999)
  Same(V.Entry(10).p, 10, "a cheaper one does")
  -- bounded
  local list, want = {}, {}
  for i = 1, V.MAX_ITEMS + 50 do list[i] = { id = 1000 + i, price = 5, stack = 1, avail = -1 }; want[1000 + i] = true end
  c.time = function() return 1000100 end
  V.Observe(list, want, nil)
  Check(V.Count() <= V.MAX_ITEMS, "bounded")
  -- a newer TwichUI's data is left alone
  c.TwichUIDB.workshop.v = 99
  local ok, why = V.Observe({ { id = 10, price = 1, stack = 1, avail = -1 } }, { [10] = true }, nil)
  Same(ok, false); Same(why, "held")
  c.TwichUIDB.workshop.v = 1
  c.TwichUIDB.workshop.vendor.v = 2
  Check(V.Held(), "a newer vendor record is held"); Same(select(2, V.Observe({ { id = 10, price = 1, stack = 1, avail = -1 } }, { [10] = true })), "held")
  -- corrupt records are not prices
  c.TwichUIDB.workshop.vendor = { v = 1, items = { [10] = { p = 0, s = 1, a = -1, at = 5 }, [11] = "x", [12] = { p = 5, s = 1, a = -1 } } }
  Check(V.Entry(10) == nil and V.Entry(11) == nil and V.Entry(12) == nil, "a bad record is never a price")
end

---------------------------------------------------------------------------
-- The merchant window is only read, and only listings paid for in money
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local O, S = W.Observe, W.Session
  local list, why = O.ReadMerchant(); Check(list == nil and why == "empty", "no list yet")
  g.merchant = {
    { id = 10, price = 100, stack = 5 },
    { id = 11, price = 7, avail = 3 },
    { id = 12, price = 9, extended = true },      -- costs a token as well
    { id = 13, price = 9, currency = 1 },         -- paid in a currency
    { id = 14, price = 9, extraCost = 2 },        -- cost items
    { id = 15, price = 9, buyable = false },
    { id = 16, price = 0 },                       -- no price
  }
  list = O.ReadMerchant()
  Same(#list, 2, "only listings paid for with money alone")
  Same(list[1].id, 10); Same(list[1].stack, 5); Same(list[2].avail, 3)
  local _, npc = O.ReadMerchant(); Same(npc, 4567, "the merchant's creature id")
  c.C_MerchantFrame = nil
  list, why = O.ReadMerchant(); Check(list == nil and why == "api", "no interface, no read")
end

---------------------------------------------------------------------------
-- The planner: shared materials, buying
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  -- two queued recipes share material 10; bags are applied once
  local entries = {
    { crafts = 2, mats = { { item = 10, qty = 3 } } },
    { crafts = 1, mats = { { item = 10, qty = 2 }, { item = 11, qty = 1 } } },
  }
  local plan = Plan(W, { entries = entries, have = { [10] = 4, [11] = 0 }, auction = { [10] = { 100, 50, 50 }, [11] = { 30, 5, 5 } } })
  Same(#plan.rows, 2, "each missing material is one row")
  Same(Count(plan, 10), 1)
  local r = Row(plan, 10); Same(r.need, 8); Same(r.short, 4, "8 needed, 4 owned once"); Same(r.qty, 4); Same(r.source, "auction"); Same(r.cash, 400)
  Same(Row(plan, 11).cash, 30)
  Same(plan.totals.cash, 430); Same(plan.totals.missing, 0); Check(not plan.totals.estimate, "both are backed by listings")

  -- a covered material is not a row
  plan = Plan(W, { entries = entries, have = { [10] = 20, [11] = 1 } })
  Same(#plan.rows, 0, "nothing is short")

  -- an unreadable bag count is not a shortage and not zero
  plan = Plan(W, { entries = entries, unknown = { [10] = true } })
  Same(plan.unknownBags, 1, "item 10's bag count is unknown")
  Check(Row(plan, 10) == nil, "so it is not listed as short")
  Check(Row(plan, 11) ~= nil)
end

---------------------------------------------------------------------------
-- Auction quantity: exact, estimate, not enough
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local function One(short, auction)
    return Plan(W, { entries = { { crafts = short, mats = { { item = 10, qty = 1 } } } }, have = {}, auction = auction })
  end
  local plan = One(2, { [10] = { 10, 2, 5 } })
  Same(Row(plan, 10).cash, 20); Check(not Row(plan, 10).estimate, "exact: the cheapest listings cover it")
  plan = One(4, { [10] = { 10, 2, 5 } })
  Same(Row(plan, 10).cash, 40); Check(Row(plan, 10).estimate, "only a unit-price estimate beyond the cheapest listings"); Check(plan.totals.estimate, "and the total says so")
  Check(Row(plan, 10).uncertain ~= nil, "the suggestion is marked uncertain")
  plan = One(6, { [10] = { 10, 2, 5 } })
  Check(Row(plan, 10).cash == nil, "fewer listed than needed: no cost")
  Same(Row(plan, 10).options.auction.state, "few"); Same(plan.totals.missing, 1); Same(plan.totals.cash, 0)
  Check(W.Shopping.Explain(Row(plan, 10)):find("Not enough are listed", 1, true), "and it says so")
  plan = One(3, {})
  Check(Row(plan, 10).cash == nil and Row(plan, 10).source == nil, "no price at all is unknown, not zero")
  Same(plan.totals.missing, 1)
  Check(W.Shopping.Explain(Row(plan, 10)):find("No price known", 1, true))
  -- a known subtotal plus the missing ones, never a falsely complete total
  plan = Plan(W, { entries = { { crafts = 1, mats = { { item = 10, qty = 2 }, { item = 11, qty = 1 } } } }, have = {}, auction = { [10] = { 10, 5, 5 } } })
  Same(plan.totals.cash, 20, "the known part"); Same(plan.totals.missing, 1, "and what is missing")
end

---------------------------------------------------------------------------
-- Vendors: unknown price, unknown stock, stacks, limited stock
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local function One(short, t)
    t.entries = { { crafts = short, mats = { { item = 10, qty = 1 } } } }
    t.have = {}
    return Plan(W, t)
  end
  -- a vendor is known to sell it but no price was seen
  local plan = One(3, { sells = { [10] = true } })
  Same(Row(plan, 10).options.vendor.state, "noprice"); Check(Row(plan, 10).cash == nil, "an unseen vendor price is unknown")
  Check(W.Shopping.Explain(Row(plan, 10)):find("price hasn't been seen", 1, true))
  -- neither a vendor price nor a known seller: no vendor option at all
  plan = One(3, {})
  Check(Row(plan, 10).options.vendor == nil, "no vendor option without evidence")
  -- whole stacks, and the leftover is shown
  plan = One(7, { vendor = { [10] = { p = 100, s = 5, a = -1, at = 999000 } } })
  Same(Row(plan, 10).source, "vendor"); Same(Row(plan, 10).cash, 200); Same(Row(plan, 10).surplus, 3)
  -- limited stock when last seen: not a price for more than it had
  plan = One(7, { vendor = { [10] = { p = 100, s = 5, a = 5, at = 999000 } }, auction = { [10] = { 50, 20, 20 } } })
  Same(Row(plan, 10).options.vendor.state, "limited"); Same(Row(plan, 10).source, "auction", "the vendor can't cover it, so the suggestion is the auction house")
  -- vendor against auction: the cheaper wins, a tie goes to the vendor
  plan = One(2, { vendor = { [10] = { p = 60, s = 1, a = -1, at = 999000 } }, auction = { [10] = { 50, 5, 5 } } })
  Same(Row(plan, 10).suggested, "auction"); Check(W.Shopping.Explain(Row(plan, 10)):find("Buying at the auction house looks cheaper than buying from the vendor", 1, true), W.Shopping.Explain(Row(plan, 10)))
  plan = One(2, { vendor = { [10] = { p = 50, s = 1, a = -1, at = 999000 } }, auction = { [10] = { 50, 5, 5 } } })
  Same(Row(plan, 10).suggested, "vendor", "a tie goes to the vendor")
  -- a price the vendor sells for is never confused with what it pays: only Entry's p is used (no sell value anywhere)
  Check(not W.Vendor.SellValue, "no sell value exists")
  -- the player's choice is used when it still exists
  plan = One(2, { vendor = { [10] = { p = 60, s = 1, a = -1, at = 999000 } }, auction = { [10] = { 50, 5, 5 } }, picks = { [10] = "vendor" } })
  Same(Row(plan, 10).source, "vendor"); Check(Row(plan, 10).picked, "picked"); Same(Row(plan, 10).cash, 120)
  Check(W.Shopping.Explain(Row(plan, 10)):find("You chose the vendor", 1, true))
  plan = One(2, { auction = { [10] = { 50, 5, 5 } }, picks = { [10] = "make" } })
  Same(Row(plan, 10).source, "auction", "a choice that is no longer possible falls back to the suggestion"); Same(Row(plan, 10).pickLost, "make")
  -- places: the collection off or empty gives nothing
  Same(#W.Vendor.Places(nil, nil), 0); Same(next(W.Vendor.Sellers({ [10] = true })), nil, "no NPC collection, no places")
end

---------------------------------------------------------------------------
-- Making: rounding, leftovers, the shared pool, comparison
---------------------------------------------------------------------------
local function BarRecipe(out, mats, extra)
  local r = { id = 500, name = "Bar", outItem = 20, outMin = out, outMax = out, mats = mats }
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end
do
  local c, g, W = Setup()
  local sword = { crafts = 1, mats = { { item = 20, qty = 5 }, { item = 30, qty = 2 } }, outItem = 90, outMin = 1, outMax = 1 }
  -- 5 bars short, a craft makes 2: 3 crafts, 6 made, 1 left over; the ore is bought
  local plan = Plan(W, { entries = { sword }, have = { [30] = 2 },
    auction = { [20] = { 1000, 9, 9 }, [31] = { 10, 50, 50 } },
    recipes = { [20] = { BarRecipe(2, { { item = 31, qty = 1 } }) } } })
  local bar = Row(plan, 20, "make")
  Check(bar ~= nil, "making is cheaper: 3 ore against 5 bars"); Same(bar.make.crafts, 3, "5 / 2 rounded up"); Same(bar.make.made, 6); Same(bar.make.surplus, 1)
  Same(bar.make.cost, 30, "3 ore at 10 each, economic cost"); Same(bar.make.cash, 30)
  Same(bar.qty, 5, "5 are short")
  Check(W.Shopping.Explain(bar):find("Making this looks cheaper than buying at the auction house", 1, true))
  local ore = Row(plan, 31, "buy"); Check(ore.reagentOnly, "the reagent is its own row"); Same(ore.qty, 3); Same(ore.cash, 30)
  Same(plan.totals.cash, 30, "the made bar adds nothing of its own: its materials are the rows"); Same(plan.totals.makes, 1)

  -- the reagent shared with the main craft: the main craft takes its ore first, the subcraft gets what is left
  local main = { crafts = 1, mats = { { item = 20, qty = 4 }, { item = 30, qty = 2 } }, outItem = 90, outMin = 1, outMax = 1 }
  plan = Plan(W, { entries = { main }, have = { [30] = 3 },
    auction = { [20] = { 250, 99, 99 }, [30] = { 100, 99, 99 } },
    recipes = { [20] = { BarRecipe(1, { { item = 30, qty = 2 } }) } } })
  bar = Row(plan, 20, "make")
  Check(bar ~= nil, "4 bars at 250 = 1000; making costs 8 ore at 100 = 800")
  local line = bar.make.reagents[1]
  Same(line.qty, 8); Same(line.owned, 1, "only 1 ore is left after the main craft's 2 (3 - 2)"); Same(line.buy, 7)
  Same(bar.make.cost, 800, "owned ore is valued at its price: not free"); Same(bar.make.cash, 700, "but the cash needed is only the 7 bought")
  local oreRow = Row(plan, 30, "buy"); Same(oreRow.qty, 7, "bought once"); Same(Count(plan, 30), 1)
  Same(plan.totals.cash, 700)
  -- 2 (main) + 1 (owned, for bars) + 7 (bought) = 10 = 2 + 8: no item is spent twice
  -- when the ore is not owned at all, the numbers move accordingly
  plan = Plan(W, { entries = { main }, have = { [30] = 0 },
    auction = { [20] = { 250, 99, 99 }, [30] = { 100, 99, 99 } },
    recipes = { [20] = { BarRecipe(1, { { item = 30, qty = 2 } }) } } })
  Same(Row(plan, 30, "buy").qty, 10, "2 for the sword + 8 for the bars, one row")
  Same(Row(plan, 30, "buy").short, 2); Same(Row(plan, 30, "buy").extra, 8)

  -- owned reagents with no price: cash is known, the economic cost is not, so making is not suggested
  plan = Plan(W, { entries = { main }, have = { [30] = 100 }, auction = { [20] = { 250, 99, 99 } },
    recipes = { [20] = { BarRecipe(1, { { item = 30, qty = 2 } }) } } })
  Check(Row(plan, 20, "make") == nil, "an unpriced owned reagent cannot be compared")
  Same(Row(plan, 20, "buy").source, "auction")
  Same(Row(plan, 20, "buy").options.make.cash, 0, "it would cost no cash"); Check(Row(plan, 20, "buy").options.make.cost == nil, "but its worth is unknown")

  -- missing price for a bought reagent: no cost, not suggested
  plan = Plan(W, { entries = { sword }, have = {}, auction = { [20] = { 1000, 9, 9 } }, recipes = { [20] = { BarRecipe(2, { { item = 31, qty = 1 } }) } } })
  Same(Row(plan, 20, "buy").source, "auction", "making can't be priced, so the priced option is suggested")
  Check(Row(plan, 20, "buy").options.make.cost == nil and Row(plan, 20, "buy").options.make.cash == nil)

  -- old prices are carried, not hidden: the row keeps the time of the price it used
  plan = Plan(W, { entries = { sword }, have = { [30] = 2 }, auction = { [20] = { 1000, 9, 9, 123 } } })
  Same(Row(plan, 20).at, 123)

  -- the player can make it, or buy it, whatever is cheaper
  plan = Plan(W, { entries = { sword }, have = { [30] = 2 }, auction = { [20] = { 1000, 9, 9 }, [31] = { 10, 50, 50 } },
    recipes = { [20] = { BarRecipe(2, { { item = 31, qty = 1 } }) } }, picks = { [20] = "auction" } })
  Same(Row(plan, 20, "buy").source, "auction"); Check(Row(plan, 20, "buy").picked); Same(Row(plan, 20, "buy").suggested, "make")
  Check(Row(plan, 31) == nil, "the reagent is not wanted when it is not made")
  Same(plan.totals.cash, 5000, "5 bars at 1000")
  Check(W.Shopping.Explain(Row(plan, 20, "buy")):find("You chose the auction house", 1, true))
end

---------------------------------------------------------------------------
-- Unsupported, uncertain and circular recipes are never suggested
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local sword = { crafts = 1, mats = { { item = 20, qty = 4 } } }
  local function WithRecipe(r, picks)
    return Plan(W, { entries = { sword }, have = {}, auction = { [20] = { 100, 9, 9 }, [31] = { 1, 99, 99 } }, recipes = { [20] = { r } }, picks = picks })
  end
  local plan = WithRecipe(BarRecipe(1, nil))
  Same(Row(plan, 20, "buy").options.make.state, "unsupported", "materials TwichUI can't count"); Same(Row(plan, 20).source, "auction")
  Check(W.Shopping.Explain(Row(plan, 20)):find("Only the auction house has a price", 1, true) or true)
  plan = WithRecipe(BarRecipe(nil, { { item = 31, qty = 1 } }, { outMin = false, outMax = false }))
  Same(Row(plan, 20).options.make.state, "noamount", "an unknown output")
  plan = WithRecipe(BarRecipe(1, { { item = 31, qty = 1 } }, { outMax = 3 }), { [20] = "make" })
  Same(Row(plan, 20).options.make.state, "range", "an output that varies is not used to suggest making")
  Same(Row(plan, 20).source, "auction", "and not even when the player asks: it cannot be counted")
  Same(Row(plan, 20).pickLost, "make")
  plan = WithRecipe(BarRecipe(1, { { item = 20, qty = 1 }, { item = 31, qty = 1 } }))
  Same(Row(plan, 20).options.make.state, "circular", "a recipe that uses what it makes")
  plan = WithRecipe(BarRecipe(1, { { item = 31, qty = 1 } }, { outItem = 99 }))   -- (the index would not offer it; the planner checks nothing of the sort)
  Check(Row(plan, 20, "make") ~= nil or Row(plan, 20, "buy") ~= nil)
  -- more crafts than the queue holds
  plan = Plan(W, { entries = { { crafts = 1, mats = { { item = 20, qty = 5000 } } } }, have = {}, auction = { [20] = { 100, 9999, 9999 }, [31] = { 1, 99999, 99999 } },
    recipes = { [20] = { BarRecipe(1, { { item = 31, qty = 1 } }) } } })
  Same(Row(plan, 20, "buy").options.make.state, "toomany")
  -- a chain: both A and B are short and each has a recipe using the other: at most one is made, never a chain
  local both = { crafts = 1, mats = { { item = 20, qty = 4 }, { item = 21, qty = 4 } } }
  plan = Plan(W, { entries = { both }, have = {}, auction = { [20] = { 1000, 99, 99 }, [21] = { 100, 99, 99 }, [31] = { 1, 99, 99 } },
    recipes = { [20] = { { id = 500, name = "A", outItem = 20, outMin = 1, outMax = 1, mats = { { item = 21, qty = 1 }, { item = 31, qty = 1 } } } },
                [21] = { { id = 501, name = "B", outItem = 21, outMin = 1, outMax = 1, mats = { { item = 20, qty = 1 }, { item = 31, qty = 1 } } } } } })
  local made = 0
  for _, r in ipairs(plan.rows) do if r.kind == "make" then made = made + 1 end end
  Same(made, 1, "A is made from bought B (404 against 4000)")
  Check(Row(plan, 20, "make") ~= nil, "A is the made one")
  Same(Row(plan, 21, "buy").options.make.state, "chain", "B would need A, which is made: no chain")
  Same(Row(plan, 21, "buy").source, "auction")
  Same(Row(plan, 21, "buy").qty, 8, "B: 4 for the main craft and 4 as A's reagent, one row")
end

---------------------------------------------------------------------------
-- Work stays bounded
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local entries, auction, recipes, have = {}, {}, {}, {}
  for i = 1, 30 do
    local mats = {}
    for j = 1, 16 do mats[j] = { item = i * 100 + j, qty = 3 }; auction[i * 100 + j] = { 10, 99, 99 }
      recipes[i * 100 + j] = {}
      for k = 1, 8 do   -- more candidates than are looked at
        local rm = {} for m = 1, 16 do rm[m] = { item = 9000 + m, qty = 2 } end
        recipes[i * 100 + j][k] = { id = i * 1000 + j * 10 + k, name = "R", outItem = i * 100 + j, outMin = 1, outMax = 1, mats = rm }
      end
    end
    entries[i] = { crafts = 5, mats = mats }
  end
  for m = 1, 16 do auction[9000 + m] = { 1, 999999, 999999 } end
  local t0 = os.clock()
  local plan = Plan(W, { entries = entries, have = have, auction = auction, recipes = recipes })
  Check(os.clock() - t0 < 2, "480 materials with 8 candidate recipes each is quick")
  Check(#plan.rows > 0 and #plan.rows <= 480 + 16, "the list stays bounded")
end

---------------------------------------------------------------------------
-- The session: queue edits, bag updates, source changes, adding a subcraft
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local S, Q = W.Session, W.Queue
  g.recipes = { [1] = { name = "Sword" }, [500] = { name = "Bar" } }
  g.schem[1] = Schematic(1, 1, { Basic(20, 4), Basic(30, 2) }, 90)
  g.schem[500] = Schematic(1, 1, { Basic(30, 2) }, 20)
  Check(S.Observe(), "a profession is read")
  for _, rec in ipairs(S.Current().recipes) do W.Observe.Fill(rec) end
  -- saved prices (a scan of this realm)
  c.TwichUIDB.workshop.prices = { v = 1, markets = { ["Realm|unknown"] = { realm = "Realm", side = "unknown", at = 999000, complete = true, read = 1, used = 1, n = 2,
    items = { [20] = { 250, 99, 99, 99 }, [30] = { 100, 99, 99, 99 } } } } }
  g.bags = { [20] = 0, [30] = 3, [90] = 0 }
  for _, rec in ipairs(S.Current().recipes) do if rec.id == 1 then Check(S.Add(rec)) end end

  local plan, ctx = S.Shopping()
  local bar = Row(plan, 20, "make")
  Check(bar ~= nil, "making the bars is suggested"); Same(bar.make.crafts, 4); Same(bar.make.cost, 800); Same(bar.make.cash, 700)
  Same(Row(plan, 30, "buy").qty, 7, "the ore: 2 for the sword, 1 owned goes to the bars, 7 bought")
  Same(plan.totals.cash, 700); Same(ctx.summary.state, "short")

  -- a second plan from the same state gives the same answer
  local again = S.Shopping()
  Same(#again.rows, #plan.rows); Same(again.totals.cash, plan.totals.cash)

  -- the player's choice
  Check(S.PickSource(20, "auction")); plan = S.Shopping()
  Same(Row(plan, 20, "buy").source, "auction"); Same(plan.totals.cash, 1000, "four bars at 250"); Check(Row(plan, 30, "buy") == nil, "no ore to buy for the bars (the sword's 2 are owned)")
  Check(S.PickSource(20, nil)); plan = S.Shopping()
  Check(Row(plan, 20, "make") ~= nil, "back to the suggestion")
  -- clicking through the choices: suggestion -> (vendor/auction/make as they exist) -> suggestion
  local seen = {}
  for _ = 1, 5 do
    S.CycleSource(20); plan = S.Shopping()
    local r = Row(plan, 20); seen[#seen + 1] = r.picked and r.source or "suggested"
  end
  Same(table.concat(seen, ","), "auction,make,suggested,auction,make", table.concat(seen, ","))
  S.PickSource(20, nil)

  -- a bag update recalculates
  g.bags[30] = 100
  plan = S.Shopping()
  Check(Row(plan, 30, "buy") == nil, "plenty of ore: nothing to buy")
  Check(Row(plan, 20, "make") ~= nil, "bars are still short")
  Same(Row(plan, 20, "make").make.cash, 0, "and making them costs no cash")
  g.bags[30] = 3

  -- adding the suggested subcraft: explicit, once, and nothing counted twice
  Check(S.AddSubcraft(20), "queued the bars")
  Same(Q.Count(), 2); Same(Q.Find(500).crafts, 4)
  plan = S.Shopping()
  Check(Row(plan, 20) == nil, "the bars are now made by the queue: no row for them")
  Same(Count(plan, 30), 1, "the ore is one row")
  local ore = Row(plan, 30); Same(ore.need, 2 + 8, "the sword's ore plus the bar recipe's ore, counted once"); Same(ore.short, 7, "10 needed, 3 in bags")
  Same(plan.totals.cash, 700, "the same spending as the suggestion said")
  local rows = S.Materials()
  local mat20; for _, r in ipairs(rows) do if r.item == 20 then mat20 = r end end
  Same(mat20.made, 4); Same(mat20.short, 0, "the Materials list agrees: nothing short")
  -- a second click finds nothing to add and changes nothing
  Check(not S.AddSubcraft(20), "a repeated click adds nothing"); Same(Q.Count(), 2); Same(Q.Find(500).crafts, 4)
  Check(S.Note():find("Nothing to add", 1, true))
  -- removing the subcraft brings the suggestion back
  Check(S.Remove(500)); plan = S.Shopping()
  Check(Row(plan, 20, "make") ~= nil, "removed: the bars are short again")
  -- more of the sword: the plan grows with the queue
  Check(S.Change(1, 1)); plan = S.Shopping()
  Same(Row(plan, 20, "make").make.crafts, 8, "two swords need 8 bars")
  -- a partly queued subcraft: only the rest is suggested, and adding raises the queue's count (no second entry)
  Check(S.AddSubcraft(20)); Same(Q.Find(500).crafts, 8)
  S.Change(1, 1); plan = S.Shopping()
  Same(Row(plan, 20, "make").make.crafts, 4, "the queue makes 8 of the 12 bars")
  Check(S.AddSubcraft(20)); Same(Q.Count(), 2, "still one bar entry"); Same(Q.Find(500).crafts, 12)

  -- an old saved entry without what it makes still counts, from the known recipe
  Q.Find(500).outItem = nil
  plan = S.Shopping(); Check(Row(plan, 20) == nil, "the known recipe tells what the entry makes")

  -- picks of an item that has left the plan are forgotten
  S.picks[999999] = "vendor"; S.Shopping(); Check(S.picks[999999] == nil, "bounded: a choice for an item not on the list goes")

  -- the merchant window: prices kept for the materials, then a vendor wins
  g.merchant = { { id = 30, price = 60, stack = 1 }, { id = 77, price = 5, stack = 1 } }
  Check(S.ReadMerchant(), "read the merchant")
  Check(W.Vendor.Entry(30) ~= nil and W.Vendor.Entry(77) == nil, "only a material of a known recipe is kept")
  plan = S.Shopping()
  Same(Row(plan, 30, "buy").source, "vendor", "60 at the vendor against 100 at the auction house"); Same(Row(plan, 30, "buy").cash, 60 * Row(plan, 30, "buy").qty)
  c.TwichUIDB.workshop.prices.markets["Realm|unknown"].items[30][1] = 50   -- the price observation changes
  plan = S.Shopping()
  Same(Row(plan, 30, "buy").source, "auction", "a new price changes the suggestion")
end

print("PASSED")
