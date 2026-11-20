-- Merchant evidence for the existing gold ledger. Never buys, sells, repairs or records money.
-- Forever source: wow-ui-source forever, 1.60.1 (70938), Mainline MerchantFrame.lua/xml,
-- Mainline ContainerFrame.lua, MerchantFrameDocumentation.lua and ContainerDocumentation.lua.
-- Restock.Listing owns the gold-only listing/stack checks used by the existing core merchant code.
--
-- A cached pre-action bag/merchant snapshot + one native request + one NEW ledger entry + a matching
-- inventory/repair outcome are all required. Sales additionally need a newly appended buyback receipt.
-- Requests overlapping before settlement, multiple balance changes, unknown prices/currencies, buyback,
-- cursor sales and partial/guild repairs stay Unclassified. No guesses from an open merchant or a missing item.
-- All state is bounded, session-only and discarded on close, world/profile changes or timeout.
local R = TwichUI
local V = {}
R.VendorGold = V

local LIMIT, BUYBACK, LISTINGS = 512, 12, 256
local WAIT, SETTLE = 2, 0.05
local active, visit, candidate, poisoned = false, nil, nil, false
local settleTimer, expiryTimer
local generation, serial = 0, 0
local watching, hooked = {}, {}
local stats = { attributed = 0, refused = 0 }
-- Why a request was not attributed: fixed codes only (no item, price or name), counted for this session and shown in the diagnostics
-- report, so a purchase or sale that stays Unclassified in the real client can be traced to the step that refused it.
local reasons = {}
local function Why(code)
    reasons[code] = (reasons[code] or 0) + 1
    stats.refused = stats.refused + 1
end
local Close, Schedule, Try

local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Whole(v, lo, hi)
    v = Plain(v)
    if type(v) ~= "number" or not tostring(v):find("^[%d%.eE%+%-]+$") then return nil end
    if v < lo or v > hi or math.floor(v) ~= v then return nil end
    return v
end
local function ID(v) return Whole(v, 1, 2147483647) end
local function Clock()
    local now = Plain(GetTime and GetTime())
    if type(now) == "number" and now >= 0 and now < R.Ledger.MAX_MONEY then return now end
end
local function LinkID(link)
    link = Plain(link)
    return type(link) == "string" and ID(tonumber(link:match("item:(%d+)"))) or nil
end
local function Record()
    local L = R.Ledger
    local key = L and L.CharKey()
    return key, key and L.Record(key)
end
local function NPC() return UnitGUID and Plain(UnitGUID("npc")) or nil end
local function Context()
    return active and visit and R.Ledger.Active() and R.Ledger.CharKey() == visit.key
        and NPC() == visit.npc and (not MerchantFrame or not MerchantFrame.IsShown or MerchantFrame:IsShown())
end
local function Cancel(timer) if timer and timer.Cancel then timer:Cancel() end end
local function Clear()
    candidate = nil
    Cancel(expiryTimer); expiryTimer = nil
end
local function Want(event, fn, on)
    if on and not watching[event] then watching[event] = fn; R:On(event, fn)
    elseif not on and watching[event] then R:Off(event, watching[event]); watching[event] = nil end
end

-- Read-only, bounded facts. An unreadable/secret/unsupported fact refuses attribution, never accounting.
local function Snapshot()
    local key, rec = Record()
    if not rec then return nil end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return nil end
    local bags = Whole(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4, 0, 8)
    if not bags then return nil end
    local s = { key = key, anchor = rec.nextId, counts = {}, keys = {}, slots = {}, listings = {}, size = 0 }
    local Cost = R.LedgerCost
    for bag = 0, bags do
        local n = Whole(C_Container.GetContainerNumSlots(bag), 0, LIMIT)
        if not n or s.size + n > LIMIT then return nil end
        s.size = s.size + n
        s.slots[bag] = {}
        for slot = 1, n do
            local info = Plain(C_Container.GetContainerItemInfo(bag, slot))
            if info ~= nil then
                if type(info) ~= "table" then return nil end
                local id, q = ID(info.itemID), ID(info.stackCount)
                if not (id and q) then return nil end
                s.counts[id] = (s.counts[id] or 0) + q
                -- the exact identity (supported variant fields) for the cost basis; a plain id when it cannot be read
                local ik = Cost and Cost.Key(info.hyperlink, id) or ("i" .. id)
                s.keys[ik] = (s.keys[ik] or 0) + q
                s.slots[bag][slot] = { id = id, qty = q, key = ik, locked = Plain(info.isLocked) == true }
            end
        end
    end
    local n = GetMerchantNumItems and Whole(GetMerchantNumItems(), 0, LISTINGS)
    if n and R.Restock and R.Restock.Listing then
        for i = 1, n do s.listings[i] = R.Restock.Listing(i) end
    end
    local bn = GetNumBuybackItems and Whole(GetNumBuybackItems(), 0, BUYBACK)
    if bn and GetBuybackItemInfo and GetBuybackItemLink then
        local list = {}
        for i = 1, bn do
            local _, _, price, qty = GetBuybackItemInfo(i)
            local id = LinkID(GetBuybackItemLink(i))
            price, qty = Whole(price, 1, R.Ledger.MAX_MONEY), ID(qty)
            if not (id and price and qty) then list = nil; break end
            list[i] = { id = id, price = price, qty = qty }
        end
        s.buyback = list
    end
    if CanMerchantRepair and Plain(CanMerchantRepair()) == true and GetRepairAllCost then
        local cost, possible = GetRepairAllCost()
        cost, possible = Whole(cost, 0, R.Ledger.MAX_MONEY), Plain(possible)
        if cost and (cost == 0 or possible == true) then s.repair = cost end
    end
    return s
end
local function Read()
    local ok, s = pcall(Snapshot)
    return ok and s or nil
end
local function SameCounts(a, b, item, delta)
    if item and (b[item] or 0) - (a[item] or 0) ~= delta then return false end
    for id, q in pairs(a) do
        if (b[id] or 0) - q ~= (id == item and delta or 0) then return false end
    end
    for id, q in pairs(b) do
        if a[id] == nil and q ~= (id == item and delta or 0) then return false end
    end
    return true
end
local function SameReceipt(a, b) return a and b and a.id == b.id and a.qty == b.qty and a.price == b.price end
local function SaleReceipt(before, after, c, amount)
    if not (before and after) or #after ~= math.min(BUYBACK, #before + 1) then return false end
    local receipt = after[#after]
    if not receipt or receipt.id ~= c.item or receipt.qty ~= c.qty or receipt.price ~= amount then return false end
    local shift = #before == BUYBACK and 1 or 0
    local identical = #before == #after
    for i = 1, #after - 1 do
        if not SameReceipt(before[i + shift], after[i]) then return false end
    end
    if identical then
        for i = 1, #before do if not SameReceipt(before[i], after[i]) then identical = false; break end end
    end
    return not identical -- a full, unchanged list of identical stacks proves no new sale
end

Try = function()
    if not Context() then Close(); return end
    if not candidate then visit.snapshot = Read(); poisoned = false; return end
    local c = candidate
    local now = Clock()
    if not now or now < c.started or now >= c.expires then
        Why(c.last or "expired"); Clear(); visit.snapshot = Read(); return
    end
    local key, rec = Record()
    if key ~= c.before.key or not rec or rec.nextId > c.before.anchor + 1 then
        Why(rec and key == c.before.key and "several-money-changes" or "other-character"); Clear(); visit.snapshot = Read(); return
    end
    if rec.nextId ~= c.before.anchor + 1 then c.last = "no-money-seen"; return end -- no observed money: an action alone counts for nothing
    local e = rec.entries[#rec.entries]
    if not e or e.id ~= c.before.anchor or e.k
        or (c.kind == "vendorSell" and e.a <= 0) or (c.amount and e.a ~= c.amount) then
        Why(e and e.k and "money-already-classified" or (c.amount and e.a ~= c.amount and "amount-differs-from-price") or "money-wrong-direction"); Clear(); visit.snapshot = Read(); return
    end
    local after = Read()
    if not after then c.last = "bags-unreadable"; return end
    local confirmed
    if c.kind == "vendorBuy" then
        confirmed = SameCounts(c.before.counts, after.counts, c.item, c.qty)
    elseif c.kind == "vendorSell" then
        confirmed = SameCounts(c.before.counts, after.counts, c.item, -c.qty)
            and SaleReceipt(c.before.buyback, after.buyback, c, e.a)
    else
        confirmed = after.repair == 0 and SameCounts(c.before.counts, after.counts)
    end
    if not confirmed then   -- inventory/merchant updates may arrive after PLAYER_MONEY; what is still missing is kept for the expiry
        if c.kind == "vendorSell" and SameCounts(c.before.counts, after.counts, c.item, -c.qty) then c.last = "no-matching-buyback-receipt"
        else c.last = c.kind == "repair" and "repair-not-cleared" or "bag-count-differs" end
        return
    end
    Clear() -- Evidence notifies subscribers synchronously: no candidate may be claimed again
    visit.snapshot = after
    serial = serial + 1
    -- exact carried counts of this identity before and after the verified outcome, for the cost basis (never for money)
    local stock
    if c.key and c.kind ~= "repair" then
        stock = { key = c.key, before = c.before.keys[c.key] or 0, after = after.keys[c.key] or 0 }
    end
    local result = R.Ledger.Evidence({ kind = c.kind, amount = e.a, item = c.item, qty = c.qty, stock = stock,
        note = c.kind == "repair" and "Equipment repairs" or nil,
        corr = "vendor:" .. generation .. ":" .. serial, entry = e.id, char = key })
    if result == "attributed" then stats.attributed = stats.attributed + 1 end
end

local function Scoped(fn, ...)
    if R.Perf and R.Perf.Call then return R.Perf.Call("ledger.vendor", fn, ...) end
    return fn(...)
end
Schedule = function()
    if settleTimer or not visit or not (C_Timer and C_Timer.NewTimer) then return end
    local mine = generation
    settleTimer = C_Timer.NewTimer(SETTLE, function()
        settleTimer = nil
        if mine == generation and visit then Scoped(Try) end
    end)
end
local function Invalidate(code)
    if not visit then return end
    if type(code) == "string" then Why(code) end
    Clear(); poisoned = true; Schedule()
end
local function Begin(c)
    if not Context() then Close(); return end
    if candidate or poisoned or not c or not visit.snapshot or not (C_Timer and C_Timer.NewTimer) then
        Why(candidate and "overlapping-requests" or poisoned and "earlier-action-in-doubt" or not visit.snapshot and "no-bag-snapshot" or "no-timer")
        Invalidate(); return
    end
    c.before = visit.snapshot
    local now = Clock()
    if not now then Why("no-clock"); Invalidate(); return end
    c.started, c.expires = now, now + WAIT
    candidate = c
    local mine = generation
    expiryTimer = C_Timer.NewTimer(WAIT, function()
        if mine == generation and candidate == c then
            expiryTimer = nil
            Scoped(function() Why(c.last or "no-money-seen"); Clear(); visit.snapshot = Read() end)
        end
    end)
    Schedule()
end
local function Buy(index, qty)
    index = Whole(index, 1, LISTINGS)
    local listing = index and visit.snapshot and visit.snapshot.listings[index]
    if not listing or listing.why then Invalidate(not listing and "buy-offer-not-in-snapshot" or "buy-unsupported-offer"); return end
    -- A stale gold-only listing must not vouch for a changed price, item or extended-currency offer.
    local ok, current = pcall(R.Restock.Listing, index)
    local costOK, costs = pcall(GetMerchantItemCostInfo, index)
    if not ok or not current or current.why or current.id ~= listing.id
        or current.price ~= listing.price or current.stack ~= listing.stack
        or not costOK or Whole(costs, 0, R.Ledger.MAX_MONEY) ~= 0 then Invalidate("buy-offer-changed-or-extended-cost"); return end
    qty = qty == nil and listing.stack or ID(qty)
    local price, stack = Whole(listing.price, 1, R.Ledger.MAX_MONEY), ID(listing.stack)
    if not (ID(listing.id) and qty and price and stack) or qty % stack ~= 0
        or qty / stack > R.Ledger.MAX_MONEY / price then Invalidate("buy-quantity-not-a-whole-stack"); return end
    Begin({ kind = "vendorBuy", item = listing.id, qty = qty, amount = -(qty / stack * price), key = R.LedgerCost and R.LedgerCost.Key(nil, listing.id) or ("i" .. listing.id) })
end
local function Sell(bag, slot, unit, bank, reagent)
    bag, slot = Whole(bag, 0, 8), Whole(slot, 1, LIMIT)
    local before = visit.snapshot
    local item = before and bag and slot and before.slots[bag] and before.slots[bag][slot]
    if unit ~= nil or bank ~= nil or reagent == true then Invalidate("sell-not-a-plain-use"); return end
    if not item then Invalidate("sell-slot-not-in-snapshot"); return end
    if item.locked then Invalidate("sell-item-locked"); return end
    if (InRepairMode and InRepairMode()) or (SpellIsTargeting and SpellIsTargeting()) then Invalidate("sell-cursor-mode"); return end
    Begin({ kind = "vendorSell", item = item.id, qty = item.qty, key = item.key })
end
local function Repair(guild)
    local cost = visit.snapshot and visit.snapshot.repair
    if (guild ~= nil and guild ~= false) or not cost or cost <= 0 then Invalidate("repair-not-supported"); return end
    Begin({ kind = "repair", amount = -cost })
end
local function Hook(owner, name, fn)
    local key = (owner and "container." or "global.") .. name
    if hooked[key] or not hooksecurefunc or type((owner or _G)[name]) ~= "function" then return end
    local callback = function(...)
        if not visit then return end
        if not Context() then Close(); return end
        return Scoped(fn, ...)
    end
    if owner then hooksecurefunc(owner, name, callback) else hooksecurefunc(name, callback) end
    hooked[key] = true
end
local function InstallHooks()
    Hook(nil, "BuyMerchantItem", Buy)
    Hook(C_Container, "UseContainerItem", Sell)
    Hook(nil, "RepairAllItems", Repair)
    for _, name in ipairs({ "BuybackItem", "PickupMerchantItem", "SellCursorItem", "PickupContainerItem" }) do
        Hook(nil, name, function() Invalidate("cursor-or-buyback:" .. name) end)
    end
    if C_Container then Hook(C_Container, "PickupContainerItem", function() Invalidate("cursor-or-buyback:PickupContainerItem") end) end
    if C_MerchantFrame then Hook(C_MerchantFrame, "SellAllJunkItems", function() Invalidate("sell-all-junk-button") end) end
end
local function Changed()
    if not Context() then Close(); return end
    if not candidate and visit.snapshot then
        local _, rec = Record()
        if rec then visit.snapshot.anchor = rec.nextId end -- money before a request is never borrowed as evidence
    end
    Schedule()
end
local function Update() if visit then Schedule() end end
local function World() Close() end
Close = function()
    generation = generation + 1
    Clear(); poisoned = false
    Cancel(settleTimer); settleTimer = nil
    if visit then R.Ledger.Unsubscribe(Changed) end
    visit = nil
    for _, event in ipairs({ "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED", "UPDATE_INVENTORY_DURABILITY",
        "UI_ERROR_MESSAGE", "PLAYER_REGEN_DISABLED" }) do Want(event, nil, false) end
end
local function Open()
    Close()
    if not active then return end
    local key = R.Ledger.CharKey()
    if not key then return end
    visit = { key = key, npc = NPC(), snapshot = Read() }
    InstallHooks()
    R.Ledger.Subscribe(Changed)
    Want("MERCHANT_UPDATE", Update, true)
    Want("BAG_UPDATE_DELAYED", Update, true)
    Want("UPDATE_INVENTORY_DURABILITY", Update, true)
    Want("UI_ERROR_MESSAGE", function() Invalidate(candidate and "ui-error-message" or nil) end, true)
    Want("PLAYER_REGEN_DISABLED", function() Invalidate(candidate and "combat" or nil) end, true)
end
local function OpenObserved() return Scoped(Open) end
function V.Refresh()
    Close() -- a refresh also marks a profile/consent boundary, even if recording remains enabled
    local on = R.Ledger and R.Ledger.Active() == true
    active = on
    Want("MERCHANT_SHOW", OpenObserved, on)
    Want("MERCHANT_CLOSED", Close, on)
    Want("PLAYER_ENTERING_WORLD", World, on)
    Want("PLAYER_LOGOUT", Close, on)
    if on and MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown() then OpenObserved() end
end
function V.Snapshot()
    local n = 0; for _ in pairs(watching) do n = n + 1 end
    return { active = active, open = visit ~= nil, candidates = candidate and 1 or 0, events = n,
        slots = visit and visit.snapshot and visit.snapshot.size or 0,
        attributed = stats.attributed, refused = stats.refused, why = reasons }
end
if R.Perf and R.Perf.Gauge then
    for _, field in ipairs({ "candidates", "events", "slots" }) do
        local name = field
        R.Perf.Gauge("ledger.vendor." .. name, { label = "Gold ledger merchant observer: " .. name,
            unit = "count", kind = name == "events" and "listeners" or "cache", group = "workshop",
            read = function() return V.Snapshot()[name] end })
    end
end
R:OnInit(V.Refresh)
