-- Open All against the real mailbox collector (auction/Mail.lua) and recorder (auction/Ledger.lua).
-- The driver below follows the classic-era Blizzard OpenAllMailMixin (Blizzard_UIPanels_Game/Classic/MailFrame.lua): it always
-- restarts at index 1 after the inbox count changes, takes one message's money at a time, waits at least 0.15 s and while
-- C_Mail.IsCommandPending(). A seller's mail with no attachment is deleted by the server once its money is taken, so the
-- next message moves into the same position. Everything here is synthetic: a stand-in "server" answers each command after a
-- chosen latency and delivers PLAYER_MONEY before or after the command result (callback order variations).
--
-- Real-client facts that remain unverified are parameters, never assumptions: whether GetInboxInvoiceInfo answers for a
-- message that was never opened (invoice = "always" | "read" | "never"), and whether money arrives before or after the
-- command result that lets Open All continue (moneyLag).
dofile(TESTS .. "harness.lua")
local failures = 0
local function Check(v, m) if not v then failures = failures + 1; print("FAIL: " .. tostring(m)) end end
local function Same(a, b, m) Check(a == b, (m or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a)) end

local SOLD = "Auction successful: %s"

local function Client(opts)
    opts = opts or {}
    local c = MakeClient("Rich", { "!!!TwichUI" })
    c.TwichUIDB = { modules = { chronicle = false, quietLogin = false, mailGoldSummary = opts.summary ~= false }, ui = { workshopEnabled = true } }
    c.TwichUILedgerDB = opts.db
    c.NOW, c.MONEY, c.INBOX, c.OUT = 100, 500000, {}, {}
    c.AUCTION_SOLD_MAIL_SUBJECT = SOLD
    c.GetServerTime = function() return 20000 * 86400 + 43200 end
    c.GetTime = function() return c.NOW end
    c.GetMoney = function() return c.MONEY end
    c.print = function(value) c.OUT[#c.OUT + 1] = tostring(value) end
    local timers = {}
    c.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = c.NOW + d, fn = fn } end }
    local function RunDue()
        local again = true
        while again do
            again = false
            local due, rest = {}, {}
            for _, t in ipairs(timers) do if t.at <= c.NOW then due[#due + 1] = t else rest[#rest + 1] = t end end
            timers = rest
            for _, t in ipairs(due) do t.fn(); again = true end
        end
    end
    c.RunDue = RunDue
    c.GetInboxNumItems = function() return #c.INBOX, #c.INBOX end
    c.GetInboxHeaderInfo = function(i)
        local m = c.INBOX[i]
        if not m then return end
        -- packageIcon, stationeryIcon, sender, subject, money, COD, daysLeft, itemCount, wasRead, wasReturned, textCreated, canReply, isGM
        return 1, 1, m.sender or "PRIVATE SENDER", m.subject or "PRIVATE SUBJECT", m.money, m.cod or 0, m.days or 29, m.items or 0,
            m.read == true, false, true, m.canReply ~= false, false
    end
    c.GetInboxInvoiceInfo = function(i)
        local m = c.INBOX[i]
        if not m or not m.kind then return end
        local mode = opts.invoice or "always"
        if mode == "never" or (mode == "read" and not m.read) then return end
        return m.kind, m.item, "PRIVATE BUYER", m.g, 99999999, m.d, m.f, 0, 1, 2, m.qty
    end
    c.GetInboxText = function(i) local m = c.INBOX[i]; if m then m.read = true; return "", nil, nil, nil, m.kind ~= nil end end
    c.HasInboxItem = function(i) local m = c.INBOX[i]; return m and (m.items or 0) > 0 end
    c.GetInboxItem = function() return nil end
    c.C_Mail = { HasInboxMoney = function(i) local m = c.INBOX[i]; return m ~= nil and m.money > 0 end,
        IsCommandPending = function() return c.PENDING ~= nil end }
    c.C_Container = { CalculateTotalNumberOfFreeBagSlots = function() return 10 end }
    c.SENT = {}       -- what the stand-in server paid, in order
    -- TakeInboxMoney sends a command; the stand-in server answers it later (Server below)
    local function Take(i)
        local m = c.INBOX[i]
        c.TAKES = (c.TAKES or 0) + 1
        if not m or m.money <= 0 or c.PENDING then return end
        c.PENDING = { msg = m, at = c.NOW }
    end
    c.TakeInboxMoney, c.AutoLootMailItem = Take, Take
    c.hooksecurefunc = function(name, fn) local original = c[name]; c[name] = function(...) original(...); fn(...) end end
    for _, name in ipairs({ "modules/Restock.lua", "WorkshopLauncher.lua", "auction/Ledger.lua", "auction/Mail.lua" }) do
        local f = assert(loadfile(ROOT .. name)); setfenv(f, c); f()
    end
    c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI"); c.FireEvent("PLAYER_LOGIN"); c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    c.L, c.MG = c.TwichUI.Ledger, c.TwichUI.MailGold
    function c.Entries() local r = c.TwichUILedgerDB.chars["Rich - Forever"]; return r and r.entries or {} end
    function c.Open(inbox) c.INBOX = inbox; c.FireEvent("MAIL_SHOW") end
    function c.Money(n) c.MONEY = c.MONEY + n; c.SENT[#c.SENT + 1] = n; c.FireEvent("PLAYER_MONEY") end
    return c
end

-- One stand-in server and the Open All driver, stepped in small ticks of game time.
--   latency   seconds from the command to its result
--   moneyLag  seconds from the result to PLAYER_MONEY (negative: money first)
--   combine   PLAYER_MONEY for two consecutive payments arrives as one change
local function OpenAll(c, opts)
    opts = opts or {}
    local lat, lag = opts.latency or 0.05, opts.moneyLag or 0
    local results = 0
    local self = { mailIndex = 1, numToOpen = #c.INBOX, wait = nil }
    local moneyQueue = {}  -- { at, amount }
    local held             -- combine: a payment waiting to be merged with the next
    local function Result()
        local cmd = c.PENDING
        c.PENDING = nil
        local m = cmd.msg
        local amount = m.money
        m.money = 0
        results = results + 1
        local at = c.NOW + (opts.moneyLagSeq and opts.moneyLagSeq[results] or lag)
        if opts.combine then
            if held then moneyQueue[#moneyQueue + 1] = { at = at, amount = held + amount }; held = nil else held = amount end
        else moneyQueue[#moneyQueue + 1] = { at = at, amount = amount } end
        -- an emptied seller's or plain money mail with nothing else is removed, and the rest move up
        if (m.items or 0) == 0 and not m.keep then
            for i, x in ipairs(c.INBOX) do if x == m then table.remove(c.INBOX, i) break end end
        end
        if not opts.noUpdate then
            if opts.updateFirst ~= false then c.FireEvent("MAIL_INBOX_UPDATE") end
            for _ = 1, (opts.repeatUpdates or 0) do c.FireEvent("MAIL_INBOX_UPDATE") end
            if opts.updateFirst == false then c.FireEvent("MAIL_INBOX_UPDATE") end
        end
        if #c.INBOX ~= self.numToOpen then self.mailIndex = 1 end   -- OpenAllMailMixin:OnEvent
    end
    local function Advance()
        while self.mailIndex <= #c.INBOX do
            local m = c.INBOX[self.mailIndex]
            if m.money > 0 and (m.cod or 0) == 0 then return true end
            self.mailIndex = self.mailIndex + 1
        end
        return false
    end
    local function Process()
        if Advance() then
            c.TakeInboxMoney(self.mailIndex)
            self.wait = opts.delay or 0.15
            return true
        end
        return false
    end
    local running = Process()
    local dt, guard = 0.01, 0
    while (running or c.PENDING or #moneyQueue > 0 or held) and guard < 20000 do
        guard = guard + 1
        c.NOW = c.NOW + dt
        if c.PENDING and c.NOW - c.PENDING.at >= lat - 1e-9 then Result() end
        for i = #moneyQueue, 1, -1 do
            if moneyQueue[i].at <= c.NOW + 1e-9 then local p = table.remove(moneyQueue, i); c.Money(p.amount) end
        end
        if held and not running and not c.PENDING then c.Money(held); held = nil end
        c.RunDue()
        if opts.closeAt and c.NOW >= opts.closeAt and not self.closed then self.closed = true; c.FireEvent("MAIL_CLOSED"); running = false end
        if running and self.wait then
            self.wait = self.wait - dt
            if self.wait <= 0 then
                if not c.C_Mail.IsCommandPending() then self.wait = nil; running = Process() else self.wait = 0.15 end
            end
        end
    end
    for _ = 1, 600 do c.NOW = c.NOW + 0.05; c.RunDue() end   -- let every timer run (expiry, deferral)
end

local function Sale(item, gross, fee, deposit, qty)
    local money = gross + deposit - fee
    return { kind = "seller", item = item, qty = qty or 1, g = gross, f = fee, d = deposit, money = money,
        subject = SOLD:format(item), sender = "AUCTION HOUSE", canReply = false }
end
local function Personal(money) return { money = money } end

local function Count(c)
    local n = { ahSale = 0, mail = 0, other = 0, total = 0, sum = 0, settled = 0 }
    for _, e in ipairs(c.Entries()) do
        n[e.k or "other"] = (n[e.k or "other"] or 0) + 1
        n.total, n.sum = n.total + 1, n.sum + e.a
        if e.s then n.settled = n.settled + 1 end
    end
    return n
end
local function Paid(c) local s = 0 for _, v in ipairs(c.SENT) do s = s + v end return s end
local function Sales(n, equal)
    local list = {}
    for i = 1, n do list[i] = Sale("Linen Cloth", equal and 10000 or (10000 + i * 137), equal and 500 or (500 + i), 60) end
    return list
end
local function Run(name, inbox, opts, expect)
    local c = Client(opts)
    c.Open(inbox)
    OpenAll(c, opts)
    local n = Count(c)
    Same(n.total, #c.SENT, name .. ": one cash entry per observed gold change")
    Same(n.sum, Paid(c), name .. ": exact money recorded once")
    if expect then expect(c, n) end
    return c, n
end

---------------------------------------------------------------------------
-- The reported symptom: many seller payments through Open All
---------------------------------------------------------------------------
-- 1. Money before the command result (the next take cannot overlap): every sale is recognised.
Run("instant, money first", Sales(12), { moneyLag = -0.01 }, function(c, n)
    Same(n.ahSale, 12, "instant, money first: all sales"); Same(n.settled, 12, "instant, money first: settlement details")
end)
-- 2. Money after the result, later than Open All's 0.15 s throttle: the next take is made while the previous payment is still
-- in flight. Blizzard's Open All takes position 1 again (the paid message was deleted and the next moved up).
-- Original failure: V4 treated the second take of position 1 as a duplicate of the first and marked every waiting request
-- ambiguous, so only the payments that arrived alone were recognised.
Run("throttled, money after next take", Sales(12), { moneyLag = 0.2 }, function(c, n)
    Same(n.ahSale, 12, "throttled, late money: all sales"); Same(n.settled, 12, "throttled, late money: settlement details")
end)
-- Real latency varies: payments sometimes arrive before the next take and sometimes after. V4 recognised only those that
-- arrived alone before an overlap, then lost the rest of the batch: "only a couple" of the Open All entries were sales.
Run("jittered latency", Sales(12), { moneyLagSeq = { 0.02, 0.05, 0.3, 0.02, 0.25, 0.1, 0.4, 0.02, 0.2, 0.05, 0.3, 0.02 } }, function(c, n)
    Same(n.ahSale, 12, "jittered latency: all sales")
end)
Run("equal sales, late money", Sales(10, true), { moneyLag = 0.2 }, function(c, n)
    Same(n.ahSale, 10, "equal sales, late money: all sales")
end)
Run("slow server", Sales(10), { latency = 0.6, moneyLag = 0.3 }, function(c, n)
    Same(n.ahSale, 10, "slow server: all sales")
end)
Run("repeated inbox updates", Sales(10), { moneyLag = 0.2, repeatUpdates = 3 }, function(c, n)
    Same(n.ahSale, 10, "repeated updates: all sales")
end)
-- The deleted message's neighbour moves up with no MAIL_INBOX_UPDATE yet: the header shows a different message at position 1.
Run("shift without update", Sales(8), { moneyLag = 0.2, noUpdate = true }, function(c, n)
    Same(n.ahSale, 8, "shift without update: all sales")
end)
Run("update after money", Sales(10), { moneyLag = -0.01, updateFirst = false }, function(c, n)
    Same(n.ahSale, 10, "update after money: all sales")
end)
-- 3. Two payments reported as one change: one cash entry, both invoices as its settlement details.
Run("combined payments", Sales(10), { moneyLag = 0.2, combine = true }, function(c, n)
    Same(n.ahSale, n.total, "combined: every entry is an auction sale")
    local two = 0
    for _, e in ipairs(c.Entries()) do if e.s and #e.s.invoices == 2 then two = two + 1 end end
    Same(two, 5, "combined: each combined entry lists its two invoices")
end)
-- 4. A seller's mail that was never opened may not give its invoice (Blizzard's own mail frame reads GetInboxText first).
-- The Auction House's own sold-auction mail is still recognised by the client's AUCTION_SOLD_MAIL_SUBJECT on a mail that cannot
-- be answered; its fee and deposit are then unavailable rather than guessed.
Run("unread invoices", Sales(12), { moneyLag = 0.2, invoice = "read" }, function(c, n)
    Same(n.ahSale, 12, "unread invoices: still auction sales"); Same(n.settled, 0, "unread invoices: no invented fee details")
    Same(c.Entries()[1].e, "mailauction", "unread invoices: evidence says it came from the sold-auction mail, not an invoice")
end)
Run("no invoices at all", Sales(6), { invoice = "never" }, function(c, n)
    Same(n.ahSale, 6, "no invoices: sold-auction mail still recognised")
end)

---------------------------------------------------------------------------
-- Mixed mail: never all auction revenue
---------------------------------------------------------------------------
do
    local inbox = { Sale("Copper Ore", 3000, 150, 20), Personal(777), Sale("Tin Ore", 4000, 200, 20), Personal(1500), Sale("Silk Cloth", 9000, 450, 60) }
    Run("mixed, sequential", inbox, { moneyLag = 0.2 }, function(c, n)
        Same(n.ahSale, 3, "mixed: the three sales"); Same(n.mail, 2, "mixed: the two letters stay Mail collected")
    end)
end
do
    -- A personal letter whose subject copies the auction text is answerable: never an auction sale without an invoice.
    local fake = { money = 5000, subject = SOLD:format("Linen Cloth"), sender = "Friend", canReply = true }
    Run("look-alike letter", { fake }, { invoice = "never" }, function(c, n) Same(n.mail, 1, "look-alike: Mail collected"); Same(n.ahSale, 0, "look-alike: not a sale") end)
end
do
    local inbox = { Sale("Copper Ore", 3000, 150, 20), Personal(2870) }   -- the sale pays 2870 too
    Run("mixed, combined", inbox, { moneyLag = 0.2, combine = true }, function(c, n)
        Same(n.total, 1, "mixed combined: one entry"); Same(n.ahSale, 0, "mixed combined: not all auction revenue")
        Same(n.mail, 1, "mixed combined: Mail collected")
        local e = c.Entries()[1]
        Check(e.s == nil, "mixed combined: no seller settlement on a mixed payment")
    end)
end
do
    -- An equal-valued letter and sale both waiting: the money is certainly mail, never certainly a sale.
    local inbox = { Sale("Copper Ore", 3000, 150, 20), Personal(2870) }
    Run("equal sale and letter in flight", inbox, { moneyLag = 0.2 }, function(c, n)
        Same(n.ahSale + n.mail, 2, "equal mixed: both entries classified as mail at least")
        Check(n.ahSale <= 1, "equal mixed: never two sales")
    end)
end

---------------------------------------------------------------------------
-- Closing, reopening, expiry and summary
---------------------------------------------------------------------------
do
    local c = Run("close during collection", Sales(6), { moneyLag = 0.2, closeAt = 100.5 }, function(c, n)
        Check(n.ahSale == n.total, "close during collection: what was collected is still recognised")
    end)
    local lines = 0
    for _, line in ipairs(c.OUT) do if line:find("Collected", 1, true) then lines = lines + 1 end end
    Same(lines, 1, "close during collection: one summary line")
end
do
    local c = Run("summary", Sales(5), { moneyLag = 0.2 })
    c.FireEvent("MAIL_CLOSED")
    local total = 0
    for _, v in ipairs(c.SENT) do total = total + v end
    local found = false
    for _, line in ipairs(c.OUT) do if line:find("Collected", 1, true) then found = true end end
    Check(found, "summary line still printed")
    Same(c.MG.Snapshot().waiting, 0, "nothing left waiting")
end
do
    -- A server that never answers: the request expires; a later identical gain is not borrowed.
    local c = Client()
    c.Open({ Sale("Linen Cloth", 10000, 500, 60) })
    c.TakeInboxMoney(1)
    c.PENDING = nil
    for _ = 1, 400 do c.NOW = c.NOW + 0.1; c.RunDue() end
    c.Money(9560)
    Same(c.Entries()[#c.Entries()].k, nil, "expired request does not claim a later identical gain")
    Check((c.MG.Snapshot().why or {}).expired == 1, "the expiry is counted")
end
do
    -- A slow but progressing collection: the request waits while the mailbox still has a command pending.
    local c = Client()
    c.Open({ Sale("Linen Cloth", 10000, 500, 60) })
    c.TakeInboxMoney(1)
    for _ = 1, 60 do c.NOW = c.NOW + 0.1; c.RunDue() end   -- 6 s, command still pending
    c.PENDING = nil; c.INBOX[1].money = 0; table.remove(c.INBOX, 1); c.FireEvent("MAIL_INBOX_UPDATE"); c.Money(9560); c.RunDue()
    for _ = 1, 10 do c.NOW = c.NOW + 0.1; c.RunDue() end
    Same(c.Entries()[#c.Entries()].k, "ahSale", "a pending command keeps its request alive (bounded)")
end

do
    -- A command the game keeps "pending" forever: the request still ends at MAX_AGE, and a later identical gain is not borrowed.
    local c = Client()
    c.Open({ Sale("Linen Cloth", 10000, 500, 60) })
    c.TakeInboxMoney(1)
    for _ = 1, 300 do c.NOW = c.NOW + 0.1; c.RunDue() end   -- 30 s, still pending
    Same(c.MG.Snapshot().waiting, 0, "a pending command keeps a request at most MAX_AGE")
    c.PENDING = nil
    c.Money(9560)
    Same(c.Entries()[#c.Entries()].k, nil, "a request that aged out does not claim a later identical gain")
end
do
    -- Two sales of different items that pay exactly the same, both in flight: each is an auction sale, but which invoice
    -- each payment carried cannot be told, so neither entry carries an item name or invoice details.
    local inbox = { Sale("Copper Ore", 3000, 150, 20), Sale("Tin Ore", 3000, 150, 20) }
    Run("equal amounts, different items", inbox, { moneyLag = 0.2 }, function(c, n)
        Same(n.ahSale, 2, "equal different: both auction sales")
        for _, e in ipairs(c.Entries()) do
            Same(e.n, nil, "equal different: no guessed item name"); Same(e.s, nil, "equal different: no guessed invoice")
        end
    end)
end
do
    -- A sale and a letter of exactly the same amount in flight: the first payment could be either, so it is Mail collected.
    local inbox = { Sale("Copper Ore", 3000, 150, 20), Personal(2870) }
    Run("equal sale and letter, first payment", inbox, { moneyLag = 0.2 }, function(c, n)
        Same(c.Entries()[1].k, "mail", "the first payment could be the letter's")
        Same(c.Entries()[2].k, "mail", "and the second could be the sale's or the letter's")
    end)
end

do
    -- More explanations than are examined (twelve equal takes, three paid at once): nothing is claimed about the payment, since an
    -- unexamined explanation could hold the letter. The money is still recorded exactly once, unclassified.
    local c = Client()
    local inbox = {}
    for i = 1, 11 do inbox[i] = Sale("Linen Cloth", 100, 0, 0) end
    inbox[12] = Personal(100)
    c.Open(inbox)
    for i = 1, 12 do c.TakeInboxMoney(i); c.PENDING = nil end
    c.Money(300); c.RunDue()
    Same(#c.Entries(), 1, "too many explanations: one entry")
    Same(c.Entries()[1].k, nil, "too many explanations: no classification claimed")
    Check((c.MG.Snapshot().why or {})["too-many-ways"] == 1, "too many explanations: the reason is counted")
end

---------------------------------------------------------------------------
-- Diagnostics: counters and reason codes only
---------------------------------------------------------------------------
do
    local c = Run("diagnostics", Sales(4), { moneyLag = 0.2, invoice = "read" })
    local s = c.MG.Snapshot()
    Check(s.requests >= 4, "requests counted"); Check(s.verified == 0, "no invoice verified")
    Check(s.why and s.why["invoice-missing"] == 4, "missing invoice evidence counted: " .. tostring(s.why and s.why["invoice-missing"]))
    Check(s.why["sold-mail"] == 4, "sold-auction mail counted")
    Check(s.exact >= 4, "exact journal matches counted")
end

do
    -- The report a player copies from /tui diagnostics: counters and reason codes, nothing personal
    local c = Run("report", { Sale("Linen Cloth", 10000, 500, 60), Personal(777) }, { moneyLag = 0.2, invoice = "read" })
    for _, name in ipairs({ "diag/Diagnostics.lua", "diag/Lifecycle.lua" }) do
        local f = assert(loadfile(ROOT .. name)); setfenv(f, c); f()
    end
    local report = c.TwichUI.Diag.Build()
    Check(report:find("mail: requests=2; verified=0; soldMail=1", 1, true), "mail counters in the report")
    Check(report:find("mail reasons:", 1, true) and report:find("invoice-missing=1", 1, true) and report:find("plain-mail=1", 1, true), "mail reasons in the report")
    for _, private in ipairs({ "Linen", "PRIVATE", "AUCTION HOUSE", "Auction successful", "Rich", "9560", "777" }) do
        Check(not report:find(private, 1, true), "nothing personal in the report: " .. private)
    end
end

if failures > 0 then print(failures .. " failures") os.exit(1) end
print("PASSED test_ledger_openall")
