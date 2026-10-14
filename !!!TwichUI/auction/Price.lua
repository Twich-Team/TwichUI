-- TwichUI: auction posting, the arithmetic
-- Which current listings are comparable to the item being sold, the price that
-- matches the lowest of them, and whether a posting's numbers are legal.
-- Plain functions over plain tables, so they can be tested without the game;
-- auction/Scan.lua reads the auction house into these tables.

local R = TwichUI
local P = {}
R.AuctionPrice = P

P.LIMITED_BELOW = 3           -- fewer comparable listings than this: the basis is thin
P.MAX_PRICE = 99999999999     -- MAXIMUM_BID_PRICE in Blizzard_AuctionHouseUI
P.COPPER_PER_SILVER = 100

-- Commodity listings: { unitPrice, quantity, numOwnerItems }. The part of a
-- listing that is yours is left out; a listing that is all yours doesn't count.
-- Each listing gets .status: "match" or "own".
function P.SummariseCommodities(listings)
    local s = { kind = "commodity", found = #listings, comparable = 0, own = 0, quantity = 0 }
    for _, l in ipairs(listings) do
        local others = (l.quantity or 0) - (l.numOwnerItems or 0)
        if others <= 0 or not l.unitPrice then
            l.status = "own"
            s.own = s.own + 1
        else
            l.status = "match"
            s.comparable = s.comparable + 1
            s.quantity = s.quantity + others
            if not s.lowest or l.unitPrice < s.lowest then
                s.lowest, s.lowestQuantity = l.unitPrice, others
            elseif l.unitPrice == s.lowest then
                s.lowestQuantity = s.lowestQuantity + others
            end
        end
    end
    return s
end

-- Item listings: { itemLevel, itemSuffix, buyout, quantity, own }.
-- target: { matchVariant, itemLevel, itemSuffix }. With matchVariant (equipment),
-- only the same item level and suffix compare. Bid-only listings are counted
-- but never priced against. Each listing gets .status: "match", "own",
-- "variant" or "bid".
function P.SummariseItems(listings, target)
    local s = { kind = "item", found = #listings, comparable = 0, own = 0, bidOnly = 0, otherVariant = 0, quantity = 0 }
    for _, l in ipairs(listings) do
        if l.own then
            l.status = "own"
            s.own = s.own + 1
        elseif target.matchVariant and (l.itemLevel ~= target.itemLevel or l.itemSuffix ~= target.itemSuffix) then
            l.status = "variant"
            s.otherVariant = s.otherVariant + 1
        elseif not l.buyout then
            l.status = "bid"
            s.bidOnly = s.bidOnly + 1
        else
            l.status = "match"
            local q = l.quantity or 1
            s.comparable = s.comparable + 1
            s.quantity = s.quantity + q
            if not s.lowest or l.buyout < s.lowest then
                s.lowest, s.lowestQuantity = l.buyout, q
            elseif l.buyout == s.lowest then
                s.lowestQuantity = s.lowestQuantity + q
            end
        end
    end
    return s
end

-- The suggestion: match the lowest comparable listing. Never undercuts. Where
-- the auction house only takes whole silver, a price with copper is rounded up.
-- Returns nil when there is nothing to compare with.
function P.Suggest(summary, copperAllowed)
    if not (summary and summary.lowest) then return nil end
    local price, rounded = summary.lowest, false
    local copper = price % P.COPPER_PER_SILVER
    if not copperAllowed and copper ~= 0 then
        price, rounded = price + (P.COPPER_PER_SILVER - copper), true
    end
    return { price = price, limited = summary.comparable < P.LIMITED_BELOW, rounded = rounded }
end

-- p: { price, quantity, maxQuantity, copperAllowed, deposit, money }.
-- Returns nil when the numbers are fine, else a short reason to show.
function P.Check(p)
    local q = p.quantity
    if not q or q < 1 or q ~= math.floor(q) then return "Enter a quantity." end
    if p.maxQuantity and q > p.maxQuantity then
        return ("You have %d to list."):format(p.maxQuantity)
    end
    local price = p.price
    if not price or price <= 0 then return "Enter a price." end
    if price ~= math.floor(price) or price > P.MAX_PRICE then return "That price is above what the auction house allows." end
    if not p.copperAllowed and price % P.COPPER_PER_SILVER ~= 0 then return "Prices here are in whole silver." end
    if p.deposit and p.money and p.deposit > p.money then return "Not enough money for the deposit." end
    return nil
end
