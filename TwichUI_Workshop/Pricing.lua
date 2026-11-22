-- Workshop references over the Companion-selected market, with independent local
-- scans. Native auction listings/actions continue to use Market.Source directly.
local R,W=TwichUI,TwichUI.Workshop
local MK,PR,B,J=W.Market,W.Prices,W.Bridge,W.BridgeCodec
local P={MAX_CACHE=8192,MAX_AGE=86400}
local CURRENT_ONLY={current=true}
W.Pricing=P
setmetatable(P,{__index=MK})
local cache,count,stamp={},0,nil
local header,headerGeneration,headerAt
local chartCache,chartPending
local pending,pendingCount={},0
local revision,epoch=0,0
local notification,notificationDelay
local notificationToken=0
local function observed(id)
    if R.Perf and R.Perf.on then R.Perf.Count('workshop.pricing.'..id) end
end
local diagnostic
local function elapsedClock()return (GetTimePreciseSec and GetTimePreciseSec() or GetTime and GetTime() or 0)*1000 end
local function capture()
    if not (R.Perf and R.Perf.on and R.Perf.Observe) then return end
    if not diagnostic or diagnostic.capture~=R.Perf.captureID then
        diagnostic={capture=R.Perf.captureID,priced=0}
    end
    return diagnostic
end
local function started(at)
    local d=capture();if not d then return end
    local now=at or elapsedClock();d.priceStart=d.priceStart or now
    return {at=now,capture=d.capture}
end
local function completed(timing,r)
    local d=capture();if not (d and timing and timing.capture==d.capture) then return end
    local now=elapsedClock()
    R.Perf.Observe('workshop.priceSettlementWait',math.max(0,now-timing.at));observed('completed')
    local recent=r and r.current.metrics.recent_copper
    if recent and recent~=J.NULL then
        R.Perf.Observe('workshop.priceWait',math.max(0,now-timing.at));d.priced=d.priced+1
        if d.priced==1 then R.Perf.Observe('workshop.firstColdPrice',now-d.priceStart) end
        if d.priced==10 then R.Perf.Observe('workshop.tenColdPrices',now-d.priceStart) end
    end
end
function P.BeginView()
    local d=capture();if d and not d.viewStart then d.viewStart=elapsedClock() end
end
local function itemPending(item)
    return type(item)=='number' and pending[item%64] and pending[item%64][item]~=nil
end
local function recipePending(rec)
    if itemPending(rec.outItem) then return true end
    for _,mat in ipairs(rec.mats or {})do if itemPending(mat.item)then return true end end
    return false
end
function P.ObserveView(all,list)
    local d=capture();if not (d and d.viewStart and #all>0)then return end
    -- Catalog construction can expose rows before the first list publication.
    -- Do not permanently capture an empty viewport in that interval.
    if not d.visible and #list.data==0 then return end
    if not d.visible then
        d.visible={};d.visibleCount=0
        local scroll=list.scroll:GetVerticalScroll() or 0
        local height=list.scroll:GetHeight() or 0;if height<=list.rowH then height=list.minH end
        local first=math.floor(scroll/list.rowH)+1
        local last=math.min(#list.data,math.ceil((scroll+height)/list.rowH))
        for i=first,math.min(last,first+127)do
            d.visible[list.data[i].rec.id]=true;d.visibleCount=d.visibleCount+1
        end
        R.Perf.Count('workshop.pricing.initialVisibleRows',d.visibleCount)
        if last-first+1>128 then observed('visibleTruncated')end
    end
    local waiting,visibleWaiting,visiblePriced,seen=0,0,0,0
    for _,row in ipairs(all)do
        local waits=recipePending(row.rec)or row.est.why=='calculating'
        if waits then waiting=waiting+1 end
        if d.visible[row.rec.id]then
            seen=seen+1
            if waits then visibleWaiting=visibleWaiting+1
            elseif row.est.state=='ok' then visiblePriced=visiblePriced+1 end
        end
    end
    local elapsed=math.max(0,elapsedClock()-d.viewStart)
    if visiblePriced>0 and not d.firstVisible then d.firstVisible=true;R.Perf.Observe('workshop.firstVisiblePrice',elapsed)end
    if visiblePriced>=10 and not d.tenVisible then d.tenVisible=true;R.Perf.Observe('workshop.tenVisiblePrices',elapsed)end
    if seen==d.visibleCount and seen>0 and visibleWaiting==0 and not d.visibleDone then
        d.visibleDone=true;R.Perf.Observe('workshop.visibleSettled',elapsed)
    end
    if waiting==0 and not d.allDone then d.allDone=true;R.Perf.Observe('workshop.opportunitiesSettled',elapsed)end
end
function P.Notify(delay)
    delay=delay or 0.1
    if notification and (delay>0 or notificationDelay==0) then return end
    notificationToken=notificationToken+1
    local mine=notificationToken
    notification,notificationDelay=true,delay
    C_Timer.After(delay,function()
        if mine~=notificationToken then return end
        notification=false
        if W.Active() then observed('notifications');P.Changed() end
    end)
end
function P.CancelPending()
    if pendingCount>0 and R.Perf and R.Perf.on then R.Perf.Count('workshop.pricing.cancelled',pendingCount)end
    pending,pendingCount={},0
    epoch=epoch+1
    notificationToken=notificationToken+1;notification=false
    chartPending=nil
end
local function dataStamp(status)
    status=status or B.Status()
    return (status.generation or "")..":"..tostring(status.failures or 0)
end
local function localMarket(opt)
    local m=opt and opt.market
    if m and m.pricing then return m.localMarket end
    if type(m)=='table' then return m.items and m or m.market end
    if type(m)=='string' then return PR.Market(m) end
    return MK.Source().market
end
local function options(opt)
    return {market=localMarket(opt),now=opt and opt.now,variant=opt and opt.variant,localOnly=true,fromCompeting=opt and opt.fromCompeting or nil}
end
local function eligible(now,status)
    if not (W.Active() and B) then return nil,'unavailable' end
    status=status or B.Status()
    if not (status.ready and status.summary) then return nil,'unavailable' end
    local generation=status.generation
    if headerGeneration~=generation then
        header,headerGeneration,headerAt=B.Manifest(),generation,nil
        if header and type(header.source_observation)=='table' then local _,at=W.BridgeValidate.Time(header.source_observation.observed_at);headerAt=at end
    end
    local h=header
    if not h or h.synthetic or not h.market.mapping_verified or h.pricing_algorithm~='twichui-pricing-v1' then return nil,'unsupported' end
    local at=headerAt
    now=now or time()
    if not at or now<at or now-at>P.MAX_AGE then return nil,'stale' end
    local side
    if W.Scan.AuctionOpen() then local _,_,s=W.Scan.Market();side=s
    elseif UnitFactionGroup then side=W.Plain(UnitFactionGroup('player')) end
    if side~=h.market.faction then return nil,'market_mismatch' end
    return h,nil,at
end
function P.Generation()
    local s=B.Status()
    return table.concat({s.generation or '',s.failures or 0,tostring(s.ready),epoch,revision},':')
end
-- Partial completions retain the calculation context; Session invalidates only
-- their item dependencies. Public Generation still includes PR1's revision.
function P.ContextGeneration()
    local s=B.Status();return dataStamp(s)..':'..tostring(s.ready)
end
local chartRevision=0
function P.ChartRevision()return chartRevision end
function P.BaseKey(item)
    item=W.Int(item,1,W.MAX_ID)
    if item then observed('baseKeys');return J.SHA('{"id":'..string.format('%.0f',item)..'}') end
end
local function record(item,opt,completion,defer)
    local asked=R.Perf and R.Perf.on and elapsedClock()
    if opt and opt.variant then return nil,'variant' end
    local status=B and B.Status()
    local h,why,at=eligible(opt and opt.now,status)
    if not h then return nil,why end
    item=W.Int(item,1,W.MAX_ID);if not item then return nil,'baditem' end
    local current=dataStamp(status)
    if stamp~=current then cache,count,stamp={},0,current;pending,pendingCount={},0;chartCache,chartPending=nil,nil end
    local entry=cache[item]
    if entry then return entry.record or nil,entry.why,h,at end
    local bucket=item%64
    local reserved=pending[bucket] and pending[bucket][item]
    if reserved and not completion then observed('deduplicated');return nil,'loading',h,at end
    if not reserved and count+pendingCount>=P.MAX_CACHE then return nil,'lookup_limit',h,at end
    local waits=pending[bucket]
    local timing=reserved and waits.timings and waits.timings[item] or not reserved and started(asked)
    local mine=epoch
    local key=reserved or P.BaseKey(item)
    local r,reason
    if defer or waits and waits.preparing then reason='loading'
    else observed('readerCalls');r,reason=B.Record(item,key,CURRENT_ONLY)end
    -- Do not keep daily arrays or mutable decoder rows in the price cache.
    if r then r={current=J.Copy(r.current),variant_key=r.variant_key} end
    if reason=='loading' then
        local waits=pending[bucket]
        if not waits then waits={ids={},cursor=1};pending[bucket]=waits end
        if not waits[item] and pendingCount<P.MAX_CACHE then
            waits[item]=key;waits.ids[#waits.ids+1]=item;pendingCount=pendingCount+1;observed('uniquePending')
            waits.members=waits.members or {};waits.members[item]=true
            if timing then waits.timings=waits.timings or {};waits.timings[item]=timing end
        end
    elseif reason~='combat' then
        if pending[bucket] and pending[bucket][item] then pending[bucket][item]=nil;pendingCount=pendingCount-1 end
        cache[item]={record=r or false,why=reason};count=count+1
        if mine==epoch then completed(timing,r)end
        if waits and waits.timings then waits.timings[item]=nil end
    end
    return r,reason,h,at
end
-- Reserve one bucket's complete demand before allowing its decoder handoff.
-- A cancelled Opportunities job releases the lease; shared price work continues.
function P.PrepareBucket(ids,work,owner)
    local first=ids[1];if not first then return end
    -- Establish the generation stamp before attaching a preparation lease.
    record(first,nil,false,true)
    local bucket=first%64;local mine=epoch
    local waits=pending[bucket]or {ids={},cursor=1};pending[bucket]=waits;waits.preparing=owner
    local readerStarted=false
    for _,item in ipairs(ids)do
        if mine~=epoch then return end
        local reserved=waits[item]
        if not reserved then record(item,nil,false,waits.preparing~=nil);reserved=waits[item]end
        if reserved and not readerStarted then
            observed('readerCalls')
            local r,why=B.Record(item,reserved,CURRENT_ONLY)
            if mine~=epoch then return end
            if why=='loading'then readerStarted=true
            elseif why=='combat'then waits.preparing=owner;P.ReleasePreparation(owner);return
            else
                waits.preparing=nil
                -- A resident partition can answer immediately. If it switches
                -- later in the batch, the next cold read takes the lease.
                record(item,nil,true)
            end
        end
        if readerStarted then waits.preparing=owner end
        if work then work()end
    end
    if pending[bucket]==waits then
        waits.preparing=nil
        if not readerStarted then
            local remaining=false;for _,item in ipairs(waits.ids)do if waits[item]then remaining=true;break end end
            if not remaining then pending[bucket]=nil end
        end
    end
end
function P.ReleasePreparation(owner)
    local released=false
    for bucket,waits in pairs(pending)do
        if waits.preparing==owner then
            waits.preparing=nil
            local n=0;for _,item in ipairs(waits.ids)do if waits[item]then n=n+1 end end
            pendingCount=pendingCount-n;pending[bucket]=nil;released=true
        end
    end
    -- Only this unfinished reservation batch is dropped. The shared decoder is
    -- left running; other consumers can retry on the normal coalesced refresh.
    if released then P.Notify()end
end
function P.Ready(item)
    local waits=pending[item%64]
    return not(waits and waits.members and waits.members[item])
end
function P.Settled(item)return cache[item]~=nil and P.Ready(item)end
function P.Source()
    local src=MK.Source();local h,why,at=eligible()
    src.referenceWhy=why
    if not h then return src end
    local localScan=src.market
    local label='Market server · '..h.market.region:upper()..' '..h.market.player_ruleset..' '..h.market.faction..' · estimates; local fallback'
    local generation=P.Generation()
    src.market={pricing=true,localMarket=localScan,key='pricing:'..h.generation_id,items=localScan and localScan.items or {},
        side=h.market.faction,realm=W.Scan.Realm(),at=at,n=h.record_count,complete=false,scope='references',
        generation=generation,label=label}
    src.label,src.generation,src.reference=label,generation,true
    return src
end
-- A local full scan NEWER than the reference's observations is the better picture of the listings now (owner decision R7): it is used, and
-- the reference stays available through P.Reference for usual values.
local function newerLocal(item,opt,at)
    local m=localMarket(opt)
    if not (m and m.scope=='full' and type(m.at)=='number' and type(at)=='number' and m.at>at) then return nil end
    local p=MK.Price(item,options(opt))
    if p then p.source='local';p.fallback='newer';p.basis=p.basis..' A local scan newer than the Market server reference.' end
    return p
end
function P.Price(item,opt)
    local r,why,h,at=record(item,opt)
    local raw=r and r.current.metrics.recent_copper
    if raw and raw~=J.NULL then
        local fresher=newerLocal(item,opt,at)
        if fresher then return fresher end
        return {item=item,price=tonumber(raw),at=at,age=(opt and opt.now or time())-at,
            complete=false,reference=true,source='market_server',generation=h.generation_id,
            notes={'reference'},basis='Market server Recent Price estimate; listing depth and purchase availability are unknown.'}
    end
    local m=localMarket(opt)
    if not m then return nil,why or 'nomarket' end
    local p,reason=MK.Price(item,options(opt))
    if p then p.source='local';p.fallback=why or 'unavailable';p.basis=p.basis..' Local scan fallback.' end
    return p,reason or why
end
-- The reference's figures of an item for planning estimates (no history arrays): { recent, market, historical, min, supply, at, generation }
-- or nil and why. Values are whole copper or nil (never 0 for a missing figure).
function P.Reference(item,opt)
    local r,why,h,at=record(item,opt)
    if not r then return nil,why end
    local m=r.current.metrics
    local function v(k) local x=m[k];if x~=nil and x~=J.NULL then x=tonumber(x);if x and x>=1 then return x end end end
    local supply=r.current.supply
    return {recent=v('recent_copper'),market=v('market_value_copper'),historical=v('historical_value_copper'),min=v('minimum_copper'),
        supply=supply~=nil and supply~=J.NULL and tonumber(supply) or nil,at=at,generation=h and h.generation_id,source='market_server'}
end
function P.Cost(item,qty,opt)
    local p=P.Price(item,opt)
    if p and p.reference then return {state='none',why='reference',qty=qty} end
    if not localMarket(opt) then return {state='none',why='nomarket',qty=qty} end
    return MK.Cost(item,qty,options(opt))
end
function P.Info(opt)
    local m=opt and opt.market
    if not (m and m.pricing) then return MK.Info(opt) end
    return {key=m.key,label=m.label,at=m.at,age=(opt.now or time())-m.at,items=m.n,scope='references',complete=false}
end
function P.Wants(opt)
    return not (opt and opt.localOnly) and (not opt or opt.market==nil or opt.references==true or type(opt.market)=='table' and opt.market.pricing)
end
function P.Facts(item,opt)
    local m=localMarket(opt)
    local base=W.Facts.Of(item,{market=m,variant=opt and opt.variant,now=opt and opt.now,localOnly=true})
    local f={};for k,v in pairs(base) do f[k]=v end
    local r,why,h,at=record(item,opt)
    if m and h and (m.realm~=W.Scan.Realm() or m.side~=h.market.faction) then return f end
    f.referenceWhy=why
    if not r then return f end
    local used=false
    for _,v in ipairs({{'min','minimum_copper'},{'recent','recent_copper'},{'mval','market_value_copper'},{'hist','historical_value_copper'}}) do
        local raw=r.current.metrics[v[2]]
        if raw~=nil and raw~=J.NULL then
            f[v[1]]={value=tonumber(raw),copper=raw,at=at,age=(opt and opt.now or time())-at,
                source='market_server',generation=h.generation_id,quality='limited',notes={'reference'},
                basis='Market server · '..h.pricing_algorithm..' · observed listings; not a sale or live competing offer.'}
            f[v[1]..'Why']=nil;used=true
        end
    end
    if used then
        f.nomarket=nil;f.reference=true;f.source='market_server';f.generation=h.generation_id
        f.key='pricing:'..h.generation_id;f.label='Market server · '..h.market.player_ruleset..' '..h.market.faction
        f.referenceItem=item;f.referenceVariant=r.variant_key;f.localMarket=m
        f.localQuality=f.quality
        f.at,f.age=at,(opt and opt.now or time())-at
        f.quality={level='limited',source='market_server',basis='Market server reference estimates; live competing listings are evaluated separately.',
            reasons={{code='reference',text='Observed server prices do not prove current purchase availability or sale outcomes.'}}}
        if r.current.supply~=J.NULL then
            f.supply={items=r.current.supply,source='market_server',at=at,age=f.age,basis='Observed Market server supply; not current purchasable depth.'}
        end
    end
    return f
end
function P.Chart(f)
    local key=f.generation..':'..f.referenceItem
    if chartCache and chartCache.key==key then return chartCache.series end
    local h,why=B.History(f.referenceItem,f.referenceVariant,'recent',{days=60})
    if not h then
        if why=='loading' then chartPending=f.referenceItem%64+(B.Status().contract_version==3 and 64 or 0) end
        if f.localMarket then
            local localFacts=W.Facts.Of(f.referenceItem,{market=f.localMarket,localOnly=true})
            return W.Facts.Chart(localFacts)
        end
        return nil,why
    end
    local out={points={},groups={},gaps=h.gaps,today=h.to,from=h.from,to=h.to,label=f.label,market=h.generation,basis=h.basis,external=true}
    for _,p in ipairs(h.points) do if p.v then out.points[#out.points+1]={day=p.from,price=p.v,provenance='Market server',at=p.at} end end
    chartCache={key=key,series=out};chartPending=nil
    return out
end
-- Summary owns the short-lived decoder handoff. The completion writer alone
-- bypasses the pending guard; every record yields back to its elapsed-time budget.
-- Queue at most MAX_CACHE identities, not decoded rows or history arrays.
local function finishBucket(bucket,work,failure)
    local waits=pending[bucket]
    local mine=epoch
    local changed=false
    local items={}
    while waits and waits.preparing and not failure do
        if not work or mine~=epoch then return end
        work()
    end
    -- A failed batch is finite. New post-combat reservations belong to a new
    -- bucket queue behind this handoff, never to the rejected cursor.
    if failure then pending[bucket]=nil end
    if waits then
        while waits.cursor<=#waits.ids do
            local item=waits.ids[waits.cursor];waits.cursor=waits.cursor+1
            if mine~=epoch or not W.Active() then return end
            if (failure or pending[bucket]==waits) and waits[item] then
                if failure then
                    waits[item]=nil;pendingCount=pendingCount-1
                    if failure~='combat' and not cache[item] then cache[item]={record=false,why=failure};count=count+1 end
                    if failure~='combat' then completed(waits.timings and waits.timings[item])end
                else
                    local _,why=record(item,nil,true)
                    -- Admission may become stale/unavailable during handoff. It is
                    -- not a permanent miss and must not leave a reservation behind.
                    if pending[bucket]==waits and waits[item] then waits[item]=nil;pendingCount=pendingCount-1 end
                end
                if waits.timings then waits.timings[item]=nil end
                items[item]=true
                changed=true;observed('settled')
            end
            if work then work() end
        end
        if pending[bucket]==waits then pending[bucket]=nil end
    end
    if changed then
        revision=revision+1
        if W.Session and W.Session.ItemsChanged then W.Session.ItemsChanged(items)end
        P.Notify()
    end
    if chartPending==bucket then chartPending=nil;chartRevision=chartRevision+1;P.Notify(0) end
end
function P.NeedsHandoff(bucket) return pending[bucket]~=nil or chartPending==bucket end
function P.Decoded(bucket,work) return finishBucket(bucket,work) end
function P.Rejected(bucket,why,work) return finishBucket(bucket,work,why) end
function P.PendingCount() return pendingCount end
function P.CacheSize() return count end
function P.Changed()
    if W.Facts then W.Facts.CacheClear() end
    if W.Strategy then W.Strategy.Bump() end
    if W.UI and W.UI.Redraw then W.UI.Redraw() end
    if W.AuctionUI and W.AuctionUI.Schedule then W.AuctionUI.Schedule() end
    if W.WorthTip and W.WorthTip.Refresh then W.WorthTip.Refresh() end
    if W.Junk then W.Junk.Request() end
end
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge('workshop.pricingPending',{label='Pending Market price identities',kind='cache',group='workshop',unit='count',read=P.PendingCount})
    R.Perf.Gauge('workshop.pricingReferences',{label='Cached Market price references',kind='cache',group='workshop',unit='count',read=P.CacheSize})
end
