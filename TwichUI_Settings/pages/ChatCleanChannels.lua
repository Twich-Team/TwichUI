-- TwichUI settings: Chat cleaning › Channels (modules/ChatClean.lua). One row per channel: whether it is cleaned and
-- which built-in filters it uses, and how many custom rules apply to it. The channels are the ones you are in now
-- (from the client) and the ones you chose before; a channel you left keeps its choice for when you are back. A frame
-- of this window's own, shown as the tab's page, since a grid of checkboxes doesn't fit the ordinary rows. Built the
-- first time it is shown; rows are made as they are first needed and reused on every redraw. While it is shown it
-- listens for the channel list changing (joining, leaving, a new zone), and stops when it is hidden. Every change goes
-- through ChatClean.lua's own functions.

local R = TwichUI
local K = R.SettingsKit
local P = {}
R.ChatCleanChannelsPage = P

local W = 644                  -- the settings window's content width
local ROW_H, VISIBLE = 36, 9
local LIST_TOP = -66
local LIST_H = ROW_H * VISIBLE + 8
local LIST_W = W - 12 - 26
local NAME_W = 214
local CLEAN_X = 232
local CAT_X = { spam = 268, recruit = 324, politics = 380, lgbt = 436, repeats = 492 }
local RULES_X = 548

local f, built
local rows = {}
local refreshQueued = false

local function Wg() return R.SettingsWidgets end
local function CC() return R.ChatClean end

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
    row:SetSize(LIST_W, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.bg = G.Solid(row, "BACKGROUND", pal.text, (i % 2 == 0) and 0.035 or 0)
    row.bg:SetAllPoints()
    row.name = G.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 8, -4)
    row.name:SetWidth(NAME_W)
    row.name:SetWordWrap(false)
    row.status = G.Text(row, "meta")
    row.status:SetPoint("TOPLEFT", 8, -20)
    row.status:SetWidth(NAME_W)
    row.status:SetWordWrap(false)

    row.clean = G.Checkbox(row, function(on) Set(row, "on", on) end)
    row.clean:SetPoint("LEFT", CLEAN_X, 0)
    I.Tip(row.clean, "Clean this channel", function()
        return "On: TwichUI checks messages in this channel against the filters ticked beside it and the custom rules that apply here. Off: the channel is left alone; its choices are kept."
    end)
    row.cats = {}
    for _, c in ipairs(CC().CATEGORIES) do
        local box = G.Checkbox(row, function(on) Set(row, c.key, on) end)
        box:SetPoint("LEFT", CAT_X[c.key], 0)
        I.Tip(box, c.label, function()
            if row.ch and not (row.ch.choice and row.ch.choice.on) then return c.text, "Needs \"Clean this channel\" ticked." end
            return c.text
        end)
        row.cats[c.key] = box
    end
    row.rules = G.Text(row, "meta")
    row.rules:SetPoint("LEFT", RULES_X, 0)
    row.rules:SetWidth(LIST_W - RULES_X - 4)
    row.rules:SetJustifyH("LEFT")
    rows[i] = row
    return row
end

local function Status(ch)
    if ch.joined then
        local where = ch.number and ("/%d"):format(ch.number) or "joined"
        if ch.kind == "custom" then return where .. " · custom channel, recognised by name" end
        return where .. " · recognised in every zone and language"
    end
    if ch.kind == "custom" then return "Not joined now · custom channel, recognised by name" end
    return "Not joined now · kept for when you are"
end

function P.Refresh()
    if not (f and built and f:IsShown()) then return end
    local G = Wg()
    local pal = G.pal
    local list, rules = {}, CC().Rules()
    -- channels you aren't in are listed only while they are cleaned (their choice is kept either way)
    for _, ch in ipairs(CC().KnownChannels()) do
        if ch.joined or (ch.choice and ch.choice.on) then list[#list + 1] = ch end
    end
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
        row.rules:SetText(n == 0 and "none" or (n == 1 and "1 rule" or ("%d rules"):format(n)))
        G.Color(row.rules, (e.on and n > 0) and pal.textDim or pal.stone)
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i].ch = nil
        rows[i]:Hide()
    end
    f.content:SetHeight(math.max(1, #list * ROW_H))
    f.empty:SetShown(#list == 0)
    f.reset:SetEnabled(CC().Customized())
end

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
    f.help:SetWidth(W - 8)
    f.help:SetText("Tick the channels to clean, then the filters each one uses. Custom rules choose their own channels on the Custom rules tab. Channels you didn't tick, and whispers, group, guild and system messages, are never looked at.")

    local function Column(text, x, title, body)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(72, 16)
        b:SetPoint("TOPLEFT", 6 + x - 4, -46)
        local t = G.Text(b, "meta")
        t:SetPoint("LEFT", 0, 0)
        t:SetText(text)
        if title then I.Tip(b, title, body) end
        return b
    end
    Column("Channel", 4)
    Column("Clean", CLEAN_X - 6, "Clean this channel", "Whether TwichUI looks at this channel at all.")
    for _, c in ipairs(CC().CATEGORIES) do Column(c.short, CAT_X[c.key] - 10, c.label, c.text) end
    Column("Rules", RULES_X, "Custom rules", "How many of your custom rules that are on apply in this channel.")

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
    f.empty:SetText("You aren't in any channel right now. Channels appear here as you join them (General and Trade join by themselves in most places).")

    local below = LIST_TOP - LIST_H - 10
    f.note = G.Text(f, "small")
    f.note:SetPoint("TOPLEFT", 4, below)
    f.note:SetWidth(W - 8)
    P.Say(P.lastSaid, P.lastTone)
    f.about = G.Text(f, "small")
    f.about:SetPoint("TOPLEFT", 4, below - 20)
    f.about:SetWidth(W - 190)
    f.about:SetText("System channels such as General and Trade are recognised by the game's own channel ID, so your choice holds whatever their number in your list, in every zone and city, and in any language. Custom channels have only their name, so they are recognised by it.")
    G.Color(f.about, pal.stone)
    f.reset = G.Button(f, "Recommended channels", 170, "danger", function()
        R.Interact.Confirm("TWICHUI_CHATCLEAN_CHANNELS", "Put the recommended channel choice back?\n\nGeneral and Trade are cleaned with the spam and repeat filters, and every other channel's choice is forgotten. Your custom rules are kept, with the channels they name.", function()
            CC().ResetChannels()
            P.Say("The recommended channels are back.", "ok")
        end, { accept = "Put back" })
    end)
    f.reset:SetPoint("TOPRIGHT", -2, below - 22)
    I.Tip(f.reset, "Recommended channels", "Puts back General and Trade with the spam and repeat filters, and forgets the choices for other channels. Custom rules are kept. Asks first.")
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
    f:SetScript("OnEvent", QueueRefresh)
    return f
end

-- A change made anywhere (here, another tab, a profile change, an import) redraws the list if it is shown. Registered once.
if R.ChatClean then R.ChatClean.OnChange(QueueRefresh) end

K.Page({
    key = "chatCleanChannels", name = "Chat cleaning channels", nav = "Channels", parent = "chatClean", order = 36,
    description = "Which channels are cleaned, and which built-in filters each one uses.",
    keywords = "chat channel channels trade general localdefense lookingforgroup custom spam repeats recruitment clean",
    when = function() return R.ChatClean ~= nil end,
    host = function() return P.Frame() end,
})
