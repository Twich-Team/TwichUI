dofile(TESTS.."harness.lua")
local n=0
local function Same(a,b,label) n=n+1;assert(a==b,(label or "check")..": "..tostring(a).." ~= "..tostring(b)) end
local Base=dofile(TESTS.."auction_host_mock.lua")(Same)
local function Setup(dev,saved)
 local t=Base();local c,R,H=t.c,t.R,t.H
 c.TwichUIDB={ui={workshopEnabled=true,auctionDebug=saved}}
 R.AuctionBuild={development=dev,verified={}}
 local shown,ctx=false,"preview"
 R.Workshop={AuctionUI={Context=function() return ctx end,IsShown=function() return shown end,
  Prepare=function() return true end,ShowIntegrated=function(id) Same(id,H.Snapshot().visit);shown,ctx=true,"auctioneer";return true end,
  Hide=function() shown,ctx=false,"preview" end}}
 R.WorkshopLauncher={Enabled=function() return true end,Load=function() end,LoadAuctionUI=function() t.loads=t.loads+1;return true end}
 return t
end
do
 local t=Setup(false,true);t.H.ApplyDebug();t.H.Opened();t.Flush()
 Same(t.H.DebugEnabled(),false,"release ignores saved development preference")
 Same(t.H.SetDebug(true),false);Same(t.loads,0);Same(t.nativeMutations or 0,0);Same(t.frames,0)
 Same(t.c.TwichUIDB.ui.auctionDebug,true,"release preserves the preference without using it")
end
do
 local t=Setup(true,false);Same(t.H.DebugEnabled(),false)
 t.c.SlashCmdList.TWICHUI("ahdebug on")
 Same(t.H.DebugEnabled(),true);Same(t.c.TwichUIDB.ui.auctionDebug,true)
 t.H.Opened();t.Flush();Same(t.H.Snapshot().state,"twichui","no confirm-native")
 t.now=61;t.Tick();Same(t.H.Snapshot().state,"twichui","no 30-second interruption")
 Same(t.H.ToBlizzard(),true);t.Restored();t.H.Control():Click()
 Same(t.H.Snapshot().state,"twichui","same-visit return")
 Same(t.H.SetDebug(false),true);t.Restored();Same(t.c.TwichUIDB.ui.auctionDebug,false)
 t.H.Ended();t.H.Opened();t.Flush();Same(t.H.Snapshot().state,"blizzard","disabled stays off next visit")
end
do
 local t=Setup(true,true);t.H.ApplyDebug()
 Same(t.loads,0,"persisted choice does not load Workshop at login");Same(t.frames,0)
 t.H.Opened();t.Flush();Same(t.H.Snapshot().state,"twichui")
 t.combat=true;Same(t.H.SetDebug(false),false,"protected restoration deferred")
 Same(t.c.TwichUIDB.ui.auctionDebug,false,"off persists even when restore must wait")
 t.combat=false;t.c.FireEvent("PLAYER_REGEN_ENABLED");t.Restored()
end
do
 local t=Setup(true,true);t.R.Persist={IsHeld=function() return true end}
 t.H.ApplyDebug();Same(t.H.DebugEnabled(),false);Same(t.H.SetDebug(true),false)
 Same(t.c.TwichUIDB.ui.auctionDebug,true,"held settings are not rewritten")
 Same(t.H.SetDebug(false),true,"emergency off still works with held data")
end
do
 local t=Setup(true,true);t.H.ApplyDebug();t.H.Opened();t.Flush()
 t.c.TwichUIDB.ui.auctionDebug=false;t.H.ApplyDebug();t.Restored()
 Same(t.H.Snapshot().enabled,false,"profile change disarms presentation")
end

do
 local t=Setup(true,true);local popup
 t.R.Workshop.AuctionActions={OwnsNativeWarning=function() return true end,Visit=function() end}
 t.c.StaticPopup_Visible=function(key) return key==popup end
 t.H.ApplyDebug();t.H.Opened();t.Flush()
 popup="AUCTION_HOUSE_POST_WARNING";t.Tick();Same(t.H.Snapshot().state,"twichui","only the owned posting warning is permitted")
 popup="BUYOUT_AUCTION";t.Tick();t.Restored();Same(t.H.Snapshot().state,"blizzard","unrelated native confirmations still restore")
end
print("PASSED: development-only persistent Auction House mode "..n.." checks")
