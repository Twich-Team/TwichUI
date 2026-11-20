-- TwichUI settings: Chat cleaning › Channels (modules/ChatClean.lua). One compact row per channel: its name, Clean on/off
-- and a summary of the built-in filters and custom rules that apply; Filters opens one channel's filter choices at a time. The channels are the ones you are in now
-- (from the client) and the ones you chose before; a channel you left keeps its choice for when you are back. A frame
-- of this window's own, shown as the tab's page, since a grid of checkboxes doesn't fit the ordinary rows. Built the
-- first time it is shown; rows are made as they are first needed and reused on every redraw. While it is shown it
-- listens for the channel list changing (joining, leaving, a new zone), and stops when it is hidden. Every change goes
-- through ChatClean.lua's own functions.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.ChatCleanChannelsPage = P

local W = 644                  -- the width the page is first built at; it follows the hosted frame's width after that
local ROW_H = 56
local LIST_TOP = -50
local LIST_H = 400
local CAT_W, CAT_H = 190, 27

local f, built
local rows = {}
local refreshQueued = false
local openKey                  -- the one channel whose filters are shown (session only, never saved)

local function Wg() return R.SettingsWidgets end
local function CC() return R.ChatClean end
local function Width() return math.max(480, (f and f:GetWidth() and f:GetWidth() > 1) and f:GetWidth() or W) end
local function ListW() return Width() - 12 - 26 end

function P.Say(text, tone)
    P.lastSaid, P.lastTone = text, tone
    if not (f and f.note) then return end
    local pal = Wg().pal
    f.note:SetText(text or "")
    Wg().Color(f.note, tone == "warn" and pal.danger.text or (tone == "ok" and pal.sage or pal.textDim))
end

-- How many enabled custom rules apply in a channel.
local function RulesFor(key, rules)
    local n = 0
    for _, rule in ipairs(rules) do
        if rule.enabled and (rule.all or rule.channels[key]) then n = n + 1 end
    end
    return n
end

-- The filters a channel uses, in words: "Spam, Repeats · 2 custom rules", "Off", "On · no built-in filters".
function P.FilterSummary(choice, ruleCount)
    local e = choice or {}
    local names = {}
    for _, c in ipairs(CC().CATEGORIES) do if e[c.key] then names[#names + 1] = c.short or c.label end end
    local rules = ruleCount == 1 and "1 custom rule" or ("%d custom rules"):format(ruleCount or 0)
    if not e.on then return "Off" .. ((ruleCount or 0) > 0 and (" · " .. rules .. " wait") or "") end
    return (#names > 0 and table.concat(names, ", ") or "No built-in filters") .. " · " .. rules
end

local function Set(row, field, value)
    if not row.ch then return end
    local ok, why = CC().SetChannel(row.ch.key, field, value, row.ch.label)
    if not ok and why == "full" then P.Say(("TwichUI keeps choices for at most %d channels."):format(CC().MAX_CHANNELS), "warn") end
end

local function Row(i)
    if rows[i] then return rows[i] end
    local G, I = Wg(), R.Interact
    local pal = G.pal
    local row = CreateFrame("Frame", nil, f.content)
    row:SetSize(ListW(), ROW_H)
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 8, -6)
    row.name:SetWordWrap(false)
    row.status = G.Text(row, "meta")
    row.status:SetPoint("TOPLEFT", 8, -26)
    row.status:SetWordWrap(true)
    row.summary = G.Text(row, "small")
    row.summary:SetJustifyH("LEFT")
    row.summary:SetWordWrap(true)

    row.clean = G.Checkbox(row, function(on) Set(row, "on", on) end)
    row.cleanLabel = G.Text(row, "small")
    row.cleanLabel:SetPoint("RIGHT", row.clean, "LEFT", -8, 0)
    row.cleanLabel:SetText("Clean")
    I.Tip(row.clean, "Clean this channel", function()
        return "On: TwichUI checks messages in this channel against the filters chosen for it and the custom rules that apply here. Off: the channel is left alone; its choices are kept."
    end)
    row.toggle = G.Button(row, "Filters", 96, "secondary", function()
        if not row.ch then return end
        openKey = openKey ~= row.ch.key and row.ch.key or nil
        P.Refresh()
    end)
    I.Tip(row.toggle, "Filters", "Shows or hides the built-in filters for this channel. One channel's filters are shown at a time; nothing changes until you tick one.")
    row.cats = {}
    row.catLabels = {}
    for _, c in ipairs(CC().CATEGORIES) do
        local box = G.Checkbox(row, function(on) Set(row, c.key, on) end)
        local label = G.Text(row, "small")
        label:SetPoint("LEFT", box, "RIGHT", 5, 0)
        label:SetText(c.label)
        I.Tip(box, c.label, function()
            if row.ch and not (row.ch.choice and row.ch.choice.on) then return c.text, "Needs \"Clean\" turned on for this channel." end
            return c.text
        end)
        row.cats[c.key] = box
        row.catLabels[c.key] = label
    end
    row.offNote = G.Text(row, "small")
    row.offNote:SetJustifyH("LEFT")
    row.offNote:SetText("Turn on Clean to use these filters. They are kept while it is off.")
    G.Color(row.offNote, pal.stone)
    local divider = G.Solid(row, "BACKGROUND", pal.bronzeLo, 0.5)
    divider:SetPoint("BOTTOMLEFT", 8, 1)
    divider:SetPoint("BOTTOMRIGHT", -8, 1)
    divider:SetHeight(1)
    row.rules = row.summary   -- the rule count is part of the summary (kept under its older name for callers)
    rows[i] = row
    return row
end

-- Places a row's parts for the list's width; returns its height.
local function Layout(row, open)
    local listW = ListW()
    row:SetWidth(listW)
    local right = listW - 8
    row.toggle:ClearAllPoints(); row.toggle:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -12)
    row.clean:ClearAllPoints(); row.clean:SetPoint("RIGHT", row.toggle, "LEFT", -14, 0)
    local nameW = math.max(140, math.floor((listW - 300) * 0.45))
    row.name:SetWidth(nameW)
    row.status:SetWidth(nameW)
    row.summary:ClearAllPoints(); row.summary:SetPoint("TOPLEFT", row, "TOPLEFT", 16 + nameW, -8)
    local summaryW = math.max(90, right - 96 - 14 - 90 - (16 + nameW))
    row.summary:SetWidth(summaryW)
    local h = math.max(ROW_H, 12 + (row.status:GetStringHeight() or 14) + 26, 16 + (row.summary:GetStringHeight() or 14))
    local cols = math.max(1, math.min(3, math.floor((listW - 16) / CAT_W)))
    local i = 0
    for _, c in ipairs(CC().CATEGORIES) do
        local box, label = row.cats[c.key], row.catLabels[c.key]
        box:SetShown(open); label:SetShown(open)
        if open then
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", row, "TOPLEFT", 8 + (i % cols) * math.floor((listW - 16) / cols), -(h + math.floor(i / cols) * CAT_H))
            label:SetWidth(math.floor((listW - 16) / cols) - 50)
        end
        i = i + 1
    end
    if open then h = h + math.ceil(i / cols) * CAT_H + 4 end
    local off = open and not (row.ch and row.ch.choice and row.ch.choice.on)
    row.offNote:SetShown(off)
    if off then
        row.offNote:ClearAllPoints(); row.offNote:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -h); row.offNote:SetWidth(listW - 16)
        h = h + (row.offNote:GetStringHeight() or 14) + 6
    end
    row:SetHeight(h + 6)
    return h + 6
end

local function Status(ch)
    if ch.joined then
        local where = ch.number and ("/%d"):format(ch.number) or "joined"
        if ch.kind == "custom" then return where .. " · custom channel" end
        return where .. " · joined"
    end
    return "Not joined · choice saved for later"
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local G = Wg()
    local pal = G.pal
    local list, rules = {}, CC().Rules()
    -- Keep saved channels discoverable even when cleaning is paused or the channel is not joined.
    for _, ch in ipairs(CC().KnownChannels()) do
        list[#list + 1] = ch
    end
    local width = Width()
    f.help:SetWidth(width - 8)
    f.well:SetWidth(width)
    f.content:SetWidth(ListW())
    f.empty:SetWidth(width - 24)
    f.note:SetWidth(width - 8)
    f.about:SetWidth(math.max(200, width - 250))
    local stillThere = false
    for _, ch in ipairs(list) do if ch.key == openKey then stillThere = true end end
    if not stillThere then openKey = nil end
    local y = 0
    for i, ch in ipairs(list) do
        local row = Row(i)
        row.ch = ch
        local e = ch.choice or {}
        row.name:SetText(R.ChatCleanMatch.Plain(ch.label))
        G.Color(row.name, e.on and pal.text or pal.textDim)
        row.status:SetText(Status(ch))
        row.clean:SetChecked(e.on == true)
        for key, box in pairs(row.cats) do
            box:SetChecked(e[key] == true)
            box:SetActive(e.on == true)
        end
        local n = RulesFor(ch.key, rules)
        row.summary:SetText(P.FilterSummary(e, n))
        G.Color(row.summary, e.on and pal.textDim or pal.stone)
        local open = openKey == ch.key
        row.open = open
        row.toggle.text:SetText(open and "Hide filters" or "Filters")
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        y = y + Layout(row, open)
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i].ch = nil
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, y))
    f.empty:SetShown(#list == 0)
    f.reset:SetEnabled(CC().Customized())
end

-- Opens one channel's filters (search and direct navigation use it); others close. Returns true when that channel is listed.
function P.OpenChannel(key)
    for _, ch in ipairs(CC().KnownChannels()) do
        if ch.key == key then openKey = key; P.Refresh(); return true end
    end
    return false
end
function P.OpenKey() return openKey end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.1, function()
        refreshQueued = false
        P.Refresh()
    end)
end
P.QueueRefresh = QueueRefresh

local EVENTS = { "CHANNEL_UI_UPDATE", "CHANNEL_LEFT", "CHAT_MSG_CHANNEL_NOTICE", "ZONE_CHANGED_NEW_AREA" }

local function Build()
    built = true
    local G, I = Wg(), R.Interact
    local pal = G.pal

    f.help = G.Text(f, "small")
    f.help:SetPoint("TOPLEFT", 4, -2)
    f.help:SetWidth(Width() - 8)
    f.help:SetText("Each channel shows whether it is cleaned and which filters it uses. Open Filters to change one channel's filters. Whispers, group, guild and system messages stay untouched.")
    I.Tip(f, "Channel filters", "Custom rules choose their own channels on the Custom rules tab. Channels you don't enable are never filtered. Channel choices are kept when you leave and rejoin.")

    f.well = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.well:SetPoint("TOPLEFT", 0, LIST_TOP)
    f.well:SetSize(Width(), LIST_H)
    G.Well(f.well)
    f.scroll, f.content = G.Scroll(f.well, ListW())
    f.scroll:SetPoint("TOPLEFT", 6, -4)
    f.scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    f.empty = G.Text(f.well, "small")
    f.empty:SetPoint("TOPLEFT", 12, -14)
    f.empty:SetWidth(Width() - 24)
    f.empty:SetText("You aren't in any channel right now. Channels appear here as you join them (General and Trade join by themselves in most places).")

    f.note = G.Text(f, "small")
    f.note:SetPoint("TOPLEFT", f.well, "BOTTOMLEFT", 4, -10)
    f.note:SetWidth(Width() - 8)
    P.Say(P.lastSaid, P.lastTone)
    f.about = G.Text(f, "small")
    f.about:SetPoint("TOPLEFT", f.well, "BOTTOMLEFT", 4, -30)
    f.about:SetWidth(Width() - 250)
    f.about:SetText("Your choices are saved when you leave a channel. Custom rules are managed on their own tab.")
    G.Color(f.about, pal.stone)
    f.reset = G.Button(f, "Restore recommended channels", 226, "danger", function()
        R.Interact.Confirm("TWICHUI_CHATCLEAN_CHANNELS", "Restore the recommended channel choice?\n\nGeneral and Trade are cleaned with the spam and repeat filters, and every other channel's choice is forgotten. Your custom rules are kept, with the channels they name.", function()
            CC().ResetChannels()
            P.Say("The recommended channels are back.", "ok")
        end, { accept = "Restore" })
    end)
    f.reset:SetPoint("TOPRIGHT", f.well, "BOTTOMRIGHT", 0, -28)
    I.Tip(f.reset, "Restore recommended channels", "Puts back General and Trade with the spam and repeat filters, and forgets the choices for other channels. Custom rules are kept. Asks first.")
end

-- The page's frame (the settings window shows it under Chat cleaning). Built the first time it is shown.
function P.Frame()
    if f then return f end
    f = CreateFrame("Frame")
    f:Hide()
    f:SetScript("OnShow", function(self)
        if not built then Build() end
        for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
        P.Refresh()
    end)
    f:SetScript("OnHide", function(self)
        for _, e in ipairs(EVENTS) do self:UnregisterEvent(e) end
    end)
    f:SetScript("OnSizeChanged", function() if built then QueueRefresh() end end)
    f:SetScript("OnEvent", QueueRefresh)
    return f
end

-- A change made anywhere (here, another tab, a profile change, an import) redraws the list if it is shown. Registered once.
if R.ChatClean then R.ChatClean.OnChange(QueueRefresh) end

K.Page({
    key = "chatCleanChannels", name = "Chat cleaning channels", nav = "Channels", parent = "chatClean", order = 36,
    description = "Which channels are cleaned, and which built-in filters each one uses.",
    keywords = "chat channel channels trade general localdefense lookingforgroup custom spam repeats recruitment clean filters restore recommended",
    when = function() return R.ChatClean ~= nil end,
    host = function() return P.Frame() end,
})
