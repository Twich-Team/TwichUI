-- Cost basis and realized results (docs/workshop/gold-ledger.md). Real Ledger, Vendor observer, LedgerCost and LedgerCostWatch on a synthetic
-- Forever client: merchant, bags, mailbox and profession events are independent mocks. The cash journal is the authority; every
-- assertion about a lot or a result is made against what the cash entries already proved.
dofile(TESTS .. "harness.lua")
local function Check(v, m) if not v then error(m or "check failed", 2) end end
local function Same(a, b, m) if a ~= b then error((m or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function Text(v)
    if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
    local keys, out = {}, {}; for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do out[#out + 1] = Text(k) .. "=" .. Text(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local T0 = 20000 * 86400 + 43200
local KEY = "Rich - Forever"

local function Client(opts)
    opts = opts or {}
    local c = MakeClient("Rich", { "!!!TwichUI" })
    c.TwichUIDB = { modules = { chronicle = false, restock = false, mageSell = false, quietLogin = false }, ui = { workshopEnabled = opts.on ~= false } }
    c.TwichUILedgerDB = opts.db
    c.MONO, c.MONEY = 100, opts.money or 500000
    c.GetServerTime = function() return T0 + (c.DT or 0) end
    c.GetTime = function() return c.MONO end
    c.GetMoney = function() return c.MONEY end
    c.OPEN, c.NPC = false, "Vendor-1"
    c.MerchantFrame = { IsShown = function() return c.OPEN end }
    local guid = c.UnitGUID
    c.UnitGUID = function(unit) if unit == "npc" then return c.NPC end return guid and guid(unit) end
    c.NUM_BAG_SLOTS = 4
    c.BAGS = { [0] = {} }
    c.BUYBACK, c.REPAIR = {}, 0
    c.LISTINGS = { { id = 10, name = "Spring Water", price = 25, stackCount = 5, numAvailable = -1, isPurchasable = true, hasExtendedCost = false } }
    c.GetMerchantNumItems = function() return #c.LISTINGS end
    c.GetMerchantItemID = function(i) return c.LISTINGS[i] and c.LISTINGS[i].id end
    c.GetMerchantItemMaxStack = function() return 20 end
    c.GetMerchantItemCostInfo = function() return 0 end
    c.C_MerchantFrame = { GetItemInfo = function(i) return c.LISTINGS[i] end }
    c.C_Container = {
        GetContainerNumSlots = function(b) return b == 0 and 12 or 0 end,
        GetContainerItemInfo = function(b, s) return c.BAGS[b] and c.BAGS[b][s] end,
    }
    c.GetNumBuybackItems = function() return #c.BUYBACK end
    c.GetBuybackItemInfo = function(i) local r = c.BUYBACK[i]; if r then return "Sold item", 1, r.price, r.qty end end
    c.GetBuybackItemLink = function(i) local r = c.BUYBACK[i]; return r and ("item:" .. r.id) end
    c.CanMerchantRepair = function() return false end
    c.InRepairMode = function() return false end
    c.SpellIsTargeting = function() return false end
    c.CMDS = {}
    local function Command(name) return function(...) c.CMDS[#c.CMDS + 1] = { name, ... } end end
    for _, name in ipairs({ "BuyMerchantItem", "RepairAllItems", "BuybackItem", "PickupMerchantItem", "SellCursorItem", "PickupContainerItem", "TakeInboxItem" }) do c[name] = Command(name) end
    c.C_Container.UseContainerItem = Command("UseContainerItem")
    c.C_Container.PickupContainerItem = Command("PickupContainerItem")
    c.C_MerchantFrame.SellAllJunkItems = Command("SellAllJunkItems")
    c.hooksecurefunc = function(owner, name, fn)
        if type(owner) == "string" then fn, name, owner = name, owner, c end
        local original = owner[name]
        owner[name] = function(...) original(...); fn(...) end
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
    -- mailbox
    c.MAIL = {}
    c.GetInboxItem = function(i, a) local m = c.MAIL[i]; local at = m and m.items[a]; if at then return "Item", at.id, "tex", at.count end end
    c.GetInboxInvoiceInfo = function(i) local m = c.MAIL[i]; return m and m.invoice end
    c.GetInboxItemLink = function(i, a) local m = c.MAIL[i]; local at = m and m.items[a]; return at and at.link end
    -- professions
    c.RECIPES = {}
    c.C_TradeSkillUI = {
        GetRecipeInfo = function(id) local r = c.RECIPES[id]; return r and { learned = r.learned ~= false } end,
        GetRecipeSchematic = function(id)
            local r = c.RECIPES[id]; if not r then return nil end
            local slots = {}
            for i, m in ipairs(r.mats) do
                slots[i] = { reagentType = 1, reagents = { { itemID = m.item } }, quantityRequired = m.qty, required = true }
            end
            return { outputItemID = r.out, reagentSlotSchematics = slots }
        end,
        GetProfessionInfoByRecipeID = function(id) local r = c.RECIPES[id]; return r and r.prof and { professionID = r.prof, professionName = r.profName } end,
    }
    local files = { "modules/Restock.lua", "WorkshopLauncher.lua", "auction/Ledger.lua", "auction/LedgerCost.lua", "auction/LedgerCostWatch.lua", "auction/Vendor.lua" }
    if opts.nocost then files = { "modules/Restock.lua", "WorkshopLauncher.lua", "auction/Ledger.lua", "auction/Vendor.lua" } end
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, c); chunk("!!!TwichUI", {})
    end
    c.LOADED["!!!TwichUI"] = true
    c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    c.L, c.V, c.K = c.TwichUI.Ledger, c.TwichUI.VendorGold, c.TwichUI.LedgerCost
    function c.Rec() return c.TwichUILedgerDB.chars[KEY] end
    function c.Entries() return c.Rec().entries end
    function c.Cost() local root = c.TwichUILedgerDB.cost; return root and root.chars[KEY] end
    function c.Open() c.OPEN = true; c.FireEvent("MERCHANT_SHOW") end
    function c.Close() c.OPEN = false; c.FireEvent("MERCHANT_CLOSED") end
    function c.Money(delta) c.MONEY = c.MONEY + delta; c.FireEvent("PLAYER_MONEY") end
    function c.Bag() c.FireEvent("BAG_UPDATE_DELAYED") end
    -- put `qty` more of item `id` in the first slot holding it (or the next free slot)
    function c.Give(id, qty, slot)
        local b = c.BAGS[0]
        if not slot then
            for s = 1, 12 do if b[s] and b[s].itemID == id then slot = s break end end
            slot = slot or (function() for s = 1, 12 do if not b[s] then return s end end end)()
        end
        local old = b[slot]
        b[slot] = { itemID = id, stackCount = (old and old.stackCount or 0) + qty, isLocked = false }
        if b[slot].stackCount <= 0 then b[slot] = nil end
        return slot
    end
    function c.Buy(qty, paid)
        c.BuyMerchantItem(1, qty); c.Give(10, qty); c.Bag(); c.Money(-paid); c.Advance(0.1)
    end
    -- sell the whole stack in `slot` to the merchant for `paid`
    function c.Sell(slot, paid)
        local it = c.BAGS[0][slot]
        c.C_Container.UseContainerItem(0, slot)
        c.BAGS[0][slot] = nil
        c.BUYBACK[#c.BUYBACK + 1] = { id = it.itemID, qty = it.stackCount, price = paid }
        if #c.BUYBACK > 12 then table.remove(c.BUYBACK, 1) end
        c.Money(paid); c.Bag(); c.Advance(0.1)
    end
    function c.Settle() c.Bag(); c.Advance(0.1) end   -- the game announces every bag change; the observer re-reads then
    function c.Results() local r = c.Cost(); return r and r.results or {} end
    function c.Lots() local r = c.Cost(); return r and r.lots or {} end
    return c
end

local function CashSnapshot(c) return Text(c.Entries()) end

-- A. A verified vendor purchase becomes one lot of the exact cost; the cash journal is exactly what the V2 evidence made.
do
    local c = Client(); c.Open()
    c.Buy(5, 25)
    Same(#c.Entries(), 1); Same(c.Entries()[1].k, "vendorBuy"); Same(c.Entries()[1].a, -25)
    Same(#c.Lots(), 1); local lot = c.Lots()[1]
    Same(lot.k, "i10"); Same(lot.i, 10); Same(lot.q, 5); Same(lot.r, 5); Same(lot.c, 25); Same(lot.s, "vendor"); Same(lot.x, c.Entries()[1].id)
    Same(c.Rec().days[20000].o, 25, "cash totals are the ledger's own")
    -- repeated notifications do not create a second lot
    c.FireEvent("PLAYER_MONEY"); c.Bag(); c.Advance(1)
    Same(#c.Lots(), 1); Same(#c.Entries(), 1)
end

-- B. Exact resale: bought five for 25, sold the same five for 30 is +5; the lot is consumed once.
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    local before = #c.Entries()
    c.Sell(1, 30)
    Same(#c.Entries(), before + 1); Same(c.Entries()[2].k, "vendorSell"); Same(c.Entries()[2].a, 30)
    Same(#c.Results(), 1); local r = c.Results()[1]
    Same(r.st, "ok"); Same(r.a, 30); Same(r.c, 25); Same(r.q, 5); Same(r.i, 10); Same(r.src, "vendorSell"); Same(r.x, c.Entries()[2].id)
    Same(#c.Lots(), 0, "the cost was consumed")
    c.FireEvent("PLAYER_MONEY"); c.Bag(); c.Advance(1); Same(#c.Results(), 1, "no duplicate result")
end

-- C. Partial quantity and exact apportionment: 5 units for 26 sold as 2 + 3 add up to exactly 26.
do
    local c = Client(); c.LISTINGS[1].price = 26; c.Open(); c.Buy(5, 26)
    c.BAGS[0][1] = { itemID = 10, stackCount = 3, isLocked = false }; c.BAGS[0][2] = { itemID = 10, stackCount = 2, isLocked = false }; c.Settle()
    c.Sell(2, 20)
    local r = c.Results()[1]; Same(r.st, "ok"); Same(r.q, 2); Same(r.c, math.floor(26 * 2 / 5)); Same(c.Lots()[1].r, 3)
    c.Sell(1, 30)
    local r2 = c.Results()[2]; Same(r2.q, 3); Same(r2.c, 26 - math.floor(26 * 2 / 5)); Same(r.c + r2.c, 26)
    Same(#c.Lots(), 0)
end

-- D. Several lots: FIFO inside identified stock, each with its own exact cost.
do
    local c = Client(); c.Open(); c.Buy(5, 25); c.LISTINGS[1].price = 30; c.Settle(); c.Buy(5, 30)
    Same(#c.Lots(), 2)
    c.BAGS[0][1] = { itemID = 10, stackCount = 7, isLocked = false }; c.BAGS[0][2] = { itemID = 10, stackCount = 3, isLocked = false }; c.Settle()
    c.Sell(1, 70)
    local r = c.Results()[1]; Same(r.st, "ok"); Same(r.c, 25 + math.floor(30 * 2 / 5)); Same(#r.al, 1, "allocations of one origin are merged"); Same(r.al[1].q, 7)
    Same(c.Lots()[1].r, 3)
end

-- E. Unknown starting inventory: older stock of the same item makes the purchase unidentifiable; profit is unavailable, never zero cost.
do
    local c = Client(); c.Give(10, 3); c.Open()
    c.Buy(5, 25)
    Same(#c.Lots(), 0, "a lot mixed with older stock is not identified")
    c.Sell(1, 40)
    local r = c.Results()[1]; Same(r.st, "unknown"); Same(r.c, nil); Same(r.w, "nolot"); Same(r.a, 40)
end

-- F. Known and unknown stock mixed AFTER the purchase (loot): the sale cannot be separated; the pool is forgotten, nothing guessed.
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    c.Give(10, 2); c.Settle()    -- loot: no evidence
    c.Sell(1, 50)
    local r = c.Results()[1]; Same(r.st, "unknown"); Same(r.w, "mixed"); Same(r.c, nil)
    Same(#c.Lots(), 0)
    c.Give(10, 5); c.Settle(); c.Sell(1, 30)
    Same(c.Results()[2].st, "unknown", "stock that is no longer identified never gets a cost afterwards")
end

-- G. Known stock partly elsewhere (bank): fewer in the bags than identified lots refuses too.
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    c.BAGS[0][1].stackCount = 2; c.Settle()
    c.Sell(1, 12)
    Same(c.Results()[1].st, "unknown"); Same(c.Results()[1].w, "missing"); Same(#c.Lots(), 0)
end

-- H. Variants are separate identities: a different bonus-id link is not pooled with the plain item.
do
    local c = Client()
    Same(c.K.Key(nil, 10), "i10")
    Same(c.K.Key("|cffffffff|Hitem:10::::::::60:::::|h[x]|h|r", 10), "i10")
    Check(c.K.Key("|Hitem:10::::::::::::2:1500:1200|h[x]|h", 10) == c.K.Key("|Hitem:10::::::::::::2:1200:1500|h[x]|h", 10), "bonus order is irrelevant")
    Check(c.K.Key("|Hitem:10::::::::::::1:1500|h[x]|h", 10) ~= "i10", "bonus ids make a variant")
    Check(c.K.Key("|Hitem:10::::::-8:::::|h[x]|h", 10) ~= "i10", "a random suffix makes a variant")
    -- a vendor sale of a variant stack is not matched to the plain lot
    local v = Client(); v.Open(); v.Buy(5, 25)
    v.BAGS[0][1] = { itemID = 10, stackCount = 5, isLocked = false, hyperlink = "|Hitem:10::::::::::::1:1500|h[x]|h" }; v.Settle()
    v.Sell(1, 30)
    Same(v.Results()[1].st, "unknown"); Same(v.Results()[1].k, v.K.Key("|Hitem:10::::::::::::1:1500|h[x]|h", 10))
end

-- I. Cash is untouched: identical activity makes byte-identical journals and day totals with and without the cost component, and
-- the cost component never creates or changes a cash entry.
do
    local function Flow(c)
        c.Open(); c.Buy(5, 25); c.Sell(1, 30)
        c.Give(10, 5); c.Settle(); c.Money(-7); c.Advance(1)
        c.Money(980); c.L.Evidence({ kind = "ahSale", amount = 980, qty = 2, corr = "mail:1", note = "Thorium Bar",
            settlement = { v = 1, invoices = { { g = 1000, f = 50, d = 30, c = 980, n = "Thorium Bar", q = 2 } } } })
        return Text(c.Entries()) .. Text(c.Rec().days)
    end
    local with, without = Client(), Client({ nocost = true })
    Same(Flow(with), Flow(without), "the cost basis never changes cash history")
    Same(#with.Entries(), 4)
    for _, e in ipairs(with.Entries()) do Check(e.cost == nil and e.lot == nil and e.stock == nil, "no cost fields on a cash entry") end
    Same(with.Rec().days[20000].i, 30 + 980); Same(with.Rec().days[20000].o, 25 + 7)
end

-- J. Unsupported / unverifiable evidence creates no lot: a repair, an unclassified purchase, a gold change with nothing verified.
do
    local c = Client(); c.Open()
    c.Money(-100); c.Advance(1)
    Same(#c.Lots(), 0); Same(#c.Results(), 0); Same(c.Cost(), nil, "no cost record is made until something is verified")
end

-- K. Auction purchase: a lot in transit; delivered only by a buyer-invoice mail take that the bags confirm exactly.
local function AhBuy(c, item, qty, paid, corr)
    c.Money(-paid)
    return c.L.Evidence({ kind = "ahBuy", amount = -paid, item = item, qty = qty, corr = corr or "ah:1:1" })
end
do
    local c = Client()
    Same(AhBuy(c, 20, 5, 100), "attributed")
    Same(#c.Lots(), 1); local lot = c.Lots()[1]
    Same(lot.s, "ah"); Same(lot.tq, 5); Same(lot.k, nil); Same(lot.c, 100)
    Same(AhBuy(c, 20, 5, 100), "repeated", "a repeated completion is not a second purchase"); Same(#c.Lots(), 1)
    -- selling from the bags before it arrives cannot use it
    -- a non-buyer mail is not a delivery
    c.MAIL[1] = { invoice = "seller", items = { { id = 20, count = 5 } } }
    c.TakeInboxItem(1, 1); c.Give(20, 5); c.Bag(); c.Advance(5)
    Same(c.Lots()[1].tq, 5, "a mail that is not a purchase delivery changes nothing")
    c.BAGS[0] = {}
    -- the real delivery
    c.MAIL[2] = { invoice = "buyer", items = { { id = 20, count = 5 } } }
    c.TakeInboxItem(2, 1); c.Give(20, 5); c.Bag()
    Same(c.Lots()[1].tq, nil); Same(c.Lots()[1].k, "i20"); Same(c.Lots()[1].r, 5)
    c.Bag(); c.Advance(5); Same(c.Lots()[1].r, 5)
    -- and it can now be resold with an exact cost
    c.Open(); c.Sell(1, 120)
    local r = c.Results()[1]; Same(r.st, "ok"); Same(r.c, 100); Same(r.a, 120); Same(r.src, "vendorSell")
end
-- A delivery whose count differs from the bags, or that overlaps, stays in transit.
do
    local c = Client(); AhBuy(c, 20, 5, 100)
    c.MAIL[1] = { invoice = "buyer", items = { { id = 20, count = 5 } } }
    c.TakeInboxItem(1, 1); c.Give(20, 4); c.Bag(); c.Advance(5)
    Same(c.Lots()[1].tq, 5)
    local d = Client(); AhBuy(d, 20, 5, 100)
    d.MAIL[1] = { invoice = "buyer", items = { { id = 20, count = 5 } } }
    d.TakeInboxItem(1, 1); d.TakeInboxItem(1, 1); d.Give(20, 5); d.Bag(); d.Advance(5)
    Same(d.Lots()[1].tq, 5, "overlapping takes attribute nothing")
    -- older stock of the same item in the bags: the delivery cannot be told from it; the lot cannot become identified
    local e = Client(); e.Give(20, 3); AhBuy(e, 20, 5, 100)
    e.MAIL[1] = { invoice = "buyer", items = { { id = 20, count = 5 } } }
    e.TakeInboxItem(1, 1); e.Give(20, 5); e.Bag()
    Same(#e.Lots(), 0, "mixed delivery is dropped, never costed")
    -- two lots of the same item and quantity at different prices cannot be told apart
    local f = Client(); AhBuy(f, 20, 5, 100, "ah:1:1"); AhBuy(f, 20, 5, 130, "ah:1:2")
    f.MAIL[1] = { invoice = "buyer", items = { { id = 20, count = 5 } } }
    f.TakeInboxItem(1, 1); f.Give(20, 5); f.Bag()
    Same(f.Lots()[1].tq, 5); Same(f.Lots()[2].tq, 5)
end

-- L. Auction sale: no identity link exists, so the sale is kept (collected, fee, gross) with no cost and no profit.
do
    local c = Client()
    c.Money(980)
    local st = c.L.Evidence({ kind = "ahSale", amount = 980, qty = 2, corr = "mail:1", note = "Thorium Bar",
        settlement = { v = 1, invoices = { { g = 1000, f = 50, d = 30, c = 980, n = "Thorium Bar", q = 2 } } } })
    Same(st, "attributed")
    local r = c.Results()[1]
    Same(r.src, "ahSale"); Same(r.st, "unknown"); Same(r.w, "auctionid"); Same(r.a, 980); Same(r.g, 1000); Same(r.fee, 50); Same(r.d, 30); Same(r.n, "Thorium Bar"); Same(r.q, 2); Same(r.c, nil)
    -- a lot of the very same item name and count is NOT matched to it
    local d = Client(); d.Open(); d.Buy(5, 25)
    d.Money(980); d.L.Evidence({ kind = "ahSale", amount = 980, qty = 5, corr = "mail:1", settlement = { v = 1, invoices = { { g = 1000, f = 50, d = 30, c = 980, n = "Spring Water", q = 5 } } } })
    Same(d.Results()[1].st, "unknown"); Same(d.Lots()[1].r, 5, "the purchase lot is untouched by a similar-looking auction sale")
end

-- M. Crafting: a verified craft consumes known-cost materials; the output carries that cost to its sale and to the profession.
local function Recipe(c, id, out, mats, prof)
    c.RECIPES[id] = { out = out, mats = mats, prof = prof or 164, profName = "Blacksmithing" }
end
local function Craft(c, id, outQty, opts)
    opts = opts or {}
    c.FireEvent("TRADE_SKILL_CRAFT_BEGIN", id)
    local r = c.RECIPES[id]
    if not opts.noConsume then for _, m in ipairs(r.mats) do c.Give(m.item, -(opts.consume and opts.consume[m.item] or m.qty)) end end
    if not opts.noOutput then c.Give(r.out, outQty) end
    c.FireEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = opts.resultItem or r.out, quantity = outQty, itemGUID = opts.guid or ("Item-" .. math.random(1, 1e9)) })
    c.Bag(); c.Advance(0.1)
end
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    Recipe(c, 1000, 50, { { item = 10, qty = 5 } })
    Craft(c, 1000, 1)
    Same(#c.Cost().crafts, 1); local cr = c.Cost().crafts[1]
    Same(cr.st, "ok"); Same(cr.c, 25); Same(cr.p, 164); Same(cr.i, 50); Same(cr.q, 1); Same(c.Cost().profs[164], "Blacksmithing")
    Same(#c.Lots(), 1); Same(c.Lots()[1].s, "craft"); Same(c.Lots()[1].c, 25); Same(c.Lots()[1].i, 50)
    -- the crafted item is sold: realized +15, attributed to the profession
    local slot; for s = 1, 12 do if c.BAGS[0][s] and c.BAGS[0][s].itemID == 50 then slot = s end end
    c.Sell(slot, 40)
    local r = c.Results()[1]; Same(r.st, "ok"); Same(r.c, 25); Same(r.a, 40); Same(r.pf, 164)
    local rows = c.K.Professions({ KEY }, 0, 4102444800)
    Same(#rows, 1); Same(rows[1].profit, 15); Same(rows[1].sales, 1); Same(rows[1].name, "Blacksmithing")
end
-- Missing cost materials: the craft is kept as incomplete; the sale has no profit and the profession shows partial, not zero cost.
do
    local c = Client(); c.Give(10, 5); c.Open()
    Recipe(c, 1000, 50, { { item = 10, qty = 5 } })
    Craft(c, 1000, 1)
    local cr = c.Cost().crafts[1]; Same(cr.st, "incomplete"); Same(cr.c, nil)
    Same(c.Lots()[1].c, nil, "unknown is not zero")
    c.Sell(1, 40)
    local r = c.Results()[1]; Same(r.st, "incomplete"); Same(r.c, nil); Same(r.w, "unknowncost"); Same(r.pf, nil)
    local rows = c.K.Professions({ KEY }, 0, 4102444800)
    Same(rows[1].sales, 0); Same(rows[1].partial, 1); Same(rows[1].crafts, 1)
end
-- Unverified crafts: only the queue's "Crafted one" (no events), an interrupted craft, extra/odd results, and moved materials.
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    Recipe(c, 1000, 50, { { item = 10, qty = 5 } })
    c.Give(10, -5); c.Give(50, 1); c.Bag(); c.Advance(5)     -- the bags changed but no craft event: not evidence
    Same(#c.Cost().crafts, 0)
    local d = Client(); d.Open(); d.Buy(5, 25); Recipe(d, 1000, 50, { { item = 10, qty = 5 } })
    d.FireEvent("TRADE_SKILL_CRAFT_BEGIN", 1000); d.Advance(10)   -- interrupted: nothing consumed
    Same(#d.Cost().crafts, 0); Same(#d.Lots(), 1, "an interrupted craft consumed nothing")
    -- materials moved during the craft: the delta is not the schematic quantity
    local e = Client(); e.Open(); e.Buy(5, 25); Recipe(e, 1000, 50, { { item = 10, qty = 5 } })
    Craft(e, 1000, 1, { consume = { [10] = 3 } }); e.Advance(5)
    Same(#e.Cost().crafts, 0); Same(#e.Lots(), 0, "unverifiable consumption forgets the stock instead of guessing")
    -- an unlearned recipe
    local f = Client(); f.Open(); f.Buy(5, 25); Recipe(f, 1000, 50, { { item = 10, qty = 5 } }); f.RECIPES[1000].learned = false
    Craft(f, 1000, 1)
    Same(#f.Cost().crafts, 0)
    -- a different item in the result (multi-output): not supported
    local g = Client(); g.Open(); g.Buy(5, 25); Recipe(g, 1000, 50, { { item = 10, qty = 5 } })
    Craft(g, 1000, 1, { resultItem = 51 }); g.Advance(5)
    Same(#g.Lots(), 0)
    Same(#g.Cost().crafts, 0)
    -- a repeated result for the same item
    local h = Client(); h.Open(); h.Buy(5, 25); Recipe(h, 1000, 50, { { item = 10, qty = 5 } })
    h.FireEvent("TRADE_SKILL_CRAFT_BEGIN", 1000); h.Give(10, -5); h.Give(50, 1)
    h.FireEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 50, quantity = 1, itemGUID = "G1" })
    Same(#h.Cost().crafts, 1)
    h.FireEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 50, quantity = 1, itemGUID = "G1" })
    Same(#h.Cost().crafts, 1, "a repeated result does not make a second craft")
end
-- Overlapping crafts: a second begin before the first settled verifies neither.
do
    local c = Client(); c.Open(); c.Buy(5, 25); Recipe(c, 1000, 50, { { item = 10, qty = 5 } })
    c.FireEvent("TRADE_SKILL_CRAFT_BEGIN", 1000); c.FireEvent("TRADE_SKILL_CRAFT_BEGIN", 1000)
    c.Give(10, -5); c.Give(50, 1)
    c.FireEvent("TRADE_SKILL_ITEM_CRAFTED_RESULT", { itemID = 50, quantity = 1, itemGUID = "G2" }); c.Bag(); c.Advance(5)
    Same(#c.Cost().crafts, 0)
end
-- Variable output: the reported quantity must equal the bag gain; multiple outputs from one craft use the exact quantity.
do
    local c = Client(); c.Open(); c.Buy(5, 25); Recipe(c, 1000, 50, { { item = 10, qty = 5 } })
    Craft(c, 1000, 3)
    local cr = c.Cost().crafts[1]; Same(cr.q, 3); Same(c.Lots()[1].q, 3); Same(c.Lots()[1].c, 25)
    local slot; for s = 1, 12 do if c.BAGS[0][s] and c.BAGS[0][s].itemID == 50 then slot = s end end
    c.BAGS[0][slot].stackCount = 3; c.Settle()
    c.Sell(slot, 60)
    Same(c.Results()[1].c, 25); Same(c.Results()[1].st, "ok")
end
-- Subcraft chain: ore -> bars -> armor. The bars' cost passes into the armor; it is not a second expense and sums once.
do
    local c = Client(); c.Open(); c.Buy(5, 25)      -- 5 water stands in for the ore, cost 25
    Recipe(c, 1000, 50, { { item = 10, qty = 5 } }, 164)    -- bar
    Craft(c, 1000, 1)
    Recipe(c, 1001, 60, { { item = 50, qty = 1 } }, 164)    -- armor made of the bar
    Craft(c, 1001, 1)
    Same(#c.Cost().crafts, 2); Same(c.Cost().crafts[2].c, 25, "the bar's cost passes through"); Same(c.Cost().crafts[2].st, "ok")
    local slot; for s = 1, 12 do if c.BAGS[0][s] and c.BAGS[0][s].itemID == 60 then slot = s end end
    c.Sell(slot, 100)
    Same(c.Results()[1].c, 25); Same(c.Results()[1].a, 100)
    local rows = c.K.Professions({ KEY }, 0, 4102444800)
    Same(rows[1].profit, 75); Same(rows[1].cost, 25, "ore cost counted once")
end
-- Materials reused across crafts: stock is allocated at most once.
do
    local c = Client(); c.Open(); c.Buy(5, 25); Recipe(c, 1000, 50, { { item = 10, qty = 5 } })
    Craft(c, 1000, 1)
    Craft(c, 1000, 1)   -- the second craft finds no identified stock (the bags hold none either): refused as a craft
    Same(#c.Cost().crafts, 1, "a craft without its materials in the bags is not verified")
end

-- N. Persistence: lots and results survive a reload; a future component version is held untouched; damage is repaired narrowly.
do
    local c = Client(); c.Open(); c.Buy(5, 25); c.Buy(5, 25)
    c.BAGS[0] = { [1] = { itemID = 10, stackCount = 10, isLocked = false } }; c.Settle()
    local saved = c.TwichUILedgerDB
    local d = Client({ db = saved }); d.Open()
    Same(#d.Lots(), 2); d.BAGS[0] = { [1] = { itemID = 10, stackCount = 10, isLocked = false } }; d.Settle()
    d.Sell(1, 70)
    local r = d.Results()[1]; Same(r.st, "ok"); Same(r.c, 50); Same(#d.Entries(), 3, "the earlier cash history is intact")
    -- future component
    local future = { version = 1, chars = {}, cost = { v = 99, chars = { [KEY] = { lots = { "keep me" } } } } }
    local e = Client({ db = future }); e.Open(); e.Buy(5, 25)
    Same(e.TwichUILedgerDB.cost.v, 99); Same(e.TwichUILedgerDB.cost.chars[KEY].lots[1], "keep me"); Same(#e.Entries(), 1, "cash still records")
    -- corrupt parts
    local bad = { version = 1, chars = {}, cost = { v = 1, chars = { [KEY] = {
        lots = { { id = 1, t = T0, k = "i10", i = 10, q = 5, r = 5, c = 25, s = "vendor" }, { id = 2, q = -1 }, "junk", { id = 3, t = T0, k = "i10", i = 10, q = 5, r = 9, s = "vendor" } },
        results = { { id = 1, t = T0, src = "vendorSell", q = 1, a = 5, st = "ok" }, 7 }, crafts = "x" } } } }
    local f = Client({ db = bad }); f.Open()
    local rec = f.Cost(); Check(rec, "record kept")
    f.Give(10, 5); f.Settle(); f.Buy(5, 25)       -- reading cleans the record narrowly
    Same(#f.Lots(), 2); Same(f.Lots()[1].id, 1); Same(f.Lots()[1].r, 5); Same(f.Results()[1].st, "incomplete", "an ok result without a cost is not trusted")
    -- an old ledger with no cost component at all
    local legacy = { version = 1, chars = { [KEY] = { name = "Rich", realm = "Forever", since = T0, nextId = 2, entries = { { id = 1, t = T0, a = 100, e = "balance" } }, days = {} } } }
    local g = Client({ db = legacy }); g.Open(); Same(#g.Entries(), 1); Same(g.TwichUILedgerDB.cost, nil, "nothing is added until something is verified")
end

-- O. Characters and realms are separate: another character's lots are never used.
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    local key = c.L.CharKey()
    Check(c.K.Rec(key, false), "own record"); Same(c.K.Rec("Other - Forever", false), nil)
    Same(c.K.Take(c.K.Rec(key, false), "i10", 5, 5) and true, true)
end

-- P. Retention is bounded and explicit.
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    local rec = c.Cost()
    for i = 1, 450 do rec.lots[#rec.lots + 1] = { id = 1000 + i, t = T0, k = "i" .. (1000 + i), i = 1000 + i, q = 1, r = 1, c = 1, s = "vendor" } end
    rec.nextLot = 2000
    c.Buy(5, 25)
    Check(#c.Lots() <= c.K.MAX_LOTS, "lots are bounded")
    c.DT = 200 * 86400
    local d = c.K.Rec(KEY, false); c.Buy(5, 25)
    for _, lot in ipairs(c.Lots()) do Check(lot.t >= T0 + c.DT - c.K.LOT_DAYS * 86400, "old lots are forgotten") end
end

-- Q. The ledger remains the only money authority: disabling the Workshop stops lots too and keeps what exists.
do
    local c = Client(); c.Open(); c.Buy(5, 25)
    c.TwichUIDB.ui.workshopEnabled = false; c.L.Refresh()
    c.Give(10, 5); c.Bag(); c.Money(-25); c.Advance(1)
    Same(#c.Lots(), 1); Same(#c.Entries(), 1)
end

print("LEDGER COST OK")
