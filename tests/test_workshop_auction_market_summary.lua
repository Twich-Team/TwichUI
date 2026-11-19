-- Real production Bridge/ServerMarket/Market presentation; synthetic source only.
local c=dofile(TESTS..'auction_mock.lua')
local W=dofile(TESTS..'auction_market_fixture.lua')(c)
local B,Q,J,A=W.Bridge,W.Summary,W.BridgeCodec,W.AuctionUI
local f=assert(io.open(TESTS..(WORKSHOP_SUMMARY_HISTORY and 'fixtures/workshop_summary_v2/synthetic.json' or 'fixtures/workshop_summary_v1/synthetic.json')));local fixture=J.Parse(f:read('*a'));f:close()
local profile=c.TwichUIDB;local db=c.TwichUIWorkshopDB
local function fingerprint(t)
 if type(t)~='table' then return tostring(t) end
 local keys={};for k in pairs(t)do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local o={};for _,k in ipairs(keys)do o[#o+1]=tostring(k)..'='..fingerprint(t[k])end;return table.concat(o,'|')
end
local before=fingerprint(profile)..fingerprint(db)
-- A second real contract partition detects accidental whole-catalog work on focus.
local manifest=fixture.manifest;local extra=J.Parse(fixture.parts['29'])[1]
extra[1]=2590;extra[2]=J.SHA('{"id":2590}')
fixture.parts['30']=J.Encode(setmetatable({extra},J.ARRAY))
manifest.partitions[2]=setmetatable({bucket=30,bytes=#fixture.parts['30'],record_count=1,sha256=J.SHA(fixture.parts['30'])},J.OBJECT)
manifest.record_count=2;manifest.coverage.source_records=2;manifest.coverage.delivered_records=2
local body=J.Copy(manifest);body.generation_id=nil;manifest.generation_id=J.SHA(J.Encode(body))
local loads={}
c.C_AddOns={GetAddOnMetadata=function(_,field) return field=='X-TwichUI-Summary' and '1' end,LoadAddOn=function(name)
 loads[name]=(loads[name] or 0)+1
 if name=='TwichUI_MarketData' then
  c.TwichUIMarketData={summary_version=1,bank='A',manifest=J.Encode(manifest),receipt=J.Encode(setmetatable({schema_version=1,generation_id=manifest.generation_id,desktop_build='synthetic-presentation',completed_at='2026-11-18T00:00:00Z'},J.OBJECT))}
 elseif name=='TwichUI_MarketPartA29' or name=='TwichUI_MarketPartA30' then c.TwichUIMarketParts=c.TwichUIMarketParts or {};local bucket=name:sub(-2);c.TwichUIMarketParts['A'..bucket]=fixture.parts[bucket]
 else error('unexpected partition '..name)end
 return true
end}
c.C_AuctionHouse=setmetatable({},{__index=function()return function()error('native AH interaction forbidden')end end})
c.ReloadUI=function()error('automatic reload forbidden')end
assert(not B.RecognizeSummary());for i=1,1000 do FlushTimers();if not B.Status().loading then break end end
assert(B.Status().ready and B.Status().loaded_parts==0 and loads.TwichUI_MarketData==1,'recognition must load only small header')
local artifact=os.getenv('WORKSHOP_SUMMARY_ARTIFACT')
if artifact then
 -- Only the Windows-generated acceptance artifact is executed, never provider input.
 local install=assert(loadfile(artifact));install();c.TwichUIMarketData=TwichUIMarketData
 B.Begin(c.TwichUIMarketData)
 for i=1,10000 do FlushTimers();if not B.Status().loading then break end end
 local addons=assert(os.getenv('WORKSHOP_SUMMARY_PARTS'))
 c.C_AddOns.LoadAddOn=function(name)
  assert(name:match('^TwichUI_MarketPart[AB]%d%d$'),'unexpected addon')
  assert(loadfile(addons..'/'..name..'/Data.lua'))();c.TwichUIMarketParts=TwichUIMarketParts;return true
 end
end
local item=tonumber(os.getenv('WORKSHOP_SUMMARY_EXPECTED_ITEM')) or 2589
local recent=tonumber(os.getenv('WORKSHOP_SUMMARY_EXPECTED_RECENT')) or 120
local market=os.getenv('WORKSHOP_SUMMARY_EXPECTED_MARKET')
local function settle()
 for i=1,5000 do FlushTimers();local p=A.Page('market');if p and not p.job and not p.summaryWaiting and not B.Status().loading then return p end end
 error('Market summary did not settle')
end
assert(A.Show('market'));local initial=settle();assert(initial.projection.source=='market_server','automatic research source ignored loaded Companion data')
local initiallyLoaded=B.Status().loaded_parts
assert(A.OpenMarket(item,{market='server'}));local p=settle()
assert(B.Status().loaded_parts<=math.max(1,initiallyLoaded),'focused research walked unrelated partitions')
assert(p.projection.record and p.projection.facts.recent.value==recent and (market=='unavailable' and p.projection.facts.mval==nil or market~='unavailable' and p.projection.facts.mval and p.projection.facts.mval.value==100),'Market references differ: record='..tostring(p.projection.record)..' variant='..tostring(p.serverVariant)..' recent='..tostring(p.projection.facts and p.projection.facts.recent and p.projection.facts.recent.value)..' market='..tostring(p.projection.facts and p.projection.facts.mval and p.projection.facts.mval.value)..' state='..tostring(p.projection.why)..' selected='..tostring(p.selected)..' chosen='..tostring(p.chosen and p.chosen.item)..' rows='..tostring(#p.rows)..' error='..tostring(p.error)..' checked='..tostring(B.Status().checked_parts)..' readerError='..tostring(B.Status().error))
assert(p.projection.facts.supply.items==10 and p.projection.facts.comp==nil)
if B.Manifest().contract_version==2 then
 assert(p.projection.series and #p.projection.series.points>=1 and p.projection.series.points[#p.projection.series.points].price==recent,'actual Market daily chart missing')
 assert(p.chartCard.heading:GetText():find('actual daily observations',1,true))
else
 assert(p.projection.series==nil and p.chart.msg:GetText():find('not a daily price series',1,true),'summary became a daily chart')
end
assert(p.contextText:GetText():find('Horde',1,true) and p.coverage:GetText():find('current observed exact variants',1,true))
assert(p.aggregateText:find(B.Status().generation,1,true),'diagnostics lost actual generation')
assert(#p.serverVariant==64 and not p.contextText:GetText():find(p.serverVariant,1,true),'ordinary view requires a variant hash')
A.Market.Variant('');settle()
local evidence=W.ServerMarket.Evidence(item,p.serverVariant)
assert(evidence.tier=='broad_summary' and not evidence.local_competition)
for i=1,25 do A.Go('browse');A.Go('market');settle()end
assert(fingerprint(profile)..fingerprint(db)==before,'external research rewrote local scans, history or preferences')
assert(B.Status().decoded_parts<=1 and W.Market.Source().market.key~='server','external data changed pricing defaults')
print('PASSED actual Workshop Market summary presentation, automatic recognition, exact research selection, no fabricated history or local mutation')
