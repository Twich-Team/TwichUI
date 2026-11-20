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
        local done, failed, pending, progress = 0, 0, 0, 0
        for _, o in ipairs(outs) do
            progress = progress + (RS.TERMINAL[o.stage] and 1 or ((o.total or 0) > 0 and (o.sent or 0) / o.total or 0))
            if o.stage == "done" then done = done + 1
            elseif RS.TERMINAL[o.stage] then failed = failed + 1
            else pending = pending + 1 end
        end
        rows[#rows + 1] = {
            text = ("\"%s\" to %d players: %d have it, %d waiting, %d not sent"):format(outs[1].name, #outs, done, pending, failed),
            frac = progress / #outs,
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
-- Choosing the recipient. The picker is built once, only on a Share click.
---------------------------------------------------------------------------
local picker
local function BuildPicker()
    local F = R.FrameLook
    picker = CreateFrame("Frame", "TwichUIReminderSharePicker", UIParent)
    UI.picker = picker
    picker:SetSize(460, 300)
    picker:SetPoint("CENTER")
    picker:SetFrameStrata("DIALOG")
    picker:SetToplevel(true)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker.shell = F.Shell(picker, { below = true })
    picker.shell:Header(34)
    if R.CraftLook then R.CraftLook.Window(picker, picker.shell, { header = 34 }) end   -- the crafted settings family (CraftLook.lua)
    F.Close(picker, function() picker:Hide() end):SetPoint("TOPRIGHT", -14, -12)
    tinsert(UISpecialFrames, "TwichUIReminderSharePicker")
    local function Text(font, x, y, width)
        local t = picker:CreateFontString(nil, "OVERLAY", font)
        t:SetPoint("TOPLEFT", x, y)
        t:SetWidth(width)
        t:SetJustifyH("LEFT")
        return t
    end
    Text("GameFontNormalLarge", 20, -18, 380):SetText("Share a reminder")
    picker.name = Text("GameFontHighlight", 20, -58, 420)
    Text("GameFontHighlightSmall", 20, -88, 420):SetText("Each player is asked first. The reminder arrives turned off, ready to view and enable in Reminders.")
    Text("GameFontNormal", 20, -130, 420):SetText("Player name")
    picker.player = R.Look.EditBox(picker, 280, 26)
    picker.player:SetPoint("TOPLEFT", 20, -150)
    picker.player:SetAutoFocus(false)
    local function Go(who)
        local id, say = picker.id, picker.say
        local ok, text = RS.Send(id, who)
        say(text, ok and "ok" or "warn")
        if ok then picker:Hide() else picker.status:SetText(text) end
    end
    picker.send = F.Button(picker, "Share", 116, "primary", function() Go(picker.player:GetText()) end)
    picker.send:SetPoint("TOPLEFT", 314, -150)
    picker.group = F.Button(picker, "My group", 196, "secondary", function() Go(RS.GROUP) end)
    picker.group:SetPoint("TOPLEFT", 20, -194)
    picker.guild = F.Button(picker, "My guild", 196, "secondary", function() Go(RS.GUILD) end)
    picker.guild:SetPoint("TOPRIGHT", -20, -194)
    picker.status = Text("GameFontHighlightSmall", 20, -234, 420)
    picker.player:SetScript("OnEnterPressed", function() Go(picker.player:GetText()) end)
    picker.player:SetScript("OnEscapePressed", function() picker:Hide() end)
    picker:SetScript("OnHide", function() picker.id, picker.say = nil, nil; picker.player:ClearFocus() end)
end

function UI.Ask(id, say)
    say = say or function(text) R.Print("%s", text) end
    local v = RM.Get(id)
    if not v then return end
    local exported, why = RM.Export(id)
    if not exported then say(why, "warn") return end
    if not picker then BuildPicker() end
    picker.id, picker.say = id, say
    picker.name:SetText(v.name)
    picker.status:SetText("Player uses your Sending options. My group uses the group channel; My guild uses the guild channel for online members.")
    local name = UnitIsPlayer and UnitIsPlayer("target") and GetUnitName("target", true) or ""
    if issecretvalue and issecretvalue(name) then name = "" end
    picker.player:SetText(type(name) == "string" and name or "")
    picker:Show()
    R.FrameLook.FadeIn(picker)
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
