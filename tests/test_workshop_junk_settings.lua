-- The real settings picker and launcher over synthetic bags. No item action API.
dofile(TESTS.."harness.lua")
dofile(TESTS.."settings_mock.lua")
local c,S=SettingsClient({beforeInit=function(c)
    c.UISpecialFrames={}
    local chunk=assert(loadfile(ROOT.."WorkshopLauncher.lua"));setfenv(chunk,c);chunk()
end})
dofile(TESTS.."mi_mock.lua")
c.UIParent=MIFake("Frame");c.UIParent:SetSize(1600,1200)
c.CreateFrame=function(kind,_,parent)
    local frame=MIFake(kind,parent)
    frame.UnregisterAllEvents=function(self) self.events={} end
    frame.Click=function(self) if self:IsEnabled() and self:GetScript("OnClick") then self:GetScript("OnClick")(self) end end
    return frame
end
local R=c.TwichUI
local L,P=R.WorkshopLauncher,R.WorkshopJunkSettings
local bags={{itemID=100},{itemID=100},{itemID=211527},{itemID=200}}
c.NUM_TOTAL_EQUIPPED_BAG_SLOTS=0
c.C_Container={GetContainerNumSlots=function() return #bags end,GetContainerItemInfo=function(_,slot) return bags[slot] end}
c.C_Item.GetItemInfo=function(id) return "Bag item "..id,nil,nil,nil,nil,nil,nil,nil,nil,134400 end
local cursor,cleared
c.GetCursorInfo=function() return cursor and cursor[1],cursor and cursor[2] end
c.ClearCursor=function() cursor=nil;cleared=(cleared or 0)+1 end
assert(#P.Entries("bags")==3,"bag picker deduplicates item IDs")
assert(#P.Entries("bags","200")==1)
assert(not L.Loaded() and not L.Enabled())
local settings=c.CreateFrame("Frame",nil,c.UIParent);settings:Show()
R.SettingsUI.Frame=function() return settings end
R.SettingsUI.IsShown=function() return settings:IsShown() end
R.SettingsUI.Close=function() settings:Hide();R.SettingsLauncher.Closed() end
local section,button
for _,row in ipairs(S.K.pages.workshop.rows) do
    if row.kind=="header" then section=row:GetName() end
    if row:GetName()=="Never mark items" then assert(section=="Junk marking");button=row end
end
assert(button and R.SettingsDesign.TaskFor(S.K.pages.workshop,"Junk marking")=="General")
local found=false
for _,result in ipairs(R.SettingsSearch.Run("never mark")) do
    if result.entry.page=="workshop" and result.entry.row==button then found=true end
end
assert(found,"settings search discovers the picker without opening it")
button.click()
assert(P.Shown() and not L.Loaded(),"picker requires no Workshop or market load")
local f=P.Frame()
local target
for _,row in ipairs(f.rows) do if row.entry and row.entry.id==200 then target=row end end
assert(target and target.action:IsEnabled())
target.action:Click();assert(L.JunkIgnored(200),"bag selection stores never-mark ID")
cursor={"item",100};f.drop:GetScript("OnReceiveDrag")()
assert(cleared==1 and L.JunkIgnored(100),"drop saves ID and returns item")
cursor={"spell",123};assert(not P.TakeCursor() and cleared==1 and cursor)
cursor={"item",0};assert(not P.TakeCursor() and cleared==1)
cursor={"item",211527};assert(P.TakeCursor() and cleared==2 and L.JunkIgnored(211527),"dropping a protected item confirms and returns it")
f.ignored:Click();assert(#P.Entries("ignored")==2)
for _,row in ipairs(f.rows) do if row.entry and row.entry.id==200 then row.action:Click();break end end
assert(not L.JunkIgnored(200) and L.JunkIgnored(100))
-- Newer-schema holds apply at the owner API, including cursor edits.
local isHeld=R.Persist.IsHeld
R.Persist.IsHeld=function() return true end
cursor={"item",300}
assert(not P.TakeCursor() and not L.JunkIgnored(300) and cleared==2)
assert(not L.SetJunkFilter("recipes",true) and not L.SetJunkIgnored(100,false))
R.Persist.IsHeld=isHeld
-- Pagination has a fixed row pool; closing unregisters all bag/item listeners.
bags={};for id=1,30 do bags[id]={itemID=1000+id} end
f.bags:Click();assert(f.next:IsEnabled() and not f.prev:IsEnabled() and #f.rows==7)
f.next:Click();assert(f.prev:IsEnabled())
f.search:SetText("1030");f.search:GetScript("OnTextChanged")();assert(f.rows[1].entry.id==1030 and not f.next:IsEnabled())
local escape=c.TwichUISettingsEsc
escape:Hide();assert(not P.Shown() and R.SettingsUI.IsShown(),"Escape closes picker before settings")
assert(next(f.events)==nil,"closed picker keeps no listeners")
P.Open();R.SettingsUI.Close();assert(not P.Shown())
P.Open();assert(not P.Shown(),"picker cannot open without settings")
assert(L.JunkIgnored(100),"closing keeps saved ignores")
print("PASSED Workshop junk settings: bag selection, drag, protection, held data, pagination, Escape and lifecycle")
