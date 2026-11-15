local c, g, Press = dofile(TESTS .. "auction_mock.lua")
local R, W = c.TwichUI, c.TwichUI.Workshop
local A = W.AuctionUI
local checks = 0
local function same(a,b,msg) checks=checks+1; assert(a==b,(msg or "").." expected "..tostring(b)..", got "..tostring(a)) end
same(A.Frame(),nil,"lazy root")
same(W.Window.Frame(),nil,"Workshop remains unbuilt")
local native = c.CreateFrame("Frame", "AuctionHouseFrame", c.UIParent)
native:SetPoint("CENTER",c.UIParent,"CENTER",30,20); native:SetScale(0.8); native:Show()
local nativeCalls = 0
for _, key in ipairs({"Hide","Show","SetPoint","ClearAllPoints","SetScale","SetParent","EnableMouse"}) do
    native[key]=function() nativeCalls=nativeCalls+1; error("native mutation: "..key) end
end
c.C_AuctionHouse = setmetatable({}, {__index=function(_,key) return function() error("auction call: "..key) end end})
same(A.Show(),true,"explicit show")
local f=A.Frame()
same(A.Mode(),"browse","Browse default")
same(W.Window.Frame(),nil,"preview never opens Workshop")
same(A.Snapshot().events,2,"visible events")
for _,key in ipairs({"browse","shopping","sell","owned","market"}) do
    Press.Must(A.nav[key]); same(A.Mode(),key,"navigation")
    same(A.Page(key):IsShown(),true,"active page")
    if key=="sell" or key=="owned" or key=="market" then same(A.Page(key).placeholder~=nil,true,"honest placeholder") end
end
local frames=#c.testFrames
for i=1,50 do
    for _,key in ipairs({"browse","shopping","sell","owned","market"}) do Press.Must(A.nav[key]) end
    Press.Must(f.close); same(A.Snapshot().events,0,"closed unsubscribed")
    A.Show(); same(A.Mode(),"browse","reopen defaults Browse")
    for key,page in pairs(A.views) do same(page:IsShown(),key=="browse","only Browse visible after reopen") end
end
same(#c.testFrames,frames,"repeat use has no new frames")
same(A.Snapshot().pages,5,"five pages built once")
Press.Must(f.blizzard); same(f:IsShown(),false,"Blizzard switch closes preview")
same(nativeCalls,0,"native never mutated")
c.InCombatLockdown=function() return true end
same(A.Show(),false,"combat refuses opening")
c.InCombatLockdown=function() return false end
A.Show(); f:SetSize(1240,760); f:GetScript("OnEvent")(f,"UI_SCALE_CHANGED"); FlushTimers()
same(f:IsShown(),true,"scale change keeps preview")
local found=0
for _,name in ipairs(c.UISpecialFrames) do if name=="TwichUIAuctionPreview" then found=found+1 end end
same(found,1,"one Escape registration")
A.Hide(); same(A.Snapshot().events,0,"final close clean")
print("PASSED: auction shell "..checks.." checks")
