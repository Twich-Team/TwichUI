-- Production reader/queue; real existing offline Deflate library. This is not
-- native Forever timing. Producer-file interoperability runs separately.
local D=dofile(ROOT..'libs/LibDeflate/LibDeflate.lua')
local function client()
    local c=dofile(TESTS..'auction_mock.lua');local W=c.TwichUI.Workshop
    local J,B,P,Q=W.BridgeCodec,W.Bridge,W.Pricing,W.Summary
    local f=assert(io.open(TESTS..'fixtures/workshop_prepared_v1/synthetic.json'));local v=J.Parse(f:read('*a'));f:close()
    local s={c=c,W=W,J=J,B=B,P=P,Q=Q,v=v,events={},loads={},inflates=0,wire={},serial=0}
    c.C_Timer.After=function(_,fn)s.events[#s.events+1]=fn end
    c.GetTimePreciseSec=function()return s.wall or 0 end;c.InCombatLockdown=function()return s.combat end
    c.Enum={CompressionMethod={Deflate=0}}
    c.C_EncodingUtil={DecodeBase64=function(text)return s.wire[text]end,
        DecompressString=function(raw,method)assert(method==0);s.inflates=s.inflates+1;return D:DecompressDeflate(raw)end}
    c.UnitFactionGroup=function()return 'Horde'end;W.UI.Redraw=function()end
    local _,at=W.BridgeValidate.Time(v.manifest.generated_at);c.time=function()return at+60 end
    function s.block(text)
        if #text==0 then return {}end
        s.serial=s.serial+1;local id=('%08d'):format(s.serial);s.wire[id]=D:CompressDeflate(text)
        return {{bytes=#text,payload=id}}
    end
    function s.tick()
        local list=s.events;s.events={};s.wall=(s.wall or 0)+1/60
        for _,fn in ipairs(list)do
            local before=s.inflates;fn();assert(s.inflates-before<=1,'multiple inflates in one scheduled callback')
        end
    end
    function s.drain()for _=1,20000 do if #s.events==0 then assert(not Q.Pending());return end;s.tick()end;error('unbounded compressed work')end
    c.C_AddOns.LoadAddOn=function(name)
        s.loads[#s.loads+1]=name
        local kind,bank,group=name:match('^TwichUI_Market(%a+)Container([AB])(%d%d)$');assert(kind and tonumber(group)<(kind=='Current'and 2 or 4));group=tonumber(group)
        local global=kind=='Current'and 'TwichUIMarketCompressedCurrent'or 'TwichUIMarketCompressedHistory'
        c[global]=c[global]or {}
        for bucket=group*16,group*16+15 do
            local p=s.a.partitions[bucket+1]
            if kind=='Current'then
                local values=v.layouts['32'].payloads[tostring(bucket)]
                local blob={version=1,generation=s.h.generation_id,content_id=p.sha256,data=s.block(values[1]),proofs=s.block(values[2])}
                if s.mutate then s.mutate(blob,bucket)end;c[global][bank..('%02d'):format(bucket)]=blob
            else
                for _,p in ipairs(s.h.history_partitions)do if p.bucket==bucket then
                    c[global][bank..('%02d'):format(bucket)]={version=1,generation=s.h.generation_id,content_id=p.sha256,data=s.block(v.parts[tostring(bucket+64)])}
                end end
            end
        end
        return true
    end
    function s.begin(bank)
        s.h=J.Copy(v.manifest);s.h.synthetic=false;for _,o in ipairs(s.h.observations)do o.synthetic=false end
        s.h.source_watermark=tostring(1000+s.serial);s.serial=s.serial+1
        local body=J.Copy(s.h);body.generation_id=nil;s.h.generation_id=J.SHA(J.Encode(body))
        s.a=J.Copy(v.layouts['32'].attestation);s.a.source_generation_id=s.h.generation_id
        body=J.Copy(s.a);body.attestation_id=nil;s.a.attestation_id=J.SHA(J.Encode(body))
        s.root={summary_version=3,bank=bank or 'A',manifest=J.Encode(s.h),prepared=J.Encode(s.a),receipt=J.Encode(setmetatable({schema_version=1,generation_id=s.h.generation_id,desktop_build='container-test',completed_at=s.h.generated_at},J.OBJECT))}
        B.Begin(s.root);s.drain()
    end
    s.begin();assert(B.Status().ready);return s
end
local s=client()
assert(#s.loads==0 and s.inflates==0,'TOC/header decompressed data')
assert(not s.P.Price(2589));s.drain();assert(s.P.Price(2589).price==120)
assert(#s.loads==1 and s.inflates==2 and s.B.Status().history_loaded_parts==0)
local count=s.inflates
for _=1,20 do assert(s.P.Price(2589).price==120)end
assert(s.inflates==count,'warm price inflated again')
s.P.Price(123);s.drain();assert(#s.loads==1,'same physical container loaded twice')
assert(not s.B.History(2589,s.P.BaseKey(2589)));s.drain()
local history=assert(s.B.History(2589,s.P.BaseKey(2589)));assert(history.points[#history.points].v==120)
count=s.inflates;assert(s.B.History(2589,s.P.BaseKey(2589)));assert(s.inflates==count)
local _,missing=s.B.Record(64,s.P.BaseKey(64),{current=true});assert(missing=='not_observed')
-- Old queued completions cannot settle a replacement generation.
s.P.Price(9001);s.begin('B');s.P.Price(2589);s.drain();assert(s.P.Price(2589).price==120)
s=client();s.P.Price(2589);s.Q.Cancel();s.drain();assert(s.inflates==0)
s.P.Price(2589);s.drain();assert(s.P.Price(2589).price==120)
for mutation=1,7 do
    s=client();s.mutate=function(blob,bucket)if bucket~=2589%32 then return end
        if mutation==1 then blob.generation=string.rep('f',64)
        elseif mutation==2 then blob.content_id=string.rep('f',64)
        elseif mutation==3 then blob.data[1].bytes=524289
        elseif mutation==4 then blob.data[1].payload=string.rep('A',700004)
        elseif mutation==5 then blob.data[1].payload='!!!!'
        elseif mutation==6 then local id=blob.data[1].payload;s.wire[id]=s.wire[id]:sub(1,2)
        else blob.unexpected=true end
    end
    assert(not s.P.Price(2589));s.drain();assert(not s.P.Price(2589),'corruption yielded price')
    assert(s.B.Status().reload_required,'corruption not reported')
end
s=client();s.c.C_EncodingUtil.DecompressString=function(raw)return raw end
s.P.Price(2589);s.drain();assert(not s.P.Price(2589),'identity stub passed')
s=client();s.c.C_EncodingUtil=nil;s.P.Price(2589);s.drain();assert(not s.P.Price(2589))
s=client();s.combat=true;local _,why=s.B.Record(2589,s.P.BaseKey(2589),{current=true});assert(why=='combat'and s.inflates==0)
assert(s.W.Containers.BLOCK_BYTES==524288)
print('TEST PASSED: bounded compressed containers, authentication, lazy history, warm reuse and cancellation')
