-- Explicit owned-listing reviews; no inferred sale reconciliation.
local W=TwichUI.Workshop
local A,UI,Q,AD=W.AuctionUI,W.UI,W.AuctionReads,W.AdvisorData
local function Money(n) return n and UI.Money(n) or "No buyout / unknown" end
local function Detail(p)
    local chosen
    for _,r in ipairs(p.rows or {}) do if r.auctionID==p.selected then chosen=r end end
    p.chosen=chosen;p.detail.market:SetEnabled(chosen~=nil)
    p.cancel:SetEnabled(A.Live() and chosen~=nil and chosen.status==0 and p.complete and Q.Fresh())
    p.repost:SetEnabled(A.Live() and chosen~=nil)
    p.cancel.text:SetText(A.Live() and "Review cancellation" or "Cancel unavailable")
    p.repost.text:SetText(A.Live() and "Prepare repost" or "Repost unavailable")
    p.detail.name:SetText(chosen and AD.Info(chosen.item).name or "Choose an owned listing")
    p.detail.pic.tex:SetTexture(chosen and AD.Info(chosen.item).icon or UI.ICON_BLANK)
    p.detail.kind:SetText("Owned listings")
    if not chosen then p.info:SetText("Select a listing to inspect its price and time remaining.");p.advice:SetText("");return end
    local k=chosen.itemKey
    local variant=(k.itemSuffix or 0)~=0 or (k.itemLevel or 0)~=0 or (k.battlePetSpeciesID or 0)~=0
    local facts=W.Facts.Of(chosen.item,{variant=variant})
    p.info:SetText("Auction ID: "..chosen.auctionID.."\nQuantity: "..chosen.qty..
        "\nAsking total: "..Money(chosen.total).."\nUnit (rounded up): "..Money(chosen.unit)..
        "\nBid: "..Money(chosen.bid).."\nTime: "..(chosen.seconds and (chosen.seconds.." seconds at read") or chosen.band and ("native band "..chosen.band) or "unavailable")..
        "\nStatus: "..(chosen.status==0 and "Active at read" or chosen.status==1 and "Native Sold status" or "Unknown")..
        "\nCompetition: unavailable\nCompleteness: "..(p.complete and "native complete response" or "unverified / partial"))
    local rec=variant and {text="Variant-specific advice unavailable",reasons={}} or AD.Decide(chosen.item,false)
    p.advice:SetText("Saved market context · "..(W.Facts.Freshness(facts) or "No observation").."\n"..
        (rec.text or "Insufficient advice").."\n"..table.concat(rec.reasons or {},"\n"))
end
local function Render(p)
    if not p.listening then
        for _,event in ipairs({"OWNED_AUCTIONS_UPDATED","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_DISABLED","GET_ITEM_INFO_RECEIVED"}) do p:RegisterEvent(event) end
        p.listening=true;p.eventCount=4
    end
    local snapshot=Q.snapshot
    local view=A.Capture(p.list,function(r) return r.auctionID end)
    p.rows={}
    p.complete=snapshot and snapshot.kind=="owned" and snapshot.epoch==Q.epoch and snapshot.complete==true
    if snapshot and snapshot.kind=="owned" and snapshot.epoch==Q.epoch and Q.Available() then
        local seen={}
        for _,r in ipairs(snapshot.rows) do
            if not seen[r.auctionID] then
                seen[r.auctionID]=true
                if p.filter=="all" or p.filter=="active" and r.status==0 or
                    p.filter=="soon" and r.status==0 and r.seconds and r.seconds<=3600 then p.rows[#p.rows+1]=r end
            end
        end
    end
    local empty=Q.Pending()>0 and "Loading your auctions…" or "Your auctions are unavailable. Click Refresh listings at an auctioneer."
    if snapshot and snapshot.kind=="owned" and snapshot.epoch==Q.epoch and Q.Available() then
        empty=#snapshot.rows>0 and "No returned owned listings match this filter." or
            p.complete and "No owned listings returned." or "No owned listings returned; this response may be partial."
    end
    p.list:SetData(p.rows,empty)
    p.refresh:SetEnabled(Q.Available() and Q.Pending()==0)
    p.status:SetText(#p.rows>0 and (#p.rows.." returned listings"..(p.complete and "" or " · partial response")
        ..(Q.Fresh(snapshot) and "" or " · refresh to check current status")) or "")
    A.Restore(p.list,view,function(r) return r.auctionID end)
    Detail(p)
end
local function Build(p)
    p.filter="all"
    p.refresh=UI.Button(p,"Refresh listings",210,"primary",function()
        local ok,why=Q.Begin("owned")
        if not ok then A.Note(why) end
        Render(p)
    end,32);p.refresh:SetPoint("TOPLEFT",0,0)
    UI.Tip(p.refresh,"Live refresh","Refresh runs only when clicked during an integrated auctioneer visit. Cancellation requires a separate review and native activation.")
    p.filters=A.Dropdown(p,240,function() return {{"all","All returned listings"},{"active","Active at read"},{"soon","Expiring within 1 hour (known)"}} end,
        function() return p.filter end,function(v) p.filter=v;Render(p) end)
    p.filters:SetPoint("LEFT",p.refresh,"RIGHT",12,0)
    local card=A.Card(p,"My Auctions",100)
    card:SetPoint("TOPLEFT",0,-48);card:SetPoint("BOTTOMRIGHT",-380,0)
    p.list=UI.List(card,60,function(parent)
        local r=CreateFrame("Button",nil,parent);UI.Hover(r)
        r.pic=UI.ItemIcon(r,34);r.pic:SetPoint("LEFT",8,0)
        r.name=A.Text(r,"",14,52,-10,-150);r.price=A.Text(r,"",12,52,-34,-12,UI.K.textDim)
        r.fill=function(self,x)
            self.data=x;local info=AD.Info(x.item)
            self.name:SetText(info.name);self.pic.tex:SetTexture(info.icon or UI.ICON_BLANK)
            self.price:SetText(x.qty.." items · "..Money(x.total).." · "..(x.status==0 and "Active at read" or "Native status "..tostring(x.status)))
            self:SetSelected(x.auctionID==p.selected)
        end
        r:SetScript("OnClick",function()
            if r.data then p.selected=r.data.auctionID;AD.Request(r.data.item);Detail(p);p.list:Layout() end
        end)
        return r
    end,400,false)
    p.list.box:SetPoint("TOPLEFT",4,-36);p.list.box:SetPoint("BOTTOMRIGHT",-4,70)
    p.status=A.Text(card,"",12,12,-1,-12,UI.K.textDim);p.status:ClearAllPoints();p.status:SetPoint("BOTTOMLEFT",12,42)
    local note=A.Text(card,"Disappearance is an unknown outcome, never a confirmed sale.",11,12,-1,-12,UI.K.textDim)
    note:ClearAllPoints();note:SetPoint("BOTTOMLEFT",12,14)
    p.detail=A.Details(p,370);p.detail:SetPoint("TOPRIGHT",0,-48);p.detail:SetPoint("BOTTOMRIGHT",0,0)
    p.info=A.Text(p.detail.body,"",13,12,-112);p.info:SetWordWrap(true);p.info:SetHeight(260)
    p.advice=A.Text(p.detail.body,"",12,12,-390);p.advice:SetWordWrap(true);p.advice:SetHeight(200)
    p.cancel=UI.Button(p.detail,"Cancel unavailable",158,"secondary",function()
        if not A.Live() then return end
        local id,why=W.AuctionActions.PrepareCancel(p.chosen);A.ReviewAction(id,why)
    end,30);p.cancel:SetPoint("BOTTOMLEFT",10,10);p.cancel:SetEnabled(false)
    p.repost=UI.Button(p.detail,"Repost unavailable",158,"secondary",function()
        if not A.Live() then return end
        local ok,why=W.AuctionActions.PrepareRepost(p.chosen)
        A.Note(ok and W.AuctionActions.message or why)
    end,30);p.repost:SetPoint("BOTTOMRIGHT",-10,10);p.repost:SetEnabled(false)
    UI.Tip(p.cancel,"Cancellation disabled","Exact real-client ownership, transaction and confirmation acceptance pending.")
    UI.Tip(p.repost,"Reposting disabled","No automatic cancellation or posting. Real-client acceptance pending.")
    p.detail.market=A.HistoryButton(p.detail.body,function()
        return p.chosen and p.chosen.item,{itemKey=p.chosen and p.chosen.itemKey}
    end,300)
    p.detail.market:SetPoint("TOPLEFT",12,-602);p.detail.body:SetHeight(646)
    p:SetScript("OnEvent",function() A.Schedule() end)
end
A.Register("owned",{Build=Build,Render=Render,Release=function(p)
    Q.Cancel("page hidden");p:UnregisterAllEvents();p.listening=false;p.rows=nil;p.chosen=nil;p.selected=nil;p.list:SetData({})
end})
