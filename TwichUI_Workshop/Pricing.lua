-- Workshop references over the Companion-selected market, with independent local
-- scans. Native auction listings/actions continue to use Market.Source directly.
local R,W=TwichUI,TwichUI.Workshop
local MK,PR,B,J=W.Market,W.Prices,W.Bridge,W.BridgeCodec
local P={MAX_CACHE=8192,MAX_AGE=86400}
W.Pricing=P
setmetatable(P,{__index=MK})
local cache,count,stamp={},0,nil
local header,headerGeneration
local chartCache,chartPending
local pending,pendingCount={},0
local warmNotification=false
local function dataStamp()
    local status=B.Status()
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
local function eligible(now)
    if not (W.Active() and B and B.Status().ready and B.Status().summary) then return nil,'unavailable' end
    local generation=B.Status().generation
    if headerGeneration~=generation then header,headerGeneration=B.Manifest(),generation end
    local h=header
    if not h or h.synthetic or not h.market.mapping_verified or h.pricing_algorithm~='twichui-pricing-v1' then return nil,'unsupported' end
    local _,at=W.BridgeValidate.Time(h.source_observation.observed_at)
    now=now or time()
    if not at or now<at or now-at>P.MAX_AGE then return nil,'stale' end
    local side
    if W.Scan.AuctionOpen() then local _,_,s=W.Scan.Market();side=s
    elseif UnitFactionGroup then side=W.Plain(UnitFactionGroup('player')) end
    if side~=h.market.faction then return nil,'market_mismatch' end
    return h,nil,at
end
-- Why the Market server summary isn't being used, in a sentence (P.Source's referenceWhy)
P.WHY={
    unavailable='No Market server summary is loaded (Companion).',
    unsupported="The loaded Market summary's pricing format isn't supported by this TwichUI.",
    stale='The Market summary is more than a day old.',
    market_mismatch="The Companion market is for another faction than this auction house or character.",
}
function P.WhyText(why) return why and P.WHY[why] or nil end
function P.Generation()
    local s=B.Status()
    return table.concat({s.generation or '',s.checked_parts or 0,s.failures or 0,tostring(s.ready)},':')
end
function P.BaseKey(item)
    item=W.Int(item,1,W.MAX_ID)
    if item then return J.SHA('{"id":'..string.format('%.0f',item)..'}') end
end
local function record(item,opt)
    if opt and opt.variant then return nil,'variant' end
    local h,why,at=eligible(opt and opt.now)
    if not h then return nil,why end
    item=W.Int(item,1,W.MAX_ID);if not item then return nil,'baditem' end
    local current=dataStamp()
    if stamp~=current then cache,count,stamp={},0,current;pending,pendingCount={},0 end
    local entry=cache[item]
    if entry then return entry.record or nil,entry.why,h,at end
    local bucket=item%64
    local reserved=pending[bucket] and pending[bucket][item]
    if not reserved and count+pendingCount>=P.MAX_CACHE then return nil,'lookup_limit',h,at end
    local r,reason=B.Record(item,P.BaseKey(item))
    -- Do not keep daily arrays or mutable decoder rows in the price cache.
    if r then r={current=J.Copy(r.current),variant_key=r.variant_key} end
    if reason=='loading' then
        local waits=pending[bucket]
        if not waits then waits={};pending[bucket]=waits end
        if not waits[item] and pendingCount<P.MAX_CACHE then waits[item]=true;pendingCount=pendingCount+1 end
    elseif reason~='combat' then
        if pending[bucket] and pending[bucket][item] then pending[bucket][item]=nil;pendingCount=pendingCount-1 end
        if count>=P.MAX_CACHE then cache,count={},0 end
        cache[item]={record=r or false,why=reason};count=count+1
    end
    return r,reason,h,at
end
function P.Source()
    local src=MK.Source();local h,why,at=eligible()
    src.referenceWhy=why
    if not h then return src end
    local localScan=src.market
    local label='Market server · '..h.market.region:upper()..' '..h.market.player_ruleset..' '..h.market.faction..' · estimates; local fallback'
    src.market={pricing=true,localMarket=localScan,key='pricing:'..h.generation_id,items=localScan and localScan.items or {},
        side=h.market.faction,realm=W.Scan.Realm(),at=at,n=h.record_count,complete=false,scope='references',
        generation=P.Generation(),label=label}
    src.label,src.generation,src.reference=label,P.Generation(),true
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
        f.referenceItem=item;f.referenceVariant=P.BaseKey(item);f.localMarket=m
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
        if why=='loading' then chartPending=f.referenceItem%64 end
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
local function notifyWarm()
    if warmNotification then return end
    warmNotification=true
    C_Timer.After(0.1,function()warmNotification=false;if W.Active() then P.Changed() end end)
end
function P.Decoded(bucket)
    -- Fill requested compact records while this checked partition is decoded.
    -- A new partition never discards prices already resolved from this generation.
    local waits=pending[bucket]
    if waits then
        local ids={};for item in pairs(waits) do ids[#ids+1]=item end
        table.sort(ids)
        local cursor,generation=1,dataStamp()
        local function warm()
            if not W.Active() or dataStamp()~=generation then return end
            local n,resolved=0,false
            while cursor<=#ids and n<16 do
                local item=ids[cursor];cursor=cursor+1;n=n+1
                if pending[bucket] and pending[bucket][item] then
                    local _,why=record(item)
                    if why~='loading' and why~='combat' then resolved=true end
                end
            end
            if resolved then notifyWarm() end
            if cursor<=#ids then C_Timer.After(0,warm) end
        end
        -- The first slice runs before another partition can evict this decoder.
        warm()
    end
    if chartPending==bucket then
        chartPending=nil
        C_Timer.After(0,function()if W.Active() then
            if W.UI and W.UI.Redraw then W.UI.Redraw() end
            if W.AuctionUI and W.AuctionUI.Schedule then W.AuctionUI.Schedule() end
        end end)
    end
end
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
    R.Perf.Gauge('workshop.pricingReferences',{label='Cached Market price references',kind='cache',group='workshop',unit='count',read=P.CacheSize})
end
