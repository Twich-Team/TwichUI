-- TwichUI Workshop: the window
-- Recipes on the left (the player's own open profession, with a search), the queue on the right, and under it the combined
-- materials against the bags. It draws what Session.lua says and asks it to do everything else. Drawn with the shared framed look
-- (FrameLook.lua). Opened with /tui workshop, the TwichUI menu or the settings page; it never opens by itself.
--
-- While the window is shown it listens for the profession window's changes (TRADE_SKILL_*), for bag changes and for item
-- names arriving; a burst of events becomes one redraw. Hidden, it listens to nothing, forgets the recipe lists it read and holds
-- no rows of work. The first thing shown after opening is read fresh, so readiness is never from before the window was closed.
-- Colour is always beside a word (Orange/Yellow/Green/Grey, "Still needed", "Unknown").

local R = TwichUI
local W = R.Workshop
local S, Q, O = W.Session, W.Queue, W.Observe
local Win = {}
W.Window = Win

local NAME = "TwichUIWorkshop"
local WIDTH, HEIGHT = 800, 620
local PAD = 16
local LEFT_W = 312
local RIGHT_X = PAD + LEFT_W + 16
local RIGHT_W = WIDTH - RIGHT_X - PAD
local SETTLE = 0.2
local REC_H, QUE_H, MAT_H = 40, 58, 22

local L, K            -- Look and its palette, looked up when first built
local f               -- the window
local lists = {}      -- recipes, queue, materials
local chips = {}
local token = 0       -- changes whenever a pending redraw should be forgotten
local scheduled = false
local dirtyRead = false
local renders, flushes = 0, 0

local function Tip(frame, title, body) R.Interact.Tip(frame, title, body) end
local function Paint(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end
local function Num(n) return tostring(n) end

local EVENTS = {
    TRADE_SKILL_SHOW = "read", TRADE_SKILL_LIST_UPDATE = "read", TRADE_SKILL_DATA_SOURCE_CHANGED = "read",
    PLAYER_REGEN_ENABLED = "read",
    BAG_UPDATE_DELAYED = "draw", GET_ITEM_INFO_RECEIVED = "draw",
}

---------------------------------------------------------------------------
-- A scrolling list that makes only the rows it can show
---------------------------------------------------------------------------
local function NewList(parent, x, y, w, h, rowH, make)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT", x, y)
    box:SetSize(w, h)
    L.Well(box, 0.9)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -22, 4)
    L.ScrollBar(sf)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(w - 30, 1)
    sf:SetScrollChild(content)
    local list = { box = box, scroll = sf, content = content, rows = {}, data = {}, rowH = rowH }
    list.empty = L.Text(box, "small")
    list.empty:SetPoint("TOPLEFT", 12, -12)
    list.empty:SetWidth(w - 40)
    list.empty:SetWordWrap(true)
    function list:Layout()
        local data, rows = self.data, self.rows
        content:SetHeight(math.max(#data * rowH, 1))
        local first = math.floor((sf:GetVerticalScroll() or 0) / rowH)
        local count = math.ceil((h - 8) / rowH) + 1
        for i = 1, count do
            local idx = first + i
            local row = rows[i]
            if idx <= #data then
                if not row then
                    row = make(content)
                    row:SetHeight(rowH)
                    rows[i] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(idx - 1) * rowH)
                row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(idx - 1) * rowH)
                row:Show()
                row.fill(row, data[idx], idx)
            elseif row then
                row:Hide()
            end
        end
        for i = count + 1, #rows do rows[i]:Hide() end
    end
    sf:HookScript("OnVerticalScroll", function() list:Layout() end)
    function list:SetData(d, emptyText)
        self.data = d
        self.empty:SetText(emptyText or "")
        self.empty:SetShown(#d == 0 and emptyText ~= nil)
        self:Layout()
    end
    function list:ScrollTop() sf:SetVerticalScroll(0) end
    function list:RowCount() local n = 0 for _, r in ipairs(self.rows) do if r:IsShown() then n = n + 1 end end return n end
    return list
end

local function Icon(row, size)
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    return t
end

local ICON_BLANK = 134400   -- the game's question-mark icon, for a recipe or item whose icon isn't known yet

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function MakeRecipeRow(parent)
    local F = R.FrameLook
    local row = CreateFrame("Frame", nil, parent)
    row.icon = Icon(row, 30)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = L.Text(row, "body")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetWidth(LEFT_W - 30 - 4 - 8 - 80 - 24)
    row.name:SetWordWrap(false)
    row.diff = L.Text(row, "small")
    row.diff:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.sub = L.Text(row, "meta")
    row.sub:SetPoint("LEFT", row.diff, "RIGHT", 6, 0)
    row.add = F.Button(row, "Add", 62, "secondary", function()
        local rec = row.rec
        if rec then S.Add(rec); Win.Render() end
    end)
    row.add:SetHeight(22)
    row.add:SetPoint("RIGHT", -2, 0)
    Tip(row.add, "Add to queue", "Puts this recipe in the queue to make once. Change how many in the queue.")
    row.fill = function(self, rec)
        self.rec = rec
        O.Fill(rec)
        self.icon:SetTexture(rec.icon or ICON_BLANK)
        self.name:SetText(rec.name)
        local d = W.DIFFICULTY[rec.diff]
        if d then
            self.diff:SetText(d.word)
            Paint(self.diff, d.color)
        else
            self.diff:SetText("")
        end
        local per = W.PerCraft(rec.outMin, rec.outMax)
        self.sub:SetText(per and ("Makes " .. per) or "Makes: unknown")
        if S.IsQueued(rec.id) then
            self.add.text:SetText("Queued")
            self.add:SetEnabled(false)
        else
            self.add.text:SetText("Add")
            self.add:SetEnabled(true)
        end
    end
    return row
end

local function QueueLine(r)
    local e = r.entry
    local crafts = e.crafts == 1 and "1 craft" or (e.crafts .. " crafts")
    if not r.perCraft then return crafts .. " - what it makes isn't known yet" end
    if e.crafts == 1 then return crafts .. " - makes " .. r.perCraft end
    return crafts .. " - makes " .. r.perCraft .. " each, " .. r.expected .. " in all"
end

local function MakeQueueRow(parent)
    local F = R.FrameLook
    local row = CreateFrame("Frame", nil, parent)
    row.icon = Icon(row, 36)
    row.icon:SetPoint("TOPLEFT", 2, -6)
    row.name = L.Text(row, "body")
    row.name:SetPoint("TOPLEFT", 46, -5)
    row.name:SetWidth(RIGHT_W - 30 - 46 - 74)
    row.name:SetWordWrap(false)
    row.line = L.Text(row, "small")
    row.line:SetPoint("TOPLEFT", 46, -23)
    row.line:SetWidth(RIGHT_W - 30 - 50)
    row.line:SetWordWrap(false)
    row.stale = L.Text(row, "small")
    row.stale:SetPoint("BOTTOMLEFT", 46, 5)
    row.stale:SetText("Open profession to update.")
    Paint(row.stale, K.gold)
    row.remove = F.Button(row, "Remove", 62, "secondary", function()
        if row.id then S.Remove(row.id); Win.Render() end
    end)
    row.remove:SetHeight(20)
    row.remove:SetPoint("TOPRIGHT", -2, -3)
    Tip(row.remove, "Remove", "Takes this recipe out of the queue. Nothing else changes.")
    row.more = F.Button(row, "+", 22, "secondary", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and 5 or 1); Win.Render() end
    end)
    row.more:SetHeight(20)
    row.more:SetPoint("BOTTOMRIGHT", -2, 3)
    Tip(row.more, "Make more", "One more craft. Hold Shift for five.")
    row.count = L.Text(row, "body")
    row.count:SetWidth(34)
    row.count:SetJustifyH("CENTER")
    row.count:SetPoint("RIGHT", row.more, "LEFT", -2, 0)
    row.less = F.Button(row, "-", 22, "secondary", function()
        if row.id then S.Change(row.id, IsShiftKeyDown and IsShiftKeyDown() and -5 or -1); Win.Render() end
    end)
    row.less:SetHeight(20)
    row.less:SetPoint("RIGHT", row.count, "LEFT", -2, 0)
    Tip(row.less, "Make fewer", "One craft fewer, down to one. Hold Shift for five. Remove takes the recipe out.")
    row.open = F.Button(row, "Open recipe", 86, "secondary", function()
        if row.id then S.OpenRecipe(row.id); Win.Render() end
    end)
    row.open:SetHeight(20)
    row.open:SetPoint("RIGHT", row.less, "LEFT", -8, 0)
    Tip(row.open, "Open recipe", "Shows this recipe in the game's profession window. It makes nothing.")
    row.fill = function(self, r)
        local e = r.entry
        self.id = e.id
        self.icon:SetTexture(e.icon or ICON_BLANK)
        local label = e.name
        if e.profName then label = label .. "  (" .. e.profName .. ")" end
        self.name:SetText(label)
        self.line:SetText(QueueLine(r))
        self.count:SetText(Num(e.crafts))
        self.stale:SetShown(r.unresolved)
        self.less:SetEnabled(e.crafts > 1)
        self.more:SetEnabled(e.crafts < W.MAX_CRAFTS)
    end
    return row
end

local function MakeMaterialRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row.icon = Icon(row, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.name = L.Text(row, "body")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(RIGHT_W - 30 - 4 - 18 - 6 - 62 - 62 - 88)
    row.name:SetWordWrap(false)
    row.short = L.Text(row, "body")
    row.short:SetPoint("RIGHT", -6, 0)
    row.short:SetWidth(78)
    row.short:SetJustifyH("RIGHT")
    row.have = L.Text(row, "body")
    row.have:SetPoint("RIGHT", row.short, "LEFT", -10, 0)
    row.have:SetWidth(52)
    row.have:SetJustifyH("RIGHT")
    row.need = L.Text(row, "body")
    row.need:SetPoint("RIGHT", row.have, "LEFT", -10, 0)
    row.need:SetWidth(52)
    row.need:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", function(self)
        if GameTooltip and self.item then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if not pcall(GameTooltip.SetItemByID, GameTooltip, self.item) then GameTooltip:Hide() end
        end
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    row.fill = function(self, m)
        self.item = m.item
        local name, icon = O.ItemFacts(m.item)
        self.icon:SetTexture(icon or ICON_BLANK)
        self.name:SetText(name or ("Item " .. m.item))
        self.need:SetText(Num(m.need))
        if m.have == nil then
            self.have:SetText("Unknown")
            self.short:SetText("Unknown")
            Paint(self.short, K.stone)
        else
            self.have:SetText(Num(m.have))
            self.short:SetText(Num(m.short))
            Paint(self.short, m.short > 0 and K.gold or K.sage)
        end
    end
    return row
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function LayoutChips(list)
    local n = #list
    for i = 1, math.max(n, #chips) do
        local b = chips[i]
        local p = list[i]
        if p then
            if not b then
                b = R.FrameLook.Toggle(f, "", 80, function(self)
                    if self.profId then S.Select(self.profId); lists.recipes:ScrollTop(); Win.Render() end
                end)
                b:SetHeight(22)
                chips[i] = b
            end
            local w = math.max(56, math.min(110, math.floor((LEFT_W - 4 * (n - 1)) / n)))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (w + 4), -72)
            b.profId = p.id
            b.text:SetText(p.name)
            b:SetOn(p.selected)
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

function Win.Render()
    if not f or not f:IsShown() then return end
    local Perf = R.Perf
    local pt = Perf and Perf.on and Perf.Start("workshop.render")
    renders = renders + 1

    -- recipes
    LayoutChips(S.Professions())
    local notices = S.Notices()
    f.notice:SetText(table.concat(notices, "\n"))
    local rows = S.Browse()
    local emptyText
    if #rows == 0 then
        if not S.Current() then emptyText = "No recipes yet."
        elseif S.filter ~= "" then emptyText = "No recipe matches your search."
        else emptyText = "This profession has no recipes to show." end
    end
    lists.recipes:SetData(rows, emptyText)

    -- queue
    local queue = S.QueueRows()
    f.queueCount:SetText(("%d of %d"):format(#queue, W.MAX_QUEUE))
    lists.queue:SetData(queue, "Nothing queued yet. Use Add on a recipe.")

    -- materials
    local mats, sum = S.Materials()
    lists.mats:SetData(mats, sum.state == "empty" and "Materials for the queue appear here." or nil)
    local text, tone = S.Headline(sum)
    f.headline:SetText(text)
    Paint(f.headline, tone == "good" and K.sage or (tone == "warn" and K.gold or K.textDim))

    f.note:SetText(S.Note() or (Q.Held() and "This queue was saved by a newer TwichUI and is read-only." or ""))
    if pt then Perf.Stop(pt) end
end

local function Flush()
    scheduled = false
    if not (f and f:IsShown()) then return end
    flushes = flushes + 1
    if dirtyRead then
        dirtyRead = false
        R.Perf.Call("workshop.read", S.Observe)
    end
    Win.Render()
end

local function Schedule(kind)
    if kind == "read" then dirtyRead = true end
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
local function Build()
    L = R.Look
    K = L.pal
    local F = R.FrameLook
    local _, _, CR = F.ContentInsets()
    f = CreateFrame("Frame", NAME, UIParent)
    f:Hide()
    f:SetSize(WIDTH, HEIGHT)
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
        if kind then Schedule(kind) end
    end)
    f:HookScript("OnShow", function(self)
        token = token + 1
        scheduled, dirtyRead = false, false
        R.FitToScreen(self)
        for event in pairs(EVENTS) do self:RegisterEvent(event) end
        R.Perf.Call("workshop.read", S.Observe)   -- fresh before anything is shown as ready
        Win.Render()
    end)
    f:HookScript("OnHide", function(self)
        token = token + 1
        scheduled, dirtyRead = false, false
        self:UnregisterAllEvents()
        S.Reset()
        Q.Unload()
    end)
    f.shell = F.Shell(f, { below = true, follow = true })
    F.FadeIn(f)
    f.head = f.shell:Header(40)
    local title = L.Text(f, "title")
    title:SetPoint("TOPLEFT", PAD, -13)
    title:SetText("Workshop")
    f.close = F.Close(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -(CR + 2), -13)

    -- left: recipes
    local rh = L.Text(f, "heading")
    rh:SetPoint("TOPLEFT", PAD, -52)
    rh:SetText("Recipes")
    local box = L.EditBox(f, LEFT_W, 22)
    box:SetPoint("TOPLEFT", PAD, -100)
    box:SetMaxLetters(40)
    box.hint = L.Text(box, "meta")
    box.hint:SetPoint("LEFT", 8, 0)
    box.hint:SetText("Search recipes")
    box:HookScript("OnTextChanged", function(self)
        self.hint:SetShown(self:GetText() == "")
        S.SetFilter(self:GetText())
        lists.recipes:ScrollTop()
        Win.Render()
    end)
    f.search = box
    f.notice = L.Text(f, "small")
    f.notice:SetPoint("TOPLEFT", PAD, -128)
    f.notice:SetWidth(LEFT_W)
    f.notice:SetWordWrap(true)
    f.notice:SetJustifyV("TOP")
    lists.recipes = NewList(f, PAD, -176, LEFT_W, HEIGHT - 176 - 52, REC_H, MakeRecipeRow)

    -- right: queue
    local qh = L.Text(f, "heading")
    qh:SetPoint("TOPLEFT", RIGHT_X, -52)
    qh:SetText("Queue")
    f.queueCount = L.Text(f, "meta")
    f.queueCount:SetPoint("LEFT", qh, "RIGHT", 10, 0)
    lists.queue = NewList(f, RIGHT_X, -74, RIGHT_W, 250, QUE_H, MakeQueueRow)

    -- right: materials
    local mh = L.Text(f, "heading")
    mh:SetPoint("TOPLEFT", RIGHT_X, -338)
    mh:SetText("Materials")
    local scope = L.Text(f, "meta")
    scope:SetPoint("LEFT", mh, "RIGHT", 10, 0)
    scope:SetText("Counts what is in your bags only.")
    local function Head(text, anchorX, w)
        local h = L.Text(f, "meta")
        h:SetPoint("TOPRIGHT", f, "TOPLEFT", anchorX, -362)
        h:SetWidth(w)
        h:SetJustifyH("RIGHT")
        h:SetText(text)
    end
    local colRight = RIGHT_X + RIGHT_W - 22 - 6 - 6
    Head("Still needed", colRight, 78)
    Head("In bags", colRight - 78 - 10, 52)
    Head("Need", colRight - 78 - 10 - 52 - 10, 52)
    lists.mats = NewList(f, RIGHT_X, -380, RIGHT_W, 150, MAT_H, MakeMaterialRow)
    f.headline = L.Text(f, "body")
    f.headline:SetPoint("TOPLEFT", RIGHT_X, -540)
    f.headline:SetWidth(RIGHT_W)
    f.headline:SetWordWrap(true)
    f.headline:SetJustifyV("TOP")

    f.note = L.Text(f, "meta")
    f.note:SetPoint("BOTTOMLEFT", PAD, 22)
    f.note:SetWidth(WIDTH - PAD * 2)
    f.note:SetWordWrap(false)
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
function Win.Lists() return lists end

-- For the diagnostics gauges and the tests. Read only.
function W.Snapshot()
    local s = S.Snapshot()
    local events = 0
    if f and f:IsShown() then for _ in pairs(EVENTS) do events = events + 1 end end
    local rows = 0
    for _, l in pairs(lists) do rows = rows + #l.rows end
    s.shown = f ~= nil and f:IsShown() or false
    s.built = f ~= nil
    s.events = events
    s.rows = rows
    s.renders = renders
    s.flushes = flushes
    return s
end

W.Open = Win.Show
W.Toggle = Win.Toggle
W.ready = true
