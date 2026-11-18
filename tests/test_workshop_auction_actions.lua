local count=0
local function Check(x,label) count=count+1;assert(x,label or "check") end
local function Setup() return dofile(TESTS.."auction_debug_mock.lua") end
do
 local c,W,s=Setup();Check(#s.calls==0,"opening sends no search")
 local row=s.Item();local id,d=W.AuctionActions.PrepareBuy(row,2)
 Check(id and d.total==299 and d.quantity==3 and d.excess==1,"exact whole listing, including excess")
 local ok,why=W.AuctionActions.Confirm(id)
 Check(not ok and why:find("hardware",1,true));Check(s.Count("PlaceBid")==0,"unverified mode cannot spend")
 W.AuctionActions.Cancel();Check(W.AuctionActions.Snapshot().listeners==0)
end
for _,bad in ipairs({"price","money","session","combat","owner","snapshot","throttle"}) do
 local c,W,s=Setup();local row=s.Item();c.TwichUI.AuctionBuild.verified.buyItem=true
 local id=W.AuctionActions.PrepareBuy(row,2);Check(id~=nil)
 if bad=="price" then s.items[1].buyoutAmount=300 elseif bad=="money" then s.money=298
 elseif bad=="session" then s.visit=2 elseif bad=="combat" then s.combat=true
 elseif bad=="owner" then row.account=true elseif bad=="snapshot" then W.AuctionReads.End("changed") elseif bad=="throttle" then s.throttle=false end
 Check(not W.AuctionActions.Confirm(id),bad);Check(s.Count("PlaceBid")==0,bad..": no spend")
end
do
 local c,W,s=Setup();c.TwichUI.AuctionBuild.verified.buyItem=true
 local id=W.AuctionActions.PrepareBuy(s.Item(),2)
 Check(W.AuctionActions.Confirm(id));Check(s.Count("PlaceBid")==1)
 local sent=s.calls[#s.calls];Check(sent.args[1]==31 and sent.args[2]==299,"never reconstruct 299 from rounded unit 100")
 W.AuctionActions.Event("AUCTION_HOUSE_PURCHASE_COMPLETED",32);Check(W.AuctionActions.state=="waiting")
 W.AuctionActions.Event("AUCTION_HOUSE_PURCHASE_COMPLETED",31);Check(W.AuctionActions.state=="complete")
 Check(not W.AuctionActions.Confirm(id));Check(s.Count("PlaceBid")==1)
 Check(W.AuctionActions.Snapshot().listeners==0 and W.AuctionActions.Snapshot().timers==0)
end
do
 local c,W,s=Setup();c.TwichUI.AuctionBuild.verified.buyItem=true;s.syncComplete=true
 local id=W.AuctionActions.PrepareBuy(s.Item());Check(W.AuctionActions.Confirm(id))
 Check(W.AuctionActions.state=="complete" and W.AuctionActions.Snapshot().timers==0,"synchronous completion clears deadline")
end
do
 local c,W,s=Setup();s.commodity=true;c.TwichUI.AuctionBuild.verified.buyCommodity=true
 s.commodities={{auctionID=11,itemID=10,quantity=5,unitPrice=100,containsOwnerItem=false,containsAccountItem=false}}
 Check(W.AuctionReads.Begin("commodity",10));W.AuctionReads.Event("COMMODITY_SEARCH_RESULTS_UPDATED",10)
 local id=W.AuctionActions.PrepareBuy(W.AuctionReads.snapshot.rows[1],3);Check(id~=nil)
 s.syncQuote=true;Check(W.AuctionActions.Confirm(id));Check(W.AuctionActions.state=="quoted")
 Check(s.Count("ConfirmCommoditiesPurchase")==0,"quote never spends")
 Check(W.AuctionActions.Review().total==309 and W.AuctionActions.Review().quantity==3)
 Check(W.AuctionActions.Confirm(id,W.AuctionActions.Review()));Check(s.Count("ConfirmCommoditiesPurchase")==1)
 W.AuctionActions.Event("COMMODITY_PRICE_UPDATED",200,600);Check(W.AuctionActions.state=="waiting","late quote cannot rearm")
 W.AuctionActions.Event("COMMODITY_PURCHASE_SUCCEEDED");Check(W.AuctionActions.state=="complete")
end
do
 local c,W,s=Setup();local row=s.Owned();c.TwichUI.AuctionBuild.verified.cancel=true
 Check(W.AuctionActions.PrepareRepost(row));Check(s.Count("CancelAuction")==0)
 local id=W.AuctionActions.PrepareCancel(row);Check(id~=nil)
 Check(W.AuctionActions.Confirm(id));W.AuctionActions.Event("AUCTION_CANCELED",43)
 Check(W.AuctionActions.state=="waiting");W.AuctionActions.Event("AUCTION_CANCELED",42)
 Check(W.AuctionActions.state=="complete");Check(s.Count("PostItem")==0,"no automatic repost")
end
for _,bad in ipairs({"quantity","locked","bound","reserved","deposit","price"}) do
 local c,W,s=Setup();local row=W.AuctionSellData.Bags("")[1];local qty,price=3,100
 if bad=="quantity" then qty=6 elseif bad=="locked" then row.locked=true elseif bad=="bound" then row.bound=true
 elseif bad=="reserved" then row.reserved=1 elseif bad=="deposit" then s.deposit=nil elseif bad=="price" then price=0 end
 Check(not W.AuctionActions.PreparePost(row,qty,price,1),bad);Check(s.Count("PostItem")==0)
end
do
 local c,W,s=Setup();local row=W.AuctionSellData.Bags("")[1];c.TwichUI.AuctionBuild.verified.postItem=true
 local id=W.AuctionActions.PreparePost(row,1,100,1);Check(id~=nil)
 s.qty=6;Check(not W.AuctionActions.Confirm(id),"bag race");Check(s.Count("PostItem")==0)
end
do
 local c,W,s=Setup();local row=W.AuctionSellData.Bags("")[1];c.TwichUI.AuctionBuild.verified.postItem=true
 local id=W.AuctionActions.PreparePost(row,1,100,1);Check(id~=nil)
 s.warning=true;Check(W.AuctionActions.Confirm(id));Check(W.AuctionActions.state=="native-warning")
 Check(s.Count("ConfirmPostItem")==0,"no automatic native warning acceptance")
 c.StaticPopupDialogs.AUCTION_HOUSE_POST_WARNING.OnAccept();Check(s.Count("ConfirmPostItem")==1)
 W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",99);Check(W.AuctionActions.state=="complete")
end
do
 local c,W,s=Setup();c.TwichUI.AuctionBuild.verified.buyItem=true
 local id=W.AuctionActions.PrepareBuy(s.Item());Check(W.AuctionActions.Confirm(id))
 c.C_AuctionHouse.PlaceBid(777,10);Check(W.AuctionActions.state=="unknown")
 W.AuctionActions.Event("AUCTION_HOUSE_PURCHASE_COMPLETED",31);Check(W.AuctionActions.state=="unknown")
 Check(not W.AuctionActions.PrepareBuy(W.AuctionReads.snapshot.rows[1]),"unknown outcome blocks duplicate")
end

-- Multi-tier quantities, account exclusion, rounding and displayed-quote consent.
do
 local c,W,s=Setup();local T,Q=W.AuctionActions,W.AuctionReads
 local rows={{item=10,unit=3,qty=2,ownershipKnown=true},{item=10,unit=5,qty=4,ownershipKnown=true},
  {item=10,unit=1,qty=50,ownershipKnown=true,account=true},{item=10,unit=1,qty=50}}
 Check(T.CommodityEstimate(rows,10,5)==21,"tiered exact total excludes own/unknown stock")
 Check(not T.CommodityEstimate(rows,10,7));Check(not T.CommodityEstimate(rows,10,0))
 rows[1].own=true;Check(not T.CommodityEstimate(rows,10,5))
 local many={};for i=1,500 do many[i]={item=10,unit=i,qty=20,ownershipKnown=true} end
 local start=os.clock();local total=T.CommodityEstimate(many,10,10000)
 Check(total==2505000,"500 tiers / 10,000 actual units")
 print(string.format("AH TIER BENCH 500 tiers / 10,000 units: %.3f ms",(os.clock()-start)*1000))
 s.commodity=true;c.TwichUI.AuctionBuild.verified.buyCommodity=true
 s.commodities={{auctionID=11,itemID=10,quantity=2,unitPrice=100,containsOwnerItem=false,containsAccountItem=false},
  {auctionID=12,itemID=10,quantity=4,unitPrice=200,containsOwnerItem=false,containsAccountItem=false}}
 Check(Q.Begin("commodity",10));Q.Event("COMMODITY_SEARCH_RESULTS_UPDATED",10)
 local id,d=T.PrepareBuy(Q.snapshot.rows[1],5);Check(id and d.total==800 and d.estimated)
 Check(T.Confirm(id));T.Event("COMMODITY_PRICE_UPDATED",161,801)
 local painted=T.Review();T.Event("COMMODITY_PRICE_UPDATED",162,802)
 Check(not T.Confirm(id,painted),"an unseen quote cannot spend");Check(s.Count("ConfirmCommoditiesPurchase")==0)
 s.quoteRemaining=0;Check(not T.Confirm(id,T.Review()),"expired quote cannot spend")
 s.quoteRemaining=0.25;Check(T.Confirm(id,T.Review()));Check(s.Count("ConfirmCommoditiesPurchase")==1)
end
for _,bad in ipairs({"deposit","nativeOwner","nativeQuantity","readException"}) do
 local c,W,s=Setup();local id
 if bad=="deposit" then
  c.TwichUI.AuctionBuild.verified.postItem=true
  id=W.AuctionActions.PreparePost(W.AuctionSellData.Bags("")[1],1,100,1);s.deposit=3
 else
  c.TwichUI.AuctionBuild.verified.buyItem=true;id=W.AuctionActions.PrepareBuy(s.Item())
  if bad=="nativeOwner" then s.items[1].containsAccountItem=true
  elseif bad=="nativeQuantity" then s.items[1].quantity=4
  else c.C_AuctionHouse.GetAuctionInfoByID=function() error("unreadable native value") end end
 end
 Check(id~=nil);Check(not W.AuctionActions.Confirm(id),bad);Check(s.Count("PlaceBid")+s.Count("PostItem")==0)
end
do
 local c,W,s=Setup();c.TwichUI.AuctionBuild.verified.postItem=true
 local id=W.AuctionActions.PreparePost(W.AuctionSellData.Bags("")[1],3,100,1)
 Check(W.AuctionActions.Confirm(id));W.AuctionActions.Event("AUCTION_HOUSE_AUCTION_CREATED",991)
 Check(W.AuctionActions.state=="waiting","one created listing does not complete multisell")
 W.AuctionActions.Event("AUCTION_MULTISELL_FAILURE");Check(W.AuctionActions.state=="unknown")
 Check(s.Count("PostItem")==1,"partial posting never retries")
end

do
 local c,W,s=Setup();c.TwichUI.AuctionBuild.verified.buyItem=true
 local id=W.AuctionActions.PrepareBuy(s.Item());Check(W.AuctionActions.Confirm(id))
 for _,timer in ipairs(LONG_TIMERS) do if timer.d==12 then timer.fn() end end
 Check(W.AuctionActions.state=="unknown","missing completion is not success")
 Check(not W.AuctionActions.Confirm(id));Check(s.Count("PlaceBid")==1,"timeout never retries")
 Check(W.AuctionActions.Snapshot().timers==0 and W.AuctionActions.Snapshot().listeners==0)
end
print("PASSED: integrated auction action controller "..count.." checks (synthetic, no real transactions)")
