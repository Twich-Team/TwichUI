-- TwichUI Settings: feature cards (a section described with K.Card, drawn by Window.lua through these)
-- A card is a section drawn as one feature: its icon, title and one sentence; its switch with "On" or "Off"
-- written beside it (never color alone); a line under the sentence for anything the switch is waiting on (a
-- reload, another addon doing the same thing); an optional sample preview; the rules as they are set, in one line;
-- what to know before turning it on (always shown, never only in a tooltip); and the actions: Adjust rules (the
-- card's other rows), More about this (short answers), Play sample. Opening or closing a part changes no setting;
-- which parts are open is kept for the session only, in the page's view. The rows inside are the window's
-- ordinary rows (same controls, tooltips, greyed-out reasons), so nothing about a setting is drawn twice.
--
--   Cards.Build(view, sec, width, env)        makes the card's own pieces once, when its page is first shown
--   Cards.Primary(sec, row, env)              the card's switch, as a row view (RefreshValue, Refresh, frame, y)
--   Cards.Layout(view, sec, inner, env) -> inner   places and draws it; rows go through env.PlaceRows
--   Cards.Reveal(view, sec)                   opens the part that holds a row search or a link asked for
-- env: { PlaceRows(sec, rows, inner) -> inner, Note(row) -> text, tone, TONE, Relayout(), PAD }

local R = TwichUI
local Wg = R.SettingsWidgets
local I = R.Interact
local P = R.SettingsPreviews
local pal, Motion = Wg.pal, Wg.Motion
local Cards = {}
R.SettingsCards = Cards

local ICON = 36            -- the card's icon, in UI units (the 64 px file)
local GAP = 12             -- between the icon and the text
local CHECK_W = 18
local ACTION_H = 22
local SAVED_SECONDS = 1.4  -- how long "Saved" stays after a change you make

Cards.ICON = ICON

local function Text(value)
    if type(value) == "function" then
        local ok, text = pcall(value)
        value = ok and text or nil
    end
    return type(value) == "string" and value ~= "" and value or nil
end

-- A text button with a chevron that says whether its part is open: "Adjust rules" / "Hide rules". The words
-- carry the state; the chevron agrees with them.
local function Disclosure(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(ACTION_H)
    b.text = Wg.Text(b, "small")
    b.text:SetPoint("LEFT", 16, 0)
    Wg.Color(b.text, pal.tealHi)
    b.down = Wg.Chevron(b, b, "LEFT", 7, 0, true, pal.tealHi)
    b.up = Wg.Chevron(b, b, "LEFT", 7, 0, false, pal.tealHi)
    Wg.Hover(b, pal.text, 0.06)
    function b:SetOpen(open, closedText, openText)
        for _, t in ipairs(self.down) do t:SetShown(not open) end
        for _, t in ipairs(self.up) do t:SetShown(open) end
        self.text:SetText(open and openText or closedText)
        self:SetWidth((self.text:GetStringWidth() or 60) + 24)
        self.open = open
    end
    b:SetScript("OnClick", onClick)
    b:HookScript("OnEnter", function(self) Wg.Color(self.text, pal.text) end)
    b:HookScript("OnLeave", function(self) Wg.Color(self.text, pal.tealHi) end)
    return b
end

function Cards.Build(view, sec, width, env)
    local card, def = sec.card, sec.header.card
    local pad = env.PAD
    sec.isCard = true
    view.open = view.open or {}
    view.details = view.details or {}

    -- the head: icon, title, sentence, switch. A frame of its own, so a search result can mark it like a row.
    sec.head = CreateFrame("Frame", nil, card)
    sec.head:SetWidth(width - pad * 2 + 8)
    sec.head.bg = Wg.Solid(sec.head, "BACKGROUND", pal.text, 0)
    sec.head.bg:SetAllPoints()
    sec.icon = sec.head:CreateTexture(nil, "ARTWORK")
    sec.icon:SetSize(ICON, ICON)
    sec.icon:SetPoint("TOPLEFT", 4, -2)
    sec.iconDrawn = R.Icons and def.icon and R.Icons.Apply(sec.icon, def.icon, ICON) or nil
    if not sec.iconDrawn then sec.icon:Hide() end
    local textX = 4 + (sec.iconDrawn and (ICON + GAP) or 0)
    local textW = width - pad * 2 - textX - 120
    sec.title:SetParent(sec.head)
    sec.title:SetWidth(textW)
    Wg.Color(sec.title, pal.text)
    sec.desc:SetParent(sec.head)
    sec.desc:SetWidth(textW)
    sec.note = Wg.Text(sec.head, "small")
    sec.note:SetWidth(textW)
    sec.textX = textX

    -- after the head: the rules in one line, and what to know first
    sec.summary = Wg.Text(card, "small")
    sec.summary:SetWidth(width - pad * 2 - 8)
    sec.summary:SetWordWrap(true)
    sec.consequence = Wg.Text(card, "small")
    sec.consequence:SetWidth(width - pad * 2 - 8)
    sec.consequence:SetWordWrap(true)

    -- actions
    if #sec.header.rules > 0 and not def.inline then
        sec.rulesButton = Disclosure(card, function()
            view.open[sec.id] = not view.open[sec.id]
            sec.revealing = view.open[sec.id]
            env.Relayout()
        end)
    end
    if def.details and #def.details > 0 then
        sec.detailsButton = Disclosure(card, function()
            view.details[sec.id] = not view.details[sec.id]
            sec.revealing = view.details[sec.id]
            env.Relayout()
        end)
        sec.detailText = Wg.Text(card, "small")
        sec.detailText:SetWidth(width - pad * 2 - 8)
        sec.detailText:SetWordWrap(true)
    end
    if def.preview and P then
        sec.preview = P.Host(card, def.preview, width - pad * 2 - 8)
        if sec.preview and not sec.preview.def.static then
            sec.play = Wg.Button(card, "Play sample", 110, "secondary", function()
                sec.preview:Play()
                sec.play.text:SetText("Play again")
            end)
            I.Tip(sec.play, "Play sample", "Plays a short sample of this feature with made-up names and places, using your rules as they are set. It changes nothing and does nothing in the game.")
        end
    end

    -- what opens fades in (alpha only); where motion is reduced it is simply there
    sec.revealFade = Motion.Fader(function(a)
        for _, v in ipairs(sec.rows) do if v.rule then v.frame:SetAlpha(a) end end
        if sec.detailText then sec.detailText:SetAlpha(a) end
    end, 1)
end

-- The card's switch, standing in for its row: the checkbox in the head, "On" or "Off" beside it, "Saved" for a
-- moment after you change it. Its tooltip is the row's own.
function Cards.Primary(sec, row, env)
    local setting = row.data.setting
    local v = { row = row, frame = sec.head, primary = true, section = sec }
    local token = 0
    local function Saved()
        token = token + 1
        local mine = token
        sec.saved:SetText("Saved")
        sec.savedFade:Set(1)
        C_Timer.After(SAVED_SECONDS, function()
            if token ~= mine then return end
            sec.savedFade:To(0, Motion.TIME.page)
        end)
    end
    -- the switch's hit area: the "On"/"Off" word and the box, so the word can be clicked too; it holds the tooltip
    local hit = CreateFrame("Button", nil, sec.head)
    hit:SetSize(64 + CHECK_W, 26)
    hit:SetPoint("TOPRIGHT", sec.head, "TOPRIGHT", 0, 0)
    I.Tip(hit, row:GetName(), function()
        local tip = row:GetTooltip()
        local why = not row:Enabled() and row:DisabledReason() or nil
        return tip, why
    end)
    local function Flip(on)
        if not row:Enabled() then return end
        setting:SetValue(on)
        Saved()
    end
    hit:SetScript("OnClick", function() Flip(not setting:GetValue()) end)
    v.control = Wg.Checkbox(sec.head, Flip)
    v.control:SetPoint("TOPRIGHT", sec.head, "TOPRIGHT", -4, -4)
    v.control:HookScript("OnEnter", function() local show = hit:GetScript("OnEnter"); if show then show(hit) end end)
    v.control:HookScript("OnLeave", function() I.HideTip(hit) end)
    hit:HookScript("OnEnter", function() v.control:SetHot(true) end)
    hit:HookScript("OnLeave", function() v.control:SetHot(false) end)
    sec.state = Wg.Text(sec.head, "body")
    sec.state:SetPoint("RIGHT", v.control, "LEFT", -8, 0)
    sec.saved = Wg.Text(sec.head, "meta")
    sec.saved:SetPoint("RIGHT", sec.state, "LEFT", -10, 0)
    Wg.Color(sec.saved, pal.tealHi)
    sec.savedFade = Motion.Fader(function(a) sec.saved:SetAlpha(a) end, 0)
    -- a page left or a window closed drops the word at once; a timer still pending finds itself stale
    sec.head:HookScript("OnHide", function() token = token + 1; sec.savedFade:Set(0) end)

    function v.RefreshValue()
        local enabled = row:Enabled()
        local on = setting:GetValue() and true or false
        v.control:SetChecked(on)
        v.control:SetActive(enabled)
        sec.state:SetText(on and "On" or "Off")
        Wg.Color(sec.state, (on and enabled) and pal.tealHi or pal.stone)
        return enabled
    end
    function v.Refresh() return v.RefreshValue() end
    return v
end

-- The words for the rules line: "Rules: <summary>", or nothing when the card has no summary.
local function SummaryText(def)
    local text = Text(def.summary)
    if not text then return nil end
    return "|c" .. Wg.Hex(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3]) .. "Rules|r   " .. text
end

local function ConsequenceText(def)
    local text = Text(def.consequence)
    if not text then return nil end
    return "|c" .. Wg.Hex(pal.bronzeText[1], pal.bronzeText[2], pal.bronzeText[3]) .. "Good to know|r   " .. text
end

local function DetailsText(def)
    local parts = {}
    for _, qa in ipairs(def.details or {}) do
        local answer = Text(qa[2])
        if answer then
            parts[#parts + 1] = "|c" .. Wg.Hex(pal.text[1], pal.text[2], pal.text[3]) .. qa[1] .. "|r\n" .. answer
        end
    end
    return table.concat(parts, "\n\n")
end

function Cards.Layout(view, sec, inner, env)
    local def, card, pad = sec.header.card, sec.card, env.PAD
    local primary = sec.primaryView
    local head = sec.head

    -- head
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", card, "TOPLEFT", pad - 4, -inner)
    sec.title:SetText(sec.header:GetName() or "")
    sec.title:ClearAllPoints()
    sec.title:SetPoint("TOPLEFT", head, "TOPLEFT", sec.textX, -2)
    local h = 2 + (sec.title:GetStringHeight() or 14) + 3
    sec.desc:SetText(sec.header:GetTooltip() or "")
    sec.desc:ClearAllPoints()
    sec.desc:SetPoint("TOPLEFT", head, "TOPLEFT", sec.textX, -h)
    sec.desc:Show()
    h = h + (sec.desc:GetStringHeight() or 12)
    -- under the sentence: why the switch can't be used, or what it is waiting on (a reload, an overlap)
    local note, tone
    if primary then
        local enabled = primary.Refresh()
        if not enabled then note = primary.row:DisabledReason() else note, tone = env.Note(primary.row) end
        primary.y = sec.top + inner
    end
    sec.note:SetShown(note ~= nil)
    if note then
        sec.note:SetText(note)
        Wg.Color(sec.note, env.TONE[tone] or pal.stone)
        sec.note:ClearAllPoints()
        sec.note:SetPoint("TOPLEFT", head, "TOPLEFT", sec.textX, -(h + 3))
        h = h + 3 + (sec.note:GetStringHeight() or 12)
    end
    h = math.max(h, (sec.iconDrawn and ICON or 0) + 4) + 4
    head:SetHeight(h)
    inner = inner + h + 8

    -- preview
    if sec.preview then
        local f = sec.preview.frame
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", card, "TOPLEFT", pad, -inner)
        f:Show()
        inner = inner + P.HostHeight(sec.preview) + 10
    end

    -- the rules as set, and what to know first
    for _, fs in ipairs({ { sec.summary, SummaryText(def) }, { sec.consequence, ConsequenceText(def) } }) do
        local text = fs[2]
        fs[1]:SetShown(text ~= nil)
        if text then
            fs[1]:SetText(text)
            fs[1]:ClearAllPoints()
            fs[1]:SetPoint("TOPLEFT", card, "TOPLEFT", pad + 2, -inner)
            inner = inner + (fs[1]:GetStringHeight() or 12) + 6
        end
    end

    -- actions
    local open = def.inline or view.open[sec.id]
    local detailsOpen = view.details[sec.id]
    local x, any = pad - 4, false
    if sec.rulesButton then
        local n = #sec.header.rules
        sec.rulesButton:SetOpen(open and true or false, n == 1 and "Adjust rule" or ("Adjust rules (%d)"):format(n), n == 1 and "Hide rule" or "Hide rules")
        sec.rulesButton:ClearAllPoints()
        sec.rulesButton:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(inner + 2))
        x = x + sec.rulesButton:GetWidth() + 12
        any = true
    end
    if sec.detailsButton then
        sec.detailsButton:SetOpen(detailsOpen and true or false, "More about this", "Less about this")
        sec.detailsButton:ClearAllPoints()
        sec.detailsButton:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(inner + 2))
        any = true
    end
    if sec.play then
        sec.play:ClearAllPoints()
        sec.play:SetPoint("TOPRIGHT", card, "TOPRIGHT", -pad, -inner)
        any = true
    end
    if any then inner = inner + ACTION_H + 8 end

    -- details: short answers, in the card, never only in a tooltip
    if sec.detailText then
        sec.detailText:SetShown(detailsOpen and true or false)
        if detailsOpen then
            sec.detailText:SetText(DetailsText(def))
            sec.detailText:ClearAllPoints()
            sec.detailText:SetPoint("TOPLEFT", card, "TOPLEFT", pad + 2, -inner)
            inner = inner + (sec.detailText:GetStringHeight() or 12) + 10
        end
    end

    -- the rules' rows (the window's own), shown while open; hidden ones keep their place in search
    local rules = {}
    for _, v in ipairs(sec.rows) do
        if v.rule then
            if open then rules[#rules + 1] = v else v.frame:Hide(); v.y = nil end
        end
    end
    if open and #rules > 0 then inner = env.PlaceRows(sec, rules, inner) end

    -- a part just opened fades in; one already open is drawn as it is
    if sec.revealing then
        sec.revealing = false
        sec.revealFade:Set(0)
        sec.revealFade:To(1, Motion.TIME.disclose)
    end
    return inner
end

-- Opens the part of a card that holds `row` (its rules), so a search result or a link can show it. Changes no
-- setting.
function Cards.Reveal(view, sec, row)
    if not (sec and sec.isCard and row and row.ruleOf) then return false end
    if sec.header.card.inline or view.open[sec.id] then return false end
    view.open[sec.id] = true
    return true
end
