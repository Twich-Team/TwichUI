-- Real Host/launcher/five-page UI and Reach geometry. Native/session/combat
-- boundaries are synthetic. This cannot establish Forever acceptance.
local R,H=TwichUI,TwichUI.AuctionHost
A_Admin.SetManualClock(GetTime());Lab.Solo();Lab.BUDGET=45
local native=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
native:SetSize(800,538);native:SetPoint("TOPLEFT",UIParent,"TOPLEFT",30,-100)
native:SetScale(0.8);native:SetClampedToScreen(false);native:EnableMouse(true)
native:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2})
native:SetBackdropColor(.10,.07,.04,1);native:SetBackdropBorderColor(.5,.35,.15,1)
local label=native:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
label:SetPoint("TOPLEFT",24,-24);label:SetText("Synthetic Blizzard native boundary\nRestored anchors; no native-client acceptance")
native:Show();AuctionHouseFrame=native
AuctionHouseFrameDisplayMode={Buy={}}
native.GetDisplayMode=function() return AuctionHouseFrameDisplayMode.Buy end
local scale=native:GetScale()
local available,combat,closed,calls=true,false,0,0
C_PlayerInteractionManager={IsInteractingWithNpcOfType=function()return available end,IsValidNPCInteraction=function()return available end}
InCombatLockdown=function()return combat end
C_AuctionHouse=setmetatable({},{__index=function(_,key)return function()calls=calls+1;error("integration issued auction operation "..key)end end})
-- This is a synthetic close boundary, never a substitute for the client test.
HideUIPanel=function(f) assert(f==native);closed=closed+1;available=false;f:Hide();H.Ended() end
local A,f
local function CheckState(label)
 Lab.Check("state",label.." state","twichui",H.Snapshot().state)
 Lab.Check("state",label.." live interaction",true,available)
 local presentation=A.Presentation()
 Lab.Check("construct",label.." custom visible in viewport",true,presentation.usable)
 Lab.Check("construct",label.." completed initialization",true,presentation.initialized)
 Lab.Check("construct",label.." completed page render",true,presentation.rendered)
 Lab.Check("state",label.." native still visible",true,native:IsVisible())
 Lab.Check("state",label.." native offscreen",true,native:GetLeft()*native:GetEffectiveScale()>UIParent:GetRight()*UIParent:GetEffectiveScale())
end
local function Reach(label,button,kind)
 local hit=R.TestLab.Reach.Analyze(button,{kind=kind or "click",evidence="simulator-geometry",limit=1000000})
 Lab.Check("construct",label,"reachable",hit.verdict)
end
Lab.Step("gated opening",function()
 Lab.Check("init","integration disabled by default",false,H.Snapshot().enabled)
 Lab.Check("init","Workshop unloaded by default",false,R.WorkshopLauncher.Loaded())
 Lab.Check("init","Phase A acknowledgement required",false,H.SetTestEnabled(true))
 H.Opened();Lab.Settle(.2)
 Lab.Check("state","default opening leaves native anchors",30,select(4,native:GetPoint(1)))
 Lab.Check("state","default opening never loads Workshop",false,R.WorkshopLauncher.Loaded())
 H.Ended()
 R.WorkshopLauncher.SetEnabled(true);H.Command("confirm-native");H.Command("replacement on")
 H.Opened();H.Opened();Lab.Settle(.4)
 A=R.Workshop.AuctionUI;f=A.Frame()
 Lab.Check("construct","existing five-page shell is integrated","auctioneer",A.Context())
 Lab.Check("construct","Workshop crafting window unbuilt",false,R.Workshop.Snapshot().built)
 Lab.Check("state","native scan control not attached",false,R.Workshop.AuctionButton.Attached())
 Lab.Check("state","only one Workshop load",1,R.WorkshopLauncher.Snapshot().attempts)
 CheckState("opening")
end)
Lab.Step("five pages and geometry",function()
 for _,key in ipairs({"browse","shopping","sell","owned","market","browse"}) do
  Reach("navigation reachable "..key,A.nav[key]);A.nav[key]:Click();Lab.Settle(.2)
  Lab.Check("interact","page navigation "..key,key,A.Mode())
  Lab.Check("construct","page visible "..key,true,A.Page(key):IsVisible())
 end
 Reach("header Blizzard switch reachable",f.blizzard);Reach("close reachable",f.close)
 Reach("Browse dropdown reachable",A.Page("browse").categoryDrop)
 Reach("Browse search reachable",A.Page("browse").submit)
 Lab.Check("state","Browse purchasing disabled",false,A.Page("browse").detail.buy:IsEnabled())
 Lab.Check("state","five lazy pages reused",5,A.Snapshot().pages)
 local over=CreateFrame("Frame",nil,f);over:SetAllPoints(f.blizzard);over:SetFrameLevel(f.blizzard:GetFrameLevel()+20);over:EnableMouse(true);over:Show()
 Lab.Check("construct","negative overlay is detected","blocked",R.TestLab.Reach.Analyze(f.blizzard,{kind="click",evidence="simulator-geometry",limit=1000000}).verdict)
 over:Hide();Reach("switch recovers from overlay",f.blizzard)
end)
Lab.Step("same-visit interface switching",function()
 local id=H.Snapshot().visit
 f.blizzard:Click();Lab.Settle(.2)
 Lab.Check("interact","switch restores Blizzard","blizzard",H.Snapshot().state)
 Lab.Check("state","exact native x restored",30,select(4,native:GetPoint(1)))
 Lab.Check("state","exact native scale restored",scale,native:GetScale())
 Lab.Check("state","switch never closes interaction",0,closed)
 Lab.Check("state","hidden UI listeners released",0,A.Snapshot().events)
 Lab.Check("state","hidden UI jobs released",0,A.Snapshot().jobs)
 Lab.Check("state","hidden UI timers released",0,A.Snapshot().timers)
 Reach("return-to-TwichUI reachable",H.Control());H.Control():Click();Lab.Settle(.2)
 CheckState("return")
 Lab.Check("state","return retains visit identity",id,H.Snapshot().visit)
 Lab.Check("state","external Market remains unloaded",false,R.Workshop.Bridge.Status().ready)
end)
Lab.Step("repeated close and reopen",function()
 for i=1,10 do
  f.close:Click();Lab.Settle(.2)
  Lab.Check("state","close clears lease "..i,false,H.Snapshot().leased)
  Lab.Check("state","close clears page jobs "..i,0,A.Snapshot().jobs)
  Lab.Check("state","close clears page listeners "..i,0,A.Snapshot().events)
  Lab.Check("state","close clears timers "..i,0,A.Snapshot().timers+H.Snapshot().pending)
  available=true;native:Show();H.Opened();Lab.Settle(.2)
  Lab.Check("interact","new visit opens replacement "..i,"twichui",H.Snapshot().state)
 end
 Lab.Check("state","reopen retains exactly five pages",5,A.Snapshot().pages)
 Lab.Check("state","reopen never reloads Workshop",1,R.WorkshopLauncher.Snapshot().attempts)
 Lab.Check("state","normal close called exactly ten times",10,closed)
end)
Lab.Step("combat recovery and environmental changes",function()
 combat=true;R.frame:GetScript("OnEvent")(R.frame,"PLAYER_REGEN_DISABLED")
 Lab.Check("state","combat retains recovery snapshot","recovery",H.Snapshot().state)
 Lab.Check("state","combat retains visible replacement until recovery",true,A.IsShown())
 combat=false;R.frame:GetScript("OnEvent")(R.frame,"PLAYER_REGEN_ENABLED")
 Lab.Check("state","combat exit restores only","blizzard",H.Snapshot().state)
 Lab.Check("state","combat exit native x",30,select(4,native:GetPoint(1)))
 H.Control():Click();Lab.Settle(.2)
 R.frame:GetScript("OnEvent")(R.frame,"UI_SCALE_CHANGED")
 Lab.Check("state","scale change restores native","blizzard",H.Snapshot().state)
 H.Control():Click();Lab.Settle(.2)
 CheckState("after scale fallback")
end)
Lab.Step("empty-screen failures recover visibly",function()
 H.ToBlizzard()
 local left,right=f.GetLeft,f.GetRight
 f.GetLeft=function() return 100000 end;f.GetRight=function() return 101420 end
 H.Control():Click();Lab.Settle(.2)
 Lab.Check("state","offscreen replacement refused","blizzard",H.Snapshot().state)
 Lab.Check("construct","offscreen failure restores usable native",true,H.Presentation(native).usable)
 Lab.Check("state","offscreen failure never retains hidden replacement",false,A.IsShown())
 local attempts=H.Snapshot().failed
 H.Opened();Lab.Settle(.2)
 Lab.Check("state","failed visit does not retry automatically",attempts,H.Snapshot().failed)
 f.GetLeft,f.GetRight=left,right
 -- The opening callback must acknowledge its completion even when the client
 -- catches script errors. Intercept only this deliberate fixture's fault.
 local fit,fault=R.FitToScreen,R.Fault
 local caught=0
 R.FitToScreen=function() error("injected opening layout failure",0) end
 R.Fault=function(source,err)
  if source=="auction window show" and tostring(err)=="injected opening layout failure" then caught=caught+1
  else fault(source,err) end
 end
 H.Control():Click();Lab.Settle(.2)
 R.FitToScreen,R.Fault=fit,fault
 Lab.Check("state","OnShow exception captured",1,caught)
 Lab.Check("state","OnShow exception refuses takeover","blizzard",H.Snapshot().state)
 Lab.Check("construct","OnShow exception leaves usable native",true,H.Presentation(native).usable)
 Lab.Check("state","failed opening cancels initialization",0,H.Snapshot().pending)
 Reach("failure recovery control reachable",H.Control())
 H.Control():Click();Lab.Settle(.2)
 CheckState("explicit recovery")
 -- Foreign anchors still outside the viewport are never reported restored.
 native:ClearAllPoints();native:SetPoint("TOPLEFT",UIParent,"TOPRIGHT",5000,0)
 local restoreFault=R.Fault
 R.Fault=function(source,err)
  if source~="auction proof restore" or tostring(err)~="foreign native anchors remain unavailable" then restoreFault(source,err) end
 end
 local restored=H.ToBlizzard()
 Lab.Check("state","offscreen foreign anchors block recovery",false,restored)
 Lab.Check("state","blocked recovery retains lease",true,H.Snapshot().leased)
 Lab.Check("state","blocked recovery is truthful","restore-blocked-owner",H.Snapshot().reason)
 Reach("blocked recovery action reachable",H.Control())
 native:ClearAllPoints();native:SetPoint("TOPLEFT",UIParent,"TOPLEFT",30,-100)
 H.Control():Click();R.Fault=restoreFault
 Lab.Check("state","foreign visible recovery releases lease",false,H.Snapshot().leased)
 Lab.Check("construct","foreign recovery verifies usable native",true,H.Presentation(native).usable)
 H.Control():Click();Lab.Settle(.2)
end)
Lab.Step("retention and diagnostics",function()
 local before=A.Snapshot()
 local frameCount=0;local frame=EnumerateFrames()
 while frame do frameCount=frameCount+1;frame=EnumerateFrames(frame) end
 for i=1,10 do H.ToBlizzard();H.Control():Click();Lab.Settle(.2) end
 local afterFrames=0;frame=EnumerateFrames()
 while frame do afterFrames=afterFrames+1;frame=EnumerateFrames(frame) end
 local after=A.Snapshot()
 Lab.Check("state","warm switches do not grow frames",0,afterFrames-frameCount)
 Lab.Check("state","warm switches retain row pool",before.rows,after.rows)
 Lab.Check("state","warm switches retain subscriptions",before.subscriptions,after.subscriptions)
 Lab.Check("state","warm switches retain event count",before.events,after.events)
 Lab.Check("state","no pending initialization timer",0,H.Snapshot().pending)
 Lab.Check("state","zero auction operations",0,calls)
 local s=H.Snapshot()
 for _,key in ipairs({"openMS","loadMS","activateMS","restoreMS","switchMS"}) do
  Lab.Check("state","timing available "..key,true,type(s[key])=="number" and s[key]>=0)
  Lab.Say("performance",key,s[key])
 end
 Lab.Say("resources","frames",afterFrames,"pages",after.pages,"rows",after.rows,"events",after.events,"subscriptions",after.subscriptions)
end)
Lab.Step("capture final presentation",function()
 if P.scaled then
  H.ToBlizzard();UIParent:SetScale(.8);H.Control():Click();Lab.Settle(.3)
 end
 if P.restored then H.ToBlizzard() end
 Lab.Check("state","capture mode",P.restored and "blizzard" or "twichui",H.Snapshot().state)
 Lab.Check("construct","native visibility preserved",true,native:IsVisible())
 if not P.restored then
  Reach("final Blizzard switch reachable",f.blizzard)
  Lab.Check("construct","window fits viewport",true,f:GetWidth()*f:GetEffectiveScale()<=UIParent:GetWidth()*UIParent:GetEffectiveScale())
 else
  Reach("final return action reachable",H.Control())
  Lab.Check("construct","native original x in restored capture",30,select(4,native:GetPoint(1)))
 end
 Lab.Check("state","no auction operations after all switches",0,calls)
 Lab.RunUntil(12)
end)
Lab.Finish()
