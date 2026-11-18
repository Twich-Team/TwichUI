-- One explicit-action controller. Events/timers reconcile outcomes; they never
-- send a purchase, post or cancellation. Native per-mode evidence is independent
-- of the development presentation switch.
local R,W=TwichUI,TwichUI.Workshop
local Q,D=W.AuctionReads,W.AuctionSellData
local T={serial=0,state="idle"}
W.AuctionActions=T
local ticket,timeout,listening,sending,hooked
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
    if not b or b.development~=true then return false,"Auction transactions require a development build." end
    if type(b.verified)~="table" or b.verified[mode]~=true then return false,REASONS[mode] or "This auction operation is unsupported." end
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
    if not Context() then return false,"Use the integrated development Auction House at a valid auctioneer outside combat." end
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
        duration=p.duration,vendor=p.vendor,quoteVersion=p.quoteVersion,estimated=p.kind=="buyCommodity" and T.state=="review",biddingCost=p.cost,allowed=allowed,reason=why,state=T.state,message=T.message}
end
local function LiveRow(p)
    local snap=Q.snapshot
    if not snap or snap~=p.snapshot or snap.epoch~=Q.epoch or not Q.Available() or GetTime()-snap.at>=30 or GetTime()<snap.at then return nil end
    for _,row in ipairs(snap.rows) do if row.auctionID==p.auctionID then return row end end
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
    if not row or not snap or not Q.Available() or not snap.complete then return nil,"Inspect a complete, current live listing first." end
    local selected
    for _,r in ipairs(snap.rows) do
        if r.auctionID==row.auctionID and r.qty==row.qty and r.total==row.total and SameKey(r.itemKey,row.itemKey) then selected=r;break end
    end
    if not selected then return nil,"The selected live listing changed; inspect it again." end
    row=selected
    if row.ownershipKnown~=true or row.own or row.account then return nil,"The selected listing's ownership is unavailable or belongs to your account." end
    local key=Key(row.itemKey);local quantity=Int(row.qty,1,W.MAX_ID);local total=Int(row.total,1)
    if not key or not quantity or not total then return nil,"This listing has no supported buyout or complete identity." end
    if snap.kind=="commodity" then
        local qty=Int(desired,1,W.MAX_ID)
        if not qty then return nil,"Enter a valid commodity quantity." end
        local estimate,why=T.CommodityEstimate(snap.rows,key.itemID,qty)
        if not estimate then return nil,why end
        local unit=math.ceil(estimate/qty)
        return Review({kind="buyCommodity",item=key.itemID,itemKey=key,quantity=qty,total=estimate,unit=unit,snapshot=snap,desired=qty,auctionID=row.auctionID})
    end
    if snap.kind~="item" then return nil,"A browse group is not a purchasable auction. Inspect its live listings." end
    return Review({kind="buyItem",item=key.itemID,itemKey=key,auctionID=Int(row.auctionID,1,9007199254740991),
        quantity=quantity,total=total,unit=math.ceil(total/quantity),snapshot=snap,desired=Int(desired,1,W.MAX_ID)})
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
        unit=price,total=draft.gross,duration=duration,deposit=draft.deposit,location=row.location,
        vendorEach=row.info.sell,vendor=p.VendorCheck(p.VendorPlan(kind=="postCommodity" and "commodity" or "item",quantity,price,row.info.sell))}
end
function T.PreparePost(row,quantity,price,duration)
    local p,why=PostCheck(row,quantity,price,duration);if not p then return nil,why end
    return Review(p)
end
function T.PrepareCancel(row)
    local snap=Q.snapshot
    if not snap or snap.kind~="owned" or not snap.complete or not Q.Available() or not row or row.status~=0 then return nil,"Refresh and select an active owned listing first." end
    local found=false;for _,r in ipairs(snap.rows) do if r==row then found=true;break end end
    if not found then return nil,"The owned listing changed; refresh it." end
    local id=Int(row.auctionID,1,9007199254740991)
    if not id or not C_AuctionHouse.CanCancelAuction(id) then return nil,"The game does not permit cancelling this listing." end
    local cost=Int(C_AuctionHouse.GetCancelCost(id),0)
    if not cost or not Money() or cost>Money() then return nil,"Cancellation cost is unavailable or exceeds your money." end
    return Review({kind="cancel",item=row.item,itemKey=Key(row.itemKey),auctionID=id,quantity=row.qty,total=cost,cost=cost,snapshot=snap})
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
        if not row or row.qty~=p.quantity or row.total~=p.total or row.own or row.account or row.ownershipKnown~=true
            or type(native)~="table" or not SameKey(native.itemKey,p.itemKey) or Int(native.buyoutAmount,1)~=p.total then return false,"The auction changed. Refresh and review it again." end
        local fresh
        local count=Int(C_AuctionHouse.GetNumItemSearchResults(p.itemKey),0,W.MAX_ID)
        for i=1,math.min(count or 0,Q.MAX) do
            local r=Q.Listing(C_AuctionHouse.GetItemSearchResultInfo(p.itemKey,i))
            if r and r.auctionID==p.auctionID then fresh=r;break end
        end
        if not fresh or not SameKey(fresh.itemKey,p.itemKey) or fresh.qty~=p.quantity or fresh.total~=p.total or
            fresh.ownershipKnown~=true or fresh.own or fresh.account then return false,"The live auction ownership or price changed; refresh it." end
        if p.total>money then return false,"Not enough money for this whole auction." end
    elseif p.kind=="buyCommodity" then
        if not LiveRow(p) and T.state~="quoted" then return false,"Commodity listings changed; inspect them again." end
        if p.total>money then return false,"Not enough money for the reviewed quantity." end
        local remaining=T.state=="quoted" and W.Plain(C_AuctionHouse.GetQuoteDurationRemaining())
        if T.state=="quoted" and (not p.quoteAt or not W.Finite(remaining) or remaining<=0) then return false,"The commodity quote expired. Request a new quote." end
    elseif p.kind=="cancel" then
        local row=LiveRow(p)
        if not row or row.status~=0 or not C_AuctionHouse.CanCancelAuction(p.auctionID)
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
    StopTimer();T.state=state;Listen(true)
    timeout=C_Timer.NewTimer(12,function()
        if ticket==p then Finish("unknown","No matching completion arrived. Check Blizzard before retrying; no automatic retry was sent.") end
    end)
end
local function Send(p,fn,...)
    Wait(p,"waiting") -- synchronous native responses must already have an owner
    sending=true;local ok,result=pcall(fn,...);sending=false
    if not ok then Finish("unknown","The game refused the call or its outcome is unknown. Check Blizzard before retrying.");return false end
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
    for _,name in ipairs({"PlaceBid","StartCommoditiesPurchase","ConfirmCommoditiesPurchase","PostItem","PostCommodity","ConfirmPostItem","ConfirmPostCommodity","CancelAuction"}) do
        if type(C_AuctionHouse[name])=="function" then hooksecurefunc(C_AuctionHouse,name,T.Foreign) end
    end
    transactionHooks=true;return true
end
function T.Confirm(id,consent)
    local p=ticket
    if not p or p.id~=id or (T.state~="review" and T.state~="quoted") then return false,"That review is no longer current." end
    local ok,why=Recheck(p);if not ok then T.message=why;Notify();return false,why end
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
        p.phase="quote"
        -- Only the generated two-argument contract is implemented. Activation
        -- remains blocked until the Forever discrepancy is actually settled.
        local sent=Send(p,C_AuctionHouse.StartCommoditiesPurchase,p.item,p.quantity)
        if sent and ticket==p and T.state=="waiting" then T.state="quoting" end
        return sent
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
        p.unit,p.total,p.quoteAt=unit,total,GetTime();p.quoteVersion=(p.quoteVersion or 0)+1;T.state="quoted";T.message="Authoritative quote received. Review its total and confirm explicitly.";Notify()
    elseif event=="AUCTION_HOUSE_PURCHASE_COMPLETED" and p.kind=="buyItem" and a==p.auctionID and T.state=="waiting" then
        Finish("complete","Purchase confirmed for this auction ID. Delivery may arrive by mail; shopping quantities still follow actual bag stock.")
    elseif event=="COMMODITY_PURCHASE_SUCCEEDED" and p.kind=="buyCommodity" and p.phase=="purchase" and T.state=="waiting" then
        Finish("complete","Commodity purchase confirmed for the sole pending intent; delivery must still be reconciled from bags/mail.")
    elseif event=="AUCTION_CANCELED" and p.kind=="cancel" and a==p.auctionID and T.state=="waiting" then
        Finish("complete","Cancellation confirmed for this auction ID. Collect returned mail yourself before preparing a new post.")
    elseif event=="AUCTION_HOUSE_AUCTION_CREATED" and (p.kind=="postItem" or p.kind=="postCommodity") and T.state=="waiting" then
        local id=Int(a,1,9007199254740991)
        if id then p.created=p.created or {};p.created[id]=true end
        -- Creation has no request token; multiple item postings require their
        -- multisell completion rather than assuming the first ID means all posted.
        if p.kind=="postCommodity" or p.quantity==1 then Finish("complete","Posting creation event received for the sole pending draft; refresh My Auctions to reconcile.") end
    elseif event=="AUCTION_MULTISELL_UPDATE" and p.kind=="postItem" and T.state=="waiting" and a==p.quantity and b==p.quantity then
        Finish("complete","The native multisell reports all reviewed item postings completed; refresh My Auctions.")
    elseif event=="COMMODITY_PRICE_UNAVAILABLE" and p.kind=="buyCommodity" then Finish("cancelled","A commodity quote is unavailable; nothing was confirmed.")
    elseif event=="COMMODITY_PURCHASE_FAILED" or event=="AUCTION_MULTISELL_FAILURE" or event=="AUCTION_HOUSE_SHOW_ERROR" or event=="AUCTION_HOUSE_POST_ERROR" then
        Finish("unknown","The game reported an error. Reconcile in Blizzard before retrying; disappearance is not a confirmed sale.")
    end
end
function T.Cancel()
    if not ticket then return end
    if T.state=="review" then Finish("cancelled","Review dismissed; no action sent.")
    elseif T.state=="quoted" or T.state=="quoting" then
        if not InCombatLockdown() and R.AuctionHost.IsCurrent(ticket.visit) and C_AuctionHouse.CancelCommoditiesPurchase then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
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
    return {state=T.state,message=T.message,pending=ticket and 1 or 0,kind=ticket and ticket.kind or T.last and T.last.kind,
        quantity=ticket and ticket.quantity or 0,total=ticket and ticket.total or 0,
        listeners=listening and #EVENTS or 0,timers=timeout and 1 or 0}
end

-- Keep unfamiliar native read failures local and visible. A failure after dispatch
-- remains unknown; it can never become permission for an automatic retry.
for _,name in ipairs({"PrepareBuy","PreparePost","PrepareCancel","PrepareRepost","Confirm","ConfirmWarning"}) do
    local fn=T[name]
    T[name]=function(...)
        local ok,a,b=pcall(R.Perf.Call,"auction.actionReview",fn,...)
        if ok then return a,b end
        T.message="The client could not validate this action. Check Blizzard before retrying."
        if ticket and T.state~="review" and T.state~="quoted" then Finish("unknown",T.message) else Notify() end
        return nil,T.message
    end
end
