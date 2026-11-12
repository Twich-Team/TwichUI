-- Workshop crafting, stock, shopping and craft-profit arithmetic against INDEPENDENT REFERENCE MODELS, on deterministic seeded scenarios
-- (testing roadmap M3; the models are TwichUI_TestLab/Reference.lua section 4, the generators TwichUI_TestLab/Fixtures.lua "Crafting").
--   A. hand-calculated examples (money and quantities worked out on paper, with the arithmetic in the comment);
--   B. W.Split against one-item-at-a-time allocation, with conservation and priority properties;
--   C. Materials.Combine/Rows against the model and against invariants (demand conserved, nothing counted twice, order of the queue is irrelevant);
--   D. Stock.Sources/Counted/Craft/Scope against the model, fed through the real storage records, and the guild-bank policy;
--   E. Shopping.Plan: (1) its cost and collect arithmetic for EVERY sourcing choice of a scenario (the choices are forced through the player's
--      "picks") against the model; (2) its own decisions (options, suggestion, recipe choice) against the contract; (3) its result against the
--      exhaustive optimum, with every difference CLASSIFIED (a documented basis, the one-at-a-time rule, ...) and counted, never called a bug;
--   F. Prices.Quote/Estimate, Opportunities Rows/Select/Summary against the model, with scaling, output, missing-price, negative-profit, cut properties;
--   G. characterization of limits that are the current contract (listed in docs/workshop/testing-roadmap.md section H).
-- (Sections are lettered by topic: the file runs 0, B, C, D, E, F, then A and G, which need the helpers above them.)
-- Synthetic: it proves the logic against a second derivation, not what the auction house, a merchant or the bank return in the game.
--
-- SEEDS (fixed): materials 7500000+i, shopping 7510000+i, economics 7520000+i, stock 7530000+i, for i = 1..N (N = 200).
-- RERUN one failing seed:  CRAFT_SEED=7510042 (cd tests && lua5.1 -e 'require("bit"); ROOT="../!!!TwichUI/"; REPO="../"; TESTS="./"' test_workshop_crafting_reference.lua)
-- STRESS (optional, not part of ./tests/run.sh's time budget):  CRAFT_SCENARIOS=2000   CRAFT_ALL=1 reports every difference instead of the first.
dofile(TESTS .. "mi_mock.lua")
dofile(TESTS .. "client_format.lua")   -- string.format refuses what the client refuses (%d beyond 32 bits, NaN)

local FILES = { "Data.lua", "Materials.lua", "Queue.lua", "Known.lua", "Observe.lua", "Storage.lua", "Stock.lua", "History.lua", "Prices.lua", "Opportunities.lua",
    "Vendor.lua", "Shopping.lua", "Scan.lua", "Market.lua", "Session.lua" }
local LAB = ROOT .. "../TwichUI_TestLab/"

local ONLY = tonumber(os.getenv("CRAFT_SEED") or "")
local N = tonumber(os.getenv("CRAFT_SCENARIOS") or "") or 200
local COLLECT = os.getenv("CRAFT_ALL") ~= nil

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end

local c = MIClient("Rich", { db = { modules = {} } })
c.TwichUIDB = c.TwichUIDB or {}
c.GetRealmName = function() return "Realm" end
for _, f in ipairs(FILES) do
  local chunk = assert(loadfile(ROOT .. "../TwichUI_Workshop/" .. f)); setfenv(chunk, c); chunk("TwichUI_Workshop", {})
end
for _, f in ipairs({ "Fixtures.lua", "Reference.lua" }) do
  local chunk = assert(loadfile(LAB .. f)); setfenv(chunk, c); chunk("TwichUI_TestLab", {})
end
local W = c.TwichUI.Workshop
local PR, MT, K, St, Sh, Op = W.Prices, W.Materials, W.Stock, W.Storage, W.Shopping, W.Opps
local FX, REF = c.TwichUI.TestLab.Fixtures, c.TwichUI.TestLab.Reference

local function Ser(v)
  if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Ser(v[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- A difference stops the run with everything needed to reproduce it (or, under CRAFT_ALL, is collected and reported at the end).
local found = {}
local function Differ(model, seed, what, input, expected, actual, contract)
  local msg = ("%s MISMATCH seed=%s: %s\n  contract: %s\n  input:    %s\n  expected: %s\n  actual:   %s\n  rerun:    CRAFT_SEED=%s"):format(
    model, tostring(seed), what, contract or "(the reference model)", input, expected, actual, tostring(seed))
  if not COLLECT then error(msg, 0) end
  found[#found + 1] = msg
end
local function Expect(model, seed, what, input, expected, actual, contract)
  local e, a = type(expected) == "table" and Ser(expected) or tostring(expected), type(actual) == "table" and Ser(actual) or tostring(actual)
  if e ~= a then Differ(model, seed, what, type(input) == "table" and Ser(input) or tostring(input), e, a, contract) return false end
  return true
end
local function Holds(model, seed, what, input, cond, contract)
  if not cond then Differ(model, seed, what, type(input) == "table" and Ser(input) or tostring(input), "(the invariant holds)", "(it does not)", contract) return false end
  return true
end
-- the seeds of one family: all of base+1..base+N, or only the one asked for
local function Seeds(base)
  local list = {}
  if ONLY then
    if ONLY > base and ONLY <= base + N then list[1] = ONLY end
  else
    for i = 1, N do list[i] = base + i end
  end
  return list
end

local clock0 = os.clock()
local stats = { split = 0, queues = 0, queueRows = 0, cyclic = 0, credited = 0, stock = 0, stockTabs = 0, shop = 0, assignments = 0, infeasible = 0, optimum = 0,
  tooBig = 0, undecided = 0, agree = 0, basis = 0, sequential = 0, unvalued = 0, econ = 0, estimates = 0, ok = 0, negative = 0 }
local examples = {}

---------------------------------------------------------------------------
-- 0. The fixtures: reproducible, different, bounded; the model constants equal production's
---------------------------------------------------------------------------
do
  Same(Ser(FX.Crafting(7500001)), Ser(FX.Crafting(7500001)), "a seed reproduces its crafting scenario")
  Check(Ser(FX.Crafting(7500002)) ~= Ser(FX.Crafting(7500001)), "a neighbouring seed gives another scenario")
  Same(Ser(FX.Economy(7520001)), Ser(FX.Economy(7520001)), "a seed reproduces its economy scenario")
  Same(Ser(FX.StockObs(7530001)), Ser(FX.StockObs(7530001)), "a seed reproduces its stock observations")
  Same(#FX.Crafting(1, { items = 1e9 }).pool, FX.LIMITS.pool, "materials are clamped")
  Same(#FX.Crafting(1, { entries = 1e9 }).entries, FX.LIMITS.entries, "entries are clamped")
  Same(#FX.Crafting(1, { entries = -4 }).entries, 0, "a negative size is none")
  Same(#FX.Crafting(1, { entries = 0 / 0 }).entries >= 1, true, "a NaN size falls back to the default")
  -- every kind of thing the scenarios are for does occur in the first 200 seeds (so a family of tests is not testing an empty case)
  local seen = { unknown = 0, vendor = 0, noprice = 0, recipes = 0, cut = 0, range = 0, nomats = 0, stale = 0, partial = 0, few = 0 }
  for i = 1, 200 do
    local s = FX.Crafting(7500000 + i)
    for _, id in ipairs(s.pool) do
      if s.unknown[id] then seen.unknown = seen.unknown + 1 end
      if s.vendor[id] then seen.vendor = seen.vendor + 1 end
      if s.sells[id] and not s.vendor[id] then seen.noprice = seen.noprice + 1 end
      if s.recipes[id] then seen.recipes = seen.recipes + 1 end
      local a = s.auction[id]
      if a and a.at < FX.NOW - 86400 then seen.stale = seen.stale + 1 end
      if a and a.complete == false then seen.partial = seen.partial + 1 end
      if a and a.total == a.qty then seen.few = seen.few + 1 end
    end
    if s.cut then seen.cut = seen.cut + 1 end
    for _, e in ipairs(s.entries) do
      if e.outMax and e.outMax ~= e.outMin then seen.range = seen.range + 1 end
      if not e.mats then seen.nomats = seen.nomats + 1 end
    end
  end
  for k, v in pairs(seen) do Check(v >= 10, "the generator produces " .. k .. " (" .. v .. ")") end
  -- the model's constants equal production's
  Same(REF.MAX_CRAFTS, W.MAX_CRAFTS); Same(REF.MAX_CANDIDATES, Sh.MAX_CANDIDATES)
  Same(FX.MAX_COPPER, PR.MAX_COPPER)
  for _, k in ipairs(Sh.ORDER) do Check(k == "vendor" or k == "auction" or k == "make") end
  Same(table.concat(Sh.ORDER, ","), "vendor,auction,make", "the tie order the model assumes")
end

---------------------------------------------------------------------------
-- B. W.Split: owned items are taken bags first, then the bank, then the guild bank
---------------------------------------------------------------------------
for _, seed in ipairs(Seeds(7500000)) do
  local rng = FX.Rng(seed)
  local function Layer() return rng:Pick({ false, false, -5, 0, 0 / 0 }) or (rng:Chance(0.3) and 0 or rng:Int(1, 30)) end
  local want = rng:Chance(0.1) and rng:Pick({ -3, 0 }) or rng:Int(0, 60)
  local bags, bank, guild = Layer(), Layer(), Layer()
  local input = ("want=%s bags=%s bank=%s guild=%s"):format(tostring(want), tostring(bags), tostring(bank), tostring(guild))
  local b, k, g, rest = W.Split(want, bags, bank, guild)
  local ref = REF.Take(want, bags, bank, guild)
  Expect("split", seed, "taken from bags, bank, guild bank and still missing", input, ("%d,%d,%d,%d"):format(ref.bags, ref.bank, ref.guild, ref.missing),
    ("%d,%d,%d,%d"):format(b, k, g, rest), "bags first, then bank, then guild bank (Stock.lua header)")
  local Q = function(v) return (type(v) == "number" and v > 0) and v or 0 end
  Holds("split", seed, "nothing is lost or invented: taken + missing = what was asked for", input, b + k + g + rest == Q(want), "quantity conservation")
  Holds("split", seed, "no layer is used beyond what it holds", input, b <= Q(bags) and k <= Q(bank) and g <= Q(guild), "nonnegative, bounded source quantities")
  Holds("split", seed, "nothing is negative", input, b >= 0 and k >= 0 and g >= 0 and rest >= 0, "missing quantities are never negative")
  Holds("split", seed, "the bank is touched only when the bags are used up, the guild bank only when both are", input,
    (k == 0 or b == Q(bags)) and (g == 0 or (b == Q(bags) and k == Q(bank))), "allocation priority")
  Holds("split", seed, "something is missing only when every layer is used up", input,
    rest == 0 or (b == Q(bags) and k == Q(bank) and g == Q(guild)), "no stock is left unused while a need remains")
  stats.split = stats.split + 1
end

---------------------------------------------------------------------------
-- C. Materials.Combine / Materials.Rows
---------------------------------------------------------------------------
local function Shuffled(rng, list)
  local copy = {}
  for i, v in ipairs(list) do copy[i] = v end
  return rng:Shuffle(copy)
end
local ROWFIELDS = { "item", "need", "made", "madeRange", "have", "short", "bank", "guild", "fromBank", "fromGuild" }
local function RowsText(rows)
  local out = {}
  for _, r in ipairs(rows) do
    local one = {}
    for _, f in ipairs(ROWFIELDS) do one[#one + 1] = f .. "=" .. tostring(r[f]) end
    out[#out + 1] = table.concat(one, " ")
  end
  return table.concat(out, "\n")
end

for _, seed in ipairs(Seeds(7500000)) do
  local scn = FX.Crafting(seed, { entries = 1 + seed % 7 })
  local have, stock = FX.CraftHave(scn), FX.CraftStock(scn)
  local rows, sum = MT.Rows(scn.entries, have, stock)
  local mrows, msum = REF.Rows(scn.entries, have, stock)
  local input = Ser(scn.entries)
  Expect("rows", seed, "the rows (need, made, have, short, collect)", input, RowsText(mrows), RowsText(rows), "Materials.lua header")
  Expect("rows", seed, "the summary", input, msum, sum, "Materials.lua header: state and counters")
  stats.queues, stats.queueRows = stats.queues + 1, stats.queueRows + #rows
  if sum.cycle > 0 then stats.cyclic = stats.cyclic + 1 end
  for _, r in ipairs(rows) do if r.made then stats.credited = stats.credited + 1 end end

  -- invariants that do not need the model
  local demand = 0
  for _, e in ipairs(scn.entries) do
    if e.mats then for _, m in ipairs(e.mats) do demand = demand + m.qty * e.crafts end end
  end
  local total, byItem = 0, {}
  for _, r in ipairs(rows) do total = total + r.need byItem[r.item] = r end
  Holds("rows", seed, "every material needed is accounted for exactly once (demand conserved)", input, total == demand, "total demand = sum of materials per craft x crafts")
  Same(#rows, sum.items, "one row per distinct material")
  local usedBags = 0
  for _, r in ipairs(rows) do
    local net = math.max(0, r.need - (r.made or 0))
    Holds("rows", seed, "made credit never exceeds the need's use (net is not negative)", input, net >= 0 and (r.made or 0) >= 0, "nonnegative quantities")
    if r.short == nil then
      Holds("rows", seed, "an unreadable bag count stays unknown (no short, no have, no collect)", input,
        r.have == nil and r.fromBank == nil and r.fromGuild == nil, "unknown is never zero")
    else
      local bagsTaken = net - r.fromBank - r.fromGuild - r.short
      Holds("rows", seed, "net need = taken from bags + bank + guild bank + still short", input, bagsTaken >= 0 and bagsTaken <= r.have, "stock-allocation conservation")
      Holds("rows", seed, "no layer is consumed beyond what it holds", input, r.fromBank <= r.bank and r.fromGuild <= r.guild, "nonnegative, bounded source quantities")
      Holds("rows", seed, "layers are used in order", input,
        (r.fromBank == 0 or bagsTaken == r.have) and (r.fromGuild == 0 or (bagsTaken == r.have and r.fromBank == r.bank)), "bags, then bank, then guild bank")
      Holds("rows", seed, "short means every layer is used up", input,
        r.short == 0 or (bagsTaken == r.have and r.fromBank == r.bank and r.fromGuild == r.guild), "nothing held stays unused while short")
    end
  end
  -- the order of the queue does not change what is needed or short (the bags are applied once, after all of it)
  local shuffled = Shuffled(FX.Rng(seed + 99), scn.entries)
  local rows2, sum2 = MT.Rows(shuffled, have, stock)
  Expect("rows", seed, "the same queue in another order gives the same rows", input, RowsText(rows), RowsText(rows2), "combined requirements do not depend on queue order")
  Expect("rows", seed, "...and the same summary", input, sum, sum2, "combined requirements do not depend on queue order")
  Expect("rows", seed, "identical inputs give identical rows", input, RowsText(rows), RowsText(MT.Rows(scn.entries, have, stock)), "deterministic")
  -- the order: short, unknown, collect, rest; each by item number
  local lastGroup, lastItem = 0, 0
  for _, r in ipairs(rows) do
    local group = r.short == nil and 2 or (r.short > 0 and 1 or ((r.fromBank + r.fromGuild > 0) and 3 or 4))
    Holds("rows", seed, "rows are ordered by group then item", input, group > lastGroup or (group == lastGroup and r.item > lastItem), "short, unknown, collect, ready; each by item")
    lastGroup, lastItem = group, r.item
  end
  -- a stock function that is absent changes nothing about the bags: the rows are what they were for the bags alone
  local bagsOnly = MT.Rows(scn.entries, have)
  for _, r in ipairs(bagsOnly) do
    Holds("rows", seed, "without a stock function nothing is collected", input, r.fromBank == nil or (r.fromBank == 0 and r.fromGuild == 0), "bags alone")
  end
end

---------------------------------------------------------------------------
-- D. Stock: what the remembered bank and guild bank may supply
---------------------------------------------------------------------------
local StockLoad, StockMe
do
  local me = W.Queue.CharKey()
  StockMe = me
  local GID = { key = "Raiders-Realm", name = "Raiders", club = "77" }
  local function Load(obs)
    c.TwichUIDB.workshop = nil
    local who = function(by) return by == "me" and me or "Other - Realm" end
    if obs.bank then
      for bag, tab in pairs(obs.bank.tabs) do Check(St.StoreBank({ tabs = { [bag] = tab.n }, incomplete = 0 }, tab.at), "bank tab stored") end
      if obs.bank.uncertain then St.MarkBankUncertain() end
    end
    if obs.guild then
      for i, tab in pairs(obs.guild.tabs) do
        Check(St.StoreGuildTab(GID, i, { n = tab.n, by = who(tab.by), w = tab.w, rem = tab.rem }, tab.at, obs.guild.nt), "guild tab stored")
      end
      for i, tab in pairs(obs.guild.tabs) do if tab.u then St.MarkGuildTabUncertain(GID, i) end end
    end
    St.SetUseGuild(obs.useGuild)
    return K.Sources({ char = me, guild = obs.inGuild and GID or nil }, obs.useGuild, obs.live, obs.now)
  end
  StockLoad = Load
  local seenState = {}
  for _, seed in ipairs(Seeds(7530000)) do
    local obs = FX.StockObs(seed)
    local view = Load(obs)
    local ref = REF.StockView(obs)
    local input = Ser(obs)
    for _, item in ipairs(obs.items) do
      local b, g = K.Counted(view, item)
      Expect("stock", seed, ("item %d: counted in the bank and in the guild bank"):format(item), input, ref.Bank(item) .. "," .. ref.Guild(item), b .. "," .. g,
        "Stock.lua header: what may be planned with")
    end
    Expect("stock", seed, "which stores the plan counts", input, ref.Scope(), K.Scope(view), "Stock.lua: Scope")
    if obs.guild then
      for i, tab in pairs(obs.guild.tabs) do
        local st = ref.TabState(tab)
        seenState[st] = (seenState[st] or 0) + 1
        if view.guild.enabled and view.guild.inGuild then
          Expect("stock", seed, ("guild tab %d: why it is or is not counted"):format(i), input, st, view.guild.tabState[i], "Stock.lua header: tab rules")
        end
      end
    end
    -- never more than was seen; nothing that was not observed
    local fn = K.Fn(view)
    for _, item in ipairs(obs.items) do
      local bank, guild = fn(item)
      local seenBank, seenGuild = 0, 0
      if obs.bank then for _, t in pairs(obs.bank.tabs) do seenBank = seenBank + (t.n[item] or 0) end end
      if obs.guild then for _, t in pairs(obs.guild.tabs) do seenGuild = seenGuild + (t.n[item] or 0) end end
      Holds("stock", seed, "counted stock never exceeds what was seen", input, bank <= seenBank and guild <= seenGuild, "unknown or unavailable storage is never confirmed stock")
      Holds("stock", seed, "a bank never seen or possibly changed supplies nothing", input, (obs.bank and not obs.bank.uncertain and not obs.live.bankPending) or bank == 0, "uncertain is not counted")
      Holds("stock", seed, "the guild bank supplies nothing unless chosen and in that guild", input, (obs.useGuild and obs.inGuild) or guild == 0, "guild bank materials are opt-in")
    end
    -- one craft's state against the model: three materials, bags drawn at random (one may be unreadable)
    local rng = FX.Rng(seed + 5)
    local mats, bagOf = {}, {}
    for j = 1, rng:Int(0, 3) do
      local item = obs.items[j]
      mats[#mats + 1] = { item = item, qty = rng:Int(1, 12) }
      bagOf[item] = rng:Chance(0.1) and "x" or rng:Int(0, 8)
    end
    local have = function(item) local v = bagOf[item] if v == "x" then return nil end return v end
    local out = K.Craft(mats, have, view)
    local want = REF.CraftState(mats, have, ref.Bank, ref.Guild)
    Expect("stock", seed, "one craft's state and what it takes from each store", input .. Ser(mats) .. Ser(bagOf), want, out, "Stock.Craft")
    -- guild-bank inclusion changes the allocation only as the policy says: the bags and the bank part are identical, the guild bank fills only what
    -- remains, and the difference is exactly what is collected from the guild bank
    local entries = {}
    for j = 1, 2 do
      local item = obs.items[j]
      entries[#entries + 1] = { crafts = rng:Int(1, 3), mats = { { item = item, qty = rng:Int(2, 14) }, { item = obs.items[j + 2], qty = rng:Int(1, 9) } } }
    end
    local bags = {}
    for _, item in ipairs(obs.items) do bags[item] = rng:Int(0, 6) end
    local haveF = function(item) return bags[item] end
    local onView = K.Sources({ char = me, guild = obs.inGuild and GID or nil }, true, obs.live, obs.now)
    local offView = K.Sources({ char = me, guild = obs.inGuild and GID or nil }, false, obs.live, obs.now)
    local on, off = MT.Rows(entries, haveF, K.Fn(onView)), MT.Rows(entries, haveF, K.Fn(offView))
    local offBy = {}
    for _, o in ipairs(off) do offBy[o.item] = o end
    for _, r in ipairs(on) do
      local o = offBy[r.item]
      Holds("stock", seed, "turning the guild bank on never raises what is short", input, r.short <= o.short, "guild stock can only cover more")
      Holds("stock", seed, "the bank part is the same with or without the guild bank", input, r.fromBank == o.fromBank, "the guild bank is the last layer")
      Holds("stock", seed, "with it off nothing is collected from the guild bank", input, o.fromGuild == 0, "guild bank materials are opt-in")
      Holds("stock", seed, "what the guild bank covers is exactly what stopped being short", input, o.short - r.short == r.fromGuild, "stock-allocation conservation")
    end
    stats.stock = stats.stock + 1
    if obs.guild then for _ in pairs(obs.guild.tabs) do stats.stockTabs = stats.stockTabs + 1 end end
  end
  if not ONLY then
    for _, st in ipairs({ "count", "rights", "nowithdraw", "uncertain", "limit" }) do Check((seenState[st] or 0) >= 10, "stock scenarios cover the tab state " .. st .. " (" .. tostring(seenState[st]) .. ")") end
  end
end

---------------------------------------------------------------------------
-- E. Shopping.Plan
---------------------------------------------------------------------------
local MAX_COMBINATIONS = 2048

-- production's plan with the player's choices forced: assign[item] = "vendor" | "auction" | { make = recipe } (one candidate recipe is offered at a time)
local function Produce(scn, rows, assign)
  local picks, cand = {}, {}
  for item, a in pairs(assign) do
    if type(a) == "table" then picks[item] = "make" cand[item] = { a.make } else picks[item] = a end
  end
  local inp = FX.PlanInput(scn, rows, { picks = picks, recipes = function(item) return cand[item] or scn.recipes[item] or {} end })
  return Sh.Plan(inp)
end

local function Collected(plan)
  local out = {}
  for _, r in ipairs(plan.rows) do
    if r.kind == "collect" then out[r.item .. ":" .. r.where] = r.qty end
  end
  return out
end

local function Totals(plan)
  local t = plan.totals
  return { cash = t.cash, priced = t.priced, missing = t.missing, estimate = t.estimate, incomplete = t.incomplete, makes = t.makes }
end

local function RefTotals(res)
  return { cash = res.cash, priced = res.priced, missing = res.missing, estimate = res.estimate, incomplete = res.incomplete, makes = res.makes }
end

-- the details of a made material: crafts, output, leftover, cash, economic cost and each reagent line
local function MakeDetail(o)
  local lines = {}
  for _, l in ipairs(o.reagents or o.lines) do
    lines[#lines + 1] = ("%d:%d own=%d(b%d,k%d,g%d) buy=%d cost=%s value=%s"):format(l.item, l.qty, l.owned or (l.bags + l.bank + l.guild), l.bags, l.bank, l.guild, l.buy,
      tostring(l.cost), tostring(l.value))
  end
  return ("crafts=%d made=%d surplus=%d cash=%s cost=%s | %s"):format(o.crafts, o.made, o.surplus, tostring(o.cash), tostring(o.cost), table.concat(lines, "; "))
end

local function Lost(plan)
  for _, r in ipairs(plan.rows) do if r.pickLost ~= nil then return true end end
  return false
end

-- compares production's plan for `assign` with the model's result for it. Returns true when they agree.
local function CompareAssignment(seed, scn, rows, assign, input, tag)
  local ref = REF.Plan(scn, rows, assign)
  local rev = REF.Plan(scn, rows, assign, true)
  Holds("shopping", seed, tag .. ": the model's verdict does not depend on the order materials are handled in", input,
    ref.feasible == rev.feasible and (not ref.feasible or (Ser(RefTotals(ref)) == Ser(RefTotals(rev)) and Ser(ref.collect) == Ser(rev.collect))),
    "the cash and the collect list of a set of choices are order independent (one shared pool, priced once per item)")
  local plan = Produce(scn, rows, assign)
  if not ref.feasible then
    Holds("shopping", seed, tag .. ": a choice that cannot be done (" .. tostring(ref.why) .. ") is not followed", input, Lost(plan),
      "a pick is used only while its option exists (Shopping.lua header)")
    return ref, plan, false
  end
  Holds("shopping", seed, tag .. ": every choice that can be done is followed", input, not Lost(plan), "a player's choice is used when its option still exists")
  Expect("shopping", seed, tag .. ": totals (cash, priced, missing, estimate, incomplete, makes)", input, RefTotals(ref), Totals(plan), "Shopping.lua: the cash adds only what is priced")
  Expect("shopping", seed, tag .. ": what is collected from storage", input, ref.collect, Collected(plan), "Shopping.lua: stored materials are collected, not bought")
  for _, row in ipairs(plan.rows) do
    if row.kind == "make" then
      local want = ref.makeInfo[row.item]
      Holds("shopping", seed, tag .. ": a made material the model did not make", input, want ~= nil, "the choices")
      if want then Expect("shopping", seed, tag .. ": the make of item " .. row.item, input, MakeDetail(want), MakeDetail(row.make), "Shopping.lua: the economic cost of making") end
    elseif row.kind == "buy" then
      local info = ref.acquire[row.item]
      Holds("shopping", seed, tag .. ": a bought item the model did not buy", input, info ~= nil, "the choices")
      if info then
        Expect("shopping", seed, tag .. ": the quantity and cost bought of item " .. row.item, input, ("qty=%d src=%s cost=%s"):format(info.qty, tostring(info.source), tostring(info.cost)),
          ("qty=%d src=%s cost=%s"):format(row.qty, tostring(row.source), tostring(row.cash)), "each bought item is priced once for its whole quantity")
      end
    end
  end
  return ref, plan, true
end

for _, seed in ipairs(Seeds(7510000)) do
  local scn = FX.Crafting(seed, { entries = 2 + seed % 3 })
  local rows = MT.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))
  local mrows = REF.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))
  Expect("shopping", seed, "the rows the plan starts from", Ser(scn.entries), RowsText(mrows), RowsText(rows), "Materials.lua header")
  local input = Ser(scn)
  local plan = Sh.Plan(FX.PlanInput(scn, rows))
  stats.shop = stats.shop + 1

  -- (1) the plan's own invariants, without the model
  local unknownBags, shortItems = 0, {}
  for _, r in ipairs(rows) do
    if r.short == nil then unknownBags = unknownBags + 1 elseif r.short > 0 then shortItems[#shortItems + 1] = r.item end
  end
  Same(plan.unknownBags, unknownBags, "unknown bag counts are reported, not treated as zero")
  local cash, priced, missing, anyEstimate, anyIncomplete, nmake = 0, 0, 0, false, false, 0
  for _, r in ipairs(plan.rows) do
    if r.kind == "buy" then
      if r.cash then
        Holds("shopping", seed, "a price is a positive whole number of copper (a missing price is never zero)", input, r.cash >= 1 and r.cash % 1 == 0, "unknown is never zero")
        cash, priced = cash + r.cash, priced + 1
        if r.estimate then anyEstimate = true end
      else
        missing = missing + 1
      end
      Holds("shopping", seed, "what is bought is short or a reagent, and positive", input, r.qty >= 1 and r.qty == (r.short or 0) + r.extra, "bought = short + reagents")
    elseif r.kind == "make" then
      nmake = nmake + 1
      local m = r.make
      Holds("shopping", seed, "crafts cover the shortage with the fewest crafts", input,
        m.made == m.crafts * m.perCraft and m.made >= r.short and m.surplus == m.made - r.short and m.surplus < m.perCraft, "ceil(short / output) crafts, the leftover is shown")
      for _, l in ipairs(m.reagents) do
        Holds("shopping", seed, "a reagent line: owned + bought = needed", input, l.owned + l.buy == l.qty and l.owned >= 0 and l.buy >= 0, "quantity conservation")
      end
    elseif r.kind == "collect" then
      Holds("shopping", seed, "a collect row holds something", input, r.qty >= 1, "positive quantities")
    end
  end
  Expect("shopping", seed, "totals add up the rows", input, ("%d,%d,%d,%s,%d"):format(cash, priced, missing, tostring(anyEstimate), nmake),
    ("%d,%d,%d,%s,%d"):format(plan.totals.cash, plan.totals.priced, plan.totals.missing, tostring(plan.totals.estimate), plan.totals.makes), "Shopping.lua: spending adds up only what is priced")
  -- owned items are spent once: the queue's own use and the made materials' reagents together never exceed what is held in any layer
  local spent = {}
  local function Spend(item, b, k, g)
    local s = spent[item] or { 0, 0, 0 }
    spent[item] = { s[1] + b, s[2] + k, s[3] + g }
  end
  for _, r in ipairs(rows) do
    if r.short ~= nil then
      local net = math.max(0, r.need - (r.made or 0))
      Spend(r.item, net - r.fromBank - r.fromGuild - r.short, r.fromBank, r.fromGuild)
    end
  end
  for _, r in ipairs(plan.rows) do
    if r.kind == "make" then for _, l in ipairs(r.make.reagents) do Spend(l.item, l.bags, l.bank, l.guild) end end
  end
  for item, s in pairs(spent) do
    local bags = FX.CraftHave(scn)(item)
    local bank, guild = FX.CraftStock(scn)(item)
    Holds("shopping", seed, "no owned item is spent twice, and an unreadable bag count spends nothing (item " .. item .. ")", input,
      (bags == nil and s[1] == 0 and s[2] == 0 and s[3] == 0) or (bags ~= nil and s[1] <= bags and s[2] <= bank and s[3] <= guild),
      "one shared pool of owned items (Shopping.lua header)")
  end
  -- the suggestion is never costlier than an option it beat, and a tie goes vendor, auction, making
  -- (the options of a bought row are priced for everything bought of it, which can exceed what was short when it was decided: the suggestion was
  -- made at its turn, so it is judged against the options of that turn: rows where nothing was added, and made materials)
  for _, r in ipairs(plan.rows) do
    if r.kind ~= "collect" and r.suggested and not r.reagentOnly and (r.kind == "make" or r.extra == 0) then
      local best = r.options[r.suggested]
      for rank, kind in ipairs(Sh.ORDER) do
        local o = r.options[kind]
        if o and o.cost and (kind ~= "make" or o.state == "ok") and r.options[r.suggested].cost then
          local mine
          for k2, name in ipairs(Sh.ORDER) do if name == r.suggested then mine = k2 end end
          Holds("shopping", seed, "the suggestion is not costlier than " .. kind, input, best.cost <= o.cost and (o.cost > best.cost or mine <= rank), "cheapest known cost, ties to vendor, auction, making")
        end
      end
    end
  end

  -- (2) the plan's own decisions against the contract, replayed material by material
  local decisions = REF.Decisions(scn, mrows)
  for _, r in ipairs(plan.rows) do
    local d = r.kind ~= "collect" and not r.reagentOnly and decisions[r.item] or nil
    if d then
      Expect("shopping", seed, "the suggestion for item " .. r.item, input, tostring(d.suggested), tostring(r.suggested), "cheapest known cost, ties to vendor, auction, making")
      if d.make then
        Expect("shopping", seed, "the recipe chosen for item " .. r.item .. " (state and cost)", input, ("%s %s %s"):format(d.make.rec.id, d.make.state, tostring(d.make.cost)),
          ("%s %s %s"):format(r.options.make.rec.id, r.options.make.state, tostring(r.options.make.cost)), "the cheapest recipe that can be done, else the first")
      else
        Holds("shopping", seed, "no recipe offered for item " .. r.item, input, r.options.make == nil, "no known recipe")
      end
      if r.extra == 0 and r.qty == r.short then
        for _, kind in ipairs({ "vendor", "auction" }) do
          local want, got = d.buy[kind], r.options[kind]
          Expect("shopping", seed, kind .. " option of item " .. r.item, input, want and ("%s %s"):format(want.state, tostring(want.cost)) or "-",
            got and ("%s %s"):format(got.state, tostring(got.cost)) or "-", "Prices.Quote / Vendor.Quote rules")
        end
      end
    end
  end

  -- (3) the choice the plan made, replayed by the model
  local mine = REF.AssignmentOf(plan, rows)
  local ref = REF.Plan(scn, mrows, mine)
  Holds("shopping", seed, "the plan's own choices are feasible in the model (" .. tostring(ref.why) .. ")", input, ref.feasible, "one level, no chains")
  if ref.feasible then
    Expect("shopping", seed, "the plan's totals", input, RefTotals(ref), Totals(plan), "Shopping.lua")
    Expect("shopping", seed, "the plan's collect rows", input, ref.collect, Collected(plan), "Shopping.lua")
    for _, row in ipairs(plan.rows) do
      if row.kind == "make" then Expect("shopping", seed, "the plan's make of item " .. row.item, input, MakeDetail(ref.makeInfo[row.item]), MakeDetail(row.make), "Shopping.lua") end
    end
  end

  -- (4) every sourcing choice, forced through the player's picks, against the model; the best of them against what the plan chose
  local best, bestEcon, bestAssign
  local count = REF.Enumerate(scn, mrows, MAX_COMBINATIONS, function(assign, res)
    local r2, p2, followed = CompareAssignment(seed, scn, rows, assign, input, "choice")
    stats.assignments = stats.assignments + 1
    if not followed then stats.infeasible = stats.infeasible + 1 return end
    if not best or res.missing < best.missing or (res.missing == best.missing and res.cash < best.cash) then best, bestAssign = res, assign end
    if res.missing == 0 then
      local econ = REF.Economic(res)
      if not bestEcon or econ < bestEcon then bestEcon = econ end
    end
  end)
  -- a plan that leaves a material UNDECIDED although a recipe could make it (its cost is not known, so it is never suggested) buys less than any
  -- choice that makes it, so it is a different kind of plan: counted and not compared
  local undecided = false
  for _, r in ipairs(rows) do
    if r.short and r.short > 0 and mine[r.item] == nil then
      local usable = false   -- (an unsourced material with only unpriced buying options equals choosing one of them: cash is unchanged)
      for _, rec in ipairs(scn.recipes[r.item] or {}) do
        if REF.MakeOption(scn, REF.NewContext(scn, mrows), r.item, r.short, rec).state == "ok" then usable = true end
      end
      if usable then undecided = true end
    end
  end
  if not count then
    stats.tooBig = stats.tooBig + 1
  elseif undecided then
    stats.undecided = stats.undecided + 1
  elseif best and ref.feasible then
    stats.optimum = stats.optimum + 1
    local mineBetter = ref.missing < best.missing or (ref.missing == best.missing and ref.cash < best.cash)
    Holds("shopping", seed, "the plan beat the exhaustive search (the model or the planner's accounting is wrong)", input, not mineBetter,
      "no combination of the same choices costs less than the cheapest one")
    if ref.missing == best.missing and ref.cash == best.cash then
      stats.agree = stats.agree + 1
    else
      -- a difference is a finding to CLASSIFY, never a bug by itself: the planner decides one material at a time and values owned reagents
      local class
      local unpriced = false
      for _, o in pairs(best.makeInfo) do if o.cost == nil then unpriced = true end end
      if ref.missing > best.missing or unpriced then class = "unvalued"   -- a recipe whose economic cost is unknown is never preferred, though its cash is known
      elseif ref.missing == 0 and REF.Economic(ref) == bestEcon then class = "basis"   -- the plan is cheapest on its own basis (owned reagents valued)
      else class = "sequential" end                                   -- an earlier choice changed what a later one costs, or pricing together beat pricing apart
      stats[class] = stats[class] + 1
      examples[class] = examples[class] or { seed = seed, plan = ref.cash, best = best.cash, planMissing = ref.missing, bestMissing = best.missing }
    end
  end

  -- (5) a pick for a source that does not exist is not used, and says so (it still decides its item first: see the hand example in section A)
  local dud = {}
  for _, item in ipairs(shortItems) do
    local o = REF.BuyOptions(scn, item, 1)
    for _, kind in ipairs({ "vendor", "auction" }) do
      if not o[kind] and not dud[item] then dud[item] = kind end
    end
  end
  if next(dud) then
    local forced = Sh.Plan(FX.PlanInput(scn, rows, { picks = dud }))
    local n, lost = 0, 0
    for item, kind in pairs(dud) do
      n = n + 1
      for _, r in ipairs(forced.rows) do
        if r.item == item and (r.kind == "buy" or r.kind == "make") and not r.reagentOnly then
          Holds("shopping", seed, "a pick for a source that does not exist is reported lost and not followed", input, r.pickLost == kind and r.picked ~= true and r.source ~= kind,
            "Shopping.lua: a pick is used when its option still exists")
          lost = lost + 1
        end
      end
    end
    Holds("shopping", seed, "each lost pick has a row", input, lost == n, "pickLost")
  end
end

---------------------------------------------------------------------------
-- F. Prices.Quote / Prices.Estimate / Opportunities
---------------------------------------------------------------------------
local function EstimateText(e)
  local mats = {}
  for _, m in ipairs(e.mats) do
    mats[#mats + 1] = ("%d x%d unit=%s total=%s at=%s complete=%s cheapest=%s unavailable=%s"):format(m.item, m.qty, tostring(m.unit), tostring(m.total), tostring(m.at),
      tostring(m.complete), tostring(m.cheapest), tostring(m.unavailable))
  end
  local f = {}
  for _, k in ipairs({ "state", "why", "cost", "missing", "outMin", "outMax", "unit", "sellLow", "sellHigh", "netLow", "netHigh", "profitLow", "profitHigh", "oldest", "incomplete", "cheapest" }) do
    f[#f + 1] = k .. "=" .. tostring(e[k])
  end
  return table.concat(f, " ") .. " | " .. table.concat(mats, "; ")
end

local OPTS = {
  { sort = "profit", desc = true }, { sort = "profit", desc = false }, { sort = "cost", desc = true }, { sort = "cost", desc = false },
  { sort = "sell", desc = true }, { sort = "sell", desc = false }, { sort = "profit", desc = true, prof = 171 }, { sort = "sell", desc = false, prof = 164, profitOnly = true },
  { sort = "profit", desc = true, profitOnly = true }, { sort = "cost", desc = false, profitOnly = true, prof = 333 },
}

for _, seed in ipairs(Seeds(7520000)) do
  local eco = FX.Economy(seed)
  local lookup = function(item) return eco.lookup[item] end
  local rate = eco.cut and eco.cut / 1000 or nil
  local input = Ser(eco)

  -- Prices.Quote on every item at the edges of what is listed
  for item, p in pairs(eco.lookup) do
    for _, qty in ipairs({ 1, p.qty, p.qty + 1, p.total, p.total + 1, 40 }) do
      local q = PR.Quote(p, qty)
      local want = REF.BuyOptions({ auction = { [item] = p }, vendor = {}, sells = {} }, item, qty).auction
      Expect("quote", seed, ("item %d x%d: state and cost"):format(item, qty), input, ("%s %s"):format(want.state, tostring(want.cost)), ("%s %s"):format(q.state, tostring(q.cost)),
        "Prices.lua: Quote (exact, estimate, few)")
      Holds("quote", seed, "an estimate is the least it could cost: price x quantity, and never presented as exact", input,
        (qty <= p.qty) == (q.state == "exact") or q.state == "few", "the estimate stays explicitly qualified")
    end
  end
  Same(PR.Quote(nil, 3).state, "none"); Same(PR.Quote({ price = 5, qty = 1, total = 1 }, 0).state, "none", "no quantity is no quote")

  -- one craft, each recipe against the model
  local rows = Op.Rows(eco.recipes, lookup, rate)
  for i, rec in ipairs(eco.recipes) do
    local e = rows[i].est
    local want = REF.Estimate(rec, eco.lookup, eco.cut)
    Expect("estimate", seed, "recipe " .. rec.id, Ser(rec), EstimateText(want), EstimateText(e), "Prices.lua: Estimate (cost, sell value, cut, profit)")
    stats.estimates = stats.estimates + 1
    Expect("estimate", seed, "identical inputs give the identical estimate", Ser(rec), EstimateText(e), EstimateText(PR.Estimate(rec, lookup, rate)), "deterministic")
    if e.state == "ok" then
      stats.ok = stats.ok + 1
      if e.profitLow < 0 then stats.negative = stats.negative + 1 end
      Holds("estimate", seed, "profit is the proceeds after the cut minus the cost, a loss stays a negative number", Ser(rec),
        e.profitLow == e.netLow - e.cost and e.profitHigh == e.netHigh - e.cost and e.profitLow <= e.profitHigh, "estimated profit = net proceeds - material cost")
      Holds("estimate", seed, "the output quantity is respected (sell value = price x amount made)", Ser(rec), e.sellLow == e.unit * e.outMin and e.sellHigh == e.unit * e.outMax, "recipe output quantity")
      Holds("estimate", seed, "the cut never raises the proceeds and is whole copper", Ser(rec), e.netLow <= e.sellLow and e.netHigh <= e.sellHigh and e.netLow % 1 == 0, "auction house cut")
      Holds("estimate", seed, "without a confirmed cut nothing is deducted", Ser(rec), rate ~= nil or (e.netLow == e.sellLow and e.netHigh == e.sellHigh), "profit before fees")
      local label = Op.ProfitLabel({ est = e })
      Same(label, rate and "Estimated profit" or "Profit before fees", "the profit is named for what it is")
    else
      Holds("estimate", seed, "an unknown estimate has no profit and no complete cost", Ser(rec), e.profitLow == nil and e.profitHigh == nil and (e.why ~= nil), "missing is never zero")
    end
    local priced = true
    for _, m in ipairs(e.mats) do
      if m.unit == nil then
        priced = false
        Holds("estimate", seed, "an unpriced material has no total (not zero)", Ser(rec), m.total == nil and m.unavailable ~= nil, "missing prices never become zero")
      else
        Holds("estimate", seed, "a price is positive", Ser(rec), m.unit >= 1 and m.total == m.unit * m.qty, "material quantity x unit price")
        local p = eco.lookup[m.item]
        Holds("estimate", seed, "a quantity beyond the cheapest listing is flagged", Ser(rec), m.cheapest == (m.qty > p.qty), "uncertain acquisition cost is not a guaranteed total")
      end
    end
    Holds("estimate", seed, "a cost exists only when every material is priced", Ser(rec), (e.cost ~= nil) == (priced and type(rec.mats) == "table" and #rec.mats > 0), "missing prices never become zero")
    -- scaling: a recipe that needs twice as much costs twice as much, while the prices stay what they are (or becomes unavailable)
    if type(rec.mats) == "table" and #rec.mats > 0 and e.cost then
      local doubled = { outItem = rec.outItem, outMin = rec.outMin, outMax = rec.outMax, mats = {} }
      local fits = true
      for j, m in ipairs(rec.mats) do
        doubled.mats[j] = { item = m.item, qty = m.qty * 2 }
        if eco.lookup[m.item].total < m.qty * 2 then fits = false end
      end
      local e2 = PR.Estimate(doubled, lookup, rate)
      if fits then
        Holds("estimate", seed, "material quantities scale: twice the materials cost twice as much", Ser(rec), e2.cost == 2 * e.cost, "cost scales with quantity")
        Holds("estimate", seed, "...and a flag set at one craft stays set", Ser(rec), (not e.cheapest) or e2.cheapest, "monotone uncertainty")
      else
        Holds("estimate", seed, "when the listed items cannot cover twice the materials the cost is unknown, not smaller", Ser(rec), e2.cost == nil and e2.missing > 0 and e2.state == "unknown", "few listed")
      end
    end
  end

  -- the Opportunities list: summary and order against the model
  local sum = Op.Summary(rows)
  local priced, profitable = 0, 0
  local refRows = {}
  for i, r in ipairs(rows) do
    refRows[i] = { rec = r.rec, est = REF.Estimate(r.rec, eco.lookup, eco.cut) }
    if r.est.state == "ok" then priced = priced + 1 if r.est.profitLow > 0 then profitable = profitable + 1 end end
  end
  Expect("opportunities", seed, "the summary", input, ("%d,%d,%d"):format(#rows, priced, profitable), ("%d,%d,%d"):format(sum.total, sum.priced, sum.profitable), "Opportunities.lua: Summary")
  for n, opts in ipairs(OPTS) do
    local got, want = {}, {}
    for _, r in ipairs(Op.Select(rows, opts)) do got[#got + 1] = r.rec.id end
    for _, r in ipairs(REF.Order(refRows, opts)) do want[#want + 1] = r.rec.id end
    Expect("opportunities", seed, "the order for options " .. n .. " " .. Ser(opts), input, table.concat(want, ","), table.concat(got, ","), "known rows first, by the chosen figure, then name, then id")
    local reversed = {}
    for k = #rows, 1, -1 do reversed[#reversed + 1] = rows[k] end
    local again = {}
    for _, r in ipairs(Op.Select(reversed, opts)) do again[#again + 1] = r.rec.id end
    Expect("opportunities", seed, "the order does not depend on the order the rows came in", input, table.concat(got, ","), table.concat(again, ","), "a total order: ties end at the recipe id")
  end
end

---------------------------------------------------------------------------
-- A. Hand-calculated examples (the arithmetic is in the comments)
---------------------------------------------------------------------------
local A, B, C = 101, 102, 103
do
  -- W.Split: 10 wanted, 4 in bags, 3 in the bank, 2 in the guild bank -> 4 + 3 + 2 and 1 missing
  local b, k, g, rest = W.Split(10, 4, 3, 2)
  Same(b .. "," .. k .. "," .. g .. "," .. rest, "4,3,2,1", "everything held is used, 1 is missing")
  b, k, g, rest = W.Split(5, 4, 3, 2)
  Same(b .. "," .. k .. "," .. g .. "," .. rest, "4,1,0,0", "5 wanted: 4 from the bags, 1 from the bank, none from the guild bank")
  b, k, g, rest = W.Split(5, nil, -2, 9)
  Same(b .. "," .. k .. "," .. g .. "," .. rest, "0,0,5,0", "an unknown or negative layer holds nothing")
  b, k, g, rest = W.Split(nil, 4, 4, 4)
  Same(b .. "," .. k .. "," .. g .. "," .. rest, "0,0,0,0", "nothing wanted takes nothing")

  -- Materials.Rows: R1 = 3 crafts of (2 A + 1 B), R2 = 2 crafts of (1 A): A is needed 3*2 + 2*1 = 8, B 3*1 = 3
  local entries = { { crafts = 3, mats = { { item = A, qty = 2 }, { item = B, qty = 1 } } }, { crafts = 2, mats = { { item = A, qty = 1 } } } }
  local have = function(i) return ({ [A] = 3, [B] = 5 })[i] end
  local stock = function(i) if i == A then return 2, 4 end return 0, 0 end
  local rows, sum = MT.Rows(entries, have, stock)
  Same(#rows, 2); Same(rows[1].item, A, "the item that is short..."); Same(rows[1].need, 8)
  -- 8 needed: 3 from the bags, 2 from the bank, 3 of the guild bank's 4; nothing is short
  Same(rows[1].fromBank .. "," .. rows[1].fromGuild .. "," .. rows[1].short, "2,3,0", "bags, then bank, then guild bank")
  Same(rows[2].item, B); Same(rows[2].need, 3); Same(rows[2].short, 0, "B: 3 of the 5 in the bags")
  Same(sum.state, "collect", "everything is held, some of it in storage")
  local noGuild = MT.Rows(entries, have, function(i) if i == A then return 2, 0 end return 0, 0 end)
  Same(noGuild[1].short, 3, "without the guild bank 8 - 3 - 2 = 3 are short"); Same(noGuild[1].fromGuild, 0)
  -- a queued craft's output counts: R3 = 2 crafts making 2 A each (from C) credits 4 A, so A's net need is 4
  local with = { entries[1], entries[2], { crafts = 2, mats = { { item = C, qty = 1 } }, outItem = A, outMin = 2, outMax = 2 } }
  local r3 = MT.Rows(with, have, stock)
  local byItem = {}
  for _, r in ipairs(r3) do byItem[r.item] = r end
  Same(byItem[A].made, 4); Same(byItem[A].fromBank, 1, "net 4: 3 from the bags, 1 from the bank"); Same(byItem[A].fromGuild, 0); Same(byItem[A].short, 0)
  with[3].outMax = 3
  local r4 = MT.Rows(with, have, stock)
  for _, r in ipairs(r4) do byItem[r.item] = r end
  Same(byItem[A].made, 4, "a range counts the least it makes"); Same(byItem[A].madeRange, true)
  -- an unknown bag count is unknown, never zero
  local ur = MT.Rows(entries, function(i) if i == B then return nil end return 3 end, stock)
  for _, r in ipairs(ur) do byItem[r.item] = r end
  Check(byItem[B].short == nil and byItem[B].have == nil, "B's bag count could not be read")
  -- a recipe whose materials are not known adds nothing and is counted
  local _, sum2 = MT.Rows({ { crafts = 2 }, entries[2] }, have, stock)
  Same(sum2.unknown, 1); Same(sum2.state, "partial")
  Same(select(2, MT.Rows({}, have)).state, "empty")
  -- Queue.CleanMats never lets an empty materials list through, so the one case the credit rule would misread is unreachable from a real queue
  Same(W.Queue.CleanMats({}), nil, "an empty list of materials is not a recipe")

  -- Stock: a bank tab holding 5 A, a guild tab (mine, may withdraw, no limit) holding 7 A
  local obs = { char = "me", items = { A }, useGuild = true, inGuild = true, live = {}, now = FX.NOW,
    bank = { tabs = { [6] = { at = FX.NOW - 100, n = { [A] = 5 } } } }, guild = { nt = 3, tabs = { [1] = { at = FX.NOW - 100, n = { [A] = 7 }, by = "me", w = 1, rem = -1 } } } }
  local function Counted(o) local v = StockLoad(o); local bk, gd = K.Counted(v, A); return bk .. "," .. gd end
  Same(Counted(obs), "5,7", "the bank and a guild tab I may take from")
  obs.guild.tabs[1].by = "other"; Same(Counted(obs), "5,0", "a tab only another character saw is information, not stock")
  obs.guild.tabs[1].by = "me"; obs.guild.tabs[1].w = 0; Same(Counted(obs), "5,0", "a rank that cannot withdraw")
  obs.guild.tabs[1].w = nil; Same(Counted(obs), "5,0", "an unknown right is not permission")
  obs.guild.tabs[1].w = 1; obs.guild.tabs[1].rem = 0; obs.guild.tabs[1].at = FX.NOW - 21599; Same(Counted(obs), "5,0", "the daily allowance was used up 21599 s ago: still believed")
  obs.guild.tabs[1].at = FX.NOW - 21600; Same(Counted(obs), "5,7", "...and at 21600 s (6 hours) it is not")
  obs.guild.tabs[1].rem = 5; obs.guild.tabs[1].at = FX.NOW - 100; obs.guild.tabs[1].u = true; Same(Counted(obs), "5,0", "a tab that may have changed")
  obs.guild.tabs[1].u = nil; obs.useGuild = false; Same(Counted(obs), "5,0", "guild bank materials are off")
  obs.useGuild = true; obs.bank.uncertain = true; Same(Counted(obs), "0,7", "a bank that may have changed is not counted")
  obs.bank.uncertain = false; obs.bank = nil; Same(Counted(obs), "0,7", "a bank never seen holds nothing")
  obs.guild.tabs[2] = { at = FX.NOW - 100, n = { [A] = 3 }, by = "me", w = 1, rem = -1 }
  Same(Counted(obs), "0,10", "two tabs add up; tab 3 was never read and adds nothing")
  Same(K.Scope(StockLoad(obs)), "bags and guild bank")
end

do
  -- Prices.Quote: price 100 at the cheapest listing, 3 items there, 8 listed in all
  local p = { price = 100, qty = 3, listings = 2, total = 8, at = FX.NOW, complete = true }
  local q = PR.Quote(p, 3);  Same(q.state .. q.cost, "exact300", "3 are listed at 100: 300 is a listed price")
  q = PR.Quote(p, 4);        Same(q.state .. q.cost, "estimate400", "the 4th costs at least 100: 400 is the LEAST it could cost, qualified as an estimate")
  q = PR.Quote(p, 8);        Same(q.state .. q.cost, "estimate800")
  q = PR.Quote(p, 9);        Same(q.state, "few"); Same(q.cost, nil, "9 are not listed, so there is no cost, not zero")
  -- the saved next higher price is NOT used to tighten the estimate (a later milestone's job)
  p.next = 150; q = PR.Quote(p, 5); Same(q.cost, 500, "estimate = price x quantity even though a dearer price is saved")

  -- Prices.Estimate, one craft: 5 M at 7 (4 at the cheapest price, 20 listed), makes 2 X listed at 90; cut 5 %
  local lookup = { [1] = { price = 7, qty = 4, total = 20, at = FX.NOW - 50, complete = true }, [2] = { price = 90, qty = 1, total = 5, at = FX.NOW - 10, complete = true } }
  local rec = { outItem = 2, outMin = 2, outMax = 2, mats = { { item = 1, qty = 5 } } }
  local function L(item) return lookup[item] end
  local e = PR.Estimate(rec, L, nil)
  -- cost 5 x 7 = 35 (flagged: 5 > 4), sells 2 x 90 = 180, no cut known: profit 145 before fees
  Same(e.cost, 35); Same(e.sellLow, 180); Same(e.profitLow, 145, "180 - 35 before fees"); Same(e.cheapest, true, "5 > 4 at the cheapest price: the cost is a minimum")
  Same(e.oldest, FX.NOW - 50, "the oldest observation used"); Same(Op.ProfitLabel({ est = e }), "Profit before fees")
  e = PR.Estimate(rec, L, 0.05)
  -- cut: 180 x 0.05 = 9 -> net 171; profit 171 - 35 = 136
  Same(e.netLow, 171); Same(e.profitLow, 136, "171 - 35"); Same(Op.ProfitLabel({ est = e }), "Estimated profit")
  -- a range of output 2-3: sells 180 to 270; cut 13.5 -> 14 (half up); net 256; profit 136 to 221
  rec.outMax = 3; e = PR.Estimate(rec, L, 0.05)
  Same(e.sellHigh, 270); Same(e.netHigh, 256); Same(e.profitLow, 136); Same(e.profitHigh, 221, "256 - 35")
  -- a loss stays a loss: it sells at 10 each: 2 x 10 = 20, minus 35 = -15
  lookup[2].price = 10; rec.outMax = 2; e = PR.Estimate(rec, L, nil)
  Same(e.profitLow, -15, "negative profit is preserved, not clamped to zero"); Same(e.state, "ok")
  -- a missing price is not zero: without a price for M there is no cost and no profit
  lookup[1] = nil; e = PR.Estimate(rec, L, nil)
  Same(e.cost, nil); Same(e.profitLow, nil); Same(e.state, "unknown"); Same(e.why, "matprice"); Same(e.missing, 1)
  -- fewer listed than one craft needs is also no cost
  lookup[1] = { price = 7, qty = 4, total = 4, at = FX.NOW, complete = true }; e = PR.Estimate(rec, L, nil)
  Same(e.cost, nil, "4 listed, 5 needed"); Same(e.mats[1].unavailable, "few")
  -- the material total is exact copper: 12 x 1,000,001 = 12,000,012
  lookup[1] = { price = 1000001, qty = 20, total = 20, at = FX.NOW, complete = true }; rec.mats[1].qty = 12
  Same(PR.Estimate(rec, L, nil).cost, 12000012)
end

local function Hand(t)
  return { now = FX.NOW, entries = t.entries or {}, bags = t.bags or {}, unknown = t.unknown or {}, bank = t.bank or {}, guild = t.guild or {},
    auction = t.auction or {}, vendor = t.vendor or {}, sells = t.sells or {}, recipes = t.recipes or {} }
end
local function Offer(price, qty, total, at, complete)
  return { price = price, qty = qty, listings = 1, total = total or qty, at = at or FX.NOW - 300, complete = complete ~= false, scope = "full" }
end
local function Go(s, picks)
  local rows = MT.Rows(s.entries, FX.CraftHave(s), FX.CraftStock(s))
  return Sh.Plan(FX.PlanInput(s, rows, { picks = picks })), rows
end
local function Find(plan, item, kind)
  for _, r in ipairs(plan.rows) do if r.item == item and (kind == nil or r.kind == kind) then return r end end
end
local function Need(item, qty) return { { crafts = qty, mats = { { item = item, qty = 1 } } } } end
local function Recipe(id, out, lo, hi, mats) return { id = id, name = "R" .. id, outItem = out, outMin = lo, outMax = hi, mats = mats } end

do
  -- vendor stack of 10 at 100, 12 needed: 2 purchases = 200 with 8 left over; the auction house: 12 x 25 = 300 (12 <= 20 at that price)
  local s = Hand{ entries = Need(1, 12), vendor = { [1] = { p = 100, s = 10, a = -1, at = FX.NOW - 100, npc = 1 } }, auction = { [1] = Offer(25, 20, 30) } }
  local plan = Go(s)
  local r = Find(plan, 1, "buy")
  Same(r.suggested, "vendor"); Same(r.cash, 200); Same(r.surplus, 8, "whole stacks: 20 bought for 12 needed"); Same(plan.totals.cash, 200)
  Same(r.options.auction.cost, 300, "the auction house is the other option")
  -- the player's choice is used (and the suggestion stays what it was)
  plan = Go(s, { [1] = "auction" })
  r = Find(plan, 1, "buy")
  Same(r.source, "auction"); Same(r.picked, true); Same(r.cash, 300); Same(r.suggested, "vendor"); Same(plan.totals.cash, 300)
  -- a tie goes to the vendor: 12 x 25 = 300 on both sides
  s.vendor[1] = { p = 25, s = 1, a = -1, at = FX.NOW - 100 }
  Same(Find(Go(s), 1, "buy").suggested, "vendor", "equal cost: vendor, then auction, then making")
  -- the merchant had too few when seen (10 in stock, 20 would be bought): no cost, so the auction house is suggested
  s.vendor[1] = { p = 100, s = 10, a = 10, at = FX.NOW - 100 }
  r = Find(Go(s), 1, "buy")
  Same(r.options.vendor.state, "limited"); Same(r.options.vendor.cost, nil); Same(r.suggested, "auction")
  -- a merchant is known, its price never seen: that is information, not a cost
  s.vendor = {}; s.sells = { [1] = true }
  r = Find(Go(s), 1, "buy")
  Same(r.options.vendor.state, "noprice"); Same(r.suggested, "auction"); Same(Sh.Explain(r), "Only the auction house has a price.")
  Same(Sh.WhyNot(r, "vendor"), nil, "it may still be chosen: the cost is then counted as missing, not as zero")
  local chosen = Go(s, { [1] = "vendor" })
  Same(Find(chosen, 1, "buy").cash, nil); Same(chosen.totals.missing, 1); Same(chosen.totals.cash, 0)
end

do
  -- quantity beyond the cheapest listing: 10 wanted, 2 at the cheapest price (10), 50 listed. The estimate is 10 x 10 = 100, the LEAST it could
  -- cost; it is not replaced by the saved next-higher price (15: 2 x 10 + 8 x 15 = 140), and it is flagged everywhere it appears
  local a = Offer(10, 2, 50); a.next = 15
  local s = Hand{ entries = Need(1, 10), auction = { [1] = a } }
  local plan = Go(s)
  local r = Find(plan, 1, "buy")
  Same(r.cash, 100, "price x quantity"); Same(r.estimate, true); Same(plan.totals.estimate, true); Same(r.options.auction.state, "estimate")
  Check(r.uncertain and r.uncertain:find("estimate"), "the row says it is an estimate")
  Same(plan.totals.cash, 100, "the total includes it and says so (totals.estimate)")
  -- exactly the quantity at the cheapest price is a listed price, not an estimate
  s.entries = Need(1, 2)
  r = Find(Go(s), 1, "buy")
  Same(r.cash, 20); Check(not r.estimate, "2 are listed at 10: exact")
  -- not enough listed: no cost, never a cheaper-looking zero
  s.entries = Need(1, 51)
  local p2 = Go(s)
  r = Find(p2, 1, "buy")
  Same(r.cash, nil); Same(r.options.auction.state, "few"); Same(p2.totals.missing, 1); Same(p2.totals.cash, 0)
  -- an old or partial scan is used as it is and labelled: age does not change the cost
  s.entries = Need(1, 2); s.auction[1] = Offer(10, 2, 50, FX.NOW - 40 * 86400, false)
  r = Find(Go(s), 1, "buy")
  Same(r.cash, 20, "a 40-day-old price is still the price"); Same(r.at, FX.NOW - 40 * 86400, "...and says when it was seen")
  Same(Go(s).totals.incomplete, true, "a price from a scan that was not complete is flagged in the totals")
end

do
  -- make or buy: 5 X are short. Auction X costs 1000 each (5000). The recipe: 1 X from 2 Y; Y costs 100 (exact up to 50 listed)
  -- 5 crafts need 10 Y = 1000 to buy: making (1000) beats buying (5000)
  local X, Y = 5, 6
  local s = Hand{ entries = Need(X, 5), auction = { [X] = Offer(1000, 9, 9), [Y] = Offer(100, 50, 50) }, recipes = { [X] = { Recipe(900, X, 1, 1, { { item = Y, qty = 2 } }) } } }
  local plan = Go(s)
  local r = Find(plan, X, "make")
  Check(r, "X is made"); Same(r.make.crafts, 5); Same(r.make.cost, 1000); Same(r.make.cash, 1000); Same(r.options.auction.cost, 5000)
  Same(Find(plan, Y, "buy").qty, 10, "the reagents are bought, once, for the whole quantity"); Same(plan.totals.cash, 1000); Same(plan.totals.makes, 1)
  -- the same Y owned (10 in the bags): making costs no cash, but owned reagents are valued at what they would cost (10 x 100 = 1000)
  s.bags[Y] = 10
  plan = Go(s)
  r = Find(plan, X, "make")
  Same(r.make.cash, 0); Same(r.make.cost, 1000, "owning them does not make them free"); Same(plan.totals.cash, 0); Same(plan.totals.missing, 0); Same(plan.totals.priced, 0)
  -- ... so if buying costs less than that valuation, it buys, though making would cost no cash at all (a documented basis, not a bug)
  s.auction[X] = Offer(150, 9, 9)
  plan = Go(s)
  Check(Find(plan, X, "buy") and not Find(plan, X, "make"), "750 to buy is below the 1000 value of the owned reagents")
  Same(plan.totals.cash, 750)
  -- a reagent that is owned and has no known price at all: the make cost cannot be valued, so making is not suggested even though it costs no cash
  s.bags[Y] = 10; s.auction[Y] = nil
  plan = Go(s)
  r = Find(plan, X, "buy")
  Check(r, "bought"); Same(r.cash, 750)
  Same(Find(plan, X, "buy").options.make.cost, nil, "the economic cost of making it is not known")
  Same(Find(plan, X, "buy").options.make.cash, 0, "...though its cash cost is known to be zero")
end

do
  local X, Y, Z = 5, 6, 7
  local base = function() return Hand{ entries = Need(X, 5), auction = { [X] = Offer(1, 9999, 9999), [Y] = Offer(1, 9999, 9999) } } end
  local function WhyNot(recipe, entries)
    local s = base()
    if entries then s.entries = entries end
    s.recipes = { [X] = { recipe } }
    local r = Find(Go(s), X, "buy")
    return r.options.make.state, r.suggested
  end
  Same(WhyNot(Recipe(1, X, 1, 2, { { item = Y, qty = 1 } })), "range", "a range of output is never suggested")
  Same(WhyNot(Recipe(1, X, nil, nil, { { item = Y, qty = 1 } })), "noamount")
  Same(WhyNot(Recipe(1, X, 1, 1, {})), "unsupported", "materials TwichUI cannot count")
  Same(WhyNot({ id = 1, name = "R", outItem = X, outMin = 1, outMax = 1 }), "unsupported")
  Same(WhyNot(Recipe(1, X, 1, 1, { { item = X, qty = 1 } })), "circular", "a recipe that uses what it makes")
  Same(WhyNot(Recipe(1, X, 1, 1, { { item = Y, qty = 1 } }), { { crafts = 999, mats = { { item = X, qty = 6 } } } }), "toomany", "5994 crafts > 999 in one entry")
  -- the other states do not make anything unless they can be done; a usable recipe with cheap reagents is suggested when it is cheaper
  local st, sug = WhyNot(Recipe(1, X, 1, 1, { { item = Y, qty = 1 } }), Need(X, 5))
  Same(st, "ok"); Same(sug, "auction", "equal cost 5 = 5: the auction house wins before making")
  -- chain: X and Y are both short and both makeable; X (the lower item number) is made, from Y, so Y itself may not be made
  local s = Hand{ entries = { { crafts = 3, mats = { { item = X, qty = 1 }, { item = Y, qty = 1 } } } },
    auction = { [X] = Offer(1000, 9, 9), [Y] = Offer(100, 9, 9), [Z] = Offer(1, 99, 99) },
    recipes = { [X] = { Recipe(1, X, 1, 1, { { item = Y, qty = 1 } }) }, [Y] = { Recipe(2, Y, 1, 1, { { item = Z, qty = 1 } }) } } }
  local plan = Go(s)
  Check(Find(plan, X, "make"), "X is made"); Check(Find(plan, Y, "buy"), "Y is bought")
  Same(Find(plan, Y, "buy").options.make.state, "chain", "one level only: a material that is a reagent of a made material is not made in turn")
  Same(Find(plan, Y, "buy").qty, 6, "3 for the queue and 3 as reagents of X")
  Same(plan.totals.cash, 600, "6 Y at 100 (X is made from 3 of them); Y's own recipe would have cost 3 but is not allowed")
end

do
  -- shared requirements: two entries both need A (2 x 3 + 1 x 4 = 10); the 6 in the bags are applied once: 4 short, one row
  local s = Hand{ entries = { { crafts = 2, mats = { { item = A, qty = 3 } } }, { crafts = 1, mats = { { item = A, qty = 4 } } } }, bags = { [A] = 6 }, auction = { [A] = Offer(7, 10, 10) } }
  local plan, rows = Go(s)
  Same(#rows, 1); Same(rows[1].need, 10); Same(rows[1].short, 4); Same(Find(plan, A, "buy").cash, 28, "4 x 7")
  -- incomplete pricing: one priced item and one with no price anywhere; the total adds only what is priced and says what is missing
  s = Hand{ entries = { { crafts = 1, mats = { { item = A, qty = 4 }, { item = B, qty = 2 } } } }, auction = { [A] = Offer(7, 10, 10) } }
  plan = Go(s)
  Same(plan.totals.cash, 28); Same(plan.totals.priced, 1); Same(plan.totals.missing, 1, "B has no price: counted, not zero"); Same(Find(plan, B, "buy").cash, nil)
  Check(Sh.Explain(Find(plan, B, "buy")):find("No price known"), "and the row says so")
  -- a known zero: everything is in the bags. Nothing to buy, nothing missing, nothing unknown.
  s = Hand{ entries = { { crafts = 1, mats = { { item = A, qty = 4 } } } }, bags = { [A] = 4 } }
  plan = Go(s)
  Same(#plan.rows, 0); Same(plan.totals.cash, 0); Same(plan.totals.missing, 0); Same(plan.unknownBags, 0, "a zero that is known")
  -- ... against a zero that is NOT known: the bag count could not be read. The totals still say 0, so unknownBags is the only carrier.
  s.unknown = { [A] = true }; s.bags = {}
  plan = Go(s)
  Same(#plan.rows, 0); Same(plan.totals.cash, 0); Same(plan.totals.missing, 0); Same(plan.unknownBags, 1, "a zero that is not known is flagged")
  -- stored materials are collected, never bought: 3 in the bank, 4 needed, 1 bought
  s = Hand{ entries = { { crafts = 1, mats = { { item = A, qty = 4 } } } }, bank = { [A] = 3 }, auction = { [A] = Offer(7, 10, 10) } }
  plan = Go(s)
  Same(Find(plan, A, "collect").qty, 3); Same(Find(plan, A, "collect").where, "bank"); Same(Find(plan, A, "buy").qty, 1); Same(plan.totals.cash, 7)
  Same(plan.totals.collect, 1)
end

do
  -- the planner decides ONE MATERIAL AT A TIME and prices each bought item once at the end. That is not a search for the cheapest plan:
  -- V is short 11 (vendor 200 per stack of 10; auction 40 each), F is short 2 (auction 2 each = 4; a recipe makes 2 F from 3 V).
  --   at F's turn: buy 4, or make 1 craft whose 3 V cost 120 at the auction house -> buy.   Plan: V 2 stacks 400 + F 4 = 404.
  --   but making F adds 3 V to the vendor order: 14 V is still 2 stacks = 400, F is free. The exhaustive best is 400.
  local V, F = 7, 8
  local s = Hand{ entries = { { crafts = 1, mats = { { item = V, qty = 11 }, { item = F, qty = 2 } } } },
    vendor = { [V] = { p = 200, s = 10, a = -1, at = FX.NOW - 10 } }, auction = { [V] = Offer(40, 50, 50), [F] = Offer(2, 9, 9) },
    recipes = { [F] = { Recipe(77, F, 2, 2, { { item = V, qty = 3 } }) } } }
  local plan, rows = Go(s)
  Same(plan.totals.cash, 404, "the plan buys F")
  Same(Find(plan, F, "buy").options.make.cost, 120, "making F looked like 120 against 4")
  local best
  REF.Enumerate(s, REF.Rows(s.entries, FX.CraftHave(s), FX.CraftStock(s)), 100, function(assign, res)
    if res.feasible and (not best or res.cash < best) then best = res.cash end
  end)
  Same(best, 400, "the exhaustive best is 4 copper cheaper: a limitation of deciding one material at a time, not a miscalculation")
  -- forcing the better choice works and costs exactly what the model says
  local forced = Go(s, { [F] = "make" })
  Same(forced.totals.cash, 400, "the player can reach it with a pick")
end


do
  -- DECISION ORDER. The source chosen for a material at its turn is kept for the combined purchase, even when a reagent of a made material
  -- raises the quantity to where another source is cheaper. P is short 6 (auction 2 each = 12, vendor 13 for a stack of 8: auction at its turn);
  -- Q is made from 2 P (Q alone costs 1000 to buy), so 8 P are bought in all: the auction house then costs 16 and the vendor 13.
  local P, Q = 5, 6
  local s = Hand{ entries = { { crafts = 1, mats = { { item = P, qty = 6 }, { item = Q, qty = 1 } } } },
    vendor = { [P] = { p = 13, s = 8, a = -1, at = FX.NOW - 10 } }, auction = { [P] = Offer(2, 6, 10), [Q] = Offer(1000, 9, 9) },
    recipes = { [Q] = { Recipe(300, Q, 1, 1, { { item = P, qty = 2 } }) } } }
  local plan = Go(s)
  local r = Find(plan, P, "buy")
  Same(r.qty, 8); Same(r.extra, 2); Same(r.source, "auction", "the source of its turn is kept"); Same(r.cash, 16, "8 x 2: the least the auction house could charge")
  Same(r.options.vendor.cost, 13, "the vendor is cheaper for the 8")
  Same(Go(s, { [P] = "vendor" }).totals.cash, 13, "the player can pick it")

  -- A pick that can no longer be used is reported, and the item is still decided first. X (5) is made from Y (6) and Y has a recipe from Z (7):
  -- by default X is decided first and made, so Y is bought; a pick for a vendor Y does not have moves Y to the front, where Y is made, and X is bought.
  local X, Y, Z = 5, 6, 7
  s = Hand{ entries = { { crafts = 3, mats = { { item = X, qty = 1 }, { item = Y, qty = 1 } } } },
    auction = { [X] = Offer(1000, 9, 9), [Y] = Offer(100, 9, 9), [Z] = Offer(1, 99, 99) },
    recipes = { [X] = { Recipe(1, X, 1, 1, { { item = Y, qty = 1 } }) }, [Y] = { Recipe(2, Y, 1, 1, { { item = Z, qty = 1 } }) } } }
  plan = Go(s)
  Check(Find(plan, X, "make") and Find(plan, Y, "buy"), "by default X is made")
  local lostPlan = Go(s, { [Y] = "vendor" })
  Same(Find(lostPlan, Y, "make") ~= nil, true, "the lost pick still decides Y first, and Y is made")
  Check(Find(lostPlan, X, "buy") and not Find(lostPlan, X, "make"), "so X can no longer be made")
  Same(Find(lostPlan, Y, "make").pickLost, "vendor", "and the row says the choice was lost")
  Check(lostPlan.totals.cash ~= plan.totals.cash, "(a lost pick does change the rest of the plan: " .. plan.totals.cash .. " against " .. lostPlan.totals.cash .. ")")
end

do
  -- BOUNDARIES that random data rarely meets. Break-even: costs 5 x 7 = 35, sells 1 x 35 = 35: profit exactly 0 is neither a profit nor a loss.
  local lookup = { [1] = { price = 7, qty = 9, total = 20, at = FX.NOW, complete = true }, [2] = { price = 35, qty = 1, total = 5, at = FX.NOW, complete = true } }
  local rows = Op.Rows({ { id = 1, name = "Even", prof = 1, outItem = 2, outMin = 1, outMax = 1, mats = { { item = 1, qty = 5 } } },
    { id = 2, name = "Gain", prof = 1, outItem = 2, outMin = 2, outMax = 2, mats = { { item = 1, qty = 5 } } } }, function(i) return lookup[i] end, nil)
  Same(rows[1].est.profitLow, 0); Same(Op.Summary(rows).profitable, 1, "only the recipe that gains is profitable; break-even is not")
  local kept = Op.Select(rows, { sort = "profit", desc = true, profitOnly = true })
  Same(#kept, 1); Same(kept[1].rec.id, 2)
  -- exactly 999 crafts fit in one queue entry (the limit is "more than 999"): 999 X short, a recipe making 1 each is still offered
  local X, Y = 5, 6
  local s = Hand{ entries = Need(X, 999), auction = { [X] = Offer(10, 9999, 9999), [Y] = Offer(1, 9999, 9999) }, recipes = { [X] = { Recipe(900, X, 1, 1, { { item = Y, qty = 1 } }) } } }
  local r = Find(Go(s), X, "make") or Find(Go(s), X, "buy")
  Same(r.options.make.state, "ok", "999 crafts is allowed"); Same(r.options.make.crafts, 999)
  s.entries = { { crafts = 999, mats = { { item = X, qty = 1 } } }, { crafts = 1, mats = { { item = X, qty = 1 } } } }
  Same(Find(Go(s), X, "buy").options.make.state, "toomany", "1000 crafts is not")
end

do
  -- ROUNDING LIMITS of the estimates (current behaviour, pinned so that a change is a conscious step). The cut and the value of an owned reagent
  -- are rounded to the nearest copper in floating point; an amount exactly halfway between two coppers can come out ONE COPPER LOW for some
  -- rates and stack sizes. 5, 10, 15, 20, 25 and 30 % are exact (checked up to 20,000,000 copper); 35 % is not. Which way a half copper should
  -- round is not known (the real cut is unconfirmed), so this is a limit and not a fix.
  Same(PR.Cut(90, 0.35), 31, "90 x 0.35 = 31.5 exactly, rounds to 31 (half up would be 32)")
  Same(PR.Cut(90, 0.05), 5, "90 x 0.05 = 4.5 rounds up to 5")
  Same(REF.RoundHalfUp(90 * 350, 1000), 32, "the model rounds a half up")
  Same(PR.Cut(1500, 0.009), 13, "1500 x 0.009 = 13.5 rounds to 13")
  -- value of 27 owned items sold in stacks of 6 for 13: 27 x 13 / 6 = 58.5
  local X, Y = 5, 6
  local s = Hand{ entries = Need(X, 5), bags = { [Y] = 27 }, vendor = { [Y] = { p = 13, s = 6, a = -1, at = FX.NOW } }, auction = { [X] = Offer(100000, 9, 9) },
    recipes = { [X] = { Recipe(900, X, 1, 1, { { item = Y, qty = 6 } }) } } }
  local rows = MT.Rows(s.entries, FX.CraftHave(s), FX.CraftStock(s))
  local plan = Sh.Plan(FX.PlanInput(s, rows, { picks = { [X] = "make" } }))
  -- 5 crafts need 30 Y: 27 owned (value 58.5), 3 bought (1 stack = 13)
  local mk = Find(plan, X, "make").make
  Same(mk.reagents[1].owned, 27); Same(mk.reagents[1].value, 58, "58.5 rounds to 58 in floating point (59 half up)"); Same(mk.cash, 13)
end

---------------------------------------------------------------------------
-- G. Characterized limits of the one-level planner (the contract as it is)
---------------------------------------------------------------------------
do
  -- the combined-materials credit looks at no more than MAX_GRAPH (60) entries; the real queue holds 30 (W.MAX_QUEUE), so this is unreachable
  Same(REF.MAX_GRAPH, 60); Check(W.MAX_QUEUE <= REF.MAX_GRAPH, "the queue can never exceed the credit's bound")
  local entries = { { crafts = 1, mats = { { item = A, qty = 1 } } } }
  for i = 1, 60 do entries[#entries + 1] = { crafts = 1, mats = { { item = B, qty = 1 } }, outItem = A, outMin = 1, outMax = 1 } end
  local _, _, _, made = MT.Combine(entries)
  Same(made[A], nil, "past 60 entries no queued output is credited (unreachable from a real queue)")
  Same(select(4, REF.Combine(entries))[A], nil, "the model says the same")
end

if #found > 0 then
  for _, m in ipairs(found) do print(m) end
  error(#found .. " differences found (CRAFT_ALL)", 0)
end

print(("crafting reference: %d scenarios per family (%.1f s)\n  split %d, queues %d (%d rows; %d with a crafting circle, %d credited rows), stock %d (%d guild tabs),\n  shopping %d scenarios, %d sourcing choices compared with production (%d infeasible: refused by both), %d optimum comparisons:\n    same cost as the exhaustive best %d, higher on the documented basis (owned reagents valued) %d, higher because choices are made one at a time %d,\n    higher because a recipe's economic cost is unknown %d, left undecided (a recipe could make it, cost unknown) %d, too many choices to search %d,\n  estimates %d (%d fully priced, %d at a loss)"):format(
  N, os.clock() - clock0, stats.split, stats.queues, stats.queueRows, stats.cyclic, stats.credited, stats.stock, stats.stockTabs, stats.shop, stats.assignments, stats.infeasible,
  stats.optimum, stats.agree, stats.basis, stats.sequential, stats.unvalued, stats.undecided, stats.tooBig, stats.estimates, stats.ok, stats.negative))
for _, class in ipairs({ "basis", "sequential", "unvalued" }) do
  local e = examples[class]
  if e then print(("  e.g. %s: seed %d, the plan %d copper (%d unpriced) against %d (%d unpriced) for the cheapest combination"):format(class, e.seed, e.plan, e.planMissing, e.best, e.bestMissing)) end
end
print("PASSED test_workshop_crafting_reference")
