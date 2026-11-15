-- Real addon shell and handler-level inputs over a synthetic native-frame sentinel.
-- No real auctioneer, server, pointer, combat, font or taint evidence.
if P.categories then
    -- Synthetic hierarchy tests presentation; runtime data comes from Blizzard.
    AuctionCategories={{name="Fixture trade group",filters={{classID=7}},
        subCategories={{name="Fixture subclass",filters={{classID=7,subClassID=0}}}}}}
end
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
    Lab.Check("state","Shopping unsubscribes hidden",0,W.Strategy.ListenerCount())
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
local function MarketSeed(W,sparse)
    local now=time();local today=math.floor(now/86400)
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
    Lab.Check("state","Market hidden cache released",0,W.AuctionMarketData.Stats().cache)
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
    C_Container.GetContainerNumSlots=function(bag) return bag==0 and not P.bagEmpty and 2 or 0 end
    C_Container.GetContainerItemInfo=function(_,slot)
        return {itemID=slot==1 and 7067 or 4306,stackCount=slot==1 and 3 or 20,isBound=false,isLocked=false}
    end
    C_AuctionHouse.IsSellItemValid=function() return true end
    A.Go("sell");Lab.Settle(0.3)
    local p=A.Page("sell")
    if p.list.rows[1] and p.list.rows[1].data then
        p.list.rows[1]:Click();p.price:SetText("101")
    end
end
if P.owned then
    -- Inject normalized synthetic evidence for presentation only; never native I/O.
    local Q=R.Workshop.AuctionReads
    Q.Available=function() return true end
    Q.state=P.ownedEmpty and "empty" or "results"
    Q.snapshot={epoch=Q.epoch,kind="owned",rows=P.ownedEmpty and {} or {
        {auctionID=21,item=7067,itemKey={itemID=7067,itemLevel=0,itemSuffix=0},qty=3,total=299,unit=100,status=0,seconds=1800},
        {auctionID=22,item=4306,itemKey={itemID=4306,itemLevel=0,itemSuffix=0},qty=20,total=12000,unit=600,status=0,band=2}
    }}
    A.Go("owned");Lab.Settle(0.3)
    local p=A.Page("owned")
    if p.list.rows[1] and p.list.rows[1].data then p.list.rows[1]:Click() end
end
if P.market then
    local W=R.Workshop
    MarketSeed(W,P.marketSparse)
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
    A.Market.Search("");Lab.Settle(0.5)
    local p=A.Page("market")
    for _=1,100 do if not p.job then break end;Lab.Settle(0.05) end
    A.Market.Select(7067)
    if P.marketRecent then A.Market.Range(2) elseif P.marketLong then A.Market.Range(120) else A.Market.Range(14) end
    if P.marketTracked then A.Market.Filter("scope","tracked");Lab.Settle(0.5) end
end
Lab.Finish()
