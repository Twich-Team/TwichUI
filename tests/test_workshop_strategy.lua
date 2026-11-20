-- The multilevel strategy in the windows (P2: TwichUI_Workshop/Strategy.lua, Session.lua's strategy part, Queue.AddBatch)
--   A. the words: status ("Best verified plan" / "Best plan found"), savings ("Savings" only when certain), ranges ("at least"), counts
--   B. the shopping list from the multilevel plan: the same chain as test_workshop_shopping's session part, the same figures, kept apart from the
--      one-level planner (which stays, as the fallback, and is never shown as the multilevel plan)
--   C. source choices, the plan's reasons and what the planner says it would suggest
--   D. cooperative jobs: planning in steps, cancelling when an input changes, stale results never shown for another key, window close
--   E. one recipe's strategy (Opportunities) and the confirmed batch (preview without a change, apply, nothing counted twice, a changed plan refused)
--   F. Queue.AddBatch: all or nothing (capacity, limits, duplicates, an unsaved queue, a queue held by a newer version)
-- Synthetic data only: this proves our logic, not what the game returns.
dofile(TESTS .. "mi_mock.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Dist.lua", "History2.lua",
  "Prices.lua", "Opportunities.lua", "Vendor.lua", "Shopping.lua", "CraftPlanner.lua", "Strategy.lua", "Scan.lua", "Market.lua", "Valuation.lua", "Fees.lua", "Estimate.lua", "Session.lua" }

local function Setup(db)
  local c = MIClient("Rich", { db = { modules = {} } })
  c.TwichUIDB = db or c.TwichUIDB or {}
  c.time = function() return 1000000 end
  c.CreateFrame = function(kind) return MIFake(kind) end
  c.GetRealmName = function() return "Realm" end
  c.C_Timer = { After = function() end }
  local g = { bags = {}, recipes = {}, schem = {} }
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
  c.UnitGUID = function() return "Creature-0-1-2-3-4567-0000" end
  for _, f in ipairs(FILES) do
    local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
  end
  return c, g, c.TwichUI.Workshop
end
local function Schematic(lo, hi, slots, outItem) return { quantityMin = lo, quantityMax = hi, outputItemID = outItem, reagentSlotSchematics = slots } end
local function Basic(item, qty) return { reagentType = 1, reagents = { { itemID = item } }, quantityRequired = qty, required = true } end
local function Row(plan, item, kind)
  for _, r in ipairs(plan.rows) do if r.item == item and (kind == nil or r.kind == kind) then return r end end
end
local function Money(n) return n .. "c" end

-- the world of test_workshop_shopping's session part: a Sword (recipe 1, makes item 90) needs 4 Bars (item 20) and 2 Ore (item 30); a Bar
-- (recipe 500) is made from 2 Ore. The auction house: Bar 250, Ore 100. Three Ore in the bags.
local function World()
  local c, g, W = Setup()
  g.recipes = { [1] = { name = "Sword" }, [500] = { name = "Bar" } }
  g.schem[1] = Schematic(1, 1, { Basic(20, 4), Basic(30, 2) }, 90)
  g.schem[500] = Schematic(1, 1, { Basic(30, 2) }, 20)
  Check(W.Session.Observe(), "a profession is read")
  for _, rec in ipairs(W.Session.Current().recipes) do W.Observe.Fill(rec) end
  c.TwichUIDB.workshop.prices = { v = 1, markets = { ["Realm|unknown"] = { realm = "Realm", side = "unknown", at = 999000, complete = true, read = 1, used = 1, n = 2,
    items = { [20] = { 250, 99, 99, 99 }, [30] = { 100, 99, 99, 99 } } } } }
  g.bags = { [20] = 0, [30] = 3, [90] = 0 }
  return c, g, W
end
local function Rec(W, id) for _, r in ipairs(W.Session.Current().recipes) do if r.id == id then return r end end end

---------------------------------------------------------------------------
-- A. The words
---------------------------------------------------------------------------
do
  local c, g, W = Setup()
  local St = W.Strategy
  Same(St.RangeText({ low = 5, high = 5 }, Money), "5c")
  Same(St.RangeText({ low = 5, high = 9 }, Money), "5c to 9c")
  Same(St.RangeText({ low = 5 }, Money), "at least 5c", "an open upper end is only a lower bound")
  Same(St.RangeText({ low = 5, high = 5 }, Money, true), "at least 5c", "a missing price makes even the figure a lower bound")
  Check(St.RangeText(nil, Money) == nil and St.RangeText({}, Money) == nil, "no figure, no words")
  local text, tone = St.Status({ status = "complete", proven = true }); Same(text, "Best verified plan"); Same(tone, "good")
  Same((St.Status({ status = "complete", proven = false, exhaustive = true })), "Best plan found", "not proven: never 'verified'")
  Same((St.Status({ status = "complete", proven = false })), "Best plan found")
  Check((St.Status({ status = "incomplete" })):find("Partial", 1, true), "missing prices are said")
  Check((St.Status({ status = "unavailable" })):find("No plan", 1, true))
  local label, t = St.Savings({ savings = { confident = true, low = 135, lowerBounds = 150 } }, Money); Same(label, "Savings"); Same(t, "at least 135c")
  label, t = St.Savings({ savings = { confident = false, lowerBounds = 150 } }, Money); Same(label, "Potential savings"); Same(t, "about 150c")
  local why
  label, t, _, why = St.Savings({ savings = { confident = false, lowerBounds = 0 } }, Money); Same(t, "No saving"); Same(why, St.NO_SAVING, "no improvement is said as such")
  label, t, _, why = St.Savings({}, Money); Same(label, "Potential savings"); Same(t, "Unknown", "unknown prices: no figure invented")
  Same(why, St.NO_COMPARE, "an unknown comparison is not called 'no saving'")
  -- P2.1: one planning figure; a figure that is not exact always says so, and the range stays in the tooltip
  local text, tip = St.CostText({ low = 5, high = 5 }, Money, false, false); Same(text, "5c"); Same(tip, nil, "an exact figure has no range")
  text, tip = St.CostText({ low = 5, high = 9 }, Money, false, false); Same(text, "from 5c", "a lower bound is never shown as the total")
  Check(tip:find("5c", 1, true) and tip:find("9c", 1, true), "the range is in the tooltip: " .. tip)
  text = St.CostText({ low = 5, high = 9 }, Money, false, true); Same(text, "5c to 9c", "Detailed shows the range inline")
  text, tip = St.CostText({ low = 5 }, Money, false, false); Same(text, "at least 5c", "an open upper end: no upper bound is invented"); Check(tip and not tip:find("to ", 1, true))
  text = St.CostText({ low = 5, high = 9 }, Money, true, false); Same(text, "at least 5c", "a missing price makes the figure a lower bound")
  Same(St.CostText(nil, Money), nil); Same(St.CostText({}, Money), nil, "no figure, no text")
  Same(St.Headline({ crafts = {}, items = { { source = "auction" }, { source = "vendor" }, { source = "none" } }, collect = {} }), "Buy 3 materials")
  Same(St.Headline({ crafts = {}, items = { { source = "vendor" } }, collect = {} }), "Buy 1 material")
  Same(St.Headline({ crafts = { {}, {} }, items = { { source = "auction" }, { source = "vendor" } }, collect = { { item = 1 } } }),
    "Craft 2 intermediates \194\183 Buy 2 \194\183 Collect 1")
  Same(St.Headline({ crafts = {}, items = {}, collect = { { item = 4 } } }), "Collect 1 material")
  -- buy-or-craft comparisons in ordinary words, from the planner's own alternatives (plan totals, never a per-item share)
  local short, lines, each = St.Compare({ source = "make", alternatives = { { kind = "buy", ok = true, compare = "lower", difference = 42, economic = { low = 142, high = 142 } } } }, Money)
  Same(short, "saves 42c"); Same(each[1], "Buying it costs 42c more."); Same(lines[2][1], "If bought instead, the whole plan costs 142c."); Same(lines[2][2], nil, "one sentence, not a two-column line")
  short, _, each = St.Compare({ source = "make", alternatives = { { kind = "buy", ok = true, compare = "overlap", difference = 42, economic = { low = 142, high = 300 } } } }, Money)
  Same(short, "too close to call", "overlapping ranges never claim a saving"); Check(each[1]:find("too close to call", 1, true))
  short, _, each = St.Compare({ source = "auction", alternatives = { { kind = "make", name = "Bolt", ok = true, compare = "lower", difference = 18 } } }, Money)
  Same(short, "cheaper by 18c"); Same(each[1], "Crafting it (Bolt) costs 18c more.")
  short, _, each = St.Compare({ source = "auction", alternatives = { { kind = "make", ok = true, compare = "higher", difference = -18 } } }, Money)
  Same(short, "your choice"); Check(each[1]:find("18c less", 1, true))
  short, _, each = St.Compare({ source = "vendor", alternatives = { { kind = "make", ok = false, why = "circular" } } }, Money)
  Same(short, nil, "an impossible way says nothing on the row"); Check(each[1]:find(W.CraftPlanner.WHY.circular, 1, true), "and its real reason in the tooltip")
  short, _, each = St.Compare({ source = "vendor", alternatives = { { kind = "make", ok = true, compare = "unknown" } } }, Money)
  Check(each[1]:find("can't be compared", 1, true), "a missing price is said, no figure")
  Same((St.Compare({ source = "vendor" }, Money)), nil, "no alternatives: nothing")
  Same(St.Actions({ crafts = { {}, {} }, items = { { source = "auction" }, { source = "vendor" }, { source = "make" } }, collect = { { item = 1 }, { item = 1 }, { item = 2 } } }),
    "Craft 2 \194\183 Buy 2 \194\183 Collect 2")
  Same(St.Actions({ crafts = {}, items = {}, collect = {} }), "Nothing to craft, buy or collect")
end

---------------------------------------------------------------------------
-- B. The shopping list from the multilevel plan
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, Q, St = W.Session, W.Queue, W.Strategy
  Check(S.Add(Rec(W, 1)))
  local old, oldCtx = S.Shopping()
  local plan, ctx, state = S.ShoppingPlan()
  Same(state, "ready", "a small plan is ready before the page is drawn (one slice at once)")
  Same(plan.engine, "multilevel"); Same(ctx.engine, "multilevel")
  local bar = Row(plan, 20, "make"); Check(bar, "making the bars is planned"); Same(bar.make.crafts, 4); Same(bar.make.made, 4); Same(bar.make.surplus, 0)
  Check(bar.make.planned, "the make option says its cost is part of the plan")
  Same(bar.suggested, "make"); Check(not bar.picked)
  local ore = Row(plan, 30, "buy"); Check(ore, "ore is bought"); Same(ore.qty, 7, "2 for the sword + 8 for the bars - 3 in the bags"); Same(ore.source, "auction")
  Same(ore.cash, 700); Same(ore.need, 10, "the queue's combined need"); Same(ore.have, 3)
  Same(ore.short, 0, "the sword's own 2 ore are covered by the 3 in the bags"); Same(ore.extra, 7, "all 7 bought are for the bars"); Check(ore.reagentOnly, "so the row says it is only for making")
  Check(ore.forNames and ore.forNames[1] == "Bar", "and names what for")
  Same(plan.totals.cash, old.totals.cash, "the same spending as the one-level planner on this chain")
  Same(plan.totals.cash, 700); Same(plan.totals.makes, 1); Same(plan.totals.missing, 0)
  Same(#plan.rows, #old.rows, "the same rows")
  Check(plan.plan.summary.complete and plan.plan.summary.proven, "the planner's own result is kept with the rows")
  -- the one-level planner is still what S.Shopping returns, untouched
  Same(old.engine, nil); Same(oldCtx.engine, nil)
  -- a request again is the cached plan, not new work
  local before = St.Stats().started
  S.ShoppingPlan(); Same(St.Stats().started, before, "same inputs: no new job")
  -- the summary words come from the plan's figures
  local words = St.Summary(plan.plan, Money)
  Same(words.economic, "1000c", "700 cash + the 3 ore owned, counted at what they would cost (owning them does not make them free)")
  Same(words.cash, "700c", "the cash is only what is bought")
  Same(words.direct, "1200c", "buying the 4 bars directly: 1000 cash + the 2 ore the sword needs, owned, 200")
  Same(words.savingsLabel, "Savings", "exact prices on both sides: certainly cheaper"); Same(words.savings, "at least 200c")
  Same(words.status, "Best verified plan"); Same(words.actions, "Craft 1 \194\183 Buy 1")
end

---------------------------------------------------------------------------
-- C. Source choices
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, Q, St = W.Session, W.Queue, W.Strategy
  Check(S.Add(Rec(W, 1)))
  local plan = S.ShoppingPlan()
  Check(S.PickSource(20, "auction"), "the player chooses the auction house for the bars")
  local p2, _, state = S.ShoppingPlan()
  Same(state, "ready")
  local bar = Row(p2, 20, "buy"); Check(bar, "the bars are now bought"); Same(bar.source, "auction"); Check(bar.picked, "and it is the player's choice")
  Same(bar.suggested, "make", "the planner's own suggestion is still known: the player's choice always wins, and the row says what differs")
  Same(bar.cash, 1000, "4 bars at 250"); Check(Row(p2, 30, "buy") == nil, "no ore to buy: the sword's 2 are owned")
  Same(p2.totals.cash, 1000)
  Check(St.RowWhy(bar):find("You chose the auction house", 1, true), St.RowWhy(bar))
  Check(bar.options.make and bar.options.make.state == "ok", "making stays a choice that can be picked")
  local choices = W.Shopping.Choices(bar); Same(table.concat(choices, ","), "auction,make", "the same choices as Shopping offers")
  -- back to the suggestion
  Check(S.PickSource(20, nil)); p2 = S.ShoppingPlan()
  Check(Row(p2, 20, "make"), "suggested again"); Check(not Row(p2, 20, "make").picked)
  -- an impossible choice is reported, not honoured, and changes nothing else
  Check(S.PickSource(20, "vendor")); p2 = S.ShoppingPlan()
  local r = Row(p2, 20, "make"); Check(r, "no vendor sells it: the plan makes it"); Check(r.pickLost == "vendor", "and the lost choice is said")
  Check(St.RowWhy(r):find("no longer possible", 1, true))
  Same(p2.totals.cash, 700)
  S.PickSource(20, nil)
  -- choosing to make something that is bought otherwise
  Check(S.PickSource(30, "make")); p2 = S.ShoppingPlan()
  Check(Row(p2, 30, "buy"), "no recipe makes ore: the choice is lost, the ore is bought"); Same(Row(p2, 30, "buy").pickLost, "make")
  S.PickSource(30, nil)
  -- the explanation of a planned make
  local mk = Row(S.ShoppingPlan(), 20, "make")
  Check(St.RowWhy(mk):find("Making this looks cheaper than buying at the auction house", 1, true), St.RowWhy(mk))
end

---------------------------------------------------------------------------
-- D. Cooperative jobs
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, Q, St, CP = W.Session, W.Queue, W.Strategy, W.CraftPlanner
  St.ResetStats()
  -- a big queue (30 recipes of 16 materials) takes many slices
  local function Big(prefix)
    local entries = {}
    for i = 1, 30 do
      local mats = {}
      for j = 1, 16 do mats[j] = { item = prefix + i * 100 + j, qty = 3 } end
      entries[i] = { id = prefix + i, name = "R" .. i, crafts = 5, mats = mats }
    end
    return entries
  end
  local entries = Big(100000)
  local make = function()
    return { entries = entries, have = function() return 0 end, stock = function() return 0, 0 end, auction = function(i) return { price = 10, qty = 99, total = 99, at = 999000, complete = true } end,
      vendor = function() return nil end, sells = function() return false end, recipes = function() return {} end, picks = {} }
  end
  local state = St.Request("t", "k1", make)
  Same(state, "planning", "a big plan is not finished by the first slice")
  Same(St.Request("t", "k1", make), "planning", "asking again for the same key is not a second job")
  Same(St.Stats().started, 1)
  local n = St.Pump()
  Check(n > 5, "the work is spread over many slices (" .. n .. ")")
  local st2, plan = St.Request("t", "k1", make)
  Same(st2, "ready"); Check(plan and plan.summary.complete)
  Check(St.Stats().longest < 50, "one slice stays short offline (" .. St.Stats().longest .. " ms)")
  -- a result is never reused for another key
  Same(St.Request("t", "k2", make), "planning", "a different key starts new work")
  -- an input changes while it runs: the job is cancelled and its answer never shown
  local cancelled = St.Stats().cancelled
  St.Bump()
  Check(St.Stats().cancelled > cancelled, "the running job was cancelled")
  Same(St.Pump(), 0, "nothing left to run"); Check(St.Peek("t", "k2") == nil, "no answer for the cancelled key")
  Same(St.Request("t", "k1", make), "planning", "the earlier answer was forgotten with the change (the key carries the epoch)")
  -- a newer request replaces an older unfinished one; only the newer answer exists
  St.Pump()
  St.Request("t", "a", make); St.Request("t", "b", make)
  St.Pump()
  Check(St.Peek("t", "a") == nil, "the superseded job produced nothing"); Check(St.Peek("t", "b") ~= nil, "the newer one did")
  -- two slots at once (Opportunities and Shopping plan side by side): neither is made stale by the other's request
  St.Reset()
  local ea, eb = Big(200000), Big(300000)
  local function MakeOf(e) return function()
    return { entries = e, have = function() return 0 end, stock = function() return 0, 0 end, auction = function(i) return { price = 10, qty = 99, total = 99, at = 999000, complete = true } end,
      vendor = function() return nil end, sells = function() return false end, recipes = function() return {} end, picks = {} } end end
  Same(St.Request("one", "ka", MakeOf(ea)), "planning"); Same(St.Request("two", "kb", MakeOf(eb)), "planning")
  St.Pump()
  Check(St.Peek("one", "ka") and St.Peek("two", "kb"), "both slots finished: a request of another slot does not make a job stale")
  Same(St.Stats().dropped, 0)
  -- the window closes: nothing runs, nothing is kept
  St.Request("t", "c", make)
  St.Reset()
  Same(St.Stats().running, 0); Same(St.Pump(), 0); Check(St.Peek("t", "c") == nil)
  -- a failing planner is a state, not an error
  local real = CP.Job
  CP.Job = function() error("boom") end
  local sf, _, why = St.Request("t", "d", make)
  Same(sf, "failed"); Check(tostring(why):find("boom", 1, true))
  CP.Job = real
  Same(St.Request("t", "d", make), "failed", "a failure is remembered for its key")
  -- the shopping list shows the last finished list as not current while a newer plan runs (and never as the new plan)
  local c2, g2, W2 = World()
  local S2, St2 = W2.Session, W2.Strategy
  Check(S2.Add(Rec(W2, 1)))
  local p1, ctx1, s1 = S2.ShoppingPlan(); Same(s1, "ready"); Check(not ctx1.stale)
  -- make the next plan take several slices by a big queue
  local realJob = W2.CraftPlanner.Job
  W2.CraftPlanner.Job = function(inp, opt)
    local job = realJob(inp, opt)
    local steps, inner = 0, job.Step
    job.Step = function(self, n) steps = steps + 1 if steps < 8 then return false end return inner(self, n) end
    return job
  end
  Check(S2.PickSource(20, "auction"))
  local p2, ctx2, s2 = S2.ShoppingPlan()
  Same(s2, "planning"); Check(ctx2.stale, "marked as not current"); Same(p2, p1, "the last finished list, unchanged")
  St2.Pump()
  p2, ctx2, s2 = S2.ShoppingPlan(); Same(s2, "ready"); Check(not ctx2.stale); Check(Row(p2, 20, "buy"), "and then the new plan")
  W2.CraftPlanner.Job = realJob
end

---------------------------------------------------------------------------
-- Fallback to the one-level planner
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, St, CP = W.Session, W.Strategy, W.CraftPlanner
  Check(S.Add(Rec(W, 1)))
  local real = CP.Job
  CP.Job = function() error("boom") end
  St.Bump()
  local plan, ctx, state = S.ShoppingPlan()
  Same(state, "basic"); Same(plan.engine, "basic", "the fallback says what it is"); Same(ctx.engine, "basic"); Check(ctx.why:find("boom", 1, true))
  Check(Row(plan, 20, "make"), "it is the old plan: it still plans")
  CP.Job = real
  St.Bump()
  plan, ctx, state = S.ShoppingPlan(); Same(state, "ready"); Same(plan.engine, "multilevel", "and the multilevel plan is back once it works")
end

---------------------------------------------------------------------------
-- E. One recipe, and the confirmed batch
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, Q, St = W.Session, W.Queue, W.Strategy
  local sword = Rec(W, 1)
  local state, plan = S.OppStrategy(sword)
  Same(state, "ready"); Same(#plan.crafts, 1); Same(plan.crafts[1].name, "Bar"); Same(plan.crafts[1].crafts, 4)
  local words = St.Summary(plan, Money)
  Same(words.economic, "1000c"); Same(words.direct, "1200c"); Same(words.actions, "Craft 1 \194\183 Buy 1")
  Same(Q.Count(), 0, "planning changes nothing")
  -- a recipe whose materials aren't known has no strategy, and says so
  local blank = { id = 7, name = "Blank", outItem = 5 }
  Same((S.OppStrategy(blank)), "unknown")

  -- the preview: the queue plus the sword, nothing changed
  local pstate, pplan, ops, key = S.PreviewOptimized(sword)
  Same(pstate, "ready"); Same(#ops, 2, "the bars, then the sword"); Same(ops[1].name, "Bar"); Same(ops[1].crafts, 4); Same(ops[2].name, "Sword"); Check(ops[2].final)
  Same(Q.Count(), 0, "a preview never changes the queue")
  -- applying a stale key is refused
  Check(S.PickSource(30, "auction"))
  local ok, why = S.ApplyOptimized(key, sword)
  Check(not ok and why == "changed", "the inputs changed since the preview: refused, nothing added"); Same(Q.Count(), 0)
  S.PickSource(30, nil)
  pstate, pplan, ops, key = S.PreviewOptimized(sword)
  Check(S.ApplyOptimized(key, sword), "confirmed")
  Same(Q.Count(), 2); Same(Q.Find(500).crafts, 4); Same(Q.Find(1).crafts, 1)
  Same(Q.Entries()[1].id, 500, "the bars stand before the sword: they are made first")
  -- nothing is counted twice: the plan of the queue now has nothing to craft, and a second confirmation finds nothing
  local after = S.QueueStrategy()
  local _, qplan = S.QueueStrategy(); Same(#qplan.crafts, 0, "the queue already makes the bars")
  local s2, p2, ops2, key2 = S.PreviewOptimized(nil)
  Same(#ops2, 0)
  local ok2, why2 = S.ApplyOptimized(key2, nil); Check(not ok2 and why2 == "nothing"); Same(Q.Count(), 2); Same(Q.Find(500).crafts, 4)
  -- more of the sword: only the missing bars are added, onto the same entry
  Check(S.Change(1, 1))
  s2, p2, ops2, key2 = S.PreviewOptimized(nil)
  Same(ops2[1].crafts, 4, "two swords need 8 bars, 4 are queued")
  Check(S.ApplyOptimized(key2, nil)); Same(Q.Find(500).crafts, 8); Same(Q.Count(), 2, "one bar entry")
end

---------------------------------------------------------------------------
-- F. Queue.AddBatch
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, Q = W.Session, W.Queue
  local sword, bar = Rec(W, 1), Rec(W, 500)
  local function Names() local t = {} for _, e in ipairs(Q.Entries()) do t[#t + 1] = e.id .. "x" .. e.crafts end return table.concat(t, ",") end
  Check(not Q.AddBatch({}), "an empty batch is refused"); Check(not Q.AddBatch(nil))
  local ok, why = Q.AddBatch({ { rec = bar, crafts = 2 }, { rec = bar, crafts = 1 } }); Check(not ok and why == "bad", "the same recipe twice is refused"); Same(Names(), "")
  ok, why = Q.AddBatch({ { rec = bar, crafts = 0 } }); Check(not ok and why == "bad")
  ok, why = Q.AddBatch({ { rec = { id = 9, name = "x" }, crafts = 1 } }); Check(not ok and why == "bad", "a recipe without known materials is never queued")
  local range = { id = 8, name = "Range", prof = 1, outItem = 4, outMin = 1, outMax = 3, mats = { { item = 3, qty = 1 } } }
  ok, why = Q.AddBatch({ { rec = range, crafts = 1 } }); Check(not ok and why == "bad", "nor one that makes a varying amount")
  ok, why = Q.AddBatch({ { rec = bar, crafts = 2 }, { rec = sword, crafts = 1 } }); Check(ok, tostring(why)); Same(why.added, 2); Same(Names(), "500x2,1x1")
  -- more crafts of a queued recipe, in the same batch as a new one; one entry too many crafts refuses everything
  ok, why = Q.AddBatch({ { rec = bar, crafts = 998 } }); Check(not ok and why == "toomany"); Same(Names(), "500x2,1x1")
  ok = Q.AddBatch({ { rec = bar, crafts = 997 } }); Check(ok, "2 + 997 is exactly the most one entry holds"); Same(Q.Find(500).crafts, W.MAX_CRAFTS)
  Check(Q.SetCrafts(500, 2))
  ok, why = Q.AddBatch({ { rec = bar, crafts = 3 } }); Check(ok); Same(why.raised, 1); Same(Names(), "500x5,1x1")
  -- a save that fails puts everything back as it was
  local db = c.TwichUIDB
  c.TwichUIDB = nil
  ok, why = Q.AddBatch({ { rec = bar, crafts = 1 } }); Check(not ok and why == "unsaved", tostring(why)); Same(Names(), "500x5,1x1", "the raised count was put back")
  local extra = { id = 77, name = "Extra", prof = 1, outItem = 55, outMin = 1, outMax = 1, mats = { { item = 3, qty = 1 } } }
  ok, why = Q.AddBatch({ { rec = bar, crafts = 1 }, { rec = extra, crafts = 1 } }); Check(not ok); Same(Names(), "500x5,1x1", "and the new entry was removed")
  c.TwichUIDB = db
  -- capacity: the batch that would not fit changes nothing
  for i = 1, W.MAX_QUEUE - 2 do
    Check(Q.AddBatch({ { rec = { id = 1000 + i, name = "F" .. i, prof = 1, outItem = 2000 + i, outMin = 1, outMax = 1, mats = { { item = 3, qty = 1 } } }, crafts = 1 } }))
  end
  Same(Q.Count(), W.MAX_QUEUE)
  local more = { id = 5000, name = "More", prof = 1, outItem = 6000, outMin = 1, outMax = 1, mats = { { item = 3, qty = 1 } } }
  ok, why = Q.AddBatch({ { rec = bar, crafts = 1 }, { rec = more, crafts = 1 } }); Check(not ok and why == "full", tostring(why)); Same(Q.Count(), W.MAX_QUEUE)
  Same(Q.Find(500).crafts, 5, "the queued recipe was not raised either")
  -- a queue held by a newer version
  db.workshop.v = W.SAVED_VERSION + 1
  ok, why = Q.AddBatch({ { rec = bar, crafts = 1 } }); Check(not ok and why == "held")
end

---------------------------------------------------------------------------
-- Invalidation: every input a plan depends on changes the key, and a changed input is never answered from an old plan
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, Q, St = W.Session, W.Queue, W.Strategy
  Check(S.Add(Rec(W, 1)))
  local function Cash() local p, _, st = S.ShoppingPlan(); Same(st, "ready"); return p.totals.cash end
  Same(Cash(), 700)
  -- the bags changed without an event: the key carries what the bags hold of the queue's materials
  g.bags[30] = 100
  Same(Cash(), 0, "plenty of ore: nothing to buy")
  g.bags[30] = 3
  Same(Cash(), 700)
  -- new prices (a scan ended): the plan is worked out again
  c.TwichUIDB.workshop.prices.markets["Realm|unknown"].items[30] = { 50, 99, 99, 99 }
  c.TwichUIDB.workshop.prices.markets["Realm|unknown"].at = 999500
  Same(Cash(), 350, "ore at 50: 7 bought")
  -- a scan that just ended bumps every plan
  local e = St.epoch
  S.NoteScan(); Same(St.epoch, e, "no new scan end: nothing changes")
  W.Scan.ended = (W.Scan.ended or 0) + 1
  S.NoteScan(); Check(St.epoch > e, "a scan end invalidates every plan")
  Same(Cash(), 350)
  -- the queue's crafts, the guild bank choice and the player's choices
  e = St.epoch
  S.Change(1, 1); Check(St.epoch > e, "the number of crafts")
  e = St.epoch; S.SetUseGuild(true); Check(St.epoch > e, "the guild bank choice")
  e = St.epoch; S.PickSource(20, "auction"); Check(St.epoch > e, "a source choice")
  e = St.epoch; S.PickSource(20, "auction"); Same(St.epoch, e, "the same choice again changes nothing")
  S.PickSource(20, nil); S.SetUseGuild(false)
  e = St.epoch; S.Remove(1); Check(St.epoch > e, "removing a recipe")
  -- an empty queue plans nothing
  local plan, ctx, state = S.ShoppingPlan(); Same(state, "ready"); Same(#plan.rows, 0); Same(plan.engine, "multilevel")
  local qs = S.QueueStrategy(); Same(qs, "empty")
end

---------------------------------------------------------------------------
-- Mixed sources: bags, storage (collect), a made material, a vendor
---------------------------------------------------------------------------
do
  local c, g, W = World()
  local S, Q, St = W.Session, W.Queue, W.Strategy
  Check(S.Add(Rec(W, 1)))
  -- a remembered bank holding 4 ore, and none in the bags
  W.Storage.StoreBank({ ids = { 6 }, tabs = { [6] = { [30] = 4 } }, incomplete = 0 }, 999000)
  g.bags[30] = 0
  local plan = S.ShoppingPlan()
  local ore = Row(plan, 30, "buy"); Check(ore, "ore is bought")
  local col = Row(plan, 30, "collect"); Check(col, "and the bank's ore is collected")
  Same(col.where, "bank"); Same(col.qty, 4, "the bank's 4 are collected, not bought")
  Same(ore.qty, 10 - 4, "and the rest is bought: 2 for the sword + 8 for the bars - 4 collected")
  Same(plan.totals.collect, 1); Same(plan.totals.cash, 600)
  -- the collected ore is part of the economic cost, not of the cash
  local words = St.Summary(plan.plan, Money)
  Same(words.cash, "600c"); Same(words.economic, "1000c", "600 cash + the 4 collected ore at 100: owned materials are not free")
  Same(St.Counts(plan.plan).collect, 1)
  Check(St.Actions(plan.plan):find("Collect 1", 1, true))
  -- every row says its source in words and has a reason or a quantity: no row has an unnamed kind
  for _, r in ipairs(plan.rows) do Check(r.kind == "buy" or r.kind == "make" or r.kind == "collect") end
end

-- The settings objective reaches the real planner and changes the chosen plan.
do
  local c, g, W = World()
  local S, St = W.Session, W.Strategy
  g.bags[30] = 10
  c.TwichUIDB.workshop.prices.markets["Realm|unknown"].items[30] = { 200, 99, 99, 99 }
  Check(S.Add(Rec(W, 1)))
  Same(S.Objective(), "economic")
  local economic = S.ShoppingPlan()
  Check(Row(economic, 20, "buy"), "economic cost buys bars rather than consuming more valuable owned ore")
  Same(economic.plan.objective, "economic")
  Check(S.SetObjective("cash"))
  local cash = S.ShoppingPlan()
  Same(cash.plan.objective, "cash", "cash preference reaches queue planner")
  Check(Row(cash, 20, "make"), "cash objective makes bars with owned ore")
  Same(cash.totals.cash, 0); Same(economic.totals.cash, 1000)
  Check(S.PickSource(20, "auction"))
  Check(S.SetObjective("economic") and S.SetObjective("cash"))
  local manual = S.ShoppingPlan()
  Check(Row(manual, 20, "buy").picked, "manual source choice survives objective changes")
  local _, opp = S.OppStrategy(Rec(W, 1))
  Same(opp.objective, "cash", "cash objective reaches recipe strategy")
  Check(not S.SetObjective("invalid")); Same(S.Objective(), "cash")
  local saved = c.TwichUIDB.workshop
  saved.v = W.SAVED_VERSION + 1
  Check(not S.SetObjective("economic") and not S.SetCompactMode("craft"), "future saved records are held")
  Same(saved.view.objective, "cash")
end

print("PASSED test_workshop_strategy")
