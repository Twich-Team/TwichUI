-- TwichUI: Magic Inventory, the review and the interface buttons
-- A small "Magic Inventory" button on the mailbox, the bank and the guild bank (only while the feature is on and that
-- window is open) says how many stacks your rules would move there. Clicking it opens the review: exactly what would
-- move, to which recipient or tab, the rule, the keep amount, what stays and why, what another rule has reserved, and
-- what needs attention. Entries can be left out of this one operation (the rule is unchanged). Then the player acts:
--   mail:        "Prepare mail 1 of 2 to Bankalt" attaches; "Send mail 1 of 2 to Bankalt" sends (one recipient a mail);
--   bank, guild: "Deposit 8 stacks" moves them one after another;
--   bank:        "Withdraw 3 stacks" takes what rules that withdraw top your bags up with (never past their targets).
-- Opening an interface only builds the count; nothing moves, nothing is announced, and the review never opens by
-- itself. The window is built the first time it is shown and reuses its rows. Drawn with the shared framed look (FrameLook.lua):
-- the illustrated frame, an espresso interior, ivory text, beveled buttons with chestnut for the one primary action, and amber for
-- what needs a look.

local R = TwichUI
local MI = R.MagicInventory
local Run = MI.Run
local W = {}
MI.Window = W

local NAME = "TwichUIMagicInventory"
local WIDTH, HEIGHT, HEADER, PAD = 560, 560, 44, 16
local CONTENT_W = WIDTH - PAD * 2 - 6 - 26   -- the list, inside its well and beside the scroll bar
local FOOT = 74
local ICON = 26
local QUESTION = [[Interface\Icons\INV_Misc_QuestionMark]]
local AMBER = { 0.93, 0.72, 0.38 }
local MAX_RESULT_LINES = 8

local f
local rows, used = {}, 0
local plan, context, leftOut = nil, nil, {}
local manual, choosingRule, bankDetails, bankDismissed
local refreshQueued = false
local buttons = {}           -- the interface buttons, by kind (made the first time each interface opens)
local counts = {}            -- the count each button shows, by kind (worked out when the interface opens or bags change)
local countQueued = {}

local function Look() return R.Look end

local function Money(copper)
    if type(copper) ~= "number" then return "?" end
    local RS = R.Restock
    if RS and RS.ColorMoney then return RS.ColorMoney(copper) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function Plural(n, one, many) return ("%d %s"):format(n, n == 1 and one or (many or one .. "s")) end

local function ItemName(facts, id)
    local name = facts and facts.name or ("item " .. tostring(id))
    local q = facts and facts.quality
    if type(q) == "number" and C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(q)
        if type(r) == "number" then return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name) end
    end
    return name
end

local function DestText(g)
    if g.kind == "mail" then return ("Send by mail to %s"):format(g.where and g.where.recipient or "?") end
    if g.kind == "bank" and g.dir == "withdraw" then return "Withdraw from your bank" end
    if g.kind == "bank" then return "Deposit in your bank" end
    local w = g.where
    return w and ("Deposit in the guild bank of <%s>, tab %d \"%s\""):format(w.guild, w.tab, w.tabName or "?") or "Deposit in the guild bank"
end

---------------------------------------------------------------------------
-- What the action of a group says and does now
---------------------------------------------------------------------------
-- Returns label, enabled, why (a sentence when disabled), onClick.
local function Action(g, forPlan)
    local cur = Run.Current()
    if not context then return "Open a " .. (g.kind == "mail" and "mailbox" or (g.kind == "bank" and "bank" or "guild bank")) .. " to move these", false, "This is a preview: nothing moves from here." end
    if g.kind == "mail" then
        local n = #g.batches
        if cur and cur.kind == "mail" and cur.group == g then
            local i = cur.batchIndex
            if cur.state == "attaching" then return ("Preparing mail %d of %d..."):format(i, n), false end
            if cur.state == "ready" then
                local label = ("Send mail %d of %d to %s"):format(i, n, g.where.recipient)
                return label, true, nil, function()
                    local ok, why = Run.SendPrepared()
                    if not ok and why then W.Say(why, "warn") end
                end
            end
            if cur.state == "sending" then return "Waiting for the game...", false end
            if cur.state == "confirming" then return "Answer the game's confirmation", false, "The game asks you to confirm sending items to this player. Magic Inventory waits for your answer there." end
            if cur.state == "between" then
                return ("Prepare mail %d of %d to %s"):format(i, n, g.where.recipient), true, nil, function()
                    local ok, why = Run.PrepareMail(forPlan, g)
                    if not ok and why then W.Say(why, "warn") end
                end
            end
        end
        local ok, why = Run.CanPrepare(forPlan, g)
        return ("Prepare mail 1 of %d to %s"):format(n, g.where.recipient), ok, why, function()
            local done, err = Run.PrepareMail(forPlan, g)
            if not done and err then W.Say(err, "warn") end
        end
    end
    local out = g.dir == "withdraw"
    if cur and cur.group == g then
        return ("%s stack %d of %d..."):format(out and "Withdrawing" or "Depositing", math.min(cur.index, #g.steps), #g.steps), false
    end
    local ok, why = Run.CanDeposit(forPlan, g)
    return ("%s %s"):format(out and "Withdraw" or "Deposit", Plural(#g.steps, "stack")), ok, why, function()
        local done, err = Run.Deposit(forPlan, g)
        if not done and err then W.Say(err, "warn") end
    end
end

---------------------------------------------------------------------------
-- Rows: one pool, reused on every draw
---------------------------------------------------------------------------
local function Row(i)
    local row = rows[i]
    if row then return row end
    local L = Look()
    row = CreateFrame("Button", nil, f.content)
    row:SetHeight(20)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("TOPLEFT", 4, -4)
    row.title = L.Text(row, "body")
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(true)
    row.meta = L.Text(row, "small")
    row.meta:SetJustifyH("LEFT")
    row.meta:SetWordWrap(true)
    row:SetScript("OnEnter", function(self)
        if self.link or self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(self.link)
            elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

-- A row's buttons are made the first time the row needs one (an item row has a toggle, a heading an action), and kept.
local function RowButton(row, key, label, w, kind)
    local b = row[key]
    if not b then
        b = R.FrameLook.Button(row, label, w, kind, function(self) if self.onClick then self.onClick() end end)
        b:SetPoint("TOPRIGHT", -4, -6)
        row[key] = b
    end
    b:SetWidth(w)
    b:ClearAllPoints(); b:SetPoint("TOPRIGHT", -4, -6)
    if context == "bank" and R.CraftLook then R.CraftLook.Dress(b, "secondary") end
    return b
end

local y
local function Place(row, h)
    row:SetHeight(h)
    y = y + h
end

local function Reset(row)
    row.link, row.itemID = nil, nil
    row.icon:Hide()
    row.icon:SetSize(ICON, ICON)
    row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", 4, -4)
    if row.toggle then row.toggle:Hide(); row.toggle.onClick = nil end
    if row.action then row.action:Hide(); row.action.onClick = nil end
    if row.withdrawAll then row.withdrawAll:Hide(); row.withdrawAll.onClick = nil end
    if row.face then row.face:SetShown(false); row.face.rim:SetShown(false) end
    row.title:ClearAllPoints(); row.meta:ClearAllPoints()
    row.title:SetText(""); row.meta:SetText("")
    row.title:SetWordWrap(true); row.meta:SetWordWrap(true)
    Look().Color(row.title, Look().pal.text)
    Look().Color(row.meta, Look().pal.textDim)
end

local function Next()
    used = used + 1
    local row = Row(used)
    Reset(row)
    -- placed first: text is measured as the row is filled
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
    row:SetWidth(CONTENT_W)
    row:Show()
    return row
end

-- A heading: bronze text, an optional sentence, an optional action on the right.
local function Heading(text, sentence, actionLabel, enabled, why, onClick)
    local L = Look()
    local row = Next()
    local right = actionLabel and (context == "bank" and 144 or 250) or 4
    row.title:SetPoint("TOPLEFT", 4, -8)
    row.title:SetWidth(CONTENT_W - right - 4)
    row.title:SetText(text)
    L.Color(row.title, L.pal.bronzeText)
    local top = 14 + math.max(14, row.title:GetStringHeight() or 14)
    local h = top
    row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
    row.meta:SetWidth(CONTENT_W - right - 4)
    if sentence and sentence ~= "" then
        row.meta:SetText(sentence)
        h = h + math.max(14, row.meta:GetStringHeight() or 14) + 4
    end
    if actionLabel then
        local action = RowButton(row, "action", "", context == "bank" and 132 or 240, "primary")
        action:SetWidth(context == "bank" and 132 or 240)
        action.text:SetText(actionLabel)
        action:SetEnabled(enabled and true or false)
        action.onClick = enabled and onClick or nil
        action:Show()
        if why then
            R.Interact.Tip(action, actionLabel, why)
            h = math.max(h, 36)
        else
            R.Interact.Tip(action, actionLabel, nil)
        end
        if not enabled and why then
            row.meta:SetText((sentence and sentence ~= "" and (sentence .. "\n") or "") .. why)
            L.Color(row.meta, AMBER)
            h = top + math.max(14, row.meta:GetStringHeight() or 14) + 6
        end
    end
    Place(row, h + 4)
    return row
end

-- An item: icon, name and count, a line of detail, and optionally the Leave out / Include toggle.
local function ItemRow(id, facts, count, detail, tone, toggle)
    local L = Look()
    local row = Next()
    row.itemID, row.link = id, facts and facts.link
    row.icon:SetTexture(facts and facts.icon or QUESTION)
    row.icon:Show()
    local right = toggle and 104 or 4
    local width = CONTENT_W - right - (4 + ICON + 8)
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.title:SetWidth(width)
    row.title:SetText(count and ("%s  |cffb8b2a6x%d|r"):format(ItemName(facts, id), count) or ItemName(facts, id))
    row.meta:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.meta:SetWidth(width)
    row.meta:SetText(detail or "")
    if tone == "warn" then L.Color(row.meta, AMBER) elseif tone == "quiet" then L.Color(row.meta, L.pal.stone) end
    if toggle then
        local b = RowButton(row, "toggle", "Leave out", 96, "secondary")
        b.text:SetText(toggle.label)
        b.onClick = toggle.onClick
        b:SetEnabled(toggle.enabled ~= false)
        b:Show()
    end
    Place(row, math.max(ICON + 10, (row.title:GetStringHeight() or 14) + (row.meta:GetStringHeight() or 12) + 12))
    return row
end

local function Line(text, tone)
    local L = Look()
    local row = Next()
    row.title:SetPoint("TOPLEFT", 4, -2)
    row.title:SetWidth(CONTENT_W - 8)
    row.title:SetText(text)
    if tone == "warn" then L.Color(row.title, AMBER) elseif tone == "quiet" then L.Color(row.title, L.pal.textDim) end
    Place(row, math.max(18, (row.title:GetStringHeight() or 14) + 6))
end

local function Gap(h) y = y + (h or 8) end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local CONTEXT_TITLE = { mail = "At the mailbox", bank = "At your bank", guild = "At the guild bank" }

local function EntryDetail(e)
    if e.target then
        -- a withdrawal: what it tops up to, and what it can't reach
        local text = ("%s  \194\183  rule \"%s\"  \194\183  you carry %d, target %d"):format(Plural(e.stacks, "stack"), e.rule, e.carried, e.target)
        if e.short then text = text .. ("\n%d short after this: %s."):format(e.short, e.shortWhy or "") end
        return text
    end
    local parts = { Plural(e.stacks, "stack"), ("rule \"%s\""):format(e.rule) }
    if e.keep > 0 then parts[#parts + 1] = ("keeps %d of %d carried"):format(e.keep, e.carried) end
    local text = table.concat(parts, "  \194\183  ")
    if e.extraKept then text = text .. ("\n%d more than the keep amount stay: only whole stacks move."):format(e.extraKept) end
    return text
end

local function DrawResults(r)
    local res = r.results
    local total = #res.confirmed + #res.failed + #res.skipped + #res.uncertain
    if total == 0 and r.stopReason == "done" then return end
    Gap(6)
    local verb = r.kind == "mail" and "sent" or (r.dir == "mixed" and "moved" or (r.dir == "withdraw" and "withdrawn" or "deposited"))
    Heading("Last transfer", ("%d %s and confirmed by the game  \194\183  %d didn't move  \194\183  %d skipped  \194\183  %d not confirmed"):format(
        #res.confirmed, verb, #res.failed, #res.skipped, #res.uncertain))
    if r.stopReason and r.stopReason ~= "done" then
        Line(("Stopped: %s. What was done stays done; nothing can be undone from here."):format(MI.STOP_TEXT[r.stopReason] or r.stopReason), "warn")
    end
    local shown = 0
    for _, status in ipairs({ "uncertain", "failed", "skipped" }) do
        for _, e in ipairs(res[status]) do
            if shown >= MAX_RESULT_LINES then break end
            shown = shown + 1
            local label = status == "uncertain" and "Not confirmed" or (status == "failed" and "Didn't move" or "Skipped")
            ItemRow(e.id, e.facts, e.count, label .. (e.why and (": " .. e.why) or ""), status == "skipped" and "quiet" or "warn")
        end
    end
    local more = #res.uncertain + #res.failed + #res.skipped - shown
    if more > 0 then Line(("and %d more."):format(more), "quiet") end
end

-- The character bank has one compact review and one batch action. Details stay available on demand.
local function BankFace(row)
    local C = R.CraftLook
    if C then
        row.face = row.face or C.PanelFace(row, "walnut")
        row.face:SetShown(true); row.face.rim:SetShown(true)
        C.Font(row.title, 14, true, "strong")
        C.Font(row.meta, 12)
    end
end

local function DrawBank(cur)
    local L = Look()
    local rules = MI.Rules()
    local ruleById = {}
    for _, rule in ipairs(rules) do ruleById[rule.id] = rule end
    local selected = manual and ruleById[manual.ruleId]
    f.title:SetText("Magic Inventory")
    f.sub:Hide(); f.bankSummary:Show()
    f.box:ClearAllPoints()
    f.box:SetPoint("TOPLEFT", PAD, -(HEADER + 78))
    f.box:SetPoint("BOTTOMRIGHT", -PAD, FOOT + 32)
    local totals, balanced = { deposit = 0, withdraw = 0 }, {}
    for _, g in ipairs(plan and plan.groups or {}) do
        if g.kind == "bank" then
            local dir = g.dir or "deposit"
            totals[dir] = totals[dir] + g.items
            for _, e in ipairs(g.entries) do
                local rule = ruleById[e.ruleId]
                if not e.leftOut and rule and rule.flow == "balance" then balanced[rule.id] = true end
            end
        end
    end
    local n = 0
    for _ in pairs(balanced) do n = n + 1 end
    f.bankSummary.deposit.value:SetText(Plural(totals.deposit, "item"))
    f.bankSummary.withdraw.value:SetText(Plural(totals.withdraw, "item"))
    f.bankSummary.balance.value:SetText(Plural(n, "rule"))
    local title = selected and ((manual.dir == "withdraw" and "Withdraw all" or "Deposit all") .. " · " .. selected.name) or "Your bank"
    Heading(title, nil, manual and "Use rules" or (choosingRule and "Back" or "Rule actions"), not cur, nil, function()
        if manual then manual, leftOut = nil, {} else choosingRule = not choosingRule end
        bankDetails = false; bankDismissed = Run.Last(); W.said = nil; W.Refresh()
    end)
    if choosingRule and not cur then
        local found = false
        for _, rule in ipairs(rules) do
            if rule.kind == "bank" then
                found = true
                local row = Next()
                BankFace(row)
                row.title:SetPoint("TOPLEFT", 10, -10); row.title:SetWidth(CONTENT_W - 230)
                row.title:SetWordWrap(false); row.title:SetText(rule.name)
                row.meta:SetPoint("TOPLEFT", 10, -30); row.meta:SetWidth(CONTENT_W - 230)
                row.meta:SetText(rule.enabled and "Rule is on" or "Manual use · rule is off")
                for _, dir in ipairs({ "deposit", "withdraw" }) do
                    local key = dir == "deposit" and "action" or "withdrawAll"
                    local label = dir == "deposit" and "Deposit all" or "Withdraw all"
                    local b = RowButton(row, key, label, 102, "secondary")
                    b:ClearAllPoints(); b:SetPoint("TOPRIGHT", dir == "deposit" and -114 or -6, -14)
                    b.text:SetText(label); b:SetEnabled(MI.Enabled()); b:Show()
                    b.onClick = function()
                        manual = { ruleId = rule.id, dir = dir }; leftOut = {}; choosingRule = false; bankDetails = false; bankDismissed = Run.Last()
                        W.said = nil; W.Refresh()
                    end
                    R.Interact.Tip(b, label, "Review matching items for this rule only. Its usual target is ignored for this visit; saved rules stay unchanged. Never transfer and item protections still apply. Other Keep in bags rules and restocking targets still protect deposits.")
                    if R.CraftLook then R.CraftLook.Dress(b, "secondary") end
                end
                Place(row, 58); Gap(4)
            end
        end
        if not found then Line("No bank rules yet. Choose Manage rules to create one.", "quiet") end
    else
        local any = false
        for _, g in ipairs(plan and plan.groups or {}) do
            if g.kind == "bank" then
                for _, e in ipairs(g.entries) do
                    any = true
                    local out = g.dir == "withdraw"
                    local after = e.carried + (out and e.count or -e.count)
                    local detail = e.leftOut and "Left out this time" or ((out and "Withdraw " or "Deposit ") .. e.count .. " · Bags " .. e.carried .. " → " .. after)
                    local startY = y
                    local row = ItemRow(e.id, e.facts, nil, detail, e.leftOut and "quiet" or nil, not cur and {
                        label = e.leftOut and "Include" or "Leave out", onClick = function()
                            leftOut[e.key] = not e.leftOut or nil; W.Refresh()
                        end } or nil)
                    BankFace(row)
                    row.icon:SetSize(32, 32); row.icon:ClearAllPoints(); row.icon:SetPoint("TOPLEFT", 10, -10)
                    row.title:ClearAllPoints(); row.title:SetPoint("TOPLEFT", 50, -9); row.title:SetWidth(CONTENT_W - 160)
                    row.title:SetWordWrap(false)
                    row.meta:ClearAllPoints(); row.meta:SetPoint("TOPLEFT", 50, -29); row.meta:SetWidth(CONTENT_W - 160)
                    row.meta:SetWordWrap(false)
                    row:SetHeight(54); y = startY + 54
                    if row.toggle then row.toggle:ClearAllPoints(); row.toggle:SetPoint("TOPRIGHT", -8, -14) end
                    Gap(5)
                end
            end
        end
        if not any then Heading("Nothing to move", manual and "No eligible matching items here." or "Your bags and bank are ready.") end
        local issues = #(plan and plan.attention or {}) + #(plan and plan.skipped or {}) + #(plan and plan.reserved or {})
        Heading(issues > 0 and Plural(issues, "item or rule", "items or rules") .. " staying put" or "Transfer details", nil,
            bankDetails and "Hide details" or "Details", true, nil, function() bankDetails = not bankDetails; W.Refresh() end)
        if bankDetails and plan then
            for _, a in ipairs(plan.attention) do Line(a.rule .. ": " .. a.why, "warn") end
            for _, e in ipairs(plan.skipped) do ItemRow(e.id, e.facts, nil, e.text, "quiet") end
            for _, e in ipairs(plan.reserved) do ItemRow(e.id, e.facts, nil, "Reserved by " .. e.rule, "quiet") end
            for _, g in ipairs(plan.groups) do for _, e in ipairs(g.entries) do
                Line(e.rule .. (e.short and (": " .. e.short .. " short · " .. (e.shortWhy or "")) or ""), "quiet")
            end end
            local last = Run.Last()
            if last and last.kind == "bank" and last ~= bankDismissed and not cur then DrawResults(last) end
        end
    end
    local ok, why = Run.CanBank(plan)
    f.bankGo:SetShown(not cur and not choosingRule)
    f.bankGo:SetEnabled(ok and MI.Enabled())
    f.bankGo.text:SetText(manual and (manual.dir == "withdraw" and "Withdraw all" or "Deposit all") or "Run rules")
    f.bankGo.onClick = function()
        local done, err = Run.Bank(plan)
        if not done then W.Say(err, "warn") end
    end
    R.Interact.Tip(f.bankGo, "Run bank transfers", why or "Carries out this review: deposits first, then withdrawals. Stop ends the batch; completed transfers stay done.")
    local autoSort = MI.BankAutoSort()
    f.bankAutoSort:SetOn(autoSort)
    f.bankAutoSort.text:SetText(autoSort and "Auto-sort: On" or "Auto-sort: Off")
    f.bankAutoSort:SetShown(not choosingRule)
    f.bankAutoSort:SetEnabled(not cur and MI.Enabled())
    f.stop:SetShown(cur ~= nil)
    f.again:SetEnabled(not cur); f.manage:SetEnabled(not cur)
    local prog = Run.BankProgress()
    if not cur and Run.Last() == bankDismissed then prog = nil end
    f.bankProgress:SetShown(prog ~= nil)
    local status = "Review the items, then run when ready."
    if choosingRule then status = "Choose a rule and an action to review."
    elseif manual then status = "One visit only · saved rule unchanged" end
    if prog then
        local frac = prog.total > 0 and prog.confirmed / prog.total or 0
        f.bankProgress.fill:SetWidth(math.max(1, (WIDTH - PAD * 2 - 4) * frac))
        f.bankProgress.fill:SetShown(frac > 0)
        f.bankProgress.text:SetText(prog.confirmed .. " / " .. prog.total .. " moves confirmed")
        if prog.active then
            local step = prog.step
            status = (prog.dir == "withdraw" and "Withdrawing" or "Depositing") .. (step and (" · " .. ItemName(step.entry.facts, step.id)) or "…")
        else
            local missed = prog.failed + prog.skipped + prog.uncertain
            status = prog.reason == "done" and (missed == 0 and "Completed" or "Completed with items left out")
                or ("Stopped · " .. (MI.STOP_TEXT[prog.reason] or prog.reason or ""))
            if prog.uncertain > 0 then status = status .. " · Check unconfirmed moves in Details" end
        end
    end
    if not MI.Enabled() then status = "Magic Inventory is off." end
    f.status:SetText(W.said or status)
    L.Color(f.status, W.saidTone == "warn" and AMBER or L.pal.textDim)
    for i = used + 1, #rows do rows[i]:Hide() end
    f.content:SetHeight(math.max(1, y + 6))
end

local function Draw()
    if not (f and f:IsShown()) then return end
    local L = Look()
    used, y = 0, 4
    local cur = Run.Current()
    if not cur then
        plan = MI.CurrentPlan(context, leftOut, context == "bank" and manual or nil)
        if not plan then manual = nil; plan = MI.CurrentPlan(context, leftOut) end
    end
    if context == "bank" then DrawBank(cur); return end
    f.bankSummary:Hide(); f.bankGo:Hide(); f.bankAutoSort:Hide(); f.bankProgress:Hide(); f.sub:Show()
    f.again:SetEnabled(not cur); f.manage:SetEnabled(true)
    f.box:ClearAllPoints(); f.box:SetPoint("TOPLEFT", PAD, -(HEADER + 30)); f.box:SetPoint("BOTTOMRIGHT", -PAD, FOOT)
    f.sub:SetText(context and CONTEXT_TITLE[context] or "Preview: what your rules would move, from your bags as they are now. Nothing moves from here.")

    if not MI.Enabled() then
        Line("Magic Inventory is off. Turn it on in the settings to use it at a mailbox or bank.", "warn")
    end
    -- what needs attention first
    if plan and #plan.attention > 0 then
        Heading("Needs attention", "These rules match items here but can't run until you look at them.")
        for _, a in ipairs(plan.attention) do Line(("\"%s\": %s"):format(a.rule, a.why), "warn") end
        Gap()
    end
    if context == "mail" and not cur then
        local draft = Run.MailDraft()
        if draft then Line(draft, "warn") Gap() end
    end

    local any = false
    for _, g in ipairs(plan and plan.groups or {}) do
        any = true
        local label, enabled, why, onClick = Action(g, plan)   -- the action acts on the plan drawn here
        local sentence
        if g.kind == "mail" then
            sentence = ("%s  \194\183  %s  \194\183  one recipient per mail"):format(Plural(g.stacks, "stack"), Plural(g.mails, "mail"))
            if cur and cur.group == g and cur.state == "ready" and cur.price then
                sentence = sentence .. ("\nPostage for this mail: %s (the game's figure for what is attached)."):format(Money(cur.price))
            else
                sentence = sentence .. "\nPostage: the game shows it when a mail is prepared. No money is sent and C.O.D. is never used."
            end
            if cur and cur.group == g and cur.note then sentence = sentence .. "\n" .. cur.note end
        else
            local out = g.dir == "withdraw"
            local free = Run.IsOpen(g.kind) and Run.FreeSlots(out and "bags" or g.kind, g.where)
            sentence = Plural(g.stacks, "stack") .. (free and ("  \194\183  %d free %s %s"):format(free, free == 1 and "slot" or "slots", out and "in your bags" or "there") or "")
            if out then sentence = sentence .. "\nStacks are split when needed, never past a rule's target." end
            if free and free < g.stacks then sentence = sentence .. "\nNot all of these fit: it stops when the room runs out." end
        end
        Heading(DestText(g), sentence, label, enabled, why, onClick)
        for _, e in ipairs(g.entries) do
            local toggle
            if not cur then
                toggle = { label = e.leftOut and "Include" or "Leave out", onClick = function()
                    leftOut[e.key] = (not e.leftOut) or nil
                    W.Refresh()
                end }
            end
            ItemRow(e.id, e.facts, e.count, e.leftOut and "Left out this time (your rule is unchanged)" or EntryDetail(e),
                e.leftOut and "quiet" or nil, toggle)
        end
        Gap()
    end

    if not any then
        Gap(4)
        local where = context and ({ mail = "to mail from here", bank = "to deposit in or withdraw from your bank", guild = "to deposit in this guild bank" })[context] or "to move"
        Heading("Nothing " .. where, #MI.Rules() == 0 and "You haven't made any rules yet. Manage rules opens them in the settings."
            or "None of your rules that are on match what you carry, or what they match stays for the reasons below.")
    end

    if plan and #plan.reserved > 0 then
        Heading("Reserved by other rules", "These match a rule higher in your list that moves them somewhere else. They aren't moved from here; change the order to change that.")
        for _, e in ipairs(plan.reserved) do
            ItemRow(e.id, e.facts, e.count, ("Reserved by \"%s\" (%s)"):format(e.rule, MI.KIND_LABEL[e.kind]:lower()), "quiet")
        end
        Gap()
    end
    for _, out in ipairs({ false, true }) do
        local list = {}
        for _, e in ipairs(plan and plan.skipped or {}) do if (e.withdraw == true) == out then list[#list + 1] = e end end
        if #list > 0 then
            if out then Heading("Not withdrawn", "A rule would top these up from your bank, but they stay there: the reason is beside each.")
            else Heading("Staying in your bags", "Matched by a rule, but kept: the reason is beside each.") end
            for _, e in ipairs(list) do
                ItemRow(e.id, e.facts, (e.count or 0) > 0 and e.count or nil, e.text .. (e.rule and ("  \194\183  rule \"" .. e.rule .. "\"") or ""), (e.reason == "attention" or e.reason == "pending") and "warn" or "quiet")
            end
            Gap()
        end
    end
    if plan and #plan.shadowed > 0 then
        Heading("Shadowed rules", "Also match these items, but a rule above them in your list goes first.")
        for _, e in ipairs(plan.shadowed) do
            ItemRow(e.id, e.facts, nil, ("\"%s\" is shadowed by \"%s\""):format(e.rule, e.by), "quiet")
        end
    end
    local last = Run.Last()
    if last and not cur and last.kind == context then DrawResults(last) end

    for i = used + 1, #rows do rows[i]:Hide() end
    f.content:SetHeight(math.max(1, y + 6))

    -- the footer: what is happening, Stop while a run is on
    local status
    if cur then
        if cur.kind == "mail" then
            status = ({ attaching = "Preparing the mail in the game's Send Mail window...", ready = "Prepared. Check the game's Send Mail window, then press Send here.",
                sending = "Sending: waiting for the game.", confirming = "The game asks you to confirm. Answer it there.",
                between = ("Mail %d of %d sent. Prepare the next when you are ready."):format(cur.batchIndex - 1, #cur.group.batches) })[cur.state] or ""
        else
            status = ("%s stack %d of %d. Stop ends it before the next stack."):format(cur.dir == "withdraw" and "Withdrawing" or "Depositing", math.min(cur.index, #cur.steps), #cur.steps)
        end
    elseif plan then
        status = plan.stacks > 0 and ("%s reviewed. Nothing moves until you press an action above."):format(Plural(plan.stacks, "stack")) or ""
    end
    f.status:SetText(W.said or status or "")
    L.Color(f.status, W.saidTone == "warn" and AMBER or L.pal.textDim)
    f.stop:SetShown(cur ~= nil)
end

function W.Refresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        local ok, err = pcall(Draw)
        if not ok then R.Fault("magic inventory window", err) end
    end)
end

-- A sentence in the footer until the next change (a refused action and why).
function W.Say(text, tone)
    W.said, W.saidTone = text, tone
    W.Refresh()
end

local function Build()
    local L, F = Look(), R.FrameLook
    if not (L and L.Text and L.ScrollBar and F and F.Ready()) then return false end
    local _, _, CR = F.ContentInsets()
    local RL, RT, RR = F.RailInsets()
    f = CreateFrame("Frame", NAME, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 260, 40)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, NAME)   -- Esc closes it (a run in progress goes on; Stop stops it)
    f.shell = F.Shell(f, { below = true, follow = true })        -- the shared frame and interior (FrameLook.lua), under everything below
    F.FadeIn(f)
    f:HookScript("OnShow", R.FitToScreen)
    local head = CreateFrame("Frame", nil, f)      -- the header: title and close box over the shell's sheen and groove
    head:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    head:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    head:SetHeight(HEADER)
    f.shell:Sheen():Place(head, RL, RT, RR, 0)
    f.shell:Groove():Place(head, "BOTTOM", 0, RL, RR)
    f.title = L.Text(head, "title")
    f.title:SetPoint("TOPLEFT", PAD, -14)
    f.title:SetText("Magic Inventory")
    f.close = F.Close(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -(CR + 2), -12)
    f.sub = L.Text(f, "small")
    f.sub:SetPoint("TOPLEFT", PAD, -(HEADER + 10))
    f.sub:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.sub:SetJustifyH("LEFT")

    local box = CreateFrame("Frame", nil, f)
    f.box = box
    box:SetPoint("TOPLEFT", PAD, -(HEADER + 30))
    box:SetPoint("BOTTOMRIGHT", -PAD, FOOT)
    f.shell:Recess():Place(box, 0, 0, 0, 0)        -- the list sits in a recess, a step deeper than the interior
    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    if L.ScrollBar then L.ScrollBar(scroll) end
    f.content = CreateFrame("Frame", nil, scroll)
    f.content:SetSize(WIDTH - PAD * 2 - 6 - 26, 1)
    scroll:SetScrollChild(f.content)

    f.status = L.Text(f, "small")
    f.status:SetPoint("BOTTOMLEFT", PAD, 46)
    f.status:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
    f.status:SetJustifyH("LEFT")
    f.stop = F.Button(f, "Stop", 90, "danger", function()
        Run.Stop("stopped")
    end)
    f.stop:SetPoint("BOTTOMLEFT", PAD, 16)
    R.Interact.Tip(f.stop, "Stop", "Stops before the next step. What was already sent, deposited or withdrawn stays where it went: none of it is undone.")
    f.manage = F.Button(f, "Manage rules", 120, "secondary", function()
        if R.OpenSettings then R:OpenSettings("magicInventory") end
    end)
    f.manage:SetPoint("BOTTOMRIGHT", -PAD, 16)
    f.again = F.Button(f, "Review again", 120, "secondary", function()
        W.said = nil
        if not Run.Current() then leftOut = {}; bankDismissed = Run.Last() end
        W.Refresh()
    end)
    f.again:SetPoint("RIGHT", f.manage, "LEFT", -8, 0)
    R.Interact.Tip(f.again, "Review again", "Looks at your bags again and includes everything you left out. Nothing moves.")

    -- Approved crafted materials shared with the rule workspace; no dependency on the settings addon.
    local C = R.CraftLook
    if C then
        if f.shell.grain then f.shell.grain:Hide() end
        C.Tile(f.shell, "BACKGROUND", -4, "dark", 1, { .90, .94, .98 }):SetAllPoints(f.shell.interior)
        C.QuietTile(f.shell, "outer", "BACKGROUND", -3):SetAllPoints(f.shell.interior)
        C.LegacyRails(f.shell, false); f.craftedFrame = C.Frame(f.shell)
        C.Font(f.title, 23, true, "serif")
        for _, button in ipairs({ f.stop, f.manage, f.again }) do C.Dress(button, button == f.stop and "danger" or "secondary") end
    end
    f.bankGo = F.Button(f, "Run rules", 132, "primary", function(self) if self.onClick then self.onClick() end end)
    f.bankGo:SetPoint("BOTTOMLEFT", PAD, 16); f.bankGo:Hide()
    if C then C.Dress(f.bankGo, "confirmation") end
    f.bankAutoSort = F.Toggle(f, "Auto-sort: On", 132, function()
        MI.SetBankAutoSort(not MI.BankAutoSort())
        W.Refresh()
    end)
    f.bankAutoSort:SetPoint("LEFT", f.bankGo, "RIGHT", 8, 0)
    f.bankAutoSort:Hide()
    R.Interact.Tip(f.bankAutoSort, "Auto-sort bags and bank",
        "Sorts your bags and character bank after a bank transfer finishes. This choice is saved across reloads.")
    f.bankSummary = CreateFrame("Frame", nil, f)
    f.bankSummary:SetPoint("TOPLEFT", PAD, -(HEADER + 10)); f.bankSummary:SetSize(WIDTH - PAD * 2, 56)
    for i, dir in ipairs({ "deposit", "withdraw", "balance" }) do
        local card = CreateFrame("Frame", nil, f.bankSummary)
        card:SetSize((WIDTH - PAD * 2 - 12) / 3, 54); card:SetPoint("TOPLEFT", (i - 1) * ((WIDTH - PAD * 2 - 12) / 3 + 6), 0)
        if C then card.face = C.PanelFace(card, "walnut") end
        local icon = card:CreateTexture(nil, "ARTWORK"); icon:SetSize(30, 30); icon:SetPoint("LEFT", 8, 0)
        icon:SetTexture(R.PATH .. (dir == "balance" and [[media\npcs\balance-scales-small]] or [[media\guides\status-current-small]]))
        if dir ~= "balance" then icon:SetRotation(dir == "withdraw" and math.pi / 2 or -math.pi / 2) end
        card.label = L.Text(card, "small"); card.label:SetPoint("TOPLEFT", 44, -8)
        card.label:SetWidth(card:GetWidth() - 50)
        card.label:SetText(({ deposit = "Deposit", withdraw = "Withdraw", balance = "Balance" })[dir])
        card.value = L.Text(card, "body"); card.value:SetPoint("TOPLEFT", 44, -28); card.value:SetWidth(card:GetWidth() - 50)
        if C then C.Font(card.label, 13); C.Font(card.value, 14, true, "strong") end
        f.bankSummary[dir] = card
    end
    f.bankSummary:Hide()
    f.bankProgress = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.bankProgress:SetPoint("BOTTOMLEFT", PAD, 76); f.bankProgress:SetSize(WIDTH - PAD * 2, 20)
    L.Surface(f.bankProgress, L.pal.well, 1, L.pal.bronzeLo, .9)
    f.bankProgress.fill = f.bankProgress:CreateTexture(nil, "ARTWORK")
    f.bankProgress.fill:SetPoint("TOPLEFT", 2, -2); f.bankProgress.fill:SetPoint("BOTTOMLEFT", 2, 2)
    -- Keep ivory progress text legible over both the well and the filled run.
    f.bankProgress.fill:SetColorTexture(L.pal.tealLo[1], L.pal.tealLo[2], L.pal.tealLo[3], .9)
    f.bankProgress.text = L.Text(f.bankProgress, "small", "OVERLAY")
    L.Color(f.bankProgress.text, L.pal.text)
    f.bankProgress.text:SetPoint("CENTER", 0, 0)
    f.bankProgress:Hide()

    -- hooked, not set: the shell's fade and the fit to the screen are hooks of the same scripts
    f:HookScript("OnShow", function() W.said = nil; W.Refresh() end)
    f:HookScript("OnHide", function() W.said = nil; GameTooltip:Hide() end)
    return true
end

-- Opens the review for the interface that is open (or, from the settings, a preview of everything). Never called by
-- an interface opening.
function W.Show(asPreview)
    if not (f or Build()) then R.Print("the Magic Inventory window isn't available right now.") return end
    local now = Run.OpenKind()
    local newContext = (not asPreview) and now or nil
    if newContext ~= context then leftOut, manual, choosingRule, bankDetails = {}, nil, false, false end
    if newContext ~= context then bankDismissed = Run.Last() end
    context = newContext
    f:Show()
    f:Raise()
    W.Refresh()
end

function W.Toggle()
    if f and f:IsShown() then f:Hide() else W.Show() end
end

function W.IsShown() return f ~= nil and f:IsShown() end
function W.Hide() if f then f:Hide() end end
function W.Plan() return plan end
function W.Context() return context end
function W.RowCount() return #rows end

---------------------------------------------------------------------------
-- The interface buttons: "Magic Inventory · 8 stacks". Made the first time each interface opens with the feature on,
-- shown only while it is open. Placed just outside the interface's window (above its top right corner) so it covers
-- none of the game's controls.
---------------------------------------------------------------------------
local F_HEIGHT   -- the button's natural height, restored when it leaves a skinned window
local HOSTS = { mail = "MailFrame", bank = "BankFrame", guild = "GuildBankFrame" }

local function ButtonText(kind)
    local n = counts[kind]
    if type(n) == "table" then
        if n.stacks > 0 then return ("Magic Inventory \194\183 %s"):format(Plural(n.stacks, "stack")) end
        if n.attention > 0 then return "Magic Inventory \194\183 needs a look" end
    end
    return "Magic Inventory"
end

-- The label sits right of the icon, left aligned. The crafted button (CraftLook.Control) re-anchors its text on every state
-- change, so this runs again after each one (see InterfaceButton).
local function PlaceLabel(b, dy)
    b.text:ClearAllPoints()
    b.text:SetJustifyH("LEFT")
    if b.icon then b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, dy or 0)
    else b.text:SetPoint("CENTER", 0, dy or 0) end
end

-- Sets the label and sizes the button to it (the icon, the text and an even margin).
local function SetLabel(b, kind)
    b.text:SetText(ButtonText(kind))
    local pad = b.icon and 40 or 24
    local w = math.ceil(b.text:GetStringWidth() or 120)
    b.text:SetWidth(w + 2)
    b:SetWidth(w + pad)
    PlaceLabel(b)
end

-- With EllesmereUI the interface windows are restyled (mailbox: its Blizzard skin) or replaced (bank: EllesmereUI Bags draws
-- its own window, EUI_BankFrame, and leaves Blizzard's hidden). The button then belongs to that window, so it shows, hides,
-- scales and stacks with it, and is placed against it rather than floating:
--   * mailbox: centred in the quiet band between the title and the list;
--   * bank: in the header, in the empty stretch between the title and the sort / search controls.
-- Without EllesmereUI the placement is unchanged.
local function AddonLoaded(name)
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
    return (loaded and loaded(name)) and true or false
end

local function Shown(frame) return type(frame) == "table" and frame.IsShown and frame:IsShown() end

-- The window to place against, and how: "band", "header" (both belong to the window) or nil (unchanged placement)
local function HostFor(kind)
    local euiBank = kind == "bank" and _G.EUI_BankFrame
    if Shown(euiBank) then return euiBank, "header" end
    local host = _G[HOSTS[kind]]
    if kind == "mail" and Shown(host) and AddonLoaded("EllesmereUIBlizzardSkin") then return host, "band" end
    return host, nil
end

local EMBED_HEIGHT, BAND_TOP = 22, -22
local BANK_HEADER_X, BANK_HEADER_Y = -62, -18   -- the empty stretch of EllesmereUI's bank header, from the window's top centre

local function Anchor(b, kind)
    b:ClearAllPoints()
    local host, how = HostFor(kind)
    if how then
        b:SetParent(host)
        b:SetFrameStrata(host:GetFrameStrata() or "HIGH")
        b:SetFrameLevel((host:GetFrameLevel() or 0) + 20)
        b.embedded = true
        if how == "band" then
            b:SetHeight(EMBED_HEIGHT)
            b:SetPoint("TOP", host, "TOP", 0, BAND_TOP)
        else
            b:SetHeight(EMBED_HEIGHT)
            b:SetPoint("CENTER", host, "TOP", BANK_HEADER_X, BANK_HEADER_Y)
        end
        return
    end
    if b.embedded then
        b.embedded = nil
        b:SetParent(UIParent)
        b:SetFrameStrata("HIGH")
        if F_HEIGHT then b:SetHeight(F_HEIGHT) end
    end
    if Shown(host) then
        b:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 4)
    else
        -- another addon draws this interface (a bag addon's bank, for one): a quiet place at the top of the screen
        b:SetPoint("TOP", UIParent, "TOP", 0, -110)
    end
end

local function InterfaceButton(kind)
    local b = buttons[kind]
    if b then return b end
    local F = R.FrameLook
    if not (F and F.Button) then return nil end
    b = F.Button(UIParent, "Magic Inventory", 190, "secondary", function() W.Toggle() end)
    b:SetFrameStrata("HIGH")
    b:Hide()
    F_HEIGHT = b:GetHeight()
    -- the settings dialog's crafted button (CraftLook), as the review window's own buttons
    if R.CraftLook and R.CraftLook.Dress then R.CraftLook.Dress(b, "secondary") end
    if R.Icons and R.Icons.Apply then
        -- the feature's own icon (the settings page's), left of the label
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", 8, 0)
        R.Icons.Apply(b.icon, "magicInventory", 18)
        b.icon:SetDrawLayer("OVERLAY", 7)
        -- the crafted button puts its label back on every hover, press and enable change, so it is placed again after
        for _, script in ipairs({ "OnEnter", "OnLeave", "OnMouseUp", "OnEnable", "OnDisable" }) do
            b:HookScript(script, function() PlaceLabel(b) end)
        end
        b:HookScript("OnMouseDown", function() if b:IsEnabled() then PlaceLabel(b, -1) end end)
    end
    R.Interact.Tip(b, "Magic Inventory", function()
        local n = counts[kind]
        local lines = "Opens the review of what your rules would move here. Nothing moves until you press an action there."
        if type(n) == "table" and n.groups and #n.groups > 0 then
            local parts = {}
            for _, g in ipairs(n.groups) do parts[#parts + 1] = g end
            lines = table.concat(parts, "\n") .. "\n\n" .. lines
        end
        return lines
    end)
    buttons[kind] = b
    return b
end

local UpdateButtons   -- (below) shows, places and hides the buttons

-- Works out the count for an open interface (a plan, read only). The game's own window may appear a moment after
-- the event that says the interface opened, so the buttons are shown and placed again here too.
local function Count(kind)
    countQueued[kind] = false
    UpdateButtons()
    if kind == "guild" and MI.GuildPanel then return end   -- the guild bank has its own panel (GuildPanel.lua)
    if not (MI.Enabled() and Run.IsOpen(kind)) then return end
    local p = MI.CurrentPlan(kind)
    local groups = {}
    for _, g in ipairs(p.groups) do
        if g.kind == "mail" then groups[#groups + 1] = ("%s: %s"):format(g.where.recipient, Plural(g.stacks, "stack"))
        else groups[#groups + 1] = ("%s: %s"):format(g.kind == "bank" and (g.dir == "withdraw" and "From the bank" or "Bank") or ("Guild tab \"" .. (g.where and g.where.tabName or "?") .. "\""), Plural(g.stacks, "stack")) end
    end
    counts[kind] = { stacks = p.stacks, attention = #p.attention, groups = groups }
    local b = buttons[kind]
    if b then SetLabel(b, kind) end
end

local function QueueCount(kind, delay)
    if countQueued[kind] then return end
    countQueued[kind] = true
    C_Timer.After(delay or 0.3, function()
        local ok, err = pcall(Count, kind)
        if not ok then countQueued[kind] = false; R.Fault("magic inventory count", err) end
    end)
end

local bagListening = false
local function OnBags()
    for kind in pairs(HOSTS) do
        if Run.IsOpen(kind) and not Run.Current() then QueueCount(kind, 0.5) end
    end
    if f and f:IsShown() and not Run.Current() then W.Refresh() end
end
local function ListenBags(on)
    if on and not bagListening then bagListening = true; R:On("BAG_UPDATE_DELAYED", OnBags)
    elseif not on and bagListening then bagListening = false; R:Off("BAG_UPDATE_DELAYED", OnBags) end
end

local hooked = {}
-- The game's window can close without the event that says so being the last word (or be another addon's window), so
-- the button also follows the window itself.
local function HookHost(kind)
    local host = _G[HOSTS[kind]]
    if hooked[kind] or type(host) ~= "table" or not host.HookScript then return end
    hooked[kind] = true
    host:HookScript("OnHide", function() UpdateButtons() end)
end

UpdateButtons = function()
    local anyOpen = false
    for kind in pairs(HOSTS) do HookHost(kind) end
    for kind in pairs(HOSTS) do
        local isOpen = MI.Enabled() and Run.IsOpen(kind) and not (kind == "guild" and MI.GuildPanel)
        anyOpen = anyOpen or isOpen
        if isOpen then
            local b = InterfaceButton(kind)
            if b then
                Anchor(b, kind)
                SetLabel(b, kind)
                b:Show()
            end
        elseif buttons[kind] then
            buttons[kind]:Hide()
            counts[kind] = nil
        end
    end
    ListenBags(anyOpen)
    if not anyOpen and f and f:IsShown() and context then f:Hide() end
end

Run.OnUpdate(function(what)
    if type(what) == "string" then
        local kind = what:match("^open:(%a+)$")
        if kind then QueueCount(kind, 0.3) end
        if what == "close:bank" or what == "leaving" or (what == "refresh" and not MI.Enabled()) then
            manual, choosingRule, bankDetails, leftOut = nil, false, false, {}
            bankDismissed = Run.Last()
        end
        if what:find("^close:") or what == "leaving" or what == "refresh" then
            local closed = what:match("^close:(%a+)$")
            if closed and f and f:IsShown() and context == closed then f:Hide() end
        end
        if what == "finished" then
            for k in pairs(HOSTS) do if Run.IsOpen(k) then QueueCount(k, 0.5) end end
        end
    end
    UpdateButtons()
    if f and f:IsShown() then
        if what ~= "progress" then W.said = nil end
        W.Refresh()
    end
end)

MI.OnChange(function()
    for kind in pairs(HOSTS) do if Run.IsOpen(kind) then QueueCount(kind, 0.1) end end
    if f and f:IsShown() then W.Refresh() end
end)

-- Read only, for the diagnostics and the tests: frames this file has made.
function W.FrameCount()
    local n = (f and 1 or 0) + #rows
    for _ in pairs(buttons) do n = n + 1 end
    return n
end

if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge("inventory.frames", { label = "Magic Inventory frames (review rows and interface buttons)", unit = "count", kind = "pool",
        read = function() return W.FrameCount() end })
    R.Perf.Gauge("inventory.listeners", { label = "Magic Inventory event listeners", unit = "count", kind = "listeners",
        read = function() return Run.ListenerCount() + (bagListening and 1 or 0) end })
    R.Perf.Gauge("inventory.itemCache", { label = "Magic Inventory item facts remembered", unit = "count", kind = "cache",
        read = function() return MI.ItemCacheSize() end })
end
