-- Offline A2 diagnostic sample. Existing reader counters and mock handlers, no client profiler.
-- Invoked by tools/measure_market_a2.py; trusted locally generated fixtures only.
local J,B,S,W,c,A
local out
local function ms(fn)
    local at=os.clock();fn();return (os.clock()-at)*1000
end
local function heap() return collectgarbage('count')*1024 end
local function fingerprint(v)
    if type(v)~='table' then return tostring(v) end
    local keys={};for k in pairs(v) do keys[#keys+1]=k end
    table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    local t={};for _,k in ipairs(keys) do t[#t+1]=tostring(k)..'='..fingerprint(v[k]) end
    return '{'..table.concat(t,',')..'}'
end
collectgarbage('collect');local base=heap()
local startup=ms(function() c=dofile(TESTS..'auction_mock.lua') end)
W=c.TwichUI.Workshop;J,B,S,A=W.BridgeCodec,W.Bridge,W.BridgeValidate,W.AuctionUI
c.GetTimePreciseSec=os.clock
out=J.Object();out.mock_workshop_load_ms=startup
collectgarbage('collect');out.mock_workshop_retained_bytes=heap()-base
assert(not B.Status().loading and not B.Status().ready and not c.TwichUIMarketData)
local saved=fingerprint(c.TwichUIDB)..fingerprint(c.TwichUIWorkshopDB)
c.C_AuctionHouse=setmetatable({},{__index=function()error('forbidden AH operation')end})
c.ReloadUI=function()error('forbidden reload')end
local fn
base=heap()
out.compile_ms=ms(function() fn=assert(loadfile(arg[1]));setfenv(fn,c) end)
out.assign_ms=ms(function() fn() end);fn=nil
local raw=c.TwichUIMarketData
local peak=heap();local drops=0;local previous=peak
local function drain(good)
    local durations={};local done=false
    for i=1,200000 do
        local ok,why
        durations[#durations+1]=ms(function() ok,why=B.Step() end)
        local h=heap();peak=math.max(peak,h);if h<previous then drops=drops+1 end;previous=h
        if why~='loading' then assert(ok==good,tostring(why));done=true;break end
    end
    assert(done,'validation deadline');table.sort(durations)
    return durations
end
local times
out.harness_load_cpu_ms=ms(function() B.Begin(raw);times=drain(true) end)+out.compile_ms+out.assign_ms
local stats=B.Status()
out.validation_ms=stats.validation_ms;out.slices=stats.slices;out.resumes=stats.resumes
out.slice_p95_ms=times[math.ceil(#times*.95)];out.slice_p99_ms=times[math.ceil(#times*.99)]
out.worst_slice_ms=stats.largest_slice_ms;out.sampled_peak_delta_bytes=peak-base
out.heap_drops=drops -- observed net drops, not a count of GC cycles
times=nil;collectgarbage('collect');out.payload_retained_bytes=heap()-base
local key=B.Variants(10001)[1]
out.first_record_ms=ms(function() assert(B.Record(10001,key).current.metrics.recent_copper=='100') end)
out.history_ms=ms(function() assert(#B.History(10001,key,'recent').points==tonumber(arg[3])) end)
out.all_records_ms=ms(function() B.EachItem(function(id) B.Record(id,B.Variants(id)[1]) end) end)
collectgarbage('collect');out.warm_retained_bytes=heap()-base;out.cache_entries=B.Status().cache_entries
-- Separate diagnostic passes with no tick, nested totals are deliberately not additive.
local records,header,ctx={},nil,nil
out.parse_records_ms=ms(function() for i,text in ipairs(raw.records) do records[i]=J.Parse(text) end end)
out.header_total_ms=ms(function() header=J.Parse(raw.manifest,nil,256*1024);ctx=S.Header(header) end)
out.record_total_ms=ms(function() for _,r in ipairs(records) do S.Record(ctx,r) end end)
out.schema_records_ms=ms(function() for _,r in ipairs(records) do S.Schema(ctx.plan.properties.records.items,r) end end)
out.encode_records_ms=ms(function() for i,r in ipairs(records) do assert(J.Encode(r)==raw.records[i]) end end)
out.hash_record_and_identity_ms=ms(function() for i,r in ipairs(records) do
    assert(J.SHA(raw.records[i])==header.scope.record_sha256[i]);assert(J.SHA(r.variant_json)==r.variant_key)
end end)
out.two_record_stream_hashes_ms=ms(function()
    local one,two=J.Hash(),J.Hash();one:Update('[');two:Update('[')
    for i,text in ipairs(raw.records) do local piece=(i>1 and ',' or '')..text;one:Update(piece);two:Update(piece) end
    one:Update(']');two:Update(']');assert(one:Finish()==header.integrity.records_sha256);two:Finish()
end)
records,header,ctx=nil,nil,nil;collectgarbage('collect')
assert(saved==fingerprint(c.TwichUIDB)..fingerprint(c.TwichUIWorkshopDB))
-- Reuse actual Market handler fixtures; initialization/fixture construction is untimed.
dofile(TESTS..'auction_market_fixture.lua')(c)
saved=fingerprint(c.TwichUIDB)..fingerprint(c.TwichUIWorkshopDB)
local function settle()
    for i=1,3000 do FlushTimers();local p=A.Page('market');if p and not p.job and not B.Status().loading then return end end
    error('Market did not settle')
end
A.Show('market');settle();assert(A.OpenMarket(10001,{market='server',serverVariant=key}));settle()
local pages=A.Snapshot().pages;local slices=B.Status().slices
collectgarbage('collect');local uiBase=heap();local worst=0
out.ui_50_cycles_ms=ms(function() for i=1,50 do
    local elapsed=ms(function()
        A.Hide();A.Show('market');assert(A.OpenMarket(10001,{market='server',serverVariant=key}));settle()
        assert(#B.History(10001,key,'recent').points==tonumber(arg[3]))
    end);worst=math.max(worst,elapsed)
end end)
collectgarbage('collect');out.ui_retained_growth_bytes=heap()-uiBase;out.ui_worst_cycle_ms=worst
assert(A.Snapshot().pages==pages and B.Status().slices==slices and B.Status().cache_entries<=24)
-- Hidden view cancels its rendering, not the independent bridge. Suspend cancels the bridge.
B.Begin(raw);B.Load();A.Hide();FlushTimers();out.validation_continues_hidden=B.Status().slices>slices
assert(out.validation_continues_hidden and B.Status().loading)
W.Suspend();local stopped=B.Status().slices;FlushTimers();FlushTimers()
assert(not B.Status().loading and B.Status().slices==stopped);out.suspend_cancels=true
local old=B.Status().generation
fn=assert(loadfile(arg[2]));setfenv(fn,c);fn();fn=nil
local bad=c.TwichUIMarketData
local before=B.Status()
local corruptTimes
out.corrupt_cpu_ms=ms(function() B.Begin(bad);corruptTimes=drain(false) end)
out.corrupt_worst_slice_ms=corruptTimes[#corruptTimes]
out.corrupt_validation_ms=B.Status().validation_ms-before.validation_ms
assert(B.Status().generation==old and B.Status().ready and B.Record(10001,key))
out.previous_generation_retained=true
local failures=B.Status().failures
W.suspended=false;B.Load();assert(not B.Status().loading and B.Status().failures==failures)
out.rejected_not_retried=true
assert(saved==fingerprint(c.TwichUIDB)..fingerprint(c.TwichUIWorkshopDB))
-- Bridge JSON intentionally accepts integers only; diagnostic timings are fractional.
local keys,parts={},{}
for k in pairs(out) do keys[#keys+1]=k end;table.sort(keys)
for _,k in ipairs(keys) do
    local v=out[k];parts[#parts+1]=J.Encode(k)..':'..(type(v)=='number' and ('%.6f'):format(v) or J.Encode(v))
end
print('{'..table.concat(parts,',')..'}')
