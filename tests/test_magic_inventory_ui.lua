-- Magic Inventory's review, interface buttons and bag chooser (inventory/Window.lua, inventory/Picker.lua) with
-- stand-in frames:
--   * opening a mailbox or bank shows a small button with the count and nothing else: no review, no chat, no move;
--   * the review names the exact recipient, says what each action does, lets an entry be left out of this operation
--     without touching the rule, and its actions are the player's (prepare, send, deposit);
--   * an empty state that offers Manage rules; the button goes with the interface;
--   * opening and closing again and again makes no new frames or listeners;
--   * choosing from bags names kinds of item only, never moves anything; Cancel and Esc change nothing.
dofile(TESTS .. "mi_mock.lua")

local failures = 0
local function Check(cond, msg) if not cond then failures = failures + 1; print("FAIL: " .. msg) end end

local c = MIClient("Rich", {
  db = { modules = { magicInventory = true } },
  beforeFiles = function(cl)
    cl.CreateFrame = function(kind, name, parent) local fr = MIFake(kind, parent); if name then cl[name] = fr end return fr end
    cl.UIParent = MIFake("Frame"); cl.UIParent.w, cl.UIParent.h = 1920, 1080
    cl.GameTooltip = MIFake("GameTooltip")
    for _, file in ipairs({ "chronicle/Style.lua", "Look.lua" }) do
      local chunk = assert(loadfile(ROOT .. file)); setfenv(chunk, cl); chunk("!!!TwichUI", {})
    end
  end,
  files = MI_FILES,
})
local R = c.TwichUI
local MI = R.MagicInventory
local Run, Win, Pick = MI.Run, MI.Window, MI.Picker
local opened
R.OpenSettings = function(_, key) opened = key end
c.MailFrame = MIFake("Frame"); c.MailFrame.shown = false
local function Flush() for _ = 1, 6 do FlushTimers() end end

local function Texts(frame, out)
  out = out or {}
  if type(frame.text) == "string" and frame.text ~= "" then out[#out + 1] = frame.text end
  for _, ch in ipairs(frame.children or {}) do if ch.shown ~= false then Texts(ch, out) end end
  return out
end
local function Has(frame, pattern)
  for _, t in ipairs(Texts(frame)) do if t:find(pattern) then return true end end
  return false
end
local function FindButton(frame, pattern)
  for _, ch in ipairs(frame.children or {}) do
    if ch.shown ~= false then
      if ch.text and type(ch.text) == "table" and ch.text.text and ch.text.text:find(pattern) then return ch end
      local hit = FindButton(ch, pattern)
      if hit then return hit end
    end
  end
end
local function Click(b) b.scripts.OnClick(b, "LeftButton") end

c.TwichUIDB.ui = c.TwichUIDB.ui or {}
local slots = {}
for i = 1, 13 do slots[i] = { 2589, 20 } end
slots[14] = { 2447, 10 }
c.Bags({ [0] = { size = 16, slots = slots } })
local alt = MI.AddDest("mail", "Bank alt")
MI.SetRecipient(alt, "Bankalt")
MI.SaveRule({ name = "Cloth to bank alt", kind = "mail", dest = alt, enabled = true, cats = { "7:5" } })
MI.SaveRule({ name = "Herbs to bank", kind = "bank", enabled = true, cats = { "7:9" } })

---------------------------------------------------------------------------
-- Opening a mailbox: a button with a count, nothing else
---------------------------------------------------------------------------
c.MailFrame.shown = true
Flush()
c.R_OUT = {}
c.OpenMail()
Flush()
local mailButton = c.TwichUI.MagicInventory.Window and (function()
  for _, ch in ipairs(c.UIParent.children) do
    if ch.text and type(ch.text) == "table" and ch.text.text and ch.text.text:find("^Magic Inventory") then return ch end
  end
end)()
Check(mailButton and mailButton.shown, "a Magic Inventory button appears at the mailbox")
Check(mailButton and mailButton.text.text == "Magic Inventory \194\183 13 stacks", "with the count: " .. tostring(mailButton and mailButton.text.text))
Check(not Win.IsShown(), "the review doesn't open by itself")
Check(#c.PICKUPS == 0 and c.SENDMAIL_CALLS == 0, "nothing moves when the mailbox opens")
Check(#c.R_OUT == 0, "and nothing is said in chat: " .. tostring(c.R_OUT[1]))
-- placed outside the mailbox window
local p = mailButton.points[1]
Check(p and p[1] == "BOTTOMRIGHT" and p[2] == c.MailFrame and p[3] == "TOPRIGHT", "above the mailbox's top right corner, covering none of its controls")

---------------------------------------------------------------------------
-- The review
---------------------------------------------------------------------------
Click(mailButton)
Flush()
local f = c.TwichUIMagicInventory
Check(Win.IsShown() and Win.Context() == "mail", "the review opens for the mailbox")
Check(Has(f, "Send by mail to Bankalt"), "the exact recipient is shown")
Check(Has(f, "13 stacks.*2 mails.*one recipient per mail"), "stacks, mails, one recipient per mail")
Check(Has(f, "Reserved by \"Herbs to bank\""), "herbs are shown reserved by the bank rule")
Check(Has(f, "No money is sent and C.O.D. is never used"), "says no money and no C.O.D.")
local prep = FindButton(f, "^Prepare mail 1 of 2 to Bankalt$")
Check(prep ~= nil, "the action names what it does")
-- leave one entry out of this operation
local leave = FindButton(f, "^Leave out$")
Click(leave)
Flush()
Check(Has(f, "Left out this time %(your rule is unchanged%)"), "an entry can be left out")
local plan = Win.Plan()
Check(plan.groups[1].stacks == 0 or plan.groups[1].stacks == 13 - 13, "the left-out entry isn't counted: " .. tostring(plan.groups[1].stacks))
Check(#MI.Rule(MI.Rules()[1].id).cats == 1 and MI.Rules()[1].enabled, "the rule itself is unchanged")
Click(FindButton(f, "^Include$"))
Flush()
plan = Win.Plan()
Check(plan.groups[1].stacks == 13, "and put back")
-- prepare and send by the player's clicks
Click(FindButton(f, "^Prepare mail 1 of 2 to Bankalt$"))
Flush()
Check(Run.Current() and Run.Current().state == "ready", "prepared")
Check(c.SENDMAIL_CALLS == 0, "nothing sent yet")
local send = FindButton(f, "^Send mail 1 of 2 to Bankalt$")
Check(send ~= nil, "the next action says send, and to whom")
Check(Has(f, "Postage for this mail"), "the game's postage is shown")
Click(send)
Check(c.SENDMAIL_CALLS == 1 and c.LAST_SEND.to == "Bankalt", "sent by the click, to Bankalt")
c.AnswerSend("success")
Flush()
Check(FindButton(f, "^Prepare mail 2 of 2 to Bankalt$") ~= nil, "then the next mail is offered, not sent")
Run.Stop()
Flush()
Check(Has(f, "Last transfer") and Has(f, "What was done stays done"), "the results say what was done stays done")

-- repeated opening and closing makes nothing new
local frames, listeners = Win.FrameCount(), Run.ListenerCount()
for _ = 1, 5 do
  f:Hide(); Flush()
  Win.Show(); Flush()
end
Check(Win.FrameCount() == frames, "no new frames after reopening: " .. frames .. " -> " .. Win.FrameCount())
Check(Run.ListenerCount() == listeners, "no new listeners")
Check(#c.UISpecialFrames == 1, "Esc registered once")

-- closing the mailbox puts the button and the review away
c.MailFrame.shown = false
c.CloseMail()
Flush()
Check(not mailButton.shown, "the button goes with the mailbox")
Check(not Win.IsShown(), "and the review too")
c.MailFrame.shown = true
for _ = 1, 3 do c.OpenMail(); Flush(); c.CloseMail(); Flush() end
Check(Win.FrameCount() == frames, "opening the mailbox again and again makes no new frames")

-- the game's window can appear a moment after its event: the button still comes
c.MailFrame.shown = false
c.OpenMail()
Check(not mailButton.shown, "no window yet: no button yet")
c.MailFrame.shown = true
Flush()
Check(mailButton.shown and mailButton.points[1][2] == c.MailFrame, "the window appeared: the button is on it")
c.CloseMail()
Flush()

---------------------------------------------------------------------------
-- The bank drawn by another addon: the button still has a place; the deposit is the player's
---------------------------------------------------------------------------
c.BankFrame = MIFake("Frame"); c.BankFrame.shown = false
c.Bags({ [0] = { size = 16, slots = { [1] = { 2447, 20 } } }, [6] = { size = 4 } })
c.PICKUPS = {}
c.OpenBank()
Flush()
local bankButton
for _, ch in ipairs(c.UIParent.children) do
  if ch ~= mailButton and ch.text and type(ch.text) == "table" and ch.text.text and ch.text.text:find("^Magic Inventory") then bankButton = ch end
end
Check(bankButton and bankButton.shown and bankButton.points[1][2] == c.UIParent, "with the game's bank window hidden the button sits at the top of the screen")
Click(bankButton)
Flush()
Check(Has(f, "Deposit in your bank") and FindButton(f, "^Deposit 1 stack$"), "the review offers Deposit 1 stack")
Check(#c.PICKUPS == 0, "nothing moved before the click")
Click(FindButton(f, "^Deposit 1 stack$"))
c.Settle()
Flush()
Check(Run.Last() and #Run.Last().results.confirmed == 1, "deposited by the click")
c.CloseBank()
Flush()

---------------------------------------------------------------------------
-- Empty state
---------------------------------------------------------------------------
c.TwichUIDB.ui.magicInventory = nil
MI.Changed()
c.OpenMail()
Flush()
Win.Show()
Flush()
Check(Has(f, "Nothing to mail from here") and Has(f, "Manage rules opens them"), "an empty state that points at Manage rules")
Click(FindButton(f, "^Manage rules$"))
Check(opened == "magicInventory", "Manage rules opens the settings page")
c.CloseMail()
Flush()
-- the settings' preview moves nothing and has no live action
Win.Show(true)
Flush()
Check(Win.Context() == nil and Has(f, "Preview"), "a preview from the settings")
f:Hide()

---------------------------------------------------------------------------
-- Choosing from bags
---------------------------------------------------------------------------
c.Bags({ [0] = { size = 16, slots = { [1] = { 2589, 20 }, [2] = { 2589, 5 }, [3] = { 2447, 3 } } } })
c.PICKUPS = {}
local got
Check(Pick.Open({ purpose = "Test", selected = {}, onDone = function(set) got = set end }), "opens")
Check(Pick.CellCount() == 2, "one square per kind of item, not per stack")
Pick.Toggle(2589)
Pick.Done()
Check(got and got[2589] and not got[2447], "Done hands back the chosen kinds")
Check(#c.PICKUPS == 0 and c.CURSOR == nil, "nothing was picked up")
got = nil
Pick.Open({ selected = { [2447] = true }, onDone = function(set) got = set end })
Pick.Toggle(2589)
Pick.Cancel()
Check(got == nil, "Cancel changes nothing")
Pick.Open({ selected = {}, onDone = function(set) got = set end })
Pick.Toggle(2589)
c.TwichUIMagicInventoryPicker:Hide()   -- Esc
Check(got == nil and not Pick.IsShown(), "Esc changes nothing")
for _ = 1, 4 do Pick.Open({ selected = {}, onDone = function() end }); Pick.Cancel() end
Check(Pick.CellCount() == 2, "reopening reuses the squares")

if failures == 0 then print("PASSED test_magic_inventory_ui") else print(failures .. " failures") os.exit(1) end
