-- Experimental read transport. No transactions, automatic sends or retries.
-- Native events have no request IDs. Any ambiguity poisons this session.
local R,W=TwichUI,TwichUI.Workshop
local Q={experimental=false,epoch=0,serial=0,state="unavailable",MAX=500}
W.AuctionReads=Q
local pending, sending, hooked
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
function Q.Available() return Q.experimental and Context() and not Q.ambiguous end
function Q.End(reason)
    Q.epoch=Q.epoch+1
    pending=nil;Q.snapshot=nil;Q.state=reason or "unavailable"
    if W.AuctionUI then W.AuctionUI.Schedule() end
end
function Q.Cancel(reason)
    if pending then Q.ambiguous=true end
    Q.End(reason or "canceled")
end
function Q.Foreign()
    if not sending then Q.ambiguous=true;Q.End("unattributed native query") end
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
-- Explicit development opt-in, not persisted. Must be enabled before a fresh visit.
function Q.EnableExperimental(on)
    Q.experimental=on==true;Q.ambiguous=true;Q.End("reopen auctioneer after experimental opt-in")
end
function Q.Key(k)
    if type(k)~="table" or not W.Int(k.itemID,1,W.MAX_ID) then return nil end
    local out={itemID=k.itemID}
    for _,f in ipairs({"itemLevel","itemSuffix","battlePetSpeciesID"}) do
        out[f]=W.Int(k[f] or 0,0,W.MAX_ID)
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
function Q.Listing(x,commodity)
    if type(x)~="table" then return nil end
    local qty=W.Int(W.Plain(x.quantity),1,W.MAX_ID)
    local id=W.Int(W.Plain(x.auctionID),1,9007199254740991)
    local key=Q.Key(x.itemKey or {itemID=x.itemID})
    if not qty or not id or not key then return nil end
    local unit,total
    if commodity then
        unit=Amount(x.unitPrice)
        total=unit and W.Int(unit*qty,1,W.Prices.MAX_COPPER)
    else total=Amount(x.buyoutAmount);unit=total and math.ceil(total/qty) end
    return {auctionID=id,itemKey=key,item=key.itemID,qty=qty,unit=unit,total=total,
        bid=Amount(x.bidAmount) or Amount(x.minBid),status=W.Int(x.status,0,1),
        seconds=W.Int(x.timeLeftSeconds,0,W.MAX_ID),band=W.Int(x.timeLeft,0,10),
        own=x.containsOwnerItem==true,account=x.containsAccountItem==true,actionable=false}
end
local function Finish(state,rows,complete)
    if not pending then return end
    Q.snapshot={epoch=pending.epoch,intent=pending.id,kind=pending.kind,rows=rows or {},
        complete=complete==true,at=GetTime(),experimental=true}
    Q.state=state;pending=nil
    local snapshot=Q.snapshot
    C_Timer.After(30,function()
        if Q.snapshot==snapshot then Q.End("results stale; reopen auctioneer") end
    end)
    if W.AuctionUI then W.AuctionUI.Schedule() end
end
function Q.BrowseQuery(opt)
    opt=opt or {}
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
        query.itemClassFilters=opt.category.filters
        if opt.category.implicit then
            query.filters=query.filters or {};query.filters[#query.filters+1]=opt.category.implicit
        end
    end
    query.minLevel=W.Int(opt.minLevel,0,W.MAX_ID)
    query.maxLevel=W.Int(opt.maxLevel,0,W.MAX_ID)
    local sorts=Enum and Enum.AuctionHouseSortOrder
    local allowed={Price=true,Name=true,Level=true,Bid=true,Buyout=true,TimeRemaining=true}
    if sorts and allowed[opt.sort] and sorts[opt.sort] then
        query.sorts={{sortOrder=sorts[opt.sort],reverseSort=opt.reverse==true}}
    end
    return query
end
function Q.Begin(kind,arg)
    if not Q.Available() then return false,"Experimental reads disabled, unavailable or ambiguous; use saved data." end
    if pending then return false,"A read is already pending." end
    if Q.used and Q.used[kind] then return false,"Repeat reads cannot be attributed safely; reopen the auctioneer." end
    local api=C_AuctionHouse
    if not api or not Hooks() then return false,"Read APIs unavailable." end
    if not api.IsThrottledMessageSystemReady() then return false,"Throttled; retry explicitly." end
    local fn,args
    if kind=="browse" then
        if type(arg)~="table" or type(arg.searchString)~="string" or #arg.searchString>200 then return false,"Invalid search." end
        fn,args=api.SendBrowseQuery,{arg}
    elseif kind=="owned" then fn,args=api.QueryOwnedAuctions,{{}}
    elseif kind=="item" then
        local key=Q.Key(arg);if not key then return false,"Invalid item key." end
        local now=GetTime();local kept={}
        for _,t in ipairs(Q.sent or {}) do if now-t<60 then kept[#kept+1]=t end end
        Q.sent=kept
        if #kept>=100 then return false,"Search minute quota reached." end
        kept[#kept+1]=now;fn,args=api.SendSearchQuery,{key,{},true}
        arg=key
    else return false,"Unsupported read." end
    if type(fn)~="function" then return false,"Read API unavailable." end
    Q.used=Q.used or {};Q.used[kind]=true
    Q.serial=Q.serial+1
    local mine=Q.serial
    pending={id=mine,epoch=Q.epoch,kind=kind,arg=arg};Q.state="loading";Q.snapshot=nil
    sending=true
    local ok=pcall(fn,unpack(args))
    sending=false
    if not ok then Q.Cancel("search failed");return false,"Search failed." end
    C_Timer.After(10,function() if pending and pending.id==mine then Q.Cancel("search timed out") end end)
    return true
end
function Q.Event(event,key)
    if event=="AUCTION_HOUSE_SHOW" then
        if not Q.open then Q.open=true;Q.used={};Q.End("ready");Q.ambiguous=not (Q.experimental and Context() and Hooks()) end
        return
    elseif event=="AUCTION_HOUSE_CLOSED" or event=="AUCTION_HOUSE_DISABLED" or event=="PLAYER_LEAVING_WORLD" then
        Q.open=false;Q.Cancel("unavailable");return
    end
    if not pending or pending.epoch~=Q.epoch then return end
    if not Context() then Q.Cancel("session ended");return end
    if event=="AUCTION_HOUSE_BROWSE_FAILURE" then Q.Cancel("search failed");return end
    local p,api=pending,C_AuctionHouse
    local function Read()
        local rows,complete={},false
        if p.kind=="browse" and event=="AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then
            local native=api.GetBrowseResults()
            for i,x in ipairs(native or {}) do
                if i>Q.MAX then break end
                local k=Q.Key(x.itemKey)
                if k then rows[#rows+1]={itemKey=k,item=k.itemID,qty=W.Int(x.totalQuantity,1,W.MAX_ID),unit=Amount(x.minPrice),actionable=false} end
            end
            complete=api.HasFullBrowseResults() and #native<=Q.MAX and #rows==#native
        elseif p.kind=="owned" and event=="OWNED_AUCTIONS_UPDATED" then
            local native=api.GetOwnedAuctions()
            for i,x in ipairs(native or {}) do if i>Q.MAX then break end
                local r=Q.Listing(x);if r then rows[#rows+1]=r end
            end
            complete=type(api.HasFullOwnedAuctionResults)=="function" and
                api.HasFullOwnedAuctionResults() and #native<=Q.MAX and #rows==#native or false
        elseif p.kind=="item" and event=="ITEM_SEARCH_RESULTS_UPDATED" and Same(p.arg,key) then
            local count=api.GetNumItemSearchResults(p.arg)
            for i=1,math.min(count,Q.MAX) do
                local r=Q.Listing(api.GetItemSearchResultInfo(p.arg,i))
                if r and Same(r.itemKey,p.arg) then rows[#rows+1]=r end
            end
            complete=api.HasFullItemSearchResults(p.arg) and count<=Q.MAX and #rows==count
        else return end
        Finish(#rows>0 and "results" or "empty",rows,complete)
    end
    if not pcall(function() R.Perf.Call("auction.readSnapshot",Read) end) then Q.Cancel("data unavailable") end
end
local events={"AUCTION_HOUSE_SHOW","AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_DISABLED","PLAYER_LEAVING_WORLD",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED","AUCTION_HOUSE_BROWSE_FAILURE","ITEM_SEARCH_RESULTS_UPDATED","OWNED_AUCTIONS_UPDATED"}
for _,event in ipairs(events) do R:On(event,function(...) Q.Event(event,...) end) end
