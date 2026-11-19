-- Real reader and feature services; all input is a disposable synthetic fixture.
local c,g=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop
local B,J,P=W.Bridge,W.BridgeCodec,W.Pricing
local file=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'))
local fixture=J.Parse(file:read('*a'));file:close()
local h=fixture.manifest
-- Exercise ordinary production admission rules without claiming a live feed.
h.synthetic=false
for _,o in ipairs(h.observations) do o.synthetic=false end
local row=J.Parse(fixture.parts['29'])[1]
local rows=setmetatable({},J.ARRAY)
for _,id in ipairs({2589,2653}) do
 local r=J.Copy(row);r[1]=id;r[2]=P.BaseKey(id);rows[#rows+1]=r
end
local variant=J.Copy(row);variant[1]=2717;variant[2]=J.SHA('{"bonus_lists":[42],"id":2717}');rows[#rows+1]=variant
local raw=J.Encode(rows)
h.partitions=setmetatable({},J.ARRAY);h.partitions[1]=setmetatable({},J.OBJECT)
local part=h.partitions[1];part.bucket=29;part.bytes=#raw;part.record_count=3;part.sha256=J.SHA(raw)
h.record_count=3;h.coverage.source_records=3;h.coverage.delivered_records=3
local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
local _,now=W.BridgeValidate.Time(h.generated_at)
c.time=function()return now+60 end
c.GetRealmName=function()return 'Configured Realm' end
c.UnitFactionGroup=function()return 'Horde' end
c.TwichUIMarketParts={A29=raw}
local input={summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='consumption-fixture',completed_at=h.generated_at},J.OBJECT))}
B.Begin(input);for i=1,1000 do FlushTimers();if not B.Status().loading then break end end
assert(B.Status().ready)
assert(P.BaseKey(2589)==J.SHA('{"id":2589}'))
local src=P.Source();assert(src.reference and src.market.pricing)
local p,why=P.Price(2589,{market=src.market})
assert(not p and why=='loading','pending validation must remain pending')
for i=1,1000 do FlushTimers();if not B.Status().loading then break end end
p=assert(P.Price(2589,{market=P.Source().market}))
assert(p.price==tonumber(row[4]) and p.reference and p.source=='market_server')
assert(P.Price(2717)==nil,'a lone modified server variant must not be treated as a base item')
assert(p.qty==nil and p.total==nil,'server supply must not become purchasable depth')
local q=W.Prices.Quote(p,123)
assert(q.state=='estimate' and q.reference and q.cost==p.price*123)
assert(P.Price(2589,{variant=true})==nil,'a native variant cannot inherit the base price')
local rec={id='fixture',name='Fixture craft',outItem=2653,outMin=1,outMax=1,mats={{item=2589,qty=2}}}
local e=W.Prices.Estimate(rec,function(id)return P.Price(id,{market=P.Source().market})end)
assert(e.state=='ok' and e.reference and e.cost==2*p.price)
local f=W.Facts.Of(2589)
assert(f.reference and f.recent.source=='market_server' and not f.comp)
assert(W.Sell.Suggest(2589,1,{facts=f}).state=='nocompetition','a reference cannot manufacture a posting price')
local series=assert(W.Facts.Chart(f));assert(#series.points>0 and series.points[#series.points].provenance=='Market server')
assert(W.Facts.Line('marketvalue',f,tostring)[1]:find('Market server',1,true))
for _,entry in ipairs(W.Facts.Rows(f,tostring)) do
 if entry.id~='source' then assert(#entry.label<24,'source labels overflow the existing fact rows') end
end
assert(f.quality.level=='limited' and f.quality.source=='market_server')
local plan=W.Shopping.Plan({rows={{item=2589,need=2,short=2,have=0}},picks={},have=function()return 0 end,
 auction=function(id)return P.Price(id)end,cost=function(id,n)return P.Cost(id,n)end,
 vendor=function()end,sells=function()return false end,recipes=function()return {} end,queued=function()end})
assert(plan.rows[1].options.auction.quote.reference and plan.rows[1].options.auction.cost==2*p.price)
local cp=W.CraftPlanner.Plan({entries={{id='fixture',crafts=1,mats=rec.mats,outItem=rec.outItem,outMin=1,outMax=1}},
 have=function()return 0 end,auction=function(id)return P.Price(id)end,cost=function(id,n)return P.Cost(id,n)end,
 vendor=function()end,sells=function()return false end,recipes=function()return {} end,picks={}})
assert(cp.summary.reference and not cp.summary.proven and cp.summary.cash.low==2*p.price)
assert(W.Strategy.RangeText(cp.summary.economic,tostring):find('about ',1,true)==1)
assert(not (cp.summary.savings and cp.summary.savings.confident))
assert(W.Strategy.CostText(cp.summary.cash,tostring):find('about ',1,true)==1)
local originalRecipes=W.Session.AllRecipes
W.Session.AllRecipes=function()return {rec}end
local opportunities=W.Session.Opportunities()
assert(opportunities.summary.priced==1 and opportunities.all[1].est.reference)
W.Window.Show()
for _,mode in ipairs({'overview','opps','craft','shop','advisor'}) do
 W.Window.SetMode(mode)
 for i=1,100 do FlushTimers() end
 W.Window.Render()
 assert(W.Window.Mode()==mode)
end
W.Window.Hide()
W.Session.AllRecipes=originalRecipes
-- Independent repeated addition checks the money model on 64 deterministic quantities.
for seed=1,64 do
 local qty=1+(seed*17)%997;local total=0
 for i=1,qty do total=total+p.price end
 local quote=W.Prices.Quote(p,qty)
 assert(quote.reference and quote.state~='exact' and quote.cost==total)
end
assert(W.Prices.Quote({price=99999999999,reference=true},2147483647).state=='none')
local advice=W.Advisor.Decide(2589,{qty=1,sell=0,bindType=0,now=now+60,minGain=0,facts=f,crafting={reserved=0}})
assert(advice.level=='tentative' and advice.reference and not advice.suggestion.price and advice.provenance.source=='market_server')
local worth=W.Worth.Evaluate({sell=1,bindType=0,market={at=now},price=p,now=now+60,rate=0.05})
assert(worth.auction.reference and W.Worth.Recommend(worth).kind=='reference','a price reference is not a proven vendor/auction winner')
-- Actual tooltip path, default primary line only: source/DE qualifications must
-- remain visible without Shift details or a local scan.
local drawn={}
local tipItem,vendorCopper,gear=2589,10,false
c.GameTooltip={AddLine=function(_,s)drawn[#drawn+1]=s end,AddDoubleLine=function(_,a,b)drawn[#drawn+1]=a..' '..b end}
c.C_Item.GetItemLocation=function()return {IsBagAndSlot=function()return true end}end
c.C_Item.DoesItemExist=function()return true end
c.C_Item.GetItemID=function()return tipItem end
c.C_Item.GetItemLink=function()return 'item:'..tipItem end
c.C_Item.IsBound=function()return false end
c.C_Item.GetStackCount=function()return 1 end
local info=c.C_Item.GetItemInfo
c.C_Item.GetItemInfo=function()
 return 'Fixture item','item:'..tipItem,gear and 2 or 1,1,1,gear and 'Armor' or 'Trade Goods','',1,gear and 'INVTYPE_CHEST' or '',134572,vendorCopper,gear and 4 or 7,1,0
end
assert(W.WorthLayout.Set({enabled=true,lines={{id='recommend',when='always'}}}))
local function tooltip(expected)
 drawn={};W.WorthTip.OnItem(c.GameTooltip,{guid='Fixture-item'})
 assert(table.concat(drawn,' '):find(expected,1,true),'tooltip did not show '..expected..': '..table.concat(drawn,' '))
end
tooltip('Workshop: Auction (Market estimate)')
vendorCopper=100;tooltip('Workshop: Vendor (Market comparison)')
tipItem=2653;gear=true;tooltip('disenchant unpriced')
tipItem=2717;gear=false;tooltip('Workshop: Auction price unavailable')
assert(W.WorthTip.faults==0,'Market recommendation tooltip faulted')
c.C_Item.GetItemInfo=info
-- A local scan remains unmodified and provides missing records independently.
local batch=W.Prices.NewBatch();batch:Add(2589,10,3000,true);batch:Add(999,10,7000,true)
local items,n,_,_,dist=batch:Items()
assert(W.Prices.Commit('Configured Realm|Horde',{realm='Configured Realm',side='Horde',at=now,
 complete=true,read=2,used=2,n=n,items=items,alg=W.Dist.ALG,dist=dist}))
local original=W.Market.Price(2589).price
local localFacts=W.Facts.Of(2589,{market=W.Market.Source().market,localOnly=true})
local originalRecent=localFacts.recent and localFacts.recent.value
assert(P.Price(999).source=='local' and P.Price(999).price==700)
local both=W.Facts.Of(2589)
assert(both.reference and W.Market.Price(2589).price==original)
assert((localFacts.recent and localFacts.recent.value)==originalRecent,'reference overlay mutated cached local facts')
local legacy=W.Market.Source();assert(legacy.market and not legacy.market.pricing,'reference pricing must not replace native scan selection')
c.UnitFactionGroup=function()return 'Alliance' end
assert(not P.Source().reference and P.Price(2589).source=='local','another faction must not inherit these prices')
c.UnitFactionGroup=function()return 'Horde' end
c.time=function()return now+P.MAX_AGE+1 end
assert(not P.Source().reference and P.Price(2589).source=='local','stale server data must fall back')
print('PASSED Market consumption: exact base identity, lazy loading, estimate arithmetic, shopping, facts, charts, local action isolation and stale/faction fallback')
