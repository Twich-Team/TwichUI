-- Standalone import invariants used by the existing disposable mutation runner.
TwichUI={Workshop={}}
TwichUIWorkshopDB={v=2,markets={localScan={items={[2589]='999,1,1,1,0'},h2={[2589]='keep-local'}}}}
TwichUIDB={profile='keep-profile'}
local localDB,profile=TwichUIWorkshopDB,TwichUIDB
for _,file in ipairs({'Data','BridgeCodec','BridgeSchema','BridgeValidate','Bridge'}) do dofile(REPO..'TwichUI_Workshop/'..file..'.lua') end
local J,B=TwichUI.Workshop.BridgeCodec,TwichUI.Workshop.Bridge
local file=assert(io.open(TESTS..'fixtures/market_bridge_v1/source-canonical-generation.json'));local g=J.Parse(file:read('*a'));file:close()
local function pack(value)
    local h=J.Copy(value);h.records=nil
    local raw={transport_version=1,manifest=J.Encode(h),records={},receipt=J.Encode(setmetatable({schema_version=1,generation_id=value.generation_id,desktop_build='synthetic-unit-fixture',completed_at='2026-11-15T13:00:00Z'},J.OBJECT))}
    for i,r in ipairs(value.records) do raw.records[i]=J.Encode(r) end
    return raw
end
local function preserved()
    assert(TwichUIWorkshopDB==localDB and TwichUIDB==profile and localDB.markets.localScan.items[2589]=='999,1,1,1,0' and localDB.markets.localScan.h2[2589]=='keep-local' and profile.profile=='keep-profile','import overwrote local saved data')
end
local function drain(value,good)
    B.Begin(pack(value))
    for i=1,10000 do local ok,why=B.Step(3);if why~='loading' then assert(ok==good,'wrong acceptance');preserved();return end end
    error('unbounded validation')
end
local function seal(value)
    local body=J.Copy(value);body.generation_id=nil;body.integrity=nil
    local manifest=J.Copy(body);manifest.records=nil
    value.generation_id=J.SHA(J.Encode(body))
    value.integrity=setmetatable({records_bytes=#J.Encode(value.records),records_sha256=J.SHA(J.Encode(value.records)),manifest_sha256=J.SHA(J.Encode(manifest))},J.OBJECT)
end
assert(J.SHA('abc')=='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
assert(not pcall(J.Parse,'{"a":null,"a":1}'),'duplicate JSON object key')
assert(not pcall(J.Parse,'9007199254740993'),'integer precision loss')
assert(not pcall(J.Parse,string.rep('[',15)..'0'..string.rep(']',15)),'depth limit')
drain(g,true)
local key=g.records[2].variant_key
assert(B.Record(2589)==nil and B.Value(2589,key,'recent').copper=='120')
assert(#B.History(2589,key,'recent',{days=1}).points==1,'history outside requested window')
local bad=J.Copy(g);bad.generation_id=string.rep('f',64);drain(bad,false)
assert(B.Status().generation==g.generation_id)
bad=J.Copy(g);bad.records[3]=J.Copy(bad.records[2]);bad.record_count=3;seal(bad);drain(bad,false)
assert(B.Status().generation==g.generation_id)
preserved()
print('PASSED bridge import integrity, identity, arithmetic and local history invariants')
