-- TwichUI settings: Chat cleaning › Live view (modules/ChatClean.lua). Two parts:
--   * Try a message: a sample you type, judged for a channel you pick by the same checks real messages go through
--     (ChatClean.Test). Nothing is sent to any channel and no chat state changes.
--   * The live list: messages TwichUI hides while this tab is on screen, newest first, each with the time, channel,
--     sender and the filter or rule that hid it.
-- Capture lifecycle, all of it here: ChatClean.SetCapture(fn) is set when this tab is shown (and not paused) and
-- cleared the moment it is hidden: another tab, another page, a search, the window closing. Hiding also forgets
-- everything listed. Pause stops listing (filtering goes on as set); Clear forgets the list. At most MAX_ENTRIES are
-- held, in memory only, as plain text made when each arrives (colors, textures and links removed, so nothing in the
-- list can be clicked or run); nothing is saved, shared or put in a report. Messages are never replayed into chat.
-- Rows are made as needed (at most MAX_ENTRIES) and reused.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.ChatCleanLivePage = P

local W = 644
local MAX_ENTRIES = 100
local ROW_H, VISIBLE = 38, 8
local LIST_TOP = -170
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26

local f, built
local rows = {}
local entries = {}       -- newest first: { time, channel, sender, text, reason } (plain text)
local paused = false
local testKey            -- the channel the tester uses (nil: the first cleaned one)
local refreshQueued = false

local function Wg() return R.SettingsWidgets end
local function CC() return R.ChatClean end
local function Match() return R.ChatCleanMatch end

---------------------------------------------------------------------------
-- Capturing
---------------------------------------------------------------------------
local QueueRefresh

-- Called by ChatClean.lua once per hidden message while capturing. Keeps plain text only.
local function OnHidden(e)
    local M = Match()
    local sender = type(e.sender) == "string" and e.sender or ""
    if Ambiguate then sender = Ambiguate(sender, "none") or sender end
    table.insert(entries, 1, {
        time = date("%H:%M:%S", e.when or time()),
        channel = M.Plain(e.channel or "?"),
        sender = M.Plain(sender),
        text = M.Plain(e.text or ""),
        reason = M.Plain((e.kind == "rule" and "Rule: " or "") .. (e.reason or "")),
    })
    for i = #entries, MAX_ENTRIES + 1, -1 do entries[i] = nil end
    QueueRefresh()
end
P.OnHidden = OnHidden

local function StartCapture()
    if paused then return end
    CC().SetCapture(OnHidden)
end

local function StopCapture()
    CC().SetCapture(nil)
end

function P.Entries() return #entries end
function P.Paused() return paused end

function P.SetPaused(on)
    paused = on and true or false
    if paused then StopCapture() elseif f and f:IsVisible() then StartCapture() end
    P.Refresh()
end

function P.Clear()
    wipe(entries)
    P.Refresh()
end

---------------------------------------------------------------------------
-- Trying a message
---------------------------------------------------------------------------
local function TestChoices()
    local out = {}
    for _, ch in ipairs(CC().KnownChannels()) do
        local e = ch.choice
        out[#out + 1] = { value = ch.key, label = Match().Plain(ch.label) .. ((e and e.on) and "" or "  (not cleaned)") }
    end
    return out
end

local function DefaultKey()
    local first
    for _, ch in ipairs(CC().KnownChannels()) do
        first = first or ch.key
        if ch.choice and ch.choice.on then return ch.key end
    end
    return first
end

-- Judges the sample in the box and says the result. Returns the result (ChatClean.Test's).
function P.Test(text)
    local key = testKey or DefaultKey()
    local G = Wg()
    local pal = G.pal
    text = text or (f and f.sample:GetText()) or ""
    local say, tone
    local result = { hidden = false }
    if text:match("^%s*$") then
        say = "Type a message to try."
    elseif not key then
        say = "There are no channels to try it in yet. Join one, or choose channels on the Channels tab."
    else
        result = CC().Test(text, key)
        local where = Match().Plain(CC().ChannelLabel(key))
        if not result.cleaned then
            say = ("Would be shown: TwichUI doesn't clean %s. Tick it on the Channels tab to clean it."):format(where)
        elseif result.hidden then
            local by = Match().Plain((result.kind == "rule" and "your rule " or "") .. (result.reason or ""))
            if result.enabled then
                say, tone = ("Would be hidden in %s, by %s."):format(where, by), "hidden"
            else
                say, tone = ("Would be hidden in %s by %s once chat cleaning is on (it is off now, so nothing is hidden)."):format(where, by), "hidden"
            end
        else
            say, tone = ("Would be shown in %s: no filter or rule matches."):format(where), "shown"
        end
    end
    P.lastResult = say
    if f and f.result then
        f.result:SetText(say)
        G.Color(f.result, tone == "hidden" and pal.danger.text or (tone == "shown" and pal.tealHi or pal.textDim))
    end
    return result, say
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------
local function Row(i)
    if rows[i] then return rows[i] end
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row:EnableMouse(true)
    row.bg = G.Solid(row, "BACKGROUND", pal.text, (i % 2 == 0) and 0.035 or 0)
    row.bg:SetAllPoints()
    row.head = G.Text(row, "meta")
    row.head:SetPoint("TOPLEFT", 8, -4)
    row.head:SetWidth(LIST_W - 16)
    row.head:SetWordWrap(false)
    row.text = G.Text(row, "small")
    row.text:SetPoint("TOPLEFT", 8, -20)
    row.text:SetWidth(LIST_W - 16)
    row.text:SetWordWrap(false)
    I.Tip(row, nil, function(self)
        local e = self.entry
        if not e then return nil end
        return ("%s · %s · %s\n%s\n\nHidden by: %s"):format(e.time, e.channel, e.sender ~= "" and e.sender or "?", e.text, e.reason)
    end)
    rows[i] = row
    return row
end

local function StateText()
    if not CC().Enabled() then return "Chat cleaning is off, so nothing is being hidden. Turn it on in General to see what it would hide.", "warn" end
    if not CC().Active() then return "No channel has a filter or rule chosen, so nothing is being hidden.", "warn" end
    if paused then return "Paused: messages are still hidden as set, but not listed here. Resume to list them again.", nil end
    return "These messages were hidden by TwichUI while this view was open. Leaving this view clears them; nothing is kept.", nil
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local G = Wg()
    local pal = G.pal
    for i, e in ipairs(entries) do
        local row = Row(i)
        row.entry = e
        row.head:SetText(("%s  ·  %s  ·  %s  ·  %s"):format(e.time, e.channel, e.sender ~= "" and e.sender or "?", e.reason))
        row.text:SetText(e.text)
        row:Show()
    end
    for i = #entries + 1, #rows do
        rows[i].entry = nil
        rows[i].head:SetText(""); rows[i].text:SetText("")
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, #entries * ROW_H))
    f.empty:SetShown(#entries == 0)
    local state, tone = StateText()
    f.state:SetText(state)
    G.Color(f.state, tone == "warn" and pal.danger.text or pal.textDim)
    f.pause:SetText(paused and "Resume" or "Pause")
    f.count:SetText(("%d of %d"):format(#entries, MAX_ENTRIES))
    local key = testKey or DefaultKey()
    f.channel:SetValue(key, key and Match().Plain(CC().ChannelLabel(key)) or "No channels")
end

QueueRefresh = function()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        P.Refresh()
    end)
end

local function Build()
    built = true
    local G, I = Wg(), R.Interact

    -- trying a message
    G.Card(f, 0, 0, W, -118)
    local title = G.Text(f, "heading")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Try a message")
    f.sample = G.EditBox(f, W - 24 - 180 - 96 - 16, 22)
    f.sample:SetPoint("TOPLEFT", 12, -32)
    f.sample:SetMaxLetters(255)
    f.sample:SetScript("OnEnterPressed", function(self) P.Test(self:GetText()) end)
    f.sample:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    I.Tip(f.sample, "Sample message", "Type or paste a message as it might appear in chat. It is only checked here; nothing is sent.")
    f.channel = G.Dropdown(f, 180, function(value)
        testKey = value
        P.Refresh()
    end)
    f.channel:SetChoices(TestChoices)
    f.channel:SetPoint("TOPLEFT", W - 12 - 96 - 8 - 180, -32)
    I.Tip(f.channel, "Channel", "Which channel's filters and rules to try it against.")
    f.test = G.Button(f, "Try it", 96, "secondary", function() P.Test(f.sample:GetText()) end)
    f.test:SetPoint("TOPRIGHT", -12, -32)
    f.result = G.Text(f, "small")
    f.result:SetPoint("TOPLEFT", 12, -62)
    f.result:SetWidth(W - 24)
    f.result:SetText(P.lastResult or "")
    local how = G.Text(f, "meta")
    how:SetPoint("TOPLEFT", 12, -92)
    how:SetWidth(W - 24)
    how:SetText("The same checks as real messages, for a message from a stranger. Repeats can't be judged from one sample.")

    -- the live list
    local heading = G.Text(f, "heading")
    heading:SetPoint("TOPLEFT", 4, -130)
    heading:SetText("Hidden while this view is open")
    f.count = G.Text(f, "meta")
    f.count:SetPoint("TOPLEFT", 260, -132)
    f.pause = G.Button(f, "Pause", 90, "secondary", function() P.SetPaused(not paused) end)
    f.pause:SetPoint("TOPRIGHT", -88, -126)
    I.Tip(f.pause, "Pause or resume", "Pause stops listing new hidden messages here. Filtering goes on exactly as set.")
    f.clear = G.Button(f, "Clear", 80, "secondary", P.Clear)
    f.clear:SetPoint("TOPRIGHT", -2, -126)
    I.Tip(f.clear, "Clear", "Forgets the messages listed here. They stay hidden in chat; nothing is brought back.")
    f.state = G.Text(f, "small")
    f.state:SetPoint("TOPLEFT", 4, -152)
    f.state:SetWidth(W - 8)
    f.state:SetWordWrap(false)
    f.well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.well:SetPoint("TOPLEFT", 0, LIST_TOP)
    f.well:SetSize(W, LIST_H)
    G.Well(f.well)
    f.scroll, f.content = G.Scroll(f.well, LIST_W)
    f.scroll:SetPoint("TOPLEFT", 6, -4)
    f.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    f.empty = G.Text(f.well, "small")
    f.empty:SetPoint("TOPLEFT", 12, -14)
    f.empty:SetWidth(W - 24)
    f.empty:SetText("Nothing hidden since this view opened. Messages TwichUI hides appear here as they arrive.")
    local foot = G.Text(f, "meta")
    foot:SetPoint("TOPLEFT", 4, LIST_TOP - LIST_H - 8)
    foot:SetWidth(W - 8)
    foot:SetText("Only TwichUI's own decisions are listed; messages another addon hides can't be seen here. A rule you change applies to new messages; hidden ones can't be brought back.")
end

-- The page's frame (the settings window shows it under Chat cleaning). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function()
        if not built then Build() end
        wipe(entries)
        paused = false
        StartCapture()
        P.Refresh()
    end)
    f:SetScript("OnHide", function()
        StopCapture()
        wipe(entries)
        for _, row in ipairs(rows) do
            row.entry = nil
            row.head:SetText(""); row.text:SetText("")
        end
        if f.sample then f.sample:ClearFocus() end
    end)
    return f
end

-- A change made anywhere (the switch, a channel, a rule, a profile change) redraws the state line if it is shown.
if R.ChatClean then R.ChatClean.OnChange(function() if QueueRefresh then QueueRefresh() end end) end

K.Page({
    key = "chatCleanLive", name = "Chat cleaning live view", nav = "Live view", parent = "chatClean", order = 38,
    description = "Messages TwichUI hides while this view is open, and a place to try a message against your rules.",
    keywords = "chat live view hidden filtered messages log test try sample tester check",
    when = function() return R.ChatClean ~= nil end,
    host = function() return P.Frame() end,
})
