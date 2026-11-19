-- TwichUI: the mailbox gold summary
-- One line in your own chat when you close the mailbox: the money you took from mail during that visit.
-- Each opening of the mailbox is a visit of its own; nothing is saved, and nothing is said if no money was taken.
-- It is a total of what the mail paid you (auction proceeds, money other players sent), not a profit figure.
--
-- How money is attributed (see docs/mailbox-gold-summary.md):
--   * A take REQUEST is noted when the game's TakeInboxMoney or AutoLootMailItem is called (a post-hook: the
--     call runs as it always did). It holds the amount the mailbox showed for that message at that moment and
--     the visit it belongs to; the message's position is never used again, since positions shift as mail goes.
--     A post-hook cannot be sure the game has not already cleared the message's money, so the amount the mailbox
--     showed at its last update is kept per position and used when the message reads empty at the call (once per
--     position until the next update).
--     Messages with a cash-on-delivery charge are not noted: taking those pays money out.
--   * A request COUNTS only when PLAYER_MONEY then shows a gain of exactly that amount (the oldest matching
--     request first; two requests together if the game reported both as one change). A call alone proves nothing.
--     Postage, COD payments and other spending are losses and are ignored; a gain that matches no waiting
--     request (a loot drop, a trade) is ignored too.
--   * A request is dropped when MAIL_FAILED arrives without an item (a refusal), or after EXPIRY seconds with
--     no matching gain (a call the game ignored). It then counts for nothing.
--   * The gold ledger (auction/Ledger.lua) is told once for each matched gain, as evidence of exactly that amount: "Mail
--     collected", or "Auction sale" when every message in the gain carries a seller's invoice. Nothing else here reaches the
--     ledger: a call alone, a refusal, an expiry, a loss or a gain that matches no request is never evidence.
-- A visit that closes with requests still waiting is finished once they are answered or have expired (a few
-- seconds at most); a late gain goes to the visit its request came from, never to the next one.

local R = TwichUI
local MG = {}
R.MailGold = MG

local EXPIRY = 4          -- seconds a request may wait for its money
local MAX_WAITING = 50    -- requests waiting at once, at most (the inbox holds that many messages); more are not counted

local session             -- the open visit, or nil
local queue = {}          -- requests waiting for their money, oldest first: { session, amount, done }
local lastMoney           -- GetMoney() as of the last PLAYER_MONEY (or the visit's start)
local hooked = false      -- the hooks are installed once and cannot be removed; `active` gates them
local active = false
local watching = {}       -- event -> handler, for the events heard only while there is something to watch
local known = {}          -- inbox position -> money the mailbox showed at its last update (cash-on-delivery mail is left out)
local knownInvoice = {}   -- inbox position -> { kind, item } of a seller's invoice seen at that update (only while the ledger records)
local credits = 0         -- evidence sent to the ledger so far (its correlation ids)
local moneyKey, moneyEntry -- next journal ID before this visit's next nonzero PLAYER_MONEY
local deferred, deferredCount = {}, 0 -- at most eight exact targets waiting for recorder event order
local stats = { ambiguous = 0, settlement = 0, unavailable = 0 }

local function Num(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    if type(v) ~= "number" or v ~= v then return nil end
    return v
end

local function Want(event, handler, wanted)
    if wanted and not watching[event] then
        watching[event] = handler
        R:On(event, handler)
    elseif not wanted and watching[event] then
        R:Off(event, watching[event])
        watching[event] = nil
    end
end

function MG.Enabled() return R:Enabled("mailGoldSummary") end

-- Listening is needed for the chat summary, or for the gold ledger's evidence; the chat line is said only for the former.
local function LedgerOn() return R.Ledger ~= nil and R.Ledger.Active ~= nil and R.Ledger.Active() == true end
local function Tracking() return MG.Enabled() or LedgerOn() end
local function Cursor()
    local L = R.Ledger
    if not LedgerOn() then return end
    local key = L.CharKey()
    local rec = key and L.Record(key)
    return key, rec and rec.nextId
end

-- A sold-auction invoice, when the mailbox offers one for this message: "ahSale" and the item's name. Whether the game gives it
-- before the message is opened is unverified; with no invoice the money is plain mail.
local function Invoice(index, money)
    if type(GetInboxInvoiceInfo) ~= "function" then return nil end
    local ok, kind, item, player, bid, buyout, deposit, fee, delay, hour, minute, count = pcall(GetInboxInvoiceInfo, index)
    if not ok or type(kind) ~= "string" or (issecretvalue and issecretvalue(kind)) then return nil end
    if kind ~= "seller" then return nil end
    if type(item) ~= "string" or (issecretvalue and issecretvalue(item)) then item = nil end
    count = Num(count)
    if not count or count < 1 or count > 2147483647 or math.floor(count) ~= count then count = nil end
    local L = R.Ledger
    local settlement = L and L.Settlement and L.Settlement({ v = 1, invoices = { { g = bid, d = deposit, f = fee, c = money, n = item, q = count } } }, money)
    return "ahSale", item, count, settlement
end

local function MoneyText(copper)
    local RS = R.Restock
    if RS and RS.ColorMoney then return RS.ColorMoney(copper) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- Money and cash-on-delivery charge of one message, or nil when either cannot be read. A missing charge is none.
local function Read(index)
    local _, _, _, _, money, cod = GetInboxHeaderInfo(index)
    if cod ~= nil then cod = Num(cod) else cod = 0 end
    money = Num(money)
    if not (money and cod) then return nil end
    return money, cod
end

-- What the mailbox shows now, kept per position for Record. Bounded by the inbox size.
local function Snapshot()
    for k in pairs(known) do known[k] = nil end
    for k in pairs(knownInvoice) do knownInvoice[k] = nil end
    if type(GetInboxNumItems) ~= "function" then return end
    local n = Num((GetInboxNumItems())) or 0
    local ledger = LedgerOn()
    for i = 1, math.min(n, MAX_WAITING) do
        local money, cod = Read(i)
        if money and money > 0 and cod == 0 then
            known[i] = money
            if ledger then
                local kind, item, qty, settlement = Invoice(i, money)
                if kind then knownInvoice[i] = { kind, item, qty, settlement } end
            end
        end
    end
end

-- At most one line per visit, and only for money.
local function Summarize(s)
    if s.printed then return end
    s.printed = true
    if s.total > 0 and MG.Enabled() then   -- the line is the summary switch's; the ledger needs none of it
        R.Print("Collected %s from mail.", MoneyText(s.total))
    end
end

-- Nothing open and nothing waiting: stop listening.
local function Rest()
    if not session and #queue == 0 then
        Want("PLAYER_MONEY", nil, false)
        Want("MAIL_FAILED", nil, false)
    end
end

-- A request is answered: its money arrived (collected) or it will not (not).
local function Finish(req, collected)
    if req.done then return end
    req.done = true
    if req.session.inflight[req.index] == req then req.session.inflight[req.index] = nil end
    for i = 1, #queue do
        if queue[i] == req then table.remove(queue, i) break end
    end
    local s = req.session
    s.waiting = s.waiting - 1
    if collected then s.total = s.total + req.amount end
    if not s.open and s.waiting == 0 then Summarize(s) end
    Rest()
end

-- One matched gain is one piece of evidence for the ledger, whatever number of requests it paid: an auction sale only when
-- every message in it is a seller's invoice, otherwise mail collected.
local function Credit(amount, matched)
    local L = R.Ledger
    if not (LedgerOn() and L and L.Evidence and matched.entry and matched.char) then return end
    local kind, note, qty = "ahSale", nil, nil
    local invoices = {}
    for _, req in ipairs(matched) do
        if req.kind ~= "ahSale" then kind = "mail" end
        if req.settlement then invoices[#invoices + 1] = req.settlement.invoices[1] end
    end
    if kind == "ahSale" and #matched == 1 then note, qty = matched[1].note, matched[1].qty end
    local settlement = kind == "ahSale" and #invoices == #matched and L.Settlement({ v = 1, invoices = invoices }, amount) or nil
    if kind == "ahSale" then
        local field = settlement and "settlement" or "unavailable"
        stats[field] = stats[field] + 1
    end
    credits = credits + 1
    local ev = { kind = kind, amount = amount, note = note, qty = qty, settlement = settlement,
        corr = "mail:" .. credits, entry = matched.entry, char = matched.char }
    local function Offer()
        if not LedgerOn() then return end
        local ok, err = pcall(L.Evidence, ev)
        if not ok then R.Fault("mailbox gold summary", err) end
    end
    local rec = L.Record(matched.char)
    if rec and rec.nextId == matched.entry then
        if deferredCount >= 8 then return end
        deferred[ev], deferredCount = true, deferredCount + 1
        C_Timer.After(0, function()
            if not deferred[ev] then return end
            deferred[ev], deferredCount = nil, deferredCount - 1
            Offer()
        end)
    else Offer() end
end

local function OnMoney()
    local now = Num(GetMoney())
    local before = lastMoney
    lastMoney = now
    if not (now and before) then return end
    local gain = now - before
    local key, nextId = Cursor()
    local target
    if gain ~= 0 and key == moneyKey and moneyEntry and nextId and (nextId == moneyEntry or nextId == moneyEntry + 1) then target = moneyEntry end
    moneyKey, moneyEntry = key, target and target + 1 or nextId
    if gain <= 0 or #queue == 0 then return end
    -- A stalled frame must not let an overdue request claim later money before its timer runs.
    local mono = GetTime and Num(GetTime())
    for i = #queue, 1, -1 do if mono and queue[i].expires and mono >= queue[i].expires then Finish(queue[i], false) end end
    if #queue == 0 then return end
    local matched
    if queue[1].amount == gain then
        matched = { queue[1] }
    else
        -- Two or more of the oldest, reported as one change.
        local sum, group = queue[1].amount, { queue[1] }
        for k = 2, #queue do
            sum = sum + queue[k].amount
            group[k] = queue[k]
            if sum == gain then matched = group break end
            if sum > gain then break end
        end
        if not matched then
            for i = 2, #queue do
                if queue[i].amount == gain then matched = { queue[i] } break end
            end
        end
    end
    if not matched then return end
    local chosen, unique = {}, target ~= nil
    for _, req in ipairs(matched) do chosen[req] = true; if req.ambiguous or req.char ~= key then unique = false end end
    -- Positive amounts: a selected prefix is unique if every unselected request exceeds the entire gain.
    -- Otherwise retain the V1 chat summary but refuse attribution for the ambiguous outstanding requests.
    for _, req in ipairs(queue) do if not chosen[req] and req.amount <= gain then unique = false end end
    if not unique then
        for _, req in ipairs(queue) do req.ambiguous = true end
        stats.ambiguous = stats.ambiguous + 1
    end
    matched.entry, matched.char = target, key
    for _, req in ipairs(matched) do Finish(req, true) end
    if unique then Credit(gain, matched) end
end

local function OnFailed(itemID)
    if itemID ~= nil then return end   -- an item that could not be taken; its money (if any) is a separate matter
    if queue[1] then Finish(queue[1], false) end
end

local function CloseVisit(s)
    if not s.open then return end
    s.open = false
    if session == s then session = nil end
    for k in pairs(known) do known[k] = nil end
    for k in pairs(knownInvoice) do knownInvoice[k] = nil end
    Want("MAIL_INBOX_UPDATE", nil, false)
    if s.waiting == 0 then Summarize(s) end
    Rest()
end

local function OnShow()
    if session then CloseVisit(session) end   -- the last visit never said it closed: it is over
    session = { open = true, total = 0, waiting = 0, inflight = {} }
    lastMoney = Num(GetMoney())
    moneyKey, moneyEntry = Cursor()
    Want("PLAYER_MONEY", OnMoney, true)
    Want("MAIL_FAILED", OnFailed, true)
    Want("MAIL_INBOX_UPDATE", Snapshot, true)
    Snapshot()
end

local function OnClosed()
    if session then CloseVisit(session) end
end

-- A loading screen ends the visit, and anything still waiting cannot be answered reliably any more.
local function OnLeaving()
    if session then CloseVisit(session) end
    while queue[1] do Finish(queue[1], false) end
    lastMoney = nil
    moneyKey, moneyEntry = nil, nil
end

-- A take is asked for. Noted only; whether it worked is for PLAYER_MONEY to say.
local function Record(index)
    local s = session
    if not (active and s and s.open and type(index) == "number") then return end
    if #queue >= MAX_WAITING then return end
    local money, cod = Read(index)
    if not money or cod ~= 0 then return end
    local remembered = known[index]
    known[index] = nil   -- this position's money is being taken; a second call must not use it again
    if money <= 0 then money = remembered end
    if not money or money <= 0 then return end
    local kind, note, qty, settlement
    if LedgerOn() then
        kind, note, qty, settlement = Invoice(index, money)
        local seenBefore = knownInvoice[index]
        if not kind and seenBefore then kind, note, qty, settlement = unpack(seenBefore) end
    end
    knownInvoice[index] = nil
    local duplicate = s.inflight[index]
    if duplicate then duplicate.ambiguous = true end
    local req = { session = s, index = index, amount = money, kind = kind, note = note, qty = qty, settlement = settlement, ambiguous = duplicate ~= nil,
        char = LedgerOn() and R.Ledger.CharKey() or nil, expires = GetTime and GetTime() + EXPIRY or nil }
    queue[#queue + 1] = req
    s.inflight[index] = req
    s.waiting = s.waiting + 1
    C_Timer.After(EXPIRY, function() Finish(req, false) end)
end

local function Noted(index)
    local ok, err = pcall(Record, index)
    if not ok then R.Fault("mailbox gold summary", err) end
end

local function Hook()
    hooked = true
    for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
        if type(_G[name]) == "function" then hooksecurefunc(name, Noted) end
    end
end

-- Whatever was open or waiting is let go without saying anything (switched off, or the profile changed).
local function Abandon()
    if session then session.open, session.printed, session = false, true, nil end
    for _, req in ipairs(queue) do req.done, req.session.printed = true, true end
    for i = #queue, 1, -1 do queue[i] = nil end
    lastMoney = nil
    moneyKey, moneyEntry = nil, nil
    for ev in pairs(deferred) do deferred[ev] = nil end
    deferredCount = 0
    for k in pairs(known) do known[k] = nil end
    for k in pairs(knownInvoice) do knownInvoice[k] = nil end
    Want("MAIL_INBOX_UPDATE", nil, false)
    Rest()
end

-- Safe to call any time, as often as you like: makes the listening match the switch.
function MG.Refresh()
    local on = Tracking()
    if on and not hooked then Hook() end
    active = on
    Want("MAIL_SHOW", OnShow, on)
    Want("MAIL_CLOSED", OnClosed, on)
    Want("PLAYER_LEAVING_WORLD", OnLeaving, on)
    if not on then Abandon() end
    if on and session and LedgerOn() and not moneyEntry then moneyKey, moneyEntry = Cursor() end
end

-- Counts only, for the tests: whether a visit is open and how many requests wait.
function MG.Snapshot() return { open = session ~= nil, waiting = #queue, deferred = deferredCount,
    ambiguous = stats.ambiguous, settlement = stats.settlement, unavailable = stats.unavailable } end

if R.Perf and R.Perf.Gauge then
    for _, key in ipairs({ "waiting", "deferred", "ambiguous", "settlement", "unavailable" }) do
        local field = key
        R.Perf.Gauge("ledger.mail." .. field, { label = "Ledger mailbox: " .. field, group = "workshop",
            unit = "count", kind = "cache", read = function() return MG.Snapshot()[field] end })
    end
end

if R.Perf and R.Perf.Wrap then
    OnMoney = R.Perf.Wrap("ledger.mail", OnMoney)
    Snapshot = R.Perf.Wrap("ledger.mail", Snapshot)
    Record = R.Perf.Wrap("ledger.mail", Record)
end

R:OnInit(MG.Refresh)
