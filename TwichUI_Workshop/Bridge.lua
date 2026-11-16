-- Opt-in Market bridge. No local scan/history writes, scans, transactions or startup loading.
local R,W=TwichUI,TwichUI.Workshop
local J,S=W.BridgeCodec,W.BridgeValidate
local B={ADDON='TwichUI_MarketData',CACHE_MAX=24,SLICE_MS=3,RESUMES=512}
W.Bridge=B
-- Delivery policy; schema-3's separate contract ceiling is 32 MiB / 1,000 records.
B.SCOPED_BYTES=2*1024*1024
local active,job,token=nil,nil,0
local rejected
local cache,order={},{}
local state,lastError='absent',nil
local stats={validation_ms=0,largest_slice_ms=0,slices=0,resumes=0,largest_resumes=0,record_ms=0,record_calls=0,history_ms=0,history_calls=0,failures=0}
local function clock() if GetTimePreciseSec then return GetTimePreciseSec()*1000 elseif debugprofilestop then return debugprofilestop() end;return 0 end
local function measured(id,fn,...) if R.Perf and R.Perf.Call then return R.Perf.Call(id,fn,...) end;return fn(...) end
local function requireData(ok) if not ok then error('invalid bridge generation',0) end end
local function shallow(t) local out={};for k,v in pairs(t) do out[k]=v end;return out end
local function validate(raw,expected)
    local function tick() coroutine.yield() end
    requireData(type(raw)=='table' and getmetatable(raw)==nil and raw.transport_version==1 and type(raw.manifest)=='string' and #raw.manifest<=256*1024
        and type(raw.records)=='table' and getmetatable(raw.records)==nil and type(raw.receipt)=='string' and #raw.receipt<=4096)
    local n=0;for k in pairs(raw) do requireData(k=='transport_version' or k=='manifest' or k=='records' or k=='receipt');n=n+1 end;requireData(n==4)
    local h=J.Parse(raw.manifest,tick,256*1024);requireData(J.Encode(h,tick)==raw.manifest)
    local ctx=S.Header(h,tick);local count=h.record_count
    if expected then
        if expected.market then requireData(J.Encode(expected.market,tick)==J.Encode(h.market,tick)) end
        if expected.request_digest then requireData(h.schema_version==3 and expected.request_digest==h.scope.request_digest) end
    end
    if h.schema_version==3 and #raw.manifest+h.integrity.records_bytes+11>B.SCOPED_BYTES then error('bridge policy canonical_bytes',0) end
    local inputBytes=#raw.manifest+13
    n=0;for i,v in pairs(raw.records) do
        requireData(W.Int(i,1,count) and type(v)=='string' and #v<=65536)
        inputBytes=inputBytes+#v+(n>0 and 1 or 0);n=n+1;requireData(n<=150000)
        if h.schema_version==3 and inputBytes>B.SCOPED_BYTES then error('bridge policy canonical_bytes',0) end
        requireData(inputBytes<=32*1024*1024);tick()
    end;requireData(n==count)
    local receipt=J.Parse(raw.receipt,tick);requireData(getmetatable(receipt)==J.OBJECT and receipt.schema_version==1 and receipt.generation_id==h.generation_id and type(receipt.desktop_build)=='string' and #receipt.desktop_build>=1 and #receipt.desktop_build<=80 and S.Time(receipt.completed_at))
    if h.schema_version==3 then requireData(S.Time(receipt.completed_at)>=S.Time(h.generated_at)) end
    n=0;for k in pairs(receipt) do requireData(k=='schema_version' or k=='generation_id' or k=='desktop_build' or k=='completed_at');n=n+1 end;requireData(n==4)
    local keys={};for k in pairs(h) do if k~='generation_id' and k~='integrity' then keys[#keys+1]=k end end;keys[#keys+1]='records';table.sort(keys)
    local before,after={'{'},{ };local seen=false
    for i,k in ipairs(keys) do
        local prefix=(i>1 and ',' or '')..J.Encode(k)..':'
        if k=='records' then before[#before+1]=prefix..'[';seen=true
        elseif not seen then before[#before+1]=prefix..J.Encode(h[k],tick)
        else after[#after+1]=prefix..J.Encode(h[k],tick) end
    end
    after[#after+1]='}'
    local bodyHash=J.Hash(tick):Update(table.concat(before));local recordsHash=J.Hash(tick):Update('[')
    local out={header=h,manifest=raw.manifest,context=ctx,records={},index={},variantKeys={},variantCounts={},itemIds={},receipt=receipt,raw=raw,bytes=#raw.manifest+13}
    local lastItem,lastVariant=0,'';local recordBytes=2
    for i=1,count do
        local text=raw.records[i];requireData(type(text)=='string')
        local r=J.Parse(text,tick);local _,canonical=S.Record(ctx,r,tick);requireData(canonical==text)
        requireData(r.item_id>lastItem or r.item_id==lastItem and r.variant_key>lastVariant)
        -- The contract already requires item/variant order. Retain one range
        -- per item and one flat key array instead of two tables per item.
        if not out.index[r.item_id] then out.index[r.item_id]=i;out.variantCounts[r.item_id]=0;out.itemIds[#out.itemIds+1]=r.item_id end
        out.variantKeys[i]=r.variant_key
        out.variantCounts[r.item_id]=out.variantCounts[r.item_id]+1
        lastItem,lastVariant=r.item_id,r.variant_key;out.records[i]=text
        local piece=(i>1 and ',' or '')..text;recordBytes=recordBytes+#piece;requireData(#raw.manifest+recordBytes+11<=32*1024*1024)
        recordsHash:Update(piece);bodyHash:Update(piece);tick()
    end
    recordsHash:Update(']');bodyHash:Update(']'..table.concat(after))
    requireData(recordBytes==h.integrity.records_bytes and recordsHash:Finish()==h.integrity.records_sha256 and bodyHash:Finish()==h.generation_id)
    out.bytes=#raw.manifest+recordBytes+11;return out
end
local schedule
function B.Begin(raw,automatic,expected)
    rejected=nil;stats.refusal=nil
    expected=expected and J.Copy(expected)
    token=token+1;job={co=coroutine.create(function() return validate(raw,expected) end),token=token,automatic=automatic,raw=raw}
    state,lastError='loading',nil;return false,'loading'
end
local function step(ms)
    local current=job;if not current then return active~=nil,lastError or state end
    local start=clock();local resumes=0;local complete=false;local failure=false;local failureReason
    -- Reserve headroom for a final bounded unit and incidental interpreter GC.
    -- Without a clock, retain the original conservative deterministic work cap.
    local budget=math.max(0.5,(W.Int(ms,1,20) or B.SLICE_MS)-1)
    local limit=(GetTimePreciseSec or debugprofilestop) and B.RESUMES or 32
    repeat
        local ok,value=coroutine.resume(current.co);resumes=resumes+1
        if not ok then failure=true;failureReason=value;break end
        if coroutine.status(current.co)=='dead' then
            active=value;cache,order={},{};job=nil;state,lastError='ready',nil;complete=true;break
        end
    until resumes>=limit or clock()-start>=budget
    stats.resumes=stats.resumes+resumes;stats.largest_resumes=math.max(stats.largest_resumes,resumes)
    local elapsed=math.max(0,clock()-start);stats.validation_ms=stats.validation_ms+elapsed;stats.largest_slice_ms=math.max(stats.largest_slice_ms,elapsed);stats.slices=stats.slices+1
    if failure then stats.refusal=failureReason=='bridge policy canonical_bytes' and 'canonical_bytes' or nil;rejected=current.raw;job=nil;state=active and 'ready' or 'invalid';lastError='invalid';stats.failures=stats.failures+1;return false,'invalid' end
    if complete then return true end;return false,'loading'
end
function B.Step(ms) return measured('workshop.bridgeValidate',step,ms) end
schedule=function()
    local current=job;if not current or current.scheduled or not(C_Timer and C_Timer.After) then return end
    current.scheduled=true
    C_Timer.After(0,function()
        if job~=current or current.token~=token then return end
        current.scheduled=false;B.Step();if job==current then schedule() end
    end)
end
function B.Load()
    if not W.Active() then return false,'disabled' end
    if job then schedule();return false,'loading' end
    local raw=TwichUIMarketData
    if active and active.raw==raw and type(raw)=='table' and raw.manifest==active.manifest then return true end
    if rejected~=nil and raw==rejected then return false,'invalid' end
    if InCombatLockdown and InCombatLockdown() then return false,'combat' end
    if raw==nil then
        if not(C_AddOns and C_AddOns.LoadAddOn) then state='absent';lastError='missing';return false,'missing' end
        local function load() return pcall(C_AddOns.LoadAddOn,B.ADDON) end
        local ok,loaded=measured('workshop.bridgeLoad',load)
        if not ok or not loaded then state=active and 'ready' or 'absent';lastError='missing';return false,'missing' end
        raw=TwichUIMarketData
    end
    B.Begin(raw,true);schedule();return false,'loading'
end
function B.Cancel()
    token=token+1;job=nil
    state=active and 'ready' or 'absent'
end
function B.Status()
    local s=shallow(stats);s.state=state;s.error=lastError;s.loading=job~=nil;s.ready=active~=nil;s.generation=active and active.header.generation_id
    s.records=active and active.header.record_count or 0;s.items=active and #active.itemIds or 0;s.bytes=active and active.bytes or 0;s.cache_entries=#order;s.schema=active and active.header.schema_version;s.scoped=active and active.header.schema_version==3 or false
    return s
end
function B.Market() return active and J.Copy(active.header.market) or nil,lastError or state end
function B.Manifest() return active and J.Copy(active.header) or nil,lastError or state end
function B.Receipt() return active and J.Copy(active.receipt) or nil,lastError or state end
function B.Variants(item,limit)
    item=W.Int(item,1,W.MAX_ID);limit=W.Int(limit or 20,1,100)
    if not item or not limit then return nil,'identity' end
    if not active then return nil,lastError or state end
    local first,count=active.index[item],active.variantCounts[item] or 0
    local out={};for i=1,math.min(limit,count) do out[i]=active.variantKeys[first+i-1] end
    return out,count>#out
end
function B.EachItem(add,tick,capped)
    if not active then return false,'unavailable' end
    for _,item in ipairs(active.itemIds) do add(item);if tick then tick() end;if capped and capped() then break end end
    return true
end
local function record(item,variant)
    if not active then return nil,lastError or state end
    if not W.Int(item,1,W.MAX_ID) or type(variant)~='string' or #variant~=64 or variant:find('[^0-9a-f]') then return nil,'variant_required' end
    local first=active.index[item];if not first then return nil,active.header.schema_version==3 and 'outside_scope' or 'not_observed' end
    local lo,hi,position=first,first+active.variantCounts[item]-1
    while lo<=hi do
        local mid=math.floor((lo+hi)/2);local key=active.variantKeys[mid]
        if key==variant then position=mid;break
        elseif key<variant then lo=mid+1 else hi=mid-1 end
    end
    if not position then return nil,active.header.schema_version==3 and 'outside_scope' or 'not_observed' end
    if cache[position] then return cache[position] end
    local r=J.Parse(active.records[position]);cache[position]=r;order[#order+1]=position
    if #order>B.CACHE_MAX then cache[table.remove(order,1)]=nil end
    return r
end
function B.Record(item,variant)
    local function run() local start=clock();local r,why=record(item,variant);stats.record_calls=stats.record_calls+1;stats.record_ms=stats.record_ms+math.max(0,clock()-start);return r and J.Copy(r),why end
    return measured('workshop.bridgeRecord',run)
end
-- Scope membership and observation availability are independent of any price.
-- A trusted caller may pin a market/request at Begin; no desktop credentials enter Lua.
function B.Capabilities() return {contract_version=1,transport_version=1,schemas={1,2,3},features={exact_copper=true,current_summaries=true,daily_history=true,scoped_selection=true},summary_index=false} end
function B.Scope()
    if not active then return nil,lastError or state end
    local h=active.header;local s=h.scope
    return {type=s and s.type or 'full_market',scope_complete=s and s.scope_complete or h.coverage.generation_complete,
        whole_market_complete=not s and h.coverage.generation_complete or false,selection_id=s and s.selection_id,
        request_digest=s and s.request_digest,requested_count=s and s.requested_count or h.record_count,
        history_from_day=h.coverage.history_from_day,history_through_day=h.coverage.history_through_day,
        watermark_observation_id=h.watermark_observation_id,generation=h.generation_id}
end
function B.Availability(item,variant,day)
    local r,why=record(item,variant)
    local out={state=why or 'unknown_coverage',included=r~=nil,scoped=active and active.header.schema_version==3 or false}
    if not active then out.state=lastError=='invalid' and 'invalid_generation' or 'unavailable';return out end
    if day~=nil then
        local n=S.Date(day);out.date_in_scope=n~=nil and n>=active.context.from and n<=active.context.to
        if not out.date_in_scope then out.state=n and 'outside_scope' or 'unsupported';out.why='history_window';return out end
    end
    if not r then return out end
    local x=r.current
    if day then
        x=nil
        for _,d in ipairs(r.daily) do if active.header.observations[d.observation_ref+1].utc_day==day then x=d;break end end
        if not x then out.state='unknown_coverage';local c=active.context.calendar and active.context.calendar[S.Date(day)];out.coverage=c and c.state or 'no_eligible_close';return out end
    end
    if day then out.complete=active.header.observations[x.observation_ref+1].scope_complete else out.complete=x.complete end
    out.observation_ref=x.observation_ref
    local price=x.metrics and x.metrics.recent_copper or x.recent_copper
    if x.state=='absent' then out.state='observed_absent'
    elseif x.state=='unknown' then out.state='unknown_coverage'
    elseif x.arithmetic_status=='unsupported' then out.state='unsupported'
    elseif price~=J.NULL and price~=nil then
        out.state=S.Money(price,true) and #price<=11 and (#price<11 or price<='99999999999') and 'priced' or 'unsupported'
    elseif x.priced_supply==0 then out.state='supply_only'
    else out.state='unsupported' end
    return out
end
local METRIC={minimum='minimum_copper',recent='recent_copper',market='market_value_copper',historical='historical_value_copper',mean='quantity_weighted_ask_copper'}
function B.Value(item,variant,metric)
    local r,why=record(item,variant);if not r then return nil,why end
    local field=METRIC[metric or 'recent'];if not field then return nil,'metric' end
    local v=r.current.metrics[field]
    if v==J.NULL then return nil,r.current.arithmetic_status=='unsupported' and 'unsupported' or 'unavailable' end
    if not S.Money(v,true) or #v>11 or (#v==11 and v>'99999999999') then return nil,'unsupported' end
    return {copper=v,value=tonumber(v),algorithm=active.header.pricing_algorithm,basis=r.current.metric_basis,
        generation=active.header.generation_id,source='market_server',observation=J.Copy(active.header.observations[r.current.observation_ref+1]),quality='limited'}
end
function B.History(item,variant,metric,opt)
    local function run()
        local start=clock();local r,why=record(item,variant);if not r then return nil,why end
        metric=metric or 'recent';if metric~='minimum' and metric~='recent' and metric~='supply' then return nil,'metric' end
        local days=W.Int(opt and opt.days or 60,1,60);if not days then return nil,'window' end
        local ctx=active.context;local from=math.max(ctx.from,ctx.today-days+1)
        if from>ctx.to and active.header.schema_version==3 then return nil,'outside_scope' end
        local out={basis=active.header.history_basis,algorithm=active.header.pricing_algorithm,source='market_server',generation=active.header.generation_id,
            scope=B.Scope(),market=J.Copy(active.header.market),coverage=J.Copy(active.header.coverage),metric=metric,points={},gaps={},from=from,to=ctx.to,observed_days=0,synthetic=active.header.synthetic}
        local present={}
        for _,d in ipairs(r.daily) do
            local o=ctx.observations[d.observation_ref+1]
            if o.day>=from and o.day<=ctx.to then
                present[o.day]=true;out.observed_days=out.observed_days+1
                local raw=metric=='supply' and d.supply or d[metric..'_copper'];local value,reason
                if raw==J.NULL then reason='unavailable'
                elseif metric=='supply' then value=raw
                elseif S.Money(raw,true) and #raw<=11 and (#raw<11 or raw<='99999999999') then value=tonumber(raw)
                else reason='unsupported' end
                if value==nil then out.gaps[#out.gaps+1]={from=o.day,to=o.day,why=d.state=='absent' and 'observed_absent' or d.state=='unknown' and 'unknown_variant_state' or reason or 'no_supported_buyout'} end
                out.points[#out.points+1]={kind='day',from=o.day,to=o.day,v=value,copper=metric~='supply' and raw~=J.NULL and raw or nil,
                    state=d.state,reason=reason,at=o.source.observed_at,observation_id=o.source.observation_id,
                    provenance='Market server · '..active.header.pricing_algorithm,synthetic=o.source.synthetic,partial=not o.source.scope_complete}
            end
        end
        for day=from,ctx.to do if not present[day] then out.gaps[#out.gaps+1]={from=day,to=day,why=not active.header.coverage.history_complete and 'export_history_incomplete' or ctx.observedDays[day] and 'only_incomplete_server_observations' or 'no_server_observation'} end end
        stats.history_calls=stats.history_calls+1;stats.history_ms=stats.history_ms+math.max(0,clock()-start);return out
    end
    return measured('workshop.bridgeHistory',run)
end
-- Read-only gauges do not load the bridge or build an index.
if R.Perf and R.Perf.Gauge then
    R.Perf.Gauge('workshop.bridgeRecords',{label='Validated external market records',kind='state',group='workshop',unit='count',read=function() return active and active.header.record_count or 0 end})
    R.Perf.Gauge('workshop.bridgeBytes',{label='Retained external payload bytes',kind='cache',group='workshop',unit='bytes',read=function() return active and active.bytes or 0 end})
    R.Perf.Gauge('workshop.bridgeCache',{label='Decoded external records (bounded)',kind='cache',group='workshop',unit='count',read=function() return #order end})
end
