-- AH-6: presentation-only adapter. All values/history come from Workshop services.
-- No saved-data parsing, import, network, native AH calls or valuation algorithms.
local R,W=TwichUI,TwichUI.Workshop
local D={DAY=86400,RANGES={{2,"Recent 48h"},{7,"7-day window"},{14,"14-day window"},
    {30,"30-day window"},{60,"60-day window"},{120,"120-day window"}}}
W.AuctionMarketData=D
local MK,PR,AD=W.Market,W.Prices,W.AdvisorData
local cached,last
function D.Clear() cached,last=nil,nil end
function D.Stats() return {cache=cached and 1 or 0,points=last and last.series and #last.series.points or 0,
    groups=last and last.series and #last.series.groups or 0} end
function D.Resolve(key)
    if key=="server" and W.ServerMarket then return W.ServerMarket.Context() end
    if not key or key=="auto" then return MK.Source().market end
    return PR.Market(key) -- an unavailable explicit market never falls back
end
function D.Markets()
    local out={{"auto","Automatic saved market"}}
    local keys=PR.Keys();table.sort(keys)
    for _,key in ipairs(keys) do
        local m=PR.Market(key)
        if m then out[#out+1]={key,PR.Label(m)} end
    end
    if W.ServerMarket then out[#out+1]={"server","Market server (external)"} end
    return out
end
function D.Context(item,opt)
    item=W.Int(item,1,W.MAX_ID);if not item then return nil end
    opt=opt or {}
    local k=opt.itemKey and W.AuctionReads.Key(opt.itemKey)
    if opt.itemKey and (not k or k.itemID~=item) then return nil end
    return {item=item,itemKey=k,market=W.Text(opt.market,200),serverVariant=W.Text(opt.serverVariant,64),
        variant=opt.variant==true or k and (k.itemLevel~=0 or k.itemSuffix~=0 or k.battlePetSpeciesID~=0) or false}
end
function D.TrackStamp()
    local ids={}
    for id,on in pairs(AD.Tracked()) do if on==true and W.Int(id,1,W.MAX_ID) then ids[#ids+1]=id end end
    table.sort(ids)
    return table.concat(ids,":")
end
function D.Catalog(opt)
    opt=opt or {}
    if opt.external and W.ServerMarket then return W.ServerMarket.Catalog(opt) end
    local sources,enumerate={},nil
    if opt.scope=="tracked" then sources[1]=AD.Tracked()
    elseif opt.scope=="bags" then
        enumerate=function(add,tick,job)
            local api=C_Container
            if not(api and api.GetContainerNumSlots and api.GetContainerItemInfo) then
                job.unavailable="Bag information unavailable";return
            end
            for bag=0,(NUM_BAG_SLOTS or 4) do
                for slot=1,math.min(api.GetContainerNumSlots(bag) or 0,200) do
                    local x=api.GetContainerItemInfo(bag,slot)
                    if type(x)=="table" then add(W.Plain(x.itemID)) end
                    tick();if job.capped then return end
                end
            end
        end
    else
        for _,name in ipairs({"items","h2","c2","hist","dist"}) do
            local t=opt.market and opt.market[name]
            if type(t)=="table" then sources[#sources+1]=t end
        end
    end
    return W.AuctionBrowseData.Job({market=opt.market,sources=sources,enumerate=enumerate,index=true,
        item=opt.item,query=opt.query,category=opt.category,quality=opt.quality})
end
-- Translate typed history records to bounded chart inputs; never decode, resample
-- or turn weekly/fortnight/legacy aggregates into daily observations.
function D.Series(history,days,now)
    if not history then return nil end
    days=W.Int(days,1,120) or 14
    local today=math.floor(now/D.DAY)
    local from=days==2 and now/D.DAY-2 or today-days+1
    local to=days==2 and now/D.DAY or today
    local s={points={},groups={},gaps={},from=from,to=to,today=today,damaged=history.damaged,
        basis=history.basis,metric="min",recent=days==2,observations=0}
    for _,p in ipairs(history.points or {}) do
        if p.kind=="obs" then
            local at=p.last or p.at
            if at and at>=now-2*D.DAY and at<=now then
                s.observations=s.observations+1
                if days==2 and p.v then s.points[#s.points+1]={day=at/D.DAY,price=p.v,kind=p.kind,
                    provenance=p.provenance,partial=p.partial,at=p.at,last=p.last} end
            end
        elseif days~=2 and p.from and p.to and p.to>=from and p.from<=to then
            if (p.kind=="day" or p.kind=="legacy-day") and p.v then
                s.points[#s.points+1]={day=p.from,price=p.v,kind=p.kind,provenance=p.provenance,partial=p.partial}
            elseif p.kind=="week" or p.kind=="fortnight" or p.kind=="legacy-bucket" then
                s.groups[#s.groups+1]={from=p.from,to=p.to,average=p.v,low=p.lo,high=p.hi,n=p.n,
                    kind=p.kind,provenance=p.provenance,partial=p.partial}
            end
        end
    end
    for _,g in ipairs(history.gaps or {}) do
        if g.to>=math.floor(from) and g.from<=math.floor(to) then s.gaps[#s.gaps+1]=g end
    end
    table.sort(s.points,function(a,b) return a.day<b.day end) -- typed service output is bounded
    return s
end
function D.Project(item,market,days,opt)
    opt=opt or {}
    local now=opt.now or time()
    local variant=opt.variant==true
    -- Do not pass nil into services that interpret nil as the automatic market.
    if not market then
        D.Clear()
        return {item=item,facts={nomarket=true,item=item},why="nomarket",variant=variant}
    end
    local facts=W.Facts.Of(item,{market=market,variant=variant,now=now})
    if not cached or cached.facts~=facts or cached.item~=item or cached.variant~=variant then
        local function Build()
            local o={market=market,variant=variant,now=now}
            local h,why=MK.History(item,"min",o)
            return {item=item,facts=facts,history=h,why=why,variant=variant,
                market=market.key,label=PR.Label(market),trend=MK.TrendOf(item,"min",14,o),
                posture=MK.Posture(item,o),distribution=MK.Distribution(item,o)}
        end
        cached=R.Perf.Call("auction.marketDetails",Build)
    end
    last={item=item,facts=facts,history=cached.history,why=cached.why,variant=variant,market=cached.market,
        label=cached.label,trend=cached.trend,posture=cached.posture,distribution=cached.distribution,
        series=D.Series(cached.history,days,now)}
    return last
end
