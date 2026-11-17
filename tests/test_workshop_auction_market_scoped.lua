-- Actual production reader + existing Market page, with independent price/state expectations.
local c,g=dofile(TESTS..'auction_mock.lua')
local W,m=dofile(TESTS..'auction_market_fixture.lua')(c)
local B,J,A=W.Bridge,W.BridgeCodec,W.AuctionUI
local function fingerprint(v)
    if type(v)~='table' then return tostring(v) end
    local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..fingerprint(v[k]) end;return '{'..table.concat(out,',')..'}'
end
local before=fingerprint(c.TwichUIWorkshopDB)..fingerprint(c.TwichUIDB)
local native,loads=0,0
c.C_AuctionHouse=setmetatable({},{__index=function(_,key)return function()native=native+1;error('forbidden AH '..key)end end})
c.ReloadUI=function()error('forbidden reload')end
c.C_AddOns={LoadAddOn=function()loads=loads+1;error('unexpected addon load')end}
local function packet(generation)
    local h=J.Copy(generation);h.records=nil
    local raw={transport_version=1,manifest=J.Encode(h),records={},receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='synthetic-ui',completed_at='2026-11-16T23:59:59Z'},J.OBJECT))}
    for i,r in ipairs(generation.records) do raw.records[i]=J.Encode(r) end
    return raw
end
local function file(name)
    local f=assert(io.open(TESTS..'fixtures/market_bridge_scoped_l1/fixtures/'..name));local value=J.Parse(f:read('*a'));f:close();return value
end
local function drain(raw,good)
    B.Begin(raw)
    for i=1,200000 do local ok,why=B.Step();if why~='loading' then assert(ok==good,why);return end end
    error('reader did not finish')
end
local function settle()
    for i=1,3000 do FlushTimers();local p=A.Page('market');if p and not p.job and not B.Status().loading then return p end end
    error('Market page did not settle')
end
local function open(item,key)
    assert(A.OpenMarket(item,{market='server',serverVariant=key}));return settle()
end
A.Show('market');settle();assert(loads==0 and not B.Status().ready)
local artifact=os.getenv('L3_MARKET_ARTIFACT')
if artifact then
    -- The actual Rust publisher created this trusted test-only assignment artifact.
    assert(loadfile(artifact))();c.TwichUIMarketData=TwichUIMarketData
    drain(c.TwichUIMarketData,true)
    local variants=B.Variants(2589);assert(#variants==1)
    local p=open(2589,variants[1]);assert(p.projection.record and #p.projection.series.points==2)
    assert(p.projection.series.points[1].price==100 and p.projection.series.points[2].price==140)
    assert(p.projection.facts.mval.value==100 and p.projection.facts.hist==nil)
    local historical=B.Variants(2);assert(B.Availability(2,historical[1]).state=='observed_absent')
    p=open(2,historical[1]);assert(p.trends:GetText():find('Observed absent',1,true))
    local bids=B.Variants(123);assert(B.Availability(123,bids[1]).state=='supply_only')
    p=open(123,bids[1]);assert(p.projection.facts.recent==nil and p.projection.facts.supply.items==2)
    assert(B.Availability(2589,J.SHA('{"bonus_lists":[9],"id":2589}')).state=='outside_scope')
else
    local generation=file('scoped.json');local raw=packet(generation);c.TwichUIMarketData=raw;drain(raw,true)
    local p=open(10001,generation.records[2].variant_key)
    assert(p.chart.maxDots==60,'Market cannot display the complete scoped daily window')
    assert(#p.projection.series.points==2 and p.projection.series.points[1].price==100)
    assert(p.contextText:GetText():find('Scope complete',1,true) and p.contextText:GetText():find('not whole-market complete',1,true))
    assert(#p.projection.series.gaps==1 and p.projection.history.scope.scope_complete)
    p=open(10000,generation.records[1].variant_key)
    assert(p.projection.availability.state=='observed_absent' and p.projection.facts.recent==nil)
    assert(p.trends:GetText():find('Observed absent',1,true))
    p=open(10003,generation.records[4].variant_key)
    assert(p.projection.availability.state=='supply_only' and p.projection.facts.supply.items==10)
    local source=file('source.json');local excluded=source.records[#source.records]
    p=open(excluded.item_id,excluded.variant_key)
    assert(p.projection.why=='outside_scope' and p.projection.record==nil)
    assert(p.chart.msg:GetText()=='Market history not included in this update.')
    assert(p.aggregateText:find(excluded.variant_key,1,true) and p.contextText:GetText():find('Requested variant:',1,true))
    assert(p.trends:GetText():find('future desktop update',1,true) and not p.browse:IsEnabled())
    p=open(10001,string.rep('f',64));assert(p.projection.why=='outside_scope')
    local unknown=file('unknown-scoped.json');raw=packet(unknown);c.TwichUIMarketData=raw;drain(raw,true)
    p=open(unknown.records[1].item_id,unknown.records[1].variant_key)
    assert(p.projection.availability.state=='unknown_coverage' and p.projection.facts.recent==nil)
    assert(p.trends:GetText():find('coverage unknown',1,true))
end
local evidence=W.ServerMarket.Evidence(2147483647,string.rep('f',64))
assert(evidence.state=='outside_scope' and evidence.recent==nil and evidence.market==nil and evidence.summary_coverage=='unavailable')
assert(not evidence.local_competition and evidence.role=='external_evidence')
local old=B.Status().generation
local broken={transport_version=1,manifest='{}',records={},receipt='{}'}
c.TwichUIMarketData=broken;drain(broken,false);assert(B.Status().generation==old)
A.Market.Filter('marketKey','server');local p=settle()
assert(p.kind:GetText():find('Previous compatible data is retained.',1,true) and p.kind:GetText():find('contract could not be verified',1,true))
local raw=packet(file('unknown-scoped.json'))
local future={transport_version=1,records=raw.records,receipt=raw.receipt}
local header=W.BridgeCodec.Parse(raw.manifest);header.schema_version=4;future.manifest=W.BridgeCodec.Encode(header)
c.TwichUIMarketData=future;drain(future,false);A.Go('browse');A.Go('market');p=settle()
assert(p.kind:GetText():find('Update TwichUI to import it.',1,true) and p.kind:GetText():find('Previous compatible data is retained.',1,true))
assert(p.contextText:GetText():find('Companion',1,true) and p.contextText:GetText():find('reader contract '..B.Compatibility().minimum_reader_version..' required',1,true))
A.Go('browse');A.Go('shopping');A.Go('sell');A.Go('market');settle()
local pages=A.Snapshot().pages;local slices=B.Status().slices
collectgarbage('collect');local heap=collectgarbage('count');local began=os.clock();local worst=0
for i=1,50 do local tick=os.clock(); A.Go('browse');A.Go('market');settle();A.Go('shopping');A.Go('sell');A.Go('market');settle();worst=math.max(worst,os.clock()-tick) end
collectgarbage('collect')
assert(A.Snapshot().pages==pages,'page count '..A.Snapshot().pages..' vs '..pages)
assert(B.Status().slices==slices and not B.Status().loading,'validation restarted '..B.Status().slices..' vs '..slices)
local growth=collectgarbage('count')-heap
print(('BRIDGE_SCOPED_UI_BENCH iterations=50 elapsed_us=%d worst_iteration_us=%d retained_growth_bytes=%d'):format((os.clock()-began)*1e6,worst*1e6,growth*1024))
assert(growth<512 and B.Status().cache_entries<=B.CACHE_MAX)
assert(before==fingerprint(c.TwichUIWorkshopDB)..fingerprint(c.TwichUIDB) and native==0 and loads==0)
A.Market.Filter('marketKey',m.key);A.Market.Search('10');p=settle();assert(A.Market.Select(10));assert(p.projection.facts.min.value==20200)
-- A typed presentation control exercises the local cap independently of History2's retention buckets.
local history=W.Market.History
W.Market.History=function()
    local h={points={},gaps={},basis='synthetic typed local daily history'}
    for day=19941,20000 do h.points[#h.points+1]={kind='day',from=day,to=day,v=100} end
    return h
end
W.AuctionMarketData.Clear()
A.Market.Range(60);assert(#p.projection.series.points==60 and p.chart.shown==30,'local 30-marker cap changed')
for _,hook in ipairs(p.main.hooks.OnSizeChanged or {}) do hook(p.main) end
assert(p.chart.shown==30,'resize changed local marker cap')
W.Market.History=history
A.Hide();assert(p.job==nil and p.catalog==nil)
print('PASSED: scoped Market page; exact prices/history, absence/unknown/exclusion, retention, navigation, local isolation')
