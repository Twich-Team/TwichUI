-- One explicit-action controller. Events/timers reconcile outcomes; they never
-- send a purchase, post or cancellation. Native per-mode evidence is independent
-- of the presentation preference.
local R,W=TwichUI,TwichUI.Workshop
local Q,D=W.AuctionReads,W.AuctionSellData
local T={serial=0,state="idle"}
W.AuctionActions=T
local ticket,timeout,listening,sending,hooked
local buyRequest
local RefreshBuy
local transactionHooks
local handlers={}
local EVENTS={"AUCTION_HOUSE_PURCHASE_COMPLETED","COMMODITY_PRICE_UPDATED","COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED","COMMODITY_PURCHASE_FAILED","AUCTION_CANCELED","AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_MULTISELL_START","AUCTION_MULTISELL_UPDATE","AUCTION_MULTISELL_FAILURE","AUCTION_HOUSE_SHOW_ERROR",
    "AUCTION_HOUSE_POST_ERROR"}
local REASONS={
    buyItem="Item buyout activation awaits Forever hardware-action and auction-ID completion verification in this interface.",
    buyCommodity="Commodity purchase is disabled: Forever's generated two-argument quote API differs from the native frame call; quote/confirmation permissions and completion must be verified.",
    postItem="Item posting activation awaits verification of the existing Sell from Bags warning/confirmation path in the integrated window.",
    postCommodity="Commodity posting activation awaits deposit, native warning and completion verification in the integrated window.",
    cancel="Cancellation activation awaits Forever permission, cancellation-cost and ID-correlated completion verification in this interface.",
}
local function Int(v,lo,hi) return W.Int(W.Plain(v),lo,hi or W.Prices.MAX_COPPER) end
local function Key(k) return Q.Key(k) end
local function SameKey(a,b)
    a,b=Key(a),Key(b)
    return a and b and a.itemID==b.itemID and a.itemLevel==b.itemLevel and a.itemSuffix==b.itemSuffix and a.battlePetSpeciesID==b.battlePetSpeciesID
end
local function SameListing(a,b)
    if a.commodity or b.commodity then return a.commodity and b.commodity and a.listingKey and a.listingKey==b.listingKey end
    return a.auctionID~=nil and a.auctionID==b.auctionID
end
local function Money() return GetMoney and Int(GetMoney(),0,9007199254740991) end
local function Notify() if W.AuctionUI then W.AuctionUI.Schedule() end end
local function Context()
    local h=R.AuctionHost
    if not h or not h.DebugEnabled or not h.DebugEnabled() then return false end
    local s=h.Snapshot()
    return s.state=="twichui" and h.IsCurrent(s.visit) and W.Active() and not InCombatLockdown()
end
function T.Busy() return ticket~=nil and T.state~="review" end
function T.Capability(mode)
    local b=R.AuctionBuild
    local enabled=b and ((b.verified and b.verified[mode]==true) or (b.integrated and b.integrated[mode]==true))
    if not enabled then return false,REASONS[mode] or "This auction operation is unsupported." end
    local needed={buyItem={"PlaceBid"},buyCommodity={"StartCommoditiesPurchase","ConfirmCommoditiesPurchase","GetQuoteDurationRemaining"},
        postItem={"PostItem","ConfirmPostItem"},postCommodity={"PostCommodity","ConfirmPostCommodity"},cancel={"CancelAuction","CanCancelAuction","GetCancelCost","GetOwnedAuctions"}}
    for _,name in ipairs(needed[mode] or {}) do
        if not C_AuctionHouse or type(C_AuctionHouse[name])~="function" then return false,"This client does not provide the required auction operation." end
    end
    return true
end
local function Listen(on)
    if on==listening then return end
    listening=on
    for _,event in ipairs(EVENTS) do
        local name=event
        handlers[name]=handlers[name] or function(...) T.Event(name,...) end
        if on then R:On(name,handlers[name]) else R:Off(name,handlers[name]) end
    end
end
local function StopTimer() if timeout then timeout:Cancel();timeout=nil end end
local function Finish(state,message)
    StopTimer();Listen(false)
    T.state,T.message=state,message
    T.last=ticket and {id=ticket.id,kind=ticket.kind,visit=ticket.visit,item=ticket.item,quantity=ticket.quantity,total=ticket.total,
        auctionID=ticket.auctionID,state=state,message=message} or T.last
    ticket=nil
    if W.AuctionUI and W.AuctionUI.IsShown() then W.AuctionUI.Note(message) end
    Notify()
end
local function Current(p)
    local h=R.AuctionHost
    return ticket==p and Context() and h.Snapshot().visit==p.visit
end
local function Idle()
    if not Context() then return false,"Use the integrated TwichUI Auction House at a valid auctioneer outside combat." end
    if ticket then return false,"Finish or dismiss the current review first." end
    if T.state=="unknown" then return false,"The last result is unknown. Check Blizzard before reopening the auctioneer; no automatic retry is safe." end
    if Q.Pending()>0 or not C_AuctionHouse.IsThrottledMessageSystemReady() then return false,"Wait for the current live request to finish." end
    if R.AuctionWindow and R.AuctionWindow.LifecycleBusy() then return false,"Sell from Bags is busy." end
    return true
end
local function Review(p)
    local ok,why=Idle();if not ok then return nil,why end
    T.serial=T.serial+1;p.id=T.serial;p.visit=R.AuctionHost.Snapshot().visit
    ticket=p;T.state="review";T.message="Review the exact quantity and total before confirming.";Notify()
    return p.id,T.Review()
end
function T.Review()
    if not ticket then return nil end
    local p=ticket
    local allowed,why=T.Capability(p.kind)
    return {id=p.id,kind=p.kind,item=p.item,quantity=p.quantity,total=p.total,unit=p.unit,deposit=p.deposit,
        desired=p.desired,excess=p.desired and math.max(0,p.quantity-p.desired) or 0,
        itemKey=p.itemKey,link=p.link,retry=p.retry,duration=p.duration,vendor=p.vendor,quoteVersion=p.quoteVersion,estimated=p.kind=="buyCommodity" and T.state=="review",biddingCost=p.cost,allowed=allowed,reason=why,state=T.state,message=T.message}
end
local function LiveRow(p)
    local snap=Q.snapshot
    if not snap or snap~=p.snapshot or snap.epoch~=Q.epoch or not Q.Available() or not Q.Fresh(snap) then return nil end
    for _,row in ipairs(snap.rows) do
        if p.listingKey and row.listingKey==p.listingKey or not p.listingKey and row.auctionID==p.auctionID then return row end
    end
end
function T.CommodityEstimate(rows,item,quantity)
    quantity=Int(quantity,1,W.MAX_ID)
    if not quantity or type(rows)~="table" then return nil,"Enter a valid commodity quantity." end
    local tiers={}
    for _,r in ipairs(rows) do
        local unit,qty=Int(r.unit,1),Int(r.qty,1,W.MAX_ID)
        if r.item==item and r.ownershipKnown==true and not r.own and not r.account and unit and qty then tiers[#tiers+1]={unit=unit,qty=qty} end
    end
    table.sort(tiers,function(a,b) return a.unit<b.unit end)
    local remaining,total=quantity,0
    for _,tier in ipairs(tiers) do
        local take=math.min(remaining,tier.qty)
        if tier.unit>math.floor((W.Prices.MAX_COPPER-total)/take) then return nil,"The commodity total exceeds the supported money range." end
        total=total+tier.unit*take;remaining=remaining-take
        if remaining==0 then return total end
    end
    return nil,"The requested commodity quantity exceeds the complete non-owned live stock."
end
function T.PrepareBuy(row,desired)
    local snap=Q.snapshot
    if not row or not snap or not Q.Available() or not Q.Fresh(snap) or not snap.complete then return nil,"Inspect a complete, current live listing first." end
    local selected
    for _,r in ipairs(snap.rows) do
        if SameListing(r,row) and r.qty==row.qty and r.total==row.total and SameKey(r.itemKey,row.itemKey) then selected=r;break end
    end
    if not selected then return nil,"The selected live listing changed; inspect it again." end
    row=selected
    if row.ownershipKnown~=true or row.own or row.account then return nil,"The selected listing's ownership is unavailable or belongs to your account." end
    local key=Key(row.itemKey);local quantity=Int(row.purchaseQty or row.qty,1,W.MAX_ID);local total=Int(row.total,1)
    if not key or not quantity or (snap.kind~="commodity" and not total) then return nil,"This listing has no supported buyout or complete identity." end
    if snap.kind=="commodity" then
        local qty=Int(desired,1,W.MAX_ID)
        if not qty then return nil,"Enter a valid commodity quantity." end
        local estimate,why=T.CommodityEstimate(snap.rows,key.itemID,qty)
        if not estimate then return nil,why end
        local unit=math.ceil(estimate/qty)
        return Review({kind="buyCommodity",item=key.itemID,itemKey=key,quantity=qty,total=estimate,unit=unit,snapshot=snap,link=row.link,desired=qty,auctionID=row.auctionID,listingKey=row.listingKey})
    end
    if snap.kind~="item" then return nil,"A browse group is not a purchasable auction. Inspect its live listings." end
    return Review({kind="buyItem",item=key.itemID,itemKey=key,auctionID=Int(row.auctionID,1,9007199254740991),
        quantity=quantity,total=total,unit=math.ceil(total/quantity),link=row.link,snapshot=snap,desired=Int(desired,1,W.MAX_ID)})
end
-- A review may need fresh read evidence, but it never sends a transaction.
-- Keep this intent in the existing action owner and bind it to the read token,
-- visit and epoch, so unrelated responses cannot open a different review.
local function BuyReview(row,quantity)
    local id,why=T.PrepareBuy(row,quantity)
    if W.AuctionUI then W.AuctionUI.ReviewAction(id,why) end
    return id~=nil,why
end
function T.RequestBuy(row,quantity)
    local ok,why=Idle();if not ok then return false,why end
    if buyRequest then return false,"A purchase review is already refreshing." end
    local key=row and Key(row.itemKey)
    if not key then return false,"Choose an identifiable live item first." end
    quantity=Int(quantity or 1,1,W.MAX_ID)
    if not quantity then return false,"Enter a valid quantity." end
    local info=C_AuctionHouse.GetItemKeyInfo(key)
    if type(info)=="table" and W.Plain(info.isCommodity)==true then
        local unit=Int(row.unit,1)
        local estimate=unit and unit<=math.floor(W.Prices.MAX_COPPER/quantity) and unit*quantity or nil
        local id,reason=Review({kind="buyCommodity",item=key.itemID,itemKey=Key({itemID=key.itemID}),
            quantity=quantity,desired=quantity,total=estimate,unit=unit,link=row.link,directQuote=true})
        if not id then return false,reason end
        if W.AuctionUI then W.AuctionUI.ReviewAction(id) end
        local sent,why=T.Quote(id)
        if not sent and ticket then T.message=why or T.message;Notify() end
        -- The quantity prompt can close once the review owns this intent,
        -- including a retryable quote refusal shown inside that review.
        return true,why
    end
    local snap=Q.snapshot
    if snap and Q.Fresh(snap) and snap.complete and (snap.kind=="item" or snap.kind=="commodity") then
        for _,current in ipairs(snap.rows) do
            if SameListing(current,row) and SameKey(current.itemKey,key) then return BuyReview(current,quantity) end
        end
    end
    local request={key=key,quantity=quantity,visit=R.AuctionHost.Snapshot().visit,epoch=Q.epoch,intent=Q.serial+1,
        auctionID=row.liveKind=="item" and row.auctionID or nil}
    buyRequest=request;T.state="refreshing";T.message="Refreshing listings before review…"
    local sent,reason=Q.Search(key)
    if not sent and buyRequest==request then buyRequest=nil;T.state="idle";T.message=reason end
    Notify();return sent,reason
end
function T.ReadEnded(reason)
    if not buyRequest then return end
    buyRequest=nil;T.state="idle";T.message=reason or "Listing refresh ended."
    if W.AuctionUI then W.AuctionUI.Note(T.message) end
    Notify()
end
function T.ReadReady(snapshot)
    local request=buyRequest
    if not request then return end
    if request.needsSearch then
        if not Context() or request.visit~=R.AuctionHost.Snapshot().visit then T.ReadEnded("The auctioneer visit changed.");return end
        if Q.Pending()>0 or not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
        request.needsSearch=nil;request.epoch=Q.epoch;request.intent=Q.serial+1
        local ok,why=Q.Search(request.key)
        if not ok then T.ReadEnded(why) end
        return
    end
    if not snapshot then return end
    if not Context() or request.visit~=R.AuctionHost.Snapshot().visit or request.epoch~=Q.epoch
        or snapshot.intent~=request.intent or not Q.Fresh(snapshot) then
        buyRequest=nil;T.state="idle";return
    end
    -- Results and throttle-ready notifications can arrive in either order.
    -- Reuse that native event to finish the review; never resend the query.
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    buyRequest=nil;T.state="idle"
    if request.kind=="cancel" then
        local chosen
        if snapshot.kind=="owned" then
            for _,row in ipairs(snapshot.rows) do
                if row.auctionID==request.auctionID and SameKey(row.itemKey,request.key) then chosen=row;break end
            end
        end
        if chosen then
            local id,why=T.PrepareCancel(chosen)
            if W.AuctionUI then W.AuctionUI.ReviewAction(id,why) end
        elseif W.AuctionUI then W.AuctionUI.Note("That auction is no longer available to cancel. It may have sold or expired.") end
        Notify();return
    end
    local key=snapshot.kind=="commodity" and {itemID=snapshot.arg} or snapshot.kind=="item" and snapshot.arg
    if not SameKey(key,request.key) then return end
    if snapshot.kind=="commodity" then
        -- A partial book may inform an estimate, but only the native quote can
        -- authorize its total. Leave quote dispatch to the player's next click.
        local total=T.CommodityEstimate(snapshot.rows,key.itemID,request.quantity)
        local id,why=Review({kind="buyCommodity",item=key.itemID,itemKey=Key(key),quantity=request.quantity,
            desired=request.quantity,total=total,directQuote=true,retry=request.retry})
        if id and request.retry then T.message="That auction is no longer available. Retry to review the current total, then confirm your purchase.";Notify() end
        if W.AuctionUI then W.AuctionUI.ReviewAction(id,why) end
        return
    end
    if not snapshot.complete then
        T.message="The refreshed results are incomplete. Load the remaining listings before reviewing a purchase."
    else
        local chosen
        for _,row in ipairs(snapshot.rows) do
            if row.ownershipKnown and not row.own and not row.account and (row.total or row.commodity and row.unit)
                and (not request.auctionID or request.retry or row.auctionID==request.auctionID)
                and (not chosen or (row.unit or row.total)<(chosen.unit or chosen.total)) then chosen=row end
        end
        if chosen then
            local ok=BuyReview(chosen,request.quantity)
            if ok and request.retry and ticket then
                ticket.retry=true;T.message="That auction is no longer available. Review the updated quantity and total before retrying."
                Notify()
            end
            return
        end
        T.message=request.auctionID and "That listing is no longer available. Choose an updated listing."
            or "No available buyout listings were returned for this item."
    end
    if W.AuctionUI then W.AuctionUI.Note(T.message) end
    Notify()
end
RefreshBuy=function(p,unavailable)
    StopTimer();Listen(false);ticket=nil
    local request={key=p.itemKey,quantity=p.desired or p.quantity,visit=p.visit,retry=unavailable~=false,needsSearch=true}
    buyRequest=request;T.state="refreshing";T.message=unavailable==false and "Refreshing the current listing and total…" or "That auction is no longer available. Finding the next listing…"
    T.ReadReady()
    if W.AuctionUI then W.AuctionUI.Note(T.message) end
    Notify()
    return false,T.message
end
local function FreshBag(p)
    for _,row in ipairs(D.Bags("")) do if row.key==p.bagKey and row.identity==p.identity and row.qty==p.bagQuantity then return row end end
end
local function PostCheck(row,quantity,price,duration)
    local draft=D.Draft(row,quantity,price,duration)
    if not draft.valid then return nil,draft.reason end
    local p=R.AuctionPrice
    if not p or not row.location or not row.itemKey or type(row.copper)~="boolean" or not draft.deposit then return nil,"Posting identity or deposit is unavailable." end
    local why=p.Check({price=price,quantity=quantity,maxQuantity=D.Max(row),copperAllowed=row.copper,deposit=draft.deposit,money=Money()})
    if why then return nil,why end
    if Money()==nil then return nil,"Your available money is unreadable." end
    local types=Enum and Enum.ItemCommodityStatus
    local kind=types and (row.mode==types.Item and "postItem" or row.mode==types.Commodity and "postCommodity")
    if not kind then return nil,"The native item/commodity posting mode is unknown." end
    return {kind=kind,item=row.item,itemKey=Key(row.itemKey),bagKey=row.key,identity=row.identity,bagQuantity=row.qty,quantity=quantity,
        unit=price,total=draft.gross,duration=duration,deposit=draft.deposit,location=row.location,link=row.link,
        vendorEach=row.info.sell,vendor=p.VendorCheck(p.VendorPlan(kind=="postCommodity" and "commodity" or "item",quantity,price,row.info.sell))}
end
function T.PreparePost(row,quantity,price,duration)
    local p,why=PostCheck(row,quantity,price,duration);if not p then return nil,why end
    return Review(p)
end
local function NativeOwned(id)
    for i,raw in ipairs(C_AuctionHouse.GetOwnedAuctions() or {}) do
        if i>Q.MAX then break end
        if W.Plain(raw.auctionID)==id then return Q.Listing(raw) end
    end
end
-- Stale cancellation reviews refresh through the same sole read-intent slot as
-- buy reviews. Only the final Confirm click can send CancelAuction.
function T.RequestCancel(row,force)
    local ok,why=Idle();if not ok then return false,why end
    if buyRequest then return false,"An auction review is already refreshing." end
    local id=row and Int(row.auctionID,1,9007199254740991)
    local key=row and Key(row.itemKey)
    if not id or not key then return false,"Choose an active auction first." end
    local snap=Q.snapshot
    if not force and snap and snap.kind=="owned" and snap.complete and Q.Fresh(snap) then
        for _,current in ipairs(snap.rows) do
            if current.auctionID==id and SameKey(current.itemKey,key) then
                local review,reason=T.PrepareCancel(current)
                if W.AuctionUI then W.AuctionUI.ReviewAction(review,reason) end
                return review~=nil,reason
            end
        end
    end
    local request={kind="cancel",key=key,auctionID=id,visit=R.AuctionHost.Snapshot().visit,epoch=Q.epoch,intent=Q.serial+1}
    buyRequest=request;T.state="refreshing";T.message="Refreshing your auction and cancellation fee…"
    local sent,reason=Q.Begin("owned")
    if not sent and buyRequest==request then buyRequest=nil;T.state="idle";T.message=reason end
    Notify();return sent,reason
end
function T.PrepareCancel(row)
    if row and row.status==1 then return nil,"This auction has already sold and cannot be cancelled." end
    local snap=Q.snapshot
    if not snap or snap.kind~="owned" or not snap.complete or not Q.Available() or not Q.Fresh(snap) or not row or row.status~=0 then return nil,"Refresh and select an active owned listing first." end
    local found=false;for _,r in ipairs(snap.rows) do if r==row then found=true;break end end
    if not found then return nil,"The owned listing changed; refresh it." end
    local id=Int(row.auctionID,1,9007199254740991)
    local native=id and NativeOwned(id)
    if not native or native.status~=0 or native.qty~=row.qty or not SameKey(native.itemKey,row.itemKey)
        or W.Plain(C_AuctionHouse.CanCancelAuction(id))~=true then return nil,row.status==1 and "This auction has already sold." or "This auction is no longer available to cancel." end
    local cost=Int(C_AuctionHouse.GetCancelCost(id),0)
    if not cost or not Money() or cost>Money() then return nil,"Cancellation cost is unavailable or exceeds your money." end
    return Review({kind="cancel",item=row.item,itemKey=Key(row.itemKey),auctionID=id,quantity=row.qty,total=cost,cost=cost,link=row.link,snapshot=snap})
end
function T.PrepareRepost(row)
    if not row or not Key(row.itemKey) or not Int(row.qty,1,W.MAX_ID) then return false,"Select an identifiable owned listing." end
    T.repost={itemKey=Key(row.itemKey),item=row.item,quantity=row.qty,total=row.total,auctionID=row.auctionID}
    T.message="Repost preparation saved for this visit. Cancel separately, collect returned mail yourself, then select the returned bag item and review a new post."
    Notify();return true
end
local function Recheck(p)
    if not Current(p) then return false,"The auctioneer visit or interface changed." end
    local allowed,why=T.Capability(p.kind);if not allowed then return false,why end
    if R.AuctionWindow and R.AuctionWindow.LifecycleBusy() then return false,"Sell from Bags became busy; dismiss this review and check Blizzard." end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() or Q.Pending()>0 then return false,"The Auction House is busy." end
    local money=Money();if not money then return false,"Your money is unreadable." end
    if p.kind=="buyItem" then
        local row=LiveRow(p);local native=C_AuctionHouse.GetAuctionInfoByID(p.auctionID)
        if not row or (row.purchaseQty or row.qty)~=p.quantity or row.total~=p.total or row.own or row.account or row.ownershipKnown~=true
            or type(native)~="table" or not SameKey(native.itemKey,p.itemKey) or Int(native.buyoutAmount,1)~=p.total then return false,"The auction changed. Refresh and review it again." end
        local fresh
        local count=Int(C_AuctionHouse.GetNumItemSearchResults(p.itemKey),0,W.MAX_ID)
        for i=1,math.min(count or 0,Q.MAX) do
            local r=Q.Listing(C_AuctionHouse.GetItemSearchResultInfo(p.itemKey,i),"item")
            if r and r.auctionID==p.auctionID then fresh=r;break end
        end
        if not fresh or not SameKey(fresh.itemKey,p.itemKey) or (fresh.purchaseQty or fresh.qty)~=p.quantity or fresh.total~=p.total or
            fresh.ownershipKnown~=true or fresh.own or fresh.account then return false,"The live auction ownership or price changed; refresh it." end
        if p.total>money then return false,"Not enough money for this whole auction." end
    elseif p.kind=="buyCommodity" then
        if not p.directQuote and not LiveRow(p) and T.state~="quoted" then return false,"Commodity listings changed; inspect them again." end
        if p.total and p.total>money then return false,"Not enough money for the reviewed quantity." end
        local remaining=T.state=="quoted" and W.Plain(C_AuctionHouse.GetQuoteDurationRemaining())
        if T.state=="quoted" and (not p.quoteAt or not W.Finite(remaining) or remaining<=0) then return false,"The commodity quote expired. Request a new quote." end
    elseif p.kind=="cancel" then
        local row=LiveRow(p);local native=NativeOwned(p.auctionID)
        if not row or row.status~=0 or not native or native.status~=0 or native.qty~=p.quantity
            or not SameKey(native.itemKey,p.itemKey) or W.Plain(C_AuctionHouse.CanCancelAuction(p.auctionID))~=true
            or Int(C_AuctionHouse.GetCancelCost(p.auctionID),0)~=p.cost or p.cost>money then return false,"The owned listing or cancellation cost changed. Refresh it." end
    else
        local row=FreshBag(p);local fresh,why=PostCheck(row,p.quantity,p.unit,p.duration)
        if not fresh then return false,why end
        if fresh.kind~=p.kind or not SameKey(fresh.itemKey,p.itemKey) or fresh.total~=p.total or fresh.deposit~=p.deposit or fresh.vendorEach~=p.vendorEach then return false,"The bag item, price or deposit changed; review a new draft." end
        p.location=fresh.location
    end
    return true
end
local function Wait(p,state)
    StopTimer();T.state=state;Listen(true);Notify()
    timeout=C_Timer.NewTimer(12,function()
        if ticket==p then
            if p.kind=="buyCommodity" and p.phase=="quote" then
                StopTimer();T.state="review";p.retry=true;T.message="A price quote was not returned. Retry to request a new total.";Notify()
            else Finish("unknown","No matching completion arrived. Check Blizzard before retrying; no automatic retry was sent.") end
        end
    end)
end
local function Send(p,fn,...)
    Wait(p,"waiting") -- synchronous native responses must already have an owner
    sending=true;local ok,result=pcall(fn,...);sending=false
    if not ok then
        if p.kind=="buyCommodity" and p.phase=="quote" then
            StopTimer();T.state="review";p.retry=true
            T.message="The game could not request a quote. Retry to get the current total.";Notify();return false,T.message
        end
        Finish("unknown","The game refused the call or its outcome is unknown. Check Blizzard before retrying.");return false
    end
    return true,result
end
local function WarningHook()
    if hooked then return true end
    local dialog=StaticPopupDialogs and StaticPopupDialogs.AUCTION_HOUSE_POST_WARNING
    if not dialog or not hooksecurefunc then return false end
    hooksecurefunc(dialog,"OnAccept",function() if ticket and T.state=="native-warning" then T.ConfirmWarning(ticket.id) end end)
    hooksecurefunc(dialog,"OnHide",function() if ticket and T.state=="native-warning" then Finish("cancelled","Native posting warning was dismissed; no confirmation was sent.") end end)
    hooked=true;return true
end
function T.OwnsNativeWarning() return ticket~=nil and T.state=="native-warning" end
function T.Foreign()
    if ticket and not sending and T.state~="review" then Finish("unknown","Another auction operation made this response ambiguous. Check Blizzard before retrying.") end
end
local function TransactionHooks()
    if transactionHooks then return true end
    if not hooksecurefunc then return false end
    for _,name in ipairs({"PlaceBid","StartCommoditiesPurchase","ConfirmCommoditiesPurchase","CancelCommoditiesPurchase","PostItem","PostCommodity","ConfirmPostItem","ConfirmPostCommodity","CancelAuction"}) do
        if type(C_AuctionHouse[name])=="function" then hooksecurefunc(C_AuctionHouse,name,T.Foreign) end
    end
    transactionHooks=true;return true
end
-- Called only by a buy/review/retry button. A quote reserves a price; it never
-- confirms spending. Use the native frame's optional unit-price argument.
function T.Quote(id)
    local p=ticket
    if not p or p.id~=id or p.kind~="buyCommodity" or (T.state~="review" and T.state~="quoted") then return false,"That purchase review is no longer current." end
    if not Current(p) or Q.Pending()>0 or not C_AuctionHouse.IsThrottledMessageSystemReady() then return false,"Wait for the Auction House to be ready, then retry." end
    local allowed,why=T.Capability(p.kind);if not allowed then return false,why end
    if not TransactionHooks() then return false,"Native operation ownership cannot be monitored." end
    p.phase="quote";p.quoteAt=nil;T.message="Getting your total…"
    local sent=Send(p,C_AuctionHouse.StartCommoditiesPurchase,p.item,p.quantity,p.unit)
    if sent and ticket==p and T.state=="waiting" then T.state="quoting" end
    Notify();return sent
end
function T.Confirm(id,consent)
    local p=ticket
    if not p or p.id~=id or (T.state~="review" and T.state~="quoted") then return false,"That review is no longer current." end
    if p.kind=="buyCommodity" then
        local remaining=p.quoteAt and W.Plain(C_AuctionHouse.GetQuoteDurationRemaining())
        if T.state=="review" or not W.Finite(remaining) or remaining<=0 then return T.Quote(id) end
    end
    local ok,why=Recheck(p)
    if not ok then
        if p.kind=="buyItem" and Current(p) and (not Q.Fresh(p.snapshot) or why:find("changed",1,true)) then return RefreshBuy(p,Q.Fresh(p.snapshot)) end
        if p.kind=="cancel" and Current(p) and (not Q.Fresh(p.snapshot) or why:find("changed",1,true)) then
            StopTimer();Listen(false);ticket=nil;T.state="idle"
            return T.RequestCancel({auctionID=p.auctionID,itemKey=p.itemKey},true)
        end
        T.message=why;Notify();return false,why
    end
    if not TransactionHooks() then return false,"Native operation ownership cannot be monitored." end
    if p.kind=="buyItem" then return Send(p,C_AuctionHouse.PlaceBid,p.auctionID,p.total)
    elseif p.kind=="cancel" then return Send(p,C_AuctionHouse.CancelAuction,p.auctionID)
    elseif p.kind=="buyCommodity" then
        if T.state=="quoted" then
            if not consent or consent.quoteVersion~=p.quoteVersion or consent.total~=p.total or consent.quantity~=p.quantity then
                T.message="The quote changed. Review the displayed total before confirming again.";Notify();return false,T.message
            end
            p.phase="purchase";return Send(p,C_AuctionHouse.ConfirmCommoditiesPurchase,p.item,p.quantity)
        end
        return T.Quote(id)
    else
        if not WarningHook() then return false,"Native posting confirmation integration is unavailable." end
        local fn=p.kind=="postCommodity" and C_AuctionHouse.PostCommodity or C_AuctionHouse.PostItem
        local sent,warning
        if p.kind=="postCommodity" then sent,warning=Send(p,fn,p.location,p.duration,p.quantity,p.unit)
        else sent,warning=Send(p,fn,p.location,p.duration,p.quantity,nil,p.unit) end
        if sent and warning and ticket==p then T.state="native-warning";T.message="Review and accept the game's native posting warning.";Notify() end
        return sent
    end
end
function T.ConfirmWarning(id)
    local p=ticket;if not p or p.id~=id or T.state~="native-warning" then return false end
    local ok,why=Recheck(p);if not ok then Finish("cancelled",why);return false,why end
    if p.kind=="postCommodity" then return Send(p,C_AuctionHouse.ConfirmPostCommodity,p.location,p.duration,p.quantity,p.unit) end
    return Send(p,C_AuctionHouse.ConfirmPostItem,p.location,p.duration,p.quantity,nil,p.unit)
end
function T.Event(event,a,b)
    local p=ticket;if not p or not Current(p) then return end
    if event=="COMMODITY_PRICE_UPDATED" and p.kind=="buyCommodity" and p.phase=="quote" and (T.state=="quoting" or T.state=="waiting" or T.state=="quoted") then
        local unit,total=Int(a,1),Int(b,1)
        if not unit or not total or not Money() or total>Money() then Finish("cancelled","The quote is invalid or exceeds your money.");return end
        -- The authoritative tiered total is not reconstructed from a rounded unit.
        StopTimer()
        p.unit,p.total,p.quoteAt=unit,total,GetTime();p.quoteVersion=(p.quoteVersion or 0)+1;T.state="quoted";T.message="Authoritative quote received. Review its total and confirm explicitly.";Notify()
    elseif event=="AUCTION_HOUSE_PURCHASE_COMPLETED" and p.kind=="buyItem" and a==p.auctionID and T.state=="waiting" then
        Finish("complete","Purchase complete. Your item will arrive by mail.")
    elseif event=="COMMODITY_PURCHASE_SUCCEEDED" and p.kind=="buyCommodity" and p.phase=="purchase" and T.state=="waiting" then
        Finish("complete","Purchase complete. Your items will arrive by mail.")
    elseif event=="AUCTION_CANCELED" and p.kind=="cancel" and a==p.auctionID and T.state=="waiting" then
        Finish("complete","Auction cancelled. Your items will be returned by mail.")
    elseif event=="AUCTION_HOUSE_AUCTION_CREATED" and (p.kind=="postItem" or p.kind=="postCommodity") and T.state=="waiting" then
        local id=Int(a,1,9007199254740991)
        if id then p.created=p.created or {};p.created[id]=true end
        -- Creation has no request token; multiple item postings require their
        -- multisell completion rather than assuming the first ID means all posted.
        if p.kind=="postCommodity" or p.quantity==1 then Finish("complete","Auction posted. View it under My Auctions.") end
    elseif event=="AUCTION_MULTISELL_UPDATE" and p.kind=="postItem" and T.state=="waiting" and a==p.quantity and b==p.quantity then
        Finish("complete","All reviewed auctions were posted. View them under My Auctions.")
    elseif (event=="COMMODITY_PRICE_UNAVAILABLE" or event=="COMMODITY_PURCHASE_FAILED") and p.kind=="buyCommodity" then
        RefreshBuy(p)
    elseif event=="AUCTION_HOUSE_SHOW_ERROR" and p.kind=="buyItem" and Enum and Enum.AuctionHouseError and a==Enum.AuctionHouseError.ItemNotFound then
        RefreshBuy(p)
    elseif event=="AUCTION_MULTISELL_FAILURE" or event=="AUCTION_HOUSE_SHOW_ERROR" or event=="AUCTION_HOUSE_POST_ERROR" then
        Finish("unknown","The game reported an error. Reconcile in Blizzard before retrying; disappearance is not a confirmed sale.")
    end
end
function T.Cancel()
    if buyRequest then
        buyRequest=nil;T.state="idle";Q.Cancel("Auction review cancelled.")
    end
    if not ticket then return end
    if T.state=="review" then Finish("cancelled","Review dismissed; no action sent.")
    elseif T.state=="quoted" or T.state=="quoting" then
        if not InCombatLockdown() and R.AuctionHost.IsCurrent(ticket.visit) and C_AuctionHouse.CancelCommoditiesPurchase then
            sending=true;pcall(C_AuctionHouse.CancelCommoditiesPurchase);sending=false
        end
        Finish("cancelled","Commodity quote dismissed; no purchase confirmation sent.")
    elseif T.state=="native-warning" then
        Finish("cancelled","Native posting review was dismissed; no confirmation was sent.")
        if not InCombatLockdown() and StaticPopup_Hide then StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING") end
    else Finish("unknown","The interface closed with an action pending. Check Blizzard before retrying.") end
end
function T.Visit(id)
    if T.visit~=id then T.Cancel();T.visit=id;T.state="idle";T.message=nil;T.repost=nil end
end
function T.Snapshot()
    return {state=T.state,message=T.message,pending=(ticket or buyRequest) and 1 or 0,kind=ticket and ticket.kind or T.last and T.last.kind,
        quantity=ticket and ticket.quantity or 0,total=ticket and ticket.total or 0,
        listeners=listening and #EVENTS or 0,timers=timeout and 1 or 0}
end

-- Keep unfamiliar native read failures local and visible. A failure after dispatch
-- remains unknown; it can never become permission for an automatic retry.
for _,name in ipairs({"RequestBuy","RequestCancel","Quote","PrepareBuy","PreparePost","PrepareCancel","PrepareRepost","Confirm","ConfirmWarning"}) do
    local fn=T[name]
    T[name]=function(...)
        local ok,a,b=pcall(R.Perf.Call,"auction.actionReview",fn,...)
        if ok then return a,b end
        if name=="RequestBuy" or name=="RequestCancel" then T.ReadEnded("Listing refresh failed.") end
        T.message="The client could not validate this action. Check Blizzard before retrying."
        if ticket and T.state~="review" and T.state~="quoted" then Finish("unknown",T.message) else Notify() end
        return nil,T.message
    end
end
