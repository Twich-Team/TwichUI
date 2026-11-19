-- Stored research and explicit live search/inspection. Clicking a live browse
-- group inspects that item's listings; no row click performs a transaction.
local R, W = TwichUI, TwichUI.Workshop
local A, UI, D, AD = W.AuctionUI, W.UI, W.AuctionBrowseData, W.AdvisorData
local V = {}
A.Browse = V
local page
local Start, Paint, Detail
local SubmitLive, Inspect, Back
local linkHooks=setmetatable({}, {__mode="k"})
local function Key(r)
    if r.listingKey then return r.listingKey end
    if r.auctionID then return "auction:"..r.auctionID end
    local k=r.itemKey
    if k then return table.concat({k.itemID,k.itemLevel or 0,k.itemSuffix or 0,k.battlePetSpeciesID or 0},":") end
    return r.item
end
local function Money(n) return n and UI.Money(n) or "Unavailable" end
local function LiveInfo(row)
    local info=AD.Info(row.link or row.item)
    info.item=row.item
    if row.itemKey and C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok,native=pcall(C_AuctionHouse.GetItemKeyInfo,row.itemKey)
        if ok and type(native)=="table" then
            info.quality=info.quality or W.Int(W.Plain(native.quality),0,20)
            info.icon=info.icon or W.Plain(native.iconFileID)
            if not info.known then
                local name=W.Text(W.Plain(native.itemName),200)
                if name then info.name=name end
            end
        end
    end
    return info
end
local function SavedMarket(p)
    if p.researchMarketKey and p.researchMarketKey~="auto" then return W.Prices.Market(p.researchMarketKey) end
    return W.Market.Source().market
end
local function Stamp(m, p)
    return m and (m.key .. ":" .. W.Valuation.Generation(m)) or "none"
end
local function Options(p)
    return {market=p.market,query=p.query,category=p.category,quality=p.quality,exact=p.exact,
        auctionable=p.auctionable,nativeCategory=p.nativeByID and p.nativeByID[p.category],
        item=p.forceItem,sort=p.sort=="Name" and "Name" or "Price",reverse=p.sort=="PriceDesc"}
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
    for _, r in ipairs(p.rows or {}) do if Key(r) == p.selected then chosen = r; break end end
    d.data = chosen
    d.track:SetEnabled(chosen ~= nil)
    d.compare:SetEnabled(chosen ~= nil)
    d.market:SetEnabled(chosen ~= nil)
    d.buy:SetEnabled(A.Live() and p.liveMode==true and chosen~=nil and chosen.source=="live" and (chosen.auctionID~=nil or chosen.commodity)
        and W.AuctionReads.Available() and W.AuctionReads.Pending()==0)
    d.buy.text:SetText(A.Live() and "Review buyout" or "Buy unavailable")
    local commodity=chosen and chosen.liveKind=="commodity"
    d.quantity:SetEnabled(A.Live() and commodity and W.AuctionReads.Pending()==0)
    d.quantityHint:SetText(commodity and "Items to buy" or "One item")
    if not commodity then d.quantity:SetText("1") end
    if chosen and d.quantityItem~=chosen.item then
        d.quantityItem=chosen.item
        if commodity and chosen.item==p.neededItem then d.quantity:SetText(tostring(p.neededQuantity or 1)) end
    end
    d.inspect:SetEnabled(p.liveMode==true and chosen~=nil and chosen.itemKey~=nil and W.AuctionReads.Available())
    if not chosen then
        d.track.text:SetText("Track")
        d.name:SetText("Choose an item"); d.kind:SetText("Stored observations only")
        d.pic.tex:SetTexture(UI.ICON_BLANK)
        for _, t in ipairs(d.factLines) do t:SetText("") end
        d.fresh:SetText("")
        d.chart:Set(nil, UI.Money,"browse-empty"); d.advice:SetText("Select an item to inspect its history.")
        d.evidence:SetText(""); d.cached = nil
        return
    end
    local item = chosen.item
    d:LayoutSummary(chosen.source=="live")
    d.name:SetText(chosen.info.name)
    local quality=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[chosen.info.quality or 1]
    if quality then d.name:SetTextColor(quality.r,quality.g,quality.b) else UI.Paint(d.name,UI.K.text) end
    d.pic.tex:SetTexture(chosen.info.icon or UI.ICON_BLANK)
    d.kind:SetText((chosen.info.category or "Category unavailable") .. (chosen.info.sub and " · " .. chosen.info.sub or ""))
    d.track.text:SetText(AD.Tracked()[item] and "Untrack" or "Track")
    local snapshot=chosen.source=="live" and (W.AuctionReads.snapshot or p.liveSnapshot)
    local age=snapshot and math.max(0,GetTime()-snapshot.at)
    if age then d.fresh:SetText(UI.Ago(time()-age)) end
    local stamp = (p.stamp or "live") .. ":" .. tostring(p.selected) .. ":" .. W.Strategy.epoch
    if d.cached == stamp then return end
    d.cached = stamp
    local k=chosen.itemKey
    local variant=k and ((k.itemLevel or 0)~=0 or (k.itemSuffix or 0)~=0 or (k.battlePetSpeciesID or 0)~=0) or false
    local facts = W.Facts.Of(item, {market = p.market,variant=variant})
    DetailRows(d, facts)
    if chosen.source=="live" then
        d.summary.heading:SetText(chosen.commodity and "Live commodity price" or chosen.priceEach and "Live price · per item" or chosen.auctionID and "Live listing · exact amounts" or "Live item group · inspect listings")
        local lines={((chosen.priceEach or chosen.commodity) and "Available at this price: " or "Quantity: ")..tostring(chosen.qty or "Unknown"),"Unit price: "..Money(chosen.unit),
            (chosen.commodity and "Value at this price: " or chosen.priceEach and "Buyout for one: " or "Exact buyout total: ")..Money(chosen.total),"Bid: "..Money(chosen.bid)}
        for i,t in ipairs(d.factLines) do t:SetText(lines[i] or "");t:SetShown(lines[i]~=nil) end
    else d.summary.heading:SetText("Market Summary · stored") end
    if not age then d.fresh:SetText(facts.age and UI.Ago(time()-facts.age) or "No saved data") end
    local market=p.market or SavedMarket(p)
    local projection=W.AuctionMarketData.Project(item,market,14,{variant=variant})
    d.chart:Set(projection and projection.series,UI.Money,tostring(item)..":browse:"..tostring(market and market.key)..":"..tostring(variant))
    -- Real bag quantity, never invented ownership to obtain a recommendation.
    local rec = variant and {text="Variant-specific advice unavailable",reasons={"Base-item prices are excluded."}} or AD.Decide(item, false)
    d.recommendation = rec
    d.advice:SetText(rec.text or "Not enough data to compare")
    d.evidence:SetText((W.Advisor.EVIDENCE[rec.evidence] or "Limited evidence") .. "\n" .. table.concat(rec.reasons or {}, "\n"))
end
Paint = function(p)
    D.Count("paints")
    p.list:SetData(p.rows or {}, p.error and "Saved observations could not be read. Use Search Saved Data to retry." or
        p.job and "Loading saved observations…" or p.market and "No stored observations match these filters." or
        "No saved market observations yet. Prices are never scanned automatically.")
    p.status:SetText(p.error and "Could not read observations" or p.job and "Loading stored observations…" or
        (tostring(#(p.rows or {})) .. " stored item observations" .. (p.capped and " · catalog limited to 20,000 items" or "")))
    p.list.box:SetAlpha(1)
    p.detail.buy:SetEnabled(false)
    Detail(p)
    if A.UpdateBusy then A.UpdateBusy() end
end
Start = function(p, reset)
    if p.job and p.job.discovering and D.SameMarket(p.market,SavedMarket(p)) and p.stamp==Stamp(SavedMarket(p),p) then
        p.refilter=true
        if reset then p.selected=nil;p.list:ScrollTop();p.pendingView=nil end
        return
    end
    if p.job and p.job.Cancel then p.job:Cancel() end
    p.token = p.token + 1
    p.state = "loading"
    if p.categoryList then p.categoryList:Layout() end
    local mine = p.token
    local view = reset and nil or (p.pendingView or p.viewport or A.Capture(p.list, Key))
    p.viewport = nil; p.pendingView = view
    if reset then p.list:ScrollTop(); p.selected = nil end
    local market=SavedMarket(p)
    local stamp=Stamp(market,p)
    local sourceKey=market and market.key or "none"
    if p.sourceKey and p.sourceKey~=sourceKey then p.rows={};p.selected=nil end
    p.sourceKey=sourceKey
    local cached=D.SameMarket(p.market,market) and p.stamp==stamp and p.catalog or nil
    if not cached then D.Count("invalidations");p.catalog,p.known,p.dirty=nil,nil,nil end
    p.market,p.stamp=market,stamp
    p.error = nil
    p.rows=p.rows or {}
    p.detail.cached = nil
    local opt=Options(p);opt.catalog=cached
    p.job = D.Job(opt)
    Paint(p)
    local function Step()
        if mine ~= p.token or not A.IsShown() or A.Mode() ~= "browse" then return end
        local ok, done, err = pcall(p.job.Step, p.job)
        if not ok then err, done = "failed", true end
        if not done then C_Timer.After(0, Step); return end
        local job = p.job
        if err and job.Cancel then job:Cancel() end
        p.job, p.error, p.capped = nil, err, job.capped
        p.rows = err and p.rows or job.rows
        if not err then
            p.catalog,p.known=job.catalog,job.seen;D.Patch(p,Options(p))
            if p.refilter then p.refilter=nil;Start(p,true);return end
        end
        p.state = err or (#p.rows > 0 and "results" or p.market and "no matching items" or "no stored data")
        local exists = false
        for _, r in ipairs(p.rows) do if r.item == p.selected then exists = true; break end end
        if not exists then p.selected = p.rows[1] and p.rows[1].item end
        Paint(p); A.Restore(p.list, view, Key); p.pendingView = nil
        if not D.SameMarket(p.market,SavedMarket(p)) or p.stamp~=Stamp(SavedMarket(p),p) then A.Schedule() end
    end
    local Advance=Step
    Step=function()
        local ok,why=pcall(Advance)
        if ok or mine~=p.token then return end
        if p.job and p.job.Cancel then p.job:Cancel() end
        p.token=p.token+1;p.job,p.dirty,p.refilter=nil,nil,nil
        p.error,p.state="failed","failed";D.Count("errors")
        p.status:SetText("Could not read observations · search saved data to retry")
        pcall(Paint,p);R.Fault("auction catalog callback",why)
    end
    C_Timer.After(0, Step)
    C_Timer.After(15, function()
        if mine ~= p.token or not p.job then return end
        p.token = p.token + 1
        if p.job.Cancel then p.job:Cancel() end
        p.job, p.error, p.state = nil, "timed out", "timed out"
        Paint(p)
    end)
end
-- Setup can fail before a new timer/deadline is installed. Invalidate and
-- clear any superseded job even when market identity/catalog construction fails.
local Begin=Start
Start=function(p,reset)
    local ok,err=pcall(Begin,p,reset)
    if ok then return end
    if p.job and p.job.Cancel then p.job:Cancel() end
    p.token=p.token+1
    p.job,p.rows,p.market,p.stamp,p.pendingView=nil,{},nil,nil,nil
    p.error,p.state="data unavailable","data unavailable"
    pcall(Paint,p)
    R.Fault("auction preview search",err)
end
local function Filter(p, name, value)
    if p[name] == value then return end
    p[name] = value
    if A.Live() then
        p.liveMode=true;p.liveSnapshot=nil;p.inspecting=false;p.returnBrowse=nil;p.showBrowseCache=false
        if p.job and p.job.Cancel then p.job:Cancel();p.job=nil end
        W.AuctionReads.Cancel("Filters changed; click Search to request fresh live results.")
        p.rows={};p.list:SetData({},"Filters changed. Click Search for fresh live results.")
        if p.categoryDrop then p.categoryDrop:Refresh();p.qualityDrop:Refresh();p.sortDrop:Refresh() end
        A.Schedule();return
    end
    p.liveMode=false -- editing research never relabels stored rows as live
    if name=="category" and p.expanded then
        local key=value
        while type(key)=="string" do
            key=key:match("^(.*)%.%d+$")
            if key then p.expanded[key]=true else break end
        end
    end
    if p.categoryDrop then p.categoryDrop:Refresh(); p.qualityDrop:Refresh() end
    if p.RefreshCategories then p.RefreshCategories() elseif p.categoryList then p.categoryList:Layout() end
    if p.exactButton then p.exactButton:SetOn(p.exact);p.tradeButton:SetOn(p.auctionable) end
    if p.sortDrop then p.sortDrop:Refresh() end
    for key, button in pairs(p.categoryButtons or {}) do button:SetOn(key == p.category) end
    for key, button in pairs(p.qualityButtons or {}) do button:SetOn(key == p.quality) end
    Start(p, true)
end
function V.Filter(name, value)
    if page and ({category=true,quality=true,exact=true,auctionable=true,sort=true})[name] then Filter(page,name,value) end
end
function V.Search(query)
    if not page then return end
    page.liveMode=false;page.researchSaved=true;page.inspecting=false;page.returnBrowse=nil;page.showBrowseCache=false
    page.query = W.Text(query, 200) or ""
    page.search:SetText(page.query)
    page.search.hint:SetShown(page.query == "" and not page.search:HasFocus())
    Start(page, true)
end
function V.Select(item, key)
    if not page then return end
    local selected=key or item
    for _,row in ipairs(page.rows or {}) do
        if Key(row)==selected and page.liveMode and row.liveKind=="browse" then
            AD.Request(item);Inspect(page,row);return
        end
    end
    page.selected=selected;AD.Request(item)
    page.detail.scroll:SetVerticalScroll(0)
    for _,r in ipairs(page.list.rows) do if r.data then r:SetSelected(Key(r.data)==selected) end end
    Detail(page)
end
function A.OpenBrowse(item, qty, opt)
    item = W.Int(item, 1, W.MAX_ID)
    if not item or not A.IsShown() then return false end
    A.Go("browse")
    if A.Live() and opt and opt.live then
        page.neededQuantity=qty;page.neededItem=item;page.researchSaved=false;page.liveMode=true;page.inspecting=true
        page.search:SetText(AD.Info(item).name)
        local ok,why=W.AuctionReads.Search({itemID=item,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0})
        if not ok then A.Note(why) end
        A.Schedule();return ok
    end
    page.researchMarketKey=opt and opt.market or nil
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
    r:RegisterForClicks("LeftButtonUp","RightButtonUp")
    r:SetScript("OnClick", function(self,button)
        local row=self.data
        if not row then return end
        if button=="RightButton" then
            R.Interact.HideTip(self)
            MenuUtil.CreateContextMenu(self,function(_,menu)
                menu:CreateTitle(row.info.name)
                if A.Live() and row.source=="live" then
                    menu:CreateButton("Quick buy…",function() A.QuickBuy(row) end)
                    menu:CreateButton("Inspect live listings",function() A.MenuSound();Inspect(page,row) end)
                end
                menu:CreateButton("Open Market history",function() A.MenuSound();A.OpenMarket(row.item,{itemKey=row.itemKey}) end)
            end)
        elseif page.search:HasFocus() and IsModifiedClick("CHATLINK") then
            page.search:SetText(row.info.name);page.search:SetCursorPosition(#page.search:GetText())
        else V.Select(row.item,Key(row)) end
    end)
    r.fill = function(self, data)
        self.data = data
        if data.source=="live" and (not data.info.known or not data.info.icon) then
            page.liveRequested=page.liveRequested or {}
            if not page.liveRequested[data.item] then
                page.liveRequested[data.item]=true;AD.Request(data.item,true)
            end
        end
        local browse=data.source=="live" and data.liveKind=="browse"
        local shift=browse and 110 or 0
        self.total:SetShown(not browse)
        self.qty:ClearAllPoints();self.qty:SetPoint("RIGHT",-222+shift,6)
        self.unit:ClearAllPoints();self.unit:SetPoint("RIGHT",-116+shift,6)
        self.name:ClearAllPoints();self.name:SetPoint("TOPLEFT",50,-10);self.name:SetPoint("RIGHT",-274+shift,0)
        self.pic.tex:SetTexture(data.info.icon or UI.ICON_BLANK); self.name:SetText(data.info.name)
        local quality=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[data.info.quality or 1]
        if quality then self.name:SetTextColor(quality.r,quality.g,quality.b) else UI.Paint(self.name,UI.K.text) end
        self.qty:SetText(data.qty and tostring(data.qty) or "—")
        self.unit:SetText(Money(data.unit)); self.total:SetText(data.source=="live" and
            (data.total and Money(data.total) or data.bid and ("Bid "..Money(data.bid)) or "—") or
            data.estimate and ("~" .. UI.Money(data.estimate)) or "—")
        self.sub:SetText((data.source=="live" and "Live experimental · " or "Stored · ") .. (data.info.category or "Metadata unavailable") .. (data.source=="live" and (data.commodity and " · available at this price" or data.priceEach and " · price per item" or data.total and " · exact listing total" or data.bid and " · bid only" or " · grouped minimum") or data.at and (" · " .. UI.Ago(data.at)) or " · no saved price"))
        self:SetSelected(not browse and page.selected == Key(data))
    end
    -- UI.Hover owns the mouse scripts. Attaching the tooltip through its
    -- supported hooks preserves highlights and refreshes recycled rows safely.
    r.TipEnter=function(self)
        local row=self.data
        if not row or not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        local link=row.link
        if not link and row.itemKey and C_AuctionHouse and C_AuctionHouse.GetItemKeySampleLink then
            local ok,value=pcall(C_AuctionHouse.GetItemKeySampleLink,row.itemKey)
            if ok and type(value)=="string" then link=value end
        end
        local ok
        if link then ok=pcall(GameTooltip.SetHyperlink,GameTooltip,link)
        elseif row.itemKey and GameTooltip.SetItemKey then
            local level
            if C_AuctionHouse and C_AuctionHouse.GetItemKeyRequiredLevel then
                local read,value=pcall(C_AuctionHouse.GetItemKeyRequiredLevel,row.itemKey)
                if read then level=value end
            end
            ok=pcall(GameTooltip.SetItemKey,GameTooltip,row.itemKey.itemID,row.itemKey.itemLevel,row.itemKey.itemSuffix,level)
        else ok=pcall(GameTooltip.SetItemByID,GameTooltip,row.item) end
        if ok then GameTooltip:Show() else GameTooltip:Hide() end
    end
    r.TipLeave=function(self) R.Interact.HideTip(self) end
    return r
end
local function BuildDetail(p)
    local d = A.Details(p, 370); p.detail = d
    d:SetPoint("TOPRIGHT", 0, -52); d:SetPoint("BOTTOMRIGHT", 0, 0)
    d.scroll:ClearAllPoints();d.scroll:SetPoint("TOPLEFT",6,-6);d.scroll:SetPoint("BOTTOMRIGHT",-24,132)
    d.summary = A.Card(d.body, "Market Summary · stored", 126)
    d.summary:SetPoint("TOPLEFT", 4, -100); d.summary:SetPoint("TOPRIGHT", -4, -100)
    d.factLines = {}
    for i=1,8 do d.factLines[i] = A.Text(d.summary,"",12,12,-31-(i-1)*18) end
    d.fresh = A.Text(d.body, "", 11, 10, -290, -8, UI.K.textDim)
    d.fresh:ClearAllPoints();d.fresh:SetPoint("TOPLEFT",12,-234);d.fresh:SetPoint("RIGHT",-8,0)
    d.fresh:SetHeight(18);d.fresh:SetWordWrap(false)
    local chartCard = A.Card(d.body, "Cheapest seen · 14 days", 222)
    chartCard:SetPoint("TOPLEFT",4,-262);chartCard:SetPoint("TOPRIGHT",-4,-262)
    d.chartCard=chartCard
    d.chart=UI.AdvancedMarketChart(chartCard,320,180)
    d.chart:SetPoint("TOPLEFT",8,-34);d.chart:SetPoint("TOPRIGHT",-8,-34)
    d.advisor = A.Card(d.body, "Item Advisor", 112)
    d.advisor:SetPoint("TOPLEFT",4,-496);d.advisor:SetPoint("TOPRIGHT",-4,-496)
    d.advice = A.Text(d.advisor, "", 14, 12, -31, -12, UI.K.bronzeText)
    d.advice:SetWordWrap(true); d.advice:SetHeight(32)
    d.evidence = A.Text(d.advisor, "", 11, 12, -68, -12, UI.K.textDim)
    d.evidence:SetWordWrap(true); d.evidence:SetHeight(38)
    UI.TipFn(d.advisor, "Item Advisor evidence", function()
        return d.recommendation and table.concat(d.recommendation.reasons or {}, "\n")
    end)
    d.body:SetHeight(574)
    d.inspect=UI.Button(d.body,"Inspect live listings",300,"secondary",function()
        local chosen=d.data
        if not (p.liveMode and chosen and chosen.itemKey) then A.Note("Select a live item group first.");return end
        Inspect(p,chosen)
    end,28)
    d.inspect:SetPoint("TOPLEFT",12,-580)
    d.market=A.HistoryButton(d.body,function()
        local row=d.data
        return row and row.item,{market=p.market and p.market.key or p.researchMarketKey,itemKey=row and row.itemKey}
    end,300)
    d.market:SetPoint("TOPLEFT",12,-620)
    d.body:SetHeight(664)
    d.footer=CreateFrame("Frame",nil,d);d.footer:SetHeight(122)
    d.footer:SetPoint("BOTTOMLEFT",4,4);d.footer:SetPoint("BOTTOMRIGHT",-4,4);UI.Panel(d.footer,"espresso")
    local quantityLabel=A.Text(d.footer,"Quantity",12,10,-8,-10,UI.K.textDim)
    d.quantity=UI.L.EditBox(d.footer,90,28);UI.CL.Dress(d.quantity,"field")
    d.quantity:SetPoint("TOPLEFT",10,-28);d.quantity:SetMaxLetters(8);d.quantity:SetNumeric(true);d.quantity:SetText("1")
    d.quantityHint=UI.Text(d.footer,11,UI.K.textDim);d.quantityHint:SetPoint("LEFT",d.quantity,"RIGHT",10,0)
    d.buy = UI.Button(d.footer, "Buy unavailable", 122, "primary", function()
        if not A.Live() then return end
        local row=d.data
        A.RequestBuy(row,tonumber(d.quantity:GetText()))
    end, 32)
    d.buy:SetPoint("BOTTOMLEFT", 10, 10); d.buy:SetEnabled(false)
    d.compare = UI.Button(d.footer, "Compare", 100, "secondary", function() d.scroll:SetVerticalScroll(98) end, 32)
    d.compare:SetPoint("LEFT", d.buy, "RIGHT", 6, 0)
    d.track = A.TrackButton(d.footer, function() return d.data and d.data.item end)
    d.track:SetPoint("BOTTOMRIGHT", -10, 10)
    function d:LayoutSummary(live)
        if self.summaryLive==live then return end
        self.summaryLive=live
        local extra=live and 0 or 58
        self.summary:SetHeight(126+extra)
        self.fresh:ClearAllPoints();self.fresh:SetPoint("TOPLEFT",12,-234-extra);self.fresh:SetPoint("RIGHT",-8,0)
        for _,entry in ipairs({{self.chartCard,262},{self.advisor,496}}) do
            entry[1]:ClearAllPoints()
            entry[1]:SetPoint("TOPLEFT",4,-entry[2]-extra);entry[1]:SetPoint("TOPRIGHT",-4,-entry[2]-extra)
        end
        self.market:ClearAllPoints();self.market:SetPoint("TOPLEFT",12,-620-extra)
        self.body:SetHeight(664+extra)
    end
end
local function Build(p)
    page = p
    p.query,p.category,p.quality,p.metadata,p.token,p.sort = "","all",-1,0,0,"Price"
    p.rows = {}
    p.search = UI.Search(p, 300, 32, "Search saved items or item ID…")
    p.search:SetPoint("TOPLEFT", 0, 0); p.search:SetMaxLetters(200)
    p.categoryDrop = A.Dropdown(p, 220, function() return p.categoryChoices or D.CATEGORIES end, function() return p.category end, function(v) Filter(p,"category",v) end)
    p.categoryDrop:SetPoint("LEFT",p.search,"RIGHT",10,0)
    p.qualityDrop = A.Dropdown(p, 160, function() return D.QUALITIES end, function() return p.quality end, function(v) Filter(p,"quality",v) end)
    p.qualityDrop:SetPoint("LEFT",p.categoryDrop,"RIGHT",10,0)
    p.sortDrop=A.Dropdown(p,146,function() return {{"Price","Lowest price"},{"PriceDesc","Highest price"},{"Name","Item name"}} end,
        function() return p.sort end,function(v) Filter(p,"sort",v) end)
    p.sortDrop:SetPoint("LEFT",p.qualityDrop,"RIGHT",10,0)
    p.submit = UI.Button(p,"Search Saved Data",164,"primary",function()
        if A.Live() then SubmitLive(p) else V.Search(p.search:GetText()) end
    end,32)
    p.submit:SetPoint("TOPRIGHT",0,0)
    p.search:SetScript("OnEnterPressed",function(self) self:ClearFocus();if A.Live() then SubmitLive(p) else V.Search(self:GetText()) end end)
    p.search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    p.search:HookScript("OnTextChanged",function(self)
        self.hint:SetShown(self:GetText()=="" and not self:HasFocus())
    end)
    local filters = A.Card(p,"Category",540); p.filters=filters
    filters:SetWidth(222); filters:SetPoint("TOPLEFT",0,-52); filters:SetPoint("BOTTOMLEFT",0,0)
    p.categoryButtons={}
    p.expanded={}
    local function SetTree(tree,byID)
        p.nativeReady=#tree>0;p.nativeByID=byID
        filters.heading:SetText(p.nativeReady and "Categories" or "Saved item groups")
        if #tree==0 then
            for _,e in ipairs(D.CATEGORIES) do tree[#tree+1]={key=e[1],name=e[2],depth=0} end
        end
        p.categoryTree=tree;p.categoryChoices={{"all","All Categories"}}
        local function Choices(nodes,indent)
            for _,n in ipairs(nodes) do
                if n.key~="all" then p.categoryChoices[#p.categoryChoices+1]={n.key,indent..n.name} end
                Choices(n.children or {},indent.."  ")
            end
        end
        Choices(tree,"")
    end
    SetTree(W.AuctionCategories.Tree())
    local Refresh
    local function CategoryRow(parent)
        local r=CreateFrame("Button",nil,parent); UI.Hover(r)
        r.text=A.Text(r,"",13,22,-6,-8);r.text:SetWordWrap(true);r.text:SetHeight(32)
        r.art=r:CreateTexture(nil,"ARTWORK");r.art:SetSize(28,28)
        r.arrow=UI.Chevron(r,18);r.arrow:SetWidth(10);r.arrow:SetHeight(18)
        r.arrow:SetPoint("LEFT",7,0)
        r:SetScript("OnClick",function()
            local n=r.data
            if not n then return end
            if #(n.children or {})>0 then p.expanded[n.key]=not p.expanded[n.key] end
            Filter(p,"category",n.key); Refresh()
        end)
        r.fill=function(self,n)
            self.data=n
            self.text:ClearAllPoints();self.text:SetPoint("TOPLEFT",56+n.depth*6,-6);self.text:SetPoint("RIGHT",-8,0)
            self.text:SetText(n.name)
            self.art:ClearAllPoints();self.art:SetPoint("LEFT",22+n.depth*6,0)
            UI.Art(self.art,W.AuctionCategories.Art(n),28)
            self.arrow:ClearAllPoints();self.arrow:SetPoint("LEFT",7+n.depth*6,0)
            self.arrow:SetShown(#(n.children or {})>0)
            self.arrow:SetText(p.expanded[n.key] and "▾" or "›")
            self.arrow:SetAlpha(p.expanded[n.key] and 1 or 0.65)
            UI.Paint(self.text,n.depth==0 and UI.K.bronzeText or UI.K.text)
            self:SetSelected(p.category==n.key)
        end
        r.TipEnter=function(self)
            if not self.data or not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText(self.data.name);GameTooltip:Show()
        end
        r.TipLeave=function(self) R.Interact.HideTip(self) end
        return r
    end
    p.categoryList=UI.List(filters,42,CategoryRow,360,false)
    p.categoryList.box:SetPoint("TOPLEFT",6,-36);p.categoryList.box:SetPoint("BOTTOMRIGHT",-6,184)
    Refresh=function()
        local rows={}
        if p.nativeReady then rows[1]={key="all",name="All Categories",depth=0} end
        local function Add(nodes)
            for _,n in ipairs(nodes) do rows[#rows+1]=n;if p.expanded[n.key] then Add(n.children or {}) end end
        end
        Add(p.categoryTree);p.categoryList:SetData(rows);p.categoryDrop:Refresh()
    end
    p.UpdateCategories=function()
        if p.nativeReady then return end
        local tree,byID=W.AuctionCategories.Tree()
        if #tree>0 then SetTree(tree,byID);p.category="all";Refresh();if not p.liveMode then Start(p,false) end end
    end
    p.RefreshCategories=Refresh
    Refresh()
    UI.Tip(filters,"Category hierarchy","Uses the loaded Forever category tree and native filters. Before native category data is available, saved research offers broad item groups. Native categories become available after a normal auctioneer visit.")
    p.qualityButtons={}
    p.exactButton=UI.Segment(filters,"Exact name only",194,function() Filter(p,"exact",not p.exact); p.exactButton:SetOn(p.exact) end)
    p.exactButton:SetPoint("BOTTOMLEFT",12,146)
    p.tradeButton=UI.Segment(filters,"Tradeable types",194,function() Filter(p,"auctionable",not p.auctionable); p.tradeButton:SetOn(p.auctionable) end)
    p.tradeButton:SetPoint("BOTTOMLEFT",12,112)
    UI.Tip(p.tradeButton,"Tradeable item types","Filters known unbound/BoE/BoU base types. This is not proof that an owned copy can currently be auctioned. Unknown binding metadata is excluded.")
    p.reset=UI.Button(filters,"Reset Filters",194,"secondary",function()
        p.category,p.quality,p.exact,p.auctionable,p.forceItem,p.sort="all",-1,false,false,nil,"Price"
        p.exactButton:SetOn(false); p.tradeButton:SetOn(false);p.categoryList:Layout()
        p.categoryDrop:Refresh(); p.qualityDrop:Refresh();p.sortDrop:Refresh()
        for key,b in pairs(p.categoryButtons) do b:SetOn(key=="all") end
        for _,b in pairs(p.qualityButtons) do b:SetOn(false) end
        V.Search("")
    end,30)
    p.reset:SetPoint("BOTTOMLEFT",12,12)
    local tableCard=A.Card(p,"Stored observations",100); p.tableCard=tableCard
    tableCard:SetPoint("TOPLEFT",filters,"TOPRIGHT",10,0); tableCard:SetPoint("BOTTOMRIGHT",-380,0)
    tableCard.heading:Hide()
    local function Head(text,w,x)
        local h=UI.Head(tableCard,text,w,"RIGHT"); h:SetPoint("TOPRIGHT",x,-14);return h
    end
    local itemHead=A.Text(tableCard,"Item",13,14,-14,-280,UI.K.bronzeText);p.itemHead=itemHead
    p.back=UI.Button(tableCard,"‹ Back to search results",210,"secondary",function() Back(p) end,28)
    p.back:SetPoint("TOPLEFT",10,-8);p.back:Hide();p.itemHead=itemHead
    p.back=UI.Button(tableCard,"‹ Back to search results",210,"secondary",function() Back(p) end,28)
    p.back:SetPoint("TOPLEFT",8,-8);p.back:Hide()
    p.qtyHead=Head("Seen qty*",64,-246); p.unitHead=Head("Seen / item",100,-138); p.totalHead=Head("Est. value*",110,-28)
    p.list=UI.List(tableCard,56,MakeRow,360,false)
    p.list.box:SetPoint("TOPLEFT",4,-36); p.list.box:SetPoint("BOTTOMRIGHT",-4,72)
    p.status=A.Text(tableCard,"",12,12,-1,-12,UI.K.textDim)
    p.status:ClearAllPoints(); p.status:SetPoint("BOTTOMLEFT",12,46); p.status:SetPoint("RIGHT",-12,0)
    local scope=A.Text(tableCard,"*Aggregated quantity at the cheapest tier.\nStored history; no current auctions or exact stacks.",11,12,-1,-12,UI.K.textDim)
    scope:ClearAllPoints(); scope:SetPoint("BOTTOMLEFT",12,12); scope:SetPoint("RIGHT",-12,0); scope:SetWordWrap(true); scope:SetHeight(30)
    p.scope=scope
    p.liveState=A.Text(tableCard,"Saved Market Data · historical observations",11,12,-1,-12,UI.K.textDim)
    p.liveState:ClearAllPoints();p.liveState:SetPoint("BOTTOMLEFT",12,86)
    p.live=UI.Button(filters,"Prepare live search",194,"secondary",function()
        if p.inspecting and p.returnBrowse then Back(p) else SubmitLive(p) end
    end,26)
    p.live:SetPoint("BOTTOMLEFT",12,64)
    UI.TipFn(p.live,"Browse auctions",function()
        return p.inspecting and p.returnBrowse and "Return to your previous search results and scroll position." or "Search current auctions using these filters."
    end)
    p.more=UI.Button(tableCard,"More results",112,"secondary",function()
        local ok,why=W.AuctionReads.More();if not ok then A.Note(why) end
    end,24);p.more:SetPoint("BOTTOMRIGHT",-12,8);p.more:Hide()
    p.refreshLive=UI.Button(tableCard,"Refresh",90,"secondary",function()
        if p.showBrowseCache then SubmitLive(p);return end
        local ok,why=W.AuctionReads.Refresh();if not ok then A.Note(why) end
    end,24);p.refreshLive:SetPoint("RIGHT",p.more,"LEFT",-6,0);p.refreshLive:Hide()
    BuildDetail(p)
    p:SetScript("OnEvent",function(_,event,item,ok)
        if p.liveMode then
            local payload=W.Plain(item)
            local id=W.Int(type(payload)=="table" and W.Plain(payload.itemID) or payload,1,W.MAX_ID)
            if ok~=false and id and p.liveKnown and p.liveKnown[id] then p.liveDirty=p.liveDirty or {};p.liveDirty[id]=true end
            A.Schedule();return
        end
        if event=="GET_ITEM_INFO_RECEIVED" or event=="ITEM_DATA_LOAD_RESULT" or event=="ITEM_KEY_ITEM_INFO_RECEIVED" then D.Metadata(p,item,ok) end
        A.Schedule()
    end)
end
SubmitLive=function(p)
    local node=p.nativeByID and p.nativeByID[p.category]
    local query,reason=W.AuctionReads.BrowseQuery({text=p.search:GetText(),category=node,quality=p.quality,exact=p.exact,
        sort=p.sort=="Name" and "Name" or "Price",reverse=p.sort=="PriceDesc"})
    if not query then A.Note(reason);return false end
    if p.job and p.job.Cancel then p.job:Cancel() end
    p.token=p.token+1;p.job=nil;p.rows={};p.liveMode=true;p.researchSaved=false;p.liveSnapshot=nil;p.detail.cached=nil;p.inspecting=false
    p.returnBrowse=nil;p.showBrowseCache=false;p.liveRequested={}
    p.list:SetData({},"Waiting for a live search response…")
    local ok,why=W.AuctionReads.Begin("browse",query)
    if not ok then p.list:SetData({},why);A.Note(why) end
    A.Schedule();return ok
end
Inspect=function(p,row)
    if not row or not row.itemKey then return false end
    local previous=p.liveSnapshot
    if previous and previous.kind=="browse" then
        p.returnBrowse={snapshot=previous,view=A.Capture(p.list,Key),text=p.search:GetText(),category=p.category,quality=p.quality,sort=p.sort,exact=p.exact}
    end
    local ok,why
    if A.Live() then ok,why=W.AuctionReads.Search(row.itemKey)
    else ok,why=W.AuctionReads.Begin("item",row.itemKey) end
    if not ok then A.Note(why);return false end
    p.showBrowseCache=false;p.inspecting=true;p.liveSnapshot=nil;p.rows={};p.selected=nil;p.liveKnown=nil;p.liveRequested={};p.detail.cached=nil
    p.detail.scroll:SetVerticalScroll(0)
    p.list:SetData({},"Loading live listings…")
    A.Schedule();return true
end
Back=function(p)
    local previous=p.returnBrowse
    if not previous then return end
    p.showBrowseCache=true;p.liveMode=true;p.researchSaved=false;p.inspecting=false;p.liveSnapshot=nil;p.selected=nil
    p.search:SetText(previous.text);p.category,p.quality,p.sort,p.exact=previous.category,previous.quality,previous.sort,previous.exact
    p.categoryDrop:Refresh();p.qualityDrop:Refresh();p.sortDrop:Refresh();p.exactButton:SetOn(p.exact);p.categoryList:Layout()
    A.Render();A.Restore(p.list,previous.view,Key)
end
local function LayoutResults(p,details)
    local offset=details and p.returnBrowse and 40 or 0
    if p.detailsShown==details and p.headerOffset==offset then return end
    p.detailsShown,p.headerOffset=details,offset
    p.detail:SetShown(details);p.back:SetShown(offset>0)
    p.itemHead:ClearAllPoints();p.itemHead:SetPoint("TOPLEFT",14,-14-offset);p.itemHead:SetPoint("RIGHT",-280,0)
    p.list.box:ClearAllPoints();p.list.box:SetPoint("TOPLEFT",4,-36-offset);p.list.box:SetPoint("BOTTOMRIGHT",-4,72)
    p.tableCard:ClearAllPoints()
    p.tableCard:SetPoint("TOPLEFT",p.filters,"TOPRIGHT",10,0)
    p.tableCard:SetPoint("BOTTOMRIGHT",details and -380 or 0,0)
    p.list:Layout()
end
local function PriceColumns(p, browse)
    local shift=browse and 110 or 0
    p.totalHead:SetShown(not browse)
    p.totalHead:ClearAllPoints();p.totalHead:SetPoint("TOPRIGHT",-28,-14-(p.headerOffset or 0))
    p.qtyHead:ClearAllPoints();p.qtyHead:SetPoint("TOPRIGHT",-246+shift,-14-(p.headerOffset or 0))
    p.unitHead:ClearAllPoints();p.unitHead:SetPoint("TOPRIGHT",-138+shift,-14-(p.headerOffset or 0))
end
local function Render(p)
    -- Metadata events are needed in live mode too. Registration used to sit
    -- below that mode's early return, leaving names/icons unresolved forever.
    if not p.listening then
        W.Strategy.Listen(A.Schedule,true)
        for _,event in ipairs({"GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT","ITEM_KEY_ITEM_INFO_RECEIVED","BAG_UPDATE_DELAYED",
            "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED","ITEM_SEARCH_RESULTS_UPDATED","AUCTION_HOUSE_BROWSE_FAILURE","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_SHOW"}) do p:RegisterEvent(event) end
        p.eventCount=9;p.listening=true
    end
    local native=AuctionHouseFrame
    if native and native.SetSearchText and not linkHooks[native] and hooksecurefunc then
        hooksecurefunc(native,"SetSearchText",function(_,text)
            -- Follow the client's shift-click link path; never replace chat or
            -- bag handlers, and never send a search until Search/Enter is used.
            if A.IsShown() and A.Live() and A.Mode()=="browse" and p.search:HasFocus() and IsModifiedClick("CHATLINK") then
                local name=W.Text(text,200)
                if name then p.search:SetText(name);p.search:SetCursorPosition(#name) end
            end
        end)
        linkHooks[native]=true
    end
    p.UpdateCategories()
    if A.Live() and not p.researchSaved and not p.liveMode then
        p.liveMode=true;p.rows={};p.liveSnapshot=nil;p.list:SetData({},"Search the live Auction House. No request starts when this page opens.")
    end
    p.submit.text:SetText(A.Live() and "Search" or "Search Saved Data")
    p.live.text:SetText(A.Live() and (p.inspecting and p.returnBrowse and "Back to search results" or "Search live auctions") or "Prepare live search")
    p.tradeButton:SetEnabled(not A.Live())
    p.more:SetShown(A.Live() and p.liveMode==true);p.refreshLive:SetShown(A.Live() and p.liveMode==true)
    local reads=W.AuctionReads
    if p.liveMode then
        local display=p.showBrowseCache and p.returnBrowse and p.returnBrowse.snapshot or reads.snapshot
        local kind=display and display.kind
        if kind=="item" or kind=="commodity" then p.inspecting=true elseif kind=="browse" then p.inspecting=false end
        LayoutResults(p,p.inspecting==true)
        p.detail.inspect:Hide()
        PriceColumns(p,kind==nil or kind=="browse")
        p.qtyHead:SetText("Available")
        p.totalHead:SetText(kind=="item" and "Buyout / bid" or "Value at price")
        p.unitHead:SetText((kind==nil or kind=="browse") and "Lowest price" or "Unit price")
        p.scope:SetText(A.Live() and "Available quantities are not stacks. Item buyouts are per item.\nCommodity purchases require a separately reviewed quote." or "Explicit experimental response · read-only.\nGrouped minima are not exact listing totals.")
        p.more:SetEnabled(not p.showBrowseCache and reads.Pending()==0 and reads.Fresh() and reads.snapshot~=nil and not reads.snapshot.complete and #reads.snapshot.rows<reads.MAX)
        p.refreshLive:SetEnabled(reads.Pending()==0 and (p.showBrowseCache or reads.snapshot~=nil))
        local snap=display
        if snap and (snap.epoch~=reads.epoch or not reads.Available()) then snap=nil end
        p.liveState:SetText("Live Auction House · experimental · " .. reads.state)
        if snap and snap~=p.liveSnapshot and (snap.kind=="browse" or snap.kind=="item" or snap.kind=="commodity") then
            local view=A.Capture(p.list,Key)
            p.liveSnapshot=snap;p.rows={};p.liveKnown={};p.liveDirty=nil;p.detail.cached=nil
            for _,r in ipairs(snap.rows) do
                local row={};for key,value in pairs(r) do row[key]=value end
                row.info=LiveInfo(row);row.source="live";row.liveKind=snap.kind;p.rows[#p.rows+1]=row;p.liveKnown[row.item]=true
            end
            local selected
            if snap.kind~="browse" then
                for _,row in ipairs(p.rows) do if Key(row)==p.selected then selected=p.selected;break end end
                selected=selected or (p.rows[1] and Key(p.rows[1]))
            end
            p.selected=selected
            p.list:SetData(p.rows,snap.complete and "Live search completed: no auctions returned." or "No validated rows; this response is partial or unverified.")
            p.status:SetText(snap.complete and "Current search results" or "Partial / completeness unverified · no purchase actions")
            Detail(p);A.Restore(p.list,view,Key)
        elseif snap and p.liveDirty then
            for _,row in ipairs(p.rows) do if p.liveDirty[row.item] then row.info=LiveInfo(row) end end
            A.PatchRows(p.list,p.liveDirty);p.liveDirty=nil;p.detail.cached=nil;Detail(p)
        elseif not snap and reads.state~="loading" then
            p.rows={};p.liveKnown=nil;p.list:SetData({},"Live search: "..reads.state..". Click Search to request results.")
            p.status:SetText("Live results unavailable");Detail(p)
        end
        if snap then
            p.status:SetText(not reads.Fresh(snap) and "Last search results · refresh to check current availability"
                or snap.complete and "Current search results" or "Partial / completeness unverified · no purchase actions")
            Detail(p) -- freshness changes also update review controls without clearing rows
        end
        return
    end
    LayoutResults(p,true)
    p.detail.inspect:Hide()
    PriceColumns(p,false)
    p.qtyHead:SetText("Seen qty*");p.unitHead:SetText("Seen / item");p.totalHead:SetText("Est. value*")
    p.scope:SetText("*Aggregated quantity at the cheapest tier.\nStored history; no current auctions or exact stacks.")
    p.liveState:SetText("Saved Market Data · historical observations")
    local market=SavedMarket(p)
    if p.job then return end
    if not p.stamp or not D.SameMarket(p.market,market) or p.stamp~=Stamp(market,p) then Start(p,false)
    else
        local view=A.Capture(p.list,Key)
        local changed,structural,selected,updates=D.Patch(p,Options(p))
        if changed and structural then p.detail.cached=nil;Paint(p);A.Restore(p.list,view,Key)
        else
            if changed then A.PatchRows(p.list,updates);if selected then p.detail.cached=nil end end
            Detail(p)
        end
    end
end
local function Release(p)
    if not A.IsShown() then p.researchMarketKey=nil end
    p.viewport=p.pendingView or A.Capture(p.list,Key)
    if p.liveMode then W.AuctionReads.Cancel("canceled");p.liveMode=false;p.liveSnapshot=nil end
    p.state="canceled"
    if p.job and p.job.Cancel then p.job:Cancel() end
    p.catalog,p.known,p.dirty,p.refilter=nil,nil,nil,nil
    p.returnBrowse,p.showBrowseCache=nil,nil
    p.liveKnown,p.liveDirty,p.liveRequested=nil,nil,nil
    p.token=p.token+1; p.job,p.rows,p.market,p.stamp,p.pendingView=nil,nil,nil,nil,nil
    p.list:SetData({}); p:UnregisterAllEvents(); p.listening=false
    W.Strategy.Listen(A.Schedule,false)
    for _,r in ipairs(p.list.rows) do r.data=nil end
    p.detail.data,p.detail.cached,p.detail.recommendation=nil,nil,nil
    p.inspecting,p.detailsShown=nil,nil
end
A.Register("browse",{Build=Build,Render=Render,Release=Release})
