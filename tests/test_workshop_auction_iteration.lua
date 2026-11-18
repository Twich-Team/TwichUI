-- Owner-requested real workflows over synthetic native records. No actual game
-- calls or player data: every transaction below is a recording sentinel.
local count=0
local function Check(value,why) count=count+1;assert(value,why or "iteration check") end
local function Same(a,b,why) Check(a==b,(why or "value")..": "..tostring(a).." ~= "..tostring(b)) end
local function Setup()
    local c,W,s,Press,g=dofile(TESTS.."auction_debug_mock.lua")
    local chunk=assert(loadfile(ROOT.."auction/Build.lua"));setfenv(chunk,c);chunk()
    return c,W,s,Press,g
end
-- Preferences work without loading settings, never mutate on read, preserve false,
-- validate inputs, and respect the active profile and future-data hold.
do
    local c,W,s=Setup();local L=c.TwichUI.WorkshopLauncher
    Same(c.TwichUIDB.ui.auctionHouse,nil)
    local d=L.AuctionSettings();Check(not d.advisorOnly and d.maxQuantity and d.duration==1)
    Same(c.TwichUIDB.ui.auctionHouse,nil,"reading defaults writes nothing")
    Check(L.SetAuctionOption("maxQuantity",false));Check(L.SetAuctionOption("advisorOnly",true));Check(L.SetAuctionOption("duration",3))
    d=L.AuctionSettings();Check(not d.maxQuantity and d.advisorOnly and d.duration==3)
    for _,value in ipairs({0,4,1.5,"2"}) do Check(not L.SetAuctionOption("duration",value)) end
    Check(not L.SetAuctionOption("maxQuantity",1));Check(not L.SetAuctionOption("unknown",true))
    local held=c.TwichUI.Persist;c.TwichUI.Persist={IsHeld=function() return true end}
    Check(not L.SetAuctionOption("duration",2));Same(L.AuctionSettings().duration,3)
    c.TwichUI.Persist=held;c.TwichUIDB.ui={workshopEnabled=true}
    Same(L.AuctionSettings().duration,1,"new profile does not reuse old defaults")
    Same(#s.calls,0,"settings never search or transact")
    for _,mode in ipairs({"buyItem","buyCommodity","postItem","postCommodity","cancel"}) do Check(W.AuctionActions.Capability(mode),mode) end
    Same(next(c.TwichUI.AuctionBuild.verified),nil,"activation never claims native verification")
end
-- Across normal and reagent bags: 5 + 7 + 11 = 23; 23 * 100 = 2300 copper.
-- The original native bag key is distinct from the base-ID commodity search key.
do
    local c,W,s=Setup();s.commodity=true
    local slots={[0]={{qty=5},{qty=7}},[5]={{qty=11}}}
    c.NUM_TOTAL_EQUIPPED_BAG_SLOTS=5;c.NUM_BAG_SLOTS=4
    c.C_Container.GetContainerNumSlots=function(bag) return #(slots[bag] or {}) end
    c.C_Container.GetContainerItemInfo=function(bag,slot)
        local x=(slots[bag] or {})[slot];if not x then return end
        return {itemID=10,stackCount=x.qty,isLocked=x.locked==true,isBound=x.bound==true,hyperlink="item:10:0:0:0:0:0:0"}
    end
    c.C_AuctionHouse.GetItemKeyFromItem=function() return {itemID=10,itemLevel=60} end
    c.C_AuctionHouse.GetAvailablePostCount=function() return 23 end
    local D,T=W.AuctionSellData,W.AuctionActions;local rows=D.Bags("");Same(#rows,1);Same(rows[1].qty,23);Same(rows[1].stacks,3)
    Same(D.Max(rows[1]),23);Same(rows[1].itemKey.itemLevel,0);Same(rows[1].bagItemKey.itemLevel,60)
    local id,review=T.PreparePost(rows[1],23,100,1);Check(id);Same(review.total,2300)
    Same(s.Count("PostCommodity"),0,"review never posts")
    slots[5][1].qty=12;Check(not D.BagCurrent(rows[1]));Check(not T.Confirm(id));Same(s.Count("PostCommodity"),0,"member race never posts")
    T.Cancel();slots[5][1].qty=11;rows=D.Bags("");id=T.PreparePost(rows[1],23,100,1);Check(id)
    slots[0][1].qty=4;slots[0][2].qty=8
    Check(not T.Confirm(id));Same(s.Count("PostCommodity"),0,"equal total cannot hide changed physical members")
    T.Cancel();slots[0][1].qty=5;slots[0][2].qty=7;slots[0][1].locked=true
    rows=D.Bags("");Same(#rows,1);Same(rows[1].qty,23);Same(D.Max(rows[1]),18,"locked copies excluded")
    Check(D.BagCurrent(rows[1]));slots[5][1].bound=true
    rows=D.Bags("");Same(rows[1].qty,12,"bound reagent copies excluded")
end
-- Sell consumes saved defaults when creating a new draft, without overwriting
-- a current draft when a default changes in the background.
do
    local c,W,s,Press=Setup();local L=c.TwichUI.WorkshopLauncher;local A=W.AuctionUI
    L.SetAuctionOption("maxQuantity",false);L.SetAuctionOption("duration",2)
    A.Go("sell");local p=A.Page("sell");Press.Must(p.list.rows[1])
    Same(p.quantity:GetText(),"1");Same(p.durationIndex,2)
    W.AuctionReads.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10});A.Render()
    L.SetAuctionOption("duration",3);L.SetAuctionOption("maxQuantity",true)
    Same(p.durationIndex,2,"current draft retains its duration")
    Press.Must(p.list.rows[1]);Same(p.quantity:GetText(),"5");Same(p.durationIndex,3)
    W.AuctionReads.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10});A.Go("browse")
    L.SetAuctionOption("advisorOnly",true);A.Go("sell");Check(p.advisorOnly and p.advisorFilter.on)
end
-- Available stock is not a stack: exactly 49,999 per item, without division.
do
    local c,W,s=Setup()
    local row=W.AuctionReads.Listing({auctionID=31,itemKey={itemID=10},quantity=9,buyoutAmount=49999,containsOwnerItem=false,containsAccountItem=false},"item")
    Same(row.qty,9);Same(row.unit,49999);Same(row.total,49999);Same(row.purchaseQty,1)
    Check(not W.AuctionReads.Fresh({epoch=W.AuctionReads.epoch}),"missing time is unusable, not a Lua error")
end
-- Direct commodity review and authoritative consent; failure refreshes the book,
-- then another explicit quote/confirmation is required. No event spends gold.
do
    local c,W,s=Setup();s.commodity=true;local T,Q,A=W.AuctionActions,W.AuctionReads,W.AuctionUI
    Check(A.RequestBuy({itemKey={itemID=10},unit=49999},2));Same(s.Count("StartCommoditiesPurchase"),1);Same(s.Count("ConfirmCommoditiesPurchase"),0)
    Same(s.Count("SendSearchQuery"),0,"quantity review does not redirect into an item search")
    T.Event("COMMODITY_PRICE_UPDATED",59999,119998);local shown=T.Review();Same(shown.quantity,2);Same(shown.total,119998)
    T.Event("COMMODITY_PRICE_UPDATED",60000,120000);Check(not T.Confirm(shown.id,shown));Same(s.Count("ConfirmCommoditiesPurchase"),0)
    Check(T.Confirm(shown.id,T.Review()));Same(s.Count("ConfirmCommoditiesPurchase"),1)
    T.Event("COMMODITY_PURCHASE_FAILED");Same(s.Count("ConfirmCommoditiesPurchase"),1);Same(s.Count("SendSearchQuery"),1)
    s.commodities={{itemID=10,quantity=9,unitPrice=61000,containsOwnerItem=false,containsAccountItem=false}}
    Q.Event("COMMODITY_SEARCH_RESULTS_UPDATED",10);shown=T.Review();Check(shown and shown.retry);Same(shown.total,122000)
    Check(T.Confirm(shown.id,shown));Same(s.Count("ConfirmCommoditiesPurchase"),1,"retry requests a quote only")
    T.Event("COMMODITY_PRICE_UPDATED",62000,124000);Check(T.Confirm(shown.id,T.Review()));Same(s.Count("ConfirmCommoditiesPurchase"),2)
    T.Event("COMMODITY_PURCHASE_SUCCEEDED");Same(T.state,"complete")
end
-- Page entry, sold/active totals, passive updates, countdowns and native cancel
-- ownership. Three active buyouts of 400, one bid of 200: posted 600, incoming 900.
do
    local c,W,s,Press=Setup();local A,Q,T=W.AuctionUI,W.AuctionReads,W.AuctionActions
    c.ITEM_QUALITY_COLORS={[2]={r=.1,g=1,b=.2}}
    c.C_Item.GetItemInfo=function(id) return "Green herb","item:10",2 end
    local tooltip
    c.GameTooltip.SetItemByID=function(_,id) tooltip=id end
    c.GameTooltip.SetHyperlink=function(_,link) tooltip=link end
    A.Go("owned");local p=A.Page("owned");Same(s.Count("QueryOwnedAuctions"),1,"entry requests owned results")
    s.owned={{auctionID=1,itemKey={itemID=10},quantity=2,buyoutAmount=400,status=0,timeLeftSeconds=3600},
        {auctionID=2,itemKey={itemID=11},quantity=3,buyoutAmount=900,status=1,timeLeftSeconds=120},
        {auctionID=3,itemKey={itemID=10},quantity=1,bidAmount=200,status=0}}
    Q.Event("OWNED_AUCTIONS_UPDATED");A.Render();Same(p.activeValue:GetText(),"2");Same(p.soldValue:GetText(),"1")
    Same(p.postedValue:GetText(),W.UI.Money(600));Same(p.incomingValue:GetText(),W.UI.Money(900))
    Same(p.list.rows[1].name.textColor[2],1,"uncommon title is green")
    p.list.rows[1]:GetScript("OnEnter")(p.list.rows[1]);Same(tooltip,10,"hover opens the native item tooltip")
    Same(p.list.rows[1].name.textColor[2],1,"uncommon name uses quality color")
    p.list.rows[1]:GetScript("OnEnter")(p.list.rows[1]);Same(tooltip,10,"hover opens the native item tooltip")
    Press.Must(p.list.rows[2]);Check(p.list.rows[2].sold:IsShown());Check(not p.cancel:IsEnabled());Same(p.time:GetText(),"2m")
    s.now=61;p.clock.fn();Same(p.time:GetText(),"1m")
    -- An unsolicited cache update must still be consumed after initial completion.
    s.owned[1].status=1;Q.Event("OWNED_AUCTIONS_UPDATED");A.Render();Same(p.soldValue:GetText(),"2");Same(s.Count("QueryOwnedAuctions"),1)
    Same(p.incomingValue:GetText(),W.UI.Money(1300));Same(p.postedValue:GetText(),W.UI.Money(200))
    Press.Must(p.list.rows[3]);Press.Must(p.cancel);local review=T.Review();Check(review and review.kind=="cancel");Same(s.Count("CancelAuction"),0)
    s.owned[3].status=1;T.Confirm(review.id,review);Same(s.Count("CancelAuction"),0,"a sold auction cannot be cancelled")
    T.Cancel();local clock=p.clock;A.Go("browse");Check(clock.cancelled);Same(p.clock,nil);A.Hide();Same(A.Snapshot().timers,0)
end
-- Back restores bounded prior results; focus/shift insertion changes only text.
do
    local c,W,s,Press=Setup();local A,Q=W.AuctionUI,W.AuctionReads;local p=A.Page("browse")
    c.AuctionCategories={{name="Weapons",filters={{classID=2}}},{name="Token",flags={WOW_TOKEN_FLAG=true}},{name="Reagents",filters={{classID=5}}}}
    local categories=W.AuctionCategories.Tree();Same(#categories,2,"Forever omits WoW Token")
    Same(W.AuctionCategories.Art(categories[1]),"npc:sword-and-shield");Same(W.AuctionCategories.Art(categories[2]),"npc:reagent-pouch")
    c.AuctionHouseFrame={SetSearchText=function() end};c.IsModifiedClick=function() return true end
    A.Render();p.search:SetFocus();local queries=s.Count("SendBrowseQuery")
    c.AuctionHouseFrame:SetSearchText("Peacebloom");Same(p.search:GetText(),"Peacebloom");Same(s.Count("SendBrowseQuery"),queries)
    p.search:ClearFocus();c.AuctionHouseFrame:SetSearchText("Ignored");Same(p.search:GetText(),"Peacebloom")
    Press.Must(p.submit);s.browse={{itemKey={itemID=10},totalQuantity=9,minPrice=49999}}
    Q.Event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED");A.Render();Press.Must(p.list.rows[1]);A.Render();Check(p.back:IsShown())
    s.items={{auctionID=31,itemKey={itemID=10},quantity=9,buyoutAmount=49999,containsOwnerItem=false,containsAccountItem=false}}
    Q.Event("ITEM_SEARCH_RESULTS_UPDATED",{itemID=10});A.Render();Same(p.rows[1].unit,49999)
    local sent=s.Count("SendBrowseQuery");Press.Must(p.back);Same(p.rows[1].liveKind,"browse");Check(not p.detail:IsShown());Same(s.Count("SendBrowseQuery"),sent)
    Press.Must(p.refreshLive);Same(s.Count("SendBrowseQuery"),sent+1,"cached Browse refresh is not an item refresh")
end
print("PASSED: Auction House iteration regressions "..count.." checks (synthetic only)")
