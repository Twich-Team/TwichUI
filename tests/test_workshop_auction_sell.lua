local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W,m,now=dofile(TESTS.."auction_market_fixture.lua")(c)
c.TwichUIWorkshopDB.markets["Realm|Horde"]=nil -- one explicit synthetic market for the Sell context
local A,D,Q=W.AuctionUI,W.AuctionSellData,W.AuctionReads
local n=0
local function same(a,b,why) n=n+1;assert(a==b,(why or "")..": "..tostring(a).." ~= "..tostring(b)) end
same(D.Money("12","34","56"),123456,"hand conversion")
same(D.Money("0","0","1"),1)
same(D.Money("9999999","99","99"),W.Prices.MAX_COPPER)
for _,v in ipairs({{"10000000","0","0"},{"1","100","0"},{"1","0","100"},{"-1","0","0"},{"1.5","0","0"},{"1e2","0","0"},{"nan","0","0"},{"","",""},{"0","0","0"}}) do
    same(D.Money(v[1],v[2],v[3]),nil,"invalid denomination refused")
end
for i=1,100 do
    local value=(i*98765431)%W.Prices.MAX_COPPER+1
    local gold,silver,copper=D.Coins(value)
    same(D.Money(gold,silver,copper),value,"exact integer round trip")
end
local clock,qty,available,deposit=1000,7,5,123
local link="item:10:0:0:0:0:0:0:0:0:0:0:0"
local key={itemID=10,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
local live=true;Q.Available=function() return live end
c.GetTime=function() return clock end
c.Enum.ItemCommodityStatus={Unknown=0,Item=1,Commodity=2}
c.ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {bag=bag,slot=slot} end}
c.C_Container={GetContainerNumSlots=function(b) return b==0 and 1 or 0 end,
 GetContainerItemInfo=function() return {itemID=10,stackCount=qty,isLocked=false,isBound=false,hyperlink=link} end}
local sent,quotes=0,0
c.hooksecurefunc=function() end
c.C_AuctionHouse=setmetatable({
 IsSellItemValid=function(_,displayError) same(displayError,false,"eligibility read does not display native errors");return true end,
 GetItemKeyFromItem=function() return key end,
 GetAvailablePostCount=function() return available end,
 GetItemCommodityStatus=function() return 1 end,
 SupportsCopperValues=function() return true end,
 CalculateItemDeposit=function(location,duration,count)
    quotes=quotes+1;same(location.bag,0);same(duration,2);same(count,3);return deposit
 end,
 IsThrottledMessageSystemReady=function() return true end,
 SendSearchQuery=function() sent=sent+1 end,
},{__index=function(_,name) return function() error("transaction/unsupported API "..name) end end})
W.AdvisorData.Reserved=function() return 0,false end
local row=D.Bags("")[1]
same(row.itemKey.itemID,10);same(row.identityKnown,true);same(D.Max(row),5,"native count caps the selected stack")
row.available=100;same(D.Max(row),7,"cannot combine stacks");row.available=5
same(D.Draft(row,6,100,2).valid,false)
same(D.Draft(row,3,100,0).valid,false,"duration indices are validated")
local draft=D.Draft(row,3,101,2)
same(draft.gross,303);same(draft.deposit,123);same(draft.fees,nil);same(draft.net,nil)
deposit=0;same(D.Draft(row,3,101,2).deposit,0,"a verified zero deposit is not unknown")
deposit=nil;same(D.Draft(row,3,101,2).deposit,nil)
same(D.Draft(row,3,W.Prices.MAX_COPPER,2).gross,nil,"overflow refused before multiplication")
row.copper=false;same(D.Draft(row,3,101,2).valid,false,"native precision respected");row.copper=true
deposit=123;row.copper=false
same(D.Draft(row,3,100,2).deposit,200,"native whole-silver deposit rounds up")
deposit=0;same(D.Draft(row,3,100,2).deposit,0,"whole-silver zero remains zero")
deposit=W.Prices.MAX_COPPER
same(D.Draft(row,3,100,2).deposit,nil,"rounded deposit cannot exceed the money bound")
local precisionQuotes=quotes;row.copper=nil
same(D.Draft(row,3,100,2).deposit,nil,"unknown money precision cannot supply an upfront quote")
same(quotes,precisionQuotes,"unknown precision does not request a deposit quote")
row.copper=true;deposit=nil
for _,field in ipairs({"locked","pending"}) do row[field]=true;same(D.Max(row),0);same(D.Draft(row,3,100,2).valid,false);row[field]=false end
row.reserved=1;same(D.Max(row),0);same(D.Draft(row,3,100,2).valid,false);row.reserved=0
row.bound=nil;same(D.Max(row),0);row.bound=false
local oldQuotes=quotes;live=false;same(D.Draft(row,3,100,2).deposit,nil);same(quotes,oldQuotes,"no quote outside the gated context");live=true
local saved=D.Competition(row)
saved.facts={item=10,key=m.key,comp={competing=500,complete=true,cut=false,age=0,at=now,notes={}},
 quality={level="good",reasons={},facts={distribution=true}}}
-- The held-item Advisor uses the same source as the tooltip, independently
-- from the competition table that supplies a posting price.
local advisorMarket={key="tooltip-source"}
local sourceFacts=saved.facts
local factsOf=W.Facts.Of
W.Session.PriceSource=function() return {market=advisorMarket} end
W.Facts.Of=function(item,opt)
    if opt and opt.market==advisorMarket then return sourceFacts end
    return factsOf(item,opt)
end
local suggestion,rec=D.Guidance(row,saved)
same(suggestion.state,"ok");same(suggestion.price,500,"existing policy supplies the qualified reference")
same(rec.action,"auction");same(rec.level,"supported")
saved.facts.mval={value=1000}
same(D.Guidance(row,saved).price,nil,"existing far-below-usual flag prevents an automatic default")
saved.facts.mval=nil
saved.facts.quality.level="limited";saved.facts.quality.reasons={{code="days",text="Few observed days"}}
suggestion,rec=D.Guidance(row,saved)
same(suggestion.price,nil,"tentative evidence never fills a default")
same(rec.level,"tentative");same(rec.observed.value,500)
local function Listing(id,count,total,own,account,k)
    return Q.Listing({auctionID=id,itemKey=k or key,quantity=count,buyoutAmount=total,
        minBid=total and nil or 50,containsOwnerItem=own,containsAccountItem=account})
end
local request={intent=41,epoch=Q.epoch,itemKey=key,marketStamp=saved.stamp}
Q.snapshot={kind="item",intent=41,epoch=Q.epoch,at=clock,complete=true,rows={
 Listing(1,3,299,false,false),Listing(2,2,2,true,false),Listing(3,2,4,false,true),Listing(4,1,nil,false,false)}}
local ctx=D.Competition(row,request)
local liveSuggestion,liveAdvice=D.Guidance(row,ctx)
local tooltipAdvice=W.AdvisorData.Tooltip({item=row.item,count=row.qty,sell=40,bindType=0,bound=false,classID=7,quality=1})
same(liveAdvice.action,tooltipAdvice.action,"Sell and tooltip agree despite low live competition")
same(liveAdvice.level,tooltipAdvice.level,"Sell and tooltip use identical evidence")
same(liveSuggestion.price,100,"live posting price remains independent of advice")
local originalFacts=sourceFacts
sourceFacts={recent={value=10,source="market_server"}}
local _,cheapAdvice=D.Guidance(row,ctx)
local cheapTooltip=W.AdvisorData.Tooltip({item=row.item,count=row.qty,sell=40,bindType=0,bound=false,classID=7,quality=1})
same(cheapAdvice.action,"vendor");same(cheapAdvice.action,cheapTooltip.action,"changed source is read afresh")
sourceFacts=originalFacts
same(ctx.source,"live");same(#ctx.rows,2,"own and account competition excluded")
same(ctx.rows[1].unit,100);same(ctx.rows[1].total,299,"exact total retained")
same(D.Copy(ctx,ctx.rows[1],row),100,"copy normalized unit price")
same(D.Copy(ctx,ctx.rows[2],row),nil,"bid-only is not a free buyout")
same(D.Copy(ctx,{unit=1,copy=true},row),nil,"foreign row cannot supply a price")
qty=6;same(D.Copy(ctx,ctx.rows[1],row),nil,"bag race invalidates matching");qty=7
clock=1031;same(D.Copy(ctx,ctx.rows[1],row),nil,"expired response cannot supply a price");clock=1000
Q.snapshot.complete=false;ctx=D.Competition(row,request)
same(ctx.source,"live");same(D.Copy(ctx,ctx.rows[1],row),nil,"partial read cannot match")
same(D.Guidance(row,ctx).price,nil,"partial live data cannot fall back to a saved posting suggestion")
Q.snapshot.complete=true;Q.snapshot.rows[1].ownershipKnown=false
ctx=D.Competition(row,request);same(D.Copy(ctx,ctx.rows[1],row),nil,"unknown owner flags cannot match")
Q.snapshot.rows[1].ownershipKnown=true
ctx=D.Competition(row,request);Q.epoch=Q.epoch+1
same(D.Copy(ctx,ctx.rows[1],row),nil,"old visit cannot supply a price")
request.epoch=Q.epoch;Q.snapshot.epoch=Q.epoch
ctx=D.Competition(row,request)
local raw=c.TwichUIWorkshopDB.markets[m.key];local at=raw.at;raw.at=raw.at+1
same(D.Copy(ctx,ctx.rows[1],row),nil,"changed market generation cannot match");raw.at=at
same(sent,0,"bag selection, guidance, quotes and price copies never search")
local req=D.Search(row);same(req.intent,Q.serial);same(sent,1,"only explicit Find competition sends a query")
Q.Cancel("test done");row.mode=2;same(D.Search(row),nil,"unverified commodity detail path remains gated");same(sent,1);row.mode=1
local originalLink=link
link="item:10:0:0:0:0:0:0:0:0:0:0:0:1:12345"
local bonus=D.Bags("")[1]
same(bonus.variant,true,"variant flags are boolean for Facts.Of")
same(bonus.keyComparable,false,"bonus IDs cannot be collapsed into a four-part native key")
same(D.Competition(bonus).facts.min,nil,"bonus variant never receives base-item history")
same(#D.Competition(bonus).rows,0);same(D.Search(bonus),nil);same(sent,1)
link=originalLink
-- Construct the actual form; inspect coin art, Max, edits and cleanup.
c.C_AuctionHouse.CalculateItemDeposit=function() return 0 end
A.Show();A.Go("sell");local p=A.Page("sell")
same(p.failed,nil);Press.Must(p.list.rows[1]);same(p.quantity:GetText(),"5")
same(sent,1,"selecting the item never sends a native search")
same(p.money.gold.coin.atlas,"coin-gold");same(p.money.silver.coin.atlas,"coin-silver");same(p.money.copper.coin.atlas,"coin-copper")
Press.Must(p.lowest)
local copied,origin,matched=p.money:GetCopper(),p.priceOrigin,p.matched
assert(copied and matched,"fixture has a valid historical tier")
p.money.copper:GetScript("OnTextChanged")(p.money.copper)
same(p.priceOrigin,origin,"deferred programmatic callback retains price provenance")
same(p.matched,matched,"deferred programmatic callback retains matched row")
p.money.gold:SetText("2");p.money.silver:SetText("3");p.money.copper:SetText("4")
p.money.copper:GetScript("OnTextChanged")(p.money.copper) -- recording frames do not dispatch native text events
same(p.money:GetCopper(),20304);same(p.draft.gross,101520)
same(p.priceOrigin,"Your unit price");same(p.matched,nil,"manual edit clears the matched row")
p.quantity:SetText("1");Press.Must(p.max);same(p.quantity:GetText(),"5")
p.money.silver:SetText("100");same(p.money:GetCopper(),nil)
same(p.post:IsEnabled(),false)
local prepare=W.AuctionActions.PreparePost
W.AuctionActions.PreparePost=function() error("standalone cannot prepare or send a posting") end
p.post:GetScript("OnClick")()
W.AuctionActions.PreparePost=prepare
qty=6;A.Render();same(p.selected,nil);same(p.money:GetCopper(),nil,"bag race clears draft price")
A.Hide();same(p.competition,nil);same(p.request,nil);same(A.Snapshot().subscriptions,0)
p.money.copper:GetScript("OnTextChanged")(p.money.copper)
same(p.competition,nil,"deferred native text events cannot resurrect hidden competition")
same(p.draft,nil);same(p.list.rows[1].data,nil)
print("PASSED: Sell preparation "..n.." checks")
