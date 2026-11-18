-- Production reader and research boundary. Every source below is explicitly synthetic.
TwichUI={Workshop={}};TwichUIDB={sentinel='profile'};TwichUIWorkshopDB={sentinel='local observations'}
for _,name in ipairs({'Data','BridgeCodec','BridgeSchema','BridgeValidate','SummarySchema','Summary','Bridge','ServerMarket'}) do dofile(REPO..'TwichUI_Workshop/'..name..'.lua') end
local W=TwichUI.Workshop;local J,Q,B=W.BridgeCodec,W.Summary,W.Bridge
local f=assert(io.open(TESTS..'fixtures/workshop_summary_v1/synthetic.json'));local fixture=J.Parse(f:read('*a'));f:close()
local function pack(h)
 return {summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='synthetic-test',completed_at='2026-11-18T00:00:00Z'},J.OBJECT))}
end
local function seal(h)
 local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
end
local function drain()
 for i=1,100000 do if not Q.Pending() then return end;Q.Step() end
 error('unbounded validation')
end
local function load(h) B.Begin(pack(h));drain() end
local h=fixture.manifest;TwichUIMarketParts={A29=fixture.parts['29']}
load(h);assert(B.Status().ready and B.Status().summary and B.Status().loaded_parts==0,'header eagerly loaded data')
local key='684434823a7f7a1797ecda68d5bb5abef5ea13a18aefa5a26cccff8e1b813d51'
assert(B.Record(2589,key)==nil);drain()
assert(B.Value(2589,key,'recent').copper=='120' and B.Value(2589,key,'market').value==100)
assert(B.Record(2589,key).current.supply==10)
assert(B.Value(2589,key,'historical')==nil,'two closes invented a historical reference')
assert(B.History(2589,key)==nil and select(2,B.History(2589,key))=='summary_only','summary fabricated daily observations')
assert(B.Record(2589)==nil and B.Record(2589,string.rep('f',64))==nil,'item ID or ambiguous variant fallback')
assert(B.Availability(2589,key).state=='priced' and B.Availability(2589,key,'2026-11-14').state=='summary_only')
assert(B.Scope().type=='current_observed_exact_variants' and not B.Scope().whole_market_complete)
assert(B.Market().faction=='Horde' and B.Freshness(0).state=='unknown' and B.Freshness(9999999999).state=='stale')
local e=W.ServerMarket.Evidence(2589,key);assert(e.tier=='broad_summary' and not e.local_competition and e.native_identity_mapping=='unavailable')
assert(W.ServerMarket.Variants(2589)[2][2]=='Observed variant 1','ordinary selector requires reading a hash')
local schemaFile=assert(io.open(TESTS..'fixtures/workshop_summary_v1/manifest.schema.json'));assert(J.Encode(J.Parse(schemaFile:read('*a')))==J.Encode(W.SummarySchema),'schema mirror drift');schemaFile:close()
local generation=B.Status().generation
local mutations={
 function(x)x.schema_version=2 end,function(x)x.can_satisfy_local_competition=true end,
 function(x)x.market.game='wow-retail' end,function(x)x.market.faction='invented' end,
 function(x)x.market.mapping_verified=false end,function(x)x.coverage.complete=false end,
 function(x)x.coverage.delivered_records=2 end,function(x)x.source_observation.observation_id='999' end,
 function(x)x.generated_at='2026-11-15T13:00:00Z' end,function(x)x.partitioning.buckets=128 end,
 function(x)x.partitions[1].bytes=131073 end,function(x)x.partitions[2]=J.Copy(x.partitions[1]) end,
 function(x)x.market.secret='unknown' end,function(x)x.source_kind='local_competition' end,
 function(x)x.confidence_ceiling='good' end,function(x)x.record_count=150001 end,
 function(x)x.issuer_id='not-an-issuer' end,function(x)x.source_watermark='9223372036854775808' end,
}
for i,mutate in ipairs(mutations) do local bad=J.Copy(h);mutate(bad);seal(bad);load(bad);assert(B.Status().generation==generation and B.Status().error,'bad header accepted '..i) end
-- Caller-pinned identity must match exactly, including faction and evidence.
local pinned=J.Copy(h.market);pinned.faction='Alliance';B.Begin(pack(h),false,{market=pinned});drain();assert(B.Status().error)
-- A valid replacement header whose requested part is corrupt preserves last-good data.
local wrong=J.Copy(h);wrong.source_watermark='903';wrong.source_observation.observation_id='903';seal(wrong)
TwichUIMarketParts.A29='[]';load(wrong);assert(not B.Record(2589,key));drain();assert(B.Status().generation==generation and B.Value(2589,key).value==120)
-- Resealed malformed tuples cannot bypass semantic validation with valid hashes.
local row=J.Parse(fixture.parts['29'])[1]
local badRows={
 function(r)r[4]='0' end,function(r)r[4]='999999999999' end,function(r)r[4]=120 end,
 function(r)r[8]=1 end,function(r)r[9]=1 end,function(r)r[1]=2590 end,
 function(r)r[2]='not-a-variant' end,function(r)r[3]=3 end,function(r)r[7]=0 end,
 function(r)r[10]='100' end,function(r)r[11]=3;r[12]=2 end,function(r)r[14]=1 end,
}
for i,mutate in ipairs(badRows) do
 local r=J.Copy(row);mutate(r);local raw=J.Encode(setmetatable({r},J.ARRAY));local bad=J.Copy(h)
 bad.source_watermark=tostring(904+i);bad.source_observation.observation_id=bad.source_watermark
 bad.partitions[1].sha256=J.SHA(raw);bad.partitions[1].bytes=#raw;seal(bad);TwichUIMarketParts.A29=raw
 load(bad);assert(not B.Record(2589,key));drain();assert(B.Status().generation==generation,'bad tuple replaced last-good '..i)
end
assert(TwichUIDB.sentinel=='profile' and TwichUIWorkshopDB.sentinel=='local observations')
local same=pack(h);B.Begin(same);drain();same.manifest='{}';B.Begin(same);drain();assert(B.Status().generation==generation and B.Status().error,'mutable raw reference bypassed revalidation')
assert(B.Capabilities().summary_contract==1 and B.Status().decoded_parts<=1)
local multiple=J.Copy(h);local r1=J.Parse(fixture.parts['29'])[1];local r2=J.Copy(r1);r2[2]=string.rep('f',64);r2[4]='999'
local raw=J.Encode(setmetatable({r1,r2},J.ARRAY));multiple.partitions[1].bytes=#raw;multiple.partitions[1].record_count=2;multiple.partitions[1].sha256=J.SHA(raw)
multiple.record_count=2;multiple.coverage.source_records=2;multiple.coverage.delivered_records=2;seal(multiple);TwichUIMarketParts.A29=raw
load(multiple);B.Variants(2589);drain();local variants,cut=B.Variants(2589)
assert(#variants==2 and not cut and not B.Record(2589),'ambiguous item acquired an item-ID aggregate')
assert(B.Value(2589,variants[1]).value==120 and B.Value(2589,variants[2]).value==999,'exact variants collapsed')
print('PASSED summary integrity, closed contracts, pinned identity, lazy loading, references, last-good preservation and economic isolation')
