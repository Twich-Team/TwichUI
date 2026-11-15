-- Source-specific UI uses the real reader/adapter; local pricing calls are sentinels.
local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W,m,now=dofile(TESTS.."auction_market_fixture.lua")(c)
local B,J,A=W.Bridge,W.BridgeCodec,W.AuctionUI
local function fingerprint(v)
    if type(v)~='table' then return tostring(v) end
    local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
    local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..fingerprint(v[k]) end;return '{'..table.concat(out,',')..'}'
end
local db=c.TwichUIWorkshopDB;local before=fingerprint(db)
local f=assert(io.open(TESTS..'fixtures/market_bridge_v1/source-canonical-generation.json'));local generation=J.Parse(f:read('*a'));f:close()
local h=J.Copy(generation);h.records=nil
local raw={transport_version=1,manifest=J.Encode(h),records={},receipt=J.Encode(setmetatable({schema_version=1,generation_id=generation.generation_id,desktop_build='synthetic-ui-test',completed_at='2026-11-15T13:00:00Z'},J.OBJECT))}
for i,r in ipairs(generation.records) do raw.records[i]=J.Encode(r) end
local loads,native=0,0
c.C_AddOns={LoadAddOn=function(name)loads=loads+1;assert(name=='TwichUI_MarketData');c.TwichUIMarketData=raw;return true end}
c.C_AuctionHouse=setmetatable({},{__index=function(_,k)return function()native=native+1;error('forbidden AH '..k)end end})
assert(not B.Status().ready and loads==0)
A.Show('market')
local function settle()
    for i=1,3000 do FlushTimers();local p=A.Page('market');if p and not p.job and not B.Status().loading then return p end end
    error('external Market UI did not settle')
end
settle();assert(loads==0,'ordinary Workshop/Market navigation loads bridge')
local oldPrice,oldValue,oldHistory=W.Market.Price,W.Market.Value,W.Market.History
W.Market.Price=function()error('external catalog read local price')end
W.Market.Value=function()error('external detail read local valuation')end
W.Market.History=function()error('external chart read local history')end
A.Market.Filter('marketKey','server');local p=settle()
assert(p.failed==nil and loads==1 and #p.rows==2)
assert(A.Market.Select(2589));assert(p.projection.record==nil,'item aggregate silently picked variant')
local key=generation.records[2].variant_key
assert(A.Market.Variant(key))
assert(p.projection.record.variant_key==key and #p.projection.series.points==2)
assert(p.projection.series.points[1].price==100 and p.projection.series.points[2].price==120)
assert(p.projection.history.points[1].at=='2026-11-14T12:00:00.123456Z')
assert(not p.browse:IsEnabled() and not p.advisor:IsEnabled() and not p.track:IsEnabled())
assert(A.Market.Metric('supply') and p.projection.series.points[1].price==10)
assert(A.Market.Metric('recent'))
assert(not A.Market.Variant(string.rep('f',64)))
-- One available complete date in the pinned partial fixture must not inherit
-- the local chart's minimum-listing caption for representative price or supply.
local file=assert(io.open(TESTS..'fixtures/market_bridge_v1/partial-unknown-generation.json'));local partial=J.Parse(file:read('*a'));file:close()
local header=J.Copy(partial);header.records=nil
local packet={transport_version=1,manifest=J.Encode(header),records={},receipt=J.Encode(setmetatable({schema_version=1,generation_id=partial.generation_id,desktop_build='synthetic-ui-test',completed_at='2026-11-15T13:00:00Z'},J.OBJECT))}
for i,r in ipairs(partial.records) do packet.records[i]=J.Encode(r) end
c.TwichUIMarketData=packet;B.Begin(packet)
for i=1,3000 do local ok,why=B.Step(3);if why~='loading' then assert(ok);break end end
A.Market.Filter('marketKey','server');p=settle();assert(A.Market.Select(2589) and A.Market.Variant(key))
assert(p.chart.state=='single' and p.chart.note:GetText():find('Observed Recent Price:',1,true) and not p.chart.note:GetText():find('Cheapest',1,true))
assert(A.Market.Metric('supply') and p.chart.note:GetText():find('Observed supply:',1,true))
assert(A.Market.Metric('minimum') and p.chart.note:GetText():find('Observed minimum listing:',1,true))
assert(c.TwichUIWorkshopDB==db and fingerprint(db)==before and native==0,'local data or AH actions changed')
W.Market.Price,W.Market.Value,W.Market.History=oldPrice,oldValue,oldHistory
A.Market.Filter('marketKey',m.key);p=settle();A.Market.Select(10)
assert(p.projection.facts.min.value==20200 and loads==1,'local source default/values changed')
A.Hide();assert(B.Status().cache_entries<=B.CACHE_MAX)
print('PASSED: external Market UI, exact variant/history, unchanged local scans, no AH requests')
