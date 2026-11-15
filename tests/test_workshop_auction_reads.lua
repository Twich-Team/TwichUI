local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W=c.TwichUI.Workshop
local Q,D=W.AuctionReads,W.AuctionSellData
local n=0
local function same(a,b,why) n=n+1;assert(a==b,(why or "").." expected "..tostring(b).." got "..tostring(a)) end
local active=true
c.Enum={PlayerInteractionType={Auctioneer=21}}
c.C_PlayerInteractionManager={IsInteractingWithNpcOfType=function() return active end,IsValidNPCInteraction=function() return active end}
local calls,reads=0,0
c.hooksecurefunc=function() end
local own={}
c.C_AuctionHouse={
 IsThrottledMessageSystemReady=function() return true end,
 SendBrowseQuery=function() calls=calls+1 end,SendSearchQuery=function() calls=calls+1 end,
 QueryOwnedAuctions=function() calls=calls+1 end,
 GetBrowseResults=function() reads=reads+1;return {{itemKey={itemID=10},totalQuantity=12,minPrice=100}} end,
 HasFullBrowseResults=function() return false end,
 GetOwnedAuctions=function() reads=reads+1;return own end,
 GetNumItemSearchResults=function() return 1 end,
 GetItemSearchResultInfo=function() return {itemKey={itemID=10},auctionID=13,quantity=3,buyoutAmount=299} end,
 HasFullItemSearchResults=function() return true end,
}
same(Q.Begin("browse",{searchString="ore",sorts={}}),false,"default off")
same(calls,0)
Q.EnableExperimental(true)
same(Q.Available(),false,"opt-in needs fresh visit")
Q.Event("AUCTION_HOUSE_SHOW")
same(Q.Available(),true)
same(Q.Begin("browse",{searchString="ore",sorts={}}),true)
same(calls,1)
Q.Event("OWNED_AUCTIONS_UPDATED")
same(reads,0,"unrelated cache never read")
Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
same(reads,1);same(Q.snapshot.complete,false);same(Q.snapshot.rows[1].unit,100)
same(Q.Begin("browse",{searchString="new",sorts={}}),false,"no-payload repeat cannot be attributed")
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
same(Q.Begin("item",{itemID=10,itemSuffix=2}),true)
Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10})
same(Q.snapshot,nil,"full key ownership")
Q.Cancel()
Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10,itemSuffix=2})
same(Q.snapshot,nil,"canceled result ignored")
same(Q.Available(),false,"cancel poisons epoch")
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
same(Q.Begin("item",{itemID=10}),true)
Q.Foreign()
Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10})
same(Q.snapshot,nil,"foreign request invalidation")
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
same(Q.Begin("owned"),true)
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("OWNED_AUCTIONS_UPDATED")
same(Q.snapshot,nil,"old session result ignored")
Q.Event("AUCTION_HOUSE_SHOW")
same(Q.Begin("owned"),true)
own={{auctionID=42,itemKey={itemID=10},quantity=3,buyoutAmount=299,status=0,timeLeftSeconds=0}}
Q.Event("OWNED_AUCTIONS_UPDATED")
same(Q.snapshot.rows[1].unit,100,"ceil unit");same(Q.snapshot.rows[1].total,299,"exact total retained")
same(Q.snapshot.rows[1].seconds,0,"expired-looking remains native active")
same(Q.snapshot.complete,false,"owned completeness not invented")
local r=Q.Listing({auctionID=1,itemKey={itemID=10},quantity=2,minBid=200})
same(r.total,nil,"bid only not free");same(r.bid,200);same(r.actionable,false)
same(Q.Listing({auctionID=1,itemID=10,quantity=4,unitPrice=19},true).total,76)
same(Q.Listing({auctionID=1,itemID=10,quantity=0,unitPrice=19},true),nil)
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
same(Q.Begin("owned"),true)
active=false;Q.Event("OWNED_AUCTIONS_UPDATED")
same(Q.snapshot,nil,"lost predicates refuse cache")
active=true;Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
same(Q.Begin("owned"),true)
c.C_AuctionHouse.GetOwnedAuctions=function() error("read failure") end
Q.Event("OWNED_AUCTIONS_UPDATED")
same(Q.state,"data unavailable");same(Q.snapshot,nil)
-- Timeout callback is captured independently from unrelated mock timers.
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
local after=c.C_Timer.After
local timeout
c.C_Timer.After=function(delay,fn) if delay==10 then timeout=fn else after(delay,fn) end end
same(Q.Begin("owned"),true);timeout()
same(Q.state,"search timed out");same(Q.Available(),false)
c.C_Timer.After=after
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
c.C_AuctionHouse.HasFullOwnedAuctionResults=function() return true end
own={}
for i=1,600 do own[i]={auctionID=i,itemKey={itemID=10},quantity=2,buyoutAmount=201,status=0} end
c.C_AuctionHouse.GetOwnedAuctions=function() return own end
same(Q.Begin("owned"),true);Q.Event("OWNED_AUCTIONS_UPDATED")
same(#Q.snapshot.rows,500,"bounded native snapshot")
same(Q.snapshot.complete,false,"cap never claims complete")
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW");own={}
same(Q.Begin("owned"),true);Q.Event("OWNED_AUCTIONS_UPDATED")
same(#Q.snapshot.rows,0,"empty native owned response")
same(Q.snapshot.complete,true,"native completeness predicate")
c.Enum.AuctionHouseFilter={RareQuality=9,ExactMatch=4}
c.Enum.AuctionHouseSortOrder={Price=0,Name=1}
local query=Q.BrowseQuery({text="ore",quality=3,exact=true,minLevel=10,maxLevel=20,sort="Name",reverse=true})
same(query.filters[1],9);same(query.filters[2],4)
same(query.minLevel,10);same(query.maxLevel,20)
same(query.sorts[1].sortOrder,1);same(query.sorts[1].reverseSort,true)
same(Q.BrowseQuery({category={filters={}}}),nil,"unsupported category cannot become unfiltered query")
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
c.C_AuctionHouse.GetNumItemSearchResults=function() return 2 end
c.C_AuctionHouse.GetItemSearchResultInfo=function(_,i)
 if i==1 then return {auctionID=12,itemKey={itemID=10},quantity=2,buyoutAmount=201} end
end
same(Q.Begin("item",{itemID=10}),true);Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10})
same(#Q.snapshot.rows,1);same(Q.snapshot.complete,false,"omitted native item record makes partial")
Q.Event("AUCTION_HOUSE_CLOSED");Q.Event("AUCTION_HOUSE_SHOW")
c.C_AuctionHouse.GetBrowseResults=function() return {{}} end
c.C_AuctionHouse.HasFullBrowseResults=function() return true end
same(Q.Begin("browse",{searchString="ore",sorts={}}),true);Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
same(#Q.snapshot.rows,0);same(Q.snapshot.complete,false,"invalid native browse key makes partial")
local row={item=10,qty=20,locked=false,bound=false,eligible=true,reserved=0}
same(D.Draft(row,3,101).gross,303)
for _,qty in ipairs({0,-1,21,1.5}) do same(D.Draft(row,qty,100).valid,false) end
same(D.Draft(row,3,W.Prices.MAX_COPPER).valid,false,"overflow")
row.reserved=1;same(D.Draft(row,1,100).valid,false,"reserved")
row.reserved=0;row.pending=true;same(D.Draft(row,1,100).valid,false,"pending plan")
row.pending=false;row.eligible=nil;same(D.Draft(row,1,100).valid,false,"unknown eligibility")
row.eligible=true;same(D.Draft(row,1,100).deposit,nil,"unknown deposit")
-- Category identity/filter coverage is sourced from the runtime hierarchy.
c.AuctionCategories={{name="Armor",filters={{classID=4}},subCategories={{name="Cloth",filters={{classID=4,subClassID=1}}}}}}
local tree,by=W.AuctionCategories.Tree()
same(#tree,1);same(tree[1].children[1].name,"Cloth")
same(W.AuctionCategories.Matches({classID=4,subClassID=1},by["native:1.1"]),true)
same(W.AuctionCategories.Matches({classID=4,subClassID=2},by["native:1.1"]),false)
local inventoryReads=0
c.C_Item.GetItemInventoryTypeByID=function() inventoryReads=inventoryReads+1;return 3 end
W.AdvisorData.Info(10);same(inventoryReads,0,"shared metadata does not read unused inventory type")
same(W.AuctionCategories.Matches({item=10,classID=4,subClassID=1},{filters={{classID=4,inventoryType=3}}}),true)
same(inventoryReads,1,"inventory filter reads type once")
same(W.AuctionCategories.Matches({item=10,classID=2},{filters={{classID=4,inventoryType=3}}}),false)
same(inventoryReads,1,"unrelated class does not read inventory type")
-- Regression: metadata storms cannot replace a running job.
local A=W.AuctionUI
local native=c.AuctionCategories
c.AuctionCategories=nil
A.Show();local p=A.Page("browse")
same(p.nativeReady,false,"saved category fallback")
c.AuctionCategories=native;A.Render()
same(p.nativeReady,true,"late native category tree upgrades in place")
Press.Must(p.categoryList.rows[2])
same(p.category,"native:1","parent selection")
same(#p.categoryList.data,3,"parent expands")
Press.Must(p.categoryList.rows[3])
same(p.category,"native:1.1","direct child selection")
local job=p.job
for i=1,20 do p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",10,true);A.Render();same(p.job,job,"job not restarted") end
while p.job do FlushTimers() end -- Finish discovery before injecting the next job's callback failure.
-- A throwing timer slice terminates with a visible failed state.
W.AuctionBrowseData.Job=function() return {Step=function() error("callback failure") end} end
A.Browse.Search("error");FlushTimers()
same(p.job,nil);same(p.state,"failed")
local source,fault=W.Market.Source,c.TwichUI.Fault
local faults=0;c.TwichUI.Fault=function() faults=faults+1 end
p.job={Step=function() return false end}
W.Market.Source=function() error("market identity failure") end
A.Browse.Search("source failure")
same(p.job,nil,"failed setup releases superseded job")
same(p.state,"data unavailable");same(faults,1,"setup error is reported")
W.Market.Source=source;c.TwichUI.Fault=fault

p.liveMode=true;Q.state="results"
Q.snapshot={kind="item",epoch=Q.epoch,rows={{auctionID=71,item=10,itemKey={itemID=10},qty=3,total=299,unit=100}}}
A.Render()
same(p.totalHead:GetText(),"Total / bid","live columns do not claim historical estimates")
same(p.scope:GetText():find("Explicit experimental",1,true)~=nil,true)
same(p.rows[1].total,299,"live exact total remains distinct")
same(p.unitHead:GetText(),"Unit price")
Q.snapshot={kind="browse",epoch=Q.epoch,rows={{item=10,itemKey={itemID=10},qty=12,unit=100}}}
A.Render();same(p.unitHead:GetText(),"Native min","group minimum not asserted to be unit price")

A.Hide()
local qty=5
c.C_Container={GetContainerNumSlots=function(bag) return bag==0 and 1 or 0 end,
 GetContainerItemInfo=function() return {itemID=10,stackCount=qty,isLocked=false,isBound=false} end}
c.ItemLocation={CreateFromBagAndSlot=function() return {} end}
c.C_AuctionHouse.IsSellItemValid=function() return true end
A.Show();A.Go("sell");local sell=A.Page("sell")
same(#sell.rows,1,"bags only");Press.Must(sell.list.rows[1]);sell.price:SetText("100")
same(sell.chosen.qty,5);qty=2;A.Render()
same(sell.selected,nil,"bag quantity change invalidates draft selection")
same(sell.price:GetText(),"","bag changes clear unit-price intent")
same(sell.post:IsEnabled(),false)
A.Hide()
A.Show();A.Go("owned")
local owned=A.Page("owned")
local available=Q.Available;Q.Available=function() return true end
Q.state="empty";Q.snapshot={kind="owned",epoch=Q.epoch,complete=true,rows={}}
A.Render()
same(owned.list.empty:GetText(),"No owned listings returned.","empty is distinct from unavailable")
local listing=Q.Listing({auctionID=9,itemKey={itemID=10},quantity=2,buyoutAmount=101,status=0})
Q.snapshot={kind="owned",epoch=Q.epoch,complete=false,rows={listing,listing}}
A.Render()
same(#owned.rows,1,"duplicate native IDs do not duplicate view")
A.Hide();Q.Available=available
print("PASSED: auction reads/drafts/categories "..n.." checks")
