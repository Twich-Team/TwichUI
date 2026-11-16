local c,g,Press=dofile(TESTS.."auction_mock.lua")
local R,A=c.TwichUI,c.TwichUI.Workshop.AuctionUI
local faults={};R.Fault=function(source,why) faults[#faults+1]={source,why} end
assert(A.Show())
local root=A.Frame()
A.Register("sell",{Build=function(p) c.CreateFrame("Frame",nil,p);error("fixture build failure") end})
assert(A.Go("sell")==false and root.failure:IsShown(),"lazy build failure has a visible state")
local frames=#c.testFrames
for i=1,20 do assert(A.Go("sell")==false) end
assert(#c.testFrames==frames and #faults==1,"failed builder is not retried into growing partial frames")
assert(faults[1][1]=="auction preview build")
assert(A.Go("browse") and not root.failure:IsShown(),"navigation recovers to another page")
local fail=true
A.Register("owned",{
 Build=function(p) p:RegisterEvent("BAG_UPDATE_DELAYED") end,
 Render=function() if fail then error("fixture render failure") end end,
 Release=function(p) p:UnregisterAllEvents() end,
})
A.Go("owned")
assert(root.failure:IsShown() and not A.Page("owned"):IsShown(),"render fault exposes safe shell")
assert(next(A.Page("owned").events)==nil,"failed render releases listeners")
for i=1,10 do A.Schedule();FlushTimers() end
assert(#faults==2,"events do not repeatedly render a failed page")
fail=false;assert(A.Go("owned"));assert(A.Page("owned"):IsShown() and not root.failure:IsShown(),"explicit retry can recover a transient render error")
Press.Must(root.close);assert(not A.IsShown(),"close remains reachable after faults")
-- Resizing is bounded, drag-only and stopped by hide/scale changes.
A.Show();assert(A.Resize(1720,1080));assert(root:GetWidth()==1720 and root:GetHeight()==1080)
assert(A.Resize(1,1));assert(root:GetWidth()==1420 and root:GetHeight()==880)
c.UIParent.w,c.UIParent.h=1000,700
assert(A.Resize(1920,1200));assert(root:GetWidth()==1586 and root:GetHeight()==1086,"growth respects shared fit scale floor")
c.UIParent.w,c.UIParent.h=1920,1080
A.Resize(1420,880)
assert(not A.Resize(math.huge,900));assert(not A.Resize(1500,0/0))
local x,y=100,100
c.GetCursorPosition=function() return x,y end
c.IsMouseButtonDown=function() return true end
root.resize:GetScript("OnMouseDown")(root.resize,"LeftButton")
x,y=300,0
root.resize:GetScript("OnUpdate")(root.resize,0.05)
assert(root:GetWidth()==1620 and root:GetHeight()==980)
assert(A.Snapshot().sizing==1)
root:GetScript("OnEvent")(root,"UI_SCALE_CHANGED")
assert(root.resize:GetScript("OnUpdate")==nil and A.Snapshot().sizing==0)
root.resize:GetScript("OnMouseDown")(root.resize,"LeftButton")
A.Hide();assert(root.resize:GetScript("OnUpdate")==nil)
-- An interrupted shell build cannot be reused or create another partial root.
local c2=dofile(TESTS.."auction_mock.lua")
local B=c2.TwichUI.Workshop.AuctionUI
c2.TwichUI.FrameLook.Shell=function() error("fixture shell failure") end
assert(not pcall(B.Show));assert(B.Frame() and not B.Frame():IsShown())
local made=#c2.testFrames
local ok,why=B.Show();assert(ok==false and why=="INCOMPLETE")
assert(#c2.testFrames==made,"interrupted shell construction stays bounded")
print("PASSED: Auction preview build/render recovery and resize lifecycle")
