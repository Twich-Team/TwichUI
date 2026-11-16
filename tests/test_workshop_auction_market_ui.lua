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
A.Market.Filter("scope","all");A.Market.Search("no matching item");Settle()
same(p.tiles[6].value:GetText(),"Choose an item","empty filter is not an absent market")
same(p.source:GetText():find("Choose an item",1,true)~=nil,true)
A.Market.Search("11");Settle()
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
local open=W.UI.Advisor.Open
local advice=0;W.UI.Advisor.Open=function() advice=advice+1 end
Press.Must(p.list.rows[1],{button="RightButton"})
W.UI.Advisor.Open=open
same(advice,0,"row right-click cannot bypass variant safeguard")
-- A filtered-out candidate must still become discoverable when metadata arrives.
A.OpenMarket(11,{market=m.key});Settle();A.Market.Search("Late Herb");Settle()
same(#p.rows,0);same(p.known[11],true,"membership includes filtered-out candidates")
local originalInfo=c.C_Item.GetItemInfo
c.C_Item.GetItemInfo=function(id) if id==11 then return "Late Herb",nil,1,nil,nil,"Trade Goods","Herb",nil,nil,134572,40,7,nil,0 end;return originalInfo(id) end
p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",11,true);Settle()
same(#p.rows,1,"late metadata can enter a text filter");same(p.selected,11)
c.C_Item.GetItemInfo=originalInfo
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
local token=p.token
local metadata=W.AuctionBrowseData.Stats().metadata
p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",9000000,true);Settle()
same(W.AuctionBrowseData.Stats().metadata,metadata,"unrelated metadata is not queued")
same(p.token,token,"unrelated metadata does not rebuild thousands of rows")
p:GetScript("OnEvent")(p,"BAG_UPDATE_DELAYED");Settle()
same(p.token,token,"bag updates do not rebuild non-bag catalogs")
p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",14,true);Settle()
same(p.selected,selected);same(p.rows[math.floor(p.list.scroll:GetVerticalScroll()/60)+1].item,top)
same(p.list.scroll:GetVerticalScroll()%60,17)
A.Market.Range(60);same(p.list.scroll:GetVerticalScroll()%60,17,"range changes do not rebuild catalog")
A.Go("shopping");A.Go("market");Settle()
local frames=#c.testFrames
for i=1,20 do A.Go("shopping");A.Go("market");Settle() end
same(#c.testFrames,frames,"page switching makes no frames")
A.Go("sell");same(p.rows,nil);same(p.index,nil);same(p.known,nil);same(p.projection,nil);same(D.Stats().cache,0)
same(p.listening,false);same(p.job,nil);same(#p.list.data,0)
-- Bags: no bank inventory; navigation does not apply history to a posting form.
c.C_Container={GetContainerNumSlots=function(b) return b==0 and 1 or 0 end,
 GetContainerItemInfo=function() return {itemID=10,stackCount=3,isBound=false,isLocked=false} end}
A.Go("sell");local sell=A.Page("sell");Press.Must(sell.list.rows[1]);sell.money:SetCopper(333)
Press.Must(sell.detail.market);Settle();same(A.Mode(),"market");same(p.selected,10)
A.Go("sell");same(sell.money:GetCopper(),nil,"changing pages does not price a posting form")
same(sell.post:IsEnabled(),false)
-- Attributed owned result is passed by identity; navigation cannot cancel/repost.
local Q=W.AuctionReads;Q.Available=function() return true end
Q.snapshot={kind="owned",epoch=Q.epoch,complete=true,rows={{auctionID=2,item=10,itemKey={itemID=10,itemLevel=0,itemSuffix=4},qty=3,total=300,unit=100,status=0}}}
A.Go("owned");local owned=A.Page("owned");Press.Must(owned.list.rows[1]);Press.Must(owned.detail.market);Settle()
same(p.context.itemKey.itemSuffix,4);same(p.projection.facts.min,nil)
-- Deterministic cancellation, deadline and error terminal states.
local after,resolve,catalog=c.C_Timer.After,D.Resolve,D.Catalog
local timers={}
c.C_Timer.After=function(delay,fn) timers[#timers+1]={delay,fn} end
D.Catalog=function() return {Step=function() return false end} end
A.OpenMarket(10,{market=m.key})
local deadline
for _,t in ipairs(timers) do if t[1]==15 then deadline=t[2] end end
assert(deadline,"deadline always installed")
deadline();same(p.job,nil);same(p.error,"timed out")
for _,t in ipairs(timers) do if t[1]==0 then t[2]() end end
same(p.job,nil,"late callback cannot revive timed-out search")
local fault=c.TwichUI.Fault;local faults=0
c.TwichUI.Fault=function() faults=faults+1 end
D.Resolve=function() error("synthetic unavailable source") end
Press.Must(p.refresh);same(p.job,nil);same(p.error,"unavailable");same(p.tiles[6].value:GetText(),"No saved market")
c.TwichUI.Fault=fault;same(faults,1,"setup failure reported once")
D.Resolve,D.Catalog,c.C_Timer.After=resolve,catalog,after
A.OpenMarket(10,{market=m.key});Settle()
local format=c.date
local utc=false;c.date=function(f,at) utc=utc or f=="!%b %d";return format(f,at) end
A.Market.Range(7);c.date=format;same(utc,true,"UTC-day labels use UTC formatting")
A.Hide();same(A.Snapshot().events,0);same(D.Stats().cache,0);same(calls,0)
print("PASSED: Auction Market UI "..n.." checks")
