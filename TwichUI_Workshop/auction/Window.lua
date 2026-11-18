-- One lazy five-page shell for standalone preview and Host-owned auctioneer mode.
-- Native geometry/session lifecycle belongs exclusively to AuctionHost.
local R, W = TwichUI, TwichUI.Workshop
local UI = W.UI
local A = { pages = {}, views = {}, nav = {} }
W.AuctionUI = A
local root, active = nil, "browse"
local context, hostVisit = "preview", nil
local epoch, scheduled, renders = 0, false, 0
local refreshTimer
local initialized, lastError
local function Fault(where, err)
    initialized = nil
    lastError = tostring(err):sub(1, 1000)
    if context == "auctioneer" and R.AuctionHost then R.AuctionHost.ReplacementFailed(hostVisit, where) end
    R.Fault(where, err)
end
local function StopRefresh()
    if refreshTimer then refreshTimer:Cancel(); refreshTimer = nil end
    scheduled = false
end
local destinations = {
    { "browse", "Browse", "diagOverview", "Browse Auctions" },
    { "shopping", "Shopping", "npc:reagent-pouch", "Shopping List" },
    { "sell", "Sell", "npc:gavel", "Sell Auctions" },
    { "owned", "My Auctions", "npc:leather-backpack", "My Auctions" },
    { "market", "Market", "diagOperations", "Market" },
}
local events = { "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }

function A.Register(key, def) A.pages[key] = def end
function A.Frame() return root end
function A.Mode() return active end
function A.Context() return context end
function A.Live() return context=="auctioneer" and R.AuctionHost and R.AuctionHost.DebugEnabled and R.AuctionHost.DebugEnabled() or false end
function A.IsShown() return root ~= nil and root:IsShown() end
function A.Page(key) return A.views[key] end
-- One passive indicator for the existing read/action controllers. The native
-- spinner animates only while visible; no polling, new timers or requests.
function A.UpdateBusy()
    if not root or not root.busy then return end
    local reads,actions=W.AuctionReads,W.AuctionActions
    local view=A.views[active]
    local waiting=actions and (actions.state=="waiting" or actions.state=="quoting")
    local text=reads and reads.Pending()>0 and "Loading auctions…"
        or waiting and "Waiting for Auction House…" or view and view.job and "Preparing results…"
    if not text and context=="auctioneer" and reads and reads.Available() and C_AuctionHouse
        and C_AuctionHouse.IsThrottledMessageSystemReady and not reads.Snapshot().throttle then
        text="Auction House busy…"
    end
    root.busy:SetShown(text~=nil and text~=false)
    root.busy.text:SetText(text or "")
end
function A.Note(text)
    if root then root.note:SetText((context == "auctioneer" and "TwichUI Auction House · " or "Preview · Replacement off · ") .. (text or "Transactions unavailable")) end
end
function A.Schedule()
    if not A.IsShown() or scheduled then return end
    scheduled = true
    local mine = epoch
    refreshTimer = C_Timer.NewTimer(0.15, function()
        if mine ~= epoch then return end
        refreshTimer = nil
        scheduled = false
        A.Render()
    end)
end
local function Release(key, page)
    local def = A.pages[key]
    if not (page and page.built and def and def.Release) then return end
    local ok, err = pcall(def.Release, page)
    if not ok then R.Fault("auction preview cleanup", err) end
end
function A.Render()
    if not A.IsShown() then return false end
    local def, page = A.pages[active], A.views[active]
    if page and page.failed then return false end
    local ok, err = pcall(function()
        if A.UpdateDebug then A.UpdateDebug() end
        if A.UpdateReview then A.UpdateReview() end
        local fresh = W.Bridge.Freshness()
        root.marketChip.tipLines = fresh.tip
        root.marketChip:Set(fresh.text..' · Reload…', nil, UI.K.textDim)
        if not (def and def.Render and page and page.built and not page.failed) then error("page-not-ready", 0) end
        R.Perf.Call("auction.previewRender", def.Render, page)
        A.UpdateBusy()
        renders = renders + 1
        page.rendered = epoch -- only a completed render counts
    end)
    if not ok then
        if page then Release(active, page); page.failed = true; page:Hide() end
        root.failure:SetText("This page could not be displayed. Close the window and try again.")
        root.failure:Show()
        Fault("auction page render", err)
    end
    return ok
end
local function Page(key)
    if A.views[key] then return A.views[key].built and A.views[key] or nil end
    local page = CreateFrame("Frame", nil, root.content)
    page:SetAllPoints()
    page:Hide()
    A.views[key] = page
    local def = A.pages[key]
    if def then
        local ok, err = pcall(function() R.Perf.Call("auction.previewPageBuild", def.Build, page) end)
        if not ok then Fault("auction preview build", err); return nil end
    else
        local text = UI.Text(page, 16, UI.K.textDim)
        text:SetPoint("TOPLEFT", 12, -12); text:SetPoint("RIGHT", -12, 0)
        text:SetWordWrap(true)
        text:SetText((key == "browse" or key == "shopping") and "This page is being prepared. No auction actions are available." or
            "Preview only. This page belongs to a later milestone and has no auction actions.")
        page.placeholder = text
    end
    page.built = true
    return page
end
local function Go(key)
    local found
    for _, d in ipairs(destinations) do if d[1] == key then found = d end end
    if not found then return false end
    if not root then active = key; return true end
    if active~=key and A.HideReview then A.HideReview() end
    for other, page in pairs(A.views) do
        if other ~= key and page:IsShown() then
            Release(other, page)
            page:Hide()
        end
    end
    active = key
    root.heading:SetText(found[4])
    root.sub:SetText(key == "browse" and "Search stored observations and compare prices and market history." or
        key == "shopping" and "Gather what your existing Workshop queue and crafting plan still need." or key == "sell" and "Prepare bag items and pricing. Posting remains disabled." or key == "owned" and "Review your listings. Cancel and repost remain unavailable." or "Inspect stored market history, listing prices and observation coverage.")
    root.failure:Hide()
    local page = Page(key)
    if page then page.failed = nil; page:Show()
    else
        root.failure:SetText("This page could not be built. Reload the UI before trying again. Blizzard's Auction House is unchanged.")
        root.failure:Show()
    end
    for k, button in pairs(A.nav) do
        button.on = k == key; button.sel:SetShown(button.on)
        UI.Paint(button.text, button.on and UI.K.text or UI.K.textDim)
    end
    if page then return A.Render() end
    if context == "auctioneer" then R.AuctionHost.ReplacementFailed(hostVisit, "page-build-failed") end
    return false
end
function A.Go(key)
    local ok, result = pcall(Go, key)
    if not ok then Fault("auction page navigation", result); return false end
    return result
end
local function Band(frame)
    local CL = R.CraftLook
    CL.Tile(frame, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 })
    CL.Tile(frame, "BACKGROUND", -3, "warm", 0.04, { 0.70, 0.83, 0.96 })
    CL.QuietTile(frame, "header", "BACKGROUND", -2)
end
-- Resize only this independent preview. Its minimum logical dimensions keep
-- the approved three-column layout usable; FitToScreen handles smaller screens.
function A.Resize(width, height)
    if not root or not W.Finite(width) or not W.Finite(height) then return false end
    R.Perf.Call("auction.previewResize", function()
        -- FitToScreen preserves at least 0.6 scale. Bound growth so that
        -- floor cannot push an enlarged window outside a narrow viewport.
        local maxW = math.max(1420, math.min(1920, math.floor((UIParent:GetWidth() - 48) / 0.6)))
        local maxH = math.max(880, math.min(1200, math.floor((UIParent:GetHeight() - 48) / 0.6)))
        root:SetSize(math.max(1420, math.min(maxW, math.floor(width + 0.5))),
            math.max(880, math.min(maxH, math.floor(height + 0.5))))
        R.FitToScreen(root)
        A.Schedule()
    end)
    return true
end
local function StopSizing()
    if root and root.resize then
        root.sizing = nil
        root.resize:SetScript("OnUpdate", nil)
    end
end
local function ResizeGrip()
    local grip = CreateFrame("Button", nil, root)
    root.resize = grip
    grip:SetSize(22,22); grip:SetPoint("BOTTOMRIGHT",-12,8)
    for x=0,2 do for y=0,2-x do
        local dot=UI.L.Solid(grip,"OVERLAY",UI.K.bronzeText,0.7)
        dot:SetSize(2,2);dot:SetPoint("BOTTOMRIGHT",-3-x*5,3+y*5)
    end end
    UI.Tip(grip,"Resize preview","Drag to resize. The approved layout keeps a minimum size and fits smaller screens by scaling.")
    grip:SetScript("OnMouseDown",function(_,button)
        if button~="LeftButton" then return end
        local scale=root:GetEffectiveScale()
        local x,y=GetCursorPosition()
        local left,top=root:GetLeft(),root:GetTop()
        if left and top then
            root:ClearAllPoints();root:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
        end
        root.sizing={x=x/scale,y=y/scale,w=root:GetWidth(),h=root:GetHeight(),since=0}
        grip:SetScript("OnUpdate",function(_,elapsed)
            if not root.sizing then return end
            if not IsMouseButtonDown("LeftButton") then StopSizing();return end
            local d=root.sizing
            d.since=d.since+elapsed
            if d.since<0.05 then return end
            d.since=0
            local px,py=GetCursorPosition()
            A.Resize(d.w+px/scale-d.x,d.h+d.y-py/scale)
        end)
    end)
    grip:SetScript("OnMouseUp",StopSizing)
end
local function Cleanup()
    local id = hostVisit
    context, hostVisit = "preview", nil
    epoch = epoch + 1; initialized = nil; StopRefresh(); StopSizing(); root:UnregisterAllEvents()
    for key, page in pairs(A.views) do
        Release(key, page)
    end
    if A.HideExtras then A.HideExtras() end
    if id and R.AuctionHost then R.AuctionHost.InterfaceHidden(id) end
end
local function Build()
    UI.Init()
    local CL, F, K = R.CraftLook, R.FrameLook, UI.K
    root = CreateFrame("Frame", "TwichUIAuctionPreview", UIParent)
    root:Hide(); root:SetSize(1420, 880); root:SetPoint("CENTER")
    root:SetFrameStrata("HIGH"); root:SetToplevel(true); root:EnableMouse(true)
    root:SetMovable(true); root:SetClampedToScreen(true)
    if root.SetDontSavePosition then root:SetDontSavePosition(true) end
    root.shell = F.Shell(root, { below = true, follow = true })
    if root.shell.grain then root.shell.grain:Hide() end
    CL.Tile(root.shell, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 }):SetAllPoints(root.shell.interior)
    CL.QuietTile(root.shell, "outer", "BACKGROUND", -3):SetAllPoints(root.shell.interior)
    CL.LegacyRails(root.shell, false); root.frameArt = CL.Frame(root.shell)
    local header = CreateFrame("Frame", nil, root)
    header:SetPoint("TOPLEFT", 10, -10); header:SetPoint("TOPRIGHT", -10, -10); header:SetHeight(56)
    Band(header); root.shell:Groove():Place(header, "BOTTOM", 0, 0, 0)
    header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() root:StartMoving() end)
    header:SetScript("OnDragStop", function() root:StopMovingOrSizing() end)
    local crest = header:CreateTexture(nil, "ARTWORK")
    crest:SetSize(44, 44); crest:SetPoint("LEFT", 10, 0); UI.Art(crest, "npc:balance-scales", 44)
    root.brand = UI.Text(header, 26, K.text, "serif")
    root.brand:SetPoint("LEFT", crest, "RIGHT", 10, 0); root.brand:SetText("TwichUI")
    root.title = UI.Text(header, 26, K.bronzeText, "serif")
    root.title:SetPoint("LEFT", root.brand, "RIGHT", 8, 0); root.title:SetText("Auction House")
    root.busy=CreateFrame("Frame",nil,header)
    root.busy:SetSize(240,28);root.busy:SetPoint("LEFT",root.title,"RIGHT",18,0);root.busy:EnableMouse(false)
    root.busy.spinner=CreateFrame("Frame",nil,root.busy,"SpinnerTemplate")
    root.busy.spinner:SetSize(22,22);root.busy.spinner:SetPoint("LEFT");root.busy.spinner:EnableMouse(false)
    root.busy.text=UI.Text(root.busy,13,K.bronzeText)
    root.busy.text:SetPoint("LEFT",root.busy.spinner,"RIGHT",8,0)
    root.busy:Hide()
    root.close = F.Close(header, function() root:Hide() end)
    root.close:SetSize(30, 30); CL.Control(root.close); root.close:SetPoint("RIGHT", -8, 0)
    root.blizzard = UI.Button(header, "Blizzard Auction House", 220, "secondary", function()
        if context == "auctioneer" then R.AuctionHost.ToBlizzard()
        else
            root:Hide()
            R.Print("Auction House replacement is not enabled. Preview closed; Blizzard's Auction House is unchanged.")
        end
    end, 32)
    root.blizzard:SetPoint("RIGHT", root.close, "LEFT", -10, 0)
    root.debug=UI.Button(header,"Debug",80,"secondary",function() if A.ToggleDebug then A.ToggleDebug() end end,28)
    root.debug:SetPoint("RIGHT",root.blizzard,"LEFT",-10,0);root.debug:Hide()
    UI.TipFn(root.blizzard, "Blizzard Auction House", function()
        return context == "auctioneer" and "Return to Blizzard's Auction House during this visit."
            or "Closes only the preview. Visit an auctioneer normally to use Blizzard's window."
    end)
    local nav = CreateFrame("Frame", nil, root)
    nav:SetPoint("TOPLEFT", 14, -78); nav:SetPoint("BOTTOMLEFT", 14, 42); nav:SetWidth(205)
    UI.Panel(nav, "espresso"); root.nav = nav
    for i, d in ipairs(destinations) do
        local key = d[1]
        local b = CreateFrame("Button", nil, nav)
        b:SetPoint("TOPLEFT", 6, -8 - (i - 1) * 56); b:SetPoint("TOPRIGHT", -6, -8 - (i - 1) * 56); b:SetHeight(48)
        CL.NavItem(b)
        b.art = b:CreateTexture(nil, "ARTWORK"); b.art:SetSize(30, 30); b.art:SetPoint("LEFT", 10, 0); UI.Art(b.art, d[3], 30)
        b.text = UI.Text(b, 18, K.text, "serif"); b.text:SetPoint("LEFT", 50, 0); b.text:SetPoint("RIGHT", -8, 0); b.text:SetText(d[2])
        b:SetScript("OnClick", function() A.Go(key) end)
        A.nav[key] = b
    end
    local mark = nav:CreateTexture(nil, "ARTWORK")
    mark:SetSize(154, 154); mark:SetPoint("BOTTOM", 0, 22); UI.Art(mark, "npc:balance-scales", 154); mark:SetAlpha(0.32)
    root.heading = UI.Text(root, 32, K.text, "serif")
    root.heading:SetPoint("TOPLEFT", 240, -80); root.heading:SetPoint("RIGHT", -24, 0)
    root.sub = UI.Text(root, 14, K.textDim)
    root.sub:SetPoint("TOPLEFT", 241, -120); root.sub:SetPoint("RIGHT", -24, 0)
    root.content = CreateFrame("Frame", nil, root)
    root.content:SetPoint("TOPLEFT", 238, -152); root.content:SetPoint("BOTTOMRIGHT", -20, 44)
    root.failure = UI.Text(root, 16, K.bronzeText)
    root.failure:SetPoint("TOPLEFT", root.content, "TOPLEFT", 14, -14); root.failure:SetPoint("RIGHT", root.content, "RIGHT", -14, 0)
    root.failure:SetWordWrap(true); root.failure:Hide()
    root.note = UI.Text(root, 12, K.textDim)
    root.marketChip=UI.Chip(root,260,22)
    root.marketChip.maxW=300
    root.marketChip:SetPoint('BOTTOMLEFT',24,12)
    UI.TipFn(root.marketChip,'Loaded Market server data',function() return table.concat(W.Bridge.Freshness().tip,'\n') end)
    root.marketChip:SetScript('OnMouseUp',function(_,button) if button=='LeftButton' then W.Bridge.RequestReload() end end)
    root.note:SetPoint("LEFT",root.marketChip,"RIGHT",12,0); root.note:SetPoint("RIGHT", -24, 0)
    root.note:SetText("Standalone preview  •  Replacement off  •  Transactions unavailable")
    root:SetScript("OnEvent", function()
        local ok, err = pcall(function() StopSizing(); R.FitToScreen(root); A.Schedule() end)
        if not ok then Fault("auction window layout", err) end
    end)
    root:HookScript("OnShow", function()
        epoch = epoch + 1; StopRefresh(); initialized = nil
        local ok, err = pcall(function()
            R.FitToScreen(root)
            for _, event in ipairs(events) do root:RegisterEvent(event) end
            if A.Go(active) then initialized = epoch end
        end)
        if not ok then Fault("auction window show", err) end
    end)
    root:HookScript("OnHide", Cleanup)
    ResizeGrip()
    A.ready = true
    if UISpecialFrames then tinsert(UISpecialFrames, "TwichUIAuctionPreview") end
end
-- Build hidden before Host leases any native geometry. No query or
-- Market load is required. Page objects remain pooled across switches/visits.
function A.Prepare()
    if not W.Active() then return false, "EXPERIMENTAL_OFF" end
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    if not root then R.Perf.Call("auction.previewBuild", Build) end
    if not A.ready then return false, "INCOMPLETE" end
    return Page("browse") ~= nil
end
function A.ShowIntegrated(id)
    local h = R.AuctionHost
    if not h or not h.IsCurrent(id) or h.Snapshot().state ~= "preparing" then return false end
    if A.IsShown() then A.Hide() end
    context, hostVisit = "auctioneer", id
    initialized, lastError = nil, nil
    active = "browse" -- switching never implicitly selects/loads an external Market
    A.Note("Live search available; transaction permissions are shown per action")
    root.debug:Show()
    -- Only our own root is positioned; foreign parent/ancestor state is never changed.
    if root:GetParent() ~= UIParent then return false end
    root:ClearAllPoints(); root:SetPoint("CENTER", UIParent, "CENTER")
    root:SetFrameStrata("HIGH"); root:Raise()
    root:Show()
    return context == "auctioneer" and A.Presentation().usable
end
-- Passive health check shared with Host's commit and watchdog. A Show callback
-- can be swallowed by the client: require its completion and a render receipt.
function A.Presentation()
    local h = R.AuctionHost
    local s = h and h.Presentation and h.Presentation(root, true) or { usable = false, why = "missing-host" }
    local page = A.views[active]
    s.initialized = initialized == epoch
    s.browse = A.views.browse and A.views.browse.built or false
    s.rendered = page and page.rendered == epoch or false
    s.error = lastError
    if not A.ready or not root or root:GetParent() ~= UIParent or s.strata ~= "HIGH" or not s.initialized or not s.rendered
        or not page or page.failed or not page:IsVisible() or page:GetAlpha() <= 0
        or not root.content:IsVisible() or root.content:GetAlpha() <= 0 or root.failure:IsShown() then
        s.usable, s.why = false, "render-incomplete"
    end
    return s
end
function A.Show(initialMode)
    if not W.Active() then return false, "EXPERIMENTAL_OFF" end
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    -- A preview request while integrated is already open must not detach Host.
    if context == "auctioneer" then return true end
    if not root then R.Perf.Call("auction.previewBuild", Build) end
    if not A.ready then return false, "INCOMPLETE" end
    context, hostVisit = "preview", nil
    root.debug:Hide()
    A.Note()
    active = initialMode == "market" and "market" or "browse"
    if root:IsShown() then A.Go(active) else root:Show() end
    return true
end
function A.Hide()
    if not root then return end
    if root:IsShown() then root:Hide() else Cleanup() end
end
function A.Snapshot()
    local pages, listeners, rows, results, jobs = 0, 0, 0, 0, 0
    for _ in pairs(A.views) do pages = pages + 1 end
    if A.IsShown() then listeners = #events end
    for _, p in pairs(A.views) do
        if p.list then rows = rows + #p.list.rows end
        results = results + #(p.rows or {})
        if p.job then jobs = jobs + 1 end
        if A.IsShown() and p.listening then listeners = listeners + (p.eventCount or 2) end
    end
    local out={ timers = refreshTimer and 1 or 0, reads = W.AuctionReads and W.AuctionReads.Pending() or 0, liveResults = W.AuctionReads and W.AuctionReads.snapshot and #W.AuctionReads.snapshot.rows or 0, shown = A.IsShown() and 1 or 0, pages = pages, events = listeners, rows = rows, results = results, jobs = jobs, subscriptions = (W.Strategy.ListenerCount and W.Strategy.ListenerCount() or 0) + (W.Storage.ListenerCount and W.Storage.ListenerCount() or 0), renders = renders, sizing = root and root.sizing and 1 or 0 }
    for k,v in pairs(W.AuctionBrowseData and W.AuctionBrowseData.Stats() or {}) do out["catalog_"..k]=v end
    return out
end
