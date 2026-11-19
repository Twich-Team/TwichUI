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

-- Negotiated producer-generated history: actual closes, gaps and standalone fallback.
local hf=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'));local historyFixture=J.Parse(hf:read('*a'));hf:close()
local hh=historyFixture.manifest
local schema2=assert(io.open(TESTS..'fixtures/workshop_summary_v2/manifest.schema.json'));assert(J.Encode(J.Parse(schema2:read('*a')))==J.Encode(W.SummaryHistorySchema),'history schema mirror drift');schema2:close()
Q.Deactivate();TwichUIMarketParts={A29=historyFixture.parts['29']};load(hh)
assert(B.Status().ready and B.Status().contract_version==2 and B.Scope().history_delivered)
assert(not B.Record(2589,key));drain()
local series=assert(B.History(2589,key,'recent',{days=14}))
assert(series.source=='market_server' and #series.points==2 and #series.gaps==12)
assert(series.points[1].v==100 and series.points[2].v==120)
assert(series.points[1].observation_id=='100' and series.points[2].observation_id=='902')
assert(series.points[1].provenance:find('Market server',1,true))
assert(series.points[1].from<series.points[2].from and series.points[1].synthetic)
local exposed=B.Record(2589,key);exposed.daily[1][2]='999'
assert(B.History(2589,key,'recent',{days=14}).points[1].v==100,'caller modified retained history')
assert(B.Compatibility().contract_version==2 and B.CompatibilityText(true):find('contract 2',1,true))
local projection=W.ServerMarket.Project(2589,key,'recent',14)
assert(projection.series.external and #projection.series.points==2 and projection.facts.recent.value==120)
assert(B.History(2589,key,'supply',{days=14}).points[2].v==10)
assert(B.History(2589,key,'unsupported')==nil and B.History(2589,key,'recent',{days=61})==nil)
local raw=J.Parse(historyFixture.parts['29']);local goodGeneration=B.Status().generation
for _,change in ipairs({
    function(p)table.remove(p)end,
    function(p)p[1][2]='0'end,
    function(p)p[1]=setmetatable({3,J.NULL,J.NULL,0},J.ARRAY)end,
    function(p)p[1][4]=-1 end,
}) do
    local badRows=J.Copy(raw);change(badRows[1][14]);local part=J.Encode(badRows);local bad=J.Copy(hh)
    bad.partitions[1].bytes=#part;bad.partitions[1].sha256=J.SHA(part);seal(bad)
    TwichUIMarketParts={A29=part};load(bad);B.Record(2589,key);drain()
    assert(B.Status().generation==goodGeneration and B.History(2589,key,'recent',{days=14}).points[2].v==120,'corrupt history replaced validated generation')
end
Q.Deactivate();TwichUIMarketParts=nil
assert(not B.Status().ready and B.History(2589,key)==nil,'absent Companion data must not manufacture a curve')
assert(TwichUIDB.sentinel=='profile' and TwichUIWorkshopDB.sentinel=='local observations','Market history mutated standalone data')
print('PASSED negotiated actual history, explicit gaps, corrupt replacement preservation and absent-data fallback')

-- While WoW keeps an old root in memory, two later bank publications can
-- overwrite a not-yet-loaded A partition. Never use it under the old manifest.
Q.Deactivate();load(hh)
local updatedRows=J.Copy(raw);updatedRows[1][4]='999';updatedRows[1][14][2][2]='999'
local updatedPart=J.Encode(updatedRows);local updated=J.Copy(hh)
updated.source_watermark='903';updated.source_observation.observation_id='903';updated.source_observation.observed_at='2026-11-15T12:01:00Z';updated.generated_at=updated.source_observation.observed_at
updated.observations[2].observation_id='903';updated.observations[2].observed_at=updated.generated_at
updated.partitions[1].bytes=#updatedPart;updated.partitions[1].sha256=J.SHA(updatedPart);seal(updated)
TwichUIMarketParts={A29=updatedPart}
assert(not B.Record(2589,key));drain()
assert(B.Status().generation==hh.generation_id and B.Status().reload_required and not B.Record(2589,key),'late bank overwrite escaped generation pin')
load(updated);assert(not B.Record(2589,key));drain()
assert(B.Status().generation==updated.generation_id and not B.Status().reload_required and B.Value(2589,key).value==999,'explicit reload did not apply validated replacement')
print('PASSED pinned in-memory generation, late bank overwrite refusal and explicit reload')

-- Queued data requested before combat must resume afterward without being
-- mislabeled as changed files, or leaving a permanently failed partition.
Q.Deactivate()
local combatHeader=J.Copy(hh);local extra=J.Copy(raw);extra[1][1]=2590;extra[1][2]=J.SHA('{"id":2590}')
local extraRaw=J.Encode(extra)
combatHeader.partitions[2]=setmetatable({bucket=30,bytes=#extraRaw,record_count=1,sha256=J.SHA(extraRaw)},J.OBJECT)
combatHeader.record_count=2;combatHeader.coverage.source_records=2;combatHeader.coverage.delivered_records=2;seal(combatHeader)
TwichUIMarketParts={A29=historyFixture.parts['29'],A30=extraRaw};load(combatHeader)
assert(not B.Record(2589,key));assert(not B.Record(2590,extra[1][2]))
InCombatLockdown=function()return true end;drain()
assert(B.Status().error=='combat' and not B.Status().reload_required,'combat deferral was mislabeled as changed files')
assert(select(2,B.Record(2590,extra[1][2]))=='combat')
InCombatLockdown=nil
assert(not B.Record(2590,extra[1][2]));drain()
assert(B.Value(2590,extra[1][2]).value==120 and not B.Status().error,'combat deferral did not resume on the next request')
print('PASSED queued combat deferral and retry without a false reload message')
