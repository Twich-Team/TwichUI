-- Real widgets and synthetic bags/history. Native AH operations are sentinels.
local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W,m,now=dofile(TESTS.."auction_market_fixture.lua")(c)
local A,D=W.AuctionUI,W.AuctionMarketData
local n=0
local function same(a,b,msg) n=n+1;assert(a==b,(msg or "").." expected "..tostring(b)..", got "..tostring(a)) end
local calls=0
c.C_AuctionHouse=setmetatable({},{__index=function(_,k) return function() calls=calls+1;error("native "..k) end end})
local function Settle()
    for i=1,1500 do FlushTimers();local p=A.Page("market");if not p or not p.job then return end end
    error("Market job did not terminate")
end
A.Show();A.Go("market");A.Market.Filter("marketKey",m.key);Settle()
local p=A.Page("market")
same(p.failed,nil,"Market builds");same(#p.rows,2);same(p.selected,10)
same(p.projection.facts.min.value,20200);same(p.projection.market,m.key)
same(p.browse:IsEnabled(),true);same(p.advisor:IsEnabled(),true)
local history=p.projection.history
W.AuctionUI.Market.Range(120);same(p.projection.history,history);same(#p.projection.series.groups>0,true)
W.AuctionUI.Market.Range(2);same(p.projection.series.points[1].kind,"obs")
Press.Must(p.track);same(W.AdvisorData.Tracked()[10],true)
A.Market.Filter("scope","tracked");Settle();same(#p.rows,1)
Press.Must(p.track);Settle();same(#p.rows,0);same(p.track:IsEnabled(),false)
A.Market.Filter("scope","all");A.Market.Search("11");Settle()
same(#p.rows,1);same(p.selected,11);same(p.projection.facts.min,nil);same(p.projection.history~=nil,true)
A.Market.Filter("marketKey","absent");Settle();same(p.projection,nil,"absent market has no known catalog")
A.OpenMarket(10,{market="absent"});Settle();same(p.projection.facts.nomarket,true)
same(p.projection.facts.min,nil,"unavailable context never falls back")
A.OpenMarket(10,{market="Realm|Horde"});Settle();same(p.projection.facts.min.value,900)
Press.Must(p.browse);Settle();local browse=A.Page("browse")
for i=1,30 do FlushTimers() end
same(A.Mode(),"browse");same(browse.market.key,"Realm|Horde","Browse preserves research market")
same(browse.rows[1].unit,900)
Press.Must(browse.detail.market);Settle();same(A.Mode(),"market");same(p.market.key,"Realm|Horde")
A.OpenMarket(10,{market=m.key,itemKey={itemID=10,itemLevel=0,itemSuffix=4}});Settle()
same(p.projection.variant,true);same(p.projection.facts.min,nil);same(p.browse:IsEnabled(),false)
same(p.advisor:IsEnabled(),false,"variant not collapsed into base-item advice")
-- Late metadata keeps top identity and offset, independent of selected item.
local raw=c.TwichUIWorkshopDB.markets[m.key]
local large={f=2,realm="Realm",side="Alliance",at=now,scope="full",complete=true,items={},n=6000,read=6000,used=6000}
for id=1,6000 do large.items[id]=m.items[10] end
c.TwichUIWorkshopDB.markets[m.key]=large
A.Market.Filter("marketKey",m.key);A.Market.Search("");Settle()
same(#p.rows,6000);same(#p.list.rows<20,true)
p.list.scroll:SetVerticalScroll(60*100+17);p.list:Layout()
local top=p.rows[101].item
A.Market.Select(p.rows[500].item);local selected=p.selected
p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",14,true);Settle()
same(p.selected,selected);same(p.rows[math.floor(p.list.scroll:GetVerticalScroll()/60)+1].item,top)
same(p.list.scroll:GetVerticalScroll()%60,17)
A.Market.Range(60);same(p.list.scroll:GetVerticalScroll()%60,17,"range changes do not rebuild catalog")
A.Go("shopping");A.Go("market");Settle()
local frames=#c.testFrames
for i=1,20 do A.Go("shopping");A.Go("market");Settle() end
same(#c.testFrames,frames,"page switching makes no frames")
A.Go("sell");same(p.rows,nil);same(p.index,nil);same(p.projection,nil);same(D.Stats().cache,0)
same(p.listening,false);same(p.job,nil);same(#p.list.data,0)
-- Bags: no bank inventory; navigation does not apply history to a posting form.
c.C_Container={GetContainerNumSlots=function(b) return b==0 and 1 or 0 end,
 GetContainerItemInfo=function() return {itemID=10,stackCount=3,isBound=false,isLocked=false} end}
A.Go("sell");local sell=A.Page("sell");Press.Must(sell.list.rows[1]);sell.price:SetText("333")
Press.Must(sell.detail.market);Settle();same(A.Mode(),"market");same(p.selected,10)
A.Go("sell");same(sell.price:GetText(),"","changing pages does not price a posting form")
same(sell.post:IsEnabled(),false)
-- Attributed owned result is passed by identity; navigation cannot cancel/repost.
local Q=W.AuctionReads;Q.Available=function() return true end
Q.snapshot={kind="owned",epoch=Q.epoch,complete=true,rows={{auctionID=2,item=10,itemKey={itemID=10,itemLevel=0,itemSuffix=4},qty=3,total=300,unit=100,status=0}}}
A.Go("owned");local owned=A.Page("owned");Press.Must(owned.list.rows[1]);Press.Must(owned.detail.market);Settle()
same(p.context.itemKey.itemSuffix,4);same(p.projection.facts.min,nil)
A.Hide();same(A.Snapshot().events,0);same(D.Stats().cache,0);same(calls,0)
print("PASSED: Auction Market UI "..n.." checks")
