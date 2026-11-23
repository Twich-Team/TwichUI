local count=0
local function Check(x,label) count=count+1;assert(x,label or "check") end
local function Setup() return dofile(TESTS.."auction_debug_mock.lua") end
do
 local c,W,s,Press=Setup();local A,Q=W.AuctionUI,W.AuctionReads
 Check(#s.calls==0,"showing complete frame never starts a query")
 A.ToggleDebug();Check(A.DebugShown(),"first click shows diagnostics");A.ToggleDebug();Check(not A.DebugShown())
 local p=A.Page("browse");Check(p.liveMode and p.submit.text:GetText()=="Search")
 p.search:SetText("Peacebloom");Press.Must(p.submit)
 Check(s.Count("SendBrowseQuery")==1 and Q.state=="loading")
 Q.Event("OWNED_AUCTIONS_UPDATED");Check(Q.Pending()==1,"unrelated response ignored")
 Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
 Check(Q.state=="empty" and Q.snapshot.complete and #Q.snapshot.rows==0,"completed empty is explicit")
 A.Render();Check(p.list.empty:GetText():find("completed",1,true)~=nil)
 Press.Must(p.submit);Check(s.Count("SendBrowseQuery")==2,"normal refresh/repeat has no one-query lease")
 s.browse={{itemKey={itemID=10},totalQuantity=3,minPrice=99}}
 Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");A.Render()
 Check(#p.rows==1 and p.rows[1].source=="live")
 Press.Must(p.list.rows[1]);Check(s.Count("SendSearchQuery")==1)
 s.items={{auctionID=4,itemKey={itemID=10},quantity=3,buyoutAmount=299,containsOwnerItem=false,containsAccountItem=false}}
 Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=11});Check(Q.Pending()==1)
 Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10});A.Render()
 Check(p.rows[1].total==299 and p.rows[1].unit==299)
 Press.Must(p.detail.buy);Check(W.AuctionActions.Review().total==299)
 Check(not W.AuctionActions.Review().allowed,"native activation remains per-mode")
 A.Go("market");Check(W.AuctionActions.Review()==nil,"navigation invalidates an old confirmation")
 A.Hide();Check(A.Snapshot().jobs==0 and A.Snapshot().events==0 and A.Snapshot().timers==0)
 Check(Q.Snapshot().timers==0,"closing cancels owned read timers")
end
do
 local c,W,s=Setup();local Q=W.AuctionReads;s.full=false
 Check(Q.Begin("browse",{searchString="empty",sorts={}}));Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
 Check(Q.state=="unverified" and not Q.snapshot.complete,"partial absence never means empty AH")
 Check(Q.More());Check(s.Count("RequestMoreBrowseResults")==1,"continuation requires a click")
 s.full=true;Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");Check(Q.snapshot.complete)
end
do
 local c,W,s=Setup();local Q=W.AuctionReads
 s.browse={};for i=1,20000 do s.browse[i]={itemKey={itemID=i},totalQuantity=1,minPrice=i} end
 local start=os.clock();Check(Q.Begin("browse",{searchString="large",sorts={}}));Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
 Check(#Q.snapshot.rows==500 and Q.snapshot.rawCount==20000 and not Q.snapshot.complete,"large snapshots remain bounded and honestly partial")
 print(string.format("AH LIVE BENCH 20,000 native rows / 500 validated: %.3f ms",(os.clock()-start)*1000))
end
do
 local c,W,s=Setup();local Q=W.AuctionReads
 Check(Q.Begin("browse",{searchString="old",sorts={}}));s.visit=2;Q.AttachVisit(2)
 Check(Q.Pending()==0 and Q.snapshot==nil)
 Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");Check(Q.snapshot==nil,"closed-visit reply has no pending intent")
 Check(Q.Begin("browse",{searchString="current",sorts={}}));Q.Foreign()
 Check(Q.Pending()==0 and not Q.Available() and Q.Snapshot().state=="unattributed native query")
end

do
 local c,W,s=Setup();local Q=W.AuctionReads;s.full=false
 Check(Q.Begin("browse",{searchString="stream",sorts={}}));Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
 s.browse={{itemKey={itemID=10},totalQuantity=2,minPrice=5}};s.full=true
 Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
 Check(Q.snapshot.complete and #Q.snapshot.rows==1,"passive continuation updates the current partial response")
 Check(s.Count("SendBrowseQuery")==1,"streaming never sends another query")
 s.throttle=false;Check(not Q.Refresh());Check(Q.Snapshot().error:find("busy",1,true)~=nil,"refused action is visible")
end

do
 local c,W,s=Setup();s.commodity=true
 local row=W.AuctionSellData.Bags("")[1];local request=W.AuctionSellData.Search(row)
 Check(request~=nil,"Sell commodity competition uses its native read mode")
 s.commodities={{auctionID=91,itemID=10,quantity=2,unitPrice=400,containsOwnerItem=false,containsAccountItem=false}}
 W.AuctionReads.Event("COMMODITY_SEARCH_RESULTS_UPDATED",10)
 local ctx=W.AuctionSellData.Competition(row,request)
 Check(ctx.source=="live" and ctx.complete and #ctx.rows==1 and ctx.rows[1].unit==400,"Sell shows actual commodity competition")
end

do
 local c,W,s,Press,g=Setup();local A,S=W.AuctionUI,W.Session;s.qty=0
 g.recipes={[1]={name="Test recipe",diff=1}};g.filtered={1};g.bags={[10]=0,[90]=0}
 g.schem[1]={outputItemID=90,quantityMin=1,quantityMax=1,reagentSlotSchematics={
  {reagentType=1,reagents={{itemID=10}},quantityRequired=5,required=true}}}
 Check(S.Observe());local rec=S.Current().recipes[1];W.Observe.Fill(rec);Check(S.Add(rec));S.PickSource(10,"auction")
 A.Go("shopping");for i=1,45 do FlushTimers() end;A.Render()
 local p=A.Page("shopping");Check(p.detail.data.row.qty==5 and p.detail.buy:IsEnabled(),"actual crafting deficit enables acquisition search")
 Press.Must(p.detail.buy);Check(A.Mode()=="shopping" and s.Count("SendSearchQuery")==1,"quick buy stays on Shopping")
 s.items={{auctionID=44,itemKey={itemID=10},quantity=7,buyoutAmount=699,containsOwnerItem=false,containsAccountItem=false}}
 W.AuctionReads.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10});A.Render()
 local d=W.AuctionActions.Review();Check(d.desired==1 and d.quantity==1 and d.excess==0 and d.total==699,"individual acquisition reviews one item, not the available stock")
 Check(W.Queue.Count()==1 and g.bags[10]==0,"review does not invent acquired stock")
end
do
 local c,W,s,Press=Setup();local A,S,Q=W.AuctionUI,W.Session,W.Queue
 assert(Q.Add({id=9001,name="Synthetic queued output",icon=1,outItem=90,outMin=1,outMax=1,mats={{item=10,qty=2}}},3))
 W.Window.Show();W.Window.SetMode("craft")
 local craft=W.Window.Craft();craft.segQueue:GetScript("OnClick")(craft.segQueue)
 local row=W.Window.Lists().queue.rows[1]
 Check(W.Window.IsShown() and A.IsShown() and not W.suspended,"queue and integrated AH coexist without a lifecycle change")
 Check(A.Frame().brand:GetParent():GetScript("OnDragStart")~=nil,"existing draggable AH can expose the Workshop beneath it")
 local linked=0;c.ChatEdit_InsertLink=function() linked=linked+1 end
 c.IsModifiedClick=function() return true end;c.IsShiftKeyDown=function() return true end
 row.iconBtn:GetScript("OnClick")(row.iconBtn,"LeftButton")
 Check(s.Count("SendSearchQuery")==1,"output shortcut sends one search")
 local request=s.calls[#s.calls]
 Check(request.name=="SendSearchQuery" and request.args[1].itemID==90,"search targets output, never reagent 10")
 Check(linked==0 and Q.Find(9001).crafts==3,"AH shortcut neither links nor changes queue")
 Check(s.Count("PlaceBid")==0 and s.Count("StartCommoditiesPurchase")==0 and s.Count("PostItem")==0,"search initiates no purchase or posting")
 s.throttle=false
 row:GetScript("OnClick")(row,"LeftButton")
 Check(s.Count("SendSearchQuery")==1 and S.Note():find("couldn't search",1,true),"refused search has guidance and no retry")
 s.throttle=true
 Q.Find(9001).outItem=nil
 row:GetScript("OnClick")(row,"LeftButton")
 Check(s.Count("SendSearchQuery")==1 and S.Note():find("no known output",1,true),"missing output never searches materials")
 Q.Find(9001).outItem=90
 s.debug=false
 Check(not S.SearchQueuedOutput(9001) and s.Count("SendSearchQuery")==1,"unavailable live context refuses search")
 A.Hide();Check(A.Show())
 local info=c.C_Item.GetItemInfo
 c.C_Item.GetItemInfo=function(id) return "Output", "item:"..id end
 row.iconBtn:GetScript("OnClick")(row.iconBtn,"LeftButton")
 Check(linked==1 and s.Count("SendSearchQuery")==1,"standalone preview preserves existing chat-link behavior")
 A.Hide();row.iconBtn:GetScript("OnClick")(row.iconBtn,"LeftButton")
 Check(linked==2 and s.Count("SendSearchQuery")==1,"closed AH preserves existing chat-link behavior")
 c.C_Item.GetItemInfo=info
 Check(not S.SearchQueuedOutput(9001),"direct call cannot create an AH visit")
end
print("PASSED: integrated live search "..count.." checks")
