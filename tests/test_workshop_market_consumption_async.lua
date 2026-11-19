local c=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop
local B,J,P=W.Bridge,W.BridgeCodec,W.Pricing
local f=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'))
local fixture=J.Parse(f:read('*a'));f:close()
local h=fixture.manifest;h.synthetic=false
for _,o in ipairs(h.observations) do o.synthetic=false end
local template=J.Parse(fixture.parts['29'])[1]
h.partitions=setmetatable({},J.ARRAY);c.TwichUIMarketParts={}
for _,id in ipairs({2589,2590}) do
 local row=J.Copy(template);row[1]=id;row[2]=P.BaseKey(id)
 local raw=J.Encode(setmetatable({row},J.ARRAY));local bucket=id%64
 c.TwichUIMarketParts['A'..bucket]=raw
 h.partitions[#h.partitions+1]=setmetatable({bucket=bucket,bytes=#raw,record_count=1,sha256=J.SHA(raw)},J.OBJECT)
end
h.record_count=2;h.coverage.source_records=2;h.coverage.delivered_records=2
local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
local _,now=W.BridgeValidate.Time(h.generated_at)
c.time=function()return now+60 end;c.UnitFactionGroup=function()return 'Horde' end
B.Begin({summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='async-fixture',completed_at=h.generated_at},J.OBJECT))})
for i=1,1000 do FlushTimers();if not B.Status().loading then break end end
local retained=true
local decoded=P.Decoded
P.Decoded=function(bucket)
 decoded(bucket)
 if B.Status().checked_parts==2 then
  local calls=B.Status().lookup_calls
  local previous=P.Price(2589)
  if not previous or B.Status().lookup_calls~=calls then retained=false end
 end
end
local prices,draws={},0
W.UI.Redraw=function()
 draws=draws+1
 prices[1]=P.Price(2589);prices[2]=P.Price(2590)
end
P.Changed()
for i=1,1000 do FlushTimers() end
assert(prices[1] and prices[2],'different partitions never settled into one complete price snapshot')
local before=draws
for i=1,100 do FlushTimers() end
assert(draws==before and draws<20,'completed prices caused an endless redraw/redecode loop')
assert(P.CacheSize()<=P.MAX_CACHE)
assert(retained,'a newly decoded partition discarded a previously resolved price')
-- Capacity pressure must settle into a stated fallback, never a decode/redraw loop.
local capacity=P.MAX_CACHE;P.MAX_CACHE=1
h.issuer_id='00000000-0000-4000-8000-000000000002'
local nextBody=J.Copy(h);nextBody.generation_id=nil;h.generation_id=J.SHA(J.Encode(nextBody))
B.Begin({summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='capacity-fixture',completed_at=h.generated_at},J.OBJECT))})
for i=1,1000 do FlushTimers() end
local missing,why=P.Price(2590)
assert(P.CacheSize()==1 and not missing and why=='lookup_limit','capacity overflow must keep bounded local fallback')
local settled=draws
for i=1,100 do FlushTimers() end
assert(draws==settled,'capacity overflow restarted background work')
P.MAX_CACHE=capacity
print('PASSED cooperative multi-partition pricing, complete refresh and stable idle')
