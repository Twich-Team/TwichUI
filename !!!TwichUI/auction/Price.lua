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

---------------------------------------------------------------------------
-- Listed price against vendor value
---------------------------------------------------------------------------
-- Both sides are whole copper for ONE auction, with the same number of items on each side. The vendor
-- value is what a vendor pays for the item (its sell price), per item; it is not the auction house's
-- own figures: no cut, no deposit, nothing about profit.

local function IsPrice(v) return type(v) == "number" and v > 0 and v == math.floor(v) and v <= P.MAX_PRICE end

-- What one Post press lists, in the terms the comparison needs. The page has one price, "each":
--   a commodity is one auction of `quantity` items, priced each x quantity;
--   an item (equipment, pets...) is `quantity` auctions of one item each, at the price.
-- The page sets no starting bid (the game then starts it at the buyout), so none is made here; a plan
-- may carry one for VendorCheck all the same. vendorEach: copper per item, nil when not known yet.
-- Returns nil when the quantity or price isn't one the game could take, so the usual checks speak instead.
function P.VendorPlan(kind, quantity, price, vendorEach)
    if type(quantity) ~= "number" or quantity < 1 or quantity ~= math.floor(quantity) or not IsPrice(price) then
        return nil
    end
    if kind == "commodity" then
        if not IsPrice(price * quantity) then return nil end
        return { auctions = 1, items = quantity, buyout = price * quantity, vendorEach = vendorEach }
    end
    return { auctions = quantity, items = 1, buyout = price, vendorEach = vendorEach }
end

-- plan: { auctions, items (in each auction), bid, buyout (per auction, copper, either may be nil), vendorEach }.
-- Returns nil when there is no valid price to look at, else a table:
--   status "below"   a price is under the vendor value of that auction (strictly; equal is not below)
--          "ok"      a vendor value is known and every price is at or above it
--          "none"    the item has no vendor value (0): nothing to compare with, nothing to say
--          "unknown" the vendor value hasn't arrived yet; never treated as 0 or as "safe"
--   vendor, vendorTotal   the vendor value of one auction and of all of them (nil unless known)
--   low   { { kind = "bid" | "buyout", price, total } ... } the prices under it, bid first
--   auctions, items
function P.VendorCheck(plan)
    if not plan then return nil end
    local bid, buyout = IsPrice(plan.bid) and plan.bid or nil, IsPrice(plan.buyout) and plan.buyout or nil
    if not (bid or buyout) then return nil end
    local auctions, items = plan.auctions or 1, plan.items or 1
    local r = { status = "unknown", auctions = auctions, items = items, low = {} }
    local each = plan.vendorEach
    if type(each) ~= "number" or each < 0 or each ~= each then return r end
    if each == 0 then r.status = "none"; return r end
    r.vendor = each * items
    r.vendorTotal = r.vendor * auctions
    r.status = "ok"
    for _, e in ipairs({ { "bid", bid }, { "buyout", buyout } }) do
        if e[2] and e[2] < r.vendor then
            r.low[#r.low + 1] = { kind = e[1], price = e[2], total = e[2] * auctions }
            r.status = "below"
        end
    end
    return r
end

local LABEL = { bid = "Starting bid", buyout = "Buyout" }
local function PerWord(items) return items > 1 and "stack" or "item" end
local function Count(n, one, many) return n == 1 and one or many end

-- The words for a "below" check. money: formats copper. Returns { title, detail, tip }.
function P.VendorWords(check, money)
    local per = PerWord(check.items)
    local low, parts = check.low, {}
    for _, l in ipairs(low) do parts[#parts + 1] = ("%s: %s"):format(LABEL[l.kind], money(l.price)) end
    local title, detail
    if #low == 2 then
        title = "Bid and buyout are below vendor value"
        detail = ("%s · Vendor: %s (all per %s)"):format(table.concat(parts, " · "), money(check.vendor), per)
    else
        title = low[1].kind == "bid" and "Starting bid is below vendor value." or "Below vendor value"
        detail = ("%s per %s · Vendor: %s per %s"):format(parts[1], per, money(check.vendor), per)
    end
    return { title = title, detail = detail,
             tip = "This auction could sell for less than you would receive from a vendor." }
end

-- The confirmation's text. item: the item link or name. Says what is listed and at what, as the page does.
function P.VendorQuestion(check, item, money)
    local per = PerWord(check.items)
    local out = { "Post below vendor value?", "" }
    if check.auctions == 1 then
        out[#out + 1] = ("%s ×%d"):format(item, check.items)
    else
        out[#out + 1] = ("%s - %d auctions of %d %s each"):format(item, check.auctions, check.items,
            Count(check.items, "item", "items"))
    end
    for _, l in ipairs(check.low) do
        out[#out + 1] = ("%s: %s per %s"):format(LABEL[l.kind], money(l.price), per)
    end
    out[#out + 1] = ("Vendor value: %s per %s"):format(money(check.vendor), per)
    if check.auctions > 1 then
        local totals = {}
        for _, l in ipairs(check.low) do totals[#totals + 1] = ("%s %s"):format(LABEL[l.kind], money(l.total)) end
        out[#out + 1] = ("All %d auctions: %s · Vendor value %s"):format(check.auctions, table.concat(totals, " · "),
            money(check.vendorTotal))
    end
    out[#out + 1] = ""
    out[#out + 1] = (check.auctions == 1 and "This auction could" or "These auctions could")
        .. " sell for less than selling the items to a vendor."
    return table.concat(out, "\n")
end
