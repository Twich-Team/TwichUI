-- Mailbox gold summary (auction/Mail.lua), the runtime: one and several collections, refusals, repeated events,
-- shifting inbox positions, the game's own take, Open All style loops, postage / COD / unrelated gold left out,
-- closing right after a take, closing and reopening quickly, one line per visit, a fresh total each visit, and
-- nothing saved. The mailbox, the "server" and the clock are mocks: whether the game really answers as modelled
-- is for an in-game test (docs/mailbox-gold-summary.md has the checklist).
dofile(TESTS .. "harness.lua")

local c = MakeClient("Rich", { "!!!TwichUI" })
c.R_OUT = {}
c.print = function(s) table.insert(c.R_OUT, tostring(s)) end

-- The clock: C_Timer.After runs when Advance() passes it.
local now, timers = 0, {}
c.C_Timer = { After = function(d, fn) timers[#timers + 1] = { at = now + d, fn = fn } end }
local function Advance(s)
  now = now + s
  local due, rest = {}, {}
  for _, t in ipairs(timers) do if t.at <= now then due[#due + 1] = t else rest[#rest + 1] = t end end
  timers = rest
  for _, t in ipairs(due) do t.fn() end
end

-- The inbox and the "server". A take is only a request: Answer() is the server replying.
c.MONEY = 5000000
c.GetMoney = function() return c.MONEY end
c.INBOX = {}
c.GetInboxHeaderInfo = function(i)
  local m = c.INBOX[i]
  if not m then return end
  return "icon", "paper", m.sender or "Auction House", m.subject or "Auction successful", m.money or 0, m.cod or 0, 29, m.items or 0
end
local cmds = {}
c.TakeInboxMoney = function(i)
  local m = c.INBOX[i]
  if m then cmds[#cmds + 1] = { mail = m, kind = "money" } end
  return "original return"
end
c.AutoLootMailItem = function(i)
  local m = c.INBOX[i]
  if m then cmds[#cmds + 1] = { mail = m, kind = "auto" } end
end
-- A post-hook as the game's hooksecurefunc: the original runs, then the hook with the same arguments.
c.hooksecurefunc = function(name, fn)
  local orig = c[name]
  c[name] = function(...)
    local r = orig(...)
    fn(...)
    return r
  end
end
local function Gain(n) c.MONEY = c.MONEY + n; c.FireEvent("PLAYER_MONEY") end
local function Spend(n) c.MONEY = c.MONEY - n; c.FireEvent("PLAYER_MONEY") end
-- The server answers the oldest command: ok = its money is paid out (and the message loses it).
local function Answer(ok)
  local cmd = table.remove(cmds, 1)
  if not cmd then return end
  if ok then
    local m = cmd.mail
    local paid = (m.cod or 0) == 0 and m.money or 0
    m.money = 0
    if paid > 0 then Gain(paid) end
  else
    c.FireEvent("MAIL_FAILED")
  end
end

for _, f in ipairs({ "modules/Restock.lua", "auction/Mail.lua" }) do
  local chunk = assert(loadfile(ROOT .. f)); setfenv(chunk, c); chunk("!!!TwichUI", {})
end
c.TwichUIDB = { modules = { chronicle = false } }   -- the Chronicle also listens for PLAYER_MONEY; keep it out of this test
c.LOADED["!!!TwichUI"] = true; c.FireEvent("ADDON_LOADED", "!!!TwichUI")
c.FireEvent("PLAYER_ENTERING_WORLD", true, false)
local R = c.TwichUI
local MG = R.MailGold
local events = R.frame.events

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end
local function Plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function Lines()
  local out = {}
  for _, l in ipairs(c.R_OUT) do out[#out + 1] = Plain(l) end
  return out
end
local function Said(text)
  for _, l in ipairs(Lines()) do if l:find(text, 1, true) then return true end end
  return false
end
local function Count() return #c.R_OUT end
local function Fresh(inbox) c.R_OUT, c.INBOX, cmds = {}, inbox or {}, {} end
local function Open() c.FireEvent("MAIL_SHOW") end
local function Close() c.FireEvent("MAIL_CLOSED") end
local G, S = 10000, 100

---------------------------------------------------------------------------
-- 1. On by default, hooked once, listening only for the mailbox
---------------------------------------------------------------------------
Check(R.DEFAULT_MODULES.mailGoldSummary == true and c.TwichUIDB.modules.mailGoldSummary == true, "on by default")
Check(events.MAIL_SHOW and events.MAIL_CLOSED, "listens for the mailbox opening and closing")
Check(not events.PLAYER_MONEY and not events.MAIL_FAILED, "money and failures are not watched until a visit")
Check(R.Switches.defs.mailGoldSummary ~= nil, "the switch is defined")
Open()
Check(events.PLAYER_MONEY and events.MAIL_FAILED, "watched during a visit")
Close()
Check(not events.PLAYER_MONEY and not events.MAIL_FAILED, "and not after it, with nothing waiting")
Check(c.TakeInboxMoney(1) == "original return", "the game's own call keeps its return value")
cmds = {}

---------------------------------------------------------------------------
-- 2. One collection, and the line
---------------------------------------------------------------------------
Fresh({ { money = 12 * G + 34 * S + 56 } })
Open()
c.TakeInboxMoney(1)
Check(Count() == 0, "a request alone says nothing")
Answer(true)
Check(Count() == 0, "nothing is said until the mailbox closes")
Close()
Check(Count() == 1 and Lines()[1] == "TwichUI: Collected 12g 34s 56c from mail.", "the line: " .. tostring(Lines()[1]))
Check(c.R_OUT[1]:find("|c", 1, true), "the prefix and amount are colored by the usual helpers")

---------------------------------------------------------------------------
-- 3. Several in quick succession (the game's take, then a loop of takes)
---------------------------------------------------------------------------
Fresh({ { money = 100 }, { money = 250 }, { money = 100 }, { money = 5 * G } })
Open()
for i = 1, 4 do c.TakeInboxMoney(i) end
for _ = 1, 4 do Answer(true) end
Close()
Check(Count() == 1 and Said("Collected 5g 4s 50c from mail."), "four takes added up: " .. tostring(Lines()[1]))

---------------------------------------------------------------------------
-- 4. A refusal counts for nothing, and the same amount arriving later from elsewhere is not taken for it
---------------------------------------------------------------------------
Fresh({ { money = 700 } })
Open()
c.TakeInboxMoney(1)
Answer(false)
Check(MG.Snapshot().waiting == 0, "a refusal ends the request")
Gain(700)
Close()
Check(Count() == 0, "no line: the refused take counted nothing and a later 700 is not a mail")

-- A refusal about an item (full bags) is not a refusal of the money.
Fresh({ { money = 900, items = 1 } })
Open()
c.AutoLootMailItem(1)
c.FireEvent("MAIL_FAILED", 12345)
Check(MG.Snapshot().waiting == 1, "an item refusal leaves the money request waiting")
Answer(true)
Close()
Check(Said("Collected 9s from mail."), "the money still counted: " .. tostring(Lines()[1]))

---------------------------------------------------------------------------
-- 5. Repeated events and repeated calls do not count twice
---------------------------------------------------------------------------
Fresh({ { money = 300 } })
Open()
c.TakeInboxMoney(1); c.TakeInboxMoney(1)     -- a double click: two requests, one payment
Answer(true)
c.FireEvent("PLAYER_MONEY"); c.FireEvent("PLAYER_MONEY")   -- the same money reported again
Close()
Check(Count() == 0 and MG.Snapshot().waiting == 1, "the spare request holds the line back until it expires")
Advance(10)
Check(MG.Snapshot().waiting == 0 and Count() == 1 and Said("Collected 3s from mail."), "counted once, one line: " .. tostring(Lines()[1]))

---------------------------------------------------------------------------
-- 6. No money, no line: attachments only, nothing taken, zero sessions
---------------------------------------------------------------------------
Fresh({ { money = 0, items = 3 } })
Open()
c.TakeInboxMoney(1); c.AutoLootMailItem(1)      -- a take of a message with no money
Answer(true); Answer(true)
Close()
Check(Count() == 0, "an attachment-only visit says nothing")
Open(); Close()
Check(Count() == 0, "an empty visit says nothing")
Check(MG.Snapshot().waiting == 0, "nothing waiting")

---------------------------------------------------------------------------
-- 7. Inbox positions shift: a request keeps the amount, not the position
---------------------------------------------------------------------------
Fresh({ { money = 111 }, { money = 222 } })
Open()
c.TakeInboxMoney(1)                      -- message A
table.remove(c.INBOX, 1)                 -- the inbox shifts before the answer: position 1 is now B
cmds[1].mail.money, cmds = 0, {}
Gain(111)
c.TakeInboxMoney(1)                      -- B, now at position 1
Answer(true)
Close()
Check(Said("Collected 3g 33c from mail.") or Said("Collected 3s 33c from mail."), "A and B both counted once: " .. tostring(Lines()[1]))

---------------------------------------------------------------------------
-- 8. The game's own take (AutoLootMailItem), and an Open All style loop that skips COD
---------------------------------------------------------------------------
Fresh({ { money = 1 * G }, { money = 0, cod = 800, items = 1 }, { money = 2 * G, items = 1 } })
Open()
for i = 1, 3 do
  local _, _, _, _, money, cod = c.GetInboxHeaderInfo(i)
  if cod == 0 then
    if money > 0 then c.TakeInboxMoney(i) else c.AutoLootMailItem(i) end
  end
end
for _ = 1, 3 do Answer(true) end
Close()
Check(Said("Collected 3g from mail."), "loop total: " .. tostring(Lines()[1]))

---------------------------------------------------------------------------
-- 9. Postage, COD, unrelated gold and spending are left out
---------------------------------------------------------------------------
Fresh({ { money = 400 }, { money = 0, cod = 650, items = 1 } })
Open()
Spend(30)                                -- postage for a letter sent meanwhile
c.AutoLootMailItem(2)                    -- taking a COD item: not a money take
Check(MG.Snapshot().waiting == 0, "a COD message makes no request")
Spend(650); Answer(true)                 -- the COD payment is paid out, not collected
Gain(650)                                -- an unrelated gain of exactly that amount (loot, a trade)
Check(Count() == 0, "nothing said yet")
c.TakeInboxMoney(1)
Gain(55)                                 -- unrelated gain while a take waits: not the take's amount
Check(MG.Snapshot().waiting == 1, "the unrelated gain did not answer the request")
Answer(true)
Spend(1000)
Close()
Check(Said("Collected 4s from mail.") and not Said("650"), "only the 400 counted: " .. tostring(Lines()[1]))

-- A COD message that also shows money is skipped too.
Fresh({ { money = 500, cod = 100, items = 1 } })
Open()
c.TakeInboxMoney(1); c.AutoLootMailItem(1)
Check(MG.Snapshot().waiting == 0, "a message with a COD charge is never a money take")
Close()

-- Two payments reported as one change.
Fresh({ { money = 100 }, { money = 200 } })
Open()
c.TakeInboxMoney(1); c.TakeInboxMoney(2)
cmds[1].mail.money, cmds[2].mail.money, cmds = 0, 0, {}
Gain(300)
Close()
Check(Said("Collected 3s from mail."), "merged change matched the two oldest requests: " .. tostring(Lines()[1]))

-- Unreadable values are not guessed at.
Fresh({ { money = 100 } })
c.issecretvalue = function(v) return v == 100 end
Open()
c.TakeInboxMoney(1)
Check(MG.Snapshot().waiting == 0, "a hidden amount makes no request")
c.issecretvalue = nil
Close()

---------------------------------------------------------------------------
-- 10. Closing right after a take: the line comes when the money arrives, once
---------------------------------------------------------------------------
Fresh({ { money = 800 } })
Open()
c.TakeInboxMoney(1)
Close()
Check(Count() == 0 and MG.Snapshot().waiting == 1, "closed with a take still waiting: no line yet")
Check(events.PLAYER_MONEY, "still listening for that one answer")
Answer(true)
Check(Count() == 1 and Said("Collected 8s from mail."), "the line came with the money: " .. tostring(Lines()[1]))
Check(not events.PLAYER_MONEY and MG.Snapshot().waiting == 0, "then nothing is watched")
Advance(10); Gain(800); Close()
Check(Count() == 1, "late echoes add nothing")

-- ... and if the answer never comes, the wait is bounded and the line says only what was confirmed.
Fresh({ { money = 800 }, { money = 60 } })
Open()
c.TakeInboxMoney(1); c.TakeInboxMoney(2)
cmds[2].mail.money = 0
Gain(60)                                  -- only the second arrived
Close()
Check(Count() == 0, "one still waiting")
Advance(3)
Check(Count() == 0, "inside the wait")
Advance(2)
Check(Count() == 1 and Said("Collected 60c from mail."), "after the bound: only the confirmed amount: " .. tostring(Lines()[1]))

---------------------------------------------------------------------------
-- 11. Closing and quickly reopening: a late answer belongs to the first visit
---------------------------------------------------------------------------
Fresh({ { money = 100 }, { money = 4000 } })
Open()
c.TakeInboxMoney(1)
Close()
Open()                                    -- reopened before the answer
c.TakeInboxMoney(2)
Answer(true)                              -- the answer to the FIRST take
Check(Said("Collected 1s from mail."), "the first visit got its own money: " .. tostring(Lines()[1]))
Check(Count() == 1, "and the new visit has not spoken")
Answer(true)
Close()
Check(Count() == 2 and Said("Collected 40s from mail."), "the second visit only has its own: " .. table.concat(Lines(), " | "))

-- A reopening without a close in between ends the previous visit.
Fresh({ { money = 500 } })
Open()
c.TakeInboxMoney(1); Answer(true)
Open()
Check(Count() == 1 and Said("Collected 5s from mail."), "the unclosed visit was finished")
Close(); Close()
Check(Count() == 1, "duplicate close events say nothing more")

---------------------------------------------------------------------------
-- 12. A fresh total every opening, one line each
---------------------------------------------------------------------------
Fresh({ { money = 100 } })
for n = 1, 3 do
  c.INBOX[1].money = 100 * n
  Open(); c.TakeInboxMoney(1); Answer(true); Close(); Close()
end
local l = Lines()
Check(#l == 3 and l[1]:find("1s") and l[2]:find("2s") and l[3]:find("3s"), "three visits, three separate totals: " .. table.concat(l, " | "))

---------------------------------------------------------------------------
-- 13. A loading screen ends the visit; switching off lets go silently and unhooks nothing it can't
---------------------------------------------------------------------------
Fresh({ { money = 100 }, { money = 100 } })
Open()
c.TakeInboxMoney(1); Answer(true)
c.TakeInboxMoney(2)
c.FireEvent("PLAYER_LEAVING_WORLD")
Check(Count() == 1 and Said("Collected 1s from mail.") and MG.Snapshot().waiting == 0, "confirmed money reported, the unanswered take let go")
Close()
Check(Count() == 1, "the close that follows adds nothing")

Fresh({ { money = 100 } })
Open()
c.TakeInboxMoney(1); Answer(true)
R:SetEnabled("mailGoldSummary", false)
Check(Count() == 0 and not events.MAIL_SHOW and not events.PLAYER_MONEY, "switched off mid-visit: nothing said, nothing listening")
Close()
c.TakeInboxMoney(1)
Check(MG.Snapshot().waiting == 0, "the hooks are gated by the switch")
R:SetEnabled("mailGoldSummary", true)
Check(events.MAIL_SHOW, "on again: listening")
c.INBOX[1].money = 100
Open(); c.TakeInboxMoney(1); Answer(true); Close()
Check(Count() == 1 and Said("Collected 1s from mail."), "and working, with the hook installed once")

---------------------------------------------------------------------------
-- 14. Bounded
---------------------------------------------------------------------------
local many = {}
for i = 1, 60 do many[i] = { money = i } end
Fresh(many)
Open()
for i = 1, 60 do c.TakeInboxMoney(i) end
Check(MG.Snapshot().waiting == 50, "at most 50 requests wait: " .. MG.Snapshot().waiting)
Close()
Advance(10)
Check(MG.Snapshot().waiting == 0 and Count() == 0, "all expired, nothing said")

---------------------------------------------------------------------------
-- 15. Nothing is saved
---------------------------------------------------------------------------
do
  local seen = {}
  local function Walk(t, path)
    for k, v in pairs(t) do
      local p = path .. "." .. tostring(k)
      if type(v) == "table" then Walk(v, p) else seen[#seen + 1] = p end
    end
  end
  Walk(c.TwichUIDB, "TwichUIDB")
  for _, p in ipairs(seen) do
    local lower = p:lower()
    Check(not (lower:find("mail") and p ~= "TwichUIDB.modules.mailGoldSummary"), "nothing of a visit is saved: " .. p)
    Check(not lower:find("collected"), "no totals saved: " .. p)
  end
end

if failures > 0 then
  print(failures .. " check(s) failed")
  error("test_mail_gold failed")
end
print("MAIL GOLD PASSED")
