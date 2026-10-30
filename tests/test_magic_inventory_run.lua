-- Magic Inventory, moving items (inventory/Run.lua), against a stand-in mailbox, bank and guild bank (tests/mi_mock.lua).
--   * nothing moves when a mailbox, bank or guild bank opens; only the player's Prepare, Send or Deposit acts;
--   * mail: the player's draft is never touched (a draft refuses), at most 12 attachments, one recipient a mail,
--     exactly the reviewed recipient, postage checked, the game's secure confirmation waited for (no time limit),
--     success counted only from MAIL_SEND_SUCCESS with the attachments gone, a failure or no answer never retried,
--     a mail sent from the game's own window noticed;
--   * bank and guild bank: merging into a stack with room, then empty slots; a deposit counts only when the bag slot
--     is empty and the destination holds it; no room stops; the guild and tab must be the chosen ones and depositable;
--   * the cursor: never touched when something else is on it; an item the destination refused goes back;
--   * locked stacks get a few more looks, then are skipped; stacks that changed are found again or skipped;
--   * stopping: closing, combat, rule changes, Stop; what was done stays reported; nothing resumes after a reload.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local db = { modules = { magicInventory = true } }
local c = MIClient("Rich", { db = db })
local MI = c.TwichUI.MagicInventory
local Run = MI.Run
Check(MI.Enabled(), "turned on for these tests")

local function Rule(fields)
  local r = { kind = "bank", enabled = true, cats = {}, qualities = {}, include = {}, exclude = {}, equip = "any", bind = "any", keep = 0 }
  for k, v in pairs(fields) do r[k] = v end
  local id = MI.SaveRule(r)
  Check(MI.Rule(id).enabled, "rule " .. (fields.name or "?") .. " is on")
  return id
end
local function Reset()
  if Run.Current() then Run.Stop() end
  c.TwichUIDB.ui = c.TwichUIDB.ui or {}
  c.TwichUIDB.ui.magicInventory = nil
  c.TwichUIDB.magicInventory = nil
  c.MAIL.name, c.MAIL.subject, c.MAIL.body, c.MAIL.money, c.MAIL.cod, c.MAIL.attach = "", "", "", 0, 0, {}
  c.SENT, c.DEPOSITS, c.PICKUPS, c.CURSOR, c.CLEARED = {}, {}, {}, nil, nil
  c.SENDMAIL_CALLS = 0
  c.R_OUT = {}
  c.MONEY = 100000
  c.MAIL_REFUSES_ATTACH, c.BANK_REFUSES, c.GUILD_REFUSES = nil, nil, nil
  c.TIMERS, c.LONG_TIMERS = {}, {}
  TIMERS, LONG_TIMERS = {}, {}
end
local function Count(id)
  local n = 0
  for _, b in pairs(c.BAGS) do for _, s in pairs(b.slots) do if s.id == id then n = n + s.count end end end
  return n
end
local function Said(pattern)
  for _, line in ipairs(c.R_OUT) do if line:find(pattern) then return true end end
  return false
end

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
Reset()
local slots = {}
for i = 1, 13 do slots[i] = { 2589, 20 } end
c.Bags({ [0] = { size = 16, slots = slots } })
local alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth to bank alt", kind = "mail", dest = alt, cats = { "7:5" } })

-- opening the mailbox moves nothing
c.OpenMail()
FlushTimers()
Check(#c.PICKUPS == 0 and c.SENDMAIL_CALLS == 0 and not Run.Current(), "opening the mailbox does nothing")

-- the player's draft refuses, and is left exactly as it was
local plan = MI.CurrentPlan("mail")
local g = plan.groups[1]
Check(g and g.mails == 2 and g.where.recipient == "Bankalt", "two mails planned to Bankalt")
c.MAIL.name, c.MAIL.body = "Somebody", "hello"
local ok, why = Run.PrepareMail(plan, g)
Check(not ok and why:find("writing a mail"), "a draft refuses: " .. tostring(why))
Check(c.MAIL.name == "Somebody" and c.MAIL.body == "hello" and #c.PICKUPS == 0, "and nothing of it is changed")
c.MAIL.name, c.MAIL.body = "", ""
c.MAIL.money = 500
ok, why = Run.PrepareMail(plan, g)
Check(not ok and why:find("never sends money"), "money typed refuses")
c.MAIL.money = 0
-- the Send Mail tab must be shown
c.MAIL.sendShown = false
ok, why = Run.PrepareMail(plan, g)
Check(not ok and why:find("Send Mail tab"), "needs the Send Mail tab")
c.MAIL.sendShown = true
-- something else on the cursor: refused, never touched
c.CURSOR = { other = true }
ok, why = Run.PrepareMail(plan, g)
Check(not ok and why:find("cursor") and c.CURSOR and c.CURSOR.other and not c.CLEARED, "the player's cursor item is left alone")
c.CURSOR = nil

-- prepare: 12 attached, nothing sent
ok = Run.PrepareMail(plan, g)
Check(ok, "prepare")
local r = Run.Current()
local attached = 0
for _ in pairs(c.MAIL.attach) do attached = attached + 1 end
Check(attached == 12 and r.state == "ready", "12 attachments, ready: " .. attached .. " " .. tostring(r and r.state))
Check(c.SENDMAIL_CALLS == 0, "nothing is sent by preparing")
Check(c.CURSOR == nil, "the cursor is empty afterwards")
-- postage
c.MONEY = 10
ok, why = Run.SendPrepared()
Check(not ok and c.SENDMAIL_CALLS == 0, "not enough for postage: nothing sent")
Check(not Run.Current(), "and the run stops")
Check(Said("postage"), "and says why")
-- the mailbox closing hands the attachments back
c.CloseMail()
c.MONEY = 100000
c.OpenMail()

-- again, all the way
Reset()
c.Bags({ [0] = { size = 16, slots = slots } })
alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth to bank alt", kind = "mail", dest = alt, cats = { "7:5" } })
plan = MI.CurrentPlan("mail")
g = plan.groups[1]
Check(Run.PrepareMail(plan, g), "prepare mail 1")
ok = Run.SendPrepared()
Check(ok and c.SENDMAIL_CALLS == 1 and c.LAST_SEND.to == "Bankalt", "sent to exactly Bankalt")
Check(c.LAST_SEND.subject == "Linen Cloth (20)" and c.LAST_SEND.body == "", "the game's own kind of subject; no body")
Check(Run.Current().state == "sending", "waiting for the game")
c.AnswerSend("success")
r = Run.Current()
Check(r and r.state == "between" and #r.results.confirmed == 12, "12 confirmed, waiting for the next mail")
Check(Count(2589) == 20, "one stack left in the bags")
ok, why = Run.SendPrepared()
Check(not ok, "nothing is sent until the next mail is prepared: " .. tostring(why))
Check(Run.PrepareMail(plan, g), "prepare mail 2")
Check(Run.SendPrepared(), "send mail 2")
c.AnswerSend("success")
Check(not Run.Current() and Run.Last().stopReason == "done", "done")
Check(#c.SENT == 2 and c.SENT[1].to == "Bankalt" and c.SENT[2].to == "Bankalt" and #c.SENT[1].items == 12 and #c.SENT[2].items == 1, "2 mails, 12 and 1, both to Bankalt")
Check(Said("sent 2 mails to Bankalt %(13 stacks%)"), "one summary line: " .. tostring(c.R_OUT[#c.R_OUT]))

-- a failure is reported and never retried
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2592, 20 } } } })
alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth", kind = "mail", dest = alt, cats = { "7:5" } })
plan = MI.CurrentPlan("mail")
Run.PrepareMail(plan, plan.groups[1])
Run.SendPrepared()
c.FireEvent("UI_ERROR_MESSAGE", 1, "Cannot find player")
c.AnswerSend("failed")
Check(not Run.Current() and #Run.Last().results.failed == 2 and Run.Last().results.failed[1].why == "Cannot find player", "a failure names the game's reason")
FlushTimers(); RunLongTimers(60)
Check(c.SENDMAIL_CALLS == 1, "never retried")
-- the items are still attached in the game's window (locked): a new review can't send them twice
plan = MI.CurrentPlan("mail")
Check(#plan.groups == 0, "a new review leaves the attached (locked) stacks out")

-- no answer at all: uncertain, never retried
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth", kind = "mail", dest = alt, cats = { "7:5" } })
plan = MI.CurrentPlan("mail")
Run.PrepareMail(plan, plan.groups[1])
Run.SendPrepared()
RunLongTimers(60)
Check(not Run.Current() and #Run.Last().results.uncertain == 1 and Run.Last().stopReason == "uncertain", "no answer: uncertain")
Check(c.SENDMAIL_CALLS == 1, "and nothing is sent again")
Check(Said("not confirmed"), "the summary says it isn't confirmed")

-- the game's own secure confirmation: waited for without a time limit; declining sends nothing
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
alt = MI.AddDest("mail", "Friend")
MI.SetRecipient(alt, "Stranger")
Rule({ name = "Cloth", kind = "mail", dest = alt, cats = { "7:5" } })
plan = MI.CurrentPlan("mail")
Run.PrepareMail(plan, plan.groups[1])
Run.SendPrepared()
c.AnswerSend("secure")
Check(Run.Current().state == "confirming", "waiting for the player's answer in the game's dialog")
RunLongTimers(600)
Check(Run.Current() and Run.Current().state == "confirming", "no time limit while it is up")
c.AnswerSend("cancel")
Check(Run.Current().state == "ready" and #c.SENT == 0, "declined: nothing sent, still prepared")
Check(Run.Current().note and Run.Current().note:find("Nothing was sent"), "and it says so")
Check(Run.SendPrepared(), "the player may press Send again (a new decision, not a retry)")
c.AnswerSend("secure")
c.AnswerSend("success")
Check(#c.SENT == 1 and Run.Last().stopReason == "done", "confirmed in the game's dialog: sent")

-- a mail sent from the game's own window while ours was prepared
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth", kind = "mail", dest = alt, cats = { "7:5" } })
plan = MI.CurrentPlan("mail")
Run.PrepareMail(plan, plan.groups[1])
c.FireEvent("MAIL_SEND_SUCCESS")
Check(not Run.Current() and Run.Last().stopReason == "sent-elsewhere" and #Run.Last().results.uncertain == 1, "noticed, uncertain, stopped")

-- the recipient changed after the review
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth", kind = "mail", dest = alt, cats = { "7:5" } })
plan = MI.CurrentPlan("mail")
MI.SetRecipient(alt, "Otheralt")
ok, why = Run.PrepareMail(plan, plan.groups[1])
Check(not ok and #c.PICKUPS == 0, "a stale review can't prepare: " .. tostring(why))
-- a rule change while prepared stops the run
plan = MI.CurrentPlan("mail")
Run.PrepareMail(plan, plan.groups[1])
MI.SetNever(2589, true)
Check(not Run.Current() and Run.Last().stopReason == "changed" and c.SENDMAIL_CALLS == 0, "a change while prepared stops it; nothing sent")
MI.SetNever(2589, false)

-- the game refuses an attachment: the item goes back from the cursor
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth", kind = "mail", dest = alt, cats = { "7:5" } })
c.MAIL_REFUSES_ATTACH = true
plan = MI.CurrentPlan("mail")
Run.PrepareMail(plan, plan.groups[1])
Check(c.CURSOR == nil and c.CLEARED == 1, "the refused item was put back")
Check(not Run.Current() and Run.Last().stopReason == "attach-failed", "and the run stopped")
-- a refundable item: the game asks; the run stops
c.MAIL_REFUSES_ATTACH = nil
c.CloseMail(); c.OpenMail()
plan = MI.CurrentPlan("mail")
local realClick = c.ClickSendMailItemButton
c.ClickSendMailItemButton = function(i) c.CURSOR = nil; c.FireEvent("MAIL_LOCK_SEND_ITEMS", i, "[x]") end
Run.PrepareMail(plan, plan.groups[1])
Check(not Run.Current() and Run.Last().stopReason == "refund", "a refund question stops it")
c.ClickSendMailItemButton = realClick

-- combat stops a prepared run
Reset()
c.CloseMail(); c.OpenMail()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 } } } })
alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
Rule({ name = "Cloth", kind = "mail", dest = alt, cats = { "7:5" } })
plan = MI.CurrentPlan("mail")
Run.PrepareMail(plan, plan.groups[1])
c.COMBAT = true
c.FireEvent("PLAYER_REGEN_DISABLED")
Check(not Run.Current() and Run.Last().stopReason == "combat", "combat stops it")
c.COMBAT = false
c.CloseMail()

---------------------------------------------------------------------------
-- Bank
---------------------------------------------------------------------------
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 }, [2] = { 2447, 5 }, [3] = { 2770, 20 } } },
  [6] = { size = 3, slots = { [1] = { 2447, 10 } } } })
Rule({ name = "Herbs to bank", cats = { "7:9", "7:7" } })
c.OpenBank()
FlushTimers()
Check(#c.PICKUPS == 0 and not Run.Current(), "opening the bank does nothing")
plan = MI.CurrentPlan("bank")
g = plan.groups[1]
Check(g and g.kind == "bank" and #g.steps == 3, "three stacks to deposit")
ok = Run.Deposit(plan, g)
Check(ok and Run.Current().index == 1 and Run.Current().waiting, "the first stack is on its way")
c.Settle()
Check(Run.Current() and #Run.Current().results.confirmed == 1, "confirmed only once the game shows it")
c.Settle()
c.Settle()
local last = Run.Last()
Check(not Run.Current() and last.stopReason == "done" and #last.results.confirmed == 3, "all three deposited")
Check(c.BAGS[6].slots[1].count == 15 or c.BAGS[6].slots[1].count == 30, "merged into the bank's stack with room")
Check(Count(2447) == 35 and c.BAGS[0].slots[1] == nil and c.BAGS[0].slots[2] == nil, "the herbs left the bags")

-- no room
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 }, [2] = { 2447, 20 }, [3] = { 2447, 20 } } },
  [6] = { size = 1, slots = {} } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
plan = MI.CurrentPlan("bank")
Run.Deposit(plan, plan.groups[1])
c.Settle()
last = Run.Last()
Check(last and last.stopReason == "full" and #last.results.confirmed == 1 and #last.results.skipped == 2, "full: one deposited, two skipped, stopped")

-- the bank refuses: the item goes back
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 } } }, [6] = { size = 4 } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
c.BANK_REFUSES = true
plan = MI.CurrentPlan("bank")
Run.Deposit(plan, plan.groups[1])
Check(c.CURSOR == nil and c.CLEARED == 1 and c.BAGS[0].slots[1] ~= nil, "refused: back in its bag slot")
Check(Run.Last().stopReason == "move-failed" and #Run.Last().results.failed == 1, "and reported as not moved")

-- a locked stack is looked at a few times, then skipped
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 } } }, [6] = { size = 4 } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
plan = MI.CurrentPlan("bank")
c.BAGS[0].slots[1].locked = true
Run.Deposit(plan, plan.groups[1])
for _ = 1, 5 do FlushTimers() end
last = Run.Last()
Check(last and #last.results.skipped == 1 and last.results.skipped[1].why == "Locked right now", "skipped after a few looks")
Check(#c.PICKUPS == 0, "never picked up")

-- a stack that moved is found again; one that changed is skipped
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 }, [2] = { 2447, 7 } } }, [6] = { size = 4 } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
plan = MI.CurrentPlan("bank")
c.BAGS[0].slots[5] = c.BAGS[0].slots[1]; c.BAGS[0].slots[1] = nil   -- moved by hand
c.BAGS[0].slots[2].count = 6                                          -- changed
Run.Deposit(plan, plan.groups[1])
c.Settle()
last = Run.Last()
Check(last and #last.results.confirmed == 1 and #last.results.skipped == 1, "moved stack found again; changed one skipped")
Check(last.results.skipped[1].why:find("Changed"), "and says it changed")

-- the bank closing mid-run: what was done is reported, the rest stops
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 }, [2] = { 2447, 20 } } }, [6] = { size = 4 } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
plan = MI.CurrentPlan("bank")
Run.Deposit(plan, plan.groups[1])
c.Settle()
c.CloseBank()
last = Run.Last()
Check(last.stopReason == "closed" and #last.results.confirmed == 1 and #last.results.uncertain == 1, "closed: one confirmed, the one in flight uncertain")
Check(Said("What was done stays done"), "the summary says completed transfers stay")

-- a move the game never shows: uncertain if it left the bag, failed if not
Reset()
c.OpenBank()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 } } }, [6] = { size = 4 } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
plan = MI.CurrentPlan("bank")
Run.Deposit(plan, plan.groups[1])
c.PENDING_MOVES = {}       -- the server never answers
RunLongTimers(10)
Check(Run.Last().stopReason == "move-failed", "nothing changed: not moved")
Reset()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 } } }, [6] = { size = 4 } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
plan = MI.CurrentPlan("bank")
Run.Deposit(plan, plan.groups[1])
c.PENDING_MOVES = {}
c.BAGS[0].slots[1] = nil   -- gone from the bag, but nowhere to be seen
RunLongTimers(10)
Check(Run.Last().stopReason == "uncertain" and #Run.Last().results.uncertain == 1, "gone but not seen arriving: uncertain")
c.CloseBank()

---------------------------------------------------------------------------
-- Guild bank
---------------------------------------------------------------------------
Reset()
c.GUILD.name = "Hearth Guild"
c.GUILD.tabs = { [1] = { name = "Main", slots = {} }, [2] = { name = "Mats", slots = {} } }
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2592, 20 }, [3] = { 9004, 1, bound = true } } } })
local gd = MI.AddDest("guild", "Mats tab")
MI.SetGuildTab(gd, "Hearth Guild", 2, "Mats")
Rule({ name = "Cloth to guild", kind = "guild", dest = gd, cats = { "7:5" }, include = { [9004] = true } })
c.OpenGuildBank()
plan = MI.CurrentPlan("guild")
g = plan.groups[1]
local bound = false
for _, s in ipairs(plan.skipped) do if s.id == 9004 and s.reason == "bound-guild" then bound = true end end
Check(bound, "a soulbound item can't go in a guild bank")
c.GUILD.current = 1
ok, why = Run.Deposit(plan, g)
Check(not ok and why:find("Mats"), "another tab shown: refused, naming the tab: " .. tostring(why))
c.GUILD.current = 2
c.GUILD.tabs[2].canDeposit = false
ok, why = Run.Deposit(plan, g)
Check(not ok and why:find("can't deposit"), "no deposit rights: refused")
c.GUILD.tabs[2].canDeposit = true
c.GUILD.tabs[2].name = "Junk"
ok, why = Run.Deposit(plan, g)
Check(not ok and why:find("Junk") and why:find("Mats"), "a renamed tab needs review: " .. tostring(why))
c.GUILD.tabs[2].name = "Mats"
c.GUILD.name = "Other Guild"
ok, why = Run.Deposit(MI.CurrentPlan("guild"), g)
Check(not ok and why:find("Hearth Guild"), "another guild: refused")
plan = MI.CurrentPlan("guild")
Check(#plan.groups == 0 and #plan.attention == 1, "and the review shows the rule needs attention")
c.GUILD.name = "Hearth Guild"
plan = MI.CurrentPlan("guild")
g = plan.groups[1]
ok = Run.Deposit(plan, g)
Check(ok, "deposit")
c.Settle()
c.Settle()
last = Run.Last()
Check(last and last.stopReason == "done" and #last.results.confirmed == 2, "two stacks deposited")
Check(c.GUILD.tabs[2].slots[1] and c.GUILD.tabs[2].slots[2] and next(c.GUILD.tabs[1].slots) == nil, "into tab 2 only")
-- the player switches tab mid-run
Reset()
c.GUILD.tabs[2].slots = {}
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2592, 20 } } } })
gd = MI.AddDest("guild", "Mats tab")
MI.SetGuildTab(gd, "Hearth Guild", 2, "Mats")
Rule({ name = "Cloth to guild", kind = "guild", dest = gd, cats = { "7:5" } })
plan = MI.CurrentPlan("guild")
Run.Deposit(plan, plan.groups[1])
c.GUILD.current = 1
c.Settle()
last = Run.Last()
Check(last.stopReason == "tab-changed" and #last.results.confirmed == 1, "switching tab stops before the next stack")
c.GUILD.current = 2
c.CloseGuildBank()

---------------------------------------------------------------------------
-- Turning it off; reloading
---------------------------------------------------------------------------
Reset()
c.OpenBank()
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 }, [2] = { 2447, 20 } } }, [6] = { size = 4 } })
Rule({ name = "Herbs to bank", cats = { "7:9" } })
plan = MI.CurrentPlan("bank")
Run.Deposit(plan, plan.groups[1])
c.TwichUIDB.modules.magicInventory = false
MI.Refresh()
Check(not Run.Current() and Run.Last().stopReason == "off", "turning it off stops a run")
Check(not Run.IsOpen("bank"), "and stops listening")
c.TwichUIDB.modules.magicInventory = true
MI.Refresh()
-- a reload: a new session with the same saved data has no run and starts nothing
local c2 = MIClient("Rich", { db = c.TwichUIDB })
local MI2 = c2.TwichUI.MagicInventory
c2.OpenBank()
c2.OpenMail()
FlushTimers()
Check(not MI2.Run.Current() and not MI2.Run.Last() and #c2.PICKUPS == 0, "nothing resumes after a reload")
for k in pairs(c.TwichUIDB.magicInventory or {}) do
  Check(k == "never" or k == "chars" or k == "shared", "nothing of a run is saved: " .. tostring(k))
end

if failures == 0 then print("PASSED test_magic_inventory_run") else print(failures .. " failures") os.exit(1) end
