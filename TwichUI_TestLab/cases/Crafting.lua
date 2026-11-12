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
                t:Same(("%d,%d,%d,%s,%s,%d"):format(tot.cash, tot.priced, tot.missing, tostring(tot.estimate), tostring(tot.incomplete), tot.makes),
                    ("%d,%d,%d,%s,%s,%d"):format(ref.cash, ref.priced, ref.missing, tostring(ref.estimate), tostring(ref.incomplete), ref.makes), "seed " .. seed .. ": totals")
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
