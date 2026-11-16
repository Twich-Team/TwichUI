AUCTION_MOCK_OPTIONS={preview=true,native=true}
local c,g,Press=dofile(TESTS.."auction_mock.lua")
local R,W=c.TwichUI,c.TwichUI.Workshop
assert(not W.AuctionButton.Attached(),"preview load never attaches native button")
assert(c.nativeHooks==0,"preview load never hooks native frame")
W.AuctionUI.Show();W.AuctionUI.Go("shopping");W.AuctionUI.Hide()
assert(c.nativeHooks==0 and not W.AuctionButton.Attached(),"preview navigation does not attach native integration")
R.WorkshopLauncher.previewLoading=nil
W.Window.Show()
assert(W.AuctionButton.Attached(),"normal Workshop resumes its established button")
assert(c.nativeHooks==2,"normal integration attaches exactly once")
W.Window.Hide();W.Window.Show();assert(c.nativeHooks==2,"normal repeated use does not rehook")
W.Window.Hide()
-- The real launcher always clears its transient flag on refused/throwing loads.
R.Workshop=nil
local chunk=assert(loadfile(ROOT.."WorkshopLauncher.lua"));setfenv(chunk,c);chunk()
local L=R.WorkshopLauncher
local attempts=0
c.C_AddOns={LoadAddOn=function()
 attempts=attempts+1;assert(L.previewLoading==true,"flag is scoped to explicit load")
 return false,"MISSING"
end}
assert(L.AuctionPreview()==false);assert(L.previewLoading==nil and attempts==1)
c.C_AddOns=nil;assert(L.AuctionPreview()==false);assert(L.previewLoading==nil)
print("PASSED: preview native-frame isolation, normal Workshop integration and refused-load cleanup")
