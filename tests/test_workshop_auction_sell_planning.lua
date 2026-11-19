-- Real queue, cooperative planner and Sell view over synthetic auction APIs.
local c,W,s,Press,g=dofile(TESTS.."auction_debug_mock.lua")
local build=assert(loadfile(ROOT.."auction/Build.lua"));setfenv(build,c);build()
W.AdvisorData.Reserved=s.RealReserved
local A,Q,D,T=W.AuctionUI,W.AuctionReads,W.AuctionSellData,W.AuctionActions
local build=assert(loadfile(ROOT.."auction/Build.lua"));setfenv(build,c);build()
W.AdvisorData.Reserved=s.RealReserved
local checks=0
local function Check(v,why) checks=checks+1;assert(v,why or "Sell planning regression") end
local function Same(a,b,why) Check(a==b,(why or "value")..": "..tostring(a).." ~= "..tostring(b)) end
local callbacks={}
c.C_Timer.After=function(delay,fn) if delay<=1 then callbacks[#callbacks+1]=fn end end
local function Drain()
 local n=0
 while #callbacks>0 do
  n=n+1;Check(n<1000,"cooperative work finishes")
  local batch=callbacks;callbacks={};for _,fn in ipairs(batch) do fn() end
 end
end
local function Recipe(id,item)
 return {id=id,name="Synthetic craft "..id,outItem=100+id,outMin=1,outMax=1,mats={{item=item,qty=2}}}
end
g.bags[10],g.bags[11],g.bags[101],g.bags[102]=5,7,0,0
Check(W.Queue.Add(Recipe(1,11),1))
W.Strategy.FIRST=0 -- force the actual cooperative path, never a synchronous stub
A.Go("owned");Q.Event("OWNED_AUCTIONS_UPDATED")
local beforeStrategies,beforeStocks=W.Strategy.ListenerCount(),W.Storage.ListenerCount()
A.Go("sell");local p=A.Page("sell")
Same(p.planState,"planning");Same(W.Strategy.Stats().started,1,"Sell initiates the shared plan")
Check(A.Frame().busy:IsShown());Check(A.Frame().busy.text:GetText():find("crafting",1,true))
Same(W.Strategy.ListenerCount(),beforeStrategies+1);Same(W.Storage.ListenerCount(),beforeStocks+1)
Press.Must(p.list.rows[1]);Check(p.chosen.pending)
Check(not p.max:IsEnabled() and not p.post:IsEnabled(),"pending plan still protects posting")
Same(s.Count("SendSearchQuery"),1,"pending reservations do not suppress read-only competition")
s.items={{auctionID=31,itemKey={itemID=10},quantity=9,buyoutAmount=300,containsOwnerItem=false,containsAccountItem=false}}
Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10});A.Render()
Check(p.autoPrice~=nil,"completed listing response waits for planning")
Same(s.Count("PostItem"),0)
Drain()
Same(p.planState,"ready");Check(not p.chosen.pending);Same(p.chosen.reserved,0,"unrelated queued material does not reserve this item")
Check(not A.Frame().busy:IsShown());Check(p.max:IsEnabled())
Same(p.money:GetCopper(),300,"deferred competition supplies the unit price")
Press.Must(p.max);Same(p.quantity:GetText(),"5");Same(p.draft.gross,1500)
Check(p.post:IsEnabled());Same(p.grossValue:GetText(),W.UI.Money(1500));Same(p.depositValue:GetText(),W.UI.Money(2))
Same(p.feesValue:GetText(),"Not yet verified","unknown fees never become zero")
Same(p.grossValue:GetParent():GetParent(),p.post:GetParent(),"totals and review share a fixed footer")
Same(p.post:GetParent():GetParent(),p,"footer is outside the scroll child")
Press.Must(p.post);Check(T.Review()~=nil);Same(s.Count("PostItem"),0,"opening a review never posts")
A.HideReview()
local epoch=W.Strategy.epoch
Check(W.Storage.SetUseGuild(true));Same(W.Strategy.epoch,epoch+1,"stock change invalidates planning immediately")
Drain();Same(p.planState,"ready")
local id=T.PreparePost(p.chosen,5,300,1);Check(id~=nil);Check(T.Review().allowed,"reservation race must not pass through a disabled capability")
Check(W.Queue.Add(Recipe(2,10),1));W.Strategy.Bump()
T.Confirm(id);Same(s.Count("PostItem"),0,"new reservations block a previously reviewed post")
T.Cancel();Drain()
Check(p.chosen.reserved>=2,"actual queued demand remains protected")
Check(not p.max:IsEnabled() and not p.post:IsEnabled())
epoch=W.Strategy.epoch
p:GetScript("OnEvent")(p,"BAG_UPDATE_DELAYED");Same(W.Strategy.epoch,epoch+1)
Drain();Same(p.planState,"ready")
A.Go("owned");Q.Event("OWNED_AUCTIONS_UPDATED");Same(p.planState,nil)
Same(W.Strategy.ListenerCount(),beforeStrategies);Same(W.Storage.ListenerCount(),beforeStocks)
epoch=W.Strategy.epoch
W.Storage.SetUseGuild(false);Same(W.Strategy.epoch,epoch,"hidden Sell no longer observes stock")
Drain();A.Hide();Same(A.Snapshot().subscriptions,0)
Same(s.Count("PostItem")+s.Count("PostCommodity"),0,"no event or calculation posts an auction")
print("PASSED: Sell planning and footer regressions "..checks.." checks (synthetic only)")
