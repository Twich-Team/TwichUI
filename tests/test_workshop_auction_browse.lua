local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W=c.TwichUI.Workshop
local A,D,PR=W.AuctionUI,W.AuctionBrowseData,W.Prices
local n=0
local function same(a,b,msg) n=n+1; assert(a==b,(msg or "").." expected "..tostring(b)..", got "..tostring(a)) end
local now=20000*86400
c.time=function() return now end
c.GetRealmName=function() return "Realm" end
c.TwichUIWorkshopDB={v=2,markets={}}
c.C_AuctionHouse=setmetatable({},{__index=function(_,key) return function() error("forbidden auction operation "..key) end end})
local info={
 [10]={"Elemental Earth",7,1,0}, [11]={"Silk Cloth",7,2,0}, [12]={"Sword",2,3,2},
 [13]={"Soulbound",4,4,1}, [14]={"Unknown"},
}
c.C_Item.GetItemInfo=function(id)
 local x=info[id] or {"Item "..id,7,1,0}
 return x[1],nil,x[3],nil,nil,x[2]==7 and "Trade Goods" or "Equipment","Elemental",nil,nil,134572,40,x[2],nil,x[4]
end
local batch=PR.NewBatch()
batch:Add(10,3,299,true); batch:Add(11,5,600,true); batch:Add(12,1,200,true); batch:Add(13,2,1000,true)
local items,count=batch:Items()
local m={f=2,key="Realm|Alliance",realm="Realm",side="Alliance",at=now-3600,complete=true,scope="full",items=items,n=count,read=4,used=4}
c.TwichUIWorkshopDB.markets[m.key]=m
local r=D.Row(10,m)
same(r.unit,100,"shared normalization ceil(299/3)");same(r.qty,3,"observed aggregate")
same(r.estimate,300,"estimate explicitly differs from original total 299")
same(r.source,"stored");same(r.actionable,false);same(r.auctionID,nil,"no purchase handle")
same(D.Matches(r,{query="earth"}),true);same(D.Matches(r,{query="earth",exact=true}),false)
same(D.Matches(r,{query="ELEMENTAL EARTH",exact=true}),true)
same(D.Matches(r,{query="10",exact=true}),true)
same(D.Matches(r,{category="trade",quality=1,auctionable=true}),true)
same(D.Matches(r,{quality=2}),false)
same(D.Matches(D.Row(13,m),{auctionable=true}),false,"bound type filtered")
same(D.Matches(D.Row(14,m),{auctionable=true}),false,"unknown binding filtered")
same(D.Row(14,m).unit,nil,"missing price unknown")
local original= W.Market.Price
W.Market.Price=function() return {price=PR.MAX_COPPER,qty=20} end
same(D.Row(10,m).estimate,nil,"out of range aggregate value unavailable")
W.Market.Price=original
local job=D.Job({market=m})
while not job:Step() do end
same(#job.rows,4);same(job.rows[1].item,10);same(job.rows[4].item,13)
-- Independent hand arithmetic over 80 deterministic quantity/total sets.
for seed=1,80 do
 local b=PR.NewBatch();local want={}
 for id=1,12 do
  local qty=(seed*17+id*7)%19+1
  local total=(seed*131+id*97)%9000+1
  b:Add(id,qty,total,true)
  local rounded=math.floor((total+qty-1)/qty)
  want[id]={unit=rounded,qty=qty,value=rounded*qty}
 end
 local encoded,num=b:Items()
 local fixture={f=2,key="fixture",at=now,scope="full",complete=true,items=encoded,n=num}
 local j=D.Job({market=fixture});while not j:Step() do end
 local prior=0
 for _,row in ipairs(j.rows) do
  same(row.unit,want[row.item].unit,"independent normalized unit")
  same(row.qty,want[row.item].qty,"independent quantity")
  same(row.estimate,want[row.item].value,"independent estimated value")
  same(row.unit>=prior,true,"ascending normalized prices");prior=row.unit
 end
end
A.Show();local p=A.Page("browse")
for i=1,30 do FlushTimers() end
same(#p.list.data,4,"actual view uses market adapter")
same(p.detail.buy:IsEnabled(),false,"Buy disabled centrally and in UI")
same(p.selected,10);same(p.list.data[1].estimate,300)
Press.Must(p.list.rows[2]);same(p.selected,11,"row resolves current pooled data")
Press.Must(p.detail.track);same(W.AdvisorData.Tracked()[11],true,"shared tracked set")
Press.Must(p.detail.track);same(W.AdvisorData.Tracked()[11],nil,"untrack uses shared set")
A.Browse.Filter("quality",3); for i=1,30 do FlushTimers() end
same(#p.list.data,1,"quality filter");same(p.list.data[1].item,12)
Press.Must(p.reset);for i=1,30 do FlushTimers() end
A.Browse.Search("absent");for i=1,30 do FlushTimers() end
same(#p.list.data,0);same(p.list.empty:GetText():find("No stored",1,true)~=nil,true,"honest empty")
A.OpenBrowse(14,8);for i=1,30 do FlushTimers() end
same(#p.list.data,1);same(p.list.data[1].unit,nil,"Shopping item without price")
same(p.detail.buy:IsEnabled(),false)
-- Large catalog and sort both yield; only visible rows have frames.
local large={f=2,key="Realm|Alliance",realm="Realm",side="Alliance",at=now,complete=true,scope="full",items={},n=6000,read=6000,used=6000}
for id=1,6000 do large.items[id]=items[10] end
c.TwichUIWorkshopDB.markets[m.key]=large
p.forceItem=nil;A.Browse.Search("")
local ticks=0
while p.job do FlushTimers();ticks=ticks+1;assert(ticks<3000,"job finishes") end
same(#p.rows,6000);same(#p.list.rows<30,true,"bounded row pool")
same(ticks>50,true,"sort and catalog cooperatively sliced")
p.list.scroll:SetVerticalScroll(56*120+17);p.list:Layout()
local top=p.list.data[121].item
A.Browse.Select(p.list.data[500].item);local selected=p.selected
p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",10,true)
FlushTimers()
while p.job do FlushTimers() end
same(p.selected,selected,"metadata preserves selection")
same(p.list.data[math.floor(p.list.scroll:GetVerticalScroll()/56)+1].item,top,"metadata preserves top identity")
same(p.list.scroll:GetVerticalScroll()%56,17,"metadata preserves within-row offset")
A.Go("shopping");same(#p.list.data,0,"hidden results released");same(p.rows,nil);same(p.market,nil)
A.Go("browse");while p.job do FlushTimers() end
same(p.selected,selected,"page return preserves selected identity")
same(p.list.scroll:GetVerticalScroll(),56*120+17,"page return keeps viewport")
-- Cancelled metadata jobs never repaint a hidden page.
A.Browse.Search("Earth");A.Hide();for i=1,20 do FlushTimers() end
same(p.job,nil);same(#p.list.data,0)
-- Error is explicit and recoverable, not a zero-price listing.
A.Show();W.AdvisorData.Info=function() error("synthetic unavailable metadata") end
for i=1,20 do FlushTimers() end
same(p.error~=nil,true);same(#p.list.data,0);same(p.list.empty:GetText():find("could not",1,true)~=nil,true)
A.Hide()
print("PASSED: Auction Browse "..n.." checks")
