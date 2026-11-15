-- Explicit display-only external source. Never participates in local pricing/advice.
local R,W=TwichUI,TwichUI.Workshop
local B,J=W.Bridge,W.BridgeCodec
local M={KEY='server',METRICS={{'recent','Recent listing price'},{'minimum','Minimum listing price'},{'supply','Observed supply'}}}
W.ServerMarket=M
function M.Context()
    local m=B.Market();local status=B.Status()
    local label=m and ('Market server · '..m.region:upper()..' · '..(m.player_ruleset~=J.NULL and m.player_ruleset or 'ruleset unverified')..' · house '..m.house_id) or 'Market server · '..status.state
    return {external=true,key='server:'..(status.generation or status.state),label=label,generation=status.generation,identity=m}
end
function M.Catalog(opt)
    if not B.Status().ready then return {rows={},index={},seen={},unavailable=B.Status().loading and 'loading_bridge' or 'bridge_unavailable',Step=function()return true end} end
    opt=opt or {}
    return W.AuctionBrowseData.Job({sources={},market=nil,index=true,item=opt.item,query=opt.query,category=opt.category,quality=opt.quality,
        enumerate=function(add,tick,job)
            if opt.scope=='tracked' then
                for id,on in pairs(W.AdvisorData.Tracked()) do if on then local variants=B.Variants(id,1);if variants and #variants>0 then add(id) end;tick();if job.capped then break end end end
            elseif opt.scope=='bags' then
                local api=C_Container
                if not(api and api.GetContainerNumSlots and api.GetContainerItemInfo) then job.unavailable='Bag information unavailable';return end
                for bag=0,(NUM_BAG_SLOTS or 4) do for slot=1,math.min(api.GetContainerNumSlots(bag) or 0,200) do
                    local entry=api.GetContainerItemInfo(bag,slot);local id=type(entry)=='table' and W.Int(W.Plain(entry.itemID),1,W.MAX_ID)
                    if id then local variants=B.Variants(id,1);if variants and #variants>0 then add(id) end end
                    tick();if job.capped then return end
                end end
            else B.EachItem(add,tick,function()return job.capped end) end
        end})
end
function M.Variants(item)
    local out={{'','Choose exact server variant'}};local variants,cut=B.Variants(item or 0,100)
    for _,key in ipairs(variants or {}) do out[#out+1]={key,'Variant '..key:sub(1,16)} end
    if cut then out[#out+1]={'','More variants omitted from this selector'} end
    return out
end
function M.Project(item,variant,metric,days)
    local context=M.Context();local header=B.Manifest();local r,why=B.Record(item,variant)
    local out={source='market_server',market=context,label=context.label,variant=variant,metric=metric or 'recent',record=r,why=why,header=header}
    if not r then return out end
    local history,historyWhy=B.History(item,variant,out.metric,{days=math.min(days or 14,60)})
    out.history,out.historyWhy=history,historyWhy
    if history then
        local series={points={},groups={},gaps=history.gaps,from=history.from,to=history.to,today=history.to,
            basis=history.basis,metric=out.metric,observations=0,observed_days=history.observed_days,external=true}
        for _,p in ipairs(history.points) do if p.v~=nil then series.points[#series.points+1]={day=p.from,price=p.v,kind='day',provenance=p.provenance,partial=p.partial,at=p.at,copper=p.copper,state=p.state} end end
        out.series=series
    end
    local f={external=true,item=item,compWhy='external_source',minWhy='unavailable',recentWhy='unavailable',mvalWhy='unavailable',histWhy='unavailable'}
    for _,entry in ipairs({{'min','minimum'},{'recent','recent'},{'mval','market'},{'hist','historical'}}) do
        local v,reason=B.Value(item,variant,entry[2]);f[entry[1]]=v;f[entry[1]..'Why']=reason
        if v then v.basis='Market server · '..header.pricing_algorithm..' · '..header.history_basis
            v.notes=r.current.coverage.priced_days_60<60 and {'sparse'} or {} end
    end
    if r.current.supply~=J.NULL then f.supply={items=r.current.supply,listings=r.current.listing_count,complete=r.current.complete,basis='Observed server listings, not demand or current local competition.'} end
    f.histDetail={n=r.current.coverage.priced_days_60};if not f.hist and header.pricing_algorithm=='twichui-pricing-v1' and r.current.coverage.priced_days_60<3 then f.histWhy='insufficient' end
    f.quality={level='limited',basis='Separate external listing evidence; local competition and selling safeguards are unchanged.',reasons={}}
    if header.synthetic then f.quality.reasons[#f.quality.reasons+1]={text='Synthetic fixture.'} end
    if not header.market.mapping_verified then f.quality.reasons[#f.quality.reasons+1]={text='Player-facing market mapping is unverified.'} end
    out.facts=f;return out
end
function M.Rows(x,money)
    if not x.facts then return {} end
    local rows=W.Facts.Rows(x.facts,money)
    for _,row in ipairs(rows) do
        if row.id=='comp' then row.value='Local competition only';row.tip='Server observations do not establish live local competition.' end
        if x.header.pricing_algorithm=='asking-v1-provisional' then
            if row.id=='recent' then row.label='Recent asking mean · provisional'
            elseif row.id=='market' then row.label='Market reference · legacy mean'
            elseif row.id=='hist' then row.label='Historical reference · legacy mean' end
        end
    end
    return rows
end
function M.Open(item,variant)
    if not W.AuctionUI or not W.Int(item,1,W.MAX_ID) then return false end
    if not W.AuctionUI.Show('market') then return false end
    return W.AuctionUI.OpenMarket(item,{market=M.KEY,serverVariant=variant})
end
