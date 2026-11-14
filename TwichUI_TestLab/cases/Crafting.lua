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
