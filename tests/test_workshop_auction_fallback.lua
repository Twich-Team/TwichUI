-- Real Host + real five-page shell. Geometry/native interaction are synthetic;
-- failures assert viewport usability, not merely calls to Show.
local function Setup()
    local c = dofile(TESTS .. "auction_mock.lua")
    local R, W = c.TwichUI, c.TwichUI.Workshop
    local H, A = R.AuctionHost, W.AuctionUI
    local t = { c=c, R=R, W=W, H=H, A=A, writes=0, faults={}, available=true }
    c.Enum.PlayerInteractionType = { Auctioneer=21 }
    c.C_PlayerInteractionManager = {
        IsInteractingWithNpcOfType=function() return t.available end,
        IsValidNPCInteraction=function() return t.available end,
    }
    c.AuctionHouseFrameDisplayMode = { Buy=1 }
    local f = c.CreateFrame("Frame", nil, c.UIParent)
    c.AuctionHouseFrame = f; t.native = f
    f.DialogOverlay=false;f.BuyDialog=false
    f:SetSize(800,500); f:SetPoint("TOPLEFT",c.UIParent,"TOPLEFT",27,-18); f:Show()
    f.GetNumPoints=function(s) return #s.points end
    f.GetPoint=function(s,i) return unpack(s.points[i],1,5) end
    f.GetDisplayMode=function() return 1 end
    f.IsProtected=function() return false end
    f.IsClampedToScreen=function() return false end
    f.GetLeft=function(s)
        local p=s.points[1]
        return p and (p[3]=="TOPRIGHT" and 1920+(p[4] or 0) or p[4] or 0)
    end
    f.GetRight=function(s) local l=s:GetLeft();return l and l+800 end
    local clear, point=f.ClearAllPoints,f.SetPoint
    f.ClearAllPoints=function(s) t.writes=t.writes+1;return clear(s) end
    f.SetPoint=function(s,...) t.writes=t.writes+1;return point(s,...) end
    R.WorkshopLauncher={Enabled=function() return true end,Load=function() end,LoadAuctionUI=function() return true end}
    R.Fault=function(where,err) t.faults[#t.faults+1]={where,tostring(err)} end
    c.HideUIPanel=function() error("fallback must preserve the auctioneer session") end
    assert(H.SetDebug(true));H.Opened()
    function t.Open() FlushTimers() end
    function t.Fallback()
        local s=H.Snapshot()
        assert(s.state=="blizzard" and not s.leased and s.pending==0, s.state..":"..s.reason)
        assert(H.Presentation(f).usable,"native fallback must be onscreen")
        assert(not A.IsShown() and A.Context()=="preview" and t.available,"failed opening preserves session and detaches context")
        assert(H.Control():IsVisible(),"independent recovery/switch action")
        local writes=t.writes
        H.Opened();c.FireEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW",21);FlushTimers()
        assert(t.writes==writes,"no automatic retry during failed visit")
    end
    return t
end

-- The former ShowIntegrated accepted a built page even when OnShow never
-- completed. Mimic the client's protected script boundary swallowing errors.
for _,kind in ipairs({"construction","onshow","missing-onshow","navigation","browse-build","browse-render","render-preamble",
    "scale","position","missing-parent","hidden-parent","viewport","parking","parking-commit","load","load-throw","load-event","close-loading"}) do
    local t=Setup();local A,H,c=t.A,t.H,t.c
    local prepare=A.Prepare
    if kind=="construction" then t.R.FrameLook.Shell=function() error("shell fixture") end
    elseif kind=="browse-build" then A.pages.browse.Build=function() error("Browse build fixture") end
    elseif kind=="browse-render" then A.pages.browse.Render=function() error("Browse render fixture") end
    elseif kind=="render-preamble" then A.UpdateDebug=function() error("render header fixture") end
    elseif kind=="load" then t.R.WorkshopLauncher.LoadAuctionUI=function() return false,"MISSING" end
    elseif kind=="load-throw" then t.R.WorkshopLauncher.LoadAuctionUI=function() error("load fixture") end
    elseif kind=="load-event" then t.R.WorkshopLauncher.LoadAuctionUI=function() c.FireEvent("ADDON_LOADED","TwichUI_Workshop");return true end
    elseif kind=="close-loading" then t.R.WorkshopLauncher.LoadAuctionUI=function() t.available=false;H.Ended();return true end
    elseif kind=="parking" then
        local point=t.native.SetPoint
        t.native.SetPoint=function(s,...)
            if select(3,...)=="TOPRIGHT" then error("parking fixture") end
            return point(s,...)
        end
    elseif kind=="parking-commit" then
        local point=t.native.SetPoint
        t.native.SetPoint=function(s,...) point(s,...);if select(3,...)=="TOPRIGHT" then A.Frame():SetAlpha(0) end end
    else
        A.Prepare=function()
            local ok=prepare();local f=A.Frame()
            if kind=="onshow" then
                t.R.FitToScreen=function() error("layout fixture") end
                local show=f.Show;f.Show=function(s) pcall(show,s) end
            elseif kind=="missing-onshow" then A.Page("browse"):Show();f.hooks.OnShow={} -- no receipt despite IsShown=true
            elseif kind=="navigation" then A.Go=function() error("navigation fixture") end
            elseif kind=="scale" then f.GetEffectiveScale=function() return 0/0 end
            elseif kind=="position" then f.GetLeft=function() return 10000 end;f.GetRight=function() return 11420 end
            elseif kind=="missing-parent" then f.parent=nil
            elseif kind=="hidden-parent" then local p=c.CreateFrame("Frame",nil,c.UIParent);p:Hide();f.parent=p
            elseif kind=="viewport" then c.UIParent.GetRight=function() return 0 end end
            return ok
        end
    end
    t.Open()
    if kind=="load-event" then
        assert(H.Snapshot().state=="twichui" and A.Presentation().usable,"Workshop ADDON_LOADED cannot cancel preflight")
        H.ToBlizzard()
    elseif kind=="viewport" then
        assert(H.Snapshot().state=="recovery" and H.Snapshot().opening.restoration=="native-unavailable",H.Snapshot().state..":"..tostring(H.Snapshot().opening.restoration)..":"..H.Snapshot().reason)
        assert(H.Control():IsShown(),"unknown viewport is a truthful recoverable state")
        c.UIParent.GetRight=function() return 1920 end;assert(H.Restore("viewport-recovered"));t.Fallback()
    elseif kind=="close-loading" then
        assert(not H.Snapshot().leased and H.Snapshot().pending==0 and t.writes==0)
    else
        t.Fallback()
        assert(H.Snapshot().failedVisit==H.Snapshot().visit,kind.." records failed visit")
        assert(H.Snapshot().opening.failure,kind.." retains actionable failure")
        local o=H.Snapshot().opening
        if kind=="load" or kind=="load-throw" then assert(o.load~="loaded",kind)
        elseif kind=="construction" or kind=="browse-build" then assert(o.build=="failed",kind)
        else assert(o.load=="loaded" and o.build=="built",kind.." reaches injected failure") end
        if kind~="parking" and kind~="parking-commit" then assert(t.writes==0,kind.." never parks native") end
    end
    H.Ended();A.Hide()
end

-- Healthy opening has a completed render and full physical bounds in viewport.
do
    local t=Setup();t.Open()
    local s=t.A.Presentation()
    assert(t.H.Snapshot().state=="twichui" and s.usable and s.initialized and s.rendered and s.browse)
    assert(s.bounds.left>=s.viewport.left and s.bounds.right<=s.viewport.right)
    assert(not t.H.Presentation(t.native).usable,"native parks only after rendered custom UI")
    -- A later render exception must restore, including exceptions before def.Render.
    t.A.UpdateReview=function() error("later render preamble") end
    t.A.Schedule();FlushTimers();t.Fallback()
    assert(#t.faults>0 and t.H.Snapshot().opening.custom.error)
    t.H.Ended()
end

-- The watchdog inspects physical visibility after a successful opening too.
for _,kind in ipairs({"alpha","parent","geometry","page-hidden","page-alpha","strata"}) do
    local t=Setup();t.Open();local f=t.A.Frame()
    if kind=="alpha" then f:SetAlpha(0)
    elseif kind=="parent" then local p=t.c.CreateFrame("Frame",nil,t.c.UIParent);p:Hide();f.parent=p
    elseif kind=="geometry" then f.GetRight=function() return nil end
    elseif kind=="page-hidden" then t.A.Page("browse"):Hide()
    elseif kind=="page-alpha" then t.A.Page("browse"):SetAlpha(0)
    elseif kind=="strata" then f:SetFrameStrata("BACKGROUND") end
    TICKERS[#TICKERS].fn();t.Fallback()
    assert(t.H.Snapshot().opening.watchdog=="replacement-unavailable")
    t.H.Ended()
end
-- SetPoint may silently refuse the write, rather than throwing.
do
    local t=Setup();t.Open();local point=t.native.SetPoint
    t.native.SetPoint=function() end
    assert(not t.H.ToBlizzard());assert(t.H.Snapshot().leased and t.H.Control():IsVisible())
    t.native.SetPoint=point;assert(t.H.Restore("retry"));t.Fallback();t.H.Ended()
end

-- Ownership mismatch must retain recovery without overwriting foreign anchors.
for _,partial in ipairs({false,true}) do
    local t=Setup();t.Open()
    if partial then
        local point=t.native.SetPoint
        t.native.SetPoint=function() error("restore fixture") end
        assert(not t.H.ToBlizzard());t.native.SetPoint=point
    end
    t.native.points={{"TOPLEFT",t.c.UIParent,"TOPRIGHT",5000,0}}
    local writes=t.writes
    assert(not t.H.Restore("foreign-offscreen"))
    local s=t.H.Snapshot()
    assert(s.state=="recovery" and s.leased and s.reason=="restore-blocked-owner")
    assert(t.writes==writes and t.H.Control():IsVisible(),"preserve foreign ownership and recovery action")
    assert(t.A.Presentation().usable,"keep the working replacement visible during blocked recovery")
    assert(not s.nativeUsable and s.opening.restoration~="visible")
    t.H.Control():Click();assert(t.H.Snapshot().leased and t.writes==writes,"retry cannot seize foreign anchors")
    t.native.points={{"TOPLEFT",t.c.UIParent,"TOPLEFT",27,-18}}
    assert(t.H.Restore("foreign-returned"));assert(not t.H.Snapshot().leased)
    assert(t.H.Snapshot().opening.restoration=="foreign-visible")
    t.H.Ended()
end
print("PASSED: actual shell empty-screen failures, render receipts, viewport fallback and foreign-anchor recovery")
