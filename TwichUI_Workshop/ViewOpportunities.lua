-- TwichUI Workshop: the Opportunities page (a list and the chosen recipe's details)
-- For every recipe read this session (all professions seen), ONE craft: Cost to make, Sell price and Estimated profit from the prices of the
-- last auction house scan (Session.Opportunities, which prices through Market.Price; nothing is calculated here). Profession segments filter,
-- the money headings sort, Profitable only hides losses and unknowns. Choosing a row shows its details beside the list: the materials of one
-- craft and what the saved scan and its history say about what it makes, each figure labelled for what it is (cheapest listings, not sales).
-- The Scan prices button starts the player's own scan (Session.StartScan); its progress is shown while it runs.

local R = TwichUI
local W = R.Workshop
local S, O, PR, Op, SC, MK = W.Session, W.Observe, W.Prices, W.Opps, W.Scan, W.Market
local UI = W.UI

local OPP_H, COL_W, DETAIL_W = 46, 92, 236
local MAT_ROWS = 3
local RIGHT = 10   -- a row's right margin before the profit column

local K
local page, opps
local chips = {}
local oppView      -- what the last draw was built from (the basis tooltips read it)
local selected     -- the recipe whose details are shown (memory only)

local function IsShift() return IsShiftKeyDown and IsShiftKeyDown() == true end

-- One money column of a row: a value, and under it "to <highest>" when the amount is a range (an uncertain output)
local function MakeCell(row, right)
    local c = {}
    c.a = UI.Text(row, 14, K.text)
    c.a:SetWidth(COL_W)
    c.a:SetJustifyH("RIGHT")
    c.b = UI.Text(row, 12, K.stone)
    c.b:SetWidth(COL_W)
    c.b:SetJustifyH("RIGHT")
    function c.Set(low, high, color)
        c.a:ClearAllPoints()
        c.b:ClearAllPoints()
        if high then
            c.a:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -7)
            c.b:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -25)
            c.b:SetText("to " .. high)
            c.b:Show()
        else
            c.a:SetPoint("RIGHT", row, "RIGHT", right, 0)
            c.b:SetText("")
            c.b:Hide()
        end
        c.a:SetText(low)
        UI.Paint(c.a, color or K.text)
    end
    return c
end

local function Known(cell, low, high)   -- a known amount, or "Unknown" in the dim colour
    if low == nil then cell.Set("Unknown", nil, K.stone)
    else cell.Set(UI.Money(low), high ~= nil and high ~= low and UI.Money(high) or nil) end
end

local function Source()
    local mk = oppView and oppView.source.market
    return mk and { label = oppView.source.label, at = mk.at, complete = mk.complete } or nil
end

-- The short tooltip; Shift (held while hovering, or pressed during it) shows the details instead
local function ShowBasis(row)
    if not (GameTooltip and row.data and oppView) then return end
    UI.hoverRow = row
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local src = Source()
    local lines = IsShift() and Op.Basis(row.data, src, UI.ItemName, UI.Money) or Op.Tip(row.data, src, UI.Money)
    for i, line in ipairs(lines) do
        local text = line[1]
        if line[2] then
            GameTooltip:AddDoubleLine(text, line[2], 0.8, 0.8, 0.8, 1, 1, 1)
        elseif i == 1 then
            GameTooltip:AddLine(text, 1, 0.82, 0)
        elseif text:sub(1, 1) == "!" then
            GameTooltip:AddLine(text:sub(2), 1, 0.82, 0.3, true)
        elseif text:sub(1, 1) == "~" then
            GameTooltip:AddLine(text:sub(2), 0.55, 0.55, 0.55)
        else
            GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
        end
    end
    GameTooltip:Show()
end

local function ProfitTone(e)
    if e.state ~= "ok" then return K.stone end
    return e.profitLow > 0 and K.sage or (e.profitHigh < 0 and K.ember or K.text)
end

local function MakeOppRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row)
    local rule = UI.Rule(row, 0.25)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(34, 34)
    row.iconBtn:SetPoint("LEFT", 6, 0)
    row.iconFrame = UI.ItemIcon(row.iconBtn, 34)
    row.iconFrame:SetAllPoints()
    row.icon = row.iconFrame.tex
    UI.ItemTip(row.iconBtn, function() return row.item end)
    row.profit = MakeCell(row, -RIGHT)
    row.sell = MakeCell(row, -(RIGHT + COL_W + 6))
    row.cost = MakeCell(row, -(RIGHT + 2 * (COL_W + 6)))
    row.name = UI.Text(row, 14, K.text)
    row.name:SetPoint("TOPLEFT", row.iconBtn, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(RIGHT + 3 * (COL_W + 6)), 0)
    row.sub = UI.Text(row, 12, K.stone)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.sub:SetPoint("RIGHT", row.name, "RIGHT", 0, 0)
    row.ShowTip = ShowBasis
    row:SetScript("OnEnter", ShowBasis)
    row:SetScript("OnLeave", function(self)
        if UI.hoverRow == self then UI.hoverRow = nil end
        if GameTooltip then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        if self.rec then selected = self.rec.id; UI.Redraw() end
    end)
    row.fill = function(self, r)
        local e, rec = r.est, r.rec
        self.data, self.rec, self.item = r, rec, rec.outItem
        local _, icon
        if rec.outItem then _, icon = O.ItemFacts(rec.outItem) end
        self.icon:SetTexture(icon or rec.icon or UI.ICON_BLANK)
        self.name:SetText(rec.name)
        local makes = W.PerCraft(e.outMin, e.outMax)
        local detail = makes and ("Makes " .. makes) or "Makes: unknown"
        if rec.profName then detail = detail .. "  -  " .. rec.profName end
        if e.state ~= "ok" then detail = (Op.WhyText(e) or "Not priced") end
        -- whether one craft's materials are in the bags or in storage (asked only for the rows drawn; never part of the estimate)
        r.avail = r.avail or (oppView and oppView.avail and oppView.avail(rec)) or nil
        local word = e.state == "ok" and Op.AvailWord(r.avail) or nil
        if word then detail = detail .. "  -  " .. word end
        local queued = S.IsQueued(rec.id)
        if queued then detail = detail .. "  -  In your queue" end
        self.sub:SetText(detail)
        UI.Paint(self.sub, e.state ~= "ok" and K.bronzeText or (word and (r.avail.state == "ready" and K.sage or K.bronzeText))
            or (queued and K.sage) or K.stone)
        Known(self.cost, e.cost)
        Known(self.sell, e.sellLow, e.sellHigh)
        if e.state == "ok" then
            self.profit.Set(UI.Money(e.profitLow), e.profitHigh ~= e.profitLow and UI.Money(e.profitHigh) or nil, ProfitTone(e))
        else
            self.profit.Set("Unknown", nil, K.stone)
        end
        self:SetSelected(rec.id == selected)
    end
    return row
end

---------------------------------------------------------------------------
-- The chosen recipe's details
---------------------------------------------------------------------------
local function Range(a, b, f) if a == b or b == nil then return f(a) end return f(a) .. " to " .. f(b) end

-- What the saved scan and its history say about the item one craft makes, as label / value pairs: plain facts, each labelled for what it is
-- (the cheapest listings a scan saw, never a sale price or a market value)
local function Evidence(item, market)
    if not (item and market) then return { { "Auction prices", "none saved yet" } } end
    local out = {}
    local p, why = MK.Price(item, { market = market })
    if p then
        out[#out + 1] = { ("Cheapest listing (%d %s)"):format(p.listings or 0, UI.Plural(p.listings or 0, "listing", "listings")), UI.Money(p.price) }
    else
        out[#out + 1] = { "Cheapest listing", why == "unlisted" and "none in the last scan" or "unknown" }
    end
    local st = MK.Stats(item, "week", { market = market })
    if st and not st.single then
        out[#out + 1] = { ("7-day lows (%d %s)"):format(st.n, UI.Plural(st.n, "day", "days")), UI.Money(st.low) .. " - " .. UI.Money(st.high) }
    else
        out[#out + 1] = { "Price history", st and "one day so far" or "not yet" }
    end
    return out
end

local function RenderDetail(rows)
    local d = page.detail
    local r
    for _, x in ipairs(rows) do if x.rec.id == selected then r = x end end
    if not r and rows[1] then r = rows[1]; selected = r.rec.id end
    local shown = r ~= nil
    d.head:SetShown(shown)
    d.body:SetShown(shown)
    d.add:SetShown(shown)
    d.empty:SetShown(not shown)
    if not shown then
        selected = nil
        d.empty:SetText(oppView and oppView.empty or "Choose a recipe to see its details.")
        return
    end
    local e, rec = r.est, r.rec
    local _, icon
    if rec.outItem then _, icon = O.ItemFacts(rec.outItem) end
    d.icon:SetTexture(icon or rec.icon or UI.ICON_BLANK)
    d.name:SetText(rec.name)
    d.prof:SetText(rec.profName or "")
    d.profitLabel:SetText(Op.ProfitLabel(r))
    if e.state == "ok" then
        d.profit:SetText(Range(e.profitLow, e.profitHigh, UI.Money))
        UI.Paint(d.profit, ProfitTone(e))
        d.why:SetText("")
    else
        d.profit:SetText("Unknown")
        UI.Paint(d.profit, K.stone)
        d.why:SetText(Op.WhyText(e) or "Not priced")
    end
    d.cost:SetText(e.cost and UI.Money(e.cost) or "Unknown")
    d.sell:SetText(e.sellLow and Range(e.sellLow, e.sellHigh, UI.Money) or "Unknown")
    -- materials of one craft
    local n = #(e.mats or {})
    for i, line in ipairs(d.mats) do
        local m = e.mats and e.mats[i]
        if m and i <= MAT_ROWS then
            local _, mi = O.ItemFacts(m.item)
            line.icon:SetTexture(mi or UI.ICON_BLANK)
            line.name:SetText(("%d x %s"):format(m.qty, UI.ItemName(m.item)))
            line.value:SetText(m.total and UI.Money(m.total) or (m.unavailable == "few" and "too few" or "no price"))
            UI.Paint(line.value, m.total and K.textDim or K.bronzeText)
            line:Show()
        else
            line:Hide()
        end
    end
    d.more:SetText(n > MAT_ROWS and ("+%d more (hold Shift over the row)"):format(n - MAT_ROWS) or (n == 0 and "Not known yet." or ""))
    -- what the market data says about what it makes
    local ev = Evidence(rec.outItem, oppView and oppView.source.market)
    for i, pair in ipairs(d.evidence) do
        local x = ev[i]
        pair.l:SetText(x and x[1] or "")
        pair.v:SetText(x and x[2] or "")
    end
    if S.IsQueued(rec.id) then
        d.add.text:SetText("In your queue")
        d.add:SetEnabled(false)
    else
        d.add.text:SetText("Add to crafting plan")
        d.add:SetEnabled(true)
    end
    d.rec = rec
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local SORT_WORDS = { profit = "profit", cost = "Cost to make", sell = "Sell price" }

local function LayoutChips(list)
    local n = #list + 1
    for i = 1, math.max(n, #chips) do
        local b = chips[i]
        local p = i == 1 and { id = nil, name = "All", selected = S.opp.prof == nil } or list[i - 1]
        if i <= n then
            if not b then
                b = UI.Segment(opps, "", 80, function(self)
                    S.FilterProfession(self.profId)
                    UI.lists.opps:ScrollTop()
                    UI.Redraw()
                end)
                chips[i] = b
            end
            local w = math.max(56, math.min(112, math.floor((560 - 4 * (n - 1)) / n)))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", opps, "TOPLEFT", (i - 1) * (w + 4), -66)
            b.profId = p.id
            b.text:SetText(p.name)
            b:SetOn(i == 1 and S.opp.prof == nil or (i > 1 and S.opp.prof == p.id))
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

local function Render()
    local v = S.Opportunities()
    oppView = v
    local src = v.source

    -- where the prices come from: the auction house and how old, in a few words
    local sourceText
    if src.market then
        sourceText = ("Prices: %s \194\183 %s"):format(src.label, Op.ScanWords({ at = src.market.at, complete = src.market.complete }) or "")
    elseif src.open then
        sourceText = "No saved prices for this auction house yet."
    else
        sourceText = "No saved prices for this realm yet."
    end
    opps.source:SetText(sourceText)

    -- the latest scan attempt
    local msg, tone = SC.Message()
    opps.status:SetText(msg or "")
    UI.Paint(opps.status, tone == "good" and K.sage or (tone == "warn" and K.bronzeText or K.textDim))
    local busy = SC.Busy()
    opps.scan.text:SetText(busy and "Scanning..." or "Scan prices")
    opps.scan:SetEnabled(not busy)
    if busy then
        local frac = SC.Progress() or 0
        opps.bar:Set(frac, W.AuctionButton.BarText(msg, frac))
        opps.bar:Show()
    else
        opps.bar:Hide()
    end

    -- filters and the sort
    LayoutChips(S.Professions())
    opps.profitOnly:SetOn(S.opp.profitOnly)
    for key, h in pairs(UI.heads) do
        if key == "profit" then h.text:SetText(v.rate and "Estimated profit" or "Profit before fees") end
        UI.Paint(h.text, S.opp.sort == key and K.bronzeText or K.stone)
        h.tipBody = (S.opp.sort == key and (S.opp.desc and "Highest first. Click to show the lowest first."
            or "Lowest first. Click to show the highest first.") or "Click to sort by this.")
    end

    -- the list and the chosen row
    RenderDetail(v.rows)
    UI.lists.opps:SetData(v.rows, v.empty)
    local sum = v.summary
    if sum.total > 0 then
        opps.summary:SetText(("%d of %d priced \194\183 %d profitable \194\183 %s, %s first")
            :format(sum.priced, sum.total, sum.profitable, SORT_WORDS[S.opp.sort]:lower(), S.opp.desc and "highest" or "lowest"))
    else
        opps.summary:SetText("")
    end
    -- one short line; the longer explanation is behind "About prices"
    local note = ""
    if sum.total > 0 then
        note = v.rate and "Profit is after the auction house's cut." or "Profit is before fees: the auction house's cut isn't confirmed."
        if v.incomplete then note = note .. " Some recipes may be missing." end
    end
    opps.notes:SetText(note)
    opps.about:SetShown(sum.total > 0)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function BuildDetail()
    local d = CreateFrame("Frame", nil, opps)
    d:SetPoint("TOPRIGHT", 0, -140)
    d:SetPoint("BOTTOMRIGHT", 0, 46)
    d:SetWidth(DETAIL_W)
    UI.Panel(d, "card")
    page.detail = d
    -- the head: the picture, the name (one or two lines) and the profession
    d.head = CreateFrame("Frame", nil, d)
    d.head:SetAllPoints()
    d.iconFrame = UI.ItemIcon(d.head, 40)
    d.iconFrame:SetPoint("TOPLEFT", 12, -12)
    d.icon = d.iconFrame.tex
    d.name = UI.Text(d.head, 16, K.text, "serif")
    d.name:SetPoint("TOPLEFT", 60, -12)
    d.name:SetWidth(DETAIL_W - 60 - 12)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(2)
    d.name:SetJustifyV("TOP")
    d.prof = UI.Text(d.head, 12, K.stone)
    d.prof:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
    -- the body hangs under the profession line, so a name of one line or two pushes it down (never under the picture)
    local body = CreateFrame("Frame", nil, d)
    body:SetPoint("TOPLEFT", d.prof, "BOTTOMLEFT", -60, -10)
    body:SetPoint("BOTTOMRIGHT", 0, 52)
    d.body = body
    local y = 0
    local function Pair(label, big)
        local l = UI.Text(body, 12, K.stone)
        l:SetPoint("TOPLEFT", 12, y - (big and 4 or 0))
        l:SetText(label)
        local v = UI.Text(body, big and 17 or 13, K.text, big and "strong" or nil)
        v:SetPoint("TOPRIGHT", -12, y + (big and 0 or 1))
        v:SetJustifyH("RIGHT")
        y = y - (big and 24 or 19)
        return l, v
    end
    d.profitLabel, d.profit = Pair("Profit before fees", true)
    d.why = UI.Text(body, 12, K.bronzeText)
    d.why:SetPoint("TOPLEFT", 12, y + 4)
    d.why:SetPoint("RIGHT", -12, 0)
    local _; _, d.cost = Pair("Cost to make")
    _, d.sell = Pair("Sell price (listing)")
    local r1 = UI.Rule(body, 0.45)
    r1:SetPoint("TOPLEFT", 12, y - 2); r1:SetPoint("TOPRIGHT", -12, y - 2)
    y = y - 10
    local mh = UI.Text(body, 13, K.bronzeText, "strong")
    mh:SetPoint("TOPLEFT", 12, y)
    mh:SetText("Materials (one craft)")
    y = y - 19
    d.mats = {}
    for i = 1, MAT_ROWS do
        local line = CreateFrame("Frame", nil, body)
        line:SetHeight(18)
        line:SetPoint("TOPLEFT", 12, y)
        line:SetPoint("TOPRIGHT", -12, y)
        line.icon = line:CreateTexture(nil, "ARTWORK")
        line.icon:SetSize(16, 16)
        line.icon:SetPoint("LEFT", 0, 0)
        line.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        line.value = UI.Text(line, 12, K.textDim)
        line.value:SetPoint("RIGHT", 0, 0)
        line.value:SetJustifyH("RIGHT")
        line.name = UI.Text(line, 12, K.text)
        line.name:SetPoint("LEFT", line.icon, "RIGHT", 6, 0)
        line.name:SetPoint("RIGHT", line.value, "LEFT", -6, 0)
        d.mats[i] = line
        y = y - 18
    end
    d.more = UI.Text(body, 11, K.stone)
    d.more:SetPoint("TOPLEFT", 12, y - 1)
    d.more:SetPoint("RIGHT", -12, 0)
    y = y - 16
    local r2 = UI.Rule(body, 0.45)
    r2:SetPoint("TOPLEFT", 12, y); r2:SetPoint("TOPRIGHT", -12, y)
    y = y - 8
    local eh = UI.Text(body, 13, K.bronzeText, "strong")
    eh:SetPoint("TOPLEFT", 12, y)
    eh:SetText("At the auction house")
    y = y - 19
    d.evidence = {}
    for i = 1, 2 do
        local l = UI.Text(body, 12, K.stone)
        l:SetPoint("TOPLEFT", 12, y)
        local v = UI.Text(body, 12, K.textDim)
        v:SetPoint("TOPRIGHT", -12, y)
        v:SetJustifyH("RIGHT")
        l:SetPoint("RIGHT", v, "LEFT", -6, 0)
        d.evidence[i] = { l = l, v = v }
        y = y - 18
    end
    UI.Tip(body, "What these figures are", "Prices are the cheapest buyout listings your scans saw, per item. The 7-day lows are the lowest and highest of each scanned day's cheapest listing. None of them is a sale price or a promise that it will sell.")
    d.add = UI.Button(d, "Add to crafting plan", DETAIL_W - 24, "primary", function()
        if d.rec then S.Add(d.rec); UI.Redraw() end
    end, 30)
    d.add:SetPoint("BOTTOMLEFT", 12, 12)
    d.add:SetPoint("BOTTOMRIGHT", -12, 12)
    UI.Tip(d.add, "Add to crafting plan", "Puts this recipe in the queue to make once, in the Crafting page. Nothing is bought or crafted.")
    d.empty = UI.Text(d, 13, K.textDim)
    d.empty:SetPoint("TOPLEFT", 14, -16)
    d.empty:SetPoint("RIGHT", -14, 0)
    d.empty:SetWordWrap(true)
    d.empty:SetJustifyV("TOP")
end

local function Build(p)
    page, opps, K = p, p, UI.K
    opps.scan = UI.Button(opps, "Scan prices", 140, "primary", function()
        S.StartScan()
        UI.Redraw()
    end, 30)
    opps.scan:SetPoint("TOPRIGHT", -2, -2)
    UI.Tip(opps.scan, "Scan prices", "Reads every listing at the open auction house once, so your crafts can be priced. It only reads: it never buys, bids or posts, and it starts only when you press this. It can take a little while.")
    opps.bar = W.NewBar(opps, 300, 20)           -- the overall progress of a scan, shown only while one runs
    opps.bar:SetPoint("TOPRIGHT", opps.scan, "BOTTOMRIGHT", 0, -6)
    opps.bar:Hide()
    opps.profitOnly = UI.Switch(opps, "Profitable only", function()
        S.ToggleProfitOnly()
        UI.lists.opps:ScrollTop()
        UI.Redraw()
    end)
    opps.profitOnly:SetPoint("TOPRIGHT", -2, -69)
    UI.Tip(opps.profitOnly, "Profitable only", "Hides crafts that lose money at these prices and crafts that couldn't be priced.")
    opps.source = UI.Text(opps, 13, K.textDim)
    opps.source:SetPoint("TOPLEFT", 1, -102)
    opps.source:SetPoint("RIGHT", -2, 0)
    opps.status = UI.Text(opps, 13, K.textDim)
    opps.status:SetPoint("TOPLEFT", 1, -120)
    opps.status:SetPoint("RIGHT", -2, 0)

    -- the list
    local card = CreateFrame("Frame", nil, opps)
    card:SetPoint("TOPLEFT", 0, -140)
    card:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 12), 46)
    UI.Panel(card, "card")
    opps.card = card
    local x = -(4 + 16)   -- a row's right edge in the card: the list's inset and its scroll gutter
    local function Head(key, text, right, w)
        local h = CreateFrame("Button", nil, card)
        h:SetSize(w, 18)
        h:SetPoint("TOPRIGHT", card, "TOPRIGHT", right, -12)
        h.text = UI.Head(h, text, w)
        h.text:SetAllPoints()
        h:SetScript("OnClick", function() S.SortBy(key); UI.lists.opps:ScrollTop(); UI.Redraw() end)
        h:SetScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(text, 1, 0.82, 0)
                GameTooltip:AddLine(self.tipBody or "Click to sort by this.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        h:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        UI.heads[key] = h
    end
    local item = UI.Head(card, "Recipe (one craft)", 160, "LEFT")
    item:SetPoint("TOPLEFT", 14, -14)
    -- the profit heading is the longest ("Profit before fees"): it may reach into the sell column's empty left side
    Head("profit", "Estimated profit", x - RIGHT, COL_W + 20)
    Head("sell", "Sell price", x - (RIGHT + COL_W + 6), COL_W - 24)
    Head("cost", "Cost to make", x - (RIGHT + 2 * (COL_W + 6)), COL_W)
    local rule = UI.Rule(card, 0.45)
    rule:SetPoint("TOPLEFT", 12, -32); rule:SetPoint("TOPRIGHT", -12, -32)
    local list = UI.List(card, OPP_H, MakeOppRow, 304, false)
    list.box:SetPoint("TOPLEFT", 4, -34)
    list.box:SetPoint("BOTTOMRIGHT", -4, 4)
    UI.lists.opps = list

    BuildDetail()

    opps.summary = UI.Text(opps, 13, K.textDim)
    opps.summary:SetPoint("BOTTOMLEFT", 1, 24)
    opps.summary:SetPoint("RIGHT", -150, 0)
    opps.notes = UI.Text(opps, 12, K.stone)
    opps.notes:SetPoint("BOTTOMLEFT", 1, 6)
    opps.notes:SetPoint("RIGHT", -150, 0)
    opps.about = UI.Button(opps, "About prices", 130, "secondary", function() end, 28)
    opps.about:SetPoint("BOTTOMRIGHT", -2, 4)
    UI.Tip(opps.about, "About these prices",
        "Cheapest buyout listings from your last scan, per item. A listing isn't a sale: it may not sell at that price, or at all. "
        .. "Deposits, unsold listings and selling time aren't counted. The auction house's cut is taken off only once it is confirmed. "
        .. "Some professions list only what their window's filters allow, so a few recipes may be missing. "
        .. "Hover a row for its numbers; hold Shift for the details.")
end

UI.Register({
    key = "opps", nav = "Opportunities", icon = "npc:coins",
    title = "Opportunities", sub = "Crafts from your known recipes, ranked by what one craft may earn.",
    tip = "Which crafts could be worth making, from the prices of your last auction house scan.",
    Build = Build, Render = Render,
    Reset = function() oppView = nil; selected = nil end,
})
