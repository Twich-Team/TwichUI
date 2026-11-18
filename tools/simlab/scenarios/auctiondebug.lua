-- Actual Host + five-page UI; only auctioneer/server responses are synthetic.
local R,H=TwichUI,TwichUI.AuctionHost
A_Admin.SetManualClock(GetTime());Lab.Solo();Lab.BUDGET=80
local native=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
native:SetSize(800,538);native:SetPoint("TOPLEFT",UIParent,"TOPLEFT",30,-100)
native:EnableMouse(true);native:SetClampedToScreen(false);native:Show();AuctionHouseFrame=native
AuctionHouseFrameDisplayMode={Buy={}};native.GetDisplayMode=function() return AuctionHouseFrameDisplayMode.Buy end
local connected,calls,transactions=true,0,0
C_PlayerInteractionManager={IsInteractingWithNpcOfType=function() return connected end,IsValidNPCInteraction=function() return connected end}
InCombatLockdown=function() return false end
local rows,full={},true
C_AuctionHouse={IsThrottledMessageSystemReady=function() return true end,
 SendBrowseQuery=function() calls=calls+1 end,SendSearchQuery=function() calls=calls+1 end,QueryOwnedAuctions=function() calls=calls+1 end,
 GetBrowseResults=function() return rows end,HasFullBrowseResults=function() return full end,
 GetNumItemSearchResults=function() return #rows end,GetItemSearchResultInfo=function(_,i) return rows[i] end,HasFullItemSearchResults=function() return full end,
 GetOwnedAuctions=function() return rows end,HasFullOwnedAuctionResults=function() return full end,
 GetItemKeyInfo=function() return {isCommodity=false} end,
 CanCancelAuction=function() return true end,GetCancelCost=function() return 0 end,
 PlaceBid=function() transactions=transactions+1 end,CancelAuction=function() transactions=transactions+1 end}
HideUIPanel=function(f) connected=false;f:Hide();H.Ended() end
local A,Q,f
local function Reach(name,button)
 local hit=R.TestLab.Reach.Analyze(button,{kind="click",evidence="simulator-geometry",limit=1000000})
 Lab.Check("construct",name,"reachable",hit.verdict)
end
Lab.Step("ordinary opt-in",function()
 Lab.Check("init","ordinary preference defaults off",false,H.DebugEnabled())
 R.WorkshopLauncher.SetEnabled(true)
 Lab.Check("interact","debug enable needs no proof",true,H.SetDebug(true))
 Lab.Check("state","choice is saved",true,TwichUIDB.ui.auctionDebug)
 H.Opened();Lab.Settle(.4);A=R.Workshop.AuctionUI;Q=R.Workshop.AuctionReads;f=A.Frame()
 Lab.Check("construct","full interface opens directly","auctioneer",A.Context())
 Lab.Check("state","opening never queries",0,calls)
end)
Lab.Step("live browse and review",function()
 local p=A.Page("browse")
 Reach("live Search reachable",p.submit);p.search:SetText("Peacebloom");p.submit:Click()
 Lab.Check("interact","Search sends one genuine API query",1,calls)
 Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");Lab.Settle(.2)
 Lab.Check("state","complete empty response","empty",Q.state)
 rows={{itemKey={itemID=2447},totalQuantity=3,minPrice=99}}
 p.submit:Click();Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");Lab.Settle(.2)
 Lab.Check("state","repeated Search supported",2,calls)
 p.detail.inspect:Click()
 rows={{auctionID=31,itemKey={itemID=2447},quantity=3,buyoutAmount=299,containsOwnerItem=false,containsAccountItem=false}}
 Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=2447});Lab.Settle(.2)
 Reach("review buyout reachable",p.detail.buy);p.detail.buy:Click();Lab.Settle(.1)
 local d=R.Workshop.AuctionActions.Review()
 Lab.Check("state","review keeps exact whole-listing total",299,d and d.total)
 Lab.Check("state","unverified native mode stays disabled",false,d and d.allowed)
 Lab.Check("state","reviews never spend",0,transactions)
 A.HideReview()
 Reach("Debug button reachable",f.debug);f.debug:Click();Lab.Settle(.1)
 Lab.Check("construct","optional integrated diagnostics shown",true,A.DebugShown())
 f.debug:Click()
end)
Lab.Step("five pages and explicit owned refresh",function()
 for _,key in ipairs({"shopping","sell","owned","market","browse"}) do
  Reach("navigation "..key,A.nav[key]);A.nav[key]:Click();Lab.Settle(.2)
  Lab.Check("interact","visible page "..key,key,A.Mode())
 end
 Lab.Check("state","navigation sends no queries",3,calls)
 A.Go("owned");Lab.Settle(.2);local p=A.Page("owned")
 rows={{auctionID=41,itemKey={itemID=2447},quantity=2,buyoutAmount=200,status=0}}
 Reach("owned refresh reachable",p.refresh);p.refresh:Click();Q.Event("OWNED_AUCTIONS_UPDATED");Lab.Settle(.2)
 Lab.Check("state","owned listing response",1,#p.rows)
 p.selected=41;A.Render();p.cancel:Click();Lab.Settle(.1)
 local d=R.Workshop.AuctionActions.Review()
 Lab.Check("state","cancellation review exists","cancel",d and d.kind)
 Lab.Check("state","cancel remains native gated",false,d and d.allowed)
 Lab.Check("state","owned refresh sends only its query",4,calls)
 A.Go("browse");Lab.Settle(.2)
end)
Lab.Step("same visit switching and persistent choice",function()
 local visit=H.Snapshot().visit
 f.blizzard:Click();Lab.Settle(.2)
 Lab.Check("state","switch returns Blizzard","blizzard",H.Snapshot().state)
 Lab.Check("state","native anchors restored",30,select(4,native:GetPoint(1)))
 Reach("return control reachable",H.Control());H.Control():Click();Lab.Settle(.2)
 Lab.Check("interact","return uses same visit",visit,H.Snapshot().visit)
 Lab.Check("state","return opens full frame","twichui",H.Snapshot().state)
 Lab.RunUntil(61)
 Lab.Check("state","normal debug has no 30 second lease","twichui",H.Snapshot().state)
 Lab.Check("interact","debug off restores Blizzard",true,H.SetDebug(false))
 Lab.Check("state","off choice is saved",false,TwichUIDB.ui.auctionDebug)
 Lab.Check("state","off restores exact native position",30,select(4,native:GetPoint(1)))
 Lab.Check("state","hidden page jobs released",0,A.Snapshot().jobs)
 Lab.Check("state","hidden page listeners released",0,A.Snapshot().events)
 Lab.Check("state","hidden read timers released",0,Q.Snapshot().timers)
 Lab.Check("state","no money-moving API calls",0,transactions)
 Lab.Check("state","native remains visible",true,native:IsVisible())
end)
Lab.Finish()
