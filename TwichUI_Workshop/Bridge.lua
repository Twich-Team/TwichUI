-- Opt-in Market bridge. No local scan/history writes, scans, transactions or startup loading.
local R,W=TwichUI,TwichUI.Workshop
local J,S=W.BridgeCodec,W.BridgeValidate
local B={ADDON='TwichUI_MarketData',CACHE_MAX=24,SLICE_MS=3,RESUMES=512}
W.Bridge=B
-- Delivery policy; schema-3's separate contract ceiling is 32 MiB / 1,000 records.
B.SCOPED_BYTES=2*1024*1024
-- Contract profiles, not marketing release numbers. Receipt/build data is outside
-- the immutable generation hash; no new transport fields or executable input.
local READER_CONTRACT=3
local SCHEMAS={[1]=1,[2]=2,[3]=3}
local compatibilityAttempt
local MESSAGES={newer_addon='This market data needs a newer TwichUI addon. Update TwichUI to import it.',
    older_companion='This market data uses an older contract. Update TwichUI Market Companion and export it again.',
    invalid_contract='The market data contract could not be verified. Re-export it from the Companion.'}
function B.CheckCompatibility(transport,contract,schema,receiptSchema)
    receiptSchema=receiptSchema==nil and 1 or receiptSchema
    local out={reader_contract_version=READER_CONTRACT,transport_version=transport,contract_version=contract,schema_version=schema,receipt_schema_version=receiptSchema,compatible=false}
    if not W.Int(receiptSchema,0,2147483647) or not W.Int(transport,0,2147483647) or not W.Int(contract,0,2147483647) or not W.Int(schema,0,2147483647) then
        out.reason='invalid_contract'
    else
        local old=transport<1 or contract<1 or schema<1 or receiptSchema<1
        local newer=receiptSchema>1 or transport>1 or contract>1 or not SCHEMAS[schema] and schema>0
        out.minimum_reader_version=SCHEMAS[schema]
        if old and newer then out.reason='invalid_contract'
        elseif old then out.reason='older_companion'
        elseif newer then out.reason='newer_addon'
        else out.compatible=true end
    end
    out.message=out.reason and MESSAGES[out.reason] or nil
    return out
end
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
    requireData(type(raw)=='table' and getmetatable(raw)==nil and type(raw.transport_version)=='number' and type(raw.manifest)=='string' and #raw.manifest<=256*1024
        and type(raw.records)=='table' and getmetatable(raw.records)==nil and type(raw.receipt)=='string' and #raw.receipt<=4096)
    local n=0;for k in pairs(raw) do requireData(k=='transport_version' or k=='manifest' or k=='records' or k=='receipt');n=n+1 end;requireData(n==4)
    local h=J.Parse(raw.manifest,tick,256*1024);requireData(J.Encode(h,tick)==raw.manifest)
    compatibilityAttempt=B.CheckCompatibility(raw.transport_version,h.contract_version,h.schema_version)
    if not compatibilityAttempt.compatible then error('bridge compatibility '..compatibilityAttempt.reason,0) end
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
    local receipt=J.Parse(raw.receipt,tick);requireData(getmetatable(receipt)==J.OBJECT)
    compatibilityAttempt=B.CheckCompatibility(raw.transport_version,h.contract_version,h.schema_version,receipt.schema_version)
    if not compatibilityAttempt.compatible then error('bridge compatibility '..compatibilityAttempt.reason,0) end
    requireData(receipt.generation_id==h.generation_id and type(receipt.desktop_build)=='string' and #receipt.desktop_build>=1 and #receipt.desktop_build<=80 and S.Time(receipt.completed_at))
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
    rejected=nil;stats.refusal=nil;stats.unsupported=nil;compatibilityAttempt=nil
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
    if failure then stats.refusal=failureReason=='bridge policy canonical_bytes' and 'canonical_bytes' or nil;stats.unsupported=compatibilityAttempt and not compatibilityAttempt.compatible and compatibilityAttempt.reason=='newer_addon' or false;rejected=current.raw;job=nil;state=active and 'ready' or 'invalid';lastError='invalid';stats.failures=stats.failures+1;return false,'invalid' end
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
    s.compatibility_message=compatibilityAttempt and not compatibilityAttempt.compatible and compatibilityAttempt.message or nil
    s.compatibility_reason=compatibilityAttempt and not compatibilityAttempt.compatible and compatibilityAttempt.reason or nil
    s.desktop_build=active and active.receipt.desktop_build or nil
    s.transport_version=active and active.header.transport_version or nil
    s.contract_version=active and active.header.contract_version or nil
    s.reader_contract_version=READER_CONTRACT
    s.minimum_reader_version=active and SCHEMAS[active.header.schema_version] or nil
    return s
end
function B.Compatibility()
    if not active then return nil,lastError or state end
    local out=B.CheckCompatibility(active.header.transport_version,active.header.contract_version,active.header.schema_version)
    out.desktop_build=active.receipt.desktop_build
    return out
end
function B.CompatibilityText(diagnostics)
    local out=B.Compatibility();if not out then return nil end
    local build=out.desktop_build:gsub('|','||'):gsub('[%c]',' ')
    local summary='Market data from Companion '..build
    if not diagnostics then return summary end
    return summary..'\ntransport '..out.transport_version..' · contract '..out.contract_version..' · schema '..out.schema_version..
        ' · receipt '..out.receipt_schema_version..'\nreader contract '..out.minimum_reader_version..' required · installed '..out.reader_contract_version
end
function B.Market() return active and J.Copy(active.header.market) or nil,lastError or state end
function B.Manifest() return active and J.Copy(active.header) or nil,lastError or state end
function B.Receipt() return active and J.Copy(active.receipt) or nil,lastError or state end
-- Read only the validated in-memory generation. Files on disk and desktop writes
-- are not observable here; the receipt describes generation preparation only.
function B.Freshness(now)
    local s=B.Status()
    local out={state='unavailable',text='Market data unavailable',tone='quiet',tip={}}
    if not active then
        if s.unsupported then out.state='unsupported';out.text='Unsupported Market data'
        elseif s.loading then out.text='Validating Market data' end
        out.tip[1]='No validated external generation is loaded. Local scans remain available.'
    else
        local h=active.header
        local o=h.observations[h.current_observation_ref+1]
        local _,stamp=S.Time(o and o.observed_at)
        now=now or (time and time())
        local age=stamp and now and now-stamp
        out.generation=h.generation_id;out.observed_at=o and o.observed_at;out.age=age
        out.state=age and age>=0 and (age<=7200 and 'ready' or age<=86400 and 'aging' or 'stale') or 'unknown'
        out.text=out.state=='ready' and 'Market data ready' or out.state=='aging' and 'Market data aging' or out.state=='stale' and 'Market data stale' or 'Market data age unknown'
        out.tone=out.state=='ready' and 'good' or 'warn'
        out.tip={
            'Loaded generation: '..h.generation_id,
            'Source: Market server · '..h.pricing_algorithm..(h.synthetic and ' · synthetic test data' or ''),
            'Market: '..h.market.region:upper()..' · '..(h.market.player_ruleset~=J.NULL and h.market.player_ruleset or 'unverified ruleset')..' · house '..h.market.house_id,
            'Last loaded observation: '..(out.observed_at or 'unknown')..' UTC',
            'Loaded observation age: '..(age and age>=0 and math.floor(age/60)..' minutes' or 'unknown; check client clock'),
            'Validation: schema '..h.schema_version..' · integrity verified'..(s.error and ' · replacement rejected; last good retained' or ''),
            h.schema_version==3 and ('Selected scope: '..h.scope.requested_count..' exact variants · complete selected history; not whole-market coverage') or ('Legacy coverage: '..h.record_count..' variants'),
            'History: '..h.coverage.history_from_day..' through '..h.coverage.history_through_day..' UTC',
            'Generation prepared by desktop: '..active.receipt.completed_at..' (not a file delivery receipt)',
        }
    end
    if s.compatibility_message then out.tip[#out.tip+1]=s.compatibility_message end
    out.tip[#out.tip+1]='The companion shows actual file delivery. WoW cannot detect newer files while running.'
    out.tip[#out.tip+1]='Click to review Reload UI after the companion has installed files.'
    return out
end
function B.RequestReload()
    if not W.Active() then return false,'disabled' end
    if InCombatLockdown and InCombatLockdown() then return false,'combat' end
    if not (StaticPopupDialogs and StaticPopup_Show and ReloadUI) then return false,'unavailable' end
    StaticPopupDialogs.TWICHUI_MARKET_RELOAD={
        text='Reload UI to read Market files already installed by the companion?\n\nFinish any unsaved edits first. This closes current interactions. A newer file cannot be detected from inside WoW. Saved settings and local scan history are preserved.',
        button1='Reload UI',button2=CANCEL or 'Cancel',timeout=0,whileDead=true,hideOnEscape=true,preferredIndex=3,
        OnAccept=function()
            if W.Active() and not (InCombatLockdown and InCombatLockdown()) then ReloadUI() end
        end,
    }
    StaticPopup_Show('TWICHUI_MARKET_RELOAD');return true
end
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

-- Keep all legacy formats and validation paths. The separate summary contract
-- becomes selected only after its header has passed validation.
if W.Summary then
    local Q=W.Summary
    local begin,step,load,cancel=B.Begin,B.Step,B.Load,B.Cancel
    function B.Begin(raw,automatic,expected)
        if type(raw)=='table' and raw.summary_version~=nil then return Q.Begin(raw,expected,active~=nil) end
        Q.Cancel();return begin(raw,automatic,expected)
    end
    function B.Step(ms)
        if Q.Pending() then return Q.Step(ms) end
        if Q.Selected() and not job then local status=Q.Status();return status.ready,status.error end
        local ok,why=step(ms);if ok and active then Q.Deactivate() end;return ok,why
    end
    function B.Load()
        if not W.Active() then return false,'disabled' end
        if type(TwichUIMarketData)=='table' and TwichUIMarketData.summary_version~=nil then
            if InCombatLockdown and InCombatLockdown() then return false,'combat' end
            return Q.Begin(TwichUIMarketData,nil,active~=nil)
        end
        return load()
    end
    function B.Cancel() Q.Cancel();return cancel() end
    for _,name in ipairs({'Status','Manifest','Market','Receipt','Scope','Variants','EachItem','Record','Availability','Value','History','Freshness'}) do
        local legacy=B[name]
        B[name]=function(...)
            if Q.Selected() then return Q[name](...) end
            return legacy(...)
        end
    end
    local status=B.Status
    function B.Status()
        local out=status()
        if not Q.Selected() then
            local q=Q.Status();out.loading=out.loading or q.loading
            if q.error then out.error=q.error;out.compatibility_message=q.compatibility_message end
        end
        return out
    end
    local compatibility,text=B.Compatibility,B.CompatibilityText
    function B.Compatibility()
        if not Q.Selected() then return compatibility() end
        local s=Q.Status();return {compatible=s.ready,desktop_build=s.desktop_build or 'unknown',summary=true,
            transport_version=1,contract_version=1,schema_version=1,receipt_schema_version=1,minimum_reader_version=1,reader_contract_version=1}
    end
    function B.CompatibilityText(diagnostics)
        if not Q.Selected() then return text(diagnostics) end
        local s=Q.Status();if not s.ready then return nil end
        return 'Market summary from Companion '..s.desktop_build:gsub('|','||'):gsub('[%c]',' ')..
            (diagnostics and '\nSummary contract 1; header verified; partitions validated on demand.' or '')
    end
    local capabilities=B.Capabilities
    function B.Capabilities() local c=capabilities();c.summary_index=true;c.summary_contract=1;return c end
    function B.RecognizeSummary()
        if not W.Active() or InCombatLockdown and InCombatLockdown() then return false end
        local get=C_AddOns and C_AddOns.GetAddOnMetadata
        if TwichUIMarketData==nil and get then
            local ok,version=pcall(get,B.ADDON,'X-TwichUI-Summary')
            if ok and version=='1' and C_AddOns.LoadAddOn then measured('workshop.bridgeLoad',function()return pcall(C_AddOns.LoadAddOn,B.ADDON)end) end
        end
        if type(TwichUIMarketData)=='table' and TwichUIMarketData.summary_version~=nil then return B.Load() end
        return false
    end
end
