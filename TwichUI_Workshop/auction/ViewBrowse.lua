-- AH-2 presentation: only stored observations. Selecting, filtering, comparing
-- or tracking never sends a query. No row holds a live purchase handle.
local R, W = TwichUI, TwichUI.Workshop
local A, UI, D, AD = W.AuctionUI, W.UI, W.AuctionBrowseData, W.AdvisorData
local V = {}
A.Browse = V
local page
local Start, Paint, Detail
local function Key(r) return r.item end
local function Money(n) return n and UI.Money(n) or "Unavailable" end
local function Stamp(m, p)
    return (m and (m.key .. ":" .. W.Valuation.Generation(m)) or "none") .. ":" .. p.metadata
end
local function DetailRows(d, facts)
    local rows = W.Facts.Rows(facts, UI.Money)
    local info = d.data and d.data.info
    rows[#rows + 1] = { label = "Vendor sell / item", value = info and info.sell and UI.Money(info.sell) or "Unavailable" }
    for i, text in ipairs(d.factLines) do
        local r = rows[i]
        if r then
            local label = r.id == "min" and "Lowest seen / item" or r.id == "comp" and "Observed competing price" or r.label
            text:SetText(label .. ":  " .. r.value)
            text:Show()
        else text:Hide() end
    end
end
Detail = function(p)
    local d, chosen = p.detail
    for _, r in ipairs(p.rows or {}) do if r.item == p.selected then chosen = r; break end end
    d.data = chosen
    d.track:SetEnabled(chosen ~= nil)
    d.compare:SetEnabled(chosen ~= nil)
    d.buy:SetEnabled(false)
    if not chosen then
        d.track.text:SetText("Track")
        d.name:SetText("Choose an item"); d.kind:SetText("Stored observations only")
        d.pic.tex:SetTexture(UI.ICON_BLANK)
        for _, t in ipairs(d.factLines) do t:SetText("") end
        d.fresh:SetText("No current auction listings are shown.")
        d.chart:Set(nil, UI.Money); d.advice:SetText("Select an item to inspect its history.")
        d.evidence:SetText(""); d.cached = nil
        return
    end
    local item = chosen.item
    d.name:SetText(chosen.info.name); d.pic.tex:SetTexture(chosen.info.icon or UI.ICON_BLANK)
    d.kind:SetText((chosen.info.category or "Category unavailable") .. (chosen.info.sub and " · " .. chosen.info.sub or ""))
    d.track.text:SetText(AD.Tracked()[item] and "Untrack" or "Track")
    local stamp = p.stamp .. ":" .. item .. ":" .. W.Strategy.epoch
    if d.cached == stamp then return end
    d.cached = stamp
    local facts = W.Facts.Of(item, {market = p.market})
    DetailRows(d, facts)
    d.fresh:SetText((p.market and (W.Prices.Label(p.market) .. " · ") or "") .. (W.Facts.Freshness(facts) or "No saved observation") .. "\nHistorical observations; availability is unknown.")
    d.chart:Set(W.Facts.Chart(facts), UI.Money)
    -- Real bag quantity, never invented ownership to obtain a recommendation.
    local rec = AD.Decide(item, false)
    d.recommendation = rec
    d.advice:SetText(rec.text or "Not enough data to compare")
    d.evidence:SetText((W.Advisor.EVIDENCE[rec.evidence] or "Limited evidence") .. "\n" .. table.concat(rec.reasons or {}, "\n"))
end
Paint = function(p)
    p.list:SetData(p.rows or {}, p.error and "Saved observations could not be read. Try Search history again." or
        p.job and "Loading saved observations…" or p.market and "No stored observations match these filters." or
        "No saved market observations yet. Prices are never scanned automatically.")
    p.status:SetText(p.error and "Could not read observations" or p.job and "Loading stored observations…" or
        (tostring(#(p.rows or {})) .. " stored item observations" .. (p.capped and " · catalog limited to 20,000 items" or "")))
    p.list.box:SetAlpha(p.job and 0.55 or 1)
    p.detail.buy:SetEnabled(false)
    Detail(p)
end
Start = function(p, reset)
    p.token = p.token + 1
    local mine = p.token
    local view = reset and nil or (p.pendingView or p.viewport or A.Capture(p.list, Key))
    p.viewport = nil; p.pendingView = view
    if reset then p.list:ScrollTop(); p.selected = nil end
    p.market = W.Market.Source().market
    p.stamp = Stamp(p.market, p)
    p.error, p.rows = nil, {}
    p.detail.cached = nil
    p.job = D.Job({market = p.market, query = p.query, category = p.category, quality = p.quality,
        exact = p.exact, auctionable = p.auctionable, item = p.forceItem or p.selected})
    Paint(p)
    local function Step()
        if mine ~= p.token or not A.IsShown() or A.Mode() ~= "browse" then return end
        local done, err = p.job:Step()
        if not done then C_Timer.After(0, Step); return end
        local job = p.job
        p.job, p.error, p.capped = nil, err, job.capped
        p.rows = err and {} or job.rows
        local exists = false
        for _, r in ipairs(p.rows) do if r.item == p.selected then exists = true; break end end
        if not exists then p.selected = p.rows[1] and p.rows[1].item end
        Paint(p); A.Restore(p.list, view, Key); p.pendingView = nil
    end
    C_Timer.After(0, Step)
end
local function Filter(p, name, value)
    if p[name] == value then return end
    p[name] = value
    if p.categoryDrop then p.categoryDrop:Refresh(); p.qualityDrop:Refresh() end
    for key, button in pairs(p.categoryButtons or {}) do button:SetOn(key == p.category) end
    for key, button in pairs(p.qualityButtons or {}) do button:SetOn(key == p.quality) end
    Start(p, true)
end
function V.Filter(name, value)
    if page and ({category=true,quality=true,exact=true,auctionable=true})[name] then Filter(page,name,value) end
end
function V.Search(query)
    if not page then return end
    page.query = W.Text(query, 200) or ""
    page.search:SetText(page.query)
    page.search.hint:SetShown(page.query == "" and not page.search:HasFocus())
    Start(page, true)
end
function V.Select(item)
    if not page then return end
    page.selected = item; AD.Request(item)
    page.detail.scroll:SetVerticalScroll(0)
    for _, r in ipairs(page.list.rows) do if r.data then r:SetSelected(r.data.item == item) end end
    Detail(page)
end
function A.OpenBrowse(item, qty)
    item = W.Int(item, 1, W.MAX_ID)
    if not item or not A.IsShown() then return false end
    A.Go("browse")
    page.forceItem = item
    page.category, page.quality, page.exact, page.auctionable = "all", -1, false, false
    page.categoryDrop:Refresh(); page.qualityDrop:Refresh()
    V.Search(tostring(item))
    A.Note("Find " .. tostring(qty or "the needed") .. " of this item at an auctioneer. This preview shows history; purchasing is unavailable.")
    return true
end
local function MakeRow(parent)
    local r = CreateFrame("Button", nil, parent)
    UI.Hover(r)
    r.pic = UI.ItemIcon(r, 34); r.pic:SetPoint("LEFT", 8, 0)
    r.name = A.Text(r, "", 14, 50, -10, -274)
    r.sub = A.Text(r, "Stored observation", 11, 50, -31, -12, UI.K.textDim)
    r.qty = UI.Text(r, 13, UI.K.text); r.qty:SetWidth(42); r.qty:SetJustifyH("RIGHT"); r.qty:SetPoint("RIGHT", -222, 6)
    r.unit = UI.Text(r, 13, UI.K.text); r.unit:SetWidth(100); r.unit:SetJustifyH("RIGHT"); r.unit:SetPoint("RIGHT", -116, 6)
    r.total = UI.Text(r, 13, UI.K.text); r.total:SetWidth(106); r.total:SetJustifyH("RIGHT"); r.total:SetPoint("RIGHT", -8, 6)
    r:SetScript("OnClick", function(self) if self.data then V.Select(self.data.item) end end)
    r.fill = function(self, data)
        self.data = data
        self.pic.tex:SetTexture(data.info.icon or UI.ICON_BLANK); self.name:SetText(data.info.name)
        self.qty:SetText(data.qty and tostring(data.qty) or "—")
        self.unit:SetText(Money(data.unit)); self.total:SetText(data.estimate and ("~" .. UI.Money(data.estimate)) or "—")
        self.sub:SetText("Stored · " .. (data.info.category or "Metadata unavailable") .. (data.at and (" · " .. UI.Ago(data.at)) or " · no saved price"))
        self:SetSelected(page.selected == data.item)
    end
    UI.TipFn(r, "Stored item observation", function()
        return r.data and (r.data.info.name .. "\nQuantity is the aggregate at the cheapest observed tier, not a stack. Unit prices are rounded up to copper by the shared market service. Estimated value is not an auction total. No current availability or purchase action.")
    end)
    return r
end
local function BuildDetail(p)
    local d = A.Details(p, 370); p.detail = d
    d:SetPoint("TOPRIGHT", 0, -52); d:SetPoint("BOTTOMRIGHT", 0, 0)
    d.summary = A.Card(d.body, "Market Summary · stored", 184)
    d.summary:SetPoint("TOPLEFT", 4, -100); d.summary:SetPoint("TOPRIGHT", -4, -100)
    d.factLines = {}
    for i=1,8 do d.factLines[i] = A.Text(d.summary,"",12,12,-31-(i-1)*18) end
    d.fresh = A.Text(d.body, "", 11, 10, -290, -8, UI.K.textDim)
    d.fresh:SetHeight(44); d.fresh:SetWordWrap(true)
    local chartCard = A.Card(d.body, "Cheapest seen · observed days", 100)
    chartCard:SetPoint("TOPLEFT", 4, -342); chartCard:SetPoint("TOPRIGHT", -4, -342)
    d.chart = UI.PriceChart(chartCard, 320, 62)
    d.chart:SetPoint("TOPLEFT", 8, -33); d.chart:SetPoint("TOPRIGHT", -8, -33)
    d.advisor = A.Card(d.body, "Item Advisor", 112)
    d.advisor:SetPoint("TOPLEFT", 4, -450); d.advisor:SetPoint("TOPRIGHT", -4, -450)
    d.advice = A.Text(d.advisor, "", 14, 12, -31, -12, UI.K.bronzeText)
    d.advice:SetWordWrap(true); d.advice:SetHeight(32)
    d.evidence = A.Text(d.advisor, "", 11, 12, -68, -12, UI.K.textDim)
    d.evidence:SetWordWrap(true); d.evidence:SetHeight(38)
    UI.TipFn(d.advisor, "Item Advisor evidence", function()
        return d.recommendation and table.concat(d.recommendation.reasons or {}, "\n")
    end)
    d.body:SetHeight(574)
    d.buy = UI.Button(d, "Buy unavailable", 122, "primary", nil, 32)
    d.buy:SetPoint("BOTTOMLEFT", 10, 10); d.buy:SetEnabled(false)
    d.compare = UI.Button(d, "Compare", 100, "secondary", function() d.scroll:SetVerticalScroll(98) end, 32)
    d.compare:SetPoint("LEFT", d.buy, "RIGHT", 6, 0)
    d.track = A.TrackButton(d, function() return d.data and d.data.item end)
    d.track:SetPoint("BOTTOMRIGHT", -10, 10)
end
local function Build(p)
    page = p
    p.query,p.category,p.quality,p.metadata,p.token = "","all",-1,0,0
    p.rows = {}
    p.search = UI.Search(p, 360, 32, "Search saved items or item ID…")
    p.search:SetPoint("TOPLEFT", 0, 0); p.search:SetMaxLetters(200)
    p.categoryDrop = A.Dropdown(p, 180, function() return D.CATEGORIES end, function() return p.category end, function(v) Filter(p,"category",v) end)
    p.categoryDrop:SetPoint("LEFT",p.search,"RIGHT",10,0)
    p.qualityDrop = A.Dropdown(p, 160, function() return D.QUALITIES end, function() return p.quality end, function(v) Filter(p,"quality",v) end)
    p.qualityDrop:SetPoint("LEFT",p.categoryDrop,"RIGHT",10,0)
    p.submit = UI.Button(p,"Search history",140,"primary",function() V.Search(p.search:GetText()) end,32)
    p.submit:SetPoint("TOPRIGHT",0,0)
    p.search:SetScript("OnEnterPressed",function(self) self:ClearFocus(); V.Search(self:GetText()) end)
    p.search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    p.search:HookScript("OnTextChanged",function(self)
        self.hint:SetShown(self:GetText()=="" and not self:HasFocus())
    end)
    local filters = A.Card(p,"Category",540); p.filters=filters
    filters:SetWidth(174); filters:SetPoint("TOPLEFT",0,-52); filters:SetPoint("BOTTOMLEFT",0,0)
    p.categoryButtons={}
    for i,entry in ipairs(D.CATEGORIES) do
        local key=entry[1]
        local b=UI.Segment(filters,entry[2],150,function() Filter(p,"category",key) end)
        b:SetPoint("TOPLEFT",12,-35-(i-1)*32); b:SetOn(key=="all"); p.categoryButtons[key]=b
    end
    A.Text(filters,"Quality",17,12,-244,-12,UI.K.bronzeText)
    p.qualityButtons={}
    for i,key in ipairs({1,2,3,4}) do
        local names={[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic"}
        local b=UI.Segment(filters,names[key],150,function() Filter(p,"quality",p.quality==key and -1 or key) end)
        b:SetPoint("TOPLEFT",12,-274-(i-1)*31); b:SetOn(false); p.qualityButtons[key]=b
    end
    p.exactButton=UI.Segment(filters,"Exact name only",150,function() Filter(p,"exact",not p.exact); p.exactButton:SetOn(p.exact) end)
    p.exactButton:SetPoint("TOPLEFT",12,-414)
    p.tradeButton=UI.Segment(filters,"Tradeable types",150,function() Filter(p,"auctionable",not p.auctionable); p.tradeButton:SetOn(p.auctionable) end)
    p.tradeButton:SetPoint("TOPLEFT",12,-448)
    UI.Tip(p.tradeButton,"Tradeable item types","Filters known unbound/BoE/BoU base types. This is not proof that an owned copy can currently be auctioned. Unknown binding metadata is excluded.")
    p.stacks=UI.Button(filters,"Stack data unavailable",150,"secondary",nil,26); p.stacks:SetPoint("TOPLEFT",12,-486); p.stacks:SetEnabled(false)
    p.reset=UI.Button(filters,"Reset Filters",150,"secondary",function()
        p.category,p.quality,p.exact,p.auctionable,p.forceItem="all",-1,false,false,nil
        p.exactButton:SetOn(false); p.tradeButton:SetOn(false)
        p.categoryDrop:Refresh(); p.qualityDrop:Refresh()
        for key,b in pairs(p.categoryButtons) do b:SetOn(key=="all") end
        for _,b in pairs(p.qualityButtons) do b:SetOn(false) end
        V.Search("")
    end,30)
    p.reset:SetPoint("BOTTOMLEFT",12,12)
    local tableCard=A.Card(p,"Stored observations",100); p.tableCard=tableCard
    tableCard:SetPoint("TOPLEFT",filters,"TOPRIGHT",10,0); tableCard:SetPoint("BOTTOMRIGHT",-380,0)
    tableCard.heading:Hide()
    local function Head(text,w,x)
        local h=UI.Head(tableCard,text,w,"RIGHT"); h:SetPoint("TOPRIGHT",x,-14)
    end
    local itemHead=A.Text(tableCard,"Item",13,14,-14,-280,UI.K.bronzeText)
    Head("Qty*",42,-246); Head("Unit price",100,-138); Head("Est. value*",110,-28)
    p.list=UI.List(tableCard,56,MakeRow,360,false)
    p.list.box:SetPoint("TOPLEFT",4,-36); p.list.box:SetPoint("BOTTOMRIGHT",-4,72)
    p.status=A.Text(tableCard,"",12,12,-1,-12,UI.K.textDim)
    p.status:ClearAllPoints(); p.status:SetPoint("BOTTOMLEFT",12,46); p.status:SetPoint("RIGHT",-12,0)
    local scope=A.Text(tableCard,"*Aggregated quantity at the cheapest tier.\nStored history; no current auctions or exact stacks.",11,12,-1,-12,UI.K.textDim)
    scope:ClearAllPoints(); scope:SetPoint("BOTTOMLEFT",12,12); scope:SetPoint("RIGHT",-12,0); scope:SetWordWrap(true); scope:SetHeight(30)
    BuildDetail(p)
    p:SetScript("OnEvent",function(_,event,item,ok)
        if event~="GET_ITEM_INFO_RECEIVED" or ok~=false then
            p.metadata=p.metadata+1
            A.Schedule()
        end
    end)
end
local function Render(p)
    if not p.listening then
        p:RegisterEvent("GET_ITEM_INFO_RECEIVED"); p:RegisterEvent("BAG_UPDATE_DELAYED"); p.listening=true
    end
    local market=W.Market.Source().market
    if not p.stamp or p.stamp~=Stamp(market,p) then Start(p,false) else Paint(p) end
end
local function Release(p)
    p.viewport=p.pendingView or A.Capture(p.list,Key)
    p.token=p.token+1; p.job,p.rows,p.market,p.stamp,p.pendingView=nil,nil,nil,nil,nil
    p.list:SetData({}); p:UnregisterAllEvents(); p.listening=false
    for _,r in ipairs(p.list.rows) do r.data=nil end
    p.detail.data,p.detail.cached,p.detail.recommendation=nil,nil,nil
end
A.Register("browse",{Build=Build,Render=Render,Release=Release})
