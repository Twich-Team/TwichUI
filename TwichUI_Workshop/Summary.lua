-- Archive-free, research-only external evidence. No saved data or native identity mapping.
local R,W=TwichUI,TwichUI.Workshop
local J,S=W.BridgeCodec,W.BridgeValidate
local Q={PART_BYTES=1048576,TOTAL_BYTES=67108864,SLICE_MS=3,RESUMES=512,HANDOFF_RESUMES=16}
W.Summary=Q
local N=J.NULL
local active,job,rejected,selected=nil,nil,nil,false
local parkedHistory
local previous,previousCache
local cached,queue,queued=nil,{},{}
local queuedAt={}
local stats={validation_ms=0,largest_slice_ms=0,slices=0,failures=0,load_ms=0,largest_load_ms=0,lookup_calls=0}
local lastError
local function changed()
    if W.Pricing and W.Pricing.Notify then W.Pricing.Notify() end
end
local function cancelPending()
    if W.Pricing and W.Pricing.CancelPending then W.Pricing.CancelPending() end
end
local function rejectSplit()
    if not (active and active.header.contract_version==3) then return end
    rejected=active.raw
    active,cached=previous,previousCache;previous,previousCache=nil,nil
    queue,queued,queuedAt={},{},{};parkedHistory=nil
    return true
end
local function clock() return GetTimePreciseSec and GetTimePreciseSec()*1000 or debugprofilestop and debugprofilestop() or 0 end
local function observing()return R.Perf and R.Perf.on and R.Perf.Observe end
local function validationFinished(current)
    if current.started and observing() and current.capture==R.Perf.captureID then
        R.Perf.Observe(current.bucket>=64 and 'workshop.historyValidationWait' or 'workshop.currentValidationWait',math.max(0,clock()-current.started))
    end
end
local function measured(id,fn,...) if R.Perf and R.Perf.Call then return R.Perf.Call(id,fn,...) end;return fn(...) end
local function need(ok) if not ok then error('invalid Workshop summary',0) end end
local function closed(v,keys)
    need(type(v)=='table');local n=0
    for k in pairs(v) do need(keys[k]);n=n+1 end
    local expected=0;for k in pairs(keys) do need(v[k]~=nil);expected=expected+1 end
    need(n==expected)
end
local function digest(v) return type(v)=='string' and #v==64 and not v:find('[^0-9a-f]') end
local function tick() coroutine.yield() end
local function header(raw,expected)
    if type(raw)=='table' and W.Int(raw.summary_version,3,2147483647) then error('summary newer_addon',0) end
    local prepared=type(raw)=='table'and raw.summary_version==2
    closed(raw,prepared and {summary_version=true,manifest=true,bank=true,receipt=true,prepared=true}or {summary_version=true,manifest=true,bank=true,receipt=true})
    need((raw.summary_version==1 or prepared) and (raw.bank=='A' or raw.bank=='B') and type(raw.manifest)=='string' and #raw.manifest<=65536)
    local h=J.Parse(raw.manifest,tick)
    if type(h)=='table' and (W.Int(h.schema_version,4,2147483647) or W.Int(h.contract_version,4,2147483647)) then error('summary newer_addon',0) end
    S.Schema(h.contract_version==3 and W.SummaryCurrentSchema or h.contract_version==2 and W.SummaryHistorySchema or W.SummarySchema,h,tick)
    need(J.Encode(h,tick)==raw.manifest and digest(h.generation_id))
    local body=J.Object();for k,v in pairs(h) do if k~='generation_id' then body[k]=v end end
    need(J.SHA(J.Encode(body,tick),tick)==h.generation_id)
    need(h.issuer_id==h.issuer_id:lower() and h.generated_at==h.source_observation.observed_at)
    need(S.CompareMoney(h.source_observation.observation_id,h.source_watermark)<=0)
    if expected and expected.market then need(J.Encode(expected.market,tick)==J.Encode(h.market,tick)) end
    local history=h.contract_version>=2
    if history then
        local _,ending=S.Time(h.generated_at);local lastDay;local seen={}
        for _,o in ipairs(h.observations) do
            local _,at=S.Time(o.observed_at);local day=math.floor(at/86400)
            need((not lastDay or day>lastDay) and at<=ending and math.floor(ending/86400)-day<60)
            need(not seen[o.observation_id] and S.CompareMoney(o.observation_id,h.source_watermark)<=0 and (not o.synthetic or h.synthetic));seen[o.observation_id]=true
            lastDay=day;tick()
        end
        local last=h.observations[#h.observations]
        need(last.observation_id==h.source_observation.observation_id and last.observed_at==h.source_observation.observed_at)
    end
    local parts,total,count,last={},0,0,-1
    for _,p in ipairs(h.partitions) do
        need(p.bucket>last);last=p.bucket;parts[p.bucket]=p;count=count+p.record_count;total=total+p.bytes;tick()
    end
    need(count==h.record_count and total<=h.partitioning.max_total_bytes and h.coverage.source_records==count and h.coverage.delivered_records==count)
    if h.contract_version==3 then
        need(#h.history_partitions==#h.partitions)
        local bytes=0
        for i,p in ipairs(h.history_partitions)do
            local current=h.partitions[i]
            need(p.bucket==current.bucket and p.record_count==current.record_count)
            parts[64+p.bucket]=p;bytes=bytes+p.bytes;tick()
        end
        need(bytes<=h.history_partitioning.max_total_bytes)
    end
    need(type(raw.receipt)=='string' and #raw.receipt<=4096)
    local receipt=J.Parse(raw.receipt,tick)
    closed(receipt,{schema_version=true,generation_id=true,desktop_build=true,completed_at=true})
    need(receipt.schema_version==1 and receipt.generation_id==h.generation_id and type(receipt.desktop_build)=='string'
        and #receipt.desktop_build>=1 and #receipt.desktop_build<=80 and S.Time(receipt.completed_at) and S.Time(receipt.completed_at)>=S.Time(h.generated_at))
    local preparedContext
    if prepared then need(W.Prepared~=nil);preparedContext=W.Prepared.Begin(raw.prepared,h,raw.bank,tick)end
    return {prepared=preparedContext,preparedText=raw.prepared,summary_version=raw.summary_version,header=h,raw=raw,bank=raw.bank,manifest=raw.manifest,receiptText=raw.receipt,receipt=receipt,parts=parts,checked={},failed={},loaded={},total_bytes=total,loaded_bytes=0,loaded_parts=0,checked_count=0,
        current_bytes=0,history_bytes=0,history_loaded_parts=0,history_checked_count=0}
end
local function money(v) return v==N or S.Money(v,true) and #v<=11 and (#v<11 or v<='99999999999') end
local function rows(raw,p,h,historical)
    local policy=historical and h.history_partitioning or h.partitioning
    need(type(raw)=='string' and #raw<=policy.max_partition_bytes and #raw==p.bytes and J.SHA(raw,tick)==p.sha256)
    local out=J.ParseSummary(raw,tick,policy.max_partition_bytes)
    need(getmetatable(out)==J.ARRAY and #out==p.record_count and J.Encode(out,tick)==raw)
    local lastItem,lastVariant=0,''
    for _,r in ipairs(out) do
        need(getmetatable(r)==J.ARRAY and #r==((historical or h.contract_version==2) and 14 or 13) and W.Int(r[1],1,2147483647) and r[1]%64==p.bucket and digest(r[2]))
        need(r[1]>lastItem or r[1]==lastItem and r[2]>lastVariant);lastItem,lastVariant=r[1],r[2]
        need(W.Int(r[3],0,4) and W.Int(r[9],0,1) and r[8]==0)
        for _,i in ipairs({4,5,6,10}) do need(money(r[i])) end
        local has=r[4]~=N or r[5]~=N or r[6]~=N or r[10]~=N
        if r[3]==0 then need(has and r[9]==0 and W.Int(r[7],1,9007199254740991))
        elseif r[3]==1 then need(not has and r[9]==1 and W.Int(r[7],1,9007199254740991))
        elseif r[3]==2 then need(not has and r[9]==1 and r[7]==0)
        elseif r[3]==3 then need(not has and r[9]==1 and r[7]==N)
        else need(not has and r[9]==1 and r[7]==N) end
        need(W.Int(r[11],0,14) and W.Int(r[12],0,60) and W.Int(r[13],0,60) and r[11]<=r[12] and r[12]<=r[13])
        need((r[10]==N or r[12]>=3) and (r[5]==N or r[11]>0))
        if historical or h.contract_version==2 then
            need(type(r[14])=='table' and getmetatable(r[14])==J.ARRAY and #r[14]==#h.observations)
            for _,p in ipairs(r[14]) do
                need(getmetatable(p)==J.ARRAY and #p==4 and W.Int(p[1],0,4) and money(p[2]) and money(p[3]))
                if p[1]==0 then need(p[2]~=N and p[3]~=N and W.Int(p[4],1,9007199254740991))
                elseif p[1]==1 then need(p[2]==N and p[3]==N and W.Int(p[4],1,9007199254740991))
                elseif p[1]==2 then need(p[2]==N and p[3]==N and p[4]==0)
                else need(p[2]==N and p[3]==N and p[4]==N) end
                tick()
            end
        end;tick()
    end
    if historical then
        -- Verify the rich data projects to the already authenticated current
        -- descriptor without loading a second decoded partition.
        local hash=J.Hash(tick);hash:Update('[')
        for i,r in ipairs(out)do
            local current=J.Array();for j=1,13 do current[j]=r[j]end
            if i>1 then hash:Update(',')end;hash:Update(J.Encode(current,tick))
        end
        hash:Update(']')
        local paired
        for _,current in ipairs(h.partitions)do if current.bucket==p.bucket then paired=current;break end end
        need(paired and hash:Finish()==paired.sha256)
    end
    return out
end
local schedule,startNext
local function handoff(bucket,why,notify)
    if not (W.Pricing and W.Pricing.Decoded and W.Pricing.Rejected) then return end
    if not why and not W.Pricing.NeedsHandoff(bucket) then return end
    job={kind='handoff',bucket=bucket,notify=notify,failure=why,co=coroutine.create(function()
        if why then W.Pricing.Rejected(bucket,why,coroutine.yield)
        else W.Pricing.Decoded(bucket,coroutine.yield) end
    end)}
end
function Q.Selected() return selected end
function Q.Deactivate() selected=false;Q.Cancel();active,cached,previous,previousCache=nil,nil,nil,nil;queue,queued={},{} end
function Q.Begin(raw,expected,suppressPendingSelection)
    if active and active.raw==raw and active.manifest==raw.manifest and active.bank==raw.bank and active.receiptText==raw.receipt and active.preparedText==raw.prepared and active.summary_version==raw.summary_version then selected=true;return true end
    if rejected==raw then return false,'invalid' end
    if job and job.raw==raw then schedule();return false,'loading' end
    cancelPending()
    if active and active.prepared then W.Prepared.Cancel(active.prepared)end
    if parkedHistory then queued[parkedHistory.bucket]=nil;parkedHistory=nil end
    rejected=nil;lastError=nil;stats.unsupported=nil;stats.reload_required=nil
    job={kind='header',raw=raw,co=coroutine.create(function()return header(raw,expected)end)}
    if not active and not suppressPendingSelection then selected=true end
    schedule();return false,'loading'
end
local function loadPart(p,bucket)
    if InCombatLockdown and InCombatLockdown() then return false,'combat' end
    local key=active.bank..('%02d'):format(p.bucket)
    local historical=bucket>=64
    local globals
    if historical then globals=TwichUIMarketHistoryParts else globals=TwichUIMarketParts end
    local raw=type(globals)=='table' and globals[key] or nil
    if raw==nil then
        if not(C_AddOns and C_AddOns.LoadAddOn) then return false,'missing' end
        local before=clock()
        local function load()return pcall(C_AddOns.LoadAddOn,'TwichUI_Market'..(historical and 'History' or '')..'Part'..key)end
        local ok,loaded=measured(historical and 'workshop.historyLoad' or 'workshop.summaryLoad',load)
        local elapsed=math.max(0,clock()-before);stats.load_ms=stats.load_ms+elapsed;stats.largest_load_ms=math.max(stats.largest_load_ms,elapsed)
        if not ok or not loaded then return false,'missing' end
        if historical then globals=TwichUIMarketHistoryParts else globals=TwichUIMarketParts end
        raw=type(globals)=='table' and globals[key] or nil
    end
    if type(raw)~='string' or #raw>Q.PART_BYTES then return false,'invalid' end
    if not active.loaded[bucket] then
        active.loaded[bucket]=true;active.loaded_bytes=active.loaded_bytes+#raw
        if historical then
            active.history_loaded_parts=active.history_loaded_parts+1;active.history_bytes=active.history_bytes+#raw
            need(active.history_bytes<=active.header.history_partitioning.max_total_bytes)
        else
            active.loaded_parts=active.loaded_parts+1;active.current_bytes=active.current_bytes+#raw
            need(active.current_bytes<=active.header.partitioning.max_total_bytes)
        end
    end
    if R.Perf and R.Perf.on then
        R.Perf.Count('workshop.summary.decodeStarts')
        R.Perf.Count(historical and 'workshop.summary.historyDecodes' or 'workshop.summary.currentDecodes')
        if active.checked[bucket] then R.Perf.Count('workshop.summary.decodeRepeats') end
    end
    job={kind='part',bucket=bucket,raw=raw,co=coroutine.create(function()return rows(raw,p,active.header,historical)end)}
    if observing()then job.started=clock();job.capture=R.Perf.captureID end
    return true
end
startNext=function()
    if job or not active then return end
    if active.prepared and W.Prepared.Pending(active.prepared)then
        local ctx=active.prepared
        job={kind='prepared',co=coroutine.create(function()
            W.Prepared.Work(ctx,function(item,key,why)
                if active and active.prepared==ctx and W.Pricing and W.Pricing.ItemReady then W.Pricing.ItemReady(item,key,why)end
            end,changed)
        end)}
        schedule();return
    end
    if #queue==0 and not parkedHistory then return end
    local position=1
    if active.header.contract_version==3 then
        position=nil
        for i,bucket in ipairs(queue)do if bucket<64 then position=i;break end end
        if not position and parkedHistory then
            job=parkedHistory;parkedHistory=nil;queued[job.bucket]=nil;schedule();return
        end
        position=position or 1
    end
    local bucket=table.remove(queue,position);queued[bucket]=nil
    local began=queuedAt[bucket];queuedAt[bucket]=nil
    if began and observing() and began.capture==R.Perf.captureID then R.Perf.Observe('workshop.partitionQueueWait',math.max(0,clock()-began.at))end
    local ok,why=loadPart(active.parts[bucket],bucket)
    if not ok then
        active.failed[bucket]=why;lastError=why
        if why~='combat' and active.header.contract_version==3 then
            stats.failures=stats.failures+1;stats.reload_required=true;cancelPending();rejectSplit();changed();return
        end
        handoff(bucket,why,true);if not job then changed() end
    end
    if job then schedule() end
end
function Q.Step(ms)
    local function run()
        local current=job
        if not current then startNext();return active~=nil,lastError end
        local start,n=clock(),0
        local budget=math.max(0.5,(W.Int(ms,1,20) or Q.SLICE_MS)-1)
        local limit=current.kind=='handoff' and Q.HANDOFF_RESUMES or (GetTimePreciseSec or debugprofilestop) and Q.RESUMES or 32
        repeat
            local ok,value=coroutine.resume(current.co);n=n+1
            if not ok then
                if current.kind=='part'then validationFinished(current)end
                stats.failures=stats.failures+1;cancelPending();changed();lastError='invalid';stats.unsupported=value=='summary newer_addon'
                if current.kind=='header' then rejected=current.raw else
                    if active.prepared then W.Prepared.Cancel(active.prepared)end
                    if current.bucket then active.failed[current.bucket]='invalid'end;stats.reload_required=true
                    if not rejectSplit() and previous then rejected=active.raw;active,cached=previous,previousCache;previous,previousCache=nil,nil;queue,queued,queuedAt={},{},{};parkedHistory=nil end
                end
                job=nil;break
            end
            if coroutine.status(current.co)=='dead' then
                if current.kind=='prepared'then job=nil;break end
                if current.kind=='handoff' then job=nil;if current.notify then changed() end;break end
                if current.kind=='part'then validationFinished(current)end
                local notify=current.kind=='header' or not active.checked[current.bucket]
                if current.kind=='header' then previous,previousCache=active,cached;active=value;cached=nil;queue,queued,queuedAt={},{},{};selected=true;cancelPending()
                else
                    if not active.checked[current.bucket] then
                        if current.bucket>=64 then active.history_checked_count=active.history_checked_count+1
                        else active.checked_count=active.checked_count+1 end
                    end
                    active.checked[current.bucket]=true;active.failed[current.bucket]=nil
                    cached={bucket=current.bucket,rows=value}
                end
                job=nil
                if current.kind=="part" then handoff(current.bucket,nil,notify) end
                if notify and not job then changed() end
                break
            end
        until n>=limit or clock()-start>=budget
        local elapsed=math.max(0,clock()-start)
        if current.kind=='handoff' then
            stats.completion_ms=(stats.completion_ms or 0)+elapsed
            stats.largest_completion_ms=math.max(stats.largest_completion_ms or 0,elapsed)
        else
            stats.validation_ms=stats.validation_ms+elapsed;stats.largest_slice_ms=math.max(stats.largest_slice_ms,elapsed);stats.slices=stats.slices+1
        end
        if not job then startNext() end
        return active~=nil,job and 'loading' or lastError
    end
    local id=job and job.kind=='handoff' and 'workshop.pricingComplete' or
        job and job.kind=='prepared'and 'workshop.preparedVerify' or
        job and job.bucket and job.bucket>=64 and 'workshop.historyValidate' or 'workshop.summaryValidate'
    return measured(id,run)
end
schedule=function()
    local current=job;if not current or current.scheduled or not(C_Timer and C_Timer.After) then return end
    current.scheduled=true
    current.scheduleSerial=(current.scheduleSerial or 0)+1
    local serial=current.scheduleSerial
    C_Timer.After(0,function()
        if job~=current or current.scheduleSerial~=serial then return end
        current.scheduled=false;Q.Step();if job then schedule() end
    end)
end
function Q.Cancel() if active and active.prepared then W.Prepared.Cancel(active.prepared)end;cancelPending();job=nil;parkedHistory=nil;queue,queued,queuedAt={},{},{} end
function Q.Pending() return job~=nil or parkedHistory~=nil end
function Q.Load(raw) return Q.Begin(raw) end
local function request(bucket)
    if not active then return nil,'unavailable' end
    local generation=active
    if not active.parts[bucket] then return {},'not_observed' end
    if cached and cached.bucket==bucket then return cached.rows end
    if active.failed[bucket]=='combat' and not(InCombatLockdown and InCombatLockdown()) then
        active.failed[bucket]=nil;if lastError=='combat' then lastError=nil end
    end
    if active.failed[bucket] then return nil,active.failed[bucket] end
    if not queued[bucket] and not(job and job.bucket==bucket and not job.failure) then
        if InCombatLockdown and InCombatLockdown() then return nil,'combat' end
        queue[#queue+1]=bucket;queued[bucket]=true
        if observing()then queuedAt[bucket]={at=clock(),capture=R.Perf.captureID}end
        if bucket<64 and active.header.contract_version==3 and job and job.kind=='part' and job.bucket>=64 then
            -- One bounded historical coroutine can pause between slices. Current
            -- requests never wait behind an unrelated long historical validation.
            parkedHistory=job;job=nil;queued[parkedHistory.bucket]=true
            parkedHistory.scheduleSerial=(parkedHistory.scheduleSerial or 0)+1;parkedHistory.scheduled=false
            if R.Perf and R.Perf.on then R.Perf.Count('workshop.summary.historyPreemptions')end
        end
        startNext();schedule()
    end
    if active~=generation then return nil,lastError or 'unavailable' end
    if active.failed[bucket] then return nil,active.failed[bucket] end
    return nil,'loading'
end
local function preparedRequested()
    if not(active and active.prepared and W.Prepared.Pending(active.prepared))then return end
    if job and job.kind=='part'and job.bucket>=64 then
        parkedHistory=job;job=nil;queued[parkedHistory.bucket]=true
        parkedHistory.scheduleSerial=(parkedHistory.scheduleSerial or 0)+1;parkedHistory.scheduled=false
        if R.Perf and R.Perf.on then R.Perf.Count('workshop.summary.historyPreemptions')end
    end
    startNext();schedule()
end
local function preparedFailure(why)
    if why~='invalid'then return end
    stats.failures=stats.failures+1;stats.reload_required=true;lastError='invalid'
    W.Prepared.Cancel(active.prepared);cancelPending();job=nil;rejectSplit();changed()
end
function Q.PreparedActive()return active and active.prepared~=nil or false end
function Q.PreparePlan(dependencies,visible,work,owner)
    if active and active.prepared then W.Prepared.Plan(active.prepared,dependencies,visible,work,owner)end
end
function Q.Prioritize(items)if active and active.prepared then W.Prepared.Prioritize(active.prepared,items);preparedRequested()end end
function Q.ReleasePreparation(owner)if active and active.prepared then W.Prepared.Release(active.prepared,owner)end end
function Q.Shared(item,key)if active and active.prepared then W.Prepared.Shared(active.prepared,item,key)end end
function Q.Status()
    local out={};for k,v in pairs(stats) do out[k]=v end
    out.state=active and 'ready' or job and 'loading' or lastError and 'invalid' or 'absent'
    out.ready=active~=nil;out.loading=job~=nil;out.error=lastError
    out.generation=active and active.header.generation_id;out.records=active and active.header.record_count or 0
    out.bytes=(active and active.loaded_bytes+#active.manifest or 0)+(previous and previous.loaded_bytes+#previous.manifest or 0);out.cache_entries=cached and #cached.rows or 0
    out.summary=true;out.schema=active and active.header.schema_version or 1;out.contract_version=active and active.header.contract_version or 1;out.reader_contract_version=3;out.minimum_reader_version=out.contract_version;out.transport_version=1
    out.history=active and active.header.contract_version>=2 or false
    out.reload_required=stats.reload_required==true
    if active then for _,why in pairs(active.failed) do if why~='combat' then out.reload_required=true;break end end end
    out.compatibility_message=stats.unsupported and 'Update TwichUI to read this newer Workshop summary.' or nil
    out.desktop_build=active and active.receipt.desktop_build
    out.checked_parts=active and active.checked_count or 0;out.parts=active and #active.header.partitions or 0
    out.loaded_parts=active and active.loaded_parts or 0;out.decoded_parts=cached and 1 or 0
    out.current_bytes=active and active.current_bytes or 0;out.history_bytes=active and active.history_bytes or 0
    out.history_loaded_parts=active and active.history_loaded_parts or 0;out.history_checked_parts=active and active.history_checked_count or 0
    out.decoded_current_rows=cached and cached.bucket<64 and #cached.rows or 0
    out.decoded_history_rows=cached and cached.bucket>=64 and #cached.rows or 0
    if active and active.prepared then
        out.prepared=W.Prepared.Status(active.prepared);out.prepared_version=1
        out.parts=active.prepared.count;out.loaded_parts=out.prepared.loads;out.checked_parts=out.prepared.full
        out.current_bytes=out.prepared.bytes;out.bytes=out.bytes+out.current_bytes+#active.preparedText
        out.decoded_current_rows=0
    end
    if previous and previous.prepared then out.bytes=out.bytes+previous.prepared.stats.bytes+#previous.preparedText end
    out.parked_history=parkedHistory~=nil
    return out
end
function Q.Manifest() return active and J.Copy(active.header) or nil end
function Q.Market() return active and J.Copy(active.header.market) or nil end
function Q.Receipt() return active and J.Copy(active.receipt) or nil end
function Q.Scope()
    return active and {type='current_observed_exact_variants',scope_complete=true,whole_market_complete=false,
        requested_count=active.header.record_count,generation=active.header.generation_id,history_delivered=active.header.contract_version>=2} or nil
end
function Q.Variants(item,limit)
    item=W.Int(item,1,2147483647);limit=W.Int(limit or 20,1,100)
    if not item or not limit then return nil,'identity' end
    if active and active.prepared then local out,why=W.Prepared.Variants(active.prepared,item,limit);preparedRequested();preparedFailure(why);return out,why end
    local part,why=request(item%64);if not part then return nil,why end
    local out,count={},0
    for _,r in ipairs(part) do if r[1]==item then count=count+1;if #out<limit then out[#out+1]=r[2] end end end
    return out,count>#out
end
function Q.EachItem(add,work,capped)
    if not active then return false,'unavailable' end
    if active.prepared then
        local generation=active;local ctx=active.prepared;local epoch=ctx.epoch
        for bucket=0,ctx.count-1 do
            local ok,why=W.Prepared.EnsurePart(ctx,bucket);preparedRequested()
            while not ok and why=='loading'and work do
                work();if active~=generation or ctx.epoch~=epoch then return false,'cancelled'end
                ok,why=W.Prepared.EnsurePart(ctx,bucket);preparedRequested()
            end
            if not ok then return false,why end
            local previous
            for i=1,ctx.descriptors[bucket].record_count do
                local item=W.Prepared.ItemAt(ctx,bucket,i)
                if item~=previous then add(item);previous=item end
                if work then work();if active~=generation or ctx.epoch~=epoch then return false,'cancelled'end end
                if capped and capped()then return true end
            end
        end
        return true
    end
    for _,p in ipairs(active.header.partitions) do
        local part,why=request(p.bucket)
        while not part and why=='loading' and work do work();part,why=request(p.bucket) end
        if not part then return false,why end
        local previous
        for _,r in ipairs(part) do
            if r[1]~=previous then add(r[1]);previous=r[1] end
            if work then work() end;if capped and capped() then return true end
        end
    end
    return true
end
local function project(item,variant,r,current)
    return {item_id=item,variant_key=variant,summary=true,daily=not current and r[14] and J.Copy(r[14]) or nil,current={state=active.header.states[r[3]+1],supply=r[7],complete=true,
                arithmetic_status=r[3]==4 and 'unsupported' or 'supported',observation_ref=0,
                metrics={recent_copper=r[4],market_value_copper=r[5],minimum_copper=r[6],historical_value_copper=r[10]},
                coverage={priced_days_14=r[11],priced_days_60=r[12],observed_days_60=r[13]}}}
end
function Q.Record(item,variant,opt)
    local function run()
        stats.lookup_calls=stats.lookup_calls+1
        item=W.Int(item,1,2147483647)
        if not item or not digest(variant) then return nil,'variant_required' end
        local current=opt and opt.current
        if active and active.prepared and current then
            local r,why=W.Prepared.Record(active.prepared,item,variant,opt);preparedRequested();preparedFailure(why)
            if r then return project(item,variant,r,true)end
            return nil,why
        end
        local bucket=item%64+(active and active.header.contract_version==3 and not current and 64 or 0)
        local part,why=request(bucket);if not part then return nil,why end
        local low,high=1,#part
        while low<=high do
            local middle=math.floor((low+high)/2);local r=part[middle]
            if r[1]==item and r[2]==variant then
            return project(item,variant,r,current)
            elseif r[1]<item or r[1]==item and r[2]<variant then low=middle+1 else high=middle-1 end
        end
        return nil,'not_observed'
    end
    return measured('workshop.summaryLookup',run)
end
function Q.Availability(item,variant,day)
    if day~=nil then return {state='summary_only',included=false,summary=true} end
    local r,why=Q.Record(item,variant,{current=true})
    local state=r and r.current.state or why
    state=state=='absent' and 'observed_absent' or state=='unknown' and 'unknown_coverage' or state
    return {state=state,included=r~=nil,summary=true,complete=r~=nil}
end
local METRIC={recent='recent_copper',market='market_value_copper',minimum='minimum_copper',historical='historical_value_copper'}
function Q.Value(item,variant,metric)
    local r,why=Q.Record(item,variant,{current=true});if not r then return nil,why end
    local field=METRIC[metric or 'recent'];if not field then return nil,'metric' end
    local v=r.current.metrics[field];if v==N then return nil,r.current.state=='unsupported' and 'unsupported' or 'unavailable' end
    return {copper=v,value=tonumber(v),algorithm=active.header.pricing_algorithm,basis='Market server summary · listing evidence',
        generation=active.header.generation_id,source='market_server',observation=J.Copy(active.header.source_observation),quality='limited'}
end
local function history(item,variant,metric,opt)
    if not active or active.header.contract_version<2 then return nil,'summary_only' end
    local r,why=Q.Record(item,variant);if not r then return nil,why end
    metric=metric or 'recent';local column=({recent=2,minimum=3,supply=4})[metric]
    if not column then return nil,'metric' end
    local days=W.Int(opt and opt.days or 60,1,60);if not days then return nil,'window' end
    local h=active.header;local _,at=S.Time(h.generated_at);local today=math.floor(at/86400);local from=today-days+1
    local out={basis=h.history_basis,algorithm=h.pricing_algorithm,source='market_server',generation=h.generation_id,
        scope=Q.Scope(),market=J.Copy(h.market),coverage=J.Copy(h.coverage),metric=metric,points={},gaps={},from=from,to=today,observed_days=0,synthetic=h.synthetic}
    local present={}
    for index,p in ipairs(r.daily) do
        local o=h.observations[index];local _,stamp=S.Time(o.observed_at);local day=math.floor(stamp/86400)
        if day>=from and day<=today then
            present[day]=true;out.observed_days=out.observed_days+1
            local raw=p[column];local value=raw~=N and tonumber(raw) or nil
            local reason=not value and (p[1]==2 and 'observed_absent' or p[1]==3 and 'unknown_variant_state' or p[1]==4 and 'unsupported' or 'no_supported_buyout') or nil
            if reason then out.gaps[#out.gaps+1]={from=day,to=day,why=reason} end
            out.points[#out.points+1]={kind='day',from=day,to=day,v=value,copper=metric~='supply' and raw~=N and raw or nil,
                state=({'listed','supply_only','absent','unknown','unsupported'})[p[1]+1],reason=reason,at=o.observed_at,
                observation_id=o.observation_id,provenance='Market server · '..h.pricing_algorithm,synthetic=o.synthetic,partial=false}
        end
    end
    for day=from,today do if not present[day] then out.gaps[#out.gaps+1]={from=day,to=day,why='no_server_observation'} end end
    return out
end
function Q.History(...) return measured("workshop.summaryHistory",history,...) end
function Q.Freshness(now)
    if not active then return {state='unavailable',text=job and 'Validating Market summary' or 'Market summary unavailable',tone='quiet',tip={'Local scans and history are unchanged.'}} end
    local h=active.header;local _,stamp=S.Time(h.source_observation.observed_at);now=now or time and time()
    local age=stamp and now and now-stamp
    local state=age and age>=0 and (age<=7200 and 'ready' or age<=86400 and 'aging' or 'stale') or 'unknown'
    return {state=state,text='Market summary '..state,tone=state=='ready' and 'good' or 'warn',generation=h.generation_id,age=age,observed_at=h.source_observation.observed_at,
        tip={'Loaded generation: '..h.generation_id,'Market server · '..h.market.region:upper()..' · '..h.market.player_ruleset..' · '..h.market.faction..' · house '..h.market.house_id,
            'Observed: '..h.source_observation.observed_at..' UTC'..(h.synthetic and ' · synthetic fixture' or ''),
            active.prepared and h.record_count..' exact current variants; requested records authenticate on demand across '..active.prepared.count..' prepared partitions.'or
                h.record_count..' current observed exact variants declared; partitions validate on demand ('..active.checked_count..'/'..#h.partitions..').',
            h.contract_version==3 and 'Actual Market daily closings are available on demand; missing observations remain gaps.' or
                h.contract_version==2 and 'Actual Market daily closings are loaded; missing observations remain gaps.' or 'Historical references only; detailed charts are not delivered.',
            'Native item-link equivalence is unavailable. Local scans remain independent.',
            'Publication in Companion does not prove game consumption. Files are read on login or a player-approved reload.'}}
end
if R.Perf and R.Perf.Gauge then
    for _,key in ipairs({'loads','bytes','hashes','verified','full','flag_words','cache_hits','pending','cancelled'})do
        R.Perf.Gauge('workshop.prepared.'..key,{label='Prepared current '..key,kind='cache',group='workshop',unit=key=='bytes'and 'bytes'or 'count',read=function()
            return active and active.prepared and W.Prepared.Status(active.prepared)[key]or 0
        end})
    end
    for _,g in ipairs({{'summaryBytes','Retained summary raw bytes','bytes','bytes'},{'summaryParts','Loaded summary partitions','loaded_parts','count'},
        {'summaryDecoded','Decoded summary rows (one partition)','cache_entries','count'},{'summaryChecked','Validated summary partitions','checked_parts','count'}}) do
        local key=g[3]
        R.Perf.Gauge('workshop.'..g[1],{label=g[2],kind='cache',group='workshop',unit=g[4],read=function()return Q.Status()[key] or 0 end})
    end
end
