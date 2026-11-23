-- Live, read-only queue material quote. No purchase API or historical vendor data.
local R = TwichUI
local W = R.Workshop
local UI, O, S = W.UI, W.Observe, W.Session
local M = { LIMIT = 512 }
W.MerchantReview = M
local frame, events, pending, generation, dismissed = nil, nil, false, 0, false
local Schedule
local MAX_MONEY = 9007199254740991
local function Int(v, lo, hi) return W.Int(v, lo, hi) end
local function Open()
    return W.Active() and MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()
        and not (InCombatLockdown and InCombatLockdown()) and not W.Queue.Held()
end

-- Only this synchronous live listing is quoted. O.ReadMerchant omits unavailable
-- listings, so read the same verified API here to distinguish sold-out/unsupported.
function M.Read()
    if not Open() then return nil, 'closed or restricted' end
    if not (UnitGUID and GetMerchantNumItems and GetMerchantItemID and C_MerchantFrame and C_MerchantFrame.GetItemInfo
        and GetMerchantItemCostInfo) then return nil, 'merchant API unavailable' end
    local guid = W.Plain(UnitGUID('npc'))
    if type(guid) ~= 'string' or guid == '' then return nil, 'merchant identity unavailable' end
    local n = Int(GetMerchantNumItems(), 0, 1000)
    if not n or n == 0 then return nil, 'merchant listings pending' end
    local out = {}
    for i = 1, n do
        local ok, id, t, costs = pcall(function()
            return GetMerchantItemID(i), C_MerchantFrame.GetItemInfo(i), GetMerchantItemCostInfo(i)
        end)
        id, t = ok and Int(id, 1, W.MAX_ID), ok and W.Plain(t)
        if id and type(t) == 'table' and not out[id] then
            local price, stack, stock = Int(t.price, 0, W.MAX_ID), Int(t.stackCount, 1, W.MAX_QTY), Int(t.numAvailable, -1, W.MAX_ID)
            local currencyKnown = not (issecretvalue and issecretvalue(t.currencyID))
            local moneyOnly = currencyKnown and W.Plain(t.hasExtendedCost) == false and W.Plain(t.currencyID) == nil and Int(costs, 0, W.MAX_ID) == 0
            out[id] = { price = price, stack = stack, stock = stock,
                eligible = moneyOnly and W.Plain(t.isPurchasable) == true and price ~= nil and stack ~= nil and stock ~= nil }
        end
    end
    if W.Plain(UnitGUID('npc')) ~= guid or not Open() then return nil, 'merchant changed' end
    return out
end

-- Pure adapter over the current ShoppingPlan, never Vendor's remembered prices.
-- Round DOWN to complete purchases: quoting a bundle must not exceed queue need.
function M.Quote(plan, listings, state)
    local q = { rows = {}, total = 0, relevant = false, truncated = false }
    if state == 'planning' or not plan or (plan.unknownBags or 0) > 0 then
        q.reason = 'Queue needs are pending or bag counts are unknown. Refresh when ready.'
        return q
    end
    local needs = {}
    for _, r in ipairs(plan.rows or {}) do
        local id, qty = Int(r.item, 1, W.MAX_ID), Int(r.qty, 1, W.MAX_ID)
        if r.kind == 'buy' and id and qty then needs[id] = math.min(W.MAX_ID, (needs[id] or 0) + qty) end
    end
    local ids = {}
    for id in pairs(needs) do ids[#ids + 1] = id end
    table.sort(ids)
    for i, id in ipairs(ids) do
        if i > M.LIMIT then q.truncated = true; break end
        local v, need = listings[id], needs[id]
        local r = { item = id, need = need, qty = 0, cost = 0, status = 'Not sold here or listing unreadable' }
        if v then
            q.relevant = true
            r.stack, r.stock, r.price = v.stack, v.stock, v.price
            if v.stock == 0 then r.status = 'Sold out'
            elseif not v.eligible then r.status = 'Unavailable or non-gold cost; not quoted'
            else
                local available = v.stock == -1 and need or math.min(need, v.stock)
                r.qty = math.floor(available / v.stack) * v.stack
                r.cost = r.qty / v.stack * v.price
                if r.cost > MAX_MONEY - q.total then
                    r.qty, r.cost, r.status = 0, 0, 'Cost exceeds quote limit'
                else
                    q.total = q.total + r.cost
                    r.status = r.qty == 0 and 'No full purchase fits outstanding need'
                        or (r.qty < need and 'Partial quantity; remainder still needed' or 'Quoted')
                end
            end
        end
        q.rows[#q.rows + 1] = r
    end
    return q
end

local function Money(n) return UI.Coins and UI.Coins.Text(n) or UI.Money(n) end
local function MakeRow(parent)
    local row = CreateFrame('Frame', nil, parent)
    row.icon = UI.ItemIcon(row, 26)
    row.icon:SetPoint('LEFT', 4, 0)
    row.name = UI.Text(row, 13, UI.K.text, 'strong')
    row.name:SetPoint('TOPLEFT', row.icon, 'TOPRIGHT', 8, 1)
    row.name:SetPoint('RIGHT', -8, 0)
    row.details = UI.Text(row, 11, UI.K.textDim)
    row.details:SetPoint('TOPLEFT', row.name, 'BOTTOMLEFT', 0, -3)
    row.details:SetPoint('RIGHT', -8, 0)
    row.details:SetWordWrap(true)
    row.fill = function(self, r)
        local name, icon, quality = O.ItemFacts(r.item)
        self.name:SetText(name or ('Item #' .. r.item))
        if UI.ItemQuality then UI.ItemQuality(self.name, quality) else UI.Paint(self.name, UI.K.text) end
        self.icon.tex:SetTexture(icon or UI.ICON_BLANK)
        local stock = r.stock == -1 and 'unlimited' or (r.stock ~= nil and tostring(r.stock) or 'unknown')
        local price = r.price and r.stack and (Money(r.price) .. ' / purchase of ' .. r.stack) or 'price unavailable'
        self.details:SetText(('Need %d · Stock %s · Quote %d\n%s · %s'):format(r.need, stock, r.qty, price, r.status))
    end
    return row
end
local function Build()
    UI.Init()
    frame = CreateFrame('Frame', 'TwichUIWorkshopMerchantQuote', UIParent)
    frame:Hide()
    frame:SetSize(720, 390)
    frame:SetPoint('CENTER', UIParent, 'CENTER', 180, 0)
    frame:SetFrameStrata('DIALOG')
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    UI.Panel(frame, 'espresso')
    frame.title = UI.Text(frame, 19, UI.K.text, 'serif')
    frame.title:SetPoint('TOPLEFT', 16, -14)
    frame.title:SetText('Craft Queue · Merchant quote')
    local close = UI.Button(frame, 'Close', 60, 'secondary', function() dismissed = true; M.Hide() end)
    close:SetPoint('TOPRIGHT', -12, -10)
    frame.note = UI.Text(frame, 12, UI.K.textDim)
    frame.note:SetPoint('TOPLEFT', 16, -47)
    frame.note:SetWidth(686)
    frame.note:SetText('Read-only estimate. Purchase manually in the merchant window; no gold is spent here.')
    frame.list = UI.List(frame, 64, MakeRow, 160)
    frame.list.box:SetPoint('TOPLEFT', 12, -72)
    frame.list.box:SetPoint('BOTTOMRIGHT', -12, 100)
    frame.total = UI.Text(frame, 13, UI.K.bronzeText, 'strong')
    frame.total:SetPoint('BOTTOMLEFT', 16, 72)
    frame.limit = UI.Text(frame, 11, UI.K.textDim)
    frame.limit:SetPoint('BOTTOMLEFT', 16, 36)
    frame.limit:SetWidth(680)
    frame.limit:SetWordWrap(true)
    frame.limit:SetText('Whole purchases only; stock conservatively treated as items. Bag capacity is unverified. First listing per item; no purchase authorization.')
    local refresh = UI.Button(frame, 'Refresh quote', 110, 'secondary', function() M.Refresh(true) end)
    refresh:SetPoint('BOTTOMRIGHT', -14, 8)
    UISpecialFrames[#UISpecialFrames + 1] = 'TwichUIWorkshopMerchantQuote'
    frame:SetScript('OnHide', function() dismissed = true; M.Hide() end)
end
function M.Hide()
    generation, pending = generation + 1, false
    if W.Strategy and W.Strategy.Listen then W.Strategy.Listen(Schedule, false) end
    if frame then frame:Hide(); frame.list:SetData({}); frame.quote = nil end
end
function M.Refresh(explicit)
    if dismissed and not explicit then return end
    if explicit then dismissed = false end
    if not Open() then M.Hide(); return end
    if W.Strategy and W.Strategy.Listen then W.Strategy.Listen(Schedule, true) end
    local listings = M.Read()
    if not listings then M.Hide(); return end
    local plan, _, state = S.ShoppingPlan()
    local quote = M.Quote(plan, listings, state)
    -- The planner's existing listener refreshes when cooperative work finishes.
    -- Never show the previous plan as a current quote while it is planning.
    if not quote.relevant and not (frame and frame:IsShown()) then return end
    if not frame then Build() end
    local money = GetMoney and Int(GetMoney(), 0, MAX_MONEY)
    frame.quote = quote
    frame.list:SetData(quote.rows, quote.reason or 'No outstanding material purchases.')
    frame.total:SetText('Estimated total: ' .. Money(quote.total) .. ' (' .. quote.total .. ' copper)'
        .. (money and quote.total > money and ' · Insufficient money' or (not money and ' · Money unknown' or ''))
        .. (quote.truncated and ' · REPORT TRUNCATED' or ''))
    frame:Show()
    if R.FitToScreen then R.FitToScreen(frame) end
end
Schedule = function()
    if pending or dismissed or not Open() then return end
    pending = true
    local mine = generation
    C_Timer.After(0.2, function()
        if mine ~= generation then return end
        pending = false
        M.Refresh(false)
    end)
end
function M.Start()
    if not events then
        events = CreateFrame('Frame')
        events:SetScript('OnEvent', function(_, event)
            if event == 'MERCHANT_CLOSED' or event == 'PLAYER_REGEN_DISABLED' then M.Hide(); return end
            if event == 'MERCHANT_SHOW' then dismissed = false end
            -- Nested make materials are not all represented in Session.PlanKey's
            -- root bag signature; invalidate the planner even with Workshop hidden.
            if event == 'BAG_UPDATE_DELAYED' and W.Strategy then W.Strategy.Bump() end
            Schedule()
        end)
    end
    if not W.Active() then return end
    for _, e in ipairs({ 'MERCHANT_SHOW', 'MERCHANT_UPDATE', 'MERCHANT_CLOSED', 'BAG_UPDATE_DELAYED',
        'PLAYER_MONEY', 'GET_ITEM_INFO_RECEIVED', 'ITEM_DATA_LOAD_RESULT', 'PLAYER_REGEN_DISABLED' }) do events:RegisterEvent(e) end
    Schedule()
end
function M.Stop()
    M.Hide()
    if events then events:UnregisterAllEvents() end
end
function M.Stats() return { shown = frame and frame:IsShown() or false, built = frame ~= nil } end
M.Start()
