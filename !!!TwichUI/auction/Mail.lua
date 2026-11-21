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
--   * A request COUNTS only when PLAYER_MONEY then shows a gain of exactly that amount (one waiting request, or several the
--     game reported as one change). A call alone proves nothing. When more than one set of waiting requests could explain the
--     gain, the oldest set is taken for the chat total, and the ledger is told only what every possible set agrees on: an
--     auction sale only if every explanation is made of sold-auction mail, its invoice details only if they are the same in all.
--     Postage, COD payments and other spending are losses and are ignored; a gain that matches no waiting
--     request (a loot drop, a trade) is ignored too.
--   * A request is dropped when MAIL_FAILED arrives without an item (a refusal), or after EXPIRY seconds with
--     no matching gain (a call the game ignored), extended while the game still says a mail command is pending
--     (C_Mail.IsCommandPending), never past MAX_AGE. It then counts for nothing.
--   * A second call for the same message (same position, same header, no inbox update between) is a SPARE: it is never matched
--     to money and only waits out its expiry, so the chat line keeps V1's timing (it waits for it). After an
--     inbox update a position can hold a different message: Blizzard's Open All takes position 1 again once the paid
--     message was deleted, often before the first payment's PLAYER_MONEY. That is a new request, never a duplicate.
--   * Which kind of mail a request is: a seller's invoice (GetInboxInvoiceInfo "seller", with its gross/fee/deposit when they
--     reconcile), or, when the message gives no invoice (the game may give it only after the message was opened), the Auction
--     House's own sold-auction mail: the client's AUCTION_SOLD_MAIL_SUBJECT on a message that cannot be answered, from no GM,
--     with no attachment. Its fee and deposit are then unavailable, never guessed. Anything else is plain mail.
--   * The gold ledger (auction/Ledger.lua) is told once for each matched gain, as evidence of exactly that amount: "Mail
--     collected", or "Auction sale" when every message of every explanation of the gain is seller mail (invoice, or the sold-auction
--     mail). Nothing else here reaches the ledger: a call alone, a refusal, an expiry, a loss, a spare or a gain that matches no
--     request is never evidence.
-- A visit that closes with requests still waiting is finished once they are answered or have expired (a few
-- seconds at most); a late gain goes to the visit its request came from, never to the next one.

local R = TwichUI
local MG = {}
R.MailGold = MG

local EXPIRY = 4          -- seconds a request may wait for its money
local MAX_AGE = 15        -- ... at most, however long the game keeps a mail command pending
local MAX_SEARCH = 12     -- waiting requests (oldest first) searched for the sets that explain one gain
local MAX_WAYS = 16       -- explanations looked at; more and the gain is matched for the chat total only
local MAX_WAITING = 50    -- requests waiting at once, at most (the inbox holds that many messages); more are not counted

local session             -- the open visit, or nil
local queue = {}          -- requests waiting for their money, oldest first: { session, amount, done }
local lastMoney           -- GetMoney() as of the last PLAYER_MONEY (or the visit's start)
local hooked = false      -- the hooks are installed once and cannot be removed; `active` gates them
local active = false
local watching = {}       -- event -> handler, for the events heard only while there is something to watch
local known = {}          -- inbox position -> money the mailbox showed at its last update (cash-on-delivery mail is left out)
local knownInvoice = {}   -- inbox position -> { kind, item, qty, settlement, how, mark } seen at that update (only while the ledger records)
local credits = 0         -- evidence sent to the ledger so far (its correlation ids)
local moneyKey, moneyEntry -- next journal ID before this visit's next nonzero PLAYER_MONEY
local deferred, deferredCount = {}, 0 -- at most eight exact targets waiting for recorder event order
local stats = { ambiguous = 0, settlement = 0, unavailable = 0, requests = 0, verified = 0, soldMail = 0, combined = 0, exact = 0 }
-- Why a request or a gain did not become exact evidence: fixed codes, session counts only (diagnostics; nothing personal)
local why = {}
local function Why(code) why[code] = (why[code] or 0) + 1 end

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

-- The invoice type the mailbox gives for a message ("seller", "buyer", "seller_temp_invoice", ...), or nil when it gives none.
local function InvoiceType(index)
    if type(GetInboxInvoiceInfo) ~= "function" then return nil end
    local ok, kind = pcall(GetInboxInvoiceInfo, index)
    if not ok or type(kind) ~= "string" or (issecretvalue and issecretvalue(kind)) then return nil end
    return kind
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

-- The client's own sold-auction subject ("Auction successful: %s") as a pattern capturing the item name; nil when the client has none.
local soldPattern, soldFrom
local function SoldPattern()
    local fmt = type(AUCTION_SOLD_MAIL_SUBJECT) == "string" and AUCTION_SOLD_MAIL_SUBJECT or nil
    if fmt ~= soldFrom then
        soldFrom, soldPattern = fmt, nil
        local a, b
        if fmt then a, b = fmt:find("%s", 1, true) end
        if a and not fmt:find("%", b + 1, true) and not fmt:sub(1, a - 1):find("%", 1, true) then
            local function Esc(t) return (t:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0")) end
            soldPattern = "^" .. Esc(fmt:sub(1, a - 1)) .. "(.+)" .. Esc(fmt:sub(b + 1)) .. "$"
        end
    end
    return soldPattern
end

-- A message's header, read once: what identifies it while it is in the inbox (kept in memory only, never saved or reported),
-- and whether it is the Auction House's sold-auction mail (with the item name its subject gives).
local function Header(index)
    local ok, _, _, sender, subject, _, _, days, items, _, returned, _, canReply, isGM = pcall(GetInboxHeaderInfo, index)
    if not ok then return nil end
    local function Str(v) if type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return "" end return v end
    local mark = Str(sender) .. "\0" .. Str(subject) .. "\0" .. tostring(Num(days) or "")
    local sold
    local pattern = SoldPattern()
    items = Num(items) or 0
    if pattern and canReply == false and not isGM and returned ~= true and items == 0 then
        local item = Str(subject):match(pattern)
        if item and item ~= "" then sold = item end
    end
    return mark, sold
end

-- What kind of mail a request is: "ahSale" with how it is known ("invoice", with a reconciled settlement when every field
-- agrees, or "soldmail"), or nil for plain mail. explicit: the invoice said it is something else (never overruled by a subject).
local function Evidence(index, money)
    local kind, item, qty, settlement = Invoice(index, money)
    if kind then return kind, item, qty, settlement, "invoice" end
    local _, sold = Header(index)
    if sold and not InvoiceType(index) then return "ahSale", sold, nil, nil, "soldmail" end
    return nil
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

-- What the mailbox shows now, kept per position for Record. Bounded by the inbox size. An update can move messages, so
-- positions noted before it no longer say which message a later call is for: the in-flight positions are forgotten here (the
-- requests themselves keep waiting for their money).
local function Snapshot()
    for k in pairs(known) do known[k] = nil end
    for k in pairs(knownInvoice) do knownInvoice[k] = nil end
    if session then for k in pairs(session.inflight) do session.inflight[k] = nil end end
    if type(GetInboxNumItems) ~= "function" then return end
    local n = Num((GetInboxNumItems())) or 0
    local ledger = LedgerOn()
    for i = 1, math.min(n, MAX_WAITING) do
        local money, cod = Read(i)
        if money and money > 0 and cod == 0 then
            known[i] = money
            if ledger then
                local kind, item, qty, settlement, how = Evidence(i, money)
                if kind then knownInvoice[i] = { kind, item, qty, settlement, how, (Header(i)) } end
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

-- How a request reads to the ledger: a short signature of its kind and invoice facts. Two explanations of one gain give the
-- same evidence only when their signatures agree (equal sales of the same item, say).
local function Signature(req)
    local kind = req.unsureKind and "mail" or (req.kind or "mail")
    local inv = not req.unsure and req.settlement and req.settlement.invoices[1]
    local detail = inv and table.concat({ inv.g, inv.f, inv.d, inv.c, tostring(inv.n), tostring(inv.q) }, ":") or ""
    return kind .. "|" .. (req.how or "") .. "|" .. (req.unsure and "" or tostring(req.note)) .. "|" .. tostring(req.qty) .. "|" .. detail
end
local function SetSignature(set)
    local list = {}
    for i, req in ipairs(set) do list[i] = Signature(req) end
    table.sort(list)
    return table.concat(list, "\1")
end

-- One matched gain is one piece of evidence for the ledger, whatever number of requests it paid. ways: every set of waiting
-- requests that could explain it (the matched one included). The ledger is told only what all of them agree on.
local function Credit(amount, matched, ways)
    local L = R.Ledger
    if not (LedgerOn() and L and L.Evidence) then return end
    if not (matched.entry and matched.char) then Why("no-target") return end
    local kind, how = "ahSale", "invoice"
    for _, set in ipairs(ways) do
        for _, req in ipairs(set) do
            if req.kind ~= "ahSale" or req.unsureKind then kind = "mail" end
            if req.how == "soldmail" then how = "soldmail" end
        end
    end
    local same = true
    local first = SetSignature(ways[1])
    for i = 2, #ways do if SetSignature(ways[i]) ~= first then same = false end end
    if #ways > 1 then stats.ambiguous = stats.ambiguous + 1; Why(same and "equal-alternatives" or "ambiguous") end
    if #matched > 1 then stats.combined = stats.combined + 1 end
    local note, qty, settlement, parts
    if kind == "ahSale" and same then
        if #matched > L.MAX_INVOICES then Why("detail-limit") end
        if #matched == 1 and not matched[1].unsure then note, qty = matched[1].note, matched[1].qty end
        local invoices = {}
        for _, req in ipairs(matched) do if req.settlement and not req.unsure then invoices[#invoices + 1] = req.settlement.invoices[1] end end
        if #invoices == #matched then settlement = L.Settlement({ v = 1, invoices = invoices }, amount) end
        -- without a full invoice breakdown, each message's own collected amount and item are still the components of this one entry
        if not settlement and #matched > 1 then
            parts = {}
            for _, req in ipairs(matched) do
                if req.unsure or not req.note then parts = nil break end
                parts[#parts + 1] = { c = req.amount, n = req.note, q = req.qty }
            end
        end
    end
    if kind == "ahSale" then
        local field = settlement and "settlement" or "unavailable"
        stats[field] = stats[field] + 1
    elseif #ways == 1 then
        for _, req in ipairs(matched) do if req.kind == "ahSale" and not req.unsureKind then Why("mixed") break end end
    end
    credits = credits + 1
    local ev = { kind = kind, amount = amount, note = note, qty = qty, settlement = settlement, parts = parts,
        evidence = kind == "ahSale" and how == "soldmail" and "mailauction" or nil,
        corr = "mail:" .. credits, entry = matched.entry, char = matched.char }
    local function Offer()
        if not LedgerOn() then return end
        local ok, result = pcall(L.Evidence, ev)
        if not ok then R.Fault("mailbox gold summary", result)
        elseif result == "attributed" then stats.exact = stats.exact + 1
        else Why("ledger-" .. tostring(result)) end
    end
    local rec = L.Record(matched.char)
    if rec and rec.nextId == matched.entry then
        if deferredCount >= 8 then Why("deferred-full") return end
        deferred[ev], deferredCount = true, deferredCount + 1
        C_Timer.After(0, function()
            if not deferred[ev] then return end
            deferred[ev], deferredCount = nil, deferredCount - 1
            Offer()
        end)
    else Offer() end
end

-- Every set of waiting requests (the oldest MAX_SEARCH, in order) whose amounts add up to the gain, oldest set first; at most
-- MAX_WAYS + 1 are collected (one more means "too many to tell"). Amounts are positive, so a branch past the gain stops.
local function Ways(gain)
    local ways, pick, cand, all = {}, {}, {}, {}
    local total, within, complete = 0, true, true
    for _, req in ipairs(queue) do
        if not req.spare then
            all[#all + 1] = req
            -- Positive amounts: the complete batch has exactly one explanation.
            -- Compare before adding, so no intermediate sum can overflow the gain.
            if total <= gain - req.amount then total = total + req.amount else within = false end
            if req.amount <= gain then
                if #cand < MAX_SEARCH then cand[#cand + 1] = req else complete = false end
            end
        end
    end
    if within and #all > 0 and total == gain then return { all }, true end
    local n = #cand
    local function Walk(i, sum)
        if #ways > MAX_WAYS then return end
        if sum == gain and #pick > 0 then
            local set = {}
            for k, req in ipairs(pick) do set[k] = req end
            ways[#ways + 1] = set
            return
        end
        if i > n or sum > gain then return end
        local req = cand[i]
        pick[#pick + 1] = req
        Walk(i + 1, sum + req.amount)
        pick[#pick] = nil
        Walk(i + 1, sum)
    end
    Walk(1, 0)
    return ways, complete
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
    if gain <= 0 then return end
    if #queue == 0 then if session then Why("no-request") end;return end
    -- A stalled frame must not let an overdue request claim later money before its timer runs.
    local mono = GetTime and Num(GetTime())
    for i = #queue, 1, -1 do
        local req = queue[i]
        if mono and req.expires and mono >= req.expires then if not req.spare then Why("expired") end Finish(req, false) end
    end
    if #queue == 0 then return end
    local ways, complete = Ways(gain)
    if not complete then
        Why("search-limit")
        -- An omitted explanation may have paid any of these requests. None may
        -- lend item/kind evidence to a later gain after this incomplete search.
        for _, req in ipairs(queue) do
            if not req.spare and req.amount <= gain then req.unsure, req.unsureKind = true, true end
        end
    end
    if #ways == 0 then Why("unmatched-gain") return end
    local matched = ways[1]   -- the oldest explanation pays the chat total; the requests it holds are answered
    local chosen = {}
    for _, req in ipairs(matched) do chosen[req] = true end
    -- An explanation that was not taken leaves its requests waiting for money that may already have come: their own invoice could be
    -- the one just paid, so they keep no item or invoice details; and when the explanations were not all auction sales, whatever
    -- they are paid later can only be plain mail.
    if #ways > 1 then
        local first, same, allSale = SetSignature(ways[1]), true, true
        for i = 2, #ways do if SetSignature(ways[i]) ~= first then same = false end end
        for _, set in ipairs(ways) do for _, req in ipairs(set) do if req.kind ~= "ahSale" or req.unsureKind then allSale = false end end end
        if not same then
            for i = 2, #ways do
                for _, req in ipairs(ways[i]) do
                    if not chosen[req] then req.unsure = true; if not allSale then req.unsureKind = true end end
                end
            end
        end
    end
    local exact = complete and target ~= nil and #ways <= MAX_WAYS
    for _, req in ipairs(matched) do if req.char ~= key then exact = false end end
    matched.entry, matched.char = target, key
    for _, req in ipairs(matched) do Finish(req, true) end
    if exact then Credit(gain, matched, ways)
    elseif #ways > MAX_WAYS then Why("too-many-ways")
    elseif target == nil then Why("no-target")
    else Why("other-character") end
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

-- A request has waited EXPIRY seconds: it is let go, unless the game still says a mail command is pending (a slow server
-- during a collection), then it waits a second more, never past MAX_AGE.
local function Expire(req)
    if req.done then return end
    local now = GetTime and Num(GetTime())
    local pending = C_Mail and type(C_Mail.IsCommandPending) == "function" and C_Mail.IsCommandPending() == true
    if pending and not req.spare and now and req.born and now - req.born < MAX_AGE then
        req.expires = now + 1
        C_Timer.After(1, function() Expire(req) end)
        return
    end
    if not req.spare then Why("expired") end
    Finish(req, false)
end

-- A take is asked for. Noted only; whether it worked is for PLAYER_MONEY to say.
local function Record(index)
    local s = session
    if not (active and s and s.open and type(index) == "number") then return end
    if #queue >= MAX_WAITING then Why("queue-full") return end
    local money, cod = Read(index)
    if not money or cod ~= 0 then return end
    local mark = Header(index)
    local remembered = known[index]
    known[index] = nil   -- this position's money is being taken; a second call must not use it again
    if money <= 0 then money = remembered end
    if not money or money <= 0 then return end
    -- the same message asked for again (same position, same header and amount, no inbox update since): a spare
    local inflight = s.inflight[index]
    local spare = inflight ~= nil and not inflight.done and inflight.mark == mark and inflight.amount == money
    if spare then Why("duplicate") end
    local kind, note, qty, settlement, how
    if LedgerOn() and not spare then
        kind, note, qty, settlement, how = Evidence(index, money)
        local seenBefore = knownInvoice[index]
        -- what this position showed at the last update, only if it is still the same message
        if not kind and seenBefore and seenBefore[6] == mark then kind, note, qty, settlement, how = unpack(seenBefore, 1, 5) end
        if how == "invoice" then stats.verified = stats.verified + 1
        elseif how == "soldmail" then stats.soldMail = stats.soldMail + 1; Why("invoice-missing"); Why("sold-mail")
        else Why("plain-mail") end
    end
    knownInvoice[index] = nil
    if not spare then stats.requests = stats.requests + 1 end
    local now = GetTime and Num(GetTime())
    local req = { session = s, index = index, mark = mark, amount = money, kind = kind, note = note, qty = qty, settlement = settlement, how = how, spare = spare or nil,
        char = LedgerOn() and R.Ledger.CharKey() or nil, born = now, expires = now and now + EXPIRY or nil }
    queue[#queue + 1] = req
    if not spare then s.inflight[index] = req end
    s.waiting = s.waiting + 1
    C_Timer.After(EXPIRY, function() Expire(req) end)
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
function MG.Snapshot()
    local copy = {}
    for code, n in pairs(why) do copy[code] = n end
    return { open = session ~= nil, waiting = #queue, deferred = deferredCount,
        ambiguous = stats.ambiguous, settlement = stats.settlement, unavailable = stats.unavailable,
        requests = stats.requests, verified = stats.verified, soldMail = stats.soldMail, combined = stats.combined, exact = stats.exact,
        why = copy }
end

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
