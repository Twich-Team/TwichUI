-- Current owned auctions, with server-reported sold state and explicit cancellation.
-- Timers update display countdowns only; they never submit auction operations.
local R,W=TwichUI,TwichUI.Workshop
local A,UI,Q,AD=W.AuctionUI,W.UI,W.AuctionReads,W.AdvisorData
local ACTIVE,SOLD=0,1 -- Forever's AuctionStatus enum
local DONE=R.PATH..[[media\guides\status-done]]
local DONE_SMALL=R.PATH..[[media\guides\status-done-small]]
local function Money(n) return type(n)=="number" and UI.Money(n) or "Unavailable" end
local function Sold(row) return row and row.status==SOLD end
local function Incoming(row) return Sold(row) and (row.total or row.bid) or nil end
local function PendingAction() return W.AuctionActions.Snapshot().pending>0 end
local function Remaining(row,snapshot)
    if not row or row.seconds==nil or not snapshot or not W.Finite(snapshot.at) then return nil end
    return math.max(0,row.seconds-math.max(0,GetTime()-snapshot.at))
end
local function TimeText(row,snapshot)
    local seconds=Remaining(row,snapshot)
    if seconds~=nil then
        if seconds<=0 then return Sold(row) and "Delivery due" or "Ending now" end
        if seconds<60 then return "Less than 1m" end
        local minutes=math.ceil(seconds/60)
        if minutes<60 then return minutes.."m" end
        local hours=math.floor(minutes/60)
        return hours.."h"..(minutes%60>0 and (" "..(minutes%60).."m") or "")
    end
    if row and row.band and AuctionHouseUtil and AuctionHouseUtil.GetTimeLeftBandText then
        local text=AuctionHouseUtil.GetTimeLeftBandText(row.band)
        if text and text~="" then return text end
    end
    return "Time unavailable"
end
local function Info(row)
    local info=AD.Info(row.link or row.item);info.item=row.item
    if C_AuctionHouse and C_AuctionHouse.GetItemKeyInfo then
        local ok,native=pcall(C_AuctionHouse.GetItemKeyInfo,row.itemKey)
        if ok and type(native)=="table" then
            if not info.known then info.name=W.Text(W.Plain(native.itemName),200) or info.name end
            info.icon=info.icon or W.Plain(native.iconFileID)
            info.quality=info.quality or W.Int(W.Plain(native.quality),0,20)
        end
    end
    return info
end
local function Quality(text,info)
    UI.ItemQuality(text, info and info.quality)
end
local function ItemTip(owner,row)
    if not row or not GameTooltip then return end
    local link=row.link
    if not link and C_AuctionHouse and C_AuctionHouse.GetItemKeySampleLink then
        local ok,value=pcall(C_AuctionHouse.GetItemKeySampleLink,row.itemKey)
        if ok then link=W.Text(W.Plain(value),1000) end
    end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(row.item) end
    GameTooltip:Show()
end
local function UpdateTimes(p)
    for _,line in ipairs(p.list.rows) do
        if line:IsShown() and line.data then line.time:SetText(TimeText(line.data,p.snapshot)) end
    end
    local row=p.chosen
    if not row then p.time:SetText("—");p.timeNote:SetText("");return end
    p.time:SetText(TimeText(row,p.snapshot))
    local seconds=Remaining(row,p.snapshot)
    if seconds and seconds>0 then
        local clock=date("%I:%M %p",time()+math.ceil(seconds)):gsub("^0","")
        p.timeNote:SetText((Sold(row) and "Expected around " or "Ends around ")..clock.." · local time")
    elseif seconds==0 then
        p.timeNote:SetText(Sold(row) and "Check your mailbox for payment." or "Waiting for the auction's final status.")
    else p.timeNote:SetText("The auction house has not provided an exact time.") end
end
local function RequestRefresh(p)
    if not p.needsRefresh or not A.Live() or not Q.Available() or Q.Pending()>0 or PendingAction()
        or not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    p.needsRefresh=false
    local ok,why=Q.Begin("owned")
    if not ok then p.error=why;A.Note(why) else p.error=nil end
end
local function Detail(p)
    local chosen
    for _,row in ipairs(p.rows or {}) do if row.auctionID==p.selected then chosen=row;break end end
    if not chosen then chosen=p.rows[1];p.selected=chosen and chosen.auctionID end
    p.chosen=chosen
    local d=p.detail
    d.market:SetEnabled(chosen~=nil)
    p.cancel:SetEnabled(A.Live() and Q.Available() and chosen~=nil and chosen.status==ACTIVE and Q.Pending()==0 and not PendingAction())
    p.repost:SetEnabled(A.Live() and chosen~=nil and chosen.status==ACTIVE and not PendingAction())
    p.cancel.text:SetText(A.Live() and "Cancel auction…" or "Cancel unavailable")
    local info=chosen and p.infoByID[chosen.auctionID]
    d.name:SetText(info and info.name or "Choose an auction")
    d.pic.tex:SetTexture(info and info.icon or UI.ICON_BLANK);Quality(d.name,info)
    d.kind:SetText(chosen and (chosen.qty..(chosen.qty==1 and " item" or " items")) or "Your current listings and incoming payments")
    local sold=Sold(chosen)
    p.saleTitle:SetText(chosen and (sold and "Sold" or chosen.status==ACTIVE and "Listed for sale" or "Status unavailable") or "Your auctions")
    UI.Paint(p.saleTitle,sold and UI.K.sage or UI.K.bronzeText)
    if sold then p.saleArt:SetTexture(DONE) else UI.Art(p.saleArt,"npc:gavel",40) end
    p.saleNote:SetText(chosen and (sold and "Your payment is on the way." or chosen.status==ACTIVE and "This auction is still open." or "Waiting for the current auction status.") or "Select a listing to view its details.")
    p.amountCard.heading:SetText(sold and "Incoming payment" or "Listing price")
    p.amount:SetText(chosen and Money(sold and Incoming(chosen) or chosen.total or chosen.bid) or "—")
    UI.Paint(p.amount,sold and UI.K.sage or UI.K.bronzeText)
    local unit=chosen and (sold and Incoming(chosen) and math.ceil(Incoming(chosen)/chosen.qty) or not sold and chosen.unit)
    p.unit:SetText("Per item:  "..(chosen and Money(unit) or "—"))
    p.bid:SetText(chosen and not sold and ("Current bid:  "..Money(chosen.bid)) or "")
    p.priceNote:SetText(sold and "Amount shown by the auction house; collect payment from your mailbox."
        or chosen and not chosen.total and "This auction has no buyout price." or "The full listing price for this quantity.")
    p.timeCard.heading:SetText(sold and "Payment delivery" or "Auction time remaining")
    UI.Paint(p.time,sold and UI.K.sage or UI.K.text)
    if chosen then
        local k=chosen.itemKey
        local variant=(k.itemSuffix or 0)~=0 or (k.itemLevel or 0)~=0 or (k.battlePetSpeciesID or 0)~=0
        local rec=variant and {text="Variant-specific advice unavailable",reasons={}} or AD.Decide(chosen.item,false)
        p.advice:SetText((rec.text or "Limited market information").."\n"..((rec.reasons or {})[1] or ""))
    else p.advice:SetText("Select an auction to see Item Advisor guidance.") end
    p.list:Layout();UpdateTimes(p)
end
local function Render(p)
    if not p.listening then
        for _,event in ipairs({"OWNED_AUCTIONS_UPDATED","AUCTION_CANCELED","AUCTION_HOUSE_NEW_BID_RECEIVED",
            "AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_DISABLED","GET_ITEM_INFO_RECEIVED","ITEM_DATA_LOAD_RESULT",
            "ITEM_KEY_ITEM_INFO_RECEIVED","AUCTION_HOUSE_THROTTLED_SYSTEM_READY"}) do p:RegisterEvent(event) end
        p.listening=true;p.eventCount=9;p.needsRefresh=A.Live()
        if A.Live() then
            p.clock=C_Timer.NewTicker(1,function()
                if not p:IsShown() or not A.IsShown() or A.Mode()~="owned" then return end
                UpdateTimes(p)
                p.clockTicks=(p.clockTicks or 0)+1
                if p.filter=="soon" and p.clockTicks%30==0 then A.Schedule() end
            end)
        end
    end
    RequestRefresh(p)
    local snapshot=Q.snapshot
    if snapshot and snapshot.kind=="owned" and snapshot.epoch==Q.epoch and Q.Available() then p.snapshot=snapshot end
    snapshot=p.snapshot
    if snapshot and (snapshot.epoch~=Q.epoch or not Q.Available()) then snapshot=nil;p.snapshot=nil end
    local view=A.Capture(p.list,function(row) return row.auctionID end)
    p.rows={};p.infoByID={};p.known={}
    p.complete=snapshot and snapshot.complete==true
    local active,sold,incoming,missing,total,posted,unpriced=0,0,0,0,0,0,0
    if snapshot then
        local seen={}
        for _,row in ipairs(snapshot.rows) do
            if not seen[row.auctionID] then
                seen[row.auctionID]=true;total=total+1;p.known[row.item]=true
                if row.status==ACTIVE then
                    active=active+1
                    local value=row.total or row.bid
                    if value then posted=posted+value else unpriced=unpriced+1 end
                end
                if Sold(row) then
                    sold=sold+1
                    local amount=Incoming(row)
                    if amount then incoming=incoming+amount else missing=missing+1 end
                end
                local seconds=Remaining(row,snapshot)
                if p.filter=="all" or p.filter=="active" and row.status==ACTIVE or p.filter=="sold" and Sold(row)
                    or p.filter=="soon" and row.status==ACTIVE and seconds and seconds<=3600 then
                    p.rows[#p.rows+1]=row;p.infoByID[row.auctionID]=Info(row)
                end
            end
        end
    end
    local partial=snapshot and not p.complete
    p.postedValue:SetText(snapshot and (((partial or unpriced>0) and "≥ " or "")..Money(posted)) or "—")
    p.activeValue:SetText(snapshot and ((partial and "≥ " or "")..active) or "—")
    p.soldValue:SetText(snapshot and ((partial and "≥ " or "")..sold) or "—")
    p.incomingValue:SetText(snapshot and (((partial or missing>0) and "≥ " or "")..Money(incoming)) or "—")
    local empty=not A.Live() and "Visit an auctioneer to see your auctions." or
        (Q.Pending()>0 or p.needsRefresh) and "Loading your auctions…" or p.error or Q.lastError or "Your auctions are unavailable. Try Refresh listings."
    if snapshot then
        empty=total>0 and "No auctions match this filter." or p.complete and "You have no active auctions or pending sales." or "No auctions returned yet."
    end
    p.list:SetData(p.rows,empty)
    p.refresh:SetEnabled(A.Live() and Q.Available() and Q.Pending()==0 and not PendingAction())
    p.refresh.text:SetText(Q.Pending()>0 and "Refreshing…" or "Refresh listings")
    p.status:SetText(snapshot and (#p.rows..(#p.rows==1 and " auction" or " auctions")..(partial and " · partial results" or "")..
        " · Updated "..UI.Ago(time()-math.max(0,GetTime()-snapshot.at))) or "")
    Detail(p);A.Restore(p.list,view,function(row) return row.auctionID end)
end
local function Build(p)
    p.filter="all";p.requested={};p.rows={};p.infoByID={}
    p.refresh=UI.Button(p,"Refresh listings",170,"secondary",function() p.needsRefresh=true;Render(p) end,32)
    p.refresh:SetPoint("TOPLEFT",0,0)
    p.filters=A.Dropdown(p,220,function() return {{"all","All auctions"},{"active","Active auctions"},{"sold","Sold · payment incoming"},{"soon","Expiring within 1 hour"}} end,
        function() return p.filter end,function(value) p.filter=value;Render(p) end)
    p.filters:SetPoint("LEFT",p.refresh,"RIGHT",12,0)
    local summary=CreateFrame("Frame",nil,p);summary:SetPoint("TOPLEFT",0,-48);summary:SetPoint("TOPRIGHT",0,-48);summary:SetHeight(76)
    local metrics={}
    for i,def in ipairs({{"Active auctions","npc:gavel",UI.K.bronzeText},{"Sold",nil,UI.K.sage},{"Incoming", "npc:coins",UI.K.sage},{"Posted value","npc:balance-scales",UI.K.bronzeText}}) do
        local m=CreateFrame("Frame",nil,summary);UI.Panel(m,"card");m:SetHeight(76)
        m.art=m:CreateTexture(nil,"ARTWORK");m.art:SetSize(32,32);m.art:SetPoint("LEFT",12,0)
        if def[2] then UI.Art(m.art,def[2],32) else m.art:SetTexture(DONE) end
        m.value=A.Text(m,"—",i>=3 and 16 or 20,56,-14,-10,def[3]);m.value:SetHeight(26)
        m.label=A.Text(m,def[1],12,56,-45,-10,UI.K.textDim);metrics[i]=m
    end
    local function SizeSummary(_,width)
        local w=math.max(1,(width-30)/4)
        for i,m in ipairs(metrics) do m:ClearAllPoints();m:SetPoint("TOPLEFT",(i-1)*(w+10),0);m:SetWidth(w) end
    end
    summary:SetScript("OnSizeChanged",SizeSummary);SizeSummary(summary,summary:GetWidth())
    p.activeValue,p.soldValue,p.incomingValue,p.postedValue=metrics[1].value,metrics[2].value,metrics[3].value,metrics[4].value
    UI.Tip(metrics[4],"Posted value","Total buyout value of active auctions. Bid-only auctions use their current bid when available. Sold payments are shown separately under Incoming.")
    local card=A.Card(p,"My Auctions",100);card:SetPoint("TOPLEFT",0,-136);card:SetPoint("BOTTOMRIGHT",-380,0);card.heading:Hide()
    A.Text(card,"Item",12,12,-14,-330,UI.K.bronzeText)
    local amountHead=UI.Head(card,"Amount",160,"RIGHT");amountHead:SetPoint("TOPRIGHT",-196,-14)
    local timeHead=UI.Head(card,"Time",150,"RIGHT");timeHead:SetPoint("TOPRIGHT",-34,-14)
    p.list=UI.List(card,68,function(parent)
        local row=CreateFrame("Button",nil,parent);UI.Hover(row)
        row.pic=UI.ItemIcon(row,40);row.pic:SetPoint("LEFT",8,0)
        row.sold=row.pic:CreateTexture(nil,"OVERLAY");row.sold:SetTexture(DONE_SMALL);row.sold:SetSize(20,20);row.sold:SetPoint("BOTTOMRIGHT",row.pic,"BOTTOMRIGHT",5,-3)
        row.name=A.Text(row,"",14,60,-12,-330);row.name:SetHeight(22)
        row.sub=A.Text(row,"",11,60,-38,-330,UI.K.textDim)
        local function Right(size,width,x,y,color)
            local text=UI.Text(row,size,color or UI.K.text);text:SetWidth(width);text:SetJustifyH("RIGHT");text:SetPoint("RIGHT",x,y);return text
        end
        row.amount=Right(14,160,-172,9,UI.K.bronzeText);row.amountHint=Right(10,160,-172,-14,UI.K.textDim)
        row.time=Right(13,150,-10,9);row.timeHint=Right(10,150,-10,-14,UI.K.textDim)
        row.fill=function(self,data)
            self.data=data
            local info=p.infoByID[data.auctionID] or Info(data)
            self.name:SetText(info.name);Quality(self.name,info);self.pic.tex:SetTexture(info.icon or UI.ICON_BLANK)
            local sold=Sold(data);self.sold:SetShown(sold)
            self.sub:SetText((sold and "Sold" or data.status==ACTIVE and "Active" or "Status unavailable").." · "..data.qty..(data.qty==1 and " item" or " items"))
            UI.Paint(self.sub,sold and UI.K.sage or UI.K.textDim)
            self.amount:SetText(Money(sold and Incoming(data) or not sold and (data.total or data.bid)))
            UI.Paint(self.amount,sold and UI.K.sage or UI.K.bronzeText)
            self.amountHint:SetText(sold and "Incoming" or data.total and "Buyout" or "Highest bid")
            self.time:SetText(TimeText(data,p.snapshot));self.timeHint:SetText(sold and "Until delivery" or "Remaining")
            self:SetSelected(data.auctionID==p.selected)
            if not info.known and not p.requested[data.item] then p.requested[data.item]=true;AD.Request(data.item,true) end
        end
        row:SetScript("OnClick",function(self)
            if self.data then p.selected=self.data.auctionID;AD.Request(self.data.item);Detail(p) end
        end)
        row.TipEnter=function(self) ItemTip(self,self.data) end
        row.TipLeave=function(self) R.Interact.HideTip(self) end
        return row
    end,400,false)
    p.list.box:SetPoint("TOPLEFT",4,-36);p.list.box:SetPoint("BOTTOMRIGHT",-4,42)
    p.status=A.Text(card,"",11,12,-1,-12,UI.K.textDim);p.status:ClearAllPoints();p.status:SetPoint("BOTTOMLEFT",12,14);p.status:SetPoint("RIGHT",-12,0)
    p.detail=A.Details(p,370);p.detail:SetPoint("TOPRIGHT",0,-136);p.detail:SetPoint("BOTTOMRIGHT",0,0)
    local d=p.detail
    local item=CreateFrame("Button",nil,d.body);item:SetPoint("TOPLEFT",8,-8);item:SetPoint("TOPRIGHT",-8,-8);item:SetHeight(68)
    item:SetScript("OnEnter",function(self) ItemTip(self,p.chosen) end);item:SetScript("OnLeave",function(self) R.Interact.HideTip(self) end)
    local sale=CreateFrame("Frame",nil,d.body);UI.Panel(sale,"espresso");sale:SetHeight(78);sale:SetPoint("TOPLEFT",6,-104);sale:SetPoint("TOPRIGHT",-6,-104)
    p.saleArt=sale:CreateTexture(nil,"ARTWORK");p.saleArt:SetSize(40,40);p.saleArt:SetPoint("LEFT",10,0)
    p.saleTitle=A.Text(sale,"",18,60,-12,-10,UI.K.bronzeText)
    p.saleNote=A.Text(sale,"",11,60,-40,-10,UI.K.textDim);p.saleNote:SetHeight(28);p.saleNote:SetWordWrap(true)
    p.amountCard=A.Card(d.body,"Listing price",174);p.amountCard:SetPoint("TOPLEFT",6,-194);p.amountCard:SetPoint("TOPRIGHT",-6,-194)
    p.amount=A.Text(p.amountCard,"",21,12,-40,-12,UI.K.bronzeText);p.amount:SetHeight(28)
    p.unit=A.Text(p.amountCard,"",12,12,-80,-12,UI.K.textDim)
    p.bid=A.Text(p.amountCard,"",12,12,-104,-12,UI.K.textDim)
    p.priceNote=A.Text(p.amountCard,"",11,12,-130,-12,UI.K.textDim);p.priceNote:SetHeight(32);p.priceNote:SetWordWrap(true)
    p.timeCard=A.Card(d.body,"Auction time remaining",112);p.timeCard:SetPoint("TOPLEFT",6,-380);p.timeCard:SetPoint("TOPRIGHT",-6,-380)
    p.time=A.Text(p.timeCard,"",21,12,-36,-12);p.time:SetHeight(28)
    p.timeNote=A.Text(p.timeCard,"",11,12,-74,-12,UI.K.textDim);p.timeNote:SetHeight(28);p.timeNote:SetWordWrap(true)
    local advice=A.Card(d.body,"Item Advisor",100);advice:SetPoint("TOPLEFT",6,-504);advice:SetPoint("TOPRIGHT",-6,-504)
    p.advice=A.Text(advice,"",12,12,-34,-12,UI.K.textDim);p.advice:SetHeight(54);p.advice:SetWordWrap(true)
    p.cancel=UI.Button(d,"Cancel auction…",158,"secondary",function()
        if not A.Live() then return end
        local ok,why=W.AuctionActions.RequestCancel(p.chosen);if not ok then A.Note(why) end
    end,30);p.cancel:SetPoint("BOTTOMLEFT",10,10);p.cancel:SetEnabled(false)
    p.repost=UI.Button(d,"Prepare repost",158,"secondary",function()
        if not A.Live() then return end
        local ok,why=W.AuctionActions.PrepareRepost(p.chosen);A.Note(ok and W.AuctionActions.message or why)
    end,30);p.repost:SetPoint("BOTTOMRIGHT",-10,10);p.repost:SetEnabled(false)
    UI.Tip(p.repost,"Prepare repost","Cancel the auction separately and collect its returned items from your mailbox. Select the returned bag item under Sell to review a new posting.")
    d.market=A.HistoryButton(d.body,function() return p.chosen and p.chosen.item,{itemKey=p.chosen and p.chosen.itemKey} end,300)
    d.market:SetPoint("TOPLEFT",12,-618);d.body:SetHeight(662)
    p:SetScript("OnEvent",function(_,event,itemID)
        if event=="AUCTION_CANCELED" or event=="AUCTION_HOUSE_NEW_BID_RECEIVED" then p.needsRefresh=true end
        if event=="GET_ITEM_INFO_RECEIVED" or event=="ITEM_DATA_LOAD_RESULT" or event=="ITEM_KEY_ITEM_INFO_RECEIVED" then
            local value=W.Plain(itemID)
            local id=W.Int(type(value)=="table" and W.Plain(value.itemID) or value,1,W.MAX_ID)
            if not id or not p.known or not p.known[id] then return end
        end
        A.Schedule()
    end)
end
A.Register("owned",{Build=Build,Render=Render,Release=function(p)
    if p.clock then p.clock:Cancel();p.clock=nil end
    Q.Cancel("page hidden");p:UnregisterAllEvents();p.listening=false;p.needsRefresh=false;p.clockTicks=nil
    p.rows,p.chosen,p.selected,p.snapshot,p.known=nil,nil,nil,nil,nil;p.requested={};p.infoByID={};p.list:SetData({})
    for _,row in ipairs(p.list.rows) do row.data=nil end
end})
