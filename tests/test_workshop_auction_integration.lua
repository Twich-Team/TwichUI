-- Host owns visit identity and all native writes. Exhaustive synthetic failures
-- use sentinels, with the real five-page shell exercised separately below.
dofile(TESTS .. "harness.lua")
local count = 0
local function Same(a,b,label)
    count=count+1;assert(a==b,(label or "check")..": expected "..tostring(b)..", got "..tostring(a))
end
local Base = dofile(TESTS .. "auction_host_mock.lua")(Same)
local function Setup()
    local t=Base();local c,R,H=t.c,t.R,t.H
    local shown,context,id=false,"preview",nil
    local A={}
    t.custom=t.Frame(c.UIParent);t.custom.shown=false
    R.Workshop={AuctionUI=A}
    function A.Context() return context end
    function A.Prepare() t.builds=(t.builds or 0)+1;return true end
    function A.ShowIntegrated(v) shown,context,id=true,"auctioneer",v;t.custom:Show();return true end
    function A.IsShown() return shown end
    function A.Presentation() return H.Presentation(t.custom,true) end
    function A.Hide() t.custom:Hide();shown=false;context="preview";if id then H.InterfaceHidden(id) end;id=nil end
    R.WorkshopLauncher={Enabled=function() return true end,Load=function() end,
        LoadAuctionUI=function() t.loads=t.loads+1;return true end}
    c.HideUIPanel=function(f) t.closed=(t.closed or 0)+1;t.available=false;f:Hide();H.Ended() end
    function t.Enable() H.Command("confirm-native");Same(H.SetTestEnabled(true),true) end
    function t.Start() t.Enable();H.Opened();t.Flush();Same(H.Snapshot().state,"twichui") end
    return t
end

do
    local t=Setup();local H=t.H
    Same(H.SetTestEnabled(true),false,"Phase A acknowledgement required")
    H.Opened();t.Flush();Same(t.loads,0);Same(t.mutations,0)
    H.Ended();t.Start()
    Same(t.loads,1);Same(t.builds,1);Same(H.Snapshot().pending,0)
    H.Opened();t.c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21);t.Flush()
    Same(t.loads,1,"duplicate opens do not load/build again")
    Same(H.Snapshot().visit,2)
    Same(H.ToBlizzard(),true);t.Restored();Same(t.available,true)
    H.Control():Click();Same(H.Snapshot().state,"twichui");Same(t.available,true)
    local frameCount=t.frames
    for i=1,100 do
        Same(H.ToBlizzard(),true);Same(H.SwitchToTwichUI(),true)
    end
    Same(t.frames,frameCount,"recovery frame pooled across switches")
    Same(#t.f.hooks.OnHide,1)
    t.R.Workshop.AuctionUI.Hide();Same(t.closed,1,"Escape uses normal native close")
    t.Restored();Same(H.Snapshot().visiting,false);Same(H.Control():IsShown(),false)
    t.Open();t.Flush();Same(H.Snapshot().state,"twichui","fresh visit auto opens under test opt-in")
    H.SetTestEnabled(false);t.Restored();Same(t.R.Workshop.AuctionUI.IsShown(),false)
    local reload=Setup();Same(reload.H.Snapshot().enabled,false);Same(reload.H.Snapshot().nativeConfirmed,false)
end

-- Bounded initialization, cancellation and callbacks from a previous visit.
do
    local t=Setup();t.Enable();t.c.AuctionHouseFrame=nil;t.H.Opened();t.Flush()
    Same(t.H.Snapshot().pending,1);Same(t.loads,0)
    local stale=t.timers[1]
    t.H.Ended();t.c.AuctionHouseFrame=t.f;t.H.Opened()
    local pending=t.H.Snapshot().pending;stale.fn()
    Same(t.H.Snapshot().pending,pending,"stale callback cannot detach new timer")
    Same(t.loads,0);t.Flush();Same(t.H.Snapshot().state,"twichui")
    local oldWatch=t.timer;t.H.ToBlizzard();t.H.SwitchToTwichUI()
    t.now=100;oldWatch.fn();Same(t.H.Snapshot().state,"twichui","old watchdog cannot touch next lease")
    t.H.Ended();t.Restored()
end
do
    local t=Setup();t.Enable();t.c.AuctionHouseFrame=nil;t.H.Opened()
    for i=1,25 do t.Flush() end
    Same(t.H.Snapshot().pending,0);Same(t.H.Snapshot().state,"recovery")
    Same(t.loads,0);Same(t.nativeMutations or 0,0)
    t.H.Ended();t.c.AuctionHouseFrame=t.f;t.H.Opened();t.H.Ended();t.Flush()
    Same(t.loads,0,"close before initialization never loads")
end
for _,kind in ipairs({"missing-launcher","missing-dependency","load-false","load-throw","build-false","build-throw","show-false","show-throw","recovery-hidden","late-combat","late-owner","close-loading","close-building","close-showing"}) do
    local t=Setup();local H,R=t.H,t.R;t.Enable()
    if kind=="missing-launcher" then R.WorkshopLauncher=nil
    elseif kind=="missing-dependency" then R.WorkshopLauncher.LoadAuctionUI=function() return false,"DEP_MISSING" end
    elseif kind=="load-false" then R.WorkshopLauncher.LoadAuctionUI=function() return false,"MISSING" end
    elseif kind=="load-throw" then R.WorkshopLauncher.LoadAuctionUI=function() error("load") end
    elseif kind=="build-false" then R.Workshop.AuctionUI.Prepare=function() return false end
    elseif kind=="build-throw" then R.Workshop.AuctionUI.Prepare=function() error("build") end
    elseif kind=="show-false" then R.Workshop.AuctionUI.ShowIntegrated=function() return false end
    elseif kind=="show-throw" then R.Workshop.AuctionUI.ShowIntegrated=function() error("show") end
    elseif kind=="recovery-hidden" then
        local create=t.c.CreateFrame;t.c.CreateFrame=function(...) local f=create(...);f.Show=function() end;return f end
    elseif kind=="late-combat" then R.Workshop.AuctionUI.Prepare=function() t.combat=true;return true end
    elseif kind=="late-owner" then R.Workshop.AuctionUI.Prepare=function() t.c.LOADED.Auctionator=true;return true end
    elseif kind=="close-loading" then R.WorkshopLauncher.LoadAuctionUI=function() H.Ended();return true end
    elseif kind=="close-building" then R.Workshop.AuctionUI.Prepare=function() H.Ended();return true end
    elseif kind=="close-showing" then R.Workshop.AuctionUI.ShowIntegrated=function() H.Ended();return true end end
    H.Opened();t.Flush()
    Same(H.Snapshot().state,"blizzard",kind)
    Same(H.Snapshot().leased,false,kind);Same(H.Snapshot().pending,0)
    Same(t.R.Workshop.AuctionUI.IsShown(),false)
    Same(select(4,t.f:GetPoint(1)),27,"fallback anchors: "..kind)
    if kind~="show-false" and kind~="show-throw" and kind~="close-showing" then Same(t.nativeMutations or 0,0,"preflight before native geometry: "..kind) end
end

for _,event in ipairs({"AUCTION_HOUSE_CLOSED","AUCTION_HOUSE_DISABLED","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT","UI_SCALE_CHANGED","DISPLAY_SIZE_CHANGED","ADDON_LOADED"}) do
    local t=Setup();t.Start();t.c.FireEvent(event);t.Restored()
    Same(t.R.Workshop.AuctionUI.IsShown(),false,event)
    Same(t.H.Snapshot().pending,0,event)
end
do
    local t=Setup();t.Start();Same(t.H.Control():IsVisible(),false,"healthy integration hides the duplicate control")
    t.Tick();Same(t.H.Snapshot().state,"twichui","the header provides the normal return action")
    t.H.ToBlizzard();t.Restored();Same(t.H.Control():IsVisible(),true,"native view retains the return action")
end
for _,foreign in ipairs({"anchors","parent","scale","addon","focus","native-hidden","busy"}) do
    local t=Setup();t.Start()
    if foreign=="anchors" then t.f.points={{"CENTER",t.c.UIParent,"CENTER",99,0}}
    elseif foreign=="parent" then t.f.parent=t.Frame(t.c.UIParent)
    elseif foreign=="scale" then t.f.scale=0.6
    elseif foreign=="addon" then t.c.LOADED.Auctionator=true
    elseif foreign=="focus" then t.Frame(t.f).focus=true
    elseif foreign=="native-hidden" then t.f:Hide()
    elseif foreign=="control-hidden" then t.H.Control():Hide()
    elseif foreign=="busy" then t.posting=true end
    t.Tick();Same(t.H.Snapshot().leased,false,foreign)
    Same(t.R.Workshop.AuctionUI.IsShown(),false,foreign)
    Same(select(4,t.f:GetPoint(1)),foreign=="anchors" and 99 or 27)
end
do
    local t=Setup();t.Start();local writes=t.mutations
    t.combat=true;t.c.FireEvent("PLAYER_REGEN_DISABLED")
    Same(t.H.Snapshot().state,"recovery");Same(t.mutations,writes)
    Same(t.R.Workshop.AuctionUI.IsShown(),true,"working custom UI remains visible until native can restore")
    t.H.Ended();t.combat=false;t.c.FireEvent("PLAYER_REGEN_ENABLED");t.Restored()
    Same(t.H.Snapshot().visiting,false,"combat exit cannot reopen closed UI")
end
do
    local t=Setup();t.Start();t.f.failPoint=true
    Same(t.H.ToBlizzard(),false);Same(t.H.Snapshot().state,"recovery")
    Same(t.H.Control():IsVisible(),true)
    Same(t.H.Snapshot().restoreFailed,1)
    t.H.Control():Click();t.Restored()
end
do
    local t=Setup();t.Start();t.combat=true
    Same(t.H.SetTestEnabled(false),false,"disable reports deferred restoration")
    Same(t.H.Snapshot().enabled,false,"deferred disable still disarms subsequent visits")
    t.combat=false;t.c.FireEvent("PLAYER_REGEN_ENABLED");t.Restored()
    t.H.Command("off");Same(t.H.Snapshot().enabled,false)
end

-- Detached native confirmations refuse takeover without dismissing them.
for _,kind in ipairs({"popup","progress","initialization-read-error","hide-error","partial-park"}) do
    local t=Setup();t.Enable()
    if kind=="popup" then t.c.StaticPopup_Visible=function(key) return key=="BUYOUT_AUCTION" end
    elseif kind=="progress" then t.c.AuctionHouseMultisellProgressFrame=t.Frame(t.c.UIParent)
    elseif kind=="initialization-read-error" then t.c.C_PlayerInteractionManager.IsValidNPCInteraction=function() error("read") end
    elseif kind=="partial-park" then t.f.failPoint=true end
    t.H.Opened();t.Flush()
    if kind=="hide-error" then
        Same(t.H.Snapshot().state,"twichui")
        t.R.Workshop.AuctionUI.Hide=function() error("hide") end
        Same(t.H.ToBlizzard(),true,"UI fault cannot strand native anchors")
    else Same(t.H.Snapshot().state,"blizzard",kind) end
    Same(t.H.Snapshot().leased,false,kind)
    Same(select(4,t.f:GetPoint(1)),27,kind)
end
do
    local t=Setup();t.Start();t.H.ToBlizzard();t.f:Hide()
    Same(t.H.Snapshot().visiting,false,"unexpected native hide ends restored visit")
    Same(t.H.Control():IsShown(),false,"no stale return overlay")
end
-- Cancellation alone is insufficient: callbacks must also reject a retained
-- recovery lease or a failing load from a previous visit.
do
    local t=Setup();t.Start();local oldWatch=t.timer
    t.combat=true;t.c.FireEvent("PLAYER_REGEN_DISABLED");t.H.Ended()
    t.available=true;t.f.shown=true;t.H.Opened();t.combat=false
    local writes=t.nativeMutations
    oldWatch.fn()
    Same(t.nativeMutations,writes,"old watchdog cannot restore during a new visit")
    Same(t.H.Snapshot().pending,1,"new visit retains its initialization timer")
    t.c.FireEvent("PLAYER_REGEN_ENABLED");t.Restored()
end
do
    local t=Setup();t.Enable()
    local load=t.R.WorkshopLauncher.LoadAuctionUI
    t.R.WorkshopLauncher.LoadAuctionUI=function()
        t.H.Ended();t.H.Opened();error("late old-visit load failure")
    end
    t.H.Opened();t.Flush()
    Same(t.H.Snapshot().pending,1,"old load error cannot cancel a new visit")
    Same(t.H.Snapshot().state,"preparing")
    t.R.WorkshopLauncher.LoadAuctionUI=load;t.Flush()
    Same(t.H.Snapshot().state,"twichui","new visit can finish normally")
    t.H.Ended();t.Restored()
end
print("PASSED: supervised integration "..count.." synthetic lifecycle assertions")
