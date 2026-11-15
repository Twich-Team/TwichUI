-- Real addon shell and handler-level inputs over a synthetic native-frame sentinel.
-- No real auctioneer, server, pointer, combat, font or taint evidence.
local R = TwichUI
A_Admin.SetManualClock(GetTime())
Lab.Solo()
local native = CreateFrame("Frame", nil, UIParent)
native:SetSize(800, 500); native:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 26, -90); native:SetScale(0.83); native:Show()
AuctionHouseFrame = native
local scale, hidden, shown, calls = native:GetScale(), 0, 0, 0
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
Lab.RunUntil(5.5)
if P.empty then A.Browse.Search("no matching observations");Lab.Settle(0.4) end
if P.filtered then A.Browse.Search("Cloth");Lab.Settle(0.4) end
Lab.Finish()
