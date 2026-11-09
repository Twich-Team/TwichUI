-- TwichUI Workshop: the Opportunities list (pure)
-- Turns recipes and a price lookup into rows (Prices.Estimate for ONE craft each), then filters and sorts them. Unknown estimates are
-- never mixed in with known ones: they come after every known row, whatever the sort. A range of output is sorted and filtered by its
-- LOW end (what you get if the craft gives the least), so a recipe is "profitable" only when it is even at its worst case.

local R = TwichUI
local W = R.Workshop
local PR = W.Prices
local Op = {}
W.Opps = Op

Op.DEFAULTS = { sort = "profit", desc = true, prof = nil, profitOnly = false }
local FIRST_DIRECTION = { profit = true, sell = true, cost = false }   -- descending first for profit and sell price, cheapest first for cost

local VALUE = {
    profit = function(e) return e.profitLow end,
    cost = function(e) return e.cost end,
    sell = function(e) return e.sellLow end,
}

-- recipes: the rows the window read (id, name, prof, outItem, outMin, outMax, mats). Returns { { rec, est } ... }
function Op.Rows(recipes, lookup, rate)
    local rows = {}
    for i, rec in ipairs(recipes) do
        rows[i] = { rec = rec, est = PR.Estimate(rec, lookup, rate) }
    end
    return rows
end

-- How many rows there are, how many have a known profit and how many are profitable (even at the worst case)
function Op.Summary(rows)
    local s = { total = #rows, priced = 0, profitable = 0 }
    for _, r in ipairs(rows) do
        if r.est.state == "ok" then
            s.priced = s.priced + 1
            if r.est.profitLow > 0 then s.profitable = s.profitable + 1 end
        end
    end
    return s
end

-- opts: { sort = "profit"|"cost"|"sell", desc, prof (a profession id to keep, nil for all), profitOnly }
function Op.Select(rows, opts)
    opts = opts or Op.DEFAULTS
    local value = VALUE[opts.sort] or VALUE.profit
    local out = {}
    for _, r in ipairs(rows) do
        local keep = opts.prof == nil or r.rec.prof == opts.prof
        if keep and opts.profitOnly then keep = r.est.state == "ok" and r.est.profitLow > 0 end
        if keep then out[#out + 1] = r end
    end
    local desc = opts.desc ~= false
    table.sort(out, function(a, b)
        local ka, kb = a.est.state == "ok", b.est.state == "ok"
        if ka ~= kb then return ka end
        if ka then
            local va, vb = value(a.est), value(b.est)
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
        end
        local na, nb = a.rec.name:lower(), b.rec.name:lower()
        if na ~= nb then return na < nb end
        return a.rec.id < b.rec.id
    end)
    return out
end

-- Clicking a column: the sorted column flips direction, another column starts in its natural direction
function Op.SetSort(opts, key)
    if not VALUE[key] then return end
    if opts.sort == key then opts.desc = not (opts.desc ~= false)
    else opts.sort, opts.desc = key, FIRST_DIRECTION[key] end
end

-- Why an estimate is unknown, in a few words
local WHY = {
    nomats = "Its materials aren't known or can't be counted",
    noitem = "It doesn't make an item",
    noamount = "How much it makes isn't known",
}
function Op.WhyText(e)
    if WHY[e.why] then return WHY[e.why] end
    if e.why == "matprice" then
        return e.missing == 1 and "1 material has no price" or (e.missing .. " materials have no price")
    end
    if e.why == "sellprice" then return "What it makes has no price" end
    return nil
end

local function Range(a, b, f)
    if a == b then return f(a) end
    return f(a) .. " to " .. f(b)
end

-- The estimate's basis, as lines for a tooltip: { text } or { left, right }. src: { label (the auction house), at, complete }.
-- name(itemID) -> text; money(copper) -> text (negative amounts allowed).
function Op.Basis(row, src, name, money, now)
    local e, out = row.est, {}
    local function L(left, right) out[#out + 1] = { left, right } end
    L(row.rec.name)
    if src and src.at then
        L(("Prices: %s, scanned %s%s"):format(src.label or "this auction house", PR.AgeText(PR.Age(src.at, now)),
            src.complete and "" or " (not a complete scan)"))
    end
    L("For one craft")
    for _, m in ipairs(e.mats) do
        local left = ("%d x %s"):format(m.qty, name(m.item))
        if m.unit then
            L(left, ("%s each = %s%s"):format(money(m.unit), money(m.total), m.cheapest and " (cheapest listing only)" or ""))
        elseif m.unavailable == "few" then
            L(left, "not enough listed")
        else
            L(left, "no price")
        end
    end
    if e.cost then L("Cost to make", money(e.cost)) end
    if e.outMin then
        local made = e.outMin == e.outMax and tostring(e.outMin) or (e.outMin .. "-" .. e.outMax)
        if e.unit then
            L(("Makes %s, listed at %s each"):format(made, money(e.unit)), Range(e.sellLow, e.sellHigh, money))
        else
            L(("Makes %s"):format(made), "no price")
        end
    end
    if e.sellLow then
        if e.cutRate then
            L(("Auction house cut (%s%%)"):format(tostring(math.floor(e.cutRate * 1000 + 0.5) / 10)), "-" .. Range(e.sellLow - e.netLow, e.sellHigh - e.netHigh, money))
        else
            L("Auction house cut: not taken off. It isn't confirmed for this auction house.")
        end
    end
    if e.state == "ok" then L("Estimated profit", Range(e.profitLow, e.profitHigh, money)) end
    L("These are the cheapest buyout listings at the time of the scan. A listing doesn't mean it will sell at that price, or at all.")
    L("Failed listings, deposits and your own selling time aren't counted.")
    return out
end
