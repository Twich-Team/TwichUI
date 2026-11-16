-- TwichUI Test Lab: crafting reference cases (category "core", class pure, they need the Workshop)
-- A SMALL, BOUNDED selection of the comparisons that tests/test_workshop_crafting_reference.lua runs by the hundred offline: a handful of fixed
-- seeds, so the client's Lua and plain Lua 5.1 can be compared on the same scenarios. All data is made up (TL.Fixtures, seeds typed below);
-- production functions get explicit inputs only (Materials.Rows, W.Split, Shopping.Plan, Prices.Quote/Estimate), nothing reads or writes saved
-- data, and no stock, price or queue of the player is involved. To reproduce a failure offline run the test with CRAFT_SCENARIOS=1000
-- CRAFT_SEED=<the seed in the message>.
--
-- Seeds: allocation and materials 7500001..7500024, shopping 7510001..7510008, economics 7520001..7520020.

local R = TwichUI
local TL = R.TestLab
local FX, REF = TL.Fixtures, TL.Reference

local function Pure(id, run) TL.Case{ id = id, cat = "core", class = "pure", needs = { "workshop" }, budget = 5, run = run } end

local function Flat(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Flat(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end

local FIELDS = { "item", "need", "made", "madeRange", "have", "short", "bank", "guild", "fromBank", "fromGuild" }
local function RowsText(rows)
    local out = {}
    for _, r in ipairs(rows) do
        local one = {}
        for _, f in ipairs(FIELDS) do one[#one + 1] = tostring(r[f]) end
        out[#out + 1] = table.concat(one, " ")
    end
    return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Held counts that are not counts. Materials.Rows and Stock.Craft judge the bag count they are handed with W.Count (a whole number from 0, finite
-- decided without a comparison): anything else is "unknown", never a count, and never makes a craft ready. Their input is the game's item
-- count (Observe.BagCount, the same boundary) or nil. This feeds malformed values anyway, with explicit inputs, and ASSERTS every one is unknown.
-- History: the first client run (Forever 1.60.1 build 70888) showed `numeric.held.inf=have inf short 0 craft ready`: the old guard
-- `h ~= h or h < 0` let a positive infinity through on desktop Lua as well. M6.1 replaced it.
---------------------------------------------------------------------------
Pure("numeric.guards.held-counts", function(t)
    local W = t.W
    local zero = 0
    local nan = zero / zero
    local forms = { { "nan", nan, true }, { "nan-literal", 0 / 0, true }, { "nan-negated", -nan, true }, { "string", "5", true }, { "negative", -1, true },
        { "-inf", -math.huge, true }, { "inf", math.huge, true }, { "inf-minus-inf", math.huge - math.huge, true },
        { "fraction", 2.5, true }, { "fraction-small", 0.5, true }, { "over-limit", 2 ^ 31, true }, { "huge", 1e300, true },
        { "boolean", true, true }, { "table", {}, true },
        { "negative-zero", -0 }, { "zero", 0 }, { "five", 5 }, { "limit", 2147483647 } }
    local mats = { { item = 1001, qty = 3 } }
    local entries = { { crafts = 1, mats = mats } }
    for _, f in ipairs(forms) do
        local v = f[2]
        local rows = W.Materials.Rows(entries, function() return v end)
        local craft = W.Stock.Craft(mats, function() return v end, nil)
        local row = rows[1]
        t:Fact("numeric.held." .. f[1], ("have %s short %s craft %s"):format(tostring(row.have), tostring(row.short), tostring(craft.state)))
        if f[3] then
            t:Check(row.have == nil and row.short == nil, f[1] .. " as a bag count: Materials.Rows must call it unknown (have and short nil)")
            t:Check(craft.state == "unknown", f[1] .. " as a bag count: Stock.Craft must call it unknown, never ready")
        end
        if f[1] == "five" then
            t:Same(row.have, 5, "an ordinary count is kept"); t:Same(row.short, 0, "and covers a need of 3"); t:Same(craft.state, "ready", "so the craft is ready")
        elseif f[1] == "limit" then
            t:Same(row.have, 2147483647, "the largest accepted count is kept"); t:Same(craft.state, "ready", "and a craft is ready")
        elseif f[1] == "zero" or f[1] == "negative-zero" then
            t:Same(row.short, 3, f[1] .. ": nothing held leaves the whole need short"); t:Same(craft.state, "short", f[1] .. ": and the craft is short")
        end
    end
    -- unknown must not become zero: a nil count leaves short nil (not the whole need), and the summary is "partial"
    local _, sum = W.Materials.Rows(entries, function() return math.huge end)
    t:Same(sum.state, "partial", "an infinite count leaves the summary partial (unknown), not short and not ready")
    t:Same(sum.unknownItems, 1, "and counts the item as unknown")
    -- the bank and guild bank stay separate: an invalid bag count does not hide what the bank holds
    local rows = W.Materials.Rows(entries, function() return math.huge end, function() return 2, 1 end)
    t:Check(rows[1].have == nil and rows[1].short == nil and rows[1].fromBank == nil, "stock counts are not applied to an unknown bag count")
    t:Note("inputs are made-up; production sees only the game's item counts. The same boundary in Observe.BagCount (W.Count) is not called here because it reads the game's C_Item; tests/test_workshop_stock_counts.lua calls it with a stand-in.")
end)

---------------------------------------------------------------------------
-- Allocation and combined materials
---------------------------------------------------------------------------
Pure("crafting.reference.allocation", function(t)
    local W = t.W
    if not (FX and REF and FX.Crafting) then t:Skip("the fixtures or the reference model are not loaded") end
    for i = 1, 24 do
        local seed = 7500000 + i
        local rng = FX.Rng(seed)
        local want, bags, bank, guild = rng:Int(0, 40), rng:Int(0, 15), rng:Int(0, 15), rng:Int(0, 15)
        local b, k, g, rest = W.Split(want, bags, bank, guild)
        local ref = REF.Take(want, bags, bank, guild)
        t:Same(("%d,%d,%d,%d"):format(b, k, g, rest), ("%d,%d,%d,%d"):format(ref.bags, ref.bank, ref.guild, ref.missing), "seed " .. seed .. ": bags, bank, guild bank, missing")
        local scn = FX.Crafting(seed, { entries = 1 + i % 5 })
        local have, stock = FX.CraftHave(scn), FX.CraftStock(scn)
        local rows, sum = W.Materials.Rows(scn.entries, have, stock)
        local mrows, msum = REF.Rows(scn.entries, have, stock)
        t:Same(RowsText(rows), RowsText(mrows), "seed " .. seed .. ": rows")
        t:Same(Flat(sum), Flat(msum), "seed " .. seed .. ": summary")
        t:Yield()
    end
end)

---------------------------------------------------------------------------
-- The shopping plan: the cost of every sourcing choice, forced through the player's picks
---------------------------------------------------------------------------
Pure("crafting.reference.shopping", function(t)
    local W = t.W
    if not (FX and REF and FX.Crafting) then t:Skip("the fixtures or the reference model are not loaded") end
    local compared = 0
    for i = 1, 8 do
        local seed = 7510000 + i
        local scn = FX.Crafting(seed, { entries = 2 + i % 3 })
        local rows = W.Materials.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))
        local mrows = REF.Rows(scn.entries, FX.CraftHave(scn), FX.CraftStock(scn))
        REF.Enumerate(scn, mrows, 64, function(assign, ref)
            local picks, cand = {}, {}
            for item, a in pairs(assign) do
                if type(a) == "table" then picks[item] = "make" cand[item] = { a.make } else picks[item] = a end
            end
            local plan = W.Shopping.Plan(FX.PlanInput(scn, rows, { picks = picks, recipes = function(item) return cand[item] or scn.recipes[item] or {} end }))
            local lost = false
            for _, r in ipairs(plan.rows) do if r.pickLost ~= nil then lost = true end end
            if ref.feasible then
                local tot = plan.totals
                t:Same(("%.0f,%d,%d,%s,%s,%d"):format(tot.cash, tot.priced, tot.missing, tostring(tot.estimate), tostring(tot.incomplete), tot.makes),
                    ("%.0f,%d,%d,%s,%s,%d"):format(ref.cash, ref.priced, ref.missing, tostring(ref.estimate), tostring(ref.incomplete), ref.makes), "seed " .. seed .. ": totals")
                t:Check(not lost, "seed " .. seed .. ": every choice that can be done is followed")
            else
                t:Check(lost, "seed " .. seed .. ": a choice that cannot be done is not followed (" .. tostring(ref.why) .. ")")
            end
            compared = compared + 1
        end)
        t:Yield()
    end
    t:Fact("crafting.shopping.choices", compared)
end)

---------------------------------------------------------------------------
-- The craft estimate
---------------------------------------------------------------------------
Pure("crafting.reference.estimate", function(t)
    local W = t.W
    local PR = W.Prices
    if not (FX and REF and FX.Economy) then t:Skip("the fixtures or the reference model are not loaded") end
    local function Text(e)
        local f = {}
        for _, k in ipairs({ "state", "why", "cost", "missing", "outMin", "outMax", "unit", "sellLow", "sellHigh", "netLow", "netHigh", "profitLow", "profitHigh", "oldest", "incomplete", "cheapest" }) do
            f[#f + 1] = k .. "=" .. tostring(e[k])
        end
        for _, m in ipairs(e.mats) do f[#f + 1] = ("%d:%s:%s:%s"):format(m.item, tostring(m.total), tostring(m.cheapest), tostring(m.unavailable)) end
        return table.concat(f, " ")
    end
    for i = 1, 20 do
        local seed = 7520000 + i
        local eco = FX.Economy(seed)
        local lookup = function(item) return eco.lookup[item] end
        local rate = eco.cut and eco.cut / 1000 or nil
        for _, rec in ipairs(eco.recipes) do
            t:Same(Text(PR.Estimate(rec, lookup, rate)), Text(REF.Estimate(rec, eco.lookup, eco.cut)), ("seed %d recipe %d"):format(seed, rec.id))
        end
        for item, p in pairs(eco.lookup) do
            local q = PR.Quote(p, p.qty + 1)
            local want = REF.BuyOptions({ auction = { [item] = p }, vendor = {}, sells = {} }, item, p.qty + 1).auction
            t:Same(q.state .. tostring(q.cost), want.state .. tostring(want.cost), ("seed %d item %d: one more than the cheapest listing"):format(seed, item))
        end
        t:Yield()
    end
end)

---------------------------------------------------------------------------
-- The multilevel crafting planner (P1, CraftPlanner.lua; docs/workshop/multilevel-crafting-planner.md). Made-up graphs with explicit inputs:
-- nothing reads the player's queue, stock, saved source choices or auction data, and the cost service is a stand-in (REF.ChainCostFn) so no
-- saved market is built. The hand-worked numbers are the ones tests/test_workshop_craftplanner.lua section A checks offline.
-- Seeds: chains 7540001..7540016.
---------------------------------------------------------------------------
local function Planner(t)
    local CP = t.W.CraftPlanner
    if not CP then t:Skip("the multilevel planner (CraftPlanner.lua) is not loaded") end
    return CP
end
local function E(item, qty, crafts, id) return { id = id or (900 + item), name = "Final", crafts = crafts or 1, mats = { { item = item, qty = qty } }, outItem = 9999, outMin = 1, outMax = 1 } end
local function Rec(id, out, per, mats)
    local m = {}
    for i = 1, #mats, 2 do m[#m + 1] = { item = mats[i], qty = mats[i + 1] } end
    return { id = id, name = "R" .. id, outItem = out, outMin = per, outMax = per, mats = m }
end
local function Look(price) return { price = price, qty = 1000, listings = 1, total = 1000, at = 1, complete = true } end
local function Vend(p, s) return { p = p, s = s or 1, a = -1, at = 1, npc = 1 } end
local function Inp(t)
    local bags, bank = t.bags or {}, t.bank or {}
    return { entries = t.entries, picks = t.picks, have = function(i) return bags[i] or 0 end, stock = function(i) return bank[i] or 0, 0 end,
        auction = function(i) return (t.lookup or {})[i] end, cost = t.cost, vendor = function(i) return (t.vendor or {})[i] end, sells = function() return false end,
        recipes = function(i) return (t.recipes or {})[i] or {} end }
end
local function Line(r, item) for _, l in ipairs(r.items) do if l.item == item then return l end end end
local TWO = { lookup = { [110] = Look(50), [120] = Look(30) }, vendor = { [200] = Vend(4) },
    recipes = { [110] = { Rec(510, 110, 1, { 120, 1, 200, 1 }) }, [120] = { Rec(520, 120, 2, { 200, 2 }) } } }
local function Two(extra) local t = { entries = { E(110, 2) } } for k, v in pairs(TWO) do t[k] = v end for k, v in pairs(extra or {}) do t[k] = v end return t end

Pure("crafting.planner.two-level", function(t)
    local CP = Planner(t)
    -- 2 A: buy 100; make A, buy B 68; make both: R 4 x 4 = 16, B crafted before A
    local r = CP.Plan(Inp(Two()))
    t:Same(r.summary.economic.low, 16, "two levels: make both for 16")
    t:Same(r.crafts[1].item .. ">" .. r.crafts[2].item, "120>110", "B is crafted before A")
    t:Same(Line(r, 200).need, 4, "R's demand is combined over both crafts")
    t:Check(r.summary.proven, "the plan is the proven best of the options considered")
    t:Fact("crafting.planner.two-level", ("econ %d cash %d crafts %d %s"):format(r.summary.economic.low, r.summary.cash.low, r.summary.crafts, r.summary.optimization))
end)

Pure("crafting.planner.shared-stock", function(t)
    local CP = Planner(t)
    -- R: 3 in bags, 2 in the bank; demand 4 takes bags 3, bank 1; nothing bought; the owned R are still worth 16
    local r = CP.Plan(Inp(Two{ bags = { [200] = 3 }, bank = { [200] = 2 } }))
    local o = Line(r, 200).owned
    t:Same(o.bags .. "/" .. o.bank, "3/1", "bags first, then the bank, once for both crafts")
    t:Same(r.summary.cash.low, 0, "no cash"); t:Same(r.summary.economic.low, 16, "owned materials are not free")
    t:Same(#r.collect, 1, "one collect row")
end)

Pure("crafting.planner.cycle", function(t)
    local CP = Planner(t)
    -- X makes 3 from 1 Y, Y makes 3 from 1 X: making both would settle at no cost and is refused; make X, buy Y (20)
    local r = CP.Plan(Inp{ entries = { E(410, 1) }, lookup = { [410] = Look(50), [411] = Look(20) },
        recipes = { [410] = { Rec(710, 410, 3, { 411, 1 }) }, [411] = { Rec(711, 411, 3, { 410, 1 }) } } })
    t:Same(r.summary.economic.low, 20, "a circle is never a plan, even when it looks free")
    t:Same(Line(r, 411).alternatives[1].why, "circular", "and the circle is named")
    -- the same circle with another route for Y (from R at 1): make X and Y from R
    r = CP.Plan(Inp{ entries = { E(176, 1) }, lookup = { [176] = Look(50), [177] = Look(20) }, vendor = { [178] = Vend(1) },
        recipes = { [176] = { Rec(576, 176, 1, { 177, 1 }) }, [177] = { Rec(577, 177, 1, { 176, 1 }), Rec(578, 177, 1, { 178, 1 }) } } })
    t:Same(r.summary.economic.low, 1, "the route that is not circular is used")
end)

Pure("crafting.planner.alternatives", function(t)
    local CP = Planner(t)
    -- two recipes: 2 R (5) = 10 or 1 S (6) = 6: the second, the first 4 dearer
    local r = CP.Plan(Inp{ entries = { E(185, 1) }, lookup = { [185] = Look(100) }, vendor = { [186] = Vend(5), [187] = Vend(6) },
        recipes = { [185] = { Rec(585, 185, 1, { 186, 2 }), Rec(586, 185, 1, { 187, 1 }) } } })
    t:Same(r.crafts[1].recipe, 586, "the cheaper recipe"); t:Same(Line(r, 185).alternatives[2].difference, 4, "the other is 4 dearer")
    -- three queued crafts each need 1 I (4 at auction, or 3 from 1 R at 9): together one craft for 9 < 12
    local entries = { E(140, 1, 1, 701), E(140, 1, 1, 702), E(140, 1, 1, 703) }
    r = CP.Plan(Inp{ entries = entries, lookup = { [140] = Look(4) }, vendor = { [141] = Vend(9) }, recipes = { [140] = { Rec(540, 140, 3, { 141, 1 }) } } })
    t:Same(r.summary.economic.low, 9, "combined demand: one craft for all three")
end)

Pure("crafting.planner.ranges", function(t)
    local CP = Planner(t)
    local function Cost(a) return function(item, qty)
        if item == 312 then return { state = "exact", cost = 2 * qty, low = 2 * qty, high = 2 * qty } end
        if item ~= 311 then return { state = "none" } end
        if a == "range" then return { state = "range", low = 8 * qty, high = 11 * qty } end
        return { state = "estimate", low = 8 * qty, high = 99 * qty }
    end end
    local chain = { entries = { E(310, 1) }, lookup = { [311] = Look(8), [312] = Look(2) }, recipes = { [310] = { Rec(610, 310, 1, { 311, 1, 312, 1 }) } } }
    chain.cost = Cost("range")
    local r = CP.Plan(Inp(chain))
    t:Same(r.summary.economic.low .. ".." .. tostring(r.summary.economic.high), "10..13", "8-11 plus exactly 2 is 10 to 13")
    chain.cost = Cost("estimate")
    r = CP.Plan(Inp(chain))
    t:Same(r.summary.economic.low .. ".." .. tostring(r.summary.economic.high), "10..nil", "at least 8 plus 2: at least 10, no upper bound")
end)

Pure("crafting.planner.bounded", function(t)
    local CP = Planner(t)
    local w = { entries = {}, lookup = {}, vendor = { [349] = Vend(2), [350] = Vend(3) }, recipes = {} }
    for i = 1, 8 do
        local item = 340 + i
        w.entries[i] = E(item, i, 1, 800 + i)
        w.lookup[item] = Look(5 + i)
        w.recipes[item] = { Rec(640 + 2 * i, item, 1 + i % 2, { 349, 1 + i % 3 }), Rec(641 + 2 * i, item, 1, { 350, 1 }) }
    end
    local full = CP.Plan(Inp(w), { limits = { states = 1000000 } })
    t:Yield()
    local r = CP.Plan(Inp(w), { limits = { states = 10 } })
    t:Same(full.summary.optimization, "exhaustive", "the full search finishes")
    t:Same(r.summary.optimization, "bounded", "a search stopped at its limit says so"); t:Check(not r.summary.proven, "and is never called proven")
    t:Check(r.summary.economic.low >= full.summary.economic.low, "a limited search never beats the full one")
    t:Fact("crafting.planner.bounded", ("full %d (%d states) limited %d (%d states)"):format(full.summary.economic.low, full.summary.work.states, r.summary.economic.low, r.summary.work.states))
end)

Pure("crafting.planner.reference", function(t)
    local CP = Planner(t)
    if not (FX and FX.Chain and REF and REF.ChainPlan) then t:Skip("the chain fixtures or the reference model are not loaded") end
    local compared = 0
    for i = 1, 16 do
        local seed = 7540000 + i
        local scn = FX.Chain(seed)
        local inp = FX.ChainInput(scn, { cost = REF.ChainCostFn(scn) })
        for _, objective in ipairs({ "economic", "cash" }) do
            local ref = REF.ChainPlan(scn, { objective = objective })
            if ref.best then
                local r = CP.Plan(inp, { objective = objective })
                local k = ref.best.key
                t:Same(("%d/%.0f/%.0f/%s/%d"):format(r.summary.missing, r.summary.economic.low, r.summary.cash.low, tostring(r.summary.cash.high), r.summary.crafts),
                    ("%d/%.0f/%.0f/%s/%d"):format(k.missing, k.econ, k.cash, tostring(k.cashHigh), k.crafts), ("seed %d %s: totals"):format(seed, objective))
                for item, p in pairs(ref.best.per) do
                    local l = Line(r, item)
                    local src = p.rest == 0 and "owned" or p.source
                    t:Same(l and l.source, src, ("seed %d %s item %d: source"):format(seed, objective, item))
                end
                compared = compared + 1
            end
        end
        t:Yield()
    end
    t:Fact("crafting.planner.compared", compared)
    t:Check(compared >= 24, "most seeds compared: " .. compared)
end)

---------------------------------------------------------------------------
-- The multilevel strategy in the windows (P2, Strategy.lua; docs/workshop/multilevel-crafting-planner.md section 14). The same made-up graphs as above,
-- explicit inputs only: nothing reads the player's queue, stock, saved choices or auction data, and nothing here changes them. The jobs use a slot of their
-- own ("lab", dropped at the end), never the windows' slots, and never Strategy.Bump or Strategy.Reset (those would cancel the player's open plans).
---------------------------------------------------------------------------
local function Strat(t)
    local St = t.W.Strategy
    if not (St and t.W.CraftPlanner) then t:Skip("the strategy (Strategy.lua) is not loaded") end
    return St
end
-- Shopping-shaped rows from a plan: the adapter's input is the combined materials of the queue (Materials.Rows) and the planner's own input
local function Adapted(t, entries, extra)
    local W = t.W
    local inp = Inp(Two(extra))
    inp.entries = entries
    local have = function(i) return (inp.have or function() return 0 end)(i) end
    local mrows = W.Materials.Rows(entries, have)
    local plan = W.CraftPlanner.Plan(inp)
    return W.Strategy.Adapt(plan, { mrows = mrows, inp = inp, recById = function(id) for _, l in pairs(TWO.recipes) do for _, r in ipairs(l) do if r.id == id then return r end end end end }), plan
end
local function RowOf(list, item, kind) for _, r in ipairs(list.rows) do if r.item == item and (kind == nil or r.kind == kind) then return r end end end

Pure("crafting.strategy.adapter", function(t)
    Strat(t)
    -- 2 A (110) as in two-level: make A and B (120) from R (200): crafts 120 then 110, R bought 4 x 4 = 16; the rows are Shopping's shape
    local a, plan = Adapted(t, { E(110, 2) })
    t:Same(a.engine, "multilevel")
    local ma, mb = RowOf(a, 110, "make"), RowOf(a, 120, "make")
    t:Check(ma and mb, "both made materials are make rows")
    t:Same(mb.make.crafts .. "/" .. ma.make.crafts, "1/2", "B once (makes 2), A twice")
    local r = RowOf(a, 200, "buy")
    t:Same(r.qty .. "/" .. tostring(r.cash) .. "/" .. tostring(r.source), "4/16/vendor", "the reagent bought once, for the whole plan")
    t:Check(r.reagentOnly, "and it says it is only for making")
    t:Same(a.totals.cash, plan.summary.cash.low, "the spending is the planner's cash")
    t:Fact("crafting.strategy.adapter", ("rows %d makes %d cash %d"):format(#a.rows, a.totals.makes, a.totals.cash))
end)

Pure("crafting.strategy.shared-allocation", function(t)
    Strat(t)
    -- R: 3 in the bags, 2 in the bank; demand 4: bags 3, bank 1 collected, nothing bought; the economic cost still counts the owned R
    local W = t.W
    local entries = { E(110, 2) }
    local inp = Inp(Two{ bags = { [200] = 3 }, bank = { [200] = 2 } })
    inp.entries = entries
    local plan = W.CraftPlanner.Plan(inp)
    local a = W.Strategy.Adapt(plan, { mrows = W.Materials.Rows(entries, inp.have, inp.stock), inp = inp })
    local c = RowOf(a, 200, "collect")
    t:Check(c, "the bank's R is a collect row"); t:Same(c.where .. "/" .. c.qty, "bank/1")
    t:Check(RowOf(a, 200, "buy") == nil, "nothing is bought")
    t:Same(a.totals.cash, 0); t:Same(W.Strategy.Summary(plan, tostring).economic, "16", "owned materials are not free")
end)

Pure("crafting.strategy.queue-wide", function(t)
    Strat(t)
    -- two queued finals that both need A (110): planned together R is needed 8 over both, bought once; alone each needs 4 (and the 3 in the bags help only one)
    local W = t.W
    local both = { E(110, 2, 1, 901), E(110, 2, 1, 902) }
    local inp = Inp(Two{ bags = { [200] = 3 } })
    inp.entries = both
    local together = W.CraftPlanner.Plan(inp)
    inp.entries = { both[1] }
    local one = W.CraftPlanner.Plan(inp)
    t:Same(Line(together, 200).need, 8, "the demand is combined over the whole queue")
    t:Same(together.summary.cash.low, 20, "8 R - 3 owned = 5 bought at 4")
    -- one queued craft alone buys 4 R - 3 owned = 1 (4 cash); two such plans added up would count the same 3 owned R twice (8): together it is 20
    t:Same(one.summary.cash.low, 4, "one final alone: 1 R bought")
    t:Check(together.summary.cash.low > 2 * one.summary.cash.low, "the plans of the recipes are not added up: the owned stock is allocated once, over the whole queue")
    t:Fact("crafting.strategy.queue-wide", ("together cash %d, one cash %d"):format(together.summary.cash.low, one.summary.cash.low))
end)

Pure("crafting.strategy.stale-job", function(t)
    local St = Strat(t)
    local inp = Inp(Two())
    local make = function() return inp end
    inp.entries = { E(110, 2) }
    local state = St.Request("lab", "k1", make, true)
    t:Check(state == "ready" or state == "planning", "a request starts or finishes a job")
    St.Pump(nil, "lab")
    t:Check(St.Peek("lab", "k1") ~= nil, "the finished plan is kept for its own key")
    t:Check(St.Peek("lab", "k2") == nil, "and for no other key")
    -- a newer request of the slot replaces an unfinished older one: only the newer answer exists
    local big = { entries = {} }
    for k, v in pairs(inp) do big[k] = v end
    for i = 1, 30 do
        local mats = {}
        for j = 1, 16 do mats[j] = { item = 20000 + i * 100 + j, qty = 3 } end
        big.entries[i] = { id = 700 + i, name = "R" .. i, crafts = 5, mats = mats }
    end
    big.auction = function() return Look(10) end
    St.Request("lab", "big", function() return big end, true)
    St.Request("lab", "small", make, true)
    St.Pump(nil, "lab")
    t:Check(St.Peek("lab", "big") == nil, "the superseded job produced nothing")
    t:Check(St.Peek("lab", "small") ~= nil, "the newer one did")
    St.Drop("lab")
    t:Check(St.Peek("lab", "small") == nil, "the slot is dropped")
end)

Pure("crafting.strategy.bounded-frame-time", function(t)
    Strat(t)
    local CP = t.W.CraftPlanner
    -- a 480-material queue, each from two recipes over three shared materials: the job's slices are short and its result equals the plan at once
    local entries, recipes, lookup = {}, {}, {}
    for i = 1, 30 do
        local mats = {}
        for j = 1, 16 do
            local item = 30000 + i * 100 + j
            mats[j] = { item = item, qty = 3 }
            lookup[item] = Look(10)
            recipes[item] = {}
            for k = 1, 2 do recipes[item][k] = Rec(item * 10 + k, item, 1, { 39001, k, 39002, 2, 39003, 1 }) end
        end
        entries[i] = { id = 600 + i, name = "R" .. i, crafts = 5, mats = mats }
    end
    lookup[39001], lookup[39002], lookup[39003] = Look(3), Look(4), Look(5)
    local inp = Inp{ entries = entries, lookup = lookup, recipes = recipes }
    local job = CP.Job(inp)
    local steps, longest, clock = 0, 0, debugprofilestop or function() return 0 end
    repeat
        local t0 = clock()
        local done = job:Step(CP.STEP)
        local dt = clock() - t0
        if dt > longest then longest = dt end
        steps = steps + 1
        if steps % 40 == 0 then t:Yield() end
    until done or steps > 5000
    t:Check(steps > 50, "the plan takes many slices: " .. steps)
    local at = CP.Plan(inp)
    t:Same(job:Result().summary.economic.low, at.summary.economic.low, "the stepped job equals the plan at once")
    t:Same(job:Result().summary.crafts, at.summary.crafts)
    t:Fact("crafting.strategy.bounded-frame-time", ("steps %d longest slice %.2f ms"):format(steps, longest))
end)
