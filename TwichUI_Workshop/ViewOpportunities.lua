-- TwichUI Workshop: the Opportunities page (a list and the chosen recipe's details)
-- For every recipe read this session (all professions seen), ONE craft: Cost to make, Sell price and Estimated profit from the prices of the
-- last auction house scan (Session.Opportunities, which prices through Market.Price; nothing is calculated here). Profession segments filter,
-- the money headings sort (each shows its direction), and the list opens on the most profitable craft first. Choosing a row shows its details
-- beside the list: the profit, what a craft costs and sells for, the materials of one craft (each with its item tooltip), and what the saved
-- scan and its history say about what it makes, drawn from the days actually observed. The Scan prices button starts the player's own scan
-- (Session.StartScan); its progress is shown while it runs. The market source and age are in the window's footer and the status tooltip.
-- P2: the details also hold a compact Crafting Strategy (Session.OppStrategy: the multilevel planner for one craft on its own: what buying the
-- ingredients directly costs, the optimized economic cost, the cash needed now and the savings) and View strategy. It is a separate, labelled
-- reference: the row's cost, profit and the list's sort are still the one-level estimate above it, and nothing here changes them.

local R = TwichUI
local W = R.Workshop
local S, O, PR, Op, SC, MK, Q = W.Session, W.Observe, W.Prices, W.Opps, W.Scan, W.Market, W.Queue
local UI = W.UI
local F = W.Facts
local Sg = W.Strategy

local OPP_H, COL_W, DETAIL_W = 52, 80, 400
local MAT_ROWS, MAT_H = 3, 22
local MK_ROW = 14          -- one market fact's row
local MK_ROWS = 7          -- most facts shown (Market.Value x4 and Competition, Supply, Data quality)
-- the details, top to bottom (all measured from the details' top edge): the head, the three money boxes, a line for why a figure is missing, the
-- Crafting Strategy block, the materials of one craft beside the market facts, then the price history, which takes what is left above the button
local BOX_Y, WHY_Y, STRAT_Y, STRAT_H, COLS_Y = -66, -112, -126, 108, -240
local MATS_W, FACT_X = 196, 212
local CHART_Y = COLS_Y - 126   -- the history's caption row (the facts column is 7 rows of 14 under its heading)
local BOTTOM = 58          -- the button's room under the chart
local RIGHT = 8   -- a row's right margin before the profit column
local TOP = -100  -- the list's top edge on the page (the chips sit above it)

local K
local page, opps
local chips = {}
local oppView      -- what the last draw was built from (the basis tooltips read it)
local selected     -- the recipe whose details are shown (memory only)

local function IsShift() return IsShiftKeyDown and IsShiftKeyDown() == true end

-- One money column of a row: a value, and under it "to <highest>" when the amount is a range (an uncertain output)
local function MakeCell(row, right, strong)
    local c = {}
    c.a = UI.Text(row, strong and 15 or 14, K.text, strong and "strong" or nil)
    c.a:SetWidth(COL_W)
    c.a:SetJustifyH("RIGHT")
    c.b = UI.Text(row, 12, K.stone)
    c.b:SetWidth(COL_W)
    c.b:SetJustifyH("RIGHT")
    function c.Set(low, high, color)
        c.a:ClearAllPoints()
        c.b:ClearAllPoints()
        if high then
            c.a:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -9)
            c.b:SetPoint("TOPRIGHT", row, "TOPRIGHT", right, -28)
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
    local rule = UI.Rule(row, 0.2)
    rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0)
    row.iconBtn = CreateFrame("Button", nil, row)
    row.iconBtn:SetSize(38, 38)
    row.iconBtn:SetPoint("LEFT", 10, 0)
    row.iconFrame = UI.ItemIcon(row.iconBtn, 38)
    row.iconFrame:SetAllPoints()
    row.icon = row.iconFrame.tex
    UI.ItemTip(row.iconBtn, function() return row.item end)
    UI.PassClicks(row.iconBtn, row)
    row.profit = MakeCell(row, -RIGHT, true)
    row.sell = MakeCell(row, -(RIGHT + COL_W + 4))
    row.cost = MakeCell(row, -(RIGHT + 2 * (COL_W + 4)))
    row.name = UI.Text(row, 14, K.text, "strong")
    row.name:SetPoint("TOPLEFT", row.iconBtn, "TOPRIGHT", 9, -2)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(RIGHT + 3 * (COL_W + 4)), 0)
    row.sub = UI.Text(row, 12, K.stone)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.sub:SetPoint("RIGHT", row.name, "RIGHT", 0, 0)
    -- the row's own tooltip goes through the row's hover (UI.Hover owns OnEnter / OnLeave), never over it
    row.ShowTip = ShowBasis
    row.TipEnter = ShowBasis
    row.TipLeave = function(self)
        if UI.hoverRow == self then UI.hoverRow = nil end
        if GameTooltip then GameTooltip:Hide() end
    end
    row:SetScript("OnClick", function(self)
        if self.rec then selected = self.rec.id; UI.Redraw() end
    end)
    row:Follow(row.iconBtn)   -- the picture takes the pointer from the row: the row stays lit while it is over the picture
    row.fill = function(self, r)
        local e, rec = r.est, r.rec
        self.data, self.rec, self.item = r, rec, rec.outItem
        local _, icon
        if rec.outItem then _, icon = O.ItemFacts(rec.outItem) end
        self.icon:SetTexture(icon or rec.icon or UI.ICON_BLANK)
        self.name:SetText(rec.name)
        -- the second line, shortest first: the profession, then what matters about this craft right now
        local detail = rec.profName or ""
        local makes = W.PerCraft(e.outMin, e.outMax)
        if e.state ~= "ok" then
            detail = Op.WhyText(e) or "Not priced"
        elseif makes and (e.outMax ~= e.outMin or (e.outMin or 1) > 1) then
            detail = detail .. " \194\183 makes " .. makes
        end
        -- whether one craft's materials are in the bags or in storage (asked only for the rows drawn; never part of the estimate)
        r.avail = r.avail or (oppView and oppView.avail and oppView.avail(rec)) or nil
        local word = e.state == "ok" and Op.AvailWord(r.avail) or nil
        if word then detail = detail .. " \194\183 " .. word end
        local queued = S.IsQueued(rec.id)
        if queued then detail = detail .. " \194\183 In your queue" end
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

-- How the history is described under the chart: the days it really covers, never more
local function ChartNote(series)
    if not series then return "" end
    local n = #series.points
    if n == 0 then return "older ranges only" end
    local note = ("%d observed %s"):format(n, UI.Plural(n, "day", "days"))
    if #series.groups > 0 then note = note .. ", plus older ranges" end
    return note
end

-- The details' Add: the chosen recipe goes into the one queue (Session.Add; a refusal is explained in the footer and the button), and the
-- page is drawn again so the row, the details and the button all say it is queued. Returns whether it was added.
local Opps = {}
W.OppsView = Opps
function Opps.AddSelected()
    local d = page and page.detail
    local rec = d and d.rec
    if not rec then return false end
    local ok = S.Add(rec)
    UI.Redraw()
    return ok
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
    -- materials of one craft, each with its item tooltip
    local n = #(e.mats or {})
    for i, line in ipairs(d.mats) do
        local m = e.mats and e.mats[i]
        if m and i <= MAT_ROWS then
            local _, mi = O.ItemFacts(m.item)
            line.item = m.item
            line.icon:SetTexture(mi or UI.ICON_BLANK)
            line.name:SetText(UI.ItemName(m.item))
            line.qty:SetText("\195\151" .. m.qty)
            line.value:SetText(m.total and UI.Money(m.total) or (m.unavailable == "few" and "too few" or "no price"))
            UI.Paint(line.value, m.total and K.textDim or K.bronzeText)
            line:Show()
        else
            line.item = nil
            line:Hide()
        end
    end
    d.more:SetText(n > MAT_ROWS and ("+%d more (Shift over the row)"):format(n - MAT_ROWS) or (n == 0 and "Not known yet." or ""))
    local used = math.min(n, MAT_ROWS)
    d.more:ClearAllPoints()
    d.more:SetPoint("TOPLEFT", d.matsCol, "TOPLEFT", 14, -(24 + used * MAT_H) + 1)
    d.more:SetPoint("RIGHT", d.matsCol, "RIGHT", -6, 0)
    -- what the market data says about what it makes (Facts: one cached read of the Market services; nothing is calculated here)
    local market = oppView and oppView.source.market
    local f = F and rec.outItem and F.Of(rec.outItem, { market = market }) or nil
    local rows = f and F.Rows(f, UI.Money) or {}   -- (the rows exist whatever the data: a missing figure says why)
    for i, pair in ipairs(d.facts) do
        local x = rows[i]
        pair.data = x
        if x then
            pair.l:SetText(x.label)
            pair.v:SetText(x.value)
            UI.Paint(pair.v, x.tone == "quiet" and K.stone or (x.tone == "dim" and K.textDim or K.text))
            pair:Show()
        else
            pair:Hide()
        end
    end
    -- the facts sit beside the materials and the history has the whole width under both (a fixed place: the strategy block never takes its room)
    local series = f and F.Chart(f) or nil
    d.chart:Set(series, UI.Money)
    d.chartNote:SetText(ChartNote(series))   -- the days the history really covers; when the listings were scanned is on the Data quality row
    d.chartTip = series and ChartNote(series) or nil
    Opps.PaintStrategy(rec)
    -- the button: what it does now (add), what already happened (queued, with a check) or why it can't (the queue is full)
    local queued = S.IsQueued(rec.id)
    local full = not queued and Q.Count() >= W.MAX_QUEUE
    d.addWhy = nil
    if queued then
        d.add.text:SetText("In your queue")
        d.add:SetEnabled(false)
        for _, part in ipairs(d.add.artParts) do part:Hide() end
        d.add.check:Show()
        d.addWhy = "This recipe is in your crafting plan. Change how many in the Crafting page."
    elseif full then
        d.add.text:SetText("Queue full")
        d.add:SetEnabled(false)
        for _, part in ipairs(d.add.artParts) do part:Show() end
        d.add.check:Hide()
        d.addWhy = ("The queue holds %d recipes and is full. Remove one in the Crafting page to add another."):format(W.MAX_QUEUE)
    else
        d.add.text:SetText("Add to crafting plan")
        d.add:SetEnabled(true)
        for _, part in ipairs(d.add.artParts) do part:Show() end
        d.add.check:Hide()
    end
    d.add.artHolder:SetAlpha(d.add:IsEnabled() and 1 or 0.7)
    d.rec = rec
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
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
            local w = math.max(56, math.min(112, math.floor((500 - 4 * (n - 1)) / n)))
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

    -- the latest scan attempt, in one short line beside the button (the full source and age are in its tooltip and the footer)
    local msg, tone = SC.Message()
    opps.status:SetText(msg or "")
    UI.Paint(opps.status, tone == "good" and K.sage or (tone == "warn" and K.bronzeText or K.textDim))
    local busy = SC.Busy()
    opps.scan.text:SetText(busy and "Scanning..." or "Scan prices")
    opps.scan:SetEnabled(not busy)
    opps.statusBox:SetShown(not busy)
    if busy then
        local frac = SC.Progress() or 0
        opps.bar:Set(frac, W.AuctionButton.BarText(msg, frac))
        opps.bar:Show()
    else
        opps.bar:Hide()
    end

    -- filters and the sort
    LayoutChips(S.Professions())
    for key, h in pairs(UI.heads) do
        if key == "profit" then h:SetLabel("Profit", v.rate and "after the cut" or "before fees") end
        h:SetSort(S.opp.sort == key, S.opp.desc)
        h.tipBody = (S.opp.sort == key and (S.opp.desc and "Highest first. Click to show the lowest first."
            or "Lowest first. Click to show the highest first.") or "Click to sort by this.")
    end

    -- the list and the chosen row
    RenderDetail(v.rows)
    UI.lists.opps:SetData(v.rows, v.empty)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Section(parent, text, y)
    local h = UI.Text(parent, 13, K.bronzeText, "strong")
    h:SetPoint("TOPLEFT", 14, y)
    h:SetText(text)
    local rule = UI.Rule(parent, 0.45)
    rule:SetPoint("TOPLEFT", 14, y - 18); rule:SetPoint("TOPRIGHT", -14, y - 18)
    return h, rule
end

local function BuildMaterialRow(parent, y)
    local line = CreateFrame("Button", nil, parent)
    line:SetHeight(MAT_H)
    line:SetPoint("TOPLEFT", 8, y)
    line:SetPoint("TOPRIGHT", -2, y)
    UI.Hover(line, 6)
    line.iconFrame = UI.ItemIcon(line, 22)
    line.iconFrame:SetPoint("LEFT", 4, 0)
    line.icon = line.iconFrame.tex
    line.value = UI.Text(line, 11, K.textDim)
    line.value:SetWidth(58)
    line.value:SetPoint("RIGHT", -4, 0)
    line.value:SetJustifyH("RIGHT")
    line.qty = UI.Text(line, 12, K.bronzeText, "strong")
    line.qty:SetWidth(22)
    line.qty:SetPoint("RIGHT", line.value, "LEFT", -2, 0)
    line.qty:SetJustifyH("RIGHT")
    line.name = UI.Text(line, 12, K.text)
    line.name:SetPoint("LEFT", line.iconFrame, "RIGHT", 6, 0)
    line.name:SetPoint("RIGHT", line.qty, "LEFT", -4, 0)
    UI.ItemTip(line, function() return line.item end)
    return line
end

-- The compact Crafting Strategy: what the multilevel planner says about making this recipe once, on its own. Four labelled figures and what to
-- do (craft, buy, collect), all from Session.OppStrategy; while it is computed the block says so and shows nothing of another recipe.
function Opps.PaintStrategy(rec)
    local d = page and page.detail
    if not d then return end
    local st = d.strat
    local state, plan, why = S.OppStrategy(rec)
    local function Pair(i, label, text, tone)
        local p = st.pairs[i]
        p.l:SetText(label)
        p.v:SetText(text or "Unknown")
        UI.Paint(p.v, text and (tone == "good" and K.sage or (tone == "quiet" and K.stone or K.text)) or K.stone)
    end
    d.stratState = state
    d.view:SetEnabled(state == "ready")
    if state ~= "ready" then
        st.status:SetText(state == "planning" and "Planning..." or (state == "failed" and "Couldn't be worked out" or "Not enough data"))
        UI.Paint(st.status, K.textDim)
        for i = 1, 4 do Pair(i, st.pairs[i].label, nil) end
        if state == "planning" then
            for i = 1, 4 do st.pairs[i].v:SetText("...") end
        end
        st.actions:SetText(state == "unknown" and (why or "") or "")
        return
    end
    local words = Sg.Summary(plan, UI.Money)
    st.status:SetText(words.status)
    UI.Paint(st.status, words.tone == "good" and K.sage or (words.tone == "warn" and K.bronzeText or K.textDim))
    Pair(1, "Buy ingredients directly", words.direct)
    Pair(2, "Optimized economic cost", words.economic)
    Pair(3, "Cash needed now", words.cash)
    Pair(4, words.savingsLabel, words.savings, words.savingsTone)
    st.actions:SetText(words.actions)
end

local function BuildDetail()
    local d = CreateFrame("Frame", nil, opps)
    d:SetPoint("TOPRIGHT", 0, -44)
    d:SetPoint("BOTTOMRIGHT", 0, 0)
    d:SetWidth(DETAIL_W)
    UI.Panel(d, "card")
    page.detail = d
    -- the head: a picture, the name (one or two lines) and the profession
    d.head = CreateFrame("Frame", nil, d)
    d.head:SetAllPoints()
    d.iconFrame = UI.ItemIcon(d.head, 46)
    d.iconFrame:SetPoint("TOPLEFT", 14, -12)
    d.icon = d.iconFrame.tex
    d.name = UI.Text(d.head, 19, K.text, "serif")
    d.name:SetPoint("TOPLEFT", 70, -12)
    d.name:SetWidth(DETAIL_W - 70 - 14)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(1)
    d.name:SetJustifyV("TOP")
    d.prof = UI.Text(d.head, 13, K.textDim)
    d.prof:SetPoint("BOTTOMLEFT", d.iconFrame, "BOTTOMRIGHT", 10, 1)
    local body = CreateFrame("Frame", nil, d)
    body:SetAllPoints()
    d.body = body
    -- the three money boxes in a row: cost to make, sell price, profit (the one-level estimate the list is ranked by)
    local bw = math.floor((DETAIL_W - 28 - 16) / 3)
    local function Box(label, i)
        local b = CreateFrame("Frame", nil, body)
        b:SetSize(bw, 42)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * (bw + 8), BOX_Y)
        UI.Panel(b, "canvas")
        local l = UI.Text(b, 11, K.stone)
        l:SetPoint("TOPLEFT", 10, -6)
        l:SetPoint("RIGHT", -6, 0)
        l:SetText(label)
        local v = UI.Text(b, 14, K.text, "strong")
        v:SetPoint("BOTTOMLEFT", 10, 6)
        v:SetPoint("RIGHT", -6, 0)
        return b, v, l
    end
    local costBox, sellBox, profitBox
    costBox, d.cost = Box("Cost to make", 1)
    sellBox, d.sell = Box("Sell price (listing)", 2)
    profitBox, d.profit, d.profitLabel = Box("Profit before fees", 3)
    d.why = UI.Text(body, 12, K.bronzeText)
    d.why:SetPoint("TOPLEFT", 14, WHY_Y)
    d.why:SetPoint("RIGHT", -14, 0)
    -- what the figures assume, in words: the existing minimum-based estimate (A7 keeps it; the selling strategy is A8), not Market Value
    UI.Tip(costBox, "Cost to make", "What one craft's materials cost at the cheapest listings your last scan saw, owned or not (owning them does not make them free). The list is ranked by this estimate, not by the strategy below.")
    UI.Tip(sellBox, "Sell price (listing)", "The lowest current listing of what it makes, from your last scan, before fees. The profit uses this. It is not the Market Value or Historical Value below, which are references from past listings, and not a promise it will sell.")
    UI.Tip(profitBox, "Profit", "Sell price minus Cost to make, as the list shows it: a one-level estimate from the cheapest listings. The Crafting Strategy below is a separate reference and does not change it.")

    -- the Crafting Strategy block
    local st = CreateFrame("Frame", nil, body)
    d.strat = st
    st:SetPoint("TOPLEFT", 14, STRAT_Y)
    st:SetPoint("TOPRIGHT", -14, STRAT_Y)
    st:SetHeight(STRAT_H)
    UI.Panel(st, "canvas")
    local sh = UI.Text(st, 13, K.bronzeText, "strong")
    sh:SetPoint("TOPLEFT", 10, -8)
    sh:SetText("Crafting strategy")
    st.status = UI.Text(st, 11, K.sage)
    st.status:SetPoint("TOPRIGHT", -10, -10)
    st.status:SetJustifyH("RIGHT")
    st.pairs = {}
    local colw = math.floor((DETAIL_W - 28 - 20) / 2)
    local LABELS = { "Buy ingredients directly", "Optimized economic cost", "Cash needed now", "Potential savings" }
    for i = 1, 4 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y = 10 + col * (colw + 0), -26 - row * 28
        local l = UI.Text(st, 11, K.stone)
        l:SetPoint("TOPLEFT", x, y)
        l:SetWidth(colw - 6)
        l:SetJustifyH("LEFT")
        local v = UI.Text(st, 13, K.text, "strong")
        v:SetPoint("TOPLEFT", x, y - 12)
        v:SetWidth(colw - 6)
        v:SetJustifyH("LEFT")
        l:SetText(LABELS[i])
        st.pairs[i] = { l = l, v = v, label = LABELS[i] }
    end
    st.actions = UI.Text(st, 12, K.textDim)
    st.actions:SetPoint("BOTTOMLEFT", 10, 10)
    st.actions:SetWidth(DETAIL_W - 28 - 20 - 110)
    st.actions:SetJustifyH("LEFT")
    d.view = UI.Button(st, "View strategy", 104, "secondary", function()
        if d.rec and UI.StrategyView then UI.StrategyView.Open("opp", d.rec) end
    end, 22)
    d.view:SetPoint("BOTTOMRIGHT", -8, 6)
    UI.Tip(d.view, "View strategy", "Shows the whole strategy for making this once: the crafting steps in order, what to buy and from where, what comes from your bags and storage, and the other ways considered.")
    st:EnableMouse(true)
    UI.Tip(st, "Crafting strategy", "The multilevel planner's answer for making this once, on its own: it may craft some of the materials itself when that costs less than buying them. These figures are a separate reference. They do not change the cost, profit or order in the list. Economic cost counts the materials you own at what they would cost; cash needed is only what you would buy.")

    -- the materials of one craft (left) beside the market facts (right)
    local mc = CreateFrame("Frame", nil, body)
    d.matsCol = mc
    mc:SetPoint("TOPLEFT", body, "TOPLEFT", 0, COLS_Y)
    mc:SetSize(FACT_X, 24 + MAT_ROWS * MAT_H + 16)
    local mh = UI.Text(mc, 13, K.bronzeText, "strong")
    mh:SetPoint("TOPLEFT", 14, 0)
    mh:SetText("Materials (one craft)")
    local mr = UI.Rule(mc, 0.45)
    mr:SetPoint("TOPLEFT", 14, -18); mr:SetPoint("TOPRIGHT", -6, -18)
    d.mats = {}
    for i = 1, MAT_ROWS do d.mats[i] = BuildMaterialRow(mc, -24 - (i - 1) * MAT_H) end
    d.more = UI.Text(mc, 11, K.stone)
    d.more:SetPoint("TOPLEFT", 14, -24 - MAT_ROWS * MAT_H + 1)
    d.more:SetPoint("RIGHT", -6, 0)
    -- the button, and the Market block: a heading and the facts in the right column, the price history under both columns
    d.add = UI.ArtButton(d, "Add to crafting plan", "plus", DETAIL_W - 28, "primary", function() Opps.AddSelected() end, 36)
    d.add:SetPoint("BOTTOMLEFT", 14, 12)
    d.add:SetPoint("BOTTOMRIGHT", -14, 12)
    d.add.check = d.add.artHolder:CreateTexture(nil, "OVERLAY")   -- the queued state's picture, in the place of the plus
    d.add.check:SetAllPoints()
    UI.Status(d.add.check, "done", 24)
    d.add.check:Hide()
    UI.TipFn(d.add, "Add to crafting plan", function()
        if d.addWhy then return d.addWhy end
        return "Puts this recipe in the queue to make once, in the Crafting page. Nothing is bought or crafted."
    end)
    local mk = CreateFrame("Frame", nil, body)
    d.market = mk
    mk:SetPoint("TOPLEFT", body, "TOPLEFT", FACT_X, COLS_Y)
    mk:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, COLS_Y)
    mk:SetHeight(24 + MK_ROWS * MK_ROW)
    local mkh = UI.Text(mk, 13, K.bronzeText, "strong")
    mkh:SetPoint("TOPLEFT", 6, 0)
    mkh:SetText("Market")
    local mkr = UI.Rule(mk, 0.45)
    mkr:SetPoint("TOPLEFT", 6, -18); mkr:SetPoint("TOPRIGHT", -14, -18)
    -- the facts: a label and a value each, one hover tooltip per fact (what the figure is, and what it is not)
    d.facts = {}
    for i = 1, MK_ROWS do
        local row = CreateFrame("Frame", nil, mk)
        row:SetHeight(MK_ROW)
        row:SetPoint("TOPLEFT", 6, -22 - (i - 1) * MK_ROW)
        row:SetPoint("TOPRIGHT", -14, -22 - (i - 1) * MK_ROW)
        row:EnableMouse(true)
        row.v = UI.Text(row, 11, K.text)
        row.v:SetPoint("RIGHT", 0, 0)
        row.v:SetJustifyH("RIGHT")
        row.l = UI.Text(row, 11, K.stone)
        row.l:SetPoint("LEFT", 0, 0)
        row.l:SetPoint("RIGHT", row.v, "LEFT", -4, 0)
        UI.TipFn(row, nil, function() local x = row.data return x and x.tip or nil end)
        d.facts[i] = row
    end
    local ch = CreateFrame("Frame", nil, body)
    d.chartBox = ch
    ch:SetPoint("TOPLEFT", body, "TOPLEFT", 0, CHART_Y)
    ch:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, BOTTOM)
    local chh = UI.Text(ch, 12, K.bronzeText, "strong")
    chh:SetPoint("TOPLEFT", 14, 0)
    chh:SetText("Price history")
    d.chartNote = UI.Text(ch, 11, K.stone)
    d.chartNote:SetPoint("TOPRIGHT", -14, -1)
    d.chartNote:SetJustifyH("RIGHT")
    d.chart = UI.PriceChart(ch, DETAIL_W - 28, 56)
    d.chart:ClearAllPoints()
    d.chart:SetPoint("TOPLEFT", 14, -16)
    d.chart:SetPoint("BOTTOMRIGHT", -14, 0)
    d.chart:EnableMouse(true)
    UI.TipFn(d.chart, "Price history", function()
        local note = d.chartTip
        return "The lowest listing on each day a scan saw the item" .. (note and (": " .. note .. ".") or ".") ..
            " A day without a scan has no dot. Not a sale price, and nothing before your first scan is known."
    end)
    -- what these figures are, on the Market heading only
    local why = CreateFrame("Frame", nil, mk)
    why:SetPoint("TOPLEFT", 6, 0); why:SetPoint("TOPRIGHT", -14, 0); why:SetHeight(20)
    why:EnableMouse(true)
    UI.Tip(why, "What these figures are", "Listings your scans saw, never sales. Lowest listing and Competing price are what is for sale now. Recent price, Market value (14 days) and Historical value (60 days) are references from past listings, not a selling price and not a promise it will sell. The profit above uses the lowest listing.")
    d.empty = UI.Text(d, 13, K.textDim)
    d.empty:SetPoint("TOPLEFT", 14, -16)
    d.empty:SetPoint("RIGHT", -14, 0)
    d.empty:SetWordWrap(true)
    d.empty:SetJustifyV("TOP")
end

local function Build(p)
    page, opps, K = p, p, UI.K
    opps.scan = UI.ArtButton(opps, "Scan prices", "diagOverview", 158, "primary", function()
        S.StartScan()
        UI.Redraw()
    end, 34)
    opps.scan:SetPoint("TOPRIGHT", -2, -2)
    UI.Tip(opps.scan, "Scan prices", "Reads every listing at the open auction house once, so your crafts can be priced. It only reads: it never buys, bids or posts, and it starts only when you press this. It can take a little while.")
    opps.bar = W.NewBar(opps, 250, 20)           -- the overall progress of a scan, shown only while one runs
    opps.bar:SetPoint("RIGHT", opps.scan, "LEFT", -12, 0)
    opps.bar:Hide()
    -- one short line about the latest scan; where the prices come from is in its tooltip (and the window's footer)
    local sb = CreateFrame("Frame", nil, opps)
    sb:SetSize(340, 34)
    sb:SetPoint("RIGHT", opps.scan, "LEFT", -12, 0)
    sb:EnableMouse(true)
    opps.statusBox = sb
    opps.status = UI.Text(sb, 13, K.textDim)
    opps.status:SetAllPoints()
    opps.status:SetJustifyH("RIGHT")
    opps.status:SetJustifyV("MIDDLE")
    opps.status:SetWordWrap(true)
    UI.TipFn(sb, "Prices", function()
        local src = oppView and oppView.source
        if not (src and src.market) then
            return (src and src.open) and "No saved prices for this auction house yet." or "No saved prices for this realm yet."
        end
        local text = ("Prices: %s \194\183 %s"):format(src.label, Op.ScanWords({ at = src.market.at, complete = src.market.complete }) or "")
        text = text .. "\nCheapest buyout listings per item: a listing is not a sale."
        if oppView.rate then text = text .. "\nProfit is after the auction house's cut." else text = text .. "\nProfit is before fees: the auction house's cut isn't confirmed." end
        if oppView.incomplete then text = text .. "\nSome recipes may be missing: a profession's window lists only what its filters allow." end
        return text
    end)

    -- the list
    local card = CreateFrame("Frame", nil, opps)
    card:SetPoint("TOPLEFT", 0, TOP)
    card:SetPoint("BOTTOMRIGHT", -(DETAIL_W + 12), 0)
    UI.Panel(card, "card")
    opps.card = card
    local x = -(4 + 16)   -- a row's right edge in the card: the list's inset and its scroll gutter
    local function Head(key, text, right, w)
        local h = UI.SortHead(card, text, w, function() S.SortBy(key); UI.lists.opps:ScrollTop(); UI.Redraw() end)
        h:SetPoint("TOPRIGHT", card, "TOPRIGHT", right, -6)
        h:HookScript("OnEnter", function(self)
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(self.label, 1, 0.82, 0)
                GameTooltip:AddLine(self.tipBody or "Click to sort by this.", 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end
        end)
        h:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        UI.heads[key] = h
    end
    local item = UI.Head(card, "Recipe (one craft)", 160, "LEFT")
    item:SetPoint("TOPLEFT", 16, -13)
    -- the profit heading carries its qualification on a second line ("before fees"), so it is no wider than its column
    Head("profit", "Profit", x - RIGHT, COL_W)
    Head("sell", "Sell price", x - (RIGHT + COL_W + 4), COL_W)
    Head("cost", "Cost to make", x - (RIGHT + 2 * (COL_W + 4)), COL_W)
    local rule = UI.Rule(card, 0.5)
    rule:SetPoint("TOPLEFT", 12, -34); rule:SetPoint("TOPRIGHT", -12, -34)
    local list = UI.List(card, OPP_H, MakeOppRow, 360, false)
    list.box:SetPoint("TOPLEFT", 4, -36)
    list.box:SetPoint("BOTTOMRIGHT", -4, 4)
    UI.lists.opps = list

    BuildDetail()
end

UI.Register({
    key = "opps", nav = "Opportunities", icon = "npc:coins",
    title = "Opportunities", sub = "Crafts from your known recipes, ranked by potential profit.",
    tip = "Which crafts could be worth making, from the prices of your last auction house scan.",
    Build = Build, Render = Render,
    Reset = function() oppView = nil; selected = nil end,
})
