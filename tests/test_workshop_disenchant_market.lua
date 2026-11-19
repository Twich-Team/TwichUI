-- Real validated reader, material-price completion, Advisor and live tooltip handlers.
local c=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop
local B,J,A,DE=W.Bridge,W.BridgeCodec,W.Advisor,W.Disenchant
local function object(t)return setmetatable(t,J.OBJECT)end
local file=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'))
local fixture=J.Parse(file:read('*a'));file:close()
local h=fixture.manifest;h.synthetic=false
for _,o in ipairs(h.observations)do o.synthetic=false end
local template=J.Parse(fixture.parts['29'])[1]
local _,now=W.BridgeValidate.Time(h.generated_at);now=now+60
c.time=function()return now end
c.GetRealmName=function()return 'Fixture Realm' end;c.UnitFactionGroup=function()return 'Horde' end
local function generation(missing)
 local buckets={}
 for _,id in ipairs({100,10938,10940})do
  if id~=missing then
   local r=J.Copy(template);r[1]=id;r[2]=W.Pricing.BaseKey(id)
   local price=id==100 and '120' or id==10938 and '400' or '200'
   for _,i in ipairs({4,5,6})do r[i]=price end
   for _,p in ipairs(r[14])do if p[1]==0 then p[2],p[3]=price,price end end
   local bucket=id%64;buckets[bucket]=buckets[bucket] or J.Array();table.insert(buckets[bucket],r)
  end
 end
 h.partitions=J.Array();c.TwichUIMarketParts={}
 for bucket=0,63 do
  if buckets[bucket]then
   local raw=J.Encode(buckets[bucket]);c.TwichUIMarketParts['A'..('%02d'):format(bucket)]=raw
   h.partitions[#h.partitions+1]=object({bucket=bucket,bytes=#raw,record_count=#buckets[bucket],sha256=J.SHA(raw)})
  end
 end
 h.record_count=missing and 2 or 3;h.coverage.source_records=h.record_count;h.coverage.delivered_records=h.record_count
 local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
 B.Begin({summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(object({schema_version=1,generation_id=h.generation_id,desktop_build='disenchant-fixture',completed_at=h.generated_at}))})
end
local can,bound,variant,sell,liveLevel,unknownLevel=true,false,false,10,5,false
c.C_SpellBook={ContainsAnyDisenchantSpell=function()return can end}
c.GetProfessions=function()return 1 end
c.GetProfessionInfo=function()return 'localized Enchanting',nil,1,75,nil,nil,333 end
c.C_Item.GetItemLocation=function()return {IsBagAndSlot=function()return true end}end
c.C_Item.DoesItemExist=function()return true end
c.C_Item.GetItemID=function()return 100 end
c.C_Item.GetItemLink=function()return variant and 'item:100:0:0:0:0:0:42' or 'item:100' end
c.C_Item.IsBound=function()return bound end
c.C_Item.GetStackCount=function()return 5 end
c.C_Item.GetItemInfo=function()return 'Fixture armor','item:100',2,5,1,'Armor','',1,'INVTYPE_CHEST',1,sell,4,1,0 end
c.C_Item.GetDetailedItemLevelInfo=function()if unknownLevel then return nil,nil,5 end;return liveLevel,nil,5 end
local drawn,refreshes={},0
local tip={IsShown=function()return true end,AddLine=function(_,s)drawn[#drawn+1]=s end,AddDoubleLine=function(_,a,b)drawn[#drawn+1]=a..' | '..b end}
c.GameTooltip=tip
local function draw()drawn={};W.WorthTip.OnItem(tip,{guid='synthetic-item'});return table.concat(drawn,'\n')end
tip.RefreshData=function()refreshes=refreshes+1;draw()end
c.TooltipDataProcessor={AddTooltipPostCall=function()end};c.Enum.TooltipDataType={Item=1}
W.WorthTip.Start()
local eventFrame
for _,frame in ipairs(c.testFrames)do if frame.events and frame.events.SPELLS_CHANGED then eventFrame=frame end end
assert(eventFrame and eventFrame.events.SKILL_LINES_CHANGED,'character changes must refresh an open tooltip')
c.C_AuctionHouse=setmetatable({},{__index=function()return function()error('auction actions forbidden')end end})
assert(W.WorthLayout.Set({enabled=true,lines={{id='recommend',when='always'},{id='disenchant',when='always'},{id='outcomes',when='shift'}}}))
generation()
for i=1,1000 do FlushTimers();if not B.Status().loading then break end end
assert(B.Status().ready and B.Status().checked_parts==0)
local initial=draw()
assert(not initial:find('Disenchant (average) | 360',1,true),'unvalidated material data was displayed')
for i=1,2000 do FlushTimers() end
local text=draw()
assert(not text:find('Classic',1,true),'unwanted source wording in tooltip')
assert(text:find('Workshop: Disenchant',1,true),'actual tooltip did not use the material estimate: '..text..' reader error='..tostring(B.Status().error))
assert(text:find('Disenchant (average) | 360',1,true),'per-item expected value differs from 80%*1.5*200 + 20%*1.5*400')
assert(refreshes>0 and B.Status().checked_parts==3,'material completion did not refresh the open tooltip')
local facts=W.Facts.Of(100)
local result=W.AdvisorData.Tooltip(W.WorthTip.Read({guid='synthetic-item'}),facts)
assert(result.action=='disenchant' and result.level=='tentative' and not result.proceeds and not result.suggestion.price)
assert(result.disenchant.priceSource=='market_server' and result.provenance.source=='disenchant')
assert(result.disenchant.value==360 and result.qty==5,'stack count changed a per-item estimate')
assert(W.Worth.Recommend({advisor=result}).kind=='possible')
local savedShift=c.IsShiftKeyDown;c.IsShiftKeyDown=function()return true end
local expanded=draw()
assert(expanded:find('Disenchant yields | |T15940:14:14:0:0|t',1,true))
assert(expanded:find('\n | |T15938:14:14:0:0|t',1,true),'second yield must be a separate right-column row')
c.IsShiftKeyDown=savedShift
liveLevel=26;local actual=W.WorthTip.Read({guid='synthetic-item'})
assert(actual.itemLevel==26 and actual.actualLevel and actual.variant=='level','actual copy level was lost')
liveLevel=5
local completed=refreshes;local slices=B.Status().slices
for i=1,100 do FlushTimers() end
assert(refreshes==completed and B.Status().slices==slices,'completed material prices restarted decoding')
sell=1000;local vendorText=draw()
assert(vendorText:find('Workshop: Vendor',1,true),'lower DE must lose to vendor')
assert(not vendorText:find('Classic',1,true),'primary comparison retained unwanted source wording')
sell=10;variant=true
assert(draw():find('Workshop: Disenchant',1,true),'known DE and vendor values can be compared without an auction quote')
unknownLevel=true;local unresolved=W.WorthTip.Read({guid='synthetic-item'})
assert(not unresolved.actualLevel and DE.ForItem(unresolved).state=='unknown','a missing detailed level was replaced by the variant base level')
unknownLevel=false
bound=true;assert(draw():find('Workshop: Disenchant',1,true),'a bound suffix item can use its actual level for DE')
can=false;eventFrame:GetScript('OnEvent')(eventFrame,'SPELLS_CHANGED')
assert(table.concat(drawn,' '):find('does not know Disenchant',1,true),'character without Disenchant remained eligible after spell change')
assert(W.WorthTip.Events()==3,'character listener count must remain bounded')
can=true;bound=false;variant=false
-- Replacement missing a material must discard the complete old value.
h.issuer_id='00000000-0000-4000-8000-000000000002';generation(10938)
for i=1,2000 do FlushTimers() end
text=draw();assert(not text:find('Disenchant (average) | 360',1,true) and text:find('price is missing',1,true),'replacement reused an old material quote')
-- The same feature works with local scan data and no Companion generation.
W.Summary.Deactivate()
local batch=W.Prices.NewBatch();batch:Add(10938,2,800,true);batch:Add(10940,2,400,true);batch:Add(100,2,240,true)
local items,n,_,_,dist=batch:Items()
assert(W.Prices.Commit('Fixture Realm|Horde',{realm='Fixture Realm',side='Horde',at=now,complete=true,read=3,used=3,n=n,items=items,alg=W.Dist.ALG,dist=dist}))
local input=W.WorthTip.Read({guid='synthetic-item'})
local localEstimate=DE.ForItem(input,{market=input.marketTable,now=now})
assert(localEstimate.state=='ok' and localEstimate.value==360 and localEstimate.priceSource=='local','local-only material prices failed')
assert(W.WorthTip.faults==0)
print('PASSED real Market material completion, automatic tooltip refresh, shared DE recommendation, eligibility and local-only fallback')
