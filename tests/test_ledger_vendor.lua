-- Synthetic Forever merchant server. Real Ledger, Restock.Listing and Vendor observer; no Workshop UI loaded.
-- Commands only enqueue requests. Tests independently deliver money, bags, buyback and repair outcomes in varying orders.
dofile(TESTS .. "harness.lua")
local function Check(v, m) if not v then error(m or "check failed", 2) end end
local function Same(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function Copy(v) if type(v) ~= "table" then return v end local t = {} for k, x in pairs(v) do t[k] = Copy(x) end return t end
local function Text(v)
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
    local keys, out = {}, {}; for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = Text(k) .. "=" .. Text(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local T0 = 20000 * 86400 + 43200
local function Client(opts)
    opts = opts or {}
    local c = MakeClient("Rich", { "!!!TwichUI" })
    c.TwichUIDB = { modules = { chronicle = false, restock = false, mageSell = false, quietLogin = false }, ui = { workshopEnabled = opts.on ~= false } }
    c.TwichUILedgerDB = opts.db
    c.MONO, c.MONEY = 100, opts.money or 500000
    c.GetServerTime = function() return T0 end
    c.GetTime = function() return c.MONO end
    c.GetMoney = function() return c.MONEY end
    c.OPEN, c.NPC = false, "Vendor-1"
    c.MerchantFrame = { IsShown = function() return c.OPEN end }
    local guid = c.UnitGUID
    c.UnitGUID = function(unit) if unit == "npc" then return c.NPC end return guid and guid(unit) end
    c.NUM_BAG_SLOTS = 4
    c.BAGS = { [0] = { [2] = { itemID = 11, stackCount = 2, isLocked = false } } }
    c.BUYBACK, c.REPAIR = {}, 12400
    c.LISTINGS = { { id = 10, name = "Refreshing Spring Water", price = 25, stackCount = 5,
        numAvailable = -1, isPurchasable = true, hasExtendedCost = false } }
    c.GetMerchantNumItems = function() return #c.LISTINGS end
    c.GetMerchantItemID = function(i) return c.LISTINGS[i] and c.LISTINGS[i].id end
    c.GetMerchantItemMaxStack = function() return 20 end
    c.GetMerchantItemCostInfo = function() return c.COSTS or 0 end
    c.C_MerchantFrame = { GetItemInfo = function(i) return c.LISTINGS[i] end }
    c.C_Container = {
        GetContainerNumSlots = function(b) return b == 0 and 8 or 0 end,
        GetContainerItemInfo = function(b, s) return c.BAGS[b] and c.BAGS[b][s] end,
    }
    c.GetNumBuybackItems = function() return #c.BUYBACK end
    c.GetBuybackItemInfo = function(i) local r = c.BUYBACK[i]; if r then return "Sold item", 1, r.price, r.qty end end
    c.GetBuybackItemLink = function(i) local r = c.BUYBACK[i]; return r and ("item:" .. r.id) end
    c.CanMerchantRepair = function() return true end
    c.GetRepairAllCost = function() return c.REPAIR, c.REPAIR > 0 end
    c.InRepairMode = function() return c.REPAIR_MODE == true end
    c.SpellIsTargeting = function() return false end
    c.CMDS, c.HOOKS = {}, 0
    local function Command(name) return function(...) c.CMDS[#c.CMDS + 1] = { name, ... } end end
    for _, name in ipairs({ "BuyMerchantItem", "RepairAllItems", "BuybackItem", "PickupMerchantItem", "SellCursorItem", "PickupContainerItem" }) do c[name] = Command(name) end
    c.C_Container.UseContainerItem = Command("UseContainerItem")
    c.C_Container.PickupContainerItem = Command("PickupContainerItem")
    c.C_MerchantFrame.SellAllJunkItems = Command("SellAllJunkItems")
    c.hooksecurefunc = function(owner, name, fn)
        if type(owner) == "string" then fn, name, owner = name, owner, c end
        local original = owner[name]
        owner[name] = function(...) original(...); fn(...) end
        c.HOOKS = c.HOOKS + 1
    end
    local timers = {}
    c.C_Timer = { NewTimer = function(delay, fn)
        local t = { at = c.MONO + delay, fn = fn }; function t:Cancel() self.cancelled = true end
        timers[#timers + 1] = t; return t
    end }
    c.C_Timer.After = function(delay, fn) c.C_Timer.NewTimer(delay, fn) end
    function c.Advance(seconds)
        local target = c.MONO + seconds
        for _ = 1, 1000 do
            local index
            for i, t in ipairs(timers) do if t.at <= target and (not index or t.at < timers[index].at) then index = i end end
            if not index then c.MONO = target; return end
            local t = table.remove(timers, index); c.MONO = math.max(c.MONO, t.at)
            if not t.cancelled then t.fn() end
        end
        error("unbounded timers")
    end
    function c.Timers() local n = 0 for _, t in ipairs(timers) do if not t.cancelled then n = n + 1 end end return n end
    for _, file in ipairs({ "modules/Restock.lua", "WorkshopLauncher.lua", "auction/Ledger.lua", "auction/Vendor.lua" }) do
        local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
    end
    c.LOADED["!!!TwichUI"] = true
    c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    c.L, c.V = c.TwichUI.Ledger, c.TwichUI.VendorGold
    function c.Rec() return c.TwichUILedgerDB.chars["Rich - Forever"] end
    function c.Entries() return c.Rec().entries end
    function c.Last() return c.Entries()[#c.Entries()] end
    function c.Open() c.OPEN = true; c.FireEvent("MERCHANT_SHOW") end
    function c.Close() c.OPEN = false; c.FireEvent("MERCHANT_CLOSED") end
    function c.Money(delta) c.MONEY = c.MONEY + delta; c.FireEvent("PLAYER_MONEY") end
    function c.Bag() c.FireEvent("BAG_UPDATE_DELAYED") end
    function c.Settle() c.Bag(); c.Advance(0.1) end   -- the game announces every bag change; the observer re-reads then
    function c.Water(q) local old = c.BAGS[0][1]; c.BAGS[0][1] = { itemID = 10, stackCount = (old and old.stackCount or 0) + q, isLocked = false } end
    function c.Receipt(id, qty, price)
        c.BUYBACK[#c.BUYBACK + 1] = { id = id, qty = qty, price = price }
        if #c.BUYBACK > 12 then table.remove(c.BUYBACK, 1) end
    end
    function c.Purchase(qty, paid, moneyFirst)
        if moneyFirst then c.Money(-paid); c.Water(qty); c.Bag()
        else c.Water(qty); c.Bag(); c.Money(-paid) end
        c.Advance(0.1)
    end
    function c.Sale(paid)
        c.BAGS[0][2] = nil; c.Receipt(11, 2, paid); c.Money(paid); c.Bag(); c.Advance(0.1)
    end
    function c.Class(code, amount, item, qty)
        local e = c.Last(); Check(e, "a balance movement was recorded")
        Same(e.k, code, "source " .. (c.CASE or "")); Same(e.a, amount); Same(e.i, item); Same(e.q, qty)
        Same(e.e, code and c.L.SOURCES[code].evidence or "balance")
    end
    return c
end

-- Normal purchase, including money-before-bags and bags-before-money delivery; no Workshop loaded or accounting on intent.
for _, moneyFirst in ipairs({ false, true }) do
    local c = Client(); c.Open(); c.BuyMerchantItem(1)
    Same(#c.Entries(), 0, "a request records nothing"); c.Purchase(5, 25, moneyFirst)
    c.Class("vendorBuy", -25, 10, 5); Same(#c.Entries(), 1)
    Same(c.LOADED.TwichUI_Workshop, nil)
    local day = c.Rec().days[20000]; Same(day.o, 25); Same(day.co.vendorBuy, 25); Same(day.co.other, nil)
    c.FireEvent("PLAYER_MONEY"); c.Bag(); c.Advance(1)
    Same(#c.Entries(), 1); Same(c.V.Snapshot().attributed, 1, "repeated notifications do not classify twice")
end
-- One bulk API request is one combined money entry; cached stack price is per five items, not per item.
do local c = Client(); c.Open(); c.BuyMerchantItem(1, 10); c.Purchase(10, 50); c.Class("vendorBuy", -50, 10, 10); Same(#c.Entries(), 1) end
-- Separate settled rapid purchases are identifiable. Overlapping requests/combined spending are deliberately ambiguous.
do
    local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Purchase(5, 25)
    c.BuyMerchantItem(1, 10); c.Purchase(10, 50)
    Same(#c.Entries(), 2); c.Class("vendorBuy", -50, 10, 10); Same(c.Entries()[1].k, "vendorBuy")
end
for _, combined in ipairs({ false, true }) do
    local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.BuyMerchantItem(1, 5)
    c.Water(10); c.Money(combined and -50 or -25); if not combined then c.Money(-25) end
    c.Bag(); c.Advance(0.1)
    Same(#c.Entries(), combined and 1 or 2)
    for _, e in ipairs(c.Entries()) do Same(e.k, nil, "overlapping purchase requests are ambiguous") end
end
do
    local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.BuyMerchantItem(1, 5)
    c.Purchase(5, 25); c.Class(nil, -25) -- only one of two overlapping attempts succeeded; which one is unknown
end
-- Failed/insufficient-gold/cancelled requests cannot claim an unrelated later change of the same amount.
for _, mode in ipairs({ "error", "timeout", "poor", "closed", "world", "profile", "npc", "combat" }) do
    local c = Client({ money = mode == "poor" and 10 or nil }); c.Open(); c.BuyMerchantItem(1, 5)
    if mode == "error" or mode == "poor" then c.FireEvent("UI_ERROR_MESSAGE", 1, "failed")
    elseif mode == "timeout" then c.Advance(3)
    elseif mode == "closed" then c.Close()
    elseif mode == "world" then c.FireEvent("PLAYER_ENTERING_WORLD")
    elseif mode == "profile" then c.L.Refresh()
    elseif mode == "npc" then c.NPC = "Vendor-2"
    elseif mode == "combat" then c.FireEvent("PLAYER_REGEN_DISABLED") end
    Same(#c.Entries(), 0)
    local unrelated = mode == "poor" and 25 or -25
    c.Money(unrelated); c.Water(5); c.Bag(); c.Advance(0.1)
    c.Class(nil, unrelated)
end
for _, mode in ipairs({ "extended", "currency", "costItem", "unknownCost", "missingCost", "price", "fractional", "unavailable", "unknownID", "quantity" }) do
    local c = Client(); c.CASE = mode; local l = c.LISTINGS[1]
    if mode == "extended" then l.hasExtendedCost = true
    elseif mode == "currency" then l.currencyID = 42
    elseif mode == "costItem" then c.COSTS = 1
    elseif mode == "unknownCost" then c.GetMerchantItemCostInfo = function() return nil end
    elseif mode == "missingCost" then c.GetMerchantItemCostInfo = nil
    elseif mode == "price" then l.price = nil
    elseif mode == "fractional" then l.price = 0.5
    elseif mode == "unavailable" then l.isPurchasable = false
    elseif mode == "unknownID" then l.id = nil end
    c.Open(); c.BuyMerchantItem(1, mode == "quantity" and 6 or 5); c.Purchase(5, 25)
    c.Class(nil, -25)
end
-- Unreadable/secret item and merchant data are refused without throwing from a secure post-hook.
for _, mode in ipairs({ "secretPrice", "secretItem", "overflowBag", "apiError" }) do
    local c = Client(); local secret = {}
    c.issecretvalue = function(value) return value == secret end
    if mode == "secretPrice" then c.LISTINGS[1].price = secret
    elseif mode == "secretItem" then c.BAGS[0][2].itemID = secret
    elseif mode == "overflowBag" then c.C_Container.GetContainerNumSlots = function() return 513 end
    elseif mode == "apiError" then c.GetMerchantNumItems = function() error("unsupported") end end
    c.Open(); c.BuyMerchantItem(1, 5); c.Money(-25); c.Water(5); c.Bag(); c.Advance(3); c.Class(nil, -25)
end
for _, field in ipairs({ "price", "hasExtendedCost", "currencyID", "id" }) do
    local c = Client(); c.Open()
    c.LISTINGS[1][field] = field == "hasExtendedCost" and true or 42
    c.BuyMerchantItem(1, 5); c.Purchase(5, 25); c.Class(nil, -25)
end
-- An advertised price alone, an item gain alone, or matching spending without the items prove nothing.
do local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Money(-25); c.Advance(3); c.Class(nil, -25) end
do local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Water(5); c.Bag(); c.Advance(3); Same(#c.Entries(), 0) end
do
    local c = Client(); c.Open(); c.BuyMerchantItem(1, 5)
    c.MONO = c.MONO + 3 -- a stalled client delivers money before its already-overdue timer callbacks
    c.Purchase(5, 25); c.Class(nil, -25)
end
do local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Purchase(5, 26); c.Class(nil, -26, nil, nil) end
-- Concurrent unrelated money, including a separate change followed by a matching debit, makes the batch ambiguous.
do local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Water(5); c.Money(7); c.Money(-25); c.Bag(); c.Advance(0.1); for _, e in ipairs(c.Entries()) do Same(e.k, nil) end end
do local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Purchase(5, 32); c.Class(nil, -32) end
do local c = Client(); c.Money(-25); c.Open(); c.BuyMerchantItem(1, 5); c.Water(5); c.Bag(); c.Advance(0.1); c.Class(nil, -25, nil, nil) end

-- Manual sale snapshots the stack before it disappears, and requires a new exact-price buyback receipt.
do
    local c = Client(); c.Open(); c.C_Container.UseContainerItem(0, 2); Same(#c.Entries(), 0)
    c.Sale(18); c.Class("vendorSell", 18, 11, 2); Same(#c.Entries(), 1)
    Same(c.Rec().days[20000].ci.vendorSell, 18)
end
do
    local c = Client(); c.BAGS[0][2].stackCount = 1; c.Open(); c.C_Container.UseContainerItem(0, 2)
    c.BAGS[0][2] = nil; c.Receipt(11, 1, 9); c.Money(9); c.Bag(); c.Advance(0.1); c.Class("vendorSell", 9, 11, 1)
end
for _, mode in ipairs({ "failed", "moved", "consumed", "receipt", "wrongPrice", "wrongItem", "wrongQty", "unknown", "repairMode", "bank", "bulk" }) do
    local c = Client()
    if mode == "unknown" then c.BAGS[0][2].itemID = nil end
    if mode == "repairMode" then c.REPAIR_MODE = true end
    if mode == "bank" then c.BankFrame = { IsShown = function() return true end } end   -- a bank open at the same time is not a sale
    c.Open(); c.C_Container.UseContainerItem(0, 2, nil, mode == "bank" and 1 or nil)
    if mode == "failed" then c.FireEvent("UI_ERROR_MESSAGE", 1, "failed") end
    if mode == "bulk" then c.C_Container.UseContainerItem(0, 3) end -- external seller: unknown/overlapping item
    c.BAGS[0][2] = nil
    if mode == "moved" then c.BAGS[0][3] = { itemID = 11, stackCount = 2, isLocked = false } end
    if mode ~= "consumed" and mode ~= "receipt" then c.Receipt(mode == "wrongItem" and 12 or 11, mode == "wrongQty" and 3 or 2, mode == "wrongPrice" and 19 or 18) end
    c.Money(18); c.Bag(); c.Advance(0.1); c.Class(nil, 18)
end
-- Consuming/moving without money never records anything; an open merchant never labels unrelated income.
do local c = Client(); c.Open(); c.C_Container.UseContainerItem(0, 2); c.BAGS[0][2] = nil; c.Bag(); c.Advance(3); Same(#c.Entries(), 0) end
do local c = Client(); c.Open(); c.Money(18); c.Advance(0.1); c.Class(nil, 18) end
-- Several sales with separate outcomes work; indistinguishable full buyback lists are refused.
do
    local c = Client(); c.Open(); c.C_Container.UseContainerItem(0, 2); c.Sale(18)
    c.Advance(1.2)   -- the first batch closes after a quiet second
    c.BAGS[0][2] = { itemID = 11, stackCount = 2, isLocked = false }; c.Bag(); c.Advance(0.1)
    c.C_Container.UseContainerItem(0, 2); c.Sale(18); c.Class("vendorSell", 18, 11, 2); Same(#c.Entries(), 2)
    Same(c.Entries()[1].k, "vendorSell")
end
for _, identical in ipairs({ false, true }) do
    local c = Client(); for i = 1, 12 do c.Receipt(identical and 11 or (20 + i), 2, 18) end
    c.Open(); c.C_Container.UseContainerItem(0, 2); c.Sale(18)
    if identical then c.Class(nil, 18) else c.Class("vendorSell", 18, 11, 2) end
end


-- Sale BATCHES: how real sellers work. EllesmereUI's Junk Marker uses one UseContainerItem about every 0.08 s; its other mode and Blizzard's
-- button use SellAllJunkItems(). Outcomes the game reports (buyback receipts, bag counts, money) decide, matched exactly.
do
    -- a burst of individual sales, each answered a little after the next request, with different prices
    local function Slots(c, list) for slot, it in pairs(list) do c.BAGS[0][slot] = { itemID = it[1], stackCount = it[2], isLocked = false } end c.BAGS[0][2] = nil; c.Settle() end
    local sells = { { 3, 21, 1, 5 }, { 4, 22, 3, 30 }, { 5, 23, 2, 17 }, { 6, 21, 1, 5 }, { 7, 24, 4, 44 } }
    local function Burst(c, delay)
        local pending = {}
        for _, sale in ipairs(sells) do
            local slot, id, qty, price = sale[1], sale[2], sale[3], sale[4]
            c.C_Container.UseContainerItem(0, slot)
            pending[#pending + 1] = sale
            if #pending > 1 then   -- the previous sale's outcome arrives only now: money, receipt and bags
                local p = table.remove(pending, 1)
                c.BAGS[0][p[1]] = nil; c.Receipt(p[2], p[3], p[4]); c.Money(p[4]); c.Bag()
            end
            c.Advance(delay)
        end
        local p = table.remove(pending, 1)
        c.BAGS[0][p[1]] = nil; c.Receipt(p[2], p[3], p[4]); c.Money(p[4]); c.Bag(); c.Advance(0.2)
    end
    local function Setup()
        local c = Client(); c.Open()
        Slots(c, { [3] = { 21, 1 }, [4] = { 22, 3 }, [5] = { 23, 2 }, [6] = { 21, 1 }, [7] = { 24, 4 } })
        return c
    end
    local c = Setup(); Burst(c, 0.08); c.Advance(2)
    Same(#c.Entries(), 5)
    for i, sale in ipairs(sells) do
        local e = c.Entries()[i]
        Same(e.k, "vendorSell", "sale " .. i); Same(e.a, sale[4]); Same(e.i, sale[2]); Same(e.q, sale[3])
    end
    Same(c.V.Snapshot().attributed, 5); Same(next(c.V.Snapshot().why), nil, "nothing was refused"); Same(c.V.Snapshot().candidates, 0, "the batch closed")
    -- money that arrives late (after the next request), and receipts that arrive with the money
    c = Setup(); Burst(c, 0.5); c.Advance(2); Same(c.V.Snapshot().attributed, 5)

    -- two sales whose money arrives as ONE change: one entry that says how many items it covers; no item is claimed
    c = Setup()
    c.C_Container.UseContainerItem(0, 3); c.C_Container.UseContainerItem(0, 4)
    c.BAGS[0][3], c.BAGS[0][4] = nil, nil; c.Receipt(21, 1, 5); c.Receipt(22, 3, 30); c.Money(35); c.Bag(); c.Advance(2)
    Same(#c.Entries(), 1); Same(c.Entries()[1].k, "vendorSell"); Same(c.Entries()[1].a, 35); Same(c.Entries()[1].i, nil); Same(c.Entries()[1].n, "2 items sold to a vendor")
    Same(c.Rec().days[20000].ci.vendorSell, 35)

    -- the junk button: no request names an item; the receipts, bags and money still agree exactly
    c = Setup(); c.C_MerchantFrame.SellAllJunkItems()
    for _, slot in ipairs({ 3, 4, 5 }) do local it = c.BAGS[0][slot]; c.BAGS[0][slot] = nil; c.Receipt(it.itemID, it.stackCount, 10 * slot); c.Money(10 * slot); c.Bag(); c.Advance(0.1) end
    c.Advance(2)
    Same(#c.Entries(), 3); for _, e in ipairs(c.Entries()) do Same(e.k, "vendorSell") end; Same(c.Entries()[2].i, 22); Same(c.Entries()[2].a, 40)
    -- repeated passes (EllesmereUI sweeps again while grays remain) are separate batches
    c.C_MerchantFrame.SellAllJunkItems(); local it = c.BAGS[0][6]; c.BAGS[0][6] = nil; c.Receipt(it[1] or it.itemID, 1, 5); c.Money(5); c.Bag(); c.Advance(2)
    Same(#c.Entries(), 4); Same(c.Last().k, "vendorSell")

    -- more sales than the buyback list holds: its oldest receipts roll off, and every sale is still attributed
    c = Client(); c.C_Container.GetContainerNumSlots = function(b) return b == 0 and 20 or 0 end; c.Open()
    for i = 1, 15 do c.BAGS[0][i + 2] = { itemID = 100 + i, stackCount = 1, isLocked = false } end
    c.BAGS[0][2] = nil; c.Settle()
    for i = 1, 15 do
        c.C_Container.UseContainerItem(0, i + 2); c.BAGS[0][i + 2] = nil; c.Receipt(100 + i, 1, 3 + i); c.Money(3 + i); c.Bag(); c.Advance(0.08)
    end
    c.Advance(2)
    Same(#c.Entries(), 15); Same(c.V.Snapshot().attributed, 15)
end

-- Batches refuse what they cannot prove, as single sales did.
do
    local function Setup()
        local c = Client(); c.Open()
        c.BAGS[0][3] = { itemID = 21, stackCount = 1, isLocked = false }; c.BAGS[0][4] = { itemID = 22, stackCount = 3, isLocked = false }; c.Settle()
        return c
    end
    local function Why(c, code) return (c.V.Snapshot().why or {})[code] or 0 end
    -- a receipt nobody asked for
    local c = Setup(); c.C_Container.UseContainerItem(0, 3)
    c.BAGS[0][3] = nil; c.Receipt(21, 1, 5); c.BAGS[0][4] = nil; c.Receipt(22, 3, 30); c.Money(5); c.Money(30); c.Bag(); c.Advance(5)
    Same(Why(c, "receipt-without-request"), 1); for _, e in ipairs(c.Entries()) do Same(e.k, nil) end
    -- money that is not a sum of receipts (a quest or loot gain inside the sweep)
    c = Setup(); c.C_MerchantFrame.SellAllJunkItems()
    c.BAGS[0][3] = nil; c.Receipt(21, 1, 5); c.Money(7); c.Bag(); c.Advance(5)
    Same(Why(c, "receipts-do-not-sum-to-money"), 1); Same(c.Last().k, nil)
    -- receipts without the items leaving the bags (a buyback, a refund)
    c = Setup(); c.C_MerchantFrame.SellAllJunkItems(); c.Receipt(21, 1, 5); c.Money(5); c.Bag(); c.Advance(5)
    Same(Why(c, "bag-count-differs"), 1); Same(c.Last().k, nil)
    -- a drag, an error, combat or a purchase in the middle
    for _, mode in ipairs({ "drag", "error", "combat", "buy" }) do
        c = Setup(); c.C_Container.UseContainerItem(0, 3)
        if mode == "drag" then c.PickupContainerItem(0, 4) elseif mode == "error" then c.FireEvent("UI_ERROR_MESSAGE", 1, "x")
        elseif mode == "combat" then c.FireEvent("PLAYER_REGEN_DISABLED") else c.BuyMerchantItem(1, 5) end
        c.BAGS[0][3] = nil; c.Receipt(21, 1, 5); c.Money(5); c.Bag(); c.Advance(5)
        Same(c.Last().k, nil, mode)
    end
    -- spending inside the sweep (an automatic repair, a purchase's debit) is named, not matched to receipts
    c = Setup(); c.C_Container.UseContainerItem(0, 3); c.Money(-100); c.BAGS[0][3] = nil; c.Receipt(21, 1, 5); c.Money(5); c.Bag(); c.Advance(5)
    Same(Why(c, "money-wrong-direction"), 1); Same(c.Entries()[2].k, nil)
    -- unrelated money before the first request is never borrowed
    c = Setup(); c.Money(5); c.C_Container.UseContainerItem(0, 3); c.BAGS[0][3] = nil; c.Receipt(21, 1, 5); c.Money(5); c.Bag(); c.Advance(5)
    Same(c.Entries()[1].k, nil); Same(c.Entries()[2].k, "vendorSell")
    -- an unreadable buyback list cannot start a batch
    c = Setup(); c.GetBuybackItemInfo = function() return nil end; c.GetNumBuybackItems = function() return 1 end; c.BUYBACK[1] = { id = 9, qty = 1, price = 1 }; c.Bag(); c.Advance(0.2)
    c.C_Container.UseContainerItem(0, 3); c.BAGS[0][3] = nil; c.Money(5); c.Bag(); c.Advance(5)
    Same(c.Last().k, nil)
end


-- What the real client does (from the diagnostic of a real session): the merchant frame's right-click passes bank arguments even though no
-- bank is open, and EllesmereUI starts selling at MERCHANT_SHOW, before the merchant frame is shown. Neither is a reason to refuse.
do
    for _, args in ipairs({ { 0, 2, nil, nil, false }, { 0, 2, nil, 0, false }, { 0, 2, nil, false, false } }) do
        local c = Client(); c.Open(); c.C_Container.UseContainerItem(unpack(args, 1, 5))
        c.Sale(18); c.Class("vendorSell", 18, 11, 2)
    end
    -- the frame is not shown yet when the first sale arrives (an automatic seller on MERCHANT_SHOW)
    local c = Client(); c.OPEN = false; c.FireEvent("MERCHANT_SHOW")
    c.C_MerchantFrame.SellAllJunkItems()
    c.BAGS[0][2] = nil; c.Receipt(11, 2, 18); c.Money(18); c.Bag(); c.Advance(2)
    c.Class("vendorSell", 18, 11, 2)
    Same(c.V.Snapshot().visits, 1); Check(c.V.Snapshot().calls >= 1, "native calls are counted")
    -- a call before any visit, and after the interaction ended, is counted and never silent
    c = Client(); c.C_Container.UseContainerItem(0, 2)
    Same((c.V.Snapshot().why or {})["no-merchant-visit-open"], 1)
    c = Client(); c.Open(); c.NPC = "Vendor-2"; c.C_Container.UseContainerItem(0, 2)
    Same((c.V.Snapshot().why or {})["merchant-context-lost"], 1)
end

-- Repair-all: actual personal spending AND the quoted cost cleared. No repair money is invented.
do
    local c = Client(); c.Open(); c.RepairAllItems(); Same(#c.Entries(), 0)
    c.REPAIR = 0; c.Money(-12400); c.FireEvent("UPDATE_INVENTORY_DURABILITY"); c.Advance(0.1)
    c.Class("repair", -12400); Same(c.Last().n, "Equipment repairs")
end
for _, mode in ipairs({ "guild", "partial", "failed", "extra", "noCost", "changedBags" }) do
    local c = Client(); if mode == "noCost" then c.GetRepairAllCost = function() return nil end end
    c.Open(); c.RepairAllItems(mode == "guild" and true or nil)
    if mode == "failed" then c.FireEvent("UI_ERROR_MESSAGE", 1, "failed") end
    c.REPAIR = mode == "partial" and 12000 or 0
    if mode == "changedBags" then c.Water(5) end
    local spent = mode == "partial" and 400 or (mode == "extra" and 12425 or 12400)
    if mode ~= "guild" then c.Money(-spent) end
    c.FireEvent("UPDATE_INVENTORY_DURABILITY"); c.Advance(0.1)
    if mode == "guild" then Same(#c.Entries(), 0); c.Money(-12400); c.Advance(0.1) end
    c.Class(nil, mode == "guild" and -12400 or -spent)
end
do local c = Client(); c.Open(); c.RepairAllItems(); c.Money(-12400); c.Advance(3); c.Class(nil, -12400) end

-- Exact-target evidence never falls back to another equal-amount entry or waits for future money.
do
    local c = Client(); c.Money(-25); c.Money(-25)
    local bad = { kind = "vendorBuy", amount = -25, entry = 99, char = "Rich - Forever" }
    Same(c.L.Evidence(bad), false); Same(c.L.Snapshot().pending, 0)
    bad.entry, bad.char = 1, "Another - Forever"; Same(c.L.Evidence(bad), false)
    bad.char, bad.amount = "Rich - Forever", -26; Same(c.L.Evidence(bad), false)
    bad.amount, bad.corr = -25, "exact:1"; Same(c.L.Evidence(bad), "attributed")
    Same(c.Entries()[1].k, "vendorBuy"); Same(c.Entries()[2].k, nil)
    Same(c.L.Evidence(bad), "repeated"); Same(c.Rec().days[20000].co.vendorBuy, 25)
    bad.corr = "same-target-again"; Same(c.L.Evidence(bad), false); Same(c.Rec().days[20000].co.vendorBuy, 25)
    bad.entry, bad.corr = 2, "expired"; c.Advance(11); Same(c.L.Evidence(bad), false); Same(c.L.Snapshot().pending, 0)
    for _, code in ipairs({ "vendorBuy", "vendorSell", "repair" }) do
        Same(c.L.Evidence({ kind = code, amount = code == "vendorSell" and -1 or 1 }), false, "source direction")
    end
end
-- Existing V1 history is unchanged; new codes, IDs, amounts and daily source splits survive a modeled reload.
do
    local db = { version = 1, chars = { ["Rich - Forever"] = { name = "Rich", realm = "Forever", since = T0, nextId = 10,
        entries = { { id = 9, t = T0, a = -36, e = "balance" } },
        days = { [20000] = { i = 0, o = 36, n = 1, ci = {}, co = { other = 36 } } } } } }
    local c = Client({ db = Copy(db) })
    local migrated = Copy(db); migrated.chars["Rich - Forever"].tz = 1   -- only the local-day marker is new; ids, amounts and totals are identical
    Same(Text(c.TwichUILedgerDB), Text(migrated))
    local old = Text(migrated)
    c.Open(); c.BuyMerchantItem(1, 5); c.Purchase(5, 25)
    c.C_Container.UseContainerItem(0, 2); c.Sale(18)
    c.RepairAllItems(); c.REPAIR = 0; c.Money(-12400); c.Advance(0.1)
    Same(Text(c.Entries()[1]), Text(db.chars["Rich - Forever"].entries[1]), "old Unclassified entry untouched")
    local saved = Copy(c.TwichUILedgerDB); local fingerprint = Text(saved)
    local reload = Client({ db = saved, money = c.MONEY }); Same(Text(saved), fingerprint)
    Same(#reload.Entries(), 4); Same(reload.Entries()[2].id, 10); Same(reload.Last().id, 12)
    Same(reload.Entries()[2].k, "vendorBuy"); Same(reload.Entries()[3].k, "vendorSell"); Same(reload.Last().k, "repair")
    Same(reload.Rec().days[20000].co.other, 36); Same(reload.Rec().days[20000].co.vendorBuy, 25)
end
do
    local future = { version = 999, chars = { keep = { anything = "future" } } }; local before = Text(future)
    local c = Client({ db = future }); Check(c.L.Held()); c.Open(); c.BuyMerchantItem(1, 5); c.Money(-25); c.Advance(3)
    Same(Text(future), before); Same(c.V.Snapshot().active, false)
end
-- Lifecycle bounds, no gameplay initiated by the observer, no duplicate hooks or stale expiry callbacks.
do
    local c = Client(); c.Open(); local hooks = c.HOOKS
    Same(#c.CMDS, 0); Same(c.V.Snapshot().events, 9); Check(c.V.Snapshot().slots <= 512)
    for _ = 1, 20 do c.Close(); c.Open() end
    Same(c.HOOKS, hooks); Same(#c.CMDS, 0); Same(c.L.Snapshot().listeners, 1)
    c.BuyMerchantItem(1, 5); c.Close(); Same(c.Timers(), 0); Same(c.L.Snapshot().listeners, 0)
    c.Open(); c.Advance(3); Same(c.V.Snapshot().candidates, 0)
    c.TwichUIDB.ui.workshopEnabled = false; c.L.Refresh()
    Same(c.V.Snapshot().events, 0); Same(c.V.Snapshot().slots, 0); Same(c.V.Snapshot().active, false)
    Same(#c.CMDS, 1, "only the explicit test command was called")
end
-- Accounting property over mixed observed movements: entries, source aggregates and signed net reconcile independently.
do
    local c = Client(); c.Open(); local balance, moneyEvents = 0, 0
    for i = 1, 60 do
        if i % 3 == 0 then c.BuyMerchantItem(1, 5); c.Purchase(5, 25); balance = balance - 25
        elseif i % 3 == 1 then c.Money(7); c.Advance(0.1); balance = balance + 7
        else c.Money(-3); c.Advance(0.1); balance = balance - 3 end
        moneyEvents = moneyEvents + 1
        c.FireEvent("PLAYER_MONEY") -- duplicate native notifications never create an entry
        Same(#c.Entries(), moneyEvents)
        local day = c.Rec().days[20000]; Same(day.i - day.o, balance)
        local inn, out = 0, 0; for _, n in pairs(day.ci) do inn = inn + n end; for _, n in pairs(day.co) do out = out + n end
        Same(inn, day.i); Same(out, day.o); Same(day.n, moneyEvents)
    end
end

-- Why a request was not attributed: fixed codes, counted (the diagnostics report lists them), so an Unclassified purchase or sale in the
-- real client can be traced to the step that refused it. Counting changes nothing about what is attributed.
do
    local function Why(c, code) return (c.V.Snapshot().why or {})[code] or 0 end
    local c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.BuyMerchantItem(1, 5); c.Advance(3)
    Check(Why(c, "overlapping-requests") >= 1, "overlap is named")
    c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Advance(3); Same(Why(c, "no-money-seen"), 1, "an action with no money")
    c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Money(-25); c.Bag(); c.Advance(3); Same(Why(c, "bag-count-differs"), 1, "money but no matching items")
    c = Client(); c.Open(); c.C_Container.UseContainerItem(0, 2); c.BAGS[0][2] = nil; c.Money(18); c.Bag(); c.Advance(5)
    Same(Why(c, "no-matching-buyback-receipt"), 1, "items gone and money in, but no buyback receipt")
    c = Client(); c.Open(); c.C_MerchantFrame.SellAllJunkItems(); c.Advance(5); Same(Why(c, "no-money-seen"), 1, "the junk button alone sold nothing")
    c = Client(); c.Open(); c.BAGS[0][2].isLocked = true; c.Bag(); c.Advance(0.2); c.C_Container.UseContainerItem(0, 2); Same(Why(c, "sell-item-locked"), 1)
    c = Client(); c.Open(); c.LISTINGS[1].price = 99; c.BuyMerchantItem(1, 5); Same(Why(c, "buy-offer-changed-or-extended-cost"), 1, "a changed offer")
    c = Client(); c.Open(); c.BuyMerchantItem(1, 3); Same(Why(c, "buy-quantity-not-a-whole-stack"), 1)
    c = Client(); c.Open(); c.C_Container.UseContainerItem(0, 2, "target"); Same(Why(c, "sell-not-a-plain-use"), 1)
    -- an item whose lock state the client does not give is not treated as locked
    c = Client(); c.BAGS[0][2].isLocked = nil; c.Open(); c.C_Container.UseContainerItem(0, 2)
    Same(Why(c, "sell-item-locked"), 0)
    -- nothing refused: no codes
    c = Client(); c.Open(); c.BuyMerchantItem(1, 5); c.Purchase(5, 25); Same(next(c.V.Snapshot().why), nil, "an attributed purchase counts no refusal")
end
print("LEDGER VENDOR OK")
