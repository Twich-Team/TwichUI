-- AH-1b: an explicitly opened companion preview. No dependency on AuctionHost,
-- Blizzard frames, auctioneer interaction or transaction APIs. Nothing opens on load.
local R, W = TwichUI, TwichUI.Workshop
local UI = W.UI
local A = { pages = {}, views = {}, nav = {} }
W.AuctionUI = A
local root, active = nil, "browse"
local epoch, scheduled, renders = 0, false, 0
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
function A.IsShown() return root ~= nil and root:IsShown() end
function A.Page(key) return A.views[key] end
function A.Note(text) if root then root.note:SetText("Preview · Replacement off · " .. (text or "Transactions unavailable")) end end
function A.Schedule()
    if not A.IsShown() or scheduled then return end
    scheduled = true
    local mine = epoch
    C_Timer.After(0.15, function()
        if mine ~= epoch then return end
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
    if not A.IsShown() then return end
    local def, page = A.pages[active], A.views[active]
    if not (def and def.Render and page and page.built and not page.failed) then return end
    local function Draw() renders = renders + 1; def.Render(page) end
    local ok, err = pcall(function() R.Perf.Call("auction.previewRender", Draw) end)
    if not ok then
        Release(active, page)
        page.failed = true
        page:Hide()
        root.failure:SetText("This page could not be displayed. Close the preview and try again. Blizzard's Auction House is unchanged.")
        root.failure:Show()
        R.Fault("auction preview", err)
    end
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
        if not ok then R.Fault("auction preview build", err); return nil end
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
function A.Go(key)
    local found
    for _, d in ipairs(destinations) do if d[1] == key then found = d end end
    if not found then return false end
    if not root then active = key; return true end
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
    if page then A.Render() end
    return page ~= nil
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
    root.close = F.Close(header, function() root:Hide() end)
    root.close:SetSize(30, 30); CL.Control(root.close); root.close:SetPoint("RIGHT", -8, 0)
    root.blizzard = UI.Button(header, "Blizzard Auction House", 220, "secondary", function()
        root:Hide()
        R.Print("Auction House replacement is not enabled. Preview closed; Blizzard's Auction House is unchanged.")
    end, 32)
    root.blizzard:SetPoint("RIGHT", root.close, "LEFT", -10, 0)
    UI.Tip(root.blizzard, "Blizzard Auction House", "Replacement mode is not enabled. This closes only the preview. Visit an auctioneer normally to use Blizzard's window.")
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
    root.note:SetPoint("BOTTOMLEFT", 24, 18); root.note:SetPoint("RIGHT", -24, 0)
    root.note:SetText("Standalone preview  •  Replacement off  •  Transactions unavailable")
    root:SetScript("OnEvent", function() StopSizing(); R.FitToScreen(root); A.Schedule() end)
    root:HookScript("OnShow", function()
        epoch = epoch + 1; scheduled = false
        R.FitToScreen(root)
        for _, event in ipairs(events) do root:RegisterEvent(event) end
        A.Go(active)
    end)
    root:HookScript("OnHide", function()
        epoch = epoch + 1; scheduled = false; StopSizing(); root:UnregisterAllEvents()
        for key, page in pairs(A.views) do
            Release(key, page)
        end
    end)
    ResizeGrip()
    A.ready = true
    if UISpecialFrames then tinsert(UISpecialFrames, "TwichUIAuctionPreview") end
end
function A.Show(initialMode)
    if not W.Active() then return false, "EXPERIMENTAL_OFF" end
    if InCombatLockdown and InCombatLockdown() then return false, "COMBAT" end
    if not root then R.Perf.Call("auction.previewBuild", Build) end
    if not A.ready then return false, "INCOMPLETE" end
    active = initialMode == "market" and "market" or "browse"
    if root:IsShown() then A.Go(active) else root:Show() end
    return true
end
function A.Hide() if root then root:Hide() end end
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
    local out={ reads = W.AuctionReads and W.AuctionReads.Pending() or 0, liveResults = W.AuctionReads and W.AuctionReads.snapshot and #W.AuctionReads.snapshot.rows or 0, shown = A.IsShown() and 1 or 0, pages = pages, events = listeners, rows = rows, results = results, jobs = jobs, subscriptions = (W.Strategy.ListenerCount and W.Strategy.ListenerCount() or 0) + (W.Storage.ListenerCount and W.Storage.ListenerCount() or 0), renders = renders, sizing = root and root.sizing and 1 or 0 }
    for k,v in pairs(W.AuctionBrowseData and W.AuctionBrowseData.Stats() or {}) do out["catalog_"..k]=v end
    return out
end
