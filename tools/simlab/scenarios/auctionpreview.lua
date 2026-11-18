-- Real addon shell and handler-level inputs over a synthetic native-frame sentinel.
-- No real auctioneer, server, pointer, combat, font or taint evidence.
if P.categories then
    -- Synthetic hierarchy tests presentation; runtime data comes from Blizzard.
    AuctionCategories={{name="Fixture trade group",filters={{classID=7}},
        subCategories={{name="Fixture subclass",filters={{classID=7,subClassID=0}}}}}}
end
if P.summary then TwichUIMarketData=SIMLAB_SUMMARY;TwichUIMarketParts=SIMLAB_SUMMARY_PARTS end
if P.bridge then TwichUIMarketData=SIMLAB_BRIDGE end -- data is present while Workshop is still unloaded
local R = TwichUI
A_Admin.SetManualClock(GetTime())
Lab.Solo()
local native = CreateFrame("Frame", nil, UIParent)
native:SetSize(800, 500); native:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 26, -90); native:SetScale(0.83); native:Show()
AuctionHouseFrame = native
local scale, hidden, shown, calls = native:GetScale(), 0, 0, 0
local nativeHooks=0
local realHook=native.HookScript
native.HookScript=function(self,...)
    nativeHooks=nativeHooks+1
    return realHook(self,...)
end
native:SetScript("OnHide", function() hidden = hidden + 1 end)
native:SetScript("OnShow", function() shown = shown + 1 end)
C_AuctionHouse = setmetatable({}, { __index = function(_, key)
    return function() calls = calls + 1; error("preview issued auction operation " .. key) end
end })
local A, f
local itemNames = { [7067]="Elemental Earth", [4306]="Silk Cloth", [4338]="Mageweave Cloth", [2770]="Copper Ore", [2771]="Tin Ore", [2320]="Coarse Thread", [2321]="Fine Thread", [2604]="Red Dye" }
local itemIcons = { [7067]="INV_Elemental_Mote_Earth01", [4306]="INV_Fabric_Silk_01", [4338]="INV_Fabric_Mageweave_01", [2770]="INV_Ore_Copper_01", [2771]="INV_Ore_Tin_01", [2320]="INV_Fabric_Linen_03", [2321]="INV_Fabric_Wool_02", [2604]="INV_Potion_11" }
C_Item.GetItemInfo = function(id)
    return itemNames[id] or ("Stored Item "..id), nil, 1, 1, 1, "Trade Goods", "Materials", 20, "", "Interface\\Icons\\"..(itemIcons[id] or "INV_Misc_QuestionMark"), 40, 7, 0, 0
end
C_Item.GetItemCount = function() return 0 end
C_Item.RequestLoadItemDataByID = function() end
GetRealmName = function() return "Fixture Realm" end
local realFaction = UnitFactionGroup
UnitFactionGroup = function(unit)
    if unit == "npc" then return "Alliance" end
    return realFaction and realFaction(unit)
end
local function Seed(W)
    local now = time()
    local batch=W.Prices.NewBatch()
    for id in pairs(itemNames) do batch:Add(id, id==7067 and 3 or 20, id==7067 and 299 or (id%200+30)*20, true) end
    local items,n=batch:Items()
    local m={f=2,key="Fixture Realm|Alliance",realm="Fixture Realm",side="Alliance",at=now-7200,scope="full",complete=true,items=items,n=n,read=n,used=n,hist={},hn=n}
    for id in pairs(itemNames) do
        for i=7,0,-1 do m.hist[id]=W.History.Add(m.hist[id],math.floor(now/86400)-i,(id%200+30)+i*3) end
    end
    TwichUIWorkshopDB={v=2,markets={[m.key]=m}}
end
Lab.Step("explicit preview", function()
    Lab.Check("init", "Workshop initially unloaded", false, R.WorkshopLauncher.Loaded())
    Lab.Check("init", "preview requires explicit experimental opt-in", true, R.WorkshopLauncher.SetEnabled(true))
    Lab.Check("init", "proof disabled", false, R.AuctionHost.Snapshot().leased)
    SlashCmdList.TWICHUI("ahpreview")
    A = R.Workshop.AuctionUI; f = A.Frame()
    Lab.Check("state","preview does not attach native scan button",false,R.Workshop.AuctionButton.Attached())
    Lab.Check("state","preview adds no native hooks",0,nativeHooks)
    Seed(R.Workshop); A.Render()
    Lab.Check("construct", "preview shown", true, f:IsShown())
    Lab.Check("construct", "Workshop window unbuilt", false, R.Workshop.Snapshot().built)
    Lab.Check("state", "Browse default", "browse", A.Mode())
end)
Lab.Step("navigation and lifecycle", function()
    for _, key in ipairs({"browse", "shopping", "sell", "owned", "market"}) do
        A.nav[key]:Click()
        Lab.Check("interact", "navigation " .. key, key, A.Mode())
        Lab.Check("state", "page shown " .. key, true, A.Page(key):IsVisible())
    end
    local pages = A.Snapshot().pages
    for i = 1, 12 do
        f.close:Click(); A.Show(); A.nav.shopping:Click(); A.nav.browse:Click()
    end
    Lab.Check("state", "bounded pages", pages, A.Snapshot().pages)
    for key,page in pairs(A.views) do Lab.Check("state", "exclusive reopened page " .. key, key=="browse", page:IsShown()) end
    f.blizzard:Click()
    Lab.Check("state", "Blizzard switch closes preview", false, f:IsShown())
    Lab.Check("state", "no hidden listeners", 0, A.Snapshot().events)
    A.Show()
end)
Lab.Step("Browse history and filters", function()
    Lab.Settle(0.8)
    local p=A.Page("browse")
    Lab.Check("state","stored catalog populated",8,#p.list.data)
    Lab.Check("state","all data marked historical",true,p.list.data[1] and p.list.data[1].source=="stored" and p.list.data[1].actionable==false)
    A.Browse.Search("Elemental Earth");Lab.Settle(0.4)
    Lab.Check("interact","search history narrows",1,#p.list.data)
    Lab.Check("construct","programmatic query hides placeholder",false,p.search.hint:IsShown())
    Lab.Check("state","observed quantity",3,p.list.data[1] and p.list.data[1].qty)
    Lab.Check("state","no live auction ID",nil,p.list.data[1] and p.list.data[1].auctionID)
    Lab.Check("state","unit normalization",100,p.list.data[1] and p.list.data[1].unit)
    Lab.Check("state","aggregate estimated value",300,p.list.data[1] and p.list.data[1].estimate)
    Lab.Check("state","Buy unavailable",false,p.detail.buy:IsEnabled())
    p.detail.track:Click()
    Lab.Check("interact","shared tracking",true,R.Workshop.AdvisorData.Tracked()[7067])
    p.reset:Click();Lab.Settle(0.4)
    Lab.Check("interact","reset restores catalog",8,#p.list.data)
    A.Browse.Select(7067)
end)
local bags={}
local function Pick(button,label)
    button:Click()
    local menu=_G.Menu.GetManager():GetOpenMenu()
    local found
    if menu then menu:EnumerateElementDescriptions(function(_,d) if MenuUtil.GetElementText(d)==label then found=d end end) end
    if not found then error("missing filter "..label) end
    found:Pick(MenuInputContext.MouseButton,"LeftButton")
    Lab.Settle(0.3)
end
local function ShoppingSeed(W)
    itemNames[10050]="Bolt of Silk Cloth";itemIcons[10050]="INV_Fabric_Silk_03"
    local robe={id=1001,name="Silk Robe",prof=197,profName="Tailoring",outItem=10090,outMin=1,outMax=1,filled=true,
        mats={{item=10050,qty=12},{item=7067,qty=8},{item=2321,qty=20},{item=4338,qty=4},{item=2604,qty=6}}}
    local bolt={id=1002,name="Bolt of Silk Cloth",prof=197,profName="Tailoring",outItem=10050,outMin=1,outMax=1,filled=true,mats={{item=4306,qty=4}}}
    W.Known.Store({prof=197,profName="Tailoring",complete=true,recipes={robe,bolt}})
    W.Queue.Add(robe,1)
    W.Session.Reset()
    local market=TwichUIWorkshopDB.markets["Fixture Realm|Alliance"]
    local b=W.Prices.NewBatch();b:Add(10050,99,1000*99,true);b:Add(4306,99,136*99,true);b:Add(7067,99,100*99,true)
    local x=b:Items()
    for id,entry in pairs(x) do market.items[id]=entry end
    market.items[2604]=nil
    W.Vendor.Observe({{id=2321,price=10,stack=1,avail=-1}},{[2321]=true},1234)
    W.Storage.StoreBank({ids={6},tabs={[6]={[4338]=4}},incomplete=0},time()-7200)
    bags={[10050]=2,[4306]=3}
    C_Item.GetItemCount=function(id) return bags[id] or 0 end
end
Lab.Step("Shopping shared plan",function()
    ShoppingSeed(R.Workshop)
    A.Go("shopping");Lab.Settle(0.8)
    local W,p=R.Workshop,A.Page("shopping")
    local function Find(item)
        for _,v in ipairs(p.rows) do if v.row.item==item then return v end end
    end
    local kinds={};for _,v in ipairs(p.rows) do kinds[v.source]=true end
    for _,kind in ipairs({"make","auction","vendor","collect","none"}) do Lab.Check("state","Shopping source "..kind,true,kinds[kind]) end
    Lab.Check("state","Shopping uses planner", "ready",p.state)
    Lab.Check("state","Shopping stock in bags",0,Find(4338) and Find(4338).have)
    Lab.Check("state","Shopping collect quantity",4,Find(4338) and Find(4338).missing)
    Lab.Check("state","Shopping unknown price",nil,Find(2604) and Find(2604).row.cash)
    Lab.Check("state","Shopping purchasing unavailable",false,p.detail.buy:IsEnabled())
    Pick(p.sourceDrop,"Vendor")
    Lab.Check("interact","Shopping source filter",1,#p.rows)
    Lab.Check("state","Shopping filtered source","vendor",p.rows[1] and p.rows[1].source)
    Pick(p.sourceDrop,"All Sources");Pick(p.groupDrop,"By crafting purpose")
    Lab.Check("interact","Shopping purpose grouping","purpose",p.group)
    Pick(p.groupDrop,"Group by item")
    for _,r in ipairs(p.list.rows) do if r.data and r.data.row.item==7067 then r:Click();break end end
    p.detail.browse:Click();Lab.Settle(0.4)
    Lab.Check("interact","Shopping opens Browse history","browse",A.Mode())
    Lab.Check("state","Shopping does not delete crafts",1,W.Queue.Count())
    A.Go("shopping");Lab.Settle(0.3)
    W.Session.SetCrafts(1001,2);Lab.Settle(0.5)
    Lab.Check("state","Shopping queue updates",16,Find(7067) and Find(7067).missing)
    bags[7067]=16;p:GetScript("OnEvent")(p,"BAG_UPDATE_DELAYED");Lab.Settle(0.5)
    Lab.Check("state","Shopping real stock fulfillment",nil,Find(7067))
    bags[7067]=0;W.Session.SetCrafts(1001,1);p.refresh:Click();Lab.Settle(0.5)
    Lab.Check("state","Shopping restores requirement",8,Find(7067) and Find(7067).missing)
    Lab.Check("state","Shopping one planner subscription",1,W.Strategy.ListenerCount())
    A.Go("browse");Lab.Settle(0.4)
    Lab.Check("state","Shopping unsubscribes; Browse owns one source observer",1,W.Strategy.ListenerCount())
    Lab.Check("state","Shopping releases references",nil,p.plan)
    A.Browse.Search("");Lab.Settle(0.4);A.Browse.Select(7067)
end)
Lab.Step("large Browse viewport and cleanup",function()
    local W,p=R.Workshop,A.Page("browse")
    local key="Fixture Realm|Alliance"
    local original=TwichUIWorkshopDB.markets[key]
    local entry=original.items[7067]
    local large={f=2,key=key,realm="Fixture Realm",side="Alliance",at=time()-60,scope="full",complete=true,items={},n=3000,read=3000,used=3000}
    for id=20000,22999 do large.items[id]=entry end
    TwichUIWorkshopDB.markets[key]=large;p.forceItem=nil
    A.Browse.Search("")
    local function Finish()
        for _=1,100 do if not p.job then return end;Lab.Settle(0.05) end
        error("large Browse job did not complete within the fixture budget")
    end
    Finish()
    Lab.Check("state","large Browse catalog",3000,#p.rows)
    Lab.Check("construct","large Browse pool bounded",true,#p.list.rows<30)
    p.list.scroll:SetVerticalScroll(56*200+17);p.list:Layout()
    local top=p.list.data[201].item
    A.Browse.Select(p.list.data[900].item)
    local selected=p.selected
    p:GetScript("OnEvent")(p,"GET_ITEM_INFO_RECEIVED",selected,true)
    Lab.Settle(0.2);Finish()
    Lab.Check("state","large Browse selected retained",selected,p.selected)
    local pixel=p.list.scroll:GetVerticalScroll()
    Lab.Check("state","large Browse top identity retained",top,p.list.data[math.floor(pixel/56)+1].item)
    Lab.Check("state","large Browse within-row offset retained",17,pixel%56)
    A.Go("shopping")
    Lab.Check("state","large Browse hidden rows released",0,#p.list.data)
    Lab.Check("state","large Browse job cancelled on hide",nil,p.job)
    TwichUIWorkshopDB.markets[key]=original
    A.Go("browse");p.forceItem=nil;A.Browse.Search("");Finish();A.Browse.Select(7067)
    Lab.Check("state","large Browse restored fixture",8,#p.rows)
end)
local function MarketSeed(W,sparse,ageOffset)
    local now=time()-(ageOffset or 0)*86400;local today=math.floor(now/86400)
    local key="Fixture Realm|Alliance"
    TwichUIWorkshopDB={v=2,markets={}}
    for age=110,0,-1 do
        if (not sparse and (age%5~=0 or age==0)) or sparse and (age==0 or age==12) then
            local batch=W.Prices.NewBatch()
            for id in pairs(itemNames) do
                local unit=20000+age*55+(id%11)*100
                batch:Add(id,20,20*unit,true);batch:Add(id,30,30*(unit+3000),true)
            end
            local items,n,_,_,dist=batch:Items()
            assert(W.Prices.Commit(key,{realm="Fixture Realm",side="Alliance",at=(today-age)*86400+60,
                complete=true,items=items,n=n,read=n,used=n,alg=W.Dist.ALG,dist=dist}))
        end
    end
    W.Facts.CacheClear();W.AuctionMarketData.Clear()
    return key
end
-- Explicit synthetic read evidence, never a native request or transaction.
local function SellFixture(W,empty)
    local function Item(slot) return slot==1 and 2771 or 4306 end
    local function Count(slot) return slot==1 and 3 or 20 end
    C_Container={GetContainerNumSlots=function(bag) return bag==0 and not empty and 2 or 0 end,
        GetContainerItemInfo=function(_,slot) return {itemID=Item(slot),stackCount=Count(slot),isBound=false,isLocked=false,
            hyperlink="item:"..Item(slot)..":0:0:0:0:0:0:0:0:0:0:0"} end}
    ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {bag=bag,slot=slot} end}
    C_AuctionHouse=setmetatable({
        IsSellItemValid=function() return true end,
        GetItemKeyFromItem=function(location) return {itemID=Item(location.slot),itemLevel=0,itemSuffix=0,battlePetSpeciesID=0} end,
        GetAvailablePostCount=function(location) return Count(location.slot) end,
        GetItemCommodityStatus=function() return Enum.ItemCommodityStatus.Item end,
        SupportsCopperValues=function() return true end,
        CalculateItemDeposit=function() return 123 end,
    },getmetatable(C_AuctionHouse))
    W.AuctionReads.Available=function() return true end
    local reserved=W.AdvisorData.Reserved
    W.AdvisorData.Reserved=function(item) if item==2771 then return 0,false end;return reserved(item) end
end
local function SellLive(W,p)
    local Q=W.AuctionReads
    local market=W.Market.Source().market
    local key=p.chosen.itemKey
    Q.serial=505
    p.request={intent=505,epoch=Q.epoch,itemKey=key,marketStamp=market and market.key..":"..W.Valuation.Generation(market) or "none"}
    Q.snapshot={kind="item",intent=505,epoch=Q.epoch,at=GetTime(),complete=true,rows={
        Q.Listing({auctionID=201,itemKey=key,quantity=3,buyoutAmount=299,containsOwnerItem=false,containsAccountItem=false},"item"),
        Q.Listing({auctionID=202,itemKey=key,quantity=20,buyoutAmount=405000,containsOwnerItem=false,containsAccountItem=false},"item"),
        Q.Listing({auctionID=203,itemKey=key,quantity=1,buyoutAmount=1,containsOwnerItem=true,containsAccountItem=false},"item")}}
    Q.state="results";A.Render()
end
Lab.Step("Market research and cross-page safety",function()
    local W=R.Workshop
    local saved=TwichUIWorkshopDB
    local key=MarketSeed(W)
    A.OpenMarket(7067,{market=key});Lab.Settle(0.5)
    local p=A.Page("market")
    Lab.Check("construct","Market functional page",nil,p.failed)
    Lab.Check("state","Market identity retained",7067,p.selected)
    Lab.Check("state","Market selected faction",key,p.projection.market)
    Lab.Check("state","Market no actionable row",false,p.rows[1].actionable)
    Lab.Check("state","Market observed supply",50,p.projection.facts.supply.items)
    Lab.Check("state","Market price history",true,#p.projection.series.points>2)
    local history=p.projection.history
    A.Market.Range(120)
    Lab.Check("interact","Market range reuses projection",true,history==p.projection.history)
    Lab.Check("state","Market old aggregates separate",true,#p.projection.series.groups>0)
    A.Market.Range(2)
    Lab.Check("state","Market recent timestamp record","obs",p.projection.series.points[1].kind)
    A.Market.Range(14)
    p.browse:Click();Lab.Settle(0.5)
    Lab.Check("interact","Market opens saved Browse","browse",A.Mode())
    Lab.Check("state","Market Browse retains faction",key,A.Page("browse").market.key)
    A.Page("browse").detail.market:Click();Lab.Settle(0.5)
    Lab.Check("interact","Browse opens Market","market",A.Mode())
    Lab.Check("state","Market shared track state",true,W.AdvisorData.Tracked()[7067])
    p.track:Click();Lab.Check("interact","Market untracks shared list",nil,W.AdvisorData.Tracked()[7067])
    p.track:Click();Lab.Check("interact","Market tracks shared list",true,W.AdvisorData.Tracked()[7067])
    A.OpenMarket(7067,{market=key,itemKey={itemID=7067,itemSuffix=4}});Lab.Settle(0.4)
    Lab.Check("state","Market variant unpriced",nil,p.projection.facts.min)
    Lab.Check("state","Market variant not collapsed",false,p.browse:IsEnabled())
    A.OpenMarket(7067,{market="missing|Horde"});Lab.Settle(0.4)
    Lab.Check("state","Market absent faction honest",true,p.projection.facts.nomarket)
    Lab.Check("state","Market zero native operations",0,calls)
    A.Go("shopping")
    Lab.Check("state","Shopping owns one bounded shared chart projection",1,W.AuctionMarketData.Stats().cache)
    Lab.Check("state","Shopping chart context replaces Market",true,A.Page("shopping").detail.chart.context:find(":shopping:",1,true)~=nil)
    Lab.Check("state","Market hidden index released",nil,p.index)
    Lab.Check("state","Market hidden events released",false,p.listening)
    TwichUIWorkshopDB=saved;W.Facts.CacheClear()
    A.Go("browse");A.Page("browse").researchMarketKey=nil
    A.Browse.Search("");Lab.Settle(0.5);A.Browse.Select(7067)
end)

Lab.Step("native untouched and fit", function()
    Lab.Check("state", "native still shown", true, native:IsVisible())
    Lab.Check("state", "native scale retained", scale, native:GetScale())
    Lab.Check("state", "native anchor retained", 26, select(4, native:GetPoint(1)))
    Lab.Check("state", "native never hidden", 0, hidden)
    Lab.Check("state", "native never reshown", 0, shown)
    Lab.Check("state", "zero auction operations", 0, calls)
    Lab.Check("state", "proof still disabled", false, R.AuctionHost.Snapshot().leased)
    if P.scaled then UIParent:SetScale(0.8); f:GetScript("OnEvent")(f,"UI_SCALE_CHANGED") end
    R.FitToScreen(f)
    Lab.Check("construct", "close inside root", true, f.close:GetRight() <= f:GetRight())
    Lab.Check("construct", "Blizzard switch above pages", true, f.blizzard:GetBottom() > f.content:GetTop())
    Lab.Check("construct", "navigation at left", true, f.nav:GetRight() < f.content:GetLeft())
    Lab.Check("construct", "window within viewport", true, f:GetWidth()*f:GetEffectiveScale() <= UIParent:GetWidth()*UIParent:GetEffectiveScale())
end)
Lab.Step("control geometry and resize",function()
    local RC=R.TestLab.Reach
    local p=A.Page("browse")
    local collected=RC.Collect({limit=1000000})
    for label,control in pairs({close=f.close,blizzard=f.blizzard,browse=A.nav.browse,shopping=A.nav.shopping,search=p.submit,category=p.categoryDrop}) do
        local hit=RC.Analyze(control,{kind="click",collected=collected,evidence="simulator-geometry",limit=1000000})
        Lab.Check("construct","reachable preview "..label,"reachable",hit.verdict)
    end
    local over=CreateFrame("Frame",nil,f)
    over:SetAllPoints(f.close);over:SetFrameLevel(f.close:GetFrameLevel()+20);over:EnableMouse(true);over:Show()
    local blocked=RC.Analyze(f.close,{kind="click",evidence="simulator-geometry",limit=1000000})
    Lab.Check("construct","geometry detects blocking overlay","blocked",blocked.verdict)
    over:Hide()
    Lab.Check("construct","geometry recovers after overlay","reachable",RC.Analyze(f.close,{kind="click",evidence="simulator-geometry",limit=1000000}).verdict)
    A.Resize(1720,1000)
    Lab.Check("state","resize width",UIParent:GetWidth()<1100 and 1586 or 1720,math.floor(f:GetWidth()+0.5))
    Lab.Check("state","resize height",1000,math.floor(f:GetHeight()+0.5))
    Lab.Check("construct","resize remains inside viewport",true,f:GetWidth()*f:GetEffectiveScale()<=UIParent:GetWidth()*UIParent:GetEffectiveScale())
    A.Resize(1420,880);Lab.Settle(0.2)
end)
Lab.Step("Sell price preparation without transactions",function()
    local W=R.Workshop;local Q=W.AuctionReads
    local old={container=C_Container,location=ItemLocation,api=C_AuctionHouse,available=Q.Available,
        reserved=W.AdvisorData.Reserved,snapshot=Q.snapshot,serial=Q.serial,epoch=Q.epoch,state=Q.state}
    local before=calls
    SellFixture(W)
    A.Go("sell");Lab.Settle(0.2)
    local p=A.Page("sell")
    Lab.Check("construct","Sell preparation built",nil,p.failed)
    p.list.rows[1]:Click()
    Lab.Check("state","Sell default selected-stack max","3",p.quantity:GetText())
    p.money:SetCopper(12345)
    Lab.Check("interact","Sell gold input","1",p.money.gold:GetText())
    Lab.Check("interact","Sell silver input","23",p.money.silver:GetText())
    Lab.Check("interact","Sell copper input","45",p.money.copper:GetText())
    Lab.Check("state","Sell integer gross",37035,p.draft.gross)
    Lab.Check("state","Sell quoted upfront deposit",123,p.draft.deposit)
    Lab.Check("state","Sell commission remains unknown",nil,p.draft.fees)
    Lab.Check("state","Sell net remains unknown",nil,p.draft.net)
    SellLive(W,p)
    Lab.Check("state","Sell excludes owned competition",2,#p.competition.rows)
    Lab.Check("state","Sell exact competing total",299,p.competition.rows[1].total)
    Lab.Check("state","Sell per-item competing price",299,p.competition.rows[1].unit)
    p.competitionList.rows[1]:Click()
    Lab.Check("interact","Sell click copies only unit price",299,p.money:GetCopper())
    Lab.Settle(0.2)
    Lab.Check("state","Sell deferred match provenance",true,p.priceOrigin=="Matched current listing" and p.matched==201)
    Lab.Check("state","Sell broker total unmodified",299,Q.snapshot.rows[1].total)
    p.quantity:SetText("1");p.max:Click()
    Lab.Check("interact","Sell Max shortcut","3",p.quantity:GetText())
    Q.snapshot.complete=false;A.Render();p.money:SetCopper(777);p.competitionList.rows[1]:Click()
    Lab.Check("state","Sell partial response cannot copy",777,p.money:GetCopper())
    Lab.Check("state","Sell post stays disabled",false,p.post:IsEnabled())
    local reviewed,prepare=0,W.AuctionActions.PreparePost
    W.AuctionActions.PreparePost=function() reviewed=reviewed+1;return nil,"Unexpected standalone posting review" end
    p.post:GetScript("OnClick")(p.post) -- bypass disabled UI to exercise the central page guard
    W.AuctionActions.PreparePost=prepare
    Lab.Check("state","Sell standalone handler refuses posting",0,reviewed)
    Lab.Check("state","Sell preparation sends no native operation",before,calls)
    A.Go("browse");Lab.Settle(0.3)
    Lab.Check("state","Sell hidden competition released",nil,p.competition)
    C_Container,ItemLocation,C_AuctionHouse=old.container,old.location,old.api
    Q.Available,W.AdvisorData.Reserved=old.available,old.reserved
    Q.snapshot,Q.serial,Q.epoch,Q.state=old.snapshot,old.serial,old.epoch,old.state
    A.Note("Transactions unavailable")
end)
Lab.RunUntil(math.max(5.5,Lab.simSeconds))
if P.resized then A.Resize(1720,1000);Lab.Settle(0.2) end
if P.shopping then A.Go("shopping");Lab.Settle(0.5) end
if P.purpose then Pick(A.Page("shopping").groupDrop,"By crafting purpose") end
if P.empty then A.Browse.Search("no matching observations");Lab.Settle(0.4) end
if P.filtered then A.Browse.Search("Cloth");Lab.Settle(0.4) end

if P.categories then
    local p=A.Page("browse")
    p.categoryList.rows[2]:Click();Lab.Settle(0.3)
    p.categoryList.rows[3]:Click();Lab.Settle(0.3)
end
if P.sell then
    MarketSeed(R.Workshop)
    SellFixture(R.Workshop,P.bagEmpty)
    A.Go("sell");Lab.Settle(0.3)
    local p=A.Page("sell")
    if p.list.rows[1] and p.list.rows[1].data then
        p.list.rows[1]:Click()
        if not P.savedCompetition then SellLive(R.Workshop,p);p.competitionList.rows[1]:Click()
        else p.money:SetCopper(20200) end
    end
end
if P.loading then
    local W=R.Workshop
    MarketSeed(W)
    local m=TwichUIWorkshopDB.markets["Fixture Realm|Alliance"]
    for id=20000,25999 do m.items[id]=m.items[7067] end
    m.n=0;for _ in pairs(m.items) do m.n=m.n+1 end
    -- The simulator drains zero-delay timers in one manual-clock tick. Keep
    -- real discovery slices on separate ticks for this capture only.
    local after=C_Timer.After
    C_Timer.After=function(delay,fn) return after(delay==0 and 0.05 or delay,fn) end
    A.Hide();W.AuctionBrowseData.BATCH=1;A.Show();A.Browse.Search("")
    Lab.Settle(0.1)
    local p=A.Page("browse")
    Lab.Check("state","Loading capture has an active real discovery",true,p.job~=nil and #p.rows==0)
end
if P.livePrepare then
    local p=A.Page("browse")
    p.search:SetText("Silk Cloth");p.live:Click()
end
if P.owned then
    -- Inject normalized synthetic evidence for presentation only; never native I/O.
    local Q=R.Workshop.AuctionReads
    Q.Available=function() return true end
    Q.state=P.ownedEmpty and "empty" or "results"
    Q.snapshot={epoch=Q.epoch,at=GetTime(),complete=true,kind="owned",rows=P.ownedEmpty and {} or {
        {auctionID=21,item=7067,itemKey={itemID=7067,itemLevel=0,itemSuffix=0},qty=3,total=299,unit=100,status=0,seconds=1800},
        {auctionID=22,item=4306,itemKey={itemID=4306,itemLevel=0,itemSuffix=0},qty=20,total=12000,unit=600,status=0,band=2}
    }}
    A.Go("owned");Lab.Settle(0.3)
    local p=A.Page("owned")
    if p.list.rows[1] and p.list.rows[1].data then p.list.rows[1]:Click() end
end
if P.market then
    local W=R.Workshop
    MarketSeed(W,P.marketSparse,P.marketStale and 20 or 0)
    if P.marketEmpty then TwichUIWorkshopDB={v=2,markets={}} end
    if P.marketLarge then
        local m=TwichUIWorkshopDB.markets["Fixture Realm|Alliance"]
        for id=20000,22999 do m.items[id]=m.items[7067] end
        m.n=3008
    end
    if P.marketMetadata then
        itemNames[7067]="A Very Long Elemental Earth Name With Unavailable Late Metadata"
        local original=C_Item.GetItemInfo
        C_Item.GetItemInfo=function(id) if id==4306 then return nil end;return original(id) end
    end
    A.Go("market")
    A.Market.Filter("marketKey","Fixture Realm|Alliance")
    if P.marketError then
        W.AuctionMarketData.Catalog=function() return {Step=function() error("synthetic unavailable catalog") end} end
    end
    A.Market.Search("");Lab.Settle(0.5)
    local p=A.Page("market")
    for _=1,100 do if not p.job then break end;Lab.Settle(0.05) end
    A.Market.Select(7067)
    if P.marketRecent then A.Market.Range(2) elseif P.marketLong then A.Market.Range(120) else A.Market.Range(14) end
    if P.chartCopper then
        local original=p.projection.series
        local s={from=original.from,to=original.to,points={},groups={},gaps={},metric='min'}
        for i=1,7 do s.points[i]={day=s.to-7+i,price=90000000000+i*1000000000,provenance='synthetic local-format stress'} end
        p.chart:Set(s,W.UI.Money);p.chart:Inspect(s.points[4].day)
        p.coverage:SetText('Synthetic large-copper presentation stress · saved valuations unchanged')
    end
    if P.chartSingle then
        local s=p.projection.series
        local one={points={s.points[#s.points]},groups={},gaps={},from=s.from,to=s.to}
        p.chart:Set(one,W.UI.Money)
        p.coverage:SetText('One exact daily observation · synthetic presentation fixture')
    end
    if P.chartInterval then
        local s=p.projection.series;p.chart:Select(s.from+3,s.to-2)
        Lab.Check('interact','Chart interval selected',true,p.chart.window~=nil)
    end
    if P.chartDrag then
        local chart=p.chart;local s=p.projection.series
        local px=(chart.plot:GetLeft()+chart.pw*.28)*chart.plot:GetEffectiveScale()
        local py=(chart.plot:GetBottom()+chart.ph*.85)*chart.plot:GetEffectiveScale()
        GetCursorPosition=function()return px,py end
        IsMouseButtonDown=function()return true end
        local RC=R.TestLab.Reach
        Lab.Check('construct','drag plane is reachable','reachable',RC.Analyze(chart.hit,{kind='click',script='OnMouseDown',point={px,py},evidence='simulator-geometry',limit=1000000}).verdict)
        chart.hit:GetScript('OnEnter')(chart.hit)
        chart.hit:GetScript('OnMouseDown')(chart.hit,'LeftButton')
        px=(chart.plot:GetLeft()+chart.pw*.72)*chart.plot:GetEffectiveScale()
        chart.hit:GetScript('OnUpdate')(chart.hit)
        Lab.Check('interact','drag selection visibly active',true,chart.selection:IsShown() and chart.drag~=nil)
        Lab.Check('state','drag temporarily owns release event',true,chart.hit:IsEventRegistered('GLOBAL_MOUSE_UP'))
    end
    if P.chartHover then
        local chart=p.chart;local s=p.projection.series
        local point=s.points[#s.points-2]
        local px=(chart.plot:GetLeft()+(point.day-s.from)/(s.to-s.from)*chart.pw)*chart.plot:GetEffectiveScale()
        local py=(chart.plot:GetBottom()+chart.ph*.9)*chart.plot:GetEffectiveScale()
        GetCursorPosition=function()return px,py end
        chart.hit:GetScript('OnEnter')(chart.hit)
        Lab.Check('interact','Chart inspection visible',true,chart.tip:IsShown())
        local RC=R.TestLab.Reach;local rect=RC.HitRect(chart.hit).hit;local reachable=0
        for _,x in ipairs({.01,.5,.99}) do for _,y in ipairs({.01,.5,.99}) do
            local hit=RC.Analyze(chart.hit,{kind='hover',point={rect[1]+(rect[3]-rect[1])*x,rect[2]+(rect[4]-rect[2])*y},evidence='simulator-geometry',limit=1000000})
            if hit.verdict=='reachable' then reachable=reachable+1 end
        end end
        Lab.Check('construct','whole plot hover geometry',9,reachable)
        local scale=chart.tip:GetEffectiveScale()
        local left,right=chart.tip:GetLeft()*scale,chart.tip:GetRight()*scale
        local bottom,top=chart.tip:GetBottom()*scale,chart.tip:GetTop()*scale
        Lab.Check('construct','inspection docks outside the plot',true,right<=rect[1] or left>=rect[3] or top<=rect[2] or bottom>=rect[4])
        Lab.Check('construct','inspection panel cannot intercept input',false,chart.tip:IsMouseEnabled())
        local update=chart.hit:GetScript('OnUpdate')
        chart:Set(R.Workshop.BridgeCodec.Copy(s),chart.format,chart.context)
        Lab.Check('state','equivalent refresh preserves active inspection',true,chart.hit:GetScript('OnUpdate')==update and chart.tip:IsShown())
    end
    if P.marketTracked then A.Market.Filter("scope","tracked");Lab.Settle(0.5) end
    if P.marketMetadata then
        Lab.Check("construct","Market long title fits its heading",true,p.name:GetText()==itemNames[7067] and not p.name:IsTruncated() and p.name:GetStringHeight()<=p.name:GetHeight())
    end
end
if P.bridge and not P.scopedState then
    local W=R.Workshop;local B=W.Bridge
    local saved=TwichUIWorkshopDB
    local function fingerprint(v)
        if type(v)~='table' then return tostring(v) end
        local keys={};for k in pairs(v) do keys[#keys+1]=k end
        table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
        local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..fingerprint(v[k]) end
        return '{'..table.concat(out,',')..'}'
    end
    local before=fingerprint(saved)
    Lab.Check('init','bridge remains idle through ordinary page navigation',false,B.Status().ready)
    B.Begin(SIMLAB_BRIDGE)
    for i=1,3000 do local ok,why=B.Step(3);if why~='loading' then break end end
    Lab.Check('state','complete external generation validated',true,B.Status().ready)
    A.Go('market');A.Market.Filter('marketKey','server');A.Market.Filter('scope','all');A.Market.Filter('category','all');A.Market.Filter('quality',-1);A.Market.Search('');Lab.Settle(0.5)
    local p=A.Page('market');for i=1,100 do if not p.job then break end;Lab.Settle(0.05) end
    Lab.Check('interact','server item selectable',true,A.Market.Select(2589))
    Lab.Check('state','exact variant required',nil,p.projection.record)
    local key=SIMLAB_BRIDGE.records[2]:match('"variant_key":"([a-f0-9]+)"')
    Lab.Check('interact','exact server variant selectable',true,A.Market.Variant(key));A.Market.Range(2)
    local points=p.projection.series and p.projection.series.points or {}
    Lab.Check('state','two actual server dates',2,#points)
    Lab.Check('state','first daily price',100,points[1] and points[1].price)
    Lab.Check('state','latest daily price',120,points[2] and points[2].price)
    Lab.Check('state','source timestamp preserved','2026-11-14T12:00:00.123456Z',points[1] and points[1].at)
    Lab.Check('state','external data cannot enable trading',false,p.browse:IsEnabled() or p.advisor:IsEnabled() or p.track:IsEnabled())
    Lab.Check('state','local saved observations unchanged',before,fingerprint(TwichUIWorkshopDB))
end
if P.scopedState then
    local W=R.Workshop;local B=W.Bridge
    local saved=TwichUIWorkshopDB
    local function fingerprint(v)
        if type(v)~='table' then return tostring(v) end
        local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
        local out={};for _,k in ipairs(keys) do out[#out+1]=tostring(k)..'='..fingerprint(v[k]) end;return '{'..table.concat(out,',')..'}'
    end
    local before=fingerprint(saved)
    local valid=P.scopedState~='corrupt' and P.scopedState~='future'
    Lab.Check('init','scoped bridge initially idle',false,B.Status().ready)
    B.Begin(SIMLAB_BRIDGE)
    for i=1,3000 do local ok,why=B.Step(3);if why~='loading' then break end end
    Lab.Check('state','scoped candidate acceptance',valid,B.Status().ready)
    Lab.Check('state','scoped validation status',valid and 'ready' or 'invalid',B.Status().state)
    local scope=B.Scope()
    Lab.Check('state','scope never claims whole market',false,scope and scope.whole_market_complete or false)
    local item=P.scopedState=='unknown' and 2 or P.scopedState=='absent' and 10000 or P.scopedState=='outside' and 10005 or 10001
    local variant=SIMLAB_BRIDGE.records[P.scopedState=='unknown' and 1 or P.scopedState=='absent' and 1 or 2]:match('"variant_key":"([a-f0-9]+)"')
    if P.scopedState=='outside' then variant=string.rep('f',64) end
    Lab.Check('interact','explicit scoped item navigation',true,A.OpenMarket(item,{market='server',serverVariant=variant}))
    Lab.Settle(0.8);local p=A.Page('market')
    local expected=({priced='priced',absent='observed_absent',unknown='unknown_coverage',outside='outside_scope',corrupt='invalid_generation',future='invalid_generation'})[P.scopedState]
    Lab.Check('state','exact scope availability',expected,p.projection.availability.state)
    local price=p.projection.facts and p.projection.facts.recent
    Lab.Check('state','supported price or explicit unavailable',P.scopedState=='priced' and 100 or nil,price and price.value)
    Lab.Check('state','unavailable never becomes zero',false,price and price.value==0 or false)
    Lab.Check('state','generation stays inactive after rejection',valid,B.Status().ready)
    Lab.Check('state','scoped observations cannot trade',false,p.browse:IsEnabled() or p.advisor:IsEnabled() or p.track:IsEnabled())
    Lab.Check('state','scoped local history unchanged',before,fingerprint(TwichUIWorkshopDB))
    if P.compatibility then
        local J=W.BridgeCodec
        local generation=B.Status().generation
        local receipt=J.Encode((B.Receipt()))
        local record=J.Encode((B.Record(item,variant)))
        Lab.Check('state','Companion summary','Market data from Companion synthetic-simulator',B.CompatibilityText())
        Lab.Check('state','explicit contract diagnostics',true,B.CompatibilityText(true):find('transport 1 · contract 1 · schema 3',1,true)~=nil)
        Lab.Check('state','minimum reader capability',3,B.Compatibility().minimum_reader_version)
        Lab.Check('state','validated receipt producer','synthetic-simulator',B.Status().desktop_build)
        local candidate=J.Copy(SIMLAB_BRIDGE)
        if P.compatibility=='newer' then
            local header=J.Parse(candidate.manifest);header.schema_version=999;candidate.manifest=J.Encode(header)
        elseif P.compatibility=='older' then candidate.transport_version=0 end
        TwichUIMarketData=candidate
        B.Begin(candidate)
        local accepted
        for i=1,3000 do local ok,why=B.Step(3);if why~='loading' then accepted=ok;break end end
        Lab.Check('state','replacement compatibility',P.compatibility=='valid',accepted)
        Lab.Check('state','validated generation retained',generation,B.Status().generation)
        Lab.Check('state','validated receipt retained',receipt,J.Encode((B.Receipt())))
        Lab.Check('state','replacement leaves local history unchanged',before,fingerprint(TwichUIWorkshopDB))
        Lab.Check('state','validated record retained',record,J.Encode((B.Record(item,variant))))
        Lab.Check('state','previous dataset remains ready',true,B.Status().ready)
        A.OpenMarket(item,{market='server',serverVariant=variant});Lab.Settle(0.8)
        p=A.Page('market')
        Lab.Check('state','player provenance visible',true,p.contextText:GetText():find('Market data from Companion synthetic-simulator',1,true)~=nil)
        Lab.Check('state','contract internals are optional',false,p.contextText:GetText():find('transport ',1,true)~=nil)
        Lab.Check('state','receipt diagnostics available',true,p.aggregateText:find('receipt 1',1,true)~=nil)
        local reason=({newer='newer_addon',older='older_companion'})[P.compatibility]
        Lab.Check('state','correct update direction',reason,B.Status().compatibility_reason)
        local message=({newer='Update TwichUI to import it.',older='Update TwichUI Market Companion'})[P.compatibility]
        Lab.Check('state','player update instruction visible',true,message and p.source:GetText():find(message,1,true)~=nil or not message)
        Lab.Check('state','player sees retained data status',P.compatibility~='valid',p.kind:GetText():find('previous compatible data retained',1,true)~=nil)
    end
end
if P.summary then
    local W=R.Workshop;local B=W.Bridge;local valid=P.summary=='valid'
    Lab.Settle(0.5)
    Lab.Check('init','summary automatically recognized',valid,B.Status().ready)
    Lab.Check('state','root does not eagerly decode parts',0,B.Status().loaded_parts)
    Lab.Check('interact','summary research navigation',true,A.OpenMarket(2589,{market='server'}))
    Lab.Settle(1);local p=A.Page('market');local x=p.projection
    Lab.Check('state','supported current reference',valid and 120 or nil,x.facts and x.facts.recent and x.facts.recent.value)
    Lab.Check('state','supported market reference',valid and 100 or nil,x.facts and x.facts.mval and x.facts.mval.value)
    Lab.Check('state','summary contains no daily series',nil,x.series)
    Lab.Check('state','local competition not supplied',nil,x.facts and x.facts.comp)
    Lab.Check('state','two closes do not imply historical value',nil,x.facts and x.facts.hist)
    Lab.Check('state','no transactions authorized',false,p.browse:IsEnabled() or p.advisor:IsEnabled() or p.track:IsEnabled())
    Lab.Check('state','valid summary preserves market faction',valid and 'Horde' or nil,B.Market() and B.Market().faction)
    Lab.Check('state','active decoded partition bounded',true,B.Status().decoded_parts<=1)
    Lab.Check('state','declared coverage only when valid',valid,B.Scope()~=nil)
    Lab.Check('state','future contract actionable',P.summary=='future',B.Status().compatibility_message~=nil)
end
Lab.Finish()
