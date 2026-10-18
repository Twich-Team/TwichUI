-- TwichUI: the mailbox gold summary
-- One line in your own chat when you close the mailbox: the money you took from mail during that visit.
-- Each opening of the mailbox is a visit of its own; nothing is saved, and nothing is said if no money was taken.
-- It is a total of what the mail paid you (auction proceeds, money other players sent), not a profit figure.
--
-- How money is attributed (see docs/mailbox-gold-summary.md):
--   * A take REQUEST is noted when the game's TakeInboxMoney or AutoLootMailItem is called (a post-hook: the
--     call runs as it always did). It holds the amount the mailbox showed for that message at that moment and
--     the visit it belongs to; the message's position is never used again, since positions shift as mail goes.
--     Messages with a cash-on-delivery charge are not noted: taking those pays money out.
--   * A request COUNTS only when PLAYER_MONEY then shows a gain of exactly that amount (the oldest matching
--     request first; two requests together if the game reported both as one change). A call alone proves nothing.
--     Postage, COD payments and other spending are losses and are ignored; a gain that matches no waiting
--     request (a loot drop, a trade) is ignored too.
--   * A request is dropped when MAIL_FAILED arrives without an item (a refusal), or after EXPIRY seconds with
--     no matching gain (a call the game ignored). It then counts for nothing.
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

local function MoneyText(copper)
    local RS = R.Restock
    if RS and RS.ColorMoney then return RS.ColorMoney(copper) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- At most one line per visit, and only for money.
local function Summarize(s)
    if s.printed then return end
    s.printed = true
    if s.total > 0 and MG.Enabled() then
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
    for i = 1, #queue do
        if queue[i] == req then table.remove(queue, i) break end
    end
    local s = req.session
    s.waiting = s.waiting - 1
    if collected then s.total = s.total + req.amount end
    if not s.open and s.waiting == 0 then Summarize(s) end
    Rest()
end

local function OnMoney()
    local now = Num(GetMoney())
    local before = lastMoney
    lastMoney = now
    if not (now and before) then return end
    local gain = now - before
    if gain <= 0 or #queue == 0 then return end
    if queue[1].amount == gain then Finish(queue[1], true) return end
    -- Two or more of the oldest, reported as one change.
    local sum, group = queue[1].amount, { queue[1] }
    for k = 2, #queue do
        sum = sum + queue[k].amount
        group[k] = queue[k]
        if sum == gain then
            for i = 1, k do Finish(group[i], true) end
            return
        end
        if sum > gain then break end
    end
    for i = 2, #queue do
        if queue[i].amount == gain then Finish(queue[i], true) return end
    end
end

local function OnFailed(itemID)
    if itemID ~= nil then return end   -- an item that could not be taken; its money (if any) is a separate matter
    if queue[1] then Finish(queue[1], false) end
end

local function CloseVisit(s)
    if not s.open then return end
    s.open = false
    if session == s then session = nil end
    if s.waiting == 0 then Summarize(s) end
    Rest()
end

local function OnShow()
    if session then CloseVisit(session) end   -- the last visit never said it closed: it is over
    session = { open = true, total = 0, waiting = 0 }
    lastMoney = Num(GetMoney())
    Want("PLAYER_MONEY", OnMoney, true)
    Want("MAIL_FAILED", OnFailed, true)
end

local function OnClosed()
    if session then CloseVisit(session) end
end

-- A loading screen ends the visit, and anything still waiting cannot be answered reliably any more.
local function OnLeaving()
    if session then CloseVisit(session) end
    while queue[1] do Finish(queue[1], false) end
    lastMoney = nil
end

-- A take is asked for. Noted only; whether it worked is for PLAYER_MONEY to say.
local function Record(index)
    local s = session
    if not (active and s and s.open and type(index) == "number") then return end
    if #queue >= MAX_WAITING then return end
    local _, _, _, _, money, cod = GetInboxHeaderInfo(index)
    money, cod = Num(money), Num(cod)
    if not money or money <= 0 or cod ~= 0 then return end
    local req = { session = s, amount = money }
    queue[#queue + 1] = req
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
    Rest()
end

-- Safe to call any time, as often as you like: makes the listening match the switch.
function MG.Refresh()
    local on = MG.Enabled()
    if on and not hooked then Hook() end
    active = on
    Want("MAIL_SHOW", OnShow, on)
    Want("MAIL_CLOSED", OnClosed, on)
    Want("PLAYER_LEAVING_WORLD", OnLeaving, on)
    if not on then Abandon() end
end

-- Counts only, for the tests: whether a visit is open and how many requests wait.
function MG.Snapshot() return { open = session ~= nil, waiting = #queue } end

R:OnInit(MG.Refresh)
