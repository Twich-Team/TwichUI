-- TwichUI Workshop: the Gold Ledger page
-- What the core's recorder (!!!TwichUI/auction/Ledger.lua) has kept of the gold this character (or all of them) gained and spent: six
-- summary cards, the Gold Flow chart, the split by source, the newest transactions, and a Profit by Profession panel that says plainly
-- it is not available yet. Everything is read through LedgerQuery.lua (pure); nothing is scanned, estimated or saved here. The filters
-- (character, source, 7/30/90 days, search) are kept for the session only and apply to every panel at once.
--
-- Net Change is the safe centre of the page: gold in minus gold out. It is not profit (materials, repairs and moves between your own
-- characters are gold out too), and no figure here is an estimate. While the page is shown it listens for the recorder's changes (one
-- subscription, released when the page or the window is hidden) and redraws once for a burst of them.

local R = TwichUI
local W = R.Workshop
local UI = W.UI
local LQ = W.LedgerQuery

local GAP = 8
local CARD_H, CARD_TOP = 76, -82
local MID_TOP, MID_H, MID_L = -166, 196, 568
local BOT_TOP, BOT_H = -370, 185
local ROW_H = 26
local DRAW_DELAY = 0.3     -- a burst of money changes is one redraw
local SEARCH_DELAY = 0.15

local K
local V = { cards = {}, srcRows = {}, profRows = {} }
UI.LedgerView = V
local page
local filter = { scope = "current", source = nil, days = 7, search = "" }
local generation = 0
local drawPending = false
local subscribed = false
local stale = false
local draws = 0

function V.Filter() return filter end
function V.Draws() return draws end

local SCOPES = { { "current", "This character" }, { "all", "All characters" } }
local SOURCES = { { "all", "All sources" } }
local CARD_DEFS = {
    { key = "net", title = "Net Change", art = "npc:balance-scales",
      tip = "Gold in minus gold out over the chosen days: how your gold changed, as recorded. It is not profit: purchases of materials, repairs and gold you moved between your own characters count as gold out." },
    { key = "inn", title = "Gold In", art = "npc:coins",
      tip = "All gold that arrived in the chosen days, whatever its source." },
    { key = "out", title = "Gold Out", art = "npc:reagent-pouch",
      tip = "All gold that left in the chosen days, whatever the reason." },
    { key = "attrIn", title = "Attributed Income", art = "npc:gavel",
      tip = "Mailbox money, auction-sale invoices and verified vendor sales, matched to the exact gold received." },
    { key = "attrOut", title = "Attributed Spending", art = "npc:hammer",
      tip = "Auction purchases, verified posting deposits and cancellation fees, vendor purchases and player-paid repairs, matched to the exact gold spent." },
    { key = "unk", title = "Unclassified", art = "npc:sealed-scroll",
      tip = "Gold that moved with nothing to say why: loot, quests, uncertain merchant activity, trades, postage and more. It is kept, never hidden. The figure is its net." },
}

---------------------------------------------------------------------------
-- Small builders
---------------------------------------------------------------------------
local function Panel(parent, title, art)
    local p = CreateFrame("Frame", nil, parent)
    UI.Panel(p, "card")
    if art then
        local icon = p:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("TOPLEFT", 12, -8)
        UI.Art(icon, art, 20)
        p.icon = icon
    end
    p.title = UI.Text(p, 18, K.text, "serif")
    p.title:SetPoint("TOPLEFT", art and 38 or 14, -8)
    p.title:SetText(title)
    return p
end

local function Dropdown(parent, width, choices, current, choose)
    local menu, b
    b = R.ChronicleStyle.DropButton(parent, width, function()
        if menu then menu:Close(); menu = nil end
        local root = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultMenuMixin())
        root:SetMinimumWidth(width)
        for _, entry in ipairs(choices) do
            local value, text = entry[1], entry[2]
            local radio = root:CreateRadio(text, function() return current() == value end, function() choose(value) end)
            radio:AddInitializer(function(button)
                if button.fontString then UI.Paint(button.fontString, current() == value and K.bronzeText or K.text) end
            end)
        end
        root:AddMenuReleasedCallback(function() menu = nil end)
        menu = Menu.GetManager():OpenMenu(b, root, AnchorUtil.CreateAnchor("TOPLEFT", b, "BOTTOMLEFT", 0, -2))
    end, K)
    b:SetHeight(28)
    UI.CL.Dress(b, "dropdown")
    function b:Refresh()
        for _, entry in ipairs(choices) do if entry[1] == current() then self.text:SetText(entry[2]) return end end
    end
    b:HookScript("OnHide", function() if menu then menu:Close(); menu = nil end end)
    b:Refresh()
    return b
end

-- A text made smaller (from `from` down to `to`) until it fits `width`: the figures and names of a card, in any font
local function Fit(fs, text, width, from, to, role)
    fs:SetText(text)
    for size = from, to, -1 do
        UI.CL.Font(fs, size, false, role)
        if (fs:GetStringWidth() or 0) <= width then return end
    end
end

---------------------------------------------------------------------------
-- Cards
---------------------------------------------------------------------------
local function BuildCards()
    local w = math.floor((940 - GAP * 5) / 6)
    for i, def in ipairs(CARD_DEFS) do
        local c = CreateFrame("Frame", nil, page)
        c:SetSize(w, CARD_H)
        c:SetPoint("TOPLEFT", page, "TOPLEFT", (i - 1) * (w + GAP), CARD_TOP)
        UI.Panel(c, "card")
        c.def = def
        c.icon = c:CreateTexture(nil, "ARTWORK")
        c.icon:SetSize(20, 20)
        c.icon:SetPoint("TOPLEFT", 9, -7)
        UI.Art(c.icon, def.art, 20)
        c.width = w - 18
        c.title = UI.Text(c, 12, K.textDim)
        c.icon:SetPoint("TOPLEFT", 10, -9)
        c.title:SetPoint("LEFT", c.icon, "RIGHT", 6, 0)
        c.title:SetWidth(w - 10 - 20 - 6 - 6)
        Fit(c.title, def.title, w - 10 - 20 - 6 - 6, 12, 10)
        c.value = UI.Text(c, 19, K.text, "serif")
        c.value:SetPoint("TOPLEFT", 10, -33)
        c.sub = UI.Text(c, 12, K.stone)
        c.sub:SetPoint("TOPLEFT", 10, -58)
        c.sub:SetWidth(c.width)
        c.cmp = UI.Text(c, 11, K.stone)   -- only when a complete earlier period exists; hidden otherwise
        c.cmp:SetPoint("TOPRIGHT", c, "TOPRIGHT", -10, -58)
        c.cmp:SetWidth(c.width)
        c.cmp:SetJustifyH("RIGHT")
        c.cmp:Hide()
        UI.Tip(c, def.title, def.tip)
        V.cards[def.key] = c
    end
end

local function Tone(v) return v > 0 and K.sage or (v < 0 and K.ember or K.text) end

local function PaintCards(s)
    local t = s and s.recording and s.totals or nil
    local days = filter.days
    for _, def in ipairs(CARD_DEFS) do
        local c = V.cards[def.key]
        local value, tone, sub, cmp = "", K.textDim, ("Last %d days"):format(days), ""
        if t then
            if def.key == "net" then
                value, tone = LQ.Money(t.net, true), Tone(t.net)
                local p = LQ.Compare(s, "net")
                cmp = p and p.text or ""
            elseif def.key == "inn" then
                value, tone = LQ.Money(t.inn, true), t.inn > 0 and K.sage or K.text
                local p = LQ.Compare(s, "inn")
                cmp = p and p.text or ""
            elseif def.key == "out" then
                value, tone = t.out > 0 and LQ.Money(-t.out) or LQ.Money(0), t.out > 0 and K.ember or K.text
                local p = LQ.Compare(s, "out")
                cmp = p and p.text or ""
            elseif def.key == "attrIn" then
                value, tone, sub = LQ.Money(t.attrIn, true), t.attrIn > 0 and K.sage or K.text, "Confirmed sources"
            elseif def.key == "attrOut" then
                value, tone, sub = t.attrOut > 0 and LQ.Money(-t.attrOut) or LQ.Money(0), t.attrOut > 0 and K.ember or K.text, "Confirmed sources"
            else
                local net = t.unkIn - t.unkOut
                value, tone, sub = LQ.Money(net, true), Tone(net), "Source unknown"
            end
        else
            value = "\226\128\148"
            sub, cmp = "Nothing recorded yet", ""
        end
        Fit(c.value, value, c.width, 19, 12, "serif")
        UI.Paint(c.value, tone)
        Fit(c.sub, sub, c.width, 12, 10)
        -- a comparison sits on its own line only when there is a real one; otherwise nothing is said
        c.cmp:SetShown(cmp ~= "")
        if cmp ~= "" then
            c.sub:SetWidth(c.width * 0.45)
            c.cmp:SetWidth(c.width * 0.55)
            Fit(c.cmp, cmp, c.width * 0.55, 11, 10)
        else
            c.sub:SetWidth(c.width)
            c.cmp:SetText("")
        end
    end
end

---------------------------------------------------------------------------
-- Gold Flow, Gold by Source, Profit by Profession
---------------------------------------------------------------------------
local function BuildFlow()
    local p = Panel(page, "Gold Flow", "npc:coins")
    p:SetSize(MID_L, MID_H)
    p:SetPoint("TOPLEFT", page, "TOPLEFT", 0, MID_TOP)
    V.flow = p
    p.ranges = {}
    local x = -10
    for i = #LQ.RANGES, 1, -1 do
        local days = LQ.RANGES[i]
        local b = UI.Segment(p, days .. "D", 52, function() V.SetFilter("days", days) end)
        b:SetPoint("TOPRIGHT", p, "TOPRIGHT", x, -6)
        x = x - 54
        b.days = days
        UI.Tip(b, days .. " days", "The last " .. days .. " days, today included. Every card and panel on this page follows.")
        p.ranges[days] = b
    end
    local chart = UI.GoldFlowChart(p, MID_L - 16, MID_H - 40)
    chart:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -34)
    chart:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 6)
    V.chart = chart
end

local function BuildSources()
    local w = 940 - MID_L - GAP
    local p = Panel(page, "Gold by Source", "npc:balance-scales")
    p:SetSize(w, MID_H)
    p:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, MID_TOP)
    V.sources = p
    local function MakeSource(parent)
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ROW_H)
        row.label = UI.Text(row, 12, K.text)
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(134)
        row.amount = UI.Text(row, 12, K.text)
        row.amount:SetPoint("RIGHT", 0, 0)
        row.amount:SetWidth(92)
        row.amount:SetJustifyH("RIGHT")
        row.bar = UI.Meter(row, 80, 10)
        row.bar:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
        row.bar:SetPoint("RIGHT", row.amount, "LEFT", -8, 0)
        row.fill = function(self, r)
            self.label:SetText(r.label)
            self.amount:SetText(LQ.Money(r.dir * r.amount, true))
            UI.Paint(self.amount, r.dir > 0 and K.sage or K.ember)
            self.bar:SetFraction(V.sourceTop > 0 and r.amount / V.sourceTop or 0)
            self.bar:SetTone(r.dir > 0 and K.sage or K.ember)
            self.data = r
        end
        return row
    end
    -- Keep the existing panel and row styling; scrolling exposes every source when more than five are present.
    V.sourceList = UI.List(p, ROW_H, MakeSource, ROW_H * 5, false)
    V.sourceList.box:SetPoint("TOPLEFT", 8, -30)
    V.sourceList.box:SetPoint("BOTTOMRIGHT", -8, 34)
    V.srcRows = V.sourceList.rows
    p.empty = V.sourceList.empty
    p.note = UI.Text(p, 11, K.stone)
    p.note:SetPoint("BOTTOMLEFT", 14, 8)
    p.note:SetPoint("RIGHT", p, "RIGHT", -12, 0)
    p.note:SetHeight(26)
    p.note:SetWordWrap(true)
    p.note:SetJustifyV("BOTTOM")
end

local function PaintSources(s)
    local p = V.sources
    local rows = LQ.SourceRows(s)
    V.sourceTop = rows[1] and rows[1].amount or 0
    V.sourceList:SetData(rows, "No gold has moved in this period.")
    local note = {}
    if #rows > 0 then note[1] = "Together these add up to Net Change." end
    if s and s.characters > 1 then note[#note + 1] = "All characters: gold you moved between your own characters counts in and out." end
    p.note:SetText(table.concat(note, " "))
end

local function BuildProfessions()
    local w = 940 - MID_L - GAP
    local p = Panel(page, "Profit by Profession", "npc:hammer-and-chisel")
    p:SetSize(w, BOT_H)
    p:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, BOT_TOP)
    V.prof = p
    p.art = p:CreateTexture(nil, "ARTWORK")
    p.art:SetSize(48, 48)
    p.art:SetPoint("TOPLEFT", 18, -62)
    UI.Art(p.art, "npc:hammer-and-chisel", 48)
    p.art:SetAlpha(0.8)
    p.head = UI.Text(p, 14, K.text, "strong")
    p.head:SetPoint("TOPLEFT", p.art, "TOPRIGHT", 14, 1)
    p.head:SetWidth(w - 18 - 48 - 14 - 16)
    p.head:SetHeight(38)
    p.head:SetWordWrap(true)
    p.head:SetJustifyV("TOP")
    p.head:SetText("Profession profitability isn't available yet.")
    p.body = UI.Text(p, 12, K.textDim)
    p.body:SetPoint("TOPLEFT", p.head, "BOTTOMLEFT", 0, -8)
    p.body:SetWidth(w - 18 - 48 - 14 - 16)
    p.body:SetHeight(36)
    p.body:SetWordWrap(true)
    p.body:SetJustifyV("TOP")
    p.body:SetText("Accurate profit requires completed sales and recorded material costs.")
    for i = 1, 5 do
        local row = CreateFrame("Frame", nil, p)
        row:SetHeight(ROW_H - 2)
        row:SetPoint("TOPLEFT", 12, -34 - (i - 1) * (ROW_H - 2))
        row:SetPoint("TOPRIGHT", -12, -34 - (i - 1) * (ROW_H - 2))
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(18, 18)
        row.icon:SetPoint("LEFT", 0, 0)
        row.name = UI.Text(row, 13, K.text)
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.amount = UI.Text(row, 13, K.text)
        row.amount:SetPoint("RIGHT", 0, 0)
        row.amount:SetJustifyH("RIGHT")
        row.name:SetPoint("RIGHT", row.amount, "LEFT", -8, 0)
        row:Hide()
        V.profRows[i] = row
    end
end

local function PaintProfessions()
    local p = V.prof
    local result = LQ.Professions(filter)
    local rows = result and result.rows or nil
    local has = rows and #rows > 0
    p.art:SetShown(not has); p.head:SetShown(not has); p.body:SetShown(not has)
    for i, row in ipairs(V.profRows) do
        local r = has and rows[i] or nil
        if r then
            row:Show()
            if r.icon then row.icon:SetTexture(r.icon) end
            row.name:SetText(tostring(r.name or "") .. (r.partial and " (partial)" or ""))
            row.amount:SetText(type(r.amount) == "number" and LQ.Money(r.amount, true) or "")
            UI.Paint(row.amount, (type(r.amount) == "number" and r.amount < 0) and K.ember or K.sage)
        else
            row:Hide()
        end
    end
    V.profShown = has and true or false
end

---------------------------------------------------------------------------
-- Transactions
---------------------------------------------------------------------------
local function RowTip(self)
    local d = self.data
    if not (d and GameTooltip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = false
    if d.item then shown = pcall(GameTooltip.SetItemByID, GameTooltip, d.item) end
    if not shown then
        GameTooltip:ClearLines()
        GameTooltip:AddLine(d.text, 1, 0.82, 0)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(LQ.Stamp(d.t), K.textDim[1], K.textDim[2], K.textDim[3])
    GameTooltip:AddLine((d.a > 0 and "Gold in: " or "Gold out: ") .. LQ.Money(d.a, true), (d.a > 0 and K.sage or K.ember)[1], (d.a > 0 and K.sage or K.ember)[2], (d.a > 0 and K.sage or K.ember)[3])
    GameTooltip:AddLine("Source: " .. LQ.ROW_LABELS[d.code] .. (d.attributed and " (confirmed)" or " (not identified)"), K.text[1], K.text[2], K.text[3])
    local words = R.Ledger and R.Ledger.EVIDENCE and R.Ledger.EVIDENCE[d.evidence or "balance"]
    if words then GameTooltip:AddLine(words, K.textDim[1], K.textDim[2], K.textDim[3], true) end
    for _, line in ipairs(LQ.AuctionDetails(d)) do GameTooltip:AddLine(line, K.text[1], K.text[2], K.text[3], true) end
    if filter.scope == "all" and d.char then GameTooltip:AddLine("Character: " .. d.char, K.stone[1], K.stone[2], K.stone[3]) end
    GameTooltip:Show()
end

local function MakeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row, 6)
    local rule = UI.Rule(row, 0.18)
    rule:SetPoint("BOTTOMLEFT", 4, 0); rule:SetPoint("BOTTOMRIGHT", -4, 0)
    row.time = UI.Text(row, 12, K.textDim)   -- dimmer than the source, so the eye finds the source and the amount first
    row.time:SetPoint("LEFT", 8, 0)
    row.time:SetWidth(92)
    row.srcIcon = row:CreateTexture(nil, "ARTWORK")
    row.srcIcon:SetSize(18, 18)
    row.srcIcon:SetPoint("LEFT", 104, 0)
    row.src = UI.Text(row, 12, K.text)
    row.src:SetPoint("LEFT", row.srcIcon, "RIGHT", 6, 0)
    row.src:SetWidth(112)
    row.src:SetHeight(ROW_H - 2)
    row.itemIcon = row:CreateTexture(nil, "ARTWORK")
    row.itemIcon:SetSize(16, 16)
    row.itemIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.amount = UI.Text(row, 13, K.text, "strong")
    row.amount:SetPoint("RIGHT", -8, 0)
    row.amount:SetWidth(106)
    row.amount:SetJustifyH("RIGHT")
    row.note = UI.Text(row, 12, K.text)
    row.TipEnter = RowTip
    row.TipLeave = function() if GameTooltip then GameTooltip:Hide() end end
    row.fill = function(self, d)
        self.data = d
        self.time:SetText(date("!%b %d  %H:%M", d.t))
        UI.Art(self.srcIcon, LQ.ART[d.code] or LQ.ART.other, 18)
        self.src:SetText(LQ.ROW_LABELS[d.code])
        self.src:SetWordWrap(d.code == "ahCancelFee")
        UI.Paint(self.src, d.attributed and K.text or K.textDim)
        self.note:ClearAllPoints()
        local x = 232
        if d.item then
            self.itemIcon:ClearAllPoints()
            self.itemIcon:SetPoint("LEFT", self, "LEFT", x, 0)
            self.itemIcon:SetTexture(LQ.ItemIcon(d.item) or UI.ICON_BLANK)
            self.itemIcon:Show()
            x = x + 22
        else
            self.itemIcon:Hide()
        end
        self.note:SetPoint("LEFT", self, "LEFT", x, 0)
        self.note:SetPoint("RIGHT", self.amount, "LEFT", -8, 0)
        self.note:SetText(filter.scope == "all" and d.char and (d.text .. " \194\183 " .. d.char) or d.text)
        self.amount:SetText(LQ.Money(d.a, true))
        UI.Paint(self.amount, d.a > 0 and K.sage or K.ember)
    end
    return row
end

local function BuildTransactions()
    local p = Panel(page, "Recent Transactions", "npc:sealed-scroll")
    p:SetSize(MID_L, BOT_H)
    p:SetPoint("TOPLEFT", page, "TOPLEFT", 0, BOT_TOP)
    V.tx = p
    p.count = UI.Text(p, 11, K.stone)
    p.count:SetPoint("TOPRIGHT", -14, -13)
    p.count:SetJustifyH("RIGHT")
    for _, h in ipairs({ { "Time (UTC)", 92, 12 }, { "Source", 112, 128 }, { "Item / Note", 200, 232 } }) do
        local fs = UI.Head(p, h[1], h[2], "LEFT")
        fs:SetPoint("TOPLEFT", p, "TOPLEFT", h[3], -32)
    end
    local amountHead = UI.Head(p, "Amount", 106, "RIGHT")
    amountHead:SetPoint("TOPRIGHT", p, "TOPRIGHT", -30, -32)
    local rule = UI.Rule(p, 0.45)
    rule:SetPoint("TOPLEFT", 10, -48); rule:SetPoint("TOPRIGHT", -10, -48)
    local list = UI.List(p, ROW_H, MakeRow, ROW_H * 4, false)
    list.box:SetPoint("TOPLEFT", 6, -50)
    list.box:SetPoint("BOTTOMRIGHT", -6, 6)
    UI.lists.ledger = list
    V.list = list
end

local function EmptyText(s)
    if filter.search ~= "" or filter.source then return "No transactions match these filters." end
    if not (s and s.recording) then
        local st = R.Ledger and R.Ledger.Status()
        if st and st.why == "held" then return "The Gold Ledger was saved by a newer TwichUI and is being kept unchanged. Nothing is recorded until TwichUI is updated." end
        return "Nothing recorded yet. The ledger counts the gold this character gains and spends while the Workshop is on. Earn or spend a little gold and it will appear here."
    end
    return "No gold changes recorded in the last " .. filter.days .. " days. Gold you gain or spend while the Workshop is on appears here."
end

local function PaintTransactions(s)
    local rows, more = LQ.Rows(filter, nil, LQ.MAX_ROWS)
    V.rows = rows
    V.list:SetData(rows, #rows == 0 and EmptyText(s) or nil)
    V.tx.count:SetText(#rows == 0 and "" or (more and ("Newest %d shown"):format(#rows) or ("%d %s"):format(#rows, #rows == 1 and "transaction" or "transactions")))
end

---------------------------------------------------------------------------
-- Filters and the page's own status line
---------------------------------------------------------------------------
local function Status(s)
    local L = R.Ledger
    local st = L and L.Status() or {}
    if st.why == "held" then return "Not recording: saved by a newer TwichUI" end
    if st.why == "off" then return "Not recording: Workshop is off" end
    if st.why then return "Not recording" end
    local since = s and s.coverage.since or st.since
    if since then return "Recording since " .. LQ.Day(math.floor(since / 86400)) .. " (UTC) \194\183 older gold is not counted" end
    return "Recording starts when you next gain or spend gold"
end

local function BuildFilters()
    V.scope = Dropdown(page, 168, SCOPES, function() return filter.scope end, function(v) V.SetFilter("scope", v) end)
    V.scope:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -46)
    for _, code in ipairs(R.Ledger and R.Ledger.ORDER or {}) do SOURCES[#SOURCES + 1] = { code, LQ.LABELS[code] } end
    V.source = Dropdown(page, 168, SOURCES, function() return filter.source or "all" end, function(v) V.SetFilter("source", v ~= "all" and v or nil) end)
    V.source:SetPoint("TOPLEFT", V.scope, "TOPRIGHT", 10, 0)
    V.status = UI.Text(page, 11, K.stone)
    V.status:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -53)
    V.status:SetJustifyH("RIGHT")
    V.search = UI.Search(page, 260, 28, "Search transactions")
    V.search:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -4)
    V.search:HookScript("OnTextChanged", function(box)
        local text = box:GetText() or ""
        if text == filter.search then return end
        local mine = generation
        filter.search = text
        C_Timer.After(SEARCH_DELAY, function()
            if mine ~= generation or filter.search ~= text then return end
            V.Draw(true)
        end)
    end)
    UI.Tip(V.search, "Search transactions", "Narrows the list of transactions below by source, item or note. The totals and the chart count every transaction and do not change.")
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
function V.Draw(rowsOnly)
    if not (page and page:IsShown()) then stale = true return end
    local Perf = R.Perf
    local pt = Perf and Perf.on and Perf.Start("ledger.draw")
    draws = draws + 1
    stale = false
    local qt = Perf and Perf.on and Perf.Start("ledger.query")
    local s = LQ.Summary(filter)
    if qt then Perf.Stop(qt) end
    V.summary = s
    PaintCards(s)
    for days, b in pairs(V.flow.ranges) do b:SetOn(days == filter.days) end
    V.scope:Refresh(); V.source:Refresh()
    V.status:SetText(Status(s))
    V.chart:Set(s)
    PaintSources(s)
    PaintTransactions(s)
    PaintProfessions()
    if pt then Perf.Stop(pt) end
end

function V.SetFilter(key, value)
    if key == "scope" then filter.scope = value == "all" and "all" or "current"
    elseif key == "source" then filter.source = (type(value) == "string" and LQ.LABELS[value]) and value or nil
    elseif key == "days" then filter.days = (value == 30 or value == 90) and value or 7
    elseif key == "search" then
        filter.search = type(value) == "string" and value or ""
        if V.search and (V.search:GetText() or "") ~= filter.search then V.search:SetText(filter.search) end
    else return end
    if V.list then V.list:ScrollTop() end
    V.Draw()
end

-- The recorder changed. While the page is shown this is one redraw after a short wait; while it is hidden, only a note that it is out of date.
local function Changed()
    if not (page and page:IsShown()) then stale = true return end
    if drawPending then return end
    drawPending = true
    local mine = generation
    C_Timer.After(DRAW_DELAY, function()
        drawPending = false
        if mine ~= generation then return end
        V.Draw()
    end)
end
V.Changed = Changed

local function Subscribe()
    if subscribed or not R.Ledger then return end
    subscribed = true
    R.Ledger.Subscribe(Changed)
end
local function Unsubscribe()
    if not subscribed then return end
    subscribed = false
    if R.Ledger then R.Ledger.Unsubscribe(Changed) end
end
function V.Subscribed() return subscribed end

local function Render()
    Subscribe()
    V.Draw()
end

local function Reset()
    generation = generation + 1
    drawPending = false
    Unsubscribe()
    if V.chart then V.chart:ClearInspection() end
    if GameTooltip then GameTooltip:Hide() end
end

local function Build(p)
    page = p
    K = UI.K
    V.page = p
    BuildFilters()
    BuildCards()
    BuildFlow()
    BuildSources()
    BuildTransactions()
    BuildProfessions()
    -- leaving the page releases the subscription at once (the window's hide releases it too)
    p:HookScript("OnHide", function() generation = generation + 1; drawPending = false; Unsubscribe() end)
end

UI.Register({
    key = "ledger", nav = "Gold Ledger", icon = "npc:coins",
    title = "Gold Ledger", sub = "",
    tip = "Gold you gained and spent, by source and by day, since recording began. Observed movement, not profit.",
    Build = Build, Render = Render, Reset = Reset,
})
