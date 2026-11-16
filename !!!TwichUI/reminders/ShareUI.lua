-- TwichUI: Reminders, what sharing shows
-- Two things, both only because the player shared a reminder or accepted one: a small card with a progress bar for each
-- transfer (the sender's and the receiver's), and, once a reminder has arrived, one question about opening the Reminders
-- settings to look at it and turn it on. The card appears when a transfer starts and goes a few seconds after the last one
-- ends; it is never there otherwise. reminders/Share.lua owns the transfers; this only draws them.

local R = TwichUI
local RM = R.Reminders
local RS = R.ReminderShare

local UI = {}
R.ReminderShareUI = UI

local WIDTH, ROW_H, MAX_ROWS = 340, 36, 4
local SHOW_FINISHED = 6          -- seconds a finished transfer stays on the card
local RED = "|cffd9604f"

local card

---------------------------------------------------------------------------
-- What the card says: rows, built from the transfers (pure; the tests read these)
---------------------------------------------------------------------------
local function Percent(frac) return math.floor(math.min(1, math.max(0, frac or 0)) * 100 + 0.5) end

local function Visible(t)
    if not RS.TERMINAL[t.stage] then return true end
    return t.ended ~= nil and GetTime() - t.ended < SHOW_FINISHED
end

local function OutText(o)
    local who, name = RS.Short(o.target), o.name
    local frac = (o.total or 0) > 0 and (o.sent or 0) / o.total or 0
    if o.stage == "offered" then return ("Waiting for %s to accept \"%s\"..."):format(who, name), 0
    elseif o.stage == "sending" or o.stage == "delivered" then
        return ("Sending \"%s\" to %s: %d%%"):format(name, who, Percent(frac)), frac
    elseif o.stage == "done" then return ("%s has \"%s\"."):format(who, name), 1
    end
    return RED .. (o.reason or "It wasn't sent.") .. "|r", 0, true
end

local function InText(sender, inc)
    local who = RS.Short(sender)
    if inc.stage == "waiting" or inc.stage == "receiving" or inc.stage == "checking" then
        local frac = (inc.expected or 0) > 0 and (inc.got or 0) / inc.expected or 0
        return ("Receiving \"%s\" from %s: %d%%"):format(inc.name, who, Percent(frac)), frac
    elseif inc.stage == "done" then
        return ("Added \"%s\" from %s. It is off until you turn it on."):format(inc.name, who), 1
    end
    return RED .. (inc.reason or "It wasn't received.") .. "|r", 0, true
end

-- { { text, frac, bad }, ... } for the card. A group send of more than three players is one summary line.
function UI.Rows()
    local rows = {}
    local outs = {}
    for _, o in ipairs(RS.out) do if Visible(o) then outs[#outs + 1] = o end end
    if #outs > 3 then
        local done, failed, pending = 0, 0, 0
        for _, o in ipairs(outs) do
            if o.stage == "done" then done = done + 1
            elseif RS.TERMINAL[o.stage] then failed = failed + 1
            else pending = pending + 1 end
        end
        rows[#rows + 1] = {
            text = ("\"%s\" to %d players: %d have it, %d waiting, %d not sent"):format(outs[1].name, #outs, done, pending, failed),
            frac = (done + failed) / #outs,
        }
    else
        for _, o in ipairs(outs) do
            local text, frac, bad = OutText(o)
            rows[#rows + 1] = { text = text, frac = frac, bad = bad }
        end
    end
    local senders = {}
    for sender, inc in pairs(RS.inc) do
        if inc.stage ~= "asking" and inc.stage ~= "declined" and Visible(inc) then senders[#senders + 1] = sender end
    end
    table.sort(senders)
    for _, sender in ipairs(senders) do
        local text, frac, bad = InText(sender, RS.inc[sender])
        rows[#rows + 1] = { text = text, frac = frac, bad = bad, newId = RS.inc[sender].newId }
    end
    return rows
end

---------------------------------------------------------------------------
-- The card
---------------------------------------------------------------------------
local function Build()
    local L = R.Look
    card = CreateFrame("Button", "TwichUIReminderShareCard", UIParent, "BackdropTemplate")
    card:SetSize(WIDTH, 40)
    card:SetPoint("TOP", 0, -200)
    card:SetFrameStrata("DIALOG")
    card:SetClampedToScreen(true)
    if L and L.Surface and L.pal then
        L.Surface(card, L.pal.band, 0.97, L.pal.bronze, 0.85)
        if L.Recess then L.Recess(card, 0.6) end
    end
    card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    card.rows = {}
    card:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            for _, o in ipairs(RS.out) do if o.stage == "offered" then RS.Cancel(o) end end
            return
        end
        for _, row in ipairs(self.shown or {}) do
            if row.newId then UI.Open(row.newId) return end
        end
    end)
    if R.Interact and R.Interact.Tip then
        R.Interact.Tip(card, "Shared reminders", "Click to open Reminders once one has arrived. Right-click to cancel offers nobody has answered yet.")
    end
    card:Hide()
end

local function Row(i)
    if card.rows[i] then return card.rows[i] end
    local L = R.Look
    local row = {}
    row.text = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.bar = CreateFrame("StatusBar", nil, card, "BackdropTemplate")
    row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetHeight(6)
    local c = L and L.pal and L.pal.teal or { 0.8, 0.65, 0.36 }
    row.bar:SetStatusBarColor(c[1], c[2], c[3])
    if L and L.Well then L.Well(row.bar, 1) end
    card.rows[i] = row
    return row
end

local scheduled = false
function UI.Update()
    local rows = UI.Rows()
    if #rows == 0 then
        if card then card:Hide() end
        return
    end
    if not card then Build() end
    if #rows > MAX_ROWS then
        local more = #rows - (MAX_ROWS - 1)
        for i = #rows, MAX_ROWS, -1 do rows[i] = nil end
        rows[MAX_ROWS] = { text = ("and %d more"):format(more), frac = 0 }
    end
    card.shown = rows
    for i, spec in ipairs(rows) do
        local row = Row(i)
        local top = -8 - (i - 1) * ROW_H
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", card, "TOPLEFT", 12, top)
        row.text:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        row.text:SetText(spec.text)
        row.bar:ClearAllPoints()
        row.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 12, top - 17)
        row.bar:SetPoint("RIGHT", card, "RIGHT", -12, 0)
        row.bar:SetValue(spec.frac or 0)
        row.text:Show()
        row.bar:SetShown(not spec.bad)
    end
    for i = #rows + 1, #card.rows do card.rows[i].text:Hide(); card.rows[i].bar:Hide() end
    card:SetHeight(12 + #rows * ROW_H - 6)
    card:Show()
    -- finished transfers leave the card on their own
    if not scheduled then
        scheduled = true
        C_Timer.After(SHOW_FINISHED + 0.2, function() scheduled = false; UI.Update() end)
    end
end
RS:OnChange(UI.Update)

---------------------------------------------------------------------------
-- Asking who to share with: a name (your target's, when it is a player, is filled in) or your group
---------------------------------------------------------------------------
-- say(text, tone) is where the answer goes (the Reminders page's line under the reminder's name).
function UI.Ask(id, say)
    say = say or function(text) R.Print("%s", text) end
    local v = RM.Get(id)
    if not v then return end
    local exported, why = RM.Export(id)
    if not exported then say(why, "warn") return end   -- a reminder that can't be sent says so before a name is asked for
    local function Go(who)
        local ok, text = RS.Send(id, who)
        say(text, ok and "ok" or "warn")
    end
    StaticPopupDialogs.TWICHUI_REMINDER_SHARE = {
        text = "%s", button1 = "Share", button2 = CANCEL, button3 = "My group", hasEditBox = true, maxLetters = 64,
        OnShow = function(self)
            local box = self.editBox or self.EditBox
            if not box then return end
            local name = UnitIsPlayer and UnitIsPlayer("target") and GetUnitName("target", true) or ""
            if issecretvalue and issecretvalue(name) then name = "" end
            box:SetText(type(name) == "string" and name or "")
            box:HighlightText()
        end,
        OnAccept = function(self)
            local box = self.editBox or self.EditBox
            local name = box and box:GetText()
            C_Timer.After(0, function() Go(name) end)   -- after this popup has gone
        end,
        OnAlt = function() C_Timer.After(0, function() Go(RS.GROUP) end) end,
        EditBoxOnEnterPressed = function(box)
            local name = box:GetText()
            box:GetParent():Hide()
            C_Timer.After(0, function() Go(name) end)
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("TWICHUI_REMINDER_SHARE", ("Share \"%s\" with which player?\n\nType their name, or choose My group to offer it to everyone else in your party or raid (up to %d). Each is asked first; nothing is added unless they accept."):format(v.name, RS.MAX_GROUP))
end

---------------------------------------------------------------------------
-- After it arrives: one question, never during combat
---------------------------------------------------------------------------
function UI.Open(id)
    if not R:OpenSettings("reminders") then return end
    local page = R.RemindersPage
    if id and page and page.Select and RM.Get(id) then
        local ok, err = pcall(page.Select, id)
        if not ok then R.Fault("reminders share", err) end
    end
end

local waiting   -- { sender, inc }: arrived while in combat

local function Ask(sender, inc)
    local text = ("%s's reminder \"%s\" arrived. It was added to your reminders turned off, and limited to this character.\n\nOpen the Reminders settings to look at it and turn it on?"):format(RS.Short(sender), inc.name)
    R.Interact.Confirm("TWICHUI_REMINDER_ARRIVED", text, function() UI.Open(inc.newId) end, { accept = "Open Reminders", cancel = "Later" })
end

RS:OnArrived(function(sender, inc)
    if InCombatLockdown() then waiting = { sender, inc } return end
    Ask(sender, inc)
end)

R:On("PLAYER_REGEN_ENABLED", function()
    local w = waiting
    waiting = nil
    if w then Ask(w[1], w[2]) end
end)
