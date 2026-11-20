-- TwichUI: evidence for the cost basis that is NOT a cash movement (docs/workshop/gold-ledger.md). Observes only; it never takes mail,
-- crafts, buys, sells or records money, and it creates no cash entry. Everything it learns goes to R.LedgerCost.
--
--   1. Auction House deliveries. A completed Auction House purchase (a lot "in transit", see LedgerCost.lua) joins the carried stock
--      only when the player takes a BUYER-invoice mail attachment (TakeInboxItem) and the bags then show exactly that many more
--      units of that exact identity. One request at a time; overlap, a different count, a non-purchase mail or a timeout all
--      leave the lot in transit. Sources: Blizzard_MailFrame.lua (GetInboxItem, TakeInboxItem), MailInfoDocumentation.lua.
--   2. Crafts. TRADE_SKILL_CRAFT_BEGIN(recipeSpellID), TRADE_SKILL_ITEM_CRAFTED_RESULT(data) and the bags together. A craft is
--      recorded only when: the recipe is the player's own learned recipe; its schematic is fixed (every material one basic item
--      at a fixed quantity, one output item); exactly one craft is in flight; the results name only that output item and the bags
--      gain exactly the reported quantity; and every material leaves the bags in exactly the schematic quantity (so no resources
--      were returned and no other movement overlapped). Anything else is not a verified craft: the materials' identified stock is
--      forgotten rather than guessed. Sources: TradeSkillUIDocumentation.lua (events, GetRecipeSchematic, GetRecipeInfo,
--      GetProfessionInfoByRecipeID), Blizzard_ProfessionsCraftingOutputLog.lua. The queue's "Crafted one" button is NOT evidence.
--
-- Listeners exist only while the Gold Ledger records; a craft or a mail take adds one bounded candidate (4 s) and two scans of the bags.
-- Not verified without the real client: that Forever delivers these events and payloads as documented, that an Auction House purchase
-- arrives as a buyer-invoice mail, and the order of bag updates against TRADE_SKILL_ITEM_CRAFTED_RESULT.
local R = TwichUI
local W = {}
R.LedgerCostWatch = W

local WAIT = 4
local MAX_RECIPE_MATS = 8
local active, hooked = false, false
local candidate           -- the one craft in flight
local mail                -- the one mail take in flight
local watching = {}
local stats = { crafts = 0, refused = 0, deliveries = 0, deliveryRefused = 0, overlap = 0 }

local function Plain(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end
local function Whole(v, lo, hi)
    v = Plain(v)
    if type(v) ~= "number" or not tostring(v):find("^[%d%.eE%+%-]+$") or v < lo or v > hi or math.floor(v) ~= v then return nil end
    return v
end
local function Mono()
    local f = GetTime
    if type(f) ~= "function" then return 0 end
    local ok, v = pcall(f)
    return ok and type(v) == "number" and v or 0
end
local function Cost() return R.LedgerCost end
local function Char() return R.Ledger and R.Ledger.CharKey() end
local function Cancel(t) if t and t.Cancel then t:Cancel() end end
local function Want(event, fn, on)
    if on and not watching[event] then
        local ok = pcall(R.On, R, event, fn)   -- an event the client does not know must never break the ledger
        if ok then watching[event] = fn end
    elseif not on and watching[event] then
        R:Off(event, watching[event]); watching[event] = nil
    end
end

-- Carried units by exact identity: { [key] = count }, or nil when the bags cannot be read.
function W.Carried()
    local C = C_Container
    local cost = Cost()
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo and cost) then return nil end
    local bags = Whole(NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4, 0, 8)
    if not bags then return nil end
    local out, slots = {}, 0
    for bag = 0, bags do
        local n = Whole(C.GetContainerNumSlots(bag), 0, 256)
        if not n then return nil end
        slots = slots + n
        if slots > 512 then return nil end
        for slot = 1, n do
            local info = Plain(C.GetContainerItemInfo(bag, slot))
            if info ~= nil then
                if type(info) ~= "table" then return nil end
                local id, q = Whole(info.itemID, 1, 2147483647), Whole(info.stackCount, 1, 2147483647)
                if not (id and q) then return nil end
                local key = cost.Key(info.hyperlink, id)
                out[key] = (out[key] or 0) + q
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Auction House deliveries
---------------------------------------------------------------------------
local MailSettle, CraftSettle
-- One bag listener serves both observers and exists only while one of them has a candidate.
local function OnBags()
    local ok, err = pcall(function()
        if mail then MailSettle() end
        if candidate then CraftSettle() end
    end)
    if not ok and R.Fault then R.Fault("gold ledger cost basis", err) end
end
local function Bags() Want("BAG_UPDATE_DELAYED", OnBags, (mail ~= nil or candidate ~= nil) and active) end

local function EndMail()
    if mail then Cancel(mail.timer) end
    mail = nil
    Bags()
end

MailSettle = function()
    if not mail then return end
    local now = W.Carried()
    if not now then return end
    local after = now[mail.key] or 0
    local gained = after - mail.before
    if gained == 0 then return end   -- the bags have not changed yet
    local m = mail
    EndMail()
    if gained ~= m.count then stats.deliveryRefused = stats.deliveryRefused + 1 return end
    local ok = Cost().Deliver(m.char, m.item, m.key, m.count, m.before)
    if ok then stats.deliveries = stats.deliveries + 1 else stats.deliveryRefused = stats.deliveryRefused + 1 end
end

local function OnTake(index, attachment)
    if not active then return end
    if mail then   -- two requests before the first settled: neither can be attributed
        stats.overlap = stats.overlap + 1
        EndMail()
        return
    end
    local char = Char()
    index, attachment = Whole(index, 1, 100), Whole(attachment, 1, 16)
    if not (char and index and attachment and GetInboxItem and GetInboxInvoiceInfo) then return end
    local _, id, _, count = GetInboxItem(index, attachment)
    id, count = Whole(id, 1, 2147483647), Whole(count, 1, 2147483647)
    local invoice = Plain((GetInboxInvoiceInfo(index)))
    if not (id and count) or invoice ~= "buyer" then return end   -- only the mail of a purchase is a delivery
    local link = GetInboxItemLink and GetInboxItemLink(index, attachment) or nil
    local key = Cost().Key(link, id)
    local carried = W.Carried()
    if not (key and carried) then return end
    mail = { char = char, item = id, key = key, count = count, before = carried[key] or 0 }
    Bags()
    if C_Timer and C_Timer.NewTimer then
        local mine = mail
        mail.timer = C_Timer.NewTimer(WAIT, function()
            if mail == mine then stats.deliveryRefused = stats.deliveryRefused + 1; EndMail() end
        end)
    end
end

---------------------------------------------------------------------------
-- Crafts
---------------------------------------------------------------------------
-- A recipe whose materials and output are fixed: { out = item id, mats = { { item, qty } } }, or nil.
local function Schematic(recipe)
    local T = C_TradeSkillUI
    if not (T and T.GetRecipeSchematic and T.GetRecipeInfo) then return nil end
    local ok, info = pcall(T.GetRecipeInfo, recipe)
    info = ok and Plain(info) or nil
    if type(info) ~= "table" or Plain(info.learned) ~= true then return nil end   -- the player's own, learned recipe
    local ok2, s = pcall(T.GetRecipeSchematic, recipe, false)
    s = ok2 and Plain(s) or nil
    if type(s) ~= "table" then return nil end
    local out = Whole(s.outputItemID, 1, 2147483647)
    local slots = Plain(s.reagentSlotSchematics)
    if not out or type(slots) ~= "table" then return nil end
    local basic = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 1
    local merged, order = {}, {}
    for i = 1, #slots do
        local slot = Plain(slots[i])
        if type(slot) ~= "table" then return nil end
        if Plain(slot.reagentType) == basic then
            local reagents = Plain(slot.reagents)
            local only = type(reagents) == "table" and #reagents == 1 and Plain(reagents[1]) or nil
            local item = type(only) == "table" and Whole(only.itemID, 1, 2147483647) or nil
            local qty = Whole(slot.quantityRequired, 1, 10000)
            local vq = Plain(slot.variableQuantities)
            if not (item and qty) or (type(vq) == "table" and next(vq) ~= nil) then return nil end
            if merged[item] then merged[item] = merged[item] + qty else merged[item] = qty; order[#order + 1] = item end
        elseif Plain(slot.required) == true then
            return nil   -- a required extra, finishing or automatic reagent this version cannot account for
        end
    end
    if #order == 0 or #order > MAX_RECIPE_MATS then return nil end
    local mats = {}
    for i, item in ipairs(order) do mats[i] = { item = item, qty = merged[item] } end
    return { out = out, mats = mats }
end

local function Profession(recipe)
    local T = C_TradeSkillUI
    if not (T and T.GetProfessionInfoByRecipeID) then return nil end
    local ok, info = pcall(T.GetProfessionInfoByRecipeID, recipe)
    info = ok and Plain(info) or nil
    if type(info) ~= "table" then return nil end
    local id = Whole(info.parentProfessionID, 1, 2147483647) or Whole(info.professionID, 1, 2147483647)
    local name = Plain(info.parentProfessionName) or Plain(info.professionName)
    if not id then return nil end
    return id, type(name) == "string" and name or nil
end

local function EndCraft()
    if candidate then Cancel(candidate.timer) end
    candidate = nil
    Bags()
end

-- Not a verified craft: the identified stock of its materials can no longer be trusted.
local function Unverified(c)
    stats.refused = stats.refused + 1
    local keys = {}
    for _, m in ipairs(c.sch.mats) do keys[#keys + 1] = m.key end
    Cost().Disturbed(c.char, keys)
end

CraftSettle = function()
    local c = candidate
    if not (c and #c.results > 0) then return end
    local now = W.Carried()
    if not now then return end
    local out = c.sch.out
    local total = 0
    for _, r in ipairs(c.results) do total = total + r.quantity end
    local gained = (now[c.outKey] or 0) - c.before[c.outKey]
    local exact = (not c.bad) and gained == total
    for _, m in ipairs(c.sch.mats) do
        if (c.before[m.key] or 0) - (now[m.key] or 0) ~= m.qty then exact = false end
    end
    if not exact then return end   -- the bags may still be catching up: wait until the window ends
    EndCraft()
    local mats = {}
    for i, m in ipairs(c.sch.mats) do mats[i] = { key = m.key, item = m.item, qty = m.qty, before = c.before[m.key] or 0 } end
    local ok, why = Cost().Crafted(c.char, { recipe = c.recipe, profession = c.profession, professionName = c.professionName,
        out = { key = c.outKey, item = out, qty = total, before = c.before[c.outKey] or 0 }, mats = mats })
    if ok then stats.crafts = stats.crafts + 1 else stats.refused = stats.refused + 1 end
end

local function OnBegin(recipe)
    if not active then return end
    recipe = Whole(recipe, 1, 2147483647)
    if candidate then   -- a second craft began before the first settled: neither can be told apart
        stats.overlap = stats.overlap + 1
        local old = candidate
        EndCraft()
        Unverified(old)
        return
    end
    local char, cost = Char(), Cost()
    if not (recipe and char and cost) then return end
    local sch = Schematic(recipe)
    if not sch then return end
    local carried = W.Carried()
    if not carried then return end
    local c = { char = char, recipe = recipe, sch = sch, results = {}, before = carried, seen = {} }
    for _, m in ipairs(sch.mats) do m.key = cost.Key(nil, m.item); c.before[m.key] = c.before[m.key] or 0 end
    c.outKey = cost.Key(nil, sch.out)
    c.before[c.outKey] = c.before[c.outKey] or 0
    c.profession, c.professionName = Profession(recipe)
    candidate = c
    Bags()
    if C_Timer and C_Timer.NewTimer then
        c.timer = C_Timer.NewTimer(WAIT, function()
            if candidate ~= c then return end
            local had = #c.results > 0
            EndCraft()
            if had then Unverified(c) end   -- a craft that produced something the bags never confirmed
        end)
    end
end

local function OnResult(data)
    local c = candidate
    if not c then return end
    data = Plain(data)
    if type(data) ~= "table" then c.bad = true return end
    if Plain(data.firstCraftReward) == true then return end   -- experience and similar rewards are not output items
    local item, qty = Whole(data.itemID, 1, 2147483647), Whole(data.quantity, 1, 10000000)
    local guid = Plain(data.itemGUID)
    local returned = Plain(data.resourcesReturned)
    if not (item and qty) or item ~= c.sch.out or (type(returned) == "table" and next(returned) ~= nil)
        or (Whole(data.ingenuityRefund, 0, 1000000) or 0) > 0 then
        c.bad = true   -- another item, returned materials or an unreadable result: consumption cannot be verified
        c.results[#c.results + 1] = { quantity = 0 }
        return
    end
    if type(guid) == "string" then
        if c.seen[guid] then c.bad = true return end   -- the same result twice
        c.seen[guid] = true
    end
    c.results[#c.results + 1] = { quantity = qty }
    OnBags()   -- the bags may already show the craft (the order of the two is not known)
end

function W.Refresh(on)
    on = on == true
    if on and not active then
        active = true
        if not hooked and type(TakeInboxItem) == "function" and hooksecurefunc then
            hooksecurefunc("TakeInboxItem", OnTake); hooked = true
        end
        Want("TRADE_SKILL_CRAFT_BEGIN", OnBegin, true)
        Want("TRADE_SKILL_ITEM_CRAFTED_RESULT", OnResult, true)
    elseif not on and active then
        active = false
        if candidate then local c = candidate; EndCraft(); if #c.results > 0 then Unverified(c) end end
        EndMail()
        Want("TRADE_SKILL_CRAFT_BEGIN", nil, false)
        Want("TRADE_SKILL_ITEM_CRAFTED_RESULT", nil, false)
    end
end

function W.Snapshot()
    local n = 0
    for _ in pairs(watching) do n = n + 1 end
    local copy = {}
    for k, v in pairs(stats) do copy[k] = v end
    return { active = active, events = n, candidates = (candidate and 1 or 0) + (mail and 1 or 0), stats = copy }
end

if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("ledger.cost.events", { label = "Gold ledger cost basis: events registered", unit = "count", kind = "listeners",
        group = "workshop", read = function() return W.Snapshot().events end })
end
