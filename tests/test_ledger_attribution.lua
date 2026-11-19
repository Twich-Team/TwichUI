-- The gold ledger's attribution: what a completed transaction may say about a money change, and what must never be said.
-- Part 1 drives the real recorder (auction/Ledger.lua) with the real mailbox code (auction/Mail.lua) on a mock mailbox and a mock
-- "server". Part 2 drives the real Auction House purchase controller (TwichUI_Workshop/auction/Actions.lua) on its mock. The mailbox,
-- the server and the clock are mocks: whether the game answers as modelled is for an in-game check (docs/workshop/gold-ledger.md).
dofile(TESTS .. "harness.lua")

local function Check(cond, msg) if not cond then error(msg or "check failed", 2) end end
local function Same(a, b, msg) if a ~= b then error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local DAY = 86400
local T0 = 20000 * DAY + 12 * 3600

---------------------------------------------------------------------------
-- Part 1: the recorder and the mailbox
---------------------------------------------------------------------------
local function Client(opts)
    opts = opts or {}
    local c = MakeClient("Rich", { "!!!TwichUI" })
    c.R_OUT = {}
    c.print = function(s) c.R_OUT[#c.R_OUT + 1] = tostring(s) end
    c.TwichUIDB = { modules = { chronicle = false, mailGoldSummary = opts.summary == true }, ui = { workshopEnabled = opts.ledger ~= false } }
    c.NOW, c.MONO, c.MONEY = T0, 100, 5000000
    c.GetServerTime = function() return c.NOW end
    c.GetTime = function() return c.MONO end
    c.GetMoney = function() return c.MONEY end
    -- timers wait for Advance()
    local now, timers = 0, {}
    c.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
    function c.Advance(s)
        now = now + s; c.MONO = c.MONO + s
        local due, rest = {}, {}
        for _, t in ipairs(timers) do if t.at <= now then due[#due + 1] = t else rest[#rest + 1] = t end end
        timers = rest
        for _, t in ipairs(due) do t.fn() end
    end
    -- the mailbox and the server
    c.INBOX = {}
    c.GetInboxHeaderInfo = function(i)
        local m = c.INBOX[i]
        if not m then return end
        return "icon", "paper", m.sender or "Someone", m.subject or "Mail", m.cleared and 0 or (m.money or 0), m.cod or 0, 29, m.items or 0
    end
    c.GetInboxNumItems = function() return #c.INBOX end
    if opts.invoices then
        c.GetInboxInvoiceInfo = function(i) local m = c.INBOX[i]; if m and m.invoice then return "seller", m.invoice end end
    end
    local cmds = {}
    c.TakeInboxMoney = function(i) local m = c.INBOX[i]; if m then cmds[#cmds + 1] = { mail = m } end end
    c.AutoLootMailItem = function(i) local m = c.INBOX[i]; if m then cmds[#cmds + 1] = { mail = m } end end
    c.hooksecurefunc = function(name, fn)
        local orig = c[name]
        c[name] = function(...) local r = orig(...); fn(...); return r end
    end
    for _, f in ipairs({ "modules/Restock.lua", "WorkshopLauncher.lua", "auction/Ledger.lua", "auction/Mail.lua" }) do
        local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
    end
    c.LOADED["!!!TwichUI"] = true
    c.FireEvent("ADDON_LOADED", "!!!TwichUI")
    c.FireEvent("PLAYER_LOGIN")
    c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    c.R, c.L = c.TwichUI, c.TwichUI.Ledger
    function c.Gain(n) c.MONEY = c.MONEY + n; c.MONO = c.MONO + 1; c.FireEvent("PLAYER_MONEY") end
    function c.Spend(n) c.MONEY = c.MONEY - n; c.MONO = c.MONO + 1; c.FireEvent("PLAYER_MONEY") end
    function c.Answer(ok)   -- the server answers the oldest command
        local cmd = table.remove(cmds, 1)
        if not cmd then return end
        if ok then
            local paid = (cmd.mail.cod or 0) == 0 and cmd.mail.money or 0
            cmd.mail.money = 0
            if paid > 0 then c.Gain(paid) end
        else
            c.FireEvent("MAIL_FAILED")
        end
    end
    function c.Entries() return c.TwichUILedgerDB.chars["Rich - Forever"].entries end
    function c.Day() return c.TwichUILedgerDB.chars["Rich - Forever"].days[20000] end
    return c
end

-- A confirmed money receipt is recorded once, as mail collected
do
    local c = Client()
    c.INBOX = { { money = 12345, sender = "Bob" } }
    c.FireEvent("MAIL_SHOW")
    c.TakeInboxMoney(1); c.Answer(true)
    local e = c.Entries()
    Same(#e, 1, "one money change, one entry")
    Same(e[1].a, 12345); Same(e[1].k, "mail"); Same(e[1].e, "mailbox")
    Same(c.Day().i, 12345, "counted once in the day"); Same(c.Day().ci.mail, 12345); Check(c.Day().ci.other == nil, "no longer unclassified")
    Check(e[1].x and e[1].x:find("^mail:"), "carries a correlation id")
    Same(#c.R_OUT, 0, "the chat summary is its own switch: silent here")
end

-- Mailbox money is not necessarily an auction sale: only a seller's invoice says so
do
    local c = Client({ invoices = true })
    c.INBOX = { { money = 5000, sender = "Auction House", invoice = "Runecloth" }, { money = 700, sender = "Alt" } }
    c.FireEvent("MAIL_SHOW")
    c.TakeInboxMoney(1); c.Answer(true)
    c.TakeInboxMoney(1); c.Answer(true)     -- the first message is empty now but keeps its place; take the second below
end
do
    local c = Client({ invoices = true })
    c.INBOX = { { money = 5000, sender = "Auction House", invoice = "Runecloth" }, { money = 700, sender = "Alt" } }
    c.FireEvent("MAIL_SHOW")
    c.TakeInboxMoney(1); c.Answer(true)
    c.TakeInboxMoney(2); c.Answer(true)
    local e = c.Entries()
    Same(#e, 2)
    Same(e[1].k, "ahSale"); Same(e[1].n, "Runecloth"); Same(e[1].e, "mailinvoice")
    Same(e[2].k, "mail", "money from a player is not an auction sale"); Check(e[2].n == nil)
    -- two invoices in one reported change are still sales; one plain message among them makes it plain mail
    local d = Client({ invoices = true })
    d.INBOX = { { money = 100, invoice = "A" }, { money = 200, invoice = "B" }, { money = 400 } }
    d.FireEvent("MAIL_SHOW")
    d.TakeInboxMoney(1); d.TakeInboxMoney(2)
    d.MONEY = d.MONEY + 300; d.INBOX[1].money = 0; d.INBOX[2].money = 0; d.FireEvent("PLAYER_MONEY")
    Same(#d.Entries(), 1, "two requests, one reported change, one entry")
    Same(d.Entries()[1].k, "ahSale"); Check(d.Entries()[1].n == nil, "no single item to name")
    d.TakeInboxMoney(3); d.MONEY = d.MONEY + 400; d.INBOX[3].money = 0; d.FireEvent("PLAYER_MONEY")
    Same(d.Entries()[2].k, "mail")
    -- no invoice call in the client at all: plain mail
    local n = Client()
    n.INBOX = { { money = 900, sender = "Auction House" } }
    n.FireEvent("MAIL_SHOW"); n.TakeInboxMoney(1); n.Answer(true)
    Same(n.Entries()[1].k, "mail", "a sender name proves nothing")
end

-- A request that was refused, ignored or never answered attributes nothing; unrelated gold stays unclassified
do
    local c = Client()
    c.INBOX = { { money = 300 }, { money = 800 } }
    c.FireEvent("MAIL_SHOW")
    c.TakeInboxMoney(1); c.Answer(false)                 -- refused
    c.Gain(300)                                          -- the same amount from somewhere else, afterwards
    Same(c.Entries()[1].k, nil, "a refused take never labels later gold")
    c.TakeInboxMoney(2); c.Advance(5)                    -- the call was ignored: it expires
    c.Gain(800)
    Same(c.Entries()[2].k, nil, "an expired request attributes nothing")
    c.Gain(123); Same(c.Entries()[3].k, nil, "gold with the mailbox open is not mail")
    c.Spend(50); Same(c.Entries()[4].a, -50); Same(c.Entries()[4].k, nil, "postage and other losses stay unclassified")
    Check(c.Day().ci.mail == nil, "no mail income at all")
end

-- A take and an unrelated gain of a different amount: the take's money is matched, the other is not
do
    local c = Client()
    c.INBOX = { { money = 1000 } }
    c.FireEvent("MAIL_SHOW")
    c.Gain(77)                                            -- loot
    c.TakeInboxMoney(1); c.Answer(true)
    local e = c.Entries()
    Same(e[1].k, nil); Same(e[2].k, "mail"); Same(e[2].a, 1000)
end

-- A cash-on-delivery message pays out, never in: no evidence
do
    local c = Client()
    c.INBOX = { { money = 1000, cod = 500 } }
    c.FireEvent("MAIL_SHOW")
    c.TakeInboxMoney(1)
    c.Spend(500)
    Same(c.Entries()[1].k, nil); Same(c.Entries()[1].a, -500)
end

-- With the ledger recording and the chat summary off, the mailbox is still listened to; with both off, it is not
do
    local c = Client()
    c.FireEvent("MAIL_SHOW")
    local counts = {}; c.R.ListenerCounts(counts)
    Check((counts.MAIL_SHOW or 0) >= 1, "the mailbox is watched for the ledger")
    local off = Client({ ledger = false })
    counts = {}; off.R.ListenerCounts(counts)
    Same(counts.MAIL_SHOW or 0, 0, "neither switch: nothing watched")
    -- the summary alone still prints and gives the ledger nothing
    local s = Client({ ledger = false, summary = true })
    s.INBOX = { { money = 250 } }
    s.FireEvent("MAIL_SHOW"); s.TakeInboxMoney(1); s.Answer(true); s.FireEvent("MAIL_CLOSED")
    Check(#s.R_OUT == 1 and s.R_OUT[1]:find("Collected", 1, true), "the summary line is unchanged")
    Check(s.TwichUILedgerDB.chars["Rich - Forever"] == nil, "and nothing is recorded")
    -- both on: the line is said and the ledger has the entry
    local b = Client({ summary = true })
    b.INBOX = { { money = 250 } }
    b.FireEvent("MAIL_SHOW"); b.TakeInboxMoney(1); b.Answer(true); b.FireEvent("MAIL_CLOSED")
    Same(#b.R_OUT, 1); Same(b.Entries()[1].k, "mail")
end

-- The evidence API itself: both orders, ambiguity, expiry, wrong direction, repeats, sign
do
    local c = Client()
    local L = c.L
    -- evidence first, its money later
    Same(L.Evidence({ kind = "ahBuy", amount = -4000, item = 25, qty = 2, corr = "ah:1:1" }), "pending")
    c.Spend(4000)
    local e = c.Entries()
    Same(e[1].k, "ahBuy"); Same(e[1].i, 25); Same(e[1].q, 2); Same(e[1].e, "auctionpurchase")
    Same(c.Day().co.ahBuy, 4000); Check(c.Day().co.other == nil)
    -- money first, its evidence later (a few seconds on)
    c.Spend(900)
    c.Advance(3)
    Same(L.Evidence({ kind = "ahBuy", amount = -900, corr = "ah:1:2" }), "attributed")
    Same(c.Entries()[2].k, "ahBuy")
    -- the same completed transaction reported twice is counted once
    Same(L.Evidence({ kind = "ahBuy", amount = -900, corr = "ah:1:2" }), "repeated")
    c.Spend(900); c.Advance(1)
    Same(L.Evidence({ kind = "ahBuy", amount = -900, corr = "ah:1:2" }), "repeated", "a used correlation id attaches to nothing else")
    Same(c.Entries()[3].k, nil)
    -- ambiguity: two unclassified changes of the same amount, evidence for one of them
    c.Spend(1500); c.Advance(1); c.Spend(1500); c.Advance(1)
    Same(L.Evidence({ kind = "ahBuy", amount = -1500, corr = "ah:1:3" }), "ambiguous")
    Same(c.Entries()[4].k, nil); Same(c.Entries()[5].k, nil, "retained as the money moved, attribution unknown")
    -- evidence that matches nothing waits, then expires: later money of that amount is not claimed
    Same(L.Evidence({ kind = "mail", amount = 6000, corr = "m:1" }), "pending")
    c.Advance(11)
    c.Gain(6000)
    Same(c.Entries()[6].k, nil, "expired evidence claims nothing")
    -- wrong direction or amount, unknown kind: refused, never recorded
    Same(select(2, L.Evidence({ kind = "mail", amount = -5 })), "invalid")
    Same(select(2, L.Evidence({ kind = "ahBuy", amount = 5 })), "invalid")
    Same(select(2, L.Evidence({ kind = "other", amount = 5 })), "invalid")
    Same(select(2, L.Evidence({ kind = "vendor", amount = 5 })), "invalid")
    Same(select(2, L.Evidence({ kind = "mail", amount = 0 })), "invalid")
    Same(select(2, L.Evidence({ kind = "mail", amount = 1.5 })), "invalid")
    Same(select(2, L.Evidence({ kind = "mail", amount = 0 / 0 })), "invalid")
    Same(select(2, L.Evidence("x")), "invalid")
    Same(#c.Entries(), 6, "evidence never makes an entry")
    -- an entry with a different amount than the evidence is untouched
    c.Gain(41); Same(L.Evidence({ kind = "mail", amount = 40, corr = "m:2" }), "pending")
    Same(c.Entries()[7].k, nil)
    -- this frame's evidence wins over an older identical change
    c.Gain(2000); c.Advance(2)
    Same(L.Evidence({ kind = "mail", amount = 2000, corr = "m:3" }), "attributed")
    Same(c.Entries()[8].k, "mail")
    c.Gain(2000)
    Same(L.Evidence({ kind = "ahSale", amount = 2000, corr = "m:4" }), "attributed", "the entry of this frame, not the older one")
    Same(c.Entries()[9].k, "ahSale")
    -- an inactive ledger takes no evidence
    c.TwichUIDB.ui.workshopEnabled = false
    c.R.WorkshopLauncher.Apply()
    Same(select(2, L.Evidence({ kind = "mail", amount = 5 })), "inactive")
end

-- Totals reconcile: the day's classified and unclassified parts add up to what came in and went out
do
    local c = Client()
    c.INBOX = { { money = 1000 } }
    c.FireEvent("MAIL_SHOW"); c.TakeInboxMoney(1); c.Answer(true)
    c.Gain(33); c.Spend(21)
    local d = c.Day()
    local ci, co = 0, 0
    for _, v in pairs(d.ci) do ci = ci + v end
    for _, v in pairs(d.co) do co = co + v end
    Same(ci, d.i); Same(co, d.o); Same(d.i, 1033); Same(d.o, 21)
    local sum = 0
    for _, e in ipairs(c.Entries()) do sum = sum + e.a end
    Same(sum, d.i - d.o, "the journal and the totals agree")
end

---------------------------------------------------------------------------
-- Part 2: the Auction House purchase controller
---------------------------------------------------------------------------
do
    local c, W, s = dofile(TESTS .. "auction_debug_mock.lua")
    local R = c.TwichUI
    c.TwichUIDB.ui = c.TwichUIDB.ui or {}
    c.TwichUIDB.ui.workshopEnabled = true
    c.TwichUILedgerDB = nil
    c.NOW = T0
    c.GetServerTime = function() return c.NOW end
    c.GetTime = function() return s.now or 1 end
    c.UnitName = function() return "Rich" end
    local chunk = assert(loadfile(ROOT .. "auction/Ledger.lua")); setfenv(chunk, c); chunk("!!!TwichUI", {})
    local L = R.Ledger
    L.Init(); L.Refresh()
    Check(L.Active(), "the ledger records in this client")
    c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
    local function Entries() return c.TwichUILedgerDB.chars["Rich - Forever"].entries end
    local function Bump() s.now = (s.now or 1) + 1 end
    local function Move(to) s.money = to; Bump(); c.FireEvent("PLAYER_MONEY") end
    local base = s.money

    -- a purchase the game confirmed, whose exact amount then left: attributed
    R.AuctionBuild.verified.buyItem = true
    local id = W.AuctionActions.PrepareBuy(s.Item(), 2)
    Check(W.AuctionActions.Confirm(id))
    Same(#Entries(), 0, "confirming alone moves no money and records nothing")
    W.AuctionActions.Event("AUCTION_HOUSE_PURCHASE_COMPLETED", 31)
    Same(W.AuctionActions.state, "complete")
    Same(#Entries(), 0, "evidence alone makes no entry")
    Move(base - 299)
    Same(#Entries(), 1); Same(Entries()[1].a, -299); Same(Entries()[1].k, "ahBuy"); Same(Entries()[1].i, 10)
    Same(Entries()[1].e, "auctionpurchase")

    -- a cancelled review sends nothing and reports nothing
    local id3 = W.AuctionActions.PrepareBuy(s.Item(34, 3, 500), 2)
    Check(id3 ~= nil)
    W.AuctionActions.Cancel()
    Same(L.Snapshot().pending, 0, "a dismissed review waits for nothing")

    -- a purchase the game did not confirm: no evidence, the money (if any moved) stays unclassified
    s.money = base - 299
    R.AuctionBuild.verified.buyItem = true
    local id2 = W.AuctionActions.PrepareBuy(s.Item(33, 3, 450), 2)
    Check(W.AuctionActions.Confirm(id2))
    W.AuctionActions.Event("AUCTION_HOUSE_PURCHASE_COMPLETED", 99)    -- another auction: not ours
    Same(W.AuctionActions.state, "waiting")
    Move(base - 299 - 450)
    Same(Entries()[2].k, nil, "no completion for this auction: unclassified")
    W.AuctionActions.Event("AUCTION_HOUSE_SHOW_ERROR")               -- the outcome becomes unknown
    Check(W.AuctionActions.state == "unknown" or W.AuctionActions.state == "cancelled", "an error is not a completion")
    Same(Entries()[2].k, nil)
    Same(L.Snapshot().pending, 0, "nothing waits for a purchase that never completed")

    -- a posting completes and moves no revenue; the deposit that left is not a sale and is not guessed at
    s.items = {}
    local before = #Entries()
    W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED", 501)
    Same(#Entries(), before, "a successful posting records nothing")
    Same(L.Snapshot().pending, 0, "and waits for nothing")
    Move(s.money - 2)
    Same(Entries()[#Entries()].k, nil, "its deposit is just a change in gold")
    Same(Entries()[#Entries()].a, -2)
    -- the same controller finished a purchase twice: counted once
    local ok = pcall(function() W.AuctionActions.Event("AUCTION_HOUSE_PURCHASE_COMPLETED", 31) end)
    Check(ok)
end

print("LEDGER ATTRIBUTION PASSED")
