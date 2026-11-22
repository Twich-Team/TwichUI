-- Production reader/pricing lifecycle, synthetic schema-2 data. No native timing claim.
local function client()
    local c=dofile(TESTS..'auction_mock.lua')
    local W=c.TwichUI.Workshop;local P,B,J,Q=W.Pricing,W.Bridge,W.BridgeCodec,W.Summary
    local f=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'))
    local fixture=J.Parse(f:read('*a'));f:close()
    local h=fixture.manifest;h.synthetic=false
    for _,o in ipairs(h.observations)do o.synthetic=false end
    h.partitions=J.Array();h.record_count=64;h.coverage.source_records=64;h.coverage.delivered_records=64
    local template=J.Parse(fixture.parts['29'])[1]
    local raw,keys={},{}
    for b=0,63 do
        local row=J.Copy(template);row[1]=64+b;row[2]=P.BaseKey(row[1])
        if b==1 then row[2]=J.SHA('modified identity') end
        keys[64+b]=row[2];raw[b]=J.Encode(setmetatable({row},J.ARRAY))
        h.partitions[#h.partitions+1]=setmetatable({bucket=b,bytes=#raw[b],record_count=1,sha256=J.SHA(raw[b])},J.OBJECT)
    end
    local s={cpu=0,events={},perf={},draws=0,h=h,raw=raw,keys=keys,c=c,W=W,P=P,B=B,Q=Q,J=J}
    local _,at=W.BridgeValidate.Time(h.generated_at);s.now=at+60
    c.time=function()return s.now end;c.UnitFactionGroup=function()return 'Horde' end
    c.InCombatLockdown=function()return s.combat==true end
    c.GetTimePreciseSec=function()return s.cpu end
    c.C_Timer.After=function(_,fn)s.events[#s.events+1]=fn end
    c.TwichUIMarketParts={}
    W.UI.Redraw=function()s.draws=s.draws+1 end
    function s.tick()
        local events=s.events;s.events={}
        for _,fn in ipairs(events)do fn() end
    end
    function s.drain()
        for _=1,20000 do if #s.events==0 then assert(not Q.Pending());return end;s.tick() end
        error('unbounded retry/notification loop')
    end
    function s.begin(bank,watermark,bad)
        h.source_watermark=tostring(watermark);h.source_observation.observation_id=tostring(watermark)
        h.observations[2].observation_id=tostring(watermark)
        for b=0,63 do
            h.partitions[b+1].bytes=#raw[b];h.partitions[b+1].sha256=J.SHA(raw[b])
            c.TwichUIMarketParts[bank..('%02d'):format(b)]=bad and b==0 and '[]' or raw[b]
        end
        local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
        B.Begin({summary_version=1,bank=bank,manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='pending-test',completed_at=h.generated_at},J.OBJECT))})
    end
    s.begin('A',902);s.drain();assert(B.Status().ready)
    c.TwichUI.Perf.on=true
    c.TwichUI.Perf.Count=function(id,n)s.perf[id]=(s.perf[id] or 0)+(n or 1)end
    local read=B.Record
    B.Record=function(...)s.cpu=s.cpu+0.001;return read(...)end -- one modeled millisecond per indivisible read
    return s
end
local function metric(s,key)return s.perf['workshop.pricing.'..key] or 0 end
local function request(s,id)return s.P.Price(id)end

-- Two consumers and redraws coalesce; both successful and missing exact identities settle.
local s=client()
for id=64,127 do request(s,id) end
for _=1,20 do for id=64,127 do request(s,id);s.P.Reference(id) end end
assert(metric(s,'readerCalls')==64 and metric(s,'baseKeys')==64)
assert(metric(s,'deduplicated')>=2560 and s.P.PendingCount()==64)
s.drain()
assert(s.Q.Status().checked_parts==64 and s.P.PendingCount()==0 and s.P.CacheSize()==64)
assert(metric(s,'readerCalls')==128 and metric(s,'baseKeys')==64)
for id=64,127 do
    local p=request(s,id)
    assert(id==65 and not p or id~=65 and p.price==120)
end
assert(not s.P.Price(64,{variant=true}),'native variants cannot inherit the base reference')
assert(metric(s,'readerCalls')==128,'warm compact references queried the reader')
assert((s.Q.Status().largest_completion_ms or 0)<=2.000001,'completion ignored modeled elapsed budget')
assert((s.perf['workshop.summary.decodeStarts'] or 0)==64)
assert(not s.perf['workshop.summary.decodeRepeats'])

-- Related completion requests produce one downstream refresh; unchanged decoding
-- does not revise estimator identity or publish another completion.
local generation=s.P.Generation();local draws=s.draws;local notified=metric(s,'notifications')
for _=1,50 do s.P.Notify() end
s.drain();assert(s.draws==draws+1 and metric(s,'notifications')==notified+1)
assert(s.P.Generation()==generation)
s.P.Decoded(63,function()error('no pending work should yield')end);s.drain()
assert(s.draws==draws+1 and s.P.Generation()==generation)

-- Capacity includes pending + resolved identities. Each bucket has >16 waiting.
for id=128,8255 do request(s,id) end
local p,why=request(s,8256);assert(not p and why=='lookup_limit')
assert(s.P.PendingCount()+s.P.CacheSize()==8192)
s.drain()
assert(s.P.PendingCount()==0 and s.P.CacheSize()==8192)
assert(metric(s,'readerCalls')<=16384 and metric(s,'baseKeys')==8192)
assert((s.perf['workshop.summary.decodeStarts'] or 0)<=128,'large handoff repeated decodes within its request batch')
assert(s.Q.Status().largest_completion_ms<=3.001,'completion exceeded budget plus one indivisible read')
assert(s.Q.Status().decoded_parts==1,'handoff retained multiple decoders')
local draws=s.draws;s.drain();assert(s.draws==draws)

-- Cancellation/replace while transferring releases old reservations, including reads during header validation.
s=client()
for n=1,40 do request(s,64*n) end
s.tick();s.tick();assert(s.P.PendingCount()>0 and s.P.PendingCount()<40)
request(s,66) -- another page/consumer requests a different bucket mid-handoff
assert(s.perf['workshop.summary.decodeStarts']==1,'new consumer evicted a handoff decoder')
s.Q.Cancel();assert(s.P.PendingCount()==0);s.drain()
for n=1,40 do request(s,64*n) end
s.begin('B',903);request(s,5001);s.drain();assert(s.P.PendingCount()==0)
local row=s.J.Parse(s.raw[0]);row[1][4]='240';s.raw[0]=s.J.Encode(row)
s.begin('A',904);s.drain();request(s,64);s.drain();assert(request(s,64).price==240)
local good=s.B.Status().generation
s.begin('B',905,true);s.drain();request(s,64);s.drain()
assert(s.B.Status().generation==good and request(s,64).price==240,'corrupt part failed last-good rollback')
assert(s.P.PendingCount()==0)

-- A queued combat refusal releases reservations, then can be retried after combat.
s=client();request(s,64);request(s,66);s.combat=true;s.drain()
assert(s.P.PendingCount()==0)
local _,why=request(s,66);assert(why=='combat')
s.combat=false;request(s,66);s.drain();assert(request(s,66).price==120)
s.now=s.now+86401;local _,why=request(s,64);assert(why=='stale','stale cache bypassed admission')

-- Completion revision changes even when checked_parts is already stable. A
-- fallback question memoized before arrival must not survive that completion.
s=client()
for id=64,127 do s.B.Record(id,s.keys[id]);s.drain() end
assert(s.Q.Status().checked_parts==64 and s.P.CacheSize()==0)
local before=s.P.Generation();local est=s.W.Session.Estimator(s.P.Source())
est:Ask('cost',64,1);s.drain()
assert(s.Q.Status().checked_parts==64 and s.P.Generation()~=before)
assert(s.W.Session.Estimator(s.P.Source())~=est,'completion retained stale fallback memo')
assert(request(s,64).price==120 and s.P.PendingCount()==0)
print('PASSED pending coalescing, 64 buckets, 8192 identities, budget, cancellation, combat, stale, revision and rollback')
