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
-- (2026-11-20) The figures are the planning estimate (Estimate.lua: listings walked for the quantity, vendors, the competing sell price capped near
-- the usual value, the auction house's cut and the deposit at risk) with a confidence; two toggles hide Low-confidence crafts and sort by margin.

local R = TwichUI
local W = R.Workshop
local S, O, PR, Op, SC, MK, Q = W.Session, W.Observe, W.Prices, W.Opps, W.Scan, W.Market, W.Queue
local UI = W.UI
local F = W.Facts
local Sg = W.Strategy

local OPP_H, COL_W, DETAIL_W = 52, 80, 430
local BODY_W = DETAIL_W - 26
local MAT_ROWS, MAT_H = 3, 22
local MK_ROW = 14          -- one market fact's row
local MK_ROWS = 7          -- most facts shown (Market.Value x4 and Competition, Supply, Data quality)
-- Scroll the facts and a full-height interactive chart below the fixed item
-- header. The Add button stays outside the scroll area.
local BOX_Y, WHY_Y, STRAT_Y, STRAT_H, COLS_Y = -4, -50, -64, 108, -178
local MATS_W, FACT_X = 196, 212
local CHART_Y = COLS_Y - 126   -- the history's caption row (the facts column is 7 rows of 14 under its heading)
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
        color=color or K.text
        if c.low==low and c.high==high and c.r==color[1]and c.g==color[2]and c.blue==color[3]and c.alpha==(color[4]or 1)then return end
        c.low,c.high,c.r,c.g,c.blue,c.alpha=low,high,color[1],color[2],color[3],color[4]or 1
        if R.Perf and R.Perf.on then R.Perf.Count('workshop.opportunities.cellUpdates')end
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

local function Known(cell,low,high,color)
    if cell.rawLow~=low or cell.rawHigh~=high or cell.money~=UI.Money then
        cell.rawLow,cell.rawHigh,cell.money=low,high,UI.Money
        cell.lowText=low~=nil and UI.Money(low)or 'Unknown'
        cell.highText=low~=nil and high~=nil and high~=low and UI.Money(high)or nil
    end
    cell.Set(cell.lowText,cell.highText,low~=nil and color or K.stone)
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
    local pt=R.Perf and R.Perf.on and R.Perf.Start('workshop.opportunityRow')
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
        UI.ItemQuality(self.name, UI.OutputQuality(rec))
        -- the second line, shortest first: the profession, then what matters about this craft right now
        local detail = rec.profName or ""
        local makes = W.PerCraft(e.outMin, e.outMax)
        if e.state ~= "ok" then
            detail = Op.WhyText(e) or "Not priced"
        elseif makes and (e.outMax ~= e.outMin or (e.outMin or 1) > 1) then
            detail = detail .. " \194\183 makes " .. makes
        end
        -- whether one craft's materials are in the bags or in storage (asked only for the rows drawn; never part of the estimate)
        r.avail = (oppView and oppView.avail and oppView.avail(rec)) or nil
        local word = e.state == "ok" and Op.AvailWord(r.avail) or nil
        if word then detail = detail .. " \194\183 " .. word end
        local queued = S.IsQueued(rec.id)
        if queued then detail = detail .. " \194\183 In your queue" end
        -- what qualifies the estimate, briefly: a vendor sale, a cooldown, low confidence
        local warn = false
        if e.state == "ok" and e.outlet == "vendor" then detail = detail .. " \194\183 Sell to a vendor" end
        if e.cooldown then detail = detail .. " \194\183 On cooldown" warn = true end
        if e.state == "ok" and e.confidence == "low" then detail = detail .. " \194\183 Low confidence" warn = true end
        self.sub:SetText(detail)
        UI.Paint(self.sub, e.state ~= "ok" and K.bronzeText or (warn and K.bronzeText) or (word and (r.avail.state == "ready" and K.sage or K.bronzeText))
            or (queued and K.sage) or K.stone)
        if R.Perf and R.Perf.on then R.Perf.Count('workshop.opportunities.rowPaints')end
        Known(self.cost, e.cost)
        Known(self.sell, e.sellLow, e.sellHigh)
        Known(self.profit,e.state=='ok'and e.profitLow or nil,e.state=='ok'and e.profitHigh or nil,ProfitTone(e))
        self:SetSelected(rec.id == selected)
    end
    if pt then R.Perf.Stop(pt)end
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
-- "Add to crafting plan": the optimized plan by default. It opens the strategy confirmation for this recipe (the queue as it is plus this
-- recipe, planned together; the list says exactly which recipes and crafts are added, and nothing changes until it is accepted). Only when the
-- confirmation can't be shown at all is the recipe queued on its own, as before.
function Opps.AddSelected()
    local d = page and page.detail
    local rec = d and d.rec
    if not rec then return false end
    -- a queued recipe or a full queue: the plain add's own refusal says why (nothing is planned for a recipe that can't be added)
    local refused = S.IsQueued(rec.id) or Q.Count() >= W.MAX_QUEUE
    if not refused and UI.StrategyView and UI.StrategyView.Confirm(rec) then return true end
    local ok = S.Add(rec)
    UI.Redraw()
    return ok
end

local function RenderDetail(rows,positions)
    local d = page.detail
    local r
    if positions and selected then r=rows[positions[selected]or 0]
    else for _,x in ipairs(rows)do if x.rec.id==selected then r=x end end end
    if not r and rows[1] and not(selected and oppView and oppView.calculating)then r=rows[1];selected=r.rec.id end
    local shown = r ~= nil
    d.head:SetShown(shown)
    d.scroll:SetShown(shown);d.body:SetShown(shown)
    d.add:SetShown(shown)
    d.empty:SetShown(not shown)
    if not shown then
        d.chart:Clear()
        d.paintEstimate,d.paintRecipe,d.historyRevision=nil,nil,nil
        if not(oppView and oppView.calculating)then selected=nil end
        d.empty:SetText(oppView and oppView.empty or "Choose a recipe to see its details.")
        return
    end
    local e, rec = r.est, r.rec
    local factsBucket=math.floor(Q.Now()/(F and F.BUCKET or 300))
    local economyChanged=d.paintEstimate~=e or d.paintRecipe~=rec or d.itemInfoRevision~=UI.itemInfoRevision or d.factsBucket~=factsBucket
    local historyRevision=W.Pricing and W.Pricing.ChartRevision and W.Pricing.ChartRevision()or 0
    if economyChanged then
    if R.Perf and R.Perf.on then R.Perf.Count('workshop.opportunities.detailUpdates')end
    d.paintEstimate,d.paintRecipe,d.itemInfoRevision=e,rec,UI.itemInfoRevision
    d.factsBucket=factsBucket
    local _, icon
    if rec.outItem then _, icon = O.ItemFacts(rec.outItem) end
    d.icon:SetTexture(icon or rec.icon or UI.ICON_BLANK)
    d.item=rec.outItem
    d.name:SetText(rec.name)
    UI.ItemQuality(d.name, UI.OutputQuality(rec))
    d.prof:SetText(rec.profName or "")
    d.profitLabel:SetText(Op.ProfitLabel(r))
    if e.state == "ok" then
        d.profit:SetText(Range(e.profitLow, e.profitHigh, UI.Money))
        UI.Paint(d.profit, ProfitTone(e))
        -- one line under the boxes: how sure the estimate is and why, the usual profit, the deposit or a cooldown
        if W.Estimate then W.Estimate.Typical(e) end
        local parts = {}
        local cw = Op.ConfidenceText and Op.ConfidenceText(e)
        if cw then
            local first = e.reasons and e.reasons[1]
            parts[1] = cw .. (first and (": " .. first.text:gsub("%.$", "")) or "")
        end
        if e.typical then parts[#parts + 1] = "usually " .. (e.typical.profit > 0 and "+" or "") .. UI.Money(e.typical.profit) end
        if e.covers then parts[#parts + 1] = ("deposit covers %d failed %s"):format(e.covers, e.covers == 1 and "listing" or "listings")
        elseif e.depositTotal then parts[#parts + 1] = "one failed listing loses the profit" end
        local cd = Op.CooldownText and Op.CooldownText(e)
        if cd then parts[#parts + 1] = cd:lower() end
        d.why:SetText(table.concat(parts, " \194\183 "))
        UI.Paint(d.why, (e.confidence == "low" or cd or (e.depositTotal and not e.covers)) and K.bronzeText or K.textDim)
    else
        d.profit:SetText("Unknown")
        UI.Paint(d.profit, K.stone)
        d.why:SetText(Op.WhyText(e) or "Not priced")
        UI.Paint(d.why, K.bronzeText)
    end
    d.sellLabel:SetText(e.outlet == "vendor" and "Sell to a vendor" or "Sell price")
    d.cost:SetText(e.cost and UI.Money(e.cost) or "Unknown")
    d.sell:SetText(e.sellLow and Range(e.sellLow, e.sellHigh, UI.Money) or "Unknown")
    -- materials of one craft, each with its item tooltip
    local n = #(e.mats or {})
    for i, line in ipairs(d.mats) do
        local m = e.mats and e.mats[i]
        if m and i <= MAT_ROWS then
            local _, mi, quality = O.ItemFacts(m.item)
            line.item = m.item
            line.icon:SetTexture(mi or UI.ICON_BLANK)
            line.name:SetText(UI.ItemName(m.item))
            UI.ItemQuality(line.name, quality)
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
    d.paintFacts=f
    end
    if economyChanged or d.historyRevision~=historyRevision then
    d.historyRevision=historyRevision
    local f=d.paintFacts
    local series = f and F.Chart(f) or nil
    d.chart:Set(W.AdvancedChart.FromObserved(series), UI.Money,
        "workshop:opportunities:"..tostring(rec.outItem)..":"..tostring(series and series.market))
    d.chartNote:SetText((series and series.external and "Market server · Recent Price · " or "")..ChartNote(series))   -- the days the history really covers; when the listings were scanned is on the Data quality row
    end
    Opps.PaintStrategy(rec, e)
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

local function PrioritizeVisible()
    local list=UI.lists.opps;if not list then return end
    local ids={};local top=math.floor((list.scroll:GetVerticalScroll()or 0)/list.rowH)+1
    local height=list.scroll:GetHeight()or 0;if height<=list.rowH then height=list.minH end
    for i=top,math.min(#list.data,top+math.ceil(height/list.rowH))do ids[#ids+1]=list.data[i].rec.id end
    if selected then ids[#ids+1]=selected end
    S.PrioritizeOpportunities(ids)
end
local function ViewportChanged()
    local list=UI.lists.opps
    if list and not list.updating then list.reanchor=true end
    PrioritizeVisible()
end

local function Render()
    if R.Perf and R.Perf.on then W.Pricing.BeginView() end
    local v = S.Opportunities()
    oppView = v

    -- the latest scan attempt, in one short line beside the button (the full source and age are in its tooltip and the footer)
    local msg, tone = SC.Message()
    if v.calculating then msg=("Calculating prices: %d/%d settled · Ranking provisional"):format(v.progress and v.progress.settled or 0,v.summary.total);tone='warn'end
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
    opps.hideLow:SetOn(S.opp.hideLow == true)
    opps.margin:SetOn(S.opp.sort == "margin")
    for key, h in pairs(UI.heads) do
        if key == "profit" then h:SetLabel("Profit", v.rate and "after the cut" or "before fees") end
        h:SetSort(S.opp.sort == key, S.opp.desc)
        h.tipBody = (S.opp.sort == key and (S.opp.desc and "Highest first. Click to show the lowest first."
            or "Lowest first. Click to show the highest first.") or "Click to sort by this.")
    end

    -- the list and the chosen row
    RenderDetail(v.rows,v.positions)
    local list=UI.lists.opps
    if list.criteria~=v.criteria then list.criteria=v.criteria;list.reanchor=false end
    local first=math.floor((list.scroll:GetVerticalScroll()or 0)/list.rowH)+1
    local anchor=list.data[first]and list.data[first].rec.id
    list.updating=true;list:SetData(v.rows,v.empty);list.updating=false
    if list.reanchor and anchor and v.positions and v.positions[anchor]and list.lastRows~=v.rows then list.scroll:SetVerticalScroll((v.positions[anchor]-1)*list.rowH)end
    if not v.calculating then list.reanchor=true end
    list.lastRows=v.rows
    list.onViewport=ViewportChanged
    PrioritizeVisible()
    if R.Perf and R.Perf.on and v.source.reference then W.Pricing.ObserveView(v.all,UI.lists.opps)end
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
function Opps.PaintStrategy(rec, est)
    local d = page and page.detail
    if not d then return end
    local st = d.strat
    local state,plan,why
    if est and est.why=='calculating'then state='planning'
    else state,plan,why=S.OppStrategy(rec)end
    local function Pair(i, text, tip)
        local p = st.pairs[i]
        p.v:SetText(text or "Unknown")
        p.tip = tip
        UI.Paint(p.v, text and K.text or K.stone)
    end
    d.stratState = state
    d.view:SetEnabled(state == "ready")
    st.saveTip = nil
    if state ~= "ready" then
        st.status:SetText(state == "planning" and "Planning..." or (state == "failed" and "Couldn't be worked out" or "Not enough data"))
        UI.Paint(st.status, K.textDim)
        Pair(1, state == "planning" and "..." or nil); Pair(2, state == "planning" and "..." or nil)
        st.headline:SetText(state == "unknown" and (why or "") or "")
        UI.Paint(st.headline, K.textDim)
        st.save:SetText("")
        return
    end
    local words = Sg.Summary(plan, UI.Money)
    st.status:SetText(words.status)
    UI.Paint(st.status, words.tone == "good" and K.sage or (words.tone == "warn" and K.bronzeText or K.textDim))
    st.headline:SetText(words.headline)
    UI.Paint(st.headline, K.text)
    local costTip = words.costTip
    if words.direct then costTip = (costTip and (costTip .. "\n") or "") .. "Buying every material directly: " .. words.direct end
    -- the profit this route gives (owner decision R8): what the sale leaves after the cut, minus the route's economic cost (its lower bound)
    local econ = plan.summary and plan.summary.economic
    if est and est.state == "ok" and est.netLow and econ and econ.low and (plan.summary.missing or 0) == 0 then
        local p = est.netLow - econ.low
        costTip = (costTip and (costTip .. "\n") or "") .. ("Profit with this route: %s%s (the list counts buying every material)."):format(
            econ.high == econ.low and "" or "about ", UI.Money(p))
        st.routeProfit = p
    else
        st.routeProfit = nil
    end
    Pair(1, words.cost, costTip)
    Pair(2, words.cash, words.cashTip)
    st.save:SetText(words.saveShort or "")
    st.saveTip = words.savingsWhy
    UI.Paint(st.save, words.savingsTone == "good" and K.sage or (words.savingsTone == "warn" and K.bronzeText or K.textDim))
end

local function BuildDetail()
    local d = CreateFrame("Frame", nil, opps)
    d:SetPoint("TOPRIGHT", 0, -80)
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
    d.advisorItem=CreateFrame("Button",nil,d.head); d.advisorItem:SetAllPoints(d.iconFrame)
    UI.ItemTip(d.advisorItem,function() return d.item end)
    d.name = UI.Text(d.head, 19, K.text, "serif")
    d.name:SetPoint("TOPLEFT", 70, -12)
    d.name:SetWidth(DETAIL_W - 70 - 14)
    d.name:SetWordWrap(true)
    d.name:SetMaxLines(1)
    d.name:SetJustifyV("TOP")
    d.prof = UI.Text(d.head, 13, K.textDim)
    d.prof:SetPoint("BOTTOMLEFT", d.iconFrame, "BOTTOMRIGHT", 10, 1)
    local scroll=CreateFrame("ScrollFrame",nil,d,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",0,-62);scroll:SetPoint("BOTTOMRIGHT",-26,58)
    UI.CL.ScrollRail(scroll);d.scroll=scroll
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(BODY_W,-CHART_Y+216);scroll:SetScrollChild(body)
    d.body = body
    -- the three money boxes in a row: cost to make, sell price, profit (the one-level estimate the list is ranked by)
    local bw = math.floor((BODY_W - 28 - 16) / 3)
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
    sellBox, d.sell, d.sellLabel = Box("Sell price", 2)
    profitBox, d.profit, d.profitLabel = Box("Profit before fees", 3)
    d.why = UI.Text(body, 12, K.bronzeText)
    d.why:SetPoint("TOPLEFT", 14, WHY_Y)
    d.why:SetPoint("RIGHT", -14, 0)
    -- what the figures assume, in words (the planning estimate, docs/workshop/pricing-realism-proposal.md); Shift over the row shows every step
    UI.Tip(costBox, "Cost to make", "One craft's materials: the cheaper of a known vendor and the listings of your last scan, walked for the quantity needed. Listings far below the rest aren't counted. Buying whole stacks can cost more.")
    UI.Tip(sellBox, "Sell price", "The lowest competing listing of what it makes, at most 115% of its usual Market Value, or what a merchant pays when that is more. Not a promise it will sell.")
    UI.Tip(profitBox, "Profit", "Sell price minus the auction house's cut minus Cost to make. A deposit is refunded on a sale, so it isn't subtracted.")

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
    -- what to do, in one line; then the planning figure, large, with the gold needed now beside it; then the saving and View strategy
    st.headline = UI.Text(st, 13, K.text, "strong")
    st.headline:SetPoint("TOPLEFT", 10, -27)
    st.headline:SetWidth(BODY_W - 28 - 20)
    st.pairs = {}
    local colw = math.floor((BODY_W - 28 - 20) / 2)
    local LABELS = { "Estimated cost", "Gold needed now" }
    for i = 1, 2 do
        local x = 10 + (i - 1) * colw
        local cell = CreateFrame("Frame", nil, st)
        cell:SetPoint("TOPLEFT", x, -45)
        cell:SetSize(colw - 6, 34)
        cell:EnableMouse(true)
        local l = UI.Text(cell, 11, K.stone)
        l:SetPoint("TOPLEFT", 0, 0)
        l:SetWidth(colw - 6)
        l:SetText(LABELS[i])
        local v = UI.Text(cell, i == 1 and 16 or 14, K.text, "strong")
        v:SetPoint("TOPLEFT", 0, -13)
        v:SetWidth(colw - 6)
        local pair = { l = l, v = v, label = LABELS[i], cell = cell }
        UI.TipFn(cell, LABELS[i], function()
            local base = i == 1 and "Owned materials count at what they would cost." or "Only what you buy now."
            return (pair.tip and (pair.tip .. "\n") or "") .. base
        end)
        st.pairs[i] = pair
    end
    st.save = UI.Text(st, 12, K.textDim)
    st.save:SetPoint("BOTTOMLEFT", 10, 10)
    st.save:SetWidth(BODY_W - 28 - 20 - 112)
    st.save:SetJustifyH("LEFT")
    d.view = UI.Button(st, "View strategy", 104, "secondary", function()
        if d.rec and UI.StrategyView then UI.StrategyView.Open("opp", d.rec) end
    end, 22)
    d.view:SetPoint("BOTTOMRIGHT", -8, 6)
    UI.Tip(d.view, "View strategy", "See every step, with prices and comparisons.")
    st:EnableMouse(true)
    UI.TipFn(st, "Crafting strategy", function()
        return (st.saveTip and (st.saveTip .. "\n") or "") .. "Making this once, on its own. Separate from the list's cost and profit."
    end)

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
        return "Review the optimized crafts before adding them."
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
    ch:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, CHART_Y);ch:SetHeight(208)
    local chh = UI.Text(ch, 12, K.bronzeText, "strong")
    chh:SetPoint("TOPLEFT", 14, 0)
    chh:SetText("Price history")
    d.serverHistory = UI.Button(ch, "Server history", 108, "secondary", function()
        if d.rec and d.rec.outItem and W.ServerMarket then W.ServerMarket.Open(d.rec.outItem) end
    end, 18)
    d.serverHistory:SetPoint("TOPLEFT", 106, 4)
    UI.Tip(d.serverHistory, "Server history", "Opens the separate Market server source. Choose an exact server variant; local prices and advice stay unchanged.")
    d.chartNote = UI.Text(ch, 11, K.stone)
    d.chartNote:SetPoint("TOPLEFT",14,-22);d.chartNote:SetPoint("RIGHT",-14,0);d.chartNote:SetHeight(16)
    d.chartNote:SetJustifyH("LEFT")
    d.chart = UI.AdvancedMarketChart(ch, BODY_W - 28, 168)
    d.chart:SetPoint("TOPLEFT",14,-40);d.chart:SetPoint("TOPRIGHT",-14,-40)
    -- what these figures are, on the Market heading only
    local why = CreateFrame("Frame", nil, mk)
    why:SetPoint("TOPLEFT", 6, 0); why:SetPoint("TOPRIGHT", -14, 0); why:SetHeight(20)
    why:EnableMouse(true)
    UI.Tip(why, "What these figures are", "Listings your scans saw, never sales.\nMarket value (14 days) and Historical value (60 days) are references, not a selling price.")
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
    UI.Tip(opps.scan, "Scan prices", "Read every listing at the open auction house.\nIt only reads: it never buys, bids or posts.")
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
        text = text .. "\nListings, not sales: costs walk the listings for the quantity needed, sell prices follow the lowest competing listing."
        if oppView.rate then
            text = text .. "\nProfit is after the auction house's cut." .. (oppView.cut and (" " .. oppView.cut.label:gsub("^%l", string.upper) .. ".") or "")
        elseif oppView.cutWhy == "off" then
            text = text .. "\nProfit is before fees: you chose not to deduct the auction house's cut."
        else
            text = text .. "\nProfit is before fees: the auction house's cut isn't confirmed."
        end
        if oppView.incomplete then text = text .. "\nSome recipes may be missing: a profession's window lists only what its filters allow." end
        return text
    end)

    -- Two toggles above the details, below Scan prices, clear of the page title.
    opps.hideLow = UI.Segment(opps, "Hide low confidence", 156, function()
        S.ToggleHideLow(); UI.lists.opps:ScrollTop(); UI.Redraw()
    end)
    opps.hideLow:SetPoint("TOPLEFT", opps, "TOPRIGHT", -DETAIL_W, -44)
    UI.Tip(opps.hideLow, "Hide low confidence", "Hide crafts whose estimate rests on thin, capped or reference data. Unknown estimates stay, with their reason.")
    opps.margin = UI.Segment(opps, "Best margin first", 138, function()
        S.SortBy(S.opp.sort == "margin" and "profit" or "margin"); UI.lists.opps:ScrollTop(); UI.Redraw()
    end)
    opps.margin:SetPoint("LEFT", opps.hideLow, "RIGHT", 6, 0)
    UI.Tip(opps.margin, "Best margin first", "Rank by profit for each copper the materials cost, so cheap crafts that pay well come first. Click again to rank by profit.")

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
