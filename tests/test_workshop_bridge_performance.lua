-- Deterministic work/identity tests, not fragile wall-clock assertions.
TwichUI={Workshop={}}
TwichUIWorkshopDB={markets={keep={items={[1]="original"}}}}
for _,name in ipairs({"Data","BridgeCodec","BridgeSchema","BridgeValidate","Bridge"})do dofile(REPO.."TwichUI_Workshop/"..name..".lua")end
local W=TwichUI.Workshop;local J,B=W.BridgeCodec,W.Bridge
assert(J.Encode('a"b\\c\n')=='"a\\"b\\\\c\\n"',"short quoting fast path escaped unsafely")
assert(J.Encode("\240\159\152\128")=='"\\ud83d\\ude00"',"Unicode canonical form changed")
assert(not pcall(J.Parse,'"'..string.char(1)..'"'),"ASCII-run parser accepted a raw control")
assert(not pcall(J.Parse,'"'..string.char(255)..'"'),"ASCII-run parser accepted raw non-ASCII")
local ticks=0
local text=string.rep("a",32768)
assert(J.Encode(text,function()ticks=ticks+1 end)=='"'..text..'"')
assert(ticks>=256,"long string encoding no longer yields bounded units")
ticks=0;assert(J.Parse('"'..text..'"',function()ticks=ticks+1 end)==text)
assert(ticks>=256,"long string parsing no longer yields bounded units")
ticks=0;J.Encode(string.rep("\240\159\152\128",2048),function()ticks=ticks+1 end)
assert(ticks>=64,"multibyte quoting no longer yields")
local deep=0;for i=1,13 do deep=setmetatable({deep},J.ARRAY)end
assert(not pcall(J.Encode,deep),"canonical encoder depth bound changed")
local file=assert(io.open(TESTS.."fixtures/market_bridge_v1/source-canonical-generation.json"))
local g=J.Parse(file:read("*a"));file:close()
local template=J.Copy(g.records[2]);g.records={g.records[1]};setmetatable(g.records,J.ARRAY)
for i=1,256 do
    local r=J.Copy(template)
    r.variant_json='{"id":2589,"slot":'..i..'}';r.variant_key=J.SHA(r.variant_json)
    g.records[#g.records+1]=r
end
local other=J.Copy(template);other.item_id=3000;other.variant_json='{"id":3000}';other.variant_key=J.SHA(other.variant_json);g.records[#g.records+1]=other
table.sort(g.records,function(a,b)return a.item_id<b.item_id or a.item_id==b.item_id and a.variant_key<b.variant_key end)
g.record_count=#g.records
local body=J.Copy(g);body.generation_id=nil;body.integrity=nil
local header=J.Copy(body);header.records=nil
g.generation_id=J.SHA(J.Encode(body))
g.integrity=setmetatable({records_bytes=#J.Encode(g.records),records_sha256=J.SHA(J.Encode(g.records)),manifest_sha256=J.SHA(J.Encode(header))},J.OBJECT)
local h=J.Copy(g);h.records=nil
local raw={transport_version=1,manifest=J.Encode(h),records={},receipt=J.Encode(setmetatable({schema_version=1,generation_id=g.generation_id,desktop_build="synthetic-work-budget",completed_at="2026-11-15T13:00:00Z"},J.OBJECT))}
for i,r in ipairs(g.records)do raw.records[i]=J.Encode(r)end
local resume=coroutine.resume;local calls=0
coroutine.resume=function(...)calls=calls+1;return resume(...)end
GetTimePreciseSec=function()return 0 end
B.Begin(raw);B.Step(3)
assert(calls<=512 and B.Status().loading,"clock-backed deterministic work cap changed")
local function drain(good)
    for i=1,100000 do local ok,why=B.Step(3);if why~="loading"then assert(ok==good);return end end
    error("validation did not finish")
end
drain(true)
assert(B.Status().records==258 and B.Status().items==3)
local variants,cut=B.Variants(2589,100);assert(#variants==100 and cut)
local expected={}
for _,r in ipairs(g.records)do
    assert(B.Record(r.item_id,r.variant_key).variant_json==r.variant_json,"sorted range lost exact variant")
    if r.item_id==2589 then expected[#expected+1]=r.variant_key end
end
for i,key in ipairs(variants)do assert(key==expected[i],"variant selector order changed")end
assert(B.Record(2,other.variant_key)==nil and B.Record(3000,expected[1])==nil,"range search crossed item boundary")
assert(B.Record(2589,string.rep("0",64))==nil and B.Record(2589,string.rep("f",64))==nil)
assert(B.Status().cache_entries<=24)
-- Repeated access to the same fully validated snapshot does not re-encode it.
TwichUIMarketData=raw;local encode=J.Encode
J.Encode=function()error("validated manifest unexpectedly re-encoded")end
assert(B.Load());J.Encode=encode
raw.manifest=raw.manifest.." "
assert(not B.Load() and B.Status().generation==g.generation_id)
drain(false);raw.manifest=raw.manifest:sub(1,-2)
-- No clock retains the old 32-unit fallback rather than expanding unmeasured work.
GetTimePreciseSec=nil;debugprofilestop=nil;calls=0;B.Begin(raw);B.Step(3)
assert(calls<=32 and B.Status().loading,"clockless fallback work expanded")
GetTimePreciseSec=function()return 0 end;drain(true)
-- A deterministic clock proves time-budget checks still stop before the unit cap.
local clock=0;GetTimePreciseSec=function()clock=clock+.0005;return clock end
calls=0;B.Begin(raw);B.Step(3);assert(calls<=4 and B.Status().loading,"time budget ignored")
GetTimePreciseSec=function()return 0 end;drain(true)
coroutine.resume=resume
assert(TwichUIWorkshopDB.markets.keep.items[1]=="original")
print("PASSED bridge bounded scheduling, compact exact-variant index, encoding and local-state invariants")
