local c,g,Press=dofile(TESTS.."auction_mock.lua")
local R,W=c.TwichUI,c.TwichUI.Workshop
local A=W.AuctionUI
local current,leased,closed,restored=true,false,0,0
R.AuctionHost={
 IsCurrent=function(id) return current and id==7 end,
 Snapshot=function() return {state="preparing",leased=leased} end,
 ToBlizzard=function() restored=restored+1;A.Hide();return true end,
 InterfaceHidden=function(id) assert(id==7);closed=closed+1 end,
}
assert(A.Prepare());local root=A.Frame()
assert(not A.IsShown() and A.Page("browse"),"preparation builds hidden before native mutation")
assert(not A.ShowIntegrated(7),"presentation needs Host lease")
leased=true;assert(A.ShowIntegrated(7));assert(A.Context()=="auctioneer")
assert(root.note:GetText():find("TwichUI Auction House",1,true))
for _,key in ipairs({"shopping","sell","owned","market","browse"}) do
 Press.Must(A.nav[key]);assert(A.Mode()==key and A.Page(key):IsVisible())
end
assert(not A.Page("browse").detail.buy:IsEnabled())
local frames=#c.testFrames
for i=1,20 do
 Press.Must(root.blizzard);assert(not A.IsShown());assert(A.Snapshot().events==0)
 assert(A.Snapshot().jobs==0 and A.Snapshot().subscriptions==0)
 assert(A.Prepare());assert(A.ShowIntegrated(7))
end
assert(#c.testFrames==frames,"switches reuse the shell, five pages and chart")
Press.Must(root.close);assert(not A.IsShown() and closed==21)
assert(A.Context()=="preview");assert(A.Show());assert(A.Context()=="preview")
Press.Must(root.blizzard);assert(restored==20,"standalone header never enters Host")
assert(not A.IsShown())
current=false;assert(not A.ShowIntegrated(7),"stale visit cannot show shell")
print("PASSED: shared integrated shell, five-page reachability and retained-resource bounds (offline)")
