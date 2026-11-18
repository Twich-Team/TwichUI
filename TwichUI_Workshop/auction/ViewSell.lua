-- Posting drafts and explicit reviews. Price edits never submit an auction.
local W=TwichUI.Workshop
local A,UI,D,AD=W.AuctionUI,W.UI,W.AuctionSellData,W.AdvisorData
local function Money(n) return n~=nil and UI.Money(n) or "Unavailable" end
local Detail,Refresh,Find
local function Fields(p)
    return table.concat({p.money.gold:GetText(),p.money.silver:GetText(),p.money.copper:GetText()},":")
end
local function SetPrice(p,n,origin)
    p.autoPrice=nil
    p.settingDraft=true;p.filledPrice=n;p.priceOrigin=origin;p.money:SetCopper(n);p.filledFields=Fields(p);p.settingDraft=false
    Detail(p)
end
local function Copy(p,tier)
    local amount,rounded=D.Copy(p.competition,tier,p.chosen)
    if not amount then A.Note("That price is unavailable or its item/market context changed. Refresh competition.");return end
    p.matched=tier.key
    SetPrice(p,amount,p.competition.source=="live" and (rounded and "Matched listing · rounded to silver" or "Matched current listing") or "Matched historical observation")
end
Detail=function(p)
    if not p.controlsReady or p.releasing or not p:IsShown() or not A.IsShown() or A.Mode()~="sell" then return end
    local row
    for _,r in ipairs(p.rows or {}) do if r.key==p.selected then row=r;break end end
    p.chosen=row
    p.detail.market:SetEnabled(row~=nil)
    p.detail.name:SetText(row and row.info.name or "Choose a bag item")
    p.detail.pic.tex:SetTexture(row and row.info.icon or UI.ICON_BLANK)
    p.detail.kind:SetText(row and (row.qty.." in selected stack"..(row.variant and " · exact variant" or "")) or "Choose an item from your bags")
    local quantity=tonumber(p.quantity:GetText())
    local price,why=p.money:GetCopper()
    local draft=D.Draft(row,quantity,price,p.durationIndex or 1)
    p.post:SetEnabled(A.Live() and draft.valid)
    p.post.text:SetText(A.Live() and "Review posting" or "Post unavailable")
    p.draft=draft;p.max:SetEnabled(D.Max(row)>0)
    p.validation:SetText(row and D.Max(row)>0 and not price and why or draft.reason)
    p.total:SetText("Gross if sold   "..Money(draft.gross).."\nDeposit upfront   "..Money(draft.deposit)..
        "\nFees / net proceeds   Not yet verified")
    local vendor=row and row.info.sell
    local warning,close
    if price and vendor and vendor>0 then
        if price<=vendor then warning="At or below vendor value. A vendor offers "..Money(vendor).." per item."
        elseif price-vendor<=math.floor(vendor/10) then
            warning="Within 10% of vendor value ("..Money(vendor).."). Fees and unsold listings may make vendoring preferable."
            close=true
        end
    end
    p.vendorWarning:SetShown(row~=nil)
    p.vendorIcon:SetShown(warning~=nil)
    p.vendorText:SetText(warning or (vendor and vendor>0 and "Vendor value: "..Money(vendor).." per item." or vendor==0 and "This item has no vendor value." or "Vendor value is still loading."))
    UI.Paint(p.vendorText,warning and (close and UI.K.bronzeText or UI.K.danger.text) or UI.K.textDim)
    local ctx=D.Competition(row,p.request or {})
    p.competition=ctx
    p.suggestion,p.recommendation,p.facts=D.Guidance(row,ctx)
    if p.autoPrice==p.request and p.autoPrice and ctx.source=="live" and ctx.complete then
        p.autoPrice=nil
        if p.suggestion and p.suggestion.state=="ok" then
            SetPrice(p,p.suggestion.price,p.suggestion.rounded and "Lowest current price · rounded to silver" or "Lowest comparable current listing")
            return
        end
    elseif p.autoPrice and W.AuctionReads.Pending()==0 and ctx.source~="live" then
        p.autoPrice=nil;p.priceOrigin="No current price available"
    end
    local live=ctx.source=="live"
    p.origin:SetText(p.priceOrigin=="Matched current listing" and not live and "Previously matched listing · verify price" or p.priceOrigin or "No price selected")
    p.competitionCard.heading:SetText(live and "Current listings · experimental" or "Observed historical competition")
    p.qtyHead:SetText(live and "Available" or "Seen qty*")
    p.totalHead:SetText(live and (ctx.kind=="item" and "Buyout each" or "Tier value") or "Est. value*")
    p.competitionNote:SetText(live and (ctx.complete and "Click a listing to use its price" or "Partial response · matching unavailable") or
        (ctx.at and ("Observed "..UI.Ago(ctx.at).." · *aggregate tiers, not stacks") or "No comparable listings"))
    if p.request and not live then p.competitionNote:SetText(W.AuctionReads.Pending()>0 and
        "Searching current listings… Historical tiers below." or "Live results unavailable · showing historical tiers") end
    p.competitionList:SetData(ctx.rows,row and (row.keyComparable==false and "Variant-specific competition is unavailable." or
        row.variant and "No comparable saved variant tiers." or "No comparable saved price tiers.") or "Select a bag item.")
    local lowest
    for _,r in ipairs(ctx.rows) do if r.copy and (not lowest or r.unit<lowest.unit) then lowest=r end end
    p.lowestTier=lowest
    p.lowest:SetEnabled(lowest~=nil and D.Current(ctx,row))
    p.lowest.text:SetText(live and "Match lowest listing" or "Use lowest observed")
    p.match:SetEnabled(p.suggestion~=nil and p.suggestion.state=="ok" and D.Current(ctx,row))
    local types=Enum and Enum.ItemCommodityStatus
    p.find:SetEnabled(row~=nil and row.itemKey~=nil and row.keyComparable~=false and W.AuctionReads.Available() and types~=nil and (row.mode==types.Item or W.AuctionReads.Integrated() and row.mode==types.Commodity) and W.AuctionReads.Pending()==0)
    if not row then
        p.history:SetText("");p.advice:SetText("Select an item for market and Item Advisor guidance.")
        p.chart:Set(nil,UI.Money);p.guidanceTip=nil;return
    end
    p.history:SetText("Vendor / item: "..Money(row.info.sell).."\nCrafting reserved: "..(row.reserved or 0)..
        (row.pending and " · plan pending" or "").."\n"..(W.Facts.Freshness(p.facts) or "No saved observation"))
    local rec=p.recommendation or {}
    local s=p.suggestion
    p.advice:SetText((rec.text or "Insufficient evidence")..
        (s and s.state=="ok" and ("\nSuggested: "..Money(s.price)..(s.source=="live" and " · current match" or " · saved reference")..(s.limited and " · few listings" or "")) or
        rec.observed and ("\nTentative observation: "..Money(rec.observed.value)) or "\nNo supported default price."))
    p.guidanceTip=table.concat(rec.reasons or {},"\n")..(s and s.caution and ("\n"..s.caution) or "")
    p.chart:Set(W.Facts.Chart(p.facts),UI.Money)
end
local function Reset(p)
    Detail(p)
    local s=p.suggestion
    SetPrice(p,s and s.state=="ok" and s.price or nil,s and s.state=="ok" and "Qualified competition reference" or nil)
end
Refresh=function(p)
    local view=A.Capture(p.list,function(r) return r.key end)
    local old=p.chosen
    p.rows,p.error=D.Bags(p.search:GetText())
    local current
    for _,r in ipairs(p.rows) do if r.key==p.selected then current=r;break end end
    if old and (not current or current.identity~=old.identity or current.qty~=old.qty or current.locked~=old.locked or current.bound~=old.bound) then
        if p.request and W.AuctionReads.serial==p.request.intent then W.AuctionReads.Cancel("bag draft changed") end
        p.selected,p.chosen,p.request,p.matched=nil,nil,nil,nil
        SetPrice(p,nil,nil);p.quantity:SetText("1")
    end
    p.list:SetData(p.rows,p.error or "No matching bag items.")
    A.Restore(p.list,view,function(r) return r.key end)
    Detail(p)
end
Find=function(p)
    if not p.chosen or D.Max(p.chosen)==0 then return end
    local request,why=D.Search(p.chosen)
    if request then
        p.request,p.autoPrice,p.matched=request,request,nil
        p.priceOrigin="Searching current listings…"
        Detail(p);A.Schedule()
    else p.autoPrice=nil;A.Note(why) end
end
local function Build(p)
    p.search=UI.Search(p,300,32,"Filter bag items…");p.search:SetPoint("TOPLEFT",0,0)
    p.search:SetScript("OnEnterPressed",function(self) self:ClearFocus();Refresh(p) end)
    local left=A.Card(p,"Bag inventory",100)
    left:SetWidth(270);left:SetPoint("TOPLEFT",0,-48);left:SetPoint("BOTTOMLEFT",0,0)
    p.list=UI.List(left,58,function(parent)
        local r=CreateFrame("Button",nil,parent);UI.Hover(r)
        r.pic=UI.ItemIcon(r,34);r.pic:SetPoint("LEFT",6,0)
        r.name=A.Text(r,"",14,48,-8)
        r.sub=A.Text(r,"",11,48,-31,-8,UI.K.textDim)
        r.fill=function(self,x)
            self.data=x;self.name:SetText(x.info.name);self.pic.tex:SetTexture(x.info.icon or UI.ICON_BLANK)
            local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[x.info.quality or 1]
            if color then self.name:SetTextColor(color.r,color.g,color.b) else UI.Paint(self.name,UI.K.text) end
            self.sub:SetText(x.qty.." in stack"..(x.locked and " · locked" or (x.reserved or 0)>0 and " · crafting reserved" or x.bound~=false and " · binding unknown / bound" or ""))
            self:SetSelected(p.selected==x.key)
        end
        r:SetScript("OnClick",function()
            if not r.data then return end
            if W.AuctionReads.Pending()>0 then A.Note("Wait for the current auction search to finish.");return end
            if p.request and W.AuctionReads.serial==p.request.intent then W.AuctionReads.Cancel("selected item changed") end
            p.selected,p.request,p.matched=r.data.key,nil,nil
            p.quantity:SetText(tostring(D.Max(r.data)));AD.Request(r.data.item)
            SetPrice(p,nil,nil);p.list:Layout()
            if A.Live() then Find(p) else Reset(p) end
        end)
        r.TipEnter=function()
            if r.data and GameTooltip and GameTooltip.SetBagItem then
                GameTooltip:SetOwner(r,"ANCHOR_RIGHT");GameTooltip:SetBagItem(r.data.bag,r.data.slot);GameTooltip:Show()
            end
        end
        r.TipLeave=function(self) TwichUI.Interact.HideTip(self) end
        return r
    end,400,false)
    p.list.box:SetPoint("TOPLEFT",4,-36);p.list.box:SetPoint("BOTTOMRIGHT",-4,8)
    local form=A.Card(p,"Posting preparation",100)
    form:SetPoint("TOPLEFT",left,"TOPRIGHT",10,0);form:SetPoint("BOTTOMRIGHT",-420,0)
    A.Text(form,"Quantity",12,12,-40)
    p.quantity=UI.L.EditBox(form,132,30);UI.CL.Dress(p.quantity,"field");p.quantity:SetPoint("TOPLEFT",12,-60);p.quantity:SetMaxLetters(10);p.quantity:SetNumeric(true)
    p.quantity:SetText("1");p.quantity:SetScript("OnTextChanged",function() Detail(p) end)
    p.max=UI.Button(form,"Max",72,"secondary",function() p.quantity:SetText(tostring(D.Max(p.chosen)));Detail(p) end,30)
    p.max:SetPoint("LEFT",p.quantity,"RIGHT",8,0)
    UI.Tip(p.max,"Maximum usable quantity","Uses only the selected bag stack, capped by the available native count when verified. Locked, bound and crafting-protected items are excluded. Stacks are never combined or split.")
    A.Text(form,"Price per item",14,12,-106)
    p.money=A.MoneyInputs(form,function()
        -- Native SetText callbacks may arrive after the guarded write finishes.
        if not p.settingDraft and Fields(p)~=p.filledFields then
            p.filledPrice=nil;p.priceOrigin="Your unit price";p.matched=nil;p.autoPrice=nil
        end
        Detail(p)
    end);p.money:SetPoint("TOPLEFT",12,-128)
    p.origin=A.Text(form,"No price selected",11,12,-168,-12,UI.K.textDim)
    A.Text(form,"Duration",12,12,-198)
    p.duration=A.Dropdown(form,286,function()
        return {{1,AUCTION_DURATION_ONE or "Duration 1 (unverified)"},{2,AUCTION_DURATION_TWO or "Duration 2 (unverified)"},{3,AUCTION_DURATION_THREE or "Duration 3 (unverified)"}}
    end,function() return p.durationIndex or 1 end,function(i) p.durationIndex=i;Detail(p) end)
    p.duration:SetPoint("TOPLEFT",12,-218)
    p.match=UI.Button(form,"Use suggested price",172,"secondary",function()
        local s=p.suggestion
        if s and s.state=="ok" and D.Current(p.competition,p.chosen) then SetPrice(p,s.price,"Qualified competition reference") end
    end,28);p.match:SetPoint("TOPLEFT",12,-262)
    p.reset=UI.Button(form,"Reset price",106,"secondary",function() Reset(p) end,28);p.reset:SetPoint("LEFT",p.match,"RIGHT",8,0)
    p.vendorWarning=CreateFrame("Frame",nil,form);UI.Panel(p.vendorWarning,"espresso")
    p.vendorWarning:SetPoint("TOPLEFT",12,-304);p.vendorWarning:SetPoint("TOPRIGHT",-12,-304);p.vendorWarning:SetHeight(70)
    p.vendorIcon=p.vendorWarning:CreateTexture(nil,"OVERLAY");p.vendorIcon:SetSize(20,20);p.vendorIcon:SetPoint("TOPLEFT",8,-10)
    p.vendorIcon:SetTexture(TwichUI.PATH..[[media\auction\vendor-warning-small]])
    p.vendorText=A.Text(p.vendorWarning,"",12,36,-10,-8,UI.K.textDim);p.vendorText:SetWordWrap(true);p.vendorText:SetHeight(50)
    p.total=A.Text(form,"",13,12,-390,-12);p.total:SetWordWrap(true);p.total:SetHeight(76)
    UI.Tip(form,"Costs and conditional proceeds","Gross proceeds assume the full draft sells. Deposit is an upfront native quote only when exact item mode, identity, quantity and duration are available. Commission and deposit refund treatment remain unverified; net proceeds are unavailable. A refundable deposit must not be treated as a permanent selling fee.")
    p.validation=A.Text(form,"",12,12,-482,-12,UI.K.textDim);p.validation:SetWordWrap(true);p.validation:SetHeight(42)
    p.post=UI.Button(form,"Post unavailable",196,"primary",function()
        if not A.Live() then return end
        local price=p.money:GetCopper()
        local id,why=W.AuctionActions.PreparePost(p.chosen,tonumber(p.quantity:GetText()),price,p.durationIndex or 1)
        A.ReviewAction(id,why)
    end,34);p.post:SetPoint("BOTTOMLEFT",12,12);p.post:SetEnabled(false)
    UI.Tip(p.post,"Posting disabled","Real-client transaction, confirmation and runtime acceptance are pending. Draft edits never submit an auction.")
    p.detail=A.Details(p,410);p.detail:SetPoint("TOPRIGHT",0,-48);p.detail:SetPoint("BOTTOMRIGHT",0,0)
    p.history=A.Text(p.detail.body,"",12,12,-108,-12);p.history:SetWordWrap(true);p.history:SetHeight(60)
    p.find=UI.Button(p.detail.body,"Refresh listings",186,"secondary",function()
        Find(p)
    end,30);p.find:SetPoint("TOPLEFT",12,-178)
    UI.Tip(p.find,"Explicit read-only search","Refreshes comparable listings for the selected bag item. Selecting an item also starts this read-only search; neither action posts an auction.")
    p.competitionCard=A.Card(p.detail.body,"Observed historical competition",226)
    p.competitionCard:SetPoint("TOPLEFT",4,-218);p.competitionCard:SetPoint("TOPRIGHT",-4,-218)
    UI.CL.Font(p.competitionCard.heading,14)
    p.qtyHead=UI.Head(p.competitionCard,"Seen qty*",68,"RIGHT");p.qtyHead:SetPoint("TOPRIGHT",-268,-36)
    local unitHead=UI.Head(p.competitionCard,"Unit price",100,"RIGHT");unitHead:SetPoint("TOPRIGHT",-152,-36)
    p.totalHead=UI.Head(p.competitionCard,"Est. value*",120,"RIGHT");p.totalHead:SetPoint("TOPRIGHT",-28,-36)
    p.competitionList=UI.List(p.competitionCard,36,function(parent)
        local r=CreateFrame("Button",nil,parent);UI.Hover(r)
        local function Cell(w,x) local t=UI.Text(r,12,UI.K.text);t:SetWidth(w);t:SetJustifyH("RIGHT");t:SetPoint("RIGHT",x,0);return t end
        r.qty=Cell(68,-244);r.unit=Cell(100,-128);r.total=Cell(120,-4)
        r.fill=function(self,x)
            self.data=x;self.qty:SetText(tostring(x.qty));self.unit:SetText(Money(x.unit))
            self.total:SetText(x.total and Money(x.total) or x.bid and ("Bid "..Money(x.bid)) or x.estimate and ("~"..Money(x.estimate)) or "—")
            self:SetSelected(p.matched==x.key);self:SetAlpha(x.copy and 1 or 0.6)
        end
        r:SetScript("OnClick",function() if r.data then Copy(p,r.data) end end)
        r.TipEnter=function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetText("Use this listing's unit price")
            GameTooltip:AddLine(p.competition.source=="live" and "Available quantity is not a stack. Own listings are excluded." or "Saved price evidence; current availability is unknown.",nil,nil,nil,true)
            GameTooltip:Show()
        end
        r.TipLeave=function(self) TwichUI.Interact.HideTip(self) end
        return r
    end,144,false)
    p.competitionList.box:SetPoint("TOPLEFT",4,-56);p.competitionList.box:SetPoint("BOTTOMRIGHT",-4,36)
    p.competitionNote=A.Text(p.competitionCard,"",11,10,-1,-10,UI.K.textDim);p.competitionNote:ClearAllPoints()
    p.competitionNote:SetPoint("BOTTOMLEFT",10,8);p.competitionNote:SetPoint("RIGHT",-10,0);p.competitionNote:SetWordWrap(true);p.competitionNote:SetHeight(26)
    p.lowest=UI.Button(p.detail.body,"Use lowest observed",186,"secondary",function() if p.lowestTier then Copy(p,p.lowestTier) end end,30)
    p.lowest:SetPoint("TOPLEFT",12,-454)
    local advice=A.Card(p.detail.body,"Item Advisor",92);advice:SetPoint("TOPLEFT",4,-496);advice:SetPoint("TOPRIGHT",-4,-496)
    p.advice=A.Text(advice,"",13,12,-30,-12);p.advice:SetWordWrap(true);p.advice:SetHeight(54)
    UI.TipFn(advice,"Price guidance evidence",function() return p.guidanceTip end)
    p.chart=UI.PriceChart(p.detail.body,350,86);p.chart:SetPoint("TOPLEFT",8,-602);p.chart:SetPoint("TOPRIGHT",-8,-602)
    p.detail.body:SetHeight(704)
    p.detail.market=A.HistoryButton(p.detail,function() return p.chosen and p.chosen.item,{variant=p.chosen and p.chosen.variant,itemKey=p.chosen and p.chosen.itemKey} end,370)
    p.detail.market:SetPoint("BOTTOMLEFT",10,10)
    p.controlsReady=true
    p:SetScript("OnEvent",function() A.Schedule() end)
end
A.Register("sell",{Build=Build,Render=function(p)
    if not p.listening then
        for _,event in ipairs({"BAG_UPDATE_DELAYED","GET_ITEM_INFO_RECEIVED","ITEM_SEARCH_RESULTS_UPDATED","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_DISABLED"}) do p:RegisterEvent(event) end
        W.Strategy.Listen(A.Schedule,true);p.listening=true;p.eventCount=5
    end
    Refresh(p)
end,Release=function(p)
    p.releasing=true
    if p.request and W.AuctionReads.serial==p.request.intent then W.AuctionReads.Cancel("page hidden") end
    W.Strategy.Listen(A.Schedule,false)
    p:UnregisterAllEvents();p.listening=false;p.rows=nil;p.chosen=nil;p.suggestion=nil;p.recommendation=nil;p.facts=nil
    p.selected,p.request,p.matched,p.competition,p.lowestTier,p.draft,p.guidanceTip,p.autoPrice=nil,nil,nil,nil,nil,nil,nil,nil
    p.quantity:SetText("1");SetPrice(p,nil,nil)
    p.list:SetData({});p.competitionList:SetData({});p.detail.market:SetEnabled(false)
    for _,list in ipairs({p.list,p.competitionList}) do for _,row in ipairs(list.rows) do row.data=nil end end
    p.releasing=nil
end})
