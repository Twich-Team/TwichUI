-- TwichUI Workshop: the compact companion (P2.1)
-- A small, movable panel for playing while the plan is followed: "Compact view" in the Workshop's header swaps the full window for it, and its
-- "Full view" button swaps back. Two modes in one panel (the choice is saved in Workshop preferences):
--   Travel  what is still to get, from the Shopping plan of the whole queue (Session.ShoppingPlan, the multilevel plan and its fallback): the
--           quantity, the source in words (Vendor, Auction, Craft, Collect) and, for a vendor seen to sell it, a map button (Session.ShowVendor:
--           the NPC collection's own "show on map" and the game's waypoint on it; no route). No market valuations.
--   Craft   the queue in its order: the next craft whose materials are all in the bags, how many crafts are left, which recipes are ready and
--           which still lack something, and a bar of how many of the queue's recipes are ready.
-- It reads; it never crafts, buys or moves anything, and it has no secure or protected control. While shown it listens to bag changes and item
-- names (a burst of events is one redraw, SETTLE seconds later; no OnUpdate) and redraws when a plan finishes; hidden, it listens to nothing.
-- Its mode is saved; its position remains session-only.

local R = TwichUI
local W = R.Workshop
local S, O, Q, K2 = W.Session, W.Observe, W.Queue, W.Stock
local UI = W.UI
local C = {}
W.Compact = C
UI.Compact = C

local NAME = "TwichUIWorkshopCompact"
local WIDTH, ROW_H, ROWS = 300, 30, 7
local HEAD_H, SUM_H = 34, 40
local HEIGHT = HEAD_H + SUM_H + ROWS * ROW_H + 22
local SETTLE = 0.3
local EVENTS = { "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }   -- (the bank and guild bank arrive through Storage.OnChange: Window.lua)

local K
local f
local mode = S.CompactMode()
local scheduled, token = false, 0
local bags = false   -- a settled bag change since the last redraw (Notice.lua looks at what became ready)
local stats = { renders = 0, flushes = 0, events = 0, longest = 0 }

local function Clock()
    if debugprofilestop then return debugprofilestop() end
    return os and os.clock and os.clock() * 1000 or 0
end

---------------------------------------------------------------------------
-- What each mode shows (pure: the tests read these)
---------------------------------------------------------------------------
-- Travel: one row per material still to get, in the Shopping page's order. { item, qty, word, full, kind, vendor (a seller place is known) }
function C.TravelRows(plan, ctx)
    local out = {}
    for _, r in ipairs(plan.rows or {}) do
        local word, k, full = UI.ShopKind(r)
        out[#out + 1] = { item = r.item, qty = r.qty, word = word, kind = k, full = full,
            vendor = k == "vendor" and ctx and ctx.sellers and ctx.sellers[r.item] ~= nil or false, recipe = S.MaterialRecipe(r) }
    end
    return out
end

-- Craft: the queue in order, each { entry, crafts, state ("ready" | "collect" | "short" | "unknown"), missing }, the next craft (the first one whose
-- materials are all in the bags, else nil), how many crafts are left, and how many of the recipes are ready
function C.CraftRows(entries, have, view)
    local out, next, left, ready = {}, nil, 0, 0
    for _, e in ipairs(entries or {}) do
        local mats
        if type(e.mats) == "table" then
            mats = {}
            for i, m in ipairs(e.mats) do mats[i] = { item = m.item, qty = m.qty * e.crafts } end
        end
        local st = K2.Craft(mats, have, view)
        local row = { entry = e, crafts = e.crafts, state = st.state, missing = st.missing }
        out[#out + 1] = row
        left = left + (e.crafts or 0)
        if st.state == "ready" then
            ready = ready + 1
            if not next then next = row end
        end
    end
    return out, next, left, ready
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local TONES = { vendor = "bronzeText", auction = "bronzeText", none = "stone", make = "tealHi", collect = "sage",
    ready = "sage", collect2 = "bronzeText", short = "textDim", unknown = "stone" }

local function MakeRow(parent)
    local row = CreateFrame("Button", nil, parent)
    UI.Hover(row, 5)
    row.iconFrame = UI.ItemIcon(row, 22)
    row.iconFrame:SetPoint("LEFT", 6, 0)
    row.icon = row.iconFrame.tex
    -- The row action is Map or Open (Travel: the seller or selected recipe), or Done (Craft: one manual credit).
    row.map = UI.Button(row, "Map", 48, "secondary", function(self)
        local d = row.data
        if not d then return end
        if d.done then S.MarkCrafted(d.done); C.Note(S.Note()); C.Render()
        elseif d.recipe then S.OpenRecipe(d.recipe); C.Note(S.Note())
        elseif d.item then S.ShowVendor(d.item); C.Note(S.Note()) end
    end, 20)
    row.map:SetPoint("RIGHT", -4, 0)
    UI.TipFn(row.map, nil, function()
        local d = row.data
        if d and d.done then return "Crafted one\nCount one craft of this recipe as done." end
        if d and d.recipe then return "Open recipe\nOpen the profession recipe selected by this plan." end
        return "Show vendor\nShow a known seller on the map and set a waypoint on it."
    end)
    row.word = UI.Text(row, 11, K.textDim)
    row.word:SetPoint("RIGHT", row.map, "LEFT", -6, 0)
    row.word:SetJustifyH("RIGHT")
    row.word:SetWidth(62)
    row.title = UI.Text(row, 12, K.text, "strong")
    row.title:SetPoint("LEFT", row.iconFrame, "RIGHT", 7, 0)
    row.title:SetPoint("RIGHT", row.word, "LEFT", -4, 0)
    row.TipEnter = function(self)
        local d = self.data
        if d then UI.ItemTipLines(self, d.item, d.lines, d.title) end
    end
    row.TipLeave = function() if GameTooltip then GameTooltip:Hide() end end
    row:SetScript("OnClick", function(self) local d = self.data if d and d.item then UI.LinkItem(d.item) end end)
    row:Follow(row.map)
    row.fill = function(self, d)
        self.data = d
        local _, icon = O.ItemFacts(d.item or 0)
        self.icon:SetTexture(icon or d.icon or UI.ICON_BLANK)
        self.title:SetText(d.title)
        self.word:SetText(d.word or "")
        self.word:SetWidth(math.min(90, math.ceil((self.word:GetStringWidth() or 0) + 4)))   -- the name gets every unit the word does not need
        UI.Paint(self.word, K[TONES[d.tone] or "textDim"])
        local act = d.vendor == true or d.done ~= nil or d.recipe ~= nil
        self.map:SetShown(act)
        if act then self.map.text:SetText(d.done and "Done" or (d.recipe and "Open" or "Map")) end
        self.word:ClearAllPoints()
        if act then self.word:SetPoint("RIGHT", self.map, "LEFT", -6, 0) else self.word:SetPoint("RIGHT", -8, 0) end
    end
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function Name(item) return UI.ItemName(item) end

local function RenderTravel()
    local plan, ctx, engine = S.ShoppingPlan()
    local rows = C.TravelRows(plan, ctx)
    local data, n = {}, { vendor = 0, auction = 0, make = 0, collect = 0, none = 0 }
    for _, r in ipairs(rows) do
        n[r.kind] = (n[r.kind] or 0) + 1
        data[#data + 1] = { item = r.item, title = r.qty .. " \195\151 " .. Name(r.item), word = r.word, tone = r.kind, vendor = r.vendor, recipe = r.recipe,
            lines = { { r.full } } }
    end
    local sum = ctx.summary
    local text
    if ctx.first then text = "Planning your list..."
    elseif sum and sum.state == "empty" then text = "Add recipes to the queue to build a list."
    elseif #rows == 0 then text = "Nothing to get: everything is in your bags."
    else
        local parts = {}
        local buy = n.vendor + n.auction + n.none
        if buy > 0 then parts[#parts + 1] = ("%d to buy"):format(buy) end
        if n.collect > 0 then parts[#parts + 1] = ("%d to collect"):format(n.collect) end
        if n.make > 0 then parts[#parts + 1] = ("%d to craft"):format(n.make) end
        text = ("%d %s still needed: %s"):format(#rows, #rows == 1 and "material" or "materials", table.concat(parts, ", "))
    end
    if engine == "planning" and not ctx.first then text = "Updating... " .. text end
    f.summary:SetText(text)
    f.bar:Hide(); f.barText:Hide()
    f.undo:Hide()
    f.list:SetData(data, nil)
    f.list.box:SetAlpha(engine == "planning" and 0.6 or 1)
end

local function RenderCraft()
    local view = S.Stock()
    local rows, nextRow, left, ready = C.CraftRows(Q.Entries(), O.BagCount, view)
    local data = {}
    local WORD = { ready = "Ready", collect = "Collect first", short = "Missing", unknown = "Open recipe" }
    for _, r in ipairs(rows) do
        local e = r.entry
        local word = r.state == "short" and ("Missing " .. r.missing) or WORD[r.state]
        data[#data + 1] = { item = e.outItem, icon = e.icon, title = e.crafts .. " \195\151 " .. e.name, word = word, done = e.id,
            tone = r.state == "collect" and "collect2" or r.state, lines = { { ("%d %s left"):format(e.crafts, e.crafts == 1 and "craft" or "crafts") } } }
    end
    local text
    if #rows == 0 then text = "Nothing queued."
    elseif nextRow then
        text = ("Next: craft %d \195\151 %s\n%d %s left in the plan"):format(nextRow.crafts, nextRow.entry.name, left, left == 1 and "craft" or "crafts")
    else
        text = ("No recipe has all its materials yet\n%d %s left in the plan"):format(left, left == 1 and "craft" or "crafts")
    end
    f.summary:SetText(text)
    if #rows > 0 then
        f.bar:SetFraction(ready / #rows)
        f.barText:SetText(("%d of %d ready"):format(ready, #rows))
        f.bar:Show(); f.barText:Show()
    else
        f.bar:Hide(); f.barText:Hide()
    end
    f.list:SetData(data, nil)
    f.list.box:SetAlpha(1)
    f.undo:SetShown(W.Progress ~= nil and W.Progress.CanUndo())
end

function C.Render()
    if not (f and f:IsShown()) then return end
    local t0 = Clock()
    stats.renders = stats.renders + 1
    f.travel:SetOn(mode == "travel"); f.craft:SetOn(mode == "craft")
    if mode == "craft" then RenderCraft() else RenderTravel() end
    f.note:SetText(f.noteText or "")
    local dt = Clock() - t0
    if dt > stats.longest then stats.longest = dt end
end

function C.Note(text)
    if not f then return end
    f.noteText = text
    f.note:SetText(text or "")
end

-- a burst of events (or finished plans) becomes one redraw, SETTLE seconds later
function C.Schedule()
    if not (f and f:IsShown()) or scheduled then return end
    scheduled = true
    local mine = token
    C_Timer.After(SETTLE, function()
        if mine ~= token then return end
        scheduled = false
        stats.flushes = stats.flushes + 1
        if bags then
            bags = false
            if W.Notice then W.Notice.BagsChanged() end
        end
        C.Render()
    end)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------
local function Build()
    K = UI.K
    f = CreateFrame("Frame", NAME, UIParent)
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("RIGHT", UIParent, "RIGHT", -60, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    if f.SetDontSavePosition then f:SetDontSavePosition(true) end
    UI.Panel(f, "card")
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT", 0, 0); head:SetPoint("TOPRIGHT", 0, 0)
    head:SetHeight(HEAD_H)
    head:EnableMouse(true)
    head:RegisterForDrag("LeftButton")
    head:SetScript("OnDragStart", function() f:StartMoving() end)
    head:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    f.head = head
    f.travel = UI.Segment(head, "Travel", 66, function() C.SetMode("travel") end)
    f.travel:SetPoint("LEFT", 8, 0)
    UI.Tip(f.travel, "Travel", "What you still need, and where to get it.")
    f.craft = UI.Segment(head, "Craft", 66, function() C.SetMode("craft") end)
    f.craft:SetPoint("LEFT", f.travel, "RIGHT", 4, 0)
    UI.Tip(f.craft, "Craft", "Your queue: what is ready to craft next.")
    f.close = UI.Button(head, "\195\151", 24, "secondary", function() C.Hide() end, 22)
    f.close:SetPoint("RIGHT", -8, 0)
    UI.Tip(f.close, "Close", "Close the compact view. Your plan is kept.")
    f.full = UI.Button(head, "Full view", 76, "secondary", function() C.ShowFull() end, 22)
    f.full:SetPoint("RIGHT", f.close, "LEFT", -4, 0)
    UI.Tip(f.full, "Full view", "Back to the full Workshop window.")
    local rule = UI.Rule(f, 0.5)
    rule:SetPoint("TOPLEFT", 8, -HEAD_H); rule:SetPoint("TOPRIGHT", -8, -HEAD_H)
    f.summary = UI.Text(f, 12, K.text, "strong")
    f.summary:SetPoint("TOPLEFT", 10, -HEAD_H - 6)
    f.summary:SetPoint("RIGHT", -10, 0)
    f.summary:SetWordWrap(true)
    f.summary:SetJustifyV("TOP")
    f.summary:SetHeight(30)
    f.bar = UI.Meter(f, WIDTH - 20 - 84, 8)
    f.bar:SetPoint("TOPLEFT", 10, -HEAD_H - SUM_H + 2)
    f.bar:Hide()
    f.barText = UI.Text(f, 11, K.textDim)
    f.barText:SetPoint("LEFT", f.bar, "RIGHT", 8, 0)
    f.barText:SetWidth(76)
    f.barText:SetJustifyH("RIGHT")
    f.barText:Hide()
    local list = UI.List(f, ROW_H, MakeRow, ROWS * ROW_H, "canvas")
    list.box:SetPoint("TOPLEFT", 6, -HEAD_H - SUM_H - 6)
    list.box:SetPoint("BOTTOMRIGHT", -6, 20)
    f.list = list
    UI.lists.compact = list
    f.undo = UI.Button(f, "Undo", 54, "secondary", function() S.UndoCrafted(); C.Note(S.Note()); C.Render() end, 18)
    f.undo:SetPoint("BOTTOMRIGHT", -8, 2)
    UI.Tip(f.undo, "Undo", "Take back your last Crafted one.")
    f.undo:Hide()
    f.note = UI.Text(f, 11, K.bronzeText)
    f.note:SetPoint("BOTTOMLEFT", 10, 5)
    f.note:SetPoint("RIGHT", f.undo, "LEFT", -6, 0)
    f:SetScript("OnEvent", function(_, event)
        stats.events = stats.events + 1
        if event == "BAG_UPDATE_DELAYED" then W.Strategy.Bump(); bags = true end   -- what is owned changed: plans are worked out again
        C.Schedule()
    end)
    f:HookScript("OnShow", function(self)
        token = token + 1
        scheduled = false
        R.FitToScreen(self)
        for _, e in ipairs(EVENTS) do self:RegisterEvent(e) end
        if W.Notice and not W.Notice.Stats().armed then W.Notice.Arm() end   -- what is ready now is remembered, never announced
        C.Render()
    end)
    f:HookScript("OnHide", function(self)
        token = token + 1
        scheduled = false
        self:UnregisterAllEvents()
        f.noteText = nil
        if not (W.Window and W.Window.IsShown()) then   -- nothing is held while neither view is shown
            if W.Notice then W.Notice.Disarm() end
            S.Reset(); Q.Unload()
        end
    end)
    if UISpecialFrames then tinsert(UISpecialFrames, NAME) end   -- Esc closes it, like the window
    return f
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------
function C.SetMode(m)
    if m ~= "travel" and m ~= "craft" then return false end
    local ok = S.SetCompactMode(m)
    if not ok then return false end
    mode = m
    C.Render()
    return true
end

function C.Mode() return mode end

-- The full window's "Compact view": the compact panel in its place (the window's page and the queue are kept)
function C.Show(m)
    if not W.Active() then return false end
    if m then mode = m end
    if not f then
        if not UI.K then return false end   -- the window builds the look first
        Build()
    end
    f:Show()
    if W.Window and W.Window.IsShown() then W.Window.Hide() end
    C.Render()
    return true
end

function C.ShowFull()
    if f then f:Hide() end
    if W.Window then W.Window.Show() end
end

function C.Hide() if f then f:Hide() end end
function C.IsShown() return f ~= nil and f:IsShown() end
function C.Frame() return f end
function C.Stats() return { renders = stats.renders, flushes = stats.flushes, events = stats.events, longest = stats.longest, shown = C.IsShown() } end
