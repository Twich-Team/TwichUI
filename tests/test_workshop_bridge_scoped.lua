-- Fast production-reader controls for the existing disposable mutation harness.
TwichUI={Workshop={}};TwichUIDB={keep='profile'};TwichUIWorkshopDB={markets={sentinel='local scans/history/quality'}}
for _,name in ipairs({'Data','BridgeCodec','BridgeSchema','BridgeValidate','Bridge'}) do dofile(REPO..'TwichUI_Workshop/'..name..'.lua') end
local W=TwichUI.Workshop;local J,B=W.BridgeCodec,W.Bridge
local function load(name)
    local f=assert(io.open(TESTS..'fixtures/market_bridge_scoped_l1/fixtures/'..name));local g=J.Parse(f:read('*a'));f:close();return g
end
local function seal(g)
    local body=J.Object();for k,v in pairs(g) do if k~='generation_id' and k~='integrity' then body[k]=v end end
    local manifest=J.Object();for k,v in pairs(body) do if k~='records' then manifest[k]=v end end
    g.generation_id=J.SHA(J.Encode(body));g.integrity.records_bytes=#J.Encode(g.records)
    g.integrity.records_sha256=J.SHA(J.Encode(g.records));g.integrity.manifest_sha256=J.SHA(J.Encode(manifest))
end
local function rehash(g)
    g.scope.record_sha256=J.Array();for i,r in ipairs(g.records) do g.scope.record_sha256[i]=J.SHA(J.Encode(r)) end
    seal(g)
end
local function pack(g)
    local h=J.Object();for k,v in pairs(g) do if k~='records' then h[k]=v end end
    local raw={transport_version=1,manifest=J.Encode(h),records={},receipt=J.Encode(setmetatable({schema_version=1,generation_id=g.generation_id,desktop_build='synthetic-mutation',completed_at='2026-11-16T23:59:59Z'},J.OBJECT))}
    for i,r in ipairs(g.records) do raw.records[i]=J.Encode(r) end;return raw
end
local function drain(g,expected)
    B.Begin(pack(g))
    for i=1,200000 do local ok,why=B.Step();if why~='loading' then assert(ok==expected,'wrong scoped acceptance');return end end
    error('unbounded validation')
end
local good=load('scoped.json');drain(good,true)
local original=B.Status().generation
assert(B.Availability(10000,good.records[1].variant_key).state=='observed_absent')
assert(B.Availability(10001,good.records[2].variant_key,'2026-11-14').state=='unknown_coverage')
assert(B.Availability(10005,string.rep('f',64)).state=='outside_scope')
assert(B.Value(10005,string.rep('f',64))==nil,'excluded price became zero')
assert(B.Value(10000,good.records[1].variant_key)==nil,'absence became zero price')
local tests={
    function(g)g.scope.request_digest=string.rep('0',64)end,
    function(g)g.scope.selection_id=string.rep('0',64)end,
    function(g)g.scope.record_sha256[1]=string.rep('0',64)end,
    function(g)g.scope.date_coverage[2].state='complete_close'end,
    function(g)g.required_features[4]='future-feature'end,
    function(g)g.schema_version=999 end,
    function(g)table.remove(g.records[2].daily);rehash(g)end,
    function(g)
        local r=g.records[2];r.variant_json='{"bonus_lists":[9],"id":10001}';r.variant_key=J.SHA(r.variant_json);rehash(g)
    end,
}
for _,mutate in ipairs(tests) do local bad=J.Copy(good);mutate(bad);seal(bad);drain(bad,false);assert(B.Status().generation==original and B.Status().ready,'lost last-good generation') end
local limit=B.SCOPED_BYTES;B.SCOPED_BYTES=1;drain(good,false);B.SCOPED_BYTES=limit;assert(B.Status().generation==original)
local liar=J.Copy(good);liar.integrity.records_bytes=2
B.SCOPED_BYTES=#pack(liar).manifest+13;drain(liar,false);B.SCOPED_BYTES=limit
assert(B.Status().refusal=='canonical_bytes','declared size bypassed actual-byte preflight')
assert(TwichUIDB.keep=='profile' and TwichUIWorkshopDB.markets.sentinel=='local scans/history/quality','external validation wrote local data')
print('PASSED scoped integrity, exact identity, completeness, availability and local isolation controls')
