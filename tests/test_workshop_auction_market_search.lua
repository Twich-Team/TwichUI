-- Real reader + Market handlers: name search must coexist with one decoded partition.
local c,g=dofile(TESTS..'auction_mock.lua')
local W=c.TwichUI.Workshop
local B,J,P,A=W.Bridge,W.BridgeCodec,W.Pricing,W.AuctionUI
local f=assert(io.open(TESTS..'fixtures/workshop_summary_v2/synthetic.json'))
local fixture=J.Parse(f:read('*a'));f:close()
local h=fixture.manifest;h.synthetic=false
for _,o in ipairs(h.observations) do o.synthetic=false end
local template=J.Parse(fixture.parts['29'])[1]
h.partitions=J.Array();c.TwichUIMarketParts={}
for bucket=29,31 do
 local rows=J.Array()
 for n=0,7 do
  local id=2560+bucket+n*64
  local row=J.Copy(template);row[1]=id;row[2]=P.BaseKey(id);rows[#rows+1]=row
  g.names[id]='Cloth '..id
 end
 local raw=J.Encode(rows);c.TwichUIMarketParts['A'..bucket]=raw
 h.partitions[#h.partitions+1]=setmetatable({bucket=bucket,bytes=#raw,record_count=#rows,sha256=J.SHA(raw)},J.OBJECT)
end
h.record_count=24;h.coverage.source_records=24;h.coverage.delivered_records=24
local body=J.Copy(h);body.generation_id=nil;h.generation_id=J.SHA(J.Encode(body))
local _,now=W.BridgeValidate.Time(h.generated_at)
c.time=function()return now+60 end;c.UnitFactionGroup=function()return 'Horde' end
B.Begin({summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='search-fixture',completed_at=h.generated_at},J.OBJECT))})
local function settle()
 for i=1,2000 do
  FlushTimers()
  local p=A.Page('market')
  if not B.Status().loading and (not p or not p.job and not p.summaryWaiting) then return p end
 end
 error('Market name search never settled')
end
settle();assert(A.Show('market'));settle()
assert(A.OpenMarket(2589,{market='server'}));local p=settle()
assert(p.projection.series and #p.projection.series.points>0)
assert(#p.rows==1,'focused item lookup should stay narrow')
-- Force validation across many frames, as on a large delivered catalog.
W.Summary.RESUMES=8
local chart,blanks=p.chart.Set,0
p.chart.Set=function(self,series,...)
 if not series or #series.points==0 then blanks=blanks+1 end
 return chart(self,series,...)
end
assert(not B.Record(2591,P.BaseKey(2591)) and B.Status().loading,'fixture must begin searching during another partition read')
A.Market.Search('Cloth');settle()
assert(not p.error and #p.rows==24,'name search reused an incomplete focused catalog: '..#p.rows)
assert(blanks==0,'search cleared an already validated chart while decoding other partitions')
assert(p.projection.record and p.projection.record.item_id==2589)
local token,starts=p.token,W.AuctionBrowseData.Stats().starts
local slices=B.Status().slices
for i=1,100 do A.Render();FlushTimers() end
assert(not p.job and not p.summaryWaiting and not B.Status().loading,'idle research keeps decoding')
assert(p.token==token and W.AuctionBrowseData.Stats().starts==starts,'loader progress restarted the catalog')
assert(B.Status().slices==slices,'completed chart reloaded evicted partitions')
-- A different query reuses the complete catalog and resolves the newly selected item.
A.Market.Search('Cloth 2590');settle()
assert(#p.rows==1 and p.selected==2590)
assert(p.projection.record and p.projection.record.item_id==2590,'selection kept the old item variant')
assert(p.projection.series and #p.projection.series.points>0)
-- Metric/range and generation changes must not reuse the previous projection.
A.Market.Metric('supply');settle()
assert(p.projection.metric=='supply' and p.projection.series.metric=='supply')
A.Market.Range(7);settle()
assert(p.projection.series.to-p.projection.series.from==6)
h.issuer_id='00000000-0000-4000-8000-000000000002'
local nextBody=J.Copy(h);nextBody.generation_id=nil;h.generation_id=J.SHA(J.Encode(nextBody))
B.Begin({summary_version=1,bank='A',manifest=J.Encode(h),receipt=J.Encode(setmetatable({schema_version=1,generation_id=h.generation_id,desktop_build='search-replacement',completed_at=h.generated_at},J.OBJECT))})
settle();A.Render();settle()
assert(p.projection.header.generation_id==h.generation_id,'selected chart retained the old generation')
assert(A.OpenMarket(2589,{market='server',serverVariant=P.BaseKey(2589)}));settle()
assert(p.serverVariant==P.BaseKey(2589) and p.projection.record.item_id==2589,'explicit research selection was reset')
A.Market.Search('nothing matches');settle()
assert(#p.rows==0 and not p.projection.record and not p.projection.series,'empty search kept another item chart')
A.Hide();settle()
assert(B.Status().decoded_parts<=1 and not p.summaryWaiting,'released Market retained pending refresh work')
assert(not p.summaryDetail,'released Market retained the selected history snapshot')
print('PASSED Market name search, complete catalog, stable chart, selection changes and idle decoding')
