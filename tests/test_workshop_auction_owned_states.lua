local c,g,Press=dofile(TESTS.."auction_mock.lua")
local W=dofile(TESTS.."auction_market_fixture.lua")(c)
local A,Q=W.AuctionUI,W.AuctionReads
local n=0
local function same(a,b,why) n=n+1;assert(a==b,(why or "")..": "..tostring(a).." ~= "..tostring(b)) end
local available,pending,refreshes=false,0,0
Q.Available=function() return available end
Q.Pending=function() return pending end
Q.Begin=function(kind) same(kind,"owned");refreshes=refreshes+1;return false,"Fixture refusal" end
c.C_AuctionHouse=setmetatable({},{__index=function(_,name) return function() error("forbidden native "..name) end end})
A.Show();A.Go("owned");local p=A.Page("owned")
same(p.refresh:IsEnabled(),false)
same(p.list.empty:GetText():find("unavailable",1,true)~=nil,true)
same(p.status:GetText(),"","one empty/unavailable message")
same(refreshes,0,"opening never refreshes native data")
available=true;pending=1;A.Render()
same(p.list.empty:GetText(),"Loading your auctions…");same(p.refresh:IsEnabled(),false)
pending=0;Q.snapshot={kind="owned",epoch=Q.epoch,rows={},complete=true};A.Render()
same(p.list.empty:GetText(),"No owned listings returned.")
same(p.refresh:IsEnabled(),true)
Q.snapshot.complete=false;A.Render()
same(p.list.empty:GetText():find("partial",1,true)~=nil,true,"incomplete absence is not an empty house")
Q.snapshot.rows={Q.Listing({auctionID=7,itemKey={itemID=10,battlePetSpeciesID=2},quantity=2,buyoutAmount=299,status=0,timeLeftSeconds=0})}
A.Render();Press.Must(p.list.rows[1])
same(p.chosen.auctionID,7);same(p.chosen.seconds,0)
same(p.advice:GetText():find("Variant-specific advice unavailable",1,true)~=nil,true)
same(p.cancel:IsEnabled(),false);same(p.repost:IsEnabled(),false)
same(p.cancel:GetScript("OnClick"),nil);same(p.repost:GetScript("OnClick"),nil)
Press.Must(p.refresh);same(refreshes,1,"only an explicit refresh invokes the broker")
Q.epoch=Q.epoch+1;A.Render();same(#p.rows,0,"stale visit rows disappear")
same(p.chosen,nil,"stale selection does not keep a detail record")
A.Hide();same(p.rows,nil);same(p.chosen,nil);same(A.Snapshot().events,0)
print("PASSED: Owned states "..n.." checks")
