-- Shared producer vectors; actual production queue, proof reader and Pricing.
local function client(layout)
    local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop
    local J,B,Q,P=W.BridgeCodec,W.Bridge,W.Summary,W.Pricing
    local f=assert(io.open(TESTS..'fixtures/workshop_prepared_v1/synthetic.json'));local fixture=J.Parse(f:read('*a'));f:close()
    local s={c=c,W=W,J=J,B=B,Q=Q,P=P,fixture=fixture,events={},loads={},layout=layout or 16}
    c.C_Timer.After=function(_,fn)s.events[#s.events+1]=fn end
    c.GetTimePreciseSec=function()return s.wall or 0 end
    c.InCombatLockdown=function()return s.combat==true end
    c.UnitFactionGroup=function()return 'Horde'end
    local _,at=W.BridgeValidate.Time(fixture.manifest.generated_at);c.time=function()return at+60 end
    c.TwichUIMarketCurrentParts={};c.TwichUIMarketHistoryParts={}
    W.UI.Redraw=function()end
    function s.tick()
        local events=s.events;s.events={};s.wall=(s.wall or 0)+1/60
        for _,fn in ipairs(events)do fn()end
    end
    function s.drain()
        for _=1,20000 do if #s.events==0 then assert(not Q.Pending());return end;s.tick()end
        error('unbounded prepared queue')
    end
    c.C_AddOns.LoadAddOn=function(name)
        s.loads[#s.loads+1]=name
        local bank,bucket=name:match('Part([AB])(%d%d)$');bucket=tonumber(bucket)
        if name:find('History',1,true)then
            c.TwichUIMarketHistoryParts[bank..('%02d'):format(bucket)]=fixture.parts[tostring(bucket+64)]
        else
            local p=s.prepared.partitions[bucket+1];local payload=s.payloads[tostring(bucket)]
            c.TwichUIMarketCurrentParts[bank..('%02d'):format(bucket)]={version=1,layout=s.layout,content_id=p.sha256,data=payload[1],proofs=payload[2]}
        end
        return true
    end
    function s.begin(bank,mutate)
        local h=J.Copy(fixture.manifest);h.synthetic=false;for _,o in ipairs(h.observations)do o.synthetic=false end
        h.source_watermark=tostring(902+(s.serial or 0));s.serial=(s.serial or 0)+1
        local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
        s.prepared=J.Copy(fixture.layouts[tostring(s.layout)].attestation);s.payloads=J.Copy(fixture.layouts[tostring(s.layout)].payloads)
        s.prepared.source_generation_id=h.generation_id
        body=J.Copy(s.prepared);body.attestation_id=nil;s.prepared.attestation_id=J.SHA(J.Encode(body))
        s.root={summary_version=2,bank=bank or 'A',manifest=J.Encode(h),prepared=J.Encode(s.prepared),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='prepared-test',completed_at=h.generated_at},J.OBJECT))}
        if mutate then mutate(s.root)end
        B.Begin(s.root);s.drain();return h
    end
    s.begin();assert(B.Status().ready and B.Status().prepared_version==1)
    return s
end
for _,layout in ipairs({16,32})do
    local s=client(layout);local B,P,Q,J=s.B,s.P,s.Q,s.J
    assert(#s.loads==0,'metadata eagerly loaded prices')
    assert(not P.Price(2589));s.drain();assert(P.Price(2589).price==120)
    assert(#s.loads==1 and B.Status().history_loaded_parts==0 and B.Status().decoded_current_rows==0)
    local hashes=B.Status().prepared.hashes
    for _=1,20 do assert(P.Price(2589).price==120);assert(B.Value(2589,P.BaseKey(2589)).value==120)end
    assert(B.Status().prepared.hashes==hashes,'warm hit repeated cryptography')
    local variants,why=B.Variants(2589);assert(not variants and why=='loading');s.drain()
    variants,why=B.Variants(2589);assert(#variants==3 and not why)
    local truncated;variants,truncated=B.Variants(2589,1);assert(#variants==1 and truncated)
    for _,key in ipairs(variants)do assert(B.Record(2589,key,{current=true}))end
    assert(not B.Record(2589,string.rep('1',64),{current=true}));s.drain()
    local _,missing=B.Record(2589,string.rep('1',64),{current=true});assert(missing=='not_observed')
    -- Empty physical bucket is authoritative and needs no addon load/proof.
    local loads=#s.loads;local _,empty=B.Record(64,P.BaseKey(64),{current=true});assert(empty=='not_observed'and #s.loads==loads)
    P.Price(123);P.Price(9001);s.drain();assert(P.PendingCount()==0 and not P.Price(123)and not P.Price(9001))
    local record=assert(B.Record(123,P.BaseKey(123),{current=true}));assert(record.current.state=='supply_only'and record.current.supply==3)
    assert(not B.History(2589,P.BaseKey(2589)));s.drain()
    local history=assert(B.History(2589,P.BaseKey(2589)));assert(history.points[#history.points].v==120 and B.Status().history_loaded_parts==1)
    local items={};local ok=B.EachItem(function(id)items[id]=true end,function()s.tick()end)
    assert(ok and items[2589]and items[123]and items[9001]);assert(B.Status().prepared.flag_words==0 and B.Status().prepared.full==3)
    assert(B.Status().parts==layout)
end
-- Independent prices are released before other tuples and without full verification.
local s=client();local P,B,Q=s.P,s.B,s.Q
Q.RESUMES=1
local owner={};P.PrepareBucket({2589},nil,owner);P.PrepareBucket({123},nil,owner)
local progressed=false
for _=1,2000 do
    s.tick()
    if P.Settled(2589)or P.Settled(123)then
        assert(not(P.Settled(2589)and P.Settled(123)),'whole job gated independent prices');progressed=true;break
    end
end
assert(progressed and B.Status().prepared.full==0);s.drain();assert(P.PendingCount()==0)
-- Releasing one owner preserves another consumer's lease and cancels unused work.
s=client();P,B,Q=s.P,s.B,s.Q
local a,b={},{};P.PrepareBucket({2589},nil,a);P.PrepareBucket({2589},nil,b)
P.ReleasePreparation(a);assert(P.PendingCount()==1);s.drain();assert(P.Price(2589).price==120)
P.PrepareBucket({123},nil,a);P.ReleasePreparation(a);s.drain();assert(P.PendingCount()==0 and not P.Settled(123))
P.PrepareBucket({123},nil,a);P.Price(123);P.ReleasePreparation(a);s.drain();assert(P.Settled(123),'shared direct consumer was cancelled')
-- Cancelled callbacks and generations never publish old reservations.
s=client();P,B,Q=s.P,s.B,s.Q
Q.RESUMES=1;P.Price(2589);s.tick();Q.Cancel();s.drain();assert(P.PendingCount()==0)
P.Price(2589);s.begin('B');assert(P.PendingCount()==0);P.Price(2589);s.drain();assert(P.Price(2589).price==120)
-- Combat terminates queued work, doesn't load addons, and can retry on normal activity.
s=client();P,B,Q=s.P,s.B,s.Q
P.Price(2589);s.combat=true;s.drain();assert(P.PendingCount()==0 and #s.loads==0 and not P.Settled(2589))
s.combat=false;P.Price(2589);s.drain();assert(P.Price(2589).price==120)
-- Corrupt payloads never release a price; same-generation globals cannot replace captured strings.
for _,kind in ipairs({'price','proof','truncated','identity'})do
    s=client();P,B,Q=s.P,s.B,s.Q
    local payload=s.payloads['13']
    if kind=='price'then payload[1]=payload[1]:sub(1,208)..'00000003e7'..payload[1]:sub(219)
    elseif kind=='identity'then payload[1]=payload[1]:sub(1,135)..'ffffffff'..payload[1]:sub(144)
    elseif kind=='proof'then payload[2]=string.rep('0',#payload[2])
    else payload[1]=payload[1]:sub(2)end
    P.Price(2589);s.drain();assert(not B.Status().ready and P.PendingCount()==0,'corruption accepted: '..kind)
end
s=client();P,B=s.P,s.B;P.Price(2589);s.drain()
s.c.TwichUIMarketCurrentParts.A13.data=string.rep('0',405)
assert(B.Value(2589,P.BaseKey(2589)).value==120,'mutable global changed a captured authenticated record')
-- Rehashed incompatible metadata refuses the candidate, retaining last good.
local generation=B.Status().generation
s.begin('B',function(root)local a=s.J.Parse(root.prepared);a.record_width=134;local body=s.J.Copy(a);body.attestation_id=nil;a.attestation_id=s.J.SHA(s.J.Encode(body));root.prepared=s.J.Encode(a)end)
assert(B.Status().generation==generation and P.Price(2589).price==120)
print('PASSED prepared 16/32 vectors, exact/missing proofs, public APIs, partial prices, leases, combat, cancellation, generations and corruption')
