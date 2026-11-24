-- AH-3 Shopping presentation over the existing shared planner, inventory and
-- source decisions. No buys, inventory writes, queue edits or second engine.
local R,W=TwichUI,TwichUI.Workshop
local A,UI,P,S=W.AuctionUI,W.UI,W.AuctionShoppingData,W.Session
local page
local SOURCE={auction="Auction House",vendor="Vendor",make="Craft",collect="Collect",none="No source"}
local function Key(r) return r.key end
local function Num(n) return n~=nil and tostring(n) or "Unknown" end
local function Watch() if A.Mode()=="shopping" then A.Schedule() end end
local function StockWatch() W.Strategy.Bump();Watch() end
local function Select(key)
    if not page then return end
    page.selected=key;page.detail.scroll:SetVerticalScroll(0);A.Render()
end
local function Evidence(d,view,p)
    local row=view.row
    local lines=W.Shopping.Basis(row,function(id) return W.AdvisorData.Info(id).name end,UI.Money,W.Prices.AgeText,p.ctx.now)
    local text={}
    for _,line in ipairs(lines) do text[#text+1]=line[1]..(line[2] and ": "..line[2] or "") end
    d.basis=table.concat(text,"\n")
end
local function QuickBuy(v)
    if not A.Live() or not page.current or not v or v.row.kind~="buy" then return end
    local qty=W.Int(v.row.qty,1,W.MAX_ID)
    if not qty then return end
    A.QuickBuy({item=v.row.item,itemKey=W.AuctionReads.Key({itemID=v.row.item}),info=v.info},qty)
end
local function Purposes(d,v)
    local items=v and P.PurposeItems(v.row) or {}
    d.purposeRows=d.purposeRows or {}
    d.needed:SetText(#items==0 and (v and v.purpose or "") or "")
    for i,data in ipairs(items) do
        local b=d.purposeRows[i]
        if not b then
            b=CreateFrame("Button",nil,d.used);UI.Hover(b)
            b:SetPoint("TOPLEFT",10,-28-(i-1)*36);b:SetPoint("RIGHT",-10,0);b:SetHeight(34)
            b.pic=UI.ItemIcon(b,28);b.pic:SetPoint("LEFT",2,0)
            b.name=A.Text(b,"",12,38,-6,-6);b.name:SetHeight(24)
            b.TipEnter=function(self)
                if not self.item or not GameTooltip then return end
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                if self.link then GameTooltip:SetHyperlink(self.link) else GameTooltip:SetItemByID(self.item) end
                GameTooltip:Show()
            end
            b.TipLeave=function(self) R.Interact.HideTip(self) end
            b:SetScript("OnClick",function(self) if self.link and HandleModifiedItemClick then HandleModifiedItemClick(self.link) end end)
            d.purposeRows[i]=b
        end
        local info=W.AdvisorData.Info(data.item)
        b.item,b.link=data.item,info.link
        b.pic.tex:SetTexture(info.icon or UI.ICON_BLANK);b.name:SetText(info.known and info.name or data.name)
        UI.ItemQuality(b.name, info.quality)
        if not info.known and not d.purposeRequested[data.item] then d.purposeRequested[data.item]=true;W.AdvisorData.Request(data.item,true) end
        b:Show()
    end
    for i=#items+1,#d.purposeRows do d.purposeRows[i].item=nil;d.purposeRows[i]:Hide() end
    local h=math.max(62,32+#items*36)
    d.used:SetHeight(h)
    d.adviceCard:ClearAllPoints();d.adviceCard:SetPoint("TOPLEFT",d.used,"BOTTOMLEFT",0,-8);d.adviceCard:SetPoint("TOPRIGHT",d.used,"BOTTOMRIGHT",0,-8)
    d.market:ClearAllPoints();d.market:SetPoint("TOPLEFT",d.adviceCard,"BOTTOMLEFT",8,-14)
    d.body:SetHeight(564+h+8+68+14+42)
    A.BindSounds(d.used)
end
local function Detail(p)
    local d,selected=p.detail
    for _,v in ipairs(p.rows) do if v.key==p.selected then selected=v;break end end
    if not selected and p.rows[1] then selected=p.rows[1];p.selected=selected.key end
    d.data=selected
    d.buy:SetEnabled(A.Live() and selected~=nil and p.current and selected.row.kind=="buy" and W.Int(selected.row.qty,1,W.MAX_ID)~=nil)
    d.buy.text:SetText(A.Live() and "Quick buy needed…" or "Purchasing unavailable")
    d.track:SetEnabled(selected~=nil)
    d.market:SetEnabled(selected~=nil)
    d.browse:SetEnabled(selected~=nil and p.current)
    d.vendor:SetEnabled(selected~=nil and p.current and p.ctx.sellers and p.ctx.sellers[selected.row.item]~=nil)
    local recipe=selected and selected.row.make and selected.row.make.rec
    d.recipe:SetEnabled(p.current and recipe~=nil)
    d.recipeID=recipe and recipe.id
    for _,b in pairs(d.choices) do b:SetEnabled(false);b:SetOn(false) end
    if not selected then
        local incomplete=P.Incomplete(p.plan,p.ctx)
        d.track.text:SetText("Track")
        d.pic.tex:SetTexture(UI.ICON_BLANK);d.name:SetText(incomplete and "Requirements unavailable" or "No missing materials")
        UI.ItemQuality(d.name, nil)
        d.kind:SetText(incomplete and "Some recipe or bag data is missing." or "The shared Workshop queue is unchanged.")
        d.quantities:SetText(incomplete and "Unknown quantities are not counted as owned." or "Choose a material to inspect its quantities.")
        d.sourceText:SetText("");d.cost:SetText("Unknown");d.costNote:SetText("")
        Purposes(d,nil);d.advice:SetText(incomplete and "Open the profession and refresh stock." or "Add recipes in Workshop to build a shopping list.")
        d.chart:Set(nil,UI.Money);d.basis=nil;return
    end
    local r=selected.row
    d.name:SetText(selected.info.name);d.pic.tex:SetTexture(selected.info.icon or UI.ICON_BLANK)
    UI.ItemQuality(d.name, selected.info.quality)
    d.kind:SetText(selected.info.category or "Metadata unavailable")
    d.quantities:SetText("Required: "..Num(r.need).."    In bags: "..Num(r.have).."\n"..
        (r.kind=="collect" and "To collect: " or "Still to get: ")..Num(r.qty)..
        ((r.made or 0)>0 and (" · From queued crafts: "..r.made) or ""))
    local cost,note=P.Cost(r,UI.Money)
    d.cost:SetText(cost or "Price unknown")
    d.costNote:SetText((note or (r.at and ("Observed "..UI.Ago(r.at)) or "Source/price may be unavailable."))..
        (p.ctx.stale and " Previous plan; quantities may change." or ""))
    d.sourceText:SetText((r.picked and "Your choice: " or "")..SOURCE[selected.source]..
        (r.kind=="collect" and (r.where=="guild" and " · guild bank" or " · personal bank") or "")..
        (r.kind=="collect" and "\nStored stock may have changed." or ""))
    if r.kind~="collect" and p.current then
        local choices={}
        for _,k in ipairs(W.Shopping.Choices(r)) do choices[k]=true end
        for k,b in pairs(d.choices) do b:SetEnabled(choices[k]==true and not W.Queue.Held());b:SetOn(r.source==k) end
    end
    Purposes(d,selected)
    local market=W.Market.Source().market
    local projection=W.AuctionMarketData.Project(r.item,market,14)
    d.chart:Set(projection and projection.series,UI.Money,r.item..":shopping:"..tostring(market and market.key))
    local rec=W.AdvisorData.Decide(r.item,false)
    d.advice:SetText((rec.text or "Limited evidence")..(p.current and "" or "\nWait for the plan to finish."))
    d.advisorTip=table.concat(rec.reasons or {},"\n")
    d.track.text:SetText(W.AdvisorData.Tracked()[r.item] and "Untrack" or "Track")
    Evidence(d,selected,p)
end
local function Row(parent)
    local r=CreateFrame("Button",nil,parent);UI.Hover(r)
    r.pic=UI.ItemIcon(r,34);r.pic:SetPoint("LEFT",8,0)
    r.name=A.Text(r,"",14,50,-8,-506)
    r.sub=A.Text(r,"",11,50,-31,-12,UI.K.textDim)
    local function Cell(w,x)
        local t=UI.Text(r,12,UI.K.text);t:SetWidth(w);t:SetJustifyH("RIGHT");t:SetPoint("RIGHT",x,7);return t
    end
    r.need=Cell(46,-454);r.have=Cell(46,-402);r.missing=Cell(46,-350)
    r.source=Cell(82,-246);r.cost=Cell(110,-126)
    r.buy=UI.Button(r,"Quick buy…",108,"secondary",function() QuickBuy(r.data) end,28)
    r.buy:SetPoint("RIGHT",-8,0);A.BindSound(r.buy)
    UI.CL.Font(r.source,11)
    r.sourceIcon=r:CreateTexture(nil,"ARTWORK");r.sourceIcon:SetSize(18,18);r.sourceIcon:SetPoint("RIGHT",-332,7)
    r:SetScript("OnClick",function(self) if self.data then Select(self.data.key) end end)
    r.fill=function(self,v)
        self.data=v
        self.pic.tex:SetTexture(v.info.icon or UI.ICON_BLANK)
        self.name:SetText(v.info.name)
        self.need:SetText(Num(v.need));self.have:SetText(Num(v.have));self.missing:SetText(Num(v.missing))
        local cue=P.Cue(v.row)
        self.source:SetText(cue[1]);UI.Art(self.sourceIcon,cue[2],18)
        UI.Paint(self.source,v.source=="auction" and UI.K.bronzeText or UI.K.text)
        self.cost:SetText((P.Cost(v.row,UI.Money)) or "Unknown")
        self.buy:SetEnabled(A.Live() and page.current and v.row.kind=="buy" and W.Int(v.missing,1,W.MAX_ID)~=nil)
        UI.ItemQuality(self.name, v.info.quality)
        if not v.info.known and not page.itemRequested[v.row.item] then page.itemRequested[v.row.item]=true;W.AdvisorData.Request(v.row.item,true) end
        self.sub:SetText(v.row.picked and "Your source choice" or v.row.kind=="collect" and
            (v.row.where=="guild" and "Guild bank stock" or "Personal bank stock") or
            v.row.kind=="make" and "Planned craft" or v.row.at and ("Observed "..UI.Ago(v.row.at)) or "")
        self:SetSelected(page.selected==v.key)
    end
    r.TipEnter=function(self)
        if not self.data or not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        local v=self.data
        if v.info.link then GameTooltip:SetHyperlink(v.info.link) else GameTooltip:SetItemByID(v.row.item) end
        GameTooltip:Show()
    end
    r.TipLeave=function(self) R.Interact.HideTip(self) end
    return r
end
local function BuildDetail(p)
    local d=A.Details(p,400);p.detail=d
    d:SetPoint("TOPRIGHT",0,-52);d:SetPoint("BOTTOMRIGHT",0,0)
    d.kind:ClearAllPoints();d.kind:SetPoint("TOPLEFT",12,-74);d.kind:SetPoint("RIGHT",-12,0)
    local q=A.Card(d.body,"Quantities",56);q:SetPoint("TOPLEFT",4,-90);q:SetPoint("TOPRIGHT",-4,-90)
    d.quantities=A.Text(q,"",11,12,-28);d.quantities:SetWordWrap(true);d.quantities:SetHeight(24)
    local sources=A.Card(d.body,"Acquisition source",98)
    sources:SetPoint("TOPLEFT",4,-154);sources:SetPoint("TOPRIGHT",-4,-154)
    d.sourceText=A.Text(sources,"",11,12,-32);d.sourceText:SetHeight(28);d.sourceText:SetWordWrap(true)
    d.choices={}
    for i,k in ipairs({"vendor","auction","make"}) do
        local b=UI.Segment(sources,SOURCE[k],106,function()
            local v=d.data
            if v and p.current then
                local choice=k
                if S.picks[v.row.item]==k then choice=nil end
                S.PickSource(v.row.item,choice);A.Schedule()
            end
        end)
        b:SetPoint("TOPLEFT",12+(i-1)*112,-64);d.choices[k]=b
    end
    local costs=A.Card(d.body,"Cost Summary",74)
    costs:SetPoint("TOPLEFT",4,-260);costs:SetPoint("TOPRIGHT",-4,-260)
    d.cost=A.Text(costs,"",15,12,-28,-12,UI.K.bronzeText)
    d.costNote=A.Text(costs,"",11,12,-47);d.costNote:SetWordWrap(true);d.costNote:SetHeight(22)
    UI.TipFn(costs,"Source and cost evidence",function() return d.basis end)
    local chart=A.Card(d.body,"Cheapest seen · observed days",214)
    chart:SetPoint("TOPLEFT",4,-342);chart:SetPoint("TOPRIGHT",-4,-342)
    d.chart=UI.AdvancedMarketChart(chart,342,176);d.chart:SetPoint("TOPLEFT",8,-28);d.chart:SetPoint("TOPRIGHT",-8,-28)
    local used=A.Card(d.body,"Needed For",62);d.used=used;d.purposeRequested={}
    used:SetPoint("TOPLEFT",4,-564);used:SetPoint("TOPRIGHT",-4,-564)
    d.needed=A.Text(used,"",11,12,-29);d.needed:SetWordWrap(true);d.needed:SetHeight(24)
    local advice=A.Card(d.body,"Item Advisor",68);d.adviceCard=advice
    advice:SetPoint("TOPLEFT",4,-500);advice:SetPoint("TOPRIGHT",-4,-500)
    d.advice=A.Text(advice,"",11,12,-29);d.advice:SetWordWrap(true);d.advice:SetHeight(34)
    UI.TipFn(advice,"Advisor evidence",function() return d.advisorTip end)
    d.market=A.HistoryButton(d.body,function() return d.data and d.data.row.item end,300)
    d.market:SetPoint("TOPLEFT",12,-582)
    d.body:SetHeight(626)
    d.vendor=UI.Button(d,"Show vendor",91,"secondary",function()
        if d.data and p.current then S.ShowVendor(d.data.row.item) end
    end,28);d.vendor:SetPoint("BOTTOMLEFT",7,10)
    d.browse=UI.Button(d,"Browse",99,"secondary",function()
        local v=d.data
        if v and p.current then A.OpenBrowse(v.row.item,v.row.qty,A.Live() and {live=true} or nil) end
    end,28);d.browse:SetPoint("LEFT",d.vendor,"RIGHT",4,0)
    d.recipe=UI.Button(d,"Open recipe",91,"secondary",function()
        if d.recipeID and p.current then S.OpenRecipe(d.recipeID) end
    end,28);d.recipe:SetPoint("LEFT",d.browse,"RIGHT",4,0)
    d.track=A.TrackButton(d,function() return d.data and d.data.row.item end)
    d.track:SetWidth(86);d.track:SetHeight(28);d.track:SetPoint("BOTTOMRIGHT",-7,10)
    -- Reuse the existing purchase-action area for an individually reviewed search.
    d.buy=UI.Button(p,"Purchasing unavailable",186,"primary",function()
        if not A.Live() then return end
        local v=d.data
        if v and p.current then QuickBuy(v) end
    end,30)
    d.buy:SetPoint("BOTTOMRIGHT",d,"BOTTOMLEFT",-24,12);d.buy:SetEnabled(false)
end

local function Build(p)
    page=p;p.eventCount=6;p.itemRequested={};p.query,p.source,p.group="","all","item";p.rows={}
    p.search=UI.Search(p,300,32,"Search needed items…")
    p.search:SetPoint("TOPLEFT",0,0);p.search:SetMaxLetters(200)
    local function Change()
        p.resetView=true;p.search:ClearFocus();A.Render()
    end
    p.search:SetScript("OnEnterPressed",function(self) p.query=W.Text(self:GetText(),200) or "";Change() end)
    p.search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    p.sourceDrop=A.Dropdown(p,164,function() return P.SOURCES end,function() return p.source end,function(v) p.source=v;Change() end)
    p.sourceDrop:SetPoint("LEFT",p.search,"RIGHT",10,0)
    p.groupDrop=A.Dropdown(p,190,function() return P.GROUPS end,function() return p.group end,function(v) p.group=v;Change() end)
    p.groupDrop:SetPoint("LEFT",p.sourceDrop,"RIGHT",10,0)
    p.refresh=UI.Button(p,"Refresh stock",140,"secondary",function() W.Strategy.Bump();A.Render() end,32)
    p.refresh:SetPoint("TOPRIGHT",0,0)
    UI.Tip(p.refresh,"Refresh stock","Re-read the existing plan against current bag and remembered bank stock. No scan, purchase or inventory move.")
    local tableCard=A.Card(p,"Shopping requirements",200);p.tableCard=tableCard
    tableCard:SetPoint("TOPLEFT",0,-52);tableCard:SetPoint("BOTTOMRIGHT",-410,0);tableCard.heading:Hide()
    A.Text(tableCard,"Item",13,14,-14,-500,UI.K.bronzeText)
    for _,h in ipairs({{"Need",46,-478},{"Bags",46,-426},{"Missing",46,-374},{"Source",92,-274},{"Est. cost",118,-150},{"Purchase",112,-32}}) do
        local t=UI.Head(tableCard,h[1],h[2],"RIGHT");t:SetPoint("TOPRIGHT",h[3],-14)
    end
    p.list=UI.List(tableCard,58,Row,360,false)
    p.list.box:SetPoint("TOPLEFT",4,-36);p.list.box:SetPoint("BOTTOMRIGHT",-4,146)
    p.status=A.Text(tableCard,"",12,12,-1,-12,UI.K.bronzeText)
    p.status:ClearAllPoints();p.status:SetPoint("BOTTOMLEFT",12,118);p.status:SetPoint("RIGHT",-12,0)
    p.total=A.Text(tableCard,"",13,12,-1,-12,UI.K.text)
    p.total:ClearAllPoints();p.total:SetPoint("BOTTOMLEFT",12,94);p.total:SetPoint("RIGHT",-12,0)
    p.scope=A.Text(tableCard,"",11,12,-1,-12,UI.K.textDim)
    p.scope:ClearAllPoints();p.scope:SetPoint("BOTTOMLEFT",12,50);p.scope:SetPoint("RIGHT",-12,0);p.scope:SetHeight(38);p.scope:SetWordWrap(true)
    p.recipes=UI.Button(tableCard,"Workshop recipes",166,"secondary",function()
        W.Window.Show();W.Window.SetMode("craft");A.Hide()
    end,30);p.recipes:SetPoint("BOTTOMLEFT",12,12)
    p.guild=UI.Switch(tableCard,"Use guild bank",function() S.SetUseGuild(not S.UseGuild());A.Schedule() end)
    p.guild:SetPoint("BOTTOMRIGHT",-214,14)
    UI.Tip(p.guild,"Use guild bank stock","Uses the existing Workshop stock preference. Remembered shared stock may change; no inventory is moved.")
    BuildDetail(p)
    p:SetScript("OnEvent",function(_,event)
        if event=="BAG_UPDATE_DELAYED" then W.Strategy.Bump() end
        if event=="MERCHANT_SHOW" or event=="MERCHANT_UPDATE" then S.ReadMerchant() end
        A.Schedule()
    end)
end
local function Render(p)
    if not p.listening then
        for _,event in ipairs({"BAG_UPDATE_DELAYED","GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT","MERCHANT_SHOW","MERCHANT_UPDATE","TRADE_SKILL_LIST_UPDATE"}) do p:RegisterEvent(event) end
        W.Strategy.Listen(Watch,true);W.Storage.Listen(StockWatch,true)
        p.listening=true
    end
    local view=p.resetView and nil or (p.viewport or A.Capture(p.list,Key))
    p.viewport=nil
    if p.resetView then p.list:ScrollTop();p.resetView=false end
    p.plan,p.ctx,p.state=S.ShoppingPlan()
    p.rows=P.Rows(p.plan,p.ctx,{query=p.query,source=p.source,group=p.group})
    local status,current=P.State(p.plan,p.ctx,p.state);p.current=current
    p.status:SetText((W.Queue.Held() and "Read-only saved queue · " or "")..status)
    p.list.box:SetAlpha(current and 1 or 0.55)
    p.list:SetData(p.rows,p.state=="planning" and "Planning shared requirements…" or
        P.Incomplete(p.plan,p.ctx) and "Some requirements cannot be counted. Open their profession and refresh stock." or
        #p.plan.rows==0 and "No missing materials. Open Workshop to review or add recipes." or "No requirements match these filters.")
    p.total:SetText(P.Total(p.plan,UI.Money,p.ctx))
    local stockNote=S.StockNote(p.ctx.summary,p.ctx.stock)
    p.scope:SetText(W.Stock.Scope(p.ctx.stock)..(stockNote and ("\n"..stockNote) or "")..(A.Live() and "\nObserved costs are estimates. Quick buy reviews the current total for the missing quantity." or "\nObserved costs are estimates; purchasing is unavailable."))
    p.guild:SetOn(S.UseGuild())
    Detail(p);p.list:Layout();A.Restore(p.list,view,Key)
end
local function Release(p)
    p.viewport=A.Capture(p.list,Key)
    W.Strategy.Listen(Watch,false);W.Storage.Listen(StockWatch,false)
    p:UnregisterAllEvents();p.listening=false
    p.rows,p.plan,p.ctx={},nil,nil
    p.list:SetData({})
    for _,r in ipairs(p.list.rows) do r.data=nil end
    p.detail.data,p.detail.basis,p.detail.advisorTip=nil,nil,nil
    -- Cancel the shared pending slot only when no other presentation uses it.
    if not W.Window.IsShown() and not (W.Compact and W.Compact.IsShown()) then
        W.Strategy.Drop("queue");W.Strategy.Drop("suggest")
    end
end
A.Register("shopping",{Build=Build,Render=Render,Release=Release})
