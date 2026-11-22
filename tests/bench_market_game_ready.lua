-- Opt-in hook for bench_market_opportunities.lua. Disposable generated files
-- only. No production module/file is edited or installed.
local X={}
local Fixed=dofile(TESTS..'market_fixed_records.lua')
local c,W,J,B,Q,P,cfg,fixture,h,stats
local loaded,queue,queued,job,serial={},{},{},nil,0
local demands,authorized,trees,completeAuth={},{},{},{}
local active,clock
local function read(path)local f=assert(io.open(path));local s=f:read('*a');f:close();return s end
local function layout(projection)
    local count=projection=='current' and cfg.count or cfg.history_count
    local representation=projection=='history' and cfg.representation:match('^fixed%-') and 'json' or cfg.representation
    for _,l in ipairs(fixture.layouts)do if l.count==count and l.representation==representation and l.projection==projection then return l end end
    error('missing layout')
end
local function file(projection,bucket)
    local l=layout(projection)
    return cfg.root..'/'..l.representation..'-'..projection..'-'..l.count..'/'..('%02d'):format(bucket)..'.lua',l
end
local function load(projection,bucket)
    local path,l=file(projection,bucket);local at=clock();local fn,why=loadfile(path);assert(fn,why)
    local began=at
    stats.compile_ms=stats.compile_ms+clock()-at;setfenv(fn,c);at=clock();local v=fn()
    stats.execute_ms=stats.execute_ms+clock()-at
    stats.worst_load_ms=math.max(stats.worst_load_ms or 0,clock()-began)
    local identity=(cfg.representation:match('^packed%-') or cfg.representation:match('^fixed%-')) and l.descriptors[bucket+1].sha256 or h.generation_id
    assert(v[1]==1 and v[2]==identity and v[3]==bucket and v[4]==l.count,'envelope binding')
    stats.loads=stats.loads+1;stats.source_bytes=stats.source_bytes+l.descriptors[bucket+1].source_bytes
    stats.peak_kib=math.max(stats.peak_kib,collectgarbage('count'))
    trees[projection..bucket]=v[6]
    return v[5],l
end
local function valid(v,offset,historical)
    local function at(i)return v[i+offset]end
    local state=at(1);assert(W.Int(state,0,4) and at(6)==0 and W.Int(at(7),0,1))
    local any=false
    for _,i in ipairs({2,3,4,8})do local n=at(i);assert(n==false or W.Int(n,1,99999999999));any=any or n~=false end
    assert((state==0 and any and at(7)==0 and W.Int(at(5),1,9007199254740991)) or
        (state~=0 and not any and at(7)==1 and (state==1 and W.Int(at(5),1,9007199254740991) or state==2 and at(5)==0 or state>=3 and at(5)==false)))
    assert(W.Int(at(9),0,14) and W.Int(at(10),0,60) and W.Int(at(11),0,60) and at(9)<=at(10) and at(10)<=at(11))
    assert((at(8)==false or at(10)>=3) and (at(3)==false or at(9)>0))
    if historical then
        local days=at(12);assert(type(days)=='table' and #days==#h.observations)
        for _,d in ipairs(days)do
            assert(#d==4 and W.Int(d[1],0,4))
            if d[1]==0 then assert(W.Int(d[2],1,99999999999) and W.Int(d[3],1,99999999999) and W.Int(d[4],1,9007199254740991))
            elseif d[1]==1 then assert(d[2]==false and d[3]==false and W.Int(d[4],1,9007199254740991))
            elseif d[1]==2 then assert(d[2]==false and d[3]==false and d[4]==0)
            else assert(d[2]==false and d[3]==false and d[4]==false)end
        end
    end
end
local function digest(s)return type(s)=='string' and #s==64 and not s:find('[^0-9a-f]')end
local function canonicalRow(r,historical)
    local row=J.Array()
    for i=1,13 do
        local v=r[i];if v==false then v=J.NULL end
        if (i==4 or i==5 or i==6 or i==10) and type(v)=='number' then v=('%.0f'):format(v)end
        row[i]=v
    end
    if historical then
        row[14]=J.Array()
        for _,p in ipairs(r[14])do local day=J.Array()
            for i=1,4 do local v=p[i];if v==false then v=J.NULL end;if (i==2 or i==3) and type(v)=='number'then v=('%.0f'):format(v)end;day[i]=v end
            row[14][#row[14]+1]=day
        end
    end
    return J.Encode(row,coroutine.yield)
end
local function hash(s)stats.proof_hashes=(stats.proof_hashes or 0)+1;return J.SHA(s,coroutine.yield)end
local function authenticate(data,position,l,bucket,historical)
    local descriptor=l.descriptors[bucket+1];local n=descriptor.record_count
    assert(Fixed.Count(data)==n and position>=1 and position<=n)
    local r=Fixed.Row(data,position);valid(r,2,historical)
    assert(W.Int(r[1],1,2147483647) and r[1]%l.count==bucket and digest(r[2]))
    local size=1;while size<math.max(1,n)do size=size*2 end
    local index=size+position-1;local nodes=trees[(historical and 'history' or 'current')..bucket]
    local domain=(cfg.representation:match('^packed%-') or cfg.representation:match('^fixed%-')) and 'row\0' or 'row\0'..h.generation_id..'\0'
    local value=hash(domain..canonicalRow(r,historical))
    while index>1 do
        local siblingIndex=index%2==0 and index+1 or index-1
        local sibling
        if type(nodes)=='string'then
            assert(#nodes==(2*size-1)*64,'packed proof length')
            sibling=nodes:sub((siblingIndex-1)*64+1,siblingIndex*64)
        else sibling=nodes[siblingIndex]end
        assert(digest(sibling))
        value=hash('node\0'..(index%2==0 and value..sibling or sibling..value));index=math.floor(index/2)
    end
    assert(value==descriptor.merkle_root,'record proof rejected')
end
local lookup
local function validate(data,l,bucket,historical,fullHash)
    local count=0
    local checksum=(fullHash or cfg.representation=='verified-array') and J.Hash(coroutine.yield)
    if checksum then checksum:Update('[') end
    if cfg.representation=='index' then
        for item,variants in pairs(data)do
            assert(W.Int(item,1,2147483647) and item%l.count==bucket and type(variants)=='table')
            for key,v in pairs(variants)do
                assert(digest(key) and #v==(historical and 12 or 11));valid(v,0,historical);count=count+1;coroutine.yield()
            end
        end
    else
        local item,key=0,''
        for i=1,Fixed.Count(data)do local r=Fixed.Row(data,i)
            assert(#r==(historical and 14 or 13) and W.Int(r[1],1,2147483647) and r[1]%l.count==bucket and digest(r[2]))
            assert(r[1]>item or r[1]==item and r[2]>key);item,key=r[1],r[2]
            valid(r,2,historical);count=count+1
            if checksum then
                if count>1 then checksum:Update(',')end
                checksum:Update(canonicalRow(r,historical))
            end
            coroutine.yield()
        end
    end
    assert(count==l.descriptors[bucket+1].record_count)
    if checksum then
        checksum:Update(']');assert(checksum:Finish()==l.descriptors[bucket+1].sha256,'full payload checksum rejected')
    end
    return data
end
local schedule
local function step()
    if not job then
        local nextJob=table.remove(queue,1);if not nextJob then return end
        job=nextJob;local data,l=loaded[job.key],layout(job.projection)
        if not data then data,l=load(job.projection,job.bucket)end
        stats.decodes=stats.decodes+1
        job.co=coroutine.create(function()
            if cfg.representation=='json' then
                local descriptor=l.descriptors[job.bucket+1]
                return W.ExperimentalRows(data,descriptor,job.projection=='history' and X.historyHeader or X.header,job.projection=='history')
            end
            if X.selective then
                assert(not (job.projection=='history'),'history proofs are outside this current-price prototype')
                assert(Fixed.Count(data)==l.descriptors[job.bucket+1].record_count,'proof row count rejected')
                local pending=demands[job.key] or {}
                local n=l.descriptors[job.bucket+1].record_count
                local depth=0;local size=1;while size<math.max(1,n)do size=size*2;depth=depth+1 end
                local unique={};local demandCount=0
                for _,d in ipairs(pending)do local id=d.item..':'..tostring(d.key);if not unique[id]then unique[id]=true;demandCount=demandCount+1 end end
                -- Test-only whole-workload demand hint. The real engine already
                -- builds item dependencies; a future API can expose that set.
                demandCount=X.required and X.required[job.bucket] or demandCount
                if (cfg.representation=='hybrid' or cfg.representation=='packed-hybrid' or cfg.representation=='fixed-hybrid') and demandCount*(depth+1)*3>l.descriptors[job.bucket+1].bytes/64 then
                    validate(data,l,job.bucket,false,true);completeAuth[job.key]=true
                    stats.bulk_authentications=(stats.bulk_authentications or 0)+1
                    demands[job.key]={};return data
                end
                authorized[job.key]=authorized[job.key] or {}
                while #pending>0 do
                    local demand=table.remove(pending,1);local key=demand.key or P.BaseKey(demand.item)
                    local id=demand.item..':'..key
                    if not authorized[job.key][id]then
                        local r,_,position=lookup(data,demand.item,key)
                        if r then authenticate(data,position,l,job.bucket,false)
                        else
                            -- Prove nonmembership with adjacent authenticated
                            -- positions, including the beginning/end boundaries.
                            if position>1 then authenticate(data,position-1,l,job.bucket,false)end
                            if position<=Fixed.Count(data)then authenticate(data,position,l,job.bucket,false)end
                            local a=position>1 and Fixed.Row(data,position-1)
                            local b=position<=Fixed.Count(data) and Fixed.Row(data,position)
                            assert(not a or a[1]<demand.item or a[1]==demand.item and a[2]<key)
                            assert(not b or b[1]>demand.item or b[1]==demand.item and b[2]>key)
                        end
                        authorized[job.key][id]=true;stats.authenticated=(stats.authenticated or 0)+1
                    end
                end
                return data
            end
            return validate(data,l,job.bucket,job.projection=='history')
        end)
    end
    local mine=job;local at=clock();local resumes=0
    repeat
        local ok,value=coroutine.resume(mine.co);assert(ok,value);resumes=resumes+1
        if coroutine.status(mine.co)=='dead' then
            if mine.kind=='handoff' then job=nil
            else
                loaded[mine.key]=value;queued[mine.key]=nil
                job={kind='handoff',co=coroutine.create(function()
                    -- Keep PR1/PR3's actual pending batches; one local partition
                    -- can satisfy several existing modulo-64 demand buckets.
                    for b=mine.bucket,63,layout('current').count do
                        if mine.projection=='current' and P.NeedsHandoff(b) then P.Decoded(b,coroutine.yield)end
                    end
                end)}
            end
            P.Notify();break
        end
    until resumes>=512 or clock()-at>=2
    stats.validation_ms=stats.validation_ms+clock()-at
    stats.peak_kib=math.max(stats.peak_kib,collectgarbage('count'))
    if job or #queue>0 then schedule()end
end
schedule=function()
    local token=serial
    c.C_Timer.After(0,function()if token==serial then step()end end)
end
local function part(item,current)
    if not active then return nil,'unavailable' end
    local projection=current and 'current' or 'history';local l=layout(projection)
    local bucket=item%l.count;local key=projection..bucket
    if loaded[key]then return loaded[key]end
    if not queued[key]then queued[key]=true;queue[#queue+1]={key=key,bucket=bucket,projection=projection};if not job and #queue==1 then schedule()end end
    return nil,'loading'
end
lookup=function(data,item,key)
    if cfg.representation=='index' then return data[item] and data[item][key],0 end
    local a,b=1,Fixed.Count(data)
    while a<=b do local m=math.floor((a+b)/2);local itemAt,keyAt=Fixed.Key(data,m)
        assert(W.Int(itemAt,1,2147483647) and digest(keyAt),'unsafe lookup key')
        if itemAt==item and keyAt==key then return Fixed.Row(data,m),2,m end
        if itemAt<item or itemAt==item and keyAt<key then a=m+1 else b=m-1 end
    end
    return nil,nil,a
end
local function reserve(item,key)
    local l=layout('current');local bucket=item%l.count;local id='current'..bucket
    if completeAuth[id]then return end
    demands[id]=demands[id] or {};demands[id][#demands[id]+1]={item=item,key=key}
    assert(#demands[id]<=P.MAX_CACHE,'bounded proof demand')
    if not queued[id]then queued[id]=true;queue[#queue+1]={key=id,bucket=bucket,projection='current'};if not job and #queue==1 then schedule()end end
end
function X.setup(client)
    serial=serial+1;loaded,queue,queued,job={},{},{},nil;active=true
    demands,authorized,trees,completeAuth={},{},{},{}
    X.required=nil
    c=client;W=c.TwichUI.Workshop;J,B,Q,P=W.BridgeCodec,W.Bridge,W.Summary,W.Pricing
    clock=function()return os.clock()*1000 end
    cfg=J.Parse(read(assert(arg[12],'experiment config required')));X.selective=cfg.representation=='proof' or cfg.representation=='hybrid' or cfg.representation=='packed-proof' or cfg.representation=='packed-hybrid' or cfg.representation=='fixed-proof' or cfg.representation=='fixed-hybrid';
    if cfg.representation:match('^fixed%-')then cfg.history_count=64 end;
    if X.originalPrepare then P.PrepareBucket=X.originalPrepare else X.originalPrepare=P.PrepareBucket end;fixture=J.ParseSummary(read(cfg.root..'/fixture.json'),nil,1048576);h=fixture.manifest
    stats={loads=0,decodes=0,compile_ms=0,execute_ms=0,validation_ms=0,source_bytes=0,peak_kib=0}
    c.time=function()local _,at=W.BridgeValidate.Time(h.generated_at);return at+60 end
    local function header(projection)
        local out=J.Copy(h);out.partitions=layout('current').descriptors;out.history_partitions=layout('history').descriptors
        out.partitioning.max_partition_bytes=1048576;out.history_partitioning.max_partition_bytes=1048576
        return out
    end
    X.header=header('current');X.historyHeader=header('history')
    local native=cfg.representation=='json' and cfg.count==64 and cfg.history_count==64
    if native then
        c.TwichUIMarketParts={};c.TwichUIMarketHistoryParts={}
        c.C_AddOns.LoadAddOn=function(name)
            local bucket=assert(tonumber(name:match('A(%d%d)$')));local history=name:find('History',1,true)
            local value=load(history and 'history' or 'current',bucket)
            local globals=history and c.TwichUIMarketHistoryParts or c.TwichUIMarketParts
            globals['A'..('%02d'):format(bucket)]=value
            return true
        end
    else
        -- Reuse the real row validator for the JSON experiment. Its only
        -- adaptation is the routing divisor; full production headers remain
        -- exercised by the unchanged 64/64 control above.
        if cfg.representation=='json' then
            assert(cfg.count==cfg.history_count,'JSON control uses equal projection counts')
            local source=read(REPO..'TwichUI_Workshop/Summary.lua');local n
            source,n=source:gsub('r%[1%]%%64==p%.bucket',function()return 'r[1]%'..cfg.count..'==p.bucket'end);assert(n==1)
            source,n=source:gsub('local schedule,startNext','W.ExperimentalRows=rows\nlocal schedule,startNext');assert(n==1)
            local fn=assert(loadstring(source,'@isolated-Summary.lua'));setfenv(fn,c);fn();W.Summary=Q
        end
        B.Begin=function(input)
            local incoming=J.Parse(input.manifest)
            h=J.Copy(h);h.source_watermark=incoming.source_watermark
            -- Generation scenarios use an explicit epoch, never stale callbacks.
            if incoming.generation_id~=h.generation_id then h.generation_id=incoming.generation_id end
            serial=serial+1;loaded,queue,queued,job={},{},{},nil;demands,authorized,trees,completeAuth={},{},{},{};active=true;P.CancelPending();return true
        end
        B.Cancel=function()serial=serial+1;loaded,queue,queued,job={},{},{},nil;active=false;P.CancelPending()end
        B.Status=function()return {ready=true,summary=true,generation=h.generation_id,contract_version=3,failures=0}end
        B.Manifest=function()return J.Copy(h)end
        B.Market=function()return J.Copy(h.market)end
        Q.Pending=function()return job~=nil or #queue>0 end
        Q.Status=function()return {validation_ms=stats.validation_ms,bytes=stats.source_bytes,decoded_parts=stats.loads,current_bytes=0,history_bytes=0,lookup_calls=stats.lookups or 0}end
        B.Record=function(item,key,opt)
            stats.lookups=(stats.lookups or 0)+1
            if X.selective then
                if not active then return nil,'unavailable'end
                local id='current'..(item%layout('current').count)
                if not (completeAuth[id] or authorized[id] and authorized[id][item..':'..key])then reserve(item,key);return nil,'loading'end
            end
            local data,why=part(item,opt and opt.current);if not data then return nil,why end
            local r,o=lookup(data,item,key);if not r then return nil,'not_observed'end
            local function at(i)local v=r[i+o];return v==false and J.NULL or v end
            local function money(i)local v=at(i);return type(v)=='number' and ('%.0f'):format(v) or v end
            return {item_id=item,variant_key=key,summary=true,current={state=h.states[at(1)+1],supply=at(5),complete=true,
                arithmetic_status=at(1)==4 and 'unsupported' or 'supported',observation_ref=0,
                metrics={recent_copper=money(2),market_value_copper=money(3),minimum_copper=money(4),historical_value_copper=money(8)},
                coverage={priced_days_14=at(9),priced_days_60=at(10),observed_days_60=at(11)}}}
        end
        if X.selective then
            local prepare=P.PrepareBucket
            P.PrepareBucket=function(ids,...)
                for _,item in ipairs(ids)do reserve(item)end
                return prepare(ids,...)
            end
        end
    end
    local receipt={schema_version=1,generation_id=h.generation_id,desktop_build='game-ready-experiment',completed_at=h.generated_at}
    local input={summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable(receipt,J.OBJECT))}
    X.native=native
    return h,input,{},{},fixture.semantic_sha256
end
function X.recipes(count)
    local recipes={}
    local output=1000
    for i=1,count do
        repeat output=output+1 until not cfg.native_cohort or output%64<58
        recipes[i]={id=i,name='Synthetic craft '..i,prof=171,filled=true,outItem=output,outMin=1,outMax=1,
            mats={{item=65+i%38,qty=1+i%4},{item=65+(i*7)%38,qty=2+i%3}}}
    end
    local needed={};X.required={}
    for _,r in ipairs(recipes)do needed[r.outItem]=true;for _,m in ipairs(r.mats)do needed[m.item]=true end end
    X.needed=0;local legacy={};local rows={}
    for item in pairs(needed)do local bucket=item%layout('current').count;X.required[bucket]=(X.required[bucket] or 0)+1;X.needed=X.needed+1;legacy[item%64]=true end
    X.buckets=0;for _ in pairs(legacy)do X.buckets=X.buckets+1 end
    for _,r in ipairs(recipes)do rows[#rows+1]=r.id..':'..r.outItem..':'..r.mats[1].item..':'..r.mats[1].qty..':'..r.mats[2].item..':'..r.mats[2].qty end
    X.recipeDigest=J.SHA(table.concat(rows,';'))
    return recipes
end
function X.observe(view,elapsed,cpu,out)
    if out.experiment_visible_model_seconds then return end
    local n=math.min(12,#view.all);if n==0 then return end
    for i=1,n do local r=view.all[i];if not(r.done and r.owner:Valid(r))then return end end
    out.experiment_visible_rows=n;out.experiment_visible_model_seconds=elapsed;out.experiment_visible_cpu_ms=cpu
end
function X.finish(out,event)
    out.experiment_representation=cfg.representation;out.experiment_current_partitions=cfg.count;out.experiment_history_partitions=cfg.history_count
    out.experiment_production_reader=X.native;out.experiment_loads=stats.loads;out.experiment_decodes=X.native and out.decodes or cfg.representation=='json' and stats.decodes or stats.loads
    out.experiment_validation_jobs=stats.decodes
    out.experiment_compile_ms=stats.compile_ms;out.experiment_execute_ms=stats.execute_ms
    out.experiment_current_validation_ms=X.native and out.validation_ms or stats.validation_ms
    out.experiment_current_initialization_ms=stats.compile_ms+stats.execute_ms+out.experiment_current_validation_ms
    out.experiment_source_bytes=stats.source_bytes;out.experiment_worst_part_source_bytes=layout('current').max_source_bytes
    out.experiment_fixture_records=fixture.records;out.experiment_profile=fixture.profile;out.experiment_days=fixture.history_days
    out.experiment_source_generation=h.generation_id
    out.experiment_recipe_sha256=X.recipeDigest;out.experiment_distinct_items=X.needed;out.experiment_requested_legacy_buckets=X.buckets
    out.experiment_bulk_authentications=stats.bulk_authentications or 0;out.experiment_authenticated=stats.authenticated or 0;out.experiment_proof_hashes=stats.proof_hashes or 0
    out.experiment_worst_load_ms=stats.worst_load_ms or 0
    -- Cheap service-only warm lookup measurement. Production P still owns its
    -- bounded price cache and the actual OpportunityEngine/Estimate are intact.
    local at=clock();for i=1,1000 do P.Price(65+i%38)end;out.experiment_warm_1000_prices_ms=clock()-at
    if cfg.history_probe then
        local beforeLoads=stats.loads;local beforeCompile,beforeExecute=stats.compile_ms,stats.execute_ms
        local beforeValidation=X.native and Q.Status().validation_ms or stats.validation_ms
        collectgarbage('collect');local base=collectgarbage('count');stats.peak_kib=base;stats.worst_load_ms=0;at=clock()
        local item=cfg.history_item or 1001;local key=P.BaseKey(item);local series,why
        if X.native then
            series,why=B.History(item,key,'recent',{days=60})
            while why=='loading' do event();series,why=B.History(item,key,'recent',{days=60})end
            assert(series and #series.points==fixture.history_days)
        else
            local data;data,why=part(item,false)
            while why=='loading' do event();data,why=part(item,false)end
            local r,o=lookup(data,item,key);assert(r and #r[o+12]==fixture.history_days)
        end
        out.experiment_history_cpu_ms=clock()-at
        out.experiment_history_loads=stats.loads-beforeLoads
        out.experiment_history_compile_ms=stats.compile_ms-beforeCompile;out.experiment_history_execute_ms=stats.execute_ms-beforeExecute
        out.experiment_history_validation_ms=(X.native and Q.Status().validation_ms or stats.validation_ms)-beforeValidation
        out.experiment_history_sampled_peak_delta_kib=stats.peak_kib-base
        at=clock();collectgarbage('collect');out.experiment_history_gc_ms=clock()-at
        out.experiment_history_retained_delta_kib=collectgarbage('count')-base
        out.experiment_history_worst_load_ms=stats.worst_load_ms
    end
end
return X
