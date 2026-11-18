-- Experimental read transport. No transactions, automatic sends or retries.
-- Native events have no request IDs. Any ambiguity poisons this session.
local R,W=TwichUI,TwichUI.Workshop
local Q={experimental=false,epoch=0,serial=0,state="unavailable",MAX=500}
W.AuctionReads=Q
local pending, stream, sending, hooked
local deadline, expiry
local function StopTimers()
    if deadline then deadline:Cancel();deadline=nil end
    if expiry then expiry:Cancel();expiry=nil end
end
function Q.Integrated()
    local h=R.AuctionHost
    if not h or not h.DebugEnabled or not h.DebugEnabled() then return false end
    local x=h.Snapshot()
    return x.enabled and (x.state=="preparing" or x.state=="twichui") and h.IsCurrent(x.visit)
end
local function Context()
    local p=C_PlayerInteractionManager
    local e=Enum and Enum.PlayerInteractionType
    if not (p and e and e.Auctioneer) then return false end
    local ok,a,b=pcall(function()
        return p.IsInteractingWithNpcOfType(e.Auctioneer),p.IsValidNPCInteraction(e.Auctioneer)
    end)
    return ok and a==true and b==true and not (InCombatLockdown and InCombatLockdown())
end
function Q.Pending() return pending and 1 or 0 end
function Q.Available() return W.Active() and (Q.experimental or Q.Integrated()) and Context() and not Q.ambiguous end
-- Display lifetime and action freshness differ: old results remain readable,
-- while reviews and continuation requests require a fresh response.
function Q.Fresh(snapshot)
    snapshot=snapshot or Q.snapshot
    if not snapshot or snapshot.epoch~=Q.epoch or snapshot.stale then return false end
    local age=GetTime()-snapshot.at
    return age>=0 and age<30
end
function Q.End(reason)
    StopTimers()
    Q.epoch=Q.epoch+1
    pending=nil;stream=nil;Q.snapshot=nil;Q.state=reason or "unavailable"
    if W.AuctionActions and W.AuctionActions.ReadEnded then W.AuctionActions.ReadEnded(Q.state) end
    if W.AuctionUI then W.AuctionUI.Schedule() end
end
function Q.Cancel(reason)
    if pending then Q.ambiguous=true end
    Q.End(reason or "canceled")
end
function Q.Foreign()
    if not W.Active() then return end
    if not sending then
        if W.AuctionActions then W.AuctionActions.Foreign() end
        Q.ambiguous=true;Q.End("unattributed native query")
    end
end
local names={"SendBrowseQuery","SendSearchQuery","SendSellSearchQuery","QueryOwnedAuctions",
    "RequestMoreBrowseResults","RequestMoreItemSearchResults","RequestMoreCommoditySearchResults",
    "RefreshItemSearchResults","RefreshCommoditySearchResults","ReplicateItems"}
local function Hooks()
    if hooked then return true end
    if not hooksecurefunc or not C_AuctionHouse then return false end
    for _,name in ipairs(names) do
        if type(C_AuctionHouse[name])=="function" then hooksecurefunc(C_AuctionHouse,name,Q.Foreign) end
    end
    hooked=true;return true
end
-- Advanced diagnostic read opt-in, not persisted. Must be enabled before a fresh visit.
function Q.EnableExperimental(on)
    Q.experimental=on==true;Q.ambiguous=true;Q.End("reopen auctioneer after experimental opt-in")
end
function Q.Key(k)
    k=W.Plain(k)
    if type(k)~="table" then return nil end
    local id=W.Int(W.Plain(k.itemID),1,W.MAX_ID)
    if not id then return nil end
    local out={itemID=id}
    for _,f in ipairs({"itemLevel","itemSuffix","battlePetSpeciesID"}) do
        local value=k[f]
        if type(value)=="nil" then value=0 else value=W.Plain(value) end
        out[f]=W.Int(value,0,W.MAX_ID)
        if not out[f] then return nil end
    end
    return out
end
local function Same(a,b)
    a,b=Q.Key(a),Q.Key(b)
    return a and b and a.itemID==b.itemID and a.itemLevel==b.itemLevel and
        a.itemSuffix==b.itemSuffix and a.battlePetSpeciesID==b.battlePetSpeciesID
end
local function Amount(v) return W.Int(W.Plain(v),1,W.Prices.MAX_COPPER) end
function Q.Listing(x,mode,requestedItem)
    x=W.Plain(x)
    if type(x)~="table" then return nil end
    local qty=W.Int(W.Plain(x.quantity),1,W.MAX_ID)
    local id=W.Int(W.Plain(x.auctionID),1,9007199254740991)
    local commodity=mode==true or mode=="commodity"
    local key=commodity and Q.Key({itemID=x.itemID or requestedItem}) or Q.Key(x.itemKey or {itemID=x.itemID})
    if not qty or not key or (not commodity and not id) then return nil end
    local unit,total
    local priceEach=mode=="item"
    if commodity then
        unit=Amount(x.unitPrice)
        if not unit then return nil end
        total=W.Int(unit*qty,1,W.Prices.MAX_COPPER)
    elseif priceEach then
        -- Forever item-search quantity is availability at this price, not a
        -- stack sold for buyoutAmount. The native buy frame uses that amount
        -- directly for the representative auction; never divide it by stock.
        total=Amount(x.buyoutAmount);unit=total
    else total=Amount(x.buyoutAmount);unit=total and math.ceil(total/qty) end
    local own,account=W.Plain(x.containsOwnerItem),W.Plain(x.containsAccountItem)
    return {auctionID=id,itemKey=key,item=key.itemID,link=W.Text(W.Plain(x.itemLink),1000),qty=qty,unit=unit,total=total,
        priceEach=priceEach,purchaseQty=priceEach and 1 or qty,commodity=commodity,
        listingKey=commodity and ("commodity:"..key.itemID..":"..("%.0f"):format(unit)) or nil,
        bid=Amount(x.bidAmount) or Amount(x.minBid),status=W.Int(W.Plain(x.status),0,1),
        seconds=W.Int(W.Plain(x.timeLeftSeconds),0,W.MAX_ID),band=W.Int(W.Plain(x.timeLeft),0,10),
        own=own==true,account=account==true,
        ownershipKnown=type(own)=="boolean" and type(account)=="boolean",actionable=false}
end
local function Finish(state,rows,complete,event,rawCount)
    local current=pending or stream
    if not current then return end
    if deadline then deadline:Cancel();deadline=nil end
    if expiry then expiry:Cancel();expiry=nil end
    if Q.Integrated() and state=="empty" and not complete then state="unverified" end
    Q.snapshot={epoch=current.epoch,intent=current.id,kind=current.kind,rows=rows or {},arg=current.arg,
        complete=complete==true,at=GetTime(),experimental=true,visit=Q.visit,
        rawCount=rawCount or #(rows or {}),response=event,correlation="serialized-local"}
    Q.state=state;Q.lastResponse=event;pending=nil
    stream=Q.Integrated() and not complete and current or nil
    local snapshot=Q.snapshot
    expiry=C_Timer.NewTimer(30,function()
        if Q.snapshot~=snapshot then return end
        expiry=nil
        snapshot.stale=true;stream=nil;Q.state="stale; refresh live results"
        if W.AuctionActions and W.AuctionActions.ReadEnded then W.AuctionActions.ReadEnded("The refreshed listings are no longer current. Try reviewing again.") end
        if W.AuctionUI then W.AuctionUI.Schedule() end
    end)
    if W.AuctionActions and W.AuctionActions.ReadReady then W.AuctionActions.ReadReady(snapshot) end
    if W.AuctionUI then W.AuctionUI.Schedule() end
end
function Q.AttachVisit(id)
    if not Q.Integrated() then return end
    if Q.visit~=id then
        Q.visit=id;Q.open=true;Q.used={};Q.sent={};Q.ambiguous=false;Q.End("ready")
        if not Hooks() then Q.ambiguous=true;Q.state="Live read hooks unavailable" end
    end
end
function Q.Search(key)
    key=Q.Key(key)
    if not key then return false,"Invalid item identity." end
    local ok,info=pcall(C_AuctionHouse.GetItemKeyInfo,key)
    if not ok or type(info)~="table" or type(W.Plain(info.isCommodity))~="boolean" then
        return false,"The game has not supplied this item's auction type yet. Try Inspect again."
    end
    return Q.Begin(info.isCommodity and "commodity" or "item",info.isCommodity and key.itemID or key)
end
function Q.Snapshot()
    local ready=false
    if Context() and C_AuctionHouse and C_AuctionHouse.IsThrottledMessageSystemReady then
        local ok,value=pcall(C_AuctionHouse.IsThrottledMessageSystemReady);ready=ok and value==true
    end
    return {state=Q.state,pending=Q.Pending(),throttle=ready,lastRequest=Q.lastRequest,lastResponse=Q.lastResponse,
        results=Q.snapshot and #Q.snapshot.rows or 0,complete=Q.snapshot and Q.snapshot.complete==true or false,
        error=Q.lastError,epoch=Q.epoch,visit=Q.visit,timers=(deadline and 1 or 0)+(expiry and 1 or 0)}
end
function Q.BrowseQuery(opt)
    opt=opt or {}
    if opt.text~=nil and (type(opt.text)~="string" or #opt.text>200) then return nil,"Search text is invalid." end
    local query={searchString=W.Text(opt.text,200) or "",sorts={}}
    local filters=Enum and Enum.AuctionHouseFilter
    if filters then
        query.filters={}
        local names={[0]="PoorQuality",[1]="CommonQuality",[2]="UncommonQuality",[3]="RareQuality",[4]="EpicQuality",[5]="LegendaryQuality"}
        local quality=names[opt.quality]
        if quality and filters[quality] then query.filters[#query.filters+1]=filters[quality] end
        if opt.exact and filters.ExactMatch then query.filters[#query.filters+1]=filters.ExactMatch end
    end
    if opt.category then
        if #(opt.category.filters or {})==0 and not opt.category.implicit then
            return nil,"This category has no generic native browse filter; use its native workflow."
        end
        query.itemClassFilters=opt.category.filters
        if opt.category.implicit then
            query.filters=query.filters or {};query.filters[#query.filters+1]=opt.category.implicit
        end
    end
    query.minLevel=W.Int(opt.minLevel,0,W.MAX_ID)
    query.maxLevel=W.Int(opt.maxLevel,0,W.MAX_ID)
    if opt.minLevel~=nil and query.minLevel==nil or opt.maxLevel~=nil and query.maxLevel==nil or
        query.minLevel and query.maxLevel and query.minLevel>query.maxLevel then return nil,"Level restrictions are invalid." end
    local sorts=Enum and Enum.AuctionHouseSortOrder
    local allowed={Price=true,Name=true,Level=true,Bid=true,Buyout=true,TimeRemaining=true}
    if sorts and allowed[opt.sort] and sorts[opt.sort] then
        query.sorts={{sortOrder=sorts[opt.sort],reverseSort=opt.reverse==true}}
    end
    return query
end
function Q.Begin(kind,arg,more)
    if not Q.Available() then return false,"Live search unavailable: "..(Q.ambiguous and "another request or a timeout made the response uncertain; reopen the auctioneer." or "use the integrated TwichUI Auction House at an auctioneer.") end
    if pending then return false,"A live request is already pending." end
    if W.AuctionActions and W.AuctionActions.Busy() then return false,"An auction action is awaiting its result." end
    if not Q.Integrated() and Q.used and Q.used[kind] then return false,"Repeat reads cannot be attributed safely; reopen the auctioneer." end
    local api=C_AuctionHouse
    if not api or not Hooks() then return false,"Read APIs unavailable." end
    if not api.IsThrottledMessageSystemReady() then return false,"Auction House is busy; click Search again when ready." end
    local fn,args
    if kind=="browse" then
        if type(arg)~="table" or type(arg.searchString)~="string" or #arg.searchString>200 then return false,"Invalid search." end
        fn,args=more and api.RequestMoreBrowseResults or api.SendBrowseQuery,more and {} or {arg}
    elseif kind=="owned" then fn,args=api.QueryOwnedAuctions,{{}}
    elseif kind=="item" or kind=="commodity" then
        if kind=="item" then arg=Q.Key(arg) else arg=W.Int(W.Plain(arg),1,W.MAX_ID) end
        if not arg then return false,"Invalid item identity." end
        local now=GetTime();local kept={}
        for _,t in ipairs(Q.sent or {}) do if now-t<60 then kept[#kept+1]=t end end
        Q.sent=kept
        if not more and #kept>=100 then return false,"Search minute quota reached; wait before trying again." end
        if not more then kept[#kept+1]=now end
        if kind=="item" then fn,args=more and api.RequestMoreItemSearchResults or api.SendSearchQuery,more and {arg} or {arg,{},true}
        else
            -- Commodity details use the ordinary item-key search contract.
            fn,args=more and api.RequestMoreCommoditySearchResults or api.SendSearchQuery,more and {arg} or {{itemID=arg,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0},{},true}
        end
    else return false,"Unsupported live request." end
    if type(fn)~="function" then return false,"This client does not provide the requested read API." end
    StopTimers();stream=nil
    Q.used=Q.used or {};Q.used[kind]=true
    Q.serial=Q.serial+1
    local mine=Q.serial
    pending={id=mine,epoch=Q.epoch,kind=kind,arg=arg};Q.state="loading";Q.snapshot=nil
    Q.lastRequest=kind..(more and " continuation" or " search");Q.lastResponse=nil;Q.lastError=nil
    if W.AuctionUI then W.AuctionUI.Schedule() end
    sending=true
    local ok,hasFull=pcall(fn,unpack(args))
    sending=false
    if not ok then Q.lastError=tostring(hasFull);Q.Cancel("search failed");return false,"Search failed; details are in Diagnostics." end
    if pending then
        deadline=C_Timer.NewTimer(10,function()
            if pending and pending.id==mine then Q.lastError="No matching response before timeout";Q.Cancel(Q.Integrated() and "search timed out; result unknown" or "search timed out") end
        end)
    end
    if more and hasFull==true then
        Q.Event(kind=="browse" and "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or kind=="item" and "ITEM_SEARCH_RESULTS_UPDATED" or "COMMODITY_SEARCH_RESULTS_UPDATED",arg)
    end
    return true
end
function Q.More()
    local snap=Q.snapshot
    if snap and not Q.Fresh(snap) then return false,"Refresh these results before requesting more listings." end
    if not snap or snap.epoch~=Q.epoch or snap.complete or #snap.rows>=Q.MAX or snap.kind=="owned" then
        return false,"Refine the search or refresh; no further results can be requested."
    end
    return Q.Begin(snap.kind,snap.arg,true)
end
function Q.Refresh()
    local snap=Q.snapshot
    if not snap or snap.epoch~=Q.epoch then return false,"Choose a live search first." end
    return Q.Begin(snap.kind,snap.arg)
end
function Q.Event(event,key)
    if not W.Active() then return end
    if event=="AUCTION_HOUSE_SHOW" then
        if not Q.open then Q.open=true;Q.used={};Q.End("ready");Q.ambiguous=not ((Q.experimental or Q.Integrated()) and Context() and Hooks()) end
        return
    elseif event=="AUCTION_HOUSE_CLOSED" or event=="AUCTION_HOUSE_DISABLED" or event=="PLAYER_LEAVING_WORLD" then
        Q.open=false;Q.Cancel("unavailable");return
    end
    if event=="AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if W.AuctionActions and W.AuctionActions.ReadReady then W.AuctionActions.ReadReady(Q.snapshot) end
        if W.AuctionUI then W.AuctionUI.Schedule() end
        return
    end
    local p=pending or stream
    if not p or p.epoch~=Q.epoch then return end
    if not Context() then Q.Cancel("session ended");return end
    if event=="AUCTION_HOUSE_BROWSE_FAILURE" or event=="AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        Q.lastError=event;Q.Cancel("search failed; response unverified");return
    end
    local api=C_AuctionHouse
    local function Read()
        -- RECEIVED has no item-ID payload on Forever. Only read it for our
        -- sole commodity request, with native evidence for that queried item.
        if event=="COMMODITY_SEARCH_RESULTS_RECEIVED" and p.kind=="commodity" and key==nil then
            if not api.HasSearchResults or not api.HasSearchResults(Q.Key({itemID=p.arg})) then return end
            key=p.arg
        end
        local rows,complete,rawCount={},false,0
        if p.kind=="browse" and (event=="AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event=="AUCTION_HOUSE_BROWSE_RESULTS_ADDED") then
            local native=api.GetBrowseResults();rawCount=#(native or {})
            for i,x in ipairs(native or {}) do
                if i>Q.MAX then break end
                local k=Q.Key(x.itemKey)
                if k then rows[#rows+1]={itemKey=k,item=k.itemID,qty=W.Int(x.totalQuantity,1,W.MAX_ID),unit=Amount(x.minPrice),actionable=false} end
            end
            complete=api.HasFullBrowseResults() and #native<=Q.MAX and #rows==#native
        elseif p.kind=="owned" and event=="OWNED_AUCTIONS_UPDATED" then
            local native=api.GetOwnedAuctions();rawCount=#(native or {})
            for i,x in ipairs(native or {}) do if i>Q.MAX then break end
                local r=Q.Listing(x);if r then rows[#rows+1]=r end
            end
            complete=type(api.HasFullOwnedAuctionResults)=="function" and
                api.HasFullOwnedAuctionResults() and #native<=Q.MAX and #rows==#native or false
        elseif p.kind=="item" and (event=="ITEM_SEARCH_RESULTS_UPDATED" or event=="ITEM_SEARCH_RESULTS_ADDED") and Same(p.arg,key) then
            local count=api.GetNumItemSearchResults(p.arg);rawCount=count
            for i=1,math.min(count,Q.MAX) do
                local r=Q.Listing(api.GetItemSearchResultInfo(p.arg,i),"item")
                if r and Same(r.itemKey,p.arg) then rows[#rows+1]=r end
            end
            complete=api.HasFullItemSearchResults(p.arg) and count<=Q.MAX and #rows==count
        elseif p.kind=="commodity" and (event=="COMMODITY_SEARCH_RESULTS_UPDATED" or event=="COMMODITY_SEARCH_RESULTS_ADDED" or event=="COMMODITY_SEARCH_RESULTS_RECEIVED") and key==p.arg then
            local count=api.GetNumCommoditySearchResults(p.arg);rawCount=count
            for i=1,math.min(count,Q.MAX) do
                local r=Q.Listing(api.GetCommoditySearchResultInfo(p.arg,i),true,p.arg)
                if r and r.item==p.arg then r.commodity=true;rows[#rows+1]=r end
            end
            complete=api.HasFullCommoditySearchResults(p.arg) and count<=Q.MAX and #rows==count
        else return end
        Finish(#rows>0 and "results" or "empty",rows,complete,event,rawCount)
    end
    local ok,err=pcall(function() R.Perf.Call("auction.readSnapshot",Read) end)
    if not ok then Q.lastError=tostring(err);Q.Cancel(Q.Integrated() and "data unavailable; response unverified" or "data unavailable") end
end
local events={"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_DISABLED","PLAYER_LEAVING_WORLD",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY","AUCTION_HOUSE_BROWSE_RESULTS_UPDATED","AUCTION_HOUSE_BROWSE_RESULTS_ADDED","AUCTION_HOUSE_BROWSE_FAILURE", "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
    "ITEM_SEARCH_RESULTS_UPDATED","ITEM_SEARCH_RESULTS_ADDED","COMMODITY_SEARCH_RESULTS_UPDATED","COMMODITY_SEARCH_RESULTS_ADDED","COMMODITY_SEARCH_RESULTS_RECEIVED","OWNED_AUCTIONS_UPDATED"}
local handlers,listening={},false
function Q.Start()
    if listening or not W.Active() then return end
    listening=true
    for _,event in ipairs(events) do
        local name=event
        handlers[name]=handlers[name] or function(...) Q.Event(name,...) end
        R:On(name,handlers[name])
    end
end
function Q.Stop()
    if listening then
        for _,event in ipairs(events) do R:Off(event,handlers[event]) end
    end
    listening=false;Q.open=false;Q.ambiguous=true
    Q.Cancel("Workshop disabled; reopen auctioneer after enabling")
end
Q.Start()

-- Refused clicks are visible in the integrated panel without flooding chat.
for _,name in ipairs({"Begin","More","Refresh","Search"}) do
    local fn=Q[name]
    Q[name]=function(...)
        local ok,why=fn(...)
        if not ok then Q.lastError=why;if W.AuctionUI then W.AuctionUI.Schedule() end end
        return ok,why
    end
end
