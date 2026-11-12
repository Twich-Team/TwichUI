-- TwichUI Workshop: the window
-- The shell in the settings window's crafted look (docs/settings-design-system.md, drawn through the core's CraftLook.lua, so the settings
-- addon is never loaded for it): a leather header with the TwichUI Workshop brand and the close box, a page list on the left, the page in a
-- recessed well, and a footer with where the prices come from and the last action's message. The pages are the views (ViewOverview,
-- ViewOpportunities, ViewCrafting, ViewShopping.lua): each builds once into its own frame and draws what Session.lua says. Opened with
-- /tui workshop, the TwichUI menu or the settings page; it never opens by itself. It opens on Overview the first time; the page shown is
-- kept only while the game runs. No position, size or page is saved.
--
-- While the window is shown it listens for the profession window's changes (TRADE_SKILL_*), for bag changes and for item
-- names arriving; a burst of events becomes one redraw of the page shown (never of the hidden ones). Hidden, it listens to nothing,
-- forgets the recipe lists it read and holds no rows of work (Watch.lua, not this window, remembers the professions opened while it is
-- hidden). The first thing shown after opening is read fresh, so readiness is never from before the window was closed.

local R = TwichUI
local W = R.Workshop
local S, Q = W.Session, W.Queue
local PR, SC, St, MK = W.Prices, W.Scan, W.Storage, W.Market
local UI = W.UI
local Win = {}
W.Window = Win

local NAME = "TwichUIWorkshop"
local WIDTH, HEIGHT = 1080, 700
local HEADER_H, FOOTER_H, NAV_W, PAD = 54, 38, 184, 14
local NAV_ROW, NAV_ICON = 42, 28
local PAGE_TOP, PAGE_BOTTOM = HEADER_H + 12, FOOTER_H + 13
local SETTLE = 0.2
-- The page list: the views registered themselves (UI.Register) in this order. Later destinations (Item Advisor, Market, Ledger) join as a
-- second group under the divider without changing the shell.
local NAV_GROUPS = { { "overview", "opps", "craft", "shop" } }

local L, K
local f               -- the window
local pages = {}      -- key -> the page's frame
local navItems = {}   -- key -> its row in the page list
local mode = "overview"
local fillToken = 0   -- changes whenever a pending batch of recipe reading should be forgotten
local token = 0       -- changes whenever a pending redraw should be forgotten
local scheduled = false
local dirtyRead = false
local dirtyMerchant = false
local renders, flushes = 0, 0

local EVENTS = {
    TRADE_SKILL_SHOW = "read", TRADE_SKILL_LIST_UPDATE = "read", TRADE_SKILL_DATA_SOURCE_CHANGED = "read",
    PLAYER_REGEN_ENABLED = "read",
    MERCHANT_SHOW = "merchant", MERCHANT_UPDATE = "merchant",
    BAG_UPDATE_DELAYED = "draw", GET_ITEM_INFO_RECEIVED = "draw",
    MODIFIER_STATE_CHANGED = "modifier",
    SKILL_LINES_CHANGED = "draw",
    AUCTION_HOUSE_SHOW = "draw", AUCTION_HOUSE_CLOSED = "draw", AUCTION_HOUSE_DISABLED = "draw",
}

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
-- The footer's first line: the prices the views use, in a few words
local function MarketLine()
    local src = S.PriceSource()
    local m = src.market
    if not m then
        return src.open and "No prices for this auction house yet" or "No auction house prices yet: scan them at the auction house"
    end
    local info = MK.Info({ market = m })
    local parts = { "Prices: " .. (src.label or "auction house") }
    local age = PR.Age(m.at)
    if age then parts[#parts + 1] = "scanned " .. PR.AgeText(age) .. (age > PR.OLD_AFTER and " (old)" or "") end
    if info and info.items then parts[#parts + 1] = ("%d %s"):format(info.items, UI.Plural(info.items, "item", "items")) end
    if info and info.scans and info.scans > 1 then parts[#parts + 1] = ("%d scan days of history"):format(info.scans) end
    return table.concat(parts, " \194\183 ")
end

function Win.Render()
    if not f or not f:IsShown() then return end
    local Perf = R.Perf
    local pt = Perf and Perf.on and Perf.Start("workshop.render")
    renders = renders + 1
    local def = UI.pages[mode]
    if def and def.Render then def.Render(pages[mode]) end
    f.market:SetText(MarketLine())
    f.note:SetText(S.Note() or (Q.Held() and "This queue was saved by a newer TwichUI and is read-only." or ""))
    if pt then Perf.Stop(pt) end
end
UI.Redraw = function() Win.Render() end

-- Reads the recipes' materials and output a batch at a time, so a long list doesn't hold up the game. It runs on every page but Crafting
-- after a profession is read, so what the window learned is complete (and kept: Session.FillSome saves it when the last batch is in); those
-- pages are drawn between batches.
local FILL_BATCH = 120
local function Prepare()
    fillToken = fillToken + 1
    local mine = fillToken
    local function Step()
        if mine ~= fillToken or not (f and f:IsShown()) then return end
        local left = S.FillSome(FILL_BATCH)
        if mode ~= "craft" then Win.Render() end
        if left > 0 then C_Timer.After(0, Step) end
    end
    Step()
end

local function PaintNav()
    for key, item in pairs(navItems) do
        local on = key == mode
        item.on = on
        item.sel:SetShown(on)
        UI.Paint(item.text, on and K.text or K.textDim)
    end
end

function Win.SetMode(m)
    if not UI.pages[m] then return end
    mode = m
    if not f then return end
    for key, page in pairs(pages) do page:SetShown(key == m) end
    PaintNav()
    if f:IsShown() then
        if m ~= "craft" then Prepare() end
        Win.Render()
    end
end
function Win.Mode() return mode end
UI.Go = function(m) Win.SetMode(m) end

local function Flush()
    scheduled = false
    if not (f and f:IsShown()) then return end
    flushes = flushes + 1
    if dirtyRead then
        dirtyRead = false
        R.Perf.Call("workshop.read", S.Observe)
        Prepare()
    end
    if dirtyMerchant then
        dirtyMerchant = false
        R.Perf.Call("workshop.read", S.ReadMerchant)
    end
    Win.Render()
end

local function Schedule(kind)
    if kind == "read" then dirtyRead = true end
    if kind == "merchant" then dirtyMerchant = true end
    if scheduled then return end
    scheduled = true
    local mine = token
    C_Timer.After(SETTLE, function()
        if mine ~= token then return end
        Flush()
    end)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
-- The leather of a band (header or footer): the dark and warm style-v2 tiles under the quiet header grain, as the settings window draws it
local function Band(frame)
    local CL = R.CraftLook
    CL.Tile(frame, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 })
    CL.Tile(frame, "BACKGROUND", -3, "warm", 0.04, { 0.70, 0.83, 0.96 })
    CL.QuietTile(frame, "header", "BACKGROUND", -2)
end

local function BuildShell()
    local F, CL = R.FrameLook, R.CraftLook
    local RL, RT, RR = F.RailInsets()
    f.shell = F.Shell(f, { below = true, follow = true })
    if f.shell.grain then f.shell.grain:Hide() end   -- the rock grain gives way to the leather
    CL.Tile(f.shell, "BACKGROUND", -4, "dark", 1, { 0.90, 0.94, 0.98 }):SetAllPoints(f.shell.interior)
    CL.QuietTile(f.shell, "outer", "BACKGROUND", -3):SetAllPoints(f.shell.interior)
    CL.LegacyRails(f.shell, false)
    f.frameArt = CL.Frame(f.shell)   -- the sculpted bronze frame of the settings window
    F.FadeIn(f)

    -- header: the brand, and the close box
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", RL, -RT)
    header:SetPoint("TOPRIGHT", -RR, -RT)
    header:SetHeight(HEADER_H - 4)
    Band(header)
    f.shell:Sheen():Place(header, 0, 0, 0, 0)
    f.shell:Groove():Place(header, "BOTTOM", 0, 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.header = header
    local crest = header:CreateTexture(nil, "ARTWORK")
    crest:SetSize(40, 40)
    crest:SetPoint("LEFT", 12, 0)
    crest:SetTexture(R.ICON)
    local brand = UI.Text(header, 25, K.text, "serif")
    brand:SetPoint("LEFT", crest, "RIGHT", 10, 1)
    brand:SetText("TwichUI")
    local title = UI.Text(header, 25, K.bronzeText, "serif")
    title:SetPoint("LEFT", brand, "RIGHT", 8, 0)
    title:SetText("Workshop")
    f.brand, f.title = brand, title
    f.close = F.Close(header, function() f:Hide() end)
    f.close:SetSize(28, 28)
    CL.Control(f.close)
    CL.Font(f.close.text, 16, true)
    f.close:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    UI.Tip(f.close, "Close", "Closes the Workshop. Your queue is saved; nothing else changes.")

    -- the page list
    local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
    nav:SetPoint("TOPLEFT", PAD, -PAGE_TOP)
    nav:SetPoint("BOTTOMLEFT", PAD, PAGE_BOTTOM)
    nav:SetWidth(NAV_W)
    L.Surface(nav, K.nav, 0.97, K.bronzeLo, 0.5)
    L.Recess(nav, 1.3)
    nav:SetBackdropColor(0.075, 0.060, 0.048, 1)
    nav:SetBackdropBorderColor(0, 0, 0, 0)
    CL.Tile(nav, "BACKGROUND", 1, "dark", 1, { 0.90, 0.94, 0.98 })
    CL.QuietTile(nav, "outer", "BACKGROUND", 2)
    local edge = CreateFrame("Frame", nil, nav, "BackdropTemplate")
    edge:SetAllPoints(nav)
    edge:SetBackdrop({ edgeFile = CL.FILE.control, edgeSize = 8 })
    edge:SetBackdropBorderColor(0.72, 0.60, 0.48, 0.55)
    -- a faint emblem at the foot of the list, under the pages (the mockups' watermark; it takes no mouse and says nothing)
    local mark = nav:CreateTexture(nil, "BORDER")
    mark:SetSize(84, 84)
    mark:SetPoint("BOTTOM", 0, 22)
    mark:SetTexture(R.ICON)
    mark:SetDesaturated(true)
    mark:SetVertexColor(0.80, 0.66, 0.46, 0.13)
    f.nav = nav

    -- the content well
    local well = CreateFrame("Frame", nil, f)
    well:SetPoint("TOPLEFT", nav, "TOPRIGHT", 12, 0)
    well:SetPoint("BOTTOMRIGHT", -PAD, PAGE_BOTTOM)
    CL.Slice(well, "recess", "BACKGROUND", 0)
    CL.QuietTile(well, "editor", "BACKGROUND", 3):SetAllPoints(well)
    f.well = well

    -- footer: where the prices come from, and the last action's message
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", PAD, 13)
    footer:SetPoint("BOTTOMRIGHT", -PAD, 13)
    footer:SetHeight(FOOTER_H - 12)
    Band(footer)
    local rule = UI.Rule(f, 0.6)
    rule:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 4)
    rule:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 4)
    f.market = UI.Text(footer, 13, K.textDim)
    f.market:SetPoint("LEFT", 10, 0)
    f.market:SetWidth(470)
    f.note = UI.Text(footer, 13, K.bronzeText)
    f.note:SetPoint("RIGHT", -10, 0)
    f.note:SetPoint("LEFT", f.market, "RIGHT", 16, 0)
    f.note:SetJustifyH("RIGHT")
    f.footer = footer
end

local function BuildNav()
    local y = -8
    for g, group in ipairs(NAV_GROUPS) do
        if g > 1 then
            local rule = UI.Rule(f.nav, 0.35)
            rule:SetPoint("TOPLEFT", 12, y - 6)
            rule:SetPoint("TOPRIGHT", -12, y - 6)
            y = y - 14
        end
        for _, key in ipairs(group) do
            local def = UI.pages[key]
            if def then
                local item = CreateFrame("Button", nil, f.nav)
                item:SetHeight(NAV_ROW)
                item:SetPoint("TOPLEFT", 6, y)
                item:SetPoint("TOPRIGHT", -6, y)
                R.CraftLook.NavItem(item)
                item.icon = item:CreateTexture(nil, "ARTWORK")
                item.icon:SetSize(NAV_ICON, NAV_ICON)
                item.icon:SetPoint("LEFT", 12, 0)
                UI.Art(item.icon, def.icon, NAV_ICON)
                item.text = UI.Text(item, 15, K.textDim)
                item.text:SetPoint("LEFT", 12 + NAV_ICON + 10, 0)
                item.text:SetPoint("RIGHT", -6, 0)
                item.text:SetText(def.nav)
                item.mode = key
                item:SetScript("OnEnter", function(self)
                    self.hover:SetAlpha(self.on and 0 or 0.55)
                    if def.tip then
                        UI.ShowTip(self, def.nav, def.tip)
                    end
                end)
                item:SetScript("OnLeave", function(self) self.hover:SetAlpha(0); if GameTooltip then GameTooltip:Hide() end end)
                item:SetScript("OnClick", function(self) Win.SetMode(self.mode) end)
                function item:SetOn(on) self.on = on and true or false end
                navItems[key] = item
                y = y - NAV_ROW - 4
            end
        end
    end
    -- the names the tests and the simulator scenario use
    f.tabOverview, f.tabOpps, f.tabCraft, f.tabShop = navItems.overview, navItems.opps, navItems.craft, navItems.shop
end

function UI.ShowTip(owner, title, body)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 0.82, 0)
    GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function BuildPages()
    for _, def in ipairs(UI.order) do
        local page = CreateFrame("Frame", nil, f.well)
        page:SetPoint("TOPLEFT", 18, -14)
        page:SetPoint("BOTTOMRIGHT", -18, 14)
        page.heading = UI.Text(page, 32, K.text, "serif")
        page.heading:SetPoint("TOPLEFT", 0, 0)
        page.heading:SetText(def.title)
        page.sub = UI.Text(page, 14, K.textDim)
        page.sub:SetPoint("TOPLEFT", 1, -38)
        page.sub:SetText(def.sub or "")
        page:Hide()
        pages[def.key] = page
        def.Build(page, f)
    end
end

local function Build()
    UI.Init()
    L, K = R.Look, R.Look.pal
    f = CreateFrame("Frame", NAME, UIParent)
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")   -- without an anchor the frame is "shown" but never drawn (the window was invisible)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnEvent", function(_, event)
        local kind = EVENTS[event]
        if kind == "modifier" then
            local row = UI.hoverRow
            if row and row:IsShown() then row:ShowTip() end   -- Shift pressed or released while over a row: the other tooltip
        elseif kind then
            Schedule(kind)
        end
    end)
    f:HookScript("OnShow", function(self)
        token = token + 1
        scheduled, dirtyRead, dirtyMerchant = false, false, false
        R.FitToScreen(self)
        for event in pairs(EVENTS) do self:RegisterEvent(event) end
        R.Perf.Call("workshop.read", S.Observe)   -- fresh before anything is shown as ready
        R.Perf.Call("workshop.read", S.ReadMerchant)   -- a merchant window already open is read too (nothing happens when none is)
        Win.Render()
        Prepare()
    end)
    f:HookScript("OnHide", function(self)
        token = token + 1
        fillToken = fillToken + 1
        scheduled, dirtyRead, dirtyMerchant = false, false, false
        self:UnregisterAllEvents()
        UI.hoverRow = nil
        for _, def in ipairs(UI.order) do if def.Reset then def.Reset() end end
        S.Reset()
        Q.Unload()
    end)
    BuildShell()
    BuildPages()
    BuildNav()
    for key, page in pairs(pages) do page:SetShown(key == mode) end
    PaintNav()
    SC.OnChange = function() if f and f:IsShown() then Schedule("draw") end end
    St.OnChange = function() if f and f:IsShown() then Schedule("draw") end end   -- the bank or guild bank was seen, or the choice changed
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it (never the game menu's handler list)
    return f
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
function Win.Show()
    if not f then Build() end
    f:Show()
end
function Win.Hide() if f then f:Hide() end end
function Win.Toggle()
    if f and f:IsShown() then f:Hide() else Win.Show() end
end
function Win.IsShown() return f ~= nil and f:IsShown() end
function Win.Frame() return f end
function Win.Lists() return UI.lists end
function Win.Page(key) return pages[key] end
function Win.Shop() return pages.shop end      -- the Shopping view (for the tests)
function Win.Opps() return pages.opps end      -- the Opportunities view (for the tests)
function Win.Craft() return pages.craft end    -- the Crafting view (for the tests)
function Win.Overview() return pages.overview end
function Win.Heads() return UI.heads end       -- the sortable column headings of Opportunities (for the tests)

-- For the diagnostics gauges and the tests. Read only.
function W.Snapshot()
    local s = S.Snapshot()
    local events = 0
    if f and f:IsShown() then for _ in pairs(EVENTS) do events = events + 1 end end
    local rows = 0
    for _, l in pairs(UI.lists) do rows = rows + #l.rows end
    s.shown = f ~= nil and f:IsShown() or false
    s.built = f ~= nil
    s.events = events
    s.watchEvents = W.Watch and W.Watch.Events() or 0
    s.watchReads = W.Watch and W.Watch.reads or 0
    s.bankEvents = W.Bank and W.Bank.Events() or 0
    s.bankReads = W.Bank and (W.Bank.reads + W.Bank.guildReads) or 0
    s.storedItems = s.stored and (s.stored.bankItems + s.stored.guildItems) or 0
    s.rows = rows
    s.mode = mode
    s.renders = renders
    s.flushes = flushes
    return s
end

W.Open = Win.Show
W.Toggle = Win.Toggle
W.ready = true
