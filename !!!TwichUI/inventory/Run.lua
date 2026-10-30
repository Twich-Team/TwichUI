-- TwichUI: Magic Inventory, moving items
-- Carries out a reviewed plan, only when the player asks, one stack at a time, at the mailbox, bank or guild bank
-- that is open. Nothing here starts by itself: opening an interface only lets the review be built (Window.lua).
-- Nothing is saved, so nothing resumes after a reload, a logout, combat or reopening the interface.
--
-- The game's side (Forever 1.60.1 UI source; none of it is verified in the game yet, docs/magic-inventory.md):
--   Mail (Blizzard_MailFrame/MailFrame.lua): an attachment is the cursor's item dropped with
--     ClickSendMailItemButton(slot); ATTACHMENTS_MAX_SEND (12) per mail; GetSendMailItem(i) -> name, itemID, texture,
--     count; GetSendMailPrice() is the postage of what is attached; SendMail(to, subject, body); MAIL_SEND_SUCCESS,
--     MAIL_FAILED; MAIL_LOCK_SEND_ITEMS when an attachment would lose a refund (the game asks the player). Items for a
--     player who isn't a friend or guild member raise SECURE_TRANSFER_CONFIRM_SEND_MAIL: the game's own secure dialog,
--     which only the player can answer (SECURE_TRANSFER_CANCEL if declined). MAIL_SEND_SUCCESS makes Blizzard's frame
--     clear the recipient, subject and body (SendMailFrame_Reset), so a mail is never prepared over the player's draft.
--   Bank (Camelot BankFrame.lua): the character bank's tabs are bags (C_Bank.FetchPurchasedBankTabIDs); an item is
--     moved with C_Container.PickupContainerItem from the bag slot, then onto a bank slot.
--   Guild bank (Mainline Blizzard_GuildBankUI.lua): GetCurrentGuildBankTab, GetGuildBankTabInfo -> name, icon,
--     isViewable, canDeposit; 98 slots a tab; PickupGuildBankItem(tab, slot) drops the cursor's item there;
--     GUILDBANKBAGSLOTS_CHANGED. Whether Forever's realms have guild vaults at all isn't known.
--
-- Safety, in the order a step is taken:
--   * the interface is still open, out of combat, the plan's generation is current (no rule, recipient, tab or
--     Never transfer change since the review), the destination is the reviewed one;
--   * the stack is found again by item and count (its old slot first, never trusted by index alone) and judged again
--     (MI.StackProblem); locked: looked at again a few times, then skipped;
--   * the cursor must be empty before anything is picked up; an item TwichUI picked up and the game didn't take is
--     put back with ClearCursor (which returns it to its slot); something else on the cursor is never touched;
--   * a step counts only when the game shows it done (the item in the mail's attachment, the bank or guild bank slot
--     holding it and the bag slot empty); before that, bag events change nothing; past a bound wait it is uncertain
--     and the run stops. Nothing is ever retried, so a send is never repeated.

local R = TwichUI
local MI = R.MagicInventory
local Run = {}
MI.Run = Run

local ATTACH_WAIT = 2      -- seconds the game has to show an attachment
local SEND_WAIT = 20       -- ... to answer a send (not counted while the game's secure confirmation is up)
local MOVE_WAIT = 4        -- ... to show a bank or guild bank deposit
local LOCK_TRIES = 3       -- a locked stack is looked at this many more times, LOCK_WAIT apart
local LOCK_WAIT = 0.5
local GUILD_SLOTS = 98     -- MAX_GUILDBANK_SLOTS_PER_TAB in the Forever Blizzard_GuildBankUI.lua (a local there)

local Plain = MI.Plain
local function InCombat() return InCombatLockdown and InCombatLockdown() end

MI.STOP_TEXT = {
    closed = "the window closed",
    combat = "combat started",
    changed = "your rules or destinations changed",
    off = "Magic Inventory was turned off",
    leaving = "you left the world",
    stopped = "you stopped it",
    cursor = "something is on your cursor",
    draft = "you are writing a mail",
    blocked = "the game blocked an action",
    refund = "the game asks whether to give up a refund for one of these items",
    postage = "you don't have enough money for the postage",
    ["recipient-changed"] = "the recipient changed since the review",
    ["attach-failed"] = "the game didn't take an attachment",
    ["attachments-changed"] = "the attachments changed since they were prepared",
    ["sent-elsewhere"] = "a mail was sent from the game's own window",
    ["send-failed"] = "the game didn't send the mail",
    uncertain = "the game didn't confirm the last step",
    full = "there is no room left",
    ["no-deposit"] = "you can't deposit in that tab",
    ["tab-changed"] = "the guild bank shows another tab",
    ["guild-changed"] = "this isn't the guild or tab you chose",
    ["move-failed"] = "the game didn't take the item",
    stale = "your bags changed since the review",
    done = "done",
}

---------------------------------------------------------------------------
-- Which interfaces are open (heard only while the feature is on)
---------------------------------------------------------------------------
local open = { mail = false, bank = false, guild = false }
local FRAMES = { mail = "MailFrame", guild = "GuildBankFrame" }

-- Open now: the game said it opened and hasn't said it closed, and its window (if it is one we can see) is up. The
-- bank's window may be another addon's, so the bank asks the game instead.
function Run.IsOpen(kind)
    if not open[kind] then return false end
    if kind == "bank" then
        if C_Bank and C_Bank.CanUseBank and Enum and Enum.BankType then
            local ok, can = pcall(C_Bank.CanUseBank, Enum.BankType.Character)
            if ok and can == false then return false end
        end
        return true
    end
    local frame = _G[FRAMES[kind]]
    if type(frame) == "table" and frame.IsShown and not frame:IsShown() then return false end
    return true
end

function Run.OpenKind()
    for _, kind in ipairs({ "guild", "bank", "mail" }) do
        if Run.IsOpen(kind) then return kind end
    end
end

local listeners = {}
function Run.OnUpdate(fn) listeners[#listeners + 1] = fn end
local function Notify(what)
    for _, fn in ipairs(listeners) do
        local ok, err = pcall(fn, what)
        if not ok then R.Fault("magic inventory", err) end
    end
end
Run.Notify = Notify

---------------------------------------------------------------------------
-- The run
---------------------------------------------------------------------------
local run            -- the run in progress, or nil
local last           -- the last run's results (this session only)
local token = 0      -- bumped to drop every timer waiting on an older step
local active = {}    -- [event] = handler while registered

local function Want(event, handler, wanted)
    if wanted and not active[event] then
        active[event] = handler
        R:On(event, handler)
    elseif not wanted and active[event] then
        R:Off(event, active[event])
        active[event] = nil
    end
end

local STEP_EVENTS = { "MAIL_SEND_INFO_UPDATE", "MAIL_LOCK_SEND_ITEMS", "MAIL_SEND_SUCCESS", "MAIL_FAILED",
    "SECURE_TRANSFER_CONFIRM_SEND_MAIL", "SECURE_TRANSFER_CANCEL", "UI_ERROR_MESSAGE", "BAG_UPDATE_DELAYED",
    "GUILDBANKBAGSLOTS_CHANGED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "PLAYER_REGEN_DISABLED" }

function Run.Current() return run end
function Run.Last() return last end
function Run.Busy() return run ~= nil end

local function NewResults() return { confirmed = {}, failed = {}, skipped = {}, uncertain = {} } end

local function Record(r, status, step, why, extra)
    local list = r.results[status]
    local e = { id = step.id, count = step.count, link = step.link or (step.entry and step.entry.facts and step.entry.facts.link),
        facts = step.entry and step.entry.facts, why = why, rule = step.entry and step.entry.rule }
    if extra then for k, v in pairs(extra) do e[k] = v end end
    list[#list + 1] = e
end

local function Say(fmt, ...) R.Print(fmt, ...) end

local function Plural(n, one, many) return n == 1 and one or (many or (one .. "s")) end

-- One line, once, in your own chat when a run ends. Only what the game confirmed is called done.
local function Summary(r, reason)
    local res = r.results
    local done = #res.confirmed
    local where
    if r.kind == "mail" then where = ("sent %d %s to %s"):format(r.mailsSent or 0, Plural(r.mailsSent or 0, "mail"), r.recipient or "?")
    elseif r.kind == "bank" then where = "deposited in your bank"
    else where = ("deposited in %s"):format(r.where and r.where.tabName and ("the guild bank tab \"" .. r.where.tabName .. "\"") or "the guild bank") end
    local parts = {}
    if r.kind == "mail" then
        parts[#parts + 1] = ("Magic Inventory %s (%d %s)."):format(where, done, Plural(done, "stack"))
    elseif done > 0 then
        parts[#parts + 1] = ("Magic Inventory %s: %d %s."):format(where, done, Plural(done, "stack"))
    else
        parts[#parts + 1] = "Magic Inventory moved nothing."
    end
    if #res.uncertain > 0 then parts[#parts + 1] = ("%d %s not confirmed by the game: check before trying again."):format(#res.uncertain, Plural(#res.uncertain, "stack was", "stacks were")) end
    if #res.failed > 0 then parts[#parts + 1] = ("%d didn't move."):format(#res.failed) end
    if #res.skipped > 0 then parts[#parts + 1] = ("%d skipped."):format(#res.skipped) end
    if reason and reason ~= "done" then parts[#parts + 1] = ("Stopped: %s. What was done stays done."):format(MI.STOP_TEXT[reason] or reason) end
    if r.kind == "mail" and r.attached and next(r.attached) and reason ~= "closed" then
        parts[#parts + 1] = "Prepared items may still be attached in the game's Send Mail window: remove them there, or close the mailbox to get them back."
    end
    Say("%s", table.concat(parts, " "))
end

local function StopListening()
    for _, e in ipairs(STEP_EVENTS) do Want(e, nil, false) end
end

-- Ends the run. Everything waiting is dropped; nothing is undone (a sent mail or a deposit can't be).
local function Finish(r, reason, quiet)
    if r ~= run then return end
    token = token + 1
    run = nil
    StopListening()
    r.stopReason = reason
    r.finished = true
    last = r
    if reason ~= "done" then R.Life.Note("mi-stopped") end
    if not quiet then Summary(r, reason) end
    Notify("finished")
end

function Run.Stop(reason)
    local r = run
    if not r then return false end
    -- what is waiting on the game is uncertain from here: the game may still do it
    if r.waiting then Record(r, "uncertain", r.waiting.step, "stopped while the game was answering") end
    Finish(r, reason or "stopped")
    return true
end

-- Still right to act? Returns true, or false and a stop reason.
local function Valid(r)
    if r ~= run then return false, "stopped" end
    if not MI.Enabled() then return false, "off" end
    if InCombat() then return false, "combat" end
    if not Run.IsOpen(r.kind) then return false, "closed" end
    if r.generation ~= MI.Generation() then return false, "changed" end
    return true
end

-- The cursor holds nothing (nothing of the player's would be disturbed).
local function CursorFree()
    if CursorHasItem and CursorHasItem() then return false end
    if GetCursorInfo and GetCursorInfo() ~= nil then return false end
    return true
end

local function CursorItem()
    if not GetCursorInfo then return nil end
    local kind, id = GetCursorInfo()
    if kind == "item" then return Plain(id) end
end

---------------------------------------------------------------------------
-- Finding a planned stack again. Its old slot first, then any carried stack of the same item and count that this run
-- hasn't used. The stack is judged again for the destination, as it is now.
---------------------------------------------------------------------------
local function SlotKey(bag, slot) return bag * 1000 + slot end

local function Resolve(r, step)
    local rule = step.entry and MI.Rule(step.entry.ruleId)
    if not rule then return nil, "stale" end
    local function Usable(s)
        if not s or s.id ~= step.id or s.count ~= step.count or r.used[SlotKey(s.bag, s.slot)] then return false end
        return true
    end
    local s = MI.ReadSlot(step.bag, step.slot)
    if not Usable(s) then
        s = nil
        for bag = 0, MI.LastBag() do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local c = MI.ReadSlot(bag, slot)
                if Usable(c) then s = c break end
            end
            if s then break end
        end
    end
    if not s then return nil, "stale" end
    if MI.IsNever(s.id) then return nil, "never" end
    local why = MI.StackProblem(s, r.kind, rule)
    if why then return nil, why, s end
    return s
end

-- Puts the cursor's item (picked up by this run) back where it came from.
local function PutBack()
    if CursorHasItem and CursorHasItem() and ClearCursor then ClearCursor() end
end

-- Picks up a stack. Returns true when the cursor now holds exactly that item.
local function PickUp(s)
    C_Container.PickupContainerItem(s.bag, s.slot)
    if CursorItem() == s.id then return true end
    PutBack()   -- whatever is on the cursor now came from this pickup (it was empty before)
    return false
end

-- A locked stack is looked at again a few times; then the step is skipped.
local function LockedRetry(r, step, again)
    step.lockTries = (step.lockTries or 0) + 1
    if step.lockTries > LOCK_TRIES then return false end
    local t = token
    C_Timer.After(LOCK_WAIT, function() if t == token and r == run then again(r) end end)
    return true
end

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
local function AttachMax() return math.max(1, math.min(12, tonumber(_G.ATTACHMENTS_MAX_SEND) or MI.ATTACH_FALLBACK)) end

local function TextOf(box)
    local b = _G[box]
    if type(b) ~= "table" or not b.GetText then return "" end
    local t = Plain(b:GetText())
    return type(t) == "string" and t or ""
end

-- What is in the game's Send Mail window that isn't this run's: nil when nothing, else a sentence.
-- mine: { [attachSlot] = true } for attachments this run made (their automatic subject counts as theirs).
function Run.MailDraft(mine)
    mine = mine or {}
    for i = 1, AttachMax() do
        if HasSendMailItem and HasSendMailItem(i) and not mine[i] then
            return "Items are attached in the game's Send Mail window. Send or remove them first."
        end
    end
    if TextOf("SendMailNameEditBox") ~= "" or TextOf("SendMailBodyEditBox") ~= "" then
        return "You are writing a mail. Send or clear it first: Magic Inventory won't change it."
    end
    local subject = TextOf("SendMailSubjectEditBox")
    local auto = _G.SendMailFrame and Plain(_G.SendMailFrame.previousItem)
    if subject ~= "" and not (next(mine) and subject == auto) then
        return "You are writing a mail. Send or clear it first: Magic Inventory won't change it."
    end
    local money = (GetSendMailMoney and Plain(GetSendMailMoney())) or 0
    local cod = (GetSendMailCOD and Plain(GetSendMailCOD())) or 0
    local typed = (MoneyInputFrame_GetCopper and _G.SendMailMoney and Plain(MoneyInputFrame_GetCopper(_G.SendMailMoney))) or 0
    if (type(money) == "number" and money > 0) or (type(cod) == "number" and cod > 0) or (type(typed) == "number" and typed > 0) then
        return "Money or a C.O.D. amount is set in the game's Send Mail window. Clear it first: Magic Inventory never sends money or uses C.O.D."
    end
    return nil
end

-- Can the next mail of this group be prepared now? true, or false and a sentence.
function Run.CanPrepare(plan, group)
    if not MI.Enabled() then return false, "Magic Inventory is off." end
    if InCombat() then return false, "Wait until combat ends." end
    if not Run.IsOpen("mail") then return false, "Open a mailbox first." end
    local send = _G.SendMailFrame
    if type(send) == "table" and send.IsVisible and not send:IsVisible() then
        return false, "Open the game's Send Mail tab: the mail is prepared there, where you can see it."
    end
    if run and run.state ~= "between" then return false, "Another transfer is in progress." end
    if plan.generation ~= MI.Generation() then return false, "Your rules changed since this review. Review again." end
    local where = group.where
    local now = group.entries[1] and MI.Rule(group.entries[1].ruleId)
    local current = now and now.dest and MI.Resolve(now.dest)
    if not (where and current and current.recipient == where.recipient) then
        return false, "The recipient changed since this review. Review again."
    end
    local draft = Run.MailDraft()
    if draft then return false, draft end
    if not CursorFree() then return false, "Put down what is on your cursor first." end
    return true
end

local AttachNext
local OnMailSuccess   -- (below) a mail the game says was sent

local function OnLockRefund()
    local r = run
    if r and r.kind == "mail" and r.state == "attaching" then
        if r.waiting then Record(r, "failed", r.waiting.step, MI.STOP_TEXT.refund) end
        r.waiting = nil
        Finish(r, "refund")
    end
end

local function AttachedAt(i, step)
    if not (HasSendMailItem and HasSendMailItem(i)) then return false end
    local _, id, _, count = GetSendMailItem(i)
    return Plain(id) == step.id and Plain(count) == step.count
end

local function AttachSettled(r, timedOut)
    local w = r.waiting
    if not w then return end
    if AttachedAt(w.slot, w.step) then
        r.waiting = nil
        r.attached[w.slot] = { step = w.step, bag = w.s.bag, slot = w.s.slot }
        r.attachIndex = r.attachIndex + 1
        Want("MAIL_SEND_INFO_UPDATE", nil, false)
        AttachNext(r)
    elseif timedOut then
        Record(r, "failed", w.step, MI.STOP_TEXT["attach-failed"])
        r.waiting = nil
        Finish(r, "attach-failed")
    end
end

local function OnSendInfo()
    local r = run
    if r and r.kind == "mail" and r.state == "attaching" and r.waiting then AttachSettled(r, false) end
end

AttachNext = function(r)
    local ok, why = Valid(r)
    if not ok then Finish(r, why) return end
    local step = r.batch[r.attachIndex]
    if not step then
        if next(r.attached) == nil then
            -- nothing could be attached: this mail is skipped, nothing is sent
            r.batchIndex = r.batchIndex + 1
            r.state = r.batchIndex <= #r.group.batches and "between" or nil
            if not r.state then Finish(r, "done") else Notify("between") end
            return
        end
        r.state = "ready"
        r.price = Plain(GetSendMailPrice and GetSendMailPrice()) or nil
        Notify("ready")
        return
    end
    local s, problem = Resolve(r, step)
    if not s then
        if problem == "locked" and LockedRetry(r, step, AttachNext) then return end
        Record(r, "skipped", step, MI.ReasonText(problem == "stale" and "stale" or problem))
        r.attachIndex = r.attachIndex + 1
        return AttachNext(r)
    end
    if not CursorFree() then Finish(r, "cursor") return end
    local slot
    for i = 1, AttachMax() do
        if not (HasSendMailItem and HasSendMailItem(i)) and not r.attached[i] then slot = i break end
    end
    if not slot then Finish(r, "attachments-changed") return end
    local pt = R.Perf.on and R.Perf.Start("inventory.step")
    if not PickUp(s) then
        if pt then R.Perf.Stop(pt) end
        Record(r, "failed", step, "The game didn't pick it up")
        Finish(r, "attach-failed")
        return
    end
    r.used[SlotKey(s.bag, s.slot)] = true
    ClickSendMailItemButton(slot)
    if CursorHasItem and CursorHasItem() then
        PutBack()
        if pt then R.Perf.Stop(pt) end
        Record(r, "failed", step, MI.STOP_TEXT["attach-failed"])
        Finish(r, "attach-failed")
        return
    end
    if pt then R.Perf.Stop(pt) end
    token = token + 1
    local t = token
    r.waiting = { step = step, s = s, slot = slot, token = t }
    if AttachedAt(slot, step) then return AttachSettled(r, false) end   -- the game showed it at once
    Want("MAIL_SEND_INFO_UPDATE", OnSendInfo, true)
    C_Timer.After(ATTACH_WAIT, function()
        if r == run and r.waiting and r.waiting.token == t then AttachSettled(r, true) end
    end)
end

-- Attaches the next mail of a reviewed mail group (the player's click). Nothing is sent until SendPrepared.
-- Returns true, or false and a sentence.
function Run.PrepareMail(plan, group)
    local ok, why = Run.CanPrepare(plan, group)
    if not ok then return false, why end
    local r = run
    if not (r and r.state == "between" and r.group == group) then
        if r then return false, "Another transfer is in progress." end
        r = { kind = "mail", plan = plan, group = group, generation = plan.generation, where = group.where,
            recipient = group.where.recipient, batchIndex = 1, mailsSent = 0, results = NewResults(), used = {} }
        run = r
        Want("MAIL_LOCK_SEND_ITEMS", OnLockRefund, true)
        Want("PLAYER_REGEN_DISABLED", function() if run then Run.Stop("combat") end end, true)
        Want("ADDON_ACTION_BLOCKED", Run.OnBlocked, true)
        Want("ADDON_ACTION_FORBIDDEN", Run.OnBlocked, true)
    end
    r.batch = group.batches[r.batchIndex]
    if not r.batch then Finish(r, "done") return false, "Nothing left to send." end
    r.state, r.attachIndex, r.attached, r.price = "attaching", 1, {}, nil
    r.error = nil
    -- heard from here on, so a mail sent with the game's own Send button while these are attached is noticed
    Want("MAIL_SEND_SUCCESS", OnMailSuccess, true)
    Notify("attaching")
    AttachNext(r)
    return true
end

-- The attachments are exactly what this run attached.
local function AttachmentsIntact(r)
    for i = 1, AttachMax() do
        local a = r.attached[i]
        if a then
            if not AttachedAt(i, a.step) then return false end
        elseif HasSendMailItem and HasSendMailItem(i) then
            return false
        end
    end
    return true
end

local function MailSettled(r, outcome)
    token = token + 1
    Want("MAIL_SEND_SUCCESS", nil, false)
    Want("MAIL_FAILED", nil, false)
    Want("SECURE_TRANSFER_CONFIRM_SEND_MAIL", nil, false)
    Want("SECURE_TRANSFER_CANCEL", nil, false)
    Want("UI_ERROR_MESSAGE", nil, false)
    local attached = {}
    for i = 1, AttachMax() do if r.attached[i] then attached[#attached + 1] = r.attached[i].step end end
    if outcome == "success" then
        local left = false
        for i = 1, AttachMax() do if HasSendMailItem and HasSendMailItem(i) then left = true end end
        for _, step in ipairs(attached) do
            Record(r, left and "uncertain" or "confirmed", step, left and "The game said it sent, but items are still attached" or nil,
                { to = r.recipient, mail = r.batchIndex })
        end
        r.mailsSent = r.mailsSent + 1
        r.attached = {}
        if left then Finish(r, "uncertain") return end
        r.batchIndex = r.batchIndex + 1
        if r.batchIndex > #r.group.batches then Finish(r, "done") return end
        r.state = "between"
        Notify("between")
    elseif outcome == "cancelled" then
        -- the player said no in the game's own confirmation: nothing was sent, the items are still attached
        r.state = "ready"
        r.note = "You cancelled the game's confirmation. Nothing was sent; the items are still attached."
        Notify("ready")
    elseif outcome == "failed" then
        for _, step in ipairs(attached) do Record(r, "failed", step, r.error or MI.STOP_TEXT["send-failed"], { to = r.recipient }) end
        Finish(r, "send-failed")
    else
        for _, step in ipairs(attached) do Record(r, "uncertain", step, "The game didn't say whether the mail was sent", { to = r.recipient }) end
        Finish(r, "uncertain")
    end
end

OnMailSuccess = function()
    local r = run
    if not (r and r.kind == "mail") then return end
    if r.state == "sending" or r.state == "confirming" then MailSettled(r, "success") return end
    -- not ours: the game's own Send button was used while this run had items attached
    if r.state == "ready" or r.state == "attaching" then
        for i = 1, AttachMax() do
            local a = r.attached[i]
            if a then Record(r, "uncertain", a.step, "Sent from the game's own Send Mail window, to whoever was typed there") end
        end
        r.attached = {}
        Finish(r, "sent-elsewhere")
    end
end

local function OnMailFailed()
    local r = run
    if r and r.kind == "mail" and (r.state == "sending" or r.state == "confirming") then MailSettled(r, "failed") end
end

local function OnSecureConfirm()
    local r = run
    if r and r.kind == "mail" and r.state == "sending" then
        token = token + 1   -- no time limit while the game's own question is up: it is the player's to answer
        r.state = "confirming"
        Notify("confirming")
    end
end

local function OnSecureCancel()
    local r = run
    if r and r.kind == "mail" and (r.state == "confirming" or r.state == "sending") then MailSettled(r, "cancelled") end
end

local function OnError(_, message)
    local r = run
    if not r then return end
    message = Plain(message)
    if type(message) == "string" and message ~= "" then r.error = message:sub(1, 160) end
end

-- Sends the prepared mail (the player's click). Everything is checked again first. Returns true, or false and a
-- sentence (and nothing is sent).
function Run.SendPrepared()
    local r = run
    if not (r and r.kind == "mail" and r.state == "ready") then return false, "Nothing is prepared to send." end
    local ok, why = Valid(r)
    if not ok then Finish(r, why) return false, MI.STOP_TEXT[why] end
    local mine = {}
    for i in pairs(r.attached) do mine[i] = true end
    local draft = Run.MailDraft(mine)
    if draft then return false, draft end
    if not AttachmentsIntact(r) then Finish(r, "attachments-changed") return false, MI.STOP_TEXT["attachments-changed"] end
    local rule = r.group.entries[1] and MI.Rule(r.group.entries[1].ruleId)
    local current = rule and rule.dest and MI.Resolve(rule.dest)
    if not (current and current.recipient == r.recipient) then Finish(r, "recipient-changed") return false, MI.STOP_TEXT["recipient-changed"] end
    local price = Plain(GetSendMailPrice and GetSendMailPrice())
    local money = Plain(GetMoney and GetMoney())
    if type(price) == "number" and type(money) == "number" and price > money then Finish(r, "postage") return false, MI.STOP_TEXT.postage end
    -- the subject is what the game would write: the first attachment's name, and its count
    local firstSlot = 1
    for i = AttachMax(), 1, -1 do if r.attached[i] then firstSlot = i end end
    local name, _, _, count = GetSendMailItem(firstSlot)
    name, count = Plain(name), Plain(count)
    local subject = type(name) == "string" and name ~= "" and ((type(count) == "number" and count > 1) and (name .. " (" .. count .. ")") or name) or "Items"
    r.state = "sending"
    r.error, r.note = nil, nil
    token = token + 1
    local t = token
    Want("MAIL_SEND_SUCCESS", OnMailSuccess, true)
    Want("MAIL_FAILED", OnMailFailed, true)
    Want("SECURE_TRANSFER_CONFIRM_SEND_MAIL", OnSecureConfirm, true)
    Want("SECURE_TRANSFER_CANCEL", OnSecureCancel, true)
    Want("UI_ERROR_MESSAGE", OnError, true)
    local sent, err = pcall(SendMail, r.recipient, subject, "")
    if not sent then
        R.Fault("magic inventory", err)
        MailSettled(r, "failed")
        return false, MI.STOP_TEXT["send-failed"]
    end
    Notify("sending")
    C_Timer.After(SEND_WAIT, function()
        if r == run and r.state == "sending" and token == t then MailSettled(r, "uncertain") end
    end)
    return true
end

---------------------------------------------------------------------------
-- Bank and guild bank deposits
---------------------------------------------------------------------------
local function BankBags()
    local bags = {}
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType then
        local ok, list = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
        if ok and type(list) == "table" then
            for _, id in ipairs(list) do
                id = Plain(id)
                if type(id) == "number" then bags[#bags + 1] = id end
            end
        end
    end
    return bags
end
Run.BankBags = BankBags

local function FamilyFits(bag, id)
    local _, family = C_Container.GetContainerNumFreeSlots(bag)
    family = Plain(family)
    if not family or family == 0 then return true end
    local itemFamily = C_Item and C_Item.GetItemFamily and Plain(C_Item.GetItemFamily(id)) or 0
    return bit and bit.band and bit.band(family, itemFamily or 0) ~= 0 or false
end

-- A bank slot for this stack: a stack of the same item with room for all of it, else an empty slot in a bag that
-- can hold it. Never a slot this run is already waiting on. Returns bag, slot, countBefore.
local function BankTarget(r, s)
    local maxStack = s.facts and s.facts.maxStack or 1
    local bags = BankBags()
    for _, bag in ipairs(bags) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and Plain(info.itemID) == s.id and not r.targets[SlotKey(bag, slot)] and Plain(info.isLocked) == false then
                local n = Plain(info.stackCount) or 0
                if n + s.count <= maxStack then return bag, slot, n end
            end
        end
    end
    for _, bag in ipairs(bags) do
        if FamilyFits(bag, s.id) then
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                if not C_Container.GetContainerItemInfo(bag, slot) and not r.targets[SlotKey(bag, slot)] then return bag, slot, 0 end
            end
        end
    end
end

local function GuildTabInfo(tab)
    if not GetGuildBankTabInfo then return nil end
    local name, _, viewable, canDeposit = GetGuildBankTabInfo(tab)
    return Plain(name), Plain(viewable), Plain(canDeposit)
end

local function GuildNow()
    if not (IsInGuild and IsInGuild()) then return nil end
    return Plain((GetGuildInfo("player")))
end

-- The guild bank shows the tab this destination names, in the guild it was chosen in, and it takes deposits.
-- Returns true, or false, a stop reason and a sentence.
function Run.GuildReady(where)
    if not where then return false, "guild-changed", "Choose the guild bank tab for this destination first." end
    local guild = GuildNow()
    if guild ~= where.guild then
        return false, "guild-changed", ("This tab was chosen in <%s>; you are in %s now. Review the destination."):format(where.guild, guild and ("<" .. guild .. ">") or "no guild")
    end
    local current = GetCurrentGuildBankTab and Plain(GetCurrentGuildBankTab())
    local name, _, canDeposit = GuildTabInfo(where.tab)
    if where.tabName and name and name ~= where.tabName then
        return false, "guild-changed", ("Tab %d is called \"%s\" now, not \"%s\". Review the destination."):format(where.tab, name, where.tabName)
    end
    if current ~= where.tab then
        return false, "tab-changed", ("Show the tab \"%s\" (tab %d) in the guild bank first."):format(where.tabName or name or "?", where.tab)
    end
    if canDeposit ~= true then return false, "no-deposit", "Your guild rank can't deposit in that tab." end
    return true
end

local function GuildSlotItem(tab, slot)
    local texture, count = GetGuildBankItemInfo(tab, slot)
    if Plain(texture) == nil then return nil end
    local link = GetGuildBankItemLink and Plain(GetGuildBankItemLink(tab, slot))
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil, Plain(count) or 0
end

local function GuildTarget(r, tab)
    for slot = 1, GUILD_SLOTS do
        if not r.targets[SlotKey(tab, slot)] and Plain((GetGuildBankItemInfo(tab, slot))) == nil then return tab, slot, 0 end
    end
end

-- Free room at the destination, counted now: slots (and, for the bank, room in stacks of the same item is counted
-- per stack as it is moved). For the review's "room for" line.
function Run.FreeSlots(kind, where)
    local n = 0
    if kind == "bank" then
        for _, bag in ipairs(BankBags()) do n = n + (Plain(C_Container.GetContainerNumFreeSlots(bag)) or 0) end
        return n
    end
    if kind == "guild" and where and GetGuildBankItemInfo then
        for slot = 1, GUILD_SLOTS do if Plain((GetGuildBankItemInfo(where.tab, slot))) == nil then n = n + 1 end end
        return n
    end
end

local DepositNext

local function MoveSettled(r, timedOut)
    local w = r.waiting
    if not w then return end
    local src = MI.ReadSlot(w.s.bag, w.s.slot)
    local srcGone = not (src and src.id == w.s.id and src.count == w.s.count)
    local arrived
    if r.kind == "bank" then
        local info = C_Container.GetContainerItemInfo(w.bag, w.slot)
        arrived = info and Plain(info.itemID) == w.s.id and Plain(info.stackCount) == w.before + w.s.count
    else
        local id, count = GuildSlotItem(w.bag, w.slot)
        arrived = id == w.s.id and count == w.s.count
    end
    if srcGone and arrived then
        r.waiting = nil
        Record(r, "confirmed", w.step)
        r.index = r.index + 1
        Notify("progress")
        return DepositNext(r)
    end
    if not timedOut then return end   -- the game hasn't finished: bag events before then change nothing
    r.waiting = nil
    if srcGone then
        Record(r, "uncertain", w.step, "It left your bags, but the game didn't show where")
        Finish(r, "uncertain")
    else
        Record(r, "failed", w.step, r.error or MI.STOP_TEXT["move-failed"])
        Finish(r, "move-failed")
    end
end

local function OnMoveEvent()
    local r = run
    if r and (r.kind == "bank" or r.kind == "guild") and r.waiting then MoveSettled(r, false) end
end

DepositNext = function(r)
    local ok, why = Valid(r)
    if not ok then Finish(r, why) return end
    if r.kind == "guild" then
        local ready, code = Run.GuildReady(r.where)
        if not ready then Finish(r, code) return end
    end
    local step = r.steps[r.index]
    if not step then Finish(r, "done") return end
    local s, problem = Resolve(r, step)
    if not s then
        if problem == "locked" and LockedRetry(r, step, DepositNext) then return end
        Record(r, "skipped", step, MI.ReasonText(problem))
        r.index = r.index + 1
        return DepositNext(r)
    end
    local bag, slot, before
    if r.kind == "bank" then bag, slot, before = BankTarget(r, s)
    else bag, slot, before = GuildTarget(r, r.where.tab) end
    if not bag then
        for i = r.index, #r.steps do Record(r, "skipped", r.steps[i], "No room left") end
        Finish(r, "full")
        return
    end
    if not CursorFree() then Finish(r, "cursor") return end
    local pt = R.Perf.on and R.Perf.Start("inventory.step")
    if not PickUp(s) then
        if pt then R.Perf.Stop(pt) end
        Record(r, "failed", step, "The game didn't pick it up")
        Finish(r, "move-failed")
        return
    end
    r.used[SlotKey(s.bag, s.slot)] = true
    r.targets[SlotKey(bag, slot)] = true
    if r.kind == "bank" then C_Container.PickupContainerItem(bag, slot) else PickupGuildBankItem(bag, slot) end
    if CursorHasItem and CursorHasItem() then
        PutBack()   -- the destination didn't take it: back to its bag slot
        if pt then R.Perf.Stop(pt) end
        Record(r, "failed", step, MI.STOP_TEXT["move-failed"])
        Finish(r, "move-failed")
        return
    end
    if pt then R.Perf.Stop(pt) end
    token = token + 1
    local t = token
    r.waiting = { step = step, s = s, bag = bag, slot = slot, before = before, token = t }
    Notify("progress")
    C_Timer.After(MOVE_WAIT, function()
        if r == run and r.waiting and r.waiting.token == t then MoveSettled(r, true) end
    end)
end

-- Can this bank or guild bank group be deposited now? true, or false and a sentence.
function Run.CanDeposit(plan, group)
    if not MI.Enabled() then return false, "Magic Inventory is off." end
    if InCombat() then return false, "Wait until combat ends." end
    if not Run.IsOpen(group.kind) then return false, group.kind == "bank" and "Open your bank first." or "Open the guild bank first." end
    if run then return false, "Another transfer is in progress." end
    if plan.generation ~= MI.Generation() then return false, "Your rules changed since this review. Review again." end
    if #(group.steps or {}) == 0 then return false, "Nothing to deposit." end
    if group.kind == "bank" and #BankBags() == 0 then return false, "The game shows no bank tabs to deposit in." end
    if group.kind == "guild" then
        local ok, _, why = Run.GuildReady(group.where)
        if not ok then return false, why end
    end
    if not CursorFree() then return false, "Put down what is on your cursor first." end
    return true
end

-- Deposits a reviewed bank or guild bank group (the player's click), one stack after another. Returns true, or
-- false and a sentence.
function Run.Deposit(plan, group)
    local ok, why = Run.CanDeposit(plan, group)
    if not ok then return false, why end
    local r = { kind = group.kind, plan = plan, group = group, generation = plan.generation, where = group.where,
        steps = group.steps, index = 1, results = NewResults(), used = {}, targets = {}, state = "depositing" }
    run = r
    Want("BAG_UPDATE_DELAYED", OnMoveEvent, true)
    if group.kind == "guild" then Want("GUILDBANKBAGSLOTS_CHANGED", OnMoveEvent, true) end
    Want("UI_ERROR_MESSAGE", OnError, true)
    Want("PLAYER_REGEN_DISABLED", function() if run then Run.Stop("combat") end end, true)
    Want("ADDON_ACTION_BLOCKED", Run.OnBlocked, true)
    Want("ADDON_ACTION_FORBIDDEN", Run.OnBlocked, true)
    Notify("depositing")
    DepositNext(r)
    return true
end

function Run.OnBlocked(addon)
    if Plain(addon) ~= R.ADDON or not run then return end
    if run.waiting then Record(run, "uncertain", run.waiting.step, MI.STOP_TEXT.blocked) end
    run.waiting = nil
    Finish(run, "blocked")
end

---------------------------------------------------------------------------
-- Listening: which interfaces are open, only while the feature is on
---------------------------------------------------------------------------
local function Opened(kind) return function() open[kind] = true; Notify("open:" .. kind) end end
local function Closed(kind)
    return function()
        open[kind] = false
        if run and run.kind == kind then
            if run.waiting then Record(run, "uncertain", run.waiting.step, "The window closed while the game was answering") end
            if run.state == "sending" or run.state == "confirming" then
                for i = 1, AttachMax() do
                    local a = run.attached and run.attached[i]
                    if a then Record(run, "uncertain", a.step, "The mailbox closed before the game answered") end
                end
            end
            run.waiting = nil
            Finish(run, "closed")
        end
        Notify("close:" .. kind)
    end
end
local HANDLERS = {
    MAIL_SHOW = Opened("mail"), MAIL_CLOSED = Closed("mail"),
    BANKFRAME_OPENED = Opened("bank"), BANKFRAME_CLOSED = Closed("bank"),
    GUILDBANKFRAME_OPENED = Opened("guild"), GUILDBANKFRAME_CLOSED = Closed("guild"),
}
local listening = {}
local function OnLeaving()
    open.mail, open.bank, open.guild = false, false, false
    if run then Run.Stop("leaving") end
    Notify("leaving")
end

-- Safe to call any time: listens while the feature is on, and drops everything when it is off.
function MI.Refresh()
    local on = MI.Enabled()
    for event, fn in pairs(HANDLERS) do
        if on and not listening[event] then listening[event] = fn; R:On(event, fn)
        elseif not on and listening[event] then R:Off(event, listening[event]); listening[event] = nil end
    end
    if on and not listening.PLAYER_LEAVING_WORLD then listening.PLAYER_LEAVING_WORLD = OnLeaving; R:On("PLAYER_LEAVING_WORLD", OnLeaving)
    elseif not on and listening.PLAYER_LEAVING_WORLD then R:Off("PLAYER_LEAVING_WORLD", OnLeaving); listening.PLAYER_LEAVING_WORLD = nil end
    if not on then
        open.mail, open.bank, open.guild = false, false, false
        if run then Finish(run, "off") end
    end
    Notify("refresh")
end

-- A change to the rules, destinations or the Never transfer list stops a run between steps (the plan it carries is
-- stale); a mail the game is answering is left to finish first, then the run stops.
MI.OnChange(function()
    local r = run
    if r and r.generation ~= MI.Generation() and r.state ~= "sending" and r.state ~= "confirming" and not r.waiting then
        Finish(r, "changed")
    end
end)

-- Read only, for the diagnostics: how many events this file listens to now.
function Run.ListenerCount()
    local n = 0
    for _ in pairs(active) do n = n + 1 end
    for _ in pairs(listening) do n = n + 1 end
    return n
end

R:OnInit(MI.Refresh)
if R.Profiles and R.Profiles.OnApply then R.Profiles.OnApply("views", "magicInventory", function() MI.Changed() end) end
